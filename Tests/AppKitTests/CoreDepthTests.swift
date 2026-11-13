// Core depth (ADR-0036): NSView geometry (flipped, scaled and turned hierarchies, with the
// values macOS answers), key view chains, tool tips, tracking rects, lockFocus and full
// screen mode; NSWindow frame autosave, cascading, resize time, zoom, resize constraints
// and the rest; NSImage named images, representation choice, nine-slice drawing, hit
// testing and coding; NSBitmapImageRep samples and the PNG/TIFF/BMP writers.

import XCTest
@testable import AppKit
import QuartzCore

private final class FlippedView: NSView { override var isFlipped: Bool { true } }
/// A count a notification block bumps (the Linux and Windows toolchains reject mutating a
/// captured var in a Sendable closure).
private final class _CoreDepthCounter: @unchecked Sendable { var value = 0 }

private func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.001) -> Bool { abs(a - b) <= tol }
private func near(_ a: NSPoint, _ b: NSPoint, _ tol: CGFloat = 0.001) -> Bool { near(a.x, b.x, tol) && near(a.y, b.y, tol) }
private func near(_ a: NSRect, _ b: NSRect, _ tol: CGFloat = 0.001) -> Bool {
    near(a.minX, b.minX, tol) && near(a.minY, b.minY, tol) && near(a.width, b.width, tol) && near(a.height, b.height, tol)
}

@MainActor
private func makeWindow(_ rect: NSRect = NSRect(x: 100, y: 100, width: 300, height: 200), style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]) -> NSWindow {
    let w = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    return w
}

@MainActor
private func hostWindow(_ w: NSWindow) -> HostWindow? {
    var m: Mirror? = Mirror(reflecting: w)
    while let cur = m {
        if let h = cur.descendant("_platform") as? HostWindow { return h }
        m = cur.superclassMirror
    }
    return nil
}

/// RGB of a premultiplied-BGRA image at (x, y), y up from the bottom row.
private func rgb(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let data = _pixels(image)
    let i = (image.height - 1 - y) * image.bytesPerRow + x * 4
    return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))
}

