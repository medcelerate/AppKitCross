// NSTableView and NSSegmentedControl on the host backend: data source and delegate
// plumbing, row views for the visible rows, selection with the mouse and keyboard,
// header clicks sorting, the scroll view's header area, and segment tracking.

import XCTest
@testable import AppKit

@MainActor
private final class Planets: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows = [("Mercury", 0), ("Venus", 0), ("Earth", 1), ("Mars", 2), ("Jupiter", 95), ("Saturn", 146), ("Uranus", 28), ("Neptune", 16)]
    var sortChanges: [[NSSortDescriptor]] = []
    var selectionChanges = 0
    var viewRequests = 0
    var refuseRow: Int? = nil

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        tableColumn?.identifier.rawValue == "moons" ? rows[row].1 : rows[row].0
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        sortChanges.append(tableView.sortDescriptors)
        if let d = tableView.sortDescriptors.first {
            if d.key == "name" { rows.sort { d.ascending ? $0.0 < $1.0 : $0.0 > $1.0 } }
            else { rows.sort { d.ascending ? $0.1 < $1.1 : $0.1 > $1.1 } }
        }
        tableView.reloadData()
    }
    func tableViewSelectionDidChange(_ notification: Notification) { selectionChanges += 1 }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { row != refuseRow }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        viewRequests += 1
        return nil      // the table makes label cells from the object values
    }
}

@MainActor
private func makeTable(rows: Planets, in window: NSWindow) -> (NSTableView, NSScrollView) {
    let table = NSTableView(frame: .zero)
    let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    name.title = "Planet"
    name.width = 120
    name.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
    let moons = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("moons"))
    moons.title = "Moons"
    moons.width = 60
    moons.sortDescriptorPrototype = NSSortDescriptor(key: "moons", ascending: true)
    table.addTableColumn(name)
    table.addTableColumn(moons)
    table.dataSource = rows
    table.delegate = rows
    table.rowHeight = 20
    table.allowsMultipleSelection = true
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
    scroll.hasVerticalScroller = true
    scroll.documentView = table
    window.contentView!.addSubview(scroll)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(table)
    scroll.layoutSubtreeIfNeeded()
    return (table, scroll)
}

@MainActor
private func click(_ table: NSTableView, row: Int, flags: NSEvent.ModifierFlags = [], clickCount: Int = 1) {
    let r = table.rect(ofRow: row)
    let p = table.convert(NSPoint(x: 10, y: r.midY), to: nil)
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: flags, timestamp: 0, windowNumber: table.window!.windowNumber, context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1)!
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: flags, timestamp: 0, windowNumber: table.window!.windowNumber, context: nil, eventNumber: 1, clickCount: clickCount, pressure: 0)!
    table.window!.sendEvent(down)
    table.window!.sendEvent(up)
}

@MainActor
private func key(_ view: NSView, _ chars: String, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    view.window!.sendEvent(e)
}

