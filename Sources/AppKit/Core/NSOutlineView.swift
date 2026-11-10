// NSOutlineView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A tree over the table's row model: the outline keeps a node per item it has seen,
// flattens the expanded part of the tree into rows, and answers the table's subclass
// hooks (row count, cell views, object values, delegate calls) from that list and the
// outline protocols. Each expandable row carries a disclosure button (identifier
// `NSOutlineView.disclosureButtonIdentifier`) in its row view, and the outline column's
// cell is indented by the row's level; both mirror right to left.
//
// `dataSource` and `delegate` keep the table's types: Swift cannot redeclare an inherited
// property with another type, so `NSOutlineViewDataSource` and `NSOutlineViewDelegate`
// refine the table protocols (tools/apigen/config.json, protocolExtraParents) and the
// outline reads its own protocols through them.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Identity of an item: objects by identity, hashable values by value, the rest by
/// description (as AppKit's `isEqual` matching does).
enum _NSOutlineItemKey: Hashable {
    case object(ObjectIdentifier)
    case value(AnyHashable)
    case description(String)

    init(_ item: Any) {
        if type(of: item) is AnyClass { self = .object(ObjectIdentifier(item as AnyObject)) }
        else if let h = item as? AnyHashable { self = .value(h) }
        else { self = .description(String(describing: item)) }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview
@MainActor open class NSOutlineView: NSTableView, NSAccessibilityOutline {
    // MARK: Tree

    /// One item the outline has seen.
    final class _Node {
        let item: Any
        let key: _NSOutlineItemKey
        weak var parent: _Node?
        var level: Int
        var children: [_Node]?      // loaded on expansion (or when asked)
        var expanded = false
        var row = -1                // row in the flattened list, -1 while hidden
        init(item: Any, parent: _Node?, level: Int) {
            self.item = item
            self.key = _NSOutlineItemKey(item)
            self.parent = parent
            self.level = level
        }
    }

    private var _roots: [_Node]? = nil
    private var _rows: [_Node] = []
    private var _rowsDirty = true
    private var _expandedKeys: Set<_NSOutlineItemKey> = []
    private var _outlineTableColumn: NSTableColumn?
    private var _indentationPerLevel: CGFloat = 16
    private var _indentationMarkerFollowsCell = true
    private var _autoresizesOutlineColumn = true
    private var _autosaveExpandedItems = false
    private var _stronglyReferencesItems = true
    private var _dropItem: Any?
    private var _dropChildIndex = NSOutlineViewDropOnItemIndex
    private var _dropLineY: CGFloat?
    private var _hasDropTarget = false

    /// Width of the disclosure button's slot in the outline column.
    static let disclosureWidth: CGFloat = 16

    private var _outlineDataSource: (any NSOutlineViewDataSource)? { dataSource as? NSOutlineViewDataSource }
    private var _outlineDelegate: (any NSOutlineViewDelegate)? { delegate as? NSOutlineViewDelegate }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { unimplemented() }

    /// The tree is dropped with the data source; the rows come back from the new one.
    @MainActor open override var dataSource: (any NSTableViewDataSource)? {
        get { super.dataSource }
        set { _roots = nil; _rowsDirty = true; super.dataSource = newValue }
    }

    // MARK: Notifications
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/columndidmovenotification
    open override class var columnDidMoveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewColumnDidMoveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/columndidresizenotification
    open override class var columnDidResizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewColumnDidResizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/selectiondidchangenotification
    open override class var selectionDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewSelectionDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/selectionischangingnotification
    open override class var selectionIsChangingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewSelectionIsChangingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/itemdidcollapsenotification
    static public var itemDidCollapseNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewItemDidCollapseNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/itemdidexpandnotification
    static public var itemDidExpandNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewItemDidExpandNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/itemwillcollapsenotification
    static public var itemWillCollapseNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewItemWillCollapseNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/itemwillexpandnotification
    static public var itemWillExpandNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSOutlineViewItemWillExpandNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/disclosurebuttonidentifier
    static public var disclosureButtonIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue: "NSOutlineViewDisclosureButtonKey") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/showhidebuttonidentifier
    static public var showHideButtonIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue: "NSOutlineViewShowHideButtonKey") }

    // MARK: Loading the tree

    /// Reads `node`'s children from the data source. Nodes of items that were already
    /// there keep their subtrees and expansion state.
    private func _loadChildren(of node: _Node?) -> [_Node] {
        guard let ds = _outlineDataSource else { return [] }
        let parentItem = node?.item
        let count = max(0, ds.outlineView(self, numberOfChildrenOfItem: parentItem))
        let level = (node?.level ?? -1) + 1
        let old = node?.children ?? (node == nil ? _roots : nil) ?? []
        var byKey: [_NSOutlineItemKey: _Node] = [:]
        for o in old { byKey[o.key] = o }
        return (0..<count).map { i in
            let item = ds.outlineView(self, child: i, ofItem: parentItem)
            let key = _NSOutlineItemKey(item)
            if let existing = byKey[key] {
                existing.parent = node
                _setLevel(existing, level)
                return existing
            }
            let n = _Node(item: item, parent: node, level: level)
            n.expanded = _expandedKeys.contains(key) && _isExpandable(n)
            return n
        }
    }

    private func _setLevel(_ node: _Node, _ level: Int) {
        guard node.level != level else { return }
        node.level = level
        for c in node.children ?? [] { _setLevel(c, level + 1) }
    }

    private func _children(of node: _Node?) -> [_Node] {
        if let node {
            if node.children == nil { node.children = _loadChildren(of: node) }
            return node.children!
        }
        if _roots == nil { _roots = _loadChildren(of: nil) }
        return _roots!
    }

    private func _isExpandable(_ node: _Node) -> Bool {
        _outlineDataSource?.outlineView(self, isItemExpandable: node.item) ?? false
    }

    /// Rebuilds the flattened rows from the expanded part of the tree.
    private func _rebuildRowsIfNeeded() {
        guard _rowsDirty else { return }
        _rowsDirty = false
        for n in _rows { n.row = -1 }
        var rows: [_Node] = []
        func visit(_ nodes: [_Node]) {
            for n in nodes {
                n.row = rows.count
                rows.append(n)
                if n.expanded { visit(_children(of: n)) }
            }
        }
        visit(_children(of: nil))
        _rows = rows
    }

    private func _node(for item: Any?) -> _Node? {
        guard let item else { return nil }
        let key = _NSOutlineItemKey(item)
        _rebuildRowsIfNeeded()
        if let n = _rows.first(where: { $0.key == key }) { return n }
        // Not visible: search the loaded part of the tree.
        func find(_ nodes: [_Node]) -> _Node? {
            for n in nodes {
                if n.key == key { return n }
                if let c = n.children, let hit = find(c) { return hit }
            }
            return nil
        }
        return find(_roots ?? [])
    }

    /// The rows changed shape: re-reads them, keeping the same items selected (a selected
    /// item hidden by a collapse hands the selection to its nearest visible ancestor).
    private func _rowsDidChange() {
        _rebuildRowsIfNeeded()
        let selectedNodes = selectedRowIndexes.compactMap { $0 < _rows.count ? _rows[$0] : nil }
        _rowsDirty = true
        noteNumberOfRowsChanged()
        var selection = IndexSet()
        for n in selectedNodes {
            var cur: _Node? = n
            while let c = cur, c.row < 0 { cur = c.parent }
            if let c = cur { selection.insert(c.row) }
        }
        selectRowIndexes(selection, byExtendingSelection: false)
        _accessibilityNotify(.structure(_accessibilityElementID))
    }

    // MARK: Row model hooks

    override func _rowCountFromDataSource() -> Int {
        _rebuildRowsIfNeeded()
        return _rows.count
    }
    override func _delegateHeightOfRow(_ row: Int) -> CGFloat {
        guard let n = _rows.indices.contains(row) ? _rows[row] : nil, let d = _outlineDelegate else { return rowHeight }
        return d.outlineView(self, heightOfRowByItem: n.item)
    }
    override func _delegateView(for column: NSTableColumn, row: Int) -> NSView? {
        guard let item = item(atRow: row) else { return nil }
        return _outlineDelegate?.outlineView(self, viewFor: column, item: item)
    }
    override func _objectValue(for column: NSTableColumn?, row: Int) -> Any? {
        guard let item = item(atRow: row) else { return nil }
        return _outlineDataSource?.outlineView(self, objectValueFor: column, byItem: item)
    }
    override func _delegateRowView(forRow row: Int) -> NSTableRowView? {
        guard let item = item(atRow: row) else { return nil }
        if let v = _outlineDelegate?.outlineView(self, rowViewForItem: item) { return v }
        let rv = _NSOutlineRowView(frame: .zero)
        rv._outline = self
        return rv
    }
    override func _delegateIsGroupRow(_ row: Int) -> Bool {
        guard let item = item(atRow: row) else { return false }
        return _outlineDelegate?.outlineView(self, isGroupItem: item) ?? false
    }
    override func _delegateDidAdd(_ rowView: NSTableRowView, row: Int) { _outlineDelegate?.outlineView(self, didAdd: rowView, forRow: row) }
    override func _delegateDidRemove(_ rowView: NSTableRowView, row: Int) { _outlineDelegate?.outlineView(self, didRemove: rowView, forRow: row) }
    override func _delegateSelectionShouldChange() -> Bool { _outlineDelegate?.selectionShouldChange(in: self) ?? true }
    override func _delegateSelectionIndexes(forProposed rows: IndexSet) -> IndexSet { _outlineDelegate?.outlineView(self, selectionIndexesForProposedSelection: rows) ?? rows }
    override func _delegateShouldSelectRow(_ row: Int) -> Bool {
        guard let item = item(atRow: row) else { return false }
        return _outlineDelegate?.outlineView(self, shouldSelectItem: item) ?? true
    }
    override func _delegateSelectionDidChange(_ notification: Notification) { _outlineDelegate?.outlineViewSelectionDidChange(notification) }
    override func _delegateDidClick(column: NSTableColumn) { _outlineDelegate?.outlineView(self, didClick: column) }
    override func _delegateColumnDidMove(_ notification: Notification) { _outlineDelegate?.outlineViewColumnDidMove(notification) }
    override func _delegateColumnDidResize(_ notification: Notification) { _outlineDelegate?.outlineViewColumnDidResize(notification) }
    override func _dataSourceSortDescriptorsDidChange(_ old: [NSSortDescriptor]) { _outlineDataSource?.outlineView(self, sortDescriptorsDidChange: old) }
    override func _delegateDataCell(for column: NSTableColumn, row: Int) -> NSCell? {
        guard let item = item(atRow: row) else { return nil }
        return _outlineDelegate?.outlineView(self, dataCellFor: column, item: item)
    }
    override func _delegateWillDisplayCell(_ cell: NSCell, for column: NSTableColumn, row: Int) {
        guard let item = item(atRow: row) else { return }
        _outlineDelegate?.outlineView(self, willDisplayCell: cell, for: column, item: item)
    }

    /// The outline column's cell starts after the disclosure slot and the row's indentation.
    override func _cellFrames(forRow row: Int, height: CGFloat) -> [(column: Int, frame: NSRect)] {
        var frames = super._cellFrames(forRow: row, height: height)
        guard let outlineIndex = _outlineColumnIndex, let i = frames.firstIndex(where: { $0.column == outlineIndex }) else { return frames }
        let indent = min(frames[i].frame.width, _indentation(forRow: row) + NSOutlineView.disclosureWidth)
        var f = frames[i].frame
        if !_isRightToLeft { f.origin.x += indent }
        f.size.width -= indent
        frames[i].frame = f
        return frames
    }

    private var _outlineColumnIndex: Int? {
        guard let c = _outlineTableColumn, !c.isHidden else { return nil }
        return tableColumns.firstIndex { $0 === c }
    }

    private func _indentation(forRow row: Int) -> CGFloat {
        _rebuildRowsIfNeeded()
        guard _rows.indices.contains(row) else { return 0 }
        return CGFloat(_rows[row].level) * _indentationPerLevel
    }

    /// Places (or removes) the row's disclosure button.
    override func _rowViewDidLayout(_ rowView: NSTableRowView, row: Int) {
        let existing = rowView.subviews.first { $0.identifier == NSOutlineView.disclosureButtonIdentifier } as? _NSOutlineDisclosureButton
        _rebuildRowsIfNeeded()
        guard _rows.indices.contains(row), _outlineColumnIndex != nil else { existing?.removeFromSuperview(); return }
        let node = _rows[row]
        let shows = _isExpandable(node) && (_outlineDelegate?.outlineView(self, shouldShowOutlineCellForItem: node.item) ?? true)
        guard shows else { existing?.removeFromSuperview(); return }
        let button = existing ?? _NSOutlineDisclosureButton(frame: .zero)
        button.identifier = NSOutlineView.disclosureButtonIdentifier
        button._row = row
        button.isExpanded = node.expanded
        button.pointsLeft = _isRightToLeft
        button.frame = _disclosureFrame(forRow: row, inRowView: true)
        button.target = self
        button.action = NSOutlineView._disclosureAction
        if existing == nil { rowView.addSubview(button) }
        if let rv = rowView as? _NSOutlineRowView { rv._outline = self }
        button.needsDisplay = true
    }

    private static let _disclosureAction = Selector(("_disclosureClicked:"))

    /// The disclosure button's frame in the row view (y from 0) or the outline (row rect).
    private func _disclosureFrame(forRow row: Int, inRowView: Bool) -> NSRect {
        guard let outlineIndex = _outlineColumnIndex else { return .zero }
        let column = rect(ofColumn: outlineIndex)
        let r = rect(ofRow: row)
        let indent = _indentation(forRow: row)
        let size: CGFloat = NSOutlineView.disclosureWidth
        let x = _isRightToLeft ? column.maxX - indent - size : column.minX + indent
        return NSRect(x: x, y: (inRowView ? 0 : r.minY) + ((r.height - size) / 2).rounded(.down), width: size, height: size)
    }

    /// `_disclosureClicked:` from a row's button: toggles the row's item; Option toggles
    /// the whole subtree.
    @MainActor open override func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        if action == NSOutlineView._disclosureAction, let b = sender as? _NSOutlineDisclosureButton {
            _toggle(row: b._row, deep: NSApplication.shared.currentEvent?.modifierFlags.contains(.option) ?? false)
            return true
        }
        return super.performSelectorAction(action, with: sender)
    }
    @MainActor open override func respondsToSelectorAction(_ action: Selector) -> Bool {
        action == NSOutlineView._disclosureAction || super.respondsToSelectorAction(action)
    }

    private func _toggle(row: Int, deep: Bool) {
        guard let item = item(atRow: row) else { return }
        if isItemExpanded(item) { collapseItem(item, collapseChildren: deep) } else { expandItem(item, expandChildren: deep) }
    }

    /// Rows that start a drag hand their items to the data source.
    override func _beginRowDrag(with event: NSEvent, row: Int) -> Bool {
        guard let ds = _outlineDataSource else { return false }
        _rebuildRowsIfNeeded()
        let rows = selectedRowIndexes.contains(row) ? Array(selectedRowIndexes) : [row]
        let items = rows.compactMap { item(atRow: $0) }
        guard !items.isEmpty else { return false }
        var dragItems: [NSDraggingItem] = []
        for (r, item) in zip(rows, items) {
            if let w = ds.outlineView(self, pasteboardWriterForItem: item) {
                let d = NSDraggingItem(pasteboardWriter: w)
                d.draggingFrame = rect(ofRow: r)
                dragItems.append(d)
            }
        }
        if dragItems.isEmpty {
            let pb = NSPasteboard(name: NSPasteboard.Name(rawValue: "Apple CFPasteboard drag"))
            pb.clearContents()
            guard ds.outlineView(self, writeItems: items, to: pb) else { return false }
            for (r, pi) in zip(rows, pb.pasteboardItems ?? []) {
                let d = NSDraggingItem(pasteboardWriter: pi)
                d.draggingFrame = rect(ofRow: r)
                dragItems.append(d)
            }
            guard !dragItems.isEmpty else { return false }
        }
        let session = beginDraggingSession(with: dragItems, event: event, source: self)
        let screen = window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        ds.outlineView(self, draggingSession: session, willBeginAt: screen, forItems: items)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession(_:endedat:operation:)
    @MainActor open func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        _outlineDataSource?.outlineView(self, draggingSession: session, endedAt: screenPoint, operation: operation)
    }

    // MARK: Drop destination

    /// The item and child index a point proposes: the middle of an expandable row drops
    /// on it, the edges of a row drop between it and its neighbour, below the rows appends
    /// to the root.
    private func _dropTarget(at pointInWindow: NSPoint) -> (item: Any?, childIndex: Int) {
        let p = convert(pointInWindow, from: nil)
        _rebuildRowsIfNeeded()
        let row = self.row(at: p)
        guard row >= 0, _rows.indices.contains(row) else { return (nil, _children(of: nil).count) }
        let node = _rows[row]
        let r = rect(ofRow: row)
        let fraction = r.height > 0 ? (p.y - r.minY) / r.height : 0.5
        if fraction >= 0.25 && fraction < 0.75 && _isExpandable(node) { return (node.item, NSOutlineViewDropOnItemIndex) }
        let siblings = _children(of: node.parent)
        let index = siblings.firstIndex { $0 === node } ?? 0
        return (node.parent?.item, index + (fraction >= 0.5 ? 1 : 0))
    }

    private func _validate(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let ds = _outlineDataSource else { return [] }
        let (item, index) = _dropTarget(at: info.draggingLocation)
        setDropItem(item, dropChildIndex: index)
        let op = ds.outlineView(self, validateDrop: info, proposedItem: _dropItem, proposedChildIndex: _dropChildIndex)
        if op.isEmpty { _clearDropTarget() }
        return op
    }
    @MainActor open override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        _outlineDataSource?.outlineView(self, updateDraggingItemsForDrag: sender)
        return _validate(sender)
    }
    @MainActor open override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { _validate(sender) }
    @MainActor open override func draggingExited(_ sender: (any NSDraggingInfo)?) { _clearDropTarget() }
    @MainActor open override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { _clearDropTarget() }
        guard _hasDropTarget, let ds = _outlineDataSource else { return false }
        return ds.outlineView(self, acceptDrop: sender, item: _dropItem, childIndex: _dropChildIndex)
    }
    private func _clearDropTarget() {
        _hasDropTarget = false
        _dropItem = nil
        _dropLineY = nil
        enumerateAvailableRowViews { rv, _ in rv.isTargetForDropOperation = false }
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/setdropitem(_:dropchildindex:)
    @MainActor open func setDropItem(_ item: Any?, dropChildIndex index: Int) {
        _dropItem = item
        _dropChildIndex = index
        _hasDropTarget = true
        _dropLineY = nil
        let onRow = index == NSOutlineViewDropOnItemIndex ? row(forItem: item) : -1
        enumerateAvailableRowViews { rv, r in rv.isTargetForDropOperation = r == onRow }
        if index != NSOutlineViewDropOnItemIndex {
            // A line between the rows: under the sibling before the index (and its visible
            // subtree), else above the sibling at the index, else under the parent.
            let siblings = _children(of: _node(for: item))
            if index > 0, index - 1 < siblings.count, siblings[index - 1].row >= 0 {
                var last = siblings[index - 1]
                while last.expanded, let c = last.children, let l = c.last, l.row >= 0 { last = l }
                _dropLineY = rect(ofRow: last.row).maxY
            } else if index < siblings.count, siblings[index].row >= 0 {
                _dropLineY = rect(ofRow: siblings[index].row).minY
            } else if row(forItem: item) >= 0 {
                _dropLineY = rect(ofRow: row(forItem: item)).maxY
            } else if numberOfRows > 0 {
                _dropLineY = rect(ofRow: numberOfRows - 1).maxY
            } else {
                _dropLineY = 0
            }
        }
        needsDisplay = true
    }
    @MainActor open override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let y = _dropLineY {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: y - 1, width: bounds.width, height: 2)).fill()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/shouldcollapseautoexpandeditems(fordeposited:)
    @MainActor open func shouldCollapseAutoExpandedItems(forDeposited deposited: Bool) -> Bool { deposited }

    // MARK: Columns

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/outlinetablecolumn
    @MainActor open var outlineTableColumn: NSTableColumn? {
        get { _outlineTableColumn }
        set { _outlineTableColumn = newValue; _columnsDidChange() }
    }
    /// The first column added is the outline column, as in AppKit.
    @MainActor open override func addTableColumn(_ tableColumn: NSTableColumn) {
        super.addTableColumn(tableColumn)
        if _outlineTableColumn == nil { _outlineTableColumn = tableColumn }
    }
    @MainActor open override func removeTableColumn(_ tableColumn: NSTableColumn) {
        super.removeTableColumn(tableColumn)
        if _outlineTableColumn === tableColumn { _outlineTableColumn = tableColumns.first }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/autoresizesoutlinecolumn
    @MainActor open var autoresizesOutlineColumn: Bool {
        get { _autoresizesOutlineColumn }
        set { _autoresizesOutlineColumn = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/indentationmarkerfollowscell
    @MainActor open var indentationMarkerFollowsCell: Bool {
        get { _indentationMarkerFollowsCell }
        set { _indentationMarkerFollowsCell = newValue; _columnsDidChange() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/indentationperlevel
    @MainActor open var indentationPerLevel: CGFloat {
        get { _indentationPerLevel }
        set { _indentationPerLevel = max(0, newValue); _columnsDidChange() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/stronglyreferencesitems
    @available(macOS 10.12, *)
    @MainActor open var stronglyReferencesItems: Bool {
        get { _stronglyReferencesItems }
        set { _stronglyReferencesItems = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/frameofoutlinecell(atrow:)
    @MainActor open func frameOfOutlineCell(atRow row: Int) -> NSRect {
        _rebuildRowsIfNeeded()
        guard _rows.indices.contains(row), _isExpandable(_rows[row]) else { return .zero }
        return _disclosureFrame(forRow: row, inRowView: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/userinterfacelayoutdirection
    @MainActor open override var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { super.userInterfaceLayoutDirection }
        set { super.userInterfaceLayoutDirection = newValue; needsDisplay = true }
    }

    // MARK: Items and rows

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/item(atrow:)
    @MainActor open func item(atRow row: Int) -> Any? {
        _rebuildRowsIfNeeded()
        return _rows.indices.contains(row) ? _rows[row].item : nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/row(foritem:)
    @MainActor open func row(forItem item: Any?) -> Int {
        guard let item else { return -1 }
        _rebuildRowsIfNeeded()
        let key = _NSOutlineItemKey(item)
        return _rows.firstIndex { $0.key == key } ?? -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/level(foritem:)
    @MainActor open func level(forItem item: Any?) -> Int { _node(for: item)?.level ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/level(forrow:)
    @MainActor open func level(forRow row: Int) -> Int {
        _rebuildRowsIfNeeded()
        return _rows.indices.contains(row) ? _rows[row].level : -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/parent(foritem:)
    @MainActor open func parent(forItem item: Any?) -> Any? { _node(for: item)?.parent?.item }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/child(_:ofitem:)
    @available(macOS 10.10, *)
    @MainActor open func child(_ index: Int, ofItem item: Any?) -> Any? {
        let children = _children(of: _node(for: item))
        return children.indices.contains(index) ? children[index].item : nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/numberofchildren(ofitem:)
    @available(macOS 10.10, *)
    @MainActor open func numberOfChildren(ofItem item: Any?) -> Int { _children(of: _node(for: item)).count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/childindex(foritem:)
    @available(macOS 10.11, *)
    @MainActor open func childIndex(forItem item: Any) -> Int {
        guard let node = _node(for: item) else { return -1 }
        return _children(of: node.parent).firstIndex { $0 === node } ?? -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/isexpandable(_:)
    @MainActor open func isExpandable(_ item: Any?) -> Bool {
        guard let item else { return true }
        return _outlineDataSource?.outlineView(self, isItemExpandable: item) ?? false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/isitemexpanded(_:)
    @MainActor open func isItemExpanded(_ item: Any?) -> Bool {
        guard let item else { return true }
        return _node(for: item)?.expanded ?? false
    }

    // MARK: Expanding and collapsing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/expanditem(_:)
    @MainActor open func expandItem(_ item: Any?) { expandItem(item, expandChildren: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/expanditem(_:expandchildren:)
    @MainActor open func expandItem(_ item: Any?, expandChildren: Bool) {
        if item == nil {
            guard expandChildren else { return }
            for n in _children(of: nil) { _expand(n, deep: true) }
            return
        }
        guard let node = _node(for: item) else { return }
        _expand(node, deep: expandChildren)
    }
    private func _expand(_ node: _Node, deep: Bool) {
        if !node.expanded, _isExpandable(node) {
            guard _outlineDelegate?.outlineView(self, shouldExpandItem: node.item) ?? true else { return }
            let info: [AnyHashable: Any] = ["NSObject": node.item]
            let will = Notification(name: NSOutlineView.itemWillExpandNotification, object: self, userInfo: info)
            NotificationCenter.default.post(will)
            _outlineDelegate?.outlineViewItemWillExpand(will)
            node.expanded = true
            _expandedKeys.insert(node.key)
            node.children = _loadChildren(of: node)
            _rowsDidChange()
            let did = Notification(name: NSOutlineView.itemDidExpandNotification, object: self, userInfo: info)
            NotificationCenter.default.post(did)
            _outlineDelegate?.outlineViewItemDidExpand(did)
            _saveExpandedItems()
        }
        if deep { for c in _children(of: node) { _expand(c, deep: true) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/collapseitem(_:)
    @MainActor open func collapseItem(_ item: Any?) { collapseItem(item, collapseChildren: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/collapseitem(_:collapsechildren:)
    @MainActor open func collapseItem(_ item: Any?, collapseChildren: Bool) {
        if item == nil {
            guard collapseChildren else { return }
            for n in _children(of: nil) { _collapse(n, deep: true) }
            return
        }
        guard let node = _node(for: item) else { return }
        _collapse(node, deep: collapseChildren)
    }
    private func _collapse(_ node: _Node, deep: Bool) {
        if deep { for c in node.children ?? [] { _collapse(c, deep: true) } }
        guard node.expanded else { return }
        guard _outlineDelegate?.outlineView(self, shouldCollapseItem: node.item) ?? true else { return }
        let info: [AnyHashable: Any] = ["NSObject": node.item]
        let will = Notification(name: NSOutlineView.itemWillCollapseNotification, object: self, userInfo: info)
        NotificationCenter.default.post(will)
        _outlineDelegate?.outlineViewItemWillCollapse(will)
        node.expanded = false
        _expandedKeys.remove(node.key)
        _rowsDidChange()
        let did = Notification(name: NSOutlineView.itemDidCollapseNotification, object: self, userInfo: info)
        NotificationCenter.default.post(did)
        _outlineDelegate?.outlineViewItemDidCollapse(did)
        _saveExpandedItems()
    }

    // MARK: Reloading and editing the tree

    /// Re-reads the whole tree; items still expanded stay expanded.
    @MainActor open override func reloadData() {
        _roots = _loadChildren(of: nil)
        _reloadDescendants(of: _roots ?? [])
        _rowsDirty = true
        _restoreExpandedItems()
        super.reloadData()
    }
    private func _reloadDescendants(of nodes: [_Node]) {
        for n in nodes where n.children != nil {
            n.children = _loadChildren(of: n)
            _reloadDescendants(of: n.children ?? [])
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/reloaditem(_:)
    @MainActor open func reloadItem(_ item: Any?) { reloadItem(item, reloadChildren: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/reloaditem(_:reloadchildren:)
    @MainActor open func reloadItem(_ item: Any?, reloadChildren: Bool) {
        guard let item else {
            if reloadChildren { reloadData() }
            return
        }
        guard let node = _node(for: item) else { return }
        if reloadChildren {
            if node.children != nil {
                node.children = _loadChildren(of: node)
                _reloadDescendants(of: node.children ?? [])
            }
            _rowsDidChange()
        }
        if node.row >= 0 { reloadData(forRowIndexes: IndexSet(integer: node.row), columnIndexes: IndexSet(0..<numberOfColumns)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/insertitems(at:inparent:withanimation:)
    @MainActor open func insertItems(at indexes: IndexSet, inParent parent: Any?, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        _childrenChanged(inParent: parent)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/removeitems(at:inparent:withanimation:)
    @MainActor open func removeItems(at indexes: IndexSet, inParent parent: Any?, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        _childrenChanged(inParent: parent)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/moveitem(at:inparent:to:inparent:)
    @MainActor open func moveItem(at fromIndex: Int, inParent oldParent: Any?, to toIndex: Int, inParent newParent: Any?) {
        let sameParent = (oldParent == nil && newParent == nil) || (_node(for: oldParent) != nil && _node(for: oldParent) === _node(for: newParent))
        _childrenChanged(inParent: oldParent)
        if !sameParent { _childrenChanged(inParent: newParent) }
    }
    /// The data source's children of `parent` changed: re-read them (nodes of items that
    /// stay keep their subtrees and expansion) and re-flatten.
    private func _childrenChanged(inParent parent: Any?) {
        if let parent {
            guard let node = _node(for: parent) else { return }
            if node.children != nil || node.expanded { node.children = _loadChildren(of: node) }
        } else {
            _roots = _loadChildren(of: nil)
        }
        _rowsDidChange()
    }

    // MARK: Autosave

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsoutlineview/autosaveexpandeditems
    @MainActor open var autosaveExpandedItems: Bool {
        get { _autosaveExpandedItems }
        set { _autosaveExpandedItems = newValue; if newValue { _restoreExpandedItems(); _rowsDidChange() } }
    }
    @MainActor open override var autosaveName: NSTableView.AutosaveName? {
        get { super.autosaveName }
        set { super.autosaveName = newValue; if _autosaveExpandedItems { _restoreExpandedItems(); _rowsDidChange() } }
    }
    private var _autosaveKey: String? { autosaveName.map { "NSOutlineView Items \($0)" } }

    private func _saveExpandedItems() {
        guard _autosaveExpandedItems, let key = _autosaveKey, let ds = _outlineDataSource else { return }
        var objects: [Any] = []
        func visit(_ nodes: [_Node]) {
            for n in nodes where n.expanded {
                if let o = ds.outlineView(self, persistentObjectForItem: n.item) { objects.append(o) }
                visit(n.children ?? [])
            }
        }
        visit(_roots ?? [])
        UserDefaults.standard.set(objects, forKey: key)
    }
    /// Marks the saved items expanded; they expand as their nodes load.
    private func _restoreExpandedItems() {
        guard _autosaveExpandedItems, let key = _autosaveKey, let ds = _outlineDataSource,
              let objects = UserDefaults.standard.array(forKey: key) else { return }
        for o in objects {
            if let item = ds.outlineView(self, itemForPersistentObject: o) { _expandedKeys.insert(_NSOutlineItemKey(item)) }
        }
        // Nodes already loaded (a reload with the tree in place) pick the state up now.
        func visit(_ nodes: [_Node]) {
            for n in nodes {
                if !n.expanded, _expandedKeys.contains(n.key), _isExpandable(n) { n.expanded = true }
                visit(n.children ?? [])
            }
        }
        visit(_roots ?? [])
        _rowsDirty = true
    }

    // MARK: Keyboard

    /// Left collapses the selected item (or selects its parent when it is collapsed),
    /// Right expands it; with Option the whole subtree. Mirrored right to left.
    @MainActor open override func keyDown(with event: NSEvent) {
        let row = selectedRow
        let deep = event.modifierFlags.contains(.option)
        let chars = event.charactersIgnoringModifiers ?? ""
        let isLeft = event.keyCode == 123 || chars == "\u{F702}"
        let isRight = event.keyCode == 124 || chars == "\u{F703}"
        guard row >= 0, isLeft || isRight, let item = item(atRow: row) else { super.keyDown(with: event); return }
        let expands = _isRightToLeft ? isLeft : isRight
        if expands {
            if isExpandable(item) { expandItem(item, expandChildren: deep) }
        } else if isItemExpanded(item) {
            collapseItem(item, collapseChildren: deep)
        } else if let parent = parent(forItem: item) {
            let parentRow = self.row(forItem: parent)
            if parentRow >= 0 { selectRowIndexes(IndexSet(integer: parentRow), byExtendingSelection: false); scrollRowToVisible(parentRow) }
        }
    }

    // MARK: Accessibility (ADR-0013)
    //
    // AXOutline whose rows are AXOutlineRow elements carrying their disclosure level and
    // expanded state; each expandable row's disclosure button is an AXDisclosureTriangle.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .outline }
}

/// A row of an outline: an outline row for accessibility, with its level and expansion.
@MainActor
final class _NSOutlineRowView: NSTableRowView {
    weak var _outline: NSOutlineView?
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { _a11y.subrole ?? .outlineRow }
    override func accessibilityDisclosureLevel() -> Int { _outline?.level(forRow: _row) ?? 0 }
    override func isAccessibilityExpanded() -> Bool { _accessibilityExpandedState() ?? false }
    override func setAccessibilityExpanded(_ accessibilityExpanded: Bool) {
        guard let o = _outline, let item = o.item(atRow: _row) else { return }
        if accessibilityExpanded { o.expandItem(item) } else { o.collapseItem(item) }
    }
    override func _accessibilityExpandedState() -> Bool? {
        guard let o = _outline, let item = o.item(atRow: _row), o.isExpandable(item) else { return nil }
        return o.isItemExpanded(item)
    }
}

/// The disclosure triangle of an outline row: points along the reading direction while
/// collapsed and down while expanded.
@MainActor
final class _NSOutlineDisclosureButton: NSButton {
    var _row = -1
    var isExpanded = false { didSet { needsDisplay = true } }
    var pointsLeft = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override var isFlipped: Bool { true }      // the triangle's geometry has +y downwards

    override func draw(_ dirtyRect: NSRect) {
        let emphasized = (superview as? NSTableRowView).map { $0.isSelected && $0.isEmphasized && $0.selectionHighlightStyle != .none } ?? false
        let color: NSColor = isEnabled ? (emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor) : .disabledControlTextColor
        color.setFill()
        NSOutlineView._disclosurePath(in: bounds, expanded: isExpanded, pointsLeft: pointsLeft).fill()
    }

    // AXDisclosureTriangle whose value is the expanded state; pressing it toggles.
    override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .disclosureTriangle }
    override func accessibilityLabel() -> String? { _a11y.label ?? (isExpanded ? "collapse" : "expand") }
    override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : (isExpanded ? 1 : 0) }
    override func _accessibilityExpandedState() -> Bool? { isExpanded }
    override func isAccessibilityExpanded() -> Bool { isExpanded }
    override func setAccessibilityExpanded(_ accessibilityExpanded: Bool) { if accessibilityExpanded != isExpanded { performClick(nil) } }
}

extension NSOutlineView {
    /// The triangle, 8 points tall, centred in `rect` (a flipped view: +y is down).
    static func _disclosurePath(in rect: NSRect, expanded: Bool, pointsLeft: Bool) -> NSBezierPath {
        let p = NSBezierPath()
        let cx = rect.midX, cy = rect.midY
        let half: CGFloat = 4, depth: CGFloat = 4
        if expanded {
            p.move(to: NSPoint(x: cx - half, y: cy - depth / 2))
            p.line(to: NSPoint(x: cx + half, y: cy - depth / 2))
            p.line(to: NSPoint(x: cx, y: cy + depth / 2))
        } else if pointsLeft {
            p.move(to: NSPoint(x: cx + depth / 2, y: cy - half))
            p.line(to: NSPoint(x: cx + depth / 2, y: cy + half))
            p.line(to: NSPoint(x: cx - depth / 2, y: cy))
        } else {
            p.move(to: NSPoint(x: cx - depth / 2, y: cy - half))
            p.line(to: NSPoint(x: cx - depth / 2, y: cy + half))
            p.line(to: NSPoint(x: cx + depth / 2, y: cy))
        }
        p.close()
        return p
    }
}
