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
    /// A `ToolbarItemGroup`'s content before it is stacked: the toolbar splits a group of
    /// image buttons into one item per button, as macOS shows them.
    var _groupContent: AnyView? = nil
    /// The environment the wrappers above a split group's button set (`.disabled`).
    var _environment: EnvironmentValues? = nil
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
    public var _toolbarEntries: [_ToolbarEntry] {
        [_ToolbarEntry(id: nil, placement: placement, showsByDefault: true, content: AnyView(HStack(spacing: 8) { content }), _groupContent: AnyView(content))]
    }
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
        if let split = _sidebarSplit() { tb.sidebarSplit = split }
        tb.set(entries: entries, source: self)
        if let v = visibility { tb.isVisible = v != .hidden }
        installed = true
    }
}

extension _ToolbarPrimitive {
    /// The navigation split view (one with a sidebar column) this toolbar's content sits in
    /// or wraps: the toolbar gives it a sidebar toggle and starts the title after its sidebar.
    func _sidebarSplit() -> _SplitPrimitive? {
        func isSidebarSplit(_ n: _ViewNode) -> _SplitPrimitive? {
            guard let p = n.primitive as? _SplitPrimitive, p.sideBySide, p.roles[AnyHashable("sidebar")] != nil else { return nil }
            return p
        }
        var up = node?.parent
        while let n = up {
            if let p = isSidebarSplit(n) { return p }
            up = n.parent
        }
        func down(_ n: _ViewNode, depth: Int) -> _SplitPrimitive? {
            if let p = isSidebarSplit(n) { return p }
            guard depth < 64 else { return nil }
            for c in n.children { if let p = down(c, depth: depth + 1) { return p } }
            return nil
        }
        return node.flatMap { down($0, depth: 0) }
    }
}

/// A split container that can show and hide its sidebar column itself (the toolbar's
/// sidebar toggle asks it when the navigation split view has no `columnVisibility`
/// binding to write).
@MainActor
protocol _SidebarColumnToggling: AnyObject {
    func _toggleSidebarColumn()
}

/// A navigation split view's `columnVisibility` binding, when the app passed one.
@MainActor
protocol _ColumnVisibilityProviding {
    var _columnVisibilityBinding: Binding<NavigationSplitViewVisibility>? { get }
}
extension NavigationSplitView: _ColumnVisibilityProviding {
    var _columnVisibilityBinding: Binding<NavigationSplitViewVisibility>? { columnVisibility }
}

/// The window's toolbar for SwiftUI content. An entry that is a button labelled with a
/// `Label` (or made with `Button(_:systemImage:)`) becomes an image item the toolbar
/// draws itself, as macOS does: the symbol alone in the unified styles, the symbol above
/// its title in the expanded style, the title as label, palette label and tool tip (or the
/// `.help` text), `.disabled` and `.keyboardShortcut` carried over. Any other entry is an
/// item hosting its view.
@MainActor
final class _SwiftUIToolbar: NSToolbar, NSToolbarDelegate {
    private struct Source { weak var primitive: _ToolbarPrimitive?; var entries: [_ToolbarEntry] }
    private var sources: [ObjectIdentifier: Source] = [:]
    private var order: [ObjectIdentifier] = []
    /// One toolbar item and what stands behind it: the hosting view of a view item, the
    /// action target of an image item.
    @MainActor final class Slot {
        let item: NSToolbarItem
        var hosting: NSHostingView<AnyView>?
        let target = _SwiftUIToolbarActionTarget()
        /// What the image was made from, so a re-render with the same symbol keeps it.
        var imageKey: String?
        init(item: NSToolbarItem) { self.item = item }
    }
    private var slots: [String: Slot] = [:]
    private var entries: [String: _ToolbarEntry] = [:]

