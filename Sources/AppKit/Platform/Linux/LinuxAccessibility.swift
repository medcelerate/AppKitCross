// AT-SPI2 over D-Bus for the Linux backends (ADR-0013).
//
// The bridge connects to the accessibility bus (AT_SPI_BUS_ADDRESS, else
// org.a11y.Bus.GetAddress on the session bus, else the X root window's AT_SPI_BUS
// property), embeds the application with the registry's org.a11y.atspi.Socket, and
// serves the application's windows and their accessibility snapshots as objects under
// /org/a11y/atspi/accessible/<id> with the Accessible, Application, Component, Action,
// Value, Text and EditableText interfaces. The core's change notifications become
// org.a11y.atspi.Event signals. The connection is pumped from the backend's poll loop.

#if os(Linux)
import Foundation
import Glibc
import CDBus

/// A platform window the bridge exposes.
@MainActor
protocol AtspiWindow: AnyObject {
    var atspiOwner: PlatformWindowOwner? { get }
    var atspiIsVisible: Bool { get }
    var atspiIsKey: Bool { get }
}

@MainActor
final class AtspiBridge {
    static let rootPath = "/org/a11y/atspi/accessible/root"
    static let elementPathPrefix = "/org/a11y/atspi/accessible/"
    static let registryName = "org.a11y.atspi.Registry"

    private let connection: OpaquePointer                   // DBusConnection*
    /// The accessibility bus address the bridge connected to.
    private(set) var address = ""
    private(set) var uniqueName = ""
    private(set) var fileDescriptor: Int32 = -1
    private(set) var desktop: (name: String, path: String)? = nil
    /// AppKit screen rect → X screen pixels (left, top, width, height). Wayland has no
    /// global coordinates, so its backend reports window-relative ones.
    private let screenPixels: (NSRect) -> (Int32, Int32, Int32, Int32)
    private final class WindowEntry {
        weak var window: AtspiWindow?
        var tree: PlatformAccessibilityElement?
        var dirty = true
        init(_ w: AtspiWindow) { window = w }
    }
    private var windows: [WindowEntry] = []
    private var filterInstalled = false
    /// Debug aid: APPKITWIN_TRACE=1 logs requests and signals.
    private let trace = NSView._traceInvalidation

    // MARK: Connecting

    /// The address of the accessibility bus, or nil when there is none to be found.
    static func busAddress(rootWindowProperty: () -> String?) -> String? {
        let env = ProcessInfo.processInfo.environment
        if env["APPKITWIN_ATSPI"] == "0" { return nil }
        if let a = env["AT_SPI_BUS_ADDRESS"], !a.isEmpty { return a }
        var err = DBusError()
        dbus_error_init(&err)
        if let session = dbus_bus_get_private(DBUS_BUS_SESSION, &err) {
            defer { dbus_connection_close(session); dbus_connection_unref(session) }
            dbus_connection_set_exit_on_disconnect(session, 0)
            if let msg = dbus_message_new_method_call("org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress") {
                defer { dbus_message_unref(msg) }
                if let reply = dbus_connection_send_with_reply_and_block(session, msg, 2000, &err) {
                    defer { dbus_message_unref(reply) }
                    var iter = DBusMessageIter()
                    if dbus_message_iter_init(reply, &iter) != 0, dbus_message_iter_get_arg_type(&iter) == DBus.string {
                        var p: UnsafePointer<CChar>? = nil
                        dbus_message_iter_get_basic(&iter, &p)
                        if let p, p.pointee != 0 { return String(cString: p) }
                    }
                }
            }
        }
        dbus_error_free(&err)
        if let a = rootWindowProperty(), !a.isEmpty { return a }
        return nil
    }

    /// Connects and embeds; nil when there is no accessibility bus.
    static func connect(rootWindowProperty: () -> String?, screenPixels: @escaping (NSRect) -> (Int32, Int32, Int32, Int32)) -> AtspiBridge? {
        guard let address = busAddress(rootWindowProperty: rootWindowProperty) else { return nil }
        var err = DBusError()
        dbus_error_init(&err)
        guard let conn = dbus_connection_open_private(address, &err) else {
            if NSView._traceInvalidation { NSView._trace("atspi: cannot open \(address): \(err.message.map { String(cString: $0) } ?? "")") }
            dbus_error_free(&err)
            return nil
        }
        dbus_connection_set_exit_on_disconnect(conn, 0)
        guard dbus_bus_register(conn, &err) != 0 else {
            if NSView._traceInvalidation { NSView._trace("atspi: cannot register: \(err.message.map { String(cString: $0) } ?? "")") }
            dbus_error_free(&err)
            dbus_connection_close(conn)
            dbus_connection_unref(conn)
            return nil
        }
        let bridge = AtspiBridge(connection: conn, screenPixels: screenPixels)
        bridge.address = address
        bridge.start()
        return bridge
    }

    private init(connection: OpaquePointer, screenPixels: @escaping (NSRect) -> (Int32, Int32, Int32, Int32)) {
        self.connection = connection
        self.screenPixels = screenPixels
    }

    private func start() {
        if let n = dbus_bus_get_unique_name(connection) { uniqueName = String(cString: n) }
        var fd: Int32 = -1
        if dbus_connection_get_unix_fd(connection, &fd) != 0 { fileDescriptor = fd }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if dbus_connection_add_filter(connection, { conn, message, context in
            MainActor.assumeIsolated {
                guard let message, let context else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
                let bridge = Unmanaged<AtspiBridge>.fromOpaque(context).takeUnretainedValue()
                return bridge.handle(message) ? DBUS_HANDLER_RESULT_HANDLED : DBUS_HANDLER_RESULT_NOT_YET_HANDLED
            }
        }, context, nil) != 0 {
            filterInstalled = true
        }
        embed()
        if trace { NSView._trace("atspi: connected as \(uniqueName), desktop \(desktop.map { "\($0.name) \($0.path)" } ?? "none")") }
    }

