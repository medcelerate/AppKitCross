// Client-side window decorations (ADR-0015): the mode a window ends up with, the surface
// geometry a decorated toplevel reports to the compositor, hit-testing of the band and the
// resize handles, and the title band the window draws with its standard buttons. All of it
// is platform-neutral; the Wayland window only feeds it pointer positions and configure
// states, so these run on every platform.

import XCTest
@testable import AppKit

final class ClientSideDecorationTests: XCTestCase, @unchecked Sendable {
    private let titled: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

    private func layout(_ mask: NSWindow.StyleMask, mode: ClientSideDecorationMode = .client, covers: Bool = false,
                        tiled: Bool = false, fullScreen: Bool = false, size: NSSize = NSSize(width: 400, height: 328)) -> ClientSideDecorationLayout {
        ClientSideDecorationLayout(mode: mode, styleMask: mask, contentCoversTitleBar: covers, tiledOrMaximized: tiled, fullScreen: fullScreen, frameSize: size)
    }

    func testModeFollowsTheStyleMaskAndTheCompositorsAnswer() {
        XCTAssertEqual(ClientSideDecorationMode.mode(for: titled, serverSideGranted: nil), .client, "no xdg-decoration (Mutter): the package decorates")
        XCTAssertEqual(ClientSideDecorationMode.mode(for: titled, serverSideGranted: false), .client, "the compositor answered client side")
        XCTAssertEqual(ClientSideDecorationMode.mode(for: titled, serverSideGranted: true), .server, "the compositor draws the frame")
        XCTAssertEqual(ClientSideDecorationMode.mode(for: [.borderless], serverSideGranted: nil), .none)
        XCTAssertEqual(ClientSideDecorationMode.mode(for: [.borderless], serverSideGranted: true), .none)
        XCTAssertEqual(ClientSideDecorationMode.mode(for: [.titled, .nonactivatingPanel], serverSideGranted: nil), .none, "menus and pop-ups get nothing")
        XCTAssertEqual(ClientSideDecorationMode.mode(for: [.titled, .fullSizeContentView], serverSideGranted: nil), .client, "content under the band still gets shadow and edges")
    }

    func testGeometryReportsTheFrameInsideTheShadowMargin() {
        let l = layout(titled)
        XCTAssertEqual(l.titleBarHeight, 28, "AppKit's title bar height")
        MainActor.assumeIsolated { XCTAssertEqual(l.titleBarHeight, NSWindow._titleBarBandHeight) }
        XCTAssertEqual(l.shadowMargin, 24)
        XCTAssertEqual(l.contentSize, NSSize(width: 400, height: 300))
        XCTAssertEqual(l.surfaceSize, NSSize(width: 448, height: 376))
        XCTAssertEqual(l.windowGeometry, NSRect(x: 24, y: 24, width: 400, height: 328), "xdg_surface.set_window_geometry: the frame, not the shadow")
        XCTAssertEqual(l.inputRegion, NSRect(x: 14, y: 14, width: 420, height: 348), "resize handles reach 10pt into the shadow")
        XCTAssertEqual(l.titleBarRect, NSRect(x: 0, y: 300, width: 400, height: 28), "window coordinates: the band above the content")
        XCTAssertTrue(l.isResizable && l.hasDecorations)
        XCTAssertEqual(ClientSideDecorationLayout.frameSize(forContentSize: NSSize(width: 400, height: 300), titleBarHeight: 28), NSSize(width: 400, height: 328))
        XCTAssertEqual(ClientSideDecorationLayout.contentSize(forFrameSize: NSSize(width: 400, height: 328), titleBarHeight: 28), NSSize(width: 400, height: 300))

        let fixed = layout([.titled, .closable])
        XCTAssertFalse(fixed.isResizable)
        XCTAssertEqual(fixed.inputRegion, fixed.windowGeometry, "nothing to grab in the shadow of a fixed-size window")

        let maximized = layout(titled, tiled: true)
        XCTAssertEqual(maximized.shadowMargin, 0, "maximised and tiled windows fill their slot")
        XCTAssertEqual(maximized.cornerRadius, 0)
        XCTAssertEqual(maximized.titleBarHeight, 28)
        XCTAssertEqual(maximized.surfaceSize, maximized.frameSize)
        XCTAssertEqual(maximized.windowGeometry, NSRect(origin: .zero, size: maximized.frameSize))

        let fullScreen = layout(titled, fullScreen: true)
        XCTAssertFalse(fullScreen.hasDecorations, "full screen: the content alone")
        XCTAssertEqual(fullScreen.contentSize, fullScreen.frameSize)

        let covered = layout([.titled, .resizable, .fullSizeContentView], covers: true)
        XCTAssertEqual(covered.titleBarHeight, 0, "fullSizeContentView: the content reaches the top, the window's overlay buttons sit on it")
        XCTAssertEqual(covered.shadowMargin, 24)
        XCTAssertTrue(covered.titleBarRect.isEmpty)

        XCTAssertFalse(layout(titled, mode: .server).hasDecorations, "server-side: the surface is the content")
        XCTAssertEqual(layout(titled, mode: .server).surfaceSize, NSSize(width: 400, height: 328))
        XCTAssertFalse(layout([.borderless], mode: .none).hasDecorations)
    }