    /// The navigation split view whose sidebar the band starts after; set by the toolbar
    /// modifiers inside (or around) it. macOS adds the sidebar toggle and a separator
    /// tracking the sidebar's divider for such a window.
    weak var sidebarSplitPrimitive: _SplitPrimitive?
    var sidebarSplit: _SplitPrimitive? {
        get { sidebarSplitPrimitive }
        set {
            guard newValue !== sidebarSplitPrimitive else { return }
            sidebarSplitPrimitive = newValue
            sidebarSeparator = nil
        }
    }
    private var sidebarSeparator: NSTrackingSeparatorToolbarItem?
    private var sidebarResizeObserver: NSObjectProtocol?
    private lazy var sidebarToggle: NSToolbarItem = {
        let item = NSToolbarItem(itemIdentifier: _SwiftUIToolbar.toggleSidebarID)
        item.image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "Sidebar")
        item.label = "Sidebar"
        item.paletteLabel = "Sidebar"
        item.toolTip = "Hide or show the sidebar"
        item.isNavigational = true
        item.autovalidates = false
        item.target = sidebarToggleTarget
        item.action = _SwiftUIToolbarActionTarget.selector
        sidebarToggleTarget.action = { [weak self] in self?.toggleSidebar() }
        return item
    }()
    private let sidebarToggleTarget = _SwiftUIToolbarActionTarget()
    static let toggleSidebarID = NSToolbarItem.Identifier("com.apple.SwiftUI.navigationSplitView.toggleSidebar")
    static let sidebarSeparatorID = NSToolbarItem.Identifier("com.apple.SwiftUI.navigationSplitView.sidebarTrackingSeparator")

    /// The sidebar toggle: writes the split view's `columnVisibility` binding when the app
    /// gave one (all columns ↔ detail only), else asks the split view to collapse or show
    /// its sidebar column itself.
    func toggleSidebar() {
        guard let split = sidebarSplitPrimitive else { return }
        if let binding = (split.node?.box.value as? _ColumnVisibilityProviding)?._columnVisibilityBinding {
            binding.wrappedValue = binding.wrappedValue == .detailOnly ? .all : .detailOnly
        } else if let toggling = split as? _SidebarColumnToggling {
            toggling._toggleSidebarColumn()
        }
        // Once the columns have changed, the title moves with the sidebar's edge.
        Platform.backend.post { [weak self] in self?.sidebarSeparator?.dividerIndex = 0 }
    }

    override init(identifier: NSToolbar.Identifier) {
        super.init(identifier: identifier)
        delegate = self
    }
    /// A SwiftUI window's toolbar is unified unless `.windowToolbarStyle` says otherwise,
    /// as on macOS 11 and later.
    override var _automaticStyleIsUnified: Bool { true }

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
                for part in _split(e) {
                    let id = part.id ?? "SwiftUI.toolbar.item.\(n)"
                    n += 1
                    out.append((id, part))
                }
            }
        }
        return out
    }

    /// A group whose every view is an image button becomes one entry per button; any
    /// other group stays one item hosting the stacked views.
    private func _split(_ e: _ToolbarEntry) -> [_ToolbarEntry] {
        guard let group = e._groupContent else { return [e] }
        let leaves = _flattenMenuBoxes(_ViewBox(group), environment: EnvironmentValues())
        guard leaves.count > 1, leaves.allSatisfy({ _toolbarButton(in: $0.0, environment: $0.1) != nil }) else { return [e] }
        return leaves.map { box, env in
            var part = _ToolbarEntry(id: nil, placement: e.placement, showsByDefault: e.showsByDefault, content: AnyView(_fromValue: box.value) ?? AnyView(EmptyView()))
            part._environment = env
            return part
        }
    }

    /// Leading: navigation; centred: principal; trailing after a flexible space: the rest.
    private var layout: (defaults: [NSToolbarItem.Identifier], centered: [NSToolbarItem.Identifier]) {
        let items = all
        let leading = items.filter { $0.entry.placement == .navigation && $0.entry.showsByDefault }.map { NSToolbarItem.Identifier($0.id) }
        let centered = items.filter { $0.entry.placement == .principal && $0.entry.showsByDefault }.map { NSToolbarItem.Identifier($0.id) }
        let trailing = items.filter { $0.entry.placement != .navigation && $0.entry.placement != .principal && $0.entry.showsByDefault }.map { NSToolbarItem.Identifier($0.id) }
        var defaults = leading + centered
        if !trailing.isEmpty { defaults.append(.flexibleSpace); defaults += trailing }
        if sidebarSplitPrimitive != nil { defaults = [_SwiftUIToolbar.toggleSidebarID, _SwiftUIToolbar.sidebarSeparatorID] + defaults }
        return (defaults, centered)
    }

    private func rebuild() {
        entries = [:]
        for (id, e) in all { entries[id] = e }
        // Existing items keep their hosting views (or targets) and get the new content.
        for (id, slot) in slots {
            if let e = entries[id] { configure(slot, with: e) }
            else { slots[id] = nil }
        }
        let l = layout
        centeredItemIdentifiers = Set(l.centered)
        let current = items.map { $0.itemIdentifier }
        if current != l.defaults {
            setConfiguration([NSToolbar._itemsKeyName: l.defaults.map { $0.rawValue }])
        }
    }

    /// Makes the item stand for the entry: an image item for a button with a label, an
    /// item hosting the view otherwise.
    private func configure(_ slot: Slot, with e: _ToolbarEntry) {
        let item = slot.item
        if item.isNavigational != (e.placement == .navigation) { item.isNavigational = e.placement == .navigation }
        if let b = _toolbarButton(in: _ViewBox(e.content), environment: e._environment ?? EnvironmentValues()) {
            if item.view != nil { item.view = nil }
            slot.hosting = nil
            if slot.imageKey != b.imageKey || item.image == nil { item.image = b.image; slot.imageKey = b.imageKey }
            if item.label != b.title { item.label = b.title }
            if item.paletteLabel != b.title { item.paletteLabel = b.title }
            let tip = b.help ?? b.title
            if item.toolTip != tip { item.toolTip = tip }
            item.autovalidates = false
            if item.isEnabled != b.isEnabled { item.isEnabled = b.isEnabled }
            slot.target.action = b.action
            if item.target !== slot.target { item.target = slot.target }
            if item.action != _SwiftUIToolbarActionTarget.selector { item.action = _SwiftUIToolbarActionTarget.selector }
            var key = "", mask: NSEvent.ModifierFlags = .command
            if let (k, mods) = b.keyShortcut {
                key = String(k.character)
                mask = []
                if mods.contains(.command) { mask.insert(.command) }
                if mods.contains(.shift) { mask.insert(.shift) }
                if mods.contains(.option) { mask.insert(.option) }
                if mods.contains(.control) { mask.insert(.control) }
            }
            item._keyEquivalent = key
            item._keyEquivalentModifierMask = mask
            return
        }
        if item.action != nil { item.action = nil; item.target = nil; item.image = nil; item.autovalidates = true; item.toolTip = nil; slot.imageKey = nil }
        item._keyEquivalent = ""
        let label = e.id ?? ""
        if item.label != label { item.label = label }
        if let h = slot.hosting {
            h.rootView = e.content
        } else {
            slot.hosting = NSHostingView(rootView: e.content)
        }
        if item.view !== slot.hosting { item.view = slot.hosting }
        size(slot)
    }

    private func size(_ slot: Slot) {
        guard let hosting = slot.hosting else { return }
        var s = hosting.sizeThatFits(.unspecified)
        s.width = max(s.width.rounded(.up), 1); s.height = max(s.height.rounded(.up), 1)
        hosting.frame = NSRect(origin: .zero, size: s)
        slot.item.minSize = s
        slot.item.maxSize = s
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { layout.defaults }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (sidebarSplitPrimitive != nil ? [_SwiftUIToolbar.toggleSidebarID, _SwiftUIToolbar.sidebarSeparatorID] : [])
            + all.map { NSToolbarItem.Identifier($0.id) } + [.flexibleSpace, .space]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == _SwiftUIToolbar.toggleSidebarID { return sidebarSplitPrimitive != nil ? sidebarToggle : nil }
        if itemIdentifier == _SwiftUIToolbar.sidebarSeparatorID {
            guard let split = sidebarSplitPrimitive else { return nil }
            if let existing = sidebarSeparator, existing.splitView === split.split { return existing }
            let item = NSTrackingSeparatorToolbarItem(identifier: itemIdentifier, splitView: split.split, dividerIndex: 0)
            sidebarSeparator = item
            // The band lays out again when the sidebar's width changes (a divider drag, the
            // sidebar shown or hidden), so the title keeps following it.
            if let o = sidebarResizeObserver { NotificationCenter.default.removeObserver(o) }
            sidebarResizeObserver = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: split.split, queue: nil) { [weak item] _ in
                MainActor.assumeIsolated { item?.dividerIndex = 0 }
            }
            return item
        }
        guard let e = entries[itemIdentifier.rawValue] else { return nil }
        if let existing = slots[itemIdentifier.rawValue] { return existing.item }
        let slot = Slot(item: NSToolbarItem(itemIdentifier: itemIdentifier))
        configure(slot, with: e)
        slots[itemIdentifier.rawValue] = slot
        return slot.item
    }
}

