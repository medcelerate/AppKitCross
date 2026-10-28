import XCTest
@testable import AppKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A view that fills itself with a color and records the rects it was asked to draw.
@MainActor
final class ColorView: NSView {
    var color: NSColor
    var drawnRects: [NSRect] = []
    var mouseDowns: [NSPoint] = []
    var keyDowns: [String] = []
    var flipped = false

    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { flipped }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        drawnRects.append(dirtyRect)
        color.setFill()
        NSBezierPath.fill(bounds)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDowns.append(convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        keyDowns.append(event.characters ?? "")
    }
}

@MainActor
final class RecordingDelegate: NSObject, NSWindowDelegate, NSApplicationDelegate {
    var events: [String] = []
    var allowClose = true
    func windowDidResize(_ notification: Notification) { events.append("resize") }
    func windowDidBecomeKey(_ notification: Notification) { events.append("key") }
    func windowDidResignKey(_ notification: Notification) { events.append("resignKey") }
    func windowWillClose(_ notification: Notification) { events.append("close") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { allowClose }
    func applicationDidFinishLaunching(_ notification: Notification) { events.append("launched") }
}

@MainActor
final class Milestone1Tests: XCTestCase {

    private func makeWindow(_ rect: NSRect = NSRect(x: 100, y: 100, width: 400, height: 300)) -> NSWindow {
        NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    }

    private var host: HostBackend { Platform.backend as! HostBackend }

