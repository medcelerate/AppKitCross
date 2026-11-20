// Navigation and presentation: NavigationStack, NavigationLink, TabView, Picker, sheets
// and alerts. The stack and tabs are built from SwiftUI views; sheets are NSWindows
// attached with NSWindow.beginSheet, alerts are NSAlerts.

import Foundation

// MARK: Box inspection

/// The leaf boxes of a view, through tuples, ForEach, Group, optionals and conditionals.
@MainActor
func _flattenBoxes(_ box: _AnyViewBox) -> [_AnyViewBox] {
    // Metadata wrappers (tags, tab items) are the items themselves: stop at them.
    guard !(box.value is _MetadataView), box.isPrimitive, let p = box.makePrimitive(node: _ViewNode.placeholder), p.isLayoutTransparent, !(box.value is _LeafMarker) else { return [box] }
    return p.children.flatMap { _flattenBoxes($0) }
}

/// Views that are transparent groups to layout but still one item (tab pages, picker rows).
protocol _LeafMarker {}

/// A wrapper that carries metadata down to a container (tags, tab items).
protocol _MetadataView {
    var _metaContent: _AnyViewBox { get }
    func _apply(to meta: inout _ItemMetadata)
}

struct _ItemMetadata {
    var tag: AnyHashable? = nil
    var tabLabel: Text? = nil
    var tabImage: Image? = nil
    var keyShortcut: (KeyEquivalent, EventModifiers)? = nil
}

/// Reads the metadata wrappers around a leaf and returns the innermost content.
@MainActor
func _metadata(of box: _AnyViewBox) -> (meta: _ItemMetadata, content: _AnyViewBox) {
    var meta = _ItemMetadata()
    var current = box
    while let m = current.value as? _MetadataView {
        m._apply(to: &meta)
        current = m._metaContent
    }
    return (meta, current)
}

struct _Tagged<Content: View, Tag: Hashable>: View, _PrimitiveView, _MetadataView {
    typealias Body = Never
    let content: Content
    let tag: Tag
    var _metaContent: _AnyViewBox { _ViewBox(content) }
    func _apply(to meta: inout _ItemMetadata) { if meta.tag == nil { meta.tag = AnyHashable(tag) } }
    func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: [_ViewBox(content)]) }
}

struct _TabItem<Content: View, Label: View>: View, _PrimitiveView, _MetadataView {
    typealias Body = Never
    let content: Content
    let label: Label
    var _metaContent: _AnyViewBox { _ViewBox(content) }
    func _apply(to meta: inout _ItemMetadata) {
        guard meta.tabLabel == nil else { return }
        if let t = label as? Text { meta.tabLabel = t }
        else if let l = label as? SwiftUI.Label<Text, Image> { meta.tabLabel = l.title; meta.tabImage = l.icon }
        else { meta.tabLabel = Text(String(describing: type(of: label))) }
    }
    func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: [_ViewBox(content)]) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/tag(_:)
    public func tag<V: Hashable>(_ tag: V) -> some View { _Tagged(content: self, tag: tag) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/tabitem(_:)
    public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> some View { _TabItem(content: self, label: label()) }
}

// MARK: Segmented selector (tab bars, segmented pickers)

@MainActor
final class _SegmentedPrimitive: _ControlPrimitive<NSSegmentedControl> {
    var titles: [String]
    var onSelect: (Int) -> Void

    init(titles: [String], selected: Int, onSelect: @escaping (Int) -> Void) {
        self.titles = titles
        self.onSelect = onSelect
        let c = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: nil, action: nil)
        c.selectedSegment = selected
        super.init(control: c)
        c.target = c
        c.action = Selector(("swiftUISegmentAction:"))
        c.setActionHandler(for: Selector(("swiftUISegmentAction:"))) { [weak self] _ in
            guard let self else { return }
            self.onSelect(self.control.selectedSegment)
        }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _SegmentedPrimitive else { return }
        onSelect = o.onSelect
        if o.titles != titles {
            titles = o.titles
            control.segmentCount = titles.count
            for (i, t) in titles.enumerated() { control.setLabel(t, forSegment: i) }
        }
        if control.selectedSegment != o.control.selectedSegment { control.selectedSegment = o.control.selectedSegment }
    }
}

struct _Segmented: View, _PrimitiveView {
    typealias Body = Never
    let titles: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive { _SegmentedPrimitive(titles: titles, selected: selected, onSelect: onSelect) }
}

// MARK: TabView

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabview
public struct TabView<SelectionValue: Hashable, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let selection: Binding<SelectionValue>?
    let content: Content
    public init(@ViewBuilder content: () -> Content) where SelectionValue == Int {
        selection = nil
        self.content = content()
    }
    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.content = content()
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        _TabViewPrimitive(selection: selection.map { AnyBinding($0) }, content: _ViewBox(content), settingsStyle: _TabViewPrimitive._inSettingsScene(node))
    }
}

extension EnvironmentValues {
    private struct SettingsSceneKey: EnvironmentKey { static let defaultValue = false }
    /// True for the content of a `Settings` scene's window (`_AppRunner.openSettings`): a
    /// TabView there shows the macOS Settings tab bar rather than a segmented control.
    var _isSettingsScene: Bool { get { self[SettingsSceneKey.self] } set { self[SettingsSceneKey.self] = newValue } }
}

/// A binding to any hashable selection, compared through AnyHashable.
struct AnyBinding {
    let get: () -> AnyHashable
    let set: (AnyHashable) -> Void
    init<V: Hashable>(_ b: Binding<V>) {
        get = { AnyHashable(b.wrappedValue) }
        set = { if let v = $0.base as? V { b.wrappedValue = v } }
    }
}

@MainActor
final class _TabViewPrimitive: _Primitive {
    var selection: AnyBinding?
    var contentBox: _AnyViewBox
    var localIndex = 0
    private var pages: [(meta: _ItemMetadata, box: _AnyViewBox)] = []

