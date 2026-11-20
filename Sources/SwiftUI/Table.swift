// Table over NSTableView: the SwiftUI Table's rows, columns, selection and sort order
// drive a real table view, whose cells host the column content as SwiftUI views.

import Foundation

/// The erased pieces of a Table the primitive needs.
struct _TableModel {
    struct Column {
        let title: String
        let width: _TableColumnWidth
        let sortable: Bool
    }
    let rowIDs: [AnyHashable]
    let columns: [Column]
    let cell: (_ row: Int, _ column: Int) -> AnyView
    let selection: _ListSelection?
    /// The sorted column and direction, when the table sorts.
    let sort: (column: Int, ascending: Bool)?
    /// Called when a header is clicked; the table owner flips its sort order binding.
    let onSort: ((Int) -> Void)?
}

struct _NativeTable: View, _PrimitiveView {
    typealias Body = Never
    let model: _TableModel
    func _makePrimitive(node: _ViewNode) -> _Primitive { _NSTablePrimitive(model: model) }
}

/// Sort descriptors that identify a column by index on every Foundation: Apple's take a
/// key string, swift-corelibs-foundation a key path (into an array, one per index).
@MainActor
enum _ColumnSort {
    static func descriptor(column: Int, ascending: Bool) -> NSSortDescriptor {
        #if canImport(Darwin)
        return NSSortDescriptor(key: "column\(column)", ascending: ascending)
        #else
        return NSSortDescriptor(keyPath: \[Int].[column], ascending: ascending)
        #endif
    }
    static func column(of descriptor: NSSortDescriptor, count: Int) -> Int? {
        #if canImport(Darwin)
        guard let key = descriptor.key, key.hasPrefix("column"), let i = Int(key.dropFirst(6)) else { return nil }
        return i
        #else
        return (0..<count).first { descriptor.keyPath == (\[Int].[$0] as AnyKeyPath) }
        #endif
    }
}

/// Data source and delegate of the table view, kept apart from the primitive so the
/// table view's weak references have an NSObject to hold.
@MainActor
final class _TableBridge: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var model: _TableModel
    weak var table: NSTableView?
    /// Set while the primitive pushes state into the table, so callbacks do not echo it.
    var updating = false
    private static let cellID = NSUserInterfaceItemIdentifier("SwiftUI.TableCell")
    /// The leading inset of each cell's content (see `tableView(_:viewFor:row:)`).
    static let cellLeadingPadding: CGFloat = 4
    /// Rows are never shorter than this, and get this much room around their tallest cell.
    static let minimumRowHeight: CGFloat = 20
    static let rowPadding: CGFloat = 6

    /// False until the primitive is attached to a node: a primitive made only to hand its
    /// model to the live one (`update(from:)`) answers the table's default row height
    /// instead of measuring every row.
    var measures = false
    /// Measured row heights, by row, for the column widths in `measuredWidths`.
    private var heights: [Int: CGFloat] = [:]
    private(set) var measuredWidths: [CGFloat] = []
    /// One reusable probe per column, so measuring a row does not build hosting views.
    private var probes: [Int: NSHostingView<AnyView>] = [:]

    init(model: _TableModel) { self.model = model }

    /// Forgets the measured heights (the model or the column widths changed).
    func invalidateHeights(dropProbes: Bool = false) {
        heights.removeAll(keepingCapacity: true)
        measuredWidths = []
        if dropProbes { probes.removeAll() }
    }

    /// The widths cells are laid out at, in column order (hidden columns count as zero).
    static func columnWidths(of tableView: NSTableView) -> [CGFloat] {
        tableView.tableColumns.map { $0.isHidden ? 0 : $0.width }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { model.rowIDs.count }

    /// Each row is as tall as its tallest cell measured at its column's width, so wrapped
    /// text grows the row instead of overdrawing its neighbours.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard measures, row >= 0, row < model.rowIDs.count, !model.columns.isEmpty else { return tableView.rowHeight }
        let widths = _TableBridge.columnWidths(of: tableView)
        if widths != measuredWidths { heights.removeAll(keepingCapacity: true); measuredWidths = widths }
        if let h = heights[row] { return h }
        var tallest: CGFloat = 0
        for (c, width) in widths.enumerated() where c < model.columns.count && width > 0 {
            // The probe holds exactly what the cell shows and is offered the cell's frame
            // width (the column's, see NSTableView's cell frames), so the row is measured
            // the way its cell lays out: measuring the bare content at a different width
            // left a cell that wrapped inside a one-line row.
            let content = cellContent(row: row, column: c)
            let probe: NSHostingView<AnyView>
            if let p = probes[c] { p.rootView = content; probe = p }
            else { probe = NSHostingView(rootView: content); probes[c] = probe }
            tallest = max(tallest, probe.sizeThatFits(NSHostingSizeProposal(width: width, height: nil)).height)
        }
        let h = max(_TableBridge.minimumRowHeight, tallest.rounded(.up) + _TableBridge.rowPadding)
        heights[row] = h
        return h
    }

    /// What a cell hosts: the column content at the cell's leading edge, as SwiftUI lays
    /// table cells out. A leading-aligned flexible frame rather than an HStack with a
    /// Spacer: the stack offers its least flexible child an equal share first, so a text
    /// beside a spacer got half the column and wrapped although the column fitted it.
    func cellContent(row: Int, column: Int) -> AnyView {
        AnyView(model.cell(row, column)
            .padding(.leading, _TableBridge.cellLeadingPadding)
            .frame(maxWidth: .infinity, alignment: .leading))
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = tableView.tableColumns.firstIndex(where: { $0 === tableColumn }), row < model.rowIDs.count else { return nil }
        let content = cellContent(row: row, column: column)
        if let v = tableView.makeView(withIdentifier: _TableBridge.cellID, owner: nil) as? NSHostingView<AnyView> {
            v.rootView = content
            return v
        }
        let v = NSHostingView(rootView: content)
        v.identifier = _TableBridge.cellID
        return v
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updating, let table, let selection = model.selection else { return }
        let ids = Set(table.selectedRowIndexes.compactMap { model.rowIDs.indices.contains($0) ? model.rowIDs[$0] : nil })
        selection.set(ids)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !updating, let first = tableView.sortDescriptors.first, let column = _ColumnSort.column(of: first, count: model.columns.count) else { return }
        model.onSort?(column)
    }
}

