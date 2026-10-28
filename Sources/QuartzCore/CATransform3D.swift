// CATransform3D: a 4x4 row-major homogeneous matrix, as in Core Animation.
// Points are row vectors: p' = p * M.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct CATransform3D: Equatable, Sendable {
    public var m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat
    public var m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat
    public var m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat
    public var m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat

    public init() {
        self = CATransform3DIdentity
    }

    public init(m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat,
                m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat,
                m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat,
                m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44
    }

    public init(_ t: CGAffineTransform) {
        self = CATransform3DMakeAffineTransform(t)
    }

    public static let identity = CATransform3D(
        m11: 1, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: 1, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: 1, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1)

    public var isIdentity: Bool { self == CATransform3D.identity }

    /// True when the transform can be represented by a CGAffineTransform (no z or perspective).
    public var isAffine: Bool {
        m13 == 0 && m14 == 0 && m23 == 0 && m24 == 0 &&
        m31 == 0 && m32 == 0 && m33 == 1 && m34 == 0 && m43 == 0 && m44 == 1
    }

    /// The affine part (the 3D components are dropped).
    public var affineTransform: CGAffineTransform {
        CGAffineTransform(a: m11, b: m12, c: m21, d: m22, tx: m41, ty: m42)
    }

    public func concatenating(_ b: CATransform3D) -> CATransform3D { CATransform3DConcat(self, b) }
    public func inverted() -> CATransform3D { CATransform3DInvert(self) }
    public func translatedBy(x: CGFloat, y: CGFloat, z: CGFloat) -> CATransform3D { CATransform3DTranslate(self, x, y, z) }
    public func scaledBy(x: CGFloat, y: CGFloat, z: CGFloat) -> CATransform3D { CATransform3DScale(self, x, y, z) }
    public func rotated(by angle: CGFloat, x: CGFloat, y: CGFloat, z: CGFloat) -> CATransform3D { CATransform3DRotate(self, angle, x, y, z) }

    /// The 4x4 as rows, for interpolation and inversion.
    var rows: [[CGFloat]] {
        get { [[m11, m12, m13, m14], [m21, m22, m23, m24], [m31, m32, m33, m34], [m41, m42, m43, m44]] }
        set {
            m11 = newValue[0][0]; m12 = newValue[0][1]; m13 = newValue[0][2]; m14 = newValue[0][3]
            m21 = newValue[1][0]; m22 = newValue[1][1]; m23 = newValue[1][2]; m24 = newValue[1][3]
            m31 = newValue[2][0]; m32 = newValue[2][1]; m33 = newValue[2][2]; m34 = newValue[2][3]
            m41 = newValue[3][0]; m42 = newValue[3][1]; m43 = newValue[3][2]; m44 = newValue[3][3]
        }
    }
}

public let CATransform3DIdentity = CATransform3D(
    m11: 1, m12: 0, m13: 0, m14: 0,
    m21: 0, m22: 1, m23: 0, m24: 0,
    m31: 0, m32: 0, m33: 1, m34: 0,
    m41: 0, m42: 0, m43: 0, m44: 1)

public func CATransform3DIsIdentity(_ t: CATransform3D) -> Bool { t.isIdentity }
public func CATransform3DEqualToTransform(_ a: CATransform3D, _ b: CATransform3D) -> Bool { a == b }

public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    var t = CATransform3DIdentity
    t.m41 = tx; t.m42 = ty; t.m43 = tz
    return t
}

public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    var t = CATransform3DIdentity
    t.m11 = sx; t.m22 = sy; t.m33 = sz
    return t
}

/// Rotation by `angle` radians about the axis (x, y, z).
public func CATransform3DMakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    let len = (x * x + y * y + z * z).squareRoot()
    guard len > 0 else { return CATransform3DIdentity }
    let (ux, uy, uz) = (x / len, y / len, z / len)
    let c = cos(angle), s = sin(angle), ic = 1 - c
    // Row-vector convention: rows are the images of the basis vectors.
    return CATransform3D(
        m11: c + ux * ux * ic,       m12: uy * ux * ic + uz * s,  m13: uz * ux * ic - uy * s,  m14: 0,
        m21: ux * uy * ic - uz * s,  m22: c + uy * uy * ic,       m23: uz * uy * ic + ux * s,  m24: 0,
        m31: ux * uz * ic + uy * s,  m32: uy * uz * ic - ux * s,  m33: c + uz * uz * ic,       m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1)
}

public func CATransform3DTranslate(_ t: CATransform3D, _ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeTranslation(tx, ty, tz), t)
}

public func CATransform3DScale(_ t: CATransform3D, _ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), t)
}

public func CATransform3DRotate(_ t: CATransform3D, _ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    CATransform3DConcat(CATransform3DMakeRotation(angle, x, y, z), t)
}

/// a * b: apply `a`, then `b`.
public func CATransform3DConcat(_ a: CATransform3D, _ b: CATransform3D) -> CATransform3D {
    let ar = a.rows, br = b.rows
    var out = [[CGFloat]](repeating: [0, 0, 0, 0], count: 4)
    for i in 0..<4 {
        for j in 0..<4 {
            var s: CGFloat = 0
            for k in 0..<4 { s += ar[i][k] * br[k][j] }
            out[i][j] = s
        }
    }
    var r = CATransform3DIdentity
    r.rows = out
    return r
}

/// Inverse by Gauss-Jordan elimination; returns the input when singular, as Core Animation does.
public func CATransform3DInvert(_ t: CATransform3D) -> CATransform3D {
    var a = t.rows
    var inv = CATransform3DIdentity.rows
    for col in 0..<4 {
        var pivot = col
        for r in col..<4 where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
        guard abs(a[pivot][col]) > 1e-12 else { return t }
        a.swapAt(col, pivot); inv.swapAt(col, pivot)
        let p = a[col][col]
        for j in 0..<4 { a[col][j] /= p; inv[col][j] /= p }
        for r in 0..<4 where r != col {
            let f = a[r][col]
            guard f != 0 else { continue }
            for j in 0..<4 { a[r][j] -= f * a[col][j]; inv[r][j] -= f * inv[col][j] }
        }
    }
    var out = CATransform3DIdentity
    out.rows = inv
    return out
}

public func CATransform3DMakeAffineTransform(_ m: CGAffineTransform) -> CATransform3D {
    CATransform3D(m11: m.a, m12: m.b, m13: 0, m14: 0,
                  m21: m.c, m22: m.d, m23: 0, m24: 0,
                  m31: 0, m32: 0, m33: 1, m34: 0,
                  m41: m.tx, m42: m.ty, m43: 0, m44: 1)
}

public func CATransform3DIsAffine(_ t: CATransform3D) -> Bool { t.isAffine }
public func CATransform3DGetAffineTransform(_ t: CATransform3D) -> CGAffineTransform { t.affineTransform }

extension CGPoint {
    /// Applies the x/y part of a 3D transform (z = 0), with perspective divide.
    public func applying(_ t: CATransform3D) -> CGPoint {
        let x = self.x * t.m11 + self.y * t.m21 + t.m41
        let y = self.x * t.m12 + self.y * t.m22 + t.m42
        let w = self.x * t.m14 + self.y * t.m24 + t.m44
        return w != 0 && w != 1 ? CGPoint(x: x / w, y: y / w) : CGPoint(x: x, y: y)
    }
}