    /// In a Settings window the tabs are the toolbar-style bar of icons over labels, and the
    /// window's title is the selected tab's.
    var settingsStyle: Bool

    init(selection: AnyBinding?, content: _AnyViewBox, settingsStyle: Bool = false) {
        self.selection = selection
        contentBox = content
        self.settingsStyle = settingsStyle
        super.init()
        rebuild()
    }
    /// The Settings scene marks its content through the environment; the window's class
    /// answers too, for content the scene re-ran into an open Settings window.
    static func _inSettingsScene(_ node: _ViewNode) -> Bool {
        node.environment._isSettingsScene || node.root?.host?.hostView.window is _SettingsWindow
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        guard let o = other as? _TabViewPrimitive else { return }
        selection = o.selection
        contentBox = o.contentBox
        settingsStyle = o.settingsStyle
        rebuild()
    }
    /// Selects page `i`: the binding takes its tag (or index), and the view re-renders.
    func _select(_ i: Int) {
        guard pages.indices.contains(i) else { return }
        localIndex = i
        if let sel = selection {
            if let tag = pages[i].meta.tag { sel.set(tag) } else { sel.set(AnyHashable(i)) }
        }
        node?.setNeedsUpdate()
    }
    private var selectedIndex: Int {
        if let s = selection?.get(), let i = pages.firstIndex(where: { $0.meta.tag == s }) { return i }
        if let s = selection?.get(), let i = s.base as? Int, pages.indices.contains(i), pages[i].meta.tag == nil { return i }
        return min(localIndex, max(0, pages.count - 1))
    }
    private func rebuild() {
        pages = _flattenBoxes(contentBox).map { _metadata(of: $0) }
        let index = selectedIndex
        let titles = pages.enumerated().map { i, p in p.meta.tabLabel?._string ?? "Tab \(i + 1)" }
        let page = pages.isEmpty ? _ViewBox(EmptyView()) : pages[index].box
        if settingsStyle {
            // macOS's Settings window: a band of icon-over-label items under the title bar,
            // the pane filling the rest of the window.
            let items = zip(titles, pages).map { _SettingsTabBarView.Item(title: $0, image: $1.meta.tabImage?.image) }
            let bar = _SettingsTabBar(items: items, selected: index) { [weak self] i in self?._select(i) }
            let body = VStack(spacing: 0) {
                bar
                _Page(box: page).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            children = [_ViewBox(body, id: AnyHashable("settings-tabview"))]
            return
        }
        let bar = _Segmented(titles: titles, selected: index) { [weak self] i in self?._select(i) }
        let body = VStack(spacing: 8) {
            bar
            // A page fills the space below the bar from the top, so a tall page spills past
            // the window's bottom edge rather than over the bar.
            _Page(box: page).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        children = [_ViewBox(body, id: AnyHashable("tabview"))]
        // The page keeps its identity across selection changes only when the same page shows.
    }
}

// MARK: Settings tab bar

/// A TabView's tabs in a Settings window, as macOS draws them: a full-width band under the
/// title bar with one item per tab (the symbol above the label), the row centred, the
/// selected item on a rounded grey background.
struct _SettingsTabBar: View, _PrimitiveView {
    typealias Body = Never
    let items: [_SettingsTabBarView.Item]
    let selected: Int
    let onSelect: (Int) -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive { _SettingsTabBarPrimitive(items: items, selected: selected, onSelect: onSelect) }
}

@MainActor
final class _SettingsTabBarPrimitive: _ControlPrimitive<_SettingsTabBarView> {
    var items: [_SettingsTabBarView.Item]
    var selected: Int
    var onSelect: (Int) -> Void
    init(items: [_SettingsTabBarView.Item], selected: Int, onSelect: @escaping (Int) -> Void) {
        self.items = items; self.selected = selected; self.onSelect = onSelect
        super.init(control: _SettingsTabBarView())
        sync()
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _SettingsTabBarPrimitive else { return }
        items = o.items; selected = o.selected; onSelect = o.onSelect
        sync()
    }
    private func sync() {
        control.onSelect = { [weak self] i in self?.onSelect(i) }
        control.setItems(items, selected: selected)
    }
    /// The band spans the width it is offered, at the toolbar's height.
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? control.contentWidth
        return CGSize(width: width, height: _SettingsTabBarView.height)
    }
}

/// The band of Settings tab items. Accessibility sees a radio group of radio buttons, as
/// for the segmented tab bar elsewhere; the value is the selected tab's title.
@MainActor
final class _SettingsTabBarView: NSView {
    struct Item {
        var title: String
        var image: NSImage?
        func same(as other: Item) -> Bool { title == other.title && image === other.image }
    }
    static let height: CGFloat = 54
    static let itemHeight: CGFloat = 48
    static let spacing: CGFloat = 4
    static let font = NSFont.systemFont(ofSize: 13)

    private(set) var items: [Item] = []
    private(set) var buttons: [_SettingsTabButton] = []
    private(set) var selectedIndex = 0
    var onSelect: (Int) -> Void = { _ in }

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    func setItems(_ newItems: [Item], selected: Int) {
        if newItems.count != items.count || zip(newItems, items).contains(where: { !$0.same(as: $1) }) {
            items = newItems
            for b in buttons { b.removeFromSuperview() }
            buttons = newItems.enumerated().map { i, item in
                let b = _SettingsTabButton(frame: .zero)
                b.setButtonType(.radio)
                b.isBordered = false
                b.title = item.title
                b.image = item.image
                b.imagePosition = .imageAbove
                b.tag = i
                b.target = b
                b.action = Selector(("swiftUISettingsTabAction:"))
                b.setActionHandler(for: Selector(("swiftUISettingsTabAction:"))) { [weak self] sender in
                    guard let self, let b = sender as? NSButton else { return }
                    self.select(b.tag)
                }
                addSubview(b)
                return b
            }
            layoutItems()
        }
        selectedIndex = selected
        syncStates()
        applyWindowTitle()
    }

