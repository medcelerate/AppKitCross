// The runtime: type-erased view boxes, the node tree, reconciliation, primitives and the
// hosting root that connects the tree to AppKit's NSHostingView.

import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

// MARK: Boxes

/// A view value with its static type, able to build and update nodes.
@MainActor
public protocol _AnyViewBox {
    var id: AnyHashable? { get }
    var viewType: Any.Type { get }
    var value: Any { get }
    var isPrimitive: Bool { get }
    func makePrimitive(node: _ViewNode) -> _Primitive?
    /// Installs dynamic properties and evaluates `body` (composite views only).
    func body(node: _ViewNode) -> _AnyViewBox?
}

@MainActor
final class _ViewBox<V: View>: _AnyViewBox {
    let view: V
    let id: AnyHashable?
    nonisolated init(_ view: V, id: AnyHashable? = nil) {
        self.view = view
        self.id = id
    }
    var viewType: Any.Type { V.self }
    var value: Any { view }
    var isPrimitive: Bool { V.Body.self == Never.self }
    func makePrimitive(node: _ViewNode) -> _Primitive? {
        if let p = view as? any _PrimitiveView { return p._makePrimitive(node: node) }
        if let r = view as? any NSViewRepresentable { return _makeRepresentablePrimitive(r) }
        if let r = view as? any NSViewControllerRepresentable { return _makeControllerRepresentablePrimitive(r) }
        return nil
    }
    func body(node: _ViewNode) -> _AnyViewBox? {
        guard !isPrimitive else { return nil }
        var slot = 0
        _installDynamicProperties(in: view, node: node, slot: &slot)
        return _ViewBox<V.Body>(view.body)
    }
}

@MainActor func _makeRepresentablePrimitive<R: NSViewRepresentable>(_ r: R) -> _Primitive { _RepresentablePrimitive(r) }
@MainActor func _makeControllerRepresentablePrimitive<R: NSViewControllerRepresentable>(_ r: R) -> _Primitive { _ControllerRepresentablePrimitive(r) }

func _boxView(_ value: Any) -> _AnyViewBox? {
    guard let v = value as? any View else { return nil }
    return _box(v)
}

func _box<V: View>(_ v: V) -> _AnyViewBox { _ViewBox(v) }

// MARK: Nodes

/// One view in the live hierarchy.
@MainActor
public final class _ViewNode {
    public private(set) var box: _AnyViewBox
    public internal(set) weak var root: _ViewRoot?
    public internal(set) weak var parent: _ViewNode?
    public internal(set) var children: [_ViewNode] = []
    public internal(set) var primitive: _Primitive?
    public var environment = EnvironmentValues()
    /// The frame placed by layout, in host view coordinates (y down).
    public internal(set) var frame = CGRect.zero
    var needsUpdate = true
    var isAttached = false
    private var cells: [Int: _StorageCell] = [:]
    private var retained: [Int: AnyObject] = [:]
    /// Set by an enclosing stack before measuring its items (Spacer reads it).
    var stackAxis: Axis? = nil
    var layoutPriority: Double = 0
    var onAppear: [() -> Void] = []
    var onDisappear: [() -> Void] = []
    private var appeared = false

    nonisolated init(box: _AnyViewBox, parent: _ViewNode?, root: _ViewRoot?) {
        self.box = box
        self.parent = parent
        self.root = root
    }

    public var viewType: Any.Type { box.viewType }
    public var backingView: NSView? { primitive?.nsView }

    /// The nearest backing AppKit view above this node (the host view at the top).
    var parentBackingView: NSView? {
        var p = parent
        while let n = p {
            if let v = n.primitive?.nsView { return v }
            p = n.parent
        }
        return root?.host?.hostView
    }

    func storageCell(_ slot: Int, make: () -> _StorageCell) -> _StorageCell {
        if let c = cells[slot] { return c }
        let c = make()
        cells[slot] = c
        return c
    }

    func retain(_ object: AnyObject, slot: Int) { retained[slot] = object }

    /// Marks the body stale; the host lays out again at the next display cycle.
    public func setNeedsUpdate() {
        needsUpdate = true
        root?.scheduleUpdate()
    }

    // MARK: Update

