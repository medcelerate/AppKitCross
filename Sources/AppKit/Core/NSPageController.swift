// NSPageController (hand-written; seeded from the generated stub, see tools/apigen)
// Pages through `arrangedObjects`, one view controller per page, cached by the
// identifier the delegate gives each object. Transitions slide the pages in the
// controller's view on the Core Animation display link (`CADisplayLink`, driven by
// `CARuntime.tick()` on every platform), so tests step them with a fake clock. A
// two-finger horizontal scroll pages live, swipe events and the arrow keys page with
// an animation (ADR-0022).
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller
@MainActor open class NSPageController: NSViewController, NSAnimatablePropertyContainer, NSSelectorHandling {
    // MARK: Storage
    private var _arrangedObjects: [Any] = []
    private var _selectedIndex = 0
    private var _transitionStyle: NSPageController.TransitionStyle = .stackHistory
    private weak var _delegate: (any NSPageControllerDelegate)?
    /// Every controller made for an identifier; the ones not on screen are reused.
    private var _cache: [NSPageController.ObjectIdentifier: [NSViewController]] = [:]
    /// The controller of the page on screen (`selectedViewController`).
    private var _current: NSViewController?
    private var _animatorPending = false

    /// A transition in flight: the outgoing and incoming pages, how far along it is, and
    /// whether the user drives it (a live transition) or the display link does.
    private struct Transition {
        var from: NSViewController?
        var fromIndex: Int
        var to: NSViewController?
        var toIndex: Int
        /// 0 shows `from`, 1 shows `to`; a live transition may go negative or past 1 (rubber band).
        var progress: CGFloat = 0
        var live: Bool
        /// The settle animation after a live transition or a programmatic one.
        var animating = false
        var animationStart: CFTimeInterval = 0
        var animationFrom: CGFloat = 0
        var animationTo: CGFloat = 1
        var duration: CFTimeInterval = 0.25
    }
    private var _transition: Transition?
    private var _displayLink: CADisplayLink?
    /// Set once the delegate was told about the arrival and until `completeTransition()` ran.
    private var _awaitingCompletion = false
    /// Horizontal scroll steps of a wheel (no phases) are debounced per transition.
    private var _wheelAccumulator: CGFloat = 0

    open override func loadView() {
        view = _NSPageControllerView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    }
    open override func viewDidLoad() {
        super.viewDidLoad()
        _displaySelectedPage()
    }

    // MARK: Objects and identifiers

    /// The identifier the delegate gives an object; nil when the delegate does not
    /// implement it, in which case the object must be a view controller itself.
    private func _identifier(for object: Any) -> NSPageController.ObjectIdentifier? {
        guard let d = _delegate else { return nil }
        let id = d.pageController(self, identifierFor: object)
        return id.isEmpty ? nil : id
    }

    private func _objectsMatch(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? AnyHashable, let y = b as? AnyHashable { return x == y }
        if type(of: a) is AnyClass, type(of: b) is AnyClass { return (a as AnyObject) === (b as AnyObject) }
        return String(describing: a) == String(describing: b)
    }

    /// The controller for a page: a cached one not on screen, else a new one from the
    /// delegate, prepared with the object (its `representedObject`, then the delegate).
    private func _viewController(forPageAt index: Int, avoiding busy: [NSViewController]) -> NSViewController? {
        guard _arrangedObjects.indices.contains(index) else { return nil }
        let object = _arrangedObjects[index]
        let vc: NSViewController
        if let id = _identifier(for: object), let d = _delegate {
            if let spare = _cache[id]?.first(where: { candidate in !busy.contains { $0 === candidate } }) {
                vc = spare
            } else {
                vc = d.pageController(self, viewControllerForIdentifier: id)
                _cache[id, default: []].append(vc)
            }
        } else if let own = object as? NSViewController {
            vc = own
        } else {
            preconditionFailure("NSPageController: arrangedObjects must be view controllers when the delegate does not answer pageController(_:identifierFor:)")
        }
        if vc.parent !== self { addChild(vc) }
        vc.representedObject = object
        _delegate?.pageController(self, prepare: vc, with: object)
        return vc
    }

    /// The frame a page gets: the delegate's, else the whole view.
    private func _pageFrame(for object: Any?) -> NSRect {
        _delegate?.pageController(self, frameFor: object) ?? view.bounds
    }

