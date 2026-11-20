// Form members a real third-party app (Examples/DailyTodo) found missing: LabeledContent and
// its styles, FormStyle with the grouped and columns styles, and ContentUnavailableView.

import Foundation

// MARK: LabeledContent

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/labeledcontentstyleconfiguration
public struct LabeledContentStyleConfiguration {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/labeledcontentstyleconfiguration/label
    public struct Label: View {
        let content: AnyView
        public var body: some View { content }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/labeledcontentstyleconfiguration/content
    public struct Content: View {
        let content: AnyView
        public var body: some View { content }
    }
    public let label: Label
    public let content: Content
    /// The content is text (the `value:` initialisers, or a `Text`): the automatic style
    /// shows it in the secondary colour, as AppKit's forms show a read-only value. Controls
    /// (a slider, a toggle) keep their own look.
    let _isTextValue: Bool
    init(label: AnyView, content: AnyView, isTextValue: Bool = false) {
        self.label = Label(content: label); self.content = Content(content: content); _isTextValue = isTextValue
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/labeledcontentstyle
@MainActor @preconcurrency
public protocol LabeledContentStyle {
    associatedtype Body: View
    typealias Configuration = LabeledContentStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

/// The label leading and the content trailing (text content in the secondary colour, as
/// AppKit's forms show a read-only value); in a columns form the label sits in the form's
/// trailing-aligned label column and the content leads the control column.
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/automaticlabeledcontentstyle
public struct AutomaticLabeledContentStyle: LabeledContentStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _FormRow(label: AnyView(configuration.label),
                 content: configuration._isTextValue ? AnyView(configuration.content.foregroundStyle(Color.secondary)) : AnyView(configuration.content),
                 alignment: .firstTextBaseline)
    }
}
extension LabeledContentStyle where Self == AutomaticLabeledContentStyle { public static var automatic: AutomaticLabeledContentStyle { AutomaticLabeledContentStyle() } }

extension EnvironmentValues {
    private struct LabeledContentStyleKey: EnvironmentKey { static let defaultValue: any LabeledContentStyle = AutomaticLabeledContentStyle() }
    var _labeledContentStyle: any LabeledContentStyle { get { self[LabeledContentStyleKey.self] } set { self[LabeledContentStyleKey.self] = newValue } }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/labeledcontentstyle(_:)
    public func labeledContentStyle<S: LabeledContentStyle>(_ style: S) -> some View { environment(\._labeledContentStyle, style) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/labeledcontent
public struct LabeledContent<Label: View, Content: View>: View {
    let label: Label
    let content: Content
    @Environment(\._labeledContentStyle) private var style
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) { self.content = content(); self.label = label() }
    public var body: some View {
        AnyView(style.makeBody(configuration: LabeledContentStyleConfiguration(label: AnyView(label), content: AnyView(content), isTextValue: content is Text)))
    }
}

extension LabeledContent where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(titleKey) }) }
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(title) }) }
}

extension LabeledContent where Label == Text, Content == Text {
    public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S) { self.init(content: { Text(value) }, label: { Text(titleKey) }) }
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) { self.init(content: { Text(value) }, label: { Text(title) }) }
    public init<F: FormatStyle>(_ titleKey: LocalizedStringKey, value: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(content: { Text(format.format(value)) }, label: { Text(titleKey) })
    }
    public init<S: StringProtocol, F: FormatStyle>(_ title: S, value: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(content: { Text(format.format(value)) }, label: { Text(title) })
    }
}

// MARK: FormStyle

public enum _FormStyleKind: Sendable { case automatic, columns, grouped }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/formstyle
public protocol FormStyle { var kind: _FormStyleKind { get } }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/automaticformstyle
public struct AutomaticFormStyle: FormStyle { public init() {}; public var kind: _FormStyleKind { .automatic } }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/columnsformstyle
public struct ColumnsFormStyle: FormStyle { public init() {}; public var kind: _FormStyleKind { .columns } }
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/groupedformstyle
public struct GroupedFormStyle: FormStyle { public init() {}; public var kind: _FormStyleKind { .grouped } }
extension FormStyle where Self == AutomaticFormStyle { public static var automatic: AutomaticFormStyle { AutomaticFormStyle() } }
extension FormStyle where Self == ColumnsFormStyle { public static var columns: ColumnsFormStyle { ColumnsFormStyle() } }
extension FormStyle where Self == GroupedFormStyle { public static var grouped: GroupedFormStyle { GroupedFormStyle() } }

