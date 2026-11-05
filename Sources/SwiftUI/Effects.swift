// Gradients, masks, blend modes, redaction and 3D rotation: the drawing effects the
// third-party library compatibility example (Examples/LibraryCompat) found missing.

import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

// MARK: Gradient

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/gradient
public struct Gradient: Equatable, Hashable, Sendable {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/gradient/stop
    public struct Stop: Equatable, Hashable, Sendable {
        public var color: Color
        public var location: CGFloat
        public init(color: Color, location: CGFloat) { self.color = color; self.location = location }
    }
    public var stops: [Stop]
    public init(stops: [Stop]) { self.stops = stops }
    public init(colors: [Color]) {
        let n = max(1, colors.count - 1)
        stops = colors.enumerated().map { Stop(color: $1, location: CGFloat($0) / CGFloat(n)) }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/lineargradient
public struct LinearGradient: ShapeStyle, View, _PrimitiveView, Sendable, Equatable {
    public typealias Body = Never
    let gradient: Gradient
    let startPoint: UnitPoint
    let endPoint: UnitPoint
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        self.gradient = gradient; self.startPoint = startPoint; self.endPoint = endPoint
    }
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(colors: colors), startPoint: startPoint, endPoint: endPoint)
    }
    public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
    }
    public func _makePrimitive(node: _ViewNode) -> _Primitive { _GradientPrimitive(gradient: self) }
    @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) {
        _drawLinearGradient(context, path: path, in: rect, stops: _resolvedStops(environment), start: startPoint, end: endPoint)
    }
    @MainActor func _resolvedStops(_ env: EnvironmentValues) -> [_GradientStop] {
        gradient.stops.map { s in
            let c = s.color.storage == .named("primary") ? (env.foregroundColor ?? s.color) : s.color
            let ns = c.nsColor
            return _GradientStop(location: s.location, r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent)
        }
    }
}

struct _GradientStop { var location: CGFloat; var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat }

/// The colour of a gradient at `t` (clamped at the ends).
func _gradientColor(_ stops: [_GradientStop], at t: CGFloat) -> CGColor {
    guard let first = stops.first else { return NSColor.clear.cgColor }
    var lo = first, hi = first
    for s in stops {
        if s.location <= t { lo = s }
        if s.location >= t { hi = s; break }
        hi = s
    }
    let span = hi.location - lo.location
    let f = span > 0 ? min(1, max(0, (t - lo.location) / span)) : 0
    return NSColor(red: lo.r + (hi.r - lo.r) * f, green: lo.g + (hi.g - lo.g) * f, blue: lo.b + (hi.b - lo.b) * f, alpha: lo.a + (hi.a - lo.a) * f).cgColor
}

/// Draws a linear gradient inside `path` as bands along the axis from `start` to `end`
/// (unit points of `rect`). CoreGraphics on Windows and Linux has no CGGradient yet
/// (docs/ROADMAP.md), so the bands stand in on every platform.
func _drawLinearGradient(_ ctx: CGContext, path: CGPath, in rect: CGRect, stops: [_GradientStop], start: UnitPoint, end: UnitPoint) {
    guard !stops.isEmpty, rect.width > 0, rect.height > 0 else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip(using: .winding)
    let p0 = CGPoint(x: rect.minX + start.x * rect.width, y: rect.minY + start.y * rect.height)
    let p1 = CGPoint(x: rect.minX + end.x * rect.width, y: rect.minY + end.y * rect.height)
    let dx = p1.x - p0.x, dy = p1.y - p0.y
    let len = (dx * dx + dy * dy).squareRoot()
    let reach = (rect.width * rect.width + rect.height * rect.height).squareRoot() * 2 + 1
    ctx.translateBy(x: p0.x, y: p0.y)
    if len > 0.01 { ctx.rotate(by: atan2(dy, dx)) }
    ctx.setFillColor(_gradientColor(stops, at: 0))
    ctx.fill(CGRect(x: -reach, y: -reach, width: reach, height: 2 * reach))
    ctx.setFillColor(_gradientColor(stops, at: 1))
    ctx.fill(CGRect(x: len, y: -reach, width: reach, height: 2 * reach))
    if len > 0.01 {
        let bands = Int(min(256, max(16, len)))
        for i in 0..<bands {
            let t0 = CGFloat(i) / CGFloat(bands), t1 = CGFloat(i + 1) / CGFloat(bands)
            ctx.setFillColor(_gradientColor(stops, at: (t0 + t1) / 2))
            ctx.fill(CGRect(x: t0 * len - 0.25, y: -reach, width: (t1 - t0) * len + 0.5, height: 2 * reach))
        }
    }
    ctx.restoreGState()
}

