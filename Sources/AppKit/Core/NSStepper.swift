// NSStepper (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Two stacked arrow buttons over an `NSStepperCell`. A press steps the value once and,
// with `autorepeat`, keeps stepping on a run-loop timer (0.5 s, then every 0.1 s) while
// the mouse stays down over the pressed half; Up and Down arrows step from the keyboard.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstepper
@MainActor open class NSStepper: NSControl, NSAccessibilityStepper {
    internal var _stepperCell: NSStepperCell? { _cell as? NSStepperCell }
    private var _repeatTimer: Timer?
    private var _mouseInsidePressedHalf = false

    /// The delay before the first repeat and the interval between repeats.
    internal static let autorepeatDelay: TimeInterval = 0.5
    internal static let autorepeatInterval: TimeInterval = 0.1

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSStepperCell(textCell: "") }

    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder }
    @MainActor open override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Steps once in `direction` (+1 up, -1 down) and sends the action when the value changed.
    @MainActor internal func _step(_ direction: Int) {
        guard let cell = _stepperCell, direction != 0 else { return }
        let next = cell._stepped(direction)
        guard next != doubleValue else { return }
        doubleValue = next
        _fireAction()
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell = _stepperCell else { return }
        let dir = cell._direction(at: convert(event.locationInWindow, from: nil), in: _cellFrame, flipped: isFlipped)
        guard dir != 0 else { return }
        cell._pressedDirection = dir
        _mouseInsidePressedHalf = true
        needsDisplay = true
        _step(dir)
        if autorepeat { _scheduleRepeat(after: NSStepper.autorepeatDelay) }
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard let cell = _stepperCell, cell._pressedDirection != 0 else { return }
        let dir = cell._direction(at: convert(event.locationInWindow, from: nil), in: _cellFrame, flipped: isFlipped)
        let inside = dir == cell._pressedDirection
        if inside != _mouseInsidePressedHalf {
            _mouseInsidePressedHalf = inside
            needsDisplay = true
        }
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        _endTracking()
    }

    @MainActor private func _endTracking() {
        _repeatTimer?.invalidate()
        _repeatTimer = nil
        _stepperCell?._pressedDirection = 0
        _mouseInsidePressedHalf = false
        needsDisplay = true
    }

    private func _scheduleRepeat(after delay: TimeInterval) {
        _repeatTimer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?._autorepeatFired() }
        }
        RunLoop.main.add(t, forMode: .default)
        _repeatTimer = t
    }

    /// One autorepeat tick: steps again while the mouse is still over the pressed half,
    /// then schedules the next tick.
    @MainActor internal func _autorepeatFired() {
        guard let cell = _stepperCell, cell._pressedDirection != 0 else { return }
        if _mouseInsidePressedHalf { _step(cell._pressedDirection) }
        _scheduleRepeat(after: NSStepper.autorepeatInterval)
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\u{F700}": _step(1)        // up
        case "\u{F701}": _step(-1)       // down
        default: super.keyDown(with: event)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstepper/autorepeat
    @MainActor open var autorepeat: Bool {
        get { _stepperCell?.autorepeat ?? true }
        set { _stepperCell?.autorepeat = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstepper/increment
    @MainActor open var increment: Double {
        get { _stepperCell?.increment ?? 1 }
        set { _stepperCell?.increment = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstepper/maxvalue
    @MainActor open var maxValue: Double {
        get { _stepperCell?.maxValue ?? 59 }
        set { _stepperCell?.maxValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstepper/minvalue
    @MainActor open var minValue: Double {
        get { _stepperCell?.minValue ?? 0 }
        set { _stepperCell?.minValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstepper/valuewraps
    @MainActor open var valueWraps: Bool {
        get { _stepperCell?.valueWraps ?? false }
        set { _stepperCell?.valueWraps = newValue }
    }
    // MARK: Accessibility (ADR-0013)
    //
    // AXIncrementor: the value and its range; increment and decrement step as a click would.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .incrementor }
    open override func accessibilityLabel() -> String? { _a11y.label ?? toolTip }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : doubleValue }
    open override func accessibilityMinValue() -> Any? { _a11y.minValue ?? minValue }
    open override func accessibilityMaxValue() -> Any? { _a11y.maxValue ?? maxValue }
    override func _accessibilityValueIsSettable() -> Bool { isEnabled }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard isEnabled, let d = value.doubleValue else { return false }
        let clamped = min(max(d, minValue), maxValue)
        guard clamped != doubleValue else { return true }
        doubleValue = clamped
        _fireAction()
        return true
    }
    // Requirement of NSAccessibilityStepper
    open override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        _step(1)
        return true
    }
    // Requirement of NSAccessibilityStepper
    open override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        _step(-1)
        return true
    }
}
