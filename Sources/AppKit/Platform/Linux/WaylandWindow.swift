// An xdg-shell toplevel painted through Cairo into wl_shm buffers.
//
// The content is drawn into a persistent Cairo image surface exactly as `LinuxWindow`
// does (through `CGContext(cairo:)`), then copied into one of two shared-memory buffers
// that the compositor releases when it is done reading. Wayland has no window positions:
// the frame origin is whatever the core last set, only the size follows the compositor.

#if os(Linux)
import Foundation
import Glibc
import CoreGraphics
import CCairo
import CWayland

@MainActor
final class WaylandWindow: PlatformWindow {
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
        surface = wl_compositor_create_surface(backend.compositor)
        wl_surface_add_listener(surface, WaylandWindow.surfaceListener, opaque)
        xdgSurface = xdg_wm_base_get_xdg_surface(backend.wmBase, surface)
        xdg_surface_add_listener(xdgSurface, WaylandWindow.xdgSurfaceListener, opaque)
        toplevel = xdg_surface_get_toplevel(xdgSurface)
        xdg_toplevel_add_listener(toplevel, WaylandWindow.toplevelListener, opaque)
        xdg_toplevel_set_app_id(toplevel, "AppKitWin")
        if let manager = backend.decorationManager {
            decoration = zxdg_decoration_manager_v1_get_toplevel_decoration(manager, toplevel)
            zxdg_toplevel_decoration_v1_add_listener(decoration, WaylandWindow.decorationListener, opaque)
        }
        backend.register(self)
        applyDecorationMode()
        applySizeHints()
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
        configure: { data, _, width, height, _ in
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.toplevelConfigure(width: Int(width), height: Int(height)) }
        },
        close: { data, _ in
            guard let w = WaylandWindow.from(data) else { return }
            MainActor.assumeIsolated { w.closeRequested() }
        },
        configure_bounds: { _, _, _, _ in },
        wm_capabilities: { _, _, _ in }))

    private static let decorationListener = WaylandBackend.listener(zxdg_toplevel_decoration_v1_listener(configure: { _, _, _ in }))

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

    private func toplevelConfigure(width: Int, height: Int) {
        if width > 0 && height > 0 { pendingSize = NSSize(width: width, height: height) }
    }

    private func configured(serial: UInt32) {
        configured = true
        if let size = pendingSize {
            pendingSize = nil
            if size != _frame.size {
                _frame.size = size
                releaseBacking()
                owner?.platformWindowDidChangeFrame(_frame)
            }
        }
        dirty = NSRect(origin: .zero, size: _frame.size)
        if isVisible { paintIfNeeded() }
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
            _frame = newValue
            if resized {
                releaseBacking()
                applySizeHints()
                dirty = NSRect(origin: .zero, size: _frame.size)
            }
        }
    }

    var styleMask: NSWindow.StyleMask {
        get { _styleMask }
        set { _styleMask = newValue; applyDecorationMode(); applySizeHints() }
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
        set { _chrome = newValue; applyDecorationMode() }
    }

    private func applyDecorationMode() {
        guard let decoration else { return }
        let serverSide = _styleMask.contains(.titled) && !_chrome.extendsContentIntoTitleBar
        zxdg_toplevel_decoration_v1_set_mode(decoration, serverSide ? UInt32(ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE.rawValue)
                                                                   : UInt32(ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE.rawValue))
    }

    private func applySizeHints() {
        guard let t = toplevel else { return }
        var minW = _minSize.width, minH = _minSize.height
        var maxW = min(_maxSize.width, 100_000), maxH = min(_maxSize.height, 100_000)
        if !_styleMask.contains(.resizable) {
            minW = _frame.width; maxW = minW
            minH = _frame.height; maxH = minH
        }
        xdg_toplevel_set_min_size(t, Int32(minW), Int32(minH))
        xdg_toplevel_set_max_size(t, maxW >= 100_000 ? 0 : Int32(maxW), maxH >= 100_000 ? 0 : Int32(maxH))
    }

    func frameRect(forContentRect contentRect: NSRect) -> NSRect { contentRect }
    func contentRect(forFrameRect frameRect: NSRect) -> NSRect { frameRect }

    func show() {
        guard !isVisible, let surface else { return }
        isVisible = true
        configured = false
        dirty = NSRect(origin: .zero, size: _frame.size)
        // Map: commit without a buffer and wait for the configure before painting.
        wl_surface_commit(surface)
        wl_display_flush(backend.display)
    }

    func hide() {
        guard isVisible, let surface else { return }
        isVisible = false
        configured = false
        wl_surface_attach(surface, nil, 0, 0)
        wl_surface_commit(surface)
        wl_display_flush(backend.display)
    }

    func makeKey() {
        // Wayland does not let clients take focus; the compositor focuses new toplevels.
    }

    func orderBack() {}

    private var minimized = false
    private var maximized = false
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
    func zoom() {
        guard let toplevel else { return }
        if maximized { xdg_toplevel_unset_maximized(toplevel) } else { xdg_toplevel_set_maximized(toplevel) }
        wl_display_flush(backend.display)
        maximized.toggle()
    }
    var isMiniaturized: Bool { minimized }
    var isZoomed: Bool { maximized }

    func close() {
        guard !destroying else { return }
        destroying = true
        backend.unregister(self)
        if let c = frameCallback { wl_callback_destroy(c); frameCallback = nil }
        releaseBacking()
        for b in buffers { b.release() }
        buffers.removeAll()
        if let d = decoration { zxdg_toplevel_decoration_v1_destroy(d); decoration = nil }
        if let t = toplevel { xdg_toplevel_destroy(t); toplevel = nil }
        if let x = xdgSurface { xdg_surface_destroy(x); xdgSurface = nil }
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

    // MARK: Painting

    private var pixelWidth: Int { max(1, Int((_frame.width * CGFloat(scale)).rounded())) }
    private var pixelHeight: Int { max(1, Int((_frame.height * CGFloat(scale)).rounded())) }

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
        guard needsPaint, let surface, let rect = dirty, ensureBacking(), let cr = backingCairo, let buffer = freeBuffer() else { return }
        dirty = nil
        let size = _frame.size
        let s = CGFloat(scale)
        let flip = CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: 0, ty: size.height * s)
        cairo_save(cr)
        do {
            let ctx = CGContext(cairo: cr, baseTransform: flip, width: pixelWidth, height: pixelHeight)
            ctx.clip(to: rect)
            owner?.platformWindowDraw(into: ctx, dirtyRect: rect)
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
        let px = NSRect(x: rect.minX * s, y: (size.height - rect.maxY) * s, width: rect.width * s, height: rect.height * s)
        let dx = Int32(px.minX.rounded(.down)), dy = Int32(px.minY.rounded(.down))
        let dw = Int32(px.width.rounded(.up) + 1), dh = Int32(px.height.rounded(.up) + 1)
        if backend.compositorVersion >= 4 { wl_surface_damage_buffer(surface, dx, dy, dw, dh) }
        else { wl_surface_damage(surface, dx / Int32(scale), dy / Int32(scale), dw / Int32(scale) + 1, dh / Int32(scale) + 1) }
        if frameCallback == nil {
            frameCallback = wl_surface_frame(surface)
            wl_callback_add_listener(frameCallback, WaylandWindow.frameListener, opaque)
        }
        wl_surface_commit(surface)
        wl_display_flush(backend.display)
    }

    // MARK: Events

    // Drags delivered by the data device (WaylandDataDevice.swift) reach the owner through these.
    func ownerDragEntered(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragEntered(drag) ?? [] }
    func ownerDragUpdated(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDragUpdated(drag) ?? [] }
    func ownerDragExited() { owner?.platformDragExited() }
    func ownerDrop(_ drag: PlatformDragInfo) -> NSDragOperation { owner?.platformDrop(drag) ?? [] }

    private func windowNumber() -> Int { (owner as? NSWindow)?.windowNumber ?? 0 }
    private func contentPoint(_ p: NSPoint) -> NSPoint { NSPoint(x: p.x, y: _frame.height - p.y) }
    private func seconds(_ t: UInt32) -> TimeInterval { TimeInterval(t) / 1000 }

    private func mouse(_ type: NSEvent.EventType, position: NSPoint, time: UInt32, button: Int, clickCount: Int = 1) {
        let e = NSEvent._mouseEvent(type: type, location: contentPoint(position), modifierFlags: backend.modifierFlags,
                                    timestamp: seconds(time), windowNumber: windowNumber(), clickCount: clickCount, buttonNumber: button)
        owner?.platformWindowDispatch(e)
    }

    func pointerMoved(time: UInt32, position: NSPoint) {
        if pressedButtons & 1 != 0 { mouse(.leftMouseDragged, position: position, time: time, button: 0) }
        else if pressedButtons & 2 != 0 { mouse(.rightMouseDragged, position: position, time: time, button: 1) }
        else if pressedButtons & 4 != 0 { mouse(.otherMouseDragged, position: position, time: time, button: 2) }
        else { mouse(.mouseMoved, position: position, time: time, button: 0, clickCount: 0) }
    }

    func pointerButton(time: UInt32, button: UInt32, pressed: Bool, position: NSPoint) {
        // Linux input event codes: BTN_LEFT 0x110, BTN_RIGHT 0x111, BTN_MIDDLE 0x112.
        let (bit, number): (Int, Int) = button == 0x110 ? (1, 0) : button == 0x111 ? (2, 1) : (4, 2)
        if pressed {
            if time &- lastClickTime < 400 { clickCount += 1 } else { clickCount = 1 }
            lastClickTime = time
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
#endif
