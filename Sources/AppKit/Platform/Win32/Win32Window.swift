// A native HWND backing an NSWindow, painted with Direct2D.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CD2D

@MainActor
final class Win32Window: PlatformWindow {
    private unowned let backend: Win32Backend
    private weak var owner: PlatformWindowOwner?
    private(set) var hwnd: HWND?
    private var renderTarget: OpaquePointer?        // CD2DTarget*
    private var _styleMask: NSWindow.StyleMask
    private var _title = ""
    private(set) var isKey = false
    private var destroying = false
    private var pressedButtons = 0
    private var dpi: UINT = 96
    var minSize = NSSize(width: 0, height: 0)
    var maxSize = NSSize(width: 100_000, height: 100_000)

    init(backend: Win32Backend, owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) {
        self.backend = backend
        self.owner = owner
        self._styleMask = styleMask
        let (style, ex) = Win32Backend.styles(for: styleMask)
        let frame = backend.frameRect(forContentRect: contentRect, styleMask: styleMask)
        let scale = CGFloat(GetDpiForSystem()) / 96
        let r = Win32Backend.win32Rect(frame, scale: scale, primaryHeight: Win32Backend.primaryHeightPixels)
        hwnd = Win32Backend.windowClassName.withCString(encodedAs: UTF16.self) { cls in
            CreateWindowExW(ex, cls, nil, style, r.left, r.top, r.right - r.left, r.bottom - r.top, nil, nil, backend.hInstance, nil)
        }
        guard let hwnd else { return }
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())))
        dpi = GetDpiForWindow(hwnd)
    }

    private var scale: CGFloat { CGFloat(dpi) / 96 }

    // MARK: PlatformWindow

    var title: String {
        get { _title }
        set {
            _title = newValue
            guard let hwnd else { return }
            newValue.withCString(encodedAs: UTF16.self) { _ = SetWindowTextW(hwnd, $0) }
        }
    }

    var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set {
            _styleMask = newValue
            guard let hwnd else { return }
            let (style, ex) = Win32Backend.styles(for: newValue)
            SetWindowLongPtrW(hwnd, GWL_STYLE, LONG_PTR(style))
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(ex))
            SetWindowPos(hwnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED))
        }
    }

    var backingScaleFactor: CGFloat { scale }

    var isVisible: Bool { hwnd.map { IsWindowVisible($0) } ?? false }

    var frame: NSRect {
        get {
            guard let hwnd else { return .zero }
            var r = RECT()
            GetWindowRect(hwnd, &r)
            return Win32Backend.appKitRect(r, scale: scale, primaryHeight: Win32Backend.primaryHeightPixels)
        }
        set {
            guard let hwnd else { return }
            var f = newValue
            f.size.width = min(max(f.size.width, minSize.width), maxSize.width)
            f.size.height = min(max(f.size.height, minSize.height), maxSize.height)
            let r = Win32Backend.win32Rect(f, scale: scale, primaryHeight: Win32Backend.primaryHeightPixels)
            SetWindowPos(hwnd, nil, r.left, r.top, r.right - r.left, r.bottom - r.top, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        }
    }

    func frameRect(forContentRect contentRect: NSRect) -> NSRect {
        let (style, ex) = Win32Backend.styles(for: _styleMask)
        var r = RECT(left: 0, top: 0, right: Int32((contentRect.width * scale).rounded()), bottom: Int32((contentRect.height * scale).rounded()))
        _ = AdjustWindowRectExForDpi(&r, style, false, ex, dpi)
        let leftInset = CGFloat(-r.left) / scale
        let bottomInset = CGFloat(r.bottom) / scale - contentRect.height
        return NSRect(x: contentRect.minX - leftInset, y: contentRect.minY - bottomInset,
                      width: CGFloat(r.right - r.left) / scale, height: CGFloat(r.bottom - r.top) / scale)
    }

    func contentRect(forFrameRect frameRect: NSRect) -> NSRect {
        let (style, ex) = Win32Backend.styles(for: _styleMask)
        var r = RECT(left: 0, top: 0, right: 100, bottom: 100)
        _ = AdjustWindowRectExForDpi(&r, style, false, ex, dpi)
        let leftInset = CGFloat(-r.left) / scale, rightInset = CGFloat(r.right - 100) / scale
        let topInset = CGFloat(-r.top) / scale, bottomInset = CGFloat(r.bottom - 100) / scale
        return NSRect(x: frameRect.minX + leftInset, y: frameRect.minY + bottomInset,
                      width: max(0, frameRect.width - leftInset - rightInset), height: max(0, frameRect.height - topInset - bottomInset))
    }

    /// Client area size in points.
    private var contentSize: NSSize {
        guard let hwnd else { return .zero }
        var r = RECT()
        GetClientRect(hwnd, &r)
        return NSSize(width: CGFloat(r.right - r.left) / scale, height: CGFloat(r.bottom - r.top) / scale)
    }

    func show() { if let hwnd { ShowWindow(hwnd, SW_SHOWNORMAL); UpdateWindow(hwnd) } }
    func hide() { if let hwnd { ShowWindow(hwnd, SW_HIDE) } }
    func makeKey() { if let hwnd { SetForegroundWindow(hwnd); SetActiveWindow(hwnd); SetFocus(hwnd) } }
    func orderBack() { if let hwnd { SetWindowPos(hwnd, HWND(bitPattern: 1) /* HWND_BOTTOM */, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)) } }

    func close() {
        guard let hwnd, !destroying else { return }
        destroying = true
        DestroyWindow(hwnd)
    }

    func setNeedsDisplay(_ rect: NSRect?) {
        guard let hwnd else { return }
        if let rect {
            var r = clientRect(rect)
            InvalidateRect(hwnd, &r, false)
        } else {
            InvalidateRect(hwnd, nil, false)
        }
    }

    func displayIfNeeded() {
        guard let hwnd else { return }
        var r = RECT()
        if GetUpdateRect(hwnd, &r, false) { UpdateWindow(hwnd) }
    }

    func display() {
        guard let hwnd else { return }
        RedrawWindow(hwnd, nil, nil, UINT(RDW_INVALIDATE | RDW_UPDATENOW | RDW_NOERASE))
    }

    // MARK: Coordinates

    /// AppKit content coordinates (points, bottom-left) -> client pixels RECT.
    private func clientRect(_ rect: NSRect) -> RECT {
        let h = contentSize.height
        return RECT(left: Int32((rect.minX * scale).rounded(.down)),
                    top: Int32(((h - rect.maxY) * scale).rounded(.down)),
                    right: Int32((rect.maxX * scale).rounded(.up)),
                    bottom: Int32(((h - rect.minY) * scale).rounded(.up)))
    }

    /// Client pixel coordinates -> AppKit content points.
    private func contentPoint(x: Int32, y: Int32) -> NSPoint {
        let h = contentSize.height
        return NSPoint(x: CGFloat(x) / scale, y: h - CGFloat(y) / scale)
    }

    private func windowNumber() -> Int { (owner as? NSWindow)?.windowNumber ?? 0 }

    // MARK: Painting

    private func ensureRenderTarget() -> OpaquePointer? {
        if let rt = renderTarget { return rt }
        guard let hwnd, let factory = backend.d2dFactory else { return nil }
        var client = RECT()
        GetClientRect(hwnd, &client)
        let rt = cd2d_target_create_hwnd(factory, UnsafeMutableRawPointer(hwnd),
                                         UInt32(max(1, client.right - client.left)), UInt32(max(1, client.bottom - client.top)), Float(dpi))
        renderTarget = rt
        return rt
    }

    private func discardRenderTarget() {
        cd2d_target_release(renderTarget)
        renderTarget = nil
    }

    private func paint() {
        guard let hwnd else { return }
        var ps = PAINTSTRUCT()
        _ = BeginPaint(hwnd, &ps)
        defer { EndPaint(hwnd, &ps) }
        guard let rt = ensureRenderTarget(), let factory = backend.d2dFactory else { return }
        let size = contentSize
        let dirty = NSRect(x: CGFloat(ps.rcPaint.left) / scale,
                           y: size.height - CGFloat(ps.rcPaint.bottom) / scale,
                           width: CGFloat(ps.rcPaint.right - ps.rcPaint.left) / scale,
                           height: CGFloat(ps.rcPaint.bottom - ps.rcPaint.top) / scale)
        cd2d_target_begin_draw(rt)
        // Flip: CoreGraphics is bottom-left in points; Direct2D is top-left in DIPs.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        do {
            let ctx = CGContext(target: rt, factory: factory, baseTransform: flip,
                                width: Int(size.width * scale), height: Int(size.height * scale))
            owner?.platformWindowDraw(into: ctx, dirtyRect: dirty.isEmpty ? NSRect(origin: .zero, size: size) : dirty)
        }
        if !cd2d_target_end_draw(rt) { discardRenderTarget() }
    }

    // MARK: Input

    private func modifierFlags() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if GetKeyState(VK_SHIFT) < 0 { flags.insert(.shift) }
        if GetKeyState(VK_CONTROL) < 0 { flags.insert(.control) }
        if GetKeyState(VK_MENU) < 0 { flags.insert(.option) }
        if GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0 { flags.insert(.command) }
        if (GetKeyState(VK_CAPITAL) & 1) != 0 { flags.insert(.capsLock) }
        NSEvent._currentModifierFlags = flags
        return flags
    }

    private func timestamp() -> TimeInterval { TimeInterval(GetTickCount64()) / 1000 }

    private func mouse(_ type: NSEvent.EventType, _ lParam: LPARAM, button: Int, clickCount: Int = 1) {
        let x = Int32(Int16(truncatingIfNeeded: lParam & 0xFFFF))
        let y = Int32(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF))
        let e = NSEvent._mouseEvent(type: type, location: contentPoint(x: x, y: y), modifierFlags: modifierFlags(),
                                    timestamp: timestamp(), windowNumber: windowNumber(), clickCount: clickCount, buttonNumber: button)
        owner?.platformWindowDispatch(e)
    }

    private func key(_ type: NSEvent.EventType, _ wParam: WPARAM, _ lParam: LPARAM) {
        var state = [UInt8](repeating: 0, count: 256)
        _ = GetKeyboardState(&state)
        let scan = UINT((lParam >> 16) & 0xFF)
        var buffer = [WCHAR](repeating: 0, count: 8)
        let n = ToUnicode(UINT(wParam), scan, state, &buffer, 8, 0)
        let chars = n > 0 ? String(decoding: buffer[0..<Int(n)], as: UTF16.self) : ""
        state[Int(VK_CONTROL)] = 0; state[Int(VK_MENU)] = 0; state[Int(VK_LCONTROL)] = 0; state[Int(VK_RCONTROL)] = 0
        state[Int(VK_LMENU)] = 0; state[Int(VK_RMENU)] = 0
        var buffer2 = [WCHAR](repeating: 0, count: 8)
        let n2 = ToUnicode(UINT(wParam), scan, state, &buffer2, 8, 0)
        let plain = n2 > 0 ? String(decoding: buffer2[0..<Int(n2)], as: UTF16.self) : chars
        let isRepeat = (lParam & 0x4000_0000) != 0
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifierFlags(), timestamp: timestamp(),
                                 windowNumber: windowNumber(), context: nil, characters: chars,
                                 charactersIgnoringModifiers: plain, isARepeat: isRepeat, keyCode: UInt16(truncatingIfNeeded: wParam))!
        owner?.platformWindowDispatch(e)
    }

    // MARK: Window procedure

    fileprivate func handle(_ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch Int32(msg) {
        case WM_PAINT:
            paint()
            return 0
        case WM_ERASEBKGND:
            return 1
        case WM_SIZE:
            if let rt = renderTarget {
                cd2d_target_resize(rt, UInt32(lParam & 0xFFFF), UInt32((lParam >> 16) & 0xFFFF))
            }
            owner?.platformWindowDidChangeFrame(frame)
            return 0
        case WM_MOVE:
            owner?.platformWindowDidChangeFrame(frame)
            return 0
        case WM_DPICHANGED:
            dpi = UINT(wParam & 0xFFFF)
            if let rt = renderTarget { cd2d_target_set_dpi(rt, Float(dpi)) }
            if let suggested = UnsafePointer<RECT>(bitPattern: Int(lParam)), let hwnd {
                let r = suggested.pointee
                SetWindowPos(hwnd, nil, r.left, r.top, r.right - r.left, r.bottom - r.top, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
            }
            owner?.platformWindowDidChangeBackingScaleFactor(scale)
            return 0
        case WM_GETMINMAXINFO:
            if let info = UnsafeMutablePointer<MINMAXINFO>(bitPattern: Int(lParam)) {
                let f = frameRect(forContentRect: NSRect(origin: .zero, size: minSize))
                info.pointee.ptMinTrackSize = POINT(x: Int32(f.width * scale), y: Int32(f.height * scale))
                if maxSize.width < 100_000 {
                    let m = frameRect(forContentRect: NSRect(origin: .zero, size: maxSize))
                    info.pointee.ptMaxTrackSize = POINT(x: Int32(m.width * scale), y: Int32(m.height * scale))
                }
            }
            return 0
        case WM_CLOSE:
            // Route through NSWindow.close() so delegates, notifications and the
            // last-window-closed check run; NSWindow then calls close() here.
            if owner?.platformWindowShouldClose() ?? true {
                if let owner { owner.platformWindowWillClose() } else { close() }
            }
            return 0
        case WM_DESTROY:
            discardRenderTarget()
            if let hwnd { SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0) }
            hwnd = nil
            let wasExternal = !destroying
            destroying = true
            if wasExternal { owner?.platformWindowWillClose() }
            return 0
        case WM_SETFOCUS:
            isKey = true
            owner?.platformWindowDidBecomeKey()
            return 0
        case WM_KILLFOCUS:
            isKey = false
            owner?.platformWindowDidResignKey()
            return 0
        case WM_LBUTTONDOWN, WM_LBUTTONDBLCLK:
            if let hwnd { SetCapture(hwnd) }
            pressedButtons |= 1
            NSEvent._pressedMouseButtons = pressedButtons
            mouse(.leftMouseDown, lParam, button: 0, clickCount: Int32(msg) == WM_LBUTTONDBLCLK ? 2 : 1)
            return 0
        case WM_LBUTTONUP:
            pressedButtons &= ~1
            NSEvent._pressedMouseButtons = pressedButtons
            if pressedButtons == 0 { ReleaseCapture() }
            mouse(.leftMouseUp, lParam, button: 0)
            return 0
        case WM_RBUTTONDOWN, WM_RBUTTONDBLCLK:
            if let hwnd { SetCapture(hwnd) }
            pressedButtons |= 2
            NSEvent._pressedMouseButtons = pressedButtons
            mouse(.rightMouseDown, lParam, button: 1, clickCount: Int32(msg) == WM_RBUTTONDBLCLK ? 2 : 1)
            return 0
        case WM_RBUTTONUP:
            pressedButtons &= ~2
            NSEvent._pressedMouseButtons = pressedButtons
            if pressedButtons == 0 { ReleaseCapture() }
            mouse(.rightMouseUp, lParam, button: 1)
            return 0
        case WM_MBUTTONDOWN:
            if let hwnd { SetCapture(hwnd) }
            pressedButtons |= 4
            NSEvent._pressedMouseButtons = pressedButtons
            mouse(.otherMouseDown, lParam, button: 2)
            return 0
        case WM_MBUTTONUP:
            pressedButtons &= ~4
            NSEvent._pressedMouseButtons = pressedButtons
            if pressedButtons == 0 { ReleaseCapture() }
            mouse(.otherMouseUp, lParam, button: 2)
            return 0
        case WM_MOUSEMOVE:
            if pressedButtons & 1 != 0 { mouse(.leftMouseDragged, lParam, button: 0) }
            else if pressedButtons & 2 != 0 { mouse(.rightMouseDragged, lParam, button: 1) }
            else if pressedButtons & 4 != 0 { mouse(.otherMouseDragged, lParam, button: 2) }
            else { mouse(.mouseMoved, lParam, button: 0, clickCount: 0) }
            return 0
        case WM_MOUSEWHEEL, WM_MOUSEHWHEEL:
            let delta = CGFloat(Int16(truncatingIfNeeded: (wParam >> 16) & 0xFFFF)) / 120
            var pt = POINT(x: Int32(Int16(truncatingIfNeeded: lParam & 0xFFFF)), y: Int32(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF)))
            if let hwnd { ScreenToClient(hwnd, &pt) }
            let horizontal = Int32(msg) == WM_MOUSEHWHEEL
            let e = NSEvent._scrollEvent(location: contentPoint(x: pt.x, y: pt.y), modifierFlags: modifierFlags(), timestamp: timestamp(),
                                         windowNumber: windowNumber(), deltaX: horizontal ? -delta : 0, deltaY: horizontal ? 0 : delta, precise: false)
            owner?.platformWindowDispatch(e)
            return 0
        case WM_KEYDOWN, WM_SYSKEYDOWN:
            key(.keyDown, wParam, lParam)
            return 0
        case WM_KEYUP, WM_SYSKEYUP:
            key(.keyUp, wParam, lParam)
            return 0
        default:
            return nil
        }
    }

    static let windowProc: WNDPROC = { hwnd, msg, wParam, lParam in
        let ptr = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
        guard ptr != 0, let raw = UnsafeRawPointer(bitPattern: Int(ptr)) else {
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
        let window = Unmanaged<Win32Window>.fromOpaque(raw).takeUnretainedValue()
        let handled: LRESULT? = MainActor.assumeIsolated { window.handle(msg, wParam, lParam) }
        return handled ?? DefWindowProcW(hwnd, msg, wParam, lParam)
    }
}
#endif
