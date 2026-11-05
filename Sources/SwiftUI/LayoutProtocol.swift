// The Layout protocol (custom layouts over subview proxies) and Grid/GridRow, found
// missing by swift-markdown-ui (its FlowLayout and table view).

import Foundation

// MARK: Layout

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/layout
public protocol Layout {
    associatedtype Cache = Void
    typealias Subviews = LayoutSubviews
    static var layoutProperties: LayoutProperties { get }
    func makeCache(subviews: Subviews) -> Cache
    func updateCache(_ cache: inout Cache, subviews: Subviews)
    func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat?
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat?
}

extension Layout {
    public static var layoutProperties: LayoutProperties { LayoutProperties() }
    public func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = makeCache(subviews: subviews) }
    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing { ViewSpacing() }
    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/layout/callasfunction(_:)
    @MainActor public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        _LayoutView(layout: self, content: content())
    }
}

extension Layout where Cache == Void {
    public func makeCache(subviews: Subviews) -> Cache { () }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/layoutproperties
public struct LayoutProperties: Sendable {
    public var stackOrientation: Axis?
    public init() { stackOrientation = nil }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/viewspacing
public struct ViewSpacing: Sendable {
    var preferred: CGFloat
    public init() { preferred = 8 }
    public static let zero: ViewSpacing = { var s = ViewSpacing(); s.preferred = 0; return s }()
    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat { max(preferred, next.preferred) }
    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) { preferred = max(preferred, other.preferred) }
    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing { var s = self; s.formUnion(other, edges: edges); return s }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/layoutvaluekey
public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/layoutsubview
/// A proxy for one of the layout's subviews (its node); placing it lays the node out.
public struct LayoutSubview {
    let node: _ViewNode
    let placed: _PlacedFlag
    @MainActor final class _PlacedFlag { var placed = false }

