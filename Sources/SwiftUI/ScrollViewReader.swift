// Programmatic scrolling and scroll-view configuration from outside the scroll view:
// `ScrollViewReader`/`ScrollViewProxy.scrollTo(_:anchor:)`, `defaultScrollAnchor(_:for:)`
// and `scrollIndicators(_:axes:)`. Each finds the scroll views (a `ScrollView`, or the one
// inside a `List`) in its content's node tree and drives their `NSScrollView`.

import Foundation

// MARK: Finding scroll views

extension _ViewNode {
    /// The outermost scroll views in this subtree (a scroll view nested in another is
    /// reached through its outer one only).
    var _outermostScrollNodes: [_ViewNode] {
        if primitive is _ScrollPrimitive { return [self] }
        return children.flatMap(\._outermostScrollNodes)
    }

    /// The first node in this subtree whose identity (`.id(_:)`, or a `ForEach` element's
    /// id) is `id`.
    func _descendant(withID id: AnyHashable) -> _ViewNode? {
        if box.id == id { return self }
        for c in children { if let f = c._descendant(withID: id) { return f } }
        return nil
    }

    /// The frame layout gave this node; for a structural group (a `ForEach` element, an
    /// `.id` wrapper) that layout passes through, the union of its laid-out leaves.
    var _laidOutFrame: CGRect? {
        if hasLaidOut { return frame }
        let frames = children.compactMap(\._laidOutFrame)
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// The nearest scroll view above this node.
    var _enclosingScrollNode: _ViewNode? {
        var p = parent
        while let n = p {
            if n.primitive is _ScrollPrimitive { return n }
            p = n.parent
        }
        return nil
    }
}

extension _ScrollPrimitive {
    /// Scrolls so `anchor` of `target` (a rect in the document's coordinates, y down) lines
    /// up with the same point of the visible area; with no anchor, by the least amount that
    /// shows the whole rect (its top edge when it is taller than the view).
    func _scroll(toShow target: CGRect, anchor: UnitPoint?) {
        let visible = scroll.contentSize
        let doc = document.frame.size
        var origin = scroll.contentView.bounds.origin
        func place(_ lo: CGFloat, _ length: CGFloat, _ current: CGFloat, _ view: CGFloat, _ unit: CGFloat?) -> CGFloat {
            if let unit { return lo + unit * length - unit * view }
            if length >= view || lo < current { return lo }
            if lo + length > current + view { return lo + length - view }
            return current
        }
        if axes.contains(.vertical) {
            origin.y = place(target.minY, target.height, origin.y, visible.height, anchor?.y)
            origin.y = min(max(0, origin.y), max(0, doc.height - visible.height))
        }
        if axes.contains(.horizontal) {
            origin.x = place(target.minX, target.width, origin.x, visible.width, anchor?.x)
            origin.x = min(max(0, origin.x), max(0, doc.width - visible.width))
        }
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

// MARK: ScrollViewReader

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollviewproxy
public struct ScrollViewProxy {
    final class Reader { weak var node: _ViewNode?; var pending: (AnyHashable, UnitPoint?)? }
    let reader: Reader

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollviewproxy/scrollto(_:anchor:)
    ///
    /// Scrolls the scroll view that holds the view with this identity (`.id(_:)` or a
    /// `ForEach` element's id) inside the reader's content. It scrolls at once with the
    /// current layout, and again after the next layout pass, so a call made while a state
    /// change is pending (the row was just inserted) lands where the new layout puts it.
    /// The scroll is not animated.
    @MainActor public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        let key = AnyHashable(id)
        reader.pending = (key, anchor)
        _ = _ScrollViewReaderPrimitive.scroll(in: reader.node, to: key, anchor: anchor)
        reader.node?.setNeedsUpdate()
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollviewreader
public struct ScrollViewReader<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    public var content: (ScrollViewProxy) -> Content
    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) { self.content = content }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _ScrollViewReaderPrimitive(node: node, content: content)
    }
}

/// The reader's node keeps one proxy for its lifetime; the content is built with it.
@MainActor
final class _ScrollViewReaderPrimitive: _Primitive {
    let reader: ScrollViewProxy.Reader
    private let view = _ContainerView(frame: .zero)

