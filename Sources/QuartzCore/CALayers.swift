// CALayer subclasses: shapes, gradients, text, transform/scroll/replicator containers,
// and the GPU-backed layer kinds that exist as types until the DirectX milestones.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct CAShapeLayerFillRule: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let nonZero = CAShapeLayerFillRule(rawValue: "non-zero")
    public static let evenOdd = CAShapeLayerFillRule(rawValue: "even-odd")
}

public struct CAShapeLayerLineCap: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let butt = CAShapeLayerLineCap(rawValue: "butt")
    public static let round = CAShapeLayerLineCap(rawValue: "round")
    public static let square = CAShapeLayerLineCap(rawValue: "square")
}

public struct CAShapeLayerLineJoin: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let miter = CAShapeLayerLineJoin(rawValue: "miter")
    public static let round = CAShapeLayerLineJoin(rawValue: "round")
    public static let bevel = CAShapeLayerLineJoin(rawValue: "bevel")
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cashapelayer
@MainActor
open class CAShapeLayer: CALayer {
    private var _path: CGPath?
    private var _fillColor: CGColor? = CGColor.black
    private var _strokeColor: CGColor?
    private var _lineWidth: CGFloat = 1
    private var _strokeStart: CGFloat = 0
    private var _strokeEnd: CGFloat = 1
    private var _miterLimit: CGFloat = 10
    private var _lineDashPhase: CGFloat = 0
    private var _lineDashPattern: [NSNumber]?

    open var fillRule: CAShapeLayerFillRule = .nonZero { didSet { _setNeedsRedraw() } }
    open var lineCap: CAShapeLayerLineCap = .butt { didSet { _setNeedsRedraw() } }
    open var lineJoin: CAShapeLayerLineJoin = .miter { didSet { _setNeedsRedraw() } }

