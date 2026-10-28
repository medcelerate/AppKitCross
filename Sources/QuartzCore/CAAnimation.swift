// CAAnimation and its subclasses: property animations evaluated on the main actor by
// the layer renderer. Values are interpolated for numbers, points, sizes, rects,
// colours and transforms.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caaction
@MainActor
public protocol CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?)
}

/// `NSNull` in an actions dictionary or from a delegate means "no implicit animation".
extension NSNull: CAAction {
    @MainActor public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caanimationdelegate
@MainActor
public protocol CAAnimationDelegate: AnyObject {
    func animationDidStart(_ anim: CAAnimation)
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool)
}

extension CAAnimationDelegate {
    public func animationDidStart(_ anim: CAAnimation) {}
    public func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caanimation
@MainActor
open class CAAnimation: NSObject, CAMediaTiming, CAAction {
    public var beginTime: CFTimeInterval = 0
    public var duration: CFTimeInterval = 0
    public var speed: Float = 1
    public var timeOffset: CFTimeInterval = 0
    public var repeatCount: Float = 0
    public var repeatDuration: CFTimeInterval = 0
    public var autoreverses = false
    public var fillMode: CAMediaTimingFillMode = .removed

    open var timingFunction: CAMediaTimingFunction?
    open weak var delegate: (any CAAnimationDelegate)?
    open var isRemovedOnCompletion = true
    open var preferredFrameRateRange = CAFrameRateRange()
    private var userValues: [String: Any] = [:]

    // Runtime state (set when the animation is added to a layer).
    var addedAt: CFTimeInterval = 0
    var layerKey: String = ""
    var didStart = false
    var countsForTransaction = false

    public required override init() { super.init() }

    public class func defaultValue(forKey key: String) -> Any? { nil }
    open func shouldArchiveValue(forKey key: String) -> Bool { true }

    #if canImport(ObjectiveC)
    open override func value(forKey key: String) -> Any? { MainActor.assumeIsolated { userValues[key] } }
    open override func setValue(_ value: Any?, forKey key: String) { MainActor.assumeIsolated { userValues[key] = value } }
    open override func copy() -> Any { MainActor.assumeIsolated { _copy() } }
    #else
    open func value(forKey key: String) -> Any? { userValues[key] }
    open func setValue(_ value: Any?, forKey key: String) { userValues[key] = value }
    open override func copy() -> Any { MainActor.assumeIsolated { _copy() } }
    #endif

    func _copy() -> CAAnimation {
        let c = type(of: self).init()
        copyInto(c)
        return c
    }

    func copyInto(_ c: CAAnimation) {
        c.beginTime = beginTime; c.duration = duration; c.speed = speed; c.timeOffset = timeOffset
        c.repeatCount = repeatCount; c.repeatDuration = repeatDuration; c.autoreverses = autoreverses
        c.fillMode = fillMode; c.timingFunction = timingFunction; c.delegate = delegate
        c.isRemovedOnCompletion = isRemovedOnCompletion; c.userValues = userValues
    }

    /// CAAction: adds a copy of the animation to the layer under `event`.
    open func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
        guard let layer = anObject as? CALayer else { return }
        layer.add(self, forKey: event)
    }

    // MARK: Timing

    /// The duration used for evaluation (0 means the transaction default).
    var effectiveDuration: CFTimeInterval { duration > 0 ? duration : 0.25 }

    /// Total active length in local time, or nil when repeating forever.
    var activeDuration: CFTimeInterval? {
        let cycle = effectiveDuration * (autoreverses ? 2 : 1)
        if repeatDuration > 0 { return repeatDuration }
        if repeatCount == .infinity { return nil }
        if repeatCount > 0 { return cycle * CFTimeInterval(repeatCount) }
        return cycle
    }

    /// Local time within the animation for a parent time, or nil before it begins
    /// (and `fillMode` does not fill backwards).
    func localTime(parentTime: CFTimeInterval) -> (t: CFTimeInterval, phase: Phase) {
        let start = beginTime == 0 ? addedAt : beginTime
        var t = (parentTime - start) * CFTimeInterval(speed) + timeOffset
        if t < 0 { return (0, .before) }
        if let total = activeDuration, t >= total { t = total; return (t, .after) }
        return (t, .active)
    }

