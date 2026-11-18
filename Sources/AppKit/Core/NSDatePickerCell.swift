// NSDatePickerCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The date, its limits and the calendar, locale and time zone it is shown in live here.
// The textual styles lay the date out as the fields of the locale's own pattern (asked
// of DateFormatter for the selected elements), one of which is selected for the keyboard
// and the stepper; the graphical style draws a month calendar and a clock face in the
// cell (ADR-0021).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell
@MainActor open class NSDatePickerCell: NSActionCell {
    // MARK: Storage
    private var _dateValue = Date()
    private var _timeInterval: TimeInterval = 0
    private var _minDate: Date? = nil
    private var _maxDate: Date? = nil
    private var _calendar: Calendar? = nil
    private var _locale: Locale? = nil
    private var _timeZone: TimeZone? = nil
    private var _style: NSDatePicker.Style = .textFieldAndStepper
    private var _mode: NSDatePicker.Mode = .single
    private var _elements: NSDatePicker.ElementFlags = [.yearMonthDay, .hourMinute]
    private var _backgroundColor: NSColor = .textBackgroundColor
    private var _textColorValue: NSColor = .textColor
    private var _drawsBackground = true
    private weak var _delegate: (any NSDatePickerCellDelegate)?

    /// The field the keyboard and stepper act on (textual styles); -1 when none.
    internal var _selectedField = -1
    /// Digits typed into the selected field so far.
    internal var _typedDigits = ""
    /// The stepper drawn by the `textFieldAndStepper` style.
    internal let _stepper = NSStepperCell(textCell: "")
    /// The month the calendar shows (its first day); follows `dateValue` unless the user paged.
    internal var _visibleMonth: Date? = nil
    /// Which clock hand a drag moves.
    internal var _draggingHand: Calendar.Component? = nil

    static let stepperWidth: CGFloat = 15
    static let calendarSize = NSSize(width: 160, height: 150)
    static let clockSize = NSSize(width: 120, height: 150)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _isBezeled = true
        _isEditable = true
        _isContinuous = true
        _objectValue = _dateValue
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/init(coder:)
    public required init(coder: NSCoder) { super.init(coder: coder) }

    private var _picker: NSDatePicker? { _controlView as? NSDatePicker }

    // MARK: Calendar

    /// The calendar used for every computation: the cell's (or the current one) with the
    /// cell's locale and time zone applied.
    internal var _effectiveCalendar: Calendar {
        var c = _calendar ?? Calendar.current
        if let l = _locale { c.locale = l } else if c.locale == nil { c.locale = Locale.current }
        if let tz = _timeZone { c.timeZone = tz }
        return c
    }
    internal var _effectiveLocale: Locale { _locale ?? _effectiveCalendar.locale ?? Locale.current }

