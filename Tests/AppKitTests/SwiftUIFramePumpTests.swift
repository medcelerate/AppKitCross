// A model change must reach the screen through the frame clock alone, as on Windows:
// nothing calls layoutSubtreeIfNeeded for the app; a frame paints whatever asked for one.
// The port's "repaint only what changed" work had left a stale screen: the update marked
// needsLayout and nothing requested a frame.

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable private final class _PumpModel {
    var text = "Stopped"
    var level = 0.2
    var rows = ["one", "two"]
    var progress = 0.0
}

@MainActor private func _pumpViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_pumpViews) }

final class SwiftUIFramePumpTests: XCTestCase, @unchecked Sendable {
    /// Runs the frames the platform would: the host window paints while it has a dirty area.
    @MainActor private func runFrames(_ window: NSWindow, limit: Int = 4) -> Int {
        guard let host = window._platformWindow as? HostWindow else { XCTFail("not the host backend"); return 0 }
        var frames = 0
        while host._needsPaint, frames < limit { host.displayIfNeeded(); frames += 1 }
        return frames
    }
    @MainActor private func drawnTexts(_ hosting: NSView) -> [String] {
        _pumpViews(hosting).compactMap { ($0 as? _TextView)?.storage.string }
    }

    func testModelChangesReachTheScreenThroughFramesAlone() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Screen: View {
                let model: _PumpModel
                var body: some View {
                    VStack(alignment: .leading) {
                        GeometryReader { _ in HStack { Circle().frame(width: 8, height: 8); Text(model.text) } }.frame(height: 20)
                        Capsule().frame(width: model.level * 200, height: 6)
                        ProgressView(value: model.progress)
                        List(model.rows, id: \.self) { Text($0) }.frame(height: 120)
                    }
                }
            }
            let model = _PumpModel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: Screen(model: model))
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            _ = runFrames(window, limit: 6)
            XCTAssertTrue(drawnTexts(hosting).contains("Stopped"))
            XCTAssertFalse((window._platformWindow as? HostWindow)?._needsPaint ?? true, "idle: no frame pending")

            // A notice read inside a GeometryReader.
            model.text = "Download the Tiny model first"
            XCTAssertTrue((window._platformWindow as? HostWindow)?._needsPaint ?? false, "the change requested a frame")
            var marks: [String: Int] = [:]
            NSView._invalidationObserver = { v, _ in marks["\(type(of: v))", default: 0] += 1 }
            defer { NSView._invalidationObserver = nil }
            let frames = runFrames(window)
            XCTAssertGreaterThan(frames, 0)
            XCTAssertTrue(drawnTexts(hosting).contains("Download the Tiny model first"), "the status text re-rendered through frames alone")
            XCTAssertGreaterThanOrEqual(marks["_TextView", default: 0], 1, "the text view was marked for drawing")

            // A meter tick marks its own shape, and only that.
            marks = [:]
            model.level = 0.6
            _ = runFrames(window)
            XCTAssertGreaterThanOrEqual(marks["_ShapeDrawingView", default: 0], 1, "the meter's shape repaints: \(marks)")
            XCTAssertEqual(marks["_TextView", default: 0], 0, "no text repaints for a meter tick: \(marks)")

            // Progress and list rows.
            model.progress = 0.5
            _ = runFrames(window)
            let bar = _pumpViews(hosting).compactMap { $0 as? NSProgressIndicator }.first
            XCTAssertEqual(bar?.doubleValue ?? -1, 0.5, accuracy: 0.001, "the progress bar follows the model")
            model.rows.append("three")
            _ = runFrames(window)
            XCTAssertTrue(drawnTexts(hosting).contains("three"), "a new list row is drawn")
            window.close()
        }
    }
}
