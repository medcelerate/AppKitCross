// NSScrollView (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview
@MainActor open class NSScrollView: NSView, NSTextFinderBarContainer {
    // MARK: Storage
    private var _contentView: NSClipView
    private var _verticalScroller: NSScroller? = nil
    private var _horizontalScroller: NSScroller? = nil
    private var _hasVerticalScroller = false
    private var _hasHorizontalScroller = false
    private var _autohidesScrollers = true
    private var _borderType: NSBorderType = .noBorder
    private var _drawsBackground = true
    private var _backgroundColor: NSColor = .controlBackgroundColor
    private var _verticalLineScroll: CGFloat = 10
    private var _horizontalLineScroll: CGFloat = 10
    private var _verticalPageScroll: CGFloat = 10
    private var _horizontalPageScroll: CGFloat = 10
    private var _scrollerStyle: NSScroller.Style = .legacy
    private var _scrollerKnobStyle: NSScroller.KnobStyle = .default
    private var _contentInsets = NSEdgeInsets()
    private var _scrollerInsets = NSEdgeInsets()
    private var _automaticallyAdjustsContentInsets = true
    private var _scrollsDynamically = true
    private var _usesPredominantAxisScrolling = true
    private var _verticalScrollElasticity: NSScrollView.Elasticity = .automatic
    private var _horizontalScrollElasticity: NSScrollView.Elasticity = .automatic
    private var _magnification: CGFloat = 1
    private var _allowsMagnification = false
    private var _minMagnification: CGFloat = 0.25
    private var _maxMagnification: CGFloat = 4
    private var _rulersVisible = false
    private var _hasVerticalRuler = false
    private var _hasHorizontalRuler = false
    private var _findBarPosition: NSScrollView.FindBarPosition = .aboveContent
    private var _findBarView: NSView? = nil
    private var _documentCursor: NSCursor? = nil
    private var _tiling = false

    private static let scrollerAction = Selector(("_scrollerChanged:"))

    @MainActor open override var isOpaque: Bool { _drawsBackground }

    private var _borderInset: CGFloat {
        switch _borderType {
        case .noBorder: return 0
        case .lineBorder: return 1
        default: return 2
        }
    }

    @MainActor private func _makeScroller(horizontal: Bool) -> NSScroller {
        let w = NSScroller.scrollerWidth(for: .regular, scrollerStyle: _scrollerStyle)
        let s = NSScroller(frame: horizontal ? NSRect(x: 0, y: 0, width: 100, height: w) : NSRect(x: 0, y: 0, width: w, height: 100))
        s.scrollerStyle = _scrollerStyle
        s.target = self
        s.action = NSScrollView.scrollerAction
        addSubview(s)
        return s
    }

