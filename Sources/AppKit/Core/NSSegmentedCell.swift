// NSSegmentedCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Holds the segments (label, image, width, state) and draws them: one rounded bezel for
// the whole control, separators between segments, the selected ones filled with the
// accent colour.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell
@MainActor open class NSSegmentedCell: NSActionCell {
    internal struct Segment {
        var label: String? = nil
        var image: NSImage? = nil
        var imageScaling: NSImageScaling = .scaleProportionallyDown
        var width: CGFloat = 0            // 0: fit the content
        var isEnabled = true
        var isSelected = false
        var tag = 0
        var toolTip: String? = nil
        var menu: NSMenu? = nil
        var alignment: NSTextAlignment = .center
        var showsMenuIndicator = false
    }
    internal var _segments: [Segment] = []
    private var _segmentStyle: NSSegmentedControl.Style = .automatic
    private var _trackingMode: NSSegmentedControl.SwitchTracking = .selectOne
    /// The segment under the mouse while it is held (momentary feedback).
    internal var _pressedSegment = -1
    /// The segment that has keyboard focus within the control.
    internal var _keySegment = -1

    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }
    public required init(coder: NSCoder) { super.init(coder: coder) }

    private func valid(_ segment: Int) -> Bool { _segments.indices.contains(segment) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/segmentcount
    @MainActor open var segmentCount: Int {
        get { _segments.count }
        set {
            let n = max(0, newValue)
            if n < _segments.count { _segments.removeLast(_segments.count - n) }
            else { _segments += Array(repeating: Segment(), count: n - _segments.count) }
            _changed()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/segmentstyle
    @MainActor open var segmentStyle: NSSegmentedControl.Style {
        get { _segmentStyle }
        set { _segmentStyle = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/trackingmode
    @MainActor open var trackingMode: NSSegmentedControl.SwitchTracking {
        get { _trackingMode }
        set { _trackingMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/selectedsegment
    @MainActor open var selectedSegment: Int {
        get { _segments.firstIndex { $0.isSelected } ?? -1 }
        set {
            for i in _segments.indices { _segments[i].isSelected = i == newValue }
            _changed()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/selectsegment(withtag:)
    @MainActor open func selectSegment(withTag tag: Int) -> Bool {
        guard let i = _segments.firstIndex(where: { $0.tag == tag }) else { return false }
        setSelected(true, forSegment: i)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/setselected(_:forsegment:)
    @MainActor open func setSelected(_ selected: Bool, forSegment segment: Int) {
        guard valid(segment) else { return }
        switch _trackingMode {
        case .selectOne:
            if selected { for i in _segments.indices { _segments[i].isSelected = i == segment } }
            else { _segments[segment].isSelected = false }
        case .selectAny:
            _segments[segment].isSelected = selected
        case .momentary, .momentaryAccelerator:
            _segments[segment].isSelected = selected
        }
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/isselected(forsegment:)
    @MainActor open func isSelected(forSegment segment: Int) -> Bool { valid(segment) && _segments[segment].isSelected }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/setenabled(_:forsegment:)
    @MainActor open func setEnabled(_ enabled: Bool, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].isEnabled = enabled; _changed() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/isenabled(forsegment:)
    @MainActor open func isEnabled(forSegment segment: Int) -> Bool { valid(segment) && _segments[segment].isEnabled }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/setimage(_:forsegment:)
    @MainActor open func setImage(_ image: NSImage?, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].image = image; _changed() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/image(forsegment:)
    @MainActor open func image(forSegment segment: Int) -> NSImage? { valid(segment) ? _segments[segment].image : nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/setimagescaling(_:forsegment:)
    @MainActor open func setImageScaling(_ scaling: NSImageScaling, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].imageScaling = scaling }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/imagescaling(forsegment:)
    @MainActor open func imageScaling(forSegment segment: Int) -> NSImageScaling { valid(segment) ? _segments[segment].imageScaling : .scaleProportionallyDown }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/setlabel(_:forsegment:)
    @MainActor open func setLabel(_ label: String, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].label = label; _changed() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/label(forsegment:)
    @MainActor open func label(forSegment segment: Int) -> String? { valid(segment) ? _segments[segment].label : nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/setmenu(_:forsegment:)
    @MainActor open func setMenu(_ menu: NSMenu?, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].menu = menu }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/menu(forsegment:)
    @MainActor open func menu(forSegment segment: Int) -> NSMenu? { valid(segment) ? _segments[segment].menu : nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/settag(_:forsegment:)
    @MainActor open func setTag(_ tag: Int, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].tag = tag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/tag(forsegment:)
    @MainActor open func tag(forSegment segment: Int) -> Int { valid(segment) ? _segments[segment].tag : 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/settooltip(_:forsegment:)
    @MainActor open func setToolTip(_ toolTip: String?, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].toolTip = toolTip }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/tooltip(forsegment:)
    @MainActor open func toolTip(forSegment segment: Int) -> String? { valid(segment) ? _segments[segment].toolTip : nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/setwidth(_:forsegment:)
    @MainActor open func setWidth(_ width: CGFloat, forSegment segment: Int) { guard valid(segment) else { return }; _segments[segment].width = max(0, width); _changed() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/width(forsegment:)
    @MainActor open func width(forSegment segment: Int) -> CGFloat { valid(segment) ? _segments[segment].width : 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/interiorbackgroundstyle(forsegment:)
    @MainActor open func interiorBackgroundStyle(forSegment segment: Int) -> NSView.BackgroundStyle { isSelected(forSegment: segment) ? .emphasized : .normal }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/makenextsegmentkey()
    @MainActor open func makeNextSegmentKey() {
        guard !_segments.isEmpty else { return }
        var i = _keySegment < 0 ? selectedSegment : _keySegment
        repeat { i = (i + 1) % _segments.count } while !_segments[i].isEnabled && i != _keySegment
        _keySegment = i
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/makeprevioussegmentkey()
    @MainActor open func makePreviousSegmentKey() {
        guard !_segments.isEmpty else { return }
        var i = _keySegment < 0 ? selectedSegment : _keySegment
        repeat { i = (i - 1 + _segments.count) % _segments.count } while !_segments[i].isEnabled && i != _keySegment
        _keySegment = i
        _changed()
    }

    // MARK: Layout

    /// The natural width of a segment's content plus padding.
    internal func _fittedWidth(_ segment: Int) -> CGFloat {
        guard valid(segment) else { return 0 }
        let s = _segments[segment]
        if s.width > 0 { return s.width }
        var w: CGFloat = 0
        if let l = s.label, !l.isEmpty { w += l.size(withAttributes: _textAttributes).width }
        if let img = s.image { w += img.size.width + (s.label?.isEmpty == false ? 4 : 0) }
        if s.showsMenuIndicator { w += 10 }
        return max(w + 20, 28)
    }

    /// Segment rects, in `frame`, laid out from the leading edge; with
    /// `distribution` the control may stretch them (see NSSegmentedControl).
    internal func _segmentRects(in frame: NSRect, distribution: NSSegmentedControl.Distribution) -> [NSRect] {
        guard !_segments.isEmpty else { return [] }
        var widths = _segments.indices.map(_fittedWidth)
        let total = widths.reduce(0, +)
        switch distribution {
        case .fillEqually:
            let each = frame.width / CGFloat(widths.count)
            widths = widths.map { _ in each }
        case .fill:
            if total < frame.width { let extra = (frame.width - total) / CGFloat(widths.count); widths = widths.map { $0 + extra } }
        case .fillProportionally:
            if total > 0 { widths = widths.map { $0 * frame.width / total } }
        case .fit:
            break
        }
        var rects: [NSRect] = []
        var x = frame.minX
        for w in widths {
            rects.append(NSRect(x: x, y: frame.minY, width: w, height: frame.height))
            x += w
        }
        return rects
    }

    @MainActor open override var cellSize: NSSize {
        let w = _segments.indices.reduce(CGFloat(0)) { $0 + _fittedWidth($1) }
        return NSSize(width: w + 2, height: 22)
    }

    // MARK: Drawing

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let frame = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = _segmentStyle == .capsule ? frame.height / 2 : 6
        let bezel = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        (_isEnabled ? NSColor.controlColor : NSColor.controlColor.withAlphaComponent(0.6)).setFill()
        bezel.fill()
        let rects = _segmentRects(in: frame, distribution: (controlView as? NSSegmentedControl)?.segmentDistribution ?? .fit)
        NSGraphicsContext.saveGraphicsState()
        bezel.addClip()
        for (i, r) in rects.enumerated() { drawSegment(i, inFrame: r, with: controlView) }
        NSGraphicsContext.restoreGraphicsState()
        (_isEnabled ? NSColor.separatorColor.withAlphaComponent(0.6) : NSColor.separatorColor.withAlphaComponent(0.3)).setStroke()
        bezel.lineWidth = 1
        bezel.stroke()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcell/drawsegment(_:inframe:with:)
    @MainActor open func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        guard valid(segment) else { return }
        let s = _segments[segment]
        let enabled = _isEnabled && s.isEnabled
        let selected = s.isSelected
        let pressed = segment == _pressedSegment
        if selected || pressed {
            let fill = selected ? (enabled ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.4)) : NSColor.selectedControlColor
            fill.setFill()
            NSBezierPath(roundedRect: frame.insetBy(dx: 1.5, dy: 1.5), xRadius: 4.5, yRadius: 4.5).fill()
        }
        // Separator before every segment but the first (hidden next to a selected segment).
        if segment > 0, !selected, !_segments[segment - 1].isSelected {
            NSColor.separatorColor.setFill()
            NSBezierPath(rect: NSRect(x: frame.minX, y: frame.minY + 5, width: 1, height: max(0, frame.height - 10))).fill()
        }
        var attrs = _textAttributes
        if !enabled { attrs[.foregroundColor] = NSColor.disabledControlTextColor }
        else if selected { attrs[.foregroundColor] = NSColor.white }
        var content = frame.insetBy(dx: 6, dy: 0)
        if let img = s.image {
            let h = min(img.size.height, content.height - 4)
            let w = img.size.height > 0 ? img.size.width * h / img.size.height : 0
            let labelWidth = s.label.map { $0.size(withAttributes: attrs).width } ?? 0
            let totalW = w + (labelWidth > 0 ? labelWidth + 4 : 0)
            let x = s.alignment == .left ? content.minX : s.alignment == .right ? content.maxX - totalW : content.midX - totalW / 2
            let imageRect = NSRect(x: x, y: content.midY - h / 2, width: w, height: h)
            img.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: enabled ? 1 : 0.5)
            content = NSRect(x: x + w + 4, y: content.minY, width: max(0, content.maxX - (x + w + 4)), height: content.height)
            if let l = s.label { _drawText(l, attributes: attrs, in: content, alignment: .left, flipped: controlView.isFlipped) }
        } else if let l = s.label {
            _drawText(l, attributes: attrs, in: content, alignment: s.alignment, flipped: controlView.isFlipped)
        }
        if segment == _keySegment, controlView.window?.firstResponder === controlView {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: frame.insetBy(dx: 2.5, dy: 2.5), xRadius: 4, yRadius: 4)
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}
