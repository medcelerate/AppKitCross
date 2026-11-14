import DailyTodoCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newItemTitle = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                newItemField
                todoList
                footer
            }
            .frame(minWidth: 560, minHeight: 420)
            .navigationTitle("Daily To Do")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var header: some View {
        HStack {
            DatePicker(
                "Day",
                selection: $store.selectedDay,
                displayedComponents: .date
            )
            .datePickerStyle(.field)

            Spacer()

            Button("Today") {
                store.selectedDay = store.planner.today()
            }
        }
        .padding()
    }

    private var newItemField: some View {
        HStack(spacing: 8) {
            TextField("Add a task", text: $newItemTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addItem)

            Button("Add", action: addItem)
                .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding([.horizontal, .bottom])
    }

    private var todoList: some View {
        List {
            ForEach(store.itemsForSelectedDay) { item in
                TodoRowView(item: item)
            }
        }
        .listStyle(.inset)
        .overlay {
            if store.itemsForSelectedDay.isEmpty {
                ContentUnavailableView(
                    "No tasks",
                    systemImage: "checkmark.circle",
                    description: Text("Add a task for the selected day.")
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(store.pendingCountForSelectedDay) pending")
                .foregroundStyle(.secondary)

            Spacer()

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private func addItem() {
        store.add(newItemTitle)
        newItemTitle = ""
    }
}

private struct TodoRowView: View {
    @EnvironmentObject private var store: AppStore
    let item: TodoItem

    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { item.isCompleted },
                    set: { store.setCompleted(item.id, isCompleted: $0) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if item.deferredCount > 0 {
                    Text("Deferred \(item.deferredCount) time\(item.deferredCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                store.deferItem(item.id)
            } label: {
                Label("Move to next working day", systemImage: "arrow.right.circle")
            }
            .disabled(item.isCompleted)
            .help("Move this task to the next working day")
        }
        .padding(.vertical, 3)
    }
}