final class TableViewTests: XCTestCase, @unchecked Sendable {
    func testRowsComeFromTheDataSourceAndOnlyVisibleOnesGetViews() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            let rows = Planets()
            let (table, scroll) = makeTable(rows: rows, in: w)
            XCTAssertEqual(table.numberOfRows, 8)
            XCTAssertEqual(table.rect(ofRow: 1).minY, 22, "rows stack from the top with the intercell spacing")
            XCTAssertEqual(table.frame.height, 8 * 22, "the document view is as tall as its rows")
            w.display()
            // 120 points of scroll view minus the header leaves room for about five rows.
            let made = Set(table.subviews.compactMap { ($0 as? NSTableRowView)?._row })
            XCTAssertTrue(made.contains(0) && made.contains(3), "the first rows have views: \(made.sorted())")
            XCTAssertFalse(made.contains(7), "rows below the visible rect have none: \(made.sorted())")
            XCTAssertEqual(table.view(atColumn: 0, row: 0, makeIfNecessary: false).flatMap { ($0 as? NSTableCellView)?.textField?.stringValue }, "Mercury")
            XCTAssertEqual((table.view(atColumn: 1, row: 2, makeIfNecessary: false) as? NSTableCellView)?.textField?.stringValue, "1")
            // Scrolling to the end recycles the top rows and makes the bottom ones.
            table.scrollRowToVisible(7)
            w.display()
            let after = Set(table.subviews.compactMap { ($0 as? NSTableRowView)?._row })
            XCTAssertTrue(after.contains(7), "\(after.sorted())")
            XCTAssertFalse(after.contains(0), "\(after.sorted())")
            XCTAssertNotNil(scroll.subviews.first { $0 is NSTableHeaderView }, "the scroll view shows the header")
            XCTAssertEqual(table.headerView?.frame.height, NSTableHeaderView.defaultHeight)
            XCTAssertLessThan(scroll.contentView.frame.height, 120, "the header takes room from the content")
            w.close()
        }
    }

    func testMouseAndKeyboardSelection() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let rows = Planets()
            let (table, scroll) = makeTable(rows: rows, in: w)
            scroll.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
            w.display()
            click(table, row: 2)
            XCTAssertEqual(table.selectedRowIndexes, [2])
            XCTAssertEqual(table.selectedRow, 2)
            XCTAssertEqual(rows.selectionChanges, 1)
            XCTAssertTrue(table.rowView(atRow: 2, makeIfNecessary: false)!.isSelected)
            click(table, row: 4, flags: .shift)
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(2...4), "shift extends from the anchor")
            click(table, row: 3, flags: .command)
            XCTAssertEqual(table.selectedRowIndexes, [2, 4], "command toggles one row")
            key(table, "\u{F701}")                       // down from the last selected row
            XCTAssertEqual(table.selectedRowIndexes, [5])
            key(table, "\u{F700}", flags: .shift)        // shift-up extends
            XCTAssertEqual(table.selectedRowIndexes, [4, 5])
            // Cmd-A through the responder chain's selectAll:.
            XCTAssertTrue(NSApplication.shared.sendAction(Selector(("selectAll:")), to: nil, from: nil))
            XCTAssertEqual(table.selectedRowIndexes.count, 8)
            // A refused row never enters the selection.
            rows.refuseRow = 6
            click(table, row: 6)
            XCTAssertEqual(table.selectedRowIndexes, [], "the delegate refused row 6, leaving nothing selected")
            table.allowsEmptySelection = false
            table.selectRowIndexes([1], byExtendingSelection: false)
            table.deselectAll(nil)
            XCTAssertEqual(table.selectedRowIndexes, [1], "no empty selection allowed")
            w.close()
        }
    }

    func testDoubleClickFiresTheDoubleActionAndClicksTheAction() {
        MainActor.assumeIsolated {
            final class Target: NSObject, NSSelectorHandling {
                var log: [String] = []
                func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool { log.append(action.description); return true }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let rows = Planets()
            let (table, _) = makeTable(rows: rows, in: w)
            let target = Target()
            table.target = target
            table.action = Selector(("rowClicked:"))
            table.doubleAction = Selector(("rowOpened:"))
            w.display()
            click(table, row: 1)
            XCTAssertEqual(target.log, ["rowClicked:"])
            XCTAssertEqual(table.clickedRow, 1)
            click(table, row: 1, clickCount: 2)
            XCTAssertEqual(target.log.last, "rowOpened:")
            w.close()
        }
    }

    func testHeaderClickSortsThroughTheDataSource() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let rows = Planets()
            let (table, scroll) = makeTable(rows: rows, in: w)
            scroll.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
            w.display()
            let header = table.headerView!
            let moons = header.headerRect(ofColumn: 1)
            let p = header.convert(NSPoint(x: moons.midX, y: moons.midY), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            w.sendEvent(down); w.sendEvent(up)
            XCTAssertEqual(rows.sortChanges.count, 1)
            XCTAssertEqual(table.sortDescriptors.first?.key, "moons")
            XCTAssertEqual(table.sortDescriptors.first?.ascending, true)
            XCTAssertEqual(rows.rows.first?.0, "Mercury")
            w.sendEvent(down); w.sendEvent(up)
            XCTAssertEqual(table.sortDescriptors.first?.ascending, false, "a second click reverses")
            XCTAssertEqual(rows.rows.first?.0, "Saturn")
            w.display()
            XCTAssertEqual((table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NSTableCellView)?.textField?.stringValue, "Saturn", "reloadData refilled the cells")
            XCTAssertTrue(table.highlightedTableColumn === table.tableColumns[1])
            w.close()
        }
    }

    func testColumnsFillTheWidthAndResize() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let rows = Planets()
            let (table, scroll) = makeTable(rows: rows, in: w)
            w.display()
            let available = scroll.contentView.bounds.width
            XCTAssertEqual(table.tableColumns[0].width + table.intercellSpacing.width + table.tableColumns[1].width, available, accuracy: 0.5, "the last column stretches to the clip view")
            table.tableColumns[0].width = 80
            XCTAssertEqual(table.tableColumns[0].width, 80)
            XCTAssertEqual(table.tableColumns[1].width, available - 80 - table.intercellSpacing.width, accuracy: 0.5)
            XCTAssertEqual(table.column(at: NSPoint(x: 100, y: 5)), 1)
            XCTAssertEqual(table.row(at: NSPoint(x: 5, y: 50)), 2)
            XCTAssertEqual(table.frameOfCell(atColumn: 1, row: 2).minX, 83)
            rows.rows.removeLast(3)
            table.noteNumberOfRowsChanged()
            XCTAssertEqual(table.numberOfRows, 5)
            XCTAssertEqual(table.rows(in: NSRect(x: 0, y: 30, width: 10, height: 50)), NSRange(location: 1, length: 3))
            w.close()
        }
    }
}

