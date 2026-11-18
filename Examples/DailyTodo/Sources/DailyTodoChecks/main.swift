import DailyTodoCore
import Foundation

var failures: [String] = []

func expect(
    _ condition: Bool,
    _ name: String
) {
    if !condition {
        failures.append(name)
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ name: String
) {
    if actual != expected {
        failures.append("\(name): expected \(expected), got \(actual)")
    }
}

func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 0,
    minute: Int = 0,
    timeZone: TimeZone
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.timeZone = timeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: components)!
}

let kolkata = TimeZone(identifier: "Asia/Kolkata")!
let kolkataPlanner = WorkingDayPlanner(
    settings: TodoSettings(timezoneIdentifier: kolkata.identifier)
)

let friday = date(2026, 11, 6, timeZone: kolkata)
let monday = date(2026, 11, 9, timeZone: kolkata)
expectEqual(kolkataPlanner.nextWorkingDay(after: friday), monday, "next working day skips weekend")

var document = TodoDocument(settings: TodoSettings(timezoneIdentifier: kolkata.identifier))
document.add(title: "  Review plan  ", on: friday, planner: kolkataPlanner)
expectEqual(document.items.map(\.title), ["Review plan"], "task title is trimmed")
expectEqual(document.items[0].dueDate, friday, "task due date is normalized to day start")

document.deferItem(document.items[0].id, planner: kolkataPlanner)
expectEqual(document.items[0].dueDate, monday, "unfinished Friday task moves to Monday")
expectEqual(document.items[0].deferredCount, 1, "deferred count increments")

document.setCompleted(document.items[0].id, isCompleted: true)
expect(document.items[0].isCompleted, "task can be completed")

var dailyDocument = TodoDocument(settings: TodoSettings(timezoneIdentifier: kolkata.identifier))
dailyDocument.add(title: "Overdue", on: date(2026, 11, 3, timeZone: kolkata), planner: kolkataPlanner)
dailyDocument.add(title: "Today", on: date(2026, 11, 5, timeZone: kolkata), planner: kolkataPlanner)
dailyDocument.add(title: "Tomorrow", on: date(2026, 11, 6, timeZone: kolkata), planner: kolkataPlanner)
dailyDocument.setCompleted(dailyDocument.items[0].id, isCompleted: true)
let pendingTitles = dailyDocument
    .pendingItems(asOf: date(2026, 11, 5, timeZone: kolkata), planner: kolkataPlanner)
    .map(\.title)
expectEqual(pendingTitles, ["Today"], "pending reminder tasks include overdue but exclude future tasks")

let openingPlanner = WorkingDayPlanner(
    settings: TodoSettings(
        workdayStartTime: TimeOfDay(hour: 9, minute: 30),
        timezoneIdentifier: kolkata.identifier
    )
)
expectEqual(
    openingPlanner.nextDailyOpening(after: date(2026, 11, 5, hour: 8, timeZone: kolkata)),
    date(2026, 11, 5, hour: 9, minute: 30, timeZone: kolkata),
    "daily opening uses current day before start time"
)
expectEqual(
    openingPlanner.nextDailyOpening(after: date(2026, 11, 5, hour: 10, timeZone: kolkata)),
    date(2026, 11, 6, hour: 9, minute: 30, timeZone: kolkata),
    "daily opening uses next day after start time"
)

expectEqual(
    kolkataPlanner.nextReminder(after: date(2026, 11, 5, hour: 11, timeZone: kolkata)),
    date(2026, 11, 5, hour: 13, timeZone: kolkata),
    "midday reminder occurs four hours after workday start"
)
expectEqual(
    kolkataPlanner.nextReminder(after: date(2026, 11, 6, hour: 14, timeZone: kolkata)),
    date(2026, 11, 9, hour: 13, timeZone: kolkata),
    "Friday midday reminder moves to Monday after it passes"
)

let newYork = TimeZone(identifier: "America/New_York")!
let newYorkPlanner = WorkingDayPlanner(
    settings: TodoSettings(
        workdayStartTime: TimeOfDay(hour: 9, minute: 0),
        timezoneIdentifier: newYork.identifier
    )
)
let daylightSavingReminder = newYorkPlanner.nextReminder(
    after: date(2026, 3, 6, hour: 12, timeZone: newYork)
)!
expectEqual(
    newYorkPlanner.timeOfDay(for: daylightSavingReminder),
    TimeOfDay(hour: 13, minute: 0),
    "reminder remains at local midpoint near a daylight-saving change"
)

var reminderDocument = TodoDocument(settings: TodoSettings(timezoneIdentifier: kolkata.identifier))
let reminderDay = date(2026, 11, 5, timeZone: kolkata)
expect(reminderDocument.markReminderSent(on: reminderDay, planner: kolkataPlanner), "first reminder is recorded")
expect(!reminderDocument.markReminderSent(on: reminderDay, planner: kolkataPlanner), "same-day reminder is not repeated")
expect(reminderDocument.hasReminderBeenSent(on: reminderDay, planner: kolkataPlanner), "reminder day is stored")
expect(!reminderDocument.hasReminderBeenSent(on: date(2026, 11, 6, timeZone: kolkata), planner: kolkataPlanner), "next day can receive a reminder")

let privateStoreDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("daily-todo-checks-\(UUID().uuidString)", isDirectory: true)
let temporaryFileURL = privateStoreDirectory.appendingPathComponent("daily-todo.json")
defer { try? FileManager.default.removeItem(at: privateStoreDirectory) }

let documentStore = TodoDocumentStore(fileURL: temporaryFileURL)
var persistedDocument = TodoDocument(
    settings: TodoSettings(
        workdayStartTime: TimeOfDay(hour: 8, minute: 45),
        timezoneIdentifier: kolkata.identifier,
        reminderEnabled: false
    )
)
persistedDocument.add(title: "Persisted task", on: reminderDay, planner: kolkataPlanner)
do {
    try documentStore.save(persistedDocument)
    let loadedDocument = documentStore.load()
    expectEqual(loadedDocument.settings.workdayStartTime, TimeOfDay(hour: 8, minute: 45), "persisted workday start time")
    expectEqual(loadedDocument.settings.timezoneIdentifier, kolkata.identifier, "persisted time zone")
    expectEqual(loadedDocument.items.map(\.title), ["Persisted task"], "persisted task")

    let directoryPermissions = try FileManager.default.attributesOfItem(
        atPath: privateStoreDirectory.path
    )[.posixPermissions] as? NSNumber
    let filePermissions = try FileManager.default.attributesOfItem(
        atPath: temporaryFileURL.path
    )[.posixPermissions] as? NSNumber
    expectEqual(
        directoryPermissions?.intValue,
        TodoDocumentStore.privateDirectoryPermissions,
        "task directory is owner-only"
    )
    expectEqual(
        filePermissions?.intValue,
        TodoDocumentStore.privateFilePermissions,
        "task file is owner-only"
    )
} catch {
    failures.append("document persistence: \(error)")
}

if failures.isEmpty {
    print("All DailyTodo checks passed.")
} else {
    print("DailyTodo checks failed:")
    failures.forEach { print(" - \($0)") }
    exit(1)
}
