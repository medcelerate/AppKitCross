// NSTableView (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A view-based table: the data source counts rows, the delegate provides a cell view per
// column and row (or the table makes a label cell from the data source's object value),
// and each visible row is an NSTableRowView holding its cells. Row views exist only for
// the rows in the visible rect and are made in `viewWillDraw`, as AppKit does; scrolling
// redraws the table, which recycles them. The header lives in the enclosing scroll view.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview
@MainActor open class NSTableView: NSControl, NSUserInterfaceValidations, NSTextViewDelegate, NSTextDelegate, NSDraggingSource, NSAccessibilityTable, NSAccessibilityGroup, NSSelectorHandling {
    // MARK: Storage
    private var _tableColumns: [NSTableColumn] = []
    private weak var _dataSource: (any NSTableViewDataSource)?
    private weak var _delegate: (any NSTableViewDelegate)?
    private var _headerView: NSTableHeaderView?
    private var _cornerView: NSView?
    private var _rowHeight: CGFloat = 17
    private var _rowSizeStyle: NSTableView.RowSizeStyle = .default
    private var _intercellSpacing = NSSize(width: 3, height: 2)
    private var _gridStyleMask: NSTableView.GridLineStyle = []
    private var _gridColor: NSColor = .gridColor
    private var _backgroundColor: NSColor = .controlBackgroundColor
    private var _usesAlternatingRowBackgroundColors = false
    private var _selectionHighlightStyle: NSTableView.SelectionHighlightStyle = .regular
    private var _style: NSTableView.Style = .automatic
    private var _allowsMultipleSelection = false
    private var _allowsEmptySelection = true
    private var _allowsColumnSelection = false
    private var _allowsColumnReordering = true
    private var _allowsColumnResizing = true
    private var _allowsTypeSelect = true
    private var _autosaveName: NSTableView.AutosaveName?
    private var _autosaveTableColumns = false
    private var _columnAutoresizingStyle: NSTableView.ColumnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    private var _doubleAction: Selector?
    private var _sortDescriptors: [NSSortDescriptor] = []
    private var _highlightedTableColumn: NSTableColumn?
    private var _indicatorImages: [ObjectIdentifier: NSImage] = [:]
    private var _floatsGroupRows = true
    private var _rowActionsVisible = false
    private var _usesAutomaticRowHeights = false
    private var _usesStaticContents = false
    private var _verticalMotionCanBeginDrag = true
    private var _draggingDestinationFeedbackStyle: NSTableView.DraggingDestinationFeedbackStyle = .regular
    private var _registeredNibs: [NSUserInterfaceItemIdentifier: NSNib] = [:]
    private var _focusedColumn = -1

    // Rows
    private var _numberOfRows = 0
    private var _rowHeights: [CGFloat] = []          // per row, after reloadData / noteHeightOfRows
    private var _rowOrigins: [CGFloat] = []          // prefix sums, count = rows + 1
    private var _rowViews: [Int: NSTableRowView] = [:]
    private var _spareRowViews: [NSTableRowView] = []
    private var _spareCellViews: [NSUserInterfaceItemIdentifier: [NSView]] = [:]
    private var _hiddenRows = IndexSet()
    private var _updateDepth = 0
    private var _needsReload = true

