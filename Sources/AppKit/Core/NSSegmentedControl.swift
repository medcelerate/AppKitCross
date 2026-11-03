// NSSegmentedControl (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol
@MainActor open class NSSegmentedControl: NSControl, NSUserInterfaceCompression {
    private var _distribution: NSSegmentedControl.Distribution = .fill
    private var _selectedSegmentBezelColor: NSColor?
    private var _isSpringLoaded = false
    private var _borderShapeRawValue = 0
    private var _pressed = -1

    internal var _segmentedCell: NSSegmentedCell? { _cell as? NSSegmentedCell }
    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSSegmentedCell(textCell: "") }
    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/init(images:trackingmode:target:action:)
    @MainActor public convenience init(images: [NSImage], trackingMode: NSSegmentedControl.SwitchTracking, target: Any?, action: Selector?) {
        self.init(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        self.trackingMode = trackingMode
        segmentCount = images.count
        for (i, img) in images.enumerated() { setImage(img, forSegment: i) }
        self.target = target as AnyObject?
        self.action = action
        sizeToFit()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/init(labels:trackingmode:target:action:)
    @MainActor public convenience init(labels: [String], trackingMode: NSSegmentedControl.SwitchTracking, target: Any?, action: Selector?) {
        self.init(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        self.trackingMode = trackingMode
        segmentCount = labels.count
        for (i, l) in labels.enumerated() { setLabel(l, forSegment: i) }
        self.target = target as AnyObject?
        self.action = action
        sizeToFit()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/activecompressionoptions
    @MainActor open var activeCompressionOptions: NSUserInterfaceCompressionOptions { NSUserInterfaceCompressionOptions(identifier: "") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/alignment(forsegment:)
    @MainActor open func alignment(forSegment segment: Int) -> NSTextAlignment { _segmentedCell?._segments.indices.contains(segment) == true ? _segmentedCell!._segments[segment].alignment : .center }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/bordershape
    @available(macOS 26.0, *)
    @MainActor open var borderShape: NSControl.BorderShape {
        get { NSControl.BorderShape(rawValue: _borderShapeRawValue) ?? .automatic }
        set { _borderShapeRawValue = newValue.rawValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/compress(withprioritizedcompressionoptions:)
    @MainActor open func compress(withPrioritizedCompressionOptions prioritizedOptions: [NSUserInterfaceCompressionOptions]) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/doublevalueforselectedsegment
    @MainActor open var doubleValueForSelectedSegment: Double { Double(selectedSegment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/image(forsegment:)
    @MainActor open func image(forSegment segment: Int) -> NSImage? { _segmentedCell?.image(forSegment: segment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/imagescaling(forsegment:)
    @MainActor open func imageScaling(forSegment segment: Int) -> NSImageScaling { _segmentedCell?.imageScaling(forSegment: segment) ?? .scaleProportionallyDown }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/indexofselecteditem
    @MainActor open var indexOfSelectedItem: Int { selectedSegment }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/isenabled(forsegment:)
    @MainActor open func isEnabled(forSegment segment: Int) -> Bool { _segmentedCell?.isEnabled(forSegment: segment) ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/isselected(forsegment:)
    @MainActor open func isSelected(forSegment segment: Int) -> Bool { _segmentedCell?.isSelected(forSegment: segment) ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/isspringloaded
    @MainActor open var isSpringLoaded: Bool {
        get { _isSpringLoaded }
        set { _isSpringLoaded = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/label(forsegment:)
    @MainActor open func label(forSegment segment: Int) -> String? { _segmentedCell?.label(forSegment: segment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/menu(forsegment:)
    @MainActor open func menu(forSegment segment: Int) -> NSMenu? { _segmentedCell?.menu(forSegment: segment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/minimumsize(withprioritizedcompressionoptions:)
    @MainActor open func minimumSize(withPrioritizedCompressionOptions prioritizedOptions: [NSUserInterfaceCompressionOptions]) -> NSSize { intrinsicContentSize }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/segmentcount
    @MainActor open var segmentCount: Int {
        get { _segmentedCell?.segmentCount ?? 0 }
        set { _segmentedCell?.segmentCount = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/segmentdistribution
    @MainActor open var segmentDistribution: NSSegmentedControl.Distribution {
        get { _distribution }
        set { _distribution = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/segmentstyle
    @MainActor open var segmentStyle: NSSegmentedControl.Style {
        get { _segmentedCell?.segmentStyle ?? .automatic }
        set { _segmentedCell?.segmentStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/selectsegment(withtag:)
    @MainActor open func selectSegment(withTag tag: Int) -> Bool { let ok = _segmentedCell?.selectSegment(withTag: tag) ?? false; needsDisplay = true; return ok }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/selectedsegment
    @MainActor open var selectedSegment: Int {
        get { _segmentedCell?.selectedSegment ?? -1 }
        set { _segmentedCell?.selectedSegment = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/selectedsegmentbezelcolor
    @MainActor open var selectedSegmentBezelColor: NSColor? {
        get { _selectedSegmentBezelColor }
        set { _selectedSegmentBezelColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setalignment(_:forsegment:)
    @MainActor open func setAlignment(_ alignment: NSTextAlignment, forSegment segment: Int) {
        guard let c = _segmentedCell, c._segments.indices.contains(segment) else { return }
        c._segments[segment].alignment = alignment
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setenabled(_:forsegment:)
    @MainActor open func setEnabled(_ enabled: Bool, forSegment segment: Int) { _segmentedCell?.setEnabled(enabled, forSegment: segment); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setimage(_:forsegment:)
    @MainActor open func setImage(_ image: NSImage?, forSegment segment: Int) { _segmentedCell?.setImage(image, forSegment: segment); invalidateIntrinsicContentSize(); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setimagescaling(_:forsegment:)
    @MainActor open func setImageScaling(_ scaling: NSImageScaling, forSegment segment: Int) { _segmentedCell?.setImageScaling(scaling, forSegment: segment); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setlabel(_:forsegment:)
    @MainActor open func setLabel(_ label: String, forSegment segment: Int) { _segmentedCell?.setLabel(label, forSegment: segment); invalidateIntrinsicContentSize(); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setmenu(_:forsegment:)
    @MainActor open func setMenu(_ menu: NSMenu?, forSegment segment: Int) { _segmentedCell?.setMenu(menu, forSegment: segment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setselected(_:forsegment:)
    @MainActor open func setSelected(_ selected: Bool, forSegment segment: Int) { _segmentedCell?.setSelected(selected, forSegment: segment); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setshowsmenuindicator(_:forsegment:)
    @MainActor open func setShowsMenuIndicator(_ showsMenuIndicator: Bool, forSegment segment: Int) {
        guard let c = _segmentedCell, c._segments.indices.contains(segment) else { return }
        c._segments[segment].showsMenuIndicator = showsMenuIndicator
        invalidateIntrinsicContentSize(); needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/settag(_:forsegment:)
    @MainActor open func setTag(_ tag: Int, forSegment segment: Int) { _segmentedCell?.setTag(tag, forSegment: segment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/settooltip(_:forsegment:)
    @MainActor open func setToolTip(_ toolTip: String?, forSegment segment: Int) { _segmentedCell?.setToolTip(toolTip, forSegment: segment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/setwidth(_:forsegment:)
    @MainActor open func setWidth(_ width: CGFloat, forSegment segment: Int) { _segmentedCell?.setWidth(width, forSegment: segment); invalidateIntrinsicContentSize(); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/showsmenuindicator(forsegment:)
    @MainActor open func showsMenuIndicator(forSegment segment: Int) -> Bool { _segmentedCell?._segments.indices.contains(segment) == true && _segmentedCell!._segments[segment].showsMenuIndicator }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/tag(forsegment:)
    @MainActor open func tag(forSegment segment: Int) -> Int { _segmentedCell?.tag(forSegment: segment) ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/tooltip(forsegment:)
    @MainActor open func toolTip(forSegment segment: Int) -> String? { _segmentedCell?.toolTip(forSegment: segment) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/trackingmode
    @MainActor open var trackingMode: NSSegmentedControl.SwitchTracking {
        get { _segmentedCell?.trackingMode ?? .selectOne }
        set { _segmentedCell?.trackingMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssegmentedcontrol/width(forsegment:)
    @MainActor open func width(forSegment segment: Int) -> CGFloat { _segmentedCell?.width(forSegment: segment) ?? 0 }

    @MainActor open override var intrinsicContentSize: NSSize { _segmentedCell?.cellSize ?? super.intrinsicContentSize }

    // MARK: Tracking

    /// The segment under a point in the view's bounds, or -1.
    @MainActor internal func _segment(at point: NSPoint) -> Int {
        guard let c = _segmentedCell else { return -1 }
        let rects = c._segmentRects(in: bounds.insetBy(dx: 0.5, dy: 0.5), distribution: _distribution)
        return rects.firstIndex { $0.contains(point) } ?? -1
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, let c = _segmentedCell else { return }
        let i = _segment(at: convert(event.locationInWindow, from: nil))
        guard i >= 0, c.isEnabled(forSegment: i) else { return }
        _pressed = i
        c._pressedSegment = i
        needsDisplay = true
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _pressed >= 0, let c = _segmentedCell else { return }
        let i = _segment(at: convert(event.locationInWindow, from: nil))
        let inside = i == _pressed ? _pressed : -1
        if c._pressedSegment != inside { c._pressedSegment = inside; needsDisplay = true }
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        guard _pressed >= 0, let c = _segmentedCell else { return }
        let pressed = _pressed
        _pressed = -1
        c._pressedSegment = -1
        let i = _segment(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
        guard i == pressed else { return }
        _activate(pressed)
    }

    /// A click (or the keyboard) on a segment: applies the tracking mode and fires the action.
    @MainActor private func _activate(_ i: Int) {
        guard let c = _segmentedCell else { return }
        switch c.trackingMode {
        case .selectOne:
            c.selectedSegment = i
        case .selectAny:
            c.setSelected(!c.isSelected(forSegment: i), forSegment: i)
        case .momentary, .momentaryAccelerator:
            c.selectedSegment = i
            needsDisplay = true
            _fireAction()
            c.selectedSegment = -1
            needsDisplay = true
            return
        }
        c._keySegment = i
        needsDisplay = true
        _fireAction()
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        guard let c = _segmentedCell, c.segmentCount > 0 else { super.keyDown(with: event); return }
        switch event.charactersIgnoringModifiers {
        case "\u{F702}": c.makePreviousSegmentKey(); needsDisplay = true      // left
        case "\u{F703}": c.makeNextSegmentKey(); needsDisplay = true          // right
        case " ", "\r":
            let i = c._keySegment >= 0 ? c._keySegment : c.selectedSegment
            if i >= 0 { _activate(i) }
        default: super.keyDown(with: event)
        }
    }

    @MainActor open override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let c = _segmentedCell, c._keySegment < 0 { c._keySegment = max(0, c.selectedSegment) }
        needsDisplay = true
        return ok
    }
    @MainActor open override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        needsDisplay = true
        return ok
    }
}
