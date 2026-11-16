// NSBrowser (hand-written; seeded from the generated stub, see tools/apigen)
//
// A column browser (ADR-0032). Each loaded column is an NSScrollView whose document view
// is a list-mode NSMatrix of browser cells, as in AppKit, so `matrix(inColumn:)` answers
// the real column. Content comes from the delegate in one of AppKit's three ways:
//
//   item-based      `rootItem(for:)`, `numberOfChildrenOfItem`, `child(_:ofItem:)`,
//                   `isLeafItem`, `objectValueForItem`
//   passive matrix  `numberOfRowsInColumn` then `willDisplayCell` for each row
//   active matrix   `createRowsForColumn(_:in:)` fills the matrix itself
//
// Selecting one branch cell in a column loads the next column with its children and
// scrolls it into view; the path of selected cells is `path()` and `setPath(_:)`. Columns
// sit side by side from `firstVisibleColumn`, sized to fill the browser
// (`autoColumnResizing`) or at their own widths (user resizing by dragging a column's
// right edge, or none), under optional titles and over a horizontal scroller. The arrow
// keys move within a column and between columns, sending the action when
// `sendsActionOnArrowKeys`; typing selects by prefix.

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

/// The browser's horizontal scroller: moving it scrolls the columns.
@MainActor
internal final class _NSBrowserScroller: NSScroller {
    weak var browser: NSBrowser?
    override func _fireAction() { browser?._scrollerMoved() }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser
@MainActor open class NSBrowser: NSControl {
    /// One loaded column: its scroll view and matrix, and in item mode its items.
    internal final class _Column {
        let scrollView: NSScrollView
        let matrix: NSMatrix
        var items: [Any] = []
        init(scrollView: NSScrollView, matrix: NSMatrix) { self.scrollView = scrollView; self.matrix = matrix }
    }

    /// How the delegate supplies content (decided when column 0 loads).
    internal enum _ContentMode { case item, passive, active }

