// What following a live transcript costs: Sibyl's `LiveTranscriptList` scrolls a List to its
// newest row (`proxy.scrollTo(last, anchor: .bottom)`) every time a line lands. A Windows run
// painted the whole visible list (`1100x648, 1 rect`) per line, because the clip view's new
// bounds origin marked everything it shows. AppKit's layer-backed scrolling moves the pixels
// it already has and draws only the band the scroll exposes; so does the port's
// `NSClipView` (`PlatformWindow.scrollBacking`).

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable private final class _FollowModel {
    var rows: [String] = (0..<60).map { "Transcript line \($0): the speaker said something worth keeping" }
}

private struct _FollowList: View {
    let model: _FollowModel
    var body: some View {
        VStack(spacing: 0) {
            Text("Live transcript").padding(8)
            ScrollViewReader { proxy in
                List(model.rows, id: \.self) { Text($0) }
                    .onAppear { proxy.scrollTo(model.rows.last!, anchor: .bottom) }
                    .onChange(of: model.rows.count) { proxy.scrollTo(model.rows.last!, anchor: .bottom) }
            }
        }
    }
}

@MainActor private func _followViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_followViews) }

/// The area `rects` cover together, in whole points (overlaps counted once).
@MainActor private func _followMergedArea(_ rects: [NSRect]) -> CGFloat {
    var disjoint: [NSRect] = []
    for r0 in rects where !r0.isEmpty {
        var pieces = [r0.integral]
        for e in disjoint { pieces = pieces.flatMap { NSView._difference($0, e) } }
        disjoint += pieces
    }
    return disjoint.reduce(0) { $0 + $1.width * $1.height }
}

/// The image's pixels as premultiplied BGRA rows, top row first.
private func _followPixels(_ image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (bytes, w, h)
}

/// A document of coloured stripes and a diagonal, so a misplaced copy shows.
private final class _StripesView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<Int(bounds.height / 10) {
            NSColor(calibratedHue: CGFloat(i % 12) / 12, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: 0, y: CGFloat(i) * 10, width: bounds.width, height: 10).fill()
        }
        NSColor.black.setStroke()
        let p = NSBezierPath()
        p.move(to: .zero); p.line(to: NSPoint(x: bounds.width, y: bounds.height)); p.lineWidth = 3; p.stroke()
    }
}

