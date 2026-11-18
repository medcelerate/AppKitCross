// The workspace's D-Bus side on Linux (ADR-0022): on the session bus the file manager
// (org.freedesktop.FileManager1 ShowItems/ShowFolders), the OpenURI and Trash portals,
// the Settings portal (icon theme, accessibility options, the SettingChanged signal),
// the screen saver's ActiveChanged (screens sleep and wake) and the Unity LauncherEntry
// signal that launchers read the badge count from; on the system bus logind's
// PrepareForSleep (sleep and wake) and the session's Lock/Unlock and Active changes.
// Both connections are private and pumped from the backends' poll loops.

#if os(Linux)
import Foundation
import Glibc
import CDBus

@MainActor
final class LinuxWorkspaceBus {
    private let session: OpaquePointer                  // DBusConnection*
    private let system: OpaquePointer?
    private(set) var fileDescriptors: [Int32] = []
    private var handler: ((PlatformWorkspaceEvent) -> Void)?
    private var sessionPath: String?
    private var accessibilityCache: PlatformAccessibilityDisplayOptions?
    private var trace: Bool { NSView._traceInvalidation }
    static let unixFD = Int32(UInt8(ascii: "h"))
    static let int64 = Int32(UInt8(ascii: "x"))

    static func connect(environment: LinuxWorkspaceEnvironment) -> LinuxWorkspaceBus? {
        guard ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] != nil || FileManager.default.fileExists(atPath: "/run/user/\(getuid())/bus") else { return nil }
        var err = DBusError()
        dbus_error_init(&err)
        guard let s = dbus_bus_get_private(DBUS_BUS_SESSION, &err) else { dbus_error_free(&err); return nil }
        dbus_connection_set_exit_on_disconnect(s, 0)
        var sys: OpaquePointer? = nil
        if FileManager.default.fileExists(atPath: "/run/dbus/system_bus_socket") || ProcessInfo.processInfo.environment["DBUS_SYSTEM_BUS_ADDRESS"] != nil {
            var e2 = DBusError()
            dbus_error_init(&e2)
            sys = dbus_bus_get_private(DBUS_BUS_SYSTEM, &e2)
            dbus_error_free(&e2)
            if let sys { dbus_connection_set_exit_on_disconnect(sys, 0) }
        }
        return LinuxWorkspaceBus(session: s, system: sys)
    }

    private init(session: OpaquePointer, system: OpaquePointer?) {
        self.session = session
        self.system = system
        var fd: Int32 = -1
        if dbus_connection_get_unix_fd(session, &fd) != 0 { fileDescriptors.append(fd) }
        if let system, dbus_connection_get_unix_fd(system, &fd) != 0 { fileDescriptors.append(fd) }
    }

    deinit {
        dbus_connection_close(session); dbus_connection_unref(session)
        if let system { dbus_connection_close(system); dbus_connection_unref(system) }
    }

    func dispatch() {
        while dbus_connection_read_write_dispatch(session, 0) != 0 && dbus_connection_get_dispatch_status(session) == DBUS_DISPATCH_DATA_REMAINS {}
        if let system { while dbus_connection_read_write_dispatch(system, 0) != 0 && dbus_connection_get_dispatch_status(system) == DBUS_DISPATCH_DATA_REMAINS {} }
    }

    private func hasOwner(_ name: String, on connection: OpaquePointer) -> Bool {
        var err = DBusError()
        dbus_error_init(&err)
        let r = dbus_bus_name_has_owner(connection, name, &err) != 0
        dbus_error_free(&err)
        return r
    }

    /// A blocking method call; nil on error (traced).
    private func call(_ connection: OpaquePointer, _ destination: String, _ path: String, _ interface: String, _ method: String, timeout: Int32 = 3000,
                      _ arguments: (inout DBusMessageIter) -> Void) -> OpaquePointer? {
        guard let msg = dbus_message_new_method_call(destination, path, interface, method) else { return nil }
        defer { dbus_message_unref(msg) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(msg, &iter)
        arguments(&iter)
        var err = DBusError()
        dbus_error_init(&err)
        let reply = dbus_connection_send_with_reply_and_block(connection, msg, timeout, &err)
        if reply == nil {
            if trace { NSView._trace("workspace bus: \(interface).\(method) failed: \(err.message.map { String(cString: $0) } ?? "?")") }
            dbus_error_free(&err)
        }
        return reply
    }

    // MARK: The file manager and the portals

    /// `org.freedesktop.FileManager1.ShowItems` (or `ShowFolders`), the convention the GNOME,
    /// KDE and Xfce file managers implement.
    func showItems(_ urls: [URL], selecting: Bool) -> Bool {
        guard hasOwner("org.freedesktop.FileManager1", on: session) || activatable("org.freedesktop.FileManager1") else { return false }
        let reply = call(session, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", selecting ? "ShowItems" : "ShowFolders", timeout: 10_000) { iter in
            DBus.appendArray(&iter, signature: "s") { a in for u in urls { DBus.appendString(&a, u.absoluteString) } }
            DBus.appendString(&iter, "")
        }
        guard let reply else { return false }
        dbus_message_unref(reply)
        return true
    }

    /// Whether the bus can start the service on demand (`ListActivatableNames`).
    private func activatable(_ name: String) -> Bool {
        guard let reply = call(session, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListActivatableNames", { _ in }) else { return false }
        defer { dbus_message_unref(reply) }
        var iter = DBusMessageIter()
        guard dbus_message_iter_init(reply, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.array else { return false }
        var sub = DBusMessageIter()
        dbus_message_iter_recurse(&iter, &sub)
        var r = DBus.Reader(iter: sub, valid: true)
        while let s = r.string() { if s == name { return true } }
        return false
    }

    private var hasPortal: Bool { hasOwner("org.freedesktop.portal.Desktop", on: session) }

    /// The OpenURI portal: `OpenURI` for web and other schemes, `OpenFile` with a file
    /// descriptor for files. The request's response is not awaited.
    func openURI(_ url: URL) -> Bool {
        guard hasPortal else { return false }
        if url.isFileURL {
            let fd = Glibc.open(url.path, O_RDONLY | O_CLOEXEC)
            guard fd >= 0 else { return false }
            defer { Glibc.close(fd) }
            guard let reply = call(session, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.OpenURI", "OpenFile", { iter in
                DBus.appendString(&iter, "")
                var f = fd
                dbus_message_iter_append_basic(&iter, LinuxWorkspaceBus.unixFD, &f)
                DBus.appendArray(&iter, signature: "{sv}") { _ in }
            }) else { return false }
            dbus_message_unref(reply)
            return true
        }
        guard let reply = call(session, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.OpenURI", "OpenURI", { iter in
            DBus.appendString(&iter, "")
            DBus.appendString(&iter, url.absoluteString)
            DBus.appendArray(&iter, signature: "{sv}") { _ in }
        }) else { return false }
        dbus_message_unref(reply)
        return true
    }

    /// The Trash portal (`TrashFile(h) -> u`, 1 on success).
    func trashFile(_ url: URL) -> Bool {
        guard hasPortal else { return false }
        let fd = Glibc.open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { Glibc.close(fd) }
        guard let reply = call(session, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Trash", "TrashFile", { iter in
            var f = fd
            dbus_message_iter_append_basic(&iter, LinuxWorkspaceBus.unixFD, &f)
        }) else { return false }
        defer { dbus_message_unref(reply) }
        var iter = DBusMessageIter()
        guard dbus_message_iter_init(reply, &iter) != 0 else { return false }
        var r = DBus.Reader(iter: iter, valid: true)
        return r.uint32() == 1
    }

    // MARK: Settings

    /// `org.freedesktop.portal.Settings.ReadOne` (or `Read` on older portals): the value
    /// as a string ("true"/"false" for booleans, the number for doubles).
    func readSetting(namespace: String, key: String) -> String? {
        guard hasPortal else { return nil }
        for method in ["ReadOne", "Read"] {
            guard let reply = call(session, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings", method, { iter in
                DBus.appendString(&iter, namespace); DBus.appendString(&iter, key)
            }) else { continue }
            defer { dbus_message_unref(reply) }
            var iter = DBusMessageIter()
            guard dbus_message_iter_init(reply, &iter) != 0 else { continue }
            return LinuxWorkspaceBus.basicValue(&iter)
        }
        return nil
    }

    /// The basic value at the iterator, through any number of variant wrappers.
    static func basicValue(_ iter: inout DBusMessageIter) -> String? {
        var it = iter
        while dbus_message_iter_get_arg_type(&it) == DBus.variant {
            var sub = DBusMessageIter()
            dbus_message_iter_recurse(&it, &sub)
            it = sub
        }
        let type = dbus_message_iter_get_arg_type(&it)
        if type == DBus.string { var p: UnsafePointer<CChar>? = nil; dbus_message_iter_get_basic(&it, &p); return p.map { String(cString: $0) } }
        if type == DBus.boolean { var b: dbus_bool_t = 0; dbus_message_iter_get_basic(&it, &b); return b != 0 ? "true" : "false" }
        if type == DBus.double { var d = 0.0; dbus_message_iter_get_basic(&it, &d); return "\(d)" }
        if type == DBus.int32 { var i: Int32 = 0; dbus_message_iter_get_basic(&it, &i); return "\(i)" }
        if type == DBus.uint32 { var u: UInt32 = 0; dbus_message_iter_get_basic(&it, &u); return "\(u)" }
        return nil
    }

    func iconThemeName() -> String? {
        if let s = readSetting(namespace: "org.gnome.desktop.interface", key: "icon-theme"), !s.isEmpty { return s }
        return nil
    }

    /// GNOME's and KDE's settings through the portal: animations off is reduced motion,
    /// the high-contrast switch (or theme) increased contrast, the screen reader VoiceOver.
    /// Nothing on these desktops reduces transparency or differentiates without colour.
    func accessibilityDisplayOptions() -> PlatformAccessibilityDisplayOptions {
        if let c = accessibilityCache { return c }
        var o = PlatformAccessibilityDisplayOptions()
        if readSetting(namespace: "org.gnome.desktop.interface", key: "enable-animations") == "false" { o.reduceMotion = true }
        if let factor = readSetting(namespace: "org.kde.kdeglobals.KDE", key: "AnimationDurationFactor").flatMap(Double.init), factor == 0 { o.reduceMotion = true }
        if readSetting(namespace: "org.gnome.desktop.a11y.interface", key: "high-contrast") == "true" { o.increaseContrast = true }
        if let theme = readSetting(namespace: "org.gnome.desktop.interface", key: "gtk-theme"), theme.localizedCaseInsensitiveContains("highcontrast") { o.increaseContrast = true }
        if readSetting(namespace: "org.gnome.desktop.a11y.applications", key: "screen-reader-enabled") == "true" { o.voiceOverEnabled = true }
        accessibilityCache = o
        return o
    }

    // MARK: Signals

    func startSignals(_ handler: @escaping (PlatformWorkspaceEvent) -> Void) {
        self.handler = handler
        let context = Unmanaged.passUnretained(self).toOpaque()
        for rule in ["type='signal',interface='org.freedesktop.portal.Settings',member='SettingChanged'",
                     "type='signal',interface='org.freedesktop.ScreenSaver',member='ActiveChanged'",
                     "type='signal',interface='org.gnome.ScreenSaver',member='ActiveChanged'"] {
            dbus_bus_add_match(session, rule, nil)
        }
        _ = dbus_connection_add_filter(session, LinuxWorkspaceBus.filter, context, nil)
        guard let system else { return }
        dbus_bus_add_match(system, "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'", nil)
        // This process's session: its Lock/Unlock and Active property.
        if let reply = call(system, "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager", "GetSessionByPID", { iter in DBus.appendUInt32(&iter, UInt32(getpid())) }) {
            var iter = DBusMessageIter()
            if dbus_message_iter_init(reply, &iter) != 0 { var r = DBus.Reader(iter: iter, valid: true); sessionPath = r.string() }
            dbus_message_unref(reply)
        }
        if let path = sessionPath {
            dbus_bus_add_match(system, "type='signal',interface='org.freedesktop.login1.Session',path='\(path)'", nil)
            dbus_bus_add_match(system, "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='\(path)'", nil)
        }
        _ = dbus_connection_add_filter(system, LinuxWorkspaceBus.filter, context, nil)
        dbus_connection_flush(session)
    }

    private static let filter: DBusHandleMessageFunction = { _, message, context in
        MainActor.assumeIsolated {
            guard let message, let context else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
            let bus = Unmanaged<LinuxWorkspaceBus>.fromOpaque(context).takeUnretainedValue()
            return bus.handle(message) ? DBUS_HANDLER_RESULT_HANDLED : DBUS_HANDLER_RESULT_NOT_YET_HANDLED
        }
    }

    private func handle(_ message: OpaquePointer) -> Bool {
        guard dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_SIGNAL, let ifaceC = dbus_message_get_interface(message), let memberC = dbus_message_get_member(message) else { return false }
        let interface = String(cString: ifaceC), member = String(cString: memberC)
        var iter = DBusMessageIter()
        let hasArgs = dbus_message_iter_init(message, &iter) != 0
        func firstBool() -> Bool? {
            guard hasArgs, dbus_message_iter_get_arg_type(&iter) == DBus.boolean else { return nil }
            var b: dbus_bool_t = 0
            dbus_message_iter_get_basic(&iter, &b)
            return b != 0
        }
        switch (interface, member) {
        case ("org.freedesktop.portal.Settings", "SettingChanged"):
            accessibilityCache = nil
            handler?(.accessibilityDisplayOptionsDidChange)
        case ("org.freedesktop.ScreenSaver", "ActiveChanged"), ("org.gnome.ScreenSaver", "ActiveChanged"):
            if let on = firstBool() { handler?(on ? .screensDidSleep : .screensDidWake) }
        case ("org.freedesktop.login1.Manager", "PrepareForSleep"):
            if let going = firstBool() { handler?(going ? .willSleep : .didWake) }
        case ("org.freedesktop.login1.Session", "Lock"):
            handler?(.sessionDidResignActive)
        case ("org.freedesktop.login1.Session", "Unlock"):
            handler?(.sessionDidBecomeActive)
        case ("org.freedesktop.DBus.Properties", "PropertiesChanged"):
            // (s interface, a{sv} changed, as invalidated): the session's Active flag.
            var r = DBus.Reader(iter: iter, valid: hasArgs)
            guard r.string() == "org.freedesktop.login1.Session", dbus_message_iter_get_arg_type(&r.iter) == DBus.array else { return false }
            var dict = DBusMessageIter()
            dbus_message_iter_recurse(&r.iter, &dict)
            while dbus_message_iter_get_arg_type(&dict) == DBus.dictEntry {
                var entry = DBusMessageIter()
                dbus_message_iter_recurse(&dict, &entry)
                var er = DBus.Reader(iter: entry, valid: true)
                if er.string() == "Active", case .boolean(let active)? = er.variant() { handler?(active ? .sessionDidBecomeActive : .sessionDidResignActive) }
                if dbus_message_iter_next(&dict) == 0 { break }
            }
        default:
            return false
        }
        return true
    }

    // MARK: The launcher badge

    /// `com.canonical.Unity.LauncherEntry.Update`: launchers (Dash to Dock, KDE's task
    /// manager, Cairo-Dock) show `count` on the application's icon; the label must be a
    /// number for that, other labels only mark the icon urgent.
    func updateLauncherEntry(desktopID: String, badgeLabel: String?) {
        let id = desktopID.hasSuffix(".desktop") ? desktopID : desktopID + ".desktop"
        var hash: UInt32 = 5381
        for b in id.utf8 { hash = hash &* 33 &+ UInt32(b) }
        guard let signal = dbus_message_new_signal("/com/canonical/unity/launcherentry/\(hash)", "com.canonical.Unity.LauncherEntry", "Update") else { return }
        defer { dbus_message_unref(signal) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(signal, &iter)
        DBus.appendString(&iter, "application://" + id)
        let count = badgeLabel.flatMap { Int64($0.filter { $0.isNumber }) }
        DBus.appendArray(&iter, signature: "{sv}") { dict in
            var entry = DBusMessageIter()
            dbus_message_iter_open_container(&dict, DBus.dictEntry, nil, &entry)
            DBus.appendString(&entry, "count")
            var v = DBusMessageIter()
            dbus_message_iter_open_container(&entry, DBus.variant, "x", &v)
            var c = count ?? 0
            dbus_message_iter_append_basic(&v, LinuxWorkspaceBus.int64, &c)
            dbus_message_iter_close_container(&entry, &v)
            dbus_message_iter_close_container(&dict, &entry)
            DBus.appendDictEntry(&dict, "count-visible", .boolean(count != nil))
            DBus.appendDictEntry(&dict, "urgent", .boolean(badgeLabel != nil && count == nil))
        }
        var serial: UInt32 = 0
        dbus_connection_send(session, signal, &serial)
        dbus_connection_flush(session)
        if trace { NSView._trace("workspace: launcher entry \(id) count=\(count.map(String.init) ?? "none")") }
    }
}
#endif