extension EnvironmentValues {
    private struct FormStyleKey: EnvironmentKey { static let defaultValue: _FormStyleKind = .automatic }
    var _formStyle: _FormStyleKind { get { self[FormStyleKey.self] } set { self[FormStyleKey.self] = newValue } }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/formstyle(_:)
    public func formStyle<S: FormStyle>(_ style: S) -> some View { environment(\._formStyle, style.kind) }
}

// MARK: Form rows

extension EnvironmentValues {
    private struct FormContextKey: EnvironmentKey { static let defaultValue: _FormStyleKind? = nil }
    /// The style of the enclosing `Form`, nil outside one. Inside a form a titled control
    /// (`TextField`, `SecureField`, `Picker`, and `LabeledContent`) is a labelled row: the
    /// title is a label beside the control, not only its placeholder, as on macOS.
    var _formContext: _FormStyleKind? { get { self[FormContextKey.self] } set { self[FormContextKey.self] = newValue } }
    private struct LabelsHiddenKey: EnvironmentKey { static let defaultValue = false }
    /// Set by `labelsHidden()`: controls show no label of their own (a text field's title
    /// stays its placeholder, a picker or toggle shows its control alone).
    var _labelsHidden: Bool { get { self[LabelsHiddenKey.self] } set { self[LabelsHiddenKey.self] = newValue } }
    private struct FormLabelWidthKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
    /// A columns form's label column: the widest label of its rows, once they reported it.
    var _formLabelWidth: CGFloat? { get { self[FormLabelWidthKey.self] } set { self[FormLabelWidthKey.self] = newValue } }
}

/// The rows of a columns form report their labels' natural widths; the form keeps the widest
/// as its label column. The widths are measured before the column frame is applied, so a
/// new column width never changes what is reported (no update loop).
struct _FormLabelWidthPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Reports its content's natural width for the label column.
struct _FormLabelWidthReporter<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _PreferencePrimitive(key: _FormLabelWidthPreference.self, value: { n in
            (n.children.first?.sizeThatFits(.unspecified).width ?? 0).rounded(.up)
        }, content: _ViewBox(content))
    }
}

