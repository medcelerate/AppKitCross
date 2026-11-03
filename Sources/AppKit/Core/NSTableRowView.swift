// NSTableRowView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// One row of a view-based table: it draws the row background and selection and holds
// the cell views (one per column) as subviews.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview
@MainActor open class NSTableRowView: NSView, NSAccessibilityRow, NSAccessibilityGroup {
    private var _backgroundColor: NSColor = .clear
    private var _feedbackStyle: NSTableView.DraggingDestinationFeedbackStyle = .regular
    private var _indentationForDropOperation: CGFloat = 0
    private var _isEmphasized = false
    private var _isFloating = false
    private var _isGroupRowStyle = false
    private var _isNextRowSelected = false
    private var _isPreviousRowSelected = false
    private var _isSelected = false
    private var _isTargetForDropOperation = false
    private var _selectionHighlightStyle: NSTableView.SelectionHighlightStyle = .regular
    /// Set by the table: the row index this view currently shows.
    internal var _row = -1
    /// Rounded selection and inset grid (NSTableView.Style.inset).
    internal var _insetStyle = false

    @MainActor public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { unimplemented() }

    @MainActor open override var isFlipped: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/draggingdestinationfeedbackstyle
    @MainActor open var draggingDestinationFeedbackStyle: NSTableView.DraggingDestinationFeedbackStyle {
        get { _feedbackStyle }
        set { _feedbackStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/drawbackground(in:)
    @MainActor open func drawBackground(in dirtyRect: NSRect) {
        guard _backgroundColor.alphaComponent > 0 else { return }
        _backgroundColor.setFill()
        NSBezierPath(rect: bounds.intersection(dirtyRect)).fill()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/drawdraggingdestinationfeedback(in:)
    @MainActor open func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        guard _isTargetForDropOperation else { return }
        NSColor.controlAccentColor.setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        p.lineWidth = 2
        p.stroke()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/drawselection(in:)
    @MainActor open func drawSelection(in dirtyRect: NSRect) {
        guard _isSelected, _selectionHighlightStyle != .none else { return }
        let color = _isEmphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor
        color.setFill()
        if _insetStyle {
            var r = bounds.insetBy(dx: 10, dy: 0)
            // Adjacent selected rows join into one rounded block.
            let radius: CGFloat = 5
            if _isPreviousRowSelected { r.origin.y -= radius; r.size.height += radius }
            if _isNextRowSelected { r.size.height += radius }
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        } else {
            NSBezierPath(rect: bounds).fill()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/drawseparator(in:)
    @MainActor open func drawSeparator(in dirtyRect: NSRect) {
        guard _isGroupRowStyle else { return }
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)).fill()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/indentationfordropoperation
    @MainActor open var indentationForDropOperation: CGFloat {
        get { _indentationForDropOperation }
        set { _indentationForDropOperation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/interiorbackgroundstyle
    @MainActor open var interiorBackgroundStyle: NSView.BackgroundStyle {
        _isSelected && _isEmphasized && _selectionHighlightStyle != .none ? .emphasized : .normal
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/isemphasized
    @MainActor open var isEmphasized: Bool {
        get { _isEmphasized }
        set { guard newValue != _isEmphasized else { return }; _isEmphasized = newValue; _updateCellBackgroundStyles(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/isfloating
    @MainActor open var isFloating: Bool {
        get { _isFloating }
        set { _isFloating = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/isgrouprowstyle
    @MainActor open var isGroupRowStyle: Bool {
        get { _isGroupRowStyle }
        set { _isGroupRowStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/isnextrowselected
    @MainActor open var isNextRowSelected: Bool {
        get { _isNextRowSelected }
        set { _isNextRowSelected = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/ispreviousrowselected
    @MainActor open var isPreviousRowSelected: Bool {
        get { _isPreviousRowSelected }
        set { _isPreviousRowSelected = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/isselected
    @MainActor open var isSelected: Bool {
        get { _isSelected }
        set { guard newValue != _isSelected else { return }; _isSelected = newValue; _updateCellBackgroundStyles(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/istargetfordropoperation
    @MainActor open var isTargetForDropOperation: Bool {
        get { _isTargetForDropOperation }
        set { _isTargetForDropOperation = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/numberofcolumns
    @MainActor open var numberOfColumns: Int { subviews.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/selectionhighlightstyle
    @MainActor open var selectionHighlightStyle: NSTableView.SelectionHighlightStyle {
        get { _selectionHighlightStyle }
        set { _selectionHighlightStyle = newValue; _updateCellBackgroundStyles(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/view(atcolumn:)
    @MainActor open func view(atColumn column: Int) -> Any? { subviews.indices.contains(column) ? subviews[column] : nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/accessibilityindex()
    open func accessibilityIndex() -> Int { MainActor.assumeIsolated { _row } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstablerowview/accessibilitydisclosurelevel()
    open func accessibilityDisclosureLevel() -> Int { 0 }

    private func _updateCellBackgroundStyles() {
        let style = interiorBackgroundStyle
        for v in subviews { (v as? NSTableCellView)?.backgroundStyle = style }
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        drawBackground(in: dirtyRect)
        drawSelection(in: dirtyRect)
        drawSeparator(in: dirtyRect)
        drawDraggingDestinationFeedback(in: dirtyRect)
    }

    /// Rows forward clicks to the table, which runs the selection.
    @MainActor open override func hitTest(_ point: NSPoint) -> NSView? {
        guard let v = super.hitTest(point) else { return nil }
        // Labels and other passive content in cells are not interactive: the row (hence
        // the table) takes the click. Controls and editable fields keep it.
        if let f = v as? NSTextField { return f.isEditable || f.isSelectable ? v : self }
        if v is NSControl || v.acceptsFirstResponder { return v }
        return self
    }
    @MainActor open override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    @MainActor open override func mouseDragged(with event: NSEvent) { superview?.mouseDragged(with: event) }
    @MainActor open override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }
}
