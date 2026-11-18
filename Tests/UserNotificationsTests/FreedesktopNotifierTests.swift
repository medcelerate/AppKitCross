// UserNotifications (ADR-0043): the Linux notifier against a fake notification server on
// the session bus. The test claims org.freedesktop.Notifications itself, answers
// GetCapabilities, Notify and CloseNotification, and emits the server's signals. It skips
// when there is no session bus (run it under `dbus-run-session`) or when a real server
// already owns the name.

#if os(Linux)
import XCTest
import Foundation
import Glibc
import CDBus
@testable import UserNotifications

final class FakeNotificationServer: @unchecked Sendable {
    struct Notify {
        var id: UInt32
        var appName: String
        var replacesID: UInt32
        var summary: String
        var body: String
        var actions: [String]
        var hintKeys: [String]
    }

    let connection: OpaquePointer
    private let lock = NSLock()
    private var _notifies: [Notify] = []
    private var _closed: [UInt32] = []
    private var nextID: UInt32 = 40
    private var running = true
    private var thread: Thread?

    var notifies: [Notify] { lock.lock(); defer { lock.unlock() }; return _notifies }
    var closed: [UInt32] { lock.lock(); defer { lock.unlock() }; return _closed }

    /// nil when the bus is missing or the name is taken.
    static func start() -> FakeNotificationServer? {
        guard FreedesktopNotifier.sessionBusAvailable() else { return nil }
        dbus_threads_init_default()
        var err = DBusError()
        dbus_error_init(&err)
        guard let c = dbus_bus_get_private(DBUS_BUS_SESSION, &err) else { dbus_error_free(&err); return nil }
        dbus_connection_set_exit_on_disconnect(c, 0)
        let r = dbus_bus_request_name(c, FreedesktopNotifier.service, UInt32(DBUS_NAME_FLAG_DO_NOT_QUEUE), &err)
        dbus_error_free(&err)
        guard r == DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER else {
            dbus_connection_close(c)
            dbus_connection_unref(c)
            return nil
        }
        let server = FakeNotificationServer(connection: c)
        _ = dbus_connection_add_filter(c, FakeNotificationServer.filter, Unmanaged.passUnretained(server).toOpaque(), nil)
        let thread = Thread { [server] in
            while server.isRunning { _ = dbus_connection_read_write_dispatch(server.connection, 20) }
        }
        server.thread = thread
        thread.start()
        return server
    }

    private init(connection: OpaquePointer) { self.connection = connection }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    func stop() {
        lock.lock(); running = false; lock.unlock()
        Thread.sleep(forTimeInterval: 0.1)
        dbus_connection_close(connection)
        dbus_connection_unref(connection)
    }

    private static let filter: DBusHandleMessageFunction = { connection, message, context in
        guard let connection, let message, let context else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
        let server = Unmanaged<FakeNotificationServer>.fromOpaque(context).takeUnretainedValue()
        return server.handle(connection, message) ? DBUS_HANDLER_RESULT_HANDLED : DBUS_HANDLER_RESULT_NOT_YET_HANDLED
    }

    private func handle(_ connection: OpaquePointer, _ message: OpaquePointer) -> Bool {
        guard dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_METHOD_CALL,
              let memberC = dbus_message_get_member(message),
              let reply = dbus_message_new_method_return(message) else { return false }
        defer { dbus_message_unref(reply) }
        var out = DBusMessageIter()
        dbus_message_iter_init_append(reply, &out)
        switch String(cString: memberC) {
        case "GetCapabilities":
            var array = DBusMessageIter()
            dbus_message_iter_open_container(&out, DBusType.array, "s", &array)
            for cap in ["actions", "body", "body-markup", "inline-reply"] { append(&array, cap) }
            dbus_message_iter_close_container(&out, &array)
        case "Notify":
            var iter = DBusMessageIter()
            dbus_message_iter_init(message, &iter)
            let appName = string(&iter); _ = dbus_message_iter_next(&iter)
            var replaces: UInt32 = 0
            dbus_message_iter_get_basic(&iter, &replaces); _ = dbus_message_iter_next(&iter)
            _ = string(&iter); _ = dbus_message_iter_next(&iter)
            let summary = string(&iter); _ = dbus_message_iter_next(&iter)
            let body = string(&iter); _ = dbus_message_iter_next(&iter)
            var actions: [String] = []
            var sub = DBusMessageIter()
            dbus_message_iter_recurse(&iter, &sub)
            while dbus_message_iter_get_arg_type(&sub) == DBusType.string {
                actions.append(string(&sub))
                if dbus_message_iter_next(&sub) == 0 { break }
            }
            _ = dbus_message_iter_next(&iter)
            var hintKeys: [String] = []
            dbus_message_iter_recurse(&iter, &sub)
            while dbus_message_iter_get_arg_type(&sub) == DBusType.dictEntry {
                var entry = DBusMessageIter()
                dbus_message_iter_recurse(&sub, &entry)
                hintKeys.append(string(&entry))
                if dbus_message_iter_next(&sub) == 0 { break }
            }
            lock.lock()
            var id = replaces
            if id == 0 { nextID += 1; id = nextID }
            _notifies.append(Notify(id: id, appName: appName, replacesID: replaces, summary: summary, body: body, actions: actions, hintKeys: hintKeys))
            lock.unlock()
            dbus_message_iter_append_basic(&out, DBusType.uint32, &id)
        case "CloseNotification":
            var iter = DBusMessageIter()
            dbus_message_iter_init(message, &iter)
            var id: UInt32 = 0
            dbus_message_iter_get_basic(&iter, &id)
            lock.lock(); _closed.append(id); lock.unlock()
            emit("NotificationClosed", id) { iter in
                var reason: UInt32 = 3
                dbus_message_iter_append_basic(&iter, DBusType.uint32, &reason)
            }
        default:
            return false
        }
        var serial: UInt32 = 0
        dbus_connection_send(connection, reply, &serial)
        return true
    }

