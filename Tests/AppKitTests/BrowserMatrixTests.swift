// NSMatrix, NSForm/NSFormCell and NSBrowser/NSBrowserCell (ADR-0032): matrix selection
// modes, tags and structure, radio exclusivity by mouse and keyboard, form layout and
// field editing, browser content from item-based, passive and active delegates, the path
// round trip, mouse and keyboard navigation between columns, and a radio matrix's pixels.

import XCTest
@testable import AppKit

// MARK: - Helpers

@MainActor
private final class ActionSink: NSObject, NSSelectorHandling {
    var count = 0
    var doubleCount = 0
    var senders: [Any?] = []
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("act:")): count += 1; senders.append(sender); return true
        case Selector(("doubleAct:")): doubleCount += 1; return true
        default: return false
        }
    }
}

@MainActor
private func window(_ size: NSSize = NSSize(width: 320, height: 200)) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
    w.backgroundColor = .white
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func key(_ w: NSWindow, _ chars: String, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    w.sendEvent(e)
}

@MainActor
private func mouse(_ w: NSWindow, _ type: NSEvent.EventType, _ p: NSPoint, count: Int = 1, flags: NSEvent.ModifierFlags = []) {
    w.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1)!)
}

@MainActor
private func click(_ w: NSWindow, _ p: NSPoint, count: Int = 1, flags: NSEvent.ModifierFlags = []) {
    mouse(w, .leftMouseDown, p, count: count, flags: flags)
    mouse(w, .leftMouseUp, p, count: count, flags: flags)
}

/// A point of `view` in window coordinates.
@MainActor
private func at(_ view: NSView, _ x: CGFloat, _ y: CGFloat) -> NSPoint { view.convert(NSPoint(x: x, y: y), to: nil) }

/// The middle of a matrix cell, in window coordinates.
@MainActor
private func center(_ m: NSMatrix, _ row: Int, _ col: Int = 0) -> NSPoint {
    let f = m.cellFrame(atRow: row, column: col)
    return at(m, f.midX, f.midY)
}

@MainActor
private func image(_ w: NSWindow) -> CGImage? {
    w.display()
    return (Mirror(reflecting: w).descendant("_platform") as? HostWindow)?.lastImage
}

/// The pixel at AppKit window point (x, y), from the host window's 2x image.
@MainActor
private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat, windowWidth: CGFloat = 320) -> (r: Int, g: Int, b: Int) {
    let data = _pixels(image)
    let scale = CGFloat(image.width) / windowWidth
    let px = Int(x * scale), py = Int(y * scale)
    let row = image.height - 1 - py
    let i = row * image.bytesPerRow + px * 4
    return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))
}

@MainActor
private func radioPrototype() -> NSButtonCell {
    let c = NSButtonCell(textCell: "Option")
    c.setButtonType(.radio)
    return c
}

@MainActor
private func radioMatrix(rows: Int = 3) -> NSMatrix {
    let m = NSMatrix(frame: NSRect(x: 0, y: 0, width: 120, height: CGFloat(rows) * 20), mode: .radioModeMatrix, prototype: radioPrototype(), numberOfRows: rows, numberOfColumns: 1)
    for (i, c) in m.cells.enumerated() { c.title = "Option \(i)"; c.tag = 10 + i }
    return m
}

/// A small tree for item-based browsers: "/" → a, b, readme; a → a1, a2; a1 → deep.
@MainActor
private final class Node: NSObject {
    let name: String
    let children: [Node]?
    init(_ name: String, _ children: [Node]? = nil) { self.name = name; self.children = children }
}

@MainActor
private final class ItemDelegate: NSObject, NSBrowserDelegate {
    let root = Node("/", [
        Node("a", [Node("a1", [Node("deep")]), Node("a2")]),
        Node("b", [Node("b1")]),
        Node("readme"),
    ])
    var childCountCalls: [String: Int] = [:]
    var lastColumnChanges: [(Int, Int)] = []
    func rootItem(for browser: NSBrowser) -> Any? { root }
    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        let n = (item as? Node) ?? root
        childCountCalls[n.name, default: 0] += 1
        return n.children?.count ?? 0
    }
    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any { ((item as? Node) ?? root).children![index] }
    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool { (item as? Node)?.children == nil }
    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? { (item as? Node)?.name }
    func browser(_ browser: NSBrowser, didChangeLastColumn oldLastColumn: Int, toColumn column: Int) { lastColumnChanges.append((oldLastColumn, column)) }
}

