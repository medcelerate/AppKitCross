// NSLevelIndicatorCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The four styles: relevancy (a hatched bar), continuous capacity (one bar coloured by
// the value against the warning and critical levels), discrete capacity (one segment per
// unit of the range) and rating (stars, or the control's images). Tick marks sit below
// (or above) the bar as on a slider.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell
@MainActor open class NSLevelIndicatorCell: NSActionCell {
    // MARK: Storage
    private var _style: NSLevelIndicator.Style = .discreteCapacity
    private var _minValue: Double = 0
    private var _maxValue: Double = 10
    private var _warningValue: Double = 6
    private var _criticalValue: Double = 8
    private var _numberOfTickMarks = 0
    private var _numberOfMajorTickMarks = 0
    private var _tickMarkPosition: NSSlider.TickMarkPosition = .below
    internal var _fillColor: NSColor? = nil
    internal var _warningFillColor: NSColor? = nil
    internal var _criticalFillColor: NSColor? = nil
    internal var _drawsTieredCapacityLevels = false
    internal var _placeholderVisibility: NSLevelIndicator.PlaceholderVisibility = .automatic
    internal var _ratingImage: NSImage? = nil
    internal var _ratingPlaceholderImage: NSImage? = nil
    internal var _editable = false
    /// The frame the bar was last drawn in (tick marks are laid out against it).
    internal var _barRect = NSRect.zero
    internal var _lastCellFrame = NSRect.zero

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/init(levelindicatorstyle:)
    @MainActor public init(levelIndicatorStyle: NSLevelIndicator.Style) {
        super.init(textCell: "")
        _style = levelIndicatorStyle
        _objectValue = 0.0
        _isContinuous = true
    }
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _objectValue = 0.0
        _isContinuous = true
    }
    // Required by the superclass (NSCoding).
    @MainActor public required init(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Values

    internal var _span: Double { max(0, _maxValue - _minValue) }
    internal var _fraction: Double {
        guard _span > 0 else { return 0 }
        return min(max((doubleValue - _minValue) / _span, 0), 1)
    }
    /// Discrete styles count whole units above the minimum.
    internal var _units: Int { max(0, Int(_span.rounded(.down))) }
    internal var _filledUnits: Int { min(_units, max(0, Int((doubleValue - _minValue).rounded()))) }

    /// The fill colour for a value: critical, warning or the plain fill.
    internal func _color(for value: Double) -> NSColor {
        if value >= _criticalValue { return _criticalFillColor ?? .systemRed }
        if value >= _warningValue { return _warningFillColor ?? .systemYellow }
        return _fillColor ?? .systemGreen
    }

    /// The value at a point in the bar, as a click or drag sets it: discrete styles round
    /// up to the unit under the pointer (so a click on the first star gives 1).
    @MainActor internal func _value(at point: NSPoint, in cellFrame: NSRect, rightToLeft: Bool) -> Double {
        let bar = _barRect(forBounds: cellFrame)
        guard bar.width > 0 else { return _minValue }
        var t = Double((point.x - bar.minX) / bar.width)
        if rightToLeft { t = 1 - t }
        t = min(max(t, 0), 1)
        switch _style {
        case .discreteCapacity, .rating:
            return _minValue + Double(min(_units, Int((t * Double(_units)).rounded(.up))))
        default:
            return _minValue + _span * t
        }
    }

    // MARK: Geometry

    /// The bar inside the cell frame: the tick marks take 6 pt on their side when present.
    @MainActor internal func _barRect(forBounds rect: NSRect) -> NSRect {
        var r = rect
        if _numberOfTickMarks > 0 {
            let flipped = _controlView?.isFlipped ?? false
            let below = _tickMarkPosition == .below
            if below != flipped { r.origin.y += 6 }
            r.size.height = max(0, r.height - 6)
        }
        switch _style {
        case .rating:
            let s = _ratingStarSize
            return NSRect(x: r.minX, y: r.midY - s / 2, width: s * CGFloat(_units), height: s)
        case .relevancy:
            return r.insetBy(dx: 0, dy: max(0, (r.height - 12) / 2))
        default:
            return r.insetBy(dx: 0, dy: max(0, (r.height - 14) / 2))
        }
    }
    internal var _ratingStarSize: CGFloat {
        switch _controlSize { case .small: return 12; case .mini: return 10; default: return 15 }
    }

    @MainActor open override var cellSize: NSSize {
        let tick: CGFloat = _numberOfTickMarks > 0 ? 6 : 0
        switch _style {
        case .rating: return NSSize(width: _ratingStarSize * CGFloat(_units), height: _ratingStarSize + tick + 2)
        case .relevancy: return NSSize(width: 100, height: 12 + tick)
        default: return NSSize(width: 100, height: 14 + tick)
        }
    }

    // MARK: Drawing

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        _lastCellFrame = cellFrame
        let bar = _barRect(forBounds: cellFrame)
        _barRect = bar
        let rtl = controlView.userInterfaceLayoutDirection == .rightToLeft
        switch _style {
        case .relevancy: _drawRelevancy(in: bar, rightToLeft: rtl)
        case .continuousCapacity: _drawContinuous(in: bar, rightToLeft: rtl)
        case .discreteCapacity: _drawDiscrete(in: bar, rightToLeft: rtl)
        case .rating: _drawRating(in: bar, rightToLeft: rtl)
        }
        _drawTickMarks()
    }

    private var _trackColor: NSColor { NSColor.scrollBarColor.withAlphaComponent(0.25) }
    private var _enabledAlpha: CGFloat { _isEnabled ? 1 : 0.45 }

    private func _filledRect(_ bar: NSRect, fraction: CGFloat, rightToLeft: Bool) -> NSRect {
        var f = bar
        f.size.width = bar.width * fraction
        if rightToLeft { f.origin.x = bar.maxX - f.width }
        return f
    }

    private func _drawRelevancy(in bar: NSRect, rightToLeft: Bool) {
        guard bar.width > 0 else { return }
        _trackColor.setFill()
        NSBezierPath.fill(bar)
        // Fine vertical lines whose spacing tightens towards the full end.
        let filled = _filledRect(bar, fraction: CGFloat(_fraction), rightToLeft: rightToLeft)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: filled).addClip()
        NSColor.secondaryLabelColor.withAlphaComponent(0.7 * _enabledAlpha).setFill()
        var x = bar.minX + 1
        var step: CGFloat = 2
        while x < bar.maxX {
            NSBezierPath.fill(NSRect(x: x.rounded(), y: bar.minY + 1, width: 1, height: bar.height - 2))
            x += step
            step = min(5, step + 0.15)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func _drawContinuous(in bar: NSRect, rightToLeft: Bool) {
        guard bar.width > 0 else { return }
        let r: CGFloat = 2
        _trackColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: r, yRadius: r).fill()
        let f = CGFloat(_fraction)
        guard f > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bar, xRadius: r, yRadius: r).addClip()
        if _drawsTieredCapacityLevels && _span > 0 {
            // Each tier keeps its own colour: green up to the warning level, yellow up
            // to the critical level, red above it.
            let bounds = [_minValue, min(_warningValue, _criticalValue), _criticalValue, _maxValue]
            var start = 0.0
            for (i, end) in bounds.dropFirst().enumerated() {
                let a = max(start, bounds[i]), b = min(doubleValue, end)
                if b > a {
                    let fa = CGFloat((a - _minValue) / _span), fb = CGFloat((b - _minValue) / _span)
                    var seg = bar
                    seg.origin.x = rightToLeft ? bar.maxX - bar.width * fb : bar.minX + bar.width * fa
                    seg.size.width = bar.width * (fb - fa)
                    _color(for: a).withAlphaComponent(_enabledAlpha).setFill()
                    NSBezierPath.fill(seg)
                }
                start = end
            }
        } else {
            _color(for: doubleValue).withAlphaComponent(_enabledAlpha).setFill()
            NSBezierPath.fill(_filledRect(bar, fraction: f, rightToLeft: rightToLeft))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The rect of one segment (0-based, counted from the leading edge).
    @MainActor internal func _segmentRect(_ i: Int, in bar: NSRect, rightToLeft: Bool) -> NSRect {
        let n = max(1, _units)
        let gap: CGFloat = 1
        let w = (bar.width - gap * CGFloat(n - 1)) / CGFloat(n)
        let x = rightToLeft ? bar.maxX - CGFloat(i + 1) * w - CGFloat(i) * gap : bar.minX + CGFloat(i) * (w + gap)
        return NSRect(x: x, y: bar.minY, width: w, height: bar.height)
    }

    private func _drawDiscrete(in bar: NSRect, rightToLeft: Bool) {
        guard bar.width > 0, _units > 0 else { return }
        let filled = _filledUnits
        for i in 0..<_units {
            let seg = _segmentRect(i, in: bar, rightToLeft: rightToLeft)
            let path = NSBezierPath(roundedRect: seg, xRadius: 1.5, yRadius: 1.5)
            if i < filled {
                // The segment's own level decides its colour when tiered; else the value's.
                let level = _drawsTieredCapacityLevels ? _minValue + Double(i) : doubleValue
                _color(for: level).withAlphaComponent(_enabledAlpha).setFill()
            } else {
                _trackColor.setFill()
            }
            path.fill()
        }
    }

    private func _drawRating(in bar: NSRect, rightToLeft: Bool) {
        guard _units > 0 else { return }
        let s = _ratingStarSize
        let filled = _filledUnits
        let editing = (_controlView?.window?.firstResponder === _controlView)
        let showPlaceholders: Bool
        switch _placeholderVisibility {
        case .always: showPlaceholders = true
        case .whileEditing: showPlaceholders = editing
        case .automatic: showPlaceholders = _editable
        }
        for i in 0..<_units {
            let x = rightToLeft ? bar.maxX - CGFloat(i + 1) * s : bar.minX + CGFloat(i) * s
            let box = NSRect(x: x, y: bar.minY, width: s, height: s).insetBy(dx: 1, dy: 1)
            if i < filled {
                if let img = _ratingImage { img.draw(in: box) }
                else { _drawStar(in: box, color: (_fillColor ?? NSColor.controlAccentColor).withAlphaComponent(_enabledAlpha), filled: true) }
            } else if showPlaceholders {
                if let img = _ratingPlaceholderImage { img.draw(in: box) }
                else { _drawStar(in: box, color: NSColor.secondaryLabelColor.withAlphaComponent(0.5 * _enabledAlpha), filled: false) }
            }
        }
    }

    private func _drawStar(in box: NSRect, color: NSColor, filled: Bool) {
        let c = NSPoint(x: box.midX, y: box.midY)
        let outer = box.width / 2, inner = outer * 0.45
        let flipped = _controlView?.isFlipped ?? false
        let p = NSBezierPath()
        for k in 0..<10 {
            let angle = CGFloat.pi / 2 + CGFloat(k) * .pi / 5
            let r = k % 2 == 0 ? outer : inner
            let dy: CGFloat = flipped ? -1 : 1
            let pt = NSPoint(x: c.x + cos(angle) * r, y: c.y + dy * sin(angle) * r)
            if k == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close()
        if filled { color.setFill(); p.fill() }
        else { color.setStroke(); p.lineWidth = 1; p.stroke() }
    }

    private func _drawTickMarks() {
        guard _numberOfTickMarks > 0 else { return }
        NSColor.secondaryLabelColor.withAlphaComponent(0.6 * _enabledAlpha).setFill()
        for i in 0..<_numberOfTickMarks { NSBezierPath.fill(rectOfTickMark(at: i)) }
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/criticalvalue
    @MainActor open var criticalValue: Double {
        get { _criticalValue }
        set { _criticalValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/levelindicatorstyle
    @MainActor open var levelIndicatorStyle: NSLevelIndicator.Style {
        get { _style }
        set { _style = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/maxvalue
    @MainActor open var maxValue: Double {
        get { _maxValue }
        set { _maxValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/minvalue
    @MainActor open var minValue: Double {
        get { _minValue }
        set { _minValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/numberofmajortickmarks
    @MainActor open var numberOfMajorTickMarks: Int {
        get { _numberOfMajorTickMarks }
        set { _numberOfMajorTickMarks = max(0, newValue); _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/numberoftickmarks
    @MainActor open var numberOfTickMarks: Int {
        get { _numberOfTickMarks }
        set { _numberOfTickMarks = max(0, newValue); _changed() }
    }
    /// Major tick marks are taller; the `numberOfMajorTickMarks` evenly spaced ones count as major.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/rectoftickmark(at:)
    @MainActor open func rectOfTickMark(at index: Int) -> NSRect {
        guard _numberOfTickMarks > 0, index >= 0, index < _numberOfTickMarks else { return .zero }
        let bar = _barRect.isEmpty ? _barRect(forBounds: _lastCellFrame) : _barRect
        let t = _numberOfTickMarks > 1 ? CGFloat(index) / CGFloat(_numberOfTickMarks - 1) : 0
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        let x = rtl ? bar.maxX - bar.width * t : bar.minX + bar.width * t
        let flipped = _controlView?.isFlipped ?? false
        let below = _tickMarkPosition == .below
        let major = _isMajorTickMark(index)
        let h: CGFloat = major ? 5 : 3
        let y = (below != flipped) ? bar.minY - 1 - h : bar.maxY + 1
        return NSRect(x: min(max(x - 0.5, bar.minX), bar.maxX - 1), y: y, width: 1, height: h)
    }
    private func _isMajorTickMark(_ index: Int) -> Bool {
        guard _numberOfMajorTickMarks > 1, _numberOfTickMarks > 1 else { return _numberOfMajorTickMarks == 1 && index == 0 }
        let spacing = Double(_numberOfTickMarks - 1) / Double(_numberOfMajorTickMarks - 1)
        let k = (Double(index) / spacing).rounded()
        return abs(k * spacing - Double(index)) < 1e-6
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/tickmarkposition
    @MainActor open var tickMarkPosition: NSSlider.TickMarkPosition {
        get { _tickMarkPosition }
        set { _tickMarkPosition = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/tickmarkvalue(at:)
    @MainActor open func tickMarkValue(at index: Int) -> Double {
        guard _numberOfTickMarks > 1 else { return _minValue }
        return _minValue + _span * Double(index) / Double(_numberOfTickMarks - 1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslevelindicatorcell/warningvalue
    @MainActor open var warningValue: Double {
        get { _warningValue }
        set { _warningValue = newValue; _changed() }
    }
}
