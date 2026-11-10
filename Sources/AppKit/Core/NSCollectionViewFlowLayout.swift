// NSCollectionViewFlowLayout (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Lines of items that wrap at the collection view's width (vertical scrolling) or
// height (horizontal), one run of lines per section between its header and footer,
// inside the section's insets. Items start at the leading edge of a line with the
// minimum inter-item spacing between them, as AppKit's flow layout places them; the
// `NSCollectionViewDelegateFlowLayout` methods override the sizes and spacings per
// section and per item. Headers and footers can pin to the visible bounds; sections
// can collapse to their header.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout
@available(macOS 10.11, *)
@MainActor open class NSCollectionViewFlowLayout: NSCollectionViewLayout {
    private var _itemSize = NSSize(width: 50, height: 50)
    private var _estimatedItemSize: NSSize = .zero
    private var _minimumLineSpacing: CGFloat = 10
    private var _minimumInteritemSpacing: CGFloat = 10
    private var _scrollDirection: NSCollectionView.ScrollDirection = .vertical
    private var _sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    private var _headerReferenceSize: NSSize = .zero
    private var _footerReferenceSize: NSSize = .zero
    private var _headersPin = false
    private var _footersPin = false
    private var _collapsed = IndexSet()

    /// One prepared section: the header, the items and the footer, plus the span the
    /// section covers along the scrolling axis (for pinning).
    private struct _Section {
        var header: NSCollectionViewLayoutAttributes?
        var footer: NSCollectionViewLayoutAttributes?
        var items: [NSCollectionViewLayoutAttributes] = []
        var frame: NSRect = .zero
    }
    private var _sections: [_Section] = []
    private var _contentSize: NSSize = .zero