/// Passive matrix-based: rows per column, filled in willDisplayCell.
@MainActor
private final class PassiveDelegate: NSObject, NSBrowserDelegate {
    var rowCountCalls: [Int] = []
    var displayed: [Int: Int] = [:]
    func browser(_ sender: NSBrowser, numberOfRowsInColumn column: Int) -> Int { rowCountCalls.append(column); return column == 0 ? 3 : 2 }
    func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        displayed[column, default: 0] += 1
        guard let c = cell as? NSBrowserCell else { return }
        c.stringValue = "c\(column)r\(row)"
        c.isLeaf = column >= 2
    }
    func browser(_ sender: NSBrowser, titleOfColumn column: Int) -> String? { "Column \(column)" }
}

/// Active matrix-based: the delegate fills the matrix.
@MainActor
private final class ActiveDelegate: NSObject, NSBrowserDelegate {
    var created: [Int] = []
    func browser(_ sender: NSBrowser, createRowsForColumn column: Int, in matrix: NSMatrix) {
        created.append(column)
        for i in 0..<2 {
            matrix.addRow()
            let c = matrix.cell(atRow: i, column: 0) as! NSBrowserCell
            c.stringValue = "x\(column)\(i)"
            c.isLeaf = column >= 1
        }
    }
}

@MainActor
private func browser(_ w: NSWindow, delegate: NSBrowserDelegate) -> NSBrowser {
    let b = NSBrowser(frame: NSRect(x: 0, y: 0, width: 300, height: 180))
    w.contentView?.addSubview(b)
    b.delegate = delegate
    return b
}

// MARK: - Matrix

final class BrowserMatrixTests: XCTestCase, @unchecked Sendable {

    func testRadioMatrixStartsWithOneSelectedAndStaysExclusive() {
        MainActor.assumeIsolated {
            let m = radioMatrix()
            XCTAssertEqual(m.numberOfRows, 3)
            XCTAssertEqual(m.numberOfColumns, 1)
            XCTAssertFalse(m.allowsEmptySelection)
            XCTAssertEqual(m.selectedRow, 0, "a radio matrix without empty selection selects its first cell")
            XCTAssertEqual(m.cells.map { $0.state }, [.on, .off, .off])
            m.selectCell(atRow: 2, column: 0)
            XCTAssertEqual(m.cells.map { $0.state }, [.off, .off, .on])
            XCTAssertEqual(m.selectedCell()?.title, "Option 2")
            m.deselectAllCells()
            XCTAssertEqual(m.selectedRow, 2, "no empty selection: deselecting does nothing")
            m.setState(1, atRow: 1, column: 0)
            XCTAssertEqual(m.cells.map { $0.state }, [.off, .on, .off], "turning a cell on turns the others off")
            m.allowsEmptySelection = true
            m.deselectAllCells()
            XCTAssertNil(m.selectedCell())
            XCTAssertEqual(m.selectedRow, -1)
            XCTAssertTrue(m.cells.allSatisfy { $0.state == .off })
            // The prototype's copies are separate cells with its settings.
            XCTAssertEqual(Set(m.cells.map { ObjectIdentifier($0) }).count, 3)
            XCTAssertTrue(m.cells.allSatisfy { ($0 as? NSButtonCell)?._buttonType == .radio })
            XCTAssertFalse(m.cells.contains { $0 === m.prototype })
        }
    }

    func testTagsSelectCellsAndAnswerSelectedTag() {
        MainActor.assumeIsolated {
            let m = radioMatrix()
            XCTAssertTrue(m.selectCell(withTag: 12))
            XCTAssertEqual(m.selectedRow, 2)
            XCTAssertEqual(m.selectedTag(), 12)
            XCTAssertFalse(m.selectCell(withTag: 99))
            XCTAssertEqual(m.cell(withTag: 11)?.title, "Option 1")
            var row = -1, col = -1
            XCTAssertTrue(m.getRow(&row, column: &col, of: m.cell(withTag: 11)!))
            XCTAssertEqual([row, col], [1, 0])
        }
    }

