// The SwiftUI members added for swift-markdown-ui in the third-party library
// compatibility example (docs/compatibility/swiftui-libraries.md): the Layout protocol,
// Grid, custom alignment guides and baselines, label styles, attributed strings, font
// and text styles, scaled metrics and preference-driven decorations.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 200, height: CGFloat = 100) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor private func root(_ h: NSView) -> _ViewRoot? { (h as? any _HostingViewLookup)?._root }
@MainActor protocol _HostingViewLookup { var _root: _ViewRoot? { get } }
extension NSHostingView: _HostingViewLookup { var _root: _ViewRoot? { hostingRoot as? _ViewRoot } }

/// Lays its subviews out in a row, wrapping at the proposed width (swift-markdown-ui's
/// FlowLayout in miniature).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        rows(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        for (i, frame) in rows(proposal: proposal, subviews: subviews).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (frames, CGSize(width: width, height: y + rowHeight))
    }
}

private enum CenterOfFirstLine: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        let afterFirstLine = context[.lastTextBaseline] - context[.firstTextBaseline]
        return (context.height - afterFirstLine) / 2
    }
}
extension VerticalAlignment { fileprivate static let centerOfFirstLine = VerticalAlignment(CenterOfFirstLine.self) }

private struct BoxStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { VStack { configuration.title; configuration.icon } }
}

final class SwiftUILayoutProtocolTests: XCTestCase, @unchecked Sendable {
    func testLayoutProtocolMeasuresAndPlacesSubviews() {
        MainActor.assumeIsolated {
            let view = FlowLayout { ForEach(0..<5, id: \.self) { _ in Color.red.frame(width: 30, height: 10) } }
            let (w, h) = host(view, width: 100, height: 100)
            let layoutNode = root(h)?.firstNode { $0.primitive is _LayoutPrimitive<FlowLayout> }
            XCTAssertEqual(layoutNode?.sizeThatFits(ProposedViewSize(width: 100, height: nil)), CGSize(width: 98, height: 24), "three per row at 30 + 4, two rows")
            let frames = (layoutNode?.children.first?.layoutLeaves ?? []).map(\.frame)
            XCTAssertEqual(frames.count, 5)
            XCTAssertEqual(frames[3].minY, frames[0].minY + 14, "the fourth wraps")
            XCTAssertEqual(frames[1].minX, frames[0].minX + 34)
            w.close()
        }
    }

    func testLayoutLeavesUnplacedSubviewsCentred() {
        MainActor.assumeIsolated {
            struct Lazy: Layout {
                func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize { CGSize(width: 50, height: 50) }
                func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {}
            }
            let (w, h) = host(Lazy { Color.blue.frame(width: 10, height: 10) }, width: 50, height: 50)
            let leaf = root(h)?.firstNode { $0.primitive is _FramePrimitive }
            XCTAssertEqual(leaf?.frame, CGRect(x: 20, y: 20, width: 10, height: 10))
            w.close()
        }
    }

    func testGridSizesColumnsByTheirWidestCell() {
        MainActor.assumeIsolated {
            let view = Grid(horizontalSpacing: 2, verticalSpacing: 3) {
                GridRow { Color.red.frame(width: 20, height: 10); Color.red.frame(width: 50, height: 10) }
                GridRow { Color.red.frame(width: 40, height: 20); Color.red.frame(width: 10, height: 10).gridColumnAlignment(.trailing) }
                Divider()
            }
            let (w, h) = host(view, width: 300, height: 100)
            let grid = root(h)?.firstNode { $0.primitive is _GridTablePrimitive }
            XCTAssertEqual(grid?.sizeThatFits(.unspecified), CGSize(width: 92, height: 37), "columns 40 and 50 with a 2-point gap; rows 10, 20 and the 1-point divider with 3 between")
            let rows = grid?.children.first?.layoutLeaves ?? []
            XCTAssertEqual(rows.count, 3)
            let cells = rows.flatMap { ($0.primitive as? _GridRowPrimitive)?.cells.map(\.frame) ?? [$0.frame] }
            XCTAssertEqual(cells[0].midX, cells[2].midX, "a column lines up (centred by default)")
            XCTAssertEqual(cells[1].minX, 42, "the second column starts after 40 + 2")
            XCTAssertEqual(cells[3].maxX, cells[1].maxX, "trailing column alignment")
            XCTAssertEqual(cells[4].width, 92, "a non-row child spans the grid")
            w.close()
        }
    }