    /// Brings this node up to date with `box` under `environment`. `force` re-evaluates the
    /// body even when nothing of this node's own changed (the parent handed a new value).
    func update(box newBox: _AnyViewBox?, environment env: EnvironmentValues, force: Bool) {
        if let newBox { box = newBox }
        let envChanged = !_sameEnvironment(environment, env)
        environment = env
        let rerun = force || needsUpdate || envChanged || newBox != nil
        if box.isPrimitive {
            if rerun || primitive == nil {
                guard let fresh = box.makePrimitive(node: self) else { return }
                if let old = primitive, type(of: old) == type(of: fresh) {
                    old.update(from: fresh)
                } else {
                    primitive?.detach()
                    primitive = fresh
                    fresh.attach(to: self)
                }
            }
            needsUpdate = false
            var childEnv = env
            primitive?.environmentTransform?(&childEnv)
            reconcile(primitive?.children ?? [], environment: childEnv, force: rerun)
        } else {
            if rerun {
                needsUpdate = false
                if let bodyBox = box.body(node: self) { reconcile([bodyBox], environment: env, force: true) }
            } else {
                for c in children { c.update(box: nil, environment: env, force: false) }
            }
        }
        if !appeared, isAttached {
            appeared = true
            for a in onAppear { a() }
        }
    }

    private func reconcile(_ boxes: [_AnyViewBox], environment env: EnvironmentValues, force: Bool) {
        var old = children
        var next: [_ViewNode] = []
        next.reserveCapacity(boxes.count)
        for (i, b) in boxes.enumerated() {
            var match: _ViewNode? = nil
            if let id = b.id {
                if let k = old.firstIndex(where: { $0.box.id == id && $0.box.viewType == b.viewType }) { match = old.remove(at: k) }
            } else if i < old.count, old[i].box.id == nil, old[i].box.viewType == b.viewType {
                match = old.remove(at: i)
                // Keep positional matching aligned after a removal.
                old.insert(_placeholder, at: i)
            }
            let node: _ViewNode
            if let m = match {
                node = m
            } else {
                node = _ViewNode(box: b, parent: self, root: root)
                node.isAttached = isAttached
            }
            node.parent = self
            node.update(box: b, environment: env, force: force || match == nil)
            next.append(node)
        }
        for o in old where o !== _placeholder { o.remove() }
        children = next
    }

    private var _placeholder: _ViewNode { _ViewNode.placeholder }
    nonisolated(unsafe) static let placeholder: _ViewNode = _ViewNode(box: _ViewBox(EmptyView()), parent: nil, root: nil)

    /// Detaches this subtree (backing views leave the hierarchy, onDisappear fires).
    func remove() {
        for c in children { c.remove() }
        children = []
        if appeared { for d in onDisappear { d() } }
        appeared = false
        primitive?.detach()
        isAttached = false
    }

    func markAttached() {
        isAttached = true
        for c in children { c.markAttached() }
    }

    // MARK: Layout

    /// Items a stack lays out: structural groups are transparent, everything else is one item.
    var layoutLeaves: [_ViewNode] {
        if let p = primitive {
            return p.isLayoutTransparent ? children.flatMap(\.layoutLeaves) : [self]
        }
        return children.flatMap(\.layoutLeaves)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let p = primitive, !p.isLayoutTransparent { return p.sizeThatFits(proposal, node: self) }
        let leaves = layoutLeaves
        if leaves.count == 1 { return leaves[0].sizeThatFits(proposal) }
        var size = CGSize.zero
        for l in leaves {
            let s = l.sizeThatFits(proposal)
            size.width = max(size.width, s.width)
            size.height = max(size.height, s.height)
        }
        return size
    }

