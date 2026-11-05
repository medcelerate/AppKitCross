import Foundation

public enum CGPathElementType: Int32, Sendable {
    case moveToPoint = 0, addLineToPoint = 1, addQuadCurveToPoint = 2, addCurveToPoint = 3, closeSubpath = 4
}

public struct CGPathElement {
    public var type: CGPathElementType
    public var points: UnsafeMutablePointer<CGPoint>
}

/// An immutable path. `CGMutablePath` adds the building methods, as in CoreGraphics.
public class CGPath: @unchecked Sendable {
    enum Element {
        case move(CGPoint), line(CGPoint), quad(CGPoint, CGPoint), curve(CGPoint, CGPoint, CGPoint), close
    }
    var elements: [Element] = []

    public init() {}
    public init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>? = nil) {
        let m = CGMutablePath()
        m.addRect(rect, transform: transform?.pointee ?? .identity)
        elements = m.elements
    }
    public init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>? = nil) {
        let m = CGMutablePath()
        m.addEllipse(in: rect, transform: transform?.pointee ?? .identity)
        elements = m.elements
    }
    public init(roundedRect rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: UnsafePointer<CGAffineTransform>? = nil) {
        let m = CGMutablePath()
        m.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: transform?.pointee ?? .identity)
        elements = m.elements
    }

    public var isEmpty: Bool { elements.isEmpty }

    /// The last point drawn; after a close, the start of that subpath (as CoreGraphics).
    public var currentPoint: CGPoint {
        for (i, e) in elements.enumerated().reversed() {
            switch e {
            case let .move(p): return p
            case let .line(p), let .quad(_, p), let .curve(_, _, p): return p
            case .close:
                for j in stride(from: i - 1, through: 0, by: -1) { if case let .move(p) = elements[j] { return p } }
                return .zero
            }
        }
        return .zero
    }

    /// Bounding box of all points, control points included.
    public var boundingBox: CGRect {
        var pts: [CGPoint] = []
        for e in elements {
            switch e {
            case let .move(p), let .line(p): pts.append(p)
            case let .quad(c, p): pts += [c, p]
            case let .curve(c1, c2, p): pts += [c1, c2, p]
            case .close: break
            }
        }
        return CGPath.bounds(of: pts)
    }

    /// Bounding box of the path itself (curves flattened).
    public var boundingBoxOfPath: CGRect { CGPath.bounds(of: flattened().flatMap { $0 }) }

    public func copy() -> CGPath? {
        let p = CGMutablePath()
        p.elements = elements
        return p
    }
    public func mutableCopy() -> CGMutablePath? {
        let p = CGMutablePath()
        p.elements = elements
        return p
    }
    public func copy(using transform: UnsafePointer<CGAffineTransform>?) -> CGPath? {
        guard let t = transform?.pointee else { return copy() }
        let p = CGMutablePath()
        p.elements = elements.map { e in
            switch e {
            case let .move(a): return .move(a.applying(t))
            case let .line(a): return .line(a.applying(t))
            case let .quad(c, a): return .quad(c.applying(t), a.applying(t))
            case let .curve(c1, c2, a): return .curve(c1.applying(t), c2.applying(t), a.applying(t))
            case .close: return .close
            }
        }
        return p
    }

    public func applyWithBlock(_ block: (UnsafePointer<CGPathElement>) -> Void) {
        let buffer = UnsafeMutablePointer<CGPoint>.allocate(capacity: 3)
        defer { buffer.deallocate() }
        for e in elements {
            var el: CGPathElement
            switch e {
            case let .move(p): buffer[0] = p; el = CGPathElement(type: .moveToPoint, points: buffer)
            case let .line(p): buffer[0] = p; el = CGPathElement(type: .addLineToPoint, points: buffer)
            case let .quad(c, p): buffer[0] = c; buffer[1] = p; el = CGPathElement(type: .addQuadCurveToPoint, points: buffer)
            case let .curve(c1, c2, p): buffer[0] = c1; buffer[1] = c2; buffer[2] = p; el = CGPathElement(type: .addCurveToPoint, points: buffer)
            case .close: el = CGPathElement(type: .closeSubpath, points: buffer)
            }
            withUnsafePointer(to: &el) { block($0) }
        }
    }

    public func contains(_ point: CGPoint, using rule: CGPathFillRule = .winding, transform: CGAffineTransform = .identity) -> Bool {
        let p = transform.isIdentity ? point : point.applying(transform.inverted())
        var winding = 0
        var crossings = 0
        for poly in flattened() where poly.count >= 2 {
            var j = poly.count - 1
            for i in 0..<poly.count {
                let a = poly[i], b = poly[j]
                if (a.y > p.y) != (b.y > p.y) {
                    let x = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                    if p.x < x {
                        crossings += 1
                        winding += a.y < b.y ? 1 : -1
                    }
                }
                j = i
            }
        }
        return rule == .evenOdd ? (crossings % 2 == 1) : (winding != 0)
    }

    // MARK: Flattening

    /// Subpaths as polylines; every subpath is treated as closed for hit testing.
    func flattened(tolerance: CGFloat = 0.25) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var last = CGPoint.zero
        func flush() { if !current.isEmpty { result.append(current) }; current = [] }
        for e in elements {
            switch e {
            case let .move(p): flush(); current = [p]; last = p
            case let .line(p): current.append(p); last = p
            case let .quad(c, p):
                let c1 = CGPoint(x: last.x + 2 / 3 * (c.x - last.x), y: last.y + 2 / 3 * (c.y - last.y))
                let c2 = CGPoint(x: p.x + 2 / 3 * (c.x - p.x), y: p.y + 2 / 3 * (c.y - p.y))
                current += CGPath.flattenCubic(last, c1, c2, p, tolerance: tolerance)
                last = p
            case let .curve(c1, c2, p):
                current += CGPath.flattenCubic(last, c1, c2, p, tolerance: tolerance)
                last = p
            case .close:
                if let first = current.first { last = first }
                flush()
            }
        }
        flush()
        return result
    }

    static func flattenCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, tolerance: CGFloat) -> [CGPoint] {
        let d = hypot(p1.x - p0.x, p1.y - p0.y) + hypot(p2.x - p1.x, p2.y - p1.y) + hypot(p3.x - p2.x, p3.y - p2.y)
        let n = max(1, min(64, Int((d / max(tolerance, 0.01)).squareRoot().rounded(.up))))
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        for i in 1...n {
            let t = CGFloat(i) / CGFloat(n), mt = 1 - t
            let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, dd = t * t * t
            out.append(CGPoint(x: a * p0.x + b * p1.x + c * p2.x + dd * p3.x,
                               y: a * p0.y + b * p1.y + c * p2.y + dd * p3.y))
        }
        return out
    }

    static func bounds(of pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public final class CGMutablePath: CGPath, @unchecked Sendable {
    public override init() { super.init() }

    public func move(to point: CGPoint, transform: CGAffineTransform = .identity) { elements.append(.move(point.applying(transform))) }
    public func addLine(to point: CGPoint, transform: CGAffineTransform = .identity) { elements.append(.line(point.applying(transform))) }
    public func addLines(between points: [CGPoint], transform: CGAffineTransform = .identity) {
        guard let f = points.first else { return }
        move(to: f, transform: transform)
        for p in points.dropFirst() { addLine(to: p, transform: transform) }
    }
    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        elements.append(.quad(control.applying(transform), end.applying(transform)))
    }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) {
        elements.append(.curve(control1.applying(transform), control2.applying(transform), end.applying(transform)))
    }
    public func closeSubpath() { elements.append(.close) }

    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        move(to: CGPoint(x: rect.minX, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY), transform: transform)
        addLine(to: CGPoint(x: rect.minX, y: rect.maxY), transform: transform)
        closeSubpath()
    }
    public func addRects(_ rects: [CGRect], transform: CGAffineTransform = .identity) { for r in rects { addRect(r, transform: transform) } }

    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let k: CGFloat = 0.5522847498
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        move(to: CGPoint(x: cx + rx, y: cy), transform: transform)
        addCurve(to: CGPoint(x: cx, y: cy + ry), control1: CGPoint(x: cx + rx, y: cy + ry * k), control2: CGPoint(x: cx + rx * k, y: cy + ry), transform: transform)
        addCurve(to: CGPoint(x: cx - rx, y: cy), control1: CGPoint(x: cx - rx * k, y: cy + ry), control2: CGPoint(x: cx - rx, y: cy + ry * k), transform: transform)
        addCurve(to: CGPoint(x: cx, y: cy - ry), control1: CGPoint(x: cx - rx, y: cy - ry * k), control2: CGPoint(x: cx - rx * k, y: cy - ry), transform: transform)
        addCurve(to: CGPoint(x: cx + rx, y: cy), control1: CGPoint(x: cx + rx * k, y: cy - ry), control2: CGPoint(x: cx + rx, y: cy - ry * k), transform: transform)
        closeSubpath()
    }

    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat, transform: CGAffineTransform = .identity) {
        let rx = min(cornerWidth, rect.width / 2), ry = min(cornerHeight, rect.height / 2)
        guard rx > 0, ry > 0 else { addRect(rect, transform: transform); return }
        let k: CGFloat = 0.5522847498
        move(to: CGPoint(x: rect.minX + rx, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX - rx, y: rect.minY), transform: transform)
        addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + ry), control1: CGPoint(x: rect.maxX - rx + rx * k, y: rect.minY), control2: CGPoint(x: rect.maxX, y: rect.minY + ry - ry * k), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ry), transform: transform)
        addCurve(to: CGPoint(x: rect.maxX - rx, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.maxY - ry + ry * k), control2: CGPoint(x: rect.maxX - rx + rx * k, y: rect.maxY), transform: transform)
        addLine(to: CGPoint(x: rect.minX + rx, y: rect.maxY), transform: transform)
        addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - ry), control1: CGPoint(x: rect.minX + rx - rx * k, y: rect.maxY), control2: CGPoint(x: rect.minX, y: rect.maxY - ry + ry * k), transform: transform)
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + ry), transform: transform)
        addCurve(to: CGPoint(x: rect.minX + rx, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.minY + ry - ry * k), control2: CGPoint(x: rect.minX + rx - rx * k, y: rect.minY), transform: transform)
        closeSubpath()
    }

    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool, transform: CGAffineTransform = .identity) {
        var start = startAngle, end = endAngle
        if clockwise { while end > start { end -= 2 * .pi } } else { while end < start { end += 2 * .pi } }
        let total = end - start
        let n = max(1, Int((abs(total) / (.pi / 2)).rounded(.up)))
        let step = total / CGFloat(n)
        let k = 4.0 / 3.0 * tan(step / 4)
        let p0 = CGPoint(x: center.x + radius * cos(start), y: center.y + radius * sin(start))
        if elements.isEmpty { move(to: p0, transform: transform) } else { addLine(to: p0, transform: transform) }
        var a0 = start
        for _ in 0..<n {
            let a1 = a0 + step
            let c0 = CGPoint(x: center.x + radius * (cos(a0) - k * sin(a0)), y: center.y + radius * (sin(a0) + k * cos(a0)))
            let c1 = CGPoint(x: center.x + radius * (cos(a1) + k * sin(a1)), y: center.y + radius * (sin(a1) - k * cos(a1)))
            let p1 = CGPoint(x: center.x + radius * cos(a1), y: center.y + radius * sin(a1))
            addCurve(to: p1, control1: c0, control2: c1, transform: transform)
            a0 = a1
        }
        start = end
    }

    /// An arc of `radius` tangent to the lines current point - `tangent1End` and
    /// `tangent1End` - `tangent2End`, preceded by the line to where the arc starts.
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat, transform: CGAffineTransform = .identity) {
        let p0 = currentPoint, p1 = tangent1End, p2 = tangent2End
        let d1 = CGPoint(x: p0.x - p1.x, y: p0.y - p1.y), d2 = CGPoint(x: p2.x - p1.x, y: p2.y - p1.y)
        let l1 = (d1.x * d1.x + d1.y * d1.y).squareRoot(), l2 = (d2.x * d2.x + d2.y * d2.y).squareRoot()
        guard radius > 0, l1 > 0, l2 > 0 else { addLine(to: p1, transform: transform); return }
        let u1 = CGPoint(x: d1.x / l1, y: d1.y / l1), u2 = CGPoint(x: d2.x / l2, y: d2.y / l2)
        let cross = u1.x * u2.y - u1.y * u2.x
        let cosTheta = max(-1, min(1, u1.x * u2.x + u1.y * u2.y))
        let theta = acos(cosTheta)
        guard abs(cross) > 1e-9, theta > 1e-6, theta < .pi - 1e-6 else { addLine(to: p1, transform: transform); return }
        let t = radius / tan(theta / 2)
        let t1 = CGPoint(x: p1.x + u1.x * t, y: p1.y + u1.y * t), t2 = CGPoint(x: p1.x + u2.x * t, y: p1.y + u2.y * t)
        let bis = CGPoint(x: u1.x + u2.x, y: u1.y + u2.y)
        let bl = (bis.x * bis.x + bis.y * bis.y).squareRoot()
        let c = CGPoint(x: p1.x + bis.x / bl * radius / sin(theta / 2), y: p1.y + bis.y / bl * radius / sin(theta / 2))
        addLine(to: t1, transform: transform)
        addArc(center: c, radius: radius, startAngle: atan2(t1.y - c.y, t1.x - c.x), endAngle: atan2(t2.y - c.y, t2.x - c.x), clockwise: cross > 0, transform: transform)
    }
    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) {
        if transform.isIdentity { elements += path.elements } else { elements += (path.copy(using: [transform])?.elements ?? []) }
    }
}
