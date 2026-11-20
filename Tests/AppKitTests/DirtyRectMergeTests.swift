// The window's pending dirty rectangles: overlapping areas merge, areas that only touch
// stay apart. corelibs Foundation says two rects that share an edge intersect (with a
// zero-width intersection), and the merge once re-queued such a rect forever on Linux.

import XCTest
@testable import AppKit

final class DirtyRectMergeTests: XCTestCase, @unchecked Sendable {
    func testTouchingRectsPaintSeparatelyAndTerminate() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            w.makeKeyAndOrderFront(nil)
            w.display()
            let v = w.contentView!
            // A row band and a scroller strip that share an edge: their union is far more
            // than they cover, so they are not merged; neither are they split endlessly.
            v.setNeedsDisplay(NSRect(x: 0, y: 0, width: 300, height: 20))
            v.setNeedsDisplay(NSRect(x: 300, y: 0, width: 12, height: 400))
            w.display()
            XCTAssertEqual(w._lastPaintArea, 300 * 20 + 12 * 400, accuracy: 1, "both areas, each once")
            // Overlapping by a sliver with a tiny union overhead: one rectangle.
            v.setNeedsDisplay(NSRect(x: 0, y: 100, width: 100, height: 10))
            v.setNeedsDisplay(NSRect(x: 99, y: 100, width: 100, height: 10))
            w.display()
            XCTAssertEqual(w._lastPaintArea, 199 * 10, accuracy: 1, "merged")
            w.close()
        }
    }
}
