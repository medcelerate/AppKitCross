// Toolbars: `.toolbar { ToolbarItem(placement:) { ... } }` over NSToolbar (ADR-0018).
//
// The modifier collects its items into a window-level NSToolbar whose items host the
// SwiftUI content in NSHostingViews: navigation items lead, principal items are centred,
// the rest follow a flexible space at the trailing edge, as macOS lays them out.
// Items with an `id` can be customized by the user (`showsByDefault` keeps them out of
// the default set); `.toolbar(.hidden)` hides the toolbar.

import Foundation
import AppKit

// MARK: Content

/// One item of a toolbar, as the content tree flattens to.
public struct _ToolbarEntry {
    public var id: String?
    public var placement: ToolbarItemPlacement
    public var showsByDefault: Bool
    public var content: AnyView
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbarcontent
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent
    @ToolbarContentBuilder var body: Self.Body { get }
    /// The items this content stands for (primitives override; composites flatten their body).
    var _toolbarEntries: [_ToolbarEntry] { get }
}

extension ToolbarContent {
    public var _toolbarEntries: [_ToolbarEntry] { body._toolbarEntries }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/customizabletoolbarcontent
public protocol CustomizableToolbarContent: ToolbarContent where Self.Body: CustomizableToolbarContent {}

extension Never: ToolbarContent {
    public var _toolbarEntries: [_ToolbarEntry] { [] }
}
extension Never: CustomizableToolbarContent {}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbaritemplacement
public struct ToolbarItemPlacement: Hashable, Sendable {
    let kind: String
    public static let automatic = ToolbarItemPlacement(kind: "automatic")
    public static let principal = ToolbarItemPlacement(kind: "principal")
    public static let navigation = ToolbarItemPlacement(kind: "navigation")
    public static let primaryAction = ToolbarItemPlacement(kind: "primaryAction")
    public static let secondaryAction = ToolbarItemPlacement(kind: "secondaryAction")
    public static let status = ToolbarItemPlacement(kind: "status")
    public static let confirmationAction = ToolbarItemPlacement(kind: "confirmationAction")
    public static let cancellationAction = ToolbarItemPlacement(kind: "cancellationAction")
    public static let destructiveAction = ToolbarItemPlacement(kind: "destructiveAction")
    public static let keyboard = ToolbarItemPlacement(kind: "keyboard")
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbarplacement
public struct ToolbarPlacement: Hashable, Sendable {
    let kind: String
    public static let automatic = ToolbarPlacement(kind: "automatic")
    public static let windowToolbar = ToolbarPlacement(kind: "windowToolbar")
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbaritem
public struct ToolbarItem<ID, Content: View>: ToolbarContent {
    public typealias Body = Never
    let id: String?
    let placement: ToolbarItemPlacement
    let showsByDefault: Bool
    let content: Content
    public var body: Never { return fatalError() }
    public var _toolbarEntries: [_ToolbarEntry] { [_ToolbarEntry(id: id, placement: placement, showsByDefault: showsByDefault, content: AnyView(content))] }
}

extension ToolbarItem where ID == () {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbaritem/init(placement:content:)
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        id = nil; self.placement = placement; showsByDefault = true; self.content = content()
    }
}

extension ToolbarItem where ID == String {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbaritem/init(id:placement:showsbydefault:content:)
    public init(id: String, placement: ToolbarItemPlacement = .automatic, showsByDefault: Bool = true, @ViewBuilder content: () -> Content) {
        self.id = id; self.placement = placement; self.showsByDefault = showsByDefault; self.content = content()
    }
}
extension ToolbarItem: CustomizableToolbarContent where ID == String {}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbaritemgroup
public struct ToolbarItemGroup<Content: View>: ToolbarContent {
    public typealias Body = Never
    let placement: ToolbarItemPlacement
    let content: Content
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbaritemgroup/init(placement:content:)
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement; self.content = content()
    }
    public var body: Never { return fatalError() }
    public var _toolbarEntries: [_ToolbarEntry] { [_ToolbarEntry(id: nil, placement: placement, showsByDefault: true, content: AnyView(HStack(spacing: 8) { content }))] }
}

/// What the builder returns for several pieces of content.
public struct _ToolbarContentList: ToolbarContent {
    public typealias Body = Never
    let entries: [_ToolbarEntry]
    public var body: Never { return fatalError() }
    public var _toolbarEntries: [_ToolbarEntry] { entries }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/toolbarcontentbuilder
/// Every piece of content is flattened to its entries as it is built, so `if`, `if/else`
/// and `for` work without the generic plumbing SwiftUI's own builder needs.
@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildExpression<C: ToolbarContent>(_ c: C) -> _ToolbarContentList { _ToolbarContentList(entries: c._toolbarEntries) }
    public static func buildBlock(_ parts: _ToolbarContentList...) -> _ToolbarContentList { _ToolbarContentList(entries: parts.flatMap { $0.entries }) }
    public static func buildOptional(_ c: _ToolbarContentList?) -> _ToolbarContentList { c ?? _ToolbarContentList(entries: []) }
    public static func buildEither(first c: _ToolbarContentList) -> _ToolbarContentList { c }
    public static func buildEither(second c: _ToolbarContentList) -> _ToolbarContentList { c }
    public static func buildArray(_ cs: [_ToolbarContentList]) -> _ToolbarContentList { _ToolbarContentList(entries: cs.flatMap { $0.entries }) }
    public static func buildLimitedAvailability(_ c: _ToolbarContentList) -> _ToolbarContentList { c }
}

// MARK: Modifiers

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/toolbar(content:)-5w0tj
    public func toolbar<Content: ToolbarContent>(@ToolbarContentBuilder content: () -> Content) -> some View {
        _ToolbarModified(content: self, entries: content()._toolbarEntries, visibility: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/toolbar(content:)-7vdkx
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        _ToolbarModified(content: self, entries: [_ToolbarEntry(id: nil, placement: .automatic, showsByDefault: true, content: AnyView(content()))], visibility: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/toolbar(id:content:)
    public func toolbar<Content: CustomizableToolbarContent>(id: String, @ToolbarContentBuilder content: () -> Content) -> some View {
        _ToolbarModified(content: self, entries: content()._toolbarEntries, visibility: nil, identifier: id)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/toolbar(_:for:)
    public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        _ToolbarModified(content: self, entries: [], visibility: visibility)
    }
}

struct _ToolbarModified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let entries: [_ToolbarEntry]
    let visibility: Visibility?
    var identifier: String? = nil
    func _makePrimitive(node: _ViewNode) -> _Primitive { _ToolbarPrimitive(entries: entries, visibility: visibility, identifier: identifier, content: _ViewBox(content)) }
}

/// Installs the items on the hosting window's toolbar (making the toolbar when the
/// window has none) and keeps them current across renders; removes them when the
/// modifier leaves the tree.
@MainActor
final class _ToolbarPrimitive: _Primitive {
    private var entries: [_ToolbarEntry]
    private var visibility: Visibility?
    private var identifier: String?
    private weak var window: NSWindow?
    private var installed = false
    private var retries = 0

    init(entries: [_ToolbarEntry], visibility: Visibility?, identifier: String?, content: _AnyViewBox) {
        self.entries = entries; self.visibility = visibility; self.identifier = identifier
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func attach(to node: _ViewNode) { super.attach(to: node); sync() }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _ToolbarPrimitive else { return }
        entries = o.entries; visibility = o.visibility; identifier = o.identifier
        sync()
    }
    override func detach() {
        guard installed, let w = window, let tb = w.toolbar as? _SwiftUIToolbar else { return }
        tb.remove(source: self)
        installed = false
    }

    private func sync() {
        guard let w = node?.root?.host?.hostWindow else {
            // The hosting view is not in a window yet (the App makes the window after the
            // first layout): try again once the loop turns.
            if retries < 20 { retries += 1; Platform.backend.post { [weak self] in self?.sync() } }
            return
        }
        window = w
        let tb: _SwiftUIToolbar
        if let existing = w.toolbar as? _SwiftUIToolbar { tb = existing }
        else {
            tb = _SwiftUIToolbar(identifier: identifier ?? "SwiftUI.toolbar.\(w.windowNumber)")
            w.toolbar = tb
        }
        if let id = identifier { tb.allowsUserCustomization = true; tb.autosavesConfiguration = true }
        tb.set(entries: entries, source: self)
        if let v = visibility { tb.isVisible = v != .hidden }
        installed = true
    }
}

/// The window's toolbar for SwiftUI content: each entry is an item hosting its view.
@MainActor
final class _SwiftUIToolbar: NSToolbar, NSToolbarDelegate {
    private struct Source { weak var primitive: _ToolbarPrimitive?; var entries: [_ToolbarEntry] }
    private var sources: [ObjectIdentifier: Source] = [:]
    private var order: [ObjectIdentifier] = []
    private var hosted: [String: (item: NSToolbarItem, hosting: NSHostingView<AnyView>)] = [:]
    private var entries: [String: _ToolbarEntry] = [:]

    override init(identifier: NSToolbar.Identifier) {
        super.init(identifier: identifier)
        delegate = self
    }

    /// The entries one `.toolbar` modifier contributes; several modifiers in one window
    /// append in the order they attached.
    func set(entries: [_ToolbarEntry], source: _ToolbarPrimitive) {
        let key = ObjectIdentifier(source)
        if sources[key] == nil { order.append(key) }
        sources[key] = Source(primitive: source, entries: entries)
        rebuild()
    }

    func remove(source: _ToolbarPrimitive) {
        let key = ObjectIdentifier(source)
        sources[key] = nil
        order.removeAll { $0 == key }
        rebuild()
    }

    private var all: [(id: String, entry: _ToolbarEntry)] {
        var out: [(String, _ToolbarEntry)] = []
        var n = 0
        for key in order {
            guard let s = sources[key] else { continue }
            for e in s.entries {
                let id = e.id ?? "SwiftUI.toolbar.item.\(n)"
                n += 1
                out.append((id, e))
            }
        }
        return out
    }

    /// Leading: navigation; centred: principal; trailing after a flexible space: the rest.
    private var layout: (defaults: [NSToolbarItem.Identifier], centered: [NSToolbarItem.Identifier]) {
        let items = all
        let leading = items.filter { $0.entry.placement == .navigation && $0.entry.showsByDefault }.map { NSToolbarItem.Identifier($0.id) }
        let centered = items.filter { $0.entry.placement == .principal && $0.entry.showsByDefault }.map { NSToolbarItem.Identifier($0.id) }
        let trailing = items.filter { $0.entry.placement != .navigation && $0.entry.placement != .principal && $0.entry.showsByDefault }.map { NSToolbarItem.Identifier($0.id) }
        var defaults = leading + centered
        if !trailing.isEmpty { defaults.append(.flexibleSpace); defaults += trailing }
        return (defaults, centered)
    }

    private func rebuild() {
        entries = [:]
        for (id, e) in all { entries[id] = e }
        // Existing items keep their hosting views and get the new content.
        for (id, pair) in hosted {
            if let e = entries[id] { pair.hosting.rootView = e.content; size(pair) }
            else { hosted[id] = nil }
        }
        let l = layout
        centeredItemIdentifiers = Set(l.centered)
        let current = items.map { $0.itemIdentifier }
        if current != l.defaults {
            setConfiguration([NSToolbar._itemsKeyName: l.defaults.map { $0.rawValue }])
        }
    }

    private func size(_ pair: (item: NSToolbarItem, hosting: NSHostingView<AnyView>)) {
        var s = pair.hosting.sizeThatFits(.unspecified)
        s.width = max(s.width.rounded(.up), 1); s.height = max(s.height.rounded(.up), 1)
        pair.hosting.frame = NSRect(origin: .zero, size: s)
        pair.item.minSize = s
        pair.item.maxSize = s
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { layout.defaults }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        all.map { NSToolbarItem.Identifier($0.id) } + [.flexibleSpace, .space]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let e = entries[itemIdentifier.rawValue] else { return nil }
        if let existing = hosted[itemIdentifier.rawValue] { return existing.item }
        let hosting = NSHostingView(rootView: e.content)
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = e.id ?? ""
        item.view = hosting
        let pair = (item, hosting)
        size(pair)
        hosted[itemIdentifier.rawValue] = pair
        return item
    }
}

extension NSToolbar {
    /// AppKit's configuration key for the item list ("TB Item Identifiers").
    static var _itemsKeyName: String { "TB Item Identifiers" }
}

// MARK: Scene

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/windowtoolbarstyle
public protocol WindowToolbarStyle { var _toolbarStyle: NSWindow.ToolbarStyle { get } }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/defaultwindowtoolbarstyle
public struct DefaultWindowToolbarStyle: WindowToolbarStyle { public init() {}; public var _toolbarStyle: NSWindow.ToolbarStyle { .automatic } }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/expandedwindowtoolbarstyle
public struct ExpandedWindowToolbarStyle: WindowToolbarStyle { public init() {}; public var _toolbarStyle: NSWindow.ToolbarStyle { .expanded } }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/unifiedwindowtoolbarstyle
public struct UnifiedWindowToolbarStyle: WindowToolbarStyle {
    let showsTitle: Bool
    public init() { showsTitle = true }
    public init(showsTitle: Bool) { self.showsTitle = showsTitle }
    public var _toolbarStyle: NSWindow.ToolbarStyle { .unified }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/unifiedcompactwindowtoolbarstyle
public struct UnifiedCompactWindowToolbarStyle: WindowToolbarStyle {
    let showsTitle: Bool
    public init() { showsTitle = true }
    public init(showsTitle: Bool) { self.showsTitle = showsTitle }
    public var _toolbarStyle: NSWindow.ToolbarStyle { .unifiedCompact }
}
extension WindowToolbarStyle where Self == DefaultWindowToolbarStyle { public static var automatic: DefaultWindowToolbarStyle { DefaultWindowToolbarStyle() } }
extension WindowToolbarStyle where Self == ExpandedWindowToolbarStyle { public static var expanded: ExpandedWindowToolbarStyle { ExpandedWindowToolbarStyle() } }
extension WindowToolbarStyle where Self == UnifiedWindowToolbarStyle {
    public static var unified: UnifiedWindowToolbarStyle { UnifiedWindowToolbarStyle() }
    public static func unified(showsTitle: Bool) -> UnifiedWindowToolbarStyle { UnifiedWindowToolbarStyle(showsTitle: showsTitle) }
}
extension WindowToolbarStyle where Self == UnifiedCompactWindowToolbarStyle {
    public static var unifiedCompact: UnifiedCompactWindowToolbarStyle { UnifiedCompactWindowToolbarStyle() }
    public static func unifiedCompact(showsTitle: Bool) -> UnifiedCompactWindowToolbarStyle { UnifiedCompactWindowToolbarStyle(showsTitle: showsTitle) }
}

extension Scene {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/scene/windowtoolbarstyle(_:)
    public func windowToolbarStyle<S: WindowToolbarStyle>(_ style: S) -> some Scene { _ToolbarStyledScene(base: self, style: style._toolbarStyle) }
}

struct _ToolbarStyledScene<Base: Scene>: Scene, _PrimitiveScene {
    typealias Body = Never
    let base: Base
    let style: NSWindow.ToolbarStyle
    var body: Never { fatalError() }
    @MainActor func _makeWindows(app: _AppRunner) {
        let previous = app.pendingToolbarStyle
        app.pendingToolbarStyle = style
        app.run(scene: base)
        app.pendingToolbarStyle = previous
    }
}
