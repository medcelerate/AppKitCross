// A grouped Form draws what the screenshots of macOS's Settings show: a light page
// (the window background) with a white card per Section. Checked in pixels, because a
// Windows run found the cards invisible: the card's white sat on a white page.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor private func _pixelTestViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_pixelTestViews) }

final class SwiftUIGroupedFormPixelTests: XCTestCase, @unchecked Sendable {
    @MainActor private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let c = rep.colorAt(x: x, y: y) ?? .black
        let rgb = c.usingColorSpace(.deviceRGB) ?? c
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    func testGroupedFormPaintsAGreyPageAndWhiteCards() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Panel: View {
                var body: some View {
                    Form {
                        Section("Reading") {
                            Toggle("Auto-scroll to newest", isOn: .constant(true))
                            Toggle("Newest line first", isOn: .constant(false))
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: Panel())
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return XCTFail("no bitmap") }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
            // The page margin (inside the form's 16-point padding) is the window background,
            // not white; the card's interior, past the header, is the control background.
            let page = pixel(rep, Int(6 * scale), Int(6 * scale))
            // The card's interior: the first toggle's row, at its trailing padding (empty).
            // A grouped form's toggle is a switch row (ADR-0051).
            guard let toggle = _pixelTestViews(hosting).first(where: { $0 is _SwiftUISwitchRow }) else { return XCTFail("no toggle") }
            let row = hosting.convert(toggle.bounds, from: toggle)
            // (The row is a switch row across the card: its middle is empty, between the
            // label and the switch at the trailing edge.)
            let cardX = row.midX, cardY = row.midY
            let card = pixel(rep, Int(cardX * scale), Int(cardY * scale))
            XCTAssertLessThan(page.r, 0.98, "the page is not white: \(page)")
            XCTAssertGreaterThan(page.r, 0.8, "the page is a light grey: \(page)")
            XCTAssertGreaterThan(card.r, 0.98, "the card is white: \(card)")
            XCTAssertGreaterThan(card.r - page.r, 0.03, "the card stands out from the page")
            window.close()
        }
    }
}
