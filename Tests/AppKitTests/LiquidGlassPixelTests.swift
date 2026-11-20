// Liquid Glass (ADR-0052), checked in pixels: a glass surface is a blurred function of the
// content beneath it (vary the backdrop and the glass follows; the variance across it drops),
// carries the rim highlight and specular sheen of a lens, bends the backdrop into its rim,
// turns dark over dark content, brightens under the pointer, merges with its neighbours in
// a container, dims when the window is inactive, and with the switch off every surface draws
// exactly as before.

import XCTest
@testable import AppKit
@testable import SwiftUI

/// Left half a pale red, right half a pale blue: a hard edge for the blur to soften, light
/// enough (mean luminance about 0.44) for the regular glass to stay in its light variant.
@MainActor
private final class _HalvesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 1, green: 0.35, blue: 0.35, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.midX, height: bounds.height)).fill()
        NSColor(red: 0.35, green: 0.35, blue: 1, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: bounds.midX, y: 0, width: bounds.width - bounds.midX, height: bounds.height)).fill()
    }
}

@MainActor
private final class _SolidView: NSView {
    var color: NSColor
    init(frame: NSRect, color: NSColor) { self.color = color; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); NSBezierPath(rect: bounds).fill() }
}

/// Vertical black and white stripes four points wide: high variance along a row.
@MainActor
private final class _StripesView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0, dark = false
        while x < bounds.width {
            (dark ? NSColor.black : NSColor.white).setFill()
            NSBezierPath(rect: NSRect(x: x, y: 0, width: 4, height: bounds.height)).fill()
            x += 4; dark.toggle()
        }
    }
}

/// Horizontal bands of changing colour, so a scroll changes what lies beneath a lens.
@MainActor
private final class _BandsView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 0, i = 0
        while y < bounds.height {
            let band = NSRect(x: 0, y: y, width: bounds.width, height: 25)
            if band.intersects(dirtyRect) {
                NSColor(hue: CGFloat(i % 12) / 12, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                band.fill()
            }
            y += 25; i += 1
        }
    }
}

@MainActor
private func render(_ v: NSView) -> NSBitmapImageRep {
    v.layoutSubtreeIfNeeded()
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

/// The variance of the luminance along a row of pixels.
@MainActor
private func rowVariance(_ rep: NSBitmapImageRep, y: Int, xs: Range<Int>) -> CGFloat {
    let values = xs.map { luma(pixel(rep, $0, y)) }
    let mean = values.reduce(0, +) / CGFloat(values.count)
    return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / CGFloat(values.count)
}

@MainActor
private func window(width: CGFloat = 200, height: CGFloat = 100) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .aqua)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

/// A 32-bit premultiplied BGRA image of `width` by `height` from a per-pixel colour.
@MainActor
private func makeImage(width: Int, height: Int, _ color: (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8)) -> CGImage {
    let stride = width * 4
    var data = Data(count: stride * height)
    for y in 0..<height { for x in 0..<width { let c = color(x, y); data[y * stride + x * 4] = c.b; data[y * stride + x * 4 + 1] = c.g; data[y * stride + x * 4 + 2] = c.r; data[y * stride + x * 4 + 3] = 255 } }
    #if os(Windows) || os(Linux)
    return CGImage.fromBGRA(width: width, height: height, stride: stride, data: data)!
    #else
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    data.withUnsafeBytes { _ = memcpy(ctx.data!, $0.baseAddress, stride * height) }
    return ctx.makeImage()!
    #endif
}

/// (r, g, b, a) in 0...1 of a shaded image's pixel (top row first).
private func shaded(_ image: CGImage, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let d = _pixels(image), o = y * image.bytesPerRow + x * 4
    return (CGFloat(d[o + 2]) / 255, CGFloat(d[o + 1]) / 255, CGFloat(d[o]) / 255, CGFloat(d[o + 3]) / 255)
}

private final class _EmptyToolbarDelegate: NSObject, NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }
}

final class LiquidGlassPixelTests: XCTestCase, @unchecked Sendable {
    /// Every test runs with the switch on unless it turns it off itself; the previous
    /// setting is restored after each.
    @MainActor private static var previousOverride: Bool?
    override func setUp() { super.setUp(); MainActor.assumeIsolated { Self.previousOverride = _LiquidGlass._override; _LiquidGlass._override = true } }
    override func tearDown() { MainActor.assumeIsolated { _LiquidGlass._override = Self.previousOverride }; super.tearDown() }

