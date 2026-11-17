// NSCollectionView (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation (the nib paths:
// the port cannot load nibs).
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The data source counts sections and items and makes an `NSCollectionViewItem` per
// index path (through `makeItem(withIdentifier:for:)`, which reuses); the layout object
// says where every element goes. Items and supplementary views exist only for the
// elements in the visible rect and are placed in `layout()` (a reload or a layout
// invalidation asks for layout), as AppKit does, so they exist before a natively hosted
// window builds its layer scene; `viewWillDraw` and scrolling place them again, which
// recycles the ones that left. Selection, highlighting, the
// keyboard and batch updates are here; the layout invalidation cycle runs through
// `_layoutDidInvalidate` (ADR-0020).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview
@MainActor open class NSCollectionView: NSView, NSDraggingSource, NSUserInterfaceValidations, NSSelectorHandling {
    // MARK: Storage
    private weak var _dataSource: (any NSCollectionViewDataSource)?
    private weak var _delegate: (any NSCollectionViewDelegate)?
    private weak var _prefetchDataSource: (any NSCollectionViewPrefetching)?
    private var _layout: NSCollectionViewLayout?
    private var _backgroundColors: [NSColor] = [.controlBackgroundColor]
    private var _backgroundView: NSView?
    private var _backgroundViewScrollsWithContent = true
    private var _allowsEmptySelection = true
    private var _allowsMultipleSelection = false
    private var _isSelectable = false
    private var _selection = Set<IndexPath>()
    private var _anchor: IndexPath?
    private var _pressed: IndexPath?
    private var _pressDidToggle = false
    private var _marqueeStart: NSPoint?            // a rubber-band selection from empty space
    private var _marqueeRect: NSRect = .zero
    private var _marqueeBase = Set<IndexPath>()    // the selection the drag adds to (Cmd/Shift)
    private var _highlighted = Set<IndexPath>()
    private var _dragMaskLocal: NSDragOperation = .every
    private var _dragMaskRemote: NSDragOperation = []

    // Registration and reuse
    private var _itemClasses: [NSUserInterfaceItemIdentifier: AnyClass] = [:]
    private var _itemNibs: [NSUserInterfaceItemIdentifier: NSNib] = [:]
    private var _supplementaryClasses: [String: AnyClass] = [:]      // "\(kind)\u{1}\(identifier)"
    private var _supplementaryNibs: [String: NSNib] = [:]
    private var _spareItems: [NSUserInterfaceItemIdentifier: [NSCollectionViewItem]] = [:]
    private var _spareSupplementary: [String: [NSView]] = [:]

    // Counts and visible elements
    private var _itemCounts: [Int] = []
    private var _needsReload = true
    private var _needsPrepare = true
    private var _visibleItems: [IndexPath: NSCollectionViewItem] = [:]
    private var _visibleSupplementary: [_NSCollectionElementKey: NSView] = [:]
    private var _visibleDecorations: [_NSCollectionElementKey: NSView] = [:]
    private var _displayed = Set<IndexPath>()           // items the delegate was told are displayed
    private var _updating = false
    private var _settingFrame = false

    // Batch updates
    private var _updateDepth = 0
    private var _pending = _NSCollectionViewPendingUpdates()
    private var _batchAnimates = false
    /// Deleted and reloaded items fading out after an animated update, removed when the
    /// animation group completes (ADR-0041).
    private var _disappearing: [ObjectIdentifier: NSCollectionViewItem] = [:]

    // Dragging (ADR-0041)
    private var _mouseDownEvent: NSEvent?
    private var _pressPoint: NSPoint = .zero
    private var _dragCandidate: IndexPath?           // the item the mouse went down on
    private var _dragAttempted = false
    private var _collapseOnMouseUp: IndexPath?
    private var _draggedIndexPaths = Set<IndexPath>()
    private var _dropTarget: (indexPath: IndexPath, operation: NSCollectionView.DropOperation)?
    private var _dropHighlight: IndexPath?
    private var _gapIndicator: NSView?

