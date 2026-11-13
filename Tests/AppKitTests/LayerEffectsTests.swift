// The software compositor's offscreen effects: blurred shadows, group opacity and alpha
// masks, checked pixel by pixel through CALayer.render(in:) on every platform.

import XCTest
@testable import AppKit
@testable import SwiftUI
import QuartzCore

final class LayerEffectsTests: XCTestCase, @unchecked Sendable {
    @MainActor private func render(_ layer: CALayer, size: Int = 100) -> (CGImage, Data) {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        layer.render(in: ctx)
        let image = ctx.makeImage()!
        return (image, _pixels(image))
    }

    /// BGRA at (x, y) with y up, as in the layer's unflipped bounds space.
    private func pixel(_ image: CGImage, _ data: Data, _ x: Int, _ y: Int) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
        let row = image.height - 1 - y
        let i = row * image.bytesPerRow + x * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    func testShadowIsBlurredAroundTheLayer() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            let box = CALayer()
            box.frame = CGRect(x: 30, y: 30, width: 40, height: 40)
            box.backgroundColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
            box.shadowColor = CGColor(gray: 0, alpha: 1)
            box.shadowOpacity = 1
            box.shadowOffset = .zero
            box.shadowRadius = 4
            root.addSublayer(box)
            let (image, data) = render(root)
            let centre = pixel(image, data, 50, 50)
            XCTAssertGreaterThan(centre.r, 240, "the box itself is red")
            let near = pixel(image, data, 27, 50)
            let farther = pixel(image, data, 23, 50)
            let far = pixel(image, data, 5, 50)
            XCTAssertGreaterThan(near.a, 40, "a dark shadow just outside the edge: \(near)")
            XCTAssertLessThan(near.r, 40, "the shadow is black, not red")
            XCTAssertGreaterThan(near.a, farther.a, "the shadow fades with distance: \(near.a) vs \(farther.a)")
            XCTAssertGreaterThan(farther.a, 0, "still some shadow 7 points out")
            XCTAssertEqual(far.a, 0, "nothing far away")
        }
    }

    func testShadowOffsetFollowsTheLayerOrientation() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            @MainActor func shadowAlpha(flipped: Bool) -> (above: UInt8, below: UInt8) {
                let root = CALayer()
                root.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
                root.isGeometryFlipped = flipped
                let box = CALayer()
                box.frame = CGRect(x: 30, y: 30, width: 40, height: 40)
                box.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
                box.shadowColor = CGColor(gray: 0, alpha: 1)
                box.shadowOpacity = 1
                box.shadowRadius = 1
                box.shadowOffset = CGSize(width: 0, height: -10)
                root.addSublayer(box)
                let (image, data) = render(root)
                // In an unflipped root the box sits at y 30..70 (y up); flipped, the same frame
                // sits at rows 30..70 from the top, i.e. y up 30..70 as well.
                return (pixel(image, data, 50, 75).a, pixel(image, data, 50, 25).a)
            }
            let unflipped = shadowAlpha(flipped: false)
            XCTAssertGreaterThan(unflipped.below, 200, "-10 is downwards in an unflipped layer")
            XCTAssertEqual(unflipped.above, 0)
            let flipped = shadowAlpha(flipped: true)
            XCTAssertGreaterThan(flipped.above, 200, "-10 is upwards in a flipped layer")
            XCTAssertEqual(flipped.below, 0)
        }
    }

    func testGroupOpacityCompositesTheSubtreeOnce() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            @MainActor func overlapAlpha(group: Bool) -> UInt8 {
                let root = CALayer()
                root.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
                let parent = CALayer()
                parent.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
                parent.opacity = 0.5
                parent.allowsGroupOpacity = group
                let a = CALayer(), b = CALayer()
                a.frame = CGRect(x: 0, y: 0, width: 60, height: 100)
                b.frame = CGRect(x: 40, y: 0, width: 60, height: 100)
                a.backgroundColor = CGColor(gray: 0, alpha: 1)
                b.backgroundColor = CGColor(gray: 0, alpha: 1)
                parent.addSublayer(a)
                parent.addSublayer(b)
                root.addSublayer(parent)
                let (image, data) = render(root)
                return pixel(image, data, 50, 50).a
            }
            XCTAssertEqual(Int(overlapAlpha(group: true)), 128, accuracy: 3, "with group opacity the overlap is 50% like the rest")
            XCTAssertEqual(Int(overlapAlpha(group: false)), 191, accuracy: 3, "without it each child is composited at 50%")
        }
    }

    func testAlphaMaskUsesTheMaskLayersPixels() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            let content = CALayer()
            content.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            content.backgroundColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
            // A mask with sublayers is not a plain clip: its rendered alpha applies.
            let mask = CALayer()
            mask.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            let solid = CALayer(), half = CALayer()
            solid.frame = CGRect(x: 0, y: 0, width: 40, height: 100)
            solid.backgroundColor = CGColor(gray: 0, alpha: 1)
            half.frame = CGRect(x: 40, y: 0, width: 30, height: 100)
            half.backgroundColor = CGColor(gray: 0, alpha: 0.5)
            mask.addSublayer(solid)
            mask.addSublayer(half)
            content.mask = mask
            root.addSublayer(content)
            let (image, data) = render(root)
            let shown = pixel(image, data, 20, 50)
            XCTAssertGreaterThan(shown.r, 240); XCTAssertEqual(shown.a, 255)
            let dimmed = pixel(image, data, 55, 50)
            XCTAssertEqual(Int(dimmed.a), 128, accuracy: 3, "half-transparent mask: \(dimmed)")
            XCTAssertEqual(Int(dimmed.r), 128, accuracy: 3, "premultiplied red at half alpha")
            let hidden = pixel(image, data, 85, 50)
            XCTAssertEqual(hidden.a, 0, "outside the mask's sublayers nothing shows")
        }
    }

    func testShapeMaskStillClips() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            let content = CALayer()
            content.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            content.backgroundColor = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
            let shape = CAShapeLayer()
            shape.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            shape.path = CGPath(ellipseIn: CGRect(x: 10, y: 10, width: 80, height: 80), transform: nil)
            content.mask = shape
            root.addSublayer(content)
            let (image, data) = render(root)
            XCTAssertGreaterThan(pixel(image, data, 50, 50).g, 240)
            XCTAssertEqual(pixel(image, data, 3, 3).a, 0, "the corner lies outside the ellipse")
        }
    }
}

