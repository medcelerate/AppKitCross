// Modifiers: environment-carrying ones (font, foreground colour, disabled, line limit),
// decorations backed by a layer-backed view (background, overlay, border, corner radius,
// clipping, opacity), and event hooks (tap, hover, appear).

import Foundation

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/font(_:)
    public func font(_ font: Font?) -> some View { environment(\.font, font) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/foregroundcolor(_:)
    public func foregroundColor(_ color: Color?) -> some View { environment(\.foregroundColor, color) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/foregroundstyle(_:)
    public func foregroundStyle(_ color: Color) -> some View { environment(\.foregroundColor, color) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/disabled(_:)
    public func disabled(_ disabled: Bool) -> some View {
        _EnvironmentView(content: self) { if disabled { $0.isEnabled = false } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/linelimit(_:)-513mb
    public func lineLimit(_ number: Int?) -> some View { environment(\.lineLimit, number) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/multilinetextalignment(_:)
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { environment(\.multilineTextAlignment, alignment) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/truncationmode(_:)
    public func truncationMode(_ mode: Text.TruncationMode) -> some View { environment(\.truncationMode, mode) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)
    public func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View { _EnvironmentView(content: self) { if let c = colorScheme { $0.colorScheme = c } } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/minimumscalefactor(_:)
    public func minimumScaleFactor(_ factor: CGFloat) -> some View { environment(\.minimumScaleFactor, factor) }
}

// MARK: Decorations

/// A view with background/overlay children, border, corner radius, clipping and opacity.
@MainActor
final class _DecorationPrimitive: _Primitive {
    struct Style {
        var cornerRadius: CGFloat = 0
        var clipShape: AnyShape? = nil
        var clips = false
        var borderColor: Color? = nil
        var borderWidth: CGFloat = 0
        var opacity: CGFloat = 1
        var hidden = false
        var tap: (() -> Void)? = nil
        var tapCount = 1
        var hover: ((Bool) -> Void)? = nil
        var helpText: String? = nil
        // Animatable geometry and the transition used on insertion/removal.
        var offset = CGSize.zero
        var scale = CGSize(width: 1, height: 1)
        var rotation = Angle.zero
        var anchor = UnitPoint.center
        var transition: AnyTransition? = nil
    }
    var style: Style
    /// Children: [background?, content, overlay?]; these flags say which are present.
    var hasBackground: Bool
    var hasOverlay: Bool
    var backgroundAlignment: Alignment
    var overlayAlignment: Alignment
    private let view = _ContainerView(frame: .zero)

    init(content: _AnyViewBox, background: _AnyViewBox?, overlay: _AnyViewBox?, backgroundAlignment: Alignment = .center, overlayAlignment: Alignment = .center, style: Style) {
        self.style = style
        hasBackground = background != nil
        hasOverlay = overlay != nil
        self.backgroundAlignment = backgroundAlignment
        self.overlayAlignment = overlayAlignment
        super.init()
        children = [background, content, overlay].compactMap { $0 }
    }

    override var nsView: NSView? { view }

    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _DecorationPrimitive else { return }
        retargetAnimations(to: o.style)
        style = o.style
        hasBackground = o.hasBackground
        hasOverlay = o.hasOverlay
        backgroundAlignment = o.backgroundAlignment
        overlayAlignment = o.overlayAlignment
        apply()
    }

    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        node.transition = style.transition
        node.presentation.opacity = style.opacity
        node.presentation.offset = style.offset
        node.presentation.scale = style.scale
        node.presentation.rotation = CGFloat(style.rotation.radians)
        apply()
    }

    /// Animates the properties that changed under the pass's animation; otherwise the
    /// presentation jumps to the new model values.
    private func retargetAnimations(to new: Style) {
        guard let node else { return }
        node.transition = new.transition
        let anim = node.effectiveAnimation
        func running(_ p: _Presentation.Property) -> Bool { node.runningAnimations.contains { $0.property == p } }
        if new.opacity != style.opacity || running(.opacity) {
            if let anim, new.opacity != style.opacity { node.animate(.opacity, from: [node.presentation.opacity], to: [new.opacity], with: anim) }
            else if !running(.opacity) { node.presentation.opacity = new.opacity }
        } else { node.presentation.opacity = new.opacity }
        if new.offset != style.offset {
            if let anim { node.animate(.offset, from: [node.presentation.offset.width, node.presentation.offset.height], to: [new.offset.width, new.offset.height], with: anim) }
            else { node.presentation.offset = new.offset }
        } else if !running(.offset) { node.presentation.offset = new.offset }
        if new.scale != style.scale {
            if let anim { node.animate(.scale, from: [node.presentation.scale.width, node.presentation.scale.height], to: [new.scale.width, new.scale.height], with: anim) }
            else { node.presentation.scale = new.scale }
        } else if !running(.scale) { node.presentation.scale = new.scale }
        if new.rotation != style.rotation {
            if let anim { node.animate(.rotation, from: [node.presentation.rotation], to: [CGFloat(new.rotation.radians)], with: anim) }
            else { node.presentation.rotation = CGFloat(new.rotation.radians) }
        } else if !running(.rotation) { node.presentation.rotation = CGFloat(new.rotation.radians) }
    }

    /// Applies the node's presentation (animated values and transition state) to the view.
    private func applyPresentation() {
        guard let node else { return }
        let p = node.presentation
        let t = min(1, max(0, p.transition))
        let spec = style.transition.map { node.isExiting ? $0.removal : $0.insertion } ?? .identity
        let size = view.bounds.size
        var edgeOffset = CGSize.zero
        switch spec.edge {
        case .leading: edgeOffset.width = -size.width
        case .trailing: edgeOffset.width = size.width
        case .top: edgeOffset.height = -size.height
        case .bottom: edgeOffset.height = size.height
        case nil: break
        }
        let opacity = p.opacity * (spec.opacity + (1 - spec.opacity) * t)
        let scale = CGSize(width: p.scale.width * (spec.scale + (1 - spec.scale) * t), height: p.scale.height * (spec.scale + (1 - spec.scale) * t))
        let offset = CGSize(width: p.offset.width + (spec.offset.width + edgeOffset.width) * (1 - t), height: p.offset.height + (spec.offset.height + edgeOffset.height) * (1 - t))
        let anchor = t < 1 && spec.scale != 1 ? spec.scaleAnchor : style.anchor
        let ax = size.width * anchor.x, ay = size.height * anchor.y
        var transform = CGAffineTransform(translationX: -ax, y: -ay)
            .concatenating(CGAffineTransform(scaleX: scale.width, y: scale.height))
            .concatenating(CGAffineTransform(rotationAngle: p.rotation))
            .concatenating(CGAffineTransform(translationX: ax + offset.width, y: ay + offset.height))
        if abs(transform.a - 1) < 1e-9, abs(transform.d - 1) < 1e-9, abs(transform.b) < 1e-9, abs(transform.c) < 1e-9, abs(transform.tx) < 1e-9, abs(transform.ty) < 1e-9 { transform = .identity }
        if view.alphaValue != opacity { view.alphaValue = opacity }
        if transform != .identity || view.layer != nil {
            if view.layer == nil { view.wantsLayer = true }
            if let l = view.layer, l.affineTransform() != transform {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.setAffineTransform(transform)
                CATransaction.commit()
            }
        }
    }

    private func apply() {
        view.alphaValue = style.opacity
        view.isHidden = style.hidden
        let clipping = style.clips || style.cornerRadius > 0 || style.clipShape != nil
        if clipping { view.wantsLayer = true }
        view.clipsToBounds = clipping
        view.layer?.cornerRadius = style.clipShape == nil ? style.cornerRadius : 0
        view.layer?.masksToBounds = clipping
        view.toolTip = style.helpText
        if let tap = style.tap {
            let count = style.tapCount
            view.mouseDownHandler = { event in
                guard event.clickCount >= count else { return count == 1 }
                tap()
                return true
            }
        } else {
            view.mouseDownHandler = nil
        }
        view.hoverHandler = style.hover
        view.drawHandler = { [weak self] _, v in self?.draw(in: v) }
        view.needsDisplay = true
    }

    private func draw(in v: NSView) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = v.bounds
        if let shape = style.clipShape {
            ctx.addPath(shape.path(in: b).cgPath)
            ctx.clip()
        }
        if let color = style.borderColor, style.borderWidth > 0 {
            ctx.setStrokeColor(color.nsColor.cgColor)
            ctx.setLineWidth(style.borderWidth)
            let r = b.insetBy(dx: style.borderWidth / 2, dy: style.borderWidth / 2)
            if style.cornerRadius > 0 {
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: style.cornerRadius, cornerHeight: style.cornerRadius, transform: nil))
            } else {
                ctx.addRect(r)
            }
            ctx.strokePath()
        }
    }

    private var contentNode: _ViewNode? { node?.children.indices.contains(hasBackground ? 1 : 0) == true ? node!.children[hasBackground ? 1 : 0] : nil }

    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        contentNode?.sizeThatFits(proposal) ?? .zero
    }

    override func place(node: _ViewNode, in rect: CGRect) {
        let content = contentNode
        content?.place(in: rect)
        let decorations = node.children.filter { $0 !== content }
        for (i, d) in decorations.enumerated() {
            let alignment = (i == 0 && hasBackground) ? backgroundAlignment : overlayAlignment
            let s = d.sizeThatFits(ProposedViewSize(rect.size))
            d.place(in: CGRect(origin: alignment.origin(of: s, in: rect), size: s).integralIfNeeded)
        }
    }

    override func didLayout(node: _ViewNode) { view.needsDisplay = true }
    override func didSyncBackingViews(node: _ViewNode) { applyPresentation() }
}

struct _Decorated<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    var background: _AnyViewBox? = nil
    var overlay: _AnyViewBox? = nil
    var backgroundAlignment: Alignment = .center
    var overlayAlignment: Alignment = .center
    var style = _DecorationPrimitive.Style()
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _DecorationPrimitive(content: _ViewBox(content), background: background, overlay: overlay, backgroundAlignment: backgroundAlignment, overlayAlignment: overlayAlignment, style: style)
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/background(_:alignment:)
    public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View {
        var d = _Decorated(content: self)
        d.background = _ViewBox(background)
        d.backgroundAlignment = alignment
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/background(alignment:content:)
    public func background<Background: View>(alignment: Alignment = .center, @ViewBuilder content: () -> Background) -> some View {
        background(content(), alignment: alignment)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/overlay(_:alignment:)
    public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View {
        var d = _Decorated(content: self)
        d.overlay = _ViewBox(overlay)
        d.overlayAlignment = alignment
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/overlay(alignment:content:)
    public func overlay<Overlay: View>(alignment: Alignment = .center, @ViewBuilder content: () -> Overlay) -> some View {
        overlay(content(), alignment: alignment)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/cornerradius(_:antialiased:)
    public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
        var d = _Decorated(content: self)
        d.style.cornerRadius = radius
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/border(_:width:)
    public func border(_ color: Color, width: CGFloat = 1) -> some View {
        var d = _Decorated(content: self)
        d.style.borderColor = color
        d.style.borderWidth = width
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/opacity(_:)
    public func opacity(_ opacity: Double) -> some View {
        var d = _Decorated(content: self)
        d.style.opacity = CGFloat(opacity)
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/hidden()
    public func hidden() -> some View {
        var d = _Decorated(content: self)
        d.style.hidden = true
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/clipped(antialiased:)
    public func clipped(antialiased: Bool = false) -> some View {
        var d = _Decorated(content: self)
        d.style.clips = true
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/clipshape(_:style:)
    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        var d = _Decorated(content: self)
        d.style.clipShape = AnyShape(shape)
        d.style.clips = true
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:perform:)
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        var d = _Decorated(content: self)
        d.style.tap = action
        d.style.tapCount = count
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onhover(perform:)
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        var d = _Decorated(content: self)
        d.style.hover = action
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/help(_:)-9swnr
    public func help(_ text: String) -> some View {
        var d = _Decorated(content: self)
        d.style.helpText = text
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/shadow(color:radius:x:y:)
    public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
}

// MARK: Lifecycle hooks

@MainActor
final class _LifecyclePrimitive: _Primitive {
    var appear: (() -> Void)?
    var disappear: (() -> Void)?
    init(appear: (() -> Void)?, disappear: (() -> Void)?, content: _AnyViewBox) {
        self.appear = appear
        self.disappear = disappear
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _LifecyclePrimitive, let node else { return }
        appear = o.appear; disappear = o.disappear
        node.onAppear = appear.map { [$0] } ?? []
        node.onDisappear = disappear.map { [$0] } ?? []
    }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        node.onAppear = appear.map { [$0] } ?? []
        node.onDisappear = disappear.map { [$0] } ?? []
    }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onappear(perform:)
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        _LayoutModified(content: self) { _LifecyclePrimitive(appear: action, disappear: nil, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/ondisappear(perform:)
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        _LayoutModified(content: self) { _LifecyclePrimitive(appear: nil, disappear: action, content: $0) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-8wgw9
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some View {
        _OnChange(content: self, value: value, initial: initial, action: { _, _ in action() })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-4psgg
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some View {
        _OnChange(content: self, value: value, initial: initial, action: action)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/onchange(of:perform:)
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        _OnChange(content: self, value: value, initial: false, action: { _, new in action(new) })
    }
}

@MainActor
final class _OnChangePrimitive<V: Equatable>: _Primitive {
    var value: V
    var action: (V, V) -> Void
    var initial: Bool
    var seeded = false
    init(value: V, initial: Bool, action: @escaping (V, V) -> Void, content: _AnyViewBox) {
        self.value = value; self.initial = initial; self.action = action
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        if initial { action(value, value) }
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _OnChangePrimitive<V> else { return }
        let old = value
        action = o.action
        value = o.value
        if old != o.value { action(old, o.value) }
    }
}

struct _OnChange<Content: View, V: Equatable>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let value: V
    let initial: Bool
    let action: (V, V) -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive { _OnChangePrimitive(value: value, initial: initial, action: action, content: _ViewBox(content)) }
}

// MARK: No-op compatibility modifiers

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationtitle(_:)-43srq
    public func navigationTitle(_ title: String) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv
    public func accessibilityLabel(_ label: String) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:)
    public func accessibilityHidden(_ hidden: Bool) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/tag(_:)
    public func tag<V: Hashable>(_ tag: V) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/buttonstyle(_:)-7qx1
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View { environment(\.buttonStyle, style.kind) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/textfieldstyle(_:)
    public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View { environment(\.textFieldStyle, style.kind) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/togglestyle(_:)
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/liststyle(_:)
    public func listStyle<S: ListStyle>(_ style: S) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/controlsize(_:)
    public func controlSize(_ size: ControlSize) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/labelshidden()
    public func labelsHidden() -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/keyboardshortcut(_:modifiers:)
    public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View { _KeyShortcut(content: self, key: key, modifiers: modifiers) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/controlsize
public enum ControlSize: CaseIterable, Hashable, Sendable { case mini, small, regular, large, extraLarge }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/keyequivalent
public struct KeyEquivalent: Hashable, Sendable, ExpressibleByExtendedGraphemeClusterLiteral {
    public var character: Character
    public init(_ character: Character) { self.character = character }
    public init(extendedGraphemeClusterLiteral value: Character) { character = value }
    public static let `return` = KeyEquivalent("\r")
    public static let escape = KeyEquivalent("\u{1B}")
    public static let space = KeyEquivalent(" ")
    public static let tab = KeyEquivalent("\t")
    public static let delete = KeyEquivalent("\u{7F}")
    public static let defaultAction = KeyEquivalent("\r")
    public static let cancelAction = KeyEquivalent("\u{1B}")
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/eventmodifiers
public struct EventModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let capsLock = EventModifiers(rawValue: 1)
    public static let shift = EventModifiers(rawValue: 2)
    public static let control = EventModifiers(rawValue: 4)
    public static let option = EventModifiers(rawValue: 8)
    public static let command = EventModifiers(rawValue: 16)
    public static let numericPad = EventModifiers(rawValue: 32)
    public static let all: EventModifiers = [.capsLock, .shift, .control, .option, .command, .numericPad]
}

struct _KeyShortcut<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let key: KeyEquivalent
    let modifiers: EventModifiers
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        let p = _GroupPrimitive(children: [_ViewBox(content)])
        p.environmentTransform = { $0._keyShortcut = (self.key, self.modifiers) }
        return p
    }
}

extension EnvironmentValues {
    private struct ButtonStyleKey: EnvironmentKey { static let defaultValue: _ButtonStyleKind = .automatic }
    private struct TextFieldStyleKey: EnvironmentKey { static let defaultValue: _TextFieldStyleKind = .automatic }
    private struct KeyShortcutKey: EnvironmentKey { static let defaultValue: (KeyEquivalent, EventModifiers)? = nil }
    var buttonStyle: _ButtonStyleKind { get { self[ButtonStyleKey.self] } set { self[ButtonStyleKey.self] = newValue } }
    var textFieldStyle: _TextFieldStyleKind { get { self[TextFieldStyleKey.self] } set { self[TextFieldStyleKey.self] = newValue } }
    var _keyShortcut: (KeyEquivalent, EventModifiers)? { get { self[KeyShortcutKey.self] } set { self[KeyShortcutKey.self] = newValue } }
}

public enum _ButtonStyleKind: Sendable { case automatic, bordered, borderedProminent, borderless, plain, link }
public enum _TextFieldStyleKind: Sendable { case automatic, roundedBorder, plain, squareBorder }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/primitivebuttonstyle
public protocol PrimitiveButtonStyle { var kind: _ButtonStyleKind { get } }
public struct DefaultButtonStyle: PrimitiveButtonStyle { public init() {}; public var kind: _ButtonStyleKind { .automatic } }
public struct BorderedButtonStyle: PrimitiveButtonStyle { public init() {}; public var kind: _ButtonStyleKind { .bordered } }
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle { public init() {}; public var kind: _ButtonStyleKind { .borderedProminent } }
public struct BorderlessButtonStyle: PrimitiveButtonStyle { public init() {}; public var kind: _ButtonStyleKind { .borderless } }
public struct PlainButtonStyle: PrimitiveButtonStyle { public init() {}; public var kind: _ButtonStyleKind { .plain } }
public struct LinkButtonStyle: PrimitiveButtonStyle { public init() {}; public var kind: _ButtonStyleKind { .link } }
extension PrimitiveButtonStyle where Self == DefaultButtonStyle { public static var automatic: DefaultButtonStyle { DefaultButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { BorderedButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle { public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() } }
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle { public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() } }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { PlainButtonStyle() } }
extension PrimitiveButtonStyle where Self == LinkButtonStyle { public static var link: LinkButtonStyle { LinkButtonStyle() } }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/textfieldstyle
public protocol TextFieldStyle { var kind: _TextFieldStyleKind { get } }
public struct DefaultTextFieldStyle: TextFieldStyle { public init() {}; public var kind: _TextFieldStyleKind { .automatic } }
public struct RoundedBorderTextFieldStyle: TextFieldStyle { public init() {}; public var kind: _TextFieldStyleKind { .roundedBorder } }
public struct PlainTextFieldStyle: TextFieldStyle { public init() {}; public var kind: _TextFieldStyleKind { .plain } }
public struct SquareBorderTextFieldStyle: TextFieldStyle { public init() {}; public var kind: _TextFieldStyleKind { .squareBorder } }
extension TextFieldStyle where Self == DefaultTextFieldStyle { public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() } }
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle { public static var roundedBorder: RoundedBorderTextFieldStyle { RoundedBorderTextFieldStyle() } }
extension TextFieldStyle where Self == PlainTextFieldStyle { public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() } }
extension TextFieldStyle where Self == SquareBorderTextFieldStyle { public static var squareBorder: SquareBorderTextFieldStyle { SquareBorderTextFieldStyle() } }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/togglestyle
public protocol ToggleStyle {}
public struct DefaultToggleStyle: ToggleStyle { public init() {} }
public struct SwitchToggleStyle: ToggleStyle { public init() {} }
public struct CheckboxToggleStyle: ToggleStyle { public init() {} }
extension ToggleStyle where Self == DefaultToggleStyle { public static var automatic: DefaultToggleStyle { DefaultToggleStyle() } }
extension ToggleStyle where Self == SwitchToggleStyle { public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() } }
extension ToggleStyle where Self == CheckboxToggleStyle { public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() } }

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/liststyle
public protocol ListStyle {}
public struct DefaultListStyle: ListStyle { public init() {} }
public struct PlainListStyle: ListStyle { public init() {} }
public struct SidebarListStyle: ListStyle { public init() {} }
public struct InsetListStyle: ListStyle { public init() {} }
public struct BorderedListStyle: ListStyle { public init() {} }
extension ListStyle where Self == DefaultListStyle { public static var automatic: DefaultListStyle { DefaultListStyle() } }
extension ListStyle where Self == PlainListStyle { public static var plain: PlainListStyle { PlainListStyle() } }
extension ListStyle where Self == SidebarListStyle { public static var sidebar: SidebarListStyle { SidebarListStyle() } }
extension ListStyle where Self == InsetListStyle { public static var inset: InsetListStyle { InsetListStyle() } }
extension ListStyle where Self == BorderedListStyle { public static var bordered: BorderedListStyle { BorderedListStyle() } }