    func emit(_ member: String, _ id: UInt32, _ rest: (inout DBusMessageIter) -> Void) {
        guard let signal = dbus_message_new_signal(FreedesktopNotifier.path, FreedesktopNotifier.interface, member) else { return }
        defer { dbus_message_unref(signal) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(signal, &iter)
        var value = id
        dbus_message_iter_append_basic(&iter, DBusType.uint32, &value)
        rest(&iter)
        var serial: UInt32 = 0
        dbus_connection_send(connection, signal, &serial)
        dbus_connection_flush(connection)
    }

    func emit(_ member: String, _ id: UInt32, string: String) {
        emit(member, id) { iter in self.append(&iter, string) }
    }

    private func append(_ iter: inout DBusMessageIter, _ s: String) {
        s.withCString { p in
            var ptr: UnsafePointer<CChar>? = p
            dbus_message_iter_append_basic(&iter, DBusType.string, &ptr)
        }
    }

    private func string(_ iter: inout DBusMessageIter) -> String {
        guard dbus_message_iter_get_arg_type(&iter) == DBusType.string else { return "" }
        var p: UnsafePointer<CChar>? = nil
        dbus_message_iter_get_basic(&iter, &p)
        return p.map { String(cString: $0) } ?? ""
    }
}

final class FreedesktopNotifierTests: XCTestCase {
    final class Events: @unchecked Sendable {
        let lock = NSLock()
        var list: [PlatformNotificationEvent] = []
        func add(_ e: PlatformNotificationEvent) { lock.lock(); list.append(e); lock.unlock() }
        var all: [PlatformNotificationEvent] { lock.lock(); defer { lock.unlock() }; return list }
    }

    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    }

    func testNotifyActionsSignalsAndClose() throws {
        guard let server = FakeNotificationServer.start() else {
            throw XCTSkip("no session bus, or a notification server already owns org.freedesktop.Notifications")
        }
        defer { server.stop() }
        let notifier = FreedesktopNotifier(identity: PlatformAppIdentity(identifier: "com.example.HelloTests", displayName: "Hello Tests", executablePath: "/usr/bin/hello"))
        let events = Events()
        notifier.setEventHandler { events.add($0) }
        XCTAssertEqual(notifier.authorization(), .allowed)

        let n = PlatformNotification(identifier: "task-1", title: "Pending", subtitle: "", body: "3 < 4 tasks", playsSound: true, soundName: nil, imageFiles: [],
                                     actions: [PlatformAction(identifier: "done", title: "Done", destructive: false, foreground: true, textInput: nil),
                                               PlatformAction(identifier: "reply", title: "Reply", destructive: false, foreground: false, textInput: (buttonTitle: "Send", placeholder: ""))],
                                     listOnly: false, interruptionLevel: .active, threadIdentifier: "")
        try notifier.post(n)
        let first = try XCTUnwrap(server.notifies.first)
        XCTAssertEqual(first.appName, "Hello Tests")
        XCTAssertEqual(first.summary, "Pending")
        XCTAssertEqual(first.body, "3 &lt; 4 tasks")
        XCTAssertEqual(first.actions, ["default", "", "done", "Done", "inline-reply", "Send"])
        XCTAssertEqual(first.hintKeys, ["desktop-entry", "urgency", "sound-name"])

        // Posting the same identifier again replaces the shown notification.
        try notifier.post(n)
        XCTAssertEqual(server.notifies.last?.replacesID, first.id)

        server.emit("ActionInvoked", first.id, string: "done")
        eventually { !events.all.isEmpty }
        XCTAssertEqual(events.all.first, .activated(identifier: "task-1", actionIdentifier: "done", userText: nil))

        try notifier.post(n)
        let second = try XCTUnwrap(server.notifies.last)
        server.emit("NotificationReplied", second.id, string: "on my way")
        eventually { events.all.count >= 2 }
        XCTAssertEqual(events.all.last, .activated(identifier: "task-1", actionIdentifier: "reply", userText: "on my way"))

        // Another app's notification id is ignored.
        server.emit("ActionInvoked", 9999, string: "default")
        try notifier.post(n)
        let third = try XCTUnwrap(server.notifies.last)
        notifier.remove(identifiers: ["task-1"])
        eventually { server.closed.contains(third.id) }
        XCTAssertEqual(server.closed, [third.id])
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(events.all.count, 2, "closing a notification it removed itself reports nothing")
    }
}
#endif
