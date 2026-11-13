// NSTreeNode (hand-written; seeded from the generated stub, see tools/apigen)
//
// A node of a tree of represented objects. `mutableChildren` is a live array: inserting or
// removing through it re-parents the nodes (ADR-0032).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode
open class NSTreeNode: NSObject {
    private let _representedObject: Any?
    internal var _children: [NSTreeNode] = []
    internal weak var _parent: NSTreeNode?
    /// A tree controller's answer from `leafKeyPath`/`countKeyPath`; nil means "no children".
    internal var _leafOverride: Bool?
    #if !canImport(ObjectiveC)
    private lazy var _mutableChildren = _NSTreeNodeChildArray(node: self)
    #endif

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/init(representedobject:)
    public init(representedObject modelObject: Any?) {
        _representedObject = modelObject
        super.init()
    }
    /// The child nodes (empty for a node without children).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/children
    open var children: [NSTreeNode]? { _children }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/descendant(at:)
    open func descendant(at indexPath: IndexPath) -> NSTreeNode? {
        var node: NSTreeNode = self
        for i in indexPath {
            guard i >= 0, i < node._children.count else { return nil }
            node = node._children[i]
        }
        return node
    }
    /// The path from the root of the tree: empty for a root node.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/indexpath
    open var indexPath: IndexPath {
        var path: [Int] = []
        var node = self
        while let p = node._parent, let i = p._children.firstIndex(where: { $0 === node }) {
            path.insert(i, at: 0)
            node = p
        }
        return IndexPath(indexes: path)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/isleaf
    open var isLeaf: Bool { _leafOverride ?? _children.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/mutablechildren
    open var mutableChildren: NSMutableArray {
        #if canImport(ObjectiveC)
        // Swift cannot subclass NSArray on Apple's Foundation; a key-value coding collection
        // proxy over the accessors below is just as live.
        return mutableArrayValue(forKey: "childNodesProxy")
        #else
        return _mutableChildren
        #endif
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/parent
    open var parent: NSTreeNode? { _parent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/representedobject
    open var representedObject: Any? { _representedObject }
    /// Sorts the children by comparing their represented objects.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstreenode/sort(with:recursively:)
    open func sort(with sortDescriptors: [NSSortDescriptor], recursively: Bool) {
        if !sortDescriptors.isEmpty {
            _children = NSTreeNode._sorted(_children, by: sortDescriptors) { $0.representedObject as Any }
        }
        if recursively { for c in _children { c.sort(with: sortDescriptors, recursively: true) } }
        _KVO.didChange(self, key: "childNodes")
    }

    // MARK: Internals

    #if canImport(ObjectiveC)
    @objc(countOfChildNodesProxy) internal func _countOfChildNodesProxy() -> Int { _children.count }
    @objc(objectInChildNodesProxyAtIndex:) internal func _objectInChildNodesProxy(at index: Int) -> Any { _children[index] }
    @objc(insertObject:inChildNodesProxyAtIndex:) internal func _insertInChildNodesProxy(_ object: Any, at index: Int) {
        guard let n = object as? NSTreeNode else { fatalError("[NSTreeNode mutableChildren]: \(type(of: object)) is not an NSTreeNode") }
        _insertChild(n, at: index)
    }
    @objc(removeObjectFromChildNodesProxyAtIndex:) internal func _removeFromChildNodesProxy(at index: Int) { _removeChild(at: index) }
    #endif

    internal func _setChildren(_ nodes: [NSTreeNode]) {
        for c in _children where c._parent === self { c._parent = nil }
        for n in nodes { n._parent?._removeChild(n); n._parent = self }
        _children = nodes
    }

    internal func _insertChild(_ node: NSTreeNode, at index: Int) {
        node._parent?._removeChild(node)
        node._parent = self
        _children.insert(node, at: min(max(index, 0), _children.count))
        _KVO.didChange(self, key: "childNodes")
    }

    internal func _removeChild(at index: Int) {
        let n = _children.remove(at: index)
        if n._parent === self { n._parent = nil }
        _KVO.didChange(self, key: "childNodes")
    }

    private func _removeChild(_ node: NSTreeNode) {
        if let i = _children.firstIndex(where: { $0 === node }) { _removeChild(at: i) }
    }

    /// A stable sort of `items` by `descriptors` applied to `key(item)`.
    static func _sorted<T>(_ items: [T], by descriptors: [NSSortDescriptor], key: (T) -> Any) -> [T] {
        items.enumerated().sorted { a, b in
            for d in descriptors {
                switch d.compare(key(a.element), to: key(b.element)) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return a.offset < b.offset
        }.map { $0.element }
    }
}

extension NSTreeNode: _NSKeyValueCodingInternal {
    func _kvcValue(forKey key: String) -> Any?? {
        switch key {
        case "representedObject": return .some(representedObject)
        case "childNodes", "children": return .some(_children)
        case "isLeaf", "leaf": return .some(isLeaf)
        case "indexPath": return .some(indexPath)
        case "parentNode", "parent": return .some(parent)
        default: return nil
        }
    }
    func _kvcSetValue(_ value: Any?, forKey key: String) -> Bool { false }
}

#if !canImport(ObjectiveC)
/// `mutableChildren`: an NSMutableArray whose primitive methods edit the node's children.
final class _NSTreeNodeChildArray: NSMutableArray {
    private unowned let node: NSTreeNode
    init(node: NSTreeNode) {
        self.node = node
        super.init()
    }
    required init?(coder: NSCoder) { unimplemented() }
    required convenience init(arrayLiteral elements: Any...) { unimplemented() }
    required init(objects: UnsafePointer<AnyObject>?, count cnt: Int) { unimplemented() }

    override var count: Int { node._children.count }
    override func object(at index: Int) -> Any { node._children[index] }
    override func insert(_ anObject: Any, at index: Int) { node._insertChild(Self.node(anObject), at: index) }
    override func removeObject(at index: Int) { node._removeChild(at: index) }
    override func add(_ anObject: Any) { insert(anObject, at: count) }
    override func removeLastObject() { if count > 0 { removeObject(at: count - 1) } }
    override func replaceObject(at index: Int, with anObject: Any) {
        removeObject(at: index)
        insert(anObject, at: index)
    }

    private static func node(_ object: Any) -> NSTreeNode {
        guard let n = object as? NSTreeNode else {
            fatalError("[NSTreeNode mutableChildren]: \(type(of: object)) is not an NSTreeNode")
        }
        return n
    }
}
#endif
