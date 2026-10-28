// Linux backend: X11 windows, Cairo drawing, PangoCairo text (Milestone 8).
//
// One X display, windows painted into Cairo image surfaces and blitted to the X window,
// an event loop over poll() that also serves posted blocks and the Core Animation frame
// clock. Menus have no native bar on X11 (key equivalents still work), the pasteboard is
// in-process, and file dialogs run zenity when it is installed.

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

    init() {
        guard let d = XOpenDisplay(nil) else {
            fatalError("AppKitWin: cannot open the X display (is DISPLAY set?)")
        }
        display = d
        screen = XDefaultScreen(d)
        root = XRootWindow(d, screen)
        var dpi = 96.0
        if let value = XGetDefault(d, "Xft", "dpi"), let v = Double(String(cString: value)), v > 0 { dpi = v }
        scale = CGFloat(dpi / 96)
        screenHeightPx = CGFloat(XDisplayHeight(d, screen))
        wmDeleteWindow = XInternAtom(d, "WM_DELETE_WINDOW", 0)
        wmProtocols = XInternAtom(d, "WM_PROTOCOLS", 0)
        netWmName = XInternAtom(d, "_NET_WM_NAME", 0)
        utf8String = XInternAtom(d, "UTF8_STRING", 0)
        var fds: [Int32] = [-1, -1]
        if pipe(&fds) == 0 { wakePipe = fds }
        text = LinuxTextBackend()
        image = LinuxImageBackend()
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

    func register(_ window: LinuxWindow) { windows.append(window) }
    func unregister(_ window: LinuxWindow) { windows.removeAll { $0 === window } }
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
        if blocking && XPending(display) == 0 {
            var fds = [pollfd(fd: XConnectionNumber(display), events: Int16(POLLIN), revents: 0),
                       pollfd(fd: wakePipe[0], events: Int16(POLLIN), revents: 0)]
            var timeout: Int32 = -1
            if let next = frameCallbacks.map(\.deadline).min() {
                timeout = Int32(max(0, (next - ProcessInfo.processInfo.systemUptime) * 1000))
            }
            if windows.contains(where: { $0.needsPaint }) { timeout = 0 }
            _ = poll(&fds, 2, timeout)
            if fds[1].revents != 0 {
                var buf = [UInt8](repeating: 0, count: 64)
                _ = read(wakePipe[0], &buf, 64)
            }
        }
        while XPending(display) > 0 {
            var event = XEvent()
            XNextEvent(display, &event)
            dispatch(&event)
        }
        drainPosted()
        fireDueFrames()
        for w in windows where w.needsPaint { w.paintIfNeeded() }
        XFlush(display)
    }

    private func dispatch(_ event: inout XEvent) {
        let xid = event.xany.window
        guard let w = window(for: xid) else { return }
        w.handle(&event)
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

    var mouseLocation: NSPoint {
        var rootReturn: Window = 0, childReturn: Window = 0
        var rx: Int32 = 0, ry: Int32 = 0, wx: Int32 = 0, wy: Int32 = 0
        var mask: UInt32 = 0
        _ = XQueryPointer(display, root, &rootReturn, &childReturn, &rx, &ry, &wx, &wy, &mask)
        return NSPoint(x: CGFloat(rx) / scale, y: (screenHeightPx - CGFloat(ry)) / scale)
    }

    let text: any PlatformTextBackend
    let image: any PlatformImageBackend
    let systemPasteboard: any PlatformPasteboard = LinuxPasteboard()

    /// Runs zenity when available; otherwise the dialog is cancelled.
    func runFileDialog(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]? {
        let zenity = ["/usr/bin/zenity", "/usr/local/bin/zenity"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let zenity else { return nil }
        var args = ["--file-selection"]
        if options.isSave { args.append("--save"); args.append("--confirm-overwrite") }
        if options.canChooseDirectories && !options.canChooseFiles { args.append("--directory") }
        if options.allowsMultipleSelection { args += ["--multiple", "--separator=\n"] }
        if let t = options.title { args.append("--title=\(t)") }
        if let name = options.defaultName { args.append("--filename=\((options.directory?.path ?? NSHomeDirectory()) + "/" + name)") }
        else if let dir = options.directory { args.append("--filename=\(dir.path)/") }
        if !options.allowedExtensions.isEmpty {
            args.append("--file-filter=Supported files | " + options.allowedExtensions.map { "*.\($0)" }.joined(separator: " "))
            if options.allowsOtherTypes { args.append("--file-filter=All files | *") }
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: zenity)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let paths = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return paths.isEmpty ? nil : paths.map { URL(fileURLWithPath: $0) }
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
        // X11 has no native menu bar; NSApplication still dispatches key equivalents.
    }

    func frameRect(forContentRect contentRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect { contentRect }
    func contentRect(forFrameRect frameRect: NSRect, styleMask: NSWindow.StyleMask) -> NSRect { frameRect }
}

@MainActor
final class LinuxPasteboard: PlatformPasteboard {
    private var entries: [PlatformPasteboardEntry] = []
    private(set) var changeCount = 0
    func write(_ entries: [PlatformPasteboardEntry]) { self.entries = entries; changeCount += 1 }
    func read() -> [PlatformPasteboardEntry] { entries }
}
#endif
