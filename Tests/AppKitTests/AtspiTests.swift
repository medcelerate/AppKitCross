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

    /// The first argument of a reply when it is a struct of int32 (GetExtents).
    @MainActor
    private func extents(_ client: Client, _ me: String, _ path: String, coordinateType: UInt32 = 0) -> [Int32] {
        guard let r = client.call(me, path, "org.a11y.atspi.Component", "GetExtents", { DBus.appendUInt32(&$0, coordinateType) }) else { return [] }
        defer { dbus_message_unref(r) }
        var iter = DBusMessageIter()
        guard dbus_message_iter_init(r, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.structType else { return [] }
        var fields = DBusMessageIter()
        dbus_message_iter_recurse(&iter, &fields)
        var out: [Int32] = []
        while dbus_message_iter_get_arg_type(&fields) == Int32(UInt8(ascii: "i")) {
            var v: Int32 = 0
            dbus_message_iter_get_basic(&fields, &v)
            out.append(v)
            dbus_message_iter_next(&fields)
        }
        return out
    }

    @MainActor
    private func states(_ client: Client, _ me: String, _ path: String) -> Set<Int> {
        guard let r = client.call(me, path, "org.a11y.atspi.Accessible", "GetState") else { return [] }
        defer { dbus_message_unref(r) }
        var iter = DBusMessageIter()
        guard dbus_message_iter_init(r, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.array else { return [] }
        var words = DBusMessageIter()
        dbus_message_iter_recurse(&iter, &words)
        var bits = Set<Int>()
        var word = 0
        while dbus_message_iter_get_arg_type(&words) == Int32(UInt8(ascii: "u")) {
            var v: UInt32 = 0
            dbus_message_iter_get_basic(&words, &v)
            for b in 0..<32 where v & (1 << UInt32(b)) != 0 { bits.insert(word * 32 + b) }
            word += 1
            dbus_message_iter_next(&words)
        }
        return bits
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

    /// ADR-0013 follow-ups over the bus: the menu bar under the application, a pop-up's
    /// items while it is open, custom actions as extra actions, and extents through the
    /// window's own client origin and scale.
    func testMenusPopUpsCustomActionsAndExtentsOverTheBus() throws {
        try MainActor.assumeIsolated {
            let (backend, bridge) = try bridge()
            guard let client = Client(address: bridge.address, backend: backend) else { throw XCTSkip("cannot open a client connection to \(bridge.address)") }
            let target = Target()
            let app = NSApplication.shared
            let savedMenu = app.mainMenu
            let main = NSMenu(title: "Main")
            let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let file = NSMenu(title: "File")
            file.autoenablesItems = false
            let save = NSMenuItem(title: "Save", action: Selector(("saveDocument:")), keyEquivalent: "s")
            save.target = target
            let wrap = NSMenuItem(title: "Wrap Lines", action: Selector(("wrap:")), keyEquivalent: "")
            wrap.target = target
            wrap.state = .on
            file.addItem(save)
            file.addItem(wrap)
            fileItem.submenu = file
            main.addItem(fileItem)
            app.mainMenu = main

            let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 320, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Menus"
            let popup = NSPopUpButton(frame: NSRect(x: 20, y: 20, width: 120, height: 26), pullsDown: false)
            popup.addItems(withTitles: ["Blue", "Red"])
            let button = NSButton(title: "Message", target: nil, action: nil)
            button.frame.origin = NSPoint(x: 20, y: 80)
            var archived = 0
            button.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Archive") { archived += 1; return true }])
            for v in [popup, button] as [NSView] { w.contentView!.addSubview(v) }
            w.makeKeyAndOrderFront(nil)
            client.pump()
            defer { app.mainMenu = savedMenu; w.close(); client.pump(0.1); client.close() }

            let me = bridge.uniqueName
            let p = { (id: Int) in AtspiBridge.elementPathPrefix + String(id) }
            // The menu bar is the application's child, next to the windows.
            let appKids = client.children(me, AtspiBridge.rootPath)
            XCTAssertTrue(appKids.contains(p(main._accessibilityElementID)), "children: \(appKids)")
            XCTAssertEqual(client.string(me, p(main._accessibilityElementID), "org.a11y.atspi.Accessible", "GetRoleName"), "menu bar")
            XCTAssertEqual(client.children(me, p(main._accessibilityElementID)), [p(fileItem._accessibilityElementID)])
            XCTAssertEqual(client.children(me, p(fileItem._accessibilityElementID)), [p(file._accessibilityElementID)])
            XCTAssertEqual(client.string(me, p(file._accessibilityElementID), "org.a11y.atspi.Accessible", "GetRoleName"), "menu")
            XCTAssertEqual(client.string(me, p(save._accessibilityElementID), "org.a11y.atspi.Accessible", "GetRoleName"), "menu item")
            XCTAssertEqual(client.string(me, p(save._accessibilityElementID), "org.a11y.atspi.Action", "GetKeyBinding") { DBus.appendInt32(&$0, 0) }, ";;<Control>s")
            XCTAssertEqual(client.string(me, p(wrap._accessibilityElementID), "org.a11y.atspi.Accessible", "GetRoleName"), "check menu item")
            XCTAssertTrue(states(client, me, p(wrap._accessibilityElementID)).isSuperset(of: [4, 41]), "checked, checkable")
            // Pressing a menu item performs it.
            XCTAssertEqual(client.bool(me, p(save._accessibilityElementID), "org.a11y.atspi.Action", "DoAction") { DBus.appendInt32(&$0, 0) }, true)
            XCTAssertEqual(target.presses, 1)

            // The pop-up: a combo box with a popup; expanding shows its items as children.
            let popupPath = p(popup._accessibilityElementID)
            XCTAssertEqual(client.string(me, popupPath, "org.a11y.atspi.Accessible", "GetRoleName"), "combo box")
            XCTAssertTrue(states(client, me, popupPath).isSuperset(of: [9, 5, 42]), "expandable, collapsed, has-popup")
            XCTAssertEqual(client.children(me, popupPath), [])
            let actions = (0..<4).map { i in client.string(me, popupPath, "org.a11y.atspi.Action", "GetName") { DBus.appendInt32(&$0, Int32(i)) } ?? "" }
            XCTAssertEqual(actions, ["press", "showMenu", "expand", "collapse"])
            XCTAssertEqual(client.bool(me, popupPath, "org.a11y.atspi.Action", "DoAction") { DBus.appendInt32(&$0, 2) }, true)
            client.pump()
            XCTAssertTrue(states(client, me, popupPath).contains(10), "expanded")
            let menuPaths = client.children(me, popupPath)
            XCTAssertEqual(menuPaths.count, 1)
            XCTAssertEqual(menuPaths.first.flatMap { client.string(me, $0, "org.a11y.atspi.Accessible", "GetRoleName") }, "menu")
            let items = menuPaths.first.map { client.children(me, $0) } ?? []
            XCTAssertEqual(items.map { client.string(me, $0, "org.freedesktop.DBus.Properties", "Get") { DBus.appendString(&$0, "org.a11y.atspi.Accessible"); DBus.appendString(&$0, "Name") } ?? "" }, ["Blue", "Red"])
            XCTAssertEqual(extents(client, me, items[1]).count, 4)
            XCTAssertGreaterThan(extents(client, me, items[1])[2], 0, "an open item has a size on screen")
            XCTAssertEqual(client.bool(me, items[1], "org.a11y.atspi.Action", "DoAction") { DBus.appendInt32(&$0, 0) }, true)
            client.pump()
            XCTAssertEqual(popup.titleOfSelectedItem, "Red")
            XCTAssertEqual(client.children(me, popupPath), [])

            // Custom actions follow the role's actions.
            let buttonPath = p(button._accessibilityElementID)
            XCTAssertEqual(client.string(me, buttonPath, "org.a11y.atspi.Action", "GetName") { DBus.appendInt32(&$0, 1) }, "Archive")
            XCTAssertEqual(client.bool(me, buttonPath, "org.a11y.atspi.Action", "DoAction") { DBus.appendInt32(&$0, 1) }, true)
            XCTAssertEqual(archived, 1)

            // Extents: the client area's root position plus the offset at the window's scale.
            let lw = Mirror(reflecting: w).descendant("_platform") as! LinuxWindow
            let tree = w.accessibilityTree()
            let mapping = lw.accessibilityScreenMapping(clientFrame: tree.mappingClientFrame)!
            let expected = mapping.pixelRect(button.accessibilityFrame())
            XCTAssertEqual(extents(client, me, buttonPath), [expected.x, expected.y, expected.width, expected.height])
            XCTAssertEqual(expected.width, Int32((button.frame.width * lw.backingScaleFactor).rounded()))
        }
    }
    #else
    func testSkippedWithoutATSPI() throws {
        throw XCTSkip("AT-SPI2 exists on Linux only")
    }
    #endif
}
