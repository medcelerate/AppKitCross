// NSArrayController (hand-written; seeded from the generated stub, see tools/apigen)
//
// The content array, its arrangement (filtered by `filterPredicate`, then sorted by
// `sortDescriptors`), and a selection kept as indexes into the arranged objects (ADR-0032).
// AppKit's rules, as implemented here:
// - Inserted objects join the arrangement where they are inserted (added ones at the end)
//   without re-sorting, unless `automaticallyRearrangesObjects` is set; inserting clears the
//   filter first when `clearsFilterPredicateOnInsertion` is set (the default).
// - `selectsInsertedObjects` selects what was inserted; `preservesSelection` keeps the same
//   objects selected across a rearrangement or new content; `avoidsEmptySelection` selects the
//   first object of new content and the nearest object after a removal.
// - `add(_:)`, `insert(_:)` and `remove(_:)` commit pending edits and run on the next pass of
//   the main run loop; the object methods act at once.
// - Every change is announced through the key-value hub, so views bound to `arrangedObjects`
//   or `selection` (and a model bound through `contentArray`) follow.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller
open class NSArrayController: NSObjectController {
    private var _objects: [Any] = []
    private var _arranged: [Any] = []
    private var _selection = IndexSet()
    private var _sortDescriptors: [NSSortDescriptor] = []
    private var _filterPredicate: NSPredicate?
    private var _alwaysUsesMultipleValuesMarker = false
    private var _automaticallyRearrangesObjects = false
    private var _avoidsEmptySelection = true
    private var _clearsFilterPredicateOnInsertion = true
    private var _preservesSelection = true
    private var _selectsInsertedObjects = true
    private var _rearrangementTokens: [_KVOToken] = []

