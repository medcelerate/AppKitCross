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
    init(label: AnyView, content: AnyView) { self.label = Label(content: label); self.content = Content(content: content) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/labeledcontentstyle
@MainActor @preconcurrency
public protocol LabeledContentStyle {
    associatedtype Body: View
    typealias Configuration = LabeledContentStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

/// The label leading, the content trailing in the secondary colour, as AppKit's forms show
/// a read-only value.
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/automaticlabeledcontentstyle
public struct AutomaticLabeledContentStyle: LabeledContentStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content.foregroundStyle(Color.secondary)
        }
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
        AnyView(style.makeBody(configuration: LabeledContentStyleConfiguration(label: AnyView(label), content: AnyView(content))))
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
