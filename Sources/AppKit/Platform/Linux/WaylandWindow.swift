// An xdg-shell toplevel painted through Cairo into wl_shm buffers.
//
// The content is drawn into a persistent Cairo image surface exactly as `LinuxWindow`
// does (through `CGContext(cairo:)`), then copied into one of two shared-memory buffers
// that the compositor releases when it is done reading. Wayland has no window positions:
// the frame origin is whatever the core last set, only the size follows the compositor.
//
// Decorations (ADR-0015): the window asks xdg-decoration for a server-side frame and
// takes what the compositor answers; without the protocol, or when the answer is "client
// side", it decorates itself (`ClientSideDecorationLayout`): the surface grows a
// transparent shadow margin around the frame, the frame gets a title band above the
// content that the owner paints with its standard buttons, the edges and the margin become
// resize handles, and `xdg_surface.set_window_geometry` tells the compositor where the
// frame is so it sizes and places the window by its visible rectangle.

#if os(Linux)
import Foundation
import Glibc
import CoreGraphics
import CCairo
import CWayland

@MainActor
final class WaylandWindow: PlatformWindow, AtspiWindow {
    private unowned let backend: WaylandBackend
    private weak var owner: PlatformWindowOwner?
    private(set) var surface: OpaquePointer?      // wl_surface*
    private var xdgSurface: OpaquePointer?        // xdg_surface*
    private var toplevel: OpaquePointer?          // xdg_toplevel*
    private var decoration: OpaquePointer?        // zxdg_toplevel_decoration_v1*
    private var frameCallback: OpaquePointer?     // wl_callback*
    private var _styleMask: NSWindow.StyleMask
    private var _frame: NSRect                    // AppKit points, bottom-left origin
    private(set) var isVisible = false
    private(set) var isKey = false
    private var _title = ""
    private var _minSize = NSSize(width: 0, height: 0)
    private var _maxSize = NSSize(width: 100_000, height: 100_000)
    private var _chrome = PlatformWindowChrome()
    private var destroying = false
    private var configured = false
    private var pendingSize: NSSize? = nil
    // Decorations
    /// The compositor's xdg-decoration answer (ZXDG_TOPLEVEL_DECORATION_V1_MODE_*), nil until it arrives.
    private var serverMode: UInt32? = nil
    private var maximized = false
    private var fullScreen = false
    private var tiled = false
    private var activated = false
    /// The layout the surface, buffers and hints were last made for.
    private var appliedLayout: ClientSideDecorationLayout
    private var sentGeometry: NSRect? = nil
    private var decorationsDirty = true
    private var hoverRegion: ClientSideDecorationRegion = .outside
    private var enteredOutputs: [WaylandOutput] = []
    private(set) var scale = 1
    private var pressedButtons = 0
    private var lastClickTime: UInt32 = 0
    private var clickCount = 1

    // Painting
    private final class Buffer {
        var buffer: OpaquePointer?               // wl_buffer*
        var pool: OpaquePointer?                 // wl_shm_pool*
        var data: UnsafeMutableRawPointer?
        var length = 0
        var surface: OpaquePointer?              // cairo image surface over `data`
        var busy = false
        var width = 0, height = 0
        func release() {
            if let s = surface { cairo_surface_destroy(s) }
            if let b = buffer { wl_buffer_destroy(b) }
            if let p = pool { wl_shm_pool_destroy(p) }
            if let d = data { munmap(d, length) }
            surface = nil; buffer = nil; pool = nil; data = nil
        }
    }
    private var buffers: [Buffer] = []
    private var backing: OpaquePointer?          // cairo image surface, window size in pixels
    private var backingCairo: OpaquePointer?     // cairo_t on the backing surface
    private var dirty: NSRect? = nil             // content points
    /// Subsurfaces that GPU swap chains present into (ADR-0012).
    private var presentationSurfaces: [WaylandPresentationSurface] = []
    var needsPaint: Bool { dirty != nil && isVisible && configured && !destroying }

    var backingScaleFactor: CGFloat { CGFloat(scale) }
    var opaque: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    static func from(_ data: UnsafeMutableRawPointer?) -> WaylandWindow? {
        data.map { Unmanaged<WaylandWindow>.fromOpaque($0).takeUnretainedValue() }
    }

    init(backend: WaylandBackend, owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) {
        self.backend = backend
        self.owner = owner
        _styleMask = styleMask
        _frame = contentRect
        appliedLayout = ClientSideDecorationLayout(frameSize: contentRect.size)
        // The frame is the content plus the band the package will draw, when the compositor
        // is not expected to decorate (its answer, if it has the protocol, may still change that).
        _frame = NSRect(origin: contentRect.origin, size: ClientSideDecorationLayout.frameSize(forContentSize: contentRect.size, titleBarHeight: layout.titleBarHeight))
        appliedLayout = layout
        createToplevel()
        backend.register(self)
        applyDecorationMode()
        applySizeHints()
    }

    /// A fresh surface with the xdg_toplevel role (at creation, and again when a sheet is
    /// detached: a surface's role is permanent, so the subsurface cannot become a toplevel).
    private func createToplevel() {
        surface = wl_compositor_create_surface(backend.compositor)
        wl_surface_add_listener(surface, WaylandWindow.surfaceListener, opaque)
        xdgSurface = xdg_wm_base_get_xdg_surface(backend.wmBase, surface)
        xdg_surface_add_listener(xdgSurface, WaylandWindow.xdgSurfaceListener, opaque)
        toplevel = xdg_surface_get_toplevel(xdgSurface)
        xdg_toplevel_add_listener(toplevel, WaylandWindow.toplevelListener, opaque)
        xdg_toplevel_set_app_id(toplevel, "AppKitCross")
        if !_title.isEmpty { xdg_toplevel_set_title(toplevel, _title) }
        if let manager = backend.decorationManager {
            decoration = zxdg_decoration_manager_v1_get_toplevel_decoration(manager, toplevel)
            zxdg_toplevel_decoration_v1_add_listener(decoration, WaylandWindow.decorationListener, opaque)
        }
        configured = false
        sentGeometry = nil
        serverMode = nil
    }

