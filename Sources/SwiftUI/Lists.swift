// List with selection, and Table: rows in a scroll view with a selection highlight, mouse and
// keyboard selection, and a selection binding (single value or set) kept in step.

import Foundation

// MARK: Selection

/// A type-erased list selection: the selected row values, and how to write them back.
struct _ListSelection {
    let get: () -> Set<AnyHashable>
    let set: (Set<AnyHashable>) -> Void
    let allowsMultiple: Bool

    init<V: Hashable>(single binding: Binding<V?>) {
        get = { binding.wrappedValue.map { [AnyHashable($0)] } ?? [] }
        set = { values in
            let v = values.first?.base as? V
            if binding.wrappedValue != v { binding.wrappedValue = v }
        }
        allowsMultiple = false
    }
    init<V: Hashable>(multiple binding: Binding<Set<V>>) {
        get = { Set(binding.wrappedValue.map { AnyHashable($0) }) }
        set = { values in
            let v = Set(values.compactMap { $0.base as? V })
            if binding.wrappedValue != v { binding.wrappedValue = v }
        }
        allowsMultiple = true
    }
}

// MARK: List

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/list
public struct List<SelectionValue: Hashable, Content: View>: View {
    let content: Content
    let selection: _ListSelection?

    public init(@ViewBuilder content: () -> Content) where SelectionValue == Never { self.content = content(); selection = nil }
    public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) {
        self.content = content(); self.selection = selection.map { _ListSelection(single: $0) }
    }
    public init(selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content) {
        self.content = content(); self.selection = selection.map { _ListSelection(multiple: $0) }
    }
    public var body: some View {
        ScrollView {
            _ListRows(content: content, selection: selection, rowInset: 10, rowPadding: 6)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

extension List where SelectionValue == Never {
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {
        content = ForEach(data, content: rowContent); selection = nil
    }
    public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent> {
        content = ForEach(data, id: id, content: rowContent); selection = nil
    }
}

extension List {
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable, Data.Element.ID == SelectionValue {
        content = ForEach(data, content: rowContent); self.selection = selection.map { _ListSelection(single: $0) }
    }
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable, Data.Element.ID == SelectionValue {
        content = ForEach(data, content: rowContent); self.selection = selection.map { _ListSelection(multiple: $0) }
    }
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, SelectionValue>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, SelectionValue, RowContent> {
        content = ForEach(data, id: id, content: rowContent); self.selection = selection.map { _ListSelection(single: $0) }
    }
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, id: KeyPath<Data.Element, SelectionValue>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, SelectionValue, RowContent> {
        content = ForEach(data, id: id, content: rowContent); self.selection = selection.map { _ListSelection(multiple: $0) }
    }
}

// MARK: Rows

/// A view whose body contributes rows to a List one by one (OutlineGroup), instead of
/// being one row itself.
protocol _ListRowsProvider {}

/// Rows stacked with padding, separators and a selection highlight.
struct _ListRows<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let selection: _ListSelection?
    let rowInset: CGFloat
    let rowPadding: CGFloat
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _ListRowsPrimitive(content: _ViewBox(content), selection: selection, rowInset: rowInset, rowPadding: rowPadding)
    }
}

/// The view behind the rows: draws separators and the selection, takes clicks and keys.
@MainActor
final class _ListView: NSView, NSSelectorHandling {
    var rowFrames: [CGRect] = []
    var selectedRows: Set<Int> = []
    var emphasized = true
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onArrow: ((Int, Bool) -> Void)?       // delta, extend
    var onSelectAll: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { onClick != nil }

    override func draw(_ dirtyRect: NSRect) {
        for i in selectedRows where rowFrames.indices.contains(i) {
            (emphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
            NSBezierPath.fill(rowFrames[i])
        }
        NSColor.separatorColor.setFill()
        for (i, f) in rowFrames.enumerated().dropLast() where !selectedRows.contains(i) || !selectedRows.contains(i + 1) {
            NSBezierPath.fill(NSRect(x: f.minX, y: f.maxY, width: f.width, height: 1))
        }
    }
    func row(at point: NSPoint) -> Int? { rowFrames.firstIndex { $0.contains(point) } }

    override func mouseDown(with event: NSEvent) {
        guard let onClick else { super.mouseDown(with: event); return }
        // A click anywhere in a row (also on a row's own views) focuses the list for the keys.
        if let w = window, w.firstResponder !== self { _ = w.makeFirstResponder(self) }
        if let i = row(at: convert(event.locationInWindow, from: nil)) { onClick(i, event.modifierFlags) }
    }
    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 125: onArrow?(1, extend)
        case 126: onArrow?(-1, extend)
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a", let onSelectAll { onSelectAll() }
            else { super.keyDown(with: event) }
        }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    /// The Edit menu's Select All (Cmd-A as a key equivalent) reaches the focused list.
    func respondsToSelectorAction(_ action: Selector) -> Bool { action == Selector(("selectAll:")) && onSelectAll != nil }
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action == Selector(("selectAll:")), let onSelectAll else { return false }
        onSelectAll()
        return true
    }
}