    public required init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let l = layer as? CAShapeLayer else { return }
        _path = l._path; _fillColor = l._fillColor; _strokeColor = l._strokeColor; _lineWidth = l._lineWidth
        _strokeStart = l._strokeStart; _strokeEnd = l._strokeEnd; _miterLimit = l._miterLimit
        _lineDashPhase = l._lineDashPhase; _lineDashPattern = l._lineDashPattern
        fillRule = l.fillRule; lineCap = l.lineCap; lineJoin = l.lineJoin
    }

    open var path: CGPath? {
        get { _path }
        set { _path = newValue; _changed("path", old: nil) }
    }
    open var fillColor: CGColor? {
        get { _fillColor }
        set { let old = _fillColor; _fillColor = newValue; _changed("fillColor", old: old) }
    }
    open var strokeColor: CGColor? {
        get { _strokeColor }
        set { let old = _strokeColor; _strokeColor = newValue; _changed("strokeColor", old: old) }
    }
    open var lineWidth: CGFloat {
        get { _lineWidth }
        set { let old = _lineWidth; _lineWidth = newValue; _changed("lineWidth", old: old) }
    }
    open var strokeStart: CGFloat {
        get { _strokeStart }
        set { let old = _strokeStart; _strokeStart = newValue; _changed("strokeStart", old: old) }
    }
    open var strokeEnd: CGFloat {
        get { _strokeEnd }
        set { let old = _strokeEnd; _strokeEnd = newValue; _changed("strokeEnd", old: old) }
    }
    open var miterLimit: CGFloat {
        get { _miterLimit }
        set { let old = _miterLimit; _miterLimit = newValue; _changed("miterLimit", old: old) }
    }
    open var lineDashPhase: CGFloat {
        get { _lineDashPhase }
        set { let old = _lineDashPhase; _lineDashPhase = newValue; _changed("lineDashPhase", old: old) }
    }
    open var lineDashPattern: [NSNumber]? {
        get { _lineDashPattern }
        set { _lineDashPattern = newValue; _setNeedsRedraw() }
    }

    open override func defaultAction(forKey event: String) -> (any CAAction)? {
        if ["fillColor", "strokeColor", "lineWidth", "strokeStart", "strokeEnd", "miterLimit", "lineDashPhase"].contains(event) {
            let a = CABasicAnimation(keyPath: event)
            a.duration = CATransaction.animationDuration()
            a.timingFunction = CATransaction.animationTimingFunction()
            return a
        }
        return super.defaultAction(forKey: event)
    }

    public override func _value(forKeyPath kp: String) -> Any? {
        switch kp {
        case "path": return _path
        case "fillColor": return _fillColor
        case "strokeColor": return _strokeColor
        case "lineWidth": return _lineWidth
        case "strokeStart": return _strokeStart
        case "strokeEnd": return _strokeEnd
        case "miterLimit": return _miterLimit
        case "lineDashPhase": return _lineDashPhase
        default: return super._value(forKeyPath: kp)
        }
    }

    public override func _setValue(_ v: Any?, forKeyPath kp: String) {
        let n = CAInterpolation.number(v)
        switch kp {
        case "path": path = CAInterpolation.asPath(v)
        case "fillColor": fillColor = CAInterpolation.asColor(v)
        case "strokeColor": strokeColor = CAInterpolation.asColor(v)
        case "lineWidth": if let x = n { lineWidth = x }
        case "strokeStart": if let x = n { strokeStart = x }
        case "strokeEnd": if let x = n { strokeEnd = x }
        case "miterLimit": if let x = n { miterLimit = x }
        case "lineDashPhase": if let x = n { lineDashPhase = x }
        default: super._setValue(v, forKeyPath: kp)
        }
    }

    override func _drawContent(in ctx: CGContext, model: CALayer) {
        if let path = _path {
            if let fc = _fillColor {
                ctx.setFillColor(fc)
                ctx.addPath(path)
                ctx.fillPath(using: fillRule == .evenOdd ? .evenOdd : .winding)
            }
            if let sc = _strokeColor, _lineWidth > 0, _strokeEnd > _strokeStart {
                ctx.setStrokeColor(sc)
                ctx.setLineWidth(_lineWidth)
                ctx.setMiterLimit(_miterLimit)
                switch lineCap {
                case .round: ctx.setLineCap(.round)
                case .square: ctx.setLineCap(.square)
                default: ctx.setLineCap(.butt)
                }
                switch lineJoin {
                case .round: ctx.setLineJoin(.round)
                case .bevel: ctx.setLineJoin(.bevel)
                default: ctx.setLineJoin(.miter)
                }
                if let dash = _lineDashPattern, !dash.isEmpty {
                    ctx.setLineDash(phase: _lineDashPhase, lengths: dash.map { CGFloat($0.doubleValue) })
                }
                ctx.addPath(_strokeStart > 0 || _strokeEnd < 1 ? CAShapeLayer._trim(path, from: _strokeStart, to: _strokeEnd) : path)
                ctx.strokePath()
            }
        }
        super._drawContent(in: ctx, model: model)
    }

    /// Approximates a partial stroke by trimming the flattened path by arc length.
    static func _trim(_ path: CGPath, from start: CGFloat, to end: CGFloat) -> CGPath {
        let pts = CAInterpolation.points(along: path)
        guard pts.count > 1 else { return path }
        var lengths: [CGFloat] = [0]
        for i in 1..<pts.count { lengths.append(lengths[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        let total = lengths.last!
        let s = max(0, min(1, start)) * total, e = max(0, min(1, end)) * total
        let out = CGMutablePath()
        var started = false
        for i in 1..<pts.count {
            let a = lengths[i - 1], b = lengths[i]
            guard b > s, a < e, b > a else { continue }
            let t0 = max(0, (s - a) / (b - a)), t1 = min(1, (e - a) / (b - a))
            let p0 = CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t0, y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t0)
            let p1 = CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t1, y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t1)
            if !started { out.move(to: p0); started = true }
            out.addLine(to: p1)
        }
        return out
    }
}

public struct CAGradientLayerType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let axial = CAGradientLayerType(rawValue: "axial")
    public static let radial = CAGradientLayerType(rawValue: "radial")
    public static let conic = CAGradientLayerType(rawValue: "conic")
}

