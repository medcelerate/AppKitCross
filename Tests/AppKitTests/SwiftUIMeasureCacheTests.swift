// Measurements survive layout passes (Runtime.swift): a pass after one leaf changed
// re-measures that leaf and its ancestors only; a new proposal, a new environment and a
// backing view that changed size on its own still measure again.

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

/// Counts its node's measurements (the node's memo answers repeats without asking).
@MainActor
private final class MeasureCounter {
    var count = 0
    init() {}
}

@MainActor
private final class _CountingLeafPrimitive: _Primitive {
    let counter: MeasureCounter
    init(counter: MeasureCounter) { self.counter = counter; super.init() }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        counter.count += 1
        return CGSize(width: min(proposal.width ?? 40, 40), height: 12)
    }
    override func place(node: _ViewNode, in rect: CGRect) {}
}

/// A leaf row that counts how often it is measured.
private struct CountingLeaf: View, _PrimitiveView {
    typealias Body = Never
    let counter: MeasureCounter
    func _makePrimitive(node: _ViewNode) -> _Primitive { _CountingLeafPrimitive(counter: counter) }
}

@MainActor
private final class _CountingWrapperPrimitive: _Primitive {
    let counter: MeasureCounter
    init(counter: MeasureCounter, content: _AnyViewBox) { self.counter = counter; super.init(); children = [content] }
    override func sizeThatFits(_ proposal: ProposedViewSize, node: _ViewNode) -> CGSize {
        counter.count += 1
        return super.sizeThatFits(proposal, node: node)
    }
}

/// Wraps content and counts how often the wrapper itself is measured.
private struct CountingWrapper<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let counter: MeasureCounter
    let content: Content
    func _makePrimitive(node: _ViewNode) -> _Primitive { _CountingWrapperPrimitive(counter: counter, content: _ViewBox(content)) }
}

@Observable
private final class Meter {
    var level = "level 0"
    var font: Font = .body
}

private struct MeterText: View {
    let meter: Meter
    var body: some View { Text(meter.level) }
}

/// 200 rows: an observable-driven leaf (wrapped), a counting row and 198 texts.
private struct Rows: View {
    let meter: Meter
    let outer: MeasureCounter, leafWrapper: MeasureCounter, row: MeasureCounter
    var body: some View {
        CountingWrapper(counter: outer, content: VStack(spacing: 0) {
            CountingWrapper(counter: leafWrapper, content: MeterText(meter: meter))
            CountingLeaf(counter: row)
            ForEach(0..<198, id: \.self) { i in Text("transcript line \(i)") }
        })
    }
}

/// Reads the model's font in its own body, so a font change re-runs from here down.
private struct Styled: View {
    let meter: Meter
    let row: MeasureCounter
    var body: some View {
        VStack {
            Text("title")
            CountingLeaf(counter: row)
        }
        .font(meter.font)
    }
}

/// A view whose height changes without SwiftUI knowing (it invalidates its own size).
private final class GrowingView: NSView {
    var height: CGFloat = 20 { didSet { invalidateIntrinsicContentSize() } }
    override var intrinsicContentSize: NSSize { NSSize(width: 60, height: height) }
}

