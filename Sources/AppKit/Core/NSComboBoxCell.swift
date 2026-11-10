// NSComboBoxCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A text field cell with a disclosure button on its trailing edge and a list of items.
// The items live here (an internal list, or a data source when `usesDataSource` is on;
// an NSComboBox's own data source is consulted through the control). The list opens in a
// borderless non-activating window holding an NSTableView (`_NSComboBoxPopUp`), tracked
// through NSApplication.sendEvent the way menus are.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell
@MainActor open class NSComboBoxCell: NSTextFieldCell {
    // MARK: Storage
    private var _items: [Any] = []
    private weak var _dataSource: (any NSComboBoxCellDataSource)?
    private var _usesDataSource = false
    private var _completes = false
    private var _hasVerticalScroller = true
    private var _intercellSpacing = NSSize(width: 3, height: 2)
    private var _isButtonBordered = true
    private var _itemHeight: CGFloat = 17
    private var _numberOfVisibleItems = 5
    private var _selectedIndex = -1
    internal var _popUp: _NSComboBoxPopUp?

    /// Width of the disclosure button's strip at the trailing edge.
    static let buttonWidth: CGFloat = 20

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/init(textcell:)
    @MainActor public override init(textCell string: String) { super.init(textCell: string) }
    public required init(coder: NSCoder) { super.init(coder: coder) }

    private var _comboBox: NSComboBox? { _controlView as? NSComboBox }

    // MARK: Items (the list, or the data source)

