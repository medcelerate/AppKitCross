// Liquid Glass for SwiftUI (ADR-0052): `glassEffect`, `Glass`, `GlassEffectContainer`,
// `glassEffectID` and the glass button styles of the macOS 26 SDK. With the Liquid Glass
// switch on (`APPKITWIN_LIQUID_GLASS=1`, `AppKitCrossLiquidGlass`) a glass effect is an
// `NSGlassEffectView` behind the view and a glass button draws on a glass capsule; off,
// `glassEffect` adds nothing and the glass button styles fall back to the bordered look,
// so an app written against the 26 SDK runs unchanged on every port.

import Foundation
import AppKit

// MARK: Glass

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/glass
public struct Glass: Equatable, Sendable {
    enum Variant: Equatable, Sendable { case regular, clear, identity }
    var variant: Variant
    var tint: Color?
    var isInteractive = false

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/glass/regular
    public static var regular: Glass { Glass(variant: .regular) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/glass/clear
    public static var clear: Glass { Glass(variant: .clear) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/glass/identity
    public static var identity: Glass { Glass(variant: .identity) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/glass/tint(_:)
    public func tint(_ color: Color?) -> Glass { var g = self; g.tint = color; return g }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/glass/interactive(_:)
    public func interactive(_ isEnabled: Bool = true) -> Glass { var g = self; g.isInteractive = isEnabled; return g }

    var style: NSGlassEffectView.Style { variant == .clear ? .clear : .regular }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/defaultglasseffectshape
/// The capsule, as on macOS.
public struct DefaultGlassEffectShape: Shape, Sendable {
    public init() {}
    public func path(in rect: CGRect) -> Path { Capsule().path(in: rect) }
}

// MARK: glassEffect

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:isenabled:)
    public func glassEffect<S: Shape>(_ glass: Glass = .regular, in shape: S = DefaultGlassEffectShape(), isEnabled: Bool = true) -> some View {
        _GlassEffectModified(content: self, glass: glass, shape: AnyShape(shape), isCapsule: shape is DefaultGlassEffectShape || shape is Capsule, isEnabled: isEnabled)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
    /// The morphing transition between glass shapes that share an identifier is not drawn;
    /// the identifier is accepted so view code written for macOS 26 compiles and lays out.
    public func glassEffectID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)
    /// Glass effects in one `GlassEffectContainer` sharing `id` draw as one shape whatever
    /// their distance.
    public func glassEffectUnion<ID: Hashable & Sendable>(id: ID, namespace: Namespace.ID) -> some View {
        environment(\._glassUnionID, AnyHashable(_GlassUnionKey(id: AnyHashable(id), namespace: namespace)))
    }
}

/// The content over an `NSGlassEffectView` with Liquid Glass on and the effect enabled;
/// the content alone otherwise (no wrapper view, so the pixels are today's).
struct _GlassEffectModified<Content: View>: View {
    let content: Content
    let glass: Glass
    let shape: AnyShape
    /// The default shape (a capsule), which the glass view draws analytically.
    let isCapsule: Bool
    let isEnabled: Bool
    @Environment(\._glassUnionID) private var unionID
    @ViewBuilder var body: some View {
        if isEnabled, glass.variant != .identity, _LiquidGlass.isEnabled {
            content.background(_GlassSurface(glass: glass, shape: shape, isCapsule: isCapsule, unionID: unionID))
        } else {
            content
        }
    }
}

/// The glass surface behind a view: an `NSGlassEffectView` clipped to the shape, taking
/// whatever size the background is offered.
struct _GlassSurface: View, _PrimitiveView {
    typealias Body = Never
    let glass: Glass
    let shape: AnyShape
    let isCapsule: Bool
    var unionID: AnyHashable? = nil
    func _makePrimitive(node: _ViewNode) -> _Primitive { _GlassSurfacePrimitive(glass: glass, shape: shape, isCapsule: isCapsule, unionID: unionID) }
}

/// `glassEffectUnion`'s identifier within its namespace.
struct _GlassUnionKey: Hashable {
    let id: AnyHashable
    let namespace: Namespace.ID
}

@MainActor
final class _GlassSurfacePrimitive: _Primitive {
    var glass: Glass
    var shape: AnyShape
    var isCapsule: Bool
    var unionID: AnyHashable?
    let view = NSGlassEffectView(frame: .zero)

    init(glass: Glass, shape: AnyShape, isCapsule: Bool, unionID: AnyHashable?) {
        self.glass = glass; self.shape = shape; self.isCapsule = isCapsule; self.unionID = unionID
        super.init()
        install()
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _GlassSurfacePrimitive else { return }
        glass = o.glass; shape = o.shape; isCapsule = o.isCapsule; unionID = o.unionID
        install()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); install() }
    private func install() {
        let shape = shape
        view.style = glass.style
        view.tintColor = glass.tint?.nsColor
        view._isInteractive = glass.isInteractive
        if view._unionID != unionID { view._unionID = unionID }
        // The default shape is the capsule the view draws itself (an analytic outline);
        // any other shape is rasterised.
        view.cornerRadius = 10_000
        view._shapePath = isCapsule ? nil : { rect in NSBezierPath(cgPath: shape.path(in: rect).cgPath) }
        view.needsDisplay = true
    }
    /// A background takes the size proposed (the content's), like a shape.
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        CGSize(width: proposal.width.map { $0.isFinite ? $0 : 10 } ?? 10, height: proposal.height.map { $0.isFinite ? $0 : 10 } ?? 10)
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
    override func didLayout(node: _ViewNode) { view.needsDisplay = true }
}

// MARK: GlassEffectContainer

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
/// Groups glass effects: an `NSGlassEffectContainerView` around the content, so glass
/// shapes closer than `spacing` (macOS's default is 40 points) merge into one surface.
public struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat?
    let content: Content
    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    public var body: some View {
        _GlassContainer(spacing: spacing ?? 40, box: _ViewBox(content.environment(\._glassContainerSpacing, spacing)))
    }
}

