// Animations: timing curves, transactions, Animatable, transitions. The runtime
// interpolates node presentation values (frames, opacity, offset, scale, rotation,
// transition progress) on the host's display link; see Runtime.swift.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/animation
public struct Animation: Equatable, Sendable {
    enum Kind: Equatable { case linear, bezier(Double, Double, Double, Double), spring(response: Double, damping: Double) }
    let kind: Kind
    var duration: Double
    var delayValue: Double = 0
    var speedFactor: Double = 1
    var repeatsForever = false
    var repeatCount = 1
    var autoreverses = true

    init(kind: Kind, duration: Double) { self.kind = kind; self.duration = duration }

    public static let `default` = Animation(kind: .bezier(0.42, 0, 0.58, 1), duration: 0.35)
    public static func linear(duration: Double = 0.35) -> Animation { Animation(kind: .linear, duration: duration) }
    public static var linear: Animation { linear() }
    public static func easeIn(duration: Double = 0.35) -> Animation { Animation(kind: .bezier(0.42, 0, 1, 1), duration: duration) }
    public static var easeIn: Animation { easeIn() }
    public static func easeOut(duration: Double = 0.35) -> Animation { Animation(kind: .bezier(0, 0, 0.58, 1), duration: duration) }
    public static var easeOut: Animation { easeOut() }
    public static func easeInOut(duration: Double = 0.35) -> Animation { Animation(kind: .bezier(0.42, 0, 0.58, 1), duration: duration) }
    public static var easeInOut: Animation { easeInOut() }
    public static func timingCurve(_ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double, duration: Double = 0.35) -> Animation {
        Animation(kind: .bezier(c0x, c0y, c1x, c1y), duration: duration)
    }
    public static func spring(response: Double = 0.55, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation {
        Animation(kind: .spring(response: response, damping: dampingFraction), duration: Animation.springDuration(response: response, damping: dampingFraction))
    }
    public static var spring: Animation { spring() }
    public static func spring(duration: Double = 0.5, bounce: Double = 0) -> Animation { spring(response: duration, dampingFraction: 1 - bounce) }
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25) -> Animation {
        spring(response: response, dampingFraction: dampingFraction)
    }
    public static var bouncy: Animation { spring(response: 0.5, dampingFraction: 0.7) }
    public static var smooth: Animation { spring(response: 0.5, dampingFraction: 1) }
    public static var snappy: Animation { spring(response: 0.5, dampingFraction: 0.85) }

    public func delay(_ delay: Double) -> Animation { var a = self; a.delayValue = delay; return a }
    public func speed(_ speed: Double) -> Animation { var a = self; a.speedFactor = max(speed, 0.0001); return a }
    public func repeatForever(autoreverses: Bool = true) -> Animation { var a = self; a.repeatsForever = true; a.autoreverses = autoreverses; return a }
    public func repeatCount(_ count: Int, autoreverses: Bool = true) -> Animation { var a = self; a.repeatCount = max(1, count); a.autoreverses = autoreverses; return a }

    /// How long a spring takes to settle within 0.1 % of its target.
    static func springDuration(response: Double, damping: Double) -> Double {
        guard response > 0 else { return 0 }
        let omega = 2 * .pi / response
        if damping >= 1 { return response * 1.6 }
        return min(10, -log(0.001) / (max(damping, 0.05) * omega))
    }

    /// Total wall time including delay and repeats (infinite when repeating forever).
    var totalDuration: Double {
        if repeatsForever { return .infinity }
        return delayValue + duration / speedFactor * Double(repeatCount)
    }

    /// Progress 0...1 of the curve at `elapsed` seconds since the start (delay included).
    func progress(at elapsed: Double) -> Double {
        let t = elapsed - delayValue
        guard t > 0 else { return 0 }
        let cycle = duration / speedFactor
        guard cycle > 0 else { return 1 }
        var local = t
        var cycleIndex = 0
        if repeatsForever || repeatCount > 1 {
            cycleIndex = Int(t / cycle)
            if !repeatsForever && cycleIndex >= repeatCount { return autoreverses && repeatCount % 2 == 0 ? 0 : 1 }
            local = t - Double(cycleIndex) * cycle
        } else if t >= cycle {
            return 1
        }
        var u = min(1, local / cycle)
        if autoreverses && cycleIndex % 2 == 1 { u = 1 - u }
        switch kind {
        case .linear: return u
        case .bezier(let x1, let y1, let x2, let y2): return Animation.bezier(u, x1, y1, x2, y2)
        case .spring(let response, let damping): return Animation.springValue(time: u * cycle, response: response, damping: damping)
        }
    }

    var isFinished: (Double) -> Bool { { elapsed in elapsed >= self.totalDuration } }

