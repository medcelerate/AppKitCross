// X11 selections: the system clipboard (CLIPBOARD) and the transfer half of XDND share
// the same machinery, so both live here. A hidden selection window owns what the
// application offers and answers SelectionRequest with the entries converted to the
// requested target; reading converts a foreign selection into a property on the same
// window and waits for SelectionNotify (INCR transfers included).
//
// `LinuxMime` maps AppKit pasteboard types to the MIME types and X targets other
// applications understand; the Wayland backend uses the same table.

#if os(Linux)
import Foundation
import Glibc
import CX11

/// AppKit pasteboard types <-> MIME types (Wayland) and X selection targets.
enum LinuxMime {
    static let utf8Text = "public.utf8-plain-text"
    static let fileURL = "public.file-url"
    static let url = "public.url"
    static let uriList = "text/uri-list"
    private static let custom = "application/x-appkitwin."

    /// What other applications accept for a type, best first.
    static func targets(for type: String) -> [String] {
        switch type {
        case utf8Text, "public.plain-text", "public.text": return ["text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT"]
        case "public.html": return ["text/html"]
        case "public.rtf": return ["text/rtf", "application/rtf"]
        case "public.png": return ["image/png"]
        case "public.jpeg": return ["image/jpeg"]
        case "public.tiff": return ["image/tiff"]
        case "public.json": return ["application/json"]
        case fileURL, url: return [uriList]
        default: return [custom + type]
        }
    }

    /// The AppKit type a target maps to (text/uri-list resolves per URL in `decode`).
    static func type(for target: String) -> String? {
        switch target.lowercased() {
        case "text/plain;charset=utf-8", "utf8_string", "text/plain", "string", "text", "text/plain;charset=utf8": return utf8Text
        case "text/html": return "public.html"
        case "text/rtf", "application/rtf": return "public.rtf"
        case "image/png": return "public.png"
        case "image/jpeg": return "public.jpeg"
        case "image/tiff": return "public.tiff"
        case "application/json": return "public.json"
        case uriList: return fileURL
        default:
            if target.hasPrefix(custom) { return String(target.dropFirst(custom.count)) }
            return nil
        }
    }

    /// Every target the entries can be served as, in offer order (duplicates removed).
    static func offeredTargets(for entries: [PlatformPasteboardEntry]) -> [String] {
        var result: [String] = []
        for e in entries { for t in targets(for: e.type) where !result.contains(t) { result.append(t) } }
        return result
    }

    /// The bytes to send for `target` from `entries`, nil when none matches.
    static func encode(target: String, entries: [PlatformPasteboardEntry]) -> Data? {
        if target == uriList {
            let urls = entries.filter { $0.type == fileURL || $0.type == url }.map { String(decoding: $0.data, as: UTF8.self) }
            guard !urls.isEmpty else { return nil }
            return Data((urls.joined(separator: "\r\n") + "\r\n").utf8)
        }
        for e in entries where targets(for: e.type).contains(target) { return e.data }
        return nil
    }

    /// The entries `data` received as `target` stands for (a uri-list yields one per URL).
    static func decode(target: String, data: Data) -> [PlatformPasteboardEntry] {
        if target == uriList {
            let text = String(decoding: data, as: UTF8.self)
            return text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .map { PlatformPasteboardEntry(type: $0.hasPrefix("file:") ? fileURL : url, data: Data($0.utf8)) }
        }
        guard let t = type(for: target) else { return [] }
        return [PlatformPasteboardEntry(type: t, data: data)]
    }
}

// MARK: Selection window and conversions

@MainActor
extension LinuxBackend {
    func atom(_ name: String) -> Atom {
        if let a = atoms[name] { return a }
        let a = XInternAtom(display, name, 0)
        atoms[name] = a
        return a
    }

    func atomName(_ atom: Atom) -> String {
        guard atom != 0, let p = XGetAtomName(display, atom) else { return "" }
        defer { XFree(p) }
        return String(cString: p)
    }

    /// The hidden window that owns selections and receives their replies.
    func ensureSelectionWindow() -> Window {
        if selectionWindow != 0 { return selectionWindow }
        selectionWindow = XCreateSimpleWindow(display, root, -10, -10, 1, 1, 0, 0, 0)
        XSelectInput(display, selectionWindow, PropertyChangeMask)
        return selectionWindow
    }

