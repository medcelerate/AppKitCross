// NSSlider (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider
@MainActor open class NSSlider: NSControl, NSAccessibilitySlider {
    private var _tracking = false
    private var _trackFillColor: NSColor? = nil
    private var _neutralValue: Double = 0

    internal var _sliderCell: NSSliderCell? { _cell as? NSSliderCell }

    @MainActor open override class func _makeDefaultCell() -> NSCell? {
        let c = NSSliderCell(textCell: "")
        c.isContinuous = true
        return c
    }

    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder }

    @MainActor private func _set(_ value: Double, send: Bool) {
        let clamped = min(max(value, minValue), maxValue)
        guard clamped != doubleValue else { return }
        doubleValue = clamped
        needsDisplay = true
        if send { _fireAction() }
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell = _sliderCell else { return }
        _tracking = true
        cell.isHighlighted = true
        _set(cell._value(at: convert(event.locationInWindow, from: nil), in: bounds, flipped: isFlipped), send: isContinuous)
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _tracking, let cell = _sliderCell else { return }
        _set(cell._value(at: convert(event.locationInWindow, from: nil), in: bounds, flipped: isFlipped), send: isContinuous)
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        guard _tracking else { return }
        _tracking = false
        _sliderCell?.isHighlighted = false
        needsDisplay = true
        if !isContinuous { _fireAction() } else { _fireAction() }
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        let step = altIncrementValue > 0 ? altIncrementValue : (maxValue - minValue) / 10
        switch event.charactersIgnoringModifiers {
        case "\u{F702}", "\u{F701}": _set(doubleValue - step, send: true)      // left / down
        case "\u{F703}", "\u{F700}": _set(doubleValue + step, send: true)      // right / up
        case "\u{F729}": _set(minValue, send: true)
        case "\u{F72B}": _set(maxValue, send: true)
        default: super.keyDown(with: event)
        }
    }

    @MainActor open override var intrinsicContentSize: NSSize { _sliderCell?.cellSize ?? super.intrinsicContentSize }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/init(target:action:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(target: Any?, action: Selector?) {
        self.init(frame: NSRect(x: 0, y: 0, width: 100, height: 21))
        self.target = target as AnyObject?
        self.action = action
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/init(value:minvalue:maxvalue:target:action:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(value: Double, minValue: Double, maxValue: Double, target: Any?, action: Selector?) {
        self.init(target: target, action: action)
        self.minValue = minValue
        self.maxValue = maxValue
        doubleValue = value
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/acceptsfirstmouse(for:)
    @MainActor open override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/allowstickmarkvaluesonly
    @MainActor open var allowsTickMarkValuesOnly: Bool {
        get { _sliderCell?.allowsTickMarkValuesOnly ?? false }
        set { _sliderCell?.allowsTickMarkValuesOnly = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/altincrementvalue
    @MainActor open var altIncrementValue: Double {
        get { _sliderCell?.altIncrementValue ?? -1 }
        set { _sliderCell?.altIncrementValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/closesttickmarkvalue(tovalue:)
    @MainActor open func closestTickMarkValue(toValue value: Double) -> Double { _sliderCell?.closestTickMarkValue(toValue: value) ?? value }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/indexoftickmark(at:)
    @MainActor open func indexOfTickMark(at point: NSPoint) -> Int { _sliderCell?.indexOfTickMark(at: point) ?? NSNotFound }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/knobthickness
    @MainActor open var knobThickness: CGFloat {
        get { _sliderCell?.knobThickness ?? 15 }
        set { _sliderCell?.knobThickness = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/maxvalue
    @MainActor open var maxValue: Double {
        get { _sliderCell?.maxValue ?? 1 }
        set { _sliderCell?.maxValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/minvalue
    @MainActor open var minValue: Double {
        get { _sliderCell?.minValue ?? 0 }
        set { _sliderCell?.minValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/neutralvalue
    @available(macOS 26.0, *)
    @MainActor open var neutralValue: Double {
        get { _neutralValue }
        set { _neutralValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/numberoftickmarks
    @MainActor open var numberOfTickMarks: Int {
        get { _sliderCell?.numberOfTickMarks ?? 0 }
        set { _sliderCell?.numberOfTickMarks = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/rectoftickmark(at:)
    @MainActor open func rectOfTickMark(at index: Int) -> NSRect { _sliderCell?.rectOfTickMark(at: index) ?? .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/slidertype
    @available(macOS 10.10, *)
    @MainActor open var sliderType: NSSlider.SliderType {
        get { _sliderCell?.sliderType ?? .linear }
        set { _sliderCell?.sliderType = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/tickmarkposition
    @MainActor open var tickMarkPosition: NSSlider.TickMarkPosition {
        get { _sliderCell?.tickMarkPosition ?? .below }
        set { _sliderCell?.tickMarkPosition = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/tickmarkvalue(at:)
    @MainActor open func tickMarkValue(at index: Int) -> Double { _sliderCell?.tickMarkValue(at: index) ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/tintprominence
    @available(macOS 26.0, *)
    @MainActor open var tintProminence: NSTintProminence {
        get { .automatic }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/trackfillcolor
    @available(macOS 10.12, *)
    @MainActor open var trackFillColor: NSColor? {
        get { _trackFillColor }
        set { _trackFillColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslider/vertical
    @available(macOS 10.12, *)
    open var vertical: Bool {
        get { MainActor.assumeIsolated { _sliderCell?.vertical ?? false } }
        set { MainActor.assumeIsolated { _sliderCell?.vertical = newValue; needsDisplay = true } }
    }
    // DUPLICATE: open var vertical: Bool
    // MARK: Accessibility (ADR-0013)
    //
    // AXSlider: the value, its range, and increment/decrement by a tick (or a
    // hundredth of the range), each sending the action as a drag would.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .slider }
    open func accessibilityOrientation() -> NSAccessibilityOrientation { vertical ? .vertical : .horizontal }
    // Requirement of NSAccessibilitySlider
    open override func accessibilityLabel() -> String? { _a11y.label ?? toolTip }
    // Requirement of NSAccessibilitySlider
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : doubleValue }
    open override func accessibilityMinValue() -> Any? { _a11y.minValue ?? minValue }
    open override func accessibilityMaxValue() -> Any? { _a11y.maxValue ?? maxValue }
    override func _accessibilityValueIsSettable() -> Bool { isEnabled }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard isEnabled, let d = value.doubleValue else { return false }
        _accessibilityApply(d)
        return true
    }
    /// The step one increment moves: the alternate increment when one is set (SwiftUI's
    /// `step`), a tick mark's spacing, else a hundredth of the range.
    internal var _accessibilityStep: Double {
        if altIncrementValue > 0 { return altIncrementValue }
        let range = maxValue - minValue
        if numberOfTickMarks > 1 { return range / Double(numberOfTickMarks - 1) }
        return range > 0 ? range / 100 : 1
    }
    private func _accessibilityApply(_ value: Double) {
        let clamped = min(max(value, minValue), maxValue)
        guard clamped != doubleValue else { return }
        doubleValue = clamped
        _fireAction()
    }
    // Requirement of NSAccessibilitySlider
    open override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        _accessibilityApply(doubleValue + _accessibilityStep)
        return true
    }
    // Requirement of NSAccessibilitySlider
    open override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        _accessibilityApply(doubleValue - _accessibilityStep)
        return true
    }
}