/// Rendered as banded fills (no shader): good enough for backgrounds until Direct2D
/// gradient brushes are exposed through CGContext.
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cagradientlayer
@MainActor
open class CAGradientLayer: CALayer {
    private var _colors: [Any]?
    private var _locations: [NSNumber]?
    private var _startPoint = CGPoint(x: 0.5, y: 0)
    private var _endPoint = CGPoint(x: 0.5, y: 1)
    open var type: CAGradientLayerType = .axial { didSet { _setNeedsRedraw() } }

    public required init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let l = layer as? CAGradientLayer else { return }
        _colors = l._colors; _locations = l._locations; _startPoint = l._startPoint; _endPoint = l._endPoint; type = l.type
    }

    open var colors: [Any]? {
        get { _colors }
        set { _colors = newValue; _changed("colors", old: nil) }
    }
    open var locations: [NSNumber]? {
        get { _locations }
        set { _locations = newValue; _changed("locations", old: nil) }
    }
    open var startPoint: CGPoint {
        get { _startPoint }
        set { let old = _startPoint; _startPoint = newValue; _changed("startPoint", old: old) }
    }
    open var endPoint: CGPoint {
        get { _endPoint }
        set { let old = _endPoint; _endPoint = newValue; _changed("endPoint", old: old) }
    }

    public override func _value(forKeyPath kp: String) -> Any? {
        switch kp {
        case "colors": return _colors
        case "locations": return _locations
        case "startPoint": return _startPoint
        case "endPoint": return _endPoint
        default: return super._value(forKeyPath: kp)
        }
    }

    public override func _setValue(_ v: Any?, forKeyPath kp: String) {
        switch kp {
        case "colors": colors = v as? [Any]
        case "locations": locations = v as? [NSNumber]
        case "startPoint": if let p = v as? CGPoint { startPoint = p }
        case "endPoint": if let p = v as? CGPoint { endPoint = p }
        default: super._setValue(v, forKeyPath: kp)
        }
    }

    override func _drawContent(in ctx: CGContext, model: CALayer) {
        let stops = (_colors ?? []).compactMap { CAInterpolation.asColor($0) }
        let b = bounds
        if stops.count >= 2 {
            let locs: [CGFloat] = _locations.map { $0.map { CGFloat($0.doubleValue) } } ?? (0..<stops.count).map { CGFloat($0) / CGFloat(stops.count - 1) }
            let bands = 64
            ctx.saveGState()
            _addBoundsPath(ctx, b)
            ctx.clip()
            func colorAt(_ t: CGFloat) -> CGColor {
                var i = 0
                while i + 1 < locs.count && locs[i + 1] < t { i += 1 }
                guard i + 1 < locs.count else { return stops.last! }
                let span = locs[i + 1] - locs[i]
                let f = span > 0 ? (t - locs[i]) / span : 1
                return CAInterpolation.lerp(stops[i], stops[i + 1], max(0, min(1, f))) as! CGColor
            }
            if type == .radial {
                let center = CGPoint(x: b.minX + _startPoint.x * b.width, y: b.minY + _startPoint.y * b.height)
                let edge = CGPoint(x: b.minX + _endPoint.x * b.width, y: b.minY + _endPoint.y * b.height)
                let radius = hypot(edge.x - center.x, edge.y - center.y)
                for i in stride(from: bands - 1, through: 0, by: -1) {
                    let t = CGFloat(i) / CGFloat(bands - 1)
                    ctx.setFillColor(colorAt(t))
                    let r = radius * (CGFloat(i + 1) / CGFloat(bands))
                    ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                }
            } else {
                // Axial: bands perpendicular to the start->end axis, in a rotated frame.
                let s = CGPoint(x: b.minX + _startPoint.x * b.width, y: b.minY + _startPoint.y * b.height)
                let e = CGPoint(x: b.minX + _endPoint.x * b.width, y: b.minY + _endPoint.y * b.height)
                let dx = e.x - s.x, dy = e.y - s.y
                let len = hypot(dx, dy)
                guard len > 0 else { ctx.restoreGState(); super._drawContent(in: ctx, model: model); return }
                ctx.translateBy(x: s.x, y: s.y)
                ctx.rotate(by: atan2(dy, dx))
                let extent = hypot(b.width, b.height) * 2
                ctx.setFillColor(stops[0])
                ctx.fill(CGRect(x: -extent, y: -extent, width: extent, height: extent * 2))
                for i in 0..<bands {
                    let t0 = CGFloat(i) / CGFloat(bands), t1 = CGFloat(i + 1) / CGFloat(bands)
                    ctx.setFillColor(colorAt((t0 + t1) / 2))
                    ctx.fill(CGRect(x: t0 * len - 0.5, y: -extent, width: (t1 - t0) * len + 1, height: extent * 2))
                }
                ctx.setFillColor(stops.last!)
                ctx.fill(CGRect(x: len, y: -extent, width: extent, height: extent * 2))
            }
            ctx.restoreGState()
        }
        super._drawContent(in: ctx, model: model)
    }
}

