// OutlineGroup, DisclosureGroup and List over a tree: one row per visible node, the
// disclosure triangle expanding and collapsing, indentation by level, selection.

import XCTest
@testable import AppKit
@testable import SwiftUI

private struct Item: Identifiable {
    let id: String
    var children: [Item]? = nil
}

private let tree = [
    Item(id: "Documents", children: [Item(id: "Reports", children: [Item(id: "Q1"), Item(id: "Q2")]), Item(id: "Notes")]),
    Item(id: "Pictures", children: [Item(id: "cat")]),
    Item(id: "README"),
]

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 300) -> (NSWindow, NSHostingView<V>) {
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
/// The disclosure triangles (custom buttons whose content is the triangle shape), top to bottom.
@MainActor
private func triangles(_ v: NSView) -> [_ContainerView] {
    allViews(v).compactMap { $0 as? _ContainerView }.filter { $0.accessibilityPress != nil && $0.subviews.count == 1 && $0.subviews[0] is _ShapeDrawingView }
        .sorted { $0.convert(NSPoint.zero, to: nil).y > $1.convert(NSPoint.zero, to: nil).y }
}

@MainActor
private func click(_ view: NSView, in w: NSWindow) {
    let p = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    for (type, n) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!
        NSApplication.shared.sendEvent(e)
    }
}

final class SwiftUIOutlineTests: XCTestCase, @unchecked Sendable {
    func testListOverATreeExpandsAndSelects() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var selected: String? = nil
                var body: some View {
                    VStack {
                        List(tree, children: \.children, selection: $selected) { Text($0.id) }.frame(height: 220)
                        Text("sel \(selected ?? "none")")
                    }
                }
            }
            let (w, h) = host(Probe())
            let list = allViews(h).compactMap { $0 as? _ListView }.first!
            XCTAssertEqual(list.rowFrames.count, 3, "collapsed: one row per root")
            XCTAssertEqual(texts(h).filter { $0 != "sel none" }, ["Documents", "Pictures", "README"])
            XCTAssertEqual(triangles(h).count, 2, "leaves have no triangle")
            XCTAssertEqual(triangles(h)[0].accessibilityLabel(), "expand")
            let documentsX = triangles(h)[0].convert(NSPoint.zero, to: nil).x
            XCTAssertEqual(triangles(h)[1].convert(NSPoint.zero, to: nil).x, documentsX, "roots line up")
            // Expand Documents: its children become rows, indented.
            click(triangles(h)[0], in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.rowFrames.count, 5)
            XCTAssertEqual(texts(h).filter { !$0.hasPrefix("sel ") }, ["Documents", "Reports", "Notes", "Pictures", "README"])
            XCTAssertEqual(triangles(h)[0].accessibilityLabel(), "collapse")
            XCTAssertEqual(triangles(h).count, 3, "Reports can expand too")
            XCTAssertEqual(triangles(h)[1].convert(NSPoint.zero, to: nil).x - documentsX, 18, accuracy: 1, "one level of indentation")
            XCTAssertEqual(triangles(h)[2].convert(NSPoint.zero, to: nil).x, documentsX, accuracy: 1, "Pictures stays at the root level")
            // Expand Reports (now the second triangle) for a third level.
            click(triangles(h)[1], in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(texts(h).filter { !$0.hasPrefix("sel ") }, ["Documents", "Reports", "Q1", "Q2", "Notes", "Pictures", "README"])
            let q1 = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Q1" }!
            let reports = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Reports" }!
            XCTAssertEqual(q1.convert(NSPoint.zero, to: nil).x - reports.convert(NSPoint.zero, to: nil).x, 18, accuracy: 1, "a leaf under Reports is one level deeper")
            // Rows select by their ids.
            let f = list.rowFrames[2]
            let p = list.convert(NSPoint(x: f.midX + 60, y: f.midY), to: nil)
            for (type, n) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
                let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: n, clickCount: 1, pressure: 1)!
                NSApplication.shared.sendEvent(e)
            }
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(h).contains("sel Q1"), texts(h).joined(separator: "|"))
            // Collapse Documents: the subtree goes, Reports stays expanded for next time.
            click(triangles(h)[0], in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.rowFrames.count, 3)
            click(triangles(h)[0], in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.rowFrames.count, 7)
            w.close()
        }
    }

    func testOutlineGroupAndDisclosureGroupOutsideAList() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var open = false
                var body: some View {
                    VStack(alignment: .leading) {
                        OutlineGroup(tree, children: \.children) { Text($0.id) }
                        DisclosureGroup("More", isExpanded: $open) { Text("inside") }
                        Text("open \(open ? "yes" : "no")")
                    }
                }
            }
            let (w, h) = host(Probe())
            XCTAssertEqual(texts(h), ["Documents", "Pictures", "README", "More", "open no"])
            XCTAssertEqual(triangles(h).count, 3)
            click(triangles(h)[2], in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(texts(h), ["Documents", "Pictures", "README", "More", "inside", "open yes"], "the binding drives the disclosure group")
            click(triangles(h)[1], in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(texts(h), ["Documents", "Pictures", "cat", "README", "More", "inside", "open yes"])
            w.close()
        }
    }
}
