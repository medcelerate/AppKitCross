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

    init(model: _TableModel) { self.model = model }

    func numberOfRows(in tableView: NSTableView) -> Int { model.rowIDs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = tableView.tableColumns.firstIndex(where: { $0 === tableColumn }), row < model.rowIDs.count else { return nil }
        // Cells sit at the leading edge of their column, as SwiftUI lays them out.
        let content = AnyView(HStack(spacing: 0) { model.cell(row, column); Spacer(minLength: 0) }.padding(.leading, 4))
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
    private var rowHeight: CGFloat = 24

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
        apply(o.bridge.model, columnsChanged: columnsChanged)
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
        measureRowHeight(model)
        table.reloadData()
        if let selection = model.selection {
            let ids = selection.get()
            let rows = IndexSet(model.rowIDs.indices.filter { ids.contains(model.rowIDs[$0]) })
            if rows != table.selectedRowIndexes { table.selectRowIndexes(rows, byExtendingSelection: false) }
        }
    }

    /// Rows are as tall as the first row's tallest cell, plus padding.
    private func measureRowHeight(_ model: _TableModel) {
        guard !model.rowIDs.isEmpty, !model.columns.isEmpty else { return }
        var h: CGFloat = 0
        for c in model.columns.indices {
            let probe = NSHostingView(rootView: model.cell(0, c))
            let s = probe.sizeThatFits(.unspecified)
            h = max(h, s.height)
        }
        let height = max(20, h.rounded(.up) + 6)
        if height != rowHeight { rowHeight = height; table.rowHeight = height }
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 400
        let natural = CGFloat(bridge.model.rowIDs.count) * (rowHeight + table.intercellSpacing.height) + (table.headerView?.frame.height ?? 23) + 4
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? min(natural, 400)
        return CGSize(width: width, height: height)
    }
}
