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
    /// Set by `.zIndex`; siblings' backing views are stacked by it (ties keep tree order).
    var zIndex: Double? = nil
    /// The z-index this subtree asks its container for: its own, else its single child's.
    var effectiveZIndex: Double { zIndex ?? (children.count == 1 ? children[0].effectiveZIndex : 0) }
    /// `.gridColumnAlignment` and `.gridCellColumns` on this subtree (a cell's single-child
    /// chain is searched, as for the z-index).
    var gridColumnAlignment: HorizontalAlignment? = nil
    var gridCellColumns: Int? = nil
    /// `.layoutValue(key:value:)` values a `Layout` reads through its subview proxies.
    var layoutValues: [ObjectIdentifier: Any] = [:]
    func trait<T>(_ keyPath: KeyPath<_ViewNode, T?>) -> T? {
        if let v = self[keyPath: keyPath] { return v }
        return children.count == 1 ? children[0].trait(keyPath) : nil
    }
    /// A trait set on this leaf or on the transparent wrappers between it and `container`
    /// (a container lists its layout leaves, which sit below such wrappers).
    func trait<T>(_ keyPath: KeyPath<_ViewNode, T?>, upTo container: _ViewNode?) -> T? {
        if let v = trait(keyPath) { return v }
        var p = parent
        while let n = p, n !== container {
            if let v = n[keyPath: keyPath] { return v }
            p = n.parent
        }
        return nil
    }
    /// The view's dimensions at `size`, with the baselines of the first and last text in it.
    func dimensions(for size: CGSize) -> ViewDimensions {
        var first: CGFloat? = nil, last: CGFloat? = nil
        func visit(_ n: _ViewNode) {
            if let t = n.primitive as? _TextPrimitive {
                let b = t.baselines(for: size)
                if first == nil { first = b.first }
                last = size.height - (t.lastMeasuredHeight - b.last)
                return
            }
            for c in n.children { visit(c) }
        }
        visit(self)
        return ViewDimensions(width: size.width, height: size.height, firstBaseline: first, lastBaseline: last)
    }
    /// Children in drawing order: by z-index, stable.
    var childrenByZIndex: [_ViewNode] {
        guard children.count > 1, children.contains(where: { $0.effectiveZIndex != 0 }) else { return children }
        return children.enumerated().sorted { a, b in
            let (za, zb) = (a.element.effectiveZIndex, b.element.effectiveZIndex)
            return za == zb ? a.offset < b.offset : za < zb
        }.map(\.element)
    }
    var onAppear: [() -> Void] = []
    var onDisappear: [() -> Void] = []
    private var appeared = false
    // Animation state (Animation.swift drives it): interpolated presentation, running
    // animations, exit transitions and the implicit animation of an `.animation` scope.
    var presentation = _Presentation()
    var runningAnimations: [_RunningAnimation] = []
    var implicitAnimation: Animation? = nil
    var transition: AnyTransition? = nil
    var insertedThisPass = false
    var hasLaidOut = false
    var isExiting = false
    var exiting: [_ViewNode] = []

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
        if NSView._traceInvalidation { NSView._trace("setNeedsUpdate \(viewType)") }
        needsUpdate = true
        root?.noteTransaction(Transaction._current)
        root?.scheduleUpdate()
    }

    /// The animation in effect for changes found in this pass: the transaction's, else the
    /// nearest enclosing `.animation(_:value:)` scope whose value changed.
    var effectiveAnimation: Animation? {
        if let a = root?.transactionAnimation { return a }
        var n: _ViewNode? = self
        while let node = n {
            if let a = node.implicitAnimation { return a }
            n = node.parent
        }
        return nil
    }

    /// Starts (or retargets) an animation of one presentation property.
    func animate(_ property: _Presentation.Property, from: [CGFloat], to: [CGFloat], with animation: Animation) {
        runningAnimations.removeAll { $0.property == property }
        runningAnimations.append(_RunningAnimation(property: property, from: from, to: to, animation: animation, start: CARuntime.now()))
        if NSView._traceInvalidation { NSView._trace("animate \(viewType) \(property) \(from) -> \(to) at \(CARuntime.now())") }
        presentation.set(property, from)          // shown at the start value until the first frame
        root?.animationsDidStart()
    }

    /// Advances running animations to `now`; true while any is still running.
    func advanceAnimations(now: CFTimeInterval) -> Bool {
        guard !runningAnimations.isEmpty else { return false }
        var remaining: [_RunningAnimation] = []
        for a in runningAnimations {
            let elapsed = now - a.start
            let p = a.animation.progress(at: elapsed)
            presentation.set(a.property, a.from.indices.map { a.from[$0] + (a.to[$0] - a.from[$0]) * CGFloat(p) })
            if a.animation.totalDuration.isFinite, elapsed >= a.animation.totalDuration {
                presentation.set(a.property, a.to)
                if a.property == .transition, presentation.transition <= 0, isExiting { finishExit() }
            } else {
                remaining.append(a)
            }
        }
        runningAnimations = remaining
        primitive?.didSyncBackingViews(node: self)
        return !runningAnimations.isEmpty
    }

    /// Begins the removal transition; the node leaves the tree when it ends.
    func beginExit(with animation: Animation) {
        isExiting = true
        parent?.exiting.append(self)
        animate(.transition, from: [presentation.transition], to: [0], with: animation)
    }

    private func finishExit() {
        let p = parent
        p?.exiting.removeAll { $0 === self }
        remove()
    }

    /// The frame currently shown (interpolated while a frame animation runs).
    var presentedFrame: CGRect { presentation.frame ?? frame }

    // MARK: Update

    /// Brings this node up to date with `box` under `environment`. `force` re-evaluates the
    /// body even when nothing of this node's own changed (the parent handed a new value).
    func update(box newBox: _AnyViewBox?, environment env: EnvironmentValues, force: Bool) {
        if let newBox { box = newBox }
        let envChanged = !_sameEnvironment(environment, env)
        environment = env
        let rerun = force || needsUpdate || envChanged || newBox != nil
        if rerun { sizeCache.removeAll(keepingCapacity: true) }
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
                node.insertedThisPass = true
                root?.noteInserted(node)
            }
            node.parent = self
            node.update(box: b, environment: env, force: force || match == nil)
            next.append(node)
        }
        for o in old where o !== _placeholder {
            if let t = o.transition, let anim = o.effectiveAnimation, t.removal != .identity, !o.isExiting {
                o.beginExit(with: anim)
            } else {
                o.remove()
            }
        }
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

    /// Measurements are memoised per proposal for one layout pass (the root's generation):
    /// stacks probe each item's flexibility with extra proposals, and nested stacks would
    /// otherwise measure the leaves exponentially often (SwiftUICharts' hierarchy).
    private var sizeCache: [_SizeKey: CGSize] = [:]
    private var sizeCacheGeneration = -1
    private struct _SizeKey: Hashable { let width: CGFloat?; let height: CGFloat? }

    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let generation = root?.measureGeneration ?? -1
        if generation != sizeCacheGeneration { sizeCache.removeAll(keepingCapacity: true); sizeCacheGeneration = generation }
        let key = _SizeKey(width: proposal.width, height: proposal.height)
        if generation >= 0, let cached = sizeCache[key] { return cached }
        let size = computeSizeThatFits(proposal)
        if generation >= 0 { sizeCache[key] = size }
        return size
    }

    private func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
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
        if hasLaidOut, primitive?.nsView != nil, rect != frame, let anim = effectiveAnimation {
            let from = presentedFrame
            animate(.frame, from: [from.minX, from.minY, from.width, from.height], to: [rect.minX, rect.minY, rect.width, rect.height], with: anim)
        } else if runningAnimations.contains(where: { $0.property == .frame }) == false {
            presentation.frame = nil
        }
        frame = rect
        hasLaidOut = true
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
        for c in childrenByZIndex { c.collectBackingViews(into: &out) }
        for e in exiting { e.collectBackingViews(into: &out) }
    }

    /// Puts backing views under their backing ancestors in tree order and sets their frames.
    func syncBackingViews(in container: NSView, containerFrame: CGRect) {
        var views: [NSView] = []
        collectBackingViews(into: &views)
        let current = container.subviews.filter { $0 is _SwiftUIBackedView || views.contains($0) }
        if current.map({ ObjectIdentifier($0) }) != views.map({ ObjectIdentifier($0) }) {
            if NSView._traceInvalidation {
                NSView._trace("syncBackingViews reorders \(type(of: container)): have \(current.map { "\(type(of: $0))" }) want \(views.map { "\(type(of: $0))" })")
            }
            for v in current where !views.contains(v) { v.removeFromSuperview() }
            for v in views { v.removeFromSuperview(); container.addSubview(v) }
        }
        syncFrames(containerFrame: containerFrame)
    }

    func syncFrames(containerFrame: CGRect) {
        if let v = primitive?.nsView {
            let pf = presentedFrame
            let f = CGRect(x: pf.minX - containerFrame.minX, y: pf.minY - containerFrame.minY, width: pf.width, height: pf.height)
            if v.frame != f { v.frame = f }
            // Children of a backing view live inside it, or inside the container the
            // primitive names (a scroll view's document view).
            let inner = primitive?.childContainer ?? v
            for c in children { c.syncBackingViews(in: inner, containerFrame: pf) }
            for e in exiting { e.syncBackingViews(in: inner, containerFrame: pf) }
            primitive?.didSyncBackingViews(node: self)
            return
        }
        for c in children { c.syncFrames(containerFrame: containerFrame) }
        for e in exiting { e.syncFrames(containerFrame: containerFrame) }
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
    /// Where the children's backing views go; nil puts them inside `nsView` itself.
    open var childContainer: NSView? { nil }
    /// Node trees the primitive owns outside `node.children` (a mask's hierarchy); the
    /// root advances their animations and tooling can find them.
    open var extraNodes: [_ViewNode] { [] }
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
    var mouseUpHandler: ((NSEvent) -> Void)?
    var hoverHandler: ((Bool) -> Void)?
    override func draw(_ dirtyRect: NSRect) { drawHandler?(dirtyRect, self) }
    override func mouseDown(with event: NSEvent) {
        if mouseDownHandler?(event) != true { super.mouseDown(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if let h = mouseUpHandler { h(event) } else { super.mouseUp(with: event) }
    }
    override func mouseEntered(with event: NSEvent) { hoverHandler?(true) }
    override func mouseExited(with event: NSEvent) { hoverHandler?(false) }
    override var acceptsFirstResponder: Bool { false }
    /// Set by a custom button: the container is then an AXButton that presses through it.
    var accessibilityPress: (() -> Void)?
    override func isAccessibilityElement() -> Bool { accessibilityPress != nil || super.isAccessibilityElement() }
    override func accessibilityRole() -> NSAccessibility.Role? { super.accessibilityRole() ?? (accessibilityPress != nil ? .button : nil) }
    /// A custom button is labelled by the text it contains.
    override func accessibilityLabel() -> String? {
        if let l = super.accessibilityLabel() { return l }
        guard accessibilityPress != nil else { return nil }
        func texts(_ v: NSView) -> [String] { (v as? _TextView).map { [$0.storage.string] } ?? v.subviews.flatMap(texts) }
        let t = texts(self).filter { !$0.isEmpty }
        return t.isEmpty ? nil : t.joined(separator: " ")
    }
    /// The label text is read through the button; it is not a separate element.
    override func accessibilityChildren() -> [Any]? { accessibilityPress != nil ? [] : super.accessibilityChildren() }
    override func accessibilityPerformPress() -> Bool {
        guard let press = accessibilityPress, !isHiddenOrHasHiddenAncestor else { return false }
        press()
        return true
    }
    var passesThroughHits = true
    /// Recognizers the decoration installed for `.gesture` modifiers.
    var installedRecognizers: [NSGestureRecognizer] = []
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === self, passesThroughHits, mouseDownHandler == nil, hoverHandler == nil, installedRecognizers.isEmpty { return nil }
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
    /// The animation of the transaction that caused the pending update, if any.
    public private(set) var transactionAnimation: Animation?
    private var implicitScopes: [_ViewNode] = []
    private var insertedNodes: [_ViewNode] = []
    private var animating: [_ViewNode] = []
    private var displayLink: CADisplayLink?

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

    func noteTransaction(_ t: Transaction?) {
        if let a = t?.animation, !(t?.disablesAnimations ?? false) { transactionAnimation = a }
    }
    func noteImplicitAnimation(_ node: _ViewNode) { implicitScopes.append(node) }
    func noteInserted(_ node: _ViewNode) { insertedNodes.append(node) }

    func animationsDidStart() {
        guard displayLink == nil, let host else { return }
        let link = host.makeDisplayLink { [weak self] _ in self?.advanceAnimations() }
        link.add(to: .main, forMode: .default)
        displayLink = link
    }

    /// One animation frame: advances every running animation and redraws.
    public func advanceAnimations() {
        let now = CARuntime.now()
        var still = false
        func visit(_ n: _ViewNode) {
            if n.advanceAnimations(now: now) { still = true }
            for c in n.children { visit(c) }
            for e in n.exiting { visit(e) }
            for x in n.primitive?.extraNodes ?? [] { visit(x) }
        }
        if let r = rootNode { visit(r) }
        if let r = rootNode, let host { r.syncBackingViews(in: host.hostView, containerFrame: .zero) }
        host?.setNeedsDisplay(in: nil)
        if NSView._traceInvalidation { NSView._trace("advanceAnimations at \(now): still animating \(still)") }
        if !still {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    /// True while any node animates (tests).
    public var isAnimating: Bool { displayLink != nil }

    private var dirty = false
    /// Set once a preference primitive attaches; the tree is then walked after layout.
    var usesPreferences = false
    /// Bumped whenever the tree may have changed; nodes drop their measurement memo.
    var measureGeneration = 0

    func scheduleUpdate() {
        dirty = true
        guard !updateScheduled, let host else { return }
        updateScheduled = true
        host.setNeedsLayout()
        host.invalidateIntrinsicContentSize()
        host.setNeedsDisplay(in: nil)
    }

    /// Re-evaluates stale bodies and reconciles the tree.
    public func updateIfNeeded() {
        updateScheduled = false
        dirty = false
        measureGeneration &+= 1
        guard let node = rootNode else { return }
        node.update(box: contentChanged ? contentBox : nil, environment: rootEnvironment, force: contentChanged)
        contentChanged = false
    }

    public func sizeThatFits(_ proposal: NSHostingSizeProposal) -> NSSize {
        updateIfNeeded()
        measureGeneration &+= 1
        guard let node = rootNode else { return .zero }
        let s = node.sizeThatFits(ProposedViewSize(width: proposal.width, height: proposal.height))
        return NSSize(width: s.width.rounded(.up), height: s.height.rounded(.up))
    }

    public func layout(in bounds: NSRect) {
        updateIfNeeded()
        measureGeneration &+= 1
        guard let node = rootNode, let host else { return }
        node.place(in: bounds)
        deliverPreferences()
        // Bodies may feed state back during a pass (a page setting its navigation title,
        // an onPreferenceChange handler storing a height): settle such updates now rather
        // than a display cycle later.
        var passes = 0
        while dirty && passes < 4 {
            passes += 1
            updateIfNeeded()
            measureGeneration &+= 1
            node.place(in: bounds)
            deliverPreferences()
        }
        if NSView._traceInvalidation { NSView._trace("root layout in \(bounds): \(passes) settle passes, still dirty: \(dirty)") }
        node.syncBackingViews(in: host.hostView, containerFrame: .zero)
        // Insertion transitions start once the new nodes have a frame.
        for n in insertedNodes where n.isAttached {
            if let t = n.transition, t.insertion != .identity, let anim = n.effectiveAnimation {
                n.presentation.transition = 0
                n.animate(.transition, from: [0], to: [1], with: anim)
                n.primitive?.didSyncBackingViews(node: n)
            }
            n.insertedThisPass = false
        }
        insertedNodes = []
        for s in implicitScopes { s.implicitAnimation = nil }
        implicitScopes = []
        transactionAnimation = nil
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
            for x in n.primitive?.extraNodes ?? [] { if let f = visit(x) { return f } }
            return nil
        }
        return rootNode.flatMap(visit)
    }
}


// MARK: Presentation

/// The values a node is currently shown with (its model values while nothing animates).
public struct _Presentation {
    public enum Property: Equatable { case frame, opacity, offset, scale, rotation, rotation3D, transition, custom }
    public var frame: CGRect? = nil
    public var opacity: CGFloat = 1
    public var offset = CGSize.zero
    public var scale = CGSize(width: 1, height: 1)
    public var rotation: CGFloat = 0           // radians
    public var rotation3D: CGFloat = 0         // radians, about the `.rotation3DEffect` axis
    public var transition: CGFloat = 1         // 1 = fully present, 0 = removed state
    /// A primitive's own animatable vector (a gradient's end points); nil when at rest.
    public var custom: [CGFloat]? = nil

    mutating func set(_ p: Property, _ v: [CGFloat]) {
        switch p {
        case .frame: if v.count == 4 { frame = CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }
        case .opacity: opacity = v[0]
        case .offset: if v.count == 2 { offset = CGSize(width: v[0], height: v[1]) }
        case .scale: if v.count == 2 { scale = CGSize(width: v[0], height: v[1]) }
        case .rotation: rotation = v[0]
        case .rotation3D: rotation3D = v[0]
        case .transition: transition = v[0]
        case .custom: custom = v
        }
    }
}

struct _RunningAnimation {
    let property: _Presentation.Property
    let from: [CGFloat]
    let to: [CGFloat]
    let animation: Animation
    let start: CFTimeInterval
}
