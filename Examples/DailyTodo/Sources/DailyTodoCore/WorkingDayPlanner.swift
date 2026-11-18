import Foundation

public struct WorkingDayPlanner: Equatable, Sendable {
    public let settings: TodoSettings
    public let timeZone: TimeZone

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public init(settings: TodoSettings) {
        self.settings = settings
        self.timeZone = settings.timeZone
    }

    public func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func today(at date: Date = Date()) -> Date {
        startOfDay(for: date)
    }

    public func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    public func timeOfDay(for date: Date) -> TimeOfDay {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    public func date(onDayOf day: Date, at time: TimeOfDay) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? day
    }

    public func isWorkingDay(_ day: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekday != 1 && weekday != 7
    }

    public func nextWorkingDay(after day: Date) -> Date {
        var candidate = calendar.date(byAdding: .day, value: 1, to: startOfDay(for: day)) ?? day
        while !isWorkingDay(candidate) {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    public func workdayStart(on day: Date) -> Date {
        date(onDayOf: day, at: settings.workdayStartTime)
    }

    public func workdayEnd(on day: Date) -> Date {
        calendar.date(byAdding: .hour, value: 8, to: workdayStart(on: day)) ?? workdayStart(on: day)
    }

    public func reminderDate(on day: Date) -> Date {
        calendar.date(byAdding: .hour, value: 4, to: workdayStart(on: day)) ?? workdayStart(on: day)
    }

    public func nextDailyOpening(after date: Date) -> Date {
        let currentDay = startOfDay(for: date)
        let todayOpening = workdayStart(on: currentDay)
        if todayOpening > date {
            return todayOpening
        }

        let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay
        return workdayStart(on: nextDay)
    }

    public func nextReminder(after date: Date) -> Date? {
        guard settings.reminderEnabled else { return nil }

        var day = startOfDay(for: date)
        if !isWorkingDay(day) || reminderDate(on: day) <= date {
            day = nextWorkingDay(after: day)
        }
        return reminderDate(on: day)
    }
}