    /// A click on an item (or the accessibility press): it shows selected at once, and the
    /// owner updates the selection.
    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        syncStates()
        applyWindowTitle()
        onSelect(index)
    }

    private func syncStates() {
        for (i, b) in buttons.enumerated() {
            let on = i == selectedIndex
            if b.state != (on ? .on : .off) { b.state = on ? .on : .off }
            let tint: NSColor = on ? .labelColor : .secondaryLabelColor
            if b.contentTintColor != tint { b.contentTintColor = tint }
        }
        needsDisplay = true
        _accessibilityValueDidChange()
    }

    private func _accessibilityValueDidChange() {
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    /// The items' widths: the label's plus padding, never narrower than a square-ish item.
    private func itemWidths() -> [CGFloat] {
        items.map { item in
            let label = (item.title as NSString).size(withAttributes: [.font: _SettingsTabBarView.font]).width
            return max(48, (label + 16).rounded(.up))
        }
    }
    var contentWidth: CGFloat {
        let w = itemWidths()
        return w.reduce(0, +) + CGFloat(max(0, w.count - 1)) * _SettingsTabBarView.spacing + 16
    }

    private func layoutItems() {
        let widths = itemWidths()
        let total = widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * _SettingsTabBarView.spacing
        var x = max(8, ((bounds.width - total) / 2).rounded())
        let y = ((_SettingsTabBarView.height - 1 - _SettingsTabBarView.itemHeight) / 2).rounded(.down)
        for (b, w) in zip(buttons, widths) {
            b.frame = NSRect(x: x, y: y, width: w, height: _SettingsTabBarView.itemHeight)
            x += w + _SettingsTabBarView.spacing
        }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutItems()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: bounds).fill()
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)).fill()
    }

    /// The window shows the selected tab's title, as macOS's Settings window does.
    private func applyWindowTitle() {
        guard let window, items.indices.contains(selectedIndex), !(window is NSPanel), window.sheetParent == nil else { return }
        let title = items[selectedIndex].title
        if window.title != title { window.title = title }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowTitle()
    }

    override func accessibilityValue() -> Any? {
        items.indices.contains(selectedIndex) ? items[selectedIndex].title : nil
    }
}

/// One Settings tab item: a radio button (for the keyboard, clicks and accessibility) drawn
/// as the symbol over the label, on a rounded fill when selected.
@MainActor
final class _SettingsTabButton: NSButton {
    static let symbolSize: CGFloat = 24
    override var isFlipped: Bool { true }
    override func isAccessibilitySelected() -> Bool { state == .on }

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        let on = state == .on
        if on || isHighlighted {
            (on ? NSColor.unemphasizedSelectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.5)).setFill()
            NSBezierPath(roundedRect: b, xRadius: 6, yRadius: 6).fill()
        }
        let color: NSColor = on ? .labelColor : .secondaryLabelColor
        let side = _SettingsTabButton.symbolSize
        if let image, let cell = cell as? NSButtonCell {
            // Fit the image's aspect into the symbol square, centred over the label.
            let s = image.size
            let scale = s.width > 0 && s.height > 0 ? min(side / s.width, side / s.height) : 1
            let w = (s.width * scale).rounded(), h = (s.height * scale).rounded()
            let r = NSRect(x: (b.midX - w / 2).rounded(), y: 4 + ((side - h) / 2).rounded(), width: w, height: h)
            cell.drawImage(image, withFrame: r, in: self)
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: _SettingsTabBarView.font, .foregroundColor: color]
        let text = title as NSString
        let size = text.size(withAttributes: attrs)
        let top: CGFloat = image == nil ? (b.height - size.height) / 2 : 4 + side + 2
        text.draw(at: NSPoint(x: (b.midX - size.width / 2).rounded(), y: top.rounded()), withAttributes: attrs)
    }
}

/// Shows one box as a view (the page of a tab, the top of a navigation stack).
struct _Page: View, _PrimitiveView {
    typealias Body = Never
    let box: _AnyViewBox
    func _makePrimitive(node: _ViewNode) -> _Primitive { _GroupPrimitive(children: [box]) }
}

// MARK: Picker

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/picker
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View, _PrimitiveView {
    public typealias Body = Never
    let label: Label
    let selection: Binding<SelectionValue>
    let content: Content
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.selection = selection; self.content = content(); self.label = label()
    }
    /// The picker inside its own form row: the row shows the label.
    var _inFormRow = false
    public func _makePrimitive(node: _ViewNode) -> _Primitive {
        let env = node.environment
        let hidden = _inFormRow || env._labelsHidden
        // In a form the label leads the row (grouped) or sits in the label column (columns);
        // radio groups and inline lists put it beside their first item (columns) or above
        // their options (grouped).
        if !hidden, env._formContext != nil, _formHasLabel(label) {
            var inner = self; inner._inFormRow = true
            let stacked = env.pickerStyle == .radioGroup || env.pickerStyle == .inline
            return _GroupPrimitive(children: [_ViewBox(_FormRow(label: AnyView(label), content: AnyView(inner), alignment: stacked ? .top : .center, stacked: stacked))])
        }
        return _PickerPrimitive(label: (label as? Text)?._string ?? _pickerItemFace(_ViewBox(label), environment: env).title, showsLabel: !hidden, selection: AnyBinding(selection), content: _ViewBox(content))
    }
}

extension Picker where Label == Text {
    public init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(title) }
    }
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(titleKey) }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/pickerstyle
public protocol PickerStyle { var _kind: _PickerStyleKind { get } }
public enum _PickerStyleKind: Sendable { case automatic, menu, segmented, inline, radioGroup }
public struct DefaultPickerStyle: PickerStyle { public init() {}; public var _kind: _PickerStyleKind { .automatic } }
public struct MenuPickerStyle: PickerStyle { public init() {}; public var _kind: _PickerStyleKind { .menu } }
public struct SegmentedPickerStyle: PickerStyle { public init() {}; public var _kind: _PickerStyleKind { .segmented } }
public struct InlinePickerStyle: PickerStyle { public init() {}; public var _kind: _PickerStyleKind { .inline } }
public struct RadioGroupPickerStyle: PickerStyle { public init() {}; public var _kind: _PickerStyleKind { .radioGroup } }
extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: DefaultPickerStyle { DefaultPickerStyle() } }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { MenuPickerStyle() } }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { SegmentedPickerStyle() } }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { InlinePickerStyle() } }
extension PickerStyle where Self == RadioGroupPickerStyle { public static var radioGroup: RadioGroupPickerStyle { RadioGroupPickerStyle() } }

