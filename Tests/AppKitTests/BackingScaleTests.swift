// A window moving between monitors of different scale (a 100% and a 200% monitor on
// Windows, two Wayland outputs): the host backend's `setBackingScaleFactor` plays the
// window system's report, and the core must keep the point size, re-render every pixel
// at the new scale, tell the view tree, and report the screen it is now on.
import XCTest
@testable import AppKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif

@MainActor
private final class RecordingView: NSView {
    var backingChanges = 0
    var color: NSColor? = nil
    init(frame: NSRect, color: NSColor? = nil) { self.color = color; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        backingChanges += 1
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let color else { return }
        color.setFill()
        NSBezierPath.fill(bounds)
    }
}

@MainActor
private final class TextView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        "Wg".draw(at: NSPoint(x: 10, y: 10), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.black])
    }
}

/// Counts notifications from an observer closure (which Linux's Foundation makes `@Sendable`).
private final class Counter: @unchecked Sendable { var n = 0 }

@MainActor
private final class BackingDelegate: NSObject, NSWindowDelegate {
    var backingChanges = 0
    func windowDidChangeBackingProperties(_ notification: Notification) { backingChanges += 1 }
}

final class BackingScaleTests: XCTestCase, @unchecked Sendable {
    @MainActor private func host(_ w: NSWindow) -> HostWindow { Mirror(reflecting: w).descendant("_platform") as! HostWindow }

    #if canImport(CoreGraphics)
    /// Pixel (BGRA) at AppKit point coordinates scaled by `scale`, from a top-down image.
    @MainActor private func pixel(_ image: CGImage, _ data: Data, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let row = image.height - 1 - y
        let i = row * image.bytesPerRow + x * 4
        return (data[i + 2], data[i + 1], data[i])
    }

    /// Width in pixels of the run of red pixels along a pixel row (AppKit y, pixels).
    @MainActor private func redExtent(_ image: CGImage, row y: Int) -> Int {
        let data = _pixels(image)
        var count = 0
        for x in 0..<image.width {
            let p = pixel(image, data, x: x, y: y)
            if p.r > 200 && p.g < 40 && p.b < 40 { count += 1 }
        }
        return count
    }

