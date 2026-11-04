// NSPressGestureRecognizer: a press-and-hold. The gesture begins once a button in
// `buttonMask` has been held for `minimumPressDuration` without moving more than
// `allowableMovement`, continues while the mouse moves, and ends on release.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspressgesturerecognizer
@available(macOS 10.10, *)
@MainActor open class NSPressGestureRecognizer: NSGestureRecognizer {
    private var _buttonMask = 0x1
    private var _minimumPressDuration: TimeInterval = 0.5
    private var _allowableMovement: CGFloat = 10
    private var _numberOfTouchesRequired = 1
    private var _downPoint: NSPoint?
    /// Identifies the pending press timer; a reset or a new press invalidates older ones.
    private var _pressGeneration = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspressgesturerecognizer/buttonmask
    @MainActor open var buttonMask: Int { get { _buttonMask } set { _buttonMask = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspressgesturerecognizer/minimumpressduration
    @MainActor open var minimumPressDuration: TimeInterval { get { _minimumPressDuration } set { _minimumPressDuration = max(0, newValue) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspressgesturerecognizer/allowablemovement
    @MainActor open var allowableMovement: CGFloat { get { _allowableMovement } set { _allowableMovement = newValue } }
    @available(macOS 10.12, *)
    @MainActor open var numberOfTouchesRequired: Int { get { _numberOfTouchesRequired } set { _numberOfTouchesRequired = newValue } }

    open override func reset() {
        _downPoint = nil
        _pressGeneration &+= 1
    }

    /// Tests and the timer call this when the press duration has elapsed.
    internal func _pressTimerFired() {
        guard _downPoint != nil, state == .possible else { return }
        guard _mayBegin() else { _downPoint = nil; state = .failed; return }
        state = .began
    }

    private func _down(_ event: NSEvent) {
        guard _NSGestureButtons.mask(for: event) & _buttonMask != 0 else { return }
        _downPoint = event.locationInWindow
        _pressGeneration &+= 1
        if _minimumPressDuration <= 0 {
            _pressTimerFired()
        } else {
            // The main dispatch queue, not a RunLoop timer: every backend's pump wakes for
            // blocks queued on it, which is not guaranteed for Foundation timers on Windows.
            let generation = _pressGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + _minimumPressDuration) { [weak self] in
                guard let self, self._pressGeneration == generation else { return }
                self._pressTimerFired()
            }
        }
    }
    private func _drag(_ event: NSEvent) {
        guard let p = _downPoint else { return }
        let d = event.locationInWindow
        let moved = abs(d.x - p.x) > _allowableMovement || abs(d.y - p.y) > _allowableMovement
        if state == .possible {
            if moved { reset(); state = .failed }
        } else {
            state = .changed
        }
    }
    private func _up(_ event: NSEvent) {
        guard _downPoint != nil, _NSGestureButtons.mask(for: event) & _buttonMask != 0 else { return }
        if state == .began || state == .changed { state = .ended } else { reset(); state = .failed }
    }

    open override func mouseDown(with event: NSEvent) { _down(event) }
    open override func mouseDragged(with event: NSEvent) { _drag(event) }
    open override func mouseUp(with event: NSEvent) { _up(event) }
    open override func rightMouseDown(with event: NSEvent) { _down(event) }
    open override func rightMouseDragged(with event: NSEvent) { _drag(event) }
    open override func rightMouseUp(with event: NSEvent) { _up(event) }
    open override func otherMouseDown(with event: NSEvent) { _down(event) }
    open override func otherMouseDragged(with event: NSEvent) { _drag(event) }
    open override func otherMouseUp(with event: NSEvent) { _up(event) }
}
