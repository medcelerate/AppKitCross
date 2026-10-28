// CGContext over a Direct2D render target, reached through the CD2D shim.
//
// The context mirrors CoreGraphics' state model (CTM, colors, line state, clip, alpha,
// current path) and translates each drawing call into Direct2D geometry and brush calls.
// Coordinates handed to Direct2D are in DIPs; the window sets the render target's DPI so
// one DIP equals one AppKit point.

import Foundation
#if os(Windows)
import CD2D

public final class CGContext {
    // MARK: Graphics state
    private struct State {
        var ctm = CGAffineTransform.identity
        var fill: CGColor = .black
        var stroke: CGColor = .black
        var lineWidth: CGFloat = 1
        var lineCap: CGLineCap = .butt
        var lineJoin: CGLineJoin = .miter
        var miterLimit: CGFloat = 10
        var dashPhase: CGFloat = 0
        var dashLengths: [CGFloat] = []
        var alpha: CGFloat = 1
        var antialias = true
        var blend: CGBlendMode = .normal
        var interpolation: CGInterpolationQuality = .default
        var clipPushes = 0         // clips pushed while this state was current
        var clipBox = CGRect.infinite
    }
    private enum ClipKind { case rect, path }

    private var state = State()
    private var stack: [State] = []
    private var clipKinds: [ClipKind] = []
    private var currentPath = CGMutablePath()

    private let target: OpaquePointer          // CD2DTarget*
    private let factory: OpaquePointer         // CD2DFactory*
    private let fillBrush: OpaquePointer?
    private let strokeBrush: OpaquePointer?
    /// Applied after the CTM; typically the y flip that makes the context bottom-left based.
    private let baseTransform: CGAffineTransform

    public private(set) var width: Int
    public private(set) var height: Int

    /// Wraps a CD2D render target that is between begin_draw and end_draw for the
    /// lifetime of the context.
    public init(target: OpaquePointer, factory: OpaquePointer, baseTransform: CGAffineTransform, width: Int, height: Int) {
        self.target = target
        self.factory = factory
        self.baseTransform = baseTransform
        self.width = width
        self.height = height
        fillBrush = cd2d_brush_create(target, 0, 0, 0, 1)
        strokeBrush = cd2d_brush_create(target, 0, 0, 0, 1)
        applyTransform()
    }

    deinit {
        while !stack.isEmpty { restoreGState() }
        popClips(state.clipPushes)
        cd2d_brush_release(fillBrush)
        cd2d_brush_release(strokeBrush)
    }

    // MARK: State

    public func saveGState() {
        stack.append(state)
        state.clipPushes = 0
    }

    public func restoreGState() {
        guard let saved = stack.popLast() else { return }
        popClips(state.clipPushes)
        state = saved
        applyTransform()
        cd2d_target_set_antialias(target, state.antialias)
    }

