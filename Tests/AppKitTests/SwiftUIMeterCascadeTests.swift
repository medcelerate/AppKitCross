// What a 50 Hz level-meter tick costs in Sibyl's capture window: a NavigationSplitView whose
// sidebar List holds three channel rows, each with a name and a level meter (a background
// capsule, a level capsule and a peak capsule bound to an @Observable model), a detail List
// of transcript rows and an inspector with a grouped Form. A Windows run counted, per meter
// tick, the shapes plus about 2.5 `_ContainerView` and 1.5 `_SwiftUISplitView` marks and
// spent about 55 ms per event-loop iteration painting. Frames run as the platform pump runs
// them (`HostWindow.displayIfNeeded()` while a paint is pending, no explicit layout call).

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable private final class _CascadeMeter {
    var level = 0.1
    var peak = 0.2
}

@Observable private final class _CascadeModel {
    let meters = [_CascadeMeter(), _CascadeMeter(), _CascadeMeter()]
    var lines: [String] = (0..<9).map { "Transcript line \($0): the speaker said something worth keeping" }
    var showsInspector = true
    var gain = 0.5
    var muted = false
}

/// Sibyl's meter: the capsules sit in a GeometryReader so the level is a fraction of the
/// width the row gives the meter.
private struct _CascadeLevelMeter: View {
    let meter: _CascadeMeter
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.3))
                Capsule().fill(Color.green).frame(width: max(0, width * meter.level))
                Capsule().fill(Color.orange).frame(width: 2).offset(x: min(width - 2, max(0, width * meter.peak - 1)))
            }
        }
        .frame(height: 4)
    }
}

private struct _CascadeScene: View {
    @Bindable var model: _CascadeModel
    var body: some View {
        NavigationSplitView {
            List(0..<3, id: \.self) { i in
                HStack(spacing: 8) {
                    Image(systemName: "mic")
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Channel \(i + 1)").lineLimit(1)
                        _CascadeLevelMeter(meter: model.meters[i])
                    }
                }
            }
        } detail: {
            List(model.lines, id: \.self) { Text($0) }
                .inspector(isPresented: $model.showsInspector) {
                    Form {
                        Section("Channel") {
                            Slider(value: $model.gain)
                            Toggle("Mute transcription", isOn: $model.muted)
                            LabeledContent("Device", value: "Built-in Microphone")
                        }
                    }
                    .formStyle(.grouped)
                }
        }
    }
}

/// The area of `rects` once overlapping ones are merged, in whole points, as the window
/// keeps its pending dirty areas.
private func _mergedArea(_ rects: [NSRect]) -> CGFloat {
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

@MainActor private func _cascadeViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_cascadeViews) }

final class SwiftUIMeterCascadeTests: XCTestCase, @unchecked Sendable {
    /// Runs the frames the platform would: the host window paints while it has a dirty area.
    @MainActor private func runFrames(_ host: HostWindow, limit: Int = 6) -> Int {
        var frames = 0
        while host._needsPaint, frames < limit { host.displayIfNeeded(); frames += 1 }
        return frames
    }

