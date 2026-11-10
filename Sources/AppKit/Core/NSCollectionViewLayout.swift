// NSCollectionViewLayout (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The base of the layout objects: an abstract class whose subclasses compute the frame
// of every element in `prepare()` and answer `layoutAttributesForElements(in:)`. The
// invalidation cycle: `invalidateLayout()` (or a context naming parts) tells the
// collection view, which calls `prepare()` again before it next places its views
// (ADR-0020).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout
@available(macOS 10.11, *)
@MainActor open class NSCollectionViewLayout: NSObject, NSCoding {
    internal weak var _collectionView: NSCollectionView?
    private var _decorationClasses: [NSCollectionView.DecorationElementKind: AnyClass] = [:]
    private var _decorationNibs: [NSCollectionView.DecorationElementKind: NSNib] = [:]

    public override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/collectionview
    @MainActor open var collectionView: NSCollectionView? { _collectionView }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/collectionviewcontentsize
    @MainActor open var collectionViewContentSize: NSSize { .zero }

    // MARK: Attributes

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforelements(in:)
    @MainActor open func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforitem(at:)
    @MainActor open func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforsupplementaryview(ofkind:at:)
    @MainActor open func layoutAttributesForSupplementaryView(ofKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesfordecorationview(ofkind:at:)
    @MainActor open func layoutAttributesForDecorationView(ofKind elementKind: NSCollectionView.DecorationElementKind, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesfordroptarget(at:)
    @MainActor open func layoutAttributesForDropTarget(at pointInCollectionView: NSPoint) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforinteritemgap(before:)
    @MainActor open func layoutAttributesForInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesclass
    @MainActor class public var layoutAttributesClass: AnyClass { NSCollectionViewLayoutAttributes.self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/invalidationcontextclass
    @MainActor class public var invalidationContextClass: AnyClass { NSCollectionViewLayoutInvalidationContext.self }

    /// A fresh attributes object of `layoutAttributesClass`, for subclasses.
    internal func _makeAttributes(forItemWith indexPath: IndexPath) -> NSCollectionViewLayoutAttributes {
        let a = (type(of: self).layoutAttributesClass as! NSCollectionViewLayoutAttributes.Type).init()
        a._configure(category: .item, kind: nil, indexPath: indexPath)
        return a
    }
    internal func _makeAttributes(forSupplementaryViewOfKind kind: NSCollectionView.SupplementaryElementKind, with indexPath: IndexPath) -> NSCollectionViewLayoutAttributes {
        let a = (type(of: self).layoutAttributesClass as! NSCollectionViewLayoutAttributes.Type).init()
        a._configure(category: .supplementaryView, kind: kind, indexPath: indexPath)
        return a
    }
    internal func _makeAttributes(forDecorationViewOfKind kind: NSCollectionView.DecorationElementKind, with indexPath: IndexPath) -> NSCollectionViewLayoutAttributes {
        let a = (type(of: self).layoutAttributesClass as! NSCollectionViewLayoutAttributes.Type).init()
        a._configure(category: .decorationView, kind: kind, indexPath: indexPath)
        return a
    }
    internal func _makeInvalidationContext() -> NSCollectionViewLayoutInvalidationContext {
        (type(of: self).invalidationContextClass as! NSCollectionViewLayoutInvalidationContext.Type).init()
    }

    // MARK: Preparing and invalidating

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/prepare()
    @MainActor open func prepare() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/invalidatelayout()
    @MainActor open func invalidateLayout() {
        let c = _makeInvalidationContext()
        c._invalidateEverything = true
        c._invalidateDataSourceCounts = true
        invalidateLayout(with: c)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/invalidatelayout(with:)
    @MainActor open func invalidateLayout(with context: NSCollectionViewLayoutInvalidationContext) {
        _collectionView?._layoutDidInvalidate(self, context: context)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/invalidationcontext(forboundschange:)
    @MainActor open func invalidationContext(forBoundsChange newBounds: NSRect) -> NSCollectionViewLayoutInvalidationContext {
        let c = _makeInvalidationContext()
        c._invalidateEverything = true
        return c
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/shouldinvalidatelayout(forboundschange:)
    @MainActor open func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/invalidationcontext(forpreferredlayoutattributes:withoriginalattributes:)
    @MainActor open func invalidationContext(forPreferredLayoutAttributes preferredAttributes: NSCollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: NSCollectionViewLayoutAttributes) -> NSCollectionViewLayoutInvalidationContext {
        let c = _makeInvalidationContext()
        if let ip = originalAttributes.indexPath {
            switch originalAttributes.representedElementCategory {
            case .item: c.invalidateItems(at: [ip])
            case .supplementaryView: c.invalidateSupplementaryElements(ofKind: originalAttributes.representedElementKind ?? "", at: [ip])
            case .decorationView: c.invalidateDecorationElements(ofKind: originalAttributes.representedElementKind ?? "", at: [ip])
            case .interItemGap: break
            }
        }
        return c
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/shouldinvalidatelayout(forpreferredlayoutattributes:withoriginalattributes:)
    @MainActor open func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: NSCollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: NSCollectionViewLayoutAttributes) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/targetcontentoffset(forproposedcontentoffset:)
    @MainActor open func targetContentOffset(forProposedContentOffset proposedContentOffset: NSPoint) -> NSPoint { proposedContentOffset }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/targetcontentoffset(forproposedcontentoffset:withscrollingvelocity:)
    @MainActor open func targetContentOffset(forProposedContentOffset proposedContentOffset: NSPoint, withScrollingVelocity velocity: NSPoint) -> NSPoint { proposedContentOffset }

    // MARK: Updates, bounds changes and transitions

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/prepare(forcollectionviewupdates:)
    @MainActor open func prepare(forCollectionViewUpdates updateItems: [NSCollectionViewUpdateItem]) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/finalizecollectionviewupdates()
    @MainActor open func finalizeCollectionViewUpdates() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/prepare(foranimatedboundschange:)
    @MainActor open func prepare(forAnimatedBoundsChange oldBounds: NSRect) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/finalizeanimatedboundschange()
    @MainActor open func finalizeAnimatedBoundsChange() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/preparefortransition(from:)
    @MainActor open func prepareForTransition(from oldLayout: NSCollectionViewLayout) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/preparefortransition(to:)
    @MainActor open func prepareForTransition(to newLayout: NSCollectionViewLayout) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/finalizelayouttransition()
    @MainActor open func finalizeLayoutTransition() { }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/initiallayoutattributesforappearingitem(at:)
    @MainActor open func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/finallayoutattributesfordisappearingitem(at:)
    @MainActor open func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/initiallayoutattributesforappearingsupplementaryelement(ofkind:at:)
    @MainActor open func initialLayoutAttributesForAppearingSupplementaryElement(ofKind elementKind: NSCollectionView.SupplementaryElementKind, at elementIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/finallayoutattributesfordisappearingsupplementaryelement(ofkind:at:)
    @MainActor open func finalLayoutAttributesForDisappearingSupplementaryElement(ofKind elementKind: NSCollectionView.SupplementaryElementKind, at elementIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/initiallayoutattributesforappearingdecorationelement(ofkind:at:)
    @MainActor open func initialLayoutAttributesForAppearingDecorationElement(ofKind elementKind: NSCollectionView.DecorationElementKind, at decorationIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/finallayoutattributesfordisappearingdecorationelement(ofkind:at:)
    @MainActor open func finalLayoutAttributesForDisappearingDecorationElement(ofKind elementKind: NSCollectionView.DecorationElementKind, at decorationIndexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/indexpathstodeleteforsupplementaryview(ofkind:)
    @MainActor open func indexPathsToDeleteForSupplementaryView(ofKind elementKind: NSCollectionView.SupplementaryElementKind) -> Set<IndexPath> { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/indexpathstodeletefordecorationview(ofkind:)
    @MainActor open func indexPathsToDeleteForDecorationView(ofKind elementKind: NSCollectionView.DecorationElementKind) -> Set<IndexPath> { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/indexpathstoinsertforsupplementaryview(ofkind:)
    @MainActor open func indexPathsToInsertForSupplementaryView(ofKind elementKind: NSCollectionView.SupplementaryElementKind) -> Set<IndexPath> { [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/indexpathstoinsertfordecorationview(ofkind:)
    @MainActor open func indexPathsToInsertForDecorationView(ofKind elementKind: NSCollectionView.DecorationElementKind) -> Set<IndexPath> { [] }

    // MARK: Decoration views

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/register(_:fordecorationviewofkind:)
    @MainActor open func register(_ viewClass: AnyClass?, forDecorationViewOfKind elementKind: NSCollectionView.DecorationElementKind) {
        _decorationClasses[elementKind] = viewClass
        _collectionView?._dropDecorationViews(ofKind: elementKind)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/register(_:fordecorationviewofkind:)
    @MainActor open func register(_ nib: NSNib?, forDecorationViewOfKind elementKind: NSCollectionView.DecorationElementKind) {
        _decorationNibs[elementKind] = nib
        _collectionView?._dropDecorationViews(ofKind: elementKind)
    }
    /// The class registered for a decoration kind, if any.
    internal func _decorationViewClass(ofKind kind: NSCollectionView.DecorationElementKind) -> AnyClass? { _decorationClasses[kind] }

    // MARK: Helpers for the concrete layouts

    /// The collection view's width and height available to the layout (the clip view's
    /// when it scrolls, else its own bounds).
    internal var _availableSize: NSSize {
        guard let cv = _collectionView else { return .zero }
        if let clip = cv.superview as? NSClipView { return clip.bounds.size }
        return cv.bounds.size
    }
    internal var _numberOfSections: Int { _collectionView?._sectionCount ?? 0 }
    internal func _numberOfItems(inSection s: Int) -> Int { _collectionView?._itemCount(inSection: s) ?? 0 }

    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { unimplemented() }
}
