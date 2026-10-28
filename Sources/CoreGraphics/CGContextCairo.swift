// CGContext over Cairo (Linux). Mirrors the Direct2D context's public API; Cairo's own
// state stack carries the CTM, clip and line state, so saveGState/restoreGState map onto
// cairo_save/cairo_restore.

import Foundation
#if os(Linux)
import CCairo

public final class CGContext {
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
    }

    private var state = State()
    private var stack: [State] = []
    private var currentPath = CGMutablePath()

    /// The cairo drawing context (`cairo_t*`); text backends draw Pango layouts on it.
    public let cairo: OpaquePointer
    private let surface: OpaquePointer?        // owned image surface for bitmap contexts
    private let baseTransform: CGAffineTransform
    public private(set) var width: Int
    public private(set) var height: Int

    /// Wraps an existing cairo context (a window's backing surface).
    public init(cairo: OpaquePointer, baseTransform: CGAffineTransform, width: Int, height: Int) {
        self.cairo = cairo
        self.surface = nil
        self.baseTransform = baseTransform
        self.width = width
        self.height = height
        cairo_reference(cairo)
        applyTransform()
    }

    /// A bitmap context, bottom-left origin as CoreGraphics' (`data` is ignored; the
    /// pixels come back through `makeImage()`).
    public convenience init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int,
                             space: CGColorSpace, bitmapInfo: UInt32) {
        guard width > 0, height > 0, let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(width), Int32(height)),
              let cr = cairo_create(surface) else { return nil }
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height))
        self.init(cairo: cr, surface: surface, baseTransform: flip, width: width, height: height)
        cairo_destroy(cr)   // init retained it
    }

    private init(cairo: OpaquePointer, surface: OpaquePointer, baseTransform: CGAffineTransform, width: Int, height: Int) {
        self.cairo = cairo
        self.surface = surface
        self.baseTransform = baseTransform
        self.width = width
        self.height = height
        cairo_reference(cairo)
        applyTransform()
    }

    deinit {
        while !stack.isEmpty { restoreGState() }
        for (_, (_, s)) in imageCache { cairo_surface_destroy(s) }
        cairo_destroy(cairo)
        if let s = surface { cairo_surface_destroy(s) }
    }

    /// The pixels of a bitmap context (premultiplied BGRA, top row first).
    public func makeImage() -> CGImage? {
        guard let s = surface else { return nil }
        cairo_surface_flush(s)
        guard let base = cairo_image_surface_get_data(s) else { return nil }
        let stride = Int(cairo_image_surface_get_stride(s))
        let data = Data(bytes: base, count: stride * height)
        return CGImage.fromBGRA(width: width, height: height, stride: stride, data: data)
    }

    // MARK: State

    public func saveGState() {
        stack.append(state)
        cairo_save(cairo)
    }

    public func restoreGState() {
        guard let saved = stack.popLast() else { return }
        cairo_restore(cairo)
        state = saved
    }

    public var ctm: CGAffineTransform { state.ctm }
    public func translateBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(translationX: x, y: y).concatenating(state.ctm); applyTransform() }
    public func scaleBy(x: CGFloat, y: CGFloat) { state.ctm = CGAffineTransform(scaleX: x, y: y).concatenating(state.ctm); applyTransform() }
    public func rotate(by angle: CGFloat) { state.ctm = CGAffineTransform(rotationAngle: angle).concatenating(state.ctm); applyTransform() }
    public func concatenate(_ t: CGAffineTransform) { state.ctm = t.concatenating(state.ctm); applyTransform() }

    private func applyTransform() {
        let t = state.ctm.concatenating(baseTransform)
        var m = cairo_matrix_t(xx: Double(t.a), yx: Double(t.b), xy: Double(t.c), yy: Double(t.d), x0: Double(t.tx), y0: Double(t.ty))
        cairo_set_matrix(cairo, &m)
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
    public func setBlendMode(_ mode: CGBlendMode) {
        state.blend = mode
        switch mode {
        case .normal: cairo_set_operator(cairo, CAIRO_OPERATOR_OVER)
        case .multiply: cairo_set_operator(cairo, CAIRO_OPERATOR_MULTIPLY)
        case .screen: cairo_set_operator(cairo, CAIRO_OPERATOR_SCREEN)
        case .copy: cairo_set_operator(cairo, CAIRO_OPERATOR_SOURCE)
        case .clear: cairo_set_operator(cairo, CAIRO_OPERATOR_CLEAR)
        case .sourceIn: cairo_set_operator(cairo, CAIRO_OPERATOR_IN)
        case .sourceOut: cairo_set_operator(cairo, CAIRO_OPERATOR_OUT)
        case .sourceAtop: cairo_set_operator(cairo, CAIRO_OPERATOR_ATOP)
        case .destinationOver: cairo_set_operator(cairo, CAIRO_OPERATOR_DEST_OVER)
        case .destinationIn: cairo_set_operator(cairo, CAIRO_OPERATOR_DEST_IN)
        case .destinationOut: cairo_set_operator(cairo, CAIRO_OPERATOR_DEST_OUT)
        case .destinationAtop: cairo_set_operator(cairo, CAIRO_OPERATOR_DEST_ATOP)
        case .xor: cairo_set_operator(cairo, CAIRO_OPERATOR_XOR)
        case .plusLighter: cairo_set_operator(cairo, CAIRO_OPERATOR_ADD)
        case .overlay: cairo_set_operator(cairo, CAIRO_OPERATOR_OVERLAY)
        case .darken: cairo_set_operator(cairo, CAIRO_OPERATOR_DARKEN)
        case .lighten: cairo_set_operator(cairo, CAIRO_OPERATOR_LIGHTEN)
        case .colorDodge: cairo_set_operator(cairo, CAIRO_OPERATOR_COLOR_DODGE)
        case .colorBurn: cairo_set_operator(cairo, CAIRO_OPERATOR_COLOR_BURN)
        case .softLight: cairo_set_operator(cairo, CAIRO_OPERATOR_SOFT_LIGHT)
        case .hardLight: cairo_set_operator(cairo, CAIRO_OPERATOR_HARD_LIGHT)
        case .difference: cairo_set_operator(cairo, CAIRO_OPERATOR_DIFFERENCE)
        case .exclusion: cairo_set_operator(cairo, CAIRO_OPERATOR_EXCLUSION)
        default: cairo_set_operator(cairo, CAIRO_OPERATOR_OVER)
        }
    }
    public func setPatternPhase(_ phase: CGSize) { }
    public var interpolationQuality: CGInterpolationQuality {
        get { state.interpolation }
        set { state.interpolation = newValue }
    }
    public func setShouldAntialias(_ on: Bool) {
        state.antialias = on
        cairo_set_antialias(cairo, on ? CAIRO_ANTIALIAS_DEFAULT : CAIRO_ANTIALIAS_NONE)
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

    /// Replays the current CGPath into cairo's path.
    private func loadPath(_ path: CGPath) {
        cairo_new_path(cairo)
        var current = CGPoint.zero
        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]
                cairo_move_to(cairo, Double(current.x), Double(current.y))
            case .addLineToPoint:
                current = e.points[0]
                cairo_line_to(cairo, Double(current.x), Double(current.y))
            case .addQuadCurveToPoint:
                let c = e.points[0], p = e.points[1]
                let c1 = CGPoint(x: current.x + 2 / 3 * (c.x - current.x), y: current.y + 2 / 3 * (c.y - current.y))
                let c2 = CGPoint(x: p.x + 2 / 3 * (c.x - p.x), y: p.y + 2 / 3 * (c.y - p.y))
                cairo_curve_to(cairo, Double(c1.x), Double(c1.y), Double(c2.x), Double(c2.y), Double(p.x), Double(p.y))
                current = p
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], p = e.points[2]
                cairo_curve_to(cairo, Double(c1.x), Double(c1.y), Double(c2.x), Double(c2.y), Double(p.x), Double(p.y))
                current = p
            case .closeSubpath:
                cairo_close_path(cairo)
            @unknown default: break
            }
        }
    }

    private func setSource(_ color: CGColor) {
        let (r, g, b, a) = color.rgba
        cairo_set_source_rgba(cairo, Double(r), Double(g), Double(b), Double(a * state.alpha))
    }

    private func applyLineState() {
        cairo_set_line_width(cairo, Double(state.lineWidth))
        switch state.lineCap {
        case .round: cairo_set_line_cap(cairo, CAIRO_LINE_CAP_ROUND)
        case .square: cairo_set_line_cap(cairo, CAIRO_LINE_CAP_SQUARE)
        default: cairo_set_line_cap(cairo, CAIRO_LINE_CAP_BUTT)
        }
        switch state.lineJoin {
        case .round: cairo_set_line_join(cairo, CAIRO_LINE_JOIN_ROUND)
        case .bevel: cairo_set_line_join(cairo, CAIRO_LINE_JOIN_BEVEL)
        default: cairo_set_line_join(cairo, CAIRO_LINE_JOIN_MITER)
        }
        cairo_set_miter_limit(cairo, Double(state.miterLimit))
        if state.dashLengths.isEmpty {
            cairo_set_dash(cairo, nil, 0, 0)
        } else {
            let dashes = state.dashLengths.map { Double($0) }
            dashes.withUnsafeBufferPointer { cairo_set_dash(cairo, $0.baseAddress, Int32($0.count), Double(state.dashPhase)) }
        }
    }

    // MARK: Painting

    public func fillPath(using rule: CGPathFillRule = .winding) {
        defer { currentPath = CGMutablePath() }
        guard !currentPath.isEmpty else { return }
        loadPath(currentPath)
        cairo_set_fill_rule(cairo, rule == .evenOdd ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
        setSource(state.fill)
        cairo_fill(cairo)
    }

    public func strokePath() {
        defer { currentPath = CGMutablePath() }
        guard !currentPath.isEmpty else { return }
        loadPath(currentPath)
        applyLineState()
        setSource(state.stroke)
        cairo_stroke(cairo)
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
        cairo_new_path(cairo)
        cairo_rectangle(cairo, Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        setSource(state.fill)
        cairo_fill(cairo)
    }
    public func fill(_ rects: [CGRect]) { for r in rects { fill(r) } }

    public func stroke(_ rect: CGRect) {
        let r = rect.standardized
        cairo_new_path(cairo)
        cairo_rectangle(cairo, Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        applyLineState()
        setSource(state.stroke)
        cairo_stroke(cairo)
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
        let r = rect.standardized
        cairo_save(cairo)
        cairo_set_operator(cairo, CAIRO_OPERATOR_CLEAR)
        cairo_new_path(cairo)
        cairo_rectangle(cairo, Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        cairo_fill(cairo)
        cairo_restore(cairo)
    }

    // MARK: Clipping

    public func clip(to rect: CGRect) {
        let r = rect.standardized
        cairo_new_path(cairo)
        cairo_rectangle(cairo, Double(r.minX), Double(r.minY), Double(r.width), Double(r.height))
        cairo_clip(cairo)
    }
    public func clip(to rects: [CGRect]) {
        guard let first = rects.first else { return }
        clip(to: rects.dropFirst().reduce(first) { $0.union($1) })
    }

    public func clip(using rule: CGPathFillRule = .winding) {
        defer { currentPath = CGMutablePath() }
        loadPath(currentPath)
        cairo_set_fill_rule(cairo, rule == .evenOdd ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING)
        cairo_clip(cairo)
    }

    public var clipBoundingBox: CGRect {
        var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
        cairo_clip_extents(cairo, &x1, &y1, &x2, &y2)
        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    // MARK: Images

    private var imageCache: [ObjectIdentifier: (CGImage, OpaquePointer)] = [:]

    private func surface(for image: CGImage) -> OpaquePointer? {
        let key = ObjectIdentifier(image)
        if let (cached, s) = imageCache[key], cached === image { return s }
        // Copy into cairo-owned memory with cairo's stride so the surface outlives the Data.
        guard let s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(image.width), Int32(image.height)),
              let dst = cairo_image_surface_get_data(s) else { return nil }
        let dstStride = Int(cairo_image_surface_get_stride(s))
        image.data.withUnsafeBytes { src in
            guard let base = src.baseAddress else { return }
            let rowBytes = min(image.bytesPerRow, dstStride)
            for row in 0..<image.height {
                memcpy(dst + row * dstStride, base + row * image.bytesPerRow, rowBytes)
            }
        }
        cairo_surface_mark_dirty(s)
        imageCache[key] = (image, s)
        return s
    }

    /// Draws `image` scaled into `rect`, first pixel row at the rect's maximum y, as CoreGraphics does.
    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool = false) {
        guard let s = surface(for: image) else { return }
        let r = rect.standardized
        cairo_save(cairo)
        cairo_translate(cairo, Double(r.minX), Double(r.maxY))
        cairo_scale(cairo, Double(r.width / CGFloat(image.width)), -Double(r.height / CGFloat(image.height)))
        cairo_set_source_surface(cairo, s, 0, 0)
        if let pattern = cairo_get_source(cairo) {
            cairo_pattern_set_filter(pattern, state.interpolation == .none ? CAIRO_FILTER_NEAREST : CAIRO_FILTER_GOOD)
        }
        cairo_new_path(cairo)
        cairo_rectangle(cairo, 0, 0, Double(image.width), Double(image.height))
        cairo_clip(cairo)
        cairo_paint_with_alpha(cairo, Double(state.alpha))
        cairo_restore(cairo)
    }

    public func releaseImageCache() {
        for (_, (_, s)) in imageCache { cairo_surface_destroy(s) }
        imageCache.removeAll()
    }

    // MARK: Text (Pango layouts created by the AppKit text backend)

    /// Draws a PangoLayout with its top-left corner at `topLeft` in user space. Pango lays
    /// text out y-down; in a y-up user space the local axis is flipped so glyphs are upright.
    public func drawPangoLayout(_ layout: OpaquePointer, topLeft: CGPoint, flipped: Bool, color: CGColor) {
        cairo_save(cairo)
        cairo_translate(cairo, Double(topLeft.x), Double(topLeft.y))
        if !flipped { cairo_scale(cairo, 1, -1) }
        setSource(color)
        pango_cairo_update_layout(cairo, layout)
        pango_cairo_show_layout(cairo, layout)
        cairo_restore(cairo)
    }

    // MARK: Flush

    public func flush() { if let s = surface { cairo_surface_flush(s) } else { cairo_surface_flush(cairo_get_target(cairo)) } }
    public func synchronize() { flush() }
}
#endif
