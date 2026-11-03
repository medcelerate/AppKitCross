// Menus: the pop-up Picker, the Menu view and contextMenu, all over NSPopUpButton/NSMenu.

import Foundation

// MARK: Pop-up picker

/// A pop-up button listing `titles`; used by Picker's menu and automatic styles.
struct _PopUp: View, _PrimitiveView {
    typealias Body = Never
    let titles: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive { _PopUpPrimitive(titles: titles, selected: selected, onSelect: onSelect) }
}

@MainActor
final class _PopUpPrimitive: _ControlPrimitive<NSPopUpButton> {
    var titles: [String]
    var onSelect: (Int) -> Void
    init(titles: [String], selected: Int, onSelect: @escaping (Int) -> Void) {
        self.titles = titles
        self.onSelect = onSelect
        let b = NSPopUpButton(frame: .zero, pullsDown: false)
        b.addItems(withTitles: titles)
        b.selectItem(at: selected)
        super.init(control: b)
        b.target = b
        b.action = Selector(("swiftUIPopUpAction:"))
        b.setActionHandler(for: Selector(("swiftUIPopUpAction:"))) { [weak self] _ in
            guard let self else { return }
            self.onSelect(self.control.indexOfSelectedItem)
        }
        b.sizeToFit()
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _PopUpPrimitive else { return }
        onSelect = o.onSelect
        if o.titles != titles {
            titles = o.titles
            control.removeAllItems()
            control.addItems(withTitles: titles)
        }
        control.selectItem(at: o.control.indexOfSelectedItem)
        control.sizeToFit()
    }
}

// MARK: Menu items from views

/// Views that know how to add themselves to an NSMenu (buttons, dividers, nested menus).
protocol _MenuItemConvertible {
    @MainActor func _addMenuItems(to menu: NSMenu)
}

/// Builds `menu`'s items from a view hierarchy: buttons become items, dividers separators,
/// nested menus submenus, toggles checked items and plain text disabled items.
@MainActor
func _buildMenu(_ box: _AnyViewBox, into menu: NSMenu) {
    for b in _flattenBoxes(box) {
        let (meta, content) = _metadata(of: b)
        let before = menu.items.count
        if let c = content.value as? _MenuItemConvertible {
            c._addMenuItems(to: menu)
        } else if let t = content.value as? Text {
            let item = NSMenuItem(title: t._string, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        // `.keyboardShortcut` on the item becomes its key equivalent.
        if let (key, modifiers) = meta.keyShortcut {
            for item in menu.items.dropFirst(before) where item.submenu == nil && !item.isSeparatorItem {
                item.keyEquivalent = String(key.character)
                var m: NSEvent.ModifierFlags = []
                if modifiers.contains(.command) { m.insert(.command) }
                if modifiers.contains(.shift) { m.insert(.shift) }
                if modifiers.contains(.option) { m.insert(.option) }
                if modifiers.contains(.control) { m.insert(.control) }
                item.keyEquivalentModifierMask = m
            }
        }
    }
}

/// A menu item that runs a closure when chosen.
@MainActor
func _menuItem(title: String, action: @escaping () -> Void) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: Selector(("swiftUIMenuItemAction:")), keyEquivalent: "")
    item.target = item
    item.setActionHandler(for: Selector(("swiftUIMenuItemAction:"))) { _ in action() }
    return item
}

@MainActor
private func _title(of label: Any) -> String {
    if let t = label as? Text { return t._string }
    if let l = label as? _LabelTitled { return l._labelTitle }
    return String(describing: type(of: label))
}

/// Labels whose title text can be read for a menu item.
protocol _LabelTitled { @MainActor var _labelTitle: String { get } }
extension Label: _LabelTitled where Title == Text {
    var _labelTitle: String { title._string }
}

extension Button: _MenuItemConvertible {
    func _addMenuItems(to menu: NSMenu) { menu.addItem(_menuItem(title: _title(of: label), action: action)) }
}