    /// Destroys the surface and whatever role objects it has (toplevel or subsurface), with
    /// the buffers attached to it; the window is hidden when this runs.
    private func destroyRole() {
        if let c = frameCallback { wl_callback_destroy(c); frameCallback = nil }
        releaseBacking()
        for b in buffers { b.release() }
        buffers.removeAll()
        if let d = decoration { zxdg_toplevel_decoration_v1_destroy(d); decoration = nil }
        if let t = toplevel { xdg_toplevel_destroy(t); toplevel = nil }
        if let x = xdgSurface { xdg_surface_destroy(x); xdgSurface = nil }
        if let sub = subsurface { wl_subsurface_destroy(sub); subsurface = nil }
        if let s = surface { wl_surface_destroy(s); surface = nil }
        configured = false
        sentGeometry = nil
    }

    // MARK: Sheets (ADR-0019)

    /// The window whose surface this one is a subsurface of while attached as a sheet.
    private(set) weak var sheetParent: WaylandWindow?
    private var subsurface: OpaquePointer?        // wl_subsurface* while attached
    private var styleBeforeSheet: NSWindow.StyleMask?

    /// A sheet is a `wl_subsurface` of its parent's surface rather than an `xdg_popup`
    /// (a popup is a menu's model: dismissed by a click outside, keyboard only under a
    /// grab that needs an input serial, placed by the compositor). The subsurface is part
    /// of the parent's surface tree: placed at the core's frame relative to the parent,
    /// composited above it, mapped, minimised and closed with it, listed nowhere.
    /// Desynchronised, so its own commits show as they come. Pointer events arrive on its
    /// own surface; keyboard focus stays with the parent toplevel and the core forwards
    /// the keys. The old surface goes (its role is permanent) and a new one takes the
    /// subsurface role; the window is hidden while this happens.
    func attachSheet(to parent: PlatformWindow?) {
        guard !destroying else { return }
        if let p = parent as? WaylandWindow, let parentSurface = p.surface, let subcompositor = backend.subcompositor {
            guard sheetParent !== p else { return }
            if styleBeforeSheet == nil { styleBeforeSheet = _styleMask }
            _styleMask = _styleMask.subtracting([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            destroyRole()
            sheetParent = p
            surface = wl_compositor_create_surface(backend.compositor)
            wl_surface_add_listener(surface, WaylandWindow.surfaceListener, opaque)
            subsurface = wl_subcompositor_get_subsurface(subcompositor, surface, parentSurface)
            wl_subsurface_set_desync(subsurface)
            configured = true                      // no configure for a subsurface: paint when shown
            if scale != p.scale { scale = p.scale; owner?.platformWindowDidChangeBackingScaleFactor(CGFloat(scale)) }
            if NSView._traceInvalidation { NSView._trace("wayland sheet '\(_title)' subsurface of '\(p._title)'") }
        } else {
            guard sheetParent != nil else { return }
            destroyRole()
            sheetParent = nil
            if let s = styleBeforeSheet { styleBeforeSheet = nil; _styleMask = s }
            createToplevel()
            applyDecorationMode()
            if NSView._traceInvalidation { NSView._trace("wayland sheet '\(_title)' detached") }
        }
        appliedLayout = layout
        decorationsDirty = true
        dirty = NSRect(origin: .zero, size: _frame.size)
        applySizeHints()
        placeSubsurface()
    }

    /// Positions the subsurface at the frame, relative to the parent's surface: the frame
    /// origins are in the same (nominal) screen space, so the difference is the offset
    /// within the parent's window, which the parent maps into its surface. The position
    /// applies with the parent's next commit, so the parent commits.
    private func placeSubsurface() {
        guard let sub = subsurface, let p = sheetParent, let parentSurface = p.surface else { return }
        let inParent = NSRect(x: _frame.minX - p._frame.minX, y: _frame.minY - p._frame.minY, width: _frame.width, height: _frame.height)
        let pos = p.subsurfacePosition(for: inParent)
        wl_subsurface_set_position(sub, pos.x, pos.y)
        wl_surface_commit(parentSurface)
        wl_display_flush(backend.display)
    }

    // MARK: Listeners

    private static let surfaceListener = WaylandBackend.listener(wl_surface_listener(
        enter: { data, _, output in
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.surfaceEntered(output) }
        },
        leave: { data, _, output in
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.surfaceLeft(output) }
        },
        preferred_buffer_scale: { _, _, _ in },          // wl_surface v6; never sent at the version bound here
        preferred_buffer_transform: { _, _, _ in }))