    func testWindowGeometry() {
        let w = makeWindow()
        XCTAssertEqual(w.contentView?.frame, NSRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(w.contentRect(forFrameRect: w.frame).size, NSSize(width: 400, height: 300))
        XCTAssertEqual(w.frame.height, 300 + HostWindow.titleBarHeight)
        XCTAssertEqual(w.frame.origin, NSPoint(x: 100, y: 100))
        XCTAssertEqual(w.convertToScreen(NSRect(x: 1, y: 2, width: 3, height: 4)), NSRect(x: 101, y: 102, width: 3, height: 4))
        XCTAssertEqual(w.convertPoint(fromScreen: NSPoint(x: 101, y: 102)), NSPoint(x: 1, y: 2))
        XCTAssertEqual(w.backingScaleFactor, 2)
        XCTAssertTrue(NSApplication.shared.windows.contains { $0 === w })
        w.close()
        XCTAssertFalse(NSApplication.shared.windows.contains { $0 === w })
    }

    func testTitleAndVisibility() {
        let w = makeWindow()
        w.title = "Hello"
        XCTAssertEqual(w.title, "Hello")
        XCTAssertFalse(w.isVisible)
        w.makeKeyAndOrderFront(nil)
        XCTAssertTrue(w.isVisible)
        XCTAssertTrue(w.isKeyWindow)
        XCTAssertTrue(w.isMainWindow)
        XCTAssertTrue(NSApplication.shared.keyWindow === w)
        w.orderOut(nil)
        XCTAssertFalse(w.isVisible)
        XCTAssertFalse(w.isKeyWindow)
        w.close()
    }

    func testResizeAutoresizesContentAndNotifiesDelegate() {
        let w = makeWindow()
        let d = RecordingDelegate()
        w.delegate = d
        let child = ColorView(frame: NSRect(x: 10, y: 10, width: 100, height: 50), color: .red)
        child.autoresizingMask = [.width, .maxYMargin]
        w.contentView!.addSubview(child)
        w.setContentSize(NSSize(width: 600, height: 300))
        XCTAssertEqual(w.contentView?.frame.size, NSSize(width: 600, height: 300))
        XCTAssertEqual(child.frame, NSRect(x: 10, y: 10, width: 300, height: 50))
        XCTAssertEqual(d.events, ["resize"])
        w.close()
        XCTAssertEqual(d.events, ["resize", "close"])
    }

    func testAutoresizingMargins() {
        let w = makeWindow(NSRect(x: 0, y: 0, width: 200, height: 200))
        let v = NSView(frame: NSRect(x: 50, y: 50, width: 100, height: 100))
        v.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        w.contentView!.addSubview(v)
        w.setContentSize(NSSize(width: 400, height: 300))
        // Both margins flexible and equal: the view stays centred.
        XCTAssertEqual(v.frame, NSRect(x: 150, y: 100, width: 100, height: 100))
        w.close()
    }

    func testCoordinateConversionAndHitTesting() {
        let w = makeWindow(NSRect(x: 0, y: 0, width: 200, height: 200))
        let outer = ColorView(frame: NSRect(x: 20, y: 20, width: 100, height: 100), color: .blue)
        let inner = ColorView(frame: NSRect(x: 10, y: 10, width: 50, height: 50), color: .green)
        inner.flipped = true
        w.contentView!.addSubview(outer)
        outer.addSubview(inner)
        // inner's origin (10,10) in outer -> (30,30) in the window
        XCTAssertEqual(inner.convert(NSPoint.zero, to: nil), NSPoint(x: 30, y: 80))     // flipped: bounds origin is the top-left
        XCTAssertEqual(inner.convert(NSPoint(x: 0, y: 50), to: nil), NSPoint(x: 30, y: 30))
        XCTAssertEqual(outer.convert(NSPoint(x: 30, y: 30), from: nil), NSPoint(x: 10, y: 10))
        XCTAssertEqual(inner.convert(NSRect(x: 0, y: 0, width: 50, height: 50), to: nil), NSRect(x: 30, y: 30, width: 50, height: 50))
        XCTAssertTrue(w.contentView!.hitTest(NSPoint(x: 35, y: 35)) === inner)
        XCTAssertTrue(w.contentView!.hitTest(NSPoint(x: 25, y: 25)) === outer)
        XCTAssertTrue(w.contentView!.hitTest(NSPoint(x: 5, y: 5)) === w.contentView)
        XCTAssertNil(w.contentView!.hitTest(NSPoint(x: -1, y: 5)))
        inner.isHidden = true
        XCTAssertTrue(w.contentView!.hitTest(NSPoint(x: 35, y: 35)) === outer)
        w.close()
    }

    func testEventDispatchAndFirstResponder() {
        let w = makeWindow(NSRect(x: 0, y: 0, width: 200, height: 200))
        let v = ColorView(frame: NSRect(x: 50, y: 50, width: 100, height: 100), color: .red)
        w.contentView!.addSubview(v)
        w.makeKeyAndOrderFront(nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 60, y: 70), modifierFlags: [], timestamp: 1,
                                      windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        XCTAssertTrue(down.window === w)
        NSApplication.shared.sendEvent(down)
        XCTAssertEqual(v.mouseDowns, [NSPoint(x: 10, y: 20)])
        XCTAssertTrue(w.firstResponder === v, "clicking a view that accepts first responder makes it first responder")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2, windowNumber: w.windowNumber,
                                   context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        NSApplication.shared.sendEvent(key)
        XCTAssertEqual(v.keyDowns, ["a"])
        XCTAssertTrue(NSApplication.shared.currentEvent === key)
        w.close()
    }

    func testCloseCanBeVetoedByDelegate() {
        let w = makeWindow()
        let d = RecordingDelegate()
        d.allowClose = false
        w.delegate = d
        w.performClose(nil)
        XCTAssertTrue(NSApplication.shared.windows.contains { $0 === w })
        d.allowClose = true
        w.performClose(nil)
        XCTAssertFalse(NSApplication.shared.windows.contains { $0 === w })
        XCTAssertEqual(d.events, ["close"])
    }

    func testApplicationLifecycle() {
        let app = NSApplication.shared
        XCTAssertTrue(NSApp === app)
        let d = RecordingDelegate()
        app.delegate = d
        app.finishLaunching()
        XCTAssertEqual(d.events, ["launched"])
        XCTAssertTrue(app.isActive)
        app.delegate = nil
    }

    func testResponderChain() {
        let w = makeWindow()
        let a = NSView(frame: .zero), b = NSView(frame: .zero)
        w.contentView!.addSubview(a)
        a.addSubview(b)
        XCTAssertTrue(b.nextResponder === a)
        XCTAssertTrue(a.nextResponder === w.contentView)
        XCTAssertTrue(w.contentView?.nextResponder === w)
        XCTAssertTrue(b.window === w)
        b.removeFromSuperview()
        XCTAssertNil(b.window)
        XCTAssertNil(b.nextResponder)
        w.close()
    }

    func testNSColorAndBezierPath() {
        let c = NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
        XCTAssertEqual(c.redComponent, 0.2)
        XCTAssertEqual(c.alphaComponent, 0.5)
        XCTAssertEqual(c.withAlphaComponent(1).alphaComponent, 1)
        XCTAssertEqual(NSColor.white.blended(withFraction: 0.5, of: .black)?.redComponent, 0.5)
        XCTAssertEqual(NSColor(hue: 0, saturation: 1, brightness: 1, alpha: 1), NSColor.red)
        let p = NSBezierPath(rect: NSRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(p.elementCount, 5)
        XCTAssertEqual(p.bounds, NSRect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertTrue(p.contains(NSPoint(x: 2, y: 3)))
        XCTAssertFalse(p.contains(NSPoint(x: 10, y: 10)))
        let oval = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(oval.bounds.width, 10, accuracy: 0.01)
        XCTAssertEqual(oval.bounds.height, 10, accuracy: 0.01)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: 0, y: 0), radius: 10, startAngle: 0, endAngle: 90)
        XCTAssertEqual(arc.currentPoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(arc.currentPoint.y, 10, accuracy: 0.001)
    }

    #if canImport(CoreGraphics)
    func testDrawingProducesPixels() {
        let w = makeWindow(NSRect(x: 0, y: 0, width: 100, height: 100))
        w.backgroundColor = .white
        let v = ColorView(frame: NSRect(x: 0, y: 0, width: 50, height: 50), color: .red)
        let flipped = ColorView(frame: NSRect(x: 50, y: 50, width: 50, height: 50), color: .blue)
        flipped.flipped = true
        w.contentView!.addSubview(v)
        w.contentView!.addSubview(flipped)
        w.makeKeyAndOrderFront(nil)
        w.display()
        XCTAssertEqual(v.drawnRects.last, NSRect(x: 0, y: 0, width: 50, height: 50))
        let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
        XCTAssertNotNil(platform)
        guard let image = platform?.lastImage else { return XCTFail("no image") }
        XCTAssertEqual(image.width, 200)   // 100 points at 2x
        XCTAssertEqual(image.height, 200)
        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
            // y is in AppKit coordinates (bottom-left origin); CG images are top-down.
            let data = image.dataProvider!.data! as Data
            let row = image.height - 1 - y
            let i = row * image.bytesPerRow + x * 4
            return (data[i + 2], data[i + 1], data[i])   // BGRA little-endian premultiplied
        }
        let red = pixel(25 * 2, 25 * 2)
        XCTAssertGreaterThan(red.r, 200); XCTAssertLessThan(red.g, 30); XCTAssertLessThan(red.b, 30)
        let blue = pixel(75 * 2, 75 * 2)
        XCTAssertLessThan(blue.r, 30); XCTAssertGreaterThan(blue.b, 200)
        let white = pixel(75 * 2, 25 * 2)
        XCTAssertGreaterThan(white.r, 200); XCTAssertGreaterThan(white.g, 200); XCTAssertGreaterThan(white.b, 200)
        w.close()
    }
    #endif
}

@MainActor
final class TextDrawingTests: XCTestCase {
    func testFontsAndMeasurement() {
        let f = NSFont.systemFont(ofSize: 13)
        XCTAssertEqual(f.pointSize, 13)
        XCTAssertGreaterThan(f.ascender, 0)
        XCTAssertLessThan(f.descender, 0)
        XCTAssertGreaterThan(f.capHeight, 0)
        let bold = NSFont.boldSystemFont(ofSize: 20)
        XCTAssertEqual(bold.pointSize, 20)
        XCTAssertNil(NSFont(name: "NoSuchFontFamily-Xyz", size: 12))
        let size = "Hello, world".size(withAttributes: [.font: f])
        XCTAssertGreaterThan(size.width, 40)
        XCTAssertGreaterThan(size.height, 10)
        let two = "a\nb".size(withAttributes: [.font: f])
        XCTAssertGreaterThan(two.height, size.height * 1.5)
        XCTAssertEqual(f.withSize(30).pointSize, 30)
    }

