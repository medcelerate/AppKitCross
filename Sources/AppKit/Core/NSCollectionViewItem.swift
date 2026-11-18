// NSCollectionViewItem (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The view controller behind one item of a collection view. The collection view sets
// `isSelected` and `highlightState`; a subclass redraws its view from them (as on
// macOS, the item draws no selection of its own). Items are reused: when one scrolls
// out, `prepareForReuse()` resets its state and the collection view hands it back from
// `makeItem(withIdentifier:for:)`.
//
// `init(nibName:bundle:)` is `required` here, where AppKit's is not: the port has no
// Objective-C runtime to instantiate a registered class with, so `register(_:forItemWithIdentifier:)`
// constructs items through this initializer (ADR-0020).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewitem
@MainActor open class NSCollectionViewItem: NSViewController, NSCopying, NSCollectionViewElement {
    internal weak var _collectionView: NSCollectionView?
    internal var _reuseIdentifier: NSUserInterfaceItemIdentifier?
    internal var _accessibilityLabelIsOurs = false
    private var _isSelected = false
    private var _highlightState: NSCollectionViewItem.HighlightState = .none
    private var _imageView: NSImageView?
    private var _textField: NSTextField?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsviewcontroller/init(nibname:bundle:)
    @MainActor public required override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewitem/collectionview
    @MainActor open var collectionView: NSCollectionView? { _collectionView }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewitem/isselected
    @MainActor open var isSelected: Bool {
        get { _isSelected }
        set {
            guard _isSelected != newValue else { return }
            _isSelected = newValue
            if let v = viewIfLoaded { v.needsDisplay = true }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewitem/highlightstate
    @available(macOS 10.11, *)
    @MainActor open var highlightState: NSCollectionViewItem.HighlightState {
        get { _highlightState }
        set {
            guard _highlightState != newValue else { return }
            _highlightState = newValue
            if let v = viewIfLoaded { v.needsDisplay = true }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewitem/imageview
    @MainActor open var imageView: NSImageView? {
        get { _imageView }
        set { _imageView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewitem/textfield
    @MainActor open var textField: NSTextField? {
        get { _textField }
        set { _textField = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewitem/draggingimagecomponents
    ///
    /// As AppKit's: a component of the image view (keyed `.icon`) and one of the text field
    /// (`.label`, or `.icon` when there is no image view), each a snapshot of that view at
    /// its frame in the item's view measured from the bottom-left; with neither, one `.icon`
    /// of the whole view (ADR-0041).
    @MainActor open var draggingImageComponents: [NSDraggingImageComponent] {
        let root = view
        var out: [NSDraggingImageComponent] = []
        func add(_ v: NSView) {
            guard v === root || v.isDescendant(of: root) else { return }
            let c = NSDraggingImageComponent(key: out.isEmpty ? .icon : .label)
            var f = v === root ? root.bounds : root.convert(v.bounds, from: v)
            if root.isFlipped { f.origin.y = root.bounds.height - f.maxY }
            c.frame = f
            c.contents = _NSCollectionViewDragImages.snapshot(of: v)
            out.append(c)
        }
        if let iv = imageView { add(iv) }
        if let tf = textField { add(tf) }
        if out.isEmpty { add(root) }
        return out
    }

    // MARK: NSCollectionViewElement

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewelement/prepareforreuse()
    @MainActor open func prepareForReuse() {
        isSelected = false
        highlightState = .none
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewelement/apply(_:)
    @MainActor open func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewelement/preferredlayoutattributesfitting(_:)
    @MainActor open func preferredLayoutAttributesFitting(_ layoutAttributes: NSCollectionViewLayoutAttributes) -> NSCollectionViewLayoutAttributes { layoutAttributes }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewelement/willtransition(from:to:)
    @MainActor open func willTransition(from oldLayout: NSCollectionViewLayout, to newLayout: NSCollectionViewLayout) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewelement/didtransition(from:to:)
    @MainActor open func didTransition(from oldLayout: NSCollectionViewLayout, to newLayout: NSCollectionViewLayout) { }

    // Requirement of NSCopying (the legacy `itemPrototype` path)
    /// A new item of the same class and nib with the same represented object. AppKit
    /// copies the view by archiving it; the port cannot archive views, so the copy loads
    /// its own view (`loadView()`, as a subclass building its view in code does) at the
    /// original view's size (ADR-0041).
    open func copy(with zone: NSZone? = nil) -> Any {
        MainActor.assumeIsolated {
            let c = type(of: self).init(nibName: nibName, bundle: nibBundle)
            c.representedObject = representedObject
            if let v = viewIfLoaded {
                let size = v.frame.size
                if c.view.frame.size == .zero { c.view.setFrameSize(size) }
            }
            return c
        }
    }
    // SKIPPED (Foundation.NSExtensionContext not in corelibs): func beginRequest(with context: NSExtensionContext)
}