@MainActor
private func render(width: Int, height: Int, flipped: Bool = false, _ draw: () -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    if flipped { ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: flipped)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

// MARK: - NSView geometry

final class CoreDepthViewGeometryTests: XCTestCase, @unchecked Sendable {
    /// The hierarchy probed on macOS: root ⊃ flipped a (10,20,200,100) ⊃ b (5,7,50,40).
    @MainActor private func hierarchy() -> (NSView, NSView, NSView) {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let a = FlippedView(frame: NSRect(x: 10, y: 20, width: 200, height: 100))
        root.addSubview(a)
        let b = NSView(frame: NSRect(x: 5, y: 7, width: 50, height: 40))
        a.addSubview(b)
        return (root, a, b)
    }

    func testFlippedHierarchyConversions() {
        MainActor.assumeIsolated {
            let (root, a, b) = hierarchy()
            XCTAssertEqual(b.convert(NSPoint(x: 1, y: 2), to: root), NSPoint(x: 16, y: 75))
            XCTAssertEqual(root.convert(NSPoint(x: 16, y: 75), to: b), NSPoint(x: 1, y: 2))
            // Sizes come back positive across a flip, as AppKit's do.
            XCTAssertEqual(b.convert(NSSize(width: 3, height: 4), to: root), NSSize(width: 3, height: 4))
            XCTAssertEqual(a.convert(NSSize(width: 3, height: 4), to: root), NSSize(width: 3, height: 4))
            XCTAssertEqual(b.convert(NSRect(x: 1, y: 2, width: 3, height: 4), to: root), NSRect(x: 16, y: 75, width: 3, height: 4))
        }
    }

    func testScaledBoundsConvertAndKeepTheirScale() {
        MainActor.assumeIsolated {
            let (root, a, b) = hierarchy()
            a.setBoundsSize(NSSize(width: 100, height: 50))   // 2x
            XCTAssertEqual(b.convert(NSPoint(x: 1, y: 2), to: root), NSPoint(x: 22, y: 30))
            XCTAssertEqual(b.convert(NSSize(width: 3, height: 4), to: root), NSSize(width: 6, height: 8))
            XCTAssertEqual(b.convert(NSRect(x: 1, y: 2, width: 3, height: 4), to: root), NSRect(x: 22, y: 30, width: 6, height: 8))
            XCTAssertTrue(a.isRotatedOrScaledFromBase)
            // A frame resize keeps the scale (bounds grow with it).
            a.setFrameSize(NSSize(width: 400, height: 200))
            XCTAssertEqual(a.bounds.size, NSSize(width: 200, height: 100))
            // scaleUnitSquare and translateOrigin as macOS answers them.
            let d = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            d.scaleUnitSquare(to: NSSize(width: 2, height: 4))
            XCTAssertEqual(d.bounds, NSRect(x: 0, y: 0, width: 50, height: 25))
            d.translateOrigin(to: NSPoint(x: 10, y: 10))
            XCTAssertEqual(d.bounds, NSRect(x: -10, y: -10, width: 50, height: 25))
        }
    }

    func testFrameRotation() {
        MainActor.assumeIsolated {
            let (root, a, b) = hierarchy()
            a.frameRotation = 90
            XCTAssertTrue(near(b.convert(NSPoint(x: 1, y: 2), to: root), NSPoint(x: -45, y: 26)))
            XCTAssertTrue(near(NSRect(origin: .zero, size: b.convert(NSSize(width: 3, height: 4), to: root)), NSRect(x: 0, y: 0, width: 4, height: 3)))
            XCTAssertTrue(near(b.convert(NSRect(x: 1, y: 2, width: 3, height: 4), to: root), NSRect(x: -49, y: 26, width: 4, height: 3)))
            XCTAssertEqual(a.frame, NSRect(x: 10, y: 20, width: 200, height: 100), "the frame keeps its unrotated origin and size")
            XCTAssertTrue(a.isRotatedFromBase && b.isRotatedFromBase)
            // Round trip through the turn.
            let p = NSPoint(x: 13.5, y: 7.25)
            XCTAssertTrue(near(root.convert(b.convert(p, to: root), to: b), p))
            // Hit testing follows the turned frame: (-45, 26) in root is inside b.
            XCTAssertTrue(a.hitTest(NSPoint(x: -45, y: 26)) === b)
            XCTAssertNil(a.hitTest(NSPoint(x: 100, y: 60)), "the unturned frame's area is outside a now")
        }
    }

    func testBoundsRotation() {
        MainActor.assumeIsolated {
            let (root, a, b) = hierarchy()
            a.boundsRotation = 30
            XCTAssertTrue(near(b.convert(NSPoint(x: 1, y: 2), to: root), NSPoint(x: -7.303847577293364, y: 78.02885682970026), 0.0001))
            XCTAssertTrue(near(a.bounds, NSRect(x: 0, y: -100, width: 223.20508075688772, height: 186.60254037844385), 0.0001))
            a.boundsRotation = 0
            XCTAssertEqual(a.bounds, NSRect(x: 0, y: 0, width: 200, height: 100))
            let c = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            c.rotate(byDegrees: 45)
            XCTAssertEqual(c.boundsRotation, 45)
            XCTAssertTrue(near(c.bounds, NSRect(x: 0, y: -70.71067811865476, width: 141.4213562373095, height: 141.4213562373095), 0.0001))
            // With a bounds origin the turn is about the coordinate origin.
            let g = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            g.setBoundsOrigin(NSPoint(x: 5, y: 5))
            g.boundsRotation = 90
            XCTAssertTrue(near(g.bounds, NSRect(x: 5, y: -105, width: 100, height: 100)))
            XCTAssertTrue(near(g.convert(NSPoint(x: 10, y: 0), to: nil), NSPoint(x: -5, y: 5)))
            // The turned bounds track a frame resize.
            let h = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
            h.boundsRotation = 90
            h.setFrameSize(NSSize(width: 200, height: 50))
            XCTAssertTrue(near(h.bounds, NSRect(x: 0, y: -200, width: 50, height: 200)))
            _ = (root, b)
        }
    }

    func testRotatedDrawingAndFrameCenterRotation() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("pixel checks run on the host backend") }
            final class Red: NSView { override func draw(_ r: NSRect) { NSColor.red.setFill(); bounds.fill() } }
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
            let v = Red(frame: NSRect(x: 30, y: 10, width: 20, height: 10))
            container.addSubview(v)
            v.frameRotation = 90   // now covers x 20...30, y 10...30
            let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds)!
            container.cacheDisplay(in: container.bounds, to: rep)
            let px = { (x: Int, y: Int) -> NSColor in rep.colorAt(x: x * rep.pixelsWide / 60, y: (59 - y) * rep.pixelsHigh / 60)! }
            XCTAssertGreaterThan(px(25, 20).redComponent, 0.9, "inside the turned frame")
            XCTAssertLessThan(px(40, 15).alphaComponent, 0.1, "the unturned frame's area stays empty")
            // frameCenterRotation turns about the centre: the centre stays put.
            let w = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
            let centre = w.convert(NSPoint(x: 20, y: 10), to: nil)
            w.frameCenterRotation = 90
            XCTAssertTrue(near(w.convert(NSPoint(x: 20, y: 10), to: nil), centre))
        }
    }

    func testIsMousePointEdges() {
        MainActor.assumeIsolated {
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50)), f = FlippedView(frame: v.frame)
            let r = NSRect(x: 0, y: 0, width: 10, height: 10)
            XCTAssertFalse(v.isMousePoint(NSPoint(x: 0, y: 0), in: r))
            XCTAssertFalse(v.isMousePoint(NSPoint(x: 10, y: 10), in: r))
            XCTAssertTrue(v.isMousePoint(NSPoint(x: 0, y: 10), in: r))
            XCTAssertFalse(f.isMousePoint(NSPoint(x: 0, y: 10), in: r))
            XCTAssertTrue(f.isMousePoint(NSPoint(x: 0, y: 0), in: r))
        }
    }

    func testAppKitDefaults() {
        MainActor.assumeIsolated {
            let v = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 50))
            XCTAssertEqual(v.allowedTouchTypes, .direct)
            XCTAssertFalse(v.acceptsTouchEvents)
            XCTAssertFalse(v.canDrawConcurrently)
            XCTAssertTrue(NSView.isCompatibleWithResponsiveScrolling)
            XCTAssertFalse(v.preservesContentDuringLiveResize)
            XCTAssertEqual(v.rectPreservedDuringLiveResize, .zero)
            XCTAssertEqual(v.focusRingMaskBounds, .zero)
            XCTAssertEqual(v.adjustScroll(NSRect(x: 1, y: 2, width: 3, height: 4)), NSRect(x: 1, y: 2, width: 3, height: 4))
            XCTAssertTrue(v.wantsBestResolutionOpenGLSurface)
            XCTAssertTrue(v.isHorizontalContentSizeConstraintActive && v.isVerticalContentSizeConstraintActive)
            XCTAssertEqual(v.gState(), 0)
            XCTAssertNil(NSView.defaultMenu)
            XCTAssertNil(v.inputContext)
            XCTAssertEqual(v.convertToLayer(NSPoint(x: 3, y: 4)), NSPoint(x: 3, y: 4))
            v.acceptsTouchEvents = true
            XCTAssertTrue(v.allowedTouchTypes.contains(.indirect))
        }
    }

    func testSortSubviewsAndViewWithTag() {
        MainActor.assumeIsolated {
            final class Tagged: NSView { var t = 0; override var tag: Int { t } }
            let s = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            for i in [3, 1, 2] { let x = Tagged(); x.t = i; s.addSubview(x) }
            s.sortSubviews({ a, b, _ in a.tag < b.tag ? .orderedAscending : (a.tag > b.tag ? .orderedDescending : .orderedSame) }, context: nil)
            XCTAssertEqual(s.subviews.map(\.tag), [1, 2, 3])
            XCTAssertEqual(s.viewWithTag(2)?.tag, 2)
        }
    }
}

// MARK: - NSView behaviour

final class CoreDepthViewBehaviourTests: XCTestCase, @unchecked Sendable {
    func testKeyViewChain() {
        MainActor.assumeIsolated {
            final class Key: NSView { override var acceptsFirstResponder: Bool { true } }
            let w = makeWindow()
            let a = Key(frame: NSRect(x: 10, y: 150, width: 50, height: 20)), b = Key(frame: NSRect(x: 10, y: 100, width: 50, height: 20)), c = Key(frame: NSRect(x: 10, y: 50, width: 50, height: 20))
            for v in [a, b, c] { w.contentView!.addSubview(v) }
            a.nextKeyView = c; c.nextKeyView = b; b.nextKeyView = a
            XCTAssertTrue(c.previousKeyView === a && b.previousKeyView === c)
            XCTAssertTrue(a.nextValidKeyView === c)
            // Relinking keeps the old back link (AppKit's behaviour).
            a.nextKeyView = b
            XCTAssertTrue(c.previousKeyView === a && b.previousKeyView === a)
            a.nextKeyView = c
            _ = w.makeFirstResponder(a)
            w.selectNextKeyView(nil)
            XCTAssertTrue(w.firstResponder === c, "the explicit chain wins over the view order")
            w.selectNextKeyView(nil)
            XCTAssertTrue(w.firstResponder === b)
            w.selectPreviousKeyView(nil)
            XCTAssertTrue(w.firstResponder === a, "b's previous key view is the last view linked to it (a)")
            XCTAssertEqual(w.keyViewSelectionDirection, .directSelection)
            XCTAssertFalse(w.autorecalculatesKeyViewLoop, "AppKit's default")
            // recalculateKeyViewLoop orders top to bottom.
            w.recalculateKeyViewLoop()
            XCTAssertTrue(a.nextKeyView === b && b.nextKeyView === c && c.nextKeyView === a)
            // A plain view in a window cannot become key; nil when nothing in the chain can.
            let p = NSView(), q = NSView()
            p.nextKeyView = q
            XCTAssertNil(p.nextValidKeyView)
            w.close()
        }
    }