private struct Growing: NSViewRepresentable {
    let view: GrowingView
    func makeNSView(context: Context) -> GrowingView { view }
    func updateNSView(_ nsView: GrowingView, context: Context) {}
}

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 4000) -> (NSWindow, NSHostingView<V>) {
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

final class SwiftUIMeasureCacheTests: XCTestCase, @unchecked Sendable {
    func testLeafChangeRemeasuresOnlyItsAncestors() {
        MainActor.assumeIsolated {
            let meter = Meter()
            let outer = MeasureCounter(), leafWrapper = MeasureCounter(), row = MeasureCounter()
            let (w, h) = host(Rows(meter: meter, outer: outer, leafWrapper: leafWrapper, row: row))
            XCTAssertGreaterThan(row.count, 0, "the first pass measures every row")
            let first = (outer: outer.count, leaf: leafWrapper.count, row: row.count)

            // An idle pass measures nothing.
            h.needsLayout = true
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(outer.count, first.outer, "an idle pass answers from the memo")
            XCTAssertEqual(row.count, first.row)

            outer.count = 0; leafWrapper.count = 0; row.count = 0
            meter.level = "level 1"
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(allViews(h).contains { ($0 as? _TextView)?.storage.string == "level 1" }, "the leaf shows the new value")
            XCTAssertGreaterThan(leafWrapper.count, 0, "the changed leaf's ancestor measures again")
            XCTAssertGreaterThan(outer.count, 0, "the stack's ancestor measures again")
            XCTAssertEqual(row.count, 0, "an unrelated row is not measured again")
            let incremental = (outer: outer.count, leaf: leafWrapper.count, row: row.count)

            // The old behaviour (every pass a new generation) for comparison.
            let root = h.hostingRoot as! _ViewRoot
            outer.count = 0; leafWrapper.count = 0; row.count = 0
            meter.level = "level 2"
            root.invalidateAllMeasurements()
            h.layoutSubtreeIfNeeded()
            print("SwiftUIMeasureCacheTests: leaf change, unrelated row measured \(incremental.row)x (outer \(incremental.outer), leaf wrapper \(incremental.leaf)); with a global clear the row is measured \(row.count)x (outer \(outer.count), leaf wrapper \(leafWrapper.count))")
            XCTAssertGreaterThan(row.count, 0)
            w.close()
        }
    }

    func testNewProposalRemeasures() {
        MainActor.assumeIsolated {
            let meter = Meter()
            let outer = MeasureCounter(), leafWrapper = MeasureCounter(), row = MeasureCounter()
            let (w, h) = host(Rows(meter: meter, outer: outer, leafWrapper: leafWrapper, row: row))
            row.count = 0
            h.frame.size.width = 200
            h.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(row.count, 0, "a narrower host proposes a new width to every row")
            w.close()
        }
    }

    func testEnvironmentChangeRemeasures() {
        MainActor.assumeIsolated {
            let meter = Meter()
            let row = MeasureCounter()
            let (w, h) = host(Styled(meter: meter, row: row))
            row.count = 0
            meter.font = .largeTitle
            h.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(row.count, 0, "a new font re-runs the subtree and measures it again")

            // A root-level environment change measures everything again too.
            row.count = 0
            (h.hostingRoot as! _ViewRoot).environmentDidChange(h.environment)
            h.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(row.count, 0)
            w.close()
        }
    }

    func testBackingViewThatGrowsOnItsOwnRelayouts() {
        MainActor.assumeIsolated {
            let grow = GrowingView(frame: .zero)
            let probe = MeasureCounter()
            let (w, h) = host(VStack(spacing: 0) {
                Text("above")
                Growing(view: grow)
                Text("below")
                CountingLeaf(counter: probe)
            }.fixedSize(), height: 400)
            XCTAssertEqual(grow.frame.height, 20)
            let below = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "below" }!
            let gap = below.frame.minY - grow.frame.maxY
            probe.count = 0
            grow.height = 70
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(grow.frame.height, 70, "the representable takes its new size")
            XCTAssertEqual(below.frame.minY - grow.frame.maxY, gap, accuracy: 1, "the enclosing stack lays out around it")
            XCTAssertEqual(below.superview, grow.superview)
            XCTAssertEqual(probe.count, 0, "its siblings answer from the memo")
            w.close()
        }
    }

    func testSplitDividerDragInvalidatesMeasurement() {
        MainActor.assumeIsolated {
            let probe = MeasureCounter()
            let (w, h) = host(VStack { CountingLeaf(counter: probe); Text("x") }, height: 200)
            let root = h.hostingRoot as! _ViewRoot
            let node = root.firstNode { $0.primitive is _CountingLeafPrimitive }!
            probe.count = 0
            node.invalidateMeasurement()
            XCTAssertTrue(h.needsLayout, "the entry point schedules a pass")
            h.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(probe.count, 0, "an invalidated node measures again")
            w.close()
        }
    }
}
