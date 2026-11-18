// NSCollectionViewDiffableDataSource
// Hand-written (ADR-0029). Seeded from the generated stub.
//
// Becomes the collection view's data source. `apply` diffs the sections (IdentifierDiff in
// Support), then the items of every section present on both sides, and issues one
// `performBatchUpdates` in the collection view's batch convention: deletes and reloads address the
// old index paths, inserts the new ones, moves both. Items that keep their place (the longest run
// common to the old and new order of their section) are left alone, so their item objects stay.
// An item that crosses into or out of an inserted, deleted or reloaded section is an insert or a
// delete on the other side (the section operation covers its own side). `animatingDifferences`
// runs the batch through the view's animator or inside a zero-duration animation group.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource
@available(macOS 10.15, *)
open class NSCollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>: NSObject, NSCollectionViewDataSource where SectionIdentifierType : Hashable, ItemIdentifierType : Hashable {
    private weak var _collectionView: NSCollectionView?
    private let _itemProvider: ItemProvider
    private var _supplementaryViewProvider: SupplementaryViewProvider?
    private var _snapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()
    private var _sectionItems: [[ItemIdentifierType]] = []
    private var _indexPathOfItem: [ItemIdentifierType: IndexPath] = [:]
    private let _lock = NSLock()

    /// Sets itself as `collectionView`'s data source (held weakly: keep a reference).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/init(collectionview:itemprovider:)
    public init(collectionView: NSCollectionView, itemProvider: @escaping NSCollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.ItemProvider) {
        _collectionView = collectionView
        _itemProvider = itemProvider
        super.init()
        _onMainActor { collectionView.dataSource = self }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/supplementaryviewprovider
    open var supplementaryViewProvider: NSCollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.SupplementaryViewProvider? {
        get { _supplementaryViewProvider }
        set { _supplementaryViewProvider = newValue }
    }

    // MARK: Snapshots

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/snapshot()
    open func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> {
        _lock.lock(); defer { _lock.unlock() }
        return _snapshot
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/apply(_:animatingdifferences:completion:)
    open func apply(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Bool = true, completion: (() -> Void)? = nil) {
        _onMainActor { _apply(snapshot, animating: animatingDifferences) }
        completion?()
    }

    @MainActor private func _apply(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animating: Bool) {
        let old = _snapshot
        let new = snapshot._withoutReloads
        let updates = _Updates(from: old, to: snapshot)
        let install = {
            self._lock.lock()
            self._snapshot = new
            self._lock.unlock()
            self._rebuildIndex()
        }
        guard let collectionView = _collectionView, collectionView.dataSource === self, !updates.isEmpty else { install(); return }
        // The view must know the old counts before the batch installs the new ones.
        _ = collectionView.numberOfSections
        let changes: () -> Void = {
            install()
            updates.issue(to: collectionView)
        }
        if animating {
            collectionView.animator().performBatchUpdates(changes, completionHandler: nil)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                collectionView.performBatchUpdates(changes, completionHandler: nil)
            }
        }
    }

    private func _rebuildIndex() {
        _sectionItems = _snapshot._contents.map { $0.items }
        var map: [ItemIdentifierType: IndexPath] = [:]
        for (s, items) in _sectionItems.enumerated() {
            for (i, id) in items.enumerated() { map[id] = IndexPath(item: i, section: s) }
        }
        _indexPathOfItem = map
    }

    /// The batch for one apply.
    private struct _Updates {
        var deleteSections = IndexSet()
        var insertSections = IndexSet()
        var moveSections: [(Int, Int)] = []
        var reloadSections = IndexSet()
        var deleteItems = Set<IndexPath>()
        var insertItems = Set<IndexPath>()
        var moveItems: [(IndexPath, IndexPath)] = []
        var reloadItems = Set<IndexPath>()

        var isEmpty: Bool {
            deleteSections.isEmpty && insertSections.isEmpty && moveSections.isEmpty && reloadSections.isEmpty
                && deleteItems.isEmpty && insertItems.isEmpty && moveItems.isEmpty && reloadItems.isEmpty
        }

        init(from old: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, to new: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>) {
            let oldSections = old.sectionIdentifiers, newSections = new.sectionIdentifiers
            let sections = _IdentifierDiff(from: oldSections, to: newSections)
            deleteSections = IndexSet(sections.deletes)
            insertSections = IndexSet(sections.inserts)
            moveSections = sections.moves.map { ($0.from, $0.to) }
            for s in new._reloadedSections { if let i = old.indexOfSection(s) { reloadSections.insert(i) } }

            // Sections on both sides that are not reloaded: their items are diffed. Items
            // elsewhere are covered by the section operations.
            var plainOld: [Int: Int] = [:]                 // old section index → new
            for pair in sections.stays + sections.moves where !reloadSections.contains(pair.from) { plainOld[pair.from] = pair.to }
            let plainNew = Set(plainOld.values)
            func oldPath(_ id: ItemIdentifierType) -> IndexPath? {
                guard let s = old.sectionIdentifier(containingItem: id), let si = old.indexOfSection(s),
                      let i = old.itemIdentifiers(inSection: s).firstIndex(of: id) else { return nil }
                return IndexPath(item: i, section: si)
            }
            var newPath: [ItemIdentifierType: IndexPath] = [:]
            for (si, entry) in new._contents.enumerated() {
                for (i, id) in entry.items.enumerated() { newPath[id] = IndexPath(item: i, section: si) }
            }
            var stays = Set<ItemIdentifierType>()
            for (os, ns) in plainOld {
                let a = old._items(at: os), b = new._items(at: ns)
                let d = _IdentifierDiff(from: a, to: b)
                for pair in d.stays { stays.insert(a[pair.from]) }
            }
            // Old side: everything in a plain section that does not stay moves or goes.
            for os in plainOld.keys.sorted() {
                for (i, id) in old._items(at: os).enumerated() where !stays.contains(id) {
                    let from = IndexPath(item: i, section: os)
                    if let to = newPath[id], plainNew.contains(to.section) { moveItems.append((from, to)) } else { deleteItems.insert(from) }
                }
            }
            // New side: everything in a plain section that neither stays nor moved in is new.
            for ns in plainNew.sorted() {
                for (i, id) in new._items(at: ns).enumerated() where !stays.contains(id) {
                    if let from = oldPath(id), plainOld[from.section] != nil { continue }
                    insertItems.insert(IndexPath(item: i, section: ns))
                }
            }
            // Reloads of items that survive in plain sections, at their old index paths.
            for id in new._reloadedItems {
                guard let from = oldPath(id), plainOld[from.section] != nil, let to = newPath[id], plainNew.contains(to.section) else { continue }
                reloadItems.insert(from)
            }
        }

        @MainActor func issue(to cv: NSCollectionView) {
            if !deleteSections.isEmpty { cv.deleteSections(deleteSections) }
            if !insertSections.isEmpty { cv.insertSections(insertSections) }
            for (a, b) in moveSections { cv.moveSection(a, toSection: b) }
            if !reloadSections.isEmpty { cv.reloadSections(reloadSections) }
            if !deleteItems.isEmpty { cv.deleteItems(at: deleteItems) }
            if !insertItems.isEmpty { cv.insertItems(at: insertItems) }
            for (a, b) in moveItems { cv.moveItem(at: a, to: b) }
            if !reloadItems.isEmpty { cv.reloadItems(at: reloadItems) }
        }
    }

    // MARK: Identifiers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/itemidentifier(for:)
    open func itemIdentifier(for indexPath: IndexPath) -> ItemIdentifierType? {
        guard indexPath.count == 2, _sectionItems.indices.contains(indexPath.section),
              _sectionItems[indexPath.section].indices.contains(indexPath.item) else { return nil }
        return _sectionItems[indexPath.section][indexPath.item]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/indexpath(for:)
    open func indexPath(for itemIdentifier: ItemIdentifierType) -> IndexPath? { _indexPathOfItem[itemIdentifier] }

    // MARK: NSCollectionViewDataSource

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/numberofsections(in:)
    @MainActor open func numberOfSections(in collectionView: NSCollectionView) -> Int { _sectionItems.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/collectionview(_:numberofitemsinsection:)
    @MainActor open func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        _sectionItems.indices.contains(section) ? _sectionItems[section].count : 0
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/collectionview(_:itemforrepresentedobjectat:)
    @MainActor open func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard let id = itemIdentifier(for: indexPath) else {
            preconditionFailure("NSCollectionViewDiffableDataSource: no item at \(indexPath)")
        }
        guard let item = _itemProvider(collectionView, indexPath, id) else {
            preconditionFailure("NSCollectionViewDiffableDataSource: the item provider returned nil for \(id) at \(indexPath)")
        }
        return item
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/collectionview(_:viewforsupplementaryelementofkind:at:)
    @MainActor open func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        guard let provider = _supplementaryViewProvider else {
            preconditionFailure("NSCollectionViewDiffableDataSource: the layout asked for a \(kind) view at \(indexPath) but supplementaryViewProvider is nil")
        }
        guard let view = provider(collectionView, kind, indexPath) else {
            preconditionFailure("NSCollectionViewDiffableDataSource: the supplementary view provider returned nil for \(kind) at \(indexPath)")
        }
        return view
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscollectionviewdiffabledatasource/description()
    open func description() -> String {
        let s = snapshot()
        return "<NSCollectionViewDiffableDataSource: \(s.numberOfSections) sections, \(s.numberOfItems) items>"
    }
}
