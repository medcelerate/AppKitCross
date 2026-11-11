// NSTableViewDiffableDataSource
// Hand-written (ADR-0029). Seeded from the generated stub.
//
// Becomes the table's data source and answers the table's view questions itself (cell views,
// row views, section header rows), as on macOS, where the delegate's view methods are not asked
// while a diffable data source is attached; the delegate keeps everything else (heights,
// selection). Rows are the snapshot flattened: each section contributes a header row when
// `sectionHeaderViewProvider` is set, then its items.
//
// `apply` diffs the current rows against the new ones (IdentifierDiff in Support) and drives
// `beginUpdates`, one `removeRows`, `insertRows`/`moveRow` in new order and `endUpdates`, then
// `reloadData(forRowIndexes:columnIndexes:)` for the reloaded items and sections. Row views
// follow their rows, so moved rows keep their cells. `animatingDifferences` chooses between
// `defaultRowAnimation` and no animation for those calls (the port's table does not animate
// rows yet, so both land at once). `apply` may be called off the main thread: the update then
// runs synchronously on the main queue.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Answers the table's view questions for its data source (see NSTableView's subclass hooks).
@MainActor internal protocol _NSTableViewContentProviding: AnyObject {
    func _tableView(_ tableView: NSTableView, viewFor column: NSTableColumn, row: Int) -> NSView?
    func _tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView?
    func _tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool
}

