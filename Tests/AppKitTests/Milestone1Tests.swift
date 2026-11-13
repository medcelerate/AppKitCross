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

final class Milestone1Tests: XCTestCase, @unchecked Sendable {

    @MainActor private func makeWindow(_ rect: NSRect = NSRect(x: 100, y: 100, width: 400, height: 300)) -> NSWindow {
        NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    }

    @MainActor private var host: HostBackend { Platform.backend as! HostBackend }

    func testWindowGeometry() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            XCTAssertEqual(w.contentView?.frame, NSRect(x: 0, y: 0, width: 400, height: 300))
            XCTAssertEqual(w.contentRect(forFrameRect: w.frame).size, NSSize(width: 400, height: 300))
            // The frame is the content plus what the backend draws around it: the host's
            // 28pt title bar; on Win32 the system caption and the invisible resize borders.
            XCTAssertEqual(w.frame, w.frameRect(forContentRect: NSRect(x: 100, y: 100, width: 400, height: 300)))
            XCTAssertEqual(w.contentRect(forFrameRect: w.frame).origin, NSPoint(x: 100, y: 100))
            if Platform.backend is HostBackend {
                XCTAssertEqual(w.frame.height, 300 + HostWindow.titleBarHeight)
                XCTAssertEqual(w.frame.origin, NSPoint(x: 100, y: 100))
            }
            XCTAssertEqual(w.convertToScreen(NSRect(x: 1, y: 2, width: 3, height: 4)), NSRect(x: 101, y: 102, width: 3, height: 4))
            XCTAssertEqual(w.convertPoint(fromScreen: NSPoint(x: 101, y: 102)), NSPoint(x: 1, y: 2))
            // The host backend simulates a 2x display; a platform window takes its monitor's scale.
            XCTAssertEqual(w.backingScaleFactor, Platform.backend is HostBackend ? 2 : w.screen?.backingScaleFactor ?? 1)
            XCTAssertTrue(NSApplication.shared.windows.contains { $0 === w })
            w.close()
            XCTAssertFalse(NSApplication.shared.windows.contains { $0 === w })
        }
    }

    func testTitleAndVisibility() {
        MainActor.assumeIsolated {
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
    }

    func testResizeAutoresizesContentAndNotifiesDelegate() {
        MainActor.assumeIsolated {
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
    }

    func testAutoresizingMargins() {
        MainActor.assumeIsolated {
            let w = makeWindow(NSRect(x: 0, y: 0, width: 200, height: 200))
            let v = NSView(frame: NSRect(x: 50, y: 50, width: 100, height: 100))
            v.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            w.contentView!.addSubview(v)
            w.setContentSize(NSSize(width: 400, height: 300))
            // Both margins flexible and equal: the view stays centred.
            XCTAssertEqual(v.frame, NSRect(x: 150, y: 100, width: 100, height: 100))
            w.close()
        }
    }

    func testCoordinateConversionAndHitTesting() {
        MainActor.assumeIsolated {
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
    }

    func testEventDispatchAndFirstResponder() {
        MainActor.assumeIsolated {
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
    }

    func testCloseCanBeVetoedByDelegate() {
        MainActor.assumeIsolated {
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
    }

    func testApplicationLifecycle() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            XCTAssertTrue(NSApp === app)
            let d = RecordingDelegate()
            app.delegate = d
            app.finishLaunching()
            XCTAssertEqual(d.events, ["launched"])
            XCTAssertTrue(app.isActive)
            app.delegate = nil
        }
    }

    func testResponderChain() {
        MainActor.assumeIsolated {
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
    }

    func testNSColorAndBezierPath() {
        MainActor.assumeIsolated {
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
    }

    #if canImport(CoreGraphics)
    func testDrawingProducesPixels() {
        MainActor.assumeIsolated {
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
            @MainActor func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
                // y is in AppKit coordinates (bottom-left origin); CG images are top-down.
                let data = _pixels(image)
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
    }
    #endif
}

final class TextDrawingTests: XCTestCase, @unchecked Sendable {
    func testFontsAndMeasurement() {
        MainActor.assumeIsolated {
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
    }

    #if canImport(CoreGraphics)
    func testTextDrawsPixelsInBothOrientations() {
        MainActor.assumeIsolated {
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
            let data = _pixels(image)
            @MainActor func dark(x: Int, y: Int) -> Bool {   // AppKit coords in points
                let row = image.height - 1 - y * 2, i = row * image.bytesPerRow + x * 2 * 4
                return data[i] < 128 && data[i + 1] < 128 && data[i + 2] < 128
            }
            @MainActor func anyDark(_ xs: Range<Int>, _ ys: Range<Int>) -> Bool {
                for x in xs { for y in ys where dark(x: x, y: y) { return true } }
                return false
            }
            // Non-flipped: text box bottom-left at (10,10), glyphs occupy roughly y 10...50.
            XCTAssertTrue(anyDark(10..<60, 12..<50), "text missing in non-flipped view")
            XCTAssertFalse(anyDark(10..<60, 60..<100), "text leaked above its box in non-flipped view")
            // Flipped: box top-left at (10,10) from the top, so glyphs are near the top: AppKit y 50...90.
            XCTAssertTrue(anyDark(110..<160, 52..<88), "text missing in flipped view")
            // The forbidden band leaves room for fonts whose ascent exceeds the em (Segoe UI).
            XCTAssertFalse(anyDark(110..<160, 0..<30), "text at the wrong end of the flipped view")
            w.close()
        }
    }
    #endif
}

final class ControlTests: XCTestCase, @unchecked Sendable {
    final class Target: NSObject, NSSelectorHandling {
        var received: [String] = []
        func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
            received.append("\(action)")
            return true
        }
    }

    func testButtonSendsActionToTargetOnClick() {
        MainActor.assumeIsolated {
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
    }

    func testCheckboxTogglesStateAndClosureHandlers() {
        MainActor.assumeIsolated {
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
    }

    func testActionWalksResponderChainAndKeyEquivalent() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            final class Host: NSView, NSSelectorHandling {
                var got = 0
                override var acceptsFirstResponder: Bool { true }
                @MainActor func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
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
    }

    func testControlValuesAndCell() {
        MainActor.assumeIsolated {
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
    }

    #if canImport(CoreGraphics)
    func testButtonDrawsBezel() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            let b = NSButton(title: "OK", target: nil, action: nil)
            b.frame = NSRect(x: 20, y: 30, width: 120, height: 32)
            w.contentView!.addSubview(b)
            w.makeKeyAndOrderFront(nil)
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
            guard let image = platform?.lastImage else { return XCTFail("no image") }
            let data = _pixels(image)
            @MainActor func px(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
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
    }
    #endif
}

final class TextFieldTests: XCTestCase, @unchecked Sendable {
    @MainActor private func key(_ chars: String, _ w: NSWindow, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    }

    func testLabelsSizeToFit() {
        MainActor.assumeIsolated {
            let label = NSTextField(labelWithString: "Hello")
            XCTAssertFalse(label.isEditable)
            XCTAssertFalse(label.drawsBackground)
            XCTAssertGreaterThan(label.frame.width, 20)
            XCTAssertGreaterThan(label.frame.height, 10)
            let wrapping = NSTextField(wrappingLabelWithString: "one two three four five six seven eight nine ten eleven twelve")
            wrapping.preferredMaxLayoutWidth = 80
            XCTAssertGreaterThan(wrapping.intrinsicContentSize.height, label.frame.height * 2, "wrapped label is several lines tall")
            XCTAssertLessThanOrEqual(wrapping.intrinsicContentSize.width, 90)
        }
    }

    func testInlineEditingAndAction() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let field = NSTextField(string: "")
            field.frame = NSRect(x: 10, y: 10, width: 200, height: 24)
            w.contentView!.addSubview(field)
            let target = NSObject()
            var actions: [String] = []
            target.setActionHandler(for: Selector(("entered:"))) { s in actions.append((s as? NSTextField)?.stringValue ?? "?") }
            field.target = target
            field.action = Selector(("entered:"))
            nonisolated(unsafe) var changes = 0
            let token = NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification, object: field, queue: nil) { _ in changes += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            w.makeKeyAndOrderFront(nil)
            // Click into the field to start editing.
            let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(click)
            XCTAssertTrue((w.firstResponder as? NSTextView)?.superview === field, "the window's field editor edits the field")
            for ch in "abc" { NSApp.sendEvent(key(String(ch), w)) }
            XCTAssertEqual(field.stringValue, "abc")
            NSApp.sendEvent(key("\u{7F}", w))                       // backspace
            XCTAssertEqual(field.stringValue, "ab")
            NSApp.sendEvent(key("\u{F702}", w))                     // left
            NSApp.sendEvent(key("X", w))
            XCTAssertEqual(field.stringValue, "aXb")
            NSApp.sendEvent(key("a", w, flags: [.command]))         // select all
            NSApp.sendEvent(key("z", w))
            XCTAssertEqual(field.stringValue, "z")
            XCTAssertEqual(changes, 6)
            NSApp.sendEvent(key("\r", w))                           // Enter: ends editing and fires the action
            XCTAssertEqual(actions, ["z"])
            XCTAssertFalse(w.firstResponder === field)
            w.close()
        }
    }
}

final class MenuTests: XCTestCase, @unchecked Sendable {
    final class Handler: NSObject, NSSelectorHandling, NSMenuItemValidation {
        var fired: [String] = []
        var allowSave = true
        func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
            fired.append("\(action)")
            return true
        }
        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            menuItem.action == Selector(("save:")) ? allowSave : true
        }
    }

    func testMainMenuInstallsAndDispatches() {
        MainActor.assumeIsolated {
            let host = Platform.backend as! HostBackend
            let handler = Handler()
            let main = NSMenu(title: "Main")
            let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let fileMenu = NSMenu(title: "File")
            let save = fileMenu.addItem(withTitle: "Save", action: Selector(("save:")), keyEquivalent: "s")
            save.target = handler
            fileMenu.addItem(NSMenuItem.separator())
            let quit = fileMenu.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
            quit.target = handler
            file.submenu = fileMenu
            main.addItem(file)
            NSApp.mainMenu = main
            defer { NSApp.mainMenu = nil }

            let spec = host.mainMenu
            XCTAssertEqual(spec?.items.count, 1)
            XCTAssertEqual(spec?.items.first?.title, "File")
            XCTAssertEqual(spec?.items.first?.submenu?.items.map { $0.title }, ["Save", "", "Quit"])
            XCTAssertEqual(spec?.items.first?.submenu?.items.first?.keyEquivalentLabel, "Ctrl+S")
            XCTAssertTrue(spec!.items.first!.submenu!.items[1].isSeparator)

            // Choosing the item through the platform fires the action.
            host.chooseMenuItem(spec!.items.first!.submenu!.items[0].id)
            XCTAssertEqual(handler.fired, ["save:"])

            // Validation disables the item when the menu opens.
            handler.allowSave = false
            let refreshed = host.openMenu(fileMenu._menuID)
            XCTAssertEqual(refreshed?.items.first?.isEnabled, false)
            XCTAssertFalse(save.isEnabled)
            host.chooseMenuItem(save._commandID)
            XCTAssertEqual(handler.fired.count, 1, "disabled items do not fire")
            handler.allowSave = true

            // Key equivalent through the application.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.makeKeyAndOrderFront(nil)
            let cmdQ = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                        characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
            NSApp.sendEvent(cmdQ)
            XCTAssertEqual(handler.fired, ["save:", "quit:"])
            let plainQ = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                          characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
            NSApp.sendEvent(plainQ)
            XCTAssertEqual(handler.fired.count, 2, "without the modifier the key is not an equivalent")
            w.close()

            // Edits propagate to the platform description.
            save.state = .on
            XCTAssertEqual(host.mainMenu?.items.first?.submenu?.items.first?.isChecked, true)
            XCTAssertTrue(save.menu === fileMenu)
            XCTAssertTrue(fileMenu.supermenu === main)
            XCTAssertEqual(main.index(of: file), 0)
        }
    }
}

final class ScrollViewTests: XCTestCase, @unchecked Sendable {
    func testClipViewScrollsAndConstrains() {
        MainActor.assumeIsolated {
            let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            sv.hasVerticalScroller = true
            sv.hasHorizontalScroller = true
            let doc = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
            sv.documentView = doc
            XCTAssertTrue(sv.contentView.documentView === doc)
            // Both scrollers needed: the clip shrinks by the scroller width on each side.
            let w = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            XCTAssertEqual(sv.contentSize, NSSize(width: 100 - w, height: 100 - w))
            XCTAssertEqual(sv.verticalScroller?.isHidden, false)
            // A non-flipped document starts at its origin, i.e. showing its bottom (the AppKit gotcha).
            XCTAssertEqual(sv.documentVisibleRect.minY, 0)
            XCTAssertEqual(sv.verticalScroller?.doubleValue, 1)
            sv.contentView.scroll(to: NSPoint(x: 50, y: 100))
            XCTAssertEqual(sv.documentVisibleRect.origin, NSPoint(x: 50, y: 100))
            let clipHeight = 100 - w
            XCTAssertEqual(sv.verticalScroller!.doubleValue, Double((400 - (100 + clipHeight)) / (400 - clipHeight)), accuracy: 0.001)
            // Constrained: cannot scroll past the document.
            sv.contentView.scroll(to: NSPoint(x: 1000, y: -1000))
            XCTAssertEqual(sv.documentVisibleRect.maxX, 300)
            XCTAssertEqual(sv.documentVisibleRect.minY, 0)
            // Small document: scrollers hide and the clip takes the full size.
            doc.frame = NSRect(x: 0, y: 0, width: 50, height: 50)
            XCTAssertEqual(sv.verticalScroller?.isHidden, true)
            XCTAssertEqual(sv.contentSize, NSSize(width: 100, height: 100))
        }
    }

    func testScrollWheelAndKnobDrag() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
            sv.hasVerticalScroller = true
            final class Doc: NSView { override var isFlipped: Bool { true } }
            let doc = Doc(frame: NSRect(x: 0, y: 0, width: 200, height: 1000))
            sv.documentView = doc
            w.contentView!.addSubview(sv)
            w.makeKeyAndOrderFront(nil)
            XCTAssertEqual(sv.documentVisibleRect.minY, 0, "flipped documents start at the top")
            let wheel = NSEvent._scrollEvent(location: NSPoint(x: 50, y: 50), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, deltaX: 0, deltaY: -3, precise: false)
            NSApp.sendEvent(wheel)
            XCTAssertEqual(sv.documentVisibleRect.minY, 30, "three lines down at the default 10 pt line scroll")
            // Drag the knob to the bottom.
            let scroller = sv.verticalScroller!
            let knob = scroller.rect(for: .knob)
            let start = scroller.convert(NSPoint(x: knob.midX, y: knob.midY), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(down)
            XCTAssertEqual(scroller.hitPart, .knob)
            let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: start.x, y: -500), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(drag)
            XCTAssertEqual(scroller.doubleValue, 1)
            XCTAssertEqual(sv.documentVisibleRect.maxY, 1000, accuracy: 0.5)
            w.close()
        }
    }

    #if canImport(CoreGraphics)
    func testPartialRedrawKeepsSiblings() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            let canvas = ColorView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), color: .white)
            w.contentView = canvas
            let a = ColorView(frame: NSRect(x: 10, y: 10, width: 30, height: 30), color: .red)
            let b = ColorView(frame: NSRect(x: 60, y: 60, width: 30, height: 30), color: .blue)
            canvas.addSubview(a); canvas.addSubview(b)
            w.makeKeyAndOrderFront(nil)
            w.display()
            a.drawnRects.removeAll(); b.drawnRects.removeAll(); canvas.drawnRects.removeAll()
            // Invalidate only b: the canvas repaints just that area, a is untouched and stays red.
            b.needsDisplay = true
            w.displayIfNeeded()
            XCTAssertEqual(a.drawnRects.count, 0)
            XCTAssertEqual(b.drawnRects.count, 1)
            XCTAssertEqual(canvas.drawnRects.first, NSRect(x: 60, y: 60, width: 30, height: 30))
            let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
            guard let image = platform?.lastImage else { return XCTFail("no image") }
            let data = _pixels(image)
            @MainActor func px(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
                let row = image.height - 1 - y * 2, i = row * image.bytesPerRow + x * 2 * 4
                return (data[i + 2], data[i + 1], data[i])
            }
            let red = px(25, 25); XCTAssertGreaterThan(red.0, 200); XCTAssertLessThan(red.2, 60)
            let blue = px(75, 75); XCTAssertGreaterThan(blue.2, 200); XCTAssertLessThan(blue.0, 60)
            w.close()
        }
    }
    #endif
}

