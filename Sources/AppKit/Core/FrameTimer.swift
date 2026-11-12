// A delay or repeat driven by the frame clock (ADR-0021).
//
// Controls that need "after a pause" (the search field's typing delay, the token field's
// completion delay) or "again and again while held" (the stepper's and the date picker's
// autorepeat) run on a `CADisplayLink` rather than a Foundation `Timer`: every backend
// schedules frames for running display links (that is how the indeterminate progress
// bar turns on Windows), while RunLoop timers are serviced only between frames and were
// not firing on Win32 during a held press. Tests drive it through `CARuntime.tick()`
// with `CARuntime.now` overridden, or call `_fire()` directly.
//
// Like a run-loop timer, a repeat fires once per frame at most: a frame that arrives late
// (the Win32 pump was busy) fires the one repeat that is due and the next one is the next
// scheduled time after it, so a slow stretch is skipped rather than made up in a burst.

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
        lastTime = CACurrentMediaTime()
        // The timer keeps its own clock from the moment it was made (a link's first frame
        // reports a nominal duration, not the time since the link was added).
        let l = CADisplayLink { [weak self] link in
            guard let self else { return }
            let now = link.timestamp
            let elapsed = now - self.lastTime
            self.lastTime = now
            self._advance(by: elapsed)
        }
        l.add(to: .main, forMode: .default)
        link = l
    }
    private var lastTime: CFTimeInterval

    var isValid: Bool { link != nil }

    /// Advances the timer's clock by `seconds` (one frame's worth from the display link).
    /// The timing is by elapsed time, not by frames; a frame fires at most one repeat.
    func _advance(by seconds: TimeInterval) {
        guard link != nil else { return }
        remaining -= max(0, seconds)
        if remaining <= 0 { _fire() }
    }

    /// Fires now: the action runs, and a repeating timer rearms for the next scheduled
    /// time after now (from the moment it was due, so frames a little late do not stretch
    /// the rate; intervals a very late frame covered are skipped, as `Timer` skips them).
    func _fire() {
        guard link != nil else { return }
        if let interval {
            remaining += interval
            if remaining <= 0 { remaining = interval + remaining.truncatingRemainder(dividingBy: interval) }
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
