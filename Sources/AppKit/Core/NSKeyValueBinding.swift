// Cocoa bindings without the Objective-C runtime (ADR-0032).
//
// AppKit's bindings sit on Foundation's key-value coding (`value(forKeyPath:)`) and key-value
// observing. swift-corelibs-foundation has neither, so the port carries its own small layer
// that every platform uses:
//
// - `_KVC` reads and writes key paths. It understands the controllers and proxies in this
//   module, objects that adopt `NSKeyValueBindingCoding` (additive API), dictionaries, arrays
//   (a key applied to an array maps over its elements; `@count`, `@sum`, `@avg`, `@min`,
//   `@max`), on Apple's Foundation any NSObject that answers the key through real KVC, and
//   otherwise stored properties found by reflection (`Mirror`).
// - `_KVO` is an observation hub keyed by object identity and key. The controllers post to it
//   directly. A model announces a change with `didChangeValue(forKey:)` — Foundation's own
//   method on macOS, where a bridge observer forwards real KVO into the hub, and an
//   equivalent `NSObject` extension elsewhere — and every write made through a binding is
//   announced automatically.
// - `_KeyPathObservation` follows a multi-component key path ("selection.name",
//   "arrangedObjects.title"), re-observing intermediate objects (and every element of an
//   intermediate array) whenever an earlier component changes.
// - `NSObject.bind(_:to:withKeyPath:options:)` records an `_NSBinding`, observes the key path
//   and hands each new value to the receiver: views and controllers that adopt
//   `_NSBindingTarget` apply the bindings they define, anything else is set through `_KVC`
//   under the binding's name, as NSObject's default implementation does on macOS.

import Foundation
#if canImport(ObjectiveC)
import ObjectiveC
#endif

// MARK: - Public additive API

/// Key-value coding for model objects on platforms without the Objective-C runtime
/// (additive API; macOS objects get the same from Foundation's key-value coding).
///
/// Bindings read model properties by reflection, which sees stored properties only; adopt this
/// protocol to expose computed properties or to make properties writable through a binding.
/// After changing a property outside a binding, call `didChangeValue(forKey:)` so bound views
/// update.
public protocol NSKeyValueBindingCoding: AnyObject {
    /// The value for `key`.
    func bindingValue(forKey key: String) -> Any?
    /// Stores `value` for `key` (a bound view was edited).
    func setBindingValue(_ value: Any?, forKey key: String)
}

extension NSKeyValueBindingCoding {
    /// Read-only adopters: writing raises, as key-value coding does for an undefined key.
    public func setBindingValue(_ value: Any?, forKey key: String) { _KVC.undefinedKey(self, key, setting: true) }
}

#if !canImport(ObjectiveC)
extension NSObject {
    /// Announces an imminent change of `key` (Foundation's key-value observing API; there is no
    /// automatic change notification without the Objective-C runtime).
    public func willChangeValue(forKey key: String) { }
    /// Announces that `key` changed: bound views and controllers observing it update.
    public func didChangeValue(forKey key: String) { _KVO.didChange(self, key: key) }
}
#endif

// MARK: - Internal key-value coding

/// Objects in this module that answer key-value coding themselves (controllers, the selection
/// proxy, tree nodes, the user-defaults values proxy). They post their own changes to `_KVO`.
protocol _NSKeyValueCodingInternal: AnyObject {
    /// The value for `key`, or `nil` (outer) when the object has no such key.
    func _kvcValue(forKey key: String) -> Any??
    /// Stores `value`; false when the key is not settable.
    func _kvcSetValue(_ value: Any?, forKey key: String) -> Bool
}

/// Observation forwarding: observing `key` on the receiver also observes `key` on these
/// objects (the selection proxy forwards to the selected objects).
protocol _NSKeyValueObservationForwarding: AnyObject {
    func _forwardedObservationTargets(forKey key: String) -> [AnyObject]
}

enum _KVC {
    /// The components of a key path; an `@operator` swallows the rest of the path.
    static func components(_ keyPath: String) -> [String] {
        var out: [String] = []
        let parts = keyPath.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < parts.count {
            if parts[i].hasPrefix("@") {
                out.append(parts[i...].joined(separator: "."))
                break
            }
            out.append(parts[i])
            i += 1
        }
        return out
    }

    static func value(_ object: Any?, forKeyPath keyPath: String) -> Any? {
        var current: Any? = object
        for key in components(keyPath) {
            guard let c = current else { return nil }
            current = value(c, forKey: key)
        }
        return current
    }