extension EnvironmentValues {
    private struct PickerStyleKey: EnvironmentKey { static let defaultValue: _PickerStyleKind = .automatic }
    var pickerStyle: _PickerStyleKind { get { self[PickerStyleKey.self] } set { self[PickerStyleKey.self] = newValue } }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/pickerstyle(_:)
    public func pickerStyle<S: PickerStyle>(_ style: S) -> some View { environment(\.pickerStyle, style._kind) }
}

/// Picker rendering: a labelled pop-up button (menu and automatic styles), a segmented row,
/// or a vertical radio group.
@MainActor
final class _PickerPrimitive: _Primitive {
    var label: String
    /// False under `labelsHidden()` or in a form row that shows the label itself; the label
    /// still names the control for assistive technology.
    var showsLabel: Bool
    var selection: AnyBinding
    var contentBox: _AnyViewBox
    init(label: String, showsLabel: Bool = true, selection: AnyBinding, content: _AnyViewBox) {
        self.label = label; self.showsLabel = showsLabel; self.selection = selection; contentBox = content
        super.init()
    }
    override var isLayoutTransparent: Bool { true }
    override func attach(to node: _ViewNode) { super.attach(to: node); rebuild() }
    override func update(from other: _Primitive) {
        guard let o = other as? _PickerPrimitive else { return }
        label = o.label; showsLabel = o.showsLabel; selection = o.selection; contentBox = o.contentBox
        rebuild()
    }
    private func rebuild() {
        let leaves = _flattenBoxes(contentBox)
        let items = leaves.map { _metadata(of: $0) }
        // An item shows its view: a Text's string, a Label's title and icon (through the
        // modifiers and custom views around it), never a type name.
        let environment = node?.environment ?? EnvironmentValues()
        let faces = items.map { _pickerItemFace($0.content, environment: environment) }
        let titles = faces.map(\.title)
        let current = selection.get()
        // An untagged row of a ForEach is tagged with its id when that is the selection's
        // type, as in SwiftUI; else with its position.
        let tags: [AnyHashable] = items.enumerated().map { i, item in
            if let tag = item.meta.tag { return tag }
            if let id = leaves[i].id, type(of: id.base) == type(of: current.base) { return id }
            return AnyHashable(i)
        }
        // A selection no item carries (a nil optional) selects nothing: the pop-up's title
        // is empty, as on macOS.
        let index = tags.firstIndex(of: current) ?? -1
        let sel = selection
        let style = node?.environment.pickerStyle ?? .automatic
        let labelText = label
        let shownLabel = showsLabel ? label : ""
        let body: AnyView
        if style == .radioGroup || style == .inline {
            body = AnyView(VStack(alignment: .leading, spacing: 4) {
                if !shownLabel.isEmpty { Text(shownLabel) }
                ForEach(Array(titles.enumerated()), id: \.offset) { pair in
                    _RadioRow(title: pair.element, isOn: pair.offset == index) { sel.set(tags[pair.offset]) }
                }
            })
        } else if style == .segmented {
            body = AnyView(HStack(spacing: 8) {
                if !shownLabel.isEmpty { Text(shownLabel) }
                _Segmented(titles: titles, selected: index) { i in sel.set(tags[i]) }._pickerLabel(labelText)
            })
        } else {
            // Menu and automatic styles: a pop-up button, as on macOS.
            body = AnyView(HStack(spacing: 8) {
                if !shownLabel.isEmpty { Text(shownLabel) }
                _PickerPopUp(titles: titles, images: faces.map(\.image), selected: index) { i in sel.set(tags[i]) }._pickerLabel(labelText)
            })
        }
        children = [_ViewBox(body, id: AnyHashable("picker"))]
    }
}

/// What a picker item shows in a menu: its text and its first image, found through the
/// item's view (a `Text`, a `Label`, modifiers and custom views around them, a stack of an
/// image and text). Custom views are evaluated outside the tree with the picker's
/// environment, as the menu has no place for their state.
@MainActor
func _pickerItemFace(_ box: _AnyViewBox, environment: EnvironmentValues = EnvironmentValues()) -> (title: String, image: NSImage?) {
    var texts: [String] = []
    var image: NSImage?
    func walk(_ box: _AnyViewBox, depth: Int) {
        guard depth < 24, image == nil || texts.isEmpty else { return }
        let value = box.value
        if let t = value as? Text { texts.append(t._string); return }
        if let i = value as? Image { if image == nil { image = i.image }; return }
        if let l = value as? _LabelParts {
            for b in l._labelParts { walk(b, depth: depth + 1) }
            return
        }
        if value is any NSViewRepresentable || value is any NSViewControllerRepresentable { return }
        if box.isPrimitive {
            guard let p = box.makePrimitive(node: _ViewNode.placeholder) else { return }
            for c in p.children { walk(c, depth: depth + 1) }
        } else {
            let scratch = _ViewNode(box: box, parent: nil, root: nil)
            scratch.environment = environment
            if let body = box.body(node: scratch) { walk(body, depth: depth + 1) }
        }
    }
    walk(box, depth: 0)
    return (texts.filter { !$0.isEmpty }.joined(separator: " "), image)
}

/// A `Label`'s title and icon views, for a picker item to show them.
protocol _LabelParts { var _labelParts: [_AnyViewBox] { get } }

