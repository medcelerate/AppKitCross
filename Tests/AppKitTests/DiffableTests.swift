// Diffable data sources (ADR-0029): the identifier diff, snapshot semantics, and applying
// snapshots to a table and a collection view whose update calls are counted by recording
// subclasses (the host backend draws nothing, so the calls are what there is to check).

import XCTest
@testable import AppKit

// MARK: - Recording views

@MainActor
private final class RecordingTable: NSTableView {
    var calls: [String] = []
    var animations: [NSTableView.AnimationOptions] = []
    var reloadedRows: [IndexSet] = []
    override func beginUpdates() { calls.append("begin"); super.beginUpdates() }
    override func endUpdates() { calls.append("end"); super.endUpdates() }
    override func insertRows(at indexes: IndexSet, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        calls.append("insert \(Array(indexes))"); animations.append(animationOptions)
        super.insertRows(at: indexes, withAnimation: animationOptions)
    }
    override func removeRows(at indexes: IndexSet, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        calls.append("remove \(Array(indexes))"); animations.append(animationOptions)
        super.removeRows(at: indexes, withAnimation: animationOptions)
    }
    override func moveRow(at oldIndex: Int, to newIndex: Int) { calls.append("move \(oldIndex)>\(newIndex)"); super.moveRow(at: oldIndex, to: newIndex) }
    override func reloadData(forRowIndexes rowIndexes: IndexSet, columnIndexes: IndexSet) {
        calls.append("reload \(Array(rowIndexes))"); reloadedRows.append(rowIndexes)
        super.reloadData(forRowIndexes: rowIndexes, columnIndexes: columnIndexes)
    }
    override func reloadData() { calls.append("reloadData"); super.reloadData() }
    func count(_ prefix: String) -> Int { calls.filter { $0.hasPrefix(prefix) }.count }
    /// Asks for the rows from inside the table's own row-view bookkeeping, as a UIA client
    /// or a synchronous paint can on Windows (COM and WM_PAINT re-enter the message loop).
    var reenterOnRemove = false
    override func didRemove(_ rowView: NSTableRowView, forRow row: Int) {
        super.didRemove(rowView, forRow: row)
        if reenterOnRemove { _ = accessibilityRows(); viewWillDraw() }
    }
    override func didAdd(_ rowView: NSTableRowView, forRow row: Int) {
        super.didAdd(rowView, forRow: row)
        if reenterOnRemove { _ = accessibilityRows() }
    }
    override func tile() {
        super.tile()
        if reenterOnRemove { _ = accessibilityRows() }
    }
}

@MainActor
private final class RecordingCollection: NSCollectionView {
    var calls: [String] = []
    var batchDurations: [TimeInterval] = []
    override func performBatchUpdates(_ updates: (() -> Void)?, completionHandler: ((Bool) -> Void)? = nil) {
        calls.append("batch"); batchDurations.append(NSAnimationContext.current.duration)
        super.performBatchUpdates(updates, completionHandler: completionHandler)
    }
    override func insertSections(_ sections: IndexSet) { calls.append("insertSections \(Array(sections))"); super.insertSections(sections) }
    override func deleteSections(_ sections: IndexSet) { calls.append("deleteSections \(Array(sections))"); super.deleteSections(sections) }
    override func moveSection(_ section: Int, toSection newSection: Int) { calls.append("moveSection \(section)>\(newSection)"); super.moveSection(section, toSection: newSection) }
    override func reloadSections(_ sections: IndexSet) { calls.append("reloadSections \(Array(sections))"); super.reloadSections(sections) }
    override func insertItems(at indexPaths: Set<IndexPath>) { calls.append("insertItems \(indexPaths.count)"); super.insertItems(at: indexPaths) }
    override func deleteItems(at indexPaths: Set<IndexPath>) { calls.append("deleteItems \(indexPaths.count)"); super.deleteItems(at: indexPaths) }
    override func moveItem(at indexPath: IndexPath, to newIndexPath: IndexPath) { calls.append("moveItem"); super.moveItem(at: indexPath, to: newIndexPath) }
    override func reloadItems(at indexPaths: Set<IndexPath>) { calls.append("reloadItems \(indexPaths.count)"); super.reloadItems(at: indexPaths) }
    override func reloadData() { calls.append("reloadData"); super.reloadData() }
    func count(_ prefix: String) -> Int { calls.filter { $0.hasPrefix(prefix) }.count }
}

// MARK: - Fixtures

private typealias Snapshot = NSDiffableDataSourceSnapshot<String, String>

private func snapshot(_ sections: [(String, [String])]) -> Snapshot {
    var s = Snapshot()
    for (section, items) in sections {
        s.appendSections([section])
        s.appendItems(items, toSection: section)
    }
    return s
}

