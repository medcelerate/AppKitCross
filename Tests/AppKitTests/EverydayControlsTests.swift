// The everyday controls (ADR-0021): NSStepper, NSProgressIndicator, NSLevelIndicator,
// NSSearchField, NSTokenField, NSDatePicker and NSPathControl — values and limits,
// keyboard and mouse, target/action, drawing, and accessibility — plus the SwiftUI views
// that host them.

import XCTest
@testable import AppKit
@testable import SwiftUI

// MARK: - Helpers

@MainActor
private final class ActionSink: NSObject, NSSelectorHandling {
    var count = 0
    var doubleCount = 0
    var senders: [Any?] = []
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("act:")): count += 1; senders.append(sender); return true
        case Selector(("doubleAct:")): doubleCount += 1; return true
        default: return false
        }
    }
}

@MainActor
private func window(_ size: NSSize = NSSize(width: 320, height: 160)) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    w.backgroundColor = .white
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func key(_ w: NSWindow, _ chars: String, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    w.sendEvent(e)
}

@MainActor
private func mouse(_ w: NSWindow, _ type: NSEvent.EventType, _ p: NSPoint, count: Int = 1, flags: NSEvent.ModifierFlags = []) {
    w.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!)
}

@MainActor
private func click(_ w: NSWindow, _ p: NSPoint, count: Int = 1, flags: NSEvent.ModifierFlags = []) {
    mouse(w, .leftMouseDown, p, count: count, flags: flags)
    mouse(w, .leftMouseUp, p, count: count, flags: flags)
}

/// A point of `view` in window coordinates.
@MainActor
private func at(_ view: NSView, _ x: CGFloat, _ y: CGFloat) -> NSPoint { view.convert(NSPoint(x: x, y: y), to: nil) }

@MainActor
private func image(_ w: NSWindow) -> CGImage? {
    w.display()
    return (Mirror(reflecting: w).descendant("_platform") as? HostWindow)?.lastImage
}

/// The pixel at AppKit window point (x, y), from the host window's 2x image.
@MainActor
private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> (r: Int, g: Int, b: Int) {
    let data = _pixels(image)
    let scale = CGFloat(image.width) / 320
    let px = Int(x * scale), py = Int(y * scale)
    let row = image.height - 1 - py
    let i = row * image.bytesPerRow + px * 4
    return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))
}

private func isWhite(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 235 && p.g > 235 && p.b > 235 }