#if canImport(CoreGraphics)
final class ImageTests: XCTestCase, @unchecked Sendable {
    /// A 4x4 PNG: left half red, right half blue.
    @MainActor private func samplePNG() -> Data {
        let img = NSImage(size: NSSize(width: 4, height: 4))
        img.lockFocus()
        NSColor.red.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 2, height: 4))
        NSColor.blue.setFill(); NSBezierPath.fill(NSRect(x: 2, y: 0, width: 2, height: 4))
        img.unlockFocus()
        let rep = img.representations.first as! NSBitmapImageRep
        return rep.representation(using: .png, properties: [:])!
    }

    func testDecodeAndPixels() {
        MainActor.assumeIsolated {
            let data = samplePNG()
            XCTAssertGreaterThan(data.count, 20)
            guard let image = NSImage(data: data) else { return XCTFail("decode failed") }
            XCTAssertEqual(image.size, NSSize(width: 8, height: 8), "lockFocus renders at 2x")
            let rep = image.representations.first as! NSBitmapImageRep
            XCTAssertEqual(rep.pixelsWide, 8)
            XCTAssertEqual(rep.colorAt(x: 1, y: 1)?.redComponent ?? 0, 1, accuracy: 0.05)
            XCTAssertEqual(rep.colorAt(x: 6, y: 6)?.blueComponent ?? 0, 1, accuracy: 0.05)
            XCTAssertTrue(image.isValid)
        }
    }

    func testImageViewDrawsUprightAndScaled() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            // Top half green, bottom half black, via a drawing handler (y-up).
            let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                NSColor.black.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 10, height: 5))
                NSColor.green.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 5, width: 10, height: 5))
                return true
            }
            let plain = NSImageView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            plain.imageScaling = .scaleAxesIndependently
            plain.image = image
            final class FlippedHost: NSView { override var isFlipped: Bool { true } }
            let host = FlippedHost(frame: NSRect(x: 50, y: 0, width: 50, height: 100))
            let flippedView = NSImageView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))   // top of the flipped host
            flippedView.imageScaling = .scaleAxesIndependently
            flippedView.image = image
            host.addSubview(flippedView)
            w.contentView!.addSubview(plain)
            w.contentView!.addSubview(host)
            w.makeKeyAndOrderFront(nil)
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
            guard let bitmap = platform?.lastImage else { return XCTFail("no image") }
            let data = _pixels(bitmap)
            @MainActor func px(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
                let row = bitmap.height - 1 - y * 2, i = row * bitmap.bytesPerRow + x * 2 * 4
                return (data[i + 2], data[i + 1], data[i])
            }
            // Non-flipped: green on top (y 25..50), black below.
            XCTAssertGreaterThan(px(25, 40).g, 200); XCTAssertLessThan(px(25, 10).g, 50)
            // Flipped host: the image view is in the top half of the window; still green on top.
            XCTAssertGreaterThan(px(75, 90).g, 200); XCTAssertLessThan(px(75, 60).g, 50)
            w.close()
        }
    }
}
#endif

