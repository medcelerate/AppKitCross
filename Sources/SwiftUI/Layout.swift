// Layout: proposals, alignment, stacks, spacers, frames, padding.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/proposedviewsize
public struct ProposedViewSize: Equatable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?
    public init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }
    public init(_ size: CGSize) {
        width = size.width
        height = size.height
    }
    public static let zero = ProposedViewSize(width: 0, height: 0)
    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)
    public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
        CGSize(width: width ?? size.width, height: height ?? size.height)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/axis
public enum Axis: Int8, CaseIterable, Hashable, Sendable {
    case horizontal, vertical
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/horizontalalignment
public struct HorizontalAlignment: Equatable, Hashable, Sendable {
    let key: String
    let fraction: CGFloat
    public static let leading = HorizontalAlignment(key: "leading", fraction: 0)
    public static let center = HorizontalAlignment(key: "center", fraction: 0.5)
    public static let trailing = HorizontalAlignment(key: "trailing", fraction: 1)
    /// The fraction from the left edge: leading is on the right in a right-to-left layout.
    func fraction(in direction: LayoutDirection) -> CGFloat { direction == .rightToLeft ? 1 - fraction : fraction }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/verticalalignment
public struct VerticalAlignment: Equatable, Hashable, Sendable {
    let key: String
    let fraction: CGFloat
    public static let top = VerticalAlignment(key: "top", fraction: 0)
    public static let center = VerticalAlignment(key: "center", fraction: 0.5)
    public static let bottom = VerticalAlignment(key: "bottom", fraction: 1)
    public static let firstTextBaseline = VerticalAlignment(key: "firstTextBaseline", fraction: 1)
    public static let lastTextBaseline = VerticalAlignment(key: "lastTextBaseline", fraction: 1)
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/alignment
public struct Alignment: Equatable, Hashable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)

    func origin(of size: CGSize, in rect: CGRect, direction: LayoutDirection = .leftToRight) -> CGPoint {
        CGPoint(x: rect.minX + (rect.width - size.width) * horizontal.fraction(in: direction), y: rect.minY + (rect.height - size.height) * vertical.fraction)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/edge
public enum Edge: Int8, CaseIterable, Hashable, Sendable {
    case top, leading, bottom, trailing
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public init(_ e: Edge) { self.init(rawValue: 1 << e.rawValue) }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/edgeinsets
public struct EdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }
    var horizontal: CGFloat { leading + trailing }
    var vertical: CGFloat { top + bottom }
}

// MARK: Stacks

@MainActor
final class _StackPrimitive: _Primitive {
    enum Kind { case horizontal(VerticalAlignment), vertical(HorizontalAlignment), depth(Alignment) }
    let kind: Kind
    var spacing: CGFloat

    init(kind: Kind, spacing: CGFloat?, content: _AnyViewBox) {
        self.kind = kind
        self.spacing = spacing ?? 8
        super.init()
        children = [content]
    }

    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _StackPrimitive { spacing = o.spacing }
    }

    private func items(_ node: _ViewNode) -> [_ViewNode] {
        let leaves = node.children.flatMap(\.layoutLeaves)
        let axis: Axis? = { switch kind { case .horizontal: return .horizontal; case .vertical: return .vertical; case .depth: return nil } }()
        for l in leaves { l.stackAxis = axis }
        return leaves
    }

