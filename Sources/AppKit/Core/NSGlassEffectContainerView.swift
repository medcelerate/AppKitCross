// NSGlassEffectContainerView (hand-written; seeded from the generated stub, see tools/apigen)
// Liquid Glass (ADR-0052): a container whose glass views draw as one group. Glass views
// closer to each other than `spacing` (or sharing a `glassEffectUnion` identifier) merge:
// the container draws one capsule around them and the members draw no surface of their
// own. The merge is geometric; macOS's animated morph between the separate and merged
// shapes is not drawn (ADR Consequences).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview
@MainActor open class NSGlassEffectContainerView: NSView {
    private var _contentView: NSView?
    private var _spacing: CGFloat = 0
    /// The merge groups of the last layout, in container coordinates.
    internal private(set) var _groups: [_MergeGroup] = []

    internal struct _MergeGroup {
        var members: [NSGlassEffectView]
        var rect: NSRect
        var cornerRadius: CGFloat
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview/contentview
    @MainActor open var contentView: NSView? {
        get { _contentView }
        set {
            guard newValue !== _contentView else { return }
            _contentView?.removeFromSuperview()
            _contentView = newValue
            if let v = newValue {
                v.frame = bounds
                v.autoresizingMask = [.width, .height]
                addSubview(v)
            }
            needsLayout = true
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview/spacing
    /// How close two glass views in the container may be before their surfaces merge
    /// into one shape.
    @MainActor open var spacing: CGFloat {
        get { _spacing }
        set { _spacing = max(0, newValue); needsLayout = true; needsDisplay = true }
    }

    open override var isOpaque: Bool { false }

    /// The glass views in the container, in paint order.
    internal var _glassViews: [NSGlassEffectView] {
        var found: [NSGlassEffectView] = []
        func visit(_ v: NSView) {
            if let g = v as? NSGlassEffectView { found.append(g); return }
            for s in v.subviews { visit(s) }
        }
        for s in subviews { visit(s) }
        return found
    }

    open override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        needsLayout = true
    }
    open override func willRemoveSubview(_ subview: NSView) {
        super.willRemoveSubview(subview)
        needsLayout = true
    }
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    open override func layout() {
        super.layout()
        _regroup()
    }

    /// Finds the groups: glass views whose frames, grown by half the spacing, touch, or
    /// that share a union identifier (transitively); a group of one draws itself.
    internal func _regroup() {
        let views = _LiquidGlass.isEnabled ? _glassViews : []
        let frames = views.map { convert($0.bounds, from: $0) }
        var parent = Array(0..<views.count)
        func root(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        let grow = _spacing / 2
        for i in 0..<views.count {
            for j in (i + 1)..<max(i + 1, views.count) {
                let near = _spacing > 0 && frames[i].insetBy(dx: -grow, dy: -grow).intersects(frames[j].insetBy(dx: -grow, dy: -grow))
                let union = views[i]._unionID != nil && views[i]._unionID == views[j]._unionID
                if near || union { parent[root(j)] = root(i) }
            }
        }
        var byRoot: [Int: [Int]] = [:]
        for i in 0..<views.count { byRoot[root(i), default: []].append(i) }
        var groups: [_MergeGroup] = []
        for indices in byRoot.values.sorted(by: { $0[0] < $1[0] }) where indices.count > 1 {
            var rect = NSRect.null
            var radius = CGFloat.greatestFiniteMagnitude
            for i in indices {
                rect = rect.union(frames[i])
                let v = views[i]
                let own = v._shapePath == nil ? v._effectiveCornerRadius(in: v.bounds) : min(v.bounds.width, v.bounds.height) / 2
                radius = min(radius, own)
            }
            groups.append(_MergeGroup(members: indices.map { views[$0] }, rect: rect, cornerRadius: min(radius, rect.width / 2, rect.height / 2)))
        }
        let merged = Set(groups.flatMap { $0.members.map(ObjectIdentifier.init) })
        for v in views { v._surfaceDrawnByContainer = merged.contains(ObjectIdentifier(v)) }
        let changed = groups.count != _groups.count || zip(groups, _groups).contains { $0.rect != $1.rect || $0.members.map(ObjectIdentifier.init) != $1.members.map(ObjectIdentifier.init) }
        _groups = groups
        if changed { needsDisplay = true }
    }

    open override func draw(_ dirtyRect: NSRect) {
        guard _LiquidGlass.isEnabled, !_groups.isEmpty else {
            // Off: the members draw their own flat tints.
            return
        }
        for (slot, group) in _groups.enumerated() {
            guard let first = group.members.first else { continue }
            var spec = _GlassSpec.lens(clear: first.style == .clear, in: self)
            spec.tint = first.tintColor
            if group.members.contains(where: { $0._isInteractive }) {
                spec.brighten = group.members.contains(where: { $0._isPressed }) ? 0.2 : (group.members.contains(where: { $0._isHovered }) ? 0.1 : 0)
            }
            let r = group.cornerRadius
            let path = r > 0 ? NSBezierPath(roundedRect: group.rect, xRadius: r, yRadius: r) : NSBezierPath(rect: group.rect)
            _GlassRenderer.draw(spec, path: path, outline: .roundedRect(r), in: group.rect, of: self, slot: slot)
        }
    }
}
