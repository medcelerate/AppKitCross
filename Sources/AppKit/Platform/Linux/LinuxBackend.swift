// Linux backend: X11 windows, Cairo drawing, PangoCairo text (Milestone 8).
//
// One X display, windows painted into Cairo image surfaces and blitted to the X window,
// an event loop over poll() that also serves posted blocks and the Core Animation frame
// clock. Menus have no native bar on X11 (key equivalents still work), the pasteboard is
// the CLIPBOARD selection and drags use XDND (LinuxSelection.swift, LinuxDragDrop.swift),
// and file dialogs go through the xdg-desktop-portal FileChooser (LinuxFileChooserPortal.swift).

#if os(Linux)
import Foundation
import Glibc
import CoreGraphics
import CCairo
import CX11

@MainActor
final class LinuxBackend: PlatformBackend {
    let display: OpaquePointer                  // Display*
    let screen: Int32
    let root: Window
    /// The XInput extension's opcode when the server speaks XI 2.4 (gestures); nil otherwise.
    private(set) var xiGestureOpcode: Int32?
    let scale: CGFloat
    /// Screen height in pixels, for the y flip between AppKit and X coordinates.
    let screenHeightPx: CGFloat
    private(set) var windows: [LinuxWindow] = []
    private var running = false
    private var posted: [@MainActor () -> Void] = []
    private var frameCallbacks: [(deadline: TimeInterval, callback: @MainActor () -> Void)] = []
    private var wakePipe: [Int32] = [-1, -1]
    let wmDeleteWindow: Atom
    let wmProtocols: Atom
    let netWmName: Atom
    let utf8String: Atom
    private var cursors: [Int32: Cursor] = [:]
    private(set) var currentCursor: Cursor = 0
    private var cursorHidden = false
    // Selections (LinuxSelection.swift) and XDND (LinuxDragDrop.swift)
    var atoms: [String: Atom] = [:]
    var selectionWindow: Window = 0
    /// The server time of the last input event, for selection ownership and XDND.
    var lastEventTime: Time = Time(CurrentTime)
    private(set) var x11DragDrop: X11DragDrop!
    var dragDrop: (any PlatformDragDrop)? { x11DragDrop }
    /// Printing (LinuxPrinting.swift): Cairo PDF and CUPS.
    let linuxPrinting = LinuxPrintBackend()
    var printing: (any PlatformPrintBackend)? { linuxPrinting }
    /// StatusNotifierItems over the session bus (LinuxStatusItem.swift); made on first use.
    private var statusNotifier: LinuxStatusNotifierHost?
    private var statusNotifierTried = false
    var statusItems: (any PlatformStatusItemHost)? {
        if !statusNotifierTried {
            statusNotifierTried = true
            statusNotifier = LinuxStatusNotifierHost.connect { [unowned self] x, y in NSPoint(x: CGFloat(x) / scale, y: (screenHeightPx - CGFloat(y)) / scale) }
        }
        return statusNotifier
    }
    /// AT-SPI2 over D-Bus (LinuxAccessibility.swift, ADR-0013); nil without an accessibility bus.
    private(set) var atspi: AtspiBridge?

    init() {
        guard let d = XOpenDisplay(nil) else {
            fatalError("AppKitCross: cannot open the X display (is DISPLAY set?)")
        }
        display = d
        screen = XDefaultScreen(d)
        root = XRootWindow(d, screen)
        var dpi = 96.0
        if let value = XGetDefault(d, "Xft", "dpi"), let v = Double(String(cString: value)), v > 0 { dpi = v }
        scale = CGFloat(dpi / 96)
        screenHeightPx = CGFloat(XDisplayHeight(d, screen))
        // XInput 2.4 delivers touchpad pinch and swipe gestures (libinput); older
        // servers answer with a lower version and the windows then select none.
        var opcode: Int32 = 0, firstEvent: Int32 = 0, firstError: Int32 = 0
        if XQueryExtension(d, "XInputExtension", &opcode, &firstEvent, &firstError) != 0 {
            var major: Int32 = 2, minor: Int32 = 4
            if XIQueryVersion(d, &major, &minor) == Success, major > 2 || (major == 2 && minor >= 4) { xiGestureOpcode = opcode }
        }
        wmDeleteWindow = XInternAtom(d, "WM_DELETE_WINDOW", 0)
        wmProtocols = XInternAtom(d, "WM_PROTOCOLS", 0)
        netWmName = XInternAtom(d, "_NET_WM_NAME", 0)
        utf8String = XInternAtom(d, "UTF8_STRING", 0)
        var fds: [Int32] = [-1, -1]
        if pipe(&fds) == 0 { wakePipe = fds }
        text = HostTextBackend()      // CoreText over Pango/HarfBuzz (ADR-0007)
        image = LinuxImageBackend()
        x11DragDrop = X11DragDrop(backend: self)
        atspi = AtspiBridge.connect(rootWindowProperty: { [self] in atspiBusFromRootWindow() })
    }

