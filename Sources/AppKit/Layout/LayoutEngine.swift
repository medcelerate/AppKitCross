// The Auto Layout engine: collects the active constraints of a view tree, adds the
// implicit ones (intrinsic content sizes, frames of views that translate their
// autoresizing mask, the root's size), solves them with Cassowary and writes the
// resulting frames back.
//
// Engine coordinates are the root view's bounds with y running downward (as AppKit's
// own engine), so `top` is always the smaller y and constants keep Apple's sign
// conventions regardless of each view's `isFlipped`.

import Foundation

@MainActor
final class LayoutEngine {
    /// Variables for one item (a view or a layout guide): engine-space frame.
    final class ItemVariables {
        let x = LayoutVariable("x"), y = LayoutVariable("y"), width = LayoutVariable("width"), height = LayoutVariable("height")
    }

    private var items: [ObjectIdentifier: ItemVariables] = [:]
    private var solver = LayoutSolver()
    private weak var root: NSView?

    init(root: NSView) { self.root = root }

    private func variables(for item: AnyObject) -> ItemVariables {
        let key = ObjectIdentifier(item)
        if let v = items[key] { return v }
        let v = ItemVariables()
        items[key] = v
        return v
    }

    /// Engine-space expression for an attribute of an item.
    private func expression(_ item: AnyObject, _ attribute: NSLayoutConstraint.Attribute) -> LayoutExpression {
        let v = variables(for: item)
        // Leading is the left edge in a left-to-right view and the right edge in a
        // right-to-left one (the item's own direction, inherited from its superview). In a
        // right-to-left layout the leading/trailing axis runs leftwards, so those
        // attributes are the negated edges: `a.leading == b.leading + 20` then puts `a`
        // 20 points inward from the right, and `b.leading == a.trailing + 8` puts `b`
        // to the left of `a`, as AppKit does.
        let rightToLeft = ((item as? NSView)?.userInterfaceLayoutDirection ?? (item as? NSLayoutGuide)?.owningView?.userInterfaceLayoutDirection) == .rightToLeft
        switch attribute {
        case .left: return LayoutExpression(v.x)
        case .right: return LayoutExpression(v.x) + LayoutExpression(v.width)
        case .leading: return rightToLeft ? LayoutExpression(v.x, -1) + LayoutExpression(v.width, -1) : LayoutExpression(v.x)
        case .trailing: return rightToLeft ? LayoutExpression(v.x, -1) : LayoutExpression(v.x) + LayoutExpression(v.width)
        case .top: return LayoutExpression(v.y)
        case .bottom: return LayoutExpression(v.y) + LayoutExpression(v.height)
        case .width: return LayoutExpression(v.width)
        case .height: return LayoutExpression(v.height)
        case .centerX: return LayoutExpression(v.x) + LayoutExpression(v.width, 0.5)
        case .centerY: return LayoutExpression(v.y) + LayoutExpression(v.height, 0.5)
        case .lastBaseline:
            let offset = (item as? NSView)?.baselineOffsetFromBottom ?? 0
            return LayoutExpression(v.y) + LayoutExpression(v.height) - Double(offset)
        case .firstBaseline:
            let offset = (item as? NSView)?.firstBaselineOffsetFromTop ?? 0
            return LayoutExpression(v.y) + Double(offset)
        case .notAnAttribute: return LayoutExpression(0)
        }
    }

    private func anchorExpression(_ anchor: NSLayoutAnchor<AnyObject>) -> LayoutExpression? {
        guard let item = anchor.item else { return nil }
        if let target = anchor._offsetTarget, let other = target.item {
            // anchorWithOffset(to:): the distance from this anchor to the other.
            return expression(other, target.attribute) - expression(item, anchor.attribute)
        }
        return expression(item, anchor.attribute)
    }

    static func strength(for priority: NSLayoutConstraint.Priority) -> Double {
        let p = Double(priority.rawValue)
        if p >= 1000 { return LayoutStrength.required }
        if p <= 0 { return 0 }
        return p * p * p / 1000
    }

