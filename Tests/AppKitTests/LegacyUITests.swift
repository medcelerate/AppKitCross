// Legacy and miscellaneous UI (ADR-0034): NSGradient colours and pixels, NSAnimation and
// NSViewAnimation on a fake frame clock, NSRulerView hash marks, markers and drags (and
// NSTextView as its client), NSDrawer open/close state, frames and slide, NSScrubber
// layouts, item views and selection.

import XCTest
@testable import AppKit
import QuartzCore

// MARK: - Helpers

@MainActor
private func sendMouse(_ w: NSWindow, _ type: NSEvent.EventType, _ p: NSPoint) {
    w.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                   eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!)
}

@MainActor
private func makeWindow(_ rect: NSRect = NSRect(x: 100, y: 100, width: 400, height: 300)) -> NSWindow {
    let w = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.makeKeyAndOrderFront(nil)
    return w
}

/// Runs `body` with Core Animation's clock replaced by a settable one starting at 100.
@MainActor
private func withFakeClock(_ body: (_ advance: (CFTimeInterval) -> Void) -> Void) {
    var clock: CFTimeInterval = 100
    let saved = CARuntime.now
    CARuntime.now = { clock }
    defer { CARuntime.now = saved }
    body { dt in
        clock += dt
        CARuntime.tick()
    }
}

private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) <= tolerance }

/// A BGRA bitmap context's pixel at (x, y) from the bottom-left, as 0...255 RGB.
private func rgb(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let data = _pixels(image)
    let row = image.height - 1 - y
    let i = row * image.bytesPerRow + x * 4
    return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))
}

private func close(_ p: (r: Int, g: Int, b: Int), _ r: Int, _ g: Int, _ b: Int, _ tolerance: Int = 8) -> Bool {
    abs(p.r - r) <= tolerance && abs(p.g - g) <= tolerance && abs(p.b - b) <= tolerance
}

// MARK: - NSGradient

final class GradientTests: XCTestCase, @unchecked Sendable {
    func testStopsAndInterpolation() {
        let g = NSGradient(colorsAndLocations: (.blue, 1), (.red, 0), (.green, 0.5))!
        XCTAssertEqual(g.numberOfColorStops, 3)
        var c = NSColor.black
        var l: CGFloat = -1
        g.getColor(&c, location: &l, at: 0)
        XCTAssertEqual(l, 0, "stops are kept in location order")
        XCTAssertEqual(c.redComponent, 1)
        g.getColor(&c, location: &l, at: 2)
        XCTAssertEqual(l, 1)
        XCTAssertEqual(c.blueComponent, 1)
        let quarter = g.interpolatedColor(atLocation: 0.25)
        XCTAssertTrue(near(quarter.redComponent, 0.5) && near(quarter.greenComponent, 0.5) && near(quarter.blueComponent, 0))
        XCTAssertEqual(g.interpolatedColor(atLocation: -1).redComponent, 1, "before the first stop: its colour")
        XCTAssertEqual(g.interpolatedColor(atLocation: 2).blueComponent, 1, "after the last stop: its colour")
        XCTAssertNil(NSGradient(colors: [.red]), "a gradient needs two colours")
        let even = NSGradient(colors: [.black, .white, .black])!
        even.getColor(nil, location: &l, at: 1)
        XCTAssertEqual(l, 0.5, "evenly spaced without locations")
        let two = NSGradient(starting: .white, ending: .black)!
        XCTAssertTrue(near(two.interpolatedColor(atLocation: 0.5).redComponent, 0.5))
    }

    func testAxisForAngle() {
        let r = NSRect(x: 0, y: 0, width: 100, height: 40)
        var (s, e) = NSGradient._axis(for: r, angle: 0)
        XCTAssertEqual(s, NSPoint(x: 0, y: 20)); XCTAssertEqual(e, NSPoint(x: 100, y: 20))
        (s, e) = NSGradient._axis(for: r, angle: 90)
        XCTAssertEqual(s, NSPoint(x: 50, y: 0)); XCTAssertEqual(e, NSPoint(x: 50, y: 40))
        (s, e) = NSGradient._axis(for: r, angle: 45)
        // The corners project onto the axis at its ends.
        let d = (100 + 40) / 2 / 2.squareRoot()
        XCTAssertTrue(near(e.x - 50, d / 2.squareRoot()) && near(s.x - 50, -d / 2.squareRoot()))
        let (c0, c1, r1) = NSGradient._radialGeometry(for: r, relativeCenterPosition: NSPoint(x: 1, y: 0))
        XCTAssertEqual(c0, NSPoint(x: 100, y: 20)); XCTAssertEqual(c1, NSPoint(x: 50, y: 20))
        XCTAssertTrue(near(r1, (100.0 * 100 + 40 * 40).squareRoot() / 2))
    }

