// NSSplitView (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview
@MainActor open class NSSplitView: NSView {
    // MARK: Storage
    private var _arranged: [NSView] = []
    private var _arrangesAllSubviews = true
    private var _autosaveName: NSSplitView.AutosaveName? = nil
    private weak var _delegate: (any NSSplitViewDelegate)? = nil
    private var _dividerStyle: NSSplitView.DividerStyle = .thick
    private var _isVertical = false
    private var _holdingPriorities: [NSLayoutConstraint.Priority] = []
    private var _collapsed: Set<ObjectIdentifier> = []
    private var _draggingDivider: Int? = nil
    private var _dragOffset: CGFloat = 0
    /// Last computed divider positions (along the split axis, from the min edge).
    private var _positions: [CGFloat] = []

    /// Thickness of each arranged view along the split axis.
    private func _thickness(_ v: NSView) -> CGFloat { _isVertical ? v.frame.width : v.frame.height }
    private var _axisLength: CGFloat { _isVertical ? bounds.width : bounds.height }

    open override var isFlipped: Bool { true }

    // MARK: Accessibility (ADR-0013)
    // AXSplitGroup whose children are the panes.
    open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .splitGroup }
    open func accessibilityOrientation() -> NSAccessibilityOrientation { isVertical ? .vertical : .horizontal }
    override func _accessibilityIsFocusable() -> Bool { false }

    /// Lays the arranged views out along the axis using the current thicknesses, giving
    /// any difference to the view with the lowest holding priority.
    private func _layoutArranged(oldLength: CGFloat?) {
        let views = arrangedSubviews
        guard !views.isEmpty else { return }
        let total = _axisLength
        let dividers = CGFloat(max(0, views.count - 1)) * dividerThickness
        var sizes = views.map { _collapsed.contains(ObjectIdentifier($0)) ? 0 : _thickness($0) }
        let available = max(0, total - dividers)
        let delta = available - sizes.reduce(0, +)
        if delta != 0 {
            // Distribute to the lowest holding priority first, then the next.
            let order = views.indices.sorted { holdingPriorityForSubview(at: $0).rawValue < holdingPriorityForSubview(at: $1).rawValue }
            var remaining = delta
            for i in order where !_collapsed.contains(ObjectIdentifier(views[i])) {
                if remaining > 0 { sizes[i] += remaining; remaining = 0; break }
                let take = min(sizes[i], -remaining)
                sizes[i] -= take
                remaining += take
                if remaining >= 0 { break }
            }
        }
        var offset: CGFloat = 0
        _positions = []
        for (i, v) in views.enumerated() {
            let size = max(0, sizes[i])
            let f = _isVertical ? NSRect(x: offset, y: 0, width: size, height: bounds.height) : NSRect(x: 0, y: offset, width: bounds.width, height: size)
            if v.frame != f { v.frame = f }
            v.isHidden = _collapsed.contains(ObjectIdentifier(v)) && size == 0 ? true : v.isHidden && _collapsed.contains(ObjectIdentifier(v))
            offset += size
            if i < views.count - 1 { _positions.append(offset); offset += dividerThickness }
        }
        needsDisplay = true
    }

    /// The divider rect at `index`, in bounds coordinates.
    private func _dividerRect(_ index: Int) -> NSRect {
        guard _positions.indices.contains(index) else { return .zero }
        let p = _positions[index]
        return _isVertical ? NSRect(x: p, y: 0, width: dividerThickness, height: bounds.height) : NSRect(x: 0, y: p, width: bounds.width, height: dividerThickness)
    }

    open override func resizeSubviews(withOldSize oldSize: NSSize) {
        if let d = _delegate, d.splitView(self, shouldAdjustSizeOfSubview: self) == false { return }
        NotificationCenter.default.post(name: NSSplitView.willResizeSubviewsNotification, object: self)
        _delegate?.splitViewWillResizeSubviews(Notification(name: NSSplitView.willResizeSubviewsNotification, object: self))
        _layoutArranged(oldLength: _isVertical ? oldSize.width : oldSize.height)
        NotificationCenter.default.post(name: NSSplitView.didResizeSubviewsNotification, object: self)
        _delegate?.splitViewDidResizeSubviews(Notification(name: NSSplitView.didResizeSubviewsNotification, object: self))
    }

    open override func layout() {
        super.layout()
        _layoutArranged(oldLength: nil)
    }

    open override func draw(_ dirtyRect: NSRect) {
        for i in 0..<max(0, arrangedSubviews.count - 1) where !(_delegate?.splitView(self, shouldHideDividerAt: i) ?? false) {
            let r = _dividerRect(i)
            if r.intersects(dirtyRect) { drawDivider(in: r) }
        }
    }

    open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in 0..<max(0, arrangedSubviews.count - 1) {
            var r = _dividerRect(i)
            r = r.insetBy(dx: _isVertical ? -2 : 0, dy: _isVertical ? 0 : -2)
            if r.contains(p) {
                if event.clickCount == 2, let d = _delegate {
                    let views = arrangedSubviews
                    if d.splitView(self, canCollapseSubview: views[i]) && d.splitView(self, shouldCollapseSubview: views[i], forDoubleClickOnDividerAt: i) {
                        _setCollapsed(views[i], true)
                        return
                    }
                }
                _draggingDivider = i
                _dragOffset = (_isVertical ? p.x : p.y) - _positions[i]
                return
            }
        }
        super.mouseDown(with: event)
    }

    open override func mouseDragged(with event: NSEvent) {
        guard let i = _draggingDivider else { super.mouseDragged(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        setPosition((_isVertical ? p.x : p.y) - _dragOffset, ofDividerAt: i)
    }

    open override func mouseUp(with event: NSEvent) {
        if _draggingDivider != nil { _draggingDivider = nil; return }
        super.mouseUp(with: event)
    }

    open override func resetCursorRects() {
        for i in 0..<max(0, arrangedSubviews.count - 1) {
            addCursorRect(_dividerRect(i), cursor: _isVertical ? .resizeLeftRight : .resizeUpDown)
        }
    }

    internal func _setCollapsed(_ view: NSView, _ collapsed: Bool) {
        if collapsed { _collapsed.insert(ObjectIdentifier(view)) } else { _collapsed.remove(ObjectIdentifier(view)) }
        view.isHidden = collapsed
        _layoutArranged(oldLength: nil)
    }

    open override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if _arrangesAllSubviews, !_arranged.contains(where: { $0 === subview }) { _arranged.append(subview) }
        needsLayout = true
    }

    open override func willRemoveSubview(_ subview: NSView) {
        super.willRemoveSubview(subview)
        _arranged.removeAll { $0 === subview }
        _collapsed.remove(ObjectIdentifier(subview))
        needsLayout = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/addarrangedsubview(_:)
    @available(macOS 10.11, *)
    @MainActor open func addArrangedSubview(_ view: NSView) { insertArrangedSubview(view, at: _arranged.count) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/adjustsubviews()
    /// Resizes the arranged views proportionally to fill the split view.
    @MainActor open func adjustSubviews() {
        let views = arrangedSubviews.filter { !_collapsed.contains(ObjectIdentifier($0)) }
        guard !views.isEmpty else { return }
        let dividers = CGFloat(max(0, arrangedSubviews.count - 1)) * dividerThickness
        let available = max(0, _axisLength - dividers)
        let current = views.map { _thickness($0) }
        let sum = current.reduce(0, +)
        for (i, v) in views.enumerated() {
            let size = sum > 0 ? (current[i] / sum * available).rounded() : (available / CGFloat(views.count)).rounded()
            if _isVertical { v.setFrameSize(NSSize(width: size, height: bounds.height)) } else { v.setFrameSize(NSSize(width: bounds.width, height: size)) }
        }
        _layoutArranged(oldLength: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/arrangedsubviews
    @available(macOS 10.11, *)
    @MainActor open var arrangedSubviews: [NSView] { _arrangesAllSubviews ? subviews : _arranged }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/arrangesallsubviews
    @available(macOS 10.11, *)
    @MainActor open var arrangesAllSubviews: Bool {
        get { _arrangesAllSubviews }
        set { _arrangesAllSubviews = newValue; if newValue { _arranged = subviews }; needsLayout = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/autosavename
    @MainActor open var autosaveName: NSSplitView.AutosaveName? {
        get { _autosaveName }
        set { _autosaveName = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/delegate
    @MainActor open var delegate: (any NSSplitViewDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/didresizesubviewsnotification
    static public var didResizeSubviewsNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSSplitViewDidResizeSubviewsNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/dividercolor
    @MainActor open var dividerColor: NSColor { _dividerStyle == .paneSplitter ? NSColor.separatorColor : NSColor.separatorColor.withAlphaComponent(0.6) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/dividerstyle
    @MainActor open var dividerStyle: NSSplitView.DividerStyle {
        get { _dividerStyle }
        set { _dividerStyle = newValue; needsLayout = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/dividerthickness
    @MainActor open var dividerThickness: CGFloat {
        switch _dividerStyle {
        case .thin: return 1
        case .paneSplitter: return 10
        default: return 9
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/drawdivider(in:)
    @MainActor open func drawDivider(in rect: NSRect) {
        dividerColor.setFill()
        if _dividerStyle == .thin {
            NSBezierPath(rect: rect).fill()
        } else {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: rect).fill()
            // A short grip in the middle.
            let grip = _isVertical ? NSRect(x: rect.midX - 1, y: rect.midY - 12, width: 2, height: 24) : NSRect(x: rect.midX - 12, y: rect.midY - 1, width: 24, height: 2)
            NSColor.separatorColor.setFill()
            NSBezierPath(roundedRect: grip, xRadius: 1, yRadius: 1).fill()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/holdingpriorityforsubview(at:)
    @MainActor open func holdingPriorityForSubview(at subviewIndex: Int) -> NSLayoutConstraint.Priority { _holdingPriorities.indices.contains(subviewIndex) ? _holdingPriorities[subviewIndex] : NSLayoutConstraint.Priority(250) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/insertarrangedsubview(_:at:)
    @available(macOS 10.11, *)
    @MainActor open func insertArrangedSubview(_ view: NSView, at index: Int) {
        if view.superview !== self { addSubview(view) }
        _arranged.removeAll { $0 === view }
        _arranged.insert(view, at: min(index, _arranged.count))
        _arrangesAllSubviews = false
        needsLayout = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/issubviewcollapsed(_:)
    @MainActor open func isSubviewCollapsed(_ subview: NSView) -> Bool { _collapsed.contains(ObjectIdentifier(subview)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/isvertical
    @MainActor open var isVertical: Bool {
        get { _isVertical }
        set { _isVertical = newValue; needsLayout = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/maxpossiblepositionofdivider(at:)
    @MainActor open func maxPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        let views = arrangedSubviews
        guard dividerIndex + 1 < views.count else { return _axisLength }
        // Up to the start of the view after the next divider.
        var limit = _axisLength - dividerThickness
        if dividerIndex + 1 < _positions.count { limit = _positions[dividerIndex + 1] - dividerThickness }
        return _delegate?.splitView(self, constrainMaxCoordinate: limit, ofSubviewAt: dividerIndex) ?? limit
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/minpossiblepositionofdivider(at:)
    @MainActor open func minPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        var limit: CGFloat = 0
        if dividerIndex > 0, dividerIndex - 1 < _positions.count { limit = _positions[dividerIndex - 1] + dividerThickness }
        return _delegate?.splitView(self, constrainMinCoordinate: limit, ofSubviewAt: dividerIndex) ?? limit
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/removearrangedsubview(_:)
    @available(macOS 10.11, *)
    @MainActor open func removeArrangedSubview(_ view: NSView) {
        _arranged.removeAll { $0 === view }
        _arrangesAllSubviews = false
        needsLayout = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/setholdingpriority(_:forsubviewat:)
    @MainActor open func setHoldingPriority(_ priority: NSLayoutConstraint.Priority, forSubviewAt subviewIndex: Int) {
        while _holdingPriorities.count <= subviewIndex { _holdingPriorities.append(NSLayoutConstraint.Priority(250)) }
        _holdingPriorities[subviewIndex] = priority
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/setposition(_:ofdividerat:)
    /// Moves a divider: the views on either side trade thickness.
    @MainActor open func setPosition(_ position: CGFloat, ofDividerAt dividerIndex: Int) {
        let views = arrangedSubviews
        guard dividerIndex >= 0, dividerIndex + 1 < views.count else { return }
        var p = max(minPossiblePositionOfDivider(at: dividerIndex), min(maxPossiblePositionOfDivider(at: dividerIndex), position))
        p = (_delegate?.splitView(self, constrainSplitPosition: p, ofSubviewAt: dividerIndex) ?? p).rounded()
        let before = views[dividerIndex], after = views[dividerIndex + 1]
        let start = dividerIndex > 0 ? _positions[dividerIndex - 1] + dividerThickness : 0
        let end = dividerIndex + 1 < _positions.count ? _positions[dividerIndex + 1] : _axisLength
        let beforeSize = p - start
        let afterSize = end - (p + dividerThickness)
        _collapsed.remove(ObjectIdentifier(before)); _collapsed.remove(ObjectIdentifier(after))
        before.isHidden = false; after.isHidden = false
        if _isVertical {
            before.setFrameSize(NSSize(width: beforeSize, height: bounds.height))
            after.setFrameSize(NSSize(width: max(0, afterSize), height: bounds.height))
        } else {
            before.setFrameSize(NSSize(width: bounds.width, height: beforeSize))
            after.setFrameSize(NSSize(width: bounds.width, height: max(0, afterSize)))
        }
        _layoutArranged(oldLength: nil)
        NotificationCenter.default.post(name: NSSplitView.didResizeSubviewsNotification, object: self, userInfo: ["NSSplitViewDividerIndex": dividerIndex])
        _delegate?.splitViewDidResizeSubviews(Notification(name: NSSplitView.didResizeSubviewsNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssplitview/willresizesubviewsnotification
    static public var willResizeSubviewsNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSSplitViewWillResizeSubviewsNotification") }
}
