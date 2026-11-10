// NSPopover and NSSwitch on the host backend (ADR-0025): placement and edge flipping,
// the attached window following its parent, behaviour-driven closing with synthesized
// events, the delegate and notification order, detaching, the drawn arrow, the switch's
// state, mouse, keyboard and accessibility, and the SwiftUI `.switch` toggle style and
// `.popover` modifier.

import XCTest
@testable import AppKit
@testable import SwiftUI
import QuartzCore

/// A log notification observers (Sendable closures) can append to.
private final class Log: @unchecked Sendable {
    var events: [String] = []
    func add(_ s: String) { events.append(s) }
}

@MainActor
private final class Delegate: NSObject, NSPopoverDelegate {
    let log: Log
    var shouldClose = true
    var shouldDetach = false
    var detachable: NSWindow? = nil
    init(log: Log) { self.log = log }
    func popoverWillShow(_ notification: Notification) { log.add("delegate willShow") }
    func popoverDidShow(_ notification: Notification) { log.add("delegate didShow") }
    func popoverWillClose(_ notification: Notification) { log.add("delegate willClose \((notification.userInfo?[NSPopover.closeReasonUserInfoKey] as? NSPopover.CloseReason)?.rawValue ?? "?")") }
    func popoverDidClose(_ notification: Notification) { log.add("delegate didClose") }
    func popoverShouldClose(_ popover: NSPopover) -> Bool { log.add("delegate shouldClose"); return shouldClose }
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { shouldDetach }
    func detachableWindow(for popover: NSPopover) -> NSWindow? { detachable }
    func popoverDidDetach(_ popover: NSPopover) { log.add("delegate didDetach") }
}

@MainActor
private func makeWindow(origin: NSPoint = NSPoint(x: 300, y: 300), size: NSSize = NSSize(width: 400, height: 300)) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func makeContent(_ size: NSSize = NSSize(width: 200, height: 100)) -> NSViewController {
    let vc = NSViewController(nibName: nil, bundle: nil)
    let v = NSView(frame: NSRect(origin: .zero, size: size))
    let b = NSButton(title: "Inside", target: nil, action: nil)
    b.frame = NSRect(x: 10, y: 10, width: 80, height: 24)
    v.addSubview(b)
    vc.view = v
    vc.title = "Detached"
    return vc
}

@MainActor
private func makePopover(_ behavior: NSPopover.Behavior, delegate: Delegate? = nil, size: NSSize = NSSize(width: 200, height: 100)) -> NSPopover {
    let p = NSPopover()
    p.behavior = behavior
    p.animates = false
    p.delegate = delegate
    p.contentViewController = makeContent(size)
    return p
}

/// A click at a screen point, as the platform delivers it: to the frontmost window under
/// it, or with no window when nothing of ours is there.
@MainActor
private func clickScreen(_ p: NSPoint, in window: NSWindow? = nil) {
    let target = window ?? NSApplication.shared.windows.last { $0.isVisible && $0.frame.contains(p) }
    let local = target.map { $0.convertPoint(fromScreen: p) } ?? p
    for (type, pressure) in [(NSEvent.EventType.leftMouseDown, 1 as Float), (.leftMouseUp, 0)] {
        let e = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: 0, windowNumber: target?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure)!
        NSApplication.shared.sendEvent(e)
    }
}

@MainActor
private func mouse(_ type: NSEvent.EventType, at local: NSPoint, in window: NSWindow) {
    let e = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    NSApplication.shared.sendEvent(e)
}

@MainActor
private func key(_ chars: String, code: UInt16 = 0, in window: NSWindow) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    NSApplication.shared.sendEvent(e)
}

@MainActor
private func hostWindow(_ w: NSWindow) -> HostWindow? { w._platformWindow as? HostWindow }

/// BGRA of a pixel of the host window's last render, in points from the bottom-left.
@MainActor
private func pixel(_ w: NSWindow, x: Int, y: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8)? {
    guard let platform = hostWindow(w), let image = platform.lastImage else { return nil }
    let scale = Int(w.backingScaleFactor)
    let data = _pixels(image)
    let px = x * scale, py = (image.height - 1) - y * scale
    guard px >= 0, py >= 0, px < image.width, py < image.height else { return nil }
    let i = py * image.bytesPerRow + px * 4
    return (b: data[i], g: data[i + 1], r: data[i + 2], a: data[i + 3])
}