    /// org.a11y.atspi.Socket.Embed on the registry: the application joins the desktop.
    private func embed() {
        guard let msg = dbus_message_new_method_call(AtspiBridge.registryName, AtspiBridge.rootPath, "org.a11y.atspi.Socket", "Embed") else { return }
        defer { dbus_message_unref(msg) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(msg, &iter)
        DBus.appendObjectReference(&iter, name: uniqueName, path: AtspiBridge.rootPath)
        var err = DBusError()
        dbus_error_init(&err)
        guard let reply = dbus_connection_send_with_reply_and_block(connection, msg, 3000, &err) else {
            if trace { NSView._trace("atspi: Embed failed: \(err.message.map { String(cString: $0) } ?? "")") }
            dbus_error_free(&err)
            return
        }
        defer { dbus_message_unref(reply) }
        var r = DBusMessageIter()
        if dbus_message_iter_init(reply, &r) != 0, let ref = DBus.readObjectReference(&r) { desktop = ref }
    }

    /// Pumps the connection: call after poll() reported the file descriptor readable, and
    /// once per loop iteration regardless (libdbus buffers).
    func dispatch() {
        while dbus_connection_read_write_dispatch(connection, 0) != 0 && dbus_connection_get_dispatch_status(connection) == DBUS_DISPATCH_DATA_REMAINS {}
    }

    // MARK: Windows

    func register(_ window: AtspiWindow) {
        windows.removeAll { $0.window == nil }
        windows.append(WindowEntry(window))
        emitWindowEvent("Create", window)
        emitChildrenChanged(parentPath: AtspiBridge.rootPath, childPath: windowPath(window), added: true)
    }

    func unregister(_ window: AtspiWindow) {
        let path = windowPath(window)
        emitWindowEvent("Destroy", window)
        windows.removeAll { $0.window == nil || $0.window === window }
        emitChildrenChanged(parentPath: AtspiBridge.rootPath, childPath: path, added: false)
    }

    private func windowPath(_ window: AtspiWindow) -> String {
        guard let id = windows.first(where: { $0.window === window })?.tree?.id ?? window.atspiOwner?.platformAccessibility.accessibilityTree().id else { return AtspiBridge.rootPath }
        return AtspiBridge.elementPathPrefix + String(id)
    }

    /// The core reported a change: refresh that window's snapshot and tell listeners.
    func windowDidChange(_ window: AtspiWindow, _ change: PlatformAccessibilityChange) {
        guard let entry = windows.first(where: { $0.window === window }) else { return }
        entry.dirty = true
        let tree = self.tree(for: entry)
        guard let tree else { return }
        switch change {
        case .focus(let id):
            if let id, let e = tree.element(withID: id) {
                emitObjectEvent(path: path(e.id), member: "StateChanged", detail: "focused", detail1: 1, detail2: 0, data: .int32(0))
                emitSignal(path: path(e.id), interface: "org.a11y.atspi.Event.Focus", member: "Focus", detail: "", detail1: 0, detail2: 0, data: .int32(0))
            }
        case .value(let id):
            guard let e = tree.element(withID: id) else { return }
            switch e.role {
            case "AXCheckBox", "AXRadioButton":
                emitObjectEvent(path: path(id), member: "StateChanged", detail: "checked", detail1: (e.value?.doubleValue ?? 0) != 0 ? 1 : 0, detail2: 0, data: .int32(0))
            case "AXTextField", "AXTextArea", "AXStaticText":
                let text = e.value?.stringValue ?? ""
                emitObjectEvent(path: path(id), member: "TextChanged", detail: "insert", detail1: 0, detail2: Int32(text.utf16.count), data: .string(text))
            default:
                emitObjectEvent(path: path(id), member: "PropertyChange", detail: "accessible-value", detail1: 0, detail2: 0, data: .double(e.value?.doubleValue ?? 0))
            }
        case .name(let id):
            guard let e = tree.element(withID: id) else { return }
            emitObjectEvent(path: path(id), member: "PropertyChange", detail: "accessible-name", detail1: 0, detail2: 0, data: .string(AtspiBridge.name(for: e) ?? ""))
        case .structure(let id):
            emitChildrenChanged(parentPath: path(id), childPath: path(id), added: true)
        case .selection(let id):
            emitObjectEvent(path: path(id), member: "SelectionChanged", detail: "", detail1: 0, detail2: 0, data: .int32(0))
            for c in tree.element(withID: id)?.children ?? [] where c.isSelected {
                emitObjectEvent(path: path(c.id), member: "StateChanged", detail: "selected", detail1: 1, detail2: 0, data: .int32(0))
            }
        }
    }

    private func tree(for entry: WindowEntry) -> PlatformAccessibilityElement? {
        guard let w = entry.window, let owner = w.atspiOwner else { return nil }
        if entry.dirty || entry.tree == nil {
            entry.tree = owner.platformAccessibility.accessibilityTree()
            entry.dirty = false
        }
        return entry.tree
    }

    /// Every window's snapshot is taken fresh for each request: AT-SPI clients ask one
    /// attribute at a time, and the tree is small.
    private func invalidateAll() { for e in windows { e.dirty = true } }

    private struct Located {
        let entry: WindowEntry
        let tree: PlatformAccessibilityElement
        let element: PlatformAccessibilityElement
        var isWindow: Bool { tree.id == element.id }
    }

    private func locate(id: Int) -> Located? {
        for entry in windows {
            guard let tree = tree(for: entry), let e = tree.element(withID: id) else { continue }
            return Located(entry: entry, tree: tree, element: e)
        }
        return nil
    }

    private var visibleWindows: [WindowEntry] { windows.filter { $0.window?.atspiIsVisible == true } }

    private func path(_ id: Int) -> String { AtspiBridge.elementPathPrefix + String(id) }

    // MARK: Requests

    /// Handles a method call for one of our objects; false lets libdbus answer.
    private func handle(_ message: OpaquePointer) -> Bool {
        guard dbus_message_get_type(message) == DBUS_MESSAGE_TYPE_METHOD_CALL,
              let pathC = dbus_message_get_path(message), let ifaceC = dbus_message_get_interface(message), let memberC = dbus_message_get_member(message) else { return false }
        let path = String(cString: pathC), iface = String(cString: ifaceC), member = String(cString: memberC)
        guard path.hasPrefix(AtspiBridge.elementPathPrefix) else { return false }
        invalidateAll()
        if trace { NSView._trace("atspi: \(iface).\(member) on \(path)") }
        let target: Target
        if path == AtspiBridge.rootPath {
            target = .application
        } else if let id = Int(path.dropFirst(AtspiBridge.elementPathPrefix.count)), let l = locate(id: id) {
            target = .element(l)
        } else {
            reply(message, error: "org.freedesktop.DBus.Error.UnknownObject", "no such accessible: \(path)")
            return true
        }
        var args = DBusMessageIter()
        let hasArgs = dbus_message_iter_init(message, &args) != 0
        var reader = DBus.Reader(iter: args, valid: hasArgs)
        switch iface {
        case "org.freedesktop.DBus.Introspectable" where member == "Introspect":
            reply(message) { DBus.appendString(&$0, self.introspection(for: target)) }
        case "org.freedesktop.DBus.Properties":
            handleProperties(message, member: member, target: target, reader: &reader)
        case "org.a11y.atspi.Accessible":
            handleAccessible(message, member: member, target: target, reader: &reader)
        case "org.a11y.atspi.Application":
            if member == "GetLocale" { reply(message) { DBus.appendString(&$0, Locale.current.identifier) } }
            else { reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member) }
        case "org.a11y.atspi.Component":
            handleComponent(message, member: member, target: target, reader: &reader)
        case "org.a11y.atspi.Action":
            handleAction(message, member: member, target: target, reader: &reader)
        case "org.a11y.atspi.Text":
            handleText(message, member: member, target: target, reader: &reader)
        case "org.a11y.atspi.EditableText":
            if case .element(let l) = target, member == "SetTextContents", let text = reader.string() {
                let ok = l.element.isSettable && (l.entry.window?.atspiOwner?.platformAccessibility.accessibilitySetValue(.string(text), on: l.element.id) ?? false)
                reply(message) { DBus.appendBool(&$0, ok) }
            } else {
                reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member)
            }
        default:
            reply(message, error: "org.freedesktop.DBus.Error.UnknownInterface", iface)
        }
        return true
    }

    private enum Target {
        case application
        case element(Located)
    }

    private func interfaces(for target: Target) -> [String] {
        switch target {
        case .application: return ["org.a11y.atspi.Accessible", "org.a11y.atspi.Application"]
        case .element(let l):
            var i = ["org.a11y.atspi.Accessible", "org.a11y.atspi.Component"]
            if !l.element.actions.isEmpty { i.append("org.a11y.atspi.Action") }
            if l.element.minValue != nil || l.element.role == "AXSlider" || l.element.role == "AXScrollBar" { i.append("org.a11y.atspi.Value") }
            if ["AXTextField", "AXTextArea", "AXStaticText"].contains(l.element.role) {
                i.append("org.a11y.atspi.Text")
                if l.element.isSettable { i.append("org.a11y.atspi.EditableText") }
            }
            return i
        }
    }

    private func introspection(for target: Target) -> String {
        var xml = "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\" \"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n<node>\n"
        xml += "  <interface name=\"org.freedesktop.DBus.Introspectable\"><method name=\"Introspect\"><arg direction=\"out\" type=\"s\"/></method></interface>\n"
        xml += "  <interface name=\"org.freedesktop.DBus.Properties\"><method name=\"Get\"><arg direction=\"in\" type=\"s\"/><arg direction=\"in\" type=\"s\"/><arg direction=\"out\" type=\"v\"/></method><method name=\"Set\"><arg direction=\"in\" type=\"s\"/><arg direction=\"in\" type=\"s\"/><arg direction=\"in\" type=\"v\"/></method><method name=\"GetAll\"><arg direction=\"in\" type=\"s\"/><arg direction=\"out\" type=\"a{sv}\"/></method></interface>\n"
        for i in interfaces(for: target) { xml += "  <interface name=\"\(i)\"/>\n" }
        switch target {
        case .application: for e in visibleWindows { if let t = tree(for: e) { xml += "  <node name=\"\(t.id)\"/>\n" } }
        case .element(let l): for c in l.element.children { xml += "  <node name=\"\(c.id)\"/>\n" }
        }
        xml += "</node>\n"
        return xml
    }

    // MARK: Accessible

    private func children(of target: Target) -> [PlatformAccessibilityElement] {
        switch target {
        case .application: return visibleWindows.compactMap { tree(for: $0) }
        case .element(let l): return l.element.children
        }
    }

    private func parentReference(of target: Target) -> (String, String) {
        switch target {
        case .application: return desktop.map { ($0.name, $0.path) } ?? (uniqueName, AtspiBridge.rootPath)
        case .element(let l):
            if l.isWindow { return (uniqueName, AtspiBridge.rootPath) }
            if let p = l.tree.parent(of: l.element.id) { return (uniqueName, path(p.id)) }
            return (uniqueName, AtspiBridge.rootPath)
        }
    }

    private func indexInParent(of target: Target) -> Int32 {
        switch target {
        case .application: return -1
        case .element(let l):
            if l.isWindow { return Int32(visibleWindows.firstIndex { $0 === l.entry } ?? -1) }
            guard let p = l.tree.parent(of: l.element.id) else { return -1 }
            return Int32(p.children.firstIndex { $0.id == l.element.id } ?? -1)
        }
    }

    private func handleAccessible(_ message: OpaquePointer, member: String, target: Target, reader: inout DBus.Reader) {
        switch member {
        case "GetChildAtIndex":
            let index = Int(reader.int32() ?? -1)
            let kids = children(of: target)
            reply(message) { iter in
                if kids.indices.contains(index) { DBus.appendObjectReference(&iter, name: self.uniqueName, path: self.path(kids[index].id)) }
                else { DBus.appendObjectReference(&iter, name: "", path: "/org/a11y/atspi/null") }
            }
        case "GetChildren":
            let kids = children(of: target)
            reply(message) { iter in
                DBus.appendArray(&iter, signature: "(so)") { a in
                    for k in kids { DBus.appendObjectReference(&a, name: self.uniqueName, path: self.path(k.id)) }
                }
            }
        case "GetIndexInParent":
            let i = indexInParent(of: target)
            reply(message) { DBus.appendInt32(&$0, i) }
        case "GetRelationSet":
            reply(message) { iter in DBus.appendArray(&iter, signature: "(ua(so))") { _ in } }
        case "GetRole":
            let r = role(for: target)
            reply(message) { DBus.appendUInt32(&$0, r.number) }
        case "GetRoleName", "GetLocalizedRoleName":
            let r = role(for: target)
            reply(message) { DBus.appendString(&$0, r.name) }
        case "GetState":
            let s = states(for: target)
            reply(message) { iter in DBus.appendArray(&iter, signature: "u") { a in DBus.appendUInt32(&a, s.0); DBus.appendUInt32(&a, s.1) } }
        case "GetAttributes":
            reply(message) { iter in
                DBus.appendArray(&iter, signature: "{ss}") { a in
                    DBus.appendDictEntry(&a, "toolkit", "AppKitCross")
                    if case .element(let l) = target {
                        DBus.appendDictEntry(&a, "role", l.element.role)
                        if let s = l.element.subrole { DBus.appendDictEntry(&a, "subrole", s) }
                        if let p = l.element.placeholder { DBus.appendDictEntry(&a, "placeholder-text", p) }
                    }
                }
            }
        case "GetApplication":
            reply(message) { DBus.appendObjectReference(&$0, name: self.uniqueName, path: AtspiBridge.rootPath) }
        case "GetInterfaces":
            let i = interfaces(for: target)
            reply(message) { iter in DBus.appendArray(&iter, signature: "s") { a in for s in i { DBus.appendString(&a, s) } } }
        default:
            reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member)
        }
    }

    // MARK: Properties

    private func handleProperties(_ message: OpaquePointer, member: String, target: Target, reader: inout DBus.Reader) {
        switch member {
        case "Get":
            guard let iface = reader.string(), let prop = reader.string() else { reply(message, error: "org.freedesktop.DBus.Error.InvalidArgs", "Get"); return }
            guard let value = property(iface, prop, target) else {
                reply(message, error: "org.freedesktop.DBus.Error.UnknownProperty", "\(iface).\(prop)")
                return
            }
            reply(message) { DBus.appendVariant(&$0, value) }
        case "GetAll":
            let iface = reader.string() ?? ""
            let names = propertyNames(iface, target)
            reply(message) { iter in
                DBus.appendArray(&iter, signature: "{sv}") { a in
                    for n in names { if let v = self.property(iface, n, target) { DBus.appendDictEntry(&a, n, v) } }
                }
            }
        case "Set":
            guard let iface = reader.string(), let prop = reader.string(), let value = reader.variant() else { reply(message, error: "org.freedesktop.DBus.Error.InvalidArgs", "Set"); return }
            if iface == "org.a11y.atspi.Value", prop == "CurrentValue", case .element(let l) = target, let d = value.doubleValue {
                _ = l.entry.window?.atspiOwner?.platformAccessibility.accessibilitySetValue(.number(d), on: l.element.id)
                reply(message) { _ in }
            } else if iface == "org.a11y.atspi.Application", prop == "Id" {
                reply(message) { _ in }
            } else {
                reply(message, error: "org.freedesktop.DBus.Error.PropertyReadOnly", "\(iface).\(prop)")
            }
        default:
            reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member)
        }
    }

    private func propertyNames(_ iface: String, _ target: Target) -> [String] {
        switch iface {
        case "org.a11y.atspi.Accessible": return ["Name", "Description", "Parent", "ChildCount", "Locale", "AccessibleId"]
        case "org.a11y.atspi.Application": return ["ToolkitName", "Version", "AtspiVersion", "Id"]
        case "org.a11y.atspi.Action": return ["NActions"]
        case "org.a11y.atspi.Value": return ["MinimumValue", "MaximumValue", "MinimumIncrement", "CurrentValue"]
        case "org.a11y.atspi.Text": return ["CharacterCount", "CaretOffset"]
        default: return []
        }
    }

    private func property(_ iface: String, _ prop: String, _ target: Target) -> DBus.Value? {
        switch (iface, prop) {
        case ("org.a11y.atspi.Accessible", "Name"):
            switch target {
            case .application: return .string(NSApplication.shared.accessibilityTitle() ?? ProcessInfo.processInfo.processName)
            case .element(let l): return .string(AtspiBridge.name(for: l.element) ?? "")
            }
        case ("org.a11y.atspi.Accessible", "Description"):
            if case .element(let l) = target { return .string(l.element.help ?? "") }
            return .string("")
        case ("org.a11y.atspi.Accessible", "Parent"):
            let p = parentReference(of: target)
            return .objectReference(p.0, p.1)
        case ("org.a11y.atspi.Accessible", "ChildCount"): return .int32(Int32(children(of: target).count))
        case ("org.a11y.atspi.Accessible", "Locale"): return .string(Locale.current.identifier)
        case ("org.a11y.atspi.Accessible", "AccessibleId"):
            if case .element(let l) = target { return .string(l.element.identifier ?? "") }
            return .string(Bundle.main.bundleIdentifier ?? "")
        case ("org.a11y.atspi.Application", "ToolkitName"): return .string("AppKitCross")
        case ("org.a11y.atspi.Application", "Version"): return .string("1.0")
        case ("org.a11y.atspi.Application", "AtspiVersion"): return .string("2.1")
        case ("org.a11y.atspi.Application", "Id"): return .int32(0)
        case ("org.a11y.atspi.Action", "NActions"):
            if case .element(let l) = target { return .int32(Int32(l.element.actions.count)) }
            return .int32(0)
        case ("org.a11y.atspi.Value", "MinimumValue"):
            if case .element(let l) = target { return .double(l.element.minValue ?? 0) }
        case ("org.a11y.atspi.Value", "MaximumValue"):
            if case .element(let l) = target { return .double(l.element.maxValue ?? 1) }
        case ("org.a11y.atspi.Value", "MinimumIncrement"):
            if case .element(let l) = target { return .double(((l.element.maxValue ?? 1) - (l.element.minValue ?? 0)) / 100) }
        case ("org.a11y.atspi.Value", "CurrentValue"):
            if case .element(let l) = target { return .double(l.element.value?.doubleValue ?? 0) }
        case ("org.a11y.atspi.Text", "CharacterCount"):
            if case .element(let l) = target { return .int32(Int32((l.element.value?.stringValue ?? "").utf16.count)) }
        case ("org.a11y.atspi.Text", "CaretOffset"):
            if case .element(let l) = target { return .int32(Int32(l.element.selectedTextRange.map { $0.location + $0.length } ?? 0)) }
        default: break
        }
        return nil
    }

    // MARK: Component

    private func extents(_ e: PlatformAccessibilityElement, coordinateType: UInt32, in tree: PlatformAccessibilityElement) -> (Int32, Int32, Int32, Int32) {
        let r = screenPixels(e.frame)
        guard coordinateType != 0 else { return r }
        // 1: window-relative; 2: parent-relative.
        let origin = coordinateType == 1 ? screenPixels(tree.frame) : screenPixels(tree.parent(of: e.id)?.frame ?? tree.frame)
        return (r.0 - origin.0, r.1 - origin.1, r.2, r.3)
    }

    private func handleComponent(_ message: OpaquePointer, member: String, target: Target, reader: inout DBus.Reader) {
        guard case .element(let l) = target else { reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member); return }
        switch member {
        case "Contains":
            let x = reader.int32() ?? 0, y = reader.int32() ?? 0, ct = reader.uint32() ?? 0
            let r = extents(l.element, coordinateType: ct, in: l.tree)
            let inside = x >= r.0 && x < r.0 + r.2 && y >= r.1 && y < r.1 + r.3
            reply(message) { DBus.appendBool(&$0, inside) }
        case "GetAccessibleAtPoint":
            let x = reader.int32() ?? 0, y = reader.int32() ?? 0, ct = reader.uint32() ?? 0
            func hit(_ e: PlatformAccessibilityElement) -> PlatformAccessibilityElement? {
                for c in e.children.reversed() { if let h = hit(c) { return h } }
                let r = extents(e, coordinateType: ct, in: l.tree)
                return x >= r.0 && x < r.0 + r.2 && y >= r.1 && y < r.1 + r.3 ? e : nil
            }
            let h = hit(l.element)
            reply(message) { iter in
                if let h { DBus.appendObjectReference(&iter, name: self.uniqueName, path: self.path(h.id)) }
                else { DBus.appendObjectReference(&iter, name: "", path: "/org/a11y/atspi/null") }
            }
        case "GetExtents":
            let ct = reader.uint32() ?? 0
            let r = extents(l.element, coordinateType: ct, in: l.tree)
            reply(message) { iter in DBus.appendStruct(&iter) { s in DBus.appendInt32(&s, r.0); DBus.appendInt32(&s, r.1); DBus.appendInt32(&s, r.2); DBus.appendInt32(&s, r.3) } }
        case "GetPosition":
            let ct = reader.uint32() ?? 0
            let r = extents(l.element, coordinateType: ct, in: l.tree)
            reply(message) { iter in DBus.appendInt32(&iter, r.0); DBus.appendInt32(&iter, r.1) }
        case "GetSize":
            let r = extents(l.element, coordinateType: 0, in: l.tree)
            reply(message) { iter in DBus.appendInt32(&iter, r.2); DBus.appendInt32(&iter, r.3) }
        case "GetLayer":
            reply(message) { DBus.appendUInt32(&$0, l.isWindow ? 7 : 3) }      // ATSPI_LAYER_WINDOW / ATSPI_LAYER_WIDGET
        case "GetMDIZOrder":
            reply(message) { DBus.appendInt16(&$0, 0) }
        case "GrabFocus":
            let ok = l.entry.window?.atspiOwner?.platformAccessibility.accessibilityFocus(l.element.id) ?? false
            reply(message) { DBus.appendBool(&$0, ok) }
        case "GetAlpha":
            reply(message) { DBus.appendDouble(&$0, 1) }
        case "ScrollTo", "ScrollToPoint":
            reply(message) { DBus.appendBool(&$0, false) }
        default:
            reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member)
        }
    }

    // MARK: Action

    private static func actionName(_ a: PlatformAccessibilityAction) -> String {
        switch a {
        case .press: return "press"
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .showMenu: return "showMenu"
        case .confirm: return "confirm"
        case .cancel: return "cancel"
        case .pick: return "pick"
        case .raise: return "raise"
        case .expand: return "expand"
        case .collapse: return "collapse"
        }
    }

    private func handleAction(_ message: OpaquePointer, member: String, target: Target, reader: inout DBus.Reader) {
        guard case .element(let l) = target else { reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member); return }
        let actions = l.element.actions
        switch member {
        case "GetName", "GetLocalizedName", "GetDescription":
            let i = Int(reader.int32() ?? -1)
            let name = actions.indices.contains(i) ? AtspiBridge.actionName(actions[i]) : ""
            reply(message) { DBus.appendString(&$0, name) }
        case "GetKeyBinding":
            reply(message) { DBus.appendString(&$0, "") }
        case "GetActions":
            reply(message) { iter in
                DBus.appendArray(&iter, signature: "(sss)") { a in
                    for act in actions { DBus.appendStruct(&a) { s in let n = AtspiBridge.actionName(act); DBus.appendString(&s, n); DBus.appendString(&s, n); DBus.appendString(&s, "") } }
                }
            }
        case "DoAction":
            let i = Int(reader.int32() ?? -1)
            var ok = false
            if actions.indices.contains(i), let provider = l.entry.window?.atspiOwner?.platformAccessibility {
                ok = provider.accessibilityPerform(actions[i], on: l.element.id)
            }
            reply(message) { DBus.appendBool(&$0, ok) }
        default:
            reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member)
        }
    }

    // MARK: Text

    private func handleText(_ message: OpaquePointer, member: String, target: Target, reader: inout DBus.Reader) {
        guard case .element(let l) = target else { reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member); return }
        let text = Array((l.element.value?.stringValue ?? "").utf16)
        func substring(_ start: Int, _ end: Int) -> String {
            let s = max(0, min(start, text.count)), e = end < 0 ? text.count : max(s, min(end, text.count))
            return String(decoding: text[s..<e], as: UTF16.self)
        }
        switch member {
        case "GetText":
            let start = Int(reader.int32() ?? 0), end = Int(reader.int32() ?? -1)
            reply(message) { DBus.appendString(&$0, substring(start, end)) }
        case "GetNSelections":
            let n: Int32 = (l.element.selectedTextRange?.length ?? 0) > 0 ? 1 : 0
            reply(message) { DBus.appendInt32(&$0, n) }
        case "GetSelection":
            let r = l.element.selectedTextRange ?? NSRange(location: 0, length: 0)
            reply(message) { iter in DBus.appendInt32(&iter, Int32(r.location)); DBus.appendInt32(&iter, Int32(r.location + r.length)) }
        case "GetCharacterAtOffset":
            let i = Int(reader.int32() ?? 0)
            reply(message) { DBus.appendInt32(&$0, text.indices.contains(i) ? Int32(text[i]) : 0) }
        case "GetStringAtOffset", "GetTextAtOffset", "GetTextAfterOffset", "GetTextBeforeOffset":
            // Granularity is ignored: the whole text is one unit.
            reply(message) { iter in DBus.appendString(&iter, substring(0, -1)); DBus.appendInt32(&iter, 0); DBus.appendInt32(&iter, Int32(text.count)) }
        case "SetCaretOffset", "SetSelection", "AddSelection", "RemoveSelection":
            reply(message) { DBus.appendBool(&$0, false) }
        case "GetCharacterExtents", "GetRangeExtents":
            let r = extents(l.element, coordinateType: 0, in: l.tree)
            reply(message) { iter in DBus.appendInt32(&iter, r.0); DBus.appendInt32(&iter, r.1); DBus.appendInt32(&iter, r.2); DBus.appendInt32(&iter, r.3) }
        case "GetAttributes", "GetDefaultAttributes", "GetAttributeRun":
            reply(message) { iter in DBus.appendArray(&iter, signature: "{ss}") { _ in }; if member == "GetAttributes" || member == "GetAttributeRun" { DBus.appendInt32(&iter, 0); DBus.appendInt32(&iter, Int32(text.count)) } }
        default:
            reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member)
        }
    }

    // MARK: Roles and states

    /// AppKit roles → AT-SPI roles (the AtspiRole enumeration's values and names).
    static func role(for role: String, subrole: String?) -> (number: UInt32, name: String) {
        switch role {
        case "AXApplication": return (75, "application")
        case "AXWindow": return subrole == "AXDialog" ? (16, "dialog") : (23, "frame")
        case "AXSheet": return (16, "dialog")
        case "AXPopover": return (69, "window")
        case "AXButton", "AXMenuButton": return (43, "push button")
        case "AXCheckBox": return subrole == "AXSwitch" ? (62, "toggle button") : (7, "check box")
        case "AXRadioButton": return subrole == "AXTabButton" ? (37, "page tab") : (44, "radio button")
        case "AXStaticText": return (29, "label")
        case "AXTextField", "AXTextArea": return (61, "text")
        case "AXSlider": return (51, "slider")
        case "AXPopUpButton", "AXComboBox": return (11, "combo box")
        case "AXImage": return (27, "image")
        case "AXTable": return (55, "table")
        case "AXRow": return (90, "table row")
        case "AXCell": return (56, "table cell")
        case "AXList": return (31, "list")
        case "AXScrollArea": return (49, "scroll pane")
        case "AXScrollBar": return (48, "scroll bar")
        case "AXGroup", "AXRadioGroup": return (39, "panel")
        case "AXSplitGroup": return (53, "split pane")
        case "AXTabGroup": return (38, "page tab list")
        case "AXMenu", "AXMenuBar": return role == "AXMenuBar" ? (34, "menu bar") : (33, "menu")
        case "AXMenuItem", "AXMenuBarItem": return (35, "menu item")
        case "AXLink": return (88, "link")
        case "AXProgressIndicator": return (42, "progress bar")
        case "AXIncrementor": return (52, "spin button")
        case "AXToolbar": return (63, "tool bar")
        case "AXSplitter": return (50, "separator")
        default: return (67, "unknown")
        }
    }

    private func role(for target: Target) -> (number: UInt32, name: String) {
        switch target {
        case .application: return AtspiBridge.role(for: "AXApplication", subrole: nil)
        case .element(let l): return AtspiBridge.role(for: l.element.role, subrole: l.element.subrole)
        }
    }

    /// The AtspiStateType bits as the two uint32 words of a state set.
    private func states(for target: Target) -> (UInt32, UInt32) {
        var bits: [Int] = []
        switch target {
        case .application:
            bits = [8, 24, 30, 25]      // enabled, sensitive, visible, showing
            if NSApplication.shared.isActive { bits.append(1) }
        case .element(let l):
            let e = l.element
            bits = [30, 25]             // visible, showing
            if e.isEnabled { bits += [8, 24] }
            if e.isFocusable { bits.append(11) }
            if e.isFocused { bits.append(12) }
            if e.isSettable && ["AXTextField", "AXTextArea"].contains(e.role) { bits.append(7) } else if ["AXTextField", "AXTextArea", "AXStaticText"].contains(e.role) { bits.append(43) }
            let isTab = e.subrole == "AXTabButton"
            if e.role == "AXRow" || e.role == "AXCell" || isTab { bits.append(22); if e.isSelected { bits.append(23) } }
            if (e.role == "AXCheckBox" || e.role == "AXRadioButton") && !isTab { bits.append(41); if (e.value?.doubleValue ?? 0) != 0 { bits.append(4) } }
            if e.isMultiline { bits.append(17) } else if e.role == "AXTextField" { bits.append(26) }
            if e.allowsMultipleSelection { bits.append(18) }
            if let expanded = e.isExpanded { bits.append(9); bits.append(expanded ? 10 : 5) }
            if l.isWindow { bits.append(21); if l.entry.window?.atspiIsKey == true { bits.append(1) } }
        }
        var w0: UInt32 = 0, w1: UInt32 = 0
        for b in bits { if b < 32 { w0 |= 1 << UInt32(b) } else { w1 |= 1 << UInt32(b - 32) } }
        return (w0, w1)
    }

    /// The AT-SPI name: the label, else the title, else a static text's value.
    static func name(for e: PlatformAccessibilityElement) -> String? {
        if let l = e.label, !l.isEmpty { return l }
        if let t = e.title, !t.isEmpty { return t }
        if e.role == "AXStaticText", case .string(let s)? = e.value { return s }
        return nil
    }

    // MARK: Replies and signals

    private func reply(_ message: OpaquePointer, _ body: (inout DBusMessageIter) -> Void) {
        guard let r = dbus_message_new_method_return(message) else { return }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(r, &iter)
        body(&iter)
        dbus_connection_send(connection, r, nil)
        dbus_message_unref(r)
    }

    private func reply(_ message: OpaquePointer, error: String, _ text: String) {
        guard let r = dbus_message_new_error(message, error, text) else { return }
        dbus_connection_send(connection, r, nil)
        dbus_message_unref(r)
    }

    private func emitObjectEvent(path: String, member: String, detail: String, detail1: Int32, detail2: Int32, data: DBus.Value) {
        emitSignal(path: path, interface: "org.a11y.atspi.Event.Object", member: member, detail: detail, detail1: detail1, detail2: detail2, data: data)
    }

    private func emitWindowEvent(_ member: String, _ window: AtspiWindow) {
        emitSignal(path: windowPath(window), interface: "org.a11y.atspi.Event.Window", member: member, detail: "", detail1: 0, detail2: 0, data: .int32(0))
    }

    private func emitChildrenChanged(parentPath: String, childPath: String, added: Bool) {
        emitSignal(path: parentPath, interface: "org.a11y.atspi.Event.Object", member: "ChildrenChanged", detail: added ? "add" : "remove", detail1: -1, detail2: 0, data: .objectReference(uniqueName, childPath))
    }

    /// An AT-SPI event: (s detail, i detail1, i detail2, v any_data, a{sv} properties).
    private func emitSignal(path: String, interface: String, member: String, detail: String, detail1: Int32, detail2: Int32, data: DBus.Value) {
        guard let s = dbus_message_new_signal(path, interface, member) else { return }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(s, &iter)
        DBus.appendString(&iter, detail)
        DBus.appendInt32(&iter, detail1)
        DBus.appendInt32(&iter, detail2)
        DBus.appendVariant(&iter, data)
        DBus.appendArray(&iter, signature: "{sv}") { a in DBus.appendDictEntry(&a, "sender", .objectReference(self.uniqueName, AtspiBridge.rootPath)) }
        dbus_connection_send(connection, s, nil)
        dbus_message_unref(s)
        dbus_connection_flush(connection)
        if trace { NSView._trace("atspi: \(interface.split(separator: ".").last ?? ""):\(member)(\(detail), \(detail1), \(detail2)) on \(path)") }
    }
}