    static func value(_ object: Any?, forKey key: String) -> Any? {
        guard let object = flatten(object), !(object is NSNull) else { return nil }
        if let o = object as? _NSKeyValueCodingInternal, let v = o._kvcValue(forKey: key) { return v }
        if let o = object as? NSKeyValueBindingCoding { return flatten(o.bindingValue(forKey: key)) }
        if let a = arrayValue(object) { return arrayValue(a, forKey: key) }
        // A Foundation dictionary is read as itself: casting it to a Swift dictionary first would
        // bridge nested Foundation objects into value types (and lose their identity) on corelibs.
        if isObject(object), let d = object as? NSDictionary { return flatten(d.object(forKey: key)) }
        if let d = object as? [String: Any] { return flatten(d[key]) }
        #if canImport(ObjectiveC)
        if let o = object as? NSObject, o.responds(to: NSSelectorFromString(key)) { return flatten(o.value(forKey: key)) }
        #endif
        let (found, v) = reflected(object, key)
        if found { return v }
        undefinedKey(object, key, setting: false)
    }

    /// Writes `value` at `keyPath` and announces the change on the object that owns the last key.
    static func setValue(_ value: Any?, on object: Any?, forKeyPath keyPath: String) {
        let comps = components(keyPath)
        guard let last = comps.last else { return }
        var target: Any? = object
        for key in comps.dropLast() { target = self.value(target, forKey: key) }
        guard let target = flatten(target) else { return }
        if let a = arrayValue(target) {
            for element in a { setValue(value, on: element, forKeyPath: last) }
            return
        }
        setValue(value, on: target, forKey: last)
    }

    static func setValue(_ value: Any?, on object: Any, forKey key: String) {
        if let o = object as? _NSKeyValueCodingInternal, o._kvcSetValue(value, forKey: key) { return }
        if let o = object as? NSKeyValueBindingCoding {
            o.setBindingValue(value, forKey: key)
            _KVO.didChange(o, key: key)
            return
        }
        if let d = object as? NSMutableDictionary {
            if let value { d.setObject(value, forKey: key as NSString) } else { d.removeObject(forKey: key as NSString) }
            _KVO.didChange(d, key: key)
            return
        }
        #if canImport(ObjectiveC)
        if let o = object as? NSObject {
            let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
            if o.responds(to: NSSelectorFromString(setter)) {
                o.setValue(value, forKey: key)
                // Real KVO tells the hub when the property is dynamic; a plain @objc property
                // is announced here (an extra notification for a dynamic one is harmless).
                _KVO.didChange(o, key: key)
                return
            }
        }
        #endif
        undefinedKey(object, key, setting: true)
    }

    /// Key-value coding raises for an undefined key; so does the port.
    static func undefinedKey(_ object: Any, _ key: String, setting: Bool) -> Never {
        let method = setting ? "setValue:forUndefinedKey:" : "valueForUndefinedKey:"
        fatalError("[<\(type(of: object))> \(method)]: this class is not key value coding-compliant for the key \(key). "
                   + "Adopt NSKeyValueBindingCoding to expose it to bindings.")
    }

    // MARK: Collections

    /// The elements of an array-like value (Swift arrays, NSArray, NSOrderedSet, sets).
    static func arrayValue(_ object: Any) -> [Any]? {
        if object is String || object is NSString { return nil }
        // Foundation collections first, element by element (see value(_:forKey:)).
        if isObject(object) {
            if let a = object as? NSArray { return (0..<a.count).map { a.object(at: $0) } }
            if let s = object as? NSOrderedSet { return (0..<s.count).map { s.object(at: $0) } }
        }
        if let a = object as? [Any] { return a }
        if let s = object as? Set<AnyHashable> { return Array(s) }
        return nil
    }

    static func arrayValue(_ array: [Any], forKey key: String) -> Any? {
        if key.hasPrefix("@") {
            let parts = key.split(separator: ".", maxSplits: 1).map(String.init)
            let op = parts[0]
            let values: [Any] = parts.count > 1 ? array.compactMap { value($0, forKeyPath: parts[1]) } : array
            switch op {
            case "@count": return array.count
            case "@sum": return values.compactMap(number).reduce(0, +)
            case "@avg": let n = values.compactMap(number); return n.isEmpty ? nil : n.reduce(0, +) / Double(n.count)
            case "@max": return values.max { compare($0, $1) == .orderedAscending }
            case "@min": return values.min { compare($0, $1) == .orderedAscending }
            default: fatalError("[<\(type(of: array))> valueForKeyPath:]: this class does not implement the \(op) operation.")
            }
        }
        return array.map { value($0, forKey: key) ?? NSNull() }
    }

