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
        /// `.shadow(color:radius:x:y:)`: drawn by the view's layer (offset in the view's y-down space).
        var shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)? = nil
        var tap: (() -> Void)? = nil
        var tapCount = 1
        var hover: ((Bool) -> Void)? = nil
        /// `.gesture`/`.highPriorityGesture`: recognizers installed on the decoration view.
        var gestures: [_GestureInstaller] = []
        var gesturesDelayEvents = false
        var pressingChanged: ((Bool) -> Void)? = nil
        var helpText: String? = nil
        // Animatable geometry and the transition used on insertion/removal.
        var offset = CGSize.zero
        var scale = CGSize(width: 1, height: 1)
        var rotation = Angle.zero
        var anchor = UnitPoint.center
        var rotation3D: _Rotation3D? = nil
        var blendMode: BlendMode = .normal
        var transition: AnyTransition? = nil
    }
    /// `.rotation3DEffect`: a rotation about `axis` through `anchor`, with perspective.
    struct _Rotation3D: Equatable {
        var angle: Angle
        var axisX: CGFloat, axisY: CGFloat, axisZ: CGFloat
        var anchor: UnitPoint
        var anchorZ: CGFloat
        var perspective: CGFloat
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
        node.presentation.rotation3D = CGFloat(style.rotation3D?.angle.radians ?? 0)
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
        let angle3D = CGFloat(new.rotation3D?.angle.radians ?? 0)
        if new.rotation3D?.angle != style.rotation3D?.angle {
            if let anim { node.animate(.rotation3D, from: [node.presentation.rotation3D], to: [angle3D], with: anim) }
            else { node.presentation.rotation3D = angle3D }
        } else if !running(.rotation3D) { node.presentation.rotation3D = angle3D }
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
        if transform != .identity || style.rotation3D != nil || view.layer != nil {
            if view.layer == nil { view.wantsLayer = true }
            var t3 = CATransform3DMakeAffineTransform(transform)
            if let r = style.rotation3D {
                // Rotate about the anchor first (with the vanishing point in front of it),
                // then apply the 2D offset/scale/rotation.
                let rx = size.width * r.anchor.x, ry = size.height * r.anchor.y
                var m = CATransform3DMakeTranslation(-rx, -ry, -r.anchorZ)
                m = CATransform3DConcat(m, CATransform3DMakeRotation(p.rotation3D, r.axisX, r.axisY, r.axisZ))
                if r.perspective != 0 {
                    var persp = CATransform3DIdentity
                    persp.m34 = -r.perspective / max(1, max(size.width, size.height) * 2.5)
                    m = CATransform3DConcat(m, persp)
                }
                m = CATransform3DConcat(m, CATransform3DMakeTranslation(rx, ry, r.anchorZ))
                t3 = CATransform3DConcat(m, t3)
            }
            if let l = view.layer, !CATransform3DEqualToTransform(l.transform, t3) {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.transform = t3
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
        if let shadow = style.shadow {
            view.wantsLayer = true
            if let l = view.layer {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.shadowColor = shadow.color.nsColor.cgColor
                l.shadowOpacity = 1
                l.shadowRadius = shadow.radius
                l.shadowOffset = CGSize(width: shadow.x, height: shadow.y)
                CATransaction.commit()
            }
        } else if let l = view.layer, l.shadowOpacity > 0 {
            l.shadowOpacity = 0
        }
        view.toolTip = style.helpText
        if let name = style.blendMode.compositingFilterName {
            view.wantsLayer = true
            view.layer?.compositingFilter = name
        } else if let l = view.layer, l.compositingFilter != nil {
            l.compositingFilter = nil
        }
        if let tap = style.tap {
            // A tap fires on release, as in SwiftUI (and like an AppKit click); the press
            // arms it, and moving away or a long press taking the release disarms it.
            let count = style.tapCount
            var armed: NSPoint? = nil
            view.mouseDownHandler = { event in
                armed = event.clickCount >= count ? event.locationInWindow : nil
                return true
            }
            view.mouseUpHandler = { [weak view] event in
                guard let view, let start = armed else { return }
                armed = nil
                let p = event.locationInWindow
                guard abs(p.x - start.x) <= 4, abs(p.y - start.y) <= 4, view.bounds.contains(view.convert(p, from: nil)) else { return }
                tap()
            }
        } else {
            view.mouseDownHandler = nil
            view.mouseUpHandler = nil
        }
        view.hoverHandler = style.hover
        // Recognizers survive re-renders (a drag that moves the view re-renders every
        // event): each installer reuses the recognizer at its index when the kind matches.
        let previous = view.installedRecognizers
        view.installedRecognizers = style.gestures.enumerated().compactMap { i, g in g.install(view, i < previous.count ? previous[i] : nil) }
        for r in previous where !view.installedRecognizers.contains(where: { $0 === r }) { view.removeGestureRecognizer(r) }
        for r in view.installedRecognizers {
            if r.view !== view { view.addGestureRecognizer(r) }
            r.delaysPrimaryMouseButtonEvents = style.gesturesDelayEvents
            if let pressing = style.pressingChanged, let press = r as? NSPressGestureRecognizer {
                let inner = press._actionHandler
                press._actionHandler = { r in
                    inner?(r)
                    switch r.state {
                    case .began: pressing(true)
                    case .ended, .cancelled, .failed: pressing(false)
                    default: break
                    }
                }
            }
        }
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
            d.place(in: CGRect(origin: alignment.origin(of: s, in: rect, direction: node.environment.layoutDirection), size: s).integralIfNeeded)
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
    public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        var d = _Decorated(content: self)
        d.style.shadow = (color, radius, x, y)
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/rotation3deffect(_:axis:anchor:anchorz:perspective:)
    public func rotation3DEffect(_ angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center, anchorZ: CGFloat = 0, perspective: CGFloat = 1) -> some View {
        var d = _Decorated(content: self)
        d.style.rotation3D = _DecorationPrimitive._Rotation3D(angle: angle, axisX: axis.x, axisY: axis.y, axisZ: axis.z, anchor: anchor, anchorZ: anchorZ, perspective: perspective)
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/blendmode(_:)
    /// The mode is set as the backing layer's compositing filter; the software and
    /// DirectComposition compositors do not apply it yet (docs/ROADMAP.md).
    public func blendMode(_ blendMode: BlendMode) -> some View {
        var d = _Decorated(content: self)
        d.style.blendMode = blendMode
        return d
    }
}

// MARK: Tasks

/// `.task`: an asynchronous task started when the view appears and cancelled when it
/// disappears or its id changes.
@MainActor
final class _TaskPrimitive: _Primitive {
    var id: AnyHashable?
    var priority: TaskPriority
    var action: @Sendable () async -> Void
    private var task: Task<Void, Never>?
    private var running = false
    init(id: AnyHashable?, priority: TaskPriority, action: @escaping @Sendable () async -> Void, content: _AnyViewBox) {
        self.id = id; self.priority = priority; self.action = action
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    private func start() {
        task?.cancel()
        let action = action
        task = Task(priority: priority) { await action() }
        running = true
    }
    private func stop() { task?.cancel(); task = nil; running = false }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        node.onAppear = [{ [weak self] in self?.start() }]
        node.onDisappear = [{ [weak self] in self?.stop() }]
    }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _TaskPrimitive else { return }
        let changed = o.id != id
        id = o.id; priority = o.priority; action = o.action
        if changed, running { start() }
    }
    override func detach() { super.detach(); stop() }
}

struct _TaskView<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let id: AnyHashable?
    let priority: TaskPriority
    let action: @Sendable () async -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive { _TaskPrimitive(id: id, priority: priority, action: action, content: _ViewBox(content)) }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/task(priority:_:)
    public func task(priority: TaskPriority = .userInitiated, @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> some View {
        _TaskView(content: self, id: nil, priority: priority, action: action)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/task(id:priority:_:)
    public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated, @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> some View {
        _TaskView(content: self, id: _EquatableBox(value), priority: priority, action: action)
    }
}

/// An `Equatable` value as `AnyHashable` (for change detection only).
struct _EquatableBox<T: Equatable>: Hashable {
    let value: T
    init(_ value: T) { self.value = value }
    static func == (a: _EquatableBox, b: _EquatableBox) -> Bool { a.value == b.value }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(T.self)) }
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

// MARK: Accessibility (ADR-0013)

/// What the accessibility modifiers set on the content's backing AppKit views: the
/// first backing view carries the label, value, identifier and hint; `hidden` applies
/// to all of them, so a hidden stack hides every control in it.
@MainActor
final class _AccessibilityPrimitive: _Primitive {
    struct Traits {
        var label: String? = nil
        var value: String? = nil
        var hidden: Bool? = nil
        var identifier: String? = nil
        var hint: String? = nil
        var isElement: Bool? = nil
    }
    var traits: Traits
    init(traits: Traits, content: _AnyViewBox) {
        self.traits = traits
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        if let o = other as? _AccessibilityPrimitive { traits = o.traits }
        apply()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); apply() }
    override func didSyncBackingViews(node: _ViewNode) { apply() }
    /// The backing views the content produced, in tree order.
    var backingViews: [NSView] {
        var views: [NSView] = []
        for c in node?.children ?? [] { c.collectBackingViews(into: &views) }
        return views
    }
    private func apply() {
        for (i, v) in backingViews.enumerated() {
            if let h = traits.hidden, v.isAccessibilityHidden() != h { v.setAccessibilityHidden(h) }
            guard i == 0 else { continue }
            if let l = traits.label, v.accessibilityLabel() != l { v.setAccessibilityLabel(l) }
            if let value = traits.value, (v.accessibilityValue() as? String) != value { v.setAccessibilityValue(value) }
            if let id = traits.identifier { v.setAccessibilityIdentifier(id) }
            if let hint = traits.hint { v.setAccessibilityHelp(hint) }
            if let e = traits.isElement { v.setAccessibilityElement(e) }
        }
    }
}

struct _AccessibilityModified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    var traits: _AccessibilityPrimitive.Traits
    func _makePrimitive(node: _ViewNode) -> _Primitive { _AccessibilityPrimitive(traits: traits, content: _ViewBox(content)) }
}

