// Sidebar rows as Sibyl draws them, checked in pixels: a custom row (an icon in a fixed slot
// beside a two-line stack, tagged under a context menu) takes the rounded selection like a
// Label row, and a symbol in an 18-point frame beside two lines draws whole and centred.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> (NSWindow, NSHostingView<V>) {
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
private func text(_ s: String, in v: NSView) -> _TextView? { allViews(v).compactMap { $0 as? _TextView }.first { $0.storage.string == s } }
@MainActor
private func frame(_ v: NSView, in root: NSView) -> CGRect { v.convert(v.bounds, to: root) }

/// The view drawn into a bitmap, and its pixel scale (pixels per point).
@MainActor
private func render(_ v: NSView) -> (rep: NSBitmapImageRep, scale: Int) {
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    return (rep, max(1, rep.pixelsWide / max(1, Int(v.bounds.width))))
}

private func close(_ a: NSColor, _ b: NSColor, _ tolerance: CGFloat = 0.06) -> Bool {
    guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
    return abs(a.redComponent - b.redComponent) < tolerance && abs(a.greenComponent - b.greenComponent) < tolerance
        && abs(a.blueComponent - b.blueComponent) < tolerance
}

private enum Item: Hashable { case combined, matrix, channel(Int) }
private struct Channel: Identifiable { let id: Int; let name: String; let symbol: String; let tint: Color }

/// Sibyl's `ChannelRow`: a tinted symbol in an 18-point slot beside the name over a meter.
private struct ChannelRow: View {
    let channel: Channel
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: channel.symbol)
                .foregroundStyle(channel.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).lineLimit(1)
                Capsule().fill(Color.gray.opacity(0.3)).frame(height: 4)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Sibyl's sidebar: a section of Labels and, per group, a section of channel rows tagged
/// below a context menu in a `ForEach` with `onMove`.
private struct Sidebar: View {
    @Binding var selection: Item?
    let channels = [Channel(id: 1, name: "Production", symbol: "headphones", tint: .blue),
                    Channel(id: 2, name: "Lighting", symbol: "lightbulb", tint: .orange),
                    Channel(id: 3, name: "Channel 3", symbol: "person.wave.2", tint: .orange)]
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Views") {
                    Label("Combined Log", systemImage: "list.bullet.rectangle").tag(Item.combined)
                    Label("Matrix", systemImage: "square.grid.3x3").tag(Item.matrix)
                }
                ForEach([("Channels", channels)], id: \.0) { title, channels in
                    Section(title) {
                        ForEach(channels) { channel in
                            ChannelRow(channel: channel)
                                .tag(Item.channel(channel.id))
                                .contextMenu { Button("Mute") { } }
                        }
                        .onMove { _, _ in }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 250, max: 420)
        } detail: {
            Text("detail")
        }
    }
}

@MainActor
private final class SelectionBox { var value: Item? = .combined }

final class SidebarRowPixelTests: XCTestCase, @unchecked Sendable {
    func testACustomTaggedRowTakesTheRoundedSelection() {
        MainActor.assumeIsolated {
            let box = SelectionBox()
            let binding = Binding<Item?>(get: { box.value }, set: { box.value = $0 })
            var (w, h) = host(Sidebar(selection: binding), width: 900, height: 500)
            box.value = .channel(1)
            w.close()
            (w, h) = host(Sidebar(selection: binding), width: 900, height: 500)
            guard let list = allViews(h).compactMap({ $0 as? _ListView }).first, let t = text("Production", in: h) else { return XCTFail("no list") }
            XCTAssertEqual(list.selectedRows.count, 1, "the channel row is selected")
            guard let index = list.selectedRows.first else { return }
            let row = list.convert(list.rowFrames[index], to: h)
            XCTAssertTrue(row.contains(CGPoint(x: frame(t, in: h).midX, y: frame(t, in: h).midY)), "the selected row is the channel's")
            // The rounded highlight at that row: the accent colour inside it, left of the icon.
            let (rep, s) = render(h)
            let probe = rep.colorAt(x: 13 * s, y: Int(row.midY) * s)!
            XCTAssertTrue(close(probe, NSColor.selectedContentBackgroundColor), "the accent selection is drawn at the row, got \(probe)")
            XCTAssertTrue(t.isInSelectedRow, "white text on a key window's selection")
            // An inactive window: the grey selection, and the title keeps the label colour.
            w.resignKey()
            XCTAssertFalse(list.emphasized)
            XCTAssertFalse(t.isInSelectedRow)
            let (grey, gs) = render(h)
            let g = grey.colorAt(x: 13 * gs, y: Int(row.midY) * gs)!
            XCTAssertTrue(close(g, NSColor.unemphasizedSelectedContentBackgroundColor), "the unemphasized selection is drawn, got \(g)")
            w.close()
        }
    }