// MARK: - libdbus helpers

/// Thin wrappers over the libdbus iterator API (the variadic append/get functions are not
/// callable from Swift). Type codes are the D-Bus characters as Int32.
enum DBus {
    static let string = Int32(UInt8(ascii: "s"))
    static let objectPath = Int32(UInt8(ascii: "o"))
    static let int32 = Int32(UInt8(ascii: "i"))
    static let uint32 = Int32(UInt8(ascii: "u"))
    static let int16 = Int32(UInt8(ascii: "n"))
    static let double = Int32(UInt8(ascii: "d"))
    static let boolean = Int32(UInt8(ascii: "b"))
    static let variant = Int32(UInt8(ascii: "v"))
    static let array = Int32(UInt8(ascii: "a"))
    static let structType = Int32(UInt8(ascii: "r"))
    static let dictEntry = Int32(UInt8(ascii: "e"))

    enum Value {
        case string(String)
        case int32(Int32)
        case uint32(UInt32)
        case double(Double)
        case boolean(Bool)
        case objectReference(String, String)

        var signature: String {
            switch self {
            case .string: return "s"
            case .int32: return "i"
            case .uint32: return "u"
            case .double: return "d"
            case .boolean: return "b"
            case .objectReference: return "(so)"
            }
        }
        var doubleValue: Double? {
            switch self {
            case .double(let d): return d
            case .int32(let i): return Double(i)
            case .uint32(let u): return Double(u)
            case .string(let s): return Double(s)
            case .boolean(let b): return b ? 1 : 0
            case .objectReference: return nil
            }
        }
    }

