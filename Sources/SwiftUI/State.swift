// Dynamic properties: State, Binding, ObservedObject, StateObject, Environment and
// EnvironmentObject. Each wrapper owns a reference box; the runtime links the box to the
// owning node's persistent storage before `body` runs.

import Foundation
#if canImport(Combine)
import Combine
#endif

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dynamicproperty
public protocol DynamicProperty {
    /// Called by the runtime before `body`; the default does nothing.
    mutating func update()
    /// Links the property's storage to `node` (runtime use).
    @MainActor func _install(in node: _ViewNode, slot: Int)
}

extension DynamicProperty {
    public mutating func update() {}
    @MainActor public func _install(in node: _ViewNode, slot: Int) {}
}

/// Persistent storage for one `State`/`StateObject` slot of a node.
final class _StorageCell {
    var value: Any
    weak var node: _ViewNode?
    init(_ value: Any) { self.value = value }
}

final class _StateBox<Value> {
    var initial: Value
    var cell: _StorageCell?
    init(_ initial: Value) { self.initial = initial }
    var value: Value {
        get { (cell?.value as? Value) ?? initial }
        set {
            if let cell {
                cell.value = newValue
                MainActor.assumeIsolated { cell.node?.setNeedsUpdate() }
            } else {
                initial = newValue
            }
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/state
@propertyWrapper
public struct State<Value>: DynamicProperty {
    let box: _StateBox<Value>

    public init(wrappedValue value: Value) { box = _StateBox(value) }
    public init(initialValue value: Value) { box = _StateBox(value) }

    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    public var projectedValue: Binding<Value> {
        let b = box
        return Binding(get: { b.value }, set: { b.value = $0 })
    }
    @MainActor public func _install(in node: _ViewNode, slot: Int) {
        let cell = node.storageCell(slot) { _StorageCell(box.initial) }
        cell.node = node
        box.cell = cell
    }
}

extension State where Value: ExpressibleByNilLiteral {
    public init() { self.init(wrappedValue: nil) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/binding
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    let getter: () -> Value
    let setter: (Value) -> Void
    public var transaction = Transaction()

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = set
    }
    public init(get: @escaping () -> Value, set: @escaping (Value, Transaction) -> Void) {
        getter = get
        setter = { set($0, Transaction()) }
    }
    public init(projectedValue: Binding<Value>) { self = projectedValue }

    public static func constant(_ value: Value) -> Binding<Value> { Binding(get: { value }, set: { _ in }) }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
    public var projectedValue: Binding<Value> { self }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(get: { self.wrappedValue[keyPath: keyPath] }, set: { var v = self.wrappedValue; v[keyPath: keyPath] = $0; self.wrappedValue = v })
    }
}

extension Binding {
    public init<V>(_ base: Binding<V>) where Value == V? { self.init(get: { base.wrappedValue }, set: { if let v = $0 { base.wrappedValue = v } }) }
    public init?(_ base: Binding<Value?>) {
        guard let initial = base.wrappedValue else { return nil }
        self.init(get: { base.wrappedValue ?? initial }, set: { base.wrappedValue = $0 })
    }
}

extension Binding {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/binding/animation(_:)
    public func animation(_ animation: Animation? = .default) -> Binding<Value> {
        Binding(get: getter, set: { v in withAnimation(animation) { self.setter(v) } })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/binding/transaction(_:)
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        Binding(get: getter, set: { v in withTransaction(transaction) { self.setter(v) } })
    }
}

extension Binding: Identifiable where Value: Identifiable {
    public var id: Value.ID { wrappedValue.id }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/transaction
public struct Transaction {
    public var animation: Animation?
    public var disablesAnimations = false
    public init() {}
    public init(animation: Animation?) { self.animation = animation }
}

// MARK: Observable objects

final class _ObservedBox<ObjectType: ObservableObject> {
    var object: ObjectType
    var cancellable: AnyCancellable?
    init(_ object: ObjectType) { self.object = object }
    func subscribe(_ node: _ViewNode) {
        cancellable?.cancel()
        cancellable = object.objectWillChange.sink { [weak node] _ in
            MainActor.assumeIsolated { node?.setNeedsUpdate() }
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/observedobject
@MainActor @preconcurrency @propertyWrapper
public struct ObservedObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    let box: _ObservedBox<ObjectType>
    public init(wrappedValue: ObjectType) { box = _ObservedBox(wrappedValue) }
    public init(initialValue: ObjectType) { box = _ObservedBox(initialValue) }
    public var wrappedValue: ObjectType {
        get { box.object }
        nonmutating set { box.object = newValue }
    }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { Wrapper(object: box.object) }
    @MainActor public func _install(in node: _ViewNode, slot: Int) {
        box.subscribe(node)
        node.retain(box, slot: slot)
    }

    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            let o = object
            return Binding(get: { o[keyPath: keyPath] }, set: { o[keyPath: keyPath] = $0 })
        }
    }
}

final class _StateObjectBox<ObjectType: ObservableObject> {
    let thunk: () -> ObjectType
    var observed: _ObservedBox<ObjectType>?
    init(_ thunk: @escaping () -> ObjectType) { self.thunk = thunk }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/stateobject
@MainActor @preconcurrency @propertyWrapper
public struct StateObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    let box: _StateObjectBox<ObjectType>
    nonisolated public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { box = _StateObjectBox(thunk) }
    public var wrappedValue: ObjectType {
        box.observed?.object ?? {
            // Read before installation (previews, tests): create and keep the object.
            let o = _ObservedBox(box.thunk())
            box.observed = o
            return o.object
        }()
    }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject<ObjectType>.Wrapper(object: wrappedValue) }
    @MainActor public func _install(in node: _ViewNode, slot: Int) {
        let cell = node.storageCell(slot) { _StorageCell(_ObservedBox(box.thunk())) }
        guard let observed = cell.value as? _ObservedBox<ObjectType> else { return }
        observed.subscribe(node)
        box.observed = observed
    }
}

// MARK: Environment

final class _EnvironmentBox<Value> {
    let keyPath: KeyPath<EnvironmentValues, Value>
    var values: EnvironmentValues?
    init(_ keyPath: KeyPath<EnvironmentValues, Value>) { self.keyPath = keyPath }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/environment
@propertyWrapper
public struct Environment<Value>: DynamicProperty {
    let box: _EnvironmentBox<Value>
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { box = _EnvironmentBox(keyPath) }
    public var wrappedValue: Value { (box.values ?? EnvironmentValues())[keyPath: box.keyPath] }
    @MainActor public func _install(in node: _ViewNode, slot: Int) { box.values = node.environment }
}

final class _EnvironmentObjectBox<ObjectType: ObservableObject> {
    var object: ObjectType?
    var cancellable: AnyCancellable?
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentobject
@propertyWrapper
public struct EnvironmentObject<ObjectType>: DynamicProperty where ObjectType: ObservableObject {
    let box = _EnvironmentObjectBox<ObjectType>()
    public init() {}
    public var wrappedValue: ObjectType {
        guard let o = box.object else { fatalError("No ObservableObject of type \(ObjectType.self) found. A View.environmentObject(_:) for \(ObjectType.self) may be missing as an ancestor of this view.") }
        return o
    }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { ObservedObject<ObjectType>.Wrapper(object: wrappedValue) }
    @MainActor public func _install(in node: _ViewNode, slot: Int) {
        guard let o = node.environment._objects[ObjectIdentifier(ObjectType.self)] as? ObjectType else { return }
        box.object = o
        box.cancellable?.cancel()
        box.cancellable = o.objectWillChange.sink { [weak node] _ in MainActor.assumeIsolated { node?.setNeedsUpdate() } }
        node.retain(box, slot: slot)
    }
}

// MARK: Environment values

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentkey
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues
public struct EnvironmentValues {
    var storage: [ObjectIdentifier: Any] = [:]
    var _objects: [ObjectIdentifier: AnyObject] = [:]

    public init() {}

    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get { (storage[ObjectIdentifier(key)] as? K.Value) ?? K.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue }
    }

    private struct FontKey: EnvironmentKey { static let defaultValue: Font? = nil }
    private struct LineSpacingKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
    private struct ImageScaleKey: EnvironmentKey { static let defaultValue: Image.Scale = .medium }
    private struct LabelStyleKey: EnvironmentKey { static let defaultValue: any LabelStyle = DefaultLabelStyle() }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/linespacing
    public var lineSpacing: CGFloat { get { self[LineSpacingKey.self] } set { self[LineSpacingKey.self] = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/imagescale
    public var imageScale: Image.Scale { get { self[ImageScaleKey.self] } set { self[ImageScaleKey.self] = newValue } }
    var _labelStyle: any LabelStyle { get { self[LabelStyleKey.self] } set { self[LabelStyleKey.self] = newValue } }
    private struct ForegroundColorKey: EnvironmentKey { static let defaultValue: Color? = nil }
    private struct ColorSchemeKey: EnvironmentKey { static let defaultValue: ColorScheme = .light }
    private struct IsEnabledKey: EnvironmentKey { static let defaultValue = true }
    private struct LayoutDirectionKey: EnvironmentKey { static let defaultValue: LayoutDirection = .leftToRight }
    private struct DisplayScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
    private struct LocaleKey: EnvironmentKey { static let defaultValue: Locale = .current }
    private struct LineLimitKey: EnvironmentKey { static let defaultValue: Int? = nil }
    private struct MultilineTextAlignmentKey: EnvironmentKey { static let defaultValue: TextAlignment = .leading }
    private struct TruncationModeKey: EnvironmentKey { static let defaultValue: Text.TruncationMode = .tail }
    private struct ControlActiveStateKey: EnvironmentKey { static let defaultValue: ControlActiveState = .inactive }
    private struct MinimumScaleFactorKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
    private struct OpenURLKey: EnvironmentKey { static let defaultValue = OpenURLAction { url in _ = NSWorkspace.shared.open(url) } }
    private struct DismissKey: EnvironmentKey { static let defaultValue = DismissAction {} }

    public var font: Font? { get { self[FontKey.self] } set { self[FontKey.self] = newValue } }
    public var foregroundColor: Color? { get { self[ForegroundColorKey.self] } set { self[ForegroundColorKey.self] = newValue } }
    public var colorScheme: ColorScheme { get { self[ColorSchemeKey.self] } set { self[ColorSchemeKey.self] = newValue } }
    public var isEnabled: Bool { get { self[IsEnabledKey.self] } set { self[IsEnabledKey.self] = newValue } }
    public var layoutDirection: LayoutDirection { get { self[LayoutDirectionKey.self] } set { self[LayoutDirectionKey.self] = newValue } }
    public var displayScale: CGFloat { get { self[DisplayScaleKey.self] } set { self[DisplayScaleKey.self] = newValue } }
    public var locale: Locale { get { self[LocaleKey.self] } set { self[LocaleKey.self] = newValue } }
    public var lineLimit: Int? { get { self[LineLimitKey.self] } set { self[LineLimitKey.self] = newValue } }
    public var multilineTextAlignment: TextAlignment { get { self[MultilineTextAlignmentKey.self] } set { self[MultilineTextAlignmentKey.self] = newValue } }
    public var truncationMode: Text.TruncationMode { get { self[TruncationModeKey.self] } set { self[TruncationModeKey.self] = newValue } }
    public var controlActiveState: ControlActiveState { get { self[ControlActiveStateKey.self] } set { self[ControlActiveStateKey.self] = newValue } }
    public var minimumScaleFactor: CGFloat { get { self[MinimumScaleFactorKey.self] } set { self[MinimumScaleFactorKey.self] = newValue } }
    public var openURL: OpenURLAction { get { self[OpenURLKey.self] } set { self[OpenURLKey.self] = newValue } }
    public var dismiss: DismissAction { get { self[DismissKey.self] } set { self[DismissKey.self] = newValue } }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/colorscheme
public enum ColorScheme: Hashable, CaseIterable, Sendable { case light, dark }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/layoutdirection
public enum LayoutDirection: Hashable, CaseIterable, Sendable { case leftToRight, rightToLeft }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/textalignment
public enum TextAlignment: Hashable, CaseIterable, Sendable { case leading, center, trailing }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/controlactivestate
public enum ControlActiveState: Hashable, CaseIterable, Sendable { case key, active, inactive }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/openurlaction
public struct OpenURLAction {
    let handler: (URL) -> Void
    public init(handler: @escaping (URL) -> Void) { self.handler = handler }
    public func callAsFunction(_ url: URL) { handler(url) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/dismissaction
public struct DismissAction {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    public func callAsFunction() { handler() }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/environment(_:_:)
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        _EnvironmentView(content: self) { $0[keyPath: keyPath] = value }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/environmentobject(_:)
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View {
        _EnvironmentView(content: self) { $0._objects[ObjectIdentifier(T.self)] = object }
    }
}

/// Applies a change to the environment of its content.
struct _EnvironmentView<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let transform: (inout EnvironmentValues) -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        let p = _GroupPrimitive(children: [_ViewBox(content)])
        p.environmentTransform = transform
        return p
    }
}

// MARK: Runtime installation

/// Links every dynamic property found in `value` (recursively through nested value types)
/// to `node`. Wrappers hold reference boxes, so the copies Mirror hands out share them.
@MainActor
func _installDynamicProperties(in value: Any, node: _ViewNode, slot: inout Int) {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .struct || mirror.displayStyle == .tuple else { return }
    for child in mirror.children {
        if let property = child.value as? DynamicProperty {
            property._install(in: node, slot: slot)
            slot += 1
            // A custom DynamicProperty owns dynamic properties of its own (a library's
            // wrapper around @ObservedObject): they are installed too, as Apple's are.
            if Mirror(reflecting: child.value).displayStyle == .struct { _installDynamicProperties(in: child.value, node: node, slot: &slot) }
        } else {
            let m = Mirror(reflecting: child.value)
            if m.displayStyle == .struct, !(child.value is any View) { _installDynamicProperties(in: child.value, node: node, slot: &slot) }
        }
    }
}
