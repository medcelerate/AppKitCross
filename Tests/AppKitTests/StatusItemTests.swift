// NSStatusBar / NSStatusItem on the host backend's in-process status area: the button's
// title, image and tool tip reach the platform item, clicks send the action or open the
// menu at the click, visibility is remembered under the autosave name (ADR-0018).

import XCTest
@testable import AppKit
#if os(Linux)
import Glibc
import CDBus
#endif

final class StatusItemTests: XCTestCase, @unchecked Sendable {
    @MainActor private var host: HostStatusItems { (Platform.backend as! HostBackend).hostStatusItems }

    @MainActor private final class Receiver: NSObject, NSSelectorHandling {
        var clicks: [String] = []
        static let act = Selector(("statusAction:"))
        func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
            guard action == Receiver.act else { return false }
            let event = NSApplication.shared.currentEvent
            clicks.append("\(type(of: sender!)) \(event.map { "\($0.type)" } ?? "none")")
            return true
        }
    }

    func testButtonStateReachesThePlatformItem() throws {
        try requireHostBackend("needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let bar = NSStatusBar.system
            XCTAssertTrue(bar === NSStatusBar.system)
            XCTAssertFalse(bar.isVertical)
            XCTAssertEqual(bar.thickness, 22)
            let before = host.items.count
            let item = bar.statusItem(withLength: NSStatusItem.variableLength)
            defer { bar.removeStatusItem(item) }
            XCTAssertEqual(host.items.count, before + 1)
            XCTAssertTrue(item.statusBar === bar)
            XCTAssertEqual(item.length, NSStatusItem.variableLength)
            XCTAssertEqual(NSStatusItem.squareLength, -2)
            guard let button = item.button, let platform = host.items.last else { return XCTFail() }
            XCTAssertTrue(button._statusItem === item)
            button.title = "Sync"
            button.toolTip = "Syncing files"
            button.image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in NSColor.blue.setFill(); NSBezierPath(ovalIn: r).fill(); return true }
            XCTAssertEqual(platform.title, "Sync")
            XCTAssertEqual(platform.toolTip, "Syncing files")
            XCTAssertNotNil(platform.image)
            XCTAssertEqual(platform.image?.width, 32, "rasterised at the screen's scale")
            XCTAssertTrue(platform.isVisible)
            item.title = "Done"
            XCTAssertEqual(button.title, "Done")
            XCTAssertEqual(platform.title, "Done")
            button.appearsDisabled = true
            XCTAssertTrue(platform.appearsDisabled)
            item.isVisible = false
            XCTAssertFalse(platform.isVisible)
            XCTAssertTrue(host.visibleItems.allSatisfy { $0 !== platform })
            item.isVisible = true
            XCTAssertTrue(platform.isVisible)
        }
    }

    func testClicksSendTheActionOrOpenTheMenu() throws {
        try requireHostBackend("needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let bar = NSStatusBar.system
            let item = bar.statusItem(withLength: NSStatusItem.squareLength)
            defer { bar.removeStatusItem(item) }
            let r = Receiver()
            item.button?.target = r
            item.button?.action = Receiver.act
            let platform = host.items.last!
            platform.click(.primary)
            XCTAssertEqual(r.clicks, ["NSStatusBarButton leftMouseUp"])
            platform.click(.secondary)
            XCTAssertEqual(r.clicks.count, 1, "right clicks send nothing unless asked for")
            _ = item.sendAction(on: [.leftMouseUp, .rightMouseUp])
            platform.click(.secondary)
            XCTAssertEqual(r.clicks.last, "NSStatusBarButton rightMouseUp")
            item.button?.isEnabled = false
            platform.click(.primary)
            XCTAssertEqual(r.clicks.count, 2, "a disabled button ignores clicks")
            item.button?.isEnabled = true
            // With a menu, a click opens it at the click point and sends no action.
            let menu = NSMenu(title: "Status")
            menu.addItem(withTitle: "Quit", action: Receiver.act, keyEquivalent: "").target = r
            item.menu = menu
            let point = NSPoint(x: 1500, y: 1000)
            Platform.backend.post { [weak menu] in
                XCTAssertTrue(_NSMenuTracker.isTracking)
                let w = NSApplication.shared.windows.compactMap { $0 as? _NSMenuWindow }.first { $0.isVisible }
                XCTAssertNotNil(w)
                XCTAssertEqual(w?.frame.minX ?? 0, point.x, accuracy: 0.5)
                XCTAssertEqual(w?.frame.maxY ?? 0, point.y, accuracy: 0.5)
                XCTAssertTrue(menu === w?.menuView.ownerMenu)
                _NSMenuTracker.current?.cancel()
            }
            platform.click(.primary, at: point)
            XCTAssertFalse(_NSMenuTracker.isTracking)
            XCTAssertEqual(r.clicks.count, 2, "the menu replaced the action")
            // Right click: the same menu.
            Platform.backend.post { _NSMenuTracker.current?.cancel() }
            platform.click(.secondary, at: point)
            XCTAssertFalse(_NSMenuTracker.isTracking)
            // Removal takes the platform item away; the button is gone with it.
            bar.removeStatusItem(item)
            XCTAssertTrue(platform.removed)
            XCTAssertNil(item.button)
            XCTAssertFalse(host.items.contains { $0 === platform })
        }
    }

    func testVisibilityIsRememberedUnderTheAutosaveName() throws {
        try requireHostBackend("needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)")
        MainActor.assumeIsolated {
            let key = "NSStatusItem Visible test.item"
            UserDefaults.standard.removeObject(forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let bar = NSStatusBar.system
            let item = bar.statusItem(withLength: NSStatusItem.variableLength)
            XCTAssertTrue(item.autosaveName.hasPrefix("Item-"), "a generated name until one is set")
            item.autosaveName = "test.item"
            item.behavior = [.removalAllowed]
            XCTAssertEqual(item.behavior, [.removalAllowed])
            item.isVisible = false
            XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, false)
            bar.removeStatusItem(item)
            let again = bar.statusItem(withLength: NSStatusItem.variableLength)
            defer { bar.removeStatusItem(again) }
            XCTAssertTrue(again.isVisible)
            again.autosaveName = "test.item"
            XCTAssertFalse(again.isVisible, "the saved visibility applies once the name is known")
            XCTAssertFalse(host.items.last!.isVisible)
        }
    }

    #if os(Linux)
    /// With a session bus (the container's run.sh starts one), the StatusNotifierItem host
    /// serves the item's properties over D-Bus; without a watcher it is merely unregistered.
    func testStatusNotifierItemServesPropertiesOnTheSessionBus() throws {
        try requireHostBackend("needs the host backend's rendered window (APPKITWIN_HOST_BACKEND=1)")
        try MainActor.assumeIsolated {
            guard ProcessInfo.processInfo.environment["DBUS_SESSION_BUS_ADDRESS"] != nil else { throw XCTSkip("no session bus") }
            guard let host = LinuxStatusNotifierHost.connect(screenPoint: { x, y in NSPoint(x: CGFloat(x), y: CGFloat(y)) }) else { return XCTFail("no connection") }
            @MainActor final class Owner: PlatformStatusItemOwner { var clicks: [PlatformStatusItemClick] = []; func platformStatusItemClicked(_ c: PlatformStatusItemClick, at p: NSPoint) { clicks.append(c) } }
            let owner = Owner()
            let item = host.makeStatusItem(owner: owner)
            item.title = "Probe"
            item.toolTip = "Probe tip"
            XCTAssertEqual((item as? LinuxStatusNotifierItem)?.path, "/StatusNotifierItem")
            XCTAssertFalse(host.uniqueName.isEmpty)
            // A second private connection asks for the properties like a tray would.
            var err = DBusError()
            dbus_error_init(&err)
            guard let client = dbus_bus_get_private(DBUS_BUS_SESSION, &err) else { return XCTFail("client connection") }
            defer { dbus_connection_close(client); dbus_connection_unref(client) }
            dbus_connection_set_exit_on_disconnect(client, 0)
            let call = dbus_message_new_method_call(host.uniqueName, "/StatusNotifierItem", "org.freedesktop.DBus.Properties", "Get")!
            var it = DBusMessageIter()
            dbus_message_iter_init_append(call, &it)
            DBus.appendString(&it, "org.kde.StatusNotifierItem")
            DBus.appendString(&it, "Title")
            var pending: OpaquePointer? = nil
            dbus_connection_send_with_reply(client, call, &pending, 2000)
            dbus_message_unref(call)
            dbus_connection_flush(client)
            var reply: OpaquePointer? = nil
            for _ in 0..<200 where reply == nil {
                host.dispatch()
                dbus_connection_read_write(client, 10)
                if let p = pending, dbus_pending_call_get_completed(p) != 0 { reply = dbus_pending_call_steal_reply(p) }
            }
            guard let reply else { return XCTFail("no reply from the item") }
            defer { dbus_message_unref(reply) }
            XCTAssertEqual(dbus_message_get_type(reply), DBUS_MESSAGE_TYPE_METHOD_RETURN)
            var r = DBusMessageIter()
            var reader = DBus.Reader(iter: r, valid: dbus_message_iter_init(reply, &r) != 0)
            reader.iter = r
            if case .string(let title)? = reader.variant() { XCTAssertEqual(title, "Probe") } else { XCTFail("no title variant") }
            // Activate from the "tray" becomes a primary click.
            let activate = dbus_message_new_method_call(host.uniqueName, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "Activate")!
            var a = DBusMessageIter()
            dbus_message_iter_init_append(activate, &a)
            DBus.appendInt32(&a, 10); DBus.appendInt32(&a, 20)
            dbus_connection_send(client, activate, nil)
            dbus_message_unref(activate)
            dbus_connection_flush(client)
            for _ in 0..<50 where owner.clicks.isEmpty { host.dispatch(); usleep(5000) }
            XCTAssertEqual(owner.clicks, [.primary])
            item.remove()
        }
    }
    #endif
}

