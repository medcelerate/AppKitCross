// Status items on Linux desktops: the StatusNotifierItem protocol over D-Bus (ADR-0018).
//
// One private session-bus connection serves every NSStatusItem as an object
// /StatusNotifierItem (then /StatusNotifierItem2, ...) with the org.kde.StatusNotifierItem
// interface (properties through org.freedesktop.DBus.Properties, Introspectable), and
// registers each with org.kde.StatusNotifierWatcher by object path. Hosts (KDE's
// system tray, waybar, GNOME's AppIndicator extension, ...) show the IconPixmap with
// the ToolTip and call Activate / SecondaryActivate / ContextMenu with a position in
// screen pixels; those become primary and secondary clicks for the owner, which opens
// the package's own menu window there. There is no com.canonical.dbusmenu: `Menu` is
// the conventional "/NO_DBUSMENU" path, so hosts that only open dbusmenus from a right
// click (GNOME's extension) show nothing there; the others call ContextMenu.
// The connection is pumped from the backend's poll loop like the AT-SPI bridge.

#if os(Linux)
import Foundation
import Glibc
import CDBus

@MainActor
final class LinuxStatusNotifierHost: PlatformStatusItemHost {
    static let interface = "org.kde.StatusNotifierItem"
    static let watcherName = "org.kde.StatusNotifierWatcher"
    static let watcherPath = "/StatusNotifierWatcher"

    private let connection: OpaquePointer                   // DBusConnection*
    private(set) var uniqueName = ""
    private(set) var fileDescriptor: Int32 = -1
    private(set) var items: [LinuxStatusNotifierItem] = []
    private var nextIndex = 1
    /// Screen pixels (root window coordinates) → AppKit screen point; the backend knows the scale and height.
    private let screenPoint: (Int32, Int32) -> NSPoint
    private var filterInstalled = false
    private var trace: Bool { NSView._traceInvalidation }
    var thickness: CGFloat { 22 }

    /// Connects to the session bus; nil without one (APPKITWIN_STATUS_NOTIFIER=0 disables).
    static func connect(screenPoint: @escaping (Int32, Int32) -> NSPoint) -> LinuxStatusNotifierHost? {
        if ProcessInfo.processInfo.environment["APPKITWIN_STATUS_NOTIFIER"] == "0" { return nil }
        var err = DBusError()
        dbus_error_init(&err)
        guard let conn = dbus_bus_get_private(DBUS_BUS_SESSION, &err) else {
            if NSView._traceInvalidation { NSView._trace("status notifier: no session bus: \(err.message.map { String(cString: $0) } ?? "")") }
            dbus_error_free(&err)
            return nil
        }
        dbus_connection_set_exit_on_disconnect(conn, 0)
        let host = LinuxStatusNotifierHost(connection: conn, screenPoint: screenPoint)
        host.start()
        return host
    }

    private init(connection: OpaquePointer, screenPoint: @escaping (Int32, Int32) -> NSPoint) {
        self.connection = connection
        self.screenPoint = screenPoint
    }

    private func start() {
        if let n = dbus_bus_get_unique_name(connection) { uniqueName = String(cString: n) }
        var fd: Int32 = -1
        if dbus_connection_get_unix_fd(connection, &fd) != 0 { fileDescriptor = fd }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if dbus_connection_add_filter(connection, { _, message, context in
            MainActor.assumeIsolated {
                guard let message, let context else { return DBUS_HANDLER_RESULT_NOT_YET_HANDLED }
                let host = Unmanaged<LinuxStatusNotifierHost>.fromOpaque(context).takeUnretainedValue()
                return host.handle(message) ? DBUS_HANDLER_RESULT_HANDLED : DBUS_HANDLER_RESULT_NOT_YET_HANDLED
            }
        }, context, nil) != 0 {
            filterInstalled = true
        }
        // A watcher that appears later (the tray starts after the application) gets the items then.
        var err = DBusError()
        dbus_error_init(&err)
        dbus_bus_add_match(connection, "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='\(LinuxStatusNotifierHost.watcherName)'", &err)
        dbus_error_free(&err)
        if trace { NSView._trace("status notifier: connected as \(uniqueName)") }
    }

    /// Pumps the connection: after poll() reported the descriptor readable, and once per
    /// loop iteration regardless (libdbus buffers).
    func dispatch() {
        while dbus_connection_read_write_dispatch(connection, 0) != 0 && dbus_connection_get_dispatch_status(connection) == DBUS_DISPATCH_DATA_REMAINS {}
    }

