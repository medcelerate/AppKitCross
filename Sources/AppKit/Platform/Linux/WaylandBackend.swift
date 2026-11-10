// Linux Wayland backend: xdg-shell windows with wl_shm buffers painted through Cairo,
// xkbcommon keyboards, wl_cursor themes (Milestone 8).
//
// Selected by `Platform` when WAYLAND_DISPLAY is set (or APPKITWIN_LINUX_BACKEND=wayland);
// the X11 `LinuxBackend` remains the fallback. One wl_display, an event loop over poll()
// that also serves posted blocks and the Core Animation frame clock; surface frame
// callbacks fire the clock early when the compositor is actually presenting. Text,
// images and file dialogs are shared with the X11 backend; the clipboard and drag and
// drop go through the seat's data device (WaylandDataDevice.swift).

#if os(Linux)
import Foundation
import Glibc
import CoreGraphics
import CCairo
import CWayland

/// A `wl_output` with the properties the core needs.
@MainActor
final class WaylandOutput {
    let proxy: OpaquePointer            // wl_output*
    let name: UInt32                    // registry name
    var x = 0, y = 0
    var widthPx = 0, heightPx = 0
    var scale = 1
    var description = "Wayland Output"
    init(proxy: OpaquePointer, name: UInt32) { self.proxy = proxy; self.name = name }
    var logicalSize: NSSize { NSSize(width: CGFloat(widthPx) / CGFloat(scale), height: CGFloat(heightPx) / CGFloat(scale)) }
}

@MainActor
final class WaylandBackend: PlatformBackend {
    let display: OpaquePointer                    // wl_display*
    private(set) var registry: OpaquePointer!     // wl_registry*
    private(set) var compositor: OpaquePointer?   // wl_compositor*
    private(set) var compositorVersion: UInt32 = 0
    private(set) var subcompositor: OpaquePointer? // wl_subcompositor* (presentation surfaces, ADR-0012)
    private(set) var shm: OpaquePointer?          // wl_shm*
    private(set) var seat: OpaquePointer?         // wl_seat*
    private(set) var wmBase: OpaquePointer?       // xdg_wm_base*
    private(set) var decorationManager: OpaquePointer?   // zxdg_decoration_manager_v1*
    /// APPKITWIN_WAYLAND_DECORATIONS=client|server overrides what windows ask xdg-decoration
    /// for (the compositor still has the last word); nil follows the style mask.
    let decorationPreference: ClientSideDecorationMode?
    private(set) var pointer: OpaquePointer?      // wl_pointer*
    private(set) var keyboard: OpaquePointer?     // wl_keyboard*
    private(set) var outputs: [WaylandOutput] = []
    private(set) var windows: [WaylandWindow] = []

    // Event loop
    private var running = false
    private var posted: [@MainActor () -> Void] = []
    private var frameCallbacks: [(deadline: TimeInterval, callback: @MainActor () -> Void)] = []
    private var wakePipe: [Int32] = [-1, -1]

    // Keyboard (xkbcommon)
    private var xkbContext: OpaquePointer?
    private var xkbKeymap: OpaquePointer?
    private(set) var xkbState: OpaquePointer?
    private(set) var keyboardFocus: WaylandWindow?
    private(set) var modifierFlags: NSEvent.ModifierFlags = []