private let posix = Locale(identifier: "en_US_POSIX")
private let utc = TimeZone(identifier: "UTC")!
/// Formatted dates with ICU's narrow no-break space before AM/PM normalised to a space.
private func norm(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") }
private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

// MARK: - NSStepper

final class StepperTests: XCTestCase, @unchecked Sendable {
    func testValuesLimitsAndWrapping() {
        MainActor.assumeIsolated {
            let s = NSStepper(frame: NSRect(x: 0, y: 0, width: 15, height: 24))
            XCTAssertEqual(s.minValue, 0); XCTAssertEqual(s.maxValue, 59); XCTAssertEqual(s.increment, 1)
            XCTAssertTrue(s.autorepeat); XCTAssertFalse(s.valueWraps)
            s.maxValue = 3; s.increment = 2
            s._step(1); s._step(1)
            XCTAssertEqual(s.doubleValue, 3, "clamped at the maximum")
            s._step(1)
            XCTAssertEqual(s.doubleValue, 3)
            s.valueWraps = true
            s._step(1)
            XCTAssertEqual(s.doubleValue, 0, "wraps to the minimum")
            s._step(-1)
            XCTAssertEqual(s.doubleValue, 3, "and back to the maximum")
            XCTAssertEqual(s.intrinsicContentSize, NSSize(width: 15, height: 24))
            s.controlSize = .small
            XCTAssertEqual(s.intrinsicContentSize.height, 20)
        }
    }

    func testMouseKeyboardAndAutorepeatSendTheAction() {
        MainActor.assumeIsolated {
            let w = window()
            let s = NSStepper(frame: NSRect(x: 20, y: 20, width: 15, height: 24))
            let sink = ActionSink()
            s.target = sink; s.action = Selector(("act:"))
            w.contentView!.addSubview(s)
            // The upper half steps up, the lower half down.
            mouse(w, .leftMouseDown, at(s, 7, 20))
            XCTAssertEqual(s.doubleValue, 1)
            XCTAssertEqual(sink.count, 1)
            XCTAssertEqual(s._stepperCell?._pressedDirection, 1)
            s._autorepeatFired(); s._autorepeatFired()
            XCTAssertEqual(s.doubleValue, 3, "autorepeat keeps stepping while the mouse is down")
            XCTAssertEqual(sink.count, 3)
            // Dragging off the pressed half pauses the repeat; back on resumes it.
            mouse(w, .leftMouseDragged, at(s, 7, 4))
            s._autorepeatFired()
            XCTAssertEqual(s.doubleValue, 3)
            mouse(w, .leftMouseDragged, at(s, 7, 20))
            s._autorepeatFired()
            XCTAssertEqual(s.doubleValue, 4)
            mouse(w, .leftMouseUp, at(s, 7, 20))
            XCTAssertEqual(s._stepperCell?._pressedDirection, 0)
            s._autorepeatFired()
            XCTAssertEqual(s.doubleValue, 4, "nothing after the mouse is up")
            mouse(w, .leftMouseDown, at(s, 7, 4)); mouse(w, .leftMouseUp, at(s, 7, 4))
            XCTAssertEqual(s.doubleValue, 3, "the lower half steps down")
            s.autorepeat = false
            XCTAssertTrue(w.makeFirstResponder(s))
            key(w, "\u{F700}"); key(w, "\u{F700}"); key(w, "\u{F701}")
            XCTAssertEqual(s.doubleValue, 4)
            XCTAssertEqual(sink.count, 8)
            s.isEnabled = false
            mouse(w, .leftMouseDown, at(s, 7, 20)); mouse(w, .leftMouseUp, at(s, 7, 20))
            XCTAssertEqual(s.doubleValue, 4, "disabled steppers ignore the mouse")
            w.close()
        }
    }

    func testAccessibilityIsAnIncrementor() {
        MainActor.assumeIsolated {
            let w = window()
            let s = NSStepper(frame: NSRect(x: 20, y: 20, width: 15, height: 24))
            s.maxValue = 5
            let sink = ActionSink()
            s.target = sink; s.action = Selector(("act:"))
            w.contentView!.addSubview(s)
            XCTAssertEqual(s.accessibilityRole(), .incrementor)
            XCTAssertTrue(s.accessibilityPerformIncrement())
            XCTAssertTrue(s.accessibilityPerformIncrement())
            XCTAssertTrue(s.accessibilityPerformDecrement())
            XCTAssertEqual(s.doubleValue, 1)
            XCTAssertEqual(sink.count, 3)
            let e = s._accessibilityElement()
            XCTAssertEqual(e.role, "AXIncrementor")
            XCTAssertEqual(e.value, .number(1))
            XCTAssertEqual(e.minValue, 0); XCTAssertEqual(e.maxValue, 5)
            XCTAssertEqual(e.actions, [.increment, .decrement])
            XCTAssertTrue(s._accessibilitySetValue(.number(4)))
            XCTAssertEqual(s.doubleValue, 4)
            w.close()
        }
    }

    func testCellDrawsTheBezelAndThePressedHalf() {
        MainActor.assumeIsolated {
            let w = window()
            let s = NSStepper(frame: NSRect(x: 100, y: 60, width: 15, height: 24))
            w.contentView!.addSubview(s)
            guard let plain = image(w) else { return XCTFail("no image") }
            XCTAssertFalse(isWhite(pixel(plain, 107, 72)), "the bezel is drawn")
            mouse(w, .leftMouseDown, at(s, 7, 20))
            guard let pressed = image(w) else { return XCTFail("no image") }
            let top = pixel(pressed, 102, 80)
            XCTAssertGreaterThan(top.b, top.r + 60, "the pressed upper half fills with the accent colour")
            mouse(w, .leftMouseUp, at(s, 7, 20))
            w.close()
        }
    }
}

// MARK: - NSProgressIndicator

final class ProgressIndicatorTests: XCTestCase, @unchecked Sendable {
    func testValuesAndAnimationMachinery() {
        MainActor.assumeIsolated {
            let p = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 160, height: 20))
            XCTAssertTrue(p.isIndeterminate); XCTAssertEqual(p.minValue, 0); XCTAssertEqual(p.maxValue, 100)
            XCTAssertEqual(p.style, .bar); XCTAssertTrue(p.isBezeled); XCTAssertTrue(p.isDisplayedWhenStopped)
            p.isIndeterminate = false
            p.doubleValue = 150
            XCTAssertEqual(p.doubleValue, 100, "clamped to the range")
            p.doubleValue = 40
            p.increment(by: 25)
            XCTAssertEqual(p.doubleValue, 65)
            p.maxValue = 50
            XCTAssertEqual(p.doubleValue, 50, "a smaller maximum pulls the value down")
            XCTAssertEqual(p.intrinsicContentSize.height, 20)
            p.controlSize = .small
            XCTAssertEqual(p.intrinsicContentSize.height, 12)
            p.style = .spinning
            XCTAssertEqual(p.intrinsicContentSize, NSSize(width: 16, height: 16))
            p.controlSize = .regular
            p.sizeToFit()
            XCTAssertEqual(p.frame.size, NSSize(width: 32, height: 32))
            // The phase advances only while animating and indeterminate.
            p.isIndeterminate = true
            p._advanceAnimation(by: 0.25)
            XCTAssertEqual(p._animationPhase, 0)
            p.startAnimation(nil)
            XCTAssertTrue(p._isAnimating)
            p._advanceAnimation(by: 0.25)
            XCTAssertEqual(p._animationPhase, 0.25, accuracy: 1e-9, "a quarter of a one-second turn")
            p._advanceAnimation(by: 1)
            XCTAssertEqual(p._animationPhase, 0.25, accuracy: 1e-9, "wraps each turn")
            p.stopAnimation(nil)
            XCTAssertFalse(p._isAnimating)
            // A Progress object drives the value.
            let progress = Progress(totalUnitCount: 4)
            progress.completedUnitCount = 1
            p.style = .bar; p.minValue = 0; p.maxValue = 100
            p.observedProgress = progress
            XCTAssertFalse(p.isIndeterminate)
            XCTAssertEqual(p.doubleValue, 25, accuracy: 1e-9)
            progress.completedUnitCount = 3
            p._advanceAnimation(by: 0.1)
            XCTAssertEqual(p.doubleValue, 75, accuracy: 1e-9)
            p.observedProgress = nil
        }
    }

    func testBarAndSpinnerDrawing() {
        MainActor.assumeIsolated {
            let w = window()
            let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 100, width: 200, height: 20))
            bar.isIndeterminate = false
            bar.doubleValue = 50
            w.contentView!.addSubview(bar)
            let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 32, height: 32))
            spinner.style = .spinning
            spinner.startAnimation(nil)
            w.contentView!.addSubview(spinner)
            guard let img = image(w) else { return XCTFail("no image") }
            let left = pixel(img, 60, 110), right = pixel(img, 180, 110)
            XCTAssertGreaterThan(left.b, left.r + 80, "the filled half is the accent colour")
            XCTAssertLessThan(abs(right.r - right.b), 30, "the track beyond the value is grey")
            XCTAssertFalse(isWhite(right), "the bezel track is drawn")
            var spokes = 0
            for x in stride(from: 22, through: 50, by: 1) where !isWhite(pixel(img, CGFloat(x), 36)) { spokes += 1 }
            XCTAssertGreaterThan(spokes, 2, "the spinner's spokes are drawn")
            // Stopped and not displayed when stopped: nothing is drawn.
            spinner.isDisplayedWhenStopped = false
            spinner.stopAnimation(nil)
            bar.isBezeled = false
            bar.doubleValue = 0
            guard let blank = image(w) else { return XCTFail("no image") }
            for x in stride(from: 22, through: 50, by: 2) { XCTAssertTrue(isWhite(pixel(blank, CGFloat(x), 36))) }
            XCTAssertTrue(isWhite(pixel(blank, 180, 110)), "no track without a bezel")
            // Indeterminate bar: the highlight moves with the phase.
            bar.isBezeled = true
            bar.isIndeterminate = true
            bar.startAnimation(nil)
            bar._advanceAnimation(by: 0)
            guard let a = image(w) else { return XCTFail("no image") }
            bar._advanceAnimation(by: NSProgressIndicator.sweepDuration / 2)
            guard let b = image(w) else { return XCTFail("no image") }
            var differs = false
            for x in stride(from: 24, through: 216, by: 4) where pixel(a, CGFloat(x), 110) != pixel(b, CGFloat(x), 110) { differs = true }
            XCTAssertTrue(differs, "the sweep moved between frames")
            bar.stopAnimation(nil)
            w.close()
        }
    }

    func testAccessibilityRolesAndValue() {
        MainActor.assumeIsolated {
            let w = window()
            let p = NSProgressIndicator(frame: NSRect(x: 20, y: 100, width: 200, height: 20))
            w.contentView!.addSubview(p)
            XCTAssertEqual(p.accessibilityRole(), .progressIndicator)
            XCTAssertNil(p.accessibilityValue() as Any?, "indeterminate: no value")
            p.isIndeterminate = false
            p.doubleValue = 30
            let e = p._accessibilityElement()
            XCTAssertEqual(e.role, "AXProgressIndicator")
            XCTAssertEqual(e.value, .number(30))
            XCTAssertEqual(e.maxValue, 100)
            let n: NSNumber? = p.accessibilityValue()
            XCTAssertEqual(n?.doubleValue, 30)
            p.style = .spinning
            p.isIndeterminate = true
            XCTAssertEqual(p.accessibilityRole(), .busyIndicator)
            w.close()
        }
    }
}

// MARK: - NSLevelIndicator