    func makeStatusItem(owner: PlatformStatusItemOwner) -> PlatformStatusItem {
        let path = nextIndex == 1 ? "/StatusNotifierItem" : "/StatusNotifierItem\(nextIndex)"
        nextIndex += 1
        let item = LinuxStatusNotifierItem(host: self, path: path, owner: owner)
        items.append(item)
        register(item)
        return item
    }

    fileprivate func forget(_ item: LinuxStatusNotifierItem) { items.removeAll { $0 === item } }

    /// org.kde.StatusNotifierWatcher.RegisterStatusNotifierItem with the object path: the
    /// watcher pairs it with this connection's unique name.
    private func register(_ item: LinuxStatusNotifierItem) {
        guard let msg = dbus_message_new_method_call(LinuxStatusNotifierHost.watcherName, LinuxStatusNotifierHost.watcherPath, LinuxStatusNotifierHost.watcherName, "RegisterStatusNotifierItem") else { return }
        defer { dbus_message_unref(msg) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(msg, &iter)
        DBus.appendString(&iter, item.path)
        var err = DBusError()
        dbus_error_init(&err)
        if let reply = dbus_connection_send_with_reply_and_block(connection, msg, 2000, &err) {
            dbus_message_unref(reply)
            item.registered = true
            if trace { NSView._trace("status notifier: registered \(item.path) with the watcher") }
        } else {
            if trace { NSView._trace("status notifier: no watcher for \(item.path): \(err.message.map { String(cString: $0) } ?? "")") }
            dbus_error_free(&err)
        }
    }

    // MARK: Messages

    private func handle(_ message: OpaquePointer) -> Bool {
        let type = dbus_message_get_type(message)
        if type == DBUS_MESSAGE_TYPE_SIGNAL {
            if let member = dbus_message_get_member(message), String(cString: member) == "NameOwnerChanged",
               dbus_message_has_interface(message, "org.freedesktop.DBus") != 0 {
                var args = DBusMessageIter()
                var r = DBus.Reader(iter: args, valid: dbus_message_iter_init(message, &args) != 0)
                r.iter = args
                if let name = r.string(), name == LinuxStatusNotifierHost.watcherName, let _ = r.string(), let newOwner = r.string(), !newOwner.isEmpty {
                    for i in items where !i.removed { register(i) }
                }
            }
            return false
        }
        guard type == DBUS_MESSAGE_TYPE_METHOD_CALL, let pathC = dbus_message_get_path(message), let memberC = dbus_message_get_member(message) else { return false }
        let path = String(cString: pathC), member = String(cString: memberC)
        let iface = dbus_message_get_interface(message).map { String(cString: $0) } ?? ""
        guard let item = items.first(where: { $0.path == path }) else { return false }
        var args = DBusMessageIter()
        let hasArgs = dbus_message_iter_init(message, &args) != 0
        var reader = DBus.Reader(iter: args, valid: hasArgs)
        if trace { NSView._trace("status notifier: \(iface).\(member) on \(path)") }
        switch iface {
        case "org.freedesktop.DBus.Introspectable" where member == "Introspect":
            reply(message) { DBus.appendString(&$0, LinuxStatusNotifierItem.introspection) }
        case "org.freedesktop.DBus.Properties":
            switch member {
            case "Get":
                guard let i = reader.string(), i == LinuxStatusNotifierHost.interface, let prop = reader.string() else { reply(message, error: "org.freedesktop.DBus.Error.UnknownProperty", member); return true }
                guard LinuxStatusNotifierItem.properties.contains(prop) else { reply(message, error: "org.freedesktop.DBus.Error.UnknownProperty", prop); return true }
                reply(message) { out in item.appendVariant(&out, prop) }
            case "GetAll":
                reply(message) { out in
                    DBus.appendArray(&out, signature: "{sv}") { arr in
                        for prop in LinuxStatusNotifierItem.properties {
                            var entry = DBusMessageIter()
                            dbus_message_iter_open_container(&arr, DBus.dictEntry, nil, &entry)
                            DBus.appendString(&entry, prop)
                            item.appendVariant(&entry, prop)
                            dbus_message_iter_close_container(&arr, &entry)
                        }
                    }
                }
            case "Set":
                reply(message, error: "org.freedesktop.DBus.Error.PropertyReadOnly", member)
            default:
                reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member)
            }
        case LinuxStatusNotifierHost.interface:
            let x = reader.int32() ?? 0, y = reader.int32() ?? 0
            switch member {
            case "Activate": item.owner?.platformStatusItemClicked(.primary, at: screenPoint(x, y))
            case "SecondaryActivate", "ContextMenu": item.owner?.platformStatusItemClicked(.secondary, at: screenPoint(x, y))
            case "Scroll", "ProvideXdgActivationToken": break
            default: reply(message, error: "org.freedesktop.DBus.Error.UnknownMethod", member); return true
            }
            reply(message) { _ in }
        default:
            return false
        }
        return true
    }
    private func reply(_ message: OpaquePointer, _ body: (inout DBusMessageIter) -> Void) {
        guard dbus_message_get_no_reply(message) == 0, let r = dbus_message_new_method_return(message) else { return }
        defer { dbus_message_unref(r) }
        var iter = DBusMessageIter()
        dbus_message_iter_init_append(r, &iter)
        body(&iter)
        dbus_connection_send(connection, r, nil)
    }