    public var priority: Double { MainActor.assumeIsolated { node.layoutPriority } }
    public var spacing: ViewSpacing { ViewSpacing() }
    public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
        MainActor.assumeIsolated { node.layoutValues[ObjectIdentifier(K.self)] as? K.Value ?? K.defaultValue }
    }
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { MainActor.assumeIsolated { node.sizeThatFits(proposal) } }
    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        MainActor.assumeIsolated { node.dimensions(for: node.sizeThatFits(proposal)) }
    }
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        MainActor.assumeIsolated {
            let s = node.sizeThatFits(proposal)
            node.place(in: CGRect(x: position.x - s.width * anchor.x, y: position.y - s.height * anchor.y, width: s.width, height: s.height).integralIfNeeded)
            placed.placed = true
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/layoutsubviews
public struct LayoutSubviews: RandomAccessCollection, Equatable {
    let subviews: [LayoutSubview]
    public var layoutDirection: LayoutDirection = .leftToRight
    public var startIndex: Int { 0 }
    public var endIndex: Int { subviews.count }
    public subscript(index: Int) -> LayoutSubview { subviews[index] }
    public subscript(bounds: Range<Int>) -> LayoutSubviews { LayoutSubviews(subviews: Array(subviews[bounds]), layoutDirection: layoutDirection) }
    public static func == (a: LayoutSubviews, b: LayoutSubviews) -> Bool { a.subviews.map { ObjectIdentifier($0.node) } == b.subviews.map { ObjectIdentifier($0.node) } }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/layoutvalue(key:value:)
    public func layoutValue<K: LayoutValueKey>(key: K.Type, value: K.Value) -> some View {
        _LayoutModified(content: self) { _LayoutValuePrimitive(key: ObjectIdentifier(K.self), value: value, content: $0) }
    }
}

@MainActor
final class _LayoutValuePrimitive: _Primitive {
    let key: ObjectIdentifier
    var value: Any
    init(key: ObjectIdentifier, value: Any, content: _AnyViewBox) {
        self.key = key; self.value = value
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _LayoutValuePrimitive { value = o.value }; node?.layoutValues[key] = value }
    override func attach(to node: _ViewNode) { super.attach(to: node); node.layoutValues[key] = value }
}

struct _LayoutView<L: Layout, Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let layout: L
    let content: Content
    func _makePrimitive(node: _ViewNode) -> _Primitive { _LayoutPrimitive(layout: layout, content: _ViewBox(content)) }
}

/// Runs a `Layout` over the content's layout leaves.
@MainActor
final class _LayoutPrimitive<L: Layout>: _Primitive {
    var layout: L
    init(layout: L, content: _AnyViewBox) {
        self.layout = layout
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _LayoutPrimitive<L> { layout = o.layout } }
    private func subviews(_ node: _ViewNode) -> LayoutSubviews {
        let leaves = node.children.flatMap(\.layoutLeaves)
        for l in leaves { l.stackAxis = nil }
        return LayoutSubviews(subviews: leaves.map { LayoutSubview(node: $0, placed: LayoutSubview._PlacedFlag()) }, layoutDirection: node.environment.layoutDirection)
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let subviews = subviews(node)
        var cache = layout.makeCache(subviews: subviews)
        return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        let subviews = subviews(node)
        var cache = layout.makeCache(subviews: subviews)
        layout.placeSubviews(in: rect, proposal: ProposedViewSize(rect.size), subviews: subviews, cache: &cache)
        // Subviews the layout did not place go to the centre, as in SwiftUI.
        for s in subviews where !s.placed.placed {
            s.place(at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center, proposal: ProposedViewSize(rect.size))
        }
        let leaves = subviews.map(\.node)
        for c in node.children where !leaves.contains(where: { $0 === c }) { c.frame = rect }
    }
}

// MARK: Grid

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/grid
public struct Grid<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: Alignment
    let horizontalSpacing: CGFloat?
    let verticalSpacing: CGFloat?
    let content: Content
    public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment; self.horizontalSpacing = horizontalSpacing; self.verticalSpacing = verticalSpacing; self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _GridTablePrimitive(alignment: alignment, horizontalSpacing: horizontalSpacing ?? 8, verticalSpacing: verticalSpacing ?? 8, content: _ViewBox(content))
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/gridrow
public struct GridRow<Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let alignment: VerticalAlignment?
    let content: Content
    public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) { self.alignment = alignment; self.content = content() }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _GridRowPrimitive(alignment: alignment, content: _ViewBox(content)) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/gridcolumnalignment(_:)
    public func gridColumnAlignment(_ guide: HorizontalAlignment) -> some View {
        _LayoutModified(content: self) { _GridCellPrimitive(columnAlignment: guide, columns: nil, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/gridcellcolumns(_:)
    public func gridCellColumns(_ count: Int) -> some View {
        _LayoutModified(content: self) { _GridCellPrimitive(columnAlignment: nil, columns: count, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/gridcellanchor(_:)
    public func gridCellAnchor(_ anchor: UnitPoint) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/gridcellunsizedaxes(_:)
    public func gridCellUnsizedAxes(_ axes: Axis.Set) -> some View { self }
}

/// A row of cells; outside a `Grid` it lays its cells out like an `HStack`.
@MainActor
final class _GridRowPrimitive: _Primitive {
    var alignment: VerticalAlignment?
    init(alignment: VerticalAlignment?, content: _AnyViewBox) {
        self.alignment = alignment
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) { super.update(from: other); if let o = other as? _GridRowPrimitive { alignment = o.alignment } }
    var cells: [_ViewNode] { node?.children.flatMap(\.layoutLeaves) ?? [] }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let sizes = cells.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)) }
        return CGSize(width: sizes.reduce(0) { $0 + $1.width } + 8 * CGFloat(max(0, sizes.count - 1)), height: sizes.map(\.height).max() ?? 0)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        var x = rect.minX
        for c in cells {
            let s = c.sizeThatFits(ProposedViewSize(width: nil, height: rect.height))
            c.place(in: CGRect(x: x, y: rect.midY - s.height / 2, width: s.width, height: s.height).integralIfNeeded)
            x += s.width + 8
        }
    }
}

/// `.gridColumnAlignment` / `.gridCellColumns`: traits the grid reads off its cells.
@MainActor
final class _GridCellPrimitive: _Primitive {
    var columnAlignment: HorizontalAlignment?
    var columns: Int?
    init(columnAlignment: HorizontalAlignment?, columns: Int?, content: _AnyViewBox) {
        self.columnAlignment = columnAlignment; self.columns = columns
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _GridCellPrimitive { columnAlignment = o.columnAlignment; columns = o.columns }
        apply()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    private func apply() { node?.gridColumnAlignment = columnAlignment; node?.gridCellColumns = columns }
}

/// Columns sized by their widest cell, rows by their tallest; a child that is not a
/// `GridRow` spans every column.
@MainActor
final class _GridTablePrimitive: _Primitive {
    var alignment: Alignment
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat
    init(alignment: Alignment, horizontalSpacing: CGFloat, verticalSpacing: CGFloat, content: _AnyViewBox) {
        self.alignment = alignment; self.horizontalSpacing = horizontalSpacing; self.verticalSpacing = verticalSpacing
        super.init()
        children = [content]
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _GridTablePrimitive else { return }
        alignment = o.alignment; horizontalSpacing = o.horizontalSpacing; verticalSpacing = o.verticalSpacing
    }

    private struct Cell { let node: _ViewNode; let column: Int; let span: Int }
    private struct Row { let node: _ViewNode?; let cells: [Cell]; let alignment: VerticalAlignment? }
    private struct Table { var rows: [Row]; var columnWidths: [CGFloat]; var rowHeights: [CGFloat]; var size: CGSize }

    private func rows(_ node: _ViewNode) -> [Row] {
        node.children.flatMap(\.layoutLeaves).map { leaf -> Row in
            if let row = leaf.primitive as? _GridRowPrimitive {
                var column = 0
                let cells = row.cells.map { c -> Cell in
                    let span = max(1, c.trait(\.gridCellColumns, upTo: leaf) ?? 1)
                    defer { column += span }
                    return Cell(node: c, column: column, span: span)
                }
                return Row(node: leaf, cells: cells, alignment: row.alignment)
            }
            return Row(node: nil, cells: [Cell(node: leaf, column: 0, span: Int.max)], alignment: nil)
        }
    }

    private func layout(_ node: _ViewNode, proposal: ProposedViewSize) -> Table {
        let rows = rows(node)
        let columns = max(1, rows.map { $0.cells.reduce(0) { $0 + ($1.span == Int.max ? 1 : $1.span) } }.max() ?? 1)
        // Ideal widths from the single-column cells, then the columns a flexible cell can
        // grow share any extra width.
        var widths = [CGFloat](repeating: 0, count: columns)
        var flexible = [Bool](repeating: false, count: columns)
        for row in rows {
            for cell in row.cells where cell.span == 1 {
                let ideal = cell.node.sizeThatFits(.unspecified)
                widths[cell.column] = max(widths[cell.column], ideal.width)
                if cell.node.sizeThatFits(ProposedViewSize(width: ideal.width + 1000, height: nil)).width > ideal.width + 1 { flexible[cell.column] = true }
            }
        }
        let gaps = horizontalSpacing * CGFloat(columns - 1)
        if let w = proposal.width, w.isFinite {
            let available = w - gaps
            let total = widths.reduce(0, +)
            if total > available, total > 0 {
                widths = widths.map { $0 * available / total }
            } else if total < available, flexible.contains(true) {
                let extra = (available - total) / CGFloat(flexible.filter { $0 }.count)
                for i in widths.indices where flexible[i] { widths[i] += extra }
            }
        }
        func cellWidth(_ cell: Cell) -> CGFloat {
            if cell.span == Int.max { return widths.reduce(0, +) + gaps }
            let end = min(columns, cell.column + cell.span)
            return (cell.column..<end).reduce(0) { $0 + widths[$1] } + horizontalSpacing * CGFloat(max(0, end - cell.column - 1))
        }
        let heights = rows.map { row in row.cells.map { $0.node.sizeThatFits(ProposedViewSize(width: cellWidth($0), height: nil)).height }.max() ?? 0 }
        let size = CGSize(width: widths.reduce(0, +) + gaps, height: heights.reduce(0, +) + verticalSpacing * CGFloat(max(0, rows.count - 1)))
        return Table(rows: rows, columnWidths: widths, rowHeights: heights, size: size)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { layout(node, proposal: proposal).size }

    override func place(node: _ViewNode, in rect: CGRect) {
        let t = layout(node, proposal: ProposedViewSize(rect.size))
        var y = rect.minY
        for (r, row) in t.rows.enumerated() {
            let h = t.rowHeights[r]
            row.node?.frame = CGRect(x: rect.minX, y: y, width: t.size.width, height: h)
            for cell in row.cells {
                let x = rect.minX + (0..<min(cell.column, t.columnWidths.count)).reduce(0) { $0 + t.columnWidths[$1] + horizontalSpacing }
                let w: CGFloat
                if cell.span == Int.max { w = t.size.width } else {
                    let end = min(t.columnWidths.count, cell.column + cell.span)
                    w = (cell.column..<end).reduce(0) { $0 + t.columnWidths[$1] } + horizontalSpacing * CGFloat(max(0, end - cell.column - 1))
                }
                let s = cell.node.sizeThatFits(ProposedViewSize(width: w, height: h))
                let a = Alignment(horizontal: cell.node.trait(\.gridColumnAlignment, upTo: row.node) ?? alignment.horizontal, vertical: row.alignment ?? alignment.vertical)
                cell.node.place(in: CGRect(origin: a.origin(of: CGSize(width: min(s.width, w), height: min(s.height, h)), in: CGRect(x: x, y: y, width: w, height: h)), size: CGSize(width: min(s.width, w), height: min(s.height, h))).integralIfNeeded)
            }
            y += h + verticalSpacing
        }
        let leaves = t.rows.flatMap { $0.node.map { [$0] } ?? $0.cells.map(\.node) }
        for c in node.children where !leaves.contains(where: { $0 === c }) { c.frame = rect }
    }
}