final class LevelIndicatorTests: XCTestCase, @unchecked Sendable {
    func testDefaultsStylesAndTickMarks() {
        MainActor.assumeIsolated {
            let l = NSLevelIndicator(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
            XCTAssertEqual(l.levelIndicatorStyle, .discreteCapacity)
            XCTAssertEqual(l.minValue, 0); XCTAssertEqual(l.maxValue, 10)
            XCTAssertEqual(l.warningValue, 6); XCTAssertEqual(l.criticalValue, 8)
            XCTAssertFalse(l.isEditable)
            l.doubleValue = 3.6
            XCTAssertEqual(l._levelCell?._filledUnits, 4, "discrete segments round to the nearest unit")
            l.numberOfTickMarks = 11
            l.numberOfMajorTickMarks = 3
            XCTAssertEqual(l.tickMarkValue(at: 0), 0)
            XCTAssertEqual(l.tickMarkValue(at: 5), 5)
            XCTAssertEqual(l.tickMarkValue(at: 10), 10)
            let first = l.rectOfTickMark(at: 0), mid = l.rectOfTickMark(at: 5), last = l.rectOfTickMark(at: 10), minor = l.rectOfTickMark(at: 1)
            XCTAssertLessThan(first.minX, mid.minX); XCTAssertLessThan(mid.minX, last.minX)
            XCTAssertEqual(mid.height, 5, "a major tick mark is taller")
            XCTAssertEqual(minor.height, 3)
            XCTAssertLessThan(first.maxY, l._levelCell!._barRect.minY, "tick marks sit below the bar")
            l.tickMarkPosition = .above
            XCTAssertGreaterThan(l.rectOfTickMark(at: 0).minY, l._levelCell!._barRect(forBounds: l.bounds).maxY)
            XCTAssertEqual(l.rectOfTickMark(at: 11), .zero)
            l.levelIndicatorStyle = .rating
            l.maxValue = 5
            XCTAssertEqual(l.intrinsicContentSize.width, 75, "five stars of 15 pt")
            // Colours and the delegate-free editability.
            XCTAssertEqual(l.fillColor, NSColor.systemGreen)
            XCTAssertEqual(l.warningFillColor, NSColor.systemYellow)
            XCTAssertEqual(l.criticalFillColor, NSColor.systemRed)
            let cell = NSLevelIndicatorCell(levelIndicatorStyle: .relevancy)
            XCTAssertEqual(cell.levelIndicatorStyle, .relevancy)
        }
    }

    func testCapacityColoursFollowWarningAndCriticalLevels() {
        MainActor.assumeIsolated {
            let w = window()
            let l = NSLevelIndicator(frame: NSRect(x: 20, y: 80, width: 200, height: 20))
            l.levelIndicatorStyle = .continuousCapacity
            l.doubleValue = 3
            w.contentView!.addSubview(l)
            guard let green = image(w) else { return XCTFail("no image") }
            let g = pixel(green, 40, 90)
            XCTAssertGreaterThan(g.g, g.r + 50, "below the warning level the fill is green")
            l.doubleValue = 7
            guard let yellow = image(w) else { return XCTFail("no image") }
            let y = pixel(yellow, 40, 90)
            XCTAssertGreaterThan(y.r, 200); XCTAssertGreaterThan(y.g, 150); XCTAssertLessThan(y.b, 100)
            l.doubleValue = 9
            guard let red = image(w) else { return XCTFail("no image") }
            let r = pixel(red, 40, 90)
            XCTAssertGreaterThan(r.r, r.g + 80, "at the critical level the fill is red")
            XCTAssertTrue(isWhite(pixel(red, 215, 90)) || abs(pixel(red, 215, 90).r - pixel(red, 215, 90).b) < 20, "beyond the value is the track")
            // Tiered: each tier keeps its own colour.
            l.drawsTieredCapacityLevels = true
            guard let tiered = image(w) else { return XCTFail("no image") }
            let low = pixel(tiered, 40, 90), high = pixel(tiered, 190, 90)
            XCTAssertGreaterThan(low.g, low.r + 50, "the first tier stays green")
            XCTAssertGreaterThan(high.r, high.g + 80, "the top tier is red")
            // Discrete segments: filled ones coloured, the rest the track.
            l.levelIndicatorStyle = .discreteCapacity
            l.drawsTieredCapacityLevels = false
            l.doubleValue = 2
            guard let discrete = image(w) else { return XCTFail("no image") }
            let seg0 = pixel(discrete, 30, 90), seg9 = pixel(discrete, 210, 90)
            XCTAssertGreaterThan(seg0.g, seg0.r + 50)
            XCTAssertLessThan(abs(seg9.r - seg9.g), 20, "an empty segment is grey")
            w.close()
        }
    }

    func testEditableIndicatorsTakeClicksAndKeys() {
        MainActor.assumeIsolated {
            let w = window()
            let l = NSLevelIndicator(frame: NSRect(x: 20, y: 80, width: 200, height: 20))
            let sink = ActionSink()
            l.target = sink; l.action = Selector(("act:"))
            w.contentView!.addSubview(l)
            click(w, at(l, 150, 10))
            XCTAssertEqual(l.doubleValue, 0, "read-only unless editable")
            XCTAssertEqual(sink.count, 0)
            l.isEditable = true
            mouse(w, .leftMouseDown, at(l, 150, 10))
            XCTAssertEqual(l.doubleValue, 8, "the segment under the pointer (rounded up)")
            XCTAssertEqual(sink.count, 1)
            mouse(w, .leftMouseDragged, at(l, 30, 10))
            mouse(w, .leftMouseUp, at(l, 30, 10))
            XCTAssertEqual(l.doubleValue, 2)
            XCTAssertEqual(sink.count, 2)
            XCTAssertTrue(w.makeFirstResponder(l))
            key(w, "\u{F703}"); key(w, "\u{F703}"); key(w, "\u{F702}")
            XCTAssertEqual(l.doubleValue, 3)
            key(w, "\u{F72B}")
            XCTAssertEqual(l.doubleValue, 10)
            XCTAssertEqual(sink.count, 6)
            // Rating: a click on the third star gives 3; the first star again gives 1.
            l.levelIndicatorStyle = .rating
            l.maxValue = 5
            l.doubleValue = 0
            click(w, at(l, 40, 10))
            XCTAssertEqual(l.doubleValue, 3)
            click(w, at(l, 5, 10))
            XCTAssertEqual(l.doubleValue, 1)
            // Continuous: a click sets the proportion.
            l.levelIndicatorStyle = .continuousCapacity
            l.maxValue = 100
            click(w, at(l, 100, 10))
            XCTAssertEqual(l.doubleValue, 50, accuracy: 0.5)
            // Accessibility.
            XCTAssertEqual(l.accessibilityRole(), .levelIndicator)
            XCTAssertTrue(l.accessibilityPerformIncrement())
            XCTAssertEqual(l.doubleValue, 60, accuracy: 0.5)
            let e = l._accessibilityElement()
            XCTAssertTrue(e.isSettable)
            XCTAssertEqual(e.maxValue, 100)
            w.close()
        }
    }
}

// MARK: - NSSearchField

@MainActor
private final class SearchDelegate: NSObject, NSSearchFieldDelegate {
    var started = 0, ended = 0
    func searchFieldDidStartSearching(_ sender: NSSearchField) { started += 1 }
    func searchFieldDidEndSearching(_ sender: NSSearchField) { ended += 1 }
}

final class SearchFieldTests: XCTestCase, @unchecked Sendable {
    @MainActor private func makeField(_ w: NSWindow) -> (NSSearchField, ActionSink) {
        let f = NSSearchField(frame: NSRect(x: 20, y: 60, width: 200, height: 22))
        let sink = ActionSink()
        f.target = sink; f.action = Selector(("act:"))
        w.contentView!.addSubview(f)
        return (f, sink)
    }

    func testGeometryAndDefaults() {
        MainActor.assumeIsolated {
            let w = window()
            let (f, _) = makeField(w)
            XCTAssertEqual(f.placeholderString, "Search")
            XCTAssertEqual(f.bezelStyle, .roundedBezel)
            XCTAssertTrue(f.centersPlaceholder)
            XCTAssertEqual(f.maximumRecents, 10)
            XCTAssertFalse(f.sendsWholeSearchString); XCTAssertFalse(f.sendsSearchStringImmediately)
            let search = f.searchButtonBounds, cancel = f.cancelButtonBounds, text = f.searchTextBounds
            XCTAssertEqual(search.minX, 0); XCTAssertEqual(search.width, 22)
            XCTAssertEqual(cancel.maxX, 200); XCTAssertEqual(cancel.width, 22)
            XCTAssertGreaterThanOrEqual(text.minX, search.maxX - 2)
            XCTAssertLessThanOrEqual(text.maxX, cancel.minX + 2)
            XCTAssertEqual(f.rectForSearchText(whenCentered: false), text)
            XCTAssertLessThan(f.rectForSearchButton(whenCentered: true).minX + 1, f.rectForSearchText(whenCentered: true).midX)
            XCTAssertEqual(NSSearchField.recentsTitleMenuItemTag, 1000); XCTAssertEqual(NSSearchField.clearRecentsMenuItemTag, 1003)
            XCTAssertEqual(f.accessibilityRole(), .textField)
            XCTAssertEqual(f.accessibilitySubrole(), .searchField)
            // The magnifying glass is drawn; the cancel button only once there is text.
            guard let empty = image(w) else { return XCTFail("no image") }
            var glass = 0
            for x in 24...40 where !isWhite(pixel(empty, CGFloat(x), 71)) { glass += 1 }
            XCTAssertGreaterThan(glass, 0, "the search glyph")
            XCTAssertTrue(isWhite(pixel(empty, 213, 71)), "no cancel button while empty")
            f.stringValue = "moons"
            guard let typed = image(w) else { return XCTFail("no image") }
            XCTAssertFalse(isWhite(pixel(typed, 213, 71)), "the cancel button appears with text")
            w.close()
        }
    }

