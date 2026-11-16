// Milestone 3b (AppKit side): window chrome derived from NSWindow properties, drag
// regions for content that extends into the title bar, and NSVisualEffectView backdrops.

import XCTest
@testable import AppKit

final class WindowChromeTests: XCTestCase, @unchecked Sendable {
    @MainActor private func host(_ w: NSWindow) -> HostWindow { Mirror(reflecting: w).descendant("_platform") as! HostWindow }

    func testChromeFollowsWindowProperties() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            var c = host(w).chrome
            XCTAssertTrue(c.extendsContentIntoTitleBar)
            XCTAssertFalse(c.hidesTitle)
            XCTAssertFalse(c.isTransparent)
            XCTAssertEqual(c.backdrop, .none)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isOpaque = false
            w.hasShadow = false
            w.isMovableByWindowBackground = true
            c = host(w).chrome
            XCTAssertTrue(c.hidesTitle && c.transparentTitleBar && c.isTransparent && c.movableByBackground)
            XCTAssertFalse(c.hasShadow)
            // A borderless window hides its title and covers the frame.
            let b = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
            XCTAssertTrue(host(b).chrome.hidesTitle)
            XCTAssertTrue(host(b).chrome.extendsContentIntoTitleBar)
            w.close(); b.close()
        }
    }

    func testDragRegions() throws {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            let button = NSButton(title: "Close", target: nil, action: nil)
            button.frame = NSRect(x: 10, y: 160, width: 80, height: 28)
            w.contentView!.addSubview(button)
            // Top band drags the window; a button there does not; the body is content. The
            // point is clear of the standard buttons in either style (traffic lights at the
            // left, Windows caption buttons over the trailing 138 points; ADR-0022).
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 120, y: 190)), .caption)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 20, y: 170)), .client)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 150, y: 100)), .client)
            w.isMovableByWindowBackground = true
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 150, y: 100)), .caption)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 20, y: 170)), .client)
            w.close()
        }
    }

    func testVisualEffectViewRequestsBackdropAndDrawsTint() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            effect.material = .sidebar
            w.contentView!.addSubview(effect)
            XCTAssertEqual(host(w).chrome.backdrop, .mica)
            effect.material = .hudWindow
            XCTAssertEqual(host(w).chrome.backdrop, .acrylic)
            effect.blendingMode = .withinWindow
            XCTAssertEqual(host(w).chrome.backdrop, .none)
            effect.material = .sidebar
            effect.blendingMode = .behindWindow
            w.isOpaque = false
            w.backgroundColor = .clear
            w.makeKeyAndOrderFront(nil)
            w.display()
            // The tint is translucent: the pixel is lighter than the HUD material would be but not opaque white.
            let platform = host(w)
            let image = platform.lastImage!
            let data = _pixels(image)
            let i = (image.height - 1 - 100) * image.bytesPerRow + 100 * 4
            let alpha = data[i + 3]
            XCTAssertGreaterThan(alpha, 20)
            XCTAssertLessThan(alpha, 250)
            effect.removeFromSuperview()
            XCTAssertEqual(host(w).chrome.backdrop, .none, "a removed effect view no longer asks for the backdrop")
            w.close()
        }
    }

    func testHiddenEffectViewDropsTheBackdrop() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let holder = NSView(frame: w.contentView!.bounds)
            let effect = NSVisualEffectView(frame: holder.bounds)
            effect.material = .hudWindow
            holder.addSubview(effect)
            w.contentView!.addSubview(holder)
            XCTAssertEqual(host(w).chrome.backdrop, .acrylic)
            effect.isHidden = true
            XCTAssertEqual(host(w).chrome.backdrop, .none, "FramelessWindow's Backdrop checkbox hides the view")
            effect.isHidden = false
            XCTAssertEqual(host(w).chrome.backdrop, .acrylic)
            holder.isHidden = true
            XCTAssertEqual(host(w).chrome.backdrop, .none, "under a hidden ancestor")
            holder.isHidden = false
            XCTAssertEqual(host(w).chrome.backdrop, .acrylic)
            w.close()
        }
    }

    /// FramelessWindow: a non-opaque window whose effect view is clipped to the card's
    /// rounded corners. DWM's backdrop would fill the rectangle, so Win32 drops it there.
    func testRoundedEffectViewOnANonOpaqueWindowKeepsTheCornersClear() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            let card = _RoundedCardView(frame: w.contentView!.bounds)
            w.contentView = card
            let effect = NSVisualEffectView(frame: card.bounds.insetBy(dx: 1, dy: 1))
            effect.material = .hudWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 22
            effect.layer?.masksToBounds = true
            card.addSubview(effect)
            var c = host(w).chrome
            XCTAssertEqual(c.backdrop, .acrylic)
            XCTAssertTrue(c.isTransparent)
            XCTAssertTrue(c.backdropCoversWindow)
            XCTAssertEqual(c.backdropCornerRadius, 22)
            XCTAssertEqual(Win32WindowPolicy.systemBackdrop(for: c), .none, "DWM cannot clip its backdrop to 22 pt corners")
            XCTAssertTrue(Win32WindowPolicy.hidesBorder(styleMask: w.styleMask, chrome: c))
            // Square corners (or DWM's own radius) over the whole window keep the backdrop.
            effect.layer?.cornerRadius = 0
            effect.frame = card.bounds
            c = host(w).chrome
            XCTAssertEqual(c.backdropCornerRadius, 0)
            XCTAssertEqual(Win32WindowPolicy.systemBackdrop(for: c), .acrylic)
            // Part of the window only: the rest would show the backdrop.
            effect.frame = NSRect(x: 0, y: 0, width: 80, height: 120)
            c = host(w).chrome
            XCTAssertFalse(c.backdropCoversWindow)
            XCTAssertEqual(Win32WindowPolicy.systemBackdrop(for: c), .none)
            // An opaque window covers its rectangle itself.
            w.isOpaque = true
            XCTAssertEqual(Win32WindowPolicy.systemBackdrop(for: host(w).chrome), .acrylic)
            XCTAssertFalse(Win32WindowPolicy.hidesBorder(styleMask: w.styleMask, chrome: host(w).chrome))
            w.isOpaque = false

            // The pixels: outside the rounded card the window is at alpha 0.
            effect.frame = card.bounds.insetBy(dx: 1, dy: 1)
            effect.layer?.cornerRadius = 22
            w.makeKeyAndOrderFront(nil)
            w.display()
            let image = host(w).lastImage!
            let data = _pixels(image)
            let scale = image.width / 200
            @MainActor func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * scale) * image.bytesPerRow + (x * scale) * 4 + 3] }
            XCTAssertEqual(alpha(1, 1), 0, "top-left corner outside the card")
            XCTAssertEqual(alpha(198, 118), 0, "bottom-right corner outside the card")
            XCTAssertGreaterThan(alpha(100, 60), 100, "inside the card")
            // A repaint clears again rather than piling translucent frames up.
            let before = alpha(100, 60)
            card.needsDisplay = true
            w.display()
            let again = _pixels(host(w).lastImage!)
            XCTAssertEqual(again[(60 * scale) * image.bytesPerRow + (100 * scale) * 4 + 3], before)
            XCTAssertEqual(again[(1 * scale) * image.bytesPerRow + (1 * scale) * 4 + 3], 0)
            w.close()
        }
    }
}

