// NSView (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview
@MainActor open class NSView: NSResponder, NSAnimatablePropertyContainer, NSUserInterfaceItemIdentification, NSDraggingDestination, NSAppearanceCustomization, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    // MARK: Storage
    private var _frame: NSRect
    private var _boundsOrigin = NSPoint.zero
    private var _boundsSize: NSSize? = nil          // nil: bounds track the frame size
    private weak var _superview: NSView?
    private var _subviews: [NSView] = []
    private weak var _window: NSWindow?
    private var _isHidden = false
    private var _needsDisplay = false
    private var _dirtyRect: NSRect? = nil
    private var _autoresizingMask: NSView.AutoresizingMask = []
    private var _autoresizesSubviews = true
    private var _wantsLayer = false
    private var _alphaValue: CGFloat = 1
    private var _needsLayout = false
    private var _translatesAutoresizingMaskIntoConstraints = true
    private var _identifier: NSUserInterfaceItemIdentifier? = nil
    private var _toolTip: String? = nil
    private var _clipsToBounds = false
    private var _postsFrameChangedNotifications = false
    private var _postsBoundsChangedNotifications = false
    private var _focusRingType: NSFocusRingType = .default
    private var _layerContentsRedrawPolicy: NSView.LayerContentsRedrawPolicy = .never
    private var _userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection = .leftToRight
    private var _frameRotation: CGFloat = 0
    private var _boundsRotation: CGFloat = 0
    private var _preparedContentRect: NSRect? = nil

    open override var description: String { MainActor.assumeIsolated { "<\(type(of: self)) frame=\(_frame)>" } }

    // MARK: Window propagation

    internal func _setWindow(_ window: NSWindow?) {
        guard _window !== window else { return }
        viewWillMove(toWindow: window)
        for s in _subviews { s._setWindow(window) }
        _window = window
        viewDidMoveToWindow()
    }

    // MARK: Coordinate math (own bounds <-> superview coordinates)

    internal func _toSuperview(_ p: NSPoint) -> NSPoint {
        let b = bounds
        let x = p.x - b.minX + _frame.minX
        let y = isFlipped ? _frame.minY + (b.maxY - p.y) : p.y - b.minY + _frame.minY
        return NSPoint(x: x, y: y)
    }

    internal func _fromSuperview(_ p: NSPoint) -> NSPoint {
        let b = bounds
        let x = p.x - _frame.minX + b.minX
        let y = isFlipped ? b.maxY - (p.y - _frame.minY) : p.y - _frame.minY + b.minY
        return NSPoint(x: x, y: y)
    }

    internal func _toWindow(_ p: NSPoint) -> NSPoint {
        var pt = p
        var v: NSView? = self
        while let cur = v { pt = cur._toSuperview(pt); v = cur._superview }
        return pt
    }

    internal func _fromWindow(_ p: NSPoint) -> NSPoint {
        var chain: [NSView] = []
        var v: NSView? = self
        while let cur = v { chain.append(cur); v = cur._superview }
        var pt = p
        for cur in chain.reversed() { pt = cur._fromSuperview(pt) }
        return pt
    }

    private func _convertRect(_ rect: NSRect, _ convert: (NSPoint) -> NSPoint) -> NSRect {
        let a = convert(NSPoint(x: rect.minX, y: rect.minY))
        let b = convert(NSPoint(x: rect.maxX, y: rect.maxY))
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    // MARK: Drawing

    /// Draws this view and its subviews into `ctx`, which is in the superview's coordinate
    /// system. `dirtyRect` is in superview coordinates too.
    internal func _displayHierarchy(in ctx: CGContext, dirtyRect: NSRect) {
        guard !_isHidden, _alphaValue > 0 else { return }
        guard _frame.intersects(dirtyRect) else { return }
        ctx.saveGState()
        ctx.translateBy(x: _frame.minX, y: _frame.minY)
        if isFlipped {
            ctx.translateBy(x: 0, y: _frame.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        let b = bounds
        ctx.translateBy(x: -b.minX, y: -b.minY)
        if wantsDefaultClipping { ctx.clip(to: b) }
        if _alphaValue < 1 { ctx.setAlpha(_alphaValue) }
        let localDirty = _convertRect(dirtyRect, _fromSuperview).intersection(b)
        let gc = NSGraphicsContext(cgContext: ctx, flipped: isFlipped)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = gc
        viewWillDraw()
        _dirtyRect = localDirty
        draw(localDirty)
        _dirtyRect = nil
        for sub in _subviews { sub._displayHierarchy(in: ctx, dirtyRect: localDirty) }
        NSGraphicsContext.current = previous
        ctx.restoreGState()
        _needsDisplay = false
    }

    private func _invalidate(_ rect: NSRect) {
        _needsDisplay = true
        if let w = _window {
            w._viewNeedsDisplay(self, rect: rect)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/init(coder:)
    public required init?(coder: NSCoder) {
        _frame = .zero
        super.init(coder: coder)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/init(frame:)
    @MainActor public init(frame frameRect: NSRect) {
        _frame = frameRect
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:)
    @MainActor open func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/acceptstouchevents
    @MainActor open var acceptsTouchEvents: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addconstraint(_:)
    @MainActor open func addConstraint(_ constraint: NSLayoutConstraint) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addconstraints(_:)
    @MainActor open func addConstraints(_ constraints: [NSLayoutConstraint]) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addcursorrect(_:cursor:)
    @MainActor open func addCursorRect(_ rect: NSRect, cursor object: NSCursor) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addgesturerecognizer(_:)
    @available(macOS 10.10, *)
    @MainActor open func addGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addlayoutguide(_:)
    @available(macOS 10.11, *)
    @MainActor open func addLayoutGuide(_ guide: NSLayoutGuide) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addsubview(_:)
    @MainActor open func addSubview(_ view: NSView) {
        addSubview(view, positioned: .above, relativeTo: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addsubview(_:positioned:relativeto:)
    @MainActor open func addSubview(_ view: NSView, positioned place: NSWindow.OrderingMode, relativeTo otherView: NSView?) {
        precondition(view !== self, "NSView: cannot add a view as a subview of itself")
        if view._superview === self {
            _subviews.removeAll { $0 === view }
        } else {
            view.removeFromSuperviewWithoutNeedingDisplay()
        }
        view.viewWillMove(toSuperview: self)
        var index = _subviews.count
        if let other = otherView, let i = _subviews.firstIndex(where: { $0 === other }) {
            index = place == .below ? i : i + 1
        } else if place == .below {
            index = 0
        }
        _subviews.insert(view, at: index)
        view._superview = self
        view.nextResponder = self
        view._setWindow(_window)
        view.viewDidMoveToSuperview()
        didAddSubview(view)
        setNeedsDisplay(view._frame)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addtooltip(_:owner:userdata:)
    @MainActor open func addToolTip(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addtrackingarea(_:)
    @MainActor open func addTrackingArea(_ trackingArea: NSTrackingArea) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addtrackingrect(_:owner:userdata:assumeinside:)
    @MainActor open func addTrackingRect(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?, assumeInside flag: Bool) -> NSView.TrackingRectTag { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/additionalsafeareainsets
    @available(macOS 11.0, *)
    @MainActor open var additionalSafeAreaInsets: NSEdgeInsets {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/adjustpageheightnew(_:top:bottom:limit:)
    @MainActor open func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat, bottom oldBottom: CGFloat, limit bottomLimit: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/adjustpagewidthnew(_:left:right:limit:)
    @MainActor open func adjustPageWidthNew(_ newRight: UnsafeMutablePointer<CGFloat>, left oldLeft: CGFloat, right oldRight: CGFloat, limit rightLimit: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/adjustscroll(_:)
    @MainActor open func adjustScroll(_ newVisible: NSRect) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/alignmentrect(forframe:)
    @MainActor open func alignmentRect(forFrame frame: NSRect) -> NSRect { frame }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/alignmentrectinsets
    @MainActor open var alignmentRectInsets: NSEdgeInsets { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/allocategstate()
    @MainActor open func allocateGState() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/allowedtouchtypes
    @available(macOS 10.12, *)
    @MainActor open var allowedTouchTypes: NSTouch.TouchTypeMask {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/allowsvibrancy
    @available(macOS 10.10, *)
    @MainActor open var allowsVibrancy: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/alphavalue
    @MainActor open var alphaValue: CGFloat {
        get { _alphaValue }
        set { _alphaValue = newValue; setNeedsDisplay(bounds) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/ancestorshared(with:)
    @MainActor open func ancestorShared(with view: NSView) -> NSView? {
        var v: NSView? = self
        while let cur = v { if view.isDescendant(of: cur) { return cur }; v = cur._superview }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizessubviews
    @MainActor open var autoresizesSubviews: Bool {
        get { _autoresizesSubviews }
        set { _autoresizesSubviews = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoresizingmask
    @MainActor open var autoresizingMask: NSView.AutoresizingMask {
        get { _autoresizingMask }
        set { _autoresizingMask = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/autoscroll(with:)
    @MainActor open func autoscroll(with event: NSEvent) -> Bool { unimplemented() }
    // SKIPPED (unknown module (CoreImage CIFilter)): @MainActor var backgroundFilters: [CIFilter] { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/backingalignedrect(_:options:)
    @MainActor open func backingAlignedRect(_ rect: NSRect, options: AlignmentOptions = []) -> NSRect { centerScanRect(rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/baselineoffsetfrombottom
    @MainActor open var baselineOffsetFromBottom: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/begindocument()
    @MainActor open func beginDocument() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)
    @MainActor open func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/beginpage(in:atplacement:)
    @MainActor open func beginPage(in rect: NSRect, atPlacement location: NSPoint) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/bitmapimagerepforcachingdisplay(in:)
    @MainActor open func bitmapImageRepForCachingDisplay(in rect: NSRect) -> NSBitmapImageRep? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/bottomanchor
    @available(macOS 10.11, *)
    @MainActor open var bottomAnchor: NSLayoutYAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/bounds
    @MainActor open var bounds: NSRect {
        get { NSRect(origin: _boundsOrigin, size: _boundsSize ?? _frame.size) }
        set {
            setBoundsOrigin(newValue.origin)
            setBoundsSize(newValue.size)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/boundsdidchangenotification
    static public var boundsDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSViewBoundsDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/boundsrotation
    @MainActor open var boundsRotation: CGFloat {
        get { _boundsRotation }
        set { _boundsRotation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/cachedisplay(in:to:)
    @MainActor open func cacheDisplay(in rect: NSRect, to bitmapImageRep: NSBitmapImageRep) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/canbecomekeyview
    @MainActor open var canBecomeKeyView: Bool { acceptsFirstResponder && !isHiddenOrHasHiddenAncestor }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/candraw
    @MainActor open var canDraw: Bool { _window != nil && !isHiddenOrHasHiddenAncestor }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/candrawconcurrently
    @MainActor open var canDrawConcurrently: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/candrawsubviewsintolayer
    @MainActor open var canDrawSubviewsIntoLayer: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/candidatelisttouchbaritem
    @available(macOS 10.12, *)
    @MainActor open var candidateListTouchBarItem: NSCandidateListTouchBarItem<AnyObject>? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/centerscanrect(_:)
    @MainActor open func centerScanRect(_ rect: NSRect) -> NSRect {
        let s = _window?.backingScaleFactor ?? 1
        return NSRect(x: (rect.minX * s).rounded() / s, y: (rect.minY * s).rounded() / s,
                      width: (rect.width * s).rounded() / s, height: (rect.height * s).rounded() / s)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/centerxanchor
    @available(macOS 10.11, *)
    @MainActor open var centerXAnchor: NSLayoutXAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/centeryanchor
    @available(macOS 10.11, *)
    @MainActor open var centerYAnchor: NSLayoutYAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/clipstobounds
    @MainActor open var clipsToBounds: Bool {
        get { _clipsToBounds }
        set { _clipsToBounds = newValue }
    }
    // SKIPPED (unknown module (CoreImage CIFilter)): @MainActor var compositingFilter: CIFilter? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/constraints
    @MainActor open var constraints: [NSLayoutConstraint] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/constraintsaffectinglayout(for:)
    @MainActor open func constraintsAffectingLayout(for orientation: NSLayoutConstraint.Orientation) -> [NSLayoutConstraint] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/contentcompressionresistancepriority(for:)
    @MainActor open func contentCompressionResistancePriority(for orientation: NSLayoutConstraint.Orientation) -> NSLayoutConstraint.Priority { unimplemented() }
    // SKIPPED (unknown module (CoreImage CIFilter)): @MainActor var contentFilters: [CIFilter] { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/contenthuggingpriority(for:)
    @MainActor open func contentHuggingPriority(for orientation: NSLayoutConstraint.Orientation) -> NSLayoutConstraint.Priority { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convert(_:from:)
    @MainActor open func convert(_ point: NSPoint, from view: NSView?) -> NSPoint { _fromWindow(view?._toWindow(point) ?? point) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convert(_:from:)
    @MainActor open func convert(_ size: NSSize, from view: NSView?) -> NSSize { size }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convert(_:from:)
    @MainActor open func convert(_ rect: NSRect, from view: NSView?) -> NSRect { _convertRect(rect) { convert($0, from: view) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convert(_:to:)
    @MainActor open func convert(_ point: NSPoint, to view: NSView?) -> NSPoint { let w = _toWindow(point); return view?._fromWindow(w) ?? w }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convert(_:to:)
    @MainActor open func convert(_ size: NSSize, to view: NSView?) -> NSSize { size }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convert(_:to:)
    @MainActor open func convert(_ rect: NSRect, to view: NSView?) -> NSRect { _convertRect(rect) { convert($0, to: view) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convertfrombacking(_:)
    @MainActor open func convertFromBacking(_ point: NSPoint) -> NSPoint { let s = _window?.backingScaleFactor ?? 1; return NSPoint(x: point.x / s, y: point.y / s) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convertfrombacking(_:)
    @MainActor open func convertFromBacking(_ size: NSSize) -> NSSize { let s = _window?.backingScaleFactor ?? 1; return NSSize(width: size.width / s, height: size.height / s) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convertfrombacking(_:)
    @MainActor open func convertFromBacking(_ rect: NSRect) -> NSRect { NSRect(origin: convertFromBacking(rect.origin), size: convertFromBacking(rect.size)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convertfromlayer(_:)
    @MainActor open func convertFromLayer(_ point: NSPoint) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convertfromlayer(_:)
    @MainActor open func convertFromLayer(_ size: NSSize) -> NSSize { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/convertfromlayer(_:)
    @MainActor open func convertFromLayer(_ rect: NSRect) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/converttobacking(_:)
    @MainActor open func convertToBacking(_ point: NSPoint) -> NSPoint { let s = _window?.backingScaleFactor ?? 1; return NSPoint(x: point.x * s, y: point.y * s) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/converttobacking(_:)
    @MainActor open func convertToBacking(_ size: NSSize) -> NSSize { let s = _window?.backingScaleFactor ?? 1; return NSSize(width: size.width * s, height: size.height * s) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/converttobacking(_:)
    @MainActor open func convertToBacking(_ rect: NSRect) -> NSRect { NSRect(origin: convertToBacking(rect.origin), size: convertToBacking(rect.size)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/converttolayer(_:)
    @MainActor open func convertToLayer(_ point: NSPoint) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/converttolayer(_:)
    @MainActor open func convertToLayer(_ size: NSSize) -> NSSize { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/converttolayer(_:)
    @MainActor open func convertToLayer(_ rect: NSRect) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/datawitheps(inside:)
    @MainActor open func dataWithEPS(inside rect: NSRect) -> Data { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/datawithpdf(inside:)
    @MainActor open func dataWithPDF(inside rect: NSRect) -> Data { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/defaultfocusringtype
    @MainActor class public var defaultFocusRingType: NSFocusRingType { NSFocusRingType(rawValue: 2)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/defaultmenu
    @MainActor class public var defaultMenu: NSMenu? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/didaddsubview(_:)
    @MainActor open func didAddSubview(_ subview: NSView) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/didclosemenu(_:with:)
    @available(macOS 10.11, *)
    @MainActor open func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/didupdatetrackingareasnotification
    static public var didUpdateTrackingAreasNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSViewDidUpdateTrackingAreasNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/discardcursorrects()
    @MainActor open func discardCursorRects() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/display()
    @MainActor open func display() { display(bounds) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/display(_:)
    @MainActor open func display(_ rect: NSRect) {
        setNeedsDisplay(rect)
        _window?.displayIfNeeded()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/displayifneeded()
    @MainActor open func displayIfNeeded() { if _needsDisplay { _window?.displayIfNeeded() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/displayifneeded(_:)
    @MainActor open func displayIfNeeded(_ rect: NSRect) { if _needsDisplay { _window?.displayIfNeeded() } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/displayifneededignoringopacity()
    @MainActor open func displayIfNeededIgnoringOpacity() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/displayifneededignoringopacity(_:)
    @MainActor open func displayIfNeededIgnoringOpacity(_ rect: NSRect) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/displayignoringopacity(_:)
    @MainActor open func displayIgnoringOpacity(_ rect: NSRect) { display(rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/displayignoringopacity(_:in:)
    @MainActor open func displayIgnoringOpacity(_ rect: NSRect, in context: NSGraphicsContext) {
        let r = convert(rect, to: _superview)
        _displayHierarchy(in: context.cgContext, dirtyRect: _superview == nil ? rect : r)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)
    @available(macOS 14.0, *)
    @MainActor open func displayLink(target: Any, selector: Selector) -> CADisplayLink { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/dragfile(_:from:slideback:event:)
    @MainActor open func dragFile(_ filename: String, from rect: NSRect, slideBack flag: Bool, event: NSEvent) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/dragpromisedfiles(oftypes:from:source:slideback:event:)
    @MainActor open func dragPromisedFiles(ofTypes typeArray: [String], from rect: NSRect, source sourceObject: Any, slideBack flag: Bool, event: NSEvent) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/draw(_:)
    @MainActor open func draw(_ dirtyRect: NSRect) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/drawfocusringmask()
    @MainActor open func drawFocusRingMask() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/drawpageborder(with:)
    @MainActor open func drawPageBorder(with borderSize: NSSize) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/drawsheetborder(with:)
    @MainActor open func drawSheetBorder(with borderSize: NSSize) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/edgeinsets(for:)
    @available(macOS 26.0, *)
    @MainActor open func edgeInsets(for region: NSView.LayoutRegion) -> NSEdgeInsets { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/enclosingmenuitem
    @MainActor open var enclosingMenuItem: NSMenuItem? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/enclosingscrollview
    @MainActor open var enclosingScrollView: NSScrollView? {
        var v = _superview
        while let cur = v { if let sv = cur as? NSScrollView { return sv }; v = cur._superview }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/enddocument()
    @MainActor open func endDocument() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/endpage()
    @MainActor open func endPage() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/enterfullscreenmode(_:withoptions:)
    @MainActor open func enterFullScreenMode(_ screen: NSScreen, withOptions options: [NSView.FullScreenModeOptionKey : Any]? = nil) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/exerciseambiguityinlayout()
    @MainActor open func exerciseAmbiguityInLayout() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/exitfullscreenmode(options:)
    @MainActor open func exitFullScreenMode(options: [NSView.FullScreenModeOptionKey : Any]? = nil) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/firstbaselineanchor
    @available(macOS 10.11, *)
    @MainActor open var firstBaselineAnchor: NSLayoutYAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/firstbaselineoffsetfromtop
    @available(macOS 10.11, *)
    @MainActor open var firstBaselineOffsetFromTop: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/fittingsize
    @MainActor open var fittingSize: NSSize { let s = intrinsicContentSize; return NSSize(width: max(0, s.width), height: max(0, s.height)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/focusringmaskbounds
    @MainActor open var focusRingMaskBounds: NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/focusringtype
    @MainActor open var focusRingType: NSFocusRingType {
        get { _focusRingType }
        set { _focusRingType = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/focusview
    @MainActor class public var focusView: NSView? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/frame
    @MainActor open var frame: NSRect {
        get { _frame }
        set {
            setFrameOrigin(newValue.origin)
            setFrameSize(newValue.size)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/frame(foralignmentrect:)
    @MainActor open func frame(forAlignmentRect alignmentRect: NSRect) -> NSRect { alignmentRect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/framecenterrotation
    @MainActor open var frameCenterRotation: CGFloat {
        get { _frameRotation }
        set { _frameRotation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/framedidchangenotification
    static public var frameDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSViewFrameDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/framerotation
    @MainActor open var frameRotation: CGFloat {
        get { _frameRotation }
        set { _frameRotation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/gstate()
    @MainActor open func gState() -> Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/gesturerecognizers
    @available(macOS 10.10, *)
    @MainActor open var gestureRecognizers: [NSGestureRecognizer] {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/getrectsbeingdrawn(_:count:)
    @MainActor open func getRectsBeingDrawn(_ rects: UnsafeMutablePointer<UnsafePointer<NSRect>?>?, count: UnsafeMutablePointer<Int>?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/getrectsexposedduringliveresize(_:count:)
    @MainActor open func getRectsExposedDuringLiveResize(_ exposedRects: UnsafeMutablePointer<NSRect>, count: UnsafeMutablePointer<Int>) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/globalframedidchangenotification
    static public var globalFrameDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSViewGlobalFrameDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/hasambiguouslayout
    @MainActor open var hasAmbiguousLayout: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/heightadjustlimit
    @MainActor open var heightAdjustLimit: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/heightanchor
    @available(macOS 10.11, *)
    @MainActor open var heightAnchor: NSLayoutDimension { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/hittest(_:)
    @MainActor open func hitTest(_ point: NSPoint) -> NSView? {
        guard !_isHidden else { return nil }
        let p = _fromSuperview(point)
        guard bounds.contains(p) else { return nil }
        for s in _subviews.reversed() { if let hit = s.hitTest(p) { return hit } }
        return self
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/inliveresize
    @MainActor open var inLiveResize: Bool { _window?.inLiveResize ?? false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/inputcontext
    @MainActor open var inputContext: NSTextInputContext? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/intrinsiccontentsize
    @MainActor open var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/invalidateintrinsiccontentsize()
    @MainActor open func invalidateIntrinsicContentSize() { _superview?.needsLayout = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/iscompatiblewithresponsivescrolling
    @MainActor class public var isCompatibleWithResponsiveScrolling: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isdescendant(of:)
    @MainActor open func isDescendant(of view: NSView) -> Bool {
        var v: NSView? = self
        while let cur = v { if cur === view { return true }; v = cur._superview }
        return false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isdrawingfindindicator
    @MainActor open var isDrawingFindIndicator: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isflipped
    @MainActor open var isFlipped: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/ishidden
    @MainActor open var isHidden: Bool {
        get { _isHidden }
        set {
            guard newValue != _isHidden else { return }
            _isHidden = newValue
            _superview?.setNeedsDisplay(_frame)
            if newValue { viewDidHide() } else { viewDidUnhide() }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/ishiddenorhashiddenancestor
    @MainActor open var isHiddenOrHasHiddenAncestor: Bool { _isHidden || (_superview?.isHiddenOrHasHiddenAncestor ?? false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/ishorizontalcontentsizeconstraintactive
    @available(macOS 10.15, *)
    @MainActor open var isHorizontalContentSizeConstraintActive: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isinfullscreenmode
    @MainActor open var isInFullScreenMode: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/ismousepoint(_:in:)
    @MainActor open func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isopaque
    @MainActor open var isOpaque: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isrotatedfrombase
    @MainActor open var isRotatedFromBase: Bool { _frameRotation != 0 || _boundsRotation != 0 || (_superview?.isRotatedFromBase ?? false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isrotatedorscaledfrombase
    @MainActor open var isRotatedOrScaledFromBase: Bool { isRotatedFromBase || _boundsSize != nil || (_superview?.isRotatedOrScaledFromBase ?? false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/isverticalcontentsizeconstraintactive
    @available(macOS 10.15, *)
    @MainActor open var isVerticalContentSizeConstraintActive: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/knowspagerange(_:)
    @MainActor open func knowsPageRange(_ range: NSRangePointer) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lastbaselineanchor
    @available(macOS 10.11, *)
    @MainActor open var lastBaselineAnchor: NSLayoutYAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lastbaselineoffsetfrombottom
    @available(macOS 10.11, *)
    @MainActor open var lastBaselineOffsetFromBottom: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layer
    @MainActor open var layer: CALayer? {
        get { nil }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement
    @MainActor open var layerContentsPlacement: NSView.LayerContentsPlacement {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsredrawpolicy
    @MainActor open var layerContentsRedrawPolicy: NSView.LayerContentsRedrawPolicy {
        get { _layerContentsRedrawPolicy }
        set { _layerContentsRedrawPolicy = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layerusescoreimagefilters
    @MainActor open var layerUsesCoreImageFilters: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layout()
    @MainActor open func layout() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutguide(for:)
    @available(macOS 26.0, *)
    @MainActor open func layoutGuide(for region: NSView.LayoutRegion) -> NSLayoutGuide { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutguides
    @available(macOS 10.11, *)
    @MainActor open var layoutGuides: [NSLayoutGuide] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutmarginsguide
    @available(macOS 11.0, *)
    @MainActor open var layoutMarginsGuide: NSLayoutGuide { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutsubtreeifneeded()
    @MainActor open func layoutSubtreeIfNeeded() {
        if _needsLayout { _needsLayout = false; layout() }
        for s in _subviews { s.layoutSubtreeIfNeeded() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/leadinganchor
    @available(macOS 10.11, *)
    @MainActor open var leadingAnchor: NSLayoutXAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/leftanchor
    @available(macOS 10.11, *)
    @MainActor open var leftAnchor: NSLayoutXAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/locationofprintrect(_:)
    @MainActor open func locationOfPrintRect(_ rect: NSRect) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lockfocus()
    @MainActor open func lockFocus() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lockfocusifcandraw()
    @MainActor open func lockFocusIfCanDraw() -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lockfocusifcandraw(in:)
    @MainActor open func lockFocusIfCanDraw(in context: NSGraphicsContext) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/makebackinglayer()
    @MainActor open func makeBackingLayer() -> CALayer { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/menu(for:)
    @MainActor open func menu(for event: NSEvent) -> NSMenu? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/mousedowncanmovewindow
    @MainActor open var mouseDownCanMoveWindow: Bool { !isOpaque }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/needsdisplay
    @MainActor open var needsDisplay: Bool {
        get { _needsDisplay }
        set { if newValue { setNeedsDisplay(bounds) } else { _needsDisplay = false } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/needslayout
    @MainActor open var needsLayout: Bool {
        get { _needsLayout }
        set { _needsLayout = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/needspaneltobecomekey
    @MainActor open var needsPanelToBecomeKey: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/needstodraw(_:)
    @MainActor open func needsToDraw(_ rect: NSRect) -> Bool { (_dirtyRect ?? bounds).intersects(rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/needsupdateconstraints
    @MainActor open var needsUpdateConstraints: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/nextkeyview
    @MainActor open var nextKeyView: NSView? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/nextvalidkeyview
    @MainActor open var nextValidKeyView: NSView? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/nointrinsicmetric
    @available(macOS 10.11, *)
    static public var noIntrinsicMetric: CGFloat { -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/notefocusringmaskchanged()
    @MainActor open func noteFocusRingMaskChanged() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/opaqueancestor
    @MainActor open var opaqueAncestor: NSView? {
        var v: NSView? = self
        while let cur = v { if cur.isOpaque { return cur }; v = cur._superview }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/pagefooter
    @MainActor open var pageFooter: NSAttributedString { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/pageheader
    @MainActor open var pageHeader: NSAttributedString { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/performkeyequivalent(with:)
    @MainActor open override func performKeyEquivalent(with event: NSEvent) -> Bool {
        for s in _subviews where !s._isHidden { if s.performKeyEquivalent(with: event) { return true } }
        return false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/postsboundschangednotifications
    @MainActor open var postsBoundsChangedNotifications: Bool {
        get { _postsBoundsChangedNotifications }
        set { _postsBoundsChangedNotifications = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/postsframechangednotifications
    @MainActor open var postsFrameChangedNotifications: Bool {
        get { _postsFrameChangedNotifications }
        set { _postsFrameChangedNotifications = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/preferscompactcontrolsizemetrics
    @available(macOS 26.0, *)
    @MainActor open var prefersCompactControlSizeMetrics: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/preparecontent(in:)
    @MainActor open func prepareContent(in rect: NSRect) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/prepareforreuse()
    @MainActor open func prepareForReuse() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/preparedcontentrect
    @MainActor open var preparedContentRect: NSRect {
        get { _preparedContentRect ?? visibleRect }
        set { _preparedContentRect = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/preservescontentduringliveresize
    @MainActor open var preservesContentDuringLiveResize: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/pressureconfiguration
    @available(macOS 10.11, *)
    @MainActor open var pressureConfiguration: NSPressureConfiguration? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/previouskeyview
    @MainActor open var previousKeyView: NSView? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/previousvalidkeyview
    @MainActor open var previousValidKeyView: NSView? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/printjobtitle
    @MainActor open var printJobTitle: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/printview(_:)
    @MainActor open func printView(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rect(for:)
    @available(macOS 26.0, *)
    @MainActor open func rect(for region: NSView.LayoutRegion) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rectforpage(_:)
    @MainActor open func rectForPage(_ page: Int) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rectforsmartmagnification(at:in:)
    @MainActor open func rectForSmartMagnification(at location: NSPoint, in visibleRect: NSRect) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rectpreservedduringliveresize
    @MainActor open var rectPreservedDuringLiveResize: NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/reflectscrolledclipview(_:)
    @MainActor open func reflectScrolledClipView(_ clipView: NSClipView) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/registerfordraggedtypes(_:)
    @MainActor open func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/registereddraggedtypes
    @MainActor open var registeredDraggedTypes: [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/releasegstate()
    @MainActor open func releaseGState() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removealltooltips()
    @MainActor open func removeAllToolTips() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removeconstraint(_:)
    @MainActor open func removeConstraint(_ constraint: NSLayoutConstraint) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removeconstraints(_:)
    @MainActor open func removeConstraints(_ constraints: [NSLayoutConstraint]) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removecursorrect(_:cursor:)
    @MainActor open func removeCursorRect(_ rect: NSRect, cursor object: NSCursor) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removefromsuperview()
    @MainActor open func removeFromSuperview() {
        let f = _frame
        let sup = _superview
        removeFromSuperviewWithoutNeedingDisplay()
        sup?.setNeedsDisplay(f)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removefromsuperviewwithoutneedingdisplay()
    @MainActor open func removeFromSuperviewWithoutNeedingDisplay() {
        guard let sup = _superview else { return }
        sup.willRemoveSubview(self)
        sup._subviews.removeAll { $0 === self }
        viewWillMove(toSuperview: nil)
        _superview = nil
        nextResponder = nil
        if let w = _window, w.firstResponder === self { _ = w.makeFirstResponder(nil) }
        _setWindow(nil)
        viewDidMoveToSuperview()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removegesturerecognizer(_:)
    @available(macOS 10.10, *)
    @MainActor open func removeGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removelayoutguide(_:)
    @available(macOS 10.11, *)
    @MainActor open func removeLayoutGuide(_ guide: NSLayoutGuide) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removetooltip(_:)
    @MainActor open func removeToolTip(_ tag: NSView.ToolTipTag) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removetrackingarea(_:)
    @MainActor open func removeTrackingArea(_ trackingArea: NSTrackingArea) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removetrackingrect(_:)
    @MainActor open func removeTrackingRect(_ tag: NSView.TrackingRectTag) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/renewgstate()
    @MainActor open func renewGState() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/replacesubview(_:with:)
    @MainActor open func replaceSubview(_ oldView: NSView, with newView: NSView) {
        guard let i = _subviews.firstIndex(where: { $0 === oldView }) else { return }
        let below = i < _subviews.count - 1 ? _subviews[i + 1] : nil
        oldView.removeFromSuperview()
        if let below { addSubview(newView, positioned: .below, relativeTo: below) } else { addSubview(newView) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/requiresconstraintbasedlayout
    @MainActor class public var requiresConstraintBasedLayout: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/resetcursorrects()
    @MainActor open func resetCursorRects() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/resize(witholdsuperviewsize:)
    @MainActor open func resize(withOldSuperviewSize oldSize: NSSize) {
        guard let sup = _superview, !_autoresizingMask.isEmpty else { return }
        let newSize = sup.bounds.size
        let mask = _autoresizingMask
        var f = _frame

        func distribute(_ parts: [CGFloat], _ flexible: [Bool], _ delta: CGFloat) -> [CGFloat] {
            let flexTotal = zip(parts, flexible).filter { $0.1 }.map { $0.0 }.reduce(0, +)
            let flexCount = flexible.filter { $0 }.count
            guard flexCount > 0 else { return parts }
            return zip(parts, flexible).map { part, flex in
                guard flex else { return part }
                return flexTotal > 0 ? part + delta * part / flexTotal : part + delta / CGFloat(flexCount)
            }
        }
        let h = distribute([f.minX, f.width, oldSize.width - f.maxX],
                           [mask.contains(.minXMargin), mask.contains(.width), mask.contains(.maxXMargin)],
                           newSize.width - oldSize.width)
        let v = distribute([f.minY, f.height, oldSize.height - f.maxY],
                           [mask.contains(.minYMargin), mask.contains(.height), mask.contains(.maxYMargin)],
                           newSize.height - oldSize.height)
        f = NSRect(x: h[0], y: v[0], width: max(0, h[1]), height: max(0, v[1]))
        frame = f
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/resizesubviews(witholdsize:)
    @MainActor open func resizeSubviews(withOldSize oldSize: NSSize) {
        for s in _subviews { s.resize(withOldSuperviewSize: oldSize) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rightanchor
    @available(macOS 10.11, *)
    @MainActor open var rightAnchor: NSLayoutXAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rotate(bydegrees:)
    @MainActor open func rotate(byDegrees angle: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:didadd:)
    @MainActor open func rulerView(_ ruler: NSRulerView, didAdd marker: NSRulerMarker) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:didmove:)
    @MainActor open func rulerView(_ ruler: NSRulerView, didMove marker: NSRulerMarker) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:didremove:)
    @MainActor open func rulerView(_ ruler: NSRulerView, didRemove marker: NSRulerMarker) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:handlemousedownwith:)
    @MainActor open func rulerView(_ ruler: NSRulerView, handleMouseDownWith event: NSEvent) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:locationfor:)
    @MainActor open func rulerView(_ ruler: NSRulerView, locationFor point: NSPoint) -> CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:pointforlocation:)
    @MainActor open func rulerView(_ ruler: NSRulerView, pointForLocation point: CGFloat) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:shouldadd:)
    @MainActor open func rulerView(_ ruler: NSRulerView, shouldAdd marker: NSRulerMarker) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:shouldmove:)
    @MainActor open func rulerView(_ ruler: NSRulerView, shouldMove marker: NSRulerMarker) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:shouldremove:)
    @MainActor open func rulerView(_ ruler: NSRulerView, shouldRemove marker: NSRulerMarker) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:willadd:atlocation:)
    @MainActor open func rulerView(_ ruler: NSRulerView, willAdd marker: NSRulerMarker, atLocation location: CGFloat) -> CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:willmove:tolocation:)
    @MainActor open func rulerView(_ ruler: NSRulerView, willMove marker: NSRulerMarker, toLocation location: CGFloat) -> CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/rulerview(_:willsetclientview:)
    @MainActor open func rulerView(_ ruler: NSRulerView, willSetClientView newClient: NSView) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/safeareainsets
    @available(macOS 11.0, *)
    @MainActor open var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/safearealayoutguide
    @available(macOS 11.0, *)
    @MainActor open var safeAreaLayoutGuide: NSLayoutGuide { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/safearearect
    @available(macOS 11.0, *)
    @MainActor open var safeAreaRect: NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/scaleunitsquare(to:)
    @MainActor open func scaleUnitSquare(to newUnitSize: NSSize) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/scroll(_:)
    @MainActor open func scroll(_ point: NSPoint) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/scroll(_:by:)
    @MainActor open func scroll(_ rect: NSRect, by delta: NSSize) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/scroll(_:to:)
    @MainActor open func scroll(_ clipView: NSClipView, to point: NSPoint) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/scrolltovisible(_:)
    @MainActor open func scrollToVisible(_ rect: NSRect) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setboundsorigin(_:)
    @MainActor open func setBoundsOrigin(_ newOrigin: NSPoint) {
        guard newOrigin != _boundsOrigin else { return }
        _boundsOrigin = newOrigin
        setNeedsDisplay(bounds)
        if _postsBoundsChangedNotifications {
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: self)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setboundssize(_:)
    @MainActor open func setBoundsSize(_ newSize: NSSize) {
        // Bounds scaling (bounds.size != frame.size) is recorded but not yet applied as a
        // drawing transform.
        _boundsSize = newSize == _frame.size ? nil : newSize
        setNeedsDisplay(bounds)
        if _postsBoundsChangedNotifications {
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: self)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setcontentcompressionresistancepriority(_:for:)
    @MainActor open func setContentCompressionResistancePriority(_ priority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setcontenthuggingpriority(_:for:)
    @MainActor open func setContentHuggingPriority(_ priority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setframeorigin(_:)
    @MainActor open func setFrameOrigin(_ newOrigin: NSPoint) {
        guard newOrigin != _frame.origin else { return }
        let old = _frame
        _frame.origin = newOrigin
        _superview?.setNeedsDisplay(old.union(_frame))
        if _postsFrameChangedNotifications {
            NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: self)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setframesize(_:)
    @MainActor open func setFrameSize(_ newSize: NSSize) {
        guard newSize != _frame.size else { return }
        let old = _frame
        _frame.size = newSize
        if _autoresizesSubviews { resizeSubviews(withOldSize: old.size) }
        _superview?.setNeedsDisplay(old.union(_frame))
        setNeedsDisplay(bounds)
        if _postsFrameChangedNotifications {
            NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: self)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setkeyboardfocusringneedsdisplay(_:)
    @MainActor open func setKeyboardFocusRingNeedsDisplay(_ rect: NSRect) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setneedsdisplay(_:)
    @MainActor open func setNeedsDisplay(_ invalidRect: NSRect) { _invalidate(invalidRect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setupgstate()
    @MainActor open func setUpGState() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/shadow
    @MainActor open var shadow: NSShadow? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/shoulddelaywindowordering(for:)
    @MainActor open func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/shoulddrawcolor()
    @MainActor open func shouldDrawColor() -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/showdefinition(for:at:)
    @MainActor open func showDefinition(for attrString: NSAttributedString?, at textBaselineOrigin: NSPoint) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/showdefinition(for:range:options:baselineoriginprovider:)
    @MainActor open func showDefinition(for attrString: NSAttributedString?, range targetRange: NSRange, options: [NSView.DefinitionOptionKey : Any]? = nil, baselineOriginProvider originProvider: ((NSRange) -> NSPoint)? = nil) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/sortsubviews(_:context:)
    @MainActor open func sortSubviews(_ compare: (NSView, NSView, UnsafeMutableRawPointer?) -> ComparisonResult, context: UnsafeMutableRawPointer?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/subviews
    @MainActor open var subviews: [NSView] {
        get { _subviews }
        set {
            for s in _subviews where !newValue.contains(where: { $0 === s }) { s.removeFromSuperview() }
            for s in newValue { if s._superview !== self { addSubview(s) } }
            _subviews = newValue
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/superview
    @MainActor open var superview: NSView? { _superview }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/tag
    @MainActor open var tag: Int { -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/tooltip
    @MainActor open var toolTip: String? {
        get { _toolTip }
        set { _toolTip = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/topanchor
    @available(macOS 10.11, *)
    @MainActor open var topAnchor: NSLayoutYAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/trackingareas
    @MainActor open var trackingAreas: [NSTrackingArea] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/trailinganchor
    @available(macOS 10.11, *)
    @MainActor open var trailingAnchor: NSLayoutXAxisAnchor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/translateorigin(to:)
    @MainActor open func translateOrigin(to translation: NSPoint) { setBoundsOrigin(NSPoint(x: _boundsOrigin.x - translation.x, y: _boundsOrigin.y - translation.y)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/translaterectsneedingdisplay(in:by:)
    @MainActor open func translateRectsNeedingDisplay(in clipRect: NSRect, by delta: NSSize) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/translatesautoresizingmaskintoconstraints
    @MainActor open var translatesAutoresizingMaskIntoConstraints: Bool {
        get { _translatesAutoresizingMaskIntoConstraints }
        set { _translatesAutoresizingMaskIntoConstraints = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/unlockfocus()
    @MainActor open func unlockFocus() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/unregisterdraggedtypes()
    @MainActor open func unregisterDraggedTypes() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updateconstraints()
    @MainActor open func updateConstraints() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updateconstraintsforsubtreeifneeded()
    @MainActor open func updateConstraintsForSubtreeIfNeeded() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updatelayer()
    @MainActor open func updateLayer() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updatetrackingareas()
    @MainActor open func updateTrackingAreas() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/userinterfacelayoutdirection
    @MainActor open var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { _userInterfaceLayoutDirection }
        set { _userInterfaceLayoutDirection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidchangebackingproperties()
    @MainActor open func viewDidChangeBackingProperties() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidchangeeffectiveappearance()
    @available(macOS 10.14, *)
    @MainActor open func viewDidChangeEffectiveAppearance() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidendliveresize()
    @MainActor open func viewDidEndLiveResize() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidhide()
    @MainActor open func viewDidHide() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidmovetosuperview()
    @MainActor open func viewDidMoveToSuperview() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidmovetowindow()
    @MainActor open func viewDidMoveToWindow() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewdidunhide()
    @MainActor open func viewDidUnhide() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewwilldraw()
    @MainActor open func viewWillDraw() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewwillmove(tosuperview:)
    @MainActor open func viewWillMove(toSuperview newSuperview: NSView?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewwillmove(towindow:)
    @MainActor open func viewWillMove(toWindow newWindow: NSWindow?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewwillstartliveresize()
    @MainActor open func viewWillStartLiveResize() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/viewwithtag(_:)
    @MainActor open func viewWithTag(_ tag: Int) -> NSView? {
        if self.tag == tag { return self }
        for s in _subviews { if let v = s.viewWithTag(tag) { return v } }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/visiblerect
    @MainActor open var visibleRect: NSRect {
        guard _window != nil, !isHiddenOrHasHiddenAncestor else { return .zero }
        guard let sup = _superview else { return bounds }
        return bounds.intersection(convert(sup.visibleRect, from: sup))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/wantsbestresolutionopenglsurface
    @MainActor open var wantsBestResolutionOpenGLSurface: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/wantsdefaultclipping
    @MainActor open var wantsDefaultClipping: Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/wantsextendeddynamicrangeopenglsurface
    @available(macOS 10.11, *)
    @MainActor open var wantsExtendedDynamicRangeOpenGLSurface: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/wantslayer
    @MainActor open var wantsLayer: Bool {
        get { _wantsLayer }
        set { _wantsLayer = newValue }   // Layer backing arrives with the QuartzCore port (Milestone 4).
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/wantsrestingtouches
    @MainActor open var wantsRestingTouches: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/wantsupdatelayer
    @MainActor open var wantsUpdateLayer: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/widthadjustlimit
    @MainActor open var widthAdjustLimit: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/widthanchor
    @available(macOS 10.11, *)
    @MainActor open var widthAnchor: NSLayoutDimension { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/willopenmenu(_:with:)
    @available(macOS 10.11, *)
    @MainActor open func willOpenMenu(_ menu: NSMenu, with event: NSEvent) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/willremovesubview(_:)
    @MainActor open func willRemoveSubview(_ subview: NSView) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/window
    @MainActor open var window: NSWindow? { _window }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/writeeps(inside:to:)
    @MainActor open func writeEPS(inside rect: NSRect, to pasteboard: NSPasteboard) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/writepdf(inside:to:)
    @MainActor open func writePDF(inside rect: NSRect, to pasteboard: NSPasteboard) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/writingtoolscoordinator
    @available(macOS 15.2, *)
    @MainActor open var writingToolsCoordinator: NSWritingToolsCoordinator? {
        get { unimplemented() }
        set { unimplemented() }
    }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityFrame() -> NSRect { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityParent() -> Any? { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func isAccessibilityFocused() -> Bool { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { unimplemented() }
}
