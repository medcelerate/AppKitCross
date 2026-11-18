// UserNotifications (ADR-0043): triggers. The port schedules them with timers inside the
// process, so delivery needs the app to be running when the trigger fires: Windows and
// Linux have no notification daemon that holds an unpackaged app's schedule. Unlike Apple's,
// pending requests do not outlive the process; an app that quits loses them and schedules
// again at its next launch.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/unnotificationtrigger
open class UNNotificationTrigger: NSObject, @unchecked Sendable {
    public let repeats: Bool

    init(repeats: Bool) {
        self.repeats = repeats
        super.init()
    }

    /// The first date the trigger fires after `date`, or nil when it never does.
    func nextFireDate(after date: Date) -> Date? { nil }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger
open class UNTimeIntervalNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let timeInterval: TimeInterval

    public init(timeInterval: TimeInterval, repeats: Bool) {
        // Apple raises NSInternalInconsistencyException for both.
        precondition(timeInterval > 0, "time interval must be greater than 0")
        precondition(!repeats || timeInterval >= 60, "time interval must be at least 60 if repeating")
        self.timeInterval = timeInterval
        super.init(repeats: repeats)
    }

    open func nextTriggerDate() -> Date? { Date(timeIntervalSinceNow: timeInterval) }

    override func nextFireDate(after date: Date) -> Date? { date.addingTimeInterval(timeInterval) }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNTimeIntervalNotificationTrigger else { return false }
        return o.timeInterval == timeInterval && o.repeats == repeats
    }

    open override var hash: Int { timeInterval.hashValue }
}

/// - SeeAlso: https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger
open class UNCalendarNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let dateComponents: DateComponents

    public init(dateMatching dateComponents: DateComponents, repeats: Bool) {
        self.dateComponents = dateComponents
        super.init(repeats: repeats)
    }

    open func nextTriggerDate() -> Date? { nextFireDate(after: Date()) }

    override func nextFireDate(after date: Date) -> Date? {
        var calendar = dateComponents.calendar ?? Calendar.current
        if let zone = dateComponents.timeZone { calendar.timeZone = zone }
        var matching = dateComponents
        matching.calendar = nil
        matching.timeZone = nil
        return calendar.nextDate(after: date, matching: matching, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? UNCalendarNotificationTrigger else { return false }
        return o.dateComponents == dateComponents && o.repeats == repeats
    }

    open override var hash: Int { dateComponents.hashValue }
}