    public func place(in rect: CGRect) {
        frame = rect
        if let p = primitive, !p.isLayoutTransparent {
            p.place(node: self, in: rect)
        } else {
            // Several leaves outside a stack overlap like a ZStack.
            let leaves = layoutLeaves
            for l in leaves {
                let s = l.sizeThatFits(ProposedViewSize(rect.size))
                l.place(in: CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height).integralIfNeeded)
            }
            for c in children where !leaves.contains(where: { $0 === c }) { c.frame = rect }
        }
        primitive?.didLayout(node: self)
    }

    /// All backing views in this subtree in drawing order, stopping at nested backing views.
    func collectBackingViews(into out: inout [NSView]) {
        if let v = primitive?.nsView { out.append(v); return }
        for c in children { c.collectBackingViews(into: &out) }
    }

    /// Puts backing views under their backing ancestors in tree order and sets their frames.
    func syncBackingViews(in container: NSView, containerFrame: CGRect) {
        var views: [NSView] = []
        collectBackingViews(into: &views)
        let current = container.subviews.filter { $0 is _SwiftUIBackedView || views.contains($0) }
        if current.map({ ObjectIdentifier($0) }) != views.map({ ObjectIdentifier($0) }) {
            for v in current where !views.contains(v) { v.removeFromSuperview() }
            for v in views { v.removeFromSuperview(); container.addSubview(v) }
        }
        syncFrames(containerFrame: containerFrame)
    }

    private func syncFrames(containerFrame: CGRect) {
        if let v = primitive?.nsView {
            let f = CGRect(x: frame.minX - containerFrame.minX, y: frame.minY - containerFrame.minY, width: frame.width, height: frame.height)
            if v.frame != f { v.frame = f }
            // Children of a backing view live inside it.
            for c in children { c.syncBackingViews(in: v, containerFrame: frame) }
            primitive?.didSyncBackingViews(node: self)
            return
        }
        for c in children { c.syncFrames(containerFrame: containerFrame) }
    }
}

func _sameEnvironment(_ a: EnvironmentValues, _ b: EnvironmentValues) -> Bool {
    a.storage.keys == b.storage.keys && a._objects.count == b._objects.count && a._generation == b._generation
}

extension EnvironmentValues {
    /// Changes bump a generation so nodes notice new values without comparing every entry.
    var _generation: Int { storage.count &* 31 &+ _objects.count }
}

extension CGRect {
    var integralIfNeeded: CGRect { CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded()) }
}

// MARK: Primitives

/// Marker for AppKit views the runtime created (so it can reorder them safely).
@MainActor
protocol _SwiftUIBackedView: AnyObject {}

/// The runtime object behind a primitive view: measures and places its node, and may own
/// an AppKit view. Subclasses implement one of three shapes: transparent groups, content
/// wrappers (one content child) and leaves (an AppKit view, no children).
@MainActor
open class _Primitive {
    public weak var node: _ViewNode?
    public var children: [_AnyViewBox] = []
    public var environmentTransform: ((inout EnvironmentValues) -> Void)?
    public nonisolated init() {}
    open var isLayoutTransparent: Bool { false }
    open var nsView: NSView? { nil }
    open func update(from other: _Primitive) {
        children = other.children
        environmentTransform = other.environmentTransform
    }
    open func attach(to node: _ViewNode) { self.node = node }
    open func detach() { nsView?.removeFromSuperview() }
    /// Default: the single content item, or a ZStack of several.
    open func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let leaves = node.children.flatMap(\.layoutLeaves)
        if leaves.count == 1 { return leaves[0].sizeThatFits(proposal) }
        var size = CGSize.zero
        for l in leaves {
            let s = l.sizeThatFits(proposal)
            size.width = max(size.width, s.width); size.height = max(size.height, s.height)
        }
        return size
    }
    open func place(node: _ViewNode, in rect: CGRect) {
        let leaves = node.children.flatMap(\.layoutLeaves)
        for l in leaves {
            let s = l.sizeThatFits(ProposedViewSize(rect.size))
            l.place(in: CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: min(s.width, rect.width), height: min(s.height, rect.height)).integralIfNeeded)
        }
        for c in node.children where !leaves.contains(where: { $0 === c }) { c.frame = rect }
    }
    open func didLayout(node: _ViewNode) {}
    open func didSyncBackingViews(node: _ViewNode) {}
}

/// A structural group: its children are the stack's items.
@MainActor
public final class _GroupPrimitive: _Primitive {
    public nonisolated init(children: [_AnyViewBox]) {
        super.init()
        self.children = children
    }
    public override var isLayoutTransparent: Bool { true }
}

