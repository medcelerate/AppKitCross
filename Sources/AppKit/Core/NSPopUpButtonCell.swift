// NSPopUpButtonCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell
@MainActor open class NSPopUpButtonCell: NSMenuItemCell, NSMenuItemValidation {
    // MARK: Storage
    private var _pullsDown = false
    private var _selectedItem: NSMenuItem?
    private var _arrowPosition: NSPopUpButton.ArrowPosition = .arrowAtCenter
    private var _preferredEdge: NSRectEdge = .maxY
    private var _usesItemFromMenu = true
    private var _altersStateOfSelectedItem = true
    private var _autoenablesItems = true
    private var _pullDownTitle = ""
    private weak var _tracker: _NSMenuTracker?

    /// The horizontal inset of the title inside the bezel.
    internal static let titleInset: CGFloat = 10
    /// Width reserved for the arrow indicator at the trailing edge.
    internal static let arrowAreaWidth: CGFloat = 26

    private var _items: [NSMenuItem] { _menu?.items ?? [] }
    private func _ensureMenu() -> NSMenu {
        if let m = _menu { return m }
        let m = NSMenu(title: "")
        _menu = m
        return m
    }
    /// The title shown in the control.
    private var _displayTitle: String {
        if _pullsDown {
            return _usesItemFromMenu ? (_items.first?.title ?? _pullDownTitle) : _pullDownTitle
        }
        return _selectedItem?.title ?? ""
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/init(coder:)
    public required init(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/init(textcell:pullsdown:)
    @MainActor public init(textCell stringValue: String, pullsDown pullDown: Bool) {
        super.init(textCell: stringValue)
        _pullsDown = pullDown
        _pullDownTitle = stringValue
        _isBordered = true
        setButtonType(.momentaryPushIn)
    }
    @MainActor public override convenience init(textCell string: String) { self.init(textCell: string, pullsDown: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/additem(withtitle:)
    @MainActor open func addItem(withTitle title: String) { insertItem(withTitle: title, at: numberOfItems) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/additems(withtitles:)
    @MainActor open func addItems(withTitles itemTitles: [String]) { for t in itemTitles { addItem(withTitle: t) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/altersstateofselecteditem
    @MainActor open var altersStateOfSelectedItem: Bool {
        get { _altersStateOfSelectedItem }
        set { _altersStateOfSelectedItem = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/arrowposition
    @MainActor open var arrowPosition: NSPopUpButton.ArrowPosition {
        get { _arrowPosition }
        set { _arrowPosition = newValue; _changed() }
    }
    /// Opens the menu for `cellFrame`: a pop-up puts the selected item over the control, a
    /// pull-down hangs it off `preferredEdge`. The menu tracks asynchronously; choosing an
    /// item selects it and sends the control's action.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/attachpopup(withframe:in:)
    @MainActor open func attachPopUp(withFrame cellFrame: NSRect, in controlView: NSView) {
        _attachPopUp(withFrame: cellFrame, in: controlView, openedWithMouseDown: false)
    }
    @MainActor internal func _attachPopUp(withFrame cellFrame: NSRect, in controlView: NSView, openedWithMouseDown: Bool) {
        guard _isEnabled, let window = controlView.window else { return }
        let menu = _ensureMenu()
        menu.autoenablesItems = _autoenablesItems
        NotificationCenter.default.post(name: NSPopUpButtonCell.willPopUpNotification, object: self)
        if let control = controlView as? NSPopUpButton { NotificationCenter.default.post(name: NSPopUpButton.willPopUpNotification, object: control) }
        let anchor = window.convertToScreen(controlView.convert(cellFrame, to: nil))
        let placement: _NSMenuPlacement
        var skipFirst = false
        if _pullsDown {
            placement = .besideAnchor(edge: _preferredEdge)
            skipFirst = _usesItemFromMenu
        } else {
            placement = .overAnchor(itemIndex: max(0, indexOfSelectedItem), titleInset: NSPopUpButtonCell.titleInset)
        }
        _isHighlighted = true
        _changed()
        let tracker = _NSMenuTracker.begin(menu: menu, anchor: anchor, placement: placement, font: _font, openedWithMouseDown: openedWithMouseDown,
                                           skipsFirstItem: skipFirst, minimumWidth: _pullsDown ? 0 : cellFrame.width) { [weak self, weak controlView] item in
            guard let self else { return }
            self._isHighlighted = false
            self._changed()
            guard let item else { return }
            if !self._pullsDown { self.select(item) }
            (controlView as? NSControl)?._fireAction()
        }
        _tracker = tracker
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/autoenablesitems
    @MainActor open var autoenablesItems: Bool {
        get { _autoenablesItems }
        set { _autoenablesItems = newValue; _menu?.autoenablesItems = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/dismisspopup()
    @MainActor open func dismissPopUp() { _tracker?.cancel() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/index(of:)
    @MainActor open func index(of item: NSMenuItem) -> Int { _menu?.index(of: item) ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/indexofitem(withrepresentedobject:)
    @MainActor open func indexOfItem(withRepresentedObject obj: Any?) -> Int { _menu?.indexOfItem(withRepresentedObject: obj) ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/indexofitem(withtag:)
    @MainActor open func indexOfItem(withTag tag: Int) -> Int { _menu?.indexOfItem(withTag: tag) ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/indexofitem(withtarget:andaction:)
    @MainActor open func indexOfItem(withTarget target: Any?, andAction actionSelector: Selector?) -> Int { _menu?.indexOfItem(withTarget: target, andAction: actionSelector) ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/indexofitem(withtitle:)
    @MainActor open func indexOfItem(withTitle title: String) -> Int { _menu?.indexOfItem(withTitle: title) ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/indexofselecteditem
    @MainActor open var indexOfSelectedItem: Int { _selectedItem.map { index(of: $0) } ?? -1 }
    /// Inserts an item; an existing item with the same title is removed first, as in AppKit.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/insertitem(withtitle:at:)
    @MainActor open func insertItem(withTitle title: String, at index: Int) {
        let menu = _ensureMenu()
        var at = index
        if let existing = menu.item(withTitle: title) {
            let i = menu.index(of: existing)
            if existing === _selectedItem { _selectedItem = nil }
            menu.removeItem(at: i)
            if i < at { at -= 1 }
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.insertItem(item, at: at)
        if !_pullsDown, _selectedItem == nil { select(item) } else { synchronizeTitleAndSelectedItem() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/item(at:)
    @MainActor open func item(at index: Int) -> NSMenuItem? { _menu?.item(at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/item(withtitle:)
    @MainActor open func item(withTitle title: String) -> NSMenuItem? { _menu?.item(withTitle: title) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/itemarray
    @MainActor open var itemArray: [NSMenuItem] { _items }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/itemtitle(at:)
    @MainActor open func itemTitle(at index: Int) -> String { item(at: index)?.title ?? "" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/itemtitles
    @MainActor open var itemTitles: [String] { _items.map(\.title) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/lastitem
    @MainActor open var lastItem: NSMenuItem? { _items.last }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/menu
    @MainActor open override var menu: NSMenu? {
        get { _menu }
        set {
            _menu = newValue
            newValue?.autoenablesItems = _autoenablesItems
            _selectedItem = nil
            if !_pullsDown, let first = newValue?.items.first { select(first) } else { synchronizeTitleAndSelectedItem() }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/numberofitems
    @MainActor open var numberOfItems: Int { _items.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/performclick(withframe:in:)
    @MainActor open func performClick(withFrame frame: NSRect, in controlView: NSView) { attachPopUp(withFrame: frame, in: controlView) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/preferrededge
    @MainActor open var preferredEdge: NSRectEdge {
        get { _preferredEdge }
        set { _preferredEdge = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/pullsdown
    @MainActor open var pullsDown: Bool {
        get { _pullsDown }
        set { _pullsDown = newValue; synchronizeTitleAndSelectedItem() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/removeallitems()
    @MainActor open func removeAllItems() {
        _menu?.removeAllItems()
        _selectedItem = nil
        synchronizeTitleAndSelectedItem()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/removeitem(at:)
    @MainActor open func removeItem(at index: Int) {
        guard let menu = _menu, let item = menu.item(at: index) else { return }
        menu.removeItem(at: index)
        if item === _selectedItem {
            _selectedItem = nil
            if !_pullsDown, let next = menu.item(at: min(index, menu.numberOfItems - 1)) { select(next); return }
        }
        synchronizeTitleAndSelectedItem()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/removeitem(withtitle:)
    @MainActor open func removeItem(withTitle title: String) { let i = indexOfItem(withTitle: title); if i >= 0 { removeItem(at: i) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/select(_:)
    @MainActor open func select(_ item: NSMenuItem?) {
        if _altersStateOfSelectedItem && !_pullsDown {
            _selectedItem?.state = .off
            item?.state = .on
        }
        _selectedItem = item
        synchronizeTitleAndSelectedItem()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/selectitem(at:)
    @MainActor open func selectItem(at index: Int) { select(index >= 0 ? item(at: index) : nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/selectitem(withtag:)
    @MainActor open func selectItem(withTag tag: Int) -> Bool {
        let i = indexOfItem(withTag: tag)
        guard i >= 0 else { return false }
        selectItem(at: i)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/selectitem(withtitle:)
    @MainActor open func selectItem(withTitle title: String) { selectItem(at: indexOfItem(withTitle: title)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/selecteditem
    @MainActor open var selectedItem: NSMenuItem? { _selectedItem }
    /// Pop-up: selects the item with that title, adding one when it is missing. Pull-down:
    /// sets the displayed title.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/settitle(_:)
    @MainActor open func setTitle(_ string: String?) {
        let title = string ?? ""
        if _pullsDown {
            _pullDownTitle = title
            if _usesItemFromMenu, let first = _items.first { first.title = title }
        } else {
            if item(withTitle: title) == nil { addItem(withTitle: title) }
            selectItem(withTitle: title)
        }
        synchronizeTitleAndSelectedItem()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/synchronizetitleandselecteditem()
    @MainActor open func synchronizeTitleAndSelectedItem() {
        if !_pullsDown, _selectedItem == nil, let first = _items.first {
            _selectedItem = first
            if _altersStateOfSelectedItem { first.state = .on }
        }
        super.stringValue = _displayTitle
        (_controlView as? NSControl)?.invalidateIntrinsicContentSize()
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/titleofselecteditem
    @MainActor open var titleOfSelectedItem: String? { _selectedItem?.title }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/usesitemfrommenu
    @MainActor open var usesItemFromMenu: Bool {
        get { _usesItemFromMenu }
        set { _usesItemFromMenu = newValue; synchronizeTitleAndSelectedItem() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbuttoncell/willpopupnotification
    static public var willPopUpNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSPopUpButtonCellWillPopUpNotification") }
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }

    // MARK: Drawing

    @MainActor open override var cellSize: NSSize {
        var titles = _items.map(\.title)
        if _pullsDown { titles = _usesItemFromMenu ? Array(titles.prefix(1)) : [_pullDownTitle] }
        if titles.isEmpty { titles = [_displayTitle] }
        let widest = titles.map { $0.size(withAttributes: _textAttributes).width }.max() ?? 0
        let height = (_effectiveFont.ascender - _effectiveFont.descender) + 8
        return NSSize(width: (widest + NSPopUpButtonCell.titleInset + NSPopUpButtonCell.arrowAreaWidth).rounded(.up), height: height.rounded(.up))
    }
    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        drawBezel(withFrame: cellFrame, in: controlView)
        drawInterior(withFrame: cellFrame, in: controlView)
    }
    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var attrs = _textAttributes
        if _isHighlighted && _isBordered { attrs[.foregroundColor] = NSColor.white }
        let titleRect = NSRect(x: cellFrame.minX + NSPopUpButtonCell.titleInset, y: cellFrame.minY,
                               width: max(0, cellFrame.width - NSPopUpButtonCell.titleInset - NSPopUpButtonCell.arrowAreaWidth), height: cellFrame.height)
        _drawText(_displayTitle, attributes: attrs, in: titleRect, alignment: .left, flipped: controlView.isFlipped)
        guard _arrowPosition != .noArrow else { return }
        let flipped = controlView.isFlipped
        let boxHeight = min(cellFrame.height - 6, 18)
        let box = NSRect(x: cellFrame.maxX - 3 - 18, y: cellFrame.midY - boxHeight / 2, width: 18, height: boxHeight)
        let chevronColor: NSColor
        if _pullsDown {
            chevronColor = _isHighlighted && _isBordered ? .white : (_isEnabled ? .labelColor : .disabledControlTextColor)
        } else {
            (_isEnabled ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.4)).setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
            chevronColor = .white
        }
        chevronColor.setStroke()
        func chevron(centerY: CGFloat, up: Bool) {
            let p = NSBezierPath()
            let dy: CGFloat = (up != flipped) ? -2.5 : 2.5
            p.move(to: NSPoint(x: box.midX - 3.5, y: centerY + dy))
            p.line(to: NSPoint(x: box.midX, y: centerY - dy))
            p.line(to: NSPoint(x: box.midX + 3.5, y: centerY + dy))
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.stroke()
        }
        if _pullsDown {
            chevron(centerY: box.midY, up: false)
        } else {
            chevron(centerY: box.midY + (flipped ? -3.5 : 3.5), up: true)
            chevron(centerY: box.midY + (flipped ? 3.5 : -3.5), up: false)
        }
    }
}
