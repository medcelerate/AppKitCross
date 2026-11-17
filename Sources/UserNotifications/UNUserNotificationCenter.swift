// UserNotifications (ADR-0043): the notification center and its delegate.
//
// The center owns everything Apple's notification daemon would: the authorization flow, the
// categories, the pending requests and their timers, and the delivered list. The platform
// notifier (Internal/PlatformNotifier.swift) only shows and removes notifications and
// reports clicks, button presses and dismissals back. State lives on one serial queue;
// delegate methods run on the main queue, as Apple's do.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate
///
/// Apple's protocol has optional Objective-C requirements, each available in a completion-
/// handler form and an async form. Here every requirement has a default, and the defaults of
/// the two forms call each other: implement either one. A delegate that implements neither
/// gets Apple's behaviour (no presentation while the app is frontmost; the response ignored).
public protocol UNUserNotificationCenterDelegate: NSObjectProtocol {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?)
}

/// Set while a completion-handler default forwards to the async form, so the async form's
/// default can tell that neither form is implemented (instead of forwarding back forever).
enum UNDelegateForwarding {
    @TaskLocal static var fromCompletionDefault = false
}

extension UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        let box = UNUncheckedBox(self)
        Task {
            let options = await UNDelegateForwarding.$fromCompletionDefault.withValue(true) {
                await box.value.userNotificationCenter(center, willPresent: notification)
            }
            completionHandler(options)
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if UNDelegateForwarding.fromCompletionDefault { return [] }
        return await withCheckedContinuation { continuation in
            self.userNotificationCenter(center, willPresent: notification, withCompletionHandler: { continuation.resume(returning: $0) })
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let box = UNUncheckedBox(self)
        Task {
            await UNDelegateForwarding.$fromCompletionDefault.withValue(true) {
                await box.value.userNotificationCenter(center, didReceive: response)
            }
            completionHandler()
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if UNDelegateForwarding.fromCompletionDefault { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.userNotificationCenter(center, didReceive: response, withCompletionHandler: { continuation.resume() })
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {}
}

/// Carries a non-Sendable value into a task; the center hands delegates over on the main
/// queue only.
struct UNUncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
open class UNUserNotificationCenter: NSObject, @unchecked Sendable {
    private static let shared = UNUserNotificationCenter(notifier: makeDefaultNotifier(), defaults: .standard)

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/current()
    open class func current() -> UNUserNotificationCenter { shared }

    private struct Pending {
        var request: UNNotificationRequest
        var timer: DispatchSourceTimer
        var fireDate: Date
    }

    let notifier: PlatformNotifier
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "UserNotifications.center")
    private let delegateLock = NSLock()
    private weak var _delegate: (any UNUserNotificationCenterDelegate)?
    // Queue-confined state.
    private var categories: Set<UNNotificationCategory> = []
    private var pending: [String: Pending] = [:]
    private var pendingOrder: [String] = []
    private var delivered: [UNNotification] = []

    static let authorizationKey = "AppKitCross.UNAuthorizationOptions"

    init(notifier: PlatformNotifier, defaults: UserDefaults) {
        self.notifier = notifier
        self.defaults = defaults
        super.init()
        notifier.setEventHandler { [weak self] event in
            guard let self else { return }
            self.queue.async { self.handle(event) }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate
    /// Held weakly, as Apple's is.
    open var delegate: (any UNUserNotificationCenterDelegate)? {
        get { delegateLock.lock(); defer { delegateLock.unlock() }; return _delegate }
        set { delegateLock.lock(); _delegate = newValue; delegateLock.unlock() }
    }

    /// Notification content extensions are an Apple-platform feature.
    open var supportsContentExtensions: Bool { false }

    // MARK: Authorization

    private var requestedOptions: UNAuthorizationOptions? {
        guard let raw = defaults.object(forKey: UNUserNotificationCenter.authorizationKey) as? NSNumber else { return nil }
        return UNAuthorizationOptions(rawValue: raw.uintValue)
    }

    var authorizationStatus: UNAuthorizationStatus {
        guard let options = requestedOptions else { return .notDetermined }
        guard notifier.authorization() == .allowed else { return .denied }
        return options.contains(.provisional) ? .provisional : .authorized
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)
    open func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        let granted = authorize(options)
        DispatchQueue.global().async { completionHandler(granted, nil) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)
    open func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool {
        authorize(options)
    }

    /// Records the request (there is no prompt on these platforms: the platform's own switch
    /// decides) and reports whether the app may notify.
    @discardableResult
    private func authorize(_ options: UNAuthorizationOptions) -> Bool {
        var stored = options
        // A full request after a provisional one upgrades it, as Apple's prompt does.
        if let previous = requestedOptions {
            stored = previous.union(options)
            if !options.contains(.provisional) { stored.remove(.provisional) }
        }
        defaults.set(NSNumber(value: stored.rawValue), forKey: UNUserNotificationCenter.authorizationKey)
        let status = authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationsettings(completionhandler:)
    open func getNotificationSettings(completionHandler: @escaping @Sendable (UNNotificationSettings) -> Void) {
        let settings = currentSettings()
        DispatchQueue.global().async { completionHandler(settings) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/notificationsettings()
    open func notificationSettings() async -> UNNotificationSettings { currentSettings() }

    private func currentSettings() -> UNNotificationSettings {
        UNNotificationSettings(status: authorizationStatus, options: requestedOptions ?? [], badgeSupported: true)
    }

    // MARK: Categories

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setnotificationcategories(_:)
    open func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        queue.sync { self.categories = categories }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getnotificationcategories(completionhandler:)
    open func getNotificationCategories(completionHandler: @escaping @Sendable (Set<UNNotificationCategory>) -> Void) {
        let categories = queue.sync { self.categories }
        DispatchQueue.global().async { completionHandler(categories) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/notificationcategories()
    open func notificationCategories() async -> Set<UNNotificationCategory> { queue.sync { categories } }

    // MARK: Requests

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)
    open func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {
        let error = schedule(request)
        if let completionHandler { DispatchQueue.global().async { completionHandler(error) } }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/add(_:withcompletionhandler:)
    open func add(_ request: UNNotificationRequest) async throws {
        if let error = schedule(request) { throw error }
    }

    private func schedule(_ request: UNNotificationRequest) -> (any Error)? {
        let status = authorizationStatus
        guard status == .authorized || status == .provisional else { return UNError(.notificationsNotAllowed) }
        queue.sync {
            cancelPending(request.identifier)
            guard let trigger = request.trigger else {
                deliver(request)
                return
            }
            guard let date = trigger.nextFireDate(after: Date()) else { return }   // a date that never comes
            arm(request, at: date)
        }
        return nil
    }

    /// Queue-confined: starts the timer for one firing of a pending request.
    private func arm(_ request: UNNotificationRequest, at date: Date) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let seconds = max(0, date.timeIntervalSinceNow)
        timer.schedule(wallDeadline: .now() + seconds, leeway: .milliseconds(50))
        let identifier = request.identifier
        timer.setEventHandler { [weak self] in self?.fire(identifier) }
        if pending[identifier] == nil { pendingOrder.append(identifier) }
        pending[identifier] = Pending(request: request, timer: timer, fireDate: date)
        timer.resume()
    }

    private func fire(_ identifier: String) {
        guard let entry = pending[identifier] else { return }
        entry.timer.cancel()
        if let trigger = entry.request.trigger, trigger.repeats,
           let next = trigger.nextFireDate(after: max(Date(), entry.fireDate.addingTimeInterval(1))) {
            arm(entry.request, at: next)
        } else {
            pending[identifier] = nil
            pendingOrder.removeAll { $0 == identifier }
        }
        deliver(entry.request)
    }

    private func cancelPending(_ identifier: String) {
        guard let entry = pending.removeValue(forKey: identifier) else { return }
        entry.timer.cancel()
        pendingOrder.removeAll { $0 == identifier }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:)
    open func getPendingNotificationRequests(completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void) {
        let requests = pendingRequests()
        DispatchQueue.global().async { completionHandler(requests) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/pendingnotificationrequests()
    open func pendingNotificationRequests() async -> [UNNotificationRequest] { pendingRequests() }

    private func pendingRequests() -> [UNNotificationRequest] {
        queue.sync { pendingOrder.compactMap { pending[$0]?.request } }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removependingnotificationrequests(withidentifiers:)
    open func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        queue.sync { identifiers.forEach(cancelPending) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removeallpendingnotificationrequests()
    open func removeAllPendingNotificationRequests() {
        queue.sync { pendingOrder.forEach(cancelPending) }
    }

    // MARK: Delivered notifications

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications(completionhandler:)
    open func getDeliveredNotifications(completionHandler: @escaping @Sendable ([UNNotification]) -> Void) {
        let notifications = queue.sync { delivered }
        DispatchQueue.global().async { completionHandler(notifications) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/deliverednotifications()
    open func deliveredNotifications() async -> [UNNotification] { queue.sync { delivered } }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removedeliverednotifications(withidentifiers:)
    open func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        queue.sync { delivered.removeAll { identifiers.contains($0.request.identifier) } }
        notifier.remove(identifiers: identifiers)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/removealldeliverednotifications()
    open func removeAllDeliveredNotifications() {
        queue.sync { delivered.removeAll() }
        notifier.removeAll()
    }

    // MARK: Badge

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setbadgecount(_:withcompletionhandler:)
    open func setBadgeCount(_ newBadgeCount: Int, withCompletionHandler completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {
        let error = applyBadge(newBadgeCount)
        if let completionHandler { DispatchQueue.global().async { completionHandler(error) } }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setbadgecount(_:withcompletionhandler:)
    open func setBadgeCount(_ newBadgeCount: Int) async throws {
        if let error = applyBadge(newBadgeCount) { throw error }
    }

    private func applyBadge(_ count: Int) -> (any Error)? {
        guard count >= 0 else { return UNError(.badgeInputInvalid) }
        if !notifier.setBadgeCount(count), let hook = UNPlatformHooks.setApplicationBadge {
            DispatchQueue.main.async { MainActor.assumeIsolated { hook(count) } }
        }
        return nil
    }

    // MARK: Delivery

    /// Queue-confined: a request's moment has come. Asks the delegate when the app is
    /// frontmost (Apple's rule), then presents with the resulting options.
    private func deliver(_ request: UNNotificationRequest) {
        let notification = UNNotification(date: Date(), request: request)
        guard let isActive = UNPlatformHooks.isApplicationActive else {
            present(notification, options: UNUserNotificationCenter.backgroundOptions)
            return
        }
        let box = UNUncheckedBox(notification)
        DispatchQueue.main.async { [self] in
            let active = MainActor.assumeIsolated { isActive() }
            guard active else {
                queue.async { self.present(box.value, options: UNUserNotificationCenter.backgroundOptions) }
                return
            }
            guard let delegate = self.delegate else {
                queue.async { self.present(box.value, options: []) }
                return
            }
            delegate.userNotificationCenter(self, willPresent: box.value) { options in
                self.queue.async { self.present(box.value, options: options) }
            }
        }
    }

    /// What Apple shows for an app in the background: everything the user allowed.
    static let backgroundOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]
    private static let legacyAlert = UNNotificationPresentationOptions(rawValue: 1 << 2)

    /// Queue-confined: shows a notification with what the delegate (or the background rule)
    /// asked for, limited to what the app is authorized for.
    func present(_ notification: UNNotification, options requested: UNNotificationPresentationOptions) {
        var options = requested
        if options.contains(UNUserNotificationCenter.legacyAlert) { options.formUnion([.banner, .list]) }
        let authorized = requestedOptions ?? []
        let status = authorizationStatus
        if !authorized.contains(.alert) || status == .provisional { options.remove(.banner) }
        if !authorized.contains(.alert) && status != .provisional { options.remove(.list) }
        if !authorized.contains(.sound) || status == .provisional { options.remove(.sound) }
        if !authorized.contains(.badge) { options.remove(.badge) }

        let content = notification.request.content
        if options.contains(.banner) || options.contains(.list) {
            let shown = platformNotification(for: notification, options: options)
            do {
                try notifier.post(shown)
                delivered.removeAll { $0.request.identifier == notification.request.identifier }
                delivered.append(notification)
            } catch {
                FileHandle.standardError.write(Data("UserNotifications: could not show \(notification.request.identifier): \(error)\n".utf8))
            }
        }
        if options.contains(.badge), let badge = content.badge {
            _ = applyBadge(badge.intValue)
        }
    }

    func platformNotification(for notification: UNNotification, options: UNNotificationPresentationOptions) -> PlatformNotification {
        let content = notification.request.content
        let category = categories.first { $0.identifier == content.categoryIdentifier }
        let actions = (category?.actions ?? []).map { action -> PlatformAction in
            let text = (action as? UNTextInputNotificationAction).map { (buttonTitle: $0.textInputButtonTitle, placeholder: $0.textInputPlaceholder) }
            return PlatformAction(identifier: action.identifier, title: action.title, destructive: action.options.contains(.destructive),
                                  foreground: action.options.contains(.foreground), textInput: text)
        }
        let images = content.attachments.filter { UNNotificationAttachment.isImage($0.type) }.map(\.url)
        return PlatformNotification(identifier: notification.request.identifier, title: content.title, subtitle: content.subtitle,
                                    body: content.body, playsSound: options.contains(.sound) && content.sound != nil,
                                    soundName: content.sound?.name?.rawValue, imageFiles: images, actions: actions,
                                    listOnly: !options.contains(.banner), interruptionLevel: content.interruptionLevel,
                                    threadIdentifier: content.threadIdentifier)
    }

    /// Queue-confined: the platform reports what happened to a shown notification.
    private func handle(_ event: PlatformNotificationEvent) {
        switch event {
        case let .activated(identifier, actionIdentifier, userText):
            guard let index = delivered.lastIndex(where: { $0.request.identifier == identifier }) else { return }
            let notification = delivered.remove(at: index)
            let category = categories.first { $0.identifier == notification.request.content.categoryIdentifier }
            let action = category?.actions.first { $0.identifier == actionIdentifier }
            let response: UNNotificationResponse
            if action is UNTextInputNotificationAction {
                response = UNTextInputNotificationResponse(notification: notification, actionIdentifier: actionIdentifier, userText: userText ?? "")
            } else {
                response = UNNotificationResponse(notification: notification, actionIdentifier: actionIdentifier)
            }
            let activates = actionIdentifier == UNNotificationDefaultActionIdentifier || action?.options.contains(.foreground) == true
            respond(response, activating: activates)
        case let .dismissed(identifier, reason):
            guard reason != .timedOut, let index = delivered.lastIndex(where: { $0.request.identifier == identifier }) else { return }
            let notification = delivered.remove(at: index)
            let category = categories.first { $0.identifier == notification.request.content.categoryIdentifier }
            if reason == .user, category?.options.contains(.customDismissAction) == true {
                respond(UNNotificationResponse(notification: notification, actionIdentifier: UNNotificationDismissActionIdentifier), activating: false)
            }
        }
    }

    private func respond(_ response: UNNotificationResponse, activating: Bool) {
        let box = UNUncheckedBox(response)
        DispatchQueue.main.async { [self] in
            if activating, let activate = UNPlatformHooks.activateApplication { MainActor.assumeIsolated { activate() } }
            self.delegate?.userNotificationCenter(self, didReceive: box.value, withCompletionHandler: {})
        }
    }
}