    #if canImport(CoreGraphics)
    func testTextDrawsPixelsInBothOrientations() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        w.backgroundColor = .white
        final class TextView: NSView {
            var flip = false
            override var isFlipped: Bool { flip }
            override func draw(_ dirtyRect: NSRect) {
                "Wg".draw(at: NSPoint(x: 10, y: 10), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.black])
            }
        }
        let plain = TextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let flipped = TextView(frame: NSRect(x: 100, y: 0, width: 100, height: 100))
        flipped.flip = true
        w.contentView!.addSubview(plain)
        w.contentView!.addSubview(flipped)
        w.makeKeyAndOrderFront(nil)
        w.display()
        let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
        guard let image = platform?.lastImage else { return XCTFail("no image") }
        let data = image.dataProvider!.data! as Data
        func dark(x: Int, y: Int) -> Bool {   // AppKit coords in points
            let row = image.height - 1 - y * 2, i = row * image.bytesPerRow + x * 2 * 4
            return data[i] < 128 && data[i + 1] < 128 && data[i + 2] < 128
        }
        func anyDark(_ xs: Range<Int>, _ ys: Range<Int>) -> Bool {
            for x in xs { for y in ys where dark(x: x, y: y) { return true } }
            return false
        }
        // Non-flipped: text box bottom-left at (10,10), glyphs occupy roughly y 10...50.
        XCTAssertTrue(anyDark(10..<60, 12..<50), "text missing in non-flipped view")
        XCTAssertFalse(anyDark(10..<60, 60..<100), "text leaked above its box in non-flipped view")
        // Flipped: box top-left at (10,10) from the top, so glyphs are near the top: AppKit y 50...90.
        XCTAssertTrue(anyDark(110..<160, 52..<88), "text missing in flipped view")
        XCTAssertFalse(anyDark(110..<160, 0..<40), "text at the wrong end of the flipped view")
        w.close()
    }
    #endif
}