    /// Shows the selected page without a transition (first display, a new object list).
    private func _displaySelectedPage() {
        guard isViewLoaded else { return }
        _cancelTransition()
        let old = _current
        let vc = _viewController(forPageAt: _selectedIndex, avoiding: [])
        if let old, old !== vc { old.view.removeFromSuperview() }
        _current = vc
        guard let vc else { return }
        let page = vc.view
        page.frame = _pageFrame(for: _arrangedObjects[_selectedIndex])
        page.autoresizingMask = [.width, .height]
        if page.superview !== view { view.addSubview(page) }
        page.isHidden = false
    }

    // MARK: Transitions

    private var _forwardDirection: CGFloat { view.userInterfaceLayoutDirection == .rightToLeft ? -1 : 1 }

    /// Starts a transition to `index`; animated ones run on the display link, the others
    /// land at once. Returns false when there is nothing to do.
    @discardableResult
    private func _transition(to index: Int, animated: Bool) -> Bool {
        guard _arrangedObjects.indices.contains(index) else { return false }
        if let t = _transition, t.live { return false }     // the user's gesture owns the pages
        _cancelTransition()
        let fromIndex = _selectedIndex
        _selectedIndex = index
        guard isViewLoaded else { return true }
        guard index != fromIndex || _current == nil else { return true }
        let from = _current
        let to = _viewController(forPageAt: index, avoiding: from.map { [$0] } ?? [])
        var t = Transition(from: from, fromIndex: fromIndex, to: to, toIndex: index, live: false)
        _addPage(to, for: index)
        if animated, view.bounds.width > 0, from != nil {
            t.animating = true
            t.animationStart = CARuntime.now()
            t.animationFrom = 0
            t.animationTo = 1
            t.duration = NSAnimationContext.current.duration
            _transition = t
            _layoutTransition()
            if t.duration <= 0 { _finishTransition() } else { _startDisplayLink() }
        } else {
            t.progress = 1
            _transition = t
            _finishTransition()
        }
        return true
    }

    private func _addPage(_ vc: NSViewController?, for index: Int) {
        guard let vc else { return }
        let page = vc.view
        page.frame = _pageFrame(for: _arrangedObjects[index])
        page.autoresizingMask = [.width, .height]
        if page.superview !== view { view.addSubview(page) }
        page.isHidden = false
    }

    /// Places the outgoing and incoming pages for the transition's progress and style.
    private func _layoutTransition() {
        guard let t = _transition else { return }
        let w = view.bounds.width
        let dir: CGFloat = (t.toIndex >= t.fromIndex ? 1 : -1) * _forwardDirection
        let p = t.progress
        let fromObject: Any? = _arrangedObjects.indices.contains(t.fromIndex) ? _arrangedObjects[t.fromIndex] : nil
        let toObject: Any? = _arrangedObjects.indices.contains(t.toIndex) ? _arrangedObjects[t.toIndex] : nil
        let fromBase = _pageFrame(for: fromObject), toBase = _pageFrame(for: toObject)
        var fromX = fromBase.minX, toX = toBase.minX
        var incomingOnTop = true
        switch _transitionStyle {
        case .horizontalStrip:
            // Side by side: both move.
            fromX -= dir * p * w
            toX += dir * (1 - p) * w
        case .stackHistory:
            // Forward: the new page slides in over the old one from the far side; back:
            // the top page slides out the way it came, revealing the one beneath.
            if dir * _forwardDirection > 0 { toX += dir * (1 - p) * w }
            else { fromX -= dir * p * w; incomingOnTop = false }
        case .stackBook:
            // A book: forward turns the current page away, revealing the next beneath;
            // back brings the previous page in over the current one.
            if dir * _forwardDirection > 0 { fromX -= dir * p * w; incomingOnTop = false }
            else { toX += dir * (1 - p) * w }
        }
        if let f = t.from?.view { f.frame = NSRect(x: fromX, y: fromBase.minY, width: fromBase.width, height: fromBase.height) }
        if let v = t.to?.view {
            v.frame = NSRect(x: toX, y: toBase.minY, width: toBase.width, height: toBase.height)
            if let f = t.from?.view, v.superview === view, f.superview === view {
                let onTop = view.subviews.last
                if incomingOnTop, onTop !== v { view.addSubview(v, positioned: .above, relativeTo: f) }
                if !incomingOnTop, onTop !== f { view.addSubview(f, positioned: .above, relativeTo: v) }
            }
        }
    }