    /// A cubic Bézier timing curve, solved for x by Newton's method as Core Animation does.
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func sample(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t
        }
        var t = x
        for _ in 0..<8 {
            let sx = sample(t, x1, x2) - x
            let mt = 1 - t
            let d = 3 * mt * mt * x1 + 6 * mt * t * (x2 - x1) + 3 * t * t * (1 - x2)
            if abs(sx) < 1e-5 || d == 0 { break }
            t -= sx / d
        }
        return min(1, max(0, sample(min(1, max(0, t)), y1, y2)))
    }

    /// A damped spring from 0 to 1 (overshoots when under-damped).
    static func springValue(time t: Double, response: Double, damping zeta: Double) -> Double {
        guard response > 0 else { return 1 }
        let omega = 2 * .pi / response
        if zeta >= 1 {
            // Critically damped.
            let e = exp(-omega * t)
            return 1 - e * (1 + omega * t)
        }
        let wd = omega * sqrt(1 - zeta * zeta)
        let e = exp(-zeta * omega * t)
        return 1 - e * (cos(wd * t) + (zeta * omega / wd) * sin(wd * t))
    }
}

// MARK: Transactions

extension Transaction {
    /// The transaction in effect while `withAnimation`/`withTransaction` run their body.
    nonisolated(unsafe) static var _current: Transaction?
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/withanimation(_:_:)
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    let previous = Transaction._current
    Transaction._current = Transaction(animation: animation)
    defer { Transaction._current = previous }
    return try body()
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/withtransaction(_:_:)
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    let previous = Transaction._current
    Transaction._current = transaction
    defer { Transaction._current = previous }
    return try body()
}

// MARK: Animatable

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/vectorarithmetic
public protocol VectorArithmetic: AdditiveArithmetic {
    mutating func scale(by rhs: Double)
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    public func scaled(by rhs: Double) -> Self { var c = self; c.scale(by: rhs); return c }
    public mutating func interpolate(towards other: Self, amount: Double) {
        var delta = other - self
        delta.scale(by: amount)
        self += delta
    }
    public func interpolated(towards other: Self, amount: Double) -> Self { var c = self; c.interpolate(towards: other, amount: amount); return c }
}

extension Double: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= rhs }
    public var magnitudeSquared: Double { self * self }
}
extension Float: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= Float(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}
extension CGFloat: VectorArithmetic {
    public mutating func scale(by rhs: Double) { self *= CGFloat(rhs) }
    public var magnitudeSquared: Double { Double(self * self) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/emptyanimatabledata
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
    public init() {}
    public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
    public static func + (a: EmptyAnimatableData, b: EmptyAnimatableData) -> EmptyAnimatableData { a }
    public static func - (a: EmptyAnimatableData, b: EmptyAnimatableData) -> EmptyAnimatableData { a }
    public static func += (a: inout EmptyAnimatableData, b: EmptyAnimatableData) {}
    public static func -= (a: inout EmptyAnimatableData, b: EmptyAnimatableData) {}
    public mutating func scale(by rhs: Double) {}
    public var magnitudeSquared: Double { 0 }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/animatablepair
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    public var first: First
    public var second: Second
    public init(_ first: First, _ second: Second) { self.first = first; self.second = second }
    public static var zero: AnimatablePair { AnimatablePair(.zero, .zero) }
    public static func + (a: AnimatablePair, b: AnimatablePair) -> AnimatablePair { AnimatablePair(a.first + b.first, a.second + b.second) }
    public static func - (a: AnimatablePair, b: AnimatablePair) -> AnimatablePair { AnimatablePair(a.first - b.first, a.second - b.second) }
    public static func += (a: inout AnimatablePair, b: AnimatablePair) { a = a + b }
    public static func -= (a: inout AnimatablePair, b: AnimatablePair) { a = a - b }
    public mutating func scale(by rhs: Double) { first.scale(by: rhs); second.scale(by: rhs) }
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/animatable
public protocol Animatable {
    associatedtype AnimatableData: VectorArithmetic
    var animatableData: AnimatableData { get set }
}

extension Animatable where Self: VectorArithmetic {
    public var animatableData: Self { get { self } set { self = newValue } }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    public var animatableData: EmptyAnimatableData { get { EmptyAnimatableData() } set {} }
}

extension CGPoint: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> { get { AnimatablePair(x, y) } set { x = newValue.first; y = newValue.second } }
}
extension CGSize: Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> { get { AnimatablePair(width, height) } set { width = newValue.first; height = newValue.second } }
}
extension CGRect: Animatable {
    public var animatableData: AnimatablePair<CGPoint.AnimatableData, CGSize.AnimatableData> {
        get { AnimatablePair(origin.animatableData, size.animatableData) }
        set { origin.animatableData = newValue.first; size.animatableData = newValue.second }
    }
}
extension Angle: Animatable {
    public var animatableData: Double { get { radians } set { radians = newValue } }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/unitpoint
public struct UnitPoint: Hashable, Sendable {
    public var x: CGFloat, y: CGFloat
    public init() { x = 0; y = 0 }
    public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

// MARK: Transitions

/// What a view looks like when fully "removed" by a transition, relative to its identity.
struct _TransitionSpec: Equatable {
    var opacity: CGFloat = 1          // 0 = fades
    var scale: CGFloat = 1
    var scaleAnchor = UnitPoint.center
    var offset = CGSize.zero
    var edge: Edge? = nil             // moves in from / out to this edge
    static let identity = _TransitionSpec()