extension WindowChromeTests {
    /// CGContextClearRect sets the rect to transparent black whatever was drawn there (on
    /// Windows a clear-colour fill blended source-over and changed nothing), and leaves
    /// the rest alone. The host backend clears non-opaque windows with it every frame.
    func testContextClearZeroesTheRect() throws {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 0.9))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        ctx.clear(CGRect(x: 0, y: 0, width: 4, height: 8))
        let image = ctx.makeImage()!
        let data = _pixels(image)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[y * image.bytesPerRow + x * 4 + 3] }
        XCTAssertEqual(alpha(1, 4), 0, "cleared")
        XCTAssertEqual(data[4 * image.bytesPerRow + 1 * 4], 0, "cleared to black too")
        XCTAssertGreaterThan(alpha(6, 4), 200, "outside the rect untouched")
    }

    /// FramelessWindow with the Backdrop checkbox off: the effect view is hidden and the
    /// card paints an opaque fill, so a card pixel is exactly the fill colour (nothing of
    /// the hidden material or the desktop behind it shows through) while the corners
    /// outside the card stay at alpha 0. The PC measured ~7 % show-through with the old
    /// 0.92 fill.
    func testBackdropOffCardIsExactlyItsOpaqueFill() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            defer { w.close() }
            w.titlebarAppearsTransparent = true
            w.isOpaque = false
            w.backgroundColor = .clear
            let card = _RoundedCardView(frame: w.contentView!.bounds)
            card.fill = NSColor(srgbRed: 41 / 255, green: 56 / 255, blue: 92 / 255, alpha: 1)
            w.contentView = card
            let effect = NSVisualEffectView(frame: card.bounds.insetBy(dx: 1, dy: 1))
            effect.material = .hudWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 22
            effect.layer?.masksToBounds = true
            card.addSubview(effect)
            w.makeKeyAndOrderFront(nil)
            effect.isHidden = true                 // Backdrop off
            XCTAssertEqual(host(w).chrome.backdrop, .none)
            w.display()
            let image = host(w).lastImage!
            let data = _pixels(image)
            let scale = image.width / 200
            @MainActor func bgra(_ x: Int, _ y: Int) -> [UInt8] { let i = (y * scale) * image.bytesPerRow + (x * scale) * 4; return Array(data[i..<(i + 4)]) }
            XCTAssertEqual(bgra(100, 60), [92, 56, 41, 255], "the card is its fill, opaque")
            XCTAssertEqual(bgra(30, 100), [92, 56, 41, 255])
            XCTAssertEqual(bgra(1, 1)[3], 0, "the corner outside the card stays clear")
            XCTAssertEqual(bgra(198, 118)[3], 0)
        }
    }
}

