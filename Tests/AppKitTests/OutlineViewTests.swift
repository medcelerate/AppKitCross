// NSOutlineView on the host backend: expand and collapse with the row mapping, levels,
// reloading, inserting, removing and moving items, autosaved expansion, the keyboard,
// delegate and notification order, right-to-left indentation, the disclosure triangle's
// pixels, and accessibility.

import XCTest
@testable import AppKit

private final class Node {
    let name: String
    var children: [Node]
    init(_ name: String, _ children: [Node] = []) { self.name = name; self.children = children }
}

private final class Log: @unchecked Sendable {
    var events: [String] = []
    func add(_ s: String) { events.append(s) }
}

@MainActor
private final class Tree: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var roots: [Node]
    let log: Log
    var refuseExpand: Node? = nil
    var viewRequests = 0
    init(roots: [Node], log: Log) { self.roots = roots; self.log = log }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { ((item as? Node)?.children ?? roots).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node)?.children ?? roots)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as! Node).children.isEmpty) }
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        guard let n = item as? Node else { return nil }
        return tableColumn?.identifier.rawValue == "count" ? n.children.count : n.name
    }
    func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? { (item as? Node)?.name }
    func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
        guard let name = object as? String else { return nil }
        func find(_ nodes: [Node]) -> Node? { for n in nodes { if n.name == name { return n }; if let f = find(n.children) { return f } }; return nil }
        return find(roots)
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? { viewRequests += 1; return nil }
    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool { (item as? Node) !== refuseExpand }
    func outlineViewItemWillExpand(_ notification: Notification) { log.add("delegate willExpand \((notification.userInfo?["NSObject"] as? Node)?.name ?? "?")") }
    func outlineViewItemDidExpand(_ notification: Notification) { log.add("delegate didExpand \((notification.userInfo?["NSObject"] as? Node)?.name ?? "?")") }
    func outlineViewItemWillCollapse(_ notification: Notification) { log.add("delegate willCollapse \((notification.userInfo?["NSObject"] as? Node)?.name ?? "?")") }
    func outlineViewItemDidCollapse(_ notification: Notification) { log.add("delegate didCollapse \((notification.userInfo?["NSObject"] as? Node)?.name ?? "?")") }
    func outlineViewSelectionDidChange(_ notification: Notification) { log.add("delegate selection \((notification.object as? NSOutlineView)?.selectedRow ?? -2)") }
}

@MainActor
private func sampleTree() -> [Node] {
    [Node("Documents", [Node("Reports", [Node("Q1"), Node("Q2")]), Node("Notes"), Node("Budget")]),
     Node("Pictures", [Node("Holiday", [Node("beach"), Node("sunset")]), Node("cat")]),
     Node("README")]
}

@MainActor
private func makeOutline(_ tree: Tree, in window: NSWindow) -> (NSOutlineView, NSScrollView) {
    let o = NSOutlineView(frame: .zero)
    let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    name.title = "Name"
    name.width = 180
    let count = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("count"))
    count.title = "Items"
    count.width = 60
    o.addTableColumn(name)
    o.addTableColumn(count)
    o.dataSource = tree
    o.delegate = tree
    o.rowHeight = 20
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
    scroll.hasVerticalScroller = true
    scroll.documentView = o
    window.contentView!.addSubview(scroll)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(o)
    scroll.layoutSubtreeIfNeeded()
    return (o, scroll)
}

@MainActor
private func names(_ o: NSOutlineView) -> [String] { (0..<o.numberOfRows).map { (o.item(atRow: $0) as! Node).name } }

@MainActor
private func key(_ w: NSWindow, _ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    NSApplication.shared.sendEvent(e)
}

@MainActor
private func click(_ w: NSWindow, _ p: NSPoint, flags: NSEvent.ModifierFlags = []) {
    for (type, pressure) in [(NSEvent.EventType.leftMouseDown, 1 as Float), (.leftMouseUp, 0)] {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure)!
        NSApplication.shared.sendEvent(e)
    }
}