    private static let xdgSurfaceListener = WaylandBackend.listener(xdg_surface_listener(
        configure: { data, xdgSurface, serial in
            xdg_surface_ack_configure(xdgSurface, serial)
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.configured(serial: serial) }
        }))

    private static let toplevelListener = WaylandBackend.listener(xdg_toplevel_listener(
        configure: { data, _, width, height, states in
            guard let w = WaylandWindow.from(data) else { return }
            var list: [UInt32] = []
            if let states, let base = states.pointee.data {
                let count = states.pointee.size / MemoryLayout<UInt32>.size
                list = Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt32.self), count: count))
            }
            MainActor.assumeIsolated { w.toplevelConfigure(width: Int(width), height: Int(height), states: list) }
        },
        close: { data, _ in
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.closeRequested() }
        },
        configure_bounds: { _, _, _, _ in },
        wm_capabilities: { _, _, _ in }))

    private static let decorationListener = WaylandBackend.listener(zxdg_toplevel_decoration_v1_listener(
        configure: { data, _, mode in
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.decorationConfigured(mode: mode) }
        }))

    private static let frameListener = WaylandBackend.listener(wl_callback_listener(
        done: { data, callback, _ in
            wl_callback_destroy(callback)
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.frameDone(callback) }
        }))

    private static let bufferListener = WaylandBackend.listener(wl_buffer_listener(
        release: { data, buffer in
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.bufferReleased(buffer) }
        }))

    // MARK: Configure

    /// The size is the window geometry (frame: band plus content) in points; 0 leaves the
    /// size to the client. The states say whether the compositor has the window maximised,
    /// tiled or full screen (no shadow margin then) and whether it is the active one.
    private func toplevelConfigure(width: Int, height: Int, states: [UInt32]) {
        if NSView._traceInvalidation { NSView._trace("wayland configure '\(_title)' \(width)x\(height) states \(states)") }
        if width > 0 && height > 0 { pendingSize = NSSize(width: width, height: height) }
        maximized = states.contains(UInt32(XDG_TOPLEVEL_STATE_MAXIMIZED.rawValue))
        fullScreen = states.contains(UInt32(XDG_TOPLEVEL_STATE_FULLSCREEN.rawValue))
        tiled = states.contains { (UInt32(XDG_TOPLEVEL_STATE_TILED_LEFT.rawValue)...UInt32(XDG_TOPLEVEL_STATE_TILED_BOTTOM.rawValue)).contains($0) }
        activated = states.contains(UInt32(XDG_TOPLEVEL_STATE_ACTIVATED.rawValue))
    }

    private func decorationConfigured(mode: UInt32) {
        if NSView._traceInvalidation { NSView._trace("wayland decoration mode '\(_title)' \(mode == 2 ? "server" : "client") side") }
        serverMode = mode
        decorationsDidChange()
    }

    private func configured(serial: UInt32) {
        configured = true
        if let size = pendingSize {
            pendingSize = nil
            if size != _frame.size {
                _frame.size = size
                appliedLayout = layout
                releaseBacking()
                owner?.platformWindowDidChangeFrame(_frame)
            }
        }
        decorationsDidChange()
        // The compositor's "activated" is the key window on a seat without a keyboard too.
        setKey(activated || backend.keyboardFocus === self)
        dirty = NSRect(origin: .zero, size: _frame.size)
        decorationsDirty = true
        if isVisible { paintIfNeeded() }
    }

    // MARK: Decorations (ADR-0015)

    /// What the compositor was asked for: a server-side frame for titled windows whose
    /// content does not cover the title bar, unless APPKITWIN_WAYLAND_DECORATIONS says otherwise.
    private var requestsServerSide: Bool {
        if let preference = backend.decorationPreference { return preference == .server }
        return _styleMask.contains(.titled) && !contentCoversTitleBar
    }

    /// `fullSizeContentView` (from the mask, so the answer is right before the chrome arrives) or
    /// a borderless window: the content reaches the top of the frame, no band.
    private var contentCoversTitleBar: Bool { _chrome.extendsContentIntoTitleBar || _styleMask.contains(.fullSizeContentView) || !_styleMask.contains(.titled) }

    private var decorationMode: ClientSideDecorationMode {
        let granted: Bool?
        if backend.decorationManager == nil { granted = nil }
        else if let serverMode { granted = serverMode == UInt32(ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue) }
        else { granted = requestsServerSide }
        return ClientSideDecorationMode.mode(for: _styleMask, serverSideGranted: granted)
    }

    /// The decoration geometry for the current mode, states and frame.
    var layout: ClientSideDecorationLayout {
        ClientSideDecorationLayout(mode: decorationMode, styleMask: _styleMask, contentCoversTitleBar: contentCoversTitleBar,
                                   tiledOrMaximized: maximized || tiled, fullScreen: fullScreen, frameSize: _frame.size)
    }

    var hasClientSideTitleBar: Bool { layout.titleBarHeight > 0 }

    /// The mode, a state or the style changed. Before the first configure the content
    /// keeps the size the application asked for and the frame gains or loses the band; once
    /// the compositor has sized the window, its size is the frame's (window geometry) and
    /// the content gives way to the band, as a compositor that answers the decoration
    /// request only after mapping (sway for windows it floats) would otherwise keep
    /// re-imposing the old frame. The surface gains or loses its margins; the owner hears
    /// of the new frame.
    private func decorationsDidChange() {
        let old = appliedLayout
        let band = layout.titleBarHeight
        if band != old.titleBarHeight, !configured {
            _frame.size.height += band - old.titleBarHeight
        }
        let new = layout
        guard new != old else { return }
        appliedLayout = new
        releaseBacking()
        for b in buffers where !b.busy { b.release() }
        buffers.removeAll { !$0.busy }
        decorationsDirty = true
        dirty = NSRect(origin: .zero, size: _frame.size)
        applySizeHints()
        if new.frameSize != old.frameSize || new.titleBarHeight != old.titleBarHeight {
            owner?.platformWindowDidChangeFrame(_frame)
        }
    }

    /// Resize-edge cursors come from the decoration, the rest from the core's `setCursor`.
    private func updateHover(_ region: ClientSideDecorationRegion) {
        guard region != hoverRegion else { return }
        hoverRegion = region
        if case .resize(let edge) = region { backend.setDecorationCursor(edge.cursorNames) } else { backend.setDecorationCursor(nil) }
    }

    private func closeRequested() {
        if owner?.platformWindowShouldClose() ?? true {
            if let owner { owner.platformWindowWillClose() } else { close() }
        }
    }

    private func surfaceEntered(_ output: OpaquePointer?) {
        guard let o = backend.outputs.first(where: { $0.proxy == output }) else { return }
        enteredOutputs.append(o)
        outputsDidChange()
    }

    private func surfaceLeft(_ output: OpaquePointer?) {
        enteredOutputs.removeAll { $0.proxy == output }
        outputsDidChange()
    }

    func outputRemoved(_ output: WaylandOutput) {
        enteredOutputs.removeAll { $0 === output }
        outputsDidChange()
    }

    /// The buffer scale for a surface shown on `outputs`: the largest of their scales, so
    /// a window straddling a 1x and a 2x output is crisp on the 2x one (the compositor
    /// downsamples it on the other). A surface no output shows keeps its scale.
    static func scale(forOutputs outputs: [WaylandOutput], current: Int) -> Int {
        max(1, outputs.map(\.scale).max() ?? current)
    }

    /// The surface entered or left an output, or an output's scale changed: the backing
    /// and the shm buffers are dropped and the owner re-rasterises for the new scale, at
    /// the same size in points (`wl_surface.set_buffer_scale` goes out with the next frame).
    func outputsDidChange() {
        let newScale = WaylandWindow.scale(forOutputs: enteredOutputs, current: scale)
        guard newScale != scale else { return }
        scale = newScale
        releaseBacking()
        for b in buffers { b.release() }
        buffers.removeAll()
        dirty = NSRect(origin: .zero, size: _frame.size)
        owner?.platformWindowDidChangeBackingScaleFactor(CGFloat(scale))
        backend.applyCursor()
    }

    func setKey(_ key: Bool) {
        guard isKey != key else { return }
        isKey = key
        if layout.hasDecorations { decorationsDirty = true; dirty = NSRect(origin: .zero, size: _frame.size) }
        if key { owner?.platformWindowDidBecomeKey() } else { owner?.platformWindowDidResignKey() }
    }

    // MARK: PlatformWindow

    var title: String {
        get { _title }
        set {
            _title = newValue
            if let t = toplevel { xdg_toplevel_set_title(t, newValue) }
        }
    }

    var frame: NSRect {
        get { _frame }
        set {
            let resized = newValue.size != _frame.size
            let moved = newValue.origin != _frame.origin
            _frame = newValue
            if resized {
                appliedLayout = layout
                releaseBacking()
                applySizeHints()
                dirty = NSRect(origin: .zero, size: _frame.size)
                decorationsDirty = true
            }
            if subsurface != nil {
                // A sheet's frame is its place within the parent; a resize needs a buffer
                // of the new size, which the next paint attaches (the slide, ADR-0019).
                if moved || resized { placeSubsurface() }
                if resized { owner?.platformWindowDidChangeFrame(_frame) }
            }
        }
    }

    var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set { _styleMask = newValue; applyDecorationMode(); decorationsDidChange(); applySizeHints() }
    }

    var minSize: NSSize {
        get { _minSize }
        set { _minSize = newValue; applySizeHints() }
    }

    var maxSize: NSSize {
        get { _maxSize }
        set { _maxSize = newValue; applySizeHints() }
    }

    var chrome: PlatformWindowChrome {
        get { _chrome }
        set {
            let changed = newValue != _chrome
            _chrome = newValue
            applyDecorationMode()
            decorationsDidChange()
            if changed, layout.hasDecorations { decorationsDirty = true; dirty = NSRect(origin: .zero, size: _frame.size) }
        }
    }

    private func applyDecorationMode() {
        guard let decoration else { return }
        zxdg_toplevel_decoration_v1_set_mode(decoration, requestsServerSide ? UInt32(ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue)
                                                                           : UInt32(ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE.rawValue))
    }

    /// Size hints are window geometry: the content limits plus the band.
    private func applySizeHints() {
        guard let t = toplevel else { return }
        let band = layout.titleBarHeight
        var minW = _minSize.width, minH = _minSize.height + band
        var maxW = min(_maxSize.width, 100_000), maxH = min(_maxSize.height + band, 100_000)
        if !_styleMask.contains(.resizable) {
            minW = _frame.width; maxW = minW
            minH = _frame.height; maxH = minH
        }
        xdg_toplevel_set_min_size(t, Int32(minW), Int32(minH))
        xdg_toplevel_set_max_size(t, maxW >= 100_000 ? 0 : Int32(maxW), maxH >= 100_000 ? 0 : Int32(maxH))
    }

    func frameRect(forContentRect contentRect: NSRect) -> NSRect {
        NSRect(origin: contentRect.origin, size: ClientSideDecorationLayout.frameSize(forContentSize: contentRect.size, titleBarHeight: layout.titleBarHeight))
    }
    func contentRect(forFrameRect frameRect: NSRect) -> NSRect {
        NSRect(origin: frameRect.origin, size: ClientSideDecorationLayout.contentSize(forFrameSize: frameRect.size, titleBarHeight: layout.titleBarHeight))
    }

    func show() {
        guard !isVisible, let surface else { return }
        isVisible = true
        dirty = NSRect(origin: .zero, size: _frame.size)
        decorationsDirty = true
        if subsurface != nil {
            // A subsurface maps with its first buffer: paint now.
            configured = true
            paintIfNeeded()
            return
        }
        configured = false
        // Map: commit without a buffer and wait for the configure before painting.
        wl_surface_commit(surface)
        wl_display_flush(backend.display)
    }

    func hide() {
        guard isVisible, let surface else { return }
        isVisible = false
        if subsurface == nil { configured = false }
        wl_surface_attach(surface, nil, 0, 0)
        wl_surface_commit(surface)
        wl_display_flush(backend.display)
    }

    func makeKey() {
        // Wayland does not let clients take focus; the compositor focuses new toplevels.
    }

    func orderBack() {}

    private var minimized = false
    func miniaturize() {
        guard let toplevel else { return }
        xdg_toplevel_set_minimized(toplevel)
        wl_display_flush(backend.display)
        minimized = true
    }
    func deminiaturize() {
        // xdg-shell has no unminimize request; the compositor restores the window from its
        // own UI. Activation requests (xdg-activation) are the closest substitute and out of scope.
        minimized = false
    }
    /// Maximised or not follows the compositor's configure states.
    func zoom() {
        guard let toplevel else { return }
        if maximized { xdg_toplevel_unset_maximized(toplevel) } else { xdg_toplevel_set_maximized(toplevel) }
        wl_display_flush(backend.display)
    }
    var isMiniaturized: Bool { minimized }
    var isZoomed: Bool { maximized }

    // MARK: Accessibility (ADR-0013)
    var atspiOwner: PlatformWindowOwner? { owner }
    var atspiIsVisible: Bool { isVisible }
    var atspiIsKey: Bool { isKey }
    func accessibilityDidChange(_ change: PlatformAccessibilityChange) { backend.atspi?.windowDidChange(self, change) }

    func close() {
        guard !destroying else { return }
        destroying = true
        backend.unregister(self)
        for s in presentationSurfaces { s.close() }
        if let c = frameCallback { wl_callback_destroy(c); frameCallback = nil }
        releaseBacking()
        for b in buffers { b.release() }
        buffers.removeAll()
        if let d = decoration { zxdg_toplevel_decoration_v1_destroy(d); decoration = nil }
        if let t = toplevel { xdg_toplevel_destroy(t); toplevel = nil }
        if let x = xdgSurface { xdg_surface_destroy(x); xdgSurface = nil }
        if let sub = subsurface { wl_subsurface_destroy(sub); subsurface = nil }
        if let s = surface { wl_surface_destroy(s); surface = nil }
        wl_display_flush(backend.display)
        isVisible = false
    }

    func setNeedsDisplay(_ rect: NSRect?) {
        let bounds = NSRect(origin: .zero, size: _frame.size)
        if let r = rect { dirty = (dirty ?? NSRect.null).union(r).intersection(bounds) } else { dirty = bounds }
    }

    func displayIfNeeded() { if dirty != nil { paintIfNeeded() } }

    func display() {
        dirty = NSRect(origin: .zero, size: _frame.size)
        paintIfNeeded()
    }

    // MARK: Presentation surfaces (ADR-0012)

    func makePresentationSurface(frame: NSRect) -> (any PlatformPresentationSurface)? {
        guard let surface, let subcompositor = backend.subcompositor, !destroying else { return nil }
        guard let s = WaylandPresentationSurface(window: self, backend: backend, parent: surface, subcompositor: subcompositor, frame: frame) else { return nil }
        presentationSurfaces.append(s)
        return s
    }

    func presentationSurfaceClosed(_ s: WaylandPresentationSurface) {
        presentationSurfaces.removeAll { $0 === s }
        presentationSurfacesDidChange()
    }

    /// A subsurface's position is applied by the parent's next commit: repaint the window.
    func presentationSurfaceDidChange() { presentationSurfacesDidChange() }
    private func presentationSurfacesDidChange() { dirty = NSRect(origin: .zero, size: _frame.size) }

    /// Where a content rect's top-left lies in the surface (logical coordinates, y down
    /// from the surface's top: the shadow margin and the title band are above the content).
    func subsurfacePosition(for frame: NSRect) -> (x: Int32, y: Int32) {
        let layout = appliedLayout
        let m = layout.shadowMargin
        return (Int32((m + frame.minX).rounded()), Int32((m + layout.frameSize.height - frame.maxY).rounded()))
    }

    // MARK: Painting

    private var pixelWidth: Int { max(1, Int((appliedLayout.surfaceSize.width * CGFloat(scale)).rounded())) }
    private var pixelHeight: Int { max(1, Int((appliedLayout.surfaceSize.height * CGFloat(scale)).rounded())) }

    private func releaseBacking() {
        if let c = backingCairo { cairo_destroy(c) }
        if let b = backing { cairo_surface_destroy(b) }
        backingCairo = nil; backing = nil
    }

    private func ensureBacking() -> Bool {
        if backing == nil {
            backing = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(pixelWidth), Int32(pixelHeight))
            guard let b = backing else { return false }
            backingCairo = cairo_create(b)
        }
        return backingCairo != nil
    }

    private static var shmCounter = 0

    /// A wl_shm buffer of the window's pixel size backed by anonymous shared memory.
    private func makeBuffer() -> Buffer? {
        let w = pixelWidth, h = pixelHeight
        let stride = w * 4, length = stride * h
        WaylandWindow.shmCounter += 1
        let name = "/appkitwin-\(getpid())-\(WaylandWindow.shmCounter)"
        let fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return nil }
        shm_unlink(name)
        defer { Glibc.close(fd) }
        guard ftruncate(fd, off_t(length)) == 0,
              let data = mmap(nil, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0), data != appkitwin_mmap_failed() else { return nil }
        let b = Buffer()
        b.data = data
        b.length = length
        b.width = w; b.height = h
        b.pool = wl_shm_create_pool(backend.shm, fd, Int32(length))
        b.buffer = wl_shm_pool_create_buffer(b.pool, 0, Int32(w), Int32(h), Int32(stride), UInt32(WL_SHM_FORMAT_ARGB8888.rawValue))
        wl_buffer_add_listener(b.buffer, WaylandWindow.bufferListener, opaque)
        b.surface = cairo_image_surface_create_for_data(data.assumingMemoryBound(to: UInt8.self), CAIRO_FORMAT_ARGB32, Int32(w), Int32(h), Int32(stride))
        return b
    }

    private func freeBuffer() -> Buffer? {
        // Drop idle buffers of a stale size (busy ones go when the compositor releases them).
        let stale = buffers.filter { !$0.busy && ($0.width != pixelWidth || $0.height != pixelHeight) }
        for b in stale { b.release() }
        buffers.removeAll { b in stale.contains { $0 === b } }
        if let b = buffers.first(where: { !$0.busy && $0.width == pixelWidth && $0.height == pixelHeight }) { return b }
        guard buffers.count < 2, let b = makeBuffer() else { return nil }
        buffers.append(b)
        return b
    }

    private func bufferReleased(_ buffer: OpaquePointer?) {
        guard let b = buffers.first(where: { $0.buffer == buffer }) else { return }
        b.busy = false
        if b.width != pixelWidth || b.height != pixelHeight { b.release(); buffers.removeAll { $0 === b } }
    }

    private func frameDone(_ callback: OpaquePointer?) {
        if frameCallback == callback { frameCallback = nil }
        backend.frameDidArrive()
    }

    func paintIfNeeded() {
        guard needsPaint, let surface, let rect0 = dirty, ensureBacking(), let cr = backingCairo, let buffer = freeBuffer() else { return }
        let layout = appliedLayout
        let frameBounds = NSRect(origin: .zero, size: layout.frameSize)
        let rect = decorationsDirty ? frameBounds : rect0
        let redrawDecorations = decorationsDirty
        dirty = nil
        decorationsDirty = false
        let s = CGFloat(scale)
        let m = layout.shadowMargin
        // Window coordinates (the frame's bottom-left, y up) to surface pixels.
        let flip = CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: m * s, ty: (m + layout.frameSize.height) * s)
        let dark = (owner as? NSWindow)?.effectiveAppearance.isDark ?? backend.systemAppearanceIsDark
        cairo_save(cr)
        if redrawDecorations {
            // Everything goes: the shadow is translucent and the rounded corners transparent.
            cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
            cairo_paint(cr)
            cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
            if layout.shadowMargin > 0 { drawShadow(cr, layout: layout) }
        }
        do {
            let ctx = CGContext(cairo: cr, baseTransform: flip, width: pixelWidth, height: pixelHeight)
            let clip = layout.cornerRadius > 0 ? CGPath(roundedRect: frameBounds, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil) : CGPath(rect: frameBounds, transform: nil)
            ctx.addPath(clip)
            ctx.clip()
            let content = NSRect(origin: .zero, size: layout.contentSize)
            let contentDirty = rect.intersection(content)
            if !contentDirty.isEmpty {
                ctx.saveGState()
                ctx.clip(to: contentDirty)
                owner?.platformWindowDraw(into: ctx, dirtyRect: contentDirty)
                ctx.restoreGState()
            }
            let bandDirty = rect.intersection(layout.titleBarRect)
            if !bandDirty.isEmpty {
                ctx.saveGState()
                ctx.clip(to: bandDirty)
                owner?.platformWindowDrawTitleBar(into: ctx, dirtyRect: bandDirty)
                ctx.restoreGState()
            }
            if layout.borderWidth > 0 {
                // A hairline just inside the frame, over whatever the content drew there.
                ctx.saveGState()
                ctx.clip(to: rect)
                let inset = frameBounds.insetBy(dx: layout.borderWidth / 2, dy: layout.borderWidth / 2)
                let r = max(0, layout.cornerRadius - layout.borderWidth / 2)
                ctx.addPath(r > 0 ? CGPath(roundedRect: inset, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: inset, transform: nil))
                ctx.setLineWidth(layout.borderWidth)
                ctx.setStrokeColor(dark ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.18) : CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
        cairo_restore(cr)
        cairo_surface_flush(backing)
        // Copy the whole backing into the free buffer (its content is one frame stale), then
        // tell the compositor which pixels changed.
        guard let bcr = cairo_create(buffer.surface) else { return }
        cairo_set_source_surface(bcr, backing, 0, 0)
        cairo_set_operator(bcr, CAIRO_OPERATOR_SOURCE)
        cairo_paint(bcr)
        cairo_destroy(bcr)
        cairo_surface_flush(buffer.surface)
        buffer.busy = true
        if backend.compositorVersion >= 3 { wl_surface_set_buffer_scale(surface, Int32(scale)) }
        wl_surface_attach(surface, buffer.buffer, 0, 0)
        applyRegions(layout)
        if redrawDecorations {
            if backend.compositorVersion >= 4 { wl_surface_damage_buffer(surface, 0, 0, Int32(pixelWidth), Int32(pixelHeight)) }
            else { wl_surface_damage(surface, 0, 0, Int32(layout.surfaceSize.width), Int32(layout.surfaceSize.height)) }
        } else {
            let px = NSRect(x: (m + rect.minX) * s, y: (m + layout.frameSize.height - rect.maxY) * s, width: rect.width * s, height: rect.height * s)
            let dx = Int32(px.minX.rounded(.down)), dy = Int32(px.minY.rounded(.down))
            let dw = Int32(px.width.rounded(.up) + 1), dh = Int32(px.height.rounded(.up) + 1)
            if backend.compositorVersion >= 4 { wl_surface_damage_buffer(surface, dx, dy, dw, dh) }
            else { wl_surface_damage(surface, dx / Int32(scale), dy / Int32(scale), dw / Int32(scale) + 1, dh / Int32(scale) + 1) }
        }
        if frameCallback == nil {
            frameCallback = wl_surface_frame(surface)
            wl_callback_add_listener(frameCallback, WaylandWindow.frameListener, opaque)
        }
        wl_surface_commit(surface)
        wl_display_flush(backend.display)
    }

    /// The window geometry (the frame within the surface), the opaque part of the frame
    /// and where pointer input is the window's, for the commit that follows.
    private func applyRegions(_ layout: ClientSideDecorationLayout) {
        guard let surface else { return }
        let g = layout.windowGeometry
        if let xdgSurface, sentGeometry != g {
            sentGeometry = g
            if NSView._traceInvalidation { NSView._trace("wayland geometry '\(_title)' \(g) surface \(layout.surfaceSize)") }
            xdg_surface_set_window_geometry(xdgSurface, Int32(g.minX), Int32(g.minY), Int32(g.width), Int32(g.height))
        }
        if let region = wl_compositor_create_region(backend.compositor) {
            if !_chrome.isTransparent {
                // The rounded corners stay out: two rects that cover the frame but its corners.
                let r = layout.cornerRadius
                wl_region_add(region, Int32(g.minX + r), Int32(g.minY), Int32(max(0, g.width - 2 * r)), Int32(g.height))
                wl_region_add(region, Int32(g.minX), Int32(g.minY + r), Int32(g.width), Int32(max(0, g.height - 2 * r)))
            }
            wl_surface_set_opaque_region(surface, region)
            wl_region_destroy(region)
        }
        if let region = wl_compositor_create_region(backend.compositor) {
            let i = layout.inputRegion
            wl_region_add(region, Int32(i.minX), Int32(i.minY), Int32(i.width), Int32(i.height))
            wl_surface_set_input_region(surface, region)
            wl_region_destroy(region)
        }
    }

    /// A soft shadow around the frame: nested rounded rectangles from the surface edge in,
    /// each a little more opaque, stronger for the key window.
    private func drawShadow(_ cr: OpaquePointer, layout: ClientSideDecorationLayout) {
        let s = Double(scale)
        let m = Double(layout.shadowMargin)
        let w = Double(layout.surfaceSize.width), h = Double(layout.surfaceSize.height)
        let steps = Int(m)
        let peak = isKey ? 0.028 : 0.014
        for i in 0..<steps {
            let t = Double(i) / m                       // 0 at the surface edge, 1 at the frame
            let inset = Double(i) + 1.5                 // the frame edge is the last ring, shifted down
            let radius = Double(layout.cornerRadius) + (m - Double(i)) * 0.5
            roundedRect(cr, x: inset * s, y: (inset + 1.5) * s, width: (w - 2 * inset) * s, height: (h - 2 * inset) * s, radius: radius * s)
            cairo_set_source_rgba(cr, 0, 0, 0, peak * t * t)
            cairo_fill(cr)
        }
    }

    private func roundedRect(_ cr: OpaquePointer, x: Double, y: Double, width: Double, height: Double, radius: Double) {
        let r = min(radius, width / 2, height / 2)
        cairo_new_path(cr)
        cairo_arc(cr, x + width - r, y + r, r, -Double.pi / 2, 0)
        cairo_arc(cr, x + width - r, y + height - r, r, 0, Double.pi / 2)
        cairo_arc(cr, x + r, y + height - r, r, Double.pi / 2, Double.pi)
        cairo_arc(cr, x + r, y + r, r, Double.pi, 3 * Double.pi / 2)
        cairo_close_path(cr)
    }

    // MARK: Events

    // Drags delivered by the data device (WaylandDataDevice.swift) reach the owner through these.
    func ownerDragEntered(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragEntered(drag) ?? [] }
    func ownerDragUpdated(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragUpdated(drag) ?? [] }
    func ownerDragExited() { owner?.platformDragExited() }
    func ownerDrop(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDrop(drag) ?? [] }

    private func windowNumber() -> Int { (owner as? NSWindow)?.windowNumber ?? 0 }
    /// Surface-local pointer position (points, y down) to window coordinates (the content
    /// at the origin, the band above it, y up), which is what `locationInWindow` carries.
    private func contentPoint(_ p: NSPoint) -> NSPoint { appliedLayout.windowPoint(fromSurface: p) }
    func windowPoint(fromSurface p: NSPoint) -> NSPoint { appliedLayout.windowPoint(fromSurface: p) }
    private func seconds(_ t: UInt32) -> TimeInterval { TimeInterval(t) / 1000 }

    private func mouse(_ type: NSEvent.EventType, position: NSPoint, time: UInt32, button: Int, clickCount: Int = 1) {
        let e = NSEvent._mouseEvent(type: type, location: contentPoint(position), modifierFlags: backend.modifierFlags,
                                    timestamp: seconds(time), windowNumber: windowNumber(), clickCount: clickCount, buttonNumber: button)
        owner?.platformWindowDispatch(e)
    }

    func pointerMoved(time: UInt32, position: NSPoint) {
        updateHover(appliedLayout.hitTest(position))
        if pressedButtons & 1 != 0 { mouse(.leftMouseDragged, position: position, time: time, button: 0) }
        else if pressedButtons & 2 != 0 { mouse(.rightMouseDragged, position: position, time: time, button: 1) }
        else if pressedButtons & 4 != 0 { mouse(.otherMouseDragged, position: position, time: time, button: 2) }
        else { mouse(.mouseMoved, position: position, time: time, button: 0, clickCount: 0) }
    }

    /// The pointer left the surface (also when the compositor grabs it for a move or
    /// resize): no edge cursor, no hovered buttons.
    func pointerLeft() {
        updateHover(.outside)
        let e = NSEvent._mouseEvent(type: .mouseMoved, location: NSPoint(x: -100_000, y: -100_000), modifierFlags: backend.modifierFlags,
                                    timestamp: 0, windowNumber: windowNumber(), clickCount: 0, buttonNumber: 0)
        owner?.platformWindowDispatch(e)
    }

    /// A left press on the decoration: resize handles and the title band go to the
    /// compositor (`xdg_toplevel.resize`/`.move`), a double click on the band zooms, and
    /// the band's buttons (and content, as usual) get the event. True when consumed here.
    private func decorationPress(position: NSPoint, clickCount: Int) -> Bool {
        guard let toplevel, appliedLayout.hasDecorations || _chrome.extendsContentIntoTitleBar || _chrome.movableByBackground else { return false }
        let region = appliedLayout.hitTest(position)
        switch region {
        case .outside:
            return true
        case .resize(let edge):
            guard let seat = backend.seat else { return true }
            xdg_toplevel_resize(toplevel, seat, backend.lastButtonSerial, edge.rawValue)
            wl_display_flush(backend.display)
            return true
        case .titleBar, .content:
            let p = contentPoint(position)
            guard owner?.platformWindowHitTest(p) == .caption else { return false }
            let inBand = region == .titleBar || (_chrome.extendsContentIntoTitleBar && p.y >= appliedLayout.contentSize.height - NSWindow._titleBarBandHeight)
            if clickCount >= 2, inBand {
                owner?.platformWindowTitleBarDoubleClicked()
            } else if let seat = backend.seat {
                xdg_toplevel_move(toplevel, seat, backend.lastButtonSerial)
                wl_display_flush(backend.display)
            }
            return true
        }
    }

    func pointerButton(time: UInt32, button: UInt32, pressed: Bool, position: NSPoint) {
        // Linux input event codes: BTN_LEFT 0x110, BTN_RIGHT 0x111, BTN_MIDDLE 0x112.
        let (bit, number): (Int, Int) = button == 0x110 ? (1, 0) : button == 0x111 ? (2, 1) : (4, 2)
        if pressed {
            if time &- lastClickTime < 400 { clickCount += 1 } else { clickCount = 1 }
            lastClickTime = time
            if number == 0, decorationPress(position: position, clickCount: clickCount) { return }
            // Other buttons on the shadow or a resize handle are nobody's.
            if number != 0 {
                switch appliedLayout.hitTest(position) { case .outside, .resize: return; default: break }
            }
            pressedButtons |= bit
            NSEvent._pressedMouseButtons = pressedButtons
            let type: NSEvent.EventType = number == 0 ? .leftMouseDown : number == 1 ? .rightMouseDown : .otherMouseDown
            mouse(type, position: position, time: time, button: number, clickCount: clickCount)
        } else {
            pressedButtons &= ~bit
            NSEvent._pressedMouseButtons = pressedButtons
            let type: NSEvent.EventType = number == 0 ? .leftMouseUp : number == 1 ? .rightMouseUp : .otherMouseUp
            mouse(type, position: position, time: time, button: number, clickCount: clickCount)
        }
    }

    // MARK: Gestures (zwp_pointer_gestures_v1)

    private var pinchScale = 1.0
    private var swipeTotal = (x: 0.0, y: 0.0)

    func pinchBegin(time: UInt32, position: NSPoint) {
        pinchScale = 1
        owner?.platformWindowDispatch(NSEvent._gestureEvent(type: .beginGesture, location: contentPoint(position), modifierFlags: backend.modifierFlags, timestamp: seconds(time), windowNumber: windowNumber()))
    }
    /// `scale` is cumulative since the begin (1.0 at the start); `rotation` is this
    /// update's change in degrees, clockwise positive (AppKit's is counterclockwise).
    func pinchUpdate(time: UInt32, scale: Double, rotation: Double, position: NSPoint) {
        let p = contentPoint(position)
        let magnification = pinchScale > 0 ? CGFloat(scale / pinchScale - 1) : 0
        pinchScale = scale
        if magnification != 0 {
            owner?.platformWindowDispatch(NSEvent._gestureEvent(type: .magnify, location: p, modifierFlags: backend.modifierFlags, timestamp: seconds(time), windowNumber: windowNumber(), magnification: magnification, phase: .changed))
        }
        if rotation != 0 {
            owner?.platformWindowDispatch(NSEvent._gestureEvent(type: .rotate, location: p, modifierFlags: backend.modifierFlags, timestamp: seconds(time), windowNumber: windowNumber(), rotation: Float(-rotation), phase: .changed))
        }
    }
    func pinchEnd(time: UInt32, cancelled: Bool, position: NSPoint) {
        owner?.platformWindowDispatch(NSEvent._gestureEvent(type: .endGesture, location: contentPoint(position), modifierFlags: backend.modifierFlags, timestamp: seconds(time), windowNumber: windowNumber(), phase: cancelled ? .cancelled : .ended))
    }
    func swipeBegin(time: UInt32) { swipeTotal = (0, 0) }
    func swipeUpdate(time: UInt32, dx: Double, dy: Double) { swipeTotal.x += dx; swipeTotal.y += dy }
    /// Reported once at the end with the dominant direction (deltaX 1 = swipe left, deltaY 1 = swipe up).
    func swipeEnd(time: UInt32, cancelled: Bool, position: NSPoint) {
        guard !cancelled, abs(swipeTotal.x) + abs(swipeTotal.y) > 20 else { return }
        let horizontal = abs(swipeTotal.x) >= abs(swipeTotal.y)
        owner?.platformWindowDispatch(NSEvent._gestureEvent(type: .swipe, location: contentPoint(position), modifierFlags: backend.modifierFlags, timestamp: seconds(time), windowNumber: windowNumber(),
                                                            deltaX: horizontal ? (swipeTotal.x < 0 ? 1 : -1) : 0, deltaY: horizontal ? 0 : (swipeTotal.y < 0 ? 1 : -1)))
    }

    func scroll(time: UInt32, deltaX: CGFloat, deltaY: CGFloat, position: NSPoint) {
        let e = NSEvent._scrollEvent(location: contentPoint(position), modifierFlags: backend.modifierFlags, timestamp: seconds(time),
                                     windowNumber: windowNumber(), deltaX: deltaX, deltaY: deltaY, precise: false)
        owner?.platformWindowDispatch(e)
    }

    func key(time: UInt32, keysym: UInt, characters: String, charactersIgnoringModifiers: String, pressed: Bool) {
        if LinuxKeys.special[keysym] == nil && LinuxKeys.modifiers.contains(keysym) {
            let e = NSEvent(type: .flagsChanged, location: .zero, modifierFlags: backend.modifierFlags, timestamp: seconds(time), windowNumber: windowNumber())
            owner?.platformWindowDispatch(e)
            return
        }
        var chars = characters, plain = charactersIgnoringModifiers
        var keyCode = UInt16(truncatingIfNeeded: keysym)
        if let special = LinuxKeys.special[keysym] {
            chars = special.0; plain = special.0; keyCode = special.1
        } else if plain.isEmpty {
            plain = chars
        }
        let e = NSEvent.keyEvent(with: pressed ? .keyDown : .keyUp, location: .zero, modifierFlags: backend.modifierFlags, timestamp: seconds(time),
                                 windowNumber: windowNumber(), context: nil, characters: chars,
                                 charactersIgnoringModifiers: plain, isARepeat: false, keyCode: keyCode)!
        owner?.platformWindowDispatch(e)
    }
}
/// A `wl_subsurface` of a `WaylandWindow` at a content rect, for a Vulkan swap chain
/// (`VK_KHR_wayland_surface`). Desynchronised, so the chain's commits show as they come;
/// placed in the parent's coordinates and given the window's buffer scale, so a chain of
/// `drawableSize` pixels covers the view's points.
@MainActor
final class WaylandPresentationSurface: PlatformPresentationSurface {
    private unowned let window: WaylandWindow
    private unowned let backend: WaylandBackend
    private(set) var surface: OpaquePointer?      // wl_surface*
    private var subsurface: OpaquePointer?        // wl_subsurface*

