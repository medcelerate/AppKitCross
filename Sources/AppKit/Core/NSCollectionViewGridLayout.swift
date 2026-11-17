// NSCollectionViewGridLayout (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Equal cells in a grid: as many columns as fit the width between the minimum and
// maximum item sizes (capped by `maximumNumberOfColumns`), the cells grown to fill the
// row, as many rows as the items need (capped by `maximumNumberOfRows`). Sections run
// one after another through the same grid. `backgroundColors` stripe the rows.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout
@available(macOS 10.11, *)
@MainActor open class NSCollectionViewGridLayout: NSCollectionViewLayout {
    private var _margins = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    private var _minimumInteritemSpacing: CGFloat = 0
    private var _minimumLineSpacing: CGFloat = 0
    private var _maximumNumberOfRows = 0
    private var _maximumNumberOfColumns = 0
    private var _minimumItemSize: NSSize = .zero
    private var _maximumItemSize: NSSize = .zero
    private var _backgroundColors: [NSColor] = []

    private var _items: [[NSCollectionViewLayoutAttributes]] = []     // per section
    private var _contentSize: NSSize = .zero
    private var _rowRects: [NSRect] = []
    private var _columns = 1

    public override init() { super.init() }
    /// AppKit's keys (`NSMaximumNumberOfColumns`, `NSMinimumItemSize`, …) and the background
    /// colours.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let m = coder._decodeObjectIfPresent(forKey: "NSMargins") as? [NSNumber], m.count == 4 {
            _margins = NSEdgeInsets(top: CGFloat(m[0].doubleValue), left: CGFloat(m[1].doubleValue), bottom: CGFloat(m[2].doubleValue), right: CGFloat(m[3].doubleValue))
        }
        _minimumInteritemSpacing = CGFloat(coder.decodeDouble(forKey: "NSMinimumInteritemSpacing"))
        _minimumLineSpacing = CGFloat(coder.decodeDouble(forKey: "NSMinimumLineSpacing"))
        _maximumNumberOfRows = coder.decodeInteger(forKey: "NSMaximumNumberOfRows")
        _maximumNumberOfColumns = coder.decodeInteger(forKey: "NSMaximumNumberOfColumns")
        if let v = coder._decodeObjectIfPresent(forKey: "NSMinimumItemSize") as? NSValue { _minimumItemSize = v.sizeValue }
        if let v = coder._decodeObjectIfPresent(forKey: "NSMaximumItemSize") as? NSValue { _maximumItemSize = v.sizeValue }
        _backgroundColors = coder._decodeObjectIfPresent(forKey: "NSBackgroundColors") as? [NSColor] ?? []
    }
    open override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        let m = _margins
        coder.encode([m.top, m.left, m.bottom, m.right].map { NSNumber(value: Double($0)) } as NSArray, forKey: "NSMargins")
        coder.encode(Double(_minimumInteritemSpacing), forKey: "NSMinimumInteritemSpacing")
        coder.encode(Double(_minimumLineSpacing), forKey: "NSMinimumLineSpacing")
        coder.encode(_maximumNumberOfRows, forKey: "NSMaximumNumberOfRows")
        coder.encode(_maximumNumberOfColumns, forKey: "NSMaximumNumberOfColumns")
        coder.encode(NSValue(size: _minimumItemSize), forKey: "NSMinimumItemSize")
        coder.encode(NSValue(size: _maximumItemSize), forKey: "NSMaximumItemSize")
        if !_backgroundColors.isEmpty { coder.encode(_backgroundColors as NSArray, forKey: "NSBackgroundColors") }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/margins
    @MainActor open var margins: NSEdgeInsets {
        get { _margins }
        set { _margins = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/minimuminteritemspacing
    @MainActor open var minimumInteritemSpacing: CGFloat {
        get { _minimumInteritemSpacing }
        set { _minimumInteritemSpacing = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/minimumlinespacing
    @MainActor open var minimumLineSpacing: CGFloat {
        get { _minimumLineSpacing }
        set { _minimumLineSpacing = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/maximumnumberofrows
    @MainActor open var maximumNumberOfRows: Int {
        get { _maximumNumberOfRows }
        set { _maximumNumberOfRows = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/maximumnumberofcolumns
    @MainActor open var maximumNumberOfColumns: Int {
        get { _maximumNumberOfColumns }
        set { _maximumNumberOfColumns = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/minimumitemsize
    @MainActor open var minimumItemSize: NSSize {
        get { _minimumItemSize }
        set { _minimumItemSize = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/maximumitemsize
    @MainActor open var maximumItemSize: NSSize {
        get { _maximumItemSize }
        set { _maximumItemSize = newValue; invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewgridlayout/backgroundcolors
    @MainActor open var backgroundColors: [NSColor]! {
        get { _backgroundColors }
        set { _backgroundColors = newValue ?? []; _collectionView?.needsDisplay = true }
    }

    // MARK: Preparing

    /// The cell size and column count for a width: the minimum size (50 points when
    /// unset) decides how many columns fit, the cells then share the width up to the
    /// maximum size, keeping the minimum size's proportions.
    internal func _grid(forWidth width: CGFloat) -> (columns: Int, cell: NSSize) {
        let minW = _minimumItemSize.width > 0 ? _minimumItemSize.width : 50
        let minH = _minimumItemSize.height > 0 ? _minimumItemSize.height : 50
        let maxW = _maximumItemSize.width > 0 ? max(_maximumItemSize.width, minW) : .greatestFiniteMagnitude
        let maxH = _maximumItemSize.height > 0 ? max(_maximumItemSize.height, minH) : .greatestFiniteMagnitude
        let usable = max(0, width - _margins.left - _margins.right)
        var columns = max(1, Int((usable + _minimumInteritemSpacing) / (minW + _minimumInteritemSpacing)))
        if _maximumNumberOfColumns > 0 { columns = min(columns, _maximumNumberOfColumns) }
        var w = (usable - CGFloat(columns - 1) * _minimumInteritemSpacing) / CGFloat(columns)
        w = min(max(w, minW), maxW)
        let h = min(max(w * (minH / minW), minH), maxH)
        return (columns, NSSize(width: w, height: h))
    }

    /// Where the item at `index` (counting across sections) goes in a grid of `count` items
    /// laid out `width` wide; zero past the last row (`frameForItem(at:withNumberOfItems:)`).
    internal func _frame(forItemAt index: Int, count: Int, width: CGFloat, rightToLeft: Bool) -> NSRect {
        guard index >= 0, index < count else { return .zero }
        let (columns, cell) = _grid(forWidth: width)
        let row = index / columns, col = index % columns
        if _maximumNumberOfRows > 0 && row >= _maximumNumberOfRows { return .zero }
        var x = _margins.left + CGFloat(col) * (cell.width + _minimumInteritemSpacing)
        if rightToLeft { x = width - x - cell.width }
        return NSRect(x: x, y: _margins.top + CGFloat(row) * (cell.height + _minimumLineSpacing), width: cell.width, height: cell.height)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/prepare()
    @MainActor open override func prepare() {
        super.prepare()
        let avail = _availableSize
        let (columns, cell) = _grid(forWidth: avail.width)
        _columns = columns
        _items = []
        _rowRects = []
        let rtl = _collectionView?.userInterfaceLayoutDirection == .rightToLeft
        var flat = 0
        var rows = 0
        for s in 0..<_numberOfSections {
            var section: [NSCollectionViewLayoutAttributes] = []
            for i in 0..<_numberOfItems(inSection: s) {
                let a = _makeAttributes(forItemWith: IndexPath(item: i, section: s))
                let row = flat / columns, col = flat % columns
                if _maximumNumberOfRows > 0 && row >= _maximumNumberOfRows {
                    // Beyond the last row: the item is laid out off the grid and hidden.
                    a.frame = NSRect(origin: .zero, size: cell)
                    a.isHidden = true
                } else {
                    var x = _margins.left + CGFloat(col) * (cell.width + _minimumInteritemSpacing)
                    if rtl { x = avail.width - x - cell.width }
                    let y = _margins.top + CGFloat(row) * (cell.height + _minimumLineSpacing)
                    a.frame = NSRect(x: x, y: y, width: cell.width, height: cell.height)
                    rows = max(rows, row + 1)
                }
                section.append(a)
                flat += 1
            }
            _items.append(section)
        }
        let step = cell.height + _minimumLineSpacing
        for r in 0..<rows {
            _rowRects.append(NSRect(x: 0, y: _margins.top + CGFloat(r) * step - (r == 0 ? _margins.top : _minimumLineSpacing / 2), width: avail.width, height: step))
        }
        let height = rows == 0 ? _margins.top + _margins.bottom : _margins.top + CGFloat(rows) * cell.height + CGFloat(rows - 1) * _minimumLineSpacing + _margins.bottom
        _contentSize = NSSize(width: avail.width, height: max(height, avail.height))
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/collectionviewcontentsize
    @MainActor open override var collectionViewContentSize: NSSize { _contentSize }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/shouldinvalidatelayout(forboundschange:)
    @MainActor open override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { newBounds.size != _contentSize }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforelements(in:)
    @MainActor open override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        _items.flatMap { $0 }.filter { !$0.isHidden && _rectsOverlap($0.frame, rect) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesforitem(at:)
    @MainActor open override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard _items.indices.contains(indexPath.section), _items[indexPath.section].indices.contains(indexPath.item) else { return nil }
        return _items[indexPath.section][indexPath.item]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewlayout/layoutattributesfordroptarget(at:)
    @MainActor open override func layoutAttributesForDropTarget(at pointInCollectionView: NSPoint) -> NSCollectionViewLayoutAttributes? {
        _items.flatMap { $0 }.first { !$0.isHidden && $0.frame.contains(pointInCollectionView) }
    }

    /// The row bands (for the striped background) and the column count, after `prepare()`.
    internal var _rowStripes: [NSRect] { _rowRects }
    internal var _numberOfColumns: Int { _columns }
}
