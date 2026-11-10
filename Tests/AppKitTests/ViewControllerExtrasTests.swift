// NSTrackingArea option semantics against synthesized mouse events, the title bar
// accessories' placement per layout attribute and direction, and NSPageController's
// navigation, delegate order and transitions (ADR-0022).

import XCTest
@testable import AppKit
import SwiftUI

@MainActor
private func makeWindow(_ mask: NSWindow.StyleMask = [.titled, .closable, .resizable], width: CGFloat = 400, height: CGFloat = 300) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height), styleMask: mask, backing: .buffered, defer: false)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func moveMouse(_ w: NSWindow, to p: NSPoint, type: NSEvent.EventType = .mouseMoved) {
    let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
    NSApplication.shared.sendEvent(e)
}

/// A view that logs the tracking messages it receives.
@MainActor
private final class TrackedView: NSView {
    var log: [String] = []
    var cursor: NSCursor?
    override func mouseEntered(with event: NSEvent) { log.append("entered:\(event.trackingArea?.userInfo?["name"] as? String ?? "-")") }
    override func mouseExited(with event: NSEvent) { log.append("exited:\(event.trackingArea?.userInfo?["name"] as? String ?? "-")") }
    override func mouseMoved(with event: NSEvent) { log.append("moved:\(Int(event.locationInWindow.x))") }
    override func cursorUpdate(with event: NSEvent) { log.append("cursor"); (cursor ?? NSCursor.crosshair).set() }
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Tracking areas

final class TrackingAreaTests: XCTestCase, @unchecked Sendable {
    @MainActor private func setUpTracked(_ options: NSTrackingArea.Options, rect: NSRect = NSRect(x: 50, y: 50, width: 100, height: 100), name: String = "a") -> (NSWindow, TrackedView, NSTrackingArea) {
        let w = makeWindow()
        let v = TrackedView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        w.contentView = v
        let area = NSTrackingArea(rect: rect, options: options, owner: v, userInfo: ["name": name])
        v.addTrackingArea(area)
        return (w, v, area)
    }

    func testAreaPropertiesAndViewBookkeeping() {
        MainActor.assumeIsolated {
            let (w, v, area) = setUpTracked([.mouseEnteredAndExited, .activeInKeyWindow])
            defer { w.close() }
            XCTAssertEqual(area.rect, NSRect(x: 50, y: 50, width: 100, height: 100))
            XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
            XCTAssertTrue(area.owner === v)
            XCTAssertEqual(area.userInfo?["name"] as? String, "a")
            XCTAssertEqual(v.trackingAreas.count, 1)
            XCTAssertTrue(v.trackingAreas[0] === area)
            let copy = area.copy() as! NSTrackingArea
            XCTAssertEqual(copy.rect, area.rect)
            XCTAssertTrue(copy.owner === v)
            v.removeTrackingArea(area)
            XCTAssertTrue(v.trackingAreas.isEmpty)
        }
    }

    func testEnteredAndExitedFollowTheMouseMoveStream() {
        MainActor.assumeIsolated {
            let (w, v, area) = setUpTracked([.mouseEnteredAndExited, .activeInKeyWindow])
            defer { w.close() }
            moveMouse(w, to: NSPoint(x: 10, y: 10))
            XCTAssertEqual(v.log, [], "outside: nothing")
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertEqual(v.log, ["entered:a"], "the entered event carries the area and its user info")
            moveMouse(w, to: NSPoint(x: 80, y: 80))
            XCTAssertEqual(v.log, ["entered:a"], "moves inside do not repeat the entry, and no mouseMoved without the option")
            moveMouse(w, to: NSPoint(x: 200, y: 200))
            XCTAssertEqual(v.log, ["entered:a", "exited:a"])
            // Leaving the window (the backends send a far-away move) exits too.
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            moveMouse(w, to: NSPoint(x: -100_000, y: -100_000))
            XCTAssertEqual(v.log, ["entered:a", "exited:a", "entered:a", "exited:a"])
            XCTAssertTrue(area._view === v)
        }
    }