    func testListModeSelectsRangesAllAndNone() {
        MainActor.assumeIsolated {
            let m = NSMatrix(frame: .zero, mode: .listModeMatrix, cellClass: NSTextFieldCell.self, numberOfRows: 2, numberOfColumns: 3)
            XCTAssertEqual(m.cellSize, NSSize(width: 100, height: 17), "no frame: the default cell size")
            XCTAssertEqual(m.frame.size, NSSize(width: 302, height: 35), "and the matrix sizes to its cells")
            XCTAssertNil(m.selectedCell(), "a list matrix starts empty")
            m.selectCell(atRow: 1, column: 1)
            XCTAssertEqual(m.selectedCells.count, 1)
            XCTAssertTrue(m.cell(atRow: 1, column: 1)!.isHighlighted)
            // Reading order: positions 1...4 are (0,1) (0,2) (1,0) (1,1).
            m.isSelectionByRect = false
            m.setSelectionFrom(1, to: 4, anchor: 1, highlight: true)
            XCTAssertEqual(m.selectedCells.count, 4)
            // By rectangle: (0,1)...(1,2) is four cells in two columns.
            m.deselectAllCells()
            m.isSelectionByRect = true
            m.setSelectionFrom(1, to: 5, anchor: 1, highlight: true)
            XCTAssertEqual(Set(m.selectedCells.map { m._position(of: $0)!.column }), [1, 2])
            XCTAssertEqual(m.selectedCells.count, 4)
            m.selectAll(nil)
            XCTAssertEqual(m.selectedCells.count, 6)
            m.deselectAllCells()
            XCTAssertTrue(m.selectedCells.isEmpty)
            XCTAssertTrue(m.cells.allSatisfy { !$0.isHighlighted })
        }
    }

    func testStructureEditsKeepCellsAndGeometry() {
        MainActor.assumeIsolated {
            let m = NSMatrix(frame: NSRect(x: 0, y: 0, width: 201, height: 41), mode: .highlightModeMatrix, cellClass: NSButtonCell.self, numberOfRows: 2, numberOfColumns: 2)
            XCTAssertEqual(m.cellSize, NSSize(width: 100, height: 20), "a framed matrix shares its frame among the cells")
            XCTAssertEqual(m.cellFrame(atRow: 1, column: 1), NSRect(x: 101, y: 21, width: 100, height: 20))
            XCTAssertEqual(m.cell(atRow: 0, column: 0)?.title, "Button", "NSButtonCell's own init")
            let original = m.cell(atRow: 1, column: 0)!
            m.insertRow(0)
            XCTAssertEqual(m.numberOfRows, 3)
            XCTAssertTrue(m.cell(atRow: 2, column: 0) === original)
            m.addColumn()
            XCTAssertEqual(m.numberOfColumns, 3)
            XCTAssertEqual(m.cells.count, 9)
            let replacement = NSButtonCell(textCell: "New")
            m.putCell(replacement, atRow: 0, column: 2)
            XCTAssertTrue(m.cell(atRow: 0, column: 2) === replacement)
            XCTAssertTrue(replacement.controlView === m)
            m.removeColumn(0)
            m.removeRow(1)
            XCTAssertEqual([m.numberOfRows, m.numberOfColumns], [2, 2])
            XCTAssertTrue(m.cell(atRow: 0, column: 1) === replacement)
            m.renewRows(1, columns: 1)
            XCTAssertEqual(m.cells.count, 1)
            var rows = 0, cols = 0
            m.getNumberOfRows(&rows, columns: &cols)
            XCTAssertEqual([rows, cols], [1, 1])
            // Hit testing skips the spacing.
            m.renewRows(2, columns: 2)
            var r = -1, c = -1
            XCTAssertTrue(m.getRow(&r, column: &c, for: NSPoint(x: 150, y: 30)))
            XCTAssertEqual([r, c], [1, 1])
            XCTAssertFalse(m.getRow(&r, column: &c, for: NSPoint(x: 100.5, y: 5)), "between columns")
            m.sizeToCells()
            XCTAssertEqual(m.frame.size, NSSize(width: 201, height: 41))
        }
    }

