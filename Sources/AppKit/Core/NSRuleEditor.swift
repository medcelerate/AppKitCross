// NSRuleEditor (hand-written; seeded from the generated stub, see tools/apigen)
//
// Rows of criteria chosen through the delegate (ADR-0032). A row's criteria are a path through
// the delegate's criterion tree for the row type: the first criterion is a child of `nil`,
// each next one a child of the previous, and the path ends at a criterion without children.
// Each criterion shows its display value: a string becomes a pop-up of its siblings' display
// values (a label when it has none), a view (a text field, say) is shown as is. Rows are kept as
// a tree and addressed by their index in display order; compound rows hold subrows.
//
// The predicate merges the delegate's predicate parts for every criterion of a row: a simple row
// becomes a comparison predicate, a compound row a compound predicate over its subrows, and
// several root rows are combined with AND. On Apple's Foundation the parts are the usual
// NSExpressions and the result is an NSComparisonPredicate. swift-corelibs-foundation cannot
// build NSExpression or NSComparisonPredicate (both trap), so there a left expression may be a
// key-path string and a right expression a plain value, and the editor builds a comparison
// predicate of its own that evaluates through the port's key-value coding and prints the same
// format string. Plain values are accepted on macOS too, so one delegate serves every platform.
//
// The rows draw themselves (package-drawn, like the table and the token field): alternating
// stripes, the selection, and +/− buttons that add a sibling (or, on a compound row, a child)
// and remove a row with its subrows. Formatting dictionaries are stored but not applied to
// the display (localised reordering of criteria is not implemented).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor
@MainActor open class NSRuleEditor: NSControl {
    final class _Row {
        var rowType: NSRuleEditor.RowType
        var criteria: [Any]
        var displayValues: [Any]
        weak var parent: _Row?
        var subrows: [_Row] = []
        init(rowType: NSRuleEditor.RowType, criteria: [Any], displayValues: [Any]) {
            self.rowType = rowType; self.criteria = criteria; self.displayValues = displayValues
        }
    }