extension Divider: _MenuItemConvertible {
    func _addMenuItems(to menu: NSMenu) { menu.addItem(.separator()) }
}

extension Toggle: _MenuItemConvertible {
    func _addMenuItems(to menu: NSMenu) {
        let binding = isOn
        let item = _menuItem(title: _title(of: label)) { binding.wrappedValue.toggle() }
        item.state = binding.wrappedValue ? .on : .off
        menu.addItem(item)
    }
}

// MARK: Menu

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/menu
public struct Menu<Label: View, Content: View>: View, _PrimitiveView, _MenuItemConvertible {
    public typealias Body = Never
    let label: Label
    let content: Content
    let primaryAction: (() -> Void)?

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content(); self.label = label(); primaryAction = nil
    }
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping () -> Void) {
        self.content = content(); self.label = label(); self.primaryAction = primaryAction
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _MenuPrimitive(title: _title(of: label), content: _ViewBox(content))
    }
    func _addMenuItems(to menu: NSMenu) {
        let item = NSMenuItem(title: _title(of: label), action: nil, keyEquivalent: "")
        let sub = NSMenu(title: item.title)
        _buildMenu(_ViewBox(content), into: sub)
        item.submenu = sub
        menu.addItem(item)
    }
}

extension Menu where Label == Text {
    public init(_ title: String, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(title) }) }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(titleKey) }) }
    public init(_ title: String, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) {
        self.init(content: content, label: { Text(title) }, primaryAction: primaryAction)
    }
}

/// A pull-down button whose menu is rebuilt from the content on every update.
@MainActor
final class _MenuPrimitive: _ControlPrimitive<NSPopUpButton> {
    var title: String
    var contentBox: _AnyViewBox
    init(title: String, content: _AnyViewBox) {
        self.title = title
        contentBox = content
        let b = NSPopUpButton(frame: .zero, pullsDown: true)
        (b.cell as? NSPopUpButtonCell)?.usesItemFromMenu = false
        super.init(control: b)
        rebuild()
    }
    private func rebuild() {
        let menu = NSMenu(title: title)
        _buildMenu(contentBox, into: menu)
        control.menu = menu
        control.setTitle(title)
        control.sizeToFit()
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _MenuPrimitive else { return }
        title = o.title
        contentBox = o.contentBox
        rebuild()
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/menustyle
public protocol MenuStyle {}
public struct DefaultMenuStyle: MenuStyle { public init() {} }
public struct ButtonMenuStyle: MenuStyle { public init() {} }
extension MenuStyle where Self == DefaultMenuStyle { public static var automatic: DefaultMenuStyle { DefaultMenuStyle() } }
extension MenuStyle where Self == ButtonMenuStyle { public static var button: ButtonMenuStyle { ButtonMenuStyle() } }
extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/menustyle(_:)
    public func menuStyle<S: MenuStyle>(_ style: S) -> some View { self }
}

// MARK: Context menu

/// Hosts content and opens a menu built from `items` on a right click.
@MainActor
final class _ContextMenuView: NSView {
    var makeMenu: (() -> NSMenu)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
}

@MainActor
final class _ContextMenuPrimitive: _Primitive {
    let view = _ContextMenuView(frame: .zero)
    var itemsBox: _AnyViewBox
    init(content: _AnyViewBox, items: _AnyViewBox) {
        itemsBox = items
        super.init()
        children = [content]
        view.makeMenu = { [weak self] in
            let menu = NSMenu(title: "")
            if let self { _buildMenu(self.itemsBox, into: menu) }
            return menu
        }
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _ContextMenuPrimitive { itemsBox = o.itemsBox }
    }
}

struct _ContextMenu<Content: View, Items: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let items: Items
    func _makePrimitive(node: _ViewNode) -> _Primitive { _ContextMenuPrimitive(content: _ViewBox(content), items: _ViewBox(items)) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)
    public func contextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
        _ContextMenu(content: self, items: menuItems())
    }
}
