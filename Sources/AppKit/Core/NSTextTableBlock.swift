// NSTextTableBlock (hand-written; seeded from the generated stub, see tools/apigen)
//
// One cell of an NSTextTable: its row and column and the spans. Geometry and drawing go to
// the table, which knows the column layout (ADR-0030).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttableblock
open class NSTextTableBlock: NSTextBlock {
    private let _table: NSTextTable
    private let _row: Int, _rowSpan: Int, _column: Int, _columnSpan: Int

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttableblock/init(table:startingrow:rowspan:startingcolumn:columnspan:)
    public init(table: NSTextTable, startingRow row: Int, rowSpan: Int, startingColumn col: Int, columnSpan colSpan: Int) {
        _table = table
        _row = row; _rowSpan = max(1, rowSpan); _column = col; _columnSpan = max(1, colSpan)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttableblock/columnspan
    open var columnSpan: Int { _columnSpan }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttableblock/rowspan
    open var rowSpan: Int { _rowSpan }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttableblock/startingcolumn
    open var startingColumn: Int { _column }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttableblock/startingrow
    open var startingRow: Int { _row }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstexttableblock/table
    open var table: NSTextTable { _table }

    open override func rectForLayout(at startingPoint: NSPoint, in rect: NSRect, textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        _table.rect(for: self, layoutAt: startingPoint, in: rect, textContainer: textContainer, characterRange: charRange)
    }
    open override func boundsRect(forContentRect contentRect: NSRect, in rect: NSRect, textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        _table.boundsRect(for: self, contentRect: contentRect, in: rect, textContainer: textContainer, characterRange: charRange)
    }
    open override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        _table.drawBackground(for: self, withFrame: frameRect, in: controlView, characterRange: charRange, layoutManager: layoutManager)
    }
    open override func copy(with zone: NSZone? = nil) -> Any {
        let c = NSTextTableBlock(table: _table, startingRow: _row, rowSpan: _rowSpan, startingColumn: _column, columnSpan: _columnSpan)
        _copyValues(into: c)
        return c
    }

    // Required by the superclass (NSCoding). A decoded cell belongs to a table of its own.
    public required init?(coder: NSCoder) {
        _table = NSTextTable()
        _row = coder.decodeInteger(forKey: "NSRow"); _rowSpan = max(1, coder.decodeInteger(forKey: "NSRowSpan"))
        _column = coder.decodeInteger(forKey: "NSColumn"); _columnSpan = max(1, coder.decodeInteger(forKey: "NSColumnSpan"))
        super.init(coder: coder)
    }
    open override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(_row, forKey: "NSRow"); coder.encode(_rowSpan, forKey: "NSRowSpan")
        coder.encode(_column, forKey: "NSColumn"); coder.encode(_columnSpan, forKey: "NSColumnSpan")
    }
}
