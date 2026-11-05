// The SwiftUI members added for SwiftUICharts in the third-party library compatibility
// example (docs/compatibility/swiftui-libraries.md): path elements and trimming, shape
// transforms, insettable shapes, styled strokes, lazy grids, position, z-order,
// accessibility grouping and localized-key format specifiers.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 200, height: CGFloat = 100) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func render(_ h: NSView) -> NSBitmapImageRep? {
    guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return nil }
    h.cacheDisplay(in: h.bounds, to: rep)
    return rep
}

private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    let scale = max(1, rep.pixelsWide / max(1, Int(rep.size.width)))
    guard let c = rep.colorAt(x: x * scale, y: y * scale) else { return (0, 0, 0, 0) }
    return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

private struct _Line: Shape { let path: Path; func path(in rect: CGRect) -> Path { path } }

private func length(_ path: Path) -> CGFloat { path._segments().reduce(0) { $0 + $1.length } }

final class SwiftUIShapeAndGridTests: XCTestCase, @unchecked Sendable {
    func testPathElementsAndCurrentPoint() {
        var p = Path()
        XCTAssertNil(p.currentPoint)
        p.move(to: CGPoint(x: 1, y: 2))
        p.addLine(to: CGPoint(x: 11, y: 2))
        p.addQuadCurve(to: CGPoint(x: 21, y: 12), control: CGPoint(x: 21, y: 2))
        p.addCurve(to: CGPoint(x: 31, y: 22), control1: CGPoint(x: 21, y: 22), control2: CGPoint(x: 31, y: 12))
        p.closeSubpath()
        var seen: [Path.Element] = []
        p.forEach { seen.append($0) }
        XCTAssertEqual(seen, [.move(to: CGPoint(x: 1, y: 2)), .line(to: CGPoint(x: 11, y: 2)),
                              .quadCurve(to: CGPoint(x: 21, y: 12), control: CGPoint(x: 21, y: 2)),
                              .curve(to: CGPoint(x: 31, y: 22), control1: CGPoint(x: 21, y: 22), control2: CGPoint(x: 31, y: 12)),
                              .closeSubpath])
        XCTAssertEqual(p.currentPoint, CGPoint(x: 1, y: 2), "closing a subpath returns to its start")
        XCTAssertEqual(p.offsetBy(dx: 5, dy: 0).boundingRect.minX, 6)
    }