    /// Converts `selection` to `target` and returns the bytes, or nil when the owner
    /// declines or does not answer within `timeout`. Runs a small loop over the X
    /// connection; other events stay queued for the pump.
    func convertSelection(_ selection: Atom, target: Atom, time: Time = Time(CurrentTime), timeout: TimeInterval = 2) -> (type: Atom, data: Data)? {
        let requestor = ensureSelectionWindow()
        let property = atom("_APPKITWIN_SELECTION")
        XDeleteProperty(display, requestor, property)
        XConvertSelection(display, selection, target, property, requestor, time)
        XFlush(display)
        let deadline = Date(timeIntervalSinceNow: timeout)
        var event = XEvent()
        while true {
            if XCheckTypedWindowEvent(display, requestor, SelectionNotify, &event) != 0 {
                if event.xselection.selection == selection { break }
            }
            guard waitForX(until: deadline) else { return nil }
        }
        guard event.xselection.property != 0 else { return nil }
        guard var (type, data) = readProperty(requestor, event.xselection.property, delete: true) else { return nil }
        if type == atom("INCR") {
            // The owner sends the data in chunks through PropertyNotify until an empty one.
            data = Data()
            type = 0
            while true {
                var p = XEvent()
                while XCheckTypedWindowEvent(display, requestor, PropertyNotify, &p) == 0 || p.xproperty.atom != event.xselection.property || p.xproperty.state != PropertyNewValue {
                    guard waitForX(until: deadline) else { return nil }
                }
                guard let (chunkType, chunk) = readProperty(requestor, event.xselection.property, delete: true) else { return nil }
                if chunk.isEmpty { break }
                type = chunkType
                data.append(chunk)
            }
        }
        return (type, data)
    }

    /// Blocks until the X connection has data or `deadline` passes; false on timeout.
    private func waitForX(until deadline: Date) -> Bool {
        if XPending(display) > 0 { return true }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return false }
        var fds = [pollfd(fd: XConnectionNumber(display), events: Int16(POLLIN), revents: 0)]
        return poll(&fds, 1, Int32(remaining * 1000)) > 0
    }

    /// Reads a whole property (any type, any format) as bytes.
    func readProperty(_ window: Window, _ property: Atom, delete: Bool) -> (type: Atom, data: Data)? {
        var type: Atom = 0
        var format: Int32 = 0
        var count: UInt = 0, remaining: UInt = 0
        var bytes: UnsafeMutablePointer<UInt8>? = nil
        guard XGetWindowProperty(display, window, property, 0, 0x7FFF_FFFF, delete ? 1 : 0, Atom(AnyPropertyType), &type, &format, &count, &remaining, &bytes) == Success else { return nil }
        defer { if let bytes { XFree(bytes) } }
        guard let bytes else { return (type, Data()) }
        // Format 32 arrives as C longs; keep atoms/ints as 32-bit values.
        if format == 32 {
            var out = Data(capacity: Int(count) * 4)
            bytes.withMemoryRebound(to: Int.self, capacity: Int(count)) { longs in
                for i in 0..<Int(count) { var v = UInt32(truncatingIfNeeded: longs[i]); withUnsafeBytes(of: &v) { out.append(contentsOf: $0) } }
            }
            return (type, out)
        }
        return (type, Data(bytes: bytes, count: Int(count) * (format == 16 ? 2 : 1)))
    }

    /// The atoms in a format-32 ATOM property, as read by `readProperty`.
    func atoms(in data: Data) -> [Atom] {
        var result: [Atom] = []
        data.withUnsafeBytes { buf in
            for i in stride(from: 0, to: buf.count - 3, by: 4) { result.append(Atom(buf.loadUnaligned(fromByteOffset: i, as: UInt32.self))) }
        }
        return result
    }

    /// Answers a SelectionRequest for a selection this application owns from `entries`.
    func serveSelectionRequest(_ request: XSelectionRequestEvent, entries: [PlatformPasteboardEntry], timestamp: Time) {
        var reply = XEvent()
        reply.xselection.type = SelectionNotify
        reply.xselection.display = request.display
        reply.xselection.requestor = request.requestor
        reply.xselection.selection = request.selection
        reply.xselection.target = request.target
        reply.xselection.time = request.time
        reply.xselection.property = 0
        let property = request.property != 0 ? request.property : request.target
        let targetName = atomName(request.target)
        if request.target == atom("TARGETS") {
            var list = [atom("TARGETS"), atom("TIMESTAMP")] + LinuxMime.offeredTargets(for: entries).map { atom($0) }
            list.withUnsafeMutableBufferPointer { buf in
                _ = XChangeProperty(display, request.requestor, property, XA_ATOM, 32, PropModeReplace, UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), Int32(buf.count))
            }
            reply.xselection.property = property
        } else if request.target == atom("TIMESTAMP") {
            var t = Int(timestamp)
            withUnsafeBytes(of: &t) { p in
                _ = XChangeProperty(display, request.requestor, property, Atom(XA_INTEGER), 32, PropModeReplace, p.baseAddress!.assumingMemoryBound(to: UInt8.self), 1)
            }
            reply.xselection.property = property
        } else if let data = LinuxMime.encode(target: targetName, entries: entries) {
            data.withUnsafeBytes { p in
                _ = XChangeProperty(display, request.requestor, property, request.target, 8, PropModeReplace, p.baseAddress?.assumingMemoryBound(to: UInt8.self), Int32(data.count))
            }
            reply.xselection.property = property
        }
        _ = XSendEvent(display, request.requestor, 0, 0, &reply)
        XFlush(display)
    }
}