    // MARK: Values

    /// Removes any levels of `Optional` boxing from a value typed `Any`.
    static func flatten(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let m = Mirror(reflecting: value)
        if m.displayStyle == .optional {
            guard let inner = m.children.first else { return nil }
            return flatten(inner.value)
        }
        return value
    }

    static func reflected(_ object: Any, _ key: String) -> (Bool, Any?) {
        var mirror: Mirror? = Mirror(reflecting: object)
        let lazy = "$__lazy_storage_$_" + key
        while let m = mirror {
            for child in m.children where child.label == key || child.label == lazy {
                return (true, flatten(child.value))
            }
            mirror = m.superclassMirror
        }
        return (false, nil)
    }

    static func number(_ value: Any) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as Float: return Double(n)
        case let n as CGFloat: return Double(n)
        case let n as Bool: return n ? 1 : 0
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    static func bool(_ value: Any?) -> Bool {
        guard let v = flatten(value) else { return false }
        if let b = v as? Bool { return b }
        if v is NSBindingSelectionMarker { return false }
        if let n = number(v) { return n != 0 }
        return true
    }

    /// Orders two values the way `compare:` does for the common Foundation types.
    static func compare(_ a: Any?, _ b: Any?) -> ComparisonResult {
        let a = flatten(a), b = flatten(b)
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        default: break
        }
        if let x = a as? String, let y = b as? String { return x.compare(y) }
        if let x = a as? Date, let y = b as? Date { return x.compare(y) }
        if let x = number(a!), let y = number(b!) { return x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame }
        let x = String(describing: a!), y = String(describing: b!)
        return x.compare(y)
    }

    /// Whether two values are the same object (class instances) or equal (everything else).
    static func same(_ a: Any?, _ b: Any?) -> Bool {
        let a = flatten(a), b = flatten(b)
        if a == nil || b == nil { return a == nil && b == nil }
        if isObject(a!), isObject(b!) { return (a! as AnyObject) === (b! as AnyObject) }
        if let x = a as? AnyHashable, let y = b as? AnyHashable { return x == y }
        // swift-corelibs-foundation hands Foundation collections back as Swift values (an
        // NSDictionary read out of an NSArray is a [AnyHashable: Any]); compare those by content.
        if let x = a as? NSObject, let y = b as? NSObject { return x.isEqual(y) }
        return false
    }

    /// Whether `value` is a class instance (Swift bridges every value to AnyObject on Apple's
    /// platforms, so `is AnyObject` cannot tell).
    static func isObject(_ value: Any) -> Bool { type(of: value) is AnyClass }

    static func object(_ value: Any?) -> AnyObject? {
        guard let v = flatten(value), isObject(v) else { return nil }
        return v as AnyObject
    }
}

// MARK: - Observation hub

final class _KVOToken {
    fileprivate let id: Int
    fileprivate let key: _KVO.Key
    fileprivate weak var object: AnyObject?
    fileprivate let handler: () -> Void
    fileprivate init(id: Int, key: _KVO.Key, object: AnyObject, handler: @escaping () -> Void) {
        self.id = id; self.key = key; self.object = object; self.handler = handler
    }
    func invalidate() { _KVO.remove(self) }
}

enum _KVO {
    struct Key: Hashable { let object: ObjectIdentifier; let key: String }
    nonisolated(unsafe) private static var observers: [Key: [_KVOToken]] = [:]
    nonisolated(unsafe) private static var nextID = 0
    #if canImport(ObjectiveC)
    nonisolated(unsafe) private static var bridges: [Key: _KVOBridge] = [:]
    #endif

    static func add(_ object: AnyObject, key: String, handler: @escaping () -> Void) -> _KVOToken {
        nextID += 1
        let k = Key(object: ObjectIdentifier(object), key: key)
        let token = _KVOToken(id: nextID, key: k, object: object, handler: handler)
        var list = (observers[k] ?? []).filter { $0.object != nil }
        list.append(token)
        observers[k] = list
        #if canImport(ObjectiveC)
        if key != anyKey, bridges[k] == nil, let o = object as? NSObject, !(o is _NSKeyValueCodingInternal),
           !(o is NSDictionary), !(o is NSArray),
           o is NSKeyValueBindingCoding || o.responds(to: NSSelectorFromString(key)) {
            bridges[k] = _KVOBridge(object: o, key: key)
        }
        #endif
        return token
    }