    func testToolTipRectsAndManager() {
        MainActor.assumeIsolated {
            final class Owner: NSObject, NSViewToolTipOwner {
                func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String { "tip \(Int(point.x))" }
            }
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 20, y: 20, width: 100, height: 50))
            w.contentView!.addSubview(v)
            let owner = Owner()
            let t1 = v.addToolTip(NSRect(x: 0, y: 0, width: 40, height: 50), owner: owner, userData: nil)
            let t2 = v.addToolTip(NSRect(x: 60, y: 0, width: 40, height: 50), owner: "plain" as NSString, userData: nil)
            XCTAssertNotEqual(t1, t2)
            v.toolTip = "whole view"
            let m = _NSToolTipManager.shared
            XCTAssertEqual(m.toolTip(in: w, at: NSPoint(x: 30, y: 30))?.text, "tip 10")
            XCTAssertEqual(m.toolTip(in: w, at: NSPoint(x: 90, y: 30))?.text, "plain")
            XCTAssertEqual(m.toolTip(in: w, at: NSPoint(x: 70, y: 30))?.text, "whole view", "between the rects: the view's tool tip")
            XCTAssertNil(m.toolTip(in: w, at: NSPoint(x: 200, y: 150)))
            v.removeToolTip(t1)
            XCTAssertEqual(m.toolTip(in: w, at: NSPoint(x: 30, y: 30))?.text, "whole view")
            v.removeAllToolTips()
            XCTAssertEqual(m.toolTip(in: w, at: NSPoint(x: 90, y: 30))?.text, "whole view")
            // Showing and dismissing.
            w.makeKeyAndOrderFront(nil)
            m.mouseMoved(in: w, at: NSPoint(x: 70, y: 30))
            m.showPending()
            XCTAssertEqual(m.visibleText, "whole view")
            m.dismiss()
            XCTAssertNil(m.visibleText)
            w.close()
        }
    }

    func testLegacyTrackingRectEvents() {
        MainActor.assumeIsolated {
            final class Watcher: NSResponder {
                var entered: [(Int, UnsafeMutableRawPointer?)] = []
                override func mouseEntered(with event: NSEvent) { entered.append((event.trackingNumber, event.userData)) }
            }
            let w = makeWindow()
            w.makeKeyAndOrderFront(nil)
            let v = NSView(frame: NSRect(x: 20, y: 20, width: 100, height: 50))
            w.contentView!.addSubview(v)
            let wasActive = NSApplication.shared.isActive
            NSApplication.shared.activate(ignoringOtherApps: true)
            defer { if !wasActive { NSApplication.shared.deactivate() } }
            let watcher = Watcher()
            let data = UnsafeMutableRawPointer(bitPattern: 0x1234)
            let tag = v.addTrackingRect(NSRect(x: 0, y: 0, width: 50, height: 50), owner: watcher, userData: data, assumeInside: false)
            XCTAssertEqual(v.trackingAreas.count, 1)
            @MainActor func move(_ p: NSPoint) {
                w.sendEvent(NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
            }
            move(NSPoint(x: 5, y: 5)); move(NSPoint(x: 30, y: 30))
            XCTAssertEqual(watcher.entered.count, 1)
            XCTAssertEqual(watcher.entered.first?.0, tag)
            XCTAssertEqual(watcher.entered.first?.1, data)
            v.removeTrackingRect(tag)
            XCTAssertTrue(v.trackingAreas.isEmpty)
            w.close()
        }
    }

    func testLockFocusDrawsOverTheViewAndFocusedViewRect() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("pixel checks run on the host backend") }
            final class Blue: NSView { override func draw(_ r: NSRect) { NSColor.blue.setFill(); bounds.fill() } }
            let w = makeWindow()
            w.makeKeyAndOrderFront(nil)
            let v = Blue(frame: NSRect(x: 10, y: 10, width: 40, height: 40))
            w.contentView!.addSubview(v)
            w.displayIfNeeded()
            v.lockFocus()
            XCTAssertTrue(NSView.focusView === v)
            NSColor.red.setFill()
            NSRect(x: 0, y: 0, width: 20, height: 40).fill()
            let rep = NSBitmapImageRep(focusedViewRect: NSRect(x: 0, y: 0, width: 40, height: 40))!
            v.unlockFocus()
            XCTAssertNil(NSView.focusView)
            XCTAssertEqual(rep.size, NSSize(width: 40, height: 40))
            let left = rep.colorAt(x: 2, y: rep.pixelsHigh / 2)!, right = rep.colorAt(x: rep.pixelsWide - 3, y: rep.pixelsHigh / 2)!
            XCTAssertGreaterThan(left.redComponent, 0.9, "what lockFocus drew")
            XCTAssertGreaterThan(right.blueComponent, 0.9, "the view's own content under it")
            XCTAssertTrue(v.lockFocusIfCanDraw())
            v.unlockFocus()
            v.removeFromSuperview()
            XCTAssertFalse(v.lockFocusIfCanDraw(), "no window: cannot draw")
            w.close()
        }
    }

    func testFullScreenModeMovesTheViewAndBack() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            w.makeKeyAndOrderFront(nil)
            let sibling = NSView(frame: .zero)
            let v = NSView(frame: NSRect(x: 5, y: 6, width: 70, height: 80))
            w.contentView!.addSubview(v)
            w.contentView!.addSubview(sibling)
            guard let screen = NSScreen.main else { return }
            XCTAssertTrue(v.enterFullScreenMode(screen, withOptions: nil))
            XCTAssertTrue(v.isInFullScreenMode)
            XCTAssertTrue(v.window !== w)
            XCTAssertEqual(v.window?.frame, screen.frame)
            XCTAssertFalse(v.enterFullScreenMode(screen, withOptions: nil), "already full screen")
            v.exitFullScreenMode(options: nil)
            XCTAssertFalse(v.isInFullScreenMode)
            XCTAssertTrue(v.window === w)
            XCTAssertEqual(v.frame, NSRect(x: 5, y: 6, width: 70, height: 80))
            XCTAssertEqual(w.contentView!.subviews.firstIndex { $0 === v }, 0, "back at its place in the order")
            w.close()
        }
    }

    func testScrollPointAndAutoscroll() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            let doc = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
            scroll.documentView = doc
            w.contentView!.addSubview(scroll)
            doc.scroll(NSPoint(x: 120, y: 200))
            XCTAssertEqual(scroll.contentView.bounds.origin, NSPoint(x: 120, y: 200))
            // A drag past the clip view's right edge scrolls by the overshoot.
            let clip = scroll.contentView
            let inWindow = clip.convert(NSPoint(x: clip.bounds.maxX + 15, y: clip.bounds.midY), to: nil)
            let e = NSEvent.mouseEvent(with: .leftMouseDragged, location: inWindow, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            XCTAssertTrue(doc.autoscroll(with: e))
            XCTAssertEqual(clip.bounds.origin.x, 135, accuracy: 0.5)
            w.close()
        }
    }
}

