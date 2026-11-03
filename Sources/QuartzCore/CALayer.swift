// CALayer: the layer tree, presentation values, implicit actions and a software
// compositor that renders a tree into a CGContext. DirectComposition acceleration can
// replace the compositor later without changing this API.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/calayerdelegate
@MainActor
public protocol CALayerDelegate: AnyObject {
    func display(_ layer: CALayer)
    func draw(_ layer: CALayer, in ctx: CGContext)
    func layerWillDraw(_ layer: CALayer)
    func layoutSublayers(of layer: CALayer)
    /// Return `NSNull()` to suppress the implicit animation, nil to fall through.
    func action(for layer: CALayer, forKey event: String) -> (any CAAction)?
}

extension CALayerDelegate {
    public func display(_ layer: CALayer) { layer._displayDefault() }
    public func draw(_ layer: CALayer, in ctx: CGContext) {}
    public func layerWillDraw(_ layer: CALayer) {}
    public func layoutSublayers(of layer: CALayer) {}
    public func action(for layer: CALayer, forKey event: String) -> (any CAAction)? { nil }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/calayoutmanager
@MainActor
public protocol CALayoutManager: AnyObject {
    func preferredSize(of layer: CALayer) -> CGSize
    func invalidateLayout(of layer: CALayer)
    func layoutSublayers(of layer: CALayer)
}

extension CALayoutManager {
    public func preferredSize(of layer: CALayer) -> CGSize { layer.bounds.size }
    public func invalidateLayout(of layer: CALayer) {}
    public func layoutSublayers(of layer: CALayer) {}
}

/// A root layer's owner: told when the tree needs redrawing. AppKit's layer-backed
/// views implement it; tests can observe invalidations through it.
@MainActor
public protocol CALayerHost: AnyObject {
    /// `rect` is in the root layer's superlayer space (the host's coordinate space), or nil for everything.
    func layerNeedsDisplay(_ root: CALayer, in rect: CGRect?)
    /// Whether the tree is on screen. Animations in a tree whose host is off screen (a
    /// closed or hidden window) stop driving frames until `CARuntime.resumeAnimations(of:)`.
    func layerHostIsOnScreen(_ root: CALayer) -> Bool
}

extension CALayerHost {
    public func layerHostIsOnScreen(_ root: CALayer) -> Bool { true }
}

public struct CAAutoresizingMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let layerNotSizable = CAAutoresizingMask([])
    public static let layerMinXMargin = CAAutoresizingMask(rawValue: 1 << 0)
    public static let layerWidthSizable = CAAutoresizingMask(rawValue: 1 << 1)
    public static let layerMaxXMargin = CAAutoresizingMask(rawValue: 1 << 2)
    public static let layerMinYMargin = CAAutoresizingMask(rawValue: 1 << 3)
    public static let layerHeightSizable = CAAutoresizingMask(rawValue: 1 << 4)
    public static let layerMaxYMargin = CAAutoresizingMask(rawValue: 1 << 5)
}

public struct CAEdgeAntialiasingMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let layerLeftEdge = CAEdgeAntialiasingMask(rawValue: 1 << 0)
    public static let layerRightEdge = CAEdgeAntialiasingMask(rawValue: 1 << 1)
    public static let layerBottomEdge = CAEdgeAntialiasingMask(rawValue: 1 << 2)
    public static let layerTopEdge = CAEdgeAntialiasingMask(rawValue: 1 << 3)
}

public struct CACornerMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let layerMinXMinYCorner = CACornerMask(rawValue: 1 << 0)
    public static let layerMaxXMinYCorner = CACornerMask(rawValue: 1 << 1)
    public static let layerMinXMaxYCorner = CACornerMask(rawValue: 1 << 2)
    public static let layerMaxXMaxYCorner = CACornerMask(rawValue: 1 << 3)
    static let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
}

public struct CALayerContentsGravity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let center = CALayerContentsGravity(rawValue: "center")
    public static let top = CALayerContentsGravity(rawValue: "top")
    public static let bottom = CALayerContentsGravity(rawValue: "bottom")
    public static let left = CALayerContentsGravity(rawValue: "left")
    public static let right = CALayerContentsGravity(rawValue: "right")
    public static let topLeft = CALayerContentsGravity(rawValue: "topLeft")
    public static let topRight = CALayerContentsGravity(rawValue: "topRight")
    public static let bottomLeft = CALayerContentsGravity(rawValue: "bottomLeft")
    public static let bottomRight = CALayerContentsGravity(rawValue: "bottomRight")
    public static let resize = CALayerContentsGravity(rawValue: "resize")
    public static let resizeAspect = CALayerContentsGravity(rawValue: "resizeAspect")
    public static let resizeAspectFill = CALayerContentsGravity(rawValue: "resizeAspectFill")
}

public struct CALayerContentsFormat: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let RGBA8Uint = CALayerContentsFormat(rawValue: "RGBA8")
    public static let RGBA16Float = CALayerContentsFormat(rawValue: "RGBAh")
    public static let gray8Uint = CALayerContentsFormat(rawValue: "Gray8")
}

public struct CALayerContentsFilter: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let nearest = CALayerContentsFilter(rawValue: "nearest")
    public static let linear = CALayerContentsFilter(rawValue: "linear")
    public static let trilinear = CALayerContentsFilter(rawValue: "trilinear")
}

public struct CALayerCornerCurve: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let circular = CALayerCornerCurve(rawValue: "circular")
    public static let continuous = CALayerCornerCurve(rawValue: "continuous")
}

public let kCAOnOrderIn = "onOrderIn"
public let kCAOnOrderOut = "onOrderOut"
public let kCATransition = "transition"

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/calayer
@MainActor
open class CALayer: NSObject, CAMediaTiming {

    // MARK: Geometry

    var _bounds = CGRect.zero
    var _position = CGPoint.zero
    var _zPosition: CGFloat = 0
    var _anchorPoint = CGPoint(x: 0.5, y: 0.5)
    var _anchorPointZ: CGFloat = 0
    var _transform = CATransform3DIdentity
    var _sublayerTransform = CATransform3DIdentity
    var _isHidden = false
    var _isDoubleSided = true
    var _isGeometryFlipped = false
    var _masksToBounds = false
    var _opacity: Float = 1
    var _backgroundColor: CGColor?
    var _cornerRadius: CGFloat = 0
    var _borderWidth: CGFloat = 0
    var _borderColor: CGColor? = CGColor.black
    var _contents: Any?
    var _contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var _contentsCenter = CGRect(x: 0, y: 0, width: 1, height: 1)
    var _contentsScale: CGFloat = 1
    var _shadowColor: CGColor? = CGColor.black
    var _shadowOpacity: Float = 0
    var _shadowOffset = CGSize(width: 0, height: -3)
    var _shadowRadius: CGFloat = 3
    var _shadowPath: CGPath?
    var _mask: CALayer?

