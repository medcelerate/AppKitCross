// XDND (version 5) for the X11 backend: drags to and from other applications.
//
// Source: the application keeps the pointer during its own drags (the implicit grab of
// the pressed button delivers motion to the source window wherever the pointer goes), so
// `_NSDragTracker` stays in charge and asks this object about the window under the
// pointer whenever none of this application's windows is there. It finds the topmost
// XdndAware window under the point, speaks XdndEnter/Position/Leave/Drop to it, and
// serves the XdndSelection from the entries the tracker handed over.
//
// Target: every window carries XdndAware; the Xdnd client messages arrive at it and are
// delivered to its owner through the `PlatformWindowOwner` drag methods, with the data
// converted from the source's XdndSelection on demand.

#if os(Linux)
import Foundation
import Glibc
import CX11

@MainActor
final class X11DragDrop: PlatformDragDrop {
    private unowned let backend: LinuxBackend
    init(backend: LinuxBackend) { self.backend = backend }

    private var display: OpaquePointer { backend.display }
    private var xdndSelection: Atom { backend.atom("XdndSelection") }
    private var actionCopy: Atom { backend.atom("XdndActionCopy") }
    private var actionMove: Atom { backend.atom("XdndActionMove") }
    private var actionLink: Atom { backend.atom("XdndActionLink") }
    private var actionPrivate: Atom { backend.atom("XdndActionPrivate") }

    private func action(for op: NSDragOperation) -> Atom {
        if op.contains(.copy) { return actionCopy }
        if op.contains(.move) { return actionMove }
        if op.contains(.link) { return actionLink }
        if op.contains(.generic) || op.contains(.private) { return actionPrivate }
        return 0
    }

    private func operation(for action: Atom) -> NSDragOperation {
        if action == actionCopy { return .copy }
        if action == actionMove { return .move }
        if action == actionLink { return .link }
        if action == actionPrivate || action == backend.atom("XdndActionAsk") { return .generic }
        return []
    }

    private func sendClientMessage(to window: Window, type: String, _ l: [Int]) {
        var event = XEvent()
        event.xclient.type = ClientMessage
        event.xclient.display = display
        event.xclient.window = window
        event.xclient.message_type = backend.atom(type)
        event.xclient.format = 32
        event.xclient.data.l = (l.count > 0 ? l[0] : 0, l.count > 1 ? l[1] : 0, l.count > 2 ? l[2] : 0, l.count > 3 ? l[3] : 0, l.count > 4 ? l[4] : 0)
        _ = XSendEvent(display, window, 0, 0, &event)
        XFlush(display)
    }

    // MARK: Source

    private var entries: [PlatformPasteboardEntry] = []
    private var operations: NSDragOperation = []
    private weak var source: (any PlatformDragSource)?
    private var selectionTime: Time = 0
    private var target: Window = 0
    private var targetVersion = 5
    private var targetAccepted = false
    private var targetAction: Atom = 0
    private var awaitingStatus = false
    private var pendingPosition: (x: Int, y: Int, time: Time, op: NSDragOperation)? = nil
    private var dropped = false
    private var lastPoint = NSPoint.zero

    var isDragging: Bool { source != nil }

