// Liquid Glass (ADR-0052), checked in pixels: a glass surface shows the content beneath it
// blurred and veiled (no solid fill), carries a rim highlight, dims when the window is
// inactive, and with the switch off every surface draws exactly as before.

import XCTest
@testable import AppKit
@testable import SwiftUI

/// Left half red, right half blue: a hard edge for the blur to soften.
@MainActor
private final class _HalvesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.midX, height: bounds.height)).fill()
        NSColor(red: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: bounds.midX, y: 0, width: bounds.width - bounds.midX, height: bounds.height)).fill()
    }
}

@MainActor
private final class _GrayView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor(white: 0.3, alpha: 1).setFill(); NSBezierPath(rect: bounds).fill() }
}

@MainActor
private func render(_ v: NSView) -> NSBitmapImageRep {
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    return rep
}

/// A pixel in view points, y up from the bottom as the view's coordinates.
@MainActor
private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let scale = max(1, rep.pixelsWide / max(1, Int(rep.size.width)))
    let row = rep.pixelsHigh - 1 - y * scale
    guard let c = rep.colorAt(x: x * scale, y: row)?.usingColorSpace(.sRGB) else { return (0, 0, 0, 0) }
    return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

private func luma(_ p: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)) -> CGFloat { 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b }

@MainActor
private func window(width: CGFloat = 200, height: CGFloat = 100) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .aqua)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

final class LiquidGlassPixelTests: XCTestCase, @unchecked Sendable {
    /// Every test runs with the switch on unless it turns it off itself; the previous
    /// setting is restored after each.
    @MainActor private static var previousOverride: Bool?
    override func setUp() { super.setUp(); MainActor.assumeIsolated { Self.previousOverride = _LiquidGlass._override; _LiquidGlass._override = true } }
    override func tearDown() { MainActor.assumeIsolated { _LiquidGlass._override = Self.previousOverride }; super.tearDown() }

    /// The glass over a red/blue edge is red on the left, blue on the right and a soft
    /// blend across the edge: the content beneath, blurred, under a light veil.
    func testGlassShowsBlurredContentBeneath() {
        MainActor.assumeIsolated {
            let w = window()
            let halves = _HalvesView(frame: w.contentView!.bounds)
            w.contentView!.addSubview(halves)
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            glass.cornerRadius = 10
            w.contentView!.addSubview(glass)
            let rep = render(w.contentView!)

            let left = pixel(rep, 60, 50), right = pixel(rep, 140, 50), edge = pixel(rep, 100, 50)
            XCTAssertGreaterThan(left.r, left.b + 0.2, "left of the edge the glass is red: \(left)")
            XCTAssertGreaterThan(right.b, right.r + 0.2, "right of the edge the glass is blue: \(right)")
            XCTAssertGreaterThan(edge.r, 0.25, "at the edge red and blue blend: \(edge)")
            XCTAssertGreaterThan(edge.b, 0.25, "at the edge red and blue blend: \(edge)")
            // The veil lifts the colours towards white: red under glass is lighter than bare red.
            let bare = pixel(rep, 20, 50)
            XCTAssertGreaterThan(left.g, bare.g + 0.2, "the veil over red: \(left) vs bare \(bare)")
            // Blurred, not a hard edge: six points across the edge change the red by less than
            // the full swing a sharp edge would show.
            let before = pixel(rep, 96, 50), after = pixel(rep, 104, 50)
            XCTAssertLessThan(before.r - after.r, 0.35, "the edge is softened: \(before) -> \(after)")
            XCTAssertGreaterThan(before.r - after.r, 0.02, "yet the edge is there: \(before) -> \(after)")
        }
    }

    /// The rim: the top row inside the glass is lighter than the body below it.
    func testGlassRimHighlight() {
        MainActor.assumeIsolated {
            let w = window()
            w.contentView!.addSubview(_GrayView(frame: w.contentView!.bounds))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            glass.cornerRadius = 8
            w.contentView!.addSubview(glass)
            let rep = render(w.contentView!)
            let top = pixel(rep, 100, 79), body = pixel(rep, 100, 70)
            XCTAssertGreaterThan(luma(top), luma(body) + 0.08, "rim highlight along the top: \(top) vs \(body)")
            let bottom = pixel(rep, 100, 20)
            XCTAssertLessThan(luma(bottom), luma(body) + 0.02, "no highlight along the bottom: \(bottom) vs \(body)")
        }
    }