/// Runs `body` on the main actor: inline on the main thread, otherwise synchronously on the
/// main queue (as a diffable data source's `apply` allows a background caller).
internal func _onMainActor<T>(_ body: @MainActor () -> T) -> T {
    if Thread.isMainThread { return MainActor.assumeIsolated(body) }
    return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource
@available(macOS 11.0, *)
open class NSTableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>: NSObject, NSTableViewDataSource where SectionIdentifierType : Hashable, ItemIdentifierType : Hashable {
    internal enum _Row: Hashable {
        case section(SectionIdentifierType)
        case item(ItemIdentifierType)
    }

    private weak var _tableView: NSTableView?
    private let _cellProvider: CellProvider
    private var _snapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>()
    private var _rows: [_Row] = []
    private var _rowOfItem: [ItemIdentifierType: Int] = [:]
    private var _rowOfSection: [SectionIdentifierType: Int] = [:]     // first row of the section's content
    private var _sectionOfRow: [SectionIdentifierType] = []
    private var _rowViewProvider: RowProvider?
    private var _sectionHeaderViewProvider: SectionHeaderViewProvider?
    private var _defaultRowAnimation: NSTableView.AnimationOptions = .effectFade
    private let _lock = NSLock()

    /// Sets itself as `tableView`'s data source (the table holds it weakly: keep a reference).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/init(tableview:cellprovider:)
    public init(tableView: NSTableView, cellProvider: @escaping NSTableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.CellProvider) {
        _tableView = tableView
        _cellProvider = cellProvider
        super.init()
        _onMainActor { tableView.dataSource = self }
    }

    // MARK: Providers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/rowviewprovider
    open var rowViewProvider: NSTableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.RowProvider? {
        get { _rowViewProvider }
        set { _rowViewProvider = newValue }
    }
    /// Setting it adds (or, set to nil, removes) a header row per section.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/sectionheaderviewprovider
    open var sectionHeaderViewProvider: NSTableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>.SectionHeaderViewProvider? {
        get { _sectionHeaderViewProvider }
        set {
            let hadHeaders = _sectionHeaderViewProvider != nil
            _sectionHeaderViewProvider = newValue
            guard hadHeaders != (newValue != nil) else { return }
            _rebuildRows()
            _onMainActor { _tableView?.reloadData() }
        }
    }
    /// The animation `apply(_:animatingDifferences:)` passes to the table when animating.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/defaultrowanimation
    open var defaultRowAnimation: NSTableView.AnimationOptions {
        get { _defaultRowAnimation }
        set { _defaultRowAnimation = newValue }
    }

    // MARK: Snapshots

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/snapshot()
    open func snapshot() -> NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType> {
        _lock.lock(); defer { _lock.unlock() }
        return _snapshot
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/apply(_:animatingdifferences:completion:)
    open func apply(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animatingDifferences: Bool, completion: (() -> Void)? = nil) {
        _onMainActor { _apply(snapshot, animating: animatingDifferences) }
        completion?()
    }

    @MainActor private func _apply(_ snapshot: NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>, animating: Bool) {
        let oldRows = _rows
        let oldSnapshot = _snapshot
        _lock.lock()
        _snapshot = snapshot._withoutReloads
        _lock.unlock()
        _rebuildRows()
        guard let tableView = _tableView, tableView.dataSource === self else { return }

        let animation: NSTableView.AnimationOptions = animating ? _defaultRowAnimation : []
        let edits = _IdentifierDiff.sequentialEdits(from: oldRows, to: _rows)
        if !edits.isEmpty {
            tableView.beginUpdates()
            for edit in edits {
                switch edit {
                case .remove(let rows): tableView.removeRows(at: rows, withAnimation: animation)
                case .insert(let rows): tableView.insertRows(at: rows, withAnimation: animation)
                case .move(let from, let to): tableView.moveRow(at: from, to: to)
                }
            }
            tableView.endUpdates()
        }
        // Reloads: rows that were there before and are marked in the applied snapshot.
        var reload = IndexSet()
        let old = Set(oldRows)
        for id in snapshot._reloadedItems where old.contains(.item(id)) {
            if let r = _rowOfItem[id] { reload.insert(r) }
        }
        for s in snapshot._reloadedSections where oldSnapshot.indexOfSection(s) != nil {
            guard let first = _rowOfSection[s] else { continue }
            let count = (_sectionHeaderViewProvider == nil ? 0 : 1) + _snapshot.numberOfItems(inSection: s)
            if count > 0 { reload.insert(integersIn: first..<(first + count)) }
        }
        if !reload.isEmpty {
            tableView.reloadData(forRowIndexes: reload, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        }
    }

    private func _rebuildRows() {
        let headers = _sectionHeaderViewProvider != nil
        var rows: [_Row] = []
        var rowOfItem: [ItemIdentifierType: Int] = [:]
        var rowOfSection: [SectionIdentifierType: Int] = [:]
        var sectionOfRow: [SectionIdentifierType] = []
        for (section, items) in _snapshot._contents {
            rowOfSection[section] = rows.count
            if headers { rows.append(.section(section)); sectionOfRow.append(section) }
            for id in items {
                rowOfItem[id] = rows.count
                rows.append(.item(id))
                sectionOfRow.append(section)
            }
        }
        _rows = rows
        _rowOfItem = rowOfItem
        _rowOfSection = rowOfSection
        _sectionOfRow = sectionOfRow
    }

    // MARK: Rows and identifiers

    /// Nil for a section header row.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/itemidentifier(forrow:)
    open func itemIdentifier(forRow row: Int) -> ItemIdentifierType? {
        guard _rows.indices.contains(row), case .item(let id) = _rows[row] else { return nil }
        return id
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/row(foritemidentifier:)
    open func row(forItemIdentifier identifier: ItemIdentifierType) -> Int? { _rowOfItem[identifier] }
    /// The section a row (header or item) belongs to.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/sectionidentifier(forrow:)
    open func sectionIdentifier(forRow row: Int) -> SectionIdentifierType? {
        _sectionOfRow.indices.contains(row) ? _sectionOfRow[row] : nil
    }
    /// The section's header row, or (without headers) its first item's row; nil for an empty
    /// section without a header.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/row(forsectionidentifier:)
    open func row(forSectionIdentifier identifier: SectionIdentifierType) -> Int? {
        guard let r = _rowOfSection[identifier], r < _rows.count, sectionIdentifier(forRow: r) == identifier else { return nil }
        return r
    }

    // MARK: NSTableViewDataSource

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstableviewdiffabledatasource/numberofrows(in:)
    @MainActor open func numberOfRows(in tableView: NSTableView) -> Int { _rows.count }
}

extension NSTableViewDiffableDataSource: _NSTableViewContentProviding {
    @MainActor func _tableView(_ tableView: NSTableView, viewFor column: NSTableColumn, row: Int) -> NSView? {
        guard _rows.indices.contains(row) else { return nil }
        switch _rows[row] {
        case .item(let id): return _cellProvider(tableView, column, row, id)
        case .section(let s): return _sectionHeaderViewProvider?(tableView, row, s)
        }
    }
    @MainActor func _tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let provider = _rowViewProvider, _rows.indices.contains(row) else { return nil }
        switch _rows[row] {
        case .item(let id): return provider(tableView, row, AnyHashable(id))
        case .section(let s): return provider(tableView, row, AnyHashable(s))
        }
    }
    @MainActor func _tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard _rows.indices.contains(row), case .section = _rows[row] else { return false }
        return true
    }
}