    func testClickingACustomRowSelectsItsTag() {
        MainActor.assumeIsolated {
            let box = SelectionBox()
            let binding = Binding<Item?>(get: { box.value }, set: { box.value = $0 })
            let (w, h) = host(Sidebar(selection: binding), width: 900, height: 500)
            guard let list = allViews(h).compactMap({ $0 as? _ListView }).first, let t = text("Lighting", in: h) else { return XCTFail("no list") }
            let p = frame(t, in: h)
            let inList = list.convert(CGPoint(x: p.midX, y: p.midY), from: h)
            guard let i = list.row(at: inList) else { return XCTFail("no row under the title") }
            list.onClick?(i, [])
            XCTAssertEqual(box.value, .channel(2), "the row's tag is the selection, through its context menu")
            w.close()
        }
    }

    func testASymbolInAnEighteenPointSlotDrawsWholeAndCentred() {
        MainActor.assumeIsolated {
            for symbol in ["headphones", "lightbulb", "person.wave.2"] {
                let view = HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(Color.blue).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Production").lineLimit(1)
                        Capsule().fill(Color.gray.opacity(0.3)).frame(width: 120, height: 4)
                    }
                }
                .padding(10)
                .background(Color.white)
                let (w, h) = host(view, width: 240, height: 80)
                guard let image = allViews(h).compactMap({ $0 as? _SymbolImageView }).first,
                      let title = text("Production", in: h) else { return XCTFail("\(symbol): no image") }
                let imageFrame = frame(image, in: h)
                let (rep, s) = render(h)
                // The glyph's bounding box: pixels clearly bluer than the white background.
                var minY = Int.max, maxY = Int.min, minX = Int.max, maxX = Int.min
                for y in 0..<rep.pixelsHigh {
                    for x in 0..<min(rep.pixelsWide, Int(imageFrame.maxX + 6) * s) {
                        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        if c.blueComponent - c.redComponent > 0.25 {
                            minY = min(minY, y); maxY = max(maxY, y); minX = min(minX, x); maxX = max(maxX, x)
                        }
                    }
                }
                guard minY <= maxY else { w.close(); return XCTFail("\(symbol): nothing drawn") }
                let glyph = CGRect(x: CGFloat(minX) / CGFloat(s), y: CGFloat(minY) / CGFloat(s),
                                   width: CGFloat(maxX - minX + 1) / CGFloat(s), height: CGFloat(maxY - minY + 1) / CGFloat(s))
                XCTAssertGreaterThan(glyph.height, 9, "\(symbol): the whole glyph shows, not a part of it (\(glyph))")
                XCTAssertGreaterThanOrEqual(glyph.minY, imageFrame.minY + 1 - 0.01, "\(symbol): a margin above the glyph (\(glyph) in \(imageFrame))")
                XCTAssertLessThanOrEqual(glyph.maxY, imageFrame.maxY - 1 + 0.01, "\(symbol): a margin below the glyph (\(glyph) in \(imageFrame))")
                XCTAssertGreaterThanOrEqual(glyph.minX, imageFrame.minX - 0.01)
                XCTAssertLessThanOrEqual(glyph.maxX, imageFrame.maxX + 0.01)
                XCTAssertEqual(glyph.midY, imageFrame.midY, accuracy: 1.5, "\(symbol): the glyph is centred in its frame")
                // And on the HStack: the two-line stack (title, 2 points, a 4-point meter) is
                // the taller item, so the row runs from the title's top to the meter's bottom.
                let t = frame(title, in: h)
                let stackMid = (t.minY + t.maxY + 2 + 4) / 2
                XCTAssertEqual(imageFrame.midY, stackMid, accuracy: 1, "\(symbol): the image is centred on the HStack")
                XCTAssertEqual(glyph.midY, stackMid, accuracy: 1.5, "\(symbol): the glyph is centred on the HStack")
                w.close()
            }
        }
    }
}