    private var _roots: [_Row] = []
    private var _flat: [_Row] = []
    private weak var _delegate: (any NSRuleEditorDelegate)?
    private var _nestingMode: NSRuleEditor.NestingMode = .compound
    private var _isEditable = true
    private var _canRemoveAllRows = true
    private var _rowHeight: CGFloat = 26
    private var _criteriaKeyPath = "criteria"
    private var _displayValuesKeyPath = "displayValues"
    private var _subrowsKeyPath = "subrows"
    private var _rowTypeKeyPath = "rowType"
    private var _rowClass: AnyClass = NSMutableDictionary.self
    private var _formattingDictionary: [String: String]?
    private var _formattingStringsFilename: String?
    private var _selectedRows = IndexSet()
    private var _rowViews: [_NSRuleEditorRowView] = []
    nonisolated(unsafe) private var _textObserver: (any NSObjectProtocol)?

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _textObserver = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: nil, queue: nil) { [weak self] note in
            MainActor.assumeIsolated { self?._textDidChange(note) }
        }
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    deinit { if let o = _textObserver { NotificationCenter.default.removeObserver(o) } }

    open override var isFlipped: Bool { true }

    // MARK: Rows

    /// Adds a row: on an empty editor a compound row with one simple subrow (compound and simple
    /// nesting) or a simple row; otherwise a simple row at the end (inside the first compound
    /// root row when there is one).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/addrow(_:)
    @MainActor open func addRow(_ sender: Any?) {
        if _flat.isEmpty {
            switch _nestingMode {
            case .compound, .simple:
                insertRow(at: 0, with: .compound, asSubrowOfRow: -1, animate: false)
                insertRow(at: 1, with: .simple, asSubrowOfRow: 0, animate: false)
            case .list, .single:
                insertRow(at: 0, with: .simple, asSubrowOfRow: -1, animate: false)
            }
            return
        }
        switch _nestingMode {
        case .single: return
        case .list: insertRow(at: _flat.count, with: .simple, asSubrowOfRow: -1, animate: false)
        case .compound, .simple:
            if let root = _roots.first(where: { $0.rowType == .compound }), let r = _index(of: root) {
                insertRow(at: r + _subtreeCount(root), with: .simple, asSubrowOfRow: r, animate: false)
            } else {
                insertRow(at: _flat.count, with: .simple, asSubrowOfRow: -1, animate: false)
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/canremoveallrows
    @MainActor open var canRemoveAllRows: Bool {
        get { _canRemoveAllRows }
        set { _canRemoveAllRows = newValue; _rebuildViews() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/criteria(forrow:)
    @MainActor open func criteria(forRow row: Int) -> [Any] { _row(row).criteria }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/criteriakeypath
    @MainActor open var criteriaKeyPath: String {
        get { _criteriaKeyPath }
        set { _criteriaKeyPath = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/delegate
    @MainActor open var delegate: (any NSRuleEditorDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/displayvalues(forrow:)
    @MainActor open func displayValues(forRow row: Int) -> [Any] { _row(row).displayValues }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/displayvalueskeypath
    @MainActor open var displayValuesKeyPath: String {
        get { _displayValuesKeyPath }
        set { _displayValuesKeyPath = newValue }
    }
    /// Stored; the editor does not reorder or translate criteria with it.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/formattingdictionary
    @MainActor open var formattingDictionary: [String : String]? {
        get { _formattingDictionary }
        set { _formattingDictionary = newValue }
    }
    /// Stored; the strings file is not loaded.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/formattingstringsfilename
    @MainActor open var formattingStringsFilename: String? {
        get { _formattingStringsFilename }
        set { _formattingStringsFilename = newValue }
    }
    /// Inserts a row of `rowType` at `rowIndex` (in display order) as a subrow of `parentRow`
    /// (-1 for a root row); its criteria are the first child at every level.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/insertrow(at:with:assubrowofrow:animate:)
    @MainActor open func insertRow(at rowIndex: Int, with rowType: NSRuleEditor.RowType, asSubrowOfRow parentRow: Int, animate shouldAnimate: Bool) {
        precondition(rowIndex >= 0 && rowIndex <= _flat.count, "[NSRuleEditor insertRowAtIndex:...]: row index \(rowIndex) beyond bounds (\(_flat.count))")
        precondition(parentRow >= -1 && parentRow < rowIndex, "[NSRuleEditor insertRowAtIndex:...]: parent row \(parentRow) must precede row index \(rowIndex)")
        let parent = parentRow >= 0 ? _flat[parentRow] : nil
        if let parent { precondition(parent.rowType == .compound, "[NSRuleEditor insertRowAtIndex:...]: parent row \(parentRow) is not a compound row") }
        let row = _Row(rowType: rowType, criteria: [], displayValues: [])
        let siblings = parent?.subrows ?? _roots
        // Among the siblings, the new row goes before the first one displayed at or after rowIndex.
        let position = siblings.firstIndex { (_index(of: $0) ?? 0) >= rowIndex } ?? siblings.count
        row.parent = parent
        if let parent { parent.subrows.insert(row, at: position) } else { _roots.insert(row, at: position) }
        _reflatten()
        row.criteria = _defaultCriteria(from: [], rowType: rowType)
        row.displayValues = _displayValues(for: row)
        _rowsDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/iseditable
    @MainActor open var isEditable: Bool {
        get { _isEditable }
        set { _isEditable = newValue; _rebuildViews() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/nestingmode
    @MainActor open var nestingMode: NSRuleEditor.NestingMode {
        get { _nestingMode }
        set { _nestingMode = newValue; _rebuildViews() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/numberofrows
    @MainActor open var numberOfRows: Int { _flat.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/parentrow(forrow:)
    @MainActor open func parentRow(forRow rowIndex: Int) -> Int { _row(rowIndex).parent.flatMap { _index(of: $0) } ?? -1 }
    /// The predicate of the root row, or the AND of the root rows' predicates; nil without rows.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/predicate
    @MainActor open var predicate: NSPredicate? {
        let parts = _roots.compactMap { _predicate(for: $0) }
        if parts.isEmpty { return nil }
        if parts.count == 1 { return parts[0] }
        return _NSRulePredicates.compound(.and, parts)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/predicate(forrow:)
    @MainActor open func predicate(forRow row: Int) -> NSPredicate? { _predicate(for: _row(row)) }
    /// Asks the delegate for every row's criteria again, keeping each choice that still exists.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/reloadcriteria()
    @MainActor open func reloadCriteria() {
        for row in _flat {
            row.criteria = _defaultCriteria(from: row.criteria, rowType: row.rowType)
            row.displayValues = _displayValues(for: row)
        }
        _rowsDidChange()
    }
    /// The predicate is computed from the rows when asked; this announces that it changed.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/reloadpredicate()
    @MainActor open func reloadPredicate() { _KVO.didChange(self, key: "predicate") }
    /// Removes a row; its subrows move up to its parent.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/removerow(at:)
    @MainActor open func removeRow(at rowIndex: Int) {
        _removeRow(_row(rowIndex), includeSubrows: false)
        _rowsDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/removerows(at:includesubrows:)
    @MainActor open func removeRows(at rowIndexes: IndexSet, includeSubrows: Bool) {
        let rows = rowIndexes.map { _row($0) }
        for r in rows.reversed() where _index(of: r) != nil { _removeRow(r, includeSubrows: includeSubrows) }
        _rowsDidChange()
    }
    /// The first row whose display values include `displayValue`, or -1.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/row(fordisplayvalue:)
    @MainActor open func row(forDisplayValue displayValue: Any) -> Int {
        _flat.firstIndex { $0.displayValues.contains { _KVC.same($0, displayValue) } } ?? -1
    }
    /// Stored for the `rows` binding's row objects; rows are not bound in the port.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/rowclass
    @MainActor open var rowClass: AnyClass {
        get { _rowClass }
        set { _rowClass = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/rowheight
    @MainActor open var rowHeight: CGFloat {
        get { _rowHeight }
        set { _rowHeight = max(1, newValue); _rebuildViews() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/rowtype(forrow:)
    @MainActor open func rowType(forRow rowIndex: Int) -> NSRuleEditor.RowType { _row(rowIndex).rowType }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/rowtypekeypath
    @MainActor open var rowTypeKeyPath: String {
        get { _rowTypeKeyPath }
        set { _rowTypeKeyPath = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/rowsdidchangenotification
    static public var rowsDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSRuleEditorRowsDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/selectrowindexes(_:byextendingselection:)
    @MainActor open func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        let valid = IndexSet(indexes.filter { $0 >= 0 && $0 < _flat.count })
        _selectedRows = extend ? _selectedRows.union(valid) : valid
        for (i, v) in _rowViews.enumerated() { v.isSelected = _selectedRows.contains(i) }
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/selectedrowindexes
    @MainActor open var selectedRowIndexes: IndexSet { _selectedRows }
    /// Sets a row's criteria and display values directly (they are not checked with the delegate).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/setcriteria(_:anddisplayvalues:forrowat:)
    @MainActor open func setCriteria(_ criteria: [Any], andDisplayValues values: [Any], forRowAt rowIndex: Int) {
        precondition(criteria.count == values.count, "[NSRuleEditor setCriteria:andDisplayValues:forRowAtIndex:]: \(criteria.count) criteria but \(values.count) display values")
        if rowIndex == _flat.count {
            let row = _Row(rowType: .simple, criteria: criteria, displayValues: values)
            _roots.append(row)
            _reflatten()
        } else {
            let row = _row(rowIndex)
            row.criteria = criteria
            row.displayValues = values
        }
        _rowsDidChange()
    }
    /// The indexes of the row's immediate subrows.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/subrowindexes(forrow:)
    @MainActor open func subrowIndexes(forRow rowIndex: Int) -> IndexSet {
        IndexSet(_row(rowIndex).subrows.compactMap { _index(of: $0) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsruleeditor/subrowskeypath
    @MainActor open var subrowsKeyPath: String {
        get { _subrowsKeyPath }
        set { _subrowsKeyPath = newValue }
    }

    // MARK: Row model

    private func _row(_ index: Int) -> _Row {
        precondition(index >= 0 && index < _flat.count, "[NSRuleEditor]: row index \(index) beyond bounds (\(_flat.count))")
        return _flat[index]
    }

    private func _index(of row: _Row) -> Int? { _flat.firstIndex { $0 === row } }

    private func _subtreeCount(_ row: _Row) -> Int { 1 + row.subrows.reduce(0) { $0 + _subtreeCount($1) } }

    private func _depth(of row: _Row) -> Int {
        var d = 0
        var p = row.parent
        while let q = p { d += 1; p = q.parent }
        return d
    }

    private func _reflatten() {
        var out: [_Row] = []
        func walk(_ rows: [_Row]) { for r in rows { out.append(r); walk(r.subrows) } }
        walk(_roots)
        _flat = out
    }

    private func _removeRow(_ row: _Row, includeSubrows: Bool) {
        let parent = row.parent
        var siblings = parent?.subrows ?? _roots
        guard let i = siblings.firstIndex(where: { $0 === row }) else { return }
        siblings.remove(at: i)
        if !includeSubrows {
            for s in row.subrows { s.parent = parent }
            siblings.insert(contentsOf: row.subrows, at: i)
        }
        if let parent { parent.subrows = siblings } else { _roots = siblings }
        _reflatten()
        _selectedRows = IndexSet(_selectedRows.filter { $0 < _flat.count })
    }

    /// The delegate's children of `criterion` for `rowType`.
    private func _children(of criterion: Any?, rowType: NSRuleEditor.RowType) -> [Any] {
        guard let d = _delegate else { return [] }
        let n = d.ruleEditor(self, numberOfChildrenForCriterion: criterion, with: rowType)
        return (0..<max(0, n)).map { d.ruleEditor(self, child: $0, forCriterion: criterion, with: rowType) }
    }

    /// A criteria path that keeps as much of `existing` as the delegate still offers and
    /// continues with first children.
    private func _defaultCriteria(from existing: [Any], rowType: NSRuleEditor.RowType) -> [Any] {
        var out: [Any] = []
        var parent: Any? = nil
        var level = 0
        while true {
            let kids = _children(of: parent, rowType: rowType)
            guard !kids.isEmpty else { break }
            var pick = kids[0]
            if level < existing.count, let same = kids.first(where: { _KVC.same($0, existing[level]) }) { pick = same }
            out.append(pick)
            parent = pick
            level += 1
            if level > 64 { break }   // a cyclic criterion tree
        }
        return out
    }

    private func _displayValues(for row: _Row) -> [Any] {
        guard let d = _delegate, let index = _index(of: row) else { return [] }
        return row.criteria.map { d.ruleEditor(self, displayValueForCriterion: $0, inRow: index) }
    }

    /// The user picked sibling `choice` at `level` of `row`.
    fileprivate func _choose(_ choice: Int, level: Int, in row: _Row) {
        let parent: Any? = level == 0 ? nil : row.criteria[level - 1]
        let kids = _children(of: parent, rowType: row.rowType)
        guard choice >= 0, choice < kids.count else { return }
        let prefix = Array(row.criteria.prefix(level)) + [kids[choice]]
        // Below the new choice, keep nothing: the delegate's first children follow it.
        var path = prefix
        var p: Any = kids[choice]
        while true {
            let next = _children(of: p, rowType: row.rowType)
            guard let first = next.first, path.count <= 64 else { break }
            path.append(first)
            p = first
        }
        row.criteria = path
        row.displayValues = _displayValues(for: row)
        _rowsDidChange()
        _fireAction()
    }

    /// + on a row: a simple row after it (after its subrows), or inside it for a compound row;
    /// with Option held in compound nesting, a compound row instead.
    fileprivate func _addRow(after row: _Row) {
        guard let index = _index(of: row) else { return }
        let option = NSApplication.shared.currentEvent?.modifierFlags.contains(.option) ?? false
        let type: NSRuleEditor.RowType = (option && _nestingMode == .compound) ? .compound : .simple
        if row.rowType == .compound {
            insertRow(at: index + _subtreeCount(row), with: type, asSubrowOfRow: index, animate: true)
        } else {
            insertRow(at: index + _subtreeCount(row), with: type, asSubrowOfRow: row.parent.flatMap { _index(of: $0) } ?? -1, animate: true)
        }
        if type == .compound, let new = _flat.last(where: { $0.rowType == .compound && $0.subrows.isEmpty }), let ni = _index(of: new) {
            insertRow(at: ni + 1, with: .simple, asSubrowOfRow: ni, animate: true)
        }
        _fireAction()
    }

    fileprivate func _remove(_ row: _Row) {
        guard let index = _index(of: row) else { return }
        removeRows(at: IndexSet(integer: index), includeSubrows: true)
        _fireAction()
    }

    fileprivate func _canRemove(_ row: _Row) -> Bool {
        guard _isEditable else { return false }
        if _nestingMode == .simple && row.parent == nil && row.rowType == .compound { return false }
        if !_canRemoveAllRows && _subtreeCount(row) >= _flat.count { return false }
        return true
    }

    fileprivate func _canAdd(_ row: _Row) -> Bool {
        guard _isEditable else { return false }
        switch _nestingMode {
        case .single: return false
        case .list: return row.rowType == .simple
        case .simple, .compound: return true
        }
    }

    /// Siblings of the criterion at `level` and their display values (for the pop-up).
    fileprivate func _choices(level: Int, in row: _Row) -> [String] {
        let parent: Any? = level == 0 ? nil : row.criteria[level - 1]
        guard let d = _delegate, let index = _index(of: row) else { return [] }
        return _children(of: parent, rowType: row.rowType).map { c in
            let v = d.ruleEditor(self, displayValueForCriterion: c, inRow: index)
            if let s = v as? String { return s }
            if let m = v as? NSMenuItem { return m.title }
            return String(describing: v)
        }
    }

    fileprivate func _siblingCount(level: Int, in row: _Row) -> Int {
        _children(of: level == 0 ? nil : row.criteria[level - 1], rowType: row.rowType).count
    }

    private func _rowsDidChange() {
        _rebuildViews()
        invalidateIntrinsicContentSize()
        let n = Notification(name: NSRuleEditor.rowsDidChangeNotification, object: self)
        NotificationCenter.default.post(n)
        _delegate?.ruleEditorRowsDidChange(n)
        _KVO.didChange(self, keys: ["numberOfRows", "predicate"])
    }

    /// A text field inside a row changed: the predicate changed with it.
    private func _textDidChange(_ note: Notification) {
        guard let v = note.object as? NSView, v.isDescendant(of: self) else { return }
        _KVO.didChange(self, key: "predicate")
        _fireAction()
    }

    // MARK: Predicates

    private func _predicate(for row: _Row) -> NSPredicate? {
        guard let index = _index(of: row) else { return nil }
        var parts: [NSRuleEditor.PredicatePartKey: Any] = [:]
        if let d = _delegate {
            for (c, v) in zip(row.criteria, row.displayValues) {
                if let p = d.ruleEditor(self, predicatePartsForCriterion: c, withDisplayValue: v, inRow: index) {
                    parts.merge(p) { _, new in new }
                }
            }
        }
        if row.rowType == .compound {
            let subs = row.subrows.compactMap { _predicate(for: $0) }
            let type = _NSRulePredicates.logicalType(parts[.compoundType]) ?? .and
            return _NSRulePredicates.compound(type, subs)
        }
        return _NSRulePredicates.comparison(parts)
    }

    // MARK: Views

    open override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(_flat.count) * _rowHeight)
    }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _layoutRows()
    }

    private func _rebuildViews() {
        for v in _rowViews { v.removeFromSuperview() }
        _rowViews = _flat.enumerated().map { i, row in
            let v = _NSRuleEditorRowView(editor: self, row: row, depth: _depth(of: row))
            v.isSelected = _selectedRows.contains(i)
            v.stripe = i % 2 == 1
            return v
        }
        for v in _rowViews { addSubview(v) }
        _layoutRows()
        needsDisplay = true
    }

    private func _layoutRows() {
        for (i, v) in _rowViews.enumerated() {
            v.frame = NSRect(x: 0, y: CGFloat(i) * _rowHeight, width: bounds.width, height: _rowHeight)
            v._layoutControls()
        }
    }

    fileprivate func _rowClicked(_ row: _Row, extend: Bool) {
        guard let i = _index(of: row) else { return }
        selectRowIndexes(IndexSet(integer: i), byExtendingSelection: extend)
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

// MARK: - Row view

/// One row: its criteria controls and the +/− buttons.
@MainActor final class _NSRuleEditorRowView: NSView, NSSelectorHandling {
    private unowned let editor: NSRuleEditor
    let row: NSRuleEditor._Row
    private let depth: Int
    private var controls: [NSView] = []
    private var addButton: NSButton?
    private var removeButton: NSButton?
    var isSelected = false { didSet { needsDisplay = true } }
    var stripe = false

    init(editor: NSRuleEditor, row: NSRuleEditor._Row, depth: Int) {
        self.editor = editor
        self.row = row
        self.depth = depth
        super.init(frame: .zero)
        _makeControls()
    }
    required init?(coder: NSCoder) { unimplemented() }

    override var isFlipped: Bool { true }

    private func _makeControls() {
        for (level, value) in row.displayValues.enumerated() {
            let view: NSView
            if let v = value as? NSView {
                v.removeFromSuperview()
                if v.frame.width < 1 { v.setFrameSize(NSSize(width: 100, height: v.frame.height < 1 ? 22 : v.frame.height)) }
                (v as? NSControl)?.isEnabled = editor.isEditable
                view = v
            } else if editor._siblingCount(level: level, in: row) > 1 {
                let p = NSPopUpButton(frame: .zero, pullsDown: false)
                p.addItems(withTitles: editor._choices(level: level, in: row))
                let current = row.criteria[level]
                let siblings = editor._siblingIndex(of: current, level: level, in: row)
                p.selectItem(at: siblings)
                p.tag = level
                p.target = self
                p.action = Selector(("criterionChanged:"))
                p.isEnabled = editor.isEditable
                p.sizeToFit()
                view = p
            } else {
                let title: String
                if let s = value as? String { title = s } else if let m = value as? NSMenuItem { title = m.title } else { title = String(describing: value) }
                let label = NSTextField(labelWithString: title)
                label.sizeToFit()
                view = label
            }
            controls.append(view)
            addSubview(view)
        }
        if editor._canAdd(row) {
            let b = NSButton(title: "+", target: self, action: Selector(("addRow:")))
            b.bezelStyle = .circular
            addButton = b
            addSubview(b)
        }
        if editor.isEditable {
            let b = NSButton(title: "\u{2212}", target: self, action: Selector(("removeRow:")))
            b.bezelStyle = .circular
            b.isEnabled = editor._canRemove(row)
            removeButton = b
            addSubview(b)
        }
    }

    func _layoutControls() {
        let h = bounds.height
        var x: CGFloat = 8 + CGFloat(depth) * 22
        for v in controls {
            var size = v.frame.size
            if v is NSPopUpButton || (v as? NSTextField)?.isEditable == false {
                let fit = v.intrinsicContentSize
                if fit.width > 0 { size.width = fit.width }
                if fit.height > 0 { size.height = fit.height }
            }
            size.height = min(size.height, h - 2)
            v.frame = NSRect(x: x, y: ((h - size.height) / 2).rounded(), width: size.width, height: size.height)
            x += size.width + 6
        }
        let bw: CGFloat = 20
        var right = bounds.width - 6
        for b in [addButton, removeButton].compactMap({ $0 }) {
            right -= bw
            b.frame = NSRect(x: right, y: ((h - bw) / 2).rounded(), width: bw, height: bw)
            right -= 4
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
            NSBezierPath.fill(bounds)
        } else if stripe {
            NSColor.alternatingContentBackgroundColors.last?.setFill()
            NSBezierPath.fill(bounds)
        }
        NSColor.separatorColor.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
    }

    override func mouseDown(with event: NSEvent) {
        editor._rowClicked(row, extend: event.modifierFlags.contains(.shift))
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action.description {
        case "criterionChanged:":
            guard let p = sender as? NSPopUpButton else { return false }
            editor._choose(p.indexOfSelectedItem, level: p.tag, in: row)
            return true
        case "addRow:": editor._addRow(after: row); return true
        case "removeRow:": editor._remove(row); return true
        default: return false
        }
    }
}

extension NSRuleEditor {
    /// The position of `criterion` among the criteria offered at `level`.
    fileprivate func _siblingIndex(of criterion: Any, level: Int, in row: _Row) -> Int {
        let kids = _children(of: level == 0 ? nil : row.criteria[level - 1], rowType: row.rowType)
        return kids.firstIndex { _KVC.same($0, criterion) } ?? 0
    }
}

// MARK: - Predicate construction

enum _NSRulePredicates {
    static func logicalType(_ value: Any?) -> NSCompoundPredicate.LogicalType? {
        guard let v = _KVC.flatten(value) else { return nil }
        if let t = v as? NSCompoundPredicate.LogicalType { return t }
        if let n = _KVC.number(v) { return NSCompoundPredicate.LogicalType(rawValue: UInt(n)) }
        return nil
    }

    static func compound(_ type: NSCompoundPredicate.LogicalType, _ subpredicates: [NSPredicate]) -> NSPredicate {
        #if canImport(ObjectiveC)
        return NSCompoundPredicate(type: type, subpredicates: subpredicates)
        #else
        return _NSRuleCompoundPredicate(type: type, subpredicates: subpredicates)
        #endif
    }

    static func operatorType(_ value: Any?) -> NSComparisonPredicate.Operator? {
        guard let v = _KVC.flatten(value) else { return nil }
        if let o = v as? NSComparisonPredicate.Operator { return o }
        if let n = _KVC.number(v) { return NSComparisonPredicate.Operator(rawValue: UInt(n)) }
        return nil
    }

    static func modifier(_ value: Any?) -> NSComparisonPredicate.Modifier {
        guard let v = _KVC.flatten(value) else { return .direct }
        if let m = v as? NSComparisonPredicate.Modifier { return m }
        if let n = _KVC.number(v), let m = NSComparisonPredicate.Modifier(rawValue: UInt(n)) { return m }
        return .direct
    }

    static func options(_ value: Any?) -> NSComparisonPredicate.Options {
        guard let v = _KVC.flatten(value) else { return [] }
        if let o = v as? NSComparisonPredicate.Options { return o }
        if let n = _KVC.number(v) { return NSComparisonPredicate.Options(rawValue: UInt(n)) }
        return []
    }

    /// A comparison predicate from a simple row's merged parts; nil when a side or the
    /// operator is missing.
    static func comparison(_ parts: [NSRuleEditor.PredicatePartKey: Any]) -> NSPredicate? {
        guard let left = parts[.leftExpression], let right = parts[.rightExpression] else { return nil }
        let modifier = modifier(parts[.comparisonModifier])
        let options = options(parts[.options])
        #if canImport(ObjectiveC)
        let l = (left as? NSExpression) ?? NSExpression(forKeyPath: String(describing: left))
        let r = (right as? NSExpression) ?? NSExpression(forConstantValue: right)
        if let sel = parts[.customSelector] {
            let selector = (sel as? Selector) ?? NSSelectorFromString(String(describing: sel))
            return NSComparisonPredicate(leftExpression: l, rightExpression: r, customSelector: selector)
        }
        guard let op = operatorType(parts[.operatorType]) else { return nil }
        return NSComparisonPredicate(leftExpression: l, rightExpression: r, modifier: modifier, type: op, options: options)
        #else
        if parts[.customSelector] != nil { unimplemented() }   // no selector dispatch without the runtime
        guard let op = operatorType(parts[.operatorType]), let keyPath = left as? String else { return nil }
        return _NSRuleComparisonPredicate(keyPath: keyPath, operator: op, value: _KVC.flatten(right), modifier: modifier, options: options)
        #endif
    }
}

#if !canImport(ObjectiveC)
/// A compound predicate that prints its format (corelibs' NSCompoundPredicate does not).
final class _NSRuleCompoundPredicate: NSCompoundPredicate {
    override var predicateFormat: String {
        let word: String
        switch compoundPredicateType {
        case .and: word = " AND "
        case .or: word = " OR "
        case .not:
            return "NOT " + _NSRuleCompoundPredicate.operand(subpredicates.first)
        @unknown default: word = " AND "
        }
        if subpredicates.isEmpty { return compoundPredicateType == .or ? "FALSEPREDICATE" : "TRUEPREDICATE" }
        return subpredicates.map { _NSRuleCompoundPredicate.operand($0) }.joined(separator: word)
    }

    static func operand(_ p: NSPredicate?) -> String {
        guard let p else { return "TRUEPREDICATE" }
        if p is NSCompoundPredicate { return "(" + p.predicateFormat + ")" }
        return p.predicateFormat
    }
}

/// A comparison of the value at a key path with a constant, evaluated through the port's
/// key-value coding (NSComparisonPredicate is unavailable in swift-corelibs-foundation).
final class _NSRuleComparisonPredicate: NSPredicate {
    let keyPath: String
    let op: NSComparisonPredicate.Operator
    let constant: Any?
    let modifier: NSComparisonPredicate.Modifier
    let comparisonOptions: NSComparisonPredicate.Options

    init(keyPath: String, operator op: NSComparisonPredicate.Operator, value: Any?, modifier: NSComparisonPredicate.Modifier, options: NSComparisonPredicate.Options) {
        self.keyPath = keyPath
        self.op = op
        self.constant = value
        self.modifier = modifier
        self.comparisonOptions = options
        super.init(value: true)
    }
    required init?(coder: NSCoder) { unimplemented() }

    override func evaluate(with object: Any?) -> Bool { evaluate(with: object, substitutionVariables: nil) }

    override func evaluate(with object: Any?, substitutionVariables bindings: [String: Any]?) -> Bool {
        let lhs = _KVC.value(object, forKeyPath: keyPath)
        switch modifier {
        case .direct: return Self.test(lhs, op, constant, comparisonOptions)
        case .any: return (_KVC.flatten(lhs).flatMap(_KVC.arrayValue) ?? []).contains { Self.test($0, op, constant, comparisonOptions) }
        case .all: return (_KVC.flatten(lhs).flatMap(_KVC.arrayValue) ?? []).allSatisfy { Self.test($0, op, constant, comparisonOptions) }
        @unknown default: return false
        }
    }

    static func string(_ v: Any?, _ options: NSComparisonPredicate.Options) -> String? {
        guard let v = _KVC.flatten(v) else { return nil }
        var s = (v as? String) ?? (v as? NSString).map { String(describing: $0) }
        if s == nil { return nil }
        if options.contains(.caseInsensitive) { s = s!.lowercased() }
        if options.contains(.diacriticInsensitive) { s = s!.folding(options: .diacriticInsensitive, locale: nil) }
        return s
    }

    static func test(_ lhs: Any?, _ op: NSComparisonPredicate.Operator, _ rhs: Any?, _ options: NSComparisonPredicate.Options) -> Bool {
        let ls = string(lhs, options), rs = string(rhs, options)
        switch op {
        case .lessThan: return order(lhs, rhs, ls, rs) == .orderedAscending
        case .lessThanOrEqualTo: return order(lhs, rhs, ls, rs) != .orderedDescending
        case .greaterThan: return order(lhs, rhs, ls, rs) == .orderedDescending
        case .greaterThanOrEqualTo: return order(lhs, rhs, ls, rs) != .orderedAscending
        case .equalTo: return equal(lhs, rhs, ls, rs)
        case .notEqualTo: return !equal(lhs, rhs, ls, rs)
        case .beginsWith: guard let l = ls, let r = rs else { return false }; return l.hasPrefix(r)
        case .endsWith: guard let l = ls, let r = rs else { return false }; return l.hasSuffix(r)
        case .contains:
            if let l = ls, let r = rs { return r.isEmpty ? false : l.contains(r) }
            if let a = _KVC.flatten(lhs).flatMap(_KVC.arrayValue) { return a.contains { _KVC.same($0, rhs) } }
            return false
        case .in:
            if let l = ls, let r = rs { return r.contains(l) }
            if let a = _KVC.flatten(rhs).flatMap(_KVC.arrayValue) { return a.contains { equal(lhs, $0, ls, string($0, options)) } }
            return false
        case .like: guard let l = ls, let r = rs else { return false }; return matches(l, pattern: likePattern(r))
        case .matches: guard let l = ls, let r = rs else { return false }; return matches(l, pattern: r)
        case .between:
            guard let bounds = _KVC.flatten(rhs).flatMap(_KVC.arrayValue), bounds.count == 2 else { return false }
            return _KVC.compare(lhs, bounds[0]) != .orderedAscending && _KVC.compare(lhs, bounds[1]) != .orderedDescending
        case .customSelector: unimplemented()
        @unknown default: return false
        }
    }

    private static func order(_ l: Any?, _ r: Any?, _ ls: String?, _ rs: String?) -> ComparisonResult {
        if let ls, let rs { return ls.compare(rs) }
        return _KVC.compare(l, r)
    }

    private static func equal(_ l: Any?, _ r: Any?, _ ls: String?, _ rs: String?) -> Bool {
        if let ls, let rs { return ls == rs }
        if let x = _KVC.flatten(l).flatMap(_KVC.number), let y = _KVC.flatten(r).flatMap(_KVC.number), !(l is String), !(r is String) { return x == y }
        return _KVC.same(l, r)
    }

    private static func likePattern(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "*": out += ".*"
            case "?": out += "."
            default: out += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        return out
    }

    private static func matches(_ s: String, pattern: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$", options: [.dotMatchesLineSeparators]) else { return false }
        return re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)) != nil
    }

    override var predicateFormat: String {
        var s = ""
        switch modifier {
        case .any: s = "ANY "
        case .all: s = "ALL "
        default: break
        }
        s += keyPath + " " + Self.operatorString(op)
        var flags = ""
        if comparisonOptions.contains(.caseInsensitive) { flags += "c" }
        if comparisonOptions.contains(.diacriticInsensitive) { flags += "d" }
        if comparisonOptions.contains(.normalized) { flags += "n" }
        if !flags.isEmpty { s += "[" + flags + "]" }
        return s + " " + Self.literal(constant)
    }

    static func operatorString(_ op: NSComparisonPredicate.Operator) -> String {
        switch op {
        case .lessThan: return "<"
        case .lessThanOrEqualTo: return "<="
        case .greaterThan: return ">"
        case .greaterThanOrEqualTo: return ">="
        case .equalTo: return "=="
        case .notEqualTo: return "!="
        case .matches: return "MATCHES"
        case .like: return "LIKE"
        case .beginsWith: return "BEGINSWITH"
        case .endsWith: return "ENDSWITH"
        case .in: return "IN"
        case .contains: return "CONTAINS"
        case .between: return "BETWEEN"
        case .customSelector: return "FUNCTION"
        @unknown default: return "=="
        }
    }

    static func literal(_ v: Any?) -> String {
        guard let v = _KVC.flatten(v) else { return "nil" }
        if let s = v as? String {
            return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        if let b = v as? Bool { return b ? "1" : "0" }
        if let a = _KVC.arrayValue(v) { return "{" + a.map { literal($0) }.joined(separator: ", ") + "}" }
        return String(describing: v)
    }
}
#endif