    func testTypingSendsTheSearchAndEscapeClearsIt() {
        MainActor.assumeIsolated {
            let w = window()
            let (f, sink) = makeField(w)
            let delegate = SearchDelegate()
            f.delegate = delegate
            f.sendsSearchStringImmediately = true
            XCTAssertTrue(w.makeFirstResponder(f))
            key(w, "m"); key(w, "a")
            XCTAssertEqual(f.stringValue, "ma")
            XCTAssertEqual(sink.count, 2, "each keystroke searches")
            XCTAssertEqual(delegate.started, 1)
            key(w, "\u{1B}")
            XCTAssertEqual(f.stringValue, "", "Escape clears")
            XCTAssertEqual(sink.count, 3, "and searches for nothing")
            XCTAssertEqual(delegate.ended, 1)
            XCTAssertNotNil(f.currentEditor, "still editing")
            // The delayed search: nothing until the timer, then once.
            f.sendsSearchStringImmediately = false
            key(w, "x")
            XCTAssertEqual(sink.count, 3)
            f._fireSearch()
            XCTAssertEqual(sink.count, 4)
            // Whole string only: Return sends and records the recent search.
            f.sendsWholeSearchString = true
            key(w, "y")
            f._fireSearch()
            XCTAssertEqual(sink.count, 5, "a pending timer still fires; typing alone does not")
            key(w, "z")
            key(w, "\r")
            XCTAssertEqual(f.stringValue, "xyz")
            XCTAssertEqual(sink.count, 6)
            XCTAssertEqual(f.recentSearches, ["xyz"])
            key(w, "\r")
            XCTAssertEqual(f.recentSearches, ["xyz"], "a repeated search is listed once")
            XCTAssertEqual(sink.count, 7, "each Return searches")
            // The cancel button clears and searches for nothing.
            click(w, at(f, 190, 11))
            XCTAssertEqual(f.stringValue, "")
            XCTAssertEqual(sink.count, 8)
            XCTAssertEqual(delegate.ended, 2)
            // Accessibility cancel does the same.
            f.stringValue = "again"
            XCTAssertTrue(f.accessibilityPerformCancel())
            XCTAssertEqual(f.stringValue, "")
            w.close()
        }
    }

    func testRecentsMenuIsBuiltFromTheTemplate() {
        MainActor.assumeIsolated {
            let w = window()
            let (f, sink) = makeField(w)
            let template = NSMenu(title: "")
            let title = NSMenuItem(title: "Recent Searches", action: nil, keyEquivalent: ""); title.tag = NSSearchField.recentsTitleMenuItemTag
            let recents = NSMenuItem(title: "%@", action: nil, keyEquivalent: ""); recents.tag = NSSearchField.recentsMenuItemTag
            let none = NSMenuItem(title: "No Recent Searches", action: nil, keyEquivalent: ""); none.tag = NSSearchField.noRecentsMenuItemTag
            let clear = NSMenuItem(title: "Clear", action: nil, keyEquivalent: ""); clear.tag = NSSearchField.clearRecentsMenuItemTag
            let custom = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
            for m in [custom, NSMenuItem.separator(), title, recents, none, clear] { template.addItem(m) }
            f.searchMenuTemplate = template
            XCTAssertEqual(f.searchButtonBounds.width, 30, "room for the menu chevron")
            guard let empty = f._searchCell?._buildSearchMenu() else { return XCTFail("no menu") }
            XCTAssertEqual(empty.items.map(\.title), ["Options", "", "No Recent Searches"])
            f.maximumRecents = 2
            f.recentSearches = ["a", "b", "c"]
            XCTAssertEqual(f.recentSearches, ["a", "b"], "trimmed to the maximum")
            guard let menu = f._searchCell?._buildSearchMenu() else { return XCTFail("no menu") }
            XCTAssertEqual(menu.items.map(\.title), ["Options", "", "Recent Searches", "a", "b", "Clear"])
            XCTAssertFalse(menu.items[2].isEnabled)
            // Choosing a recent search fills the field and searches; clearing empties the list.
            guard let item = menu.items.first(where: { $0.title == "b" }), let target = item.target, let action = item.action else { return XCTFail("no item") }
            _ = ActionRegistry.perform(action, on: target, with: item)
            XCTAssertEqual(f.stringValue, "b")
            XCTAssertEqual(sink.count, 1)
            XCTAssertEqual(f.recentSearches, ["b", "a"], "moved to the front")
            let clearItem = menu.items.last!
            _ = ActionRegistry.perform(clearItem.action!, on: clearItem.target!, with: clearItem)
            XCTAssertEqual(f.recentSearches, [])
            // Autosave round-trips through user defaults.
            let name = "AppKitCrossTests.recents.\(UUID().uuidString)"
            f.recentsAutosaveName = name
            f.recentSearches = ["saved"]
            let g = NSSearchField(frame: .zero)
            g.recentsAutosaveName = name
            XCTAssertEqual(g.recentSearches, ["saved"])
            UserDefaults.standard.removeObject(forKey: "NSSearchField Recents \(name)")
            w.close()
        }
    }
}

// MARK: - NSTokenField

@MainActor
private final class TokenDelegate: NSObject, NSTokenFieldDelegate {
    var completions: [String] = []
    var added: [[Any]] = []
    var menuFor: String? = nil
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
        let m = completions.filter { $0.lowercased().hasPrefix(substring.lowercased()) }
        return m.isEmpty ? nil : m
    }
    func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
        added.append(tokens)
        return tokens.filter { ($0 as? String) != "nope" }
    }
    func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
        (representedObject as? String).map { $0.uppercased() }
    }
    func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool { (representedObject as? String) == menuFor }
    func tokenField(_ tokenField: NSTokenField, menuForRepresentedObject representedObject: Any) -> NSMenu? {
        let m = NSMenu(title: ""); m.addItem(NSMenuItem(title: "Info", action: nil, keyEquivalent: "")); return m
    }
}

final class TokenFieldTests: XCTestCase, @unchecked Sendable {
    @MainActor private func makeField(_ w: NSWindow) -> (NSTokenField, ActionSink) {
        let f = NSTokenField(frame: NSRect(x: 20, y: 60, width: 280, height: 22))
        let sink = ActionSink()
        f.target = sink; f.action = Selector(("act:"))
        w.contentView!.addSubview(f)
        return (f, sink)
    }

