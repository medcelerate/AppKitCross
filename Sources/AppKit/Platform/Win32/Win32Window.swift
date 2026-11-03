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
    var minSize = NSSize(width: 0, height: 0)
    var maxSize = NSSize(width: 100_000, height: 100_000)

    init(backend: Win32Backend, owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) {
        self.backend = backend
        self.owner = owner
        self.ownerWantsMenuBar = owner.platformWantsMenuBar
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
        backend.register(self)
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
    var wantsMenuBar: Bool { _styleMask.contains(.titled) && !_styleMask.contains(.utilityWindow) && ownerWantsMenuBar && !usesCustomFrame }
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

    // dwmapi.h values (the enums import awkwardly); Windows 11 22H2+ for the backdrop.
    private static let dwmwaNCRenderingPolicy: DWORD = 2
    private static let dwmwaUseImmersiveDarkMode: DWORD = 20
    private static let dwmwaWindowCornerPreference: DWORD = 33
    private static let dwmwaSystemBackdropType: DWORD = 38
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
        // covers the frame by extending the frame one pixel into the client area.
        var margins = MARGINS(cxLeftWidth: 0, cxRightWidth: 0, cyTopHeight: usesCustomFrame ? 1 : 0, cyBottomHeight: 0)
        _ = DwmExtendFrameIntoClientArea(hwnd, &margins)
        if previous.map({ $0.extendsContentIntoTitleBar != _chrome.extendsContentIntoTitleBar }) ?? false {
            SetWindowPos(hwnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED))
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
            // WM_NCCALCSIZE re-runs for the new mask (custom frame or system caption).
            SetWindowPos(hwnd, nil, 0, 0, 0, 0, UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED))
            applyChrome(previous: _chrome)
        }
    }

    var backingScaleFactor: CGFloat { scale }

    var isVisible: Bool { hwnd.map { IsWindowVisible($0) } ?? false }

    /// The frame before the window was minimised: a minimised HWND sits at
    /// (-32000, -32000) with a tiny rect, while AppKit keeps a miniaturised window's frame.
    private var frameBeforeMinimize: NSRect?

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
            guard let hwnd, IsZoomed(hwnd), isResizable else { return (0, 0, 0, 0) }
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
            if _chrome.isTransparent || hostedScene != nil {
                rt = cd2d_target_create_composition_swapchain(factory, UnsafeMutableRawPointer(hwnd), width, height, Float(dpi))
            }
            if rt == nil {
                rt = cd2d_target_create_swapchain(factory, UnsafeMutableRawPointer(hwnd), width, height, Float(dpi))
            }
        }
        if rt == nil {
            // Legacy path, or no usable D3D11/DXGI device: the HWND render target still works.
            rt = cd2d_target_create_hwnd(factory, UnsafeMutableRawPointer(hwnd), width, height, Float(dpi))
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
        let dirty = NSRect(x: CGFloat(ps.rcPaint.left) / scale,
                           y: size.height - CGFloat(ps.rcPaint.bottom) / scale,
                           width: CGFloat(ps.rcPaint.right - ps.rcPaint.left) / scale,
                           height: CGFloat(ps.rcPaint.bottom - ps.rcPaint.top) / scale)
        if NSView._traceInvalidation { NSView._trace("win32 paint dirty \(ps.rcPaint.left),\(ps.rcPaint.top)-\(ps.rcPaint.right),\(ps.rcPaint.bottom) px of \(Int(size.width * scale))x\(Int(size.height * scale))") }
        painting = true
        defer { painting = false }
        cd2d_target_begin_draw(rt)
        if cd2d_target_is_swapchain(rt), !dirty.isEmpty {
            cd2d_target_set_dirty(rt, ps.rcPaint.left, ps.rcPaint.top, ps.rcPaint.right, ps.rcPaint.bottom)
        }
        // A transparent window starts every frame fully transparent so unpainted areas
        // show the backdrop; an opaque window fills its background in NSWindow.
        if cd2d_target_is_composition(rt) {
            cd2d_target_push_clip_rect(rt, Float(ps.rcPaint.left) / Float(scale), Float(ps.rcPaint.top) / Float(scale), Float(ps.rcPaint.right) / Float(scale), Float(ps.rcPaint.bottom) / Float(scale), false)
            cd2d_target_clear(rt, 0, 0, 0, 0)
            cd2d_target_pop_clip_rect(rt)
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
    private var painting = false

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
                NSView._trace("win32 scene node \(node.id) parent \(node.parent.map { String(scene.nodes[$0].id) } ?? "root") size \(Int(node.size.width))x\(Int(node.size.height)) at \(Int(t.tx)),\(Int(t.ty)) d \(t.d) clip \(node.clipsToBounds) content \(node.content != nil) \(node.name ?? "")")
            }
            cd2d_comp_tree_set_transform(tree, id, Float(t.a), Float(t.b), Float(t.c), Float(t.d), Float(t.tx * s), Float(t.ty * s))
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
        case WM_PAINT:
            paint()
            return 0
        case WM_ERASEBKGND:
            return 1
        case WM_SIZE:
            // Minimised (SIZE_MINIMIZED): the client area is 0x0 and the HWND moves off
            // screen; AppKit keeps the frame and content of a miniaturised window, so the
            // owner is not told (and the content view does not collapse to zero).
            if wParam == 1 { return 0 }
            if let rt = renderTarget {
                cd2d_target_resize(rt, UInt32(lParam & 0xFFFF), UInt32((lParam >> 16) & 0xFFFF))
            }
            frameBeforeMinimize = frame
            owner?.platformWindowDidChangeFrame(frame)
            return 0
        case WM_MOVE:
            if let hwnd, IsIconic(hwnd) { return 0 }
            frameBeforeMinimize = frame
            owner?.platformWindowDidChangeFrame(frame)
            return 0
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
        case WM_DESTROY:
            if NSView._traceInvalidation { NSView._trace("win32 WM_DESTROY '\(title)' destroying \(destroying)") }
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
            let e = NSEvent._scrollEvent(location: contentPoint(x: pt.x, y: pt.y), modifierFlags: modifierFlags(), timestamp: timestamp(),
                                         windowNumber: windowNumber(), deltaX: horizontal ? -delta : 0, deltaY: horizontal ? 0 : delta, precise: false)
            owner?.platformWindowDispatch(e)
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
