// Shape-style members apps reach for as `some ShapeStyle`: the colours as static members
// (`.fill(.green)`, `.background(.clear)`), `opacity(_:)` on any style, the tint style and
// the `tint(_:)` modifier that sets it.

import Foundation

extension ShapeStyle where Self == Color {
    public static var red: Color { Color.red }
    public static var orange: Color { Color.orange }
    public static var yellow: Color { Color.yellow }
    public static var green: Color { Color.green }
    public static var mint: Color { Color.mint }
    public static var teal: Color { Color.teal }
    public static var cyan: Color { Color.cyan }
    public static var blue: Color { Color.blue }
    public static var indigo: Color { Color.indigo }
    public static var purple: Color { Color.purple }
    public static var pink: Color { Color.pink }
    public static var brown: Color { Color.brown }
    public static var white: Color { Color.white }
    public static var gray: Color { Color.gray }
    public static var black: Color { Color.black }
    public static var clear: Color { Color.clear }
}

// MARK: Opacity

/// A style drawn at a fraction of its opacity.
public struct _OpacityShapeStyle<Base: ShapeStyle>: ShapeStyle {
    let base: Base
    let opacity: Double
    @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) {
        context.saveGState()
        context.setAlpha(CGFloat(opacity))
        base._fill(context, path: path, in: rect, environment: environment)
        context.restoreGState()
    }
    @MainActor public func _stroke(_ context: CGContext, path: CGPath, in rect: CGRect, style: StrokeStyle, environment: EnvironmentValues) {
        context.saveGState()
        context.setAlpha(CGFloat(opacity))
        base._stroke(context, path: path, in: rect, style: style, environment: environment)
        context.restoreGState()
    }
    @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? {
        base._color(at: point, in: rect, environment: environment).flatMap { $0.copy(alpha: $0.alpha * CGFloat(opacity)) }
    }
}

extension ShapeStyle {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shapestyle/opacity(_:)
    public func opacity(_ opacity: Double) -> some ShapeStyle { _OpacityShapeStyle(base: self, opacity: opacity) }
}

extension ShapeStyle where Self == AnyShapeStyle {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shapestyle/opacity(_:)-4tqot
    public static func opacity(_ opacity: Double) -> some ShapeStyle { _OpacityShapeStyle(base: HierarchicalShapeStyle.primary, opacity: opacity) }
}

// MARK: Tint

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/tintshapestyle
///
/// The tint set by `tint(_:)` above the view, else the accent colour.
public struct TintShapeStyle: ShapeStyle {
    public init() {}
    func _resolved(_ environment: EnvironmentValues) -> AnyShapeStyle { environment._tint ?? AnyShapeStyle(Color.accentColor) }
    @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) {
        _resolved(environment)._fill(context, path: path, in: rect, environment: environment)
    }
    @MainActor public func _stroke(_ context: CGContext, path: CGPath, in rect: CGRect, style: StrokeStyle, environment: EnvironmentValues) {
        _resolved(environment)._stroke(context, path: path, in: rect, style: style, environment: environment)
    }
    @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? {
        _resolved(environment)._color(at: point, in: rect, environment: environment)
    }
}

extension ShapeStyle where Self == TintShapeStyle {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shapestyle/tint
    public static var tint: TintShapeStyle { TintShapeStyle() }
}

private struct _TintKey: EnvironmentKey { static let defaultValue: AnyShapeStyle? = nil }

extension EnvironmentValues {
    var _tint: AnyShapeStyle? { get { self[_TintKey.self] } set { self[_TintKey.self] = newValue } }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/tint(_:)-93mfq
    ///
    /// Sets the style `.tint` resolves to below this view. AppKit controls keep the system
    /// accent colour.
    public func tint(_ tint: Color?) -> some View {
        transformEnvironment(\._tint) { $0 = tint.map { AnyShapeStyle($0) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/tint(_:)-23xyq
    public func tint<S: ShapeStyle>(_ tint: S?) -> some View {
        transformEnvironment(\._tint) { $0 = tint.map { AnyShapeStyle($0) } }
    }
}

/// The colour a foreground style of these types sets (Styles.swift's `_foregroundColor`).
func _extraForegroundColor(for style: any ShapeStyle, in environment: EnvironmentValues) -> Color? {
    switch style {
    case let t as TintShapeStyle: return SwiftUI._foregroundColor(for: t._resolved(environment), in: environment)
    case let o as any _OpacityStyled: return o._foregroundColor(in: environment)
    default: return nil
    }
}

protocol _OpacityStyled { func _foregroundColor(in environment: EnvironmentValues) -> Color? }
extension _OpacityShapeStyle: _OpacityStyled {
    func _foregroundColor(in environment: EnvironmentValues) -> Color? {
        SwiftUI._foregroundColor(for: base, in: environment)?.opacity(opacity)
    }
}
