// NSDatePicker (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The control over an `NSDatePickerCell`. Textual styles: a click selects a field,
// Left/Right move between fields, Up/Down (and the stepper) step the selected one,
// digits type into it. The graphical style: a click picks a day (Shift extends the range),
// the arrows page the month, a drag turns a clock hand; arrows move by a day or a week.
// Every change sends the action.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker
@MainActor open class NSDatePicker: NSControl {
    internal var _dateCell: NSDatePickerCell? { _cell as? NSDatePickerCell }
    private var _presentsCalendarOverlay = false
    private var _stepperRepeat: _NSFrameTimer? = nil
    private var _stepperDirection = 0

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSDatePickerCell(textCell: "") }

    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder }

    @MainActor open override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let c = _dateCell, c.datePickerStyle != .clockAndCalendar, c._selectedField < 0 { c._selectFirstField() }
        needsDisplay = true
        return true
    }
    @MainActor open override func resignFirstResponder() -> Bool {
        _dateCell?._typedDigits = ""
        needsDisplay = true
        return super.resignFirstResponder()
    }

    @MainActor private func _changed(_ did: Bool) {
        guard did else { return }
        needsDisplay = true
        _accessibilityValueChanged()
        _fireAction()
    }

    // MARK: Mouse

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell = _dateCell else { super.mouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if window?.firstResponder !== self { _ = window?.makeFirstResponder(self) }
        if cell.datePickerStyle == .clockAndCalendar {
            let page = cell._pageDirection(at: p, in: _cellFrame, flipped: isFlipped)
            if page != 0 { cell._pageMonth(page); needsDisplay = true; return }
            if let day = cell._day(at: p, in: _cellFrame, flipped: isFlipped) {
                _changed(cell._choose(day: day, extending: event.modifierFlags.contains(.shift)))
                return
            }
            if let hand = cell._hand(at: p, in: _cellFrame) {
                cell._draggingHand = hand
                _changed(cell._drag(hand: hand, to: p, in: _cellFrame, flipped: isFlipped))
            }
            return
        }
        let stepper = cell._stepperRect(forBounds: _cellFrame)
        if stepper.contains(p) {
            let dir = cell._stepper._direction(at: p, in: stepper, flipped: isFlipped)
            guard dir != 0 else { return }
            cell._stepper._pressedDirection = dir
            _stepperDirection = dir
            needsDisplay = true
            _changed(cell._stepSelectedField(dir))
            _scheduleStepperRepeat(after: NSStepper.autorepeatDelay)
            return
        }
        let fields = cell._layoutFields(in: _cellFrame)
        if let i = fields.firstIndex(where: { $0.isEditable && $0.rect.contains(p) }) {
            cell._selectedField = i
            cell._typedDigits = ""
            needsDisplay = true
        }
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard let cell = _dateCell, let hand = cell._draggingHand else { return }
        _changed(cell._drag(hand: hand, to: convert(event.locationInWindow, from: nil), in: _cellFrame, flipped: isFlipped))
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        _dateCell?._draggingHand = nil
        _stepperRepeat?.invalidate()
        _stepperRepeat = nil
        _stepperDirection = 0
        _dateCell?._stepper._pressedDirection = 0
        needsDisplay = true
    }

    /// The stepper's repeat on the frame clock, as `NSStepper`'s.
    private func _scheduleStepperRepeat(after delay: TimeInterval) {
        _stepperRepeat?.invalidate()
        _stepperRepeat = _NSFrameTimer(delay: delay, interval: NSStepper.autorepeatInterval) { [weak self] in self?._stepperRepeatFired() }
    }
    @MainActor internal func _stepperRepeatFired() {
        guard _stepperDirection != 0, let cell = _dateCell else { return }
        _changed(cell._stepSelectedField(_stepperDirection))
    }

    // MARK: Keyboard

    @MainActor open override func keyDown(with event: NSEvent) {
        guard isEnabled, let cell = _dateCell else { super.keyDown(with: event); return }
        let chars = event.charactersIgnoringModifiers ?? ""
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        if cell.datePickerStyle == .clockAndCalendar {
            let cal = cell._effectiveCalendar
            var delta: (Calendar.Component, Int)? = nil
            switch chars {
            case "\u{F702}": delta = (.day, rtl ? 1 : -1)
            case "\u{F703}": delta = (.day, rtl ? -1 : 1)
            case "\u{F700}": delta = (.day, -7)
            case "\u{F701}": delta = (.day, 7)
            case "\u{F72C}": delta = (.month, -1)     // page up
            case "\u{F72D}": delta = (.month, 1)      // page down
            default: super.keyDown(with: event); return
            }
            if let (comp, n) = delta, let d = cal.date(byAdding: comp, value: n, to: cell.dateValue) {
                _changed(cell._propose(d))
            }
            return
        }
        switch chars {
        case "\u{F702}": if rtl { cell._selectNextField() } else { cell._selectPreviousField() }; needsDisplay = true
        case "\u{F703}": if rtl { cell._selectPreviousField() } else { cell._selectNextField() }; needsDisplay = true
        case "\u{F700}": _changed(cell._stepSelectedField(1))
        case "\u{F701}": _changed(cell._stepSelectedField(-1))
        case "\u{7F}", "\u{8}":
            cell._typedDigits = ""
        default:
            if let ch = chars.first, cell._selectedField >= 0, !event.modifierFlags.contains(.command) {
                let before = cell.dateValue
                if cell._type(ch) { _changed(cell.dateValue != before); needsDisplay = true; return }
            }
            super.keyDown(with: event)
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _dateCell?.backgroundColor ?? .textBackgroundColor }
        set { _dateCell?.backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/calendar
    @MainActor open var calendar: Calendar? {
        get { _dateCell?.calendar }
        set { _dateCell?.calendar = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/datepickerelements
    @MainActor open var datePickerElements: NSDatePicker.ElementFlags {
        get { _dateCell?.datePickerElements ?? [] }
        set { _dateCell?.datePickerElements = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/datepickermode
    @MainActor open var datePickerMode: NSDatePicker.Mode {
        get { _dateCell?.datePickerMode ?? .single }
        set { _dateCell?.datePickerMode = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/datepickerstyle
    @MainActor open var datePickerStyle: NSDatePicker.Style {
        get { _dateCell?.datePickerStyle ?? .textFieldAndStepper }
        set { _dateCell?.datePickerStyle = newValue; invalidateIntrinsicContentSize(); needsDisplay = true; _accessibilityStructureChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/datevalue
    @MainActor open var dateValue: Date {
        get { _dateCell?.dateValue ?? Date() }
        set { _dateCell?.dateValue = newValue; needsDisplay = true; _accessibilityValueChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/delegate
    @MainActor open var delegate: (any NSDatePickerCellDelegate)? {
        get { _dateCell?.delegate }
        set { _dateCell?.delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _dateCell?.drawsBackground ?? false }
        set { _dateCell?.drawsBackground = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/isbezeled
    @MainActor open var isBezeled: Bool {
        get { _cell?.isBezeled ?? false }
        set { _cell?.isBezeled = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/isbordered
    @MainActor open var isBordered: Bool {
        get { _cell?.isBordered ?? false }
        set { _cell?.isBordered = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/locale
    @MainActor open var locale: Locale? {
        get { _dateCell?.locale }
        set { _dateCell?.locale = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/maxdate
    @MainActor open var maxDate: Date? {
        get { _dateCell?.maxDate }
        set { _dateCell?.maxDate = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/mindate
    @MainActor open var minDate: Date? {
        get { _dateCell?.minDate }
        set { _dateCell?.minDate = newValue; needsDisplay = true }
    }
    /// The calendar overlay of the textual styles is not provided: the flag is stored.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/presentscalendaroverlay
    @available(macOS 10.15, *)
    @MainActor open var presentsCalendarOverlay: Bool {
        get { _presentsCalendarOverlay }
        set { _presentsCalendarOverlay = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/textcolor
    @MainActor open var textColor: NSColor {
        get { _dateCell?.textColor ?? .textColor }
        set { _dateCell?.textColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/timeinterval
    @MainActor open var timeInterval: TimeInterval {
        get { _dateCell?.timeInterval ?? 0 }
        set { _dateCell?.timeInterval = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepicker/timezone
    @MainActor open var timeZone: TimeZone? {
        get { _dateCell?.timeZone }
        set { _dateCell?.timeZone = newValue; needsDisplay = true }
    }
    // MARK: Accessibility (ADR-0013)
    //
    // AXDateTimeArea whose value is the date as the field shows it; increment and
    // decrement step the selected field (the day in the graphical style).
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .dateTimeAreaRole }
    open override func accessibilityLabel() -> String? { _a11y.label ?? toolTip }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : stringValue }
    override func _accessibilityValueIsSettable() -> Bool { isEnabled }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard isEnabled, let cell = _dateCell else { return false }
        let before = cell.dateValue
        cell.stringValue = value.stringValue
        guard cell.dateValue != before else { return false }
        _changed(true)
        return true
    }
    open override func accessibilityPerformIncrement() -> Bool { _accessibilityStep(1) }
    open override func accessibilityPerformDecrement() -> Bool { _accessibilityStep(-1) }
    private func _accessibilityStep(_ delta: Int) -> Bool {
        guard isEnabled, let cell = _dateCell else { return false }
        if cell.datePickerStyle == .clockAndCalendar {
            guard let d = cell._effectiveCalendar.date(byAdding: .day, value: delta, to: cell.dateValue) else { return false }
            _changed(cell._propose(d))
            return true
        }
        if cell._selectedField < 0 { cell._selectFirstField() }
        _changed(cell._stepSelectedField(delta))
        return true
    }
}
