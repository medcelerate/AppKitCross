// Menus in the accessibility tree (ADR-0013 follow-ups).
//
// `NSMenu` and `NSMenuItem` are virtual elements: the main menu is an AXMenuBar whose
// AXMenuBarItems hold AXMenu submenus of AXMenuItems; any other menu is an AXMenu. Items
// report their title, enabled state, check mark (`checkedState`) and key equivalent, and
// pressing one performs it, or opens its submenu. A menu that is open on screen (the
// `_NSMenuTracker` shows it in an `_NSMenuWindow`) lists its items as drawn, with frames
// and the highlighted item selected and focused; a closed menu lists its whole structure
// without frames. The main menu reaches the platform through
// `PlatformAccessibilityApplication` on backends whose menu bar the system does not
// expose (AT-SPI); on Windows the native HMENU bar is the system's (see ADR-0013).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension NSMenu {
    @MainActor internal var _a11yIsMainMenu: Bool { NSApplication._shared?.mainMenu === self }
    @MainActor internal var _a11yRole: NSAccessibility.Role { _a11yIsMainMenu ? .menuBar : .menu }
    /// The items as elements: the open level's drawn rows, else every visible item.
    @MainActor internal var _a11yChildren: [Any] {
        if let t = _NSMenuTracker.current, let i = t.levelIndex(of: self) {
            return t.levels[i].window.menuView.accessibilityChildren() ?? []
        }
        return items.filter { !$0.isHidden && !$0.isSeparatorItem && !$0.isAlternate }.map { ($0.view as Any?) ?? $0 }
    }
    @MainActor internal var _a11yFrame: NSRect {
        if let t = _NSMenuTracker.current, let i = t.levelIndex(of: self) { return t.levels[i].window.frame }
        return .zero
    }
    @MainActor internal var _a11yParent: Any? {
        if let s = supermenu { return s.items.first { $0.submenu === self } }
        if _a11yIsMainMenu { return NSApplication._shared }
        return _NSMenuTracker.current?.rootMenu === self ? _NSMenuTracker.current?.accessibilityOwner : nil
    }
    @MainActor internal var _a11yIsOpen: Bool { _NSMenuTracker.current?.levelIndex(of: self) != nil }
    /// Closes the menu if it is open.
    @MainActor internal func _a11yCancel() -> Bool { _NSMenuTracker.current?.accessibilityClose(self) ?? false }
}

extension NSMenu: _NSAccessibilityVirtualElement {
    @MainActor var _accessibilityElementID: Int {
        if _accessibilityID == 0 { _accessibilityID = _NSAccessibilityIDs.next(registering: self) }
        return _accessibilityID
    }
    @MainActor var _accessibilityOwnerView: NSView? {
        var m: NSMenu = self
        while let s = m.supermenu { m = s }
        return _NSMenuTracker.current?.rootMenu === m ? _NSMenuTracker.current?.accessibilityOwner : nil
    }
    @MainActor var _accessibilityVirtualChildren: [any _NSAccessibilityVirtualElement] {
        items.filter { !$0.isSeparatorItem }
    }
    @MainActor func _accessibilityElement() -> PlatformAccessibilityElement {
        let role = _a11yRole
        var e = PlatformAccessibilityElement(id: _accessibilityElementID, role: role.rawValue, frame: _a11yFrame)
        e.label = accessibilityLabel()
        e.identifier = identifier?.rawValue
        e.actions = NSAccessibility._actions(for: role)
        e.children = NSAccessibility._childElements(_a11yChildren)
        return e
    }
    @MainActor func _accessibilityPerform(_ action: PlatformAccessibilityAction) -> Bool {
        action == .cancel ? _a11yCancel() : false
    }
}

extension NSMenuItem {
    @MainActor internal var _a11yRole: NSAccessibility.Role { menu?._a11yIsMainMenu == true ? .menuBarItem : .menuItem }
    @MainActor internal var _a11yIsHighlighted: Bool { _NSMenuTracker.current?.isHighlighted(self) ?? false }
    @MainActor internal var _a11yFrame: NSRect { _NSMenuTracker.current?.screenFrame(of: self) ?? .zero }
    /// Whether the submenu is open on screen (nil: no submenu).
    @MainActor internal var _a11yIsExpanded: Bool? { submenu.map { $0._a11yIsOpen } }

    /// Press (and pick): an item of an open menu is chosen, or its submenu opens, as a click
    /// would; a closed item performs its action, or opens its submenu as a menu of its own
    /// (the menu bar on platforms that draw none).
    @MainActor internal func _a11yPress() -> Bool {
        guard isEnabled, !isSeparatorItem else { return false }
        if let t = _NSMenuTracker.current, t.screenFrame(of: self) != nil { return t.accessibilityActivate(self) }
        if let submenu { return submenu._a11yOpenAsMenu() }
        guard let menu, case let index = menu.index(of: self), index >= 0 else { return false }
        menu.update()
        guard isEnabled else { return false }
        menu.performActionForItem(at: index)
        return true
    }
}

