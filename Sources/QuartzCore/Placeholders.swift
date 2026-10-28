// QuartzCore on Windows: Milestone 4 implements the CALayer tree over DirectComposition.
// Until then these declarations keep AppKit's layer-related API signatures compilable;
// AppKit does not create layers (NSView.wantsLayer is recorded but has no effect).

import Foundation

open class CALayer: NSObject {
    public override init() { super.init() }
    open var bounds: CGRect = .zero
    open var frame: CGRect = .zero
    open var position: CGPoint = .zero
    open var isHidden = false
    open var opacity: Float = 1
    open var contentsScale: CGFloat = 1
    open weak var superlayer: CALayer?
    open var sublayers: [CALayer]?
    open var name: String?
    open func addSublayer(_ layer: CALayer) {
        layer.superlayer = self
        sublayers = (sublayers ?? []) + [layer]
    }
    open func removeFromSuperlayer() {
        superlayer?.sublayers?.removeAll { $0 === self }
        superlayer = nil
    }
    open func setNeedsDisplay() {}
    open func setNeedsLayout() {}
    open func display() {}
    open func layoutSublayers() {}
}

open class CAOpenGLLayer: CALayer {}

public final class CAMediaTimingFunction: NSObject {
    public let controlPoints: [Float]
    public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {
        controlPoints = [c1x, c1y, c2x, c2y]
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

/// Display-synchronised timer. Milestone 3 drives it from DXGI vblank; until then it
/// exists only as a type.
open class CADisplayLink: NSObject {
    open var isPaused = false
    open var timestamp: TimeInterval = 0
    open var duration: TimeInterval = 1.0 / 60.0
    open func invalidate() {}
}
