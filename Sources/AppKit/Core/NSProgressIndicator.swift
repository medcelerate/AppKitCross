// NSProgressIndicator (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A bar or a spinner, determinate or not. The indeterminate animation (the bar's
// sweeping highlight, the spinner's turning spokes) advances on a `CADisplayLink`, so
// the platform schedules frames only while something is animating; tests advance it
// with `_advanceAnimation(by:)`.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator
@MainActor open class NSProgressIndicator: NSView, NSAccessibilityProgressIndicator, NSAccessibilityGroup {
    // MARK: Storage
    private var _style: NSProgressIndicator.Style = .bar
    private var _controlSize: NSControl.ControlSize = .regular
    private var _controlTint: NSControlTint = .defaultControlTint
    private var _minValue: Double = 0
    private var _maxValue: Double = 100
    private var _doubleValue: Double = 0
    private var _isIndeterminate = true
    private var _isBezeled = true
    private var _isDisplayedWhenStopped = true
    private var _usesThreadedAnimation = false
    private var _observedProgress: Progress? = nil
    private var _link: CADisplayLink? = nil
    private var _lastTick: CFTimeInterval = 0

    /// Progress of the indeterminate animation, 0 ..< 1 (one sweep or one turn).
    internal private(set) var _animationPhase: Double = 0
    /// True between `startAnimation` and `stopAnimation`.
    internal private(set) var _isAnimating = false

    /// Seconds per sweep of the bar's highlight and per turn of the spinner.
    internal static let sweepDuration: TimeInterval = 1.5
    internal static let turnDuration: TimeInterval = 1.0

    @MainActor public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    /// The fraction of the range the value covers, 0 ... 1.
    internal var _fraction: Double {
        let span = _maxValue - _minValue
        guard span > 0 else { return 0 }
        return min(max((_doubleValue - _minValue) / span, 0), 1)
    }

    // MARK: Animation

    private func _startLink() {
        guard _link == nil else { return }
        _lastTick = 0
        let link = CADisplayLink { [weak self] link in
            guard let self else { return }
            let now = link.timestamp
            let dt = self._lastTick > 0 ? now - self._lastTick : link.duration
            self._lastTick = now
            self._advanceAnimation(by: dt)
        }
        link.add(to: .main, forMode: .common)
        _link = link
    }

    private func _stopLink() {
        _link?.invalidate()
        _link = nil
    }

    /// Advances the indeterminate animation by `seconds` and redraws; also refreshes the
    /// value from `observedProgress` while one is set.
    @MainActor internal func _advanceAnimation(by seconds: TimeInterval) {
        if let p = _observedProgress { _take(from: p) }
        guard _isAnimating, _isIndeterminate else { return }
        let period = _style == .spinning ? NSProgressIndicator.turnDuration : NSProgressIndicator.sweepDuration
        _animationPhase = (_animationPhase + seconds / period).truncatingRemainder(dividingBy: 1)
        if _animationPhase < 0 { _animationPhase += 1 }
        needsDisplay = true
    }

    private func _take(from progress: Progress) {
        let fraction = progress.fractionCompleted
        let value = _minValue + (_maxValue - _minValue) * min(max(fraction, 0), 1)
        if value != _doubleValue {
            _doubleValue = value
            needsDisplay = true
            _accessibilityValueChanged()
        }
        let indeterminate = progress.isIndeterminate
        if indeterminate != _isIndeterminate { _isIndeterminate = indeterminate; needsDisplay = true }
    }