    /// Distributes the main-axis length: items grouped by layout priority, least flexible
    /// first within a group, each offered an equal share of what remains.
    private func measure(_ items: [_ViewNode], proposal: ProposedViewSize, horizontal: Bool) -> [CGSize] {
        guard !items.isEmpty else { return [] }
        var sizes = [CGSize](repeating: .zero, count: items.count)
        let mainProposal = horizontal ? proposal.width : proposal.height
        let cross = horizontal ? proposal.height : proposal.width
        func propose(_ main: CGFloat?) -> ProposedViewSize { horizontal ? ProposedViewSize(width: main, height: cross) : ProposedViewSize(width: cross, height: main) }
        func mainOf(_ s: CGSize) -> CGFloat { horizontal ? s.width : s.height }
        guard let total = mainProposal else {
            for (i, item) in items.enumerated() { sizes[i] = item.sizeThatFits(propose(nil)) }
            return sizes
        }
        var remaining = total - spacing * CGFloat(items.count - 1)
        // Flexibility: how much an item can grow between its minimum and its maximum.
        let flex: [CGFloat] = items.map { item in
            let lo = mainOf(item.sizeThatFits(propose(0)))
            let hi = mainOf(item.sizeThatFits(propose(.infinity)))
            return hi - lo
        }
        let priorities = Set(items.map(\.layoutPriority)).sorted(by: >)
        for p in priorities {
            var group = items.indices.filter { items[$0].layoutPriority == p }
            group.sort { flex[$0] < flex[$1] }
            var left = group.count
            for i in group {
                let share = max(0, remaining / CGFloat(left))
                let s = items[i].sizeThatFits(propose(share))
                sizes[i] = s
                remaining -= mainOf(s)
                left -= 1
            }
        }
        return sizes
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let items = items(node)
        switch kind {
        case .depth:
            var size = CGSize.zero
            for i in items {
                let s = i.sizeThatFits(proposal)
                size.width = max(size.width, s.width); size.height = max(size.height, s.height)
            }
            return size
        case .horizontal:
            let sizes = measure(items, proposal: proposal, horizontal: true)
            let w = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
            return CGSize(width: w, height: sizes.map(\.height).max() ?? 0)
        case .vertical:
            let sizes = measure(items, proposal: proposal, horizontal: false)
            let h = sizes.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, sizes.count - 1))
            return CGSize(width: sizes.map(\.width).max() ?? 0, height: h)
        }
    }

    override func place(node: _ViewNode, in rect: CGRect) {
        let items = items(node)
        let direction = node.environment.layoutDirection
        switch kind {
        case .depth(let alignment):
            for i in items {
                let s = i.sizeThatFits(ProposedViewSize(rect.size))
                i.place(in: CGRect(origin: alignment.origin(of: s, in: rect, direction: direction), size: s).integralIfNeeded)
            }
        case .horizontal(let v):
            let sizes = measure(items, proposal: ProposedViewSize(rect.size), horizontal: true)
            let total = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
            // Right to left: the first item sits at the right edge and the row grows leftwards.
            let rightToLeft = direction == .rightToLeft
            let leftover = rect.width.isFinite ? max(0, (rect.width - total) / 2) : 0
            var x = rightToLeft ? (rect.width.isFinite ? rect.maxX - leftover : rect.minX + total) : rect.minX + leftover
            for (i, item) in items.enumerated() {
                let s = sizes[i]
                let y = rect.minY + (rect.height - s.height) * v.fraction
                if rightToLeft {
                    x -= s.width
                    item.place(in: CGRect(x: x, y: y, width: s.width, height: s.height).integralIfNeeded)
                    x -= spacing
                } else {
                    item.place(in: CGRect(x: x, y: y, width: s.width, height: s.height).integralIfNeeded)
                    x += s.width + spacing
                }
            }
        case .vertical(let h):
            let sizes = measure(items, proposal: ProposedViewSize(rect.size), horizontal: false)
            let total = sizes.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, sizes.count - 1))
            var y = rect.minY + max(0, (rect.height - total) / 2)
            for (i, item) in items.enumerated() {
                let s = sizes[i]
                let x = rect.minX + (rect.width - s.width) * h.fraction(in: direction)
                item.place(in: CGRect(x: x, y: y, width: s.width, height: s.height).integralIfNeeded)
                y += s.height + spacing
            }
        }
        for c in node.children where !items.contains(where: { $0 === c }) { c.frame = rect }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/hstack
public struct HStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _StackPrimitive(kind: .horizontal(alignment), spacing: spacing, content: _ViewBox(content)) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/vstack
public struct VStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _StackPrimitive(kind: .vertical(alignment), spacing: spacing, content: _ViewBox(content)) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/zstack
public struct ZStack<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: Alignment
    let content: Content
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _StackPrimitive(kind: .depth(alignment), spacing: 0, content: _ViewBox(content)) }
}

// MARK: Spacer and Divider