public struct CATextLayerTruncationMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let none = CATextLayerTruncationMode(rawValue: "none")
    public static let start = CATextLayerTruncationMode(rawValue: "start")
    public static let end = CATextLayerTruncationMode(rawValue: "end")
    public static let middle = CATextLayerTruncationMode(rawValue: "middle")
}

public struct CATextLayerAlignmentMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let natural = CATextLayerAlignmentMode(rawValue: "natural")
    public static let left = CATextLayerAlignmentMode(rawValue: "left")
    public static let right = CATextLayerAlignmentMode(rawValue: "right")
    public static let center = CATextLayerAlignmentMode(rawValue: "center")
    public static let justified = CATextLayerAlignmentMode(rawValue: "justified")
}

/// Text is drawn by the host's `CARuntime.textRenderer` (AppKit's string drawing).
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/catextlayer
@MainActor
open class CATextLayer: CALayer {
    /// A `String` or `NSAttributedString`.
    open var string: Any? { didSet { _setNeedsRedraw() } }
    /// A font name (`String`) or a host font object.
    open var font: Any? { didSet { _setNeedsRedraw() } }
    open var fontSize: CGFloat = 36 { didSet { _setNeedsRedraw() } }
    open var foregroundColor: CGColor? = CGColor.white { didSet { _setNeedsRedraw() } }
    open var isWrapped = false { didSet { _setNeedsRedraw() } }
    open var truncationMode: CATextLayerTruncationMode = .none { didSet { _setNeedsRedraw() } }
    open var alignmentMode: CATextLayerAlignmentMode = .natural { didSet { _setNeedsRedraw() } }
    open var allowsFontSubpixelQuantization = false

    public required init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let l = layer as? CATextLayer else { return }
        string = l.string; font = l.font; fontSize = l.fontSize; foregroundColor = l.foregroundColor
        isWrapped = l.isWrapped; truncationMode = l.truncationMode; alignmentMode = l.alignmentMode
    }

    override func _drawContent(in ctx: CGContext, model: CALayer) {
        CARuntime.textRenderer?(self, ctx, isGeometryFlipped)
        super._drawContent(in: ctx, model: model)
    }
}

/// Draws nothing itself; only its sublayers.
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/catransformlayer
@MainActor
open class CATransformLayer: CALayer {
    public required init() { super.init() }
    public required init(layer: Any) { super.init(layer: layer) }
    override func _drawContent(in ctx: CGContext, model: CALayer) {}
}

public struct CAScrollLayerScrollMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let none = CAScrollLayerScrollMode(rawValue: "none")
    public static let vertically = CAScrollLayerScrollMode(rawValue: "vertically")
    public static let horizontally = CAScrollLayerScrollMode(rawValue: "horizontally")
    public static let both = CAScrollLayerScrollMode(rawValue: "both")
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cascrolllayer
@MainActor
open class CAScrollLayer: CALayer {
    open var scrollMode: CAScrollLayerScrollMode = .both
    public required init() { super.init(); masksToBounds = true }
    public required init(layer: Any) { super.init(layer: layer); scrollMode = (layer as? CAScrollLayer)?.scrollMode ?? .both }

    open func scroll(to p: CGPoint) {
        var o = bounds.origin
        if scrollMode == .horizontally || scrollMode == .both { o.x = p.x }
        if scrollMode == .vertically || scrollMode == .both { o.y = p.y }
        bounds.origin = o
    }

    open func scroll(to r: CGRect) { scroll(to: r.origin) }
}

