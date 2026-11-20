// The macOS 15 tab content API: `Tab`, `TabContent`, `TabContentBuilder` and the `TabView`
// initialisers that take them. Each `Tab` becomes a page of the existing TabView (a tagged
// page with a tab item), so selection, the tab bar and page identity work as they do for
// `.tabItem`/`.tag` content.

import Foundation

// MARK: Entries

/// One tab as the tab view sees it: its selection value, its title and icon, and its page.
public struct _TabEntry {
    let tag: AnyHashable?
    let title: Text
    let icon: Image?
    let content: AnyView

    /// The page as the TabView's metadata views (`.tabItem` and `.tag`) carry it.
    @MainActor var box: _AnyViewBox {
        let label = SwiftUI.Label(title: { title }, icon: { icon ?? Image(systemName: "") })
        let item = _TabItem(content: content, label: label)
        if let tag { return _ViewBox(_Tagged(content: item, tag: tag)) }
        return _ViewBox(item)
    }
}

// MARK: TabContent

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabcontent
@MainActor @preconcurrency
public protocol TabContent<TabValue> {
    associatedtype TabValue: Hashable where TabValue == Body.TabValue
    associatedtype Body: TabContent
    @TabContentBuilder<TabValue> @MainActor @preconcurrency var body: Body { get }
    /// The tabs this content contributes, in order. Built-in tab content answers directly;
    /// a custom type answers through its `body`.
    func _tabEntries() -> [_TabEntry]
}

extension TabContent {
    public func _tabEntries() -> [_TabEntry] { body._tabEntries() }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabrole
public struct TabRole: Hashable, Sendable {
    let kind: Int
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabrole/search
    public static let search = TabRole(kind: 0)
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/defaulttablabel
public struct DefaultTabLabel: View {
    let title: Text
    let icon: Image?
    public var body: some View {
        if let icon { SwiftUI.Label(title: { title }, icon: { icon }) } else { title }
    }
}

// MARK: Tab

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tab
///
/// A tab of a `TabView`: the tab bar shows its title (the port's tab bar is a segmented
/// control, so the icon is not drawn there; in a Settings window the bar shows the icon
/// above the title, as macOS does) and its content is the page shown while it is selected. A `role` is accepted and ignored: the
/// search role's special placement belongs to iPadOS and tvOS tab bars.
public struct Tab<Value, Content, Label> {
    let value: Value?
    let content: Content
    let label: Label
    let role: TabRole?
    init(_value: Value?, _content: Content, _label: Label, _role: TabRole?) {
        value = _value; content = _content; label = _label; role = _role
    }
}

extension Tab: TabContent where Value: Hashable, Content: View, Label: View {
    public typealias TabValue = Value
    public typealias Body = Tab<Value, Content, Label>
    public var body: Tab<Value, Content, Label> { self }

    public func _tabEntries() -> [_TabEntry] {
        let title: Text, icon: Image?
        if let d = label as? DefaultTabLabel { title = d.title; icon = d.icon }
        else if let t = label as? Text { title = t; icon = nil }
        else if let l = label as? SwiftUI.Label<Text, Image> { title = l.title; icon = l.icon }
        else { title = Text(verbatim: ""); icon = nil }
        return [_TabEntry(tag: value.map { AnyHashable($0) }, title: title, icon: icon, content: AnyView(content))]
    }

    // Title and image.
    public init<S: StringProtocol>(_ title: S, image: String, value: Value, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(image)), _role: nil)
    }
    public init<S: StringProtocol>(_ title: S, image: String, value: Value, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(image)), _role: role)
    }
    public init<S: StringProtocol, T: Hashable>(_ title: S, image: String, value: T, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(image)), _role: nil)
    }
    public init<S: StringProtocol, T: Hashable>(_ title: S, image: String, value: T, role: TabRole?, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(image)), _role: role)
    }
    public init(_ titleKey: LocalizedStringKey, image: String, value: Value, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(image)), _role: nil)
    }
    public init(_ titleKey: LocalizedStringKey, image: String, value: Value, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(image)), _role: role)
    }
    public init<T: Hashable>(_ titleKey: LocalizedStringKey, image: String, value: T, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(image)), _role: nil)
    }
    public init<T: Hashable>(_ titleKey: LocalizedStringKey, image: String, value: T, role: TabRole?, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(image)), _role: role)
    }

    // Title and system image.
    public init<S: StringProtocol>(_ title: S, systemImage: String, value: Value, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(systemName: systemImage)), _role: nil)
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, value: Value, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(systemName: systemImage)), _role: role)
    }
    public init<S: StringProtocol, T: Hashable>(_ title: S, systemImage: String, value: T, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(systemName: systemImage)), _role: nil)
    }
    public init<S: StringProtocol, T: Hashable>(_ title: S, systemImage: String, value: T, role: TabRole?, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(systemName: systemImage)), _role: role)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(systemName: systemImage)), _role: nil)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage: String, value: Value, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(systemName: systemImage)), _role: role)
    }
    public init<T: Hashable>(_ titleKey: LocalizedStringKey, systemImage: String, value: T, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(systemName: systemImage)), _role: nil)
    }
    public init<T: Hashable>(_ titleKey: LocalizedStringKey, systemImage: String, value: T, role: TabRole?, @ViewBuilder content: () -> Content) where Value == T?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(systemName: systemImage)), _role: role)
    }

    // Value only, or a custom label.
    public init(value: Value, @ViewBuilder content: () -> Content) where Label == EmptyView {
        self.init(_value: value, _content: content(), _label: EmptyView(), _role: nil)
    }
    public init<V: Hashable>(value: V, @ViewBuilder content: () -> Content) where Value == V?, Label == EmptyView {
        self.init(_value: .some(value), _content: content(), _label: EmptyView(), _role: nil)
    }
    public init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: value, _content: content(), _label: DefaultTabLabel(title: Text(verbatim: ""), icon: nil), _role: role)
    }
    public init<V: Hashable>(value: V, role: TabRole?, @ViewBuilder content: () -> Content) where Value == V?, Label == DefaultTabLabel {
        self.init(_value: .some(value), _content: content(), _label: DefaultTabLabel(title: Text(verbatim: ""), icon: nil), _role: role)
    }
    public init(value: Value, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(_value: value, _content: content(), _label: label(), _role: nil)
    }
    public init(value: Value, role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(_value: value, _content: content(), _label: label(), _role: role)
    }
    public init<V: Hashable>(value: V, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) where Value == V? {
        self.init(_value: .some(value), _content: content(), _label: label(), _role: nil)
    }
    public init<V: Hashable>(value: V, role: TabRole?, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) where Value == V? {
        self.init(_value: .some(value), _content: content(), _label: label(), _role: role)
    }
}

