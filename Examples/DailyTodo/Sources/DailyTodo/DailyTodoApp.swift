import SwiftUI

@main
struct DailyTodoApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var scheduler = ReminderScheduler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    scheduler.start(store: store)
                }
        }
        .windowResizability(.contentSize)
    }
}