@MainActor
final class ControlTests: XCTestCase {
    final class Target: NSObject, NSSelectorHandling {
        var received: [String] = []
        func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
            received.append("\(action)")
            return true
        }
    }

    func testButtonSendsActionToTargetOnClick() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let target = Target()
        let button = NSButton(title: "Press", target: target, action: Selector(("press:")))
        XCTAssertGreaterThan(button.frame.width, 40, "sizeToFit gives the button a width")
        button.setFrameOrigin(NSPoint(x: 20, y: 20))
        w.contentView!.addSubview(button)
        w.makeKeyAndOrderFront(nil)
        let inside = NSPoint(x: button.frame.midX, y: button.frame.midY)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: inside, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: inside, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.sendEvent(down)
        XCTAssertTrue(button.isHighlighted)
        NSApp.sendEvent(up)
        XCTAssertFalse(button.isHighlighted)
        XCTAssertEqual(target.received, ["press:"])
        // Releasing outside cancels.
        NSApp.sendEvent(down)
        let outside = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 290, y: 190), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0)!
        NSApp.sendEvent(outside)
        XCTAssertEqual(target.received.count, 1)
        button.isEnabled = false
        button.performClick(nil)
        XCTAssertEqual(target.received.count, 1, "disabled buttons do not fire")
        w.close()
    }

    func testCheckboxTogglesStateAndClosureHandlers() {
        let box = NSButton(checkboxWithTitle: "Enable", target: nil, action: Selector(("toggle:")))
        XCTAssertEqual(box.state, .off)
        var fired = 0
        let handler = NSObject()
        handler.setActionHandler(for: Selector(("toggle:"))) { _ in fired += 1 }
        box.target = handler
        box.performClick(nil)
        XCTAssertEqual(box.state, .on)
        XCTAssertEqual(fired, 1)
        box.performClick(nil)
        XCTAssertEqual(box.state, .off)
        box.allowsMixedState = true
        box.state = .mixed
        box.setNextState()
        XCTAssertEqual(box.state, .on)
    }

    func testActionWalksResponderChainAndKeyEquivalent() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        final class Host: NSView, NSSelectorHandling {
            var got = 0
            override var acceptsFirstResponder: Bool { true }
            func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
                guard action == Selector(("go:")) else { return false }
                got += 1
                return true
            }
        }
        let host = Host(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        w.contentView = host
        let button = NSButton(title: "Go", target: nil, action: Selector(("go:")))
        button.keyEquivalent = "\r"
        host.addSubview(button)
        w.makeKeyAndOrderFront(nil)
        XCTAssertTrue(w.makeFirstResponder(host))
        button.performClick(nil)
        XCTAssertEqual(host.got, 1, "nil target reaches the first responder through the responder chain")
        let ret = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        NSApp.sendEvent(ret)
        XCTAssertEqual(host.got, 2, "return key triggers the default button")
        w.close()
    }

    func testControlValuesAndCell() {
        let c = NSControl(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertNil(c.cell)
        c.cell = NSCell(textCell: "42")
        XCTAssertEqual(c.stringValue, "42")
        XCTAssertEqual(c.integerValue, 42)
        c.doubleValue = 2.5
        XCTAssertEqual(c.stringValue, "2.5")
        XCTAssertEqual(c.floatValue, 2.5)
        c.isEnabled = false
        XCTAssertFalse(c.cell!.isEnabled)
    }

    #if canImport(CoreGraphics)
    func testButtonDrawsBezel() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        w.backgroundColor = .white
        let b = NSButton(title: "OK", target: nil, action: nil)
        b.frame = NSRect(x: 20, y: 30, width: 120, height: 32)
        w.contentView!.addSubview(b)
        w.makeKeyAndOrderFront(nil)
        w.display()
        let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
        guard let image = platform?.lastImage else { return XCTFail("no image") }
        let data = image.dataProvider!.data! as Data
        func px(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let row = image.height - 1 - y * 2, i = row * image.bytesPerRow + x * 2 * 4
            return (data[i + 2], data[i + 1], data[i])
        }
        // Some pixel on the border is not white; the far background is white.
        var nonWhite = false
        for x in 20..<140 { let p = px(x, 30); if p.0 < 250 || p.1 < 250 || p.2 < 250 { nonWhite = true; break } }
        XCTAssertTrue(nonWhite, "button border drawn")
        let bg = px(180, 90)
        XCTAssertGreaterThan(bg.0, 250)
        w.close()
    }
    #endif
}