extension Tab where Value == Never, Content: View, Label: View {
    public init<S: StringProtocol>(_ title: S, image: String, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: nil, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(image)), _role: nil)
    }
    public init<S: StringProtocol>(_ title: S, image: String, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: nil, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(image)), _role: role)
    }
    public init(_ titleKey: LocalizedStringKey, image: String, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: nil, _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(image)), _role: nil)
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: nil, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(systemName: systemImage)), _role: nil)
    }
    public init<S: StringProtocol>(_ title: S, systemImage: String, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: nil, _content: content(), _label: DefaultTabLabel(title: Text(title), icon: Image(systemName: systemImage)), _role: role)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: nil, _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(systemName: systemImage)), _role: nil)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: TabRole?, @ViewBuilder content: () -> Content) where Label == DefaultTabLabel {
        self.init(_value: nil, _content: content(), _label: DefaultTabLabel(title: Text(titleKey), icon: Image(systemName: systemImage)), _role: role)
    }
    public init(@ViewBuilder content: () -> Content) where Label == EmptyView {
        self.init(_value: nil, _content: content(), _label: EmptyView(), _role: nil)
    }
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.init(_value: nil, _content: content(), _label: label(), _role: nil)
    }
}

// MARK: Erasure and structure

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/anytabcontent
public struct AnyTabContent<SelectionValue: Hashable>: TabContent {
    public typealias TabValue = SelectionValue
    public typealias Body = AnyTabContent<SelectionValue>
    let entries: @MainActor () -> [_TabEntry]
    public init<T: TabContent>(_ tabContent: T) where SelectionValue == T.TabValue { entries = { tabContent._tabEntries() } }
    public var body: AnyTabContent<SelectionValue> { self }
    public func _tabEntries() -> [_TabEntry] { entries() }
}

/// The tabs of a builder block, in order.
public struct _TabContentGroup<TabValue: Hashable>: TabContent {
    public typealias Body = _TabContentGroup<TabValue>
    let parts: [@MainActor () -> [_TabEntry]]
    public var body: _TabContentGroup<TabValue> { self }
    public func _tabEntries() -> [_TabEntry] { parts.flatMap { $0() } }
}

/// The tabs of whichever branch an `if`/`else` or `switch` took.
public struct _ConditionalTabContent<TrueContent: TabContent, FalseContent: TabContent>: TabContent where TrueContent.TabValue == FalseContent.TabValue {
    public typealias TabValue = TrueContent.TabValue
    public typealias Body = _ConditionalTabContent<TrueContent, FalseContent>
    enum Storage { case first(TrueContent), second(FalseContent) }
    let storage: Storage
    public var body: _ConditionalTabContent<TrueContent, FalseContent> { self }
    public func _tabEntries() -> [_TabEntry] {
        switch storage {
        case .first(let c): return c._tabEntries()
        case .second(let c): return c._tabEntries()
        }
    }
}

/// The tabs of an `if` without `else`: none when the condition is false.
public struct _OptionalTabContent<Wrapped: TabContent>: TabContent {
    public typealias TabValue = Wrapped.TabValue
    public typealias Body = _OptionalTabContent<Wrapped>
    let wrapped: Wrapped?
    public var body: _OptionalTabContent<Wrapped> { self }
    public func _tabEntries() -> [_TabEntry] { wrapped?._tabEntries() ?? [] }
}