    static func remove(_ token: _KVOToken) {
        guard var list = observers[token.key] else { return }
        list.removeAll { $0.id == token.id || $0.object == nil }
        if list.isEmpty {
            observers[token.key] = nil
            #if canImport(ObjectiveC)
            bridges.removeValue(forKey: token.key)?.detach()
            #endif
        } else {
            observers[token.key] = list
        }
    }

    /// Observers registered for this key hear about a change of any key of the object.
    static let anyKey = "*"

    /// Tells everything observing `key` (or any key) on `object`.
    static func didChange(_ object: AnyObject, key: String) {
        let id = ObjectIdentifier(object)
        for k in [Key(object: id, key: key), Key(object: id, key: anyKey)] {
            guard let list = observers[k] else { continue }
            for t in list where t.object === object { t.handler() }
        }
    }

    static func didChange(_ object: AnyObject, keys: [String]) { for k in keys { didChange(object, key: k) } }

    /// Tells every observer of `object`, whatever key it observes.
    static func didChangeAllKeys(_ object: AnyObject) {
        let id = ObjectIdentifier(object)
        for (k, list) in observers where k.object == id {
            for t in list where t.object === object { t.handler() }
        }
    }
}

#if canImport(ObjectiveC)
/// Forwards Foundation's key-value observing of one key into the hub (macOS host build).
final class _KVOBridge: NSObject {
    private weak var object: NSObject?
    private let key: String
    private var attached = true
    init(object: NSObject, key: String) {
        self.object = object
        self.key = key
        super.init()
        object.addObserver(self, forKeyPath: key, options: [], context: nil)
    }
    func detach() {
        guard attached else { return }
        attached = false
        object?.removeObserver(self, forKeyPath: key)
    }
    deinit { detach() }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let o = object as? NSObject else { return }
        _KVO.didChange(o, key: key)
    }
}
#endif

// MARK: - Key path observation

/// Observes a key path from a root object: each component is observed on the object (or on
/// every element of the array) the previous components lead to.
final class _KeyPathObservation {
    private let root: AnyObject?
    private let components: [String]
    private let handler: () -> Void
    private var tokens: [_KVOToken] = []
    private var firing = false

    init(root: Any, keyPath: String, handler: @escaping () -> Void) {
        self.root = _KVC.object(root)
        self.components = _KVC.components(keyPath)
        self.handler = handler
        rebuild()
    }

    deinit { for t in tokens { t.invalidate() } }

    func invalidate() {
        for t in tokens { t.invalidate() }
        tokens = []
    }

    private func rebuild() {
        for t in tokens { t.invalidate() }
        tokens = []
        guard let root else { return }
        var level: [Any] = [root]
        for (i, key) in components.enumerated() {
            if key.hasPrefix("@") { break }
            var next: [Any] = []
            for item in expand(level) {
                guard let obj = _KVC.object(item) else { continue }
                var targets: [AnyObject] = [obj]
                if let f = obj as? _NSKeyValueObservationForwarding { targets += f._forwardedObservationTargets(forKey: key) }
                for t in targets {
                    tokens.append(_KVO.add(t, key: key) { [weak self] in self?.changed() })
                }
                if i < components.count - 1, let v = _KVC.value(obj, forKey: key) { next.append(v) }
            }
            level = next
        }
    }

    private func expand(_ items: [Any]) -> [Any] {
        var out: [Any] = []
        for item in items {
            if let a = _KVC.arrayValue(item) { out += a.filter { !($0 is NSNull) } } else { out.append(item) }
        }
        return out
    }

    private func changed() {
        if firing { return }
        firing = true
        defer { firing = false }
        if components.count > 1 { rebuild() }
        handler()
    }
}

// MARK: - Bindings

/// One binding: `owner.name` follows `observable.keyPath`.
final class _NSBinding {
    let name: NSBindingName
    weak var owner: NSObject?
    let observable: Any
    let keyPath: String
    let options: [NSBindingOption: Any]
    fileprivate var observation: _KeyPathObservation?
    /// Set while the owner writes back, so the echo of its own change is not applied again.
    var pushing = false
    /// State a target keeps for the binding (a text field's editability before placeholders).
    var saved: [String: Any] = [:]