/// A small deterministic generator for the randomized cases.
private struct LCG {
    var state: UInt64
    mutating func next(_ n: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(max(1, n)))
    }
    mutating func shuffle<T>(_ a: [T]) -> [T] {
        var a = a
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, next(i + 1)) }
        return a
    }
}

@MainActor
private final class TableFixture {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let table = RecordingTable(frame: .zero)
    let scroll: NSScrollView
    var cellRequests: [String] = []
    var suffix = ""            // appended to every label, so a reload has something to show
    var source: NSTableViewDiffableDataSource<String, String>!

    init(height: CGFloat = 400) {
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: height))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 200
        table.addTableColumn(column)
        table.rowHeight = 20
        source = NSTableViewDiffableDataSource<String, String>(tableView: table) { [unowned self] _, _, row, id in
            self.cellRequests.append(id)
            // Reused through makeView, as real data sources do: a reused cell is relabelled
            // while detached from the window.
            let cell = (table.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: nil) as? NSTableCellView)
                ?? NSTableCellView._makeLabelCell(frame: .zero)
            cell.textField?.stringValue = id + self.suffix
            cell.identifier = NSUserInterfaceItemIdentifier("cell")
            return cell
        }
        scroll.documentView = table
        window.contentView!.addSubview(scroll)
        window.makeKeyAndOrderFront(nil)
        scroll.layoutSubtreeIfNeeded()
    }

    /// The labels of the live row views, top to bottom.
    func shownRows() -> [String] {
        window.display()
        var out: [(Int, String)] = []
        table.enumerateAvailableRowViews { rv, row in
            let text = (rv._cellViews.first as? NSTableCellView)?.textField?.stringValue ?? "?"
            out.append((row, text))
        }
        return out.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}

@MainActor
private final class CollectionFixture {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    let cv = RecordingCollection(frame: .zero)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    var itemRequests: [String] = []
    var suffix = ""
    var source: NSCollectionViewDiffableDataSource<String, String>!

    init(headers: Bool = false) {
        let flow = NSCollectionViewFlowLayout()
        flow.itemSize = NSSize(width: 40, height: 40)
        flow.minimumInteritemSpacing = 4
        flow.minimumLineSpacing = 4
        if headers { flow.headerReferenceSize = NSSize(width: 0, height: 20) }
        cv.collectionViewLayout = flow
        cv.isSelectable = true
        cv.register(ColorItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("color"))
        cv.register(HeaderView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: NSUserInterfaceItemIdentifier("header"))
        source = NSCollectionViewDiffableDataSource<String, String>(collectionView: cv) { [unowned self] cv, ip, id in
            self.itemRequests.append(id)
            let item = cv.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("color"), for: ip)
            item.textField?.stringValue = id + self.suffix
            return item
        }
        scroll.documentView = cv
        window.contentView!.addSubview(scroll)
        window.makeKeyAndOrderFront(nil)
        scroll.layoutSubtreeIfNeeded()
    }

    /// The label of each visible item by index path, as [section][item].
    func shown() -> [[String]] {
        window.display()
        var out: [[String]] = Array(repeating: [], count: cv.numberOfSections)
        for ip in cv.indexPathsForVisibleItems().sorted() {
            out[ip.section].append(cv.item(at: ip)?.textField?.stringValue ?? "?")
        }
        return out
    }
}


/// Turns on the host's reference native compositor for `window` (the model of Win32's
/// DirectComposition hosting), runs `change`, and returns the labels whose text changed while
/// their layer kept the raster version the compositor had cached: those would show stale text.
@MainActor
private func staleLabelsUnderNativeHosting(_ window: NSWindow, labels: () -> [NSTextField], after change: () -> Void) -> [String] {
    let host = Mirror(reflecting: window).descendant("_platform") as! HostWindow
    window.contentView!.wantsLayer = true
    host.layerHostingEnabled = true
    window._updateLayerHosting()
    precondition(window._hostsLayersNatively)
    window.display()
    var before: [ObjectIdentifier: (String, Int)] = [:]
    for l in labels() { if let layer = l.layer { before[ObjectIdentifier(l)] = (l.stringValue, layer._rasterVersion) } }
    change()
    window.displayIfNeeded()
    var stale: [String] = []
    for l in labels() {
        guard let (text, version) = before[ObjectIdentifier(l)], let layer = l.layer else { continue }
        if text != l.stringValue && layer._rasterVersion == version { stale.append(l.stringValue) }
    }
    host.layerHostingEnabled = false
    window._updateLayerHosting()
    return stale
}

// MARK: - Tests

final class DiffableTests: XCTestCase, @unchecked Sendable {