    private func _startDisplayLink() {
        guard _displayLink == nil else { return }
        let link = CADisplayLink { [weak self] _ in self?._tick() }
        link.add(to: .main, forMode: .common)
        _displayLink = link
    }

    private func _stopDisplayLink() {
        _displayLink?.invalidate()
        _displayLink = nil
    }

    /// One frame of a settle animation: eased progress towards the target.
    private func _tick() {
        guard var t = _transition, t.animating else { _stopDisplayLink(); return }
        let elapsed = CARuntime.now() - t.animationStart
        var fraction = t.duration > 0 ? min(1, max(0, elapsed / t.duration)) : 1
        fraction = fraction < 0.5 ? 2 * fraction * fraction : 1 - pow(-2 * fraction + 2, 2) / 2    // ease in-out
        t.progress = t.animationFrom + (t.animationTo - t.animationFrom) * CGFloat(fraction)
        _transition = t
        _layoutTransition()
        if fraction >= 1 {
            _stopDisplayLink()
            if t.animationTo >= 1 { _finishTransition() } else { _abandonTransition() }
        }
    }

    /// The incoming page is in place: the outgoing one leaves, the delegate hears about
    /// the arrival and may call `completeTransition()`; otherwise it runs here.
    private func _finishTransition() {
        guard var t = _transition else { return }
        t.progress = 1
        t.animating = false
        _transition = t
        _layoutTransition()
        _stopDisplayLink()
        if let from = t.from, from !== t.to {
            // The keyboard focus follows the pages: an outgoing page that held it hands it on.
            if let w = view.window, let fr = w.firstResponder as? NSView, fr === from.view || fr.isDescendant(of: from.view) {
                if let to = t.to, w.makeFirstResponder(to.view) {} else { _ = w.makeFirstResponder(view.acceptsFirstResponder ? view : nil) }
            }
            from.view.removeFromSuperview()
        }
        _current = t.to
        _awaitingCompletion = true
        if _arrangedObjects.indices.contains(t.toIndex) {
            _delegate?.pageController(self, didTransitionTo: _arrangedObjects[t.toIndex])
        }
        if _awaitingCompletion { completeTransition() }
    }

    /// A live transition that did not reach the next page: the incoming page leaves again.
    private func _abandonTransition() {
        guard let t = _transition else { return }
        _stopDisplayLink()
        if let to = t.to, to !== t.from { to.view.removeFromSuperview() }
        _selectedIndex = t.fromIndex
        _transition = nil
        if let from = t.from {
            from.view.frame = _pageFrame(for: _arrangedObjects.indices.contains(t.fromIndex) ? _arrangedObjects[t.fromIndex] : nil)
        }
    }

    /// Drops whatever transition is running, landing on the selected page.
    private func _cancelTransition() {
        guard _transition != nil else { return }
        _stopDisplayLink()
        if let t = _transition {
            if t.progress >= 0.5, t.to != nil { _finishTransition() } else { _abandonTransition() }
        }
        _transition = nil
    }

    // MARK: Live transitions (two-finger scroll)

    private func _beginLiveTransition() {
        _cancelTransition()
        _transition = Transition(from: _current, fromIndex: _selectedIndex, to: nil, toIndex: _selectedIndex, live: true)
        _delegate?.pageControllerWillStartLiveTransition(self)
    }

    /// Moves the pages by a fraction of the width; the incoming page is picked by the sign.
    private func _updateLiveTransition(by delta: CGFloat) {
        guard var t = _transition, t.live, view.bounds.width > 0 else { return }
        var progress = t.progress + delta
        let forward = progress >= 0
        let target = t.fromIndex + (forward ? 1 : -1)
        if !_arrangedObjects.indices.contains(target) {
            // Nothing that way: the page resists (a quarter of the pull) and springs back.
            t.progress = progress / 4
            if let to = t.to { to.view.removeFromSuperview(); t.to = nil }
            t.toIndex = t.fromIndex
            _transition = t
            _layoutResisted()
            return
        }
        if t.toIndex != target || t.to == nil {
            if let old = t.to, old !== t.from { old.view.removeFromSuperview() }
            t.to = _viewController(forPageAt: target, avoiding: t.from.map { [$0] } ?? [])
            t.toIndex = target
            _transition = t
            _addPage(t.to, for: target)
        }
        progress = min(1, max(-1, progress))
        t.progress = abs(progress)
        _transition = t
        _layoutTransition()
    }

