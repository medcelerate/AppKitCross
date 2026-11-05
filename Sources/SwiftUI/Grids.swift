// Lazy grids: GridItem tracks laid out across the available width (LazyVGrid) or height
// (LazyHGrid). Nothing is lazy about them yet: every item is measured and placed.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/griditem
public struct GridItem: Sendable {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/griditem/size-swift.enum
    public enum Size: Sendable {
        case fixed(CGFloat)
        case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
        case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity)
    }
    public var size: Size
    public var spacing: CGFloat?
    public var alignment: Alignment?
    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {
        self.size = size; self.spacing = spacing; self.alignment = alignment
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/pinnedscrollableviews
public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/lazyvgrid
public struct LazyVGrid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let columns: [GridItem]
    let alignment: HorizontalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.columns = columns; self.alignment = alignment; self.spacing = spacing; self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _GridPrimitive(axis: .vertical, tracks: columns, alignment: Alignment(horizontal: alignment, vertical: .center), spacing: spacing, content: _ViewBox(content))
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/lazyhgrid
public struct LazyHGrid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let rows: [GridItem]
    let alignment: VerticalAlignment
    let spacing: CGFloat?
    let content: Content
    public init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {
        self.rows = rows; self.alignment = alignment; self.spacing = spacing; self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _GridPrimitive(axis: .horizontal, tracks: rows, alignment: Alignment(horizontal: .center, vertical: alignment), spacing: spacing, content: _ViewBox(content))
    }
}

/// Tracks run across the grid's axis (columns of a vertical grid); items fill them in
/// order and wrap into lines along the axis.
@MainActor
final class _GridPrimitive: _Primitive {
    let axis: Axis
    var tracks: [GridItem]
    var alignment: Alignment
    var spacing: CGFloat?

    init(axis: Axis, tracks: [GridItem], alignment: Alignment, spacing: CGFloat?, content: _AnyViewBox) {
        self.axis = axis; self.tracks = tracks; self.alignment = alignment; self.spacing = spacing
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _GridPrimitive else { return }
        tracks = o.tracks; alignment = o.alignment; spacing = o.spacing
    }

    /// The track lengths across the axis for an available length, with the gap after
    /// each (an adaptive item becomes as many tracks of its minimum as fit).
    func resolveTracks(available: CGFloat?) -> (lengths: [CGFloat], gaps: [CGFloat], items: [GridItem]) {
        var expanded: [GridItem] = []
        if let available {
            var fixedTotal: CGFloat = 0, gapTotal: CGFloat = 0, count = 0
            for t in tracks {
                if case .adaptive = t.size { continue }
                if case .fixed(let f) = t.size { fixedTotal += f } else if case .flexible(let lo, _) = t.size { fixedTotal += lo }
                gapTotal += t.spacing ?? 8; count += 1
            }
            for t in tracks {
                if case .adaptive(let lo, _) = t.size {
                    let gap = t.spacing ?? 8
                    let rest = available - fixedTotal - gapTotal
                    let n = max(1, Int(((rest + gap) / (lo + gap)).rounded(.down)))
                    expanded += Array(repeating: t, count: n)
                } else {
                    expanded.append(t)
                }
            }
        } else {
            expanded = tracks
        }
        let gaps = expanded.indices.map { i in i == expanded.count - 1 ? 0 : (expanded[i].spacing ?? 8) }
        var lengths = expanded.map { t -> CGFloat in
            switch t.size {
            case .fixed(let f): return f
            case .flexible(let lo, _), .adaptive(let lo, _): return lo
            }
        }
        if let available {
            let flexible = expanded.indices.filter { if case .fixed = expanded[$0].size { return false }; return true }
            var remaining = available - gaps.reduce(0, +) - expanded.indices.filter { !flexible.contains($0) }.reduce(0) { $0 + lengths[$1] }
            var open = flexible
            // Equal shares, clamped to each track's bounds; tracks that hit a bound leave
            // the rest to the others.
            while !open.isEmpty {
                let share = remaining / CGFloat(open.count)
                var settled: [Int] = []
                for i in open {
                    var lo: CGFloat = 10, hi: CGFloat = .infinity
                    if case .flexible(let l, let h) = expanded[i].size { lo = l; hi = h } else if case .adaptive(let l, let h) = expanded[i].size { lo = l; hi = h }
                    if share < lo { lengths[i] = lo; settled.append(i) } else if share > hi { lengths[i] = hi; settled.append(i) }
                }
                if settled.isEmpty { for i in open { lengths[i] = max(0, share) }; break }
                for i in settled { remaining -= lengths[i] }
                open.removeAll { settled.contains($0) }
            }
        }
        return (lengths, gaps, expanded)
    }

    private struct Layout { var cells: [CGRect]; var size: CGSize }

    private func layout(_ node: _ViewNode, proposal: ProposedViewSize) -> Layout {
        let items = node.children.flatMap(\.layoutLeaves)
        let across = axis == .vertical ? proposal.width : proposal.height
        let (lengths, gaps, trackItems) = resolveTracks(available: across.flatMap { $0.isFinite ? $0 : nil })
        let n = max(1, lengths.count)
        let lineGap = spacing ?? 8
        var cells: [CGRect] = []
        var along: CGFloat = 0
        var line: [(index: Int, size: CGSize)] = []
        func flushLine() {
            guard !line.isEmpty else { return }
            let lineLength = line.map { axis == .vertical ? $0.size.height : $0.size.width }.max() ?? 0
            var offset: CGFloat = 0
            for (k, entry) in line.enumerated() {
                let trackLength = lengths[k]
                let a = trackItems[k].alignment ?? alignment
                let cell: CGRect
                if axis == .vertical {
                    let s = CGSize(width: min(entry.size.width, trackLength), height: min(entry.size.height, lineLength))
                    cell = CGRect(origin: a.origin(of: s, in: CGRect(x: offset, y: along, width: trackLength, height: lineLength)), size: s)
                } else {
                    let s = CGSize(width: min(entry.size.width, lineLength), height: min(entry.size.height, trackLength))
                    cell = CGRect(origin: a.origin(of: s, in: CGRect(x: along, y: offset, width: lineLength, height: trackLength)), size: s)
                }
                cells.append(cell)
                offset += trackLength + gaps[k]
            }
            along += lineLength + lineGap
            line = []
        }
        for (i, item) in items.enumerated() {
            let k = i % n
            let trackLength = lengths[k]
            let s = item.sizeThatFits(axis == .vertical ? ProposedViewSize(width: trackLength, height: nil) : ProposedViewSize(width: nil, height: trackLength))
            line.append((i, s))
            if k == n - 1 { flushLine() }
        }
        flushLine()
        let acrossTotal = lengths.reduce(0, +) + gaps.reduce(0, +)
        let alongTotal = max(0, along - lineGap)
        return Layout(cells: cells, size: axis == .vertical ? CGSize(width: acrossTotal, height: alongTotal) : CGSize(width: alongTotal, height: acrossTotal))
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { layout(node, proposal: proposal).size }

    override func place(node: _ViewNode, in rect: CGRect) {
        let items = node.children.flatMap(\.layoutLeaves)
        let l = layout(node, proposal: ProposedViewSize(rect.size))
        for (i, item) in items.enumerated() where i < l.cells.count {
            item.place(in: l.cells[i].offsetBy(dx: rect.minX, dy: rect.minY).integralIfNeeded)
        }
        for c in node.children where !items.contains(where: { $0 === c }) { c.frame = rect }
    }
}
