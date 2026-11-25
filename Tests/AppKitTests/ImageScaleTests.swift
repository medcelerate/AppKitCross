// Symbol and template images at non-1x display scales: text was crisp at 150% on Windows
// while every symbol was soft, a 4-pixel ramp at each edge, as if rasterised at 1x and
// scaled up. On Windows and Linux a window's backing scale lives in the render target (the
// Direct2D DPI, the Cairo base transform), not in the CTM, and images measured their scale
// from the CTM. These tests measure an edge the way the PC did: the partially covered pixels
// between the background and the artwork's solid core along one row.
import XCTest
@testable import AppKit
@testable import SwiftUI
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
@testable import QuartzCore
#endif
#if os(Linux)
import CCairo
#endif

#if canImport(CoreGraphics)
/// One row's left edge: how many pixels sit between the background and the solid core
/// (coverage strictly between 2% and 98%), and the row's ink in pixels (the coverage sum).
struct _EdgeProfile: CustomStringConvertible {
    var ramp: Int
    var ink: CGFloat
    var values: [UInt8]
    var description: String { "ramp \(ramp) ink \(String(format: "%.2f", ink)) row \(values.map { String(format: "%02X", $0) }.joined(separator: " "))" }

    /// `coverage(x)` in 0...1 for each pixel of a row of `width` pixels; `values` keeps a
    /// byte per pixel for the failure message (as the PC printed the R channel).
    init(width: Int, coverage: (Int) -> CGFloat) {
        let c = (0..<width).map { min(1, max(0, coverage($0))) }
        values = c.map { UInt8((255 * (1 - $0)).rounded()) }
        ink = c.reduce(0, +)
        guard let core = c.firstIndex(where: { $0 >= 0.98 }) else { ramp = .max; return }
        var n = 0, x = core - 1
        while x >= 0, c[x] > 0.02 { n += 1; x -= 1 }
        ramp = n
    }
}

/// Coverage of a top-down BGRA image: by alpha (artwork on transparent pixels) or by
/// darkness against a white background, relative to `core` (the artwork's own darkness).
@MainActor
func _edgeProfile(_ image: CGImage, row: Int, byAlpha: Bool, core: CGFloat = 1) -> _EdgeProfile {
    let data = _pixels(image)
    return _EdgeProfile(width: image.width) { x in
        let i = row * image.bytesPerRow + x * 4
        if byAlpha { return CGFloat(data[i + 3]) / 255 }
        return (1 - CGFloat(data[i + 2]) / 255) / max(0.01, core)
    }
}

/// Bounding box (pixels, top-down rows) of pixels darker than half way on white.
@MainActor
func _darkBox(_ image: CGImage, threshold: UInt8 = 128) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
    let data = _pixels(image)
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for row in 0..<image.height {
        for x in 0..<image.width where data[row * image.bytesPerRow + x * 4 + 2] < threshold {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, row); maxY = max(maxY, row)
        }
    }
    return maxX < 0 ? nil : (minX, maxX, minY, maxY)
}
#endif

final class ImageScaleTests: XCTestCase, @unchecked Sendable {
    #if canImport(CoreGraphics)
    @MainActor private func host(_ w: NSWindow) -> HostWindow { Mirror(reflecting: w).descendant("_platform") as! HostWindow }

