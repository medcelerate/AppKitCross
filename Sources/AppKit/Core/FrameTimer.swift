// A delay or repeat driven by the frame clock (ADR-0021).
//
// Controls that need "after a pause" (the search field's typing delay, the token field's
// completion delay) or "again and again while held" (the stepper's and the date picker's
// autorepeat) run on a `CADisplayLink` rather than a Foundation `Timer`: every backend
// schedules frames for running display links (that is how the indeterminate progress
// bar turns on Windows), while RunLoop timers are serviced only between frames and were
// not firing on Win32 during a held press. Tests drive it through `CARuntime.tick()`
// with `CARuntime.now` overridden, or call `_fire()` directly.

import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

@MainActor
internal final class _NSFrameTimer {
    private var link: CADisplayLink?
    private var remaining: TimeInterval
    private let interval: TimeInterval?
    private let action: @MainActor () -> Void

    /// Fires `action` after `delay`, then (with an `interval`) every `interval` seconds
    /// until invalidated.
    init(delay: TimeInterval, interval: TimeInterval? = nil, action: @escaping @MainActor () -> Void) {
        remaining = delay
        self.interval = interval
        self.action = action
        let l = CADisplayLink { [weak self] link in self?._advance(by: link.duration) }
        l.add(to: .main, forMode: .default)
        link = l
    }

    var isValid: Bool { link != nil }

    /// Advances the timer's clock by `seconds` (one frame's worth from the display link).
    func _advance(by seconds: TimeInterval) {
        guard link != nil else { return }
        remaining -= max(0, seconds)
        guard remaining <= 0 else { return }
        _fire()
    }

    /// Fires now: the action runs, and a repeating timer rearms for its interval.
    func _fire() {
        guard link != nil else { return }
        if let interval {
            remaining = interval
            action()
        } else {
            invalidate()
            action()
        }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}