@MainActor
final class _ListRowsPrimitive: _Primitive {
    let view = _ListView(frame: .zero)
    var selection: _ListSelection?
    let rowInset: CGFloat
    let rowPadding: CGFloat
    private var rowValues: [AnyHashable] = []
    private var rowNodes: [_ViewNode] = []
    private var anchor: Int?

    init(content: _AnyViewBox, selection: _ListSelection?, rowInset: CGFloat, rowPadding: CGFloat) {
        self.selection = selection
        self.rowInset = rowInset
        self.rowPadding = rowPadding
        super.init()
        children = [content]
        wireView()
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _ListRowsPrimitive else { return }
        selection = o.selection
        wireView()
    }
    private func wireView() {
        guard selection != nil else { view.onClick = nil; view.onArrow = nil; view.onSelectAll = nil; return }
        view.onClick = { [weak self] i, flags in self?.click(i, flags) }
        view.onArrow = { [weak self] delta, extend in self?.arrow(delta, extend: extend) }
        view.onSelectAll = { [weak self] in
            guard let self, let sel = self.selection, sel.allowsMultiple else { return }
            sel.set(Set(self.rowValues))
        }
    }

    /// The rows: direct items of the content, through groups, ForEach and views that
    /// declare themselves row providers (OutlineGroup), stopping at tagged items so a
    /// row's tag is its selection value.
    private func collectRows(_ node: _ViewNode, into out: inout [_ViewNode]) {
        for c in node.children {
            if c.box.value is _MetadataView { out.append(c); continue }
            if let p = c.primitive, p.isLayoutTransparent { collectRows(c, into: &out) }
            else if c.primitive == nil, c.box.value is any _ListRowsProvider { collectRows(c, into: &out) }
            else { out.append(c) }
        }
    }
    private func rows(_ node: _ViewNode) -> [_ViewNode] {
        var out: [_ViewNode] = []
        collectRows(node, into: &out)
        return out
    }
    private func value(of row: _ViewNode, index: Int) -> AnyHashable {
        _metadata(of: row.box).meta.tag ?? row.box.id ?? AnyHashable(index)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        var height: CGFloat = 0
        var width: CGFloat = 0
        for r in rows(node) {
            let s = r.sizeThatFits(ProposedViewSize(width: proposal.width.map { max(0, $0 - 2 * rowInset) }, height: nil))
            height += s.height + 2 * rowPadding + 1
            width = max(width, s.width + 2 * rowInset)
        }
        return CGSize(width: proposal.width.map { $0.isFinite ? max($0, width) : width } ?? width, height: height)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        var y = rect.minY
        var frames: [CGRect] = []
        let nodes = rows(node)
        rowNodes = nodes
        rowValues = nodes.enumerated().map { value(of: $1, index: $0) }
        for r in nodes {
            let s = r.sizeThatFits(ProposedViewSize(width: rect.width - 2 * rowInset, height: nil))
            let rowHeight = s.height + 2 * rowPadding
            r.place(in: CGRect(x: rect.minX + rowInset, y: y + rowPadding, width: rect.width - 2 * rowInset, height: s.height).integralIfNeeded)
            frames.append(CGRect(x: 0, y: y - rect.minY, width: rect.width, height: rowHeight))
            y += rowHeight + 1
        }
        view.rowFrames = frames
        refreshHighlight()
    }
    override func didSyncBackingViews(node: _ViewNode) { refreshHighlight() }

    /// Mirrors the binding into the view and the row texts.
    private func refreshHighlight() {
        let selected = selection?.get() ?? []
        let indices = Set(rowValues.indices.filter { selected.contains(rowValues[$0]) })
        view.selectedRows = indices
        view.emphasized = view.window?.isKeyWindow ?? true
        for (i, r) in rowNodes.enumerated() {
            var views: [NSView] = []
            r.collectBackingViews(into: &views)
            for v in views { setSelected(indices.contains(i), in: v) }
        }
        view.needsDisplay = true
    }
    private func setSelected(_ on: Bool, in v: NSView) {
        if let t = v as? _TextView { t.isInSelectedRow = on }
        for s in v.subviews { setSelected(on, in: s) }
    }