    @MainActor private func render(width: Int, height: Int, _ draw: () -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    func testLinearPixelsAtStops() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("pixel checks run on the host backend") }
            let g = NSGradient(colorsAndLocations: (.red, 0), (.green, 0.5), (.blue, 1))!
            let image = render(width: 100, height: 20) { g.draw(in: NSRect(x: 0, y: 0, width: 100, height: 20), angle: 0) }
            XCTAssertTrue(close(rgb(image, 0, 10), 255, 0, 0, 12), "\(rgb(image, 0, 10))")
            XCTAssertTrue(close(rgb(image, 50, 10), 0, 255, 0, 12), "\(rgb(image, 50, 10))")
            XCTAssertTrue(close(rgb(image, 99, 10), 0, 0, 255, 12), "\(rgb(image, 99, 10))")
            XCTAssertTrue(close(rgb(image, 25, 10), 128, 128, 0, 12), "half way between red and green: \(rgb(image, 25, 10))")
            // Vertical: 90 degrees runs bottom to top.
            let v = render(width: 20, height: 100) { g.draw(in: NSRect(x: 0, y: 0, width: 20, height: 100), angle: 90) }
            XCTAssertTrue(close(rgb(v, 10, 0), 255, 0, 0, 12) && close(rgb(v, 10, 99), 0, 0, 255, 12))
            // Between two points without extension options nothing is painted outside them.
            let p = render(width: 100, height: 10) {
                NSColor.white.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 100, height: 10))
                g.draw(from: NSPoint(x: 20, y: 0), to: NSPoint(x: 80, y: 0), options: [])
            }
            XCTAssertTrue(close(rgb(p, 5, 5), 255, 255, 255), "before the start: untouched")
            XCTAssertTrue(close(rgb(p, 95, 5), 255, 255, 255), "after the end: untouched")
            XCTAssertTrue(close(rgb(p, 21, 5), 255, 0, 0, 16))
            let ext = render(width: 100, height: 10) { g.draw(from: NSPoint(x: 20, y: 0), to: NSPoint(x: 80, y: 0), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]) }
            XCTAssertTrue(close(rgb(ext, 5, 5), 255, 0, 0) && close(rgb(ext, 95, 5), 0, 0, 255), "extended with the end colours")
        }
    }

    func testRadialAndPathPixels() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("pixel checks run on the host backend") }
            let g = NSGradient(starting: .white, ending: .black)!
            let image = render(width: 101, height: 101) {
                g.draw(fromCenter: NSPoint(x: 50.5, y: 50.5), radius: 0, toCenter: NSPoint(x: 50.5, y: 50.5), radius: 50, options: [])
            }
            XCTAssertTrue(close(rgb(image, 50, 50), 255, 255, 255, 12), "the centre is the start colour: \(rgb(image, 50, 50))")
            XCTAssertTrue(close(rgb(image, 75, 50), 128, 128, 128, 14), "half the radius: half way \(rgb(image, 75, 50))")
            XCTAssertEqual(rgb(image, 1, 1).r, 0, "outside the end circle without the option: unpainted (transparent)")
            // In an oval path: clipped to it.
            let o = render(width: 60, height: 60) {
                NSColor.white.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 60, height: 60))
                NSGradient(starting: .red, ending: .red)!.draw(in: NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 60, height: 60)), angle: 0)
            }
            XCTAssertTrue(close(rgb(o, 30, 30), 255, 0, 0))
            XCTAssertTrue(close(rgb(o, 1, 1), 255, 255, 255), "the corner is outside the oval")
        }
    }
}

// MARK: - NSAnimation

/// Marks seen by a notification closure (a captured `var` there is a Sendable error on Linux and Windows).
private final class MarkBox: @unchecked Sendable { var marks: [Float] = [] }

private final class AnimationRecorder: NSObject, NSAnimationDelegate, @unchecked Sendable {
    var marks: [Float] = []
    var ended = 0, stopped = 0
    var allowStart = true
    var custom: ((Float) -> Float)?
    func animation(_ animation: NSAnimation, didReachProgressMark progress: NSAnimation.Progress) { marks.append(progress) }
    func animationDidEnd(_ animation: NSAnimation) { ended += 1 }
    func animationDidStop(_ animation: NSAnimation) { stopped += 1 }
    func animationShouldStart(_ animation: NSAnimation) -> Bool { allowStart }
    func animation(_ animation: NSAnimation, valueForProgress progress: NSAnimation.Progress) -> Float {
        custom?(progress) ?? NSAnimation._value(of: animation.animationCurve, at: progress)
    }
}