/// FramelessWindow's CardView: a rounded translucent card, nothing outside it.
private final class _RoundedCardView: NSView {
    var fill = NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.36, alpha: 0.92)
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 22, yRadius: 22).fill()
    }
}

final class AppearanceTests: XCTestCase, @unchecked Sendable {
    func testWindowBackgroundFollowsTheWindowAppearance() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
            w.makeKeyAndOrderFront(nil)
            let host = w._platformWindow as! HostWindow
            w.display()
            let light = _pixels(host.lastImage!)
            XCTAssertGreaterThan(light[1], 200, "light appearance: a light window background")
            w.appearance = NSAppearance(named: .darkAqua)
            w.display()
            let dark = _pixels(host.lastImage!)
            XCTAssertLessThan(dark[1], 80, "dark appearance: the window fill resolves dark, like the text drawn over it")
            w.close()
        }
    }

    func testEffectiveAppearanceInheritsAndColoursResolve() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            w.contentView!.addSubview(v)
            XCTAssertEqual(v.effectiveAppearance.name, .aqua)
            w.appearance = NSAppearance(named: .darkAqua)
            XCTAssertEqual(v.effectiveAppearance.name, .darkAqua)
            XCTAssertTrue(v.effectiveAppearance.isDark)
            v.appearance = NSAppearance(named: .aqua)
            XCTAssertEqual(v.effectiveAppearance.name, .aqua)
            XCTAssertNil(NSAppearance(named: NSAppearance.Name("bogus")))
            XCTAssertEqual(NSAppearance(named: .darkAqua)!.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
            XCTAssertEqual(NSAppearance(named: .aqua)!.bestMatch(from: [.vibrantDark, .darkAqua]), .darkAqua)
            // Semantic colours follow the drawing appearance.
            XCTAssertEqual(NSColor.textBackgroundColor.redComponent, 1)
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                XCTAssertLessThan(NSColor.textBackgroundColor.redComponent, 0.2)
                XCTAssertGreaterThan(NSColor.labelColor.redComponent, 0.9)
            }
            XCTAssertEqual(NSColor.textBackgroundColor.redComponent, 1)
            w.close()
        }
    }

    func testHUDEffectViewDrawsFieldsDark() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            effect.material = .hudWindow
            XCTAssertEqual(effect.effectiveAppearance.name, .vibrantDark)
            let field = NSTextField()
            field.frame = NSRect(x: 20, y: 40, width: 120, height: 24)
            effect.addSubview(field)
            XCTAssertTrue(field.effectiveAppearance.isDark)
            w.contentView!.addSubview(effect)
            w.makeKeyAndOrderFront(nil)
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            let image = platform.lastImage!
            let data = _pixels(image)
            @MainActor func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
                let row = image.height - 1 - y * 2
                let i = row * image.bytesPerRow + x * 2 * 4
                return (data[i + 2], data[i + 1], data[i])
            }
            let inField = pixel(80, 52)
            XCTAssertLessThan(inField.r, 90, "the field bezel is dark on a HUD material")
            // A field on a plain window stays light.
            let light = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let f2 = NSTextField()
            f2.frame = NSRect(x: 20, y: 40, width: 120, height: 24)
            light.contentView!.addSubview(f2)
            light.makeKeyAndOrderFront(nil)
            light.display()
            let p2 = Mirror(reflecting: light).descendant("_platform") as! HostWindow
            let d2 = _pixels(p2.lastImage!)
            let i2 = (p2.lastImage!.height - 1 - 52 * 2) * p2.lastImage!.bytesPerRow + 80 * 2 * 4
            XCTAssertGreaterThan(d2[i2 + 2], 200)
            w.close(); light.close()
        }
    }
}