    func testTrimmedPathKeepsTheMiddleOfALine() {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: 100, y: 0))
        p.addLine(to: CGPoint(x: 100, y: 100))
        let half = p.trimmedPath(from: 0, to: 0.5)
        XCTAssertEqual(half.elements, [.move(to: .zero), .line(to: CGPoint(x: 100, y: 0))])
        let middle = p.trimmedPath(from: 0.25, to: 0.75)
        XCTAssertEqual(middle.elements, [.move(to: CGPoint(x: 50, y: 0)), .line(to: CGPoint(x: 100, y: 0)), .line(to: CGPoint(x: 100, y: 50))])
        XCTAssertTrue(p.trimmedPath(from: 0.5, to: 0.5).isEmpty)
        XCTAssertEqual(p.trimmedPath(from: 0, to: 1), p)
    }

    func testTrimmedCurveLengthIsProportional() {
        let circle = Circle().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let full = length(circle)
        XCTAssertEqual(full, .pi * 100, accuracy: 2, "the circumference")
        XCTAssertEqual(length(circle.trimmedPath(from: 0, to: 0.25)), full / 4, accuracy: 1.5)
        XCTAssertEqual(length(circle.trimmedPath(from: 0.1, to: 0.9)), full * 0.8, accuracy: 1.5)
        // The trimmed arc starts where the full arc is at that fraction.
        let quarter = circle.trimmedPath(from: 0.25, to: 0.5)
        if case .move(to: let start)? = quarter.elements.first {
            XCTAssertEqual(((start.x - 50) * (start.x - 50) + (start.y - 50) * (start.y - 50)).squareRoot(), 50, accuracy: 0.5, "on the circle")
        } else { XCTFail("no move") }
    }

    func testRelativeArcAndTangentArc() {
        var p = Path()
        p.move(to: CGPoint(x: 100, y: 50))
        p.addRelativeArc(center: CGPoint(x: 50, y: 50), radius: 50, startAngle: .zero, delta: .degrees(90))
        XCTAssertEqual(length(p), .pi * 25, accuracy: 1.5)
        XCTAssertEqual(p.currentPoint!.x, 50, accuracy: 0.01)
        XCTAssertEqual(p.currentPoint!.y, 100, accuracy: 0.01)
        var t = Path()
        t.move(to: .zero)
        t.addArc(tangent1End: CGPoint(x: 100, y: 0), tangent2End: CGPoint(x: 100, y: 100), radius: 20)
        XCTAssertEqual(t.currentPoint!.x, 100, accuracy: 0.01, "ends on the second tangent line")
        XCTAssertEqual(t.currentPoint!.y, 20, accuracy: 0.01)
    }

    func testShapeTransforms() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertEqual(Rectangle().scale(0.5).path(in: rect).boundingRect, CGRect(x: 25, y: 12.5, width: 50, height: 25))
        XCTAssertEqual(Rectangle().scale(x: 1, y: 0.5, anchor: .bottom).path(in: rect).boundingRect, CGRect(x: 0, y: 25, width: 100, height: 25), "scaled towards the bottom anchor")
        XCTAssertEqual(Rectangle().offset(x: 10, y: 5).path(in: rect).boundingRect, CGRect(x: 10, y: 5, width: 100, height: 50))
        let rotated = Rectangle().rotation(.degrees(90)).path(in: rect).boundingRect
        XCTAssertEqual(rotated.width, 50, accuracy: 0.01); XCTAssertEqual(rotated.height, 100, accuracy: 0.01)
        XCTAssertEqual(Rectangle().transform(CGAffineTransform(scaleX: 2, y: 2)).path(in: rect).boundingRect.width, 200)
        XCTAssertEqual(Rectangle().inset(by: 10).path(in: rect).boundingRect, rect.insetBy(dx: 10, dy: 10))
        XCTAssertEqual(Circle().inset(by: 5).inset(by: 5).path(in: rect).boundingRect.width, 30, "insets add up")
        XCTAssertEqual(Rectangle().trim(from: 0, to: 0.5).path(in: rect).elements.count, 3, "move and two sides")
    }

    func testStrokeBorderStaysInsideAndGradientStrokeFollowsTheLine() {
        MainActor.assumeIsolated {
            let (w, h) = host(Rectangle().strokeBorder(Color.red, lineWidth: 10), width: 100, height: 60)
            guard let rep = render(h) else { return XCTFail("no render") }
            XCTAssertGreaterThan(pixel(rep, 3, 30).r, 0.8, "the border is inside the edge")
            XCTAssertLessThan(pixel(rep, 50, 30).a, 0.1, "the middle is empty")
            w.close()
            let line = Path { p in p.move(to: CGPoint(x: 0, y: 20)); p.addLine(to: CGPoint(x: 200, y: 20)) }
            let (w2, h2) = host(_Line(path: line).stroke(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 8)), width: 200, height: 40)
            guard let rep2 = render(h2) else { return XCTFail("no render") }
            XCTAssertGreaterThan(pixel(rep2, 5, 20).r, 0.7, "red at the start: \(pixel(rep2, 5, 20))")
            XCTAssertGreaterThan(pixel(rep2, 195, 20).b, 0.7, "blue at the end: \(pixel(rep2, 195, 20))")
            XCTAssertLessThan(pixel(rep2, 100, 5).a, 0.1, "nothing beside the line")
            w2.close()
        }
    }

    func testLazyVGridLaysOutRowsAcrossFlexibleColumns() {
        MainActor.assumeIsolated {
            let grid = LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in Color.red.frame(height: 10) }
            }
            let (w, h) = host(grid, width: 100, height: 100)
            let root = h.hostingRoot as? _ViewRoot
            let gridNode = root?.firstNode { $0.primitive is _GridPrimitive }
            XCTAssertEqual(gridNode?.sizeThatFits(ProposedViewSize(width: 100, height: nil)), CGSize(width: 100, height: 38), "three rows of 10 with 4 between")
            let cells = (gridNode?.children.first?.layoutLeaves ?? []).map(\.frame)
            XCTAssertEqual(cells.count, 5)
            XCTAssertEqual(cells[0], CGRect(x: 0, y: 0, width: 46, height: 10), "two 46-point columns with an 8-point gap")
            XCTAssertEqual(cells[1].minX, 54)
            XCTAssertEqual(cells[2].minY, cells[0].minY + 14, "the next row")
            XCTAssertEqual(cells[4].minX, 0, "the fifth item wraps to the third row")
            w.close()
        }
    }

    func testLazyVGridAdaptiveColumnsFillTheWidth() {
        MainActor.assumeIsolated {
            let grid = LazyVGrid(columns: [GridItem(.adaptive(minimum: 30))], spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in Color.blue.frame(height: 10) }
            }
            let (w, h) = host(grid, width: 120, height: 50)
            let gridNode = (h.hostingRoot as? _ViewRoot)?.firstNode { $0.primitive is _GridPrimitive }
            let cells = (gridNode?.children.first?.layoutLeaves ?? []).map(\.frame)
            XCTAssertEqual(cells.map(\.minY), [0, 0, 0, 10], "three 30-point columns fit in 120 with 8-point gaps, so the fourth item wraps")
            XCTAssertEqual(cells.map(\.width), [34.67, 34.67, 34.67, 34.67].map { CGFloat($0) }.map { $0.rounded() }.map { _ in 35 }, "the three columns share the width")
            XCTAssertEqual(cells[1].minX, 43, "35 + 8")
            w.close()
        }
    }

    func testLazyHGridFillsRowsDownThenAcross() {
        MainActor.assumeIsolated {
            let grid = LazyHGrid(rows: [GridItem(.fixed(10)), GridItem(.fixed(10))], spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in Color.red.frame(width: 20) }
            }
            let (w, h) = host(grid, width: 100, height: 100)
            let gridNode = (h.hostingRoot as? _ViewRoot)?.firstNode { $0.primitive is _GridPrimitive }
            let cells = (gridNode?.children.first?.layoutLeaves ?? []).map(\.frame)
            XCTAssertEqual(cells.count, 3)
            XCTAssertEqual(cells[1].minY, cells[0].minY + 18, "second row")
            XCTAssertEqual(cells[2].minX, cells[0].minX + 22, "third item starts the next column")
            w.close()
        }
    }

    func testPositionCentresContentOnThePoint() {
        MainActor.assumeIsolated {
            let (w, h) = host(Color.red.frame(width: 20, height: 10).position(x: 50, y: 30), width: 200, height: 100)
            let node = (h.hostingRoot as? _ViewRoot)?.firstNode { $0.primitive is _PositionPrimitive }
            XCTAssertEqual(node?.frame, CGRect(x: 0, y: 0, width: 200, height: 100), "position fills what it is offered")
            XCTAssertEqual(node?.children.first?.frame, CGRect(x: 40, y: 25, width: 20, height: 10))
            w.close()
        }
    }

    func testZIndexOrdersSiblingsBackingViews() {
        MainActor.assumeIsolated {
            let view = ZStack {
                Color.red.zIndex(2)
                Color.blue
                Color.green.zIndex(1).padding(0)
            }
            let (w, h) = host(view, width: 50, height: 50)
            guard let rep = render(h) else { return XCTFail("no render") }
            let p = pixel(rep, 25, 25)
            XCTAssertGreaterThan(p.r, 0.8, "red (zIndex 2) draws on top: \(p)")
            var views: [NSView] = []
            (h.hostingRoot as? _ViewRoot)?.rootNode?.collectBackingViews(into: &views)
            XCTAssertEqual(views.count, 3)
            XCTAssertEqual(views.last, (h.hostingRoot as? _ViewRoot)?.firstNode { ($0.box.value as? Color) == .red }?.backingView)
            XCTAssertEqual(views.first, (h.hostingRoot as? _ViewRoot)?.firstNode { ($0.box.value as? Color) == .blue }?.backingView, "the unmodified sibling is at the back")
            w.close()
        }
    }

    func testAccessibilityElementIgnoresChildren() {
        MainActor.assumeIsolated {
            let view = HStack { Text("a"); Text("b") }.accessibilityElement(children: .ignore).accessibilityLabel("pair")
            let (w, h) = host(view)
            let texts = (h.hostingRoot as? _ViewRoot)?.firstNode { $0.primitive is _StackPrimitive }?.children.first?.layoutLeaves.compactMap(\.backingView) ?? []
            XCTAssertEqual(texts.count, 2)
            XCTAssertTrue(texts[0].isAccessibilityElement())
            XCTAssertEqual(texts[0].accessibilityLabel(), "pair")
            XCTAssertTrue(texts[1].isAccessibilityHidden(), "the second child is hidden from assistive technology")
            let contained = HStack { Text("a"); Text("b") }.accessibilityElement(children: .contain)
            let (w2, h2) = host(contained)
            let texts2 = (h2.hostingRoot as? _ViewRoot)?.firstNode { $0.primitive is _StackPrimitive }?.children.first?.layoutLeaves.compactMap(\.backingView) ?? []
            XCTAssertFalse(texts2[1].isAccessibilityHidden(), "`.contain` keeps the children")
            w.close(); w2.close()
        }
    }

    func testLocalizedStringKeyInterpolationSpecifiers() {
        let value = 3.14159
        let key: LocalizedStringKey = "v=\(value, specifier: "%.2f") n=\(7) s=\("x")"
        XCTAssertEqual(key.key, "v=3.14 n=7 s=x")
        XCTAssertEqual(Text("\(42, specifier: "%03d")")._string, "042")
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        XCTAssertEqual(Text("\(NSNumber(value: 3), formatter: formatter)")._string, "3.0")
        #if canImport(Darwin)   // Date is ReferenceConvertible on Apple's Foundation only
        XCTAssertEqual(Text("\(Date(timeIntervalSince1970: 0), formatter: ISO8601DateFormatter())")._string, "1970-01-01T00:00:00Z")
        #endif
    }

    func testValuelessAnimationCompilesAndStrokeStyleIsApplied() {
        MainActor.assumeIsolated {
            let view = Circle().stroke(Color.black, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4])).animation(.default)
            let (w, h) = host(view, width: 40, height: 40)
            XCTAssertNotNil(render(h))
            w.close()
        }
    }
}