    enum Phase { case before, active, after }

    /// Progress 0...1 within the current cycle for local time `t`, eased.
    func progress(localTime t: CFTimeInterval) -> Float {
        let d = effectiveDuration
        guard d > 0 else { return 1 }
        var cycles = t / d
        if autoreverses {
            let whole = floor(cycles)
            var frac = cycles - whole
            if Int(whole) % 2 == 1 { frac = 1 - frac }
            cycles = frac
        } else {
            cycles -= floor(cycles)
            if t > 0 && cycles == 0 && (activeDuration.map { t >= $0 } ?? false) { cycles = 1 }
        }
        if let total = activeDuration, t >= total {
            // Final value: the end of the last cycle (start, when autoreversed to an even count).
            let lastCycles = total / d
            let whole = floor(lastCycles + 1e-9)
            if autoreverses { cycles = Int(whole) % 2 == 0 ? 0 : 1 } else { cycles = 1 }
        }
        let x = Float(max(0, min(1, cycles)))
        return (timingFunction ?? CATransaction.animationTimingFunction())?.evaluate(x) ?? x
    }

    /// Applies the animation's value for `parentTime` to the presentation layer.
    /// Returns false when the animation has no effect at that time.
    @discardableResult
    func apply(to presentation: CALayer, model: CALayer, parentTime: CFTimeInterval) -> Bool {
        let (t, phase) = localTime(parentTime: parentTime)
        switch phase {
        case .before: guard fillMode == .backwards || fillMode == .both else { return false }
        case .after: guard fillMode == .forwards || fillMode == .both || !isRemovedOnCompletion else { return false }
        case .active: break
        }
        applyValue(to: presentation, model: model, localTime: t)
        return true
    }

    /// Subclasses write their interpolated value here.
    func applyValue(to presentation: CALayer, model: CALayer, localTime t: CFTimeInterval) {}

    /// Whether the animation is finished at `parentTime`.
    func isFinished(parentTime: CFTimeInterval) -> Bool { localTime(parentTime: parentTime).phase == .after }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/capropertyanimation
@MainActor
open class CAPropertyAnimation: CAAnimation {
    open var keyPath: String?
    open var isAdditive = false
    open var isCumulative = false
    open var valueFunction: CAValueFunction?

    public required init() { super.init() }

    public convenience init(keyPath path: String?) {
        self.init()
        keyPath = path
    }

    override func copyInto(_ c: CAAnimation) {
        super.copyInto(c)
        if let p = c as? CAPropertyAnimation {
            p.keyPath = keyPath; p.isAdditive = isAdditive; p.isCumulative = isCumulative; p.valueFunction = valueFunction
        }
    }