    func testValuesTokenizeOnTheCharacterSet() {
        MainActor.assumeIsolated {
            let f = NSTokenField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
            XCTAssertEqual(f.tokenizingCharacterSet, CharacterSet(charactersIn: ","))
            XCTAssertEqual(f.tokenStyle, .default)
            XCTAssertEqual(NSTokenField.defaultCompletionDelay, 0)
            f.stringValue = "Mercury, Venus ,Earth,"
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["Mercury", "Venus", "Earth"])
            XCTAssertEqual(f.stringValue, "Mercury, Venus, Earth")
            f.objectValue = ["a", "b"]
            XCTAssertEqual(f.stringValue, "a, b")
            f.tokenizingCharacterSet = CharacterSet(charactersIn: ";")
            f.stringValue = "x;y"
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["x", "y"])
            XCTAssertEqual(f.stringValue, "x; y")
            XCTAssertGreaterThan(f.intrinsicContentSize.width, NSTextField(frame: .zero).intrinsicContentSize.width, "room for the tokens")
        }
    }

    func testTypingMakesTokensAndKeysMoveAmongThem() {
        MainActor.assumeIsolated {
            let w = window()
            let (f, sink) = makeField(w)
            let delegate = TokenDelegate()
            f.delegate = delegate
            XCTAssertTrue(w.makeFirstResponder(f))
            for c in "ab,cd" { key(w, String(c)) }
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["ab"], "the comma makes the first token")
            XCTAssertEqual(f.currentEditor?.string, "cd", "the rest is still being typed")
            XCTAssertEqual(delegate.added.count, 1)
            key(w, "\r")
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["ab", "cd"], "Return tokenizes the rest")
            XCTAssertEqual(sink.count, 1, "and sends the action")
            XCTAssertEqual(f.currentEditor?.string, "")
            XCTAssertEqual(f.stringValue, "AB, CD", "display strings come from the delegate")
            // Backspace: first selects the last token, then deletes it.
            key(w, "\u{7F}")
            XCTAssertEqual(f._tokenCell?._selectedToken, 1)
            XCTAssertEqual((f.objectValue as? [String])?.count, 2)
            key(w, "\u{7F}")
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["ab"])
            XCTAssertEqual(f._tokenCell?._selectedToken, -1)
            // Left selects the last token, Right past the end deselects.
            for c in "ef," { key(w, String(c)) }
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["ab", "ef"])
            key(w, "\u{F702}")
            XCTAssertEqual(f._tokenCell?._selectedToken, 1)
            key(w, "\u{F702}")
            XCTAssertEqual(f._tokenCell?._selectedToken, 0)
            key(w, "\u{F703}"); key(w, "\u{F703}")
            XCTAssertEqual(f._tokenCell?._selectedToken, -1)
            // Typing deselects; the delegate's shouldAdd filters.
            key(w, "\u{F702}")
            for c in "nope," { key(w, String(c)) }
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["ab", "ef"], "the delegate refused the token")
            // Tab tokenizes the typed text before focus moves on.
            for c in "gh" { key(w, String(c)) }
            key(w, "\t")
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["ab", "ef", "gh"])
            w.close()
        }
    }

    func testCompletionsListFollowsTheDelegate() {
        MainActor.assumeIsolated {
            let w = window()
            let (f, _) = makeField(w)
            let delegate = TokenDelegate()
            delegate.completions = ["Mercury", "Mars", "Venus"]
            f.delegate = delegate
            XCTAssertTrue(w.makeFirstResponder(f))
            key(w, "m")
            XCTAssertNotNil(f._completionPopUp, "the list opens with matches")
            XCTAssertEqual(f._completions as? [String], ["Mercury", "Mars"])
            XCTAssertEqual(f._selectedCompletion, 0)
            XCTAssertTrue(f._completionPopUp?.window.isVisible ?? false)
            key(w, "\u{F701}")
            XCTAssertEqual(f._selectedCompletion, 1)
            key(w, "\u{F701}")
            XCTAssertEqual(f._selectedCompletion, 1, "stays on the last row")
            key(w, "\r")
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["Mars"], "Return takes the selected completion")
            XCTAssertNil(f._completionPopUp)
            XCTAssertEqual(f.currentEditor?.string, "")
            key(w, "v")
            XCTAssertEqual(f._completions as? [String], ["Venus"])
            key(w, "\u{1B}")
            XCTAssertNil(f._completionPopUp, "Escape closes the list")
            XCTAssertEqual(f.currentEditor?.string, "v", "and keeps the text")
            key(w, "z")
            XCTAssertNil(f._completionPopUp, "no matches, no list")
            // A click in the list takes that row.
            key(w, "\u{7F}"); key(w, "\u{7F}")
            key(w, "m")
            guard let popUp = f._completionPopUp else { return XCTFail("no list") }
            let list = popUp.list
            let p = NSPoint(x: 20, y: _NSTokenCompletionListView.rowHeight * 1.5)
            list.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: list.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: popUp.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            list.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: list.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: popUp.window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!)
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["Mars", "Mars"])
            // Ending editing closes the list and keeps the tokens.
            key(w, "m")
            XCTAssertNotNil(f._completionPopUp)
            _ = w.makeFirstResponder(nil)
            XCTAssertNil(f._completionPopUp)
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["Mars", "Mars", "m"])
            w.close()
        }
    }

    func testMouseSelectsEditsAndMenusTokens() {
        MainActor.assumeIsolated {
            let w = window()
            let (f, _) = makeField(w)
            let delegate = TokenDelegate()
            delegate.menuFor = "two"
            f.delegate = delegate
            f.objectValue = ["one", "two"]
            guard let cell = f._tokenCell else { return XCTFail("no cell") }
            let rects = cell._tokenRects(in: f.bounds)
            XCTAssertEqual(rects.count, 2)
            XCTAssertGreaterThan(rects[1].minX, rects[0].maxX)
            XCTAssertGreaterThan(rects[1].width, rects[0].width, "the token with a menu is wider (its chevron)")
            XCTAssertGreaterThanOrEqual(cell._textRect(forBounds: f.bounds).minX, rects[1].maxX, "the editor sits after the tokens")
            // Click a token: it is selected and editing begins.
            click(w, at(f, rects[0].midX, rects[0].midY))
            XCTAssertEqual(cell._selectedToken, 0)
            XCTAssertNotNil(f.currentEditor)
            // The chevron hits the menu side.
            XCTAssertEqual(cell._token(at: NSPoint(x: rects[1].maxX - 4, y: rects[1].midY), in: f.bounds)?.onMenu, true)
            XCTAssertEqual(cell._token(at: NSPoint(x: rects[1].minX + 4, y: rects[1].midY), in: f.bounds)?.onMenu, false)
            // Double-click turns the token back into text (its editing string) for editing.
            click(w, at(f, rects[0].midX, rects[0].midY), count: 2)
            XCTAssertEqual((f.objectValue as? [String]) ?? [], [])
            XCTAssertEqual(f.currentEditor?.string, "ONE, TWO", "the editing string defaults to the display string")
            XCTAssertEqual(f.currentEditor?.selectedRange, NSRange(location: 0, length: 3))
            // Ending editing tokenizes the text again.
            _ = w.makeFirstResponder(nil)
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["ONE", "TWO"])
            // Drawing: the token pill is tinted, the field background white.
            f.objectValue = ["one"]
            guard let img = image(w) else { return XCTFail("no image") }
            let r = f._tokenCell!._tokenRects(in: f.bounds)[0]
            let inside = pixel(img, 20 + r.midX, 60 + r.midY - 4)
            XCTAssertFalse(isWhite(inside), "the pill is tinted")
            XCTAssertTrue(isWhite(pixel(img, 250, 71)), "the rest of the field is clear")
            // Accessibility: the value is the text, setting it tokenizes.
            let tokenValue: Any? = f.accessibilityValue()
            XCTAssertEqual(tokenValue as? String, "ONE")
            XCTAssertTrue(f._accessibilitySetValue(.string("x, y")))
            XCTAssertEqual((f.objectValue as? [String]) ?? [], ["x", "y"])
            w.close()
        }
    }
}