    /// An inactive window flattens the glass: more veil, less of the colour beneath.
    func testInactiveWindowDimsGlass() {
        MainActor.assumeIsolated {
            let w = window()
            w.contentView!.addSubview(_HalvesView(frame: w.contentView!.bounds))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            let active = pixel(render(w.contentView!), 60, 50)
            w.resignKey()
            XCTAssertFalse(w.isKeyWindow)
            let inactive = pixel(render(w.contentView!), 60, 50)
            XCTAssertGreaterThan(inactive.g, active.g + 0.05, "inactive glass is flatter (more veil): \(inactive) vs \(active)")
            XCTAssertLessThan(inactive.r - inactive.b, active.r - active.b, "inactive glass is less saturated")
        }
    }

    /// Dark appearance: the veil is dark, so glass over red stays dark rather than pink.
    func testDarkAppearanceUsesDarkVeil() {
        MainActor.assumeIsolated {
            let w = window()
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView!.addSubview(_HalvesView(frame: w.contentView!.bounds))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            let p = pixel(render(w.contentView!), 60, 50)
            XCTAssertLessThan(p.g, 0.25, "a dark veil over red: \(p)")
            XCTAssertGreaterThan(p.r, p.b + 0.2, "still red beneath: \(p)")
        }
    }

    /// The sample is cached: redrawing the glass itself keeps it, a view beneath dirtying
    /// the glass rectangle takes it again, one outside the rectangle does not.
    func testSampleCacheInvalidation() {
        MainActor.assumeIsolated {
            let w = window()
            let halves = _HalvesView(frame: w.contentView!.bounds)
            w.contentView!.addSubview(halves)
            let aside = _GrayView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
            w.contentView!.addSubview(aside)
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            _ = render(w.contentView!)
            let sample = _GlassRegistry.sample(for: glass)
            XCTAssertFalse(sample.dirty)
            XCTAssertNotNil(sample.image)
            glass.needsDisplay = true
            XCTAssertFalse(sample.dirty, "the glass redrawing keeps its sample")
            aside.needsDisplay = true
            XCTAssertFalse(sample.dirty, "a view outside the glass rectangle keeps the sample")
            halves.setNeedsDisplay(NSRect(x: 90, y: 40, width: 20, height: 20))
            XCTAssertTrue(sample.dirty, "content beneath the glass invalidates the sample")
            XCTAssertTrue(glass.needsDisplay, "and the glass redraws")
        }
    }

    /// Switch off: the glass view is the flat tint, the same on both sides of the edge.
    func testSwitchOffDrawsFlatTint() {
        MainActor.assumeIsolated {
            _LiquidGlass._override = false
            let w = window()
            w.contentView!.addSubview(_HalvesView(frame: w.contentView!.bounds))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            let rep = render(w.contentView!)
            let left = pixel(rep, 60, 50), right = pixel(rep, 140, 50), top = pixel(rep, 100, 79)
            // The tint is the window colour at 75% over red or blue.
            let expectedLeft = 0.75 * 0.925 + 0.25
            XCTAssertEqual(left.r, expectedLeft, accuracy: 0.03, "\(left)")
            XCTAssertEqual(right.b, expectedLeft, accuracy: 0.03, "\(right)")
            XCTAssertEqual(luma(top), luma(pixel(rep, 100, 70)), accuracy: 0.03, "no rim with the switch off")
        }
    }

