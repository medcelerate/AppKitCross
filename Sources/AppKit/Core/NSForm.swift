// NSForm (hand-written; seeded from the generated stub, see tools/apigen)
//
// A one-column NSMatrix of NSFormCells (ADR-0032): titled text entries stacked with
// `interlineSpacing` between them, every title as wide as the widest so the entries line
// up, and the entries as wide as the form. Entries are edited through the matrix's
// field-editor path; Tab moves from one entry to the next.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform
@MainActor open class NSForm: NSMatrix {
    private var _preferredTextFieldWidth: CGFloat = 0

    @MainActor internal override class var _defaultCellClass: AnyClass { NSFormCell.self }

    @MainActor internal override func _configureNewMatrix(frame frameRect: NSRect) {
        intercellSpacing = NSSize(width: 0, height: 8)
        cellSize = NSSize(width: frameRect.width > 0 ? frameRect.width : 200, height: 22)
        allowsEmptySelection = true
    }

    private var _formCells: [NSFormCell] { cells.compactMap { $0 as? NSFormCell } }

    /// Gives every entry the widest title's width, so the entries start at one x.
    internal func _alignTitles() {
        let cells = _formCells
        let width = cells.map { $0._ownTitleWidth }.max() ?? 0
        for c in cells where c._formTitleWidth != width { c._formTitleWidth = width }
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        _alignTitles()
        super.draw(dirtyRect)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/addentry(_:)
    @MainActor open func addEntry(_ title: String) -> NSFormCell { insertEntry(title, at: numberOfRows) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/insertentry(_:at:)
    @MainActor open func insertEntry(_ title: String, at index: Int) -> NSFormCell! {
        guard index >= 0, index <= numberOfRows else { return nil }
        let made = makeCell(atRow: index, column: 0)
        let cell = (made as? NSFormCell) ?? NSFormCell(textCell: title)
        cell.title = title
        if _preferredTextFieldWidth > 0 { cell.preferredTextFieldWidth = _preferredTextFieldWidth }
        insertRow(index, with: [cell])
        _alignTitles()
        return cell
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/removeentry(at:)
    @MainActor open func removeEntry(at index: Int) {
        removeRow(index)
        _alignTitles()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/cell(at:)
    @MainActor open func cell(at index: Int) -> Any! { cell(atRow: index, column: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/drawcell(at:)
    @MainActor open func drawCell(at index: Int) { drawCell(atRow: index, column: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/indexofcell(withtag:)
    @MainActor open func indexOfCell(withTag tag: Int) -> Int {
        guard let c = cell(withTag: tag), let p = _position(of: c) else { return -1 }
        return p.row
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/indexofselecteditem()
    @MainActor open func indexOfSelectedItem() -> Int { selectedRow }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/selecttext(at:)
    @MainActor open func selectText(at index: Int) { _ = selectText(atRow: index, column: 0) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/setentrywidth(_:)
    /// The width of every entry, title and text field together.
    @MainActor open func setEntryWidth(_ width: CGFloat) {
        cellSize = NSSize(width: width, height: cellSize.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/setinterlinespacing(_:)
    @MainActor open func setInterlineSpacing(_ spacing: CGFloat) {
        intercellSpacing = NSSize(width: intercellSpacing.width, height: spacing)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/preferredtextfieldwidth()
    @MainActor open func preferredTextFieldWidth() -> CGFloat { _preferredTextFieldWidth }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/setpreferredtextfieldwidth(_:)
    @MainActor open func setPreferredTextFieldWidth(_ preferredWidth: CGFloat) {
        _preferredTextFieldWidth = preferredWidth
        for c in _formCells { c.preferredTextFieldWidth = preferredWidth }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/setbezeled(_:)
    @MainActor open func setBezeled(_ flag: Bool) { for c in cells { c.isBezeled = flag }; needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/setbordered(_:)
    @MainActor open func setBordered(_ flag: Bool) { for c in cells { c.isBordered = flag }; needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/settextalignment(_:)
    @MainActor open func setTextAlignment(_ mode: NSTextAlignment) { for c in cells { c.alignment = mode }; needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/settextbasewritingdirection(_:)
    @MainActor open func setTextBaseWritingDirection(_ writingDirection: NSWritingDirection) { for c in cells { c.baseWritingDirection = writingDirection } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/settextfont(_:)
    @MainActor open func setTextFont(_ fontObj: NSFont) { for c in cells { c.font = fontObj }; needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/settitlealignment(_:)
    @MainActor open func setTitleAlignment(_ mode: NSTextAlignment) { for c in _formCells { c.titleAlignment = mode }; needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/settitlebasewritingdirection(_:)
    @MainActor open func setTitleBaseWritingDirection(_ writingDirection: NSWritingDirection) { for c in _formCells { c.titleBaseWritingDirection = writingDirection } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/settitlefont(_:)
    @MainActor open func setTitleFont(_ fontObj: NSFont) {
        for c in _formCells { c.titleFont = fontObj }
        _alignTitles()
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsform/setframesize(_:)
    /// The entries follow the form's width.
    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if numberOfColumns == 1, newSize.width > 0, cellSize.width != newSize.width {
            cellSize = NSSize(width: newSize.width, height: cellSize.height)
        }
    }
}