    func testMouseMovedOnlyForAreasThatAskForIt() {
        MainActor.assumeIsolated {
            let (w, v, _) = setUpTracked([.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow])
            defer { w.close() }
            XCTAssertFalse(w.acceptsMouseMovedEvents, "the window's own moved events stay off")
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            moveMouse(w, to: NSPoint(x: 70, y: 60))
            moveMouse(w, to: NSPoint(x: 80, y: 60))
            XCTAssertEqual(v.log, ["entered:a", "moved:70", "moved:80"])
            moveMouse(w, to: NSPoint(x: 10, y: 10))
            moveMouse(w, to: NSPoint(x: 20, y: 10))
            XCTAssertEqual(v.log, ["entered:a", "moved:70", "moved:80", "exited:a"], "no moved events outside the area")
        }
    }

    func testCursorUpdateSetsTheCursorPerAreaAndCursorRectsStandBack() {
        MainActor.assumeIsolated {
            let (w, v, _) = setUpTracked([.cursorUpdate, .activeInKeyWindow])
            defer { w.close() }
            v.cursor = NSCursor.pointingHand
            moveMouse(w, to: NSPoint(x: 10, y: 10))
            XCTAssertTrue(NSCursor.current === NSCursor.arrow)
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertEqual(v.log, ["cursor"], "cursorUpdate on entry, no entered event without mouseEnteredAndExited")
            XCTAssertTrue(NSCursor.current === NSCursor.pointingHand)
            moveMouse(w, to: NSPoint(x: 70, y: 70))
            XCTAssertTrue(NSCursor.current === NSCursor.pointingHand, "the cursor rects do not reset it while inside")
            moveMouse(w, to: NSPoint(x: 10, y: 10))
            XCTAssertTrue(NSCursor.current === NSCursor.arrow, "leaving hands the cursor back")
            XCTAssertEqual(v.log, ["cursor"])
            // The window ends the cursorUpdate chain with the arrow.
            let plain = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            w.contentView = plain
            plain.addTrackingArea(NSTrackingArea(rect: plain.bounds, options: [.cursorUpdate, .activeAlways], owner: plain))
            NSCursor.crosshair.set()
            moveMouse(w, to: NSPoint(x: 100, y: 100))
            XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        }
    }

    func testActivityScopes() {
        MainActor.assumeIsolated {
            let (w, v, area) = setUpTracked([.mouseEnteredAndExited, .activeInKeyWindow])
            defer { w.close() }
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertEqual(v.log, ["entered:a"])
            w.resignKey()
            XCTAssertEqual(v.log, ["entered:a", "exited:a"], "losing key exits an activeInKeyWindow area without the pointer moving")
            moveMouse(w, to: NSPoint(x: 70, y: 70))
            XCTAssertEqual(v.log.count, 2, "and nothing enters while the window is not key")
            w.makeKey()
            XCTAssertEqual(v.log, ["entered:a", "exited:a", "entered:a"], "becoming key enters again at the last location")
            // activeWhenFirstResponder follows the first responder.
            v.removeTrackingArea(area)
            v.log = []
            v.addTrackingArea(NSTrackingArea(rect: area.rect, options: [.mouseEnteredAndExited, .activeWhenFirstResponder], owner: v, userInfo: ["name": "fr"]))
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertEqual(v.log, [], "not first responder yet")
            XCTAssertTrue(w.makeFirstResponder(v))
            XCTAssertEqual(v.log, ["entered:fr"])
            XCTAssertTrue(w.makeFirstResponder(nil))
            XCTAssertEqual(v.log, ["entered:fr", "exited:fr"])
            // activeInActiveApp follows the application.
            v.log = []
            v.trackingAreas.forEach { v.removeTrackingArea($0) }
            v.addTrackingArea(NSTrackingArea(rect: area.rect, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: v, userInfo: ["name": "app"]))
            let wasActive = NSApplication.shared.isActive
            defer { if wasActive { NSApplication.shared.activate(ignoringOtherApps: true) } else { NSApplication.shared.deactivate() } }
            NSApplication.shared.deactivate()
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertEqual(v.log, [])
            NSApplication.shared.activate(ignoringOtherApps: true)
            XCTAssertEqual(v.log, ["entered:app"])
            NSApplication.shared.deactivate()
            XCTAssertEqual(v.log, ["entered:app", "exited:app"])
            // activeAlways ignores all of it.
            v.log = []
            v.trackingAreas.forEach { v.removeTrackingArea($0) }
            v.addTrackingArea(NSTrackingArea(rect: area.rect, options: [.mouseEnteredAndExited, .activeAlways], owner: v, userInfo: ["name": "always"]))
            w.resignKey()
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertEqual(v.log, ["entered:always"])
        }
    }