    /// The pull against an edge: the current page shifts a little and comes back.
    private func _layoutResisted() {
        guard let t = _transition, let from = t.from else { return }
        let base = _pageFrame(for: _arrangedObjects.indices.contains(t.fromIndex) ? _arrangedObjects[t.fromIndex] : nil)
        from.view.frame = NSRect(x: base.minX - t.progress * _forwardDirection * view.bounds.width, y: base.minY, width: base.width, height: base.height)
    }

    /// The fingers lifted: past the middle the pages settle on the new one, else back.
    private func _endLiveTransition() {
        guard var t = _transition, t.live else { return }
        _delegate?.pageControllerDidEndLiveTransition(self)
        t.live = false
        let advancing = t.to != nil && t.progress >= 0.5
        if t.to == nil {
            // Sprang against an edge: restore the current page.
            _transition = nil
            if let from = t.from { from.view.frame = _pageFrame(for: _arrangedObjects.indices.contains(t.fromIndex) ? _arrangedObjects[t.fromIndex] : nil) }
            return
        }
        if advancing { _selectedIndex = t.toIndex }
        t.animating = true
        t.animationStart = CARuntime.now()
        t.animationFrom = t.progress
        t.animationTo = advancing ? 1 : 0
        t.duration = NSAnimationContext.current.duration * Double(abs(t.animationTo - t.progress))
        _transition = t
        if t.duration <= 0 { if advancing { _finishTransition() } else { _abandonTransition() } }
        else { _startDisplayLink() }
    }

    // MARK: Events