    private func reply(_ message: OpaquePointer, error: String, _ text: String) {
        guard dbus_message_get_no_reply(message) == 0, let r = dbus_message_new_error(message, error, text) else { return }
        dbus_connection_send(connection, r, nil)
        dbus_message_unref(r)
    }

    /// Emits one of the item's change signals (NewTitle, NewIcon, NewToolTip, NewStatus).
    fileprivate func emit(_ item: LinuxStatusNotifierItem, _ name: String, status: String? = nil) {
        guard let sig = dbus_message_new_signal(item.path, LinuxStatusNotifierHost.interface, name) else { return }
        defer { dbus_message_unref(sig) }
        if let status {
            var iter = DBusMessageIter()
            dbus_message_iter_init_append(sig, &iter)
            DBus.appendString(&iter, status)
        }
        dbus_connection_send(connection, sig, nil)
        dbus_connection_flush(connection)
    }
}

@MainActor
final class LinuxStatusNotifierItem: PlatformStatusItem {
    static let properties = ["Category", "Id", "Title", "Status", "WindowId", "IconName", "IconPixmap", "OverlayIconName", "OverlayIconPixmap",
                             "AttentionIconName", "AttentionIconPixmap", "AttentionMovieName", "ToolTip", "ItemIsMenu", "Menu"]
    static let introspection = """
    <!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    <node>
      <interface name="org.kde.StatusNotifierItem">
        <property name="Category" type="s" access="read"/>
        <property name="Id" type="s" access="read"/>
        <property name="Title" type="s" access="read"/>
        <property name="Status" type="s" access="read"/>
        <property name="WindowId" type="i" access="read"/>
        <property name="IconName" type="s" access="read"/>
        <property name="IconPixmap" type="a(iiay)" access="read"/>
        <property name="OverlayIconName" type="s" access="read"/>
        <property name="OverlayIconPixmap" type="a(iiay)" access="read"/>
        <property name="AttentionIconName" type="s" access="read"/>
        <property name="AttentionIconPixmap" type="a(iiay)" access="read"/>
        <property name="AttentionMovieName" type="s" access="read"/>
        <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
        <property name="ItemIsMenu" type="b" access="read"/>
        <property name="Menu" type="o" access="read"/>
        <method name="ContextMenu"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
        <method name="Activate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
        <method name="SecondaryActivate"><arg name="x" type="i" direction="in"/><arg name="y" type="i" direction="in"/></method>
        <method name="Scroll"><arg name="delta" type="i" direction="in"/><arg name="orientation" type="s" direction="in"/></method>
        <method name="ProvideXdgActivationToken"><arg name="token" type="s" direction="in"/></method>
        <signal name="NewTitle"/>
        <signal name="NewIcon"/>
        <signal name="NewAttentionIcon"/>
        <signal name="NewOverlayIcon"/>
        <signal name="NewToolTip"/>
        <signal name="NewStatus"><arg name="status" type="s"/></signal>
      </interface>
      <interface name="org.freedesktop.DBus.Properties">
        <method name="Get"><arg name="interface" type="s" direction="in"/><arg name="name" type="s" direction="in"/><arg name="value" type="v" direction="out"/></method>
        <method name="GetAll"><arg name="interface" type="s" direction="in"/><arg name="properties" type="a{sv}" direction="out"/></method>
      </interface>
      <interface name="org.freedesktop.DBus.Introspectable">
        <method name="Introspect"><arg name="data" type="s" direction="out"/></method>
      </interface>
    </node>
    """

