// NSTreeController (hand-written; seeded from the generated stub, see tools/apigen)
//
// A tree of NSTreeNodes over model objects whose children are found at `childrenKeyPath`
// (and whose leaf state comes from `leafKeyPath`, else from `countKeyPath`, else from the
// number of children). `arrangedObjects` is a root node whose descendants are addressed by
// index paths; the selection is a list of index paths. Insertions and removals edit the model
// through key-value coding (the root array, or a parent's children array) and rebuild the
// tree; changes a model announces for the key paths rebuild it too (ADR-0032).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller
open class NSTreeController: NSObjectController {
    private var _roots: [Any] = []
    private var _root = NSTreeNode(representedObject: nil)
    private var _selection: [IndexPath] = []
    private var _childrenKeyPath: String?
    private var _countKeyPath: String?
    private var _leafKeyPath: String?
    private var _sortDescriptors: [NSSortDescriptor] = []
    private var _alwaysUsesMultipleValuesMarker = false
    private var _avoidsEmptySelection = true
    private var _preservesSelection = true
    private var _selectsInsertedObjects = true
    private var _modelTokens: [_KVOToken] = []

    internal override func _setContentFromInit(_ content: Any) {
        _roots = NSArrayController._array(content)
        _rebuild(selecting: nil)
    }

