// CoreGraphics geometry that Foundation on Windows does not provide.
// CGFloat, CGPoint, CGSize, CGRect and CGVector come from swift-corelibs-foundation.

import Foundation

public struct CGAffineTransform: Equatable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init() { self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    public static let identity = CGAffineTransform()

    public init(translationX tx: CGFloat, y ty: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty) }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    public init(rotationAngle angle: CGFloat) {
        let s = sin(angle), c = cos(angle)
        self.init(a: c, b: s, c: -s, d: c, tx: 0, ty: 0)
    }

    public var isIdentity: Bool { self == .identity }

    /// `self` followed by `t2` (CoreGraphics order: the result applies `self` first).
    public func concatenating(_ t2: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(a: a * t2.a + b * t2.c, b: a * t2.b + b * t2.d,
                          c: c * t2.a + d * t2.c, d: c * t2.b + d * t2.d,
                          tx: tx * t2.a + ty * t2.c + t2.tx, ty: tx * t2.b + ty * t2.d + t2.ty)
    }
    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform { CGAffineTransform(translationX: x, y: y).concatenating(self) }
    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform { CGAffineTransform(scaleX: x, y: y).concatenating(self) }
    public func rotated(by angle: CGFloat) -> CGAffineTransform { CGAffineTransform(rotationAngle: angle).concatenating(self) }

    public func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        guard det != 0 else { return self }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return CGAffineTransform(a: ia, b: ib, c: ic, d: id, tx: -(tx * ia + ty * ic), ty: -(tx * ib + ty * id))
    }
}

extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
    }
}

extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSize(width: t.a * width + t.c * height, height: t.b * width + t.d * height)
    }
}

extension CGRect {
    /// The smallest rectangle containing the transformed corners.
    public func applying(_ t: CGAffineTransform) -> CGRect {
        if isNull { return self }
        let pts = [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY)].map { $0.applying(t) }
        let xs = pts.map { $0.x }, ys = pts.map { $0.y }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

public enum CGLineCap: Int32, Sendable { case butt = 0, round = 1, square = 2 }
public enum CGLineJoin: Int32, Sendable { case miter = 0, round = 1, bevel = 2 }
public enum CGPathFillRule: Int, Sendable { case winding = 0, evenOdd = 1 }
public enum CGPathDrawingMode: Int32, Sendable { case fill = 0, eoFill = 1, stroke = 2, fillStroke = 3, eoFillStroke = 4 }
public enum CGInterpolationQuality: Int32, Sendable { case `default` = 0, none = 1, low = 2, medium = 4, high = 3 }
public enum CGBlendMode: Int32, Sendable {
    case normal = 0, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight,
         difference, exclusion, hue, saturation, color, luminosity,
         clear, copy, sourceIn, sourceOut, sourceAtop, destinationOver, destinationIn, destinationOut,
         destinationAtop, xor, plusDarker, plusLighter
}
