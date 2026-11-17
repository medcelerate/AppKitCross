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

/// Whether two rects share area. `NSRect.intersects` answers differently for rects that
/// only touch (Apple's says no, corelibs Foundation's yes); the layouts need Apple's
/// answer on every platform, so an element that ends where the visible rect starts is
/// not in it.
internal func _rectsOverlap(_ a: NSRect, _ b: NSRect) -> Bool {
    let i = a.intersection(b)
    return !i.isNull && i.width > 0 && i.height > 0
}

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

    // MARK: Drop targets (ADR-0041)
    //
    // The flow and grid layouts lay items out in lines. A point over an item targets the
    // item; anywhere else it targets the inter-item gap of the nearest line, before the
    // first item whose middle lies past the point (after the line's last item when none
    // does). Gap frames sit between the neighbours, one spacing wide before the first
    // item of a line and after the last, as AppKit's do.

    /// The items in layout order, per section (subclasses that lay out lines answer).
    internal var _lineItemAttributes: [[NSCollectionViewLayoutAttributes]] { [] }
    /// Each section's extent, when the layout keeps one (flow), to pick the section a
    /// point falls in; nil treats all the items as one run (grid).
    internal var _lineSectionFrames: [NSRect]? { nil }
    /// Whether lines run down (a horizontally scrolling flow) rather than across.
    internal var _linesRunVertically: Bool { false }
    /// The spacing between neighbours in a line of `section`.
    internal func _lineGapWidth(inSection section: Int) -> CGFloat { 10 }

    /// Rects in "line space": lines run along +x and stack along +y (mirrored for
    /// right-to-left, transposed for vertical lines). The mapping is its own inverse.
    private func _toLineSpace(_ r: NSRect) -> NSRect {
        if _linesRunVertically { return NSRect(x: r.minY, y: r.minX, width: r.height, height: r.width) }
        if _collectionView?.userInterfaceLayoutDirection == .rightToLeft { return NSRect(x: -r.maxX, y: r.minY, width: r.width, height: r.height) }
        return r
    }
    private func _toLineSpace(_ p: NSPoint) -> NSPoint { _toLineSpace(NSRect(origin: p, size: .zero)).origin }

    /// Groups visible items (already in order) into lines: an item starts a new line when
    /// it does not share the current line's band.
    private func _lines(_ items: [NSCollectionViewLayoutAttributes]) -> [[NSCollectionViewLayoutAttributes]] {
        var lines: [[NSCollectionViewLayoutAttributes]] = []
        var band: (lo: CGFloat, hi: CGFloat)? = nil
        for a in items where !a.isHidden {
            let r = _toLineSpace(a.frame)
            if let b = band, r.minY < b.hi, r.maxY > b.lo {
                lines[lines.count - 1].append(a)
                band = (min(b.lo, r.minY), max(b.hi, r.maxY))
            } else {
                lines.append([a])
                band = (r.minY, r.maxY)
            }
        }
        return lines
    }

    private func _gapAttributes(before indexPath: IndexPath, lineSpaceFrame: NSRect) -> NSCollectionViewLayoutAttributes {
        let a = NSCollectionViewLayoutAttributes(forInterItemGapBefore: indexPath)
        a.frame = _toLineSpace(lineSpaceFrame)
        return a
    }
    /// The gap attributes before item `k` of `line` (`k == line.count`: after the last).
    private func _gap(in line: [NSCollectionViewLayoutAttributes], at k: Int) -> NSCollectionViewLayoutAttributes? {
        guard let first = line.first, let fip = first.indexPath else { return nil }
        let spacing = _lineGapWidth(inSection: fip.section)
        if k < line.count {
            let cur = _toLineSpace(line[k].frame)
            guard let ip = line[k].indexPath else { return nil }
            if k == 0 { return _gapAttributes(before: ip, lineSpaceFrame: NSRect(x: cur.minX - spacing, y: cur.minY, width: spacing, height: cur.height)) }
            let prev = _toLineSpace(line[k - 1].frame)
            let lo = min(prev.maxX, cur.minX), hi = max(prev.maxX, cur.minX)
            return _gapAttributes(before: ip, lineSpaceFrame: NSRect(x: lo, y: min(prev.minY, cur.minY), width: hi - lo, height: max(prev.maxY, cur.maxY) - min(prev.minY, cur.minY)))
        }
        let last = line[line.count - 1]
        guard let lip = last.indexPath else { return nil }
        let r = _toLineSpace(last.frame)
        return _gapAttributes(before: IndexPath(item: lip.item + 1, section: lip.section), lineSpaceFrame: NSRect(x: r.maxX, y: r.minY, width: spacing, height: r.height))
    }

    /// `layoutAttributesForDropTarget(at:)` for a layout of lines.
    internal func _lineDropTarget(at point: NSPoint) -> NSCollectionViewLayoutAttributes? {
        let sections = _lineItemAttributes
        guard !sections.isEmpty else { return nil }
        for s in sections { for a in s where !a.isHidden && a.frame.contains(point) { return a } }
        // The section the point is in (or nearest to), else every item as one run.
        var items: [NSCollectionViewLayoutAttributes]
        var section = 0
        if let frames = _lineSectionFrames, frames.count == sections.count {
            let p = _toLineSpace(point)
            func distance(_ f: NSRect) -> CGFloat { let r = _toLineSpace(f); return p.y < r.minY ? r.minY - p.y : (p.y >= r.maxY ? p.y - r.maxY : 0) }
            section = frames.indices.min { distance(frames[$0]) < distance(frames[$1]) } ?? 0
            items = sections[section]
        } else {
            items = sections.flatMap { $0 }
        }
        let lines = _lines(items)
        guard !lines.isEmpty else {
            // An empty section: before its first item.
            let r = _lineSectionFrames.map { _toLineSpace($0[section]) } ?? .zero
            return _gapAttributes(before: IndexPath(item: 0, section: section), lineSpaceFrame: NSRect(x: r.minX, y: r.minY, width: _lineGapWidth(inSection: section), height: r.height))
        }
        let p = _toLineSpace(point)
        func distance(_ line: [NSCollectionViewLayoutAttributes]) -> CGFloat {
            let lo = line.map { _toLineSpace($0.frame).minY }.min()!, hi = line.map { _toLineSpace($0.frame).maxY }.max()!
            return p.y < lo ? lo - p.y : (p.y >= hi ? p.y - hi : 0)
        }
        let line = lines.min { distance($0) < distance($1) }!
        let k = line.firstIndex { _toLineSpace($0.frame).midX > p.x } ?? line.count
        return _gap(in: line, at: k)
    }

    /// `layoutAttributesForInterItemGap(before:)` for a layout of lines.
    internal func _lineInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        let sections = _lineItemAttributes
        guard indexPath.count == 2, sections.indices.contains(indexPath.section) else { return nil }
        let items = sections[indexPath.section]
        let lines = _lines(_lineSectionFrames == nil ? sections.flatMap { $0 } : items)
        for line in lines {
            if let k = line.firstIndex(where: { $0.indexPath == indexPath }) { return _gap(in: line, at: k) }
        }
        // One past the section's last laid-out item: the gap after it.
        guard indexPath.item > 0, indexPath.item <= items.count, indexPath.item == items.count || items[indexPath.item].isHidden else { return nil }
        let before = IndexPath(item: indexPath.item - 1, section: indexPath.section)
        guard let line = lines.first(where: { $0.last?.indexPath == before }) else { return nil }
        return _gap(in: line, at: line.count)
    }

    // MARK: Updates (ADR-0041)
    //
    // During a batch update the collection view tells the layout how old index paths map
    // to new ones and, for an animated update, the item attributes the old layout gave.
    // The flow and grid layouts answer the appearing/disappearing queries from them as
    // AppKit's do: an inserted item starts at its new frame transparent, a deleted one
    // ends at its old frame transparent, a surviving item travels from its old frame to
    // its new one. Outside an update both answer the current attributes, transparent.

    internal struct _UpdateContext {
        var oldToNew: [IndexPath: IndexPath] = [:]
        var newToOld: [IndexPath: IndexPath] = [:]
        var reloaded = Set<IndexPath>()              // new index paths of reloaded items
        var previous: [IndexPath: NSCollectionViewLayoutAttributes] = [:]   // by old index path
    }
    internal var _updateContext: _UpdateContext?

    private func _transparent(_ a: NSCollectionViewLayoutAttributes?, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let c = a?.copy() as? NSCollectionViewLayoutAttributes else { return nil }
        c.indexPath = indexPath
        c.alpha = 0
        return c
    }
    internal func _lineInitialAttributes(forAppearingItemAt indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let ctx = _updateContext else { return _transparent(layoutAttributesForItem(at: indexPath), at: indexPath) }
        if let old = ctx.newToOld[indexPath], !ctx.reloaded.contains(indexPath) {
            guard let c = (ctx.previous[old] ?? layoutAttributesForItem(at: indexPath))?.copy() as? NSCollectionViewLayoutAttributes else { return nil }
            c.indexPath = indexPath
            return c
        }
        return _transparent(layoutAttributesForItem(at: indexPath), at: indexPath)
    }
    internal func _lineFinalAttributes(forDisappearingItemAt indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let ctx = _updateContext else { return _transparent(layoutAttributesForItem(at: indexPath), at: indexPath) }
        if let new = ctx.oldToNew[indexPath], !ctx.reloaded.contains(new), let c = layoutAttributesForItem(at: new)?.copy() as? NSCollectionViewLayoutAttributes {
            c.indexPath = indexPath
            return c
        }
        return _transparent(ctx.previous[indexPath], at: indexPath)
    }

    // Requirement of NSCoding
    /// The base layout has no settings to archive (AppKit's writes no keys either).
    open func encode(with coder: NSCoder) { }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { super.init() }

    /// Keyed-archive helpers for the concrete layouts (AppKit stores sizes and insets as
    /// NSValues). A missing key leaves the default: corelibs' unarchiver aborts on reading one.
    internal static func _decodeSize(_ coder: NSCoder, _ key: String) -> NSSize? {
        coder.containsValue(forKey: key) ? (coder.decodeObject(forKey: key) as? NSValue)?.sizeValue : nil
    }
    internal static func _decodeInsets(_ coder: NSCoder, _ key: String) -> NSEdgeInsets? {
        guard coder.containsValue(forKey: key) else { return nil }
        if let v = coder.decodeObject(forKey: key) as? NSValue { return v.edgeInsetsValue }
        return nil
    }
    internal static func _decodeDouble(_ coder: NSCoder, _ key: String) -> CGFloat? {
        coder.containsValue(forKey: key) ? CGFloat(coder.decodeDouble(forKey: key)) : nil
    }
    internal static func _decodeInt(_ coder: NSCoder, _ key: String) -> Int? {
        coder.containsValue(forKey: key) ? coder.decodeInteger(forKey: key) : nil
    }
}