    init(name: NSBindingName, owner: NSObject, observable: Any, keyPath: String, options: [NSBindingOption: Any]) {
        self.name = name; self.owner = owner; self.observable = observable; self.keyPath = keyPath; self.options = options
    }

    /// The bound value, through the value transformer when one is set.
    var value: Any? {
        let raw = _KVC.value(observable, forKeyPath: keyPath)
        return transformed(raw)
    }

    /// The first component of the key path and the rest ("arrangedObjects", "name").
    var splitKeyPath: (head: String, rest: String?) {
        let c = _KVC.components(keyPath)
        return (c.first ?? keyPath, c.count > 1 ? c.dropFirst().joined(separator: ".") : nil)
    }

    /// Writes `value` back to the observed object.
    func push(_ value: Any?) {
        pushing = true
        defer { pushing = false }
        _KVC.setValue(reverseTransformed(value), on: observable, forKeyPath: keyPath)
    }

    func option<T>(_ key: NSBindingOption, _ type: T.Type) -> T? { options[key] as? T }
    func boolOption(_ key: NSBindingOption, default def: Bool) -> Bool {
        guard let v = options[key] else { return def }
        return _KVC.bool(v)
    }

    var info: [NSBindingInfoKey: Any] {
        [.observedObject: observable, .observedKeyPath: keyPath, .options: options as Any]
    }

    private func transformer() -> Any? {
        if let t = options[.valueTransformer] { return t }
        if let name = options[.valueTransformerName] {
            #if canImport(ObjectiveC)
            let n = (name as? NSValueTransformerName) ?? NSValueTransformerName(rawValue: String(describing: name))
            return ValueTransformer(forName: n)
            #else
            _ = name
            unimplemented()
            #endif
        }
        return nil
    }

    private func transformed(_ value: Any?) -> Any? {
        guard let t = transformer(), !(value is NSBindingSelectionMarker) else { return value }
        #if canImport(ObjectiveC)
        return (t as? ValueTransformer)?.transformedValue(value)
        #else
        _ = t
        unimplemented()
        #endif
    }

    private func reverseTransformed(_ value: Any?) -> Any? {
        guard let t = transformer() else { return value }
        #if canImport(ObjectiveC)
        return (t as? ValueTransformer)?.reverseTransformedValue(value)
        #else
        _ = t
        unimplemented()
        #endif
    }
}

/// Classes that define bindings of their own (views, columns, controllers).
protocol _NSBindingTarget: AnyObject {
    /// The binding names the class defines.
    static var _definedBindings: [NSBindingName] { get }
    /// Applies the binding's current value; false when the class does not define `binding.name`.
    func _applyBinding(_ binding: _NSBinding) -> Bool
    /// The binding was created or removed.
    func _bindingDidAttach(_ binding: _NSBinding)
    func _bindingDidDetach(_ binding: _NSBinding)
}

extension _NSBindingTarget {
    func _bindingDidAttach(_ binding: _NSBinding) { }
    func _bindingDidDetach(_ binding: _NSBinding) { }
}

enum _NSBindings {
    nonisolated(unsafe) private static var table: [ObjectIdentifier: [NSBindingName: _NSBinding]] = [:]
    nonisolated(unsafe) static var exposed: [ObjectIdentifier: [NSBindingName]] = [:]

    static func binding(_ owner: NSObject, _ name: NSBindingName) -> _NSBinding? {
        guard let b = table[ObjectIdentifier(owner)]?[name], b.owner === owner else { return nil }
        return b
    }

    static func bindings(_ owner: NSObject) -> [_NSBinding] {
        guard let all = table[ObjectIdentifier(owner)] else { return [] }
        return all.values.filter { $0.owner === owner }
    }

    static func store(_ b: _NSBinding, owner: NSObject) {
        // Drop the bindings of owners that are gone (they would keep their controllers alive).
        for (key, all) in table where !all.values.contains(where: { $0.owner != nil }) {
            for dead in all.values { dead.observation?.invalidate() }
            table[key] = nil
        }
        let id = ObjectIdentifier(owner)
        var all = (table[id] ?? [:]).filter { $0.value.owner === owner }
        all[b.name] = b
        table[id] = all
    }

    static func remove(_ owner: NSObject, _ name: NSBindingName) -> _NSBinding? {
        let id = ObjectIdentifier(owner)
        guard var all = table[id], let b = all.removeValue(forKey: name) else { return nil }
        table[id] = all.isEmpty ? nil : all
        return b.owner === owner ? b : nil
    }

