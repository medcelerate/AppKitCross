// Win32 backend: process-wide state, the message loop, displays and DPI.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CD2D

@MainActor
final class Win32Backend: PlatformBackend {
    static let windowClassName = "AppKitCross.NSWindow"
    static let messageWindowClassName = "AppKitCross.MessageWindow"
    static let postMessage = UINT(WM_APP) + 1

    let hInstance: HINSTANCE? = GetModuleHandleW(nil)
    private(set) var d2dFactory: OpaquePointer?     // CD2DFactory*
    private var messageWindow: HWND?
    private var posted: [@MainActor () -> Void] = []
    private var running = false
    private var classesRegistered = false
    /// CoreText over the seam (ADR-0007). APPKITWIN_LEGACY_TEXT=1 keeps the DirectWrite
    /// string backend (IDWriteTextLayout drawn by Direct2D) for comparison.
    let text: any PlatformTextBackend = ProcessInfo.processInfo.environment["APPKITWIN_LEGACY_TEXT"] == "1"
        ? Win32TextBackend() as any PlatformTextBackend : HostTextBackend()
    let image: any PlatformImageBackend = Win32ImageBackend()
    let menuBar = Win32MenuBar()
    private(set) var windows: [Win32Window] = []
    /// OLE drag and drop (Win32DragDrop.swift).
    private(set) var win32DragDrop: Win32DragDrop!
    var dragDrop: (any PlatformDragDrop)? { win32DragDrop }
    /// The notification area (Win32StatusItem.swift).
    private(set) var win32StatusItems: Win32StatusItems?
    var statusItems: (any PlatformStatusItemHost)? { win32StatusItems }
    /// Printing (Win32Printing.swift): the PDF writer, print jobs through Direct2D's print
    /// control, the PrintDlgEx dialog.
    private(set) lazy var win32Printing = Win32PrintBackend(backend: self)
    var printing: (any PlatformPrintBackend)? { win32Printing }

    func setMainMenu(_ menu: PlatformMenu?, host: PlatformMenuHost?) {
        menuBar.install(menu, host: host, on: windows.compactMap { $0.wantsMenuBar ? $0.hwnd : nil })
    }

    func register(_ window: Win32Window) {
        windows.append(window)
        if let hwnd = window.hwnd, window.wantsMenuBar { menuBar.apply(to: hwnd) }
    }

    func unregister(_ window: Win32Window) {
        windows.removeAll { $0 === window }
    }

    init() {
        // Per-monitor v2 DPI awareness; the manifest can set this too, in which case the
        // call simply fails and we keep the manifest's choice.
        _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
        d2dFactory = cd2d_factory_create()
        registerClasses()
        createMessageWindow()
        win32DragDrop = Win32DragDrop(backend: self)
        if let hwnd = messageWindow { win32StatusItems = Win32StatusItems(backend: self, hwnd: hwnd) }
    }

    // MARK: Nested loops owned by the system

    private static let dragTimer: UINT_PTR = 1

    /// While OLE runs a drag it pumps messages itself, so the frame clock and the main
    /// queue are serviced from a timer on the message window instead of `pump()`.
    func beginNestedDrag() {
        if let hwnd = messageWindow { _ = SetTimer(hwnd, Win32Backend.dragTimer, 16, nil) }
    }

    func endNestedDrag() {
        if let hwnd = messageWindow { _ = KillTimer(hwnd, Win32Backend.dragTimer) }
    }

    /// One pass of what `pump()` does between messages, for loops the system owns.
    func serviceWhileNested() {
        drainPosted()
        fireFrameIfDue()
        _ = PlatformMainQueue.service()
    }

    // MARK: Displays

