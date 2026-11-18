// NSSwitch (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The macOS toggle switch: a pill track with a knob that slides between off and on
// (animated on Core Animation's clock), drawn per appearance; a click or Space toggles
// it and sends the action; dragging the knob past the middle sets the state. AXCheckBox
// with the AXSwitch subrole (UIA Button with the Toggle pattern, AT-SPI toggle button).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsswitch
@available(macOS 10.15, *)
@MainActor open class NSSwitch: NSControl, NSAccessibilitySwitch, NSAccessibilityButton {
    // MARK: Storage
    private var _state: NSControl.StateValue = .off
    private var _tracking = false
    private var _trackingInside = false
    private var _dragStart: NSPoint? = nil
    private var _dragged = false
    /// 0 (off) … 1 (on): where the knob is drawn; animates towards the state.
    private var _knob: CGFloat = 0
    private var _animation: _NSSwitchKnobAnimation? = nil

    /// How long the knob takes to slide; 0 jumps (tests). Not part of Apple's API.
    public static var _animationDuration: TimeInterval = 0.2

    /// The action and target live in a plain action cell, as on other controls.
    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSActionCell(textCell: "") }

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if frameRect.isEmpty { setFrameSize(intrinsicContentSize) }
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsswitch/state
    @MainActor open var state: NSControl.StateValue {
        get { _state }
        set { _setState(newValue, animated: false) }
    }

    private func _setState(_ value: NSControl.StateValue, animated: Bool) {
        let v: NSControl.StateValue = value == .off ? .off : .on
        let changed = v != _state
        _state = v
        _cell?.state = v
        let target: CGFloat = v == .on ? 1 : 0
        if animated, NSSwitch._animationDuration > 0, _knob != target {
            _animation?.finish()
            let a = _NSSwitchKnobAnimation(from: _knob, to: target, duration: NSSwitch._animationDuration) { [weak self] k in
                self?._knob = k
                self?.needsDisplay = true
            }
            _animation = a
            a.start()
        } else {
            _animation?.finish()
            _animation = nil
            _knob = target
        }
        needsDisplay = true
        if changed { _accessibilityValueChanged() }
    }

    /// Flips the state (animated) and sends the action, as a click does.
    @MainActor open override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        _setState(_state == .on ? .off : .on, animated: true)
        _fireAction()
    }

    // MARK: Geometry

    /// The track size for the control size (regular 38×22, small 32×18, mini 26×15).
    internal var _trackSize: NSSize {
        switch controlSize {
        case .mini: return NSSize(width: 26, height: 15)
        case .small: return NSSize(width: 32, height: 18)
        default: return NSSize(width: 38, height: 22)
        }
    }
    @MainActor open override var intrinsicContentSize: NSSize { _trackSize }
    @MainActor open override func sizeToFit() { setFrameSize(_trackSize) }
    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder }

    /// The track, centred in the bounds.
    internal var _trackRect: NSRect {
        let s = _trackSize
        return NSRect(x: (bounds.midX - s.width / 2).rounded(), y: (bounds.midY - s.height / 2).rounded(), width: s.width, height: s.height)
    }
    /// The knob for a knob position (0 off … 1 on).
    internal func _knobRect(at position: CGFloat) -> NSRect {
        let t = _trackRect
        let inset: CGFloat = 2
        let d = t.height - 2 * inset
        let travel = t.width - 2 * inset - d
        let x = userInterfaceLayoutDirection == .rightToLeft ? t.maxX - inset - d - travel * position : t.minX + inset + travel * position
        return NSRect(x: x, y: t.minY + inset, width: d, height: d)
    }

    // MARK: Drawing

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        let t = _trackRect
        let on = _knob
        let enabled = isEnabled
        let dark = effectiveAppearance.isDark
        // Track: the accent colour blended in as the knob travels, over a grey track.
        let off: NSColor = dark ? NSColor(white: 1, alpha: 0.2) : NSColor(white: 0, alpha: 0.09)
        let accent: NSColor = .controlAccentColor
        let track = NSBezierPath(roundedRect: t, xRadius: t.height / 2, yRadius: t.height / 2)
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor.white).setFill()
        track.fill()
        off.withAlphaComponent(off.alphaComponent * (enabled ? 1 : 0.5)).setFill()
        track.fill()
        if on > 0 {
            accent.withAlphaComponent((isHighlighted && _trackingInside ? 0.85 : 1) * on * (enabled ? 1 : 0.5)).setFill()
            track.fill()
        }
        (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.08)).setStroke()
        let border = NSBezierPath(roundedRect: t.insetBy(dx: 0.5, dy: 0.5), xRadius: t.height / 2, yRadius: t.height / 2)
        border.lineWidth = 1
        border.stroke()
        // Knob: white with a soft edge; pressed, it stretches a little towards the far side.
        var k = _knobRect(at: on)
        if isHighlighted && _trackingInside {
            let stretch = k.width * 0.2
            if (on < 0.5) != (userInterfaceLayoutDirection == .rightToLeft) { k.size.width += stretch } else { k.origin.x -= stretch; k.size.width += stretch }
        }
        let knob = NSBezierPath(roundedRect: k, xRadius: k.height / 2, yRadius: k.height / 2)
        NSColor(white: 0, alpha: enabled ? 0.18 : 0.08).setFill()
        NSBezierPath(roundedRect: k.offsetBy(dx: 0, dy: isFlipped ? 1 : -1).insetBy(dx: -0.5, dy: -0.5), xRadius: k.height / 2 + 0.5, yRadius: k.height / 2 + 0.5).fill()
        (enabled ? NSColor.white : NSColor(white: 1, alpha: 0.7)).setFill()
        knob.fill()
    }

    // MARK: Mouse and keyboard

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        _tracking = true
        _trackingInside = true
        _dragStart = convert(event.locationInWindow, from: nil)
        _dragged = false
        isHighlighted = true
    }
    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _tracking, let start = _dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        let inside = bounds.insetBy(dx: -8, dy: -8).contains(p)
        if inside != _trackingInside { _trackingInside = inside; needsDisplay = true }
        let dx = p.x - start.x
        if abs(dx) >= 3 {
            // Dragging the knob: it follows the pointer along the track.
            _dragged = true
            let t = _trackRect
            let travel = max(1, t.width - t.height)
            let base: CGFloat = _state == .on ? 1 : 0
            let dir: CGFloat = userInterfaceLayoutDirection == .rightToLeft ? -1 : 1
            _animation?.finish()
            _animation = nil
            _knob = min(1, max(0, base + dir * dx / travel))
            needsDisplay = true
        }
    }
    @MainActor open override func mouseUp(with event: NSEvent) {
        guard _tracking else { return }
        _tracking = false
        isHighlighted = false
        let p = convert(event.locationInWindow, from: nil)
        let inside = bounds.insetBy(dx: -8, dy: -8).contains(p)
        _dragStart = nil
        if _dragged {
            // The knob lands on the side it was dragged to.
            let wanted: NSControl.StateValue = _knob >= 0.5 ? .on : .off
            let changed = wanted != _state
            _setState(wanted, animated: true)
            if changed { _fireAction() }
        } else if inside {
            performClick(self)
        }
        _dragged = false
    }
    @MainActor open override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { performClick(self); return }
        super.keyDown(with: event)
    }

    // MARK: Accessibility (ADR-0013)
    //
    // A check box with the switch subrole: UIA's Toggle pattern on a Button, AT-SPI's
    // toggle button with the checked state.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .checkBox }
    open override func accessibilitySubrole() -> NSAccessibility.Subrole? { _a11y.subrole ?? .switch }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : state.rawValue }
    // Requirement of NSAccessibilitySwitch
    open func accessibilityValue() -> String? { String(state.rawValue) }
    override func _accessibilityValueIsSettable() -> Bool { true }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard let d = value.doubleValue else { return false }
        let wanted: NSControl.StateValue = d == 0 ? .off : .on
        if state != wanted { performClick(nil) }
        return state == wanted
    }
    open override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isHiddenOrHasHiddenAncestor else { return false }
        performClick(nil)
        return true
    }
}

/// Slides the knob from one position to the other on a `CADisplayLink` over
/// `CARuntime.now` (tests drive it with a fake clock and `CARuntime.tick()`).
@MainActor final class _NSSwitchKnobAnimation {
    private let from: CGFloat, to: CGFloat
    private let duration: TimeInterval
    private let apply: (CGFloat) -> Void
    private var startTime: CFTimeInterval = 0
    private var link: CADisplayLink? = nil
    private var finished = false

    init(from: CGFloat, to: CGFloat, duration: TimeInterval, apply: @escaping (CGFloat) -> Void) {
        self.from = from; self.to = to; self.duration = duration; self.apply = apply
    }
    func start() {
        startTime = CARuntime.now()
        apply(from)
        let l = CADisplayLink { [weak self] _ in self?.step() }
        link = l
        l.add(to: .main, forMode: .default)
    }
    private func step() {
        let t = min(1, max(0, (CARuntime.now() - startTime) / duration))
        let eased = CGFloat(1 - (1 - t) * (1 - t))
        apply(from + (to - from) * eased)
        if t >= 1 { finish() }
    }
    func finish() {
        guard !finished else { return }
        finished = true
        link?.invalidate()
        link = nil
        apply(to)
    }
}
