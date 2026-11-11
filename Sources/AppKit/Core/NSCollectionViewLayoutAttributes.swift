// NSCollectionViewLayoutAttributes (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A value object: where one element (item, supplementary or decoration view, inter-item
// gap) goes and how it looks. Layouts make them in `prepare()` and hand them out; the
// collection view applies them to the element's view.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes
@available(macOS 10.11, *)
@MainActor open class NSCollectionViewLayoutAttributes: NSObject, NSCopying {
    private var _frame: NSRect = .zero
    private var _alpha: CGFloat = 1
    private var _zIndex = 0
    private var _isHidden = false
    private var _indexPath: IndexPath?
    private var _category: NSCollectionElementCategory = .item
    private var _kind: String?

    public required override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/init(fordecorationviewofkind:with:)
    @MainActor public convenience init(forDecorationViewOfKind decorationViewKind: NSCollectionView.DecorationElementKind, with indexPath: IndexPath) {
        self.init()
        _category = .decorationView
        _kind = decorationViewKind
        _indexPath = indexPath
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/init(forinteritemgapbefore:)
    @MainActor public convenience init(forInterItemGapBefore indexPath: IndexPath) {
        self.init()
        _category = .interItemGap
        _kind = NSCollectionView.elementKindInterItemGapIndicator
        _indexPath = indexPath
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/init(foritemwith:)
    @MainActor public convenience init(forItemWith indexPath: IndexPath) {
        self.init()
        _category = .item
        _indexPath = indexPath
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/init(forsupplementaryviewofkind:with:)
    @MainActor public convenience init(forSupplementaryViewOfKind elementKind: NSCollectionView.SupplementaryElementKind, with indexPath: IndexPath) {
        self.init()
        _category = .supplementaryView
        _kind = elementKind
        _indexPath = indexPath
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/alpha
    @MainActor open var alpha: CGFloat {
        get { _alpha }
        set { _alpha = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/frame
    @MainActor open var frame: NSRect {
        get { _frame }
        set { _frame = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/indexpath
    @MainActor open var indexPath: IndexPath? {
        get { _indexPath }
        set { _indexPath = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/ishidden
    @MainActor open var isHidden: Bool {
        get { _isHidden }
        set { _isHidden = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/representedelementcategory
    @MainActor open var representedElementCategory: NSCollectionElementCategory { _category }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/representedelementkind
    @MainActor open var representedElementKind: String? { _kind }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/size
    @MainActor open var size: NSSize {
        get { _frame.size }
        set { _frame.size = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutattributes/zindex
    @MainActor open var zIndex: Int {
        get { _zIndex }
        set { _zIndex = newValue }
    }

    /// Sets what the attributes stand for (the layouts construct through `layoutAttributesClass`).
    internal func _configure(category: NSCollectionElementCategory, kind: String?, indexPath: IndexPath) {
        _category = category
        _kind = kind
        _indexPath = indexPath
    }

    /// The key the collection view files an element's view under.
    internal var _elementKey: _NSCollectionElementKey? {
        guard let ip = _indexPath else { return nil }
        return _NSCollectionElementKey(category: _category, kind: _kind, indexPath: ip)
    }

    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        MainActor.assumeIsolated {
            let c = type(of: self).init()
            c._frame = _frame
            c._alpha = _alpha
            c._zIndex = _zIndex
            c._isHidden = _isHidden
            c._indexPath = _indexPath
            c._category = _category
            c._kind = _kind
            return c
        }
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSCollectionViewLayoutAttributes else { return false }
        return MainActor.assumeIsolated {
            o._frame == _frame && o._alpha == _alpha && o._zIndex == _zIndex && o._isHidden == _isHidden
                && o._indexPath == _indexPath && o._category == _category && o._kind == _kind
        }
    }
    open override var hash: Int {
        MainActor.assumeIsolated {
            var h = Hasher()
            h.combine(_indexPath)
            h.combine(_category)
            h.combine(_kind)
            return h.finalize()
        }
    }
}

/// Identifies one element of a collection view: its category, kind and index path.
internal struct _NSCollectionElementKey: Hashable {
    var category: NSCollectionElementCategory
    var kind: String?
    var indexPath: IndexPath
}
