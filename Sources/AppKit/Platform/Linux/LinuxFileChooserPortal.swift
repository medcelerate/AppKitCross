// The xdg-desktop-portal FileChooser over D-Bus (ADR-0017): the desktop's own open and
// save dialogs (GTK, KDE, ...) shown by the portal service, which the application talks
// to on the session bus. The X11 and Wayland backends offer it as their
// `PlatformFileDialog` when `org.freedesktop.portal.Desktop` is on the bus; without a
// portal the panels draw themselves (NSSavePanel's package panel).
//
// Protocol: `org.freedesktop.portal.FileChooser.OpenFile` / `SaveFile` on
// `/org/freedesktop/portal/desktop` take a parent window identifier, a title and an
// `a{sv}` of options and answer with the object path of a Request; the choice arrives as
// that Request's `Response(u, a{sv})` signal with the chosen `uris`. The path is known in
// advance from the connection's unique name and the `handle_token` option, so the match
// rule is added before the call.

import Foundation
import CDBus

@MainActor
final class LinuxFileChooserPortal: PlatformFileDialog {
    static let service = "org.freedesktop.portal.Desktop"
    static let path = "/org/freedesktop/portal/desktop"
    static let interface = "org.freedesktop.portal.FileChooser"

    /// Keeps the backend's windows painting and responsive while the portal dialog is up.
    private let pump: @MainActor () -> Void
    /// The parent identifier ("x11:<hex xid>"; Wayland needs xdg-foreign and passes "").
    private let parentIdentifier: @MainActor (PlatformWindow?) -> String
    private var connection: OpaquePointer?
    private var tokenCounter = 0

    init(pump: @escaping @MainActor () -> Void, parentIdentifier: @escaping @MainActor (PlatformWindow?) -> String) {
        self.pump = pump
        self.parentIdentifier = parentIdentifier
    }

