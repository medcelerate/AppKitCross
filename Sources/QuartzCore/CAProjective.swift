// Perspective in the software compositor. A layer under a 3D transform with perspective
// (its own `transform`, or an ancestor's `sublayerTransform` with `m34`) maps its plane
// into the parent's plane by a projective transform, not an affine one: Core Animation
// flattens each layer's sublayers into the layer's plane, so the map from a sublayer's
// plane to its superlayer's is a 2D homography (z = 0 in, perspective divide out). A
// CGContext only has an affine CTM, so such a layer is rasterised to an offscreen surface
// and drawn through the homography as a mesh of affinely mapped cells (ADR-0005, "3D
// transforms"). DirectComposition applies the full 4x4 to the visual instead.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A 2D projective map, row-vector convention like `CATransform3D`:
/// `(x, y, 1) · M = (x', y', w')`, the point being `(x'/w', y'/w')`.
public struct _CAHomography: Equatable, Sendable {
    public var a: CGFloat, b: CGFloat, c: CGFloat     // row 1: x's contribution to x', y', w'
    public var d: CGFloat, e: CGFloat, f: CGFloat     // row 2: y's
    public var g: CGFloat, h: CGFloat, i: CGFloat     // row 3: translation and w's constant

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, e: CGFloat, f: CGFloat, g: CGFloat, h: CGFloat, i: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.e = e; self.f = f; self.g = g; self.h = h; self.i = i
    }

    /// The map of the z = 0 plane through a 4x4: rows 1, 2 and 4, columns 1, 2 and 4.
    public init(_ t: CATransform3D) {
        self.init(a: t.m11, b: t.m12, c: t.m14, d: t.m21, e: t.m22, f: t.m24, g: t.m41, h: t.m42, i: t.m44)
        if i != 0 && i != 1 { let s = 1 / i; a *= s; b *= s; c *= s; d *= s; e *= s; f *= s; g *= s; h *= s; i = 1 }
    }

    public init(_ t: CGAffineTransform) {
        self.init(a: t.a, b: t.b, c: 0, d: t.c, e: t.d, f: 0, g: t.tx, h: t.ty, i: 1)
    }

    public static let identity = _CAHomography(CGAffineTransform.identity)

    /// No perspective: the map is the affine transform `affine`.
    public var isAffine: Bool { abs(c) < 1e-12 && abs(f) < 1e-12 && i == 1 }

    /// The affine part (exact when `isAffine`).
    public var affine: CGAffineTransform { CGAffineTransform(a: a, b: b, c: d, d: e, tx: g, ty: h) }

    /// The image of `p`, or nil when it projects behind the eye (w ≤ 0).
    public func apply(_ p: CGPoint) -> CGPoint? {
        let w = p.x * c + p.y * f + i
        guard w > 1e-9 else { return nil }
        return CGPoint(x: (p.x * a + p.y * d + g) / w, y: (p.x * b + p.y * e + h) / w)
    }

    /// `self` then `t`.
    public func concatenating(_ t: _CAHomography) -> _CAHomography {
        _CAHomography(a: a * t.a + b * t.d + c * t.g, b: a * t.b + b * t.e + c * t.h, c: a * t.c + b * t.f + c * t.i,
                      d: d * t.a + e * t.d + f * t.g, e: d * t.b + e * t.e + f * t.h, f: d * t.c + e * t.f + f * t.i,
                      g: g * t.a + h * t.d + i * t.g, h: g * t.b + h * t.e + i * t.h, i: g * t.c + h * t.f + i * t.i)
    }

    public func concatenating(_ t: CGAffineTransform) -> _CAHomography { concatenating(_CAHomography(t)) }

    /// The inverse map, or nil when singular.
    public func inverted() -> _CAHomography? {
        let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
        let det = a * A + b * B + c * C
        guard abs(det) > 1e-18 else { return nil }
        let s = 1 / det
        return _CAHomography(a: A * s, b: -(b * i - c * h) * s, c: (b * f - c * e) * s,
                             d: B * s, e: (a * i - c * g) * s, f: -(a * f - c * d) * s,
                             g: C * s, h: -(a * h - b * g) * s, i: (a * e - b * d) * s)
    }

    /// The four corners of `rect` (min/min, max/min, max/max, min/max) projected, or nil
    /// when any lies behind the eye.
    public func corners(of rect: CGRect) -> [CGPoint]? {
        let pts = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                   CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        var out: [CGPoint] = []
        for p in pts { guard let q = apply(p) else { return nil }; out.append(q) }
        return out
    }

    /// The signed area of `rect`'s projection: negative when the map mirrors the plane,
    /// which for a 3D rotation means the back of the layer faces the viewer.
    public func signedArea(of rect: CGRect) -> CGFloat? {
        guard let c = corners(of: rect) else { return nil }
        var s: CGFloat = 0
        for k in 0..<4 { let p = c[k], q = c[(k + 1) % 4]; s += p.x * q.y - q.x * p.y }
        return s / 2
    }

    /// Whether a layer with this plane map shows its front: the projection keeps the
    /// plane's orientation. A single-sided layer (`isDoubleSided == false`) is hidden otherwise.
    public func showsFront(of rect: CGRect) -> Bool {
        if isAffine { return affine.a * affine.d - affine.b * affine.c > 0 }
        return (signedArea(of: rect) ?? 0) > 0
    }

    /// How much the projection magnifies `rect` at most (the nearest edge), at least 1:
    /// a raster of the plane wants that many more pixels per point to stay sharp.
    public func stretch(of rect: CGRect) -> CGFloat {
        guard rect.width > 0, rect.height > 0, let c = corners(of: rect) else { return 1 }
        let top = hypot(c[1].x - c[0].x, c[1].y - c[0].y), bottom = hypot(c[2].x - c[3].x, c[2].y - c[3].y)
        let left = hypot(c[3].x - c[0].x, c[3].y - c[0].y), right = hypot(c[2].x - c[1].x, c[2].y - c[1].y)
        return max(1, min(4, max(top, bottom) / rect.width, max(left, right) / rect.height))
    }
}