    static func appendString(_ iter: inout DBusMessageIter, _ s: String) {
        s.withCString { p in var q: UnsafePointer<CChar>? = p; dbus_message_iter_append_basic(&iter, string, &q) }
    }
    static func appendObjectPath(_ iter: inout DBusMessageIter, _ s: String) {
        s.withCString { p in var q: UnsafePointer<CChar>? = p; dbus_message_iter_append_basic(&iter, objectPath, &q) }
    }
    static func appendInt32(_ iter: inout DBusMessageIter, _ v: Int32) { var x = v; dbus_message_iter_append_basic(&iter, int32, &x) }
    static func appendUInt32(_ iter: inout DBusMessageIter, _ v: UInt32) { var x = v; dbus_message_iter_append_basic(&iter, uint32, &x) }
    static func appendInt16(_ iter: inout DBusMessageIter, _ v: Int16) { var x = v; dbus_message_iter_append_basic(&iter, int16, &x) }
    static func appendDouble(_ iter: inout DBusMessageIter, _ v: Double) { var x = v; dbus_message_iter_append_basic(&iter, double, &x) }
    static func appendBool(_ iter: inout DBusMessageIter, _ v: Bool) { var x: dbus_bool_t = v ? 1 : 0; dbus_message_iter_append_basic(&iter, boolean, &x) }

