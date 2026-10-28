// NSSliderCell (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell
@MainActor open class NSSliderCell: NSActionCell {
    // MARK: Storage
    private var _minValue: Double = 0
    private var _maxValue: Double = 1
    private var _altIncrementValue: Double = -1
    private var _numberOfTickMarks = 0
    private var _tickMarkPosition: NSSlider.TickMarkPosition = .below
    private var _allowsTickMarkValuesOnly = false
    private var _sliderType: NSSlider.SliderType = .linear
    private var _isVertical = false
    private var _knobThickness: CGFloat = 15
    internal var _trackRect = NSRect.zero

    @MainActor internal var _fraction: Double {
        let span = _maxValue - _minValue
        guard span > 0 else { return 0 }
        return min(max((doubleValue - _minValue) / span, 0), 1)
    }

    @MainActor internal func _value(forFraction f: Double) -> Double {
        let v = _minValue + (_maxValue - _minValue) * min(max(f, 0), 1)
        return _allowsTickMarkValuesOnly && _numberOfTickMarks > 1 ? closestTickMarkValue(toValue: v) : v
    }

    /// Value for a point in the control's bounds.
    @MainActor internal func _value(at point: NSPoint, in bounds: NSRect, flipped: Bool) -> Double {
        let bar = barRect(flipped: flipped)
        let half = _knobThickness / 2
        if _isVertical {
            let usable = max(1, bar.height - _knobThickness)
            let t = flipped ? (bar.maxY - half - point.y) / usable : (point.y - bar.minY - half) / usable
            return _value(forFraction: Double(t))
        }
        let usable = max(1, bar.width - _knobThickness)
        return _value(forFraction: Double((point.x - bar.minX - half) / usable))
    }

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        _trackRect = cellFrame.insetBy(dx: _isVertical ? 0 : 2, dy: _isVertical ? 2 : 0)
        let flipped = controlView.isFlipped
        drawBar(inside: barRect(flipped: flipped), flipped: flipped)
        drawTickMarks()
        drawKnob(knobRect(flipped: flipped))
    }

    @MainActor open override var cellSize: NSSize { _isVertical ? NSSize(width: _knobThickness + 6, height: 100) : NSSize(width: 100, height: _knobThickness + 6) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/allowstickmarkvaluesonly
    @MainActor open var allowsTickMarkValuesOnly: Bool {
        get { _allowsTickMarkValuesOnly }
        set { _allowsTickMarkValuesOnly = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/altincrementvalue
    @MainActor open var altIncrementValue: Double {
        get { _altIncrementValue }
        set { _altIncrementValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/barrect(flipped:)
    @MainActor open func barRect(flipped: Bool) -> NSRect {
        let b = _trackRect
        if _isVertical { return NSRect(x: b.midX - 2, y: b.minY, width: 4, height: b.height) }
        return NSRect(x: b.minX, y: b.midY - 2, width: b.width, height: 4)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/closesttickmarkvalue(tovalue:)
    @MainActor open func closestTickMarkValue(toValue value: Double) -> Double {
        guard _numberOfTickMarks > 1 else { return value }
        return (0..<_numberOfTickMarks).map { tickMarkValue(at: $0) }.min { abs($0 - value) < abs($1 - value) } ?? value
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/drawbar(inside:flipped:)
    @MainActor open func drawBar(inside rect: NSRect, flipped: Bool) {
        let r = rect.height / 2
        NSColor.scrollBarColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: rect, xRadius: _isVertical ? rect.width / 2 : r, yRadius: _isVertical ? rect.width / 2 : r).fill()
        // Filled portion up to the knob.
        let knob = knobRect(flipped: flipped)
        var filled = rect
        if _isVertical {
            if flipped { filled = NSRect(x: rect.minX, y: knob.midY, width: rect.width, height: rect.maxY - knob.midY) }
            else { filled = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: knob.midY - rect.minY) }
        } else {
            filled.size.width = max(0, knob.midX - rect.minX)
        }
        (_isEnabled ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.4)).setFill()
        NSBezierPath(roundedRect: filled, xRadius: r, yRadius: r).fill()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/drawknob()
    @MainActor open func drawKnob() { drawKnob(knobRect(flipped: _controlView?.isFlipped ?? false)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/drawknob(_:)
    @MainActor open func drawKnob(_ knobRect: NSRect) {
        let r = knobRect.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: r)
        (_isEnabled ? NSColor.controlColor : NSColor.controlColor.withAlphaComponent(0.6)).setFill()
        path.fill()
        (_isHighlighted ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.8)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/drawtickmarks()
    @MainActor open func drawTickMarks() {
        guard _numberOfTickMarks > 1 else { return }
        NSColor.secondaryLabelColor.withAlphaComponent(0.6).setFill()
        for i in 0..<_numberOfTickMarks { NSBezierPath.fill(rectOfTickMark(at: i)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/indexoftickmark(at:)
    @MainActor open func indexOfTickMark(at point: NSPoint) -> Int {
        (0..<_numberOfTickMarks).first { rectOfTickMark(at: $0).insetBy(dx: -3, dy: -3).contains(point) } ?? NSNotFound
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/knobrect(flipped:)
    @MainActor open func knobRect(flipped: Bool) -> NSRect {
        let bar = barRect(flipped: flipped)
        let t = CGFloat(_fraction)
        let k = _knobThickness
        if _isVertical {
            let travel = max(0, bar.height - k)
            let y = flipped ? bar.maxY - k - travel * t : bar.minY + travel * t
            return NSRect(x: bar.midX - k / 2, y: y, width: k, height: k)
        }
        let travel = max(0, bar.width - k)
        return NSRect(x: bar.minX + travel * t, y: bar.midY - k / 2, width: k, height: k)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/knobthickness
    @MainActor open var knobThickness: CGFloat {
        get { _knobThickness }
        set { _knobThickness = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/maxvalue
    @MainActor open var maxValue: Double {
        get { _maxValue }
        set { _maxValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/minvalue
    @MainActor open var minValue: Double {
        get { _minValue }
        set { _minValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/numberoftickmarks
    @MainActor open var numberOfTickMarks: Int {
        get { _numberOfTickMarks }
        set { _numberOfTickMarks = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/preferstrackinguntilmouseup
    @MainActor class public override var prefersTrackingUntilMouseUp: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/rectoftickmark(at:)
    @MainActor open func rectOfTickMark(at index: Int) -> NSRect {
        guard _numberOfTickMarks > 1 else { return .zero }
        let bar = barRect(flipped: _controlView?.isFlipped ?? false)
        let t = CGFloat(index) / CGFloat(_numberOfTickMarks - 1)
        let k = _knobThickness
        if _isVertical {
            let y = bar.minY + k / 2 + (bar.height - k) * t
            let x = _tickMarkPosition == .leading ? bar.minX - 8 : bar.maxX + 4
            return NSRect(x: x, y: y - 0.5, width: 4, height: 1)
        }
        let x = bar.minX + k / 2 + (bar.width - k) * t
        let flipped = _controlView?.isFlipped ?? false
        let below = _tickMarkPosition == .below
        let y = (below != flipped) ? bar.minY - 8 : bar.maxY + 4
        return NSRect(x: x - 0.5, y: y, width: 1, height: 4)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/slidertype
    @MainActor open var sliderType: NSSlider.SliderType {
        get { _sliderType }
        set { _sliderType = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/tickmarkposition
    @MainActor open var tickMarkPosition: NSSlider.TickMarkPosition {
        get { _tickMarkPosition }
        set { _tickMarkPosition = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/tickmarkvalue(at:)
    @MainActor open func tickMarkValue(at index: Int) -> Double {
        guard _numberOfTickMarks > 1 else { return _minValue }
        return _minValue + (_maxValue - _minValue) * Double(index) / Double(_numberOfTickMarks - 1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/trackrect
    @MainActor open var trackRect: NSRect { _trackRect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsslidercell/vertical
    @available(macOS 10.11, *)
    open var vertical: Bool {
        get { MainActor.assumeIsolated { _isVertical } }
        set { MainActor.assumeIsolated { _isVertical = newValue; _changed() } }
    }
    // DUPLICATE: open var vertical: Bool
}
