import Combine
import DailyTodoCore
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var document: TodoDocument
    @Published var selectedDay: Date
    @Published var errorMessage: String?

    private let documentStore: TodoDocumentStore

    init(fileURL: URL = AppStore.defaultFileURL) {
        documentStore = TodoDocumentStore(fileURL: fileURL)
        let loadedDocument = documentStore.load()
        document = loadedDocument
        selectedDay = WorkingDayPlanner(settings: loadedDocument.settings).today()
    }

    nonisolated static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupport
            .appending(path: "DailyTodo", directoryHint: .isDirectory)
            .appending(path: "daily-todo.json")
    }

    var planner: WorkingDayPlanner {
        WorkingDayPlanner(settings: document.settings)
    }

    var itemsForSelectedDay: [TodoItem] {
        document.items(dueOn: selectedDay, planner: planner)
    }

    var pendingCountForSelectedDay: Int {
        itemsForSelectedDay.filter { !$0.isCompleted }.count
    }

    func add(_ title: String) {
        document.add(title: title, on: selectedDay, planner: planner)
        save()
    }

    func setCompleted(_ id: UUID, isCompleted: Bool) {
        document.setCompleted(id, isCompleted: isCompleted)
        save()
    }

    func deferItem(_ id: UUID) {
        document.deferItem(id, planner: planner)
        save()
    }

    func updateWorkdayStartTime(_ time: TimeOfDay) {
        document.settings.workdayStartTime = time
        save()
    }

    func updateTimeZone(_ identifier: String) {
        document.settings.timezoneIdentifier = identifier
        selectedDay = planner.today()
        save()
    }

    func setReminderEnabled(_ isEnabled: Bool) {
        document.settings.reminderEnabled = isEnabled
        save()
    }

    func markReminderSentIfNeeded(on date: Date) -> Bool {
        let wasMarked = document.markReminderSent(on: date, planner: planner)
        save()
        return wasMarked
    }

    private func save() {
        do {
            try documentStore.save(document)
        } catch {
            errorMessage = "Could not save your tasks: \(error.localizedDescription)"
        }
    }
}