    func testCustomAlignmentGuidesAndBaselines() {
        MainActor.assumeIsolated {
            let (w, h) = host(Text("Hello\nWorld").font(.system(size: 20)))
            let text = root(h)?.firstNode { $0.primitive is _TextPrimitive }
            let dims = text!.dimensions(for: text!.sizeThatFits(.unspecified))
            XCTAssertGreaterThan(dims[.firstTextBaseline], 10, "the first baseline sits below the top")
            XCTAssertLessThan(dims[.firstTextBaseline], dims.height / 2, "and in the first line")
            XCTAssertGreaterThan(dims[.lastTextBaseline], dims.height / 2, "the last baseline is in the second line")
            XCTAssertEqual(dims[VerticalAlignment.center], dims.height / 2)
            XCTAssertEqual(dims[.trailing], dims.width)
            w.close()
            // A bullet aligned with the centre of a two-line text's first line sits above the text's centre.
            let view = HStack(alignment: .centerOfFirstLine, spacing: 4) { Color.red.frame(width: 6, height: 6); Text("Hello\nWorld").font(.system(size: 20)) }
            let (w2, h2) = host(view, width: 200, height: 100)
            let bullet = root(h2)?.firstNode { $0.primitive is _FramePrimitive }
            let t = root(h2)?.firstNode { $0.primitive is _TextPrimitive }
            XCTAssertLessThan(bullet!.frame.midY, t!.frame.midY - 5, "bullet \(bullet!.frame) against text \(t!.frame)")
            XCTAssertGreaterThan(bullet!.frame.midY, t!.frame.minY)
            w2.close()
        }
    }

    func testLabelStylesFromTheEnvironment() {
        MainActor.assumeIsolated {
            let view = VStack {
                Label("Title", systemImage: "star").labelStyle(.titleOnly)
                Label("Boxed", systemImage: "star").labelStyle(BoxStyle())
            }
            let (w, h) = host(view)
            var labels: [_ViewNode] = []
            var queue: [_ViewNode] = root(h)?.rootNode.map { [$0] } ?? []
            while let x = queue.popLast() {
                if "\(x.viewType)".hasPrefix("Label<") { labels.append(x) }
                queue.append(contentsOf: x.children.reversed())
            }
            XCTAssertEqual(labels.count, 2)
            XCTAssertEqual(labels[0].layoutLeaves.count, 1, "title only")
            XCTAssertTrue(labels[1].children.first.map { "\($0.viewType)" }?.hasPrefix("AnyView") == true)
            XCTAssertTrue(labels[1].firstDescendant { $0.primitive is _StackPrimitive }.map { ($0.primitive as! _StackPrimitive).kindIsVertical } ?? false, "the custom style's VStack")
            w.close()
        }
    }

    func testAttributedStringRunsBecomeTextRuns() throws {
        #if os(Windows)
        throw XCTSkip("the Windows 6.2 toolchain cannot link AttributedString run ranges; Text keeps the plain string there")
        #endif
        var s = AttributedString("plain ")
        var bold = AttributedString("bold")
        bold.font = Font.title
        bold.foregroundColor = .red
        bold.underlineStyle = .single
        bold.kern = 2
        var code = AttributedString(" code")
        code.font = Font.body.monospaced()
        #if canImport(Darwin)
        code.font = nil
        code.inlinePresentationIntent = .code     // corelibs has no inline presentation intents
        #endif
        s += bold + code
        let runs = Text._runs(of: s)
        XCTAssertEqual(runs.map(\.string), ["plain ", "bold", " code"])
        XCTAssertEqual(runs[1].font, .title)
        XCTAssertEqual(runs[1].color, .red)
        XCTAssertEqual(runs[1].underline, .single)
        XCTAssertEqual(runs[1].kerning, 2)
        XCTAssertEqual(runs[2].font, Font.body.monospaced(), "the code intent gives a monospaced font")
        XCTAssertEqual(Text(s)._string, "plain bold code")
    }

