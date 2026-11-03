// AppStorage/SceneStorage over UserDefaults; FocusState with focused(_:) and onSubmit.

import Foundation

// MARK: AppStorage

/// Types AppStorage can store (the property-list types plus raw-representable enums).
public protocol _AppStorageValue {
    static func _read(_ defaults: UserDefaults, _ key: String) -> Self?
    func _write(_ defaults: UserDefaults, _ key: String)
}

extension Bool: _AppStorageValue {
    public static func _read(_ d: UserDefaults, _ k: String) -> Bool? { d.object(forKey: k) == nil ? nil : d.bool(forKey: k) }
    public func _write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension Int: _AppStorageValue {
    public static func _read(_ d: UserDefaults, _ k: String) -> Int? { d.object(forKey: k) == nil ? nil : d.integer(forKey: k) }
    public func _write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension Double: _AppStorageValue {
    public static func _read(_ d: UserDefaults, _ k: String) -> Double? { d.object(forKey: k) == nil ? nil : d.double(forKey: k) }
    public func _write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension String: _AppStorageValue {
    public static func _read(_ d: UserDefaults, _ k: String) -> String? { d.string(forKey: k) }
    public func _write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}
extension URL: _AppStorageValue {
    public static func _read(_ d: UserDefaults, _ k: String) -> URL? { d.string(forKey: k).flatMap { URL(string: $0) } }
    public func _write(_ d: UserDefaults, _ k: String) { d.set(absoluteString, forKey: k) }
}
extension Data: _AppStorageValue {
    public static func _read(_ d: UserDefaults, _ k: String) -> Data? { d.data(forKey: k) }
    public func _write(_ d: UserDefaults, _ k: String) { d.set(self, forKey: k) }
}

final class _AppStorageBox<Value> {
    let key: String
    let store: UserDefaults
    let initial: Value
    let read: (UserDefaults, String) -> Value?
    let write: (Value, UserDefaults, String) -> Void
    weak var node: _ViewNode?
    var observer: NSObjectProtocol?
    init(key: String, store: UserDefaults, initial: Value, read: @escaping (UserDefaults, String) -> Value?, write: @escaping (Value, UserDefaults, String) -> Void) {
        self.key = key; self.store = store; self.initial = initial; self.read = read; self.write = write
    }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }
    var value: Value {
        get { read(store, key) ?? initial }
        set {
            write(newValue, store, key)
            MainActor.assumeIsolated { node?.setNeedsUpdate() }
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/appstorage
@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    let box: _AppStorageBox<Value>

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: _AppStorageValue {
        box = _AppStorageBox(key: key, store: store ?? .standard, initial: wrappedValue, read: { Value._read($0, $1) }, write: { $0._write($1, $2) })
    }
    public init<R: _AppStorageValue>(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == R {
        box = _AppStorageBox(key: key, store: store ?? .standard, initial: wrappedValue,
                             read: { R._read($0, $1).flatMap { Value(rawValue: $0) } }, write: { $0.rawValue._write($1, $2) })
    }
    public init<W: _AppStorageValue>(_ key: String, store: UserDefaults? = nil) where Value == W? {
        box = _AppStorageBox(key: key, store: store ?? .standard, initial: nil,
                             read: { W._read($0, $1) }, write: { v, d, k in if let v { v._write(d, k) } else { d.removeObject(forKey: k) } })
    }

    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    public var projectedValue: Binding<Value> {
        let b = box
        return Binding(get: { b.value }, set: { b.value = $0 })
    }
    @MainActor public func _install(in node: _ViewNode, slot: Int) {
        box.node = node
        if box.observer == nil {
            box.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: box.store, queue: nil) { [weak box] _ in
                MainActor.assumeIsolated { box?.node?.setNeedsUpdate() }
            }
        }
        node.retain(box, slot: slot)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scenestorage
@propertyWrapper
public struct SceneStorage<Value>: DynamicProperty {
    let storage: AppStorage<Value>
    public init(wrappedValue: Value, _ key: String) where Value: _AppStorageValue { storage = AppStorage(wrappedValue: wrappedValue, "scene." + key) }
    public init<R: _AppStorageValue>(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == R { storage = AppStorage(wrappedValue: wrappedValue, "scene." + key) }
    public var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }
    public var projectedValue: Binding<Value> { storage.projectedValue }
    @MainActor public func _install(in node: _ViewNode, slot: Int) { storage._install(in: node, slot: slot) }
}

// MARK: FocusState

final class _FocusBox<Value: Hashable> {
    var cell: _StorageCell?
    let initial: Value
    init(_ initial: Value) { self.initial = initial }
    var value: Value {
        get { (cell?.value as? Value) ?? initial }
        set {
            if let cell {
                guard (cell.value as? Value) != newValue else { return }
                cell.value = newValue
                MainActor.assumeIsolated { cell.node?.setNeedsUpdate() }
            }
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/focusstate
@propertyWrapper
public struct FocusState<Value: Hashable>: DynamicProperty {
    let box: _FocusBox<Value>

    public init() where Value == Bool { box = _FocusBox(false) }
    public init<T: Hashable>() where Value == T? { box = _FocusBox(nil) }

    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    public var projectedValue: FocusState<Value>.Binding { Binding(box: box) }

    @MainActor public func _install(in node: _ViewNode, slot: Int) {
        let cell = node.storageCell(slot) { _StorageCell(box.initial) }
        cell.node = node
        box.cell = cell
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/focusstate/binding
    @propertyWrapper
    public struct Binding {
        let box: _FocusBox<Value>
        public var wrappedValue: Value {
            get { box.value }
            nonmutating set { box.value = newValue }
        }
        public var projectedValue: Binding { self }
    }
}

/// Keeps a focusable AppKit view (a text field) in step with a FocusState value.
@MainActor
final class _FocusedPrimitive<Value: Hashable>: _Primitive {
    var binding: FocusState<Value>.Binding
    var value: Value
    var unfocused: Value
    private var observers: [NSObjectProtocol] = []
    private weak var field: NSTextField?

    init(binding: FocusState<Value>.Binding, value: Value, unfocused: Value, content: _AnyViewBox) {
        self.binding = binding; self.value = value; self.unfocused = unfocused
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _FocusedPrimitive<Value> else { return }
        binding = o.binding; value = o.value; unfocused = o.unfocused
        sync()
    }
    override func detach() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
    }
    override func didLayout(node: _ViewNode) { sync() }

    /// The first text field under this node.
    private func findField(_ node: _ViewNode) -> NSTextField? {
        if let f = node.primitive?.nsView as? NSTextField { return f }
        for c in node.children { if let f = findField(c) { return f } }
        return nil
    }

    private func sync() {
        guard let node, let f = findField(node) else { return }
        if field !== f {
            field = f
            for o in observers { NotificationCenter.default.removeObserver(o) }
            observers = [
                NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: f, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { guard let self else { return }; if self.binding.wrappedValue != self.value { self.binding.wrappedValue = self.value } }
                },
                NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: f, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { guard let self else { return }; if self.binding.wrappedValue == self.value { self.binding.wrappedValue = self.unfocused } }
                },
            ]
        }
        let wantsFocus = binding.wrappedValue == value
        let hasFocus = f.currentEditor != nil
        if wantsFocus && !hasFocus, let w = f.window {
            _ = w.makeFirstResponder(f)
        } else if !wantsFocus && hasFocus, let w = f.window, w.firstResponder === f.currentEditor {
            _ = w.makeFirstResponder(nil)
        }
    }
}

struct _Focused<Content: View, Value: Hashable>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let binding: FocusState<Value>.Binding
    let value: Value
    let unfocused: Value
    func _makePrimitive(node: _ViewNode) -> _Primitive { _FocusedPrimitive(binding: binding, value: value, unfocused: unfocused, content: _ViewBox(content)) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/focused(_:equals:)
    public func focused<Value: Hashable>(_ binding: FocusState<Value?>.Binding, equals value: Value) -> some View {
        _Focused(content: self, binding: binding, value: Optional(value), unfocused: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/focused(_:)
    public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        _Focused(content: self, binding: condition, value: true, unfocused: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/focusable(_:)
    public func focusable(_ isFocusable: Bool = true) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onsubmit(of:_:)
    public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        environment(\._onSubmit, _SubmitAction(action))
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/submittriggers
public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1)
    public static let search = SubmitTriggers(rawValue: 2)
}

struct _SubmitAction { let run: () -> Void; init(_ run: @escaping () -> Void) { self.run = run } }

extension EnvironmentValues {
    private struct SubmitKey: EnvironmentKey { static let defaultValue: _SubmitAction? = nil }
    var _onSubmit: _SubmitAction? { get { self[SubmitKey.self] } set { self[SubmitKey.self] = newValue } }
}