/// The target of a SwiftUI image item: runs the button's action.
@MainActor
final class _SwiftUIToolbarActionTarget: NSObject {
    static let selector = Selector(("swiftUIToolbarItemAction:"))
    var action: () -> Void = {}
    override init() {
        super.init()
        setActionHandler(for: _SwiftUIToolbarActionTarget.selector) { [weak self] _ in self?.action() }
    }
}

// MARK: Buttons the toolbar draws

/// A toolbar button read from its view: a `Button` whose label is a `Label` with an
/// image (or an `Image`), under any number of `.help`, `.disabled`, `.keyboardShortcut`,
/// animation and other layout-transparent wrappers.
struct _ToolbarButton {
    var title: String
    var image: NSImage
    var imageKey: String
    var action: () -> Void
    var isEnabled: Bool
    var help: String?
    var keyShortcut: (KeyEquivalent, EventModifiers)?
}

/// Buttons that can stand as an image toolbar item.
protocol _ToolbarButtonConvertible {
    @MainActor var _toolbarButtonParts: (title: String, image: Image, action: () -> Void)? { get }
}
extension Button: _ToolbarButtonConvertible {
    var _toolbarButtonParts: (title: String, image: Image, action: () -> Void)? {
        guard let (title, image) = _toolbarLabel(in: _ViewBox(label)) else { return nil }
        return (title, image, action)
    }
}