/// The pop-up of a menu-style picker: `_PopUp` with an image per item (a Label's icon) and
/// no selected item when the selection matches none (`selected` -1). It shrinks to the
/// width it is offered (its title truncates), so a form row never pushes it out of its
/// column.
struct _PickerPopUp: View, _PrimitiveView {
    typealias Body = Never
    let titles: [String]
    let images: [NSImage?]
    let selected: Int
    let onSelect: (Int) -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive { _PickerPopUpPrimitive(titles: titles, images: images, selected: selected, onSelect: onSelect) }
}

@MainActor
final class _PickerPopUpPrimitive: _ControlPrimitive<NSPopUpButton> {
    var titles: [String]
    var images: [NSImage?]
    var selected: Int
    var onSelect: (Int) -> Void
    /// The items are built when the primitive attaches (see `_PopUpPrimitive`).
    init(titles: [String], images: [NSImage?], selected: Int, onSelect: @escaping (Int) -> Void) {
        self.titles = titles; self.images = images; self.selected = selected; self.onSelect = onSelect
        let b = NSPopUpButton(frame: .zero, pullsDown: false)
        super.init(control: b)
        b.target = b
        b.action = Selector(("swiftUIPopUpAction:"))
        b.setActionHandler(for: Selector(("swiftUIPopUpAction:"))) { [weak self] _ in
            guard let self else { return }
            self.selected = self.control.indexOfSelectedItem
            self.onSelect(self.control.indexOfSelectedItem)
        }
    }
    private func rebuildItems() {
        control.removeAllItems()
        control.addItems(withTitles: titles)
        for (i, image) in images.enumerated() { control.item(at: i)?.image = image }
        control.selectItem(at: selected)
        control.sizeToFit()
    }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        if control.numberOfItems != titles.count { rebuildItems() }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _PickerPopUpPrimitive else { return }
        onSelect = o.onSelect
        let imagesChanged = o.images.count != images.count || zip(o.images, images).contains { ($0 == nil) != ($1 == nil) || ($0 !== $1 && $0?.name() != $1?.name()) }
        if o.titles != titles || imagesChanged {
            titles = o.titles; images = o.images; selected = o.selected
            rebuildItems()
        } else if o.selected != selected || control.indexOfSelectedItem != o.selected {
            selected = o.selected
            control.selectItem(at: o.selected)
            control.sizeToFit()
        }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        let s = intrinsicSize
        guard let w = proposal.width, w.isFinite else { return s }
        return CGSize(width: max(min(s.width, w), 44), height: s.height)
    }
}

extension View {
    /// The picker's label names its control for assistive technology (the label text is
    /// still shown beside it).
    @ViewBuilder fileprivate func _pickerLabel(_ label: String) -> some View {
        if label.isEmpty { self } else { accessibilityLabel(label) }
    }
}

struct _RadioRow: View, _PrimitiveView {
    typealias Body = Never
    let title: String
    let isOn: Bool
    let action: () -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive { _RadioPrimitive(title: title, isOn: isOn, action: action) }
}

@MainActor
final class _RadioPrimitive: _ControlPrimitive<NSButton> {
    var action: () -> Void
    init(title: String, isOn: Bool, action: @escaping () -> Void) {
        self.action = action
        let b = NSButton(frame: .zero)
        b.setButtonType(.radio)
        b.title = title
        b.state = isOn ? .on : .off
        super.init(control: b)
        b.target = b
        b.action = Selector(("swiftUIRadio:"))
        b.setActionHandler(for: Selector(("swiftUIRadio:"))) { [weak self] _ in self?.action() }
        b.sizeToFit()
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _RadioPrimitive else { return }
        action = o.action
        control.title = o.control.title
        control.state = o.control.state
        control.sizeToFit()
    }
}

// MARK: NavigationStack

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationpath
public struct NavigationPath: Equatable {
    var elements: [AnyHashable] = []
    public init() {}
    public init<S: Sequence>(_ elements: S) where S.Element: Hashable { self.elements = elements.map { AnyHashable($0) } }
    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }
    public mutating func append<V: Hashable>(_ value: V) { elements.append(AnyHashable(value)) }
    public mutating func removeLast(_ k: Int = 1) { elements.removeLast(min(k, elements.count)) }
}

/// The live state of a stack: the pushed pages, the registered destinations and titles.
@MainActor
final class _NavigationState: ObservableObject {
    struct Page { let value: AnyHashable?; let box: _AnyViewBox; var title: String? }
    @Published var pages: [Page] = []
    var destinations: [ObjectIdentifier: (AnyHashable) -> _AnyViewBox?] = [:]
    var rootTitle: String? = nil
    var path: AnyBinding? = nil
    var pathSetter: (([AnyHashable]) -> Void)? = nil
    nonisolated init() {}

    func push(_ box: _AnyViewBox, value: AnyHashable?) {
        pages.append(Page(value: value, box: box, title: nil))
        pathSetter?(pages.compactMap(\.value))
    }
    func push(value: AnyHashable) {
        guard let make = destinations[ObjectIdentifier(type(of: value.base))], let box = make(value) else { return }
        push(box, value: value)
    }
    func pop() {
        guard !pages.isEmpty else { return }
        pages.removeLast()
        pathSetter?(pages.compactMap(\.value))
    }
    func sync(path: [AnyHashable]) {
        // Rebuild pages only when the external path differs from the valued pages
        // (destination-style links push pages that the path does not represent).
        guard path != pages.compactMap(\.value) else { return }
        var next: [Page] = []
        for v in path {
            if let existing = pages.first(where: { $0.value == v }) { next.append(existing) }
            else if let make = destinations[ObjectIdentifier(type(of: v.base))], let box = make(v) { next.append(Page(value: v, box: box, title: nil)) }
        }
        pages = next
    }
    var title: String? { pages.last?.title ?? (pages.isEmpty ? rootTitle : nil) }
}