    func testRadioClicksAndArrowsSelectAndSendTheAction() {
        MainActor.assumeIsolated {
            let w = window()
            let m = radioMatrix()
            m.setFrameOrigin(NSPoint(x: 20, y: 20))
            w.contentView?.addSubview(m)
            let sink = ActionSink()
            m.target = sink
            m.action = Selector(("act:"))
            click(w, center(m, 1))
            XCTAssertEqual(m.selectedRow, 1)
            XCTAssertEqual(m.cells.map { $0.state }, [.off, .on, .off])
            XCTAssertEqual(sink.count, 1)
            XCTAssertTrue(sink.senders.last as AnyObject === m, "the matrix sends its action")
            XCTAssertTrue(w.firstResponder === m)
            key(w, "\u{F701}")
            XCTAssertEqual(m.selectedRow, 2, "Down moves the radio selection")
            XCTAssertEqual(sink.count, 2)
            key(w, "\u{F701}")
            XCTAssertEqual(m.selectedRow, 2, "and stops at the last cell")
            key(w, "\u{F700}"); key(w, "\u{F700}")
            XCTAssertEqual(m.selectedRow, 0)
            XCTAssertEqual(m.cells.filter { $0.state == .on }.count, 1)
            // A disabled cell is skipped by the arrows and ignores clicks.
            m.cell(atRow: 1, column: 0)?.isEnabled = false
            key(w, "\u{F701}")
            XCTAssertEqual(m.selectedRow, 2)
            click(w, center(m, 1))
            XCTAssertEqual(m.selectedRow, 2)
            // A cell's own action wins over the matrix's.
            let cellSink = ActionSink()
            m.cell(atRow: 0, column: 0)?.target = cellSink
            m.cell(atRow: 0, column: 0)?.action = Selector(("act:"))
            click(w, center(m, 0))
            XCTAssertEqual(cellSink.count, 1)
            w.close()
        }
    }

    func testHighlightModeTogglesStatesAndListModeClicksExtend() {
        MainActor.assumeIsolated {
            let w = window()
            let proto = NSButtonCell(textCell: "Check")
            proto.setButtonType(.switch)
            let m = NSMatrix(frame: NSRect(x: 10, y: 10, width: 100, height: 60), mode: .highlightModeMatrix, prototype: proto, numberOfRows: 3, numberOfColumns: 1)
            w.contentView?.addSubview(m)
            click(w, center(m, 0))
            click(w, center(m, 2))
            XCTAssertEqual(m.cells.map { $0.state }, [.on, .off, .on], "each click flips its own cell")
            click(w, center(m, 0))
            XCTAssertEqual(m.cells.map { $0.state }, [.off, .off, .on])
            XCTAssertEqual(m.selectedRow, 0, "the last clicked cell is the selected cell")

            let list = NSMatrix(frame: NSRect(x: 150, y: 10, width: 100, height: 80), mode: .listModeMatrix, cellClass: NSTextFieldCell.self, numberOfRows: 4, numberOfColumns: 1)
            for (i, c) in list.cells.enumerated() { c.stringValue = "Row \(i)"; c.isEditable = false; c.isSelectable = false }
            w.contentView?.addSubview(list)
            XCTAssertFalse(list.acceptsFirstMouse(for: nil), "a list ignores the activating click")
            click(w, center(list, 1))
            click(w, center(list, 3), flags: .shift)
            XCTAssertEqual(list.selectedCells.map { $0.stringValue }, ["Row 1", "Row 2", "Row 3"])
            click(w, center(list, 2), flags: .command)
            XCTAssertEqual(list.selectedCells.map { $0.stringValue }, ["Row 1", "Row 3"])
            // Dragging from a cell selects the run.
            mouse(w, .leftMouseDown, center(list, 0))
            mouse(w, .leftMouseDragged, center(list, 2))
            mouse(w, .leftMouseUp, center(list, 2))
            XCTAssertEqual(list.selectedCells.map { $0.stringValue }, ["Row 0", "Row 1", "Row 2"])
            w.close()
        }
    }

    // MARK: - Form

