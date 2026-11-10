// The AT-SPI2 bridge (ADR-0013) on the X11 backend: a second D-Bus connection plays an
// assistive technology, walks this process's tree through the bridge, presses a button,
// and hears the focus event. Runs where the X11 backend is up with an accessibility bus
// (tools/linux/run.sh under Xvfb); skipped everywhere else.

import XCTest
@testable import AppKit
#if os(Linux)
import CDBus
import Glibc
#endif

final class AtspiTests: XCTestCase, @unchecked Sendable {
    #if os(Linux)
    @MainActor
    private func bridge() throws -> (LinuxBackend, AtspiBridge) {
        guard ProcessInfo.processInfo.environment["DISPLAY"] != nil, let b = Platform.backend as? LinuxBackend else { throw XCTSkip("needs the X11 backend (DISPLAY set, APPKITWIN_HOST_BACKEND unset)") }
        guard let bridge = b.atspi else { throw XCTSkip("no accessibility bus (AT_SPI_BUS_ADDRESS or org.a11y.Bus on the session bus)") }
        return (b, bridge)
    }

    /// A client connection to the same bus, pumped together with the backend so this
    /// process can answer its own calls.
    @MainActor
    private final class Client {
        let connection: OpaquePointer
        let backend: LinuxBackend
        nonisolated(unsafe) static var signals: [(path: String, member: String, detail: String)] = []