    /// A horizontal two-finger scroll pages live; a wheel without phases pages a step.
    open override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        if event.phase.contains(.began) {
            _beginLiveTransition()
            return
        }
        if let t = _transition, t.live {
            if event.phase.contains(.changed) {
                guard view.bounds.width > 0 else { return }
                // Fingers moving left (content follows them) go forward.
                _updateLiveTransition(by: -dx * _forwardDirection / view.bounds.width)
                return
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                _endLiveTransition()
                return
            }
        }
        if !event.momentumPhase.isEmpty { return }
        if event.phase.isEmpty, abs(dx) > abs(event.scrollingDeltaY), dx != 0 {
            // A mouse's horizontal wheel: one page per notch, while nothing is in flight.
            guard _transition == nil else { return }
            _wheelAccumulator += dx
            if _wheelAccumulator <= -1 { _wheelAccumulator = 0; if _forwardDirection > 0 { navigateForward(nil) } else { navigateBack(nil) } }
            else if _wheelAccumulator >= 1 { _wheelAccumulator = 0; if _forwardDirection > 0 { navigateBack(nil) } else { navigateForward(nil) } }
            return
        }
        super.scrollWheel(with: event)
    }

    /// A swipe event (three fingers, or the platform's gesture): left goes forward.
    open override func swipe(with event: NSEvent) {
        if event.deltaX < 0 { if _forwardDirection > 0 { navigateForward(nil) } else { navigateBack(nil) } }
        else if event.deltaX > 0 { if _forwardDirection > 0 { navigateBack(nil) } else { navigateForward(nil) } }
        else { super.swipe(with: event) }
    }

    /// Left and right arrows page (mirrored right to left).
    open override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\u{F702}": if _forwardDirection > 0 { navigateBack(nil) } else { navigateForward(nil) }
        case "\u{F703}": if _forwardDirection > 0 { navigateForward(nil) } else { navigateBack(nil) }
        default: super.keyDown(with: event)
        }
    }

    // MARK: NSAnimatablePropertyContainer

    /// Property changes made through the proxy animate: `animator().selectedIndex = 2`.
    @MainActor public func animator() -> Self {
        _animatorPending = true
        return self
    }
    private func _takeAnimator() -> Bool {
        let a = _animatorPending
        _animatorPending = false
        return a
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/arrangedobjects
    @MainActor open var arrangedObjects: [Any] {
        get { _arrangedObjects }
        set {
            _cancelTransition()
            _arrangedObjects = newValue
            _selectedIndex = newValue.isEmpty ? 0 : min(max(0, _selectedIndex), newValue.count - 1)
            _displaySelectedPage()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/completetransition()
    /// Settles the pages after a transition: the arrived page fills its frame, the cache
    /// keeps the others. Called by the delegate from `pageController(_:didTransitionTo:)`
    /// once it updated the page's content, or by the controller when it does not.
    @MainActor open func completeTransition() {
        _awaitingCompletion = false
        guard let t = _transition else { return }
        _transition = nil
        _stopDisplayLink()
        if let vc = t.to {
            vc.view.frame = _pageFrame(for: _arrangedObjects.indices.contains(t.toIndex) ? _arrangedObjects[t.toIndex] : nil)
            vc.view.isHidden = false
        }
        _wheelAccumulator = 0
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/delegate
    @MainActor open var delegate: (any NSPageControllerDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/navigateback(_:)
    @MainActor open func navigateBack(_ sender: Any?) { _transition(to: _selectedIndex - 1, animated: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/navigateforward(_:)
    @MainActor open func navigateForward(_ sender: Any?) { _transition(to: _selectedIndex + 1, animated: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/navigateforward(to:)
    @MainActor open func navigateForward(to object: Any) {
        guard let i = _arrangedObjects.firstIndex(where: { _objectsMatch($0, object) }) else { return }
        _transition(to: i, animated: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/selectedindex
    /// Setting it shows the page at once; through `animator()` it transitions.
    @MainActor open var selectedIndex: Int {
        get { _selectedIndex }
        set {
            let animated = _takeAnimator()
            guard newValue != _selectedIndex || _current == nil else { return }
            _transition(to: newValue, animated: animated)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/selectedviewcontroller
    @MainActor open var selectedViewController: NSViewController? { _current }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/takeselectedindexfrom(_:)
    /// Takes the sender's integer value (a segmented control's selected segment, a
    /// menu item's tag) as the index, with an animation.
    @MainActor open func takeSelectedIndexFrom(_ sender: Any?) {
        let index: Int?
        if let seg = sender as? NSSegmentedControl { index = seg.selectedSegment }
        else if let c = sender as? NSControl { index = c.integerValue }
        else if let m = sender as? NSMenuItem { index = m.tag }
        else if let i = sender as? Int { index = i }
        else { index = nil }
        guard let index else { return }
        _transition(to: index, animated: true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/transitionstyle
    @MainActor open var transitionStyle: NSPageController.TransitionStyle {
        get { _transitionStyle }
        set { _transitionStyle = newValue }
    }
    // SKIPPED (Foundation.NSExtensionContext not in corelibs): func beginRequest(with context: NSExtensionContext)

    // MARK: Standard actions (TargetAction.swift)

    /// The navigation actions a control or menu item can target.
    public func respondsToSelectorAction(_ action: Selector) -> Bool {
        switch NSStringFromSelector(action) {
        case "navigateForward:": return _arrangedObjects.indices.contains(_selectedIndex + 1)
        case "navigateBack:": return _arrangedObjects.indices.contains(_selectedIndex - 1)
        case "takeSelectedIndexFrom:": return true
        default: return false
        }
    }
    public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "navigateForward:": navigateForward(sender)
        case "navigateBack:": navigateBack(sender)
        case "takeSelectedIndexFrom:": takeSelectedIndexFrom(sender)
        default: return false
        }
        return true
    }

    /// Test and tooling hook: the progress of the transition in flight, nil when none.
    internal var _transitionProgress: CGFloat? { _transition?.progress }
    internal var _isLiveTransition: Bool { _transition?.live ?? false }
}

/// The page controller's own view: clips its pages while they slide.
@MainActor
final class _NSPageControllerView: NSView {}

extension NSPageController {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/objectidentifier
    public typealias ObjectIdentifier = String
}

extension NSPageController {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/transitionstyle
    public enum TransitionStyle: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/transitionstyle/horizontalstrip
        case horizontalStrip = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/transitionstyle/stackbook
        case stackBook = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspagecontroller/transitionstyle/stackhistory
        case stackHistory = 0
        // SKIPPED (constrained extension): func hash(into hasher: inout Hasher)
        // SKIPPED (constrained extension): var hashValue: Int { get }
    }
}