/// A `LinearGradient` used as a view: fills its bounds; the start and end points animate
/// under `withAnimation` and `.animation(_:value:)`.
@MainActor
final class _GradientPrimitive: _Primitive {
    var gradient: LinearGradient
    let view = _ShapeDrawingView(frame: .zero)
    init(gradient: LinearGradient) { self.gradient = gradient }
    override var nsView: NSView? { view }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _GradientPrimitive, let node else { return }
        let new = o.gradient
        let from = node.presentation.custom ?? [gradient.startPoint.x, gradient.startPoint.y, gradient.endPoint.x, gradient.endPoint.y]
        let to = [new.startPoint.x, new.startPoint.y, new.endPoint.x, new.endPoint.y]
        if from != to {
            if let anim = node.effectiveAnimation { node.animate(.custom, from: from, to: to, with: anim) }
            else { node.presentation.custom = nil }
        }
        gradient = new
        install()
    }
    override func attach(to node: _ViewNode) { super.attach(to: node); install() }
    private func install() {
        guard let node else { return }
        let stops = gradient._resolvedStops(node.environment)
        let model = gradient
        view.draw = { [weak node] ctx, bounds in
            var start = model.startPoint, end = model.endPoint
            if let c = node?.presentation.custom, c.count == 4 { start = UnitPoint(x: c[0], y: c[1]); end = UnitPoint(x: c[2], y: c[3]) }
            _drawLinearGradient(ctx, path: CGPath(rect: bounds, transform: nil), in: bounds, stops: stops, start: start, end: end)
        }
        view.needsDisplay = true
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        CGSize(width: proposal.width.map { $0.isFinite ? $0 : 10 } ?? 10, height: proposal.height.map { $0.isFinite ? $0 : 10 } ?? 10)
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
    override func didLayout(node: _ViewNode) { view.needsDisplay = true }
    override func didSyncBackingViews(node: _ViewNode) { if !node.runningAnimations.isEmpty { view.needsDisplay = true } }
}

// MARK: Mask

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/mask(alignment:_:)
extension View {
    public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
        _Masked(content: self, mask: _ViewBox(mask()), alignment: alignment)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/mask(_:)
    public func mask<Mask: View>(_ mask: Mask) -> some View {
        _Masked(content: self, mask: _ViewBox(mask), alignment: .center)
    }
}

struct _Masked<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let mask: _AnyViewBox
    let alignment: Alignment
    func _makePrimitive(node: _ViewNode) -> _Primitive { _MaskPrimitive(content: _ViewBox(content), mask: mask, alignment: alignment) }
}

/// The content in a layer-backed container whose layer mask is the mask view hierarchy,
/// rendered offscreen into an image (the mask's backing views live in a host view that is
/// never in a window). The mask subtree is a node tree the primitive owns; the root walks
/// it through `extraNodes` so its animations run.
@MainActor
final class _MaskPrimitive: _Primitive {
    private let view = _ContainerView(frame: .zero)
    private let maskHost = _ContainerView(frame: .zero)
    private var maskBox: _AnyViewBox
    private var maskNode: _ViewNode?
    private var maskBoxChanged = true
    var alignment: Alignment

