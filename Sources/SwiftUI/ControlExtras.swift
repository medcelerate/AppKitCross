// Controls and modifiers a real app (Sibyl) reached for: `Button(_:systemImage:)`,
// `GroupBox`, `Link`, `safeAreaInset`, `contentShape`, `pointerStyle`, the borderless
// button menu style, `openSettings`, the duration forms of the named springs and
// unsorted `TableColumn(_:value:)`.

import Foundation

// MARK: Button with a system image

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/button/init(_:systemimage:action:)-6u7jw
    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/button/init(_:systemimage:action:)-48hdp
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) { SwiftUI.Label(title, systemImage: systemImage) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/button/init(_:systemimage:role:action:)-8d0tt
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/button/init(_:systemimage:role:action:)-1vb7p
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, systemImage: systemImage) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/button/init(_:image:action:)-6ohrf
    public init(_ titleKey: LocalizedStringKey, image: String, action: @escaping () -> Void) {
        self.init(action: action) { SwiftUI.Label(titleKey, image: image) }
    }
}

extension Button where Label == Text {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/button/init(_:role:action:)-93ek6
    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) { Text(titleKey) }
    }
}

// MARK: GroupBox

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/groupbox
///
/// The label above a rounded, lightly filled box holding the content, as macOS draws it.
public struct GroupBox<Label: View, Content: View>: View {
    let label: Label
    let content: Content
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content(); self.label = label()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !(label is EmptyView) { label.font(.headline) }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
        }
    }
}

extension GroupBox where Label == EmptyView {
    public init(@ViewBuilder content: () -> Content) { self.init(content: content, label: { EmptyView() }) }
}

extension GroupBox where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(titleKey) }) }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(title) }) }
}

extension GroupBox {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/groupbox/init(label:content:)
    @available(macOS, deprecated: 100000.0, renamed: "GroupBox(content:label:)")
    public init(label: Label, @ViewBuilder content: () -> Content) { self.init(content: content, label: { label }) }
}

// MARK: Link

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/link
///
/// A link-styled button that opens its URL through the environment's `openURL`.
public struct Link<Label: View>: View {
    let destination: URL
    let label: Label
    @Environment(\.openURL) private var openURL
    public init(destination: URL, @ViewBuilder label: () -> Label) { self.destination = destination; self.label = label() }
    public var body: some View {
        Button(action: { openURL(destination) }) { label }
            .buttonStyle(.link)
    }
}

extension Link where Label == Text {
    public init(_ titleKey: LocalizedStringKey, destination: URL) { self.init(destination: destination) { Text(titleKey) } }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, destination: URL) { self.init(destination: destination) { Text(title) } }
}

// MARK: safeAreaInset

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-6gwby
    ///
    /// The inset content sits on that edge and the view takes the rest of the space. On
    /// macOS a scroll view under the inset scrolls behind it; here it ends where the inset
    /// begins (the port has no safe-area insets for scroll content).
    public func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View {
        let inset = content()
        return VStack(alignment: alignment, spacing: spacing ?? 0) {
            if edge == .top { inset }
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
            if edge == .bottom { inset }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-4s51l
    public func safeAreaInset<V: View>(edge: HorizontalEdge, alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View {
        let inset = content()
        return HStack(alignment: alignment, spacing: spacing ?? 0) {
            if edge == .leading { inset }
            self.frame(maxWidth: .infinity, maxHeight: .infinity)
            if edge == .trailing { inset }
        }
    }
}

// MARK: contentShape

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/contentshapekinds
public struct ContentShapeKinds: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let interaction = ContentShapeKinds(rawValue: 1 << 0)
    public static let dragPreview = ContentShapeKinds(rawValue: 1 << 1)
    public static let contextMenuPreview = ContentShapeKinds(rawValue: 1 << 2)
    public static let hoverEffect = ContentShapeKinds(rawValue: 1 << 3)
    public static let focusEffect = ContentShapeKinds(rawValue: 1 << 4)
    public static let accessibility = ContentShapeKinds(rawValue: 1 << 5)
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/contentshape(_:eofill:)
    ///
    /// Hit testing for the content follows the shape: a point inside it hits the content
    /// (its transparent gaps included), a point outside it hits nothing in the content.
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        _ContentShaped(content: self, shape: AnyShape(shape), eoFill: eoFill)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/contentshape(_:_:eofill:)
    ///
    /// Only `.interaction` changes anything: the port draws no drag, context-menu or hover
    /// previews whose outline the other kinds would set.
    public func contentShape<S: Shape>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View {
        _ContentShaped(content: self, shape: kind.contains(.interaction) ? AnyShape(shape) : nil, eoFill: eoFill)
    }
}

struct _ContentShaped<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let shape: AnyShape?
    let eoFill: Bool
    func _makePrimitive(node: _ViewNode) -> _Primitive { _ContentShapePrimitive(shape: shape, eoFill: eoFill, content: _ViewBox(content)) }
}