    /// The accessibility bus address the bus launcher stores on the root window.
    private func atspiBusFromRootWindow() -> String? {
        let atom = XInternAtom(display, "AT_SPI_BUS", 1)
        guard atom != 0 else { return nil }
        var actualType: Atom = 0, format: Int32 = 0, count: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>? = nil
        guard XGetWindowProperty(display, root, atom, 0, 1024, 0, Atom(0), &actualType, &format, &count, &after, &data) == 0, let data else { return nil }
        defer { XFree(data) }
        guard format == 8, count > 0 else { return nil }
        return String(decoding: UnsafeBufferPointer(start: data, count: Int(count)), as: UTF8.self)
    }

    var displays: [PlatformDisplay] {
        let w = CGFloat(XDisplayWidth(display, screen)) / scale
        let h = screenHeightPx / scale
        return [PlatformDisplay(frame: NSRect(x: 0, y: 0, width: w, height: h),
                                visibleFrame: NSRect(x: 0, y: 0, width: w, height: h),
                                backingScaleFactor: scale, localizedName: "X11 Display", isMain: true)]
    }

    func makeWindow(owner: PlatformWindowOwner, contentRect: NSRect, styleMask: NSWindow.StyleMask) -> PlatformWindow {
        LinuxWindow(backend: self, owner: owner, contentRect: contentRect, styleMask: styleMask)
    }

    func register(_ window: LinuxWindow) { windows.append(window); atspi?.register(window) }
    func unregister(_ window: LinuxWindow) {
        if windows.contains(where: { $0 === window }) { atspi?.unregister(window) }
        windows.removeAll { $0 === window }
    }
    func window(for id: Window) -> LinuxWindow? { windows.first { $0.xid == id } }

    // MARK: Event loop

    func run() {
        running = true
        while running { pump(blocking: true) }
    }

    func stop() {
        running = false
        wake()
    }

    /// Handles pending X events, posted blocks, due frames and repaints. With `blocking`
    /// it waits for the next event or deadline.
    func pump(blocking: Bool) {
        drainPosted()
        let nextTimer = PlatformMainQueue.service()
        if blocking && XPending(display) == 0 {
            var fds = [pollfd(fd: XConnectionNumber(display), events: Int16(POLLIN), revents: 0),
                       pollfd(fd: wakePipe[0], events: Int16(POLLIN), revents: 0),
                       pollfd(fd: PlatformMainQueue.fileDescriptor, events: Int16(POLLIN), revents: 0)]
            if let a = atspi, a.fileDescriptor >= 0 { fds.append(pollfd(fd: a.fileDescriptor, events: Int16(POLLIN), revents: 0)) }
            if let s = statusNotifier, s.fileDescriptor >= 0 { fds.append(pollfd(fd: s.fileDescriptor, events: Int16(POLLIN), revents: 0)) }
            var timeout: Int32 = -1
            if let next = frameCallbacks.map(\.deadline).min() {
                timeout = Int32(max(0, (next - ProcessInfo.processInfo.systemUptime) * 1000))
            }
            if let t = nextTimer { let ms = Int32(min(Double(Int32.max), t * 1000)); timeout = timeout < 0 ? ms : min(timeout, ms) }
            if windows.contains(where: { $0.needsPaint }) { timeout = 0 }
            _ = poll(&fds, nfds_t(fds.count), timeout)
            if fds[1].revents != 0 {
                var buf = [UInt8](repeating: 0, count: 64)
                _ = read(wakePipe[0], &buf, 64)
            }
            if fds[2].revents != 0 { PlatformMainQueue.service() }
        }
        while XPending(display) > 0 {
            var event = XEvent()
            XNextEvent(display, &event)
            dispatch(&event)
        }
        atspi?.dispatch()
        statusNotifier?.dispatch()
        drainPosted()
        fireDueFrames()
        for w in windows where w.needsPaint { w.paintIfNeeded() }
        XFlush(display)
    }