extension View {
    private func _accessibility(_ change: (inout _AccessibilityPrimitive.Traits) -> Void) -> some View {
        var t = _AccessibilityPrimitive.Traits()
        change(&t)
        return _AccessibilityModified(content: self, traits: t)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-1d7jv
    public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View { _accessibility { $0.label = String(label) } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-7i9lv
    public func accessibilityLabel(_ label: Text) -> some View { _accessibility { $0.label = label._string } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilitylabel(_:)-8mc9b
    public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> some View { _accessibility { $0.label = Text(labelKey)._string } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:)-6q3vd
    public func accessibilityValue<S: StringProtocol>(_ value: S) -> some View { _accessibility { $0.value = String(value) } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:)-7nxay
    public func accessibilityValue(_ value: Text) -> some View { _accessibility { $0.value = value._string } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:)-4w8xl
    public func accessibilityValue(_ valueKey: LocalizedStringKey) -> some View { _accessibility { $0.value = Text(valueKey)._string } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:)
    public func accessibilityHidden(_ hidden: Bool) -> some View { _accessibility { $0.hidden = hidden } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier(_:)
    public func accessibilityIdentifier(_ identifier: String) -> some View { _accessibility { $0.identifier = identifier } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:)-1k7dv
    public func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View { _accessibility { $0.hint = String(hint) } }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/accessibilityhint(_:)-6fdn0
    public func accessibilityHint(_ hint: Text) -> some View { _accessibility { $0.hint = hint._string } }
}

// MARK: No-op compatibility modifiers

extension View {
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

struct _KeyShortcut<Content: View>: View, _PrimitiveView, _MetadataView {
    typealias Body = Never
    let content: Content
    let key: KeyEquivalent
    let modifiers: EventModifiers
    var _metaContent: _AnyViewBox { _ViewBox(content) }
    func _apply(to meta: inout _ItemMetadata) { if meta.keyShortcut == nil { meta.keyShortcut = (key, modifiers) } }
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
