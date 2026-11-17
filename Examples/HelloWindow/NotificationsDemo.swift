// Layout Demo tab "notifications" (ADR-0043): UserNotifications and ServiceManagement by
// hand. "Notify now" posts at once (the delegate shows it as a banner while the app is
// frontmost), "Notify in 10 s" schedules a time-interval trigger (switch to another app to
// see the background path), "Notify with actions" uses a category with a foreground button,
// a plain button and a text reply; every click, button and reply is shown below and traced
// to stderr as "notifications …". "Launch at login" registers SMAppService.mainApp (the Run
// key on Windows, an XDG autostart entry on Linux) and reads its status back.
//
// On macOS this tab uses Apple's frameworks, which need an app bundle: run unbundled, it says
// so instead of posting.

import AppKit
import Foundation
import ServiceManagement
import UserNotifications

final class NotificationsDemoViewController: NSViewController, NSSelectorHandling, UNUserNotificationCenterDelegate {
    let status = NSTextField(labelWithString: "")
    let response = NSTextField(labelWithString: "No response yet")
    let loginItem = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: Selector(("toggleLoginItem:")))
    static let categoryIdentifier = "hello.notifications.actions"

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Notify"
    }
    required init?(coder: NSCoder) { nil }

    /// Apple's UserNotifications refuses to work outside an app bundle; the port's does not care.
    private var available: Bool {
        #if canImport(ObjectiveC)
        return Bundle.main.bundleIdentifier != nil
        #else
        return true
        #endif
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 270))
        let buttons: [(String, Selector)] = [
            ("Request Permission", Selector(("requestPermission:"))), ("Notify now", Selector(("notifyNow:"))),
            ("Notify in 10 s", Selector(("notifyLater:"))), ("Notify with actions", Selector(("notifyWithActions:"))),
            ("Remove delivered", Selector(("removeDelivered:"))), ("Login Items Settings…", Selector(("openLoginItems:"))),
        ]
        for (i, (title, action)) in buttons.enumerated() {
            let b = NSButton(title: title, target: self, action: action)
            b.frame = NSRect(x: 16 + CGFloat(i % 2) * 200, y: 214 - CGFloat(i / 2) * 36, width: 190, height: 28)
            root.addSubview(b)
        }
        loginItem.target = self
        loginItem.frame = NSRect(x: 16, y: 94, width: 300, height: 22)
        root.addSubview(loginItem)
        status.frame = NSRect(x: 16, y: 56, width: 800, height: 18)
        status.textColor = .secondaryLabelColor
        root.addSubview(status)
        response.frame = NSRect(x: 16, y: 30, width: 800, height: 18)
        root.addSubview(response)
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard available else {
            status.stringValue = "UserNotifications needs an app bundle on macOS"
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "done", title: "Done", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze")
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Type a reply")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: NotificationsDemoViewController.categoryIdentifier, actions: [done, snooze, reply],
                                   intentIdentifiers: [], options: [.customDismissAction]),
        ])
        refresh()
    }

    private func trace(_ line: String) {
        FileHandle.standardError.write(Data("notifications \(line)\n".utf8))
    }

    private func refresh() {
        let service = SMAppService.mainApp
        let loginStatus = service.status
        loginItem.state = loginStatus == .enabled ? .on : .off
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let authorization = settings.authorizationStatus
            DispatchQueue.main.async {
                let text = "Authorization: \(Self.describe(authorization)) · login item: \(Self.describe(loginStatus))"
                self?.status.stringValue = text
                self?.trace(text)
            }
        }
    }

    private static func describe(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "not determined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        @unknown default: return "other"
        }
    }

    private static func describe(_ s: SMAppService.Status) -> String {
        switch s {
        case .notRegistered: return "not registered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requires approval"
        case .notFound: return "not found"
        @unknown default: return "other"
        }
    }

    private func post(_ identifier: String, title: String, body: String, after seconds: TimeInterval?, actions: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = "HelloWindow"
        content.body = body
        content.sound = .default
        if actions { content.categoryIdentifier = NotificationsDemoViewController.categoryIdentifier }
        let trigger = seconds.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                let text = error.map { "add \(identifier) failed: \($0.localizedDescription)" } ?? "added \(identifier)\(seconds.map { " (fires in \(Int($0)) s)" } ?? "")"
                self?.response.stringValue = text
                self?.trace(text)
            }
        }
    }

    private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if loginItem.state == .on {
                try service.register()
            } else {
                try service.unregister()
            }
            trace("login item \(Self.describe(service.status))")
        } catch {
            response.stringValue = "Login item: \(error.localizedDescription)"
            trace("login item error \(error.localizedDescription)")
        }
        refresh()
    }

    // Actions arrive by selector name (no Objective-C runtime on Windows and Linux).
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        if action == Selector(("toggleLoginItem:")) { toggleLoginItem(); return true }
        if action == Selector(("openLoginItems:")) { SMAppService.openSystemSettingsLoginItems(); return true }
        guard available else { return false }
        switch action {
        case Selector(("requestPermission:")):
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.trace("authorization granted=\(granted)")
                    self?.refresh()
                }
            }
        case Selector(("notifyNow:")): post("now", title: "Hello now", body: "Posted at once.", after: nil, actions: false)
        case Selector(("notifyLater:")): post("later", title: "Hello later", body: "Scheduled 10 seconds ago.", after: 10, actions: false)
        case Selector(("notifyWithActions:")): post("actions", title: "Hello with actions", body: "Try Done, Snooze or Reply.", after: nil, actions: true)
        case Selector(("removeDelivered:")):
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            response.stringValue = "Removed delivered notifications"
        default: return false
        }
        return true
    }

    // MARK: UNUserNotificationCenterDelegate

    #if canImport(ObjectiveC)
    @objc
    #endif
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    #if canImport(ObjectiveC)
    @objc
    #endif
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse).map { " text=\"\($0.userText)\"" } ?? ""
        await MainActor.run {
            let line = "response \(id) action=\(action)\(text)"
            self.response.stringValue = line
            self.trace(line)
        }
    }
}
