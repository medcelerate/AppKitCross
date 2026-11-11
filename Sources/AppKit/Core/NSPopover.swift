// NSPopover (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A popover is a borderless window attached to the positioning view's window (the
// attached-window seam of ADR-0019, `PlatformWindow.attachSheet(to:)`) that draws its
// own rounded body and the arrow pointing at the positioning rect (`_NSPopoverFrameView`),
// placed by `_NSPopoverPlacement` on the preferred edge or the opposite one when the
// screen has no room, follows the parent when it moves and closes per its behaviour
// through `NSApplication.sendEvent` (ADR-0025).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover
@MainActor open class NSPopover: NSResponder, NSAppearanceCustomization, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    // MARK: Storage
    private var _animates = true
    private var _appearance: NSAppearance? = nil
    private var _behavior: NSPopover.Behavior = .applicationDefined
    private var _contentSize = NSSize.zero
    private var _contentViewController: NSViewController? = nil
    private weak var _delegate: (any NSPopoverDelegate)? = nil
    private var _positioningRect = NSRect.zero
    private var _hasFullSizeContent = false
    private weak var _positioningView: NSView? = nil
    private var _preferredEdge: NSRectEdge = .minY
    /// The popover's window while shown attached (nil while detached or closed).
    internal private(set) var _window: _NSPopoverWindow? = nil
    /// The titled window the content moved into when the user detached the popover
    /// without the delegate providing one (`isDetached`).
    internal private(set) var _detachedWindow: NSWindow? = nil
    private var _isClosing = false
    private var _observers: [Any] = []
    private var _pop: _NSPopoverPop? = nil
    private var _showNotified = false
    /// Where the window is while shown attached.
    internal private(set) var _placement: _NSPopoverPlacement? = nil

    /// How long the pop-out animation takes when `animates`; 0 skips it (tests). Not part
    /// of Apple's API.
    public static var _animationDuration: TimeInterval = 0.16

    /// The popovers shown now, in the order they were shown. A shown popover stays alive
    /// until it closes (NSApplication routes events to it).
    private(set) static var _shown: [NSPopover] = []

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/init()
    @MainActor public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/init(coder:)
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    open override var description: String { MainActor.assumeIsolated { "<NSPopover \(_behavior) \(isShown ? "shown" : "closed")\(isDetached ? " detached" : "")>" } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/animates
    @MainActor open var animates: Bool {
        get { _animates }
        set { _animates = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/appearance
    @available(macOS 10.10, *)
    @MainActor open var appearance: NSAppearance? {
        get { _appearance }
        set {
            _appearance = newValue
            _window?.appearance = effectiveAppearance
            _detachedWindow?.appearance = effectiveAppearance
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/behavior
    @MainActor open var behavior: NSPopover.Behavior {
        get { _behavior }
        set { _behavior = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/close()
    @MainActor open func close() { _close(reason: .standard) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/closereasonuserinfokey
    static public var closeReasonUserInfoKey: String { "NSPopoverCloseReasonKey" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/contentsize
    @MainActor open var contentSize: NSSize {
        get { _contentSize }
        set {
            _contentSize = newValue
            if _window != nil { _relayout() }
            else if let d = _detachedWindow, newValue.width > 0, newValue.height > 0 { d.setContentSize(newValue) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/contentviewcontroller
    @MainActor open var contentViewController: NSViewController? {
        get { _contentViewController }
        set {
            guard newValue !== _contentViewController else { return }
            let old = _contentViewController
            _contentViewController = newValue
            if let w = _window {
                old?.view.removeFromSuperview()
                if let vc = newValue { w.frameView.setContent(vc.view) }
                _relayout()
            } else if let d = _detachedWindow {
                d.contentViewController = newValue
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/delegate
    @MainActor open var delegate: (any NSPopoverDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/didclosenotification
    static public var didCloseNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSPopoverDidCloseNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/didshownotification
    static public var didShowNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSPopoverDidShowNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/effectiveappearance
    /// The popover's own appearance, else the positioning view's (the application's
    /// before the popover is shown).
    @available(macOS 10.10, *)
    @MainActor open var effectiveAppearance: NSAppearance {
        _appearance ?? _positioningView?.effectiveAppearance ?? NSApplication.shared.effectiveAppearance
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/hasfullsizecontent
    @available(macOS 14.0, *)
    @MainActor open var hasFullSizeContent: Bool {
        get { _hasFullSizeContent }
        set { _hasFullSizeContent = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/isdetached
    @available(macOS 10.10, *)
    @MainActor open var isDetached: Bool { _detachedWindow != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/isshown
    @MainActor open var isShown: Bool { _window != nil || _detachedWindow != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/performclose(_:)
    @MainActor open func performClose(_ sender: Any?) {
        guard isShown else { return }
        if let d = _delegate, !d.popoverShouldClose(self) { return }
        _close(reason: .standard)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/positioningrect
    @MainActor open var positioningRect: NSRect {
        get { _positioningRect }
        set { _positioningRect = newValue; if _window != nil { _relayout() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/show(relativeto:)
    /// The item's view anchors the popover below the toolbar; an item without a view (an
    /// image item) anchors it at the item's drawn frame in the toolbar band.
    @available(macOS 14.0, *)
    @MainActor open func show(relativeTo toolbarItem: NSToolbarItem) {
        if let v = toolbarItem.view, v.window != nil {
            show(relativeTo: v.bounds, of: v, preferredEdge: v.isFlipped ? .maxY : .minY)
            return
        }
        guard let toolbar = toolbarItem.toolbar, let w = toolbar._window, let band = w._toolbarView, let cv = w.contentView else { return }
        let frame = band._frame(ofItem: toolbarItem) ?? band.bounds
        let inContent = cv.convert(frame, from: band)
        show(relativeTo: inContent, of: cv, preferredEdge: cv.isFlipped ? .maxY : .minY)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/show(relativeto:of:preferrededge:)
    @MainActor open func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        guard !isShown else { return }
        guard let parent = positioningView.window else {
            preconditionFailure("NSPopover: the positioning view must be in a window")
        }
        guard let vc = _contentViewController else {
            preconditionFailure("NSPopover: contentViewController must be set before the popover is shown")
        }
        _positioningView = positioningView
        _positioningRect = positioningRect
        _preferredEdge = preferredEdge
        _showNotified = false
        let willShow = Notification(name: NSPopover.willShowNotification, object: self)
        NotificationCenter.default.post(willShow)
        _delegate?.popoverWillShow(willShow)
        let view = vc.view
        let size = _effectiveContentSize(for: view)
        let w = _NSPopoverWindow(popover: self, contentSize: size)
        w.appearance = effectiveAppearance
        _window = w
        w.frameView.setContent(view)
        // Attached to the parent (owner / transient / subsurface), placed, then ordered in.
        w._platformWindow?.attachSheet(to: parent._platformWindow)
        w.frameView.opaqueBacking = (w._platformWindow?.supportsTransparency ?? true) ? nil : parent.backgroundColor
        let placement = _computePlacement(contentSize: size)
        _placement = placement
        w.frameView.apply(placement)
        w.setFrame(placement.frame, display: false)
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            _observers.append(center.addObserver(forName: name, object: parent, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?._relayout() }
            })
        }
        _observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: parent, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?._parentDidBecomeKey() }
        })
        _observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?._windowIsClosing() }
        })
        NSPopover._shown.append(self)
        if NSView._traceInvalidation { NSView._trace("popover show \(placement.frame) side \(placement.side) behavior \(_behavior)") }
        parent.addChildWindow(w, ordered: .above)
        w.makeKey()
        if _animates, NSPopover._animationDuration > 0 {
            let pop = _NSPopoverPop(window: w, placement: placement, duration: NSPopover._animationDuration) { [weak self] in
                self?._pop = nil
                self?._didShow()
            }
            _pop = pop
            pop.start()
        } else {
            _didShow()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/willclosenotification
    static public var willCloseNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSPopoverWillCloseNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspopover/willshownotification
    static public var willShowNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSPopoverWillShowNotification") }

    // MARK: Accessibility (ADR-0013)
    //
    // The popover's window is the AXPopover element (its tree holds the content); the
    // popover object answers for it so `NSAccessibility.post(element: popover, …)` works.
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityFrame() -> NSRect { MainActor.assumeIsolated { _window?.frame ?? _detachedWindow?.frame ?? .zero } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityParent() -> Any? { MainActor.assumeIsolated { _positioningView } }
    // Requirement of NSAccessibilityElementProtocol
    open func isAccessibilityFocused() -> Bool { MainActor.assumeIsolated { _window?.isKeyWindow ?? _detachedWindow?.isKeyWindow ?? false } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { "" }

    // MARK: Showing and closing

    /// The content size: `contentSize` when set, else the view's frame, else what fits.
    private func _effectiveContentSize(for view: NSView) -> NSSize {
        if _contentSize.width > 0, _contentSize.height > 0 { return _contentSize }
        var s = view.frame.size
        if s.width <= 0 || s.height <= 0 { s = view.fittingSize }
        if s.width <= 0 || s.height <= 0 { s = _contentViewController?.preferredContentSize ?? .zero }
        return NSSize(width: max(s.width, 40), height: max(s.height, 20))
    }

    /// The positioning rect in screen coordinates: the view's bounds when the rect is empty.
    private func _anchorInScreen() -> NSRect? {
        guard let v = _positioningView, let w = v.window else { return nil }
        w.contentView?.layoutSubtreeIfNeeded()
        let rect = _positioningRect.isEmpty ? v.bounds : _positioningRect
        return w.convertToScreen(v.convert(rect, to: nil))
    }

    /// The preferred edge in screen space: the edge names are the view's, so a flipped
    /// view's `maxY` is its bottom.
    private var _preferredSideInScreen: NSRectEdge {
        guard _positioningView?.isFlipped ?? false else { return _preferredEdge }
        switch _preferredEdge {
        case .minY: return .maxY
        case .maxY: return .minY
        default: return _preferredEdge
        }
    }

    private func _computePlacement(contentSize: NSSize) -> _NSPopoverPlacement {
        let anchor = _anchorInScreen() ?? .zero
        let screen = (_positioningView?.window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        return _NSPopoverPlacement.compute(anchor: anchor, contentSize: contentSize, preferredSide: _preferredSideInScreen, screen: screen)
    }

    /// The parent moved or resized, or the content size changed: the window follows.
    internal func _relayout() {
        guard let w = _window, let vc = _contentViewController else { return }
        let size = _effectiveContentSize(for: vc.view)
        let placement = _computePlacement(contentSize: size)
        guard placement != _placement else { return }
        _placement = placement
        w.frameView.apply(placement)
        if let pop = _pop { pop.retarget(placement) } else if w.frame != placement.frame { w.setFrame(placement.frame, display: true) }
    }

    private func _didShow() {
        guard !_showNotified, isShown else { return }
        _showNotified = true
        let n = Notification(name: NSPopover.didShowNotification, object: self)
        NotificationCenter.default.post(n)
        _delegate?.popoverDidShow(n)
    }

    /// The window is going away by other means (its parent closed): the popover closes.
    private func _windowIsClosing() {
        guard !_isClosing else { return }
        _close(reason: .standard)
    }

    private func _removeObservers() {
        for o in _observers { NotificationCenter.default.removeObserver(o) }
        _observers.removeAll()
    }

    private func _close(reason: NSPopover.CloseReason) {
        guard isShown, !_isClosing else { return }
        _isClosing = true
        defer { _isClosing = false }
        _pop?.finish()
        if NSView._traceInvalidation { NSView._trace("popover close \(reason.rawValue)") }
        let info: [AnyHashable: Any] = [NSPopover.closeReasonUserInfoKey: reason]
        let willClose = Notification(name: NSPopover.willCloseNotification, object: self, userInfo: info)
        NotificationCenter.default.post(willClose)
        _delegate?.popoverWillClose(willClose)
        _removeObservers()
        let parent = _positioningView?.window
        var wasKey = false
        if let w = _window {
            _window = nil
            wasKey = w.isKeyWindow
            w._popover = nil
            _contentViewController?.view.removeFromSuperview()
            parent?.removeChildWindow(w)
            if wasKey { w.resignKey() }
            w.close()
        }
        if let d = _detachedWindow {
            _detachedWindow = nil
            wasKey = wasKey || d.isKeyWindow
            d.close()
        }
        _placement = nil
        NSPopover._shown.removeAll { $0 === self }
        if wasKey, let p = parent, p.isVisible { p.makeKey() }
        let didClose = Notification(name: NSPopover.didCloseNotification, object: self, userInfo: info)
        NotificationCenter.default.post(didClose)
        _delegate?.popoverDidClose(didClose)
    }

    // MARK: Behaviour (NSApplication.sendEvent)

    /// Whether `window` is this popover's window or a popover opened from inside it.
    private func _owns(_ window: NSWindow?) -> Bool {
        var w = window
        while let cur = w {
            if cur === _window || cur === _detachedWindow { return true }
            w = cur.parent
        }
        return false
    }

    /// A mouse down somewhere: transient popovers close on any click outside them,
    /// semitransient ones on a click in the window that holds the positioning view; the
    /// click still reaches what is under it. Called by NSApplication.sendEvent.
    internal static func _noteEvent(_ event: NSEvent) {
        guard !_shown.isEmpty else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: break
        default: return
        }
        for p in _shown.reversed() where p._window != nil {
            if p._owns(event.window) { continue }
            switch p._behavior {
            case .transient:
                p.performClose(nil)
            case .semitransient:
                if let w = event.window, w === p._positioningView?.window { p.performClose(nil) }
            case .applicationDefined:
                break
            }
        }
    }

    /// The popover's window lost the keyboard: a transient popover closes unless the key
    /// window is a popover opened from it; a semitransient one closes when its parent
    /// window took the keyboard (a click on its title bar).
    internal func _windowDidResignKey() {
        guard _window != nil, !_isClosing else { return }
        let key = NSApplication.shared.keyWindow
        if _owns(key) { return }
        switch _behavior {
        case .transient: performClose(nil)
        case .semitransient: if let k = key, k === _positioningView?.window { performClose(nil) }
        case .applicationDefined: break
        }
    }

    /// The parent window took the keyboard while the popover is up (a click on its title
    /// bar: on Win32 the popover's deactivation arrives before the parent's activation, so
    /// `_windowDidResignKey` saw no key window). Transient and semitransient popovers close.
    internal func _parentDidBecomeKey() {
        guard _window != nil, !_isClosing, _behavior != .applicationDefined else { return }
        performClose(nil)
    }

    /// Escape in the popover closes it unless the application decides (`.applicationDefined`).
    internal func _cancel() -> Bool {
        guard _behavior != .applicationDefined, _window != nil else { return false }
        performClose(nil)
        return true
    }

    // MARK: Detaching

    /// The user dragged the popover by its background. With a delegate window the popover
    /// closes with the `.detachToWindow` reason and that window shows in its place; with
    /// `popoverShouldDetach` alone the content moves into a titled window of the
    /// framework's and the popover stays shown as `isDetached`. Returns false when the
    /// delegate allows neither.
    internal func _detach(by delta: NSPoint) -> Bool {
        guard let w = _window, !_isClosing, let vc = _contentViewController else { return false }
        let should = _delegate?.popoverShouldDetach(self) ?? false
        let custom = _delegate?.detachableWindow(for: self)
        guard should || custom != nil else { return false }
        _pop?.finish()
        let body = w.convertToScreen(w.frameView.bodyRect).offsetBy(dx: delta.x, dy: delta.y)
        if let custom {
            // The delegate's window takes the body's place (its own size, top-left aligned).
            let content = custom.contentRect(forFrameRect: custom.frame)
            let origin = NSPoint(x: body.minX, y: body.maxY - content.height)
            custom.setFrame(custom.frameRect(forContentRect: NSRect(origin: origin, size: content.size)), display: false)
            custom.appearance = custom.appearance ?? _appearance
            _close(reason: .detachToWindow)
            custom.makeKeyAndOrderFront(nil)
            _delegate?.popoverDidDetach(self)
            return true
        }
        if NSView._traceInvalidation { NSView._trace("popover detach into a titled window at \(body)") }
        _removeObservers()
        _window = nil
        w._popover = nil
        let wasKey = w.isKeyWindow
        vc.view.removeFromSuperview()
        _positioningView?.window?.removeChildWindow(w)
        if wasKey { w.resignKey() }
        w.close()
        let detached = NSWindow(contentRect: body, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        detached.isReleasedWhenClosed = false
        detached.title = vc.title ?? ""
        detached.appearance = effectiveAppearance
        detached.contentViewController = vc
        detached.setFrame(detached.frameRect(forContentRect: body), display: false)
        _detachedWindow = detached
        _placement = nil
        _observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: detached, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?._windowIsClosing() }
        })
        detached.makeKeyAndOrderFront(nil)
        _delegate?.popoverDidDetach(self)
        return true
    }
}

// MARK: - Placement

/// Where a popover goes for an anchor rect: on the preferred side of it when the screen
/// has room there, else on the opposite side, else beside it, slid along the edge to stay
/// on screen with the arrow kept over the anchor. Screen coordinates, y up.
struct _NSPopoverPlacement: Equatable {
    static let arrowHeight: CGFloat = 11
    static let arrowBase: CGFloat = 22
    static let cornerRadius: CGFloat = 6

    /// The window frame.
    var frame: NSRect
    /// The anchor's edge the popover sits on (`.minY`: below the anchor).
    var side: NSRectEdge
    /// The body (the rounded rectangle) within the window.
    var bodyRect: NSRect
    /// The body edge the arrow is on, in window coordinates.
    var arrowEdge: NSRectEdge
    /// The arrow tip's position along that edge, in window coordinates (x for a
    /// horizontal edge, y for a vertical one).
    var arrowOffset: CGFloat

    static func opposite(_ e: NSRectEdge) -> NSRectEdge {
        switch e {
        case .minX: return .maxX
        case .maxX: return .minX
        case .minY: return .maxY
        case .maxY: return .minY
        @unknown default: return .minY
        }
    }

    static func compute(anchor: NSRect, contentSize: NSSize, preferredSide: NSRectEdge, screen: NSRect) -> _NSPopoverPlacement {
        let h = arrowHeight
        let cw = contentSize.width, ch = contentSize.height
        func frame(for side: NSRectEdge) -> NSRect {
            switch side {
            case .minY: return NSRect(x: anchor.midX - cw / 2, y: anchor.minY - h - ch, width: cw, height: ch + h)
            case .maxY: return NSRect(x: anchor.midX - cw / 2, y: anchor.maxY, width: cw, height: ch + h)
            case .minX: return NSRect(x: anchor.minX - h - cw, y: anchor.midY - ch / 2, width: cw + h, height: ch)
            case .maxX: return NSRect(x: anchor.maxX, y: anchor.midY - ch / 2, width: cw + h, height: ch)
            @unknown default: return NSRect(x: anchor.midX - cw / 2, y: anchor.minY - h - ch, width: cw, height: ch + h)
            }
        }
        /// Room beyond the anchor on that side, less what the popover needs there.
        func slack(for side: NSRectEdge) -> CGFloat {
            switch side {
            case .minY: return anchor.minY - screen.minY - (ch + h)
            case .maxY: return screen.maxY - anchor.maxY - (ch + h)
            case .minX: return anchor.minX - screen.minX - (cw + h)
            case .maxX: return screen.maxX - anchor.maxX - (cw + h)
            @unknown default: return -1
            }
        }
        let candidates: [NSRectEdge] = [preferredSide, opposite(preferredSide)] + ([.minY, .maxY, .minX, .maxX].filter { $0 != preferredSide && $0 != opposite(preferredSide) })
        let side = candidates.first { slack(for: $0) >= 0 } ?? candidates.max { slack(for: $0) < slack(for: $1) } ?? preferredSide
        var f = frame(for: side)
        let vertical = side == .minY || side == .maxY
        // Slide along the edge to stay on screen; then clamp the other axis as well.
        if vertical {
            if f.maxX > screen.maxX { f.origin.x = screen.maxX - f.width }
            if f.minX < screen.minX { f.origin.x = screen.minX }
            if f.maxY > screen.maxY { f.origin.y = screen.maxY - f.height }
            if f.minY < screen.minY { f.origin.y = screen.minY }
        } else {
            if f.maxY > screen.maxY { f.origin.y = screen.maxY - f.height }
            if f.minY < screen.minY { f.origin.y = screen.minY }
            if f.maxX > screen.maxX { f.origin.x = screen.maxX - f.width }
            if f.minX < screen.minX { f.origin.x = screen.minX }
        }
        f = NSRect(x: f.minX.rounded(), y: f.minY.rounded(), width: f.width.rounded(), height: f.height.rounded())
        let margin = cornerRadius + arrowBase / 2
        let body: NSRect
        let arrowEdge: NSRectEdge
        let offset: CGFloat
        switch side {
        case .minY:
            body = NSRect(x: 0, y: 0, width: f.width, height: f.height - h)
            arrowEdge = .maxY
            offset = min(max(anchor.midX - f.minX, margin), f.width - margin).rounded()
        case .maxY:
            body = NSRect(x: 0, y: h, width: f.width, height: f.height - h)
            arrowEdge = .minY
            offset = min(max(anchor.midX - f.minX, margin), f.width - margin).rounded()
        case .minX:
            body = NSRect(x: 0, y: 0, width: f.width - h, height: f.height)
            arrowEdge = .maxX
            offset = min(max(anchor.midY - f.minY, margin), f.height - margin).rounded()
        default:
            body = NSRect(x: h, y: 0, width: f.width - h, height: f.height)
            arrowEdge = .minX
            offset = min(max(anchor.midY - f.minY, margin), f.height - margin).rounded()
        }
        return _NSPopoverPlacement(frame: f, side: side, bodyRect: body, arrowEdge: arrowEdge, arrowOffset: offset)
    }
}

// MARK: - Window

/// The borderless window a popover shows in: transparent outside its body, with the
/// platform's shadow, able to take the keyboard (the content may hold text fields).
@MainActor
final class _NSPopoverWindow: NSWindow {
    weak var _popover: NSPopover?
    let frameView: _NSPopoverFrameView

    init(popover: NSPopover, contentSize: NSSize) {
        _popover = popover
        frameView = _NSPopoverFrameView(frame: NSRect(origin: .zero, size: NSSize(width: contentSize.width, height: contentSize.height + _NSPopoverPlacement.arrowHeight)))
        super.init(contentRect: frameView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        frameView.popover = popover
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        contentView = frameView
    }
    required init?(coder: NSCoder) { nil }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        let was = isKeyWindow
        super.resignKey()
        if was { _popover?._windowDidResignKey() }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.charactersIgnoringModifiers == "\u{1B}",
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            if contentView?.performKeyEquivalent(with: event) ?? false { return }
            if _popover?._cancel() ?? false { return }
        }
        super.sendEvent(event)
    }

    // The window is the AXPopover element; its title is nothing to read.
    override func accessibilityRole() -> NSAccessibility.Role? { .popover }
    override func accessibilityTitle() -> String? { nil }
}

// MARK: - Frame view

/// Draws the popover: the rounded body with its arrow, in the window's appearance
/// (plain or vibrant/HUD), transparent around it where the platform composites alpha,
/// over the parent's background colour where it does not. Holds the content view
/// controller's view in the body. Dragging its background detaches the popover.
@MainActor
final class _NSPopoverFrameView: NSView {
    weak var popover: NSPopover?
    private(set) var bodyRect = NSRect.zero
    private(set) var arrowEdge: NSRectEdge = .maxY
    private(set) var arrowOffset: CGFloat = 0
    /// Set where the window system shows no transparency (X11): what is around the body.
    var opaqueBacking: NSColor? = nil { didSet { needsDisplay = true } }
    private var dragStart: NSPoint? = nil
    private var detaching = false

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { opaqueBacking != nil }
    /// The whole window is client area: never a draggable title band.
    override var mouseDownCanMoveWindow: Bool { false }

    func apply(_ p: _NSPopoverPlacement) {
        bodyRect = p.bodyRect
        arrowEdge = p.arrowEdge
        arrowOffset = p.arrowOffset
        if frame.size != p.frame.size { setFrameSize(p.frame.size) }
        if let content = subviews.first, content.frame != bodyRect { content.frame = bodyRect }
        needsDisplay = true
    }

    func setContent(_ view: NSView) {
        for s in subviews { s.removeFromSuperview() }
        view.frame = bodyRect.isEmpty ? NSRect(origin: .zero, size: NSSize(width: frame.width, height: frame.height - _NSPopoverPlacement.arrowHeight)) : bodyRect
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    /// The body and arrow as one outline (y up).
    var outline: NSBezierPath {
        let r = _NSPopoverPlacement.cornerRadius
        let h = _NSPopoverPlacement.arrowHeight
        let half = _NSPopoverPlacement.arrowBase / 2
        let b = bodyRect.insetBy(dx: 0.5, dy: 0.5)
        let a = arrowOffset
        let p = NSBezierPath()
        // Clockwise from the top-left corner: top, right, bottom, left edges.
        p.move(to: NSPoint(x: b.minX + r, y: b.maxY))
        if arrowEdge == .maxY {
            p.line(to: NSPoint(x: a - half, y: b.maxY)); p.line(to: NSPoint(x: a, y: b.maxY + h)); p.line(to: NSPoint(x: a + half, y: b.maxY))
        }
        p.line(to: NSPoint(x: b.maxX - r, y: b.maxY))
        p.appendArc(withCenter: NSPoint(x: b.maxX - r, y: b.maxY - r), radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        if arrowEdge == .maxX {
            p.line(to: NSPoint(x: b.maxX, y: a + half)); p.line(to: NSPoint(x: b.maxX + h, y: a)); p.line(to: NSPoint(x: b.maxX, y: a - half))
        }
        p.line(to: NSPoint(x: b.maxX, y: b.minY + r))
        p.appendArc(withCenter: NSPoint(x: b.maxX - r, y: b.minY + r), radius: r, startAngle: 0, endAngle: -90, clockwise: true)
        if arrowEdge == .minY {
            p.line(to: NSPoint(x: a + half, y: b.minY)); p.line(to: NSPoint(x: a, y: b.minY - h)); p.line(to: NSPoint(x: a - half, y: b.minY))
        }
        p.line(to: NSPoint(x: b.minX + r, y: b.minY))
        p.appendArc(withCenter: NSPoint(x: b.minX + r, y: b.minY + r), radius: r, startAngle: -90, endAngle: -180, clockwise: true)
        if arrowEdge == .minX {
            p.line(to: NSPoint(x: b.minX, y: a - half)); p.line(to: NSPoint(x: b.minX - h, y: a)); p.line(to: NSPoint(x: b.minX, y: a + half))
        }
        p.line(to: NSPoint(x: b.minX, y: b.maxY - r))
        p.appendArc(withCenter: NSPoint(x: b.minX + r, y: b.maxY - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        p.close()
        return p
    }

    override func draw(_ dirtyRect: NSRect) {
        if let backing = opaqueBacking {
            backing.setFill()
            NSBezierPath.fill(bounds)
        }
        let path = outline
        let vibrant = effectiveAppearance.allowsVibrancy
        // Vibrant appearances (the default look, the HUD) let a little of what is behind
        // through where the platform composites alpha; plain ones are solid.
        let fill: NSColor = vibrant && opaqueBacking == nil ? NSColor.windowBackgroundColor.withAlphaComponent(0.94) : .windowBackgroundColor
        fill.setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(effectiveAppearance.isDark ? 1 : 0.8).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        detaching = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, !detaching else { return }
        let p = event.locationInWindow
        let delta = NSPoint(x: p.x - start.x, y: p.y - start.y)
        guard abs(delta.x) >= 4 || abs(delta.y) >= 4 else { return }
        detaching = true
        dragStart = nil
        _ = popover?._detach(by: delta)
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil; detaching = false }
}

// MARK: - Pop animation

/// The pop-out: the window starts a few points into the anchor and slides to its place,
/// one step per frame of a `CADisplayLink` on Core Animation's clock (`CARuntime.now`,
/// so tests drive it with a fake clock and `CARuntime.tick()`).
@MainActor final class _NSPopoverPop {
    private static let distance: CGFloat = 8
    private let window: NSWindow
    private var target: NSRect
    private var startFrame: NSRect
    private let duration: TimeInterval
    private let completion: () -> Void
    private var startTime: CFTimeInterval = 0
    private var link: CADisplayLink? = nil
    private var finished = false

    init(window: NSWindow, placement: _NSPopoverPlacement, duration: TimeInterval, completion: @escaping () -> Void) {
        self.window = window
        self.target = placement.frame
        self.startFrame = _NSPopoverPop.startFrame(for: placement)
        self.duration = duration
        self.completion = completion
    }

    private static func startFrame(for p: _NSPopoverPlacement) -> NSRect {
        switch p.side {
        case .minY: return p.frame.offsetBy(dx: 0, dy: distance)
        case .maxY: return p.frame.offsetBy(dx: 0, dy: -distance)
        case .minX: return p.frame.offsetBy(dx: distance, dy: 0)
        default: return p.frame.offsetBy(dx: -distance, dy: 0)
        }
    }

    func start() {
        guard duration > 0 else { finish(); return }
        startTime = CARuntime.now()
        apply(0)
        let l = CADisplayLink { [weak self] _ in self?.step() }
        link = l
        l.add(to: .main, forMode: .default)
    }

    /// The parent moved mid-animation: the destination moves with it.
    func retarget(_ p: _NSPopoverPlacement) {
        target = p.frame
        startFrame = _NSPopoverPop.startFrame(for: p)
    }

    private func step() {
        let t = min(1, max(0, (CARuntime.now() - startTime) / duration))
        let eased = 1 - (1 - t) * (1 - t)
        apply(eased)
        if t >= 1 { finish() }
    }

    private func apply(_ progress: Double) {
        let k = CGFloat(progress)
        let f = NSRect(x: startFrame.minX + (target.minX - startFrame.minX) * k, y: startFrame.minY + (target.minY - startFrame.minY) * k, width: target.width, height: target.height)
        let rounded = NSRect(x: f.minX.rounded(), y: f.minY.rounded(), width: f.width, height: f.height)
        if window.frame != rounded { window.setFrame(rounded, display: true) }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        link?.invalidate()
        link = nil
        apply(1)
        completion()
    }
}

extension NSWindow {
    /// Whether this is a popover's window (tooling that renders windows, such as the
    /// examples' screenshots). Not part of Apple's API.
    public var _isPopoverWindow: Bool { self is _NSPopoverWindow }
}