final class SliderAndCursorTests: XCTestCase, @unchecked Sendable {
    func testSliderTracksAndSnaps() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let target = NSObject()
            var values: [Double] = []
            target.setActionHandler(for: Selector(("changed:"))) { s in values.append((s as? NSSlider)?.doubleValue ?? -1) }
            let slider = NSSlider(value: 0, minValue: 0, maxValue: 10, target: target, action: Selector(("changed:")))
            slider.frame = NSRect(x: 10, y: 40, width: 215, height: 21)   // bar 211 wide, knob 15: 196 pt of travel
            w.contentView!.addSubview(slider)
            w.makeKeyAndOrderFront(nil)
            w.display()                                                     // lays out the cell's track rect
            let mid = NSPoint(x: slider.frame.minX + 2 + 7.5 + 98, y: 50)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: mid, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(down)
            XCTAssertEqual(slider.doubleValue, 5, accuracy: 0.2)
            XCTAssertEqual(values.count, 1, "continuous sliders send the action on mouse down")
            let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 1000, y: 50), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(drag)
            XCTAssertEqual(slider.doubleValue, 10)
            slider.numberOfTickMarks = 3
            slider.allowsTickMarkValuesOnly = true
            slider.doubleValue = 6
            let up = NSEvent.mouseEvent(with: .leftMouseUp, location: mid, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 0)!
            NSApp.sendEvent(up)
            XCTAssertEqual(slider.closestTickMarkValue(toValue: 6), 5)
            XCTAssertEqual(slider.tickMarkValue(at: 2), 10)
            w.close()
        }
    }

    func testCursorRectsFollowTheMouse() {
        MainActor.assumeIsolated {
            let host = Platform.backend as! HostBackend
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let field = NSTextField(string: "x")
            field.frame = NSRect(x: 10, y: 10, width: 100, height: 24)
            w.contentView!.addSubview(field)
            w.makeKeyAndOrderFront(nil)
            @MainActor func move(_ p: NSPoint) {
                NSApp.sendEvent(NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!)
            }
            move(NSPoint(x: 50, y: 20))
            XCTAssertEqual(host.cursor, .iBeam)
            XCTAssertTrue(NSCursor.current === NSCursor.iBeam)
            move(NSPoint(x: 150, y: 80))
            XCTAssertEqual(host.cursor, .arrow)
            NSCursor.pointingHand.push()
            XCTAssertEqual(host.cursor, .pointingHand)
            NSCursor.pop()
            XCTAssertEqual(host.cursor, .arrow)
            w.close()
        }
    }
}

