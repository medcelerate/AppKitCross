// NSUserDefaultsController (hand-written; seeded from the generated stub, see tools/apigen)
//
// `values` is a proxy for binding to user defaults ("values.fontSize"): it reads unapplied
// changes, then the defaults, then the initial values; it writes to the defaults at once when
// `appliesImmediately` is set and otherwise keeps the change until `save(_:)` (ADR-0032).
// A change of the defaults made elsewhere reaches bound views through
// UserDefaults.didChangeNotification.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller
open class NSUserDefaultsController: NSController {
    nonisolated(unsafe) private static var _shared: NSUserDefaultsController?
    private let _defaults: UserDefaults
    private var _initialValues: [String: Any]?
    private var _appliesImmediately = true
    internal var _pending: [String: Any?] = [:]
    private lazy var _values = _NSUserDefaultsValues(controller: self)
    nonisolated(unsafe) private var _observer: (any NSObjectProtocol)?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/init(defaults:initialvalues:)
    public init(defaults: UserDefaults?, initialValues: [String : Any]?) {
        _defaults = defaults ?? .standard
        _initialValues = initialValues
        super.init()
        _observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: _defaults, queue: nil) { [weak self] _ in
            guard let self else { return }
            _KVO.didChangeAllKeys(self._values)
        }
    }
    deinit { if let o = _observer { NotificationCenter.default.removeObserver(o) } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/appliesimmediately
    open var appliesImmediately: Bool {
        get { _appliesImmediately }
        set { _appliesImmediately = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/defaults
    open var defaults: UserDefaults { _defaults }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/hasunappliedchanges
    open var hasUnappliedChanges: Bool { !_pending.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/initialvalues
    open var initialValues: [String : Any]? {
        get { _initialValues }
        set { _initialValues = newValue; _KVO.didChangeAllKeys(_values) }
    }
    /// Discards the unapplied changes.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/revert(_:)
    @MainActor open func revert(_ sender: Any?) {
        discardEditing()
        let keys = Array(_pending.keys)
        _pending = [:]
        _KVO.didChange(_values, keys: keys)
        _KVO.didChange(self, key: "hasUnappliedChanges")
    }
    /// Sets every key that has an initial value back to it.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/reverttoinitialvalues(_:)
    @MainActor open func revertToInitialValues(_ sender: Any?) {
        for (key, value) in _initialValues ?? [:] { _setValue(value, forKey: key) }
    }
    /// Writes the unapplied changes to the defaults.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/save(_:)
    @MainActor open func save(_ sender: Any?) {
        guard commitEditing() else { return }
        let pending = _pending
        _pending = [:]
        for (key, value) in pending { _write(value, forKey: key) }
        _KVO.didChange(self, key: "hasUnappliedChanges")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/shared
    class public var shared: NSUserDefaultsController {
        if let s = _shared { return s }
        let s = NSUserDefaultsController(defaults: nil, initialValues: nil)
        _shared = s
        return s
    }
    /// The proxy bindings use: `bind(.value, to: controller, withKeyPath: "values.<key>")`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsuserdefaultscontroller/values
    open var values: Any { _values }

    // MARK: Internals

    @MainActor internal override func _performControllerAction(_ name: String, _ sender: Any?) -> Bool? {
        switch name {
        case "save:": save(sender)
        case "revert:": revert(sender)
        case "revertToInitialValues:": revertToInitialValues(sender)
        default: return nil
        }
        return true
    }
    internal override func _respondsToControllerAction(_ name: String) -> Bool {
        name == "revert:" || name == "save:" ? hasUnappliedChanges : name == "revertToInitialValues:"
    }

    internal func _value(forKey key: String) -> Any? {
        if let p = _pending[key] { return p }
        return _defaults.object(forKey: key) ?? _initialValues?[key]
    }

    internal func _setValue(_ value: Any?, forKey key: String) {
        if _appliesImmediately {
            _write(value, forKey: key)
        } else {
            _pending[key] = .some(value)
            _KVO.didChange(self, key: "hasUnappliedChanges")
        }
        _KVO.didChange(_values, key: key)
    }

    private func _write(_ value: Any?, forKey key: String) {
        if let value, !(value is NSNull) { _defaults.set(value, forKey: key) } else { _defaults.removeObject(forKey: key) }
    }
}

extension NSUserDefaultsController: _NSKeyValueCodingInternal {
    func _kvcValue(forKey key: String) -> Any?? {
        switch key {
        case "values": return .some(values)
        case "hasUnappliedChanges": return .some(hasUnappliedChanges)
        case "appliesImmediately": return .some(appliesImmediately)
        case "initialValues": return .some(initialValues)
        case "editing", "isEditing": return .some(isEditing)
        default: return nil
        }
    }
    func _kvcSetValue(_ value: Any?, forKey key: String) -> Bool {
        switch key {
        case "appliesImmediately": appliesImmediately = _KVC.bool(value)
        case "initialValues": initialValues = value as? [String: Any]
        default: return false
        }
        return true
    }
}

/// The `values` proxy: every key is a user-defaults key.
final class _NSUserDefaultsValues: NSObject, _NSKeyValueCodingInternal {
    unowned let controller: NSUserDefaultsController
    init(controller: NSUserDefaultsController) { self.controller = controller; super.init() }
    func _kvcValue(forKey key: String) -> Any?? { .some(controller._value(forKey: key)) }
    func _kvcSetValue(_ value: Any?, forKey key: String) -> Bool {
        controller._setValue(value, forKey: key)
        return true
    }
}
