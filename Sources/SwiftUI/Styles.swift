// Label styles, type-erased shape styles, scaled metrics, symbol and image scale
// modifiers, environment transforms and preference-driven decorations: members
// swift-markdown-ui uses that the third-party library compatibility example found missing.

import Foundation

// MARK: LabelStyle

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration
public struct LabelStyleConfiguration {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration/title
    public struct Title: View {
        let content: AnyView
        public var body: some View { content }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/labelstyleconfiguration/icon
    public struct Icon: View {
        let content: AnyView
        public var body: some View { content }
    }
    public let title: Title
    public let icon: Icon
    init(title: AnyView, icon: AnyView) { self.title = Title(content: title); self.icon = Icon(content: icon) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/labelstyle
@MainActor @preconcurrency
public protocol LabelStyle {
    associatedtype Body: View
    typealias Configuration = LabelStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/defaultlabelstyle
public struct DefaultLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.icon; configuration.title } }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/titleandiconlabelstyle
public struct TitleAndIconLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.icon; configuration.title } }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/titleonlylabelstyle
public struct TitleOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.title }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/icononlylabelstyle
public struct IconOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.icon }
}
extension LabelStyle where Self == DefaultLabelStyle { public static var automatic: DefaultLabelStyle { DefaultLabelStyle() } }
extension LabelStyle where Self == TitleAndIconLabelStyle { public static var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() } }
extension LabelStyle where Self == TitleOnlyLabelStyle { public static var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() } }
extension LabelStyle where Self == IconOnlyLabelStyle { public static var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() } }

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/labelstyle(_:)
    public func labelStyle<S: LabelStyle>(_ style: S) -> some View { environment(\._labelStyle, style) }
}

// MARK: AnyShapeStyle

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/anyshapestyle
public struct AnyShapeStyle: ShapeStyle {
    let style: any ShapeStyle
    public init<S: ShapeStyle>(_ style: S) { self.style = style }
    @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) {
        style._fill(context, path: path, in: rect, environment: environment)
    }
    @MainActor public func _stroke(_ context: CGContext, path: CGPath, in rect: CGRect, style strokeStyle: StrokeStyle, environment: EnvironmentValues) {
        style._stroke(context, path: path, in: rect, style: strokeStyle, environment: environment)
    }
    @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? {
        style._color(at: point, in: rect, environment: environment)
    }
}

// MARK: ScaledMetric

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scaledmetric
/// Dynamic Type has no counterpart on Windows and Linux: the value is used as given.
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty {
    let value: Value
    let textStyle: Font.TextStyle
    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle) { value = wrappedValue; self.textStyle = textStyle }
    public init(wrappedValue: Value) { self.init(wrappedValue: wrappedValue, relativeTo: .body) }
    public var wrappedValue: Value { value }
}

// MARK: Symbols and image scale

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/symbolrenderingmode
public struct SymbolRenderingMode: Sendable {
    let kind: Int
    public static let monochrome = SymbolRenderingMode(kind: 0)
    public static let multicolor = SymbolRenderingMode(kind: 1)
    public static let hierarchical = SymbolRenderingMode(kind: 2)
    public static let palette = SymbolRenderingMode(kind: 3)
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/symbolrenderingmode(_:)
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/imagescale(_:)
    public func imageScale(_ scale: Image.Scale) -> some View { environment(\.imageScale, scale) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/linespacing(_:)
    public func lineSpacing(_ lineSpacing: CGFloat) -> some View { environment(\.lineSpacing, lineSpacing) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/transformenvironment(_:transform:)
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, transform: @escaping (inout V) -> Void) -> some View {
        _EnvironmentView(content: self) { transform(&$0[keyPath: keyPath]) }
    }
}

// MARK: Preference-driven decorations

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/backgroundpreferencevalue(_:_:)
    public func backgroundPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type, @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        _PreferenceView(content: self) { _PreferenceValuePrimitive(key: K.self, overlay: false, alignment: .center, transform: { AnyView(transform($0)) }, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/backgroundpreferencevalue(_:alignment:_:)
    public func backgroundPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type, alignment: Alignment = .center, @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        _PreferenceView(content: self) { _PreferenceValuePrimitive(key: K.self, overlay: false, alignment: alignment, transform: { AnyView(transform($0)) }, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/overlaypreferencevalue(_:_:)
    public func overlayPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type, @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        _PreferenceView(content: self) { _PreferenceValuePrimitive(key: K.self, overlay: true, alignment: .center, transform: { AnyView(transform($0)) }, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/overlaypreferencevalue(_:alignment:_:)
    public func overlayPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type, alignment: Alignment = .center, @ViewBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        _PreferenceView(content: self) { _PreferenceValuePrimitive(key: K.self, overlay: true, alignment: alignment, transform: { AnyView(transform($0)) }, content: $0) }
    }
}

/// The content with a background or overlay built from the subtree's preference value;
/// the root hands the value over after each layout pass and the decoration is rebuilt
/// when it changes (values compared by `==` when Equatable, else by description).
@MainActor
final class _PreferenceValuePrimitive: _Primitive {
    let key: ObjectIdentifier
    let defaultValue: Any
    let isEqual: (Any, Any) -> Bool
    var transform: (Any) -> AnyView
    let overlay: Bool
    var alignment: Alignment
    private let content: _AnyViewBox
    private var last: Any?
    private let view = _ContainerView(frame: .zero)

    init<K: PreferenceKey>(key: K.Type, overlay: Bool, alignment: Alignment, transform: @escaping (K.Value) -> AnyView, content: _AnyViewBox) {
        self.key = ObjectIdentifier(K.self)
        defaultValue = K.defaultValue
        isEqual = { a, b in
            if let x = a as? any Equatable, let y = b as? any Equatable { return _equatableEqual(x, y) }
            return String(describing: a) == String(describing: b)
        }
        self.transform = { transform($0 as! K.Value) }
        self.overlay = overlay
        self.alignment = alignment
        self.content = content
        super.init()
        children = [content]
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        guard let o = other as? _PreferenceValuePrimitive else { return }
        transform = o.transform
        alignment = o.alignment
        children = decorated(o.content)
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); node.root?.usesPreferences = true }
    private var contentBox: _AnyViewBox { children.count == 2 ? children[overlay ? 0 : 1] : children[0] }
    private func decorated(_ content: _AnyViewBox) -> [_AnyViewBox] {
        guard let v = last else { return [content] }
        let d = _ViewBox(transform(v))
        return overlay ? [content, d] : [d, content]
    }
    /// Called by the root with the subtree's reduced value.
    func deliver(_ value: Any) {
        if let l = last, isEqual(l, value) { return }
        last = value
        children = decorated(contentBox)
        node?.setNeedsUpdate()
    }
    private var contentNode: _ViewNode? {
        guard let node else { return nil }
        return node.children.count == 2 ? node.children[overlay ? 0 : 1] : node.children.first
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { contentNode?.sizeThatFits(proposal) ?? .zero }
    override func place(node: _ViewNode, in rect: CGRect) {
        let content = contentNode
        content?.place(in: rect)
        for d in node.children where d !== content {
            let s = d.sizeThatFits(ProposedViewSize(rect.size))
            d.place(in: CGRect(origin: alignment.origin(of: s, in: rect), size: s).integralIfNeeded)
        }
    }
}

func _equatableEqual<A: Equatable>(_ a: A, _ b: any Equatable) -> Bool { (b as? A) == a }