    public var beginTime: CFTimeInterval = 0
    public var duration: CFTimeInterval = 0
    public var speed: Float = 1
    public var timeOffset: CFTimeInterval = 0
    public var repeatCount: Float = 0
    public var repeatDuration: CFTimeInterval = 0
    public var autoreverses = false
    public var fillMode: CAMediaTimingFillMode = .removed

    open var contentsGravity: CALayerContentsGravity = .resize { didSet { _rasterVersion += 1; _setNeedsRedraw() } }
    open var contentsFormat: CALayerContentsFormat = .RGBA8Uint
    open var minificationFilter: CALayerContentsFilter = .linear
    open var magnificationFilter: CALayerContentsFilter = .linear
    open var minificationFilterBias: Float = 0
    open var isOpaque = false
    open var needsDisplayOnBoundsChange = false
    open var drawsAsynchronously = false
    open var edgeAntialiasingMask: CAEdgeAntialiasingMask = []
    open var allowsEdgeAntialiasing = false
    open var allowsGroupOpacity = true
    open var maskedCorners: CACornerMask = .all { didSet { _rasterVersion += 1; _borderVersion += 1; _setNeedsRedraw() } }
    open var cornerCurve: CALayerCornerCurve = .circular
    open var shouldRasterize = false
    open var rasterizationScale: CGFloat = 1
    open var name: String?
    open var style: [AnyHashable: Any]?
    open var actions: [String: any CAAction]?
    open var autoresizingMask: CAAutoresizingMask = []
    open var layoutManager: (any CALayoutManager)?
    open weak var delegate: (any CALayerDelegate)?
    open var filters: [Any]?
    open var compositingFilter: Any?
    open var backgroundFilters: [Any]?
    open var wantsExtendedDynamicRangeContent = false

    /// The owner of a root layer's tree (AppKit's layer-backed view).
    public weak var host: (any CALayerHost)?

    // MARK: Hierarchy

    public private(set) weak var superlayer: CALayer?
    var _sublayers: [CALayer] = []
    open var sublayers: [CALayer]? {
        get { _sublayers.isEmpty ? nil : _sublayers }
        set {
            for s in _sublayers { s.superlayer = nil }
            _sublayers = []
            for s in newValue ?? [] { addSublayer(s) }
        }
    }

    // MARK: Display state

    var _needsDisplay = true
    var _needsLayout = true
    private var userValues: [String: Any] = [:]
    var animations: [(key: String, animation: CAAnimation)] = []
    private var animationCounter = 0
    /// Old values captured while a property changes, so implicit animations can start
    /// from where the layer was.
    private var pendingOldValues: [String: Any] = [:]
    /// True once rendered at least once: implicit animations only apply after that.
    var hasPresentation = false
    /// Presentation copies carry this so their setters never trigger actions.
    var isPresentationCopy = false
    /// Bumped whenever this layer's own rasterised content changes (not its placement).
    /// Native layer hosts re-rasterise a layer only when this moves.
    public private(set) var _rasterVersion = 0
    /// Bumped when the border's appearance changes (it is composited as its own node).
    public private(set) var _borderVersion = 0
    static let borderKeys: Set<String> = ["borderWidth", "borderColor", "cornerRadius", "bounds"]
    /// Bumped whenever anything in this layer's subtree changes (placement included).
    public private(set) var _treeVersion = 0
    /// Properties that only affect compositing: a change leaves the rasterised content valid.
    static let compositingOnlyKeys: Set<String> = ["position", "transform", "opacity", "hidden", "anchorPoint", "anchorPointZ", "zPosition", "sublayerTransform"]

    public required override init() {
        super.init()
    }

    /// Copies `layer`'s model values (used for presentation layers).
    public required init(layer: Any) {
        super.init()
        guard let l = layer as? CALayer else { return }
        _bounds = l._bounds; _position = l._position; _zPosition = l._zPosition
        _anchorPoint = l._anchorPoint; _anchorPointZ = l._anchorPointZ
        _transform = l._transform; _sublayerTransform = l._sublayerTransform
        _isHidden = l._isHidden; _isDoubleSided = l._isDoubleSided; _isGeometryFlipped = l._isGeometryFlipped
        _masksToBounds = l._masksToBounds; _opacity = l._opacity; _backgroundColor = l._backgroundColor
        _cornerRadius = l._cornerRadius; _borderWidth = l._borderWidth; _borderColor = l._borderColor
        _contents = l._contents; _contentsRect = l._contentsRect; _contentsCenter = l._contentsCenter
        _contentsScale = l._contentsScale
        _shadowColor = l._shadowColor; _shadowOpacity = l._shadowOpacity; _shadowOffset = l._shadowOffset
        _shadowRadius = l._shadowRadius; _shadowPath = l._shadowPath; _mask = l._mask
        contentsGravity = l.contentsGravity; isOpaque = l.isOpaque; maskedCorners = l.maskedCorners
        name = l.name; delegate = l.delegate; userValues = l.userValues
        beginTime = l.beginTime; duration = l.duration; speed = l.speed; timeOffset = l.timeOffset
        isPresentationCopy = true
    }

    // MARK: Property change plumbing

    /// Records a change to an animatable property: redraws and runs the implicit action.
    func _changed(_ key: String, old: Any?) {
        guard !isPresentationCopy else { return }
        if !CALayer.compositingOnlyKeys.contains(key) { _rasterVersion += 1 }
        if CALayer.borderKeys.contains(key) { _borderVersion += 1 }
        _setNeedsRedraw()
        guard hasPresentation, !CATransaction.disableActions() else { return }
        if let old { pendingOldValues[key] = old }
        defer { pendingOldValues[key] = nil }
        if let action = action(forKey: key) {
            action.run(forKey: key, object: self, arguments: nil)
        }
    }

    /// Marks the hosting tree dirty.
    func _setNeedsRedraw() {
        guard !isPresentationCopy else { return }
        var l: CALayer? = self
        while let layer = l { layer._treeVersion += 1; l = layer.superlayer }
        _invalidateHost(nil)
    }

    /// Finds the root and tells its host to redraw. `rect` is in this layer's superlayer space.
    func _invalidateHost(_ rect: CGRect?) {
        var l = self
        while let s = l.superlayer { l = s }
        l.host?.layerNeedsDisplay(l, in: l === self ? rect : nil)
    }

    var root: CALayer {
        var l = self
        while let s = l.superlayer { l = s }
        return l
    }

    // MARK: Geometry accessors

    open var bounds: CGRect {
        get { _bounds }
        set {
            guard newValue != _bounds else { return }
            let old = _bounds
            _bounds = newValue
            if old.size != newValue.size {
                _resizeSublayers(oldSize: old.size)
                if needsDisplayOnBoundsChange { setNeedsDisplay() }
                _needsLayout = true
            }
            _changed("bounds", old: old)
        }
    }

