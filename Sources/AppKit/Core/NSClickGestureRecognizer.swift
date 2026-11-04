// NSClickGestureRecognizer: a discrete gesture that recognizes a number of clicks of the
// buttons in `buttonMask` without the mouse moving away between press and release.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclickgesturerecognizer
@available(macOS 10.10, *)
@MainActor open class NSClickGestureRecognizer: NSGestureRecognizer {
    private var _buttonMask = 0x1
    private var _numberOfClicksRequired = 1
    private var _numberOfTouchesRequired = 1
    private var _downPoint: NSPoint?
    /// Movement allowed between press and release before the click fails.
    private let _slop: CGFloat = 4

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclickgesturerecognizer/buttonmask
    @MainActor open var buttonMask: Int { get { _buttonMask } set { _buttonMask = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsclickgesturerecognizer/numberofclicksrequired
    @MainActor open var numberOfClicksRequired: Int { get { _numberOfClicksRequired } set { _numberOfClicksRequired = max(1, newValue) } }
    @available(macOS 10.12, *)
    @MainActor open var numberOfTouchesRequired: Int { get { _numberOfTouchesRequired } set { _numberOfTouchesRequired = newValue } }

    open override func reset() { _downPoint = nil }

    private func _down(_ event: NSEvent) {
        guard _NSGestureButtons.mask(for: event) & _buttonMask != 0 else { return }
        _downPoint = event.locationInWindow
    }
    private func _drag(_ event: NSEvent) {
        guard let p = _downPoint else { return }
        let d = event.locationInWindow
        if abs(d.x - p.x) > _slop || abs(d.y - p.y) > _slop { _downPoint = nil; state = .failed }
    }
    private func _up(_ event: NSEvent) {
        guard _downPoint != nil, _NSGestureButtons.mask(for: event) & _buttonMask != 0 else { return }
        _downPoint = nil
        guard event.clickCount >= _numberOfClicksRequired, _mayBegin() else {
            if event.clickCount > _numberOfClicksRequired { state = .failed }
            return
        }
        // Discrete gesture: possible → recognized (ended) in one step.
        state = .ended
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
