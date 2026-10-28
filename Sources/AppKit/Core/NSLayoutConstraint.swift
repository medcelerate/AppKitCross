// NSLayoutConstraint (hand-written; seeded from the generated stub, see tools/apigen)
// A linear relation between two layout attributes. Activation installs the constraint
// on the closest common ancestor of its items; the layout engine (Layout/LayoutEngine.swift)
// collects active constraints from the view tree and solves them with Cassowary.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint
@MainActor open class NSLayoutConstraint: NSObject, NSAnimatablePropertyContainer {
    private var _constant: CGFloat
    private var _priority: NSLayoutConstraint.Priority = .required
    private var _identifier: String?
    private var _isActive = false
    private var _shouldBeArchived = false
    /// The view holding this constraint while active.
    internal weak var _holder: NSView?
    /// Set for constraints the engine creates itself (intrinsic sizes, stack views).
    internal var _isInternal = false

    public let firstAnchor: NSLayoutAnchor<AnyObject>
    public let secondAnchor: NSLayoutAnchor<AnyObject>?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/init(item:attribute:relatedby:toitem:attribute:multiplier:constant:)
    public convenience init(item view1: Any, attribute attr1: NSLayoutConstraint.Attribute, relatedBy relation: NSLayoutConstraint.Relation, toItem view2: Any?, attribute attr2: NSLayoutConstraint.Attribute, multiplier: CGFloat, constant c: CGFloat) {
        self.init(firstAnchor: NSLayoutAnchor<AnyObject>(item: view1 as AnyObject, attribute: attr1),
                  relation: relation,
                  secondAnchor: view2.map { NSLayoutAnchor<AnyObject>(item: $0 as AnyObject, attribute: attr2) },
                  multiplier: multiplier, constant: c)
    }