    // MARK: Storage
    internal var _columns: [_Column] = []
    private var _reusePool: [_Column] = []
    private var _isLoaded = false
    private var _contentMode: _ContentMode? = nil
    private var _usesRowHeights = false
    private weak var _delegate: (any NSBrowserDelegate)? = nil
    private weak var _browserTarget: AnyObject? = nil
    private var _browserAction: Selector? = nil
    private var _doubleAction: Selector? = nil
    private var _isBrowserEnabled = true
    private var _browserTag = 0
    private var _firstVisibleColumn = 0
    private var _maxVisibleColumns = 3
    private var _minColumnWidth: CGFloat = 100
    private var _defaultColumnWidth: CGFloat = -1
    private var _columnWidths: [Int: CGFloat] = [:]
    private var _columnResizingType: NSBrowser.ColumnResizingType = .autoColumnResizing
    private var _prefersAllColumnUserResizing = false
    private var _columnsAutosaveName: NSBrowser.ColumnsAutosaveName = ""
    private var _isTitled = true
    private var _titles: [Int: String] = [:]
    private var _separatesColumns = true
    private var _takesTitleFromPreviousColumn = true
    private var _hasHorizontalScroller = true
    private var _autohidesScroller = false
    private var _backgroundColor: NSColor = .controlBackgroundColor
    private var _allowsBranchSelection = true
    private var _allowsEmptySelection = true
    private var _allowsMultipleSelection = false
    private var _allowsTypeSelect = true
    private var _reusesColumns = false
    private var _rowHeight: CGFloat = 17
    private var _pathSeparator = "/"
    private var _sendsActionOnArrowKeys = true
    private var _matrixClass: AnyClass = NSMatrix.self
    private var _cellPrototype: NSCell = NSBrowserCell(textCell: "")
    private var _clickedColumn = -1
    private var _clickedRow = -1
    private var _localDragMask: NSDragOperation = .every
    private var _remoteDragMask: NSDragOperation = []
    private var _typeSelectString = ""
    private var _typeSelectTime: TimeInterval = 0
    private let _scroller = _NSBrowserScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 15))
    // Column resizing by drag.
    private var _resizingColumn = -1
    private var _resizeStartX: CGFloat = 0
    private var _resizeStartWidth: CGFloat = 0

    /// Set by the delegate defaults of optional methods the delegate didn't implement.
    @MainActor internal static var _delegateMethodMissing = false
    /// Called by NSBrowserDelegate's defaults for `@optional` methods whose absence changes
    /// what the browser does (AppKit asks `respondsToSelector:`).
    @MainActor internal static func _noteDelegateMethodMissing() { _delegateMethodMissing = true }
    /// Runs a delegate call and reports whether the delegate implements it.
    private func _probe<T>(_ call: () -> T) -> (value: T, implemented: Bool) {
        let saved = NSBrowser._delegateMethodMissing
        NSBrowser._delegateMethodMissing = false
        let v = call()
        let implemented = !NSBrowser._delegateMethodMissing
        NSBrowser._delegateMethodMissing = saved
        return (v, implemented)
    }

    // MARK: Initializers

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _setUp()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        _setUp()
    }
    private func _setUp() {
        _scroller.browser = self
        _scroller.isHidden = true
        addSubview(_scroller)
    }

    open override var isFlipped: Bool { true }

    // MARK: Delegate and target/action

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/delegate
    @MainActor open var delegate: (any NSBrowserDelegate)? {
        get { _delegate }
        set {
            _delegate = newValue
            _contentMode = nil
            _isLoaded = false
            if newValue != nil, window != nil { loadColumnZero() } else { needsDisplay = true; needsLayout = true }
        }
    }
    @MainActor open override var target: AnyObject? {
        get { _browserTarget }
        set { _browserTarget = newValue }
    }
    @MainActor open override var action: Selector? {
        get { _browserAction }
        set { _browserAction = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/doubleaction
    @MainActor open var doubleAction: Selector? {
        get { _doubleAction }
        set { _doubleAction = newValue }
    }
    @MainActor open override var isEnabled: Bool {
        get { _isBrowserEnabled }
        set { _isBrowserEnabled = newValue; for c in _columns { c.matrix.isEnabled = newValue }; needsDisplay = true }
    }
    @MainActor open override var tag: Int {
        get { _browserTag }
        set { _browserTag = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/sendaction()
    @MainActor open func sendAction() -> Bool { sendAction(_browserAction, to: _browserTarget) }
    @MainActor internal override func _fireAction() { _ = sendAction() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/doclick(_:)
    /// The column matrices' action: updates the columns after a click and sends the action.
    @MainActor open func doClick(_ sender: Any?) {
        guard let m = sender as? NSMatrix, column(of: m) >= 0 else { return }
        _matrixClicked(m)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/dodoubleclick(_:)
    @MainActor open func doDoubleClick(_ sender: Any?) {
        guard let d = _doubleAction else { return }
        _ = sendAction(d, to: _browserTarget)
    }

    // MARK: Appearance

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _backgroundColor }
        set {
            _backgroundColor = newValue
            for c in _columns { c.scrollView.backgroundColor = newValue; c.matrix.backgroundColor = newValue }
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/istitled
    @MainActor open var isTitled: Bool {
        get { _isTitled }
        set { _isTitled = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/titleheight
    @MainActor open var titleHeight: CGFloat {
        let f = _titleFont
        return ceil(f.ascender - f.descender) + 6
    }
    private var _titleFont: NSFont { NSFont.systemFont(ofSize: NSFont.smallSystemFontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/separatescolumns
    @MainActor open var separatesColumns: Bool {
        get { _separatesColumns }
        set { _separatesColumns = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/takestitlefrompreviouscolumn
    @MainActor open var takesTitleFromPreviousColumn: Bool {
        get { _takesTitleFromPreviousColumn }
        set { _takesTitleFromPreviousColumn = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/hashorizontalscroller
    @MainActor open var hasHorizontalScroller: Bool {
        get { _hasHorizontalScroller }
        set { _hasHorizontalScroller = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/autohidesscroller
    @MainActor open var autohidesScroller: Bool {
        get { _autohidesScroller }
        set { _autohidesScroller = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/rowheight
    @MainActor open var rowHeight: CGFloat {
        get { _rowHeight }
        set {
            _rowHeight = max(1, newValue)
            for c in _columns where c.matrix._rowHeights == nil { c.matrix.cellSize = NSSize(width: c.matrix.cellSize.width, height: _rowHeight) }
            tile()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/pathseparator
    @MainActor open var pathSeparator: String {
        get { _pathSeparator }
        set { _pathSeparator = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/reusescolumns
    @MainActor open var reusesColumns: Bool {
        get { _reusesColumns }
        set { _reusesColumns = newValue; if !newValue { _reusePool = [] } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/sendsactiononarrowkeys
    @MainActor open var sendsActionOnArrowKeys: Bool {
        get { _sendsActionOnArrowKeys }
        set { _sendsActionOnArrowKeys = newValue }
    }

    // MARK: Selection options

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/allowsbranchselection
    @MainActor open var allowsBranchSelection: Bool {
        get { _allowsBranchSelection }
        set { _allowsBranchSelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/allowsemptyselection
    @MainActor open var allowsEmptySelection: Bool {
        get { _allowsEmptySelection }
        set { _allowsEmptySelection = newValue; for c in _columns { c.matrix.allowsEmptySelection = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/allowsmultipleselection
    @MainActor open var allowsMultipleSelection: Bool {
        get { _allowsMultipleSelection }
        set { _allowsMultipleSelection = newValue; for c in _columns { c.matrix._listAllowsMultipleSelection = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/allowstypeselect
    @MainActor open var allowsTypeSelect: Bool {
        get { _allowsTypeSelect }
        set { _allowsTypeSelect = newValue }
    }

    // MARK: Cells and matrices

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/cellprototype
    @MainActor open var cellPrototype: Any! {
        get { _cellPrototype }
        set { if let c = newValue as? NSCell { _cellPrototype = c } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/setcellclass(_:)
    @MainActor open func setCellClass(_ factoryId: AnyClass) { _cellPrototype = NSMatrix._instantiateCell(of: factoryId) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/matrixclass()
    @MainActor open func matrixClass() -> AnyClass { _matrixClass }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/setmatrixclass(_:)
    @MainActor open func setMatrixClass(_ factoryId: AnyClass) {
        precondition(factoryId is NSMatrix.Type, "NSBrowser: matrix class must be NSMatrix or a subclass")
        _matrixClass = factoryId
        _reusePool = []
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/matrix(incolumn:)
    @MainActor open func matrix(inColumn column: Int) -> NSMatrix? {
        _ensureLoaded()
        return column >= 0 && column < _columns.count ? _columns[column].matrix : nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/column(of:)
    @MainActor open func column(of matrix: NSMatrix) -> Int { _columns.firstIndex { $0.matrix === matrix } ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/loadedcell(atrow:column:)
    @MainActor open func loadedCell(atRow row: Int, column col: Int) -> Any? {
        guard let cell = matrix(inColumn: col)?.cell(atRow: row, column: 0) else { return nil }
        if let b = cell as? NSBrowserCell, !b.isLoaded {
            _delegate?.browser(self, willDisplayCell: b, atRow: row, column: col)
            b.isLoaded = true
        }
        return cell
    }

    // MARK: Loading columns

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/isloaded
    @MainActor open var isLoaded: Bool { _isLoaded }

    private func _ensureLoaded() {
        if !_isLoaded, _delegate != nil { loadColumnZero() }
    }

    /// Column zero is loaded in layout at the latest, before a natively hosted window builds
    /// its layer scene (loaded only at draw time, the columns' layers would miss that commit).
    @MainActor open override func layout() {
        super.layout()
        _ensureLoaded()
    }
    @MainActor open override func viewWillDraw() {
        super.viewWillDraw()
        _ensureLoaded()
    }
    @MainActor open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { _ensureLoaded() }
    }

    /// Makes (or reuses) the scroll view and matrix for a new column.
    private func _makeColumn() -> _Column {
        if _reusesColumns, let c = _reusePool.popLast() { return c }
        let m: NSMatrix
        if ObjectIdentifier(_matrixClass) == ObjectIdentifier(NSMatrix.self) {
            m = NSMatrix(frame: .zero, mode: .listModeMatrix, prototype: _cellPrototype, numberOfRows: 0, numberOfColumns: 0)
        } else {
            // A subclass is made through the required initializer, then configured.
            guard let made = (_matrixClass as! NSMatrix.Type).init(coder: NSCoder()) else { preconditionFailure("NSBrowser: \(_matrixClass) init(coder:) failed") }
            m = made
            m.mode = .listModeMatrix
        }
        m.prototype = _cellPrototype
        m._browser = self
        m.allowsEmptySelection = true
        m.isSelectionByRect = false
        m.intercellSpacing = .zero
        m.drawsBackground = true
        m.backgroundColor = _backgroundColor
        m.isEnabled = _isBrowserEnabled
        m._listAllowsMultipleSelection = _allowsMultipleSelection
        let sv = NSScrollView(frame: .zero)
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = true
        sv.backgroundColor = _backgroundColor
        sv.documentView = m
        return _Column(scrollView: sv, matrix: m)
    }

    /// Fills column `index` from the delegate. `rowCount` is a count already asked for.
    private func _loadColumn(_ index: Int, rowCount known: Int? = nil) {
        guard index < _columns.count, let d = _delegate else { return }
        let col = _columns[index]
        let m = col.matrix
        m.renewRows(0, columns: 1)
        m._rowHeights = nil
        m.cellSize = NSSize(width: max(1, m.cellSize.width), height: _rowHeight)
        col.items = []
        switch _contentMode ?? .active {
        case .item:
            let parent = parentForItems(inColumn: index)
            let n = max(0, known ?? d.browser(self, numberOfChildrenOfItem: parent))
            col.items = (0..<n).map { d.browser(self, child: $0, ofItem: parent) }
            m.renewRows(n, columns: 1)
            for (row, item) in col.items.enumerated() {
                guard let cell = m.cell(atRow: row, column: 0) else { continue }
                cell.objectValue = d.browser(self, objectValueForItem: item)
                if let b = cell as? NSBrowserCell { b.isLeaf = d.browser(self, isLeafItem: item) }
                d.browser(self, willDisplayCell: cell, atRow: row, column: index)
                (cell as? NSBrowserCell)?.isLoaded = true
            }
        case .passive:
            let n = max(0, known ?? d.browser(self, numberOfRowsInColumn: index))
            m.renewRows(n, columns: 1)
            for row in 0..<n {
                guard let cell = m.cell(atRow: row, column: 0) else { continue }
                d.browser(self, willDisplayCell: cell, atRow: row, column: index)
                (cell as? NSBrowserCell)?.isLoaded = true
            }
        case .active:
            d.browser(self, createRowsForColumn: index, in: m)
            for cell in m.cells { (cell as? NSBrowserCell)?.isLoaded = true }
        }
        _loadRowHeights(index)
    }

    /// Per-row heights from the delegate, when it gives them.
    private func _loadRowHeights(_ index: Int) {
        guard let d = _delegate, index < _columns.count else { return }
        let m = _columns[index].matrix
        guard m.numberOfRows > 0 else { m._rowHeights = nil; return }
        let first = _probe { d.browser(self, heightOfRow: 0, inColumn: index) }
        _usesRowHeights = first.implemented
        guard first.implemented else { m._rowHeights = nil; return }
        var heights = [max(1, first.value)]
        for row in 1..<m.numberOfRows { heights.append(max(1, d.browser(self, heightOfRow: row, inColumn: index))) }
        m._rowHeights = heights
    }

    /// Decides item-based, passive or active content; returns column 0's row count when
    /// asking for it decided.
    private func _decideContentMode() -> Int? {
        guard let d = _delegate else { _contentMode = nil; return nil }
        let root = d.rootItem(for: self)
        let children = _probe { d.browser(self, numberOfChildrenOfItem: root) }
        if children.implemented { _contentMode = .item; return children.value }
        let rows = _probe { d.browser(self, numberOfRowsInColumn: 0) }
        if rows.implemented { _contentMode = .passive; return rows.value }
        _contentMode = .active
        return nil
    }

    private func _removeColumns(after index: Int) {
        while _columns.count > max(index + 1, 0) {
            let c = _columns.removeLast()
            if let w = window, let fr = w.firstResponder as? NSView, fr === c.matrix || fr.isDescendant(of: c.scrollView) {
                _ = w.makeFirstResponder(index >= 0 && index < _columns.count ? _columns[index].matrix : self)
            }
            c.scrollView.removeFromSuperview()
            c.matrix.deselectAllCells()
            if _reusesColumns { _reusePool.append(c) }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/loadcolumnzero()
    @MainActor open func loadColumnZero() {
        let old = _columns.count - 1
        _removeColumns(after: -1)
        _isLoaded = true
        _firstVisibleColumn = 0
        let known = _decideContentMode()
        guard _delegate != nil else { tile(); return }
        let c = _makeColumn()
        _columns.append(c)
        addSubview(c.scrollView)
        _loadColumn(0, rowCount: known)
        tile()
        if old != 0 { _delegate?.browser(self, didChangeLastColumn: old, toColumn: 0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/addcolumn()
    /// Loads the column after the last one.
    @MainActor open func addColumn() {
        _ensureLoaded()
        guard _delegate != nil, _isLoaded else { return }
        let old = _columns.count - 1
        let c = _makeColumn()
        _columns.append(c)
        addSubview(c.scrollView)
        _loadColumn(_columns.count - 1)
        tile()
        _delegate?.browser(self, didChangeLastColumn: old, toColumn: _columns.count - 1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/lastcolumn
    @MainActor open var lastColumn: Int {
        get { _ensureLoaded(); return _columns.count - 1 }
        set {
            _ensureLoaded()
            let old = _columns.count - 1
            guard newValue >= 0, newValue < old else { return }
            _removeColumns(after: newValue)
            if _firstVisibleColumn > newValue { _firstVisibleColumn = max(0, newValue - numberOfVisibleColumns + 1) }
            tile()
            _delegate?.browser(self, didChangeLastColumn: old, toColumn: newValue)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/reloadcolumn(_:)
    /// Reloads a column, keeping its selected rows that still exist; when its selection
    /// changes, the columns after it go.
    @MainActor open func reloadColumn(_ column: Int) {
        _ensureLoaded()
        guard column >= 0, column < _columns.count else { return }
        let m = _columns[column].matrix
        let selected = IndexSet(m.selectedCells.compactMap { m._position(of: $0)?.row })
        let oldTitles = m.selectedCells.map { $0.stringValue }
        _loadColumn(column)
        let keep = IndexSet(selected.filter { $0 < m.numberOfRows })
        let cells = keep.compactMap { m.cell(atRow: $0, column: 0) }
        if !cells.isEmpty { m._applySelection(cells, primary: cells.last) }
        if cells.map({ $0.stringValue }) != oldTitles || cells.count != selected.count || (cells.count == 1 && _isBranch(row: keep.first!, column: column) == false) {
            if column < _columns.count - 1 { lastColumn = column }
        }
        tile()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/validatevisiblecolumns()
    @MainActor open func validateVisibleColumns() {
        guard let d = _delegate else { return }
        for c in _firstVisibleColumn...max(_firstVisibleColumn, min(lastVisibleColumn, _columns.count - 1)) where c < _columns.count {
            if !d.browser(self, isColumnValid: c) { reloadColumn(c) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/reloaddata(forrowindexes:incolumn:)
    @MainActor open func reloadData(forRowIndexes rowIndexes: IndexSet, inColumn column: Int) {
        guard let d = _delegate, column >= 0, column < _columns.count else { return }
        let col = _columns[column]
        for row in rowIndexes {
            guard let cell = col.matrix.cell(atRow: row, column: 0) else { continue }
            if _contentMode == .item, row < col.items.count {
                let item = col.items[row]
                cell.objectValue = d.browser(self, objectValueForItem: item)
                (cell as? NSBrowserCell)?.isLeaf = d.browser(self, isLeafItem: item)
            }
            d.browser(self, willDisplayCell: cell, atRow: row, column: column)
        }
        col.matrix.needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/noteheightofrowswithindexeschanged(_:incolumn:)
    @MainActor open func noteHeightOfRowsWithIndexesChanged(_ indexSet: IndexSet, inColumn columnIndex: Int) {
        guard let d = _delegate, columnIndex >= 0, columnIndex < _columns.count else { return }
        let m = _columns[columnIndex].matrix
        guard var heights = m._rowHeights else { _loadRowHeights(columnIndex); tile(); return }
        for row in indexSet where row < heights.count { heights[row] = max(1, d.browser(self, heightOfRow: row, inColumn: columnIndex)) }
        m._rowHeights = heights
        tile()
    }

    // MARK: Items (item-based delegates)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/item(atrow:incolumn:)
    @MainActor open func item(atRow row: Int, inColumn column: Int) -> Any? {
        _ensureLoaded()
        guard column >= 0, column < _columns.count, row >= 0, row < _columns[column].items.count else { return nil }
        return _columns[column].items[row]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/parentforitems(incolumn:)
    @MainActor open func parentForItems(inColumn column: Int) -> Any? {
        if column <= 0 { return _delegate?.rootItem(for: self) }
        guard column - 1 < _columns.count else { return nil }
        let row = _columns[column - 1].matrix.selectedRow
        return row >= 0 ? item(atRow: row, inColumn: column - 1) : nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/item(at:)
    @MainActor open func item(at indexPath: IndexPath) -> Any? {
        guard let d = _delegate, _contentMode == .item || _decideModeIfNeeded() == .item else { return nil }
        var item = d.rootItem(for: self)
        for index in indexPath {
            guard index >= 0, index < d.browser(self, numberOfChildrenOfItem: item) else { return nil }
            item = d.browser(self, child: index, ofItem: item)
        }
        return item
    }
    private func _decideModeIfNeeded() -> _ContentMode? {
        if _contentMode == nil { _ = _decideContentMode() }
        return _contentMode
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/isleafitem(_:)
    @MainActor open func isLeafItem(_ item: Any?) -> Bool { _delegate?.browser(self, isLeafItem: item) ?? true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/indexpath(forcolumn:)
    /// The selected rows of the columns before `column`: the path of the item whose
    /// children it shows.
    @MainActor open func indexPath(forColumn column: Int) -> IndexPath {
        _ensureLoaded()
        var path = IndexPath()
        for c in 0..<min(max(column, 0), _columns.count) {
            let row = _columns[c].matrix.selectedRow
            guard row >= 0 else { break }
            path.append(row)
        }
        return path
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/edititem(at:with:select:)
    @MainActor open func editItem(at indexPath: IndexPath, with event: NSEvent?, select: Bool) {
        guard let d = _delegate, let row = indexPath.last else { return }
        selectionIndexPath = indexPath.count > 1 ? indexPath.dropLast() : nil
        let column = indexPath.count - 1
        guard let m = matrix(inColumn: column), let cell = m.cell(atRow: row, column: 0) else { return }
        guard d.browser(self, shouldEditItem: item(atRow: row, inColumn: column)) else { return }
        cell.isEditable = true
        m._editCell(atRow: row, column: 0, event: event, select: select)
    }

    // MARK: Selection

    private func _isBranch(row: Int, column: Int) -> Bool {
        guard column >= 0, column < _columns.count else { return false }
        if _contentMode == .item, row >= 0, row < _columns[column].items.count {
            return !(_delegate?.browser(self, isLeafItem: _columns[column].items[row]) ?? true)
        }
        guard let cell = _columns[column].matrix.cell(atRow: row, column: 0) else { return false }
        return !((cell as? NSBrowserCell)?.isLeaf ?? true)
    }

    /// After the selection in `column` changed: show the children of a single selected
    /// branch in the next column, otherwise make `column` the last.
    private func _updateColumns(afterSelectionIn column: Int) {
        guard column >= 0, column < _columns.count else { return }
        let m = _columns[column].matrix
        let rows = m.selectedCells.compactMap { m._position(of: $0)?.row }
        if column < _columns.count - 1 { lastColumn = column }
        if rows.count == 1, _isBranch(row: rows[0], column: column) {
            addColumn()
            scrollColumnToVisible(column + 1)
        } else {
            scrollColumnToVisible(column)
        }
        needsDisplay = true
    }

    /// The delegate's say on a proposed selection, applied to the matrix.
    private func _confirmSelection(in column: Int) {
        guard let d = _delegate, column >= 0, column < _columns.count else { return }
        let m = _columns[column].matrix
        var proposed = IndexSet(m.selectedCells.compactMap { m._position(of: $0)?.row })
        if !_allowsBranchSelection, proposed.count > 1 { proposed = IndexSet(proposed.filter { !_isBranch(row: $0, column: column) }) }
        let rows = d.browser(self, selectionIndexesForProposedSelection: proposed, inColumn: column)
        guard rows != proposed || rows.count != m.selectedCells.count else { return }
        let cells = rows.compactMap { m.cell(atRow: $0, column: 0) }
        if cells.isEmpty { m.deselectAllCells() } else { m._applySelection(cells, primary: cells.last) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectrow(_:incolumn:)
    @MainActor open func selectRow(_ row: Int, inColumn column: Int) {
        _ensureLoaded()
        guard column >= 0, column < _columns.count, let d = _delegate else { return }
        let m = _columns[column].matrix
        let byDelegate = _contentMode != .item ? _probe { d.browser(self, selectRow: row, inColumn: column) } : (value: false, implemented: false)
        if !(byDelegate.implemented && byDelegate.value) {
            guard row >= 0, row < m.numberOfRows else { return }
            m.selectCell(atRow: row, column: 0)
        }
        _updateColumns(afterSelectionIn: column)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectrowindexes(_:incolumn:)
    @MainActor open func selectRowIndexes(_ indexes: IndexSet, inColumn column: Int) {
        _ensureLoaded()
        guard column >= 0, column < _columns.count, let d = _delegate else { return }
        let m = _columns[column].matrix
        var rows = IndexSet(indexes.filter { $0 >= 0 && $0 < m.numberOfRows })
        if !_allowsMultipleSelection, let last = rows.last { rows = [last] }
        rows = d.browser(self, selectionIndexesForProposedSelection: rows, inColumn: column)
        let cells = rows.compactMap { m.cell(atRow: $0, column: 0) }
        if cells.isEmpty { m.deselectAllCells() } else { m._applySelection(cells, primary: cells.last) }
        _updateColumns(afterSelectionIn: column)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectedrow(incolumn:)
    @MainActor open func selectedRow(inColumn column: Int) -> Int { matrix(inColumn: column)?.selectedRow ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectedrowindexes(incolumn:)
    @MainActor open func selectedRowIndexes(inColumn column: Int) -> IndexSet? {
        guard let m = matrix(inColumn: column) else { return nil }
        return IndexSet(m.selectedCells.compactMap { m._position(of: $0)?.row })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectedcolumn
    /// The last column with a selection; -1 when nothing is selected.
    @MainActor open var selectedColumn: Int {
        _ensureLoaded()
        return _columns.lastIndex { $0.matrix.selectedCell() != nil } ?? -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectedcell()
    @MainActor open func selectedCell() -> Any? { selectedCell(inColumn: selectedColumn) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectedcell(incolumn:)
    @MainActor open func selectedCell(inColumn column: Int) -> Any? { matrix(inColumn: column)?.selectedCell() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectedcells
    @MainActor open var selectedCells: [NSCell]? { matrix(inColumn: selectedColumn)?.selectedCells }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectall(_:)
    @MainActor open func selectAll(_ sender: Any?) {
        guard _allowsMultipleSelection else { return }
        let column = max(0, selectedColumn)
        guard let m = matrix(inColumn: column) else { return }
        m.selectAll(sender)
        _confirmSelection(in: column)
        _updateColumns(afterSelectionIn: column)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectionindexpath
    @MainActor open var selectionIndexPath: IndexPath? {
        get {
            let column = selectedColumn
            guard column >= 0 else { return nil }
            var path = indexPath(forColumn: column)
            path.append(_columns[column].matrix.selectedRow)
            return path
        }
        set {
            _ensureLoaded()
            guard _isLoaded, !_columns.isEmpty else { return }
            lastColumn = 0
            _columns[0].matrix.deselectAllCells()
            guard let path = newValue else { needsDisplay = true; return }
            for (column, row) in path.enumerated() {
                guard column < _columns.count, row >= 0, row < _columns[column].matrix.numberOfRows else { break }
                _columns[column].matrix.selectCell(atRow: row, column: 0)
                _updateColumns(afterSelectionIn: column)
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/selectionindexpaths
    @MainActor open var selectionIndexPaths: [IndexPath] {
        get {
            let column = selectedColumn
            guard column >= 0 else { return [] }
            let prefix = indexPath(forColumn: column)
            return (selectedRowIndexes(inColumn: column) ?? []).map { prefix.appending($0) }
        }
        set {
            guard let first = newValue.first else { selectionIndexPath = nil; return }
            let parent = first.dropLast()
            selectionIndexPath = parent.isEmpty ? nil : parent
            let rows = IndexSet(newValue.filter { $0.dropLast() == parent }.compactMap { $0.last })
            selectRowIndexes(rows, inColumn: parent.count)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/clickedcolumn
    @MainActor open var clickedColumn: Int { _clickedColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/clickedrow
    @MainActor open var clickedRow: Int { _clickedRow }

    // MARK: Paths

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/path()
    @MainActor open func path() -> String { path(toColumn: _columns.count) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/path(tocolumn:)
    /// The separator and the selected cells' titles of the columns before `column`.
    @MainActor open func path(toColumn column: Int) -> String {
        _ensureLoaded()
        var parts: [String] = []
        for c in 0..<min(max(column, 0), _columns.count) {
            guard let cell = _columns[c].matrix.selectedCell() else { break }
            parts.append(cell.stringValue)
        }
        return _pathSeparator + parts.joined(separator: _pathSeparator)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/setpath(_:)
    /// Selects the cell titled by each component in turn, from column 0 for an absolute
    /// path or from the last column otherwise. False when a component isn't found.
    @MainActor open func setPath(_ path: String) -> Bool {
        _ensureLoaded()
        guard let d = _delegate, !_columns.isEmpty else { return false }
        let absolute = path.hasPrefix(_pathSeparator)
        let components = path.components(separatedBy: _pathSeparator).filter { !$0.isEmpty }
        var column: Int
        if absolute {
            lastColumn = 0
            _columns[0].matrix.deselectAllCells()
            column = 0
        } else {
            column = _columns.count - 1
            if _columns[column].matrix.selectedCell() != nil {
                guard _isBranch(row: _columns[column].matrix.selectedRow, column: column) else { return components.isEmpty }
                if column == _columns.count - 1 { addColumn() }
                column += 1
            }
        }
        var ok = true
        for (i, name) in components.enumerated() {
            guard column < _columns.count else { ok = false; break }
            let m = _columns[column].matrix
            let byDelegate = _probe { d.browser(self, selectCellWith: name, inColumn: column) }
            var found = byDelegate.implemented && byDelegate.value && m.selectedCell() != nil
            if !byDelegate.implemented, let row = (0..<m.numberOfRows).first(where: { m.cell(atRow: $0, column: 0)?.stringValue == name }) {
                m.selectCell(atRow: row, column: 0)
                found = true
            }
            guard found else { ok = false; break }
            if column < _columns.count - 1 { lastColumn = column }
            if _isBranch(row: m.selectedRow, column: column) {
                addColumn()
                column += 1
            } else if i < components.count - 1 {
                ok = false
                break
            }
        }
        scrollColumnToVisible(_columns.count - 1)
        needsDisplay = true
        return ok
    }

    // MARK: Titles

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/title(ofcolumn:)
    /// The delegate's title, else one set with `setTitle(_:ofColumn:)`, else (when
    /// `takesTitleFromPreviousColumn`) the previous column's selected cell.
    @MainActor open func title(ofColumn column: Int) -> String? {
        guard column >= 0 else { return nil }
        if let t = _delegate?.browser(self, titleOfColumn: column) { return t }
        if let t = _titles[column] { return t }
        if _takesTitleFromPreviousColumn {
            if column == 0 { return "" }
            guard column - 1 < _columns.count, let cell = _columns[column - 1].matrix.selectedCell() else { return column < _columns.count ? "" : nil }
            return cell.stringValue
        }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/settitle(_:ofcolumn:)
    @MainActor open func setTitle(_ string: String, ofColumn column: Int) {
        guard column >= 0 else { return }
        _titles[column] = string
        setNeedsDisplay(titleFrame(ofColumn: column))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/titleframe(ofcolumn:)
    @MainActor open func titleFrame(ofColumn column: Int) -> NSRect {
        guard _isTitled else { return .zero }
        let f = frame(ofColumn: column)
        return NSRect(x: f.minX, y: 0, width: f.width, height: titleHeight)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/drawtitle(ofcolumn:in:)
    @MainActor open func drawTitle(ofColumn column: Int, in rect: NSRect) {
        guard let title = title(ofColumn: column), !title.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: _titleFont, .foregroundColor: NSColor.secondaryLabelColor]
        let size = title.size(withAttributes: attrs)
        let x = max(rect.minX + 4, rect.midX - size.width / 2)
        let y = rect.midY - size.height / 2
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clip(to: rect.insetBy(dx: 2, dy: 0))
        title.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Geometry

    private var _separatorWidth: CGFloat { _separatesColumns ? 1 : 0 }
    private var _scrollerShown: Bool {
        guard _hasHorizontalScroller else { return false }
        if !_autohidesScroller { return true }
        return _columns.count > numberOfVisibleColumns
    }
    private var _columnsTop: CGFloat { _isTitled ? titleHeight : 0 }
    private var _columnsBottom: CGFloat {
        bounds.height - (_scrollerShown ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
    }
    private var _verticalScrollerWidth: CGFloat { NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle) }

    /// The width column `column` has (auto: an equal share of the browser).
    private func _width(ofColumn column: Int) -> CGFloat {
        if _columnResizingType == .autoColumnResizing {
            let n = CGFloat(numberOfVisibleColumns)
            return max(1, (bounds.width - _separatorWidth * (n - 1)) / n)
        }
        return max(_minColumnWidth, _columnWidths[column] ?? defaultColumnWidth())
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/numberofvisiblecolumns
    @MainActor open var numberOfVisibleColumns: Int {
        if _columnResizingType == .autoColumnResizing {
            let fit = Int((bounds.width + _separatorWidth) / (_minColumnWidth + _separatorWidth))
            return max(1, min(_maxVisibleColumns, fit))
        }
        var x: CGFloat = 0, n = 0, c = _firstVisibleColumn
        while true {
            let w = _width(ofColumn: c)
            if n > 0 && x + w > bounds.width { break }
            x += w + _separatorWidth
            n += 1
            c += 1
            if x >= bounds.width || n > 1000 { break }
        }
        return max(1, n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/firstvisiblecolumn
    @MainActor open var firstVisibleColumn: Int { _firstVisibleColumn }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/lastvisiblecolumn
    @MainActor open var lastVisibleColumn: Int { _firstVisibleColumn + numberOfVisibleColumns - 1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/maxvisiblecolumns
    @MainActor open var maxVisibleColumns: Int {
        get { _maxVisibleColumns }
        set { _maxVisibleColumns = max(1, newValue); tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/mincolumnwidth
    @MainActor open var minColumnWidth: CGFloat {
        get { _minColumnWidth }
        set { _minColumnWidth = max(1, newValue); tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/frame(ofcolumn:)
    /// The column's frame below the titles (columns left of the first visible one have
    /// negative x).
    @MainActor open func frame(ofColumn column: Int) -> NSRect {
        var x: CGFloat = 0
        if column >= _firstVisibleColumn {
            for c in _firstVisibleColumn..<column { x += _width(ofColumn: c) + _separatorWidth }
        } else {
            for c in column..<_firstVisibleColumn { x -= _width(ofColumn: c) + _separatorWidth }
        }
        return NSRect(x: x, y: _columnsTop, width: _width(ofColumn: column), height: max(0, _columnsBottom - _columnsTop))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/frame(ofinsideofcolumn:)
    @MainActor open func frame(ofInsideOfColumn column: Int) -> NSRect { frame(ofColumn: column) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/frame(ofrow:incolumn:)
    @MainActor open func frame(ofRow row: Int, inColumn column: Int) -> NSRect {
        guard let m = matrix(inColumn: column), row >= 0, row < m.numberOfRows else { return .zero }
        return convert(m.cellFrame(atRow: row, column: 0), from: m)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/getrow(_:column:for:)
    @MainActor open func getRow(_ row: UnsafeMutablePointer<Int>?, column: UnsafeMutablePointer<Int>?, for point: NSPoint) -> Bool {
        _ensureLoaded()
        for (c, col) in _columns.enumerated() where !col.scrollView.isHidden {
            guard col.scrollView.frame.contains(point) else { continue }
            column?.pointee = c
            let p = col.matrix.convert(point, from: self)
            guard let pos = col.matrix._cellPosition(at: p) else { row?.pointee = -1; return false }
            row?.pointee = pos.row
            return true
        }
        return false
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnresizingtype
    @MainActor open var columnResizingType: NSBrowser.ColumnResizingType {
        get { _columnResizingType }
        set { _columnResizingType = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/prefersallcolumnuserresizing
    @MainActor open var prefersAllColumnUserResizing: Bool {
        get { _prefersAllColumnUserResizing }
        set { _prefersAllColumnUserResizing = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/defaultcolumnwidth()
    @MainActor open func defaultColumnWidth() -> CGFloat {
        if _defaultColumnWidth > 0 { return _defaultColumnWidth }
        let n = CGFloat(_maxVisibleColumns)
        return max(_minColumnWidth, (bounds.width - _separatorWidth * (n - 1)) / n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/setdefaultcolumnwidth(_:)
    @MainActor open func setDefaultColumnWidth(_ columnWidth: CGFloat) { _defaultColumnWidth = columnWidth; tile() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/width(ofcolumn:)
    @MainActor open func width(ofColumn column: Int) -> CGFloat { _width(ofColumn: column) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/setwidth(_:ofcolumn:)
    @MainActor open func setWidth(_ columnWidth: CGFloat, ofColumn columnIndex: Int) {
        guard columnIndex >= 0 else { return }
        _columnWidths[columnIndex] = max(_minColumnWidth, columnWidth)
        tile()
        _columnConfigurationChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columncontentwidth(forcolumnwidth:)
    @MainActor open func columnContentWidth(forColumnWidth columnWidth: CGFloat) -> CGFloat { max(0, columnWidth - _verticalScrollerWidth) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnwidth(forcolumncontentwidth:)
    @MainActor open func columnWidth(forColumnContentWidth columnContentWidth: CGFloat) -> CGFloat { columnContentWidth + _verticalScrollerWidth }
    /// The width that fits column `column`'s widest cell (for size-to-fit).
    internal func _fittingWidth(ofColumn column: Int) -> CGFloat {
        guard column >= 0, column < _columns.count else { return defaultColumnWidth() }
        let widest = _columns[column].matrix.cells.map { $0.cellSize.width }.max() ?? 0
        return max(_minColumnWidth, columnWidth(forColumnContentWidth: ceil(widest)))
    }

    private var _autosaveKey: String { "NSBrowser Column Widths \(_columnsAutosaveName)" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnsautosavename
    /// User-resized column widths are kept in the user defaults under this name.
    @MainActor open var columnsAutosaveName: NSBrowser.ColumnsAutosaveName {
        get { _columnsAutosaveName }
        set {
            _columnsAutosaveName = newValue
            guard !newValue.isEmpty, let saved = UserDefaults.standard.array(forKey: _autosaveKey) as? [Double] else { return }
            for (i, w) in saved.enumerated() where w > 0 { _columnWidths[i] = CGFloat(w) }
            tile()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/removesavedcolumns(withautosavename:)
    @MainActor public class func removeSavedColumns(withAutosaveName name: NSBrowser.ColumnsAutosaveName) {
        UserDefaults.standard.removeObject(forKey: "NSBrowser Column Widths \(name)")
    }
    private func _columnConfigurationChanged() {
        if !_columnsAutosaveName.isEmpty {
            let count = (_columnWidths.keys.max() ?? -1) + 1
            UserDefaults.standard.set((0..<count).map { Double(_columnWidths[$0] ?? 0) }, forKey: _autosaveKey)
        }
        let n = Notification(name: NSBrowser.columnConfigurationDidChangeNotification, object: self)
        NotificationCenter.default.post(n)
        _delegate?.browserColumnConfigurationDidChange(n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnconfigurationdidchangenotification
    static public var columnConfigurationDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSBrowserColumnConfigurationDidChangeNotification") }

    // MARK: Layout and scrolling

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/tile()
    /// Places the visible columns, sizes their matrices and updates the scroller.
    @MainActor open func tile() {
        let first = _firstVisibleColumn, last = lastVisibleColumn
        for (c, col) in _columns.enumerated() {
            let visible = c >= first && c <= last
            col.scrollView.isHidden = !visible
            let f = frame(ofColumn: c)
            if col.scrollView.frame != f { col.scrollView.frame = f }
            let m = col.matrix
            let contentWidth = max(1, columnContentWidth(forColumnWidth: f.width))
            if m.cellSize.width != contentWidth || (m._rowHeights == nil && m.cellSize.height != _rowHeight) {
                m.cellSize = NSSize(width: contentWidth, height: m._rowHeights == nil ? _rowHeight : m.cellSize.height)
            }
            let rowsHeight = m.numberOfRows == 0 ? 0 : m.cellFrame(atRow: m.numberOfRows - 1, column: 0).maxY
            let size = NSSize(width: contentWidth, height: max(rowsHeight, f.height))
            if m.frame.size != size { m.setFrameSize(size) }
        }
        let scrollerHeight = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        _scroller.isHidden = !_scrollerShown
        _scroller.frame = NSRect(x: 0, y: bounds.height - scrollerHeight, width: bounds.width, height: scrollerHeight)
        let total = max(_columns.count, last + 1)
        let visibleCount = numberOfVisibleColumns
        _scroller.knobProportion = total > 0 ? min(1, CGFloat(visibleCount) / CGFloat(total)) : 1
        _scroller.doubleValue = total > visibleCount ? Double(first) / Double(total - visibleCount) : 0
        needsDisplay = true
    }
    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        tile()
    }

    private func _setFirstVisibleColumn(_ column: Int) {
        let maxFirst = max(0, _columns.count - numberOfVisibleColumns)
        let c = min(max(0, column), max(maxFirst, _firstVisibleColumn))
        guard c != _firstVisibleColumn else { return }
        _delegate?.browserWillScroll(self)
        _firstVisibleColumn = c
        tile()
        _delegate?.browserDidScroll(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/scrollcolumntovisible(_:)
    @MainActor open func scrollColumnToVisible(_ column: Int) {
        guard column >= 0 else { return }
        if column < _firstVisibleColumn { _setFirstVisibleColumn(column) }
        else if column > lastVisibleColumn {
            let target = column - numberOfVisibleColumns + 1
            _delegate?.browserWillScroll(self)
            _firstVisibleColumn = max(0, target)
            tile()
            _delegate?.browserDidScroll(self)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/scrollcolumnsleft(by:)
    @MainActor open func scrollColumnsLeft(by shiftAmount: Int) { _setFirstVisibleColumn(_firstVisibleColumn - max(0, shiftAmount)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/scrollcolumnsright(by:)
    @MainActor open func scrollColumnsRight(by shiftAmount: Int) { _setFirstVisibleColumn(_firstVisibleColumn + max(0, shiftAmount)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/scrollrowtovisible(_:incolumn:)
    @MainActor open func scrollRowToVisible(_ row: Int, inColumn column: Int) {
        matrix(inColumn: column)?.scrollCellToVisible(atRow: row, column: 0)
    }
    internal func _scrollerMoved() {
        let total = max(_columns.count, lastVisibleColumn + 1)
        let range = max(0, total - numberOfVisibleColumns)
        _setFirstVisibleColumn(Int((_scroller.doubleValue * Double(range)).rounded()))
    }

    // MARK: Drawing

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        _backgroundColor.setFill()
        NSBezierPath.fill(dirtyRect)
        let first = _firstVisibleColumn, last = lastVisibleColumn
        if _isTitled {
            for c in first...last { drawTitle(ofColumn: c, in: titleFrame(ofColumn: c)) }
            NSColor.separatorColor.setFill()
            NSBezierPath.fill(NSRect(x: 0, y: titleHeight - 1, width: bounds.width, height: 1))
        }
        if _separatesColumns {
            NSColor.separatorColor.setFill()
            for c in first..<last {
                let f = frame(ofColumn: c)
                NSBezierPath.fill(NSRect(x: f.maxX, y: 0, width: 1, height: _columnsBottom))
            }
        }
    }

    // MARK: Column matrix events (from NSMatrix)

    /// A click (mouse up) in a column's matrix.
    internal func _matrixClicked(_ m: NSMatrix) {
        let column = column(of: m)
        guard column >= 0 else { return }
        _clickedColumn = column
        _clickedRow = m.selectedRow
        _confirmSelection(in: column)
        _updateColumns(afterSelectionIn: column)
        _ = sendAction()
    }
    /// The selection in a column changed during a press (mouse down or drag).
    internal func _matrixSelectionChanged(_ m: NSMatrix) {
        let column = column(of: m)
        guard column >= 0 else { return }
        _clickedColumn = column
        _clickedRow = m.selectedRow
        if m.selectedCell() == nil, column < _columns.count - 1 { lastColumn = column }
    }
    internal func _matrixDoubleClicked(_ m: NSMatrix) {
        _clickedColumn = column(of: m)
        _clickedRow = m.selectedRow
        doDoubleClick(m)
    }
    /// A browser cell finished editing (`editItem(at:with:select:)`).
    internal func _matrixCellEdited(_ m: NSMatrix, cell: NSCell) {
        let column = column(of: m)
        guard column >= 0, let row = m._position(of: cell)?.row else { return }
        _delegate?.browser(self, setObjectValue: cell.objectValue, forItem: item(atRow: row, inColumn: column))
        if cell is NSBrowserCell { cell.isEditable = false }
    }

    /// Arrow keys, Home/End and type select in a column. True when handled.
    internal func _matrixKeyDown(_ m: NSMatrix, event: NSEvent) -> Bool {
        let column = column(of: m)
        guard column >= 0, _isBrowserEnabled else { return false }
        let extend = event.modifierFlags.contains(.shift) && _allowsMultipleSelection
        func moved(in col: Int) {
            _clickedColumn = col
            _clickedRow = _columns[col].matrix.selectedRow
            _confirmSelection(in: col)
            _updateColumns(afterSelectionIn: col)
            if _sendsActionOnArrowKeys { _ = sendAction() }
        }
        switch event.charactersIgnoringModifiers ?? "" {
        case "\u{F700}", "\u{F701}":
            if m._moveSelection(dRow: event.charactersIgnoringModifiers == "\u{F700}" ? -1 : 1, dCol: 0, extend: extend) { moved(in: column) }
            return true
        case "\u{F729}", "\u{F72B}":
            guard m.numberOfRows > 0 else { return true }
            let row = event.charactersIgnoringModifiers == "\u{F729}" ? 0 : m.numberOfRows - 1
            m.selectCell(atRow: row, column: 0)
            m.scrollCellToVisible(atRow: row, column: 0)
            moved(in: column)
            return true
        case "\u{F703}":
            // Into the selected branch's children.
            let rows = m.selectedCells.compactMap { m._position(of: $0)?.row }
            guard rows.count == 1, _isBranch(row: rows[0], column: column) else { return true }
            if column + 1 >= _columns.count { addColumn() }
            guard column + 1 < _columns.count else { return true }
            let next = _columns[column + 1].matrix
            guard next.numberOfRows > 0 else { return true }
            _ = window?.makeFirstResponder(next)
            if next.selectedCell() == nil { next.selectCell(atRow: 0, column: 0) }
            next.scrollCellToVisible(atRow: next.selectedRow, column: 0)
            moved(in: column + 1)
            m.needsDisplay = true
            return true
        case "\u{F702}":
            // Back to the parent column, which keeps its selection.
            guard column > 0 else { return true }
            m.deselectAllCells()
            if column < _columns.count - 1 { lastColumn = column }
            let previous = _columns[column - 1].matrix
            _ = window?.makeFirstResponder(previous)
            scrollColumnToVisible(column - 1)
            _clickedColumn = column - 1
            _clickedRow = previous.selectedRow
            needsDisplay = true
            if _sendsActionOnArrowKeys { _ = sendAction() }
            return true
        default:
            return _typeSelect(event, in: m, column: column, moved: moved)
        }
    }

    /// Selects the first row whose title starts with what has been typed in the last second.
    private func _typeSelect(_ event: NSEvent, in m: NSMatrix, column: Int, moved: (Int) -> Void) -> Bool {
        guard _allowsTypeSelect, let chars = event.characters, chars.count == 1,
              let scalar = chars.unicodeScalars.first, scalar.value >= 32, !(0xF700...0xF8FF).contains(scalar.value),
              event.modifierFlags.intersection([.command, .control]).isEmpty, m.numberOfRows > 0 else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if now - _typeSelectTime > 1 { _typeSelectString = "" }
        _typeSelectTime = now
        let search = _typeSelectString + chars
        guard let d = _delegate, d.browser(self, shouldTypeSelectFor: event, withCurrentSearch: search) else { return false }
        _typeSelectString = search
        let start = max(0, m.selectedRow)
        let byDelegate = _probe { d.browser(self, nextTypeSelectMatchFromRow: start, toRow: m.numberOfRows, inColumn: column, for: search) }
        var row = byDelegate.implemented ? byDelegate.value : -1
        if !byDelegate.implemented {
            let needle = search.lowercased()
            row = (0..<m.numberOfRows).first { r in
                let s = d.browser(self, typeSelectStringForRow: r, inColumn: column) ?? m.cell(atRow: r, column: 0)?.stringValue ?? ""
                return s.lowercased().hasPrefix(needle)
            } ?? -1
        }
        guard row >= 0, row < m.numberOfRows else { return true }
        m.selectCell(atRow: row, column: 0)
        m.scrollCellToVisible(atRow: row, column: 0)
        moved(column)
        return true
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        _ensureLoaded()
        let column = max(0, selectedColumn)
        if column < _columns.count, _matrixKeyDown(_columns[column].matrix, event: event) { return }
        super.keyDown(with: event)
    }

    // MARK: Column resizing by mouse

    /// The column whose right edge is under `p`, for user resizing.
    private func _resizeColumn(at p: NSPoint) -> Int? {
        guard _columnResizingType == .userColumnResizing else { return nil }
        for c in _firstVisibleColumn...lastVisibleColumn {
            let f = frame(ofColumn: c)
            if abs(p.x - (f.maxX + _separatorWidth / 2)) <= 3, p.y < _columnsBottom { return c }
        }
        return nil
    }
    @MainActor open override func resetCursorRects() {
        guard _columnResizingType == .userColumnResizing else { return }
        for c in _firstVisibleColumn...lastVisibleColumn {
            let f = frame(ofColumn: c)
            addCursorRect(NSRect(x: f.maxX - 3, y: 0, width: 6 + _separatorWidth, height: _columnsBottom), cursor: .resizeLeftRight)
        }
    }
    @MainActor open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let c = _resizeColumn(at: p) else { super.mouseDown(with: event); return }
        if event.clickCount == 2 {
            let w = _delegate?.browser(self, sizeToFitWidthOfColumn: c) ?? _fittingWidth(ofColumn: c)
            setWidth(w, ofColumn: c)
            return
        }
        _resizingColumn = c
        _resizeStartX = p.x
        _resizeStartWidth = _width(ofColumn: c)
    }
    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _resizingColumn >= 0 else { return }
        let p = convert(event.locationInWindow, from: nil)
        let suggested = max(_minColumnWidth, _resizeStartWidth + p.x - _resizeStartX)
        let w = max(_minColumnWidth, _delegate?.browser(self, shouldSizeColumn: _resizingColumn, forUserResize: true, toWidth: suggested) ?? suggested)
        if _prefersAllColumnUserResizing != event.modifierFlags.contains(.option) {
            _defaultColumnWidth = w
            _columnWidths = [:]
        } else {
            _columnWidths[_resizingColumn] = w
        }
        tile()
    }
    @MainActor open override func mouseUp(with event: NSEvent) {
        guard _resizingColumn >= 0 else { return }
        _resizingColumn = -1
        _columnConfigurationChanged()
    }

    // MARK: Dragging

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/candragrows(with:incolumn:with:)
    @MainActor open func canDragRows(with rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent) -> Bool {
        _delegate?.browser(self, canDragRowsWith: rowIndexes, inColumn: column, with: event) ?? false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/draggingimageforrows(with:incolumn:with:offset:)
    @MainActor open func draggingImageForRows(with rowIndexes: IndexSet, inColumn column: Int, with event: NSEvent, offset dragImageOffset: NSPointPointer?) -> NSImage? {
        var offset = NSPoint.zero
        if let image = _delegate?.browser(self, draggingImageForRowsWith: rowIndexes, inColumn: column, with: event, offset: &offset) {
            dragImageOffset?.pointee = offset
            return image
        }
        unimplemented()   // AppKit renders the rows; row drag images arrive with browser drag and drop.
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/setdraggingsourceoperationmask(_:forlocal:)
    @MainActor open func setDraggingSourceOperationMask(_ mask: NSDragOperation, forLocal isLocal: Bool) {
        if isLocal { _localDragMask = mask } else { _remoteDragMask = mask }
    }

    // MARK: Accessibility (ADR-0013)

    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .browser }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : path() }
}

extension NSBrowser {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnresizingtype
    public enum ColumnResizingType: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnresizingtype/autocolumnresizing
        case autoColumnResizing = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnresizingtype/nocolumnresizing
        case noColumnResizing = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnresizingtype/usercolumnresizing
        case userColumnResizing = 2
        // SKIPPED (constrained extension): func hash(into hasher: inout Hasher)
        // SKIPPED (constrained extension): var hashValue: Int { get }
    }
}

extension NSBrowser {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/columnsautosavename
    public typealias ColumnsAutosaveName = String
}

extension NSBrowser {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/dropoperation
    public enum DropOperation: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/dropoperation/above
        case above = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowser/dropoperation/on
        case on = 0
        // SKIPPED (constrained extension): func hash(into hasher: inout Hasher)
        // SKIPPED (constrained extension): var hashValue: Int { get }
    }
}
