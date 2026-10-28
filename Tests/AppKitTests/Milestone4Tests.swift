// Milestone 4: QuartzCore — the layer tree, animations and layer-backed views.

import XCTest
@testable import AppKit

final class LayerGeometryTests: XCTestCase, @unchecked Sendable {
    func testFrameFollowsPositionAnchorAndBounds() {
        MainActor.assumeIsolated {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
            l.position = CGPoint(x: 60, y: 40)
            XCTAssertEqual(l.frame, CGRect(x: 10, y: 15, width: 100, height: 50))
            l.anchorPoint = .zero
            XCTAssertEqual(l.frame, CGRect(x: 60, y: 40, width: 100, height: 50))
            l.frame = CGRect(x: 5, y: 6, width: 20, height: 30)
            XCTAssertEqual(l.position, CGPoint(x: 5, y: 6))
            XCTAssertEqual(l.bounds.size, CGSize(width: 20, height: 30))
        }
    }

    func testConvertBetweenLayersHonoursFlippedGeometry() {
        MainActor.assumeIsolated {
            let root = CALayer()
            root.anchorPoint = .zero
            root.bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
            let child = CALayer()
            child.anchorPoint = .zero
            child.frame = CGRect(x: 10, y: 20, width: 50, height: 40)
            root.addSublayer(child)
            XCTAssertEqual(child.convert(CGPoint(x: 0, y: 0), to: root), CGPoint(x: 10, y: 20))
            XCTAssertEqual(root.convert(CGPoint(x: 35, y: 50), to: child), CGPoint(x: 25, y: 30))
            // Flipped child: its own y runs downward within the same frame.
            child.isGeometryFlipped = true
            XCTAssertEqual(child.convert(CGPoint(x: 0, y: 0), to: root), CGPoint(x: 10, y: 60))
            XCTAssertEqual(child.convert(CGPoint(x: 0, y: 40), to: root), CGPoint(x: 10, y: 20))
            XCTAssertEqual(root.convert(CGPoint(x: 10, y: 60), to: child), CGPoint(x: 0, y: 0))
            // Transformed child: scale about the centre.
            child.isGeometryFlipped = false
            child.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            child.frame = CGRect(x: 10, y: 20, width: 50, height: 40)
            child.transform = CATransform3DMakeScale(2, 2, 1)
            XCTAssertEqual(child.frame, CGRect(x: -15, y: 0, width: 100, height: 80))
            XCTAssertEqual(child.convert(CGPoint(x: 0, y: 0), to: root), CGPoint(x: -15, y: 0))
            XCTAssertTrue(root.hitTest(CGPoint(x: 0, y: 10)) === child)
            XCTAssertTrue(root.hitTest(CGPoint(x: 150, y: 90)) === root)
            XCTAssertNil(root.hitTest(CGPoint(x: 250, y: 90)))
        }
    }

    func testTransform3DAlgebra() {
        MainActor.assumeIsolated {
            let t = CATransform3DMakeTranslation(10, 20, 0)
            let s = CATransform3DMakeScale(2, 3, 1)
            let ts = CATransform3DConcat(t, s)   // translate then scale
            let p = CGPoint(x: 1, y: 1).applying(ts)
            XCTAssertEqual(p, CGPoint(x: 22, y: 63))
            let inv = CATransform3DInvert(ts)
            let back = p.applying(inv)
            XCTAssertEqual(back.x, 1, accuracy: 1e-9); XCTAssertEqual(back.y, 1, accuracy: 1e-9)
            let r = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)
            let q = CGPoint(x: 1, y: 0).applying(r)
            XCTAssertEqual(q.x, 0, accuracy: 1e-9); XCTAssertEqual(q.y, 1, accuracy: 1e-9)
            XCTAssertTrue(ts.isAffine)
            XCTAssertEqual(ts.affineTransform.tx, 20)
            XCTAssertEqual(CATransform3DIdentity, CATransform3D.identity)
        }
    }

    func testSublayerOrderingAndAutoresizing() {
        MainActor.assumeIsolated {
            let root = CALayer()
            root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
            let a = CALayer(), b = CALayer(), c = CALayer()
            a.name = "a"; b.name = "b"; c.name = "c"
            root.addSublayer(a)
            root.insertSublayer(b, below: a)
            root.insertSublayer(c, above: a)
            XCTAssertEqual(root.sublayers?.map(\.name), ["b", "a", "c"])
            root.replaceSublayer(a, with: CALayer())
            XCTAssertNil(a.superlayer)
            c.removeFromSuperlayer()
            XCTAssertEqual(root.sublayers?.count, 2)
            let stretch = CALayer()
            stretch.anchorPoint = .zero
            stretch.frame = CGRect(x: 10, y: 10, width: 80, height: 80)
            stretch.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            root.addSublayer(stretch)
            root.bounds = CGRect(x: 0, y: 0, width: 200, height: 150)
            XCTAssertEqual(stretch.frame, CGRect(x: 10, y: 10, width: 180, height: 130))
        }
    }
}

