// NSTableHeaderView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The header draws one cell per visible column, aligned with the table's columns. A
// click on a column with a sort descriptor prototype toggles the sort; dragging the
// edge between two columns resizes the left one.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview
@MainActor open class NSTableHeaderView: NSView, NSViewToolTipOwner {
    internal weak var _tableView: NSTableView?
    private var _draggedColumn = -1
    private var _draggedDistance: CGFloat = 0
    private var _resizedColumn = -1
    private var _resizeStartX: CGFloat = 0
    private var _resizeStartWidth: CGFloat = 0
    private var _pressedColumn = -1

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    public required init?(coder: NSCoder) { unimplemented() }

    @MainActor open override var isFlipped: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview/column(at:)
    @MainActor open func column(at point: NSPoint) -> Int {
        guard let t = _tableView else { return -1 }
        for (i, c) in t.tableColumns.enumerated() where !c.isHidden {
            if headerRect(ofColumn: i).contains(point) { return i }
        }
        return -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview/draggedcolumn
    @MainActor open var draggedColumn: Int { _draggedColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview/draggeddistance
    @MainActor open var draggedDistance: CGFloat { _draggedDistance }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview/headerrect(ofcolumn:)
    @MainActor open func headerRect(ofColumn column: Int) -> NSRect {
        guard let t = _tableView, t.tableColumns.indices.contains(column) else { return .zero }
        let r = t.rect(ofColumn: column)
        return NSRect(x: r.minX, y: 0, width: r.width, height: bounds.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview/resizedcolumn
    @MainActor open var resizedColumn: Int { _resizedColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview/tableview
    @MainActor open var tableView: NSTableView? {
        get { _tableView }
        set { _tableView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableheaderview/view(_:stringfortooltip:point:userdata:)
    @MainActor open func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let t = _tableView else { return "" }
        let i = column(at: point)
        return i >= 0 ? (t.tableColumns[i].headerToolTip ?? "") : ""
    }

    @MainActor open override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSTableHeaderView.defaultHeight) }
    static let defaultHeight: CGFloat = 23

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(rect: bounds).fill()
        guard let t = _tableView else { return }
        let sort = t.sortDescriptors.first
        for (i, c) in t.tableColumns.enumerated() where !c.isHidden {
            let r = headerRect(ofColumn: i)
            guard r.intersects(dirtyRect) else { continue }
            c.headerCell.isHighlighted = i == _pressedColumn
            c.headerCell.draw(withFrame: r, in: self)
            if let sort, let identity = c.sortDescriptorPrototype?._sortIdentity, identity == sort._sortIdentity {
                c.headerCell.drawSortIndicator(withFrame: r, in: self, ascending: sort.ascending, priority: 0)
            }
        }
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)).fill()
    }

    // MARK: Mouse

    /// The column whose trailing edge is within 4 points of `x`, for resizing.
    private func resizeEdgeColumn(at point: NSPoint) -> Int {
        guard let t = _tableView, t.allowsColumnResizing else { return -1 }
        for (i, c) in t.tableColumns.enumerated() where !c.isHidden && c.resizingMask.contains(.userResizingMask) {
            let r = headerRect(ofColumn: i)
            if abs(point.x - r.maxX) <= 4 { return i }
        }
        return -1
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard let t = _tableView else { return }
        let p = convert(event.locationInWindow, from: nil)
        let edge = resizeEdgeColumn(at: p)
        if edge >= 0 {
            _resizedColumn = edge
            _resizeStartX = p.x
            _resizeStartWidth = t.tableColumns[edge].width
            return
        }
        let i = column(at: p)
        guard i >= 0 else { return }
        _pressedColumn = i
        t.delegate?.tableView(t, mouseDownInHeaderOf: t.tableColumns[i])
        needsDisplay = true
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard let t = _tableView else { return }
        let p = convert(event.locationInWindow, from: nil)
        if _resizedColumn >= 0 {
            t.tableColumns[_resizedColumn].width = _resizeStartWidth + (p.x - _resizeStartX)
            return
        }
        if _pressedColumn >= 0 {
            let inside = column(at: p) == _pressedColumn
            let was = _pressedColumn
            _pressedColumn = inside ? was : -1
            if _pressedColumn < 0 { _pressedColumn = was; _draggedDistance = p.x - headerRect(ofColumn: was).midX }
            needsDisplay = true
        }
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        guard let t = _tableView else { return }
        let p = convert(event.locationInWindow, from: nil)
        if _resizedColumn >= 0 {
            _resizedColumn = -1
            return
        }
        guard _pressedColumn >= 0 else { return }
        let pressed = _pressedColumn
        _pressedColumn = -1
        _draggedDistance = 0
        needsDisplay = true
        guard column(at: p) == pressed else { return }
        t._headerClicked(column: pressed)
    }

    @MainActor open override func resetCursorRects() {
        guard let t = _tableView, t.allowsColumnResizing else { return }
        for (i, c) in t.tableColumns.enumerated() where !c.isHidden && c.resizingMask.contains(.userResizingMask) {
            let r = headerRect(ofColumn: i)
            addCursorRect(NSRect(x: r.maxX - 4, y: 0, width: 8, height: bounds.height), cursor: .resizeLeftRight)
        }
    }
}