/// The container view behind `GlassEffectContainer`, holding the content's views.
struct _GlassContainer: View, _PrimitiveView {
    typealias Body = Never
    let spacing: CGFloat
    let box: _AnyViewBox
    func _makePrimitive(node: _ViewNode) -> _Primitive { _GlassContainerPrimitive(spacing: spacing, content: box) }
}

@MainActor
final class _GlassContainerPrimitive: _Primitive {
    let view = NSGlassEffectContainerView(frame: .zero)
    init(spacing: CGFloat, content: _AnyViewBox) {
        super.init()
        children = [content]
        view.spacing = spacing
    }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _GlassContainerPrimitive, view.spacing != o.view.spacing { view.spacing = o.view.spacing }
    }
    override func didLayout(node: _ViewNode) { view.needsLayout = true }
}

extension EnvironmentValues {
    private struct GlassContainerSpacingKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }
    /// The enclosing `GlassEffectContainer`'s spacing (nil outside one).
    var _glassContainerSpacing: CGFloat? {
        get { self[GlassContainerSpacingKey.self] }
        set { self[GlassContainerSpacingKey.self] = newValue }
    }
    private struct GlassUnionIDKey: EnvironmentKey { static let defaultValue: AnyHashable? = nil }
    /// `glassEffectUnion`'s identifier for the glass effects inside it.
    var _glassUnionID: AnyHashable? {
        get { self[GlassUnionIDKey.self] }
        set { self[GlassUnionIDKey.self] = newValue }
    }
}

// MARK: Namespace

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/namespace
/// A namespace for identifiers shared between views (`glassEffectID`, `matchedGeometryEffect`).
@propertyWrapper
public struct Namespace: DynamicProperty, Sendable {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/namespace/id
    public struct ID: Hashable, Sendable {
        let value: Int
    }
    private let id: ID
    public init() { id = ID(value: Namespace._next()) }
    public var wrappedValue: Namespace.ID { id }

    private static let _lock = NSLock()
    nonisolated(unsafe) private static var _counter = 0
    private static func _next() -> Int {
        _lock.lock(); defer { _lock.unlock() }
        _counter += 1
        return _counter
    }
}

// MARK: Glass button styles

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/glassbuttonstyle
public struct GlassButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public var kind: _ButtonStyleKind { .glass }
}
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle
public struct GlassProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}
    public var kind: _ButtonStyleKind { .glassProminent }
}
extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass
    public static var glass: GlassButtonStyle { GlassButtonStyle() }
}
extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent
    public static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

/// The button behind SwiftUI's `Button`: with a glass style and Liquid Glass on it draws
/// its label on a glass capsule (the bezel is left to the glass; the cell still sizes the
/// button as a bordered one); otherwise it is a plain `NSButton`, pixel for pixel.
@MainActor
final class _GlassButton: NSButton {
    /// The glass this button draws (nil: the cell's bezel, as today).
    var glassProminent: Bool? {
        didSet {
            guard glassProminent != oldValue else { return }
            needsDisplay = true
            if (glassProminent == nil) != (oldValue == nil) { hovered = false; updateTrackingAreas() }
        }
    }
    /// The pointer is over the button (a glass button brightens under it).
    private(set) var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = hoverArea { removeTrackingArea(a); hoverArea = nil }
        guard glassProminent != nil, _LiquidGlass.isEnabled else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { if hoverArea != nil { hovered = true } else { super.mouseEntered(with: event) } }
    override func mouseExited(with event: NSEvent) { if hoverArea != nil { hovered = false } else { super.mouseExited(with: event) } }

    override func draw(_ dirtyRect: NSRect) {
        guard let prominent = glassProminent, _LiquidGlass.isEnabled, isBordered else { super.draw(dirtyRect); return }
        let r = bounds.insetBy(dx: 1, dy: 1)
        _MaterialBackground.draw(.control(prominent: prominent, highlighted: isHighlighted, hovered: hovered), in: r, of: self)
        cell?.drawInterior(withFrame: bounds, in: self)
    }
}
