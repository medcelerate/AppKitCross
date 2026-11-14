// List selection (single and set bindings, mouse and keyboard) and Table.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 260) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
@MainActor
private func texts(_ v: NSView) -> [String] { allViews(v).compactMap { ($0 as? _TextView)?.storage.string } }

/// Clicks row `row` of the list view with `flags`.
@MainActor
private func click(_ list: _ListView, row: Int, flags: NSEvent.ModifierFlags = [], in w: NSWindow) {
    let f = list.rowFrames[row]
    let p = list.convert(NSPoint(x: f.midX, y: f.midY), to: nil)
    for (type, n) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!
        NSApplication.shared.sendEvent(e)
    }
}

@MainActor
private func key(_ code: UInt16, _ chars: String = "", flags: NSEvent.ModifierFlags = [], in w: NSWindow) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    NSApplication.shared.sendEvent(e)
}

final class SwiftUIListTests: XCTestCase, @unchecked Sendable {
    /// Rows follow a resize in the same layout pass (they lagged one resize behind: the
    /// scroll primitive measured them against the scroll view's previous content size).
    func testRowsFollowAResizeAtOnce() {
        MainActor.assumeIsolated {
            struct Rows: View {
                var body: some View {
                    List { ForEach(0..<3, id: \.self) { i in HStack { Text("Row \(i)"); Spacer(); Text("end") } } }
                }
            }
            let (w, h) = host(Rows(), width: 320, height: 260)
            guard let list = allViews(h).compactMap({ $0 as? _ListView }).first else { return XCTFail("no list view") }
            XCTAssertEqual(list.rowFrames.first?.width ?? 0, list.bounds.width, accuracy: 1)
            let narrowEnd = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "end" }.map { $0.convert($0.bounds, to: h).minX } ?? 0
            w.setContentSize(NSSize(width: 520, height: 260))
            h.frame = NSRect(x: 0, y: 0, width: 520, height: 260)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.rowFrames.first?.width ?? 0, list.bounds.width, accuracy: 1, "rows span the new width in the same pass")
            XCTAssertGreaterThan(list.bounds.width, 480)
            let wideEnd = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "end" }.map { $0.convert($0.bounds, to: h).minX } ?? 0
            XCTAssertGreaterThan(wideEnd, narrowEnd + 150, "the trailing text moved with the new width")
            w.close()
        }
    }

    /// Text measured before its window turned dark draws with colours resolved for dark.
    func testTextColourFollowsTheDrawingAppearance() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, h) = host(Text("hello"), width: 120, height: 40)
            let platform = w._platformWindow as! HostWindow
            w.display()
            let light = _pixels(platform.lastImage!)
            w.appearance = NSAppearance(named: .darkAqua)
            w.display()
            let dark = _pixels(platform.lastImage!)
            // Count light pixels (text) in each render: dark mode draws light text on a dark fill.
            func lightPixels(_ d: Data) -> Int { stride(from: 0, to: d.count, by: 4).filter { d[$0] > 200 && d[$0 + 1] > 200 && d[$0 + 2] > 200 }.count }
            func darkPixels(_ d: Data) -> Int { stride(from: 0, to: d.count, by: 4).filter { d[$0] < 60 && d[$0 + 1] < 60 && d[$0 + 2] < 60 }.count }
            XCTAssertGreaterThan(darkPixels(light), 20, "light appearance: dark glyphs")
            XCTAssertGreaterThan(lightPixels(dark), 20, "dark appearance: light glyphs, re-resolved although the text was laid out under light")
            w.close()
        }
    }

    func testSingleSelectionByMouseKeyboardAndBinding() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var selected: String? = nil
                let items = ["Alpha", "Beta", "Gamma"]
                var body: some View {
                    VStack {
                        List(items, id: \.self, selection: $selected) { Text($0) }.frame(height: 150)
                        Text("sel \(selected ?? "none")")
                        Button("Pick Gamma") { selected = "Gamma" }
                    }
                }
            }
            let (w, h) = host(Probe())
            let list = allViews(h).compactMap { $0 as? _ListView }.first!
            XCTAssertEqual(list.rowFrames.count, 3)
            XCTAssertTrue(list.selectedRows.isEmpty)
            XCTAssertTrue(texts(h).contains("sel none"))
            // Click selects and highlights; the row's text takes the selection colour.
            click(list, row: 1, in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel Beta"), texts(h).joined(separator: "|"))
            XCTAssertEqual(list.selectedRows, [1])
            let beta = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Beta" }!
            XCTAssertTrue(beta.isInSelectedRow)
            XCTAssertTrue(w.firstResponder === list, "clicking the list focuses it")
            // Arrow keys move the selection; a single-selection list ignores shift.
            key(125, in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel Gamma"))
            XCTAssertFalse(beta.isInSelectedRow)
            key(125, in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel Gamma"), "stays on the last row")
            key(126, flags: [.shift], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel Beta"))
            XCTAssertEqual(list.selectedRows, [1])
            // The binding drives the highlight too.
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Pick Gamma" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.selectedRows, [2])
            w.close()
        }
    }

    func testSetSelectionWithModifiers() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var selected: Set<Int> = []
                var body: some View {
                    VStack {
                        List(selection: $selected) {
                            Text("one").tag(1)
                            Text("two").tag(2)
                            Text("three").tag(3)
                            Text("four").tag(4)
                        }.frame(height: 180)
                        Text("sel \(selected.sorted().map(String.init).joined(separator: ","))")
                    }
                }
            }
            let (w, h) = host(Probe())
            let list = allViews(h).compactMap { $0 as? _ListView }.first!
            XCTAssertEqual(list.rowFrames.count, 4)
            click(list, row: 0, in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1"))
            click(list, row: 2, flags: [.command], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1,3"), "command-click adds")
            click(list, row: 0, flags: [.command], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 3"), "command-click removes")
            click(list, row: 3, flags: [.shift], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1,2,3,4"), "shift-click adds the range from the anchor (the last clicked row): \(texts(h).joined(separator: "|"))")
            click(list, row: 0, flags: [.command], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2,3,4"))
            click(list, row: 1, flags: [.shift], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1,2,3,4"), "shift-click keeps the existing selection and adds the range: \(texts(h).joined(separator: "|"))")
            click(list, row: 1, in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2"), "a plain click replaces")
            key(125, flags: [.shift], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2,3"), "shift-down extends")
            key(0, "a", flags: [.command], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1,2,3,4"), "command-A selects all")
            XCTAssertEqual(list.selectedRows, [0, 1, 2, 3])
            // With an Edit menu owning Cmd-A, the menu's selectAll: reaches the focused list.
            click(list, row: 1, in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2"))
            let menu = NSMenu(title: "Main")
            let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            edit.submenu = NSMenu(title: "Edit")
            edit.submenu!.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
            menu.addItem(edit)
            let previousMenu = NSApplication.shared.mainMenu
            NSApplication.shared.mainMenu = menu
            defer { NSApplication.shared.mainMenu = previousMenu }
            key(0, "a", flags: [.command], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1,2,3,4"), "Select All from the menu: \(texts(h).joined(separator: "|"))")
            w.close()
        }
    }

    struct Person: Identifiable {
        let id: Int
        let name: String
        let age: Int
    }

    func testTableColumnsSelectionAndSortOrder() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var selected: Int? = nil
                @State var order = [KeyPathComparator(\Person.name)]
                let people = [Person(id: 1, name: "Ada", age: 36), Person(id: 2, name: "Grace", age: 45)]
                var body: some View {
                    VStack {
                        Table(people.sorted(using: order), selection: $selected, sortOrder: $order) {
                            TableColumn("Name", value: \.name)
                            TableColumn("Age", value: \.age) { Text("\($0.age)") }.width(60)
                            TableColumn("Note") { _ in Text("-") }
                        }.frame(height: 160)
                        Text("sel \(selected.map(String.init) ?? "none") order \(order.first?.order == .forward ? "fwd" : "rev")")
                    }
                }
            }
            let (w, h) = host(Probe(), width: 360)
            let table = allViews(h).compactMap { $0 as? NSTableView }.first!
            XCTAssertEqual(table.tableColumns.map(\.title), ["Name", "Age", "Note"])
            XCTAssertTrue(table.highlightedTableColumn === table.tableColumns[0], "the sorted column is highlighted")
            XCTAssertEqual(table.sortDescriptors.first?.ascending, true)
            w.display()
            let shown = texts(h)
            XCTAssertEqual(shown.filter { ["Ada", "Grace", "36", "45"].contains($0) }, ["Ada", "36", "Grace", "45"], "rows in sort order, cells per column: \(shown)")
            // The Age column is 60 wide; the Name cells start at the table's leading edge.
            XCTAssertEqual(table.tableColumns[1].width, 60)
            let ada = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Ada" }!
            let age = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "36" }!
            XCTAssertGreaterThan(age.convert(age.bounds.origin, to: nil).x, ada.convert(ada.bounds.origin, to: nil).x + 60)
            // Selecting a row writes the element id, also when the click lands on a cell's view;
            // the table takes keyboard focus so the arrows move the selection.
            let grace = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Grace" }!
            let onCell = grace.convert(NSPoint(x: 2, y: 2), to: nil)
            for (type, n) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
                NSApplication.shared.sendEvent(NSEvent.mouseEvent(with: type, location: onCell, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!)
            }
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2 order fwd"), texts(h).joined(separator: "|"))
            XCTAssertTrue(w.firstResponder === table, "the table has keyboard focus after a click on a cell")
            key(126, "\u{F700}", in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1 order fwd"), "up arrow moves to Ada: \(texts(h).joined(separator: "|"))")
            key(125, "\u{F701}", in: w); h.layoutSubtreeIfNeeded()
            // Clicking the sorted header flips the order and the rows follow.
            table._headerClicked(column: 0)
            h.layoutSubtreeIfNeeded()
            w.display()
            XCTAssertTrue(texts(h).contains("sel 2 order rev"), texts(h).joined(separator: "|"))
            XCTAssertEqual(table.sortDescriptors.first?.ascending, false)
            XCTAssertEqual(texts(h).filter { ["Ada", "Grace"].contains($0) }, ["Grace", "Ada"])
            w.close()
        }
    }
}

