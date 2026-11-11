// Observable: SwiftUI driven by an ObservableObject model with @Published properties (the
// port has no Observation framework, so `@Observable` is not available; see README), a
// list that updates live, a detail pane editing the selected item, and a Combine timer
// feeding the model. Same source on macOS, Windows and Linux.

import SwiftUI
import Combine

struct Vehicle: Identifiable, Equatable {
    let id: Int
    var name: String
    var speed: Double        // km/h
    var distance: Double     // km
    var isMoving: Bool
}

final class FleetModel: ObservableObject {
    @Published var vehicles: [Vehicle] = [
        Vehicle(id: 1, name: "Courier", speed: 48, distance: 0, isMoving: true),
        Vehicle(id: 2, name: "Van", speed: 72, distance: 12, isMoving: true),
        Vehicle(id: 3, name: "Truck", speed: 0, distance: 95, isMoving: false),
    ]
    @Published var selection: Int? = 1
    @Published var isRunning = true
    @Published var ticks = 0
    @Published var lastTick = Date()
    private var nextID = 4
    private var timer: AnyCancellable?

    init() {
        // A Combine timer on the main run loop drives the model once a second.
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tick(at: date) }
    }

    func tick(at date: Date) {
        guard isRunning else { return }
        ticks += 1
        lastTick = date
        for i in vehicles.indices where vehicles[i].isMoving {
            vehicles[i].distance += vehicles[i].speed / 3600 * 60   // one tick stands for a minute
            vehicles[i].speed = max(0, min(120, vehicles[i].speed + Double((ticks * 7 + i * 13) % 11 - 5)))
        }
    }

    func add() {
        vehicles.append(Vehicle(id: nextID, name: "Vehicle \(nextID)", speed: 30, distance: 0, isMoving: true))
        selection = nextID
        nextID += 1
    }

    func removeSelected() {
        guard let id = selection, let i = vehicles.firstIndex(where: { $0.id == id }) else { return }
        vehicles.remove(at: i)
        selection = vehicles.first?.id
    }

    /// A binding into one vehicle, so the detail pane edits the model in place.
    func binding(for id: Int) -> Binding<Vehicle>? {
        guard let i = vehicles.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { self.vehicles[i] }, set: { self.vehicles[i] = $0 })
    }
}

struct DetailPane: View {
    @Binding var vehicle: Vehicle
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(vehicle.name).font(.title)
            TextField("Name", text: $vehicle.name)
            HStack {
                Text("Speed")
                Slider(value: $vehicle.speed, in: 0...120).accessibilityLabel("Speed")
                Text("\(Int(vehicle.speed)) km/h").frame(width: 70, alignment: .trailing)
            }
            Toggle("Moving", isOn: $vehicle.isMoving)
            Text(String(format: "Distance: %.1f km", vehicle.distance))
            // A bar that grows with the distance (wraps every 200 km).
            RoundedRectangle(cornerRadius: 4)
                .fill(vehicle.isMoving ? Color.green : Color.gray)
                .frame(width: max(4, CGFloat(vehicle.distance.truncatingRemainder(dividingBy: 200)) * 1.5), height: 10)
            Spacer()
        }
        .padding(12)
    }
}

struct FleetView: View {
    @StateObject private var model = FleetModel()
    static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("Running", isOn: $model.isRunning)
                Button("Add") { model.add() }
                Button("Remove") { model.removeSelected() }.disabled(model.selection == nil)
                Spacer()
                Text("tick \(model.ticks) at \(FleetView.clock.string(from: model.lastTick))").foregroundColor(.secondary)
            }
            .padding(10)
            Divider()
            HStack(spacing: 0) {
                List(model.vehicles, selection: $model.selection) { v in
                    HStack {
                        Circle().fill(v.isMoving ? Color.green : Color.gray).frame(width: 10, height: 10)
                        Text(v.name)
                        Spacer()
                        Text(String(format: "%.1f km", v.distance)).foregroundColor(.secondary)
                    }
                }
                .frame(width: 240)
                Divider()
                if let id = model.selection, let binding = model.binding(for: id) {
                    DetailPane(vehicle: binding).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Select a vehicle").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 320)
    }
}

@main
struct ObservableApp: App {
    var body: some Scene {
        WindowGroup("Observable") {
            FleetView()
        }
    }
}