extension EnvironmentValues {
    private struct NavigationKey: EnvironmentKey { static let defaultValue: _NavigationState? = nil }
    var _navigation: _NavigationState? { get { self[NavigationKey.self] } set { self[NavigationKey.self] = newValue } }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationstack
public struct NavigationStack<Data, Root: View>: View {
    let root: Root
    let path: AnyBinding?
    let pathElements: (() -> [AnyHashable])?
    let setPath: (([AnyHashable]) -> Void)?
    @StateObject private var state = _NavigationState()

    public init(@ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root(); path = nil; pathElements = nil; setPath = nil
    }
    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
        self.root = root(); self.path = nil
        pathElements = { path.wrappedValue.elements }
        setPath = { var p = NavigationPath(); p.elements = $0; path.wrappedValue = p }
    }
    public init<E: Hashable>(path: Binding<[E]>, @ViewBuilder root: () -> Root) where Data == [E] {
        self.root = root(); self.path = nil
        pathElements = { path.wrappedValue.map { AnyHashable($0) } }
        setPath = { path.wrappedValue = $0.compactMap { $0.base as? E } }
    }

    public var body: some View {
        _NavigationStackBody(state: state, root: AnyView(root), pathElements: pathElements, setPath: setPath)
    }
}

struct _NavigationStackBody: View {
    @ObservedObject var state: _NavigationState
    let root: AnyView
    let pathElements: (() -> [AnyHashable])?
    let setPath: (([AnyHashable]) -> Void)?