    private unowned let host: LinuxStatusNotifierHost
    let path: String
    fileprivate weak var owner: PlatformStatusItemOwner?
    fileprivate var registered = false
    fileprivate var removed = false
    var title = "" { didSet { if title != oldValue { host.emit(self, "NewTitle"); host.emit(self, "NewToolTip") } } }
    var toolTip: String? { didSet { if toolTip != oldValue { host.emit(self, "NewToolTip") } } }
    var isVisible = true { didSet { if isVisible != oldValue { host.emit(self, "NewStatus", status: status) } } }
    var appearsDisabled = false
    /// ARGB32, network byte order, rows top-down (what IconPixmap carries).
    private(set) var pixmap: (width: Int32, height: Int32, bytes: [UInt8])?

    init(host: LinuxStatusNotifierHost, path: String, owner: PlatformStatusItemOwner) {
        self.host = host
        self.path = path
        self.owner = owner
    }

    var status: String { isVisible && !removed ? "Active" : "Passive" }
    static var applicationID: String { ProcessInfo.processInfo.processName }

    func setImage(_ image: CGImage?, scale: CGFloat) {
        if let image, image.width > 0, image.height > 0 {
            var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
            image.data.withUnsafeBytes { src in
                guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return }
                for y in 0..<image.height {
                    let row = base + y * image.bytesPerRow
                    for x in 0..<image.width {
                        let p = row + x * 4          // BGRA premultiplied (Cairo ARGB32 on little endian)
                        let o = (y * image.width + x) * 4
                        out[o] = p[3]; out[o + 1] = p[2]; out[o + 2] = p[1]; out[o + 3] = p[0]
                    }
                }
            }
            pixmap = (Int32(image.width), Int32(image.height), out)
        } else {
            pixmap = nil
        }
        host.emit(self, "NewIcon")
    }

    func remove() {
        guard !removed else { return }
        removed = true
        host.emit(self, "NewStatus", status: "Passive")
        host.forget(self)
    }

    // MARK: Marshalling

    private func appendPixmaps(_ iter: inout DBusMessageIter) {
        DBus.appendArray(&iter, signature: "(iiay)") { arr in
            guard let p = pixmap else { return }
            DBus.appendStruct(&arr) { s in
                DBus.appendInt32(&s, p.width)
                DBus.appendInt32(&s, p.height)
                var bytes = DBusMessageIter()
                dbus_message_iter_open_container(&s, DBus.array, "y", &bytes)
                p.bytes.withUnsafeBufferPointer { buf in
                    var ptr: UnsafePointer<UInt8>? = buf.baseAddress
                    dbus_message_iter_append_fixed_array(&bytes, Int32(UInt8(ascii: "y")), &ptr, Int32(buf.count))
                }
                dbus_message_iter_close_container(&s, &bytes)
            }
        }
    }

    /// Appends the property's value wrapped in a variant.
    func appendVariant(_ iter: inout DBusMessageIter, _ name: String) {
        func variant(_ signature: String, _ body: (inout DBusMessageIter) -> Void) {
            var sub = DBusMessageIter()
            signature.withCString { dbus_message_iter_open_container(&iter, DBus.variant, $0, &sub) }
            body(&sub)
            dbus_message_iter_close_container(&iter, &sub)
        }
        switch name {
        case "Category": variant("s") { DBus.appendString(&$0, "ApplicationStatus") }
        case "Id": variant("s") { DBus.appendString(&$0, LinuxStatusNotifierItem.applicationID) }
        case "Title": variant("s") { DBus.appendString(&$0, title.isEmpty ? LinuxStatusNotifierItem.applicationID : title) }
        case "Status": variant("s") { DBus.appendString(&$0, status) }
        case "WindowId": variant("i") { DBus.appendInt32(&$0, 0) }
        case "IconName", "OverlayIconName", "AttentionIconName", "AttentionMovieName": variant("s") { DBus.appendString(&$0, "") }
        case "IconPixmap": variant("a(iiay)") { appendPixmaps(&$0) }
        case "OverlayIconPixmap", "AttentionIconPixmap": variant("a(iiay)") { DBus.appendArray(&$0, signature: "(iiay)") { _ in } }
        case "ToolTip":
            variant("(sa(iiay)ss)") { v in
                DBus.appendStruct(&v) { s in
                    DBus.appendString(&s, "")
                    DBus.appendArray(&s, signature: "(iiay)") { _ in }
                    DBus.appendString(&s, toolTip ?? title)
                    DBus.appendString(&s, "")
                }
            }
        case "ItemIsMenu": variant("b") { DBus.appendBool(&$0, false) }
        case "Menu": variant("o") { DBus.appendObjectPath(&$0, "/NO_DBUSMENU") }
        default: variant("s") { DBus.appendString(&$0, "") }
        }
    }
}
#endif