    private func _formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = _effectiveCalendar
        f.locale = _effectiveLocale
        f.timeZone = _effectiveCalendar.timeZone
        f.dateFormat = format
        return f
    }

    internal var _showsDate: Bool { !_elements.intersection(.yearMonthDay).isEmpty }
    internal var _showsTime: Bool { !_elements.intersection(.hourMinuteSecond).isEmpty }

    /// The ICU template for the selected elements, in the locale's order.
    internal var _template: String {
        var t = ""
        if _elements.contains(.yearMonthDay) { t += "yMd" } else if _elements.contains(.yearMonth) { t += "yM" }
        if _elements.contains(.era) { t += "G" }
        if _elements.contains(.hourMinuteSecond) { t += "jms" } else if _elements.contains(.hourMinute) { t += "jm" }
        if _elements.contains(.timeZone) { t += "z" }
        return t
    }

    /// The locale's pattern for the template ("M/d/yyyy, h:mm a" in en_US).
    internal var _pattern: String {
        let t = _template
        guard !t.isEmpty else { return "" }
        return DateFormatter.dateFormat(fromTemplate: t, options: 0, locale: _effectiveLocale) ?? t
    }

    /// One run of the pattern: a literal, or a field for a calendar component.
    internal struct Field {
        var format: String
        var component: Calendar.Component?     // nil for literals and display-only runs
        var text: String = ""
        var rect = NSRect.zero
        var isEditable: Bool { component != nil }
    }

    /// The pattern split into fields, with each field's text for the current date.
    internal func _fields() -> [Field] {
        var out: [Field] = []
        var i = _pattern.startIndex
        let p = _pattern
        while i < p.endIndex {
            let ch = p[i]
            if ch == "'" {
                // Quoted literal up to the closing quote ('' is a quote).
                var j = p.index(after: i)
                var lit = ""
                while j < p.endIndex {
                    if p[j] == "'" {
                        let next = p.index(after: j)
                        if next < p.endIndex, p[next] == "'" { lit.append("'"); j = p.index(after: next); continue }
                        break
                    }
                    lit.append(p[j]); j = p.index(after: j)
                }
                out.append(Field(format: "", component: nil, text: lit))
                i = j < p.endIndex ? p.index(after: j) : j
                continue
            }
            if ch.isLetter {
                var j = i
                while j < p.endIndex, p[j] == ch { j = p.index(after: j) }
                let run = String(p[i..<j])
                let comp: Calendar.Component?
                switch ch {
                case "y", "Y", "u": comp = .year
                case "M", "L": comp = .month
                case "d": comp = .day
                case "h", "H", "k", "K", "j": comp = .hour
                case "m": comp = .minute
                case "s": comp = .second
                case "G": comp = .era
                case "a", "b", "B": comp = .hour     // AM/PM: stepping it toggles 12 hours
                default: comp = nil                   // weekday, zone, ...: shown, not edited
                }
                var f = Field(format: run, component: comp)
                f.text = _formatter(run).string(from: _dateValue)
                if ch == "a" || ch == "b" || ch == "B" { f.format = "a" }
                out.append(f)
                i = j
            } else {
                var j = i
                var lit = ""
                while j < p.endIndex, !p[j].isLetter, p[j] != "'" { lit.append(p[j]); j = p.index(after: j) }
                out.append(Field(format: "", component: nil, text: lit))
                i = j
            }
        }
        return out
    }

    internal var _isAmPmField: (Field) -> Bool { { $0.format == "a" } }

    // MARK: Values

    /// Applies a proposed date: clamps to the limits, lets the delegate adjust it, and
    /// records it (with the proposed range when in range mode). Returns true when the
    /// value changed.
    @discardableResult
    @MainActor internal func _propose(_ date: Date, interval: TimeInterval? = nil) -> Bool {
        var d = date
        if let lo = _minDate, d < lo { d = lo }
        if let hi = _maxDate, d > hi { d = hi }
        var ti = interval ?? _timeInterval
        if let delegate = _delegate {
            var nsd = NSDate(timeIntervalSinceReferenceDate: d.timeIntervalSinceReferenceDate)
            withUnsafeMutablePointer(to: &nsd) { ptr in
                withUnsafeMutablePointer(to: &ti) { tptr in
                    delegate.datePickerCell(self, validateProposedDateValue: AutoreleasingUnsafeMutablePointer(ptr), timeInterval: tptr)
                }
            }
            d = Date(timeIntervalSinceReferenceDate: nsd.timeIntervalSinceReferenceDate)
        }
        let changed = d != _dateValue || ti != _timeInterval
        _dateValue = d
        _timeInterval = max(0, ti)
        _objectValue = d
        _visibleMonth = nil
        _changed()
        return changed
    }

    /// Steps the selected field's component by `delta` (AM/PM toggles 12 hours).
    @MainActor internal func _stepSelectedField(_ delta: Int) -> Bool {
        let fields = _fields()
        guard _selectedField >= 0, _selectedField < fields.count, let comp = fields[_selectedField].component else { return false }
        _typedDigits = ""
        let cal = _effectiveCalendar
        if _isAmPmField(fields[_selectedField]) {
            guard let d = cal.date(byAdding: .hour, value: 12 * delta, to: _dateValue) else { return false }
            return _propose(d)
        }
        guard let d = cal.date(byAdding: comp, value: delta, to: _dateValue) else { return false }
        return _propose(d)
    }

    /// Types a character into the selected field: digits set the component's value (moving
    /// to the next field once it is complete); "a"/"p" set AM or PM.
    @MainActor internal func _type(_ ch: Character) -> Bool {
        var fields = _fields()
        guard _selectedField >= 0, _selectedField < fields.count, let comp = fields[_selectedField].component else { return false }
        let cal = _effectiveCalendar
        if _isAmPmField(fields[_selectedField]) {
            let lower = ch.lowercased()
            guard lower == "a" || lower == "p" else { return false }
            let hour = cal.component(.hour, from: _dateValue)
            let wantPM = lower == "p"
            if (hour >= 12) != wantPM, let d = cal.date(byAdding: .hour, value: wantPM ? 12 : -12, to: _dateValue) { _propose(d) }
            _selectNextField()
            return true
        }
        guard ch.isNumber, let digit = ch.wholeNumberValue else { return false }
        _typedDigits.append(String(digit))
        let maxDigits = comp == .year ? 4 : 2
        if _typedDigits.count > maxDigits { _typedDigits = String(digit) }
        guard let n = Int(_typedDigits) else { return false }
        var comps = cal.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: _dateValue)
        var value = n
        switch comp {
        case .month: value = min(max(n, 1), 12)
        case .day:
            let range = cal.range(of: .day, in: .month, for: _dateValue) ?? 1..<32
            value = min(max(n, 1), range.upperBound - 1)
        case .hour:
            let twelveHour = fields[_selectedField].format.first == "h" || fields[_selectedField].format.first == "K"
            if twelveHour {
                let pm = (comps.hour ?? 0) >= 12
                value = (min(max(n, 0), 12) % 12) + (pm ? 12 : 0)
            } else { value = min(max(n, 0), 23) }
        case .minute, .second: value = min(max(n, 0), 59)
        case .era: value = min(max(n, 0), 1)
        default: break
        }
        comps.setValue(value, for: comp)
        if let d = cal.date(from: comps) { _propose(d) }
        fields = _fields()
        // Complete: as many digits as the field takes, or no further digit could fit.
        let complete = _typedDigits.count >= maxDigits || (comp == .month && n > 1) || (comp == .day && n > 3) || (comp == .hour && n > 2) || ((comp == .minute || comp == .second) && n > 5)
        if complete { _selectNextField() }
        return true
    }

    @MainActor internal func _selectNextField() {
        let fields = _fields()
        _typedDigits = ""
        var i = _selectedField
        for _ in 0..<fields.count {
            i = (i + 1) % fields.count
            if fields[i].isEditable { _selectedField = i; _changed(); return }
        }
    }
    @MainActor internal func _selectPreviousField() {
        let fields = _fields()
        _typedDigits = ""
        var i = _selectedField < 0 ? fields.count : _selectedField
        for _ in 0..<fields.count {
            i = (i - 1 + fields.count) % fields.count
            if fields[i].isEditable { _selectedField = i; _changed(); return }
        }
    }
    @MainActor internal func _selectFirstField() {
        _selectedField = _fields().firstIndex { $0.isEditable } ?? -1
        _typedDigits = ""
        _changed()
    }

    // MARK: Geometry

    internal var _attributes: [NSAttributedString.Key: Any] { [.font: _effectiveFont, .foregroundColor: _isEnabled ? _textColorValue : NSColor.disabledControlTextColor] }

    /// Lays the fields out from the leading edge of the text rect and returns them with rects.
    @MainActor internal func _layoutFields(in cellFrame: NSRect) -> [Field] {
        var fields = _fields()
        let text = _textRect(forBounds: cellFrame)
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        var x = rtl ? text.maxX : text.minX
        for i in fields.indices {
            let w = fields[i].text.isEmpty ? 0 : fields[i].text.size(withAttributes: _attributes).width + (fields[i].isEditable ? 4 : 0)
            if rtl { x -= w }
            fields[i].rect = NSRect(x: x, y: text.minY, width: w, height: text.height)
            if !rtl { x += w }
        }
        return fields
    }

    @MainActor internal func _textRect(forBounds rect: NSRect) -> NSRect {
        var r = rect
        if _style == .textFieldAndStepper {
            let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
            if rtl { r.origin.x += NSDatePickerCell.stepperWidth + 3 }
            r.size.width = max(0, r.width - NSDatePickerCell.stepperWidth - 3)
        }
        if _isBezeled || _isBordered { r = r.insetBy(dx: 3, dy: 1) }
        return r.insetBy(dx: 1, dy: 0)
    }

    @MainActor internal func _stepperRect(forBounds rect: NSRect) -> NSRect {
        guard _style == .textFieldAndStepper else { return .zero }
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        let w = NSDatePickerCell.stepperWidth
        return NSRect(x: rtl ? rect.minX : rect.maxX - w, y: rect.minY, width: w, height: rect.height)
    }

    /// The calendar's and the clock's rects inside the graphical cell.
    @MainActor internal func _calendarRect(forBounds rect: NSRect) -> NSRect {
        guard _showsDate else { return .zero }
        return NSRect(x: rect.minX, y: rect.minY, width: NSDatePickerCell.calendarSize.width, height: rect.height)
    }
    @MainActor internal func _clockRect(forBounds rect: NSRect) -> NSRect {
        guard _showsTime else { return .zero }
        let x = _showsDate ? rect.minX + NSDatePickerCell.calendarSize.width + 8 : rect.minX
        return NSRect(x: x, y: rect.minY, width: NSDatePickerCell.clockSize.width, height: rect.height)
    }

    @MainActor open override var cellSize: NSSize {
        switch _style {
        case .clockAndCalendar:
            var w: CGFloat = 0
            if _showsDate { w += NSDatePickerCell.calendarSize.width }
            if _showsTime { w += (_showsDate ? 8 : 0) + NSDatePickerCell.clockSize.width }
            return NSSize(width: w, height: NSDatePickerCell.calendarSize.height)
        default:
            let fields = _fields()
            var w: CGFloat = 0
            for f in fields where !f.text.isEmpty { w += f.text.size(withAttributes: _attributes).width + (f.isEditable ? 4 : 0) }
            w += 8
            if _style == .textFieldAndStepper { w += NSDatePickerCell.stepperWidth + 3 }
            return NSSize(width: w.rounded(.up), height: 22)
        }
    }

    // MARK: Drawing

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        switch _style {
        case .clockAndCalendar: _drawGraphical(in: cellFrame, flipped: controlView.isFlipped)
        default: _drawTextual(in: cellFrame, flipped: controlView.isFlipped)
        }
    }

    private var _hasKeyboardFocus: Bool {
        guard let v = _controlView, let w = v.window else { return false }
        return w.firstResponder === v && w.isKeyWindow
    }

    private func _drawTextual(in cellFrame: NSRect, flipped: Bool) {
        var frame = cellFrame
        if _style == .textFieldAndStepper {
            let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
            if rtl { frame.origin.x += NSDatePickerCell.stepperWidth + 3 }
            frame.size.width -= NSDatePickerCell.stepperWidth + 3
        }
        if _drawsBackground {
            _backgroundColor.setFill()
            NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3).fill()
        }
        if _isBezeled {
            (_hasKeyboardFocus ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor.withAlphaComponent(0.7)).setStroke()
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            path.lineWidth = _hasKeyboardFocus ? 2 : 1
            path.stroke()
        } else if _isBordered {
            NSColor.separatorColor.setStroke()
            NSBezierPath.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        }
        let fields = _layoutFields(in: cellFrame)
        let focused = _hasKeyboardFocus
        for (i, f) in fields.enumerated() where !f.text.isEmpty {
            var attrs = _attributes
            if focused && i == _selectedField {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: f.rect.insetBy(dx: 0, dy: 2), xRadius: 2, yRadius: 2).fill()
                attrs[.foregroundColor] = NSColor.white
            }
            _drawText(f.text, attributes: attrs, in: f.rect, alignment: .center, flipped: flipped)
        }
        if _style == .textFieldAndStepper {
            // Only on a change: the cell's setter marks the control view dirty, and doing
            // that from every draw scheduled the next paint (a picker with a stepper kept
            // its window repainting, and the main thread busy, for as long as it showed).
            if _stepper.isEnabled != _isEnabled { _stepper.isEnabled = _isEnabled }
            _stepper.draw(withFrame: _stepperRect(forBounds: cellFrame), in: _controlView!)
        }
    }

    // MARK: The calendar and the clock

    /// The first day of the month the calendar shows.
    internal var _monthStart: Date {
        let cal = _effectiveCalendar
        let base = _visibleMonth ?? _dateValue
        return cal.date(from: cal.dateComponents([.era, .year, .month], from: base)) ?? base
    }

    /// Row and column of the calendar's day cells and the rects of its parts.
    internal struct CalendarLayout {
        var header: NSRect
        var previous: NSRect
        var next: NSRect
        var weekdays: NSRect
        var grid: NSRect
        var cell: NSSize
        /// The date each grid cell (row-major, 6 x 7) shows.
        var days: [Date]
        var firstOfMonth: Date
    }

    @MainActor internal func _calendarLayout(in rect: NSRect, flipped: Bool) -> CalendarLayout {
        let cal = _effectiveCalendar
        let headerH: CGFloat = 22, weekdayH: CGFloat = 16
        let top = flipped ? rect.minY : rect.maxY - headerH
        let header = NSRect(x: rect.minX, y: top, width: rect.width, height: headerH)
        let previous = NSRect(x: rect.minX, y: header.minY, width: 22, height: headerH)
        let next = NSRect(x: rect.maxX - 22, y: header.minY, width: 22, height: headerH)
        let weekdays = NSRect(x: rect.minX, y: flipped ? header.maxY : header.minY - weekdayH, width: rect.width, height: weekdayH)
        let gridTop = flipped ? weekdays.maxY : rect.minY
        let grid = NSRect(x: rect.minX, y: gridTop, width: rect.width, height: max(0, rect.height - headerH - weekdayH))
        let cell = NSSize(width: grid.width / 7, height: grid.height / 6)
        let first = _monthStart
        let weekday = cal.component(.weekday, from: first)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -lead, to: first) ?? first
        var days: [Date] = []
        for i in 0..<42 { days.append(cal.date(byAdding: .day, value: i, to: start) ?? start) }
        return CalendarLayout(header: header, previous: previous, next: next, weekdays: weekdays, grid: grid, cell: cell, days: days, firstOfMonth: first)
    }

    @MainActor internal func _dayCellRect(_ index: Int, layout: CalendarLayout, flipped: Bool) -> NSRect {
        let row = index / 7, col = index % 7
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        let x = rtl ? layout.grid.maxX - CGFloat(col + 1) * layout.cell.width : layout.grid.minX + CGFloat(col) * layout.cell.width
        let y = flipped ? layout.grid.minY + CGFloat(row) * layout.cell.height : layout.grid.maxY - CGFloat(row + 1) * layout.cell.height
        return NSRect(x: x, y: y, width: layout.cell.width, height: layout.cell.height)
    }

    private func _isSelectable(_ day: Date) -> Bool {
        let cal = _effectiveCalendar
        if let lo = _minDate, cal.compare(day, to: lo, toGranularity: .day) == .orderedAscending { return false }
        if let hi = _maxDate, cal.compare(day, to: hi, toGranularity: .day) == .orderedDescending { return false }
        return true
    }

    private func _drawGraphical(in cellFrame: NSRect, flipped: Bool) {
        if _drawsBackground {
            _backgroundColor.setFill()
            NSBezierPath(roundedRect: cellFrame, xRadius: 4, yRadius: 4).fill()
        }
        if _isBezeled || _isBordered {
            (_hasKeyboardFocus ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor.withAlphaComponent(0.7)).setStroke()
            let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            path.lineWidth = _hasKeyboardFocus ? 2 : 1
            path.stroke()
        }
        if _showsDate { _drawCalendar(in: _calendarRect(forBounds: cellFrame).insetBy(dx: 4, dy: 4), flipped: flipped) }
        if _showsTime { _drawClock(in: _clockRect(forBounds: cellFrame).insetBy(dx: 4, dy: 4), flipped: flipped) }
    }

    private func _drawCalendar(in rect: NSRect, flipped: Bool) {
        let cal = _effectiveCalendar
        let layout = _calendarLayout(in: rect, flipped: flipped)
        let small = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        let textColor: NSColor = _isEnabled ? _textColorValue : .disabledControlTextColor
        // Header: month and year, with the paging arrows.
        let title = _formatter(DateFormatter.dateFormat(fromTemplate: "yMMMM", options: 0, locale: _effectiveLocale) ?? "MMMM y").string(from: layout.firstOfMonth)
        _drawText(title, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize(for: .small)), .foregroundColor: textColor], in: layout.header, alignment: .center, flipped: flipped)
        for (r, left) in [(layout.previous, true), (layout.next, false)] {
            let p = NSBezierPath()
            let c = NSPoint(x: r.midX, y: r.midY)
            let dx: CGFloat = left ? 1 : -1
            p.move(to: NSPoint(x: c.x + dx * 2, y: c.y - 4))
            p.line(to: NSPoint(x: c.x - dx * 2, y: c.y))
            p.line(to: NSPoint(x: c.x + dx * 2, y: c.y + 4))
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            (_isEnabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor).setStroke()
            p.stroke()
        }
        // Weekday initials in the calendar's order.
        let symbols = cal.veryShortWeekdaySymbols
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        for col in 0..<7 {
            let s = symbols[(cal.firstWeekday - 1 + col) % 7]
            let x = rtl ? layout.weekdays.maxX - CGFloat(col + 1) * layout.cell.width : layout.weekdays.minX + CGFloat(col) * layout.cell.width
            let r = NSRect(x: x, y: layout.weekdays.minY, width: layout.cell.width, height: layout.weekdays.height)
            _drawText(s, attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor], in: r, alignment: .center, flipped: flipped)
        }
        // Days.
        let today = Date()
        let rangeEnd = _mode == .range ? _dateValue.addingTimeInterval(_timeInterval) : _dateValue
        for (i, day) in layout.days.enumerated() {
            let r = _dayCellRect(i, layout: layout, flipped: flipped)
            let inMonth = cal.isDate(day, equalTo: layout.firstOfMonth, toGranularity: .month)
            let selected = cal.isDate(day, inSameDayAs: _dateValue)
            let inRange = _mode == .range && !selected && cal.compare(day, to: _dateValue, toGranularity: .day) != .orderedAscending && cal.compare(day, to: rangeEnd, toGranularity: .day) != .orderedDescending
            var color: NSColor = inMonth ? textColor : NSColor.tertiaryLabelColor
            if !_isSelectable(day) { color = NSColor.quaternaryLabelColor }
            if selected {
                NSColor.controlAccentColor.setFill()
                let d = min(r.width, r.height) - 2
                NSBezierPath(ovalIn: NSRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)).fill()
                color = .white
            } else if inRange {
                NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
                NSBezierPath.fill(r)
            } else if cal.isDate(day, inSameDayAs: today) {
                NSColor.controlAccentColor.setStroke()
                let d = min(r.width, r.height) - 2
                let ring = NSBezierPath(ovalIn: NSRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d).insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            }
            let text = String(cal.component(.day, from: day))
            _drawText(text, attributes: [.font: small, .foregroundColor: color], in: r, alignment: .center, flipped: flipped)
        }
    }

    /// The clock face's centre and radius inside its rect.
    @MainActor internal func _clockGeometry(in rect: NSRect) -> (centre: NSPoint, radius: CGFloat) {
        let d = min(rect.width, rect.height - 18)
        return (NSPoint(x: rect.midX, y: rect.midY + (_controlView?.isFlipped ?? false ? -9 : 9)), d / 2)
    }

    private func _drawClock(in rect: NSRect, flipped: Bool) {
        let cal = _effectiveCalendar
        let (c, radius) = _clockGeometry(in: rect)
        let dy: CGFloat = flipped ? -1 : 1
        let face = NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
        NSColor.controlBackgroundColor.setFill()
        face.fill()
        NSColor.separatorColor.setStroke()
        face.lineWidth = 1
        face.stroke()
        // Hour ticks.
        (_isEnabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor).setStroke()
        for i in 0..<12 {
            let a = CGFloat.pi / 2 - CGFloat(i) * .pi / 6
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x + cos(a) * radius * 0.88, y: c.y + dy * sin(a) * radius * 0.88))
            p.line(to: NSPoint(x: c.x + cos(a) * radius * 0.97, y: c.y + dy * sin(a) * radius * 0.97))
            p.lineWidth = i % 3 == 0 ? 2 : 1
            p.stroke()
        }
        let hour = cal.component(.hour, from: _dateValue), minute = cal.component(.minute, from: _dateValue), second = cal.component(.second, from: _dateValue)
        func hand(_ angle: CGFloat, _ length: CGFloat, _ width: CGFloat, _ color: NSColor) {
            let p = NSBezierPath()
            p.move(to: c)
            p.line(to: NSPoint(x: c.x + cos(angle) * radius * length, y: c.y + dy * sin(angle) * radius * length))
            p.lineWidth = width
            p.lineCapStyle = .round
            color.setStroke()
            p.stroke()
        }
        let textColor: NSColor = _isEnabled ? _textColorValue : .disabledControlTextColor
        hand(CGFloat.pi / 2 - CGFloat(Double(hour % 12) + Double(minute) / 60) * .pi / 6, 0.5, 3, textColor)
        hand(CGFloat.pi / 2 - CGFloat(minute) * .pi / 30, 0.75, 2, textColor)
        if _elements.contains(.hourMinuteSecond) { hand(CGFloat.pi / 2 - CGFloat(second) * .pi / 30, 0.8, 1, .controlAccentColor) }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)).fill()
        // The time, digitally, under the face.
        let timeText = _formatter(DateFormatter.dateFormat(fromTemplate: _elements.contains(.hourMinuteSecond) ? "jms" : "jm", options: 0, locale: _effectiveLocale) ?? "HH:mm").string(from: _dateValue)
        let label = NSRect(x: rect.minX, y: flipped ? rect.maxY - 16 : rect.minY, width: rect.width, height: 16)
        _drawText(timeText, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)), .foregroundColor: textColor], in: label, alignment: .center, flipped: flipped)
    }

    // MARK: Hit-testing (graphical)

    /// The date under a point of the calendar, if any day is there.
    @MainActor internal func _day(at point: NSPoint, in cellFrame: NSRect, flipped: Bool) -> Date? {
        guard _showsDate else { return nil }
        let layout = _calendarLayout(in: _calendarRect(forBounds: cellFrame).insetBy(dx: 4, dy: 4), flipped: flipped)
        for i in 0..<42 where _dayCellRect(i, layout: layout, flipped: flipped).contains(point) { return layout.days[i] }
        return nil
    }

    /// -1 / +1 when a point is on the calendar's paging arrows.
    @MainActor internal func _pageDirection(at point: NSPoint, in cellFrame: NSRect, flipped: Bool) -> Int {
        guard _showsDate else { return 0 }
        let layout = _calendarLayout(in: _calendarRect(forBounds: cellFrame).insetBy(dx: 4, dy: 4), flipped: flipped)
        if layout.previous.contains(point) { return -1 }
        if layout.next.contains(point) { return 1 }
        return 0
    }

    @MainActor internal func _pageMonth(_ delta: Int) {
        let cal = _effectiveCalendar
        _visibleMonth = cal.date(byAdding: .month, value: delta, to: _monthStart)
        _changed()
    }

    /// Chooses a day: keeps the time of day, extends the range with `extending`.
    @MainActor internal func _choose(day: Date, extending: Bool) -> Bool {
        guard _isSelectable(day) else { return false }
        let cal = _effectiveCalendar
        var comps = cal.dateComponents([.era, .year, .month, .day], from: day)
        let time = cal.dateComponents([.hour, .minute, .second], from: _dateValue)
        comps.hour = time.hour; comps.minute = time.minute; comps.second = time.second
        guard let d = cal.date(from: comps) else { return false }
        if _mode == .range && extending {
            if d >= _dateValue { return _propose(_dateValue, interval: d.timeIntervalSince(_dateValue)) }
            return _propose(d, interval: _dateValue.addingTimeInterval(_timeInterval).timeIntervalSince(d))
        }
        return _propose(d, interval: _mode == .range ? 0 : nil)
    }

    /// The clock hand a point is nearest (hours inside 60 % of the radius), or nil off the face.
    @MainActor internal func _hand(at point: NSPoint, in cellFrame: NSRect) -> Calendar.Component? {
        guard _showsTime else { return nil }
        let (c, radius) = _clockGeometry(in: _clockRect(forBounds: cellFrame).insetBy(dx: 4, dy: 4))
        let d = hypot(point.x - c.x, point.y - c.y)
        guard d <= radius + 4 else { return nil }
        return d < radius * 0.5 ? .hour : .minute
    }

    /// Moves a hand to point at `point`.
    @MainActor internal func _drag(hand: Calendar.Component, to point: NSPoint, in cellFrame: NSRect, flipped: Bool) -> Bool {
        let (c, _) = _clockGeometry(in: _clockRect(forBounds: cellFrame).insetBy(dx: 4, dy: 4))
        let dy: CGFloat = flipped ? -1 : 1
        var angle = atan2(dy * (point.y - c.y), point.x - c.x)      // 0 at three o'clock, counter-clockwise
        angle = CGFloat.pi / 2 - angle                                // clockwise from twelve
        if angle < 0 { angle += 2 * .pi }
        let cal = _effectiveCalendar
        var comps = cal.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: _dateValue)
        if hand == .hour {
            let h = Int((angle / (.pi / 6)).rounded()) % 12
            comps.hour = h + ((comps.hour ?? 0) >= 12 ? 12 : 0)
        } else {
            comps.minute = Int((angle / (.pi / 30)).rounded()) % 60
        }
        guard let d = cal.date(from: comps) else { return false }
        return _propose(d)
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/calendar
    @MainActor open var calendar: Calendar? {
        get { _calendar }
        set { _calendar = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/datepickerelements
    @MainActor open var datePickerElements: NSDatePicker.ElementFlags {
        get { _elements }
        set { guard newValue != _elements else { return }; _elements = newValue; _selectedField = -1; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/datepickermode
    @MainActor open var datePickerMode: NSDatePicker.Mode {
        get { _mode }
        set { _mode = newValue; if newValue == .single { _timeInterval = 0 }; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/datepickerstyle
    @MainActor open var datePickerStyle: NSDatePicker.Style {
        get { _style }
        set { _style = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/datevalue
    @MainActor open var dateValue: Date {
        get { _dateValue }
        set {
            var d = newValue
            if let lo = _minDate, d < lo { d = lo }
            if let hi = _maxDate, d > hi { d = hi }
            _dateValue = d
            _objectValue = d
            _visibleMonth = nil
            _changed()
        }
    }
    @MainActor open override var objectValue: Any? {
        get { _dateValue }
        set { if let d = newValue as? Date { dateValue = d } else if let n = newValue as? NSDate { dateValue = Date(timeIntervalSinceReferenceDate: n.timeIntervalSinceReferenceDate) } }
    }
    @MainActor open override var stringValue: String {
        get { _fields().map(\.text).joined() }
        set { if let d = _formatter(_pattern).date(from: newValue) { dateValue = d } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/delegate
    @MainActor open var delegate: (any NSDatePickerCellDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _drawsBackground }
        set { _drawsBackground = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/locale
    @MainActor open var locale: Locale? {
        get { _locale }
        set { guard newValue != _locale else { return }; _locale = newValue; _selectedField = -1; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/maxdate
    @MainActor open var maxDate: Date? {
        get { _maxDate }
        set { _maxDate = newValue; if let hi = newValue, _dateValue > hi { dateValue = hi }; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/mindate
    @MainActor open var minDate: Date? {
        get { _minDate }
        set { _minDate = newValue; if let lo = newValue, _dateValue < lo { dateValue = lo }; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/textcolor
    @MainActor open var textColor: NSColor {
        get { _textColorValue }
        set { _textColorValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/timeinterval
    @MainActor open var timeInterval: TimeInterval {
        get { _timeInterval }
        set { _timeInterval = max(0, newValue); _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdatepickercell/timezone
    @MainActor open var timeZone: TimeZone? {
        get { _timeZone }
        set { _timeZone = newValue; _changed() }
    }
}