/// The view that answers hit tests by the shape.
@MainActor
final class _ContentShapeView: NSView, _SwiftUIBackedView {
    var shape: AnyShape?
    var eoFill = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let shape else {
            let hit = super.hitTest(point)
            return hit === self ? nil : hit
        }
        let local = superview.map { convert(point, from: $0) } ?? point
        guard shape.path(in: bounds).cgPath.contains(local, using: eoFill ? .evenOdd : .winding) else { return nil }
        return super.hitTest(point)
    }
    override var acceptsFirstResponder: Bool { false }
}

@MainActor
final class _ContentShapePrimitive: _Primitive {
    let view = _ContentShapeView(frame: .zero)
    init(shape: AnyShape?, eoFill: Bool, content: _AnyViewBox) {
        super.init()
        view.shape = shape
        view.eoFill = eoFill
        children = [content]
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _ContentShapePrimitive { view.shape = o.view.shape; view.eoFill = o.view.eoFill }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { node.children.first?.sizeThatFits(proposal) ?? .zero }
    override func place(node: _ViewNode, in rect: CGRect) { node.children.first?.place(in: rect) }
}

// MARK: pointerStyle

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/frameresizeposition
@frozen public enum FrameResizePosition: Int8, CaseIterable {
    case top, leading, bottom, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/frameresizedirection
@frozen public enum FrameResizeDirection: Int8, CaseIterable {
    case inward, outward
    @frozen public struct Set: OptionSet, Equatable, Hashable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ direction: FrameResizeDirection) { self.init(rawValue: 1 << direction.rawValue) }
        public static let inward = Set(.inward)
        public static let outward = Set(.outward)
        public static let all: Set = [.inward, .outward]
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/pointerstyle
public struct PointerStyle: Sendable {
    enum Kind: Sendable {
        case standard, horizontalText, verticalText, rectSelection, grabIdle, grabActive, link, zoomIn, zoomOut, columnResize, rowResize
        case frameResize(FrameResizePosition, FrameResizeDirection.Set)
        case image(Image, UnitPoint)
    }
    let kind: Kind
    public static let `default` = PointerStyle(kind: .standard)
    public static let horizontalText = PointerStyle(kind: .horizontalText)
    public static let verticalText = PointerStyle(kind: .verticalText)
    public static let rectSelection = PointerStyle(kind: .rectSelection)
    public static let grabIdle = PointerStyle(kind: .grabIdle)
    public static let grabActive = PointerStyle(kind: .grabActive)
    public static let link = PointerStyle(kind: .link)
    public static let zoomIn = PointerStyle(kind: .zoomIn)
    public static let zoomOut = PointerStyle(kind: .zoomOut)
    public static let columnResize = PointerStyle(kind: .columnResize)
    public static let rowResize = PointerStyle(kind: .rowResize)
    public static func frameResize(position: FrameResizePosition, directions: FrameResizeDirection.Set = .all) -> PointerStyle {
        PointerStyle(kind: .frameResize(position, directions))
    }
    public static func image(_ image: Image, hotSpot: UnitPoint) -> PointerStyle { PointerStyle(kind: .image(image, hotSpot)) }