final class SwiftUIShadowTests: XCTestCase, @unchecked Sendable {
    func testShadowModifierDrawsBeyondTheViewsBounds() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Probe: View {
                var body: some View {
                    Color.red.frame(width: 40, height: 40).shadow(color: .black, radius: 3, x: 0, y: 4)
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            w.backgroundColor = .white
            let h = NSHostingView(rootView: Probe())
            h.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as? HostWindow
            let image = platform!.lastImage!
            let data = _pixels(image)
            func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {   // window points, y up, 2x backing
                let row = image.height - 1 - y * 2
                let i = row * image.bytesPerRow + x * 2 * 4
                return (data[i + 2], data[i + 1], data[i])
            }
            // The square is centred (30...70). Below it (y positive is down in SwiftUI) the
            // shadow darkens the white background; above it nothing does.
            let centre = pixel(50, 50)
            XCTAssertGreaterThan(centre.r, 200); XCTAssertLessThan(centre.g, 100)   // the system red
            let below = pixel(50, 27)
            XCTAssertLessThan(below.r, 200, "shadow below the square: \(below)")
            XCTAssertEqual(Int(below.r), Int(below.g), accuracy: 2, "the shadow is grey, not red")
            let above = pixel(50, 76)
            XCTAssertGreaterThan(above.r, 250, "no shadow far above: \(above)")
            w.close()
        }
    }
}