    init?(window: WaylandWindow, backend: WaylandBackend, parent: OpaquePointer, subcompositor: OpaquePointer, frame: NSRect) {
        self.window = window
        self.backend = backend
        guard let s = wl_compositor_create_surface(backend.compositor) else { return nil }
        guard let sub = wl_subcompositor_get_subsurface(subcompositor, s, parent) else { wl_surface_destroy(s); return nil }
        surface = s
        subsurface = sub
        wl_subsurface_set_desync(sub)
        apply(frame)
        window.presentationSurfaceDidChange()
    }

    var handle: PlatformPresentationSurfaceHandle {
        PlatformPresentationSurfaceHandle(kind: .wayland, display: UnsafeMutableRawPointer(backend.display), window: UInt(bitPattern: surface))
    }

    private func apply(_ frame: NSRect) {
        guard let surface, let subsurface else { return }
        let p = window.subsurfacePosition(for: frame)
        wl_subsurface_set_position(subsurface, p.x, p.y)
        if backend.compositorVersion >= 3 { wl_surface_set_buffer_scale(surface, Int32(window.scale)) }
    }

    func setFrame(_ frame: NSRect) {
        apply(frame)
        window.presentationSurfaceDidChange()
    }

    func close() {
        guard surface != nil else { return }
        if let sub = subsurface { wl_subsurface_destroy(sub) }
        if let s = surface { wl_surface_destroy(s) }
        subsurface = nil
        surface = nil
        wl_display_flush(backend.display)
        window.presentationSurfaceClosed(self)
    }
}
#endif