final class AnimationTests: XCTestCase, @unchecked Sendable {
    func testCurves() {
        XCTAssertEqual(NSAnimation._value(of: .linear, at: 0.3), 0.3, accuracy: 1e-6)
        XCTAssertEqual(NSAnimation._value(of: .easeInOut, at: 0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(NSAnimation._value(of: .easeIn, at: 0.5), 1 - Float(cos(Double.pi / 4)), accuracy: 1e-6)
        XCTAssertEqual(NSAnimation._value(of: .easeOut, at: 0.5), Float(sin(Double.pi / 4)), accuracy: 1e-6)
        for curve in [NSAnimation.Curve.linear, .easeIn, .easeOut, .easeInOut] {
            XCTAssertEqual(NSAnimation._value(of: curve, at: 0), 0, accuracy: 1e-6)
            XCTAssertEqual(NSAnimation._value(of: curve, at: 1), 1, accuracy: 1e-6)
        }
        XCTAssertLessThan(NSAnimation._value(of: .easeIn, at: 0.25), 0.25, "ease in starts slow")
        XCTAssertGreaterThan(NSAnimation._value(of: .easeOut, at: 0.25), 0.25, "ease out starts fast")
    }

    func testNonBlockingProgressMarksAndEnd() {
        MainActor.assumeIsolated {
            withFakeClock { advance in
                let a = NSAnimation(duration: 1, animationCurve: .easeInOut)
                XCTAssertEqual(a.animationBlockingMode, .blocking, "AppKit's default")
                a.animationBlockingMode = .nonblocking
                a.progressMarks = [0.5, 0.25, 1]
                XCTAssertEqual(a.progressMarks.map { $0.floatValue }, [0.25, 0.5, 1])
                let r = AnimationRecorder()
                a.delegate = r
                let notified = MarkBox()
                let token = NotificationCenter.default.addObserver(forName: NSAnimation.progressMarkNotification, object: a, queue: nil) { n in
                    notified.marks.append((n.userInfo?[NSAnimation.progressMarkUserInfoKey] as? NSNumber)?.floatValue ?? -1)
                }
                defer { NotificationCenter.default.removeObserver(token) }
                a.start()
                XCTAssertTrue(a.isAnimating)
                XCTAssertEqual(a.currentProgress, 0)
                advance(0.3)
                XCTAssertEqual(a.currentProgress, 0.3, accuracy: 1e-4)
                XCTAssertEqual(a.currentValue, NSAnimation._value(of: .easeInOut, at: 0.3), accuracy: 1e-4)
                XCTAssertEqual(r.marks, [0.25])
                advance(0.3)
                XCTAssertEqual(r.marks, [0.25, 0.5])
                advance(0.5)
                XCTAssertEqual(a.currentProgress, 1)
                XCTAssertFalse(a.isAnimating)
                XCTAssertEqual(r.marks, [0.25, 0.5, 1])
                XCTAssertEqual(notified.marks, [0.25, 0.5, 1])
                XCTAssertEqual(r.ended, 1)
                XCTAssertEqual(r.stopped, 0)
                // A finished animation starts again from the beginning.
                a.start()
                XCTAssertEqual(a.currentProgress, 0)
                a.stop()
                XCTAssertEqual(r.stopped, 1)
                XCTAssertFalse(a.isAnimating)
            }
        }
    }

    func testDelegateValueVetoAndStop() {
        MainActor.assumeIsolated {
            withFakeClock { advance in
                let a = NSAnimation(duration: 2, animationCurve: .linear)
                a.animationBlockingMode = .nonblocking
                let r = AnimationRecorder()
                r.custom = { $0 * $0 }
                a.delegate = r
                r.allowStart = false
                a.start()
                XCTAssertFalse(a.isAnimating, "the delegate refused")
                r.allowStart = true
                a.start()
                advance(1)
                XCTAssertEqual(a.currentProgress, 0.5, accuracy: 1e-4)
                XCTAssertEqual(a.currentValue, 0.25, accuracy: 1e-4, "the delegate's value")
                a.stop()
                advance(1)
                XCTAssertEqual(a.currentProgress, 0.5, accuracy: 1e-4, "stopped where it was")
                XCTAssertEqual(r.stopped, 1)
                XCTAssertEqual(r.ended, 0)
                // Setting the progress of a running animation continues from there.
                a.start()
                a.currentProgress = 0.9
                advance(0.1)
                XCTAssertEqual(a.currentProgress, 0.95, accuracy: 1e-4)
                a.stop()
            }
        }
    }

    func testLinkedStartAndStop() {
        MainActor.assumeIsolated {
            withFakeClock { advance in
                let a = NSAnimation(duration: 1, animationCurve: .linear)
                let b = NSAnimation(duration: 1, animationCurve: .linear)
                let c = NSAnimation(duration: 10, animationCurve: .linear)
                for x in [a, b, c] { x.animationBlockingMode = .nonblocking }
                b.start(when: a, reachesProgress: 0.5)
                c.stop(when: a, reachesProgress: 0.75)
                XCTAssertTrue(a.progressMarks.map { $0.floatValue }.contains(0.5))
                c.start()
                a.start()
                advance(0.4)
                XCTAssertFalse(b.isAnimating)
                advance(0.2)
                XCTAssertTrue(b.isAnimating, "b starts when a passes 0.5")
                XCTAssertTrue(c.isAnimating)
                advance(0.2)
                XCTAssertFalse(c.isAnimating, "c stops when a passes 0.75")
                b.clearStart()
                advance(1)
                a.start()
                b.stop()
                advance(0.6)
                XCTAssertFalse(b.isAnimating, "cleared: a's mark no longer starts b")
                a.stop()
            }
        }
    }

    func testBlockingModeReturnsAtTheEnd() {
        MainActor.assumeIsolated {
            let a = NSAnimation(duration: 0.05, animationCurve: .linear)
            let r = AnimationRecorder()
            a.delegate = r
            a.start()
            XCTAssertFalse(a.isAnimating)
            XCTAssertEqual(a.currentProgress, 1)
            XCTAssertEqual(r.ended, 1)
            let copy = a.copy() as! NSAnimation
            XCTAssertEqual(copy.duration, 0.05)
            XCTAssertEqual(copy.animationCurve, .linear)
        }
    }

    func testViewAnimationFramesAndEffects() {
        MainActor.assumeIsolated {
            withFakeClock { advance in
                let v = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
                let fader = NSView(frame: NSRect(x: 0, y: 0, width: 5, height: 5))
                let collapser = NSView(frame: NSRect(x: 0, y: 0, width: 5, height: 5))
                let anim = NSViewAnimation(viewAnimations: [
                    [.target: v, .endFrame: NSValue(rect: NSRect(x: 100, y: 20, width: 30, height: 10))],
                    [.target: fader, .effect: NSViewAnimation.EffectName.fadeOut],
                    [.target: collapser, .endFrame: NSRect.zero],
                ])
                XCTAssertEqual(anim.duration, 0.5)
                XCTAssertEqual(anim.animationCurve, .easeInOut)
                anim.animationCurve = .linear
                anim.duration = 1
                anim.animationBlockingMode = .nonblocking
                anim.start()
                advance(0.5)
                XCTAssertEqual(v.frame, NSRect(x: 50, y: 10, width: 20, height: 10))
                XCTAssertEqual(fader.alphaValue, 0.5, accuracy: 1e-4)
                XCTAssertFalse(fader.isHidden)
                advance(0.6)
                XCTAssertEqual(v.frame, NSRect(x: 100, y: 20, width: 30, height: 10))
                XCTAssertTrue(fader.isHidden, "faded out: hidden at the end")
                XCTAssertEqual(fader.alphaValue, 1, "and its alpha restored")
                XCTAssertTrue(collapser.isHidden, "an empty end frame hides the view")
                // Fade in shows a hidden view from transparent.
                let shy = NSView(frame: .zero)
                shy.isHidden = true
                let fadeIn = NSViewAnimation(viewAnimations: [[.target: shy, .effect: "NSViewAnimationFadeInEffect"]])
                fadeIn.animationBlockingMode = .nonblocking
                fadeIn.animationCurve = .linear
                fadeIn.duration = 1
                fadeIn.start()
                XCTAssertFalse(shy.isHidden)
                XCTAssertEqual(shy.alphaValue, 0, accuracy: 1e-4)
                advance(0.25)
                XCTAssertEqual(shy.alphaValue, 0.25, accuracy: 1e-4)
                advance(1)
                XCTAssertEqual(shy.alphaValue, 1)
            }
        }
    }
}

// MARK: - NSRulerView

@MainActor
private final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
    var events: [String] = []
    override func rulerView(_ ruler: NSRulerView, didMove marker: NSRulerMarker) { events.append("move \(marker.markerLocation)") }
    override func rulerView(_ ruler: NSRulerView, didRemove marker: NSRulerMarker) { events.append("remove") }
    override func rulerView(_ ruler: NSRulerView, didAdd marker: NSRulerMarker) { events.append("add \(marker.markerLocation)") }
    override func rulerView(_ ruler: NSRulerView, willMove marker: NSRulerMarker, toLocation location: CGFloat) -> CGFloat {
        (location / 9).rounded() * 9      // snaps to an eighth of an inch
    }
}

final class RulerTests: XCTestCase, @unchecked Sendable {
    @MainActor private func rulerSetup() -> (NSWindow, NSScrollView, FlippedDocument, NSRulerView) {
        let w = makeWindow()
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let doc = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 2000, height: 2000))
        sv.documentView = doc
        w.contentView = sv
        sv.hasHorizontalRuler = true
        sv.rulersVisible = true
        let ruler = sv.horizontalRulerView!
        ruler.clientView = doc
        ruler.measurementUnits = .inches
        return (w, sv, doc, ruler)
    }

    func testTilingAndThickness() {
        MainActor.assumeIsolated {
            let (w, sv, _, ruler) = rulerSetup()
            defer { w.close() }
            XCTAssertTrue(ruler.superview === sv)
            XCTAssertEqual(ruler.orientation, .horizontalRuler)
            XCTAssertTrue(ruler.isFlipped)
            XCTAssertEqual(ruler.requiredThickness, 31, "rule 16 + markers 15")
            XCTAssertEqual(ruler.baselineLocation, 15)
            XCTAssertEqual(ruler.frame, NSRect(x: 0, y: 300 - 31, width: 400, height: 31))
            XCTAssertEqual(sv.contentView.frame.height, 300 - 31, "the content gives up the ruler's strip")
            sv.hasVerticalRuler = true
            let v = sv.verticalRulerView!
            XCTAssertEqual(v.frame.minX, 0)
            XCTAssertEqual(sv.contentView.frame.minX, v.requiredThickness)
            ruler.reservedThicknessForAccessoryView = 10
            XCTAssertEqual(ruler.requiredThickness, 41)
            XCTAssertEqual(ruler.frame.height, 41, "the scroll view tiles again")
            sv.rulersVisible = false
            XCTAssertNil(ruler.superview)
            XCTAssertEqual(sv.contentView.frame.height, 300)
        }
    }

    func testHashMarkLevelsPerUnit() {
        MainActor.assumeIsolated {
            let (w, _, _, ruler) = rulerSetup()
            defer { w.close() }
            XCTAssertEqual(ruler._levels(), [1, 0.5, 0.25, 0.125], "inches: labels every inch, down to eighths (9 pt)")
            ruler.measurementUnits = .centimeters
            XCTAssertEqual(ruler._levels().map { ($0 * 100).rounded() / 100 }, [2, 1, 0.2], "centimetres: labels every 2 cm, millimetre pairs")
            ruler.measurementUnits = .points
            XCTAssertEqual(ruler._levels(), [100, 50, 25, 12.5, 6.25])
            NSRulerView.registerUnit(withName: NSRulerView.UnitName("Grids"), abbreviation: "gd", unitToPointsConversionFactor: 40,
                                     stepUpCycle: [2], stepDownCycle: [0.5])
            ruler.measurementUnits = NSRulerView.UnitName("Grids")
            XCTAssertEqual(ruler._levels(), [1, 0.5, 0.25, 0.125])
        }
    }

    func testHashMarkPositionsOffsetAndScrolling() {
        MainActor.assumeIsolated {
            let (w, sv, doc, ruler) = rulerSetup()
            defer { w.close() }
            var marks = ruler._hashMarks(from: 0, to: 80)
            XCTAssertEqual(marks.first, NSRulerView._HashMark(location: 0, level: 0, label: "0"))
            XCTAssertEqual(marks.map { $0.location }, [0, 9, 18, 27, 36, 45, 54, 63, 72])
            XCTAssertEqual(marks.map { $0.level }, [0, 3, 2, 3, 1, 3, 2, 3, 0])
            XCTAssertEqual(marks.last?.label, "1")
            ruler.originOffset = 36
            marks = ruler._hashMarks(from: 0, to: 120)
            XCTAssertEqual(marks.first { $0.label == "0" }?.location, 36)
            XCTAssertEqual(marks.first { $0.label == "1" }?.location, 108)
            XCTAssertEqual(marks.first?.level, 1, "half an inch before the zero")
            ruler.originOffset = 0
            sv.contentView.scroll(to: NSPoint(x: 100, y: 0))
            sv.reflectScrolledClipView(sv.contentView)
            marks = ruler._hashMarks(from: 0, to: 60)
            XCTAssertEqual(marks.first { $0.label == "2" }?.location, 44, "the 2-inch mark (144) sits 100 points left after scrolling")
            _ = doc
        }
    }

    func testMarkerRectAndDrag() {
        MainActor.assumeIsolated {
            let (w, _, doc, ruler) = rulerSetup()
            defer { w.close() }
            let image = NSRulerView._markerImage(.leftTab)
            let m = NSRulerMarker(rulerView: ruler, markerLocation: 72, image: image, imageOrigin: NSPoint(x: 4.5, y: 0))
            XCTAssertTrue(m.isMovable)
            XCTAssertFalse(m.isRemovable)
            XCTAssertEqual(m.thicknessRequiredInRuler, 7)
            ruler.addMarker(m)
            XCTAssertEqual(ruler.markers?.count, 1)
            XCTAssertEqual(m.imageRectInRuler, NSRect(x: 67.5, y: 8, width: 9, height: 7), "standing on the baseline at 72")
            // Drag it right by 36 points: the client snaps to eighths.
            let start = ruler.convert(NSPoint(x: 72, y: 12), to: nil)
            sendMouse(w, .leftMouseDown, start)
            XCTAssertTrue(m.isDragging)
            sendMouse(w, .leftMouseDragged, NSPoint(x: start.x + 20, y: start.y))
            XCTAssertEqual(m.markerLocation, 90)
            sendMouse(w, .leftMouseUp, NSPoint(x: start.x + 37, y: start.y))
            XCTAssertFalse(m.isDragging)
            XCTAssertEqual(m.markerLocation, 108)
            XCTAssertEqual(doc.events, ["move 108.0"])
            // Not removable: dragging it off the ruler leaves it.
            let at = ruler.convert(NSPoint(x: 108, y: 12), to: nil)
            sendMouse(w, .leftMouseDown, at)
            sendMouse(w, .leftMouseUp, NSPoint(x: at.x, y: at.y - 200))
            XCTAssertEqual(ruler.markers?.count, 1)
            m.isRemovable = true
            sendMouse(w, .leftMouseDown, at)
            sendMouse(w, .leftMouseDragged, NSPoint(x: at.x, y: at.y - 200))
            sendMouse(w, .leftMouseUp, NSPoint(x: at.x, y: at.y - 200))
            XCTAssertNil(ruler.markers, "removed")
            XCTAssertEqual(doc.events.last, "remove")
            // A new marker tracked from a mouse-down is added where it is dropped.
            let fresh = NSRulerMarker(rulerView: ruler, markerLocation: 0, image: image, imageOrigin: NSPoint(x: 4.5, y: 0))
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: ruler.convert(NSPoint(x: 30, y: 20), to: nil), modifierFlags: [], timestamp: 0,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            XCTAssertTrue(ruler.trackMarker(fresh, withMouseEvent: down))
            XCTAssertNil(ruler.markers, "not added until dropped")
            sendMouse(w, .leftMouseUp, ruler.convert(NSPoint(x: 54, y: 20), to: nil))
            XCTAssertEqual(ruler.markers?.count, 1)
            XCTAssertEqual(fresh.markerLocation, 54)
            XCTAssertEqual(doc.events.last, "add 54.0")
            // A new client clears the markers.
            ruler.clientView = NSView(frame: .zero)
            XCTAssertNil(ruler.markers)
        }
    }

    func testTextViewIsTheRulerClient() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let sv = NSTextView.scrollableTextView()
            sv.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
            w.contentView = sv
            let tv = sv.documentView as! NSTextView
            XCTAssertTrue(tv.usesRuler)
            let ps = NSMutableParagraphStyle()
            ps.headIndent = 20
            ps.tabStops = [NSTextTab(textAlignment: .left, location: 100)]
            tv.textStorage!.setAttributedString(NSAttributedString(string: "one\ttwo\n", attributes: [.paragraphStyle: ps, .font: NSFont.systemFont(ofSize: 12)]))
            tv.setSelectedRange(NSRange(location: 1, length: 0))
            XCTAssertFalse(tv.isRulerVisible)
            tv.toggleRuler(nil)
            XCTAssertTrue(tv.isRulerVisible)
            let ruler = sv.horizontalRulerView!
            XCTAssertTrue(ruler.clientView === tv)
            let markers = ruler.markers ?? []
            XCTAssertEqual(markers.count, 4, "first-line, head and tail indents and one tab stop")
            let leading = tv._rulerLeadingX
            let tabMarker = markers.first { $0.representedObject is NSTextTab }!
            XCTAssertEqual(tabMarker.markerLocation, leading + 100)
            XCTAssertTrue(tabMarker.isRemovable)
            let head = markers.first { ($0.representedObject as? NSString) == NSTextView._headIndentMarker }!
            XCTAssertEqual(head.markerLocation, leading + 20)
            // Moving the tab stop marker moves the paragraph's tab stop.
            tabMarker.markerLocation = leading + 150
            tv.rulerView(ruler, didMove: tabMarker)
            let style = tv.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
            XCTAssertEqual(style.tabStops.map { $0.location }, [150])
            XCTAssertEqual(style.headIndent, 20)
            // Removing it removes the tab stop.
            let moved = (ruler.markers ?? []).first { $0.representedObject is NSTextTab }!
            tv.rulerView(ruler, didRemove: moved)
            XCTAssertTrue((tv.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).tabStops.isEmpty)
            tv.toggleRuler(nil)
            XCTAssertFalse(sv.rulersVisible)
        }
    }
}

