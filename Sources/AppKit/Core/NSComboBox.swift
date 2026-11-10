// NSComboBox (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A text field whose cell (NSComboBoxCell) carries a list of items and a disclosure
// button that opens the list in a pop-up window. The list API forwards to the cell, as
// NSPopUpButton's does; the data source and delegate are the control's own, consulted by
// the cell through the control when `usesDataSource` is set.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox
@MainActor open class NSComboBox: NSTextField {
    private weak var _dataSource: (any NSComboBoxDataSource)?
    private var _completing = false
    private var _previousLength = 0

    internal var _comboCell: NSComboBoxCell { _cell as! NSComboBoxCell }
    internal var _comboDataSource: (any NSComboBoxDataSource)? { _dataSource }
    /// The delegate, when it is a combo box delegate.
    internal var _comboDelegate: (any NSComboBoxDelegate)? { delegate as? NSComboBoxDelegate }

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSComboBoxCell(textCell: "") }

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = true
        isSelectable = true
        isBezeled = true
        drawsBackground = true
        bezelStyle = .roundedBezel
    }
    public required init?(coder: NSCoder) { unimplemented() }

    // SKIPPED (override type (any NSComboBoxDelegate)? differs from superclass (any NSTextFieldDelegate)?): @MainActor var delegate: (any NSComboBoxDelegate)? { get set }
    // The inherited `delegate` takes a combo box delegate (NSComboBoxDelegate refines
    // NSTextFieldDelegate); the combo box messages reach it when it is one.

    // MARK: Items

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/additem(withobjectvalue:)
    @MainActor open func addItem(withObjectValue object: Any) { _comboCell.addItem(withObjectValue: object) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/additems(withobjectvalues:)
    @MainActor open func addItems(withObjectValues objects: [Any]) { _comboCell.addItems(withObjectValues: objects) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/completes
    @MainActor open var completes: Bool {
        get { _comboCell.completes }
        set { _comboCell.completes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/datasource
    @MainActor open var dataSource: (any NSComboBoxDataSource)? {
        get { _dataSource }
        set { _dataSource = newValue; _comboCell.reloadData() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/deselectitem(at:)
    @MainActor open func deselectItem(at index: Int) { _comboCell.deselectItem(at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/hasverticalscroller
    @MainActor open var hasVerticalScroller: Bool {
        get { _comboCell.hasVerticalScroller }
        set { _comboCell.hasVerticalScroller = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/indexofitem(withobjectvalue:)
    @MainActor open func indexOfItem(withObjectValue object: Any) -> Int { _comboCell.indexOfItem(withObjectValue: object) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/indexofselecteditem
    @MainActor open var indexOfSelectedItem: Int { _comboCell.indexOfSelectedItem }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/insertitem(withobjectvalue:at:)
    @MainActor open func insertItem(withObjectValue object: Any, at index: Int) { _comboCell.insertItem(withObjectValue: object, at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/intercellspacing
    @MainActor open var intercellSpacing: NSSize {
        get { _comboCell.intercellSpacing }
        set { _comboCell.intercellSpacing = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/isbuttonbordered
    @MainActor open var isButtonBordered: Bool {
        get { _comboCell.isButtonBordered }
        set { _comboCell.isButtonBordered = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/itemheight
    @MainActor open var itemHeight: CGFloat {
        get { _comboCell.itemHeight }
        set { _comboCell.itemHeight = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/itemobjectvalue(at:)
    @MainActor open func itemObjectValue(at index: Int) -> Any { _comboCell.itemObjectValue(at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/notenumberofitemschanged()
    @MainActor open func noteNumberOfItemsChanged() { _comboCell.noteNumberOfItemsChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/numberofitems
    @MainActor open var numberOfItems: Int { _comboCell.numberOfItems }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/numberofvisibleitems
    @MainActor open var numberOfVisibleItems: Int {
        get { _comboCell.numberOfVisibleItems }
        set { _comboCell.numberOfVisibleItems = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/objectvalueofselecteditem
    @MainActor open var objectValueOfSelectedItem: Any? { _comboCell.objectValueOfSelectedItem }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/objectvalues
    @MainActor open var objectValues: [Any] { _comboCell.objectValues }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/reloaddata()
    @MainActor open func reloadData() { _comboCell.reloadData() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/removeallitems()
    @MainActor open func removeAllItems() { _comboCell.removeAllItems() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/removeitem(at:)
    @MainActor open func removeItem(at index: Int) { _comboCell.removeItem(at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/removeitem(withobjectvalue:)
    @MainActor open func removeItem(withObjectValue object: Any) { _comboCell.removeItem(withObjectValue: object) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/scrollitematindextotop(_:)
    @MainActor open func scrollItemAtIndexToTop(_ index: Int) { _comboCell.scrollItemAtIndexToTop(index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/scrollitematindextovisible(_:)
    @MainActor open func scrollItemAtIndexToVisible(_ index: Int) { _comboCell.scrollItemAtIndexToVisible(index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/selectitem(at:)
    @MainActor open func selectItem(at index: Int) { _comboCell.selectItem(at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/selectitem(withobjectvalue:)
    @MainActor open func selectItem(withObjectValue object: Any?) { _comboCell.selectItem(withObjectValue: object) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/selectiondidchangenotification
    static public var selectionDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSComboBoxSelectionDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/selectionischangingnotification
    static public var selectionIsChangingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSComboBoxSelectionIsChangingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/usesdatasource
    @MainActor open var usesDataSource: Bool {
        get { _comboCell.usesDataSource }
        set { _comboCell.usesDataSource = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/willdismissnotification
    static public var willDismissNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSComboBoxWillDismissNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscombobox/willpopupnotification
    static public var willPopUpNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSComboBoxWillPopUpNotification") }

    // MARK: Behaviour

    /// Whether the list is open.
    internal var _isPopUpOpen: Bool { _comboCell._popUp != nil }
    /// The disclosure button's rect, in the view.
    internal var _buttonRect: NSRect { _comboCell._buttonRect(forBounds: _cellFrame) }

    /// Shows an item's value in the field, in the editor too while editing.
    internal func _showValue(_ value: Any?) {
        _completing = true
        defer { _completing = false }
        _comboCell.objectValue = value
        _setStringValueUpdatingEditor(NSComboBoxCell._string(for: value))
        _previousLength = stringValue.count
    }

    /// A click on the button opens (or closes) the list; the field starts editing first,
    /// so the keyboard stays in it. Anywhere else edits as a text field does.
    @MainActor open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard isEnabled, _buttonRect.contains(p) || !isEditable else { super.mouseDown(with: event); return }
        if isEditable, currentEditor == nil { _ = window?.makeFirstResponder(self) }
        _comboCell._togglePopUp(withFrame: _cellFrame, in: self)
    }

    @MainActor open override func resetCursorRects() {
        guard isEnabled && (isEditable || isSelectable) else { return }
        var text = bounds
        let button = _buttonRect
        if _comboCell._isRightToLeft { text.origin.x = button.maxX; text.size.width -= button.maxX } else { text.size.width = button.minX }
        addCursorRect(text, cursor: .iBeam)
    }

    /// Down opens the list while editing; the list's own keys run once it is open.
    override func _editorDoCommand(by selector: Selector) -> Bool {
        if !_isPopUpOpen, NSStringFromSelector(selector) == "moveDown:" {
            _comboCell._popUp(withFrame: _cellFrame, in: self)
            return true
        }
        return super._editorDoCommand(by: selector)
    }

    /// Typing with `completes` on fills in the rest of the first matching item, selected
    /// so the next key replaces it.
    @MainActor open override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        guard !_completing, completes, let editor = currentEditor as? NSTextView else { _previousLength = stringValue.count; return }
        let typed = editor.string
        let grew = typed.count > _previousLength
        _previousLength = typed.count
        guard grew, editor.selectedRange.location == (typed as NSString).length, let completed = _comboCell._completed(typed), completed != typed, completed.count > typed.count else { return }
        _completing = true
        editor.string = completed
        _comboCell.stringValue = completed
        editor.selectedRange = NSRange(location: (typed as NSString).length, length: (completed as NSString).length - (typed as NSString).length)
        _previousLength = typed.count      // the next key replaces the completion: it grew when it passes the typed part
        _completing = false
    }

    @MainActor open override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, _isPopUpOpen { _comboCell._dismissPopUp() }
        super.viewWillMove(toWindow: newWindow)
    }

    // MARK: Accessibility (ADR-0013)
    //
    // AXComboBox whose value is the field's text; press and showMenu open the list, which
    // is an AXList of rows in its own window while open.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .comboBox }
    @MainActor open override func accessibilityPerformShowMenu() -> Bool {
        guard isEnabled else { return false }
        if !_isPopUpOpen { _comboCell._popUp(withFrame: _cellFrame, in: self) }
        return true
    }
    @MainActor open override func accessibilityPerformPress() -> Bool { accessibilityPerformShowMenu() }
    override func _accessibilityExpandedState() -> Bool? { _isPopUpOpen }
    open override func isAccessibilityExpanded() -> Bool { _isPopUpOpen }
    open override func setAccessibilityExpanded(_ accessibilityExpanded: Bool) {
        if accessibilityExpanded { _ = accessibilityPerformShowMenu() } else { _comboCell._dismissPopUp() }
    }
}