    private func solverConstraint(for c: NSLayoutConstraint) -> LayoutSolverConstraint? {
        guard let first = anchorExpression(c.firstAnchor) else { return nil }
        var rhs = LayoutExpression(Double(c.constant))
        if let second = c.secondAnchor {
            guard let e = anchorExpression(second) else { return nil }
            rhs = e * Double(c.multiplier) + Double(c.constant)
        }
        let relation: LayoutRelation
        switch c.relation {
        case .equal: relation = .equal
        case .lessThanOrEqual: relation = .lessOrEqual
        case .greaterThanOrEqual: relation = .greaterOrEqual
        }
        return LayoutSolverConstraint(first - rhs, relation, strength: LayoutEngine.strength(for: c.priority))
    }

    /// Engine-space frame of a view from its current frame (for views the engine does not size).
    private func engineFrame(of view: NSView, root: NSView) -> NSRect {
        if view === root { return NSRect(origin: .zero, size: root.bounds.size) }
        // Convert the view's frame (superview coordinates) into root coordinates, then flip
        // so y runs downward from the root's top.
        let r = view.superview!.convert(view.frame, to: root)
        let rb = root.bounds
        let y = root.isFlipped ? r.minY - rb.minY : rb.maxY - r.maxY
        return NSRect(x: r.minX - rb.minX, y: y, width: r.width, height: r.height)
    }

    /// Converts an engine-space rect into a frame for `view` in its superview's coordinates.
    private func frame(fromEngine e: NSRect, for view: NSView, root: NSView) -> NSRect {
        let rb = root.bounds
        let rootRect = NSRect(x: e.minX + rb.minX, y: root.isFlipped ? e.minY + rb.minY : rb.maxY - e.maxY, width: e.width, height: e.height)
        guard let sup = view.superview else { return rootRect }
        return root.convert(rootRect, to: sup)
    }

    private func guideFrame(fromEngine e: NSRect, for guide: NSLayoutGuide, root: NSView) -> NSRect {
        let rb = root.bounds
        let rootRect = NSRect(x: e.minX + rb.minX, y: root.isFlipped ? e.minY + rb.minY : rb.maxY - e.maxY, width: e.width, height: e.height)
        guard let owner = guide.owningView else { return rootRect }
        return root.convert(rootRect, to: owner)
    }

