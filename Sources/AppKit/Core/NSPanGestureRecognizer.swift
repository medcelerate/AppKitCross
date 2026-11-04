// NSPanGestureRecognizer: a continuous drag with a button in `buttonMask`. The gesture
// begins once the mouse has moved past a small threshold and reports the translation
// from the press point, plus a velocity in points per second.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspangesturerecognizer
@available(macOS 10.10, *)
@MainActor open class NSPanGestureRecognizer: NSGestureRecognizer {
    private var _buttonMask = 0x1
    private var _numberOfTouchesRequired = 1
    private var _downPoint: NSPoint?
    private var _translation = NSPoint.zero       // window space, y up
    private var _origin = NSPoint.zero            // window point translation is measured from
    private var _lastPoint = NSPoint.zero
    private var _lastTime: TimeInterval = 0
    private var _velocity = NSPoint.zero
    private let _threshold: CGFloat = 3

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspangesturerecognizer/buttonmask
    @MainActor open var buttonMask: Int { get { _buttonMask } set { _buttonMask = newValue } }
    @available(macOS 10.12, *)
    @MainActor open var numberOfTouchesRequired: Int { get { _numberOfTouchesRequired } set { _numberOfTouchesRequired = newValue } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspangesturerecognizer/translation(in:)
    @MainActor open func translation(in view: NSView?) -> NSPoint {
        guard let view else { return _translation }
        let a = view.convert(_origin, from: nil)
        let b = view.convert(NSPoint(x: _origin.x + _translation.x, y: _origin.y + _translation.y), from: nil)
        return NSPoint(x: b.x - a.x, y: b.y - a.y)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspangesturerecognizer/settranslation(_:in:)
    @MainActor open func setTranslation(_ translation: NSPoint, in view: NSView?) {
        if let view {
            let a = view.convert(NSPoint.zero, to: nil)
            let b = view.convert(translation, to: nil)
            _translation = NSPoint(x: b.x - a.x, y: b.y - a.y)
        } else {
            _translation = translation
        }
        _origin = NSPoint(x: _lastPoint.x - _translation.x, y: _lastPoint.y - _translation.y)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspangesturerecognizer/velocity(in:)
    @MainActor open func velocity(in view: NSView?) -> NSPoint {
        guard let view, view.isFlipped else { return _velocity }
        return NSPoint(x: _velocity.x, y: -_velocity.y)
    }

    open override func reset() {
        _downPoint = nil
        _translation = .zero
        _velocity = .zero
    }

    private func _down(_ event: NSEvent) {
        guard _NSGestureButtons.mask(for: event) & _buttonMask != 0 else { return }
        _downPoint = event.locationInWindow
        _origin = event.locationInWindow
        _lastPoint = event.locationInWindow
        _lastTime = event.timestamp
        _translation = .zero
        _velocity = .zero
    }
    private func _drag(_ event: NSEvent) {
        guard let start = _downPoint, _NSGestureButtons.mask(for: event) & _buttonMask != 0 else { return }
        let p = event.locationInWindow
        let dt = event.timestamp - _lastTime
        if dt > 0 { _velocity = NSPoint(x: (p.x - _lastPoint.x) / dt, y: (p.y - _lastPoint.y) / dt) }
        _lastPoint = p
        _lastTime = event.timestamp
        if state == .possible {
            guard abs(p.x - start.x) > _threshold || abs(p.y - start.y) > _threshold else { return }
            guard _mayBegin() else { _downPoint = nil; state = .failed; return }
            _translation = NSPoint(x: p.x - _origin.x, y: p.y - _origin.y)
            state = .began
        } else {
            _translation = NSPoint(x: p.x - _origin.x, y: p.y - _origin.y)
            state = .changed
        }
    }
    private func _up(_ event: NSEvent) {
        guard _downPoint != nil, _NSGestureButtons.mask(for: event) & _buttonMask != 0 else { return }
        let p = event.locationInWindow
        _lastPoint = p
        if state == .began || state == .changed {
            _translation = NSPoint(x: p.x - _origin.x, y: p.y - _origin.y)
            state = .ended
        } else {
            _downPoint = nil
            state = .failed
        }
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
