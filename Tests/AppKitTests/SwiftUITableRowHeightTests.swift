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
                XCTAssertLessThanOrEqual(height, 32, "a one-line row stays about 24pt tall; 32 allows Windows\u{2019} taller fonts (row \(row): \(height))")
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
            XCTAssertLessThanOrEqual(short.height, 32, "a one-line row keeps its height")
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
            XCTAssertLessThanOrEqual(table.rect(ofRow: 0).height, 32, "a wide column keeps the text on one line")

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
            XCTAssertLessThanOrEqual(table.rect(ofRow: 0).height, 32)
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
            XCTAssertLessThanOrEqual(table.rect(ofRow: 0).height, 32)
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

    /// The Settings pane's sequence on Windows: the window's first layout runs with the
    /// columns at their default widths, then the pane gets its final width and uniform
    /// autoresizing refits the columns without anyone resizing a column by hand. Every
    /// row must then be as tall as its cells measured at the final widths.
    func testRowsFollowAutoresizedColumnsAfterFirstLayout() {
        MainActor.assumeIsolated {
            let initial = [
                Destination(id: 1, name: "New Destination", transport: "TCP (length-prefixed)"),
                Destination(id: 2, name: "Desk", transport: "UDP"),
                Destination(id: 3, name: "Studio", transport: "OSC"),
            ]
            final class Model: ObservableObject { @Published var rows: [Destination] = [] }
            struct Probe: View {
                @ObservedObject var model: Model
                @State var selection: Destination.ID?
                var body: some View {
                    VStack {
                        Table(model.rows, selection: $selection) {
                            TableColumn("Name", value: \.name)
                            TableColumn("Host") { _ in Text("127.0.0.1") }
                            TableColumn("Port") { d in Text("\(9000 + d.id)") }
                            TableColumn("Transport") { Text($0.transport) }
                        }
                    }
                }
            }
            let model = Model()
            model.rows = initial
            // The window and the hosting view's first layout, at a width the columns'
            // default 100pt fill (the pane is not yet at its final width).
            let (w, h) = host(Probe(model: model), width: 420, height: 300)
            let table = allViews(h).compactMap { $0 as? NSTableView }.first!
            XCTAssertEqual(table.numberOfRows, 3)

            @MainActor func expectedHeight(_ row: Int, _ texts: [String]) -> CGFloat {
                var tallest: CGFloat = 0
                for (c, text) in texts.enumerated() {
                    // The cell's text is offered its column's width less the cell's leading inset.
                    let width = table.tableColumns[c].width - 4
                    tallest = max(tallest, NSHostingView(rootView: Text(text)).sizeThatFits(NSHostingSizeProposal(width: width, height: nil)).height)
                }
                return max(20, tallest.rounded(.up) + 6)
            }
            func texts(_ d: Destination) -> [String] { [d.name, "127.0.0.1", "\(9000 + d.id)", d.transport] }
            @MainActor func check(_ label: String, rows: [Destination], file: StaticString = #filePath, line: UInt = #line) {
                XCTAssertEqual(table.numberOfRows, rows.count, label, file: file, line: line)
                let clip = table.enclosingScrollView!.contentView.bounds.width
                let columns = table.tableColumns.reduce(0) { $0 + $1.width } + CGFloat(table.tableColumns.count - 1) * table.intercellSpacing.width
                XCTAssertEqual(columns, clip, accuracy: 1, "\(label): the columns fill the clip view", file: file, line: line)
                var bottom: CGFloat = 0
                for (row, d) in rows.enumerated() {
                    let r = table.rect(ofRow: row)
                    XCTAssertEqual(r.height, expectedHeight(row, texts(d)), accuracy: 0.5, "\(label): row \(row) is measured at the final column widths", file: file, line: line)
                    bottom = r.maxY
                    if let rv = table.rowView(atRow: row, makeIfNecessary: false) {
                        XCTAssertEqual(rv.frame, r, "\(label): row \(row)'s view follows its rect", file: file, line: line)
                    }
                    for c in 0..<table.tableColumns.count {
                        guard let cell = table.view(atColumn: c, row: row, makeIfNecessary: true) else { continue }
                        cell.layoutSubtreeIfNeeded()
                        XCTAssertEqual(cell.frame.width, table.tableColumns[c].width, accuracy: 0.5, "\(label): cell \(row),\(c) is laid out at its column's width", file: file, line: line)
                        XCTAssertLessThanOrEqual(cell.frame.height, r.height + 0.5, "\(label): cell \(row),\(c) fits its row", file: file, line: line)
                        for t in allViews(cell).compactMap({ $0 as? _TextView }) {
                            XCTAssertLessThanOrEqual(t.frame.height, r.height, "\(label): cell \(row),\(c)'s text (\(t.storage.string)) fits its row", file: file, line: line)
                            XCTAssertGreaterThanOrEqual(t.frame.minY, 0, "\(label): cell \(row),\(c)'s text is not clipped at the top", file: file, line: line)
                            let measured = NSHostingView(rootView: Text(t.storage.string)).sizeThatFits(NSHostingSizeProposal(width: table.tableColumns[c].width - 4, height: nil))
                            XCTAssertEqual(t.frame.height, measured.height, accuracy: 0.5, "\(label): cell \(row),\(c)'s text wraps where the row was measured", file: file, line: line)
                        }
                    }
                }
                XCTAssertGreaterThanOrEqual(table.frame.height, bottom, "\(label): the document is as tall as the rows", file: file, line: line)
            }
            check("first layout", rows: initial)

            // The pane reaches its final width: the columns widen.
            for width: CGFloat in [760, 300, 760] {
                let before = table.tableColumns.map(\.width)
                w.setContentSize(NSSize(width: width, height: 300))
                h.frame = NSRect(x: 0, y: 0, width: width, height: 300)
                h.layoutSubtreeIfNeeded()
                XCTAssertNotEqual(table.tableColumns.map(\.width), before, "the columns autoresize")
                check("at \(width)", rows: initial)
            }

            // Narrow enough that the wrapping cells wrap: their row is two lines tall.
            w.setContentSize(NSSize(width: 300, height: 300))
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
            h.layoutSubtreeIfNeeded()
            let line = oneLineHeight()
            XCTAssertGreaterThanOrEqual(table.rect(ofRow: 0).height, 2 * line + 6 - 1, "the wrapped row is two lines tall")
            XCTAssertLessThanOrEqual(table.rect(ofRow: 1).height, 32, "a one-line row stays one line")

            // A model change reloads the rows: they are measured again at the same widths.
            var changed = initial
            changed[1] = Destination(id: 2, name: "Desk", transport: "TCP (length-prefixed)")
            changed.append(Destination(id: 4, name: "Rack", transport: "UDP"))
            model.rows = changed
            h.layoutSubtreeIfNeeded()
            check("after a model change", rows: changed)
            table.reloadData()
            h.layoutSubtreeIfNeeded()
            check("after reloadData", rows: changed)
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
