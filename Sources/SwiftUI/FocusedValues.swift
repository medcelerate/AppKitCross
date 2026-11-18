// Focused values: `FocusedValueKey`, `FocusedValues`, `@FocusedValue`, `@FocusedBinding` and
// the `focusedValue(_:_:)` / `focusedSceneValue(_:_:)` modifiers that publish them, so
// commands (menu items) act on the focused window's content.
//
// Each publishing view writes its value into a central table, tagged with the view's
// hosting root; a reader sees the values of the key window (or the window a key sheet is
// attached to), falling back to the main window when a panel is key. When what a reader
// would see changes (the key window changes, a key appears or goes, or an equatable value
// changes) the app's menu bar is rebuilt, so `CommandGroup` items re-evaluate their
// `disabled` and titles, and views reading `@FocusedValue` update.
//
// Simplification: `focusedValue(_:_:)` publishes while its window is key, whatever view
// inside the window has focus (SwiftUI publishes it only while the focus is inside the
// modified view); `focusedSceneValue` matches SwiftUI. A changed `Binding` does not count
// as a change (bindings are not comparable); the binding reads the current value anyway.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/focusedvaluekey
public protocol FocusedValueKey {
    associatedtype Value
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/focusedvalues
public struct FocusedValues {
    var storage: [ObjectIdentifier: Any] = [:]
    init() {}
    public subscript<Key: FocusedValueKey>(key: Key.Type) -> Key.Value? {
        get { storage[ObjectIdentifier(key)] as? Key.Value }
        set { storage[ObjectIdentifier(key)] = newValue }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/focusedvalue
@propertyWrapper
public struct FocusedValue<Value>: DynamicProperty {
    let keyPath: KeyPath<FocusedValues, Value?>
    public init(_ keyPath: KeyPath<FocusedValues, Value?>) { self.keyPath = keyPath }
    public var wrappedValue: Value? {
        let kp = keyPath
        return MainActor.assumeIsolated { _FocusedValuesCenter.shared.current[keyPath: kp] }
    }
    @MainActor public func _install(in node: _ViewNode, slot: Int) { _FocusedValuesCenter.shared.subscribe(node) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/focusedbinding
@propertyWrapper
public struct FocusedBinding<Value>: DynamicProperty {
    let keyPath: KeyPath<FocusedValues, Binding<Value>?>
    public init(_ keyPath: KeyPath<FocusedValues, Binding<Value>?>) { self.keyPath = keyPath }
    var binding: Binding<Value>? {
        let kp = keyPath
        return MainActor.assumeIsolated { _FocusedValuesCenter.shared.current[keyPath: kp] }
    }
    public var wrappedValue: Value? {
        get { binding?.wrappedValue }
        nonmutating set { if let v = newValue { binding?.wrappedValue = v } }
    }
    public var projectedValue: Binding<Value?> {
        let me = self
        return Binding(get: { me.wrappedValue }, set: { me.wrappedValue = $0 })
    }
    @MainActor public func _install(in node: _ViewNode, slot: Int) { _FocusedValuesCenter.shared.subscribe(node) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/focusedvalue(_:_:)
    public func focusedValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value) -> some View {
        var values = FocusedValues()
        values[keyPath: keyPath] = value
        return _FocusedValuePublisher(content: self, values: values)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/focusedscenevalue(_:_:)
    public func focusedSceneValue<T>(_ keyPath: WritableKeyPath<FocusedValues, T?>, _ value: T) -> some View {
        var values = FocusedValues()
        values[keyPath: keyPath] = value
        return _FocusedValuePublisher(content: self, values: values)
    }
}

struct _FocusedValuePublisher<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let values: FocusedValues
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _FocusedValuesCenter.shared.publish(values, from: node)
        return _GroupPrimitive(children: [_ViewBox(content)])
    }
}

/// The table of published values and the readers to tell when it changes.
@MainActor
final class _FocusedValuesCenter {
    static let shared = _FocusedValuesCenter()

    private struct Entry {
        weak var node: _ViewNode?
        weak var root: _ViewRoot?
        let key: ObjectIdentifier
        var value: Any
    }
    private var entries: [Entry] = []
    private var readers: [WeakNode] = []
    private struct WeakNode { weak var node: _ViewNode? }
    private var lastSignature: [ObjectIdentifier: AnyHashable] = [:]
    private var refreshScheduled = false
    private var observers: [any NSObjectProtocol] = []
    /// Test hook: how many times the menu bar was rebuilt for a focus change.
    static var _menuRefreshCount = 0

    private init() {
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { _ in
                MainActor.assumeIsolated { _FocusedValuesCenter.shared.scheduleRefresh() }
            })
        }
    }

    /// The window whose values readers see: the key window, the window a key sheet is
    /// attached to when the sheet publishes nothing, else the main window.
    private var focusedWindows: [NSWindow] {
        var out: [NSWindow] = []
        let app = NSApplication.shared
        if let key = app.keyWindow {
            var w: NSWindow? = key
            while let window = w { out.append(window); w = window.sheetParent }
        }
        if let main = app.mainWindow, !out.contains(where: { $0 === main }) { out.append(main) }
        return out
    }

    var current: FocusedValues {
        entries.removeAll { $0.node == nil || $0.root == nil }
        var values = FocusedValues()
        for window in focusedWindows {
            let here = entries.filter { $0.root?.host?.hostView.window === window }
            guard !here.isEmpty else { continue }
            for e in here where values.storage[e.key] == nil { values.storage[e.key] = e.value }
            break
        }
        return values
    }

    func publish(_ values: FocusedValues, from node: _ViewNode) {
        for (key, value) in values.storage {
            if let i = entries.firstIndex(where: { $0.node === node && $0.key == key }) {
                entries[i].value = value
                entries[i].root = node.root
            } else {
                entries.append(Entry(node: node, root: node.root, key: key, value: value))
            }
        }
        scheduleRefresh()
    }

    func subscribe(_ node: _ViewNode) {
        readers.removeAll { $0.node == nil }
        if !readers.contains(where: { $0.node === node }) { readers.append(WeakNode(node: node)) }
    }

    /// What a reader would see, comparable: each present key with its value when that is
    /// hashable, else the publishing node.
    private func signature() -> [ObjectIdentifier: AnyHashable] {
        entries.removeAll { $0.node == nil || $0.root == nil }
        var out: [ObjectIdentifier: AnyHashable] = [:]
        for window in focusedWindows {
            let here = entries.filter { $0.root?.host?.hostView.window === window }
            guard !here.isEmpty else { continue }
            for e in here where out[e.key] == nil {
                out[e.key] = (e.value as? AnyHashable) ?? AnyHashable(ObjectIdentifier(e.node!))
            }
            break
        }
        return out
    }

    func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated { _FocusedValuesCenter.shared.refreshIfChanged() }
        }
    }

    func refreshIfChanged() {
        refreshScheduled = false
        let now = signature()
        guard now != lastSignature else { return }
        lastSignature = now
        _FocusedValuesCenter._menuRefreshCount += 1
        if let runner = _AppRunner._current, NSApplication.shared.mainMenu != nil { runner.installMenuBar() }
        readers.removeAll { $0.node == nil }
        for r in readers { r.node?.setNeedsUpdate() }
    }
}
