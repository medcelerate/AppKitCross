// Fidelity of a macOS app's main window (the Sibyl port): a sidebar List with sections and
// Labels, a grouped Form in a tall column, and a header row of icons and a title inside a
// horizontally scrolling matrix of fixed-width columns.

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
@MainActor
private func text(_ s: String, in v: NSView) -> _TextView? { allViews(v).compactMap { $0 as? _TextView }.first { $0.storage.string == s } }
@MainActor
private func frame(_ v: NSView, in root: NSView) -> CGRect { v.convert(v.bounds, to: root) }
/// The symbol image view on the same line as `t`.
@MainActor
private func icon(beside t: _TextView, in root: NSView) -> _SymbolImageView? {
    let line = frame(t, in: root)
    return allViews(root).compactMap { $0 as? _SymbolImageView }.first { frame($0, in: root).midY > line.minY - 4 && frame($0, in: root).midY < line.maxY + 4 }
}
private func sameColor(_ a: NSColor?, _ b: NSColor) -> Bool {
    guard let a else { return false }
    if a.isEqual(b) { return true }
    guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
    return abs(a.redComponent - b.redComponent) < 0.02 && abs(a.greenComponent - b.greenComponent) < 0.02
        && abs(a.blueComponent - b.blueComponent) < 0.02 && abs(a.alphaComponent - b.alphaComponent) < 0.02
}

private enum Item: Hashable { case combined, matrix, channel(Int) }

private struct Sidebar: View {
    @State var selection: Item? = .combined
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Views") {
                    Label("Combined Log", systemImage: "list.bullet.rectangle").tag(Item.combined)
                    Label("Matrix", systemImage: "square.grid.3x3").tag(Item.matrix)
                }
                Section("Channels") {
                    Label {
                        Text("Lighting")
                    } icon: {
                        Image(systemName: "bolt").foregroundStyle(Color.orange)
                    }
                    .tag(Item.channel(1))
                }
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 250, max: 420)
        } detail: {
            Text("detail")
        }
    }
}

/// A matrix column's top bar as Sibyl draws it: grip, symbol, title, a spacer, a meter
/// and two borderless buttons.
private struct ColumnHeader: View {
    let name: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").font(.caption2).foregroundStyle(.tertiary)
            Image(systemName: "waveform").foregroundStyle(Color.blue)
            Text(name).fontWeight(.semibold).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            GeometryReader { g in Capsule().fill(.quaternary).frame(width: g.size.width) }.frame(width: 40)
            Button { } label: { Image(systemName: "ellipsis.circle") }.buttonStyle(.borderless)
            Button { } label: { Image(systemName: "chevron.compact.left") }.buttonStyle(.borderless)
        }
        .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 6)
    }
}

final class SwiftUISidebarFidelityTests: XCTestCase, @unchecked Sendable {
    func testSidebarRowsAreLeadingAlignedWithTheIconBeforeTheTitle() {
        MainActor.assumeIsolated {
            let (w, h) = host(Sidebar(), width: 900, height: 500)
            for name in ["Combined Log", "Matrix", "Lighting"] {
                guard let t = text(name, in: h), let i = icon(beside: t, in: h) else { return XCTFail("no row or icon for \(name)") }
                let tf = frame(t, in: h), f = frame(i, in: h)
                XCTAssertLessThanOrEqual(f.maxX, tf.minX, "\(name): the icon leads the title")
                XCTAssertEqual(f.minX, 18, accuracy: 3, "\(name): the icon sits at the sidebar's content inset, not centred")
                XCTAssertLessThan(tf.minX, 50, "\(name): the title follows the icon")
                XCTAssertEqual(tf.width, t.size(for: nil).width, accuracy: 1, "\(name): the full title shows in a 250-point column")
            }
            // Labels' icons are accent-coloured; an icon with its own foreground style keeps it.
            XCTAssertTrue(sameColor(icon(beside: text("Matrix", in: h)!, in: h)?._drawnTemplateColor, NSColor.controlAccentColor))
            XCTAssertTrue(sameColor(icon(beside: text("Lighting", in: h)!, in: h)?._drawnTemplateColor, Color.orange.nsColor))
            w.close()
        }
    }

