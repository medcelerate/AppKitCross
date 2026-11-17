// UserNotifications (ADR-0043): Windows toasts through the CWinAppServices shim. The app is
// registered under an AppUserModelID (its bundle identifier, else "AppKitCross.<exe>") the
// first time a notification is needed; toasts go out with that ID, a tag per request
// (hashed to Windows' 64-character limit) and one group for the app, so removal by
// identifier maps to ToastNotificationHistory.RemoveGroupedTagWithId.

#if os(Windows)
import Foundation
@_implementationOnly import CWinAppServices

final class WindowsToastNotifier: PlatformNotifier, @unchecked Sendable {
    static let group = "UserNotifications"

    private struct Shown {
        var identifier: String
        /// The text box of each text-input action, by action identifier.
        var inputs: [String: String]
    }

    private let identity: PlatformAppIdentity
    private let lock = NSLock()
    private var initResult: Int32?
    private var handler: (@Sendable (PlatformNotificationEvent) -> Void)?
    private var shown: [String: Shown] = [:]   // by tag

    init(identity: PlatformAppIdentity) {
        self.identity = identity
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    /// Registers the app and creates the notifier once; the HRESULT of that.
    private func start() -> Int32 {
        if let result = locked({ initResult }) { return result }
        let context = Unmanaged.passRetained(self).toOpaque()
        let activated: cwas_toast_activated_fn = { context, tag, arguments, inputs in
            guard let context, let tag else { return }
            let me = Unmanaged<WindowsToastNotifier>.fromOpaque(context).takeUnretainedValue()
            me.activated(tag: String(cString: tag), arguments: arguments.map { String(cString: $0) } ?? "",
                         inputs: WindowsToastNotifier.unpack(inputs))
        }
        let dismissed: cwas_toast_dismissed_fn = { context, tag, reason, _ in
            guard let context, let tag else { return }
            let me = Unmanaged<WindowsToastNotifier>.fromOpaque(context).takeUnretainedValue()
            me.dismissed(tag: String(cString: tag), reason: reason)
        }
        let result = cwas_toast_init(identity.identifier, identity.displayName, nil, activated, dismissed, context)
        if result < 0 {
            FileHandle.standardError.write(Data("UserNotifications: toast notifier for \(identity.identifier) unavailable (HRESULT 0x\(String(UInt32(bitPattern: result), radix: 16)))\n".utf8))
        }
        locked { initResult = result }
        return result
    }

    func authorization() -> PlatformAuthorization {
        guard start() >= 0 else { return .unavailable }
        switch cwas_toast_setting() {
        case 0: return .allowed
        case 1, 2, 3, 4: return .deniedBySettings
        default: return .unavailable
        }
    }

    func post(_ notification: PlatformNotification) throws {
        let hr = start()
        guard hr >= 0 else { throw NSError(domain: "UserNotifications.WindowsToast", code: Int(hr)) }
        let tag = ToastXML.tag(for: notification.identifier)
        var inputs: [String: String] = [:]
        for (i, action) in notification.actions.prefix(ToastXML.maximumActions).enumerated() where action.textInput != nil {
            inputs[action.identifier] = ToastXML.inputIdentifier(forActionAt: i)
        }
        locked { shown[tag] = Shown(identifier: notification.identifier, inputs: inputs) }
        var packed: [CChar] = []
        for id in inputs.values.sorted() { packed += id.utf8CString }
        packed.append(0)
        let xml = ToastXML.document(for: notification)
        let result = packed.withUnsafeBufferPointer { ids in
            cwas_toast_show(xml, tag, WindowsToastNotifier.group, notification.listOnly ? 1 : 0, inputs.isEmpty ? nil : ids.baseAddress)
        }
        guard result >= 0 else {
            locked { _ = shown.removeValue(forKey: tag) }
            throw NSError(domain: "UserNotifications.WindowsToast", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "The toast could not be shown (HRESULT 0x\(String(UInt32(bitPattern: result), radix: 16)))."])
        }
    }

    func remove(identifiers: [String]) {
        guard start() >= 0 else { return }
        for identifier in identifiers {
            let tag = ToastXML.tag(for: identifier)
            locked { _ = shown.removeValue(forKey: tag) }
            cwas_toast_remove(tag, WindowsToastNotifier.group)
        }
    }

    func removeAll() {
        guard start() >= 0 else { return }
        locked { shown.removeAll() }
        cwas_toast_clear()
    }

    /// Windows has no app badge for an unpackaged app; AppKit shows it on the taskbar button.
    func setBadgeCount(_ count: Int) -> Bool { false }

    func setEventHandler(_ handler: @escaping @Sendable (PlatformNotificationEvent) -> Void) {
        locked { self.handler = handler }
    }

    private func activated(tag: String, arguments: String, inputs: [String: String]) {
        let (entry, handler) = locked { (shown.removeValue(forKey: tag), self.handler) }
        let identifier = entry?.identifier ?? tag
        let action = arguments.isEmpty ? UNNotificationDefaultActionIdentifier : arguments
        let text = entry?.inputs[action].flatMap { inputs[$0] }
        handler?(.activated(identifier: identifier, actionIdentifier: action, userText: text))
    }

    private func dismissed(tag: String, reason: Int32) {
        let mapped: PlatformDismissReason = reason == 0 ? .user : reason == 2 ? .timedOut : .removed
        let (entry, handler) = locked { () -> (Shown?, (@Sendable (PlatformNotificationEvent) -> Void)?) in
            (mapped == .timedOut ? shown[tag] : shown.removeValue(forKey: tag), self.handler)
        }
        handler?(.dismissed(identifier: entry?.identifier ?? tag, reason: mapped))
    }

    /// NUL-separated id/value pairs ending with an empty string.
    static func unpack(_ pointer: UnsafePointer<CChar>?) -> [String: String] {
        guard var p = pointer else { return [:] }
        var result: [String: String] = [:]
        while p.pointee != 0 {
            let key = String(cString: p)
            p += strlen(p) + 1
            let value = String(cString: p)
            p += strlen(p) + 1
            result[key] = value
        }
        return result
    }
}
#endif