    // Pointer
    private(set) var pointerFocus: WaylandWindow?
    private var pointerGestures: OpaquePointer?       // zwp_pointer_gestures_v1*
    private var pinchGesture: OpaquePointer?          // zwp_pointer_gesture_pinch_v1*
    private var swipeGesture: OpaquePointer?          // zwp_pointer_gesture_swipe_v1*
    private var gestureFocus: WaylandWindow?
    private(set) var pointerPosition = NSPoint.zero     // surface-local, points, y down
    private var pointerEnterSerial: UInt32 = 0
    /// Serials the data device needs: the last button press (start_drag) and the last
    /// input event of any kind (set_selection).
    private(set) var lastButtonSerial: UInt32 = 0
    private(set) var lastInputSerial: UInt32 = 0
    /// The clipboard and drag and drop over the seat's data device (WaylandDataDevice.swift).
    private(set) var dataDevice: WaylandDataDevice!
    var dragDrop: (any PlatformDragDrop)? { dataDevice }
    /// Printing (LinuxPrinting.swift): Cairo PDF and CUPS.
    let linuxPrinting = LinuxPrintBackend()
    var printing: (any PlatformPrintBackend)? { linuxPrinting }
    /// StatusNotifierItems over the session bus (LinuxStatusItem.swift); made on first use.
    /// Wayland has no global coordinates: a host's position is taken as the top-left of
    /// the first output.
    private var statusNotifier: LinuxStatusNotifierHost?
    private var statusNotifierTried = false
    var statusItems: (any PlatformStatusItemHost)? {
        if !statusNotifierTried {
            statusNotifierTried = true
            statusNotifier = LinuxStatusNotifierHost.connect { [weak self] x, y in
                let d = self?.displays.first
                let s = d?.backingScaleFactor ?? 1
                return NSPoint(x: CGFloat(x) / s, y: (d?.frame.height ?? 0) - CGFloat(y) / s)
            }
        }
        return statusNotifier
    }
    /// AT-SPI2 over D-Bus (LinuxAccessibility.swift, ADR-0013). Wayland has no global
    /// coordinates, so extents are reported against the primary output's logical size.
    private(set) var atspi: AtspiBridge?
    private var pendingAxis = (x: CGFloat(0), y: CGFloat(0), time: UInt32(0), has: false)

    // Cursor
    private var cursorTheme: OpaquePointer?       // wl_cursor_theme*
    private var cursorSurface: OpaquePointer?     // wl_surface*
    private var cursorThemeScale = 1
    private var currentCursor: PlatformCursor = .arrow
    private var cursorHidden = false
    /// XCursor names a window's decoration wants over a resize handle, overriding the core's cursor.
    private var decorationCursorNames: [String]? = nil

    private static var listenerStorage: [UnsafeMutableRawPointer] = []

    /// Allocates a listener struct that lives for the process (libwayland keeps the pointer).
    static func listener<T>(_ value: T) -> UnsafeMutablePointer<T> {
        let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
        p.initialize(to: value)
        listenerStorage.append(UnsafeMutableRawPointer(p))
        return p
    }

    var opaque: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    static func from(_ data: UnsafeMutableRawPointer?) -> WaylandBackend? {
        data.map { Unmanaged<WaylandBackend>.fromOpaque($0).takeUnretainedValue() }
    }

    /// nil when there is no Wayland compositor to talk to.
    init?() {
        guard let d = wl_display_connect(nil) else { return nil }
        display = d
        text = HostTextBackend()      // CoreText over Pango/HarfBuzz (ADR-0007)
        image = LinuxImageBackend()
        switch ProcessInfo.processInfo.environment["APPKITWIN_WAYLAND_DECORATIONS"]?.lowercased() {
        case "client", "csd": decorationPreference = .client
        case "server", "ssd": decorationPreference = .server
        default: decorationPreference = nil
        }
        var fds: [Int32] = [-1, -1]
        if pipe(&fds) == 0 { wakePipe = fds }
        dataDevice = WaylandDataDevice(backend: self)
        registry = wl_display_get_registry(d)
        let registryListener = WaylandBackend.listener(wl_registry_listener(
            global: { data, registry, name, interface, version in
                guard let interface, let backend = WaylandBackend.from(data) else { return }
                MainActor.assumeIsolated { backend.globalAdded(name: name, interface: String(cString: interface), version: version) }
            },
            global_remove: { data, _, name in
                guard let backend = WaylandBackend.from(data) else { return }
                MainActor.assumeIsolated { backend.globalRemoved(name: name) }
            }))
        wl_registry_add_listener(registry, registryListener, opaque)
        wl_display_roundtrip(d)     // globals
        wl_display_roundtrip(d)     // output modes, seat capabilities, keymap
        guard compositor != nil, shm != nil, wmBase != nil else {
            wl_display_disconnect(d)
            return nil
        }
        xkbContext = xkb_context_new(XKB_CONTEXT_NO_FLAGS)
    }

    // MARK: Registry

