// NSTableHeaderCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheadercell
@MainActor open class NSTableHeaderCell: NSTextFieldCell {
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        _alignment = .natural
        _lineBreakMode = .byTruncatingTail
    }
    public required init(coder: NSCoder) { super.init(coder: coder) }

    internal override var _textColor: NSColor { NSColor.headerTextColor }

    /// Header cells fill their background and draw a trailing separator; the sort indicator
    /// is drawn by the header view, which knows the table's sort state.
    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(rect: cellFrame).fill()
        if _isHighlighted {
            NSColor.controlColor.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: cellFrame).fill()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 4, width: 1, height: max(0, cellFrame.height - 8))).fill()
    }

    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let inset = cellFrame.insetBy(dx: 6, dy: 0)
        _drawText(stringValue, attributes: _textAttributes, in: inset, alignment: _alignment, flipped: controlView.isFlipped)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheadercell/drawsortindicator(withframe:in:ascending:priority:)
    @MainActor open func drawSortIndicator(withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int) {
        let r = sortIndicatorRect(forBounds: cellFrame)
        guard !r.isEmpty else { return }
        let path = NSBezierPath()
        // A small chevron: pointing up when ascending (y up in an unflipped view).
        let up = ascending != controlView.isFlipped
        let (tipY, baseY) = up ? (r.maxY, r.minY) : (r.minY, r.maxY)
        path.move(to: NSPoint(x: r.minX, y: baseY))
        path.line(to: NSPoint(x: r.midX, y: tipY))
        path.line(to: NSPoint(x: r.maxX, y: baseY))
        path.lineWidth = 1.5
        (priority == 0 ? NSColor.headerTextColor : NSColor.secondaryLabelColor).setStroke()
        path.stroke()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheadercell/sortindicatorrect(forbounds:)
    @MainActor open func sortIndicatorRect(forBounds rect: NSRect) -> NSRect {
        guard rect.width > 24 else { return .zero }
        return NSRect(x: rect.maxX - 14, y: rect.midY - 2.5, width: 7, height: 5)
    }
}
