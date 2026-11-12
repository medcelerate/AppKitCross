// NSAnimation (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Progress runs from 0 to 1 over `duration` on Core Animation's clock (`CARuntime.now`),
// one step per frame of a `CADisplayLink` like the port's other frame-driven work
// (`_NSFrameTimer`, sheet slides; ADR-0034). Each step sets `currentProgress` (so
// subclasses such as NSViewAnimation apply it by overriding the setter), reports the
// progress marks passed since the last step to the delegate and as notifications, and
// starts or stops the animations linked to those marks.
//
// Blocking mode runs the steps in a loop inside `start()` that also redisplays the
// application's windows, returning when the animation ends: the port has no private
// run-loop mode for it, so other run-loop sources do not run meanwhile. The threaded
// non-blocking mode runs on the main thread's frame clock, as the non-blocking mode does.
// Animations are driven from the main thread.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation
open class NSAnimation: NSObject, NSCopying, NSCoding {
    private var _duration: TimeInterval
    private var _curve: NSAnimation.Curve
    private var _frameRate: Float = 60
    private var _blockingMode: NSAnimation.BlockingMode = .blocking
    private var _progress: NSAnimation.Progress = 0
    private var _marks: [NSAnimation.Progress] = []
    private weak var _delegate: (any NSAnimationDelegate)?

    // Running state.
    private var _running = false
    private var _runStartTime: CFTimeInterval = 0
    private var _runStartProgress: NSAnimation.Progress = 0
    /// Marks at or below this were reported in this run.
    private var _reportedThrough: NSAnimation.Progress = -1
    private var _link: CADisplayLink?

