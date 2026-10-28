// Win32 backend: process-wide state, the message loop, displays and DPI.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CD2D

@MainActor
final class Win32Backend: PlatformBackend {
    static let windowClassName = "AppKitWin.NSWindow"
    static let messageWindowClassName = "AppKitWin.MessageWindow"
    static let postMessage = UINT(WM_APP) + 1

    let hInstance: HINSTANCE? = GetModuleHandleW(nil)
    private(set) var d2dFactory: OpaquePointer?     // CD2DFactory*
    private var messageWindow: HWND?
    private var posted: [@MainActor () -> Void] = []
    private var running = false
    private var classesRegistered = false
    let text: any PlatformTextBackend = Win32TextBackend()
    let image: any PlatformImageBackend = Win32ImageBackend()
    let menuBar = Win32MenuBar()
    private(set) var windows: [Win32Window] = []

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
    }

    // MARK: Displays

    var displays: [PlatformDisplay] {
        var result: [PlatformDisplay] = []
        let primaryHeight = Win32Backend.primaryHeightPixels
        let callback: MONITORENUMPROC = { hMonitor, _, _, lParam in
            var info = MONITORINFOEXW()
            info.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)
            withUnsafeMutablePointer(to: &info) { p in
                p.withMemoryRebound(to: MONITORINFO.self, capacity: 1) { _ = GetMonitorInfoW(hMonitor, $0) }
            }
            var dpiX: UINT = 96, dpiY: UINT = 96
            _ = GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
            let scale = CGFloat(dpiX) / 96
            let list = Unmanaged<DisplayList>.fromOpaque(UnsafeRawPointer(bitPattern: Int(lParam))!).takeUnretainedValue()
            let name = withUnsafePointer(to: &info.szDevice) { p -> String in
                p.withMemoryRebound(to: WCHAR.self, capacity: 32) { String(decodingCString: $0, as: UTF16.self) }
            }
            list.items.append(PlatformDisplay(
                frame: Win32Backend.appKitRect(info.rcMonitor, scale: scale, primaryHeight: list.primaryHeight),
                visibleFrame: Win32Backend.appKitRect(info.rcWork, scale: scale, primaryHeight: list.primaryHeight),
                backingScaleFactor: scale, localizedName: name,
                isMain: (info.dwFlags & DWORD(MONITORINFOF_PRIMARY)) != 0))
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
        return (style, ex)
    }

    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
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
        var msg = MSG()
        while running {
            // The overlay imports BOOL as Bool: WM_QUIT (0) and errors (-1) both end the loop.
            if !GetMessageW(&msg, nil, 0, 0) { break }
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }
        running = false
    }

    func stop() {
        running = false
        PostQuitMessage(0)
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

    // MARK: File dialogs

    func runFileDialog(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]? {
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
        let exts = Array(options.allowedExtensions.joined(separator: ";").utf16) + [0]
        var out: UnsafeMutablePointer<UInt16>? = nil
        var outLen: UInt32 = 0
        let hwnd = (parent as? Win32Window)?.hwnd
        let ok = title.withUnsafeBufferPointer { t in prompt.withUnsafeBufferPointer { p in name.withUnsafeBufferPointer { n in dir.withUnsafeBufferPointer { d in exts.withUnsafeBufferPointer { e in
            cd2d_file_dialog(hwnd.map { UnsafeMutableRawPointer($0) }, &o, t.baseAddress, p.baseAddress, n.baseAddress, d.baseAddress, e.baseAddress, &out, &outLen)
        } } } } }
        guard ok, let out else { return nil }
        defer { cd2d_file_dialog_free(out) }
        // Paths are NUL-separated, double NUL terminated.
        let all = String(decoding: UnsafeBufferPointer(start: out, count: Int(outLen)), as: UTF16.self)
        return all.split(separator: "\u{0}", omittingEmptySubsequences: true).map { URL(fileURLWithPath: String($0).replacingOccurrences(of: "\\", with: "/")) }
    }

    // MARK: Pasteboard and modal loops

    let systemPasteboard: any PlatformPasteboard = Win32Pasteboard()

    func runModal(for window: PlatformWindow?, until stop: @escaping @MainActor () -> Bool) {
        let modal = (window as? Win32Window)?.hwnd
        let others = windows.compactMap { $0.hwnd }.filter { $0 != modal }
        for h in others { EnableWindow(h, false) }
        var msg = MSG()
        while !stop() {
            if !GetMessageW(&msg, nil, 0, 0) { PostQuitMessage(Int32(msg.wParam)); break }
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
            drainPosted()
        }
        for h in others { EnableWindow(h, true) }
        if let modal { SetActiveWindow(modal) }
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
        guard bgra.count >= width * height * 4 else { return nil }
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
        info.fIcon = false
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