/// One labelled row of a form. Grouped (and outside a form): the label leading, the content
/// trailing. Columns: the label trailing-aligned in the form's label column, the content
/// leading the control column. The content is laid out as outside a form, so a field inside
/// a `LabeledContent` is not labelled twice.
struct _FormRow: View {
    let label: AnyView
    let content: AnyView
    var alignment: VerticalAlignment = .center
    /// A control that lists its options (a radio-group or inline picker): in a grouped form
    /// the label sits at the top of the row and the options under it, leading-aligned and
    /// across the full width, as macOS's Settings forms show them.
    var stacked = false
    @Environment(\._formContext) private var context
    @Environment(\._formLabelWidth) private var labelWidth
    var body: some View {
        if context == .columns || context == .automatic {
            HStack(alignment: alignment, spacing: 8) {
                _FormLabelWidthReporter(content: label).frame(width: labelWidth, alignment: .trailing)
                content.environment(\._formContext, nil)
            }
        } else if stacked {
            VStack(alignment: .leading, spacing: 4) {
                label
                content.environment(\._formContext, nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // The label leads and the control sits at the trailing edge, a flexible control
            // taking the rest of the row. When the two do not fit side by side the label
            // wraps (down to its widest word) before the control gives up width, as macOS's
            // grouped forms do ("Hardware" / "Channel" beside a whole "1 — Input 1").
            _FormRowLayout(alignment: alignment) {
                label
                content.environment(\._formContext, nil)
            }
        }
    }
}

/// The grouped row's two-column layout: see `_FormRow`.
struct _FormRowLayout: Layout {
    var alignment: VerticalAlignment = .center
    static let gap: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (label, content) = widths(proposal, subviews)
        let lh = subviews.first?.sizeThatFits(ProposedViewSize(width: label, height: nil)).height ?? 0
        let ch = subviews.count > 1 ? subviews[1].sizeThatFits(ProposedViewSize(width: content, height: nil)).height : 0
        let natural = label + (subviews.count > 1 ? Self.gap + content : 0)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural
        return CGSize(width: width, height: max(lh, ch))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (label, content) = widths(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
        let rtl = subviews.layoutDirection == .rightToLeft
        func y(_ h: CGFloat) -> CGFloat { alignment == .top ? bounds.minY : alignment == .bottom ? bounds.maxY - h : bounds.midY - h / 2 }
        if let l = subviews.first {
            let p = ProposedViewSize(width: label, height: nil)
            l.place(at: CGPoint(x: rtl ? bounds.maxX - label : bounds.minX, y: y(l.sizeThatFits(p).height)), proposal: p)
        }
        if subviews.count > 1 {
            let p = ProposedViewSize(width: content, height: nil)
            subviews[1].place(at: CGPoint(x: rtl ? bounds.minX : bounds.maxX - content, y: y(subviews[1].sizeThatFits(p).height)), proposal: p)
        }
    }
    /// The label's and the control's widths for a proposal.
    private func widths(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGFloat, CGFloat) {
        guard let l = subviews.first else { return (0, 0) }
        let labelIdeal = l.sizeThatFits(.unspecified).width
        guard subviews.count > 1 else { return (labelIdeal, 0) }
        let c = subviews[1]
        let contentIdeal = c.sizeThatFits(.unspecified).width
        guard let w = proposal.width, w.isFinite else { return (labelIdeal, contentIdeal) }
        if labelIdeal + Self.gap + contentIdeal <= w {
            // Room for both: the control may stretch into the rest (a text field does, a
            // pop-up or switch keeps its size).
            let content = min(max(contentIdeal, c.sizeThatFits(ProposedViewSize(width: w - labelIdeal - Self.gap, height: nil)).width), w - labelIdeal - Self.gap)
            return (labelIdeal, content)
        }
        // The label's narrowest: wrapped at every word (a zero proposal).
        let labelMin = min(labelIdeal, l.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width)
        let content = min(c.sizeThatFits(ProposedViewSize(width: max(0, min(contentIdeal, w - labelMin - Self.gap)), height: nil)).width, max(0, w - labelMin - Self.gap))
        let label = max(0, min(labelIdeal, w - content - Self.gap))
        return (label, content)
    }
}

/// Whether a titled control's label view has something to show in a form row.
func _formHasLabel(_ label: Any) -> Bool {
    if let t = label as? Text { return !t._string.isEmpty }
    return !(label is EmptyView)
}

// MARK: ContentUnavailableView

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/contentunavailableview
public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    let label: Label
    let description: Description
    let actions: Actions
    public init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() }, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label(); self.description = description(); self.actions = actions()
    }
    public var body: some View {
        VStack(spacing: 10) {
            label
                .font(.title2.weight(.bold))
                .labelStyle(_ContentUnavailableLabelStyle())
            description
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The icon above the title, large and secondary, as Apple's view lays it out.
private struct _ContentUnavailableLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 12) {
            configuration.icon.font(.system(size: 44)).foregroundStyle(Color.secondary)
            configuration.title
        }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    public init(_ title: LocalizedStringKey, image name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, image: name) }, description: { description }, actions: { EmptyView() })
    }
    public init<S: StringProtocol>(_ title: S, image name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, image: name) }, description: { description }, actions: { EmptyView() })
    }
    public init(_ title: LocalizedStringKey, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description }, actions: { EmptyView() })
    }
    public init<S: StringProtocol>(_ title: S, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(title, systemImage: name) }, description: { description }, actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/contentunavailableview/search
    public static var search: ContentUnavailableView<SwiftUI.Label<Text, Image>, Text?, EmptyView> {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/contentunavailableview/search(text:)
    public static func search(text: String) -> ContentUnavailableView<SwiftUI.Label<Text, Image>, Text?, EmptyView> {
        ContentUnavailableView("No Results for “\(text)”", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    }
}
