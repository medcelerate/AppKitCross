// Shape transforms, insettable shapes, path elements and trimming: the shape API the
// third-party library compatibility example found missing (SwiftUICharts draws its lines,
// bars and arcs with them).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: InsettableShape

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/insettableshape
public protocol InsettableShape: Shape {
    associatedtype InsetShape: InsettableShape
    func inset(by amount: CGFloat) -> InsetShape
}

extension InsettableShape {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/insettableshape/strokeborder(_:style:antialiased:)
    public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View {
        inset(by: style.lineWidth / 2).stroke(content, style: style, antialiased: antialiased)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/insettableshape/strokeborder(_:linewidth:antialiased:)
    public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
        strokeBorder(content, style: StrokeStyle(lineWidth: lineWidth), antialiased: antialiased)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/insettableshape/strokeborder(style:antialiased:)
    public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> some View { strokeBorder(Color.primary, style: style, antialiased: antialiased) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/insettableshape/strokeborder(linewidth:antialiased:)
    public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View { strokeBorder(Color.primary, lineWidth: lineWidth, antialiased: antialiased) }
}

/// A built-in shape drawn in its rect inset by an amount (what `inset(by:)` returns).
public struct _InsetShape<Content: Shape>: InsettableShape, Sendable {
    var shape: Content
    var amount: CGFloat
    public func path(in rect: CGRect) -> Path { shape.path(in: rect.insetBy(dx: amount, dy: amount)) }
    public func inset(by amount: CGFloat) -> _InsetShape<Content> { _InsetShape(shape: shape, amount: self.amount + amount) }
}

extension Rectangle: InsettableShape {
    public func inset(by amount: CGFloat) -> some InsettableShape { _InsetShape(shape: self, amount: amount) }
}
extension RoundedRectangle: InsettableShape {
    public func inset(by amount: CGFloat) -> some InsettableShape { _InsetShape(shape: self, amount: amount) }
}
extension Circle: InsettableShape {
    public func inset(by amount: CGFloat) -> some InsettableShape { _InsetShape(shape: self, amount: amount) }
}
extension Ellipse: InsettableShape {
    public func inset(by amount: CGFloat) -> some InsettableShape { _InsetShape(shape: self, amount: amount) }
}
extension Capsule: InsettableShape {
    public func inset(by amount: CGFloat) -> some InsettableShape { _InsetShape(shape: self, amount: amount) }
}

// MARK: Transformed shapes

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/scaledshape
public struct ScaledShape<Content: Shape>: Shape, Sendable {
    public var shape: Content
    public var scale: CGSize
    public var anchor: UnitPoint
    public init(shape: Content, scale: CGSize, anchor: UnitPoint = .center) { self.shape = shape; self.scale = scale; self.anchor = anchor }
    public func path(in rect: CGRect) -> Path {
        let ax = rect.minX + rect.width * anchor.x, ay = rect.minY + rect.height * anchor.y
        let t = CGAffineTransform(translationX: ax, y: ay).scaledBy(x: scale.width, y: scale.height).translatedBy(x: -ax, y: -ay)
        return shape.path(in: rect).applying(t)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/rotatedshape
public struct RotatedShape<Content: Shape>: Shape, Sendable {
    public var shape: Content
    public var angle: Angle
    public var anchor: UnitPoint
    public init(shape: Content, angle: Angle, anchor: UnitPoint = .center) { self.shape = shape; self.angle = angle; self.anchor = anchor }
    public func path(in rect: CGRect) -> Path {
        let ax = rect.minX + rect.width * anchor.x, ay = rect.minY + rect.height * anchor.y
        let t = CGAffineTransform(translationX: ax, y: ay).rotated(by: CGFloat(angle.radians)).translatedBy(x: -ax, y: -ay)
        return shape.path(in: rect).applying(t)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/offsetshape
public struct OffsetShape<Content: Shape>: Shape, Sendable {
    public var shape: Content
    public var offset: CGSize
    public init(shape: Content, offset: CGSize) { self.shape = shape; self.offset = offset }
    public func path(in rect: CGRect) -> Path { shape.path(in: rect).offsetBy(dx: offset.width, dy: offset.height) }
}

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/transformedshape
public struct TransformedShape<Content: Shape>: Shape, Sendable {
    public var shape: Content
    public var transform: CGAffineTransform
    public init(shape: Content, transform: CGAffineTransform) { self.shape = shape; self.transform = transform }
    public func path(in rect: CGRect) -> Path { shape.path(in: rect).applying(transform) }
}

extension OffsetShape: InsettableShape where Content: InsettableShape {
    public func inset(by amount: CGFloat) -> OffsetShape<Content.InsetShape> { OffsetShape<Content.InsetShape>(shape: shape.inset(by: amount), offset: offset) }
}
extension ScaledShape: InsettableShape where Content: InsettableShape {
    public func inset(by amount: CGFloat) -> ScaledShape<Content.InsetShape> { ScaledShape<Content.InsetShape>(shape: shape.inset(by: amount), scale: scale, anchor: anchor) }
}
extension RotatedShape: InsettableShape where Content: InsettableShape {
    public func inset(by amount: CGFloat) -> RotatedShape<Content.InsetShape> { RotatedShape<Content.InsetShape>(shape: shape.inset(by: amount), angle: angle, anchor: anchor) }
}
extension TransformedShape: InsettableShape where Content: InsettableShape {
    public func inset(by amount: CGFloat) -> TransformedShape<Content.InsetShape> { TransformedShape<Content.InsetShape>(shape: shape.inset(by: amount), transform: transform) }
}

/// The part of a shape's path between two fractions of its length (`Shape.trim`).
public struct _TrimmedShape<Content: Shape>: Shape, Sendable {
    var shape: Content
    var startFraction: CGFloat
    var endFraction: CGFloat
    public func path(in rect: CGRect) -> Path { shape.path(in: rect).trimmedPath(from: startFraction, to: endFraction) }
}

extension Shape {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/scale(_:anchor:)
    public func scale(_ scale: CGFloat, anchor: UnitPoint = .center) -> ScaledShape<Self> { ScaledShape(shape: self, scale: CGSize(width: scale, height: scale), anchor: anchor) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/scale(x:y:anchor:)
    public func scale(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> ScaledShape<Self> { ScaledShape(shape: self, scale: CGSize(width: x, height: y), anchor: anchor) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/rotation(_:anchor:)
    public func rotation(_ angle: Angle, anchor: UnitPoint = .center) -> RotatedShape<Self> { RotatedShape(shape: self, angle: angle, anchor: anchor) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/offset(_:)-5pgl2
    public func offset(_ offset: CGSize) -> OffsetShape<Self> { OffsetShape(shape: self, offset: offset) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/offset(_:)-2v2ek
    public func offset(_ offset: CGPoint) -> OffsetShape<Self> { OffsetShape(shape: self, offset: CGSize(width: offset.x, height: offset.y)) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/offset(x:y:)
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> OffsetShape<Self> { OffsetShape(shape: self, offset: CGSize(width: x, height: y)) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/transform(_:)
    public func transform(_ transform: CGAffineTransform) -> TransformedShape<Self> { TransformedShape(shape: self, transform: transform) }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/shape/trim(from:to:)
    public func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> some Shape {
        _TrimmedShape(shape: self, startFraction: startFraction, endFraction: endFraction)
    }
}

// MARK: Path elements

extension Path {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/element
    public enum Element: Equatable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/foreach(_:)
    public func forEach(_ body: (Element) -> Void) {
        cgPath.applyWithBlock { el in
            let p = el.pointee.points
            switch el.pointee.type {
            case .moveToPoint: body(.move(to: p[0]))
            case .addLineToPoint: body(.line(to: p[0]))
            case .addQuadCurveToPoint: body(.quadCurve(to: p[1], control: p[0]))
            case .addCurveToPoint: body(.curve(to: p[2], control1: p[0], control2: p[1]))
            case .closeSubpath: body(.closeSubpath)
            @unknown default: break
            }
        }
    }

    var elements: [Element] { var out: [Element] = []; forEach { out.append($0) }; return out }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/currentpoint
    public var currentPoint: CGPoint? { cgPath.isEmpty ? nil : cgPath.currentPoint }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/applying(_:)
    public func applying(_ transform: CGAffineTransform) -> Path {
        var t = transform
        return Path(cgPath.copy(using: &t) ?? cgPath)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/offsetby(dx:dy:)
    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Path { applying(CGAffineTransform(translationX: dx, y: dy)) }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/addrelativearc(center:radius:startangle:delta:transform:)
    public mutating func addRelativeArc(center: CGPoint, radius: CGFloat, startAngle: Angle, delta: Angle, transform: CGAffineTransform = .identity) {
        addArc(center: center, radius: radius, startAngle: startAngle, endAngle: Angle(radians: startAngle.radians + delta.radians), clockwise: delta.radians < 0, transform: transform)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/path/trimmedpath(from:to:)
    /// The part of the path between two fractions of its total length; curves are cut
    /// exactly (de Casteljau), a close becomes the line it stands for.
    public func trimmedPath(from startFraction: CGFloat, to endFraction: CGFloat) -> Path {
        let f0 = min(max(0, min(startFraction, endFraction)), 1), f1 = min(max(0, max(startFraction, endFraction)), 1)
        guard f1 > f0 else { return Path() }
        if f0 <= 0, f1 >= 1 { return self }
        let segments = _segments()
        let total = segments.reduce(0) { $0 + $1.length }
        guard total > 0 else { return self }
        let s0 = f0 * total, s1 = f1 * total
        var out = Path()
        var d: CGFloat = 0
        var pen: CGPoint? = nil
        for seg in segments {
            let len = seg.length
            defer { d += len }
            guard len > 0 else { continue }
            let t0 = max(0, (s0 - d) / len), t1 = min(1, (s1 - d) / len)
            guard t1 > t0 else { continue }
            let piece = seg.sub(t0, t1)
            if pen != piece.start { out.move(to: piece.start) }
            switch piece {
            case .line(_, let p): out.addLine(to: p)
            case .quad(_, let c, let p): out.addQuadCurve(to: p, control: c)
            case .cubic(_, let c1, let c2, let p): out.addCurve(to: p, control1: c1, control2: c2)
            }
            pen = piece.end
        }
        return out
    }

    /// The drawing segments with their start points (moves and closes resolved).
    func _segments() -> [_PathSegment] {
        var out: [_PathSegment] = []
        var current = CGPoint.zero, start = CGPoint.zero
        forEach { el in
            switch el {
            case .move(to: let p): current = p; start = p
            case .line(to: let p): out.append(.line(current, p)); current = p
            case .quadCurve(to: let p, control: let c): out.append(.quad(current, c, p)); current = p
            case .curve(to: let p, control1: let c1, control2: let c2): out.append(.cubic(current, c1, c2, p)); current = p
            case .closeSubpath: if current != start { out.append(.line(current, start)) }; current = start
            }
        }
        return out
    }

    /// The path as polylines (curves flattened), one per subpath.
    func _flattened(steps: Int = 16) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var poly: [CGPoint] = []
        var start = CGPoint.zero
        func flush() { if poly.count > 1 { out.append(poly) }; poly = [] }
        forEach { el in
            switch el {
            case .move(to: let p): flush(); poly = [p]; start = p
            case .line(to: let p): poly.append(p)
            case .quadCurve(to: let p, control: let c):
                let a = poly.last ?? p
                for i in 1...steps { poly.append(_PathSegment.quad(a, c, p).point(at: CGFloat(i) / CGFloat(steps))) }
            case .curve(to: let p, control1: let c1, control2: let c2):
                let a = poly.last ?? p
                for i in 1...steps { poly.append(_PathSegment.cubic(a, c1, c2, p).point(at: CGFloat(i) / CGFloat(steps))) }
            case .closeSubpath: poly.append(start); flush()
            }
        }
        flush()
        return out
    }
}

/// One drawn piece of a path, with the point it starts from.
enum _PathSegment {
    case line(CGPoint, CGPoint)
    case quad(CGPoint, CGPoint, CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint, CGPoint)

    var start: CGPoint {
        switch self { case .line(let a, _), .quad(let a, _, _), .cubic(let a, _, _, _): return a }
    }
    var end: CGPoint {
        switch self { case .line(_, let p), .quad(_, _, let p), .cubic(_, _, _, let p): return p }
    }
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        switch self {
        case .line(let a, let b): return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        case .quad(let a, let c, let b):
            return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
        case .cubic(let a, let c1, let c2, let b):
            return CGPoint(x: u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x,
                           y: u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y)
        }
    }
    /// Arc length (curves by flattening).
    var length: CGFloat {
        switch self {
        case .line(let a, let b): return ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        default:
            var total: CGFloat = 0, last = start
            for i in 1...24 {
                let p = point(at: CGFloat(i) / 24)
                total += ((p.x - last.x) * (p.x - last.x) + (p.y - last.y) * (p.y - last.y)).squareRoot()
                last = p
            }
            return total
        }
    }
    /// The piece between parameters `t0` and `t1` (de Casteljau subdivision).
    func sub(_ t0: CGFloat, _ t1: CGFloat) -> _PathSegment {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        switch self {
        case .line(let a, let b): return .line(lerp(a, b, t0), lerp(a, b, t1))
        case .quad(let a, let c, let b):
            // The right part from t0, then the left (t1 - t0) / (1 - t0) of that.
            let r0 = point(at: t0), r1 = lerp(c, b, t0), r2 = b
            let s = t0 >= 1 ? 0 : (t1 - t0) / (1 - t0)
            let q1 = lerp(r0, r1, s)
            let q2 = lerp(q1, lerp(r1, r2, s), s)
            return .quad(r0, q1, q2)
        case .cubic(let a, let c1, let c2, let b):
            func split(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> ((CGPoint, CGPoint, CGPoint, CGPoint), (CGPoint, CGPoint, CGPoint, CGPoint)) {
                let p01 = lerp(p0, p1, t), p12 = lerp(p1, p2, t), p23 = lerp(p2, p3, t)
                let p012 = lerp(p01, p12, t), p123 = lerp(p12, p23, t)
                let m = lerp(p012, p123, t)
                return ((p0, p01, p012, m), (m, p123, p23, p3))
            }
            let right = split(a, c1, c2, b, t0).1
            let s = t0 >= 1 ? 0 : (t1 - t0) / (1 - t0)
            let left = split(right.0, right.1, right.2, right.3, s).0
            return .cubic(left.0, left.1, left.2, left.3)
        }
    }
}

// MARK: Styled strokes

/// Strokes `path` with any style: each flattened segment is stroked with the style's
/// colour at its midpoint, so gradients run along the line (CoreGraphics on Windows and
/// Linux has no stroked-path outline to clip a fill to).
@MainActor
func _strokeSegments(_ ctx: CGContext, path: CGPath, in rect: CGRect, style: StrokeStyle, environment: EnvironmentValues, color: (CGPoint) -> CGColor) {
    ctx.saveGState()
    ctx._apply(style)
    ctx.setLineDash(phase: 0, lengths: [])
    for poly in Path(path)._flattened() {
        guard poly.count > 1 else { continue }
        for i in 1..<poly.count {
            let a = poly[i - 1], b = poly[i]
            // Long straight runs are cut into short pieces so the colour can change along them.
            let len = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            let pieces = max(1, Int(len / 4))
            for k in 0..<pieces {
                let t0 = CGFloat(k) / CGFloat(pieces), t1 = CGFloat(k + 1) / CGFloat(pieces)
                let p0 = CGPoint(x: a.x + (b.x - a.x) * t0, y: a.y + (b.y - a.y) * t0)
                let p1 = CGPoint(x: a.x + (b.x - a.x) * t1, y: a.y + (b.y - a.y) * t1)
                ctx.setStrokeColor(color(CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)))
                ctx.move(to: p0)
                ctx.addLine(to: p1)
                ctx.strokePath()
            }
        }
    }
    ctx.restoreGState()
}

extension ShapeStyle {
    @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? { nil }
    @MainActor func _strokeSegments(_ ctx: CGContext, path: CGPath, in rect: CGRect, style: StrokeStyle, environment: EnvironmentValues) {
        guard _color(at: CGPoint(x: rect.midX, y: rect.midY), in: rect, environment: environment) != nil else { unimplemented("\(Self.self)._stroke"); return }
        SwiftUI._strokeSegments(ctx, path: path, in: rect, style: style, environment: environment) { p in
            self._color(at: p, in: rect, environment: environment) ?? NSColor.clear.cgColor
        }
    }
}

extension LinearGradient {
    @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? {
        let p0 = CGPoint(x: rect.minX + startPoint.x * rect.width, y: rect.minY + startPoint.y * rect.height)
        let p1 = CGPoint(x: rect.minX + endPoint.x * rect.width, y: rect.minY + endPoint.y * rect.height)
        let dx = p1.x - p0.x, dy = p1.y - p0.y
        let len2 = dx * dx + dy * dy
        let t = len2 > 0 ? ((point.x - p0.x) * dx + (point.y - p0.y) * dy) / len2 : 0
        return _gradientColor(_resolvedStops(environment), at: min(1, max(0, t)))
    }
}