    open var position: CGPoint {
        get { _position }
        set { guard newValue != _position else { return }; let old = _position; _position = newValue; _changed("position", old: old) }
    }

    open var zPosition: CGFloat {
        get { _zPosition }
        set { guard newValue != _zPosition else { return }; let old = _zPosition; _zPosition = newValue; _changed("zPosition", old: old) }
    }

    open var anchorPoint: CGPoint {
        get { _anchorPoint }
        set { guard newValue != _anchorPoint else { return }; let old = _anchorPoint; _anchorPoint = newValue; _changed("anchorPoint", old: old) }
    }

    open var anchorPointZ: CGFloat {
        get { _anchorPointZ }
        set { let old = _anchorPointZ; _anchorPointZ = newValue; _changed("anchorPointZ", old: old) }
    }

    open var transform: CATransform3D {
        get { _transform }
        set { guard newValue != _transform else { return }; let old = _transform; _transform = newValue; _changed("transform", old: old) }
    }

    open var sublayerTransform: CATransform3D {
        get { _sublayerTransform }
        set { guard newValue != _sublayerTransform else { return }; let old = _sublayerTransform; _sublayerTransform = newValue; _changed("sublayerTransform", old: old) }
    }

    open func affineTransform() -> CGAffineTransform { _transform.affineTransform }
    open func setAffineTransform(_ m: CGAffineTransform) { transform = CATransform3DMakeAffineTransform(m) }

