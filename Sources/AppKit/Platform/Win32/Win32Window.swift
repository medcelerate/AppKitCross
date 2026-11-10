// A native HWND backing an NSWindow, painted with Direct2D.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import QuartzCore
import CD2D

@MainActor
final class Win32Window: PlatformWindow {
    private unowned let backend: Win32Backend
    /// Timer that drives animation frames during the modal move/size loop.
    private static let sizeMoveTimer: UINT_PTR = 7
    private static let wheelGestureTimer: UINT_PTR = 8
    /// WM_GESTURE tracking: the previous zoom distance, rotation angle and pan point.
    private var gestureZoomDistance: Double = 0
    private var gestureAngle: Double = 0
    private var gesturePanPoint = POINT()
    private var gestureActive = false
    /// A Ctrl+wheel magnify in progress (ends when no notch arrives for a while).
    private var wheelGesturePoint = NSPoint.zero
    private var wheelGestureActive = false
    private weak var owner: PlatformWindowOwner?
    private(set) var hwnd: HWND?
    private var renderTarget: OpaquePointer?        // CD2DTarget*
    private var _styleMask: NSWindow.StyleMask
    private var _title = ""
    private(set) var isKey = false
    private var destroying = false
    private var pressedButtons = 0
    /// An input method composition is in progress (WM_IME_STARTCOMPOSITION ... ENDCOMPOSITION).
    private var composing = false
    private var dpi: UINT = 96
    /// UI Automation provider root (CUIARoot*, Win32Accessibility.swift), made on demand.
    var uiaRoot: OpaquePointer? = nil
    var accessibilityOwner: PlatformWindowOwner? { owner }
    var accessibilityBackend: Win32Backend { backend }
    /// Changes waiting for the next turn of the event loop (Win32Accessibility.swift).
    var pendingAccessibilityChanges: [PlatformAccessibilityChange] = []
    var accessibilityFlushScheduled = false
    var minSize = NSSize(width: 0, height: 0)
    var maxSize = NSSize(width: 100_000, height: 100_000)