    /// One monitor as the core sees it: its rects in points at its own effective DPI
    /// (per-monitor-v2 awareness gives every monitor its own scale), its device name,
    /// and whether it is the primary.
    static func display(for hMonitor: HMONITOR?, primaryHeight: Int32) -> PlatformDisplay? {
        guard let hMonitor else { return nil }
        var info = MONITORINFOEXW()
        info.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)
        let ok = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: MONITORINFO.self, capacity: 1) { GetMonitorInfoW(hMonitor, $0) }
        }
        guard ok else { return nil }
        var dpiX: UINT = 96, dpiY: UINT = 96
        _ = GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
        let scale = CGFloat(dpiX) / 96
        let name = withUnsafePointer(to: &info.szDevice) { p -> String in
            p.withMemoryRebound(to: WCHAR.self, capacity: 32) { String(decodingCString: $0, as: UTF16.self) }
        }
        let edr = extendedDynamicRange(for: hMonitor)
        return PlatformDisplay(
            frame: appKitRect(info.rcMonitor, scale: scale, primaryHeight: primaryHeight),
            visibleFrame: appKitRect(info.rcWork, scale: scale, primaryHeight: primaryHeight),
            backingScaleFactor: scale, localizedName: name,
            isMain: (info.dwFlags & DWORD(MONITORINFOF_PRIMARY)) != 0,
            maximumEDRValue: edr.current, maximumPotentialEDRValue: edr.potential, maximumReferenceEDRValue: 0)
    }

    /// What the monitor reports about HDR (DXGI output description, SDR white level and
    /// advanced-colour state through the shim; cached there for a second).
    static func displayHDR(for hMonitor: HMONITOR?) -> CD2DDisplayHDR {
        var info = CD2DDisplayHDR()
        _ = cd2d_display_hdr_info(hMonitor.map { UnsafeMutableRawPointer($0) }, &info)
        return info
    }

    /// `NSScreen`'s EDR headroom: colour component 1.0 is the SDR white level, so the
    /// headroom is the panel's peak luminance over that level while HDR is on (1 while
    /// it is off: nothing brighter than white can be shown), and what it would be with
    /// HDR on for a monitor that supports it. Windows has no reference modes.
    static func extendedDynamicRange(for hMonitor: HMONITOR) -> (current: CGFloat, potential: CGFloat) {
        let hdr = displayHDR(for: hMonitor)
        let white = hdr.sdrWhiteNits > 0 ? CGFloat(hdr.sdrWhiteNits) : 80
        let headroom = max(1, CGFloat(hdr.maxLuminance) / white)
        return (hdr.hdr ? headroom : 1, hdr.advancedColorSupported || hdr.hdr ? headroom : 1)
    }

    var displays: [PlatformDisplay] {
        var result: [PlatformDisplay] = []
        let primaryHeight = Win32Backend.primaryHeightPixels
        let callback: MONITORENUMPROC = { hMonitor, _, _, lParam in
            let list = Unmanaged<DisplayList>.fromOpaque(UnsafeRawPointer(bitPattern: Int(lParam))!).takeUnretainedValue()
            if let d = Win32Backend.display(for: hMonitor, primaryHeight: list.primaryHeight) { list.items.append(d) }
            return true
        }
        let list = DisplayList(primaryHeight: primaryHeight)
        let unmanaged = Unmanaged.passUnretained(list)
        _ = EnumDisplayMonitors(nil, nil, callback, LPARAM(Int(bitPattern: unmanaged.toOpaque())))
        result = list.items
        if result.isEmpty {
            result = [PlatformDisplay(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1040),
                                      backingScaleFactor: 1, localizedName: "Display", isMain: true)]
        }
        return result
    }

    private final class DisplayList {
        var items: [PlatformDisplay] = []
        let primaryHeight: Int32
        init(primaryHeight: Int32) { self.primaryHeight = primaryHeight }
    }

    /// Height of the primary monitor in physical pixels: the AppKit y axis is flipped
    /// against it.
    static var primaryHeightPixels: Int32 { GetSystemMetrics(SM_CYSCREEN) }

    /// Converts a physical-pixel RECT into AppKit screen points (bottom-left origin).
    static func appKitRect(_ r: RECT, scale: CGFloat, primaryHeight: Int32) -> NSRect {
        let x = CGFloat(r.left) / scale
        let w = CGFloat(r.right - r.left) / scale
        let h = CGFloat(r.bottom - r.top) / scale
        let y = CGFloat(primaryHeight - r.bottom) / scale
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// Converts an AppKit screen rect (points) into a physical-pixel RECT.
    static func win32Rect(_ r: NSRect, scale: CGFloat, primaryHeight: Int32) -> RECT {
        let left = Int32((r.minX * scale).rounded())
        let top = primaryHeight - Int32((r.maxY * scale).rounded())
        let right = Int32((r.maxX * scale).rounded())
        let bottom = primaryHeight - Int32((r.minY * scale).rounded())
        return RECT(left: left, top: top, right: right, bottom: bottom)
    }

    var mouseLocation: NSPoint {
        var pt = POINT()
        GetCursorPos(&pt)
        let scale = CGFloat(GetDpiForSystem()) / 96
        return NSPoint(x: CGFloat(pt.x) / scale, y: CGFloat(Win32Backend.primaryHeightPixels - pt.y) / scale)
    }

    // MARK: Windows

    func makeWindow(owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) -> PlatformWindow {
        Win32Window(backend: self, owner: owner, contentRect: contentRect, styleMask: styleMask)
    }

    static func styles(for mask: NSWindow.StyleMask) -> (DWORD, DWORD) {
        var style: DWORD = 0
        var ex: DWORD = DWORD(WS_EX_APPWINDOW)
        if mask.contains(.titled) {
            style |= DWORD(WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_CLIPCHILDREN)
            if mask.contains(.miniaturizable) { style |= DWORD(WS_MINIMIZEBOX) }
            if mask.contains(.resizable) { style |= DWORD(WS_THICKFRAME | WS_MAXIMIZEBOX) }
        } else {
            style |= DWORD(WS_POPUP) | DWORD(WS_CLIPCHILDREN)
            if mask.contains(.resizable) { style |= DWORD(WS_THICKFRAME) }
        }
        if mask.contains(.utilityWindow) { ex |= DWORD(WS_EX_TOOLWINDOW) }
        if mask.contains(.nonactivatingPanel) {
            // Menus and other pop-ups: no taskbar entry, never activated, above the owner.
            ex = (ex & ~DWORD(WS_EX_APPWINDOW)) | DWORD(WS_EX_TOOLWINDOW) | DWORD(WS_EX_NOACTIVATE) | DWORD(WS_EX_TOPMOST)
        }
        return (style, ex)
    }

    /// Whether windows with this style mask draw their content over the whole window
    /// (Milestone 3b): `fullSizeContentView`, or borderless. Such windows handle
    /// WM_NCCALCSIZE so the client area is the window rect, and their frame equals their
    /// content rect, as on macOS.
    static func usesCustomFrame(_ mask: NSWindow.StyleMask) -> Bool {
        mask.contains(.fullSizeContentView) || !mask.contains(.titled)
    }

    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
        if Win32Backend.usesCustomFrame(styleMask) { return contentRect }
        let (style, ex) = Win32Backend.styles(for: styleMask)
        let dpi = GetDpiForSystem()
        let scale = CGFloat(dpi) / 96
        var r = RECT(left: 0, top: 0, right: Int32((contentRect.width * scale).rounded()), bottom: Int32((contentRect.height * scale).rounded()))
        _ = AdjustWindowRectExForDpi(&r, style, false, ex, dpi)
        let extraW = CGFloat(r.right - r.left) / scale - contentRect.width
        let extraH = CGFloat(r.bottom - r.top) / scale - contentRect.height
        let leftInset = CGFloat(-r.left) / scale
        let bottomInset = CGFloat(r.bottom) / scale - contentRect.height
        return NSRect(x: contentRect.minX - leftInset, y: contentRect.minY - bottomInset, width: contentRect.width + extraW, height: contentRect.height + extraH)
    }

    func contentRect(forFrameRect frameRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
        if Win32Backend.usesCustomFrame(styleMask) { return frameRect }
        let (style, ex) = Win32Backend.styles(for: styleMask)
        let dpi = GetDpiForSystem()
        let scale = CGFloat(dpi) / 96
        var r = RECT(left: 0, top: 0, right: 100, bottom: 100)
        _ = AdjustWindowRectExForDpi(&r, style, false, ex, dpi)
        let leftInset = CGFloat(-r.left) / scale, rightInset = CGFloat(r.right - 100) / scale
        let topInset = CGFloat(-r.top) / scale, bottomInset = CGFloat(r.bottom - 100) / scale
        return NSRect(x: frameRect.minX + leftInset, y: frameRect.minY + bottomInset,
                      width: max(0, frameRect.width - leftInset - rightInset), height: max(0, frameRect.height - topInset - bottomInset))
    }

    // MARK: Event loop

    func run() {
        running = true
        while running {
            if !pump() { break }
        }
        running = false
    }

    func stop() {
        running = false
        PostQuitMessage(0)
    }

    /// Dispatches every queued message, fires the animation frame when its deadline has
    /// passed, then blocks until the next message or the deadline. Returns false on WM_QUIT
    /// (left in the queue for an outer loop).
    ///
    /// Frames are driven by a deadline checked here rather than by WM_TIMER: Windows only
    /// synthesises WM_TIMER (and WM_PAINT) when the queue is otherwise empty, so a window
    /// that repaints every frame would starve the timer and animations would never advance.
    private func pump() -> Bool {
        var msg = MSG()
        while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
            if msg.message == UINT(WM_QUIT) {
                PostQuitMessage(Int32(truncatingIfNeeded: msg.wParam))
                return false
            }
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
            fireFrameIfDue()
        }
        fireFrameIfDue()
        // Blocks queued on the main queue from other threads, and RunLoop timers.
        let serviceStart = GetTickCount64()
        let nextTimer = PlatformMainQueue.service()
        serviceMs += GetTickCount64() - serviceStart
        var timeout: DWORD
        if let deadline = frameDeadline {
            let now = GetTickCount64()
            timeout = deadline > now ? DWORD(min(deadline - now, 1000)) : 0
        } else {
            timeout = INFINITE
        }
        if let t = nextTimer { timeout = min(timeout, DWORD(min(t * 1000, 60_000))) }
        pumpIterations += 1
        if NSView._traceInvalidation {
            let now = GetTickCount64()
            if now - pumpTraceStart >= 1000 {
                NSView._trace("pump \(pumpIterations) iterations in \(now - pumpTraceStart) ms, wait \(timeout == INFINITE ? "infinite" : "\(timeout) ms") (frame deadline \(frameDeadline.map { "\(Int64($0) - Int64(now)) ms" } ?? "none"), timer \(nextTimer.map { "\($0) s" } ?? "none")); wakes: queue \(wakesQueue) input \(wakesInput) timeout \(wakesTimeout); service \(serviceMs) ms")
                pumpIterations = 0
                wakesQueue = 0; wakesInput = 0; wakesTimeout = 0; serviceMs = 0
                pumpTraceStart = now
            }
        }
        if let handle = PlatformMainQueue.handle {
            var handles: [HANDLE?] = [handle]
            let r = MsgWaitForMultipleObjectsEx(1, &handles, timeout, DWORD(QS_ALLINPUT), DWORD(MWMO_INPUTAVAILABLE))
            if r == WAIT_OBJECT_0 { wakesQueue += 1; PlatformMainQueue.service() }
            else if r == WAIT_OBJECT_0 + 1 { wakesInput += 1 }
            else { wakesTimeout += 1 }
        } else {
            let r = MsgWaitForMultipleObjectsEx(0, nil, timeout, DWORD(QS_ALLINPUT), DWORD(MWMO_INPUTAVAILABLE))
            if r == WAIT_OBJECT_0 { wakesInput += 1 } else { wakesTimeout += 1 }
        }
        return true
    }
    private var wakesQueue = 0, wakesInput = 0, wakesTimeout = 0
    private var serviceMs: UInt64 = 0
    private var pumpIterations = 0
    private var pumpTraceStart: UInt64 = GetTickCount64()

    private var frameCallback: (@MainActor () -> Void)?
    private var frameDeadline: UInt64?          // GetTickCount64 milliseconds

    /// Schedules one frame about 16 ms from now; `pump()` fires it.
    func scheduleFrame(_ callback: @escaping @MainActor () -> Void) {
        frameCallback = callback
        if frameDeadline == nil { frameDeadline = GetTickCount64() + 16 }
        if NSView._traceInvalidation { NSView._trace("win32 scheduleFrame deadline in \(Int64(frameDeadline!) - Int64(GetTickCount64())) ms") }
    }

    func fireFrameIfDue() {
        guard let deadline = frameDeadline, GetTickCount64() >= deadline else { return }
        if NSView._traceInvalidation { NSView._trace("win32 fireFrame") }
        frameDeadline = nil
        let cb = frameCallback
        frameCallback = nil
        cb?()
    }

    func post(_ block: @escaping @MainActor () -> Void) {
        posted.append(block)
        if let hwnd = messageWindow { PostMessageW(hwnd, Win32Backend.postMessage, 0, 0) }
    }

    fileprivate func drainPosted() {
        while !posted.isEmpty {
            let blocks = posted
            posted.removeAll()
            for b in blocks { b() }
        }
    }

    func beep() { MessageBeep(UINT(MB_OK)) }
    var systemAppearanceIsDark: Bool { Win32Window.systemAppThemeIsDark() }

    // MARK: File dialogs

    /// IFileOpenDialog / IFileSaveDialog through the CD2D shim (ADR-0017).
    private lazy var win32FileDialog = Win32FileDialog()
    var fileDialog: (any PlatformFileDialog)? { PlatformFileDialogPolicy.allowsNative ? win32FileDialog : nil }

    // MARK: Pasteboard and modal loops

    let systemPasteboard: any PlatformPasteboard = Win32Pasteboard()

    func runModal(for window: PlatformWindow?, until stop: @escaping @MainActor () -> Bool) {
        let modal = (window as? Win32Window)?.hwnd
        let others = windows.compactMap { $0.hwnd }.filter { $0 != modal }
        for h in others { EnableWindow(h, false) }
        while !stop() {
            if !pump() { break }
        }
        for h in others { EnableWindow(h, true) }
        if let modal { SetActiveWindow(modal) }
    }

    func runNested(until stop: @escaping @MainActor () -> Bool) {
        while !stop() {
            if !pump() { break }
        }
    }

    // MARK: Cursor

    private(set) var currentCursor: HCURSOR? = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
    private var customCursor: HCURSOR? = nil
    private var cursorHiddenDepth = 0

    private static func systemCursor(_ id: Int) -> HCURSOR? { LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: id)) }

    func setCursor(_ cursor: PlatformCursor) {
        let h: HCURSOR?
        switch cursor {
        case .arrow, .openHand, .closedHand, .dragCopy, .dragLink, .contextualMenu: h = Win32Backend.systemCursor(32512)   // IDC_ARROW
        case .iBeam, .iBeamVertical: h = Win32Backend.systemCursor(32513)          // IDC_IBEAM
        case .wait: h = Win32Backend.systemCursor(32514)                            // IDC_WAIT
        case .crosshair: h = Win32Backend.systemCursor(32515)                       // IDC_CROSS
        case .resizeAll: h = Win32Backend.systemCursor(32646)                       // IDC_SIZEALL
        case .resizeLeftRight: h = Win32Backend.systemCursor(32644)                 // IDC_SIZEWE
        case .resizeUpDown: h = Win32Backend.systemCursor(32645)                    // IDC_SIZENS
        case .operationNotAllowed: h = Win32Backend.systemCursor(32648)             // IDC_NO
        case .pointingHand: h = Win32Backend.systemCursor(32649)                    // IDC_HAND
        case let .custom(width, height, hotX, hotY, pixels):
            if let old = customCursor { DestroyIcon(old); customCursor = nil }
            h = makeCursor(width: width, height: height, hotSpot: (hotX, hotY), bgra: pixels) ?? Win32Backend.systemCursor(32512)
            customCursor = h
        }
        currentCursor = h
        SetCursor(h)
    }

    func setCursorHidden(_ hidden: Bool) {
        if hidden { cursorHiddenDepth += 1; ShowCursor(false) } else if cursorHiddenDepth > 0 { cursorHiddenDepth -= 1; ShowCursor(true) }
    }

    /// Builds a color cursor (an icon with a hot spot) from premultiplied BGRA pixels.
    private func makeCursor(width: Int, height: Int, hotSpot: (Int, Int), bgra: [UInt8]) -> HCURSOR? {
        Win32Backend.makeIconHandle(width: width, height: height, hotSpot: hotSpot, isIcon: false, bgra: bgra)
    }

    /// An HICON/HCURSOR with alpha from premultiplied BGRA pixels (top-down rows): a
    /// 32-bit DIB section as the colour plane, as the icon APIs document. Status items
    /// (Win32StatusItem) and cursors share it.
    static func makeIconHandle(width: Int, height: Int, hotSpot: (Int, Int), isIcon: Bool, bgra: [UInt8]) -> HICON? {
        guard width > 0, height > 0, bgra.count >= width * height * 4 else { return nil }
        var bi = BITMAPV5HEADER()
        bi.bV5Size = DWORD(MemoryLayout<BITMAPV5HEADER>.size)
        bi.bV5Width = Int32(width)
        bi.bV5Height = -Int32(height)      // top-down
        bi.bV5Planes = 1
        bi.bV5BitCount = 32
        bi.bV5Compression = DWORD(BI_BITFIELDS)
        bi.bV5RedMask = 0x00FF0000; bi.bV5GreenMask = 0x0000FF00; bi.bV5BlueMask = 0x000000FF; bi.bV5AlphaMask = 0xFF000000
        let dc = GetDC(nil)
        defer { ReleaseDC(nil, dc) }
        var bits: UnsafeMutableRawPointer? = nil
        let color = withUnsafePointer(to: &bi) { p -> HBITMAP? in
            p.withMemoryRebound(to: BITMAPINFO.self, capacity: 1) { CreateDIBSection(dc, $0, UINT(DIB_RGB_COLORS), &bits, nil, 0) }
        }
        guard let color, let bits else { return nil }
        bgra.withUnsafeBytes { src in bits.copyMemory(from: src.baseAddress!, byteCount: width * height * 4) }
        let mask = CreateBitmap(Int32(width), Int32(height), 1, 1, nil)
        var info = ICONINFO()
        info.fIcon = WindowsBool(isIcon)
        info.xHotspot = DWORD(hotSpot.0)
        info.yHotspot = DWORD(hotSpot.1)
        info.hbmMask = mask
        info.hbmColor = color
        let cursor = CreateIconIndirect(&info)
        DeleteObject(color)
        DeleteObject(mask)
        return cursor
    }

    // MARK: Window classes

    private func registerClasses() {
        guard !classesRegistered else { return }
        classesRegistered = true
        Win32Backend.windowClassName.withCString(encodedAs: UTF16.self) { name in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.style = UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS)
            wc.lpfnWndProc = Win32Window.windowProc
            wc.hInstance = hInstance
            wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))   // IDC_ARROW
            wc.hbrBackground = nil
            wc.lpszClassName = name
            _ = RegisterClassExW(&wc)
        }
        Win32Backend.messageWindowClassName.withCString(encodedAs: UTF16.self) { name in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.lpfnWndProc = Win32Backend.messageProc
            wc.hInstance = hInstance
            wc.lpszClassName = name
            _ = RegisterClassExW(&wc)
        }
    }

    private func createMessageWindow() {
        messageWindow = Win32Backend.messageWindowClassName.withCString(encodedAs: UTF16.self) { name in
            CreateWindowExW(0, name, name, 0, 0, 0, 0, 0, HWND(bitPattern: -3) /* HWND_MESSAGE */, nil, hInstance, nil)
        }
        if let hwnd = messageWindow {
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())))
        }
    }

    private static let messageProc: WNDPROC = { hwnd, msg, wParam, lParam in
        if msg == UINT(WM_TIMER), wParam == Win32Backend.dragTimer {
            let ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
            if ptr != 0 {
                let backend = Unmanaged<Win32Backend>.fromOpaque(UnsafeRawPointer(bitPattern: Int(ptr))!).takeUnretainedValue()
                MainActor.assumeIsolated { backend.serviceWhileNested() }
            }
            return 0
        }
        if msg == Win32StatusItems.callbackMessage || msg == Win32StatusItems.taskbarCreated || msg == UINT(WM_KILLFOCUS) {
            let ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
            if ptr != 0 {
                let backend = Unmanaged<Win32Backend>.fromOpaque(UnsafeRawPointer(bitPattern: Int(ptr))!).takeUnretainedValue()
                MainActor.assumeIsolated {
                    if msg == UINT(WM_KILLFOCUS) { backend.win32StatusItems?.foregroundLost() }
                    else { backend.win32StatusItems?.handle(message: msg, wParam: wParam, lParam: lParam) }
                }
            }
            return 0
        }
        if msg == Win32Backend.postMessage {
            let ptr = SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0)
            if ptr != 0 {
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, ptr)
                let backend = Unmanaged<Win32Backend>.fromOpaque(UnsafeRawPointer(bitPattern: Int(ptr))!).takeUnretainedValue()
                MainActor.assumeIsolated { backend.drainPosted() }
            }
            return 0
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }
}
#endif

