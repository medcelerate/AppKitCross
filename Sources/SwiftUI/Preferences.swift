// Preferences: values that flow up the view tree (PreferenceKey, preference,
// anchorPreference, onPreferenceChange) and the anchors that resolve to geometry after
// layout. The root collects them after every layout pass (Runtime.swift).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/preferencekey
public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}

extension PreferenceKey where Value: ExpressibleByNilLiteral {
    public static var defaultValue: Value { nil }
}

// MARK: Anchors

extension Anchor.Source where Value == CGRect {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/anchor/source/bounds
    public static var bounds: Anchor<CGRect>.Source { Anchor<CGRect>.Source { $0 } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/anchor/source/rect(_:)
    public static func rect(_ r: CGRect) -> Anchor<CGRect>.Source { Anchor<CGRect>.Source { $0.offsetBy(dx: r.minX, dy: r.minY).withSize(r.size) } }
}

extension Anchor.Source where Value == CGPoint {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/anchor/source/point(_:)
    public static func point(_ p: CGPoint) -> Anchor<CGPoint>.Source { Anchor<CGPoint>.Source { CGPoint(x: $0.minX + p.x, y: $0.minY + p.y) } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/anchor/source/unitpoint(_:)
    public static func unitPoint(_ p: UnitPoint) -> Anchor<CGPoint>.Source { Anchor<CGPoint>.Source { CGPoint(x: $0.minX + p.x * $0.width, y: $0.minY + p.y * $0.height) } }
    public static var topLeading: Anchor<CGPoint>.Source { unitPoint(.topLeading) }
    public static var top: Anchor<CGPoint>.Source { unitPoint(.top) }
    public static var topTrailing: Anchor<CGPoint>.Source { unitPoint(.topTrailing) }
    public static var leading: Anchor<CGPoint>.Source { unitPoint(.leading) }
    public static var center: Anchor<CGPoint>.Source { unitPoint(.center) }
    public static var trailing: Anchor<CGPoint>.Source { unitPoint(.trailing) }
    public static var bottomLeading: Anchor<CGPoint>.Source { unitPoint(.bottomLeading) }
    public static var bottom: Anchor<CGPoint>.Source { unitPoint(.bottom) }
    public static var bottomTrailing: Anchor<CGPoint>.Source { unitPoint(.bottomTrailing) }
}

extension CGRect {
    fileprivate func withSize(_ s: CGSize) -> CGRect { CGRect(origin: origin, size: s) }
}

// MARK: Modifiers

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/preference(key:value:)
    public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
        _PreferenceView(content: self, primitive: { _PreferencePrimitive(key: K.self, value: { _ in value }, content: $0) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/anchorpreference(key:value:transform:)
    public func anchorPreference<A, K: PreferenceKey>(key _: K.Type = K.self, value: Anchor<A>.Source, transform: @escaping (Anchor<A>) -> K.Value) -> some View {
        _PreferenceView(content: self, primitive: { _PreferencePrimitive(key: K.self, value: { transform(Anchor(value: value.resolve($0.frame))) }, content: $0) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/transformpreference(_:_:)
    public func transformPreference<K: PreferenceKey>(_ key: K.Type = K.self, _ callback: @escaping (inout K.Value) -> Void) -> some View {
        _PreferenceView(content: self, primitive: { _PreferencePrimitive(key: K.self, transform: callback, content: $0) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onpreferencechange(_:perform:)
    public func onPreferenceChange<K: PreferenceKey>(_ key: K.Type = K.self, perform action: @escaping (K.Value) -> Void) -> some View where K.Value: Equatable {
        _PreferenceView(content: self, primitive: { _OnPreferenceChangePrimitive(key: K.self, action: action, content: $0) })
    }
}

struct _PreferenceView<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let primitive: @MainActor (_AnyViewBox) -> _Primitive
    func _makePrimitive(node: _ViewNode) -> _Primitive { primitive(_ViewBox(content)) }
}

/// Sets (or transforms) one preference for its subtree; the value is read after layout so
/// anchors can resolve against the node's frame.
@MainActor
final class _PreferencePrimitive: _Primitive {
    let key: ObjectIdentifier
    /// The value for the subtree, or a transform of the value the subtree produced.
    var value: ((_ViewNode) -> Any)?
    var transform: ((inout Any) -> Void)?
    let reduce: (inout Any, Any) -> Void
    let defaultValue: Any

    init<K: PreferenceKey>(key: K.Type, value: @escaping (_ViewNode) -> Any, content: _AnyViewBox) {
        self.key = ObjectIdentifier(K.self)
        self.value = value
        reduce = { acc, next in var a = acc as! K.Value; K.reduce(value: &a, nextValue: { next as! K.Value }); acc = a }
        defaultValue = K.defaultValue
        super.init()
        children = [content]
    }
    init<K: PreferenceKey>(key: K.Type, transform: @escaping (inout K.Value) -> Void, content: _AnyViewBox) {
        self.key = ObjectIdentifier(K.self)
        self.transform = { v in var t = v as! K.Value; transform(&t); v = t }
        reduce = { acc, next in var a = acc as! K.Value; K.reduce(value: &a, nextValue: { next as! K.Value }); acc = a }
        defaultValue = K.defaultValue
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _PreferencePrimitive else { return }
        value = o.value; transform = o.transform
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); node.root?.usesPreferences = true }
}

/// Calls its action when the subtree's value for a key changes.
@MainActor
final class _OnPreferenceChangePrimitive: _Primitive {
    let key: ObjectIdentifier
    var action: (Any) -> Void
    let isEqual: (Any, Any) -> Bool
    let defaultValue: Any
    var last: Any?

    init<K: PreferenceKey>(key: K.Type, action: @escaping (K.Value) -> Void, content: _AnyViewBox) where K.Value: Equatable {
        self.key = ObjectIdentifier(K.self)
        self.action = { action($0 as! K.Value) }
        isEqual = { ($0 as? K.Value) == ($1 as? K.Value) }
        defaultValue = K.defaultValue
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _OnPreferenceChangePrimitive { action = o.action }
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); node.root?.usesPreferences = true }
}

extension _ViewRoot {
    /// Collects the preferences of the laid-out tree (children in order, reduced per key;
    /// a `preference` modifier replaces its subtree's value) and delivers the changed
    /// ones to their `onPreferenceChange` handlers, after the walk.
    func deliverPreferences() {
        guard usesPreferences, let root = rootNode else { return }
        var pending: [() -> Void] = []
        var reducers: [ObjectIdentifier: (inout Any, Any) -> Void] = [:]
        @MainActor func collect(_ n: _ViewNode) -> [ObjectIdentifier: Any] {
            var mine: [ObjectIdentifier: Any] = [:]
            for c in n.children {
                for (k, v) in collect(c) {
                    if let existing = mine[k], let r = reducers[k] { var acc = existing; r(&acc, v); mine[k] = acc }
                    else { mine[k] = v }
                }
            }
            if let p = n.primitive as? _PreferencePrimitive {
                reducers[p.key] = p.reduce
                if let value = p.value { mine[p.key] = value(n) }
                else if let t = p.transform { var v = mine[p.key] ?? p.defaultValue; t(&v); mine[p.key] = v }
            }
            if let p = n.primitive as? _PreferenceValuePrimitive {
                let v = mine[p.key] ?? p.defaultValue
                pending.append { p.deliver(v) }
            }
            if let o = n.primitive as? _OnPreferenceChangePrimitive {
                let v = mine[o.key] ?? o.defaultValue
                if o.last == nil || !o.isEqual(o.last!, v) {
                    o.last = v
                    let action = o.action
                    pending.append { action(v) }
                }
            }
            return mine
        }
        _ = collect(root)
        for p in pending { p() }
    }
}