    func testFormLaysOutTitlesAndEntries() {
        MainActor.assumeIsolated {
            let form = NSForm(frame: NSRect(x: 0, y: 0, width: 260, height: 100))
            XCTAssertTrue(form.cellClass == NSFormCell.self)
            let name = form.addEntry("Name:")
            let address = form.addEntry("Street address:")
            let city = form.insertEntry("City:", at: 1)!
            XCTAssertEqual(form.numberOfRows, 3)
            XCTAssertEqual(form.numberOfColumns, 1)
            XCTAssertTrue(form.cell(at: 1) as AnyObject === city)
            XCTAssertEqual((form.cell(at: 2) as? NSFormCell)?.title, "Street address:")
            XCTAssertEqual(name.stringValue, "", "the entry starts empty; the string is the title")
            XCTAssertEqual(form.cellSize.width, 260, "entries are as wide as the form")
            // Every title is as wide as the widest, so the entries line up.
            form.display()
            form._alignTitles()
            let widest = address._ownTitleWidth
            XCTAssertGreaterThan(widest, name._ownTitleWidth)
            XCTAssertEqual(name.titleWidth, widest)
            XCTAssertEqual(city.titleWidth, widest)
            let e0 = name._entryFrame(forBounds: form.cellFrame(atRow: 0, column: 0))
            let e2 = address._entryFrame(forBounds: form.cellFrame(atRow: 2, column: 0))
            XCTAssertEqual(e0.minX, e2.minX)
            XCTAssertEqual(e0.maxX, 260)
            XCTAssertEqual(form.cellFrame(atRow: 1, column: 0).minY, 22 + 8, "22 pt entries, 8 pt apart")
            form.setInterlineSpacing(4)
            XCTAssertEqual(form.cellFrame(atRow: 1, column: 0).minY, 26)
            form.setEntryWidth(200)
            XCTAssertEqual(form.cellSize.width, 200)
            name.tag = 7
            XCTAssertEqual(form.indexOfCell(withTag: 7), 0)
            XCTAssertEqual(form.indexOfCell(withTag: 8), -1)
            name.titleWidth = 30
            XCTAssertEqual(name.titleWidth, 30, "an explicit title width wins")
            form.removeEntry(at: 1)
            XCTAssertEqual(form.numberOfRows, 2)
            XCTAssertTrue(form.cell(at: 1) as AnyObject === address)
            // A form cell made directly: the string is its title.
            let solo = NSFormCell(textCell: "Zip:")
            XCTAssertEqual(solo.title, "Zip:")
            XCTAssertTrue(solo.isEditable)
            XCTAssertTrue(solo.isBezeled)
        }
    }

    func testFormEntriesEditInTheFieldEditorAndTabBetween() {
        MainActor.assumeIsolated {
            let w = window()
            let form = NSForm(frame: NSRect(x: 10, y: 20, width: 260, height: 120))
            let first = form.addEntry("First:")
            let second = form.addEntry("Second:")
            w.contentView?.addSubview(form)
            let sink = ActionSink()
            form.target = sink
            form.action = Selector(("act:"))
            var began = 0, ended = 0
            let o1 = NotificationCenter.default.addObserver(forName: NSControl.textDidBeginEditingNotification, object: form, queue: nil) { _ in began += 1 }
            let o2 = NotificationCenter.default.addObserver(forName: NSControl.textDidEndEditingNotification, object: form, queue: nil) { _ in ended += 1 }
            defer { NotificationCenter.default.removeObserver(o1); NotificationCenter.default.removeObserver(o2) }

            form.selectText(at: 0)
            let editor = form.currentEditor() as? NSTextView
            XCTAssertNotNil(editor, "selectText(at:) starts editing the entry")
            XCTAssertTrue(w.firstResponder === editor)
            XCTAssertEqual(form.indexOfSelectedItem(), 0)
            XCTAssertTrue(first._hidesEntryText, "the entry's text is the editor's while editing")
            let entry = first._entryTextRect(forBounds: form.cellFrame(atRow: 0, column: 0))
            XCTAssertEqual(editor?.frame, entry, "the editor sits over the entry, right of the title")
            for ch in "Ada" { key(w, String(ch)) }
            XCTAssertEqual(first.stringValue, "Ada", "the cell follows the editor")
            XCTAssertEqual(began, 1)
            key(w, "\t")
            XCTAssertEqual(first.stringValue, "Ada")
            XCTAssertFalse(first._hidesEntryText)
            XCTAssertEqual(form.indexOfSelectedItem(), 1, "Tab moves to the next entry")
            XCTAssertTrue(w.firstResponder === form.currentEditor())
            for ch in "Lovelace" { key(w, String(ch)) }
            key(w, "\r")
            XCTAssertEqual(second.stringValue, "Lovelace")
            XCTAssertEqual(sink.count, 1, "Return sends the form's action")
            XCTAssertNotNil(form.currentEditor(), "and keeps editing, as a text field does")
            XCTAssertEqual(ended, 2)
            // Clicking the first entry moves editing there.
            click(w, at(form, entry.midX, entry.midY))
            XCTAssertEqual(form.indexOfSelectedItem(), 0)
            XCTAssertTrue(form.abortEditing())
            XCTAssertNil(form.currentEditor())
            XCTAssertEqual(first.stringValue, "Ada")
            w.close()
        }
    }

    // MARK: - Browser