extension CALayer {
    /// Scrolls the nearest enclosing CAScrollLayer so `p` (in this layer's space) is at the origin.
    public func scroll(_ p: CGPoint) {
        var l: CALayer? = superlayer
        while let cur = l, !(cur is CAScrollLayer) { l = cur.superlayer }
        (l as? CAScrollLayer)?.scroll(to: convert(p, to: l))
    }

    public func scrollRectToVisible(_ r: CGRect) {
        var l: CALayer? = superlayer
        while let cur = l, !(cur is CAScrollLayer) { l = cur.superlayer }
        guard let s = l as? CAScrollLayer else { return }
        let target = convert(r, to: s)
        var o = s.bounds.origin
        if target.minX < s.bounds.minX { o.x = target.minX } else if target.maxX > s.bounds.maxX { o.x = target.maxX - s.bounds.width }
        if target.minY < s.bounds.minY { o.y = target.minY } else if target.maxY > s.bounds.maxY { o.y = target.maxY - s.bounds.height }
        s.scroll(to: o)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/careplicatorlayer
@MainActor
open class CAReplicatorLayer: CALayer {
    open var instanceCount = 1 { didSet { _setNeedsRedraw() } }
    open var preservesDepth = false
    open var instanceDelay: CFTimeInterval = 0
    open var instanceTransform = CATransform3DIdentity { didSet { _setNeedsRedraw() } }
    open var instanceColor: CGColor?
    open var instanceRedOffset: Float = 0
    open var instanceGreenOffset: Float = 0
    open var instanceBlueOffset: Float = 0
    open var instanceAlphaOffset: Float = 0

    public required init() { super.init() }
    public required init(layer: Any) {
        super.init(layer: layer)
        guard let l = layer as? CAReplicatorLayer else { return }
        instanceCount = l.instanceCount; instanceTransform = l.instanceTransform; instanceAlphaOffset = l.instanceAlphaOffset
    }

    public override func _compose(into ctx: CGContext, parentFlipped: Bool, alpha: CGFloat, time: CFTimeInterval, dirty: CGRect?) {
        guard instanceCount > 1 else { super._compose(into: ctx, parentFlipped: parentFlipped, alpha: alpha, time: time, dirty: dirty); return }
        // Each instance is the whole subtree, composed again through the accumulated transform.
        let saved = transform
        var acc = CATransform3DIdentity
        for i in 0..<instanceCount {
            let wasDisabled = CATransaction.disableActions()
            CATransaction.setDisableActions(true)
            transform = CATransform3DConcat(acc, saved)
            CATransaction.setDisableActions(wasDisabled)
            super._compose(into: ctx, parentFlipped: parentFlipped, alpha: max(0, alpha + CGFloat(instanceAlphaOffset) * CGFloat(i)), time: time, dirty: nil)
            acc = CATransform3DConcat(acc, instanceTransform)
        }
        let wasDisabled = CATransaction.disableActions()
        CATransaction.setDisableActions(true)
        transform = saved
        CATransaction.setDisableActions(wasDisabled)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/catiledlayer
@MainActor
open class CATiledLayer: CALayer {
    open class func fadeDuration() -> CFTimeInterval { 0.25 }
    open var levelsOfDetail = 1
    open var levelsOfDetailBias = 0
    open var tileSize = CGSize(width: 256, height: 256)
    public required init() { super.init() }
    public required init(layer: Any) { super.init(layer: layer) }
}

public struct CAEmitterLayerEmitterShape: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let point = CAEmitterLayerEmitterShape(rawValue: "point")
    public static let line = CAEmitterLayerEmitterShape(rawValue: "line")
    public static let rectangle = CAEmitterLayerEmitterShape(rawValue: "rectangle")
    public static let cuboid = CAEmitterLayerEmitterShape(rawValue: "cuboid")
    public static let circle = CAEmitterLayerEmitterShape(rawValue: "circle")
    public static let sphere = CAEmitterLayerEmitterShape(rawValue: "sphere")
}

public struct CAEmitterLayerEmitterMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let points = CAEmitterLayerEmitterMode(rawValue: "points")
    public static let outline = CAEmitterLayerEmitterMode(rawValue: "outline")
    public static let surface = CAEmitterLayerEmitterMode(rawValue: "surface")
    public static let volume = CAEmitterLayerEmitterMode(rawValue: "volume")
}

public struct CAEmitterLayerRenderMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let unordered = CAEmitterLayerRenderMode(rawValue: "unordered")
    public static let oldestFirst = CAEmitterLayerRenderMode(rawValue: "oldestFirst")
    public static let oldestLast = CAEmitterLayerRenderMode(rawValue: "oldestLast")
    public static let backToFront = CAEmitterLayerRenderMode(rawValue: "backToFront")
    public static let additive = CAEmitterLayerRenderMode(rawValue: "additive")
}

/// Particle emission is not simulated by the software compositor; the configuration is kept.
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caemittercell
@MainActor
open class CAEmitterCell: NSObject, CAMediaTiming {
    public var beginTime: CFTimeInterval = 0
    public var duration: CFTimeInterval = 0
    public var speed: Float = 1
    public var timeOffset: CFTimeInterval = 0
    public var repeatCount: Float = 0
    public var repeatDuration: CFTimeInterval = 0
    public var autoreverses = false
    public var fillMode: CAMediaTimingFillMode = .removed
    open var name: String?
    open var isEnabled = true
    open var birthRate: Float = 0
    open var lifetime: Float = 0
    open var lifetimeRange: Float = 0
    open var emissionLatitude: CGFloat = 0
    open var emissionLongitude: CGFloat = 0
    open var emissionRange: CGFloat = 0
    open var velocity: CGFloat = 0
    open var velocityRange: CGFloat = 0
    open var xAcceleration: CGFloat = 0
    open var yAcceleration: CGFloat = 0
    open var zAcceleration: CGFloat = 0
    open var spin: CGFloat = 0
    open var spinRange: CGFloat = 0
    open var scale: CGFloat = 1
    open var scaleRange: CGFloat = 0
    open var scaleSpeed: CGFloat = 0
    open var contents: Any?
    open var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var contentsScale: CGFloat = 1
    open var color: CGColor? = CGColor.white
    open var redRange: Float = 0
    open var greenRange: Float = 0
    open var blueRange: Float = 0
    open var alphaRange: Float = 0
    open var redSpeed: Float = 0
    open var greenSpeed: Float = 0
    open var blueSpeed: Float = 0
    open var alphaSpeed: Float = 0
    open var emitterCells: [CAEmitterCell]?
    open var style: [AnyHashable: Any]?
    public override init() { super.init() }
    public class func emitterCell() -> CAEmitterCell { CAEmitterCell() }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caemitterlayer
@MainActor
open class CAEmitterLayer: CALayer {
    open var emitterCells: [CAEmitterCell]?
    open var birthRate: Float = 1
    open var lifetime: Float = 1
    open var emitterPosition = CGPoint.zero
    open var emitterZPosition: CGFloat = 0
    open var emitterSize = CGSize.zero
    open var emitterDepth: CGFloat = 0
    open var emitterShape: CAEmitterLayerEmitterShape = .point
    open var emitterMode: CAEmitterLayerEmitterMode = .volume
    open var renderMode: CAEmitterLayerRenderMode = .unordered
    open var preservesDepth = false
    open var velocity: Float = 1
    open var scale: Float = 1
    open var spin: Float = 1
    open var seed: UInt32 = 0
    public required init() { super.init() }
    public required init(layer: Any) { super.init(layer: layer) }
}

/// Metal-backed presentation arrives with the Metal translation layer (M7).
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cametallayer
@MainActor
open class CAMetalLayer: CALayer {
    open var device: Any?
    open var preferredDevice: Any? { nil }
    open var pixelFormat: UInt = 0
    open var framebufferOnly = true
    open var drawableSize = CGSize.zero
    open var presentsWithTransaction = false
    open var colorspace: CGColorSpace?
    open var wantsExtendedDynamicRangeContentMetal = false
    open var maximumDrawableCount = 3
    open var allowsNextDrawableTimeout = true
    open var displaySyncEnabled = true
    public required init() { super.init() }
    public required init(layer: Any) { super.init(layer: layer) }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caopengllayer
@MainActor
open class CAOpenGLLayer: CALayer {
    open var isAsynchronous = false
    open var wantsExtendedDynamicRangeContentGL = false
    open var colorspace: CGColorSpace?
    public required init() { super.init() }
    public required init(layer: Any) { super.init(layer: layer) }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/carenderer
@MainActor
open class CARenderer: NSObject {
    open var layer: CALayer?
    open var bounds = CGRect.zero
    public override init() { super.init() }