    /// Adds a new object after the selection's siblings (at the end of the roots without one).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/add(_:)
    @MainActor open override func add(_ sender: Any?) {
        _performDeferred { [self] in
            let parentPath = selectionIndexPath.map { $0.dropLast() } ?? IndexPath()
            let count = (_root.descendant(at: parentPath)?._children.count) ?? 0
            insert(newObject(), atArrangedObjectIndexPath: parentPath.appending(count))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/addchild(_:)
    @MainActor open func addChild(_ sender: Any?) {
        _performDeferred { [self] in
            guard let path = selectionIndexPath, let node = _root.descendant(at: path) else { return }
            insert(newObject(), atArrangedObjectIndexPath: path.appending(node._children.count))
        }
    }
    /// Appends `object` to the root objects.
    open override func addObject(_ object: Any) {
        insert(object, atArrangedObjectIndexPath: IndexPath(index: _root._children.count))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/addselectionindexpaths(_:)
    open func addSelectionIndexPaths(_ indexPaths: [IndexPath]) -> Bool {
        setSelectionIndexPaths(_selection + indexPaths.filter { !_selection.contains($0) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/alwaysusesmultiplevaluesmarker
    open var alwaysUsesMultipleValuesMarker: Bool {
        get { _alwaysUsesMultipleValuesMarker }
        set { _alwaysUsesMultipleValuesMarker = newValue; _didChange(["selection"]) }
    }
    /// The root of the arranged tree; its children are the content objects' nodes.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/arrangedobjects
    open var arrangedObjects: NSTreeNode { _root }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/avoidsemptyselection
    open var avoidsEmptySelection: Bool {
        get { _avoidsEmptySelection }
        set { _avoidsEmptySelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/canaddchild
    open var canAddChild: Bool { isEditable && _childrenKeyPath != nil && selectedNodes.count == 1 && !selectedNodes[0].isLeaf }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/caninsert
    open var canInsert: Bool { isEditable }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/caninsertchild
    open var canInsertChild: Bool { canAddChild }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/childrenkeypath
    open var childrenKeyPath: String? {
        get { _childrenKeyPath }
        set { _childrenKeyPath = newValue; rearrangeObjects() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/childrenkeypath(for:)
    open func childrenKeyPath(for node: NSTreeNode) -> String? { _childrenKeyPath }
    /// The root objects (`[Any]`); setting accepts an array or a single root object.
    // INHERITED (identical redeclaration): var content: Any? { get set }
    open override var content: Any? {
        get { _roots }
        set {
            _roots = NSArrayController._array(newValue)
            _didChange(["content"])
            _rebuild(selecting: nil)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/countkeypath
    open var countKeyPath: String? {
        get { _countKeyPath }
        set { _countKeyPath = newValue; rearrangeObjects() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/countkeypath(for:)
    open func countKeyPath(for node: NSTreeNode) -> String? { _countKeyPath }
    /// Inserts a new object at the selection (at the end of the roots without one).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/insert(_:)
    @MainActor open func insert(_ sender: Any?) {
        _performDeferred { [self] in
            insert(newObject(), atArrangedObjectIndexPath: selectionIndexPath ?? IndexPath(index: _root._children.count))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/insert(_:atarrangedobjectindexpath:)
    open func insert(_ object: Any?, atArrangedObjectIndexPath indexPath: IndexPath) {
        guard let object else { return }
        insert([object], atArrangedObjectIndexPaths: [indexPath])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/insert(_:atarrangedobjectindexpaths:)
    open func insert(_ objects: [Any], atArrangedObjectIndexPaths indexPaths: [IndexPath]) {
        precondition(objects.count == indexPaths.count, "[NSTreeController insertObjects:atArrangedObjectIndexPaths:]: count of array (\(objects.count)) differs from count of index paths (\(indexPaths.count))")
        for (object, path) in zip(objects, indexPaths) { _insertModel(object, at: path) }
        _rebuild(selecting: _selectsInsertedObjects ? objects : nil)
    }
    /// Inserts a new object as the first child of the selected node.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/insertchild(_:)
    @MainActor open func insertChild(_ sender: Any?) {
        _performDeferred { [self] in
            guard let path = selectionIndexPath else { return }
            insert(newObject(), atArrangedObjectIndexPath: path.appending(0))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/leafkeypath
    open var leafKeyPath: String? {
        get { _leafKeyPath }
        set { _leafKeyPath = newValue; rearrangeObjects() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/leafkeypath(for:)
    open func leafKeyPath(for node: NSTreeNode) -> String? { _leafKeyPath }
    /// Moves `node`'s object to `indexPath` (an index path in the tree without the node).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/move(_:to:)
    open func move(_ node: NSTreeNode, to indexPath: IndexPath) { move([node], to: indexPath) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/move(_:to:)
    open func move(_ nodes: [NSTreeNode], to startingIndexPath: IndexPath) {
        let objects = nodes.compactMap { $0.representedObject }
        // Remove deepest/last paths first so earlier paths stay valid.
        for path in nodes.map(\.indexPath).sorted(by: >) { _removeModel(at: path) }
        var path = startingIndexPath
        for o in objects {
            _insertModel(o, at: path)
            if let last = path.last { path = path.dropLast().appending(last + 1) }
        }
        _rebuild(selecting: objects)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/preservesselection
    open var preservesSelection: Bool {
        get { _preservesSelection }
        set { _preservesSelection = newValue }
    }
    /// Rebuilds the tree from the model (sorting every level by `sortDescriptors`).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/rearrangeobjects()
    open func rearrangeObjects() { _rebuild(selecting: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/remove(_:)
    @MainActor open override func remove(_ sender: Any?) {
        _performDeferred { [self] in removeObjects(atArrangedObjectIndexPaths: _selection) }
    }
    /// Removes the object (with its subtree) wherever it is in the tree.
    open override func removeObject(_ object: Any) {
        let paths = _allPaths().filter { _KVC.same(_root.descendant(at: $0)?.representedObject, object) }
        removeObjects(atArrangedObjectIndexPaths: paths)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/removeobject(atarrangedobjectindexpath:)
    open func removeObject(atArrangedObjectIndexPath indexPath: IndexPath) { removeObjects(atArrangedObjectIndexPaths: [indexPath]) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/removeobjects(atarrangedobjectindexpaths:)
    open func removeObjects(atArrangedObjectIndexPaths indexPaths: [IndexPath]) {
        let valid = indexPaths.filter { !$0.isEmpty && _root.descendant(at: $0) != nil }
        guard !valid.isEmpty else { return }
        let anchor = valid.min()!
        // A path inside a removed subtree goes with it.
        let roots = valid.filter { p in !valid.contains { q in q != p && q.count < p.count && Array(p.prefix(q.count)) == Array(q) } }
        let selectedBefore = selectedObjects
        for path in roots.sorted(by: >) { _removeModel(at: path) }
        _rebuild(selecting: nil, previouslySelected: selectedBefore, anchor: anchor)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/removeselectionindexpaths(_:)
    open func removeSelectionIndexPaths(_ indexPaths: [IndexPath]) -> Bool {
        setSelectionIndexPaths(_selection.filter { !indexPaths.contains($0) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/selectednodes
    open var selectedNodes: [NSTreeNode] { _selection.compactMap { _root.descendant(at: $0) } }
    // INHERITED (identical redeclaration): var selectedObjects: [Any] { get }
    open override var selectedObjects: [Any] { selectedNodes.compactMap { $0.representedObject } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/selectionindexpath
    open var selectionIndexPath: IndexPath? { _selection.first }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/selectionindexpaths
    open var selectionIndexPaths: [IndexPath] { _selection }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/selectsinsertedobjects
    open var selectsInsertedObjects: Bool {
        get { _selectsInsertedObjects }
        set { _selectsInsertedObjects = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/setselectionindexpath(_:)
    open func setSelectionIndexPath(_ indexPath: IndexPath?) -> Bool { setSelectionIndexPaths(indexPath.map { [$0] } ?? []) }
    /// Selects the paths that exist in the tree (sorted), after committing pending edits.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/setselectionindexpaths(_:)
    open func setSelectionIndexPaths(_ indexPaths: [IndexPath]) -> Bool {
        var valid: [IndexPath] = []
        for p in indexPaths.sorted() where !p.isEmpty && _root.descendant(at: p) != nil && !valid.contains(p) { valid.append(p) }
        guard valid != _selection else { return false }
        guard MainActor.assumeIsolated({ commitEditing() }) else { return false }
        _selection = valid
        _selectionDidChange()
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreecontroller/sortdescriptors
    open var sortDescriptors: [NSSortDescriptor] {
        get { _sortDescriptors }
        set {
            _sortDescriptors = newValue
            _didChange(["sortDescriptors"])
            _NSBindings.push(self, .sortDescriptors, newValue)
            rearrangeObjects()
        }
    }

    // MARK: Model edits

    /// The model array that holds the children of the node at `parentPath`, and a writer for it.
    private func _childArray(at parentPath: IndexPath) -> (objects: [Any], write: ([Any]) -> Void)? {
        if parentPath.isEmpty {
            return (_roots, { [self] in _roots = $0; _NSBindings.push(self, .contentArray, $0); _didChange(["content"]) })
        }
        guard let key = _childrenKeyPath, let parent = _root.descendant(at: parentPath)?.representedObject else { return nil }
        let kids = NSArrayController._array(_KVC.value(parent, forKeyPath: key))
        return (kids, { _KVC.setValue($0, on: parent, forKeyPath: key) })
    }

    /// Inserts into the model so the object appears at `path` of the arranged tree (before the
    /// object now at that position).
    private func _insertModel(_ object: Any, at path: IndexPath) {
        guard let index = path.last, let array = _childArray(at: path.dropLast()) else { return }
        var objs = array.objects
        let siblings = _root.descendant(at: path.dropLast())?._children ?? []
        var at = objs.count
        if index < siblings.count, let i = objs.firstIndex(where: { _KVC.same($0, siblings[index].representedObject) }) { at = i }
        objs.insert(object, at: at)
        array.write(objs)
    }

    private func _removeModel(at path: IndexPath) {
        guard let node = _root.descendant(at: path), let array = _childArray(at: path.dropLast()) else { return }
        var objs = array.objects
        guard let i = objs.firstIndex(where: { _KVC.same($0, node.representedObject) }) else { return }
        objs.remove(at: i)
        array.write(objs)
    }

    // MARK: Building the tree

    private func _rebuild(selecting inserted: [Any]?, previouslySelected: [Any]? = nil, anchor: IndexPath? = nil) {
        let selectedBefore = previouslySelected ?? selectedObjects
        let oldSelection = _selection
        for t in _modelTokens { t.invalidate() }
        _modelTokens = []
        let root = NSTreeNode(representedObject: nil)
        root._setChildren(_nodes(for: _roots, depth: 0))
        _root = root
        if let inserted, !inserted.isEmpty {
            _selection = _paths(of: inserted)
        } else if _preservesSelection {
            _selection = _paths(of: selectedBefore)
        } else {
            _selection = oldSelection.filter { root.descendant(at: $0) != nil }
        }
        if _selection.isEmpty, _avoidsEmptySelection, !root._children.isEmpty {
            _selection = [anchor.map { _nearestPath(to: $0) } ?? IndexPath(index: 0)]
        }
        _didChange(["arrangedObjects"])
        _selectionDidChange()
    }

    private func _nodes(for objects: [Any], depth: Int) -> [NSTreeNode] {
        var nodes: [NSTreeNode] = []
        for o in objects {
            let node = NSTreeNode(representedObject: o)
            _observeModel(o)
            var kids: [Any] = []
            if let key = _childrenKeyPath { kids = NSArrayController._array(_KVC.value(o, forKeyPath: key)) }
            if let key = _leafKeyPath {
                node._leafOverride = _KVC.bool(_KVC.value(o, forKeyPath: key))
            } else if let key = _countKeyPath {
                node._leafOverride = (_KVC.number(_KVC.value(o, forKeyPath: key) ?? 0) ?? 0) == 0
            } else {
                node._leafOverride = kids.isEmpty
            }
            if node._leafOverride != true || !kids.isEmpty { node._setChildren(_nodes(for: kids, depth: depth + 1)) }
            nodes.append(node)
        }
        if !_sortDescriptors.isEmpty {
            nodes = NSTreeNode._sorted(nodes, by: _sortDescriptors) { $0.representedObject as Any }
        }
        return nodes
    }

    private func _observeModel(_ object: Any) {
        guard let obj = _KVC.object(object) else { return }
        for key in [_childrenKeyPath, _leafKeyPath, _countKeyPath].compactMap({ $0 }).compactMap({ _KVC.components($0).first }) {
            _modelTokens.append(_KVO.add(obj, key: key) { [weak self] in self?.rearrangeObjects() })
        }
    }

    private func _allPaths() -> [IndexPath] {
        var out: [IndexPath] = []
        func walk(_ n: NSTreeNode, _ p: IndexPath) {
            for (i, c) in n._children.enumerated() {
                let cp = p.appending(i)
                out.append(cp)
                walk(c, cp)
            }
        }
        walk(_root, IndexPath())
        return out
    }

    private func _paths(of objects: [Any]) -> [IndexPath] {
        let all = _allPaths()
        var out: [IndexPath] = []
        for o in objects {
            if let p = all.first(where: { !out.contains($0) && _KVC.same(_root.descendant(at: $0)?.representedObject, o) }) { out.append(p) }
        }
        return out.sorted()
    }

    /// After a removal: the node now at `anchor`, else its previous sibling, else its parent.
    private func _nearestPath(to anchor: IndexPath) -> IndexPath {
        var p = anchor
        while !p.isEmpty {
            if _root.descendant(at: p) != nil { return p }
            if let last = p.last, last > 0 { p = p.dropLast().appending(last - 1); continue }
            p = p.dropLast()
        }
        return IndexPath(index: 0)
    }

    private func _selectionDidChange() {
        _NSBindings.push(self, .selectionIndexPaths, _selection)
        _didChange(["selectionIndexPaths", "selectionIndexPath", "selectedNodes", "selectedObjects", "selection",
                    "canRemove", "canAddChild", "canInsertChild"])
    }

    // MARK: Key-value coding and bindings

    internal override var _usesMultipleValuesMarker: Bool { _alwaysUsesMultipleValuesMarker }

    @MainActor internal override func _performControllerAction(_ name: String, _ sender: Any?) -> Bool? {
        switch name {
        case "insert:": insert(sender)
        case "addChild:": addChild(sender)
        case "insertChild:": insertChild(sender)
        default: return super._performControllerAction(name, sender)
        }
        return true
    }

    internal override func _canPerform(_ selector: String) -> Bool {
        switch selector {
        case "insert:": return canInsert
        case "addChild:": return canAddChild
        case "insertChild:": return canInsertChild
        default: return super._canPerform(selector)
        }
    }

    internal override func _kvcSubclassValue(forKey key: String) -> Any?? {
        switch key {
        case "arrangedObjects": return .some(arrangedObjects)
        case "selectionIndexPaths": return .some(selectionIndexPaths)
        case "selectionIndexPath": return .some(selectionIndexPath)
        case "selectedNodes": return .some(selectedNodes)
        case "sortDescriptors": return .some(sortDescriptors)
        case "canInsert": return .some(canInsert)
        case "canAddChild": return .some(canAddChild)
        case "canInsertChild": return .some(canInsertChild)
        case "contentArray": return .some(_roots)
        default: return nil
        }
    }

    internal override func _kvcSubclassSetValue(_ value: Any?, forKey key: String) -> Bool {
        switch key {
        case "selectionIndexPaths": _ = setSelectionIndexPaths((value as? [IndexPath]) ?? [])
        case "selectionIndexPath": _ = setSelectionIndexPath(value as? IndexPath)
        case "sortDescriptors": sortDescriptors = (value as? [NSSortDescriptor]) ?? []
        case "contentArray": content = value
        default: return false
        }
        return true
    }

    internal override func _applySubclassBinding(_ b: _NSBinding) -> Bool {
        switch b.name {
        case .contentArray: content = b.value
        case .selectionIndexPaths: _ = setSelectionIndexPaths((b.value as? [IndexPath]) ?? [])
        case .sortDescriptors:
            _sortDescriptors = (b.value as? [NSSortDescriptor]) ?? []
            _didChange(["sortDescriptors"])
            rearrangeObjects()
        default: return false
        }
        return true
    }
}
