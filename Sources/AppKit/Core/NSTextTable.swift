// NSTextTable (hand-written; seeded from the generated stub, see tools/apigen)
//
// A table is a text block whose cells are NSTextTableBlocks: each cell is a run of
// paragraphs whose last text block is the cell, in row-major order. The layout manager
// asks the table for column geometry (`_layoutColumns`) once per table, then lays each
// row's cells side by side; the row is as tall as its tallest cell (ADR-0030).
// Column widths: a span-1 cell with a content width fixes its column; the fixed algorithm
// shares the rest equally, the automatic one in proportion to the cells' natural widths
// (and no wider than they need when the table has no width of its own).
// `collapsesBorders` is stored but adjacent borders are drawn side by side.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable
open class NSTextTable: NSTextBlock {
    private var _numberOfColumns = 0
    private var _layoutAlgorithm: NSTextTable.LayoutAlgorithm = .automaticLayoutAlgorithm
    private var _collapsesBorders = false
    private var _hidesEmptyCells = false
    /// Column origins and widths, relative to the table's content rect.
    internal var _columnX: [CGFloat] = []
    internal var _columnWidth: [CGFloat] = []
    /// The table's content rect from the last layout (container coordinates).
    internal var _contentRect: NSRect = .zero

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable/collapsesborders
    open var collapsesBorders: Bool {
        get { _collapsesBorders }
        set { _collapsesBorders = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable/hidesemptycells
    open var hidesEmptyCells: Bool {
        get { _hidesEmptyCells }
        set { _hidesEmptyCells = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable/layoutalgorithm
    open var layoutAlgorithm: NSTextTable.LayoutAlgorithm {
        get { _layoutAlgorithm }
        set { _layoutAlgorithm = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable/numberofcolumns
    open var numberOfColumns: Int {
        get { _numberOfColumns }
        set { _numberOfColumns = max(0, newValue) }
    }

    /// The content rect of a cell: its columns' span inside the cell's own insets.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable/rect(for:layoutat:in:textcontainer:characterrange:)
    open func rect(for block: NSTextTableBlock, layoutAt startingPoint: NSPoint, in rect: NSRect, textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        if _columnWidth.count != max(1, _numberOfColumns) { _layoutColumns(in: rect, natural: [:]) }
        let span = _span(of: block)
        let basis = _contentRect.width
        let left = block._inset(.minX, basis: basis), right = block._inset(.maxX, basis: basis), top = block._inset(.minY, basis: basis)
        return NSRect(x: _contentRect.minX + span.x + left, y: startingPoint.y + top, width: max(1, span.width - left - right),
                      height: max(0, rect.maxY - startingPoint.y - top))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable/boundsrect(for:contentrect:in:textcontainer:characterrange:)
    open func boundsRect(for block: NSTextTableBlock, contentRect: NSRect, in rect: NSRect, textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        var r = block._boundsRect(forContent: contentRect, in: NSRect(x: 0, y: 0, width: _contentRect.width, height: 0))
        // The cell box spans its columns exactly, whatever its content needed.
        let span = _span(of: block)
        r.origin.x = _contentRect.minX + span.x
        r.size.width = span.width
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttable/drawbackground(for:withframe:in:characterrange:layoutmanager:)
    open func drawBackground(for block: NSTextTableBlock, withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        if _hidesEmptyCells, let s = layoutManager.textStorage, charRange.length <= 1,
           charRange.length == 0 || (s.string as NSString).character(at: charRange.location) == 0x0A { return }
        block._drawBackground(frame: frameRect, relativeTo: _contentRect.width)
    }

    // MARK: Column layout

    /// x and width of the columns a cell spans.
    internal func _span(of block: NSTextTableBlock) -> (x: CGFloat, width: CGFloat) {
        guard !_columnWidth.isEmpty else { return (0, _contentRect.width) }
        let lo = min(max(0, block.startingColumn), _columnWidth.count - 1)
        let hi = min(_columnWidth.count, lo + max(1, block.columnSpan))
        return (_columnX[lo], _columnWidth[lo..<hi].reduce(0, +))
    }

    /// Lays the columns out in the table's rect inside `rect` (the container's or the
    /// enclosing block's content rect). `natural` maps cells to the width their content
    /// wants on one line (cell insets included).
    internal func _layoutColumns(in rect: NSRect, natural: [ObjectIdentifier: (block: NSTextTableBlock, width: CGFloat)]) {
        let n = max(1, _numberOfColumns)
        let tableRect = _layoutRect(at: rect.origin, in: rect)
        let available = tableRect.width
        let basis = available
        var fixed = [CGFloat?](repeating: nil, count: n)
        var want = [CGFloat](repeating: 0, count: n)
        for (_, entry) in natural {
            let b = entry.block
            guard b.columnSpan == 1, b.startingColumn >= 0, b.startingColumn < n else { continue }
            if let w = b._resolvedValue(.width, basis: basis) {
                fixed[b.startingColumn] = w + b._inset(.minX, basis: basis) + b._inset(.maxX, basis: basis)
            }
            want[b.startingColumn] = max(want[b.startingColumn], entry.width)
        }
        var widths = [CGFloat](repeating: 0, count: n)
        let fixedTotal = fixed.compactMap { $0 }.reduce(0, +)
        let free = (0..<n).filter { fixed[$0] == nil }
        let remaining = max(0, available - fixedTotal)
        for i in 0..<n { if let f = fixed[i] { widths[i] = f } }
        if !free.isEmpty {
            if _layoutAlgorithm == .fixedLayoutAlgorithm || want.allSatisfy({ $0 == 0 }) {
                for i in free { widths[i] = remaining / CGFloat(free.count) }
            } else {
                let floorWidth: CGFloat = 12
                let wanted = free.map { max(floorWidth, want[$0]) }
                let total = wanted.reduce(0, +)
                let hasOwnWidth = _resolvedValue(.width, basis: rect.width) != nil
                let scale = (total > remaining || hasOwnWidth) && total > 0 ? remaining / total : 1
                for (k, i) in free.enumerated() { widths[i] = wanted[k] * scale }
            }
        }
        var x: CGFloat = 0
        _columnX = []
        for w in widths { _columnX.append(x); x += w }
        _columnWidth = widths
        let used = (_resolvedValue(.width, basis: rect.width) != nil) ? available : min(available, x)
        _contentRect = NSRect(x: tableRect.minX, y: tableRect.minY, width: used, height: tableRect.height)
    }

    open override func copy(with zone: NSZone? = nil) -> Any {
        let c = NSTextTable()
        _copyValues(into: c)
        c.numberOfColumns = numberOfColumns
        c.layoutAlgorithm = layoutAlgorithm
        c.collapsesBorders = collapsesBorders
        c.hidesEmptyCells = hidesEmptyCells
        return c
    }
}