    init(backend: Win32Backend, owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) {
        self.backend = backend
        self.owner = owner
        self.ownerWantsMenuBar = owner.platformWantsMenuBar
        self._styleMask = styleMask
        let style = windowStyle(for: styleMask)
        var ex = Win32Backend.styles(for: styleMask).1
        // Windows presented through a flip-model swap chain or a DirectComposition visual
        // need no redirection surface: DWM would allocate one per window and copy into
        // it every frame. Windows honours the bit only at CreateWindowExW (verified on
        // build 26200), so it is decided here (Win32WindowPolicy), from whether swap
        // chains work at all, not from the chrome (which arrives after creation). Kept
        // for the legacy ID2D1HwndRenderTarget (APPKITWIN_LEGACY_D2D=1, or no D3D11
        // device), which blits into it, and for windows that carry the Win32 menu bar:
        // user32 draws the bar through GDI into the surface, a black strip without one.
        let redirection = Win32WindowPolicy.redirectionBitmap(styleMask: styleMask, applicationHasMenuBar: ownerWantsMenuBar,
                                                              legacyTarget: Win32Window.useLegacyHwndTarget, presentationAvailable: cd2d_presentation_available())
        if !redirection.keeps { ex |= Win32Window.wsExNoRedirectionBitmap }
        if NSView._traceInvalidation {
            let why: String
            switch redirection {
            case .none: why = "swap-chain presentation"
            case .keptForLegacyTarget: why = "legacy HWND target"
            case .keptForMissingDevice: why = "no D3D11/DXGI 1.2 device: HWND target"
            case .keptForMenuBar: why = "window carries the Win32 menu bar"
            }
            NSView._trace("win32 window create mask \(styleMask.rawValue) redirection bitmap \(redirection.keeps ? "kept" : "none") (\(why))")
        }
        let frame = backend.frameRect(forContentRect: contentRect, styleMask: styleMask)
        let scale = CGFloat(GetDpiForSystem()) / 96
        let r = Win32Backend.win32Rect(frame, scale: scale, primaryHeight: Win32Backend.primaryHeightPixels)
        hwnd = Win32Backend.windowClassName.withCString(encodedAs: UTF16.self) { cls in
            CreateWindowExW(ex, cls, nil, style, r.left, r.top, r.right - r.left, r.bottom - r.top, nil, nil, backend.hInstance, nil)
        }
        guard let hwnd else { return }
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())))
        dpi = GetDpiForWindow(hwnd)
        if CGFloat(dpi) / 96 != scale {
            // The window opened on a monitor whose DPI is not the system's: per-monitor-v2
            // awareness gives it that monitor's DPI without touching its size, so the
            // pixels requested at the system scale are the wrong number of points. Size
            // the client area from the point size at the window's own DPI, like
            // WM_DPICHANGED does, keeping the top-left corner.
            let i = nonClientInsets(dpi: dpi)
            let width = Int32((contentRect.width * self.scale).rounded()) + i.left + i.right
            let height = Int32((contentRect.height * self.scale).rounded()) + i.top + i.bottom
            SetWindowPos(hwnd, nil, 0, 0, width, height, UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
        }
        backend.register(self)
        cd2d_gestures_enable(UnsafeMutableRawPointer(hwnd))
        backend.win32DragDrop.register(hwnd)
        if usesCustomFrame {
            // CreateWindowExW sent WM_NCCALCSIZE before the window procedure knew this
            // object; recalculate so the client area covers the window from the start.
            SetWindowPos(hwnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
        }
        applyChrome()
    }

    /// Titled windows carry the application menu bar (AppKit's main menu is global).
    /// Windows whose content covers the frame have no non-client area to show it in.
    var wantsMenuBar: Bool { Win32WindowPolicy.carriesMenuBar(_styleMask, applicationHasMenuBar: ownerWantsMenuBar) && !usesCustomFrame }
    private let ownerWantsMenuBar: Bool
    private var _chrome = PlatformWindowChrome()
    var chrome: PlatformWindowChrome {
        get { _chrome }
        set {
            guard newValue != _chrome else { return }
            let old = _chrome
            _chrome = newValue
            applyChrome(previous: old)
        }
    }

    // MARK: Chrome (Milestone 3b)

    /// The content covers the whole window: no system caption, our WM_NCCALCSIZE and
    /// WM_NCHITTEST. Decided by the style mask (`fullSizeContentView` or borderless) so
    /// the frame is right from creation, before the chrome arrives; the chrome agrees.
    private var usesCustomFrame: Bool { Win32Backend.usesCustomFrame(_styleMask) || _chrome.extendsContentIntoTitleBar }

    private var isResizable: Bool { _styleMask.contains(.resizable) }

    private static let wsExNoRedirectionBitmap: DWORD = 0x0020_0000   // WS_EX_NOREDIRECTIONBITMAP

    /// A borderless window has no frame DWM could draw a shadow for (a resizable one has
    /// WS_THICKFRAME): WS_THICKFRAME gives it one, so `DwmExtendFrameIntoClientArea`
    /// below produces the drop shadow macOS shows. The client area still covers the
    /// whole window (WM_NCCALCSIZE) and WM_NCHITTEST never reports a resize edge for a
    /// non-resizable window, so the frame is invisible and inert. Dropped again when
    /// `hasShadow` is false.
    private func wantsShadowFrame(_ mask: NSWindow.StyleMask) -> Bool {
        !mask.contains(.titled) && !mask.contains(.resizable) && _chrome.hasShadow
    }

    /// The WS_* style for the mask, with the shadow frame when the chrome wants it.
    private func windowStyle(for mask: NSWindow.StyleMask) -> DWORD {
        var style = Win32Backend.styles(for: mask).0
        if wantsShadowFrame(mask) { style |= DWORD(WS_THICKFRAME) }
        return style
    }

    /// Whether the HWND carries WS_THICKFRAME (resizable, or the shadow frame).
    private var hasThickFrame: Bool { isResizable || wantsShadowFrame(_styleMask) }

    /// Re-applies the style when the shadow frame came or went (the mask itself is set
    /// by `styleMask`), so WM_NCCALCSIZE re-runs and DWM re-evaluates the frame.
    private func updateShadowFrameStyle() {
        guard let hwnd else { return }
        let current = DWORD(truncatingIfNeeded: GetWindowLongPtrW(hwnd, GWL_STYLE))
        let wanted = windowStyle(for: _styleMask)
        guard (current & DWORD(WS_THICKFRAME)) != (wanted & DWORD(WS_THICKFRAME)) else { return }
        let style = (current & ~DWORD(WS_THICKFRAME)) | (wanted & DWORD(WS_THICKFRAME))
        SetWindowLongPtrW(hwnd, GWL_STYLE, LONG_PTR(style))
        SetWindowPos(hwnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
    }

    // dwmapi.h values (the enums import awkwardly); Windows 11 22H2+ for the backdrop.
    private static let dwmwaNCRenderingPolicy: DWORD = 2
    private static let dwmwaUseImmersiveDarkMode: DWORD = 20
    private static let dwmwaWindowCornerPreference: DWORD = 33
    private static let dwmwaSystemBackdropType: DWORD = 38
    private static let dwmwaBorderColor: DWORD = 34
    /// DWMWA_COLOR_NONE / DWMWA_COLOR_DEFAULT for DWMWA_BORDER_COLOR (Windows 11).
    private static let dwmColorNone = Int32(bitPattern: 0xFFFF_FFFE), dwmColorDefault = Int32(bitPattern: 0xFFFF_FFFF)
    private static let dwmncrpUseWindowStyle: Int32 = 0, dwmncrpDisabled: Int32 = 2
    private static let dwmwcpDoNotRound: Int32 = 1, dwmwcpRound: Int32 = 2
    private static let dwmsbtNone: Int32 = 1, dwmsbtMainWindow: Int32 = 2, dwmsbtTransientWindow: Int32 = 3, dwmsbtTabbedWindow: Int32 = 4

    private func setDwmAttribute(_ attribute: DWORD, _ value: Int32) {
        guard let hwnd else { return }
        var v = value
        // Fails silently on builds that do not know the attribute (e.g. the backdrop
        // before Windows 11 22H2), which leaves the default look.
        _ = DwmSetWindowAttribute(hwnd, attribute, &v, DWORD(MemoryLayout<Int32>.size))
    }

    /// Whether the system app theme is dark (HKCU ...\Themes\Personalize\AppsUseLightTheme == 0).
    static func systemAppThemeIsDark() -> Bool {
        var value: DWORD = 1
        var size = DWORD(MemoryLayout<DWORD>.size)
        // HKEY_CURRENT_USER is ((HKEY)(ULONG_PTR)((LONG)0x80000001)), sign-extended on x64.
        let hkcu = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0001)))
        let status = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize".withCString(encodedAs: UTF16.self) { key in
            "AppsUseLightTheme".withCString(encodedAs: UTF16.self) { name in
                RegGetValueW(hkcu, key, name, DWORD(RRF_RT_REG_DWORD), nil, &value, &size)
            }
        }
        return status == ERROR_SUCCESS && value == 0
    }

    /// Applies the chrome to the live HWND without recreating it: DWM attributes
    /// (backdrop, corners, shadow policy, dark mode), the frame extension that keeps the
    /// DWM shadow and rounded corners on a custom frame, and the swap-chain kind
    /// (composition, premultiplied) for transparent windows.
    private func applyChrome(previous: PlatformWindowChrome? = nil) {
        if NSView._traceInvalidation { NSView._trace("win32 applyChrome") }
        guard let hwnd else { return }

        // Transparent windows draw into a premultiplied composition swap chain, so
        // unpainted pixels show the backdrop (see ensureRenderTarget); the next paint
        // builds the right kind of target. WS_EX_NOREDIRECTIONBITMAP would also drop
        // the window's redirection surface, but Windows honours that bit only at
        // CreateWindowExW (SetWindowLongPtr + SWP_FRAMECHANGED leaves it clear; verified
        // on build 26200) and the chrome arrives after creation. The composition visual
        // is composed over the never-painted surface and the backdrop shows through, so
        // the window is not recreated for it.
        let transparencyChanged = previous.map { $0.isTransparent != _chrome.isTransparent } ?? _chrome.isTransparent
        if transparencyChanged, renderTarget != nil {
            discardRenderTarget()
            setNeedsDisplay(nil)
        }

        // Frame: keep the DWM shadow, border and rounded corners while the client area
        // covers the frame by extending the frame one pixel into the client area. A
        // borderless window gets a frame to extend (WS_THICKFRAME) while it wants a
        // shadow; without a shadow nothing is extended and DWM draws no frame at all.
        updateShadowFrameStyle()
        let shadowFrame = usesCustomFrame && _chrome.hasShadow
        var margins = MARGINS(cxLeftWidth: 0, cxRightWidth: 0, cyTopHeight: shadowFrame ? 1 : 0, cyBottomHeight: 0)
        _ = DwmExtendFrameIntoClientArea(hwnd, &margins)
        if previous.map({ $0.extendsContentIntoTitleBar != _chrome.extendsContentIntoTitleBar }) ?? false {
            SetWindowPos(hwnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
        }
        // A borderless window shows no border line (macOS draws none), only the shadow;
        // so the extended pixel of a translucent window stays invisible too.
        setDwmAttribute(Win32Window.dwmwaBorderColor, _styleMask.contains(.titled) ? Win32Window.dwmColorDefault : Win32Window.dwmColorNone)
        if NSView._traceInvalidation {
            let frame = _styleMask.contains(.titled) ? "system caption" : isResizable ? "thick frame" : wantsShadowFrame(_styleMask) ? "shadow frame (WS_THICKFRAME added)" : "none"
            NSView._trace("win32 chrome '\(_title)' shadow \(_chrome.hasShadow ? "on" : "off") frame \(frame) extended \(margins.cyTopHeight) px transparent \(_chrome.isTransparent)")
        }

        let backdrop: Int32
        switch _chrome.backdrop {
        case .none: backdrop = Win32Window.dwmsbtNone
        case .mica: backdrop = Win32Window.dwmsbtMainWindow
        case .micaAlt: backdrop = Win32Window.dwmsbtTabbedWindow
        case .acrylic: backdrop = Win32Window.dwmsbtTransientWindow
        }
        setDwmAttribute(Win32Window.dwmwaSystemBackdropType, backdrop)
        setDwmAttribute(Win32Window.dwmwaUseImmersiveDarkMode, Win32Window.systemAppThemeIsDark() ? 1 : 0)
        setDwmAttribute(Win32Window.dwmwaWindowCornerPreference, _chrome.roundedCorners ? Win32Window.dwmwcpRound : Win32Window.dwmwcpDoNotRound)
        // No shadow: disabling non-client rendering is the closest DWM offers.
        setDwmAttribute(Win32Window.dwmwaNCRenderingPolicy, _chrome.hasShadow ? Win32Window.dwmncrpUseWindowStyle : Win32Window.dwmncrpDisabled)
        // hidesTitle / transparentTitleBar only have a visible effect together with
        // extendsContentIntoTitleBar, where the caption is not drawn at all.
    }

    var scale: CGFloat { CGFloat(dpi) / 96 }

    // MARK: PlatformWindow

    var title: String {
        get { _title }
        set {
            _title = newValue
            applyNativeTitle()
        }
    }
    /// `NSWindow.isDocumentEdited`: shown as "*" before the title, as Notepad does.
    private var isDocumentEdited = false
    func setDocumentEdited(_ edited: Bool) {
        guard edited != isDocumentEdited else { return }
        isDocumentEdited = edited
        applyNativeTitle()
    }
    private func applyNativeTitle() {
        guard let hwnd else { return }
        let shown = isDocumentEdited ? "*" + _title : _title
        shown.withCString(encodedAs: UTF16.self) { _ = SetWindowTextW(hwnd, $0) }
    }

    var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set {
            _styleMask = newValue
            guard let hwnd else { return }
            let style = windowStyle(for: newValue)
            // The redirection-bitmap bit is creation-only: keep whatever the window has.
            let ex = Win32Backend.styles(for: newValue).1 | (DWORD(truncatingIfNeeded: GetWindowLongPtrW(hwnd, GWL_EXSTYLE)) & Win32Window.wsExNoRedirectionBitmap)
            SetWindowLongPtrW(hwnd, GWL_STYLE, LONG_PTR(style))
            SetWindowLongPtrW(hwnd, GWL_EXSTYLE, LONG_PTR(ex))
            // WM_NCCALCSIZE re-runs for the new mask (custom frame or system caption).
            SetWindowPos(hwnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED))
            applyChrome(previous: _chrome)
        }
    }

    var backingScaleFactor: CGFloat { scale }

    /// The monitor holding most of the window (what WM_DPICHANGED tracks), so
    /// `NSWindow.screen` reports its scale rather than guessing from point rects.
    var currentDisplay: PlatformDisplay? {
        guard let hwnd else { return nil }
        return Win32Backend.display(for: MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST)), primaryHeight: Win32Backend.primaryHeightPixels)
    }

    var isVisible: Bool { hwnd.map { IsWindowVisible($0) } ?? false }

    /// The frame before the window was minimised: a minimised HWND sits at
    /// (-32000, -32000) with a tiny rect, while AppKit keeps a miniaturised window's frame.
    private var frameBeforeMinimize: NSRect?
    /// Whether the last WM_SIZE was SIZE_MINIMIZED, so a restore (from the taskbar or
    /// `deminiaturize()`) is reported once.
    private var reportedIconic = false

    var frame: NSRect {
        get {
            guard let hwnd else { return .zero }
            if IsIconic(hwnd), let f = frameBeforeMinimize { return f }
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
            if NSView._traceInvalidation { NSView._trace("win32 set frame \(f) (was \(frame))") }
            SetWindowPos(hwnd, nil, r.left, r.top, r.right - r.left, r.bottom - r.top, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
        }
    }

    private var hasMenuBar: Bool { wantsMenuBar && backend.menuBar.spec != nil }

    /// Pixels between the window rect and the client rect on each side, at `dpi`
    /// (`left`/`top` positive inward). A custom frame has none, except that a
    /// maximised thick-framed window hangs over the monitor edge by its frame width,
    /// which WM_NCCALCSIZE trims off the client area.
    private func nonClientInsets(dpi: UINT) -> (left: Int32, top: Int32, right: Int32, bottom: Int32) {
        if usesCustomFrame {
            guard let hwnd, IsZoomed(hwnd), hasThickFrame else { return (0, 0, 0, 0) }
            let padded = GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi)
            let x = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + padded
            let y = GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + padded
            return (x, y, x, y)
        }
        let (style, ex) = Win32Backend.styles(for: _styleMask)
        var r = RECT(left: 0, top: 0, right: 100, bottom: 100)
        _ = AdjustWindowRectExForDpi(&r, style, hasMenuBar, ex, dpi)
        return (-r.left, -r.top, r.right - 100, r.bottom - 100)
    }

    func frameRect(forContentRect contentRect: NSRect) -> NSRect {
        let i = nonClientInsets(dpi: dpi)
        let leftInset = CGFloat(i.left) / scale, rightInset = CGFloat(i.right) / scale
        let topInset = CGFloat(i.top) / scale, bottomInset = CGFloat(i.bottom) / scale
        return NSRect(x: contentRect.minX - leftInset, y: contentRect.minY - bottomInset,
                      width: contentRect.width + leftInset + rightInset, height: contentRect.height + topInset + bottomInset)
    }

    func contentRect(forFrameRect frameRect: NSRect) -> NSRect {
        let i = nonClientInsets(dpi: dpi)
        let leftInset = CGFloat(i.left) / scale, rightInset = CGFloat(i.right) / scale
        let topInset = CGFloat(i.top) / scale, bottomInset = CGFloat(i.bottom) / scale
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

    func show() { if let hwnd { ShowWindow(hwnd, _styleMask.contains(.nonactivatingPanel) ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL); UpdateWindow(hwnd) } }
    func hide() { if let hwnd { ShowWindow(hwnd, SW_HIDE) } }
    func makeKey() { if let hwnd { SetForegroundWindow(hwnd); SetActiveWindow(hwnd); SetFocus(hwnd) } }
    func orderBack() { if let hwnd { SetWindowPos(hwnd, HWND(bitPattern: 1) /* HWND_BOTTOM */, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)) } }
    func miniaturize() { if let hwnd { ShowWindow(hwnd, SW_MINIMIZE) } }
    func deminiaturize() { if let hwnd, IsIconic(hwnd) { ShowWindow(hwnd, SW_RESTORE) } }
    func zoom() { if let hwnd { ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE) } }
    var isMiniaturized: Bool { hwnd.map { IsIconic($0) } ?? false }
    var isZoomed: Bool { hwnd.map { IsZoomed($0) } ?? false }

    func close() {
        guard let hwnd, !destroying else { return }
        destroying = true
        DestroyWindow(hwnd)
    }

    func setNeedsDisplay(_ rect: NSRect?) {
        guard let hwnd else { return }
        if let rect, var r = clientRect(rect) {
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

    /// AppKit content coordinates (points, bottom-left) -> client pixels RECT, or nil
    /// for a rect that is not finite (layout fallout the caller treats as "everything").
    private func clientRect(_ rect: NSRect) -> RECT? {
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        let h = contentSize.height
        func px(_ v: CGFloat, _ rule: FloatingPointRoundingRule) -> Int32 {
            Int32(min(max(v * scale, -1_000_000), 1_000_000).rounded(rule))
        }
        return RECT(left: px(rect.minX, .down), top: px(h - rect.maxY, .down),
                    right: px(rect.maxX, .up), bottom: px(h - rect.minY, .up))
    }

    /// Client pixel coordinates -> AppKit content points.
    /// Content coordinates for a point in screen pixels (OLE drag positions).
    func contentPoint(screenX: Int32, screenY: Int32) -> NSPoint {
        var pt = POINT(x: screenX, y: screenY)
        if let hwnd { ScreenToClient(hwnd, &pt) }
        return contentPoint(x: pt.x, y: pt.y)
    }

    /// After an OLE drag (which captured the mouse): the pressed buttons are released and
    /// the owner sees the mouse-up it missed, at the current pointer position.
    func endPressAfterDrag() {
        guard pressedButtons != 0, let hwnd else { return }
        var pt = POINT()
        GetCursorPos(&pt)
        ScreenToClient(hwnd, &pt)
        let button = pressedButtons & 1 != 0 ? 0 : pressedButtons & 2 != 0 ? 1 : 2
        pressedButtons = 0
        NSEvent._pressedMouseButtons = 0
        let e = NSEvent._mouseEvent(type: button == 0 ? .leftMouseUp : button == 1 ? .rightMouseUp : .otherMouseUp, location: contentPoint(x: pt.x, y: pt.y),
                                    modifierFlags: modifierFlags(), timestamp: timestamp(), windowNumber: windowNumber(), clickCount: 1, buttonNumber: button)
        owner?.platformWindowDispatch(e)
    }

    // Drags delivered by OLE (Win32DragDrop.swift) reach the owner through these.
    func ownerDragEntered(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragEntered(drag) ?? [] }
    func ownerDragUpdated(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragUpdated(drag) ?? [] }
    func ownerDragExited() { owner?.platformDragExited() }
    func ownerDrop(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDrop(drag) ?? [] }

    private func contentPoint(x: Int32, y: Int32) -> NSPoint {
        let h = contentSize.height
        return NSPoint(x: CGFloat(x) / scale, y: h - CGFloat(y) / scale)
    }

    private func windowNumber() -> Int { (owner as? NSWindow)?.windowNumber ?? 0 }

    // MARK: Painting

    /// `APPKITWIN_LEGACY_D2D=1` selects the Milestone 1 `ID2D1HwndRenderTarget` instead of
    /// the DXGI flip-model swap chain (Milestone 3).
    private static let useLegacyHwndTarget = ProcessInfo.processInfo.environment["APPKITWIN_LEGACY_D2D"] == "1"
    /// `APPKITWIN_DXGI_DEBUG=1` prints the DXGI debug layer's live-object report to stderr
    /// whenever a window target is released (and asks for the D3D11 debug layer).
    private static let reportsLiveObjects = ProcessInfo.processInfo.environment["APPKITWIN_DXGI_DEBUG"] == "1"

    private func ensureRenderTarget() -> OpaquePointer? {
        if let rt = renderTarget { return rt }
        guard let hwnd, let factory = backend.d2dFactory else { return nil }
        var client = RECT()
        GetClientRect(hwnd, &client)
        let width = UInt32(max(1, client.right - client.left))
        let height = UInt32(max(1, client.bottom - client.top))
        var rt: OpaquePointer? = nil
        if !Win32Window.useLegacyHwndTarget {
            // Transparent windows (Milestone 3b): a premultiplied composition swap chain
            // under DirectComposition, so the DWM backdrop shows through unpainted pixels.
            // Windows hosting their layer tree (Milestone 9) need the same chain: the
            // visuals hang under its DirectComposition visual.
            let composition = _chrome.isTransparent || hostedScene != nil
            // HDR (ADR-0016): on a monitor in HDR mode the chain is FP16 scRGB and the
            // frames are scaled by the SDR white level; elsewhere 8-bit sRGB as before.
            let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
            let hdr = Win32Backend.displayHDR(for: monitor)
            presentationMonitor = monitor
            presentationSDRWhite = hdr.sdrWhiteNits
            var options = CD2DSwapChainOptions(composition: composition, hdr: hdr.hdr, sdrWhiteNits: hdr.sdrWhiteNits)
            var hdrRefused = false
            rt = cd2d_target_create_swapchain_with_options(factory, UnsafeMutableRawPointer(hwnd), width, height, Float(dpi), &options)
            if rt == nil, options.hdr {
                hdrRefused = true
                options.hdr = false
                rt = cd2d_target_create_swapchain_with_options(factory, UnsafeMutableRawPointer(hwnd), width, height, Float(dpi), &options)
            }
            if rt == nil, composition {
                options.composition = false
                rt = cd2d_target_create_swapchain_with_options(factory, UnsafeMutableRawPointer(hwnd), width, height, Float(dpi), &options)
            }
            if NSView._traceInvalidation {
                let chain = rt.map { cd2d_target_is_hdr($0) ? "hdr R16G16B16A16_FLOAT scRGB sdr white \(hdr.sdrWhiteNits) nits" : "sdr B8G8R8A8_UNORM sRGB" } ?? "none (HWND target)"
                let colour = hdr.advancedColorEnabled ? "on" : hdr.advancedColorSupported ? "off" : "unsupported"
                NSView._trace("win32 window '\(_title)' swap chain \(chain)\(hdrRefused ? " (HDR chain refused)" : "") \(options.composition ? "composition" : "hwnd") monitor \(currentDisplay?.localizedName ?? "?") colour space \(hdr.colorSpace) max \(hdr.maxLuminance) nits advanced colour \(colour) \(hdr.bitsPerColor) bpc")
            }
        }
        if rt == nil {
            // Legacy path, or no usable D3D11/DXGI device: the HWND render target still works.
            rt = cd2d_target_create_hwnd(factory, UnsafeMutableRawPointer(hwnd), width, height, Float(dpi))
            if NSView._traceInvalidation, !Win32Window.useLegacyHwndTarget, (DWORD(truncatingIfNeeded: GetWindowLongPtrW(hwnd, GWL_EXSTYLE)) & Win32Window.wsExNoRedirectionBitmap) != 0 {
                NSView._trace("win32 window '\(_title)' fell back to the HWND target without a redirection bitmap: its frames cannot reach the screen")
            }
        }
        renderTarget = rt
        if Win32Window.reportsLiveObjects, let rt {
            let kind = cd2d_target_is_composition(rt) ? "composition swap-chain" : cd2d_target_is_swapchain(rt) ? "swap-chain" : "HWND"
            reportLiveObjects("after creating the \(kind) window target")
        }
        return rt
    }

    private func discardRenderTarget() {
        releaseCompositionTree()         // its visuals and surfaces live on the target's devices
        cd2d_target_release(renderTarget)
        renderTarget = nil
        if Win32Window.reportsLiveObjects { reportLiveObjects("after releasing the window target") }
    }

    private func reportLiveObjects(_ when: String) {
        let lines = cd2d_debug_report_live_objects()
        fputs("[dxgi-debug] live DXGI/D3D objects \(when): \(lines < 0 ? "debug layer unavailable" : "\(lines)")\n", stderr)
    }

    private func paint() {
        guard let hwnd else { return }
        var ps = PAINTSTRUCT()
        _ = BeginPaint(hwnd, &ps)
        defer { EndPaint(hwnd, &ps) }
        guard let rt = ensureRenderTarget(), let factory = backend.d2dFactory else { return }
        // A hosted scene whose visual tree went with a discarded target is rebuilt on the
        // new one (device loss, a chrome change) before the frame it sits on is drawn.
        if let scene = hostedScene, compositionTree == nil, !applyLayerScene(scene, to: rt) {
            tearDownLayerHosting()
        }
        let size = contentSize
        // Both kinds of target keep their contents between frames (the swap chain through
        // its canvas), so only the rect Windows reports is repainted and presented.
        var dirty = NSRect(x: CGFloat(ps.rcPaint.left) / scale,
                           y: size.height - CGFloat(ps.rcPaint.bottom) / scale,
                           width: CGFloat(ps.rcPaint.right - ps.rcPaint.left) / scale,
                           height: CGFloat(ps.rcPaint.bottom - ps.rcPaint.top) / scale)
        // A new or resized canvas has nothing to keep: paint everything this frame. A
        // transparent window repaints whole every frame: its cleared pixels must meet the
        // DWM backdrop edge to edge, and a partial clear left dark bands after resizes.
        if cd2d_target_is_swapchain(rt), cd2d_target_canvas_is_fresh(rt) || cd2d_target_is_composition(rt) { dirty = NSRect(origin: .zero, size: size) }
        if NSView._traceInvalidation { NSView._trace("win32 paint dirty \(ps.rcPaint.left),\(ps.rcPaint.top)-\(ps.rcPaint.right),\(ps.rcPaint.bottom) px of \(Int(size.width * scale))x\(Int(size.height * scale))") }
        painting = true
        defer { painting = false }
        cd2d_target_begin_draw(rt)
        let whole = dirty == NSRect(origin: .zero, size: size)
        if cd2d_target_is_swapchain(rt), !dirty.isEmpty, !whole {
            cd2d_target_set_dirty(rt, ps.rcPaint.left, ps.rcPaint.top, ps.rcPaint.right, ps.rcPaint.bottom)
        }
        // A transparent window starts every frame fully transparent in the painted area so
        // unpainted pixels show the backdrop; an opaque window fills its background in NSWindow.
        if cd2d_target_is_composition(rt) {
            if whole {
                cd2d_target_clear(rt, 0, 0, 0, 0)
            } else {
                cd2d_target_push_clip_rect(rt, Float(ps.rcPaint.left) / Float(scale), Float(ps.rcPaint.top) / Float(scale), Float(ps.rcPaint.right) / Float(scale), Float(ps.rcPaint.bottom) / Float(scale), false)
                cd2d_target_clear(rt, 0, 0, 0, 0)
                cd2d_target_pop_clip_rect(rt)
            }
        }
        // Flip: CoreGraphics is bottom-left in points; Direct2D is top-left in DIPs.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        do {
            let ctx = CGContext(target: rt, factory: factory, baseTransform: flip,
                                width: Int(size.width * scale), height: Int(size.height * scale))
            let rect = dirty.isEmpty ? NSRect(origin: .zero, size: size) : dirty
            ctx.clip(to: rect)
            owner?.platformWindowDraw(into: ctx, dirtyRect: rect)
        }
        if !cd2d_target_end_draw(rt) {
            discardRenderTarget()
        } else if hostedScene != nil, !cd2d_target_is_composition(rt) {
            // Hosting started during this paint on an opaque swap chain: swap the target for
            // a composition one now that the frame is out, and build the tree on it.
            discardRenderTarget()
            setNeedsDisplay(nil)
        }
    }

    // MARK: Native layer hosting (Milestone 9, ADR-0005)

    /// `APPKITWIN_SOFTWARE_LAYERS=1` declines every scene, so the window composites its
    /// layer tree in software (to compare against the DirectComposition tree).
    private static let softwareLayers = ProcessInfo.processInfo.environment["APPKITWIN_SOFTWARE_LAYERS"] == "1"
    /// `APPKITWIN_TRACE_SCENE=1` (with APPKITWIN_TRACE) logs every scene node on each commit.
    private static let traceScene = ProcessInfo.processInfo.environment["APPKITWIN_TRACE_SCENE"] == "1"
    private var compositionTree: OpaquePointer?       // CD2DCompTree*, built on `renderTarget`
    /// The last scene committed; non-nil while hosting. Kept so the tree can be rebuilt on a
    /// new target (device loss, chrome change) or at a new DPI without a new commit.
    private var hostedScene: PlatformLayerScene?
    /// What each content node's surface holds: redrawn when any of these change.
    private var surfaceRasters: [Int: (version: Int, width: Int, height: Int, scale: CGFloat)] = [:]
    /// Nodes whose visual shows a swap chain instead of a surface (MTKView, M7).
    private var nativeContents: [Int: UnsafeMutableRawPointer] = [:]
    private var painting = false
    /// The monitor the swap chain was made for, and the SDR white level it scales by:
    /// a move to a monitor of the other kind (HDR / SDR) rebuilds the chain, a changed
    /// white level on the same kind adjusts the scale (ADR-0016).
    private var presentationMonitor: HMONITOR?
    private var presentationSDRWhite: Float = 80

    /// After a move, resize or display change: does the window's monitor still match the
    /// chain it presents through?
    private func checkPresentationMonitor(force: Bool = false) {
        guard let hwnd, let rt = renderTarget, cd2d_target_is_swapchain(rt), !painting else { return }
        let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
        guard force || monitor != presentationMonitor else { return }
        presentationMonitor = monitor
        let hdr = Win32Backend.displayHDR(for: monitor)
        if hdr.hdr != cd2d_target_is_hdr(rt) {
            if NSView._traceInvalidation { NSView._trace("win32 window '\(_title)' monitor \(currentDisplay?.localizedName ?? "?") is \(hdr.hdr ? "HDR" : "SDR"): rebuilding the swap chain") }
            discardRenderTarget()
            setNeedsDisplay(nil)
        } else if hdr.hdr, hdr.sdrWhiteNits != presentationSDRWhite {
            if NSView._traceInvalidation { NSView._trace("win32 window '\(_title)' sdr white \(presentationSDRWhite) -> \(hdr.sdrWhiteNits) nits") }
            presentationSDRWhite = hdr.sdrWhiteNits
            cd2d_target_set_sdr_white_level(rt, hdr.sdrWhiteNits)
            setNeedsDisplay(nil)
        }
    }

    func hostLayerScene(_ scene: PlatformLayerScene?) -> Bool {
        guard let scene else { tearDownLayerHosting(); return true }
        guard !Win32Window.softwareLayers, !Win32Window.useLegacyHwndTarget, hwnd != nil, !destroying else { return false }
        hostedScene = scene
        // An opaque window on the HWND swap chain moves to the composition swap chain the
        // visuals need. Not while the chain is mid-frame: paint() swaps it afterwards.
        if let rt = renderTarget, !cd2d_target_is_composition(rt) {
            guard !painting else { return true }
            discardRenderTarget()
            setNeedsDisplay(nil)
        }
        guard let rt = ensureRenderTarget(), cd2d_target_is_composition(rt) else {
            tearDownLayerHosting()
            return false
        }
        guard applyLayerScene(scene, to: rt) else {
            tearDownLayerHosting()
            return false
        }
        return true
    }

    private func tearDownLayerHosting() {
        hostedScene = nil
        releaseCompositionTree()
        // The composition swap chain keeps serving an opaque window; nothing to switch back.
    }

    private func releaseCompositionTree() {
        guard let tree = compositionTree else { return }
        cd2d_comp_tree_release(tree)
        compositionTree = nil
        surfaceRasters.removeAll()
        nativeContents.removeAll()
    }

    /// Mirrors the scene into the visual tree on `rt`: one visual per node, placed by its
    /// transform with the DPI scale folded into translations, clips and surface sizes
    /// (DirectComposition composes in pixels), and one surface per content node that is
    /// redrawn only when its version, pixel size or scale changed.
    private func applyLayerScene(_ scene: PlatformLayerScene, to rt: OpaquePointer) -> Bool {
        guard let factory = backend.d2dFactory else { return false }
        if compositionTree == nil {
            compositionTree = cd2d_comp_tree_create(rt)
            surfaceRasters.removeAll()
            nativeContents.removeAll()
        }
        guard let tree = compositionTree else { return false }
        let s = scale
        let dpi = Float(96 * s)
        cd2d_comp_tree_begin_update(tree)
        var live = Set<Int>()
        for node in scene.nodes {
            let id = Int64(node.id)
            live.insert(node.id)
            let parent = node.parent.map { Int64(scene.nodes[$0].id) } ?? 0
            guard cd2d_comp_tree_ensure_visual(tree, id, parent) else {
                cd2d_comp_tree_end_update(tree)
                return false
            }
            let t = node.transform
            if NSView._traceInvalidation, Win32Window.traceScene {
                NSView._trace("win32 scene node \(node.id) parent \(node.parent.map { String(scene.nodes[$0].id) } ?? "root") size \(Int(node.size.width))x\(Int(node.size.height)) at \(Int(t.tx)),\(Int(t.ty)) d \(t.d) 3d \(node.transform3D != nil) clip \(node.clipsToBounds) content \(node.content != nil) native \(node.nativeContent != nil) \(node.name ?? "")")
            }
            if let m = node.transform3D {
                // The whole placement goes through the 3D effect; the 2D transform stays identity.
                // Points → pixels: x,y rows/columns scale by s, z stays in points (x' = x*m11 + ... ;
                // entries feeding x,y from z/w scale up, entries feeding z/w from x,y scale down).
                cd2d_comp_tree_set_transform(tree, id, 1, 0, 0, 1, 0, 0)
                let f = Float(s)
                var rows: [Float] = [
                    Float(m.m11), Float(m.m12), Float(m.m13) / f, Float(m.m14) / f,
                    Float(m.m21), Float(m.m22), Float(m.m23) / f, Float(m.m24) / f,
                    Float(m.m31) * f, Float(m.m32) * f, Float(m.m33), Float(m.m34),
                    Float(m.m41) * f, Float(m.m42) * f, Float(m.m43), Float(m.m44),
                ]
                cd2d_comp_tree_set_transform3d(tree, id, &rows)
            } else {
                cd2d_comp_tree_set_transform(tree, id, Float(t.a), Float(t.b), Float(t.c), Float(t.d), Float(t.tx * s), Float(t.ty * s))
                cd2d_comp_tree_set_transform3d(tree, id, nil)
            }
            cd2d_comp_tree_set_opacity(tree, id, node.opacity)
            if node.clipsToBounds {
                let w = node.size.width * s, h = node.size.height * s
                let r = min(node.cornerRadius * s, w / 2, h / 2)
                func radius(_ corner: CACornerMask) -> Float { node.maskedCorners.contains(corner) ? Float(r) : 0 }
                cd2d_comp_tree_set_clip(tree, id, true, 0, 0, Float(w), Float(h),
                                        radius(.layerMinXMinYCorner), radius(.layerMaxXMinYCorner),
                                        radius(.layerMinXMaxYCorner), radius(.layerMaxXMaxYCorner))
            } else {
                cd2d_comp_tree_set_clip(tree, id, false, 0, 0, 0, 0, 0, 0, 0, 0)
            }
            if let native = node.nativeContent {
                // A swap chain presented by its owner (MTKView): the visual shows it directly,
                // sized by the chain itself, so only a changed chain touches the visual.
                if nativeContents[node.id] != native {
                    surfaceRasters[node.id] = nil
                    if cd2d_comp_tree_set_swapchain(tree, id, native) { nativeContents[node.id] = native } else { nativeContents[node.id] = nil }
                }
                continue
            }
            if nativeContents.removeValue(forKey: node.id) != nil { _ = cd2d_comp_tree_set_swapchain(tree, id, nil) }
            guard let content = node.content else {
                if surfaceRasters.removeValue(forKey: node.id) != nil { cd2d_comp_tree_remove_surface(tree, id) }
                continue
            }
            let width = max(1, Int((node.size.width * s).rounded(.up)))
            let height = max(1, Int((node.size.height * s).rounded(.up)))
            if let r = surfaceRasters[node.id], r.version == content.version, r.width == width, r.height == height, r.scale == s { continue }
            guard let surface = cd2d_comp_tree_surface_begin_draw(tree, id, UInt32(width), UInt32(height), dpi) else {
                surfaceRasters[node.id] = nil
                continue
            }
            do {
                // Points, bottom-left origin, flipped by the node height: the same space
                // Win32Offscreen gives lockFocus drawing.
                let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: node.size.height)
                let ctx = CGContext(target: surface, factory: factory, baseTransform: flip, width: width, height: height)
                content.draw(ctx)
            }
            cd2d_comp_tree_surface_end_draw(tree, id)
            surfaceRasters[node.id] = (content.version, width, height, s)
        }
        cd2d_comp_tree_end_update(tree)
        surfaceRasters = surfaceRasters.filter { live.contains($0.key) }
        nativeContents = nativeContents.filter { live.contains($0.key) }
        return true
    }

    // MARK: Input

    private func modifierFlags() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if GetKeyState(VK_SHIFT) < 0 { flags.insert(.shift) }
        // Ctrl plays the role of Command so AppKit key equivalents (Cmd+S, Cmd+Q) land on the
        // keys Windows users press; the Windows key maps to .control.
        if GetKeyState(VK_CONTROL) < 0 { flags.insert(.command) }
        if GetKeyState(VK_MENU) < 0 { flags.insert(.option) }
        if GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0 { flags.insert(.control) }
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

    /// Virtual keys that AppKit reports as function-key characters (NSEvent.SpecialKey) or
    /// control characters, with the macOS virtual key code AppKit clients may compare against.
    private static let specialKeys: [Int32: (String, UInt16)] = [
        VK_LEFT: ("\u{F702}", 123), VK_RIGHT: ("\u{F703}", 124), VK_UP: ("\u{F700}", 126), VK_DOWN: ("\u{F701}", 125),
        VK_HOME: ("\u{F729}", 115), VK_END: ("\u{F72B}", 119), VK_PRIOR: ("\u{F72C}", 116), VK_NEXT: ("\u{F72D}", 121),
        VK_DELETE: ("\u{F728}", 117), VK_BACK: ("\u{7F}", 51), VK_RETURN: ("\r", 36), VK_TAB: ("\t", 48),
        VK_ESCAPE: ("\u{1B}", 53), VK_INSERT: ("\u{F727}", 114),
        VK_F1: ("\u{F704}", 122), VK_F2: ("\u{F705}", 120), VK_F3: ("\u{F706}", 99), VK_F4: ("\u{F707}", 118),
        VK_F5: ("\u{F708}", 96), VK_F6: ("\u{F709}", 97), VK_F7: ("\u{F70A}", 98), VK_F8: ("\u{F70B}", 100),
        VK_F9: ("\u{F70C}", 101), VK_F10: ("\u{F70D}", 109), VK_F11: ("\u{F70E}", 103), VK_F12: ("\u{F70F}", 111),
    ]

    private func key(_ type: NSEvent.EventType, _ wParam: WPARAM, _ lParam: LPARAM) {
        let vk = Int32(truncatingIfNeeded: wParam)
        if NSView._traceInvalidation { NSView._trace("win32 key \(type == .keyDown ? "down" : "up") vk \(vk) '\(title)' composing \(composing)") }
        // An active input method owns the keyboard: the keystrokes it consumes arrive as
        // VK_PROCESSKEY and come back as WM_IME_* messages, so they are not key events too.
        if vk == VK_PROCESSKEY || composing { return }
        var chars = "", plain = ""
        var keyCode = UInt16(truncatingIfNeeded: wParam)
        if let special = Win32Window.specialKeys[vk] {
            chars = special.0
            plain = special.0
            keyCode = special.1
        } else {
            var state = [UInt8](repeating: 0, count: 256)
            _ = GetKeyboardState(&state)
            let scan = UINT((lParam >> 16) & 0xFF)
            var buffer = [WCHAR](repeating: 0, count: 8)
            let n = ToUnicode(UINT(wParam), scan, state, &buffer, 8, 0)
            chars = n > 0 ? String(decoding: buffer[0..<Int(n)], as: UTF16.self) : ""
            state[Int(VK_CONTROL)] = 0; state[Int(VK_MENU)] = 0; state[Int(VK_LCONTROL)] = 0; state[Int(VK_RCONTROL)] = 0
            state[Int(VK_LMENU)] = 0; state[Int(VK_RMENU)] = 0
            var buffer2 = [WCHAR](repeating: 0, count: 8)
            let n2 = ToUnicode(UINT(wParam), scan, state, &buffer2, 8, 0)
            plain = n2 > 0 ? String(decoding: buffer2[0..<Int(n2)], as: UTF16.self) : chars
            // Control+letter yields a control character from ToUnicode; AppKit reports the letter.
            if plain.unicodeScalars.count == 1, let v = plain.unicodeScalars.first?.value, v < 0x20, vk >= 0x41, vk <= 0x5A {
                plain = String(UnicodeScalar(UInt8(vk) + 32))   // lowercase letter
            }
            if vk == VK_SHIFT || vk == VK_CONTROL || vk == VK_MENU || vk == VK_LWIN || vk == VK_RWIN || vk == VK_CAPITAL {
                let e = NSEvent(type: .flagsChanged, location: .zero, modifierFlags: modifierFlags(), timestamp: timestamp(), windowNumber: windowNumber())
                owner?.platformWindowDispatch(e)
                return
            }
        }
        let isRepeat = (lParam & 0x4000_0000) != 0
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifierFlags(), timestamp: timestamp(),
                                 windowNumber: windowNumber(), context: nil, characters: chars,
                                 charactersIgnoringModifiers: plain, isARepeat: isRepeat, keyCode: keyCode)!
        owner?.platformWindowDispatch(e)
    }

    // MARK: Input methods (IME)

    /// `APPKITWIN_IME_LAYOUT=00000411` (a keyboard layout identifier: 00000411 is Japanese)
    /// activates that layout for this thread and opens its IME in native conversion mode
    /// on the focused window. A test hook for machines whose input settings cannot be
    /// switched by hand; it changes nothing outside the process.
    private func activateTestInputMethodIfRequested() {
        guard let hwnd, let id = ProcessInfo.processInfo.environment["APPKITWIN_IME_LAYOUT"], !id.isEmpty else { return }
        let layout = id.withCString(encodedAs: UTF16.self) { LoadKeyboardLayoutW($0, 0) }
        let loadError = GetLastError()
        // Activate for the whole process (every thread), then ask the window to switch its
        // input language the way the language bar would.
        let activated = layout.flatMap { ActivateKeyboardLayout($0, UINT(KLF_SETFORPROCESS)) }
        if let layout { PostMessageW(hwnd, UINT(WM_INPUTLANGCHANGEREQUEST), 0, LPARAM(Int(bitPattern: layout)) ) }
        let current = GetKeyboardLayout(0)
        if NSView._traceInvalidation {
            NSView._trace("ime layout '\(id)': loaded \(layout.map { String(Int(bitPattern: $0), radix: 16) } ?? "nil") (error \(loadError)), previous \(activated.map { String(Int(bitPattern: $0), radix: 16) } ?? "nil"), thread now \(String(Int(bitPattern: current), radix: 16))")
        }
        guard layout != nil, let himc = ImmGetContext(hwnd) else { return }
        defer { _ = ImmReleaseContext(hwnd, himc) }
        let opened = ImmSetOpenStatus(himc, true)
        // Native (kana) input, full-width characters: the Hiragana mode of Microsoft IME.
        let mode = ImmSetConversionStatus(himc, DWORD(IME_CMODE_NATIVE | IME_CMODE_FULLSHAPE), DWORD(IME_SMODE_PHRASEPREDICT))
        if NSView._traceInvalidation { NSView._trace("ime open \(opened) conversion \(mode) status \(ImmGetOpenStatus(himc))") }
    }

    /// The composition string of one kind (`GCS_COMPSTR`, `GCS_RESULTSTR`) as text.
    private func compositionString(_ himc: HIMC, _ kind: DWORD) -> String {
        let bytes = ImmGetCompositionStringW(himc, kind, nil, 0)
        guard bytes > 0 else { return "" }
        var buffer = [WCHAR](repeating: 0, count: Int(bytes) / 2)
        let got = buffer.withUnsafeMutableBytes { ImmGetCompositionStringW(himc, kind, $0.baseAddress, DWORD(bytes)) }
        guard got > 0 else { return "" }
        return String(decoding: buffer[0..<Int(got) / 2], as: UTF16.self)
    }

    /// Puts the input method's (suppressed) composition window and its candidate list at the
    /// marked text or caret rectangle, so candidates pop up under the text being composed.
    private func positionInputMethodWindows(_ input: PlatformTextInput) {
        guard let hwnd, let rect = input.markedRect(), let himc = ImmGetContext(hwnd) else { return }
        defer { _ = ImmReleaseContext(hwnd, himc) }
        let h = contentSize.height
        let x = Int32((rect.minX * scale).rounded(.down))
        let top = Int32(((h - rect.maxY) * scale).rounded(.down))
        let bottom = Int32(((h - rect.minY) * scale).rounded(.up))
        var composition = COMPOSITIONFORM(dwStyle: DWORD(CFS_POINT), ptCurrentPos: POINT(x: x, y: top), rcArea: RECT())
        _ = ImmSetCompositionWindow(himc, &composition)
        var candidates = CANDIDATEFORM(dwIndex: 0, dwStyle: DWORD(CFS_CANDIDATEPOS), ptCurrentPos: POINT(x: x, y: bottom), rcArea: RECT())
        _ = ImmSetCandidateWindow(himc, &candidates)
    }

    // MARK: Gestures

    /// Ctrl+wheel notches become a magnify gesture: beginGesture on the first notch, a
    /// magnify per notch (10% each), endGesture once notches stop for 300 ms.
    private func magnifyFromWheel(delta: CGFloat, at point: NSPoint, flags: NSEvent.ModifierFlags) {
        if !wheelGestureActive {
            wheelGestureActive = true
            wheelGesturePoint = point
            owner?.platformWindowDispatch(NSEvent._gestureEvent(type: .beginGesture, location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber()))
        }
        wheelGesturePoint = point
        let e = NSEvent._gestureEvent(type: .magnify, location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber(),
                                      magnification: delta * 0.1, phase: .changed)
        owner?.platformWindowDispatch(e)
        if let hwnd { _ = SetTimer(hwnd, Win32Window.wheelGestureTimer, 300, nil) }
    }

    private func endWheelGesture() {
        guard wheelGestureActive else { return }
        wheelGestureActive = false
        owner?.platformWindowDispatch(NSEvent._gestureEvent(type: .endGesture, location: wheelGesturePoint, modifierFlags: modifierFlags(), timestamp: timestamp(), windowNumber: windowNumber()))
    }

    /// WM_GESTURE (touch screens): zoom → magnify, rotate → rotate, pan → precise scroll
    /// events with phases; GF_BEGIN/GF_END bracket them with beginGesture/endGesture.
    private func handleGesture(_ lParam: LPARAM) -> Bool {
        var g = CD2DGesture()
        guard cd2d_gesture_decode(Int(lParam), &g) else { return false }
        let point = contentPoint(screenX: g.x, screenY: g.y)
        let flags = modifierFlags()
        let s = scale
        func send(_ e: NSEvent) { owner?.platformWindowDispatch(e) }
        switch g.id {
        case 1: // GID_BEGIN
            gestureActive = true
            send(NSEvent._gestureEvent(type: .beginGesture, location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber()))
        case 2: // GID_END
            gestureActive = false
            send(NSEvent._gestureEvent(type: .endGesture, location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber()))
        case 3: // GID_ZOOM: ullArguments is the distance between the fingers
            let distance = Double(g.argument)
            if g.begin { gestureZoomDistance = distance; return true }
            guard gestureZoomDistance > 0 else { gestureZoomDistance = distance; return true }
            let magnification = CGFloat((distance - gestureZoomDistance) / gestureZoomDistance)
            gestureZoomDistance = distance
            send(NSEvent._gestureEvent(type: .magnify, location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber(),
                                       magnification: magnification, phase: g.end ? .ended : .changed))
        case 5: // GID_ROTATE: cumulative angle in radians, counterclockwise positive
            if g.begin { gestureAngle = g.angle; return true }
            let delta = Float((g.angle - gestureAngle) * 180 / .pi)
            gestureAngle = g.angle
            send(NSEvent._gestureEvent(type: .rotate, location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber(),
                                       rotation: delta, phase: g.end ? .ended : .changed))
        case 4: // GID_PAN: a touch scroll with precise deltas (finger down moves content down)
            if g.begin {
                gesturePanPoint = POINT(x: g.x, y: g.y)
                send(NSEvent._scrollEvent(location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber(),
                                          deltaX: 0, deltaY: 0, precise: true, phase: .began))
                return true
            }
            let dx = CGFloat(g.x - gesturePanPoint.x) / s, dy = CGFloat(g.y - gesturePanPoint.y) / s
            gesturePanPoint = POINT(x: g.x, y: g.y)
            send(NSEvent._scrollEvent(location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber(),
                                      deltaX: dx, deltaY: dy, precise: true, phase: g.end ? .ended : .changed,
                                      momentumPhase: g.inertia ? .changed : []))
        case 7: // GID_TWOFINGERTAP → smart magnify, as a two-finger double tap does on macOS
            send(NSEvent._gestureEvent(type: .smartMagnify, location: point, modifierFlags: flags, timestamp: timestamp(), windowNumber: windowNumber()))
        default:
            return false     // GID_PRESSANDTAP and unknown ids: let DefWindowProc handle them
        }
        return true
    }

    // MARK: Window procedure

    fileprivate func handle(_ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        if NSView._traceInvalidation, _styleMask.contains(.nonactivatingPanel) {
            // Raw mouse traffic of pop-up (menu) windows, for the cases where the tracker sees nothing.
            switch Int32(msg) {
            case WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_RBUTTONDOWN, WM_RBUTTONUP, WM_NCHITTEST, WM_NCMOUSEMOVE,
                 WM_NCLBUTTONDOWN, WM_NCLBUTTONUP, WM_MOUSEACTIVATE, WM_SETCURSOR, WM_CAPTURECHANGED, WM_MOUSELEAVE, WM_ACTIVATE, WM_SHOWWINDOW, WM_WINDOWPOSCHANGED:
                NSView._trace("win32 popup msg 0x\(String(msg, radix: 16)) wParam \(wParam) lParam \(Int(bitPattern: UInt(lParam))) owner \(owner == nil ? "nil" : "set")")
            default: break
            }
        }
        switch Int32(msg) {
        case WM_ENTERSIZEMOVE:
            // DefWindowProc runs its own message loop while the user drags or resizes the
            // window, so the backend's pump (which fires animation frames) is not reached:
            // a timer fires them (display links, MTKView) until the loop ends.
            if let hwnd { _ = SetTimer(hwnd, Win32Window.sizeMoveTimer, 16, nil) }
            return nil
        case WM_EXITSIZEMOVE:
            if let hwnd { _ = KillTimer(hwnd, Win32Window.sizeMoveTimer) }
            return nil
        case WM_TIMER:
            guard wParam == Win32Window.sizeMoveTimer else { return nil }
            backend.fireFrameIfDue()
            return 0
        case WM_PAINT:
            paint()
            return 0
        case WM_ERASEBKGND:
            return 1
        case WM_SIZE:
            // Minimised (SIZE_MINIMIZED): the client area is 0x0 and the HWND moves off
            // screen; AppKit keeps the frame and content of a miniaturised window, so the
            // frame is not changed (and the content view does not collapse to zero); the
            // owner hears the minimise, whether `miniaturize()` or the taskbar asked for it.
            if wParam == 1 {
                if !reportedIconic { reportedIconic = true; owner?.platformWindowDidMiniaturize() }
                return 0
            }
            if let rt = renderTarget {
                cd2d_target_resize(rt, UInt32(lParam & 0xFFFF), UInt32((lParam >> 16) & 0xFFFF))
            }
            frameBeforeMinimize = frame
            owner?.platformWindowDidChangeFrame(frame)
            if reportedIconic { reportedIconic = false; owner?.platformWindowDidDeminiaturize() }
            checkPresentationMonitor()
            return 0
        case WM_MOVE:
            if let hwnd, IsIconic(hwnd) { return 0 }
            frameBeforeMinimize = frame
            owner?.platformWindowDidChangeFrame(frame)
            checkPresentationMonitor()
            return 0
        case WM_DISPLAYCHANGE:
            // Monitors came, went or changed mode (HDR toggled): what the shim knows
            // about them is stale.
            cd2d_display_hdr_invalidate()
            checkPresentationMonitor(force: true)
            return nil
        case WM_DPICHANGED:
            // Keep the content size in points exact: size the frame from the point size at
            // the new DPI rather than taking the suggested rect's size (which rounds).
            let pointSize = contentSize
            dpi = UINT(wParam & 0xFFFF)
            if let rt = renderTarget {
                cd2d_target_set_dpi(rt, Float(dpi))
                // The content size in points is unchanged, so no scene commit follows: the
                // hosted tree is re-placed and re-rasterised at the new scale here.
                if let scene = hostedScene, compositionTree != nil { _ = applyLayerScene(scene, to: rt) }
            }
            if let suggested = UnsafePointer<RECT>(bitPattern: Int(lParam)), let hwnd {
                let r = suggested.pointee
                let i = nonClientInsets(dpi: dpi)
                let width = Int32((pointSize.width * scale).rounded()) + i.left + i.right
                let height = Int32((pointSize.height * scale).rounded()) + i.top + i.bottom
                SetWindowPos(hwnd, nil, r.left, r.top, width, height, UINT(SWP_NOZORDER | SWP_NOACTIVATE))
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
        case WM_NCCALCSIZE:
            // Custom frame: the client area is the whole window, so no caption or border
            // is drawn (the DWM shadow and corners survive through the extended frame).
            // Maximised, the window overhangs the monitor by its frame; keep content on screen.
            guard usesCustomFrame else { return nil }
            let i = nonClientInsets(dpi: dpi)
            func inset(_ r: inout RECT) { r.left += i.left; r.top += i.top; r.right -= i.right; r.bottom -= i.bottom }
            if wParam != 0, let params = UnsafeMutablePointer<NCCALCSIZE_PARAMS>(bitPattern: Int(lParam)) {
                inset(&params.pointee.rgrc.0)
            } else if wParam == 0, let rect = UnsafeMutablePointer<RECT>(bitPattern: Int(lParam)) {
                inset(&rect.pointee)
            }
            return 0
        case WM_NCHITTEST:
            guard let hwnd, usesCustomFrame || _chrome.movableByBackground else { return nil }
            var pt = POINT(x: Int32(Int16(truncatingIfNeeded: lParam & 0xFFFF)), y: Int32(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF)))
            if usesCustomFrame {
                // Resize bands (8 px at 96 dpi) along the edges of resizable, non-maximised windows.
                var client = RECT()
                GetClientRect(hwnd, &client)
                ScreenToClient(hwnd, &pt)
                if isResizable, !IsZoomed(hwnd) {
                    let band = Int32((8 * scale).rounded())
                    let left = pt.x < client.left + band, right = pt.x >= client.right - band
                    let top = pt.y < client.top + band, bottom = pt.y >= client.bottom - band
                    if top && left { return LRESULT(HTTOPLEFT) }
                    if top && right { return LRESULT(HTTOPRIGHT) }
                    if bottom && left { return LRESULT(HTBOTTOMLEFT) }
                    if bottom && right { return LRESULT(HTBOTTOMRIGHT) }
                    if left { return LRESULT(HTLEFT) }
                    if right { return LRESULT(HTRIGHT) }
                    if top { return LRESULT(HTTOP) }
                    if bottom { return LRESULT(HTBOTTOM) }
                }
                if pt.x < client.left || pt.x >= client.right || pt.y < client.top || pt.y >= client.bottom { return LRESULT(HTNOWHERE) }
            } else {
                // System frame: only client points are ours to reclassify as caption.
                let def = DefWindowProcW(hwnd, msg, wParam, lParam)
                if def != LRESULT(HTCLIENT) { return def }
                ScreenToClient(hwnd, &pt)
            }
            // NSWindow decides: caption when movable by background or in the title bar
            // band of content that extends into it, unless a control is under the mouse.
            let region = owner?.platformWindowHitTest(contentPoint(x: pt.x, y: pt.y)) ?? .client
            if NSView._traceInvalidation, _styleMask.contains(.nonactivatingPanel) { NSView._trace("win32 popup nchittest client \(pt.x),\(pt.y) -> \(region)") }
            return LRESULT(region == .caption ? HTCAPTION : HTCLIENT)
        case WM_CLOSE:
            // Route through NSWindow.close() so delegates, notifications and the
            // last-window-closed check run; NSWindow then calls close() here.
            if NSView._traceInvalidation { NSView._trace("win32 WM_CLOSE '\(title)' owner \(owner == nil ? "nil" : "set")") }
            if owner?.platformWindowShouldClose() ?? true {
                if let owner { owner.platformWindowWillClose() } else { close() }
            }
            return 0
        case WM_SETCURSOR:
            if (lParam & 0xFFFF) == HTCLIENT {
                SetCursor(backend.currentCursor)
                return 1
            }
            return nil
        case WM_INITMENUPOPUP:
            if let menu = HMENU(bitPattern: Int(wParam)) { backend.menuBar.willOpen(menu) }
            return 0
        case WM_COMMAND:
            if (wParam >> 16) & 0xFFFF == 0, lParam == 0, backend.menuBar.command(Int(wParam & 0xFFFF)) { return 0 }
            return nil
        case WM_GETOBJECT:
            return accessibilityHandleGetObject(wParam, lParam)
        case WM_DESTROY:
            if NSView._traceInvalidation { NSView._trace("win32 WM_DESTROY '\(title)' destroying \(destroying)") }
            accessibilityWindowDestroyed()
            if let hwnd { backend.win32DragDrop.revoke(hwnd); backend.menuBar.windowDestroyed(hwnd) }
            backend.unregister(self)
            tearDownLayerHosting()
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
            activateTestInputMethodIfRequested()
            return nil      // DefWindowProc activates the input method context for the window
        case WM_KILLFOCUS:
            isKey = false
            owner?.platformWindowDidResignKey()
            return nil      // ... and deactivates it
        case WM_MOUSEACTIVATE:
            // Pop-up windows take clicks without taking activation from their owner.
            if _styleMask.contains(.nonactivatingPanel) { return LRESULT(MA_NOACTIVATE) }
            return nil
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
            let flags = modifierFlags()
            if !horizontal, flags.contains(.command) {   // the Ctrl key (reported as Command on this port)
                // Ctrl+wheel is how Windows delivers a precision-touchpad pinch (and what
                // mouse users expect to zoom with): a magnify gesture, not a scroll.
                magnifyFromWheel(delta: delta, at: contentPoint(x: pt.x, y: pt.y), flags: flags.subtracting(.command))
                return 0
            }
            let e = NSEvent._scrollEvent(location: contentPoint(x: pt.x, y: pt.y), modifierFlags: flags, timestamp: timestamp(),
                                         windowNumber: windowNumber(), deltaX: horizontal ? -delta : 0, deltaY: horizontal ? 0 : delta, precise: false)
            owner?.platformWindowDispatch(e)
            return 0
        case WM_GESTURE:
            return handleGesture(lParam) ? 0 : nil
        case WM_TIMER where wParam == Win32Window.wheelGestureTimer:
            if let hwnd { _ = KillTimer(hwnd, Win32Window.wheelGestureTimer) }
            endWheelGesture()
            return 0
        case WM_IME_STARTCOMPOSITION:
            // The text view draws the composition (marked text) itself, so the input
            // method's own composition window is suppressed (no DefWindowProc) and its
            // candidate list is placed by the caret. Without a text view the default applies.
            guard let input = owner?.platformWindowTextInput() else { composing = false; return nil }
            composing = true
            positionInputMethodWindows(input)
            return 0
        case WM_IME_COMPOSITION:
            guard composing, let hwnd, let input = owner?.platformWindowTextInput(), let himc = ImmGetContext(hwnd) else { return nil }
            defer { _ = ImmReleaseContext(hwnd, himc) }
            let flags = DWORD(truncatingIfNeeded: lParam)
            var handled = false
            if flags & DWORD(GCS_RESULTSTR) != 0 {
                // Committed text (replaces the marked text); a new composition may follow below.
                let result = compositionString(himc, DWORD(GCS_RESULTSTR))
                if !result.isEmpty { input.insertText(result) }
                handled = true
            }
            if flags & DWORD(GCS_COMPSTR) != 0 {
                let composition = compositionString(himc, DWORD(GCS_COMPSTR))
                var cursor = composition.utf16.count
                if flags & DWORD(GCS_CURSORPOS) != 0 {
                    cursor = max(0, min(cursor, Int(ImmGetCompositionStringW(himc, DWORD(GCS_CURSORPOS), nil, 0))))
                }
                input.setMarkedText(composition, NSRange(location: cursor, length: 0))
                positionInputMethodWindows(input)
                handled = true
            }
            return handled ? 0 : nil
        case WM_IME_ENDCOMPOSITION:
            composing = false
            if let input = owner?.platformWindowTextInput(), input.hasMarkedText() { input.unmarkText() }
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
