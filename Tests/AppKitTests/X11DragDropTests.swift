// XDND and the CLIPBOARD selection on the X11 backend, against a second X client in
// this process (its own Display on its own thread) playing the other application.
// These run only with an X display and the X11 backend selected (no
// APPKITWIN_HOST_BACKEND): tools/linux/run.sh runs them under Xvfb.

#if os(Linux)
import XCTest
import Glibc
import CX11
@testable import AppKit

/// Another X client: a window of its own that speaks XDND, driven on a background thread.
private final class XdndPeer: @unchecked Sendable {
    let display: OpaquePointer
    let window: Window
    let root: Window
    private var atoms: [String: Atom] = [:]
    // Results (read from the main thread after `done`)
    nonisolated(unsafe) var done = false
    nonisolated(unsafe) var received: String?
    nonisolated(unsafe) var statusAccepted: Bool?
    nonisolated(unsafe) var finishedAccepted: Bool?
    nonisolated(unsafe) var enteredTypes: [String] = []

    init(x: Int32, y: Int32, width: UInt32, height: UInt32, mapped: Bool) {
        display = XOpenDisplay(nil)!
        let screen = XDefaultScreen(display)
        root = XRootWindow(display, screen)
        window = XCreateSimpleWindow(display, root, x, y, width, height, 0, 0, XWhitePixel(display, screen))
        XSelectInput(display, window, StructureNotifyMask | PropertyChangeMask)
        if mapped {
            var attrs = XSetWindowAttributes()
            attrs.override_redirect = 1        // no window manager in the test display anyway
            XChangeWindowAttributes(display, window, UInt(CWOverrideRedirect), &attrs)
            var version: [UInt] = [5]
            version.withUnsafeMutableBufferPointer { buf in
                _ = XChangeProperty(display, window, atom("XdndAware"), XA_ATOM, 32, PropModeReplace, UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), 1)
            }
            XMapRaised(display, window)
        }
        XFlush(display)
    }

    func atom(_ name: String) -> Atom {
        if let a = atoms[name] { return a }
        let a = XInternAtom(display, name, 0)
        atoms[name] = a
        return a
    }

    func send(to target: Window, _ type: String, _ l: [Int]) {
        var e = XEvent()
        e.xclient.type = ClientMessage
        e.xclient.display = display
        e.xclient.window = target
        e.xclient.message_type = atom(type)
        e.xclient.format = 32
        e.xclient.data.l = (l[0], l[1], l[2], l[3], l[4])
        _ = XSendEvent(display, target, 0, 0, &e)
        XFlush(display)
    }

    /// Waits for the next event of `type` on our window (or a client message of `message`).
    func wait(type: Int32, message: String? = nil, timeout: TimeInterval = 5) -> XEvent? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if XPending(display) > 0 {
                var e = XEvent()
                XNextEvent(display, &e)
                if Int32(e.type) == type, message == nil || e.xclient.message_type == atom(message!) { return e }
                if Int32(e.type) == SelectionRequest { serve(e.xselectionrequest) }
                continue
            }
            var fds = [pollfd(fd: XConnectionNumber(display), events: Int16(POLLIN), revents: 0)]
            _ = poll(&fds, 1, 50)
        }
        return nil
    }

    var text = "from the other client"

    /// Serves our XdndSelection: TARGETS and the UTF-8 text.
    func serve(_ r: XSelectionRequestEvent) {
        var reply = XEvent()
        reply.xselection.type = SelectionNotify
        reply.xselection.display = display
        reply.xselection.requestor = r.requestor
        reply.xselection.selection = r.selection
        reply.xselection.target = r.target
        reply.xselection.time = r.time
        reply.xselection.property = 0
        if r.target == atom("TARGETS") {
            var list = [atom("TARGETS"), atom("text/plain;charset=utf-8")]
            list.withUnsafeMutableBufferPointer { buf in
                _ = XChangeProperty(display, r.requestor, r.property, XA_ATOM, 32, PropModeReplace, UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), Int32(buf.count))
            }
            reply.xselection.property = r.property
        } else if r.target == atom("text/plain;charset=utf-8") || r.target == atom("UTF8_STRING") {
            let bytes = Array(text.utf8)
            bytes.withUnsafeBufferPointer { buf in
                _ = XChangeProperty(display, r.requestor, r.property, r.target, 8, PropModeReplace, buf.baseAddress, Int32(buf.count))
            }
            reply.xselection.property = r.property
        }
        _ = XSendEvent(display, r.requestor, 0, 0, &reply)
        XFlush(display)
    }

    /// Converts a selection to `target` and returns the bytes.
    func convert(_ selection: String, target: String) -> String? {
        let property = atom("PEER_SELECTION")
        XConvertSelection(display, atom(selection), atom(target), property, window, Time(CurrentTime))
        XFlush(display)
        guard let e = wait(type: SelectionNotify), e.xselection.property != 0 else { return nil }
        var type: Atom = 0; var format: Int32 = 0; var count: UInt = 0; var remaining: UInt = 0
        var bytes: UnsafeMutablePointer<UInt8>? = nil
        guard XGetWindowProperty(display, window, property, 0, 0x7FFF_FFFF, 1, Atom(AnyPropertyType), &type, &format, &count, &remaining, &bytes) == Success, let bytes else { return nil }
        defer { XFree(bytes) }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(count)), as: UTF8.self)
    }

    /// Acts as an XDND source dropping `text` on `target` at root pixel (x, y).
    func dropText(on target: Window, x: Int, y: Int) {
        Thread.detachNewThread { [self] in
            XSetSelectionOwner(display, atom("XdndSelection"), window, Time(CurrentTime))
            send(to: target, "XdndEnter", [Int(window), 5 << 24, Int(atom("text/plain;charset=utf-8")), 0, 0])
            send(to: target, "XdndPosition", [Int(window), 0, (x << 16) | y, 0, Int(atom("XdndActionCopy"))])
            guard let status = wait(type: ClientMessage, message: "XdndStatus") else { done = true; return }
            statusAccepted = status.xclient.data.l.1 & 1 != 0
            send(to: target, "XdndDrop", [Int(window), 0, 0, 0, 0])
            if let finished = wait(type: ClientMessage, message: "XdndFinished") {
                finishedAccepted = finished.xclient.data.l.1 & 1 != 0
            }
            done = true
        }
    }

    /// Acts as an XDND target: accepts a copy and reads the text on drop.
    func acceptDrops() {
        Thread.detachNewThread { [self] in
            var source: Window = 0
            while !done {
                guard let e = wait(type: ClientMessage, timeout: 10) else { break }
                let m = e.xclient
                if m.message_type == atom("XdndEnter") {
                    source = Window(m.data.l.0)
                    enteredTypes = [m.data.l.2, m.data.l.3, m.data.l.4].filter { $0 != 0 }.map { a -> String in
                        let p = XGetAtomName(display, Atom(a))!; defer { XFree(p) }; return String(cString: p)
                    }
                } else if m.message_type == atom("XdndPosition") {
                    send(to: source, "XdndStatus", [Int(window), 1 | 2, 0, 0, Int(atom("XdndActionCopy"))])
                } else if m.message_type == atom("XdndDrop") {
                    received = convert("XdndSelection", target: "text/plain;charset=utf-8")
                    send(to: source, "XdndFinished", [Int(window), received != nil ? 1 : 0, Int(atom("XdndActionCopy")), 0, 0])
                    done = true
                } else if m.message_type == atom("XdndLeave") {
                    done = true
                }
            }
            done = true
        }
    }
}

