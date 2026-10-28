// NSScroller (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller
@MainActor open class NSScroller: NSControl {
    // MARK: Storage
    private var _knobProportion: CGFloat = 1
    private var _scrollerStyle: NSScroller.Style = .legacy
    private var _knobStyle: NSScroller.KnobStyle = .default
    private var _arrowsPosition: NSScroller.ArrowPosition = .scrollerArrowsNone
    private var _controlTint: NSControlTint = .defaultControlTint
    private var _hitPart: NSScroller.Part = .noPart
    private var _isHorizontal = false
    private var _dragOffset: CGFloat = 0
    private var _isHighlighted = false

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSActionCell(textCell: "") }

    /// Decided from the frame at creation, as AppKit does.
    internal var _horizontal: Bool { _isHorizontal }

    private static let minimumKnobLength: CGFloat = 20

    @MainActor private func _knobRect(in slot: NSRect) -> NSRect {
        let length = _isHorizontal ? slot.width : slot.height
        let knobLength = max(NSScroller.minimumKnobLength, (length * min(max(_knobProportion, 0), 1)).rounded())
        let travel = max(0, length - knobLength)
        let value = min(max(doubleValue, 0), 1)
        if _isHorizontal {
            return NSRect(x: slot.minX + travel * CGFloat(value), y: slot.minY, width: knobLength, height: slot.height)
        }
        // Value 0 is the top in both orientations; in a y-up view the top is maxY.
        let y = isFlipped ? slot.minY + travel * CGFloat(value) : slot.maxY - knobLength - travel * CGFloat(value)
        return NSRect(x: slot.minX, y: y, width: slot.width, height: knobLength)
    }

    @MainActor private func _value(forKnobOrigin p: CGFloat, in slot: NSRect) -> Double {
        let knob = rect(for: .knob)
        let length = _isHorizontal ? slot.width : slot.height
        let knobLength = _isHorizontal ? knob.width : knob.height
        let travel = max(1, length - knobLength)
        if _isHorizontal { return Double(min(max((p - slot.minX) / travel, 0), 1)) }
        return isFlipped ? Double(min(max((p - slot.minY) / travel, 0), 1)) : Double(min(max((slot.maxY - knobLength - p) / travel, 0), 1))
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        drawKnobSlot(in: rect(for: .knobSlot), highlight: _isHighlighted)
        if _knobProportion < 1 { drawKnob() }
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        _hitPart = testPart(p)
        switch _hitPart {
        case .knob:
            let knob = rect(for: .knob)
            _dragOffset = _isHorizontal ? p.x - knob.minX : p.y - knob.minY
            _isHighlighted = true
            needsDisplay = true
        case .decrementPage, .incrementPage:
            let delta = _knobProportion * (_hitPart == .incrementPage ? 1 : -1)
            doubleValue = min(max(doubleValue + Double(delta), 0), 1)
            needsDisplay = true
            _fireAction()
        default:
            break
        }
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _hitPart == .knob else { return }
        let p = convert(event.locationInWindow, from: nil)
        let slot = rect(for: .knobSlot)
        let origin = (_isHorizontal ? p.x : p.y) - _dragOffset
        let v = _value(forKnobOrigin: origin, in: slot)
        if v != doubleValue {
            doubleValue = v
            needsDisplay = true
            _fireAction()
        }
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        _hitPart = .noPart
        _isHighlighted = false
        needsDisplay = true
    }

    @MainActor open override func scrollWheel(with event: NSEvent) {
        (superview as? NSScrollView)?.scrollWheel(with: event)
    }

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _isHorizontal = frameRect.width > frameRect.height
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/arrowsposition
    @MainActor open var arrowsPosition: NSScroller.ArrowPosition {
        get { _arrowsPosition }
        set { _arrowsPosition = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/checkspaceforparts()
    @MainActor open func checkSpaceForParts() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/controlsize
    @MainActor open override var controlSize: NSControl.ControlSize {
        get { super.controlSize }
        set { super.controlSize = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/controltint
    @MainActor open var controlTint: NSControlTint {
        get { _controlTint }
        set { _controlTint = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/drawarrow(_:highlight:)
    @MainActor open func drawArrow(_ whichArrow: NSScroller.Arrow, highlight flag: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/drawknob()
    @MainActor open func drawKnob() {
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        let radius = min(knob.width, knob.height) / 2
        (_isHighlighted ? NSColor.selectedKnobColor : NSColor.knobColor).withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: knob.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius).fill()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/drawknobslot(in:highlight:)
    @MainActor open func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        NSColor.scrollBarColor.withAlphaComponent(0.12).setFill()
        NSBezierPath.fill(bounds)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/highlight(_:)
    @MainActor open func highlight(_ flag: Bool) { _isHighlighted = flag; needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/hitpart
    @MainActor open var hitPart: NSScroller.Part { _hitPart }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/iscompatiblewithoverlayscrollers
    @MainActor class public var isCompatibleWithOverlayScrollers: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/knobproportion
    @MainActor open var knobProportion: CGFloat {
        get { _knobProportion }
        set { _knobProportion = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/knobstyle
    @MainActor open var knobStyle: NSScroller.KnobStyle {
        get { _knobStyle }
        set { _knobStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle
    @MainActor class public var preferredScrollerStyle: NSScroller.Style { NSScroller.Style(rawValue: 1)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyledidchangenotification
    static public var preferredScrollerStyleDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSPreferredScrollerStyleDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/rect(for:)
    @MainActor open func rect(for partCode: NSScroller.Part) -> NSRect {
        let slot = bounds.insetBy(dx: 2, dy: 2)
        switch partCode {
        case .knobSlot: return slot
        case .knob: return _knobProportion < 1 ? _knobRect(in: slot) : .zero
        case .decrementPage, .incrementPage:
            let knob = _knobRect(in: slot)
            let before = partCode == .decrementPage
            if _isHorizontal {
                return before ? NSRect(x: slot.minX, y: slot.minY, width: max(0, knob.minX - slot.minX), height: slot.height)
                              : NSRect(x: knob.maxX, y: slot.minY, width: max(0, slot.maxX - knob.maxX), height: slot.height)
            }
            // "decrement" is towards the top.
            let topSide = isFlipped ? NSRect(x: slot.minX, y: slot.minY, width: slot.width, height: max(0, knob.minY - slot.minY))
                                    : NSRect(x: slot.minX, y: knob.maxY, width: slot.width, height: max(0, slot.maxY - knob.maxY))
            let bottomSide = isFlipped ? NSRect(x: slot.minX, y: knob.maxY, width: slot.width, height: max(0, slot.maxY - knob.maxY))
                                       : NSRect(x: slot.minX, y: slot.minY, width: slot.width, height: max(0, knob.minY - slot.minY))
            return before ? topSide : bottomSide
        default: return .zero
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/scrollerstyle
    @MainActor open var scrollerStyle: NSScroller.Style {
        get { _scrollerStyle }
        set { _scrollerStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/scrollerwidth(for:scrollerstyle:)
    @MainActor public class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        if scrollerStyle == .overlay { return 12 }
        switch controlSize {
        case .small: return 11
        case .mini: return 9
        default: return 15
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/testpart(_:)
    @MainActor open func testPart(_ point: NSPoint) -> NSScroller.Part {
        guard bounds.contains(point) else { return .noPart }
        if rect(for: .knob).contains(point) { return .knob }
        if rect(for: .decrementPage).contains(point) { return .decrementPage }
        if rect(for: .incrementPage).contains(point) { return .incrementPage }
        return .knobSlot
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/trackknob(with:)
    @MainActor open func trackKnob(with event: NSEvent) { mouseDown(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/trackscrollbuttons(with:)
    @MainActor open func trackScrollButtons(with event: NSEvent) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscroller/usableparts
    @MainActor open var usableParts: NSScroller.UsableParts { _knobProportion < 1 ? .allScrollerParts : .onlyScrollerArrows }
}
