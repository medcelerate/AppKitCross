// NSStepperCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The value, its range and step live here; the stepper view tracks the mouse and the
// autorepeat timer and asks the cell which half (up or down) a point is in.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssteppercell
@MainActor open class NSStepperCell: NSActionCell {
    // MARK: Storage
    private var _minValue: Double = 0
    private var _maxValue: Double = 59
    private var _increment: Double = 1
    private var _autorepeat = true
    private var _valueWraps = false
    /// The half being pressed: +1 (up), -1 (down), 0 (none).
    internal var _pressedDirection = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssteppercell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _objectValue = 0.0
        _isContinuous = true
    }
    public required init(coder: NSCoder) { super.init(coder: coder) }

    /// The value after one step in `direction` (+1 / -1), clamped or wrapped.
    @MainActor internal func _stepped(_ direction: Int) -> Double {
        let next = doubleValue + Double(direction) * _increment
        if _valueWraps {
            if next > _maxValue { return _minValue }
            if next < _minValue { return _maxValue }
            return next
        }
        return min(max(next, _minValue), _maxValue)
    }

    /// +1 when `point` (in the cell frame's coordinates) is in the up half, -1 in the down half.
    @MainActor internal func _direction(at point: NSPoint, in cellFrame: NSRect, flipped: Bool) -> Int {
        guard cellFrame.contains(point) else { return 0 }
        let upper = point.y >= cellFrame.midY
        return (upper != flipped) ? 1 : -1
    }

    @MainActor open override var cellSize: NSSize {
        switch _controlSize {
        case .small: return NSSize(width: 13, height: 20)
        case .mini: return NSSize(width: 11, height: 16)
        default: return NSSize(width: 15, height: 24)
        }
    }

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        let flipped = controlView.isFlipped
        let r = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = min(5, r.width / 3)
        // Bezel.
        (_isEnabled ? NSColor.controlColor : NSColor.controlColor.withAlphaComponent(0.6)).setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        // The pressed half fills with the accent colour.
        if _pressedDirection != 0 {
            let topHalf = NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2)
            let bottomHalf = NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2)
            let upRect = flipped ? bottomHalf : topHalf
            let pressed = _pressedDirection > 0 ? upRect : (flipped ? topHalf : bottomHalf)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip()
            NSColor.controlAccentColor.setFill()
            NSBezierPath.fill(pressed)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
        // Divider between the halves.
        NSBezierPath.strokeLine(from: NSPoint(x: r.minX, y: r.midY), to: NSPoint(x: r.maxX, y: r.midY))
        // Chevrons: up in the up half, down in the down half.
        let w: CGFloat = max(2, r.width / 5), h: CGFloat = max(1.5, r.width / 7)
        let upY = flipped ? r.minY + r.height / 4 : r.maxY - r.height / 4
        let downY = flipped ? r.maxY - r.height / 4 : r.minY + r.height / 4
        let dir: CGFloat = flipped ? 1 : -1      // +1: y grows downwards
        let up = NSBezierPath(), down = NSBezierPath()
        up.move(to: NSPoint(x: r.midX - w, y: upY + dir * h / 2))
        up.line(to: NSPoint(x: r.midX, y: upY - dir * h / 2))
        up.line(to: NSPoint(x: r.midX + w, y: upY + dir * h / 2))
        down.move(to: NSPoint(x: r.midX - w, y: downY - dir * h / 2))
        down.line(to: NSPoint(x: r.midX, y: downY + dir * h / 2))
        down.line(to: NSPoint(x: r.midX + w, y: downY - dir * h / 2))
        for (p, pressed) in [(up, _pressedDirection > 0), (down, _pressedDirection < 0)] {
            (pressed ? NSColor.white : (_isEnabled ? NSColor.controlTextColor : NSColor.disabledControlTextColor)).setStroke()
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.stroke()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssteppercell/autorepeat
    @MainActor open var autorepeat: Bool {
        get { _autorepeat }
        set { _autorepeat = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssteppercell/increment
    @MainActor open var increment: Double {
        get { _increment }
        set { _increment = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssteppercell/maxvalue
    @MainActor open var maxValue: Double {
        get { _maxValue }
        set { _maxValue = newValue; if doubleValue > newValue { doubleValue = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssteppercell/minvalue
    @MainActor open var minValue: Double {
        get { _minValue }
        set { _minValue = newValue; if doubleValue < newValue { doubleValue = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssteppercell/valuewraps
    @MainActor open var valueWraps: Bool {
        get { _valueWraps }
        set { _valueWraps = newValue }
    }
}
