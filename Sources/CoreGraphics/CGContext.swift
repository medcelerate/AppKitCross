// CGContext over a Direct2D render target.
//
// The context mirrors CoreGraphics' state model (CTM, colors, line state, clip, alpha,
// current path) and translates each drawing call into Direct2D geometry and brush calls.
// Coordinates handed to Direct2D are in DIPs; callers set the DPI on the render target so
// one DIP equals one AppKit point.

import Foundation
#if os(Windows)
import WinSDK

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
        var clipPushes = 0         // Direct2D axis-aligned clips / layers pushed in this state
        var clipBox = CGRect.infinite
    }

    private var state = State()
    private var stack: [State] = []
    private var path = CGMutablePath()

    private let target: UnsafeMutablePointer<ID2D1RenderTarget>
    private let factory: UnsafeMutablePointer<ID2D1Factory>
    private var fillBrush: UnsafeMutablePointer<ID2D1SolidColorBrush>?
    private var strokeBrush: UnsafeMutablePointer<ID2D1SolidColorBrush>?
    /// Transform that maps CoreGraphics user space to the target: applied after the CTM.
    private let baseTransform: CGAffineTransform

    public private(set) var width: Int
    public private(set) var height: Int

    /// Wraps a Direct2D render target. `baseTransform` typically flips the y axis so that
    /// the context is bottom-left based like CoreGraphics. The target must be inside
    /// BeginDraw/EndDraw for the lifetime of the context.
    public init(renderTarget: UnsafeMutableRawPointer, factory: UnsafeMutableRawPointer,
                baseTransform: CGAffineTransform, width: Int, height: Int) {
        self.target = renderTarget.assumingMemoryBound(to: ID2D1RenderTarget.self)
        self.factory = factory.assumingMemoryBound(to: ID2D1Factory.self)
        self.baseTransform = baseTransform
        self.width = width
        self.height = height
        applyTransform()
        var color = d2dColor(0, 0, 0, 1)
        _ = target.pointee.lpVtbl.pointee.CreateSolidColorBrush(target, &color, nil, &fillBrush)
        _ = target.pointee.lpVtbl.pointee.CreateSolidColorBrush(target, &color, nil, &strokeBrush)
    }

    deinit {
        while stack.count > 0 { restoreGState() }
        popClips(state.clipPushes)
        if let b = fillBrush { _ = b.pointee.lpVtbl.pointee.Release(b) }
        if let b = strokeBrush { _ = b.pointee.lpVtbl.pointee.Release(b) }
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
        _ = target.pointee.lpVtbl.pointee.SetAntialiasMode(target, state.antialias ? D2D1_ANTIALIAS_MODE_PER_PRIMITIVE : D2D1_ANTIALIAS_MODE_ALIASED)
    }

    public var ctm: CGAffineTransform { state.ctm }
    public func translateBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(translationX: x, y: y).concatenating(state.ctm); applyTransform() }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(scaleX: x, y: y).concatenating(state.ctm); applyTransform() }
    public func rotate(by angle: CGFloat) { state.ctm = CGAffineTransform(rotationAngle: angle).concatenating(state.ctm); applyTransform() }
    public func concatenate(_ t: CGAffineTransform) { state.ctm = t.concatenating(state.ctm); applyTransform() }

    private func applyTransform() {
        var m = d2dMatrix(state.ctm.concatenating(baseTransform))
        target.pointee.lpVtbl.pointee.SetTransform(target, &m)
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
        _ = target.pointee.lpVtbl.pointee.SetAntialiasMode(target, on ? D2D1_ANTIALIAS_MODE_PER_PRIMITIVE : D2D1_ANTIALIAS_MODE_ALIASED)
    }
    public func setShouldSmoothFonts(_ on: Bool) { }
    public func setAllowsAntialiasing(_ on: Bool) { }

    // MARK: Path construction

    public func beginPath() { path = CGMutablePath() }
    public func move(to p: CGPoint) { path.move(to: p) }
    public func addLine(to p: CGPoint) { path.addLine(to: p) }
    public func addLines(between points: [CGPoint]) { path.addLines(between: points) }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { path.addCurve(to: end, control1: control1, control2: control2) }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) { path.addQuadCurve(to: end, control: control) }
    public func addRect(_ rect: CGRect) { path.addRect(rect) }
    public func addRects(_ rects: [CGRect]) { path.addRects(rects) }
    public func addEllipse(in rect: CGRect) { path.addEllipse(in: rect) }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
    }
    public func addPath(_ p: CGPath) { path.addPath(p) }
    public func closePath() { path.closeSubpath() }
    public var isPathEmpty: Bool { path.isEmpty }
    public var currentPointOfPath: CGPoint { path.currentPoint }
    public var boundingBoxOfPath: CGRect { path.boundingBoxOfPath }
    public var path: CGPath? { self.path.copy() }

    // MARK: Painting

    public func fillPath(using rule: CGPathFillRule = .winding) {
        guard let geometry = makeGeometry(path, rule: rule) else { path = CGMutablePath(); return }
        defer { _ = geometry.pointee.lpVtbl.pointee.Release(geometry) }
        let brush = configure(fillBrush, color: state.fill)
        target.pointee.lpVtbl.pointee.FillGeometry(target, geometry.withMemoryRebound(to: ID2D1Geometry.self, capacity: 1) { $0 }, brush, nil)
        path = CGMutablePath()
    }

    public func strokePath() {
        guard let geometry = makeGeometry(path, rule: .winding) else { path = CGMutablePath(); return }
        defer { _ = geometry.pointee.lpVtbl.pointee.Release(geometry) }
        let brush = configure(strokeBrush, color: state.stroke)
        let style = makeStrokeStyle()
        defer { if let s = style { _ = s.pointee.lpVtbl.pointee.Release(s) } }
        target.pointee.lpVtbl.pointee.DrawGeometry(target, geometry.withMemoryRebound(to: ID2D1Geometry.self, capacity: 1) { $0 }, brush, Float(state.lineWidth), style)
        path = CGMutablePath()
    }

    public func drawPath(using mode: CGPathDrawingMode) {
        let saved = path.copy() as? CGMutablePath ?? CGMutablePath()
        switch mode {
        case .fill: fillPath(using: .winding)
        case .eoFill: fillPath(using: .evenOdd)
        case .stroke: strokePath()
        case .fillStroke, .eoFillStroke:
            fillPath(using: mode == .eoFillStroke ? .evenOdd : .winding)
            path = saved
            strokePath()
        }
    }

    public func fill(_ rect: CGRect) {
        var r = d2dRect(rect.standardized)
        let brush = configure(fillBrush, color: state.fill)
        target.pointee.lpVtbl.pointee.FillRectangle(target, &r, brush)
    }
    public func fill(_ rects: [CGRect]) { for r in rects { fill(r) } }

    public func stroke(_ rect: CGRect) {
        var r = d2dRect(rect.standardized)
        let brush = configure(strokeBrush, color: state.stroke)
        let style = makeStrokeStyle()
        defer { if let s = style { _ = s.pointee.lpVtbl.pointee.Release(s) } }
        target.pointee.lpVtbl.pointee.DrawRectangle(target, &r, brush, Float(state.lineWidth), style)
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
        var r = d2dRect(rect.standardized)
        target.pointee.lpVtbl.pointee.PushAxisAlignedClip(target, &r, state.antialias ? D2D1_ANTIALIAS_MODE_PER_PRIMITIVE : D2D1_ANTIALIAS_MODE_ALIASED)
        state.clipPushes += 1
        state.clipBox = state.clipBox.intersection(rect.standardized)
        clipKinds.append(.axisAligned)
    }
    public func clip(to rects: [CGRect]) {
        guard let first = rects.first else { return }
        clip(to: rects.dropFirst().reduce(first) { $0.union($1) })
    }

    public func clip(using rule: CGPathFillRule = .winding) {
        guard let geometry = makeGeometry(path, rule: rule) else { path = CGMutablePath(); return }
        defer { _ = geometry.pointee.lpVtbl.pointee.Release(geometry) }
        var layer: UnsafeMutablePointer<ID2D1Layer>?
        guard target.pointee.lpVtbl.pointee.CreateLayer(target, nil, &layer) >= 0, let layer else { path = CGMutablePath(); return }
        var params = D2D1_LAYER_PARAMETERS()
        params.contentBounds = D2D1_RECT_F(left: -.infinity, top: -.infinity, right: .infinity, bottom: .infinity)
        params.geometricMask = geometry.withMemoryRebound(to: ID2D1Geometry.self, capacity: 1) { $0 }
        params.maskAntialiasMode = D2D1_ANTIALIAS_MODE_PER_PRIMITIVE
        params.maskTransform = d2dMatrix(.identity)
        params.opacity = 1
        params.opacityBrush = nil
        params.layerOptions = D2D1_LAYER_OPTIONS_NONE
        target.pointee.lpVtbl.pointee.PushLayer(target, &params, layer)
        _ = layer.pointee.lpVtbl.pointee.Release(layer)
        state.clipPushes += 1
        state.clipBox = state.clipBox.intersection(path.boundingBoxOfPath)
        clipKinds.append(.layer)
        path = CGMutablePath()
    }

    public var clipBoundingBox: CGRect { state.clipBox }

    private enum ClipKind { case axisAligned, layer }
    private var clipKinds: [ClipKind] = []

    private func popClips(_ n: Int) {
        for _ in 0..<n {
            guard let kind = clipKinds.popLast() else { break }
            switch kind {
            case .axisAligned: target.pointee.lpVtbl.pointee.PopAxisAlignedClip(target)
            case .layer: target.pointee.lpVtbl.pointee.PopLayer(target)
            }
        }
    }

    // MARK: Flush

    public func flush() { }
    public func synchronize() { }

    // MARK: Direct2D plumbing

    private func configure(_ brush: UnsafeMutablePointer<ID2D1SolidColorBrush>?, color: CGColor) -> UnsafeMutablePointer<ID2D1Brush>? {
        guard let brush else { return nil }
        let (r, g, b, a) = color.rgba
        var c = d2dColor(r, g, b, a * state.alpha)
        brush.pointee.lpVtbl.pointee.SetColor(brush, &c)
        return brush.withMemoryRebound(to: ID2D1Brush.self, capacity: 1) { $0 }
    }

    private func makeStrokeStyle() -> UnsafeMutablePointer<ID2D1StrokeStyle>? {
        var props = D2D1_STROKE_STYLE_PROPERTIES()
        switch state.lineCap {
        case .butt: props.startCap = D2D1_CAP_STYLE_FLAT; props.endCap = D2D1_CAP_STYLE_FLAT; props.dashCap = D2D1_CAP_STYLE_FLAT
        case .round: props.startCap = D2D1_CAP_STYLE_ROUND; props.endCap = D2D1_CAP_STYLE_ROUND; props.dashCap = D2D1_CAP_STYLE_ROUND
        case .square: props.startCap = D2D1_CAP_STYLE_SQUARE; props.endCap = D2D1_CAP_STYLE_SQUARE; props.dashCap = D2D1_CAP_STYLE_SQUARE
        }
        switch state.lineJoin {
        case .miter: props.lineJoin = D2D1_LINE_JOIN_MITER_OR_BEVEL
        case .round: props.lineJoin = D2D1_LINE_JOIN_ROUND
        case .bevel: props.lineJoin = D2D1_LINE_JOIN_BEVEL
        }
        props.miterLimit = Float(state.miterLimit)
        props.dashStyle = state.dashLengths.isEmpty ? D2D1_DASH_STYLE_SOLID : D2D1_DASH_STYLE_CUSTOM
        // Direct2D dash lengths are multiples of the stroke width.
        let w = max(state.lineWidth, 0.0001)
        props.dashOffset = Float(state.dashPhase / w)
        var style: UnsafeMutablePointer<ID2D1StrokeStyle>?
        if state.dashLengths.isEmpty {
            _ = factory.pointee.lpVtbl.pointee.CreateStrokeStyle(factory, &props, nil, 0, &style)
        } else {
            let dashes = state.dashLengths.map { Float($0 / w) }
            dashes.withUnsafeBufferPointer { buf in
                _ = factory.pointee.lpVtbl.pointee.CreateStrokeStyle(factory, &props, buf.baseAddress, UInt32(buf.count), &style)
            }
        }
        return style
    }

    private func makeGeometry(_ p: CGPath, rule: CGPathFillRule) -> UnsafeMutablePointer<ID2D1PathGeometry>? {
        guard !p.isEmpty else { return nil }
        var geometry: UnsafeMutablePointer<ID2D1PathGeometry>?
        guard factory.pointee.lpVtbl.pointee.CreatePathGeometry(factory, &geometry) >= 0, let geometry else { return nil }
        var sink: UnsafeMutablePointer<ID2D1GeometrySink>?
        guard geometry.pointee.lpVtbl.pointee.Open(geometry, &sink) >= 0, let sink else {
            _ = geometry.pointee.lpVtbl.pointee.Release(geometry)
            return nil
        }
        sink.pointee.lpVtbl.pointee.SetFillMode(sink, rule == .evenOdd ? D2D1_FILL_MODE_ALTERNATE : D2D1_FILL_MODE_WINDING)
        var figureOpen = false
        var figureStart = CGPoint.zero
        var last = CGPoint.zero
        func endFigure(closed: Bool) {
            if figureOpen {
                sink.pointee.lpVtbl.pointee.EndFigure(sink, closed ? D2D1_FIGURE_END_CLOSED : D2D1_FIGURE_END_OPEN)
                figureOpen = false
            }
        }
        func ensureFigure() {
            if !figureOpen {
                sink.pointee.lpVtbl.pointee.BeginFigure(sink, d2dPoint(last), D2D1_FIGURE_BEGIN_FILLED)
                figureOpen = true
                figureStart = last
            }
        }
        for e in p.elements {
            switch e {
            case let .move(pt):
                endFigure(closed: false)
                last = pt
                sink.pointee.lpVtbl.pointee.BeginFigure(sink, d2dPoint(pt), D2D1_FIGURE_BEGIN_FILLED)
                figureOpen = true
                figureStart = pt
            case let .line(pt):
                ensureFigure()
                sink.pointee.lpVtbl.pointee.AddLine(sink, d2dPoint(pt))
                last = pt
            case let .quad(c, pt):
                ensureFigure()
                var seg = D2D1_QUADRATIC_BEZIER_SEGMENT(point1: d2dPoint(c), point2: d2dPoint(pt))
                sink.pointee.lpVtbl.pointee.AddQuadraticBezier(sink, &seg)
                last = pt
            case let .curve(c1, c2, pt):
                ensureFigure()
                var seg = D2D1_BEZIER_SEGMENT(point1: d2dPoint(c1), point2: d2dPoint(c2), point3: d2dPoint(pt))
                sink.pointee.lpVtbl.pointee.AddBezier(sink, &seg)
                last = pt
            case .close:
                endFigure(closed: true)
                last = figureStart
            }
        }
        endFigure(closed: false)
        _ = sink.pointee.lpVtbl.pointee.Close(sink)
        _ = sink.pointee.lpVtbl.pointee.Release(sink)
        return geometry
    }
}
#endif
