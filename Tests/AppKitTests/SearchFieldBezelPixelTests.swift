// A search field is a capsule over whatever is behind it: on macOS the toolbar's grey
// shows past the rounded ends. Checked in pixels, because a Windows run drew the
// capsule's outline on a white square (the cell filled its background colour over the
// whole frame before stroking the rounded bezel).

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor private func _searchPixelViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_searchPixelViews) }

/// A view filled with the toolbar band's grey.
@MainActor private final class _GreyBand: NSView {
    static let grey: CGFloat = 0.914
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: _GreyBand.grey, alpha: 1).setFill()
        NSBezierPath.fill(bounds)
    }
}

final class SearchFieldBezelPixelTests: XCTestCase, @unchecked Sendable {
    private typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

    @MainActor private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> RGB {
        let c = rep.colorAt(x: x, y: y) ?? .black
        let rgb = c.usingColorSpace(.deviceRGB) ?? c
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    private func close(_ a: RGB, _ b: RGB, _ tolerance: CGFloat = 0.02) -> Bool {
        abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
    }

    /// Checks a field's frame (in `root`'s coordinates) in a rendering of `root`: the
    /// corners and the pixels a point inside them are `outside`, the centre column is the
    /// capsule's fill (lighter than the band) and the left edge's midpoint is the outline.
    @MainActor private func assertCapsule(_ frame: NSRect, in root: NSView, outside: RGB, _ what: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return XCTFail("no bitmap", file: file, line: line) }
        root.cacheDisplay(in: root.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / root.bounds.width
        // Bitmap rows run top-down; the frame is in the root's (possibly unflipped) space.
        let top = root.isFlipped ? frame.minY : root.bounds.height - frame.maxY
        let x0 = Int((frame.minX * scale).rounded()), x1 = Int((frame.maxX * scale).rounded()) - 1
        let y0 = Int((top * scale).rounded()), y1 = Int(((top + frame.height) * scale).rounded()) - 1
        let inset = Int(scale.rounded())
        let corners = [(x0, y0), (x1, y0), (x0, y1), (x1, y1),
                       (x0 + inset, y0 + inset), (x1 - inset, y0 + inset), (x0 + inset, y1 - inset), (x1 - inset, y1 - inset)]
        for (x, y) in corners {
            let p = pixel(rep, x, y)
            XCTAssertTrue(close(p, outside), "\(what): (\(x), \(y)) outside the capsule shows the band \(outside), not \(p)", file: file, line: line)
        }
        let midY = (y0 + y1) / 2
        // The centre column, 3 points below the top: inside the capsule but clear of the
        // placeholder (centred) and the typed text, which cover the exact centre.
        let fill = pixel(rep, (x0 + x1) / 2, y0 + Int((3 * scale).rounded()))
        XCTAssertGreaterThan(fill.r, outside.r + 0.03, "\(what): the capsule's fill is lighter than the band: \(fill)", file: file, line: line)
        let edge = pixel(rep, x0, midY)
        XCTAssertFalse(close(edge, outside, 0.01), "\(what): the left end's midpoint is the outline, not the band: \(edge)", file: file, line: line)
        XCTAssertFalse(close(edge, fill, 0.01), "\(what): the left end's midpoint is the outline, not the fill: \(edge)", file: file, line: line)
    }

    func testSearchFieldIsACapsuleOverTheBand() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 60), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            let band = _GreyBand(frame: NSRect(x: 0, y: 0, width: 260, height: 60))
            window.contentView = band
            let field = NSSearchField(frame: NSRect(x: 20, y: 16, width: 220, height: 28))
            field.placeholderString = "Search transcript"
            band.addSubview(field)
            window.makeKeyAndOrderFront(nil)
            (Platform.backend as! HostBackend).drain()
            defer { window.close() }
            let g = _GreyBand.grey
            assertCapsule(field.frame, in: band, outside: (g, g, g), "idle")

            // Focused and holding text: the field editor stays inside the capsule.
            XCTAssertTrue(window.makeFirstResponder(field))
            guard let editor = field.currentEditor() as? NSTextView else { return XCTFail("no field editor") }
            editor.insertText("cue", replacementRange: editor.selectedRange())
            (Platform.backend as! HostBackend).drain()
            XCTAssertEqual(editor.string, "cue")
            let editorFrame = band.convert(editor.bounds, from: editor)
            XCTAssertTrue(field.frame.insetBy(dx: field.frame.height / 2 - 4, dy: 0).contains(editorFrame), "the editor sits between the rounded ends: \(editorFrame)")
            assertCapsule(field.frame, in: band, outside: (g, g, g), "focused with text")
        }
    }

    func testSearchableToolbarItemIsACapsuleOverTheToolbar() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Screen: View {
                @State var text = ""
                var body: some View {
                    Text("Body").searchable(text: $text, placement: .toolbar, prompt: "Search transcript")
                }
            }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: Screen())
            hosting.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            (Platform.backend as! HostBackend).drain()
            defer { window.close() }
            guard let bandView = window._toolbarView else { return XCTFail("no toolbar band") }
            bandView.layoutSubtreeIfNeeded()
            guard let field = _searchPixelViews(bandView).compactMap({ $0 as? NSSearchField }).first else { return XCTFail("no search field in the toolbar") }
            let frame = bandView.convert(field.bounds, from: field)
            XCTAssertGreaterThan(frame.width, 100, "the toolbar's search field has its width: \(frame)")

            // The band's own colour, sampled just left of the field.
            guard let rep = bandView.bitmapImageRepForCachingDisplay(in: bandView.bounds) else { return XCTFail("no bitmap") }
            bandView.cacheDisplay(in: bandView.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / bandView.bounds.width
            let midY = bandView.isFlipped ? frame.midY : bandView.bounds.height - frame.midY
            let outside = pixel(rep, Int(((frame.minX - 3) * scale).rounded()), Int((midY * scale).rounded()))
            XCTAssertLessThan(outside.r, 0.97, "the toolbar band is grey: \(outside)")
            assertCapsule(frame, in: bandView, outside: outside, "toolbar idle")

            XCTAssertTrue(window.makeFirstResponder(field))
            guard let editor = field.currentEditor() as? NSTextView else { return XCTFail("no field editor") }
            editor.insertText("cue", replacementRange: editor.selectedRange())
            (Platform.backend as! HostBackend).drain()
            assertCapsule(frame, in: bandView, outside: outside, "toolbar focused with text")
        }
    }
}