@MainActor
private final class DropView: NSView {
    var dropped: String?
    var log: [String] = []
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.string]) }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { log.append("entered"); return .copy }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropped = sender.draggingPasteboard.string(forType: .string)
        return dropped != nil
    }
}

@MainActor
private final class DragView: NSView, NSDraggingSource {
    var log: [String] = []
    override func mouseDragged(with event: NSEvent) {
        let item = NSPasteboardItem()
        _ = item.setString("dragged out", forType: .string)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(NSRect(x: 0, y: 0, width: 40, height: 20), contents: nil)
        _ = beginDraggingSession(with: [dragging], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .move] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { log.append("end \(operation.rawValue)") }
}

final class X11DragDropTests: XCTestCase, @unchecked Sendable {
    private func x11Backend() throws -> LinuxBackend {
        guard ProcessInfo.processInfo.environment["DISPLAY"] != nil, let b = MainActor.assumeIsolated({ Platform.backend as? LinuxBackend }) else { throw XCTSkip("needs the X11 backend (DISPLAY set, APPKITWIN_HOST_BACKEND unset)") }
        return b
    }

    @MainActor
    private func pump(_ backend: LinuxBackend, until condition: () -> Bool, timeout: TimeInterval = 6) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline { backend.pump(blocking: false); usleep(5000) }
    }

    @MainActor
    private func send(_ type: NSEvent.EventType, _ point: NSPoint, in w: NSWindow) {
        let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApplication.shared.sendEvent(e)
    }

