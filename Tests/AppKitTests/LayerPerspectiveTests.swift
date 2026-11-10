// 3D layer transforms with perspective in the software compositor: a layer rotated about Y
// under a perspective sublayerTransform projects to the analytically expected quad, the
// host backend's reference compositor (the scene path DirectComposition also consumes)
// and the software compositor agree, hit-testing inverts the projection, and a
// single-sided layer showing its back is culled.

import XCTest
@testable import AppKit
@testable import QuartzCore

final class LayerPerspectiveTests: XCTestCase, @unchecked Sendable {
    @MainActor private func hostWindow(_ w: NSWindow) -> HostWindow {
        Mirror(reflecting: w).descendant("_platform") as! HostWindow
    }

    /// Distance of the eye for the perspective, and the card: 100 x 60 points, rotated
    /// 45° about Y, centred on the perspective centre (the host's anchor).
    private static let eye: CGFloat = 400
    private static let angle = CGFloat.pi / 4

    /// Where a card-local point (relative to the card's centre, in points) lands relative
    /// to the perspective centre: CATransform3DMakeRotation(θ, 0, 1, 0) takes (x, 0, 0) to
    /// (x cos θ, 0, -x sin θ); the perspective divides by w = 1 + z · m34 with m34 = -1/eye.
    private static func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let z = -x * sin(angle)
        let w = 1 - z / eye
        return CGPoint(x: x * cos(angle) / w, y: y / w)
    }

    /// A white window whose layer-backed content view hosts the perspective host and the card.
    @MainActor private func makeWindow() -> (NSWindow, host: CALayer, card: CALayer) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        w.backgroundColor = .white
        w.contentView!.wantsLayer = true
        let host = CALayer()
        host.frame = CGRect(x: 50, y: 50, width: 200, height: 100)     // centre (150, 100) in the window
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / Self.eye
        host.sublayerTransform = perspective
        let card = CALayer()
        card.bounds = CGRect(x: 0, y: 0, width: 100, height: 60)
        card.position = CGPoint(x: 100, y: 50)
        card.backgroundColor = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        card.transform = CATransform3DMakeRotation(Self.angle, 0, 1, 0)
        host.addSublayer(card)
        w.contentView!.layer!.addSublayer(host)
        w.makeKeyAndOrderFront(nil)
        return (w, host, card)
    }

    /// Red, white or neither at a window point (y up), on the 2x host display.
    @MainActor private func sample(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> String {
        let data = _pixels(image)
        let px = Int(x * 2), py = image.height - 1 - Int(y * 2)
        let i = py * image.bytesPerRow + px * 4
        let (b, g, r) = (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        if r > 200 && g < 60 && b < 60 { return "red" }
        if r > 240 && g > 240 && b > 240 { return "white" }
        return "other(\(r),\(g),\(b))"
    }

    func testCardCornersProjectToTheAnalyticPositions() {
        MainActor.assumeIsolated {
            let (w, host, card) = makeWindow()
            defer { w.close() }
            CATransaction.flush()
            // convert(_:to:) goes through the projection: the near (left) edge is wider and
            // taller than the affine approximation, the far (right) edge narrower and shorter.
            let centre = CGPoint(x: 100, y: 50)      // the perspective centre in host space
            for (local, expected) in [(CGPoint(x: 0, y: 0), Self.project(-50, -30)), (CGPoint(x: 100, y: 0), Self.project(50, -30)),
                                      (CGPoint(x: 100, y: 60), Self.project(50, 30)), (CGPoint(x: 0, y: 60), Self.project(-50, 30))] {
                let p = card.convert(local, to: host)
                XCTAssertEqual(p.x, centre.x + expected.x, accuracy: 1e-6, "\(local)")
                XCTAssertEqual(p.y, centre.y + expected.y, accuracy: 1e-6, "\(local)")
            }
            let affineLeft = -50 * cos(Self.angle)
            XCTAssertLessThan(Self.project(-50, 0).x, affineLeft - 3, "the near edge comes toward the viewer")
            XCTAssertLessThan(Self.project(50, 0).x, -affineLeft - 2.5, "the far edge recedes")
            XCTAssertGreaterThan(Self.project(-50, 30).y, 30, "the near edge is taller")
            XCTAssertLessThan(Self.project(50, 30).y, 30, "the far edge is shorter")
            // The scene (which the host compositor and DirectComposition consume) carries the same map.
            let scene = w.contentView!.layer!._buildScene(parentFlipped: false, parentBounds: w.contentView!.bounds, scale: 2, frame: 0)
            let node = scene.nodes.first { $0.transform3D != nil }!
            let plane = _CAHomography(node.transform3D!)
            XCTAssertFalse(plane.isAffine)
            let nearTop = plane.apply(CGPoint(x: 0, y: 0))!              // card-local y-down: top-left
            XCTAssertEqual(nearTop.x, 100 + Self.project(-50, 0).x, accuracy: 1e-6)
            XCTAssertEqual(nearTop.y, 50 - Self.project(-50, 30).y, accuracy: 1e-6)
        }
    }

    func testSoftwareAndHostedCompositesDrawThePerspectiveCard() {
        MainActor.assumeIsolated {
            let (w, _, _) = makeWindow()
            defer { w.close() }
            let host = hostWindow(w)
            let cx: CGFloat = 150, cy: CGFloat = 100         // the perspective centre in window points
            let near = Self.project(-50, 0).x, far = Self.project(50, 0).x
            let nearTop = Self.project(-50, 30).y, farTop = Self.project(50, 30).y
            let affineHalf = 50 * cos(Self.angle)
            var images: [CGImage] = []
            for hosted in [false, true] {
                host.layerHostingEnabled = hosted
                w._updateLayerHosting()
                XCTAssertEqual(w._hostsLayersNatively, hosted)
                w.display()
                let image = host.lastImage!
                images.append(image)
                let tag = hosted ? "hosted" : "software"
                XCTAssertEqual(sample(image, cx, cy), "red", tag)
                // Beyond the affine edge but inside the projected near edge: drawn.
                XCTAssertEqual(sample(image, cx + near + 1.5, cy), "red", "\(tag): near edge at \(near)")
                XCTAssertEqual(sample(image, cx - affineHalf - 1.5, cy + 4), "red", "\(tag): past the affine edge (\(-affineHalf))")
                XCTAssertEqual(sample(image, cx + near - 1.5, cy), "white", "\(tag): outside the near edge")
                // Inside the affine edge but beyond the projected far edge: not drawn.
                XCTAssertEqual(sample(image, cx + far - 1.5, cy), "red", "\(tag): far edge at \(far)")
                XCTAssertEqual(sample(image, cx + far + 1.5, cy), "white", "\(tag): beyond the far edge")
                XCTAssertEqual(sample(image, cx + affineHalf - 1.5, cy), "white", "\(tag): within the affine edge (\(affineHalf)) is empty")
                // The near edge is taller than the card, the far edge shorter.
                XCTAssertEqual(sample(image, cx + near + 3, cy + nearTop - 1.5), "red", "\(tag): near top at \(nearTop)")
                XCTAssertEqual(sample(image, cx + near + 3, cy + 31.5), "red", "\(tag): above the card's own height")
                XCTAssertEqual(sample(image, cx + far - 3, cy + farTop + 1.5), "white", "\(tag): far top at \(farTop)")
                XCTAssertEqual(sample(image, cx + far - 3, cy + farTop - 1.5), "red", "\(tag): far top at \(farTop)")
            }
            // The two paths agree: no more than a few anti-aliased edge pixels differ strongly.
            let a = _pixels(images[0]), b = _pixels(images[1])
            XCTAssertEqual(a.count, b.count)
            var far2 = 0
            for i in stride(from: 0, to: min(a.count, b.count), by: 4) where abs(Int(a[i + 2]) - Int(b[i + 2])) > 48 { far2 += 1 }
            XCTAssertLessThan(far2, 120, "\(far2) pixels differ strongly between the software and hosted composites")
        }
    }

    func testHitTestingInvertsTheProjection() {
        MainActor.assumeIsolated {
            let (w, host, card) = makeWindow()
            defer { w.close() }
            let root = w.contentView!.layer!
            let hx: CGFloat = 150, hy: CGFloat = 100     // the host's centre in root space
            let near = Self.project(-50, 0).x, far = Self.project(50, 0).x
            let affineHalf = 50 * cos(Self.angle)
            // Points in root space: hitTest takes the receiver's superlayer space.
            XCTAssertTrue(root.hitTest(CGPoint(x: hx, y: hy)) === card)
            XCTAssertTrue(root.hitTest(CGPoint(x: hx + near + 1, y: hy)) === card, "inside the projected near edge")
            XCTAssertTrue(root.hitTest(CGPoint(x: hx - affineHalf - 1, y: hy)) === card, "past the affine edge is still the card")
            XCTAssertTrue(root.hitTest(CGPoint(x: hx + near - 1, y: hy)) === host, "outside the near edge")
            XCTAssertTrue(root.hitTest(CGPoint(x: hx + far + 1, y: hy)) === host, "beyond the far edge, though inside the affine one")
            XCTAssertTrue(root.hitTest(CGPoint(x: hx + near + 3, y: hy + 31)) === card, "the near edge is taller than the card")
            XCTAssertTrue(root.hitTest(CGPoint(x: hx + far - 3, y: hy + 29)) === host, "the far edge is shorter")
            // convert(_:from:) is the inverse of convert(_:to:).
            let p = CGPoint(x: 12, y: 47)
            let back = card.convert(card.convert(p, to: root), from: root)
            XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
            // A view under the card: NSView hit-testing stays frame-based, as on macOS, so
            // the window's mouse dispatch is unchanged; apps hit-test layers through CALayer.
            let v = NSView(frame: NSRect(x: 100, y: 70, width: 100, height: 60))
            w.contentView!.addSubview(v)
            XCTAssertTrue(w.contentView!.hitTest(NSPoint(x: 150, y: 100)) === v)
        }
    }

    func testSingleSidedLayerShowingItsBackIsCulled() {
        MainActor.assumeIsolated {
            let (w, _, card) = makeWindow()
            defer { w.close() }
            let host = hostWindow(w)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.transform = CATransform3DMakeRotation(.pi * 0.75, 0, 1, 0)   // 135°: the back faces the viewer
            CATransaction.commit()
            for hosted in [false, true] {
                host.layerHostingEnabled = hosted
                w._updateLayerHosting()
                card.isDoubleSided = true
                card.setNeedsDisplay()
                w.contentView!.layer!.setNeedsDisplay()
                w.display()
                XCTAssertEqual(sample(host.lastImage!, 150, 100), "red", "hosted=\(hosted): a double-sided layer shows its back")
                XCTAssertNotNil(w.contentView!.layer!.hitTest(CGPoint(x: 150, y: 100)))
                card.isDoubleSided = false
                card.setNeedsDisplay()
                w.contentView!.layer!.setNeedsDisplay()
                w.display()
                XCTAssertEqual(sample(host.lastImage!, 150, 100), "white", "hosted=\(hosted): a single-sided layer's back is culled")
                XCTAssertFalse(w.contentView!.layer!.hitTest(CGPoint(x: 150, y: 100)) === card, "hosted=\(hosted): nor is it hit")
            }
        }
    }

    /// The projective draw itself: a unit-square image through a homography lands its
    /// corners where the map says, with the mesh seams closed.
    func testProjectiveMeshDrawCoversTheProjectedQuad() {
        MainActor.assumeIsolated {
            let src = _CAPixels.render(extent: CGRect(x: 0, y: 0, width: 80, height: 80), scale: (2, 2), yDown: true) { c in
                c.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
                c.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
            }!
            // A keystone: the top edge (y = 0) 80 wide from x = 20, the bottom edge (y = 80) halved, 20...60.
            var t = CATransform3DIdentity
            t.m24 = 1 / 80          // w = 1 + y / 80: 1 at the top, 2 at the bottom
            let h = _CAHomography(t).concatenating(CGAffineTransform(translationX: 20, y: 20))
            XCTAssertFalse(h.isAffine)
            XCTAssertEqual(h.apply(CGPoint(x: 80, y: 80))!.x, 60, accuracy: 1e-9)
            let ctx = _CAPixels.makeContext(width: 240, height: 240)!
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
            ctx.translateBy(x: 0, y: 240)
            ctx.scaleBy(x: 2, y: -2)               // user space: points, y-down
            _CAProjective.draw(src, extent: CGRect(x: 0, y: 0, width: 80, height: 80), yDown: true, through: h, into: ctx, alpha: 1)
            let image = ctx.makeImage()!
            let data = _pixels(image)
            func blue(_ x: CGFloat, _ y: CGFloat, fully: Bool = false) -> Bool {      // points, y-down
                let i = Int(y * 2) * image.bytesPerRow + Int(x * 2) * 4
                return data[i] > (fully ? 250 : 200) && data[i + 2] < (fully ? 5 : 60)
            }
            XCTAssertTrue(blue(21, 21)); XCTAssertTrue(blue(98, 21))                 // top corners at (20, 20)-(100, 20)
            XCTAssertTrue(blue(21, 59)); XCTAssertTrue(blue(58, 59))                 // bottom edge at y = 60, x in 20...60
            XCTAssertFalse(blue(62, 59)); XCTAssertFalse(blue(70, 59)); XCTAssertFalse(blue(18, 40))
            XCTAssertFalse(blue(60, 62)); XCTAssertFalse(blue(60, 18))
            // The midline (y = 40 → w = 1.5 → y' = 20 + 26.67, x' from 20 + 0 to 20 + 53.3): no seams.
            // Every interior pixel is fully covered: no seam between cells, in any direction.
            for x in stride(from: CGFloat(21), through: 72, by: 0.5) { XCTAssertTrue(blue(x, 46.5, fully: true), "seam at x=\(x)") }
            for y in stride(from: CGFloat(21), through: 59, by: 0.5) { XCTAssertTrue(blue(50, y, fully: true), "seam at y=\(y)") }
            for y in stride(from: CGFloat(22), through: 58, by: 0.5) { XCTAssertTrue(blue(30, y, fully: true), "seam at y=\(y)") }
        }
    }
}
