import DailyTodoCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var timeZoneFilter = ""
    @State private var loginItemMessage: String?

    private var planner: WorkingDayPlanner {
        store.planner
    }

    private var timeZoneOptions: [TimeZoneOption] {
        TimeZone.knownTimeZoneIdentifiers.map { identifier in
            TimeZoneOption(
                id: identifier,
                title: displayName(for: identifier),
                searchKeywords: searchKeywords(for: identifier)
            )
        }
        .filter { option in
            timeZoneFilter.isEmpty ||
            option.searchKeywords.localizedCaseInsensitiveContains(timeZoneFilter)
        }
    }

    var body: some View {
        Form {
            Section("Workday") {
                DatePicker(
                    "Workday starts",
                    selection: workdayStartTimeBinding,
                    displayedComponents: .hourAndMinute
                )

                Picker("Time zone", selection: timeZoneBinding) {
                    ForEach(timeZoneOptions) { option in
                        Text(option.title)
                            .tag(option.id)
                    }
                }

                TextField("Filter time zones", text: $timeZoneFilter)

                Toggle("Midday reminder", isOn: reminderEnabledBinding)
            }

            Section("Schedule") {
                LabeledContent(
                    "Reminder time",
                    value: formatted(planner.reminderDate(on: planner.today()))
                )
                LabeledContent(
                    "Next opening",
                    value: formatted(planner.nextDailyOpening(after: Date()))
                )
                LabeledContent(
                    "Next reminder",
                    value: planner.nextReminder(after: Date()).map(formatted) ?? "Disabled"
                )
            }

            Section("Daily Opening") {
                Text("The app starts at login and activates its window at your configured time. Keep it running after closing its window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Open at login") {
                        runLoginItemAction(controller.install)
                    }
                    Button("Disable") {
                        runLoginItemAction(controller.uninstall)
                    }
                }

                if let loginItemMessage {
                    Text(loginItemMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 560)
        .toolbar {
            Button("Done") {
                dismiss()
            }
        }
    }

    private var workdayStartTimeBinding: Binding<Date> {
        Binding(
            get: {
                planner.date(
                    onDayOf: planner.today(),
                    at: store.document.settings.workdayStartTime
                )
            },
            set: { date in
                store.updateWorkdayStartTime(planner.timeOfDay(for: date))
            }
        )
    }

    private var timeZoneBinding: Binding<String> {
        Binding(
            get: { store.document.settings.timezoneIdentifier },
            set: { store.updateTimeZone($0) }
        )
    }

    private var reminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.document.settings.reminderEnabled },
            set: { store.setReminderEnabled($0) }
        )
    }

    private let controller = LoginItemController()

    private func displayName(for identifier: String) -> String {
        timeZoneLabels(for: identifier).joined(separator: " — ")
    }

    private func searchKeywords(for identifier: String) -> String {
        let aliases = [
            "Asia/Kolkata": "India IST Indian Standard Time Calcutta",
            "Asia/Calcutta": "India IST Indian Standard Time Kolkata"
        ]
        return (timeZoneLabels(for: identifier) + [aliases[identifier] ?? ""])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func timeZoneLabels(for identifier: String) -> [String] {
        let timeZone = TimeZone(identifier: identifier) ?? .current
        return [
            identifier,
            timeZone.localizedName(for: .standard, locale: .current) ?? "",
            timeZone.abbreviation() ?? ""
        ].filter { !$0.isEmpty }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                timeZone: planner.timeZone
            )
        )
    }

    private func runLoginItemAction(_ action: () throws -> Void) {
        do {
            try action()
            loginItemMessage = "Login item settings updated."
        } catch {
            loginItemMessage = error.localizedDescription
        }
    }
}

private struct TimeZoneOption: Identifiable {
    let id: String
    let title: String
    let searchKeywords: String
}
