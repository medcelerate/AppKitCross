// Attached sheets (ADR-0019): attachment to the parent's platform window, position under
// the title band and the delegate hook, following the parent, input blocking and key
// forwarding, queueing and critical sheets, end-sheet return codes, Escape, the
// application-modal loop over a sheet, NSAlert sheets and the slide on the frame clock.

import XCTest
@testable import AppKit
import QuartzCore

@MainActor
private final class EventRecorder: NSView {
    var mouseDowns = 0
    var keys: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { mouseDowns += 1 }
    override func keyDown(with event: NSEvent) { keys.append(event.charactersIgnoringModifiers ?? "") }
}

/// A notification count (a captured `var` in a notification closure is a Sendable error on Linux).
private final class Counter: @unchecked Sendable { var n = 0 }

@MainActor
private func keyDown(_ chars: String, in window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
}

@MainActor
private func mouseDown(at point: NSPoint, in window: NSWindow) -> NSEvent {
    NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                       eventNumber: 1, clickCount: 1, pressure: 1)!
}

final class SheetTests: XCTestCase, @unchecked Sendable {
    private var savedDuration: TimeInterval = 0.25

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            savedDuration = NSWindow._sheetAnimationDuration
            NSWindow._sheetAnimationDuration = 0        // the slide has its own test
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { NSWindow._sheetAnimationDuration = savedDuration }
        super.tearDown()
    }

    @MainActor private func parentWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Parent"
        w.makeKeyAndOrderFront(nil)
        return w
    }

    @MainActor private func sheetWindow(width: CGFloat = 200, height: CGFloat = 100) -> NSWindow {
        let s = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        s.title = "Sheet"
        return s
    }

    @MainActor private func hostWindow(_ w: NSWindow) -> HostWindow { w._platformWindow as! HostWindow }

    func testBeginSheetAttachesUnderTheTitleBarAndMakesItKey() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let s = sheetWindow()
            XCTAssertEqual(s.frame.height, 128, "a titled window has the host's 28pt title bar")
            let began = Counter()
            let token = NotificationCenter.default.addObserver(forName: NSWindow.willBeginSheetNotification, object: w, queue: nil) { _ in began.n += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            w.beginSheet(s)
            XCTAssertEqual(began.n, 1)
            XCTAssertTrue(s.isSheet)
            XCTAssertTrue(s.sheetParent === w)
            XCTAssertTrue(w.attachedSheet === s)
            XCTAssertEqual(w.sheets.count, 1)
            XCTAssertTrue(hostWindow(s).sheetParent === hostWindow(w), "attached to the parent's platform window")
            XCTAssertTrue(s.isVisible)
            XCTAssertTrue(s.isKeyWindow)
            XCTAssertTrue(NSApplication.shared.keyWindow === s)
            XCTAssertFalse(w.isKeyWindow)
            // No title bar of its own: the frame is the content, centred on the top of the
            // parent's content (y 100 + 300 = 400, x 100 + (400 - 200) / 2).
            XCTAssertEqual(s.frame, NSRect(x: 200, y: 300, width: 200, height: 100))
            XCTAssertEqual(s.contentView!.frame.size, NSSize(width: 200, height: 100))
            XCTAssertEqual(s.contentView!.frame.origin, .zero)
            w.endSheet(s)
            XCTAssertFalse(s.isVisible)
            XCTAssertNil(w.attachedSheet)
            XCTAssertNil(s.sheetParent)
            XCTAssertNil(hostWindow(s).sheetParent)
            XCTAssertEqual(s.frame.height, 128, "detached: the title bar is back")
            XCTAssertTrue(w.isKeyWindow, "the parent takes the keyboard back")
            s.close(); w.close()
        }
    }

    func testDelegateMovesTheAttachmentPoint() {
        MainActor.assumeIsolated {
            final class Delegate: NSObject, NSWindowDelegate {
                var asked: NSRect?
                func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
                    asked = rect
                    return NSRect(x: 10, y: rect.minY - 40, width: rect.width, height: 0)
                }
            }
            let w = parentWindow()
            let d = Delegate()
            w.delegate = d
            let s = sheetWindow()
            w.beginSheet(s)
            XCTAssertEqual(d.asked, NSRect(x: 100, y: 300, width: 200, height: 0), "window coordinates: the attachment point and the sheet's width")
            XCTAssertEqual(s.frame, NSRect(x: 110, y: 260, width: 200, height: 100))
            w.endSheet(s)
            s.close(); w.close()
        }
    }

    func testSheetFollowsTheParent() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let s = sheetWindow()
            w.beginSheet(s)
            w.setFrameOrigin(NSPoint(x: 300, y: 50))
            XCTAssertEqual(s.frame.origin, NSPoint(x: 400, y: 250))
            w.setFrame(NSRect(x: 300, y: 50, width: 600, height: 400), display: false)
            XCTAssertEqual(s.frame.origin, NSPoint(x: 500, y: 322), "re-centred under the taller window's title bar")
            w.endSheet(s)
            s.close(); w.close()
        }
    }

    func testParentContentIsBlockedAndKeysReachTheSheet() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let parentView = EventRecorder(frame: w.contentView!.bounds)
            w.contentView!.addSubview(parentView)
            _ = w.makeFirstResponder(parentView)
            let s = sheetWindow()
            let sheetView = EventRecorder(frame: s.contentView!.bounds)
            s.contentView!.addSubview(sheetView)
            let backend = Platform.backend as! HostBackend
            let beeps = backend.beepCount
            w.beginSheet(s)
            _ = s.makeFirstResponder(sheetView)
            // A click on the parent's content goes nowhere; a key typed while the window
            // system still routes to the parent (Wayland) reaches the sheet.
            hostWindow(w).inject(mouseDown(at: NSPoint(x: 50, y: 50), in: w))
            XCTAssertEqual(parentView.mouseDowns, 0)
            hostWindow(w).inject(keyDown("k", in: w))
            XCTAssertEqual(parentView.keys, [])
            XCTAssertEqual(sheetView.keys, ["k"])
            hostWindow(s).inject(mouseDown(at: NSPoint(x: 50, y: 50), in: s))
            XCTAssertEqual(sheetView.mouseDowns, 1)
            // The parent's close button and performClose refuse while the sheet is up.
            XCTAssertFalse(w.platformWindowShouldClose())
            w.performClose(nil)
            XCTAssertTrue(w.isVisible)
            XCTAssertEqual(backend.beepCount, beeps + 2)
            // Activating the parent (its title bar, the taskbar) hands the keyboard to the sheet.
            s.resignKey()
            w.platformWindowDidBecomeKey()
            XCTAssertTrue(s.isKeyWindow)
            XCTAssertFalse(w.isKeyWindow)
            w.endSheet(s)
            hostWindow(w).inject(mouseDown(at: NSPoint(x: 50, y: 50), in: w))
            XCTAssertEqual(parentView.mouseDowns, 1, "unblocked once the sheet ended")
            s.close(); w.close()
        }
    }

    func testSheetsQueueAndReportTheirReturnCodes() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let first = sheetWindow(), second = sheetWindow()
            var codes: [String: NSApplication.ModalResponse] = [:]
            let ended = Counter()
            let token = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: w, queue: nil) { _ in ended.n += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            w.beginSheet(first) { codes["first"] = $0 }
            w.beginSheet(second) { codes["second"] = $0 }
            XCTAssertEqual(w.sheets.count, 2)
            XCTAssertTrue(w.attachedSheet === first)
            XCTAssertTrue(first.isVisible)
            XCTAssertFalse(second.isVisible, "the second sheet waits for the first to end")
            XCTAssertTrue(second.isSheet)
            w.endSheet(first, returnCode: .OK)
            XCTAssertEqual(codes["first"], .OK)
            XCTAssertEqual(ended.n, 1)
            XCTAssertTrue(w.attachedSheet === second, "the queued sheet comes up")
            XCTAssertTrue(second.isVisible)
            XCTAssertTrue(second.isKeyWindow)
            XCTAssertEqual(second.frame, NSRect(x: 200, y: 300, width: 200, height: 100))
            w.endSheet(second, returnCode: .cancel)
            XCTAssertEqual(codes["second"], .cancel)
            XCTAssertEqual(ended.n, 2)
            XCTAssertTrue(w.sheets.isEmpty)
            XCTAssertTrue(w.isKeyWindow)
            // Ending a sheet that is still queued only reports its code.
            let third = sheetWindow(), fourth = sheetWindow()
            w.beginSheet(third)
            w.beginSheet(fourth) { codes["fourth"] = $0 }
            w.endSheet(fourth, returnCode: .abort)
            XCTAssertEqual(codes["fourth"], .abort)
            XCTAssertTrue(w.attachedSheet === third)
            w.endSheet(third)
            first.close(); second.close(); third.close(); fourth.close(); w.close()
        }
    }

    func testCriticalSheetJumpsTheQueue() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let normal = sheetWindow(), critical = sheetWindow()
            var code: NSApplication.ModalResponse?
            w.beginSheet(normal)
            w._beginCriticalSheet(critical) { code = $0 }
            XCTAssertTrue(w.attachedSheet === critical, "presented in front of the sheet already up")
            XCTAssertTrue(critical.isVisible && normal.isVisible)
            XCTAssertTrue(critical.isKeyWindow)
            XCTAssertEqual(w.sheets.map { $0 === critical }, [true, false])
            w.endSheet(critical, returnCode: .continue)
            XCTAssertEqual(code, .continue)
            XCTAssertTrue(w.attachedSheet === normal)
            XCTAssertTrue(normal.isKeyWindow)
            w.endSheet(normal)
            normal.close(); critical.close(); w.close()
        }
    }

    func testEscapeCancelsASheetThatOptedIn() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let s = sheetWindow()
            var code: NSApplication.ModalResponse?
            w.beginSheet(s) { code = $0 }
            hostWindow(s).inject(keyDown("\u{1B}", in: s))
            XCTAssertNil(code, "a plain sheet keeps Escape for its responders")
            s._cancelsSheetOnEscape = true
            hostWindow(s).inject(keyDown("\u{1B}", in: s))
            XCTAssertEqual(code, .cancel)
            XCTAssertTrue(w.sheets.isEmpty)
            XCTAssertFalse(s.isVisible)
            // A Cancel button's key equivalent wins over the opt-in.
            let t = sheetWindow()
            var pressed = false
            let cancel = NSButton(title: "Cancel", target: nil, action: Selector(("cancelPressed:")))
            cancel.keyEquivalent = "\u{1B}"
            cancel.target = cancel
            cancel.setActionHandler(for: Selector(("cancelPressed:"))) { _ in pressed = true }
            t.contentView!.addSubview(cancel)
            t._cancelsSheetOnEscape = true
            w.beginSheet(t)
            hostWindow(t).inject(keyDown("\u{1B}", in: t))
            XCTAssertTrue(pressed)
            XCTAssertTrue(w.attachedSheet === t, "the button handled it; the sheet decides what to do")
            w.endSheet(t)
            s.close(); t.close(); w.close()
        }
    }

    func testClosingEndsSheetsWithCancel() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let s = sheetWindow()
            var code: NSApplication.ModalResponse?
            w.beginSheet(s) { code = $0 }
            s.close()
            XCTAssertEqual(code, .cancel, "a sheet closed by other means ends its session")
            XCTAssertTrue(w.sheets.isEmpty)
            XCTAssertNil(s.sheetParent)
            // A window closing with sheets up ends them.
            let t = sheetWindow()
            code = nil
            w.beginSheet(t) { code = $0 }
            w.close()
            XCTAssertEqual(code, .cancel)
            XCTAssertFalse(t.isVisible)
            XCTAssertNil(t.sheetParent)
            t.close()
        }
    }

    func testRunModalOverASheet() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let s = sheetWindow()
            let app = NSApplication.shared
            let backend = Platform.backend as! HostBackend
            w.beginSheet(s)
            backend.post { app.stopModal(withCode: .OK) }
            let response = app.runModal(for: s)
            XCTAssertEqual(response, .OK)
            XCTAssertTrue(w.attachedSheet === s, "runModal does not end the sheet; the caller does")
            w.endSheet(s)
            XCTAssertNil(w.attachedSheet)
            // The deprecated application-level endSheet forwards to the parent.
            var code: NSApplication.ModalResponse?
            w.beginSheet(s) { code = $0 }
            app.endSheet(s, returnCode: NSApplication.ModalResponse.OK.rawValue)
            XCTAssertEqual(code, .OK)
            s.close(); w.close()
        }
    }

    func testAlertSheetEndsFromItsButtons() {
        MainActor.assumeIsolated {
            let w = parentWindow()
            let alert = NSAlert()
            alert.messageText = "Replace?"
            _ = alert.addButton(withTitle: "Replace")
            _ = alert.addButton(withTitle: "Cancel")
            var code: NSApplication.ModalResponse?
            alert.beginSheetModal(for: w) { code = $0 }
            let panel = w.attachedSheet
            XCTAssertNotNil(panel)
            XCTAssertTrue(panel === alert.window)
            XCTAssertTrue(panel!.isKeyWindow)
            // Escape is the Cancel button's key equivalent.
            hostWindow(panel!).inject(keyDown("\u{1B}", in: panel!))
            XCTAssertEqual(code, .alertSecondButtonReturn)
            XCTAssertTrue(w.sheets.isEmpty)
            code = nil
            alert.beginSheetModal(for: w) { code = $0 }
            alert.buttons[0].performClick(nil)
            XCTAssertEqual(code, .alertFirstButtonReturn)
            XCTAssertTrue(w.sheets.isEmpty)
            XCTAssertTrue(w.isKeyWindow)
            w.close()
        }
    }

    func testSheetSlidesInAndOutOnTheFrameClock() {
        MainActor.assumeIsolated {
            NSWindow._sheetAnimationDuration = 0.25
            var clock: CFTimeInterval = 10
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let w = parentWindow()
            let s = sheetWindow()
            w.beginSheet(s)
            XCTAssertTrue(s.isVisible)
            XCTAssertEqual(s.frame, NSRect(x: 200, y: 399, width: 200, height: 1), "starts rolled up at the attachment line")
            XCTAssertEqual(s.contentView!.frame.size, NSSize(width: 200, height: 100), "the content keeps its size")
            XCTAssertEqual(s.contentView!.frame.origin.y, -99, "pinned to the top")
            clock = 10.125
            CARuntime.tick()
            let mid = s.frame
            XCTAssertEqual(mid.maxY, 400)
            XCTAssertTrue(mid.height > 50 && mid.height < 100, "ease-out: past half way at half time (\(mid.height))")
            XCTAssertEqual(s.contentView!.frame.origin.y, mid.height - 100)
            clock = 10.3
            CARuntime.tick()
            XCTAssertEqual(s.frame, NSRect(x: 200, y: 300, width: 200, height: 100))
            XCTAssertEqual(s.contentView!.frame.origin, .zero)
            w.endSheet(s)
            XCTAssertTrue(s.isVisible, "rolls up before it goes")
            XCTAssertNil(w.attachedSheet)
            clock = 10.4
            CARuntime.tick()
            XCTAssertTrue(s.frame.height < 100 && s.frame.maxY == 400)
            clock = 10.6
            CARuntime.tick()
            XCTAssertFalse(s.isVisible)
            XCTAssertEqual(s.frame.height, 128, "detached again")
            // Ending a sheet mid-slide completes the slide first.
            w.beginSheet(s)
            clock = 10.7
            CARuntime.tick()
            w.endSheet(s)
            clock = 11
            CARuntime.tick()
            XCTAssertFalse(s.isVisible)
            s.close(); w.close()
        }
    }
}
