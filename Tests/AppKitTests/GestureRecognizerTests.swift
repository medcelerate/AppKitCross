// Gesture recognizers: the window routes mouse and gesture events to the recognizers of
// the hit view and its ancestors; each recognizer tracks its gesture and sends its
// action on every state change.

import XCTest
@testable import AppKit

final class GestureRecognizerTests: XCTestCase, @unchecked Sendable {
    @MainActor final class Log: NSObject {
        var states: [NSGestureRecognizer.State] = []
        var values: [CGFloat] = []
        func record(_ r: NSGestureRecognizer) {
            states.append(r.state)
            if let m = r as? NSMagnificationGestureRecognizer { values.append(m.magnification) }
            if let m = r as? NSRotationGestureRecognizer { values.append(m.rotationInDegrees) }
        }
    }

    @MainActor private func window() -> (NSWindow, NSView) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let v = NSView(frame: NSRect(x: 50, y: 50, width: 100, height: 100))
        w.contentView!.addSubview(v)
        return (w, v)
    }
    @MainActor private func mouse(_ w: NSWindow, _ type: NSEvent.EventType, _ p: NSPoint, clicks: Int = 1, t: TimeInterval = 0) {
        w.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: t, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!)
    }
    @MainActor private func hooked<R: NSGestureRecognizer>(_ r: R, _ log: Log) -> R {
        r.target = log
        r.action = Selector(("record:"))
        log.setActionHandler(for: Selector(("record:"))) { [log] sender in log.record(sender as! NSGestureRecognizer) }
        return r
    }

    func testClickRecognizesAReleaseWithoutMovementAndTheViewStillSeesTheEvents() {
        MainActor.assumeIsolated {
            let (w, v) = window()
            let log = Log()
            let click = hooked(NSClickGestureRecognizer(target: nil, action: nil), log)
            v.addGestureRecognizer(click)
            XCTAssertTrue(click.view === v)
            XCTAssertEqual(v.gestureRecognizers.count, 1)
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100))
            mouse(w, .leftMouseUp, NSPoint(x: 101, y: 100))
            XCTAssertEqual(log.states, [.ended], "a click is a discrete gesture: one action in the recognized state")
            XCTAssertEqual(click.state, .possible, "reset after the action")
            XCTAssertEqual(click.location(in: v), NSPoint(x: 51, y: 50))
            // Moving away before release fails the click.
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100))
            mouse(w, .leftMouseDragged, NSPoint(x: 130, y: 100))
            mouse(w, .leftMouseUp, NSPoint(x: 130, y: 100))
            XCTAssertEqual(log.states, [.ended])
            // Two clicks required: a single click does nothing, a double click fires.
            click.numberOfClicksRequired = 2
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100)); mouse(w, .leftMouseUp, NSPoint(x: 100, y: 100))
            XCTAssertEqual(log.states.count, 1)
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100), clicks: 2); mouse(w, .leftMouseUp, NSPoint(x: 100, y: 100), clicks: 2)
            XCTAssertEqual(log.states.count, 2)
            v.removeGestureRecognizer(click)
            XCTAssertNil(click.view)
            XCTAssertTrue(v.gestureRecognizers.isEmpty)
            w.close()
        }
    }

    func testPanReportsTranslationAndVelocityAndAncestorsReceiveEvents() {
        MainActor.assumeIsolated {
            let (w, v) = window()
            let inner = NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 50))
            v.addSubview(inner)
            let log = Log()
            let pan = hooked(NSPanGestureRecognizer(target: nil, action: nil), log)
            v.addGestureRecognizer(pan)           // on the parent; the hit view is `inner`
            var translations: [NSPoint] = []
            pan.setActionHandler(for: Selector(("noop:"))) { _ in }
            pan._actionHandler = { r in translations.append((r as! NSPanGestureRecognizer).translation(in: nil)) }
            mouse(w, .leftMouseDown, NSPoint(x: 70, y: 70), t: 0)
            mouse(w, .leftMouseDragged, NSPoint(x: 71, y: 70), t: 0.01)       // under the threshold
            XCTAssertEqual(pan.state, .possible)
            mouse(w, .leftMouseDragged, NSPoint(x: 80, y: 75), t: 0.02)
            XCTAssertEqual(pan.state, .began)
            mouse(w, .leftMouseDragged, NSPoint(x: 90, y: 85), t: 0.03)
            XCTAssertEqual(pan.state, .changed)
            XCTAssertEqual(pan.translation(in: nil), NSPoint(x: 20, y: 15))
            XCTAssertEqual(pan.velocity(in: nil).x, 1000, accuracy: 1)
            pan.setTranslation(.zero, in: nil)
            mouse(w, .leftMouseDragged, NSPoint(x: 95, y: 85), t: 0.04)
            XCTAssertEqual(pan.translation(in: nil), NSPoint(x: 5, y: 0), "translation restarts from the reset point")
            mouse(w, .leftMouseUp, NSPoint(x: 95, y: 85), t: 0.05)
            XCTAssertEqual(log.states, [.began, .changed, .changed, .ended])
            XCTAssertEqual(translations.last, NSPoint(x: 5, y: 0))
            XCTAssertEqual(pan.state, .possible)
            w.close()
        }
    }

    func testPressBeginsAfterTheMinimumDurationAndFailsOnMovement() {
        MainActor.assumeIsolated {
            let (w, v) = window()
            let log = Log()
            let press = hooked(NSPressGestureRecognizer(target: nil, action: nil), log)
            press.minimumPressDuration = 0.5
            v.addGestureRecognizer(press)
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100))
            XCTAssertEqual(press.state, .possible)
            press._pressTimerFired()                        // the duration elapsed
            XCTAssertEqual(press.state, .began)
            mouse(w, .leftMouseDragged, NSPoint(x: 120, y: 100))
            XCTAssertEqual(press.state, .changed, "movement after the press began continues it")
            mouse(w, .leftMouseUp, NSPoint(x: 120, y: 100))
            XCTAssertEqual(log.states, [.began, .changed, .ended])
            // Moving before the duration elapses fails the press; the release then does nothing.
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100))
            mouse(w, .leftMouseDragged, NSPoint(x: 130, y: 100))
            press._pressTimerFired()
            mouse(w, .leftMouseUp, NSPoint(x: 130, y: 100))
            XCTAssertEqual(log.states.count, 3)
            // A zero duration begins on the press itself.
            press.minimumPressDuration = 0
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100))
            XCTAssertEqual(press.state, .began)
            mouse(w, .leftMouseUp, NSPoint(x: 100, y: 100))
            w.close()
        }
    }

    func testMagnifyAndRotateAccumulateAndEndWithTheGesture() {
        MainActor.assumeIsolated {
            let (w, v) = window()
            let log = Log()
            let mag = hooked(NSMagnificationGestureRecognizer(target: nil, action: nil), log)
            let rot = hooked(NSRotationGestureRecognizer(target: nil, action: nil), log)
            v.addGestureRecognizer(mag)
            v.addGestureRecognizer(rot)
            final class Target: NSView {
                var magnifies = 0, rotates = 0
                override func magnify(with event: NSEvent) { magnifies += 1 }
                override func rotate(with event: NSEvent) { rotates += 1 }
            }
            let target = Target(frame: v.bounds)
            v.addSubview(target)
            let p = NSPoint(x: 100, y: 100)
            @MainActor func g(_ type: NSEvent.EventType, magnification: CGFloat = 0, rotation: Float = 0, phase: NSEvent.Phase = []) {
                w.sendEvent(NSEvent._gestureEvent(type: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                                  magnification: magnification, rotation: rotation, phase: phase))
            }
            g(.beginGesture)
            g(.magnify, magnification: 0.25, phase: .began)
            g(.magnify, magnification: 0.25, phase: .changed)
            g(.rotate, rotation: 10, phase: .began)
            g(.rotate, rotation: -4, phase: .changed)
            XCTAssertEqual(mag.state, .changed)
            XCTAssertEqual(mag.magnification, 0.5)
            XCTAssertEqual(rot.rotationInDegrees, 6, accuracy: 1e-9)
            XCTAssertEqual(rot.rotation, 6 * .pi / 180, accuracy: 1e-9)
            g(.endGesture)
            XCTAssertEqual(mag.state, .possible)
            XCTAssertEqual(rot.state, .possible)
            XCTAssertEqual(log.states, [.began, .changed, .began, .changed, .ended, .ended])
            XCTAssertEqual(log.values, [0.25, 0.5, 10, 6, 0.5, 6], "the final value is still readable in the ended action")
            // The view under the pointer saw the raw events too (no delays requested).
            XCTAssertEqual(target.magnifies, 2)
            XCTAssertEqual(target.rotates, 2)
            // An event phase of ended finishes a gesture without an endGesture event.
            g(.magnify, magnification: 0.1, phase: .began)
            g(.magnify, magnification: 0.1, phase: .ended)
            XCTAssertEqual(mag.state, .possible)
            XCTAssertEqual(log.states.suffix(2), [.changed, .ended])
            w.close()
        }
    }

    func testDelaysPrimaryMouseButtonEventsKeepsThemFromTheViewWhileTracking() {
        MainActor.assumeIsolated {
            let (w, v) = window()
            final class Target: NSView {
                var downs = 0, drags = 0, ups = 0
                override func mouseDown(with event: NSEvent) { downs += 1 }
                override func mouseDragged(with event: NSEvent) { drags += 1 }
                override func mouseUp(with event: NSEvent) { ups += 1 }
            }
            let target = Target(frame: v.bounds)
            v.addSubview(target)
            let pan = NSPanGestureRecognizer(target: nil, action: nil)
            pan.delaysPrimaryMouseButtonEvents = true
            v.addGestureRecognizer(pan)
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100))
            XCTAssertEqual(target.downs, 1, "nothing is tracking yet, so the view gets the press")
            mouse(w, .leftMouseDragged, NSPoint(x: 120, y: 100))
            mouse(w, .leftMouseDragged, NSPoint(x: 130, y: 100))
            XCTAssertEqual(pan.state, .changed)
            XCTAssertEqual(target.drags, 0, "drags are withheld while the pan tracks")
            mouse(w, .leftMouseUp, NSPoint(x: 130, y: 100))
            XCTAssertEqual(target.ups, 0)
            // Disabling cancels a tracking gesture; a delegate can veto the start.
            final class Veto: NSObject, NSGestureRecognizerDelegate {
                func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool { false }
            }
            let veto = Veto()
            pan.delegate = veto
            mouse(w, .leftMouseDown, NSPoint(x: 100, y: 100))
            mouse(w, .leftMouseDragged, NSPoint(x: 120, y: 100))
            XCTAssertEqual(pan.state, .possible)
            XCTAssertEqual(target.drags, 1, "a vetoed recognizer withholds nothing")
            mouse(w, .leftMouseUp, NSPoint(x: 120, y: 100))
            w.close()
        }
    }
}