    public var ctm: CGAffineTransform { state.ctm }
    public func translateBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(translationX: x, y: y).concatenating(state.ctm); applyTransform() }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(scaleX: x, y: y).concatenating(state.ctm); applyTransform() }
    public func rotate(by angle: CGFloat) { state.ctm = CGAffineTransform(rotationAngle: angle).concatenating(state.ctm); applyTransform() }
    public func concatenate(_ t: CGAffineTransform) { state.ctm = t.concatenating(state.ctm); applyTransform() }

    private func applyTransform() {
        let t = state.ctm.concatenating(baseTransform)
        var m = CD2DMatrix(m11: Float(t.a), m12: Float(t.b), m21: Float(t.c), m22: Float(t.d), dx: Float(t.tx), dy: Float(t.ty))
        cd2d_target_set_transform(target, &m)
    }

    public func setFillColor(_ color: CGColor) { state.fill = color }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.fill = CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    public func setFillColor(gray: CGFloat, alpha: CGFloat) { state.fill = CGColor(gray: gray, alpha: alpha) }
    public func setStrokeColor(_ color: CGColor) { state.stroke = color }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { state.stroke = CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    public func setStrokeColor(gray: CGFloat, alpha: CGFloat) { state.stroke = CGColor(gray: gray, alpha: alpha) }
    public func setLineWidth(_ width: CGFloat) { state.lineWidth = width }
    public func setLineCap(_ cap: CGLineCap) { state.lineCap = cap }
    public func setLineJoin(_ join: CGLineJoin) { state.lineJoin = join }
    public func setMiterLimit(_ limit: CGFloat) { state.miterLimit = limit }
    public func setFlatness(_ flatness: CGFloat) { }
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) { state.dashPhase = phase; state.dashLengths = lengths }
    public func setAlpha(_ alpha: CGFloat) { state.alpha = alpha }
    public func setBlendMode(_ mode: CGBlendMode) { state.blend = mode }   // Needs ID2D1DeviceContext (Milestone 3).
    public func setPatternPhase(_ phase: CGSize) { }
    public var interpolationQuality: CGInterpolationQuality {
        get { state.interpolation }
        set { state.interpolation = newValue }
    }
    public func setShouldAntialias(_ on: Bool) {
        state.antialias = on
        cd2d_target_set_antialias(target, on)
    }
    public func setShouldSmoothFonts(_ on: Bool) { }
    public func setAllowsAntialiasing(_ on: Bool) { }

    // MARK: Path construction

    public func beginPath() { currentPath = CGMutablePath() }
    public func move(to p: CGPoint) { currentPath.move(to: p) }
    public func addLine(to p: CGPoint) { currentPath.addLine(to: p) }
    public func addLines(between points: [CGPoint]) { currentPath.addLines(between: points) }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { currentPath.addCurve(to: end, control1: control1, control2: control2) }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) { currentPath.addQuadCurve(to: end, control: control) }
    public func addRect(_ rect: CGRect) { currentPath.addRect(rect) }
    public func addRects(_ rects: [CGRect]) { currentPath.addRects(rects) }
    public func addEllipse(in rect: CGRect) { currentPath.addEllipse(in: rect) }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        currentPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
    }
    public func addPath(_ p: CGPath) { currentPath.addPath(p) }
    public func closePath() { currentPath.closeSubpath() }
    public var isPathEmpty: Bool { currentPath.isEmpty }
    public var currentPointOfPath: CGPoint { currentPath.currentPoint }
    public var boundingBoxOfPath: CGRect { currentPath.boundingBoxOfPath }
    public var path: CGPath? { currentPath.copy() }

    // MARK: Painting

    public func fillPath(using rule: CGPathFillRule = .winding) {
        defer { currentPath = CGMutablePath() }
        guard let geometry = makeGeometry(currentPath, rule: rule) else { return }
        defer { cd2d_path_release(geometry) }
        cd2d_target_fill_path(target, geometry, configure(fillBrush, color: state.fill))
    }

    public func strokePath() {
        defer { currentPath = CGMutablePath() }
        guard let geometry = makeGeometry(currentPath, rule: .winding) else { return }
        defer { cd2d_path_release(geometry) }
        let style = makeStrokeStyle()
        defer { cd2d_stroke_style_release(style) }
        cd2d_target_stroke_path(target, geometry, configure(strokeBrush, color: state.stroke), Float(state.lineWidth), style)
    }

    public func drawPath(using mode: CGPathDrawingMode) {
        let saved = currentPath.mutableCopy() ?? CGMutablePath()
        switch mode {
        case .fill: fillPath(using: .winding)
        case .eoFill: fillPath(using: .evenOdd)
        case .stroke: strokePath()
        case .fillStroke, .eoFillStroke:
            fillPath(using: mode == .eoFillStroke ? .evenOdd : .winding)
            currentPath = saved
            strokePath()
        }
    }

    public func fill(_ rect: CGRect) {
        let r = rect.standardized
        cd2d_target_fill_rect(target, Float(r.minX), Float(r.minY), Float(r.maxX), Float(r.maxY), configure(fillBrush, color: state.fill))
    }
    public func fill(_ rects: [CGRect]) { for r in rects { fill(r) } }

    public func stroke(_ rect: CGRect) {
        let r = rect.standardized
        let style = makeStrokeStyle()
        defer { cd2d_stroke_style_release(style) }
        cd2d_target_stroke_rect(target, Float(r.minX), Float(r.minY), Float(r.maxX), Float(r.maxY),
                                configure(strokeBrush, color: state.stroke), Float(state.lineWidth), style)
    }
    public func stroke(_ rect: CGRect, width: CGFloat) {
        let w = state.lineWidth
        state.lineWidth = width
        stroke(rect)
        state.lineWidth = w
    }

    public func fillEllipse(in rect: CGRect) { beginPath(); addEllipse(in: rect); fillPath() }
    public func strokeEllipse(in rect: CGRect) { beginPath(); addEllipse(in: rect); strokePath() }
    public func strokeLineSegments(between points: [CGPoint]) {
        beginPath()
        var i = 0
        while i + 1 < points.count { move(to: points[i]); addLine(to: points[i + 1]); i += 2 }
        strokePath()
    }

    public func clear(_ rect: CGRect) {
        let saved = state.fill
        state.fill = .clear
        fill(rect)
        state.fill = saved
    }

    // MARK: Clipping

    public func clip(to rect: CGRect) {
        let r = rect.standardized
        cd2d_target_push_clip_rect(target, Float(r.minX), Float(r.minY), Float(r.maxX), Float(r.maxY), state.antialias)
        clipKinds.append(.rect)
        state.clipPushes += 1
        state.clipBox = state.clipBox.intersection(r)
    }
    public func clip(to rects: [CGRect]) {
        guard let first = rects.first else { return }
        clip(to: rects.dropFirst().reduce(first) { $0.union($1) })
    }

    public func clip(using rule: CGPathFillRule = .winding) {
        defer { currentPath = CGMutablePath() }
        guard let geometry = makeGeometry(currentPath, rule: rule) else { return }
        cd2d_target_push_clip_path(target, geometry)
        cd2d_path_release(geometry)      // the layer keeps the geometry alive
        clipKinds.append(.path)
        state.clipPushes += 1
        state.clipBox = state.clipBox.intersection(currentPath.boundingBoxOfPath)
    }

    public var clipBoundingBox: CGRect { state.clipBox }

    private func popClips(_ n: Int) {
        for _ in 0..<n {
            guard let kind = clipKinds.popLast() else { break }
            switch kind {
            case .rect: cd2d_target_pop_clip_rect(target)
            case .path: cd2d_target_pop_clip_path(target)
            }
        }
    }

    // MARK: Flush

    public func flush() { }
    public func synchronize() { }

    // MARK: Direct2D plumbing

    private func configure(_ brush: OpaquePointer?, color: CGColor) -> OpaquePointer? {
        let (r, g, b, a) = color.rgba
        cd2d_brush_set_color(brush, Float(r), Float(g), Float(b), Float(a * state.alpha))
        return brush
    }

    private func makeStrokeStyle() -> OpaquePointer? {
        let cap: Int32 = state.lineCap == .round ? Int32(CD2D_CAP_ROUND) : state.lineCap == .square ? Int32(CD2D_CAP_SQUARE) : Int32(CD2D_CAP_FLAT)
        let join: Int32 = state.lineJoin == .round ? Int32(CD2D_JOIN_ROUND) : state.lineJoin == .bevel ? Int32(CD2D_JOIN_BEVEL) : Int32(CD2D_JOIN_MITER)
        // Direct2D dash lengths are multiples of the stroke width.
        let w = max(state.lineWidth, 0.0001)
        let dashes = state.dashLengths.map { Float($0 / w) }
        return dashes.withUnsafeBufferPointer { buf in
            cd2d_stroke_style_create(factory, cap, join, Float(state.miterLimit), buf.baseAddress, UInt32(buf.count), Float(state.dashPhase / w))
        }
    }

    private func makeGeometry(_ p: CGPath, rule: CGPathFillRule) -> OpaquePointer? {
        guard !p.isEmpty, let geometry = cd2d_path_create(factory, rule == .evenOdd) else { return nil }
        var figureOpen = false
        var figureStart = CGPoint.zero
        var last = CGPoint.zero
        func ensureFigure() {
            if !figureOpen {
                cd2d_path_begin_figure(geometry, Float(last.x), Float(last.y))
                figureOpen = true
                figureStart = last
            }
        }
        for e in p.elements {
            switch e {
            case let .move(pt):
                if figureOpen { cd2d_path_end_figure(geometry, false) }
                cd2d_path_begin_figure(geometry, Float(pt.x), Float(pt.y))
                figureOpen = true
                figureStart = pt
                last = pt
            case let .line(pt):
                ensureFigure()
                cd2d_path_add_line(geometry, Float(pt.x), Float(pt.y))
                last = pt
            case let .quad(c, pt):
                ensureFigure()
                cd2d_path_add_quad(geometry, Float(c.x), Float(c.y), Float(pt.x), Float(pt.y))
                last = pt
            case let .curve(c1, c2, pt):
                ensureFigure()
                cd2d_path_add_bezier(geometry, Float(c1.x), Float(c1.y), Float(c2.x), Float(c2.y), Float(pt.x), Float(pt.y))
                last = pt
            case .close:
                if figureOpen { cd2d_path_end_figure(geometry, true); figureOpen = false }
                last = figureStart
            }
        }
        if figureOpen { cd2d_path_end_figure(geometry, false) }
        cd2d_path_close(geometry)
        return geometry
    }
}
#endif