    // MARK: The diff

    func testDiffInsertsAndDeletes() {
        let d = _IdentifierDiff(from: ["a", "b", "c", "d"], to: ["a", "x", "c", "y", "z"])
        XCTAssertEqual(d.deletes, [1, 3])
        XCTAssertEqual(d.inserts, [1, 3, 4])
        XCTAssertTrue(d.moves.isEmpty)
        XCTAssertEqual(d.stays.map { [$0.from, $0.to] }, [[0, 0], [2, 2]])
        XCTAssertTrue(_IdentifierDiff(from: ["a"], to: ["a"]).isEmpty)
        XCTAssertEqual(_IdentifierDiff(from: [String](), to: ["a", "b"]).inserts, [0, 1])
        XCTAssertEqual(_IdentifierDiff(from: ["a", "b"], to: [String]()).deletes, [0, 1])
    }

    func testDiffFindsTheFewestMoves() {
        // Moving the first element to the end is one move, not n - 1.
        let d = _IdentifierDiff(from: ["a", "b", "c", "d", "e"], to: ["b", "c", "d", "e", "a"])
        XCTAssertEqual(d.moves.map { [$0.from, $0.to] }, [[0, 4]])
        XCTAssertEqual(d.stays.count, 4)
        // A swap is one move.
        XCTAssertEqual(_IdentifierDiff(from: [1, 2, 3], to: [1, 3, 2]).moves.count, 1)
        // A reversal keeps one element.
        XCTAssertEqual(_IdentifierDiff(from: Array(0..<6), to: Array((0..<6).reversed())).moves.count, 5)
        XCTAssertEqual(_IdentifierDiff.sequentialEdits(from: ["a", "b", "c", "d", "e"], to: ["b", "c", "d", "e", "a"]), [.move(from: 0, to: 4)])
    }

    func testSequentialEditsMergeInsertRunsAndRemoveOnce() {
        let edits = _IdentifierDiff.sequentialEdits(from: ["a", "b", "c", "d"], to: ["x", "y", "a", "d", "c", "z"])
        XCTAssertEqual(edits, [.remove(IndexSet([1])), .insert(IndexSet([0, 1])), .move(from: 4, to: 3), .insert(IndexSet([5]))])
    }