    // Legacy (10.5) API storage
    private var _content: [Any] = []
    private var _itemPrototype: NSCollectionViewItem?
    private var _minItemSize: NSSize = .zero
    private var _maxItemSize: NSSize = .zero
    private var _maxNumberOfRows = 0
    private var _maxNumberOfColumns = 0

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/elementkindsectionheader
    @available(macOS 10.11, *)
    static public var elementKindSectionHeader: String { "UICollectionElementKindSectionHeader" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/elementkindsectionfooter
    @available(macOS 10.11, *)
    static public var elementKindSectionFooter: String { "UICollectionElementKindSectionFooter" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/elementkindinteritemgapindicator
    @available(macOS 10.11, *)
    static public var elementKindInterItemGapIndicator: String { "NSCollectionElementKindInterItemGapIndicator" }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    /// Unarchives the settings AppKit archives (selection behaviour, background colours,
    /// the dragging masks); the view's own geometry comes from `NSView`.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard coder.allowsKeyedCoding else { return }
        if coder.containsValue(forKey: "NSSelectable") { _isSelectable = coder.decodeBool(forKey: "NSSelectable") }
        if coder.containsValue(forKey: "NSAllowsMultipleSelection") { _allowsMultipleSelection = coder.decodeBool(forKey: "NSAllowsMultipleSelection") }
        if coder.containsValue(forKey: "NSAllowsEmptySelection") { _allowsEmptySelection = coder.decodeBool(forKey: "NSAllowsEmptySelection") }
        if coder.containsValue(forKey: "NSBackgroundColors"), let colors = coder.decodeObject(forKey: "NSBackgroundColors") as? [NSColor], !colors.isEmpty { _backgroundColors = colors }
        if coder.containsValue(forKey: "NSDraggingSourceMaskForLocal") { _dragMaskLocal = NSDragOperation(rawValue: UInt(truncatingIfNeeded: coder.decodeInteger(forKey: "NSDraggingSourceMaskForLocal"))) }
        if coder.containsValue(forKey: "NSDraggingSourceMaskForNonLocal") { _dragMaskRemote = NSDragOperation(rawValue: UInt(truncatingIfNeeded: coder.decodeInteger(forKey: "NSDraggingSourceMaskForNonLocal"))) }
    }

    @MainActor open override var isFlipped: Bool { true }
    @MainActor open override var acceptsFirstResponder: Bool { _isSelectable }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/isfirstresponder
    @MainActor open var isFirstResponder: Bool { window?.firstResponder === self }

    // MARK: Data source, delegate and layout

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/datasource
    @available(macOS 10.11, *)
    @MainActor open var dataSource: (any NSCollectionViewDataSource)? {
        get { _dataSource }
        set { _dataSource = newValue; reloadData() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/delegate
    @MainActor open var delegate: (any NSCollectionViewDelegate)? {
        get { _delegate }
        set { _delegate = newValue; _invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/prefetchdatasource
    @available(macOS 10.13, *)
    @MainActor open var prefetchDataSource: (any NSCollectionViewPrefetching)? {
        get { _prefetchDataSource }
        set { _prefetchDataSource = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/collectionviewlayout
    @available(macOS 10.11, *)
    @MainActor open var collectionViewLayout: NSCollectionViewLayout? {
        get { _layout }
        set {
            guard newValue !== _layout else { return }
            let old = _layout
            old?.prepareForTransition(to: newValue ?? NSCollectionViewLayout())
            newValue?.prepareForTransition(from: old ?? NSCollectionViewLayout())
            if let old, old._collectionView === self { old._collectionView = nil }
            _layout = newValue
            newValue?._collectionView = self
            _dropAllElements()
            _invalidateLayout()
            newValue?.finalizeLayoutTransition()
            old?.finalizeLayoutTransition()
        }
    }

    // MARK: Counts

    /// The counts, read from the data source once per reload.
    private func _reloadCountsIfNeeded() {
        guard _needsReload else { return }
        _needsReload = false
        guard let ds = _dataSource else { _itemCounts = []; return }
        let sections = max(0, ds.numberOfSections(in: self))
        _itemCounts = (0..<sections).map { max(0, ds.collectionView(self, numberOfItemsInSection: $0)) }
        _selection = _selection.filter(_isValid)
        if let a = _anchor, !_isValid(a) { _anchor = nil }
    }
    private func _isValid(_ ip: IndexPath) -> Bool {
        ip.count == 2 && _itemCounts.indices.contains(ip.section) && ip.item >= 0 && ip.item < _itemCounts[ip.section]
    }
    internal var _sectionCount: Int { _reloadCountsIfNeeded(); return _itemCounts.count }
    internal func _itemCount(inSection s: Int) -> Int { _reloadCountsIfNeeded(); return _itemCounts.indices.contains(s) ? _itemCounts[s] : 0 }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/numberofsections
    @available(macOS 10.11, *)
    @MainActor open var numberOfSections: Int { _sectionCount }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/numberofitems(insection:)
    @available(macOS 10.11, *)
    @MainActor open func numberOfItems(inSection section: Int) -> Int { _itemCount(inSection: section) }

    /// Every item's index path, in order.
    private func _allIndexPaths() -> [IndexPath] {
        _reloadCountsIfNeeded()
        var out: [IndexPath] = []
        for (s, n) in _itemCounts.enumerated() { for i in 0..<n { out.append(IndexPath(item: i, section: s)) } }
        return out
    }

    // MARK: Registration and reuse

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/register(_:foritemwithidentifier:)
    @available(macOS 10.11, *)
    @MainActor open func register(_ itemClass: AnyClass?, forItemWithIdentifier identifier: NSUserInterfaceItemIdentifier) {
        _itemClasses[identifier] = itemClass
        _spareItems[identifier] = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/register(_:foritemwithidentifier:)
    @available(macOS 10.11, *)
    @MainActor open func register(_ nib: NSNib?, forItemWithIdentifier identifier: NSUserInterfaceItemIdentifier) {
        _itemNibs[identifier] = nib
        _spareItems[identifier] = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/register(_:forsupplementaryviewofkind:withidentifier:)
    @available(macOS 10.11, *)
    @MainActor open func register(_ viewClass: AnyClass?, forSupplementaryViewOfKind kind: NSCollectionView.SupplementaryElementKind, withIdentifier identifier: NSUserInterfaceItemIdentifier) {
        _supplementaryClasses[_supplementaryKey(kind, identifier)] = viewClass
        _spareSupplementary[_supplementaryKey(kind, identifier)] = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/register(_:forsupplementaryviewofkind:withidentifier:)
    @available(macOS 10.11, *)
    @MainActor open func register(_ nib: NSNib?, forSupplementaryViewOfKind kind: NSCollectionView.SupplementaryElementKind, withIdentifier identifier: NSUserInterfaceItemIdentifier) {
        _supplementaryNibs[_supplementaryKey(kind, identifier)] = nib
        _spareSupplementary[_supplementaryKey(kind, identifier)] = nil
    }
    private func _supplementaryKey(_ kind: String, _ identifier: NSUserInterfaceItemIdentifier) -> String { kind + "\u{1}" + identifier.rawValue }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/makeitem(withidentifier:for:)
    ///
    /// A spare item registered under the identifier (after `prepareForReuse()`), else a
    /// new one of the registered class. Nib registrations cannot be loaded by the port.
    @available(macOS 10.11, *)
    @MainActor open func makeItem(withIdentifier identifier: NSUserInterfaceItemIdentifier, for indexPath: IndexPath) -> NSCollectionViewItem {
        let item: NSCollectionViewItem
        if var spare = _spareItems[identifier], let s = spare.popLast() {
            _spareItems[identifier] = spare
            item = s
            item.prepareForReuse()
        } else if let cls = _itemClasses[identifier] {
            guard let itemType = cls as? NSCollectionViewItem.Type else {
                preconditionFailure("NSCollectionView: \(cls) registered for item identifier '\(identifier.rawValue)' is not an NSCollectionViewItem subclass")
            }
            item = itemType.init(nibName: nil, bundle: nil)
            item._reuseIdentifier = identifier
        } else if _itemNibs[identifier] != nil {
            unimplemented("NSCollectionView.makeItem(withIdentifier:for:) from a nib")
        } else {
            preconditionFailure("NSCollectionView: no item class registered for identifier '\(identifier.rawValue)'")
        }
        item._collectionView = self
        _ = item.view          // loaded, so the data source can fill its outlets
        item.isSelected = _selection.contains(indexPath)
        item.highlightState = _highlightState(at: indexPath)
        return item
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/makesupplementaryview(ofkind:withidentifier:for:)
    ///
    /// A spare view registered under the kind and identifier, else a new one of the
    /// registered class, constructed through `init?(coder:)` (the port has no runtime
    /// to call `init(frame:)` on an arbitrary class).
    @available(macOS 10.11, *)
    @MainActor open func makeSupplementaryView(ofKind elementKind: NSCollectionView.SupplementaryElementKind, withIdentifier identifier: NSUserInterfaceItemIdentifier, for indexPath: IndexPath) -> NSView {
        let key = _supplementaryKey(elementKind, identifier)
        if var spare = _spareSupplementary[key], let v = spare.popLast() {
            _spareSupplementary[key] = spare
            (v as? any NSCollectionViewElement)?.prepareForReuse()
            return v
        }
        if let cls = _supplementaryClasses[key] {
            guard let viewType = cls as? NSView.Type else {
                preconditionFailure("NSCollectionView: \(cls) registered for supplementary '\(elementKind)' / '\(identifier.rawValue)' is not an NSView subclass")
            }
            guard let v = viewType.init(coder: _NSCollectionViewPlaceholderCoder()) else {
                preconditionFailure("NSCollectionView: \(cls) could not be constructed for supplementary '\(elementKind)' / '\(identifier.rawValue)'")
            }
            v.identifier = identifier
            return v
        }
        if _supplementaryNibs[key] != nil { unimplemented("NSCollectionView.makeSupplementaryView(ofKind:withIdentifier:for:) from a nib") }
        preconditionFailure("NSCollectionView: no view class registered for supplementary '\(elementKind)' / '\(identifier.rawValue)'")
    }

    // MARK: Reloading and batch updates

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/reloaddata()
    @available(macOS 10.11, *)
    @MainActor open func reloadData() {
        _dropAllElements()
        _needsReload = true
        _invalidateLayout()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/performbatchupdates(_:completionhandler:)
    @available(macOS 10.11, *)
    ///
    /// Called on the `animator()` proxy (with a non-zero `NSAnimationContext` duration, in
    /// a window on screen), inserted items fade in, deleted ones fade out and moved ones slide to their new
    /// frames; the completion handler then runs when the animation ends. Otherwise the
    /// update is instant and the handler runs before this returns.
    @MainActor open func performBatchUpdates(_ updates: (() -> Void)?, completionHandler: ((Bool) -> Void)? = nil) {
        if _updateDepth == 0 { _batchAnimates = _takeAnimatedUpdateRequest() }
        _updateDepth += 1
        updates?()
        _updateDepth -= 1
        guard _updateDepth == 0 else { completionHandler?(true); return }
        let animates = _batchAnimates
        _batchAnimates = false
        _applyPendingUpdates(animated: animates, completion: completionHandler)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/performbatchupdates(_:)
    @available(macOS 10.11, *)
    @MainActor open func performBatchUpdates(_ updates: (() -> Void)?) async -> Bool {
        var finished = false
        performBatchUpdates(updates) { finished = $0 }
        return finished
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/insertitems(at:)
    @available(macOS 10.11, *)
    @MainActor open func insertItems(at indexPaths: Set<IndexPath>) { _batch { _pending.insertItems.formUnion(indexPaths) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/deleteitems(at:)
    @available(macOS 10.11, *)
    @MainActor open func deleteItems(at indexPaths: Set<IndexPath>) { _batch { _pending.deleteItems.formUnion(indexPaths) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/reloaditems(at:)
    @available(macOS 10.11, *)
    @MainActor open func reloadItems(at indexPaths: Set<IndexPath>) { _batch { _pending.reloadItems.formUnion(indexPaths) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/moveitem(at:to:)
    @available(macOS 10.11, *)
    @MainActor open func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) { _batch { _pending.moveItems.append((indexPath, newIndexPath)) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/insertsections(_:)
    @available(macOS 10.11, *)
    @MainActor open func insertSections(_ sections: IndexSet) { _batch { _pending.insertSections.formUnion(sections) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/deletesections(_:)
    @available(macOS 10.11, *)
    @MainActor open func deleteSections(_ sections: IndexSet) { _batch { _pending.deleteSections.formUnion(sections) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/reloadsections(_:)
    @available(macOS 10.11, *)
    @MainActor open func reloadSections(_ sections: IndexSet) { _batch { _pending.reloadSections.formUnion(sections) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/movesection(_:tosection:)
    @available(macOS 10.11, *)
    @MainActor open func moveSection(_ section: Int, toSection newSection: Int) { _batch { _pending.moveSections.append((section, newSection)) } }

    /// Records one change; outside `performBatchUpdates` it is applied at once.
    private func _batch(_ record: () -> Void) {
        record()
        if _updateDepth == 0 { _applyPendingUpdates(animated: _takeAnimatedUpdateRequest(), completion: nil) }
    }
    /// Whether this update animates: asked through `animator()`, with a duration, on a
    /// window on screen (the port advances layer animations only for trees on screen, so
    /// an off-screen update is instant and its completion runs at once).
    private func _takeAnimatedUpdateRequest() -> Bool {
        _takeAnimatorRequest() && NSAnimationContext.current.duration > 0 && window?.isVisible == true
    }

    /// Applies the recorded changes: deletes and reloads address the old index paths,
    /// inserts the new ones (moves are a delete and an insert of the same element).
    /// The visible items, the selection and the anchor follow their elements to the
    /// new index paths; the counts must then match the data source's, as AppKit
    /// demands.
    ///
    /// Animated, the layout's appearing and disappearing attributes give each item's start
    /// (and a deleted item's end); the model frames are final at once, the views' layers
    /// animate from there (ADR-0041).
    private func _applyPendingUpdates(animated: Bool, completion: ((Bool) -> Void)?) {
        _reloadCountsIfNeeded()
        let pending = _pending
        _pending = _NSCollectionViewPendingUpdates()
        guard !pending.isEmpty else { completion?(true); return }
        if animated && layer == nil { _becomeLayerBacked() }
        // What the old layout gave, for the layout's appearing queries, and where the
        // live views are now (the fallback when the layout has no answer).
        var previous: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
        var oldState: [ObjectIdentifier: (frame: NSRect, alpha: CGFloat)] = [:]
        if animated {
            _prepareLayoutIfNeeded()
            if let layout = _layout {
                for ip in _allIndexPaths() { if let a = layout.layoutAttributesForItem(at: ip)?.copy() as? NSCollectionViewLayoutAttributes { previous[ip] = a } }
            }
            for item in _visibleItems.values { if let v = item.viewIfLoaded { oldState[ObjectIdentifier(item)] = (v.frame, v.alphaValue) } }
        }

        // Identity tokens: the old index path (sections: item NSNotFound).
        struct Token { var old: IndexPath?; var reload: Bool }
        var sections: [(token: Token, items: [Token])] = _itemCounts.enumerated().map { s, n in
            (Token(old: IndexPath(item: NSNotFound, section: s), reload: false), (0..<n).map { Token(old: IndexPath(item: $0, section: s), reload: false) })
        }
        func check(_ ip: IndexPath, _ what: String) {
            precondition(ip.count == 2 && sections.indices.contains(ip.section) && (ip.item == NSNotFound || sections[ip.section].items.indices.contains(ip.item)), "NSCollectionView: invalid \(what) at \(ip)")
        }
        for ip in pending.reloadItems { check(ip, "reload"); sections[ip.section].items[ip.item].reload = true }
        for s in pending.reloadSections { precondition(sections.indices.contains(s), "NSCollectionView: invalid section reload \(s)"); sections[s].token.reload = true }
        // Deletes, highest first so the indices stay valid.
        var movedItems: [(token: Token, to: IndexPath)] = []
        for (from, to) in pending.moveItems { check(from, "move"); movedItems.append((sections[from.section].items[from.item], to)) }
        let itemDeletes = (pending.deleteItems.union(pending.moveItems.map { $0.0 })).sorted(by: >)
        for ip in itemDeletes { check(ip, "delete"); sections[ip.section].items.remove(at: ip.item) }
        // A moved section takes its items as they are after the item deletes (old index
        // paths address the old sections; inserts address the new ones).
        var movedSections: [(token: Token, items: [Token], to: Int)] = []
        for (from, to) in pending.moveSections { precondition(sections.indices.contains(from), "NSCollectionView: invalid section move \(from)"); movedSections.append((sections[from].token, sections[from].items, to)) }
        let sectionDeletes = (pending.deleteSections.union(IndexSet(pending.moveSections.map { $0.0 }))).sorted(by: >)
        for s in sectionDeletes { sections.remove(at: s) }
        // Inserts, lowest first.
        var sectionInserts: [(Int, (Token, [Token]))] = pending.insertSections.map { ($0, (Token(old: nil, reload: false), [])) }
        sectionInserts += movedSections.map { ($0.to, ($0.token, $0.items)) }
        for (s, entry) in sectionInserts.sorted(by: { $0.0 < $1.0 }) {
            precondition(s >= 0 && s <= sections.count, "NSCollectionView: invalid section insert \(s)")
            sections.insert((entry.0, entry.1), at: s)
        }
        var itemInserts: [(IndexPath, Token)] = pending.insertItems.map { ($0, Token(old: nil, reload: false)) }
        itemInserts += movedItems.map { ($0.to, $0.token) }
        for (ip, token) in itemInserts.sorted(by: { $0.0 < $1.0 }) {
            precondition(ip.count == 2 && sections.indices.contains(ip.section) && ip.item >= 0 && ip.item <= sections[ip.section].items.count, "NSCollectionView: invalid insert at \(ip)")
            sections[ip.section].items.insert(token, at: ip.item)
        }
        // The data source must agree. Inserted and reloaded sections take their item
        // counts from it (every item in them is new). The selection is mapped from the
        // old index paths below, so keep it from the new counts' filter.
        let oldSelection = _selection, oldAnchor = _anchor
        _needsReload = true
        _reloadCountsIfNeeded()
        precondition(_itemCounts.count == sections.count, "NSCollectionView: invalid update: the data source has \(_itemCounts.count) sections after the update, the updates give \(sections.count)")
        for (s, n) in _itemCounts.enumerated() {
            if sections[s].token.old == nil || sections[s].token.reload {
                sections[s].items = (0..<n).map { _ in Token(old: nil, reload: false) }
                continue
            }
            precondition(n == sections[s].items.count, "NSCollectionView: invalid update: section \(s) has \(n) items after the update, the updates give \(sections[s].items.count)")
        }
        // Old → new maps.
        var itemMap: [IndexPath: IndexPath] = [:]
        var sectionMap: [Int: Int] = [:]
        var reloaded = Set<IndexPath>()
        for (s, section) in sections.enumerated() {
            if let old = section.token.old { sectionMap[old.section] = s }
            for (i, t) in section.items.enumerated() {
                guard let old = t.old else { continue }
                let new = IndexPath(item: i, section: s)
                itemMap[old] = new
                if t.reload || section.token.reload { reloaded.insert(new) }
            }
        }
        var updates: [NSCollectionViewUpdateItem] = []
        for ip in pending.deleteItems { updates.append(NSCollectionViewUpdateItem(before: ip, after: nil, action: .delete)) }
        for s in pending.deleteSections { updates.append(NSCollectionViewUpdateItem(before: IndexPath(item: NSNotFound, section: s), after: nil, action: .delete)) }
        for ip in pending.insertItems { updates.append(NSCollectionViewUpdateItem(before: nil, after: ip, action: .insert)) }
        for s in pending.insertSections { updates.append(NSCollectionViewUpdateItem(before: nil, after: IndexPath(item: NSNotFound, section: s), action: .insert)) }
        for (from, to) in pending.moveItems { updates.append(NSCollectionViewUpdateItem(before: from, after: to, action: .move)) }
        for (from, to) in pending.moveSections { updates.append(NSCollectionViewUpdateItem(before: IndexPath(item: NSNotFound, section: from), after: IndexPath(item: NSNotFound, section: to), action: .move)) }
        for ip in pending.reloadItems { updates.append(NSCollectionViewUpdateItem(before: ip, after: itemMap[ip], action: .reload)) }
        for s in pending.reloadSections { updates.append(NSCollectionViewUpdateItem(before: IndexPath(item: NSNotFound, section: s), after: sectionMap[s].map { IndexPath(item: NSNotFound, section: $0) }, action: .reload)) }

        // Move the live items, supplementary views, the selection and the anchor.
        var items: [IndexPath: NSCollectionViewItem] = [:]
        var displayed = Set<IndexPath>()
        var leaving: [(NSCollectionViewItem, IndexPath)] = []
        for (old, item) in _visibleItems {
            if let new = itemMap[old], !reloaded.contains(new) {
                items[new] = item
                if _displayed.contains(old) { displayed.insert(new) }
            } else if animated {
                _retire(item, at: old)
                leaving.append((item, old))
            } else {
                _recycle(item, at: old)
            }
        }
        _visibleItems = items
        _displayed = displayed
        var supplementary: [_NSCollectionElementKey: NSView] = [:]
        for (key, v) in _visibleSupplementary {
            if let new = sectionMap[key.indexPath.section], !pending.reloadSections.contains(key.indexPath.section) {
                var k = key
                k.indexPath = IndexPath(item: key.indexPath.item, section: new)
                supplementary[k] = v
            } else {
                _recycleSupplementary(v, key: key)
            }
        }
        _visibleSupplementary = supplementary
        for (key, v) in _visibleDecorations { _recycleDecoration(v, key: key) }
        _visibleDecorations = [:]
        _selection = Set(oldSelection.compactMap { itemMap[$0] })
        _anchor = oldAnchor.flatMap { itemMap[$0] }
        _highlighted = Set(_highlighted.compactMap { itemMap[$0] })
        for (ip, item) in _visibleItems { item.isSelected = _selection.contains(ip) }

        // The layout prepares for the new data, hears the updates, answers the appearing
        // and disappearing queries, then finalizes (UICollectionView's order).
        var context = NSCollectionViewLayout._UpdateContext()
        context.oldToNew = itemMap
        for (o, n) in itemMap { context.newToOld[n] = o }
        context.reloaded = reloaded
        context.previous = previous
        _layout?._updateContext = context
        _needsPrepare = true
        _prepareLayoutIfNeeded()
        _layout?.prepare(forCollectionViewUpdates: updates)
        _updateVisibleElements()
        if animated {
            _animateUpdate(oldState: oldState, leaving: leaving, inserted: Set(pending.insertItems), completion: completion)
        }
        _layout?.finalizeCollectionViewUpdates()
        _layout?._updateContext = nil
        needsDisplay = true
        _accessibilityStructureChangedHere()
        if !animated { completion?(true) }
    }

    /// Runs the animations of an update whose views are already at their final frames:
    /// every visible item starts where the layout's appearing attributes (else its old
    /// view state, else transparent for an inserted item) say; every leaving item goes
    /// where the disappearing attributes say (else fades in place) and is removed when the
    /// group ends.
    private func _animateUpdate(oldState: [ObjectIdentifier: (frame: NSRect, alpha: CGFloat)], leaving: [(NSCollectionViewItem, IndexPath)], inserted: Set<IndexPath>, completion: ((Bool) -> Void)?) {
        let layout = _layout
        NSAnimationContext.beginGrouping()
        let ids = leaving.map { ObjectIdentifier($0.0) }
        for (item, _) in leaving { _disappearing[ObjectIdentifier(item)] = item }
        NSAnimationContext.current.completionHandler = { [weak self] in
            MainActor.assumeIsolated {
                self?._finishDisappearing(ids)
                completion?(true)
            }
        }
        for (ip, item) in _visibleItems {
            guard let view = item.viewIfLoaded else { continue }
            let final = (frame: view.frame, alpha: view.alphaValue)
            var from: (frame: NSRect, alpha: CGFloat)?
            if let a = layout?.initialLayoutAttributesForAppearingItem(at: ip) { from = (a.frame, a.alpha) }
            else if let old = oldState[ObjectIdentifier(item)] { from = old }
            else if inserted.contains(ip) { from = (final.frame, 0) }
            guard let start = from, start.frame != final.frame || start.alpha != final.alpha else { continue }
            view.frame = start.frame
            view.alphaValue = start.alpha
            view.animator().frame = final.frame
            view.animator().alphaValue = final.alpha
        }
        for (item, old) in leaving {
            guard let view = item.viewIfLoaded else { continue }
            let end = layout?.finalLayoutAttributesForDisappearingItem(at: old).map { (frame: $0.frame, alpha: $0.alpha) } ?? (frame: view.frame, alpha: 0)
            if view.frame != end.frame { view.animator().frame = end.frame }
            view.animator().alphaValue = end.alpha
        }
        NSAnimationContext.endGrouping()
    }

    /// Removes the items that faded out (now, or when their animation group ends).
    private func _finishDisappearing(_ ids: [ObjectIdentifier]? = nil) {
        for id in ids ?? Array(_disappearing.keys) {
            guard let item = _disappearing.removeValue(forKey: id) else { continue }
            _park(item)
        }
    }

    // MARK: The layout cycle

    /// The layout (or a property of it) changed: prepare again before the next draw.
    internal func _layoutDidInvalidate(_ layout: NSCollectionViewLayout, context: NSCollectionViewLayoutInvalidationContext) {
        guard layout === _layout else { return }
        if context.invalidateDataSourceCounts { _needsReload = true }
        _needsPrepare = true
        if context.contentOffsetAdjustment != .zero, let clip = superview as? NSClipView {
            let o = clip.bounds.origin
            clip.scroll(to: NSPoint(x: o.x + context.contentOffsetAdjustment.x, y: o.y + context.contentOffsetAdjustment.y))
        }
        needsDisplay = true
        needsLayout = true
    }
    private func _invalidateLayout() {
        _needsPrepare = true
        needsDisplay = true
        // The elements are made in layout, before a natively hosted window builds its layer
        // scene (made only at draw time, their layers would miss that frame's commit).
        needsLayout = true
    }

    /// Runs `prepare()` when the layout is stale and sizes the view to the content.
    private func _prepareLayoutIfNeeded() {
        _reloadCountsIfNeeded()
        guard _needsPrepare, let layout = _layout else { return }
        _needsPrepare = false
        layout.prepare()
        _updateContentSize()
    }
    /// The document view is as large as the content, and at least the clip view.
    private func _updateContentSize() {
        guard let layout = _layout else { return }
        var size = layout.collectionViewContentSize
        if let clip = superview as? NSClipView {
            size.width = max(size.width, clip.bounds.width)
            size.height = max(size.height, clip.bounds.height)
        } else {
            return
        }
        guard size != frame.size else { return }
        _settingFrame = true
        setFrameSize(size)
        _settingFrame = false
    }

    /// A bounds change (the clip view or the view itself resized): the layout decides
    /// whether to re-prepare.
    private func _boundsDidChange() {
        guard let layout = _layout else { return }
        let newBounds = NSRect(origin: .zero, size: (superview as? NSClipView)?.bounds.size ?? bounds.size)
        if layout.shouldInvalidateLayout(forBoundsChange: newBounds) {
            layout.invalidateLayout(with: layout.invalidationContext(forBoundsChange: newBounds))
        }
        needsDisplay = true
        needsLayout = true
    }
    internal override func _clipViewDidResize() { _boundsDidChange() }
    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        let old = frame.size
        super.setFrameSize(newSize)
        if !_settingFrame && old != newSize { _boundsDidChange() }
    }
    @MainActor open override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        _observeClipView()
        _invalidateLayout()
    }
    /// Scrolling re-places the visible elements (pinned headers move with the visible
    /// rect, items come and go) whether or not the backend redraws the document view
    /// for it: the clip view's bounds change notification drives it.
    private var _clipObserver: Any?
    private func _observeClipView() {
        if let o = _clipObserver { NotificationCenter.default.removeObserver(o); _clipObserver = nil }
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        _clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?._clipViewDidScroll() }
        }
    }
    private func _clipViewDidScroll() {
        guard _layout != nil else { return }
        _updateVisibleElements()
        needsDisplay = true
    }

    /// Makes the visible elements' views, as AppKit's collection view does during layout.
    @MainActor open override func layout() {
        super.layout()
        _updateVisibleElements()
    }

    @MainActor open override func viewWillDraw() {
        super.viewWillDraw()
        _updateVisibleElements()
    }

    /// Makes the views for the elements in the visible rect and recycles the rest.
    private func _updateVisibleElements() {
        guard !_updating else { return }
        _updating = true
        defer { _updating = false }
        _prepareLayoutIfNeeded()
        guard let layout = _layout else { _dropAllElements(); return }
        let rect = visibleRect.isEmpty ? bounds : visibleRect
        let attributes = layout.layoutAttributesForElements(in: rect)
        var wantedItems = Set<IndexPath>()
        var wantedSupplementary = Set<_NSCollectionElementKey>()
        var wantedDecorations = Set<_NSCollectionElementKey>()
        var placed: [(NSView, Int, Int)] = []          // view, zIndex, order
        var order = 0
        for a in attributes {
            guard let ip = a.indexPath else { continue }
            switch a.representedElementCategory {
            case .item:
                guard _isValid(ip) else { continue }
                wantedItems.insert(ip)
                guard let item = _visibleItems[ip] ?? _makeItem(at: ip) else { continue }
                _apply(a, to: item.view)
                item.apply(a)
                placed.append((item.view, a.zIndex, order))
            case .supplementaryView:
                guard let key = a._elementKey, let kind = a.representedElementKind else { continue }
                wantedSupplementary.insert(key)
                guard let v = _visibleSupplementary[key] ?? _makeSupplementary(kind: kind, at: ip, key: key) else { continue }
                _apply(a, to: v)
                (v as? any NSCollectionViewElement)?.apply(a)
                placed.append((v, a.zIndex, order))
            case .decorationView:
                guard let key = a._elementKey, let kind = a.representedElementKind else { continue }
                wantedDecorations.insert(key)
                guard let v = _visibleDecorations[key] ?? _makeDecoration(kind: kind, at: ip, key: key) else { continue }
                _apply(a, to: v)
                (v as? any NSCollectionViewElement)?.apply(a)
                placed.append((v, a.zIndex, order))
            case .interItemGap:
                continue
            }
            order += 1
        }
        for (ip, item) in _visibleItems where !wantedItems.contains(ip) { _recycle(item, at: ip) }
        for (key, v) in _visibleSupplementary where !wantedSupplementary.contains(key) { _recycleSupplementary(v, key: key) }
        for (key, v) in _visibleDecorations where !wantedDecorations.contains(key) { _recycleDecoration(v, key: key) }
        _restack(placed)
        _placeBackgroundView()
        if let m = _marqueeView, subviews.last !== m { addSubview(m) }
        if let g = _gapIndicator, subviews.last !== g { addSubview(g) }
        _refreshItemAccessibility()
        // Tell the delegate about the items now on screen.
        for ip in wantedItems.sorted() where !_displayed.contains(ip) {
            _displayed.insert(ip)
            if let item = _visibleItems[ip] { _delegate?.collectionView(self, willDisplay: item, forRepresentedObjectAt: ip) }
        }
    }

    private func _apply(_ a: NSCollectionViewLayoutAttributes, to view: NSView) {
        if view.frame != a.frame { view.frame = a.frame }
        view.isHidden = a.isHidden
        view.alphaValue = a.alpha
    }

    /// Subviews follow the attributes' zIndex (ties keep the layout's order); the
    /// background view stays at the back.
    private func _restack(_ placed: [(NSView, Int, Int)]) {
        guard placed.contains(where: { $0.1 != 0 }) else { return }
        let sorted = placed.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }.map { $0.0 }
        let current = subviews.filter { v in sorted.contains { $0 === v } }
        guard !zip(current, sorted).allSatisfy({ $0 === $1 }) else { return }
        for v in sorted { addSubview(v) }
    }

    private func _makeItem(at ip: IndexPath) -> NSCollectionViewItem? {
        guard let ds = _dataSource else { return nil }
        let item = ds.collectionView(self, itemForRepresentedObjectAt: ip)
        item._collectionView = self
        item.isSelected = _selection.contains(ip)
        item.highlightState = _highlightState(at: ip)
        _visibleItems[ip] = item
        let v = item.view
        if v.superview !== self { addSubview(v) }
        return item
    }
    private func _recycle(_ item: NSCollectionViewItem, at ip: IndexPath) {
        _retire(item, at: ip)
        _park(item)
    }
    /// The item stops representing `ip` (its view may stay a while to fade out).
    private func _retire(_ item: NSCollectionViewItem, at ip: IndexPath) {
        _visibleItems[ip] = nil
        if _displayed.contains(ip) {
            _displayed.remove(ip)
            _delegate?.collectionView(self, didEndDisplaying: item, forRepresentedObjectAt: ip)
        }
        if _dropHighlight == ip { _dropHighlight = nil }
        _clearItemAccessibility(item)
    }
    /// The item's view leaves and the item waits for reuse.
    private func _park(_ item: NSCollectionViewItem) {
        item.viewIfLoaded?.removeFromSuperview()
        item.viewIfLoaded?.layer?.removeAllAnimations()
        if let id = item._reuseIdentifier, _spareItems[id, default: []].count < 32 {
            _spareItems[id, default: []].append(item)
        } else {
            item._collectionView = nil
        }
    }
    private func _makeSupplementary(kind: String, at ip: IndexPath, key: _NSCollectionElementKey) -> NSView? {
        guard let ds = _dataSource else { return nil }
        let v = ds.collectionView(self, viewForSupplementaryElementOfKind: kind, at: ip)
        _visibleSupplementary[key] = v
        if v.superview !== self { addSubview(v) }
        _delegate?.collectionView(self, willDisplaySupplementaryView: v, forElementKind: kind, at: ip)
        return v
    }
    private func _recycleSupplementary(_ v: NSView, key: _NSCollectionElementKey) {
        _visibleSupplementary[key] = nil
        _delegate?.collectionView(self, didEndDisplayingSupplementaryView: v, forElementOfKind: key.kind ?? "", at: key.indexPath)
        v.removeFromSuperview()
        if let kind = key.kind, let id = v.identifier {
            let k = _supplementaryKey(kind, id)
            if _spareSupplementary[k, default: []].count < 32 { _spareSupplementary[k, default: []].append(v) }
        }
    }
    private func _makeDecoration(kind: String, at ip: IndexPath, key: _NSCollectionElementKey) -> NSView? {
        guard let cls = _layout?._decorationViewClass(ofKind: kind), let viewType = cls as? NSView.Type,
              let v = viewType.init(coder: _NSCollectionViewPlaceholderCoder()) else { return nil }
        _visibleDecorations[key] = v
        addSubview(v, positioned: .below, relativeTo: subviews.first { $0 !== _backgroundView })
        return v
    }
    private func _recycleDecoration(_ v: NSView, key: _NSCollectionElementKey) {
        _visibleDecorations[key] = nil
        v.removeFromSuperview()
    }
    internal func _dropDecorationViews(ofKind kind: String) {
        for (key, v) in _visibleDecorations where key.kind == kind { _recycleDecoration(v, key: key) }
        needsDisplay = true
        needsLayout = true
    }
    private func _dropAllElements() {
        _finishDisappearing()
        for (ip, item) in _visibleItems { _recycle(item, at: ip) }
        _visibleItems = [:]
        for (key, v) in _visibleSupplementary { _recycleSupplementary(v, key: key) }
        _visibleSupplementary = [:]
        for (key, v) in _visibleDecorations { _recycleDecoration(v, key: key) }
        _visibleDecorations = [:]
        _displayed = []
    }

    // MARK: Items and geometry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/item(at:)
    @available(macOS 10.11, *)
    @MainActor open func item(at indexPath: IndexPath) -> NSCollectionViewItem? {
        _updateVisibleElements()
        return _visibleItems[indexPath]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/item(at:)
    @MainActor open func item(at index: Int) -> NSCollectionViewItem? { item(at: IndexPath(item: index, section: 0)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/indexpath(for:)
    @available(macOS 10.11, *)
    @MainActor open func indexPath(for item: NSCollectionViewItem) -> IndexPath? { _visibleItems.first { $0.value === item }?.key }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/indexpathforitem(at:)
    @available(macOS 10.11, *)
    @MainActor open func indexPathForItem(at point: NSPoint) -> IndexPath? {
        _prepareLayoutIfNeeded()
        guard let layout = _layout else { return nil }
        let probe = NSRect(x: point.x, y: point.y, width: 1, height: 1)
        return layout.layoutAttributesForElements(in: probe).first { $0.representedElementCategory == .item && !$0.isHidden && $0.frame.contains(point) }?.indexPath
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/indexpathsforvisibleitems()
    @available(macOS 10.11, *)
    @MainActor open func indexPathsForVisibleItems() -> Set<IndexPath> {
        _updateVisibleElements()
        return Set(_visibleItems.keys)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/visibleitems()
    @available(macOS 10.11, *)
    @MainActor open func visibleItems() -> [NSCollectionViewItem] {
        _updateVisibleElements()
        return _visibleItems.sorted { $0.key < $1.key }.map { $0.value }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/indexpathsforvisiblesupplementaryelements(ofkind:)
    @available(macOS 10.11, *)
    @MainActor open func indexPathsForVisibleSupplementaryElements(ofKind elementKind: NSCollectionView.SupplementaryElementKind) -> Set<IndexPath> {
        _updateVisibleElements()
        return Set(_visibleSupplementary.keys.filter { $0.kind == elementKind }.map { $0.indexPath })
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/visiblesupplementaryviews(ofkind:)
    @available(macOS 10.11, *)
    @MainActor open func visibleSupplementaryViews(ofKind elementKind: NSCollectionView.SupplementaryElementKind) -> [any NSView & NSCollectionViewElement] {
        _updateVisibleElements()
        return _visibleSupplementary.filter { $0.key.kind == elementKind }.sorted { $0.key.indexPath < $1.key.indexPath }.compactMap { $0.value as? any NSView & NSCollectionViewElement }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/supplementaryview(forelementkind:at:)
    @available(macOS 10.11, *)
    @MainActor open func supplementaryView(forElementKind elementKind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> (any NSView & NSCollectionViewElement)? {
        _updateVisibleElements()
        return _visibleSupplementary[_NSCollectionElementKey(category: .supplementaryView, kind: elementKind, indexPath: indexPath)] as? any NSView & NSCollectionViewElement
    }
    /// The supplementary view at an index path whatever its type (for the demo and tests).
    internal func _supplementaryView(ofKind kind: String, at indexPath: IndexPath) -> NSView? {
        _updateVisibleElements()
        return _visibleSupplementary[_NSCollectionElementKey(category: .supplementaryView, kind: kind, indexPath: indexPath)]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/layoutattributesforitem(at:)
    @available(macOS 10.11, *)
    @MainActor open func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        _prepareLayoutIfNeeded()
        return _layout?.layoutAttributesForItem(at: indexPath)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/layoutattributesforsupplementaryelement(ofkind:at:)
    @available(macOS 10.11, *)
    @MainActor open func layoutAttributesForSupplementaryElement(ofKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        _prepareLayoutIfNeeded()
        return _layout?.layoutAttributesForSupplementaryView(ofKind: kind, at: indexPath)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/frameforitem(at:)
    @MainActor open func frameForItem(at index: Int) -> NSRect { layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame ?? .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/frameforitem(at:withnumberofitems:)
    ///
    /// The legacy grid: as many columns as items of `minItemSize` (the prototype's view
    /// size when unset) fit the width, never more than the items (or
    /// `maxNumberOfColumns`), cells widened to share the width up to `maxItemSize`; rows
    /// follow without spacing, as AppKit's 10.5 layout places them.
    @MainActor open func frameForItem(at index: Int, withNumberOfItems numberOfItems: Int) -> NSRect {
        let proto = _itemPrototype?.viewIfLoaded?.frame.size ?? .zero
        let minW = _minItemSize.width > 0 ? _minItemSize.width : proto.width
        let minH = _minItemSize.height > 0 ? _minItemSize.height : proto.height
        guard minW > 0, minH > 0, numberOfItems > 0, index >= 0 else { return .zero }
        let width = (superview as? NSClipView)?.bounds.width ?? bounds.width
        var columns = max(1, min(numberOfItems, Int(width / minW)))
        if _maxNumberOfColumns > 0 { columns = min(columns, _maxNumberOfColumns) }
        let maxW = _maxItemSize.width > 0 ? max(_maxItemSize.width, minW) : .greatestFiniteMagnitude
        let w = min(max(width / CGFloat(columns), minW), maxW)
        let h = minH
        return NSRect(x: CGFloat(index % columns) * w, y: CGFloat(index / columns) * h, width: w, height: h)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/scrolltoitems(at:scrollposition:)
    @available(macOS 10.11, *)
    @MainActor open func scrollToItems(at indexPaths: Set<IndexPath>, scrollPosition: NSCollectionView.ScrollPosition) {
        _prepareLayoutIfNeeded()
        guard let layout = _layout else { return }
        var union: NSRect? = nil
        for ip in indexPaths {
            guard let f = layout.layoutAttributesForItem(at: ip)?.frame else { continue }
            union = union.map { $0.union(f) } ?? f
        }
        guard let target = union, let clip = superview as? NSClipView else { return }
        let visible = clip.bounds
        var origin = visible.origin
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let left = scrollPosition.contains(.left) || scrollPosition.contains(rtl ? .trailingEdge : .leadingEdge)
        let right = scrollPosition.contains(.right) || scrollPosition.contains(rtl ? .leadingEdge : .trailingEdge)
        if scrollPosition.contains(.top) { origin.y = target.minY }
        else if scrollPosition.contains(.bottom) { origin.y = target.maxY - visible.height }
        else if scrollPosition.contains(.centeredVertically) { origin.y = target.midY - visible.height / 2 }
        else if target.minY < visible.minY { origin.y = target.minY }
        else if target.maxY > visible.maxY { origin.y += target.maxY - visible.maxY }
        if left { origin.x = target.minX }
        else if right { origin.x = target.maxX - visible.width }
        else if scrollPosition.contains(.centeredHorizontally) { origin.x = target.midX - visible.width / 2 }
        else if target.minX < visible.minX { origin.x = target.minX }
        else if target.maxX > visible.maxX { origin.x += target.maxX - visible.maxX }
        clip.scroll(to: origin)
        (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
        needsDisplay = true
    }

    // MARK: Selection

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/isselectable
    @MainActor open var isSelectable: Bool {
        get { _isSelectable }
        set { _isSelectable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/allowsemptyselection
    @available(macOS 10.11, *)
    @MainActor open var allowsEmptySelection: Bool {
        get { _allowsEmptySelection }
        set { _allowsEmptySelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/allowsmultipleselection
    @MainActor open var allowsMultipleSelection: Bool {
        get { _allowsMultipleSelection }
        set { _allowsMultipleSelection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/selectionindexpaths
    ///
    /// Set programmatically, the selection changes without the delegate's should/did
    /// methods (they report what the user does).
    @available(macOS 10.11, *)
    @MainActor open var selectionIndexPaths: Set<IndexPath> {
        get { _selection }
        set {
            _reloadCountsIfNeeded()
            var proposed = newValue.filter(_isValid)
            if !_allowsMultipleSelection, proposed.count > 1, let last = proposed.sorted().last { proposed = [last] }
            _setSelection(proposed)
            _anchor = proposed.sorted().first
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/selectionindexes
    @MainActor open var selectionIndexes: IndexSet {
        get { IndexSet(_selection.filter { $0.section == 0 }.map { $0.item }) }
        set { selectionIndexPaths = Set(newValue.map { IndexPath(item: $0, section: 0) }) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/selectitems(at:scrollposition:)
    @available(macOS 10.11, *)
    @MainActor open func selectItems(at indexPaths: Set<IndexPath>, scrollPosition: NSCollectionView.ScrollPosition) {
        _reloadCountsIfNeeded()
        let valid = indexPaths.filter(_isValid)
        guard !valid.isEmpty else { return }
        if _allowsMultipleSelection { _setSelection(_selection.union(valid)) } else if let last = valid.sorted().last { _setSelection([last]) }
        scrollToItems(at: valid, scrollPosition: scrollPosition)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/deselectitems(at:)
    @available(macOS 10.11, *)
    @MainActor open func deselectItems(at indexPaths: Set<IndexPath>) {
        let remaining = _selection.subtracting(indexPaths)
        if remaining.isEmpty && !_allowsEmptySelection && !_selection.isEmpty { return }
        _setSelection(remaining)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/selectall(_:)
    @MainActor open func selectAll(_ sender: Any?) {
        guard _allowsMultipleSelection else { return }
        _userSetSelection(Set(_allIndexPaths()))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/deselectall(_:)
    @MainActor open func deselectAll(_ sender: Any?) {
        guard _allowsEmptySelection else { return }
        _userSetSelection([])
    }

    /// Stores a selection and updates the items.
    private func _setSelection(_ new: Set<IndexPath>) {
        guard new != _selection else { return }
        _selection = new
        for (ip, item) in _visibleItems { item.isSelected = new.contains(ip) }
        _refreshItemAccessibility()
        _accessibilityNotify(.selection(_accessibilityElementID))
        needsDisplay = true
    }

    /// A selection the user asked for: the delegate vets what gets selected and
    /// deselected, then hears what did.
    @discardableResult
    private func _userSetSelection(_ proposed: Set<IndexPath>) -> Bool {
        let toSelect = proposed.subtracting(_selection)
        let toDeselect = _selection.subtracting(proposed)
        var select = toSelect, deselect = toDeselect
        if let d = _delegate {
            if !toSelect.isEmpty { select = d.collectionView(self, shouldSelectItemsAt: toSelect).intersection(toSelect) }
            if !toDeselect.isEmpty { deselect = d.collectionView(self, shouldDeselectItemsAt: toDeselect).intersection(toDeselect) }
        }
        let final = _selection.subtracting(deselect).union(select)
        if final.isEmpty && !_allowsEmptySelection && !_selection.isEmpty { return false }
        guard final != _selection else { return false }
        _setSelection(final)
        if !deselect.isEmpty { _delegate?.collectionView(self, didDeselectItemsAt: deselect) }
        if !select.isEmpty { _delegate?.collectionView(self, didSelectItemsAt: select) }
        return true
    }

    /// The highlight an item made for `ip` starts with.
    private func _highlightState(at ip: IndexPath) -> NSCollectionViewItem.HighlightState {
        ip == _dropHighlight ? .asDropTarget : (_highlighted.contains(ip) ? .forSelection : .none)
    }

    /// Highlights items (while the mouse is down), through the delegate.
    private func _setHighlight(_ state: NSCollectionViewItem.HighlightState, for indexPaths: Set<IndexPath>) {
        guard !indexPaths.isEmpty else { return }
        var allowed = indexPaths
        if let d = _delegate { allowed = d.collectionView(self, shouldChangeItemsAt: indexPaths, to: state).intersection(indexPaths) }
        guard !allowed.isEmpty else { return }
        if state == .none { _highlighted.subtract(allowed) } else { _highlighted.formUnion(allowed) }
        for ip in allowed { _visibleItems[ip]?.highlightState = state }
        _delegate?.collectionView(self, didChangeItemsAt: allowed, to: state)
    }

    // MARK: Mouse and keyboard

    /// Clicks in an item's passive content (labels, images) go to the collection view,
    /// which runs the selection; controls and editable fields keep them.
    @MainActor open override func hitTest(_ point: NSPoint) -> NSView? {
        guard let v = super.hitTest(point) else { return nil }
        if v !== self, _disappearing.values.contains(where: { $0.viewIfLoaded.map { v.isDescendant(of: $0) } ?? false }) { return self }
        guard v !== self, _itemView(containing: v) != nil else { return v }
        if let f = v as? NSTextField { return f.isEditable || f.isSelectable ? v : self }
        if v is NSControl || v.acceptsFirstResponder { return v }
        return self
    }
    /// The item whose view holds `view`, if any.
    private func _item(containing view: NSView) -> (IndexPath, NSCollectionViewItem)? {
        var v: NSView? = view
        while let cur = v, cur !== self {
            if let hit = _visibleItems.first(where: { $0.value.viewIfLoaded === cur }) { return (hit.key, hit.value) }
            v = cur.superview
        }
        return nil
    }
    private func _itemView(containing view: NSView) -> NSView? { _item(containing: view)?.1.viewIfLoaded }

    @MainActor open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        _collapseOnMouseUp = nil
        // A press on an item may become a drag (selectable or not, as in AppKit).
        _mouseDownEvent = event
        _pressPoint = p
        _dragAttempted = false
        _dragCandidate = indexPathForItem(at: p)
        guard _isSelectable else { super.mouseDown(with: event); return }
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        let hit = _dragCandidate
        _pressDidToggle = false
        _pressed = hit
        let flags = event.modifierFlags
        guard let ip = hit else {
            // Empty space: a rubber band starts here; without Cmd or Shift it replaces the
            // selection, so the click alone clears it.
            let extends = _allowsMultipleSelection && (flags.contains(.command) || flags.contains(.shift))
            if !extends && _allowsEmptySelection { _userSetSelection([]) }
            if _allowsMultipleSelection {
                _marqueeStart = p
                _marqueeRect = NSRect(origin: p, size: .zero)
                _marqueeBase = extends ? _selection : []
            }
            return
        }
        if _allowsMultipleSelection && flags.contains(.command) {
            _pressDidToggle = true
            _anchor = ip
            if _selection.contains(ip) {
                _setHighlight(.forDeselection, for: [ip])
                _userSetSelection(_selection.subtracting([ip]))
            } else {
                _setHighlight(.forSelection, for: [ip])
                _userSetSelection(_selection.union([ip]))
            }
        } else if _allowsMultipleSelection && flags.contains(.shift), let anchor = _anchor {
            let range = _indexPaths(between: anchor, and: ip)
            _setHighlight(.forSelection, for: range)
            _userSetSelection(_selection.union(range))
        } else {
            _anchor = ip
            _setHighlight(.forSelection, for: [ip])
            // A press on one of several selected items keeps them (they may be dragged
            // together); the click alone selects just it on mouse-up, as in AppKit.
            if !_selection.contains(ip) { _userSetSelection([ip]) } else if _selection.count > 1 { _collapseOnMouseUp = ip }
        }
    }
    @MainActor open override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let start = _dragCandidate, !_dragAttempted, _marqueeStart == nil, abs(p.x - _pressPoint.x) > 3 || abs(p.y - _pressPoint.y) > 3 {
            _dragAttempted = true
            if _beginItemDrag(from: start, event: event) {
                // The drag session has the mouse now: the press is over.
                _pressed = nil
                _dragCandidate = nil
                _collapseOnMouseUp = nil
                if !_highlighted.isEmpty { _setHighlight(.none, for: _highlighted) }
                return
            }
        }
        guard _isSelectable else { return }
        if let origin = _marqueeStart {
            // Rubber band: the items whose frames the rect touches join the base selection.
            let old = _marqueeRect
            _marqueeRect = NSRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x - origin.x), height: abs(p.y - origin.y))
            _prepareLayoutIfNeeded()
            let hits = (_layout?.layoutAttributesForElements(in: _marqueeRect) ?? []).filter { $0.representedElementCategory == .item && !$0.isHidden && _rectsOverlap($0.frame, _marqueeRect) }.compactMap(\.indexPath)
            _userSetSelection(_marqueeBase.union(hits))
            _ = old
            _showMarquee()
            return
        }
        guard let start = _pressed, _allowsMultipleSelection, !_pressDidToggle else { return }
        // Sweeping across items selects the range (once the pointer reaches another item).
        guard let ip = indexPathForItem(at: p), ip != start || _collapseOnMouseUp == nil && _selection.count > 1 else { return }
        _collapseOnMouseUp = nil
        let range = _indexPaths(between: start, and: ip)
        _userSetSelection(range)
    }
    @MainActor open override func mouseUp(with event: NSEvent) {
        let pressed = _pressed
        _pressed = nil
        _dragCandidate = nil
        _mouseDownEvent = nil
        guard _isSelectable else { super.mouseUp(with: event); return }
        if let ip = _collapseOnMouseUp {
            _collapseOnMouseUp = nil
            _userSetSelection([ip])
        }
        if _marqueeStart != nil {
            _marqueeStart = nil
            _marqueeRect = .zero
            _showMarquee()
        }
        if !_highlighted.isEmpty { _setHighlight(.none, for: _highlighted) }
        _ = pressed
    }
    /// The rubber band's rect while a drag from empty space is in progress (else zero).
    internal var _marquee: NSRect { _marqueeStart == nil ? .zero : _marqueeRect }
    /// The rubber band is a view of its own above the elements (a view draws under its
    /// subviews, so the collection view cannot paint it in `draw`).
    private var _marqueeView: _NSCollectionViewMarqueeView?
    private func _showMarquee() {
        guard _marqueeStart != nil else { _marqueeView?.removeFromSuperview(); _marqueeView = nil; return }
        let v = _marqueeView ?? _NSCollectionViewMarqueeView(frame: _marqueeRect)
        _marqueeView = v
        v.frame = _marqueeRect
        v.isHidden = _marqueeRect.isEmpty
        addSubview(v)       // (re)added: always on top
        v.needsDisplay = true
    }

    /// The index paths from one to another in order, both included.
    private func _indexPaths(between a: IndexPath, and b: IndexPath) -> Set<IndexPath> {
        let lo = min(a, b), hi = max(a, b)
        return Set(_allIndexPaths().filter { $0 >= lo && $0 <= hi })
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        guard _isSelectable else { super.keyDown(with: event); return }
        let all = _allIndexPaths()
        guard !all.isEmpty else { super.keyDown(with: event); return }
        let shift = event.modifierFlags.contains(.shift) && _allowsMultipleSelection
        let current = _selection.sorted().last ?? _anchor
        func move(to target: IndexPath?) {
            guard let target else { return }
            if shift, let anchor = _anchor {
                _userSetSelection(_indexPaths(between: anchor, and: target))
            } else {
                _anchor = target
                _userSetSelection([target])
            }
            scrollToItems(at: [target], scrollPosition: [])
        }
        switch event.charactersIgnoringModifiers {
        case "\u{F700}": move(to: _neighbour(of: current, direction: .up, all: all))        // up
        case "\u{F701}": move(to: _neighbour(of: current, direction: .down, all: all))      // down
        case "\u{F702}": move(to: _neighbour(of: current, direction: .left, all: all))      // left
        case "\u{F703}": move(to: _neighbour(of: current, direction: .right, all: all))     // right
        case "\u{F729}": move(to: all.first)                                                 // home
        case "\u{F72B}": move(to: all.last)                                                  // end
        default: super.keyDown(with: event)
        }
    }

    private enum _Direction { case up, down, left, right }
    /// The item next to `ip` on screen: for the vertical directions the nearest item
    /// whose centre is above or below, for the horizontal ones the previous or next
    /// item in order (which is the item beside it in a flow). Nothing selected yet:
    /// the first or the last item.
    private func _neighbour(of ip: IndexPath?, direction: _Direction, all: [IndexPath]) -> IndexPath? {
        guard let ip, let i = all.firstIndex(of: ip) else {
            return direction == .up || direction == .left ? all.last : all.first
        }
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        switch direction {
        case .left: return rtl ? (i + 1 < all.count ? all[i + 1] : ip) : (i > 0 ? all[i - 1] : ip)
        case .right: return rtl ? (i > 0 ? all[i - 1] : ip) : (i + 1 < all.count ? all[i + 1] : ip)
        case .up, .down:
            _prepareLayoutIfNeeded()
            guard let layout = _layout, let f = layout.layoutAttributesForItem(at: ip)?.frame else { return ip }
            var best: (IndexPath, CGFloat, CGFloat)? = nil
            for a in layout.layoutAttributesForElements(in: NSRect(origin: .zero, size: layout.collectionViewContentSize)) where a.representedElementCategory == .item {
                guard let other = a.indexPath, other != ip, !a.isHidden else { continue }
                let dy = a.frame.midY - f.midY
                guard direction == .down ? dy > 0.5 : dy < -0.5 else { continue }
                let dx = abs(a.frame.midX - f.midX)
                let d = abs(dy)
                if best == nil || d < best!.1 - 0.5 || (abs(d - best!.1) <= 0.5 && dx < best!.2) { best = (other, d, dx) }
            }
            if let b = best { return b.0 }
            // Nothing above or below (a horizontal flow): step along the order instead.
            return direction == .up ? (i > 0 ? all[i - 1] : ip) : (i + 1 < all.count ? all[i + 1] : ip)
        }
    }

    /// `selectAll:` and `deselectAll:` from the Edit menu.
    @MainActor public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action.description {
        case "selectAll:": selectAll(sender); return true
        case "deselectAll:": deselectAll(sender); return true
        default: return false
        }
    }
    @MainActor public func respondsToSelectorAction(_ action: Selector) -> Bool {
        action.description == "selectAll:" ? _allowsMultipleSelection && _isSelectable : action.description == "deselectAll:"
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/validateuserinterfaceitem(_:)
    @MainActor open func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let a = item.action else { return true }
        return respondsToSelectorAction(a)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/togglesectioncollapse(_:)
    ///
    /// Sent by a header's `sectionCollapseButton`: collapses or expands the section of
    /// the header the sender sits in (a flow layout).
    @available(macOS 10.12, *)
    @MainActor open func toggleSectionCollapse(_ sender: Any) {
        guard let flow = _layout as? NSCollectionViewFlowLayout else { return }
        var section: Int? = nil
        if let s = sender as? Int { section = s }
        else if let v = sender as? NSView {
            var cur: NSView? = v
            while let c = cur, c !== self, section == nil {
                if let hit = _visibleSupplementary.first(where: { $0.value === c }) { section = hit.key.indexPath.section }
                cur = c.superview
            }
        }
        guard let s = section else { return }
        if flow.section(atIndexIsCollapsed: s) { flow.expandSection(at: s) } else { flow.collapseSection(at: s) }
    }

    // MARK: Background

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/backgroundcolors
    ///
    /// The first colour fills the view; with a grid layout the colours stripe the rows
    /// in turn (the grid layout's own `backgroundColors` win when set).
    @MainActor open var backgroundColors: [NSColor]! {
        get { _backgroundColors }
        set { _backgroundColors = (newValue ?? []).isEmpty ? [.controlBackgroundColor] : newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/backgroundview
    @available(macOS 10.11, *)
    @MainActor open var backgroundView: NSView? {
        get { _backgroundView }
        set {
            _backgroundView?.removeFromSuperview()
            _backgroundView = newValue
            if let v = newValue { addSubview(v, positioned: .below, relativeTo: subviews.first) }
            _placeBackgroundView()
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/backgroundviewscrollswithcontent
    @available(macOS 10.12, *)
    @MainActor open var backgroundViewScrollsWithContent: Bool {
        get { _backgroundViewScrollsWithContent }
        set { _backgroundViewScrollsWithContent = newValue; _placeBackgroundView() }
    }
    private func _placeBackgroundView() {
        guard let v = _backgroundView else { return }
        let r = _backgroundViewScrollsWithContent || visibleRect.isEmpty ? bounds : visibleRect
        if v.frame != r { v.frame = r }
        if subviews.first !== v { addSubview(v, positioned: .below, relativeTo: subviews.first) }
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        guard _backgroundView == nil else { return }
        let grid = _layout as? NSCollectionViewGridLayout
        let colors = (grid?.backgroundColors ?? []).isEmpty ? _backgroundColors : grid!.backgroundColors!
        (colors.first ?? .controlBackgroundColor).setFill()
        NSBezierPath(rect: dirtyRect).fill()
        guard colors.count > 1, let grid else { return }
        _prepareLayoutIfNeeded()
        for (i, r) in grid._rowStripes.enumerated() where r.intersects(dirtyRect) {
            colors[i % colors.count].setFill()
            NSBezierPath(rect: r.intersection(dirtyRect)).fill()
        }
    }

    // MARK: Legacy (10.5) API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/content
    @MainActor open var content: [Any] {
        get { _content }
        set { _content = newValue; reloadData() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/itemprototype
    @MainActor open var itemPrototype: NSCollectionViewItem? {
        get { _itemPrototype }
        set { _itemPrototype = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/newitem(forrepresentedobject:)
    ///
    /// A copy of `itemPrototype` representing `object` (see `NSCollectionViewItem.copy`).
    @MainActor open func newItem(forRepresentedObject object: Any) -> NSCollectionViewItem {
        guard let proto = _itemPrototype, let item = proto.copy() as? NSCollectionViewItem else {
            preconditionFailure("NSCollectionView.newItem(forRepresentedObject:): no itemPrototype")
        }
        item.representedObject = object
        return item
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/minitemsize
    @MainActor open var minItemSize: NSSize {
        get { _minItemSize }
        set { _minItemSize = newValue; (_layout as? NSCollectionViewGridLayout)?.minimumItemSize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/maxitemsize
    @MainActor open var maxItemSize: NSSize {
        get { _maxItemSize }
        set { _maxItemSize = newValue; (_layout as? NSCollectionViewGridLayout)?.maximumItemSize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/maxnumberofrows
    @MainActor open var maxNumberOfRows: Int {
        get { _maxNumberOfRows }
        set { _maxNumberOfRows = newValue; (_layout as? NSCollectionViewGridLayout)?.maximumNumberOfRows = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/maxnumberofcolumns
    @MainActor open var maxNumberOfColumns: Int {
        get { _maxNumberOfColumns }
        set { _maxNumberOfColumns = newValue; (_layout as? NSCollectionViewGridLayout)?.maximumNumberOfColumns = newValue }
    }

    // MARK: Dragging source (ADR-0041)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/setdraggingsourceoperationmask(_:forlocal:)
    ///
    /// Every operation within the application and none outside it until set, as in AppKit.
    @MainActor open func setDraggingSourceOperationMask(_ dragOperationMask: NSDragOperation, forLocal localDestination: Bool) {
        if localDestination { _dragMaskLocal = dragOperationMask } else { _dragMaskRemote = dragOperationMask }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/draggingimageforitems(at:with:offset:)
    ///
    /// The visible parts of the items' views, drawn where they sit, cropped to their
    /// union; `dragImageOffset` is left at zero (the image centred under the pointer).
    @available(macOS 10.11, *)
    @MainActor open func draggingImageForItems(at indexPaths: Set<IndexPath>, with event: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage {
        _prepareLayoutIfNeeded()
        var parts: [(NSRect, NSImage)] = []
        for ip in indexPaths.sorted() {
            guard let item = _visibleItems[ip], let v = item.viewIfLoaded else { continue }
            let r = v.frame.intersection(visibleRect.isEmpty ? bounds : visibleRect)
            guard !r.isNull, r.width > 0, r.height > 0 else { continue }
            parts.append((r, _NSCollectionViewDragImages.snapshot(of: v, rect: v.convert(r, from: self))))
        }
        guard let union = parts.map({ $0.0 }).reduce(nil, { (u: NSRect?, r: NSRect) in u.map { $0.union(r) } ?? r }) else { return NSImage(size: .zero) }
        // The parts are in this (flipped) view's space; the image draws bottom-up.
        return NSImage(size: union.size, flipped: false) { _ in
            for (r, image) in parts {
                image.draw(in: NSRect(x: r.minX - union.minX, y: union.maxY - r.maxY, width: r.width, height: r.height))
            }
            return true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionview/draggingimageforitems(at:with:offset:)
    @MainActor open func draggingImageForItems(at indexes: IndexSet, with event: NSEvent, offset dragImageOffset: NSPointPointer) -> NSImage {
        draggingImageForItems(at: Set(indexes.map { IndexPath(item: $0, section: 0) }), with: event, offset: dragImageOffset)
    }

    /// Starts a drag of the pressed item (with the rest of the selection when it is
    /// selected): the delegate vets it, then provides a pasteboard writer per item (each
    /// item drags its own image components from its frame) or, failing that, writes the
    /// items to the drag pasteboard itself (one image for all).
    private func _beginItemDrag(from pressed: IndexPath, event: NSEvent) -> Bool {
        guard let d = _delegate else { return false }
        _reloadCountsIfNeeded()
        guard _isValid(pressed) else { return false }
        let indexPaths: Set<IndexPath> = _selection.contains(pressed) ? _selection : [pressed]
        let down = _mouseDownEvent ?? event
        guard d.collectionView(self, canDragItemsAt: indexPaths, with: down) else { return false }
        _prepareLayoutIfNeeded()
        var dragItems: [NSDraggingItem] = []
        var dragged = Set<IndexPath>()
        for ip in indexPaths.sorted() {
            guard let writer = d.collectionView(self, pasteboardWriterForItemAt: ip) else { continue }
            let di = NSDraggingItem(pasteboardWriter: writer)
            di.draggingFrame = _visibleItems[ip]?.viewIfLoaded?.frame ?? _layout?.layoutAttributesForItem(at: ip)?.frame ?? .zero
            if let item = _visibleItems[ip] { di.imageComponentsProvider = { [item] in MainActor.assumeIsolated { item.draggingImageComponents } } }
            dragItems.append(di)
            dragged.insert(ip)
        }
        if dragItems.isEmpty {
            let pb = NSPasteboard(name: NSPasteboard.Name(rawValue: "Apple CFPasteboard drag"))
            pb.clearContents()
            guard d.collectionView(self, writeItemsAt: indexPaths, to: pb) else { return false }
            var offset = NSPoint.zero
            let image = withUnsafeMutablePointer(to: &offset) { d.collectionView(self, draggingImageForItemsAt: indexPaths, with: down, offset: $0) }
            // Centred under the pointer, moved by the offset (y up, as AppKit's is).
            let size = image.size
            let frame = NSRect(x: _pressPoint.x - size.width / 2 + offset.x, y: _pressPoint.y - size.height / 2 - offset.y, width: size.width, height: size.height)
            for (i, pi) in (pb.pasteboardItems ?? []).enumerated() {
                let di = NSDraggingItem(pasteboardWriter: pi)
                if i == 0 { di.setDraggingFrame(frame, contents: image) } else { di.draggingFrame = frame }
                dragItems.append(di)
            }
            guard !dragItems.isEmpty else { return false }
            dragged = indexPaths
        }
        _draggedIndexPaths = dragged
        _ = beginDraggingSession(with: dragItems, event: event, source: self)
        return true
    }

    // NSDraggingSource
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession(_:sourceoperationmaskfor:)
    @MainActor open func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? _dragMaskLocal : _dragMaskRemote
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession(_:willbeginat:)
    @MainActor open func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        _delegate?.collectionView(self, draggingSession: session, willBeginAt: screenPoint, forItemsAt: _draggedIndexPaths)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsdraggingsource/draggingsession(_:endedat:operation:)
    @MainActor open func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        _delegate?.collectionView(self, draggingSession: session, endedAt: screenPoint, dragOperation: operation)
        _draggedIndexPaths = []
    }
    /// A destination asked for the promised files (`NSDraggingInfo.namesOfPromisedFilesDropped(atDestination:)`):
    /// the delegate creates them for the dragged items.
    internal func _namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
        guard let d = _delegate, !_draggedIndexPaths.isEmpty else { return nil }
        return d.collectionView(self, namesOfPromisedFilesDroppedAtDestination: dropDestination, forDraggedItemsAt: _draggedIndexPaths)
    }

    // MARK: Drop destination (ADR-0041)
    //
    // With dragged types registered, the collection view proposes a target under the
    // pointer from the layout's `layoutAttributesForDropTarget(at:)`: over an item, on it
    // when the pointer is nearer the item's middle than its edges, else before it or the
    // next one; over a gap, before the item after it. The delegate's `validateDrop` may
    // retarget; the target shows as the item's `.asDropTarget` highlight (on) or the
    // inter-item gap indicator (before), and `acceptDrop` gets it.

    @MainActor open override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        _delegate?.collectionView(self, updateDraggingItemsForDrag: sender)
        return _validateDrop(sender)
    }
    @MainActor open override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        _autoscrollForDrag(sender)
        return _validateDrop(sender)
    }
    @MainActor open override func draggingExited(_ sender: (any NSDraggingInfo)?) { _clearDropTarget() }
    @MainActor open override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { _dropTarget != nil }
    @MainActor open override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let target = _dropTarget, let d = _delegate else { return false }
        return d.collectionView(self, acceptDrop: sender, indexPath: target.indexPath, dropOperation: target.operation)
    }
    @MainActor open override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { _clearDropTarget() }
    @MainActor open override func draggingEnded(_ sender: any NSDraggingInfo) { _clearDropTarget() }

    /// The target AppKit proposes for a point (before validation).
    internal func _proposedDropTarget(at p: NSPoint) -> (indexPath: IndexPath, operation: NSCollectionView.DropOperation, gap: NSCollectionViewLayoutAttributes?) {
        _prepareLayoutIfNeeded()
        let end: IndexPath = {
            let s = max(0, _itemCounts.count - 1)
            return IndexPath(item: _itemCounts.isEmpty ? 0 : _itemCounts[s], section: s)
        }()
        guard let layout = _layout, let a = layout.layoutAttributesForDropTarget(at: p), let ip = a.indexPath else { return (end, .before, nil) }
        switch a.representedElementCategory {
        case .item:
            // Along the line: x, or y when lines run down (a horizontal flow).
            let vertical = layout._linesRunVertically
            let f = a.frame
            let (lo, hi, v) = vertical ? (f.minY, f.maxY, p.y) : (f.minX, f.maxX, p.x)
            let mid = (lo + hi) / 2
            if abs(v - mid) < min(v - lo, hi - v) { return (ip, .on, nil) }
            var trailing = v > mid
            if !vertical && userInterfaceLayoutDirection == .rightToLeft { trailing.toggle() }
            let target = trailing ? IndexPath(item: ip.item + 1, section: ip.section) : ip
            return (target, .before, layout.layoutAttributesForInterItemGap(before: target))
        case .interItemGap:
            return (ip, .before, a)
        default:
            return (end, .before, nil)
        }
    }

    private func _validateDrop(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let d = _delegate, _layout != nil else { _clearDropTarget(); return [] }
        let p = convert(info.draggingLocation, from: nil)
        let proposal = _proposedDropTarget(at: p)
        var path = NSIndexPath(indexes: [proposal.indexPath.section, proposal.indexPath.item], length: 2)
        var operation = proposal.operation
        let result = withUnsafeMutablePointer(to: &path) { pp in
            withUnsafeMutablePointer(to: &operation) { op in
                d.collectionView(self, validateDrop: info, proposedIndexPath: AutoreleasingUnsafeMutablePointer(pp), dropOperation: op)
            }
        }
        let ip = path.length >= 2 ? IndexPath(item: path.index(atPosition: 1), section: path.index(atPosition: 0)) : proposal.indexPath
        guard !result.isEmpty else { _clearDropTarget(); return [] }
        let gap = ip == proposal.indexPath && operation == .before ? proposal.gap : nil
        guard _showDropTarget(ip, operation: operation, gap: gap) else { _clearDropTarget(); return [] }
        return result
    }

    /// Shows the drop target; false when the delegate refuses the item's drop highlight.
    private func _showDropTarget(_ ip: IndexPath, operation: NSCollectionView.DropOperation, gap: NSCollectionViewLayoutAttributes?) -> Bool {
        if operation == .on {
            _hideGapIndicator()
            if _dropHighlight != ip {
                _clearDropHighlight()
                var allowed: Set<IndexPath> = [ip]
                if let d = _delegate { allowed = d.collectionView(self, shouldChangeItemsAt: [ip], to: .asDropTarget).intersection([ip]) }
                guard !allowed.isEmpty else { return false }
                _dropHighlight = ip
                _visibleItems[ip]?.highlightState = .asDropTarget
                _delegate?.collectionView(self, didChangeItemsAt: [ip], to: .asDropTarget)
            }
        } else {
            _clearDropHighlight()
            let frame = (gap ?? _layout?.layoutAttributesForInterItemGap(before: ip))?.frame
            _showGapIndicator(at: ip, frame: frame)
        }
        _dropTarget = (ip, operation)
        return true
    }
    private func _clearDropHighlight() {
        guard let ip = _dropHighlight else { return }
        _dropHighlight = nil
        _visibleItems[ip]?.highlightState = _highlighted.contains(ip) ? .forSelection : .none
        _delegate?.collectionView(self, didChangeItemsAt: [ip], to: .none)
    }
    private func _clearDropTarget() {
        _dropTarget = nil
        _clearDropHighlight()
        _hideGapIndicator()
    }

    /// The inter-item gap indicator: the data source's view when a class or nib is
    /// registered for `elementKindInterItemGapIndicator`, else a bar in the accent colour.
    private func _showGapIndicator(at ip: IndexPath, frame: NSRect?) {
        guard let frame, !frame.isNull else { _hideGapIndicator(); return }
        let kind = NSCollectionView.elementKindInterItemGapIndicator
        let registered = _supplementaryClasses.keys.contains { $0.hasPrefix(kind + "\u{1}") } || _supplementaryNibs.keys.contains { $0.hasPrefix(kind + "\u{1}") }
        let v: NSView
        if let g = _gapIndicator, registered == !(g is _NSCollectionViewGapIndicatorView) {
            v = g
        } else {
            _gapIndicator?.removeFromSuperview()
            if registered, let ds = _dataSource { v = ds.collectionView(self, viewForSupplementaryElementOfKind: kind, at: ip) }
            else { v = _NSCollectionViewGapIndicatorView(frame: .zero) }
            _gapIndicator = v
        }
        var f = frame
        // A gap thinner than the bar still shows it, centred.
        if f.width < 4 && f.width <= f.height { f = f.insetBy(dx: (f.width - 4) / 2, dy: 0) }
        if f.height < 4 && f.height < f.width { f = f.insetBy(dx: 0, dy: (f.height - 4) / 2) }
        if v.frame != f { v.frame = f }
        v.isHidden = false
        if subviews.last !== v { addSubview(v) }
        v.needsDisplay = true
    }
    private func _hideGapIndicator() {
        guard let g = _gapIndicator else { return }
        g.removeFromSuperview()
        _gapIndicator = nil
    }
    /// The drop target being shown, for tests and the demo.
    internal var _currentDropTarget: (indexPath: IndexPath, operation: NSCollectionView.DropOperation)? { _dropTarget }
    internal var _gapIndicatorView: NSView? { _gapIndicator }

    /// Scrolls while a drag hovers within 16 points of the visible rect's edge.
    private func _autoscrollForDrag(_ info: any NSDraggingInfo) {
        guard let clip = superview as? NSClipView else { return }
        let p = convert(info.draggingLocation, from: nil)
        let v = visibleRect, margin: CGFloat = 16, step: CGFloat = 10
        var o = clip.bounds.origin
        if p.y < v.minY + margin { o.y -= step } else if p.y > v.maxY - margin { o.y += step }
        if p.x < v.minX + margin { o.x -= step } else if p.x > v.maxX - margin { o.x += step }
        o.x = max(0, min(o.x, frame.width - clip.bounds.width))
        o.y = max(0, min(o.y, frame.height - clip.bounds.height))
        guard o != clip.bounds.origin else { return }
        clip.scroll(to: o)
        (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
    }

    // MARK: Accessibility (ADR-0013)
    //
    // AXGrid whose children are the headers and the items on screen, each item's view
    // an AXGroup at its index (in order) that reports selected, labelled by its text
    // field unless the view labels itself. Selecting through assistive technology runs
    // the same path as a click, so delegates hear it.
    open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .grid }
    open override func accessibilityChildren() -> [Any]? {
        if let c = _a11y.children { return c }
        return MainActor.assumeIsolated {
            _updateVisibleElements()
            var out: [Any] = []
            @MainActor func add(_ v: NSView) {
                guard !v.isHidden, !v.isAccessibilityHidden() else { return }
                if v.isAccessibilityElement() { out.append(v) } else if let c = v.accessibilityChildren() { out.append(contentsOf: c) }
            }
            for s in 0..<_itemCounts.count {
                for (key, v) in _visibleSupplementary.sorted(by: { $0.key.indexPath < $1.key.indexPath }) where key.indexPath.section == s { add(v) }
                for (ip, item) in _visibleItems.sorted(by: { $0.key < $1.key }) where ip.section == s { add(item.view) }
            }
            return out
        }
    }
    open func accessibilitySelectedChildren() -> [Any]? {
        MainActor.assumeIsolated { _visibleItems.filter { _selection.contains($0.key) }.sorted { $0.key < $1.key }.map { $0.value.view } }
    }
    override func _accessibilityAllowsMultipleSelection() -> Bool { _allowsMultipleSelection }
    override func _accessibilityIsFocusable() -> Bool { _isSelectable && super._accessibilityIsFocusable() }

    /// Item views are elements of their own (unless the view says otherwise), at their
    /// flat index, selected or not, labelled by the text field.
    private func _refreshItemAccessibility() {
        var flat: [IndexPath: Int] = [:]
        for (i, ip) in _allIndexPaths().enumerated() { flat[ip] = i }
        for (ip, item) in _visibleItems {
            let v = item.view
            if v._a11y.isElement == nil { v._a11y.isElement = true }
            if v._a11y.role == nil { v._a11y.role = .group }
            v._a11y.index = flat[ip]
            v._a11y.isSelected = _selection.contains(ip)
            if v._a11y.label == nil || item._accessibilityLabelIsOurs {
                let text = item.textField?.stringValue
                v._a11y.label = (text?.isEmpty ?? true) ? nil : text
                item._accessibilityLabelIsOurs = v._a11y.label != nil
            }
        }
    }
    private func _clearItemAccessibility(_ item: NSCollectionViewItem) {
        guard let v = item.viewIfLoaded else { return }
        v._a11y.index = nil
        v._a11y.isSelected = nil
        if item._accessibilityLabelIsOurs { v._a11y.label = nil; item._accessibilityLabelIsOurs = false }
    }
    private func _accessibilityStructureChangedHere() { if window != nil { _accessibilityNotify(.structure(_accessibilityElementID)) } }
    /// An item's view (not what is inside it) is selectable through assistive technology.
    override func _accessibilityChildIsSelectable(_ view: NSView) -> Bool { _visibleItems.values.contains { $0.viewIfLoaded === view } }
    /// Pressing an item selects it (as a click would).
    override func _accessibilityChildPressed(_ view: NSView) -> Bool {
        guard _isSelectable, let (ip, _) = _item(containing: view) else { return false }
        _anchor = ip
        return _userSetSelection([ip])
    }
    override func _accessibilityChild(_ view: NSView, setSelected selected: Bool, extending: Bool) -> Bool? {
        guard let (ip, _) = _item(containing: view) else { return nil }
        guard _isSelectable else { return false }
        if selected {
            _anchor = ip
            return _userSetSelection(extending && _allowsMultipleSelection ? _selection.union([ip]) : [ip])
        }
        return _userSetSelection(_selection.subtracting([ip]))
    }
}

/// The rubber band drawn over the items while the mouse drags from empty space.
@MainActor internal final class _NSCollectionViewMarqueeView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(rect: bounds).fill()
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        let p = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        p.lineWidth = 1
        p.stroke()
    }
}

/// The default inter-item gap indicator: a rounded bar along the gap's long side.
@MainActor internal final class _NSCollectionViewGapIndicatorView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        let b = bounds
        let bar = b.height >= b.width
            ? NSRect(x: b.midX - 1.5, y: b.minY, width: 3, height: b.height)
            : NSRect(x: b.minX, y: b.midY - 1.5, width: b.width, height: 3)
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// Snapshots of item views for drag images.
@MainActor internal enum _NSCollectionViewDragImages {
    /// What `view` draws in `rect` (its own space), with its subviews.
    static func snapshot(of view: NSView, rect: NSRect? = nil) -> NSImage {
        let r = rect ?? view.bounds
        let image = NSImage(size: r.size)
        guard r.width > 0, r.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: r) else { return image }
        view.cacheDisplay(in: r, to: rep)
        image.addRepresentation(rep)
        return image
    }
}

/// The changes recorded between `performBatchUpdates` begin and end.
internal struct _NSCollectionViewPendingUpdates {
    var insertItems = Set<IndexPath>()
    var deleteItems = Set<IndexPath>()
    var reloadItems = Set<IndexPath>()
    var moveItems: [(IndexPath, IndexPath)] = []
    var insertSections = IndexSet()
    var deleteSections = IndexSet()
    var reloadSections = IndexSet()
    var moveSections: [(Int, Int)] = []
    var isEmpty: Bool {
        insertItems.isEmpty && deleteItems.isEmpty && reloadItems.isEmpty && moveItems.isEmpty
            && insertSections.isEmpty && deleteSections.isEmpty && reloadSections.isEmpty && moveSections.isEmpty
    }
}

/// The coder a registered view class is constructed with: it decodes nothing, so a
/// class that chains to `NSView.init?(coder:)` comes out as a zero-frame view.
internal final class _NSCollectionViewPlaceholderCoder: NSCoder, @unchecked Sendable {
    override var allowsKeyedCoding: Bool { true }
    override func containsValue(forKey key: String) -> Bool { false }
    override func decodeObject(forKey key: String) -> Any? { nil }
    override func decodeBool(forKey key: String) -> Bool { false }
    override func decodeInteger(forKey key: String) -> Int { 0 }
    override func decodeDouble(forKey key: String) -> Double { 0 }
    override func decodeFloat(forKey key: String) -> Float { 0 }
}
