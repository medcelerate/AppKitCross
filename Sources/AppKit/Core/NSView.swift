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
    private var _layer: CALayer? = nil
    private var _layerIsHosted = false          // set through `layer =`: the view hosts a foreign layer tree
    private var _layerContentsPlacement: NSView.LayerContentsPlacement = .scaleAxesIndependently
    private var _canDrawSubviewsIntoLayer = false
    private var _animatorPending = false
    private var _appearance: NSAppearance? = nil
    private var _registeredDraggedTypes: [NSPasteboard.PasteboardType] = []
    /// What `draggingEntered` returned, for the default `draggingUpdated` (AppKit's rule).
    internal var _lastDraggingEnteredOperation: NSDragOperation = []
    private var _constraints: [NSLayoutConstraint] = []
    private var _layoutGuides: [NSLayoutGuide] = []
    private var _anchors: [NSLayoutConstraint.Attribute: AnyObject] = [:]
    private var _huggingPriority: [NSLayoutConstraint.Orientation: NSLayoutConstraint.Priority] = [:]
    private var _compressionPriority: [NSLayoutConstraint.Orientation: NSLayoutConstraint.Priority] = [:]
    private var _needsUpdateConstraints = true
    private var _constraintsDirty = false       // on a layout root: the engine must run
    private var _applyingLayout = false
    private var _engine: LayoutEngine? = nil
    private var _marginsGuide: NSLayoutGuide? = nil
    private var _safeAreaGuide: NSLayoutGuide? = nil
    /// The controller whose view this is (set by NSViewController).
    internal weak var _viewController: NSViewController? = nil
    private var _alphaValue: CGFloat = 1
    private var _needsLayout = true          // AppKit lays a view out at least once
    private var _translatesAutoresizingMaskIntoConstraints = true
    private var _identifier: NSUserInterfaceItemIdentifier? = nil
    private var _toolTip: String? = nil
    private var _gestureRecognizers: [NSGestureRecognizer] = []
    private var _accessibilityOverrides = _NSAccessibilityOverrides()
    private var _accessibilityID = 0
    private var _clipsToBounds = false
    private var _postsFrameChangedNotifications = false
    private var _postsBoundsChangedNotifications = false
    private var _focusRingType: NSFocusRingType = .default
    private var _layerContentsRedrawPolicy: NSView.LayerContentsRedrawPolicy = .never
    private var _userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection?   // nil: inherited
    private var _frameRotation: CGFloat = 0
    private var _boundsRotation: CGFloat = 0
    private var _preparedContentRect: NSRect? = nil
    internal var _cursorRects: [(NSRect, NSCursor)] = []
    internal var _cursorRectsValid = false

    /// Cursor for a point in this view's bounds, consulting (and lazily rebuilding) cursor rects.
    @MainActor internal func _cursor(at point: NSPoint) -> NSCursor? {
        if !_cursorRectsValid {
            _cursorRects.removeAll()
            resetCursorRects()
            _cursorRectsValid = true
        }
        for (rect, cursor) in _cursorRects.reversed() where rect.contains(point) { return cursor }
        return nil
    }

    open override var description: String { MainActor.assumeIsolated { "<\(type(of: self)) frame=\(_frame)>" } }

    // MARK: Auto Layout plumbing

    /// The view whose engine solves this view's constraints: the topmost ancestor.
    internal var _layoutRoot: NSView {
        var v = self
        while let s = v._superview { v = s }
        return v
    }

    /// Marks the engine root dirty; the next layout pass re-solves.
    /// Marks the layout root for another constraint pass. A plain frame change
    /// (`force` false) only does so once an engine exists: re-laying out the whole root
    /// for every frame set would turn any two disagreeing sizes into an endless loop.
    internal func _setNeedsConstraintLayout(force: Bool = true) {
        let root = _layoutRoot
        guard force || root._engine != nil else { return }
        root._constraintsDirty = true
        root._needsLayout = true
        if let w = root._window, root === w.contentView { w._viewNeedsDisplay(root, rect: root.bounds) }
    }

    /// Whether any view in the subtree has constraints, layout guides or opts out of
    /// autoresizing translation (the engine is only built when it has work).
    internal var _subtreeUsesConstraints: Bool {
        if !_constraints.isEmpty || !_layoutGuides.isEmpty || !_translatesAutoresizingMaskIntoConstraints { return true }
        return _subviews.contains { $0._subtreeUsesConstraints }
    }

    /// Runs the engine for this root if anything changed.
    private func _solveConstraintsIfNeeded() {
        guard _constraintsDirty else { return }
        _constraintsDirty = false
        updateConstraintsForSubtreeIfNeeded()
        guard _subtreeUsesConstraints else { return }
        if _engine == nil { _engine = LayoutEngine(root: self) }
        _applyingLayout = true
        _engine!.solve(root: self)
        _applyingLayout = false
    }

    /// Sets a frame computed by the engine without re-dirtying the engine.
    internal func _applyLayoutFrame(_ f: NSRect) {
        guard f != _frame else { return }
        let root = _layoutRoot
        let wasDirty = root._constraintsDirty
        let old = _frame
        setFrameOrigin(f.origin)
        setFrameSize(f.size)
        root._constraintsDirty = wasDirty
        if old.size != f.size { _needsLayout = true }
    }

    private func anchorX(_ a: NSLayoutConstraint.Attribute) -> NSLayoutXAxisAnchor {
        if let x = _anchors[a] as? NSLayoutXAxisAnchor { return x }
        let x = NSLayoutXAxisAnchor(item: self, attribute: a)
        _anchors[a] = x
        return x
    }
    private func anchorY(_ a: NSLayoutConstraint.Attribute) -> NSLayoutYAxisAnchor {
        if let y = _anchors[a] as? NSLayoutYAxisAnchor { return y }
        let y = NSLayoutYAxisAnchor(item: self, attribute: a)
        _anchors[a] = y
        return y
    }
    private func anchorDimension(_ a: NSLayoutConstraint.Attribute) -> NSLayoutDimension {
        if let d = _anchors[a] as? NSLayoutDimension { return d }
        let d = NSLayoutDimension(item: self, attribute: a)
        _anchors[a] = d
        return d
    }

    /// A guide pinned to the view's edges (layout margins and safe area are the bounds here).
    private func _edgeGuide(_ slot: inout NSLayoutGuide?, name: String) -> NSLayoutGuide {
        if let g = slot { return g }
        let g = NSLayoutGuide()
        g.identifier = NSUserInterfaceItemIdentifier(name)
        addLayoutGuide(g)
        NSLayoutConstraint.activate([
            g.leadingAnchor.constraint(equalTo: leadingAnchor), g.trailingAnchor.constraint(equalTo: trailingAnchor),
            g.topAnchor.constraint(equalTo: topAnchor), g.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        slot = g
        return g
    }

    // MARK: Layer backing

    /// Gives the view a backing layer (AppKit makes the whole subtree layer-backed).
    internal func _becomeLayerBacked() {
        _CoreAnimationHost.installIfNeeded()
        _wantsLayer = true
        if _layer == nil {
            let l = makeBackingLayer()
            _layer = l
            _configureBackingLayer(l)
        }
        _attachLayerToSuperview()
        for s in _subviews { s._becomeLayerBacked() }
        if let w = _window, w.contentView === self { w._updateLayerHosting() }
    }

    private func _configureBackingLayer(_ l: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.delegate = self
        l.anchorPoint = .zero
        l.isGeometryFlipped = isFlipped
        _syncLayerGeometry()
        l.isHidden = _isHidden
        l.opacity = Float(_alphaValue)
        l.masksToBounds = _clipsToBounds
        l.contentsScale = _window?.backingScaleFactor ?? 1
        CATransaction.commit()
    }

    /// Mirrors frame/bounds into the backing layer without animating.
    private func _syncLayerGeometry() {
        guard let l = _layer, !_layerIsHosted else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.bounds = bounds
        l.position = _frame.origin
        CATransaction.commit()
    }

    /// Puts the backing layer into the superview's layer (or makes it a root this view hosts).
    private func _attachLayerToSuperview() {
        guard let l = _layer else { return }
        if let sup = _superview, let sl = sup._layer, !sup._layerIsHosted {
            if l.superlayer !== sl {
                var i = 0
                for v in sup._subviews {
                    if v === self { break }
                    if let vl = v._layer, vl.superlayer === sl { i += 1 }
                }
                sl.insertSublayer(l, at: UInt32(min(i, sl.sublayers?.count ?? 0)))
            }
            l.host = nil
        } else {
            if l.superlayer != nil { l.removeFromSuperlayer() }
            l.host = self
        }
    }

    /// True when this view's layer is the root of a layer tree (its superview is not layer-backed).
    private var _isLayerRoot: Bool { _layer != nil && (_superview?._layer == nil || _superview?._layerIsHosted == true) }

    /// Foreign layer trees hosted by subviews (`view.layer = tree`): they sit outside this
    /// view's layer, so the scene builder is told about them here.
    internal var _hostedChildLayers: [CALayer] { _subviews.compactMap { $0._layerIsHosted ? $0._layer : nil } }

    /// Takes the one-shot `animator()` flag.
    private func _takeAnimator() -> Bool {
        let a = _animatorPending
        _animatorPending = false
        return a
    }

    /// Runs an explicit animation on the backing layer for a change made through `animator()`.
    private func _animateLayer(_ key: String, from: Any?, to: Any?) {
        guard let l = _layer, !_layerIsHosted else { return }
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.duration = NSAnimationContext.current.duration
        a.timingFunction = NSAnimationContext.current.timingFunction
        l.add(a, forKey: key)
    }

    // MARK: Window propagation

    internal func _setWindow(_ window: NSWindow?) {
        guard _window !== window else { return }
        let old = _window
        // Appearance callbacks follow on-screen visibility, as in AppKit.
        let appearing = window?.isVisible == true, disappearing = old?.isVisible == true && window == nil
        if appearing { _viewController?.viewWillAppear() } else if disappearing { _viewController?.viewWillDisappear() }
        viewWillMove(toWindow: window)
        for s in _subviews { s._setWindow(window) }
        _window = window
        if let l = _layer, let w = window { l.contentsScale = w.backingScaleFactor }
        viewDidMoveToWindow()
        if appearing { _viewController?.viewDidAppear() } else if disappearing { _viewController?.viewDidDisappear() }
    }

    /// The window is about to be shown or hidden: view controllers in the tree hear about it.
    internal func _windowVisibilityWillChange(_ visible: Bool) {
        if visible { _viewController?.viewWillAppear() } else { _viewController?.viewWillDisappear() }
        for s in _subviews { s._windowVisibilityWillChange(visible) }
    }

    internal func _windowVisibilityDidChange(_ visible: Bool) {
        if visible { _viewController?.viewDidAppear() } else { _viewController?.viewDidDisappear() }
        if visible, let l = _layer, _isLayerRoot { CARuntime.resumeAnimations(of: l) }
        for s in _subviews { s._windowVisibilityDidChange(visible) }
    }

    /// Called on the superview when a subview's `isHidden` changes (stack views re-layout).
    internal func _subviewDidChangeHidden(_ subview: NSView) { }

    // MARK: Coordinate math (own bounds <-> superview coordinates)

    /// Whether this view's orientation differs from its superview's (the window's content
    /// space is y-up). Only then does the frame mapping flip.
    internal var _flipsRelativeToSuperview: Bool { isFlipped != (_superview?.isFlipped ?? false) }

    internal func _toSuperview(_ p: NSPoint) -> NSPoint {
        let b = bounds
        let x = p.x - b.minX + _frame.minX
        let y = _flipsRelativeToSuperview ? _frame.minY + (b.maxY - p.y) : p.y - b.minY + _frame.minY
        return NSPoint(x: x, y: y)
    }

    internal func _fromSuperview(_ p: NSPoint) -> NSPoint {
        let b = bounds
        let x = p.x - _frame.minX + b.minX
        let y = _flipsRelativeToSuperview ? b.maxY - (p.y - _frame.minY) : p.y - _frame.minY + b.minY
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
        if let l = _layer, _isLayerRoot {
            if let w = _window, w._hostsLayersNatively, w.contentView === self, !NSView._cachingDisplay {
                // The platform composites the tree from the committed scene (an offscreen
                // `cacheDisplay` still composes it here: screenshots on DirectComposition).
                _clearNeedsDisplay()
                return
            }
            // Layer-backed subtree: Core Animation composites it (each view draws through
            // its layer's delegate callback).
            layoutSubtreeIfNeeded()
            ctx.saveGState()
            ctx.clip(to: dirtyRect)
            l._compose(into: ctx, parentFlipped: _superview?.isFlipped ?? false, alpha: 1, time: CARuntime.now(), dirty: dirtyRect)
            ctx.restoreGState()
            _clearNeedsDisplay()
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: _frame.minX, y: _frame.minY)
        if _flipsRelativeToSuperview {
            ctx.translateBy(x: 0, y: _frame.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        let b = bounds
        ctx.translateBy(x: -b.minX, y: -b.minY)
        let localDirty = _convertRect(dirtyRect, _fromSuperview).intersection(b)
        // Drawing is confined to the dirty region, as in AppKit: siblings outside it keep
        // their pixels.
        ctx.clip(to: wantsDefaultClipping ? localDirty : _convertRect(dirtyRect, _fromSuperview))
        if _alphaValue < 1 { ctx.setAlpha(_alphaValue) }
        let gc = NSGraphicsContext(cgContext: ctx, flipped: isFlipped)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = gc
        let previousAppearance = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        viewWillDraw()
        _dirtyRect = localDirty
        draw(localDirty)
        _dirtyRect = nil
        for sub in _subviews { sub._displayHierarchy(in: ctx, dirtyRect: localDirty) }
        NSAppearance.current = previousAppearance
        NSGraphicsContext.current = previous
        ctx.restoreGState()
        _needsDisplay = false
    }

    private func _clearNeedsDisplay() {
        _needsDisplay = false
        for s in _subviews { s._clearNeedsDisplay() }
    }

    /// `APPKITWIN_TRACE=1` logs every view invalidation (view class and rect), for finding
    /// what keeps a window repainting on a platform without usable backtraces.
    nonisolated(unsafe) public static let _traceInvalidation = ProcessInfo.processInfo.environment["APPKITWIN_TRACE"] != nil
    /// Unbuffered, so a killed process keeps the tail of the trace.
    public static func _trace(_ message: String) { fputs("[trace] \(message)\n", stderr) }

    private func _invalidate(_ rect: NSRect) {
        if NSView._traceInvalidation { NSView._trace("setNeedsDisplay \(type(of: self)) \(rect)") }
        _needsDisplay = true
        if let l = _layer, !_layerIsHosted {
            // Under native hosting the layer's raster must be versioned and recommitted;
            // in software the window repaint below redraws it anyway.
            if _window?._hostsLayersNatively == true { l.setNeedsDisplay() } else { l._markNeedsDisplayQuietly() }
        }
        if let w = _window {
            w._viewNeedsDisplay(self, rect: rect)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/appearance
    @MainActor public var appearance: NSAppearance? {
        get { _appearance }
        set { _appearance = newValue; _effectiveAppearanceDidChange(); setNeedsDisplay(bounds) }
    }

    /// Inherited from the superview, then the window, then the application.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/effectiveappearance
    @MainActor public var effectiveAppearance: NSAppearance {
        _appearance ?? _superview?.effectiveAppearance ?? _window?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
    }

    internal func _effectiveAppearanceDidChange() {
        if NSView._traceInvalidation { NSView._trace("effectiveAppearanceDidChange \(type(of: self))") }
        viewDidChangeEffectiveAppearance()
        for s in _subviews where s._appearance == nil { s._effectiveAppearanceDidChange() }
    }

    /// The animator proxy. The next `frame`/`alphaValue` change on a layer-backed view
    /// animates over `NSAnimationContext.current.duration`; other views change at once.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsanimatablepropertycontainer/animator()
    @MainActor public func animator() -> Self {
        _animatorPending = _layer != nil
        return self
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/identifier
    @MainActor open var identifier: NSUserInterfaceItemIdentifier? {
        get { _identifier }
        set { _identifier = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/init(coder:)
    public required init?(coder: NSCoder) {
        _frame = .zero
        super.init(coder: coder)
    }
    /// AppKit inherits `init()` from NSObject; it is a zero frame.
    @MainActor public convenience override init() { self.init(frame: .zero) }

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
    @MainActor open func addConstraint(_ constraint: NSLayoutConstraint) {
        if let h = constraint._holder, h !== self { h.removeConstraint(constraint) }
        guard !_constraints.contains(where: { $0 === constraint }) else { return }
        _constraints.append(constraint)
        constraint._setActiveFlag(true, holder: self)
        _setNeedsConstraintLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addconstraints(_:)
    @MainActor open func addConstraints(_ constraints: [NSLayoutConstraint]) { for c in constraints { addConstraint(c) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addcursorrect(_:cursor:)
    @MainActor open func addCursorRect(_ rect: NSRect, cursor object: NSCursor) { _cursorRects.append((rect, object)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addgesturerecognizer(_:)
    @available(macOS 10.10, *)
    @MainActor open func addGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        if let old = gestureRecognizer.view, old !== self { old.removeGestureRecognizer(gestureRecognizer) }
        guard !_gestureRecognizers.contains(where: { $0 === gestureRecognizer }) else { return }
        _gestureRecognizers.append(gestureRecognizer)
        gestureRecognizer._setView(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addlayoutguide(_:)
    @available(macOS 10.11, *)
    @MainActor open func addLayoutGuide(_ guide: NSLayoutGuide) {
        guide.owningView?.removeLayoutGuide(guide)
        _layoutGuides.append(guide)
        guide.owningView = self
        _setNeedsConstraintLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addsubview(_:)
    @MainActor open func addSubview(_ view: NSView) {
        addSubview(view, positioned: .above, relativeTo: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/addsubview(_:positioned:relativeto:)
    @MainActor open func addSubview(_ view: NSView, positioned place: NSWindow.OrderingMode, relativeTo otherView: NSView?) {
        precondition(view !== self, "NSView: cannot add a view as a subview of itself")
        if NSView._traceInvalidation { NSView._trace("addSubview \(type(of: view)) to \(type(of: self))\(view._superview === self ? " (re-add)" : "")") }
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
        if let vc = view._viewController { view.nextResponder = vc; vc.nextResponder = self } else { view.nextResponder = self }
        view._setWindow(_window)
        if _layer != nil && !_layerIsHosted { view._becomeLayerBacked() } else if view._layer != nil { view._attachLayerToSuperview() }
        // A new constraint participant needs a root pass; a plain view (re)added does not,
        // or every backing-view reorder would schedule another full layout.
        _setNeedsConstraintLayout(force: view._subtreeUsesConstraints)
        if view._appearance == nil { view._effectiveAppearanceDidChange() }
        view.viewDidMoveToSuperview()
        didAddSubview(view)
        setNeedsDisplay(view._frame)
        if _window != nil { view._accessibilityStructureChanged() }
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
    @MainActor open var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
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
        set {
            let animate = _takeAnimator()
            let old = _alphaValue
            _alphaValue = newValue
            if let l = _layer, !_layerIsHosted {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.opacity = Float(newValue)
                CATransaction.commit()
                if animate { _animateLayer("opacity", from: CGFloat(old), to: newValue) }
            }
            setNeedsDisplay(bounds)
        }
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
    @MainActor open var baselineOffsetFromBottom: CGFloat { 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/begindocument()
    @MainActor open func beginDocument() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:)
    /// Starts a drag. Unlike AppKit this returns at once: the session tracks through the
    /// application's event stream and reports to `source` as it goes.
    @MainActor open func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession {
        _NSDragTracker.begin(items: items, event: event, source: source, view: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/beginpage(in:atplacement:)
    @MainActor open func beginPage(in rect: NSRect, atPlacement location: NSPoint) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/bitmapimagerepforcachingdisplay(in:)
    @MainActor open func bitmapImageRepForCachingDisplay(in rect: NSRect) -> NSBitmapImageRep? {
        let scale = window?.backingScaleFactor ?? 1
        guard let surface = Platform.backend.image.makeOffscreen(size: rect.size, scale: scale), let blank = surface.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: blank)
        rep.size = rect.size
        return rep
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/bottomanchor
    @available(macOS 10.11, *)
    @MainActor open var bottomAnchor: NSLayoutYAxisAnchor { anchorY(.bottom) }
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
    /// True while `cacheDisplay(in:to:)` renders: a natively hosted layer tree is then
    /// composed in software into the bitmap instead of being left to the platform.
    @MainActor static var _cachingDisplay = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/cachedisplay(in:to:)
    /// Renders the view and its subviews (what the window would draw) into `bitmapImageRep`.
    @MainActor open func cacheDisplay(in rect: NSRect, to bitmapImageRep: NSBitmapImageRep) {
        let scale = CGFloat(bitmapImageRep.pixelsWide) / max(1, rect.width)
        guard let surface = Platform.backend.image.makeOffscreen(size: rect.size, scale: scale) else { return }
        let ctx = surface.context
        layoutSubtreeIfNeeded()
        ctx.saveGState()
        // `_displayHierarchy` expects the superview's space; move `rect` to the origin.
        ctx.translateBy(x: -(_frame.minX + rect.minX), y: -(_frame.minY + rect.minY))
        let previous = NSGraphicsContext.current
        let wasCaching = NSView._cachingDisplay
        NSView._cachingDisplay = true
        // Layer contents redrawn during the capture resolve dynamic colours under the
        // view's appearance (a dark window stays dark in the bitmap).
        let previousAppearance = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        _displayHierarchy(in: ctx, dirtyRect: NSRect(x: _frame.minX + rect.minX, y: _frame.minY + rect.minY, width: rect.width, height: rect.height))
        NSAppearance.current = previousAppearance
        NSView._cachingDisplay = wasCaching
        NSGraphicsContext.current = previous
        ctx.restoreGState()
        if let image = surface.makeImage() { bitmapImageRep._setImage(image) }
    }
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
        get { _canDrawSubviewsIntoLayer }
        set { _canDrawSubviewsIntoLayer = newValue }
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
    @MainActor open var centerXAnchor: NSLayoutXAxisAnchor { anchorX(.centerX) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/centeryanchor
    @available(macOS 10.11, *)
    @MainActor open var centerYAnchor: NSLayoutYAxisAnchor { anchorY(.centerY) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/clipstobounds
    @MainActor open var clipsToBounds: Bool {
        get { _clipsToBounds }
        set {
            _clipsToBounds = newValue
            if let l = _layer, !_layerIsHosted { l.masksToBounds = newValue }
        }
    }
    // SKIPPED (unknown module (CoreImage CIFilter)): @MainActor var compositingFilter: CIFilter? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/constraints
    @MainActor open var constraints: [NSLayoutConstraint] { _constraints.filter { !$0._isInternal } }
    /// Every active constraint held here, including engine-internal ones.
    internal var _allConstraints: [NSLayoutConstraint] { _constraints }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/constraintsaffectinglayout(for:)
    @MainActor open func constraintsAffectingLayout(for orientation: NSLayoutConstraint.Orientation) -> [NSLayoutConstraint] {
        let horizontal: Set<NSLayoutConstraint.Attribute> = [.left, .right, .leading, .trailing, .width, .centerX]
        let attrs = orientation == .horizontal ? horizontal : Set([.top, .bottom, .height, .centerY, .firstBaseline, .lastBaseline])
        var out: [NSLayoutConstraint] = []
        var v: NSView? = self
        while let cur = v {
            out += cur._constraints.filter { ($0.firstItem === self && attrs.contains($0.firstAttribute)) || ($0.secondItem === self && attrs.contains($0.secondAttribute)) }
            v = cur._superview
        }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/contentcompressionresistancepriority(for:)
    @MainActor open func contentCompressionResistancePriority(for orientation: NSLayoutConstraint.Orientation) -> NSLayoutConstraint.Priority { _compressionPriority[orientation] ?? .defaultHigh }
    // SKIPPED (unknown module (CoreImage CIFilter)): @MainActor var contentFilters: [CIFilter] { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/contenthuggingpriority(for:)
    @MainActor open func contentHuggingPriority(for orientation: NSLayoutConstraint.Orientation) -> NSLayoutConstraint.Priority { _huggingPriority[orientation] ?? .defaultLow }
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
    @MainActor open func discardCursorRects() { _cursorRects.removeAll(); _cursorRectsValid = false }
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
    @MainActor open func displayLink(target: Any, selector: Selector) -> CADisplayLink {
        _CoreAnimationHost.installIfNeeded()
        let t = target as AnyObject
        return CADisplayLink { link in _ = ActionRegistry.perform(selector, on: t, with: link) }
    }
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
    @MainActor open func exerciseAmbiguityInLayout() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/exitfullscreenmode(options:)
    @MainActor open func exitFullScreenMode(options: [NSView.FullScreenModeOptionKey : Any]? = nil) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/firstbaselineanchor
    @available(macOS 10.11, *)
    @MainActor open var firstBaselineAnchor: NSLayoutYAxisAnchor { anchorY(.firstBaseline) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/firstbaselineoffsetfromtop
    @available(macOS 10.11, *)
    @MainActor open var firstBaselineOffsetFromTop: CGFloat { 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/fittingsize
    @MainActor open var fittingSize: NSSize {
        if _subtreeUsesConstraints {
            updateConstraintsForSubtreeIfNeeded()
            let engine = LayoutEngine(root: self)
            let s = engine.solve(root: self, fittingRoot: true, apply: false)
            return NSSize(width: s.width.rounded(), height: s.height.rounded())
        }
        let s = intrinsicContentSize
        return NSSize(width: max(0, s.width), height: max(0, s.height))
    }
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
        get { _gestureRecognizers }
        set {
            for r in _gestureRecognizers where !newValue.contains(where: { $0 === r }) { r._setView(nil) }
            _gestureRecognizers = []
            for r in newValue { addGestureRecognizer(r) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/getrectsbeingdrawn(_:count:)
    @MainActor open func getRectsBeingDrawn(_ rects: UnsafeMutablePointer<UnsafePointer<NSRect>?>?, count: UnsafeMutablePointer<Int>?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/getrectsexposedduringliveresize(_:count:)
    @MainActor open func getRectsExposedDuringLiveResize(_ exposedRects: UnsafeMutablePointer<NSRect>, count: UnsafeMutablePointer<Int>) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/globalframedidchangenotification
    static public var globalFrameDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSViewGlobalFrameDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/hasambiguouslayout
    @MainActor open var hasAmbiguousLayout: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/heightadjustlimit
    @MainActor open var heightAdjustLimit: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/heightanchor
    @available(macOS 10.11, *)
    @MainActor open var heightAnchor: NSLayoutDimension { anchorDimension(.height) }
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
    @MainActor open func invalidateIntrinsicContentSize() { _superview?.needsLayout = true; _setNeedsConstraintLayout() }
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
            _superview?._subviewDidChangeHidden(self)
            if let l = _layer, !_layerIsHosted {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.isHidden = newValue
                CATransaction.commit()
            }
            _superview?.setNeedsDisplay(_frame)
            if newValue { viewDidHide() } else { viewDidUnhide() }
            if _window != nil { _accessibilityStructureChanged() }
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
    @MainActor open var lastBaselineAnchor: NSLayoutYAxisAnchor { anchorY(.lastBaseline) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lastbaselineoffsetfrombottom
    @available(macOS 10.11, *)
    @MainActor open var lastBaselineOffsetFromBottom: CGFloat { baselineOffsetFromBottom }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layer
    @MainActor open var layer: CALayer? {
        get { _layer }
        set {
            // Layer-hosting: the view shows `newValue`'s tree and does not draw itself.
            if let old = _layer, old !== newValue {
                old.delegate = nil
                old.removeFromSuperlayer()
                old.host = nil
            }
            _layer = newValue
            _layerIsHosted = newValue != nil
            if let l = newValue {
                _CoreAnimationHost.installIfNeeded()
                CATransaction.begin(); CATransaction.setDisableActions(true)
                l.contentsScale = _window?.backingScaleFactor ?? 1
                CATransaction.commit()
                l.removeFromSuperlayer()
                l.host = self
            }
            setNeedsDisplay(bounds)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layercontentsplacement
    @MainActor open var layerContentsPlacement: NSView.LayerContentsPlacement {
        get { _layerContentsPlacement }
        set { _layerContentsPlacement = newValue }
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
    @MainActor open var layoutGuides: [NSLayoutGuide] { _layoutGuides }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutmarginsguide
    @available(macOS 11.0, *)
    @MainActor open var layoutMarginsGuide: NSLayoutGuide { _edgeGuide(&_marginsGuide, name: "layoutMargins") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/layoutsubtreeifneeded()
    @MainActor open func layoutSubtreeIfNeeded() {
        if _superview == nil { _solveConstraintsIfNeeded() }
        if _needsLayout {
            _needsLayout = false
            _viewController?.viewWillLayout()
            layout()
            _viewController?.viewDidLayout()
        }
        for s in _subviews { s.layoutSubtreeIfNeeded() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/leadinganchor
    @available(macOS 10.11, *)
    @MainActor open var leadingAnchor: NSLayoutXAxisAnchor { anchorX(.leading) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/leftanchor
    @available(macOS 10.11, *)
    @MainActor open var leftAnchor: NSLayoutXAxisAnchor { anchorX(.left) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/locationofprintrect(_:)
    @MainActor open func locationOfPrintRect(_ rect: NSRect) -> NSPoint { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lockfocus()
    @MainActor open func lockFocus() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lockfocusifcandraw()
    @MainActor open func lockFocusIfCanDraw() -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/lockfocusifcandraw(in:)
    @MainActor open func lockFocusIfCanDraw(in context: NSGraphicsContext) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/makebackinglayer()
    @MainActor open func makeBackingLayer() -> CALayer { CALayer() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/menu(for:)
    @MainActor open func menu(for event: NSEvent) -> NSMenu? { menu }
    /// A right click opens the view's contextual menu (`menu(for:)`), as in AppKit.
    @MainActor open override func rightMouseDown(with event: NSEvent) {
        if let m = menu(for: event) { NSMenu.popUpContextMenu(m, with: event, for: self) } else { super.rightMouseDown(with: event) }
    }
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
        get { _needsUpdateConstraints }
        set { _needsUpdateConstraints = newValue; if newValue { _setNeedsConstraintLayout() } }
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
    @MainActor open func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) { for t in newTypes where !_registeredDraggedTypes.contains(t) { _registeredDraggedTypes.append(t) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/registereddraggedtypes
    @MainActor open var registeredDraggedTypes: [NSPasteboard.PasteboardType] { _registeredDraggedTypes }
    /// Whether a drag carrying `types` may land here: a registered type matches exactly or
    /// as a UTType the dragged type conforms to (a registered "public.text" takes UTF-8 text).
    @MainActor internal func _acceptsDraggedTypes(_ types: [NSPasteboard.PasteboardType]) -> Bool {
        guard !_registeredDraggedTypes.isEmpty else { return false }
        for t in types {
            for r in _registeredDraggedTypes where r == t || _NSPasteboardTypeConformance.conforms(t.rawValue, to: r.rawValue) { return true }
        }
        return false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/draggingentered(_:)
    @MainActor open func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/draggingupdated(_:)
    @MainActor open func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { _lastDraggingEnteredOperation }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/draggingexited(_:)
    @MainActor open func draggingExited(_ sender: (any NSDraggingInfo)?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/draggingended(_:)
    @MainActor open func draggingEnded(_ sender: any NSDraggingInfo) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/preparefordragoperation(_:)
    @MainActor open func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/performdragoperation(_:)
    @MainActor open func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/concludedragoperation(_:)
    @MainActor open func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/updatedraggingitemsfordrag(_:)
    @MainActor open func updateDraggingItemsForDrag(_ sender: (any NSDraggingInfo)?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingdestination/wantsperiodicdraggingupdates()
    @MainActor open func wantsPeriodicDraggingUpdates() -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/releasegstate()
    @MainActor open func releaseGState() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removealltooltips()
    @MainActor open func removeAllToolTips() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removeconstraint(_:)
    @MainActor open func removeConstraint(_ constraint: NSLayoutConstraint) {
        guard let i = _constraints.firstIndex(where: { $0 === constraint }) else { return }
        _constraints.remove(at: i)
        constraint._setActiveFlag(false, holder: nil)
        _setNeedsConstraintLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removeconstraints(_:)
    @MainActor open func removeConstraints(_ constraints: [NSLayoutConstraint]) { for c in constraints { removeConstraint(c) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removecursorrect(_:cursor:)
    @MainActor open func removeCursorRect(_ rect: NSRect, cursor object: NSCursor) { _cursorRects.removeAll { $0.0 == rect && $0.1 === object } }
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
        // Constraints held by ancestors that mention this view go away with it.
        var a: NSView? = sup
        while let cur = a {
            for c in cur._constraints where c.firstItem === self || c.secondItem === self { c._setActiveFlag(false, holder: nil) }
            cur._constraints.removeAll { $0.firstItem === self || $0.secondItem === self }
            a = cur._superview
        }
        sup._setNeedsConstraintLayout(force: sup._engine != nil)
        viewWillMove(toSuperview: nil)
        if _window != nil { _accessibilityStructureChanged() }
        _superview = nil
        nextResponder = nil
        if let w = _window, w.firstResponder === self { _ = w.makeFirstResponder(nil) }
        _setWindow(nil)
        if let l = _layer { l.removeFromSuperlayer(); l.host = self }
        viewDidMoveToSuperview()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removegesturerecognizer(_:)
    @available(macOS 10.10, *)
    @MainActor open func removeGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        guard let i = _gestureRecognizers.firstIndex(where: { $0 === gestureRecognizer }) else { return }
        _gestureRecognizers.remove(at: i)
        gestureRecognizer._setView(nil)
        if gestureRecognizer.state == .began || gestureRecognizer.state == .changed { gestureRecognizer.state = .cancelled }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/removelayoutguide(_:)
    @available(macOS 10.11, *)
    @MainActor open func removeLayoutGuide(_ guide: NSLayoutGuide) {
        _layoutGuides.removeAll { $0 === guide }
        guide.owningView = nil
        _constraints.removeAll { $0.firstItem === guide || $0.secondItem === guide }
        _setNeedsConstraintLayout()
    }
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
    @MainActor class public var requiresConstraintBasedLayout: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/resetcursorrects()
    @MainActor open func resetCursorRects() { }
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
    @MainActor open var rightAnchor: NSLayoutXAxisAnchor { anchorX(.right) }
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
    @MainActor open var safeAreaLayoutGuide: NSLayoutGuide { _edgeGuide(&_safeAreaGuide, name: "safeArea") }
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
    @MainActor open func scrollToVisible(_ rect: NSRect) -> Bool {
        var v: NSView? = _superview
        while let cur = v, !(cur is NSClipView) { v = cur._superview }
        guard let clip = v as? NSClipView else { return false }
        let target = convert(rect, to: clip)
        var origin = clip.bounds.origin
        let visible = clip.bounds
        if target.minX < visible.minX { origin.x = target.minX } else if target.maxX > visible.maxX { origin.x += target.maxX - visible.maxX }
        if target.minY < visible.minY { origin.y = target.minY } else if target.maxY > visible.maxY { origin.y += target.maxY - visible.maxY }
        guard origin != clip.bounds.origin else { return false }
        clip.scroll(to: origin)
        (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setboundsorigin(_:)
    @MainActor open func setBoundsOrigin(_ newOrigin: NSPoint) {
        guard newOrigin != _boundsOrigin else { return }
        _boundsOrigin = newOrigin
        _syncLayerGeometry()
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
        _syncLayerGeometry()
        setNeedsDisplay(bounds)
        if _postsBoundsChangedNotifications {
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: self)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setcontentcompressionresistancepriority(_:for:)
    @MainActor open func setContentCompressionResistancePriority(_ priority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) { _compressionPriority[orientation] = priority; _setNeedsConstraintLayout() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setcontenthuggingpriority(_:for:)
    @MainActor open func setContentHuggingPriority(_ priority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) { _huggingPriority[orientation] = priority; _setNeedsConstraintLayout() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setframeorigin(_:)
    @MainActor open func setFrameOrigin(_ newOrigin: NSPoint) {
        let animate = _takeAnimator()
        guard newOrigin.x.isFinite, newOrigin.y.isFinite else { return }   // never adopt NaN/inf geometry
        guard newOrigin != _frame.origin else { return }
        let old = _frame
        _frame.origin = newOrigin
        _syncLayerGeometry()
        if animate { _animateLayer("position", from: old.origin, to: newOrigin) }
        _superview?.setNeedsDisplay(old.union(_frame))
        if _postsFrameChangedNotifications {
            NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: self)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/setframesize(_:)
    @MainActor open func setFrameSize(_ newSize: NSSize) {
        if NSView._traceInvalidation { NSView._trace("setFrameSize \(type(of: self)) \(newSize)") }
        let animate = _takeAnimator()
        guard newSize.width.isFinite, newSize.height.isFinite else { return }
        let newSize = NSSize(width: max(0, newSize.width), height: max(0, newSize.height))
        guard newSize != _frame.size else { return }
        let old = _frame
        let oldBounds = bounds
        _frame.size = newSize
        _cursorRectsValid = false
        _syncLayerGeometry()
        if animate { _animateLayer("bounds", from: oldBounds, to: bounds) }
        if _autoresizesSubviews { resizeSubviews(withOldSize: old.size) }
        if !_applyingLayout { _needsLayout = true; _setNeedsConstraintLayout(force: false) }
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
    @MainActor open var topAnchor: NSLayoutYAxisAnchor { anchorY(.top) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/trackingareas
    @MainActor open var trackingAreas: [NSTrackingArea] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/trailinganchor
    @available(macOS 10.11, *)
    @MainActor open var trailingAnchor: NSLayoutXAxisAnchor { anchorX(.trailing) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/translateorigin(to:)
    @MainActor open func translateOrigin(to translation: NSPoint) { setBoundsOrigin(NSPoint(x: _boundsOrigin.x - translation.x, y: _boundsOrigin.y - translation.y)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/translaterectsneedingdisplay(in:by:)
    @MainActor open func translateRectsNeedingDisplay(in clipRect: NSRect, by delta: NSSize) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/translatesautoresizingmaskintoconstraints
    @MainActor open var translatesAutoresizingMaskIntoConstraints: Bool {
        get { _translatesAutoresizingMaskIntoConstraints }
        set { _translatesAutoresizingMaskIntoConstraints = newValue; _setNeedsConstraintLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/unlockfocus()
    @MainActor open func unlockFocus() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/unregisterdraggedtypes()
    @MainActor open func unregisterDraggedTypes() { _registeredDraggedTypes = [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updateconstraints()
    @MainActor open func updateConstraints() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updateconstraintsforsubtreeifneeded()
    @MainActor open func updateConstraintsForSubtreeIfNeeded() {
        for s in _subviews { s.updateConstraintsForSubtreeIfNeeded() }
        if _needsUpdateConstraints {
            _needsUpdateConstraints = false
            updateConstraints()
            _viewController?.updateViewConstraints()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updatelayer()
    @MainActor open func updateLayer() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/updatetrackingareas()
    @MainActor open func updateTrackingAreas() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/userinterfacelayoutdirection
    @MainActor open var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { _userInterfaceLayoutDirection ?? superview?.userInterfaceLayoutDirection ?? NSApplication._resolvedLayoutDirection }
        set {
            guard newValue != _userInterfaceLayoutDirection else { return }
            _userInterfaceLayoutDirection = newValue
            // Leading and trailing edges swap sides: constraints and layout run again.
            _setNeedsConstraintLayout()
            needsLayout = true
            needsDisplay = true
        }
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
        set {
            if newValue && _layer == nil && !_layerIsHosted {
                _becomeLayerBacked()
                setNeedsDisplay(bounds)
            } else {
                _wantsLayer = newValue   // AppKit keeps the layer once created; turning this off is a no-op.
            }
        }
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
    @MainActor open var widthAnchor: NSLayoutDimension { anchorDimension(.width) }
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
    // MARK: Accessibility (ADR-0013)
    //
    // Every answer is derived from the view's state unless one of the
    // `setAccessibility...` methods stored an override. Subclasses override the getters
    // for their roles and values; `NSAccessibility.swift` turns the answers into the
    // snapshot the platform seam hands to assistive technology.

    /// Values stored through the `setAccessibility...` methods.
    internal var _a11y: _NSAccessibilityOverrides {
        get { _accessibilityOverrides }
        set { _accessibilityOverrides = newValue }
    }
    /// Stable identity of the view in the platform accessibility tree.
    public var _accessibilityElementID: Int {
        if _accessibilityID == 0 { _accessibilityID = _NSAccessibilityIDs.next() }
        return _accessibilityID
    }
    /// Whether the value can be set by assistive technology (editable text, sliders, ...).
    @MainActor internal func _accessibilityValueIsSettable() -> Bool { false }
    /// Assistive technology sets a new value; the control applies it and sends its action.
    @MainActor internal func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool { false }
    @MainActor internal func _accessibilityIsMultiline() -> Bool { false }
    @MainActor internal func _accessibilityAllowsMultipleSelection() -> Bool { false }
    @MainActor internal func _accessibilityIsFocusable() -> Bool { acceptsFirstResponder && isAccessibilityEnabled() && !isHiddenOrHasHiddenAncestor }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/isaccessibilityelement()
    ///
    /// A plain view is ignored (its subviews stand in for it); controls and views with a
    /// role are elements.
    open func isAccessibilityElement() -> Bool { _a11y.isElement ?? (_a11y.role != nil) }
    open func setAccessibilityElement(_ accessibilityElement: Bool) { _a11y.isElement = accessibilityElement; _accessibilityStructureChanged() }
    open func accessibilityRole() -> NSAccessibility.Role? { _a11y.role }
    open func setAccessibilityRole(_ accessibilityRole: NSAccessibility.Role?) { _a11y.role = accessibilityRole; _accessibilityStructureChanged() }
    open func accessibilitySubrole() -> NSAccessibility.Subrole? { _a11y.subrole }
    open func setAccessibilitySubrole(_ accessibilitySubrole: NSAccessibility.Subrole?) { _a11y.subrole = accessibilitySubrole }
    open func accessibilityRoleDescription() -> String? { _a11y.roleDescription }
    open func setAccessibilityRoleDescription(_ accessibilityRoleDescription: String?) { _a11y.roleDescription = accessibilityRoleDescription }
    open func accessibilityLabel() -> String? { _a11y.label }
    open func setAccessibilityLabel(_ accessibilityLabel: String?) { _a11y.label = accessibilityLabel; _accessibilityNameChanged() }
    open func accessibilityTitle() -> String? { _a11y.title }
    open func setAccessibilityTitle(_ accessibilityTitle: String?) { _a11y.title = accessibilityTitle; _accessibilityNameChanged() }
    open func accessibilityValue() -> Any? { _a11y.value }
    open func setAccessibilityValue(_ accessibilityValue: Any?) { _a11y.value = accessibilityValue; _a11y.hasValue = true; _accessibilityValueChanged() }
    open func accessibilityHelp() -> String? { _a11y.help ?? toolTip }
    open func setAccessibilityHelp(_ accessibilityHelp: String?) { _a11y.help = accessibilityHelp }
    open func accessibilityPlaceholderValue() -> String? { _a11y.placeholder }
    open func setAccessibilityPlaceholderValue(_ accessibilityPlaceholderValue: String?) { _a11y.placeholder = accessibilityPlaceholderValue }
    open func isAccessibilityEnabled() -> Bool { _a11y.isEnabled ?? true }
    open func setAccessibilityEnabled(_ accessibilityEnabled: Bool) { _a11y.isEnabled = accessibilityEnabled }
    /// `accessibilityHidden` views and their subtrees leave the tree, as hidden views do.
    open func isAccessibilityHidden() -> Bool { _a11y.isHidden }
    open func setAccessibilityHidden(_ accessibilityHidden: Bool) { _a11y.isHidden = accessibilityHidden; _accessibilityStructureChanged() }
    open func isAccessibilitySelected() -> Bool { _a11y.isSelected ?? false }
    open func setAccessibilitySelected(_ accessibilitySelected: Bool) { _a11y.isSelected = accessibilitySelected }
    /// The frame in screen coordinates (window content coordinates before the view is
    /// in a window).
    open func accessibilityFrame() -> NSRect {
        if let f = _a11y.frame { return f }
        let inWindow = convert(bounds, to: nil)
        return window?.convertToScreen(inWindow) ?? inWindow
    }
    open func setAccessibilityFrame(_ accessibilityFrame: NSRect) { _a11y.frame = accessibilityFrame }
    /// The nearest ancestor that is an element, else the window.
    open func accessibilityParent() -> Any? {
        if let p = _a11y.parent { return p }
        var v = superview
        while let cur = v { if cur.isAccessibilityElement() { return cur }; v = cur.superview }
        return window
    }
    open func setAccessibilityParent(_ accessibilityParent: Any?) { _a11y.parent = accessibilityParent }
    /// The subviews that are elements, with ignored subviews replaced by their own
    /// children, in subview order. Hidden subviews are left out.
    open func accessibilityChildren() -> [Any]? {
        if let c = _a11y.children { return c }
        var out: [Any] = []
        for s in subviews where !s.isHidden && !s.isAccessibilityHidden() {
            if s.isAccessibilityElement() { out.append(s) } else if let c = s.accessibilityChildren() { out.append(contentsOf: c) }
        }
        return out
    }
    open func setAccessibilityChildren(_ accessibilityChildren: [Any]?) { _a11y.children = accessibilityChildren; _accessibilityStructureChanged() }
    open func accessibilityVisibleChildren() -> [Any]? { accessibilityChildren() }
    open func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? { accessibilityChildren()?.compactMap { $0 as? any NSAccessibilityElementProtocol } }
    open func accessibilityWindow() -> Any? { window }
    open func accessibilityTopLevelUIElement() -> Any? { window }
    /// Keyboard focus: the view is the window's first responder (or its field editor is).
    open func isAccessibilityFocused() -> Bool {
        guard let w = window, let r = w.firstResponder as? NSView else { return false }
        return r === self || r._accessibilityFocusTarget === self
    }
    /// Moves keyboard focus to the view (`true`) or away from it.
    open func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        guard let w = window else { return }
        if accessibilityFocused { _ = w.makeFirstResponder(self) } else if isAccessibilityFocused() { _ = w.makeFirstResponder(nil) }
    }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { _a11y.identifier ?? identifier?.rawValue ?? "" }
    open func setAccessibilityIdentifier(_ accessibilityIdentifier: String?) { _a11y.identifier = accessibilityIdentifier }
    open func accessibilityMinValue() -> Any? { _a11y.minValue }
    open func setAccessibilityMinValue(_ accessibilityMinValue: Any?) { _a11y.minValue = accessibilityMinValue }
    open func accessibilityMaxValue() -> Any? { _a11y.maxValue }
    open func setAccessibilityMaxValue(_ accessibilityMaxValue: Any?) { _a11y.maxValue = accessibilityMaxValue }
    /// The index among the siblings of the same kind (rows in a table); -1 when the view
    /// has none.
    open func accessibilityIndex() -> Int { _a11y.index ?? -1 }
    open func setAccessibilityIndex(_ accessibilityIndex: Int) { _a11y.index = accessibilityIndex }
    open func accessibilitySelectedTextRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    open func accessibilityActivationPoint() -> NSPoint { let f = accessibilityFrame(); return NSPoint(x: f.midX, y: f.midY) }
    open func accessibilityPerformPress() -> Bool { false }
    open func accessibilityPerformIncrement() -> Bool { false }
    open func accessibilityPerformDecrement() -> Bool { false }
    open func accessibilityPerformShowMenu() -> Bool { false }
    open func accessibilityPerformConfirm() -> Bool { false }
    open func accessibilityPerformCancel() -> Bool { false }
    open func accessibilityPerformPick() -> Bool { false }
    open func accessibilityPerformRaise() -> Bool { false }
}


// MARK: - Core Animation delegate and host

extension NSView: CALayerDelegate, CALayerHost {
    /// The backing layer asks the view to draw; `ctx` is in the view's bounds space.
    public func draw(_ layer: CALayer, in ctx: CGContext) {
        guard layer === _layer, !_layerIsHosted else { return }
        let gc = NSGraphicsContext(cgContext: ctx, flipped: isFlipped)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = gc
        let previousAppearance = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        viewWillDraw()
        let b = bounds
        if wantsDefaultClipping { ctx.clip(to: b) }
        _dirtyRect = b
        if wantsUpdateLayer { updateLayer() } else { draw(b) }
        _dirtyRect = nil
        NSAppearance.current = previousAppearance
        NSGraphicsContext.current = previous
        _needsDisplay = false
    }

    public func display(_ layer: CALayer) {
        layer._displayDefault()
    }

    public func layoutSublayers(of layer: CALayer) {
        if layer === _layer { layoutSubtreeIfNeeded() }
    }

    /// AppKit suppresses implicit animations on backing layers unless the current
    /// NSAnimationContext allows them.
    public func action(for layer: CALayer, forKey event: String) -> (any CAAction)? {
        NSAnimationContext.current.allowsImplicitAnimation ? nil : NSNull()
    }

    public func layerHostIsOnScreen(_ root: CALayer) -> Bool { _window?.isVisible == true && !isHiddenOrHasHiddenAncestor }
    public var _layerHostDescription: String {
        "\(type(of: self)) in \(_window.map { "'\($0.title)' visible \($0.isVisible)" } ?? "no window")\(isHiddenOrHasHiddenAncestor ? " hidden" : "")"
    }

    public func layerNeedsDisplay(_ root: CALayer, in rect: CGRect?) {
        guard root === _layer else { return }
        if let w = _window, w._hostsLayersNatively {
            w._setLayerSceneNeedsCommit()
            return
        }
        if let r = rect, let sup = _superview {
            sup.setNeedsDisplay(r.intersection(_frame))
        } else {
            setNeedsDisplay(bounds)
        }
    }
}
