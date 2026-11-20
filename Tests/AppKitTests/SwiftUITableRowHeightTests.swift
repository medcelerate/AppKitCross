// SwiftUI Table rows grow for cell text that wraps at its column's width (a real app's
// "TCP (length-prefixed)" in a narrow column overdrew the row above), keep the one-line
// height otherwise, and follow column width changes.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 240) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

/// The height of one line of body text, as a Text measures it unconstrained.
@MainActor
private func oneLineHeight() -> CGFloat { NSHostingView(rootView: Text("Xy")).sizeThatFits(.unspecified).height }

private struct Destination: Identifiable { let id: Int; let name: String; let transport: String }

final class SwiftUITableRowHeightTests: XCTestCase, @unchecked Sendable {
    func testOneLineTableKeepsDefaultRowHeight() {
        MainActor.assumeIsolated {
            let rows = [Destination(id: 1, name: "Studio", transport: "UDP"), Destination(id: 2, name: "Desk", transport: "TCP")]
            struct Probe: View {
                let rows: [Destination]
                @State var selection: Destination.ID?
                var body: some View {
                    Table(rows, selection: $selection) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Transport") { Text($0.transport) }
                    }
                }
            }
            let (w, h) = host(Probe(rows: rows))
            let table = allViews(h).compactMap { $0 as? NSTableView }.first!
            XCTAssertEqual(table.numberOfRows, 2)
            for row in 0..<2 {
                let height = table.rect(ofRow: row).height
                XCTAssertGreaterThanOrEqual(height, 20)
                XCTAssertLessThanOrEqual(height, 28, "a one-line row stays about 24pt tall (row \(row): \(height))")
            }
            w.close()
        }
    }

    func testWrappedCellGrowsItsRow() {
        MainActor.assumeIsolated {
            let rows = [Destination(id: 1, name: "New Destination", transport: "TCP (length-prefixed)"), Destination(id: 2, name: "Desk", transport: "UDP")]
            struct Probe: View {
                let rows: [Destination]
                @State var selection: Destination.ID?
                var body: some View {
                    Table(rows, selection: $selection) {
                        TableColumn("Name", value: \.name).width(60)
                        TableColumn("Transport") { Text($0.transport) }.width(90)
                    }
                }
            }
            let (w, h) = host(Probe(rows: rows))
            let table = allViews(h).compactMap { $0 as? NSTableView }.first!
            let line = oneLineHeight()
            XCTAssertGreaterThan(line, 0)

            // The wide text, measured at its column's width, is at least two lines.
            let column = table.tableColumns[1]
            XCTAssertEqual(column.width, 90)
            let wrapped = NSHostingView(rootView: Text("TCP (length-prefixed)"))
                .sizeThatFits(NSHostingSizeProposal(width: column.width - 4 - table.intercellSpacing.width, height: nil))
            XCTAssertGreaterThanOrEqual(wrapped.height, 2 * line - 1, "the text wraps inside the column")

            let tall = table.rect(ofRow: 0), short = table.rect(ofRow: 1)
            XCTAssertGreaterThanOrEqual(tall.height, 2 * line + 6 - 1, "the wrapped row grows to its text (\(tall.height), line \(line))")
            XCTAssertLessThanOrEqual(short.height, 28, "a one-line row keeps its height")
            XCTAssertGreaterThanOrEqual(short.minY, tall.maxY, "rows do not overlap")

            // The cell lays its text out at the column width, so it wraps where it was measured.
            let cell = table.view(atColumn: 1, row: 0, makeIfNecessary: true)!
            cell.layoutSubtreeIfNeeded()
            XCTAssertEqual(cell.frame.width, column.width)
            let text = allViews(cell).compactMap { $0 as? _TextView }.first!
            XCTAssertEqual(text.storage.string, "TCP (length-prefixed)")
            XCTAssertLessThanOrEqual(text.frame.width, column.width - 4 + 0.5, "the text gets the column's finite width")
            XCTAssertGreaterThanOrEqual(text.frame.height, 2 * line - 1, "the cell shows the text on two lines")
            XCTAssertLessThanOrEqual(text.frame.height, tall.height, "the wrapped text fits its row")
            w.close()
        }
    }

    func testRowsFollowColumnWidth() {
        MainActor.assumeIsolated {
            let rows = [Destination(id: 1, name: "a", transport: "TCP (length-prefixed)")]
            struct Probe: View {
                let rows: [Destination]
                @State var selection: Destination.ID?
                var body: some View {
                    Table(rows, selection: $selection) {
                        TableColumn("Name", value: \.name).width(40)
                        TableColumn("Transport") { Text($0.transport) }
                    }
                }
            }
            let (w, h) = host(Probe(rows: rows), width: 600)
            let table = allViews(h).compactMap { $0 as? NSTableView }.first!
            let line = oneLineHeight()
            XCTAssertLessThanOrEqual(table.rect(ofRow: 0).height, 28, "a wide column keeps the text on one line")

            // The window narrows: the transport column autoresizes and its text wraps.
            w.setContentSize(NSSize(width: 110, height: 240))
            h.frame = NSRect(x: 0, y: 0, width: 110, height: 240)
            h.layoutSubtreeIfNeeded()
            XCTAssertLessThan(table.tableColumns[1].width, 80)
            XCTAssertGreaterThanOrEqual(table.rect(ofRow: 0).height, 2 * line + 6 - 1, "the narrowed column's row grows")

            // And widens again: back to one line.
            w.setContentSize(NSSize(width: 600, height: 240))
            h.frame = NSRect(x: 0, y: 0, width: 600, height: 240)
            h.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(table.rect(ofRow: 0).height, 28)
            w.close()
        }
    }

    func testModelChangeRemeasuresRows() {
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var transport = "UDP"
                @State var selection: Int?
                var body: some View {
                    VStack {
                        Button("wrap") { transport = "TCP (length-prefixed)" }
                        Table([Destination(id: 1, name: "a", transport: transport)], selection: $selection) {
                            TableColumn("Name", value: \.name).width(40)
                            TableColumn("Transport") { Text($0.transport) }.width(70)
                        }
                    }
                }
            }
            let (w, h) = host(Probe())
            let table = allViews(h).compactMap { $0 as? NSTableView }.first!
            XCTAssertLessThanOrEqual(table.rect(ofRow: 0).height, 28)
            let button = allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "wrap" }!
            _ = button.sendAction(button.action, to: button.target)
            h.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(table.rect(ofRow: 0).height, 2 * oneLineHeight() + 6 - 1, "the new text is measured")
            w.close()
        }
    }

    func testUnproposedTableHeightSumsRows() {
        MainActor.assumeIsolated {
            let rows = (0..<3).map { Destination(id: $0, name: "n\($0)", transport: $0 == 0 ? "TCP (length-prefixed)" : "UDP") }
            struct Probe: View {
                let rows: [Destination]
                @State var selection: Destination.ID?
                var body: some View {
                    Table(rows, selection: $selection) {
                        TableColumn("Name", value: \.name).width(40)
                        TableColumn("Transport") { Text($0.transport) }.width(70)
                    }
                }
            }
            let (w, h) = host(Probe(rows: rows))
            let table = allViews(h).compactMap { $0 as? NSTableView }.first!
            let primitive = h.hostingRoot.flatMap { _ in findTablePrimitive(h) }
            XCTAssertNotNil(primitive)
            if let (p, node) = primitive {
                let rowsHeight = table.rect(ofRow: 2).maxY + table.intercellSpacing.height
                let size = p.sizeThatFits(ProposedViewSize(width: 300, height: nil), node: node)
                XCTAssertEqual(size.height, min(400, rowsHeight + (table.headerView?.frame.height ?? 23) + 4), accuracy: 0.5)
                XCTAssertGreaterThan(rowsHeight, 3 * 24 + 3 * table.intercellSpacing.height, "the wrapped row counts at its real height")
                XCTAssertEqual(p.sizeThatFits(ProposedViewSize(width: 300, height: 90), node: node).height, 90, "a proposed height is kept")
            }
            w.close()
        }
    }
}

@MainActor
private func findTablePrimitive<V: View>(_ h: NSHostingView<V>) -> (_NSTablePrimitive, _ViewNode)? {
    guard let root = (h.hostingRoot as? _ViewRoot)?.rootNode else { return nil }
    func walk(_ n: _ViewNode) -> (_NSTablePrimitive, _ViewNode)? {
        if let p = n.primitive as? _NSTablePrimitive { return (p, n) }
        for c in n.children { if let r = walk(c) { return r } }
        return nil
    }
    return walk(root)
}