    /// Number of items in the list, from the data source when one is used.
    internal func _count() -> Int {
        if _usesDataSource {
            if let ds = _dataSource { return max(0, ds.numberOfItems(in: self)) }
            if let c = _comboBox, let ds = c._comboDataSource { return max(0, ds.numberOfItems(in: c)) }
            return 0
        }
        return _items.count
    }
    internal func _value(at index: Int) -> Any? {
        guard index >= 0, index < _count() else { return nil }
        if _usesDataSource {
            if let ds = _dataSource { return ds.comboBoxCell(self, objectValueForItemAt: index) }
            if let c = _comboBox, let ds = c._comboDataSource { return ds.comboBox(c, objectValueForItemAt: index) }
            return nil
        }
        return _items[index]
    }
    internal static func _string(for value: Any?) -> String {
        switch value {
        case nil: return ""
        case let s as String: return s
        case let a as NSAttributedString: return a.string
        case let v: return String(describing: v)
        }
    }
    /// The index of the item whose string value is `string`, through the data source's
    /// lookup when it has one, else by searching the values.
    internal func _index(ofString string: String) -> Int {
        if _usesDataSource {
            var i = NSNotFound
            if let ds = _dataSource { i = ds.comboBoxCell(self, indexOfItemWithStringValue: string) }
            else if let c = _comboBox, let ds = c._comboDataSource { i = ds.comboBox(c, indexOfItemWithStringValue: string) }
            if i != NSNotFound { return i }
        }
        let n = _count()
        for i in 0..<n where NSComboBoxCell._string(for: _value(at: i)) == string { return i }
        return -1
    }
    /// The value that should follow the typed `string`, from the data source or the
    /// first item it is a prefix of (ignoring case).
    internal func _completed(_ string: String) -> String? {
        guard !string.isEmpty else { return nil }
        if _usesDataSource {
            if let ds = _dataSource, let s = ds.comboBoxCell(self, completedString: string) { return s }
            if let c = _comboBox, let ds = c._comboDataSource, let s = ds.comboBox(c, completedString: string) { return s }
        }
        let n = _count()
        let lower = string.lowercased()
        for i in 0..<n {
            let s = NSComboBoxCell._string(for: _value(at: i))
            if s.lowercased().hasPrefix(lower) { return s }
        }
        return nil
    }
    private func _itemsChanged() {
        if _selectedIndex >= _count() { _selectedIndex = -1 }
        _popUp?.reload()
        _changed()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/additem(withobjectvalue:)
    @MainActor open func addItem(withObjectValue object: Any) { _items.append(object); _itemsChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/additems(withobjectvalues:)
    @MainActor open func addItems(withObjectValues objects: [Any]) { _items.append(contentsOf: objects); _itemsChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/completedstring(_:)
    @MainActor open func completedString(_ string: String) -> String? { _completed(string) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/completes
    @MainActor open var completes: Bool {
        get { _completes }
        set { _completes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/datasource
    @MainActor open var dataSource: (any NSComboBoxCellDataSource)? {
        get { _dataSource }
        set { _dataSource = newValue; _itemsChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/deselectitem(at:)
    @MainActor open func deselectItem(at index: Int) {
        guard index == _selectedIndex, index >= 0 else { return }
        _selectedIndex = -1
        _popUp?.syncSelection()
        _postSelectionDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/hasverticalscroller
    @MainActor open var hasVerticalScroller: Bool {
        get { _hasVerticalScroller }
        set { _hasVerticalScroller = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/indexofitem(withobjectvalue:)
    @MainActor open func indexOfItem(withObjectValue object: Any) -> Int {
        let n = _count()
        for i in 0..<n {
            let v = _value(at: i)
            if let a = v as? AnyHashable, let b = object as? AnyHashable { if a == b { return i } }
            else if let a = v as AnyObject?, a === (object as AnyObject) { return i }
            else if NSComboBoxCell._string(for: v) == NSComboBoxCell._string(for: object) { return i }
        }
        return NSNotFound
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/indexofselecteditem
    @MainActor open var indexOfSelectedItem: Int { _selectedIndex }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/insertitem(withobjectvalue:at:)
    @MainActor open func insertItem(withObjectValue object: Any, at index: Int) {
        let i = min(max(0, index), _items.count)
        _items.insert(object, at: i)
        if _selectedIndex >= i { _selectedIndex += 1 }
        _itemsChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/intercellspacing
    @MainActor open var intercellSpacing: NSSize {
        get { _intercellSpacing }
        set { _intercellSpacing = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/isbuttonbordered
    @MainActor open var isButtonBordered: Bool {
        get { _isButtonBordered }
        set { _isButtonBordered = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/itemheight
    @MainActor open var itemHeight: CGFloat {
        get { _itemHeight }
        set { _itemHeight = max(1, newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/itemobjectvalue(at:)
    @MainActor open func itemObjectValue(at index: Int) -> Any {
        precondition(index >= 0 && index < _count(), "NSComboBoxCell: item index \(index) out of range")
        return _value(at: index) ?? ""
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/notenumberofitemschanged()
    @MainActor open func noteNumberOfItemsChanged() { _itemsChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/numberofitems
    @MainActor open var numberOfItems: Int { _count() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/numberofvisibleitems
    @MainActor open var numberOfVisibleItems: Int {
        get { _numberOfVisibleItems }
        set { _numberOfVisibleItems = max(1, newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/objectvalueofselecteditem
    @MainActor open var objectValueOfSelectedItem: Any? { _selectedIndex >= 0 ? _value(at: _selectedIndex) : nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/objectvalues
    @MainActor open var objectValues: [Any] { _usesDataSource ? (0..<_count()).compactMap { _value(at: $0) } : _items }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/reloaddata()
    @MainActor open func reloadData() { _itemsChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/removeallitems()
    @MainActor open func removeAllItems() { _items.removeAll(); _selectedIndex = -1; _itemsChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/removeitem(at:)
    @MainActor open func removeItem(at index: Int) {
        guard _items.indices.contains(index) else { return }
        _items.remove(at: index)
        if _selectedIndex == index { _selectedIndex = -1 } else if _selectedIndex > index { _selectedIndex -= 1 }
        _itemsChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/removeitem(withobjectvalue:)
    @MainActor open func removeItem(withObjectValue object: Any) {
        let i = indexOfItem(withObjectValue: object)
        if i != NSNotFound { removeItem(at: i) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/scrollitematindextotop(_:)
    @MainActor open func scrollItemAtIndexToTop(_ index: Int) { _popUp?.scroll(index, toTop: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/scrollitematindextovisible(_:)
    @MainActor open func scrollItemAtIndexToVisible(_ index: Int) { _popUp?.scroll(index, toTop: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/selectitem(at:)
    @MainActor open func selectItem(at index: Int) {
        guard index >= 0, index < _count() else { return }
        _select(index, final: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/selectitem(withobjectvalue:)
    @MainActor open func selectItem(withObjectValue object: Any?) {
        guard let object else { return }
        let i = indexOfItem(withObjectValue: object)
        if i != NSNotFound { selectItem(at: i) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscomboboxcell/usesdatasource
    @MainActor open var usesDataSource: Bool {
        get { _usesDataSource }
        set { _usesDataSource = newValue; _itemsChanged() }
    }

    /// Selects an item and shows its value in the field. While the list is open and the
    /// user is arrowing through it (`final` false) the selection is only "changing".
    internal func _select(_ index: Int, final: Bool) {
        _selectedIndex = index
        let value = _value(at: index)
        if let c = _comboBox { c._showValue(value) } else { objectValue = value; stringValue = NSComboBoxCell._string(for: value) }
        _popUp?.syncSelection()
        if final { _postSelectionDidChange() } else { _postSelectionIsChanging() }
    }

    private func _postSelectionDidChange() {
        guard let c = _comboBox else { return }
        let n = Notification(name: NSComboBox.selectionDidChangeNotification, object: c)
        NotificationCenter.default.post(n)
        c._comboDelegate?.comboBoxSelectionDidChange(n)
        c._accessibilityValueChanged()
    }
    private func _postSelectionIsChanging() {
        guard let c = _comboBox else { return }
        let n = Notification(name: NSComboBox.selectionIsChangingNotification, object: c)
        NotificationCenter.default.post(n)
        c._comboDelegate?.comboBoxSelectionIsChanging(n)
    }

    // MARK: Geometry and drawing

    /// The text keeps clear of the button strip at the trailing edge.
    @MainActor internal override func _textRect(forBounds rect: NSRect) -> NSRect {
        var r = super._textRect(forBounds: rect)
        let w = min(r.width, NSComboBoxCell.buttonWidth)
        if _isRightToLeft { r.origin.x += w }
        r.size.width -= w
        return r
    }
    internal var _isRightToLeft: Bool { _controlView?.userInterfaceLayoutDirection == .rightToLeft }
    /// The disclosure button's rect inside the cell frame.
    @MainActor internal func _buttonRect(forBounds rect: NSRect) -> NSRect {
        let inset: CGFloat = _isBezeled || _isBordered ? 2 : 0
        let w = min(rect.width, NSComboBoxCell.buttonWidth)
        let x = _isRightToLeft ? rect.minX + inset : rect.maxX - inset - w
        return NSRect(x: x, y: rect.minY + inset, width: w, height: max(0, rect.height - 2 * inset))
    }
    @MainActor open override var cellSize: NSSize {
        var s = super.cellSize
        s.width += NSComboBoxCell.buttonWidth
        s.height = max(s.height, 21)
        return s
    }

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.draw(withFrame: cellFrame, in: controlView)
        _drawButton(in: _buttonRect(forBounds: cellFrame), flipped: controlView.isFlipped)
    }

    private func _drawButton(in rect: NSRect, flipped: Bool) {
        guard !rect.isEmpty else { return }
        let open = _popUp != nil
        var chevron: NSColor = _isEnabled ? .secondaryLabelColor : .disabledControlTextColor
        if _isButtonBordered {
            let fill: NSColor = _isEnabled ? (open ? NSColor.controlAccentColor.withAlphaComponent(0.8) : .controlAccentColor) : NSColor.controlColor
            fill.setFill()
            let radius: CGFloat = bezelStyle == .roundedBezel ? rect.height / 2 : 4
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            chevron = _isEnabled ? .white : .disabledControlTextColor
        }
        // Two chevrons (up and down), as the standard combo box button shows.
        let cx = rect.midX, cy = rect.midY
        let w: CGFloat = 3, h: CGFloat = 2.2, gap: CGFloat = 1.6
        let up = NSBezierPath(), down = NSBezierPath()
        let dir: CGFloat = flipped ? 1 : -1      // +1: y grows downwards
        up.move(to: NSPoint(x: cx - w, y: cy - dir * gap))
        up.line(to: NSPoint(x: cx, y: cy - dir * (gap + h)))
        up.line(to: NSPoint(x: cx + w, y: cy - dir * gap))
        down.move(to: NSPoint(x: cx - w, y: cy + dir * gap))
        down.line(to: NSPoint(x: cx, y: cy + dir * (gap + h)))
        down.line(to: NSPoint(x: cx + w, y: cy + dir * gap))
        chevron.setStroke()
        for p in [up, down] {
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.stroke()
        }
    }

    // MARK: The pop-up list

    /// Opens the list under the cell (or closes it when it is open).
    @MainActor internal func _togglePopUp(withFrame cellFrame: NSRect, in controlView: NSView) {
        if _popUp != nil { _dismissPopUp() } else { _popUp(withFrame: cellFrame, in: controlView, openedWithMouseDown: true) }
    }

    @MainActor internal func _popUp(withFrame cellFrame: NSRect, in controlView: NSView, openedWithMouseDown: Bool = false) {
        guard _isEnabled, _popUp == nil, let window = controlView.window else { return }
        if let c = _comboBox {
            let n = Notification(name: NSComboBox.willPopUpNotification, object: c)
            NotificationCenter.default.post(n)
            c._comboDelegate?.comboBoxWillPopUp(n)
        }
        let anchor = window.convertToScreen(controlView.convert(cellFrame, to: nil))
        let popUp = _NSComboBoxPopUp(cell: self, control: controlView, anchor: anchor, openedWithMouseDown: openedWithMouseDown)
        _popUp = popUp
        popUp.open()
        _changed()
    }

    /// Closes the list without choosing.
    @MainActor internal func _dismissPopUp() {
        guard let p = _popUp else { return }
        if let c = _comboBox {
            let n = Notification(name: NSComboBox.willDismissNotification, object: c)
            NotificationCenter.default.post(n)
            c._comboDelegate?.comboBoxWillDismiss(n)
        }
        _popUp = nil
        p.close()
        _changed()
    }

    /// The user chose a row in the list: select it, close the list, send the action.
    @MainActor internal func _choose(_ index: Int) {
        _dismissPopUp()
        _select(index, final: true)
        (_controlView as? NSControl)?._fireAction()
    }
}

// MARK: - The list window

/// The borderless window the list opens in. Like a menu window it never becomes key:
/// the combo box's window keeps the keyboard and NSApplication hands events over.
@MainActor
final class _NSComboBoxPopUpWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isReleasedWhenClosed = false
    }
    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The content of the list window: a bordered box around the scroll view.
@MainActor
final class _NSComboBoxListView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

/// One open combo box list: the window, its table over the cell's items, and the
/// mouse and keyboard routed to it by NSApplication.sendEvent.
@MainActor
final class _NSComboBoxPopUp: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSelectorHandling {
    private(set) static var current: _NSComboBoxPopUp?
    static var isOpen: Bool { current != nil }

    let cell: NSComboBoxCell
    private(set) weak var control: NSView?
    let window: _NSComboBoxPopUpWindow
    let scrollView = NSScrollView(frame: .zero)
    let table = NSTableView(frame: .zero)
    private let anchor: NSRect
    private var sawFirstMouseUp: Bool
    private var openPoint: NSPoint?
    private var movedSinceOpen = false
    private static let border: CGFloat = 1
    private static let rowClicked = Selector(("_comboRowClicked:"))

    init(cell: NSComboBoxCell, control: NSView, anchor: NSRect, openedWithMouseDown: Bool) {
        self.cell = cell
        self.control = control
        self.anchor = anchor
        sawFirstMouseUp = !openedWithMouseDown
        window = _NSComboBoxPopUpWindow(contentRect: NSRect(origin: anchor.origin, size: NSSize(width: max(anchor.width, 40), height: 40)))
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppKitCross.ComboBoxItem"))
        column.width = max(10, anchor.width - 2 * _NSComboBoxPopUp.border)
        column.dataCell = {
            let c = NSTextFieldCell(textCell: "")
            c.font = cell.font
            c.alignment = cell.alignment
            return c
        }()
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = cell.itemHeight
        table.intercellSpacing = cell.intercellSpacing
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = _NSComboBoxPopUp.rowClicked
        table.setAccessibilityRole(.list)
        scrollView.documentView = table
        scrollView.hasVerticalScroller = cell.hasVerticalScroller
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        let content = _NSComboBoxListView(frame: .zero)
        content.addSubview(scrollView)
        window.contentView = content
    }

    private var rowStep: CGFloat { cell.itemHeight + cell.intercellSpacing.height }

    /// Sizes the window to the visible rows and places it under the field (above it when
    /// the screen has no room below), then shows it.
    func open() {
        _NSComboBoxPopUp.current?.dismiss()
        _NSComboBoxPopUp.current = self
        openPoint = Platform.backend.mouseLocation
        layout()
        syncSelection()
        if cell.indexOfSelectedItem >= 0 { table.scrollRowToVisible(cell.indexOfSelectedItem) }
        window.orderFront(nil)
    }

    private func layout() {
        let count = cell.numberOfItems
        let visible = max(1, min(count, cell.numberOfVisibleItems))
        let b = _NSComboBoxPopUp.border
        let height = CGFloat(visible) * rowStep - (count > 0 ? cell.intercellSpacing.height : 0) + 2 * b + 2
        let width = max(anchor.width, 40)
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            if origin.y < visibleFrame.minY, anchor.maxY + height <= visibleFrame.maxY { origin.y = anchor.maxY }
            if origin.x + width > visibleFrame.maxX { origin.x = max(visibleFrame.minX, visibleFrame.maxX - width) }
        }
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
        scrollView.frame = NSRect(x: b, y: b + 1, width: width - 2 * b, height: height - 2 * b - 2)
        scrollView.tile()
        if let c = table.tableColumns.first { c.width = max(10, scrollView.contentView.bounds.width) }
        table.tile()
    }

    func close() {
        if _NSComboBoxPopUp.current === self { _NSComboBoxPopUp.current = nil }
        window.close()
    }
    /// Closes through the cell, so the will-dismiss notification goes out.
    func dismiss() { cell._dismissPopUp() }

    func reload() {
        table.reloadData()
        layout()
        syncSelection()
    }
    func syncSelection() {
        let i = cell.indexOfSelectedItem
        if i >= 0 && i < table.numberOfRows { table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
    }
    func scroll(_ index: Int, toTop: Bool) {
        guard index >= 0, index < table.numberOfRows else { return }
        if toTop { scrollView.contentView.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: index).minY)) } else { table.scrollRowToVisible(index) }
    }

    // NSTableViewDataSource / delegate
    func numberOfRows(in tableView: NSTableView) -> Int { cell.numberOfItems }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { NSComboBoxCell._string(for: cell._value(at: row)) }

    /// A click on a row (the table's action from mouseUp) chooses it.
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action == _NSComboBoxPopUp.rowClicked else { return false }
        let row = table.clickedRow
        if row >= 0 { cell._choose(row) }
        return true
    }
    func respondsToSelectorAction(_ action: Selector) -> Bool { action == _NSComboBoxPopUp.rowClicked }

    // MARK: Events (from NSApplication.sendEvent)

    private func screenPoint(of event: NSEvent) -> NSPoint {
        if let w = event.window { return w.convertPoint(toScreen: event.locationInWindow) }
        return event.locationInWindow
    }
    private func eventInList(_ event: NSEvent) -> NSEvent? {
        let p = screenPoint(of: event)
        guard window.frame.contains(p) else { return nil }
        if event.window === window { return event }
        let local = window.convertPoint(fromScreen: p)
        return NSEvent.mouseEvent(with: event.type, location: local, modifierFlags: event.modifierFlags, timestamp: event.timestamp, windowNumber: window.windowNumber,
                                  context: nil, eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure)
    }

    /// Handles an event while the list is open; returns false for events the combo box's
    /// window should still see (typing goes on in the field).
    func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if let e = eventInList(event) { window.sendEvent(e); return true }
            // A click elsewhere closes the list; on the field's button it toggles, so let it through.
            dismiss()
            if let control, let w = control.window, event.window === w,
               control.hitTest(control.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow) === control,
               let combo = control as? NSComboBox, combo._buttonRect.contains(control.convert(event.locationInWindow, from: nil)) {
                return true
            }
            return false
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if !sawFirstMouseUp && !movedSinceOpen {
                // Releasing the opening click without moving leaves the list open.
                sawFirstMouseUp = true
                return true
            }
            sawFirstMouseUp = true
            if let e = eventInList(event) { window.sendEvent(e) }
            return true
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let p = screenPoint(of: event)
            if let o = openPoint, abs(p.x - o.x) > 3 || abs(p.y - o.y) > 3 { movedSinceOpen = true }
            // Dragging over the list highlights the row under the pointer.
            if event.type != .mouseMoved, let e = eventInList(event) {
                let local = table.convert(e.locationInWindow, from: nil)
                let row = table.row(at: local)
                if row >= 0 { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            }
            return true
        case .scrollWheel:
            if let e = eventInList(event) { window.sendEvent(e); return true }
            return false
        case .keyDown:
            return keyDown(event)
        default:
            return false
        }
    }

    private func keyDown(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        let count = cell.numberOfItems
        func move(_ delta: Int) {
            guard count > 0 else { return }
            let current = cell.indexOfSelectedItem
            let next = current < 0 ? (delta > 0 ? 0 : count - 1) : min(max(current + delta, 0), count - 1)
            cell._select(next, final: false)
            table.scrollRowToVisible(next)
        }
        switch (event.keyCode, chars) {
        case (125, _), (_, "\u{F701}"): move(1); return true            // down
        case (126, _), (_, "\u{F700}"): move(-1); return true           // up
        case (36, _), (76, _), (_, "\r"), (_, "\u{3}"):                 // return, enter
            if table.selectedRow >= 0 { cell._choose(table.selectedRow) } else { dismiss() }
            return true
        case (53, _), (_, "\u{1B}"):                                    // escape
            dismiss()
            return true
        default:
            return false     // typing continues in the field
        }
    }

    /// Selection the table reports (a click chose a row before mouseUp) is "changing".
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, row != cell.indexOfSelectedItem else { return }
        cell._select(row, final: false)
    }
}