final class SegmentedControlTests: XCTestCase, @unchecked Sendable {
    @MainActor private func press(_ control: NSSegmentedControl, segment: Int) {
        guard let cell = control.cell as? NSSegmentedCell else { return }
        let r = cell._segmentRects(in: control.bounds.insetBy(dx: 0.5, dy: 0.5), distribution: control.segmentDistribution)[segment]
        let p = control.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: control.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: 0, windowNumber: control.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        control.window!.sendEvent(down)
        control.window!.sendEvent(up)
    }

    func testSelectOneSelectAnyAndMomentary() {
        MainActor.assumeIsolated {
            final class Target: NSObject, NSSelectorHandling {
                var fired: [Int] = []
                func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool { fired.append((sender as? NSSegmentedControl)?.selectedSegment ?? -9); return true }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let target = Target()
            let control = NSSegmentedControl(labels: ["Day", "Week", "Month"], trackingMode: .selectOne, target: target, action: Selector(("changed:")))
            XCTAssertEqual(control.segmentCount, 3)
            XCTAssertGreaterThan(control.frame.width, 90, "sized to its labels")
            control.frame.origin = NSPoint(x: 20, y: 40)
            w.contentView!.addSubview(control)
            w.makeKeyAndOrderFront(nil)
            control.selectedSegment = 0
            press(control, segment: 2)
            XCTAssertEqual(control.selectedSegment, 2)
            XCTAssertFalse(control.isSelected(forSegment: 0), "selectOne is exclusive")
            XCTAssertEqual(target.fired, [2])
            control.setEnabled(false, forSegment: 1)
            press(control, segment: 1)
            XCTAssertEqual(control.selectedSegment, 2, "a disabled segment ignores the click")
            XCTAssertEqual(target.fired, [2])
            // selectAny toggles independently.
            control.trackingMode = .selectAny
            press(control, segment: 0)
            XCTAssertTrue(control.isSelected(forSegment: 0) && control.isSelected(forSegment: 2))
            press(control, segment: 0)
            XCTAssertFalse(control.isSelected(forSegment: 0))
            // Momentary fires with the pressed segment selected, then clears it.
            control.trackingMode = .momentary
            control.selectedSegment = -1
            target.fired = []
            press(control, segment: 0)
            XCTAssertEqual(target.fired, [0])
            XCTAssertEqual(control.selectedSegment, -1)
            w.close()
        }
    }

    func testKeyboardMovesAndTagsSelect() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let control = NSSegmentedControl(labels: ["A", "B", "C"], trackingMode: .selectOne, target: nil, action: nil)
            control.setTag(10, forSegment: 0); control.setTag(20, forSegment: 1); control.setTag(30, forSegment: 2)
            w.contentView!.addSubview(control)
            w.makeKeyAndOrderFront(nil)
            XCTAssertTrue(control.selectSegment(withTag: 20))
            XCTAssertEqual(control.selectedSegment, 1)
            XCTAssertEqual(control.doubleValueForSelectedSegment, 1)
            w.makeFirstResponder(control)
            key(control, "\u{F703}")       // right moves the key segment
            key(control, " ")              // space activates it
            XCTAssertEqual(control.selectedSegment, 2)
            XCTAssertEqual(control.label(forSegment: 2), "C")
            w.close()
        }
    }
}