    // MARK: Backdrop

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
            XCTAssertGreaterThan(edge.r, 0.4, "at the edge red and blue blend: \(edge)")
            XCTAssertGreaterThan(edge.b, 0.4, "at the edge red and blue blend: \(edge)")
            // The veil lifts the colours towards white: red under glass is lighter than bare red.
            let bare = pixel(rep, 20, 50)
            XCTAssertGreaterThan(left.g, bare.g + 0.1, "the veil over red: \(left) vs bare \(bare)")
            // Blurred, not a hard edge: eight points across the edge change the red by less than
            // the full swing a sharp edge would show.
            let before = pixel(rep, 96, 50), after = pixel(rep, 104, 50)
            XCTAssertLessThan(before.r - after.r, 0.35, "the edge is softened: \(before) -> \(after)")
            XCTAssertGreaterThan(before.r - after.r, 0.02, "yet the edge is there: \(before) -> \(after)")
        }
    }

    /// The glass pixels are a function of the backdrop: a different backdrop gives
    /// different glass, and the stripes beneath lose most of their variance through it.
    func testGlassFollowsAndSmoothsTheBackdrop() {
        MainActor.assumeIsolated {
            @MainActor func glassOver(_ content: NSView) -> NSBitmapImageRep {
                let w = window()
                content.frame = w.contentView!.bounds
                w.contentView!.addSubview(content)
                let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
                glass.cornerRadius = 10
                w.contentView!.addSubview(glass)
                return render(w.contentView!)
            }
            let overGreen = glassOver(_SolidView(frame: .zero, color: NSColor(red: 0.4, green: 0.9, blue: 0.4, alpha: 1)))
            let overBlue = glassOver(_SolidView(frame: .zero, color: NSColor(red: 0.4, green: 0.5, blue: 1, alpha: 1)))
            let g = pixel(overGreen, 100, 50), b = pixel(overBlue, 100, 50)
            XCTAssertGreaterThan(g.g - g.b, 0.15, "green shows through: \(g)")
            XCTAssertGreaterThan(b.b - b.g, 0.15, "blue shows through: \(b)")
            XCTAssertGreaterThan(abs(g.g - b.g) + abs(g.b - b.b), 0.3, "a different backdrop gives different glass: \(g) vs \(b)")

            let overStripes = glassOver(_StripesView(frame: .zero))
            let bare = rowVariance(overStripes, y: 10, xs: 60..<140)
            let glassRow = rowVariance(overStripes, y: 50, xs: 60..<140)
            XCTAssertGreaterThan(bare, 0.15, "the stripes beneath vary strongly: \(bare)")
            XCTAssertLessThan(glassRow, bare * 0.1, "the glass smooths them: \(glassRow) vs \(bare)")
        }
    }

    /// The sample is cached: redrawing the glass itself keeps it, a view beneath dirtying
    /// the glass rectangle takes it again, one outside the rectangle does not.
    func testSampleCacheInvalidation() {
        MainActor.assumeIsolated {
            let w = window()
            let halves = _HalvesView(frame: w.contentView!.bounds)
            w.contentView!.addSubview(halves)
            let aside = _SolidView(frame: NSRect(x: 0, y: 0, width: 20, height: 20), color: .gray)
            w.contentView!.addSubview(aside)
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            _ = render(w.contentView!)
            let sample = _GlassRegistry.sample(for: glass)
            XCTAssertFalse(sample.dirty)
            XCTAssertNotNil(sample.image)
            XCTAssertNotNil(sample.shadedImage, "the shaded image is kept with the sample")
            glass.needsDisplay = true
            XCTAssertFalse(sample.dirty, "the glass redrawing keeps its sample")
            aside.needsDisplay = true
            XCTAssertFalse(sample.dirty, "a view outside the glass rectangle keeps the sample")
            halves.setNeedsDisplay(NSRect(x: 90, y: 40, width: 20, height: 20))
            XCTAssertTrue(sample.dirty, "content beneath the glass invalidates the sample")
            XCTAssertTrue(glass.needsDisplay, "and the glass redraws")
        }
    }

    /// One paint renders the content beneath the glass once for every surface in the
    /// window, and content dirtied under one lens re-samples that lens alone.
    func testSharedFrameRendersOncePerPaint() {
        MainActor.assumeIsolated {
            let w = window(width: 300, height: 100)
            let halves = _HalvesView(frame: w.contentView!.bounds)
            w.contentView!.addSubview(halves)
            let lenses = (0..<3).map { i in NSGlassEffectView(frame: NSRect(x: 10 + i * 100, y: 20, width: 80, height: 60)) }
            lenses.forEach { w.contentView!.addSubview($0) }
            let before = _GlassRegistry.frameRenders
            let first = render(w.contentView!)
            XCTAssertEqual(_GlassRegistry.frameRenders - before, 1, "three lenses share one frame of the content beneath them")
            let samples = lenses.map { _GlassRegistry.sample(for: $0) }
            XCTAssertTrue(samples.allSatisfy { !$0.dirty && $0.image != nil })
            // Content under the middle lens changes: that lens re-samples, the others keep theirs.
            halves.setNeedsDisplay(NSRect(x: 120, y: 30, width: 40, height: 20))
            XCTAssertFalse(samples[0].dirty); XCTAssertTrue(samples[1].dirty); XCTAssertFalse(samples[2].dirty)
            XCTAssertTrue(lenses[1].needsDisplay); XCTAssertFalse(lenses[0].needsDisplay)
            let rendersBeforeSecond = _GlassRegistry.frameRenders
            let second = render(w.contentView!)
            XCTAssertEqual(_GlassRegistry.frameRenders - rendersBeforeSecond, 1, "the frame is rendered again after the content changed, once")
            XCTAssertFalse(samples[1].dirty)
            // The frame's crop lines up with the lens: its pixels match the first paint's.
            for x in [20, 50, 80, 220, 250] {
                let a = pixel(first, x, 50), b = pixel(second, x, 50)
                XCTAssertEqual(a.r, b.r, accuracy: 0.03, "x \(x)"); XCTAssertEqual(a.b, b.b, accuracy: 0.03, "x \(x)")
            }
            // Nothing changed: a third paint renders no frame and samples nothing.
            let rendersBeforeThird = _GlassRegistry.frameRenders
            _ = render(w.contentView!)
            XCTAssertEqual(_GlassRegistry.frameRenders, rendersBeforeThird, "an unchanged window is not sampled again")
        }
    }

    /// A scroll by copy (`NSClipView.copiesOnScroll`, the backing store moved rather than
    /// repainted) moves the content beneath a lens over the scroll view: the lens's sample
    /// goes stale, and the scrolled frame matches a full repaint.
    func testScrollByCopyUnderGlassResamples() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: .aqua)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            scroll.documentView = _BandsView(frame: NSRect(x: 0, y: 0, width: 300, height: 2000))
            w.contentView!.addSubview(scroll)
            let lens = NSGlassEffectView(frame: NSRect(x: 60, y: 60, width: 180, height: 80))
            w.contentView!.addSubview(lens)
            w.makeKeyAndOrderFront(nil)
            defer { w.close() }
            guard let host = w._platformWindow as? HostWindow else { XCTFail("not the host backend"); return }
            var frames = 0
            while host._needsPaint, frames < 10 { host.displayIfNeeded(); frames += 1 }
            let sample = _GlassRegistry.sample(for: lens)
            XCTAssertFalse(sample.dirty)
            let copies = host.scrollCopyCount
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: 0, y: 37))
            scroll.reflectScrolledClipView(clip)
            XCTAssertEqual(host.scrollCopyCount, copies + 1, "the scroll moved the backing store by copy")
            XCTAssertTrue(sample.dirty, "the content beneath the lens moved with the copy: its sample is stale")
            XCTAssertTrue(lens.needsDisplay)
            frames = 0
            while host._needsPaint, frames < 6 { host.displayIfNeeded(); frames += 1 }
            XCTAssertFalse(sample.dirty)
            guard let scrolled = host.lastImage.map(_pixels) else { XCTFail("no image"); return }
            w._setNeedsDisplayWhole()
            host.displayIfNeeded()
            guard let full = host.lastImage.map(_pixels), let image = host.lastImage else { XCTFail("no image"); return }
            // Across the lens (y 100 in content points, y up) the scrolled frame is the repaint.
            let scale = Int(w.backingScaleFactor)
            let row = (image.height - 1 - 100 * scale) * image.bytesPerRow
            var maxDiff = 0
            for x in stride(from: 70 * scale, to: 230 * scale, by: scale) {
                for c in 0..<3 { maxDiff = max(maxDiff, abs(Int(scrolled[row + x * 4 + c]) - Int(full[row + x * 4 + c]))) }
            }
            XCTAssertLessThanOrEqual(maxDiff, 4, "the lens over a copied scroll shows the content now beneath it")
        }
    }

    // MARK: Lens

    /// The rim: the top row inside the glass is lighter than the body below it, the bottom
    /// row is not.
    func testGlassRimHighlight() {
        MainActor.assumeIsolated {
            let w = window()
            w.contentView!.addSubview(_SolidView(frame: w.contentView!.bounds, color: NSColor(white: 0.6, alpha: 1)))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            glass.cornerRadius = 8
            w.contentView!.addSubview(glass)
            let rep = render(w.contentView!)
            let top = pixel(rep, 100, 79), body = pixel(rep, 100, 60)
            XCTAssertGreaterThan(luma(top), luma(body) + 0.08, "rim highlight along the top: \(top) vs \(body)")
            let bottom = pixel(rep, 100, 20)
            XCTAssertLessThan(luma(bottom), luma(body) + 0.02, "no highlight along the bottom: \(bottom) vs \(body)")
        }
    }

    /// The lens stage bends the backdrop into the rim: a pixel just inside the left edge
    /// shows the content beyond the edge once refraction is on, the centre does not move.
    func testRefractionBendsBackdropIntoRim() {
        MainActor.assumeIsolated {
            // Two pixels of green at the left, red beyond: the undisplaced lookup at x = 3 is red.
            let backdrop = makeImage(width: 60, height: 30) { x, _ in x < 2 ? (0, 220, 0) : (220, 0, 0) }
            let shape = PlatformGlassShape.roundedRect(CGRect(x: 0, y: 0, width: 60, height: 30), cornerRadius: 15)
            var flat = PlatformGlassParameters(width: 60, height: 30)
            flat.veilAlpha = 0; flat.edgeWidth = 8; flat.refraction = 0
            var lens = flat
            lens.refraction = 6
            let m = SoftwareMaterialBackend.shared
            let a = m.shade(backdrop, in: CGRect(x: 0, y: 0, width: 60, height: 30), shape: shape, parameters: flat)!
            let b = m.shade(backdrop, in: CGRect(x: 0, y: 0, width: 60, height: 30), shape: shape, parameters: lens)!
            let rimFlat = shaded(a, 3, 15), rimLens = shaded(b, 3, 15)
            XCTAssertLessThan(rimFlat.g, 0.1, "without refraction the rim pixel is red: \(rimFlat)")
            XCTAssertGreaterThan(rimLens.g, rimFlat.g + 0.3, "refraction bends the green beyond the edge into the rim: \(rimLens)")
            XCTAssertEqual(shaded(a, 30, 15).r, shaded(b, 30, 15).r, accuracy: 0.02, "the centre is not displaced")
            XCTAssertEqual(shaded(b, 59, 0).a, 0, "outside the capsule's corner the output is transparent")
        }
    }

    /// The specular sheen and rim follow the light from the top left: over a flat grey
    /// backdrop the top edge is brighter than the body, the bottom edge darker.
    func testSpecularHighlightFollowsTheLight() {
        MainActor.assumeIsolated {
            let backdrop = makeImage(width: 80, height: 30) { _, _ in (128, 128, 128) }
            let shape = PlatformGlassShape.roundedRect(CGRect(x: 0, y: 0, width: 80, height: 30), cornerRadius: 15)
            var p = PlatformGlassParameters(width: 80, height: 30)
            p.veilAlpha = 0; p.edgeWidth = 8; p.refraction = 0; p.rimWidth = 1; p.rimAlpha = 0.6; p.specular = 0.5
            let img = SoftwareMaterialBackend.shared.shade(backdrop, in: CGRect(x: 0, y: 0, width: 80, height: 30), shape: shape, parameters: p)!
            let top = shaded(img, 40, 0), bevel = shaded(img, 40, 3), body = shaded(img, 40, 15), bottom = shaded(img, 40, 29)
            XCTAssertGreaterThan(luma(top), luma(body) + 0.15, "the rim catches the light: \(top) vs \(body)")
            XCTAssertGreaterThan(luma(bevel), luma(body) + 0.03, "the sheen spreads down the bevel: \(bevel) vs \(body)")
            // The sheen is a soft band, not a line: still well above the body two pixels in,
            // fading by six pixels, gone at the centre.
            let band = shaded(img, 40, 2), deeper = shaded(img, 40, 6)
            XCTAssertGreaterThan(luma(band), luma(body) + 0.12, "the highlight band is pronounced: \(band) vs \(body)")
            XCTAssertGreaterThan(luma(band), luma(deeper) + 0.03, "and falls off with depth")
            XCTAssertGreaterThan(luma(deeper), luma(body) + 0.04, "reaching twice the bevel's depth")
            XCTAssertLessThan(luma(bottom), luma(body) - 0.03, "the bottom rim is in shadow: \(bottom) vs \(body)")
            // Top left faces the light more than top right.
            XCTAssertGreaterThan(luma(shaded(img, 10, 4)), luma(shaded(img, 70, 4)), "the highlight leans left")
        }
    }

    /// Any outline (a diamond) goes through the coverage distance field: the output is
    /// transparent outside it, shaded inside, with a rim at its edge.
    func testCoverageShapeIsShaded() {
        MainActor.assumeIsolated {
            let backdrop = makeImage(width: 40, height: 40) { _, _ in (100, 150, 200) }
            let diamond = _MaterialPixelsProbe.diamond(width: 40, height: 40, template: backdrop)
            var p = PlatformGlassParameters(width: 40, height: 40)
            p.veilAlpha = 0.3; p.edgeWidth = 4; p.refraction = 2; p.rimWidth = 2; p.rimAlpha = 0.6; p.specular = 0.5
            let img = SoftwareMaterialBackend.shared.shade(backdrop, in: CGRect(x: 0, y: 0, width: 40, height: 40), shape: .coverage(diamond), parameters: p)!
            XCTAssertEqual(shaded(img, 1, 1).a, 0, "transparent outside the diamond")
            let centre = shaded(img, 20, 20)
            XCTAssertEqual(centre.a, 1, accuracy: 0.01)
            XCTAssertGreaterThan(centre.b, centre.r, "the backdrop shows through the veil: \(centre)")
            // Just inside the upper-left edge (whose normal faces the light) the bevel is lit;
            // the lower-right edge, facing away, is not.
            XCTAssertGreaterThan(luma(shaded(img, 10, 10)), luma(centre) + 0.05, "a lit bevel along the diamond's upper-left edge")
            XCTAssertLessThan(luma(shaded(img, 29, 29)), luma(centre) + 0.02, "no sheen along the lower-right edge")
        }
    }

    // MARK: Variants

    /// Light appearance, regular glass: over dark content the glass turns to its dark
    /// variant, over light content it stays light.
    func testAdaptiveVariantFollowsBackdropLuminance() {
        MainActor.assumeIsolated {
            @MainActor func glassOver(_ color: NSColor) -> (pixel: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat), luminance: CGFloat?) {
                let w = window()
                w.contentView!.addSubview(_SolidView(frame: w.contentView!.bounds, color: color))
                let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
                w.contentView!.addSubview(glass)
                let rep = render(w.contentView!)
                return (pixel(rep, 100, 50), _GlassRegistry.sample(for: glass).luminance)
            }
            let overBlack = glassOver(NSColor(white: 0.05, alpha: 1))
            let overWhite = glassOver(NSColor(white: 0.95, alpha: 1))
            XCTAssertLessThan(overBlack.luminance ?? 1, 0.35, "the sample's luminance is read")
            XCTAssertGreaterThan(overWhite.luminance ?? 0, 0.35)
            XCTAssertLessThan(luma(overBlack.pixel), 0.3, "dark glass over dark content: \(overBlack.pixel)")
            XCTAssertGreaterThan(luma(overWhite.pixel), 0.8, "light glass over light content: \(overWhite.pixel)")
            let spec = _GlassSpec.lens(clear: false, in: NSView())
            XCTAssertTrue(spec.resolvesDark(luminance: 0.2))
            XCTAssertFalse(spec.resolvesDark(luminance: 0.6))
        }
    }

    /// Dark appearance: the veil is dark whatever the backdrop, so glass over a pale red
    /// stays dark rather than pink.
    func testDarkAppearanceUsesDarkVeil() {
        MainActor.assumeIsolated {
            let w = window()
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView!.addSubview(_HalvesView(frame: w.contentView!.bounds))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            let p = pixel(render(w.contentView!), 60, 50)
            XCTAssertLessThan(p.g, 0.3, "a dark veil over red: \(p)")
            XCTAssertGreaterThan(p.r, p.b + 0.2, "still red beneath: \(p)")
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

    // MARK: Interaction and containers

    /// An interactive surface brightens under the pointer, more while pressed, and grows
    /// back to its bounds while pressed.
    func testInteractiveStatesBrightenAndGrow() {
        MainActor.assumeIsolated {
            let w = window()
            w.contentView!.addSubview(_SolidView(frame: w.contentView!.bounds, color: NSColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1)))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            glass.cornerRadius = 10
            glass._isInteractive = true
            w.contentView!.addSubview(glass)
            let restRep = render(w.contentView!)
            let rest = pixel(restRep, 100, 50), restEdge = pixel(restRep, 100, 79)
            glass._isHovered = true
            let hovered = pixel(render(w.contentView!), 100, 50)
            glass._isPressed = true
            let rep = render(w.contentView!)
            let pressed = pixel(rep, 100, 50), pressedEdge = pixel(rep, 100, 79)
            XCTAssertGreaterThan(luma(hovered), luma(rest) + 0.01, "hover brightens: \(hovered) vs \(rest)")
            XCTAssertGreaterThan(luma(pressed), luma(hovered) + 0.01, "press brightens more: \(pressed) vs \(hovered)")
            // At rest the surface is inset a point: the top row of the bounds is bare content.
            XCTAssertEqual(restEdge.b, 0.9, accuracy: 0.1, "at rest the bounds' top row is bare: \(restEdge)")
            XCTAssertGreaterThan(luma(pressedEdge), luma(restEdge) + 0.1, "pressed, the surface grows to the bounds (rim row): \(pressedEdge) vs \(restEdge)")
        }
    }

    /// Two glass views closer than the container's spacing draw as one capsule: the gap
    /// between them is glass, and the members draw no surface of their own; farther apart
    /// than the spacing they stay separate; a shared union identifier merges them anyway.
    func testContainerMergesNeighbours() {
        MainActor.assumeIsolated {
            @MainActor func merged(spacing: CGFloat, union: Bool = false) -> (NSGlassEffectContainerView, NSBitmapImageRep) {
                let w = window()
                w.contentView!.addSubview(_SolidView(frame: w.contentView!.bounds, color: NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)))
                let container = NSGlassEffectContainerView(frame: w.contentView!.bounds)
                container.spacing = spacing
                let a = NSGlassEffectView(frame: NSRect(x: 30, y: 30, width: 60, height: 40)), b = NSGlassEffectView(frame: NSRect(x: 110, y: 30, width: 60, height: 40))
                a.cornerRadius = 20; b.cornerRadius = 20
                if union { a._unionID = "pair"; b._unionID = "pair" }
                container.addSubview(a); container.addSubview(b)
                w.contentView!.addSubview(container)
                container.layoutSubtreeIfNeeded()
                return (container, render(w.contentView!))
            }
            let (one, repOne) = merged(spacing: 30)
            XCTAssertEqual(one._groups.count, 1)
            XCTAssertTrue(one._glassViews.allSatisfy(\._surfaceDrawnByContainer))
            XCTAssertEqual(one._groups.first?.rect, NSRect(x: 30, y: 30, width: 140, height: 40))
            let gap = pixel(repOne, 100, 50)
            XCTAssertGreaterThan(gap.g, 0.55, "the gap between the members is glass (veiled): \(gap)")

            let (two, repTwo) = merged(spacing: 10)
            XCTAssertEqual(two._groups.count, 0, "a gap of 20 points is wider than a spacing of 10")
            XCTAssertFalse(two._glassViews.contains(where: \._surfaceDrawnByContainer))
            let bareGap = pixel(repTwo, 100, 50)
            XCTAssertEqual(bareGap.g, 0.4, accuracy: 0.05, "the gap shows the content: \(bareGap)")
            let inside = pixel(repTwo, 60, 50)
            XCTAssertGreaterThan(inside.g, 0.55, "each member draws its own surface: \(inside)")

            let (unioned, _) = merged(spacing: 0, union: true)
            XCTAssertEqual(unioned._groups.count, 1, "glassEffectUnion merges whatever the distance")
        }
    }

    /// SwiftUI: `GlassEffectContainer` is the container view, and two glass effects within
    /// its spacing merge; `glassEffectUnion` merges them whatever the spacing; `interactive`
    /// reaches the surface.
    func testSwiftUIContainerMerges() {
        MainActor.assumeIsolated {
            struct Pair: View {
                let spacing: CGFloat
                let union: Bool
                @Namespace var ns
                var body: some View {
                    GlassEffectContainer(spacing: spacing) {
                        HStack(spacing: 8) {
                            Text("Play").padding(8).glassEffect().glassEffectUnion(id: union ? "a" : "x", namespace: ns)
                            Text("Next").padding(8).glassEffect().glassEffectUnion(id: union ? "a" : "y", namespace: ns)
                        }
                    }
                }
            }
            @MainActor func host(_ spacing: CGFloat, union: Bool = false) -> NSGlassEffectContainerView {
                let w = window(width: 300, height: 80)
                let h = NSHostingView(rootView: Pair(spacing: spacing, union: union))
                h.frame = w.contentView!.bounds
                w.contentView!.addSubview(h)
                h.layoutSubtreeIfNeeded()
                _ = render(w.contentView!)
                let containers = allViews(h).compactMap { $0 as? NSGlassEffectContainerView }
                XCTAssertEqual(containers.count, 1)
                containers.first?.layoutSubtreeIfNeeded()
                return containers.first!
            }
            XCTAssertEqual(host(20)._glassViews.count, 2)
            XCTAssertEqual(host(20)._groups.count, 1, "eight points apart, within a spacing of 20")
            XCTAssertEqual(host(4)._groups.count, 0, "farther apart than a spacing of 4")
            XCTAssertEqual(host(4, union: true)._groups.count, 1, "glassEffectUnion merges them")
            let h = NSHostingView(rootView: Text("Hi").glassEffect(.regular.interactive()))
            h.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(allViews(h).compactMap { $0 as? NSGlassEffectView }.first?._isInteractive, true)
        }
    }

    // MARK: Chrome

    /// The toolbar band over a document that does not run under it: nothing but the window
    /// background lies beneath, so the scroll-edge effect mirrors the content below the band
    /// into the material, and the band carries the document's colour. Off, the band is grey.
    func testToolbarBandCarriesTheContentColour() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            @MainActor func bandPixel(on: Bool) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
                _LiquidGlass._override = on
                let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 200), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                w.appearance = NSAppearance(named: .aqua)
                w.makeKeyAndOrderFront(nil)
                defer { w.close() }
                let content = _SolidView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), color: NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1))
                content.autoresizingMask = [.width, .height]
                w.contentView = content
                let d = _EmptyToolbarDelegate()
                let tb = NSToolbar(identifier: "glass.band.\(on)")
                tb.delegate = d
                w.toolbar = tb
                w.display()
                guard let image = (Mirror(reflecting: w).descendant("_platform") as? HostWindow)?.lastImage else { XCTFail("no host image"); return (0, 0, 0) }
                let data = _pixels(image)
                let scale = Int(w.backingScaleFactor)
                let contentHeight = Int(w.contentView!.bounds.height)
                // Six points into the band, in content points y up.
                let i = (image.height - 1 - (contentHeight + 6) * scale) * image.bytesPerRow + 200 * scale * 4
                return (CGFloat(data[i + 2]) / 255, CGFloat(data[i + 1]) / 255, CGFloat(data[i]) / 255)
            }
            let glass = bandPixel(on: true)
            XCTAssertGreaterThan(glass.g, glass.r + 0.1, "the band carries the green of the document below it: \(glass)")
            XCTAssertGreaterThan(glass.g, 0.7, "under the light veil: \(glass)")
            let plain = bandPixel(on: false)
            XCTAssertLessThan(abs(plain.g - plain.r), 0.03, "off, the band is grey: \(plain)")
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

    // MARK: Switch off

    /// Switch off: the glass view is the flat tint, the same on both sides of the edge, and
    /// a container groups nothing.
    func testSwitchOffDrawsFlatTint() {
        MainActor.assumeIsolated {
            _LiquidGlass._override = false
            let w = window()
            w.contentView!.addSubview(_SolidView(frame: w.contentView!.bounds, color: NSColor(red: 1, green: 0, blue: 0, alpha: 1)))
            let glass = NSGlassEffectView(frame: NSRect(x: 40, y: 20, width: 120, height: 60))
            w.contentView!.addSubview(glass)
            let rep = render(w.contentView!)
            let left = pixel(rep, 60, 50), top = pixel(rep, 100, 79)
            // The tint is the window colour at 75% over red.
            let expected = 0.75 * 0.925 + 0.25
            XCTAssertEqual(left.r, expected, accuracy: 0.03, "\(left)")
            XCTAssertEqual(luma(top), luma(pixel(rep, 100, 70)), accuracy: 0.03, "no rim with the switch off")
            let container = NSGlassEffectContainerView(frame: w.contentView!.bounds)
            container.spacing = 100
            container.addSubview(NSGlassEffectView(frame: NSRect(x: 10, y: 10, width: 40, height: 40)))
            container.addSubview(NSGlassEffectView(frame: NSRect(x: 60, y: 10, width: 40, height: 40)))
            container.layoutSubtreeIfNeeded()
            XCTAssertEqual(container._groups.count, 0)
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

    // MARK: Software pass

    /// The software material pass: a hard edge blurs into a ramp and alpha survives.
    func testSoftwareBlur() {
        MainActor.assumeIsolated {
            let image = makeImage(width: 16, height: 2) { x, _ in x < 8 ? (0, 0, 0) : (200, 200, 200) }
            let blurred = SoftwareMaterialBackend.shared.blur(image, radius: 4)!
            let px = _pixels(blurred)
            let row = blurred.bytesPerRow
            XCTAssertEqual(px[0], 0); XCTAssertEqual(px[15 * 4], 200)
            XCTAssertGreaterThan(px[7 * 4], 10); XCTAssertLessThan(px[7 * 4], 100)
            XCTAssertGreaterThan(px[8 * 4], 100); XCTAssertLessThan(px[8 * 4], 190)
            XCTAssertEqual(px[3], 255); XCTAssertEqual(px[row + 9 * 4 + 3], 255)
        }
    }

    /// Saturation pulls a pale colour away from its luminance; the luminance probe reads
    /// the mean.
    func testSaturationAndLuminance() {
        MainActor.assumeIsolated {
            let pale = makeImage(width: 4, height: 4) { _, _ in (180, 120, 120) }
            let vivid = SoftwareMaterialBackend.shared.blur(pale, radius: 0, saturation: 1.5)!
            let p = shaded(vivid, 1, 1)
            XCTAssertGreaterThan(p.r, 180.0 / 255 + 0.05, "red pushed up: \(p)")
            XCTAssertLessThan(p.g, 120.0 / 255 - 0.02, "green pushed down: \(p)")
            let l = SoftwareMaterialBackend.shared.averageLuminance(pale)!
            XCTAssertEqual(l, (0.2126 * 180 + 0.7152 * 120 + 0.0722 * 120) / 255, accuracy: 0.01)
            XCTAssertEqual(SoftwareMaterialBackend.shared.averageLuminance(makeImage(width: 2, height: 2) { _, _ in (255, 255, 255) })!, 1, accuracy: 0.01)
        }
    }
}

/// Builds coverage masks for the shape tests.
enum _MaterialPixelsProbe {
    /// A diamond (rotated square) filling the image, as a coverage mask.
    @MainActor
    static func diamond(width: Int, height: Int, template: CGImage) -> CGImage {
        var px = _MaterialPixels(width: width, height: height, template: template)
        let cx = Double(width) / 2, cy = Double(height) / 2
        for y in 0..<height {
            for x in 0..<width {
                let inside = abs(Double(x) + 0.5 - cx) / cx + abs(Double(y) + 0.5 - cy) / cy <= 1
                let o = y * px.stride + x * 4
                let v: UInt8 = inside ? 255 : 0
                px.bytes[o] = v; px.bytes[o + 1] = v; px.bytes[o + 2] = v; px.bytes[o + 3] = v
            }
        }
        return px.makeImage()!
    }
}