// MARK: - NSDrawer

private final class DrawerRecorder: NSObject, NSDrawerDelegate, @unchecked Sendable {
    var events: [String] = []
    var allowOpen = true
    func drawerShouldOpen(_ sender: NSDrawer) -> Bool { events.append("shouldOpen"); return allowOpen }
    func drawerWillOpen(_ notification: Notification) { events.append("willOpen") }
    func drawerDidOpen(_ notification: Notification) { events.append("didOpen") }
    func drawerWillClose(_ notification: Notification) { events.append("willClose") }
    func drawerDidClose(_ notification: Notification) { events.append("didClose") }
}

final class DrawerTests: XCTestCase, @unchecked Sendable {
    private var savedDuration: TimeInterval = 0

    // The slide is off on the host backend but on (0.2 s) on a real one; the state and
    // frame checks want the drawer open at once, and the slide has its own test.
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            savedDuration = NSDrawer._animationDuration
            NSDrawer._animationDuration = 0
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { NSDrawer._animationDuration = savedDuration }
        super.tearDown()
    }

    func testOpenCloseStateAndFrames() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let d = NSDrawer(contentSize: NSSize(width: 150, height: 100), preferredEdge: .maxX)
            let r = DrawerRecorder()
            d.delegate = r
            let content = NSView(frame: .zero)
            d.contentView = content
            d.open()
            XCTAssertEqual(d.state, NSDrawer.State.closedState.rawValue, "no parent window: nothing to open from")
            d.parentWindow = w
            d.open()
            XCTAssertEqual(d.state, NSDrawer.State.openState.rawValue)
            XCTAssertEqual(r.events, ["shouldOpen", "willOpen", "didOpen"])
            XCTAssertEqual(d.edge, .maxX)
            let dw = d._drawerWindow!
            XCTAssertTrue(dw.isVisible)
            XCTAssertTrue(dw.parent === w, "a child window of the parent")
            XCTAssertFalse(dw.hasShadow, "no shadow frame: Win32 would keep a thick-frame window at least its border wide")
            let parentContent = w.contentRect(forFrameRect: w.frame)
            XCTAssertEqual(dw.frame, NSRect(x: w.frame.maxX, y: parentContent.minY, width: 162, height: parentContent.height))
            XCTAssertEqual(d.contentSize, NSSize(width: 150, height: parentContent.height - 12), "the height follows the parent")
            XCTAssertEqual(content.frame, NSRect(x: 6, y: 6, width: 150, height: parentContent.height - 12))
            // The parent moves: the drawer follows.
            w.setFrameOrigin(NSPoint(x: w.frame.minX + 30, y: w.frame.minY - 10))
            XCTAssertEqual(dw.frame.minX, w.frame.maxX)
            XCTAssertEqual(dw.frame.minY, w.contentRect(forFrameRect: w.frame).minY)
            // Offsets trim the drawer along the edge (leading from the top).
            d.leadingOffset = 20
            d.trailingOffset = 10
            XCTAssertEqual(dw.frame.height, w.contentRect(forFrameRect: w.frame).height - 30)
            XCTAssertEqual(dw.frame.minY, w.contentRect(forFrameRect: w.frame).minY + 10)
            d.toggle(nil)
            XCTAssertEqual(d.state, NSDrawer.State.closedState.rawValue)
            XCTAssertFalse(dw.isVisible)
            XCTAssertNil(w.childWindows)
            XCTAssertEqual(Array(r.events.suffix(2)), ["willClose", "didClose"])
            // The left edge.
            d.leadingOffset = 0; d.trailingOffset = 0
            d.open(on: .minX)
            XCTAssertEqual(d.edge, .minX)
            XCTAssertEqual(dw.frame.maxX, w.frame.minX)
            d.close()
            // A delegate can refuse.
            r.allowOpen = false
            d.open()
            XCTAssertEqual(d.state, NSDrawer.State.closedState.rawValue)
        }
    }

    func testContentSizeLimits() {
        MainActor.assumeIsolated {
            let d = NSDrawer(contentSize: NSSize(width: 150, height: 100), preferredEdge: .minY)
            d.minContentSize = NSSize(width: 50, height: 40)
            d.maxContentSize = NSSize(width: 300, height: 200)
            d.contentSize = NSSize(width: 10, height: 500)
            XCTAssertEqual(d.contentSize, NSSize(width: 50, height: 200))
            d.maxContentSize = NSSize(width: 40, height: 100)
            XCTAssertEqual(d.contentSize, NSSize(width: 40, height: 100), "a lower maximum clamps the current size")
            XCTAssertEqual(d.preferredEdge, .minY)
            XCTAssertEqual(d.edge, .minY)
        }
    }

    func testSlideOnTheFrameClock() {
        MainActor.assumeIsolated {
            let saved = NSDrawer._animationDuration
            NSDrawer._animationDuration = 0.2
            defer { NSDrawer._animationDuration = saved }
            withFakeClock { advance in
                let w = makeWindow()
                defer { w.close() }
                let d = NSDrawer(contentSize: NSSize(width: 100, height: 100), preferredEdge: .maxX)
                let content = NSView(frame: .zero)
                d.contentView = content
                d.parentWindow = w
                d.open()
                XCTAssertEqual(d.state, NSDrawer.State.openingState.rawValue)
                let dw = d._drawerWindow!
                XCTAssertEqual(dw.frame.width, 1, "starts at the parent's edge")
                XCTAssertEqual(dw.frame.minX, w.frame.maxX)
                advance(0.1)
                XCTAssertTrue(dw.frame.width > 56 && dw.frame.width < 112, "ease out: past half way at half time (\(dw.frame.width))")
                XCTAssertEqual(dw.frame.minX, w.frame.maxX)
                // The content is pinned to the outer edge: its right side shows first.
                XCTAssertEqual(content.convert(NSPoint(x: content.bounds.maxX, y: 0), to: nil).x, dw.frame.width - 6, accuracy: 0.5)
                advance(0.2)
                XCTAssertEqual(d.state, NSDrawer.State.openState.rawValue)
                XCTAssertEqual(dw.frame.width, 112)
                d.close()
                XCTAssertEqual(d.state, NSDrawer.State.closingState.rawValue)
                advance(0.1)
                XCTAssertTrue(dw.frame.width < 112 && dw.isVisible)
                // Opening again mid-close reverses from where it is.
                d.open()
                XCTAssertEqual(d.state, NSDrawer.State.openingState.rawValue)
                advance(0.3)
                XCTAssertEqual(d.state, NSDrawer.State.openState.rawValue)
                d.close()
                advance(0.3)
                XCTAssertEqual(d.state, NSDrawer.State.closedState.rawValue)
                XCTAssertFalse(dw.isVisible)
            }
        }
    }
}

