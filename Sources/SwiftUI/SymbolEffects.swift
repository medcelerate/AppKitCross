// Symbol effects (the Symbols framework, which Apple's SwiftUI re-exports), content
// transitions, and a few modifiers the port accepts with no or partial effect:
// `help` with a Text or localized key, `navigationSubtitle`, `presentedWindowStyle`.
//
// The port draws no SF Symbol animations and does not interpolate text changes, so
// `symbolEffect` and `contentTransition` keep the view as it is: the symbol shows
// unanimated, a changed value appears at once.

import Foundation

// MARK: Symbol effects

/// - SeeAlso: https://developer.apple.com/documentation/symbols/symboleffectconfiguration
public struct SymbolEffectConfiguration: Hashable, Sendable {
    let name: String
    let options: [String]
}

/// - SeeAlso: https://developer.apple.com/documentation/symbols/symboleffect
public protocol SymbolEffect: Hashable, Sendable {
    var configuration: SymbolEffectConfiguration { get }
}
/// - SeeAlso: https://developer.apple.com/documentation/symbols/indefinitesymboleffect
public protocol IndefiniteSymbolEffect {}
/// - SeeAlso: https://developer.apple.com/documentation/symbols/discretesymboleffect
public protocol DiscreteSymbolEffect {}
/// - SeeAlso: https://developer.apple.com/documentation/symbols/contenttransitionsymboleffect
public protocol ContentTransitionSymbolEffect {}

/// Shared shape of the effect structs: a name plus the option modifiers applied.
public protocol _SymbolEffectValue: SymbolEffect {
    init(_options: [String])
    var _options: [String] { get }
    static var _name: String { get }
}
extension _SymbolEffectValue {
    public var configuration: SymbolEffectConfiguration { SymbolEffectConfiguration(name: Self._name, options: _options) }
    func _with(_ option: String) -> Self { Self(_options: _options + [option]) }
}

/// - SeeAlso: https://developer.apple.com/documentation/symbols/variablecolorsymboleffect
public struct VariableColorSymbolEffect: _SymbolEffectValue, IndefiniteSymbolEffect, DiscreteSymbolEffect {
    public static var _name: String { "variableColor" }
    public let _options: [String]
    public init(_options: [String]) { self._options = _options }
    public var reversing: VariableColorSymbolEffect { _with("reversing") }
    public var nonReversing: VariableColorSymbolEffect { _with("nonReversing") }
    public var cumulative: VariableColorSymbolEffect { _with("cumulative") }
    public var iterative: VariableColorSymbolEffect { _with("iterative") }
    public var hideInactiveLayers: VariableColorSymbolEffect { _with("hideInactiveLayers") }
    public var dimInactiveLayers: VariableColorSymbolEffect { _with("dimInactiveLayers") }
}
/// - SeeAlso: https://developer.apple.com/documentation/symbols/pulsesymboleffect
public struct PulseSymbolEffect: _SymbolEffectValue, IndefiniteSymbolEffect, DiscreteSymbolEffect {
    public static var _name: String { "pulse" }
    public let _options: [String]
    public init(_options: [String]) { self._options = _options }
    public var byLayer: PulseSymbolEffect { _with("byLayer") }
    public var wholeSymbol: PulseSymbolEffect { _with("wholeSymbol") }
}
/// - SeeAlso: https://developer.apple.com/documentation/symbols/bouncesymboleffect
public struct BounceSymbolEffect: _SymbolEffectValue, IndefiniteSymbolEffect, DiscreteSymbolEffect {
    public static var _name: String { "bounce" }
    public let _options: [String]
    public init(_options: [String]) { self._options = _options }
    public var up: BounceSymbolEffect { _with("up") }
    public var down: BounceSymbolEffect { _with("down") }
    public var byLayer: BounceSymbolEffect { _with("byLayer") }
    public var wholeSymbol: BounceSymbolEffect { _with("wholeSymbol") }
}
/// - SeeAlso: https://developer.apple.com/documentation/symbols/scalesymboleffect
public struct ScaleSymbolEffect: _SymbolEffectValue, IndefiniteSymbolEffect {
    public static var _name: String { "scale" }
    public let _options: [String]
    public init(_options: [String]) { self._options = _options }
    public var up: ScaleSymbolEffect { _with("up") }
    public var down: ScaleSymbolEffect { _with("down") }
    public var byLayer: ScaleSymbolEffect { _with("byLayer") }
    public var wholeSymbol: ScaleSymbolEffect { _with("wholeSymbol") }
}
/// - SeeAlso: https://developer.apple.com/documentation/symbols/replacesymboleffect
public struct ReplaceSymbolEffect: _SymbolEffectValue, ContentTransitionSymbolEffect {
    public static var _name: String { "replace" }
    public let _options: [String]
    public init(_options: [String]) { self._options = _options }
    public var downUp: ReplaceSymbolEffect { _with("downUp") }
    public var upUp: ReplaceSymbolEffect { _with("upUp") }
    public var offUp: ReplaceSymbolEffect { _with("offUp") }
    public var byLayer: ReplaceSymbolEffect { _with("byLayer") }
    public var wholeSymbol: ReplaceSymbolEffect { _with("wholeSymbol") }
}