    /// Bounding box of dark pixels (ink) in a top-down image, in pixels.
    @MainActor private func inkBox(_ image: CGImage) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        let data = _pixels(image)
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for row in 0..<image.height {
            for x in 0..<image.width {
                let i = row * image.bytesPerRow + x * 4
                if data[i] < 100 && data[i + 1] < 100 && data[i + 2] < 100 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, row); maxY = max(maxY, row)
                }
            }
        }
        return maxX < 0 ? nil : (minX, maxX, minY, maxY)
    }

    func testMoveToDoubleScaleKeepsPointSizeAndDoublesPixels() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            let delegate = BackingDelegate()
            w.delegate = delegate
            let red = RecordingView(frame: NSRect(x: 10, y: 10, width: 40, height: 40), color: .red)
            w.contentView!.addSubview(red)
            let platform = host(w)
            platform.setBackingScaleFactor(1)
            w.makeKeyAndOrderFront(nil)
            w.display()
            XCTAssertEqual(w.backingScaleFactor, 1)
            let frameBefore = w.frame
            guard let one = platform.lastImage else { return XCTFail("no image") }
            XCTAssertEqual(one.width, 100); XCTAssertEqual(one.height, 100)
            XCTAssertEqual(redExtent(one, row: 30), 40)

            // The move to 1x above already counted once; the move to 2x counts once more.
            let delegateBefore = delegate.backingChanges, viewBefore = red.backingChanges
            let notified = Counter()
            let token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: w, queue: nil) { _ in notified.n += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            platform.setBackingScaleFactor(2)
            XCTAssertEqual(w.backingScaleFactor, 2)
            XCTAssertEqual(w.frame, frameBefore, "the frame keeps its point size and position")
            XCTAssertEqual(w.contentView!.frame.size, NSSize(width: 100, height: 100))
            XCTAssertEqual(red.frame, NSRect(x: 10, y: 10, width: 40, height: 40))
            XCTAssertEqual(notified.n, 1)
            XCTAssertEqual(delegate.backingChanges, delegateBefore + 1)
            XCTAssertEqual(red.backingChanges, viewBefore + 1)
            XCTAssertEqual(w.convertToBacking(NSRect(x: 0, y: 0, width: 100, height: 100)), NSRect(x: 0, y: 0, width: 200, height: 200))

            // The change marked the whole window dirty: displayIfNeeded repaints at 2x.
            let paints = platform.paintCount
            w.displayIfNeeded()
            XCTAssertEqual(platform.paintCount, paints + 1, "a backing change repaints the window")
            guard let two = platform.lastImage else { return XCTFail("no image") }
            XCTAssertEqual(two.width, 200); XCTAssertEqual(two.height, 200)
            XCTAssertEqual(redExtent(two, row: 60), 80, "the rect's pixel extent doubles")
            let data = _pixels(two)
            let inside = pixel(two, data, x: 30 * 2, y: 30 * 2)
            XCTAssertGreaterThan(inside.r, 200); XCTAssertLessThan(inside.g, 40)
            let outside = pixel(two, data, x: 75 * 2, y: 75 * 2)
            XCTAssertGreaterThan(outside.r, 200); XCTAssertGreaterThan(outside.g, 200); XCTAssertGreaterThan(outside.b, 200)

            // And back to 1x.
            platform.setBackingScaleFactor(1)
            w.displayIfNeeded()
            XCTAssertEqual(platform.lastImage?.width, 100)
            XCTAssertEqual(redExtent(platform.lastImage!, row: 30), 40)
            XCTAssertEqual(red.backingChanges, viewBefore + 2)
            w.close()
        }
    }

    func testTextRerendersAtTheNewPixelSize() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            w.contentView!.addSubview(TextView(frame: NSRect(x: 0, y: 0, width: 120, height: 80)))
            let platform = host(w)
            platform.setBackingScaleFactor(1)
            w.makeKeyAndOrderFront(nil)
            w.display()
            guard let one = platform.lastImage, let inkOne = inkBox(one) else { return XCTFail("no text at 1x") }
            platform.setBackingScaleFactor(2)
            w.displayIfNeeded()
            guard let two = platform.lastImage, let inkTwo = inkBox(two) else { return XCTFail("no text at 2x") }
            XCTAssertEqual(two.width, 240); XCTAssertEqual(two.height, 160)
            let widthOne = inkOne.maxX - inkOne.minX + 1, widthTwo = inkTwo.maxX - inkTwo.minX + 1
            let heightOne = inkOne.maxY - inkOne.minY + 1, heightTwo = inkTwo.maxY - inkTwo.minY + 1
            // Glyphs are laid out in points and rasterised in pixels: their ink is about twice as
            // wide and tall at 2x (hinting and antialiasing shift the edges by a pixel or two).
            XCTAssertGreaterThan(widthOne, 20)
            XCTAssertEqual(Double(widthTwo), Double(widthOne) * 2, accuracy: 6, "text ink width at 2x: \(widthTwo) vs \(widthOne) at 1x")
            XCTAssertEqual(Double(heightTwo), Double(heightOne) * 2, accuracy: 6, "text ink height at 2x: \(heightTwo) vs \(heightOne) at 1x")
            // Same place in points: the ink's left edge in points is unchanged.
            XCTAssertEqual(Double(inkTwo.minX) / 2, Double(inkOne.minX), accuracy: 2)
            w.close()
        }
    }

    func testLayerBackedViewsRerasteriseAtTheNewScale() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            let red = RecordingView(frame: NSRect(x: 10, y: 10, width: 40, height: 40), color: .red)
            w.contentView!.addSubview(red)
            w.contentView!.wantsLayer = true
            let platform = host(w)
            platform.layerHostingEnabled = true
            platform.setBackingScaleFactor(1)
            w.makeKeyAndOrderFront(nil)
            w._updateLayerHosting()
            w.display()
            XCTAssertTrue(w._hostsLayersNatively)
            XCTAssertEqual(platform.hostedScene?.scale, 1)
            XCTAssertEqual(red.layer?.contentsScale, 1)
            guard let one = platform.lastImage else { return XCTFail("no image") }
            XCTAssertEqual(one.width, 100)
            XCTAssertEqual(redExtent(one, row: 30), 40)
            let rasters = platform.rasterCount, viewBefore = red.backingChanges

            platform.setBackingScaleFactor(2)
            XCTAssertEqual(red.layer?.contentsScale, 2, "every layer in the tree takes the new contents scale")
            XCTAssertEqual(w.contentView!.layer?.contentsScale, 2)
            XCTAssertEqual(red.backingChanges, viewBefore + 1)
            w.displayIfNeeded()        // commits the re-rasterised scene and composites it
            XCTAssertEqual(platform.hostedScene?.scale, 2, "the hosted scene is rebuilt at the new scale")
            XCTAssertGreaterThan(platform.rasterCount, rasters, "layer contents are rasterised again at 2x")
            guard let two = platform.lastImage else { return XCTFail("no image") }
            XCTAssertEqual(two.width, 200); XCTAssertEqual(two.height, 200)
            XCTAssertEqual(redExtent(two, row: 60), 80, "the layer-backed rect's pixel extent doubles")
            w.close()
        }
    }
    #endif

    func testViewDidChangeBackingPropertiesReachesTheWholeTree() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let a = RecordingView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
            let b = RecordingView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
            let c = RecordingView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
            let hidden = RecordingView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
            hidden.isHidden = true
            w.contentView!.addSubview(a)
            a.addSubview(b)
            b.addSubview(c)
            a.addSubview(hidden)
            let platform = host(w)
            platform.setBackingScaleFactor(1)
            XCTAssertEqual([a, b, c, hidden].map(\.backingChanges), [1, 1, 1, 1])
            platform.setBackingScaleFactor(2)
            XCTAssertEqual([a, b, c, hidden].map(\.backingChanges), [2, 2, 2, 2], "every view, hidden ones too, hears about the change once")
            platform.setBackingScaleFactor(2)
            XCTAssertEqual(a.backingChanges, 2, "no change, no callback")
            w.close()
        }
    }

    func testScreenReportsTheMonitorTheWindowMovedTo() {
        MainActor.assumeIsolated {
            let backend = Platform.backend as! HostBackend
            let saved = backend.displays
            defer { backend.displays = saved }
            backend.displays.append(PlatformDisplay(frame: NSRect(x: 1920, y: 0, width: 1280, height: 1024),
                                                    visibleFrame: NSRect(x: 1920, y: 0, width: 1280, height: 1000),
                                                    backingScaleFactor: 1, localizedName: "Second Display", isMain: false))
            XCTAssertEqual(NSScreen.screens.count, 2)
            XCTAssertEqual(NSScreen.screens.map(\.backingScaleFactor), [2, 1])

            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            w.makeKeyAndOrderFront(nil)
            XCTAssertEqual(w.screen?.localizedName, "Host Display")
            XCTAssertEqual(w.screen?.backingScaleFactor, 2)
            XCTAssertEqual(w.backingScaleFactor, 2)
            XCTAssertEqual(NSScreen.main?.localizedName, "Host Display")

            // Dragged onto the second monitor: the window system moves the frame and then
            // reports the new scale (WM_DPICHANGED); the window's own scale follows.
            w.setFrameOrigin(NSPoint(x: 2000, y: 100))
            host(w).setBackingScaleFactor(1)
            XCTAssertEqual(w.screen?.localizedName, "Second Display")
            XCTAssertEqual(w.screen?.backingScaleFactor, 1)
            XCTAssertEqual(w.backingScaleFactor, 1)
            XCTAssertEqual(w.frame.size, NSSize(width: 300, height: 200 + HostWindow.titleBarHeight))
            XCTAssertEqual(NSScreen.main?.localizedName, "Second Display", "the key window's screen is the main screen")
            w.close()
        }
    }
}

