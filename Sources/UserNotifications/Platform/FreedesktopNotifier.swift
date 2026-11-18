// UserNotifications (ADR-0043): Linux notifications through the freedesktop notification
// server (org.freedesktop.Notifications on the session bus: GNOME Shell, KDE Plasma, dunst,
// mako, xfce4-notifyd, …).
//
// The notifier keeps a private session-bus connection that only it uses, on one serial
// queue: method calls block there, and a read source on the connection's socket dispatches
// the server's signals (ActionInvoked, NotificationClosed, KDE's NotificationReplied) on the
// same queue. Nothing here touches AppKit's own bus connections or poll loop.
// The app's badge goes through AppKit's dock tile, which already sends the Unity launcher
// entry signal.

#if os(Linux)
import Foundation
import Glibc
import CDBus

final class FreedesktopNotifier: PlatformNotifier, @unchecked Sendable {
    static let service = "org.freedesktop.Notifications"
    static let path = "/org/freedesktop/Notifications"
    static let interface = "org.freedesktop.Notifications"

    private struct Shown {
        var identifier: String
        var actionKeys: [String: String]
    }

    private let identity: PlatformAppIdentity
    private let queue = DispatchQueue(label: "UserNotifications.freedesktop")
    // Queue-confined.
    private var connection: OpaquePointer?          // DBusConnection*
    private var readSource: DispatchSourceRead?
    private var capabilities: Set<String>?
    private var serverIDs: [String: UInt32] = [:]   // identifier -> server id
    private var shown: [UInt32: Shown] = [:]
    // Any thread.
    private let handlerLock = NSLock()
    private var handler: (@Sendable (PlatformNotificationEvent) -> Void)?

    init(identity: PlatformAppIdentity) {
        self.identity = identity
    }

    /// The desktop entry the server can match for the app's name and icon.
    private var desktopEntry: String { identity.identifier }

    // MARK: PlatformNotifier

    func authorization() -> PlatformAuthorization {
        queue.sync { serverCapabilities() == nil ? .unavailable : .allowed }
    }

