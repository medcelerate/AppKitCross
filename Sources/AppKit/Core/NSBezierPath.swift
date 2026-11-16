// NSBezierPath (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath
open class NSBezierPath: NSObject, NSCopying, NSSecureCoding, NSCoding {
    // MARK: Storage
    internal enum Segment {
        case move(NSPoint)
        case line(NSPoint)
        case curve(NSPoint, NSPoint, NSPoint)      // control1, control2, end
        case quad(NSPoint, NSPoint)                 // control, end
        case close
    }
    internal var segments: [Segment] = []
    private var _lineWidth: CGFloat = NSBezierPath.defaultLineWidth
    private var _lineCapStyle: NSBezierPath.LineCapStyle = NSBezierPath.defaultLineCapStyle
    private var _lineJoinStyle: NSBezierPath.LineJoinStyle = NSBezierPath.defaultLineJoinStyle
    private var _miterLimit: CGFloat = NSBezierPath.defaultMiterLimit
    private var _flatness: CGFloat = NSBezierPath.defaultFlatness
    private var _windingRule: NSBezierPath.WindingRule = NSBezierPath.defaultWindingRule
    private var _dash: [CGFloat] = []
    private var _dashPhase: CGFloat = 0
    private var _subpathStart = NSPoint.zero

    nonisolated(unsafe) private static var _defaultLineWidth: CGFloat = 1
    nonisolated(unsafe) private static var _defaultMiterLimit: CGFloat = 10
    nonisolated(unsafe) private static var _defaultFlatness: CGFloat = 0.6
    nonisolated(unsafe) private static var _defaultLineCapStyle: NSBezierPath.LineCapStyle = .butt
    nonisolated(unsafe) private static var _defaultLineJoinStyle: NSBezierPath.LineJoinStyle = .miter
    nonisolated(unsafe) private static var _defaultWindingRule: NSBezierPath.WindingRule = .nonZero

    public override init() { super.init() }

    private func apply(to ctx: CGContext) {
        ctx.beginPath()
        ctx.addPath(cgPath)
        ctx.setLineWidth(_lineWidth)
        ctx.setMiterLimit(_miterLimit)
        ctx.setFlatness(_flatness)
        switch _lineCapStyle {
        case .round: ctx.setLineCap(.round)
        case .square: ctx.setLineCap(.square)
        default: ctx.setLineCap(.butt)
        }
        switch _lineJoinStyle {
        case .round: ctx.setLineJoin(.round)
        case .bevel: ctx.setLineJoin(.bevel)
        default: ctx.setLineJoin(.miter)
        }
        ctx.setLineDash(phase: _dashPhase, lengths: _dash)
    }

    private var fillRule: CGPathFillRule { _windingRule == .evenOdd ? .evenOdd : .winding }

