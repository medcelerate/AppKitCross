// NSLayoutAnchor, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor, NSLayoutDimension
// (hand-written; seeded from the generated stubs, see tools/apigen)
// Anchors are (item, attribute) pairs that build NSLayoutConstraints.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor
@MainActor open class NSLayoutAnchor<AnchorType>: NSObject, NSCopying, NSCoding where AnchorType: AnyObject {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/item
    open private(set) weak var item: AnyObject?
    public let attribute: NSLayoutConstraint.Attribute

    internal init(item: AnyObject, attribute: NSLayoutConstraint.Attribute) {
        self.item = item
        self.attribute = attribute
        super.init()
    }

    public required init?(coder: NSCoder) { return nil }
    open func encode(with coder: NSCoder) {}
    open func copy(with zone: NSZone? = nil) -> Any { self }

    /// The same anchor typed for constraint storage.
    internal var _erased: NSLayoutAnchor<AnyObject> {
        if let e = self as? NSLayoutAnchor<AnyObject> { return e }
        return NSLayoutAnchor<AnyObject>(item: item!, attribute: attribute)
    }

    internal func _make(_ relation: NSLayoutConstraint.Relation, _ other: NSLayoutAnchor<AnchorType>?, multiplier: CGFloat = 1, constant: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(firstAnchor: _erased, relation: relation, secondAnchor: other?._erased, multiplier: multiplier, constant: constant)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/constraint(equalto:)
    open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { _make(.equal, anchor) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/constraint(equalto:constant:)
    open func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { _make(.equal, anchor, constant: c) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/constraint(greaterthanorequalto:)
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { _make(.greaterThanOrEqual, anchor) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/constraint(greaterthanorequalto:constant:)
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { _make(.greaterThanOrEqual, anchor, constant: c) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/constraint(lessthanorequalto:)
    open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { _make(.lessThanOrEqual, anchor) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/constraint(lessthanorequalto:constant:)
    open func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { _make(.lessThanOrEqual, anchor, constant: c) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/constraintsaffectinglayout
    open var constraintsAffectingLayout: [NSLayoutConstraint] {
        guard let item else { return [] }
        let holder = (item as? NSView) ?? (item as? NSLayoutGuide)?.owningView
        var out: [NSLayoutConstraint] = []
        var v: NSView? = holder
        while let cur = v {
            out += cur.constraints.filter { ($0.firstItem === item && $0.firstAttribute == attribute) || ($0.secondItem === item && $0.secondAttribute == attribute) }
            v = cur.superview
        }
        return out
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/hasambiguouslayout
    open var hasAmbiguousLayout: Bool { false }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutanchor/name
    open var name: String { "\(attribute)" }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutxaxisanchor
@MainActor open class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutxaxisanchor/anchorwithoffset(to:)
    open func anchorWithOffset(to otherAnchor: NSLayoutXAxisAnchor) -> NSLayoutDimension {
        NSLayoutDimension(item: item!, attribute: attribute, offsetTo: otherAnchor)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutxaxisanchor/constraint(equaltosystemspacingafter:multiplier:)
    open func constraint(equalToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _make(.equal, anchor, constant: 8 * multiplier) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutxaxisanchor/constraint(greaterthanorequaltosystemspacingafter:multiplier:)
    open func constraint(greaterThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _make(.greaterThanOrEqual, anchor, constant: 8 * multiplier) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutxaxisanchor/constraint(lessthanorequaltosystemspacingafter:multiplier:)
    open func constraint(lessThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _make(.lessThanOrEqual, anchor, constant: 8 * multiplier) }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutyaxisanchor
@MainActor open class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutyaxisanchor/anchorwithoffset(to:)
    open func anchorWithOffset(to otherAnchor: NSLayoutYAxisAnchor) -> NSLayoutDimension {
        NSLayoutDimension(item: item!, attribute: attribute, offsetTo: otherAnchor)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutyaxisanchor/constraint(equaltosystemspacingbelow:multiplier:)
    open func constraint(equalToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _make(.equal, anchor, constant: 8 * multiplier) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutyaxisanchor/constraint(greaterthanorequaltosystemspacingbelow:multiplier:)
    open func constraint(greaterThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _make(.greaterThanOrEqual, anchor, constant: 8 * multiplier) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutyaxisanchor/constraint(lessthanorequaltosystemspacingbelow:multiplier:)
    open func constraint(lessThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint { _make(.lessThanOrEqual, anchor, constant: 8 * multiplier) }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension
@MainActor open class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    /// For `anchorWithOffset(to:)`: the dimension is `other - self` along the axis.
    internal var _offsetTarget: NSLayoutAnchor<AnyObject>?

    internal override init(item: AnyObject, attribute: NSLayoutConstraint.Attribute) {
        super.init(item: item, attribute: attribute)
    }

    internal init<T>(item: AnyObject, attribute: NSLayoutConstraint.Attribute, offsetTo other: NSLayoutAnchor<T>) {
        super.init(item: item, attribute: attribute)
        _offsetTarget = other._erased
    }

    public required init?(coder: NSCoder) { return nil }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(equalto:multiplier:)
    open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { _make(.equal, anchor, multiplier: m) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(equalto:multiplier:constant:)
    open func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { _make(.equal, anchor, multiplier: m, constant: c) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(equaltoconstant:)
    open func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { _make(.equal, nil, constant: c) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(greaterthanorequalto:multiplier:)
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { _make(.greaterThanOrEqual, anchor, multiplier: m) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(greaterthanorequalto:multiplier:constant:)
    open func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { _make(.greaterThanOrEqual, anchor, multiplier: m, constant: c) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(greaterthanorequaltoconstant:)
    open func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { _make(.greaterThanOrEqual, nil, constant: c) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(lessthanorequalto:multiplier:)
    open func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { _make(.lessThanOrEqual, anchor, multiplier: m) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(lessthanorequalto:multiplier:constant:)
    open func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { _make(.lessThanOrEqual, anchor, multiplier: m, constant: c) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutdimension/constraint(lessthanorequaltoconstant:)
    open func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { _make(.lessThanOrEqual, nil, constant: c) }

    internal override var _erased: NSLayoutAnchor<AnyObject> {
        let e = NSLayoutAnchor<AnyObject>(item: item!, attribute: attribute)
        e._offsetTarget = _offsetTarget
        return e
    }
}

private var erasedOffsetTargets: [ObjectIdentifier: NSLayoutAnchor<AnyObject>] = [:]

extension NSLayoutAnchor where AnchorType == AnyObject {
    internal var _offsetTarget: NSLayoutAnchor<AnyObject>? {
        get { erasedOffsetTargets[ObjectIdentifier(self)] }
        set { erasedOffsetTargets[ObjectIdentifier(self)] = newValue }
    }
}