// MARK: Clipboard

/// The system clipboard over the X11 CLIPBOARD selection.
@MainActor
final class X11Pasteboard: PlatformPasteboard {
    private unowned let backend: LinuxBackend
    private var entries: [PlatformPasteboardEntry] = []
    private var owned = false
    private var ownedSince: Time = 0
    private var count = 0
    private var lastOwner: Window = 0
    private var lastOwnerTimestamp: Int = -1
    private var lastCheck = Date.distantPast
    private var cached: [PlatformPasteboardEntry]? = nil

    init(backend: LinuxBackend) { self.backend = backend }

    private var clipboard: Atom { backend.atom("CLIPBOARD") }

    func write(_ entries: [PlatformPasteboardEntry]) {
        self.entries = entries
        let w = backend.ensureSelectionWindow()
        ownedSince = backend.lastEventTime
        XSetSelectionOwner(backend.display, clipboard, w, ownedSince)
        XFlush(backend.display)
        owned = XGetSelectionOwner(backend.display, clipboard) == w
        count += 1
        cached = nil
    }

    func read() -> [PlatformPasteboardEntry] {
        if owned { return entries }
        _ = changeCount
        if let cached { return cached }
        let owner = XGetSelectionOwner(backend.display, clipboard)
        guard owner != 0 else { cached = []; return [] }
        var result: [PlatformPasteboardEntry] = []
        if let (_, data) = backend.convertSelection(clipboard, target: backend.atom("TARGETS")) {
            let targets = backend.atoms(in: data).map { backend.atomName($0) }
            var seenTypes: Set<String> = []
            // Take the best target for each type the owner offers.
            for t in targets {
                guard let type = LinuxMime.type(for: t), !seenTypes.contains(type) else { continue }
                guard let (_, bytes) = backend.convertSelection(clipboard, target: backend.atom(t)) else { continue }
                let decoded = LinuxMime.decode(target: t, data: bytes)
                guard !decoded.isEmpty else { continue }
                seenTypes.insert(type)
                result += decoded
            }
        }
        cached = result
        return result
    }

    /// Changes when another application takes the selection or re-sets it (its TIMESTAMP
    /// target), checked at most a few times a second.
    var changeCount: Int {
        if owned { return count }
        if Date().timeIntervalSince(lastCheck) > 0.25 {
            lastCheck = Date()
            let owner = XGetSelectionOwner(backend.display, clipboard)
            var timestamp = -1
            if owner != 0, let (_, data) = backend.convertSelection(clipboard, target: backend.atom("TIMESTAMP"), timeout: 0.3), data.count >= 4 {
                timestamp = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
            }
            if owner != lastOwner || timestamp != lastOwnerTimestamp {
                lastOwner = owner
                lastOwnerTimestamp = timestamp
                count += 1
                cached = nil
            }
        }
        return count
    }

    /// Another application took the clipboard.
    func selectionCleared() {
        owned = false
        entries = []
        count += 1
        cached = nil
    }

    func handleRequest(_ request: XSelectionRequestEvent) {
        backend.serveSelectionRequest(request, entries: entries, timestamp: ownedSince)
    }
}
#endif
