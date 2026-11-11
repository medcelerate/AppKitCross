// NSCollectionViewLayoutInvalidationContext (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// What a layout invalidation covers: everything (the default `invalidateLayout()`), the
// data source counts, or particular elements. The collection view reads the flags when
// the layout hands the context back through `invalidateLayout(with:)`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext
@available(macOS 10.11, *)
@MainActor open class NSCollectionViewLayoutInvalidationContext: NSObject {
    internal var _invalidateEverything = false
    internal var _invalidateDataSourceCounts = false
    private var _items: Set<IndexPath>?
    private var _supplementary: [NSCollectionView.SupplementaryElementKind: Set<IndexPath>]?
    private var _decoration: [NSCollectionView.DecorationElementKind: Set<IndexPath>]?
    private var _offsetAdjustment: NSPoint = .zero
    private var _sizeAdjustment: NSSize = .zero

    public required override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/contentoffsetadjustment
    @MainActor open var contentOffsetAdjustment: NSPoint {
        get { _offsetAdjustment }
        set { _offsetAdjustment = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/contentsizeadjustment
    @MainActor open var contentSizeAdjustment: NSSize {
        get { _sizeAdjustment }
        set { _sizeAdjustment = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidatedatasourcecounts
    @MainActor open var invalidateDataSourceCounts: Bool { _invalidateDataSourceCounts }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidatedecorationelements(ofkind:at:)
    @MainActor open func invalidateDecorationElements(ofKind elementKind: NSCollectionView.DecorationElementKind, at indexPaths: Set<IndexPath>) {
        _decoration = _decoration ?? [:]
        _decoration![elementKind, default: []].formUnion(indexPaths)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidateeverything
    @MainActor open var invalidateEverything: Bool { _invalidateEverything }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidateitems(at:)
    @MainActor open func invalidateItems(at indexPaths: Set<IndexPath>) {
        _items = (_items ?? []).union(indexPaths)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidatesupplementaryelements(ofkind:at:)
    @MainActor open func invalidateSupplementaryElements(ofKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPaths: Set<IndexPath>) {
        _supplementary = _supplementary ?? [:]
        _supplementary![elementKind, default: []].formUnion(indexPaths)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidateddecorationindexpaths
    @MainActor open var invalidatedDecorationIndexPaths: [NSCollectionView.DecorationElementKind : Set<IndexPath>]? { _decoration }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidateditemindexpaths
    @MainActor open var invalidatedItemIndexPaths: Set<IndexPath>? { _items }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayoutinvalidationcontext/invalidatedsupplementaryindexpaths
    @MainActor open var invalidatedSupplementaryIndexPaths: [NSCollectionView.SupplementaryElementKind : Set<IndexPath>]? { _supplementary }

    /// Nothing in particular was named: the whole layout is stale.
    internal var _isWhole: Bool {
        _invalidateEverything || _invalidateDataSourceCounts || (_items == nil && _supplementary == nil && _decoration == nil)
    }
}
