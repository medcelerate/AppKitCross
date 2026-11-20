// A pop-up button's bezel is one rounded rect: filled, then a single light hairline
// stroke of the whole path. A Windows run (light theme) showed dark lines down each side
// that stopped short of the corners: the shared push-button bezel stroked with
// `separatorColor.withAlphaComponent(0.6)`, which replaces separator's 0.1 alpha, so the
// border was 60% black and only the straight runs between the 6-point arcs looked solid.

import XCTest
@testable import AppKit

final class PopUpBezelPixelTests: XCTestCase, @unchecked Sendable {
    private typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

    /// The pixel composited over white (the bitmap is transparent outside the bezel).
    @MainActor private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> RGB {
        let c = rep.colorAt(x: x, y: y) ?? .clear
        let rgb = c.usingColorSpace(.deviceRGB) ?? c
        let a = rgb.alphaComponent
        return (rgb.redComponent * a + (1 - a), rgb.greenComponent * a + (1 - a), rgb.blueComponent * a + (1 - a))
    }
    private func over(_ top: RGB, _ alpha: CGFloat, _ bottom: RGB) -> RGB {
        (top.r * alpha + bottom.r * (1 - alpha), top.g * alpha + bottom.g * (1 - alpha), top.b * alpha + bottom.b * (1 - alpha))
    }
    private func diff(_ a: RGB, _ b: RGB) -> CGFloat { max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)) }
    private func fmt(_ c: RGB) -> String { String(format: "(%.2f %.2f %.2f)", c.r, c.g, c.b) }

    private enum Variant: String, CaseIterable { case normal, pressed, disabled, dark }

    @MainActor private func check(_ variant: Variant) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        window.contentView = content
        let popUp = NSPopUpButton(frame: NSRect(x: 20, y: 18, width: 160, height: 24), pullsDown: false)
        popUp.addItems(withTitles: ["Medium", "Large"])
        content.addSubview(popUp)
        switch variant {
        case .normal: break
        case .pressed: popUp.cell?.isHighlighted = true
        case .disabled: popUp.isEnabled = false
        case .dark: popUp.appearance = NSAppearance(named: .darkAqua)
        }
        defer { window.close() }
        guard let rep = popUp.bitmapImageRepForCachingDisplay(in: popUp.bounds) else { return XCTFail("no bitmap") }
        popUp.cacheDisplay(in: popUp.bounds, to: rep)
        let w = rep.pixelsWide, h = rep.pixelsHigh
        let scale = CGFloat(w) / popUp.bounds.width
        let radius = Int((NSPopUpButtonCell._bezelCornerRadius * scale).rounded(.up))
        let inset = Int((2 * scale).rounded())   // a fill sample just inside the border
        // The border colour the cell strokes, per appearance.
        let border: RGB = variant == .dark ? (1, 1, 1) : (0, 0, 0)
        let borderAlpha: CGFloat = variant == .dark ? 0.15 : 0.2
        let tolerance: CGFloat = 0.04

        // (edge pixel, the fill beside it) along each side, between the corner arcs.
        var sides: [(name: String, samples: [(at: String, edge: RGB, fill: RGB)])] = []
        let ys = radius..<(h - radius), xs = radius..<(w - radius)
        sides.append(("left", ys.map { ("y=\($0)", pixel(rep, 0, $0), pixel(rep, inset, $0)) }))
        sides.append(("right", ys.map { ("y=\($0)", pixel(rep, w - 1, $0), pixel(rep, w - 1 - inset, $0)) }))
        sides.append(("top", xs.map { ("x=\($0)", pixel(rep, $0, 0), pixel(rep, $0, inset)) }))
        sides.append(("bottom", xs.map { ("x=\($0)", pixel(rep, $0, h - 1), pixel(rep, $0, h - 1 - inset)) }))

        for side in sides {
            let dump = side.samples.map { "\($0.at) edge \(fmt($0.edge)) fill \(fmt($0.fill))" }.joined(separator: "\n")
            var tooDark: [String] = [], gaps: [String] = []
            for (i, s) in side.samples.enumerated() {
                let expected = over(border, borderAlpha, s.fill)
                let contrast = diff(expected, s.fill)
                // (a) nothing on the edge is darker (or stronger) than the border over the fill.
                if diff(s.edge, expected) > tolerance { tooDark.append(s.at) }
                // (b, c) the border runs the full length between the arcs: no gap.
                if i > 0 && i < side.samples.count - 1 && diff(s.edge, s.fill) < contrast * 0.6 { gaps.append(s.at) }
            }
            XCTAssertTrue(tooDark.isEmpty, "\(variant) \(side.name) edge differs from the border colour at \(tooDark):\n\(dump)")
            XCTAssertTrue(gaps.isEmpty, "\(variant) \(side.name) border has a gap at \(gaps):\n\(dump)")
        }
    }

    func testPopUpBezelIsOneLightHairlineInEveryState() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for v in Variant.allCases { check(v) }
        }
    }
}