    /// Writes `value` for `keyPath`, adding to the presentation's current value when additive.
    func write(_ value: Any?, to presentation: CALayer) {
        guard let keyPath else { return }
        if isAdditive, let cur = presentation._value(forKeyPath: keyPath), let sum = CAInterpolation.add(cur, value) {
            presentation._setValue(sum, forKeyPath: keyPath)
        } else {
            presentation._setValue(value, forKeyPath: keyPath)
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cabasicanimation
@MainActor
open class CABasicAnimation: CAPropertyAnimation {
    open var fromValue: Any?
    open var toValue: Any?
    open var byValue: Any?

    public required init() { super.init() }

    override func copyInto(_ c: CAAnimation) {
        super.copyInto(c)
        if let b = c as? CABasicAnimation { b.fromValue = fromValue; b.toValue = toValue; b.byValue = byValue }
    }

    override func applyValue(to presentation: CALayer, model: CALayer, localTime t: CFTimeInterval) {
        guard let keyPath else { return }
        let modelValue = model._value(forKeyPath: keyPath)
        var from = fromValue, to = toValue
        if from == nil && to == nil && byValue != nil {
            from = modelValue
            to = CAInterpolation.add(modelValue, byValue)
        } else if from == nil {
            from = byValue != nil ? CAInterpolation.subtract(to, byValue) : (isAdditive ? CAInterpolation.zero(like: to ?? modelValue) : modelValue)
        } else if to == nil {
            to = byValue != nil ? CAInterpolation.add(from, byValue) : (isAdditive ? CAInterpolation.zero(like: from) : modelValue)
        }
        let p = progress(localTime: t)
        write(CAInterpolation.lerp(from, to, CGFloat(p)), to: presentation)
    }
}

public struct CAAnimationCalculationMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = CAAnimationCalculationMode(rawValue: "linear")
    public static let discrete = CAAnimationCalculationMode(rawValue: "discrete")
    public static let paced = CAAnimationCalculationMode(rawValue: "paced")
    public static let cubic = CAAnimationCalculationMode(rawValue: "cubic")
    public static let cubicPaced = CAAnimationCalculationMode(rawValue: "cubicPaced")
}

public struct CAAnimationRotationMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let rotateAuto = CAAnimationRotationMode(rawValue: "auto")
    public static let rotateAutoReverse = CAAnimationRotationMode(rawValue: "autoReverse")
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cakeyframeanimation
@MainActor
open class CAKeyframeAnimation: CAPropertyAnimation {
    open var values: [Any]?
    open var keyTimes: [NSNumber]?
    open var timingFunctions: [CAMediaTimingFunction]?
    open var calculationMode: CAAnimationCalculationMode = .linear
    open var path: CGPath?
    open var rotationMode: CAAnimationRotationMode?
    open var tensionValues: [NSNumber]?
    open var continuityValues: [NSNumber]?
    open var biasValues: [NSNumber]?

    public required init() { super.init() }

    override func copyInto(_ c: CAAnimation) {
        super.copyInto(c)
        if let k = c as? CAKeyframeAnimation {
            k.values = values; k.keyTimes = keyTimes; k.timingFunctions = timingFunctions
            k.calculationMode = calculationMode; k.path = path; k.rotationMode = rotationMode
        }
    }

    override func applyValue(to presentation: CALayer, model: CALayer, localTime t: CFTimeInterval) {
        var frames = values ?? []
        if frames.isEmpty, let path {
            frames = CAInterpolation.points(along: path).map { $0 as Any }
        }
        guard !frames.isEmpty else { return }
        if frames.count == 1 { write(frames[0], to: presentation); return }
        let p = CGFloat(progress(localTime: t))
        let times: [CGFloat] = keyTimes.map { $0.map { CGFloat($0.doubleValue) } } ?? (0..<frames.count).map { CGFloat($0) / CGFloat(frames.count - 1) }
        var i = 0
        while i + 1 < times.count && times[i + 1] <= p { i += 1 }
        if i >= frames.count - 1 { write(frames[frames.count - 1], to: presentation); return }
        if calculationMode == .discrete { write(frames[i], to: presentation); return }
        let span = times[i + 1] - times[i]
        var local = span > 0 ? (p - times[i]) / span : 1
        if let fns = timingFunctions, i < fns.count { local = CGFloat(fns[i].evaluate(Float(local))) }
        write(CAInterpolation.lerp(frames[i], frames[i + 1], local), to: presentation)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caspringanimation
@MainActor
open class CASpringAnimation: CABasicAnimation {
    open var mass: CGFloat = 1
    open var stiffness: CGFloat = 100
    open var damping: CGFloat = 10
    open var initialVelocity: CGFloat = 0
    open var allowsOverdamping = false

    public required init() { super.init() }

    @available(macOS 14.0, *)
    public convenience init(perceptualDuration: CFTimeInterval, bounce: CGFloat) {
        self.init()
        // Apple's mapping: natural frequency from the perceptual duration, damping ratio from bounce.
        let omega = 2 * CGFloat.pi / CGFloat(max(0.001, perceptualDuration))
        mass = 1
        stiffness = omega * omega
        let zeta = bounce >= 0 ? 1 - bounce : 1 / (1 + bounce)
        damping = 2 * zeta * omega
    }

    override func copyInto(_ c: CAAnimation) {
        super.copyInto(c)
        if let s = c as? CASpringAnimation {
            s.mass = mass; s.stiffness = stiffness; s.damping = damping; s.initialVelocity = initialVelocity
        }
    }

    /// Time for the spring to come within 0.1% of rest.
    open var settlingDuration: CFTimeInterval {
        let omega = (stiffness / mass).squareRoot()
        let zeta = damping / (2 * (stiffness * mass).squareRoot())
        guard omega > 0, zeta > 0 else { return 1 }
        let decay = zeta < 1 ? zeta * omega : omega * (zeta - (zeta * zeta - 1).squareRoot())
        guard decay > 0 else { return 1 }
        return CFTimeInterval(-log(0.001) / decay)
    }

    override var effectiveDuration: CFTimeInterval { duration > 0 ? duration : settlingDuration }

    /// Spring position as a fraction of the way from 0 to 1 at time `t`.
    func fraction(at t: CGFloat) -> CGFloat {
        let omega = (stiffness / mass).squareRoot()
        let zeta = damping / (2 * (stiffness * mass).squareRoot())
        let v0 = initialVelocity
        if zeta < 1 {
            let wd = omega * (1 - zeta * zeta).squareRoot()
            let e = exp(-zeta * omega * t)
            let a = -1.0
            let b = (v0 - zeta * omega) / wd
            return 1 + e * (a * cos(wd * t) + b * sin(wd * t))
        } else if zeta == 1 {
            let e = exp(-omega * t)
            return 1 + e * (-1 + (v0 - omega) * t)
        } else {
            let s1 = -omega * (zeta - (zeta * zeta - 1).squareRoot())
            let s2 = -omega * (zeta + (zeta * zeta - 1).squareRoot())
            let c2 = (v0 + s1) / (s1 - s2) * -1
            let c1 = -1 - c2
            return 1 + c1 * exp(s1 * t) + c2 * exp(s2 * t)
        }
    }

    override func applyValue(to presentation: CALayer, model: CALayer, localTime t: CFTimeInterval) {
        guard let keyPath else { return }
        let modelValue = model._value(forKeyPath: keyPath)
        var from = fromValue, to = toValue
        if from == nil { from = byValue != nil && to != nil ? CAInterpolation.subtract(to, byValue) : modelValue }
        if to == nil { to = byValue != nil ? CAInterpolation.add(from, byValue) : modelValue }
        let f = fraction(at: CGFloat(min(t, effectiveDuration)))
        write(CAInterpolation.lerp(from, to, f), to: presentation)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/caanimationgroup
@MainActor
open class CAAnimationGroup: CAAnimation {
    open var animations: [CAAnimation]?

    public required init() { super.init() }

    override func copyInto(_ c: CAAnimation) {
        super.copyInto(c)
        (c as? CAAnimationGroup)?.animations = animations?.map { $0._copy() }
    }

    override var effectiveDuration: CFTimeInterval {
        if duration > 0 { return duration }
        return animations?.map { ($0.beginTime) + ($0.activeDuration ?? 0.25) }.max() ?? 0.25
    }

    override func applyValue(to presentation: CALayer, model: CALayer, localTime t: CFTimeInterval) {
        for a in animations ?? [] {
            // Children's beginTime is relative to the group.
            a.addedAt = 0
            a.apply(to: presentation, model: model, parentTime: t)
        }
    }
}

public struct CATransitionType: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fade = CATransitionType(rawValue: "fade")
    public static let moveIn = CATransitionType(rawValue: "moveIn")
    public static let push = CATransitionType(rawValue: "push")
    public static let reveal = CATransitionType(rawValue: "reveal")
}

public struct CATransitionSubtype: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fromRight = CATransitionSubtype(rawValue: "fromRight")
    public static let fromLeft = CATransitionSubtype(rawValue: "fromLeft")
    public static let fromTop = CATransitionSubtype(rawValue: "fromTop")
    public static let fromBottom = CATransitionSubtype(rawValue: "fromBottom")
}

/// Transitions are accepted but rendered as an opacity fade of the new content.
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/catransition
@MainActor
open class CATransition: CAAnimation {
    open var type: CATransitionType = .fade
    open var subtype: CATransitionSubtype?
    open var startProgress: Float = 0
    open var endProgress: Float = 1
    open var filter: Any?

    public required init() { super.init() }

    override func applyValue(to presentation: CALayer, model: CALayer, localTime t: CFTimeInterval) {
        let p = progress(localTime: t)
        presentation.opacity = model.opacity * p
    }
}

public struct CAValueFunctionName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let rotateX = CAValueFunctionName(rawValue: "rotateX")
    public static let rotateY = CAValueFunctionName(rawValue: "rotateY")
    public static let rotateZ = CAValueFunctionName(rawValue: "rotateZ")
    public static let scale = CAValueFunctionName(rawValue: "scale")
    public static let scaleX = CAValueFunctionName(rawValue: "scaleX")
    public static let scaleY = CAValueFunctionName(rawValue: "scaleY")
    public static let scaleZ = CAValueFunctionName(rawValue: "scaleZ")
    public static let translate = CAValueFunctionName(rawValue: "translate")
    public static let translateX = CAValueFunctionName(rawValue: "translateX")
    public static let translateY = CAValueFunctionName(rawValue: "translateY")
    public static let translateZ = CAValueFunctionName(rawValue: "translateZ")
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cavaluefunction
open class CAValueFunction: NSObject {
    public let name: CAValueFunctionName
    public init?(name: CAValueFunctionName) { self.name = name }
}

public struct CAFrameRateRange: Equatable, Sendable {
    public var minimum: Float
    public var maximum: Float
    public var preferred: Float
    public init(minimum: Float = 0, maximum: Float = 0, preferred: Float = 0) {
        self.minimum = minimum; self.maximum = maximum; self.preferred = preferred
    }
    public static let `default` = CAFrameRateRange()
}

// MARK: - Value interpolation

@MainActor
enum CAInterpolation {
    static func number(_ v: Any?) -> CGFloat? {
        switch v {
        case let x as CGFloat: return x
        case let x as Double: return CGFloat(x)
        case let x as Float: return CGFloat(x)
        case let x as Int: return CGFloat(x)
        case let x as NSNumber: return CGFloat(x.doubleValue)
        default: return nil
        }
    }

    static func rgba(_ c: CGColor) -> [CGFloat] {
        #if os(Windows) || os(Linux)
        let (r, g, b, a) = c.rgba
        return [r, g, b, a]
        #else
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let conv = c.converted(to: space, intent: .defaultIntent, options: nil) ?? c
        let comps = conv.components ?? [0, 0, 0, 1]
        if comps.count >= 4 { return Array(comps[0..<4]) }
        if comps.count == 2 { return [comps[0], comps[0], comps[0], comps[1]] }
        return [0, 0, 0, 1]
        #endif
    }

    static func color(_ c: [CGFloat]) -> CGColor {
        CGColor(srgbRed: max(0, min(1, c[0])), green: max(0, min(1, c[1])), blue: max(0, min(1, c[2])), alpha: max(0, min(1, c[3])))
    }

    static func asPath(_ v: Any?) -> CGPath? {
        guard let v else { return nil }
        #if os(Windows) || os(Linux)
        return v as? CGPath
        #else
        if CFGetTypeID(v as CFTypeRef) == CGPath.typeID { return (v as! CGPath) }
        return nil
        #endif
    }

    static func asColor(_ v: Any?) -> CGColor? {
        guard let v else { return nil }
        #if os(Windows) || os(Linux)
        return v as? CGColor
        #else
        if CFGetTypeID(v as CFTypeRef) == CGColor.typeID { return (v as! CGColor) }
        return nil
        #endif
    }

    static func lerp(_ a: Any?, _ b: Any?, _ t: CGFloat) -> Any? {
        if t <= 0 { return a ?? b }
        if t >= 1 { return b ?? a }
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        if let x = number(a), let y = number(b) { return mix(x, y) }
        switch (a, b) {
        case let (p as CGPoint, q as CGPoint): return CGPoint(x: mix(p.x, q.x), y: mix(p.y, q.y))
        case let (p as CGSize, q as CGSize): return CGSize(width: mix(p.width, q.width), height: mix(p.height, q.height))
        case let (p as CGRect, q as CGRect):
            return CGRect(x: mix(p.minX, q.minX), y: mix(p.minY, q.minY), width: mix(p.width, q.width), height: mix(p.height, q.height))
        case let (p as CATransform3D, q as CATransform3D):
            var r = p
            let pr = p.rows, qr = q.rows
            r.rows = (0..<4).map { i in (0..<4).map { j in mix(pr[i][j], qr[i][j]) } }
            return r
        case let (p as CGAffineTransform, q as CGAffineTransform):
            return CGAffineTransform(a: mix(p.a, q.a), b: mix(p.b, q.b), c: mix(p.c, q.c), d: mix(p.d, q.d), tx: mix(p.tx, q.tx), ty: mix(p.ty, q.ty))
        case let (p as Bool, q as Bool): return t < 0.5 ? p : q
        default: break
        }
        if let p = asColor(a), let q = asColor(b) {
            let x = rgba(p), y = rgba(q)
            return color((0..<4).map { mix(x[$0], y[$0]) })
        }
        return t < 0.5 ? a : b
    }

    static func add(_ a: Any?, _ b: Any?) -> Any? {
        if let x = number(a), let y = number(b) { return x + y }
        switch (a, b) {
        case let (p as CGPoint, q as CGPoint): return CGPoint(x: p.x + q.x, y: p.y + q.y)
        case let (p as CGSize, q as CGSize): return CGSize(width: p.width + q.width, height: p.height + q.height)
        case let (p as CGRect, q as CGRect): return CGRect(x: p.minX + q.minX, y: p.minY + q.minY, width: p.width + q.width, height: p.height + q.height)
        case let (p as CATransform3D, q as CATransform3D): return CATransform3DConcat(q, p)
        default: return b ?? a
        }
    }

    static func subtract(_ a: Any?, _ b: Any?) -> Any? {
        if let x = number(a), let y = number(b) { return x - y }
        switch (a, b) {
        case let (p as CGPoint, q as CGPoint): return CGPoint(x: p.x - q.x, y: p.y - q.y)
        case let (p as CGSize, q as CGSize): return CGSize(width: p.width - q.width, height: p.height - q.height)
        case let (p as CGRect, q as CGRect): return CGRect(x: p.minX - q.minX, y: p.minY - q.minY, width: p.width - q.width, height: p.height - q.height)
        case let (p as CATransform3D, q as CATransform3D): return CATransform3DConcat(CATransform3DInvert(q), p)
        default: return a
        }
    }

    static func zero(like v: Any?) -> Any? {
        if number(v) != nil { return CGFloat(0) }
        switch v {
        case is CGPoint: return CGPoint.zero
        case is CGSize: return CGSize.zero
        case is CGRect: return CGRect.zero
        case is CATransform3D: return CATransform3DIdentity
        default: return v
        }
    }

    /// Flattens a path into evenly spaced sample points for keyframe paths.
    static func points(along path: CGPath) -> [CGPoint] {
        var pts: [CGPoint] = []
        var current = CGPoint.zero, start = CGPoint.zero
        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint: current = e.points[0]; start = current; pts.append(current)
            case .addLineToPoint: current = e.points[0]; pts.append(current)
            case .addQuadCurveToPoint:
                let c = e.points[0], p = e.points[1]
                for i in 1...8 {
                    let t = CGFloat(i) / 8, mt = 1 - t
                    let w0 = mt * mt, w1 = 2 * mt * t, w2 = t * t
                    let x = w0 * current.x + w1 * c.x + w2 * p.x
                    let y = w0 * current.y + w1 * c.y + w2 * p.y
                    pts.append(CGPoint(x: x, y: y))
                }
                current = p
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], p = e.points[2]
                for i in 1...12 {
                    let t = CGFloat(i) / 12, mt = 1 - t
                    let w0 = mt * mt * mt, w1 = 3 * mt * mt * t, w2 = 3 * mt * t * t, w3 = t * t * t
                    let x = w0 * current.x + w1 * c1.x + w2 * c2.x + w3 * p.x
                    let y = w0 * current.y + w1 * c1.y + w2 * c2.y + w3 * p.y
                    pts.append(CGPoint(x: x, y: y))
                }
                current = p
            case .closeSubpath: current = start; pts.append(current)
            @unknown default: break
            }
        }
        return pts
    }
}