    func testAssumeInsideStartsInsideAndInVisibleRectFollowsTheVisibleRect() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            w.contentView = content
            let v = TrackedView(frame: NSRect(x: 100, y: 100, width: 100, height: 100))
            content.addSubview(v)
            let assumed = NSTrackingArea(rect: v.bounds, options: [.mouseEnteredAndExited, .activeAlways, .assumeInside], owner: v, userInfo: ["name": "assumed"])
            v.addTrackingArea(assumed)
            XCTAssertTrue(assumed._isInside)
            moveMouse(w, to: NSPoint(x: 10, y: 10))
            XCTAssertEqual(v.log, ["exited:assumed"], "the first event is the exit, as the pointer was assumed inside")
            v.log = []
            v.removeTrackingArea(assumed)
            // inVisibleRect: the area is whatever part of the view shows, so it moves with the view.
            let visible = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: v, userInfo: ["name": "vis"])
            v.addTrackingArea(visible)
            moveMouse(w, to: NSPoint(x: 150, y: 150))
            XCTAssertEqual(v.log, ["entered:vis"])
            v.setFrameOrigin(NSPoint(x: 250, y: 100))
            w.display()
            XCTAssertEqual(v.log, ["entered:vis", "exited:vis"], "the view moved out from under the pointer: the next evaluation exits")
            moveMouse(w, to: NSPoint(x: 300, y: 150))
            XCTAssertEqual(v.log, ["entered:vis", "exited:vis", "entered:vis"])
            // Hidden views do not track.
            v.isHidden = true
            w.display()
            XCTAssertEqual(v.log.last, "exited:vis")
        }
    }

    func testDragsOnlyReachAreasEnabledDuringMouseDrag() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            w.contentView = content
            let plain = TrackedView(frame: NSRect(x: 0, y: 0, width: 100, height: 300))
            let dragging = TrackedView(frame: NSRect(x: 200, y: 0, width: 100, height: 300))
            content.addSubview(plain)
            content.addSubview(dragging)
            plain.addTrackingArea(NSTrackingArea(rect: plain.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: plain, userInfo: ["name": "plain"]))
            dragging.addTrackingArea(NSTrackingArea(rect: dragging.bounds, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: dragging, userInfo: ["name": "drag"]))
            moveMouse(w, to: NSPoint(x: 150, y: 150))
            moveMouse(w, to: NSPoint(x: 150, y: 150), type: .leftMouseDown)
            moveMouse(w, to: NSPoint(x: 50, y: 150), type: .leftMouseDragged)
            moveMouse(w, to: NSPoint(x: 250, y: 150), type: .leftMouseDragged)
            XCTAssertEqual(plain.log, [], "a plain area ignores the drag")
            XCTAssertEqual(dragging.log, ["entered:drag"], "an enabled area enters during the drag")
            moveMouse(w, to: NSPoint(x: 50, y: 150), type: .leftMouseDragged)
            XCTAssertEqual(dragging.log, ["entered:drag", "exited:drag"])
            moveMouse(w, to: NSPoint(x: 50, y: 150), type: .leftMouseUp)
            XCTAssertEqual(plain.log, ["entered:plain"], "the mouse up catches the plain area up with the pointer")
        }
    }

    func testUpdateTrackingAreasRunsAfterGeometryChangesAndPostsTheNotification() {
        MainActor.assumeIsolated {
            final class Rebuilding: NSView {
                var updates = 0
                override func updateTrackingAreas() {
                    updates += 1
                    trackingAreas.forEach { removeTrackingArea($0) }
                    addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
                    super.updateTrackingAreas()
                }
            }
            let w = makeWindow()
            defer { w.close() }
            let v = Rebuilding(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            w.contentView!.addSubview(v)
            var posted = 0
            let o = NotificationCenter.default.addObserver(forName: NSView.didUpdateTrackingAreasNotification, object: v, queue: nil) { _ in posted += 1 }
            defer { NotificationCenter.default.removeObserver(o) }
            moveMouse(w, to: NSPoint(x: 10, y: 10))
            XCTAssertEqual(v.updates, 1, "the window asks the view before its first evaluation")
            XCTAssertEqual(v.trackingAreas.count, 1)
            moveMouse(w, to: NSPoint(x: 20, y: 10))
            XCTAssertEqual(v.updates, 1, "a move alone does not ask again")
            v.setFrameSize(NSSize(width: 200, height: 200))
            moveMouse(w, to: NSPoint(x: 30, y: 10))
            XCTAssertEqual(v.updates, 2, "a resize does")
            XCTAssertEqual(v.trackingAreas[0].rect.width, 200)
            XCTAssertEqual(posted, 2)
        }
    }

    func testCursorOwnerAndNonResponderOwnerFallBackToTheView() {
        MainActor.assumeIsolated {
            let (w, v, area) = setUpTracked([.mouseEnteredAndExited, .activeAlways])
            defer { w.close() }
            v.removeTrackingArea(area)
            // An NSCursor owner gets its own mouseEntered/mouseExited and sets itself.
            let cursor = NSCursor.pointingHand
            cursor.setOnMouseEntered(true)
            v.addTrackingArea(NSTrackingArea(rect: area.rect, options: [.mouseEnteredAndExited, .activeAlways], owner: cursor))
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertTrue(NSCursor.current === cursor)
            XCTAssertEqual(v.log, [], "the view is not the owner")
            v.trackingAreas.forEach { v.removeTrackingArea($0) }
            // An owner that is no responder: the view takes the messages.
            final class Plain {}
            let owner = Plain()
            v.addTrackingArea(NSTrackingArea(rect: area.rect, options: [.mouseEnteredAndExited, .activeAlways], owner: owner, userInfo: ["name": "plain"]))
            moveMouse(w, to: NSPoint(x: 10, y: 10))
            moveMouse(w, to: NSPoint(x: 60, y: 60))
            XCTAssertEqual(v.log, ["entered:plain"])
            withExtendedLifetime(owner) {}
        }
    }

    func testSwiftUIHoverModifiersUseTrackingAreas() {
        MainActor.assumeIsolated {
            final class Model { var hovering: [Bool] = []; var phases: [HoverPhase] = [] }
            let model = Model()
            struct Content: View {
                let model: Model
                var body: some View {
                    VStack {
                        Color.red.frame(width: 100, height: 50).onHover { model.hovering.append($0) }
                        Color.blue.frame(width: 100, height: 50).onContinuousHover { model.phases.append($0) }
                    }
                }
            }
            let w = makeWindow()
            defer { w.close() }
            let host = NSHostingView(rootView: Content(model: model))
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
            w.contentView = host
            w.display()
            // Find the two decorated containers by their tracking areas.
            @MainActor func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { views($0) } }
            let tracked = views(host).filter { !$0.trackingAreas.isEmpty }
            XCTAssertEqual(tracked.count, 2, "both hover modifiers installed a tracking area")
            let hoverView = tracked[0], continuous = tracked[1]
            let p1 = hoverView.convert(NSPoint(x: 50, y: 25), to: nil)
            let p2 = continuous.convert(NSPoint(x: 50, y: 25), to: nil)
            moveMouse(w, to: p1)
            XCTAssertEqual(model.hovering, [true])
            moveMouse(w, to: p2)
            XCTAssertEqual(model.hovering, [true, false])
            XCTAssertEqual(model.phases.count, 1)
            moveMouse(w, to: NSPoint(x: p2.x + 10, y: p2.y))
            if case .active(let p) = model.phases.last! { XCTAssertEqual(p.x, 60, accuracy: 0.5) } else { XCTFail("expected an active phase") }
            moveMouse(w, to: NSPoint(x: 390, y: 290))
            XCTAssertEqual(model.phases.last, .ended)
        }
    }
}