    func testFontAndTextStyleMembers() {
        let f = Font.body.width(.condensed).smallCaps().leading(.tight)
        XCTAssertEqual(f.width, .condensed)
        XCTAssertNotEqual(f, Font.body)
        XCTAssertEqual(Font.Width.standard.value, 0)
        let t = Text("1234").monospacedDigit().strikethrough(true, pattern: .dash, color: .blue).tracking(1)
        XCTAssertEqual(t.runs[0].strikethrough, Text.LineStyle(pattern: .dash, color: .blue))
        XCTAssertTrue(t.runs[0].monospacedDigits)
        XCTAssertEqual(Text.LineStyle.single.pattern, .solid)
        XCTAssertEqual(Text(Image(systemName: "star"))._string, "", "an inline image adds no characters")
        XCTAssertEqual(Image("missing", bundle: nil, label: Text("A label")).accessibilityLabel, "A label")
        XCTAssertEqual(AnyShapeStyle(Color.red).style as? Color, .red)
    }

    func testScaledMetricAndEnvironmentTransforms() {
        MainActor.assumeIsolated {
            struct Sized: View {
                @ScaledMetric(relativeTo: .body) var size: CGFloat = 17
                var body: some View { Color.red.frame(width: size, height: size) }
            }
            let (w, h) = host(Sized().transformEnvironment(\.lineSpacing) { $0 += 3 }.imageScale(.large), width: 100, height: 100)
            let frame = root(h)?.firstNode { $0.primitive is _FramePrimitive }
            XCTAssertEqual(frame?.frame.width, 17)
            XCTAssertEqual(frame?.environment.lineSpacing, 3)
            XCTAssertEqual(frame?.environment.imageScale, .large)
            w.close()
        }
    }

    func testFontManagerConvertsTraits() {
        MainActor.assumeIsolated {
            let base = NSFont.systemFont(ofSize: 13)
            let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
            XCTAssertFalse(NSFontManager.shared.traits(of: base).contains(.italicFontMask))
            XCTAssertEqual(NSFontManager.shared.convert(italic, toNotHaveTrait: .italicFontMask), base)
            let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
            XCTAssertEqual(NSFontManager.shared.weight(of: bold), 9)
            XCTAssertEqual(NSFontManager.shared.weight(of: base), 5)
            XCTAssertEqual(NSFontManager.shared.convert(base, toSize: 20).pointSize, 20)
            XCTAssertTrue(Font.body.italic().nsFont.italicAngle != 0, "Font.italic() goes through the manager")
        }
    }

    struct WidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    func testBackgroundPreferenceValueBuildsFromTheSubtreesValue() {
        MainActor.assumeIsolated {
            let view = HStack {
                Text("a").preference(key: WidthKey.self, value: 30)
                Text("b").preference(key: WidthKey.self, value: 70)
            }
            .backgroundPreferenceValue(WidthKey.self) { width in Color.red.frame(width: width, height: 5) }
            let (w, h) = host(view)
            let bg = root(h)?.firstNode { $0.primitive is _FramePrimitive }
            XCTAssertEqual(bg?.frame.width, 70, "the background is built from the reduced value")
            w.close()
        }
    }
}

extension _ViewNode {
    @MainActor func firstDescendant(where predicate: (_ViewNode) -> Bool) -> _ViewNode? {
        for c in children { if predicate(c) { return c }; if let f = c.firstDescendant(where: predicate) { return f } }
        return nil
    }
}
extension _StackPrimitive {
    var kindIsVertical: Bool { if case .vertical = kind { return true }; return false }
}