final class OutlineViewTests: XCTestCase, @unchecked Sendable {
    func testExpandAndCollapseMapRowsAndKeepTheSelection() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let log = Log()
            let tree = Tree(roots: sampleTree(), log: log)
            let (o, _) = makeOutline(tree, in: w)
            let docs = tree.roots[0], reports = docs.children[0], pics = tree.roots[1]
            XCTAssertEqual(names(o), ["Documents", "Pictures", "README"])
            XCTAssertTrue(o.isExpandable(docs))
            XCTAssertFalse(o.isExpandable(tree.roots[2]))
            XCTAssertFalse(o.isItemExpanded(docs))
            XCTAssertTrue(o.isItemExpanded(nil), "the root is always expanded")
            XCTAssertEqual(o.level(forItem: docs), 0)
            XCTAssertEqual(o.level(forItem: nil), -1)
            XCTAssertEqual(o.row(forItem: reports), -1, "hidden under a collapsed parent")
            XCTAssertEqual(o.numberOfChildren(ofItem: nil), 3)
            XCTAssertEqual(o.numberOfChildren(ofItem: docs), 3)
            XCTAssertTrue((o.child(1, ofItem: docs) as? Node) === docs.children[1])
            XCTAssertEqual(o.childIndex(forItem: pics), 1)
            let observers = [NSOutlineView.itemWillExpandNotification, NSOutlineView.itemDidExpandNotification, NSOutlineView.itemWillCollapseNotification, NSOutlineView.itemDidCollapseNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: o, queue: nil) { n in
                    log.add("\(name.rawValue.replacingOccurrences(of: "NSOutlineView", with: "").replacingOccurrences(of: "Notification", with: "")) \((n.userInfo?["NSObject"] as? Node)?.name ?? "?")")
                }
            }
            o.expandItem(docs)
            XCTAssertEqual(names(o), ["Documents", "Reports", "Notes", "Budget", "Pictures", "README"])
            XCTAssertTrue(o.isItemExpanded(docs))
            XCTAssertEqual(o.row(forItem: reports), 1)
            XCTAssertEqual(o.level(forRow: 1), 1)
            XCTAssertEqual(o.level(forItem: reports), 1)
            XCTAssertTrue((o.parent(forItem: reports) as? Node) === docs)
            XCTAssertNil(o.parent(forItem: docs))
            XCTAssertEqual(log.events, ["ItemWillExpand Documents", "delegate willExpand Documents", "ItemDidExpand Documents", "delegate didExpand Documents"], "notification, then delegate, will before did")
            log.events.removeAll()
            o.expandItem(docs)
            XCTAssertTrue(log.events.isEmpty, "expanding an expanded item does nothing")
            // Expand children deep: every descendant opens.
            o.expandItem(pics, expandChildren: true)
            XCTAssertEqual(names(o), ["Documents", "Reports", "Notes", "Budget", "Pictures", "Holiday", "beach", "sunset", "cat", "README"])
            XCTAssertEqual(o.level(forRow: 6), 2)
            XCTAssertEqual(log.events.filter { $0.hasPrefix("ItemDidExpand") }, ["ItemDidExpand Pictures", "ItemDidExpand Holiday"])
            // A selected row under a collapsing parent hands the selection to the parent.
            o.selectRowIndexes(IndexSet(integer: 7), byExtendingSelection: false)       // sunset
            log.events.removeAll()
            o.collapseItem(pics)
            XCTAssertEqual(names(o), ["Documents", "Reports", "Notes", "Budget", "Pictures", "README"])
            XCTAssertEqual(o.selectedRow, 4, "Pictures")
            XCTAssertEqual(log.events, ["ItemWillCollapse Pictures", "delegate willCollapse Pictures", "delegate selection 4", "ItemDidCollapse Pictures", "delegate didCollapse Pictures"])
            XCTAssertTrue(o.isItemExpanded(pics.children[0]), "Holiday stays expanded inside its collapsed parent")
            o.expandItem(pics)
            XCTAssertEqual(names(o).count, 10, "and shows again")
            XCTAssertEqual(o.selectedRow, 4, "the selection follows the item, not the row index")
            o.selectRowIndexes(IndexSet(integer: 9), byExtendingSelection: false)       // README
            o.collapseItem(docs)
            XCTAssertEqual(names(o)[o.selectedRow], "README", "rows above collapsing keeps the selected item")
            o.collapseItem(nil, collapseChildren: true)
            XCTAssertEqual(names(o), ["Documents", "Pictures", "README"])
            XCTAssertFalse(o.isItemExpanded(pics.children[0]), "collapse everything")
            o.expandItem(nil, expandChildren: true)
            XCTAssertEqual(names(o).count, 12)
            // The delegate can refuse.
            o.collapseItem(nil, collapseChildren: true)
            tree.refuseExpand = docs
            log.events.removeAll()
            o.expandItem(docs)
            XCTAssertFalse(o.isItemExpanded(docs))
            XCTAssertTrue(log.events.isEmpty)
            for ob in observers { NotificationCenter.default.removeObserver(ob) }
            w.close()
        }
    }

    func testReloadInsertRemoveAndMove() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, _) = makeOutline(tree, in: w)
            let docs = tree.roots[0], pics = tree.roots[1]
            o.expandItem(docs)
            o.expandItem(pics)
            // Insert under an expanded parent.
            docs.children.insert(Node("Drafts"), at: 1)
            o.insertItems(at: IndexSet(integer: 1), inParent: docs)
            XCTAssertEqual(names(o), ["Documents", "Reports", "Drafts", "Notes", "Budget", "Pictures", "Holiday", "cat", "README"])
            // Remove.
            docs.children.remove(at: 2)
            o.removeItems(at: IndexSet(integer: 2), inParent: docs)
            XCTAssertEqual(names(o), ["Documents", "Reports", "Drafts", "Budget", "Pictures", "Holiday", "cat", "README"])
            // Move across parents: the moved item keeps its subtree and gets the new level.
            let holiday = pics.children.remove(at: 0)
            docs.children.append(holiday)
            o.moveItem(at: 0, inParent: pics, to: docs.children.count - 1, inParent: docs)
            XCTAssertEqual(names(o), ["Documents", "Reports", "Drafts", "Budget", "Holiday", "Pictures", "cat", "README"])
            XCTAssertEqual(o.level(forItem: holiday), 1)
            o.expandItem(holiday)
            XCTAssertEqual(o.level(forItem: holiday.children[0]), 2)
            // Insert a root at the end.
            tree.roots.append(Node("Music", [Node("song")]))
            o.insertItems(at: IndexSet(integer: 3), inParent: nil)
            XCTAssertEqual(names(o).last, "Music")
            XCTAssertEqual(o.level(forItem: tree.roots[3]), 0)
            // reloadItem(reloadChildren:) re-reads a subtree; expansion survives.
            docs.children[0].children.append(Node("Q3"))
            o.expandItem(docs.children[0])
            XCTAssertEqual(o.numberOfChildren(ofItem: docs.children[0]), 3)
            docs.children[0].children.removeFirst()
            o.reloadItem(docs.children[0], reloadChildren: true)
            XCTAssertEqual(o.numberOfChildren(ofItem: docs.children[0]), 2)
            XCTAssertTrue(o.isItemExpanded(docs.children[0]))
            XCTAssertEqual(names(o).prefix(4), ["Documents", "Reports", "Q2", "Q3"])
            // A row's cell shows the new value after reloadItem.
            w.display()
            let before = (o.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
            XCTAssertEqual(before, "4")
            docs.children.removeLast()
            o.reloadItem(docs)
            XCTAssertEqual((o.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue, "3")
            // reloadData keeps expanded items expanded.
            o.reloadData()
            XCTAssertTrue(o.isItemExpanded(docs))
            XCTAssertTrue(o.isItemExpanded(docs.children[0]))
            XCTAssertEqual(names(o).prefix(4), ["Documents", "Reports", "Q2", "Q3"])
            // Changing the data source drops the tree.
            let other = Tree(roots: [Node("Only")], log: Log())
            o.dataSource = other
            XCTAssertEqual(names(o), ["Only"])
            w.close()
        }
    }

    func testAutosaveExpandedItems() {
        MainActor.assumeIsolated {
            let key = "NSOutlineView Items AppKitCrossOutlineTest"
            UserDefaults.standard.removeObject(forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, _) = makeOutline(tree, in: w)
            o.autosaveName = "AppKitCrossOutlineTest"
            o.autosaveExpandedItems = true
            o.expandItem(tree.roots[1], expandChildren: true)
            o.expandItem(tree.roots[0])
            XCTAssertEqual(Set(UserDefaults.standard.array(forKey: key) as? [String] ?? []), ["Documents", "Pictures", "Holiday"])
            o.collapseItem(tree.roots[0])
            XCTAssertEqual(Set(UserDefaults.standard.array(forKey: key) as? [String] ?? []), ["Pictures", "Holiday"])
            // A new outline over the same items restores the expansion from the defaults.
            let tree2 = Tree(roots: sampleTree(), log: Log())
            let w2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let (o2, _) = makeOutline(tree2, in: w2)
            o2.autosaveExpandedItems = true
            o2.autosaveName = "AppKitCrossOutlineTest"
            o2.reloadData()
            XCTAssertEqual(names(o2), ["Documents", "Pictures", "Holiday", "beach", "sunset", "cat", "README"])
            w2.close()
            w.close()
        }
    }

    func testKeyboardExpandsCollapsesAndClimbs() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, _) = makeOutline(tree, in: w)
            o.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)       // Pictures
            key(w, "\u{F703}", code: 124)                                                // right expands
            XCTAssertEqual(names(o), ["Documents", "Pictures", "Holiday", "cat", "README"])
            key(w, "\u{F701}", code: 125)                                                // down to Holiday
            XCTAssertEqual(o.selectedRow, 2)
            key(w, "\u{F702}", code: 123)                                                // left on a collapsed row: the parent
            XCTAssertEqual(o.selectedRow, 1, "Pictures")
            XCTAssertTrue(o.isItemExpanded(tree.roots[1]))
            key(w, "\u{F702}", code: 123)                                                // left collapses
            XCTAssertEqual(names(o), ["Documents", "Pictures", "README"])
            key(w, "\u{F702}", code: 123)                                                // left on a collapsed root: nothing
            XCTAssertEqual(o.selectedRow, 1)
            key(w, "\u{F703}", code: 124, flags: .option)                               // option-right: the subtree
            XCTAssertEqual(names(o), ["Documents", "Pictures", "Holiday", "beach", "sunset", "cat", "README"])
            key(w, "\u{F702}", code: 123, flags: .option)
            XCTAssertEqual(names(o), ["Documents", "Pictures", "README"])
            XCTAssertFalse(o.isItemExpanded(tree.roots[1].children[0]), "option-left collapsed the children too")
            key(w, "\u{F703}", code: 124)
            XCTAssertEqual(names(o).count, 5, "Holiday stays collapsed")
            // Right to left mirrors the keys.
            o.userInterfaceLayoutDirection = .rightToLeft
            key(w, "\u{F703}", code: 124)                                                // right collapses
            XCTAssertEqual(names(o), ["Documents", "Pictures", "README"])
            key(w, "\u{F702}", code: 123)                                                // left expands
            XCTAssertEqual(names(o).count, 5)
            w.close()
        }
    }

    func testDisclosureButtonsClickAndIndentation() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, _) = makeOutline(tree, in: w)
            w.display()
            let row0 = o.rowView(atRow: 0, makeIfNecessary: true)!
            let button = row0.subviews.first { $0.identifier == NSOutlineView.disclosureButtonIdentifier }
            XCTAssertNotNil(button, "an expandable row carries a disclosure button")
            XCTAssertEqual(row0.numberOfColumns, 2, "the button is not a cell")
            XCTAssertTrue(row0.view(atColumn: 0) is NSTableCellView)
            XCTAssertNil(o.rowView(atRow: 2, makeIfNecessary: true)!.subviews.first { $0.identifier == NSOutlineView.disclosureButtonIdentifier }, "a leaf has none")
            XCTAssertEqual(o.frameOfOutlineCell(atRow: 2), .zero)
            let f0 = o.frameOfOutlineCell(atRow: 0)
            XCTAssertEqual(f0.minX, 0)
            XCTAssertEqual(f0.width, NSOutlineView.disclosureWidth)
            XCTAssertEqual(f0.midY, o.rect(ofRow: 0).midY, accuracy: 1)
            let cell0 = o.view(atColumn: 0, row: 0, makeIfNecessary: true)!
            XCTAssertEqual(cell0.frame.minX, NSOutlineView.disclosureWidth, "the outline column's cell starts after the triangle")
            XCTAssertEqual(o.view(atColumn: 1, row: 0, makeIfNecessary: true)!.frame.minX, o.rect(ofColumn: 1).minX, "other columns are not indented")
            // Clicking the triangle expands; the child row is indented one level.
            click(w, o.convert(NSPoint(x: f0.midX, y: f0.midY), to: nil))
            XCTAssertTrue(o.isItemExpanded(tree.roots[0]))
            XCTAssertEqual(o.selectedRow, -1, "the triangle does not select the row")
            w.display()
            let cell1 = o.view(atColumn: 0, row: 1, makeIfNecessary: true)!
            XCTAssertEqual(cell1.frame.minX, NSOutlineView.disclosureWidth + o.indentationPerLevel)
            XCTAssertEqual(o.frameOfOutlineCell(atRow: 1).minX, o.indentationPerLevel)
            o.indentationPerLevel = 30
            w.display()
            XCTAssertEqual(o.view(atColumn: 0, row: 1, makeIfNecessary: true)!.frame.minX, NSOutlineView.disclosureWidth + 30)
            o.indentationPerLevel = 16
            w.display()      // row views (and their buttons) are made when the table draws
            // Option-click on the Pictures triangle opens its subtree.
            let f4 = o.frameOfOutlineCell(atRow: 4)
            click(w, o.convert(NSPoint(x: f4.midX, y: f4.midY), to: nil), flags: .option)
            XCTAssertEqual(names(o), ["Documents", "Reports", "Notes", "Budget", "Pictures", "Holiday", "beach", "sunset", "cat", "README"])
            // Clicking it again collapses.
            w.display()
            click(w, o.convert(NSPoint(x: f0.midX, y: f0.midY), to: nil))
            XCTAssertFalse(o.isItemExpanded(tree.roots[0]))
            // A click on the row's text selects as a table does.
            w.display()
            let r1 = o.rect(ofRow: 1)
            click(w, o.convert(NSPoint(x: 100, y: r1.midY), to: nil))
            XCTAssertEqual(o.selectedRow, 1)
            w.close()
        }
    }

    func testRightToLeftMirrorsTheIndentation() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, scroll) = makeOutline(tree, in: w)
            o.expandItem(tree.roots[0])
            o.userInterfaceLayoutDirection = .rightToLeft
            w.display()
            let width = scroll.contentView.bounds.width
            let column = o.rect(ofColumn: 0)
            XCTAssertEqual(column.maxX, width, accuracy: 0.5, "the outline column is at the right edge")
            let f0 = o.frameOfOutlineCell(atRow: 0)
            XCTAssertEqual(f0.maxX, column.maxX, accuracy: 0.5, "the triangle sits at the leading (right) edge")
            let cell0 = o.view(atColumn: 0, row: 0, makeIfNecessary: true)!
            XCTAssertEqual(cell0.frame.maxX, column.maxX - NSOutlineView.disclosureWidth, accuracy: 0.5, "the cell ends before the triangle")
            XCTAssertEqual(cell0.frame.minX, column.minX, accuracy: 0.5)
            let cell1 = o.view(atColumn: 0, row: 1, makeIfNecessary: true)!
            XCTAssertEqual(cell1.frame.maxX, column.maxX - NSOutlineView.disclosureWidth - o.indentationPerLevel, accuracy: 0.5, "a child is indented from the right")
            XCTAssertEqual(o.frameOfOutlineCell(atRow: 1).maxX, column.maxX - o.indentationPerLevel, accuracy: 0.5)
            let button = o.rowView(atRow: 1, makeIfNecessary: true)!.subviews.first { $0.identifier == NSOutlineView.disclosureButtonIdentifier } as! _NSOutlineDisclosureButton
            XCTAssertTrue(button.pointsLeft, "collapsed triangles point along the reading direction")
            o.userInterfaceLayoutDirection = .leftToRight
            w.display()
            XCTAssertEqual(o.frameOfOutlineCell(atRow: 0).minX, 0, accuracy: 0.5, "switching back restores the layout")
            XCTAssertFalse(button.pointsLeft)
            w.close()
        }
    }

    func testDisclosureTrianglePixels() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, _) = makeOutline(tree, in: w)
            o.usesAlternatingRowBackgroundColors = false
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            @MainActor func luminance(_ p: NSPoint) -> Int {      // p in outline coordinates
                guard let image = platform.lastImage else { return -1 }
                let data = _pixels(image)
                let c = o.convert(p, to: w.contentView)
                let x = Int((c.x * 2).rounded(.down)), row = image.height - 1 - Int((c.y * 2).rounded(.down))
                let i = row * image.bytesPerRow + x * 4
                return (Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])) / 3
            }
            let f = o.frameOfOutlineCell(atRow: 0)
            let cx = f.midX, cy = f.midY
            // Collapsed: an 8-point-tall triangle pointing right, 4 points deep. A point in
            // its left part is ink; a point left of it is the row background.
            let inCollapsed = NSPoint(x: cx - 1.5, y: cy + 3)
            let inExpanded = NSPoint(x: cx - 3, y: cy - 1.5)
            XCTAssertLessThan(luminance(inCollapsed), 170, "collapsed triangle ink")
            XCTAssertGreaterThan(luminance(inExpanded), 200, "outside the collapsed triangle")
            XCTAssertGreaterThan(luminance(NSPoint(x: cx - 6, y: cy)), 200, "row background beside it")
            o.expandItem(tree.roots[0])
            w.display()
            XCTAssertLessThan(luminance(inExpanded), 170, "expanded: the triangle points down and covers the wide top")
            XCTAssertGreaterThan(luminance(inCollapsed), 200, "and no longer the right-pointing tip region")
            // A selected, emphasized row draws the triangle in the selected text colour (light).
            o.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            w.display()
            XCTAssertGreaterThan(luminance(NSPoint(x: cx, y: cy)), 150, "light ink over the selection")
            w.close()
        }
    }

    func testAccessibilityExposesLevelsAndExpansion() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, _) = makeOutline(tree, in: w)
            o.expandItem(tree.roots[0])
            w.display()
            XCTAssertEqual(o.accessibilityRole(), .outline)
            let element = o._accessibilityElement()
            XCTAssertEqual(element.role, "AXOutline")
            let rows = element.children.filter { $0.role == "AXRow" }
            XCTAssertEqual(rows.count, 6)
            XCTAssertEqual(rows[0].subrole, "AXOutlineRow")
            XCTAssertEqual(rows[0].isExpanded, true)
            XCTAssertEqual(rows[1].isExpanded, false, "Reports is collapsed")
            XCTAssertNil(rows[2].isExpanded, "Notes cannot expand")
            XCTAssertTrue(rows[1].actions.contains(.expand))
            let row1 = o.rowView(atRow: 1, makeIfNecessary: true)!
            XCTAssertEqual(row1.accessibilityDisclosureLevel(), 1)
            XCTAssertEqual(o.rowView(atRow: 0, makeIfNecessary: true)!.accessibilityDisclosureLevel(), 0)
            let triangle = rows[1].children.first { $0.role == "AXDisclosureTriangle" }
            XCTAssertNotNil(triangle)
            XCTAssertEqual(triangle?.value, .number(0))
            XCTAssertEqual(triangle?.label, "expand")
            // Expanding through the row's element, and collapsing through the triangle's press.
            XCTAssertTrue(w.accessibilityPerform(.expand, on: rows[1].id))
            XCTAssertTrue(o.isItemExpanded(tree.roots[0].children[0]))
            // The rows changed shape (a structure notification went out): snapshot again, as
            // assistive technology does, before acting on the new rows.
            w.display()
            let after = o._accessibilityElement().children.filter { $0.role == "AXRow" }
            XCTAssertEqual(after.count, 8)
            XCTAssertEqual(after[1].isExpanded, true)
            XCTAssertTrue(o.rowView(atRow: 1, makeIfNecessary: true)!.isAccessibilityExpanded())
            let triangle2 = after[1].children.first { $0.role == "AXDisclosureTriangle" }!
            XCTAssertEqual(triangle2.value, .number(1))
            XCTAssertTrue(w.accessibilityPerform(.press, on: triangle2.id))
            XCTAssertFalse(o.isItemExpanded(tree.roots[0].children[0]))
            w.display()
            let again = o._accessibilityElement().children.filter { $0.role == "AXRow" }
            XCTAssertTrue(w.accessibilityPerform(.collapse, on: again[0].id))
            XCTAssertEqual(o.numberOfRows, 3)
            w.close()
        }
    }

    func testDelegateProvidesViewsAndRowHeights() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let tree = Tree(roots: sampleTree(), log: Log())
            let (o, _) = makeOutline(tree, in: w)
            w.display()
            XCTAssertEqual(tree.viewRequests, 6, "every visible row asks the delegate for its cells (two columns)")
            XCTAssertEqual((o.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue, "Pictures")
            XCTAssertEqual(o.rect(ofRow: 1).height, 20)
            w.close()
        }
    }
}