final class PasteboardAndAlertTests: XCTestCase, @unchecked Sendable {
    func testPasteboardRoundTripAndTextFieldClipboard() {
        MainActor.assumeIsolated {
            let pb = NSPasteboard.general
            let before = pb.changeCount
            XCTAssertGreaterThan(pb.clearContents(), before)
            XCTAssertTrue(pb.setString("hello", forType: .string))
            XCTAssertEqual(pb.string(forType: .string), "hello")
            XCTAssertEqual(pb.types, [.string])
            XCTAssertEqual(pb.availableType(from: [.png, .string]), .string)
            // Copy and paste through a text field.
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let field = NSTextField(string: "abc")
            field.frame = NSRect(x: 10, y: 10, width: 200, height: 24)
            w.contentView!.addSubview(field)
            w.makeKeyAndOrderFront(nil)
            _ = w.makeFirstResponder(field)
            @MainActor func key(_ c: String, _ flags: NSEvent.ModifierFlags = []) {
                NSApp.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: 0)!)
            }
            key("a", [.command]); key("x", [.command])
            XCTAssertEqual(field.stringValue, "")
            XCTAssertEqual(pb.string(forType: .string), "abc")
            key("v", [.command]); key("v", [.command])
            XCTAssertEqual(field.stringValue, "abcabc")
            w.close()
        }
    }

    func testAlertRunsModalAndReturnsButton() {
        MainActor.assumeIsolated {
            let host = Platform.backend as! HostBackend
            let alert = NSAlert()
            alert.messageText = "Delete the file?"
            alert.informativeText = "This cannot be undone."
            _ = alert.addButton(withTitle: "Delete")
            _ = alert.addButton(withTitle: "Cancel")
            XCTAssertEqual(alert.buttons.count, 2)
            alert.layout()
            XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r", "the first button is the default button")
            // Press "Cancel" once the modal loop is running.
            host.post {
                XCTAssertTrue(NSApp.modalWindow === alert.window)
                alert.buttons[1].performClick(nil)
            }
            let response = alert.runModal()
            XCTAssertEqual(response, .alertSecondButtonReturn)
            XCTAssertNil(NSApp.modalWindow)
            XCTAssertFalse(alert.window.isVisible)
        }
    }
}

