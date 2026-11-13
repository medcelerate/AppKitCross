// NSMatrix (hand-written; seeded from the generated stub, see tools/apigen)
//
// A grid of cells in one control (ADR-0032). The cells live in a row-major array; the
// matrix lays them out at `cellSize` with `intercellSpacing` between them (flipped, row 0
// at the top), draws each through the cell's own `draw(withFrame:in:)`, and keeps the
// selection itself:
//
//   radio      one selected cell whose state is on (the rest off); empty only when
//              `allowsEmptySelection`
//   list       any number of highlighted cells, chosen by click, Shift/Command-click and
//              drag (by rectangle or in reading order, per `isSelectionByRect`)
//   highlight  each click highlights the cell while the mouse is down and flips its state
//   track      each click flips the cell's state without highlighting
//
// Text cells that are editable or selectable are edited in the window's field editor laid
// over the cell, as NSTextField does; Tab and Shift-Tab move between editable cells when
// `tabKeyTraversesCells`. NSForm is this class with NSFormCells, NSBrowser puts one list
// matrix in each column.

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

/// The field editor's delegate while a matrix cell is edited. NSMatrix receives the
/// `NSText` delegate messages (`textDidBeginEditing(_:)` and the rest are its own public
/// members, as in AppKit) without declaring `NSTextDelegate`, which AppKit's NSMatrix
/// doesn't.
@MainActor
internal final class _NSMatrixTextDelegate: NSObject, NSTextDelegate {
    weak var matrix: NSMatrix?
    init(_ matrix: NSMatrix) { self.matrix = matrix }
    func textShouldBeginEditing(_ textObject: NSText) -> Bool { matrix?.textShouldBeginEditing(textObject) ?? true }
    func textShouldEndEditing(_ textObject: NSText) -> Bool { matrix?.textShouldEndEditing(textObject) ?? true }
    func textDidBeginEditing(_ notification: Notification) { matrix?.textDidBeginEditing(notification) }
    func textDidChange(_ notification: Notification) { matrix?.textDidChange(notification) }
    func textDidEndEditing(_ notification: Notification) { matrix?.textDidEndEditing(notification) }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix
@MainActor open class NSMatrix: NSControl, NSUserInterfaceValidations, NSViewToolTipOwner {
    // MARK: Storage

    /// The cells, row-major: cell (r, c) is `_grid[r * _cols + c]`.
    internal var _grid: [NSCell] = []
    internal var _rows = 0
    internal var _cols = 0
    private var _mode: NSMatrix.Mode = .radioModeMatrix
    private var _cellClass: AnyClass = NSActionCell.self
    private var _prototype: NSCell? = nil
    private var _cellSize = NSSize(width: 100, height: 17)
    private var _intercellSpacing = NSSize(width: 1, height: 1)
    private var _backgroundColor: NSColor = .controlColor
    private var _cellBackgroundColor: NSColor? = nil
    private var _drawsBackground = false
    private var _drawsCellBackground = false
    private var _allowsEmptySelection = false
    private var _isSelectionByRect = true
    private var _autosizesCells = false
    private var _autorecalculatesCellSize = false
    private var _isAutoscroll = false
    private var _tabKeyTraversesCells = true
    private var _cellSizeIsValid = true
    private var _isMatrixEnabled = true
    private var _matrixTag = 0
    private weak var _matrixTarget: AnyObject? = nil
    private var _matrixAction: Selector? = nil
    private var _doubleAction: Selector? = nil
    private weak var _delegate: (any NSMatrixDelegate)? = nil
    private var _keyCell: NSCell? = nil
    private var _toolTips: [ObjectIdentifier: String] = [:]
    private var _mouseDownFlags = 0

    /// The selected cells (list mode: all of them; other modes: at most the primary one),
    /// and the primary selected cell `selectedCell()` returns.
    internal var _selection: [NSCell] = []
    internal var _selectedCell: NSCell? = nil

    // Mouse tracking.
    private var _pressedCell: NSCell? = nil
    private var _anchor: (row: Int, column: Int)? = nil
    private var _selectionAtPress: [NSCell] = []

    // Field editing.
    private var _editor: NSTextView? = nil
    private var _editingCell: NSCell? = nil
    private var _editingOriginalValue: Any? = nil
    private var _handingOffToEditor = false
    private lazy var _textDelegate = _NSMatrixTextDelegate(self)

    // NSBrowser support (ADR-0032): the browser that owns this column matrix, whether a
    // list selection may hold several cells, and per-row heights (nil: all `cellSize`).
    internal weak var _browser: NSBrowser? = nil
    internal var _listAllowsMultipleSelection = true
    internal var _rowHeights: [CGFloat]? = nil

    /// The cell class a matrix made without one uses (NSForm: NSFormCell).
    @MainActor internal class var _defaultCellClass: AnyClass { NSActionCell.self }
    /// Subclass set-up after the designated initializers (NSForm's defaults).
    @MainActor internal func _configureNewMatrix(frame frameRect: NSRect) { }

