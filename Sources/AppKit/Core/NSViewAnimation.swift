// NSViewAnimation (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Each dictionary names a target view or window, optional start and end frames
// (`NSValue(rect:)` or an `NSRect`) and an optional fade effect. The start state is taken
// when the animation first moves; every progress change sets each target's frame (and
// alpha for a fade) from the current value of the curve (ADR-0034). At the end a view whose
// end frame is empty, or that faded out, is hidden; a window is ordered out.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewanimation
open class NSViewAnimation: NSAnimation {
    private var _viewAnimations: [[NSViewAnimation.Key : Any]]

    /// One target's resolved animation.
    private struct _Track {
        enum Target { case view(NSView), window(NSWindow) }
        let target: Target
        let start: NSRect
        let end: NSRect
        let effect: NSViewAnimation.EffectName?
    }
    private var _tracks: [_Track]? = nil

    /// Duration 0.5 seconds, ease-in-out.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewanimation/init(viewanimations:)
    public init(viewAnimations: [[NSViewAnimation.Key : Any]]) {
        _viewAnimations = viewAnimations
        super.init(duration: 0.5, animationCurve: .easeInOut)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewanimation/viewanimations
    open var viewAnimations: [[NSViewAnimation.Key : Any]] {
        get { _viewAnimations }
        set { _viewAnimations = newValue; _tracks = nil }
    }
    // Required by the superclass (NSCoding).
    public required init?(coder: NSCoder) { unimplemented() }

    open override var currentProgress: NSAnimation.Progress {
        get { super.currentProgress }
        set {
            super.currentProgress = newValue
            _apply()
        }
    }

    open override func start() {
        if !isAnimating { _tracks = nil }
        super.start()
    }

    open override func copy(with zone: NSZone? = nil) -> Any {
        let c = NSViewAnimation(viewAnimations: _viewAnimations)
        _copySettings(to: c)
        return c
    }

    // MARK: Applying

    private static func _rect(_ value: Any?) -> NSRect? {
        switch value {
        case let r as NSRect: return r
        case let v as NSValue: return v.rectValue
        default: return nil
        }
    }

    private static func _effect(_ value: Any?) -> NSViewAnimation.EffectName? {
        switch value {
        case let e as NSViewAnimation.EffectName: return e
        case let s as String: return NSViewAnimation.EffectName(rawValue: s)
        case let s as NSString: return NSViewAnimation.EffectName(rawValue: s as String)
        default: return nil
        }
    }

    /// Reads the dictionaries against the targets' current state.
    private func _resolve() -> [_Track] {
        MainActor.assumeIsolated {
            _viewAnimations.compactMap { dict -> _Track? in
                let effect = NSViewAnimation._effect(dict[.effect])
                let target: _Track.Target
                let current: NSRect
                switch dict[.target] {
                case let v as NSView: target = .view(v); current = v.frame
                case let w as NSWindow: target = .window(w); current = w.frame
                default: return nil
                }
                let start = NSViewAnimation._rect(dict[.startFrame]) ?? current
                let end = NSViewAnimation._rect(dict[.endFrame]) ?? start
                return _Track(target: target, start: start, end: end, effect: effect)
            }
        }
    }

    private func _apply() {
        let progress = super.currentProgress
        if _tracks == nil {
            // Nothing to capture before the animation moves.
            if progress <= 0 && !isAnimating { return }
            _tracks = _resolve()
            MainActor.assumeIsolated { _prepare(_tracks ?? []) }
        }
        guard let tracks = _tracks else { return }
        let finished = progress >= 1
        let v = CGFloat(finished ? 1 : currentValue)
        MainActor.assumeIsolated {
            for t in tracks { NSViewAnimation._apply(t, value: v, finished: finished) }
        }
        if finished { _tracks = nil }
    }

    /// Shows the targets that fade in, from transparent.
    @MainActor private func _prepare(_ tracks: [_Track]) {
        for t in tracks where t.effect == .fadeIn {
            switch t.target {
            case .view(let v): v.alphaValue = 0; v.isHidden = false
            case .window(let w): w.alphaValue = 0; if !w.isVisible { w.orderFront(nil) }
            }
        }
    }

    @MainActor private static func _apply(_ t: _Track, value v: CGFloat, finished: Bool) {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * v }
        let frame = NSRect(x: lerp(t.start.minX, t.end.minX), y: lerp(t.start.minY, t.end.minY),
                           width: lerp(t.start.width, t.end.width), height: lerp(t.start.height, t.end.height))
        let alpha: CGFloat? = t.effect == .fadeIn ? v : t.effect == .fadeOut ? 1 - v : nil
        let disappears = finished && (t.effect == .fadeOut || t.end.isEmpty)
        switch t.target {
        case .view(let view):
            if view.frame != frame { view.frame = frame }
            if let alpha { view.alphaValue = alpha }
            if disappears {
                view.isHidden = true
                if t.effect == .fadeOut { view.alphaValue = 1 }
            }
        case .window(let w):
            if w.frame != frame { w.setFrame(frame, display: true) }
            if let alpha { w.alphaValue = alpha }
            if disappears {
                w.orderOut(nil)
                if t.effect == .fadeOut { w.alphaValue = 1 }
            }
        }
    }
}
