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
    private func addArc(center: NSPoint, radius: CGFloat, startDeg: CGFloat, endDeg: CGFloat, clockwise: Bool) {
        var start = startDeg * .pi / 180, end = endDeg * .pi / 180
        if clockwise { while end > start { end -= 2 * .pi } } else { while end < start { end += 2 * .pi } }
        let total = end - start
        let n = max(1, Int((abs(total) / (.pi / 2)).rounded(.up)))
        let step = total / CGFloat(n)
        let k = 4.0 / 3.0 * tan(step / 4)
        var a0 = start
        let p0 = NSPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0))
        if segments.isEmpty { move(to: p0) } else { line(to: p0) }
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
    open func appendArc(from point1: NSPoint, to point2: NSPoint, radius: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendarc(withcenter:radius:startangle:endangle:)
    open func appendArc(withCenter center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) { addArc(center: center, radius: radius, startDeg: startAngle, endDeg: endAngle, clockwise: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendarc(withcenter:radius:startangle:endangle:clockwise:)
    open func appendArc(withCenter center: NSPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) { addArc(center: center, radius: radius, startDeg: startAngle, endDeg: endAngle, clockwise: clockwise) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendglyph(_:in:)
    open func appendGlyph(_ glyph: NSGlyph, in font: NSFont) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendglyphs(_:count:in:)
    open func appendGlyphs(_ glyphs: UnsafeMutablePointer<NSGlyph>, count: Int, in font: NSFont) { unimplemented() }
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
        close()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbezierpath/appendpackedglyphs(_:)
    open func appendPackedGlyphs(_ packedGlyphs: UnsafePointer<CChar>) { unimplemented() }
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
        close()
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
        close()
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
    open func close() { segments.append(.close) }
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
    public class func drawPackedGlyphs(_ packedGlyphs: UnsafePointer<CChar>, at point: NSPoint) { unimplemented() }
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
    open var flattened: NSBezierPath { unimplemented() }
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
    open func move(to point: NSPoint) { segments.append(.move(point)); _subpathStart = point }
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
    open var reversed: NSBezierPath { unimplemented() }
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
    class public var supportsSecureCoding: Bool { unimplemented() }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { super.init() }
}
