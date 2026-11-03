// NSPopUpButton (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton
@MainActor open class NSPopUpButton: NSButton {
    internal var _popUpCell: NSPopUpButtonCell { _cell as! NSPopUpButtonCell }

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSPopUpButtonCell(textCell: "", pullsDown: false) }

    @MainActor public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/init(frame:pullsdown:)
    @MainActor public init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame)
        _popUpCell.pullsDown = flag
    }
    /// Creates a standard pull-down button with a title, optional image, and menu.
    ///
    /// Pull-down buttons created using this method have the `usesItemFromMenu` property set to `false`.
    ///
    /// - Parameters:
    ///   - image: The icon that is displayed on the button.
    ///   - pullDownMenu: The pull-down menu to present when interacting with the button.
    /// - Returns: An initialized pull-down button object.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/init(image:pulldownmenu:)
    @available(macOS 10.10, *)
    @MainActor public convenience init(image: NSImage, pullDownMenu: NSMenu) {
        self.init(title: "", image: image, pullDownMenu: pullDownMenu)
    }
    /// Creates a standard pop-up button with a menu, target, and action.
    ///
    /// If `menu` is non-empty, the pop-up button uses the first item for its initial selection.
    ///
    /// - Parameters:
    ///   - popUpMenu: A menu presented by the pop-up button, containing items that the user can choose between.
    ///   - target: The target object that receives action messages from the control.
    ///   - action: The action message sent by the control.
    /// - Returns: An initialized pop-up button object.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/init(popupmenu:target:action:)
    @available(macOS 10.10, *)
    @MainActor public convenience init(popUpMenu: NSMenu, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero, pullsDown: false)
        menu = popUpMenu
        self.target = target
        self.action = action
        sizeToFit()
    }
    /// Creates a standard pull-down button with a title, optional image, and menu.
    ///
    /// Pull-down buttons created using this method have the `usesItemFromMenu` property set to `false`.
    ///
    /// - Parameters:
    ///   - title: The localized title string that is displayed on the button.
    ///   - image: The icon that is displayed on the button.
    ///   - pullDownMenu: The pull-down menu to present when interacting with the button.
    /// - Returns: An initialized pull-down button object.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/init(title:image:pulldownmenu:)
    @available(macOS 10.10, *)
    @MainActor public convenience init(title: String, image: NSImage? = nil, pullDownMenu: NSMenu) {
        self.init(frame: .zero, pullsDown: true)
        _popUpCell.usesItemFromMenu = false
        menu = pullDownMenu
        if let image { self.image = image }
        setTitle(title)
        sizeToFit()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/additem(withtitle:)
    @MainActor open func addItem(withTitle title: String) { _popUpCell.addItem(withTitle: title); invalidateIntrinsicContentSize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/additems(withtitles:)
    @MainActor open func addItems(withTitles itemTitles: [String]) { _popUpCell.addItems(withTitles: itemTitles); invalidateIntrinsicContentSize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/altersstateofselecteditem
    @MainActor open var altersStateOfSelectedItem: Bool {
        get { _popUpCell.altersStateOfSelectedItem }
        set { _popUpCell.altersStateOfSelectedItem = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/autoenablesitems
    @MainActor open var autoenablesItems: Bool {
        get { _popUpCell.autoenablesItems }
        set { _popUpCell.autoenablesItems = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/index(of:)
    @MainActor open func index(of item: NSMenuItem) -> Int { _popUpCell.index(of: item) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/indexofitem(withrepresentedobject:)
    @MainActor open func indexOfItem(withRepresentedObject obj: Any?) -> Int { _popUpCell.indexOfItem(withRepresentedObject: obj) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/indexofitem(withtag:)
    @MainActor open func indexOfItem(withTag tag: Int) -> Int { _popUpCell.indexOfItem(withTag: tag) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/indexofitem(withtarget:andaction:)
    @MainActor open func indexOfItem(withTarget target: Any?, andAction actionSelector: Selector?) -> Int { _popUpCell.indexOfItem(withTarget: target, andAction: actionSelector) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/indexofitem(withtitle:)
    @MainActor open func indexOfItem(withTitle title: String) -> Int { _popUpCell.indexOfItem(withTitle: title) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/indexofselecteditem
    @MainActor open var indexOfSelectedItem: Int { _popUpCell.indexOfSelectedItem }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/insertitem(withtitle:at:)
    @MainActor open func insertItem(withTitle title: String, at index: Int) { _popUpCell.insertItem(withTitle: title, at: index); invalidateIntrinsicContentSize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/item(at:)
    @MainActor open func item(at index: Int) -> NSMenuItem? { _popUpCell.item(at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/item(withtitle:)
    @MainActor open func item(withTitle title: String) -> NSMenuItem? { _popUpCell.item(withTitle: title) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/itemarray
    @MainActor open var itemArray: [NSMenuItem] { _popUpCell.itemArray }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/itemtitle(at:)
    @MainActor open func itemTitle(at index: Int) -> String { _popUpCell.itemTitle(at: index) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/itemtitles
    @MainActor open var itemTitles: [String] { _popUpCell.itemTitles }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/lastitem
    @MainActor open var lastItem: NSMenuItem? { _popUpCell.lastItem }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/menu
    @MainActor open override var menu: NSMenu? {
        get { _popUpCell.menu }
        set { _popUpCell.menu = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/numberofitems
    @MainActor open var numberOfItems: Int { _popUpCell.numberOfItems }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/preferrededge
    @MainActor open var preferredEdge: NSRectEdge {
        get { _popUpCell.preferredEdge }
        set { _popUpCell.preferredEdge = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/pullsdown
    @MainActor open var pullsDown: Bool {
        get { _popUpCell.pullsDown }
        set { _popUpCell.pullsDown = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/removeallitems()
    @MainActor open func removeAllItems() { _popUpCell.removeAllItems(); invalidateIntrinsicContentSize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/removeitem(at:)
    @MainActor open func removeItem(at index: Int) { _popUpCell.removeItem(at: index); invalidateIntrinsicContentSize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/removeitem(withtitle:)
    @MainActor open func removeItem(withTitle title: String) { _popUpCell.removeItem(withTitle: title); invalidateIntrinsicContentSize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/select(_:)
    @MainActor open func select(_ item: NSMenuItem?) { _popUpCell.select(item); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/selectitem(at:)
    @MainActor open func selectItem(at index: Int) { _popUpCell.selectItem(at: index); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/selectitem(withtag:)
    @MainActor open func selectItem(withTag tag: Int) -> Bool { defer { needsDisplay = true }; return _popUpCell.selectItem(withTag: tag) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/selectitem(withtitle:)
    @MainActor open func selectItem(withTitle title: String) { _popUpCell.selectItem(withTitle: title); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/selecteditem
    @MainActor open var selectedItem: NSMenuItem? { _popUpCell.selectedItem }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/selectedtag()
    @MainActor open override func selectedTag() -> Int { selectedItem?.tag ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/settitle(_:)
    @MainActor open func setTitle(_ string: String) { _popUpCell.setTitle(string); invalidateIntrinsicContentSize(); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/synchronizetitleandselecteditem()
    @MainActor open func synchronizeTitleAndSelectedItem() { _popUpCell.synchronizeTitleAndSelectedItem(); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/titleofselecteditem
    @MainActor open var titleOfSelectedItem: String? { _popUpCell.titleOfSelectedItem }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/usesitemfrommenu
    @available(macOS 15.0, *)
    @MainActor open var usesItemFromMenu: Bool {
        get { _popUpCell.usesItemFromMenu }
        set { _popUpCell.usesItemFromMenu = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopupbutton/willpopupnotification
    static public var willPopUpNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSPopUpButtonWillPopUpNotification") }
    // Required by the superclass (NSCoding).
    @MainActor public required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Behaviour

    /// Opens the menu. Unlike AppKit this returns at once; the menu tracks asynchronously
    /// and the action is sent when an item is chosen.
    @MainActor open override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        _popUpCell._attachPopUp(withFrame: _cellFrame, in: self, openedWithMouseDown: false)
    }
    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        _popUpCell._attachPopUp(withFrame: _cellFrame, in: self, openedWithMouseDown: true)
    }
    @MainActor open override func mouseDragged(with event: NSEvent) { }
    @MainActor open override func mouseUp(with event: NSEvent) { }
    @MainActor open override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 36, 76, 125, 126: performClick(self)      // space, return, enter, down, up
        default: super.keyDown(with: event)
        }
    }
}
