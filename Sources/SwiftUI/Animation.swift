// Animation API surface. Animations are not interpolated yet (ADR-0010): withAnimation
// runs its body and the resulting state is laid out immediately.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/animation
public struct Animation: Equatable, Sendable {
    enum Kind: Equatable { case linear, easeIn, easeOut, easeInOut, spring, `default` }
    let kind: Kind
    var duration: Double = 0.35
    var delayValue: Double = 0
    var repeatsForever = false

    public static let `default` = Animation(kind: .default)
    public static func linear(duration: Double = 0.35) -> Animation { Animation(kind: .linear, duration: duration) }
    public static var linear: Animation { linear() }
    public static func easeIn(duration: Double = 0.35) -> Animation { Animation(kind: .easeIn, duration: duration) }
    public static var easeIn: Animation { easeIn() }
    public static func easeOut(duration: Double = 0.35) -> Animation { Animation(kind: .easeOut, duration: duration) }
    public static var easeOut: Animation { easeOut() }
    public static func easeInOut(duration: Double = 0.35) -> Animation { Animation(kind: .easeInOut, duration: duration) }
    public static var easeInOut: Animation { easeInOut() }
    public static func spring(response: Double = 0.55, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation { Animation(kind: .spring, duration: response) }
    public static var spring: Animation { spring() }
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25) -> Animation { Animation(kind: .spring, duration: response) }
    public static var bouncy: Animation { spring() }
    public static var smooth: Animation { easeInOut() }
    public static var snappy: Animation { easeOut(duration: 0.25) }

    public func delay(_ delay: Double) -> Animation { var a = self; a.delayValue = delay; return a }
    public func speed(_ speed: Double) -> Animation { var a = self; a.duration = duration / max(speed, 0.0001); return a }
    public func repeatForever(autoreverses: Bool = true) -> Animation { var a = self; a.repeatsForever = true; return a }
    public func repeatCount(_ count: Int, autoreverses: Bool = true) -> Animation { self }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/withanimation(_:_:)
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try body()
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/withtransaction(_:_:)
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    try body()
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/animation(_:value:)
    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/transition(_:)
    public func transition(_ t: AnyTransition) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/transaction(_:)
    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View { self }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/anytransition
public struct AnyTransition: Sendable {
    public static let opacity = AnyTransition()
    public static let slide = AnyTransition()
    public static let scale = AnyTransition()
    public static let identity = AnyTransition()
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { AnyTransition() }
    public func combined(with other: AnyTransition) -> AnyTransition { self }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition { insertion }
}