    // MARK: Initializers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/init(frame:)
    @MainActor public override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, mode: .radioModeMatrix, cellClass: nil, numberOfRows: 0, numberOfColumns: 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/init(frame:mode:cellclass:numberofrows:numberofcolumns:)
    @MainActor public init(frame frameRect: NSRect, mode: NSMatrix.Mode, cellClass factoryId: AnyClass?, numberOfRows rowsHigh: Int, numberOfColumns colsWide: Int) {
        super.init(frame: frameRect)
        _cellClass = factoryId ?? type(of: self)._defaultCellClass
        _setUp(frame: frameRect, mode: mode, rows: rowsHigh, columns: colsWide)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/init(frame:mode:prototype:numberofrows:numberofcolumns:)
    @MainActor public init(frame frameRect: NSRect, mode: NSMatrix.Mode, prototype cell: NSCell, numberOfRows rowsHigh: Int, numberOfColumns colsWide: Int) {
        super.init(frame: frameRect)
        _cellClass = type(of: self)._defaultCellClass
        _prototype = cell
        _setUp(frame: frameRect, mode: mode, rows: rowsHigh, columns: colsWide)
    }
    // Required by the superclass (NSCoding).
    @MainActor public required init?(coder: NSCoder) {
        super.init(coder: coder)
        _cellClass = type(of: self)._defaultCellClass
    }

    private func _setUp(frame frameRect: NSRect, mode: NSMatrix.Mode, rows: Int, columns: Int) {
        _mode = mode
        // Cells share the frame when the matrix is made with one; otherwise they take
        // the default size (or the prototype's) and the frame follows them.
        if rows > 0, columns > 0, frameRect.width > 0, frameRect.height > 0 {
            _cellSize = NSSize(width: max(1, (frameRect.width - CGFloat(columns - 1) * _intercellSpacing.width) / CGFloat(columns)),
                               height: max(1, (frameRect.height - CGFloat(rows - 1) * _intercellSpacing.height) / CGFloat(rows)))
        } else if let p = _prototype {
            let s = p.cellSize
            if s.width > 0, s.height > 0 { _cellSize = s }
        }
        _configureNewMatrix(frame: frameRect)
        if rows > 0, columns > 0 { renewRows(rows, columns: columns) }
        if rows > 0, columns > 0, frameRect.isEmpty { sizeToCells() }
    }

    open override var isFlipped: Bool { true }

    // MARK: Cells and geometry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/numberofrows
    @MainActor open var numberOfRows: Int { _rows }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/numberofcolumns
    @MainActor open var numberOfColumns: Int { _cols }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/cells
    @MainActor open var cells: [NSCell] { _grid }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/getnumberofrows(_:columns:)
    @MainActor open func getNumberOfRows(_ rowCount: UnsafeMutablePointer<Int>?, columns colCount: UnsafeMutablePointer<Int>?) {
        rowCount?.pointee = _rows
        colCount?.pointee = _cols
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/cell(atrow:column:)
    @MainActor open func cell(atRow row: Int, column col: Int) -> NSCell? {
        guard row >= 0, row < _rows, col >= 0, col < _cols else { return nil }
        return _grid[row * _cols + col]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/cell(withtag:)
    @MainActor open func cell(withTag tag: Int) -> NSCell? { _grid.first { $0.tag == tag } }

    /// Row and column of `cell`, if it is one of the matrix's cells.
    internal func _position(of cell: NSCell?) -> (row: Int, column: Int)? {
        guard let cell, _cols > 0, let i = _grid.firstIndex(where: { $0 === cell }) else { return nil }
        return (i / _cols, i % _cols)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/getrow(_:column:of:)
    @MainActor open func getRow(_ row: UnsafeMutablePointer<Int>, column col: UnsafeMutablePointer<Int>, of cell: NSCell) -> Bool {
        guard let p = _position(of: cell) else { return false }
        row.pointee = p.row
        col.pointee = p.column
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/getrow(_:column:for:)
    @MainActor open func getRow(_ row: UnsafeMutablePointer<Int>, column col: UnsafeMutablePointer<Int>, for point: NSPoint) -> Bool {
        guard let p = _cellPosition(at: point) else { return false }
        row.pointee = p.row
        col.pointee = p.column
        return true
    }

    private func _rowHeight(_ row: Int) -> CGFloat {
        if let h = _rowHeights, row >= 0, row < h.count { return h[row] }
        return _cellSize.height
    }
    private func _rowTop(_ row: Int) -> CGFloat {
        guard let h = _rowHeights else { return CGFloat(row) * (_cellSize.height + _intercellSpacing.height) }
        var y: CGFloat = 0
        for r in 0..<row { y += (r < h.count ? h[r] : _cellSize.height) + _intercellSpacing.height }
        return y
    }

    /// The cell under `point` (matrix coordinates); nil in the spacing between cells.
    internal func _cellPosition(at point: NSPoint) -> (row: Int, column: Int)? {
        guard _rows > 0, _cols > 0, point.x >= 0, point.y >= 0 else { return nil }
        let pitchX = _cellSize.width + _intercellSpacing.width
        let col = Int(point.x / pitchX)
        guard col < _cols, point.x - CGFloat(col) * pitchX < _cellSize.width else { return nil }
        var y: CGFloat = 0
        for r in 0..<_rows {
            let h = _rowHeight(r)
            if point.y < y + h { return (r, col) }
            y += h + _intercellSpacing.height
            if point.y < y { return nil }
        }
        return nil
    }

    /// The cell under `point`, or the nearest one when `point` is in the spacing or past
    /// the edges (for drags).
    private func _nearestCellPosition(to point: NSPoint) -> (row: Int, column: Int)? {
        guard _rows > 0, _cols > 0 else { return nil }
        let pitchX = _cellSize.width + _intercellSpacing.width
        let col = min(max(Int(floor(point.x / pitchX)), 0), _cols - 1)
        var row = _rows - 1
        var y: CGFloat = 0
        for r in 0..<_rows {
            y += _rowHeight(r) + _intercellSpacing.height
            if point.y < y { row = r; break }
        }
        return (max(row, 0), col)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/cellframe(atrow:column:)
    @MainActor open func cellFrame(atRow row: Int, column col: Int) -> NSRect {
        NSRect(x: CGFloat(col) * (_cellSize.width + _intercellSpacing.width), y: _rowTop(row),
               width: _cellSize.width, height: _rowHeight(row))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/cellsize
    @MainActor open var cellSize: NSSize {
        get { _cellSize }
        set { _cellSize = newValue; _relayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/intercellspacing
    @MainActor open var intercellSpacing: NSSize {
        get { _intercellSpacing }
        set { _intercellSpacing = newValue; _relayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/autosizescells
    @MainActor open var autosizesCells: Bool {
        get { _autosizesCells }
        set { _autosizesCells = newValue; if newValue { _autosize() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/autorecalculatescellsize
    @MainActor open var autorecalculatesCellSize: Bool {
        get { _autorecalculatesCellSize }
        set { _autorecalculatesCellSize = newValue; if newValue { _recalculateCellSize() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/setvalidatesize(_:)
    @MainActor open func setValidateSize(_ flag: Bool) {
        _cellSizeIsValid = flag
        if !flag { _recalculateCellSize(); _cellSizeIsValid = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/sizetocells()
    @MainActor open func sizeToCells() {
        let w = _cols == 0 ? 0 : CGFloat(_cols) * _cellSize.width + CGFloat(_cols - 1) * _intercellSpacing.width
        let h = _rows == 0 ? 0 : _rowTop(_rows - 1) + _rowHeight(_rows - 1)
        setFrameSize(NSSize(width: w, height: h))
    }
    @MainActor open override func sizeToFit() { sizeToCells() }

    /// The largest natural size of the cells (for `autorecalculatesCellSize`).
    private func _recalculateCellSize() {
        guard _autorecalculatesCellSize, !_grid.isEmpty else { return }
        var s = NSSize.zero
        for c in _grid { let cs = c.cellSize; s.width = max(s.width, cs.width); s.height = max(s.height, cs.height) }
        if s.width > 0, s.height > 0 { _cellSize = s }
    }

    /// Fits the cells to the bounds (for `autosizesCells`).
    private func _autosize() {
        guard _autosizesCells, _rows > 0, _cols > 0 else { return }
        let w = (bounds.width - CGFloat(_cols - 1) * _intercellSpacing.width) / CGFloat(_cols)
        let h = (bounds.height - CGFloat(_rows - 1) * _intercellSpacing.height) / CGFloat(_rows)
        if w > 0 { _cellSize.width = w }
        if h > 0, _rowHeights == nil { _cellSize.height = h }
    }

    private func _relayout() {
        _relayoutEditor()
        needsDisplay = true
    }

    /// Called whenever cells are added, removed or replaced.
    private func _cellsChanged() {
        _recalculateCellSize()
        _autosize()
        _selection.removeAll { s in !_grid.contains { $0 === s } }
        if let s = _selectedCell, !_grid.contains(where: { $0 === s }) { _selectedCell = _selection.last }
        if let k = _keyCell, !_grid.contains(where: { $0 === k }) { _keyCell = nil }
        if let e = _editingCell, !_grid.contains(where: { $0 === e }) { _endEditingSession(takeValue: false) }
        _ensureRadioSelection()
        _relayout()
        window?.invalidateCursorRects(for: self)
    }

    /// A radio matrix that doesn't allow an empty selection always has one.
    private func _ensureRadioSelection() {
        guard _mode == .radioModeMatrix, !_allowsEmptySelection, _selectedCell == nil, _rows > 0, _cols > 0 else { return }
        if let first = _grid.first(where: { $0.isEnabled }) ?? _grid.first { _applySelection([first], primary: first) }
    }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _autosize()
        _relayout()
    }

    // MARK: Making and arranging cells

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/cellclass
    @MainActor open var cellClass: AnyClass {
        get { _cellClass }
        set { _cellClass = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/prototype
    @MainActor open var prototype: NSCell? {
        get { _prototype }
        set { _prototype = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/makecell(atrow:column:)
    @MainActor open func makeCell(atRow row: Int, column col: Int) -> NSCell {
        if let p = _prototype, let c = p.copy() as? NSCell { return c }
        return NSMatrix._instantiateCell(of: _cellClass)
    }

    /// A new cell of `cls`. AppKit sends `init`; Swift can only construct through a
    /// metatype with a required initializer, so AppKit's own cell classes get their
    /// `init()` equivalents and other NSCell subclasses come from `init(coder:)`.
    internal static func _instantiateCell(of cls: AnyClass) -> NSCell {
        let id = ObjectIdentifier(cls)
        if id == ObjectIdentifier(NSFormCell.self) { return NSFormCell(textCell: "Field:") }
        if id == ObjectIdentifier(NSBrowserCell.self) { return NSBrowserCell(textCell: "BrowserItem") }
        if id == ObjectIdentifier(NSButtonCell.self) { return NSButtonCell(textCell: "Button") }
        if id == ObjectIdentifier(NSTextFieldCell.self) { return NSTextFieldCell(textCell: "") }
        if id == ObjectIdentifier(NSActionCell.self) { return NSActionCell(textCell: "") }
        if id == ObjectIdentifier(NSCell.self) { return NSCell(textCell: "") }
        guard let cellType = cls as? NSCell.Type else {
            preconditionFailure("NSMatrix: cell class \(cls) is not an NSCell subclass")
        }
        return cellType.init(coder: NSCoder())
    }

    private func _adopt(_ cell: NSCell) {
        cell.controlView = self
        if !_isMatrixEnabled { cell.isEnabled = false }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/addrow()
    @MainActor open func addRow() { insertRow(_rows, with: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/addrow(with:)
    @MainActor open func addRow(with newCells: [NSCell]) { insertRow(_rows, with: newCells) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/addcolumn()
    @MainActor open func addColumn() { insertColumn(_cols, with: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/addcolumn(with:)
    @MainActor open func addColumn(with newCells: [NSCell]) { insertColumn(_cols, with: newCells) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/insertrow(_:)
    @MainActor open func insertRow(_ row: Int) { insertRow(row, with: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/insertcolumn(_:)
    @MainActor open func insertColumn(_ column: Int) { insertColumn(column, with: nil) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/insertrow(_:with:)
    @MainActor open func insertRow(_ row: Int, with newCells: [NSCell]?) {
        guard row >= 0 else { return }
        if _cols == 0 { _cols = max(1, newCells?.count ?? 1); _grid = [] ; _rows = 0 }
        while _rows < row { _insertRowCells(at: _rows, cells: nil) }
        _insertRowCells(at: row, cells: newCells)
        if _rowHeights != nil { _rowHeights?.insert(_cellSize.height, at: min(row, _rowHeights!.count)) }
        _cellsChanged()
    }
    private func _insertRowCells(at row: Int, cells newCells: [NSCell]?) {
        var rowCells: [NSCell] = []
        for c in 0..<_cols {
            let cell = (newCells != nil && c < newCells!.count) ? newCells![c] : makeCell(atRow: row, column: c)
            _adopt(cell)
            rowCells.append(cell)
        }
        _grid.insert(contentsOf: rowCells, at: row * _cols)
        _rows += 1
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/insertcolumn(_:with:)
    @MainActor open func insertColumn(_ column: Int, with newCells: [NSCell]?) {
        guard column >= 0 else { return }
        if _rows == 0 { _rows = max(1, newCells?.count ?? 1); _grid = []; _cols = 0 }
        while _cols < column { _insertColumnCells(at: _cols, cells: nil) }
        _insertColumnCells(at: column, cells: newCells)
        _cellsChanged()
    }
    private func _insertColumnCells(at column: Int, cells newCells: [NSCell]?) {
        var grid: [NSCell] = []
        grid.reserveCapacity(_rows * (_cols + 1))
        for r in 0..<_rows {
            for c in 0...(_cols) {
                if c == column {
                    let cell = (newCells != nil && r < newCells!.count) ? newCells![r] : makeCell(atRow: r, column: column)
                    _adopt(cell)
                    grid.append(cell)
                }
                if c < _cols { grid.append(_grid[r * _cols + c]) }
            }
        }
        _grid = grid
        _cols += 1
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/removerow(_:)
    @MainActor open func removeRow(_ row: Int) {
        guard row >= 0, row < _rows else { return }
        _grid.removeSubrange((row * _cols)..<((row + 1) * _cols))
        _rows -= 1
        if _rowHeights != nil, row < _rowHeights!.count { _rowHeights!.remove(at: row) }
        _cellsChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/removecolumn(_:)
    @MainActor open func removeColumn(_ col: Int) {
        guard col >= 0, col < _cols else { return }
        var grid: [NSCell] = []
        for r in 0..<_rows { for c in 0..<_cols where c != col { grid.append(_grid[r * _cols + c]) } }
        _grid = grid
        _cols -= 1
        _cellsChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/renewrows(_:columns:)
    @MainActor open func renewRows(_ newRows: Int, columns newCols: Int) {
        let rows = max(0, newRows), cols = max(0, newCols)
        var grid: [NSCell] = []
        grid.reserveCapacity(rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                if r < _rows, c < _cols { grid.append(_grid[r * _cols + c]) }
                else { let cell = makeCell(atRow: r, column: c); _adopt(cell); grid.append(cell) }
            }
        }
        _grid = grid
        _rows = rows
        _cols = cols
        if _rowHeights != nil { _rowHeights = Array((_rowHeights! + Array(repeating: _cellSize.height, count: rows)).prefix(rows)) }
        _cellsChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/putcell(_:atrow:column:)
    @MainActor open func putCell(_ newCell: NSCell, atRow row: Int, column col: Int) {
        guard row >= 0, row < _rows, col >= 0, col < _cols else { return }
        let old = _grid[row * _cols + col]
        guard old !== newCell else { return }
        _adopt(newCell)
        _grid[row * _cols + col] = newCell
        _cellsChanged()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/sort(using:)
    /// Sorts with the cells' `compare(_:)`; other selectors need the Objective-C runtime.
    @MainActor open func sort(using comparator: Selector) {
        guard NSStringFromSelector(comparator) == "compare:" else { unimplemented() }
        _grid.sort { $0.compare($1) == .orderedAscending }
        _relayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/sort(using:context:)
    @MainActor open func sort(using compare: (Any, Any, UnsafeMutableRawPointer?) -> Int, context: UnsafeMutableRawPointer?) {
        _grid.sort { compare($0, $1, context) < 0 }
        _relayout()
    }

    // MARK: Mode and selection

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mode
    @MainActor open var mode: NSMatrix.Mode {
        get { _mode }
        set {
            guard newValue != _mode else { return }
            _mode = newValue
            _ensureRadioSelection()
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/allowsemptyselection
    @MainActor open var allowsEmptySelection: Bool {
        get { _allowsEmptySelection }
        set { _allowsEmptySelection = newValue; _ensureRadioSelection() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/isselectionbyrect
    @MainActor open var isSelectionByRect: Bool {
        get { _isSelectionByRect }
        set { _isSelectionByRect = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selectedcell()
    @MainActor open override func selectedCell() -> NSCell? { _selectedCell }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selectedcells
    @MainActor open var selectedCells: [NSCell] {
        // In reading order, as AppKit returns them.
        _grid.filter { c in _selection.contains { $0 === c } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selectedrow
    @MainActor open var selectedRow: Int { _position(of: _selectedCell)?.row ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selectedcolumn
    @MainActor open var selectedColumn: Int { _position(of: _selectedCell)?.column ?? -1 }

    /// Makes `newCells` the selection, updating the cells' look for the mode: radio cells
    /// turn on (the rest off), list cells highlight, highlight- and track-mode cells turn on.
    internal func _applySelection(_ newCells: [NSCell], primary: NSCell?) {
        let old = _selection
        func contains(_ list: [NSCell], _ c: NSCell) -> Bool { list.contains { $0 === c } }
        switch _mode {
        case .listModeMatrix:
            for c in old where !contains(newCells, c) { c.isHighlighted = false }
            for c in newCells where !c.isHighlighted { c.isHighlighted = true }
        case .radioModeMatrix:
            for c in old where !contains(newCells, c) { c.state = .off }
            for c in newCells where c.state != .on { c.state = .on }
        case .highlightModeMatrix, .trackModeMatrix:
            for c in newCells where c.state != .on { c.state = .on }
        }
        _selection = newCells
        _selectedCell = primary ?? newCells.last
        if let s = _selectedCell { _keyCell = s }
        needsDisplay = true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selectcell(atrow:column:)
    @MainActor open func selectCell(atRow row: Int, column col: Int) {
        guard row >= 0, col >= 0 else {
            if _mode == .radioModeMatrix && !_allowsEmptySelection { return }
            _clearSelection()
            return
        }
        guard let cell = cell(atRow: row, column: col) else { return }
        _applySelection([cell], primary: cell)
        // AppKit selects the text of an editable cell; only while the matrix has focus,
        // so building a form doesn't move the window's first responder.
        if _isTextEditable(cell), window != nil, window?.firstResponder === self || _editor != nil {
            _ = selectText(atRow: row, column: col)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selectcell(withtag:)
    @MainActor open func selectCell(withTag tag: Int) -> Bool {
        guard let c = cell(withTag: tag), let p = _position(of: c) else { return false }
        selectCell(atRow: p.row, column: p.column)
        return true
    }
    /// `NSControl.selectCell(_:)` for one of the matrix's cells.
    @MainActor open override func selectCell(_ cell: NSCell) {
        guard let p = _position(of: cell) else { return }
        selectCell(atRow: p.row, column: p.column)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selectall(_:)
    @MainActor open func selectAll(_ sender: Any?) {
        guard _mode != .radioModeMatrix else { return }
        if _mode == .listModeMatrix && !_listAllowsMultipleSelection { return }
        let cells = _grid.filter { $0.isEnabled }
        _applySelection(cells, primary: cells.last)
    }
    private func _clearSelection() {
        switch _mode {
        case .listModeMatrix: for c in _grid where c.isHighlighted { c.isHighlighted = false }
        case .radioModeMatrix: for c in _selection { c.state = .off }
        case .highlightModeMatrix, .trackModeMatrix: for c in _grid where c.state != .off { c.state = .off }
        }
        _selection = []
        _selectedCell = nil
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/deselectallcells()
    @MainActor open func deselectAllCells() {
        if _mode == .radioModeMatrix && !_allowsEmptySelection { return }
        _clearSelection()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/deselectselectedcell()
    @MainActor open func deselectSelectedCell() {
        guard let cell = _selectedCell else { return }
        if _mode == .radioModeMatrix && !_allowsEmptySelection { return }
        if _mode == .listModeMatrix { cell.isHighlighted = false } else { cell.state = .off }
        _selection.removeAll { $0 === cell }
        _selectedCell = _selection.last
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/setselectionfrom(_:to:anchor:highlight:)
    /// Positions count in reading order. The cells between the anchor and `endPos` (a
    /// rectangle when `isSelectionByRect`) take `lit`; the rest of the start...end range
    /// is restored to the opposite.
    @MainActor open func setSelectionFrom(_ startPos: Int, to endPos: Int, anchor anchorPos: Int, highlight lit: Bool) {
        guard _cols > 0 else { return }
        let range = _cells(from: anchorPos, to: endPos)
        let outer = _cells(from: min(startPos, endPos, anchorPos), to: max(startPos, endPos, anchorPos))
        var selection = _selection
        for c in outer where !range.contains(where: { $0 === c }) {
            if lit { selection.removeAll { $0 === c } } else if !selection.contains(where: { $0 === c }) { selection.append(c) }
        }
        for c in range {
            if lit { if !selection.contains(where: { $0 === c }) { selection.append(c) } } else { selection.removeAll { $0 === c } }
        }
        let anchorCell = (anchorPos >= 0 && anchorPos < _grid.count) ? _grid[anchorPos] : nil
        if _mode == .listModeMatrix {
            for c in _grid { c.isHighlighted = selection.contains { $0 === c } }
            _selection = selection
            _selectedCell = selection.contains(where: { $0 === anchorCell }) ? anchorCell : selection.last
            needsDisplay = true
        } else {
            _applySelection(selection, primary: selection.last)
        }
    }
    /// The cells between two reading-order positions: a rectangle when selecting by
    /// rectangle, otherwise every cell from one to the other.
    private func _cells(from a: Int, to b: Int) -> [NSCell] {
        let n = _grid.count
        guard n > 0, _cols > 0 else { return [] }
        let lo = min(max(min(a, b), 0), n - 1), hi = min(max(max(a, b), 0), n - 1)
        if _isSelectionByRect {
            let r0 = min(a, b) / _cols, r1 = max(a, b) / _cols
            let c0 = min(min(max(a, 0), n - 1) % _cols, min(max(b, 0), n - 1) % _cols)
            let c1 = max(min(max(a, 0), n - 1) % _cols, min(max(b, 0), n - 1) % _cols)
            var out: [NSCell] = []
            for r in max(r0, 0)...min(r1, _rows - 1) { for c in c0...c1 { out.append(_grid[r * _cols + c]) } }
            return out
        }
        return Array(_grid[lo...hi])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/setstate(_:atrow:column:)
    @MainActor open func setState(_ value: Int, atRow row: Int, column col: Int) {
        guard let cell = cell(atRow: row, column: col) else { return }
        if _mode == .radioModeMatrix {
            if value != 0 { _applySelection([cell], primary: cell) }
            else if cell === _selectedCell { deselectSelectedCell() }
            else { cell.state = .off }
            return
        }
        cell.state = NSControl.StateValue(rawValue: value)
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/highlightcell(_:atrow:column:)
    @MainActor open func highlightCell(_ flag: Bool, atRow row: Int, column col: Int) {
        guard let cell = cell(atRow: row, column: col) else { return }
        cell.highlight(flag, withFrame: cellFrame(atRow: row, column: col), in: self)
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/keycell
    @MainActor open var keyCell: NSCell? {
        get { _keyCell ?? _selectedCell }
        set { _keyCell = newValue; needsDisplay = true }
    }

    // MARK: Values (the selected cell's, as for any control)

    @MainActor open override var objectValue: Any? {
        get { _selectedCell?.objectValue }
        set { _selectedCell?.objectValue = newValue; needsDisplay = true }
    }
    @MainActor open override var stringValue: String {
        get { _selectedCell?.stringValue ?? "" }
        set { _selectedCell?.stringValue = newValue; needsDisplay = true }
    }
    @MainActor open override var integerValue: Int {
        get { _selectedCell?.integerValue ?? 0 }
        set { _selectedCell?.integerValue = newValue; needsDisplay = true }
    }
    @MainActor open override var intValue: Int32 {
        get { _selectedCell?.intValue ?? 0 }
        set { _selectedCell?.intValue = newValue; needsDisplay = true }
    }
    @MainActor open override var doubleValue: Double {
        get { _selectedCell?.doubleValue ?? 0 }
        set { _selectedCell?.doubleValue = newValue; needsDisplay = true }
    }
    @MainActor open override var floatValue: Float {
        get { _selectedCell?.floatValue ?? 0 }
        set { _selectedCell?.floatValue = newValue; needsDisplay = true }
    }
    /// Enabling the matrix enables every cell, as in AppKit.
    @MainActor open override var isEnabled: Bool {
        get { _isMatrixEnabled }
        set { _isMatrixEnabled = newValue; for c in _grid { c.isEnabled = newValue }; needsDisplay = true }
    }
    @MainActor open override var font: NSFont? {
        get { _grid.first?.font }
        set { for c in _grid { c.font = newValue }; _prototype?.font = newValue; needsDisplay = true }
    }
    @MainActor open override var alignment: NSTextAlignment {
        get { _grid.first?.alignment ?? .natural }
        set { for c in _grid { c.alignment = newValue }; needsDisplay = true }
    }
    @MainActor open override var tag: Int {
        get { _matrixTag }
        set { _matrixTag = newValue }
    }

    // MARK: Target and action

    @MainActor open override var target: AnyObject? {
        get { _matrixTarget }
        set { _matrixTarget = newValue }
    }
    @MainActor open override var action: Selector? {
        get { _matrixAction }
        set { _matrixAction = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/doubleaction
    @MainActor open var doubleAction: Selector? {
        get { _doubleAction }
        set { _doubleAction = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/delegate
    @MainActor open var delegate: (any NSMatrixDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    @MainActor internal override func _fireAction() { _ = sendAction() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/sendaction()
    /// The selected cell's action to its target when it has one, else the matrix's.
    @MainActor open func sendAction() -> Bool {
        guard let cell = _selectedCell, cell.isEnabled else { return false }
        if let a = cell.action { return NSApplication.shared.sendAction(a, to: cell.target, from: self) }
        guard let a = _matrixAction else { return false }
        return NSApplication.shared.sendAction(a, to: _matrixTarget, from: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/sendaction(_:to:forallcells:)
    /// Sends `selector` with each cell (every cell, or the selected ones) to `object`,
    /// stopping when a handler answers false.
    @MainActor open func sendAction(_ selector: Selector, to object: Any, forAllCells flag: Bool) {
        for cell in (flag ? _grid : selectedCells) {
            if let h = object as? NSSelectorHandling {
                if !h.performSelectorAction(selector, with: cell) { return }
            } else if !NSApplication.shared.sendAction(selector, to: object as AnyObject, from: cell) {
                return
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/senddoubleaction()
    @MainActor open func sendDoubleAction() {
        guard let cell = _selectedCell, cell.isEnabled else { return }
        if let d = _doubleAction { _ = NSApplication.shared.sendAction(d, to: _matrixTarget, from: self) } else { _ = sendAction() }
    }

    // MARK: Drawing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/cellbackgroundcolor
    @MainActor open var cellBackgroundColor: NSColor? {
        get { _cellBackgroundColor }
        set { _cellBackgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _drawsBackground }
        set { _drawsBackground = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/drawscellbackground
    @MainActor open var drawsCellBackground: Bool {
        get { _drawsCellBackground }
        set { _drawsCellBackground = newValue; needsDisplay = true }
    }
    @MainActor open override var isOpaque: Bool { _drawsBackground && _backgroundColor.alphaComponent >= 1 }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        if _drawsBackground {
            _backgroundColor.setFill()
            NSBezierPath.fill(dirtyRect)
        }
        for r in 0..<_rows {
            let top = _rowTop(r)
            if top > dirtyRect.maxY { break }
            if top + _rowHeight(r) < dirtyRect.minY { continue }
            for c in 0..<_cols {
                let f = cellFrame(atRow: r, column: c)
                guard f.intersects(dirtyRect) else { continue }
                _drawCell(_grid[r * _cols + c], in: f)
            }
        }
    }

    private func _drawCell(_ cell: NSCell, in frame: NSRect) {
        if _drawsCellBackground, let bg = _cellBackgroundColor {
            bg.setFill()
            NSBezierPath.fill(frame)
        }
        // A highlighted text cell in a list shows the selection behind its text (button
        // and browser cells draw their own highlight).
        if _mode == .listModeMatrix, cell.isHighlighted, !(cell is NSButtonCell), !(cell is NSBrowserCell) {
            NSColor.selectedControlColor.setFill()
            NSBezierPath.fill(frame)
        }
        cell.draw(withFrame: frame, in: self)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/drawcell(atrow:column:)
    @MainActor open func drawCell(atRow row: Int, column col: Int) {
        guard cell(atRow: row, column: col) != nil else { return }
        setNeedsDisplay(cellFrame(atRow: row, column: col))
    }
    @MainActor open override func drawCell(_ cell: NSCell) {
        guard let p = _position(of: cell) else { return }
        drawCell(atRow: p.row, column: p.column)
    }
    @MainActor open override func drawCellInside(_ cell: NSCell) { drawCell(cell) }
    @MainActor open override func updateCell(_ cell: NSCell) { drawCell(cell) }
    @MainActor open override func updateCellInside(_ cell: NSCell) { drawCell(cell) }

    // MARK: Scrolling

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/isautoscroll
    @MainActor open var isAutoscroll: Bool {
        get { _isAutoscroll }
        set { _isAutoscroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/setscrollable(_:)
    @MainActor open func setScrollable(_ flag: Bool) {
        for c in _grid { c.isScrollable = flag }
        _prototype?.isScrollable = flag
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/scrollcelltovisible(atrow:column:)
    @MainActor open func scrollCellToVisible(atRow row: Int, column col: Int) {
        guard cell(atRow: row, column: col) != nil else { return }
        _ = scrollToVisible(cellFrame(atRow: row, column: col))
    }

    // MARK: Mouse

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/acceptsfirstmouse(for:)
    /// A list matrix ignores the click that activates its window, so the click doesn't
    /// change the selection.
    @MainActor open override func acceptsFirstMouse(for event: NSEvent?) -> Bool { _mode != .listModeMatrix }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mousedownflags
    @MainActor open var mouseDownFlags: Int { _mouseDownFlags }

    @MainActor open override var acceptsFirstResponder: Bool {
        _isMatrixEnabled && !refusesFirstResponder && _grid.contains { $0.isEnabled && $0.acceptsFirstResponder }
    }
    @MainActor open override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    @MainActor open override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    private func _isTextEditable(_ cell: NSCell) -> Bool {
        cell.type == .textCellType && (cell.isEditable || cell.isSelectable) && !(cell is NSButtonCell) && !(cell is NSBrowserCell)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mousedown(with:)
    @MainActor open override func mouseDown(with event: NSEvent) {
        _mouseDownFlags = Int(event.modifierFlags.rawValue)
        guard _isMatrixEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        let hit = _cellPosition(at: p)
        if let hit, let cell = cell(atRow: hit.row, column: hit.column), cell.isEnabled, _isTextEditable(cell) {
            _applySelection([cell], primary: cell)
            _beginEditing(cell, event: event, selectAll: false)
            return
        }
        if acceptsFirstResponder, window?.firstResponder !== self { _ = window?.makeFirstResponder(self) }
        guard let hit, let cell = cell(atRow: hit.row, column: hit.column) else {
            if _mode == .listModeMatrix && _allowsEmptySelection && !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.command) {
                _clearSelection()
                _browser?._matrixSelectionChanged(self)
            }
            return
        }
        guard cell.isEnabled else { return }
        if event.clickCount >= 2 {
            if !ignoresMultiClick { _browser != nil ? _browser!._matrixDoubleClicked(self) : sendDoubleAction() }
            return
        }
        _pressedCell = cell
        _anchor = _anchor ?? hit
        switch _mode {
        case .radioModeMatrix:
            cell.isHighlighted = true
            _applySelection([cell], primary: cell)
        case .listModeMatrix:
            let multiple = _listAllowsMultipleSelection
            if multiple && event.modifierFlags.contains(.command) {
                var s = _selection
                if s.contains(where: { $0 === cell }) { s.removeAll { $0 === cell } } else { s.append(cell) }
                if s.isEmpty && !_allowsEmptySelection { return }
                _anchor = hit
                _applySelection(s, primary: s.contains { $0 === cell } ? cell : s.last)
            } else if multiple && event.modifierFlags.contains(.shift), let a = _anchor {
                _applySelection(_cells(from: a.row * _cols + a.column, to: hit.row * _cols + hit.column), primary: cell)
            } else {
                _anchor = hit
                _applySelection([cell], primary: cell)
            }
            _selectionAtPress = _selection
            _browser?._matrixSelectionChanged(self)
        case .highlightModeMatrix:
            cell.isHighlighted = true
            needsDisplay = true
        case .trackModeMatrix:
            _ = cell.startTracking(at: p, in: self)
        }
        if cell.isContinuous { _ = sendAction() }
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard let pressed = _pressedCell else { return }
        let p = convert(event.locationInWindow, from: nil)
        if _isAutoscroll { _ = scrollToVisible(NSRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)) }
        switch _mode {
        case .radioModeMatrix:
            // The selection follows the pointer across the group.
            guard let hit = _cellPosition(at: p), let cell = cell(atRow: hit.row, column: hit.column), cell.isEnabled else { return }
            if cell !== pressed { pressed.isHighlighted = false; cell.isHighlighted = true; _pressedCell = cell; _applySelection([cell], primary: cell) }
        case .listModeMatrix:
            guard let a = _anchor, let hit = _nearestCellPosition(to: p), let cell = cell(atRow: hit.row, column: hit.column) else { return }
            let range = _listAllowsMultipleSelection ? _cells(from: a.row * _cols + a.column, to: hit.row * _cols + hit.column) : [cell]
            let selection = (_listAllowsMultipleSelection && event.modifierFlags.contains(.command))
                ? _selectionAtPress + range.filter { r in !_selectionAtPress.contains { $0 === r } } : range
            if selection.count != _selection.count || zip(selection, _selection).contains(where: { $0 !== $1 }) {
                _applySelection(selection, primary: cell)
                scrollCellToVisible(atRow: hit.row, column: hit.column)
                _browser?._matrixSelectionChanged(self)
            }
        case .highlightModeMatrix:
            let inside = cellFrameContaining(pressed)?.contains(p) ?? false
            if pressed.isHighlighted != inside { pressed.isHighlighted = inside; needsDisplay = true }
        case .trackModeMatrix:
            _ = pressed.continueTracking(last: p, current: p, in: self)
        }
    }

    private func cellFrameContaining(_ cell: NSCell) -> NSRect? {
        guard let pos = _position(of: cell) else { return nil }
        return cellFrame(atRow: pos.row, column: pos.column)
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        guard let pressed = _pressedCell else { return }
        _pressedCell = nil
        let p = convert(event.locationInWindow, from: nil)
        let inside = cellFrameContaining(pressed)?.contains(p) ?? false
        switch _mode {
        case .radioModeMatrix:
            pressed.isHighlighted = false
            needsDisplay = true
            _ = sendAction()
        case .listModeMatrix:
            if let b = _browser { b._matrixClicked(self) } else { _ = sendAction() }
        case .highlightModeMatrix, .trackModeMatrix:
            if _mode == .trackModeMatrix { pressed.stopTracking(last: p, current: p, in: self, mouseIsUp: true) }
            pressed.isHighlighted = false
            if inside {
                pressed.setNextState()
                _selection = [pressed]
                _selectedCell = pressed
                _keyCell = pressed
                _ = sendAction()
            }
            needsDisplay = true
        }
    }

    // MARK: Keyboard

    /// The enabled cell next to (row, col) in a direction, skipping disabled cells.
    private func _neighbor(of pos: (row: Int, column: Int), dRow: Int, dCol: Int) -> (row: Int, column: Int)? {
        var r = pos.row + dRow, c = pos.column + dCol
        while r >= 0, r < _rows, c >= 0, c < _cols {
            if _grid[r * _cols + c].isEnabled { return (r, c) }
            r += dRow; c += dCol
        }
        return nil
    }

    /// Moves the key cell (and in radio and list modes the selection) with the arrow keys.
    internal func _moveSelection(dRow: Int, dCol: Int, extend: Bool) -> Bool {
        guard _rows > 0, _cols > 0 else { return false }
        let start: (row: Int, column: Int)
        if let from = _position(of: keyCell) {
            guard let n = _neighbor(of: from, dRow: dRow, dCol: dCol) else { return false }
            start = n
        } else {
            // Nothing focused yet: the first (or last) enabled cell.
            let forward = dRow + dCol >= 0
            guard let i = forward ? _grid.firstIndex(where: { $0.isEnabled }) : _grid.lastIndex(where: { $0.isEnabled }) else { return false }
            start = (i / _cols, i % _cols)
        }
        let cell = _grid[start.row * _cols + start.column]
        switch _mode {
        case .radioModeMatrix:
            _applySelection([cell], primary: cell)
            _ = sendAction()
        case .listModeMatrix:
            if extend, _listAllowsMultipleSelection, let a = _anchor {
                _applySelection(_cells(from: a.row * _cols + a.column, to: start.row * _cols + start.column), primary: cell)
            } else {
                _anchor = start
                _applySelection([cell], primary: cell)
            }
        case .highlightModeMatrix, .trackModeMatrix:
            _keyCell = cell
            needsDisplay = true
        }
        scrollCellToVisible(atRow: start.row, column: start.column)
        return true
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        if let b = _browser, b._matrixKeyDown(self, event: event) { return }
        guard _isMatrixEnabled, _rows > 0, _cols > 0 else { super.keyDown(with: event); return }
        let extend = event.modifierFlags.contains(.shift)
        switch event.charactersIgnoringModifiers {
        case "\u{F700}": if _moveSelection(dRow: -1, dCol: 0, extend: extend) { return }
        case "\u{F701}": if _moveSelection(dRow: 1, dCol: 0, extend: extend) { return }
        case "\u{F702}": if _moveSelection(dRow: 0, dCol: -1, extend: extend) { return }
        case "\u{F703}": if _moveSelection(dRow: 0, dCol: 1, extend: extend) { return }
        case " ":
            if let cell = keyCell, cell.isEnabled, let p = _position(of: cell) {
                switch _mode {
                case .radioModeMatrix, .listModeMatrix: _applySelection([cell], primary: cell)
                case .highlightModeMatrix, .trackModeMatrix:
                    cell.setNextState(); _selection = [cell]; _selectedCell = cell
                }
                scrollCellToVisible(atRow: p.row, column: p.column)
                needsDisplay = true
                _ = sendAction()
                return
            }
        case "\r", "\u{3}":
            if let cell = keyCell, let p = _position(of: cell), _isTextEditable(cell) { _ = selectText(atRow: p.row, column: p.column); return }
        default: break
        }
        super.keyDown(with: event)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/performkeyequivalent(with:)
    /// Clicks the enabled button cell whose key equivalent matches.
    @MainActor open override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard _isMatrixEnabled, let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        for (i, cell) in _grid.enumerated() where cell.isEnabled {
            guard let b = cell as? NSButtonCell, !b.keyEquivalent.isEmpty, b.keyEquivalent == chars,
                  b.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]) == mods else { continue }
            let r = i / _cols, c = i % _cols
            switch _mode {
            case .radioModeMatrix, .listModeMatrix: selectCell(atRow: r, column: c)
            case .highlightModeMatrix, .trackModeMatrix: cell.setNextState(); _selection = [cell]; _selectedCell = cell; needsDisplay = true
            }
            _ = sendAction()
            return true
        }
        return false
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/tabkeytraversescells
    @MainActor open var tabKeyTraversesCells: Bool {
        get { _tabKeyTraversesCells }
        set { _tabKeyTraversesCells = newValue }
    }

    // MARK: Cursor rects and tool tips

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/resetcursorrects()
    @MainActor open override func resetCursorRects() {
        for r in 0..<_rows {
            for c in 0..<_cols {
                let cell = _grid[r * _cols + c]
                if cell.isEnabled, _isTextEditable(cell) { addCursorRect(_editorFrame(for: cell, in: cellFrame(atRow: r, column: c)), cursor: .iBeam) }
                else { cell.resetCursorRect(cellFrame(atRow: r, column: c), in: self) }
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/settooltip(_:for:)
    @MainActor open func setToolTip(_ toolTipString: String?, for cell: NSCell) {
        _toolTips[ObjectIdentifier(cell)] = toolTipString
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/tooltip(for:)
    @MainActor open func toolTip(for cell: NSCell) -> String? { _toolTips[ObjectIdentifier(cell)] }
    // Requirement of NSViewToolTipOwner
    /// The tool tip of the cell under `point`.
    @MainActor open func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let pos = _cellPosition(at: point), let cell = cell(atRow: pos.row, column: pos.column) else { return "" }
        return toolTip(for: cell) ?? ""
    }

    // MARK: Text editing

    /// Where the field editor goes over a cell.
    internal func _editorFrame(for cell: NSCell, in cellFrame: NSRect) -> NSRect {
        if let f = cell as? NSFormCell { return f._entryTextRect(forBounds: cellFrame) }
        if let t = cell as? NSTextFieldCell { return t._textRect(forBounds: cellFrame) }
        return cell.titleRect(forBounds: cellFrame)
    }
    private func _setHidesText(_ cell: NSCell, _ hides: Bool) {
        if let f = cell as? NSFormCell { f._hidesEntryText = hides }
        else if let t = cell as? NSTextFieldCell { t._hidesText = hides }
    }
    private func _relayoutEditor() {
        guard let editor = _editor, let cell = _editingCell, let p = _position(of: cell) else { return }
        editor.frame = _editorFrame(for: cell, in: cellFrame(atRow: p.row, column: p.column))
    }

    /// Starts editing `cell` in the window's field editor (handing it `event` or
    /// selecting all of its text).
    @discardableResult
    private func _beginEditing(_ cell: NSCell, event: NSEvent?, selectAll: Bool) -> Bool {
        guard let w = window, cell.isEnabled, _isTextEditable(cell), let p = _position(of: cell) else { return false }
        if _editingCell === cell, let editor = _editor {
            if let e = event { editor.mouseDown(with: e) } else if selectAll { editor.selectAll(nil) }
            return true
        }
        _endEditingSession(takeValue: true)
        guard let editor = w.fieldEditor(true, for: self) as? NSTextView else { return false }
        _editingCell = cell
        _editingOriginalValue = cell.objectValue
        _keyCell = cell
        _setHidesText(cell, true)
        editor.string = cell.stringValue
        editor.font = cell.font ?? cell._effectiveFont
        editor.textColor = (cell as? NSTextFieldCell)?.textColor ?? .textColor
        editor.drawsBackground = false
        editor.alignment = cell.alignment
        editor.isEditable = cell.isEditable
        editor.isSelectable = cell.isEditable || cell.isSelectable
        editor.isFieldEditor = true
        editor.delegate = _textDelegate
        editor.frame = _editorFrame(for: cell, in: cellFrame(atRow: p.row, column: p.column))
        editor.autoresizingMask = []
        _editor = editor
        addSubview(editor)
        _handingOffToEditor = true
        let became = w.makeFirstResponder(editor)
        _handingOffToEditor = false
        guard became else { _detachEditor(); return false }
        if let e = event { editor.mouseDown(with: e) } else if selectAll { editor.selectAll(nil) }
        needsDisplay = true
        return true
    }

    private func _detachEditor() {
        guard let editor = _editor else { return }
        editor.delegate = nil
        editor.removeFromSuperview()
        _editor = nil
        if let c = _editingCell { _setHidesText(c, false) }
        _editingCell = nil
        _editingOriginalValue = nil
        needsDisplay = true
    }

    /// Ends any editing session, keeping the editor's text in the cell or not.
    private func _endEditingSession(takeValue: Bool) {
        guard let editor = _editor, let cell = _editingCell else { return }
        if takeValue { cell.stringValue = editor.string }
        let wasFirst = window?.firstResponder === editor
        _detachEditor()
        if wasFirst { _ = window?.makeFirstResponder(self) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selecttext(atrow:column:)
    @MainActor open func selectText(atRow row: Int, column col: Int) -> NSCell? {
        guard let cell = cell(atRow: row, column: col) else { return nil }
        guard _isTextEditable(cell) else { return nil }
        if _selectedCell !== cell { _applySelection([cell], primary: cell) }
        return _beginEditing(cell, event: nil, selectAll: true) ? cell : nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/selecttext(_:)
    /// Edits the key cell's text, or the first editable cell's.
    @MainActor open func selectText(_ sender: Any?) {
        if let k = keyCell, _isTextEditable(k), let p = _position(of: k) { _ = selectText(atRow: p.row, column: p.column); return }
        guard let i = _grid.firstIndex(where: { $0.isEnabled && _isTextEditable($0) }) else { return }
        _ = selectText(atRow: i / _cols, column: i % _cols)
    }
    @MainActor open override func currentEditor() -> NSText? { _editor }
    @MainActor open override func abortEditing() -> Bool {
        guard _editor != nil else { return false }
        if let c = _editingCell { c.objectValue = _editingOriginalValue }
        _endEditingSession(takeValue: false)
        return true
    }
    @MainActor open override func validateEditing() {
        if let editor = _editor, let cell = _editingCell { cell.stringValue = editor.string }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/textshouldbeginediting(_:)
    @MainActor open func textShouldBeginEditing(_ textObject: NSText) -> Bool {
        _delegate?.control(self, textShouldBeginEditing: textObject) ?? true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/textshouldendediting(_:)
    @MainActor open func textShouldEndEditing(_ textObject: NSText) -> Bool {
        _delegate?.control(self, textShouldEndEditing: textObject) ?? true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/textdidbeginediting(_:)
    @MainActor open func textDidBeginEditing(_ notification: Notification) {
        let n = Notification(name: NSControl.textDidBeginEditingNotification, object: self, userInfo: ["NSFieldEditor": notification.object as Any])
        NotificationCenter.default.post(n)
        _delegate?.controlTextDidBeginEditing(n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/textdidchange(_:)
    @MainActor open func textDidChange(_ notification: Notification) {
        if let editor = _editor, let cell = _editingCell, (notification.object as? NSTextView) === editor {
            cell.stringValue = editor.string
        }
        let n = Notification(name: NSControl.textDidChangeNotification, object: self, userInfo: ["NSFieldEditor": notification.object as Any])
        NotificationCenter.default.post(n)
        _delegate?.controlTextDidChange(n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/textdidendediting(_:)
    /// Return keeps the cell editing with its text selected after sending the action;
    /// Tab and Shift-Tab go to the next or previous editable cell (then out of the
    /// matrix); Escape restores the text; anything else ends the session.
    @MainActor open func textDidEndEditing(_ notification: Notification) {
        guard let editor = _editor, let cell = _editingCell, (notification.object as? NSTextView) === editor else { return }
        let raw = notification.userInfo?["NSTextMovement"] as? Int ?? NSTextMovement.other.rawValue
        let movement = NSTextMovement(rawValue: raw) ?? .other
        if movement == .cancel { cell.objectValue = _editingOriginalValue } else { cell.stringValue = editor.string }
        let n = Notification(name: NSControl.textDidEndEditingNotification, object: self, userInfo: ["NSFieldEditor": editor, "NSTextMovement": raw])
        let position = _position(of: cell)
        switch movement {
        case .return:
            _browser?._matrixCellEdited(self, cell: cell)
            _ = sendAction()
            if _editor === editor {
                _editingOriginalValue = cell.objectValue
                editor.selectAll(nil)
                editor._beginEditingIfNeeded()
            }
        case .tab, .backtab:
            _detachEditor()
            _browser?._matrixCellEdited(self, cell: cell)
            let forward = movement == .tab
            if _tabKeyTraversesCells, let pos = position, let next = _nextEditableCell(from: pos.row * _cols + pos.column, forward: forward) {
                _ = selectText(atRow: next / _cols, column: next % _cols)
            } else if let w = window {
                if forward { w.selectKeyView(following: self) } else { w.selectKeyView(preceding: self) }
            }
        default:
            let wasFirst = window?.firstResponder === editor
            _detachEditor()
            if movement != .cancel { _browser?._matrixCellEdited(self, cell: cell) }
            if wasFirst, let w = window { _ = w.makeFirstResponder(movement == .cancel ? self : nil) }
        }
        NotificationCenter.default.post(n)
        _delegate?.controlTextDidEndEditing(n)
    }
    private func _nextEditableCell(from index: Int, forward: Bool) -> Int? {
        var i = index + (forward ? 1 : -1)
        while i >= 0, i < _grid.count {
            if _grid[i].isEnabled, _isTextEditable(_grid[i]) { return i }
            i += forward ? 1 : -1
        }
        return nil
    }

    /// Begins editing the cell at (row, col) for NSBrowser's `editItem(at:with:select:)`.
    internal func _editCell(atRow row: Int, column col: Int, event: NSEvent?, select: Bool) {
        guard let cell = cell(atRow: row, column: col) else { return }
        _beginEditing(cell, event: event, selectAll: select)
    }

    // MARK: Accessibility (ADR-0013)

    open override func accessibilityRole() -> NSAccessibility.Role? {
        _a11y.role ?? (_mode == .radioModeMatrix ? .radioGroup : .group)
    }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : _selectedCell?.stringValue }
}

extension NSMatrix {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mode
    public enum Mode: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mode/highlightmodematrix
        case highlightModeMatrix = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mode/listmodematrix
        case listModeMatrix = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mode/radiomodematrix
        case radioModeMatrix = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmatrix/mode/trackmodematrix
        case trackModeMatrix = 3
        // SKIPPED (constrained extension): func hash(into hasher: inout Hasher)
        // SKIPPED (constrained extension): var hashValue: Int { get }
    }
}
