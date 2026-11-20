// A transcript line that lands animated (Sibyl appends inside `withAnimation` and scrolls
// to the live edge): each animation frame paints the moving row and the band the scroll
// uncovers, not the whole list. The animation tick marked the whole hosting view every
// frame (1100x648 per frame on a Windows run), and the live-edge scroll moved by fractions
// of a pixel, which the backing-store copy cannot do, so the clip repainted too.

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable private final class _LiveModel {
    var rows: [String] = (0..<60).map { "Transcript line \($0): the speaker said something worth keeping" }
}

/// Sibyl's `LiveTranscriptList`: sentinels at both ends, the live edge as the default
/// anchor for size changes, a quick implicit animation keyed to the content, and a scroll
/// to the newest row inside `withAnimation` once the row exists.
private struct _LiveList: View {
    let model: _LiveModel
    var body: some View {
        VStack(spacing: 0) {
            Text("Live transcript").padding(8)
            ScrollViewReader { proxy in
                List {
                    Color.clear.frame(height: 0).listRowInsets(EdgeInsets()).listRowSeparator(.hidden).id("top")
                    ForEach(model.rows, id: \.self) { Text($0) }
                    Color.clear.frame(height: 0).listRowInsets(EdgeInsets()).listRowSeparator(.hidden).id("bottom")
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .animation(.snappy(duration: 0.2), value: model.rows.count)
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: model.rows.count) { withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }
}

@MainActor private func _liveViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_liveViews) }

final class SwiftUIAnimatedRowTests: XCTestCase, @unchecked Sendable {
    func testAnimatedAppendPaintsTheRowBandPerFrame() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 100
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let holdBefore = NSScrollView._overlayHoldInterval
            NSScrollView._overlayHoldInterval = 3600
            defer { NSScrollView._overlayHoldInterval = holdBefore }

            let model = _LiveModel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: _LiveList(model: model))
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            guard let host = window._platformWindow as? HostWindow else { XCTFail("not the host backend"); return }
            var frames = 0
            while host._needsPaint, frames < 10 { host.displayIfNeeded(); frames += 1 }
            guard let scroll = _liveViews(hosting).compactMap({ $0 as? NSScrollView }).first else { XCTFail("no scroll view"); return }
            let clip = scroll.contentView
            let originBefore = clip.bounds.origin
            let clipInWindow = clip.convert(clip.bounds, to: nil)
            let whole = hosting.bounds.width * hosting.bounds.height
            let root = hosting.hostingRoot as! _ViewRoot

            let copies = host.scrollCopyCount
            model.rows.append("Transcript line 60: a new line lands")
            var perFrame: [CGFloat] = []
            @MainActor func settle() -> CGFloat {
                var area: CGFloat = 0, n = 0
                while host._needsPaint, n < 6 {
                    let painted = host.paintCount
                    host.displayIfNeeded(); n += 1
                    if host.paintCount != painted { area += window._lastPaintArea }
                }
                return area
            }
            perFrame.append(settle())
            XCTAssertTrue(root.isAnimating, "the append animates")
            var ticks = 0
            while root.isAnimating, ticks < 30 {
                clock += 1.0 / 60
                CARuntime.tick()
                perFrame.append(settle())
                ticks += 1
            }
            XCTAssertFalse(root.isAnimating, "the animation ends")
            let delta = clip.bounds.origin.y - originBefore.y
            print("SwiftUIAnimatedRowTests: \(ticks) ticks, scrolled \(delta), per frame \(perFrame.map { Int($0) }), copies \(host.scrollCopyCount - copies)")
            XCTAssertGreaterThan(abs(delta), 10, "the list followed the new row")
            XCTAssertEqual(clip.bounds.maxY, clip.documentRect.maxY, accuracy: 10, "the newest row is in view")
            XCTAssertGreaterThan(ticks, 3, "several animation frames ran")
            // Every frame: at most a couple of row bands plus the overlay scroller's strip,
            // never the visible list.
            let rowBand = 40 * clipInWindow.width
            for (i, a) in perFrame.enumerated() {
                XCTAssertLessThan(a, rowBand * 3 + 20 * clipInWindow.height, "frame \(i) paints a band, not the list (\(Int(a)) of \(Int(whole)))")
            }
            XCTAssertGreaterThan(host.scrollCopyCount, copies, "the live-edge scroll moved the pixels it already had")
            // The scroll settles on device pixels.
            let scale = max(1, window.backingScaleFactor)
            XCTAssertEqual((clip.bounds.origin.y * scale).rounded() / scale, clip.bounds.origin.y, accuracy: 0.001, "the clip scrolls by whole pixels")
        }
    }
}