    func combined(with o: _TransitionSpec) -> _TransitionSpec {
        var s = self
        s.opacity *= o.opacity
        s.scale *= o.scale
        s.offset = CGSize(width: offset.width + o.offset.width, height: offset.height + o.offset.height)
        s.edge = o.edge ?? edge
        return s
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/anytransition
public struct AnyTransition: Sendable {
    let insertion: _TransitionSpec
    let removal: _TransitionSpec
    init(_ spec: _TransitionSpec) { insertion = spec; removal = spec }
    init(insertion: _TransitionSpec, removal: _TransitionSpec) { self.insertion = insertion; self.removal = removal }

    public static let identity = AnyTransition(.identity)
    public static let opacity = AnyTransition(_TransitionSpec(opacity: 0))
    public static let scale = AnyTransition(_TransitionSpec(scale: 0))
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { AnyTransition(_TransitionSpec(scale: scale, scaleAnchor: anchor)) }
    public static func offset(_ offset: CGSize) -> AnyTransition { AnyTransition(_TransitionSpec(offset: offset)) }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { AnyTransition(_TransitionSpec(offset: CGSize(width: x, height: y))) }
    public static func move(edge: Edge) -> AnyTransition { AnyTransition(_TransitionSpec(edge: edge)) }
    public static let slide = AnyTransition(insertion: _TransitionSpec(edge: .leading), removal: _TransitionSpec(edge: .trailing))
    public static func push(from edge: Edge) -> AnyTransition {
        let opposite: Edge = { switch edge { case .leading: return .trailing; case .trailing: return .leading; case .top: return .bottom; case .bottom: return .top } }()
        return AnyTransition(insertion: _TransitionSpec(opacity: 0, edge: edge), removal: _TransitionSpec(opacity: 0, edge: opposite))
    }
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(insertion: insertion.combined(with: other.insertion), removal: removal.combined(with: other.removal))
    }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(insertion: insertion.insertion, removal: removal.removal)
    }
    public func animation(_ animation: Animation?) -> AnyTransition { self }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/transition(_:)
    public func transition(_ t: AnyTransition) -> some View {
        var d = _Decorated(content: self)
        d.style.transition = t
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/animation(_:value:)
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        _AnimationScope(content: self, value: value, animation: animation)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/animation(_:)
    /// Deprecated by Apple in favour of `animation(_:value:)`; every change below animates.
    public func animation(_ animation: Animation?) -> some View { _AnimationScope(content: self, value: _AlwaysChanged(), animation: animation) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/transaction(_:)
    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/offset(x:y:)
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
        var d = _Decorated(content: self)
        d.style.offset = CGSize(width: x, height: y)
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/offset(_:)
    public func offset(_ offset: CGSize) -> some View { self.offset(x: offset.width, y: offset.height) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/scaleeffect(_:anchor:)-pmi7
    public func scaleEffect(_ scale: CGFloat, anchor: UnitPoint = .center) -> some View { scaleEffect(x: scale, y: scale, anchor: anchor) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/scaleeffect(x:y:anchor:)
    public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some View {
        var d = _Decorated(content: self)
        d.style.scale = CGSize(width: x, height: y)
        d.style.anchor = anchor
        return d
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/rotationeffect(_:anchor:)
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
        var d = _Decorated(content: self)
        d.style.rotation = angle
        d.style.anchor = anchor
        return d
    }
}

/// `.animation(_:value:)`: when `value` changes, this pass's layout and property changes
/// in the subtree animate with `animation`.
struct _AnimationScope<Content: View, V: Equatable>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let value: V
    let animation: Animation?
    func _makePrimitive(node: _ViewNode) -> _Primitive { _AnimationScopePrimitive(value: value, animation: animation, content: _ViewBox(content)) }
}

@MainActor
final class _AnimationScopePrimitive<V: Equatable>: _Primitive {
    var value: V
    var animation: Animation?
    init(value: V, animation: Animation?, content: _AnyViewBox) {
        self.value = value
        self.animation = animation
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _AnimationScopePrimitive<V> else { return }
        let changed = o.value != value
        value = o.value
        animation = o.animation
        if changed, let node { node.implicitAnimation = animation; node.root?.noteImplicitAnimation(node) }
    }
}

/// A value that is never equal to its previous one (the value-less `.animation`).
struct _AlwaysChanged: Equatable {
    static func == (a: _AlwaysChanged, b: _AlwaysChanged) -> Bool { false }
}
