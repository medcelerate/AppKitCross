// Win32 backend: process-wide state, the message loop, displays and DPI.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics

@MainActor
final class Win32Backend: PlatformBackend {
    static let windowClassName = "AppKitWin.NSWindow"
    static let messageWindowClassName = "AppKitWin.MessageWindow"
    static let postMessage = UINT(WM_APP) + 1

    let hInstance: HINSTANCE? = GetModuleHandleW(nil)
    private(set) var d2dFactory: UnsafeMutablePointer<ID2D1Factory>?
    private var messageWindow: HWND?
    private var posted: [@MainActor () -> Void] = []
    private var running = false
    private var classesRegistered = false

    init() {
        // Per-monitor v2 DPI awareness; the manifest can set this too, in which case the
        // call simply fails and we keep the manifest's choice.
        _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
        var iid = IID.d2d1FactoryForBackend
        var raw: UnsafeMutableRawPointer?
        let hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &iid, nil, &raw)
        if hr >= 0, let raw { d2dFactory = raw.assumingMemoryBound(to: ID2D1Factory.self) }
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
            style |= DWORD(WS_POPUP | WS_CLIPCHILDREN)
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
            let r = GetMessageW(&msg, nil, 0, 0)
            if r == 0 || r == -1 { break }
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
            wc.hCursor = LoadCursorW(nil, IDC_ARROW)
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
            CreateWindowExW(0, name, name, 0, 0, 0, 0, 0, HWND_MESSAGE, nil, hInstance, nil)
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

extension IID {
    /// {06152247-6f50-465a-9245-118bfd3b6041}
    static let d2d1FactoryForBackend = IID(Data1: 0x0615_2247, Data2: 0x6f50, Data3: 0x465a,
                                           Data4: (0x92, 0x45, 0x11, 0x8b, 0xfd, 0x3b, 0x60, 0x41))
}
#endif