    // MARK: Selecting

    private func click(_ i: Int, _ flags: NSEvent.ModifierFlags) {
        guard let sel = selection, rowValues.indices.contains(i) else { return }
        let v = rowValues[i]
        if sel.allowsMultiple, flags.contains(.command) {
            var s = sel.get()
            if s.contains(v) { s.remove(v) } else { s.insert(v) }
            sel.set(s)
            anchor = i
        } else if sel.allowsMultiple, flags.contains(.shift), let a = anchor {
            // Shift extends: the rows between the anchor and the click join what is selected.
            sel.set(sel.get().union(rowValues[min(a, i)...max(a, i)]))
        } else {
            sel.set([v])
            anchor = i
        }
    }
    private func arrow(_ delta: Int, extend: Bool) {
        guard let sel = selection, !rowValues.isEmpty else { return }
        let selected = sel.get()
        let current = rowValues.indices.filter { selected.contains(rowValues[$0]) }
        let from = delta > 0 ? (current.max() ?? -1) : (current.min() ?? rowValues.count)
        let next = min(max(from + delta, 0), rowValues.count - 1)
        if extend, sel.allowsMultiple {
            let a = anchor ?? from
            sel.set(selected.union(rowValues[min(a, next)...max(a, next)]))
        } else {
            sel.set([rowValues[next]])
            anchor = next
        }
    }
}

// MARK: Table columns

/// A table column erased to what the table needs: a title, a cell factory, a width and
/// an optional sort comparator factory.
public struct _AnyTableColumn<RowValue> {
    let title: String
    let makeCell: (RowValue) -> AnyView
    var width: CGFloat?
    var minWidth: CGFloat?
    var maxWidth: CGFloat?
    let sortKeyPath: PartialKeyPath<RowValue>?
    let comparator: ((SortOrder) -> KeyPathComparator<RowValue>)?
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tablecolumncontent
public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
    associatedtype TableRowValue: Identifiable
    associatedtype TableColumnSortComparator: SortComparator
    var _columns: [_AnyTableColumn<TableRowValue>] { get }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tablecolumn
public struct TableColumn<RowValue: Identifiable, Sort: SortComparator, Content: View, Label: View>: TableColumnContent {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    var column: _AnyTableColumn<RowValue>
    public var _columns: [_AnyTableColumn<RowValue>] { [column] }
    init(_erased column: _AnyTableColumn<RowValue>) { self.column = column }

