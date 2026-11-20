// What one update costs: a 50 Hz level meter beside a transcript List (Sibyl's capture
// screen) and typing into a grouped Form's field (its Settings). A Windows run spent about
// a second per event-loop iteration redrawing every text and shape in the window on each
// meter tick and keystroke; an update now invalidates only the views it changed and
// measures only the subtree it re-ran (ADR-0010 "Invalidation").

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable
private final class CaptureModel {
    var level: Double = 0
    var lines: [String] = (0..<40).map { "transcript line \($0)" }
}

private struct LevelMeter: View {
    let model: CaptureModel
    var body: some View {
        Capsule().fill(Color.green).frame(width: max(1, model.level * 200), height: 6)
    }
}

private struct Transcript: View {
    let model: CaptureModel
    var body: some View {
        ScrollViewReader { _ in
            List {
                ForEach(model.lines.indices, id: \.self) { i in Text(model.lines[i]) }
            }
        }
    }
}

private struct CaptureScreen: View {
    let model: CaptureModel
    var body: some View {
        VStack(alignment: .leading) {
            LevelMeter(model: model)
            Transcript(model: model)
        }
    }
}

@Observable
private final class SettingsModel {
    var name = ""
    var server = "localhost"
    var enabled = true
}

private struct SettingsForm: View {
    @Bindable var model: SettingsModel
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $model.name)
                TextField("Server", text: $model.server)
                Toggle("Enabled", isOn: $model.enabled)
            }
        }
        .formStyle(.grouped)
    }
}

/// Invalidations per view, the dirty area in the host's coordinates, and measurements.
@MainActor
private final class CostRecorder {
    var marked: [ObjectIdentifier: Int] = [:]
    var markedTypes: [String: Int] = [:]
    var dirty = NSRect.null
    var measured: [String: Int] = [:]
    let host: NSView
    init(host: NSView) { self.host = host }

    func start() {
        reset()
        NSView._invalidationObserver = { [weak self] v, r in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.marked[ObjectIdentifier(v), default: 0] += 1
                self.markedTypes["\(type(of: v))", default: 0] += 1
                if v.window != nil, v === self.host || v.isDescendant(of: self.host) {
                    self.dirty = self.dirty.union(self.host.convert(r, from: v))
                }
            }
        }
        _ViewNode._measureObserver = { [weak self] n, _ in
            MainActor.assumeIsolated {
                guard let self, let p = n.primitive, !p.isLayoutTransparent else { return }
                self.measured["\(type(of: p))", default: 0] += 1
            }
        }
    }
    func stop() {
        NSView._invalidationObserver = nil
        _ViewNode._measureObserver = nil
    }
    func reset() {
        marked = [:]; markedTypes = [:]; dirty = .null; measured = [:]
    }
    func wasMarked(_ v: NSView) -> Bool { marked[ObjectIdentifier(v)] != nil }
    /// The views the next display draws again: the host's subtree is layer-backed, and the
    /// compositor re-renders only layers that need display (the others keep their raster).
    func drawn(_ views: [NSView]) -> [NSView] {
        views.filter { !$0.isHiddenOrHasHiddenAncestor && ($0.layer?.needsDisplay() ?? $0.needsDisplay) }
    }
    var summary: String { markedTypes.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") }
}

@MainActor private func subviewsOf(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(subviewsOf) }

@MainActor private func drawDirtyArea(_ host: NSView, _ recorder: CostRecorder, into rep: NSBitmapImageRep) {
    guard !recorder.dirty.isNull else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
}

private func ms(_ t: TimeInterval) -> String { String(format: "%.2f ms", t * 1000) }