    public override init() { super.init() }
    public required init?(coder: NSCoder) { unimplemented() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/invalidationcontextclass
    @MainActor open override class var invalidationContextClass: AnyClass { NSCollectionViewFlowLayoutInvalidationContext.self }

    // MARK: Metrics

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/itemsize
    @MainActor open var itemSize: NSSize {
        get { _itemSize }
        set { _itemSize = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/estimateditemsize
    @MainActor open var estimatedItemSize: NSSize {
        get { _estimatedItemSize }
        set { _estimatedItemSize = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/minimumlinespacing
    @MainActor open var minimumLineSpacing: CGFloat {
        get { _minimumLineSpacing }
        set { _minimumLineSpacing = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/minimuminteritemspacing
    @MainActor open var minimumInteritemSpacing: CGFloat {
        get { _minimumInteritemSpacing }
        set { _minimumInteritemSpacing = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/scrolldirection
    @MainActor open var scrollDirection: NSCollectionView.ScrollDirection {
        get { _scrollDirection }
        set { _scrollDirection = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/sectioninset
    @MainActor open var sectionInset: NSEdgeInsets {
        get { _sectionInset }
        set { _sectionInset = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/headerreferencesize
    @MainActor open var headerReferenceSize: NSSize {
        get { _headerReferenceSize }
        set { _headerReferenceSize = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/footerreferencesize
    @MainActor open var footerReferenceSize: NSSize {
        get { _footerReferenceSize }
        set { _footerReferenceSize = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/sectionheaderspintovisiblebounds
    @available(macOS 10.12, *)
    @MainActor open var sectionHeadersPinToVisibleBounds: Bool {
        get { _headersPin }
        set { _headersPin = newValue; _collectionView?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/sectionfooterspintovisiblebounds
    @available(macOS 10.12, *)
    @MainActor open var sectionFootersPinToVisibleBounds: Bool {
        get { _footersPin }
        set { _footersPin = newValue; _collectionView?.needsDisplay = true }
    }

    // MARK: Collapsing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/collapsesection(at:)
    @available(macOS 10.12, *)
    @MainActor open func collapseSection(at sectionIndex: Int) {
        guard !_collapsed.contains(sectionIndex) else { return }
        _collapsed.insert(sectionIndex)
        invalidateLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/expandsection(at:)
    @available(macOS 10.12, *)
    @MainActor open func expandSection(at sectionIndex: Int) {
        guard _collapsed.contains(sectionIndex) else { return }
        _collapsed.remove(sectionIndex)
        invalidateLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewflowlayout/section(atindexiscollapsed:)
    @available(macOS 10.12, *)
    @MainActor open func section(atIndexIsCollapsed sectionIndex: Int) -> Bool { _collapsed.contains(sectionIndex) }

    // MARK: Delegate metrics

    private var _flowDelegate: (any NSCollectionViewDelegateFlowLayout)? { _collectionView?.delegate as? any NSCollectionViewDelegateFlowLayout }
    private func _size(forItemAt ip: IndexPath) -> NSSize {
        guard let cv = _collectionView, let d = _flowDelegate else { return _itemSize }
        return d.collectionView(cv, layout: self, sizeForItemAt: ip)
    }
    private func _inset(forSection s: Int) -> NSEdgeInsets {
        guard let cv = _collectionView, let d = _flowDelegate else { return _sectionInset }
        return d.collectionView(cv, layout: self, insetForSectionAt: s)
    }
    private func _lineSpacing(forSection s: Int) -> CGFloat {
        guard let cv = _collectionView, let d = _flowDelegate else { return _minimumLineSpacing }
        return d.collectionView(cv, layout: self, minimumLineSpacingForSectionAt: s)
    }
    private func _interitemSpacing(forSection s: Int) -> CGFloat {
        guard let cv = _collectionView, let d = _flowDelegate else { return _minimumInteritemSpacing }
        return d.collectionView(cv, layout: self, minimumInteritemSpacingForSectionAt: s)
    }
    private func _headerSize(forSection s: Int) -> NSSize {
        guard let cv = _collectionView, let d = _flowDelegate else { return _headerReferenceSize }
        return d.collectionView(cv, layout: self, referenceSizeForHeaderInSection: s)
    }
    private func _footerSize(forSection s: Int) -> NSSize {
        guard let cv = _collectionView, let d = _flowDelegate else { return _footerReferenceSize }
        return d.collectionView(cv, layout: self, referenceSizeForFooterInSection: s)
    }

    // MARK: Preparing

    private var _vertical: Bool { _scrollDirection == .vertical }
    private var _rightToLeft: Bool { _collectionView?.userInterfaceLayoutDirection == .rightToLeft }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/prepare()
    @MainActor open override func prepare() {
        super.prepare()
        _sections = []
        let avail = _availableSize
        // The extent across the scrolling axis (a line's length) and the cursor along it.
        let across = _vertical ? avail.width : avail.height
        var along: CGFloat = 0
        for s in 0..<_numberOfSections {
            var section = _Section()
            let start = along
            let headerSize = _headerSize(forSection: s)
            let headerLength = _vertical ? headerSize.height : headerSize.width
            if headerLength > 0 {
                let a = _makeAttributes(forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, with: IndexPath(item: 0, section: s))
                a.frame = _vertical ? NSRect(x: 0, y: along, width: across, height: headerLength) : NSRect(x: along, y: 0, width: headerLength, height: across)
                section.header = a
                along += headerLength
            }
            if !_collapsed.contains(s) {
                let inset = _inset(forSection: s)
                let lineSpacing = _lineSpacing(forSection: s)
                let gap = _interitemSpacing(forSection: s)
                let leadInset = _vertical ? inset.left : inset.top
                let trailInset = _vertical ? inset.right : inset.bottom
                let lineLength = max(0, across - leadInset - trailInset)
                along += _vertical ? inset.top : inset.left
                var cursor: CGFloat = 0      // across the axis, within the line
                var lineExtent: CGFloat = 0  // the tallest item of the line, along the axis
                var lineStart = along
                var inLine = 0
                let count = _numberOfItems(inSection: s)
                for i in 0..<count {
                    let ip = IndexPath(item: i, section: s)
                    let size = _size(forItemAt: ip)
                    let w = _vertical ? size.width : size.height
                    let h = _vertical ? size.height : size.width
                    if inLine > 0 && cursor + w > lineLength + 0.001 {
                        // Wrap to the next line.
                        lineStart += lineExtent + lineSpacing
                        cursor = 0
                        lineExtent = 0
                        inLine = 0
                    }
                    let a = _makeAttributes(forItemWith: ip)
                    let acrossOrigin = leadInset + cursor
                    if _vertical {
                        let x = _rightToLeft ? across - acrossOrigin - w : acrossOrigin
                        a.frame = NSRect(x: x, y: lineStart, width: w, height: h)
                    } else {
                        a.frame = NSRect(x: lineStart, y: acrossOrigin, width: h, height: w)
                    }
                    section.items.append(a)
                    cursor += w + gap
                    lineExtent = max(lineExtent, h)
                    inLine += 1
                }
                along = count > 0 ? lineStart + lineExtent : along
                along += _vertical ? inset.bottom : inset.right
            }
            let footerSize = _footerSize(forSection: s)
            let footerLength = _vertical ? footerSize.height : footerSize.width
            if footerLength > 0 {
                let a = _makeAttributes(forSupplementaryViewOfKind: NSCollectionView.elementKindSectionFooter, with: IndexPath(item: 0, section: s))
                a.frame = _vertical ? NSRect(x: 0, y: along, width: across, height: footerLength) : NSRect(x: along, y: 0, width: footerLength, height: across)
                section.footer = a
                along += footerLength
            }
            section.frame = _vertical ? NSRect(x: 0, y: start, width: across, height: along - start) : NSRect(x: start, y: 0, width: along - start, height: across)
            _sections.append(section)
        }
        _contentSize = _vertical ? NSSize(width: across, height: along) : NSSize(width: along, height: across)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/collectionviewcontentsize
    @MainActor open override var collectionViewContentSize: NSSize { _contentSize }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/shouldinvalidatelayout(forboundschange:)
    /// A change of the extent across the scrolling axis re-wraps the lines.
    @MainActor open override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        _vertical ? newBounds.width != _contentSize.width : newBounds.height != _contentSize.height
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/invalidatelayout(with:)
    @MainActor open override func invalidateLayout(with context: NSCollectionViewLayoutInvalidationContext) {
        if let c = context as? NSCollectionViewFlowLayoutInvalidationContext, !c.invalidateFlowLayoutAttributes, !c.invalidateFlowLayoutDelegateMetrics, !c._isWhole {
            // Nothing of the flow's own changed: the collection view re-places what the
            // context names, the frames stay.
            super.invalidateLayout(with: context)
            return
        }
        super.invalidateLayout(with: context)
    }

    // MARK: Attributes

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforelements(in:)
    @MainActor open override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var out: [NSCollectionViewLayoutAttributes] = []
        let visible = _collectionView?.visibleRect ?? rect
        for (s, section) in _sections.enumerated() {
            guard section.frame.intersects(rect) || (_headersPin && section.header != nil) || (_footersPin && section.footer != nil) else { continue }
            if let h = section.header {
                let pinned = _headersPin ? _pinnedHeader(h, section: section, visible: visible) : h
                if pinned.frame.intersects(rect) || (_headersPin && section.frame.intersects(visible) && pinned.frame.intersects(visible)) { out.append(pinned) }
            }
            for a in section.items where a.frame.intersects(rect) { out.append(a) }
            if let f = section.footer {
                let pinned = _footersPin ? _pinnedFooter(f, section: section, visible: visible) : f
                if pinned.frame.intersects(rect) || (_footersPin && section.frame.intersects(visible) && pinned.frame.intersects(visible)) { out.append(pinned) }
            }
            _ = s
        }
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforitem(at:)
    @MainActor open override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard _sections.indices.contains(indexPath.section), _sections[indexPath.section].items.indices.contains(indexPath.item) else { return nil }
        return _sections[indexPath.section].items[indexPath.item]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforsupplementaryview(ofkind:at:)
    @MainActor open override func layoutAttributesForSupplementaryView(ofKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard _sections.indices.contains(indexPath.section) else { return nil }
        let section = _sections[indexPath.section]
        let visible = _collectionView?.visibleRect ?? .zero
        switch elementKind {
        case NSCollectionView.elementKindSectionHeader:
            guard let h = section.header else { return nil }
            return _headersPin ? _pinnedHeader(h, section: section, visible: visible) : h
        case NSCollectionView.elementKindSectionFooter:
            guard let f = section.footer else { return nil }
            return _footersPin ? _pinnedFooter(f, section: section, visible: visible) : f
        default: return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesfordroptarget(at:)
    @MainActor open override func layoutAttributesForDropTarget(at pointInCollectionView: NSPoint) -> NSCollectionViewLayoutAttributes? {
        for section in _sections { for a in section.items where a.frame.contains(pointInCollectionView) { return a } }
        return nil
    }

    /// The header moved to stay in view while its section is: it slides from the top
    /// (leading edge) of the visible rect to the end of the section, above the items.
    private func _pinnedHeader(_ h: NSCollectionViewLayoutAttributes, section: _Section, visible: NSRect) -> NSCollectionViewLayoutAttributes {
        let a = h.copy() as! NSCollectionViewLayoutAttributes
        var f = h.frame
        if _vertical {
            let top = max(section.frame.minY, visible.minY)
            f.origin.y = min(top, section.frame.maxY - f.height)
        } else {
            let lead = max(section.frame.minX, visible.minX)
            f.origin.x = min(lead, section.frame.maxX - f.width)
        }
        a.frame = f
        a.zIndex = 10
        return a
    }
    private func _pinnedFooter(_ ft: NSCollectionViewLayoutAttributes, section: _Section, visible: NSRect) -> NSCollectionViewLayoutAttributes {
        let a = ft.copy() as! NSCollectionViewLayoutAttributes
        var f = ft.frame
        if _vertical {
            let bottom = min(section.frame.maxY, visible.maxY)
            f.origin.y = max(bottom - f.height, section.frame.minY)
        } else {
            let trail = min(section.frame.maxX, visible.maxX)
            f.origin.x = max(trail - f.width, section.frame.minX)
        }
        a.frame = f
        a.zIndex = 10
        return a
    }

    /// The items' frames in order, for keyboard navigation and tests.
    internal var _allItemAttributes: [NSCollectionViewLayoutAttributes] { _sections.flatMap { $0.items } }
}
