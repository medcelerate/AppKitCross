// NSMenu (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu
open class NSMenu: NSObject, NSCopying, NSCoding, NSUserInterfaceItemIdentification, NSAppearanceCustomization, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    // MARK: Storage
    private var _title: String
    private var _items: [NSMenuItem] = []
    internal weak var _supermenu: NSMenu?
    private weak var _delegate: (any NSMenuDelegate)?
    private var _autoenablesItems = true
    private var _minimumWidth: CGFloat = 0
    private var _font: NSFont? = nil
    private var _showsStateColumn = true
    private var _allowsContextMenuPlugIns = true
    private var _userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection = .leftToRight
    private var _identifier: NSUserInterfaceItemIdentifier? = nil
    internal let _menuID: Int
    nonisolated(unsafe) private static var _nextMenuID = 1

    open override var description: String { "<NSMenu '\(_title)' \(_items.count) items>" }

    /// Root of this menu's tree.
    internal var _root: NSMenu {
        var m = self
        while let s = m._supermenu { m = s }
        return m
    }

    /// Tells the application the main menu changed, if this menu is part of it.
    internal func _menuTreeChanged() {
        MainActor.assumeIsolated {
            if let app = NSApplication._shared, app.mainMenu === _root { app._mainMenuDidChange() }
        }
    }

    @MainActor internal func _platformMenu() -> PlatformMenu {
        PlatformMenu(id: _menuID, title: _title, items: _items.map { $0._platformItem() })
    }

    /// Finds the menu with `id` in this tree.
    internal func _menu(withID id: Int) -> NSMenu? {
        if _menuID == id { return self }
        for i in _items { if let m = i.submenu?._menu(withID: id) { return m } }
        return nil
    }

    internal func _item(withCommandID id: Int) -> NSMenuItem? {
        for i in _items {
            if i._commandID == id { return i }
            if let found = i.submenu?._item(withCommandID: id) { return found }
        }
        return nil
    }


    open var identifier: NSUserInterfaceItemIdentifier? {
        get { _identifier }
        set { _identifier = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/init(coder:)
    public required convenience init(coder: NSCoder) { self.init(title: "") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/init(title:)
    public init(title: String) {
        _title = title
        _menuID = NSMenu._nextMenuID
        NSMenu._nextMenuID += 1
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/additem(_:)
    open func addItem(_ newItem: NSMenuItem) { insertItem(newItem, at: _items.count) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/additem(withtitle:action:keyequivalent:)
    open func addItem(withTitle string: String, action selector: Selector?, keyEquivalent charCode: String) -> NSMenuItem {
        insertItem(withTitle: string, action: selector, keyEquivalent: charCode, at: _items.count)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/allowscontextmenuplugins
    open var allowsContextMenuPlugIns: Bool {
        get { _allowsContextMenuPlugIns }
        set { _allowsContextMenuPlugIns = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/autoenablesitems
    open var autoenablesItems: Bool {
        get { _autoenablesItems }
        set { _autoenablesItems = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/automaticallyinsertswritingtoolsitems
    @available(macOS 15.2, *)
    open var automaticallyInsertsWritingToolsItems: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/canceltracking()
    open func cancelTracking() { MainActor.assumeIsolated { if _NSMenuTracker.current?.rootMenu === self || _NSMenuTracker.current?.levels.contains(where: { $0.menu === self }) == true { _NSMenuTracker.current?.cancel() } } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/canceltrackingwithoutanimation()
    open func cancelTrackingWithoutAnimation() { cancelTracking() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/delegate
    open var delegate: (any NSMenuDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/didadditemnotification
    static public var didAddItemNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSMenuDidAddItemNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/didbegintrackingnotification
    static public var didBeginTrackingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSMenuDidBeginTrackingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/didchangeitemnotification
    static public var didChangeItemNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSMenuDidChangeItemNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/didendtrackingnotification
    static public var didEndTrackingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSMenuDidEndTrackingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/didremoveitemnotification
    static public var didRemoveItemNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSMenuDidRemoveItemNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/didsendactionnotification
    static public var didSendActionNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSMenuDidSendActionNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/font
    open var font: NSFont! {
        get { _font }
        set { _font = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/helprequested(with:)
    open func helpRequested(with eventPtr: NSEvent) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/highlighteditem
    open var highlightedItem: NSMenuItem? { MainActor.assumeIsolated { _NSMenuTracker.current?.levels.first { $0.menu === self }?.window.menuView.highlightedItem } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/index(of:)
    open func index(of item: NSMenuItem) -> Int { _items.firstIndex { $0 === item } ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/indexofitem(withrepresentedobject:)
    open func indexOfItem(withRepresentedObject object: Any?) -> Int {
        _items.firstIndex { ($0.representedObject as AnyObject?) === (object as AnyObject?) } ?? -1
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/indexofitem(withsubmenu:)
    open func indexOfItem(withSubmenu submenu: NSMenu?) -> Int { _items.firstIndex { $0.submenu === submenu && submenu != nil } ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/indexofitem(withtag:)
    open func indexOfItem(withTag tag: Int) -> Int { MainActor.assumeIsolated { _items.firstIndex { $0.tag == tag } ?? -1 } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/indexofitem(withtarget:andaction:)
    open func indexOfItem(withTarget target: Any?, andAction actionSelector: Selector?) -> Int {
        MainActor.assumeIsolated { _items.firstIndex { (target == nil || $0.target === (target as AnyObject?)) && (actionSelector == nil || $0.action == actionSelector) } ?? -1 }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/indexofitem(withtitle:)
    open func indexOfItem(withTitle title: String) -> Int { _items.firstIndex { $0.title == title } ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/insertitem(_:at:)
    open func insertItem(_ newItem: NSMenuItem, at index: Int) {
        precondition(newItem.menu == nil, "NSMenu: item is already in a menu")
        _items.insert(newItem, at: min(max(0, index), _items.count))
        newItem._menu = self
        newItem.submenu?._supermenu = self
        _menuTreeChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/insertitem(withtitle:action:keyequivalent:at:)
    open func insertItem(withTitle string: String, action selector: Selector?, keyEquivalent charCode: String, at index: Int) -> NSMenuItem {
        let item = NSMenuItem(title: string, action: selector, keyEquivalent: charCode)
        insertItem(item, at: index)
        return item
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/istornoff
    open var isTornOff: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/item(at:)
    open func item(at index: Int) -> NSMenuItem? { _items.indices.contains(index) ? _items[index] : nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/item(withtag:)
    open func item(withTag tag: Int) -> NSMenuItem? { MainActor.assumeIsolated { _items.first { $0.tag == tag } } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/item(withtitle:)
    open func item(withTitle title: String) -> NSMenuItem? { _items.first { $0.title == title } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/itemchanged(_:)
    open func itemChanged(_ item: NSMenuItem) { _menuTreeChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/items
    open var items: [NSMenuItem] {
        get { _items }
        set {
            for i in _items { i._menu = nil }
            _items = newValue
            for i in _items { i._menu = self; i.submenu?._supermenu = self }
            _menuTreeChanged()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/menubarheight
    open var menuBarHeight: CGFloat { 20 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/menubarvisible()
    public class func menuBarVisible() -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/menuchangedmessagesenabled
    open var menuChangedMessagesEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    // SKIPPED (ObjectiveC.NSZone): class func menuZone() -> NSZone!
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/minimumwidth
    open var minimumWidth: CGFloat {
        get { _minimumWidth }
        set { _minimumWidth = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/numberofitems
    open var numberOfItems: Int { _items.count }
    /// Creates a palette menu displaying user-selectable color tags
    /// using the provided template image, tinted using the specified
    /// array of colors.
    /// 
    /// Optionally allows observing changes to the selection state in
    /// the palette menu. The closure is invoked after the selection
    /// has been updated. Currently selected items can be retrieved
    /// from the `selectedItems` property.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/palette(colors:titles:template:onselectionchange:)
    @available(macOS 14.0, *)
    public static func palette(colors: [NSColor], titles: [String] = [], template: NSImage? = nil, onSelectionChange: ((NSMenu) -> Void)? = nil) -> NSMenu { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/performactionforitem(at:)
    open func performActionForItem(at index: Int) {
        guard let item = item(at: index), item.isEnabled, !item.isSeparatorItem else { return }
        MainActor.assumeIsolated {
            NotificationCenter.default.post(name: NSMenu.willSendActionNotification, object: self, userInfo: ["MenuItem": item])
            if let action = item.action {
                let handled = NSApplication.shared.sendAction(action, to: item.target, from: item)
                if NSView._traceInvalidation {
                    NSView._trace("menu action '\(item.title)' \(action) target \(item.target.map { "\(type(of: $0))" } ?? "nil (first responder \(NSApplication.shared.keyWindow?.firstResponder.map { "\(type(of: $0))" } ?? "none"))") handled \(handled)")
                }
            }
            NotificationCenter.default.post(name: NSMenu.didSendActionNotification, object: self, userInfo: ["MenuItem": item])
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/performkeyequivalent(with:)
    open func performKeyEquivalent(with event: NSEvent) -> Bool {
        MainActor.assumeIsolated {
            guard event.type == .keyDown else { return false }
            for (i, item) in _items.enumerated() where !item.isHidden || item.allowsKeyEquivalentWhenHidden {
                if let sub = item.submenu {
                    if sub.performKeyEquivalent(with: event) { return true }
                } else if item._matches(event) {
                    update()
                    if NSView._traceInvalidation {
                        NSView._trace("key equivalent '\(item.title)' action \(item.action.map(NSStringFromSelector) ?? "none") enabled \(item.isEnabled) target \(item.target.map { String(describing: type(of: $0)) } ?? "nil") first responder \(NSApplication.shared.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
                    }
                    guard item.isEnabled else { return true }
                    performActionForItem(at: i)
                    return true
                }
            }
            return false
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/popup(positioning:at:in:)
    /// Opens the menu with `item` (or its first item) at `location` and returns once it
    /// closes: true when an item was chosen. Events are pumped by a nested run loop.
    open func popUp(positioning item: NSMenuItem?, at location: NSPoint, in view: NSView?) -> Bool {
        MainActor.assumeIsolated { () -> Bool in
            var point = location
            if let view { point = view.convert(location, to: nil); if let w = view.window { point = w.convertPoint(toScreen: point) } }
            let itemIndex = item.map { self.index(of: $0) }.flatMap { $0 >= 0 ? $0 : nil }
            let tracker = _NSMenuTracker.begin(menu: self, anchor: NSRect(origin: point, size: .zero), placement: .atPoint(itemIndex: itemIndex), openedWithMouseDown: false)
            Platform.backend.runNested { tracker.finished }
            return tracker.chosenItem != nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/popupcontextmenu(_:with:for:)
    public class func popUpContextMenu(_ menu: NSMenu, with event: NSEvent, for view: NSView) { popUpContextMenu(menu, with: event, for: view, with: nil) }
    /// Opens the menu at the event's location. Unlike AppKit this returns at once; the
    /// menu tracks asynchronously and sends the chosen item's action when it closes.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/popupcontextmenu(_:with:for:with:)
    public class func popUpContextMenu(_ menu: NSMenu, with event: NSEvent, for view: NSView, with font: NSFont?) {
        MainActor.assumeIsolated {
            let window = event.window ?? view.window
            let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown
            view.willOpenMenu(menu, with: event)
            _NSMenuTracker.begin(menu: menu, anchor: NSRect(origin: point, size: .zero), placement: .atPoint(itemIndex: nil), font: font, openedWithMouseDown: isDown) { [weak view] _ in
                view?.didCloseMenu(menu, with: nil)
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/presentationstyle
    @available(macOS 14.0, *)
    open var presentationStyle: NSMenu.PresentationStyle {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/propertiestoupdate
    open var propertiesToUpdate: NSMenu.Properties { [.propertyItemTitle, .propertyItemEnabled] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/removeallitems()
    open func removeAllItems() {
        for i in _items { i._menu = nil; i.submenu?._supermenu = nil }
        _items.removeAll()
        _menuTreeChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/removeitem(_:)
    open func removeItem(_ item: NSMenuItem) { if let i = _items.firstIndex(where: { $0 === item }) { removeItem(at: i) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/removeitem(at:)
    open func removeItem(at index: Int) {
        let item = _items.remove(at: index)
        item._menu = nil
        item.submenu?._supermenu = nil
        _menuTreeChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/selecteditems
    @available(macOS 14.0, *)
    open var selectedItems: [NSMenuItem] {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/selectionmode
    @available(macOS 14.0, *)
    open var selectionMode: NSMenu.SelectionMode {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/setmenubarvisible(_:)
    public class func setMenuBarVisible(_ visible: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/setsubmenu(_:for:)
    open func setSubmenu(_ menu: NSMenu?, for item: NSMenuItem) { item.submenu = menu }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/showsstatecolumn
    open var showsStateColumn: Bool {
        get { _showsStateColumn }
        set { _showsStateColumn = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/size
    open var size: NSSize { MainActor.assumeIsolated { _NSMenuLayout(menu: self, font: _font ?? NSFont.menuFont(ofSize: NSFont.systemFontSize)).size } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/submenuaction(_:)
    open func submenuAction(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/supermenu
    open var supermenu: NSMenu? {
        get { _supermenu }
        set { _supermenu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/title
    open var title: String {
        get { _title }
        set { _title = newValue; _menuTreeChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/update()
    open func update() {
        MainActor.assumeIsolated {
            if let d = _delegate { d.menuNeedsUpdate(self) }
            guard _autoenablesItems else { return }
            for item in _items where !item.isSeparatorItem && !item.hasSubmenu {
                guard let action = item.action else { continue }
                // AppKit: find the object that would receive the action; the item is enabled
                // when there is one, unless that object implements validateMenuItem and says no.
                let target: AnyObject? = item.target ?? NSApplication.shared._target(forAction: action)
                if let t = target, ActionRegistry.canPerform(action, on: t) {
                    item.isEnabled = (t as? NSMenuItemValidation)?.validateMenuItem(item) ?? true
                } else {
                    item.isEnabled = false
                }
                if _PasteboardTrace.enabled, NSStringFromSelector(action).hasPrefix("paste") {
                    _PasteboardTrace.log("NSMenu.update \"\(item.title)\" (\(NSStringFromSelector(action))): target \(target.map { "\(type(of: $0)) \(ObjectIdentifier($0))" } ?? "none"), validates \(target is NSMenuItemValidation) -> enabled \(item.isEnabled)")
                }
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/userinterfacelayoutdirection
    @available(macOS 10.11, *)
    open var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { _userInterfaceLayoutDirection }
        set { _userInterfaceLayoutDirection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenu/willsendactionnotification
    static public var willSendActionNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSMenuWillSendActionNotification") }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let m = NSMenu(title: _title)
        for i in _items { m.addItem(i.copy() as! NSMenuItem) }
        m._autoenablesItems = _autoenablesItems
        return m
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // MARK: Accessibility (ADR-0013, NSMenuAccessibility.swift)
    // AXMenuBar for the main menu, AXMenu otherwise; the items are the children. An open
    // menu has the frame of its window.
    internal var _accessibilityID = 0
    open func accessibilityRole() -> NSAccessibility.Role? { MainActor.assumeIsolated { _a11yRole } }
    open func accessibilityTitle() -> String? { _title }
    open func accessibilityLabel() -> String? { _title.isEmpty ? nil : _title }
    open func isAccessibilityElement() -> Bool { true }
    open func isAccessibilityEnabled() -> Bool { true }
    open func accessibilityChildren() -> [Any]? { MainActor.assumeIsolated { _a11yChildren } }
    open func accessibilityPerformCancel() -> Bool { MainActor.assumeIsolated { _a11yCancel() } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityFrame() -> NSRect { MainActor.assumeIsolated { _a11yFrame } }
    // Requirement of NSAccessibilityElementProtocol
    /// The item whose submenu this is; the application for the main menu; nil otherwise.
    open func accessibilityParent() -> Any? { MainActor.assumeIsolated { _a11yParent } }
    // Requirement of NSAccessibilityElementProtocol
    open func isAccessibilityFocused() -> Bool { false }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { _identifier?.rawValue ?? "" }
}