    @MainActor private func _scrollerChanged(_ scroller: NSScroller) {
        let clip = _contentView
        let doc = clip.documentRect
        var origin = clip.bounds.origin
        let v = CGFloat(min(max(scroller.doubleValue, 0), 1))
        if scroller === _horizontalScroller {
            origin.x = doc.minX + v * max(0, doc.width - clip.bounds.width)
        } else {
            let range = max(0, doc.height - clip.bounds.height)
            origin.y = clip.isFlipped ? doc.minY + v * range : doc.maxY - clip.bounds.height - v * range
        }
        clip.scroll(to: origin)
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        if _drawsBackground {
            _backgroundColor.setFill()
            NSBezierPath.fill(dirtyRect)
        }
        switch _borderType {
        case .lineBorder, .bezelBorder, .grooveBorder:
            NSColor.separatorColor.setStroke()
            NSBezierPath.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
        default: break
        }
    }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        tile()
    }

    /// Scrolls so that `rect` (in document coordinates) is visible.
    @MainActor internal func _scrollToVisible(_ rect: NSRect) {
        let clip = _contentView
        let visible = clip.documentVisibleRect
        var o = clip.bounds.origin
        if rect.minX < visible.minX { o.x -= visible.minX - rect.minX } else if rect.maxX > visible.maxX { o.x += rect.maxX - visible.maxX }
        if rect.minY < visible.minY { o.y -= visible.minY - rect.minY } else if rect.maxY > visible.maxY { o.y += rect.maxY - visible.maxY }
        clip.scroll(to: o)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/init(coder:)
    public required init?(coder: NSCoder) {
        _contentView = NSClipView(frame: .zero)
        super.init(coder: coder)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        _contentView = NSClipView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        addSubview(_contentView)
        setActionHandler(for: NSScrollView.scrollerAction) { [weak self] sender in
            if let s = sender as? NSScroller { self?._scrollerChanged(s) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/addfloatingsubview(_:for:)
    @MainActor open func addFloatingSubview(_ view: NSView, for axis: NSEvent.GestureAxis) { addSubview(view) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/allowsmagnification
    @MainActor open var allowsMagnification: Bool {
        get { _allowsMagnification }
        set { _allowsMagnification = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/autohidesscrollers
    @MainActor open var autohidesScrollers: Bool {
        get { _autohidesScrollers }
        set { _autohidesScrollers = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/automaticallyadjustscontentinsets
    @available(macOS 10.10, *)
    @MainActor open var automaticallyAdjustsContentInsets: Bool {
        get { _automaticallyAdjustsContentInsets }
        set { _automaticallyAdjustsContentInsets = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/backgroundcolor
    @MainActor open var backgroundColor: NSColor {
        get { _backgroundColor }
        set { _backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/bordertype
    @MainActor open var borderType: NSBorderType {
        get { _borderType }
        set { _borderType = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/contentinsets
    @available(macOS 10.10, *)
    @MainActor open var contentInsets: NSEdgeInsets {
        get { _contentInsets }
        set { _contentInsets = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/contentsize
    @MainActor open var contentSize: NSSize { _contentView.bounds.size }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/contentsize(forframesize:horizontalscrollerclass:verticalscrollerclass:bordertype:controlsize:scrollerstyle:)
    @MainActor public class func contentSize(forFrameSize fSize: NSSize, horizontalScrollerClass: AnyClass?, verticalScrollerClass: AnyClass?, borderType type: NSBorderType, controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> NSSize {
        let inset: CGFloat = type == .noBorder ? 0 : (type == .lineBorder ? 1 : 2)
        let w = NSScroller.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle)
        return NSSize(width: fSize.width - 2 * inset - (verticalScrollerClass != nil ? w : 0), height: fSize.height - 2 * inset - (horizontalScrollerClass != nil ? w : 0))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/contentview
    @MainActor open var contentView: NSClipView {
        get { _contentView }
        set {
            let doc = _contentView.documentView
            _contentView.removeFromSuperview()
            _contentView = newValue
            addSubview(newValue)
            if newValue.documentView == nil { newValue.documentView = doc }
            tile()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/didendlivemagnifynotification
    static public var didEndLiveMagnifyNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSScrollViewDidEndLiveMagnifyNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/didendlivescrollnotification
    static public var didEndLiveScrollNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSScrollViewDidEndLiveScrollNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/didlivescrollnotification
    static public var didLiveScrollNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSScrollViewDidLiveScrollNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/documentcursor
    @MainActor open var documentCursor: NSCursor? {
        get { _documentCursor }
        set { _documentCursor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/documentview
    @MainActor open var documentView: NSView? {
        get { _contentView.documentView }
        set { _contentView.documentView = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/documentvisiblerect
    @MainActor open var documentVisibleRect: NSRect { _contentView.documentVisibleRect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _drawsBackground }
        set { _drawsBackground = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/findbarposition
    @MainActor open var findBarPosition: NSScrollView.FindBarPosition {
        get { _findBarPosition }
        set { _findBarPosition = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/flashscrollers()
    @MainActor open func flashScrollers() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/framesize(forcontentsize:horizontalscrollerclass:verticalscrollerclass:bordertype:controlsize:scrollerstyle:)
    @MainActor public class func frameSize(forContentSize cSize: NSSize, horizontalScrollerClass: AnyClass?, verticalScrollerClass: AnyClass?, borderType type: NSBorderType, controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> NSSize {
        let inset: CGFloat = type == .noBorder ? 0 : (type == .lineBorder ? 1 : 2)
        let w = NSScroller.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle)
        return NSSize(width: cSize.width + 2 * inset + (verticalScrollerClass != nil ? w : 0), height: cSize.height + 2 * inset + (horizontalScrollerClass != nil ? w : 0))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/hashorizontalruler
    @MainActor open var hasHorizontalRuler: Bool {
        get { _hasHorizontalRuler }
        set { _hasHorizontalRuler = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/hashorizontalscroller
    @MainActor open var hasHorizontalScroller: Bool {
        get { _hasHorizontalScroller }
        set {
            _hasHorizontalScroller = newValue
            if newValue, _horizontalScroller == nil { _horizontalScroller = _makeScroller(horizontal: true) }
            tile()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/hasverticalruler
    @MainActor open var hasVerticalRuler: Bool {
        get { _hasVerticalRuler }
        set { _hasVerticalRuler = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/hasverticalscroller
    @MainActor open var hasVerticalScroller: Bool {
        get { _hasVerticalScroller }
        set {
            _hasVerticalScroller = newValue
            if newValue, _verticalScroller == nil { _verticalScroller = _makeScroller(horizontal: false) }
            tile()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/horizontallinescroll
    @MainActor open var horizontalLineScroll: CGFloat {
        get { _horizontalLineScroll }
        set { _horizontalLineScroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/horizontalpagescroll
    @MainActor open var horizontalPageScroll: CGFloat {
        get { _horizontalPageScroll }
        set { _horizontalPageScroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/horizontalrulerview
    @MainActor open var horizontalRulerView: NSRulerView? {
        get { nil }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/horizontalscrollelasticity
    @MainActor open var horizontalScrollElasticity: NSScrollView.Elasticity {
        get { _horizontalScrollElasticity }
        set { _horizontalScrollElasticity = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/horizontalscroller
    @MainActor open var horizontalScroller: NSScroller? {
        get { _horizontalScroller }
        set { _horizontalScroller?.removeFromSuperview(); _horizontalScroller = newValue; if let s = newValue { s.target = self; s.action = NSScrollView.scrollerAction; addSubview(s) }; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/linescroll
    @MainActor open var lineScroll: CGFloat {
        get { _verticalLineScroll }
        set { _verticalLineScroll = newValue; _horizontalLineScroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/magnification
    @MainActor open var magnification: CGFloat {
        get { _magnification }
        set { _magnification = min(max(newValue, _minMagnification), _maxMagnification) }   // Applied in Milestone 4 with layer transforms.
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/magnify(tofit:)
    @MainActor open func magnify(toFit rect: NSRect) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/maxmagnification
    @MainActor open var maxMagnification: CGFloat {
        get { _maxMagnification }
        set { _maxMagnification = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/minmagnification
    @MainActor open var minMagnification: CGFloat {
        get { _minMagnification }
        set { _minMagnification = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/pagescroll
    @MainActor open var pageScroll: CGFloat {
        get { _verticalPageScroll }
        set { _verticalPageScroll = newValue; _horizontalPageScroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/reflectscrolledclipview(_:)
    @MainActor open override func reflectScrolledClipView(_ cView: NSClipView) {
        guard cView === _contentView else { return }
        if let header = _headerView, header.bounds.minX != cView.bounds.minX {
            header.setBoundsOrigin(NSPoint(x: cView.bounds.minX, y: 0))
            header.needsDisplay = true
        }
        let doc = cView.documentRect
        let b = cView.bounds
        if let v = _verticalScroller {
            let range = max(0, doc.height - b.height)
            v.knobProportion = doc.height > 0 ? min(1, b.height / doc.height) : 1
            let fromTop = cView.isFlipped ? b.minY - doc.minY : doc.maxY - b.maxY
            v.doubleValue = range > 0 ? Double(min(max(fromTop / range, 0), 1)) : 0
            v.needsDisplay = true
        }
        if let h = _horizontalScroller {
            let range = max(0, doc.width - b.width)
            h.knobProportion = doc.width > 0 ? min(1, b.width / doc.width) : 1
            h.doubleValue = range > 0 ? Double(min(max((b.minX - doc.minX) / range, 0), 1)) : 0
            h.needsDisplay = true
        }
        if _autohidesScrollers && !_tiling {
            let w = NSScroller.scrollerWidth(for: .regular, scrollerStyle: _scrollerStyle)
            let needV = _hasVerticalScroller && doc.height > bounds.height - 2 * _borderInset
            let needH = _hasHorizontalScroller && doc.width > bounds.width - 2 * _borderInset - (needV ? w : 0)
            if needV != !(_verticalScroller?.isHidden ?? true) || needH != !(_horizontalScroller?.isHidden ?? true) { tile() }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/rulerviewclass
    @MainActor class public var rulerViewClass: AnyClass! {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/rulersvisible
    @MainActor open var rulersVisible: Bool {
        get { _rulersVisible }
        set { _rulersVisible = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/scrollwheel(with:)
    @MainActor open override func scrollWheel(with event: NSEvent) {
        let clip = _contentView
        var dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { dx *= _horizontalLineScroll; dy *= _verticalLineScroll }
        if _usesPredominantAxisScrolling { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
        var o = clip.bounds.origin
        o.x -= dx
        o.y += clip.isFlipped ? -dy : dy
        let before = clip.bounds.origin
        clip.scroll(to: o)
        if clip.bounds.origin == before { super.scrollWheel(with: event) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/scrollerinsets
    @available(macOS 10.10, *)
    @MainActor open var scrollerInsets: NSEdgeInsets {
        get { _scrollerInsets }
        set { _scrollerInsets = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/scrollerknobstyle
    @MainActor open var scrollerKnobStyle: NSScroller.KnobStyle {
        get { _scrollerKnobStyle }
        set { _scrollerKnobStyle = newValue; _verticalScroller?.knobStyle = newValue; _horizontalScroller?.knobStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/scrollerstyle
    @MainActor open var scrollerStyle: NSScroller.Style {
        get { _scrollerStyle }
        set { _scrollerStyle = newValue; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/scrollsdynamically
    @MainActor open var scrollsDynamically: Bool {
        get { _scrollsDynamically }
        set { _scrollsDynamically = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/setmagnification(_:centeredat:)
    @MainActor open func setMagnification(_ magnification: CGFloat, centeredAt point: NSPoint) { self.magnification = magnification }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/tile()
    @MainActor open func tile() {
        guard !_tiling else { return }
        _tiling = true
        defer { _tiling = false }
        let inset = _borderInset
        var content = bounds.insetBy(dx: inset, dy: inset)
        // A scroll view smaller than its border (a collapsed or minimised window) must not
        // produce the null rect's infinities.
        if content.isNull || content.width < 0 || content.height < 0 {
            content = NSRect(x: bounds.minX + min(inset, bounds.width / 2), y: bounds.minY + min(inset, bounds.height / 2), width: 0, height: 0)
        }
        // A table's header sits above the content, scrolling horizontally with it.
        let header = (_contentView.documentView as? NSTableView)?.headerView
        if let stale = _headerView, stale !== header { stale.removeFromSuperview() }
        _headerView = header
        if let header {
            if header.superview !== self { addSubview(header) }
            let h = header.intrinsicContentSize.height
            header.frame = NSRect(x: content.minX, y: isFlipped ? content.minY : content.maxY - h, width: content.width, height: h)
            content.size.height = max(0, content.height - h)
            if isFlipped { content.origin.y += h }
        }
        let doc = _contentView.documentRect
        let w = NSScroller.scrollerWidth(for: .regular, scrollerStyle: _scrollerStyle)
        var showV = _hasVerticalScroller, showH = _hasHorizontalScroller
        if _autohidesScrollers {
            // Two passes: showing one scroller can make the other necessary.
            showV = _hasVerticalScroller && doc.height > content.height
            showH = _hasHorizontalScroller && doc.width > content.width - (showV ? w : 0)
            showV = _hasVerticalScroller && doc.height > content.height - (showH ? w : 0)
        }
        if showV { content.size.width = max(0, content.size.width - w) }
        if showH {
            content.size.height = max(0, content.size.height - w)
            if !isFlipped { content.origin.y += w }
        }
        if let v = _verticalScroller {
            v.isHidden = !showV
            v.frame = NSRect(x: content.maxX, y: content.minY, width: w, height: content.height)
        }
        if let h = _horizontalScroller {
            h.isHidden = !showH
            h.frame = NSRect(x: content.minX, y: isFlipped ? content.maxY : bounds.minY + inset, width: content.width, height: w)
        }
        if _contentView.frame != content {
            _contentView.frame = content
            (_contentView.documentView as? NSTableView)?._clipViewDidResize()
        }
        reflectScrolledClipView(_contentView)
        needsDisplay = true
    }
    private var _headerView: NSTableHeaderView?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/usespredominantaxisscrolling
    @MainActor open var usesPredominantAxisScrolling: Bool {
        get { _usesPredominantAxisScrolling }
        set { _usesPredominantAxisScrolling = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/verticallinescroll
    @MainActor open var verticalLineScroll: CGFloat {
        get { _verticalLineScroll }
        set { _verticalLineScroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/verticalpagescroll
    @MainActor open var verticalPageScroll: CGFloat {
        get { _verticalPageScroll }
        set { _verticalPageScroll = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/verticalrulerview
    @MainActor open var verticalRulerView: NSRulerView? {
        get { nil }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/verticalscrollelasticity
    @MainActor open var verticalScrollElasticity: NSScrollView.Elasticity {
        get { _verticalScrollElasticity }
        set { _verticalScrollElasticity = newValue }
    }
    // MARK: Accessibility (ADR-0013)
    // AXScrollArea: the clip view is ignored, so the document view's elements and the
    // scrollers are the children.
    @MainActor open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    @MainActor open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .scrollArea }
    @MainActor open func accessibilityContents() -> [Any]? { documentView.map { [$0] } }
    @MainActor open func accessibilityVerticalScrollBar() -> Any? { hasVerticalScroller ? verticalScroller : nil }
    @MainActor open func accessibilityHorizontalScrollBar() -> Any? { hasHorizontalScroller ? horizontalScroller : nil }
    @MainActor override func _accessibilityIsFocusable() -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/verticalscroller
    @MainActor open var verticalScroller: NSScroller? {
        get { _verticalScroller }
        set { _verticalScroller?.removeFromSuperview(); _verticalScroller = newValue; if let s = newValue { s.target = self; s.action = NSScrollView.scrollerAction; addSubview(s) }; tile() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/willstartlivemagnifynotification
    static public var willStartLiveMagnifyNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSScrollViewWillStartLiveMagnifyNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrollview/willstartlivescrollnotification
    static public var willStartLiveScrollNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSScrollViewWillStartLiveScrollNotification") }
    // Requirement of NSTextFinderBarContainer
    open var findBarView: NSView? {
        get { MainActor.assumeIsolated { _findBarView } }
        set { MainActor.assumeIsolated { _findBarView = newValue } }
    }
    // Requirement of NSTextFinderBarContainer
    open var isFindBarVisible: Bool {
        get { false }
        set { }
    }
    // Requirement of NSTextFinderBarContainer
    open func findBarViewDidChangeHeight() { }
}
