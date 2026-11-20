// Sibyl's inspector on the PC, round 11: a narrowed button's title ends in an ellipsis, a
// picker menu's colour swatches keep their colour (only symbols are templates), and a
// grouped form row wraps its label before the pop-up's title truncates.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 320, height: CGFloat = 400) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

@MainActor
private func bitmap(_ v: NSView) -> (NSBitmapImageRep, CGFloat)? {
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
    v.cacheDisplay(in: v.bounds, to: rep)
    return (rep, CGFloat(rep.pixelsWide) / max(1, v.bounds.width))
}

final class SibylCosmeticRound11Tests: XCTestCase, @unchecked Sendable {
    // MARK: 1. Truncated titles end in an ellipsis

    func testNarrowBorderedButtonTitleEndsInEllipsis() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            let b = NSButton(title: "Clear This Channel's Transcript", target: nil, action: nil)
            b.bezelStyle = .rounded
            b.frame = NSRect(x: 10, y: 20, width: 120, height: 24)
            w.contentView!.addSubview(b)
            XCTAssertGreaterThan(b.intrinsicContentSize.width, 120, "the title does not fit")
            guard let cell = b.cell as? NSButtonCell, let (rep, scale) = bitmap(b) else { return XCTFail("no cell") }
            let drawn = cell._lastDrawnTitle ?? ""
            XCTAssertTrue(drawn.hasSuffix("…"), "the cut title ends in an ellipsis: \(drawn)")
            XCTAssertTrue("Clear This Channel's Transcript".hasPrefix(String(drawn.dropLast()).trimmingCharacters(in: .whitespaces)))
            XCTAssertLessThanOrEqual(drawn.size(withAttributes: [.font: cell._effectiveFont]).width, 120 - 12 + 0.5, "the drawn text fits inside the bezel's padding")
            // A title that fits is drawn as it is.
            b.title = "Clear"
            _ = bitmap(b)
            XCTAssertEqual(cell._lastDrawnTitle, "Clear")
            b.title = "Clear This Channel's Transcript"
            // Ink: the ellipsis is drawn right of the last whole word, near the bezel's end.
            var lastInk = -1
            let midY = Int(b.bounds.midY * scale)
            for xPx in 0..<rep.pixelsWide {
                for dy in -4...4 {
                    guard let c = rep.colorAt(x: xPx, y: midY + Int(CGFloat(dy) * scale))?.usingColorSpace(.deviceRGB) else { continue }
                    if (c.redComponent + c.greenComponent + c.blueComponent) / 3 < 0.45, c.alphaComponent > 0.5 { lastInk = max(lastInk, xPx) }
                }
            }
            let prefix = String(drawn.dropLast())
            let prefixWidth = prefix.size(withAttributes: [.font: cell._effectiveFont]).width
            let textStart = (b.bounds.width - drawn.size(withAttributes: [.font: cell._effectiveFont]).width) / 2
            XCTAssertGreaterThan(CGFloat(lastInk) / scale, textStart + prefixWidth + 1, "ink right of the last word (the ellipsis)")
            w.close()
        }
    }

    func testTruncatingTextHelperCutsAtACharacterAndAppendsEllipsis() {
        MainActor.assumeIsolated {
            let font = NSFont.systemFont(ofSize: 13)
            let text = "1 — Shure ULX-D Receiver Channel One Left"
            let full = text.size(withAttributes: [.font: font]).width
            for width in stride(from: CGFloat(30), to: full, by: 17) {
                let cut = NSCell._truncatedTail(text, attributes: [.font: font], width: width)
                XCTAssertTrue(cut.hasSuffix("…"), "\(width): \(cut)")
                XCTAssertLessThanOrEqual(cut.size(withAttributes: [.font: font]).width, width + 0.5, "\(width): \(cut)")
            }
            XCTAssertEqual(NSCell._truncatedTail(text, attributes: [.font: font], width: full + 1), text)
        }
    }

    // MARK: 2. Menu swatches keep their colour

    func testPickerMenuSwatchesKeepTheirColourAndSymbolsAreTemplates() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                @State var tint = 0
                @State var sibylTint = 0
                @State var symbol = "mic"
                var body: some View {
                    Form {
                        Picker("Colour", selection: $tint) {
                            Label { Text("Rose") } icon: { Circle().fill(Color.red) }.tag(0)
                            Label { Text("Slate") } icon: { Circle().fill(Color.blue) }.tag(1)
                        }
                        Picker("Tint", selection: $sibylTint) {
                            Label { Text("Rose").foregroundStyle(Color.red) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color.red) }.tag(0)
                            Label { Text("Slate").foregroundStyle(Color.blue) } icon: { Image(systemName: "circle.fill").foregroundStyle(Color.blue) }.tag(1)
                        }
                        Picker("Icon", selection: $symbol) {
                            Label("Headphones", systemImage: "headphones").tag("mic")
                            Label("Star", systemImage: "star").tag("star")
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            let (w, h) = host(Probe(), width: 360, height: 300)
            let popUps = allViews(h).compactMap { $0 as? NSPopUpButton }
            XCTAssertEqual(popUps.count, 3)
            guard popUps.count == 3, let menu = popUps[0].menu else { return w.close() }
            for p in popUps.prefix(2) {
                for item in p.itemArray {
                    XCTAssertNotNil(item.image, "\(item.title) has a swatch")
                    XCTAssertEqual(item.image?.isTemplate, false, "\(item.title)'s swatch is drawn in its own colour")
                }
            }
            for item in popUps[2].itemArray { XCTAssertEqual(item.image?.isTemplate, true, "a symbol item (\(item.title)) is a template") }

            // Pixels of the open menu: the Rose row's swatch is red, Slate's blue.
            @MainActor func swatchColours(_ menu: NSMenu) -> [NSColor] {
                let layout = _NSMenuLayout(menu: menu, font: NSFont.menuFont(ofSize: 0))
                let view = _NSMenuView(menu: menu, layout: layout)
                let win = NSWindow(contentRect: NSRect(origin: .zero, size: layout.size), styleMask: [.borderless], backing: .buffered, defer: false)
                win.contentView!.addSubview(view)
                defer { win.close() }
                guard let (rep, scale) = bitmap(view) else { return [] }
                return layout.rows.map { row in
                    let cx = layout.textLeft + _NSMenuLayout.imageSize / 2
                    // Flipped view; the bitmap's rows run top-down too.
                    let c = rep.colorAt(x: Int(cx * scale), y: Int(row.frame.midY * scale))?.usingColorSpace(.deviceRGB) ?? .black
                    return c
                }
            }
            for m in [menu, popUps[1].menu!] {
                let colours = swatchColours(m)
                XCTAssertEqual(colours.count, 2)
                guard colours.count == 2 else { continue }
                XCTAssertGreaterThan(colours[0].redComponent, 0.7, "Rose's swatch is red: \(colours[0])")
                XCTAssertLessThan(colours[0].blueComponent, 0.5, "Rose's swatch is red: \(colours[0])")
                XCTAssertGreaterThan(colours[1].blueComponent, 0.7, "Slate's swatch is blue: \(colours[1])")
                XCTAssertLessThan(colours[1].redComponent, 0.5, "Slate's swatch is blue: \(colours[1])")
            }
            w.close()
        }
    }

    // MARK: 3. A grouped row wraps its label before the pop-up truncates

    private struct ChannelRow: View {
        let label: String
        @State var channel = 0
        var body: some View {
            Form {
                Section("Input") {
                    Picker(label, selection: $channel) {
                        Text("1 — Input 1").tag(0)
                        Text("2 — Input 2").tag(1)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Sibyl's Hardware Channel row in the 210-point inspector: the label wraps to its words
    /// ("Hardware" / "Channel") and the pop-up takes every point the row has left; a
    /// title-only item reserves no image slot.
    func testGroupedFormRowWrapsTheLabelAndGivesThePopUpTheRest() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, h) = host(ChannelRow(label: "Hardware Channel"), width: 210, height: 300)
            guard let popUp = allViews(h).compactMap({ $0 as? NSPopUpButton }).first,
                  let cell = popUp.cell as? NSPopUpButtonCell,
                  let label = allViews(h).compactMap({ $0 as? _TextView }).first(where: { $0.storage.string == "Hardware Channel" }) else { return XCTFail("no row") }
            XCTAssertNil(popUp.selectedItem?.image, "a title-only item has no image")
            let font = cell._effectiveFont
            let title = max("1 — Input 1".size(withAttributes: [.font: font]).width, "2 — Input 2".size(withAttributes: [.font: font]).width)
            XCTAssertEqual(cell.cellSize.width, (title + NSPopUpButtonCell.titleInset + NSPopUpButtonCell.arrowAreaWidth).rounded(.up), accuracy: 0.5, "no image slot in the face's width")
            let lf = label.convert(label.bounds, to: nil), pf = popUp.convert(popUp.bounds, to: nil)
            let one = "Hardware".size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
            XCTAssertGreaterThan(lf.height, one.height * 1.5, "the label wraps to two lines: \(lf)")
            XCTAssertLessThanOrEqual(lf.width, one.width + 2, "the label is down to its widest word: \(lf)")
            XCTAssertLessThanOrEqual(lf.maxX + 8, pf.minX + 0.5, "the label stays left of the pop-up")
            _ = bitmap(popUp)
            let drawn = cell._lastDrawnTitle ?? ""
            if popUp.frame.width >= cell.cellSize.width - 0.5 {
                XCTAssertEqual(drawn, "1 — Input 1", "the pop-up's title is drawn whole")
            } else {
                XCTAssertTrue(drawn.hasSuffix("…"), "a title that does not fit ends in an ellipsis: \(drawn)")
            }
            w.close()
        }
    }

    /// Where the wrapped label leaves room for the whole pop-up, the pop-up keeps its full
    /// width and draws its title whole. An HStack's equal shares gave a three-word label
    /// half the row ("Hardware Input" / "Channel") and truncated the pop-up.
    func testGroupedFormRowKeepsThePopUpWholeWhenTheWrappedLabelLeavesRoom() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            // The row width comes from the metrics in use, not the Mac's: a wide host measures the
            // row's insets and the pop-up's need, then the row is hosted just wide enough for the
            // label's widest word, the gap and the whole pop-up (Cairo's words are wider than CoreText's).
            let (wide, hw) = host(ChannelRow(label: "Hardware Input Channel"), width: 600, height: 300)
            guard let wp = allViews(hw).compactMap({ $0 as? NSPopUpButton }).first, let wc = wp.cell as? NSPopUpButtonCell,
                  let wl = allViews(hw).compactMap({ $0 as? _TextView }).first(where: { $0.storage.string == "Hardware Input Channel" }) else { return XCTFail("no row") }
            let insets = 600 - (wp.convert(wp.bounds, to: nil).maxX - wl.convert(wl.bounds, to: nil).minX)
            let word = ["Hardware", "Input", "Channel"].map { $0.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width }.max()!
            let width = (insets + word + 8 + wc.cellSize.width + 2).rounded(.up)
            wide.close()
            let (w, h) = host(ChannelRow(label: "Hardware Input Channel"), width: width, height: 300)
            guard let popUp = allViews(h).compactMap({ $0 as? NSPopUpButton }).first,
                  let cell = popUp.cell as? NSPopUpButtonCell,
                  let label = allViews(h).compactMap({ $0 as? _TextView }).first(where: { $0.storage.string == "Hardware Input Channel" }) else { return XCTFail("no row") }
            XCTAssertGreaterThanOrEqual(popUp.frame.width, cell.cellSize.width - 0.5, "the pop-up keeps the width its title needs")
            _ = bitmap(popUp)
            XCTAssertEqual(cell._lastDrawnTitle, "1 — Input 1", "the pop-up's title is drawn whole")
            let one = "Hardware".size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).height
            XCTAssertGreaterThan(label.frame.height, one * 1.5, "the label wraps instead")
            let lf = label.convert(label.bounds, to: nil), pf = popUp.convert(popUp.bounds, to: nil)
            XCTAssertLessThanOrEqual(lf.maxX, pf.minX + 0.5)
            w.close()
        }
    }

    /// A row with room for both is laid out as before: the label on one line, the pop-up at
    /// its natural width at the trailing edge.
    func testGroupedFormRowWithRoomKeepsBothNatural() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (w, h) = host(ChannelRow(label: "Hardware Channel"), width: 360, height: 300)
            guard let popUp = allViews(h).compactMap({ $0 as? NSPopUpButton }).first,
                  let cell = popUp.cell as? NSPopUpButtonCell,
                  let label = allViews(h).compactMap({ $0 as? _TextView }).first(where: { $0.storage.string == "Hardware Channel" }) else { return XCTFail("no row") }
            XCTAssertEqual(popUp.frame.width, cell.cellSize.width, accuracy: 0.5)
            let one = "Hardware".size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).height
            XCTAssertLessThan(label.frame.height, one * 1.5, "one line")
            w.close()
        }
    }
}