public enum _CAProjective {
    /// Draws `image`, a raster of `extent` in a source plane (`yDown` says the extent's
    /// minimum y is the top row, as `_CAPixels.render` makes it), into `ctx` through `h`,
    /// which maps the source plane to the context's current user space. An affine `h` is
    /// one draw; otherwise the extent is split into a mesh of up to 8x8 cells, each drawn
    /// with the affine transform fitted to its projected corners and clipped to them. The
    /// mesh is as fine as the projection's curvature needs: cells are added until the
    /// corner a cell's affine fit misplaces lands within half a device pixel.
    @MainActor
    public static func draw(_ image: CGImage, extent: CGRect, yDown: Bool, through h: _CAHomography, into ctx: CGContext, alpha: CGFloat) {
        if h.isAffine {
            ctx.saveGState()
            ctx.concatenate(h.affine)
            _CAPixels.blit(image, into: ctx, rect: extent, yDown: yDown, alpha: alpha)
            ctx.restoreGState()
            return
        }
        guard extent.width > 0, extent.height > 0, let whole = h.corners(of: extent) else { return }
        let ctm = ctx.ctm
        let device = whole.map { $0.applying(ctm) }
        // The deviation of the fourth corner from the parallelogram the other three span,
        // in device pixels: the error of drawing the whole extent with one affine map.
        let predicted = CGPoint(x: device[1].x + device[3].x - device[0].x, y: device[1].y + device[3].y - device[0].y)
        let deviation = hypot(device[2].x - predicted.x, device[2].y - predicted.y)
        // Subdividing n times per side divides that error by about n².
        let n = min(8, max(1, Int((deviation / 0.5).squareRoot().rounded(.up))))
        let scale = max(0.01, (abs(ctm.a * ctm.d - ctm.b * ctm.c)).squareRoot())
        let eps = 0.35 / scale           // clip overlap between neighbouring cells, so seams stay closed
        let cw = extent.width / CGFloat(n), ch = extent.height / CGFloat(n)
        for row in 0..<n {
            for col in 0..<n {
                let cell = CGRect(x: extent.minX + CGFloat(col) * cw, y: extent.minY + CGFloat(row) * ch, width: cw, height: ch)
                guard let q = h.corners(of: cell), let centre = h.apply(CGPoint(x: cell.midX, y: cell.midY)) else { continue }
                // The affine fit: the cell's centre lands on its projection; the axes are
                // the mean projected edge vectors, so each corner is off by the same amount.
                let ux = CGPoint(x: (q[1].x - q[0].x + q[2].x - q[3].x) / (2 * cw), y: (q[1].y - q[0].y + q[2].y - q[3].y) / (2 * cw))
                let uy = CGPoint(x: (q[3].x - q[0].x + q[2].x - q[1].x) / (2 * ch), y: (q[3].y - q[0].y + q[2].y - q[1].y) / (2 * ch))
                let fit = CGAffineTransform(a: ux.x, b: ux.y, c: uy.x, d: uy.y,
                                            tx: centre.x - cell.midX * ux.x - cell.midY * uy.x,
                                            ty: centre.y - cell.midX * ux.y - cell.midY * uy.y)
                let cx = (q[0].x + q[1].x + q[2].x + q[3].x) / 4, cy = (q[0].y + q[1].y + q[2].y + q[3].y) / 4
                ctx.saveGState()
                for (k, p) in q.enumerated() {
                    let len = max(1e-6, hypot(p.x - cx, p.y - cy))
                    let out = CGPoint(x: p.x + (p.x - cx) / len * eps, y: p.y + (p.y - cy) / len * eps)
                    if k == 0 { ctx.move(to: out) } else { ctx.addLine(to: out) }
                }
                ctx.closePath()
                ctx.clip()
                ctx.concatenate(fit)
                _CAPixels.blit(image, into: ctx, rect: extent, yDown: yDown, alpha: alpha)
                ctx.restoreGState()
            }
        }
    }
}
