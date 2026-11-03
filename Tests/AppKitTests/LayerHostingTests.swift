// Native layer hosting: the window hands its layer tree to the platform as a scene of
// visuals. The host backend's reference compositor must match the software compositor.

import XCTest
@testable import AppKit
#if canImport(QuartzCore)
import QuartzCore
#endif

@MainActor
private final class BoxView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 4, y: 4, width: 30, height: 12)).fill()   // near the top in flipped space
    }
}

final class LayerHostingTests: XCTestCase, @unchecked Sendable {
    /// Rasterising a node into its own surface and compositing it anti-aliases edges once
    /// more than drawing straight into the window, so edge pixels may differ slightly.
    private func _assertSimilar(_ a: Data, _ b: Data, _ message: String = "", strongShare: Int = 200, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, message, file: file, line: line)
        guard a.count == b.count else { return }
        var off = 0, far = 0, maxDiff = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            var d = 0
            for c in 0..<4 { d = max(d, abs(Int(a[i + c]) - Int(b[i + c]))) }
            if d > 0 { off += 1 }
            if d > 48 { far += 1 }
            maxDiff = max(maxDiff, d)
        }
        let pixels = a.count / 4
        XCTAssertLessThan(far, pixels / strongShare, "\(message): \(far) of \(pixels) pixels differ strongly, \(off) at all, max \(maxDiff)", file: file, line: line)
    }

    @MainActor private func hostWindow(_ w: NSWindow) -> HostWindow {
        Mirror(reflecting: w).descendant("_platform") as! HostWindow
    }

    /// A window whose content view is layer-backed, with views and bare layers.
    @MainActor private func makeWindow() -> (NSWindow, CALayer, CALayer) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        w.backgroundColor = .white
        let box = BoxView(frame: NSRect(x: 20, y: 100, width: 60, height: 40))
        w.contentView!.addSubview(box)
        w.contentView!.wantsLayer = true
        let panel = CALayer()
        panel.frame = CGRect(x: 100, y: 20, width: 80, height: 60)
        panel.backgroundColor = CGColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        panel.cornerRadius = 8
        panel.borderWidth = 2
        panel.borderColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        panel.masksToBounds = true
        let child = CALayer()
        child.frame = CGRect(x: 50, y: 30, width: 60, height: 60)   // overhangs: clipped by the panel
        child.backgroundColor = CGColor(red: 0, green: 0.6, blue: 0.2, alpha: 1)
        child.opacity = 0.5
        panel.addSublayer(child)
        w.contentView!.layer!.addSublayer(panel)
        w.makeKeyAndOrderFront(nil)
        return (w, panel, child)
    }

    func testHostedCompositeMatchesSoftware() {
        MainActor.assumeIsolated {
            let (w, panel, child) = makeWindow()
            let host = hostWindow(w)
            w.display()
            XCTAssertFalse(w._hostsLayersNatively)
            let software = _pixels(host.lastImage!)

            host.layerHostingEnabled = true
            w._updateLayerHosting()
            XCTAssertTrue(w._hostsLayersNatively)
            w.display()
            let hosted = _pixels(host.lastImage!)
            XCTAssertEqual(hosted.count, software.count)
            _assertSimilar(hosted, software, "the reference compositor reproduces the software composite")

            // The scene: content view, box view, panel, child, panel border (pre-order, parents first).
            let scene = host.hostedScene!
            XCTAssertEqual(scene.nodes.count, 5)
            XCTAssertNil(scene.nodes[0].parent)
            XCTAssertEqual(scene.nodes[0].size, CGSize(width: 200, height: 150))
            let panelNode = scene.nodes.first { $0.size == CGSize(width: 80, height: 60) }!
            // y-down placement: the panel's top edge is 150 - (20 + 60) = 70 points from the top.
            XCTAssertEqual(panelNode.transform.tx, 100, accuracy: 0.001)
            XCTAssertEqual(panelNode.transform.ty, 70, accuracy: 0.001)
            XCTAssertTrue(panelNode.clipsToBounds)
            XCTAssertEqual(panelNode.cornerRadius, 8)
            let childNode = scene.nodes.first { $0.size == CGSize(width: 60, height: 60) && $0.parent != nil }!
            XCTAssertEqual(childNode.opacity, 0.5)
            XCTAssertEqual(childNode.transform.tx, 50, accuracy: 0.001)
            XCTAssertEqual(childNode.transform.ty, 60 - 30 - 60, accuracy: 0.001)
            XCTAssertEqual(scene.nodes.last!.name, nil)
            XCTAssertEqual(scene.nodes.last!.parent, scene.nodes.firstIndex { $0.size == panelNode.size })
            _ = panel; _ = child
            w.close()
        }
    }

    func testCommitsAndRastersOnlyWhenNeeded() {
        MainActor.assumeIsolated {
            let (w, panel, child) = makeWindow()
            let host = hostWindow(w)
            host.layerHostingEnabled = true
            w._updateLayerHosting()
            w.display()
            let commits = host.sceneCommitCount, rasters = host.rasterCount
            XCTAssertGreaterThan(rasters, 0)

            // Nothing changed: no commit, no raster.
            w.displayIfNeeded()
            XCTAssertEqual(host.sceneCommitCount, commits)
            XCTAssertEqual(host.rasterCount, rasters)

            // Moving a layer commits a new scene but keeps every raster.
            CATransaction.begin(); CATransaction.setDisableActions(true)
            child.position = CGPoint(x: 10, y: 10)
            CATransaction.commit()
            w.displayIfNeeded()
            XCTAssertEqual(host.sceneCommitCount, commits + 1)
            XCTAssertEqual(host.rasterCount, rasters)
            let moved = host.hostedScene!.nodes.first { $0.size == CGSize(width: 60, height: 60) && $0.parent != nil }!
            XCTAssertEqual(moved.transform.tx, 10 - 30, accuracy: 0.001)

            // Changing content re-rasterises that one node.
            CATransaction.begin(); CATransaction.setDisableActions(true)
            panel.backgroundColor = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
            CATransaction.commit()
            w.displayIfNeeded()
            XCTAssertEqual(host.rasterCount, rasters + 1)

            // A view invalidation re-rasterises the view's node only.
            w.contentView!.subviews[0].needsDisplay = true
            w.displayIfNeeded()
            XCTAssertEqual(host.rasterCount, rasters + 2)
            w.close()
        }
    }

    func testAnimationsCommitPresentationValues() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 100
            let savedNow = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = savedNow }
            let (w, _, child) = makeWindow()
            let host = hostWindow(w)
            host.layerHostingEnabled = true
            w._updateLayerHosting()
            w.display()
            let rasters = host.rasterCount

            let a = CABasicAnimation(keyPath: "position")
            a.fromValue = CGPoint(x: 30, y: 30)
            a.toValue = CGPoint(x: 70, y: 30)
            a.duration = 1
            child.add(a, forKey: "slide")
            clock = 100.5
            CARuntime.tick()
            w.displayIfNeeded()
            let node = host.hostedScene!.nodes.first { $0.size == CGSize(width: 60, height: 60) && $0.parent != nil }!
            XCTAssertEqual(node.transform.tx, 50 - 30, accuracy: 0.5, "halfway through the slide")
            XCTAssertEqual(host.rasterCount, rasters, "a position animation never re-rasterises")

            // A colour animation does redraw each frame.
            let c = CABasicAnimation(keyPath: "backgroundColor")
            c.fromValue = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
            c.toValue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
            c.duration = 1
            child.add(c, forKey: "tint")
            clock = 100.6
            CARuntime.tick(); w.displayIfNeeded()
            let afterOne = host.rasterCount
            XCTAssertGreaterThan(afterOne, rasters)
            clock = 100.7
            CARuntime.tick(); w.displayIfNeeded()
            XCTAssertGreaterThan(host.rasterCount, afterOne)
            w.close()
        }
    }

    func testLayerBackedScrollViewClipsItsDocument() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            let scroll = NSScrollView(frame: NSRect(x: 50, y: 50, width: 100, height: 100))
            scroll.hasVerticalScroller = false
            scroll.drawsBackground = false
            let doc = BoxView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
            scroll.documentView = doc
            w.contentView!.addSubview(scroll)
            w.contentView!.wantsLayer = true
            w.makeKeyAndOrderFront(nil)
            XCTAssertTrue(scroll.contentView.layer?.masksToBounds == true)
            for hosted in [false, true] {
                let host = hostWindow(w)
                host.layerHostingEnabled = hosted
                w._updateLayerHosting()
                w.display()
                let px = _pixels(host.lastImage!)
                let img = host.lastImage!
                func pixel(_ x: Int, _ y: Int) -> [UInt8] {      // y from the top, in pixels
                    let i = y * img.bytesPerRow + x * 4
                    return [px[i], px[i + 1], px[i + 2], px[i + 3]]
                }
                let s = Int(w.backingScaleFactor)
                // Inside the scroll view the document's box shows; outside it the window is white.
                XCTAssertNotEqual(pixel(60 * s, 60 * s), [255, 255, 255, 255], "hosted=\(hosted)")
                XCTAssertEqual(pixel(40 * s, 40 * s), [255, 255, 255, 255], "hosted=\(hosted): clipped outside the scroll view")
            }
            w.close()
        }
    }

    func testUnsupportedFeaturesFlattenTheirSubtree() {
        MainActor.assumeIsolated {
            let (w, panel, _) = makeWindow()
            let host = hostWindow(w)
            w.display()
            let software = _pixels(host.lastImage!)
            let mask = CALayer()
            mask.frame = CGRect(x: 0, y: 0, width: 40, height: 60)
            panel.mask = mask
            w.display()
            let softwareMasked = _pixels(host.lastImage!)
            XCTAssertNotEqual(software, softwareMasked)

            host.layerHostingEnabled = true
            w._updateLayerHosting()
            w.display()
            let scene = host.hostedScene!
            // content view, box, panel (flattened: no child or border node).
            XCTAssertEqual(scene.nodes.count, 3)
            _assertSimilar(_pixels(host.lastImage!), softwareMasked)

            // Hosting ends when the content view loses its layer tree (new content view).
            w.contentView = NSView(frame: .zero)
            XCTAssertFalse(w._hostsLayersNatively)
            XCTAssertNil(host.hostedScene)
            w.close()
        }
    }

    /// A shadow reaches outside the layer's bounds: the flattened node a host gets must
    /// cover it, placed so the layer itself stays where it was.
    func testShadowsSurviveFlattening() {
        MainActor.assumeIsolated {
            let (w, panel, _) = makeWindow()
            panel.masksToBounds = false
            panel.shadowColor = CGColor(gray: 0, alpha: 1)
            panel.shadowOpacity = 0.8
            panel.shadowRadius = 4
            panel.shadowOffset = CGSize(width: 0, height: -6)
            let host = hostWindow(w)
            w.display()
            let software = _pixels(host.lastImage!)
            host.layerHostingEnabled = true
            w._updateLayerHosting()
            w.display()
            let scene = host.hostedScene!
            let node = scene.nodes.first { $0.size.width > 80 && $0.size.height > 60 && $0.parent != nil }
            XCTAssertNotNil(node, "the panel's node grew to hold the shadow: \(scene.nodes.map(\.size))")
            // The blur's soft edge lands on different pixel grids in the two paths, so a few
            // percent of pixels differ by a shade; nothing is missing or displaced.
            _assertSimilar(_pixels(host.lastImage!), software, "hosted shadow matches the software one", strongShare: 40)
            w.close()
        }
    }
}

