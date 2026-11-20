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
    /// A list in a navigation split view's sidebar column takes the sidebar style.
    @Environment(\._inSidebarColumn) private var inSidebarColumn
    public var body: some View {
        if inSidebarColumn {
            // The sidebar style: no separators, small grey section headers, rows leading
            // from the column edge under a rounded selection, on the column's own background.
            ScrollView {
                _ListRows(content: content, selection: selection, rowInset: _ListRowsPrimitive.sidebarContentInset, rowPadding: 6, sidebar: true)
            }
            .environment(\._inSidebarList, true)
        } else {
            ScrollView {
                _ListRows(content: content, selection: selection, rowInset: 10, rowPadding: 6)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: Sidebar style

private struct _InSidebarColumnKey: EnvironmentKey { static let defaultValue = false }
private struct _InSidebarListKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Inside a `NavigationSplitView`'s sidebar column, where a `List` takes the sidebar
    /// style (macOS's `.automatic` list style there). `.listStyle(.sidebar)` means the same.
    var _inSidebarColumn: Bool {
        get { self[_InSidebarColumnKey.self] }
        set { self[_InSidebarColumnKey.self] = newValue }
    }
    /// The content of a sidebar-style list: section headers are small and grey, and a
    /// `Label`'s icon takes the accent colour unless it has a foreground style of its own.
    var _inSidebarList: Bool {
        get { self[_InSidebarListKey.self] }
        set { self[_InSidebarListKey.self] = newValue }
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

/// A view whose body contributes rows to a List one by one (OutlineGroup, Section), instead
/// of being one row itself.
protocol _ListRowsProvider {}

/// A row that is not content (a section's header or footer): never selected, no separator.
protocol _ListSupplementaryRow {}

/// A section's header row (the sidebar style spaces it from the section above).
protocol _ListSectionHeaderRow: _ListSupplementaryRow {}

/// Rows stacked with padding, separators and a selection highlight.
struct _ListRows<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let selection: _ListSelection?
    let rowInset: CGFloat
    let rowPadding: CGFloat
    var sidebar = false
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _ListRowsPrimitive(content: _ViewBox(content), selection: selection, rowInset: rowInset, rowPadding: rowPadding, sidebar: sidebar)
    }
}

/// The view behind the rows: draws separators and the selection, takes clicks and keys.
@MainActor
final class _ListView: NSView, NSSelectorHandling {
    var rowFrames: [CGRect] = []
    var selectedRows: Set<Int> = []
    /// Section headers and footers: no separator above or below them.
    var supplementaryRows: Set<Int> = []
    /// Rows whose separator `listRowSeparator(.hidden)` removed: above, and below.
    var hiddenSeparatorsAbove: Set<Int> = []
    var hiddenSeparatorsBelow: Set<Int> = []
    /// Delete, Forward Delete and Edit > Delete on the selection (rows with `onDelete`).
    var onDelete: (() -> Bool)?
    var emphasized = true
    /// The sidebar style: a rounded selection inset from the edges, no separators.
    var sidebar = false
    /// The window became or stopped being key (the selection's emphasis follows it).
    var onKeyChange: (() -> Void)?
    private var keyObservers: [NSObjectProtocol] = []
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onArrow: ((Int, Bool) -> Void)?       // delta, extend
    var onSelectAll: (() -> Void)?
    /// Drag reordering (`onMove`): whether a row can be dragged, and the move to a gap.
    var canReorder: ((Int) -> Bool)?
    var onReorder: ((Int, Int) -> Void)?
    private var dragRow: Int?
    private var dragStart: NSPoint?
    /// The gap a dragged row would drop into (0...rowFrames.count), drawn as a line.
    private(set) var dropGap: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { onClick != nil }
    /// The rows' separators and selection repaint where rows moved (`place` marks them);
    /// a list growing by a row does not repaint every row.
    override var layerContentsRedrawPolicy: NSView.LayerContentsRedrawPolicy {
        get { .onSetNeedsDisplay }
        set { super.layerContentsRedrawPolicy = newValue }
    }
    /// Marks the rows whose frames differ between `old` and `rowFrames`, or whose separators
    /// were hidden or shown (`oldHidden*`, by index), with the separator lines on their edges.
    func setNeedsDisplay(changedFrom old: [CGRect], hiddenAbove oldAbove: Set<Int>, hiddenBelow oldBelow: Set<Int>) {
        var dirty: [NSRect] = []
        /// The separator line under row `i` (drawn at its bottom edge), old and new.
        func separator(below i: Int) {
            for frames in [old, rowFrames] where frames.indices.contains(i) {
                let f = frames[i]
                dirty.append(NSRect(x: f.minX, y: f.maxY - 1, width: f.width, height: 3))
            }
        }
        for i in 0..<max(old.count, rowFrames.count) {
            let a = old.indices.contains(i) ? old[i] : .null
            let b = rowFrames.indices.contains(i) ? rowFrames[i] : .null
            guard a != b else { continue }
            for r in [a, b] where !r.isNull { dirty.append(r.insetBy(dx: 0, dy: -1)) }
            // The row above gains or loses its separator when this one appears or goes.
            separator(below: i - 1)
        }
        // A separator hidden from below (row i) or above (row i + 1) lies between the two.
        for i in oldBelow.symmetricDifference(hiddenSeparatorsBelow) { separator(below: i) }
        for i in oldAbove.symmetricDifference(hiddenSeparatorsAbove) { separator(below: i - 1) }
        let visible = bounds.insetBy(dx: 0, dy: -1)
        var merged = NSRect.null
        for r in dirty { merged = merged.union(r) }
        // One mark for a contiguous band (the usual case), each on its own otherwise.
        if !merged.isNull, dirty.reduce(0, { $0 + $1.width * $1.height }) * 2 >= merged.width * merged.height {
            setNeedsDisplay(merged.intersection(visible))
        } else {
            for r in dirty { setNeedsDisplay(r.intersection(visible)) }
        }
    }


    override func draw(_ dirtyRect: NSRect) {
        for i in selectedRows where rowFrames.indices.contains(i) {
            (emphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
            if sidebar {
                let r = Self.sidebarSelectionRect(rowFrames[i])
                NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            } else {
                NSBezierPath.fill(rowFrames[i])
            }
        }
        NSColor.separatorColor.setFill()
        for (i, f) in rowFrames.enumerated().dropLast() where !sidebar && (!selectedRows.contains(i) || !selectedRows.contains(i + 1)) && !supplementaryRows.contains(i) && !supplementaryRows.contains(i + 1) && !hiddenSeparatorsBelow.contains(i) && !hiddenSeparatorsAbove.contains(i + 1) {
            NSBezierPath.fill(NSRect(x: f.minX, y: f.maxY, width: f.width, height: 1))
        }
        if let g = dropGap, !rowFrames.isEmpty {
            let y = g < rowFrames.count ? rowFrames[g].minY : rowFrames[rowFrames.count - 1].maxY
            NSColor.controlAccentColor.setFill()
            NSBezierPath.fill(NSRect(x: 4, y: y - 1, width: bounds.width - 8, height: 2))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let r = dragRow, let start = dragStart else { super.mouseDragged(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        guard dropGap != nil || abs(p.y - start.y) > 3 else { return }
        // The gap whose row midpoint the pointer is above.
        var gap = rowFrames.count
        for (i, f) in rowFrames.enumerated() where p.y < f.midY { gap = i; break }
        if gap != dropGap { dropGap = gap; needsDisplay = true }
        _ = r
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragRow = nil; dragStart = nil }
        guard let r = dragRow, let g = dropGap else { super.mouseUp(with: event); return }
        dropGap = nil
        needsDisplay = true
        onReorder?(r, g)
    }
    func row(at point: NSPoint) -> Int? { rowFrames.firstIndex { $0.contains(point) } }

    /// The sidebar selection of a row: inset 10 points from the column's sides, as macOS's.
    static func sidebarSelectionRect(_ row: CGRect) -> CGRect { row.insetBy(dx: 10, dy: 0) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for o in keyObservers { NotificationCenter.default.removeObserver(o) }
        keyObservers = []
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.onKeyChange?() }
            })
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let i = row(at: p), canReorder?(i) == true { dragRow = i; dragStart = p; dropGap = nil }
        guard let onClick else { if dragRow == nil { super.mouseDown(with: event) }; return }
        // A click anywhere in a row (also on a row's own views) focuses the list for the keys.
        if let w = window, w.firstResponder !== self { _ = w.makeFirstResponder(self) }
        if let i = row(at: p) { onClick(i, event.modifierFlags) }
    }
    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 125: onArrow?(1, extend)
        case 126: onArrow?(-1, extend)
        case 51, 117:
            if onDelete?() != true { super.keyDown(with: event) }
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a", let onSelectAll { onSelectAll() }
            else { super.keyDown(with: event) }
        }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    /// The Edit menu's Select All (Cmd-A as a key equivalent) reaches the focused list.
    func respondsToSelectorAction(_ action: Selector) -> Bool {
        (action == Selector(("selectAll:")) && onSelectAll != nil) || (action == Selector(("delete:")) && onDelete != nil)
    }
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        if action == Selector(("delete:")), let onDelete { return onDelete() }
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
    let sidebar: Bool
    /// The sidebar style's leading inset of a row's content (the icon), and of a header.
    static let sidebarContentInset: CGFloat = 18
    static let sidebarHeaderInset: CGFloat = 14
    private var rowValues: [AnyHashable] = []
    private var rowNodes: [_ViewNode] = []
    /// Per row: the `onDelete` content it came from and its element's offset there.
    private var rowDeleteTargets: [(actions: _RowActionsPrimitive, offset: Int)?] = []
    /// Per row: the `onMove` content it came from and its element's offset there.
    private var rowMoveTargets: [(actions: _RowMovePrimitive, offset: Int)?] = []
    private var supplementary: Set<Int> = []
    private var anchor: Int?

    init(content: _AnyViewBox, selection: _ListSelection?, rowInset: CGFloat, rowPadding: CGFloat, sidebar: Bool = false) {
        self.selection = selection
        self.rowInset = rowInset
        self.rowPadding = rowPadding
        self.sidebar = sidebar
        super.init()
        view.sidebar = sidebar
        view.onKeyChange = { [weak self] in self?.refreshHighlight() }
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
        view.canReorder = { [weak self] i in self?.rowMoveTargets.indices.contains(i) == true && self?.rowMoveTargets[i]?.actions.onMove != nil }
        view.onReorder = { [weak self] row, gap in self?.reorder(row, toGap: gap) }
        guard selection != nil else { view.onClick = nil; view.onArrow = nil; view.onSelectAll = nil; view.onDelete = nil; return }
        view.onDelete = { [weak self] in self?.deleteSelected() ?? false }
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
    private struct _Row {
        let node: _ViewNode
        let deleteTarget: (actions: _RowActionsPrimitive, offset: Int)?
        var moveTarget: (actions: _RowMovePrimitive, offset: Int)? = nil
    }
    /// Where rows are being collected: the nearest `onDelete` content and, below its
    /// `ForEach`, the element's offset.
    private struct _RowContext {
        var actions: _RowActionsPrimitive?
        /// The nearest `onMove` content (MoveAndDialogs.swift).
        var move: _RowMovePrimitive?
        var offset: Int?
        var target: (actions: _RowActionsPrimitive, offset: Int)? {
            guard let actions, let offset else { return nil }
            return (actions, offset)
        }
        var moveTarget: (actions: _RowMovePrimitive, offset: Int)? {
            guard let move, let offset else { return nil }
            return (move, offset)
        }
    }
    private func collectRows(_ node: _ViewNode, context: _RowContext, into out: inout [_Row]) {
        for (i, c) in node.children.enumerated() {
            var inner = context
            if node.primitive is _ForEachPrimitive, context.actions != nil || context.move != nil, context.offset == nil { inner.offset = i }
            if c.box.value is _MetadataView { out.append(_Row(node: c, deleteTarget: inner.target, moveTarget: inner.moveTarget)); continue }
            if c.box.value is EmptyView { continue }
            if let p = c.primitive, p.isLayoutTransparent {
                if let actions = p as? _RowActionsPrimitive { inner.actions = actions; inner.offset = nil }
                if let move = p as? _RowMovePrimitive { inner.move = move; inner.offset = nil }
                collectRows(c, context: inner, into: &out)
            }
            else if c.primitive == nil, c.box.value is any _ListRowsProvider { collectRows(c, context: inner, into: &out) }
            else { out.append(_Row(node: c, deleteTarget: inner.target, moveTarget: inner.moveTarget)) }
        }
    }
    private func rowEntries(_ node: _ViewNode) -> [_Row] {
        var out: [_Row] = []
        collectRows(node, context: _RowContext(), into: &out)
        return out
    }
    private func rows(_ node: _ViewNode) -> [_ViewNode] { rowEntries(node).map(\.node) }
    private func isSupplementary(_ row: _ViewNode) -> Bool {
        row.box.value is any _ListSupplementaryRow
    }
    private func value(of row: _ViewNode, index: Int) -> AnyHashable {
        Self.tag(of: row) ?? row.box.id ?? AnyHashable(index)
    }
    /// A row's tag: on the row itself, or below it through single-child wrappers (a
    /// context menu, padding, a custom view's body), as SwiftUI's tag trait reaches the list
    /// through the modifiers applied after it. Sibyl's channel rows are
    /// `ChannelRow(...).tag(...).contextMenu { ... }`: the tag sits under the context menu,
    /// and without this the row's value was its `ForEach` id, which no selection holds.
    /// A ForEach or a scroll view below is content of its own, not the row's wrapper.
    static func tag(of row: _ViewNode) -> AnyHashable? {
        var current: _ViewNode? = row
        while let n = current {
            if let tag = _metadata(of: n.box).meta.tag { return tag }
            if n.primitive is _ForEachPrimitive || n.primitive is _ScrollPrimitive || n.primitive is _ListRowsPrimitive { return nil }
            current = n.children.count == 1 ? n.children[0] : nil
        }
        return nil
    }

    /// How a row sits in the list: its content's leading and trailing insets, the padding
    /// above and below it, and the gap after it (the separator's line).
    private struct _RowMetrics { var leading, trailing, top, bottom, gap: CGFloat }
    private func metrics(of row: _ViewNode, index: Int) -> _RowMetrics {
        guard sidebar else { return _RowMetrics(leading: rowInset, trailing: rowInset, top: rowPadding, bottom: rowPadding, gap: 1) }
        if row.box.value is any _ListSectionHeaderRow {
            // A header: small text near the column edge, set off from the section above.
            return _RowMetrics(leading: Self.sidebarHeaderInset, trailing: Self.sidebarHeaderInset, top: index == 0 ? 4 : 12, bottom: 4, gap: 0)
        }
        return _RowMetrics(leading: rowInset, trailing: rowInset - 4, top: rowPadding, bottom: rowPadding, gap: 0)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        var height: CGFloat = 0
        var width: CGFloat = 0
        for (i, r) in rows(node).enumerated() {
            if _ListRowDecorationPrimitive.traits(of: r) != nil {
                // A decorated row (listRowInsets/Background/Separator) insets itself.
                let s = r.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
                height += s.height + 1
                width = max(width, s.width)
                continue
            }
            let m = metrics(of: r, index: i)
            let s = r.sizeThatFits(ProposedViewSize(width: proposal.width.map { max(0, $0 - m.leading - m.trailing) }, height: nil))
            height += s.height + m.top + m.bottom + m.gap
            width = max(width, s.width + m.leading + m.trailing)
        }
        return CGSize(width: proposal.width.map { $0.isFinite ? max($0, width) : width } ?? width, height: height)
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        var y = rect.minY
        var frames: [CGRect] = []
        let entries = rowEntries(node)
        let nodes = entries.map(\.node)
        rowNodes = nodes
        rowDeleteTargets = entries.map(\.deleteTarget)
        rowMoveTargets = entries.map(\.moveTarget)
        supplementary = Set(nodes.indices.filter { isSupplementary(nodes[$0]) })
        if view.supplementaryRows != supplementary { view.supplementaryRows = supplementary; view.needsDisplay = true }
        // A header or footer's value is the row object itself: no selection ever holds it.
        rowValues = nodes.enumerated().map { supplementary.contains($0) ? AnyHashable(ObjectIdentifier($1)) : value(of: $1, index: $0) }
        var hiddenAbove: Set<Int> = [], hiddenBelow: Set<Int> = []
        for (i, r) in nodes.enumerated() {
            if let traits = _ListRowDecorationPrimitive.traits(of: r) {
                if traits.separatorHidden.contains(.top) { hiddenAbove.insert(i) }
                if traits.separatorHidden.contains(.bottom) { hiddenBelow.insert(i) }
                let s = r.sizeThatFits(ProposedViewSize(width: rect.width, height: nil))
                r.place(in: CGRect(x: rect.minX, y: y, width: rect.width, height: s.height).integralIfNeeded)
                frames.append(CGRect(x: 0, y: y - rect.minY, width: rect.width, height: s.height))
                y += s.height + 1
                continue
            }
            let m = metrics(of: r, index: i)
            let available = max(0, rect.width - m.leading - m.trailing)
            let s = r.sizeThatFits(ProposedViewSize(width: available, height: nil))
            let rowHeight = s.height + m.top + m.bottom
            // The row's content sits at its own width against the leading edge (a list
            // row is leading-aligned; a stack given the full width would centre itself).
            let w = min(s.width, available)
            let x = node.environment.layoutDirection == .rightToLeft ? rect.maxX - m.trailing - w : rect.minX + m.leading
            r.place(in: CGRect(x: x, y: y + m.top, width: w, height: s.height).integralIfNeeded)
            frames.append(CGRect(x: 0, y: y - rect.minY, width: rect.width, height: rowHeight))
            y += rowHeight + m.gap
        }
        // The rows' separators and selection repaint only when they moved or changed.
        if view.rowFrames != frames || view.hiddenSeparatorsAbove != hiddenAbove || view.hiddenSeparatorsBelow != hiddenBelow {
            // Only the rows that moved, changed size or gained or lost a separator: a line
            // appended to a transcript repaints that line (and the sentinel row after it,
            // whose hidden separator moved down one index), an insertion the rows it shifts.
            let old = view.rowFrames, oldAbove = view.hiddenSeparatorsAbove, oldBelow = view.hiddenSeparatorsBelow
            view.rowFrames = frames
            view.hiddenSeparatorsAbove = hiddenAbove
            view.hiddenSeparatorsBelow = hiddenBelow
            view.setNeedsDisplay(changedFrom: old, hiddenAbove: oldAbove, hiddenBelow: oldBelow)
        }
        refreshHighlight()
    }
    override func didSyncBackingViews(node: _ViewNode) { refreshHighlight() }

    /// Mirrors the binding into the view and the row texts.
    private func refreshHighlight() {
        let selected = selection?.get() ?? []
        let indices = Set(rowValues.indices.filter { selected.contains(rowValues[$0]) })
        let emphasized = view.window?.isKeyWindow ?? true
        if view.selectedRows != indices || view.emphasized != emphasized {
            view.selectedRows = indices
            view.emphasized = emphasized
            view.needsDisplay = true
        }
        for (i, r) in rowNodes.enumerated() {
            var views: [NSView] = []
            r.collectBackingViews(into: &views)
            // Text (and symbols) turn white on the accent selection of a key window; on the
            // unemphasized grey selection of an inactive one they keep their colours.
            for v in views { setSelected(indices.contains(i) && emphasized, in: v) }
        }
    }
    private func setSelected(_ on: Bool, in v: NSView) {
        if let t = v as? _TextView { t.isInSelectedRow = on }
        if let s = v as? _SymbolImageView { s.isInSelectedRow = on }
        for s in v.subviews { setSelected(on, in: s) }
    }

    // MARK: Moving

    /// Moves `row` to the gap before row `gap` (`rowCount` for the end) within its own
    /// `onMove` content, as `onMove(perform:)` offsets count.
    private func reorder(_ row: Int, toGap gap: Int) {
        guard rowMoveTargets.indices.contains(row), let target = rowMoveTargets[row], let onMove = target.actions.onMove else { return }
        var destination = 0
        for (i, t) in rowMoveTargets.enumerated() where i < gap {
            if let t, t.actions === target.actions { destination = t.offset + 1 }
        }
        // A gap before the first row of the group (or anywhere above it) is offset zero.
        if let first = rowMoveTargets.firstIndex(where: { $0?.actions === target.actions }), gap <= first { destination = 0 }
        guard destination != target.offset, destination != target.offset + 1 else { return }
        onMove(IndexSet(integer: target.offset), destination)
    }

    // MARK: Deleting

    /// Calls each `onDelete` with the offsets of its selected rows; false when none applies.
    private func deleteSelected() -> Bool {
        guard let sel = selection else { return false }
        let selected = sel.get()
        var batches: [(actions: _RowActionsPrimitive, offsets: IndexSet)] = []
        for (i, target) in rowDeleteTargets.enumerated() {
            guard let target, rowValues.indices.contains(i), selected.contains(rowValues[i]), target.actions.onDelete != nil else { continue }
            if let k = batches.firstIndex(where: { $0.actions === target.actions }) { batches[k].offsets.insert(target.offset) }
            else { batches.append((target.actions, IndexSet(integer: target.offset))) }
        }
        guard !batches.isEmpty else { return false }
        for b in batches { b.actions.onDelete?(b.offsets) }
        return true
    }

    // MARK: Selecting

    private func click(_ i: Int, _ flags: NSEvent.ModifierFlags) {
        guard let sel = selection, rowValues.indices.contains(i), !supplementary.contains(i) else { return }
        let v = rowValues[i]
        if sel.allowsMultiple, flags.contains(.command) {
            var s = sel.get()
            if s.contains(v) { s.remove(v) } else { s.insert(v) }
            sel.set(s)
            anchor = i
        } else if sel.allowsMultiple, flags.contains(.shift), let a = anchor {
            // Shift extends: the rows between the anchor and the click join what is selected.
            sel.set(sel.get().union((min(a, i)...max(a, i)).filter { !supplementary.contains($0) }.map { rowValues[$0] }))
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
        // The next content row that way (headers and footers are stepped over).
        var candidate = from + delta
        while rowValues.indices.contains(candidate), supplementary.contains(candidate) { candidate += delta }
        guard rowValues.indices.contains(candidate) || current.isEmpty == false else { return }
        let next = rowValues.indices.contains(candidate) ? candidate : from
        guard rowValues.indices.contains(next), !supplementary.contains(next) else { return }
        if extend, sel.allowsMultiple {
            let a = anchor ?? from
            sel.set(selected.union((min(a, next)...max(a, next)).filter { !supplementary.contains($0) }.map { rowValues[$0] }))
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