// MARK: - Title bar accessories

@MainActor
private func accessory(_ attribute: NSLayoutConstraint.Attribute, size: NSSize = NSSize(width: 80, height: 22), hidden: Bool = false) -> NSTitlebarAccessoryViewController {
    let vc = NSTitlebarAccessoryViewController()
    vc.view = NSView(frame: NSRect(origin: .zero, size: size))
    vc.layoutAttribute = attribute
    vc.isHidden = hidden
    return vc
}

final class TitlebarAccessoryTests: XCTestCase, @unchecked Sendable {
    func testDefaultsAndBookkeeping() {
        MainActor.assumeIsolated {
            let vc = NSTitlebarAccessoryViewController()
            XCTAssertEqual(vc.layoutAttribute, .bottom)
            XCTAssertFalse(vc.isHidden)
            XCTAssertEqual(vc.fullScreenMinHeight, 0)
            if #available(macOS 11.0, *) { XCTAssertTrue(vc.automaticallyAdjustsSize) }
            vc.fullScreenMinHeight = 10
            XCTAssertEqual(vc.fullScreenMinHeight, 10)
            let w = makeWindow()
            defer { w.close() }
            let a = accessory(.leading), b = accessory(.trailing), c = accessory(.bottom)
            w.addTitlebarAccessoryViewController(a)
            w.addTitlebarAccessoryViewController(c)
            w.insertTitlebarAccessoryViewController(b, at: 1)
            XCTAssertEqual(w.titlebarAccessoryViewControllers.map { $0 === a ? "a" : $0 === b ? "b" : "c" }, ["a", "b", "c"])
            XCTAssertTrue(a.view.window === w)
            w.removeTitlebarAccessoryViewController(at: 1)
            XCTAssertEqual(w.titlebarAccessoryViewControllers.count, 2)
            XCTAssertNil(b.view.window)
            c.removeFromParent()
            XCTAssertEqual(w.titlebarAccessoryViewControllers.count, 1)
            w.titlebarAccessoryViewControllers = []
            XCTAssertTrue(w.titlebarAccessoryViewControllers.isEmpty)
            XCTAssertNil(a.view.window)
        }
    }