    func testItemBrowserPathRoundTripAndDelegateCalls() {
        MainActor.assumeIsolated {
            let w = window()
            let d = ItemDelegate()
            let b = browser(w, delegate: d)
            XCTAssertTrue(b.isLoaded, "a browser in a window loads column zero when it gets a delegate")
            XCTAssertEqual(b.lastColumn, 0)
            XCTAssertEqual(d.childCountCalls["/"], 1, "column 0 asks for the root's children once")
            XCTAssertEqual(b.matrix(inColumn: 0)?.numberOfRows, 3)
            XCTAssertEqual(b.matrix(inColumn: 0)?.cells.map { $0.stringValue }, ["a", "b", "readme"])
            XCTAssertEqual((b.loadedCell(atRow: 2, column: 0) as? NSBrowserCell)?.isLeaf, true)
            XCTAssertEqual((b.loadedCell(atRow: 0, column: 0) as? NSBrowserCell)?.isLeaf, false)
            XCTAssertEqual(b.path(), "/")

            XCTAssertTrue(b.setPath("/a/a1/deep"))
            XCTAssertEqual(b.path(), "/a/a1/deep")
            XCTAssertEqual(b.lastColumn, 2, "deep is a leaf: no column after it")
            XCTAssertEqual(b.selectedColumn, 2)
            XCTAssertEqual(b.selectionIndexPath, IndexPath(indexes: [0, 0, 0]))
            XCTAssertEqual(b.path(toColumn: 2), "/a/a1")
            XCTAssertEqual(d.childCountCalls["a"], 1, "each column asks for its parent's children once")
            XCTAssertEqual(d.childCountCalls["a1"], 1)
            XCTAssertEqual((b.item(atRow: 0, inColumn: 2) as? Node)?.name, "deep")
            XCTAssertEqual((b.parentForItems(inColumn: 2) as? Node)?.name, "a1")
            XCTAssertEqual(b.indexPath(forColumn: 2), IndexPath(indexes: [0, 0]))
            XCTAssertEqual((b.item(at: IndexPath(indexes: [1, 0])) as? Node)?.name, "b1")
            let selected: Any? = b.selectedCell()
            XCTAssertEqual((selected as? NSCell)?.stringValue, "deep")
            XCTAssertEqual(b.title(ofColumn: 1), "a", "titles come from the previous column")
            XCTAssertEqual(b.title(ofColumn: 2), "a1")

            // A shorter path drops the later columns; a branch shows its children.
            XCTAssertTrue(b.setPath("/b"))
            XCTAssertEqual(b.path(), "/b")
            XCTAssertEqual(b.lastColumn, 1, "b is a branch: its children show in column 1")
            XCTAssertEqual(b.matrix(inColumn: 1)?.cells.map { $0.stringValue }, ["b1"])
            XCTAssertEqual(b.selectedColumn, 0)
            XCTAssertFalse(b.setPath("/a/missing"), "an unknown component fails")
            XCTAssertEqual(b.path(), "/a")
            XCTAssertTrue(d.lastColumnChanges.contains { $0 == (2, 0) || $0 == (2, 1) }, "the delegate hears about lastColumn changes")

            b.selectionIndexPath = IndexPath(indexes: [0, 1])
            XCTAssertEqual(b.path(), "/a/a2")
            b.selectionIndexPath = nil
            XCTAssertEqual(b.path(), "/")
            XCTAssertEqual(b.lastColumn, 0)
            b.pathSeparator = ":"
            XCTAssertTrue(b.setPath(":a:a1"))
            XCTAssertEqual(b.path(), ":a:a1")
            w.close()
        }
    }

