// NSStackView (hand-written; seeded from the generated stub, see tools/apigen)
// Arranges views in a row or column by generating Auto Layout constraints (as AppKit
// does), so the arranged views can carry their own constraints too.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview
@MainActor open class NSStackView: NSView {
    private var _arranged: [NSView] = []
    private var _detached: [NSView] = []
    private var _gravity: [ObjectIdentifier: NSStackView.Gravity] = [:]
    private var _customSpacing: [ObjectIdentifier: CGFloat] = [:]
    private var _visibility: [ObjectIdentifier: NSStackView.VisibilityPriority] = [:]
    private var _orientation: NSUserInterfaceLayoutOrientation = .horizontal
    private var _alignment: NSLayoutConstraint.Attribute = .centerY
    private var _distribution: NSStackView.Distribution = .gravityAreas
    private var _spacing: CGFloat = 8
    private var _edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    private var _detachesHiddenViews = true
    private var _hugging: [NSLayoutConstraint.Orientation: NSLayoutConstraint.Priority] = [:]
    private var _clipping: [NSLayoutConstraint.Orientation: NSLayoutConstraint.Priority] = [:]
    private weak var _delegate: (any NSStackViewDelegate)? = nil
    private var _generated: [NSLayoutConstraint] = []
    private var _gapGuides: [NSLayoutGuide] = []

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/init(views:)
    @MainActor public convenience init(views: [NSView]) {
        self.init(frame: .zero)
        for v in views { addArrangedSubview(v) }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _alignment = .centerY
    }