    func testStripUnderAServerSideTitleBarGrowsTheFrameLikeTheToolbarBand() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let frameBefore = w.frame
            let contentBefore = w.contentView!.frame.size
            let lead = accessory(.leading, size: NSSize(width: 60, height: 24))
            let trail = accessory(.trailing, size: NSSize(width: 90, height: 20))
            w.addTitlebarAccessoryViewController(lead)
            w.addTitlebarAccessoryViewController(trail)
            XCTAssertEqual(w._accessoryBandHeight, 24, "the strip is as tall as the tallest side accessory")
            XCTAssertEqual(w.frame.height, frameBefore.height + 24, "the frame grows by the strip")
            XCTAssertEqual(w.frame.maxY, frameBefore.maxY, "with the top edge fixed")
            XCTAssertEqual(w.contentView!.frame.size, contentBefore, "the content keeps its size")
            XCTAssertEqual(w.contentLayoutRect, w.contentView!.bounds)
            let pc = w._platformContentSize
            XCTAssertEqual(lead.view.frame.minX, 8, "no package buttons under a system title bar: leading starts at the edge")
            XCTAssertEqual(lead.view.frame.maxY, pc.height)
            XCTAssertEqual(trail.view.frame.maxX, pc.width - 8)
            XCTAssertEqual(trail.view.frame.midY, pc.height - 12, accuracy: 0.5, "centred in the strip")
            // A bottom accessory stacks under the strip (and under the toolbar when there is one).
            let bottom = accessory(.bottom, size: NSSize(width: 10, height: 30))
            w.addTitlebarAccessoryViewController(bottom)
            XCTAssertEqual(w._accessoryBandHeight, 54)
            XCTAssertEqual(w.frame.height, frameBefore.height + 54)
            XCTAssertEqual(bottom.view.frame, NSRect(x: 0, y: contentBefore.height, width: pc.width, height: 30), "full width, right above the content")
            XCTAssertEqual(lead.view.frame.minY, contentBefore.height + 30, "the strip is above it")
            // Hiding takes the space away; a second bottom accessory stacks.
            lead.isHidden = true
            XCTAssertEqual(w._accessoryBandHeight, 20 + 30)
            let bottom2 = accessory(.bottom, size: NSSize(width: 10, height: 16))
            w.addTitlebarAccessoryViewController(bottom2)
            XCTAssertEqual(bottom2.view.frame.minY, contentBefore.height)
            XCTAssertEqual(bottom.view.frame.minY, contentBefore.height + 16)
            // Removing everything restores the frame.
            w.titlebarAccessoryViewControllers = []
            XCTAssertEqual(w.frame, frameBefore)
            XCTAssertEqual(w.contentView!.frame.size, contentBefore)
            XCTAssertEqual(w.frameRect(forContentRect: w.contentRect(forFrameRect: w.frame)), w.frame)
        }
    }

    func testAccessoriesSitBelowTheToolbarBandInTheRightOrder() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let contentHeight = w.contentView!.frame.height
            let tb = NSToolbar(identifier: "test.accessory.toolbar")
            w.toolbar = tb
            let toolbarBand = w._toolbarBandHeight
            let side = accessory(.leading, size: NSSize(width: 60, height: 24))
            let bottom = accessory(.bottom, size: NSSize(width: 10, height: 30))
            w.addTitlebarAccessoryViewController(side)
            w.addTitlebarAccessoryViewController(bottom)
            let pc = w._platformContentSize
            XCTAssertEqual(pc.height, contentHeight + toolbarBand + 24 + 30)
            XCTAssertEqual(side.view.frame.maxY, pc.height, "the side strip is at the very top, under the system title bar")
            XCTAssertEqual(tb._view!.frame.maxY, pc.height - 24, "the toolbar under the strip")
            XCTAssertEqual(tb._view!.frame.minY, contentHeight + 30)
            XCTAssertEqual(bottom.view.frame.maxY, contentHeight + 30, "the bottom accessory under the toolbar")
            XCTAssertEqual(bottom.view.frame.minY, contentHeight)
            XCTAssertEqual(w.contentView!.frame.height, contentHeight)
        }
    }

    func testAccessoriesShareTheBandWithTheButtonsWhenTheContentCoversTheTitleBar() {
        MainActor.assumeIsolated {
            let w = makeWindow([.titled, .closable, .resizable, .fullSizeContentView])
            defer { w.close() }
            let frameBefore = w.frame
            let ch = w.contentView!.bounds.height
            let lead = accessory(.leading, size: NSSize(width: 60, height: 20))
            let trail = accessory(.trailing, size: NSSize(width: 40, height: 20))
            let bottom = accessory(.bottom, size: NSSize(width: 10, height: 26))
            w.addTitlebarAccessoryViewController(lead)
            w.addTitlebarAccessoryViewController(trail)
            w.addTitlebarAccessoryViewController(bottom)
            XCTAssertEqual(w.frame, frameBefore, "nothing comes out of the frame: the accessories overlay the content")
            XCTAssertEqual(lead.view.frame.minX, _NSWindowButtonsView.width + 4, "leading starts after the standard buttons")
            XCTAssertEqual(lead.view.frame.midY, ch - NSWindow._titleBarBandHeight / 2, accuracy: 0.5, "in the title band")
            XCTAssertEqual(trail.view.frame.maxX, w.contentView!.bounds.width - 8)
            XCTAssertEqual(bottom.view.frame.maxY, ch - NSWindow._titleBarBandHeight, "the bottom accessory under the title band")
            XCTAssertEqual(w.contentLayoutRect.height, ch - NSWindow._titleBarBandHeight - 26, "contentLayoutRect excludes the band and the accessory")
            // With a unified toolbar the bottom accessory goes under the toolbar band.
            let tb = NSToolbar(identifier: "test.accessory.unified")
            w.toolbar = tb
            let m = w._toolbarMetrics!
            XCTAssertEqual(bottom.view.frame.maxY, ch - m.height)
            XCTAssertEqual(w.contentLayoutRect.height, ch - m.height - 26)
            // Hit testing: the accessory's view takes the click, the gaps in the band drag the window.
            let inLead = NSPoint(x: lead.view.frame.midX, y: lead.view.frame.midY)
            XCTAssertTrue(w._hitTestForTests(inLead) === lead.view, "the accessory is above the unified toolbar")
            w.display()
            let firstItem = tb._view!.subviews.compactMap { $0 as? _NSToolbarItemButton }.min { $0.frame.minX < $1.frame.minX }
            if let firstItem { XCTAssertGreaterThanOrEqual(firstItem.frame.minX, lead.view.frame.maxX, "unified items start after the leading accessory") }
            XCTAssertEqual(w.platformWindowHitTest(inLead), .caption, "a plain view in the band drags, as mouseDownCanMoveWindow says")
            let button = NSButton(title: "Go", target: nil, action: nil)
            button.frame = NSRect(x: 0, y: 0, width: 50, height: 20)
            lead.view = button
            w._accessoryGeometryDidChange()
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)), .client, "a control in the band takes the mouse")
        }
    }

    func testClientSideTitleBandHoldsTheSideAccessoriesBesideTheButtons() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            defer { w.close() }
            let host = w._platformWindow as! HostWindow
            host.clientSideTitleBar = true
            w.title = "Decorated"
            w.platformWindowDidChangeFrame(w.frame)
            XCTAssertEqual(w.frame.height, 328)
            let lead = accessory(.leading, size: NSSize(width: 60, height: 20))
            let bottom = accessory(.bottom, size: NSSize(width: 10, height: 24))
            w.addTitlebarAccessoryViewController(lead)
            XCTAssertEqual(w.frame.height, 328, "the band the package draws already has room: nothing grows")
            XCTAssertEqual(lead.view.frame.minX, _NSWindowButtonsView.width + 4, "after the buttons")
            XCTAssertEqual(lead.view.frame.midY, 314, accuracy: 0.5, "in the band above the content")
            w.addTitlebarAccessoryViewController(bottom)
            XCTAssertEqual(w.frame.height, 352, "a bottom accessory still comes out of the frame")
            XCTAssertEqual(bottom.view.frame, NSRect(x: 0, y: 300, width: 400, height: 24))
            XCTAssertEqual(lead.view.frame.midY, 338, accuracy: 0.5)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 200, y: 338)), .caption)
            // The band drawing path paints the accessory: a red accessory view shows in the band.
            final class Red: NSView { override func draw(_ r: NSRect) { NSColor.red.setFill(); NSBezierPath.fill(bounds) } }
            lead.view = Red(frame: NSRect(x: 0, y: 0, width: 60, height: 20))
            w._accessoryGeometryDidChange()
            w.appearance = NSAppearance(named: .aqua)
            let ctx = CGContext(data: nil, width: 400, height: 352, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            w.platformWindowDrawTitleBar(into: ctx, dirtyRect: NSRect(x: 0, y: 324, width: 400, height: 28))
            let image = ctx.makeImage()!
            let data = _pixels(image)
            let x = Int(lead.view.frame.midX), y = image.height - 1 - Int(lead.view.frame.midY)
            let i = y * image.bytesPerRow + x * 4
            XCTAssertTrue(Int(data[i + 2]) > 200 && Int(data[i + 1]) < 60, "red accessory in the band \(data[i]) \(data[i + 1]) \(data[i + 2])")
        }
    }

    func testRightToLeftMirrorsLeadingAndTrailingButNotLeftAndRight() {
        MainActor.assumeIsolated {
            let w = makeWindow([.titled, .closable, .resizable, .fullSizeContentView])
            defer { w.close() }
            w.contentView!.userInterfaceLayoutDirection = .rightToLeft
            XCTAssertEqual(w.windowTitlebarLayoutDirection, .rightToLeft)
            let lead = accessory(.leading, size: NSSize(width: 60, height: 20))
            let trail = accessory(.trailing, size: NSSize(width: 40, height: 20))
            let left = accessory(.left, size: NSSize(width: 30, height: 20))
            let right = accessory(.right, size: NSSize(width: 30, height: 20))
            for a in [lead, trail, left, right] { w.addTitlebarAccessoryViewController(a) }
            let width = w.contentView!.bounds.width
            XCTAssertEqual(lead.view.frame.maxX, width - 8, "leading is at the right edge")
            XCTAssertEqual(trail.view.frame.minX, _NSWindowButtonsView.width + 4, "trailing after the buttons, which stay left")
            XCTAssertEqual(left.view.frame.minX, trail.view.frame.maxX + 8, "left stacks after trailing on the left")
            XCTAssertEqual(right.view.frame.maxX, lead.view.frame.minX - 8, "right stacks before leading on the right")
            w.contentView!.userInterfaceLayoutDirection = .leftToRight
            w._accessoryGeometryDidChange()
            XCTAssertEqual(lead.view.frame.minX, _NSWindowButtonsView.width + 4)
            XCTAssertEqual(trail.view.frame.maxX, width - 8)
        }
    }

    func testAccessoryViewResizeAndFittingSizeAreFollowed() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let frameBefore = w.frame
            let bottom = accessory(.bottom, size: NSSize(width: 10, height: 30))
            w.addTitlebarAccessoryViewController(bottom)
            XCTAssertEqual(w.frame.height, frameBefore.height + 30)
            bottom.view.setFrameSize(NSSize(width: 10, height: 44))
            XCTAssertEqual(w.frame.height, frameBefore.height + 44, "the window follows the accessory view's frame")
            // A view with constraints reports its fitting size when automaticallyAdjustsSize.
            if #available(macOS 11.0, *) {
                final class Fitting: NSView { override var fittingSize: NSSize { NSSize(width: 10, height: 36) } }
                let fitted = NSTitlebarAccessoryViewController()
                fitted.view = Fitting(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
                w.addTitlebarAccessoryViewController(fitted)
                XCTAssertEqual(w.frame.height, frameBefore.height + 44 + 36)
                fitted.automaticallyAdjustsSize = false
                XCTAssertEqual(w.frame.height, frameBefore.height + 44 + 36, "the frame the window gave the view stays")
                fitted.view.setFrameSize(NSSize(width: 10, height: 10))
                XCTAssertEqual(w.frame.height, frameBefore.height + 44 + 10, "without adjusting, the view's own frame rules")
            }
        }
    }
}