    func testMeterTickMarksOnlyTheMeters() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _CascadeModel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 780), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: _CascadeScene(model: model))
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            guard let host = window._platformWindow as? HostWindow else { return XCTFail("not the host backend") }
            _ = runFrames(host, limit: 10)
            XCTAssertFalse(host._needsPaint, "idle: no frame pending")
            let texts = _cascadeViews(hosting).compactMap { $0 as? _TextView }
            XCTAssertGreaterThanOrEqual(texts.count, 12, "channel names and transcript rows are on screen")

            // Keyed by type (names are made once, after the ticks), so the observer costs
            // little next to what it measures.
            var marks: [ObjectIdentifier: Int] = [:]
            var names: [ObjectIdentifier: String] = [:]
            var biggestMark: [ObjectIdentifier: CGFloat] = [:]
            var dirty = NSRect.null          // the union of what was marked, in window coordinates
            var rects: [NSRect] = []         // what was marked, one rect per mark
            var drawn: [ObjectIdentifier: Int] = [:]
            NSView._invalidationObserver = { v, r in
                MainActor.assumeIsolated {
                    let k = ObjectIdentifier(type(of: v))
                    if marks[k] == nil, names[k] == nil { names[k] = "\(type(of: v))" }
                    marks[k, default: 0] += 1
                    biggestMark[k] = max(biggestMark[k] ?? 0, r.width * r.height)
                    if v.window === window {
                        let w = v._dirtyRectInWindow(r)
                        dirty = dirty.union(w)
                        rects.append(w)
                    }
                }
            }
            NSView._drawObserver = { v in
                MainActor.assumeIsolated {
                    let k = ObjectIdentifier(type(of: v))
                    if names[k] == nil { names[k] = "\(type(of: v))" }
                    drawn[k, default: 0] += 1
                }
            }
            // Placements and measurements a tick runs, by primitive (the memo and the pass's
            // skipping of unchanged subtrees answer the rest).
            var placed: [String: Int] = [:], measured: [String: Int] = [:]
            _ViewNode._placeObserver = { n in MainActor.assumeIsolated { placed[n.primitive.map { "\(type(of: $0))" } ?? "body", default: 0] += 1 } }
            _ViewNode._measureObserver = { n, _ in MainActor.assumeIsolated { measured[n.primitive.map { "\(type(of: $0))" } ?? "body", default: 0] += 1 } }
            defer { NSView._invalidationObserver = nil; NSView._drawObserver = nil; _ViewNode._placeObserver = nil; _ViewNode._measureObserver = nil }

            let ticks = Int(ProcessInfo.processInfo.environment["CASCADE_TICKS"] ?? "") ?? 50
            var total: TimeInterval = 0, worst: TimeInterval = 0, frames = 0, service: TimeInterval = 0, layoutTime: TimeInterval = 0
            var dirtyArea: CGFloat = 0, worstDirty = NSRect.null, paintArea: CGFloat = 0
            var allMarksByType: [ObjectIdentifier: Int] = [:], allDrawnByType: [ObjectIdentifier: Int] = [:]
            for t in 1...ticks {
                marks = [:]; drawn = [:]; dirty = .null; rects = []
                let t0 = Date()
                for (i, m) in model.meters.enumerated() {
                    m.level = 0.1 + 0.8 * Double((t * (i + 3)) % 17) / 17
                    m.peak = min(1, m.level + 0.05)
                }
                // What the timer's block costs on the main queue: the mutations and the
                // observation callbacks they run (marks and one frame request).
                service += Date().timeIntervalSince(t0)
                // The layout pass the frame starts with, timed on its own (the platform runs
                // it from the pump; the frame's own pass then finds nothing to do).
                let tl = Date()
                window.platformWindowLayout()
                layoutTime += Date().timeIntervalSince(tl)
                frames += runFrames(host)
                let dt = Date().timeIntervalSince(t0)
                total += dt; worst = max(worst, dt)
                if !dirty.isNull {
                    dirtyArea += dirty.width * dirty.height
                    if worstDirty.isNull || dirty.width * dirty.height > worstDirty.width * worstDirty.height { worstDirty = dirty }
                }
                paintArea += _mergedArea(rects)
                for (k, v) in marks { allMarksByType[k, default: 0] += v }
                for (k, v) in drawn { allDrawnByType[k, default: 0] += v }
            }
            func byName(_ d: [ObjectIdentifier: Int]) -> [String: Int] {
                Dictionary(d.map { (names[$0.key] ?? "?", $0.value) }, uniquingKeysWith: +)
            }
            let allMarks = byName(allMarksByType), allDrawn = byName(allDrawnByType)
            let biggest = Dictionary(biggestMark.map { (names[$0.key] ?? "?", $0.value) }, uniquingKeysWith: max)
            func perTick(_ d: [String: Int]) -> String {
                d.sorted { $0.value > $1.value }.map { String(format: "%@ %.1f", $0.key, Double($0.value) / Double(ticks)) }.joined(separator: ", ")
            }
            print(String(format: "SwiftUIMeterCascadeTests: model mutations %.3f ms per tick, layout %.3f ms per tick, paint %.3f ms per tick", service / Double(ticks) * 1000, layoutTime / Double(ticks) * 1000, (total - service - layoutTime) / Double(ticks) * 1000))
            print("SwiftUIMeterCascadeTests: marks per tick: \(perTick(allMarks))")
            print("SwiftUIMeterCascadeTests: placements per tick: \(perTick(placed)) (\(placed.values.reduce(0, +) / ticks) in all)")
            print("SwiftUIMeterCascadeTests: measurements per tick: \(perTick(measured)) (\(measured.values.reduce(0, +) / ticks) in all)")
            print("SwiftUIMeterCascadeTests: draws per tick: \(perTick(allDrawn))")
            print(String(format: "SwiftUIMeterCascadeTests: %.3f ms per tick (worst %.3f ms), %.1f frames per tick, painted area %.0f pt² per tick, bounding box of the marks %.0f pt² (worst %@ of %@)",
                         total / Double(ticks) * 1000, worst * 1000, Double(frames) / Double(ticks), paintArea / CGFloat(ticks), dirtyArea / CGFloat(ticks), "\(worstDirty)", "\(hosting.bounds.size)"))

            let shapes = _cascadeViews(hosting).compactMap { $0 as? _ShapeDrawingView }
            XCTAssertGreaterThanOrEqual(shapes.count, 9, "three meters of three capsules each")
            XCTAssertEqual(allMarks["_TextView", default: 0], 0, "a meter tick marks no text")
            XCTAssertEqual(allMarks["_SwiftUISplitView", default: 0], 0, "a meter tick marks no split view")
            // The containers around the capsules draw nothing: a tick marks the shapes (and
            // their layers' hosts), never a container (a Windows run: 2,542 marks in 30 s).
            XCTAssertEqual(allMarks["_ContainerView", default: 0], 0, "a meter tick marks no container")
            // The layout a tick runs is the three meter rows': the GeometryReader keeps its
            // ancestors' measurements, and the transcript list and the inspector are skipped.
            XCTAssertLessThanOrEqual(measured.values.reduce(0, +), 40 * ticks, "measurements per tick: \(perTick(measured))")
            XCTAssertLessThanOrEqual(placed.values.reduce(0, +), 80 * ticks, "placements per tick: \(perTick(placed))")
            XCTAssertEqual(allDrawn["_TextView", default: 0], 0, "a meter tick draws no text")
            // No ancestor is marked with more than a meter's area (the superview repaints what
            // a capsule uncovered as it shrank; the host the peak capsule's moved layer).
            print("SwiftUIMeterCascadeTests: largest mark per type (pt²): \(biggest.sorted { $0.value > $1.value }.map { "\($0.key) \(Int($0.value))" }.joined(separator: ", "))")
            for (type, area) in biggest where type != "_ShapeDrawingView" {
                XCTAssertLessThanOrEqual(area, 200 * 6, "\(type) is marked with no more than a meter's area")
            }
            // Three meters 4 points high in a sidebar about 200 points wide; the window paints
            // each marked area on its own (NSWindow._takePaintRects), not their bounding box.
            XCTAssertLessThan(paintArea / CGFloat(ticks), 3 * 6 * 200, "the painted area is the meters'")
            XCTAssertFalse(host._needsPaint, "the tick settles: no frame pending")
            window.close()
        }
    }
}
