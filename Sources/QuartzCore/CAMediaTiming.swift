// Media timing: the CAMediaTiming protocol, timing functions, the media clock and the
// host hooks that drive animation frames.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if os(Windows) || os(Linux)
// swift-corelibs-foundation does not export CoreFoundation's CFTimeInterval.
public typealias CFTimeInterval = Double
#endif

/// Seconds on the system's monotonic clock, as Core Animation's `CACurrentMediaTime()`.
/// Tests can substitute a clock through `CARuntime.now`.
@MainActor
public func CACurrentMediaTime() -> CFTimeInterval { CARuntime.now() }

public struct CAMediaTimingFillMode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let forwards = CAMediaTimingFillMode(rawValue: "forwards")
    public static let backwards = CAMediaTimingFillMode(rawValue: "backwards")
    public static let both = CAMediaTimingFillMode(rawValue: "both")
    public static let removed = CAMediaTimingFillMode(rawValue: "removed")
}

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/camediatiming
@MainActor
public protocol CAMediaTiming: AnyObject {
    var beginTime: CFTimeInterval { get set }
    var duration: CFTimeInterval { get set }
    var speed: Float { get set }
    var timeOffset: CFTimeInterval { get set }
    var repeatCount: Float { get set }
    var repeatDuration: CFTimeInterval { get set }
    var autoreverses: Bool { get set }
    var fillMode: CAMediaTimingFillMode { get set }
}

public struct CAMediaTimingFunctionName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = CAMediaTimingFunctionName(rawValue: "linear")
    public static let easeIn = CAMediaTimingFunctionName(rawValue: "easeIn")
    public static let easeOut = CAMediaTimingFunctionName(rawValue: "easeOut")
    public static let easeInEaseOut = CAMediaTimingFunctionName(rawValue: "easeInEaseOut")
    public static let `default` = CAMediaTimingFunctionName(rawValue: "default")
}

/// A cubic Bézier easing curve from (0,0) to (1,1).
/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/camediatimingfunction
open class CAMediaTimingFunction: NSObject {
    private let c1x: Float, c1y: Float, c2x: Float, c2y: Float

    public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {
        self.c1x = c1x; self.c1y = c1y; self.c2x = c2x; self.c2y = c2y
        super.init()
    }

    public convenience init(name: CAMediaTimingFunctionName) {
        switch name {
        case .easeIn: self.init(controlPoints: 0.42, 0, 1, 1)
        case .easeOut: self.init(controlPoints: 0, 0, 0.58, 1)
        case .easeInEaseOut: self.init(controlPoints: 0.42, 0, 0.58, 1)
        case .default: self.init(controlPoints: 0.25, 0.1, 0.25, 1)
        default: self.init(controlPoints: 0, 0, 1, 1)
        }
    }

    /// Copies the control point at `idx` (0...3) into `ptr` (x then y).
    open func getControlPoint(at idx: Int, values ptr: UnsafeMutablePointer<Float>) {
        let pts: [(Float, Float)] = [(0, 0), (c1x, c1y), (c2x, c2y), (1, 1)]
        let p = pts[max(0, min(3, idx))]
        ptr[0] = p.0; ptr[1] = p.1
    }

    /// The control points as [c1x, c1y, c2x, c2y].
    public var controlPoints: [Float] { [c1x, c1y, c2x, c2y] }

    /// Evaluates the curve: progress in 0...1 -> eased value.
    public func evaluate(_ x: Float) -> Float {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if c1x == c1y && c2x == c2y { return x }   // linear
        // Solve the x polynomial for t with Newton iterations, then evaluate y(t).
        func bez(_ t: Float, _ p1: Float, _ p2: Float) -> Float {
            let mt = 1 - t
            return 3 * mt * mt * t * p1 + 3 * mt * t * t * p2 + t * t * t
        }
        func dbez(_ t: Float, _ p1: Float, _ p2: Float) -> Float {
            let mt = 1 - t
            return 3 * mt * mt * p1 + 6 * mt * t * (p2 - p1) + 3 * t * t * (1 - p2)
        }
        var t = x
        for _ in 0..<8 {
            let err = bez(t, c1x, c2x) - x
            if abs(err) < 1e-5 { break }
            let d = dbez(t, c1x, c2x)
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        if t < 0 || t > 1 {
            // Bisection fallback.
            var lo: Float = 0, hi: Float = 1
            for _ in 0..<30 {
                t = (lo + hi) / 2
                if bez(t, c1x, c2x) < x { lo = t } else { hi = t }
            }
        }
        return bez(t, c1y, c2y)
    }
}

/// A weak box for registries.
final class CAWeak<T: AnyObject> {
    weak var value: T?
    init(_ v: T) { value = v }
}

/// Process-wide hooks between QuartzCore and its host (AppKit on Windows, tests on macOS):
/// the clock, how to request an animation frame, and the frame tick that advances
/// display links and redraws animating layer trees.
@MainActor
public enum CARuntime {
    /// The media clock. Tests may replace it with a controllable one.
    public static var now: () -> CFTimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// Installed by the host: schedule one call to `tick()` about a frame from now.
    public static var frameRequester: (() -> Void)? {
        didSet { framePending = false }
    }

    /// Installed by the host: draws a CATextLayer's string into a context whose
    /// coordinate space is the layer's bounds. QuartzCore has no text engine of its own.
    public static var textRenderer: ((CATextLayer, CGContext, Bool) -> Void)?

    static var framePending = false
    static var animatingRoots: [CAWeak<CALayer>] = []
    static var displayLinks: [CAWeak<CADisplayLink>] = []

    /// Asks the host for a frame; coalesced until `tick()` runs.
    public static func requestFrame() {
        guard !framePending, let requester = frameRequester else { return }
        framePending = true
        requester()
    }

    /// True while any layer tree animates or a display link runs.
    public static var hasPendingWork: Bool {
        animatingRoots.contains { $0.value != nil } || displayLinks.contains { ($0.value?.isRunning) == true }
    }

    static func noteAnimating(root: CALayer) {
        animatingRoots.removeAll { $0.value == nil }
        if !animatingRoots.contains(where: { $0.value === root }) { animatingRoots.append(CAWeak(root)) }
        requestFrame()
    }

    /// One animation frame: fire display links, then invalidate every layer tree whose
    /// animations are still running (their hosts redraw them). Requests another frame when
    /// work remains. Hosts call this from the timer `frameRequester` set up.
    public static func tick() {
        framePending = false
        let t = now()
        for box in displayLinks { box.value?._fire(at: t) }
        displayLinks.removeAll { $0.value == nil || $0.value!.isInvalidated }
        var remaining: [CAWeak<CALayer>] = []
        for box in animatingRoots {
            guard let root = box.value else { continue }
            let still = root._advanceAnimations(now: t)
            root._invalidateHost(nil)
            if still { remaining.append(box) }
        }
        animatingRoots = remaining
        if hasPendingWork { requestFrame() }
    }
}