// MARK: - NSWindow

final class CoreDepthWindowTests: XCTestCase, @unchecked Sendable {
    func testFrameContentRoundTripAndConstrain() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let content = NSRect(x: 40, y: 50, width: 320, height: 240)
            XCTAssertEqual(w.contentRect(forFrameRect: w.frameRect(forContentRect: content)), content)
            guard let screen = w.screen ?? NSScreen.main else { return }
            let v = screen.visibleFrame
            let off = NSRect(x: v.maxX - 50, y: v.minY - 80, width: 300, height: 200)
            let c = w.constrainFrameRect(off, to: screen)
            XCTAssertTrue(v.contains(c), "\(c) inside \(v)")
            XCTAssertEqual(c.size, off.size)
            w.close()
        }
    }

    func testFrameAutosaveRoundTrip() {
        MainActor.assumeIsolated {
            let name = "CoreDepthTest-\(UUID().uuidString)"
            defer { NSWindow.removeFrame(usingName: name) }
            let w = makeWindow()
            w.setFrame(NSRect(x: 120, y: 140, width: 330, height: 250), display: false)
            w.saveFrame(usingName: name)
            let saved = UserDefaults.standard.string(forKey: "NSWindow Frame \(name)")
            let s = (w.screen ?? NSScreen.main)!.frame
            XCTAssertEqual(saved, "120 140 330 250 \(Int(s.minX)) \(Int(s.minY)) \(Int(s.width)) \(Int(s.height)) ")
            XCTAssertEqual(w.frameDescriptor, saved)
            // Another window restores it; a second claim on the name fails.
            let w2 = makeWindow()
            XCTAssertTrue(w2.setFrameAutosaveName(name))
            XCTAssertEqual(w2.frame, NSRect(x: 120, y: 140, width: 330, height: 250))
            XCTAssertFalse(w.setFrameAutosaveName(name), "the name belongs to w2")
            // Moving the window saves again.
            w2.setFrame(NSRect(x: 60, y: 70, width: 310, height: 230), display: false)
            XCTAssertTrue(UserDefaults.standard.string(forKey: "NSWindow Frame \(name)")!.hasPrefix("60 70 310 230 "))
            // setFrameUsingName; a missing name answers false.
            let w3 = makeWindow()
            XCTAssertTrue(w3.setFrameUsingName(name))
            XCTAssertEqual(w3.frame, NSRect(x: 60, y: 70, width: 310, height: 230))
            XCTAssertFalse(w3.setFrameUsingName("CoreDepthTest-missing-\(UUID().uuidString)"))
            // A window that cannot resize keeps its size and takes the saved top-left.
            let fixed = makeWindow(style: [.titled])
            let size = fixed.frame.size
            fixed.setFrame(from: "10 20 300 400 \(Int(s.minX)) \(Int(s.minY)) \(Int(s.width)) \(Int(s.height)) ")
            XCTAssertEqual(fixed.frame.size, size)
            XCTAssertEqual(fixed.frame.maxY, (fixed.constrainFrameRect(NSRect(x: 10, y: 420 - size.height, width: size.width, height: size.height), to: fixed.screen)).maxY)
            NSWindow.removeFrame(usingName: name)
            XCTAssertNil(UserDefaults.standard.string(forKey: "NSWindow Frame \(name)"))
            for x in [w, w2, w3, fixed] { x.close() }
        }
    }

    func testCascadeAndResizeTime() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let topLeft = NSPoint(x: w.frame.minX, y: w.frame.maxY)
            XCTAssertEqual(w.cascadeTopLeft(from: .zero), NSPoint(x: topLeft.x + 29, y: topLeft.y - 29))
            let next = w.cascadeTopLeft(from: NSPoint(x: 200, y: 700))
            if let v = w.screen?.visibleFrame, v.contains(NSPoint(x: 200, y: 700)), 700 - w.frame.height > v.minY {
                XCTAssertEqual(NSPoint(x: w.frame.minX, y: w.frame.maxY), NSPoint(x: 200, y: 700))
                XCTAssertEqual(next, NSPoint(x: 229, y: 671))
            }
            // macOS's curve (probed): 0.0230 s for 10 pt, 0.1673 s for 100, 0.3346 s for 300.
            let f = w.frame
            XCTAssertEqual(w.animationResizeTime(f), 0)
            XCTAssertEqual(w.animationResizeTime(NSRect(x: f.minX, y: f.minY, width: f.width + 10, height: f.height)), 0.023001523392777085, accuracy: 1e-6)
            XCTAssertEqual(w.animationResizeTime(NSRect(x: f.minX, y: f.minY, width: f.width, height: f.height + 100)), 0.16727951957513346, accuracy: 1e-6)
            XCTAssertEqual(w.animationResizeTime(NSRect(x: f.minX, y: f.minY, width: f.width, height: f.height + 300)), 0.3345590391502669, accuracy: 1e-6)
            XCTAssertEqual(w.animationResizeTime(NSRect(x: f.minX + 50, y: f.minY, width: f.width, height: f.height)), 0.09785224609010368, accuracy: 1e-6)
            w.close()
        }
    }

    func testAnimatedSetFrameArrives() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            w.makeKeyAndOrderFront(nil)
            let target = NSRect(x: w.frame.minX, y: w.frame.minY, width: w.frame.width + 40, height: w.frame.height + 20)
            w.setFrame(target, display: true, animate: true)
            XCTAssertEqual(w.frame, target)
            w.close()
        }
    }

    func testZoomToDelegateStandardFrameAndBack() {
        MainActor.assumeIsolated {
            final class D: NSObject, NSWindowDelegate {
                func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect { NSRect(x: 50, y: 60, width: 500, height: 400) }
            }
            let w = makeWindow()
            let d = D()
            w.delegate = d
            let user = w.frame
            XCTAssertFalse(w.isZoomed)
            w.zoom(nil)
            XCTAssertEqual(w.frame, NSRect(x: 50, y: 60, width: 500, height: 400))
            XCTAssertTrue(w.isZoomed)
            w.setIsZoomed(false)
            XCTAssertEqual(w.frame, user)
            XCTAssertFalse(w.isZoomed)
            w.delegate = nil
            w.close()
        }
    }

    func testResizeConstraintsReachThePlatform() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("the host window simulates the user's resize") }
            let w = makeWindow()
            let host = try XCTUnwrap(hostWindow(w))
            w.contentAspectRatio = NSSize(width: 16, height: 9)
            XCTAssertEqual(host.resizeConstraints.contentAspectRatio, NSSize(width: 16, height: 9))
            host._userResize(toContentSize: NSSize(width: 320, height: 300))
            XCTAssertEqual(w.contentRect(forFrameRect: w.frame).size, NSSize(width: 320, height: 180))
            host._userResize(toContentSize: NSSize(width: 100, height: 90), heightEdgeOnly: true)
            XCTAssertEqual(w.contentRect(forFrameRect: w.frame).size, NSSize(width: 160, height: 90))
            // Setting the frame aspect ratio clears the content one (AppKit keeps one).
            w.aspectRatio = NSSize(width: 1, height: 1)
            XCTAssertEqual(w.contentAspectRatio, .zero)
            w.aspectRatio = .zero
            w.contentResizeIncrements = NSSize(width: 50, height: 25)
            host._userResize(toContentSize: NSSize(width: 333, height: 160))
            XCTAssertEqual(w.contentRect(forFrameRect: w.frame).size, NSSize(width: 350, height: 150))
            // A programmatic frame is not constrained.
            w.setFrame(NSRect(x: 100, y: 100, width: 333, height: 233), display: false)
            XCTAssertEqual(w.frame.size, NSSize(width: 333, height: 233))
            w.close()
        }
    }

    func testBackingAndMisc() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let s = w.backingScaleFactor
            XCTAssertEqual(w.convertPointToBacking(NSPoint(x: 3, y: 4)), NSPoint(x: 3 * s, y: 4 * s))
            XCTAssertEqual(w.convertPointFromBacking(NSPoint(x: 3 * s, y: 4 * s)), NSPoint(x: 3, y: 4))
            let aligned = w.backingAlignedRect(NSRect(x: 0.3, y: 0.3, width: 10.4, height: 10.4), options: .alignAllEdgesNearest)
            XCTAssertEqual(aligned, w.convertFromBacking(NSRect(x: (0.3 * s).rounded(), y: (0.3 * s).rounded(),
                                                                 width: (10.7 * s).rounded() - (0.3 * s).rounded(), height: (10.7 * s).rounded() - (0.3 * s).rounded())))
            if s == 2 { XCTAssertEqual(aligned, NSRect(x: 0.5, y: 0.5, width: 10, height: 10), "macOS's answer at 2x") }
            XCTAssertEqual(NSWindow.oldScaleFactorUserInfoKey, "NSBackingPropertyOldScaleFactorKey")
            XCTAssertEqual(NSWindow.oldColorSpaceUserInfoKey, "NSBackingPropertyOldColorSpaceKey")
            XCTAssertEqual(w.anchorAttribute(for: .horizontal), .left)
            XCTAssertEqual(w.anchorAttribute(for: .vertical), .top)
            XCTAssertEqual(w.miniwindowTitle, w.title)
            w.title = "Doc"; XCTAssertEqual(w.miniwindowTitle, "Doc")
            XCTAssertTrue(w.isResizable && w.isMiniaturizable && w.hasCloseBox && w.hasTitleBar && w.isZoomable)
            XCTAssertTrue(w.autorecalculatesContentBorderThickness(for: .minY))
            w.setContentBorderThickness(22, for: .minY)
            XCTAssertEqual(w.contentBorderThickness(for: .minY), 22)
            XCTAssertEqual(NSWindow.minFrameWidth(withTitle: "", styleMask: [.titled]), 69)
            XCTAssertEqual(NSWindow.minFrameWidth(withTitle: "", styleMask: [.borderless]), 4)
            XCTAssertGreaterThan(NSWindow.minFrameWidth(withTitle: "Hello World", styleMask: [.titled]), 100)
            XCTAssertNil(w.tabbedWindows)
            XCTAssertNil(w.tabGroup)
            XCTAssertEqual(w.depthLimit, NSWindow.defaultDepthLimit)
            XCTAssertTrue(w.preventsApplicationTerminationWhenModal)
            w.disableFlushing(); XCTAssertTrue(w.isFlushWindowDisabled); w.enableFlushing(); XCTAssertFalse(w.isFlushWindowDisabled)
            XCTAssertEqual(w.occlusionState, [])
            w.makeKeyAndOrderFront(nil)
            XCTAssertEqual(w.occlusionState, .visible)
            XCTAssertEqual(NSWindow.windowNumber(at: w.convertPoint(toScreen: NSPoint(x: 10, y: 10)), belowWindowWithWindowNumber: 0), w.windowNumber)
            XCTAssertTrue(NSWindow.windowNumbers()?.contains(NSNumber(value: w.windowNumber)) ?? false)
            w.close()
        }
    }

    func testDefaultButtonCell() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let ok = NSButton(title: "OK", target: nil, action: nil), cancel = NSButton(title: "Cancel", target: nil, action: nil)
            ok.keyEquivalent = "\r"
            w.contentView!.addSubview(ok); w.contentView!.addSubview(cancel)
            XCTAssertTrue(w.defaultButtonCell === ok.cell)
            w.disableKeyEquivalentForDefaultButtonCell()
            XCTAssertEqual(ok.keyEquivalent, "")
            XCTAssertTrue(w.defaultButtonCell === ok.cell)
            w.enableKeyEquivalentForDefaultButtonCell()
            XCTAssertEqual(ok.keyEquivalent, "\r")
            w.defaultButtonCell = cancel.cell as? NSButtonCell
            XCTAssertEqual(cancel.keyEquivalent, "\r")
            XCTAssertEqual(ok.keyEquivalent, "")
            w.close()
        }
    }

    func testToggleFullScreen() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            w.makeKeyAndOrderFront(nil)
            let before = w.frame
            let entered = _CoreDepthCounter()
            let token = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: w, queue: nil) { _ in entered.value += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            w.toggleFullScreen(nil)
            XCTAssertEqual(entered.value, 1)
            XCTAssertTrue(w.styleMask.contains(.fullScreen))
            if let s = w.screen ?? NSScreen.main { XCTAssertEqual(w.frame.size, s.frame.size) }
            w.toggleFullScreen(nil)
            XCTAssertFalse(w.styleMask.contains(.fullScreen))
            XCTAssertEqual(w.frame, before)
            w.close()
        }
    }
}