/// The Windows common item dialog (`IFileOpenDialog` / `IFileSaveDialog`), shown by the
/// CD2D shim. Type filters come from the allowed extensions; the dialog is modal to the
/// parent HWND while the shim pumps messages.
@MainActor
final class Win32FileDialog: PlatformFileDialog {
    func run(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]? {
        var o = CD2DFileDialogOptions()
        o.isSave = options.isSave
        o.canChooseFiles = options.canChooseFiles
        o.canChooseDirectories = options.canChooseDirectories
        o.allowsMultiple = options.allowsMultipleSelection
        o.allowsOtherTypes = options.allowsOtherTypes
        o.showsHidden = options.showsHiddenFiles
        let title = Array((options.title ?? "").utf16) + [0]
        let prompt = Array((options.prompt ?? "").utf16) + [0]
        let name = Array((options.defaultName ?? "").utf16) + [0]
        let dir = Array((options.directory?.path.replacingOccurrences(of: "/", with: "\\") ?? "").utf16) + [0]
        // One filter group per type: extensions that share a description (a content type)
        // form a group; without descriptions every extension is one "Supported files" group.
        var groups: [(label: String, extensions: [String])] = []
        if options.allowedTypeDescriptions.count == options.allowedExtensions.count {
            for (ext, label) in zip(options.allowedExtensions, options.allowedTypeDescriptions) {
                if let i = groups.firstIndex(where: { $0.label == label }) { groups[i].extensions.append(ext) } else { groups.append((label, [ext])) }
            }
        } else if !options.allowedExtensions.isEmpty {
            groups = [("", options.allowedExtensions)]
        }
        let exts = Array(groups.map { $0.extensions.joined(separator: ";") }.joined(separator: "|").utf16) + [0]
        let labels = Array(groups.map { $0.label.replacingOccurrences(of: "|", with: "/") }.joined(separator: "|").utf16) + [0]
        let defaultExt = Array((options.defaultExtension ?? "").utf16) + [0]
        if ProcessInfo.processInfo.environment["APPKITWIN_FILE_DIALOG_TRACE"] != nil {
            FileHandle.standardError.write(Data("[file-dialog] swift: name=\"\(options.defaultName ?? "")\" defaultExtension=\"\(options.defaultExtension ?? "")\" groups=\(groups)\n".utf8))
        }
        var out: UnsafeMutablePointer<UInt16>? = nil
        var outLen: UInt32 = 0
        let hwnd = (parent as? Win32Window)?.hwnd
        let ok = title.withUnsafeBufferPointer { t in prompt.withUnsafeBufferPointer { p in name.withUnsafeBufferPointer { n in dir.withUnsafeBufferPointer { d in exts.withUnsafeBufferPointer { e in labels.withUnsafeBufferPointer { l in defaultExt.withUnsafeBufferPointer { x in
            cd2d_file_dialog(hwnd.map { UnsafeMutableRawPointer($0) }, &o, t.baseAddress, p.baseAddress, n.baseAddress, d.baseAddress, e.baseAddress, l.baseAddress, x.baseAddress, &out, &outLen)
        } } } } } } }
        guard ok, let out else { return nil }
        defer { cd2d_file_dialog_free(out) }
        // Paths are NUL-separated, double NUL terminated.
        let all = String(decoding: UnsafeBufferPointer(start: out, count: Int(outLen)), as: UTF16.self)
        return all.split(separator: "\u{0}", omittingEmptySubsequences: true).map { URL(fileURLWithPath: String($0).replacingOccurrences(of: "\\", with: "/")) }
    }
}