// MARK: - NSDatePicker

@MainActor
private final class DateDelegate: NSObject, NSDatePickerCellDelegate {
    var floor: Date? = nil
    var calls = 0
    func datePickerCell(_ datePickerCell: NSDatePickerCell, validateProposedDateValue proposedDateValue: AutoreleasingUnsafeMutablePointer<NSDate>, timeInterval proposedTimeInterval: UnsafeMutablePointer<TimeInterval>?) {
        calls += 1
        if let floor, proposedDateValue.pointee.timeIntervalSinceReferenceDate < floor.timeIntervalSinceReferenceDate {
            proposedDateValue.pointee = NSDate(timeIntervalSinceReferenceDate: floor.timeIntervalSinceReferenceDate)
        }
    }
}

final class DatePickerTests: XCTestCase, @unchecked Sendable {
    @MainActor private func makePicker(_ w: NSWindow, style: NSDatePicker.Style = .textFieldAndStepper) -> (NSDatePicker, ActionSink) {
        let p = NSDatePicker(frame: NSRect(x: 20, y: 60, width: 200, height: 22))
        p.locale = posix
        p.timeZone = utc
        p.datePickerStyle = style
        p.dateValue = date(2026, 11, 10, 14, 30)
        let sink = ActionSink()
        p.target = sink; p.action = Selector(("act:"))
        w.contentView!.addSubview(p)
        return (p, sink)
    }

    func testFieldsFollowTheLocaleAndElements() {
        MainActor.assumeIsolated {
            let p = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
            p.locale = posix; p.timeZone = utc
            p.dateValue = date(2026, 11, 10, 14, 30, 5)
            XCTAssertEqual(p.datePickerElements, [.yearMonthDay, .hourMinute])
            XCTAssertEqual(norm(p.stringValue), "11/10/2026, 2:30 PM")
            p.datePickerElements = [.yearMonthDay]
            XCTAssertEqual(p.stringValue, "11/10/2026")
            p.datePickerElements = [.hourMinuteSecond]
            XCTAssertEqual(norm(p.stringValue), "2:30:05 PM")
            p.datePickerElements = [.yearMonth]
            XCTAssertEqual(p.stringValue, "11/2026")
            p.locale = Locale(identifier: "de_DE")
            p.datePickerElements = [.yearMonthDay, .hourMinute]
            XCTAssertEqual(p.stringValue, "10.11.2026, 14:30")
            let editable = p._dateCell!._fields().filter(\.isEditable).map(\.format)
            XCTAssertEqual(editable, ["d", "M", "y", "HH", "mm"])
            // Limits clamp the value; stringValue parses the field's own pattern.
            p.locale = posix
            p.minDate = date(2026, 1, 1)
            p.maxDate = date(2026, 12, 31)
            p.dateValue = date(2027, 6, 1)
            XCTAssertEqual(p.dateValue, date(2026, 12, 31))
            p.stringValue = "3/4/2026, 1:02 AM"
            XCTAssertEqual(p.dateValue, date(2026, 3, 4, 1, 2))
            XCTAssertEqual(p.timeInterval, 0)
            XCTAssertGreaterThan(p.intrinsicContentSize.width, 100)
            XCTAssertEqual(p.intrinsicContentSize.height, 22)
            p.datePickerStyle = .clockAndCalendar
            XCTAssertEqual(p.intrinsicContentSize, NSSize(width: 160 + 8 + 120, height: 150))
            p.datePickerElements = [.yearMonthDay]
            XCTAssertEqual(p.intrinsicContentSize.width, 160)
        }
    }

    func testKeyboardStepperAndTypingEditTheSelectedField() {
        MainActor.assumeIsolated {
            let w = window()
            let (p, sink) = makePicker(w)
            let delegate = DateDelegate()
            p.delegate = delegate
            XCTAssertTrue(w.makeFirstResponder(p))
            XCTAssertEqual(p._dateCell?._selectedField, 0, "the first field (the month) is selected on focus")
            key(w, "\u{F700}")
            XCTAssertEqual(p.dateValue, date(2026, 12, 10, 14, 30))
            XCTAssertEqual(sink.count, 1)
            XCTAssertEqual(delegate.calls, 1)
            key(w, "\u{F703}")       // day
            key(w, "\u{F701}")
            XCTAssertEqual(p.dateValue, date(2026, 12, 9, 14, 30))
            key(w, "\u{F703}")       // year
            key(w, "\u{F703}")       // hour
            key(w, "\u{F700}")
            XCTAssertEqual(p.dateValue, date(2026, 12, 9, 15, 30))
            key(w, "\u{F703}")       // minute
            key(w, "\u{F703}")       // AM/PM
            key(w, "\u{F700}")
            XCTAssertEqual(p.dateValue, date(2026, 12, 10, 3, 30), "AM/PM toggles twelve hours")
            key(w, "\u{F703}")
            XCTAssertEqual(p._dateCell?._selectedField, 0, "wraps to the first field")
            // Typing digits sets the field and moves on when it is complete.
            key(w, "3")
            XCTAssertEqual(p.dateValue, date(2026, 12, 10, 3, 30).setting(month: 3), "a 3 can only be March")
            XCTAssertEqual(p._dateCell?._fields()[p._dateCell!._selectedField].format, "d", "moved to the day")
            key(w, "1"); key(w, "5")
            XCTAssertEqual(p.dateValue, date(2026, 3, 15, 3, 30))
            XCTAssertEqual(p._dateCell?._fields()[p._dateCell!._selectedField].format, "y")
            key(w, "2"); key(w, "0"); key(w, "3"); key(w, "0")
            XCTAssertEqual(p.dateValue, date(2030, 3, 15, 3, 30))
            key(w, "\u{F703}"); key(w, "\u{F703}")   // minute, then AM/PM
            key(w, "p")
            XCTAssertEqual(p.dateValue, date(2030, 3, 15, 15, 30))
            XCTAssertEqual(p._dateCell?._selectedField, 0, "AM/PM was the last field: back to the first")
            // The delegate can veto: a floor below which the date will not go.
            delegate.floor = date(2030, 3, 15, 15, 0)
            key(w, "\u{F702}"); key(w, "\u{F702}")       // back to the minute
            key(w, "\u{F701}")
            XCTAssertEqual(p.dateValue, date(2030, 3, 15, 15, 29))
            for _ in 0..<40 { key(w, "\u{F701}") }
            XCTAssertEqual(p.dateValue, date(2030, 3, 15, 15, 0), "held at the delegate's floor")
            // The stepper steps the selected field; the action goes out once per step.
            delegate.floor = nil
            let before = sink.count
            let stepper = p._dateCell!._stepperRect(forBounds: p.bounds)
            mouse(w, .leftMouseDown, at(p, stepper.midX, stepper.maxY - 3))
            mouse(w, .leftMouseUp, at(p, stepper.midX, stepper.maxY - 3))
            XCTAssertEqual(p.dateValue, date(2030, 3, 15, 15, 1))
            XCTAssertEqual(sink.count, before + 1)
            // A click on a field selects it.
            let fields = p._dateCell!._layoutFields(in: p.bounds)
            let year = fields.firstIndex { $0.format == "y" }!
            click(w, at(p, fields[year].rect.midX, fields[year].rect.midY))
            XCTAssertEqual(p._dateCell?._selectedField, year)
            // Accessibility.
            XCTAssertEqual(p.accessibilityRole(), .dateTimeAreaRole)
            let axValue: Any? = p.accessibilityValue()
            XCTAssertEqual(axValue as? String, p.stringValue)
            XCTAssertTrue(p.accessibilityPerformIncrement())
            XCTAssertEqual(p.dateValue, date(2031, 3, 15, 15, 1))
            w.close()
        }
    }