    func testDropFromAnotherClient() throws {
        let backend = try x11Backend()
        try MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let view = DropView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            w.contentView!.addSubview(view)
            w.makeKeyAndOrderFront(nil)
            guard let xw = w._platformWindow as? LinuxWindow else { throw XCTSkip("not an X11 window") }
            pump(backend, until: { xw.isVisible }, timeout: 3)
            XSync(backend.display, 0)
            // Root pixel inside the window: its frame is in AppKit points, y up.
            let scale = backend.scale
            let px = Int((w.frame.minX + 150) * scale), py = Int(backend.screenHeightPx - (w.frame.minY + 100) * scale)
            let peer = XdndPeer(x: 0, y: 0, width: 1, height: 1, mapped: false)
            peer.dropText(on: xw.xid, x: px, y: py)
            pump(backend, until: { peer.done })
            XCTAssertTrue(peer.done, "the peer finished its drag")
            XCTAssertEqual(peer.statusAccepted, true, "XdndStatus accepted the copy")
            XCTAssertEqual(view.log, ["entered"])
            XCTAssertEqual(view.dropped, "from the other client")
            XCTAssertEqual(peer.finishedAccepted, true)
            w.close()
        }
    }

    func testDragToAnotherClient() throws {
        let backend = try x11Backend()
        try MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let source = DragView(frame: NSRect(x: 10, y: 10, width: 80, height: 40))
            w.contentView!.addSubview(source)
            w.makeKeyAndOrderFront(nil)
            guard let xw = w._platformWindow as? LinuxWindow else { throw XCTSkip("not an X11 window") }
            pump(backend, until: { xw.isVisible }, timeout: 3)
            // The peer's window sits to the right of ours (root pixels), mapped and XdndAware.
            let scale = backend.scale
            let peerX: Int32 = 600, peerY: Int32 = 100
            let peer = XdndPeer(x: peerX, y: peerY, width: 200, height: 200, mapped: true)
            XSync(peer.display, 0)
            XSync(backend.display, 0)
            peer.acceptDrops()
            send(.leftMouseDown, NSPoint(x: 30, y: 20), in: w)
            send(.leftMouseDragged, NSPoint(x: 40, y: 25), in: w)
            XCTAssertTrue(_NSDragTracker.isDragging)
            // A point over the peer, in AppKit screen coordinates, as a window-relative event.
            let screen = NSPoint(x: CGFloat(peerX + 100) / scale, y: (backend.screenHeightPx - CGFloat(peerY + 100)) / scale)
            let local = w.convertPoint(fromScreen: screen)
            send(.leftMouseDragged, local, in: w)
            pump(backend, until: { !peer.enteredTypes.isEmpty }, timeout: 3)
            XCTAssertTrue(peer.enteredTypes.contains("text/plain;charset=utf-8"), "XdndEnter carried the text target: \(peer.enteredTypes)")
            // Give the status time to come back, move once more, then release.
            pump(backend, until: { false }, timeout: 0.3)
            send(.leftMouseDragged, NSPoint(x: local.x + 1, y: local.y), in: w)
            pump(backend, until: { false }, timeout: 0.3)
            send(.leftMouseUp, NSPoint(x: local.x + 1, y: local.y), in: w)
            pump(backend, until: { peer.done && !source.log.isEmpty })
            XCTAssertEqual(peer.received, "dragged out")
            XCTAssertEqual(source.log, ["end \(NSDragOperation.copy.rawValue)"])
            XCTAssertFalse(_NSDragTracker.isDragging)
            w.close()
        }
    }
}

final class X11ClipboardTests: XCTestCase, @unchecked Sendable {
    private func x11Backend() throws -> LinuxBackend {
        guard ProcessInfo.processInfo.environment["DISPLAY"] != nil, let b = MainActor.assumeIsolated({ Platform.backend as? LinuxBackend }) else { throw XCTSkip("needs the X11 backend") }
        return b
    }

    func testClipboardRoundTripWithAnotherClient() throws {
        let backend = try x11Backend()
        try MainActor.assumeIsolated {
            let peer = XdndPeer(x: 0, y: 0, width: 1, height: 1, mapped: false)
            // Ours to theirs.
            let pb = NSPasteboard.general
            _ = pb.clearContents()
            _ = pb.setString("copied in appkitwin", forType: .string)
            nonisolated(unsafe) var seen: String? = nil
            nonisolated(unsafe) var finished = false
            Thread.detachNewThread {
                seen = peer.convert("CLIPBOARD", target: "UTF8_STRING")
                finished = true
            }
            let deadline = Date(timeIntervalSinceNow: 5)
            while !finished && Date() < deadline { backend.pump(blocking: false); usleep(5000) }
            XCTAssertEqual(seen, "copied in appkitwin")
            // Theirs to ours: the peer takes the selection and serves it.
            peer.text = "copied elsewhere"
            XSetSelectionOwner(peer.display, peer.atom("CLIPBOARD"), peer.window, Time(CurrentTime))
            XFlush(peer.display)
            nonisolated(unsafe) var stop = false
            Thread.detachNewThread {
                while !stop { _ = peer.wait(type: -1, timeout: 0.1) }     // serves SelectionRequest meanwhile
            }
            backend.pump(blocking: false)       // SelectionClear
            Thread.sleep(forTimeInterval: 0.3)  // past the change-count throttle
            let got = pb.string(forType: .string)
            stop = true
            XCTAssertEqual(got, "copied elsewhere")
        }
    }
}
#endif