    /// Solves the subtree rooted at `root` and applies frames. `fittingRoot` leaves the
    /// root's size free (used by `fittingSize`); returns the root's engine size.
    @discardableResult
    func solve(root: NSView, fittingRoot: Bool = false, apply: Bool = true) -> NSSize {
        solver = LayoutSolver()
        items = [:]
        var constrainedViews: [NSView] = []
        var guides: [NSLayoutGuide] = []
        var solverConstraints: [LayoutSolverConstraint] = []

        func add(_ e: LayoutExpression, _ rel: LayoutRelation, _ strength: Double) {
            solverConstraints.append(LayoutSolverConstraint(e, rel, strength: strength))
        }

        func addIntrinsic(_ view: NSView, _ v: ItemVariables) {
            let intrinsic = view.intrinsicContentSize
            if intrinsic.width != NSView.noIntrinsicMetric {
                let w = Double(intrinsic.width)
                add(LayoutExpression(v.width) - w, .lessOrEqual, LayoutEngine.strength(for: view.contentHuggingPriority(for: .horizontal)))
                add(LayoutExpression(v.width) - w, .greaterOrEqual, LayoutEngine.strength(for: view.contentCompressionResistancePriority(for: .horizontal)))
            }
            if intrinsic.height != NSView.noIntrinsicMetric {
                let h = Double(intrinsic.height)
                add(LayoutExpression(v.height) - h, .lessOrEqual, LayoutEngine.strength(for: view.contentHuggingPriority(for: .vertical)))
                add(LayoutExpression(v.height) - h, .greaterOrEqual, LayoutEngine.strength(for: view.contentCompressionResistancePriority(for: .vertical)))
            }
        }

        func visit(_ view: NSView) {
            let v = variables(for: view)
            if view === root {
                let size = root.bounds.size
                add(LayoutExpression(v.x), .equal, LayoutStrength.required)
                add(LayoutExpression(v.y), .equal, LayoutStrength.required)
                if fittingRoot {
                    // Prefer the smallest size that satisfies everything (compression at 50),
                    // honouring the root's own intrinsic size.
                    add(LayoutExpression(v.width), .equal, LayoutEngine.strength(for: .fittingSizeCompression))
                    add(LayoutExpression(v.height), .equal, LayoutEngine.strength(for: .fittingSizeCompression))
                    add(LayoutExpression(v.width), .greaterOrEqual, LayoutStrength.required)
                    add(LayoutExpression(v.height), .greaterOrEqual, LayoutStrength.required)
                    addIntrinsic(view, v)
                } else {
                    add(LayoutExpression(v.width) - Double(size.width), .equal, LayoutStrength.required)
                    add(LayoutExpression(v.height) - Double(size.height), .equal, LayoutStrength.required)
                }
            } else if view.translatesAutoresizingMaskIntoConstraints {
                // The frame is an input: pin it (required), as AppKit's autoresizing constraints do.
                let f = engineFrame(of: view, root: root)
                add(LayoutExpression(v.x) - Double(f.minX), .equal, LayoutStrength.required)
                add(LayoutExpression(v.y) - Double(f.minY), .equal, LayoutStrength.required)
                add(LayoutExpression(v.width) - Double(f.width), .equal, LayoutStrength.required)
                add(LayoutExpression(v.height) - Double(f.height), .equal, LayoutStrength.required)
            } else {
                constrainedViews.append(view)
                add(LayoutExpression(v.width), .greaterOrEqual, LayoutStrength.required)
                add(LayoutExpression(v.height), .greaterOrEqual, LayoutStrength.required)
                addIntrinsic(view, v)
                // A weak preference for the current position keeps underdetermined layouts stable.
                let f = engineFrame(of: view, root: root)
                add(LayoutExpression(v.x) - Double(f.minX), .equal, LayoutStrength.weak)
                add(LayoutExpression(v.y) - Double(f.minY), .equal, LayoutStrength.weak)
            }
            for g in view.layoutGuides {
                guides.append(g)
                let gv = variables(for: g)
                add(LayoutExpression(gv.width), .greaterOrEqual, LayoutStrength.required)
                add(LayoutExpression(gv.height), .greaterOrEqual, LayoutStrength.required)
            }
            for c in view._allConstraints {
                if let sc = solverConstraint(for: c) { solverConstraints.append(sc) }
            }
            for s in view.subviews { visit(s) }
        }
        visit(root)

        for sc in solverConstraints {
            do { try solver.addConstraint(sc) } catch {
                // Unsatisfiable or duplicate: AppKit logs and drops one; do the same.
                NSLog("Unable to simultaneously satisfy constraints; dropping \(sc.expression) \(sc.relation)")
            }
        }
        solver.updateVariables()

        let rv = variables(for: root)
        let rootSize = NSSize(width: CGFloat(rv.width.value), height: CGFloat(rv.height.value))
        guard apply else { return rootSize }

        for view in constrainedViews {
            let v = variables(for: view)
            let e = NSRect(x: CGFloat(v.x.value), y: CGFloat(v.y.value), width: CGFloat(v.width.value), height: CGFloat(v.height.value))
            let f = frame(fromEngine: e, for: view, root: root)
            view._applyLayoutFrame(NSRect(x: f.minX.rounded(), y: f.minY.rounded(), width: f.width.rounded(), height: f.height.rounded()))
        }
        for g in guides {
            let v = variables(for: g)
            let e = NSRect(x: CGFloat(v.x.value), y: CGFloat(v.y.value), width: CGFloat(v.width.value), height: CGFloat(v.height.value))
            g._frame = guideFrame(fromEngine: e, for: g, root: root)
        }
        return rootSize
    }
}