    // Links between animations: this animation starts (stops) when another reaches a mark.
    private struct _Link { weak var source: NSAnimation?; var mark: NSAnimation.Progress }
    private var _startLink: _Link?
    private var _stopLink: _Link?
    /// Animations that start or stop on this one's marks.
    private var _dependents: [_WeakAnimation] = []
    private struct _WeakAnimation { weak var value: NSAnimation? }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/init(duration:animationcurve:)
    public init(duration: TimeInterval, animationCurve: NSAnimation.Curve) {
        _duration = max(0, duration)
        _curve = animationCurve
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/addprogressmark(_:)
    open func addProgressMark(_ progressMark: NSAnimation.Progress) {
        let m = min(max(progressMark, 0), 1)
        guard !_marks.contains(m) else { return }
        _marks.append(m)
        _marks.sort()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/animationblockingmode
    open var animationBlockingMode: NSAnimation.BlockingMode {
        get { _blockingMode }
        set { _blockingMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/animationcurve
    open var animationCurve: NSAnimation.Curve {
        get { _curve }
        set { _curve = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/clearstart()
    open func clearStart() { _startLink = nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/clearstop()
    open func clearStop() { _stopLink = nil }
    /// Setting it moves the animation (subclasses override the setter to apply the
    /// progress); a running animation continues from there.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/currentprogress
    open var currentProgress: NSAnimation.Progress {
        get { _progress }
        set {
            _progress = min(max(newValue, 0), 1)
            if _running && !_stepping {
                _runStartTime = NSAnimation._now()
                _runStartProgress = _progress
            }
        }
    }
    /// The delegate's `animation(_:valueForProgress:)` when there is a delegate, else the
    /// curve's value at the current progress.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/currentvalue
    open var currentValue: Float {
        if let d = delegate { return d.animation(self, valueForProgress: currentProgress) }
        return _curveValue(forProgress: currentProgress)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/delegate
    open var delegate: (any NSAnimationDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/duration
    open var duration: TimeInterval {
        get { _duration }
        set {
            precondition(newValue >= 0, "NSAnimation: negative duration")
            _duration = newValue
            if _running {
                _runStartTime = NSAnimation._now()
                _runStartProgress = _progress
            }
        }
    }
    /// Updates per second; 0 steps on every display frame.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/framerate
    open var frameRate: Float {
        get { _frameRate }
        set {
            precondition(newValue >= 0, "NSAnimation: negative frame rate")
            _frameRate = newValue
            if let link = _link { NSAnimation._onMain { link.preferredFramesPerSecond = Int(newValue.rounded()) } }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/isanimating
    open var isAnimating: Bool { _running }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/progressmarknotification
    static public var progressMarkNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSAnimationProgressMarkNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/progressmarkuserinfokey
    static public var progressMarkUserInfoKey: String { "NSAnimationProgressMark" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/progressmarks
    open var progressMarks: [NSNumber] {
        get { _marks.map { NSNumber(value: $0) } }
        set { _marks = Array(Set(newValue.map { min(max($0.floatValue, 0), 1) })).sorted() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/removeprogressmark(_:)
    open func removeProgressMark(_ progressMark: NSAnimation.Progress) { _marks.removeAll { $0 == progressMark } }
    /// nil: the default, common modes.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/runloopmodesforanimating
    open var runLoopModesForAnimating: [RunLoop.Mode]? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/start()
    open func start() {
        guard !_running else { return }
        if let d = delegate, !d.animationShouldStart(self) { return }
        if _progress >= 1 { _progress = 0; currentProgress = 0 }
        _running = true
        _runStartTime = NSAnimation._now()
        _runStartProgress = _progress
        _reportedThrough = _progress > 0 ? _progress : -1
        if _duration <= 0 {
            _step(at: _runStartTime)
            return
        }
        // A mark at the starting point is reached at once.
        _step(at: _runStartTime)
        guard _running else { return }
        switch _blockingMode {
        case .blocking: _runBlocking()
        case .nonblocking, .nonblockingThreaded: _schedule()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/start(when:reachesprogress:)
    open func start(when animation: NSAnimation, reachesProgress startProgress: NSAnimation.Progress) {
        _startLink = _Link(source: animation, mark: startProgress)
        animation._addDependent(self, mark: startProgress)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/stop()
    open func stop() {
        guard _running else { return }
        _halt()
        delegate?.animationDidStop(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimation/stop(when:reachesprogress:)
    open func stop(when animation: NSAnimation, reachesProgress stopProgress: NSAnimation.Progress) {
        _stopLink = _Link(source: animation, mark: stopProgress)
        animation._addDependent(self, mark: stopProgress)
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSAnimation(duration: _duration, animationCurve: _curve)
        _copySettings(to: c)
        return c
    }
    /// Copies the settings (not the running state, delegate or links) to `copy`.
    internal func _copySettings(to copy: NSAnimation) {
        copy._duration = _duration
        copy._curve = _curve
        copy._frameRate = _frameRate
        copy._blockingMode = _blockingMode
        copy._marks = _marks
        copy._progress = _progress
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }

    // MARK: Curves

    /// The curve's value at `progress`: ease-in-out is a half cosine, ease-in and ease-out
    /// its quarter halves, linear the progress itself. The default for the delegate's
    /// `animation(_:valueForProgress:)`.
    internal func _curveValue(forProgress progress: NSAnimation.Progress) -> Float {
        NSAnimation._value(of: _curve, at: progress)
    }

    internal static func _value(of curve: NSAnimation.Curve, at progress: NSAnimation.Progress) -> Float {
        let p = Double(min(max(progress, 0), 1))
        switch curve {
        case .easeInOut: return Float((1 - cos(p * .pi)) / 2)
        case .easeIn: return Float(1 - cos(p * .pi / 2))
        case .easeOut: return Float(sin(p * .pi / 2))
        case .linear: return Float(p)
        }
    }

    // MARK: Running

    /// Set while a step assigns `currentProgress`, so the setter does not rebase the run.
    private var _stepping = false

    /// The animation is driven from the main thread: frame-clock objects are main-actor.
    private static func _onMain<T>(_ body: @MainActor () -> T) -> T {
        MainActor.assumeIsolated { body() }
    }

    private static func _now() -> CFTimeInterval { _onMain { CARuntime.now() } }

    /// One step at clock time `now`: the progress from the run's start, the marks passed,
    /// the end when progress reaches 1.
    private func _step(at now: CFTimeInterval) {
        guard _running else { return }
        let target: NSAnimation.Progress
        if _duration <= 0 {
            target = 1
        } else {
            let elapsed = max(0, now - _runStartTime)
            target = min(1, _runStartProgress + Float(elapsed / _duration))
        }
        _stepping = true
        currentProgress = target
        _stepping = false
        _reportMarks(through: target)
        guard _running else { return }
        if target >= 1 {
            _halt()
            delegate?.animationDidEnd(self)
        }
    }

    private func _reportMarks(through progress: NSAnimation.Progress) {
        let passed = _marks.filter { $0 > _reportedThrough && $0 <= progress }
        _reportedThrough = max(_reportedThrough, progress)
        for m in passed {
            delegate?.animation(self, didReachProgressMark: m)
            NotificationCenter.default.post(name: NSAnimation.progressMarkNotification, object: self,
                                            userInfo: [NSAnimation.progressMarkUserInfoKey: NSNumber(value: m)])
            _fireLinks(at: m)
            if !_running { return }
        }
    }

    private func _addDependent(_ animation: NSAnimation, mark: NSAnimation.Progress) {
        addProgressMark(mark)
        _dependents.removeAll { $0.value == nil || $0.value === animation }
        _dependents.append(_WeakAnimation(value: animation))
    }

    /// Starts and stops the animations linked to mark `m` of this animation.
    private func _fireLinks(at m: NSAnimation.Progress) {
        for dep in _dependents.compactMap({ $0.value }) {
            if let l = dep._startLink, l.source === self, l.mark == m { dep.start() }
            if let l = dep._stopLink, l.source === self, l.mark == m { dep.stop() }
        }
    }

    private func _schedule() {
        let rate = _frameRate
        _link = NSAnimation._onMain {
            let l = CADisplayLink { [weak self] link in self?._step(at: link.timestamp) }
            l.preferredFramesPerSecond = Int(rate.rounded())
            l.add(to: .main, forMode: .common)
            return l
        }
    }

    /// Steps until the end, redrawing the windows between steps.
    private func _runBlocking() {
        let interval = 1.0 / Double(_frameRate > 0 ? _frameRate : 60)
        while _running {
            Thread.sleep(forTimeInterval: interval)
            _step(at: NSAnimation._now())
            NSAnimation._onMain {
                for w in NSApplication.shared.windows where w.isVisible { w.displayIfNeeded() }
            }
        }
    }

    private func _halt() {
        _running = false
        if let link = _link {
            _link = nil
            NSAnimation._onMain { link.invalidate() }
        }
    }
}
