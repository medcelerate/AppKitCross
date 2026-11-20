// What a new transcript line costs in Sibyl's detail list: a List (or a ScrollView over a
// LazyVStack) of about forty text rows in a 1100x700 window. A Windows run painted the whole
// content area (`1100x1349, 1 rects`) for every line that landed; on the Mac a new row
// dirties only itself and the rows it shifts. Frames run as the platform pump runs them.

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable private final class _GrowthModel {
    var lines: [String] = (0..<40).map { "Transcript line \($0): the speaker said something worth keeping" }
}

private struct _GrowthList: View {
    let model: _GrowthModel
    var body: some View {
        VStack(spacing: 0) {
            Text("Live transcript").padding(8)
            List(model.lines, id: \.self) { Text($0) }
        }
    }
}

private struct _GrowthStack: View {
    let model: _GrowthModel
    var body: some View {
        VStack(spacing: 0) {
            Text("Live transcript").padding(8)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.lines, id: \.self) { Text($0) }
                }
            }
        }
    }
}

/// Sibyl's `LiveTranscriptList`: a List between two zero-height sentinel rows, in a
/// ScrollViewReader, inset style (following the live edge off: the scroll position stays).
private struct _GrowthLiveList: View {
    let model: _GrowthModel
    var body: some View {
        ScrollViewReader { _ in
            List {
                Color.clear.frame(height: 0).listRowInsets(EdgeInsets()).listRowSeparator(.hidden).id("top")
                ForEach(model.lines, id: \.self) { Text($0).id($0) }
                Color.clear.frame(height: 0).listRowInsets(EdgeInsets()).listRowSeparator(.hidden).id("bottom")
            }
            .listStyle(.inset)
        }
    }
}

@MainActor private func _growthViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_growthViews) }

/// The area of `rects` once overlapping ones are merged, in whole points, as the window
/// keeps its pending dirty areas (`NSWindow._noteDirty`) and paints them one by one.
private func _growthMergedArea(_ rects: [NSRect]) -> CGFloat {
    var merged: [NSRect] = []
    for r0 in rects where !r0.isEmpty {
        var r = r0.integral
        var i = 0
        while i < merged.count {
            if merged[i].intersects(r) { r = r.union(merged[i]); merged.remove(at: i); i = 0 } else { i += 1 }
        }
        merged.append(r)
    }
    return merged.reduce(0) { $0 + $1.width * $1.height }
}

final class SwiftUIListGrowthTests: XCTestCase, @unchecked Sendable {
    @MainActor private struct _Run {
        /// The platform's dirty rectangle per frame (the bounding box, Win32's `rcPaint`).
        var paintRects: [NSRect] = []
        /// What the views marked, in window coordinates clipped to the window.
        var markRects: [(String, NSRect)] = []
        var marks: [String: Int] = [:]
        var markedTexts: [String] = []
    }