final class LayerAnimationLifetimeTests: XCTestCase, @unchecked Sendable {
    /// A repeating layer animation drives frames only while its window is on screen:
    /// closing (or ordering out) the window stops the frame requests, showing it resumes them.
    func testOffScreenAnimationsStopDrivingFrames() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 100
            let savedNow = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = savedNow }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            let v = NSView(frame: NSRect(x: 10, y: 10, width: 40, height: 40))
            v.wantsLayer = true
            w.contentView!.addSubview(v)
            w.makeKeyAndOrderFront(nil)
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.2; pulse.toValue = 1; pulse.duration = 0.5; pulse.repeatCount = .infinity
            v.layer!.add(pulse, forKey: "pulse")
            XCTAssertTrue(CARuntime.hasPendingWork)
            clock = 101; CARuntime.tick()
            XCTAssertTrue(CARuntime.hasPendingWork, "an infinite animation keeps requesting frames while visible")
            w.orderOut(nil)
            clock = 102; CARuntime.tick()
            XCTAssertFalse(CARuntime.hasPendingWork, "an ordered-out window's animations stop driving frames")
            XCTAssertNotNil(v.layer!.animation(forKey: "pulse"), "the animation itself is kept")
            w.makeKeyAndOrderFront(nil)
            XCTAssertTrue(CARuntime.hasPendingWork, "showing the window again resumes the frames")
            w.close()
            clock = 103; CARuntime.tick()
            XCTAssertFalse(CARuntime.hasPendingWork, "a closed window's animations stop driving frames")
        }
    }

    /// The HelloWindow badge: animations added to a layer before it joins its tree are
    /// gated by that tree's window too, and a tree nothing hosts drives no frames.
    func testAnimationsAddedBeforeAttachFollowTheTreeTheyJoin() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 200
            let savedNow = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = savedNow }
            let ring = CAShapeLayer()
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.6; pulse.toValue = 1.2; pulse.duration = 0.9; pulse.repeatCount = .infinity
            ring.add(pulse, forKey: "pulse")
            clock = 201; CARuntime.tick()
            XCTAssertFalse(CARuntime.hasPendingWork, "a layer nothing hosts does not request frames")
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            let v = NSView(frame: NSRect(x: 10, y: 10, width: 60, height: 40))
            v.wantsLayer = true
            w.contentView!.addSubview(v)
            w.makeKeyAndOrderFront(nil)
            v.layer!.addSublayer(ring)
            XCTAssertTrue(CARuntime.hasPendingWork, "joining a shown tree starts the frames")
            clock = 202; CARuntime.tick()
            XCTAssertTrue(CARuntime.hasPendingWork)
            w.close()
            clock = 203; CARuntime.tick()
            XCTAssertFalse(CARuntime.hasPendingWork, "closing the window stops them, although the animation predates the attach")
        }
    }
}