    func testSidebarSectionHeadersAreSmallSecondaryText() {
        MainActor.assumeIsolated {
            let (w, h) = host(Sidebar(), width: 900, height: 500)
            for name in ["Views", "Channels"] {
                guard let t = text(name, in: h) else { return XCTFail("no header \(name)") }
                let font = t.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                XCTAssertLessThanOrEqual(font?.pointSize ?? 99, 11.5, "\(name): a small font")
                XCTAssertNotEqual(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) }, true, "\(name): not bold")
                XCTAssertTrue(sameColor(t.storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.secondaryLabelColor), "\(name): the secondary colour")
                XCTAssertEqual(frame(t, in: h).minX, 14, accuracy: 2, "\(name): leading, not centred")
            }
            // The second section's header is set off from the rows above it.
            let matrix = frame(text("Matrix", in: h)!, in: h), channels = frame(text("Channels", in: h)!, in: h)
            XCTAssertGreaterThan(channels.minY - matrix.maxY, 14)
            w.close()
        }
    }

    func testSidebarSelectionIsRoundedAndTextStaysLegibleWhenTheWindowIsInactive() {
        MainActor.assumeIsolated {
            let (w, h) = host(Sidebar(), width: 900, height: 500)
            guard let list = allViews(h).compactMap({ $0 as? _ListView }).first, let t = text("Combined Log", in: h) else { return XCTFail("no list") }
            XCTAssertTrue(list.sidebar)
            XCTAssertEqual(list.selectedRows.count, 1)
            let row = list.rowFrames[list.selectedRows.first!]
            XCTAssertEqual(row.height, 28, accuracy: 1, "a sidebar row is 28 points tall")
            XCTAssertEqual(_ListView.sidebarSelectionRect(row).minX, 10)
            XCTAssertTrue(w.isKeyWindow)
            XCTAssertTrue(list.emphasized)
            XCTAssertTrue(t.isInSelectedRow, "white text on the accent selection of a key window")
            XCTAssertTrue(sameColor(icon(beside: t, in: h)?._drawnTemplateColor, .alternateSelectedControlTextColor))
            w.resignKey()
            XCTAssertFalse(list.emphasized, "an inactive window's selection is the unemphasized grey")
            XCTAssertFalse(t.isInSelectedRow, "and its text keeps the label colour")
            XCTAssertTrue(sameColor(icon(beside: t, in: h)?._drawnTemplateColor, .controlAccentColor))
            w.close()
        }
    }

    func testPlainListRowsAreLeadingAligned() {
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    List {
                        Section("Header") { Label("Row", systemImage: "star") }
                    }
                }
            }
            let (w, h) = host(Probe(), width: 300, height: 200)
            XCTAssertLessThan(frame(text("Header", in: h)!, in: h).minX, 20)
            XCTAssertLessThan(frame(text("Row", in: h)!, in: h).minX, 40)
            w.close()
        }
    }

    func testGroupedFormInATallContainerStartsAtTheTop() {
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    Text("content")
                        .inspector(isPresented: .constant(true)) {
                            Form {
                                Section("Show") { LabeledContent("Name", value: "New Show") }
                            }
                            .formStyle(.grouped)
                        }
                }
            }
            let (w, h) = host(Probe(), width: 700, height: 600)
            guard let header = text("Show", in: h), let name = text("Name", in: h) else { return XCTFail("no form rows") }
            XCTAssertLessThan(frame(header, in: h).minY, 50, "the form starts at the top, not centred in 600 points")
            XCTAssertLessThan(frame(name, in: h).minY, 90)
            w.close()
        }
    }

    func testFixedWidthChildrenKeepTheirWidthsInAHorizontalScrollView() {
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    GeometryReader { geometry in
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(["Production", "Lighting", "Channel 3"], id: \.self) { name in
                                    VStack(spacing: 0) {
                                        ColumnHeader(name: name)
                                        Color.clear.frame(maxHeight: .infinity)
                                    }
                                    .frame(width: name == "Channel 3" ? 34 : 320, height: geometry.size.height)
                                    Rectangle().fill(Color.clear).frame(width: 9).frame(height: geometry.size.height)
                                }
                            }
                        }
                    }
                }
            }
            let (w, h) = host(Probe(), width: 500, height: 300)
            guard let scroll = allViews(h).compactMap({ $0 as? NSScrollView }).first, let document = scroll.documentView else { return XCTFail("no scroll view") }
            XCTAssertEqual(document.frame.width, 320 + 9 + 320 + 9 + 34 + 9, accuracy: 1, "the document is as wide as its columns, wider than the viewport")
            let production = frame(text("Production", in: h)!, in: document), lighting = frame(text("Lighting", in: h)!, in: document)
            XCTAssertEqual(lighting.minX - production.minX, 329, accuracy: 1, "each column keeps its width")
            w.close()
        }
    }

    func testHeaderTitleIsNotTruncatedBesideFixedSizeSiblings() {
        MainActor.assumeIsolated {
            let (w, h) = host(ColumnHeader(name: "Production").frame(width: 320), width: 320, height: 60)
            guard let t = text("Production", in: h) else { return XCTFail("no title") }
            XCTAssertEqual(frame(t, in: h).width, t.size(for: nil).width, accuracy: 1, "the title has its full width")
            w.close()
        }
    }

    func testOneLineTextShrinksToNothingAtAZeroProposal() {
        MainActor.assumeIsolated {
            // A stack measures a child's minimum with a zero proposal: a one-line text can
            // truncate away, a wrapping one narrows to its widest word.
            let (w, h) = host(HStack(spacing: 0) {
                Text("one line only").lineLimit(1).frame(width: 0)
                Text("wrapping words").frame(width: 0).fixedSize(horizontal: false, vertical: true)
            }, width: 300, height: 60)
            XCTAssertEqual(frame(text("one line only", in: h)!, in: h).width, 0, accuracy: 1)
            let wrapped = text("wrapping words", in: h)!
            XCTAssertLessThan(frame(wrapped, in: h).width, wrapped.size(for: nil).width)
            w.close()
        }
    }
}