    public required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: Arranged views

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/addarrangedsubview(_:)
    @MainActor open func addArrangedSubview(_ view: NSView) { insertArrangedSubview(view, at: _arranged.count) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/insertarrangedsubview(_:at:)
    @MainActor open func insertArrangedSubview(_ view: NSView, at index: Int) {
        _arranged.removeAll { $0 === view }
        _arranged.insert(view, at: min(index, _arranged.count))
        if _gravity[ObjectIdentifier(view)] == nil { _gravity[ObjectIdentifier(view)] = .leading }
        view.translatesAutoresizingMaskIntoConstraints = false
        if view.superview !== self { addSubview(view) }
        needsUpdateConstraints = true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/removearrangedsubview(_:)
    @MainActor open func removeArrangedSubview(_ view: NSView) {
        _arranged.removeAll { $0 === view }
        _detached.removeAll { $0 === view }
        _gravity[ObjectIdentifier(view)] = nil
        needsUpdateConstraints = true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/arrangedsubviews
    @MainActor open var arrangedSubviews: [NSView] { _arranged }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/addview(_:in:)
    @MainActor open func addView(_ view: NSView, in gravity: NSStackView.Gravity) {
        let last = _arranged.lastIndex { _gravity[ObjectIdentifier($0)]!.rawValue <= gravity.rawValue }
        _gravity[ObjectIdentifier(view)] = gravity
        insertArrangedSubview(view, at: last.map { $0 + 1 } ?? 0)
        _gravity[ObjectIdentifier(view)] = gravity
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/insertview(_:at:in:)
    @MainActor open func insertView(_ view: NSView, at index: Int, in gravity: NSStackView.Gravity) {
        let inGravity = _arranged.filter { _gravity[ObjectIdentifier($0)] == gravity }
        let anchor = index < inGravity.count ? _arranged.firstIndex { $0 === inGravity[index] }! : (_arranged.lastIndex { _gravity[ObjectIdentifier($0)]!.rawValue <= gravity.rawValue }.map { $0 + 1 } ?? 0)
        _gravity[ObjectIdentifier(view)] = gravity
        insertArrangedSubview(view, at: anchor)
        _gravity[ObjectIdentifier(view)] = gravity
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/removeview(_:)
    @MainActor open func removeView(_ view: NSView) {
        removeArrangedSubview(view)
        view.removeFromSuperview()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/setviews(_:in:)
    @MainActor open func setViews(_ views: [NSView], in gravity: NSStackView.Gravity) {
        for v in self.views(in: gravity) { removeView(v) }
        for v in views { addView(v, in: gravity) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/views
    @MainActor open var views: [NSView] { _arranged }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/views(in:)
    @MainActor open func views(in gravity: NSStackView.Gravity) -> [NSView] { _arranged.filter { _gravity[ObjectIdentifier($0)] == gravity } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/detachedviews
    @MainActor open var detachedViews: [NSView] { _detached }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/detacheshiddenviews
    @MainActor open var detachesHiddenViews: Bool {
        get { _detachesHiddenViews }
        set { _detachesHiddenViews = newValue; needsUpdateConstraints = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/visibilitypriority(for:)
    @MainActor open func visibilityPriority(for view: NSView) -> NSStackView.VisibilityPriority { _visibility[ObjectIdentifier(view)] ?? .mustHold }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/setvisibilitypriority(_:for:)
    @MainActor open func setVisibilityPriority(_ priority: NSStackView.VisibilityPriority, for view: NSView) {
        _visibility[ObjectIdentifier(view)] = priority
        needsUpdateConstraints = true
    }

    // MARK: Geometry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/orientation
    @MainActor open var orientation: NSUserInterfaceLayoutOrientation {
        get { _orientation }
        set {
            _orientation = newValue
            if newValue == .horizontal, [.leading, .trailing, .left, .right, .centerX, .width].contains(_alignment) { _alignment = .centerY }
            if newValue == .vertical, [.top, .bottom, .centerY, .height, .firstBaseline, .lastBaseline].contains(_alignment) { _alignment = .centerX }
            needsUpdateConstraints = true
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/alignment
    @MainActor open var alignment: NSLayoutConstraint.Attribute {
        get { _alignment }
        set { _alignment = newValue; needsUpdateConstraints = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/distribution
    @MainActor open var distribution: NSStackView.Distribution {
        get { _distribution }
        set { _distribution = newValue; needsUpdateConstraints = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/spacing
    @MainActor open var spacing: CGFloat {
        get { _spacing }
        set { _spacing = newValue; needsUpdateConstraints = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/usedefaultspacing
    static public var useDefaultSpacing: CGFloat { CGFloat.greatestFiniteMagnitude }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/customspacing(after:)
    @MainActor open func customSpacing(after view: NSView) -> CGFloat { _customSpacing[ObjectIdentifier(view)] ?? NSStackView.useDefaultSpacing }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/setcustomspacing(_:after:)
    @MainActor open func setCustomSpacing(_ spacing: CGFloat, after view: NSView) {
        _customSpacing[ObjectIdentifier(view)] = spacing == NSStackView.useDefaultSpacing ? nil : spacing
        needsUpdateConstraints = true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/edgeinsets
    @MainActor open var edgeInsets: NSEdgeInsets {
        get { _edgeInsets }
        set { _edgeInsets = newValue; needsUpdateConstraints = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/hasequalspacing
    @MainActor open var hasEqualSpacing: Bool {
        get { _distribution == .equalSpacing }
        set { _distribution = newValue ? .equalSpacing : .gravityAreas; needsUpdateConstraints = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/huggingpriority(for:)
    @MainActor open func huggingPriority(for orientation: NSLayoutConstraint.Orientation) -> NSLayoutConstraint.Priority { _hugging[orientation] ?? .defaultLow }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/sethuggingpriority(_:for:)
    @MainActor open func setHuggingPriority(_ huggingPriority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) {
        _hugging[orientation] = huggingPriority
        setContentHuggingPriority(huggingPriority, for: orientation)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/clippingresistancepriority(for:)
    @MainActor open func clippingResistancePriority(for orientation: NSLayoutConstraint.Orientation) -> NSLayoutConstraint.Priority { _clipping[orientation] ?? .required }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/setclippingresistancepriority(_:for:)
    @MainActor open func setClippingResistancePriority(_ clippingResistancePriority: NSLayoutConstraint.Priority, for orientation: NSLayoutConstraint.Orientation) {
        _clipping[orientation] = clippingResistancePriority
        needsUpdateConstraints = true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsstackview/delegate
    @MainActor open var delegate: (any NSStackViewDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }

    // MARK: Layout

    open override var isFlipped: Bool { true }

    /// Views that take part in the layout: hidden or low-visibility ones are detached.
    private var _visibleArranged: [NSView] {
        _arranged.filter { v in
            !(_detachesHiddenViews && v.isHidden) && visibilityPriority(for: v) != .notVisible
        }
    }

    internal override func _subviewDidChangeHidden(_ subview: NSView) {
        if _arranged.contains(where: { $0 === subview }) { needsUpdateConstraints = true }
    }

    @MainActor open override var intrinsicContentSize: NSSize {
        let views = _visibleArranged
        let horizontal = _orientation == .horizontal
        var along: CGFloat = 0, across: CGFloat = 0
        for (i, v) in views.enumerated() {
            let s = v.fittingSize
            let a = horizontal ? s.width : s.height
            let c = horizontal ? s.height : s.width
            along += a
            across = max(across, c)
            if i < views.count - 1 { along += _effectiveSpacing(after: v) }
        }
        along += horizontal ? _edgeInsets.left + _edgeInsets.right : _edgeInsets.top + _edgeInsets.bottom
        across += horizontal ? _edgeInsets.top + _edgeInsets.bottom : _edgeInsets.left + _edgeInsets.right
        if views.isEmpty { return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        return horizontal ? NSSize(width: along, height: across) : NSSize(width: across, height: along)
    }

    private func _effectiveSpacing(after v: NSView) -> CGFloat { _customSpacing[ObjectIdentifier(v)] ?? _spacing }

    /// Regenerates the internal constraints for the current arranged views.
    @MainActor open override func updateConstraints() {
        for c in _generated { removeConstraint(c) }
        _generated = []
        for g in _gapGuides { removeLayoutGuide(g) }
        _gapGuides = []
        let visible = _visibleArranged
        let newlyDetached = _arranged.filter { v in !visible.contains { $0 === v } && !_detached.contains { $0 === v } }
        let reattached = _detached.filter { v in visible.contains { $0 === v } }
        if !newlyDetached.isEmpty { _delegate?.stackView(self, willDetach: newlyDetached) }
        _detached = _arranged.filter { v in !visible.contains { $0 === v } }
        if !reattached.isEmpty { _delegate?.stackView(self, didReattach: reattached) }
        super.updateConstraints()
        guard !visible.isEmpty else { return }

        let horizontal = _orientation == .horizontal
        func leadingEdge(_ item: AnyObject) -> NSLayoutAnchor<AnyObject> { NSLayoutAnchor<AnyObject>(item: item, attribute: horizontal ? .leading : .top) }
        func trailingEdge(_ item: AnyObject) -> NSLayoutAnchor<AnyObject> { NSLayoutAnchor<AnyObject>(item: item, attribute: horizontal ? .trailing : .bottom) }
        func along(_ item: AnyObject) -> NSLayoutAnchor<AnyObject> { NSLayoutAnchor<AnyObject>(item: item, attribute: horizontal ? .width : .height) }
        func center(_ item: AnyObject) -> NSLayoutAnchor<AnyObject> { NSLayoutAnchor<AnyObject>(item: item, attribute: horizontal ? .centerX : .centerY) }
        func make(_ a: NSLayoutAnchor<AnyObject>, _ rel: NSLayoutConstraint.Relation, _ b: NSLayoutAnchor<AnyObject>?, multiplier: CGFloat = 1, constant: CGFloat = 0, priority: NSLayoutConstraint.Priority = .required) {
            let c = NSLayoutConstraint(firstAnchor: a, relation: rel, secondAnchor: b, multiplier: multiplier, constant: constant)
            c.priority = priority
            c._isInternal = true
            _generated.append(c)
            addConstraint(c)
        }
        let leadInset = horizontal ? _edgeInsets.left : _edgeInsets.top
        let trailInset = horizontal ? _edgeInsets.right : _edgeInsets.bottom
        let clipping = clippingResistancePriority(for: horizontal ? .horizontal : .vertical)

        // Chain along the axis.
        let gravityAreas = _distribution == .gravityAreas
        for (i, v) in visible.enumerated() {
            if i == 0 {
                let gravity = _gravity[ObjectIdentifier(v)] ?? .leading
                if gravityAreas && gravity != .leading {
                    make(leadingEdge(v), .greaterThanOrEqual, leadingEdge(self), constant: leadInset)
                } else {
                    make(leadingEdge(v), .equal, leadingEdge(self), constant: leadInset, priority: gravityAreas ? .required : clipping)
                }
            } else {
                let prev = visible[i - 1]
                let gap = _effectiveSpacing(after: prev)
                let prevGravity = _gravity[ObjectIdentifier(prev)] ?? .leading
                let gravity = _gravity[ObjectIdentifier(v)] ?? .leading
                switch _distribution {
                case .equalSpacing, .equalCentering:
                    let g = NSLayoutGuide()
                    addLayoutGuide(g)
                    _gapGuides.append(g)
                    make(leadingEdge(g), .equal, trailingEdge(prev))
                    make(trailingEdge(g), .equal, leadingEdge(v))
                    make(along(g), .greaterThanOrEqual, nil, constant: gap)
                    if let first = _gapGuides.first, first !== g { make(along(g), .equal, along(first)) }
                default:
                    if gravityAreas && prevGravity != gravity {
                        make(leadingEdge(v), .greaterThanOrEqual, trailingEdge(prev), constant: gap)
                    } else {
                        make(leadingEdge(v), .equal, trailingEdge(prev), constant: gap)
                    }
                }
            }
            if i == visible.count - 1 {
                let gravity = _gravity[ObjectIdentifier(v)] ?? .leading
                if gravityAreas && gravity != .trailing {
                    make(trailingEdge(self), .greaterThanOrEqual, trailingEdge(v), constant: trailInset)
                } else {
                    make(trailingEdge(self), .equal, trailingEdge(v), constant: trailInset, priority: gravityAreas ? .required : clipping)
                }
            }
            // Cross-axis alignment.
            let topInset = horizontal ? _edgeInsets.top : _edgeInsets.left
            let bottomInset = horizontal ? _edgeInsets.bottom : _edgeInsets.right
            let crossLead = NSLayoutAnchor<AnyObject>(item: self, attribute: horizontal ? .top : .leading)
            let crossTrail = NSLayoutAnchor<AnyObject>(item: self, attribute: horizontal ? .bottom : .trailing)
            make(NSLayoutAnchor<AnyObject>(item: v, attribute: horizontal ? .top : .leading), .greaterThanOrEqual, crossLead, constant: topInset)
            make(crossTrail, .greaterThanOrEqual, NSLayoutAnchor<AnyObject>(item: v, attribute: horizontal ? .bottom : .trailing), constant: bottomInset)
            switch _alignment {
            case .width, .height:
                make(NSLayoutAnchor<AnyObject>(item: v, attribute: horizontal ? .top : .leading), .equal, crossLead, constant: topInset)
                make(crossTrail, .equal, NSLayoutAnchor<AnyObject>(item: v, attribute: horizontal ? .bottom : .trailing), constant: bottomInset)
            case .top, .leading, .left:
                make(NSLayoutAnchor<AnyObject>(item: v, attribute: _alignment), .equal, NSLayoutAnchor<AnyObject>(item: self, attribute: _alignment), constant: topInset)
            case .bottom, .trailing, .right:
                make(NSLayoutAnchor<AnyObject>(item: self, attribute: _alignment), .equal, NSLayoutAnchor<AnyObject>(item: v, attribute: _alignment), constant: bottomInset)
            case .firstBaseline, .lastBaseline:
                if i > 0 { make(NSLayoutAnchor<AnyObject>(item: v, attribute: _alignment), .equal, NSLayoutAnchor<AnyObject>(item: visible[0], attribute: _alignment)) }
                else { make(NSLayoutAnchor<AnyObject>(item: v, attribute: .top), .equal, crossLead, constant: topInset, priority: .defaultLow) }
            default:
                make(NSLayoutAnchor<AnyObject>(item: v, attribute: horizontal ? .centerY : .centerX), .equal, NSLayoutAnchor<AnyObject>(item: self, attribute: horizontal ? .centerY : .centerX), constant: (topInset - bottomInset) / 2)
            }
        }

        // Distribution along the axis.
        switch _distribution {
        case .fillEqually:
            for v in visible.dropFirst() { make(along(v), .equal, along(visible[0])) }
        case .fillProportionally:
            let sizes = visible.map { horizontal ? $0.fittingSize.width : $0.fittingSize.height }
            for (i, v) in visible.enumerated().dropFirst() where sizes[0] > 0 {
                make(along(v), .equal, along(visible[0]), multiplier: sizes[i] / sizes[0], priority: .defaultHigh)
            }
        case .equalCentering:
            for (i, v) in visible.enumerated().dropFirst() {
                // Centres equally spaced: distance between consecutive centres is constant.
                if i >= 2 {
                    let g = NSLayoutGuide()
                    addLayoutGuide(g)
                    _gapGuides.append(g)
                    make(leadingEdge(g), .equal, center(visible[i - 1]))
                    make(trailingEdge(g), .equal, center(v))
                }
            }
        default:
            break
        }
    }
}