    /// Opens a private session-bus connection and checks that a portal service is running.
    /// Nil when there is no session bus or no portal (the panel then draws itself).
    static func connect(pump: @escaping @MainActor () -> Void, parentIdentifier: @escaping @MainActor (PlatformWindow?) -> String) -> LinuxFileChooserPortal? {
        guard ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] != nil || FileManager.default.fileExists(atPath: "/run/user/\(getuid())/bus") else { return nil }
        var err = DBusError()
        dbus_error_init(&err)
        guard let conn = dbus_bus_get_private(DBUS_BUS_SESSION, &err) else {
            dbus_error_free(&err)
            return nil
        }
        dbus_connection_set_exit_on_disconnect(conn, 0)
        let hasPortal = dbus_bus_name_has_owner(conn, service, &err) != 0
        dbus_error_free(&err)
        guard hasPortal else {
            dbus_connection_close(conn)
            dbus_connection_unref(conn)
            return nil
        }
        let portal = LinuxFileChooserPortal(pump: pump, parentIdentifier: parentIdentifier)
        portal.connection = conn
        if NSView._traceInvalidation { NSView._trace("file chooser portal on the session bus") }
        return portal
    }

    deinit {
        if let c = connection {
            dbus_connection_close(c)
            dbus_connection_unref(c)
        }
    }

    func run(_ options: PlatformFileDialogOptions, parent: PlatformWindow?) -> [URL]? {
        guard let conn = connection else { return nil }
        tokenCounter += 1
        let token = "appkitcross_\(getpid())_\(tokenCounter)"
        guard let unique = dbus_bus_get_unique_name(conn).map({ String(cString: $0) }) else { return nil }
        let sender = unique.dropFirst().replacingOccurrences(of: ".", with: "_")   // ":1.42" -> "1_42"
        let requestPath = "/org/freedesktop/portal/desktop/request/\(sender)/\(token)"
        let rule = "type='signal',interface='org.freedesktop.portal.Request',member='Response',path='\(requestPath)'"
        var err = DBusError()
        dbus_error_init(&err)
        dbus_bus_add_match(conn, rule, &err)
        if dbus_error_is_set(&err) != 0 { dbus_error_free(&err); return nil }
        defer { dbus_bus_remove_match(conn, rule, nil) }

        let method = options.isSave ? "SaveFile" : "OpenFile"
        guard let msg = dbus_message_new_method_call(Self.service, Self.path, Self.interface, method) else { return nil }
        defer { dbus_message_unref(msg) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(msg, &iter)
        DBus.appendString(&iter, parentIdentifier(parent))
        DBus.appendString(&iter, options.title ?? (options.isSave ? "Save" : "Open"))
        appendOptions(&iter, options, token: token)

        // The call itself answers at once with the request path (or an error).
        guard let reply = dbus_connection_send_with_reply_and_block(conn, msg, 5000, &err) else {
            if NSView._traceInvalidation { NSView._trace("file chooser portal \(method) failed: \(err.message.map { String(cString: $0) } ?? "?")") }
            dbus_error_free(&err)
            return nil
        }
        var replyIter = DBusMessageIter()
        var actualPath = requestPath
        if dbus_message_iter_init(reply, &replyIter) != 0, dbus_message_iter_get_arg_type(&replyIter) == DBus.objectPath {
            var p: UnsafePointer<CChar>? = nil
            dbus_message_iter_get_basic(&replyIter, &p)
            if let p { actualPath = String(cString: p) }
        }
        dbus_message_unref(reply)
        if actualPath != requestPath {
            // An older portal that does not honour handle_token: match its path instead.
            dbus_bus_remove_match(conn, rule, nil)
            dbus_bus_add_match(conn, "type='signal',interface='org.freedesktop.portal.Request',member='Response',path='\(actualPath)'", nil)
        }

        // Wait for the Response signal, keeping our own windows alive meanwhile.
        while true {
            dbus_connection_read_write(conn, 20)
            while let m = dbus_connection_pop_message(conn) {
                defer { dbus_message_unref(m) }
                guard dbus_message_is_signal(m, "org.freedesktop.portal.Request", "Response") != 0,
                      let pathC = dbus_message_get_path(m), String(cString: pathC) == actualPath else { continue }
                return parseResponse(m)
            }
            pump()
        }
    }

    // MARK: Options

    private func appendOptions(_ iter: inout DBusMessageIter, _ o: PlatformFileDialogOptions, token: String) {
        var dict = DBusMessageIter()
        dbus_message_iter_open_container(&iter, DBus.array, "{sv}", &dict)
        appendEntry(&dict, "handle_token", signature: "s") { DBus.appendString(&$0, token) }
        appendEntry(&dict, "modal", signature: "b") { DBus.appendBool(&$0, true) }
        if let prompt = o.prompt, !prompt.isEmpty { appendEntry(&dict, "accept_label", signature: "s") { DBus.appendString(&$0, prompt) } }
        if !o.isSave {
            appendEntry(&dict, "multiple", signature: "b") { DBus.appendBool(&$0, o.allowsMultipleSelection) }
            appendEntry(&dict, "directory", signature: "b") { DBus.appendBool(&$0, o.canChooseDirectories && !o.canChooseFiles) }
        } else if let name = o.defaultName, !name.isEmpty {
            appendEntry(&dict, "current_name", signature: "s") { DBus.appendString(&$0, name) }
        }
        if let dir = o.directory {
            appendEntry(&dict, "current_folder", signature: "ay") { Self.appendByteString(&$0, dir.path) }
        }
        if !o.allowedExtensions.isEmpty {
            appendEntry(&dict, "filters", signature: "a(sa(us))") { v in
                var filters = DBusMessageIter()
                dbus_message_iter_open_container(&v, DBus.array, "(sa(us))", &filters)
                let label: String
                if o.allowedTypeDescriptions.count == o.allowedExtensions.count, !o.allowedTypeDescriptions.isEmpty {
                    label = Array(Set(o.allowedTypeDescriptions)).sorted().joined(separator: ", ")
                } else {
                    label = "Supported files (" + o.allowedExtensions.map { "*.\($0)" }.joined(separator: ", ") + ")"
                }
                Self.appendFilter(&filters, name: label, patterns: o.allowedExtensions.map { "*.\($0)" })
                if o.allowsOtherTypes { Self.appendFilter(&filters, name: "All files", patterns: ["*"]) }
                dbus_message_iter_close_container(&v, &filters)
            }
        }
        dbus_message_iter_close_container(&iter, &dict)
    }

    private func appendEntry(_ dict: inout DBusMessageIter, _ key: String, signature: String, _ value: (inout DBusMessageIter) -> Void) {
        var entry = DBusMessageIter()
        dbus_message_iter_open_container(&dict, DBus.dictEntry, nil, &entry)
        DBus.appendString(&entry, key)
        var variant = DBusMessageIter()
        dbus_message_iter_open_container(&entry, DBus.variant, signature, &variant)
        value(&variant)
        dbus_message_iter_close_container(&entry, &variant)
        dbus_message_iter_close_container(&dict, &entry)
    }

    /// A NUL-terminated byte string (`ay`), how the portal passes file system paths.
    private static func appendByteString(_ iter: inout DBusMessageIter, _ s: String) {
        var array = DBusMessageIter()
        dbus_message_iter_open_container(&iter, DBus.array, "y", &array)
        let bytes = Array(s.utf8) + [0]
        bytes.withUnsafeBufferPointer { buf in
            var p: UnsafePointer<UInt8>? = buf.baseAddress
            dbus_message_iter_append_fixed_array(&array, Int32(UInt8(ascii: "y")), &p, Int32(buf.count))
        }
        dbus_message_iter_close_container(&iter, &array)
    }

    /// One `(sa(us))` filter: a name and glob patterns (type 0).
    private static func appendFilter(_ filters: inout DBusMessageIter, name: String, patterns: [String]) {
        DBus.appendStruct(&filters) { f in
            DBus.appendString(&f, name)
            var pats = DBusMessageIter()
            dbus_message_iter_open_container(&f, DBus.array, "(us)", &pats)
            for p in patterns {
                DBus.appendStruct(&pats) { s in
                    DBus.appendUInt32(&s, 0)
                    DBus.appendString(&s, p)
                }
            }
            dbus_message_iter_close_container(&f, &pats)
        }
    }

    // MARK: Response

    /// `Response(u response, a{sv} results)`: 0 is success with `uris` (as); 1 the user
    /// cancelled; 2 something else ended the interaction.
    private func parseResponse(_ m: OpaquePointer) -> [URL]? {
        var iter = DBusMessageIter()
        guard dbus_message_iter_init(m, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.uint32 else { return nil }
        var code: UInt32 = 0
        dbus_message_iter_get_basic(&iter, &code)
        guard code == 0, dbus_message_iter_next(&iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.array else { return nil }
        var dict = DBusMessageIter()
        dbus_message_iter_recurse(&iter, &dict)
        var urls: [URL] = []
        while dbus_message_iter_get_arg_type(&dict) == DBus.dictEntry {
            var entry = DBusMessageIter()
            dbus_message_iter_recurse(&dict, &entry)
            var keyC: UnsafePointer<CChar>? = nil
            dbus_message_iter_get_basic(&entry, &keyC)
            if let keyC, String(cString: keyC) == "uris", dbus_message_iter_next(&entry) != 0 {
                var variant = DBusMessageIter()
                dbus_message_iter_recurse(&entry, &variant)
                if dbus_message_iter_get_arg_type(&variant) == DBus.array {
                    var strings = DBusMessageIter()
                    dbus_message_iter_recurse(&variant, &strings)
                    while dbus_message_iter_get_arg_type(&strings) == DBus.string {
                        var s: UnsafePointer<CChar>? = nil
                        dbus_message_iter_get_basic(&strings, &s)
                        if let s, let url = URL(string: String(cString: s)) { urls.append(url.isFileURL ? URL(fileURLWithPath: url.path) : url) }
                        if dbus_message_iter_next(&strings) == 0 { break }
                    }
                }
            }
            if dbus_message_iter_next(&dict) == 0 { break }
        }
        return urls.isEmpty ? nil : urls
    }
}