    internal override func _setContentFromInit(_ content: Any) { _replaceContent(Self._array(content)) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/add(_:)
    @MainActor open override func add(_ sender: Any?) {
        _performDeferred { [self] in addObject(newObject()) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/add(contentsof:)
    open func add(contentsOf objects: [Any]) {
        guard !objects.isEmpty else { return }
        _prepareForInsertion()
        _objects += objects
        if _automaticallyRearrangesObjects {
            _arranged = arrange(_objects)
        } else {
            _arranged += objects.filter { o in !_arranged.contains { _KVC.same($0, o) } }
        }
        if _selectsInsertedObjects { _selection = _indexes(of: objects) }
        _contentDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/addobject(_:)
    open override func addObject(_ object: Any) { add(contentsOf: [object]) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/addselectedobjects(_:)
    open func addSelectedObjects(_ objects: [Any]) -> Bool { setSelectionIndexes(_selection.union(_indexes(of: objects))) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/addselectionindexes(_:)
    open func addSelectionIndexes(_ indexes: IndexSet) -> Bool { setSelectionIndexes(_selection.union(indexes)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/alwaysusesmultiplevaluesmarker
    open var alwaysUsesMultipleValuesMarker: Bool {
        get { _alwaysUsesMultipleValuesMarker }
        set { _alwaysUsesMultipleValuesMarker = newValue; _didChange(["selection"]) }
    }
    /// Filters `objects` with `filterPredicate` and sorts them with `sortDescriptors`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/arrange(_:)
    open func arrange(_ objects: [Any]) -> [Any] {
        var out = objects
        if let p = _filterPredicate { out = out.filter { p.evaluate(with: $0) } }
        guard !_sortDescriptors.isEmpty else { return out }
        // A stable sort: equal objects keep their content order.
        return out.enumerated().sorted { a, b in
            for d in _sortDescriptors {
                switch d.compare(a.element, to: b.element) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return a.offset < b.offset
        }.map { $0.element }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/arrangedobjects
    open var arrangedObjects: Any { _arranged }
    /// The keys whose change rearranges the content when `automaticallyRearrangesObjects` is
    /// set: the sort descriptors' keys and the filter predicate's key paths. Sort descriptors
    /// made from Swift key paths have no string form on swift-corelibs-foundation and are left out.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/automaticrearrangementkeypaths
    open var automaticRearrangementKeyPaths: [String]? {
        guard _automaticallyRearrangesObjects else { return nil }
        var keys: [String] = []
        #if canImport(ObjectiveC)
        for d in _sortDescriptors { if let k = d.key, !keys.contains(k) { keys.append(k) } }
        #endif
        for k in _NSPredicateKeyPaths.keyPaths(in: _filterPredicate) where !keys.contains(k) { keys.append(k) }
        return keys
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/automaticallyrearrangesobjects
    open var automaticallyRearrangesObjects: Bool {
        get { _automaticallyRearrangesObjects }
        set {
            _automaticallyRearrangesObjects = newValue
            _observeForRearrangement()
            if newValue { rearrangeObjects() }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/avoidsemptyselection
    open var avoidsEmptySelection: Bool {
        get { _avoidsEmptySelection }
        set { _avoidsEmptySelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/caninsert
    open var canInsert: Bool { isEditable }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/canselectnext
    open var canSelectNext: Bool {
        guard let last = _selection.last else { return !_arranged.isEmpty }
        return last < _arranged.count - 1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/canselectprevious
    open var canSelectPrevious: Bool { (_selection.first ?? 0) > 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/clearsfilterpredicateoninsertion
    open var clearsFilterPredicateOnInsertion: Bool {
        get { _clearsFilterPredicateOnInsertion }
        set { _clearsFilterPredicateOnInsertion = newValue }
    }
    /// The content array (`[Any]`); setting accepts an array, an ordered set or a set.
    open override var content: Any? {
        get { _objects }
        set { _replaceContent(Self._array(newValue)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/didchangearrangementcriteria()
    open func didChangeArrangementCriteria() {
        _observeForRearrangement()
        rearrangeObjects()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/filterpredicate
    open var filterPredicate: NSPredicate? {
        get { _filterPredicate }
        set {
            _filterPredicate = newValue
            _didChange(["filterPredicate"])
            _NSBindings.push(self, .filterPredicate, newValue)
            didChangeArrangementCriteria()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/insert(_:)
    @MainActor open func insert(_ sender: Any?) {
        _performDeferred { [self] in
            let index = _selection.first ?? _arranged.count
            insert(newObject(), atArrangedObjectIndex: index)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/insert(_:atarrangedobjectindex:)
    open func insert(_ object: Any, atArrangedObjectIndex index: Int) {
        insert(contentsOf: [object], atArrangedObjectIndexes: IndexSet(integer: index))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/insert(contentsof:atarrangedobjectindexes:)
    open func insert(contentsOf objects: [Any], atArrangedObjectIndexes indexes: IndexSet) {
        precondition(objects.count == indexes.count, "[NSArrayController insertObjects:atArrangedObjectIndexes:]: count of array (\(objects.count)) differs from count of index set (\(indexes.count))")
        guard !objects.isEmpty else { return }
        _prepareForInsertion()
        var selection = _selection
        for (object, index) in zip(objects, indexes) {
            precondition(index >= 0 && index <= _arranged.count, "[NSArrayController insertObject:atArrangedObjectIndex:]: index (\(index)) beyond bounds (\(_arranged.count))")
            // The content keeps the arrangement's order around the insertion point.
            let contentIndex = index < _arranged.count ? (_contentIndex(of: _arranged[index]) ?? _objects.count) : _objects.count
            _objects.insert(object, at: contentIndex)
            _arranged.insert(object, at: index)
            selection = IndexSet(selection.map { $0 >= index ? $0 + 1 : $0 })
        }
        if _automaticallyRearrangesObjects { _arranged = arrange(_objects) }
        _selection = _selectsInsertedObjects ? _indexes(of: objects) : _resolve(selection, previously: [])
        _contentDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/preservesselection
    open var preservesSelection: Bool {
        get { _preservesSelection }
        set { _preservesSelection = newValue }
    }
    /// Arranges the content again (after a change of the arrangement criteria or of the objects).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/rearrangeobjects()
    open func rearrangeObjects() {
        let selected = selectedObjects
        _arranged = arrange(_objects)
        _selection = _preservesSelection ? _indexes(of: selected) : IndexSet(_selection.filter { $0 < _arranged.count })
        _selection = _resolve(_selection, previously: selected)
        _arrangementDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/remove(_:)
    @MainActor open override func remove(_ sender: Any?) {
        _performDeferred { [self] in remove(atArrangedObjectIndexes: _selection) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/remove(atarrangedobjectindex:)
    open func remove(atArrangedObjectIndex index: Int) { remove(atArrangedObjectIndexes: IndexSet(integer: index)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/remove(atarrangedobjectindexes:)
    open func remove(atArrangedObjectIndexes indexes: IndexSet) {
        let valid = IndexSet(indexes.filter { $0 >= 0 && $0 < _arranged.count })
        guard !valid.isEmpty else { return }
        let removed = valid.map { _arranged[$0] }
        let selectedBefore = selectedObjects
        let anchor = valid.first!
        for i in valid.reversed() { _arranged.remove(at: i) }
        for o in removed { if let ci = _contentIndex(of: o) { _objects.remove(at: ci) } }
        _selection = _indexes(of: selectedBefore)
        if _selection.isEmpty, !selectedBefore.isEmpty, _avoidsEmptySelection, !_arranged.isEmpty {
            _selection = IndexSet(integer: min(anchor, _arranged.count - 1))
        }
        _contentDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/remove(contentsof:)
    open func remove(contentsOf objects: [Any]) {
        let arrangedIndexes = IndexSet(_arranged.indices.filter { i in objects.contains { _KVC.same($0, _arranged[i]) } })
        let hidden = objects.filter { o in !_arranged.contains { _KVC.same($0, o) } }
        if !hidden.isEmpty {
            _objects.removeAll { o in hidden.contains { _KVC.same($0, o) } }
            if arrangedIndexes.isEmpty { _contentDidChange(); return }
        }
        remove(atArrangedObjectIndexes: arrangedIndexes)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/removeobject(_:)
    open override func removeObject(_ object: Any) { remove(contentsOf: [object]) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/removeselectedobjects(_:)
    open func removeSelectedObjects(_ objects: [Any]) -> Bool { setSelectionIndexes(_selection.subtracting(_indexes(of: objects))) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/removeselectionindexes(_:)
    open func removeSelectionIndexes(_ indexes: IndexSet) -> Bool { setSelectionIndexes(_selection.subtracting(indexes)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/selectnext(_:)
    @MainActor open func selectNext(_ sender: Any?) {
        guard canSelectNext else { return }
        _ = setSelectionIndex(_selection.last.map { $0 + 1 } ?? 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/selectprevious(_:)
    @MainActor open func selectPrevious(_ sender: Any?) {
        guard canSelectPrevious, let first = _selection.first else { return }
        _ = setSelectionIndex(first - 1)
    }
    // SKIPPED (override type [Any]! differs from superclass [Any]): var selectedObjects: [Any]! { get }
    open override var selectedObjects: [Any] { _selection.map { _arranged[$0] } }
    /// The first selected index, or `NSNotFound`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/selectionindex
    open var selectionIndex: Int { _selection.first ?? NSNotFound }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/selectionindexes
    open var selectionIndexes: IndexSet { _selection }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/selectsinsertedobjects
    open var selectsInsertedObjects: Bool {
        get { _selectsInsertedObjects }
        set { _selectsInsertedObjects = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/setselectedobjects(_:)
    open func setSelectedObjects(_ objects: [Any]) -> Bool { setSelectionIndexes(_indexes(of: objects)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/setselectionindex(_:)
    open func setSelectionIndex(_ index: Int) -> Bool {
        setSelectionIndexes(index == NSNotFound ? IndexSet() : IndexSet(integer: index))
    }
    /// Selects `indexes` (those inside the arrangement) after committing pending edits.
    /// Returns true when the selection changed.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/setselectionindexes(_:)
    open func setSelectionIndexes(_ indexes: IndexSet) -> Bool {
        let valid = IndexSet(indexes.filter { $0 >= 0 && $0 < _arranged.count })
        guard valid != _selection else { return false }
        guard MainActor.assumeIsolated({ commitEditing() }) else { return false }
        _selection = valid
        _selectionDidChange()
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsarraycontroller/sortdescriptors
    open var sortDescriptors: [NSSortDescriptor] {
        get { _sortDescriptors }
        set {
            _sortDescriptors = newValue
            _didChange(["sortDescriptors"])
            _NSBindings.push(self, .sortDescriptors, newValue)
            didChangeArrangementCriteria()
        }
    }

    // MARK: Internals

    internal override var _usesMultipleValuesMarker: Bool { _alwaysUsesMultipleValuesMarker }

    internal override func _canPerform(_ selector: String) -> Bool {
        switch selector {
        case "insert:": return canInsert
        case "selectNext:": return canSelectNext
        case "selectPrevious:": return canSelectPrevious
        default: return super._canPerform(selector)
        }
    }

    static func _array(_ value: Any?) -> [Any] {
        guard let v = _KVC.flatten(value) else { return [] }
        return _KVC.arrayValue(v) ?? [v]
    }

    private func _contentIndex(of object: Any) -> Int? { _objects.firstIndex { _KVC.same($0, object) } }

    /// The arranged indexes of `objects`.
    private func _indexes(of objects: [Any]) -> IndexSet {
        var out = IndexSet()
        for o in objects {
            if let i = _arranged.indices.first(where: { !out.contains($0) && _KVC.same(_arranged[$0], o) }) { out.insert(i) }
        }
        return out
    }

    /// Applies `avoidsEmptySelection` to a proposed selection.
    private func _resolve(_ selection: IndexSet, previously: [Any]) -> IndexSet {
        let valid = IndexSet(selection.filter { $0 < _arranged.count })
        if valid.isEmpty, _avoidsEmptySelection, !_arranged.isEmpty { return IndexSet(integer: 0) }
        return valid
    }

    private func _prepareForInsertion() {
        guard _clearsFilterPredicateOnInsertion, _filterPredicate != nil else { return }
        _filterPredicate = nil
        _didChange(["filterPredicate"])
        _NSBindings.push(self, .filterPredicate, nil)
        let selected = selectedObjects
        _arranged = arrange(_objects)
        _selection = _indexes(of: selected)
    }

    private func _replaceContent(_ objects: [Any]) {
        let selected = selectedObjects
        _objects = objects
        _arranged = arrange(objects)
        _selection = _preservesSelection ? _indexes(of: selected) : IndexSet(_selection.filter { $0 < _arranged.count })
        _selection = _resolve(_selection, previously: selected)
        _observeForRearrangement()
        _didChange(["content", "contentArray"])
        _arrangementDidChange()
    }

    /// The content changed through the controller: tell the model bound through `contentArray`.
    private func _contentDidChange() {
        _observeForRearrangement()
        _NSBindings.push(self, .contentArray, _objects)
        _didChange(["content", "contentArray"])
        _arrangementDidChange()
    }

    private func _arrangementDidChange() {
        _didChange(["arrangedObjects", "canSelectNext", "canSelectPrevious"])
        _selectionDidChange()
    }

    private func _selectionDidChange() {
        _NSBindings.push(self, .selectionIndexes, _selection)
        _didChange(["selectionIndexes", "selectionIndex", "selectedObjects", "selection", "canRemove", "canSelectNext", "canSelectPrevious"])
    }

    /// With `automaticallyRearrangesObjects`, a change of any rearrangement key (or any key a
    /// model announces by hand) on any content object rearranges.
    private func _observeForRearrangement() {
        for t in _rearrangementTokens { t.invalidate() }
        _rearrangementTokens = []
        guard _automaticallyRearrangesObjects else { return }
        let keys = [_KVO.anyKey] + (automaticRearrangementKeyPaths ?? []).compactMap { _KVC.components($0).first }
        for o in _objects {
            guard let obj = _KVC.object(o) else { continue }
            for k in keys {
                _rearrangementTokens.append(_KVO.add(obj, key: k) { [weak self] in self?.rearrangeObjects() })
            }
        }
    }

    // MARK: Key-value coding and bindings

    internal override func _kvcSubclassValue(forKey key: String) -> Any?? {
        switch key {
        case "arrangedObjects": return .some(arrangedObjects)
        case "selectionIndexes": return .some(selectionIndexes)
        case "selectionIndex": return .some(selectionIndex)
        case "sortDescriptors": return .some(sortDescriptors)
        case "filterPredicate": return .some(filterPredicate)
        case "canInsert": return .some(canInsert)
        case "canSelectNext": return .some(canSelectNext)
        case "canSelectPrevious": return .some(canSelectPrevious)
        case "contentArray": return .some(_objects)
        default: return nil
        }
    }

    internal override func _kvcSubclassSetValue(_ value: Any?, forKey key: String) -> Bool {
        switch key {
        case "selectionIndexes": _ = setSelectionIndexes((value as? IndexSet) ?? IndexSet())
        case "selectionIndex": _ = setSelectionIndex((value as? Int) ?? NSNotFound)
        case "selectedObjects": _ = setSelectedObjects(Self._array(value))
        case "sortDescriptors": sortDescriptors = (value as? [NSSortDescriptor]) ?? []
        case "filterPredicate": filterPredicate = value as? NSPredicate
        case "contentArray": content = value
        default: return false
        }
        return true
    }

    internal override func _applySubclassBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .contentArray: _replaceContent(Self._array(b.value))
        case .selectionIndexes: _ = setSelectionIndexes((b.value as? IndexSet) ?? IndexSet())
        case .sortDescriptors:
            _sortDescriptors = (b.value as? [NSSortDescriptor]) ?? []
            _didChange(["sortDescriptors"])
            didChangeArrangementCriteria()
        case .filterPredicate:
            _filterPredicate = b.value as? NSPredicate
            _didChange(["filterPredicate"])
            didChangeArrangementCriteria()
        default: return false
        }
        return true
    }
}

/// The key paths a predicate compares (for `automaticRearrangementKeyPaths`).
enum _NSPredicateKeyPaths {
    static func keyPaths(in predicate: NSPredicate?) -> [String] {
        guard let predicate else { return [] }
        if let c = predicate as? NSCompoundPredicate {
            return c.subpredicates.flatMap { keyPaths(in: $0 as? NSPredicate) }
        }
        #if !canImport(ObjectiveC)
        if let r = predicate as? _NSRuleComparisonPredicate { return [r.keyPath] }
        #endif
        #if canImport(ObjectiveC)
        if let c = predicate as? NSComparisonPredicate {
            return [c.leftExpression, c.rightExpression].compactMap { $0.expressionType == .keyPath ? $0.keyPath : nil }
        }
        #endif
        return []
    }
}