    private func dispatch(_ event: inout XEvent) {
        let xid = event.xany.window
        if xid == selectionWindow && xid != 0 {
            // Replies and requests for the selections this application owns or asked for.
            switch Int32(event.type) {
            case SelectionRequest:
                if event.xselectionrequest.selection == atom("CLIPBOARD") { x11Pasteboard.handleRequest(event.xselectionrequest) }
                else { _ = x11DragDrop.handle(&event, window: nil) }
            case SelectionClear:
                if event.xselectionclear.selection == atom("CLIPBOARD") { x11Pasteboard.selectionCleared() }
            default:
                _ = x11DragDrop.handle(&event, window: nil)
            }
            return
        }
        if Int32(event.type) == GenericEvent, let opcode = xiGestureOpcode, event.xcookie.extension == opcode {
            guard XGetEventData(display, &event.xcookie) != 0, let data = event.xcookie.data else { return }
            defer { XFreeEventData(display, &event.xcookie) }
            switch event.xcookie.evtype {
            case XI_GesturePinchBegin, XI_GesturePinchUpdate, XI_GesturePinchEnd:
                let g = data.assumingMemoryBound(to: XIGesturePinchEvent.self).pointee
                window(for: g.event)?.gesturePinch(evtype: event.xcookie.evtype, time: g.time, x: g.event_x, y: g.event_y, scale: g.scale,
                                                   deltaAngle: g.delta_angle, state: UInt32(g.mods.effective), cancelled: g.flags & XIGesturePinchEventCancelled != 0)
            case XI_GestureSwipeBegin, XI_GestureSwipeUpdate, XI_GestureSwipeEnd:
                let g = data.assumingMemoryBound(to: XIGestureSwipeEvent.self).pointee
                window(for: g.event)?.gestureSwipe(evtype: event.xcookie.evtype, time: g.time, x: g.event_x, y: g.event_y, dx: g.delta_x, dy: g.delta_y,
                                                   state: UInt32(g.mods.effective), cancelled: g.flags & XIGestureSwipeEventCancelled != 0)
            default: break
            }
            return
        }
        guard let w = window(for: xid) else { return }
        w.handle(&event)
    }

    /// AppKit modifier flags from an X key/button state mask: Ctrl plays Command (as on
    /// Windows) so key equivalents land on Ctrl+key; Super maps to .control.
    static func modifierFlags(fromState state: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if state & UInt32(ShiftMask) != 0 { flags.insert(.shift) }
        if state & UInt32(LockMask) != 0 { flags.insert(.capsLock) }
        if state & UInt32(ControlMask) != 0 { flags.insert(.command) }
        if state & UInt32(Mod1Mask) != 0 { flags.insert(.option) }
        if state & UInt32(Mod4Mask) != 0 { flags.insert(.control) }
        return flags
    }

