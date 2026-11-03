// 3D transforms in the layer scene: nodes with a 3D rotation or under a perspective
// sublayerTransform carry the full 4x4 (and its affine approximation); plain layers do not.

import XCTest
@testable import AppKit
@testable import QuartzCore

final class LayerScene3DTests: XCTestCase, @unchecked Sendable {
    func testSceneNodesCarryTheirFullMatrixOnlyWhenNeeded() {
        MainActor.assumeIsolated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            let root = CALayer()
            root.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
            root.position = CGPoint(x: 100, y: 100)     // the anchor (perspective centre) sits on the card
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / 500
            root.sublayerTransform = perspective
            let card = CALayer()
            card.bounds = CGRect(x: 0, y: 0, width: 100, height: 60)
            card.position = CGPoint(x: 100, y: 100)
            card.transform = CATransform3DMakeRotation(.pi / 4, 0, 1, 0)
            card.name = "card"
            root.addSublayer(card)
            let flat = CALayer()
            flat.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
            flat.name = "flat"
            root.addSublayer(flat)

            var scene = root._buildScene(parentFlipped: false, parentBounds: root.bounds, scale: 1, frame: 0)
            XCTAssertEqual(scene.nodes.count, 3, "a sublayerTransform no longer flattens the subtree")
            XCTAssertNil(scene.nodes[0].transform3D)
            let cardNode = scene.nodes.first { $0.name == "card" }!
            let m = try! XCTUnwrap(cardNode.transform3D)
            // The centre sits on the anchor: no perspective shift there.
            let centre = CGPoint(x: 50, y: 30).applying(m)
            XCTAssertEqual(centre.x, 100, accuracy: 1e-6)
            XCTAssertEqual(centre.y, 100, accuracy: 1e-6)
            // The left edge turns toward the viewer: closer than the affine approximation says.
            let affineLeft = CGPoint(x: 0, y: 30).applying(cardNode.transform)
            let left = CGPoint(x: 0, y: 30).applying(m)
            XCTAssertEqual(affineLeft.x, 100 - 50 * cos(CGFloat.pi / 4), accuracy: 1e-6)
            XCTAssertGreaterThan(abs(left.x - affineLeft.x), 1, "perspective moves the edge")
            XCTAssertEqual(left.y, 100, accuracy: 1e-6, "the edge moves along the line through the perspective centre")
            // A plain layer under the perspective still records the matrix, with its usual placement.
            let flatNode = scene.nodes.first { $0.name == "flat" }!
            XCTAssertNotNil(flatNode.transform3D)
            XCTAssertEqual(flatNode.transform.tx, 10)
            XCTAssertEqual(flatNode.transform.ty, 170)

            // Without perspective, only the rotated card is 3D; a z rotation stays affine.
            root.sublayerTransform = CATransform3DIdentity
            flat.transform = CATransform3DMakeRotation(0.3, 0, 0, 1)
            scene = root._buildScene(parentFlipped: false, parentBounds: root.bounds, scale: 1, frame: 0)
            XCTAssertNotNil(scene.nodes.first { $0.name == "card" }!.transform3D)
            XCTAssertNil(scene.nodes.first { $0.name == "flat" }!.transform3D)
        }
    }
}