    /// The AppKit cursor for this style in a layout direction.
    @available(macOS 15.0, *)
    @MainActor func cursor(rightToLeft: Bool) -> NSCursor {
        switch kind {
        case .standard: return .arrow
        case .horizontalText: return .iBeam
        case .verticalText: return .iBeamCursorForVerticalLayout
        case .rectSelection: return .crosshair
        case .grabIdle: return .openHand
        case .grabActive: return .closedHand
        case .link: return .pointingHand
        case .zoomIn: return .zoomIn
        case .zoomOut: return .zoomOut
        case .columnResize: return .resizeLeftRight
        case .rowResize: return .resizeUpDown
        case .frameResize(let position, let directions):
            let leading: NSCursor.FrameResizePosition = rightToLeft ? .right : .left
            let trailing: NSCursor.FrameResizePosition = rightToLeft ? .left : .right
            let p: NSCursor.FrameResizePosition
            switch position {
            case .top: p = .top
            case .bottom: p = .bottom
            case .leading: p = leading
            case .trailing: p = trailing
            case .topLeading: p = rightToLeft ? .topRight : .topLeft
            case .topTrailing: p = rightToLeft ? .topLeft : .topRight
            case .bottomLeading: p = rightToLeft ? .bottomRight : .bottomLeft
            case .bottomTrailing: p = rightToLeft ? .bottomLeft : .bottomRight
            }
            let d = NSCursor.FrameResizeDirection.Set(rawValue: (directions.contains(.inward) ? NSCursor.FrameResizeDirection.Set.inward.rawValue : 0)
                                                        | (directions.contains(.outward) ? NSCursor.FrameResizeDirection.Set.outward.rawValue : 0))
            return .frameResize(position: p, directions: d)
        case .image(let image, let hotSpot):
            guard let ns = image.image else { return .arrow }
            return NSCursor(image: ns, hotSpot: NSPoint(x: ns.size.width * hotSpot.x, y: ns.size.height * hotSpot.y))
        }
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:)
    ///
    /// Sets the cursor over the view through an AppKit cursor rect; nil leaves it alone.
    public func pointerStyle(_ style: PointerStyle?) -> some View { _PointerStyled(content: self, style: style) }
}

struct _PointerStyled<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let style: PointerStyle?
    func _makePrimitive(node: _ViewNode) -> _Primitive { _PointerStylePrimitive(style: style, content: _ViewBox(content)) }
}

@MainActor
final class _PointerStyleView: NSView, _SwiftUIBackedView {
    var cursor: NSCursor? { didSet { window?.invalidateCursorRects(for: self) } }
    override var isFlipped: Bool { true }
    override func resetCursorRects() {
        if let cursor { addCursorRect(bounds, cursor: cursor) }
    }
    /// The view only sets the cursor: clicks reach what is under it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
final class _PointerStylePrimitive: _Primitive {
    let view = _PointerStyleView(frame: .zero)
    var style: PointerStyle?
    init(style: PointerStyle?, content: _AnyViewBox) {
        self.style = style
        super.init()
        children = [content]
    }
    override var nsView: NSView? { view }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _PointerStylePrimitive { style = o.style }
        apply()
    }
    private func apply() {
        var c: NSCursor? = nil
        if #available(macOS 15.0, *) { c = style?.cursor(rightToLeft: node?.environment.layoutDirection == .rightToLeft) }
        if c !== view.cursor { view.cursor = c }
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize { node.children.first?.sizeThatFits(proposal) ?? .zero }
    override func place(node: _ViewNode, in rect: CGRect) { node.children.first?.place(in: rect) }
}

// MARK: Menu style

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/borderlessbuttonmenustyle
///
/// Accepted like the other menu styles; the port's menus keep their one look.
public struct BorderlessButtonMenuStyle: MenuStyle {
    public init() {}
}
extension MenuStyle where Self == BorderlessButtonMenuStyle {
    public static var borderlessButton: BorderlessButtonMenuStyle { BorderlessButtonMenuStyle() }
}

// MARK: openSettings

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/opensettingsaction
///
/// Opens (or brings forward) the app's `Settings` scene window.
@MainActor @preconcurrency
public struct OpenSettingsAction {
    public func callAsFunction() { _AppRunner._current?.openSettings() }
}

private struct _OpenSettingsKey: EnvironmentKey {
    static var defaultValue: OpenSettingsAction { MainActor.assumeIsolated { OpenSettingsAction() } }
}

extension EnvironmentValues {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/opensettings
    public var openSettings: OpenSettingsAction { self[_OpenSettingsKey.self] }
}

// MARK: Named springs with a duration

extension Animation {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/animation/smooth(duration:extrabounce:)
    public static func smooth(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: extraBounce)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/animation/snappy(duration:extrabounce:)
    public static func snappy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.15 + extraBounce)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/animation/bouncy(duration:extrabounce:)
    public static func bouncy(duration: TimeInterval = 0.5, extraBounce: Double = 0.0) -> Animation {
        spring(duration: duration, bounce: 0.3 + extraBounce)
    }
}

// MARK: Unsorted value columns

extension TableColumn where Sort == Never, Label == Text, Content == Text {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/tablecolumn/init(_:value:)-1kgsb
    ///
    /// A column of the row's string in a table without a sort order.
    public init(_ titleKey: LocalizedStringKey, value: KeyPath<RowValue, String>) {
        self.init(_erased: _AnyTableColumn(title: titleKey.key, makeCell: { AnyView(Text($0[keyPath: value])) }, sortKeyPath: nil, comparator: nil))
    }
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String>) {
        self.init(_erased: _AnyTableColumn(title: String(title), makeCell: { AnyView(Text($0[keyPath: value])) }, sortKeyPath: nil, comparator: nil))
    }
    public init(_ text: Text, value: KeyPath<RowValue, String>) {
        self.init(_erased: _AnyTableColumn(title: text._string, makeCell: { AnyView(Text($0[keyPath: value])) }, sortKeyPath: nil, comparator: nil))
    }
}