    private func globalAdded(name: UInt32, interface: String, version: UInt32) {
        switch interface {
        case "wl_compositor":
            compositorVersion = min(version, 4)
            compositor = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, compositorVersion))
        case "wl_shm":
            shm = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, 1))
        case "wl_subcompositor":
            subcompositor = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, 1))
        case "zwp_pointer_gestures_v1":
            pointerGestures = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, 1))
            attachPointerGestures()
        case "wl_seat" where seat == nil:
            seat = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, min(version, 5)))
            let seatListener = WaylandBackend.listener(wl_seat_listener(
                capabilities: { data, _, caps in
                    guard let backend = WaylandBackend.from(data) else { return }
                    MainActor.assumeIsolated { backend.seatCapabilities(caps) }
                },
                name: { _, _, _ in }))
            wl_seat_add_listener(seat, seatListener, opaque)
        case "wl_output":
            guard let proxy = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, min(version, 2))) else { return }
            let output = WaylandOutput(proxy: proxy, name: name)
            outputs.append(output)
            let outputListener = WaylandBackend.listener(wl_output_listener(
                geometry: { data, output, x, y, _, _, _, make, model, _ in
                    guard let backend = WaylandBackend.from(data) else { return }
                    MainActor.assumeIsolated {
                        guard let o = backend.outputs.first(where: { $0.proxy == output }) else { return }
                        o.x = Int(x); o.y = Int(y)
                        let parts = [make, model].compactMap { $0.map { String(cString: $0) } }.filter { !$0.isEmpty }
                        if !parts.isEmpty { o.description = parts.joined(separator: " ") }
                    }
                },
                mode: { data, output, flags, width, height, _ in
                    guard flags & UInt32(WL_OUTPUT_MODE_CURRENT.rawValue) != 0, let backend = WaylandBackend.from(data) else { return }
                    MainActor.assumeIsolated {
                        guard let o = backend.outputs.first(where: { $0.proxy == output }) else { return }
                        o.widthPx = Int(width); o.heightPx = Int(height)
                    }
                },
                done: { _, _ in },
                scale: { data, output, factor in
                    guard let backend = WaylandBackend.from(data) else { return }
                    MainActor.assumeIsolated {
                        guard let o = backend.outputs.first(where: { $0.proxy == output }) else { return }
                        o.scale = max(1, Int(factor))
                        for w in backend.windows { w.outputsDidChange() }
                    }
                },
                name: { _, _, _ in },
                description: { _, _, _ in }))
            wl_output_add_listener(proxy, outputListener, opaque)
        case "xdg_wm_base":
            wmBase = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, 1))
            let wmListener = WaylandBackend.listener(xdg_wm_base_listener(ping: { _, base, serial in xdg_wm_base_pong(base, serial) }))
            xdg_wm_base_add_listener(wmBase, wmListener, opaque)
        case "zxdg_decoration_manager_v1":
            decorationManager = OpaquePointer(appkitwin_wl_registry_bind(registry, name, interface, 1))
        case "wl_data_device_manager":
            dataDevice.managerAdded(name: name, version: version)
        default:
            break
        }
    }

    private func globalRemoved(name: UInt32) {
        if let i = outputs.firstIndex(where: { $0.name == name }) {
            let o = outputs.remove(at: i)
            for w in windows { w.outputRemoved(o) }
            wl_output_destroy(o.proxy)
        }
    }

    private func seatCapabilities(_ caps: UInt32) {
        dataDevice.seatDidChange()
        let hasPointer = caps & UInt32(WL_SEAT_CAPABILITY_POINTER.rawValue) != 0
        let hasKeyboard = caps & UInt32(WL_SEAT_CAPABILITY_KEYBOARD.rawValue) != 0
        if hasPointer && pointer == nil {
            pointer = wl_seat_get_pointer(seat)
            wl_pointer_add_listener(pointer, WaylandBackend.pointerListener, opaque)
            attachPointerGestures()
        } else if !hasPointer, let p = pointer {
            if let g = pinchGesture { zwp_pointer_gesture_pinch_v1_destroy(g); pinchGesture = nil }
            if let g = swipeGesture { zwp_pointer_gesture_swipe_v1_destroy(g); swipeGesture = nil }
            wl_pointer_release(p)
            pointer = nil
        }
        if hasKeyboard && keyboard == nil {
            keyboard = wl_seat_get_keyboard(seat)
            wl_keyboard_add_listener(keyboard, WaylandBackend.keyboardListener, opaque)
        } else if !hasKeyboard, let k = keyboard {
            wl_keyboard_release(k)
            keyboard = nil
        }
    }

    // MARK: PlatformBackend

    var displays: [PlatformDisplay] {
        guard !outputs.isEmpty else {
            return [PlatformDisplay(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 800),
                                    backingScaleFactor: 1, localizedName: "Wayland Output", isMain: true)]
        }
        // AppKit screen space: the primary (first) output's bottom-left is the origin.
        let primary = outputs[0]
        let primaryHeight = primary.logicalSize.height
        return outputs.enumerated().map { i, o in
            let size = o.logicalSize
            let origin = NSPoint(x: CGFloat(o.x - primary.x), y: primaryHeight - CGFloat(o.y - primary.y) - size.height)
            let frame = NSRect(origin: origin, size: size)
            return PlatformDisplay(frame: frame, visibleFrame: frame, backingScaleFactor: CGFloat(o.scale), localizedName: o.description, isMain: i == 0)
        }
    }

    func makeWindow(owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) -> PlatformWindow {
        WaylandWindow(backend: self, owner: owner, contentRect: contentRect, styleMask: styleMask)
    }

    func register(_ window: WaylandWindow) {
        windows.append(window)
        if atspi == nil && !atspiTried {
            atspiTried = true
            atspi = AtspiBridge.connect(rootWindowProperty: { nil }) { [weak self] r in
                let h = self?.displays.first?.frame.height ?? 0
                return (Int32(r.minX.rounded()), Int32((h - r.maxY).rounded()), Int32(r.width.rounded()), Int32(r.height.rounded()))
            }
        }
        atspi?.register(window)
    }
    private var atspiTried = false
    func unregister(_ window: WaylandWindow) {
        if windows.contains(where: { $0 === window }) { atspi?.unregister(window) }
        windows.removeAll { $0 === window }
        if pointerFocus === window { pointerFocus = nil }
        if keyboardFocus === window { keyboardFocus = nil }
    }
    func window(for surface: OpaquePointer?) -> WaylandWindow? {
        guard let surface else { return nil }
        return windows.first { $0.surface == surface }
    }

    // MARK: Event loop

    func run() {
        running = true
        while running { pump(blocking: true) }
    }

    func stop() {
        running = false
        wake()
    }

    /// Handles pending Wayland events, posted blocks, due frames and repaints. With
    /// `blocking` it waits for the next event or deadline.
    func pump(blocking: Bool) {
        drainPosted()
        let nextTimer = PlatformMainQueue.service()
        while wl_display_prepare_read(display) != 0 { wl_display_dispatch_pending(display) }
        wl_display_flush(display)
        var fds = [pollfd(fd: wl_display_get_fd(display), events: Int16(POLLIN), revents: 0),
                   pollfd(fd: wakePipe[0], events: Int16(POLLIN), revents: 0),
                   pollfd(fd: PlatformMainQueue.fileDescriptor, events: Int16(POLLIN), revents: 0)]
        if let a = atspi, a.fileDescriptor >= 0 { fds.append(pollfd(fd: a.fileDescriptor, events: Int16(POLLIN), revents: 0)) }
        if let s = statusNotifier, s.fileDescriptor >= 0 { fds.append(pollfd(fd: s.fileDescriptor, events: Int16(POLLIN), revents: 0)) }
        var timeout: Int32 = blocking ? -1 : 0
        if blocking {
            if let next = frameCallbacks.map(\.deadline).min() {
                timeout = Int32(max(0, (next - ProcessInfo.processInfo.systemUptime) * 1000))
            }
            if let t = nextTimer { let ms = Int32(min(Double(Int32.max), t * 1000)); timeout = timeout < 0 ? ms : min(timeout, ms) }
            if !posted.isEmpty || windows.contains(where: { $0.needsPaint }) { timeout = 0 }
        }
        _ = poll(&fds, nfds_t(fds.count), timeout)
        if fds[0].revents & Int16(POLLIN) != 0 { wl_display_read_events(display) } else { wl_display_cancel_read(display) }
        if fds[1].revents != 0 {
            var buf = [UInt8](repeating: 0, count: 64)
            _ = read(wakePipe[0], &buf, 64)
        }
        if fds[2].revents != 0 { PlatformMainQueue.service() }
        wl_display_dispatch_pending(display)
        if wl_display_get_error(display) != 0 {
            FileHandle.standardError.write(Data("AppKitCross: Wayland display error \(wl_display_get_error(display)); stopping\n".utf8))
            running = false
            return
        }
        atspi?.dispatch()
        statusNotifier?.dispatch()
        drainPosted()
        fireDueFrames()
        for w in windows where w.needsPaint { w.paintIfNeeded() }
        wl_display_flush(display)
    }

    func post(_ block: @escaping @MainActor () -> Void) {
        posted.append(block)
        wake()
    }

    private func wake() {
        var byte: UInt8 = 1
        if wakePipe[1] >= 0 { _ = write(wakePipe[1], &byte, 1) }
    }

    private func drainPosted() {
        while !posted.isEmpty {
            let blocks = posted
            posted.removeAll()
            for b in blocks { b() }
        }
    }

    func scheduleFrame(_ callback: @escaping @MainActor () -> Void) {
        frameCallbacks.append((ProcessInfo.processInfo.systemUptime + 1.0 / 60.0, callback))
        wake()
    }

    /// A surface frame callback arrived: the compositor presented, so the frame clock ticks.
    func frameDidArrive() {
        guard !frameCallbacks.isEmpty else { return }
        let due = frameCallbacks
        frameCallbacks.removeAll()
        for f in due { f.callback() }
    }

    private func fireDueFrames() {
        let now = ProcessInfo.processInfo.systemUptime
        let due = frameCallbacks.filter { $0.deadline <= now }
        guard !due.isEmpty else { return }
        frameCallbacks.removeAll { $0.deadline <= now }
        for f in due { f.callback() }
    }

    func beep() { FileHandle.standardError.write(Data([0x07])) }   // no bell in the Wayland protocol
    var systemAppearanceIsDark: Bool { false }

    var mouseLocation: NSPoint {
        guard let w = pointerFocus else { return .zero }
        let p = w.windowPoint(fromSurface: pointerPosition)
        return NSPoint(x: w.frame.minX + p.x, y: w.frame.minY + p.y)
    }

    let text: any PlatformTextBackend
    let image: any PlatformImageBackend
    var systemPasteboard: any PlatformPasteboard { dataDevice }

    /// The xdg-desktop-portal FileChooser when a portal is on the session bus (ADR-0017).
    /// Parent identifiers need xdg-foreign exports, which the backend does not do yet, so
    /// the portal dialog is not parented.
    private var portalLookedUp = false
    private var portal: LinuxFileChooserPortal?
    var fileDialog: (any PlatformFileDialog)? {
        guard PlatformFileDialogPolicy.allowsNative else { return nil }
        if !portalLookedUp {
            portalLookedUp = true
            portal = LinuxFileChooserPortal.connect(pump: { [weak self] in self?.pump(blocking: false) }, parentIdentifier: { _ in "" })
        }
        return portal
    }

    func runModal(for window: PlatformWindow?, until stop: @escaping @MainActor () -> Bool) {
        while !stop() {
            pump(blocking: true)
            if !running { break }
        }
    }

    func setMainMenu(_ menu: PlatformMenu?, host: PlatformMenuHost?) {
        // No native menu bar on Wayland; NSApplication still dispatches key equivalents.
    }

    /// The band a window of this style would draw itself (ClientSideDecoration.swift):
    /// none when the compositor decorates, which it is expected to when it has xdg-decoration.
    func titleBarHeight(for styleMask: NSWindow.StyleMask) -> CGFloat {
        let requestsServer = decorationPreference.map { $0 == .server } ?? !styleMask.contains(.fullSizeContentView)
        let mode = ClientSideDecorationMode.mode(for: styleMask, serverSideGranted: decorationManager == nil ? nil : requestsServer)
        return mode == .client && !styleMask.contains(.fullSizeContentView) ? ClientSideDecorationLayout.titleBandHeight : 0
    }
    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
        NSRect(origin: contentRect.origin, size: ClientSideDecorationLayout.frameSize(forContentSize: contentRect.size, titleBarHeight: titleBarHeight(for: styleMask)))
    }
    func contentRect(forFrameRect frameRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect {
        NSRect(origin: frameRect.origin, size: ClientSideDecorationLayout.contentSize(forFrameSize: frameRect.size, titleBarHeight: titleBarHeight(for: styleMask)))
    }

    // MARK: Cursors

    /// XCursor names (with fallbacks) for each AppKit cursor.
    private static func names(for cursor: PlatformCursor) -> [String] {
        switch cursor {
        case .arrow, .custom: return ["left_ptr", "default", "arrow"]
        case .contextualMenu: return ["context-menu", "left_ptr", "default"]
        case .dragCopy: return ["copy", "dnd-copy", "left_ptr", "default"]
        case .dragLink: return ["alias", "dnd-link", "left_ptr", "default"]
        case .operationNotAllowed: return ["not-allowed", "crossed_circle", "left_ptr", "default"]
        case .iBeam, .iBeamVertical: return ["xterm", "text", "ibeam"]
        case .crosshair: return ["crosshair", "cross"]
        case .pointingHand: return ["hand2", "pointer", "hand"]
        case .openHand: return ["hand1", "grab", "openhand"]
        case .closedHand: return ["grabbing", "closedhand", "hand1"]
        case .resizeLeftRight: return ["sb_h_double_arrow", "ew-resize", "col-resize"]
        case .resizeUpDown: return ["sb_v_double_arrow", "ns-resize", "row-resize"]
        case .resizeAll: return ["fleur", "all-scroll", "move"]
        case .wait: return ["watch", "wait", "progress"]
        }
    }

    func setCursor(_ cursor: PlatformCursor) {
        currentCursor = cursor
        applyCursor()
    }

    func setCursorHidden(_ hidden: Bool) {
        cursorHidden = hidden
        applyCursor()
    }

    func setDecorationCursor(_ names: [String]?) {
        guard names != decorationCursorNames else { return }
        decorationCursorNames = names
        applyCursor()
    }

    private func loadCursorTheme(scale: Int) {
        if let t = cursorTheme, cursorThemeScale == scale { _ = t; return }
        if let t = cursorTheme { wl_cursor_theme_destroy(t) }
        let env = ProcessInfo.processInfo.environment
        let size = Int32(env["XCURSOR_SIZE"].flatMap(Int.init) ?? 24) * Int32(scale)
        cursorTheme = wl_cursor_theme_load(env["XCURSOR_THEME"], size, shm)
        cursorThemeScale = scale
        if cursorSurface == nil { cursorSurface = wl_compositor_create_surface(compositor) }
    }

    /// Sets the pointer image for the window under the pointer (Wayland cursors are per
    /// pointer-enter, so this is re-applied from `pointerEntered`).
    func applyCursor() {
        guard let pointer, let focus = pointerFocus else { return }
        if cursorHidden {
            wl_pointer_set_cursor(pointer, pointerEnterSerial, nil, 0, 0)
            return
        }
        let scale = focus.scale
        loadCursorTheme(scale: scale)
        guard let theme = cursorTheme, let cursorSurface else { return }
        var wlCursor: UnsafeMutablePointer<wl_cursor>? = nil
        for name in decorationCursorNames ?? WaylandBackend.names(for: currentCursor) {
            wlCursor = wl_cursor_theme_get_cursor(theme, name)
            if wlCursor != nil { break }
        }
        guard let c = wlCursor, c.pointee.image_count > 0, let img = c.pointee.images[0], let buffer = wl_cursor_image_get_buffer(img) else { return }
        let i = img.pointee
        if compositorVersion >= 3 { wl_surface_set_buffer_scale(cursorSurface, Int32(scale)) }
        wl_surface_attach(cursorSurface, buffer, 0, 0)
        wl_surface_damage(cursorSurface, 0, 0, Int32(i.width), Int32(i.height))
        wl_surface_commit(cursorSurface)
        wl_pointer_set_cursor(pointer, pointerEnterSerial, cursorSurface, Int32(i.hotspot_x) / Int32(scale), Int32(i.hotspot_y) / Int32(scale))
    }

    // MARK: Pointer

    private static let pointerListener = WaylandBackend.listener(wl_pointer_listener(
        enter: { data, _, serial, surface, sx, sy in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.pointerEntered(serial: serial, surface: surface, x: wl_fixed_to_double(sx), y: wl_fixed_to_double(sy)) }
        },
        leave: { data, _, _, surface in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.pointerLeft(surface: surface) }
        },
        motion: { data, _, time, sx, sy in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.pointerMoved(time: time, x: wl_fixed_to_double(sx), y: wl_fixed_to_double(sy)) }
        },
        button: { data, _, serial, time, button, state in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated {
                backend.lastInputSerial = serial
                if state == UInt32(WL_POINTER_BUTTON_STATE_PRESSED.rawValue) { backend.lastButtonSerial = serial }
                backend.pointerButton(time: time, button: button, pressed: state == UInt32(WL_POINTER_BUTTON_STATE_PRESSED.rawValue))
            }
        },
        axis: { data, _, time, axis, value in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.pointerAxis(time: time, axis: axis, value: wl_fixed_to_double(value)) }
        },
        frame: { data, _ in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.pointerFrame() }
        },
        axis_source: { _, _, _ in },
        axis_stop: { _, _, _, _ in },
        axis_discrete: { _, _, _, _ in },
        axis_value120: { _, _, _, _ in },            // v8+, never sent at the version bound here
        axis_relative_direction: { _, _, _, _ in })) // v9+

    private func pointerEntered(serial: UInt32, surface: OpaquePointer?, x: Double, y: Double) {
        pointerEnterSerial = serial
        lastInputSerial = serial
        pointerFocus = window(for: surface)
        pointerPosition = NSPoint(x: x, y: y)
        applyCursor()
        pointerFocus?.pointerMoved(time: 0, position: pointerPosition)
    }

    private func pointerLeft(surface: OpaquePointer?) {
        if pointerFocus?.surface == surface {
            pointerFocus?.pointerLeft()
            pointerFocus = nil
        }
    }

    private func pointerMoved(time: UInt32, x: Double, y: Double) {
        pointerPosition = NSPoint(x: x, y: y)
        pointerFocus?.pointerMoved(time: time, position: pointerPosition)
    }

    private func pointerButton(time: UInt32, button: UInt32, pressed: Bool) {
        pointerFocus?.pointerButton(time: time, button: button, pressed: pressed, position: pointerPosition)
    }

    // MARK: Pointer gestures (zwp_pointer_gestures_v1: touchpad pinch and swipe)

    private func attachPointerGestures() {
        guard let pointerGestures, let pointer, pinchGesture == nil else { return }
        pinchGesture = zwp_pointer_gestures_v1_get_pinch_gesture(pointerGestures, pointer)
        zwp_pointer_gesture_pinch_v1_add_listener(pinchGesture, WaylandBackend.pinchListener, opaque)
        swipeGesture = zwp_pointer_gestures_v1_get_swipe_gesture(pointerGestures, pointer)
        zwp_pointer_gesture_swipe_v1_add_listener(swipeGesture, WaylandBackend.swipeListener, opaque)
    }

    private static let pinchListener = WaylandBackend.listener(zwp_pointer_gesture_pinch_v1_listener(
        begin: { data, _, _, time, surface, _ in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated {
                backend.gestureFocus = backend.window(for: surface)
                backend.gestureFocus?.pinchBegin(time: time, position: backend.pointerPosition)
            }
        },
        update: { data, _, time, _, _, scale, rotation in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.gestureFocus?.pinchUpdate(time: time, scale: wl_fixed_to_double(scale), rotation: wl_fixed_to_double(rotation), position: backend.pointerPosition) }
        },
        end: { data, _, _, time, cancelled in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.gestureFocus?.pinchEnd(time: time, cancelled: cancelled != 0, position: backend.pointerPosition) }
        }))

    private static let swipeListener = WaylandBackend.listener(zwp_pointer_gesture_swipe_v1_listener(
        begin: { data, _, _, time, surface, _ in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated {
                backend.gestureFocus = backend.window(for: surface)
                backend.gestureFocus?.swipeBegin(time: time)
            }
        },
        update: { data, _, time, dx, dy in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.gestureFocus?.swipeUpdate(time: time, dx: wl_fixed_to_double(dx), dy: wl_fixed_to_double(dy)) }
        },
        end: { data, _, _, time, cancelled in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.gestureFocus?.swipeEnd(time: time, cancelled: cancelled != 0, position: backend.pointerPosition) }
        }))

    private func pointerAxis(time: UInt32, axis: UInt32, value: Double) {
        // Wayland: positive is down/right; AppKit: positive deltaY scrolls content down
        // (wheel up). One wheel notch is 15 units in most compositors, 3 lines in AppKit.
        let delta = -CGFloat(value) / 5
        if axis == UInt32(WL_POINTER_AXIS_VERTICAL_SCROLL.rawValue) { pendingAxis.y += delta } else { pendingAxis.x += delta }
        pendingAxis.time = time
        pendingAxis.has = true
        if let pointer, wl_pointer_get_version(pointer) < 5 { pointerFrame() }   // no frame events before v5
    }

    private func pointerFrame() {
        guard pendingAxis.has else { return }
        let axis = pendingAxis
        pendingAxis = (0, 0, 0, false)
        pointerFocus?.scroll(time: axis.time, deltaX: axis.x, deltaY: axis.y, position: pointerPosition)
    }

    // MARK: Keyboard

    private static let keyboardListener = WaylandBackend.listener(wl_keyboard_listener(
        keymap: { data, _, format, fd, size in
            guard let backend = WaylandBackend.from(data) else { close(fd); return }
            MainActor.assumeIsolated { backend.keymap(format: format, fd: fd, size: size) }
        },
        enter: { data, _, serial, surface, _ in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.lastInputSerial = serial; backend.keyboardEntered(surface: surface) }
        },
        leave: { data, _, _, surface in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.keyboardLeft(surface: surface) }
        },
        key: { data, _, serial, time, key, state in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated {
                backend.lastInputSerial = serial
                backend.key(time: time, key: key, pressed: state == UInt32(WL_KEYBOARD_KEY_STATE_PRESSED.rawValue))
            }
        },
        modifiers: { data, _, _, depressed, latched, locked, group in
            guard let backend = WaylandBackend.from(data) else { return }
            MainActor.assumeIsolated { backend.modifiers(depressed: depressed, latched: latched, locked: locked, group: group) }
        },
        repeat_info: { _, _, _, _ in }))

    private func keymap(format: UInt32, fd: Int32, size: UInt32) {
        defer { close(fd) }
        guard format == UInt32(WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1.rawValue), let ctx = xkbContext else { return }
        guard let map = mmap(nil, Int(size), PROT_READ, MAP_PRIVATE, fd, 0), map != appkitwin_mmap_failed() else { return }
        defer { munmap(map, Int(size)) }
        let keymap = xkb_keymap_new_from_string(ctx, map.assumingMemoryBound(to: CChar.self), XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS)
        guard let keymap else { return }
        if let s = xkbState { xkb_state_unref(s) }
        if let k = xkbKeymap { xkb_keymap_unref(k) }
        xkbKeymap = keymap
        xkbState = xkb_state_new(keymap)
    }

    private func keyboardEntered(surface: OpaquePointer?) {
        keyboardFocus = window(for: surface)
        keyboardFocus?.setKey(true)
    }

    private func keyboardLeft(surface: OpaquePointer?) {
        if keyboardFocus?.surface == surface {
            keyboardFocus?.setKey(false)
            keyboardFocus = nil
        }
    }

    private func modifiers(depressed: UInt32, latched: UInt32, locked: UInt32, group: UInt32) {
        guard let state = xkbState else { return }
        xkb_state_update_mask(state, depressed, latched, locked, 0, 0, group)
        var flags: NSEvent.ModifierFlags = []
        func active(_ name: String) -> Bool { xkb_state_mod_name_is_active(state, name, XKB_STATE_MODS_EFFECTIVE) > 0 }
        if active("Shift") { flags.insert(.shift) }
        if active("Lock") { flags.insert(.capsLock) }
        // Ctrl plays Command (as on Windows and X11) so key equivalents land on Ctrl+key; Super maps to .control.
        if active("Control") { flags.insert(.command) }
        if active("Mod1") { flags.insert(.option) }
        if active("Mod4") { flags.insert(.control) }
        modifierFlags = flags
        NSEvent._currentModifierFlags = flags
    }

    private func key(time: UInt32, key: UInt32, pressed: Bool) {
        guard let state = xkbState, let keymap = xkbKeymap else { return }
        let keycode = key + 8      // evdev -> xkb keycode
        let keysym = UInt(xkb_state_key_get_one_sym(state, keycode))
        var buffer = [CChar](repeating: 0, count: 32)
        let n = xkb_state_key_get_utf8(state, keycode, &buffer, 32)
        let chars = n > 0 ? String(cString: buffer) : ""
        // The level-0 keysym of the key's layout: what the key produces without modifiers.
        var plain = chars
        let layout = xkb_state_key_get_layout(state, keycode)
        var syms: UnsafePointer<xkb_keysym_t>? = nil
        if xkb_keymap_key_get_syms_by_level(keymap, keycode, layout, 0, &syms) > 0, let s = syms?.pointee {
            let cp = xkb_keysym_to_utf32(s)
            if cp != 0, let scalar = UnicodeScalar(cp) { plain = String(scalar) }
        }
        keyboardFocus?.key(time: time, keysym: keysym, characters: chars, charactersIgnoringModifiers: plain, pressed: pressed)
    }
}
#endif