final class SwiftUIScrollCopyTests: XCTestCase, @unchecked Sendable {
    /// An AppKit scroll view scrolled programmatically, down, sideways, back and by more
    /// than it shows: every frame matches a full repaint, and the small scrolls copy.
    func testClipViewScrollMatchesAFullRepaint() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 300, height: 200))
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = true
            scroll.documentView = _StripesView(frame: NSRect(x: 0, y: 0, width: 900, height: 2000))
            window.contentView!.addSubview(scroll)
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            guard let host = window._platformWindow as? HostWindow else { XCTFail("not the host backend"); return }
            var frames = 0
            while host._needsPaint, frames < 10 { host.displayIfNeeded(); frames += 1 }
            let clip = scroll.contentView
            for (step, origin) in [NSPoint(x: 0, y: 37), NSPoint(x: 23, y: 37), NSPoint(x: 23, y: 12), NSPoint(x: 0, y: 900), NSPoint(x: 5.5, y: 900.5)].enumerated() {
                let copies = host.scrollCopyCount
                clip.scroll(to: origin)
                scroll.reflectScrolledClipView(clip)
                frames = 0
                var area: CGFloat = 0
                while host._needsPaint, frames < 6 {
                    let n = host.paintCount
                    host.displayIfNeeded(); frames += 1
                    if host.paintCount != n { area += window._lastPaintArea }
                }
                if step < 3 {
                    XCTAssertEqual(host.scrollCopyCount, copies + 1, "step \(step) copies")
                    XCTAssertLessThan(area, 300 * 200 * 0.6, "step \(step) paints the uncovered band and the scrollers")
                }
                guard let scrolled = host.lastImage.map(_followPixels) else { XCTFail("no image"); return }
                window._setNeedsDisplayWhole()
                host.displayIfNeeded()
                guard let full = host.lastImage.map(_followPixels) else { XCTFail("no image"); return }
                var box = (x0: Int.max, y0: Int.max, x1: -1, y1: -1), count = 0, maxDiff = 0
                for y in 0..<full.height {
                    let row = y * full.width * 4
                    if scrolled.bytes[row..<(row + full.width * 4)].elementsEqual(full.bytes[row..<(row + full.width * 4)]) { continue }
                    for x in 0..<full.width {
                    let i = (y * full.width + x) * 4
                    let worst = (0..<4).map { abs(Int(scrolled.bytes[i + $0]) - Int(full.bytes[i + $0])) }.max()!
                    maxDiff = max(maxDiff, worst)
                    if worst > 0 { count += 1; box = (min(box.x0, x), min(box.y0, y), max(box.x1, x), max(box.y1, y)) }
                } }
                // Equal but for the diagonal's antialiasing, which CoreGraphics computes a
                // level or two differently at another offset from the clip (a misplaced copy
                // differs by whole stripes).
                XCTAssertLessThanOrEqual(maxDiff, 4, "step \(step) (\(origin)): the scrolled frame matches a full repaint; \(count) px differ (by up to \(maxDiff)) in px \(box) (top-left, scale \(full.width / 400))")
            }
        }
    }


    func testFollowingTheLiveEdgeCopiesTheVisibleRowsAndPaintsTheNewBand() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let model = _FollowModel()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: _FollowList(model: model))
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            guard let host = window._platformWindow as? HostWindow else { XCTFail("not the host backend"); return }
            var frames = 0
            while host._needsPaint, frames < 10 { host.displayIfNeeded(); frames += 1 }
            XCTAssertFalse(host._needsPaint, "idle: no frame pending")
            guard let scroll = _followViews(hosting).compactMap({ $0 as? NSScrollView }).first else { XCTFail("no scroll view"); return }
            let clip = scroll.contentView
            let doc = clip.documentRect
            XCTAssertEqual(clip.bounds.maxY, doc.maxY, accuracy: 10, "scrolled to the newest row before the line lands")
            let originBefore = clip.bounds.origin
            let clipInWindow = clip.convert(clip.bounds, to: nil)
            // The overlay scroller's fade timers would mark it again later; hold it.
            let holdBefore = NSScrollView._overlayHoldInterval
            NSScrollView._overlayHoldInterval = 3600
            defer { NSScrollView._overlayHoldInterval = holdBefore }
            guard let before = host.lastImage.map(_followPixels) else { XCTFail("no image"); return }

            let whole = NSRect(origin: .zero, size: hosting.bounds.size)
            var markRects: [(String, NSRect)] = []
            var markedTexts: [String] = []
            var paintRects: [NSRect] = []
            NSView._invalidationObserver = { v, r in
                MainActor.assumeIsolated {
                    guard v.window === window else { return }
                    let w = v._dirtyRectInWindow(r).intersection(whole)
                    // What a clip view's scroll hides is not drawn (`_viewNeedsDisplay`).
                    var vis = w
                    var a = v.superview
                    while let s = a, !vis.isNull { if s is NSClipView { vis = vis.intersection(s._dirtyRectInWindow(s.bounds)) }; a = s.superview }
                    if !vis.isNull, !vis.isEmpty { markRects.append(("\(type(of: v))", vis)) }
                    if let stacks = ProcessInfo.processInfo.environment["SCROLLCOPY_STACKS"], "\(type(of: v))".hasPrefix(stacks) { print("STACK \(type(of: v)) \(r)\n" + Thread.callStackSymbols.prefix(30).joined(separator: "\n")) }
                    if let t = v as? _TextView, !vis.isNull, !vis.isEmpty { markedTexts.append(t.storage.string) }
                }
            }
            let copies = host.scrollCopyCount
            model.rows.append("Transcript line 60: a new line lands")
            frames = 0
            var paintedArea: CGFloat = 0
            while host._needsPaint, frames < 6 {
                let painted = host.paintCount
                host.displayIfNeeded(); frames += 1
                guard host.paintCount != painted else { continue }      // a layout pass only
                if let r = host.lastPaintRect { paintRects.append(r) }
                paintedArea += window._lastPaintArea
            }
            NSView._invalidationObserver = nil
            XCTAssertFalse(host._needsPaint, "the change settles")
            let delta = clip.bounds.origin.y - originBefore.y
            print("SwiftUIScrollCopyTests: \(frames) frames, scrolled \(delta), painted \(Int(paintedArea)) pt² of \(Int(whole.width * whole.height)), platform rects \(paintRects.map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.minX)),\(Int($0.minY))" }); marks \(markRects.map { "\($0.0) \(Int($0.1.width))x\(Int($0.1.height))@\(Int($0.1.minX)),\(Int($0.1.minY))" })")
            XCTAssertGreaterThan(abs(delta), 10, "the list followed the new row")
            XCTAssertEqual(host.scrollCopyCount, copies + 1, "the backing store moved the visible rows")
            XCTAssertLessThan(abs(delta), 60, "by about one row")
            XCTAssertEqual(clip.bounds.maxY, clip.documentRect.maxY, accuracy: 10, "the newest row is in view")

            // The paint draws about the exposed band, the rows' separators next to it and the
            // overlay scroller: far less than the visible list.
            let rowBand = abs(delta) * clipInWindow.width
            XCTAssertGreaterThan(paintedArea, 0, "the new row is drawn")
            XCTAssertLessThan(paintedArea, rowBand * 2.5 + 20 * clipInWindow.height, "the scroll paints a band, not the list: \(markRects)")
            XCTAssertLessThan(_followMergedArea(markRects.map(\.1)), whole.width * whole.height * 0.15, "views mark a band: \(markRects)")
            XCTAssertFalse(markedTexts.contains("Live transcript"), "the header stays clean")
            let olderRows = markedTexts.filter { $0.hasPrefix("Transcript line ") && !$0.hasPrefix("Transcript line 60") && !$0.hasPrefix("Transcript line 59") }
            XCTAssertTrue(olderRows.isEmpty, "no row that was already on screen is marked: \(olderRows)")

            // A row visible before and after shows the same pixels, moved up by the scroll.
            guard let after = host.lastImage.map(_followPixels) else { XCTFail("no image"); return }
            XCTAssertEqual(before.width, after.width)
            let scale = CGFloat(before.height) / whole.height
            let shift = Int((abs(delta) * scale).rounded())
            // Image rows are top first; the window's y is bottom-up.
            let clipTop = Int(((whole.height - clipInWindow.maxY) * scale).rounded())
            let clipBottom = Int(((whole.height - clipInWindow.minY) * scale).rounded())
            let x0 = Int((clipInWindow.minX * scale).rounded()), x1 = Int(((clipInWindow.maxX - 24) * scale).rounded())
            var differing = 0, compared = 0
            // Rows that stay on screen: after the scroll they are `shift` rows higher.
            for y in (clipTop + shift + 4)..<(clipBottom - shift - 4) where y - shift >= 0 {
                let a = (y * before.width + x0) * 4, b = ((y - shift) * after.width + x0) * 4
                let n = (x1 - x0) * 4
                if !before.bytes[a..<(a + n)].elementsEqual(after.bytes[b..<(b + n)]) { differing += 1 }
                compared += 1
            }
            XCTAssertGreaterThan(compared, 100)
            XCTAssertEqual(differing, 0, "the rows that stayed in view keep their pixels, \(shift) px higher (\(differing) of \(compared) rows differ)")

            // And the window shows what a full repaint draws: nothing the copy moved is stale.
            window._setNeedsDisplayWhole()
            host.displayIfNeeded()
            guard let full = host.lastImage.map(_followPixels) else { XCTFail("no image"); return }
            var stale: [Int] = []
            for y in 0..<full.height {
                let a = y * full.width * 4, n = full.width * 4
                if !after.bytes[a..<(a + n)].elementsEqual(full.bytes[a..<(a + n)]) { stale.append(y) }
            }
            XCTAssertTrue(stale.isEmpty, "the scrolled frame matches a full repaint; differing pixel rows \(stale.prefix(8))\(stale.count > 8 ? "… (\(stale.count))" : "")")
        }
    }
}
