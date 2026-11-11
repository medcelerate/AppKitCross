// NSGridView (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Rows and columns of cells laid out with Auto Layout, as AppKit does: every column and
// row is a layout guide (a track) chained with the spacing and paddings, sized to its
// content unless given a width or height, and each cell's content view is placed in
// its track (or the tracks of its merged region) by the x and y placements, the row
// alignment, or its own `customPlacementConstraints`. Hidden rows and columns collapse
// to nothing. The constraints are regenerated in `updateConstraints()`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview
@available(macOS 10.12, *)
@MainActor open class NSGridView: NSView {
    private var _rows: [NSGridRow] = []
    private var _columns: [NSGridColumn] = []
    private var _cells: [[NSGridCell]] = []           // [row][column]
    private var _rowSpacing: CGFloat = 6
    private var _columnSpacing: CGFloat = 6
    private var _xPlacement: NSGridCell.Placement = .leading
    private var _yPlacement: NSGridCell.Placement = .top
    private var _rowAlignment: NSGridRow.Alignment = .none
    private var _generated: [NSLayoutConstraint] = []
    private var _customActive: [NSLayoutConstraint] = []
    private var _columnGuides: [NSLayoutGuide] = []
    private var _rowGuides: [NSLayoutGuide] = []

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/sizedforcontent
    static public var sizedForContent: CGFloat { -1 }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/init(numberofcolumns:rows:)
    @MainActor public convenience init(numberOfColumns columnCount: Int, rows rowCount: Int) {
        self.init(frame: .zero)
        for _ in 0..<max(0, columnCount) { _ = addColumn(with: []) }
        for _ in 0..<max(0, rowCount) { _ = addRow(with: []) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/init(views:)
    @MainActor public convenience init(views rows: [[NSView]]) {
        self.init(frame: .zero)
        for r in rows { _ = addRow(with: r) }
    }

    // MARK: Rows and columns

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/numberofrows
    @MainActor open var numberOfRows: Int { _rows.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/numberofcolumns
    @MainActor open var numberOfColumns: Int { _columns.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/row(at:)
    @MainActor open func row(at index: Int) -> NSGridRow { _rows[index] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/column(at:)
    @MainActor open func column(at index: Int) -> NSGridColumn { _columns[index] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/index(of:)
    @MainActor open func index(of row: NSGridRow) -> Int { _rows.firstIndex { $0 === row } ?? NSNotFound }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/index(of:)
    @MainActor open func index(of column: NSGridColumn) -> Int { _columns.firstIndex { $0 === column } ?? NSNotFound }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/addrow(with:)
    @MainActor open func addRow(with views: [NSView]) -> NSGridRow { insertRow(at: _rows.count, with: views) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/insertrow(at:with:)
    ///
    /// More views than columns add columns, as AppKit does.
    @MainActor open func insertRow(at index: Int, with views: [NSView]) -> NSGridRow {
        let index = min(max(0, index), _rows.count)
        while _columns.count < views.count { _appendColumn() }
        let row = NSGridRow()
        row._gridView = self
        _rows.insert(row, at: index)
        var cells: [NSGridCell] = []
        for _ in 0..<_columns.count {
            let cell = NSGridCell()
            cell._gridView = self
            cells.append(cell)
        }
        _cells.insert(cells, at: index)
        _shiftMerges(insertedRow: index)
        for (c, v) in views.enumerated() { _setContent(v, of: cells[c]) }
        _gridChanged()
        return row
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/removerow(at:)
    @MainActor open func removeRow(at index: Int) {
        guard _rows.indices.contains(index) else { return }
        for cell in _cells[index] { _setContent(nil, of: cell); cell._gridView = nil }
        _rows[index]._gridView = nil
        _rows.remove(at: index)
        _cells.remove(at: index)
        _shiftMerges(removedRow: index)
        _gridChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/moverow(at:to:)
    @MainActor open func moveRow(at fromIndex: Int, to toIndex: Int) {
        guard _rows.indices.contains(fromIndex), _rows.indices.contains(toIndex), fromIndex != toIndex else { return }
        let row = _rows.remove(at: fromIndex)
        let cells = _cells.remove(at: fromIndex)
        _rows.insert(row, at: toIndex)
        _cells.insert(cells, at: toIndex)
        _clearMerges()
        _gridChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/addcolumn(with:)
    @MainActor open func addColumn(with views: [NSView]) -> NSGridColumn { insertColumn(at: _columns.count, with: views) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/insertcolumn(at:with:)
    @MainActor open func insertColumn(at index: Int, with views: [NSView]) -> NSGridColumn {
        let index = min(max(0, index), _columns.count)
        while _rows.count < views.count { _ = addRow(with: []) }
        let column = NSGridColumn()
        column._gridView = self
        _columns.insert(column, at: index)
        for r in _cells.indices {
            let cell = NSGridCell()
            cell._gridView = self
            _cells[r].insert(cell, at: index)
        }
        _shiftMerges(insertedColumn: index)
        for (r, v) in views.enumerated() { _setContent(v, of: _cells[r][index]) }
        _gridChanged()
        return column
    }
    private func _appendColumn() {
        let column = NSGridColumn()
        column._gridView = self
        _columns.append(column)
        for r in _cells.indices {
            let cell = NSGridCell()
            cell._gridView = self
            _cells[r].append(cell)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/removecolumn(at:)
    @MainActor open func removeColumn(at index: Int) {
        guard _columns.indices.contains(index) else { return }
        for r in _cells.indices { _setContent(nil, of: _cells[r][index]); _cells[r][index]._gridView = nil; _cells[r].remove(at: index) }
        _columns[index]._gridView = nil
        _columns.remove(at: index)
        _shiftMerges(removedColumn: index)
        _gridChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/movecolumn(at:to:)
    @MainActor open func moveColumn(at fromIndex: Int, to toIndex: Int) {
        guard _columns.indices.contains(fromIndex), _columns.indices.contains(toIndex), fromIndex != toIndex else { return }
        let column = _columns.remove(at: fromIndex)
        _columns.insert(column, at: toIndex)
        for r in _cells.indices {
            let cell = _cells[r].remove(at: fromIndex)
            _cells[r].insert(cell, at: toIndex)
        }
        _clearMerges()
        _gridChanged()
    }

    // MARK: Cells

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/cell(atcolumnindex:rowindex:)
    @MainActor open func cell(atColumnIndex columnIndex: Int, rowIndex: Int) -> NSGridCell { _cells[rowIndex][columnIndex] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/cell(for:)
    @MainActor open func cell(for view: NSView) -> NSGridCell? {
        for row in _cells { for cell in row where cell._contentView === view { return cell } }
        return nil
    }
    /// The row and column of a cell.
    internal func _position(of cell: NSGridCell) -> (row: Int, column: Int)? {
        for (r, row) in _cells.enumerated() { if let c = row.firstIndex(where: { $0 === cell }) { return (r, c) } }
        return nil
    }
    internal func _cell(inRow row: NSGridRow, at column: Int) -> NSGridCell { _cells[index(of: row)][column] }
    internal func _cell(inColumn col: NSGridColumn, at row: Int) -> NSGridCell { _cells[row][index(of: col)] }

    /// Sets a cell's content view, adding it as a subview (the empty content view
    /// stands for none).
    internal func _setContent(_ view: NSView?, of cell: NSGridCell) {
        if let old = cell._contentView, old.superview === self, old !== view { old.removeFromSuperview() }
        let v = view === NSGridCell.emptyContentView ? nil : view
        cell._contentView = v
        if let v {
            v.translatesAutoresizingMaskIntoConstraints = false
            if v.superview !== self { addSubview(v) }
        }
        _gridChanged()
    }

    // MARK: Merging

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/mergecells(inhorizontalrange:verticalrange:)
    ///
    /// The cells of the region become one: the top-leading cell keeps its content and
    /// spans the region, the others lose theirs.
    @MainActor open func mergeCells(inHorizontalRange hRange: NSRange, verticalRange vRange: NSRange) {
        let h = _clamp(hRange, to: _columns.count), v = _clamp(vRange, to: _rows.count)
        guard h.length > 0, v.length > 0 else { return }
        let head = _cells[v.location][h.location]
        for r in v.location..<NSMaxRange(v) {
            for c in h.location..<NSMaxRange(h) {
                let cell = _cells[r][c]
                if cell !== head { _setContent(nil, of: cell) }
                cell._mergeHead = head
            }
        }
        head._mergeHead = head
        head._mergedColumns = h
        head._mergedRows = v
        _gridChanged()
    }
    private func _clamp(_ r: NSRange, to count: Int) -> NSRange {
        let lo = min(max(0, r.location), count)
        let hi = min(max(lo, NSMaxRange(r)), count)
        return NSRange(location: lo, length: hi - lo)
    }
    private func _clearMerges() {
        for row in _cells { for cell in row { cell._mergeHead = nil; cell._mergedColumns = nil; cell._mergedRows = nil } }
    }
    private func _shiftMerges(insertedRow: Int? = nil, removedRow: Int? = nil, insertedColumn: Int? = nil, removedColumn: Int? = nil) {
        // A structural change inside a merged region would split it: AppKit's merged
        // regions are dissolved by structural changes crossing them; here any change
        // that touches a region clears it, the rest shift along.
        for row in _cells {
            for cell in row where cell._mergeHead === cell {
                guard var cols = cell._mergedColumns, var rows = cell._mergedRows else { continue }
                var dissolve = false
                if let i = insertedRow { if i > rows.location && i < NSMaxRange(rows) { dissolve = true } else if i <= rows.location { rows.location += 1 } }
                if let i = removedRow { if i >= rows.location && i < NSMaxRange(rows) { dissolve = true } else if i < rows.location { rows.location -= 1 } }
                if let i = insertedColumn { if i > cols.location && i < NSMaxRange(cols) { dissolve = true } else if i <= cols.location { cols.location += 1 } }
                if let i = removedColumn { if i >= cols.location && i < NSMaxRange(cols) { dissolve = true } else if i < cols.location { cols.location -= 1 } }
                if dissolve {
                    for r in _cells { for c in r where c._mergeHead === cell { c._mergeHead = nil } }
                    cell._mergedColumns = nil
                    cell._mergedRows = nil
                } else {
                    cell._mergedColumns = cols
                    cell._mergedRows = rows
                    for r in _cells { for c in r where c._mergeHead === cell && c !== cell { c._mergeHead = nil } }
                    for r in rows.location..<NSMaxRange(rows) { for c in cols.location..<NSMaxRange(cols) { _cells[r][c]._mergeHead = cell } }
                }
            }
        }
    }

    // MARK: Spacing, placement and alignment

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/rowspacing
    @MainActor open var rowSpacing: CGFloat {
        get { _rowSpacing }
        set { _rowSpacing = newValue; _gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/columnspacing
    @MainActor open var columnSpacing: CGFloat {
        get { _columnSpacing }
        set { _columnSpacing = newValue; _gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/xplacement
    @MainActor open var xPlacement: NSGridCell.Placement {
        get { _xPlacement }
        set { _xPlacement = newValue == .inherited ? .leading : newValue; _gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/yplacement
    @MainActor open var yPlacement: NSGridCell.Placement {
        get { _yPlacement }
        set { _yPlacement = newValue == .inherited ? .top : newValue; _gridChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsgridview/rowalignment
    @MainActor open var rowAlignment: NSGridRow.Alignment {
        get { _rowAlignment }
        set { _rowAlignment = newValue == .inherited ? .none : newValue; _gridChanged() }
    }

    internal func _gridChanged() {
        needsUpdateConstraints = true
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
    internal override func _subviewDidChangeHidden(_ subview: NSView) { if !_applyingHidden { _gridChanged() } }

    // MARK: Layout

    /// The effective placements and alignment of a cell: the cell's, else its column's
    /// or row's, else the grid's.
    private func _xPlacement(of cell: NSGridCell, column: Int) -> NSGridCell.Placement {
        if cell.xPlacement != .inherited { return cell.xPlacement }
        if _columns[column].xPlacement != .inherited { return _columns[column].xPlacement }
        return _xPlacement
    }
    private func _yPlacement(of cell: NSGridCell, row: Int) -> NSGridCell.Placement {
        if cell.yPlacement != .inherited { return cell.yPlacement }
        if _rows[row].yPlacement != .inherited { return _rows[row].yPlacement }
        return _yPlacement
    }
    private func _alignment(of cell: NSGridCell, row: Int) -> NSGridRow.Alignment {
        if cell.rowAlignment != .inherited { return cell.rowAlignment }
        if _rows[row].rowAlignment != .inherited { return _rows[row].rowAlignment }
        return _rowAlignment
    }

    /// The content views in place (the head cells of merged regions, hidden rows and
    /// columns left out), with their tracks.
    private struct _Placed { var cell: NSGridCell; var view: NSView; var columns: NSRange; var rows: NSRange }
    private func _placedCells() -> [_Placed] {
        var out: [_Placed] = []
        for (r, row) in _cells.enumerated() {
            for (c, cell) in row.enumerated() {
                guard let v = cell._contentView, cell._mergeHead == nil || cell._mergeHead === cell else { continue }
                let cols = cell._mergedColumns ?? NSRange(location: c, length: 1)
                let rows = cell._mergedRows ?? NSRange(location: r, length: 1)
                out.append(_Placed(cell: cell, view: v, columns: cols, rows: rows))
            }
        }
        return out
    }
    private func _columnIsHidden(_ c: Int) -> Bool { _columns[c].isHidden }
    private func _rowIsHidden(_ r: Int) -> Bool { _rows[r].isHidden }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/intrinsiccontentsize
    @MainActor open override var intrinsicContentSize: NSSize {
        guard !_rows.isEmpty, !_columns.isEmpty else { return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        // Track sizes from the single-track cells; merged regions only widen the total.
        var widths = _columns.map { $0.width != NSGridView.sizedForContent ? $0.width : 0 }
        var heights = _rows.map { $0.height != NSGridView.sizedForContent ? $0.height : 0 }
        let placed = _placedCells()
        for p in placed where p.columns.length == 1 && _columns[p.columns.location].width == NSGridView.sizedForContent && !p.view.isHidden {
            widths[p.columns.location] = max(widths[p.columns.location], p.view.fittingSize.width)
        }
        for p in placed where p.rows.length == 1 && _rows[p.rows.location].height == NSGridView.sizedForContent && !p.view.isHidden {
            heights[p.rows.location] = max(heights[p.rows.location], p.view.fittingSize.height)
        }
        var w: CGFloat = 0, h: CGFloat = 0
        var visibleColumns = 0, visibleRows = 0
        for (c, col) in _columns.enumerated() where !col.isHidden { w += widths[c] + col.leadingPadding + col.trailingPadding; visibleColumns += 1 }
        for (r, row) in _rows.enumerated() where !row.isHidden { h += heights[r] + row.topPadding + row.bottomPadding; visibleRows += 1 }
        w += CGFloat(max(0, visibleColumns - 1)) * _columnSpacing
        h += CGFloat(max(0, visibleRows - 1)) * _rowSpacing
        return NSSize(width: w, height: h)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updateconstraints()
    @MainActor open override func updateConstraints() {
        for c in _generated { removeConstraint(c) }
        _generated = []
        NSLayoutConstraint.deactivate(_customActive)
        _customActive = []
        for g in _columnGuides + _rowGuides { removeLayoutGuide(g) }
        _columnGuides = []
        _rowGuides = []
        super.updateConstraints()
        guard !_rows.isEmpty, !_columns.isEmpty else { return }

        func anchor(_ item: AnyObject, _ a: NSLayoutConstraint.Attribute) -> NSLayoutAnchor<AnyObject> { NSLayoutAnchor<AnyObject>(item: item, attribute: a) }
        func make(_ a: NSLayoutAnchor<AnyObject>, _ rel: NSLayoutConstraint.Relation, _ b: NSLayoutAnchor<AnyObject>?, constant: CGFloat = 0, priority: NSLayoutConstraint.Priority = .required) {
            let c = NSLayoutConstraint(firstAnchor: a, relation: rel, secondAnchor: b, multiplier: 1, constant: constant)
            c.priority = priority
            c._isInternal = true
            _generated.append(c)
            addConstraint(c)
        }
        // Tracks: a guide per column and per row, chained with the spacing and paddings.
        // Hidden tracks are zero wide and add no spacing. Content-sized tracks hug their
        // content with a weak zero width; the content's compression resistance holds
        // them open.
        for _ in _columns { let g = NSLayoutGuide(); addLayoutGuide(g); _columnGuides.append(g) }
        for _ in _rows { let g = NSLayoutGuide(); addLayoutGuide(g); _rowGuides.append(g) }
        var prev: (guide: NSLayoutGuide, trailingPadding: CGFloat)? = nil
        for (c, col) in _columns.enumerated() {
            let g = _columnGuides[c]
            if col.isHidden {
                make(anchor(g, .width), .equal, nil)
                if let p = prev { make(anchor(g, .leading), .equal, anchor(p.guide, .trailing)) } else { make(anchor(g, .leading), .equal, anchor(self, .leading)) }
                continue
            }
            if let p = prev { make(anchor(g, .leading), .equal, anchor(p.guide, .trailing), constant: p.trailingPadding + _columnSpacing + col.leadingPadding) }
            else { make(anchor(g, .leading), .equal, anchor(self, .leading), constant: col.leadingPadding) }
            if col.width != NSGridView.sizedForContent { make(anchor(g, .width), .equal, nil, constant: max(0, col.width)) }
            else { make(anchor(g, .width), .equal, nil, priority: NSLayoutConstraint.Priority(rawValue: 1)) }
            prev = (g, col.trailingPadding)
        }
        if let p = prev { make(anchor(self, .trailing), .equal, anchor(p.guide, .trailing), constant: p.trailingPadding) }
        else if let last = _columnGuides.last { make(anchor(self, .trailing), .equal, anchor(last, .trailing)) }
        prev = nil
        for (r, row) in _rows.enumerated() {
            let g = _rowGuides[r]
            if row.isHidden {
                make(anchor(g, .height), .equal, nil)
                if let p = prev { make(anchor(g, .top), .equal, anchor(p.guide, .bottom)) } else { make(anchor(g, .top), .equal, anchor(self, .top)) }
                continue
            }
            if let p = prev { make(anchor(g, .top), .equal, anchor(p.guide, .bottom), constant: p.trailingPadding + _rowSpacing + row.topPadding) }
            else { make(anchor(g, .top), .equal, anchor(self, .top), constant: row.topPadding) }
            if row.height != NSGridView.sizedForContent { make(anchor(g, .height), .equal, nil, constant: max(0, row.height)) }
            else { make(anchor(g, .height), .equal, nil, priority: NSLayoutConstraint.Priority(rawValue: 1)) }
            prev = (g, row.bottomPadding)
        }
        if let p = prev { make(anchor(self, .bottom), .equal, anchor(p.guide, .bottom), constant: p.trailingPadding) }
        else if let last = _rowGuides.last { make(anchor(self, .bottom), .equal, anchor(last, .bottom)) }

        // Content views in their tracks.
        var baselineLeaders: [Int: NSView] = [:]
        for p in _placedCells() {
            let v = p.view
            let hidden = (p.columns.location..<NSMaxRange(p.columns)).allSatisfy(_columnIsHidden) || (p.rows.location..<NSMaxRange(p.rows)).allSatisfy(_rowIsHidden)
            if hidden { _hiddenByTrack.insert(ObjectIdentifier(v)); continue }
            _hiddenByTrack.remove(ObjectIdentifier(v))
            if !p.cell.customPlacementConstraints.isEmpty {
                NSLayoutConstraint.activate(p.cell.customPlacementConstraints)
                _customActive += p.cell.customPlacementConstraints
                continue
            }
            let lead = _columnGuides[p.columns.location], trail = _columnGuides[NSMaxRange(p.columns) - 1]
            let top = _rowGuides[p.rows.location], bottom = _rowGuides[NSMaxRange(p.rows) - 1]
            switch _xPlacement(of: p.cell, column: p.columns.location) {
            case .fill:
                make(anchor(v, .leading), .equal, anchor(lead, .leading))
                make(anchor(v, .trailing), .equal, anchor(trail, .trailing))
            case .leading:
                make(anchor(v, .leading), .equal, anchor(lead, .leading))
                make(anchor(v, .trailing), .lessThanOrEqual, anchor(trail, .trailing))
            case .trailing:
                make(anchor(v, .trailing), .equal, anchor(trail, .trailing))
                make(anchor(v, .leading), .greaterThanOrEqual, anchor(lead, .leading))
            case .center:
                make(anchor(v, .leading), .greaterThanOrEqual, anchor(lead, .leading))
                make(anchor(v, .trailing), .lessThanOrEqual, anchor(trail, .trailing))
                if p.columns.length == 1 { make(anchor(v, .centerX), .equal, anchor(lead, .centerX)) }
                else { make(anchor(v, .centerX), .equal, anchor(_regionGuide(lead, trail, horizontal: true), .centerX)) }
            case .none, .inherited:
                break
            }
            let alignment = _alignment(of: p.cell, row: p.rows.location)
            if alignment != .none, p.rows.length == 1 {
                // Baseline rows: every view's baseline meets the first view's in the row.
                let attr: NSLayoutConstraint.Attribute = alignment == .firstBaseline ? .firstBaseline : .lastBaseline
                make(anchor(v, .top), .greaterThanOrEqual, anchor(top, .top))
                make(anchor(v, .bottom), .lessThanOrEqual, anchor(bottom, .bottom))
                if let leader = baselineLeaders[p.rows.location] { make(anchor(v, attr), .equal, anchor(leader, attr)) }
                else {
                    baselineLeaders[p.rows.location] = v
                    make(anchor(v, .top), .equal, anchor(top, .top), priority: .defaultLow)
                }
                continue
            }
            switch _yPlacement(of: p.cell, row: p.rows.location) {
            case .fill:
                make(anchor(v, .top), .equal, anchor(top, .top))
                make(anchor(v, .bottom), .equal, anchor(bottom, .bottom))
            case .leading:   // top
                make(anchor(v, .top), .equal, anchor(top, .top))
                make(anchor(v, .bottom), .lessThanOrEqual, anchor(bottom, .bottom))
            case .trailing:  // bottom
                make(anchor(v, .bottom), .equal, anchor(bottom, .bottom))
                make(anchor(v, .top), .greaterThanOrEqual, anchor(top, .top))
            case .center:
                make(anchor(v, .top), .greaterThanOrEqual, anchor(top, .top))
                make(anchor(v, .bottom), .lessThanOrEqual, anchor(bottom, .bottom))
                if p.rows.length == 1 { make(anchor(v, .centerY), .equal, anchor(top, .centerY)) }
                else { make(anchor(v, .centerY), .equal, anchor(_regionGuide(top, bottom, horizontal: false), .centerY)) }
            case .none, .inherited:
                break
            }
        }
    }
    /// A guide spanning two tracks, for centring in a merged region.
    private func _regionGuide(_ a: NSLayoutGuide, _ b: NSLayoutGuide, horizontal: Bool) -> NSLayoutGuide {
        let g = NSLayoutGuide()
        addLayoutGuide(g)
        if horizontal { _columnGuides.append(g) } else { _rowGuides.append(g) }
        let c1 = NSLayoutConstraint(firstAnchor: NSLayoutAnchor<AnyObject>(item: g, attribute: horizontal ? .leading : .top), relation: .equal, secondAnchor: NSLayoutAnchor<AnyObject>(item: a, attribute: horizontal ? .leading : .top), multiplier: 1, constant: 0)
        let c2 = NSLayoutConstraint(firstAnchor: NSLayoutAnchor<AnyObject>(item: g, attribute: horizontal ? .trailing : .bottom), relation: .equal, secondAnchor: NSLayoutAnchor<AnyObject>(item: b, attribute: horizontal ? .trailing : .bottom), multiplier: 1, constant: 0)
        for c in [c1, c2] { c._isInternal = true; _generated.append(c); addConstraint(c) }
        return g
    }

    /// Content views of hidden rows and columns are hidden with them, and shown again
    /// when the track is; a view the application hid itself stays hidden.
    private var _hiddenByTrack = Set<ObjectIdentifier>()     // content in a hidden row or column
    private var _hiddenByGrid = Set<ObjectIdentifier>()      // ... that the grid hid (not the application)
    private var _applyingHidden = false
    @MainActor open override func layout() {
        super.layout()
        _applyingHidden = true
        defer { _applyingHidden = false }
        for p in _placedCells() {
            let id = ObjectIdentifier(p.view)
            if _hiddenByTrack.contains(id) {
                if !p.view.isHidden { _hiddenByGrid.insert(id); p.view.isHidden = true }
            } else if _hiddenByGrid.contains(id) {
                _hiddenByGrid.remove(id)
                p.view.isHidden = false
            }
        }
    }
}