    /// The modifier keys held now (for events that carry no state, such as XDND messages).
    func queryModifierFlags() -> NSEvent.ModifierFlags {
        var rootReturn: Window = 0, childReturn: Window = 0
        var rx: Int32 = 0, ry: Int32 = 0, wx: Int32 = 0, wy: Int32 = 0
        var mask: UInt32 = 0
        _ = XQueryPointer(display, root, &rootReturn, &childReturn, &rx, &ry, &wx, &wy, &mask)
        let flags = LinuxBackend.modifierFlags(fromState: mask)
        NSEvent._currentModifierFlags = flags
        return flags
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

    private func fireDueFrames() {
        let now = ProcessInfo.processInfo.systemUptime
        let due = frameCallbacks.filter { $0.deadline <= now }
        guard !due.isEmpty else { return }
        frameCallbacks.removeAll { $0.deadline <= now }
        for f in due { f.callback() }
    }

    func beep() { XBell(display, 0) }
    var systemAppearanceIsDark: Bool { false }

    var mouseLocation: NSPoint {
        var rootReturn: Window = 0, childReturn: Window = 0
        var rx: Int32 = 0, ry: Int32 = 0, wx: Int32 = 0, wy: Int32 = 0
        var mask: UInt32 = 0
        _ = XQueryPointer(display, root, &rootReturn, &childReturn, &rx, &ry, &wx, &wy, &mask)
        return NSPoint(x: CGFloat(rx) / scale, y: (screenHeightPx - CGFloat(ry)) / scale)
    }

    let text: any PlatformTextBackend
    let image: any PlatformImageBackend
    /// The CLIPBOARD selection (LinuxSelection.swift).
    private(set) lazy var x11Pasteboard = X11Pasteboard(backend: self)
    var systemPasteboard: any PlatformPasteboard { x11Pasteboard }

    /// The xdg-desktop-portal FileChooser when a portal is on the session bus
    /// (LinuxFileChooserPortal.swift, ADR-0017); otherwise nil and the panels draw themselves.
    private var portalLookedUp = false
    private var portal: LinuxFileChooserPortal?
    var fileDialog: (any PlatformFileDialog)? {
        guard PlatformFileDialogPolicy.allowsNative else { return nil }
        if !portalLookedUp {
            portalLookedUp = true
            portal = LinuxFileChooserPortal.connect(pump: { [weak self] in self?.pump(blocking: false) },
                                                   parentIdentifier: { ($0 as? LinuxWindow).map { "x11:" + String($0.xid, radix: 16) } ?? "" })
        }
        return portal
    }

    func runModal(for window: PlatformWindow?, until stop: @escaping @MainActor () -> Bool) {
        while !stop() && (running || true) {
            pump(blocking: true)
            if !running { break }
        }
    }

    // MARK: Cursors

    /// X cursor font shapes (cursorfont.h).
    private static func shape(for cursor: PlatformCursor) -> Int32 {
        switch cursor {
        case .arrow, .contextualMenu, .dragCopy, .dragLink, .operationNotAllowed, .custom: return 68   // XC_left_ptr
        case .iBeam, .iBeamVertical: return 152                                                           // XC_xterm
        case .crosshair: return 34
        case .pointingHand: return 60                                                                     // XC_hand2
        case .openHand, .closedHand: return 58                                                            // XC_hand1
        case .resizeLeftRight: return 108
        case .resizeUpDown: return 116
        case .resizeAll: return 52                                                                        // XC_fleur
        case .wait: return 150
        }
    }

    func setCursor(_ cursor: PlatformCursor) {
        let shape = LinuxBackend.shape(for: cursor)
        if cursors[shape] == nil { cursors[shape] = XCreateFontCursor(display, UInt32(shape)) }
        currentCursor = cursors[shape] ?? 0
        if !cursorHidden { for w in windows { w.applyCursor(currentCursor) } }
    }

    func setCursorHidden(_ hidden: Bool) {
        cursorHidden = hidden
        for w in windows { w.applyCursor(hidden ? w.blankCursor() : currentCursor) }
    }

    func setMainMenu(_ menu: PlatformMenu?, host: PlatformMenuHost?) {
        // X11 has no native menu bar; NSApplication still dispatches key equivalents. The
        // menu reaches assistive technology as the application's AXMenuBar (ADR-0013).
        if let app = host as? PlatformAccessibilityApplication, atspi?.application !== app { atspi?.application = app }
        else { atspi?.menuBarChanged() }
    }

    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect { contentRect }
    func contentRect(forFrameRect frameRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect { frameRect }
}

#endif
