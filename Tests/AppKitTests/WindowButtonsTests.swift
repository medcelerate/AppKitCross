// The standard window buttons that content-covered title bars show, and the
// miniaturize/zoom entry points behind them.

import XCTest
@testable import AppKit

final class WindowButtonsTests: XCTestCase, @unchecked Sendable {
    @MainActor private func window(_ mask: NSWindow.StyleMask) -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: mask, backing: .buffered, defer: false)
    }

    func testButtonsAppearOnlyWhenContentCoversTheTitleBar() {
        MainActor.assumeIsolated {
            let plain = window([.titled, .closable])
            XCTAssertFalse(plain._showsWindowButtons)
            XCTAssertNotNil(plain.standardWindowButton(.closeButton), "the buttons exist for every titled window, as on macOS")
            XCTAssertEqual(plain.platformWindowHitTest(NSPoint(x: 18, y: 186)), .client, "no overlay on a plain window")
            plain.close()

            let w = window([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            XCTAssertTrue(w._showsWindowButtons)
            let close = w.standardWindowButton(.closeButton)!
            let mini = w.standardWindowButton(.miniaturizeButton)!
            let zoom = w.standardWindowButton(.zoomButton)!
            XCTAssertNil(w.standardWindowButton(.toolbarButton))
            // Three 12pt circles 20pt apart, centred in the 28pt band at the top-left.
            let row = close.superview!
            XCTAssertEqual(row.frame.maxY, 200)
            XCTAssertEqual(close.frame.origin.x, 12)
            XCTAssertEqual(mini.frame.origin.x, 32)
            XCTAssertEqual(zoom.frame.origin.x, 52)
            XCTAssertEqual(close.frame.width, 12)
            XCTAssertTrue(close.isEnabled && mini.isEnabled && zoom.isEnabled)
            // The buttons sit above the content and never drag the window; the gaps do.
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 18, y: 186)), .client)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 38, y: 186)), .client)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 4, y: 186)), .caption)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 200, y: 186)), .caption)
            w.close()
        }
    }

    func testStyleMaskDisablesButtonsAndTheRowFollowsResizes() {
        MainActor.assumeIsolated {
            let w = window([.titled, .closable, .fullSizeContentView])
            XCTAssertTrue(w.standardWindowButton(.closeButton)!.isEnabled)
            XCTAssertFalse(w.standardWindowButton(.miniaturizeButton)!.isEnabled)
            XCTAssertFalse(w.standardWindowButton(.zoomButton)!.isEnabled)
            w.setFrame(NSRect(x: 0, y: 0, width: 400, height: 300), display: false)
            let row = w.standardWindowButton(.closeButton)!.superview!
            XCTAssertEqual(row.frame.maxY, w.contentRect(forFrameRect: w.frame).height)
            XCTAssertEqual(row.frame.origin.x, 0)
            w.close()
        }
    }

    func testClickingCloseClosesAndTheOthersReachTheWindow() {
        MainActor.assumeIsolated {
            final class Delegate: NSObject, NSWindowDelegate {
                var minis = 0, deminis = 0, zoomAsked = 0
                func windowDidMiniaturize(_ n: Notification) { minis += 1 }
                func windowDidDeminiaturize(_ n: Notification) { deminis += 1 }
                func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { zoomAsked += 1; return true }
            }
            let w = window([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            let delegate = Delegate()
            w.delegate = delegate
            w.makeKeyAndOrderFront(nil)
            let mini = w.standardWindowButton(.miniaturizeButton)!
            XCTAssertEqual(mini.target as? NSWindow, w)
            mini._fireAction()
            XCTAssertEqual(delegate.minis, 1)
            w.deminiaturize(nil)
            XCTAssertEqual(delegate.deminis, 1)
            w.standardWindowButton(.zoomButton)!._fireAction()
            XCTAssertEqual(delegate.zoomAsked, 1)
            XCTAssertFalse(w.isMiniaturized, "the test backend has no native minimise")
            // A press and release on the close circle closes the window.
            let center = NSPoint(x: 18, y: 186)
            XCTAssertTrue(w.isVisible)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!)
            XCTAssertFalse(w.isVisible)
        }
    }

    func testClassFactoryHonoursTheStyleMask() {
        MainActor.assumeIsolated {
            XCTAssertTrue(NSWindow.standardWindowButton(.closeButton, for: [.titled, .closable])!.isEnabled)
            XCTAssertFalse(NSWindow.standardWindowButton(.zoomButton, for: [.titled, .closable])!.isEnabled)
            XCTAssertNil(NSWindow.standardWindowButton(.documentIconButton, for: [.titled]))
        }
    }
}
