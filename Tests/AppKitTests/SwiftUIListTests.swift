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
            XCTAssertTrue(texts(h).contains("sel 1,2,3,4"), "shift-click extends from the anchor: \(texts(h).joined(separator: "|"))")
            click(list, row: 1, in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2"), "a plain click replaces")
            key(125, flags: [.shift], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2,3"), "shift-down extends")
            key(0, "a", flags: [.command], in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 1,2,3,4"), "command-A selects all")
            XCTAssertEqual(list.selectedRows, [0, 1, 2, 3])
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
            let shown = texts(h)
            XCTAssertTrue(shown.contains("Name \u{25B2}"), "the sorted column shows its direction: \(shown)")
            XCTAssertTrue(shown.contains("Age") && shown.contains("Note"))
            XCTAssertEqual(shown.filter { ["Ada", "Grace", "36", "45"].contains($0) }, ["Ada", "36", "Grace", "45"], "rows in sort order, cells per column")
            // The Age column is 60 wide; the others share the rest and the Name cells start at x 0.
            let ada = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Ada" }!
            let age = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "36" }!
            XCTAssertGreaterThan(age.convert(age.bounds.origin, to: nil).x, ada.convert(ada.bounds.origin, to: nil).x + 60)
            // Selecting a row writes the element id.
            let list = allViews(h).compactMap { $0 as? _ListView }.first!
            click(list, row: 1, in: w); h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2 order fwd"), texts(h).joined(separator: "|"))
            // Clicking the sorted header flips the order and the rows follow.
            let header = allViews(h).compactMap { $0 as? _ContainerView }.first { $0.mouseDownHandler != nil }!
            let p = header.convert(NSPoint(x: 10, y: header.bounds.midY), to: nil)
            NSApplication.shared.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel 2 order rev"), texts(h).joined(separator: "|"))
            XCTAssertTrue(texts(h).contains("Name \u{25BC}"))
            XCTAssertEqual(texts(h).filter { ["Ada", "Grace"].contains($0) }, ["Grace", "Ada"])
            w.close()
        }
    }
}
