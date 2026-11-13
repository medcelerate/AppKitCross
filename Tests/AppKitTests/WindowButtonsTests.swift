// The standard window buttons that content-covered title bars show, and the
// miniaturize/zoom entry points behind them.

import XCTest
@testable import AppKit

final class WindowButtonsTests: XCTestCase, @unchecked Sendable {
    @MainActor private func window(_ mask: NSWindow.StyleMask) -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: mask, backing: .buffered, defer: false)
    }

    func testButtonsAppearOnlyWhenContentCoversTheTitleBar() {
        withTrafficLights {
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
            // The buttons sit above the content and never drag the window (the backend hears
            // which button it is: Windows answers HTCLOSE and friends); the gaps do.
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 18, y: 186)), .closeButton)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 38, y: 186)), .miniaturizeButton)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 4, y: 186)), .caption)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 200, y: 186)), .caption)
            w.close()
        }
    }

    func testStyleMaskDisablesButtonsAndTheRowFollowsResizes() {
        withTrafficLights {
            let w = window([.titled, .closable, .fullSizeContentView])
            XCTAssertTrue(w.standardWindowButton(.closeButton)!.isEnabled)
            XCTAssertFalse(w.standardWindowButton(.miniaturizeButton)!.isEnabled)
            XCTAssertFalse(w.standardWindowButton(.zoomButton)!.isEnabled)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 58, y: 186)), .client, "a disabled zoom button is plain content")
            w.setFrame(NSRect(x: 0, y: 0, width: 400, height: 300), display: false)
            let row = w.standardWindowButton(.closeButton)!.superview!
            XCTAssertEqual(row.frame.maxY, w.contentRect(forFrameRect: w.frame).height)
            XCTAssertEqual(row.frame.origin.x, 0)
            XCTAssertEqual(row.frame.width, 400, "the row spans the band, like AppKit's theme frame")
            XCTAssertEqual(w.standardWindowButton(.closeButton)!.frame.origin.x, 12, "the buttons keep their place at the left")
            w.close()
        }
    }

    func testClickingCloseClosesAndTheOthersReachTheWindow() {
        withTrafficLights {
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
            // A press and release on the close circle closes the window (wherever it is now:
            // a native zoom, as on Win32, made the window fill the screen).
            let center = windowCenter(of: w.standardWindowButton(.closeButton)!)
            XCTAssertTrue(w.isVisible)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!)
            XCTAssertFalse(w.isVisible)
        }
    }

    /// The window system minimising or restoring the window on its own (taskbar, Win+D,
    /// the window manager) reaches the delegate through the platform callbacks, and a
    /// backend that also reports the `miniaturize()` it was asked for does not double up.
    func testSystemMinimiseAndRestoreReachTheDelegateOnce() {
        MainActor.assumeIsolated {
            final class Delegate: NSObject, NSWindowDelegate {
                var minis = 0, deminis = 0
                func windowDidMiniaturize(_ n: Notification) { minis += 1 }
                func windowDidDeminiaturize(_ n: Notification) { deminis += 1 }
            }
            let w = window([.titled, .closable, .miniaturizable])
            let delegate = Delegate()
            w.delegate = delegate
            w.makeKeyAndOrderFront(nil)
            w.platformWindowDidMiniaturize()          // the taskbar minimised it
            XCTAssertEqual(delegate.minis, 1)
            w.platformWindowDidMiniaturize()          // a repeated WM_SIZE while iconic
            XCTAssertEqual(delegate.minis, 1)
            w.platformWindowDidDeminiaturize()        // the taskbar restored it
            XCTAssertEqual(delegate.deminis, 1)
            w.deminiaturize(nil)                      // nothing to restore
            XCTAssertEqual(delegate.deminis, 1)
            w.miniaturize(nil)                        // the API path
            w.platformWindowDidMiniaturize()          // and the backend's synchronous report of it
            XCTAssertEqual(delegate.minis, 2)
            w.deminiaturize(nil)
            w.platformWindowDidDeminiaturize()
            XCTAssertEqual(delegate.deminis, 2)
            w.close()
        }
    }

    /// An application that moves a standard button (`setFrameOrigin`, y from the top as
    /// in AppKit's flipped theme frame) keeps it there across the window's relayouts, and
    /// the moved button still takes clicks and reports itself to the backend.
    func testRepositionedButtonsSurviveRelayoutAndStillHitTest() {
        withTrafficLights {
            let w = window([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            defer { w.close() }
            let close = w.standardWindowButton(.closeButton)!
            close.setFrameOrigin(NSPoint(x: 100, y: 8))
            w.setFrame(NSRect(x: 0, y: 0, width: 500, height: 300), display: false)
            XCTAssertEqual(close.frame.origin, NSPoint(x: 100, y: 8))
            XCTAssertEqual(w.standardWindowButton(.miniaturizeButton)!.frame.origin.x, 32, "the others were placed by the window")
            let band = w.contentView!.bounds.height - 14
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 106, y: band)), .closeButton)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 18, y: band)), .caption, "where the close button was is the draggable band")
            XCTAssertEqual(w._windowButtonsLeadingInset, 100 + 12 + 8 + 4, "the inset follows the moved button")
            XCTAssertEqual(w._windowButtonsTrailingInset, 0)
            close.isHidden = true
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 106, y: band)), .caption, "a hidden button is not hit")
            XCTAssertEqual(w._windowButtonsLeadingInset, _NSWindowButtonsView.width + 4, "and a hidden one no longer counts")
        }
    }

    /// The traffic-light layout (macOS, Linux, the host backend), pinned so these run on
    /// the Win32 backend too, whose own look is the caption buttons below.
    private func withTrafficLights(_ body: @MainActor () -> Void) {
        MainActor.assumeIsolated { withWindowButtonStyle(.trafficLights, body) }
    }

    // MARK: Windows caption buttons (ADR-0022)

    private func withCaptionButtons(_ body: @MainActor () -> Void) {
        MainActor.assumeIsolated { withWindowButtonStyle(.caption, body) }
    }

    /// With the Windows style the row puts minimise, maximise and close at the top-right,
    /// 46 points each, and the hit test names them so Win32 answers HTMINBUTTON,
    /// HTMAXBUTTON and HTCLOSE; the gaps still drag and disabled buttons are content.
    func testCaptionButtonsSitAtTheTopRight() {
        withCaptionButtons {
            let w = window([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            defer { w.close() }
            let close = w.standardWindowButton(.closeButton)!
            let mini = w.standardWindowButton(.miniaturizeButton)!
            let zoom = w.standardWindowButton(.zoomButton)!
            XCTAssertEqual((close as? _NSWindowButton)?.style, .caption)
            XCTAssertEqual(close.frame, NSRect(x: 300 - 46, y: 0, width: 46, height: 28))
            XCTAssertEqual(zoom.frame.origin.x, 300 - 92)
            XCTAssertEqual(mini.frame.origin.x, 300 - 138)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 290, y: 186)), .closeButton)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 230, y: 186)), .zoomButton)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 170, y: 186)), .miniaturizeButton)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 150, y: 186)), .caption, "left of the buttons the band drags")
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 18, y: 186)), .caption, "nothing at the left any more")
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 290, y: 150)), .client, "below the band is content")
            XCTAssertEqual(w._windowButtonsLeadingInset, 0)
            XCTAssertEqual(w._windowButtonsTrailingInset, _NSWindowButtonsView.captionWidth + 4)
            // Resizing keeps them at the right edge.
            w.setFrame(NSRect(x: 0, y: 0, width: 500, height: 300), display: false)
            XCTAssertEqual(close.frame.origin.x, 500 - 46)
            let band = w.contentView!.bounds.height - 14
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 490, y: band)), .closeButton)
            // A non-resizable window: the maximise button is there, greyed, and is content.
            w.styleMask.remove(.resizable)
            XCTAssertFalse(zoom.isEnabled)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 430, y: band)), .client)
        }
    }

    /// Hover lights one caption button at a time and a press-and-release on close closes
    /// the window, the same as a click delivered from the client area.
    func testCaptionButtonsHoverAndClick() {
        withCaptionButtons {
            let w = window([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            w.makeKeyAndOrderFront(nil)
            let close = w.standardWindowButton(.closeButton) as! _NSWindowButton
            let zoom = w.standardWindowButton(.zoomButton) as! _NSWindowButton
            @MainActor func move(to p: NSPoint) {
                w.sendEvent(NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
            }
            move(to: NSPoint(x: 290, y: 186))
            XCTAssertTrue(close.isHovered)
            XCTAssertFalse(zoom.isHovered)
            move(to: NSPoint(x: 230, y: 186))
            XCTAssertFalse(close.isHovered)
            XCTAssertTrue(zoom.isHovered)
            move(to: NSPoint(x: -100_000, y: -100_000))      // the backend's "pointer left"
            XCTAssertFalse(zoom.isHovered)
            let center = NSPoint(x: 290, y: 186)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!)
            XCTAssertFalse(w.isVisible)
        }
    }

    /// The caption buttons render: a fill under the hovered close button (red) and glyphs
    /// in the others, and nothing where the traffic lights used to be.
    func testCaptionButtonsDraw() {
        withCaptionButtons {
            let w = window([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            defer { w.close() }
            w.backgroundColor = .white
            w.makeKeyAndOrderFront(nil)
            let close = w.standardWindowButton(.closeButton) as! _NSWindowButton
            close.isHovered = true
            w.display()
            guard let image = (w._platformWindow as? HostWindow)?.lastImage else { return XCTFail("no host image") }
            let scale = Int(w.backingScaleFactor)
            let data = _pixels(image)
            func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {     // y from the top, in points
                let i = (y * scale) * image.bytesPerRow + (x * scale) * 4
                return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))     // BGRA
            }
            let red = pixel(300 - 40, 3)
            XCTAssertGreaterThan(red.r, 150, "the hovered close button is red: \(red)")
            XCTAssertLessThan(red.g, 90, "\(red)")
            let gap = pixel(300 - 140, 14)
            XCTAssertEqual(gap.r, 255, "left of the buttons the background shows: \(gap)")
            let left = pixel(18, 14)
            XCTAssertEqual(left.r, 255, "no traffic light at the left: \(left)")
            // A dark pixel somewhere along the minimise glyph (a 10-point line at mid height).
            var darkest = 255
            for x in (300 - 138 + 15)...(300 - 138 + 31) { for y in 12...16 { darkest = min(darkest, pixel(x, y).r) } }
            XCTAssertLessThan(darkest, 120, "the minimise glyph is drawn")
        }
    }

    /// A FramelessWindow-style window (content covering the title bar, movable by
    /// background, non-opaque, clear background) under the caption style is shown, key,
    /// on screen and painted after `makeKeyAndOrderFront`, with the buttons placed in
    /// its band: the overlay must never keep a window from appearing.
    func testFramelessWindowIsVisibleWithCaptionButtons() {
        withCaptionButtons {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            defer { w.close() }
            w.title = "Frameless"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.isMovableByWindowBackground = true
            w.minSize = NSSize(width: 320, height: 200)
            w.center()
            w.makeKeyAndOrderFront(nil)
            let host = w._platformWindow as! HostWindow
            XCTAssertTrue(w.isVisible)
            XCTAssertTrue(host.isVisible, "the platform window was shown")
            XCTAssertTrue(w.isKeyWindow)
            XCTAssertEqual(w.frame.size.width, 480)
            XCTAssertTrue(NSScreen.main!.frame.contains(w.frame), "on screen: \(w.frame)")
            w.display()
            XCTAssertNotNil(host.lastImage, "a frame was painted")
            XCTAssertTrue(w._showsWindowButtons)
            let row = w.standardWindowButton(.closeButton)!.superview!
            XCTAssertFalse(row.isHidden)
            XCTAssertEqual(row.frame.width, w.contentView!.bounds.width)
            XCTAssertEqual(row.frame.maxY, w.contentView!.bounds.height)
            XCTAssertEqual(w.standardWindowButton(.closeButton)!.frame.maxX, 480)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 240, y: 150)), .caption, "movable by background")
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 470, y: w.contentView!.bounds.height - 14)), .closeButton)
        }
    }

    /// Under either button style, a plain titled window and a `fullSizeContentView` window
    /// come up with their frames and titles intact after `makeKeyAndOrderFront`: the
    /// buttons overlay never feeds the platform window an empty frame or steals the title.
    func testWindowsKeepTheirFramesAndTitlesUnderBothStyles() {
        for style in [PlatformWindowButtonStyle.trafficLights, .caption] {
            MainActor.assumeIsolated {
                let host = Platform.backend as! HostBackend
                host.windowButtonStyle = style
                defer { host.windowButtonStyle = .trafficLights }
                for mask in [NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable]),
                             [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]] {
                    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 300), styleMask: mask, backing: .buffered, defer: false)
                    defer { w.close() }
                    w.title = "Toolbar"
                    w.makeKeyAndOrderFront(nil)
                    let platform = w._platformWindow as! HostWindow
                    XCTAssertTrue(platform.isVisible, "\(style) \(mask.rawValue)")
                    XCTAssertEqual(platform.title, "Toolbar", "\(style) \(mask.rawValue)")
                    XCTAssertEqual(platform.frame.width, 600, "\(style) \(mask.rawValue)")
                    XCTAssertGreaterThanOrEqual(platform.frame.height, 300, "\(style) \(mask.rawValue)")
                    XCTAssertEqual(w.contentRect(forFrameRect: w.frame).size, NSSize(width: 600, height: 300), "\(style) \(mask.rawValue)")
                    XCTAssertEqual(w.contentView!.frame.size, NSSize(width: 600, height: 300), "\(style) \(mask.rawValue)")
                    XCTAssertEqual(w._showsWindowButtons, mask.contains(.fullSizeContentView))
                }
            }
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