    /// Renders `layer` into a context the host supplies; a convenience for offscreen output.
    open func render(in ctx: CGContext) {
        layer?.render(in: ctx)
    }
}

/// Keys for sublayer constraints: the solver is not implemented; layouts use frames.
public enum CAConstraintAttribute: Int, Sendable {
    case minX = 0, midX, maxX, width, minY, midY, maxY, height
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caconstraint
open class CAConstraint: NSObject {
    public let attribute: CAConstraintAttribute
    public let sourceName: String
    public let sourceAttribute: CAConstraintAttribute
    public let scale: CGFloat
    public let offset: CGFloat

    public init(attribute attr: CAConstraintAttribute, relativeTo srcId: String, attribute srcAttr: CAConstraintAttribute, scale: CGFloat, offset c: CGFloat) {
        attribute = attr; sourceName = srcId; sourceAttribute = srcAttr; self.scale = scale; offset = c
        super.init()
    }

    public convenience init(attribute attr: CAConstraintAttribute, relativeTo srcId: String, attribute srcAttr: CAConstraintAttribute, offset c: CGFloat) {
        self.init(attribute: attr, relativeTo: srcId, attribute: srcAttr, scale: 1, offset: c)
    }

    public convenience init(attribute attr: CAConstraintAttribute, relativeTo srcId: String, attribute srcAttr: CAConstraintAttribute) {
        self.init(attribute: attr, relativeTo: srcId, attribute: srcAttr, scale: 1, offset: 0)
    }
}

/// Resolves CAConstraints among a layer's sublayers (one pass, "superlayer" and named siblings).
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caconstraintlayoutmanager
@MainActor
open class CAConstraintLayoutManager: NSObject, CALayoutManager {
    public override init() { super.init() }
    public class func layoutManager() -> CAConstraintLayoutManager { CAConstraintLayoutManager() }