    /// Hosts `root`, idles it, applies `change`, runs the frames and reports what they marked
    /// and painted (window coordinates).
    @MainActor private func measure<V: View>(_ root: V, _ change: () -> Void) -> (_Run, NSRect)? {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: root)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        guard let host = window._platformWindow as? HostWindow else { XCTFail("not the host backend"); return nil }
        var frames = 0
        while host._needsPaint, frames < 10 { host.displayIfNeeded(); frames += 1 }
        XCTAssertFalse(host._needsPaint, "idle: no frame pending")
        let whole = NSRect(origin: .zero, size: hosting.bounds.size)
        var run = _Run()
        let stacks = ProcessInfo.processInfo.environment["GROWTH_STACKS"]
        NSView._invalidationObserver = { v, r in
            MainActor.assumeIsolated {
                let name = "\(type(of: v))"
                run.marks[name, default: 0] += 1
                if v.window === window {
                    let w = v._dirtyRectInWindow(r).intersection(whole)
                    if !w.isNull, !w.isEmpty { run.markRects.append((name, w)) }
                }
                if let t = v as? _TextView { run.markedTexts.append(t.storage.string) }
                if let stacks, name.hasPrefix(stacks) { print("STACK \(name) \(r)\n" + Thread.callStackSymbols.prefix(24).joined(separator: "\n")) }
            }
        }
        change()
        frames = 0
        while host._needsPaint, frames < 6 {
            host.displayIfNeeded(); frames += 1
            if let r = host.lastPaintRect { run.paintRects.append(r) }
        }
        NSView._invalidationObserver = nil
        XCTAssertFalse(host._needsPaint, "the change settles")
        print("SwiftUIListGrowthTests \(name): \(frames) frames, painted \(Int(_growthMergedArea(run.markRects.map(\.1)))) pt² of \(Int(whole.width * whole.height)), platform rects \(run.paintRects.map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.minX)),\(Int($0.minY))" }); marks \(run.markRects.map { "\($0.0) \(Int($0.1.width))x\(Int($0.1.height))@\(Int($0.1.minX)),\(Int($0.1.minY))" })")
        return (run, whole)
    }

    private func check(_ run: _Run, _ whole: NSRect, maxFraction: CGFloat, untouched: (String) -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let area = _growthMergedArea(run.markRects.map(\.1))
        XCTAssertLessThan(area, whole.width * whole.height * maxFraction, "the frames paint a small part of the window: \(run.markRects)", file: file, line: line)
        // The platform's one dirty rectangle per frame (what Win32 reports as `rcPaint`) is
        // small too: no mark far from the change grows it to the content area.
        let platform = run.paintRects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        XCTAssertLessThan(platform, whole.width * whole.height * maxFraction, "the platform's dirty rectangles are small: \(run.paintRects)", file: file, line: line)
        let wrong = run.markedTexts.filter(untouched)
        XCTAssertTrue(wrong.isEmpty, "no row above the change is marked: \(wrong)", file: file, line: line)
        XCTAssertFalse(run.markedTexts.contains("Live transcript"), "the chrome above the list stays clean", file: file, line: line)
    }

    private static func lineNumber(_ s: String) -> Int? {
        guard s.hasPrefix("Transcript line ") else { return nil }
        return Int(s.dropFirst("Transcript line ".count).prefix { $0.isNumber })
    }

    func testListAppendPaintsOnlyTheNewRow() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _GrowthModel()
            model.lines = Array(model.lines.prefix(12))     // the list does not fill the window yet
            guard let (run, whole) = measure(_GrowthList(model: model), { model.lines.append("Transcript line 12: a new line lands") }) else { return }
            check(run, whole, maxFraction: 0.08, untouched: { (Self.lineNumber($0) ?? 99) < 12 })
        }
    }

    func testListAppendBelowTheFoldPaintsAlmostNothing() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _GrowthModel()
            guard let (run, whole) = measure(_GrowthList(model: model), { model.lines.append("Transcript line 40: a new line lands") }) else { return }
            // The row lands below the visible area; only the scroller's knob changes.
            check(run, whole, maxFraction: 0.05, untouched: { (Self.lineNumber($0) ?? 99) < 40 })
        }
    }

    func testListInsertPaintsTheShiftedBand() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _GrowthModel()
            model.lines = Array(model.lines.prefix(12))
            guard let (run, whole) = measure(_GrowthList(model: model), { model.lines.insert("Transcript line 8b: an insertion", at: 8) }) else { return }
            check(run, whole, maxFraction: 0.25, untouched: { (Self.lineNumber($0) ?? 99) < 8 })
        }
    }

    func testLiveTranscriptListAppendPaintsTheNewRowAndTheSentinel() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _GrowthModel()
            model.lines = Array(model.lines.prefix(12))
            guard let (run, whole) = measure(_GrowthLiveList(model: model), { model.lines.append("Transcript line 12: a new line lands") }) else { return }
            check(run, whole, maxFraction: 0.08, untouched: { (Self.lineNumber($0) ?? 99) < 12 })
        }
    }

    func testLazyStackAppendPaintsOnlyTheNewRow() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _GrowthModel()
            model.lines = Array(model.lines.prefix(12))
            guard let (run, whole) = measure(_GrowthStack(model: model), { model.lines.append("Transcript line 12: a new line lands") }) else { return }
            check(run, whole, maxFraction: 0.08, untouched: { (Self.lineNumber($0) ?? 99) < 12 })
        }
    }

    func testLazyStackAppendBelowTheFoldPaintsAlmostNothing() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _GrowthModel()
            guard let (run, whole) = measure(_GrowthStack(model: model), { model.lines.append("Transcript line 40: a new line lands") }) else { return }
            check(run, whole, maxFraction: 0.05, untouched: { (Self.lineNumber($0) ?? 99) < 40 })
        }
    }
}
