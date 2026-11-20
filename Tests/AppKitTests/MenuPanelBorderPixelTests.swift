// A menu panel's border is one light hairline that follows the panel's rounded outline:
// its straight runs span the full edge between the corner arcs, and the arcs are drawn.
// A Windows run saw a dark rectangular stroke whose corners the system's rounding cut off,
// leaving "dark lines on each side that stop short of the ends".

import XCTest
@testable import AppKit

final class MenuPanelBorderPixelTests: XCTestCase, @unchecked Sendable {
    @MainActor private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        let c = rep.colorAt(x: x, y: y) ?? .black
        let rgb = c.usingColorSpace(.deviceRGB) ?? c
        // Composited over white for a translucent border pixel.
        return rgb.redComponent * rgb.alphaComponent + (1 - rgb.alphaComponent)
    }

    func testMenuPanelBorderIsOneLightRoundedHairline() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let saved = _NSMenuFrameView.cornerRadius
            _NSMenuFrameView.cornerRadius = 8          // as Windows rounds the panel
            defer { _NSMenuFrameView.cornerRadius = saved }
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.makeKeyAndOrderFront(nil)
            let menu = NSMenu(title: "Colours")
            for t in ["Red", "Green", "Blue", "Yellow"] { menu.addItem(withTitle: t, action: nil, keyEquivalent: "") }
            let click = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 50, y: 150), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            defer { menu.cancelTracking(); w.close() }
            guard let mw = NSApplication.shared.windows.compactMap({ $0 as? _NSMenuWindow }).first(where: { $0.isVisible }), let content = mw.contentView else { return XCTFail("no menu window") }
            content.layoutSubtreeIfNeeded()
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return XCTFail("no bitmap") }
            content.cacheDisplay(in: content.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / content.bounds.width
            let width = rep.pixelsWide, height = rep.pixelsHigh
            let radius = Int(8 * scale)
            let fill = pixel(rep, width / 2, height / 2)
            let border = pixel(rep, 0, height / 2)
            XCTAssertLessThan(border, fill - 0.08, "the left edge carries a border darker than the fill (border \(border), fill \(fill))")
            XCTAssertGreaterThan(border, 0.55, "the border is light, not the old 60% black: \(border)")
            // The straight run spans the whole edge between the arcs, on every side.
            var gaps: [String] = []
            for y in (radius + 1)..<(height - radius - 1) {
                if pixel(rep, 0, y) > fill - 0.08 { gaps.append("left y=\(y)") }
                if pixel(rep, width - 1, y) > fill - 0.08 { gaps.append("right y=\(y)") }
            }
            for x in (radius + 1)..<(width - radius - 1) {
                if pixel(rep, x, 0) > fill - 0.08 { gaps.append("top x=\(x)") }
                if pixel(rep, x, height - 1) > fill - 0.08 { gaps.append("bottom x=\(x)") }
            }
            XCTAssertTrue(gaps.isEmpty, "the border has gaps: \(gaps.prefix(8))")
            // The corner carries an arc of the border: on the diagonal at the arc, a pixel
            // darker than the fill.
            let d = Int(Double(radius) * (1 - 0.7071))
            let cornerArc = [pixel(rep, d, d), pixel(rep, d + 1, d + 1), pixel(rep, d, d + 1), pixel(rep, d + 1, d)].min()!
            XCTAssertLessThan(cornerArc, fill - 0.04, "the top-left corner has an arc of the border (min \(cornerArc), fill \(fill))")
            // Nothing darker than the border anywhere along the edges.
            let darkest = min((0..<height).map { pixel(rep, 0, $0) }.min()!, (0..<width).map { pixel(rep, $0, 0) }.min()!)
            XCTAssertGreaterThan(darkest, 0.55, "no edge pixel is darker than the border colour: \(darkest)")
        }
    }
}
