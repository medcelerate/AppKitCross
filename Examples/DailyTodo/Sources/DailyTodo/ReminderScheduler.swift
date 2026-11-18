import AppKit
import DailyTodoCore
import Foundation
import UserNotifications

@MainActor
final class ReminderScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private var timer: Timer?
    private weak var store: AppStore?
    private var lastOpenedDayKey: String?

    func start(store: AppStore) {
        stop()
        self.store = store
        UNUserNotificationCenter.current().delegate = self
        requestAuthorization()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        store = nil
    }

    private func requestAuthorization() {
        Task {
            _ = try? await UNUserNotificationCenter
                .current()
                .requestAuthorization(options: [.alert, .sound])
        }
    }

    private func tick() {
        guard let store else { return }
        let now = Date()
        let planner = store.planner
        let today = planner.today(at: now)

        let opening = planner.workdayStart(on: today)
        if now >= opening && lastOpenedDayKey != planner.dayKey(for: today) {
            openMainWindow()
            lastOpenedDayKey = planner.dayKey(for: today)
        }

        sendMiddayReminderIfNeeded(now: now, today: today, planner: planner, store: store)
    }

    private func sendMiddayReminderIfNeeded(
        now: Date,
        today: Date,
        planner: WorkingDayPlanner,
        store: AppStore
    ) {
        guard planner.settings.reminderEnabled,
              planner.isWorkingDay(today),
              now >= planner.reminderDate(on: today),
              now < planner.workdayEnd(on: today) else {
            return
        }

        let pendingItems = store.document.pendingItems(asOf: today, planner: planner)
        guard !pendingItems.isEmpty else { return }
        guard store.markReminderSentIfNeeded(on: today) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Pending tasks"
        content.body = "You have \(pendingItems.count) \(pendingItems.count == 1 ? "task" : "tasks") pending halfway through your workday."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "daily-todo-midday-\(planner.dayKey(for: today))",
            content: content,
            trigger: nil
        )

        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            break
        }
    }

    // AppKitCross: `@objc` needs the Objective-C runtime, which Windows and Linux lack.
    #if canImport(ObjectiveC)
    @objc
    #endif
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