@MainActor
final class _NSTablePrimitive: _ControlPrimitive<NSScrollView> {
    let table = NSTableView(frame: .zero)
    let bridge: _TableBridge
    /// The default row height, answered before the rows are measured.
    private var rowHeight: CGFloat = 24
    private var resizeObserver: NSObjectProtocol?

    init(model: _TableModel) {
        bridge = _TableBridge(model: model)
        let scroll = NSScrollView(frame: .zero)
        super.init(control: scroll)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        bridge.table = table
        table.dataSource = bridge
        table.delegate = bridge
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        apply(model, columnsChanged: true)
    }

    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _NSTablePrimitive else { return }
        let columnsChanged = o.bridge.model.columns.map(\.title) != bridge.model.columns.map(\.title) || o.bridge.model.columns.count != bridge.model.columns.count
        bridge.model = o.bridge.model
        // A new model may change any cell's content: the rows are measured again as the
        // table asks for them.
        bridge.invalidateHeights(dropProbes: columnsChanged)
        apply(o.bridge.model, columnsChanged: columnsChanged)
    }

    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        guard !bridge.measures else { return }
        bridge.measures = true
        bridge.invalidateHeights()
        noteAllRowHeightsChanged()
        // A column resized by the user, or by autoresizing as the table follows its scroll
        // view, rewraps its cells: the rows are measured again.
        resizeObserver = NotificationCenter.default.addObserver(forName: NSTableView.columnDidResizeNotification, object: table, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.columnsDidResize() }
        }
    }

    override func detach() {
        if let o = resizeObserver { NotificationCenter.default.removeObserver(o); resizeObserver = nil }
        super.detach()
    }

    /// A backstop for widths that changed without a notification: once the scroll view
    /// has its frame, compare with the widths the heights were measured at.
    override func didSyncBackingViews(node: _ViewNode) {
        super.didSyncBackingViews(node: node)
        if bridge.measures, !bridge.measuredWidths.isEmpty { columnsDidResize() }
    }

    /// Re-measures the rows unless they were measured at the current widths (autoresizing
    /// posts one notification per column; the first re-measures at the final widths).
    private func columnsDidResize() {
        guard bridge.measuredWidths != _TableBridge.columnWidths(of: table) else { return }
        bridge.invalidateHeights()
        noteAllRowHeightsChanged()
    }

    private func noteAllRowHeightsChanged() {
        let n = table.numberOfRows
        if n > 0 { table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<n)) }
    }

    private func apply(_ model: _TableModel, columnsChanged: Bool) {
        bridge.updating = true
        defer { bridge.updating = false }
        if columnsChanged {
            for c in table.tableColumns { table.removeTableColumn(c) }
            for (i, c) in model.columns.enumerated() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column\(i)"))
                column.title = c.title
                if let w = c.width.fixed { column.width = w; column.minWidth = w; column.maxWidth = w; column.resizingMask = [] }
                else {
                    if let mn = c.width.min { column.minWidth = mn }
                    if let mx = c.width.max { column.maxWidth = mx }
                    column.width = c.width.min ?? 100
                }
                if c.sortable { column.sortDescriptorPrototype = _ColumnSort.descriptor(column: i, ascending: true) }
                table.addTableColumn(column)
            }
        }
        table.allowsMultipleSelection = model.selection?.allowsMultiple ?? false
        table.allowsEmptySelection = true
        if let sort = model.sort, table.tableColumns.indices.contains(sort.column) {
            table.sortDescriptors = [_ColumnSort.descriptor(column: sort.column, ascending: sort.ascending)]
            table.highlightedTableColumn = table.tableColumns[sort.column]
        } else {
            table.sortDescriptors = []
            table.highlightedTableColumn = nil
        }
        if table.rowHeight != rowHeight { table.rowHeight = rowHeight }
        table.reloadData()
        if let selection = model.selection {
            let ids = selection.get()
            let rows = IndexSet(model.rowIDs.indices.filter { ids.contains(model.rowIDs[$0]) })
            if rows != table.selectedRowIndexes { table.selectRowIndexes(rows, byExtendingSelection: false) }
        }
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 400
        // The rows' real heights (each row as the delegate measured it), plus the header.
        let rows = table.numberOfRows
        let rowsHeight = rows > 0 ? table.rect(ofRow: rows - 1).maxY + table.intercellSpacing.height : 0
        let natural = rowsHeight + (table.headerView?.frame.height ?? 23) + 4
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? min(natural, 400)
        return CGSize(width: width, height: height)
    }
}