final class LayerAnimationTests: XCTestCase, @unchecked Sendable {
    nonisolated(unsafe) static var clock: CFTimeInterval = 100
    var clock: CFTimeInterval {
        get { LayerAnimationTests.clock }
        set { LayerAnimationTests.clock = newValue }
    }

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            LayerAnimationTests.clock = 100
            CARuntime.now = { LayerAnimationTests.clock }
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated { CARuntime.now = { ProcessInfo.processInfo.systemUptime } }
        super.tearDown()
    }

    func testExplicitBasicAnimationInterpolatesPresentation() {
        MainActor.assumeIsolated {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
            l.opacity = 1
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0
            a.toValue = 0.0
            a.duration = 2
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            l.add(a, forKey: "fade")
            XCTAssertEqual(l.animationKeys(), ["fade"])
            XCTAssertEqual(l.opacity, 1)   // model unchanged
            clock = 101
            XCTAssertEqual(l.presentation()!.opacity, 0.5, accuracy: 0.001)
            clock = 101.5
            XCTAssertEqual(l.presentation()!.opacity, 0.25, accuracy: 0.001)
            clock = 103
            _ = l._advanceAnimations(now: clock)
            XCTAssertNil(l.animationKeys())   // removed on completion
            XCTAssertEqual(l.presentation()!.opacity, 1)
        }
    }

    func testImplicitAnimationStartsFromPresentationValue() {
        MainActor.assumeIsolated {
            let host = TestHost()
            let root = CALayer()
            root.host = host
            root.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
            let l = CALayer()
            l.position = CGPoint(x: 0, y: 0)
            root.addSublayer(l)
            // No presentation yet: the change applies at once without animating.
            l.position = CGPoint(x: 10, y: 0)
            XCTAssertNil(l.animationKeys())
            // After a render pass, property changes animate implicitly.
            let ctx = makeContext()
            root.render(in: ctx)
            l.position = CGPoint(x: 50, y: 0)
            XCTAssertEqual(l.animationKeys(), ["position"])
            clock = 100.125   // half of the 0.25 s default
            let p = l.presentation()!.position.x
            XCTAssertGreaterThan(p, 10); XCTAssertLessThan(p, 50)
            // Disabled actions: no animation.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            l.opacity = 0.5
            CATransaction.commit()
            XCTAssertEqual(l.animationKeys(), ["position"])
            XCTAssertGreaterThan(host.invalidations, 0)
        }
    }

    func testTransactionCompletionWaitsForAnimations() {
        MainActor.assumeIsolated {
            let root = CALayer()
            root.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
            root.render(in: makeContext())
            var completed = false
            CATransaction.begin()
            CATransaction.setAnimationDuration(1)
            CATransaction.setCompletionBlock { completed = true }
            root.opacity = 0
            CATransaction.commit()
            XCTAssertFalse(completed)
            clock = 100.5
            XCTAssertFalse(root._advanceAnimations(now: clock) == false)
            clock = 101.1
            _ = root._advanceAnimations(now: clock)
            XCTAssertTrue(completed)
        }
    }

    func testKeyframeGroupAndSpring() {
        MainActor.assumeIsolated {
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
            let k = CAKeyframeAnimation(keyPath: "position.x")
            k.values = [0, 10, 30]
            k.keyTimes = [0, 0.5, 1]
            k.duration = 1
            k.timingFunction = CAMediaTimingFunction(name: .linear)
            let s = CABasicAnimation(keyPath: "transform.scale")
            s.fromValue = 1; s.toValue = 3; s.duration = 1
            s.timingFunction = CAMediaTimingFunction(name: .linear)
            let g = CAAnimationGroup()
            g.animations = [k, s]
            g.duration = 1
            l.add(g, forKey: "group")
            clock = 100.25
            let p = l.presentation()!
            XCTAssertEqual(p.position.x, 5, accuracy: 0.01)
            XCTAssertEqual(p.transform.m11, 1.5, accuracy: 0.01)
            clock = 100.75
            XCTAssertEqual(l.presentation()!.position.x, 20, accuracy: 0.01)

            let spring = CASpringAnimation(keyPath: "position.y")
            spring.fromValue = 0; spring.toValue = 100
            spring.damping = 100; spring.stiffness = 100; spring.mass = 1   // overdamped: monotonic
            l.removeAllAnimations()
            clock = 101
            l.add(spring, forKey: "spring")
            clock = 101.5
            let y1 = l.presentation()!.position.y
            clock = 102.5
            let y2 = l.presentation()!.position.y
            XCTAssertGreaterThan(y1, 0); XCTAssertGreaterThan(y2, y1); XCTAssertLessThanOrEqual(y2, 100.0001)
        }
    }

    func testRuntimeTickDrivesDisplayLinksAndRedraws() {
        MainActor.assumeIsolated {
            var frames = 0
            var requested = 0
            CARuntime.frameRequester = { requested += 1 }
            defer { CARuntime.frameRequester = nil }
            let link = CADisplayLink { _ in frames += 1 }
            link.add(to: .main, forMode: .default)
            XCTAssertEqual(requested, 1)
            clock = 100.016
            CARuntime.tick()
            XCTAssertEqual(frames, 1)
            XCTAssertEqual(link.timestamp, 100.016, accuracy: 1e-9)
            XCTAssertEqual(requested, 2)   // still running: another frame requested
            link.isPaused = true
            link.invalidate()
            CARuntime.tick()
            XCTAssertEqual(frames, 1)

            let host = TestHost()
            let root = CALayer()
            root.host = host
            root.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0; a.toValue = 1; a.duration = 1
            root.add(a, forKey: nil)
            let before = host.invalidations
            clock = 100.5
            CARuntime.tick()
            XCTAssertGreaterThan(host.invalidations, before)
            XCTAssertTrue(CARuntime.hasPendingWork)
            clock = 102
            CARuntime.tick()
            XCTAssertFalse(CARuntime.hasPendingWork)
        }
    }

    @MainActor private func makeContext() -> CGContext {
        CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    }
}