    /// `stop.fill` is a 9 pt square from 3.5 to 12.5 in its 16 pt box: one straight edge per
    /// side, half a point off the 1x grid.
    @MainActor private func stopSymbol() -> NSImage? { NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil) }

    /// The symbol drawn into a bitmap context of `scale` at `origin` (points).
    @MainActor private func drawSymbol(scale: CGFloat, origin: NSPoint = .zero, size: CGFloat = 16) -> CGImage? {
        guard let image = stopSymbol(),
              let surface = Platform.backend.image.makeOffscreen(size: NSSize(width: size + 4, height: size + 4), scale: scale) else { return nil }
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: surface.context, flipped: false)
        image.draw(in: NSRect(x: origin.x, y: origin.y, width: size, height: size))
        NSGraphicsContext.current = saved
        return surface.makeImage()
    }

    /// The row through the middle of the square (8 pt up from the image's bottom edge at
    /// `originY`), top-down, in an image `heightPoints` tall at `scale`.
    private func middleRow(scale: CGFloat, heightPoints: CGFloat, originY: CGFloat = 0, size: CGFloat = 16) -> Int {
        Int(((heightPoints - originY - size / 2) * scale).rounded(.down))
    }

    /// A symbol in a 2x context has twice the edge resolution of the same symbol at 1x: each
    /// edge is at most one partially covered pixel (not the 4-pixel ramp of a 1x raster scaled
    /// up), and the row's ink doubles. At 1.5x the same holds.
    func testSymbolRasterisesAtTheContextScale() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            var inks: [CGFloat: CGFloat] = [:]
            for scale: CGFloat in [1, 1.5, 2] {
                guard let image = drawSymbol(scale: scale) else { return XCTFail("no offscreen at \(scale)x") }
                XCTAssertEqual(image.width, Int((20 * scale).rounded(.up)))
                let p = _edgeProfile(image, row: middleRow(scale: scale, heightPoints: 20), byAlpha: true)
                XCTAssertLessThanOrEqual(p.ramp, 1, "\(scale)x: the edge is one pixel of coverage at most: \(p)")
                XCTAssertEqual(p.ink, 9 * scale, accuracy: 0.6, "\(scale)x: the 9 pt square covers \(9 * scale) px of the row: \(p)")
                inks[scale] = p.ink
            }
            if let one = inks[1], let two = inks[2] { XCTAssertEqual(two / one, 2, accuracy: 0.1) }
            // At 2x the square's edge (3.5 pt = 7 px) is on the pixel grid: no partial pixel.
            if let two = drawSymbol(scale: 2) {
                let p = _edgeProfile(two, row: middleRow(scale: 2, heightPoints: 20), byAlpha: true)
                XCTAssertEqual(p.ramp, 0, "2x: the edge falls on a pixel boundary: \(p)")
            }
        }
    }

    /// A symbol drawn at a fractional point position at 1.5x is placed on the pixel grid
    /// rather than resampled across two pixels at every edge.
    func testSymbolAtAFractionalPositionStaysOnThePixelGrid() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard let image = drawSymbol(scale: 1.5, origin: NSPoint(x: 0.4, y: 0.4)) else { return XCTFail("no offscreen") }
            let p = _edgeProfile(image, row: middleRow(scale: 1.5, heightPoints: 20, originY: 0.4), byAlpha: true)
            XCTAssertLessThanOrEqual(p.ramp, 1, "\(p)")
            XCTAssertEqual(p.ink, 13.5, accuracy: 0.6, "\(p)")
        }
    }

    /// A symbol drawn larger than its artwork (a 44 pt empty-state glyph) is rasterised for
    /// the destination's pixels, not rendered at its 16 pt size and scaled up.
    func testEnlargedSymbolRasterisesForTheDestination() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard let image = drawSymbol(scale: 1, size: 64) else { return XCTFail("no offscreen") }
            let p = _edgeProfile(image, row: middleRow(scale: 1, heightPoints: 68, size: 64), byAlpha: true)
            XCTAssertLessThanOrEqual(p.ramp, 1, "\(p)")
            XCTAssertEqual(p.ink, 36, accuracy: 0.6, "\(p)")
        }
    }

    /// The template tint (buttons, toolbar items, menus) renders at the context's device
    /// scale and keeps one tinted raster per pixel size.
    func testTemplateTintFollowsTheContextScale() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard let image = stopSymbol() else { return XCTFail("no symbol") }
            var widths: [Int] = []
            for scale: CGFloat in [1, 2, 1.5] {
                guard let surface = Platform.backend.image.makeOffscreen(size: NSSize(width: 16, height: 16), scale: scale) else { return XCTFail("no offscreen") }
                let saved = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: surface.context, flipped: false)
                let tinted = image._tintedForTemplate(.systemRed, size: NSSize(width: 16, height: 16))
                NSGraphicsContext.current = saved
                guard let cg = tinted?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return XCTFail("no tint at \(scale)x") }
                widths.append(cg.width)
            }
            XCTAssertEqual(widths, [16, 32, 24], "one raster per device pixel size")
        }
    }

    /// An image view's symbol is drawn again at the new scale after the window moves to a
    /// monitor of another scale (WM_DPICHANGED), and is crisp at each; back at 1x it is the
    /// 1x raster again, not a blurred one left from the 2x pass.
    func testImageViewRerastersAfterABackingScaleChange() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            let view = NSImageView(frame: NSRect(x: 12, y: 12, width: 16, height: 16))
            view.image = stopSymbol()
            w.contentView!.addSubview(view)
            let platform = host(w)
            platform.setBackingScaleFactor(1)
            w.makeKeyAndOrderFront(nil)
            w.display()
            var rows: [CGFloat: _EdgeProfile] = [:]
            for scale: CGFloat in [1, 1.5, 2, 1] {
                platform.setBackingScaleFactor(scale)
                var frames = 0
                repeat { w.displayIfNeeded(); frames += 1 } while platform._needsPaint && frames < 6
                guard let image = platform.lastImage else { return XCTFail("no image at \(scale)x") }
                XCTAssertEqual(image.width, Int(40 * scale))
                let p = _edgeProfile(image, row: middleRow(scale: scale, heightPoints: 40, originY: 12), byAlpha: false)
                XCTAssertLessThanOrEqual(p.ramp, 1, "\(scale)x: \(p)")
                XCTAssertEqual(p.ink, 9 * scale, accuracy: 0.8, "\(scale)x: \(p)")
                if let previous = rows[scale] { XCTAssertEqual(previous.values, p.values, "\(scale)x again draws the same pixels") }
                rows[scale] = p
            }
            w.close()
        }
    }

    /// `Image(systemName:)` in a hosting view draws at the hosting window's scale: at 1.5x
    /// and 2x its edges are as crisp as at 1x and its ink grows with the scale.
    func testSwiftUISymbolDrawsAtTheHostingViewsScale() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Screen: View {
                var body: some View {
                    Image(systemName: "stop.fill").foregroundColor(.black).frame(width: 40, height: 40)
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            w.contentView = NSHostingView(rootView: Screen())
            let platform = host(w)
            w.makeKeyAndOrderFront(nil)
            var inks: [CGFloat: CGFloat] = [:]
            for scale: CGFloat in [1, 1.5, 2] {
                platform.setBackingScaleFactor(scale)
                var frames = 0
                repeat { w.displayIfNeeded(); frames += 1 } while platform._needsPaint && frames < 6
                guard let image = platform.lastImage, let box = _darkBox(image) else { return XCTFail("no symbol drawn at \(scale)x") }
                let row = (box.minY + box.maxY) / 2
                let p = _edgeProfile(image, row: row, byAlpha: false)
                XCTAssertLessThanOrEqual(p.ramp, 1, "\(scale)x: \(p)")
                XCTAssertEqual(p.ink, 9 * scale, accuracy: 0.8, "\(scale)x: \(p)")
                inks[scale] = p.ink
            }
            if let one = inks[1], let two = inks[2] { XCTAssertEqual(two / one, 2, accuracy: 0.1) }
            w.close()
        }
    }

    /// `layerContents(forContentsScale:)` renders a symbol at the layer's scale, and an
    /// NSImage set as a layer's contents is drawn from those pixels at its point size.
    func testLayerContentsFollowTheContentsScale() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard let image = stopSymbol() else { return XCTFail("no symbol") }
            XCTAssertEqual(image.recommendedLayerContentsScale(2), 2, "a drawn image renders at any scale")
            XCTAssertEqual(image._cgImage(scale: 2)?.width, 32)
            let bitmap = NSImage(cgImage: image._cgImage(scale: 1)!, size: NSSize(width: 16, height: 16))
            XCTAssertEqual(bitmap.recommendedLayerContentsScale(2), 1, "a 1x bitmap has no more pixels to give")

            _CoreAnimationHost.installIfNeeded()
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
            layer.contentsScale = 2
            layer.contents = image
            guard let surface = Platform.backend.image.makeOffscreen(size: NSSize(width: 16, height: 16), scale: 2) else { return XCTFail("no offscreen") }
            layer.render(in: surface.context)
            guard let out = surface.makeImage() else { return XCTFail("no pixels") }
            let p = _edgeProfile(out, row: 16, byAlpha: true)
            XCTAssertLessThanOrEqual(p.ramp, 1, "\(p)")
            XCTAssertEqual(p.ink, 18, accuracy: 0.6, "the NSImage fills its 16 pt at 2x: \(p)")
        }
    }

    /// The port's contexts report the pixels per point through the user-to-device transform.
    func testUserSpaceToDeviceSpaceIncludesTheScale() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard let surface = Platform.backend.image.makeOffscreen(size: NSSize(width: 10, height: 10), scale: 1.5) else { return XCTFail("no offscreen") }
            XCTAssertEqual(NSImage._deviceScale(surface.context, hints: nil), 1.5, accuracy: 0.001)
            XCTAssertEqual(NSImage._scale(of: surface.context.userSpaceToDeviceSpaceTransform), 1.5, accuracy: 0.001)
        }
    }

    /// A row's darkness on white relative to its darkest pixel (a tinted symbol is grey).
    @MainActor private func relativeProfile(_ image: CGImage, row: Int) -> _EdgeProfile {
        let data = _pixels(image)
        var darkest: CGFloat = 0
        for x in 0..<image.width { darkest = max(darkest, 1 - CGFloat(data[row * image.bytesPerRow + x * 4 + 2]) / 255) }
        return _edgeProfile(image, row: row, byAlpha: false, core: darkest)
    }

    /// A toolbar group's buttons sit in a container whose origin is fractional at 1.5x (the
    /// right-hand group of Sibyl's toolbar at x + 0.5 px). Their symbols must land on whole
    /// pixels, drawn in software and composited as layers alike: the PC read a half-pixel
    /// shifted edge (E8 D9 99 79 B9) on those items while the left group was crisp.
    func testButtonSymbolInAFractionalContainerAtOneAndAHalf() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for layered in [false, true] {
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
                w.backgroundColor = .white
                let group = NSView(frame: NSRect(x: 30 + 1.0 / 3, y: 10, width: 40, height: 20))
                let button = NSButton(frame: NSRect(x: 2, y: 2, width: 16, height: 16))
                button.isBordered = false
                button.image = stopSymbol()
                button.imagePosition = .imageOnly
                group.addSubview(button)
                w.contentView!.addSubview(group)
                let platform = host(w)
                if layered {
                    w.contentView!.wantsLayer = true
                    platform.layerHostingEnabled = true
                }
                platform.setBackingScaleFactor(1.5)
                w.makeKeyAndOrderFront(nil)
                if layered { w._updateLayerHosting() }
                var frames = 0
                repeat { w.displayIfNeeded(); frames += 1 } while platform._needsPaint && frames < 6
                w.display()
                if layered { XCTAssertTrue(w._hostsLayersNatively) }
                guard let image = platform.lastImage, let box = _darkBox(image, threshold: 200) else { return XCTFail("no symbol (layered \(layered))") }
                let p = relativeProfile(image, row: (box.minY + box.maxY) / 2)
                XCTAssertLessThanOrEqual(p.ramp, 1, "layered \(layered): \(p)")
                w.close()
            }
        }
    }

    /// The placement arithmetic: absolute positions round to whole pixels, children are
    /// placed relative to their parent's rounded position, and a node under a scale keeps
    /// its exact translation.
    func testScenePlacementsSnapToWholePixels() {
        var scene = _CALayerScene()
        func node(_ id: Int, parent: Int?, _ t: CGAffineTransform) -> _CALayerSceneNode {
            _CALayerSceneNode(id: id, parent: parent, transform: t, size: CGSize(width: 10, height: 10), opacity: 1, clipsToBounds: false, cornerRadius: 0, maskedCorners: [], content: nil, name: nil)
        }
        scene.nodes = [
            node(100, parent: nil, .identity),
            node(101, parent: 0, CGAffineTransform(translationX: 30 + 1.0 / 3, y: 10)),     // 45.5 px
            node(102, parent: 1, CGAffineTransform(translationX: 2, y: 2.25)),             // 48.5, 18.375
            node(103, parent: 1, CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: 0.5, ty: 0)),
            node(104, parent: 3, CGAffineTransform(translationX: 0.25, y: 0)),
        ]
        let p = scene._pixelSnappedTranslations(scale: 1.5)
        XCTAssertEqual(p[0], .zero)
        XCTAssertEqual(p[1], CGPoint(x: 46, y: 15), "45.5 px rounds to 46")
        // Child absolute 48.5 → 49 (relative 3 to the parent's 46); 18.375 → 18 (relative 3).
        XCTAssertEqual(p[2], CGPoint(x: 3, y: 3))
        XCTAssertNil(p[3], "a scaled node keeps its exact translation")
        XCTAssertNil(p[4], "and so does everything under it")
    }

    /// A menu opened from a window on a 150% monitor to the right of a 100% primary. In the
    /// port's screen points (each monitor's pixels at its own scale) the two monitors' point
    /// frames overlap, so the first screen holding the anchor was the primary: the PC saw
    /// the "Toolbar style" pop-up open on the primary at x / 1.5. The menu takes the screen
    /// of the window it was opened from and its window is placed on that display.
    func testMenuFromAWindowOnASecondaryMonitorOpensOnThatMonitor() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let backend = Platform.backend as! HostBackend
            let saved = backend.displays
            defer { backend.displays = saved }
            let primary = PlatformDisplay(frame: NSRect(x: 0, y: 0, width: 2560, height: 1440), visibleFrame: NSRect(x: 0, y: 40, width: 2560, height: 1400),
                                          backingScaleFactor: 1, localizedName: "Primary 100%", isMain: true)
            // 2560 px to the right at 150%: points are its pixels / 1.5.
            let secondary = PlatformDisplay(frame: NSRect(x: 2560 / 1.5, y: 0, width: 2560 / 1.5, height: 1440 / 1.5), visibleFrame: NSRect(x: 2560 / 1.5, y: 0, width: 2560 / 1.5, height: 1440 / 1.5),
                                            backingScaleFactor: 1.5, localizedName: "Secondary 150%", isMain: false)
            backend.displays = [primary, secondary]
            let w = NSWindow(contentRect: NSRect(x: 2006, y: 400, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            host(w)._currentDisplay = secondary
            w.makeKeyAndOrderFront(nil)
            XCTAssertEqual(w.screen?.localizedName, "Secondary 150%")
            let anchor = NSRect(x: 2116, y: 560, width: 130, height: 24)
            XCTAssertTrue(NSScreen.screens[0].frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)), "the point frames overlap at the anchor")
            XCTAssertEqual(_NSMenuTracker.screen(forAnchor: anchor, source: w)?.localizedName, "Secondary 150%")
            XCTAssertEqual(_NSMenuTracker.screen(forAnchor: anchor, source: nil)?.localizedName, "Primary 100%", "without a source window the first screen holding the anchor")

            let menu = NSMenu(title: "Style")
            menu.addItem(withTitle: "Icon and Text", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Icon Only", action: nil, keyEquivalent: "")
            let tracker = _NSMenuTracker.begin(menu: menu, anchor: anchor, placement: .besideAnchor(edge: .minY), openedWithMouseDown: false)
            defer { tracker.cancel() }
            guard let menuWindow = tracker.levels.first?.window else { return XCTFail("no menu window") }
            // NSWindow's storage, through the subclass's mirror.
            var mirror: Mirror? = Mirror(reflecting: menuWindow)
            var found: HostWindow? = nil
            while let m = mirror, found == nil { found = m.descendant("_platform") as? HostWindow; mirror = m.superclassMirror }
            guard let menuHost = found else { return XCTFail("no host window") }
            XCTAssertEqual(menuHost.lastPlacementDisplay?.localizedName, "Secondary 150%", "the menu window is placed on the source window's monitor")
            XCTAssertEqual(menuWindow.frame.minX, anchor.minX, accuracy: 0.5, "it opens at its button")
            XCTAssertEqual(menuWindow.frame.maxY, anchor.minY, accuracy: 0.5)
            w.close()
        }
    }

    #if os(Linux)
    /// The Linux window path exactly: a Cairo context whose backing scale is in the base
    /// transform (as `LinuxWindow` and `WaylandWindow` make it), so the CTM is in points.
    /// Before the fix the symbol was rendered at 1x here and stretched: a 4-pixel ramp.
    func testWindowContextWithTheScaleOutsideTheCTM() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            for scale: CGFloat in [1.5, 2] {
                let side = 20 * scale
                let w = Int32(side.rounded(.up)), h = w
                guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h), let cr = cairo_create(surface) else { return XCTFail("no cairo surface") }
                defer { cairo_destroy(cr); cairo_surface_destroy(surface) }
                let flip = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: 20 * scale)
                let ctx = CGContext(cairo: cr, baseTransform: flip, width: Int(w), height: Int(h))
                XCTAssertEqual(ctx.ctm, .identity, "the window's scale is outside the CTM")
                XCTAssertEqual(NSImage._deviceScale(ctx, hints: nil), scale, accuracy: 0.001)
                let saved = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                stopSymbol()?.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
                // And through the template tint (a button's or toolbar item's symbol).
                if let tinted = stopSymbol()?._tintedForTemplate(.black, size: NSSize(width: 16, height: 16)) {
                    XCTAssertEqual(tinted.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, Int((16 * scale).rounded()), "the tint renders at the window's scale")
                } else { XCTFail("no tint") }
                NSGraphicsContext.current = saved
                cairo_surface_flush(surface)
                guard let data = cairo_image_surface_get_data(surface) else { return XCTFail("no pixels") }
                let stride = Int(cairo_image_surface_get_stride(surface))
                let row = middleRow(scale: scale, heightPoints: 20)
                let p = _EdgeProfile(width: Int(w)) { x in CGFloat(data[row * stride + x * 4 + 3]) / 255 }
                XCTAssertLessThanOrEqual(p.ramp, 1, "\(scale)x: \(p)")
                XCTAssertEqual(p.ink, 9 * scale, accuracy: 0.6, "\(scale)x: \(p)")
            }
        }
    }
    #endif
    #endif
}