    func testSequentialEditsReproduceTheNewOrderingMixed() {
        var rng = LCG(state: 42)
        for _ in 0..<300 {
            let universe = (0..<rng.next(30)).map { "e\($0)" }
            let old = rng.shuffle(universe.filter { _ in rng.next(4) != 0 })
            let new = rng.shuffle(universe.filter { _ in rng.next(4) != 0 })
            var current = old
            let diff = _IdentifierDiff(from: old, to: new)
            for edit in _IdentifierDiff.sequentialEdits(from: old, to: new) {
                switch edit {
                case .remove(let rows): for r in rows.reversed() { current.remove(at: r) }
                case .insert(let rows): for r in rows { current.insert(new[0], at: r) }   // placeholder, replaced below
                case .move(let a, let b): current.insert(current.remove(at: a), at: b)
                }
                if case .insert(let rows) = edit {
                    // Inserted rows take the element the new ordering has after their predecessor.
                    for r in rows {
                        let prev = r == 0 ? nil : current[r - 1]
                        let j = prev.flatMap { new.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                        current[r] = new[j]
                    }
                }
            }
            XCTAssertEqual(current, new, "old \(old) new \(new)")
            XCTAssertEqual(diff.deletes.count + diff.stays.count + diff.moves.count, old.count)
            XCTAssertEqual(diff.inserts.count + diff.stays.count + diff.moves.count, new.count)
        }
    }

    // MARK: Snapshots

    func testSnapshotSectionsAndItems() {
        var s = Snapshot()
        XCTAssertEqual(s.numberOfSections, 0)
        s.appendSections(["fruit", "veg"])
        s.appendItems(["carrot", "leek"])                         // to the last section
        s.appendItems(["apple", "pear"], toSection: "fruit")
        s.insertItems(["banana"], afterItem: "apple")
        s.insertItems(["kiwi"], beforeItem: "apple")
        XCTAssertEqual(s.itemIdentifiers, ["kiwi", "apple", "banana", "pear", "carrot", "leek"])
        XCTAssertEqual(s.numberOfItems, 6)
        XCTAssertEqual(s.numberOfItems(inSection: "veg"), 2)
        XCTAssertEqual(s.itemIdentifiers(inSection: "fruit"), ["kiwi", "apple", "banana", "pear"])
        XCTAssertEqual(s.indexOfItem("carrot"), 4)
        XCTAssertNil(s.indexOfItem("plum"))
        XCTAssertEqual(s.sectionIdentifier(containingItem: "leek"), "veg")
        XCTAssertNil(s.sectionIdentifier(containingItem: "plum"))

        s.moveItem("leek", beforeItem: "kiwi")                    // across sections
        XCTAssertEqual(s.sectionIdentifier(containingItem: "leek"), "fruit")
        XCTAssertEqual(s.itemIdentifiers(inSection: "fruit").first, "leek")
        s.moveItem("kiwi", afterItem: "pear")
        XCTAssertEqual(s.itemIdentifiers(inSection: "fruit"), ["leek", "apple", "banana", "pear", "kiwi"])
        s.deleteItems(["banana", "plum"])                          // unknown identifiers are ignored
        XCTAssertEqual(s.numberOfItems, 5)

        s.insertSections(["nuts"], beforeSection: "fruit")
        s.insertSections(["herbs"], afterSection: "veg")
        XCTAssertEqual(s.sectionIdentifiers, ["nuts", "fruit", "veg", "herbs"])
        s.moveSection("herbs", beforeSection: "nuts")
        s.moveSection("nuts", afterSection: "veg")
        XCTAssertEqual(s.sectionIdentifiers, ["herbs", "fruit", "veg", "nuts"])
        XCTAssertEqual(s.indexOfSection("veg"), 2)
        XCTAssertNil(s.indexOfSection("grain"))
        s.deleteSections(["fruit"])                                // with its items
        XCTAssertEqual(s.itemIdentifiers, ["carrot"])
        XCTAssertNil(s.sectionIdentifier(containingItem: "apple"))
        s.deleteAllItems()
        XCTAssertEqual(s.numberOfSections, 0)
        XCTAssertEqual(s.numberOfItems, 0)
    }

    func testSnapshotIsAValueAndCarriesReloadsUntilApplied() {
        let a = snapshot([("s", ["1", "2"])])
        var b = a
        b.appendItems(["3"])
        XCTAssertEqual(a.numberOfItems, 2)
        XCTAssertEqual(b.numberOfItems, 3)
        b.reloadItems(["1"])
        b.reloadSections(["s"])
        XCTAssertEqual(b._reloadedItems, ["1"])
        XCTAssertEqual(b._reloadedSections, ["s"])
        b.deleteItems(["1"])
        XCTAssertTrue(b._reloadedItems.isEmpty)
        XCTAssertTrue(b._withoutReloads._reloadedSections.isEmpty)
        // Identifiers are compared by their Hashable conformance.
        struct Key: Hashable { var id: Int; var title: String; static func == (a: Key, b: Key) -> Bool { a.id == b.id }; func hash(into h: inout Hasher) { h.combine(id) } }
        var k = NSDiffableDataSourceSnapshot<Int, Key>()
        k.appendSections([0])
        k.appendItems([Key(id: 1, title: "one")])
        XCTAssertEqual(k.indexOfItem(Key(id: 1, title: "renamed")), 0)
    }

    // MARK: Table

    func testTableApplyInsertsTheRowsAndAnswersForTheDelegate() {
        MainActor.assumeIsolated {
            let f = TableFixture()
            XCTAssertTrue(f.table.dataSource === f.source)
            XCTAssertEqual(f.source.defaultRowAnimation, .effectFade)
            f.table.calls = []
            f.source.apply(snapshot([("s", ["a", "b", "c"])]), animatingDifferences: true)
            XCTAssertEqual(f.table.calls, ["begin", "insert [0, 1, 2]", "end"])
            XCTAssertEqual(f.table.animations, [.effectFade])
            XCTAssertEqual(f.table.numberOfRows, 3)
            XCTAssertEqual(f.shownRows(), ["a", "b", "c"])
            XCTAssertEqual(f.cellRequests, ["a", "b", "c"])
            XCTAssertEqual(f.source.itemIdentifier(forRow: 1), "b")
            XCTAssertNil(f.source.itemIdentifier(forRow: 3))
            XCTAssertEqual(f.source.row(forItemIdentifier: "c"), 2)
            XCTAssertNil(f.source.row(forItemIdentifier: "z"))
            XCTAssertEqual(f.source.sectionIdentifier(forRow: 0), "s")
            XCTAssertEqual(f.source.row(forSectionIdentifier: "s"), 0)
            XCTAssertEqual(f.source.snapshot().itemIdentifiers, ["a", "b", "c"])
            // The same snapshot again changes nothing.
            f.table.calls = []
            var done = false
            f.source.apply(f.source.snapshot(), animatingDifferences: true) { done = true }
            XCTAssertTrue(done)
            XCTAssertEqual(f.table.calls, [])
        }
    }

    func testTableApplyDiffsDeletesInsertsAndMovesAndRowViewsFollowTheirRows() {
        MainActor.assumeIsolated {
            let f = TableFixture()
            f.source.apply(snapshot([("s", ["a", "b", "c", "d", "e"])]), animatingDifferences: false)
            XCTAssertEqual(f.shownRows(), ["a", "b", "c", "d", "e"])
            let viewOfA = f.table.rowView(atRow: 0, makeIfNecessary: false)
            f.table.selectRowIndexes(IndexSet([0]), byExtendingSelection: false)
            f.table.calls = []
            f.cellRequests = []
            f.source.apply(snapshot([("s", ["b", "x", "c", "e", "a"])]), animatingDifferences: true)
            XCTAssertEqual(f.table.calls, ["begin", "remove [3]", "insert [2]", "move 0>4", "end"])
            XCTAssertEqual(f.shownRows(), ["b", "x", "c", "e", "a"])
            // Only the new row asked for a cell; the moved row kept its view and its selection.
            XCTAssertEqual(f.cellRequests, ["x"])
            XCTAssertTrue(f.table.rowView(atRow: 4, makeIfNecessary: false) === viewOfA)
            XCTAssertEqual(f.table.selectedRowIndexes, IndexSet([4]))
        }
    }

    func testTableAnimatingDifferencesChoosesTheAnimation() {
        MainActor.assumeIsolated {
            let f = TableFixture()
            f.source.defaultRowAnimation = .slideLeft
            f.source.apply(snapshot([("s", ["a", "b"])]), animatingDifferences: false)
            XCTAssertEqual(f.table.animations, [[]])
            f.source.apply(snapshot([("s", ["b"])]), animatingDifferences: true)
            XCTAssertEqual(f.table.animations, [[], .slideLeft])
            XCTAssertEqual(f.table.count("reloadData"), 0)
        }
    }

    func testTableReloadsOnlyTheMarkedRows() {
        MainActor.assumeIsolated {
            let f = TableFixture()
            f.source.apply(snapshot([("s", ["a", "b", "c"])]), animatingDifferences: false)
            _ = f.shownRows()
            f.cellRequests = []
            f.table.calls = []
            var s = f.source.snapshot()
            s.appendItems(["d"])
            s.reloadItems(["b"])
            f.source.apply(s, animatingDifferences: true)
            XCTAssertEqual(f.table.calls, ["begin", "insert [3]", "end", "reload [1]"])
            _ = f.shownRows()
            XCTAssertEqual(f.cellRequests.sorted(), ["b", "d"])
            // The reload mark is consumed by the apply.
            XCTAssertTrue(f.source.snapshot()._reloadedItems.isEmpty)
        }
    }

    func testTableSectionHeadersAreGroupRows() {
        MainActor.assumeIsolated {
            let f = TableFixture()
            var headerRequests: [String] = []
            f.source.sectionHeaderViewProvider = { _, row, section in
                headerRequests.append(section)
                let cell = NSTableCellView._makeLabelCell(frame: .zero)
                cell.textField?.stringValue = "[\(section)]"
                return cell
            }
            var rowViewKeys: [AnyHashable] = []
            f.source.rowViewProvider = { _, _, key in rowViewKeys.append(key); return NSTableRowView(frame: .zero) }
            f.source.apply(snapshot([("one", ["a", "b"]), ("two", ["c"])]), animatingDifferences: true)
            XCTAssertEqual(f.table.numberOfRows, 5)
            XCTAssertEqual(f.shownRows(), ["[one]", "a", "b", "[two]", "c"])
            XCTAssertEqual(headerRequests, ["one", "two"])
            XCTAssertEqual(rowViewKeys, [AnyHashable("one"), "a", "b", AnyHashable("two"), "c"])
            XCTAssertNil(f.source.itemIdentifier(forRow: 0))
            XCTAssertEqual(f.source.itemIdentifier(forRow: 4), "c")
            XCTAssertEqual(f.source.row(forSectionIdentifier: "two"), 3)
            XCTAssertEqual(f.source.sectionIdentifier(forRow: 2), "one")
            XCTAssertEqual(f.source.sectionIdentifier(forRow: 4), "two")
            XCTAssertTrue(f.table.rowView(atRow: 3, makeIfNecessary: false)!.isGroupRowStyle)
            XCTAssertFalse(f.table.rowView(atRow: 4, makeIfNecessary: false)!.isGroupRowStyle)
            // The header spans the row.
            XCTAssertEqual(f.table.rowView(atRow: 0, makeIfNecessary: false)!._cellViews.first!.frame.width, f.table.bounds.width)
            // Moving a section moves its header with it.
            f.table.calls = []
            var s = f.source.snapshot()
            s.moveSection("two", beforeSection: "one")
            s.reloadSections(["one"])
            f.source.apply(s, animatingDifferences: true)
            XCTAssertEqual(f.shownRows(), ["[two]", "c", "[one]", "a", "b"])
            XCTAssertEqual(f.table.calls.last, "reload [2, 3, 4]")
        }
    }

    func testTableRandomizedAppliesMatchTheSnapshot() {
        MainActor.assumeIsolated {
            let f = TableFixture()
            var rng = LCG(state: 7)
            for _ in 0..<40 {
                let items = rng.shuffle((0..<rng.next(15)).map { "i\($0)" }.filter { _ in rng.next(3) != 0 })
                f.source.apply(snapshot([("s", items)]), animatingDifferences: rng.next(2) == 0)
                XCTAssertEqual(f.shownRows(), items)
            }
        }
    }

    func testTableShufflesWithHeadersAndRowsOutOfViewMatchTheSnapshot() {
        // The Layout Demo's Shuffle, after the table has drawn: two sections with header
        // rows, more rows than the view shows, items moving across the header.
        MainActor.assumeIsolated {
            let f = TableFixture(height: 150)
            f.source.sectionHeaderViewProvider = { _, _, section in
                let cell = NSTableCellView._makeLabelCell(frame: .zero)
                cell.textField?.stringValue = "[\(section)]"
                return cell
            }
            var rng = LCG(state: 2026)
            var all = (1...8).map { "\($0)" }
            for round in 0..<40 {
                if round > 0 { all = rng.shuffle(all) }
                let rows = ["[Warm]"] + all[..<4] + ["[Cool]"] + all[4...]
                f.source.apply(snapshot([("Warm", Array(all[..<4])), ("Cool", Array(all[4...]))]), animatingDifferences: true)
                let shown = f.shownRows()
                XCTAssertFalse(shown.isEmpty)
                XCTAssertEqual(shown, Array(rows.prefix(shown.count)), "round \(round)")
                // Every row, scrolled into view, shows its own item.
                f.table.scrollRowToVisible(rows.count - 1)
                f.window.display()
                var bottom: [(Int, String)] = []
                f.table.enumerateAvailableRowViews { rv, row in bottom.append((row, (rv._cellViews.first as? NSTableCellView)?.textField?.stringValue ?? "?")) }
                for (row, text) in bottom { XCTAssertEqual(text, rows[row], "round \(round) row \(row)") }
                f.table.scrollRowToVisible(0)
            }
        }
    }

    func testTableLayoutDemoShuffleSequenceWithReusedCells() {
        // The Layout Demo's two Shuffle clicks (its generator, seed 2026) with cells reused
        // through makeView(withIdentifier:), drawn between the clicks.
        MainActor.assumeIsolated {
            let f = TableFixture(height: 190)
            f.source = NSTableViewDiffableDataSource<String, String>(tableView: f.table) { tableView, _, _, id in
                let rid = NSUserInterfaceItemIdentifier("reused")
                let cell = (tableView.makeView(withIdentifier: rid, owner: nil) as? NSTableCellView) ?? {
                    let c = NSTableCellView._makeLabelCell(frame: .zero)
                    c.identifier = rid
                    return c
                }()
                cell.textField?.stringValue = id
                return cell
            }
            f.source.sectionHeaderViewProvider = { tableView, _, section in
                let hid = NSUserInterfaceItemIdentifier("header")
                let cell = (tableView.makeView(withIdentifier: hid, owner: nil) as? NSTableCellView) ?? {
                    let c = NSTableCellView._makeLabelCell(frame: .zero)
                    c.identifier = hid
                    return c
                }()
                cell.textField?.stringValue = "[\(section)]"
                return cell
            }
            @MainActor func apply(_ model: [[String]], animating: Bool) -> [String] {
                f.source.apply(snapshot([("Warm", model[0]), ("Cool", model[1])]), animatingDifferences: animating)
                return ["[Warm]"] + model[0] + ["[Cool]"] + model[1]
            }
            var rows = apply([["1", "2", "3", "4"], ["5", "6", "7", "8"]], animating: false)
            XCTAssertEqual(f.shownRows(), Array(rows.prefix(f.shownRows().count)))
            rows = apply([["3", "6", "5", "7"], ["4", "2", "1", "8"]], animating: true)
            XCTAssertEqual(f.shownRows(), Array(rows.prefix(f.shownRows().count)))
            rows = apply([["2", "7", "5", "4"], ["6", "8", "1", "3"]], animating: true)
            XCTAssertEqual(f.shownRows(), Array(rows.prefix(f.shownRows().count)))
        }
    }

    func testTableRowsStayRightWhenTheTableIsQueriedDuringAnUpdate() {
        MainActor.assumeIsolated {
            let f = TableFixture(height: 150)
            f.source.sectionHeaderViewProvider = { _, _, section in
                let cell = NSTableCellView._makeLabelCell(frame: .zero)
                cell.textField?.stringValue = "[\(section)]"
                return cell
            }
            f.table.reenterOnRemove = true
            var rng = LCG(state: 11)
            var all = (1...8).map { "\($0)" }
            for round in 0..<30 {
                if round > 0 { all = rng.shuffle(all) }
                let rows = ["[Warm]"] + all[..<4] + ["[Cool]"] + all[4...]
                f.source.apply(snapshot([("Warm", Array(all[..<4])), ("Cool", Array(all[4...]))]), animatingDifferences: true)
                let shown = f.shownRows()
                XCTAssertEqual(shown, Array(rows.prefix(shown.count)), "round \(round)")
                // No orphaned row views: every row view in the table is a live, filed one.
                let rowViews = f.table.subviews.filter { $0 is NSTableRowView }
                var live = 0
                f.table.enumerateAvailableRowViews { _, _ in live += 1 }
                XCTAssertEqual(rowViews.count, live, "round \(round)")
            }
        }
    }

    // MARK: Collection

    func testCollectionApplyBatchesSectionsAndItems() {
        MainActor.assumeIsolated {
            let f = CollectionFixture()
            XCTAssertTrue(f.cv.dataSource === f.source)
            f.cv.calls = []
            f.source.apply(snapshot([("one", ["a", "b", "c"]), ("two", ["d"])]))
            XCTAssertEqual(f.cv.calls, ["batch", "insertSections [0, 1]"])
            XCTAssertEqual(f.cv.numberOfSections, 2)
            XCTAssertEqual(f.cv.numberOfItems(inSection: 0), 3)
            XCTAssertEqual(f.shown(), [["a", "b", "c"], ["d"]])
            XCTAssertEqual(f.source.itemIdentifier(for: IndexPath(item: 2, section: 0)), "c")
            XCTAssertNil(f.source.itemIdentifier(for: IndexPath(item: 3, section: 0)))
            XCTAssertEqual(f.source.indexPath(for: "d"), IndexPath(item: 0, section: 1))
            XCTAssertNil(f.source.indexPath(for: "z"))
            XCTAssertTrue(f.source.description().contains("2 sections, 4 items"))
            // Nothing changed: no batch.
            f.cv.calls = []
            f.source.apply(f.source.snapshot())
            XCTAssertEqual(f.cv.calls, [])
        }
    }

    func testCollectionApplyMovesItemsAcrossSectionsAndKeepsTheirItems() {
        MainActor.assumeIsolated {
            let f = CollectionFixture()
            f.source.apply(snapshot([("one", ["a", "b", "c"]), ("two", ["d", "e"])]), animatingDifferences: false)
            _ = f.shown()
            let itemB = f.cv.item(at: IndexPath(item: 1, section: 0))
            f.cv.selectItems(at: [IndexPath(item: 1, section: 0)], scrollPosition: [])
            f.itemRequests = []
            f.cv.calls = []
            // b moves to the other section, c goes, f arrives, e is reloaded.
            var s = snapshot([("one", ["a"]), ("two", ["d", "b", "e", "f"])])
            s.reloadItems(["e"])
            f.source.apply(s)
            XCTAssertEqual(f.cv.calls, ["batch", "deleteItems 1", "insertItems 1", "moveItem", "reloadItems 1"])
            XCTAssertEqual(f.shown(), [["a"], ["d", "b", "e", "f"]])
            XCTAssertEqual(f.itemRequests.sorted(), ["e", "f"])
            XCTAssertTrue(f.cv.item(at: IndexPath(item: 1, section: 1)) === itemB)
            XCTAssertEqual(f.cv.selectionIndexPaths, [IndexPath(item: 1, section: 1)])
        }
    }

    func testCollectionApplyMovesSectionsWithItemChangesInside() {
        MainActor.assumeIsolated {
            let f = CollectionFixture(headers: true)
            var headerRequests: [IndexPath] = []
            f.source.supplementaryViewProvider = { cv, kind, ip in
                headerRequests.append(ip)
                let v = cv.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier("header"), for: ip) as! HeaderView
                v.label.stringValue = "\(ip.section)"
                return v
            }
            f.source.apply(snapshot([("one", ["a", "b"]), ("two", ["c", "d", "e"]), ("three", ["f"])]))
            XCTAssertEqual(f.shown(), [["a", "b"], ["c", "d", "e"], ["f"]])
            XCTAssertEqual(Set(headerRequests.map { $0.section }), [0, 1, 2])
            f.cv.calls = []
            // "two" moves to the front and loses d; "three" goes; "four" arrives with f in it.
            f.source.apply(snapshot([("two", ["c", "e"]), ("one", ["a", "b"]), ("four", ["f", "g"])]))
            XCTAssertEqual(f.cv.calls.first, "batch")
            XCTAssertTrue(f.cv.calls.contains("deleteSections [2]"))
            XCTAssertTrue(f.cv.calls.contains("insertSections [2]"))
            XCTAssertEqual(f.cv.count("moveSection"), 1)
            XCTAssertTrue(f.cv.calls.contains("deleteItems 1"))
            XCTAssertEqual(f.shown(), [["c", "e"], ["a", "b"], ["f", "g"]])
        }
    }

