// Observation-driven views (ADR-0050): `@Observable` models update the views that read
// them. Every body evaluation and primitive construction runs inside
// `withObservationTracking`; the first change to any observable property the pass read
// marks the node stale, and the host re-runs it at the next display cycle, as Apple's
// SwiftUI does since macOS 14. The `Observation` module ships with every Swift 5.9+
// toolchain (Windows and Linux included), so the macro and the tracking work on all three
// platforms; the port's floor (macOS 14) is Observation's.

import Foundation
import Observation

/// Runs `body` with observation tracking; a change to anything it read re-renders `node`.
@MainActor
func _trackingObservation<T>(_ node: _ViewNode, _ body: () -> T) -> T {
    withObservationTracking(body) { [weak node] in
        // `onChange` runs on the mutating thread, before the new value is stored
        // (`willSet`); the update is scheduled, so the body reads the stored value.
        if Thread.isMainThread {
            MainActor.assumeIsolated { node?.setNeedsUpdate() }
        } else {
            DispatchQueue.main.async { node?.setNeedsUpdate() }
        }
    }
}

// MARK: Environment

extension Environment where Value: AnyObject, Value: Observable {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environment/init(_:)-8slkf
    public init(_ objectType: Value.Type) {
        self.init(box: _EnvironmentBox(read: { values in
            guard let o = values._objects[ObjectIdentifier(objectType)] as? Value else {
                fatalError("No Observable object of type \(objectType) found. A View.environment(_:) for \(objectType) may be missing as an ancestor of this view.")
            }
            return o
        }))
    }
}

extension Environment {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environment/init(_:)-6dm9r
    public init<T>(_ objectType: T.Type) where Value == T?, T: AnyObject, T: Observable {
        self.init(box: _EnvironmentBox(read: { $0._objects[ObjectIdentifier(objectType)] as? T }))
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/environment(_:)
    public func environment<T>(_ object: T?) -> some View where T: AnyObject, T: Observable {
        _EnvironmentView(content: self) { $0._objects[ObjectIdentifier(T.self)] = object }
    }
}

// MARK: Bindable

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/bindable
@dynamicMemberLookup @propertyWrapper
public struct Bindable<Value> {
    public var wrappedValue: Value
    public var projectedValue: Bindable<Value> { self }
    // Declared in the body so no internal memberwise initializer is synthesized.
    public init(wrappedValue: Value) where Value: AnyObject, Value: Observable { self.wrappedValue = wrappedValue }
}

extension Bindable where Value: AnyObject {
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let o = wrappedValue
        return Binding(get: { o[keyPath: keyPath] }, set: { o[keyPath: keyPath] = $0 })
    }
}

extension Bindable where Value: AnyObject, Value: Observable {
    public init(_ wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(projectedValue: Bindable<Value>) { self = projectedValue }
}

extension Bindable: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

extension Bindable: Sendable where Value: Sendable {}

extension Bindable: DynamicProperty where Value: AnyObject, Value: Observable {}
