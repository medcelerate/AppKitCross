// NSLevelIndicator (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The control over an `NSLevelIndicatorCell`: read-only unless `isEditable`, in which
// case a click or drag sets the value under the pointer and Left/Right step it.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator
@MainActor open class NSLevelIndicator: NSControl {
    internal var _levelCell: NSLevelIndicatorCell? { _cell as? NSLevelIndicatorCell }
    private var _tracking = false

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSLevelIndicatorCell(levelIndicatorStyle: .discreteCapacity) }

    @MainActor open override var acceptsFirstResponder: Bool { isEditable && isEnabled && !refusesFirstResponder }

    @MainActor private func _set(_ value: Double) {
        let clamped = min(max(value, minValue), maxValue)
        guard clamped != doubleValue else { return }
        doubleValue = clamped
        _fireAction()
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, isEditable, let cell = _levelCell else { super.mouseDown(with: event); return }
        _tracking = true
        _set(cell._value(at: convert(event.locationInWindow, from: nil), in: _cellFrame, rightToLeft: userInterfaceLayoutDirection == .rightToLeft))
    }
    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _tracking, let cell = _levelCell else { return }
        _set(cell._value(at: convert(event.locationInWindow, from: nil), in: _cellFrame, rightToLeft: userInterfaceLayoutDirection == .rightToLeft))
    }
    @MainActor open override func mouseUp(with event: NSEvent) { _tracking = false }

    /// The step an arrow key (or an accessibility increment) moves: one unit for the
    /// discrete styles, a tenth of the range otherwise.
    internal var _keyStep: Double {
        switch levelIndicatorStyle {
        case .discreteCapacity, .rating: return 1
        default: return (maxValue - minValue) / 10
        }
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        guard isEditable else { super.keyDown(with: event); return }
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        switch event.charactersIgnoringModifiers {
        case "\u{F702}": _set(doubleValue + (rtl ? _keyStep : -_keyStep))    // left
        case "\u{F703}": _set(doubleValue + (rtl ? -_keyStep : _keyStep))    // right
        case "\u{F700}": _set(doubleValue + _keyStep)                        // up
        case "\u{F701}": _set(doubleValue - _keyStep)                        // down
        case "\u{F729}": _set(minValue)
        case "\u{F72B}": _set(maxValue)
        default: super.keyDown(with: event)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/criticalfillcolor
    @available(macOS 10.13, *)
    @MainActor open var criticalFillColor: NSColor! {
        get { _levelCell?._criticalFillColor ?? .systemRed }
        set { _levelCell?._criticalFillColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/criticalvalue
    @MainActor open var criticalValue: Double {
        get { _levelCell?.criticalValue ?? 0 }
        set { _levelCell?.criticalValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/drawstieredcapacitylevels
    @available(macOS 10.13, *)
    @MainActor open var drawsTieredCapacityLevels: Bool {
        get { _levelCell?._drawsTieredCapacityLevels ?? false }
        set { _levelCell?._drawsTieredCapacityLevels = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/fillcolor
    @available(macOS 10.13, *)
    @MainActor open var fillColor: NSColor! {
        get { _levelCell?._fillColor ?? .systemGreen }
        set { _levelCell?._fillColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/iseditable
    @available(macOS 10.13, *)
    @MainActor open var isEditable: Bool {
        get { _levelCell?._editable ?? false }
        set { _levelCell?._editable = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/levelindicatorstyle
    @available(macOS 10.10, *)
    @MainActor open var levelIndicatorStyle: NSLevelIndicator.Style {
        get { _levelCell?.levelIndicatorStyle ?? .discreteCapacity }
        set { _levelCell?.levelIndicatorStyle = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/maxvalue
    @MainActor open var maxValue: Double {
        get { _levelCell?.maxValue ?? 10 }
        set { _levelCell?.maxValue = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/minvalue
    @MainActor open var minValue: Double {
        get { _levelCell?.minValue ?? 0 }
        set { _levelCell?.minValue = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/numberofmajortickmarks
    @MainActor open var numberOfMajorTickMarks: Int {
        get { _levelCell?.numberOfMajorTickMarks ?? 0 }
        set { _levelCell?.numberOfMajorTickMarks = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/numberoftickmarks
    @MainActor open var numberOfTickMarks: Int {
        get { _levelCell?.numberOfTickMarks ?? 0 }
        set { _levelCell?.numberOfTickMarks = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/placeholdervisibility
    @available(macOS 10.13, *)
    @MainActor open var placeholderVisibility: NSLevelIndicator.PlaceholderVisibility {
        get { _levelCell?._placeholderVisibility ?? .automatic }
        set { _levelCell?._placeholderVisibility = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/ratingimage
    @available(macOS 10.13, *)
    @MainActor open var ratingImage: NSImage? {
        get { _levelCell?._ratingImage }
        set { _levelCell?._ratingImage = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/ratingplaceholderimage
    @available(macOS 10.13, *)
    @MainActor open var ratingPlaceholderImage: NSImage? {
        get { _levelCell?._ratingPlaceholderImage }
        set { _levelCell?._ratingPlaceholderImage = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/rectoftickmark(at:)
    @MainActor open func rectOfTickMark(at index: Int) -> NSRect {
        guard let c = _levelCell else { return .zero }
        if c._lastCellFrame.isEmpty { c._lastCellFrame = _cellFrame; c._barRect = c._barRect(forBounds: _cellFrame) }
        return c.rectOfTickMark(at: index)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/tickmarkposition
    @MainActor open var tickMarkPosition: NSSlider.TickMarkPosition {
        get { _levelCell?.tickMarkPosition ?? .below }
        set { _levelCell?.tickMarkPosition = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/tickmarkvalue(at:)
    @MainActor open func tickMarkValue(at index: Int) -> Double { _levelCell?.tickMarkValue(at: index) ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/warningfillcolor
    @available(macOS 10.13, *)
    @MainActor open var warningFillColor: NSColor! {
        get { _levelCell?._warningFillColor ?? .systemYellow }
        set { _levelCell?._warningFillColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicator/warningvalue
    @MainActor open var warningValue: Double {
        get { _levelCell?.warningValue ?? 0 }
        set { _levelCell?.warningValue = newValue; needsDisplay = true }
    }
    // MARK: Accessibility (ADR-0013)
    //
    // AXLevelIndicator with the value and its range; editable indicators take a value
    // and step by increment/decrement.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .levelIndicator }
    open override func accessibilityLabel() -> String? { _a11y.label ?? toolTip }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : doubleValue }
    open override func accessibilityMinValue() -> Any? { _a11y.minValue ?? minValue }
    open override func accessibilityMaxValue() -> Any? { _a11y.maxValue ?? maxValue }
    override func _accessibilityValueIsSettable() -> Bool { isEditable && isEnabled }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard isEditable, isEnabled, let d = value.doubleValue else { return false }
        _set(d)
        return true
    }
    open override func accessibilityPerformIncrement() -> Bool {
        guard isEditable, isEnabled else { return false }
        _set(doubleValue + _keyStep)
        return true
    }
    open override func accessibilityPerformDecrement() -> Bool {
        guard isEditable, isEnabled else { return false }
        _set(doubleValue - _keyStep)
        return true
    }
}