    public func layoutSublayers(of layer: CALayer) {
        guard let subs = layer.sublayers else { return }
        func value(_ l: CALayer, _ attr: CAConstraintAttribute, superlayer: Bool) -> CGFloat {
            let f = superlayer ? l.bounds : l.frame
            switch attr {
            case .minX: return f.minX
            case .midX: return f.midX
            case .maxX: return f.maxX
            case .width: return f.width
            case .minY: return f.minY
            case .midY: return f.midY
            case .maxY: return f.maxY
            case .height: return f.height
            }
        }
        for s in subs {
            guard let cs = s.constraints, !cs.isEmpty else { continue }
            var f = s.frame
            for c in cs {
                let src: CALayer? = c.sourceName == "superlayer" ? layer : subs.first { $0.name == c.sourceName }
                guard let src else { continue }
                let v = value(src, c.sourceAttribute, superlayer: src === layer) * c.scale + c.offset
                switch c.attribute {
                case .minX: f.origin.x = v
                case .midX: f.origin.x = v - f.width / 2
                case .maxX: f.origin.x = v - f.width
                case .width: f.size.width = v
                case .minY: f.origin.y = v
                case .midY: f.origin.y = v - f.height / 2
                case .maxY: f.origin.y = v - f.height
                case .height: f.size.height = v
                }
            }
            s.frame = f
        }
    }
}

private var constraintStore: [ObjectIdentifier: [CAConstraint]] = [:]

extension CALayer {
    /// Constraints resolved by a `CAConstraintLayoutManager` on the superlayer.
    public var constraints: [CAConstraint]? {
        get { constraintStore[ObjectIdentifier(self)] }
        set { constraintStore[ObjectIdentifier(self)] = newValue; superlayer?.setNeedsLayout() }
    }

    public func addConstraint(_ c: CAConstraint) {
        constraints = (constraints ?? []) + [c]
    }
}
