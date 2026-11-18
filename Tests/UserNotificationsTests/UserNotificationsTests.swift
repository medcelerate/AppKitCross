// UserNotifications (ADR-0043): the center against an in-memory platform notifier, the
// Windows toast XML and the freedesktop Notify arguments. Runs on every platform (macOS
// builds the module as UserNotificationsPortable).

import XCTest
#if canImport(UserNotificationsPortable)
@testable @_spi(AppKitCross) import UserNotificationsPortable
#else
@testable @_spi(AppKitCross) import UserNotifications
#endif

final class RecordingDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var presentOptions: UNNotificationPresentationOptions = [.banner, .sound]
    var presented: [String] = []
    var responses: [UNNotificationResponse] = []
    var onResponse: (() -> Void)?
    var onPresent: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        presented.append(notification.request.identifier)
        onPresent?()
        return presentOptions
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        responses.append(response)
        onResponse?()
    }
}

/// Implements the completion-handler forms instead.
final class CompletionDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var responses: [String] = []
    var onResponse: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        responses.append(response.actionIdentifier)
        onResponse?()
        completionHandler()
    }
}

/// Implements neither form.
final class SilentDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {}

final class UserNotificationsTests: XCTestCase {
    var notifier: InMemoryNotifier!
    var defaults: UserDefaults!
    var suiteName: String!
    var center: UNUserNotificationCenter!

    override func setUp() {
        super.setUp()
        suiteName = "UserNotificationsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        notifier = InMemoryNotifier()
        center = UNUserNotificationCenter(notifier: notifier, defaults: defaults)
        UNPlatformHooks.isApplicationActive = nil
        UNPlatformHooks.activateApplication = nil
        UNPlatformHooks.setApplicationBadge = nil
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        UNPlatformHooks.isApplicationActive = nil
        UNPlatformHooks.activateApplication = nil
        UNPlatformHooks.setApplicationBadge = nil
        super.tearDown()
    }