    /// Hands the binding's current value to its owner.
    static func apply(_ b: _NSBinding) {
        guard let owner = b.owner, !b.pushing else { return }
        if let t = owner as? _NSBindingTarget, t._applyBinding(b) { return }
        _KVC.setValue(b.value, on: owner, forKey: b.name.rawValue)
    }

    /// Writes `value` back through the owner's binding `name`, if it has one.
    @discardableResult
    static func push(_ owner: NSObject, _ name: NSBindingName, _ value: Any?) -> Bool {
        guard let b = binding(owner, name) else { return false }
        b.push(value)
        return true
    }
}

// MARK: - NSKeyValueBindingCreation

extension NSObject {
    /// - SeeAlso: https://developer.apple.com/documentation/objectivec/nsobject/exposebinding(_:)
    public class func exposeBinding(_ binding: NSBindingName) {
        let id = ObjectIdentifier(self)
        var list = _NSBindings.exposed[id] ?? []
        if !list.contains(binding) { list.append(binding) }
        _NSBindings.exposed[id] = list
    }

    /// - SeeAlso: https://developer.apple.com/documentation/objectivec/nsobject/exposedbindings
    public var exposedBindings: [NSBindingName] {
        var out: [NSBindingName] = []
        var cls: AnyClass? = type(of: self)
        while let c = cls {
            if let t = c as? _NSBindingTarget.Type { out += t._definedBindings.filter { !out.contains($0) } }
            out += (_NSBindings.exposed[ObjectIdentifier(c)] ?? []).filter { !out.contains($0) }
            cls = _getSuperclass(c)
        }
        return out
    }

    /// - SeeAlso: https://developer.apple.com/documentation/objectivec/nsobject/valueclassforbinding(_:)
    public func valueClassForBinding(_ binding: NSBindingName) -> AnyClass? { unimplemented() }

    /// - SeeAlso: https://developer.apple.com/documentation/objectivec/nsobject/bind(_:to:withkeypath:options:)
    public func bind(_ binding: NSBindingName, to observable: Any, withKeyPath keyPath: String, options: [NSBindingOption: Any]? = nil) {
        unbind(binding)
        let b = _NSBinding(name: binding, owner: self, observable: observable, keyPath: keyPath, options: options ?? [:])
        _NSBindings.store(b, owner: self)
        (self as? _NSBindingTarget)?._bindingDidAttach(b)
        b.observation = _KeyPathObservation(root: observable, keyPath: keyPath) { [weak b] in
            if let b { _NSBindings.apply(b) }
        }
        _NSBindings.apply(b)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/objectivec/nsobject/unbind(_:)
    public func unbind(_ binding: NSBindingName) {
        guard let b = _NSBindings.remove(self, binding) else { return }
        b.observation?.invalidate()
        b.observation = nil
        (self as? _NSBindingTarget)?._bindingDidDetach(b)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/objectivec/nsobject/infoforbinding(_:)
    public func infoForBinding(_ binding: NSBindingName) -> [NSBindingInfoKey: Any]? {
        _NSBindings.binding(self, binding)?.info
    }
}

// MARK: - Placeholders

enum _NSBindingPlaceholders {
    /// The text a bound view shows for a selection marker or a nil value, from the binding's
    /// options, then the registered default placeholders, then AppKit's defaults.
    static func placeholder(for value: Any?, binding b: _NSBinding) -> String? {
        let marker = value as? NSBindingSelectionMarker
        let option: NSBindingOption
        switch marker {
        case .some(let m) where m === NSBindingSelectionMarker.multipleValues: option = .multipleValuesPlaceholder
        case .some(let m) where m === NSBindingSelectionMarker.noSelection: option = .noSelectionPlaceholder
        case .some: option = .notApplicablePlaceholder
        case .none: option = .nullPlaceholder
        }
        if let p = b.options[option] { return p is NSNull ? nil : String(describing: p) }
        if let owner = b.owner, let p = NSBindingSelectionMarker.defaultPlaceholder(for: marker, on: type(of: owner), withBinding: b.name) {
            return p is NSNull ? nil : String(describing: p)
        }
        switch marker {
        case .some(let m) where m === NSBindingSelectionMarker.multipleValues: return "Multiple Values"
        case .some(let m) where m === NSBindingSelectionMarker.noSelection: return "No Selection"
        case .some: return "Not Applicable"
        case .none: return nil
        }
    }
}