/// The tabs of a `for` loop in a builder.
public struct _ArrayTabContent<Element: TabContent>: TabContent {
    public typealias TabValue = Element.TabValue
    public typealias Body = _ArrayTabContent<Element>
    let elements: [Element]
    public var body: _ArrayTabContent<Element> { self }
    public func _tabEntries() -> [_TabEntry] { elements.flatMap { $0._tabEntries() } }
}

// MARK: Builder

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabcontentbuilder
@resultBuilder
public struct TabContentBuilder<TabValue: Hashable> {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabcontentbuilder/content
    ///
    /// The tabs as the content of a `TabView`: each becomes one tagged page with its tab item.
    public struct Content<C: TabContent>: View, _PrimitiveView {
        public typealias Body = Never
        let content: C
        public func _makePrimitive(node: _ViewNode) -> _Primitive {
            _GroupPrimitive(children: content._tabEntries().map(\.box))
        }
    }

    public static func buildExpression<C: TabContent>(_ content: C) -> C where C.TabValue == TabValue { content }
    public static func buildBlock<C: TabContent>(_ content: C) -> C where C.TabValue == TabValue { content }
    public static func buildBlock<C0: TabContent, C1: TabContent>(_ c0: C0, _ c1: C1) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue, C3.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }, { c3._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue, C3.TabValue == TabValue, C4.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }, { c3._tabEntries() }, { c4._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue, C3.TabValue == TabValue, C4.TabValue == TabValue, C5.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }, { c3._tabEntries() }, { c4._tabEntries() }, { c5._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue, C3.TabValue == TabValue, C4.TabValue == TabValue, C5.TabValue == TabValue, C6.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }, { c3._tabEntries() }, { c4._tabEntries() }, { c5._tabEntries() }, { c6._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent, C7: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue, C3.TabValue == TabValue, C4.TabValue == TabValue, C5.TabValue == TabValue, C6.TabValue == TabValue, C7.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }, { c3._tabEntries() }, { c4._tabEntries() }, { c5._tabEntries() }, { c6._tabEntries() }, { c7._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent, C7: TabContent, C8: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue, C3.TabValue == TabValue, C4.TabValue == TabValue, C5.TabValue == TabValue, C6.TabValue == TabValue, C7.TabValue == TabValue, C8.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }, { c3._tabEntries() }, { c4._tabEntries() }, { c5._tabEntries() }, { c6._tabEntries() }, { c7._tabEntries() }, { c8._tabEntries() }])
    }
    public static func buildBlock<C0: TabContent, C1: TabContent, C2: TabContent, C3: TabContent, C4: TabContent, C5: TabContent, C6: TabContent, C7: TabContent, C8: TabContent, C9: TabContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> _TabContentGroup<TabValue> where C0.TabValue == TabValue, C1.TabValue == TabValue, C2.TabValue == TabValue, C3.TabValue == TabValue, C4.TabValue == TabValue, C5.TabValue == TabValue, C6.TabValue == TabValue, C7.TabValue == TabValue, C8.TabValue == TabValue, C9.TabValue == TabValue {
        _TabContentGroup(parts: [{ c0._tabEntries() }, { c1._tabEntries() }, { c2._tabEntries() }, { c3._tabEntries() }, { c4._tabEntries() }, { c5._tabEntries() }, { c6._tabEntries() }, { c7._tabEntries() }, { c8._tabEntries() }, { c9._tabEntries() }])
    }
    public static func buildIf<C: TabContent>(_ content: C?) -> _OptionalTabContent<C> where C.TabValue == TabValue { _OptionalTabContent(wrapped: content) }
    public static func buildOptional<C: TabContent>(_ content: C?) -> _OptionalTabContent<C> where C.TabValue == TabValue { _OptionalTabContent(wrapped: content) }
    public static func buildEither<T: TabContent, F: TabContent>(first: T) -> _ConditionalTabContent<T, F> where T.TabValue == TabValue, F.TabValue == TabValue {
        _ConditionalTabContent(storage: .first(first))
    }
    public static func buildEither<T: TabContent, F: TabContent>(second: F) -> _ConditionalTabContent<T, F> where T.TabValue == TabValue, F.TabValue == TabValue {
        _ConditionalTabContent(storage: .second(second))
    }
    public static func buildArray<C: TabContent>(_ components: [C]) -> _ArrayTabContent<C> where C.TabValue == TabValue { _ArrayTabContent(elements: components) }
    public static func buildLimitedAvailability<T: TabContent>(_ content: T) -> AnyTabContent<T.TabValue> { AnyTabContent(content) }
}

// MARK: TabView

extension TabView {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabview/init(selection:content:)
    public init<C: TabContent>(selection: Binding<SelectionValue>, @TabContentBuilder<SelectionValue> content: () -> C) where Content == TabContentBuilder<SelectionValue>.Content<C> {
        self.init(selection: selection) { TabContentBuilder<SelectionValue>.Content(content: content()) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/tabview/init(content:)
    public init<C: TabContent>(@TabContentBuilder<Never> content: () -> C) where SelectionValue == Never, Content == TabContentBuilder<Never>.Content<C> {
        self.init(selection: nil) { TabContentBuilder<Never>.Content(content: content()) }
    }
}