    static func appendStruct(_ iter: inout DBusMessageIter, _ body: (inout DBusMessageIter) -> Void) {
        var sub = DBusMessageIter()
        dbus_message_iter_open_container(&iter, structType, nil, &sub)
        body(&sub)
        dbus_message_iter_close_container(&iter, &sub)
    }
    static func appendArray(_ iter: inout DBusMessageIter, signature: String, _ body: (inout DBusMessageIter) -> Void) {
        var sub = DBusMessageIter()
        signature.withCString { dbus_message_iter_open_container(&iter, array, $0, &sub) }
        body(&sub)
        dbus_message_iter_close_container(&iter, &sub)
    }
    static func appendVariant(_ iter: inout DBusMessageIter, _ value: Value) {
        var sub = DBusMessageIter()
        value.signature.withCString { dbus_message_iter_open_container(&iter, variant, $0, &sub) }
        append(&sub, value)
        dbus_message_iter_close_container(&iter, &sub)
    }
    static func append(_ iter: inout DBusMessageIter, _ value: Value) {
        switch value {
        case .string(let s): appendString(&iter, s)
        case .int32(let i): appendInt32(&iter, i)
        case .uint32(let u): appendUInt32(&iter, u)
        case .double(let d): appendDouble(&iter, d)
        case .boolean(let b): appendBool(&iter, b)
        case .objectReference(let name, let path): appendObjectReference(&iter, name: name, path: path)
        }
    }
    static func appendObjectReference(_ iter: inout DBusMessageIter, name: String, path: String) {
        appendStruct(&iter) { s in appendString(&s, name); appendObjectPath(&s, path) }
    }
    static func appendDictEntry(_ iter: inout DBusMessageIter, _ key: String, _ value: String) {
        var sub = DBusMessageIter()
        dbus_message_iter_open_container(&iter, dictEntry, nil, &sub)
        appendString(&sub, key)
        appendString(&sub, value)
        dbus_message_iter_close_container(&iter, &sub)
    }
    static func appendDictEntry(_ iter: inout DBusMessageIter, _ key: String, _ value: Value) {
        var sub = DBusMessageIter()
        dbus_message_iter_open_container(&iter, dictEntry, nil, &sub)
        appendString(&sub, key)
        appendVariant(&sub, value)
        dbus_message_iter_close_container(&iter, &sub)
    }