@MainActor
final class _SpacerPrimitive: _Primitive {
    var minLength: CGFloat
    init(minLength: CGFloat) { self.minLength = minLength }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _SpacerPrimitive { minLength = o.minLength } }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        // An infinite proposal is the stack probing flexibility: a spacer is infinitely flexible.
        func along(_ p: CGFloat?) -> CGFloat { guard let p else { return minLength }; return p.isFinite ? max(minLength, p) : .infinity }
        switch node.stackAxis {
        case .horizontal: return CGSize(width: along(proposal.width), height: 0)
        case .vertical: return CGSize(width: 0, height: along(proposal.height))
        case nil: return CGSize(width: along(proposal.width), height: along(proposal.height))
        }
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/spacer
public struct Spacer: View, _PrimitiveView {
    public typealias Body = Never
    public var minLength: CGFloat?
    public init(minLength: CGFloat? = nil) { self.minLength = minLength }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _SpacerPrimitive(minLength: minLength ?? 0) }
}

// MARK: Frame, padding, fixed size, priority

@MainActor
final class _FramePrimitive: _Primitive {
    var width: CGFloat?, height: CGFloat?
    var minWidth: CGFloat?, idealWidth: CGFloat?, maxWidth: CGFloat?
    var minHeight: CGFloat?, idealHeight: CGFloat?, maxHeight: CGFloat?
    var alignment: Alignment
    var flexible: Bool

    init(width: CGFloat?, height: CGFloat?, alignment: Alignment, content: _AnyViewBox) {
        self.width = width; self.height = height; self.alignment = alignment; flexible = false
        super.init()
        children = [content]
    }
    init(minWidth: CGFloat?, idealWidth: CGFloat?, maxWidth: CGFloat?, minHeight: CGFloat?, idealHeight: CGFloat?, maxHeight: CGFloat?, alignment: Alignment, content: _AnyViewBox) {
        self.minWidth = minWidth; self.idealWidth = idealWidth; self.maxWidth = maxWidth
        self.minHeight = minHeight; self.idealHeight = idealHeight; self.maxHeight = maxHeight
        self.alignment = alignment; flexible = true
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _FramePrimitive else { return }
        width = o.width; height = o.height; minWidth = o.minWidth; idealWidth = o.idealWidth; maxWidth = o.maxWidth
        minHeight = o.minHeight; idealHeight = o.idealHeight; maxHeight = o.maxHeight; alignment = o.alignment; flexible = o.flexible
    }

    private func resolve(_ proposal: ProposedViewSize, node: _ViewNode) -> (CGSize, CGSize) {
        let content = node.children.first
        if !flexible {
            let childProposal = ProposedViewSize(width: width ?? proposal.width, height: height ?? proposal.height)
            let child = content?.sizeThatFits(childProposal) ?? .zero
            return (CGSize(width: width ?? child.width, height: height ?? child.height), child)
        }
        func clamp(_ v: CGFloat, _ lo: CGFloat?, _ hi: CGFloat?) -> CGFloat { min(max(v, lo ?? -.infinity), hi ?? .infinity) }
        // The proposal, clamped into the frame's bounds, goes to the content.
        var pw = proposal.width, ph = proposal.height
        if pw == nil, let i = idealWidth { pw = i }
        if ph == nil, let i = idealHeight { ph = i }
        let childProposal = ProposedViewSize(width: pw.map { clamp($0, minWidth, maxWidth) }, height: ph.map { clamp($0, minHeight, maxHeight) })
        let child = content?.sizeThatFits(childProposal) ?? .zero
        var w = child.width, h = child.height
        if minWidth != nil || maxWidth != nil {
            let target = pw ?? child.width
            w = clamp(target.isFinite ? target : child.width, minWidth, maxWidth)
            if maxWidth == .infinity, pw == nil { w = max(child.width, minWidth ?? 0) }
            if maxWidth == .infinity, let p = pw, p.isFinite { w = max(p, minWidth ?? 0) }
            if let mw = maxWidth, mw.isFinite, w > mw { w = mw }
            if w < child.width, maxWidth == nil { w = child.width }
        }
        if minHeight != nil || maxHeight != nil {
            let target = ph ?? child.height
            h = clamp(target.isFinite ? target : child.height, minHeight, maxHeight)
            if maxHeight == .infinity, ph == nil { h = max(child.height, minHeight ?? 0) }
            if maxHeight == .infinity, let p = ph, p.isFinite { h = max(p, minHeight ?? 0) }
            if let mh = maxHeight, mh.isFinite, h > mh { h = mh }
            if h < child.height, maxHeight == nil { h = child.height }
        }
        if idealWidth != nil, proposal.width == nil, minWidth == nil, maxWidth == nil { w = idealWidth! }
        if idealHeight != nil, proposal.height == nil, minHeight == nil, maxHeight == nil { h = idealHeight! }
        return (CGSize(width: w, height: h), child)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { resolve(proposal, node: node).0 }

    override func place(node: _ViewNode, in rect: CGRect) {
        let (_, child) = resolve(ProposedViewSize(rect.size), node: node)
        let s = CGSize(width: min(child.width, rect.width.isFinite ? max(rect.width, child.width) : child.width), height: child.height)
        node.children.first?.place(in: CGRect(origin: alignment.origin(of: s, in: rect, direction: node.environment.layoutDirection), size: s).integralIfNeeded)
    }
}

@MainActor
final class _PaddingPrimitive: _Primitive {
    var insets: EdgeInsets
    init(insets: EdgeInsets, content: _AnyViewBox) {
        self.insets = insets
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _PaddingPrimitive { insets = o.insets } }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let p = ProposedViewSize(width: proposal.width.map { max(0, $0 - insets.horizontal) }, height: proposal.height.map { max(0, $0 - insets.vertical) })
        let c = node.children.first?.sizeThatFits(p) ?? .zero
        return CGSize(width: c.width + insets.horizontal, height: c.height + insets.vertical)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        // The leading inset is on the right in a right-to-left layout.
        let left = node.environment.layoutDirection == .rightToLeft ? insets.trailing : insets.leading
        node.children.first?.place(in: CGRect(x: rect.minX + left, y: rect.minY + insets.top, width: max(0, rect.width - insets.horizontal), height: max(0, rect.height - insets.vertical)))
    }
}