extension SymbolEffect where Self == VariableColorSymbolEffect { public static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect(_options: []) } }
extension SymbolEffect where Self == PulseSymbolEffect { public static var pulse: PulseSymbolEffect { PulseSymbolEffect(_options: []) } }
extension SymbolEffect where Self == BounceSymbolEffect { public static var bounce: BounceSymbolEffect { BounceSymbolEffect(_options: []) } }
extension SymbolEffect where Self == ScaleSymbolEffect { public static var scale: ScaleSymbolEffect { ScaleSymbolEffect(_options: []) } }
extension SymbolEffect where Self == ReplaceSymbolEffect { public static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect(_options: []) } }

/// - SeeAlso: https://developer.apple.com/documentation/symbols/symboleffectoptions
public struct SymbolEffectOptions: Hashable, Sendable {
    var speed: Double = 1
    var repeatCount: Int? = nil
    var repeats = false
    public static var `default`: SymbolEffectOptions { SymbolEffectOptions() }
    public static func speed(_ speed: Double) -> SymbolEffectOptions { SymbolEffectOptions().speed(speed) }
    public func speed(_ speed: Double) -> SymbolEffectOptions { var o = self; o.speed = speed; return o }
    public static func `repeat`(_ count: Int?) -> SymbolEffectOptions { SymbolEffectOptions().repeat(count) }
    public func `repeat`(_ count: Int?) -> SymbolEffectOptions { var o = self; o.repeatCount = count; o.repeats = true; return o }
    public static var repeating: SymbolEffectOptions { SymbolEffectOptions().repeating }
    public var repeating: SymbolEffectOptions { var o = self; o.repeats = true; o.repeatCount = nil; return o }
    public static var nonRepeating: SymbolEffectOptions { SymbolEffectOptions().nonRepeating }
    public var nonRepeating: SymbolEffectOptions { var o = self; o.repeats = false; o.repeatCount = nil; return o }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:isactive:)
    /// Accepted; the port draws no symbol animations, so the symbol shows still.
    public func symbolEffect<T: IndefiniteSymbolEffect & SymbolEffect>(_ effect: T, options: SymbolEffectOptions = .default, isActive: Bool = true) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:)
    /// Accepted; no animation plays when the value changes.
    public func symbolEffect<T: DiscreteSymbolEffect & SymbolEffect, U: Equatable>(_ effect: T, options: SymbolEffectOptions = .default, value: U) -> some View { self }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/symboleffectsremoved(_:)
    public func symbolEffectsRemoved(_ isEnabled: Bool = true) -> some View { self }
}

// MARK: Content transitions

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/contenttransition
/// Accepted by `contentTransition(_:)`; the port swaps changed content at once.
public struct ContentTransition: Equatable, Sendable {
    let kind: String
    public static let identity = ContentTransition(kind: "identity")
    public static let opacity = ContentTransition(kind: "opacity")
    public static let interpolate = ContentTransition(kind: "interpolate")
    public static func numericText(countsDown: Bool = false) -> ContentTransition { ContentTransition(kind: countsDown ? "numericText.down" : "numericText") }
    public static func numericText(value: Double) -> ContentTransition { ContentTransition(kind: "numericText.value") }
    public static func symbolEffect<T: ContentTransitionSymbolEffect & SymbolEffect>(_ effect: T, options: SymbolEffectOptions = .default) -> ContentTransition {
        ContentTransition(kind: "symbolEffect.\(effect.configuration.name)")
    }
    public static var symbolEffect: ContentTransition { ContentTransition(kind: "symbolEffect") }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/contenttransition(_:)
    /// Accepted; no effect (see `ContentTransition`).
    public func contentTransition(_ transition: ContentTransition) -> some View { self }
}

// MARK: Help, subtitles, presented window style

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/help(_:)-6d1ow
    /// The tooltip, as `help(_: String)`.
    public func help(_ textKey: LocalizedStringKey) -> some View { help(Text(textKey)._string) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/help(_:)-4z2pa
    public func help(_ text: Text) -> some View { help(text._string) }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)-1bq1e
    /// The hosting window's subtitle (`NSWindow.subtitle`), shown under the title in the
    /// title bar where the backend draws one.
    public func navigationSubtitle(_ subtitle: Text) -> some View { _NavigationSubtitle(content: self, subtitle: subtitle._string) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)-5kqd1
    public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> some View { _NavigationSubtitle(content: self, subtitle: Text(subtitleKey)._string) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)-7pu5e
    @_disfavoredOverload
    public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> some View { _NavigationSubtitle(content: self, subtitle: String(subtitle)) }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/presentedwindowstyle(_:)
    /// Accepted; no effect (the port has no presented-window API that takes a style).
    public func presentedWindowStyle<S: WindowStyle>(_ style: S) -> some View { self }
}

struct _NavigationSubtitle<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let subtitle: String
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        if let window = node.root?.host?.hostView.window, !(window is NSPanel), window.sheetParent == nil, window.subtitle != subtitle {
            window.subtitle = subtitle
        }
        return _GroupPrimitive(children: [_ViewBox(content)])
    }
}