@MainActor
private final class Receiver: NSObject, NSSelectorHandling {
    var fired = 0
    static let act = Selector(("switched:"))
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action == Receiver.act else { return false }
        fired += 1
        return true
    }
}

final class PopoverTests: XCTestCase, @unchecked Sendable {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            NSPopover._animationDuration = 0
            NSSwitch._animationDuration = 0
            for w in NSApplication.shared.windows { w.close() }
        }
    }

    // MARK: Placement

    func testPlacementPrefersTheRequestedSideAndFlipsWhenThereIsNoRoom() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = NSRect(x: 400, y: 400, width: 80, height: 24)
        let size = NSSize(width: 200, height: 100)
        let below = _NSPopoverPlacement.compute(anchor: anchor, contentSize: size, preferredSide: .minY, screen: screen)
        XCTAssertEqual(below.side, .minY)
        XCTAssertEqual(below.frame.maxY, anchor.minY, "the arrow tip touches the anchor's bottom edge")
        XCTAssertEqual(below.frame.height, size.height + _NSPopoverPlacement.arrowHeight)
        XCTAssertEqual(below.frame.midX, anchor.midX, "centred on the anchor")
        XCTAssertEqual(below.arrowEdge, .maxY)
        XCTAssertEqual(below.arrowOffset, anchor.midX - below.frame.minX)
        XCTAssertEqual(below.bodyRect, NSRect(x: 0, y: 0, width: 200, height: 100))

        // Near the bottom of the screen there is no room below: it flips above.
        let low = NSRect(x: 400, y: 30, width: 80, height: 24)
        let flipped = _NSPopoverPlacement.compute(anchor: low, contentSize: size, preferredSide: .minY, screen: screen)
        XCTAssertEqual(flipped.side, .maxY)
        XCTAssertEqual(flipped.frame.minY, low.maxY)
        XCTAssertEqual(flipped.arrowEdge, .minY)
        XCTAssertEqual(flipped.bodyRect.minY, _NSPopoverPlacement.arrowHeight)

        // No room above or below (a tall popover): it goes beside the anchor, clamped to the screen.
        let tall = NSSize(width: 200, height: 700)
        let squeezed = _NSPopoverPlacement.compute(anchor: anchor, contentSize: tall, preferredSide: .maxY, screen: screen)
        XCTAssertEqual(squeezed.side, .minX, "neither above nor below fits; the left does")
        XCTAssertEqual(squeezed.frame.maxX, anchor.minX)
        XCTAssertGreaterThanOrEqual(squeezed.frame.minY, screen.minY, "clamped onto the screen")
        // Nothing fits at all: the side with the most room, clamped.
        let huge = NSSize(width: 900, height: 700)
        let crammed = _NSPopoverPlacement.compute(anchor: anchor, contentSize: huge, preferredSide: .maxY, screen: screen)
        XCTAssertEqual(crammed.side, .minY, "more room below (400) than above (376) or beside")
        XCTAssertGreaterThanOrEqual(crammed.frame.minY, screen.minY)

        // Beside the anchor: the right side, flipping to the left at the screen's right edge.
        let right = _NSPopoverPlacement.compute(anchor: anchor, contentSize: size, preferredSide: .maxX, screen: screen)
        XCTAssertEqual(right.side, .maxX)
        XCTAssertEqual(right.frame.minX, anchor.maxX)
        XCTAssertEqual(right.arrowEdge, .minX)
        XCTAssertEqual(right.bodyRect.minX, _NSPopoverPlacement.arrowHeight)
        let edgeAnchor = NSRect(x: 900, y: 400, width: 80, height: 24)
        let left = _NSPopoverPlacement.compute(anchor: edgeAnchor, contentSize: size, preferredSide: .maxX, screen: screen)
        XCTAssertEqual(left.side, .minX)
        XCTAssertEqual(left.frame.maxX, edgeAnchor.minX)
    }

    func testPlacementSlidesAlongTheEdgeAndKeepsTheArrowOverTheAnchor() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let anchor = NSRect(x: 950, y: 400, width: 40, height: 24)       // near the right edge
        let p = _NSPopoverPlacement.compute(anchor: anchor, contentSize: NSSize(width: 300, height: 100), preferredSide: .minY, screen: screen)
        XCTAssertEqual(p.side, .minY)
        XCTAssertEqual(p.frame.maxX, screen.maxX, "slid left to stay on screen")
        XCTAssertEqual(p.arrowOffset, anchor.midX - p.frame.minX, "the arrow still points at the anchor")
        // An anchor hanging off the screen: the arrow stops short of the rounded corner.
        let off = NSRect(x: 995, y: 400, width: 40, height: 24)
        let q = _NSPopoverPlacement.compute(anchor: off, contentSize: NSSize(width: 300, height: 100), preferredSide: .minY, screen: screen)
        XCTAssertEqual(q.arrowOffset, q.frame.width - _NSPopoverPlacement.cornerRadius - _NSPopoverPlacement.arrowBase / 2)
    }

    // MARK: Showing

    func testShowAttachesAWindowBelowTheViewAndReportsTheDelegateInOrder() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let button = NSButton(title: "Show", target: nil, action: nil)
            button.frame = NSRect(x: 100, y: 200, width: 80, height: 24)
            w.contentView!.addSubview(button)
            let log = Log()
            let d = Delegate(log: log)
            let p = makePopover(.applicationDefined, delegate: d)
            let names: [(NSNotification.Name, String)] = [(NSPopover.willShowNotification, "willShow"), (NSPopover.didShowNotification, "didShow"), (NSPopover.willCloseNotification, "willClose"), (NSPopover.didCloseNotification, "didClose")]
            let observers = names.map { pair in NotificationCenter.default.addObserver(forName: pair.0, object: p, queue: nil) { _ in log.add("note \(pair.1)") } }
            defer { observers.forEach { NotificationCenter.default.removeObserver($0) } }
            XCTAssertFalse(p.isShown)
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            XCTAssertTrue(p.isShown)
            XCTAssertFalse(p.isDetached)
            let pw = try! XCTUnwrap(p._window)
            XCTAssertTrue(pw.isVisible)
            XCTAssertTrue(pw.parent === w, "a child of the positioning view's window")
            XCTAssertTrue(w.childWindows?.contains { $0 === pw } ?? false)
            XCTAssertTrue(pw.isKeyWindow, "the popover takes the keyboard")
            XCTAssertTrue(hostWindow(pw)?.sheetParent === hostWindow(w), "attached through the platform seam")
            let anchor = w.convertToScreen(button.convert(button.bounds, to: nil))
            XCTAssertEqual(pw.frame.maxY, anchor.minY, "hangs under the button")
            XCTAssertEqual(pw.frame.midX, anchor.midX)
            XCTAssertEqual(pw.frame.size, NSSize(width: 200, height: 100 + _NSPopoverPlacement.arrowHeight))
            XCTAssertEqual(p.contentViewController!.view.frame, NSRect(x: 0, y: 0, width: 200, height: 100), "the content fills the body")
            XCTAssertTrue(p.contentViewController!.view.window === pw)
            XCTAssertEqual(pw.accessibilityTree().role, NSAccessibility.Role.popover.rawValue)
            XCTAssertEqual(log.events, ["note willShow", "delegate willShow", "note didShow", "delegate didShow"])
            log.events.removeAll()
            p.close()
            XCTAssertFalse(p.isShown)
            XCTAssertNil(p._window)
            XCTAssertFalse(pw.isVisible)
            XCTAssertNil(p.contentViewController!.view.window)
            XCTAssertTrue(w.isKeyWindow, "the parent takes the keyboard back")
            XCTAssertEqual(log.events, ["note willClose", "delegate willClose NSPopoverCloseReasonStandard", "note didClose", "delegate didClose"])
            w.close()
        }
    }

    func testPreferredEdgeIsInTheViewsCoordinatesAndFlipsAtTheScreenEdge() {
        MainActor.assumeIsolated {
            final class Flipped: NSView { override var isFlipped: Bool { true } }
            let w = makeWindow()
            let v = Flipped(frame: NSRect(x: 100, y: 100, width: 80, height: 24))
            w.contentView!.addSubview(v)
            let p = makePopover(.applicationDefined)
            // In a flipped view maxY is the bottom edge: the popover hangs below.
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .maxY)
            let anchor = w.convertToScreen(v.convert(v.bounds, to: nil))
            XCTAssertEqual(p._placement?.side, .minY)
            XCTAssertEqual(p._window!.frame.maxY, anchor.minY)
            p.close()
            // At the bottom of the screen the same request flips above.
            let low = makeWindow(origin: NSPoint(x: 300, y: 0))
            let lv = Flipped(frame: NSRect(x: 100, y: 10, width: 80, height: 24))
            low.contentView!.addSubview(lv)
            p.show(relativeTo: lv.bounds, of: lv, preferredEdge: .maxY)
            XCTAssertEqual(p._placement?.side, .maxY)
            XCTAssertEqual(p._window!.frame.minY, low.convertToScreen(lv.convert(lv.bounds, to: nil)).maxY)
            p.close()
            w.close(); low.close()
        }
    }

    func testPopoverFollowsTheParentWindowAndContentSizeChanges() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 50, y: 50, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let p = makePopover(.applicationDefined)
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .maxY)
            let before = p._window!.frame
            w.setFrameOrigin(NSPoint(x: 340, y: 330))
            XCTAssertEqual(p._window!.frame, before.offsetBy(dx: 40, dy: 30), "moved with the parent")
            p.contentSize = NSSize(width: 240, height: 60)
            XCTAssertEqual(p._window!.frame.size, NSSize(width: 240, height: 60 + _NSPopoverPlacement.arrowHeight))
            XCTAssertEqual(p.contentViewController!.view.frame.size, NSSize(width: 240, height: 60))
            XCTAssertEqual(p._window!.frame.minY, w.convertToScreen(v.convert(v.bounds, to: nil)).maxY, "still on the anchor")
            // The parent closing closes the popover.
            let log = Log()
            let o = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: p, queue: nil) { _ in log.add("closed") }
            defer { NotificationCenter.default.removeObserver(o) }
            w.close()
            XCTAssertEqual(log.events, ["closed"])
            XCTAssertFalse(p.isShown)
        }
    }

    func testFrameViewDrawsTheBodyAndTheArrowOverTransparency() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let p = makePopover(.applicationDefined)
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .maxY)        // above: the arrow at the bottom
            let pw = p._window!
            pw.display()
            let placement = p._placement!
            XCTAssertEqual(placement.arrowEdge, .minY)
            let tipX = Int(placement.arrowOffset)
            // Inside the arrow, just above its tip: painted. Beside the arrow at the same height: clear.
            let inArrow = pixel(pw, x: tipX, y: 3)
            let besideArrow = pixel(pw, x: tipX + 30, y: 3)
            let inBody = pixel(pw, x: 100, y: 60)
            let corner = pixel(pw, x: 0, y: Int(pw.frame.height) - 1)
            XCTAssertEqual(inArrow?.a, 255)
            XCTAssertEqual(inBody?.a, 255)
            XCTAssertEqual(besideArrow?.a, 0, "transparent around the arrow")
            XCTAssertEqual(corner?.a, 0, "transparent rounded corner")
            // Where the platform shows no transparency the surround is the parent's background.
            pw.frameView.opaqueBacking = NSColor.systemRed
            pw.display()
            let backing = pixel(pw, x: tipX + 30, y: 3)
            XCTAssertEqual(backing?.a, 255)
            XCTAssertGreaterThan(backing?.r ?? 0, 200)
            p.close()
            w.close()
        }
    }

    // MARK: Behaviour

    func testTransientClosesOnAnyClickOutsideButNotInside() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let other = makeWindow(origin: NSPoint(x: 900, y: 300))
            w.makeKeyAndOrderFront(nil)
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let log = Log()
            let d = Delegate(log: log)
            let p = makePopover(.transient, delegate: d)
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            let pw = p._window!
            // A click inside the popover (on its button) keeps it.
            clickScreen(pw.convertPoint(toScreen: NSPoint(x: 30, y: 20)), in: pw)
            XCTAssertTrue(p.isShown)
            // A click elsewhere in the parent closes it, through popoverShouldClose.
            clickScreen(w.convertPoint(toScreen: NSPoint(x: 300, y: 250)), in: w)
            XCTAssertFalse(p.isShown)
            XCTAssertEqual(log.events.filter { $0.hasPrefix("delegate shouldClose") }.count, 1)
            // A click in another window closes it too.
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            clickScreen(other.convertPoint(toScreen: NSPoint(x: 10, y: 10)), in: other)
            XCTAssertFalse(p.isShown)
            // And so does a click on nothing of ours (the desktop).
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            clickScreen(NSPoint(x: 5, y: 5), in: nil)
            XCTAssertFalse(p.isShown)
            // The delegate can refuse.
            d.shouldClose = false
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            clickScreen(w.convertPoint(toScreen: NSPoint(x: 300, y: 250)), in: w)
            XCTAssertTrue(p.isShown, "popoverShouldClose said no")
            d.shouldClose = true
            p.close()
            w.close(); other.close()
        }
    }

    func testSemitransientClosesOnlyOnClicksInTheParentWindow() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let other = makeWindow(origin: NSPoint(x: 900, y: 300))
            w.makeKeyAndOrderFront(nil)
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let p = makePopover(.semitransient)
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            clickScreen(other.convertPoint(toScreen: NSPoint(x: 10, y: 10)), in: other)
            XCTAssertTrue(p.isShown, "another window is not the parent")
            clickScreen(NSPoint(x: 5, y: 5), in: nil)
            XCTAssertTrue(p.isShown, "nor is the desktop")
            clickScreen(w.convertPoint(toScreen: NSPoint(x: 300, y: 250)), in: w)
            XCTAssertFalse(p.isShown, "a click in the parent's content closes it")
            w.close(); other.close()
        }
    }

    func testApplicationDefinedClosesOnlyProgrammaticallyAndEscapeClosesTheOthers() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let p = makePopover(.applicationDefined)
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            clickScreen(w.convertPoint(toScreen: NSPoint(x: 300, y: 250)), in: w)
            clickScreen(NSPoint(x: 5, y: 5), in: nil)
            key("\u{1B}", code: 53, in: p._window!)
            XCTAssertTrue(p.isShown, "nothing but the application closes it")
            p.performClose(nil)
            XCTAssertFalse(p.isShown)
            let t = makePopover(.transient)
            t.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            key("\u{1B}", code: 53, in: t._window!)
            XCTAssertFalse(t.isShown, "Escape closes a transient popover")
            w.close()
        }
    }

    func testKeysReachThePopoverThroughTheParentWindow() {
        MainActor.assumeIsolated {
            // On Wayland the popover is a subsurface and the parent toplevel keeps the
            // keyboard: keys sent to the parent reach the popover's first responder.
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let p = makePopover(.applicationDefined)
            let r = Receiver()
            let inside = p.contentViewController!.view.subviews.compactMap { $0 as? NSButton }.first!
            inside.target = r
            inside.action = Receiver.act
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            _ = p._window!.makeFirstResponder(inside)
            key(" ", code: 49, in: w)
            XCTAssertEqual(r.fired, 1, "Space on the parent pressed the popover's button")
            p.close()
            w.close()
        }
    }

    // MARK: Detaching

    func testDraggingDetachesIntoATitledWindowWhenTheDelegateAllows() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let log = Log()
            let d = Delegate(log: log)
            let p = makePopover(.applicationDefined, delegate: d)
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            let pw = p._window!
            // Not detachable: a drag on the background does nothing.
            mouse(.leftMouseDown, at: NSPoint(x: 150, y: 80), in: pw)
            mouse(.leftMouseDragged, at: NSPoint(x: 170, y: 70), in: pw)
            mouse(.leftMouseUp, at: NSPoint(x: 170, y: 70), in: pw)
            XCTAssertFalse(p.isDetached)
            XCTAssertNotNil(p._window)
            d.shouldDetach = true
            let body = pw.convertToScreen(pw.frameView.bodyRect)
            mouse(.leftMouseDown, at: NSPoint(x: 150, y: 80), in: pw)
            mouse(.leftMouseDragged, at: NSPoint(x: 170, y: 70), in: pw)
            XCTAssertTrue(p.isDetached)
            XCTAssertTrue(p.isShown, "still shown, in a window of its own")
            XCTAssertNil(p._window)
            let detached = try! XCTUnwrap(p._detachedWindow)
            XCTAssertTrue(detached.styleMask.contains(.titled))
            XCTAssertEqual(detached.title, "Detached")
            XCTAssertTrue(detached.isVisible)
            XCTAssertTrue(p.contentViewController!.view.window === detached, "the content moved into it")
            XCTAssertEqual(detached.contentRect(forFrameRect: detached.frame), body.offsetBy(dx: 20, dy: -10), "where the body was, moved by the drag")
            XCTAssertEqual(log.events.filter { $0.hasPrefix("delegate didDetach") }.count, 1)
            XCTAssertFalse(log.events.contains { $0.hasPrefix("delegate willClose") })
            // Closing the detached window closes the popover.
            detached.performClose(nil)
            XCTAssertFalse(p.isShown)
            XCTAssertFalse(p.isDetached)
            XCTAssertTrue(log.events.contains("delegate willClose NSPopoverCloseReasonStandard"))
            w.close()
        }
    }

    func testDraggingShowsTheDelegatesWindowAndClosesWithTheDetachReason() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let log = Log()
            let d = Delegate(log: log)
            let custom = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 140), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            custom.isReleasedWhenClosed = false
            d.detachable = custom
            let p = makePopover(.semitransient, delegate: d)
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            let pw = p._window!
            let body = pw.convertToScreen(pw.frameView.bodyRect)
            mouse(.leftMouseDown, at: NSPoint(x: 150, y: 80), in: pw)
            mouse(.leftMouseDragged, at: NSPoint(x: 160, y: 80), in: pw)
            XCTAssertFalse(p.isShown, "closed in favour of the delegate's window")
            XCTAssertFalse(p.isDetached)
            XCTAssertTrue(custom.isVisible)
            let content = custom.contentRect(forFrameRect: custom.frame)
            XCTAssertEqual(NSPoint(x: content.minX, y: content.maxY), NSPoint(x: body.minX + 10, y: body.maxY), "top-left aligned with the body")
            XCTAssertEqual(log.events.filter { $0.hasPrefix("delegate willClose") }, ["delegate willClose NSPopoverCloseReasonDetachToWindow"])
            XCTAssertEqual(log.events.last, "delegate didDetach")
            custom.close()
            w.close()
        }
    }

    func testPopAnimationSlidesOutOfTheAnchorOnTheDisplayLink() {
        MainActor.assumeIsolated {
            NSPopover._animationDuration = 0.2
            defer { NSPopover._animationDuration = 0 }
            let savedNow = CARuntime.now
            var clock: CFTimeInterval = 100
            CARuntime.now = { clock }
            defer { CARuntime.now = savedNow }
            let w = makeWindow()
            let v = NSView(frame: NSRect(x: 100, y: 100, width: 60, height: 20))
            w.contentView!.addSubview(v)
            let log = Log()
            let d = Delegate(log: log)                 // the delegate is weak: keep it
            let p = makePopover(.applicationDefined, delegate: d)
            p.animates = true
            p.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
            let final = p._placement!.frame
            XCTAssertEqual(p._window!.frame, final.offsetBy(dx: 0, dy: 8), "starts into the anchor")
            XCTAssertFalse(log.events.contains("delegate didShow"), "didShow waits for the animation")
            clock = 100.1; CARuntime.tick()
            XCTAssertLessThan(p._window!.frame.minY, final.minY + 8)
            XCTAssertGreaterThan(p._window!.frame.minY, final.minY)
            clock = 100.3; CARuntime.tick()
            XCTAssertEqual(p._window!.frame, final)
            XCTAssertTrue(log.events.contains("delegate didShow"))
            p.close()
            w.close()
        }
    }

    func testViewControllerPresentsAsPopover() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let host = NSViewController(nibName: nil, bundle: nil)
            host.view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            w.contentViewController = host
            let content = makeContent()
            host.present(content, asPopoverRelativeTo: NSRect(x: 100, y: 100, width: 50, height: 20), of: host.view, preferredEdge: .minY, behavior: .transient)
            XCTAssertEqual(host.presentedViewControllers?.count, 1)
            let pw = try! XCTUnwrap(content.view.window as? _NSPopoverWindow)
            XCTAssertTrue(pw.isVisible)
            content.dismiss(nil)
            XCTAssertNil(host.presentedViewControllers)
            XCTAssertFalse(pw.isVisible)
            w.close()
        }
    }

    // MARK: NSSwitch

    func testSwitchTogglesByClickSpaceAndDragAndSendsItsAction() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let s = NSSwitch(frame: .zero)
            XCTAssertEqual(s.frame.size, NSSize(width: 38, height: 22), "the regular size")
            s.frame.origin = NSPoint(x: 50, y: 50)
            w.contentView!.addSubview(s)
            let r = Receiver()
            s.target = r
            s.action = Receiver.act
            XCTAssertEqual(s.state, .off)
            s.performClick(nil)
            XCTAssertEqual(s.state, .on)
            XCTAssertEqual(r.fired, 1)
            // A click: down and up inside.
            mouse(.leftMouseDown, at: NSPoint(x: 60, y: 60), in: w)
            XCTAssertTrue(s.isHighlighted)
            mouse(.leftMouseUp, at: NSPoint(x: 60, y: 60), in: w)
            XCTAssertEqual(s.state, .off)
            XCTAssertEqual(r.fired, 2)
            // Space on the focused switch.
            _ = w.makeFirstResponder(s)
            key(" ", code: 49, in: w)
            XCTAssertEqual(s.state, .on)
            XCTAssertEqual(r.fired, 3)
            // Dragging the knob to the off side sets the state once, on release.
            mouse(.leftMouseDown, at: NSPoint(x: 80, y: 60), in: w)
            mouse(.leftMouseDragged, at: NSPoint(x: 55, y: 60), in: w)
            XCTAssertEqual(s.state, .on, "not yet")
            mouse(.leftMouseUp, at: NSPoint(x: 55, y: 60), in: w)
            XCTAssertEqual(s.state, .off)
            XCTAssertEqual(r.fired, 4)
            // A drag that stays on the same side changes nothing and sends nothing.
            mouse(.leftMouseDown, at: NSPoint(x: 55, y: 60), in: w)
            mouse(.leftMouseDragged, at: NSPoint(x: 58, y: 60), in: w)
            mouse(.leftMouseUp, at: NSPoint(x: 58, y: 60), in: w)
            XCTAssertEqual(s.state, .off)
            XCTAssertEqual(r.fired, 4)
            // Disabled: nothing.
            s.isEnabled = false
            s.performClick(nil)
            key(" ", code: 49, in: w)
            XCTAssertEqual(s.state, .off)
            XCTAssertEqual(r.fired, 4)
            s.isEnabled = true
            // Setting the state does not send the action; mixed reads as on.
            s.state = .mixed
            XCTAssertEqual(s.state, .on)
            XCTAssertEqual(r.fired, 4)
            w.close()
        }
    }

    func testSwitchKnobAnimatesOnTheDisplayLinkAndDrawsPerState() {
        MainActor.assumeIsolated {
            NSSwitch._animationDuration = 0.2
            defer { NSSwitch._animationDuration = 0 }
            let savedNow = CARuntime.now
            var clock: CFTimeInterval = 50
            CARuntime.now = { clock }
            defer { CARuntime.now = savedNow }
            let w = makeWindow()
            let s = NSSwitch(frame: NSRect(x: 50, y: 50, width: 38, height: 22))
            w.contentView!.addSubview(s)
            w.display()
            // Off: the track is grey (no accent) and the knob on the left.
            let offTrack = pixel(w, x: 50 + 30, y: 50 + 11)!
            XCTAssertTrue(abs(Int(offTrack.r) - Int(offTrack.g)) < 12 && abs(Int(offTrack.g) - Int(offTrack.b)) < 12, "grey track when off: \(offTrack)")
            let knobLeft = pixel(w, x: 50 + 11, y: 50 + 11)!
            XCTAssertGreaterThan(knobLeft.r, 240, "white knob at the left")
            s.performClick(nil)                      // animates to on
            XCTAssertEqual(s.state, .on)
            clock = 50.05; CARuntime.tick(); w.displayIfNeeded()
            let mid = s._knobRect(at: 0.5)
            XCTAssertTrue(s._knobRect(at: 0).minX < mid.minX, "the knob is on its way")
            clock = 50.3; CARuntime.tick(); w.displayIfNeeded()
            let onTrack = pixel(w, x: 50 + 8, y: 50 + 11)!
            XCTAssertGreaterThan(onTrack.b, onTrack.r, "the accent fills the track when on: \(onTrack)")
            let knobRight = pixel(w, x: 50 + 27, y: 50 + 11)!
            XCTAssertGreaterThan(knobRight.r, 240, "white knob at the right")
            w.close()
        }
    }

    func testSwitchAccessibilityIsACheckBoxWithTheSwitchSubrole() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let s = NSSwitch(frame: NSRect(x: 50, y: 50, width: 38, height: 22))
            s.setAccessibilityLabel("Wi-Fi")
            w.contentView!.addSubview(s)
            let tree = w.accessibilityTree()
            let e = try! XCTUnwrap(tree.flattened.first { $0.role == NSAccessibility.Role.checkBox.rawValue })
            XCTAssertEqual(e.subrole, NSAccessibility.Subrole.switch.rawValue)
            XCTAssertEqual(e.label, "Wi-Fi")
            XCTAssertEqual(e.value, .number(0))
            XCTAssertTrue(e.isSettable)
            XCTAssertTrue(e.actions.contains(.press))
            XCTAssertTrue(w.accessibilityPerform(.press, on: e.id))
            XCTAssertEqual(s.state, .on)
            XCTAssertEqual(w.accessibilityTree().element(withID: e.id)?.value, .number(1))
            XCTAssertTrue(w.accessibilitySetValue(.number(0), on: e.id))
            XCTAssertEqual(s.state, .off)
            XCTAssertTrue(hostWindow(w)!.accessibilityChanges.contains(.value(e.id)))
            w.close()
        }
    }

    // MARK: SwiftUI

    func testSwiftUIToggleWithTheSwitchStyleIsAnNSSwitch() {
        MainActor.assumeIsolated {
            struct Root: View {
                @State var on = true
                var body: some View {
                    VStack {
                        Toggle("Wi-Fi", isOn: $on).toggleStyle(.switch)
                        Toggle("Plain", isOn: $on)
                        Text(on ? "on" : "off")
                    }
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Root())
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            @MainActor func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            let switches = all(h).compactMap { $0 as? NSSwitch }
            let checkboxes = all(h).compactMap { $0 as? NSButton }
            XCTAssertEqual(switches.count, 1)
            XCTAssertEqual(checkboxes.count, 1, "the default style stays a check box")
            let s = switches[0]
            XCTAssertEqual(s.state, .on)
            let row = try! XCTUnwrap(s.superview as? _SwiftUISwitchRow)
            XCTAssertEqual(row.label.stringValue, "Wi-Fi")
            XCTAssertGreaterThan(s.frame.minX, row.label.frame.maxX, "the switch sits after its label")
            s.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(checkboxes[0].state, .off, "the binding changed")
            XCTAssertTrue(all(h).compactMap { ($0 as? _TextView)?.storage.string }.contains("off"))
            checkboxes[0].performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(s.state, .on, "and back through the binding")
            w.close()
        }
    }

    func testSwiftUIPopoverPresentsAnNSPopoverOnTheView() {
        MainActor.assumeIsolated {
            struct Root: View {
                @State var showing = false
                var body: some View {
                    VStack {
                        Button("Open") { showing = true }
                            .popover(isPresented: $showing, arrowEdge: .top) { Inner() }
                    }
                }
            }
            struct Inner: View {
                @Environment(\.dismiss) var dismiss
                var body: some View { VStack { Text("Popover body"); Button("Done") { dismiss() } } }
            }
            let w = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Root())
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            @MainActor func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
            let open = all(h).compactMap { $0 as? NSButton }.first { $0.title == "Open" }!
            open.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(NSPopover._shown.count, 1)
            let p = NSPopover._shown[0]
            XCTAssertEqual(p.behavior, .transient)
            let pw = try! XCTUnwrap(p._window)
            XCTAssertTrue(pw.parent === w)
            let anchor = w.convertToScreen(open.convert(open.bounds, to: nil))
            XCTAssertEqual(pw.frame.maxY, anchor.minY, "arrowEdge .top: the popover hangs below the button")
            XCTAssertTrue(all(pw.contentView!).compactMap { ($0 as? _TextView)?.storage.string }.contains("Popover body"))
            all(pw.contentView!).compactMap { $0 as? NSButton }.first { $0.title == "Done" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertFalse(p.isShown, "dismiss closes it")
            XCTAssertTrue(NSPopover._shown.isEmpty)
            // Shown again and closed by a click outside: the binding clears, so it stays closed.
            open.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertEqual(NSPopover._shown.count, 1)
            clickScreen(w.convertPoint(toScreen: NSPoint(x: 280, y: 10)), in: w)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(NSPopover._shown.isEmpty)
            w.close()
        }
    }
}