// MARK: - NSScrubber

@MainActor
private final class ScrubberSource: NSObject, NSScrubberDataSource, NSScrubberFlowLayoutDelegate {
    var count = 10
    var widths: [CGFloat]? = nil
    var events: [String] = []
    func numberOfItems(for scrubber: NSScrubber) -> Int { count }
    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let v = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("text"), owner: nil) as! NSScrubberTextItemView
        v.title = "Item \(index)"
        return v
    }
    nonisolated func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt itemIndex: Int) -> NSSize {
        MainActor.assumeIsolated {
            guard let widths else { return layout.itemSize }
            return NSSize(width: widths[itemIndex], height: 30)
        }
    }
    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) { events.append("select \(selectedIndex)") }
    func scrubber(_ scrubber: NSScrubber, didChangeVisibleRange visibleRange: NSRange) { events.append("visible \(visibleRange.location)+\(visibleRange.length)") }
    func didBeginInteracting(with scrubber: NSScrubber) { events.append("begin") }
    func didFinishInteracting(with scrubber: NSScrubber) { events.append("finish") }
    func didCancelInteracting(with scrubber: NSScrubber) { events.append("cancel") }
}

final class ScrubberTests: XCTestCase, @unchecked Sendable {
    @MainActor private func scrubberSetup() -> (NSWindow, NSScrubber, ScrubberSource) {
        let w = makeWindow()
        let s = NSScrubber(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        s.register(NSScrubberTextItemView.self, forItemIdentifier: NSUserInterfaceItemIdentifier("text"))
        (s.scrubberLayout as! NSScrubberFlowLayout).itemSpacing = 10
        let src = ScrubberSource()
        w.contentView!.addSubview(s)
        s.delegate = src
        s.dataSource = src
        return (w, s, src)
    }

    func testFlowLayoutAttributesAndVisibleItems() {
        MainActor.assumeIsolated {
            let (w, s, src) = scrubberSetup()
            defer { w.close() }
            let layout = s.scrubberLayout as! NSScrubberFlowLayout
            XCTAssertEqual(layout.itemSize, NSSize(width: 50, height: 30))
            XCTAssertEqual(s.numberOfItems, 10)
            XCTAssertEqual(layout.layoutAttributesForItem(at: 2)?.frame, NSRect(x: 120, y: 0, width: 50, height: 30))
            XCTAssertEqual(layout.scrubberContentSize, NSSize(width: 590, height: 30))
            XCTAssertEqual(layout.visibleRect, NSRect(x: 0, y: 0, width: 200, height: 30))
            XCTAssertEqual(Set(layout.layoutAttributesForItems(in: layout.visibleRect).map { $0.itemIndex }), [0, 1, 2, 3])
            XCTAssertNotNil(s.itemViewForItem(at: 3))
            XCTAssertNil(s.itemViewForItem(at: 4))
            XCTAssertEqual((s.itemViewForItem(at: 1) as? NSScrubberTextItemView)?.title, "Item 1")
            XCTAssertEqual(s.itemViewForItem(at: 1)?.frame, NSRect(x: 60, y: 0, width: 50, height: 30))
            XCTAssertEqual(src.events.last, "visible 0+4")
            // Scrolling the last item to the trailing edge recycles the first ones.
            s.scrollItem(at: 9, to: .trailing)
            XCTAssertEqual(s._contentOffset, 390)
            XCTAssertNil(s.itemViewForItem(at: 0))
            XCTAssertNotNil(s.itemViewForItem(at: 9))
            XCTAssertEqual(src.events.last, "visible 6+4")
            s.scrollItem(at: 5, to: .center)
            XCTAssertEqual(s._contentOffset, 300 + 25 - 100)
            // Per-item sizes from the flow layout delegate.
            src.widths = (0..<10).map { CGFloat(20 + $0) }
            layout.invalidateLayout()
            XCTAssertEqual(layout.layoutAttributesForItem(at: 2)?.frame, NSRect(x: 20 + 21 + 20, y: 0, width: 22, height: 30))
            XCTAssertEqual(layout.scrubberContentSize.width, CGFloat((20...29).reduce(0, +) + 90))
            // The proportional layout divides the visible width.
            s.scrubberLayout = NSScrubberProportionalLayout(numberOfVisibleItems: 4)
            XCTAssertEqual(s.scrubberLayout.layoutAttributesForItem(at: 3)?.frame, NSRect(x: 150, y: 0, width: 50, height: 30))
            XCTAssertEqual(s.scrubberLayout.scrubberContentSize, NSSize(width: 500, height: 30))
            XCTAssertTrue(s.scrubberLayout.scrubber === s)
            XCTAssertNil(layout.scrubber, "the old layout is let go")
        }
    }

    func testSelection() {
        MainActor.assumeIsolated {
            let (w, s, src) = scrubberSetup()
            defer { w.close() }
            s.selectionBackgroundStyle = .roundedBackground
            XCTAssertEqual(s.selectedIndex, -1)
            src.events.removeAll()
            s.selectedIndex = 2
            XCTAssertEqual(s.selectedIndex, 2)
            XCTAssertTrue(src.events.isEmpty, "setting the selection does not call the delegate")
            XCTAssertTrue(s.itemViewForItem(at: 2)!.isSelected)
            let selectionView = s.itemViewForItem(at: 2)!.superview!.subviews.first { $0 is NSScrubberSelectionView }
            XCTAssertEqual(selectionView?.frame, NSRect(x: 120, y: 0, width: 50, height: 30), "the background sits at the selected item")
            XCTAssertTrue(s.itemViewForItem(at: 2)!.superview!.subviews.first === selectionView, "below the items")
            s.selectedIndex = 42
            XCTAssertEqual(s.selectedIndex, -1, "out of range: no selection")
            // A click selects and tells the delegate.
            let p = s.convert(NSPoint(x: 85, y: 15), to: nil)
            sendMouse(w, .leftMouseDown, p)
            XCTAssertEqual(s.highlightedIndex, 1)
            sendMouse(w, .leftMouseUp, p)
            XCTAssertEqual(s.selectedIndex, 1)
            XCTAssertEqual(s.highlightedIndex, -1)
            XCTAssertEqual(src.events, ["begin", "select 1", "finish"])
            // A drag in free mode scrolls instead.
            src.events.removeAll()
            sendMouse(w, .leftMouseDown, p)
            sendMouse(w, .leftMouseDragged, NSPoint(x: p.x - 60, y: p.y))
            XCTAssertEqual(s._contentOffset, 60)
            sendMouse(w, .leftMouseUp, NSPoint(x: p.x - 60, y: p.y))
            XCTAssertEqual(s.selectedIndex, 1)
            XCTAssertFalse(src.events.contains("select 1"))
            // Continuous: dragging over items selects them.
            s.scrollItem(at: 0, to: .leading)
            s.isContinuous = true
            src.events.removeAll()
            sendMouse(w, .leftMouseDown, s.convert(NSPoint(x: 10, y: 15), to: nil))
            sendMouse(w, .leftMouseDragged, s.convert(NSPoint(x: 140, y: 15), to: nil))
            sendMouse(w, .leftMouseUp, s.convert(NSPoint(x: 140, y: 15), to: nil))
            XCTAssertEqual(src.events.filter { $0.hasPrefix("select") }, ["select 0", "select 2"])
            XCTAssertEqual(s.selectedIndex, 2)
            // Removing items before the selection moves it; removing it clears it.
            src.count = 9
            s.removeItems(at: IndexSet(integer: 0))
            XCTAssertEqual(s.selectedIndex, 1)
            src.count = 8
            s.removeItems(at: IndexSet(integer: 1))
            XCTAssertEqual(s.selectedIndex, -1)
            src.count = 9
            s.selectedIndex = 3
            s.insertItems(at: IndexSet(integer: 0))
            XCTAssertEqual(s.selectedIndex, 4)
        }
    }

    func testItemReuseAndStyles() {
        MainActor.assumeIsolated {
            let (w, s, _) = scrubberSetup()
            defer { w.close() }
            let first = s.itemViewForItem(at: 0)!
            s.scrollItem(at: 9, to: .trailing)
            let reused = s.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("text"), owner: nil)
            XCTAssertNotNil(reused)
            XCTAssertNil(s.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("nothing"), owner: nil))
            _ = first
            XCTAssertNotNil(NSScrubberSelectionStyle.outlineOverlay.makeSelectionView())
            XCTAssertNil(NSScrubberSelectionStyle().makeSelectionView(), "the base style makes none")
            XCTAssertTrue(NSScrubberSelectionStyle.roundedBackground === NSScrubberSelectionStyle.roundedBackground)
            let attrs = NSScrubberLayoutAttributes(forItemAt: 3)
            attrs.frame = NSRect(x: 1, y: 2, width: 3, height: 4)
            attrs.alpha = 0.5
            let copy = attrs.copy() as! NSScrubberLayoutAttributes
            XCTAssertEqual(copy, attrs)
            XCTAssertEqual(copy.itemIndex, 3)
            let item = NSScrubberImageItemView(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
            XCTAssertEqual(item.imageView.frame, NSRect(x: 0, y: 0, width: 30, height: 30))
            item.apply(attrs)
            XCTAssertEqual(item.frame, attrs.frame)
            XCTAssertEqual(item.alphaValue, 0.5)
            s.showsArrowButtons = true
            XCTAssertEqual(s.scrubberLayout.visibleRect.width, 160, "arrow buttons take the ends")
        }
    }
}