    func testMatrixDelegatesLoadEachColumnOnce() {
        MainActor.assumeIsolated {
            let w = window()
            let passive = PassiveDelegate()
            let b = browser(w, delegate: passive)
            XCTAssertEqual(passive.rowCountCalls, [0])
            XCTAssertEqual(passive.displayed[0], 3, "willDisplayCell once per row")
            XCTAssertEqual(b.title(ofColumn: 0), "Column 0", "the delegate's titles win")
            b.selectRow(1, inColumn: 0)
            XCTAssertEqual(passive.rowCountCalls, [0, 1])
            XCTAssertEqual(passive.displayed[1], 2)
            XCTAssertEqual(b.lastColumn, 1)
            XCTAssertEqual(b.path(), "/c0r1")
            b.selectRow(0, inColumn: 1)
            XCTAssertEqual(b.lastColumn, 2)
            XCTAssertEqual(b.matrix(inColumn: 2)?.cells.map { $0.stringValue }, ["c2r0", "c2r1"])
            b.selectRow(1, inColumn: 2)
            XCTAssertEqual(b.lastColumn, 2, "leaves add no column")
            XCTAssertEqual(b.path(), "/c0r1/c1r0/c2r1")
            XCTAssertTrue(b.setPath("/c0r2/c1r1"))
            XCTAssertEqual(b.path(), "/c0r2/c1r1")
            XCTAssertNil(b.item(atRow: 0, inColumn: 0), "matrix-based browsers have no items")
            b.reloadColumn(0)
            XCTAssertEqual(b.path(), "/c0r2/c1r1", "reloading keeps a selection that still exists")

            let active = ActiveDelegate()
            b.delegate = active
            XCTAssertEqual(active.created, [0])
            XCTAssertEqual(b.matrix(inColumn: 0)?.cells.map { $0.stringValue }, ["x00", "x01"])
            b.selectRow(0, inColumn: 0)
            XCTAssertEqual(active.created, [0, 1])
            XCTAssertEqual(b.lastColumn, 1)
            XCTAssertTrue((b.loadedCell(atRow: 0, column: 1) as? NSBrowserCell)?.isLoaded ?? false)
            w.close()
        }
    }

    func testBrowserMouseAndArrowNavigation() {
        MainActor.assumeIsolated {
            let w = window()
            let d = ItemDelegate()
            let b = browser(w, delegate: d)
            let sink = ActionSink()
            b.target = sink
            b.action = Selector(("act:"))
            b.doubleAction = Selector(("doubleAct:"))
            let m0 = b.matrix(inColumn: 0)!
            XCTAssertEqual(b.numberOfVisibleColumns, 2, "three 100 pt columns and their separators need 302 pt")
            b.minColumnWidth = 90
            XCTAssertEqual(b.numberOfVisibleColumns, 3)
            XCTAssertEqual(b.width(ofColumn: 0), (300 - 2) / 3)
            XCTAssertEqual(b.frame(ofColumn: 1).minX, b.frame(ofColumn: 0).maxX + 1)
            XCTAssertEqual(b.frame(ofColumn: 0).minY, b.titleHeight)

            click(w, center(m0, 0))
            XCTAssertEqual(b.path(), "/a")
            XCTAssertEqual(b.lastColumn, 1, "clicking a branch opens its column")
            XCTAssertEqual(b.clickedColumn, 0)
            XCTAssertEqual(b.clickedRow, 0)
            XCTAssertEqual(sink.count, 1)
            XCTAssertTrue(w.firstResponder === m0)
            let r = b.frame(ofRow: 1, inColumn: 0)
            var row = -1, col = -1
            XCTAssertTrue(b.getRow(&row, column: &col, for: NSPoint(x: r.midX, y: r.midY)))
            XCTAssertEqual([row, col], [1, 0])

            // Down moves within the column, reloading the next one, and sends the action.
            key(w, "\u{F701}")
            XCTAssertEqual(b.path(), "/b")
            XCTAssertEqual(b.matrix(inColumn: 1)?.cells.map { $0.stringValue }, ["b1"])
            XCTAssertEqual(sink.count, 2)
            // Right goes into the children, selecting the first.
            key(w, "\u{F703}")
            XCTAssertEqual(b.path(), "/b/b1")
            XCTAssertTrue(w.firstResponder === b.matrix(inColumn: 1))
            XCTAssertEqual(sink.count, 3)
            key(w, "\u{F703}")
            XCTAssertEqual(b.path(), "/b/b1", "a leaf has no children to enter")
            // Left goes back to the parent, which keeps its selection.
            key(w, "\u{F702}")
            XCTAssertEqual(b.path(), "/b")
            XCTAssertTrue(w.firstResponder === m0)
            XCTAssertEqual(b.lastColumn, 1)
            // Without sendsActionOnArrowKeys the selection still moves, silently.
            b.sendsActionOnArrowKeys = false
            let before = sink.count
            key(w, "\u{F700}")
            XCTAssertEqual(b.path(), "/a")
            XCTAssertEqual(sink.count, before)
            // Type select.
            key(w, "r")
            XCTAssertEqual(b.path(), "/readme")
            XCTAssertEqual(b.lastColumn, 0, "a leaf closes the columns after it")
            // Double-click sends the double action.
            click(w, center(m0, 2), count: 2)
            XCTAssertEqual(sink.doubleCount, 1)
            w.close()
        }
    }

