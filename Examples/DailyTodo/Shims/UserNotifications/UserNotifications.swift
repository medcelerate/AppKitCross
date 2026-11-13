// Shim for Apple's UserNotifications framework (Windows and Linux only; the macOS host build
// uses the real one). Port gap: AppKitCross has no UserNotifications module, and the upstream
// app (ReminderScheduler.swift) asks UNUserNotificationCenter for permission and posts one
// midday reminder. This shim keeps the API the app uses — `current()`, `delegate`,
// `requestAuthorization`, `add`, the content, request, sound and presentation-option types —
// and delivers a request by asking the delegate how to present it, then printing the title
// and body on stderr. Follow-up for the port: a real UserNotifications over Windows toast
// notifications (Shell_NotifyIcon balloons or WinRT ToastNotificationManager) and the
// org.freedesktop.Notifications D-Bus service on Linux.
import Foundation

public struct UNAuthorizationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let provisional = UNAuthorizationOptions(rawValue: 1 << 6)
}

public struct UNNotificationPresentationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 3)
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 4)
}

public enum UNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0, denied, authorized, provisional
}

open class UNNotificationSound: NSObject, @unchecked Sendable {
    public static let `default` = UNNotificationSound()
    override public init() { super.init() }
}

open class UNNotificationContent: NSObject, @unchecked Sendable {
    public internal(set) var title: String = ""
    public internal(set) var subtitle: String = ""
    public internal(set) var body: String = ""
    public internal(set) var sound: UNNotificationSound?
    public internal(set) var badge: NSNumber?
    public internal(set) var userInfo: [AnyHashable: Any] = [:]
    override public init() { super.init() }
}

open class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {
    override public var title: String { get { super.title } set { super.title = newValue } }
    override public var subtitle: String { get { super.subtitle } set { super.subtitle = newValue } }
    override public var body: String { get { super.body } set { super.body = newValue } }
    override public var sound: UNNotificationSound? { get { super.sound } set { super.sound = newValue } }
    override public var badge: NSNumber? { get { super.badge } set { super.badge = newValue } }
    override public var userInfo: [AnyHashable: Any] { get { super.userInfo } set { super.userInfo = newValue } }
}

open class UNNotificationTrigger: NSObject, @unchecked Sendable {
    public let repeats: Bool
    init(repeats: Bool) { self.repeats = repeats }
}

open class UNTimeIntervalNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let timeInterval: TimeInterval
    public init(timeInterval: TimeInterval, repeats: Bool) { self.timeInterval = timeInterval; super.init(repeats: repeats) }
}

open class UNNotificationRequest: NSObject, @unchecked Sendable {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

open class UNNotification: NSObject, @unchecked Sendable {
    public let date: Date
    public let request: UNNotificationRequest
    init(date: Date, request: UNNotificationRequest) { self.date = date; self.request = request }
}

public protocol UNUserNotificationCenterDelegate: NSObjectProtocol {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions
}

extension UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [] }
}

public final class UNUserNotificationCenter: NSObject, @unchecked Sendable {
    private static let shared = UNUserNotificationCenter()
    public static func current() -> UNUserNotificationCenter { shared }

    public weak var delegate: (any UNUserNotificationCenterDelegate)?
    private let lock = NSLock()
    private var authorized = false
    private var pending: [UNNotificationRequest] = []
    /// Every request delivered so far, oldest first.
    public private(set) var delivered: [UNNotificationRequest] = []

    override private init() { super.init() }

    public func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping (Bool, (any Error)?) -> Void) {
        lock.lock(); authorized = true; lock.unlock()
        completionHandler(true, nil)
    }

    public func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool {
        lock.lock(); authorized = true; lock.unlock()
        return true
    }

    public func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((any Error)?) -> Void) {
        Task { try? await add(request) }
        completionHandler(nil)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
            lock.lock(); pending.append(request); lock.unlock()
            try? await Task.sleep(nanoseconds: UInt64(max(0, trigger.timeInterval) * 1_000_000_000))
            lock.lock(); pending.removeAll { $0 === request }; lock.unlock()
        }
        let notification = UNNotification(date: Date(), request: request)
        let options = await delegate?.userNotificationCenter(self, willPresent: notification) ?? [.banner]
        lock.lock(); delivered.append(request); lock.unlock()
        guard !options.isEmpty else { return }
        let content = request.content
        let line = "[notification] \(content.title)\(content.body.isEmpty ? "" : ": \(content.body)")\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.lock(); pending.removeAll { identifiers.contains($0.identifier) }; lock.unlock()
    }

    public func removeAllPendingNotificationRequests() {
        lock.lock(); pending.removeAll(); lock.unlock()
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        lock.lock(); delivered.removeAll { identifiers.contains($0.identifier) }; lock.unlock()
    }
}