    func post(_ notification: PlatformNotification) throws {
        try queue.sync {
            guard let capabilities = serverCapabilities(), let connection else {
                throw NSError(domain: "UserNotifications.Freedesktop", code: 1, userInfo: [NSLocalizedDescriptionKey: "No notification server on the session bus."])
            }
            let replaces = serverIDs[notification.identifier] ?? 0
            let payload = FreedesktopPayload.make(for: notification, appName: identity.displayName, desktopEntry: desktopEntry,
                                                  capabilities: capabilities, replacesID: replaces)
            guard let reply = call(connection, "Notify", { iter in self.appendNotify(&iter, payload) }) else {
                throw NSError(domain: "UserNotifications.Freedesktop", code: 2, userInfo: [NSLocalizedDescriptionKey: "The notification server refused the notification."])
            }
            defer { dbus_message_unref(reply) }
            var iter = DBusMessageIter()
            var id: UInt32 = 0
            if dbus_message_iter_init(reply, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBusType.uint32 {
                dbus_message_iter_get_basic(&iter, &id)
            }
            if replaces != 0, replaces != id { shown[replaces] = nil }
            serverIDs[notification.identifier] = id
            shown[id] = Shown(identifier: notification.identifier, actionKeys: payload.actionKeys)
        }
    }

    func remove(identifiers: [String]) {
        queue.sync {
            for identifier in identifiers {
                guard let id = serverIDs.removeValue(forKey: identifier) else { continue }
                shown[id] = nil
                close(id)
            }
        }
    }

    func removeAll() {
        queue.sync {
            for id in shown.keys { close(id) }
            shown.removeAll()
            serverIDs.removeAll()
        }
    }

    func setBadgeCount(_ count: Int) -> Bool { false }

    func setEventHandler(_ handler: @escaping @Sendable (PlatformNotificationEvent) -> Void) {
        handlerLock.lock()
        self.handler = handler
        handlerLock.unlock()
    }

    // MARK: The connection

    /// Queue-confined: the server's capabilities, connecting first. nil when there is no
    /// session bus or no notification server on it (retried on the next call).
    private func serverCapabilities() -> Set<String>? {
        if let capabilities { return capabilities }
        guard let connection = connect() else { return nil }
        guard let reply = call(connection, "GetCapabilities", { _ in }) else { return nil }
        defer { dbus_message_unref(reply) }
        var iter = DBusMessageIter()
        var result: Set<String> = []
        if dbus_message_iter_init(reply, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBusType.array {
            var element = DBusMessageIter()
            dbus_message_iter_recurse(&iter, &element)
            while dbus_message_iter_get_arg_type(&element) == DBusType.string {
                var p: UnsafePointer<CChar>? = nil
                dbus_message_iter_get_basic(&element, &p)
                if let p { result.insert(String(cString: p)) }
                if dbus_message_iter_next(&element) == 0 { break }
            }
        }
        capabilities = result
        return result
    }

    static func sessionBusAvailable(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["DBUS_SESSION_BUS_ADDRESS"] != nil || FileManager.default.fileExists(atPath: "/run/user/\(getuid())/bus")
    }

    /// Queue-confined.
    private func connect() -> OpaquePointer? {
        if let connection { return connection }
        guard FreedesktopNotifier.sessionBusAvailable() else { return nil }
        dbus_threads_init_default()
        var err = DBusError()
        dbus_error_init(&err)
        guard let c = dbus_bus_get_private(DBUS_BUS_SESSION, &err) else {
            dbus_error_free(&err)
            return nil
        }
        dbus_error_free(&err)
        dbus_connection_set_exit_on_disconnect(c, 0)
        connection = c
        dbus_bus_add_match(c, "type='signal',interface='\(FreedesktopNotifier.interface)'", nil)
        _ = dbus_connection_add_filter(c, FreedesktopNotifier.filter, Unmanaged.passUnretained(self).toOpaque(), nil)
        dbus_connection_flush(c)
        var fd: Int32 = -1
        if dbus_connection_get_unix_fd(c, &fd) != 0, fd >= 0 {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.pump() }
            source.resume()
            readSource = source
        }
        return c
    }

    /// Queue-confined: reads what arrived and dispatches it to the filter.
    private func pump() {
        guard let connection else { return }
        _ = dbus_connection_read_write(connection, 0)
        while dbus_connection_dispatch(connection) == DBUS_DISPATCH_DATA_REMAINS {}
    }

    /// Queue-confined: a blocking call on the notification interface; nil on error.
    private func call(_ connection: OpaquePointer, _ method: String, _ arguments: (inout DBusMessageIter) -> Void) -> OpaquePointer? {
        guard let message = dbus_message_new_method_call(FreedesktopNotifier.service, FreedesktopNotifier.path, FreedesktopNotifier.interface, method) else { return nil }
        defer { dbus_message_unref(message) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(message, &iter)
        arguments(&iter)
        var err = DBusError()
        dbus_error_init(&err)
        let reply = dbus_connection_send_with_reply_and_block(connection, message, 5000, &err)
        if reply == nil, let text = err.message {
            FileHandle.standardError.write(Data("UserNotifications: \(method) failed: \(String(cString: text))\n".utf8))
        }
        dbus_error_free(&err)
        // Signals read while waiting for the reply are queued: dispatch them too.
        queue.async { [weak self] in self?.pump() }
        return reply
    }

    private func close(_ id: UInt32) {
        guard let connection else { return }
        if let reply = call(connection, "CloseNotification", { iter in
            var value = id
            dbus_message_iter_append_basic(&iter, DBusType.uint32, &value)
        }) {
            dbus_message_unref(reply)
        }
    }

    // MARK: Marshalling

    private func appendNotify(_ iter: inout DBusMessageIter, _ payload: FreedesktopPayload) {
        appendString(&iter, payload.appName)
        var replaces = payload.replacesID
        dbus_message_iter_append_basic(&iter, DBusType.uint32, &replaces)
        appendString(&iter, payload.appIcon)
        appendString(&iter, payload.summary)
        appendString(&iter, payload.body)
        var actions = DBusMessageIter()
        dbus_message_iter_open_container(&iter, DBusType.array, "s", &actions)
        for a in payload.actions { appendString(&actions, a) }
        dbus_message_iter_close_container(&iter, &actions)
        var hints = DBusMessageIter()
        dbus_message_iter_open_container(&iter, DBusType.array, "{sv}", &hints)
        for (key, value) in payload.hints {
            var entry = DBusMessageIter()
            dbus_message_iter_open_container(&hints, DBusType.dictEntry, nil, &entry)
            appendString(&entry, key)
            var variant = DBusMessageIter()
            switch value {
            case .string(let s):
                dbus_message_iter_open_container(&entry, DBusType.variant, "s", &variant)
                appendString(&variant, s)
            case .bool(let b):
                dbus_message_iter_open_container(&entry, DBusType.variant, "b", &variant)
                var v: dbus_bool_t = b ? 1 : 0
                dbus_message_iter_append_basic(&variant, DBusType.boolean, &v)
            case .byte(let y):
                dbus_message_iter_open_container(&entry, DBusType.variant, "y", &variant)
                var v = y
                dbus_message_iter_append_basic(&variant, DBusType.byte, &v)
            }
            dbus_message_iter_close_container(&entry, &variant)
            dbus_message_iter_close_container(&hints, &entry)
        }
        dbus_message_iter_close_container(&iter, &hints)
        var timeout = payload.expireTimeout
        dbus_message_iter_append_basic(&iter, DBusType.int32, &timeout)
    }

    private func appendString(_ iter: inout DBusMessageIter, _ s: String) {
        s.withCString { p in
            var ptr: UnsafePointer<CChar>? = p
            dbus_message_iter_append_basic(&iter, DBusType.string, &ptr)
        }
    }

    // MARK: Signals

    private static let filter: DBusHandleMessageFunction = { _, message, context in
        guard let message, let context else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
        let me = Unmanaged<FreedesktopNotifier>.fromOpaque(context).takeUnretainedValue()
        return me.handle(message) ? DBUS_HANDLER_RESULT_HANDLED : DBUS_HANDLER_RESULT_NOT_YET_HANDLED
    }

    /// Queue-confined (the filter runs inside `dbus_connection_dispatch`).
    private func handle(_ message: OpaquePointer) -> Bool {
        guard dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_SIGNAL,
              let interfaceC = dbus_message_get_interface(message), String(cString: interfaceC) == FreedesktopNotifier.interface,
              let memberC = dbus_message_get_member(message) else { return false }
        var iter = DBusMessageIter()
        guard dbus_message_iter_init(message, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBusType.uint32 else { return false }
        var id: UInt32 = 0
        dbus_message_iter_get_basic(&iter, &id)
        guard let entry = shown[id] else { return false }   // another app's notification
        _ = dbus_message_iter_next(&iter)
        handlerLock.lock()
        let handler = self.handler
        handlerLock.unlock()
        switch String(cString: memberC) {
        case "ActionInvoked":
            guard let key = string(&iter) else { return false }
            let action = entry.actionKeys[key] ?? key
            // Most servers close the notification after an action; forget it either way.
            forget(id)
            handler?(.activated(identifier: entry.identifier, actionIdentifier: action, userText: nil))
        case "NotificationReplied":
            let text = string(&iter) ?? ""
            let action = entry.actionKeys[FreedesktopPayload.inlineReplyKey] ?? FreedesktopPayload.inlineReplyKey
            forget(id)
            handler?(.activated(identifier: entry.identifier, actionIdentifier: action, userText: text))
        case "NotificationClosed":
            var reason: UInt32 = 4
            if dbus_message_iter_get_arg_type(&iter) == DBusType.uint32 { dbus_message_iter_get_basic(&iter, &reason) }
            forget(id)
            // 1 expired, 2 dismissed by the user, 3 closed by CloseNotification, 4 undefined.
            let mapped: PlatformDismissReason = reason == 2 ? .user : reason == 1 ? .timedOut : .removed
            handler?(.dismissed(identifier: entry.identifier, reason: mapped))
        default:
            return false
        }
        return true
    }

    private func forget(_ id: UInt32) {
        guard let entry = shown.removeValue(forKey: id) else { return }
        if serverIDs[entry.identifier] == id { serverIDs[entry.identifier] = nil }
    }

    private func string(_ iter: inout DBusMessageIter) -> String? {
        guard dbus_message_iter_get_arg_type(&iter) == DBusType.string else { return nil }
        var p: UnsafePointer<CChar>? = nil
        dbus_message_iter_get_basic(&iter, &p)
        return p.map { String(cString: $0) }
    }
}

/// D-Bus type codes (dbus-protocol.h's macros are casts Swift does not import).
enum DBusType {
    static let byte = Int32(UInt8(ascii: "y"))
    static let boolean = Int32(UInt8(ascii: "b"))
    static let int32 = Int32(UInt8(ascii: "i"))
    static let uint32 = Int32(UInt8(ascii: "u"))
    static let string = Int32(UInt8(ascii: "s"))
    static let array = Int32(UInt8(ascii: "a"))
    static let variant = Int32(UInt8(ascii: "v"))
    static let dictEntry = Int32(UInt8(ascii: "e"))
}
#endif