    func testColumnsScrollAndResize() {
        MainActor.assumeIsolated {
            let w = window()
            let d = ItemDelegate()
            let b = browser(w, delegate: d)
            b.maxVisibleColumns = 2
            XCTAssertEqual(b.numberOfVisibleColumns, 2)
            XCTAssertEqual(b.width(ofColumn: 0), (300 - 1) / 2)
            XCTAssertTrue(b.setPath("/a/a1"))
            XCTAssertEqual(b.lastColumn, 2)
            XCTAssertEqual(b.firstVisibleColumn, 1, "the newest column scrolls into view")
            XCTAssertEqual(b.lastVisibleColumn, 2)
            XCTAssertTrue(b.matrix(inColumn: 0)!.enclosingScrollView!.isHidden)
            b.scrollColumnsLeft(by: 1)
            XCTAssertEqual(b.firstVisibleColumn, 0)
            b.scrollColumnToVisible(2)
            XCTAssertEqual(b.firstVisibleColumn, 1)
            b.scrollColumnsLeft(by: 5)
            XCTAssertEqual(b.firstVisibleColumn, 0)

            // User resizing: drag column 0's right edge.
            b.columnResizingType = .userColumnResizing
            b.setDefaultColumnWidth(120)
            XCTAssertEqual(b.width(ofColumn: 0), 120)
            var notified = 0
            let o = NotificationCenter.default.addObserver(forName: NSBrowser.columnConfigurationDidChangeNotification, object: b, queue: nil) { _ in notified += 1 }
            defer { NotificationCenter.default.removeObserver(o) }
            let edge = b.frame(ofColumn: 0).maxX
            mouse(w, .leftMouseDown, at(b, edge, 60))
            mouse(w, .leftMouseDragged, at(b, edge + 30, 60))
            mouse(w, .leftMouseUp, at(b, edge + 30, 60))
            XCTAssertEqual(b.width(ofColumn: 0), 150)
            XCTAssertEqual(b.width(ofColumn: 1), 120)
            XCTAssertEqual(notified, 1)
            b.setWidth(10, ofColumn: 1)
            XCTAssertEqual(b.width(ofColumn: 1), b.minColumnWidth, "no narrower than minColumnWidth")
            XCTAssertEqual(b.columnContentWidth(forColumnWidth: 150) + NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle), 150)
            w.close()
        }
    }

    // MARK: - Pixels

    func testRadioMatrixDrawsSelectedIndicatorWithTheAccentColour() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("needs the host backend (APPKITWIN_HOST_BACKEND=1)") }
            let w = window(NSSize(width: 320, height: 160))
            let m = radioMatrix()
            m.setFrameOrigin(NSPoint(x: 20, y: 20))
            w.contentView?.addSubview(m)
            m.selectCell(atRow: 1, column: 0)
            guard let img = image(w) else { return XCTFail("no host image") }
            // The indicator is a 14 pt circle at x 2 in each cell; its ring centre (between
            // the outer edge and the inner dot) is about 3 pt in.
            @MainActor func ring(_ row: Int) -> (r: Int, g: Int, b: Int) {
                let f = m.cellFrame(atRow: row, column: 0)
                let p = m.convert(NSPoint(x: f.minX + 2 + 3, y: f.midY), to: nil)
                return pixel(img, p.x, p.y)
            }
            let on = ring(1), off0 = ring(0), off2 = ring(2)
            XCTAssertGreaterThan(on.b, on.r + 60, "the selected radio's indicator is accent blue: \(on)")
            for off in [off0, off2] {
                XCTAssertGreaterThan(off.r, 200, "unselected indicators stay light: \(off)")
                XCTAssertLessThan(abs(off.r - off.b), 30, "and grey/white rather than blue: \(off)")
            }
            // The title is drawn beside the indicator (dark text pixels somewhere in the row).
            let f = m.cellFrame(atRow: 1, column: 0)
            var dark = 0
            for x in stride(from: f.minX + 24, to: f.minX + 70, by: 1) {
                let p = m.convert(NSPoint(x: x, y: f.midY), to: nil)
                let px = pixel(img, p.x, p.y)
                if px.r < 120 && px.g < 120 && px.b < 120 { dark += 1 }
            }
            XCTAssertGreaterThan(dark, 3, "the title draws beside the indicator")
            w.close()
        }
    }
}