    internal init(firstAnchor: NSLayoutAnchor<AnyObject>, relation: NSLayoutConstraint.Relation, secondAnchor: NSLayoutAnchor<AnyObject>?, multiplier: CGFloat, constant: CGFloat) {
        self.firstAnchor = firstAnchor
        self.relation = relation
        self.secondAnchor = secondAnchor
        self.multiplier = multiplier
        _constant = constant
        super.init()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/activate(_:)
    public class func activate(_ constraints: [NSLayoutConstraint]) {
        for c in constraints { c.isActive = true }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/deactivate(_:)
    public class func deactivate(_ constraints: [NSLayoutConstraint]) {
        for c in constraints { c.isActive = false }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/constant
    open var constant: CGFloat {
        get { _constant }
        set {
            guard newValue != _constant else { return }
            _constant = newValue
            _holder?._setNeedsConstraintLayout()
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/firstattribute
    open var firstAttribute: NSLayoutConstraint.Attribute { firstAnchor.attribute }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/firstitem
    open var firstItem: AnyObject? { firstAnchor.item }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/identifier
    open var identifier: String? {
        get { _identifier }
        set { _identifier = newValue }
    }

    /// Activating adds the constraint to the closest common ancestor view of its items.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/isactive
    open var isActive: Bool {
        get { _isActive }
        set {
            guard newValue != _isActive else { return }
            if newValue {
                guard let holder = NSLayoutConstraint._commonHolder(firstItem, secondItem) else {
                    preconditionFailure("NSLayoutConstraint: cannot activate \(self): the items have no common ancestor view")
                }
                holder.addConstraint(self)
            } else if let h = _holder {
                h.removeConstraint(self)
            }
        }
    }

    internal func _setActiveFlag(_ flag: Bool, holder: NSView?) {
        _isActive = flag
        _holder = holder
    }

    /// The view that owns a constraint between `a` and `b` (views or layout guides).
    internal static func _commonHolder(_ a: AnyObject?, _ b: AnyObject?) -> NSView? {
        func view(of item: AnyObject?) -> NSView? {
            if let v = item as? NSView { return v }
            if let g = item as? NSLayoutGuide { return g.owningView }
            return nil
        }
        guard let va = view(of: a) else { return nil }
        guard let b, let vb = view(of: b) else { return va }
        if va === vb { return va }
        return va.ancestorShared(with: vb)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/multiplier
    public let multiplier: CGFloat
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/priority
    open var priority: NSLayoutConstraint.Priority {
        get { _priority }
        set { _priority = newValue; _holder?._setNeedsConstraintLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/relation
    public let relation: NSLayoutConstraint.Relation
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/secondattribute
    open var secondAttribute: NSLayoutConstraint.Attribute { secondAnchor?.attribute ?? .notAnAttribute }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/seconditem
    open var secondItem: AnyObject? { secondAnchor?.item }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/shouldbearchived
    open var shouldBeArchived: Bool {
        get { _shouldBeArchived }
        set { _shouldBeArchived = newValue }
    }

    private func _itemName(_ o: AnyObject?) -> String {
        guard let o else { return "nil" }
        if let v = o as? NSView { return "\(type(of: v))" }
        if let g = o as? NSLayoutGuide { return "NSLayoutGuide(\(g.identifier.rawValue))" }
        return "\(type(of: o))"
    }

    open override var description: String {
        MainActor.assumeIsolated {
            let name = _itemName
            let rel = relation == .equal ? "==" : relation == .lessThanOrEqual ? "<=" : ">="
            var s = "<NSLayoutConstraint \(name(firstItem)).\(firstAttribute) \(rel) "
            if let second = secondItem { s += "\(name(second)).\(secondAttribute)" + (multiplier != 1 ? " * \(multiplier)" : "") + (constant != 0 ? " + \(constant)" : "") }
            else { s += "\(constant)" }
            if priority != .required { s += " @\(priority.rawValue)" }
            return s + ">"
        }
    }

    // MARK: Visual format language

    /// Parses Apple's visual format language (`H:|-[a]-(>=8)-[b(==a@750)]-|`).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutconstraint/constraints(withvisualformat:options:metrics:views:)
    public class func constraints(withVisualFormat format: String, options opts: NSLayoutConstraint.FormatOptions = [], metrics: [String: Any]?, views: [String: Any]) -> [NSLayoutConstraint] {
        var parser = VisualFormatParser(format: format, options: opts, metrics: metrics ?? [:], views: views)
        return parser.parse()
    }

    @MainActor private struct VisualFormatParser {
        let chars: [Character]
        var i = 0
        let options: NSLayoutConstraint.FormatOptions
        let metrics: [String: Any]
        let views: [String: Any]
        var horizontal = true
        var result: [NSLayoutConstraint] = []

        init(format: String, options: NSLayoutConstraint.FormatOptions, metrics: [String: Any], views: [String: Any]) {
            chars = Array(format)
            self.options = options
            self.metrics = metrics
            self.views = views
        }

        private struct Predicate { var relation: NSLayoutConstraint.Relation; var constant: CGFloat; var view: AnyObject?; var priority: NSLayoutConstraint.Priority }
        private enum Element { case superview, view(AnyObject), spacing([Predicate]?) }

        private var peek: Character? { i < chars.count ? chars[i] : nil }
        private mutating func take() -> Character? { defer { i += 1 }; return peek }
        private mutating func takeIf(_ c: Character) -> Bool { if peek == c { i += 1; return true }; return false }

        mutating func parse() -> [NSLayoutConstraint] {
            if peek == "H", chars.count > 1, chars[1] == ":" { horizontal = true; i = 2 }
            else if peek == "V", chars.count > 1, chars[1] == ":" { horizontal = false; i = 2 }
            var elements: [Element] = []
            while let c = peek {
                switch c {
                case "|": i += 1; elements.append(.superview)
                case "[":
                    i += 1
                    let name = identifier()
                    guard let v = views[name] else { preconditionFailure("Visual format: unknown view '\(name)'") }
                    let obj = v as AnyObject
                    if takeIf("(") {
                        let preds = predicates()
                        _ = takeIf(")")
                        for p in preds { emitSize(obj, p) }
                    }
                    _ = takeIf("]")
                    elements.append(.view(obj))
                case "-":
                    i += 1
                    if takeIf("(") {
                        let preds = predicates()
                        _ = takeIf(")")
                        elements.append(.spacing(preds))
                    } else if let n = peek, n.isNumber || n.isLetter {
                        // Bare metric or number: "-8-" / "-pad-"
                        let v = number()
                        elements.append(.spacing([Predicate(relation: .equal, constant: v, view: nil, priority: .required)]))
                    } else {
                        elements.append(.spacing(nil))
                    }
                    _ = takeIf("-")
                default: i += 1
                }
            }
            connect(elements)
            return result
        }

        private mutating func identifier() -> String {
            var s = ""
            while let c = peek, c.isLetter || c.isNumber || c == "_" { s.append(c); i += 1 }
            return s
        }

        private mutating func number() -> CGFloat {
            var s = ""
            if let c = peek, c == "-" || c == "+" { s.append(c); i += 1 }
            while let c = peek, c.isNumber || c == "." { s.append(c); i += 1 }
            if let v = Double(s) { return CGFloat(v) }
            let name = s + identifier()
            if let m = metrics[name] {
                if let d = m as? Double { return CGFloat(d) }
                if let n = m as? NSNumber { return CGFloat(n.doubleValue) }
                if let f = m as? CGFloat { return f }
                if let x = m as? Int { return CGFloat(x) }
            }
            preconditionFailure("Visual format: unknown metric '\(name)'")
        }

        private mutating func predicates() -> [Predicate] {
            var out: [Predicate] = []
            repeat {
                var rel = NSLayoutConstraint.Relation.equal
                if takeIf("=") { _ = takeIf("="); rel = .equal }
                else if takeIf(">") { _ = takeIf("="); rel = .greaterThanOrEqual }
                else if takeIf("<") { _ = takeIf("="); rel = .lessThanOrEqual }
                var constant: CGFloat = 0
                var view: AnyObject? = nil
                if let c = peek, c.isNumber || c == "-" || c == "+" || c == "." {
                    constant = number()
                } else {
                    let name = identifier()
                    if let v = views[name] { view = v as AnyObject }
                    else if let m = metrics[name] { constant = (m as? NSNumber).map { CGFloat($0.doubleValue) } ?? (m as? CGFloat) ?? CGFloat((m as? Double) ?? 0) }
                }
                var priority = NSLayoutConstraint.Priority.required
                if takeIf("@") { priority = NSLayoutConstraint.Priority(Float(number())) }
                out.append(Predicate(relation: rel, constant: constant, view: view, priority: priority))
            } while takeIf(",")
            return out
        }

        private mutating func emitSize(_ obj: AnyObject, _ p: Predicate) {
            let attr: NSLayoutConstraint.Attribute = horizontal ? .width : .height
            let c = NSLayoutConstraint(item: obj, attribute: attr, relatedBy: p.relation, toItem: p.view, attribute: p.view == nil ? .notAnAttribute : attr, multiplier: 1, constant: p.constant)
            c.priority = p.priority
            result.append(c)
        }

        private mutating func connect(_ elements: [Element]) {
            let leading: NSLayoutConstraint.Attribute = horizontal ? (options.contains(.directionLeftToRight) ? .left : .leading) : .top
            let trailing: NSLayoutConstraint.Attribute = horizontal ? (options.contains(.directionLeftToRight) ? .right : .trailing) : .bottom
            var idx = 0
            var previous: Element? = nil
            var pendingSpacing: [Predicate]?? = nil   // nil: adjacent; .some(nil): default spacing; .some(preds)
            var hadSpacing = false
            var allViews: [AnyObject] = []
            while idx < elements.count {
                let el = elements[idx]
                idx += 1
                if case .spacing(let preds) = el { pendingSpacing = .some(preds); hadSpacing = true; continue }
                if case .view(let v) = el { allViews.append(v) }
                if let prev = previous {
                    var isEdge = false
                    if case .superview = prev { isEdge = true }
                    if case .superview = el { isEdge = true }
                    let defaultSpacing: CGFloat = isEdge ? 20 : 8
                    let preds: [Predicate] = hadSpacing ? ((pendingSpacing ?? nil) ?? [Predicate(relation: .equal, constant: defaultSpacing, view: nil, priority: .required)]) : [Predicate(relation: .equal, constant: 0, view: nil, priority: .required)]
                    for p in preds {
                        let c: NSLayoutConstraint
                        switch (prev, el) {
                        case (.superview, .view(let v)):
                            guard let sup = (v as? NSView)?.superview ?? (v as? NSLayoutGuide)?.owningView else { continue }
                            c = NSLayoutConstraint(item: v, attribute: leading, relatedBy: p.relation, toItem: sup, attribute: leading, multiplier: 1, constant: p.constant)
                        case (.view(let v), .superview):
                            guard let sup = (v as? NSView)?.superview ?? (v as? NSLayoutGuide)?.owningView else { continue }
                            c = NSLayoutConstraint(item: sup, attribute: trailing, relatedBy: p.relation, toItem: v, attribute: trailing, multiplier: 1, constant: p.constant)
                        case (.view(let a), .view(let b)):
                            c = NSLayoutConstraint(item: b, attribute: leading, relatedBy: p.relation, toItem: a, attribute: trailing, multiplier: 1, constant: p.constant)
                        default: continue
                        }
                        c.priority = p.priority
                        result.append(c)
                    }
                }
                previous = el
                pendingSpacing = nil
                hadSpacing = false
            }
            // Alignment options align every view in the format with the first one.
            let alignments: [(NSLayoutConstraint.FormatOptions, NSLayoutConstraint.Attribute)] = [
                (.alignAllLeft, .left), (.alignAllRight, .right), (.alignAllTop, .top), (.alignAllBottom, .bottom),
                (.alignAllLeading, .leading), (.alignAllTrailing, .trailing), (.alignAllCenterX, .centerX), (.alignAllCenterY, .centerY),
                (.alignAllLastBaseline, .lastBaseline), (.alignAllFirstBaseline, .firstBaseline),
            ]
            if allViews.count > 1 {
                for (opt, attr) in alignments where options.contains(opt) {
                    for v in allViews.dropFirst() {
                        result.append(NSLayoutConstraint(item: v, attribute: attr, relatedBy: .equal, toItem: allViews[0], attribute: attr, multiplier: 1, constant: 0))
                    }
                }
            }
        }
    }
}