    // Selection
    private var _selectedRows = IndexSet()
    private var _selectedColumns = IndexSet()
    private var _anchorRow = -1
    private var _clickedRow = -1
    private var _clickedColumn = -1
    private var _editedRow = -1
    private var _editedColumn = -1
    private var _pressedRow = -1
    private var _pressPoint = NSPoint.zero
    private var _pressDidToggle = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/columndidmovenotification
    open class var columnDidMoveNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTableViewColumnDidMoveNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/columndidresizenotification
    open class var columnDidResizeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTableViewColumnDidResizeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectiondidchangenotification
    open class var selectionDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTableViewSelectionDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectionischangingnotification
    open class var selectionIsChangingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTableViewSelectionIsChangingNotification") }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let header = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: frameRect.width, height: NSTableHeaderView.defaultHeight))
        header._tableView = self
        _headerView = header
    }

    @MainActor open override var isFlipped: Bool { true }
    @MainActor open override var acceptsFirstResponder: Bool { isEnabled }
    @MainActor open override class func _makeDefaultCell() -> NSCell? { nil }

    // A table has no cell, so target and action live here.
    private weak var _target: AnyObject?
    private var _action: Selector?
    @MainActor open override var target: AnyObject? {
        get { _target }
        set { _target = newValue }
    }
    @MainActor open override var action: Selector? {
        get { _action }
        set { _action = newValue }
    }

    // MARK: Columns

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/addtablecolumn(_:)
    @MainActor open func addTableColumn(_ tableColumn: NSTableColumn) {
        tableColumn._tableView = self
        _tableColumns.append(tableColumn)
        _columnsDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/removetablecolumn(_:)
    @MainActor open func removeTableColumn(_ tableColumn: NSTableColumn) {
        _tableColumns.removeAll { $0 === tableColumn }
        tableColumn._tableView = nil
        _columnsDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/movecolumn(_:tocolumn:)
    @MainActor open func moveColumn(_ oldIndex: Int, toColumn newIndex: Int) {
        guard _tableColumns.indices.contains(oldIndex), _tableColumns.indices.contains(newIndex), oldIndex != newIndex else { return }
        let c = _tableColumns.remove(at: oldIndex)
        _tableColumns.insert(c, at: newIndex)
        _columnsDidChange()
        let n = Notification(name: type(of: self).columnDidMoveNotification, object: self, userInfo: ["NSOldColumn": oldIndex, "NSNewColumn": newIndex])
        NotificationCenter.default.post(n)
        _delegateColumnDidMove(n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/tablecolumns
    @MainActor open var tableColumns: [NSTableColumn] { _tableColumns }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/numberofcolumns
    @MainActor open var numberOfColumns: Int { _tableColumns.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/tablecolumn(withidentifier:)
    @MainActor open func tableColumn(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> NSTableColumn? { _tableColumns.first { $0.identifier == identifier } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/column(withidentifier:)
    @MainActor open func column(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> Int { _tableColumns.firstIndex { $0.identifier == identifier } ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/column(at:)
    @MainActor open func column(at point: NSPoint) -> Int {
        for i in _tableColumns.indices where !_tableColumns[i].isHidden {
            let r = rect(ofColumn: i)
            // The intercell gap belongs to the column before it (in reading order).
            let gap = _intercellSpacing.width
            let hit = _isRightToLeft ? (point.x >= r.minX - gap && point.x < r.maxX) : (point.x >= r.minX && point.x < r.maxX + gap)
            if hit { return i }
        }
        return -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/column(for:)
    @MainActor open func column(for view: NSView) -> Int {
        var v: NSView? = view
        while let cur = v, !(cur.superview is NSTableRowView) { v = cur.superview }
        guard let cell = v, let row = cell.superview as? NSTableRowView, let i = row._cellViews.firstIndex(where: { $0 === cell }) else { return -1 }
        // Cell views are ordered like the visible columns.
        let visible = _tableColumns.indices.filter { !_tableColumns[$0].isHidden }
        return visible.indices.contains(i) ? visible[i] : -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/columnindexes(in:)
    @MainActor open func columnIndexes(in rect: NSRect) -> IndexSet {
        var set = IndexSet()
        for i in _tableColumns.indices where !_tableColumns[i].isHidden && self.rect(ofColumn: i).intersects(rect) { set.insert(i) }
        return set
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/rect(ofcolumn:)
    @MainActor open func rect(ofColumn column: Int) -> NSRect {
        guard _tableColumns.indices.contains(column) else { return .zero }
        var x: CGFloat = 0
        for (i, c) in _tableColumns.enumerated() where !c.isHidden {
            if i == column {
                // Right to left: the first column sits at the right edge of the content width.
                let origin = _isRightToLeft ? max(bounds.width, _visibleColumnsWidth) - x - c.width : x
                return NSRect(x: origin, y: 0, width: c.width, height: max(bounds.height, _totalRowHeight))
            }
            x += c.width + _intercellSpacing.width
        }
        return .zero
    }
    internal var _isRightToLeft: Bool { userInterfaceLayoutDirection == .rightToLeft }
    /// The x of the gap after `column` in reading order (its trailing separator).
    internal func _trailingGapX(ofColumn column: Int) -> CGFloat {
        let c = rect(ofColumn: column)
        return _isRightToLeft ? c.minX - _intercellSpacing.width : c.maxX
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/allowscolumnreordering
    @MainActor open var allowsColumnReordering: Bool {
        get { _allowsColumnReordering }
        set { _allowsColumnReordering = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/allowscolumnresizing
    @MainActor open var allowsColumnResizing: Bool {
        get { _allowsColumnResizing }
        set { _allowsColumnResizing = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/allowscolumnselection
    @MainActor open var allowsColumnSelection: Bool {
        get { _allowsColumnSelection }
        set { _allowsColumnSelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/columnautoresizingstyle
    @MainActor open var columnAutoresizingStyle: NSTableView.ColumnAutoresizingStyle {
        get { _columnAutoresizingStyle }
        set { _columnAutoresizingStyle = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/sizelastcolumntofit()
    @MainActor open func sizeLastColumnToFit() {
        guard let last = _tableColumns.last(where: { !$0.isHidden }) else { return }
        let others = _visibleColumnsWidth - last.width
        last._setWidthQuietly(max(last.minWidth, (_availableWidth ?? frame.width) - others))
        _columnsDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/sizetofit()
    @MainActor open override func sizeToFit() {
        for c in _tableColumns { c.sizeToFit() }
        tile()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/highlightedtablecolumn
    @MainActor open var highlightedTableColumn: NSTableColumn? {
        get { _highlightedTableColumn }
        set { _highlightedTableColumn = newValue; _headerView?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/indicatorimage(in:)
    @MainActor open func indicatorImage(in tableColumn: NSTableColumn) -> NSImage? { _indicatorImages[ObjectIdentifier(tableColumn)] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/setindicatorimage(_:in:)
    @MainActor open func setIndicatorImage(_ image: NSImage?, in tableColumn: NSTableColumn) {
        _indicatorImages[ObjectIdentifier(tableColumn)] = image
        _headerView?.needsDisplay = true
    }

    /// Column widths summed with their spacing.
    private var _visibleColumnsWidth: CGFloat {
        let visible = _tableColumns.filter { !$0.isHidden }
        return visible.reduce(0) { $0 + $1.width } + CGFloat(max(0, visible.count - 1)) * _intercellSpacing.width
    }
    /// The width the columns should fill: the clip view's. Outside a scroll view the
    /// columns keep their widths and the frame follows them.
    private var _availableWidth: CGFloat? {
        (superview as? NSClipView)?.bounds.width
    }

    internal func _columnsDidChange() {
        tile()
        _dropAllRowViews()
        needsDisplay = true
        _headerView?.needsDisplay = true
    }

    internal func _columnDidResize(_ column: NSTableColumn) {
        tile()
        _layoutRowViews()
        needsDisplay = true
        _headerView?.needsDisplay = true
        let n = Notification(name: type(of: self).columnDidResizeNotification, object: self, userInfo: ["NSTableColumn": column])
        NotificationCenter.default.post(n)
        _delegateColumnDidResize(n)
    }

    /// A click on a column header: sorts by the column's prototype (toggling direction when
    /// it already leads), then tells the delegate.
    internal func _headerClicked(column: Int) {
        guard _tableColumns.indices.contains(column) else { return }
        let c = _tableColumns[column]
        if let proto = c.sortDescriptorPrototype, let identity = proto._sortIdentity {
            var ascending = proto.ascending
            if let first = _sortDescriptors.first, first._sortIdentity == identity { ascending = !first.ascending }
            sortDescriptors = [proto._with(ascending: ascending)] + _sortDescriptors.filter { $0._sortIdentity != identity }
            highlightedTableColumn = c
        }
        _clickedColumn = column
        _delegateDidClick(column: c)
    }

    // MARK: Subclass hooks
    //
    // NSOutlineView maps its tree onto the row model through these: every data source and
    // delegate call that depends on the row model goes through one, so the outline view can
    // answer from its flattened rows and its own protocols without forking the table.

    internal func _rowCountFromDataSource() -> Int { max(0, _dataSource?.numberOfRows(in: self) ?? 0) }
    internal func _delegateHeightOfRow(_ row: Int) -> CGFloat { _delegate?.tableView(self, heightOfRow: row) ?? _rowHeight }
    internal func _delegateView(for column: NSTableColumn, row: Int) -> NSView? { _delegate?.tableView(self, viewFor: column, row: row) }
    internal func _objectValue(for column: NSTableColumn?, row: Int) -> Any? { _dataSource?.tableView(self, objectValueFor: column, row: row) }
    internal func _delegateRowView(forRow row: Int) -> NSTableRowView? { _delegate?.tableView(self, rowViewForRow: row) }
    internal func _delegateIsGroupRow(_ row: Int) -> Bool { _delegate?.tableView(self, isGroupRow: row) ?? false }
    internal func _delegateDidAdd(_ rowView: NSTableRowView, row: Int) { _delegate?.tableView(self, didAdd: rowView, forRow: row) }
    internal func _delegateDidRemove(_ rowView: NSTableRowView, row: Int) { _delegate?.tableView(self, didRemove: rowView, forRow: row) }
    internal func _delegateSelectionShouldChange() -> Bool { _delegate?.selectionShouldChange(in: self) ?? true }
    internal func _delegateSelectionIndexes(forProposed rows: IndexSet) -> IndexSet { _delegate?.tableView(self, selectionIndexesForProposedSelection: rows) ?? rows }
    internal func _delegateShouldSelectRow(_ row: Int) -> Bool { _delegate?.tableView(self, shouldSelectRow: row) ?? true }
    internal func _delegateSelectionDidChange(_ notification: Notification) { _delegate?.tableViewSelectionDidChange(notification) }
    internal func _delegateDidClick(column: NSTableColumn) { _delegate?.tableView(self, didClick: column) }
    internal func _delegateColumnDidMove(_ notification: Notification) { _delegate?.tableViewColumnDidMove(notification) }
    internal func _delegateColumnDidResize(_ notification: Notification) { _delegate?.tableViewColumnDidResize(notification) }
    internal func _dataSourceSortDescriptorsDidChange(_ old: [NSSortDescriptor]) { _dataSource?.tableView(self, sortDescriptorsDidChange: old) }
    internal func _delegateDataCell(for column: NSTableColumn, row: Int) -> NSCell? { _delegate?.tableView(self, dataCellFor: column, row: row) }
    internal func _delegateWillDisplayCell(_ cell: NSCell, for column: NSTableColumn, row: Int) { _delegate?.tableView(self, willDisplayCell: cell, for: column, row: row) }
    /// The frame of each visible column's cell inside a row view of `height`.
    internal func _cellFrames(forRow row: Int, height: CGFloat) -> [(column: Int, frame: NSRect)] {
        _tableColumns.indices.filter { !_tableColumns[$0].isHidden }.map { i in
            let cf = rect(ofColumn: i)
            return (i, NSRect(x: cf.minX, y: 0, width: cf.width, height: height))
        }
    }
    /// The row view has its cells (made or re-laid out); an outline adds its disclosure button.
    internal func _rowViewDidLayout(_ rowView: NSTableRowView, row: Int) { }
    /// The mouse moved far enough from the press on `row` to start a drag: a subclass that
    /// drags rows starts the session and returns true. The table itself extends the selection.
    internal func _beginRowDrag(with event: NSEvent, row: Int) -> Bool { false }

    // MARK: Rows

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/datasource
    @MainActor open var dataSource: (any NSTableViewDataSource)? {
        get { _dataSource }
        set { _dataSource = newValue; _needsReload = true; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/delegate
    @MainActor open var delegate: (any NSTableViewDelegate)? {
        get { _delegate }
        set { _delegate = newValue; _needsReload = true; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/numberofrows
    @MainActor open var numberOfRows: Int { _reloadIfNeeded(); return _numberOfRows }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/rowheight
    @MainActor open var rowHeight: CGFloat {
        get { _rowHeight }
        set { _rowHeight = max(1, newValue); _needsReload = true; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/rowsizestyle
    @MainActor open var rowSizeStyle: NSTableView.RowSizeStyle {
        get { _rowSizeStyle }
        set { _rowSizeStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/effectiverowsizestyle
    @MainActor open var effectiveRowSizeStyle: NSTableView.RowSizeStyle { _rowSizeStyle == .default ? .medium : _rowSizeStyle }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/intercellspacing
    @MainActor open var intercellSpacing: NSSize {
        get { _intercellSpacing }
        set { _intercellSpacing = newValue; _needsReload = true; needsDisplay = true; _headerView?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/usesautomaticrowheights
    @MainActor open var usesAutomaticRowHeights: Bool {
        get { _usesAutomaticRowHeights }
        set { _usesAutomaticRowHeights = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/usesstaticcontents
    @MainActor open var usesStaticContents: Bool {
        get { _usesStaticContents }
        set { _usesStaticContents = newValue }
    }

    private var _totalRowHeight: CGFloat { _rowOrigins.last ?? 0 }

    /// Re-reads the row count and heights from the data source and delegate.
    private func _reloadIfNeeded() {
        guard _needsReload else { return }
        _needsReload = false
        _numberOfRows = _rowCountFromDataSource()
        _rowHeights = (0..<_numberOfRows).map { row in
            if _hiddenRows.contains(row) { return 0 }
            return max(1, _delegateHeightOfRow(row))
        }
        var origins: [CGFloat] = [0]
        origins.reserveCapacity(_numberOfRows + 1)
        for (i, h) in _rowHeights.enumerated() { origins.append(origins[i] + h + (h > 0 ? _intercellSpacing.height : 0)) }
        _rowOrigins = origins
        _selectedRows = IndexSet(_selectedRows.filter { $0 < _numberOfRows })
        tile()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/reloaddata()
    @MainActor open func reloadData() {
        _needsReload = true
        _dropAllRowViews()
        _reloadIfNeeded()
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/reloaddata(forrowindexes:columnindexes:)
    @MainActor open func reloadData(forRowIndexes rowIndexes: IndexSet, columnIndexes: IndexSet) {
        for row in rowIndexes { if let v = _rowViews[row] { _recycle(v, row: row) } }
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/notenumberofrowschanged()
    @MainActor open func noteNumberOfRowsChanged() {
        let selected = _selectedRows
        _needsReload = true
        _dropAllRowViews()
        _reloadIfNeeded()
        _selectedRows = IndexSet(selected.filter { $0 < _numberOfRows })
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/noteheightofrows(withindexeschanged:)
    @MainActor open func noteHeightOfRows(withIndexesChanged indexSet: IndexSet) {
        _needsReload = true
        _reloadIfNeeded()
        _layoutRowViews()
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/beginupdates()
    @MainActor open func beginUpdates() { _updateDepth += 1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/endupdates()
    @MainActor open func endUpdates() {
        _updateDepth = max(0, _updateDepth - 1)
        if _updateDepth == 0 { noteNumberOfRowsChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/insertrows(at:withanimation:)
    @MainActor open func insertRows(at indexes: IndexSet, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        // Selection follows the rows below the insertion points.
        var selected = IndexSet()
        for row in _selectedRows { selected.insert(row + indexes.count(in: 0...row)) }
        _selectedRows = selected
        if _updateDepth == 0 { noteNumberOfRowsChanged() } else { _needsReload = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/removerows(at:withanimation:)
    @MainActor open func removeRows(at indexes: IndexSet, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        var selected = IndexSet()
        for row in _selectedRows where !indexes.contains(row) { selected.insert(row - indexes.count(in: 0..<row)) }
        _selectedRows = selected
        if _updateDepth == 0 { noteNumberOfRowsChanged() } else { _needsReload = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/moverow(at:to:)
    @MainActor open func moveRow(at oldIndex: Int, to newIndex: Int) {
        let wasSelected = _selectedRows.contains(oldIndex)
        var selected = IndexSet()
        for row in _selectedRows where row != oldIndex {
            var r = row
            if r > oldIndex { r -= 1 }
            if r >= newIndex { r += 1 }
            selected.insert(r)
        }
        if wasSelected { selected.insert(newIndex) }
        _selectedRows = selected
        if _updateDepth == 0 { noteNumberOfRowsChanged() } else { _needsReload = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/hiddenrowindexes
    @MainActor open var hiddenRowIndexes: IndexSet { _hiddenRows }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/hiderows(at:withanimation:)
    @MainActor open func hideRows(at indexes: IndexSet, withAnimation rowAnimation: NSTableView.AnimationOptions = []) {
        _hiddenRows.formUnion(indexes)
        noteHeightOfRows(withIndexesChanged: indexes)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/unhiderows(at:withanimation:)
    @MainActor open func unhideRows(at indexes: IndexSet, withAnimation rowAnimation: NSTableView.AnimationOptions = []) {
        _hiddenRows.subtract(indexes)
        noteHeightOfRows(withIndexesChanged: indexes)
    }

    // MARK: Geometry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/rect(ofrow:)
    @MainActor open func rect(ofRow row: Int) -> NSRect {
        _reloadIfNeeded()
        guard row >= 0, row < _numberOfRows else { return .zero }
        return NSRect(x: 0, y: _rowOrigins[row], width: max(bounds.width, _visibleColumnsWidth), height: _rowHeights[row])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/row(at:)
    @MainActor open func row(at point: NSPoint) -> Int {
        _reloadIfNeeded()
        guard _numberOfRows > 0, point.y >= 0, point.y < _totalRowHeight else { return -1 }
        // Binary search over the row origins.
        var lo = 0, hi = _numberOfRows - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if _rowOrigins[mid] <= point.y { lo = mid } else { hi = mid - 1 }
        }
        return _rowHeights[lo] > 0 && point.y < _rowOrigins[lo] + _rowHeights[lo] ? lo : (point.y < _rowOrigins[lo + 1] ? lo : -1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/row(for:)
    @MainActor open func row(for view: NSView) -> Int {
        var v: NSView? = view
        while let cur = v, !(cur is NSTableRowView) { v = cur.superview }
        return (v as? NSTableRowView)?._row ?? -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/rows(in:)
    @MainActor open func rows(in rect: NSRect) -> NSRange {
        _reloadIfNeeded()
        guard _numberOfRows > 0, rect.maxY > 0 else { return NSRange(location: 0, length: 0) }
        var first = row(at: NSPoint(x: 0, y: max(0, rect.minY)))
        if first < 0 { first = _numberOfRows > 0 && rect.minY < _totalRowHeight ? 0 : _numberOfRows }
        if first >= _numberOfRows { return NSRange(location: _numberOfRows, length: 0) }
        var last = row(at: NSPoint(x: 0, y: rect.maxY - 0.01))
        if last < 0 { last = rect.maxY >= _totalRowHeight ? _numberOfRows - 1 : first }
        return NSRange(location: first, length: max(0, last - first + 1))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/frameofcell(atcolumn:row:)
    @MainActor open func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let c = rect(ofColumn: column), r = rect(ofRow: row)
        guard !c.isEmpty, !r.isEmpty else { return .zero }
        return NSRect(x: c.minX, y: r.minY, width: c.width, height: r.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/scrollrowtovisible(_:)
    @MainActor open func scrollRowToVisible(_ row: Int) {
        let r = rect(ofRow: row)
        guard !r.isEmpty else { return }
        _ = scrollToVisible(NSRect(x: visibleRect.minX, y: r.minY, width: 1, height: r.height))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/scrollcolumntovisible(_:)
    @MainActor open func scrollColumnToVisible(_ column: Int) {
        let c = rect(ofColumn: column)
        guard !c.isEmpty else { return }
        _ = scrollToVisible(NSRect(x: c.minX, y: visibleRect.minY, width: c.width, height: 1))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/tile()
    /// Sizes the columns to the autoresizing style and the frame to the rows and columns.
    @MainActor open func tile() {
        let visible = _tableColumns.filter { !$0.isHidden }
        if !visible.isEmpty, let available = _availableWidth, available > 0 {
            let spacing = CGFloat(max(0, visible.count - 1)) * _intercellSpacing.width
            switch _columnAutoresizingStyle {
            case .lastColumnOnlyAutoresizingStyle:
                let others = visible.dropLast().reduce(0) { $0 + $1.width }
                visible.last!._setWidthQuietly(available - spacing - others)
            case .firstColumnOnlyAutoresizingStyle:
                let others = visible.dropFirst().reduce(0) { $0 + $1.width }
                visible.first!._setWidthQuietly(available - spacing - others)
            case .uniformColumnAutoresizingStyle, .sequentialColumnAutoresizingStyle, .reverseSequentialColumnAutoresizingStyle:
                // Columns that autoresize share what the fixed ones leave, in proportion.
                let flexible = visible.filter { $0.resizingMask.contains(.autoresizingMask) }
                let fixed = visible.filter { !$0.resizingMask.contains(.autoresizingMask) }.reduce(0) { $0 + $1.width }
                let total = flexible.reduce(0) { $0 + $1.width }
                guard total > 0 else { break }
                let target = max(0, available - spacing - fixed)
                for c in flexible { c._setWidthQuietly(c.width * target / total) }
            case .noColumnAutoresizing:
                break
            }
        }
        let size = NSSize(width: max(_availableWidth ?? 0, _visibleColumnsWidth), height: max(_totalRowHeight, superview is NSClipView ? (superview?.bounds.height ?? 0) : frame.height))
        if frame.size != size { setFrameSize(size) }
        _headerView?.needsDisplay = true
    }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged && !(superview is NSClipView) { tile() }
    }

    @MainActor open override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        tile()
    }

    private var _keyObservers: [Any] = []
    @MainActor open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for o in _keyObservers { NotificationCenter.default.removeObserver(o) }
        _keyObservers.removeAll()
        guard let w = window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            _keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?._windowKeyStateChanged() }
            })
        }
    }

    /// The enclosing scroll view's width changed: refit the columns.
    internal func _clipViewDidResize() { tile(); _layoutRowViews() }

    // MARK: Views

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/makeview(withidentifier:owner:)
    @MainActor open func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        if var spare = _spareCellViews[identifier], let v = spare.popLast() {
            _spareCellViews[identifier] = spare
            return v
        }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/register(_:foridentifier:)
    @MainActor open func register(_ nib: NSNib?, forIdentifier identifier: NSUserInterfaceItemIdentifier) {
        _registeredNibs[identifier] = nib
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/registerednibsbyidentifier
    @MainActor open var registeredNibsByIdentifier: [NSUserInterfaceItemIdentifier : NSNib]? { _registeredNibs }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/rowview(atrow:makeifnecessary:)
    @MainActor open func rowView(atRow row: Int, makeIfNecessary: Bool) -> NSTableRowView? {
        if let v = _rowViews[row] { return v }
        guard makeIfNecessary, row >= 0, row < numberOfRows else { return nil }
        return _makeRowView(row)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/view(atcolumn:row:makeifnecessary:)
    @MainActor open func view(atColumn column: Int, row: Int, makeIfNecessary: Bool) -> NSView? {
        guard let rv = rowView(atRow: row, makeIfNecessary: makeIfNecessary) else { return nil }
        let visible = _tableColumns.indices.filter { !_tableColumns[$0].isHidden }
        guard let i = visible.firstIndex(of: column), rv._cellViews.indices.contains(i) else { return nil }
        return rv._cellViews[i]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/enumerateavailablerowviews(_:)
    @MainActor open func enumerateAvailableRowViews(_ handler: (NSTableRowView, Int) -> Void) {
        for (row, v) in _rowViews.sorted(by: { $0.key < $1.key }) { handler(v, row) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/didadd(_:forrow:)
    @MainActor open func didAdd(_ rowView: NSTableRowView, forRow row: Int) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/didremove(_:forrow:)
    @MainActor open func didRemove(_ rowView: NSTableRowView, forRow row: Int) { }

    /// The cell view for one column of a row: the delegate's, or a label over the data
    /// source's object value.
    private func _makeCellView(column: Int, row: Int, frame: NSRect) -> NSView {
        let c = _tableColumns[column]
        if let v = _delegateView(for: c, row: row) {
            v.frame = frame
            return v
        }
        let value = _objectValue(for: c, row: row)
        let id = NSUserInterfaceItemIdentifier("AppKitCross.TextCell")
        let cell = (makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? NSTableCellView._makeLabelCell(frame: frame)
        cell.frame = frame
        cell.objectValue = value
        if let s = value as? String { cell.textField?.stringValue = s }
        else if let v = value { cell.textField?.stringValue = String(describing: v) }
        else { cell.textField?.stringValue = "" }
        if let dataCell = c.dataCell as? NSTextFieldCell, let f = cell.textField {
            f.alignment = dataCell.alignment
            if let font = dataCell.font { f.font = font }
        }
        return cell
    }

    private func _makeRowView(_ row: Int) -> NSTableRowView {
        let r = rect(ofRow: row)
        let rv = _delegateRowView(forRow: row) ?? _spareRowViews.popLast() ?? NSTableRowView(frame: r)
        rv.frame = r
        rv._row = row
        rv._insetStyle = effectiveStyle == .inset
        rv.selectionHighlightStyle = _selectionHighlightStyle
        rv.isGroupRowStyle = _delegateIsGroupRow(row)
        for v in rv.subviews { v.removeFromSuperview() }
        rv._cellViews = []
        for (i, frame) in _cellFrames(forRow: row, height: r.height) {
            let cell = _makeCellView(column: i, row: row, frame: frame)
            rv._cellViews.append(cell)
            rv.addSubview(cell)
        }
        _rowViewDidLayout(rv, row: row)
        _applyRowState(rv, row: row)
        _rowViews[row] = rv
        addSubview(rv)
        _delegateDidAdd(rv, row: row)
        didAdd(rv, forRow: row)
        return rv
    }

    private func _recycle(_ rv: NSTableRowView, row: Int) {
        _rowViews[row] = nil
        _delegateDidRemove(rv, row: row)
        didRemove(rv, forRow: row)
        for v in rv.subviews {
            v.removeFromSuperview()
            if rv._cellViews.contains(where: { $0 === v }), let id = v.identifier { _spareCellViews[id, default: []].append(v) }
        }
        rv._cellViews = []
        rv.removeFromSuperview()
        rv._row = -1
        rv.isSelected = false
        if _spareRowViews.count < 16 { _spareRowViews.append(rv) }
    }

    private func _dropAllRowViews() {
        for (row, v) in _rowViews { _recycle(v, row: row) }
        _rowViews.removeAll()
    }

    private func _applyRowState(_ rv: NSTableRowView, row: Int) {
        rv.isEmphasized = _isEmphasized
        rv.isSelected = _selectedRows.contains(row)
        rv.isPreviousRowSelected = row > 0 && _selectedRows.contains(row - 1)
        rv.isNextRowSelected = _selectedRows.contains(row + 1)
        if _usesAlternatingRowBackgroundColors {
            let colors = NSColor.alternatingContentBackgroundColors
            rv.backgroundColor = colors[row % max(1, colors.count)]
        } else {
            rv.backgroundColor = .clear
        }
    }

    private var _isEmphasized: Bool {
        guard let w = window else { return false }
        return w.isKeyWindow && w.firstResponder === self
    }

    /// Moves the live row views to their rects (after a resize or a height change).
    private func _layoutRowViews() {
        for (row, rv) in _rowViews {
            let r = rect(ofRow: row)
            rv.frame = r
            let frames = _cellFrames(forRow: row, height: r.height)
            for (i, cell) in rv._cellViews.enumerated() where frames.indices.contains(i) { cell.frame = frames[i].frame }
            _rowViewDidLayout(rv, row: row)
        }
    }

    /// Makes row views for the visible rows and recycles the rest.
    private var _updatingVisibleRows = false
    private func _updateVisibleRows() {
        guard !_updatingVisibleRows else { return }
        _updatingVisibleRows = true
        defer { _updatingVisibleRows = false }
        _reloadIfNeeded()
        let visible = visibleRect
        let range = rows(in: visible.isEmpty ? bounds : visible)
        let wanted = range.length > 0 ? Set(range.location..<(range.location + range.length)) : Set<Int>()
        for (row, v) in _rowViews where !wanted.contains(row) || row >= _numberOfRows { _recycle(v, row: row) }
        for row in wanted.sorted() where _rowViews[row] == nil && _rowHeights[row] > 0 { _ = _makeRowView(row) }
    }

    @MainActor open override func viewWillDraw() {
        super.viewWillDraw()
        _updateVisibleRows()
    }

    // MARK: Drawing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/usesalternatingrowbackgroundcolors
    @MainActor open var usesAlternatingRowBackgroundColors: Bool {
        get { _usesAlternatingRowBackgroundColors }
        set { _usesAlternatingRowBackgroundColors = newValue; for (row, v) in _rowViews { _applyRowState(v, row: row) }; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/gridcolor
    @MainActor open var gridColor: NSColor {
        get { _gridColor }
        set { _gridColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/gridstylemask
    @MainActor open var gridStyleMask: NSTableView.GridLineStyle {
        get { _gridStyleMask }
        set { _gridStyleMask = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectionhighlightstyle
    @MainActor open var selectionHighlightStyle: NSTableView.SelectionHighlightStyle {
        get { _selectionHighlightStyle }
        set { _selectionHighlightStyle = newValue; for v in _rowViews.values { v.selectionHighlightStyle = newValue }; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/style
    @MainActor open var style: NSTableView.Style {
        get { _style }
        set { _style = newValue; _dropAllRowViews(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/effectivestyle
    @MainActor open var effectiveStyle: NSTableView.Style { _style == .automatic ? .fullWidth : _style }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/drawbackground(incliprect:)
    @MainActor open func drawBackground(inClipRect clipRect: NSRect) {
        _backgroundColor.setFill()
        NSBezierPath(rect: clipRect).fill()
        guard _usesAlternatingRowBackgroundColors else { return }
        // Stripes continue below the last row, as in AppKit.
        let colors = NSColor.alternatingContentBackgroundColors
        guard colors.count > 1 else { return }
        var y = _totalRowHeight
        var index = _numberOfRows
        let step = _rowHeight + _intercellSpacing.height
        while y < clipRect.maxY {
            if y + step > clipRect.minY {
                colors[index % colors.count].setFill()
                NSBezierPath(rect: NSRect(x: clipRect.minX, y: y, width: clipRect.width, height: step)).fill()
            }
            y += step
            index += 1
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/drawgrid(incliprect:)
    @MainActor open func drawGrid(inClipRect clipRect: NSRect) {
        guard !_gridStyleMask.isEmpty else { return }
        _gridColor.setFill()
        if _gridStyleMask.contains(.solidHorizontalGridLineMask) || _gridStyleMask.contains(.dashedHorizontalGridLineMask) {
            let range = rows(in: clipRect)
            for row in range.location..<(range.location + range.length) {
                let r = rect(ofRow: row)
                NSBezierPath(rect: NSRect(x: clipRect.minX, y: r.maxY + _intercellSpacing.height - 1, width: clipRect.width, height: 1)).fill()
            }
        }
        if _gridStyleMask.contains(.solidVerticalGridLineMask) {
            for i in _tableColumns.indices where !_tableColumns[i].isHidden {
                NSBezierPath(rect: NSRect(x: _trailingGapX(ofColumn: i) + _intercellSpacing.width - 1, y: clipRect.minY, width: 1, height: clipRect.height)).fill()
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/drawrow(_:cliprect:)
    @MainActor open func drawRow(_ row: Int, clipRect: NSRect) { }   // rows are views
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/highlightselection(incliprect:)
    @MainActor open func highlightSelection(inClipRect clipRect: NSRect) { }   // drawn by the row views

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        drawBackground(inClipRect: dirtyRect)
        drawGrid(inClipRect: dirtyRect)
    }

    // MARK: Selection

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/allowsemptyselection
    @MainActor open var allowsEmptySelection: Bool {
        get { _allowsEmptySelection }
        set { _allowsEmptySelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/allowsmultipleselection
    @MainActor open var allowsMultipleSelection: Bool {
        get { _allowsMultipleSelection }
        set { _allowsMultipleSelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/allowstypeselect
    @MainActor open var allowsTypeSelect: Bool {
        get { _allowsTypeSelect }
        set { _allowsTypeSelect = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectedrow
    @MainActor open var selectedRow: Int { _selectedRows.last ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectedrowindexes
    @MainActor open var selectedRowIndexes: IndexSet { _selectedRows }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/numberofselectedrows
    @MainActor open var numberOfSelectedRows: Int { _selectedRows.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/isrowselected(_:)
    @MainActor open func isRowSelected(_ row: Int) -> Bool { _selectedRows.contains(row) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectedcolumn
    @MainActor open var selectedColumn: Int { _selectedColumns.last ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectedcolumnindexes
    @MainActor open var selectedColumnIndexes: IndexSet { _selectedColumns }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/numberofselectedcolumns
    @MainActor open var numberOfSelectedColumns: Int { _selectedColumns.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/iscolumnselected(_:)
    @MainActor open func isColumnSelected(_ column: Int) -> Bool { _selectedColumns.contains(column) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectrowindexes(_:byextendingselection:)
    @MainActor open func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        _reloadIfNeeded()
        var proposed = extend ? _selectedRows.union(indexes) : indexes
        proposed = IndexSet(proposed.filter { $0 >= 0 && $0 < _numberOfRows })
        if !_allowsMultipleSelection, proposed.count > 1, let last = indexes.last { proposed = [last] }
        if proposed.isEmpty && !_allowsEmptySelection && !_selectedRows.isEmpty { return }
        _applySelection(proposed, notify: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/deselectrow(_:)
    @MainActor open func deselectRow(_ row: Int) {
        guard _selectedRows.contains(row) else { return }
        var s = _selectedRows
        s.remove(row)
        if s.isEmpty && !_allowsEmptySelection { return }
        _applySelection(s, notify: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/deselectall(_:)
    @MainActor open func deselectAll(_ sender: Any?) {
        guard _allowsEmptySelection else { return }
        _applySelection([], notify: true)
        if !_selectedColumns.isEmpty { _selectedColumns = []; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectall(_:)
    @MainActor open func selectAll(_ sender: Any?) {
        _reloadIfNeeded()
        guard _allowsMultipleSelection, _numberOfRows > 0 else { return }
        _applySelection(IndexSet(0..<_numberOfRows), notify: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/selectcolumnindexes(_:byextendingselection:)
    @MainActor open func selectColumnIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        guard _allowsColumnSelection else { return }
        _selectedColumns = extend ? _selectedColumns.union(indexes) : indexes
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/deselectcolumn(_:)
    @MainActor open func deselectColumn(_ column: Int) { _selectedColumns.remove(column); needsDisplay = true }

    /// Sets the selection after asking the delegate, updates the row views and notifies.
    private func _applySelection(_ proposed: IndexSet, notify: Bool) {
        var rows = proposed
        guard _delegateSelectionShouldChange() else { return }
        rows = _delegateSelectionIndexes(forProposed: rows)
        rows = IndexSet(rows.filter { _delegateShouldSelectRow($0) })
        guard rows != _selectedRows else { return }
        _selectedRows = rows
        for (row, v) in _rowViews { _applyRowState(v, row: row) }
        needsDisplay = true
        guard notify else { return }
        let n = Notification(name: type(of: self).selectionDidChangeNotification, object: self)
        NotificationCenter.default.post(n)
        _delegateSelectionDidChange(n)
        _accessibilityNotify(.selection(_accessibilityElementID))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/clickedcolumn
    @MainActor open var clickedColumn: Int { _clickedColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/clickedrow
    @MainActor open var clickedRow: Int { _clickedRow }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/doubleaction
    @MainActor open var doubleAction: Selector? {
        get { _doubleAction }
        set { _doubleAction = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/editedcolumn
    @MainActor open var editedColumn: Int { _editedColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/editedrow
    @MainActor open var editedRow: Int { _editedRow }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/editcolumn(_:row:with:select:)
    @MainActor open func editColumn(_ column: Int, row: Int, with event: NSEvent?, select: Bool) {
        guard let cell = view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView, let f = cell.textField, f.isEditable else { return }
        _editedColumn = column
        _editedRow = row
        window?.makeFirstResponder(f)
        if select { f.selectText(nil) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/performclickoncell(atcolumn:row:)
    @MainActor open func performClickOnCell(atColumn column: Int, row: Int) {
        _clickedRow = row
        _clickedColumn = column
        _fireAction()
    }

    // MARK: Mouse and keyboard

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if acceptsFirstResponder, window?.firstResponder !== self { window?.makeFirstResponder(self) }
        let p = convert(event.locationInWindow, from: nil)
        let row = self.row(at: p)
        _clickedRow = row
        _clickedColumn = column(at: p)
        _pressDidToggle = false
        if event.clickCount == 2 {
            if let d = _doubleAction, let target = target { _ = sendAction(d, to: target) }
            else if _doubleAction != nil { _ = NSApplication.shared.sendAction(_doubleAction!, to: nil, from: self) }
            return
        }
        guard row >= 0 else {
            if _allowsEmptySelection { _applySelection([], notify: true) }
            return
        }
        _pressedRow = row
        _pressPoint = p
        let flags = event.modifierFlags
        if _allowsMultipleSelection && flags.contains(.command) {
            var s = _selectedRows
            if s.contains(row) { s.remove(row) } else { s.insert(row) }
            if s.isEmpty && !_allowsEmptySelection { return }
            _anchorRow = row
            _pressDidToggle = true
            _applySelection(s, notify: true)
        } else if _allowsMultipleSelection && flags.contains(.shift) && _anchorRow >= 0 {
            let lo = min(_anchorRow, row), hi = max(_anchorRow, row)
            _applySelection(_selectedRows.union(IndexSet(lo...hi)), notify: true)
        } else {
            _anchorRow = row
            if !_selectedRows.contains(row) || _selectedRows.count > 1 { _applySelection([row], notify: true) }
        }
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _pressedRow >= 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        if abs(p.x - _pressPoint.x) > 3 || abs(p.y - _pressPoint.y) > 3, _beginRowDrag(with: event, row: _pressedRow) {
            _pressedRow = -1
            return
        }
        guard _allowsMultipleSelection, !_pressDidToggle else { return }
        let row = self.row(at: p)
        guard row >= 0, row != _pressedRow || _selectedRows.count > 1 else { return }
        let lo = min(_pressedRow, row), hi = max(_pressedRow, row)
        _applySelection(IndexSet(lo...hi), notify: true)
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        let row = _pressedRow
        _pressedRow = -1
        guard row >= 0 else { return }
        _fireAction()
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        _reloadIfNeeded()
        guard _numberOfRows > 0 else { super.keyDown(with: event); return }
        let shift = event.modifierFlags.contains(.shift) && _allowsMultipleSelection
        func move(to target: Int) {
            let row = min(max(target, 0), _numberOfRows - 1)
            if shift, _anchorRow >= 0 {
                let lo = min(_anchorRow, row), hi = max(_anchorRow, row)
                _applySelection(IndexSet(lo...hi), notify: true)
            } else {
                _anchorRow = row
                _applySelection([row], notify: true)
            }
            scrollRowToVisible(row)
        }
        let current = shift ? (_selectedRows.last == _anchorRow ? _selectedRows.first ?? -1 : _selectedRows.last ?? -1) : (_selectedRows.last ?? -1)
        switch event.charactersIgnoringModifiers {
        case "\u{F700}": move(to: current < 0 ? _numberOfRows - 1 : current - 1)          // up
        case "\u{F701}": move(to: current < 0 ? 0 : current + 1)                          // down
        case "\u{F729}": move(to: 0)                                                       // home
        case "\u{F72B}": move(to: _numberOfRows - 1)                                       // end
        case "\r", "\u{3}":
            if let d = _doubleAction { if let t = target { _ = sendAction(d, to: t) } else { _ = NSApplication.shared.sendAction(d, to: nil, from: self) } }
        default: super.keyDown(with: event)
        }
    }

    @MainActor open override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { for (row, v) in _rowViews { _applyRowState(v, row: row) } }
        return ok
    }
    @MainActor open override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { for (row, v) in _rowViews { _applyRowState(v, row: row) } }
        return ok
    }
    /// The key window changed: selection emphasis follows it.
    internal func _windowKeyStateChanged() { for (row, v) in _rowViews { _applyRowState(v, row: row) } }

    /// `selectAll:` from the Edit menu, and `deselectAll:`.
    @MainActor public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action.description {
        case "selectAll:": selectAll(sender); return true
        case "deselectAll:": deselectAll(sender); return true
        default: return false
        }
    }
    @MainActor public func respondsToSelectorAction(_ action: Selector) -> Bool {
        action.description == "selectAll:" ? _allowsMultipleSelection : action.description == "deselectAll:"
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/validateuserinterfaceitem(_:)
    @MainActor open func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let a = item.action else { return true }
        return respondsToSelectorAction(a)
    }

    // MARK: Header and corner

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/headerview
    @MainActor open var headerView: NSTableHeaderView? {
        get { _headerView }
        set {
            _headerView?._tableView = nil
            _headerView = newValue
            newValue?._tableView = self
            enclosingScrollView?.tile()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/cornerview
    @MainActor open var cornerView: NSView? {
        get { _cornerView }
        set { _cornerView = newValue; enclosingScrollView?.tile() }
    }

    // MARK: Sorting

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/sortdescriptors
    @MainActor open var sortDescriptors: [NSSortDescriptor] {
        get { _sortDescriptors }
        set {
            let old = _sortDescriptors
            _sortDescriptors = newValue
            _headerView?.needsDisplay = true
            _dataSourceSortDescriptorsDidChange(old)
        }
    }

    // MARK: Misc

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/autosavename
    @MainActor open var autosaveName: NSTableView.AutosaveName? {
        get { _autosaveName }
        set { _autosaveName = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/autosavetablecolumns
    @MainActor open var autosaveTableColumns: Bool {
        get { _autosaveTableColumns }
        set { _autosaveTableColumns = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/candragrows(with:at:)
    @MainActor open func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/dragimageforrows(with:tablecolumns:event:offset:)
    @MainActor open func dragImageForRows(with dragRows: IndexSet, tableColumns: [NSTableColumn], event dragEvent: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/draggingdestinationfeedbackstyle
    @MainActor open var draggingDestinationFeedbackStyle: NSTableView.DraggingDestinationFeedbackStyle {
        get { _draggingDestinationFeedbackStyle }
        set { _draggingDestinationFeedbackStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/floatsgrouprows
    @MainActor open var floatsGroupRows: Bool {
        get { _floatsGroupRows }
        set { _floatsGroupRows = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/focusedcolumn()
    @MainActor open func focusedColumn() -> Int { _focusedColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/setfocusedcolumn(_:)
    @MainActor open func setFocusedColumn(_ focusedColumn: Int) { _focusedColumn = focusedColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/preparedcell(atcolumn:row:)
    @MainActor open func preparedCell(atColumn column: Int, row: Int) -> NSCell? {
        guard _tableColumns.indices.contains(column) else { return nil }
        let c = _tableColumns[column]
        guard let cell = (_delegateDataCell(for: c, row: row) ?? c.dataCell(forRow: row) as? NSCell) else { return nil }
        cell.objectValue = _objectValue(for: c, row: row)
        _delegateWillDisplayCell(cell, for: c, row: row)
        return cell
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/rowactionsvisible
    @MainActor open var rowActionsVisible: Bool {
        get { _rowActionsVisible }
        set { _rowActionsVisible = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/setdraggingsourceoperationmask(_:forlocal:)
    @MainActor open func setDraggingSourceOperationMask(_ mask: NSDragOperation, forLocal isLocal: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/setdroprow(_:dropoperation:)
    @MainActor open func setDropRow(_ row: Int, dropOperation: NSTableView.DropOperation) {
        for (r, v) in _rowViews { v.isTargetForDropOperation = r == row && dropOperation == .on }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/shouldfocuscell(_:atcolumn:row:)
    @MainActor open func shouldFocusCell(_ cell: NSCell, atColumn column: Int, row: Int) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/userinterfacelayoutdirection
    @MainActor open override var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { super.userInterfaceLayoutDirection }
        set {
            let was = userInterfaceLayoutDirection
            super.userInterfaceLayoutDirection = newValue
            // The columns mirror: re-place every cell view and redraw the header.
            if userInterfaceLayoutDirection != was { tile(); _layoutRowViews() }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableview/verticalmotioncanbegindrag
    @MainActor open var verticalMotionCanBeginDrag: Bool {
        get { _verticalMotionCanBeginDrag }
        set { _verticalMotionCanBeginDrag = newValue }
    }

    // NSDraggingSource
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession(_:sourceoperationmaskfor:)
    @MainActor open func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [] }

    // MARK: Accessibility (ADR-0013)
    //
    // AXTable whose children are the row views the table currently has (the visible
    // rows and the recycled margin), each an AXRow carrying its cells. Selection goes
    // through `selectRowIndexes`, so delegates and notifications see it.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .table }
    open override func accessibilityLabel() -> String? { _a11y.label }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : nil }
    open override func accessibilityChildren() -> [Any]? {
        if let c = _a11y.children { return c }
        let rows: [any NSAccessibilityRow]? = accessibilityRows()      // the typed overload, not the protocol default
        return rows ?? []
    }
    open func accessibilitySelectedChildren() -> [Any]? {
        let rows: [any NSAccessibilityRow]? = accessibilitySelectedRows()
        return rows ?? []
    }
    override func _accessibilityAllowsMultipleSelection() -> Bool { allowsMultipleSelection }
    open func accessibilityRowCount() -> Int { numberOfRows }
    open func accessibilityColumnCount() -> Int { numberOfColumns }
    /// The rows the table has views for (the visible rect), made now if the table has
    /// not drawn yet, so a snapshot taken before the first paint already has them.
    open func accessibilityRows() -> [any NSAccessibilityRow]? { MainActor.assumeIsolated { _updateVisibleRows(); return _rowViews.sorted { $0.key < $1.key }.map { $0.value } } }
    open func accessibilitySelectedRows() -> [any NSAccessibilityRow]? { MainActor.assumeIsolated { _rowViews.filter { _selectedRows.contains($0.key) }.sorted { $0.key < $1.key }.map { $0.value } } }
    open func setAccessibilitySelectedRows(_ selectedRows: [any NSAccessibilityRow]) {
        MainActor.assumeIsolated {
            let rows = IndexSet(selectedRows.compactMap { ($0 as? NSTableRowView)?._row }.filter { $0 >= 0 })
            selectRowIndexes(rows, byExtendingSelection: false)
        }
    }
    open func accessibilityVisibleRows() -> [any NSAccessibilityRow]? { accessibilityRows() }
    open func accessibilityColumns() -> [Any]? { MainActor.assumeIsolated { _tableColumns } }
    open func accessibilityVisibleColumns() -> [Any]? { MainActor.assumeIsolated { _tableColumns.filter { !$0.isHidden } } }
    open func accessibilitySelectedColumns() -> [Any]? { MainActor.assumeIsolated { _selectedColumns.map { _tableColumns[$0] } } }
    open func accessibilitySelectedCells() -> [Any]? { nil }
    open func accessibilityVisibleCells() -> [Any]? { nil }
    open func accessibilityRowHeaderUIElements() -> [Any]? { nil }
    open func accessibilityColumnHeaderUIElements() -> [Any]? { nil }
}