    init<Content: View>(node: _ViewNode, content: (ScrollViewProxy) -> Content) {
        // The node's own reader survives updates (the runtime makes a fresh primitive per
        // update and hands it to the attached one).
        let reader = (node.primitive as? _ScrollViewReaderPrimitive)?.reader ?? ScrollViewProxy.Reader()
        self.reader = reader
        super.init()
        children = [_ViewBox(content(ScrollViewProxy(reader: reader)))]
    }
    override var nsView: NSView? { view }
    override func attach(to node: _ViewNode) { super.attach(to: node); reader.node = node }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { node.children.first?.sizeThatFits(proposal) ?? .zero }
    override func place(node: _ViewNode, in rect: CGRect) { node.children.first?.place(in: rect) }
    override func didSyncBackingViews(node: _ViewNode) {
        guard let (id, anchor) = reader.pending else { return }
        reader.pending = nil
        _ = Self.scroll(in: node, to: id, anchor: anchor)
    }

    static func scroll(in node: _ViewNode?, to id: AnyHashable, anchor: UnitPoint?) -> Bool {
        guard let node, let target = node._descendant(withID: id), let scrollNode = target._enclosingScrollNode,
              let scroll = scrollNode.primitive as? _ScrollPrimitive, let frame = target._laidOutFrame else { return false }
        // Content is laid out with the document at the scroll view's origin.
        let rect = frame.offsetBy(dx: -scrollNode.frame.minX, dy: -scrollNode.frame.minY)
        scroll._scroll(toShow: rect, anchor: anchor)
        return true
    }
}

// MARK: defaultScrollAnchor

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollanchorrole
public struct ScrollAnchorRole: Hashable, Sendable {
    let kind: Int
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollanchorrole/initialoffset
    public static var initialOffset: ScrollAnchorRole { ScrollAnchorRole(kind: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollanchorrole/sizechanges
    public static var sizeChanges: ScrollAnchorRole { ScrollAnchorRole(kind: 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollanchorrole/alignment
    public static var alignment: ScrollAnchorRole { ScrollAnchorRole(kind: 2) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:)
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        _ScrollConfigured(content: self, configuration: .anchor(anchor, roles: [.initialOffset, .sizeChanges, .alignment]))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:for:)
    ///
    /// `initialOffset` scrolls a scroll view to the anchor the first time it has content;
    /// `sizeChanges` keeps the anchor's point of the content where it was when the content
    /// grows or shrinks (a bottom anchor follows new rows at the end while the view is at the
    /// bottom). `alignment` (where content smaller than the view sits) is not applied: the
    /// port's scroll views put such content at the top.
    public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View {
        _ScrollConfigured(content: self, configuration: .anchor(anchor, roles: [role]))
    }
}

// MARK: scrollIndicators

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scrollindicatorvisibility
public struct ScrollIndicatorVisibility: Equatable {
    let kind: Int
    public static var automatic: ScrollIndicatorVisibility { ScrollIndicatorVisibility(kind: 0) }
    public static var visible: ScrollIndicatorVisibility { ScrollIndicatorVisibility(kind: 1) }
    public static var hidden: ScrollIndicatorVisibility { ScrollIndicatorVisibility(kind: 2) }
    public static var never: ScrollIndicatorVisibility { ScrollIndicatorVisibility(kind: 3) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/scrollindicators(_:axes:)
    ///
    /// `hidden` and `never` remove the scrollers of the scroll views inside; `visible` and
    /// `automatic` keep them (the port's scrollers already show only while there is
    /// something to scroll).
    public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        _ScrollConfigured(content: self, configuration: .indicators(visibility, axes: axes))
    }
}

// MARK: The configuring wrapper

enum _ScrollConfiguration {
    case anchor(UnitPoint?, roles: [ScrollAnchorRole])
    case indicators(ScrollIndicatorVisibility, axes: Axis.Set)
}

struct _ScrollConfigured<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let configuration: _ScrollConfiguration
    func _makePrimitive(node: _ViewNode) -> _Primitive { _ScrollConfiguredPrimitive(configuration: configuration, content: _ViewBox(content)) }
}

/// Applies its configuration to the scroll views in its content once their AppKit views
/// have their frames for the pass.
@MainActor
final class _ScrollConfiguredPrimitive: _Primitive {
    var configuration: _ScrollConfiguration
    private let view = _ContainerView(frame: .zero)
    /// Per scroll view: the document size last seen (nil until it first had content).
    private var lastDocumentSize: [ObjectIdentifier: CGSize] = [:]

    init(configuration: _ScrollConfiguration, content: _AnyViewBox) {
        self.configuration = configuration
        super.init()
        children = [content]
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _ScrollConfiguredPrimitive { configuration = o.configuration }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { node.children.first?.sizeThatFits(proposal) ?? .zero }
    override func place(node: _ViewNode, in rect: CGRect) { node.children.first?.place(in: rect) }

    override func didSyncBackingViews(node: _ViewNode) {
        for n in node._outermostScrollNodes {
            guard let p = n.primitive as? _ScrollPrimitive else { continue }
            switch configuration {
            case .indicators(let visibility, let axes):
                let show = visibility == .automatic || visibility == .visible
                if axes.contains(.vertical) {
                    let v = show && p.axes.contains(.vertical) && p.showsIndicators
                    if p.scroll.hasVerticalScroller != v { p.scroll.hasVerticalScroller = v }
                }
                if axes.contains(.horizontal) {
                    let h = show && p.axes.contains(.horizontal) && p.showsIndicators
                    if p.scroll.hasHorizontalScroller != h { p.scroll.hasHorizontalScroller = h }
                }
            case .anchor(let anchor, let roles):
                applyAnchor(anchor, roles: roles, to: p)
            }
        }
    }

    private func applyAnchor(_ anchor: UnitPoint?, roles: [ScrollAnchorRole], to p: _ScrollPrimitive) {
        let key = ObjectIdentifier(p)
        let doc = p.document.frame.size
        let visible = p.scroll.contentSize
        guard doc.width > 0 || doc.height > 0, visible.height > 0 || visible.width > 0 else { return }
        defer { lastDocumentSize[key] = doc }
        guard let anchor else { return }
        guard let last = lastDocumentSize[key] else {
            if roles.contains(.initialOffset) {
                p._scroll(toShow: CGRect(x: anchor.x * doc.width, y: anchor.y * doc.height, width: 0, height: 0), anchor: anchor)
            }
            return
        }
        guard roles.contains(.sizeChanges), last != doc else { return }
        // Keep the anchor's point of the content where it is in the view.
        var origin = p.scroll.contentView.bounds.origin
        let wasMaxY = max(0, last.height - visible.height), wasMaxX = max(0, last.width - visible.width)
        // A view scrolled to the anchored end stays at that end.
        if anchor.y >= 1, origin.y >= wasMaxY - 1 { origin.y = max(0, doc.height - visible.height) }
        else { origin.y += anchor.y * (doc.height - last.height) }
        if anchor.x >= 1, origin.x >= wasMaxX - 1 { origin.x = max(0, doc.width - visible.width) }
        else { origin.x += anchor.x * (doc.width - last.width) }
        origin.y = min(max(0, origin.y), max(0, doc.height - visible.height))
        origin.x = min(max(0, origin.x), max(0, doc.width - visible.width))
        p.scroll.contentView.scroll(to: origin)
        p.scroll.reflectScrolledClipView(p.scroll.contentView)
    }
}
