// NSDrawer (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A drawer is a borderless child window of its parent, placed against one edge of the
// parent (ADR-0034). Win32 and X11 keep an owned window above its owner, so the drawer
// cannot slide out from behind the parent as on macOS; instead its window grows outward
// from the parent's edge while the drawer's content is pinned to the outer edge, so the
// outer edge appears first, as if it came out from under the parent. The slide is an
// NSAnimation on the frame clock (off on the headless host backend, like sheet slides).
//
// Along the edge the drawer spans the parent's content area (left and right edges) or
// the whole frame width (top and bottom), less the leading and trailing offsets; across
// the edge it is `contentSize` thick plus its border. The parent's moves and resizes
// carry the drawer along. Dragging the outer border resizes the content, through the
// delegate's `drawerWillResizeContents(_:to:)` and the size limits.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer
@MainActor open class NSDrawer: NSResponder, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    private var _contentSize: NSSize
    private var _minContentSize = NSSize.zero
    private var _maxContentSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    private var _preferredEdge: NSRectEdge
    private var _edge: NSRectEdge
    private var _leadingOffset: CGFloat = 0
    private var _trailingOffset: CGFloat = 0
    private weak var _parentWindow: NSWindow?
    private weak var _delegate: (any NSDrawerDelegate)?
    private var _state: NSDrawer.State = .closedState
    private var _contentView: NSView?

    /// How much of the drawer shows across the edge, 0 (closed) to 1 (open).
    private var _fraction: CGFloat = 0
    private var _window: _NSDrawerWindow?
    private var _frameView: _NSDrawerFrameView?
    private var _slide: _NSDrawerSlide?
    private var _observers: [NSObjectProtocol] = []

    /// The border around the content.
    internal static let _border: CGFloat = 6
    /// How long a full slide takes; 0 skips the animation. Off on the headless host
    /// backend, whose run loop nobody spins for frames; the slide test turns it on. Not
    /// part of Apple's API.
    public static var _animationDuration: TimeInterval = Platform.backend is HostBackend ? 0 : 0.2

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/init(contentsize:preferrededge:)
    @MainActor public init(contentSize: NSSize, preferredEdge edge: NSRectEdge) {
        _contentSize = contentSize
        _preferredEdge = edge
        _edge = edge
        super.init()
    }
    // Required by the superclass (NSCoding).
    @MainActor public required init?(coder: NSCoder) { unimplemented() }

    // MARK: Opening and closing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/open()
    @MainActor open func open() { _open(on: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/open(_:)
    @MainActor open func open(_ sender: Any?) { _open(on: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/open(on:)
    @MainActor open func open(on edge: NSRectEdge) { _open(on: edge) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/close()
    @MainActor open func close() { _close(animated: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/close(_:)
    @MainActor open func close(_ sender: Any?) { _close(animated: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/toggle(_:)
    @MainActor open func toggle(_ sender: Any?) {
        switch _state {
        case .closedState, .closingState: open(sender)
        case .openState, .openingState: close(sender)
        }
    }

    private func _post(_ name: NSNotification.Name) {
        let n = Notification(name: name, object: self)
        NotificationCenter.default.post(n)
        guard let d = _delegate else { return }
        switch name {
        case NSDrawer.willOpenNotification: d.drawerWillOpen(n)
        case NSDrawer.didOpenNotification: d.drawerDidOpen(n)
        case NSDrawer.willCloseNotification: d.drawerWillClose(n)
        case NSDrawer.didCloseNotification: d.drawerDidClose(n)
        default: break
        }
    }

    private func _open(on requested: NSRectEdge?) {
        guard let parent = _parentWindow else { return }
        switch _state {
        case .openState, .openingState: return
        case .closingState:
            // Reverses the slide from where it is.
            _state = .openingState
            _slideTo(1)
            return
        case .closedState: break
        }
        if let d = _delegate, !d.drawerShouldOpen(self) { return }
        _edge = requested ?? _chooseEdge(parent)
        _post(NSDrawer.willOpenNotification)
        _state = .openingState
        _fraction = 0
        let w = _makeWindowIfNeeded()
        _observeParent(parent)
        _layout()
        if w.parent !== parent { parent.addChildWindow(w, ordered: .above) } else { w.orderFront(nil) }
        _slideTo(1)
    }

    private func _close(animated: Bool) {
        switch _state {
        case .closedState, .closingState: return
        case .openingState, .openState: break
        }
        if let d = _delegate, !d.drawerShouldClose(self) { return }
        _post(NSDrawer.willCloseNotification)
        _state = .closingState
        if animated { _slideTo(0) } else { _finishSlide(at: 0) }
    }

    /// The preferred edge, or the opposite one when the drawer would leave the parent's
    /// screen on the preferred side and fits on the other.
    private func _chooseEdge(_ parent: NSWindow) -> NSRectEdge {
        guard let screen = (parent.screen ?? NSScreen.main)?.visibleFrame else { return _preferredEdge }
        func fits(_ e: NSRectEdge) -> Bool {
            let f = _targetFrame(edge: e, parent: parent, fraction: 1)
            return screen.contains(f)
        }
        if fits(_preferredEdge) { return _preferredEdge }
        let opposite: NSRectEdge
        switch _preferredEdge {
        case .minX: opposite = .maxX
        case .maxX: opposite = .minX
        case .minY: opposite = .maxY
        case .maxY: opposite = .minY
        @unknown default: return _preferredEdge
        }
        return fits(opposite) ? opposite : _preferredEdge
    }

    // MARK: Slide

    private func _slideTo(_ target: CGFloat) {
        _slide?.stop()
        _slide = nil
        let from = _fraction
        let distance = abs(target - from)
        let duration = NSDrawer._animationDuration * TimeInterval(distance)
        guard duration > 0 else { _finishSlide(at: target); return }
        let a = _NSDrawerSlide(duration: duration, animationCurve: .easeOut)
        a.animationBlockingMode = .nonblocking
        a.step = { [weak self] value in
            guard let self else { return }
            self._fraction = from + (target - from) * CGFloat(value)
            self._layout()
        }
        a.end = { [weak self] in self?._finishSlide(at: target) }
        _slide = a
        a.start()
    }

    private func _finishSlide(at target: CGFloat) {
        _slide?.stop()
        _slide = nil
        _fraction = target
        if target >= 1 {
            _layout()
            _state = .openState
            _post(NSDrawer.didOpenNotification)
        } else {
            if let w = _window {
                w.orderOut(nil)
                _parentWindow?.removeChildWindow(w)
            }
            _stopObservingParent()
            _state = .closedState
            _post(NSDrawer.didCloseNotification)
        }
    }

    // MARK: Geometry

    private var _thickness: CGFloat {
        let b = NSDrawer._border
        switch _edge {
        case .minX, .maxX: return _contentSize.width + 2 * b
        default: return _contentSize.height + 2 * b
        }
    }

    /// The drawer window's frame on `edge` with `fraction` of its thickness showing.
    private func _targetFrame(edge: NSRectEdge, parent: NSWindow, fraction: CGFloat) -> NSRect {
        let b = NSDrawer._border
        let pf = parent.frame
        let content = parent.contentRect(forFrameRect: pf)
        let full: CGFloat
        switch edge {
        case .minX, .maxX: full = _contentSize.width + 2 * b
        default: full = _contentSize.height + 2 * b
        }
        let shown = max(1, (full * min(max(fraction, 0), 1)).rounded())
        switch edge {
        case .minX, .maxX:
            // Leading is from the top.
            let h = max(1, content.height - _leadingOffset - _trailingOffset)
            let y = content.minY + _trailingOffset
            return NSRect(x: edge == .maxX ? pf.maxX : pf.minX - shown, y: y, width: shown, height: h)
        default:
            let w = max(1, pf.width - _leadingOffset - _trailingOffset)
            let x = pf.minX + _leadingOffset
            return NSRect(x: x, y: edge == .maxY ? pf.maxY : pf.minY - shown, width: w, height: shown)
        }
    }

    /// Places the window for the current fraction and the drawer inside it, the content
    /// pinned to the outer edge.
    private func _layout() {
        guard let parent = _parentWindow, let w = _window, let frameView = _frameView else { return }
        let f = _targetFrame(edge: _edge, parent: parent, fraction: _fraction)
        if w.frame != f { w.setFrame(f, display: true) }
        let b = NSDrawer._border
        let full = _thickness
        let size: NSSize
        let origin: NSPoint
        switch _edge {
        case .minX: size = NSSize(width: full, height: f.height); origin = .zero
        case .maxX: size = NSSize(width: full, height: f.height); origin = NSPoint(x: f.width - full, y: 0)
        case .minY: size = NSSize(width: f.width, height: full); origin = .zero
        default: size = NSSize(width: f.width, height: full); origin = NSPoint(x: 0, y: f.height - full)
        }
        frameView.edge = _edge
        if frameView.frame != NSRect(origin: origin, size: size) { frameView.frame = NSRect(origin: origin, size: size) }
        // The content's size along the edge follows the parent.
        switch _edge {
        case .minX, .maxX: _contentSize.height = max(0, f.height - 2 * b)
        default: _contentSize.width = max(0, f.width - 2 * b)
        }
        if let cv = _contentView {
            let r = NSRect(x: b, y: b, width: max(0, size.width - 2 * b), height: max(0, size.height - 2 * b))
            if cv.frame != r { cv.frame = r }
        }
    }

    private func _makeWindowIfNeeded() -> _NSDrawerWindow {
        if let w = _window { return w }
        let w = _NSDrawerWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        // No shadow of its own: the drawer reads as part of its parent, and on Win32 a
        // borderless window's shadow is a WS_THICKFRAME frame (ADR-0016), which Windows
        // never sizes below its border width (about 14 px), so the slide could not start
        // at the parent's edge.
        w.hasShadow = false
        w.drawer = self
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        w.contentView = root
        let frameView = _NSDrawerFrameView(frame: .zero)
        frameView.drawer = self
        root.addSubview(frameView)
        if let cv = _contentView { frameView.addSubview(cv) }
        _window = w
        _frameView = frameView
        return w
    }

    private func _observeParent(_ parent: NSWindow) {
        _stopObservingParent()
        let nc = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            _observers.append(nc.addObserver(forName: name, object: parent, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?._layout() }
            })
        }
        _observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?._close(animated: false) }
        })
    }

    private func _stopObservingParent() {
        for o in _observers { NotificationCenter.default.removeObserver(o) }
        _observers.removeAll()
    }

    /// The outer border was dragged by `delta` points outward.
    internal func _resizeByDragging(to proposed: NSSize) {
        var size = proposed
        if let d = _delegate { size = d.drawerWillResizeContents(self, to: size) }
        contentSize = size
    }

    /// The drawer's window (internal for tests and the frame view).
    internal var _drawerWindow: NSWindow? { _window }
    internal var _slideFraction: CGFloat { _fraction }

    // MARK: Properties

    /// The content's size; while the drawer is attached, the dimension along the edge
    /// follows the parent window.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/contentsize
    @MainActor open var contentSize: NSSize {
        get { _contentSize }
        set {
            _contentSize = NSSize(width: min(max(newValue.width, _minContentSize.width), _maxContentSize.width),
                                  height: min(max(newValue.height, _minContentSize.height), _maxContentSize.height))
            _layout()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/contentview
    @MainActor open var contentView: NSView? {
        get { _contentView }
        set {
            guard newValue !== _contentView else { return }
            _contentView?.removeFromSuperview()
            _contentView = newValue
            if let v = newValue, let fv = _frameView { fv.addSubview(v) }
            _layout()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/delegate
    @MainActor open var delegate: (any NSDrawerDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/didclosenotification
    static public var didCloseNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSDrawerDidCloseNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/didopennotification
    static public var didOpenNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSDrawerDidOpenNotification") }
    /// The edge the drawer is on (or last opened on; the preferred edge before it opens).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/edge
    @MainActor open var edge: NSRectEdge { _edge }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/leadingoffset
    @MainActor open var leadingOffset: CGFloat {
        get { _leadingOffset }
        set { _leadingOffset = max(0, newValue); _layout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/maxcontentsize
    @MainActor open var maxContentSize: NSSize {
        get { _maxContentSize }
        set { _maxContentSize = newValue; contentSize = _contentSize }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/mincontentsize
    @MainActor open var minContentSize: NSSize {
        get { _minContentSize }
        set { _minContentSize = newValue; contentSize = _contentSize }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/parentwindow
    @MainActor open var parentWindow: NSWindow? {
        get { _parentWindow }
        set {
            guard newValue !== _parentWindow else { return }
            let wasOpen = _state == .openState || _state == .openingState
            if _state != .closedState {
                if let w = _window { w.orderOut(nil); _parentWindow?.removeChildWindow(w) }
                _slide?.stop(); _slide = nil
                _stopObservingParent()
                _state = .closedState
                _fraction = 0
            }
            _parentWindow = newValue
            if wasOpen, newValue != nil { _open(on: _edge) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/preferrededge
    @MainActor open var preferredEdge: NSRectEdge {
        get { _preferredEdge }
        set {
            _preferredEdge = newValue
            if _state == .closedState { _edge = newValue }
        }
    }
    /// The raw value of an `NSDrawer.State`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/state
    @MainActor open var state: Int { _state.rawValue }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/trailingoffset
    @MainActor open var trailingOffset: CGFloat {
        get { _trailingOffset }
        set { _trailingOffset = max(0, newValue); _layout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/willclosenotification
    static public var willCloseNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSDrawerWillCloseNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdrawer/willopennotification
    static public var willOpenNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSDrawerWillOpenNotification") }

    // MARK: Accessibility

    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityFrame() -> NSRect {
        MainActor.assumeIsolated { _state == .closedState ? .zero : (_window?.frame ?? .zero) }
    }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityParent() -> Any? { MainActor.assumeIsolated { _parentWindow } }
    // Requirement of NSAccessibilityElementProtocol
    open func isAccessibilityFocused() -> Bool { false }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { "" }
}

// MARK: - Drawer window and frame

/// The drawer's borderless window: it takes key status for the content's controls.
@MainActor final class _NSDrawerWindow: NSWindow {
    weak var drawer: NSDrawer?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The drawer's panel: background, border, and the outer border as a resize handle.
@MainActor final class _NSDrawerFrameView: NSView {
    weak var drawer: NSDrawer?
    var edge: NSRectEdge = .maxX
    /// The press point on screen and the content size when a border drag began.
    private var _dragStart: (point: NSPoint, size: NSSize)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(dirtyRect)
        NSColor.separatorColor.setStroke()
        NSBezierPath.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
    }

    /// The outer border strip.
    private var _handle: NSRect {
        let b = NSDrawer._border
        switch edge {
        case .minX: return NSRect(x: 0, y: 0, width: b, height: bounds.height)
        case .maxX: return NSRect(x: bounds.maxX - b, y: 0, width: b, height: bounds.height)
        case .minY: return NSRect(x: 0, y: 0, width: bounds.width, height: b)
        default: return NSRect(x: 0, y: bounds.maxY - b, width: bounds.width, height: b)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard _handle.contains(p), let d = drawer else { super.mouseDown(with: event); return }
        _dragStart = (window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow, d.contentSize)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = _dragStart, let d = drawer, let w = window else { super.mouseDragged(with: event); return }
        // Window coordinates move with the window as it resizes: compare on screen.
        let now = w.convertPoint(toScreen: event.locationInWindow)
        var size = start.size
        switch edge {
        case .minX: size.width = start.size.width + (start.point.x - now.x)
        case .maxX: size.width = start.size.width + (now.x - start.point.x)
        case .minY: size.height = start.size.height + (start.point.y - now.y)
        default: size.height = start.size.height + (now.y - start.point.y)
        }
        d._resizeByDragging(to: size)
    }

    override func mouseUp(with event: NSEvent) {
        if _dragStart == nil { super.mouseUp(with: event) }
        _dragStart = nil
    }
}

/// The slide: each progress change hands the curve's value to the drawer, the end
/// finishes the open or close.
private final class _NSDrawerSlide: NSAnimation, NSAnimationDelegate, @unchecked Sendable {
    var step: (@MainActor (Float) -> Void)?
    var end: (@MainActor () -> Void)?

    override init(duration: TimeInterval, animationCurve: NSAnimation.Curve) {
        super.init(duration: duration, animationCurve: animationCurve)
        delegate = self
    }
    required init?(coder: NSCoder) { unimplemented() }

    override var currentProgress: NSAnimation.Progress {
        get { super.currentProgress }
        set {
            super.currentProgress = newValue
            let v = _curveValue(forProgress: super.currentProgress)
            MainActor.assumeIsolated { step?(v) }
        }
    }
    func animationDidEnd(_ animation: NSAnimation) {
        MainActor.assumeIsolated { end?() }
    }
}