// MARK: - NSImage

final class CoreDepthImageTests: XCTestCase, @unchecked Sendable {
    @MainActor private func solidRep(_ w: Int, _ h: Int, _ color: NSColor) -> NSBitmapImageRep {
        let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<h { for x in 0..<w { r.setColor(color, atX: x, y: y) } }
        return r
    }

    func testNamedSystemImagesAndSymbols() {
        MainActor.assumeIsolated {
            XCTAssertEqual(NSImage.addTemplateName, "NSAddTemplate")
            XCTAssertEqual(NSImage.touchBarAudioOutputVolumeHighTemplateName, "NSTouchBarAudioOutputVolumeHighTemplate")
            let add = NSImage(named: NSImage.addTemplateName)
            XCTAssertNotNil(add)
            XCTAssertTrue(add?.isTemplate ?? false)
            XCTAssertEqual(add?.name(), NSImage.addTemplateName)
            XCTAssertNotNil(NSImage(named: NSImage.cautionName))
            XCTAssertFalse(NSImage(named: NSImage.cautionName)!.isTemplate, "the caution sign is in colour")
            let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
            XCTAssertNotNil(plus)
            XCTAssertEqual(plus?.accessibilityDescription, "Add")
            XCTAssertNil(NSImage(systemSymbolName: "no.such.symbol.anywhere", accessibilityDescription: nil))
            // The symbol draws something.
            let image = render(width: 16, height: 16) { plus!.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16)) }
            let px = NSBitmapImageRep(cgImage: image)
            XCTAssertGreaterThan(px.colorAt(x: 8, y: 8)!.alphaComponent, 0.5)
        }
    }

    func testBestRepresentationSelection() {
        MainActor.assumeIsolated {
            let image = NSImage(size: NSSize(width: 16, height: 16))
            let r1 = solidRep(16, 16, .red), r2 = solidRep(32, 32, .green), r4 = solidRep(64, 64, .blue)
            for r in [r4, r1, r2] { r.size = NSSize(width: 16, height: 16); image.addRepresentation(r) }
            func best(_ scale: CGFloat, _ size: CGFloat = 16) -> NSImageRep? {
                let t = NSAffineTransform(); t.scale(by: scale)
                return image.bestRepresentation(for: NSRect(x: 0, y: 0, width: size, height: size), context: nil, hints: [.ctm: t])
            }
            XCTAssertTrue(best(1) === r1)
            XCTAssertTrue(best(2) === r2)
            XCTAssertTrue(best(3) === r4, "the smallest that covers 48 px")
            XCTAssertTrue(best(1, 100) === r4, "nothing covers: the largest")
            // Drawing at 2x uses the 2x rep (green).
            let out = render(width: 32, height: 32) {
                NSGraphicsContext.current!.cgContext.scaleBy(x: 2, y: 2)
                image.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            }
            let c = NSBitmapImageRep(cgImage: out).colorAt(x: 16, y: 16)!
            XCTAssertGreaterThan(c.greenComponent, 0.9)
            XCTAssertLessThan(c.redComponent, 0.1)
            XCTAssertEqual(image.recommendedLayerContentsScale(3), 3)
            XCTAssertEqual(image.recommendedLayerContentsScale(8), 4)
        }
    }

    func testNineSliceDrawing() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("pixel checks run on the host backend") }
            // 9×9 source: 3-px red corners, green edges, blue centre.
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 9, pixelsHigh: 9, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<9 {
                for x in 0..<9 {
                    let edgeX = x < 3 || x > 5, edgeY = y < 3 || y > 5
                    rep.setColor(edgeX && edgeY ? .red : (edgeX || edgeY ? .green : .blue), atX: x, y: y)
                }
            }
            let image = NSImage(size: NSSize(width: 9, height: 9))
            image.addRepresentation(rep)
            image.capInsets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
            let out = render(width: 60, height: 30) { image.draw(in: NSRect(x: 0, y: 0, width: 60, height: 30)) }
            func at(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) { rgb(out, x, y) }
            // Corners stay 3 px; edges and centre stretch. Sample interior pixels.
            XCTAssertGreaterThan(at(1, 1).r, 200); XCTAssertGreaterThan(at(58, 28).r, 200); XCTAssertGreaterThan(at(1, 28).r, 200)
            XCTAssertGreaterThan(at(30, 1).g, 200, "bottom edge"); XCTAssertGreaterThan(at(1, 15).g, 200, "left edge")
            XCTAssertGreaterThan(at(58, 15).g, 200, "right edge"); XCTAssertGreaterThan(at(30, 28).g, 200, "top edge")
            XCTAssertGreaterThan(at(30, 15).b, 200, "centre"); XCTAssertGreaterThan(at(10, 10).b, 200)
            XCTAssertLessThan(at(10, 10).r, 60, "a stretched draw would put red here")
            // Flipped context, respecting flip: same picture.
            let flipped = render(width: 60, height: 30, flipped: true) {
                image.draw(in: NSRect(x: 0, y: 0, width: 60, height: 30), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            XCTAssertGreaterThan(rgb(flipped, 1, 1).r, 200); XCTAssertGreaterThan(rgb(flipped, 30, 15).b, 200); XCTAssertGreaterThan(rgb(flipped, 30, 28).g, 200)
            // Tiling: the centre repeats its 3-px tile instead of stretching (still blue).
            image.resizingMode = .tile
            let tiled = render(width: 60, height: 30) { image.draw(in: NSRect(x: 0, y: 0, width: 60, height: 30)) }
            XCTAssertGreaterThan(rgb(tiled, 30, 15).b, 200); XCTAssertGreaterThan(rgb(tiled, 1, 1).r, 200)
        }
    }

    func testHitTestUsesAlpha() {
        MainActor.assumeIsolated {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<10 { for x in 0..<5 { rep.setColor(.black, atX: x, y: y) } }   // left half opaque
            let image = NSImage(size: NSSize(width: 10, height: 10))
            image.addRepresentation(rep)
            let dst = NSRect(x: 100, y: 100, width: 20, height: 20)
            XCTAssertTrue(image.hitTest(NSRect(x: 102, y: 110, width: 2, height: 2), withDestinationRect: dst, context: nil, hints: nil, flipped: false))
            XCTAssertFalse(image.hitTest(NSRect(x: 115, y: 110, width: 2, height: 2), withDestinationRect: dst, context: nil, hints: nil, flipped: false))
            XCTAssertFalse(image.hitTest(NSRect(x: 0, y: 0, width: 2, height: 2), withDestinationRect: dst, context: nil, hints: nil, flipped: false))
        }
    }

    func testCodingAndPasteboardAndItemProvider() throws {
        try MainActor.assumeIsolated {
            let image = NSImage(size: NSSize(width: 4, height: 4))
            image.addRepresentation(solidRep(4, 4, .red))
            image.isTemplate = true
            let data = try NSKeyedArchiver.archivedData(withRootObject: image, requiringSecureCoding: false)
            let back = try XCTUnwrap(NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? NSImage)
            XCTAssertEqual(back.size, NSSize(width: 4, height: 4))
            XCTAssertTrue(back.isTemplate)
            let c = (back.representations.first as? NSBitmapImageRep)?.colorAt(x: 1, y: 1)
            XCTAssertGreaterThan(c?.redComponent ?? 0, 0.9)
            XCTAssertTrue(NSImage.supportsSecureCoding)
            XCTAssertEqual(NSImage.writableTypeIdentifiersForItemProvider.first, "public.tiff")
            let png = try XCTUnwrap((image.representations.first as? NSBitmapImageRep)?.representation(using: .png, properties: [:]))
            let fromProvider = try NSImage.object(withItemProviderData: png, typeIdentifier: "public.png")
            XCTAssertEqual(fromProvider.size, NSSize(width: 4, height: 4))
            let fromPlist = NSImage(pasteboardPropertyList: png, ofType: .png)
            XCTAssertEqual(fromPlist?.size, NSSize(width: 4, height: 4))
        }
    }

    func testImageRepRegistry() {
        MainActor.assumeIsolated {
            final class CustomRep: NSImageRep {}
            XCTAssertTrue(NSImageRep.registeredClasses.contains { $0 == NSBitmapImageRep.self })
            XCTAssertTrue(NSImageRep.imageTypes.isEmpty, "the base class lists nothing (AppKit)")
            XCTAssertTrue(NSBitmapImageRep.imageTypes.contains("public.png"))
            XCTAssertTrue(NSImage.imageTypes.contains("public.tiff"))
            XCTAssertTrue(NSImageRep.class(forType: "public.png") == NSBitmapImageRep.self)
            XCTAssertTrue(NSImageRep.class(forFileType: "PNG") == NSBitmapImageRep.self)
            let png = solidRep(2, 2, .blue).representation(using: .png, properties: [:])!
            XCTAssertTrue(NSImageRep.class(for: png) == NSBitmapImageRep.self)
            XCTAssertTrue(NSImageRep.canInit(with: png))
            XCTAssertFalse(NSImageRep.canInit(with: Data([1, 2, 3, 4, 5])))
            let notified = _CoreDepthCounter()
            let token = NotificationCenter.default.addObserver(forName: NSImageRep.registryDidChangeNotification, object: nil, queue: nil) { _ in notified.value += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            NSImageRep.registerClass(CustomRep.self)
            XCTAssertTrue(NSImageRep.registeredClasses.contains { $0 == CustomRep.self })
            NSImageRep.unregisterClass(CustomRep.self)
            XCTAssertFalse(NSImageRep.registeredClasses.contains { $0 == CustomRep.self })
            XCTAssertEqual(notified.value, 2)
            // A plain NSImageRep from a file draws the decoded pixels.
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("coredepth-\(UUID().uuidString).png")
            try? png.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let plain = NSImageRep(contentsOf: url)
            XCTAssertEqual(plain?.pixelsWide, 2)
            XCTAssertNotNil(plain?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }
}

// MARK: - NSBitmapImageRep

final class CoreDepthBitmapTests: XCTestCase, @unchecked Sendable {
    private func rgbaRep(_ w: Int, _ h: Int, format: NSBitmapImageRep.Format = []) -> NSBitmapImageRep {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: format, bytesPerRow: 0, bitsPerPixel: 0)!
    }

    func testPixelAccessorsMatchAppKit() {
        let r = rgbaRep(4, 2)
        XCTAssertEqual(r.bitmapFormat, [])
        XCTAssertEqual(r.bytesPerRow, 32, "rows padded to 32 bytes")
        XCTAssertEqual(r.bitsPerPixel, 32)
        XCTAssertEqual(r.size, NSSize(width: 4, height: 2))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: r.bitmapData, count: 8)), [0, 0, 0, 0, 0, 0, 0, 0])
        r.setColor(NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 0.5), atX: 1, y: 0)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: r.bitmapData, count: 8)), [0, 0, 0, 0, 127, 63, 0, 127], "premultiplied, as macOS stores it")
        let c = r.colorAt(x: 1, y: 0)!
        XCTAssertEqual(c.redComponent, 1, accuracy: 0.01); XCTAssertEqual(c.greenComponent, 0.496, accuracy: 0.01); XCTAssertEqual(c.alphaComponent, 0.498, accuracy: 0.01)
        var px = [Int](repeating: 0, count: 4)
        r.getPixel(&px, atX: 1, y: 0)
        XCTAssertEqual(px, [127, 63, 0, 127])
        var set = [10, 20, 30, 40]
        r.setPixel(&set, atX: 0, y: 1)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: r.bitmapData! + r.bytesPerRow, count: 4)), [10, 20, 30, 40])
        XCTAssertNil(r.colorAt(x: 4, y: 0))
        // Non-premultiplied, alpha first.
        let np = rgbaRep(1, 1, format: [.alphaNonpremultiplied, .alphaFirst])
        np.setColor(NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 0.5), atX: 0, y: 0)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: np.bitmapData, count: 4)), [127, 255, 127, 0])
        // Planar: one plane per sample.
        let pl = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: true, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        XCTAssertEqual(pl.numberOfPlanes, 4); XCTAssertEqual(pl.bitsPerPixel, 8); XCTAssertEqual(pl.bytesPerRow, 32)
        pl.setColor(.red, atX: 1, y: 0)
        var planes = [UnsafeMutablePointer<UInt8>?](repeating: nil, count: 5)
        pl.getBitmapDataPlanes(&planes)
        XCTAssertEqual(planes[0]![1], 255); XCTAssertEqual(planes[1]![1], 0); XCTAssertEqual(planes[3]![1], 255)
        // Gray.
        let gray = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0)!
        gray.setColor(NSColor(white: 0.5, alpha: 1), atX: 0, y: 0)
        XCTAssertEqual(gray.bitmapData![0], 127)
        XCTAssertEqual(gray.colorAt(x: 0, y: 0)!.whiteComponent, 0.498, accuracy: 0.01)
        // Bad parameters.
        XCTAssertNil(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 0, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        XCTAssertNil(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    }

    func testWritingBitmapDataReachesTheImage() {
        let r = rgbaRep(2, 2)
        let p = r.bitmapData!
        for i in 0..<2 { p[i * 4] = 0; p[i * 4 + 1] = 0; p[i * 4 + 2] = 255; p[i * 4 + 3] = 255 }   // top row blue
        let px = NSBitmapImageRep._rgbaPixels(of: r.cgImage!)
        XCTAssertEqual(Array(px.bytes[0..<4]), [0, 0, 255, 255])
        p[2] = 0; p[0] = 255   // later writes are seen too
        XCTAssertEqual(Array(NSBitmapImageRep._rgbaPixels(of: r.cgImage!).bytes[0..<4]), [255, 0, 0, 255])
        // Caller-supplied planes are read in place.
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 255, count: 4)
        var planes: [UnsafeMutablePointer<UInt8>?] = [buffer, nil, nil, nil, nil]
        let own = NSBitmapImageRep(bitmapDataPlanes: &planes, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        XCTAssertTrue(own.bitmapData == buffer)
        buffer[1] = 0
        XCTAssertEqual(own.colorAt(x: 0, y: 0)!.greenComponent, 0, accuracy: 0.01)
    }

    func testPNGRoundTrip() throws {
        let r = rgbaRep(4, 2)
        r.setColor(NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 0.5), atX: 1, y: 0)
        r.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: 3, y: 1)
        let png = try XCTUnwrap(r.representation(using: .png, properties: [:]))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let back = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(back.pixelsWide, 4); XCTAssertEqual(back.pixelsHigh, 2)
        XCTAssertTrue(back.bitmapFormat.contains(.alphaNonpremultiplied), "decoded reps hold straight alpha, as macOS's do")
        let c = try XCTUnwrap(back.colorAt(x: 1, y: 0))
        XCTAssertEqual(c.redComponent, 1, accuracy: 0.02); XCTAssertEqual(c.greenComponent, 0.5, accuracy: 0.03); XCTAssertEqual(c.alphaComponent, 0.5, accuracy: 0.02)
        XCTAssertEqual(back.colorAt(x: 3, y: 1)!.blueComponent, 1, accuracy: 0.02)
        XCTAssertEqual(back.colorAt(x: 0, y: 0)!.alphaComponent, 0, accuracy: 0.01)
    }

    func testTIFFAndBMPWriters() throws {
        let r = rgbaRep(3, 2)
        r.setColor(.red, atX: 0, y: 0); r.setColor(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 0.5), atX: 2, y: 1)
        let tiff = try XCTUnwrap(r.tiffRepresentation)
        XCTAssertEqual(Array(tiff.prefix(4)), [0x4D, 0x4D, 0x00, 0x2A], "big-endian TIFF, as AppKit writes")
        for data in [tiff, try XCTUnwrap(r.tiffRepresentation(using: .packBits, factor: 0))] {
            let pages = _NSTIFFCodec.decode(data)
            XCTAssertEqual(pages.count, 1)
            XCTAssertEqual(Array(pages[0].bytes[0..<4]), [255, 0, 0, 255])
            let i = (1 * 3 + 2) * 4
            XCTAssertEqual(pages[0].bytes[i + 1], 255); XCTAssertEqual(Int(pages[0].bytes[i + 3]), 127, accuracy: 1)
            let back = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(back.colorAt(x: 0, y: 0)!.redComponent, 1, accuracy: 0.02)
        }
        XCTAssertTrue(r.canBeCompressed(using: .packBits))
        XCTAssertFalse(r.canBeCompressed(using: .lzw))
        XCTAssertEqual(NSBitmapImageRep.localizedName(forTIFFCompressionType: .lzw), "Lempel-Ziv & Welch")
        var comp = NSBitmapImageRep.TIFFCompression.lzw, f: Float = 1
        r.getCompression(&comp, factor: &f)
        XCTAssertEqual(comp, .none); XCTAssertEqual(f, 0)
        r.setCompression(.packBits, factor: 0.5)
        r.getCompression(&comp, factor: &f)
        XCTAssertEqual(comp, .packBits); XCTAssertEqual(f, 0.5)
        // Two reps, two pages.
        let both = try XCTUnwrap(NSBitmapImageRep.tiffRepresentationOfImageReps(in: [r, rgbaRep(1, 1)]))
        XCTAssertEqual(_NSTIFFCodec.decode(both).map(\.width), [3, 1])
        // BMP: a 32-bit V4 bitmap, bottom row first.
        let bmp = try XCTUnwrap(r.representation(using: .bmp, properties: [:]))
        XCTAssertEqual(Array(bmp.prefix(2)), [0x42, 0x4D])
        XCTAssertEqual(bmp.count, 14 + 108 + 3 * 2 * 4)
        let firstTopRowPixel = 14 + 108 + 3 * 4   // bottom-up: the top row is second
        XCTAssertEqual(Array(bmp[firstTopRowPixel..<(firstTopRowPixel + 4)]), [0, 0, 255, 255], "BGRA red")
        // NSImage's TIFF is a real TIFF now.
        let image = NSImage(size: NSSize(width: 3, height: 2)); image.addRepresentation(r)
        XCTAssertEqual(Array(image.tiffRepresentation!.prefix(2)), [0x4D, 0x4D])
    }

    func testIncrementalLoadAndColorize() {
        let png = rgbaRep(2, 2).representation(using: .png, properties: [:])!
        let inc = NSBitmapImageRep(forIncrementalLoad: ())
        XCTAssertEqual(inc.incrementalLoad(from: png.prefix(10), complete: false), NSBitmapImageRep.LoadStatus.willNeedAllData.rawValue)
        XCTAssertEqual(inc.incrementalLoad(from: png, complete: true), NSBitmapImageRep.LoadStatus.completed.rawValue)
        XCTAssertEqual(inc.pixelsWide, 2)
        let bad = NSBitmapImageRep(forIncrementalLoad: ())
        XCTAssertEqual(bad.incrementalLoad(from: Data([1, 2, 3]), complete: true), NSBitmapImageRep.LoadStatus.invalidData.rawValue)
        // Colorize: black → red, white → blue.
        let g = rgbaRep(2, 1)
        g.setColor(.black, atX: 0, y: 0); g.setColor(.white, atX: 1, y: 0)
        g.colorize(byMappingGray: 0.5, to: nil, blackMapping: .red, whiteMapping: .blue)
        XCTAssertEqual(g.colorAt(x: 0, y: 0)!.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(g.colorAt(x: 1, y: 0)!.blueComponent, 1, accuracy: 0.01)
        XCTAssertEqual(g.value(forProperty: .compressionFactor) as? NSNumber, nil)
        g.setProperty(.compressionFactor, withValue: NSNumber(value: 0.7))
        XCTAssertEqual((g.value(forProperty: .compressionFactor) as? NSNumber)?.doubleValue ?? 0, 0.7, accuracy: 0.001)
    }
}