    func testGraphicalStyleCalendarAndClock() {
        MainActor.assumeIsolated {
            let w = window(NSSize(width: 320, height: 200))
            let (p, sink) = makePicker(w, style: .clockAndCalendar)
            p.frame = NSRect(x: 10, y: 20, width: 288, height: 150)
            let cell = p._dateCell!
            // The calendar shows November 2026 with the 10th selected.
            let layout = cell._calendarLayout(in: cell._calendarRect(forBounds: p.bounds).insetBy(dx: 4, dy: 4), flipped: false)
            let cal = cell._effectiveCalendar
            XCTAssertEqual(cal.component(.month, from: layout.firstOfMonth), 11)
            XCTAssertEqual(cal.component(.weekday, from: layout.days[0]), cal.firstWeekday)
            let index = layout.days.firstIndex { cal.isDate($0, inSameDayAs: date(2026, 11, 20)) }!
            let r = cell._dayCellRect(index, layout: layout, flipped: false)
            click(w, at(p, r.midX, r.midY))
            XCTAssertEqual(p.dateValue, date(2026, 11, 20, 14, 30), "a day keeps the time")
            XCTAssertEqual(sink.count, 1)
            // Paging the month moves what is shown, not the value.
            click(w, at(p, layout.next.midX, layout.next.midY))
            XCTAssertEqual(cal.component(.month, from: cell._monthStart), 12)
            XCTAssertEqual(p.dateValue, date(2026, 11, 20, 14, 30))
            click(w, at(p, layout.previous.midX, layout.previous.midY))
            XCTAssertEqual(cal.component(.month, from: cell._monthStart), 11)
            // Days before the minimum cannot be chosen.
            p.minDate = date(2026, 11, 5)
            let early = layout.days.firstIndex { cal.isDate($0, inSameDayAs: date(2026, 11, 2)) }!
            let er = cell._dayCellRect(early, layout: layout, flipped: false)
            click(w, at(p, er.midX, er.midY))
            XCTAssertEqual(p.dateValue, date(2026, 11, 20, 14, 30))
            // Range mode: Shift-click extends.
            p.datePickerMode = .range
            let later = layout.days.firstIndex { cal.isDate($0, inSameDayAs: date(2026, 11, 25)) }!
            let lr = cell._dayCellRect(later, layout: layout, flipped: false)
            click(w, at(p, lr.midX, lr.midY), flags: .shift)
            XCTAssertEqual(p.dateValue, date(2026, 11, 20, 14, 30))
            XCTAssertEqual(p.timeInterval, 5 * 86400)
            // The clock: a drag on the outer part turns the minute hand.
            let (c, radius) = cell._clockGeometry(in: cell._clockRect(forBounds: p.bounds).insetBy(dx: 4, dy: 4))
            mouse(w, .leftMouseDown, at(p, c.x + radius * 0.8, c.y))        // three o'clock: 15 minutes
            XCTAssertEqual(cal.component(.minute, from: p.dateValue), 15)
            mouse(w, .leftMouseDragged, at(p, c.x, c.y - radius * 0.8))     // six o'clock: 30 minutes
            mouse(w, .leftMouseUp, at(p, c.x, c.y - radius * 0.8))
            XCTAssertEqual(cal.component(.minute, from: p.dateValue), 30)
            click(w, at(p, c.x - radius * 0.3, c.y))                       // nine o'clock on the hour hand: 9 (PM stays)
            XCTAssertEqual(cal.component(.hour, from: p.dateValue), 21)
            // Keyboard: arrows move by a day and a week.
            XCTAssertTrue(w.makeFirstResponder(p))
            key(w, "\u{F703}"); key(w, "\u{F701}")
            XCTAssertEqual(cal.component(.day, from: p.dateValue), 28)
            // Drawing: the selected day is a filled accent disc.
            guard let img = image(w) else { return XCTFail("no image") }
            let sel = layout.days.firstIndex { cal.isDate($0, inSameDayAs: p.dateValue) }!
            let sr = cell._dayCellRect(sel, layout: layout, flipped: false)
            let px = pixel(img, 10 + sr.midX - 5, 20 + sr.midY)
            XCTAssertGreaterThan(px.b, px.r + 80, "selected day is accent-filled")
            w.close()
        }
    }
}

private extension Date {
    func setting(month: Int) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: self)
        c.month = month
        return cal.date(from: c)!
    }
}

// MARK: - NSPathControl