    var body: some View {
        state.pathSetter = setPath
        if let elements = pathElements?() { state.sync(path: elements) }
        return VStack(spacing: 0) {
            // The bar (back button and title) belongs to pushed pages; at the root the
            // title goes to the window's title bar, as on macOS, with no row in the content.
            if !state.pages.isEmpty {
                HStack(spacing: 8) {
                    if !state.pages.isEmpty {
                        Button("‹ Back") { withAnimation(.easeOut(duration: 0.25)) { state.pop() } }.buttonStyle(.borderless)
                    }
                    if let t = state.title { Text(t).font(.headline) }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
            }
            ZStack {
                if let top = state.pages.last {
                    _Page(box: top.box).id(AnyHashable(state.pages.count)).transition(.push(from: .trailing))
                } else {
                    root.id(AnyHashable(0)).transition(.push(from: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .environment(\._navigation, state)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationlink
public struct NavigationLink<Label: View, Destination: View>: View {
    let label: Label
    let destination: Destination?
    let value: AnyHashable?
    @Environment(\._navigation) private var navigation

    public init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination; self.label = label(); value = nil
    }
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination(); self.label = label(); value = nil
    }
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) where Destination == Never {
        self.label = label(); destination = nil; self.value = value.map { AnyHashable($0) }
    }

    public var body: some View {
        let nav = navigation
        let dest = destination
        let v = value
        return Button(action: {
            withAnimation(.easeOut(duration: 0.25)) {
                if let d = dest { nav?.push(_ViewBox(d), value: nil) } else if let v { nav?.push(value: v) }
            }
        }) { label }
        .buttonStyle(.link)
    }
}

extension NavigationLink where Label == Text {
    public init(_ title: String, destination: Destination) { self.init(destination: destination) { Text(title) } }
    public init(_ title: String, @ViewBuilder destination: () -> Destination) { self.init(destination: destination) { Text(title) } }
    public init<P: Hashable>(_ title: String, value: P?) where Destination == Never { self.init(value: value) { Text(title) } }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)
    public func navigationDestination<D: Hashable, C: View>(for data: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> some View {
        _NavigationDestination(content: self, type: ObjectIdentifier(D.self)) { any in (any.base as? D).map { _ViewBox(destination($0)) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationtitle(_:)-43srq
    public func navigationTitle(_ title: String) -> some View { _NavigationTitle(content: self, title: title) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationtitle(_:)-5di1u
    public func navigationTitle(_ title: Text) -> some View { _NavigationTitle(content: self, title: title._string) }
}

struct _NavigationDestination<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let type: ObjectIdentifier
    let make: (AnyHashable) -> _AnyViewBox?
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        if let nav = node.environment._navigation { nav.destinations[type] = make }
        return _GroupPrimitive(children: [_ViewBox(content)])
    }
}

struct _NavigationTitle<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let title: String
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        if let nav = node.environment._navigation {
            if nav.pages.isEmpty { if nav.rootTitle != title { nav.rootTitle = title; nav.objectWillChange.send() } }
            else if nav.pages[nav.pages.count - 1].title != title { nav.pages[nav.pages.count - 1].title = title }
        }
        // The window shows the navigation title, as macOS does for a WindowGroup's content.
        if let window = node.root?.host?.hostView.window, !(window is NSPanel), window.sheetParent == nil {
            if window.title != title { window.title = title }
            // An app with no bundle name (a bare executable) takes its main window's title
            // as its name too, so the app menu and the window agree.
            if let runner = _AppRunner._current, runner.windows.first === window { runner._adoptName(title) }
        }
        return _GroupPrimitive(children: [_ViewBox(content)])
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/navigationview
public struct NavigationView<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { NavigationStack { content } }
}

// MARK: Sheets

/// Presented content (a sheet, a popover) inherits the presenting view's environment, as on
/// macOS: its environment objects, fonts, tints and custom keys. The values the new host's
/// root sets from its own window (appearance, scale, activity, direction, locale) are kept.
@MainActor
func _presented(_ content: AnyView, from node: _ViewNode?) -> AnyView {
    guard let inherited = node?.environment else { return content }
    return AnyView(_EnvironmentView(content: content) { env in
        var e = inherited
        e.colorScheme = env.colorScheme
        e.displayScale = env.displayScale
        e.layoutDirection = env.layoutDirection
        e.locale = env.locale
        e.controlActiveState = env.controlActiveState
        env = e
    })
}

@MainActor
final class _SheetPrimitive: _Primitive {
    var isPresented: Binding<Bool>
    var make: () -> AnyView
    var onDismiss: (() -> Void)?
    private var window: NSWindow?
    private weak var parentWindow: NSWindow?

    init(isPresented: Binding<Bool>, onDismiss: (() -> Void)?, make: @escaping () -> AnyView, content: _AnyViewBox) {
        self.isPresented = isPresented; self.onDismiss = onDismiss; self.make = make
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func attach(to node: _ViewNode) { super.attach(to: node); sync() }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _SheetPrimitive else { return }
        isPresented = o.isPresented; make = o.make; onDismiss = o.onDismiss
        sync()
    }
    override func detach() { close(notify: false) }

    private func sync() {
        if isPresented.wrappedValue { if window == nil { present() } } else if window != nil { close(notify: true) }
    }

    private func present() {
        guard let host = node?.root?.host?.hostWindow else { return }
        parentWindow = host
        let dismiss = DismissAction { [weak self] in self?.isPresented.wrappedValue = false }
        let content = _presented(AnyView(make().environment(\.dismiss, dismiss)), from: node)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.sizeThatFits(.unspecified)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(size.width, 200), height: max(size.height, 120)), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        hosting.frame = w.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        w.contentView = hosting
        w._cancelsSheetOnEscape = true          // Escape dismisses a SwiftUI sheet, as on macOS
        w._closesAfterSheetEnds = true          // nothing keeps the window once it is dismissed
        window = w
        host.beginSheet(w) { [weak self] _ in
            guard let self, self.window === w else { return }
            self.window = nil
            if self.isPresented.wrappedValue { self.isPresented.wrappedValue = false }
            self.onDismiss?()
        }
    }

    private func close(notify: Bool) {
        guard let w = window else { return }
        window = nil
        if let p = parentWindow, p.sheets.contains(where: { $0 === w }) {
            p.endSheet(w)
        } else {
            w.close()
        }
        if notify { onDismiss?() }
    }
}

struct _SheetModified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let make: () -> AnyView
    func _makePrimitive(node: _ViewNode) -> _Primitive { _SheetPrimitive(isPresented: isPresented, onDismiss: onDismiss, make: make, content: _ViewBox(content)) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)
    public func sheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        _SheetModified(content: self, isPresented: isPresented, onDismiss: onDismiss, make: { AnyView(content()) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/sheet(item:ondismiss:content:)
    public func sheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        let presented = Binding<Bool>(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
        return _SheetModified(content: self, isPresented: presented, onDismiss: onDismiss, make: { item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView()) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)
    public func popover<Content: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> Content) -> some View {
        _PopoverModified(content: self, isPresented: isPresented, anchor: attachmentAnchor, arrowEdge: arrowEdge, make: { AnyView(content()) })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/popover(item:attachmentanchor:arrowedge:content:)
    public func popover<Item: Identifiable, Content: View>(item: Binding<Item?>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge = .top, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        let presented = Binding<Bool>(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
        return _PopoverModified(content: self, isPresented: presented, anchor: attachmentAnchor, arrowEdge: arrowEdge, make: { item.wrappedValue.map { AnyView(content($0)) } ?? AnyView(EmptyView()) })
    }
}

// MARK: Popovers

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/popoverattachmentanchor
public enum PopoverAttachmentAnchor {
    case rect(Anchor<CGRect>.Source)
    case point(UnitPoint)
}

/// Presents an `NSPopover` holding the content, anchored on the modified view's frame in
/// the hosting view, with the arrow on `arrowEdge` of the popover (so `.top` puts the
/// popover below the view). Transient: a click outside closes it and clears the binding.
@MainActor
final class _PopoverPrimitive: _Primitive {
    var isPresented: Binding<Bool>
    var anchor: PopoverAttachmentAnchor
    var arrowEdge: Edge
    var make: () -> AnyView
    private var popover: NSPopover?
    private var observer: Any?

    init(isPresented: Binding<Bool>, anchor: PopoverAttachmentAnchor, arrowEdge: Edge, make: @escaping () -> AnyView, content: _AnyViewBox) {
        self.isPresented = isPresented; self.anchor = anchor; self.arrowEdge = arrowEdge; self.make = make
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func attach(to node: _ViewNode) { super.attach(to: node); sync() }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _PopoverPrimitive else { return }
        isPresented = o.isPresented; anchor = o.anchor; arrowEdge = o.arrowEdge; make = o.make
        sync()
    }
    override func detach() { close() }

    private func sync() {
        if isPresented.wrappedValue { if popover == nil { present() } } else if popover != nil { close() }
    }

    /// The modified view's frame in the host view: the node is layout-transparent, so its
    /// leaf (the content) carries the frame.
    private var anchorFrame: CGRect? {
        guard let node else { return nil }
        let leaves = node.layoutLeaves
        guard let first = leaves.first(where: { $0.hasLaidOut }) else { return node.hasLaidOut ? node.frame : nil }
        return leaves.filter { $0.hasLaidOut }.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    private func present() {
        guard let node, let host = node.root?.host?.hostView, host.window != nil, let frame = anchorFrame else { return }
        let rect: CGRect
        switch anchor {
        case .rect(let source): rect = source.resolve(frame)
        case .point(let p): rect = CGRect(x: frame.minX + frame.width * p.x, y: frame.minY + frame.height * p.y, width: 1, height: 1)
        }
        // The host view is flipped: its maxY edge is the bottom.
        let rtl = node.environment.layoutDirection == .rightToLeft
        let edge: NSRectEdge
        switch arrowEdge {
        case .top: edge = .maxY
        case .bottom: edge = .minY
        case .leading: edge = rtl ? .minX : .maxX
        case .trailing: edge = rtl ? .maxX : .minX
        }
        let dismiss = DismissAction { [weak self] in self?.isPresented.wrappedValue = false }
        let content = _presented(AnyView(make().environment(\.dismiss, dismiss)), from: node)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.sizeThatFits(.unspecified)
        hosting.frame = NSRect(x: 0, y: 0, width: max(size.width.rounded(.up), 40), height: max(size.height.rounded(.up), 20))
        let vc = NSViewController(nibName: nil, bundle: nil)
        vc.view = hosting
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = vc
        popover = p
        observer = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: p, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.popover === p else { return }
                self.popover = nil
                if self.isPresented.wrappedValue { self.isPresented.wrappedValue = false }
            }
        }
        p.show(relativeTo: rect, of: host, preferredEdge: edge)
    }

    private func close() {
        guard let p = popover else { return }
        popover = nil
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        p.close()
    }
}

struct _PopoverModified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let isPresented: Binding<Bool>
    let anchor: PopoverAttachmentAnchor
    let arrowEdge: Edge
    let make: () -> AnyView
    func _makePrimitive(node: _ViewNode) -> _Primitive { _PopoverPrimitive(isPresented: isPresented, anchor: anchor, arrowEdge: arrowEdge, make: make, content: _ViewBox(content)) }
}

// MARK: Alerts

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/alert
public struct Alert {
    public struct Button {
        let title: String
        let action: (() -> Void)?
        let role: ButtonRole?
        public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Button { Button(title: label._string, action: action, role: nil) }
        public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Button { Button(title: label._string, action: action, role: .cancel) }
        public static func cancel(_ action: (() -> Void)? = {}) -> Button { Button(title: "Cancel", action: action, role: .cancel) }
        public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Button { Button(title: label._string, action: action, role: .destructive) }
    }
    let title: Text
    let message: Text?
    let buttons: [Button]
    public init(title: Text, message: Text? = nil, dismissButton: Button? = nil) {
        self.title = title; self.message = message; buttons = [dismissButton ?? .default(Text("OK"))]
    }
    public init(title: Text, message: Text? = nil, primaryButton: Button, secondaryButton: Button) {
        self.title = title; self.message = message; buttons = [primaryButton, secondaryButton]
    }
}

@MainActor
final class _AlertPrimitive: _Primitive {
    var isPresented: Binding<Bool>
    var make: @MainActor () -> Alert
    private var showing = false
    private var current: NSAlert?     // kept alive while shown: the panel's buttons target it

    init(isPresented: Binding<Bool>, make: @escaping @MainActor () -> Alert, content: _AnyViewBox) {
        self.isPresented = isPresented; self.make = make
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func attach(to node: _ViewNode) { super.attach(to: node); sync() }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _AlertPrimitive else { return }
        isPresented = o.isPresented; make = o.make
        sync()
    }
    private func sync() {
        guard isPresented.wrappedValue, !showing else { return }
        showing = true
        let alert = make()
        let ns = NSAlert()
        current = ns
        ns.messageText = alert.title._string
        ns.informativeText = alert.message?._string ?? ""
        // As SwiftUI does on macOS: the cancel role takes Escape, and a destructive role
        // draws red and is never the default (Return) button.
        for b in alert.buttons {
            let button = ns.addButton(withTitle: b.title)
            switch b.role {
            case .cancel?: button.keyEquivalent = "\u{1B}"
            case .destructive?: button.keyEquivalent = ""; button.hasDestructiveAction = true
            default: break
            }
        }
        let buttons = alert.buttons
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.showing = false
            self.current = nil
            self.isPresented.wrappedValue = false
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if buttons.indices.contains(index) { buttons[index].action?() }
        }
        if let w = node?.root?.host?.hostWindow { ns.beginSheetModal(for: w, completionHandler: finish) } else { finish(ns.runModal()) }
    }
}

struct _AlertModified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let isPresented: Binding<Bool>
    let make: @MainActor () -> Alert
    func _makePrimitive(node: _ViewNode) -> _Primitive { _AlertPrimitive(isPresented: isPresented, make: make, content: _ViewBox(content)) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/alert(ispresented:content:)
    public func alert(isPresented: Binding<Bool>, content: @escaping () -> Alert) -> some View {
        _AlertModified(content: self, isPresented: isPresented, make: content)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:)-6awwp
    public func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A, @ViewBuilder message: @escaping () -> M) -> some View {
        _AlertModified(content: self, isPresented: isPresented) {
            Alert._fromViews(title: Text(title), actions: AnyView(actions()), message: (message() as? Text))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:)-3npqg
    public func alert<A: View>(_ title: String, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> A) -> some View {
        _AlertModified(content: self, isPresented: isPresented) { Alert._fromViews(title: Text(title), actions: AnyView(actions()), message: nil) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:)
    public func confirmationDialog<A: View>(_ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: @escaping () -> A) -> some View {
        _AlertModified(content: self, isPresented: isPresented) {
            Alert._fromViews(title: Text(title), actions: AnyView(actions()), message: nil)._confirmationDialog
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/visibility
public enum Visibility: Hashable, CaseIterable, Sendable { case automatic, visible, hidden }

extension Alert {
    /// Buttons from an `actions` view builder: each `Button` with a text label is one alert button.
    @MainActor static func _fromViews(title: Text, actions: AnyView, message: Text?) -> Alert {
        var buttons: [Button] = []
        for box in _flattenBoxes(actions.box) {
            if let b = box.value as? any _AlertButtonSource { buttons.append(b._alertButton) }
        }
        if buttons.isEmpty { buttons = [.default(Text("OK"))] }
        var a = Alert(title: title, message: message)
        a = Alert(title: title, message: message, buttons: buttons)
        return a
    }
    /// A confirmation dialog always offers Cancel: SwiftUI adds one (last) when no action
    /// has the cancel role.
    var _confirmationDialog: Alert {
        guard !buttons.contains(where: { $0.role == .cancel }) else { return self }
        return Alert(title: title, message: message, buttons: buttons + [.cancel()])
    }
    init(title: Text, message: Text?, buttons: [Button]) { self.title = title; self.message = message; self.buttons = buttons }
}

protocol _AlertButtonSource { var _alertButton: Alert.Button { get } }
extension SwiftUI.Button: _AlertButtonSource {
    var _alertButton: Alert.Button { Alert.Button(title: (label as? Text)?._string ?? "OK", action: action, role: role) }
}