    func testPointConversionBetweenSurfaceAndWindow() {
        let l = layout(titled)
        // The surface's top-left is above and left of the frame by the margin.
        XCTAssertEqual(l.windowPoint(fromSurface: NSPoint(x: 24, y: 24)), NSPoint(x: 0, y: 328))
        XCTAssertEqual(l.windowPoint(fromSurface: NSPoint(x: 24, y: 352)), NSPoint(x: 0, y: 0), "the frame's bottom-left is the window origin")
        XCTAssertEqual(l.windowPoint(fromSurface: NSPoint(x: 124, y: 38)), NSPoint(x: 100, y: 314), "in the band")
        XCTAssertEqual(l.surfacePoint(fromWindow: NSPoint(x: 100, y: 314)), NSPoint(x: 124, y: 38))
        let flat = layout(titled, mode: .server)
        XCTAssertEqual(flat.windowPoint(fromSurface: NSPoint(x: 10, y: 10)), NSPoint(x: 10, y: 318), "no margin: plain flip")
    }

    func testHitTestingOfBandEdgesAndCorners() {
        let l = layout(titled)                    // frame at (24, 24) 400x328 in the surface
        XCTAssertEqual(l.hitTest(NSPoint(x: 5, y: 5)), .outside, "far shadow")
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 5)), .outside)
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 18)), .resize(.top), "shadow near the top edge")
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 26)), .resize(.top), "just inside the top edge")
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 30)), .titleBar, "past the grip: the band")
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 51)), .titleBar, "last row of the band")
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 52)), .content, "first row of the content")
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 200)), .content)
        XCTAssertEqual(l.hitTest(NSPoint(x: 26, y: 200)), .resize(.left))
        XCTAssertEqual(l.hitTest(NSPoint(x: 422, y: 200)), .resize(.right))
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 350)), .resize(.bottom))
        XCTAssertEqual(l.hitTest(NSPoint(x: 200, y: 360)), .resize(.bottom), "shadow below the bottom edge")
        XCTAssertEqual(l.hitTest(NSPoint(x: 18, y: 18)), .resize(.topLeft))
        XCTAssertEqual(l.hitTest(NSPoint(x: 26, y: 35)), .resize(.topLeft), "an edge hit near a corner widens into the corner")
        XCTAssertEqual(l.hitTest(NSPoint(x: 35, y: 26)), .resize(.topLeft))
        XCTAssertEqual(l.hitTest(NSPoint(x: 420, y: 26)), .resize(.topRight))
        XCTAssertEqual(l.hitTest(NSPoint(x: 26, y: 345)), .resize(.bottomLeft))
        XCTAssertEqual(l.hitTest(NSPoint(x: 430, y: 358)), .resize(.bottomRight))
        XCTAssertEqual(l.hitTest(NSPoint(x: 26, y: 60)), .resize(.left), "beyond the corner grip: a plain edge")
        // xdg_toplevel.resize_edge values and cursors.
        XCTAssertEqual(ClientSideDecorationResizeEdge.topLeft.rawValue, 5)
        XCTAssertEqual(ClientSideDecorationResizeEdge.bottomRight.rawValue, 10)
        XCTAssertEqual(ClientSideDecorationResizeEdge.top.cursorNames.first, "ns-resize")
        XCTAssertEqual(ClientSideDecorationResizeEdge.topRight.cursorNames.first, "nesw-resize")

        let fixed = layout([.titled, .closable])
        XCTAssertEqual(fixed.hitTest(NSPoint(x: 200, y: 18)), .outside, "no handles on a fixed-size window")
        XCTAssertEqual(fixed.hitTest(NSPoint(x: 200, y: 26)), .titleBar)
        XCTAssertEqual(fixed.hitTest(NSPoint(x: 26, y: 200)), .content)

        let covered = layout([.titled, .resizable, .fullSizeContentView], covers: true)
        XCTAssertEqual(covered.hitTest(NSPoint(x: 200, y: 40)), .content, "no band: the window's own drag band rules")
        XCTAssertEqual(covered.hitTest(NSPoint(x: 200, y: 26)), .resize(.top))

        let maximized = layout(titled, tiled: true)
        XCTAssertEqual(maximized.hitTest(NSPoint(x: 200, y: 2)), .resize(.top), "edges still resize without a margin")
        XCTAssertEqual(maximized.hitTest(NSPoint(x: 200, y: 10)), .titleBar)
        XCTAssertEqual(maximized.hitTest(NSPoint(x: 200, y: 100)), .content)

        let server = layout(titled, mode: .server)
        XCTAssertEqual(server.hitTest(NSPoint(x: 200, y: 2)), .content, "the compositor's frame is not on our surface")
        XCTAssertEqual(server.hitTest(NSPoint(x: 200, y: 10)), .content)
    }

    // MARK: The window's side: band, buttons, hit regions

    @MainActor private func decoratedWindow(_ mask: NSWindow.StyleMask) -> (NSWindow, HostWindow) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: mask, backing: .buffered, defer: false)
        let host = w._platformWindow as! HostWindow
        host.clientSideTitleBar = true
        w.title = "Decorated"
        w.platformWindowDidChangeFrame(w.frame)   // what a backend reports when its band appears: the buttons move into it
        return (w, host)
    }

    func testWindowShowsItsButtonsInTheBandAndDragsTheRest() {
        MainActor.assumeIsolated {
            let (w, host) = decoratedWindow(titled)
            defer { w.close() }
            XCTAssertTrue(host.hasClientSideTitleBar)
            XCTAssertTrue(w._showsWindowButtons, "a plain titled window shows the standard buttons when the package draws its title bar")
            XCTAssertEqual(w.frame.height, 328, "the frame is the content plus the band")
            let close = w.standardWindowButton(.closeButton)!
            let row = close.superview!
            XCTAssertEqual(row.frame.maxY, 328, "the row sits in the band, above the content")
            XCTAssertEqual(row.frame.minY, 300)
            XCTAssertFalse(row.isHidden)
            // Band points: buttons are content (they take the click), the rest drags the window.
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 18, y: 314)), .client, "the close button")
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 58, y: 314)), .client, "the zoom button")
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 4, y: 314)), .caption, "the gap before the buttons")
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 200, y: 314)), .caption, "the title")
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 200, y: 290)), .client, "content just below the band")

            // The same window with the compositor decorating: no overlay, no band.
            host.clientSideTitleBar = false
            w.platformWindowDidChangeFrame(w.frame)
            XCTAssertFalse(w._showsWindowButtons)
            XCTAssertTrue(row.isHidden)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 200, y: 314)), .client)
        }
    }

    func testBandClickCloses_DoubleClickZooms() {
        MainActor.assumeIsolated {
            final class Delegate: NSObject, NSWindowDelegate {
                var zoomAsked = 0
                func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { zoomAsked += 1; return true }
            }
            let (w, _) = decoratedWindow(titled)
            let delegate = Delegate()
            w.delegate = delegate
            w.makeKeyAndOrderFront(nil)
            w.platformWindowTitleBarDoubleClicked()
            XCTAssertEqual(delegate.zoomAsked, 1, "a double click on the band is performZoom:")
            let fixed = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            fixed.delegate = delegate
            fixed.platformWindowTitleBarDoubleClicked()
            XCTAssertEqual(delegate.zoomAsked, 1, "not on a window that cannot resize")
            fixed.close()
            // A press and release on the close circle, at its band location, closes the window.
            let center = NSPoint(x: 18, y: 314)
            XCTAssertTrue(w.isVisible)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            w.sendEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: center, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!)
            XCTAssertFalse(w.isVisible)
        }
    }

    /// The band is painted into a context in window coordinates: a flat bar of the
    /// appearance's colour, the close button's red at the left, the title in the middle,
    /// and nothing below the band.
    func testBandDrawsBackgroundButtonsAndTitle() {
        MainActor.assumeIsolated {
            let (w, _) = decoratedWindow(titled)
            defer { w.close() }
            w.makeKeyAndOrderFront(nil)
            @MainActor func render(dark: Bool) -> (CGImage, Data) {
                w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let ctx = CGContext(data: nil, width: 400, height: 328, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
                w.platformWindowDrawTitleBar(into: ctx, dirtyRect: NSRect(x: 0, y: 0, width: 400, height: 328))
                let image = ctx.makeImage()!
                return (image, _pixels(image))
            }
            func pixel(_ image: CGImage, _ data: Data, _ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int, a: Int) {   // window points, y up
                let i = (image.height - 1 - y) * image.bytesPerRow + x * 4
                return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
            }
            let (light, lightData) = render(dark: false)
            let bar = pixel(light, lightData, 380, 314)
            XCTAssertEqual(bar.a, 255)
            XCTAssertTrue(bar.r > 220 && bar.g > 220 && bar.b > 220, "a light band \(bar)")
            let close = pixel(light, lightData, 18, 314)
            XCTAssertTrue(close.r > 200 && close.g < 140, "the close button is red \(close)")
            XCTAssertEqual(pixel(light, lightData, 200, 150).a, 0, "nothing drawn in the content area")
            // The title: some pixel in the middle of the band is darker than the bar.
            var darkest = 255
            for x in 150..<250 { for y in 304..<324 { darkest = min(darkest, pixel(light, lightData, x, y).r) } }
            XCTAssertLessThan(darkest, 150, "the title text is drawn in the middle of the band")

            let (dark, darkData) = render(dark: true)
            let darkBar = pixel(dark, darkData, 380, 314)
            XCTAssertTrue(darkBar.r < 90 && darkBar.g < 90 && darkBar.b < 90, "a dark band under the dark appearance \(darkBar)")
        }
    }
}
