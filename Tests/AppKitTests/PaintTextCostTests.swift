// What a repaint costs in text work (ADR-0054): a view that asks for its font and draws its
// labels in `draw(_:)` every frame, as the Glass example's bands do, must not build a
// platform font or lay out a line again once it has drawn them once.

import XCTest
@testable import AppKit

private final class _LabelledBandsView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<Int(bounds.height / 90) {
            let band = NSRect(x: 0, y: CGFloat(i) * 90, width: bounds.width, height: 90)
            guard band.intersects(dirtyRect) else { continue }
            NSColor(calibratedHue: CGFloat(i % 10) / 10, saturation: 0.5, brightness: 0.9, alpha: 1).setFill()
            band.fill()
            let label = NSAttributedString(string: "Band \(i + 1)", attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: i % 2 == 0 ? NSColor.black : NSColor.white])
            label.draw(at: NSPoint(x: bounds.width - 140, y: band.minY + 30))
        }
    }
}

final class PaintTextCostTests: XCTestCase, @unchecked Sendable {
    func testFontRequestsAnswerWithTheSameFont() {
        MainActor.assumeIsolated {
            let a = NSFont.systemFont(ofSize: 22, weight: .semibold)
            let b = NSFont.systemFont(ofSize: 22, weight: .semibold)
            XCTAssertTrue(a === b, "a repeated request is served from the cache")
            XCTAssertFalse(a === NSFont.systemFont(ofSize: 22), "a different weight is a different font")
            XCTAssertEqual(NSFont.systemFont(ofSize: 13).pointSize, 13)
        }
    }

    func testRepaintingTheSameLabelsMakesNoFontsAndLaysOutNoLines() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let document = _LabelledBandsView(frame: NSRect(x: 0, y: 0, width: 600, height: 1800))
            scroll.documentView = document
            window.contentView!.addSubview(scroll)
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            guard let host = window._platformWindow as? HostWindow else { XCTFail("not the host backend"); return }
            var frames = 0
            while host._needsPaint, frames < 10 { host.displayIfNeeded(); frames += 1 }

            // Every band once (whole repaints), then repaint them all again: the second pass
            // draws the same strings and builds nothing.
            document.needsDisplay = true
            while host._needsPaint { host.displayIfNeeded() }
            let before = _NSPaintTextCounters.read()
            document.needsDisplay = true
            while host._needsPaint { host.displayIfNeeded() }
            let repaint = _NSPaintTextCounters.read().since(before)
            XCTAssertGreaterThan(repaint.stringsDrawn, 0, "the labels were drawn")
            XCTAssertEqual(repaint.linesLaidOut, 0, "drawn labels come from the line cache")
            XCTAssertEqual(repaint.fontsMade, 0, "systemFont(ofSize:weight:) in draw(_:) makes no platform font")

            // Each walk reports no more views drawn than entered.
            XCTAssertFalse(window._lastPaintWalks.isEmpty)
            for walk in window._lastPaintWalks { XCTAssertLessThanOrEqual(walk.drawn, walk.visited) }
        }
    }
}