@MainActor
final class _FixedSizePrimitive: _Primitive {
    var horizontal: Bool, vertical: Bool
    init(horizontal: Bool, vertical: Bool, content: _AnyViewBox) {
        self.horizontal = horizontal; self.vertical = vertical
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _FixedSizePrimitive { horizontal = o.horizontal; vertical = o.vertical } }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        node.children.first?.sizeThatFits(ProposedViewSize(width: horizontal ? nil : proposal.width, height: vertical ? nil : proposal.height)) ?? .zero
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        let s = sizeThatFits(ProposedViewSize(rect.size), node: node)
        node.children.first?.place(in: CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height).integralIfNeeded)
    }
}

@MainActor
final class _LayoutPriorityPrimitive: _Primitive {
    var priority: Double
    init(priority: Double, content: _AnyViewBox) {
        self.priority = priority
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _LayoutPriorityPrimitive { priority = o.priority } }
    override func attach(to node: _ViewNode) { super.attach(to: node); node.layoutPriority = priority }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        node.layoutPriority = priority
        return node.children.first?.sizeThatFits(proposal) ?? .zero
    }
    override func place(node: _ViewNode, in rect: CGRect) { node.children.first?.place(in: rect) }
}

/// A primitive with one content child and a parameter, used by the layout modifiers.
struct _LayoutModified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let make: @MainActor (_AnyViewBox) -> _Primitive
    func _makePrimitive(node: _ViewNode) -> _Primitive { make(_ViewBox(content)) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/frame(width:height:alignment:)
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        _LayoutModified(content: self) { _FramePrimitive(width: width, height: height, alignment: alignment, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:)
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        _LayoutModified(content: self) { _FramePrimitive(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth, minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight, alignment: alignment, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/padding(_:_:)
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let l = length ?? 16
        let insets = EdgeInsets(top: edges.contains(.top) ? l : 0, leading: edges.contains(.leading) ? l : 0, bottom: edges.contains(.bottom) ? l : 0, trailing: edges.contains(.trailing) ? l : 0)
        return _LayoutModified(content: self) { _PaddingPrimitive(insets: insets, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/padding(_:)-6pgqq
    public func padding(_ length: CGFloat) -> some View { padding(.all, length) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/padding(_:)-9f33x
    public func padding(_ insets: EdgeInsets) -> some View { _LayoutModified(content: self) { _PaddingPrimitive(insets: insets, content: $0) } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fixedsize(horizontal:vertical:)
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        _LayoutModified(content: self) { _FixedSizePrimitive(horizontal: horizontal, vertical: vertical, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fixedsize()
    public func fixedSize() -> some View { fixedSize(horizontal: true, vertical: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/layoutpriority(_:)
    public func layoutPriority(_ value: Double) -> some View {
        _LayoutModified(content: self) { _LayoutPriorityPrimitive(priority: value, content: $0) }
    }
}