    public init(_ title: String, value: KeyPath<RowValue, String>) where Sort == KeyPathComparator<RowValue>, Content == Text, Label == Text {
        column = _AnyTableColumn(title: title, makeCell: { AnyView(Text($0[keyPath: value])) }, sortKeyPath: value,
                                 comparator: { KeyPathComparator(value, order: $0) })
    }
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>) where Sort == KeyPathComparator<RowValue>, Content == Text, Label == Text {
        self.init(titleKey.key, value: value)
    }
    public init<V: Comparable>(_ title: String, value: KeyPath<RowValue, V>, @ViewBuilder content: @escaping (RowValue) -> Content) where Sort == KeyPathComparator<RowValue>, Label == Text {
        column = _AnyTableColumn(title: title, makeCell: { AnyView(content($0)) }, sortKeyPath: value,
                                 comparator: { KeyPathComparator(value, order: $0) })
    }
    public init(_ title: String, @ViewBuilder content: @escaping (RowValue) -> Content) where Sort == Never, Label == Text {
        column = _AnyTableColumn(title: title, makeCell: { AnyView(content($0)) }, sortKeyPath: nil, comparator: nil)
    }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping (RowValue) -> Content) where Sort == Never, Label == Text {
        self.init(titleKey.key, content: content)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/tablecolumn/width(_:)
    public func width(_ width: CGFloat? = nil) -> TableColumn { var c = self; c.column.width = width; return c }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/tablecolumn/width(min:ideal:max:)
    public func width(min: CGFloat? = nil, ideal: CGFloat? = nil, max: CGFloat? = nil) -> TableColumn {
        var c = self; c.column.minWidth = min; c.column.maxWidth = max; if let ideal { c.column.width = ideal }; return c
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tupletablecolumncontent
public struct TupleTableColumnContent<RowValue: Identifiable, Sort: SortComparator, T>: TableColumnContent {
    public typealias TableRowValue = RowValue
    public typealias TableColumnSortComparator = Sort
    public var value: T
    public var _columns: [_AnyTableColumn<RowValue>]
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tablecolumnbuilder
@resultBuilder
public struct TableColumnBuilder<RowValue: Identifiable, Sort: SortComparator> {
    /// Pins the row type so `\.name` in a column resolves against it.
    public static func buildExpression<Content: View, Label: View>(_ column: TableColumn<RowValue, Sort, Content, Label>) -> TableColumn<RowValue, Sort, Content, Label> { column }
    /// An unsortable column inside a sortable table.
    public static func buildExpression<Content: View, Label: View>(_ column: TableColumn<RowValue, Never, Content, Label>) -> TableColumn<RowValue, Sort, Content, Label>
    where Sort == KeyPathComparator<RowValue> {
        TableColumn(_erased: column.column)
    }
    public static func buildBlock<C: TableColumnContent>(_ c: C) -> C where C.TableRowValue == RowValue { c }
    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent>(_ c0: C0, _ c1: C1) -> TupleTableColumnContent<RowValue, Sort, (C0, C1)>
    where C0.TableRowValue == RowValue, C1.TableRowValue == RowValue {
        TupleTableColumnContent(value: (c0, c1), _columns: c0._columns + c1._columns)
    }
    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2)>
    where C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue {
        TupleTableColumnContent(value: (c0, c1, c2), _columns: c0._columns + c1._columns + c2._columns)
    }
    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3)>
    where C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue {
        TupleTableColumnContent(value: (c0, c1, c2, c3), _columns: c0._columns + c1._columns + c2._columns + c3._columns)
    }
    public static func buildBlock<C0: TableColumnContent, C1: TableColumnContent, C2: TableColumnContent, C3: TableColumnContent, C4: TableColumnContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleTableColumnContent<RowValue, Sort, (C0, C1, C2, C3, C4)>
    where C0.TableRowValue == RowValue, C1.TableRowValue == RowValue, C2.TableRowValue == RowValue, C3.TableRowValue == RowValue, C4.TableRowValue == RowValue {
        TupleTableColumnContent(value: (c0, c1, c2, c3, c4), _columns: c0._columns + c1._columns + c2._columns + c3._columns + c4._columns)
    }
}

// MARK: Table rows

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tablerowcontent
public protocol TableRowContent<TableRowValue> {
    associatedtype TableRowValue: Identifiable
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tableforeachcontent
public struct TableForEachContent<Data: RandomAccessCollection>: TableRowContent where Data.Element: Identifiable {
    public typealias TableRowValue = Data.Element
    let data: Data
}

// MARK: Table

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/table
public struct Table<Value: Identifiable, Rows: TableRowContent, Columns: TableColumnContent>: View where Rows.TableRowValue == Value, Columns.TableRowValue == Value {
    let rows: [Value]
    let columns: [_AnyTableColumn<Value>]
    let selection: _ListSelection?
    let sortOrder: Binding<[KeyPathComparator<Value>]>?

    public init<Data: RandomAccessCollection>(_ data: Data, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        rows = Array(data); self.columns = columns()._columns; selection = nil; sortOrder = nil
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Value.ID?>, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        rows = Array(data); self.columns = columns()._columns; self.selection = _ListSelection(single: selection); sortOrder = nil
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Set<Value.ID>>, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == Never {
        rows = Array(data); self.columns = columns()._columns; self.selection = _ListSelection(multiple: selection); sortOrder = nil
    }
    public init<Data: RandomAccessCollection>(_ data: Data, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == KeyPathComparator<Value> {
        rows = Array(data); self.columns = columns()._columns; selection = nil; self.sortOrder = sortOrder
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Value.ID?>, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == KeyPathComparator<Value> {
        rows = Array(data); self.columns = columns()._columns; self.selection = _ListSelection(single: selection); self.sortOrder = sortOrder
    }
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Set<Value.ID>>, sortOrder: Binding<[KeyPathComparator<Value>]>, @TableColumnBuilder<Value, KeyPathComparator<Value>> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns.TableColumnSortComparator == KeyPathComparator<Value> {
        rows = Array(data); self.columns = columns()._columns; self.selection = _ListSelection(multiple: selection); self.sortOrder = sortOrder
    }

    public var body: some View {
        let cols = columns
        let sort = sortOrder
        var sortState: (column: Int, ascending: Bool)? = nil
        if let s = sort?.wrappedValue.first, let i = cols.firstIndex(where: { $0.sortKeyPath == s.keyPath }) {
            sortState = (i, s.order == .forward)
        }
        let model = _TableModel(
            rowIDs: rows.map { AnyHashable($0.id) },
            columns: cols.map { _TableModel.Column(title: $0.title, width: _TableColumnWidth(fixed: $0.width, min: $0.minWidth, max: $0.maxWidth), sortable: $0.comparator != nil) },
            cell: { row, column in cols[column].makeCell(rows[row]) },
            selection: selection,
            sort: sortState,
            onSort: sort.map { binding in { i in
                guard let make = cols[i].comparator, let kp = cols[i].sortKeyPath else { return }
                let current = binding.wrappedValue.first
                let order: SortOrder = (current?.keyPath == kp && current?.order == .forward) ? .reverse : .forward
                binding.wrappedValue = [make(order)]
            } })
        return _NativeTable(model: model)
    }
}

struct _TableColumnWidth {
    var fixed: CGFloat?
    var min: CGFloat?
    var max: CGFloat?
}

/// One row of cells laid out in the table's columns: fixed widths as given, the rest
/// shared equally.
struct _TableCells: View, _PrimitiveView {
    typealias Body = Never
    let widths: [_TableColumnWidth]
    let cells: [AnyView]
    let onClick: ((Int) -> Void)?
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _TableCellsPrimitive(widths: widths, cells: cells.enumerated().map { _ViewBox($1, id: AnyHashable($0)) }, onClick: onClick)
    }
}

@MainActor
final class _TableCellsPrimitive: _Primitive {
    var widths: [_TableColumnWidth]
    var onClick: ((Int) -> Void)?
    let view = _ContainerView(frame: .zero)
    private var columnX: [CGFloat] = []
    static let spacing: CGFloat = 8

    init(widths: [_TableColumnWidth], cells: [_AnyViewBox], onClick: ((Int) -> Void)?) {
        self.widths = widths
        self.onClick = onClick
        super.init()
        children = cells
        wire()
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _TableCellsPrimitive else { return }
        widths = o.widths; onClick = o.onClick
        wire()
    }
    private func wire() {
        // Header cells take the click themselves; row cells let it through to the list view.
        view.passesThroughHits = onClick == nil
        guard onClick != nil else { view.mouseDownHandler = nil; return }
        view.mouseDownHandler = { [weak self] event in
            guard let self, let onClick = self.onClick else { return false }
            let x = self.view.convert(event.locationInWindow, from: nil).x
            if let i = self.columnX.lastIndex(where: { $0 <= x }) { onClick(i) }
            return true
        }
    }
    func columnWidths(for total: CGFloat) -> [CGFloat] {
        let n = widths.count
        guard n > 0 else { return [] }
        let gaps = CGFloat(n - 1) * _TableCellsPrimitive.spacing
        var out: [CGFloat?] = widths.map { $0.fixed }
        let fixedTotal = out.compactMap { $0 }.reduce(0, +)
        let flexible = out.filter { $0 == nil }.count
        let share = flexible > 0 ? max(0, (total - gaps - fixedTotal) / CGFloat(flexible)) : 0
        for i in out.indices where out[i] == nil {
            var w = share
            if let mn = widths[i].min { w = max(w, mn) }
            if let mx = widths[i].max { w = min(w, mx) }
            out[i] = w
        }
        return out.map { $0 ?? 0 }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let total = proposal.width.map { $0.isFinite ? $0 : 400 } ?? 400
        let ws = columnWidths(for: total)
        var height: CGFloat = 0
        for (i, c) in node.children.enumerated() where i < ws.count {
            height = max(height, c.sizeThatFits(ProposedViewSize(width: ws[i], height: nil)).height)
        }
        return CGSize(width: total, height: height)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        let ws = columnWidths(for: rect.width)
        var x = rect.minX
        columnX = []
        for (i, c) in node.children.enumerated() where i < ws.count {
            columnX.append(x - rect.minX)
            let s = c.sizeThatFits(ProposedViewSize(width: ws[i], height: nil))
            c.place(in: CGRect(x: x, y: rect.midY - s.height / 2, width: min(s.width, ws[i]), height: s.height).integralIfNeeded)
            x += ws[i] + _TableCellsPrimitive.spacing
        }
    }
}
