// Commands: the menu bar an App gets (app, File, Edit, View, Window, Help) and the
// CommandMenu/CommandGroup additions a scene's `.commands` makes to it. Menu items come
// from the same views as `Menu`: buttons, dividers, toggles and nested menus.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/commands
public protocol Commands {
    associatedtype Body: Commands
    @CommandsBuilder var body: Self.Body { get }
}

extension Never: Commands {}

/// Commands that know how to change the menu bar.
protocol _PrimitiveCommands {
    @MainActor func _apply(to builder: _MenuBarBuilder)
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/commandsbuilder
@resultBuilder
public struct CommandsBuilder {
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<C: Commands>(_ c: C) -> C { c }
    public static func buildBlock<C0: Commands, C1: Commands>(_ c0: C0, _ c1: C1) -> _TupleCommands { _TupleCommands([c0, c1]) }
    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands>(_ c0: C0, _ c1: C1, _ c2: C2) -> _TupleCommands { _TupleCommands([c0, c1, c2]) }
    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> _TupleCommands { _TupleCommands([c0, c1, c2, c3]) }
    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> _TupleCommands { _TupleCommands([c0, c1, c2, c3, c4]) }
    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands, C5: Commands>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> _TupleCommands { _TupleCommands([c0, c1, c2, c3, c4, c5]) }
    public static func buildOptional<C: Commands>(_ c: C?) -> _TupleCommands { _TupleCommands(c.map { [$0] } ?? []) }
    public static func buildEither<C: Commands>(first c: C) -> _TupleCommands { _TupleCommands([c]) }
    public static func buildEither<C: Commands>(second c: C) -> _TupleCommands { _TupleCommands([c]) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/emptycommands
public struct EmptyCommands: Commands, _PrimitiveCommands {
    public typealias Body = Never
    public init() {}
    public var body: Never { fatalError() }
    func _apply(to builder: _MenuBarBuilder) {}
}

public struct _TupleCommands: Commands, _PrimitiveCommands {
    public typealias Body = Never
    let parts: [any Commands]
    init(_ parts: [any Commands]) { self.parts = parts }
    public var body: Never { fatalError() }
    func _apply(to builder: _MenuBarBuilder) { for p in parts { builder.apply(p) } }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/commandgroupplacement
public struct CommandGroupPlacement: Hashable, Sendable {
    let menu: String
    let group: String
    init(_ menu: String, _ group: String) { self.menu = menu; self.group = group }
    public static let appInfo = CommandGroupPlacement("app", "appInfo")
    public static let appSettings = CommandGroupPlacement("app", "appSettings")
    public static let systemServices = CommandGroupPlacement("app", "systemServices")
    public static let appVisibility = CommandGroupPlacement("app", "appVisibility")
    public static let appTermination = CommandGroupPlacement("app", "appTermination")
    public static let newItem = CommandGroupPlacement("File", "newItem")
    public static let saveItem = CommandGroupPlacement("File", "saveItem")
    public static let importExport = CommandGroupPlacement("File", "importExport")
    public static let printItem = CommandGroupPlacement("File", "printItem")
    public static let undoRedo = CommandGroupPlacement("Edit", "undoRedo")
    public static let pasteboard = CommandGroupPlacement("Edit", "pasteboard")
    public static let textEditing = CommandGroupPlacement("Edit", "textEditing")
    public static let textFormatting = CommandGroupPlacement("Format", "textFormatting")
    public static let toolbar = CommandGroupPlacement("View", "toolbar")
    public static let sidebar = CommandGroupPlacement("View", "sidebar")
    public static let windowSize = CommandGroupPlacement("Window", "windowSize")
    public static let windowArrangement = CommandGroupPlacement("Window", "windowArrangement")
    public static let windowList = CommandGroupPlacement("Window", "windowList")
    public static let help = CommandGroupPlacement("Help", "help")
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/commandmenu
public struct CommandMenu<Content: View>: Commands, _PrimitiveCommands {
    public typealias Body = Never
    let title: String
    let content: Content
    public init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(titleKey.key, content: content) }
    public var body: Never { fatalError() }
    func _apply(to builder: _MenuBarBuilder) { builder.addMenu(title: title, content: _ViewBox(content)) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/commandgroup
public struct CommandGroup<Content: View>: Commands, _PrimitiveCommands {
    public typealias Body = Never
    enum Position { case before, after, replacing }
    let position: Position
    let placement: CommandGroupPlacement
    let content: Content
    public init(before placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) { position = .before; self.placement = placement; content = addition() }
    public init(after placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) { position = .after; self.placement = placement; content = addition() }
    public init(replacing placement: CommandGroupPlacement, @ViewBuilder addition: () -> Content) { position = .replacing; self.placement = placement; content = addition() }
    public var body: Never { fatalError() }
    func _apply(to builder: _MenuBarBuilder) {
        let menu = NSMenu(title: "")
        _buildMenu(_ViewBox(content), into: menu)
        let items = menu.items
        for i in items { menu.removeItem(i) }
        switch position {
        case .before: builder.insert(items, before: placement)
        case .after: builder.insert(items, after: placement)
        case .replacing: builder.replace(placement, with: items)
        }
    }
}

// MARK: Menu bar

/// The standard menu bar as named groups per menu, which commands insert into, replace or
/// extend; `makeMenu` turns it into NSMenus with separators between non-empty groups.
@MainActor
public final class _MenuBarBuilder {
    private struct Group { let name: String; var items: [NSMenuItem] }
    private struct MenuSpec { let title: String; var groups: [Group] }
    private var menus: [MenuSpec] = []
    private let appName: String
    private unowned let runner: _AppRunner

    init(appName: String, hasSettings: Bool, runner: _AppRunner) {
        self.appName = appName
        self.runner = runner
        func item(_ title: String, _ selector: String, _ key: String = "", mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: Selector((selector)), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        var app: [Group] = [Group(name: "appInfo", items: [_menuItem(title: "About \(appName)") { NSApplication.shared.orderFrontStandardAboutPanel(nil) }])]
        if hasSettings {
            app.append(Group(name: "appSettings", items: [_menuItem(title: "Settings\u{2026}") { [unowned runner] in runner.openSettings() }]))
            app[1].items[0].keyEquivalent = ","
        } else {
            app.append(Group(name: "appSettings", items: []))
        }
        app.append(Group(name: "systemServices", items: []))
        app.append(Group(name: "appVisibility", items: []))
        app.append(Group(name: "appTermination", items: [item("Quit \(appName)", "terminate:", "q")]))
        menus.append(MenuSpec(title: appName, groups: app))
        menus.append(MenuSpec(title: "File", groups: [
            Group(name: "newItem", items: [_menuItem(title: "New Window") { [unowned runner] in runner.primaryWindowGroup?() }]),
            Group(name: "close", items: [item("Close", "performClose:", "w")]),
            Group(name: "saveItem", items: []),
            Group(name: "importExport", items: []),
            Group(name: "printItem", items: []),
        ]))
        menus[1].groups[0].items[0].keyEquivalent = "n"
        menus.append(MenuSpec(title: "Edit", groups: [
            Group(name: "undoRedo", items: [item("Undo", "undo:", "z"), item("Redo", "redo:", "z", mods: [.command, .shift])]),
            Group(name: "pasteboard", items: [item("Cut", "cut:", "x"), item("Copy", "copy:", "c"), item("Paste", "paste:", "v"),
                                              item("Delete", "delete:"), item("Select All", "selectAll:", "a")]),
            Group(name: "textEditing", items: []),
        ]))
        menus.append(MenuSpec(title: "View", groups: [Group(name: "toolbar", items: []), Group(name: "sidebar", items: [])]))
        menus.append(MenuSpec(title: "Window", groups: [
            Group(name: "windowSize", items: [item("Minimize", "performMiniaturize:", "m"), item("Zoom", "performZoom:")]),
            Group(name: "windowArrangement", items: []),
            Group(name: "windowList", items: []),
        ]))
        menus.append(MenuSpec(title: "Help", groups: [Group(name: "help", items: [item("\(appName) Help", "showHelp:", "?")])]))
    }

    func apply(_ commands: any Commands) {
        if let p = commands as? any _PrimitiveCommands { p._apply(to: self) } else { applyBody(commands) }
    }
    private func applyBody<C: Commands>(_ c: C) { apply(c.body) }

    private func locate(_ placement: CommandGroupPlacement) -> (menu: Int, group: Int)? {
        let title = placement.menu == "app" ? appName : placement.menu
        guard let m = menus.firstIndex(where: { $0.title == title }) else { return nil }
        guard let g = menus[m].groups.firstIndex(where: { $0.name == placement.group }) else { return nil }
        return (m, g)
    }

    /// A new top-level menu, before Window and Help as on macOS.
    func addMenu(title: String, content: _AnyViewBox) {
        let menu = NSMenu(title: title)
        _buildMenu(content, into: menu)
        let items = menu.items
        for i in items { menu.removeItem(i) }
        let spec = MenuSpec(title: title, groups: [Group(name: "custom", items: items)])
        let at = menus.firstIndex { $0.title == "Window" } ?? menus.count
        menus.insert(spec, at: at)
    }

    func replace(_ placement: CommandGroupPlacement, with items: [NSMenuItem]) {
        guard let (m, g) = locate(placement) else { return }
        menus[m].groups[g].items = items
    }
    func insert(_ items: [NSMenuItem], before placement: CommandGroupPlacement) {
        guard let (m, g) = locate(placement) else { return }
        menus[m].groups.insert(Group(name: "before.\(placement.group)", items: items), at: g)
    }
    func insert(_ items: [NSMenuItem], after placement: CommandGroupPlacement) {
        guard let (m, g) = locate(placement) else { return }
        menus[m].groups.insert(Group(name: "after.\(placement.group)", items: items), at: g + 1)
    }

    func makeMenu() -> NSMenu {
        let main = NSMenu(title: "Main")
        for spec in menus {
            let menu = NSMenu(title: spec.title)
            var first = true
            for group in spec.groups where !group.items.isEmpty {
                if !first { menu.addItem(.separator()) }
                first = false
                for i in group.items { menu.addItem(i) }
            }
            guard !menu.items.isEmpty else { continue }
            let item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}