    /// The frame in the superlayer's space: the bounds placed by position/anchor and transformed.
    open var frame: CGRect {
        get {
            let w = _bounds.width, h = _bounds.height
            let ax = _anchorPoint.x * w, ay = _anchorPoint.y * h
            if _transform.isIdentity {
                return CGRect(x: _position.x - ax, y: _position.y - ay, width: w, height: h)
            }
            let corners = [CGPoint(x: -ax, y: -ay), CGPoint(x: w - ax, y: -ay), CGPoint(x: -ax, y: h - ay), CGPoint(x: w - ax, y: h - ay)]
                .map { $0.applying(_transform) }
                .map { CGPoint(x: $0.x + _position.x, y: $0.y + _position.y) }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        set {
            // As in Core Animation: sets bounds.size and position for the current anchor point.
            CATransaction.begin()
            let wasDisabled = CATransaction.disableActions()
            let animate = !wasDisabled && hasPresentation
            CATransaction.setDisableActions(true)
            let oldBounds = _bounds, oldPosition = _position
            _bounds.size = newValue.size
            _position = CGPoint(x: newValue.minX + _anchorPoint.x * newValue.width, y: newValue.minY + _anchorPoint.y * newValue.height)
            if oldBounds.size != _bounds.size {
                _resizeSublayers(oldSize: oldBounds.size)
                if needsDisplayOnBoundsChange { setNeedsDisplay() }
                _needsLayout = true
            }
            CATransaction.setDisableActions(wasDisabled)
            CATransaction.commit()
            if animate {
                _changed("bounds", old: oldBounds)
                _changed("position", old: oldPosition)
            } else {
                _setNeedsRedraw()
            }
        }
    }

    open var isHidden: Bool {
        get { _isHidden }
        set { guard newValue != _isHidden else { return }; let old = _isHidden; _isHidden = newValue; _changed("hidden", old: old) }
    }

    open var isDoubleSided: Bool {
        get { _isDoubleSided }
        set { _isDoubleSided = newValue }
    }

    open var isGeometryFlipped: Bool {
        get { _isGeometryFlipped }
        set { guard newValue != _isGeometryFlipped else { return }; _isGeometryFlipped = newValue; _setNeedsRedraw() }
    }

    open var masksToBounds: Bool {
        get { _masksToBounds }
        set { guard newValue != _masksToBounds else { return }; _masksToBounds = newValue; _setNeedsRedraw() }
    }

    open var opacity: Float {
        get { _opacity }
        set { guard newValue != _opacity else { return }; let old = _opacity; _opacity = newValue; _changed("opacity", old: old) }
    }

    open var backgroundColor: CGColor? {
        get { _backgroundColor }
        set { let old = _backgroundColor; _backgroundColor = newValue; _changed("backgroundColor", old: old) }
    }

    open var cornerRadius: CGFloat {
        get { _cornerRadius }
        set { guard newValue != _cornerRadius else { return }; let old = _cornerRadius; _cornerRadius = newValue; _changed("cornerRadius", old: old) }
    }

    open var borderWidth: CGFloat {
        get { _borderWidth }
        set { guard newValue != _borderWidth else { return }; let old = _borderWidth; _borderWidth = newValue; _changed("borderWidth", old: old) }
    }

    open var borderColor: CGColor? {
        get { _borderColor }
        set { let old = _borderColor; _borderColor = newValue; _changed("borderColor", old: old) }
    }

    /// A `CGImage` (other content kinds are ignored by the software compositor).
    open var contents: Any? {
        get { _contents }
        set { _contents = newValue; _changed("contents", old: nil) }
    }

    open var contentsRect: CGRect {
        get { _contentsRect }
        set { let old = _contentsRect; _contentsRect = newValue; _changed("contentsRect", old: old) }
    }

    open var contentsCenter: CGRect {
        get { _contentsCenter }
        set { let old = _contentsCenter; _contentsCenter = newValue; _changed("contentsCenter", old: old) }
    }

    open var contentsScale: CGFloat {
        get { _contentsScale }
        set { guard newValue != _contentsScale else { return }; _contentsScale = newValue; setNeedsDisplay() }
    }

    open var shadowColor: CGColor? {
        get { _shadowColor }
        set { let old = _shadowColor; _shadowColor = newValue; _changed("shadowColor", old: old) }
    }

    open var shadowOpacity: Float {
        get { _shadowOpacity }
        set { let old = _shadowOpacity; _shadowOpacity = newValue; _changed("shadowOpacity", old: old) }
    }

    open var shadowOffset: CGSize {
        get { _shadowOffset }
        set { let old = _shadowOffset; _shadowOffset = newValue; _changed("shadowOffset", old: old) }
    }

    open var shadowRadius: CGFloat {
        get { _shadowRadius }
        set { let old = _shadowRadius; _shadowRadius = newValue; _changed("shadowRadius", old: old) }
    }

    open var shadowPath: CGPath? {
        get { _shadowPath }
        set { _shadowPath = newValue; _changed("shadowPath", old: nil) }
    }

    open var mask: CALayer? {
        get { _mask }
        set { _mask?.superlayer = nil; _mask = newValue; _mask?.superlayer = self; _setNeedsRedraw() }
    }

    open var visibleRect: CGRect {
        guard let s = superlayer else { return _bounds }
        return convert(s.visibleRect.intersection(frame), from: s)
    }

    open var preferredFrameSize: CGSize { layoutManager?.preferredSize(of: self) ?? _bounds.size }

    // MARK: Sublayers

    open func addSublayer(_ layer: CALayer) {
        insertSublayer(layer, at: UInt32(_sublayers.count))
    }

    open func insertSublayer(_ layer: CALayer, at idx: UInt32) {
        precondition(layer !== self, "CALayer: cannot add a layer to itself")
        if layer.superlayer === self {
            _sublayers.removeAll { $0 === layer }
        } else {
            layer.removeFromSuperlayer()
        }
        let i = min(Int(idx), _sublayers.count)
        _sublayers.insert(layer, at: i)
        layer.superlayer = self
        layer.hasPresentation = layer.hasPresentation || hasPresentation
        _needsLayout = true
        _setNeedsRedraw()
        if hasPresentation, !CATransaction.disableActions(), let a = layer.action(forKey: kCAOnOrderIn) {
            a.run(forKey: kCAOnOrderIn, object: layer, arguments: nil)
        }
    }

    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {
        let i = sibling.flatMap { s in _sublayers.firstIndex { $0 === s } } ?? 0
        insertSublayer(layer, at: UInt32(i))
    }

    open func insertSublayer(_ layer: CALayer, above sibling: CALayer?) {
        let i = sibling.flatMap { s in _sublayers.firstIndex { $0 === s } }.map { $0 + 1 } ?? _sublayers.count
        insertSublayer(layer, at: UInt32(i))
    }

    open func replaceSublayer(_ oldLayer: CALayer, with newLayer: CALayer) {
        guard let i = _sublayers.firstIndex(where: { $0 === oldLayer }) else { return }
        oldLayer.superlayer = nil
        _sublayers.remove(at: i)
        insertSublayer(newLayer, at: UInt32(i))
    }

    open func removeFromSuperlayer() {
        guard let s = superlayer else { return }
        if s._mask === self { s._mask = nil } else { s._sublayers.removeAll { $0 === self } }
        s._needsLayout = true
        s._setNeedsRedraw()
        superlayer = nil
    }

    // MARK: Display

    open func setNeedsDisplay() {
        _needsDisplay = true
        _rasterVersion += 1
        _setNeedsRedraw()
    }

    open func setNeedsDisplay(_ r: CGRect) { setNeedsDisplay() }

    /// Marks the content stale without notifying the host (used by hosts that already redraw).
    public func _markNeedsDisplayQuietly() { _needsDisplay = true }

    open func needsDisplay() -> Bool { _needsDisplay }

    open func displayIfNeeded() {
        if _needsDisplay { display() }
    }

    /// Reloads the layer's content. With a delegate, `display(_:)` is asked; the default
    /// draws through `draw(in:)` at composite time, so nothing is cached here.
    open func display() {
        _needsDisplay = false
        if let d = delegate { d.display(self) } else { _displayDefault() }
    }

    /// The default `display()` behaviour: content is produced by `draw(in:)` when composited.
    public func _displayDefault() {
        _needsDisplay = false
    }

    /// Draws the layer's content into `ctx` (bounds coordinates). Subclasses override;
    /// the base implementation forwards to the delegate.
    open func draw(in ctx: CGContext) {
        delegate?.draw(self, in: ctx)
    }

    /// Composites the layer and its sublayers into `ctx`, whose coordinate space is the
    /// layer's *own bounds* space (as Core Animation's `render(in:)`).
    open func render(in ctx: CGContext) {
        let saved = (_position, _anchorPoint, _transform)
        _position = CGPoint(x: _bounds.minX + _anchorPoint.x * _bounds.width, y: _bounds.minY + _anchorPoint.y * _bounds.height)
        _transform = CATransform3DIdentity
        _compose(into: ctx, parentFlipped: _isGeometryFlipped, alpha: 1, time: CARuntime.now(), dirty: nil)
        (_position, _anchorPoint, _transform) = saved
    }

    open func setNeedsLayout() {
        _needsLayout = true
        _setNeedsRedraw()
    }

    open func needsLayout() -> Bool { _needsLayout }

    open func layoutIfNeeded() {
        if _needsLayout {
            _needsLayout = false
            layoutSublayers()
        }
        for s in _sublayers { s.layoutIfNeeded() }
    }

    open func layoutSublayers() {
        if let lm = layoutManager { lm.layoutSublayers(of: self) }
        delegate?.layoutSublayers(of: self)
    }

    private func _resizeSublayers(oldSize: CGSize) {
        guard oldSize.width > 0 || oldSize.height > 0 else { return }
        let dw = _bounds.width - oldSize.width, dh = _bounds.height - oldSize.height
        for s in _sublayers where !s.autoresizingMask.isEmpty {
            let m = s.autoresizingMask
            var f = s.frame
            let flexX = (m.contains(.layerMinXMargin) ? 1 : 0) + (m.contains(.layerWidthSizable) ? 1 : 0) + (m.contains(.layerMaxXMargin) ? 1 : 0)
            if flexX > 0 {
                let share = dw / CGFloat(flexX)
                if m.contains(.layerMinXMargin) { f.origin.x += share }
                if m.contains(.layerWidthSizable) { f.size.width += share }
            }
            let flexY = (m.contains(.layerMinYMargin) ? 1 : 0) + (m.contains(.layerHeightSizable) ? 1 : 0) + (m.contains(.layerMaxYMargin) ? 1 : 0)
            if flexY > 0 {
                let share = dh / CGFloat(flexY)
                if m.contains(.layerMinYMargin) { f.origin.y += share }
                if m.contains(.layerHeightSizable) { f.size.height += share }
            }
            s.frame = f
        }
    }

    open func resize(withOldSuperlayerSize size: CGSize) {}
    open func resizeSublayers(withOldSize size: CGSize) { _resizeSublayers(oldSize: size) }

    // MARK: Coordinate conversion

    /// Own bounds space -> superlayer space.
    private func _toSuperlayer(_ p: CGPoint, flipped parentFlipped: Bool) -> CGPoint {
        let ax = _bounds.minX + _anchorPoint.x * _bounds.width
        let ay = _bounds.minY + _anchorPoint.y * _bounds.height
        var q = p
        if _isGeometryFlipped != parentFlipped { q.y = _bounds.minY + _bounds.maxY - q.y }
        q = CGPoint(x: q.x - ax, y: q.y - ay).applying(_transform)
        return CGPoint(x: q.x + _position.x, y: q.y + _position.y)
    }

    private func _fromSuperlayer(_ p: CGPoint, flipped parentFlipped: Bool) -> CGPoint {
        var q = CGPoint(x: p.x - _position.x, y: p.y - _position.y)
        q = q.applying(CATransform3DInvert(_transform))
        let ax = _bounds.minX + _anchorPoint.x * _bounds.width
        let ay = _bounds.minY + _anchorPoint.y * _bounds.height
        q = CGPoint(x: q.x + ax, y: q.y + ay)
        if _isGeometryFlipped != parentFlipped { q.y = _bounds.minY + _bounds.maxY - q.y }
        return q
    }

    private var _parentFlipped: Bool { superlayer?._isGeometryFlipped ?? _isGeometryFlipped }

    private func _ancestors() -> [CALayer] {
        var chain: [CALayer] = [self]
        var l = self
        while let s = l.superlayer { chain.append(s); l = s }
        return chain
    }

    private func _toRoot(_ p: CGPoint) -> CGPoint {
        var q = p
        var l: CALayer? = self
        while let cur = l, cur.superlayer != nil {
            q = cur._toSuperlayer(q, flipped: cur._parentFlipped)
            l = cur.superlayer
        }
        return q
    }

    private func _fromRoot(_ p: CGPoint) -> CGPoint {
        let chain = _ancestors().dropLast().reversed()   // from the root's child down to self
        var q = p
        for cur in chain { q = cur._fromSuperlayer(q, flipped: cur._parentFlipped) }
        return q
    }

    open func convert(_ p: CGPoint, from l: CALayer?) -> CGPoint {
        guard let l else { return p }
        return _fromRoot(l._toRoot(p))
    }

    open func convert(_ p: CGPoint, to l: CALayer?) -> CGPoint {
        guard let l else { return p }
        return l._fromRoot(_toRoot(p))
    }

    open func convert(_ r: CGRect, from l: CALayer?) -> CGRect {
        let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            .map { convert($0, from: l) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    open func convert(_ r: CGRect, to l: CALayer?) -> CGRect {
        let pts = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            .map { convert($0, to: l) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    open func convertTime(_ t: CFTimeInterval, from l: CALayer?) -> CFTimeInterval { t }
    open func convertTime(_ t: CFTimeInterval, to l: CALayer?) -> CFTimeInterval { t }

    open func contains(_ p: CGPoint) -> Bool { _bounds.contains(p) }

    /// The deepest layer containing `p`, given in the superlayer's space.
    open func hitTest(_ p: CGPoint) -> CALayer? {
        guard !_isHidden else { return nil }
        let local = _fromSuperlayer(p, flipped: _parentFlipped)
        if _masksToBounds && !_bounds.contains(local) { return nil }
        for s in _sublayers.sorted(by: { $0._zPosition < $1._zPosition }).reversed() {
            if let hit = s.hitTest(local) { return hit }
        }
        return contains(local) ? self : nil
    }

    // MARK: Animations

    open func add(_ anim: CAAnimation, forKey key: String?) {
        let copy = anim._copy()
        let k = key ?? { animationCounter += 1; return "animation\(animationCounter)" }()
        copy.layerKey = k
        copy.addedAt = CARuntime.now()
        if let basic = copy as? CABasicAnimation, basic.fromValue == nil, basic.toValue == nil || basic.byValue == nil, let kp = basic.keyPath {
            // An implicit or from-less animation starts where the layer currently is.
            if basic.toValue != nil || basic.byValue == nil {
                basic.fromValue = pendingOldValues[kp] ?? _presentationValue(forKeyPath: kp)
            }
        }
        copy.countsForTransaction = CATransaction.noteAnimationAdded()
        animations.removeAll { $0.key == k }
        animations.append((k, copy))
        hasPresentation = true
        CARuntime.noteAnimating(root: root)
        _setNeedsRedraw()
    }

    open func removeAllAnimations() {
        let old = animations
        animations.removeAll()
        for (_, a) in old { _finish(a, finished: false) }
        _setNeedsRedraw()
    }

    open func removeAnimation(forKey key: String) {
        guard let i = animations.firstIndex(where: { $0.key == key }) else { return }
        let a = animations.remove(at: i).animation
        _finish(a, finished: false)
        _setNeedsRedraw()
    }

    open func animationKeys() -> [String]? { animations.isEmpty ? nil : animations.map(\.key) }

    open func animation(forKey key: String) -> CAAnimation? { animations.first { $0.key == key }?.animation }

    private func _finish(_ a: CAAnimation, finished: Bool) {
        if a.countsForTransaction { CATransactionCompletion.animationFinished() }
        a.delegate?.animationDidStop(a, finished: finished)
    }

    /// Advances animations in the subtree: starts pending ones, removes finished ones.
    /// Returns true while any animation is still running.
    public func _advanceAnimations(now: CFTimeInterval) -> Bool {
        var active = false
        var finished: [CAAnimation] = []
        for (_, a) in animations {
            let phase = a.localTime(parentTime: now).phase
            if phase != .before && !a.didStart { a.didStart = true; a.delegate?.animationDidStart(a) }
            if phase == .after {
                if a.isRemovedOnCompletion { finished.append(a) } else if a.fillMode == .forwards || a.fillMode == .both { /* holds */ }
            } else {
                active = true
            }
        }
        if !finished.isEmpty {
            animations.removeAll { entry in finished.contains { $0 === entry.animation } }
            for a in finished { _finish(a, finished: true) }
        }
        for s in _sublayers where s._advanceAnimations(now: now) { active = true }
        if let m = _mask, m._advanceAnimations(now: now) { active = true }
        return active
    }

    var hasActiveAnimations: Bool { !animations.isEmpty }

    /// Whether this layer, its mask or any sublayer has animations attached.
    public var _hasAnimationsInTree: Bool {
        if !animations.isEmpty { return true }
        if let m = _mask, m._hasAnimationsInTree { return true }
        return _sublayers.contains { $0._hasAnimationsInTree }
    }

    /// A copy of the layer with the running animations applied at `time`.
    func _presentation(at time: CFTimeInterval) -> CALayer {
        let p = type(of: self).init(layer: self)
        for (_, a) in animations { a.apply(to: p, model: self, parentTime: time) }
        return p
    }

    /// A copy of the layer with the running animations applied, or nil before the first render.
    open func presentation() -> Self? {
        guard hasPresentation else { return nil }
        return (_presentation(at: CARuntime.now()) as! Self)
    }

    open func model() -> Self { self }

    private func _presentationValue(forKeyPath kp: String) -> Any? {
        guard !animations.isEmpty else { return _value(forKeyPath: kp) }
        return _presentation(at: CARuntime.now())._value(forKeyPath: kp)
    }

    // MARK: Actions

    open func action(forKey event: String) -> (any CAAction)? {
        if let d = delegate {
            if let a = d.action(for: self, forKey: event) { return a is NSNull ? nil : a }
        }
        if let a = actions?[event] { return a is NSNull ? nil : a }
        if let s = style, let a = s["actions"] as? [String: any CAAction], let act = a[event] { return act is NSNull ? nil : act }
        return defaultAction(forKey: event)
    }

    open class func defaultAction(forKey event: String) -> (any CAAction)? { nil }

    /// The implicit animation for an animatable property: a basic animation from the
    /// presentation value to the model value over the transaction's duration.
    open func defaultAction(forKey event: String) -> (any CAAction)? {
        guard CALayer.animatableKeys.contains(event) else { return nil }
        let a = CABasicAnimation(keyPath: event)
        a.duration = CATransaction.animationDuration()
        a.timingFunction = CATransaction.animationTimingFunction()
        return a
    }

    static let animatableKeys: Set<String> = [
        "bounds", "position", "zPosition", "anchorPoint", "anchorPointZ", "transform", "sublayerTransform",
        "hidden", "opacity", "backgroundColor", "cornerRadius", "borderWidth", "borderColor", "contents",
        "contentsRect", "contentsCenter", "shadowColor", "shadowOpacity", "shadowOffset", "shadowRadius", "shadowPath",
    ]

    open class func needsDisplay(forKey key: String) -> Bool { false }
    open class func defaultValue(forKey key: String) -> Any? { nil }
    open func shouldArchiveValue(forKey key: String) -> Bool { true }

    // MARK: Key paths

    /// Reads a property by Core Animation key path ("position.x", "transform.scale", ...).
    public func _value(forKeyPath kp: String) -> Any? {
        switch kp {
        case "bounds": return _bounds
        case "bounds.origin": return _bounds.origin
        case "bounds.origin.x": return _bounds.minX
        case "bounds.origin.y": return _bounds.minY
        case "bounds.size": return _bounds.size
        case "bounds.size.width": return _bounds.width
        case "bounds.size.height": return _bounds.height
        case "position": return _position
        case "position.x": return _position.x
        case "position.y": return _position.y
        case "frame": return frame
        case "zPosition": return _zPosition
        case "anchorPoint": return _anchorPoint
        case "anchorPoint.x": return _anchorPoint.x
        case "anchorPoint.y": return _anchorPoint.y
        case "anchorPointZ": return _anchorPointZ
        case "transform": return _transform
        case "sublayerTransform": return _sublayerTransform
        case "hidden": return _isHidden
        case "opacity": return CGFloat(_opacity)
        case "backgroundColor": return _backgroundColor
        case "cornerRadius": return _cornerRadius
        case "borderWidth": return _borderWidth
        case "borderColor": return _borderColor
        case "contents": return _contents
        case "contentsRect": return _contentsRect
        case "contentsCenter": return _contentsCenter
        case "contentsScale": return _contentsScale
        case "shadowColor": return _shadowColor
        case "shadowOpacity": return CGFloat(_shadowOpacity)
        case "shadowOffset": return _shadowOffset
        case "shadowRadius": return _shadowRadius
        case "shadowPath": return _shadowPath
        case "masksToBounds": return _masksToBounds
        case "name": return name
        default: break
        }
        if kp.hasPrefix("transform.") || kp.hasPrefix("sublayerTransform.") {
            let t = kp.hasPrefix("transform.") ? _transform : _sublayerTransform
            let sub = String(kp[kp.index(after: kp.firstIndex(of: ".")!)...])
            return CALayer._transformComponent(t, sub)
        }
        return userValues[kp]
    }

    /// Writes a property by key path. Transform sub-keys compose onto the current transform.
    public func _setValue(_ v: Any?, forKeyPath kp: String) {
        let n = CAInterpolation.number(v)
        switch kp {
        case "bounds": if let r = v as? CGRect { bounds = r }
        case "bounds.origin": if let p = v as? CGPoint { bounds.origin = p }
        case "bounds.origin.x": if let x = n { bounds.origin.x = x }
        case "bounds.origin.y": if let x = n { bounds.origin.y = x }
        case "bounds.size": if let s = v as? CGSize { bounds.size = s }
        case "bounds.size.width": if let x = n { bounds.size.width = x }
        case "bounds.size.height": if let x = n { bounds.size.height = x }
        case "position": if let p = v as? CGPoint { position = p }
        case "position.x": if let x = n { position.x = x }
        case "position.y": if let x = n { position.y = x }
        case "frame": if let r = v as? CGRect { frame = r }
        case "zPosition": if let x = n { zPosition = x }
        case "anchorPoint": if let p = v as? CGPoint { anchorPoint = p }
        case "anchorPoint.x": if let x = n { anchorPoint.x = x }
        case "anchorPoint.y": if let x = n { anchorPoint.y = x }
        case "anchorPointZ": if let x = n { anchorPointZ = x }
        case "transform": if let t = v as? CATransform3D { transform = t } else if let a = v as? CGAffineTransform { setAffineTransform(a) }
        case "sublayerTransform": if let t = v as? CATransform3D { sublayerTransform = t }
        case "hidden": if let b = v as? Bool { isHidden = b } else if let x = n { isHidden = x != 0 }
        case "opacity": if let x = n { opacity = Float(x) }
        case "backgroundColor": backgroundColor = CAInterpolation.asColor(v)
        case "cornerRadius": if let x = n { cornerRadius = x }
        case "borderWidth": if let x = n { borderWidth = x }
        case "borderColor": borderColor = CAInterpolation.asColor(v)
        case "contents": contents = v
        case "contentsRect": if let r = v as? CGRect { contentsRect = r }
        case "contentsCenter": if let r = v as? CGRect { contentsCenter = r }
        case "contentsScale": if let x = n { contentsScale = x }
        case "shadowColor": shadowColor = CAInterpolation.asColor(v)
        case "shadowOpacity": if let x = n { shadowOpacity = Float(x) }
        case "shadowOffset": if let s = v as? CGSize { shadowOffset = s }
        case "shadowRadius": if let x = n { shadowRadius = x }
        case "shadowPath": shadowPath = CAInterpolation.asPath(v)
        case "masksToBounds": if let b = v as? Bool { masksToBounds = b }
        case "name": name = v as? String
        default:
            if kp.hasPrefix("transform.") {
                let sub = String(kp[kp.index(after: kp.firstIndex(of: ".")!)...])
                transform = CALayer._settingTransformComponent(_transform, sub, v)
            } else if kp.hasPrefix("sublayerTransform.") {
                let sub = String(kp[kp.index(after: kp.firstIndex(of: ".")!)...])
                sublayerTransform = CALayer._settingTransformComponent(_sublayerTransform, sub, v)
            } else {
                userValues[kp] = v
                _changed(kp, old: nil)
            }
        }
    }

    static func _transformComponent(_ t: CATransform3D, _ sub: String) -> Any? {
        let sx = (t.m11 * t.m11 + t.m12 * t.m12 + t.m13 * t.m13).squareRoot()
        let sy = (t.m21 * t.m21 + t.m22 * t.m22 + t.m23 * t.m23).squareRoot()
        let sz = (t.m31 * t.m31 + t.m32 * t.m32 + t.m33 * t.m33).squareRoot()
        switch sub {
        case "scale": return (sx + sy + sz) / 3
        case "scale.x": return sx
        case "scale.y": return sy
        case "scale.z": return sz
        case "rotation", "rotation.z": return atan2(t.m12, t.m11)
        case "rotation.x": return atan2(t.m23, t.m22)
        case "rotation.y": return atan2(t.m31, t.m33)
        case "translation": return CGSize(width: t.m41, height: t.m42)
        case "translation.x": return t.m41
        case "translation.y": return t.m42
        case "translation.z": return t.m43
        default: return nil
        }
    }

    /// Applies a sub-key relative to `base` (the model transform), as value functions do.
    static func _settingTransformComponent(_ base: CATransform3D, _ sub: String, _ v: Any?) -> CATransform3D {
        let n = CAInterpolation.number(v) ?? 0
        var delta = CATransform3DIdentity
        switch sub {
        case "scale": delta = CATransform3DMakeScale(n, n, 1)
        case "scale.x": delta = CATransform3DMakeScale(n, 1, 1)
        case "scale.y": delta = CATransform3DMakeScale(1, n, 1)
        case "scale.z": delta = CATransform3DMakeScale(1, 1, n)
        case "rotation", "rotation.z": delta = CATransform3DMakeRotation(n, 0, 0, 1)
        case "rotation.x": delta = CATransform3DMakeRotation(n, 1, 0, 0)
        case "rotation.y": delta = CATransform3DMakeRotation(n, 0, 1, 0)
        case "translation":
            if let s = v as? CGSize { delta = CATransform3DMakeTranslation(s.width, s.height, 0) }
            else if let p = v as? CGPoint { delta = CATransform3DMakeTranslation(p.x, p.y, 0) }
        case "translation.x": delta = CATransform3DMakeTranslation(n, 0, 0)
        case "translation.y": delta = CATransform3DMakeTranslation(0, n, 0)
        case "translation.z": delta = CATransform3DMakeTranslation(0, 0, n)
        default: return base
        }
        return CATransform3DConcat(delta, base)
    }

    #if canImport(ObjectiveC)
    open override func value(forKeyPath keyPath: String) -> Any? { MainActor.assumeIsolated { _value(forKeyPath: keyPath) } }
    open override func setValue(_ value: Any?, forKeyPath keyPath: String) { MainActor.assumeIsolated { _setValue(value, forKeyPath: keyPath) } }
    open override func value(forKey key: String) -> Any? { MainActor.assumeIsolated { _value(forKeyPath: key) } }
    open override func setValue(_ value: Any?, forKey key: String) { MainActor.assumeIsolated { _setValue(value, forKeyPath: key) } }
    #else
    open func value(forKeyPath keyPath: String) -> Any? { _value(forKeyPath: keyPath) }
    open func setValue(_ value: Any?, forKeyPath keyPath: String) { _setValue(value, forKeyPath: keyPath) }
    open func value(forKey key: String) -> Any? { _value(forKeyPath: key) }
    open func setValue(_ value: Any?, forKey key: String) { _setValue(value, forKeyPath: key) }
    #endif

    // MARK: Compositing

    /// Composites this layer into `ctx`, whose coordinate space is the superlayer's bounds
    /// space with orientation `parentFlipped`. `dirty` is in that space, nil for everything.
    public func _compose(into ctx: CGContext, parentFlipped: Bool, alpha: CGFloat, time: CFTimeInterval, dirty: CGRect?) {
        hasPresentation = true
        let p = animations.isEmpty ? self : _presentation(at: time)
        guard !p._isHidden, p._opacity > 0 else { return }
        if let dirty, p._transform.isIdentity, !p.frame.intersects(dirty), p._masksToBounds { return }
        if _needsLayout { _needsLayout = false; layoutSublayers() }
        if _needsDisplay { display() }

        ctx.saveGState()
        ctx.translateBy(x: p._position.x, y: p._position.y)
        if !p._transform.isIdentity { ctx.concatenate(p._transform.affineTransform) }
        let ax = p._bounds.minX + p._anchorPoint.x * p._bounds.width
        let ay = p._bounds.minY + p._anchorPoint.y * p._bounds.height
        ctx.translateBy(x: -ax, y: -ay)
        let flip = p._isGeometryFlipped != parentFlipped
        if flip {
            // Mirror the content within the layer's own rect; the frame itself does not move.
            ctx.translateBy(x: 0, y: p._bounds.minY + p._bounds.maxY)
            ctx.scaleBy(x: 1, y: -1)
        }

        let a = alpha * CGFloat(p._opacity)
        ctx.setAlpha(a)
        let b = p._bounds
        if let m = p._mask { m._applyMask(to: ctx, in: self) }
        if p._masksToBounds { p._addBoundsPath(ctx, b); ctx.clip() }

        // Shadow: an offset, translucent copy of the shape (no blur in the software path).
        if p._shadowOpacity > 0, let sc = p._shadowColor {
            let comps = CAInterpolation.rgba(sc)
            ctx.saveGState()
            ctx.setAlpha(a * CGFloat(p._shadowOpacity) * comps[3])
            ctx.setFillColor(CAInterpolation.color([comps[0], comps[1], comps[2], 1]))
            ctx.translateBy(x: p._shadowOffset.width, y: flip ? -p._shadowOffset.height : p._shadowOffset.height)
            if let sp = p._shadowPath { ctx.addPath(sp) } else { p._addBoundsPath(ctx, b) }
            ctx.fillPath()
            ctx.restoreGState()
        }

        _drawOwnContent(into: ctx, presentation: p)

        // Sublayers, in bounds space, through the sublayer transform about the anchor.
        let subs = p._sublayers.isEmpty ? _sublayers : p._sublayers
        if !subs.isEmpty {
            ctx.saveGState()
            if !p._sublayerTransform.isIdentity {
                ctx.translateBy(x: ax, y: ay)
                ctx.concatenate(p._sublayerTransform.affineTransform)
                ctx.translateBy(x: -ax, y: -ay)
            }
            let localDirty: CGRect? = (dirty != nil && p._transform.isIdentity) ? _localRect(dirty!, p: p, flip: flip) : nil
            let ordered = subs.enumerated().sorted { l, r in
                l.element._zPosition != r.element._zPosition ? l.element._zPosition < r.element._zPosition : l.offset < r.offset
            }.map(\.element)
            for s in ordered {
                s._compose(into: ctx, parentFlipped: p._isGeometryFlipped, alpha: a, time: time, dirty: localDirty)
            }
            ctx.restoreGState()
        }

        p._drawBorder(into: ctx)
        ctx.restoreGState()
    }

    /// Background, `contents` and delegate/subclass drawing, in the layer's oriented bounds
    /// space. `presentation` carries the animated values; `self` is the model the delegate sees.
    func _drawOwnContent(into ctx: CGContext, presentation p: CALayer) {
        if _needsDisplay { display() }
        // A layer's own content lives in its backing store, so it never extends past the
        // bounds (sublayers may, unless masksToBounds); native hosts rasterise exactly this.
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: p._bounds)
        if let bg = p._backgroundColor {
            ctx.setFillColor(bg)
            p._addBoundsPath(ctx, p._bounds)
            ctx.fillPath()
        }
        p._drawContents(in: ctx, flipped: p._isGeometryFlipped)
        delegate?.layerWillDraw(self)
        ctx.saveGState()
        p._drawContent(in: ctx, model: self)
        ctx.restoreGState()
    }

    /// The border, stroked inside the bounds (drawn above sublayers).
    func _drawBorder(into ctx: CGContext) {
        guard _borderWidth > 0, let bc = _borderColor else { return }
        ctx.setStrokeColor(bc)
        ctx.setLineWidth(_borderWidth)
        _addBoundsPath(ctx, _bounds.insetBy(dx: _borderWidth / 2, dy: _borderWidth / 2), radiusInset: _borderWidth / 2)
        ctx.strokePath()
    }

    /// Converts a superlayer-space rect into this layer's bounds space (translation-only placement).
    private func _localRect(_ r: CGRect, p: CALayer, flip: Bool) -> CGRect {
        let ax = p._bounds.minX + p._anchorPoint.x * p._bounds.width
        let ay = p._bounds.minY + p._anchorPoint.y * p._bounds.height
        var out = CGRect(x: r.minX - p._position.x + ax, y: r.minY - p._position.y + ay, width: r.width, height: r.height)
        if flip { out.origin.y = p._bounds.minY + p._bounds.maxY - out.maxY }
        return out
    }

    /// Subclasses draw their own content here (bounds coordinates). The base class asks
    /// `draw(in:)` on the *model* layer so delegates see the real layer.
    func _drawContent(in ctx: CGContext, model: CALayer) {
        model.draw(in: ctx)
    }

    func _addBoundsPath(_ ctx: CGContext, _ r: CGRect, radiusInset: CGFloat = 0) {
        let radius = max(0, _cornerRadius - radiusInset)
        if radius > 0 && maskedCorners == .all {
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil))
        } else if radius > 0 {
            let path = CGMutablePath()
            let rr = min(radius, r.width / 2, r.height / 2)
            func corner(_ c: CACornerMask) -> CGFloat { maskedCorners.contains(c) ? rr : 0 }
            let (tl, tr, bl, br) = (corner(.layerMinXMaxYCorner), corner(.layerMaxXMaxYCorner), corner(.layerMinXMinYCorner), corner(.layerMaxXMinYCorner))
            path.move(to: CGPoint(x: r.minX + bl, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX - br, y: r.minY))
            if br > 0 { path.addArc(center: CGPoint(x: r.maxX - br, y: r.minY + br), radius: br, startAngle: -.pi / 2, endAngle: 0, clockwise: false) }
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - tr))
            if tr > 0 { path.addArc(center: CGPoint(x: r.maxX - tr, y: r.maxY - tr), radius: tr, startAngle: 0, endAngle: .pi / 2, clockwise: false) }
            path.addLine(to: CGPoint(x: r.minX + tl, y: r.maxY))
            if tl > 0 { path.addArc(center: CGPoint(x: r.minX + tl, y: r.maxY - tl), radius: tl, startAngle: .pi / 2, endAngle: .pi, clockwise: false) }
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + bl))
            if bl > 0 { path.addArc(center: CGPoint(x: r.minX + bl, y: r.minY + bl), radius: bl, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false) }
            path.closeSubpath()
            ctx.addPath(path)
        } else {
            ctx.addRect(r)
        }
    }

    /// Clips `ctx` (in `owner`'s bounds space) to this mask layer's shape.
    private func _applyMask(to ctx: CGContext, in owner: CALayer) {
        let f = frame
        if let shape = self as? CAShapeLayer, let path = shape.path {
            var t = CGAffineTransform(translationX: f.minX - _bounds.minX, y: f.minY - _bounds.minY)
            ctx.addPath(path.copy(using: &t) ?? path)
            ctx.clip()
        } else {
            _addBoundsPath(ctx, f)
            ctx.clip()
        }
    }

    /// Draws `contents` (a CGImage) positioned by `contentsGravity`.
    private func _drawContents(in ctx: CGContext, flipped: Bool) {
        guard let image = CALayer._image(from: _contents) else { return }
        let b = _bounds
        let iw = CGFloat(image.width) / _contentsScale, ih = CGFloat(image.height) / _contentsScale
        var r = b
        switch contentsGravity {
        case .resize: r = b
        case .resizeAspect:
            let s = min(b.width / max(iw, 1), b.height / max(ih, 1))
            r = CGRect(x: b.midX - iw * s / 2, y: b.midY - ih * s / 2, width: iw * s, height: ih * s)
        case .resizeAspectFill:
            let s = max(b.width / max(iw, 1), b.height / max(ih, 1))
            r = CGRect(x: b.midX - iw * s / 2, y: b.midY - ih * s / 2, width: iw * s, height: ih * s)
        default:
            let g = contentsGravity.rawValue
            var x = b.midX - iw / 2, y = b.midY - ih / 2
            if g.hasPrefix("left") || g.hasSuffix("Left") { x = b.minX }
            if g.hasPrefix("right") || g.hasSuffix("Right") { x = b.maxX - iw }
            // "top" is the max-y edge in unflipped space and the min-y edge when flipped.
            if g.hasPrefix("top") { y = flipped ? b.minY : b.maxY - ih }
            if g.hasPrefix("bottom") { y = flipped ? b.maxY - ih : b.minY }
            r = CGRect(x: x, y: y, width: iw, height: ih)
        }
        ctx.saveGState()
        if _masksToBounds == false { ctx.clip(to: b) }
        if flipped {
            ctx.translateBy(x: 0, y: r.minY + r.maxY)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.draw(image, in: r)
        ctx.restoreGState()
    }

    static func _image(from contents: Any?) -> CGImage? {
        guard let c = contents else { return nil }
        #if os(Windows) || os(Linux)
        return c as? CGImage
        #else
        if CFGetTypeID(c as CFTypeRef) == CGImage.typeID { return (c as! CGImage) }
        return nil
        #endif
    }

    open override var description: String {
        MainActor.assumeIsolated { "<\(type(of: self)) \(name ?? "") frame=\(frame)>" }
    }
}