    func testCollectionAnimatingDifferencesUsesAZeroDurationGroupWhenNotAnimating() {
        MainActor.assumeIsolated {
            let f = CollectionFixture()
            f.cv.calls = []
            f.source.apply(snapshot([("s", ["a"])]), animatingDifferences: false)
            f.source.apply(snapshot([("s", ["a", "b"])]), animatingDifferences: true)
            XCTAssertEqual(f.cv.batchDurations.count, 2)
            XCTAssertEqual(f.cv.batchDurations[0], 0)
            XCTAssertGreaterThan(f.cv.batchDurations[1], 0)
            XCTAssertEqual(f.cv.count("reloadData"), 0)
        }
    }

    /// A reload re-requests every cell; the reused cell views are relabelled while detached,
    /// and a natively hosted window (Win32's DirectComposition) must re-rasterise them.
    func testReloadRedrawsReusedViewsUnderNativeHosting() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("uses the host's reference compositor") }
            let t = TableFixture()
            var s = snapshot([("A", ["one", "two", "three", "four"]), ("B", ["five", "six"])])
            t.source.apply(s, animatingDifferences: false)
            @MainActor func tableLabels() -> [NSTextField] {
                var out: [NSTextField] = []
                t.table.enumerateAvailableRowViews { rv, _ in
                    if let f = (rv._cellViews.first as? NSTableCellView)?.textField { out.append(f) }
                }
                return out
            }
            XCTAssertEqual(staleLabelsUnderNativeHosting(t.window, labels: tableLabels) {
                t.suffix = " r2"
                s.reloadItems(s.itemIdentifiers)
                t.source.apply(s, animatingDifferences: true)
            }, [], "table: reused cells relabelled off-window get a new raster")
            XCTAssertEqual(t.shownRows(), ["one r2", "two r2", "three r2", "four r2", "five r2", "six r2"])
            t.window.close()

            let c = CollectionFixture()
            var cs = snapshot([("A", ["one", "two", "three"]), ("B", ["four", "five"])])
            c.source.apply(cs, animatingDifferences: false)
            @MainActor func collectionLabels() -> [NSTextField] { c.cv.visibleItems().compactMap(\.textField) }
            XCTAssertEqual(staleLabelsUnderNativeHosting(c.window, labels: collectionLabels) {
                c.suffix = "#"
                cs.reloadItems(cs.itemIdentifiers)
                c.source.apply(cs, animatingDifferences: false)
            }, [], "collection: reused items relabelled off-window get a new raster")
            XCTAssertEqual(c.shown(), [["one#", "two#", "three#"], ["four#", "five#"]])
            c.window.close()
        }
    }

    func testCollectionRandomizedAppliesMatchTheSnapshot() {
        MainActor.assumeIsolated {
            let f = CollectionFixture()
            var rng = LCG(state: 99)
            let allSections = ["A", "B", "C", "D"]
            for _ in 0..<60 {
                let sections = rng.shuffle(allSections.filter { _ in rng.next(4) != 0 })
                var pool = rng.shuffle((0..<14).map { "i\($0)" }.filter { _ in rng.next(3) != 0 })
                var s = Snapshot()
                var expected: [[String]] = []
                for section in sections {
                    let n = min(pool.count, rng.next(6))
                    let items = Array(pool.prefix(n))
                    pool.removeFirst(n)
                    s.appendSections([section])
                    s.appendItems(items, toSection: section)
                    expected.append(items)
                }
                let old = f.source.snapshot()
                for id in s.itemIdentifiers where old.indexOfItem(id) != nil && rng.next(5) == 0 { s.reloadItems([id]) }
                for sec in s.sectionIdentifiers where old.indexOfSection(sec) != nil && rng.next(8) == 0 { s.reloadSections([sec]) }
                f.source.apply(s, animatingDifferences: rng.next(2) == 0)
                XCTAssertEqual(f.shown(), expected)
            }
        }
    }
}
