// NSRotationGestureRecognizer: a continuous two-finger rotation. `rotation` is the
// accumulated angle in radians (counterclockwise positive, as AppKit reports it);
// `NSEvent.rotation` carries each event's change in degrees.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrotationgesturerecognizer
@available(macOS 10.10, *)
@MainActor open class NSRotationGestureRecognizer: NSGestureRecognizer {
    private var _rotation: CGFloat = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrotationgesturerecognizer/rotation
    @MainActor open var rotation: CGFloat { get { _rotation } set { _rotation = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsrotationgesturerecognizer/rotationindegrees
    @MainActor open var rotationInDegrees: CGFloat {
        get { _rotation * 180 / .pi }
        set { _rotation = newValue * .pi / 180 }
    }

    open override func reset() { _rotation = 0 }

    open override func rotate(with event: NSEvent) {
        let delta = CGFloat(event.rotation) * .pi / 180
        if state == .possible {
            guard _mayBegin() else { state = .failed; return }
            _rotation = delta
            state = .began
        } else {
            _rotation += delta
            state = .changed
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { _finish(event) }
    }

    internal override func _endGesture(with event: NSEvent) { _finish(event) }

    private func _finish(_ event: NSEvent) {
        guard state == .began || state == .changed else { return }
        state = event.phase.contains(.cancelled) ? .cancelled : .ended
    }
}