final class SwiftUIUpdateCostTests: XCTestCase, @unchecked Sendable {
    func testMeterTickMarksNoTextAndMeasuresNoRow() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = CaptureModel()
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: CaptureScreen(model: model))
            w.contentView = h
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!
            h.cacheDisplay(in: h.bounds, to: rep)
            let texts = subviewsOf(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(texts.count, 40)
            let recorder = CostRecorder(host: h)
            recorder.start()
            defer { recorder.stop() }

            // 50 meter ticks.
            var markedTexts = 0, drawnTexts = 0, rowMeasures = 0
            var total: TimeInterval = 0, layoutTotal: TimeInterval = 0
            for i in 1...50 {
                recorder.reset()
                let t0 = Date()
                model.level = Double(i) / 50
                h.layoutSubtreeIfNeeded()
                layoutTotal += Date().timeIntervalSince(t0)
                drawnTexts += recorder.drawn(texts).count
                drawDirtyArea(h, recorder, into: rep)
                total += Date().timeIntervalSince(t0)
                markedTexts += texts.filter(recorder.wasMarked).count
                rowMeasures += recorder.measured["_TextPrimitive", default: 0]
                if i == 50 { print("SwiftUIUpdateCostTests: meter tick marks \(recorder.summary); dirty \(recorder.dirty)") }
            }
            let capsule = subviewsOf(h).first { $0 is _ShapeDrawingView }!
            XCTAssertEqual(capsule.frame.width, 200, accuracy: 1, "the meter shows the last level")
            print("SwiftUIUpdateCostTests: 50 meter ticks: \(markedTexts) text marks, \(drawnTexts) text draws, \(rowMeasures) row measurements, \(ms(total / 50)) per tick (layout \(ms(layoutTotal / 50)))")
            XCTAssertEqual(markedTexts, 0, "a meter tick marks no text view")
            XCTAssertEqual(drawnTexts, 0, "a meter tick redraws no text view")
            XCTAssertEqual(rowMeasures, 0, "a meter tick measures no row")

            // A transcript line arrives: the new row's views and the list, nothing else.
            recorder.reset()
            let t0 = Date()
            model.lines.append("transcript line 40")
            h.layoutSubtreeIfNeeded()
            let after = subviewsOf(h).compactMap { $0 as? _TextView }
            let appendDrawn = recorder.drawn(after).count
            drawDirtyArea(h, recorder, into: rep)
            let appendTime = Date().timeIntervalSince(t0)
            XCTAssertEqual(after.count, 41)
            let newRow = after.first { $0.storage.string == "transcript line 40" }!
            let otherMarked = after.filter { $0 !== newRow && recorder.wasMarked($0) }
            print("SwiftUIUpdateCostTests: append marks \(recorder.summary); \(recorder.measured["_TextPrimitive", default: 0]) row measurements, \(otherMarked.count) other texts marked, \(appendDrawn) texts drawn, \(ms(appendTime))")
            XCTAssertTrue(recorder.wasMarked(newRow), "the new row is drawn")
            XCTAssertEqual(otherMarked.count, 0, "no other row is marked")
            XCTAssertLessThanOrEqual(recorder.measured["_TextPrimitive", default: 0], 2, "only the new row is measured")
            XCTAssertNotNil(subviewsOf(h).first { $0 is _ListView }.map(recorder.wasMarked), "the list is marked")
            w.close()
        }
    }

    func testTypingIntoAGroupedFormMarksOnlyTheField() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = SettingsModel()
            typeIntoForm(SettingsForm(model: model), model: model, label: "form")
        }
    }

    /// The form as a Settings tab (Sibyl's General pane).
    func testTypingIntoAFormInATabViewMarksOnlyTheField() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = SettingsModel()
            typeIntoForm(TabView {
                SettingsForm(model: model).tabItem { Label("General", systemImage: "gear") }
                Text("Audio settings").tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            }, model: model, label: "tab")
        }
    }

    @MainActor private func typeIntoForm<V: View>(_ root: V, model: SettingsModel, label: String) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let h = NSHostingView(rootView: root)
        w.contentView = h
        w.makeKeyAndOrderFront(nil)
        h.layoutSubtreeIfNeeded()
        let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds)!
        h.cacheDisplay(in: h.bounds, to: rep)
        guard let scroll = subviewsOf(h).compactMap({ $0 as? NSScrollView }).first,
              let field = subviewsOf(h).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && $0.stringValue == "" }) else {
            return XCTFail("no form scroll view or empty field")
        }
        let documentSize = scroll.documentView!.frame.size
        let scrollers = subviewsOf(scroll).compactMap { $0 as? NSScroller }
        let recorder = CostRecorder(host: h)
        recorder.start()
        defer { recorder.stop() }
        var scrollerMarks = 0, scrollViewMarks = 0, otherTextMarks = 0, drawnTexts = 0
        var total: TimeInterval = 0, layoutTotal: TimeInterval = 0
        let typed = "abcdefghijklmnopqrst"
        for (i, _) in typed.enumerated() {
            recorder.reset()
            let t0 = Date()
            field.stringValue = String(typed.prefix(i + 1))
            NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
            h.layoutSubtreeIfNeeded()
            layoutTotal += Date().timeIntervalSince(t0)
            let others = subviewsOf(h).filter { ($0 is _TextView || $0 is NSTextField) && $0 !== field && !$0.isDescendant(of: field) }
            drawnTexts += recorder.drawn(others).count
            drawDirtyArea(h, recorder, into: rep)
            total += Date().timeIntervalSince(t0)
            scrollerMarks += scrollers.filter(recorder.wasMarked).count
            scrollViewMarks += recorder.wasMarked(scroll) ? 1 : 0
            otherTextMarks += others.filter(recorder.wasMarked).count
            if i == typed.count - 1 { print("SwiftUIUpdateCostTests (\(label)): keystroke marks \(recorder.summary); measured \(recorder.measured)") }
        }
        XCTAssertEqual(model.name, typed)
        print("SwiftUIUpdateCostTests (\(label)): 20 keystrokes: \(scrollerMarks) scroller marks, \(scrollViewMarks) scroll view marks, \(otherTextMarks) other text marks, \(drawnTexts) other texts drawn, \(ms(total / 20)) per keystroke (layout \(ms(layoutTotal / 20)))")
        XCTAssertEqual(scroll.documentView!.frame.size, documentSize, "the form's document keeps its size")
        XCTAssertEqual(scrollerMarks, 0, "the scrollers are not redrawn")
        XCTAssertEqual(scrollViewMarks, 0, "the scroll view is not redrawn")
        XCTAssertEqual(otherTextMarks, 0, "no other text is marked")
        w.close()
    }
}