    private func content(_ title: String, body: String = "", category: String = "") -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.categoryIdentifier = category
        return c
    }

    private func authorize(_ options: UNAuthorizationOptions = [.alert, .sound, .badge]) async throws {
        let granted = try await center.requestAuthorization(options: options)
        XCTAssertTrue(granted)
    }

    /// Waits until `condition` holds. Delegate calls arrive on the main queue, which the main
    /// thread services while an async test runs off it.
    private func eventually(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: Authorization

    func testAuthorizationStartsUndeterminedAndFollowsThePlatformSwitch() async throws {
        var settings = await center.notificationSettings()
        XCTAssertEqual(settings.authorizationStatus, .notDetermined)
        try await authorize([.alert, .sound])
        settings = await center.notificationSettings()
        XCTAssertEqual(settings.authorizationStatus, .authorized)
        XCTAssertEqual(settings.alertSetting, .enabled)
        XCTAssertEqual(settings.soundSetting, .enabled)
        XCTAssertEqual(settings.badgeSetting, .disabled)
        XCTAssertEqual(settings.alertStyle, .banner)

        notifier.setAuthorization(.deniedBySettings)
        settings = await center.notificationSettings()
        XCTAssertEqual(settings.authorizationStatus, .denied)
        let granted = try await center.requestAuthorization(options: [.alert])
        XCTAssertFalse(granted)
    }

    func testCompletionHandlerAuthorizationAndSettings() {
        let done = expectation(description: "authorized")
        center.requestAuthorization(options: [.alert]) { granted, error in
            XCTAssertTrue(granted)
            XCTAssertNil(error)
            done.fulfill()
        }
        let settings = expectation(description: "settings")
        center.getNotificationSettings { s in
            XCTAssertEqual(s.authorizationStatus, .authorized)
            settings.fulfill()
        }
        wait(for: [done, settings], timeout: 2)
    }

    func testProvisionalAuthorizationDeliversQuietlyToTheList() async throws {
        try await authorize([.provisional, .alert, .sound])
        XCTAssertEqual(center.authorizationStatus, .provisional)
        try await center.add(UNNotificationRequest(identifier: "quiet", content: content("Quiet"), trigger: nil))
        XCTAssertEqual(notifier.shown.first?.listOnly, true)
        XCTAssertEqual(notifier.shown.first?.playsSound, false)
        // A full request later upgrades it.
        try await authorize([.alert, .sound])
        XCTAssertEqual(center.authorizationStatus, .authorized)
    }

    func testAddingBeforeAuthorizationFails() async {
        do {
            try await center.add(UNNotificationRequest(identifier: "x", content: content("X"), trigger: nil))
            XCTFail("expected notificationsNotAllowed")
        } catch let error as UNError {
            XCTAssertEqual(error.code, .notificationsNotAllowed)
            XCTAssertEqual((error as NSError).domain, UNErrorDomain)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(notifier.shown.isEmpty)
    }

    // MARK: Requests

    func testImmediateRequestIsShownAndDelivered() async throws {
        try await authorize()
        let c = content("Pending tasks", body: "You have 3 tasks")
        c.subtitle = "Midday"
        try await center.add(UNNotificationRequest(identifier: "midday", content: c, trigger: nil))
        let shown = try XCTUnwrap(notifier.shown.first)
        XCTAssertEqual(shown.identifier, "midday")
        XCTAssertEqual(shown.title, "Pending tasks")
        XCTAssertEqual(shown.subtitle, "Midday")
        XCTAssertEqual(shown.body, "You have 3 tasks")
        XCTAssertTrue(shown.playsSound)
        XCTAssertFalse(shown.listOnly)
        let delivered = await center.deliveredNotifications()
        XCTAssertEqual(delivered.map(\.request.identifier), ["midday"])

        center.removeDeliveredNotifications(withIdentifiers: ["midday"])
        XCTAssertTrue(notifier.shown.isEmpty)
        let after = await center.deliveredNotifications()
        XCTAssertTrue(after.isEmpty)
    }

    func testRequestKeepsAnImmutableCopyOfItsContent() {
        let c = content("Before")
        let request = UNNotificationRequest(identifier: "copy", content: c, trigger: nil)
        c.title = "After"
        XCTAssertEqual(request.content.title, "Before")
        XCTAssertFalse(request.content is UNMutableNotificationContent)
        let mutable = request.content.mutableCopy() as! UNMutableNotificationContent
        mutable.body = "edited"
        XCTAssertEqual(request.content.body, "")
    }

    func testTimeIntervalTriggerIsPendingUntilItFires() async throws {
        try await authorize()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.3, repeats: false)
        try await center.add(UNNotificationRequest(identifier: "soon", content: content("Soon"), trigger: trigger))
        var pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.map(\.identifier), ["soon"])
        XCTAssertTrue(notifier.shown.isEmpty)
        try await Task.sleep(nanoseconds: 800_000_000)
        pending = await center.pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(notifier.shown.map(\.identifier), ["soon"])
    }

    func testRemovingAndReplacingPendingRequests() async throws {
        try await authorize()
        let later = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        try await center.add(UNNotificationRequest(identifier: "a", content: content("A"), trigger: later))
        try await center.add(UNNotificationRequest(identifier: "b", content: content("B"), trigger: later))
        try await center.add(UNNotificationRequest(identifier: "a", content: content("A2"), trigger: later))
        var pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.map(\.identifier), ["b", "a"])
        XCTAssertEqual(pending.last?.content.title, "A2")
        center.removePendingNotificationRequests(withIdentifiers: ["b"])
        pending = await center.pendingNotificationRequests()
        XCTAssertEqual(pending.map(\.identifier), ["a"])
        center.removeAllPendingNotificationRequests()
        pending = await center.pendingNotificationRequests()
        XCTAssertTrue(pending.isEmpty)

        let listed = expectation(description: "pending")
        center.getPendingNotificationRequests { requests in
            XCTAssertTrue(requests.isEmpty)
            listed.fulfill()
        }
        await fulfillment(of: [listed], timeout: 2)
    }

    func testCalendarTriggerFindsTheNextMatchingDate() throws {
        var components = DateComponents()
        components.hour = 12
        components.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let next = try XCTUnwrap(trigger.nextTriggerDate())
        XCTAssertGreaterThan(next, Date())
        let parts = Calendar.current.dateComponents([.hour, .minute], from: next)
        XCTAssertEqual(parts.hour, 12)
        XCTAssertEqual(parts.minute, 30)
        XCTAssertLessThanOrEqual(next.timeIntervalSinceNow, 24 * 3600 + 3600)

        var past = DateComponents()
        past.year = 2001
        past.month = 1
        past.day = 1
        XCTAssertNil(UNCalendarNotificationTrigger(dateMatching: past, repeats: false).nextTriggerDate())
    }

    // MARK: Presentation and the delegate

    func testFrontmostAppAsksTheDelegate() async throws {
        try await authorize()
        UNPlatformHooks.isApplicationActive = { true }
        let delegate = RecordingDelegate()
        delegate.presentOptions = [.list]
        center.delegate = delegate
        try await center.add(UNNotificationRequest(identifier: "front", content: content("Front"), trigger: nil))
        await eventually { !notifier.shown.isEmpty }
        XCTAssertEqual(delegate.presented, ["front"])
        XCTAssertEqual(notifier.shown.first?.listOnly, true)
        XCTAssertEqual(notifier.shown.first?.playsSound, false)
    }

    func testFrontmostAppWithoutWillPresentShowsNothing() async throws {
        try await authorize()
        UNPlatformHooks.isApplicationActive = { true }
        let delegate = SilentDelegate()
        center.delegate = delegate
        try await center.add(UNNotificationRequest(identifier: "hidden", content: content("Hidden"), trigger: nil))
        await eventually(timeout: 0.5) { false }
        XCTAssertTrue(notifier.shown.isEmpty)
        let delivered = await center.deliveredNotifications()
        XCTAssertTrue(delivered.isEmpty)
    }

    func testBackgroundAppShowsWithoutAskingTheDelegate() async throws {
        try await authorize()
        UNPlatformHooks.isApplicationActive = { false }
        let delegate = RecordingDelegate()
        center.delegate = delegate
        try await center.add(UNNotificationRequest(identifier: "bg", content: content("Background"), trigger: nil))
        await eventually { !notifier.shown.isEmpty }
        XCTAssertTrue(delegate.presented.isEmpty)
        XCTAssertEqual(notifier.shown.first?.listOnly, false)
    }

    func testCompletionHandlerDelegateForms() async throws {
        try await authorize()
        UNPlatformHooks.isApplicationActive = { true }
        let delegate = CompletionDelegate()
        center.delegate = delegate
        try await center.add(UNNotificationRequest(identifier: "c", content: content("C"), trigger: nil))
        await eventually { !notifier.shown.isEmpty }
        XCTAssertEqual(notifier.shown.first?.listOnly, true)
        notifier.send(.activated(identifier: "c", actionIdentifier: UNNotificationDefaultActionIdentifier, userText: nil))
        await eventually { !delegate.responses.isEmpty }
        XCTAssertEqual(delegate.responses, [UNNotificationDefaultActionIdentifier])
    }

    func testActionsAndTextInputRouteBackToTheDelegate() async throws {
        try await authorize()
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let done = UNNotificationAction(identifier: "done", title: "Mark Done", options: [.foreground])
        let delete = UNNotificationAction(identifier: "delete", title: "Delete", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: "task", actions: [done, delete, reply], intentIdentifiers: [], options: [])])
        let categories = await center.notificationCategories()
        XCTAssertEqual(categories.map(\.identifier), ["task"])

        var activations = 0
        UNPlatformHooks.activateApplication = { activations += 1 }
        let delegate = RecordingDelegate()
        center.delegate = delegate
        try await center.add(UNNotificationRequest(identifier: "t1", content: content("Task", category: "task"), trigger: nil))
        let shown = try XCTUnwrap(notifier.shown.first)
        XCTAssertEqual(shown.actions.map(\.identifier), ["done", "delete", "reply"])
        XCTAssertEqual(shown.actions[0].foreground, true)
        XCTAssertEqual(shown.actions[1].destructive, true)
        XCTAssertEqual(shown.actions[2].textInput?.buttonTitle, "Send")

        notifier.send(.activated(identifier: "t1", actionIdentifier: "done", userText: nil))
        await eventually { delegate.responses.count == 1 }
        XCTAssertEqual(delegate.responses.first?.actionIdentifier, "done")
        XCTAssertEqual(delegate.responses.first?.notification.request.identifier, "t1")
        XCTAssertEqual(activations, 1)   // .foreground brings the app forward
        let delivered = await center.deliveredNotifications()
        XCTAssertTrue(delivered.isEmpty)

        try await center.add(UNNotificationRequest(identifier: "t2", content: content("Task", category: "task"), trigger: nil))
        notifier.send(.activated(identifier: "t2", actionIdentifier: "reply", userText: "on it"))
        await eventually { delegate.responses.count == 2 }
        let text = try XCTUnwrap(delegate.responses.last as? UNTextInputNotificationResponse)
        XCTAssertEqual(text.actionIdentifier, "reply")
        XCTAssertEqual(text.userText, "on it")
        XCTAssertEqual(activations, 1)
    }

    func testCustomDismissActionReportsUserDismissals() async throws {
        try await authorize()
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "watch", actions: [], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        let delegate = RecordingDelegate()
        center.delegate = delegate
        try await center.add(UNNotificationRequest(identifier: "timed", content: content("T", category: "watch"), trigger: nil))
        notifier.send(.dismissed(identifier: "timed", reason: .timedOut))
        var delivered = await center.deliveredNotifications()
        XCTAssertEqual(delivered.count, 1, "a timed-out toast stays in Action Center")
        notifier.send(.dismissed(identifier: "timed", reason: .user))
        await eventually { !delegate.responses.isEmpty }
        XCTAssertEqual(delegate.responses.first?.actionIdentifier, UNNotificationDismissActionIdentifier)
        delivered = await center.deliveredNotifications()
        XCTAssertTrue(delivered.isEmpty)
    }

    func testBadgeFollowsContentAndSetBadgeCount() async throws {
        try await authorize([.alert, .badge])
        let c = content("Badge")
        c.badge = 4
        try await center.add(UNNotificationRequest(identifier: "b", content: c, trigger: nil))
        XCTAssertEqual(notifier.badge, 4)
        try await center.setBadgeCount(0)
        XCTAssertEqual(notifier.badge, 0)
        do {
            try await center.setBadgeCount(-1)
            XCTFail("expected badgeInputInvalid")
        } catch let error as UNError {
            XCTAssertEqual(error.code, .badgeInputInvalid)
        }
    }

    func testBadgeFallsBackToTheDockTileHook() async throws {
        let notifier = InMemoryNotifier(ownsBadge: false)
        let center = UNUserNotificationCenter(notifier: notifier, defaults: defaults)
        var shownBadge: Int?
        UNPlatformHooks.setApplicationBadge = { shownBadge = $0 }
        try await center.setBadgeCount(7)
        await eventually { shownBadge != nil }
        XCTAssertEqual(shownBadge, 7)
    }

    // MARK: Values

    func testAttachmentsValidateTheirFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("pic.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: png)
        let attachment = try UNNotificationAttachment(identifier: "pic", url: png)
        XCTAssertEqual(attachment.type, "public.png")
        XCTAssertThrowsError(try UNNotificationAttachment(identifier: "missing", url: dir.appendingPathComponent("nope.png"))) {
            XCTAssertEqual(($0 as? UNError)?.code, .attachmentInvalidURL)
        }
        let txt = dir.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: txt)
        XCTAssertThrowsError(try UNNotificationAttachment(identifier: "txt", url: txt)) {
            XCTAssertEqual(($0 as? UNError)?.code, .attachmentUnrecognizedType)
        }
    }

    func testPresentationOptionRawValuesMatchApple() {
        XCTAssertEqual(UNNotificationPresentationOptions.banner.rawValue, 16)
        XCTAssertEqual(UNNotificationPresentationOptions.list.rawValue, 8)
        XCTAssertEqual(UNAuthorizationOptions.provisional.rawValue, 64)
        XCTAssertEqual(UNAuthorizationStatus.provisional.rawValue, 3)
        XCTAssertEqual(UNError.Code.notificationsNotAllowed.rawValue, 1)
        XCTAssertEqual(UNNotificationSound.default, UNNotificationSound.default)
        XCTAssertNotEqual(UNNotificationSound(named: UNNotificationSoundName("ding.wav")), UNNotificationSound.default)
    }

    // MARK: Windows toast XML

    private func sample(actions: [PlatformAction] = [], playsSound: Bool = true) -> PlatformNotification {
        PlatformNotification(identifier: "id", title: "Tom & Jerry", subtitle: "<sub>", body: "say \"hi\"", playsSound: playsSound, soundName: nil,
                             imageFiles: [], actions: actions, listOnly: false, interruptionLevel: .active, threadIdentifier: "")
    }

    func testToastXMLEscapesTextAndCarriesActionIdentifiers() {
        let xml = ToastXML.document(for: sample(actions: [
            PlatformAction(identifier: "done", title: "Done", destructive: false, foreground: true, textInput: nil),
            PlatformAction(identifier: "reply", title: "Reply", destructive: false, foreground: false, textInput: (buttonTitle: "Send", placeholder: "Say <it>")),
        ]))
        XCTAssertTrue(xml.hasPrefix("<toast launch=\"id com.apple.UNNotificationDefaultActionIdentifier\">"))
        XCTAssertTrue(xml.contains("<text>Tom &amp; Jerry</text><text>&lt;sub&gt;</text><text>say &quot;hi&quot;</text>"))
        XCTAssertTrue(xml.contains("<input id=\"text-1\" type=\"text\" title=\"Reply\" placeHolderContent=\"Say &lt;it&gt;\"/>"))
        XCTAssertTrue(xml.contains("<action content=\"Done\" arguments=\"id done\" activationType=\"foreground\"/>"))
        XCTAssertTrue(xml.contains("<action content=\"Send\" arguments=\"id reply\" activationType=\"foreground\" hint-inputId=\"text-1\"/>"))
        XCTAssertTrue(xml.contains("<audio src=\"ms-winsoundevent:Notification.Default\"/>"))
        XCTAssertTrue(ToastXML.document(for: sample(playsSound: false)).contains("<audio silent=\"true\"/>"))
    }

    func testToastArgumentsCarryTheTagForTheCOMActivator() {
        XCTAssertEqual(ToastXML.arguments(tag: "task 1", action: "done"), "task%201 done")
        XCTAssertEqual(ToastXML.arguments(tag: "a&b", action: "r\u{e9}ply"), "a%26b r%C3%A9ply")
        let xml = ToastXML.document(for: PlatformNotification(identifier: "two words", title: "t", subtitle: "", body: "", playsSound: true, soundName: nil,
                                                              imageFiles: [], actions: [], listOnly: false, interruptionLevel: .active, threadIdentifier: ""))
        XCTAssertTrue(xml.hasPrefix("<toast launch=\"two%20words com.apple.UNNotificationDefaultActionIdentifier\">"))
    }

    func testToastXMLKeepsAtMostFiveActionsAndShortTags() {
        let many = (0..<7).map { PlatformAction(identifier: "a\($0)", title: "A\($0)", destructive: false, foreground: false, textInput: nil) }
        let xml = ToastXML.document(for: sample(actions: many))
        XCTAssertEqual(xml.components(separatedBy: "<action ").count - 1, 5)
        XCTAssertEqual(ToastXML.tag(for: "short"), "short")
        let long = String(repeating: "x", count: 100)
        XCTAssertLessThanOrEqual(ToastXML.tag(for: long).count, 64)
        XCTAssertEqual(ToastXML.tag(for: long), ToastXML.tag(for: long))
        XCTAssertNotEqual(ToastXML.tag(for: long), ToastXML.tag(for: long + "y"))
    }

    // MARK: freedesktop Notify arguments

    func testFreedesktopPayloadWithActionsAndMarkup() {
        var n = sample(actions: [
            PlatformAction(identifier: "done", title: "Done", destructive: false, foreground: true, textInput: nil),
            PlatformAction(identifier: "reply", title: "Reply", destructive: false, foreground: false, textInput: (buttonTitle: "Send", placeholder: "")),
        ])
        n.imageFiles = [URL(fileURLWithPath: "/tmp/pic.png")]
        let p = FreedesktopPayload.make(for: n, appName: "Daily To Do", desktopEntry: "com.example.todo",
                                        capabilities: ["actions", "body", "body-markup", "inline-reply"])
        XCTAssertEqual(p.summary, "Tom & Jerry")
        XCTAssertEqual(p.body, "&lt;sub&gt;\nsay \"hi\"")
        XCTAssertEqual(p.actions, ["default", "", "done", "Done", "inline-reply", "Send"])
        XCTAssertEqual(p.actionKeys["default"], UNNotificationDefaultActionIdentifier)
        XCTAssertEqual(p.actionKeys["inline-reply"], "reply")
        XCTAssertEqual(p.hint("desktop-entry"), .string("com.example.todo"))
        XCTAssertEqual(p.hint("urgency"), .byte(1))
        XCTAssertEqual(p.hint("sound-name"), .string("message-new-instant"))
        XCTAssertEqual(p.hint("image-path"), .string("/tmp/pic.png"))
        XCTAssertEqual(p.expireTimeout, -1)
    }

    func testFreedesktopPayloadWithoutCapabilities() {
        var n = sample(actions: [PlatformAction(identifier: "reply", title: "Reply", destructive: false, foreground: false, textInput: (buttonTitle: "Send", placeholder: ""))],
                       playsSound: false)
        n.listOnly = true
        let p = FreedesktopPayload.make(for: n, appName: "App", desktopEntry: "", capabilities: ["body"])
        XCTAssertEqual(p.body, "<sub>\nsay \"hi\"")
        XCTAssertTrue(p.actions.isEmpty)
        XCTAssertNil(p.hint("desktop-entry"))
        XCTAssertEqual(p.hint("urgency"), .byte(0))
        XCTAssertEqual(p.hint("suppress-sound"), .bool(true))

        let plain = FreedesktopPayload.make(for: sample(actions: n.actions), appName: "App", desktopEntry: "", capabilities: ["actions"])
        XCTAssertEqual(plain.actions, ["default", "", "reply", "Reply"])
    }
}