/// Labels with a text title and an image icon.
protocol _ToolbarLabelConvertible { @MainActor var _toolbarLabelParts: (title: String, image: Image) { get } }
extension Label: _ToolbarLabelConvertible where Title == Text, Icon == Image {
    var _toolbarLabelParts: (title: String, image: Image) { (title._string, icon) }
}

/// `.help` (and nothing that draws) around a toolbar button.
protocol _ToolbarDecoration {
    @MainActor var _toolbarHelp: String? { get }
    @MainActor var _toolbarDecoratedContent: _AnyViewBox? { get }
}
extension _Decorated: _ToolbarDecoration {
    var _toolbarHelp: String? { style.helpText }
    var _toolbarDecoratedContent: _AnyViewBox? { background == nil && overlay == nil ? _ViewBox(content) : nil }
}

/// The title and image of a button label: a `Label(_:systemImage:)` (also through
/// `.contentTransition` and other transparent wrappers) or a bare `Image`.
@MainActor
func _toolbarLabel(in box: _AnyViewBox) -> (String, Image)? {
    var current = box
    for _ in 0..<16 {
        if let l = current.value as? _ToolbarLabelConvertible { return l._toolbarLabelParts }
        if let i = current.value as? Image { return (i.accessibilityLabel ?? i.name, i) }
        guard current.isPrimitive, !(current.value is _MetadataView), let p = current.makePrimitive(node: _ViewNode.placeholder),
              p.isLayoutTransparent, p.children.count == 1 else { return nil }
        current = p.children[0]
    }
    return nil
}

/// Reads an entry's view as a toolbar button, or nil when it is anything else (or its
/// image is not one the port draws).
@MainActor
func _toolbarButton(in box: _AnyViewBox, environment: EnvironmentValues) -> _ToolbarButton? {
    var env = environment
    var meta = _ItemMetadata()
    var help: String?
    var current = box
    for _ in 0..<32 {
        let value = current.value
        if let b = value as? _ToolbarButtonConvertible {
            guard let parts = b._toolbarButtonParts, let image = parts.image.image else { return nil }
            let key = parts.image.name.isEmpty ? "\(ObjectIdentifier(image))" : parts.image.name
            return _ToolbarButton(title: parts.title, image: image, imageKey: key, action: parts.action, isEnabled: env.isEnabled,
                                  help: help, keyShortcut: meta.keyShortcut)
        }
        if let m = value as? _MetadataView {
            m._apply(to: &meta)
            current = m._metaContent
            continue
        }
        if let d = value as? _ToolbarDecoration {
            guard let inner = d._toolbarDecoratedContent else { return nil }
            if let h = d._toolbarHelp { help = h }       // the innermost `.help` wins
            current = inner
            continue
        }
        guard current.isPrimitive, let p = current.makePrimitive(node: _ViewNode.placeholder), p.isLayoutTransparent, p.children.count == 1 else { return nil }
        p.environmentTransform?(&env)
        current = p.children[0]
    }
    return nil
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