@MainActor
final class TestHost: CALayerHost {
    var invalidations = 0
    func layerNeedsDisplay(_ root: CALayer, in rect: CGRect?) { invalidations += 1 }
}

final class LayerBackedViewTests: XCTestCase, @unchecked Sendable {
    final class SquareView: NSView {
        var drawCount = 0
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            drawCount += 1
            NSColor.red.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 20)).fill()   // top-left in a flipped view
        }
    }

    @MainActor private func pixel(_ w: NSWindow, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
        let image = platform!.lastImage!
        let data = _pixels(image)
        let row = image.height - 1 - y * 2
        let i = row * image.bytesPerRow + x * 2 * 4
        return (data[i + 2], data[i + 1], data[i])
    }

    func testLayerBackedViewsCompositeThroughTheLayerTree() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let container = NSView(frame: NSRect(x: 10, y: 10, width: 80, height: 80))
            container.wantsLayer = true
            container.layer!.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
            let square = SquareView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
            container.addSubview(square)
            XCTAssertNotNil(square.layer, "subviews of a layer-backed view become layer-backed")
            XCTAssertTrue(square.layer!.superlayer === container.layer)
            XCTAssertTrue(square.layer!.isGeometryFlipped)
            XCTAssertEqual(square.layer!.frame, NSRect(x: 0, y: 0, width: 40, height: 40))
            // A plain sublayer added by the app.
            let dot = CALayer()
            dot.anchorPoint = .zero
            dot.frame = CGRect(x: 60, y: 60, width: 10, height: 10)
            dot.backgroundColor = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
            dot.cornerRadius = 5
            container.layer!.addSublayer(dot)
            w.contentView!.addSubview(container)
            w.makeKeyAndOrderFront(nil)
            w.display()
            let firstDraws = square.drawCount
            XCTAssertGreaterThan(firstDraws, 0)
            // Container background (blue) at a point not covered by the square: window (85, 85).
            let blue = pixel(w, 85, 85)
            XCTAssertGreaterThan(blue.b, 200); XCTAssertLessThan(blue.r, 30)
            // The square draws red at its top-left (flipped): view (5, 5) from the top = window y 10+40-5 = 45.
            let red = pixel(w, 15, 45)
            XCTAssertGreaterThan(red.r, 200); XCTAssertLessThan(red.b, 30)
            // Below the red block inside the square: still the container blue (square has no background).
            let under = pixel(w, 15, 15)
            XCTAssertGreaterThan(under.b, 200)
            // The green dot at container (65, 65) -> window (75, 75).
            let green = pixel(w, 75, 75)
            XCTAssertGreaterThan(green.g, 200); XCTAssertLessThan(green.r, 30)

            // Moving the view moves its layer; invalidation redraws.
            square.frame = NSRect(x: 40, y: 0, width: 40, height: 40)
            XCTAssertEqual(square.layer!.position, CGPoint(x: 40, y: 0))
            w.display()
            XCTAssertGreaterThan(square.drawCount, firstDraws)
            let moved = pixel(w, 55, 45)
            XCTAssertGreaterThan(moved.r, 200)
            let vacated = pixel(w, 15, 45)
            XCTAssertGreaterThan(vacated.b, 200)
            square.removeFromSuperview()
            XCTAssertNil(square.layer!.superlayer)
            XCTAssertTrue(square.layer!.host === square)
            w.close()
        }
    }

    func testAnimatorAnimatesLayerBackedGeometry() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 10
            CARuntime.now = { clock }
            defer { CARuntime.now = { ProcessInfo.processInfo.systemUptime } }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
            v.wantsLayer = true
            w.contentView!.addSubview(v)
            w.makeKeyAndOrderFront(nil)
            w.display()
            var done = false
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 1
                v.animator().frame = NSRect(x: 50, y: 0, width: 20, height: 20)
                v.animator().alphaValue = 0.5
            }, completionHandler: { done = true })
            XCTAssertEqual(v.frame.origin.x, 50)            // model is final at once
            XCTAssertEqual(v.alphaValue, 0.5)
            XCTAssertNotNil(v.layer!.animation(forKey: "position"))
            XCTAssertNotNil(v.layer!.animation(forKey: "opacity"))
            clock = 10.5
            let p = v.layer!.presentation()!
            XCTAssertGreaterThan(p.position.x, 0); XCTAssertLessThan(p.position.x, 50)
            XCTAssertFalse(done)
            clock = 11.5
            CARuntime.tick()
            XCTAssertTrue(done)
            XCTAssertNil(v.layer!.animationKeys())
            // Implicit layer animations stay off for backing layers.
            v.layer!.opacity = 1
            XCTAssertNil(v.layer!.animationKeys())
            w.close()
        }
    }

    func testShapeGradientAndTextLayersRender() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            v.wantsLayer = true
            let shape = CAShapeLayer()
            shape.path = CGPath(rect: CGRect(x: 10, y: 10, width: 30, height: 30), transform: nil)
            shape.fillColor = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
            shape.strokeColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
            shape.lineWidth = 4
            v.layer!.addSublayer(shape)
            let gradient = CAGradientLayer()
            gradient.anchorPoint = .zero
            gradient.frame = CGRect(x: 50, y: 0, width: 50, height: 100)
            gradient.colors = [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            v.layer!.addSublayer(gradient)
            let text = CATextLayer()
            text.anchorPoint = .zero
            text.frame = CGRect(x: 0, y: 60, width: 50, height: 30)
            text.string = "Hi"
            text.fontSize = 20
            text.foregroundColor = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
            v.layer!.addSublayer(text)
            w.contentView!.addSubview(v)
            w.makeKeyAndOrderFront(nil)
            w.display()
            let fill = pixel(w, 25, 25)
            XCTAssertGreaterThan(fill.g, 200); XCTAssertLessThan(fill.r, 30)
            let edge = pixel(w, 10, 25)
            XCTAssertGreaterThan(edge.r, 200)
            let dark = pixel(w, 52, 50), light = pixel(w, 97, 50)
            XCTAssertLessThan(dark.r, 60); XCTAssertGreaterThan(light.r, 200)
            // Some blue text pixel exists in the text layer's area.
            var sawBlue = false
            for x in stride(from: 0, to: 50, by: 1) {
                for y in stride(from: 60, to: 90, by: 1) {
                    let p = pixel(w, x, y)
                    if p.b > 150 && p.r < 100 { sawBlue = true }
                }
            }
            XCTAssertTrue(sawBlue)
            w.close()
        }
    }
}