    /// Reads a message's arguments in order.
    struct Reader {
        var iter: DBusMessageIter
        var valid: Bool

        mutating func string() -> String? {
            guard valid, dbus_message_iter_get_arg_type(&iter) == DBus.string || dbus_message_iter_get_arg_type(&iter) == objectPath else { return nil }
            var p: UnsafePointer<CChar>? = nil
            dbus_message_iter_get_basic(&iter, &p)
            let s = p.map { String(cString: $0) }
            valid = dbus_message_iter_next(&iter) != 0
            return s
        }
        mutating func int32() -> Int32? {
            guard valid, dbus_message_iter_get_arg_type(&iter) == DBus.int32 else { return nil }
            var v: Int32 = 0
            dbus_message_iter_get_basic(&iter, &v)
            valid = dbus_message_iter_next(&iter) != 0
            return v
        }
        mutating func uint32() -> UInt32? {
            guard valid, dbus_message_iter_get_arg_type(&iter) == DBus.uint32 else { return nil }
            var v: UInt32 = 0
            dbus_message_iter_get_basic(&iter, &v)
            valid = dbus_message_iter_next(&iter) != 0
            return v
        }
        mutating func variant() -> Value? {
            guard valid, dbus_message_iter_get_arg_type(&iter) == DBus.variant else { return nil }
            var sub = DBusMessageIter()
            dbus_message_iter_recurse(&iter, &sub)
            let type = dbus_message_iter_get_arg_type(&sub)
            var result: Value? = nil
            if type == DBus.double { var d = 0.0; dbus_message_iter_get_basic(&sub, &d); result = .double(d) }
            else if type == DBus.int32 { var i: Int32 = 0; dbus_message_iter_get_basic(&sub, &i); result = .int32(i) }
            else if type == DBus.uint32 { var u: UInt32 = 0; dbus_message_iter_get_basic(&sub, &u); result = .uint32(u) }
            else if type == DBus.string { var p: UnsafePointer<CChar>? = nil; dbus_message_iter_get_basic(&sub, &p); result = p.map { .string(String(cString: $0)) } }
            else if type == DBus.boolean { var b: dbus_bool_t = 0; dbus_message_iter_get_basic(&sub, &b); result = .boolean(b != 0) }
            valid = dbus_message_iter_next(&iter) != 0
            return result
        }
    }

    /// Reads an (so) struct at the iterator.
    static func readObjectReference(_ iter: inout DBusMessageIter) -> (name: String, path: String)? {
        guard dbus_message_iter_get_arg_type(&iter) == structType else { return nil }
        var sub = DBusMessageIter()
        dbus_message_iter_recurse(&iter, &sub)
        var r = Reader(iter: sub, valid: true)
        guard let name = r.string(), let path = r.string() else { return nil }
        return (name, path)
    }
}
#endif