    /// Frames run only while the indicator can be seen: an animating indicator whose window
    /// closed or ordered out kept its display link, invalidating a view nothing shows on
    /// every tick and keeping the frame clock running for good.
    private func _updateLink() {
        let needsFrames = (_isAnimating && _isIndeterminate) || _observedProgress != nil
        let visible = window?.isVisible ?? false
        if needsFrames && visible { _startLink() } else { _stopLink() }
    }
    @MainActor open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _updateLink()
    }
    override func _windowVisibilityDidChange(_ visible: Bool) {
        super._windowVisibilityDidChange(visible)
        _updateLink()
    }

    // MARK: Drawing

    /// Bar track thickness and spinner diameter per control size.
    internal var _barThickness: CGFloat {
        switch _controlSize { case .small: return 4; case .mini: return 3; default: return 6 }
    }
    internal var _spinnerDiameter: CGFloat {
        switch _controlSize { case .small: return 16; case .mini: return 12; case .large: return 40; default: return 32 }
    }

    /// The track the bar draws in: centred vertically, the full width.
    internal func _barRect() -> NSRect {
        let t = _barThickness
        return NSRect(x: bounds.minX, y: bounds.midY - t / 2, width: bounds.width, height: t)
    }
    /// The square the spinner draws in: centred in the bounds.
    internal func _spinnerRect() -> NSRect {
        let d = min(_spinnerDiameter, bounds.width, bounds.height)
        return NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        if !_isAnimating && !_isDisplayedWhenStopped { return }
        switch _style {
        case .bar: _drawBar()
        case .spinning: _drawSpinner()
        }
    }

    private func _drawBar() {
        let track = _barRect()
        guard track.width > 0 else { return }
        let r = track.height / 2
        if _isBezeled {
            NSColor.scrollBarColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: track, xRadius: r, yRadius: r).fill()
        }
        let fill = _tintColor
        if _isIndeterminate {
            guard _isAnimating || _isDisplayedWhenStopped else { return }
            // A highlight a third of the track wide sweeps left to right (right to left
            // in right-to-left layout), fading at both ends.
            let w = max(track.height * 2, track.width / 3)
            let travel = track.width + w
            var x = track.minX - w + CGFloat(_animationPhase) * travel
            if userInterfaceLayoutDirection == .rightToLeft { x = track.maxX - (x - track.minX) - w }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: track, xRadius: r, yRadius: r).addClip()
            fill.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: track.minY, width: w, height: track.height), xRadius: r, yRadius: r).fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            var filled = track
            filled.size.width = track.width * CGFloat(_fraction)
            if userInterfaceLayoutDirection == .rightToLeft { filled.origin.x = track.maxX - filled.width }
            fill.setFill()
            NSBezierPath(roundedRect: filled, xRadius: r, yRadius: r).fill()
        }
    }

    private func _drawSpinner() {
        let box = _spinnerRect()
        guard box.width > 0 else { return }
        let centre = NSPoint(x: box.midX, y: box.midY)
        let radius = box.width / 2
        if _isIndeterminate {
            // Twelve spokes; the one at the phase is brightest, the others fade behind it.
            let spokes = 12
            let lead = Int((_animationPhase * Double(spokes)).rounded(.down)) % spokes
            let flipped = isFlipped
            for i in 0..<spokes {
                let age = (i - lead + spokes) % spokes          // 0 = brightest
                let alpha = 0.15 + 0.85 * (1 - Double(age) / Double(spokes))
                // Spokes run clockwise from twelve o'clock.
                let angle = CGFloat.pi / 2 - CGFloat(i) * 2 * .pi / CGFloat(spokes)
                let dy: CGFloat = flipped ? -1 : 1
                let inner = NSPoint(x: centre.x + cos(angle) * radius * 0.55, y: centre.y + dy * sin(angle) * radius * 0.55)
                let outer = NSPoint(x: centre.x + cos(angle) * radius * 0.95, y: centre.y + dy * sin(angle) * radius * 0.95)
                let p = NSBezierPath()
                p.move(to: inner)
                p.line(to: outer)
                p.lineWidth = max(1.5, radius / 6)
                p.lineCapStyle = .round
                NSColor.secondaryLabelColor.withAlphaComponent(CGFloat(alpha)).setStroke()
                p.stroke()
            }
        } else {
            // A pie: the ring is the track, the wedge from twelve o'clock is the value.
            let ring = NSBezierPath(ovalIn: box.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setStroke()
            ring.stroke()
            let f = CGFloat(_fraction)
            guard f > 0 else { return }
            let wedge = NSBezierPath()
            wedge.move(to: centre)
            // Angles in degrees, clockwise from twelve o'clock (the path's y grows upwards unless flipped).
            let start: CGFloat = 90
            let end: CGFloat = 90 - 360 * f
            if isFlipped { wedge.appendArc(withCenter: centre, radius: radius - 2, startAngle: -start, endAngle: -end, clockwise: false) }
            else { wedge.appendArc(withCenter: centre, radius: radius - 2, startAngle: start, endAngle: end, clockwise: true) }
            wedge.close()
            _tintColor.setFill()
            wedge.fill()
        }
    }

    private var _tintColor: NSColor { NSColor.controlAccentColor }

    @MainActor open override var intrinsicContentSize: NSSize {
        switch _style {
        case .spinning: let d = _spinnerDiameter; return NSSize(width: d, height: d)
        case .bar: return NSSize(width: NSView.noIntrinsicMetric, height: _barFrameHeight)
        }
    }
    private var _barFrameHeight: CGFloat {
        switch _controlSize { case .small: return 12; case .mini: return 10; default: return 20 }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/controlsize
    @MainActor open var controlSize: NSControl.ControlSize {
        get { _controlSize }
        set { _controlSize = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/controltint
    @MainActor open var controlTint: NSControlTint {
        get { _controlTint }
        set { _controlTint = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/doublevalue
    @MainActor open var doubleValue: Double {
        get { _doubleValue }
        set {
            let v = min(max(newValue, _minValue), _maxValue)
            guard v != _doubleValue else { return }
            _doubleValue = v
            needsDisplay = true
            _accessibilityValueChanged()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/increment(by:)
    @MainActor open func increment(by delta: Double) { doubleValue = _doubleValue + delta }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/isbezeled
    @MainActor open var isBezeled: Bool {
        get { _isBezeled }
        set { _isBezeled = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/isdisplayedwhenstopped
    @MainActor open var isDisplayedWhenStopped: Bool {
        get { _isDisplayedWhenStopped }
        set { _isDisplayedWhenStopped = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/isindeterminate
    @MainActor open var isIndeterminate: Bool {
        get { _isIndeterminate }
        set { _isIndeterminate = newValue; _updateLink(); needsDisplay = true; _accessibilityValueChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/maxvalue
    @MainActor open var maxValue: Double {
        get { _maxValue }
        set { _maxValue = newValue; if _doubleValue > newValue { _doubleValue = newValue }; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/minvalue
    @MainActor open var minValue: Double {
        get { _minValue }
        set { _minValue = newValue; if _doubleValue < newValue { _doubleValue = newValue }; needsDisplay = true }
    }
    /// The value follows the progress object's `fractionCompleted` (read on each frame
    /// while set; KVO is not available on every platform) and its `isIndeterminate`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/observedprogress
    @available(macOS 14.0, *)
    @MainActor open var observedProgress: Progress? {
        get { _observedProgress }
        set {
            _observedProgress = newValue
            if let p = newValue { _take(from: p) }
            _updateLink()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/sizetofit()
    @MainActor open func sizeToFit() {
        switch _style {
        case .spinning: setFrameSize(intrinsicContentSize)
        case .bar: setFrameSize(NSSize(width: frame.width, height: _barFrameHeight))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/startanimation(_:)
    @MainActor open func startAnimation(_ sender: Any?) {
        guard !_isAnimating else { return }
        _isAnimating = true
        _updateLink()
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/stopanimation(_:)
    @MainActor open func stopAnimation(_ sender: Any?) {
        guard _isAnimating else { return }
        _isAnimating = false
        _updateLink()
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/style
    @MainActor open var style: NSProgressIndicator.Style {
        get { _style }
        set { _style = newValue; invalidateIntrinsicContentSize(); needsDisplay = true; _accessibilityStructureChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsprogressindicator/usesthreadedanimation
    @MainActor open var usesThreadedAnimation: Bool {
        get { _usesThreadedAnimation }
        set { _usesThreadedAnimation = newValue }
    }
    // MARK: Accessibility (ADR-0013)
    //
    // AXProgressIndicator with the value and its range; an indeterminate spinner is
    // AXBusyIndicator and has no value.
    open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? (_style == .spinning && _isIndeterminate ? .busyIndicator : .progressIndicator) }
    open override func accessibilityLabel() -> String? { _a11y.label ?? toolTip }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : (_isIndeterminate ? nil : _doubleValue) }
    open override func accessibilityMinValue() -> Any? { _a11y.minValue ?? minValue }
    open override func accessibilityMaxValue() -> Any? { _a11y.maxValue ?? maxValue }
    // Requirement of NSAccessibilityProgressIndicator
    open func accessibilityValue() -> NSNumber? { _isIndeterminate ? nil : NSNumber(value: _doubleValue) }
}