    /// Switch off: `glassEffect` adds no view and a glass button is the bordered button,
    /// pixel for pixel; on, the button draws its capsule and the effect its surface.
    func testSwiftUIFallbacksWithSwitchOff() {
        MainActor.assumeIsolated {
            _LiquidGlass._override = false
            @MainActor func host<V: View>(_ v: V) -> (NSWindow, NSHostingView<V>) {
                let w = window(width: 160, height: 60)
                let h = NSHostingView(rootView: v)
                h.frame = w.contentView!.bounds
                w.contentView!.addSubview(h)
                h.layoutSubtreeIfNeeded()
                return (w, h)
            }
            let (_, plain) = host(Text("Hello"))
            let (_, glassed) = host(Text("Hello").glassEffect())
            XCTAssertEqual(allViews(glassed).count, allViews(plain).count, "glassEffect is a no-op with the switch off")
            XCTAssertFalse(allViews(glassed).contains { $0 is NSGlassEffectView })

            let (wb, bordered) = host(Button("Go") {}.buttonStyle(.bordered))
            let (wg, glass) = host(Button("Go") {}.buttonStyle(.glass))
            let b = allViews(bordered).compactMap { $0 as? NSButton }.first!, g = allViews(glass).compactMap { $0 as? NSButton }.first!
            XCTAssertTrue(g.isBordered)
            XCTAssertEqual(b.frame, g.frame)
            let pb = render(wb.contentView!), pg = render(wg.contentView!)
            XCTAssertEqual(pb.representation(using: .png, properties: [:]), pg.representation(using: .png, properties: [:]), "a glass button is the bordered button with the switch off")

            _LiquidGlass._override = true
            let (_, on) = host(Text("Hello").glassEffect())
            XCTAssertTrue(allViews(on).contains { $0 is NSGlassEffectView }, "the switch on adds the glass surface")
            let (wp, prominent) = host(Button("Go") {}.buttonStyle(.glassProminent))
            let p = allViews(prominent).compactMap { $0 as? _GlassButton }.first!
            XCTAssertEqual(p.glassProminent, true)
            let rp = render(wp.contentView!)
            let centre = pixel(rp, Int(p.frame.midX), Int(wp.contentView!.bounds.height - p.frame.midY))
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)!
            XCTAssertGreaterThan(centre.b, centre.r, "a prominent glass button carries the accent tint: \(centre) vs accent \(accent)")
        }
    }

    /// The navigation split view's sidebar pane draws the sidebar material; the detail does not.
    func testSidebarPaneIsMarked() {
        MainActor.assumeIsolated {
            struct Root: View {
                var body: some View { NavigationSplitView { List { Text("A") } } detail: { Text("Detail") } }
            }
            let w = window(width: 400, height: 200)
            let h = NSHostingView(rootView: Root())
            h.frame = w.contentView!.bounds
            w.contentView!.addSubview(h)
            h.layoutSubtreeIfNeeded()
            let panes = allViews(h).compactMap { $0 as? _SplitPaneView }
            XCTAssertEqual(panes.filter(\.isSidebar).count, 1)
            XCTAssertEqual(panes.filter { !$0.isSidebar }.count, 1)
        }
    }

    /// The software material pass: a hard edge blurs into a ramp and alpha survives.
    func testSoftwareBlur() {
        MainActor.assumeIsolated {
            let width = 16, height = 2, stride = width * 4
            var data = Data(count: stride * height)
            for y in 0..<height { for x in 0..<width { let v: UInt8 = x < 8 ? 0 : 200; data[y * stride + x * 4] = v; data[y * stride + x * 4 + 1] = v; data[y * stride + x * 4 + 2] = v; data[y * stride + x * 4 + 3] = 255 } }
            #if os(Windows) || os(Linux)
            let image = CGImage.fromBGRA(width: width, height: height, stride: stride, data: data)!
            #else
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            data.withUnsafeBytes { _ = memcpy(ctx.data!, $0.baseAddress, stride * height) }
            let image = ctx.makeImage()!
            #endif
            let blurred = SoftwareMaterialBackend.shared.blur(image, radius: 4)!
            let px = _pixels(blurred)
            let row = blurred.bytesPerRow
            XCTAssertEqual(px[0], 0); XCTAssertEqual(px[15 * 4], 200)
            XCTAssertGreaterThan(px[7 * 4], 10); XCTAssertLessThan(px[7 * 4], 100)
            XCTAssertGreaterThan(px[8 * 4], 100); XCTAssertLessThan(px[8 * 4], 190)
            XCTAssertEqual(px[3], 255); XCTAssertEqual(px[row + 9 * 4 + 3], 255)
        }
    }
}
