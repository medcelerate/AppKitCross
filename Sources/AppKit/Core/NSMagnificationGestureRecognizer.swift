// NSMagnificationGestureRecognizer: a continuous pinch. `magnification` accumulates the
// per-event changes AppKit reports in `NSEvent.magnification` (0 at the start of a
// gesture; 1 means the content has doubled). The gesture begins on the first magnify
// event, continues with each one, and ends with the platform's end-of-gesture event (or
// the event whose phase is ended).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmagnificationgesturerecognizer
@available(macOS 10.10, *)
@MainActor open class NSMagnificationGestureRecognizer: NSGestureRecognizer {
    private var _magnification: CGFloat = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmagnificationgesturerecognizer/magnification
    @MainActor open var magnification: CGFloat { get { _magnification } set { _magnification = newValue } }

    open override func reset() { _magnification = 0 }

    open override func magnify(with event: NSEvent) {
        if state == .possible {
            guard _mayBegin() else { state = .failed; return }
            _magnification = event.magnification
            state = .began
        } else {
            _magnification += event.magnification
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