extension NSMenu {
    /// Opens the menu on its own (an item of a menu bar that is not drawn was pressed):
    /// below the key window's content, at its top-left corner.
    @MainActor internal func _a11yOpenAsMenu() -> Bool {
        if _a11yIsOpen { return true }
        let w = NSApplication._shared?.keyWindow ?? NSApplication._shared?.mainWindow ?? NSApplication._shared?.windows.first { $0.isVisible && !($0 is _NSMenuWindow) }
        let anchor: NSRect
        if let w { let c = w.contentRect(forFrameRect: w.frame); anchor = NSRect(x: c.minX, y: c.maxY, width: 0, height: 0) }
        else { anchor = NSRect(origin: Platform.backend.mouseLocation, size: .zero) }
        _NSMenuTracker.begin(menu: self, anchor: anchor, placement: .besideAnchor(edge: .minY), openedWithMouseDown: false)
        return _a11yIsOpen
    }
}

extension NSMenuItem: _NSAccessibilityVirtualElement {
    @MainActor var _accessibilityElementID: Int {
        if _accessibilityID == 0 { _accessibilityID = _NSAccessibilityIDs.next(registering: self) }
        return _accessibilityID
    }
    @MainActor var _accessibilityOwnerView: NSView? { menu?._accessibilityOwnerView }
    @MainActor var _accessibilityVirtualChildren: [any _NSAccessibilityVirtualElement] { submenu.map { [$0] } ?? [] }
    @MainActor func _accessibilityElement() -> PlatformAccessibilityElement {
        let role = _a11yRole
        var e = PlatformAccessibilityElement(id: _accessibilityElementID, role: role.rawValue, frame: _a11yFrame)
        e.title = title
        e.help = toolTip
        let identifier = accessibilityIdentifier()
        e.identifier = identifier.isEmpty ? nil : identifier
        e.isEnabled = isEnabled
        let highlighted = _a11yIsHighlighted
        e.isSelected = highlighted
        e.isFocused = highlighted
        e.isFocusable = true
        e.checkedState = state == .on ? 1 : state == .mixed ? 2 : 0
        let key = _keyEquivalentLabel
        e.keyEquivalent = key.isEmpty ? nil : key
        e.index = menu.map { m in m.items.filter { !$0.isHidden && !$0.isSeparatorItem }.firstIndex { $0 === self } ?? -1 }.flatMap { $0 < 0 ? nil : $0 }
        e.actions = NSAccessibility._actions(for: role)
        if let expanded = _a11yIsExpanded {
            e.isExpanded = expanded
            e.actions += [.expand, .collapse]
        }
        // An open menu shows its own rows; an item's submenu is a child only while the
        // item's menu is closed (an open submenu is a menu window of its own).
        if let submenu, !(menu?._a11yIsOpen ?? false) { e.children = [submenu._accessibilityElement()] }
        return e
    }
    @MainActor func _accessibilityPerform(_ action: PlatformAccessibilityAction) -> Bool {
        switch action {
        case .press, .pick: return _a11yPress()
        case .expand: return submenu != nil && (_a11yIsExpanded == true || _a11yPress())
        case .collapse: return submenu?._a11yCancel() ?? false
        case .cancel: return menu?._a11yCancel() ?? false
        default: return false
        }
    }
}

// MARK: The control that opened a menu

extension NSView {
    /// A menu this view opened (a pop-up button's) appeared: its children changed.
    @MainActor internal func _accessibilityMenuDidOpen(_ menu: NSMenu) {
        guard window != nil else { return }
        _accessibilityNotify(.structure(_accessibilityElementID))
        _accessibilityNotify(.childAdded(parent: _accessibilityElementID, child: menu._accessibilityElementID))
        _accessibilityNotify(.value(_accessibilityElementID))      // expanded state
    }
    /// The menu closed again.
    @MainActor internal func _accessibilityMenuDidClose(_ menu: NSMenu) {
        guard window != nil else { return }
        _accessibilityNotify(.structure(_accessibilityElementID))
        _accessibilityNotify(.childRemoved(parent: _accessibilityElementID, child: menu._accessibilityElementID))
        _accessibilityNotify(.value(_accessibilityElementID))
    }
}

// MARK: The application's menu bar for the platform

extension NSApplication: PlatformAccessibilityApplication {
    public func accessibilityMenuBarTree() -> PlatformAccessibilityElement? { mainMenu?._accessibilityElement() }
    public func accessibilityPerformMenuBarAction(_ action: PlatformAccessibilityAction, on elementID: Int) -> Bool {
        guard let menu = mainMenu, let e = menu._accessibilityVirtualElement(withID: elementID) else { return false }
        return e._accessibilityPerform(action)
    }
}
