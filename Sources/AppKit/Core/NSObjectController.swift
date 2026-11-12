// NSObjectController (hand-written; seeded from the generated stub, see tools/apigen)
//
// A controller for one content object. Its `selection` is a proxy that answers key-value
// coding for the selected objects: the shared value, or a selection marker when there is no
// selection or the selected objects disagree; writing through it sets every selected object
// (ADR-0032). Core Data fetching is out of scope (`fetch`), as everywhere in the port.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller
open class NSObjectController: NSController {
    internal var _contentObject: Any?
    private var _objectClass: AnyClass = NSMutableDictionary.self
    private var _isEditable = true
    private var _automaticallyPreparesContent = false
    private var _entityName: String?
    private var _fetchPredicate: NSPredicate?
    private var _usesLazyFetching = false
    internal lazy var _selectionProxy = _NSControllerSelectionProxy(controller: self)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/init(content:)
    public init(content: Any?) {
        super.init()
        if let content { _setContentFromInit(content) }
    }
    /// The inherited `init()`: a controller with no content.
    public override convenience init() { self.init(content: nil) }

    /// Subclasses take their initial content without the side effects of the setter.
    internal func _setContentFromInit(_ content: Any) { _contentObject = content }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/add(_:)
    @MainActor open func add(_ sender: Any?) {
        _performDeferred { [self] in addObject(newObject()) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/addobject(_:)
    open func addObject(_ object: Any) {
        content = object
        _NSBindings.push(self, .contentObject, object)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/automaticallypreparescontent
    open var automaticallyPreparesContent: Bool {
        get { _automaticallyPreparesContent }
        set { _automaticallyPreparesContent = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/canadd
    open var canAdd: Bool { isEditable }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/canremove
    open var canRemove: Bool { isEditable && !selectedObjects.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/content
    open var content: Any? {
        get { _contentObject }
        set {
            _contentObject = newValue
            _didChange(["content", "selection", "selectedObjects", "canRemove"])
        }
    }
    // SKIPPED (unknown module (CoreData NSFetchRequest); unknown module (CoreData NSFetchRequestResult)): func defaultFetchRequest() -> NSFetchRequest<any NSFetchRequestResult>
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/entityname
    open var entityName: String? {
        get { _entityName }
        set { _entityName = newValue }
    }
    /// Core Data fetching is not part of the port.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/fetch(_:)
    @MainActor open func fetch(_ sender: Any?) { unimplemented() }
    // SKIPPED (unknown module (CoreData NSFetchRequest); unknown module (CoreData NSFetchRequestResult)): func fetch(with fetchRequest: NSFetchRequest<any NSFetchRequestResult>?, merge: Bool) throws
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/fetchpredicate
    open var fetchPredicate: NSPredicate? {
        get { _fetchPredicate }
        set { _fetchPredicate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/iseditable
    open var isEditable: Bool {
        get { _isEditable }
        set {
            guard newValue != _isEditable else { return }
            _isEditable = newValue
            _didChange(["editable", "isEditable", "canAdd", "canInsert", "canRemove", "canAddChild", "canInsertChild"])
        }
    }
    // SKIPPED (unknown module (CoreData NSManagedObjectContext)): var managedObjectContext: NSManagedObjectContext? { get set }
    /// A new instance of `objectClass` (an `NSMutableDictionary` unless set).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/newobject()
    open func newObject() -> Any {
        if _objectClass == NSMutableDictionary.self { return NSMutableDictionary() }
        if _objectClass == NSDictionary.self { return NSMutableDictionary() }
        #if canImport(ObjectiveC)
        guard let cls = _objectClass as? NSObject.Type else {
            fatalError("[\(type(of: self)) newObject]: \(_objectClass) is not an NSObject subclass")
        }
        return cls.init()
        #else
        // corelibs' NSObject.init() is not `required`, so a metatype cannot construct an
        // arbitrary class; override newObject() for model classes on these platforms.
        unimplemented()
        #endif
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/objectclass
    open var objectClass: AnyClass! {
        get { _objectClass }
        set { _objectClass = newValue ?? NSMutableDictionary.self }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/preparecontent()
    open func prepareContent() { content = newObject() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/remove(_:)
    @MainActor open func remove(_ sender: Any?) {
        _performDeferred { [self] in
            for o in selectedObjects { removeObject(o) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/removeobject(_:)
    open func removeObject(_ object: Any) {
        guard _KVC.same(object, _contentObject) else { return }
        content = nil
        _NSBindings.push(self, .contentObject, nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/selectedobjects
    open var selectedObjects: [Any] { _contentObject.map { [$0] } ?? [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/selection
    open var selection: Any { _selectionProxy }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/useslazyfetching
    open var usesLazyFetching: Bool {
        get { _usesLazyFetching }
        set { _usesLazyFetching = newValue }
    }
    /// Enables the controller's actions by what they can do now.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsobjectcontroller/validateuserinterfaceitem(_:)
    open func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let action = MainActor.assumeIsolated({ item.action }) else { return true }
        return _canPerform(action.description)
    }

    /// Whether the controller action named `selector` can run.
    internal func _canPerform(_ selector: String) -> Bool {
        switch selector {
        case "add:": return canAdd
        case "remove:": return canRemove
        case "fetch:": return false
        default: return true
        }
    }

    // MARK: Change notification

    internal func _didChange(_ keys: [String]) { _KVO.didChange(self, keys: keys) }

    /// The selection proxy reports multiple values whenever several objects are selected.
    internal var _usesMultipleValuesMarker: Bool { false }

    // MARK: Subclass hooks (extension members cannot be overridden without the runtime)

    /// Keys subclasses add (arrangedObjects, selectionIndexes, ...).
    internal func _kvcSubclassValue(forKey key: String) -> Any?? { nil }
    internal func _kvcSubclassSetValue(_ value: Any?, forKey key: String) -> Bool { false }
    /// Bindings subclasses define.
    internal func _applySubclassBinding(_ b: _NSBinding) -> Bool { false }
}

// MARK: - Key-value coding

extension NSObjectController: _NSKeyValueCodingInternal {
    func _kvcValue(forKey key: String) -> Any?? {
        switch key {
        case "content": return .some(content)
        case "selection": return .some(selection)
        case "selectedObjects": return .some(selectedObjects)
        case "canAdd": return .some(canAdd)
        case "canRemove": return .some(canRemove)
        case "editable", "isEditable": return .some(isEditable)
        case "editing", "isEditing": return .some(isEditing)
        default: return _kvcSubclassValue(forKey: key)
        }
    }

    func _kvcSetValue(_ value: Any?, forKey key: String) -> Bool {
        switch key {
        case "content": content = value
        case "editable", "isEditable": isEditable = _KVC.bool(value)
        default: return _kvcSubclassSetValue(value, forKey: key)
        }
        return true
    }
}

// MARK: - Bindings

extension NSObjectController: _NSBindingTarget {
    static var _definedBindings: [NSBindingName] { [.contentObject, .editable, .contentArray, .selectionIndexes, .sortDescriptors, .filterPredicate] }

    func _applyBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .contentObject: content = b.value
        case .editable: isEditable = _KVC.bool(b.value)
        default: return _applySubclassBinding(b)
        }
        return true
    }
}

// MARK: - Selection proxy

/// What `selection` returns: key-value coding over the selected objects.
final class _NSControllerSelectionProxy: NSObject, _NSKeyValueCodingInternal, _NSKeyValueObservationForwarding {
    unowned let controller: NSObjectController
    init(controller: NSObjectController) { self.controller = controller; super.init() }

    func _kvcValue(forKey key: String) -> Any?? {
        let objects = controller.selectedObjects
        guard let first = objects.first else { return .some(NSBindingSelectionMarker.noSelection) }
        if objects.count > 1 && controller._usesMultipleValuesMarker { return .some(NSBindingSelectionMarker.multipleValues) }
        let value = _KVC.value(first, forKey: key)
        for o in objects.dropFirst() where !_KVC.same(_KVC.value(o, forKey: key), value) {
            return .some(NSBindingSelectionMarker.multipleValues)
        }
        return .some(value)
    }

    func _kvcSetValue(_ value: Any?, forKey key: String) -> Bool {
        for o in controller.selectedObjects { _KVC.setValue(value, on: o, forKey: key) }
        return true
    }

    func _forwardedObservationTargets(forKey key: String) -> [AnyObject] {
        controller.selectedObjects.compactMap { _KVC.object($0) }
    }

    override var description: String { "<_NSControllerProxyObject \(controller.selectedObjects.count) selected>" }
}