    init(content: _AnyViewBox, mask: _AnyViewBox, alignment: Alignment) {
        maskBox = mask
        self.alignment = alignment
        super.init()
        children = [content]
    }
    override var nsView: NSView? { view }
    override var extraNodes: [_ViewNode] { maskNode.map { [$0] } ?? [] }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _MaskPrimitive else { return }
        maskBox = o.maskBox
        alignment = o.alignment
        maskBoxChanged = true
    }
    override func attach(to node: _ViewNode) {
        super.attach(to: node)
        view.wantsLayer = true
        view.layer?.masksToBounds = true
    }
    override func detach() {
        super.detach()
        maskNode?.remove()
        maskNode = nil
    }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        node.children.first?.sizeThatFits(proposal) ?? .zero
    }
    override func place(node: _ViewNode, in rect: CGRect) {
        node.children.first?.place(in: rect)
        let m: _ViewNode
        if let existing = maskNode {
            m = existing
        } else {
            m = _ViewNode(box: maskBox, parent: node, root: node.root)
            m.isAttached = node.isAttached
            maskNode = m
            maskBoxChanged = true
        }
        m.parent = node
        m.update(box: maskBoxChanged ? maskBox : nil, environment: node.environment, force: maskBoxChanged)
        maskBoxChanged = false
        let s = m.sizeThatFits(ProposedViewSize(rect.size))
        m.place(in: CGRect(origin: alignment.origin(of: s, in: rect, direction: node.environment.layoutDirection), size: s).integralIfNeeded)
    }
    override func didLayout(node: _ViewNode) { view.needsDisplay = true }
    override func didSyncBackingViews(node: _ViewNode) {
        guard let m = maskNode else { return }
        let pf = node.presentedFrame
        maskHost.frame = CGRect(origin: .zero, size: pf.size)
        m.syncBackingViews(in: maskHost, containerFrame: pf)
        renderMask()
    }
    /// Rasterises the mask hierarchy and installs it as the container layer's mask.
    private func renderMask() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, let layer = view.layer else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        maskHost.cacheDisplay(in: maskHost.bounds, to: rep)
        guard let image = rep.cgImage else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let mask = layer.mask ?? CALayer()
        mask.frame = CGRect(origin: .zero, size: bounds.size)
        mask.contentsScale = layer.contentsScale
        mask.contents = image
        if layer.mask == nil { layer.mask = mask }
        CATransaction.commit()
    }
}

// MARK: Blend modes

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/blendmode
public enum BlendMode: Hashable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity
    case sourceAtop, destinationOver, destinationOut, plusDarker, plusLighter

    /// The Core Animation compositing filter name.
    var compositingFilterName: String? {
        switch self {
        case .normal: return nil
        case .multiply: return "multiplyBlendMode"
        case .screen: return "screenBlendMode"
        case .overlay: return "overlayBlendMode"
        case .darken: return "darkenBlendMode"
        case .lighten: return "lightenBlendMode"
        case .colorDodge: return "colorDodgeBlendMode"
        case .colorBurn: return "colorBurnBlendMode"
        case .softLight: return "softLightBlendMode"
        case .hardLight: return "hardLightBlendMode"
        case .difference: return "differenceBlendMode"
        case .exclusion: return "exclusionBlendMode"
        case .hue: return "hueBlendMode"
        case .saturation: return "saturationBlendMode"
        case .color: return "colorBlendMode"
        case .luminosity: return "luminosityBlendMode"
        case .sourceAtop: return "sourceAtopCompositing"
        case .destinationOver: return "destinationOverCompositing"
        case .destinationOut: return "destinationOutCompositing"
        case .plusDarker: return "darkenBlendMode"
        case .plusLighter: return "lightenBlendMode"
        }
    }
}

// MARK: Redaction

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/redactionreasons
public struct RedactionReasons: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let placeholder = RedactionReasons(rawValue: 1 << 0)
    public static let privacy = RedactionReasons(rawValue: 1 << 1)
    public static let invalidated = RedactionReasons(rawValue: 1 << 2)
}

extension EnvironmentValues {
    private struct RedactionReasonsKey: EnvironmentKey { static let defaultValue = RedactionReasons() }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/environmentvalues/redactionreasons
    public var redactionReasons: RedactionReasons { get { self[RedactionReasonsKey.self] } set { self[RedactionReasonsKey.self] = newValue } }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/redacted(reason:)
    public func redacted(reason: RedactionReasons) -> some View {
        _EnvironmentView(content: self) { $0.redactionReasons.formUnion(reason) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/unredacted()
    public func unredacted() -> some View { environment(\.redactionReasons, RedactionReasons()) }
}
