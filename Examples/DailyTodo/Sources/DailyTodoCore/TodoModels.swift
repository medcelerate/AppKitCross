import Foundation

public struct TimeOfDay: Codable, Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
}

public struct TodoSettings: Codable, Equatable, Sendable {
    public var workdayStartTime: TimeOfDay
    public var timezoneIdentifier: String
    public var reminderEnabled: Bool

    public init(
        workdayStartTime: TimeOfDay = TimeOfDay(hour: 9, minute: 0),
        timezoneIdentifier: String = TimeZone.current.identifier,
        reminderEnabled: Bool = true
    ) {
        self.workdayStartTime = workdayStartTime
        self.timezoneIdentifier = timezoneIdentifier
        self.reminderEnabled = reminderEnabled
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? .current
    }
}

public struct TodoItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var dueDate: Date
    public var completedAt: Date?
    public var deferredCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        dueDate: Date,
        completedAt: Date? = nil,
        deferredCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.deferredCount = deferredCount
    }

    public var isCompleted: Bool {
        completedAt != nil
    }
}

public struct TodoDocument: Codable, Equatable, Sendable {
    public var settings: TodoSettings
    public var items: [TodoItem]
    public var lastReminderDayKey: String?

    public init(
        settings: TodoSettings = TodoSettings(),
        items: [TodoItem] = [],
        lastReminderDayKey: String? = nil
    ) {
        self.settings = settings
        self.items = items
        self.lastReminderDayKey = lastReminderDayKey
    }

    public mutating func add(title: String, on day: Date, planner: WorkingDayPlanner) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        items.append(
            TodoItem(
                title: trimmedTitle,
                dueDate: planner.startOfDay(for: day)
            )
        )
    }

    public mutating func setCompleted(_ id: UUID, isCompleted: Bool, at date: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].completedAt = isCompleted ? date : nil
    }

    public mutating func deferItem(_ id: UUID, planner: WorkingDayPlanner) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isCompleted else { return }

        items[index].dueDate = planner.nextWorkingDay(after: items[index].dueDate)
        items[index].deferredCount += 1
    }

    public func items(dueOn day: Date, planner: WorkingDayPlanner) -> [TodoItem] {
        let dayStart = planner.startOfDay(for: day)
        return items.filter { planner.startOfDay(for: $0.dueDate) == dayStart }
    }

    public func pendingItems(asOf day: Date, planner: WorkingDayPlanner) -> [TodoItem] {
        let dayStart = planner.startOfDay(for: day)
        return items.filter { !$0.isCompleted && planner.startOfDay(for: $0.dueDate) <= dayStart }
    }

    public func hasReminderBeenSent(on day: Date, planner: WorkingDayPlanner) -> Bool {
        lastReminderDayKey == planner.dayKey(for: day)
    }

    @discardableResult
    public mutating func markReminderSent(on day: Date, planner: WorkingDayPlanner) -> Bool {
        let dayKey = planner.dayKey(for: day)
        guard lastReminderDayKey != dayKey else {
            return false
        }
        lastReminderDayKey = dayKey
        return true
    }
}