final class PathControlTests: XCTestCase, @unchecked Sendable {
    func testItemsFollowTheURL() {
        MainActor.assumeIsolated {
            let p = NSPathControl(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
            XCTAssertNil(p.url)
            XCTAssertEqual(p.pathItems.count, 0)
            p.placeholderString = "No file"
            p.url = URL(fileURLWithPath: "/Users/jane/Documents/notes.txt")
            XCTAssertEqual(p.pathItems.map(\.title), ["/", "Users", "jane", "Documents", "notes.txt"])
            XCTAssertEqual(p.pathItems[2].url, URL(fileURLWithPath: "/Users/jane"))
            XCTAssertEqual(p.pathItems.last?.url, p.url)
            XCTAssertEqual(p.pathComponentCells().count, 5)
            XCTAssertEqual(p.pathComponentCells()[3].stringValue, "Documents")
            XCTAssertEqual(p.stringValue, "/Users/jane/Documents/notes.txt")
            // Items can be set: the URL follows the last one.
            let a = NSPathControlItem(); a.title = "Root"; a._url = URL(fileURLWithPath: "/")
            let b = NSPathControlItem(); b.title = "Leaf"; b._url = URL(fileURLWithPath: "/leaf")
            p.pathItems = [a, b]
            XCTAssertEqual(p.url, URL(fileURLWithPath: "/leaf"))
            XCTAssertEqual(p.pathComponentCells().map(\.stringValue), ["Root", "Leaf"])
            // Component cells, directly.
            let c = NSPathComponentCell(textCell: "X"); c.url = URL(fileURLWithPath: "/x")
            p.setPathComponentCells([c])
            XCTAssertEqual(p.url, URL(fileURLWithPath: "/x"))
            XCTAssertEqual(p.pathItems.map(\.title), ["X"])
            // A remote URL has its host as the root.
            p.url = URL(string: "https://example.com/a/b")!
            XCTAssertEqual(p.pathItems.map(\.title), ["/", "a", "b"])
            p.url = nil
            XCTAssertEqual(p.pathItems.count, 0)
            XCTAssertGreaterThan(p.intrinsicContentSize.width, 0)
        }
    }

    func testClicksReportTheItemAndTheStandardLayoutShrinks() {
        MainActor.assumeIsolated {
            let w = window()
            let p = NSPathControl(frame: NSRect(x: 10, y: 60, width: 300, height: 22))
            p.url = URL(fileURLWithPath: "/Users/jane/Documents/notes.txt")
            let sink = ActionSink()
            p.target = sink; p.action = Selector(("act:")); p.doubleAction = Selector(("doubleAct:"))
            w.contentView!.addSubview(p)
            let cells = p.pathComponentCells()
            let rects = cells.map { p._pathCell!.rect(of: $0, withFrame: p.bounds, in: p) }
            for i in 1..<rects.count { XCTAssertGreaterThan(rects[i].minX, rects[i - 1].maxX, "components run left to right with a gap") }
            click(w, at(p, rects[2].midX, 11))
            XCTAssertEqual(p.clickedPathItem?.title, "jane")
            XCTAssertEqual(p.clickedPathItem?.url, URL(fileURLWithPath: "/Users/jane"))
            XCTAssertEqual(sink.count, 1)
            XCTAssertEqual(p.url, URL(fileURLWithPath: "/Users/jane/Documents/notes.txt"), "a click does not change the URL")
            click(w, at(p, rects[4].midX, 11), count: 2)
            XCTAssertEqual(sink.doubleCount, 1)
            XCTAssertEqual(p.clickedPathItem?.title, "notes.txt")
            // Pressing down on one component and releasing on another sends nothing.
            mouse(w, .leftMouseDown, at(p, rects[1].midX, 11))
            mouse(w, .leftMouseUp, at(p, rects[3].midX, 11))
            XCTAssertEqual(sink.count, 1)
            // Narrow: all but the last component shrink, nothing overflows.
            p.frame.size.width = 120
            let narrow = p.pathComponentCells().map { p._pathCell!.rect(of: $0, withFrame: p.bounds, in: p) }
            XCTAssertLessThanOrEqual(narrow.last!.maxX, p.bounds.maxX)
            XCTAssertLessThan(narrow[3].width, rects[3].width)
            XCTAssertGreaterThanOrEqual(narrow[1].width, 8)
            // Drawing: the chevrons between components leave ink.
            p.frame.size.width = 300
            guard let img = image(w) else { return XCTFail("no image") }
            var ink = 0
            let gap = (rects[0].maxX + rects[1].minX) / 2
            for y in 64...78 where !isWhite(pixel(img, 10 + gap, CGFloat(y))) { ink += 1 }
            XCTAssertGreaterThan(ink, 0, "a chevron is drawn between components")
            // Accessibility: one button per component.
            XCTAssertEqual(p.accessibilityRole(), .group)
            let e = p._accessibilityElement()
            XCTAssertEqual(e.children.count, 5)
            XCTAssertEqual(e.children[2].label, "jane")
            XCTAssertEqual(e.children[2].role, "AXButton")
            let id = e.children[2].id
            XCTAssertTrue(p._accessibilityVirtualElement(withID: id)?._accessibilityPerform(.press) ?? false)
            XCTAssertEqual(sink.count, 2)
            XCTAssertEqual(p.clickedPathItem?.title, "jane")
            w.close()
        }
    }

    func testPopUpStyleBuildsAMenuOfAncestors() {
        MainActor.assumeIsolated {
            let w = window()
            let p = NSPathControl(frame: NSRect(x: 10, y: 60, width: 160, height: 22))
            p.pathStyle = .popUp
            p.url = URL(fileURLWithPath: "/Users/jane/Documents")
            let sink = ActionSink()
            p.target = sink; p.action = Selector(("act:"))
            w.contentView!.addSubview(p)
            XCTAssertEqual(p._popUpMenu().items.map(\.title), ["Documents", "jane", "Users", "/"])
            p.isEditable = true
            let menu = p._popUpMenu()
            XCTAssertEqual(menu.items.map(\.title), ["Choose…", "", "Documents", "jane", "Users", "/"])
            // Choosing an ancestor sets the URL and sends the action.
            let item = menu.items[3]
            _ = ActionRegistry.perform(item.action!, on: item.target!, with: item)
            XCTAssertEqual(p.url, URL(fileURLWithPath: "/Users/jane"))
            XCTAssertEqual(p.clickedPathItem?.title, "jane")
            XCTAssertEqual(sink.count, 1)
            // The pop-up draws the last component only, with the bezel.
            let rects = p.pathComponentCells().map { p._pathCell!.rect(of: $0, withFrame: p.bounds, in: p) }
            XCTAssertTrue(rects.dropLast().allSatisfy(\.isEmpty))
            XCTAssertFalse(rects.last!.isEmpty)
            XCTAssertEqual(p.accessibilityRole(), .popUpButton)
            XCTAssertEqual(p.accessibilityValue() as? String, "jane")
            guard let img = image(w) else { return XCTFail("no image") }
            var chevronInk = 0
            for y in 64...78 where !isWhite(pixel(img, 159, CGFloat(y))) { chevronInk += 1 }
            XCTAssertGreaterThan(chevronInk, 0, "the chevron strip is drawn")
            // A custom menu replaces the built one.
            let custom = NSMenu(title: "")
            custom.addItem(NSMenuItem(title: "Only", action: nil, keyEquivalent: ""))
            p.menu = custom
            XCTAssertTrue(p._popUpMenu() === custom)
            w.close()
        }
    }
}

// MARK: - SwiftUI

@MainActor
private func host<V: View>(_ view: V) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}
@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

final class SwiftUIEverydayControlsTests: XCTestCase, @unchecked Sendable {
    struct Progress: View {
        var value: Double?
        var body: some View {
            VStack {
                ProgressView(value: value, total: 2)
                ProgressView("Working").progressViewStyle(.circular)
            }
        }
    }

    func testProgressViewHostsTheIndicator() {
        MainActor.assumeIsolated {
            let (w, h) = host(Progress(value: 1))
            let indicators = allViews(h).compactMap { $0 as? NSProgressIndicator }
            XCTAssertEqual(indicators.count, 2)
            let bar = indicators.first { $0.style == .bar }, spinner = indicators.first { $0.style == .spinning }
            XCTAssertNotNil(bar); XCTAssertNotNil(spinner)
            XCTAssertEqual(bar?.isIndeterminate, false)
            XCTAssertEqual(bar?.doubleValue, 1); XCTAssertEqual(bar?.maxValue, 2)
            XCTAssertGreaterThan(bar?.frame.width ?? 0, 100, "the bar takes the proposed width")
            XCTAssertEqual(spinner?.isIndeterminate, true)
            XCTAssertEqual(spinner?._isAnimating, true)
            let labels = allViews(h).compactMap { $0 as? _TextView }.map { $0.storage.string }
            XCTAssertEqual(labels, ["Working"])
            h.rootView = Progress(value: nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(bar?.isIndeterminate, true, "no value: indeterminate, in place")
            XCTAssertEqual(bar?._isAnimating, true)
            w.close()
        }
    }

    struct Counter: View {
        @State var count = 3
        @State var when = date(2026, 11, 10, 12, 0)
        var body: some View {
            VStack {
                Stepper("Count \(count)", value: $count, in: 0...5)
                DatePicker("When", selection: $when, in: date(2026, 1, 1)..., displayedComponents: [.date])
            }
        }
    }

    func testStepperAndDatePickerBindings() {
        MainActor.assumeIsolated {
            let (w, h) = host(Counter())
            guard let stepper = allViews(h).compactMap({ $0 as? NSStepper }).first else { return XCTFail("no stepper") }
            XCTAssertEqual(stepper.doubleValue, 3); XCTAssertEqual(stepper.maxValue, 5)
            stepper._step(1)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(allViews(h).compactMap { $0 as? _TextView }.map { $0.storage.string }.first, "Count 4")
            stepper._step(1); stepper._step(1)
            XCTAssertEqual(stepper.doubleValue, 5, "clamped at the bound")
            guard let picker = allViews(h).compactMap({ $0 as? NSDatePicker }).first else { return XCTFail("no picker") }
            XCTAssertEqual(picker.dateValue, date(2026, 11, 10, 12, 0))
            XCTAssertEqual(picker.datePickerElements, [.yearMonthDay])
            XCTAssertEqual(picker.minDate, date(2026, 1, 1)); XCTAssertNil(picker.maxDate)
            picker.dateValue = date(2026, 12, 1)
            _ = picker.sendAction(picker.action, to: picker.target)
            h.layoutSubtreeIfNeeded()
            let n = (h.hostingRoot as? _ViewRoot)?.firstNode { $0.viewType == Counter.self }
            XCTAssertNotNil(n)
            XCTAssertEqual(picker.dateValue, date(2026, 12, 1))
            w.close()
        }
    }
}