    func beginDrag(from window: PlatformWindow, entries: [(item: Int, entry: PlatformPasteboardEntry)], operations: NSDragOperation,
                   image: PlatformDragImage?, source: any PlatformDragSource) -> Bool {
        self.entries = entries.map(\.entry)
        self.operations = operations
        self.source = source
        target = 0
        dropped = false
        selectionTime = backend.lastEventTime
        let w = backend.ensureSelectionWindow()
        XSetSelectionOwner(display, xdndSelection, w, selectionTime)
        // More than three types go in XdndTypeList on the source window.
        var atoms = LinuxMime.offeredTargets(for: self.entries).map { backend.atom($0) }
        atoms.withUnsafeMutableBufferPointer { buf in
            _ = XChangeProperty(display, w, backend.atom("XdndTypeList"), XA_ATOM, 32, PropModeReplace, UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), Int32(buf.count))
        }
        XFlush(display)
        return false        // the tracker keeps the pointer; see foreignDragMoved
    }

    private func pixel(_ point: NSPoint) -> (Int, Int) {
        (Int((point.x * backend.scale).rounded()), Int((backend.screenHeightPx - point.y * backend.scale).rounded()))
    }

    /// Whether `window` (or any of its ancestors up to the root) is XdndAware; returns the
    /// aware window and its protocol version.
    private func xdndAware(_ window: Window) -> (Window, Int)? {
        guard let (type, data) = backend.readProperty(window, backend.atom("XdndAware"), delete: false), type == XA_ATOM, let v = backend.atoms(in: data).first else { return nil }
        return (window, min(5, Int(v)))
    }

    /// The topmost XdndAware window of another application under a root-relative point.
    private func foreignWindow(atX x: Int, y: Int) -> (Window, Int)? {
        var rootReturn: Window = 0, parentReturn: Window = 0
        var children: UnsafeMutablePointer<Window>? = nil
        var count: UInt32 = 0
        guard XQueryTree(display, backend.root, &rootReturn, &parentReturn, &children, &count) != 0, let children else { return nil }
        defer { XFree(children) }
        let ours = Set(backend.windows.map(\.xid) + [backend.selectionWindow])
        // Children are bottom to top: the last mapped one containing the point is on top.
        for i in stride(from: Int(count) - 1, through: 0, by: -1) {
            let child = children[i]
            var attrs = XWindowAttributes()
            guard XGetWindowAttributes(display, child, &attrs) != 0, attrs.map_state == IsViewable else { continue }
            let w = Int(attrs.width) + 2 * Int(attrs.border_width), h = Int(attrs.height) + 2 * Int(attrs.border_width)
            guard x >= Int(attrs.x), y >= Int(attrs.y), x < Int(attrs.x) + w, y < Int(attrs.y) + h else { continue }
            // Our own windows (the drag image under the pointer, pop-ups) hide nothing: look beneath them.
            if ours.contains(child) { continue }
            // Descend to the deepest window under the point, stopping at the first aware one.
            var current = child
            while true {
                if ours.contains(current) { return nil }
                if let aware = xdndAware(current) { return aware }
                var cx: Int32 = 0, cy: Int32 = 0, next: Window = 0
                guard XTranslateCoordinates(display, backend.root, current, Int32(x), Int32(y), &cx, &cy, &next) != 0, next != 0 else { return nil }
                current = next
            }
        }
        return nil
    }

    private func sendPosition(x: Int, y: Int, time: Time, op: NSDragOperation) {
        guard target != 0 else { return }
        if awaitingStatus { pendingPosition = (x, y, time, op); return }
        awaitingStatus = true
        pendingPosition = nil
        sendClientMessage(to: target, type: "XdndPosition", [Int(backend.selectionWindow), 0, (x << 16) | (y & 0xFFFF), Int(time), Int(action(for: op))])
    }

    private func leaveTarget() {
        guard target != 0 else { return }
        sendClientMessage(to: target, type: "XdndLeave", [Int(backend.selectionWindow), 0, 0, 0, 0])
        target = 0
        targetAccepted = false
        targetAction = 0
        awaitingStatus = false
        pendingPosition = nil
    }

    func foreignDragMoved(to screenPoint: NSPoint, operations: NSDragOperation) -> NSDragOperation {
        guard source != nil, !dropped else { return [] }
        lastPoint = screenPoint
        let (x, y) = pixel(screenPoint)
        let found = foreignWindow(atX: x, y: y)
        if found?.0 != target {
            leaveTarget()
            if let (w, version) = found {
                target = w
                targetVersion = version
                let types = LinuxMime.offeredTargets(for: entries).map { Int(backend.atom($0)) }
                let flags = (5 << 24) | (types.count > 3 ? 1 : 0)
                sendClientMessage(to: w, type: "XdndEnter", [Int(backend.selectionWindow), flags, types.count > 0 ? types[0] : 0, types.count > 1 ? types[1] : 0, types.count > 2 ? types[2] : 0])
            }
        }
        sendPosition(x: x, y: y, time: backend.lastEventTime, op: operations)
        return targetAccepted ? operation(for: targetAction).intersection(operations) : []
    }

    func foreignDrop(at screenPoint: NSPoint, operations: NSDragOperation) -> Bool {
        guard source != nil, target != 0 else { return false }
        lastPoint = screenPoint
        guard targetAccepted else { leaveTarget(); return false }
        dropped = true
        sendClientMessage(to: target, type: "XdndDrop", [Int(backend.selectionWindow), 0, Int(backend.lastEventTime), 0, 0])
        // A target that never answers XdndFinished must not keep the source waiting.
        let dropTarget = target
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.dropped, self.target == dropTarget else { return }
            self.finish(operation: self.operation(for: self.targetAction))
        }
        return true
    }

    func foreignDragEnded() {
        guard !dropped else { return }
        leaveTarget()
        if source != nil {
            source = nil
            entries = []
        }
    }

    private func finish(operation: NSDragOperation) {
        let s = source
        source = nil
        dropped = false
        target = 0
        targetAccepted = false
        entries = []
        s?.platformDragEnded(at: lastPoint, operation: operation)
    }

    // MARK: Target

    private struct Inbound {
        var source: Window
        var version: Int
        var targets: [String]
        var info: PlatformDragInfo?
        var window: LinuxWindow?
    }
    private var inbound: Inbound?

    /// Handles an Xdnd client message or selection event for `window`; false when the
    /// event is something else.
    func handle(_ event: inout XEvent, window: LinuxWindow?) -> Bool {
        switch Int32(event.type) {
        case ClientMessage:
            let m = event.xclient
            let type = m.message_type
            if type == backend.atom("XdndEnter") { enter(m); return true }
            if type == backend.atom("XdndPosition") { position(m, window: window); return true }
            if type == backend.atom("XdndLeave") { leave(m); return true }
            if type == backend.atom("XdndDrop") { drop(m, window: window); return true }
            if type == backend.atom("XdndStatus") { status(m); return true }
            if type == backend.atom("XdndFinished") { finished(m); return true }
            return false
        case SelectionRequest:
            guard event.xselectionrequest.selection == xdndSelection else { return false }
            backend.serveSelectionRequest(event.xselectionrequest, entries: entries, timestamp: selectionTime)
            return true
        default:
            return false
        }
    }

    private func status(_ m: XClientMessageEvent) {
        guard Window(m.data.l.0) == target else { return }
        targetAccepted = m.data.l.1 & 1 != 0
        targetAction = targetAccepted ? Atom(m.data.l.4) : 0
        if targetAccepted && targetAction == 0 { targetAction = actionCopy }
        awaitingStatus = false
        if let p = pendingPosition { sendPosition(x: p.x, y: p.y, time: p.time, op: p.op) }
    }

    private func finished(_ m: XClientMessageEvent) {
        guard dropped, Window(m.data.l.0) == target else { return }
        var op: NSDragOperation = operation(for: targetAction)
        if targetVersion >= 5 {
            let accepted = m.data.l.1 & 1 != 0
            op = accepted ? operation(for: Atom(m.data.l.2)) : []
            if accepted && op == [] { op = operation(for: targetAction) }
        }
        finish(operation: op)
    }

    private func enter(_ m: XClientMessageEvent) {
        let source = Window(m.data.l.0)
        let version = Int(m.data.l.1 >> 24)
        var targets: [String] = []
        if m.data.l.1 & 1 != 0, let (_, data) = backend.readProperty(source, backend.atom("XdndTypeList"), delete: false) {
            targets = backend.atoms(in: data).map { backend.atomName($0) }
        } else {
            targets = [m.data.l.2, m.data.l.3, m.data.l.4].filter { $0 != 0 }.map { backend.atomName(Atom($0)) }
        }
        inbound = Inbound(source: source, version: version, targets: targets, info: nil, window: nil)
    }

    /// Builds the drag info for an inbound drag: the types per item (a uri-list is read
    /// at once to learn how many files it carries) and a loader over the selection.
    private func makeInfo(location: NSPoint, operations: NSDragOperation, time: Time) -> PlatformDragInfo? {
        guard let inbound else { return nil }
        var types: [String] = []
        var seen: Set<String> = []
        var best: [String: String] = [:]      // AppKit type -> the target to convert
        for t in inbound.targets {
            guard let type = LinuxMime.type(for: t), !seen.contains(type) else { continue }
            seen.insert(type)
            types.append(type)
            best[type] = t
        }
        var items: [[String]] = [types]
        var urls: [PlatformPasteboardEntry] = []
        if let uriTarget = best[LinuxMime.fileURL], let (_, data) = backend.convertSelection(xdndSelection, target: backend.atom(uriTarget), time: time) {
            urls = LinuxMime.decode(target: uriTarget, data: data)
            let others = types.filter { $0 != LinuxMime.fileURL }
            if urls.isEmpty { items = [others] }
            else { items = urls.enumerated().map { i, u in i == 0 ? others + [u.type] : [u.type] } }
        }
        let selection = xdndSelection
        let backend = self.backend
        return PlatformDragInfo(location: location, sourceOperations: operations, modifierFlags: backend.queryModifierFlags(), items: items, isFromThisApplication: false) { item, type in
            if type == LinuxMime.fileURL || type == LinuxMime.url {
                return urls.indices.contains(item) ? urls[item].data : nil
            }
            guard item == 0, let target = best[type], let (_, data) = backend.convertSelection(selection, target: backend.atom(target), time: time) else { return nil }
            return LinuxMime.decode(target: target, data: data).first { $0.type == type }?.data
        }
    }

    private func position(_ m: XClientMessageEvent, window: LinuxWindow?) {
        guard var current = inbound, Window(m.data.l.0) == current.source, let window else { return }
        let rx = CGFloat(m.data.l.2 >> 16), ry = CGFloat(m.data.l.2 & 0xFFFF)
        let time = Time(m.data.l.3)
        let screen = NSPoint(x: rx / backend.scale, y: (backend.screenHeightPx - ry) / backend.scale)
        let location = NSPoint(x: screen.x - window.frame.minX, y: screen.y - window.frame.minY)
        let ops = current.version >= 2 ? operation(for: Atom(m.data.l.4)) : NSDragOperation.copy
        let entered = current.info == nil || current.window !== window
        if entered, current.window != nil, current.window !== window { current.window?.ownerDragExited() }
        var op: NSDragOperation = []
        if entered {
            guard let info = makeInfo(location: location, operations: ops == [] ? .copy : ops, time: time) else { return }
            current.info = info
            current.window = window
            inbound = current
            op = window.ownerDragEntered(info)
        } else if let info = current.info {
            info.location = location
            info.sourceOperations = ops == [] ? .copy : ops
            info.modifierFlags = backend.queryModifierFlags()
            op = window.ownerDragUpdated(info)
        }
        sendClientMessage(to: current.source, type: "XdndStatus", [Int(window.xid), (op != [] ? 1 : 0) | 2, 0, 0, Int(action(for: op))])
    }

    private func leave(_ m: XClientMessageEvent) {
        guard let current = inbound, Window(m.data.l.0) == current.source else { return }
        current.window?.ownerDragExited()
        inbound = nil
    }

    private func drop(_ m: XClientMessageEvent, window: LinuxWindow?) {
        guard let current = inbound, Window(m.data.l.0) == current.source else { return }
        inbound = nil
        var performed: NSDragOperation = []
        if let info = current.info, let w = current.window {
            info.modifierFlags = backend.queryModifierFlags()
            performed = w.ownerDrop(info)
        }
        sendClientMessage(to: current.source, type: "XdndFinished", [Int(window?.xid ?? current.window?.xid ?? 0), performed != [] ? 1 : 0, Int(action(for: performed)), 0, 0])
    }
}
#endif