        init?(address: String, backend: LinuxBackend) {
            var err = DBusError()
            dbus_error_init(&err)
            guard let c = dbus_connection_open_private(address, &err), dbus_bus_register(c, &err) != 0 else { dbus_error_free(&err); return nil }
            connection = c
            self.backend = backend
            dbus_connection_set_exit_on_disconnect(c, 0)
            dbus_bus_add_match(c, "type='signal',interface='org.a11y.atspi.Event.Object'", nil)
            dbus_bus_add_match(c, "type='signal',interface='org.a11y.atspi.Event.Focus'", nil)
            dbus_connection_add_filter(c, { _, message, _ in
                guard let message, dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_SIGNAL, let p = dbus_message_get_path(message), let m = dbus_message_get_member(message) else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
                var iter = DBusMessageIter()
                var detail = ""
                if dbus_message_iter_init(message, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.string {
                    var s: UnsafePointer<CChar>? = nil
                    dbus_message_iter_get_basic(&iter, &s)
                    detail = s.map { String(cString: $0) } ?? ""
                }
                Client.signals.append((String(cString: p), String(cString: m), detail))
                return DBUS_HANDLER_RESULT_HANDLED
            }, nil, nil)
        }

        func close() { dbus_connection_close(connection); dbus_connection_unref(connection) }

        func pump(_ seconds: TimeInterval = 0.3) {
            let deadline = Date(timeIntervalSinceNow: seconds)
            while Date() < deadline { backend.pump(blocking: false); dbus_connection_read_write_dispatch(connection, 5) }
        }

        /// Calls a method on this process and returns the reply's first-argument reader.
        func call(_ dest: String, _ path: String, _ iface: String, _ member: String, _ args: (inout DBusMessageIter) -> Void = { _ in }) -> OpaquePointer? {
            guard let msg = dbus_message_new_method_call(dest, path, iface, member) else { return nil }
            defer { dbus_message_unref(msg) }
            var iter = DBusMessageIter()
            dbus_message_iter_init_append(msg, &iter)
            args(&iter)
            var pending: OpaquePointer? = nil
            guard dbus_connection_send_with_reply(connection, msg, &pending, 5000) != 0, let pending else { return nil }
            dbus_connection_flush(connection)
            let deadline = Date(timeIntervalSinceNow: 5)
            while dbus_pending_call_get_completed(pending) == 0 && Date() < deadline { backend.pump(blocking: false); dbus_connection_read_write_dispatch(connection, 5) }
            let reply = dbus_pending_call_steal_reply(pending)
            dbus_pending_call_unref(pending)
            // An error reply (unknown object, unknown method) counts as no answer.
            if let reply, dbus_message_get_type(reply) == DBUS_MESSAGE_TYPE_ERROR { dbus_message_unref(reply); return nil }
            return reply
        }

        func string(_ dest: String, _ path: String, _ iface: String, _ member: String, _ args: (inout DBusMessageIter) -> Void = { _ in }) -> String? {
            guard let r = call(dest, path, iface, member, args) else { return nil }
            defer { dbus_message_unref(r) }
            var iter = DBusMessageIter()
            guard dbus_message_iter_init(r, &iter) != 0 else { return nil }
            var reader = DBus.Reader(iter: iter, valid: true)
            if dbus_message_iter_get_arg_type(&iter) == DBus.variant { return reader.variant().flatMap { if case .string(let s) = $0 { return s } else { return nil } } }
            return reader.string()
        }

        func children(_ dest: String, _ path: String) -> [String] {
            guard let r = call(dest, path, "org.a11y.atspi.Accessible", "GetChildren") else { return [] }
            defer { dbus_message_unref(r) }
            var iter = DBusMessageIter()
            guard dbus_message_iter_init(r, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.array else { return [] }
            var array = DBusMessageIter()
            dbus_message_iter_recurse(&iter, &array)
            var paths: [String] = []
            while dbus_message_iter_get_arg_type(&array) == DBus.structType {
                if let ref = DBus.readObjectReference(&array) { paths.append(ref.path) }
                dbus_message_iter_next(&array)
            }
            return paths
        }

        func bool(_ dest: String, _ path: String, _ iface: String, _ member: String, _ args: (inout DBusMessageIter) -> Void = { _ in }) -> Bool? {
            guard let r = call(dest, path, iface, member, args) else { return nil }
            defer { dbus_message_unref(r) }
            var iter = DBusMessageIter()
            guard dbus_message_iter_init(r, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.boolean else { return nil }
            var b: dbus_bool_t = 0
            dbus_message_iter_get_basic(&iter, &b)
            return b != 0
        }
    }

    private final class Target: NSObject, NSSelectorHandling {
        var presses = 0
        func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool { presses += 1; return true }
    }

    func testTreeActionsAndFocusOverTheBus() throws {
        try MainActor.assumeIsolated {
            let (backend, bridge) = try bridge()
            guard let client = Client(address: bridge.address, backend: backend) else { throw XCTSkip("cannot open a client connection to \(bridge.address)") }
            let target = Target()
            let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 320, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "AT-SPI window"
            let button = NSButton(title: "Press me", target: target, action: Selector(("pressed:")))
            button.frame.origin = NSPoint(x: 20, y: 20)
            let check = NSButton(checkboxWithTitle: "Checked", target: nil, action: nil)
            check.frame.origin = NSPoint(x: 20, y: 60)
            let field = NSTextField(string: "hello")
            field.frame = NSRect(x: 20, y: 100, width: 200, height: 24)
            for v in [button, check, field] as [NSView] { w.contentView!.addSubview(v) }
            w.makeKeyAndOrderFront(nil)
            client.pump()
            defer { w.close(); client.pump(0.1); client.close() }

            let me = bridge.uniqueName
            let root = AtspiBridge.rootPath
            XCTAssertEqual(client.string(me, root, "org.freedesktop.DBus.Properties", "Get") { DBus.appendString(&$0, "org.a11y.atspi.Application"); DBus.appendString(&$0, "ToolkitName") }, "AppKitCross")
            XCTAssertEqual(client.string(me, root, "org.a11y.atspi.Accessible", "GetRoleName"), "application")
            let windows = client.children(me, root)
            let windowPath = AtspiBridge.elementPathPrefix + String(w._accessibilityElementID)
            XCTAssertTrue(windows.contains(windowPath), "the window is a child of the application: \(windows)")
            XCTAssertEqual(client.string(me, windowPath, "org.a11y.atspi.Accessible", "GetRoleName"), "frame")
            XCTAssertEqual(client.string(me, windowPath, "org.freedesktop.DBus.Properties", "Get") { DBus.appendString(&$0, "org.a11y.atspi.Accessible"); DBus.appendString(&$0, "Name") }, "AT-SPI window")
            let kids = client.children(me, windowPath)
            XCTAssertEqual(kids.count, 3)
            let roles = kids.map { client.string(me, $0, "org.a11y.atspi.Accessible", "GetRoleName") ?? "" }
            XCTAssertEqual(roles, ["push button", "check box", "text"])
            let buttonPath = AtspiBridge.elementPathPrefix + String(button._accessibilityElementID)
            XCTAssertEqual(client.string(me, buttonPath, "org.freedesktop.DBus.Properties", "Get") { DBus.appendString(&$0, "org.a11y.atspi.Accessible"); DBus.appendString(&$0, "Name") }, "Press me")
            XCTAssertEqual(client.string(me, buttonPath, "org.a11y.atspi.Action", "GetName") { DBus.appendInt32(&$0, 0) }, "press")
            // DoAction presses the button in this process.
            XCTAssertEqual(client.bool(me, buttonPath, "org.a11y.atspi.Action", "DoAction") { DBus.appendInt32(&$0, 0) }, true)
            XCTAssertEqual(target.presses, 1)
            // The field's text through the Text interface, and a new value through EditableText.
            let fieldPath = AtspiBridge.elementPathPrefix + String(field._accessibilityElementID)
            XCTAssertEqual(client.string(me, fieldPath, "org.a11y.atspi.Text", "GetText") { DBus.appendInt32(&$0, 0); DBus.appendInt32(&$0, -1) }, "hello")
            XCTAssertEqual(client.bool(me, fieldPath, "org.a11y.atspi.EditableText", "SetTextContents") { DBus.appendString(&$0, "world") }, true)
            XCTAssertEqual(field.stringValue, "world")
            // Focus moves are signalled as StateChanged(focused) on the element.
            Client.signals.removeAll()
            XCTAssertEqual(client.bool(me, buttonPath, "org.a11y.atspi.Component", "GrabFocus"), true)
            XCTAssertTrue(w.firstResponder === button)
            client.pump()
            XCTAssertTrue(Client.signals.contains { $0.path == buttonPath && $0.member == "StateChanged" && $0.detail == "focused" }, "signals: \(Client.signals)")
            // A missing object is an error, not a crash.
            XCTAssertNil(client.string(me, AtspiBridge.elementPathPrefix + "999999", "org.a11y.atspi.Accessible", "GetRoleName"))
        }
    }
    #else
    func testSkippedWithoutATSPI() throws {
        throw XCTSkip("AT-SPI2 exists on Linux only")
    }
    #endif
}
