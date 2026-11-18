// The X11 window list for the workspace (ADR-0022): the EWMH properties the window
// manager keeps on the root window (`_NET_CLIENT_LIST`, `_NET_ACTIVE_WINDOW`) and on each
// client (`_NET_WM_PID`, `_NET_WM_STATE`, `WM_CLASS`) tell which processes show windows,
// which is in front and which are minimised; activation, minimising and closing go
// through the EWMH client messages and `XIconifyWindow`; this application's own windows
// get their `_NET_WM_ICON`. The backend selects PropertyNotify on the root window and
// reports changes to the workspace.

#if os(Linux)
import Foundation
import CX11
import CoreGraphics

@MainActor
final class LinuxX11WindowSystem: LinuxWorkspaceWindowSystem {
    private unowned let backend: LinuxBackend
    private var display: OpaquePointer { backend.display }
    private let clientList: Atom, activeWindow: Atom, wmPid: Atom, wmState: Atom, stateHidden: Atom, wmIcon: Atom, cardinal: Atom
    private var lastIcon: [UInt]? = nil

    init(backend: LinuxBackend) {
        self.backend = backend
        let d = backend.display
        clientList = XInternAtom(d, "_NET_CLIENT_LIST", 0)
        activeWindow = XInternAtom(d, "_NET_ACTIVE_WINDOW", 0)
        wmPid = XInternAtom(d, "_NET_WM_PID", 0)
        wmState = XInternAtom(d, "_NET_WM_STATE", 0)
        stateHidden = XInternAtom(d, "_NET_WM_STATE_HIDDEN", 0)
        wmIcon = XInternAtom(d, "_NET_WM_ICON", 0)
        cardinal = XInternAtom(d, "CARDINAL", 0)
        XSelectInput(d, backend.root, PropertyChangeMask)
    }

    /// Whether a root property change concerns the window list.
    func concernsWindowList(_ atom: Atom) -> Bool { atom == clientList || atom == activeWindow }

    /// A 32-bit-format property as integers (Xlib hands them out as C longs).
    private func longs(_ window: Window, _ property: Atom) -> [UInt]? {
        var actualType: Atom = 0, format: Int32 = 0, count: UInt = 0, after: UInt = 0
        var data: UnsafeMutablePointer<UInt8>? = nil
        guard XGetWindowProperty(display, window, property, 0, 4096, 0, Atom(0), &actualType, &format, &count, &after, &data) == Success, let data else { return nil }
        defer { XFree(data) }
        guard format == 32, count > 0 else { return [] }
        return data.withMemoryRebound(to: UInt.self, capacity: Int(count)) { Array(UnsafeBufferPointer(start: $0, count: Int(count))) }
    }

    func windowList() -> [LinuxWindowRecord]? {
        guard let clients = longs(backend.root, clientList) else { return nil }
        let active = longs(backend.root, activeWindow)?.first ?? 0
        var records: [LinuxWindowRecord] = []
        for xid in clients {
            let w = Window(xid)
            guard let pid = longs(w, wmPid)?.first, pid > 0 else { continue }
            let states = longs(w, wmState) ?? []
            var hint = XClassHint()
            var wmClass: String? = nil
            if XGetClassHint(display, w, &hint) != 0 {
                if let c = hint.res_class { wmClass = String(cString: c); XFree(c) }
                if let n = hint.res_name { XFree(n) }
            }
            records.append(LinuxWindowRecord(pid: Int32(truncatingIfNeeded: pid), wmClass: wmClass, title: nil, isActive: xid == active && active != 0,
                                             isHidden: states.contains(UInt(stateHidden)), windowID: xid))
        }
        return records
    }

    private func sendToRoot(_ window: Window, _ type: Atom, _ l0: Int, _ l1: Int = 0) {
        var event = XEvent()
        event.xclient.type = ClientMessage
        event.xclient.window = window
        event.xclient.message_type = type
        event.xclient.format = 32
        event.xclient.data.l.0 = l0
        event.xclient.data.l.1 = l1
        event.xclient.data.l.2 = 0
        XSendEvent(display, backend.root, 0, SubstructureRedirectMask | SubstructureNotifyMask, &event)
        XFlush(display)
    }

    func activate(_ window: LinuxWindowRecord) -> Bool {
        // Source indication 2 (a pager): the window manager honours it without focus-stealing checks.
        sendToRoot(Window(window.windowID), activeWindow, 2, Int(backend.lastEventTime))
        return true
    }
    func minimize(_ window: LinuxWindowRecord) -> Bool { XIconifyWindow(display, Window(window.windowID), backend.screen) != 0 }
    func restore(_ window: LinuxWindowRecord) -> Bool {
        XMapWindow(display, Window(window.windowID))
        sendToRoot(Window(window.windowID), activeWindow, 2, Int(backend.lastEventTime))
        return true
    }
    func requestClose(_ window: LinuxWindowRecord) -> Bool {
        var protocols: UnsafeMutablePointer<Atom>? = nil
        var count: Int32 = 0
        guard XGetWMProtocols(display, Window(window.windowID), &protocols, &count) != 0, let protocols else { return false }
        defer { XFree(protocols) }
        guard (0..<Int(count)).contains(where: { protocols[$0] == backend.wmDeleteWindow }) else { return false }
        var event = XEvent()
        event.xclient.type = ClientMessage
        event.xclient.window = Window(window.windowID)
        event.xclient.message_type = backend.wmProtocols
        event.xclient.format = 32
        event.xclient.data.l.0 = Int(backend.wmDeleteWindow)
        event.xclient.data.l.1 = Int(backend.lastEventTime)
        XSendEvent(display, Window(window.windowID), 0, NoEventMask, &event)
        XFlush(display)
        return true
    }

    /// `_NET_WM_ICON`: width, height, then ARGB pixels as CARDINALs, on every window of ours.
    func setApplicationIcon(_ image: CGImage?) -> Bool {
        var payload: [UInt]? = nil
        if let image {
            let w = image.width, h = image.height
            let data = image.data
            var p: [UInt] = [UInt(w), UInt(h)]
            p.reserveCapacity(w * h + 2)
            data.withUnsafeBytes { bytes in
                let px = bytes.bindMemory(to: UInt32.self)
                // Premultiplied BGRA little-endian words are ARGB as integers already.
                for i in 0..<(w * h) where i < px.count { p.append(UInt(px[i])) }
            }
            payload = p
        }
        lastIcon = payload
        for window in backend.windows where window.xid != 0 { apply(to: window.xid) }
        return true
    }
    /// A new window of ours takes the icon too.
    func apply(to xid: Window) {
        if var icon = lastIcon {
            icon.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: buf.count * MemoryLayout<UInt>.size) { bytes in
                    XChangeProperty(display, xid, wmIcon, cardinal, 32, PropModeReplace, bytes, Int32(buf.count))
                }
            }
        } else {
            XDeleteProperty(display, xid, wmIcon)
        }
        XFlush(display)
    }
}
#endif
