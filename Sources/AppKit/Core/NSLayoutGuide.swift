// NSLayoutGuide (hand-written; seeded from the generated stub, see tools/apigen)
// A rectangular region in a view that constraints can refer to without a view.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutguide
@MainActor open class NSLayoutGuide: NSObject, NSCoding, NSUserInterfaceItemIdentification {
    private var _identifier = NSUserInterfaceItemIdentifier("")
    internal var _frame = NSRect.zero
    private var _anchors: [NSLayoutConstraint.Attribute: AnyObject] = [:]

    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init() }
    open func encode(with coder: NSCoder) {}

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutguide/owningview
    open internal(set) weak var owningView: NSView?

    /// The guide's rectangle in its owning view's coordinate system, set by layout.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutguide/frame
    open var frame: NSRect { _frame }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutguide/identifier
    open var identifier: NSUserInterfaceItemIdentifier {
        get { _identifier }
        set { _identifier = newValue }
    }

    private func xAnchor(_ a: NSLayoutConstraint.Attribute) -> NSLayoutXAxisAnchor {
        if let x = _anchors[a] as? NSLayoutXAxisAnchor { return x }
        let x = NSLayoutXAxisAnchor(item: self, attribute: a)
        _anchors[a] = x
        return x
    }
    private func yAnchor(_ a: NSLayoutConstraint.Attribute) -> NSLayoutYAxisAnchor {
        if let y = _anchors[a] as? NSLayoutYAxisAnchor { return y }
        let y = NSLayoutYAxisAnchor(item: self, attribute: a)
        _anchors[a] = y
        return y
    }
    private func dimension(_ a: NSLayoutConstraint.Attribute) -> NSLayoutDimension {
        if let d = _anchors[a] as? NSLayoutDimension { return d }
        let d = NSLayoutDimension(item: self, attribute: a)
        _anchors[a] = d
        return d
    }

    open var bottomAnchor: NSLayoutYAxisAnchor { yAnchor(.bottom) }
    open var centerXAnchor: NSLayoutXAxisAnchor { xAnchor(.centerX) }
    open var centerYAnchor: NSLayoutYAxisAnchor { yAnchor(.centerY) }
    open var heightAnchor: NSLayoutDimension { dimension(.height) }
    open var leadingAnchor: NSLayoutXAxisAnchor { xAnchor(.leading) }
    open var leftAnchor: NSLayoutXAxisAnchor { xAnchor(.left) }
    open var rightAnchor: NSLayoutXAxisAnchor { xAnchor(.right) }
    open var topAnchor: NSLayoutYAxisAnchor { yAnchor(.top) }
    open var trailingAnchor: NSLayoutXAxisAnchor { xAnchor(.trailing) }
    open var widthAnchor: NSLayoutDimension { dimension(.width) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutguide/constraintsaffectinglayout(for:)
    open func constraintsAffectingLayout(for orientation: NSLayoutConstraint.Orientation) -> [NSLayoutConstraint] {
        let horizontal: Set<NSLayoutConstraint.Attribute> = [.left, .right, .leading, .trailing, .width, .centerX]
        let attrs = orientation == .horizontal ? horizontal : Set([.top, .bottom, .height, .centerY, .firstBaseline, .lastBaseline])
        var out: [NSLayoutConstraint] = []
        var v = owningView
        while let cur = v {
            out += cur.constraints.filter { ($0.firstItem === self && attrs.contains($0.firstAttribute)) || ($0.secondItem === self && attrs.contains($0.secondAttribute)) }
            v = cur.superview
        }
        return out
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutguide/hasambiguouslayout
    open var hasAmbiguousLayout: Bool { false }
}