#if os(Linux)
/// Wayland: a surface's scale follows the outputs it is on. `WaylandWindow` itself needs a
/// compositor (`tools/linux/run-wayland.sh` moves HelloWindow to a 2x headless output and
/// checks the backing-scale trace and the unchanged logical size); the rule it applies in
/// `outputsDidChange` is checked here.
final class WaylandScaleTests: XCTestCase, @unchecked Sendable {
    func testSurfaceScaleFollowsTheOutputsItIsOn() {
        MainActor.assumeIsolated {
            let one = WaylandOutput(proxy: OpaquePointer(bitPattern: 0x10)!, name: 1)
            let two = WaylandOutput(proxy: OpaquePointer(bitPattern: 0x20)!, name: 2)
            two.scale = 2
            XCTAssertEqual(WaylandWindow.scale(forOutputs: [one], current: 1), 1)
            XCTAssertEqual(WaylandWindow.scale(forOutputs: [one, two], current: 1), 2, "straddling two outputs: the larger scale")
            XCTAssertEqual(WaylandWindow.scale(forOutputs: [two], current: 1), 2, "moved to the 2x output")
            XCTAssertEqual(WaylandWindow.scale(forOutputs: [one], current: 2), 1, "moved back to the 1x output")
            XCTAssertEqual(WaylandWindow.scale(forOutputs: [], current: 2), 2, "left every output: keeps its scale")
            one.scale = 3
            XCTAssertEqual(WaylandWindow.scale(forOutputs: [one], current: 1), 3, "an output's scale changed under the surface")
        }
    }
}
#endif