/// A plain flipped container view for decorated content and documents.
@MainActor
final class _ContainerView: NSView {
    override var isFlipped: Bool { true }
    var drawHandler: ((NSRect, NSView) -> Void)?
    var mouseDownHandler: ((NSEvent) -> Bool)?
    var hoverHandler: ((Bool) -> Void)?
    override func draw(_ dirtyRect: NSRect) { drawHandler?(dirtyRect, self) }
    override func mouseDown(with event: NSEvent) {
        if mouseDownHandler?(event) != true { super.mouseDown(with: event) }
    }
    override func mouseEntered(with event: NSEvent) { hoverHandler?(true) }
    override func mouseExited(with event: NSEvent) { hoverHandler?(false) }
    override var acceptsFirstResponder: Bool { false }
    var passesThroughHits = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === self, passesThroughHits, mouseDownHandler == nil, hoverHandler == nil { return nil }
        return hit
    }
}

// MARK: Root

/// The `NSHostingRoot` of a SwiftUI view tree.
@MainActor
public final class _ViewRoot: NSHostingRoot {
    public internal(set) weak var host: (any NSHostingRootHost)?
    public private(set) var rootNode: _ViewNode?
    private var contentBox: _AnyViewBox
    private var rootEnvironment = EnvironmentValues()
    private var updateScheduled = false
    private var contentChanged = true

    init<V: View>(content: V) { contentBox = _ViewBox(content) }

    func setContent<V: View>(_ content: V) {
        contentBox = _ViewBox(content)
        contentChanged = true
    }

    public func attach(to host: any NSHostingRootHost) {
        self.host = host
        environmentDidChange(host.environment)
        let node = _ViewNode(box: contentBox, parent: nil, root: self)
        rootNode = node
        node.markAttached()
        updateIfNeeded()
    }

    public func detach() {
        rootNode?.remove()
        rootNode = nil
        host = nil
    }

    public func contentDidChange() {
        contentChanged = true
        scheduleUpdate()
    }

    public func environmentDidChange(_ environment: NSHostingEnvironment) {
        rootEnvironment.colorScheme = environment.isDarkAppearance ? .dark : .light
        rootEnvironment.displayScale = environment.displayScale
        rootEnvironment.layoutDirection = environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        rootEnvironment.locale = environment.locale
        switch environment.controlActiveState {
        case .key: rootEnvironment.controlActiveState = .key
        case .active: rootEnvironment.controlActiveState = .active
        case .inactive: rootEnvironment.controlActiveState = .inactive
        }
        rootNode?.needsUpdate = true
        scheduleUpdate()
    }

    func scheduleUpdate() {
        guard !updateScheduled, let host else { return }
        updateScheduled = true
        host.setNeedsLayout()
        host.invalidateIntrinsicContentSize()
        host.setNeedsDisplay(in: nil)
    }

    /// Re-evaluates stale bodies and reconciles the tree.
    public func updateIfNeeded() {
        updateScheduled = false
        guard let node = rootNode else { return }
        node.update(box: contentChanged ? contentBox : nil, environment: rootEnvironment, force: contentChanged)
        contentChanged = false
    }

    public func sizeThatFits(_ proposal: NSHostingSizeProposal) -> NSSize {
        updateIfNeeded()
        guard let node = rootNode else { return .zero }
        let s = node.sizeThatFits(ProposedViewSize(width: proposal.width, height: proposal.height))
        return NSSize(width: s.width.rounded(.up), height: s.height.rounded(.up))
    }

    public func layout(in bounds: NSRect) {
        updateIfNeeded()
        guard let node = rootNode, let host else { return }
        node.place(in: bounds)
        node.syncBackingViews(in: host.hostView, containerFrame: .zero)
        updateScheduled = false
    }

    public func draw(_ dirtyRect: NSRect, in context: NSGraphicsContext) {}
    public func handle(_ event: NSEvent) -> Bool { false }
    public func responder(at point: NSPoint) -> NSResponder? { nil }

    /// The node for a view type, depth first (tests and tooling).
    public func firstNode(where predicate: (_ViewNode) -> Bool) -> _ViewNode? {
        func visit(_ n: _ViewNode) -> _ViewNode? {
            if predicate(n) { return n }
            for c in n.children { if let f = visit(c) { return f } }
            return nil
        }
        return rootNode.flatMap(visit)
    }
}