    /// Appends a circular arc as cubic Bézier segments. Angles in degrees, counter-clockwise
    /// positive like AppKit.
    private func addArc(center: NSPoint, radius: CGFloat, startDeg: CGFloat, endDeg: CGFloat, clockwise: Bool, joinsCurrentPoint: Bool = false) {
        var start = startDeg * .pi / 180, end = endDeg * .pi / 180
        if clockwise { while end > start { end -= 2 * .pi } } else { while end < start { end += 2 * .pi } }
        let total = end - start
        let n = max(1, Int((abs(total) / (.pi / 2) - 1e-9).rounded(.up)))
        let step = total / CGFloat(n)
        let k = 4.0 / 3.0 * tan(step / 4)
        var a0 = start
        let p0 = NSPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0))
        if segments.isEmpty { move(to: p0) } else if !joinsCurrentPoint { line(to: p0) }
        for _ in 0..<n {
            let a1 = a0 + step
            let c0 = NSPoint(x: center.x + radius * (cos(a0) - k * sin(a0)), y: center.y + radius * (sin(a0) + k * cos(a0)))
            let c1 = NSPoint(x: center.x + radius * (cos(a1) + k * sin(a1)), y: center.y + radius * (sin(a1) - k * cos(a1)))
            let p1 = NSPoint(x: center.x + radius * cos(a1), y: center.y + radius * sin(a1))
            curve(to: p1, controlPoint1: c0, controlPoint2: c1)
            a0 = a1
        }
    }

    open override var description: String { "NSBezierPath(\(segments.count) elements, bounds \(bounds))" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/init(cgpath:)
    @available(macOS 14.0, *)
    public init(cgPath: CGPath) {
        super.init()
        self.cgPath = cgPath
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/init(ovalin:)
    public init(ovalIn rect: NSRect) {
        super.init()
        appendOval(in: rect)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/init(rect:)
    public init(rect: NSRect) {
        super.init()
        appendRect(rect)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/init(roundedrect:xradius:yradius:)
    public init(roundedRect rect: NSRect, xRadius: CGFloat, yRadius: CGFloat) {
        super.init()
        appendRoundedRect(rect, xRadius: xRadius, yRadius: yRadius)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/addclip()
    open func addClip() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.beginPath()
        ctx.addPath(cgPath)
        ctx.clip(using: fillRule)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/append(_:)
    open func append(_ path: NSBezierPath) { segments.append(contentsOf: path.segments) }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func append(withCGGlyph glyph: CGGlyph, in font: NSFont)
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func append(withCGGlyphs glyphs: UnsafePointer<CGGlyph>, count: Int, in font: NSFont)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendarc(from:to:radius:)
    /// The arc of `radius` tangent to the lines current point → point1 and point1 → point2: a
    /// line to the first tangent point, then the arc (macOS 15: nothing without a current
    /// point; a line to point1 when the three points are collinear).
    open func appendArc(from point1: NSPoint, to point2: NSPoint, radius: CGFloat) {
        guard !segments.isEmpty else { return }
        let p0 = currentPoint
        let v1 = NSPoint(x: p0.x - point1.x, y: p0.y - point1.y), v2 = NSPoint(x: point2.x - point1.x, y: point2.y - point1.y)
        let l1 = hypot(v1.x, v1.y), l2 = hypot(v2.x, v2.y)
        let cross = v1.x * v2.y - v1.y * v2.x
        guard l1 > 0, l2 > 0, abs(cross) > 1e-9 * l1 * l2, radius > 0 else { line(to: point1); return }
        let u1 = NSPoint(x: v1.x / l1, y: v1.y / l1), u2 = NSPoint(x: v2.x / l2, y: v2.y / l2)
        let angle = acos(max(-1, min(1, u1.x * u2.x + u1.y * u2.y)))   // between the two legs
        let d = radius / tan(angle / 2)                                // corner → tangent points
        let t1 = NSPoint(x: point1.x + u1.x * d, y: point1.y + u1.y * d)
        let t2 = NSPoint(x: point1.x + u2.x * d, y: point1.y + u2.y * d)
        let bis = NSPoint(x: u1.x + u2.x, y: u1.y + u2.y), bl = hypot(bis.x, bis.y)
        let h = radius / sin(angle / 2)
        let center = NSPoint(x: point1.x + bis.x / bl * h, y: point1.y + bis.y / bl * h)
        let a0 = atan2(t1.y - center.y, t1.x - center.x) * 180 / .pi
        let a1 = atan2(t2.y - center.y, t2.x - center.x) * 180 / .pi
        line(to: t1)
        addArc(center: center, radius: radius, startDeg: a0, endDeg: a1, clockwise: cross > 0, joinsCurrentPoint: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendarc(withcenter:radius:startangle:endangle:)
    open func appendArc(withCenter center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) { addArc(center: center, radius: radius, startDeg: startAngle, endDeg: endAngle, clockwise: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendarc(withcenter:radius:startangle:endangle:clockwise:)
    open func appendArc(withCenter center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) { addArc(center: center, radius: radius, startDeg: startAngle, endDeg: endAngle, clockwise: clockwise) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendglyph(_:in:)
    /// The glyph's outline with its origin at the current point, then a move one advance on
    /// (macOS 15; with no current point it raises "No current point for line").
    open func appendGlyph(_ glyph: NSGlyph, in font: NSFont) {
        var g = glyph
        appendGlyphs(&g, count: 1, in: font)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendglyphs(_:count:in:)
    open func appendGlyphs(_ glyphs: UnsafeMutablePointer<NSGlyph>, count: Int, in font: NSFont) {
        guard !segments.isEmpty else { fatalError("NSBezierPath.appendGlyphs: No current point for line") }
        #if canImport(CoreText)
        var origin = currentPoint
        for i in 0..<count {
            let g = CGGlyph(truncatingIfNeeded: glyphs[i])
            if let outline = CTFontCreatePathForGlyph(font._coreTextFont, g, nil) {
                let t = CGAffineTransform(translationX: origin.x, y: origin.y)
                outline.applyWithBlock { element in
                    let e = element.pointee
                    switch e.type {
                    case .moveToPoint: self.move(to: e.points[0].applying(t))
                    case .addLineToPoint: self.line(to: e.points[0].applying(t))
                    case .addQuadCurveToPoint: self.curve(to: e.points[1].applying(t), controlPoint: e.points[0].applying(t))
                    case .addCurveToPoint: self.curve(to: e.points[2].applying(t), controlPoint1: e.points[0].applying(t), controlPoint2: e.points[1].applying(t))
                    case .closeSubpath: self.segments.append(.close)
                    @unknown default: break
                    }
                }
            }
            origin.x += font.advancement(forGlyph: glyphs[i]).width
            move(to: origin)
        }
        #else
        unimplemented("NSBezierPath.appendGlyphs — needs CoreText")
        #endif
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendoval(in:)
    open func appendOval(in rect: NSRect) {
        // Four cubic segments; k = 4/3 * (sqrt(2) - 1).
        let k: CGFloat = 0.5522847498
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        move(to: NSPoint(x: cx + rx, y: cy))
        curve(to: NSPoint(x: cx, y: cy + ry), controlPoint1: NSPoint(x: cx + rx, y: cy + ry * k), controlPoint2: NSPoint(x: cx + rx * k, y: cy + ry))
        curve(to: NSPoint(x: cx - rx, y: cy), controlPoint1: NSPoint(x: cx - rx * k, y: cy + ry), controlPoint2: NSPoint(x: cx - rx, y: cy + ry * k))
        curve(to: NSPoint(x: cx, y: cy - ry), controlPoint1: NSPoint(x: cx - rx, y: cy - ry * k), controlPoint2: NSPoint(x: cx - rx * k, y: cy - ry))
        curve(to: NSPoint(x: cx + rx, y: cy), controlPoint1: NSPoint(x: cx + rx * k, y: cy - ry), controlPoint2: NSPoint(x: cx + rx, y: cy - ry * k))
        segments.append(.close)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendpackedglyphs(_:)
    /// Packed glyphs (NSNativeShortGlyphPacking: big-endian 16-bit, ended by a zero glyph)
    /// in the current graphics context's font (`NSFont.set()`), else the 12-point system font.
    open func appendPackedGlyphs(_ packedGlyphs: UnsafePointer<CChar>) {
        var glyphs = NSBezierPath._unpack(packedGlyphs)
        let font = NSGraphicsContext.current?._font ?? MainActor.assumeIsolated { NSFont.systemFont(ofSize: 12) }
        appendGlyphs(&glyphs, count: glyphs.count, in: font)
    }
    internal static func _unpack(_ packed: UnsafePointer<CChar>) -> [NSGlyph] {
        let bytes = UnsafeRawPointer(packed).assumingMemoryBound(to: UInt8.self)
        var out: [NSGlyph] = [], i = 0
        while true {
            let g = NSGlyph(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]))
            if g == 0 { break }
            out.append(g); i += 2
        }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendpoints(_:count:)
    open func appendPoints(_ points: NSPointArray, count: Int) {
        for i in 0..<count { if i == 0 && segments.isEmpty { move(to: points[i]) } else { line(to: points[i]) } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendrect(_:)
    open func appendRect(_ rect: NSRect) {
        move(to: NSPoint(x: rect.minX, y: rect.minY))
        line(to: NSPoint(x: rect.maxX, y: rect.minY))
        line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        line(to: NSPoint(x: rect.minX, y: rect.maxY))
        segments.append(.close)   // the shape builders close without the trailing move (macOS: 5 elements)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendroundedrect(_:xradius:yradius:)
    open func appendRoundedRect(_ rect: NSRect, xRadius: CGFloat, yRadius: CGFloat) {
        let rx = min(xRadius, rect.width / 2), ry = min(yRadius, rect.height / 2)
        guard rx > 0, ry > 0 else { appendRect(rect); return }
        let k: CGFloat = 0.5522847498
        move(to: NSPoint(x: rect.minX + rx, y: rect.minY))
        line(to: NSPoint(x: rect.maxX - rx, y: rect.minY))
        curve(to: NSPoint(x: rect.maxX, y: rect.minY + ry), controlPoint1: NSPoint(x: rect.maxX - rx + rx * k, y: rect.minY), controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + ry - ry * k))
        line(to: NSPoint(x: rect.maxX, y: rect.maxY - ry))
        curve(to: NSPoint(x: rect.maxX - rx, y: rect.maxY), controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - ry + ry * k), controlPoint2: NSPoint(x: rect.maxX - rx + rx * k, y: rect.maxY))
        line(to: NSPoint(x: rect.minX + rx, y: rect.maxY))
        curve(to: NSPoint(x: rect.minX, y: rect.maxY - ry), controlPoint1: NSPoint(x: rect.minX + rx - rx * k, y: rect.maxY), controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - ry + ry * k))
        line(to: NSPoint(x: rect.minX, y: rect.minY + ry))
        curve(to: NSPoint(x: rect.minX + rx, y: rect.minY), controlPoint1: NSPoint(x: rect.minX, y: rect.minY + ry - ry * k), controlPoint2: NSPoint(x: rect.minX + rx - rx * k, y: rect.minY))
        segments.append(.close)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/bounds
    open var bounds: NSRect { segments.isEmpty ? .zero : cgPath.boundingBoxOfPath }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/cgpath
    @available(macOS 14.0, *)
    open var cgPath: CGPath {
        get {
            let p = CGMutablePath()
            for seg in segments {
                switch seg {
                case let .move(pt): p.move(to: pt)
                case let .line(pt): p.addLine(to: pt)
                case let .curve(c1, c2, pt): p.addCurve(to: pt, control1: c1, control2: c2)
                case let .quad(c, pt): p.addQuadCurve(to: pt, control: c)
                case .close: p.closeSubpath()
                }
            }
            return p
        }
        set {
            segments.removeAll()
            newValue.applyWithBlock { element in
                let e = element.pointee
                switch e.type {
                case .moveToPoint: self.move(to: e.points[0])
                case .addLineToPoint: self.line(to: e.points[0])
                case .addQuadCurveToPoint: self.curve(to: e.points[1], controlPoint: e.points[0])
                case .addCurveToPoint: self.curve(to: e.points[2], controlPoint1: e.points[0], controlPoint2: e.points[1])
                case .closeSubpath: self.close()
                @unknown default: break
                }
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/clip(_:)
    public class func clip(_ rect: NSRect) { NSGraphicsContext.current?.cgContext.clip(to: rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/close()
    /// Closes the subpath and, as macOS does, starts a new one at the subpath's first point
    /// (an implicit move: `close()` adds two elements).
    open func close() {
        guard !segments.isEmpty else { return }
        segments.append(.close)
        segments.append(.move(_subpathStart))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/contains(_:)
    open func contains(_ point: NSPoint) -> Bool { cgPath.contains(point, using: fillRule) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/controlpointbounds
    open var controlPointBounds: NSRect { segments.isEmpty ? .zero : cgPath.boundingBox }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/currentpoint
    open var currentPoint: NSPoint {
        for seg in segments.reversed() {
            switch seg {
            case let .move(p), let .line(p): return p
            case let .curve(_, _, p), let .quad(_, p): return p
            case .close: return _subpathStart
            }
        }
        return .zero
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/curve(to:controlpoint1:controlpoint2:)
    open func curve(to endPoint: NSPoint, controlPoint1: NSPoint, controlPoint2: NSPoint) { segments.append(.curve(controlPoint1, controlPoint2, endPoint)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/curve(to:controlpoint:)
    @available(macOS 14.0, *)
    open func curve(to endPoint: NSPoint, controlPoint: NSPoint) { segments.append(.quad(controlPoint, endPoint)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/defaultflatness
    class public var defaultFlatness: CGFloat {
        get { _defaultFlatness }
        set { _defaultFlatness = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/defaultlinecapstyle
    class public var defaultLineCapStyle: NSBezierPath.LineCapStyle {
        get { _defaultLineCapStyle }
        set { _defaultLineCapStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/defaultlinejoinstyle
    class public var defaultLineJoinStyle: NSBezierPath.LineJoinStyle {
        get { _defaultLineJoinStyle }
        set { _defaultLineJoinStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/defaultlinewidth
    class public var defaultLineWidth: CGFloat {
        get { _defaultLineWidth }
        set { _defaultLineWidth = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/defaultmiterlimit
    class public var defaultMiterLimit: CGFloat {
        get { _defaultMiterLimit }
        set { _defaultMiterLimit = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/defaultwindingrule
    class public var defaultWindingRule: NSBezierPath.WindingRule {
        get { _defaultWindingRule }
        set { _defaultWindingRule = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/drawpackedglyphs(_:at:)
    /// Fills the packed glyphs' outlines at `point` in the current colour (see `appendPackedGlyphs`).
    public class func drawPackedGlyphs(_ packedGlyphs: UnsafePointer<CChar>, at point: NSPoint) {
        let p = NSBezierPath()
        p.move(to: point)
        p.appendPackedGlyphs(packedGlyphs)
        p.fill()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/element(at:)
    open func element(at index: Int) -> NSBezierPath.ElementType { element(at: index, associatedPoints: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/element(at:associatedpoints:)
    open func element(at index: Int, associatedPoints points: NSPointArray?) -> NSBezierPath.ElementType {
        switch segments[index] {
        case let .move(p): points?[0] = p; return .moveTo
        case let .line(p): points?[0] = p; return .lineTo
        case let .curve(c1, c2, p): points?[0] = c1; points?[1] = c2; points?[2] = p; return .cubicCurveTo
        case let .quad(c, p): points?[0] = c; points?[1] = p; return .quadraticCurveTo
        case .close: return .closePath
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/elementcount
    open var elementCount: Int { segments.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/fill()
    open func fill() {
        guard let ctx = NSGraphicsContext.current?.cgContext, !segments.isEmpty else { return }
        apply(to: ctx)
        ctx.fillPath(using: fillRule)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/fill(_:)
    public class func fill(_ rect: NSRect) { NSGraphicsContext.current?.cgContext.fill(rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/flatness
    open var flatness: CGFloat {
        get { _flatness }
        set { _flatness = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/flattened
    /// Curves replaced by lines within `flatness` (Wang's bound on the subdivision; macOS 15
    /// uses a fixed eight lines a quarter circle whatever the flatness). Closes keep their
    /// implicit move, as macOS's rebuilt paths do.
    open var flattened: NSBezierPath {
        let out = copy() as! NSBezierPath
        out.segments.removeAll()
        var current = NSPoint.zero, start = NSPoint.zero
        let tol = max(_flatness, 0.01)
        func lines(_ pts: [NSPoint]) {
            // Wang: n ≥ sqrt(d(d-1)/8 · M / tol), M the largest second difference of the control net.
            var m: CGFloat = 0
            if pts.count >= 3 { for i in 0..<(pts.count - 2) { m = max(m, hypot(pts[i].x - 2 * pts[i + 1].x + pts[i + 2].x, pts[i].y - 2 * pts[i + 1].y + pts[i + 2].y)) } }
            let degree = CGFloat(pts.count - 1)
            let n = max(1, Int(sqrt(degree * (degree - 1) / 8 * m / tol).rounded(.up)))
            for k in 1...n {
                let t = CGFloat(k) / CGFloat(n), u = 1 - t
                let p: NSPoint
                if pts.count == 4 {
                    p = NSPoint(x: u*u*u*pts[0].x + 3*u*u*t*pts[1].x + 3*u*t*t*pts[2].x + t*t*t*pts[3].x, y: u*u*u*pts[0].y + 3*u*u*t*pts[1].y + 3*u*t*t*pts[2].y + t*t*t*pts[3].y)
                } else {
                    p = NSPoint(x: u*u*pts[0].x + 2*u*t*pts[1].x + t*t*pts[2].x, y: u*u*pts[0].y + 2*u*t*pts[1].y + t*t*pts[2].y)
                }
                out.segments.append(.line(k == n ? pts[pts.count - 1] : p))
            }
        }
        for seg in segments {
            switch seg {
            case let .move(p): out.move(to: p); current = p; start = p
            case let .line(p): out.segments.append(.line(p)); current = p
            case let .curve(c1, c2, p): lines([current, c1, c2, p]); current = p
            case let .quad(c, p): lines([current, c, p]); current = p
            case .close: out._subpathStart = start; out.close(); current = start
            }
        }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/getlinedash(_:count:phase:)
    open func getLineDash(_ pattern: UnsafeMutablePointer<CGFloat>?, count: UnsafeMutablePointer<Int>?, phase: UnsafeMutablePointer<CGFloat>?) {
        if let pattern { for (i, v) in _dash.enumerated() { pattern[i] = v } }
        count?.pointee = _dash.count
        phase?.pointee = _dashPhase
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/isempty
    open var isEmpty: Bool { segments.isEmpty }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/line(to:)
    open func line(to point: NSPoint) { segments.append(.line(point)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/linecapstyle
    open var lineCapStyle: NSBezierPath.LineCapStyle {
        get { _lineCapStyle }
        set { _lineCapStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/linejoinstyle
    open var lineJoinStyle: NSBezierPath.LineJoinStyle {
        get { _lineJoinStyle }
        set { _lineJoinStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/linewidth
    open var lineWidth: CGFloat {
        get { _lineWidth }
        set { _lineWidth = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/miterlimit
    open var miterLimit: CGFloat {
        get { _miterLimit }
        set { _miterLimit = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/move(to:)
    /// A move right after a move replaces it (macOS keeps one).
    open func move(to point: NSPoint) {
        if case .move? = segments.last { segments[segments.count - 1] = .move(point) } else { segments.append(.move(point)) }
        _subpathStart = point
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/relativecurve(to:controlpoint1:controlpoint2:)
    open func relativeCurve(to endPoint: NSPoint, controlPoint1: NSPoint, controlPoint2: NSPoint) {
        let c = currentPoint
        curve(to: NSPoint(x: c.x + endPoint.x, y: c.y + endPoint.y),
              controlPoint1: NSPoint(x: c.x + controlPoint1.x, y: c.y + controlPoint1.y),
              controlPoint2: NSPoint(x: c.x + controlPoint2.x, y: c.y + controlPoint2.y))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/relativecurve(to:controlpoint:)
    @available(macOS 14.0, *)
    open func relativeCurve(to endPoint: NSPoint, controlPoint: NSPoint) {
        let c = currentPoint
        curve(to: NSPoint(x: c.x + endPoint.x, y: c.y + endPoint.y), controlPoint: NSPoint(x: c.x + controlPoint.x, y: c.y + controlPoint.y))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/relativeline(to:)
    open func relativeLine(to point: NSPoint) { let c = currentPoint; line(to: NSPoint(x: c.x + point.x, y: c.y + point.y)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/relativemove(to:)
    open func relativeMove(to point: NSPoint) { let c = currentPoint; move(to: NSPoint(x: c.x + point.x, y: c.y + point.y)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/removeallpoints()
    open func removeAllPoints() { segments.removeAll() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/reversed
    /// Each subpath traced backwards, in the original subpath order; a closed subpath starts
    /// from its first point again and keeps its close (with the implicit move, macOS 15).
    open var reversed: NSBezierPath {
        let out = copy() as! NSBezierPath
        out.segments.removeAll()
        struct Sub { var start: NSPoint; var parts: [Segment] = []; var ends: [NSPoint] = []; var closed = false }
        var subs: [Sub] = []
        for seg in segments {
            switch seg {
            case let .move(p):
                // The implicit move after a close (or a lone move) starts an empty subpath.
                subs.append(Sub(start: p))
            case .close:
                if !subs.isEmpty { subs[subs.count - 1].closed = true }
            case let .line(p), let .curve(_, _, p), let .quad(_, p):
                if subs.isEmpty { subs.append(Sub(start: .zero)) }
                subs[subs.count - 1].parts.append(seg)
                subs[subs.count - 1].ends.append(p)
            }
        }
        for sub in subs where !sub.parts.isEmpty {
            let v = [sub.start] + sub.ends        // v[i] is where part i (1-based) ends
            let n = sub.parts.count
            func reversedPart(_ i: Int) -> Segment {   // part i traced from v[i] back to v[i-1]
                switch sub.parts[i - 1] {
                case let .curve(c1, c2, _): return .curve(c2, c1, v[i - 1])
                case let .quad(c, _): return .quad(c, v[i - 1])
                default: return .line(v[i - 1])
                }
            }
            if sub.closed {
                // Start where the original started; the close's edge comes first, then the
                // parts backwards; the first part, a line, is the new close.
                out.move(to: sub.start)
                if v[n] != sub.start { out.segments.append(.line(v[n])) }
                for i in stride(from: n, through: 2, by: -1) { out.segments.append(reversedPart(i)) }
                if case .line = sub.parts[0] {} else { out.segments.append(reversedPart(1)) }
                out._subpathStart = sub.start
                out.close()
            } else {
                out.move(to: v[n])
                for i in stride(from: n, through: 1, by: -1) { out.segments.append(reversedPart(i)) }
            }
        }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/setassociatedpoints(_:at:)
    open func setAssociatedPoints(_ points: NSPointArray?, at index: Int) {
        guard let points else { return }
        switch segments[index] {
        case .move: segments[index] = .move(points[0])
        case .line: segments[index] = .line(points[0])
        case .curve: segments[index] = .curve(points[0], points[1], points[2])
        case .quad: segments[index] = .quad(points[0], points[1])
        case .close: break
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/setclip()
    open func setClip() { addClip() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/setlinedash(_:count:phase:)
    open func setLineDash(_ pattern: UnsafePointer<CGFloat>?, count: Int, phase: CGFloat) {
        _dash = pattern.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? []
        _dashPhase = phase
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/stroke()
    open func stroke() {
        guard let ctx = NSGraphicsContext.current?.cgContext, !segments.isEmpty else { return }
        apply(to: ctx)
        ctx.strokePath()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/stroke(_:)
    public class func stroke(_ rect: NSRect) { let p = NSBezierPath(rect: rect); p.stroke() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/strokeline(from:to:)
    public class func strokeLine(from point1: NSPoint, to point2: NSPoint) { let p = NSBezierPath(); p.move(to: point1); p.line(to: point2); p.stroke() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/transform(using:)
    open func transform(using transform: AffineTransform) {
        segments = segments.map { seg in
            switch seg {
            case let .move(p): return .move(transform.transform(p))
            case let .line(p): return .line(transform.transform(p))
            case let .curve(c1, c2, p): return .curve(transform.transform(c1), transform.transform(c2), transform.transform(p))
            case let .quad(c, p): return .quad(transform.transform(c), transform.transform(p))
            case .close: return .close
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/windingrule
    open var windingRule: NSBezierPath.WindingRule {
        get { _windingRule }
        set { _windingRule = newValue }
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let p = NSBezierPath()
        p.segments = segments
        p._lineWidth = _lineWidth; p._lineCapStyle = _lineCapStyle; p._lineJoinStyle = _lineJoinStyle
        p._miterLimit = _miterLimit; p._flatness = _flatness; p._windingRule = _windingRule
        p._dash = _dash; p._dashPhase = _dashPhase; p._subpathStart = _subpathStart
        return p
    }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    /// AppKit's keys: `NSSegments` (per point: a type byte — 0 move, 1 line, 2 cubic, 3 close,
    /// 4 quadratic — and big-endian Float32 x, y; a curve writes one entry per point) and the
    /// attributes that differ from their defaults.
    open func encode(with coder: NSCoder) {
        var data = Data()
        func put(_ type: UInt8, _ p: NSPoint) {
            data.append(type)
            for v in [Float(p.x), Float(p.y)] { withUnsafeBytes(of: v.bitPattern.bigEndian) { data.append(contentsOf: $0) } }
        }
        var start = NSPoint.zero
        for seg in segments {
            switch seg {
            case let .move(p): put(0, p); start = p
            case let .line(p): put(1, p)
            case let .curve(c1, c2, p): put(2, c1); put(2, c2); put(2, p)
            case let .quad(c, p): put(4, c); put(4, p)
            case .close: put(3, start)
            }
        }
        coder.encode(data, forKey: "NSSegments")
        if _lineWidth != 1 { coder.encode(Double(_lineWidth), forKey: "NSLineWidth") }
        if _lineCapStyle != .butt { coder.encode(Int(_lineCapStyle.rawValue), forKey: "NSCapStyle") }
        if _lineJoinStyle != .miter { coder.encode(Int(_lineJoinStyle.rawValue), forKey: "NSJoinStyle") }
        if _miterLimit != 10 { coder.encode(Double(_miterLimit), forKey: "NSMiterLimit") }
        if _flatness != 0.6 { coder.encode(Double(_flatness), forKey: "NSFlatness") }
        if _windingRule != .nonZero { coder.encode(Int(_windingRule.rawValue), forKey: "NSWindingRule") }
        if !_dash.isEmpty {
            var d = Data()
            for v in _dash { withUnsafeBytes(of: Float(v).bitPattern.bigEndian) { d.append(contentsOf: $0) } }
            coder.encode(d, forKey: "NSDashPatterns")
            coder.encode(Double(_dashPhase), forKey: "NSDashPhase")
        }
    }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) {
        super.init()
        func float(_ d: Data, _ at: Int) -> CGFloat {
            var bits: UInt32 = 0
            for k in 0..<4 { bits = bits << 8 | UInt32(d[d.startIndex + at + k]) }
            return CGFloat(Float(bitPattern: bits))
        }
        if let data = coder._decodeObjectIfPresent(forKey: "NSSegments") as? Data {
            var i = 0, pending: [NSPoint] = []
            while i + 9 <= data.count {
                let type = data[data.startIndex + i]
                let p = NSPoint(x: float(data, i + 1), y: float(data, i + 5))
                i += 9
                switch type {
                case 0: segments.append(.move(p)); _subpathStart = p
                case 1: segments.append(.line(p))
                case 2: pending.append(p); if pending.count == 3 { segments.append(.curve(pending[0], pending[1], pending[2])); pending.removeAll() }
                case 4: pending.append(p); if pending.count == 2 { segments.append(.quad(pending[0], pending[1])); pending.removeAll() }
                case 3: segments.append(.close)
                default: break
                }
            }
        }
        if coder.containsValue(forKey: "NSLineWidth") { _lineWidth = CGFloat(coder.decodeDouble(forKey: "NSLineWidth")) }
        if coder.containsValue(forKey: "NSCapStyle") { _lineCapStyle = NSBezierPath.LineCapStyle(rawValue: coder.decodeInteger(forKey: "NSCapStyle")) ?? .butt }
        if coder.containsValue(forKey: "NSJoinStyle") { _lineJoinStyle = NSBezierPath.LineJoinStyle(rawValue: coder.decodeInteger(forKey: "NSJoinStyle")) ?? .miter }
        if coder.containsValue(forKey: "NSMiterLimit") { _miterLimit = CGFloat(coder.decodeDouble(forKey: "NSMiterLimit")) }
        if coder.containsValue(forKey: "NSFlatness") { _flatness = CGFloat(coder.decodeDouble(forKey: "NSFlatness")) }
        if coder.containsValue(forKey: "NSWindingRule") { _windingRule = NSBezierPath.WindingRule(rawValue: coder.decodeInteger(forKey: "NSWindingRule")) ?? .nonZero }
        if let d = coder._decodeObjectIfPresent(forKey: "NSDashPatterns") as? Data {
            _dash = stride(from: 0, to: d.count - 3, by: 4).map { float(d, $0) }
            _dashPhase = CGFloat(coder.decodeDouble(forKey: "NSDashPhase"))
        }
    }
}
