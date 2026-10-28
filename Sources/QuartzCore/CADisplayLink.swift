// CADisplayLink: a frame-synchronised callback driven by CARuntime.tick().

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/quartzcore/cadisplaylink
@MainActor
open class CADisplayLink: NSObject {
    private let callback: (CADisplayLink) -> Void
    open var isPaused = false { didSet { if !isPaused { CARuntime.requestFrame() } } }
    open private(set) var timestamp: CFTimeInterval = 0
    open private(set) var targetTimestamp: CFTimeInterval = 0
    open private(set) var duration: CFTimeInterval = 1.0 / 60.0
    open var preferredFramesPerSecond = 0
    open var preferredFrameRateRange = CAFrameRateRange()
    private(set) var isInvalidated = false
    private var scheduled = false
    private var lastFire: CFTimeInterval = 0

    /// Creates a link that calls `callback` each frame once added to a run loop.
    /// AppKit's `displayLink(target:selector:)` wraps selector dispatch in this.
    public init(callback: @escaping (CADisplayLink) -> Void) {
        self.callback = callback
        super.init()
    }

    var isRunning: Bool { scheduled && !isPaused && !isInvalidated }

    open func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        guard !isInvalidated, !scheduled else { return }
        scheduled = true
        CARuntime.displayLinks.append(CAWeak(self))
        CARuntime.requestFrame()
    }

    open func remove(from runloop: RunLoop, forMode mode: RunLoop.Mode) {
        scheduled = false
        CARuntime.displayLinks.removeAll { $0.value === self }
    }

    open func invalidate() {
        isInvalidated = true
        scheduled = false
        CARuntime.displayLinks.removeAll { $0.value === self }
    }

    func _fire(at now: CFTimeInterval) {
        guard isRunning else { return }
        if preferredFramesPerSecond > 0 {
            let interval = 1.0 / CFTimeInterval(preferredFramesPerSecond)
            if lastFire > 0 && now - lastFire < interval * 0.9 { return }
        }
        duration = lastFire > 0 ? now - lastFire : 1.0 / 60.0
        lastFire = now
        timestamp = now
        targetTimestamp = now + duration
        callback(self)
    }
}