final class FileDialogTests: XCTestCase, @unchecked Sendable {
    /// A native dialog stand-in (`HostFileDialog`) receives the panel's options and its
    /// answer becomes the panel's URLs (the package-drawn panel is covered in DocumentTests).
    func testOpenPanelReturnsChosenURLs() {
        MainActor.assumeIsolated {
            let host = Platform.backend as! HostBackend
            let dialog = HostFileDialog(result: [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.jpg")])
            host.fileDialogOverride = dialog
            defer { host.fileDialogOverride = nil }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = true
            panel.allowedFileTypes = ["png", "jpg"]
            panel.title = "Pick images"
            XCTAssertEqual(panel.runModal(), .OK)
            XCTAssertEqual(panel.urls.map { $0.lastPathComponent }, ["a.png", "b.jpg"])
            XCTAssertEqual(panel.url?.lastPathComponent, "a.png")
            let o = dialog.lastOptions!
            XCTAssertFalse(o.isSave)
            XCTAssertTrue(o.allowsMultipleSelection)
            XCTAssertTrue(o.canChooseDirectories)
            XCTAssertEqual(o.allowedExtensions, ["png", "jpg"])
            dialog.result = nil
            XCTAssertEqual(panel.runModal(), .cancel)
            XCTAssertNil(panel.url)
            let save = NSSavePanel()
            save.nameFieldStringValue = "Untitled.txt"
            dialog.result = [URL(fileURLWithPath: "/tmp/Untitled.txt")]
            XCTAssertEqual(save.runModal(), .OK)
            XCTAssertTrue(dialog.lastOptions!.isSave)
            XCTAssertEqual(dialog.lastOptions!.defaultName, "Untitled.txt")
            XCTAssertEqual(save.url?.path, "/tmp/Untitled.txt")
            panel.close(); save.close()
        }
    }
}

final class DefaultButtonTests: XCTestCase, @unchecked Sendable {
    func testDefaultButtonUsesAccentFill() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let plain = NSButton(title: "Later", target: nil, action: nil)
            plain.frame = NSRect(x: 10, y: 30, width: 80, height: 28)
            let def = NSButton(title: "OK", target: nil, action: nil)
            def.keyEquivalent = "\r"
            def.frame = NSRect(x: 110, y: 30, width: 80, height: 28)
            w.contentView!.addSubview(plain); w.contentView!.addSubview(def)
            w.makeKeyAndOrderFront(nil)
            w.displayIfNeeded()
            let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
            guard let image = platform?.lastImage else { return XCTFail("no image") }
            @MainActor func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
                let data = _pixels(image)
                let row = image.height - 1 - y * 2
                let i = row * image.bytesPerRow + x * 2 * 4
                return (data[i + 2], data[i + 1], data[i])
            }
            let a = pixel(115, 32)   // inside the default button, away from the title
            let b = pixel(15, 32)
            XCTAssertGreaterThan(a.b, 200); XCTAssertLessThan(a.r, 80)
            XCTAssertGreaterThan(b.r, 200)
            XCTAssertFalse(NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true).platformWantsMenuBar)
            XCTAssertTrue(w.platformWantsMenuBar)
            w.close()
        }
    }
}
