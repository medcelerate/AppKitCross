// SwiftUI gestures: `.gesture` installs AppKit recognizers on the hosted view; the
// gesture values follow the recognizers' state changes.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 300, height: CGFloat = 200) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func recognizers(_ v: NSView) -> [NSGestureRecognizer] { v.gestureRecognizers + v.subviews.flatMap(recognizers) }

final class SwiftUIGestureTests: XCTestCase, @unchecked Sendable {
    @MainActor private func mouse(_ w: NSWindow, _ type: NSEvent.EventType, _ p: NSPoint, t: TimeInterval = 0) {
        w.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: t, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
    }
    @MainActor private func gesture(_ w: NSWindow, _ type: NSEvent.EventType, _ p: NSPoint, magnification: CGFloat = 0, rotation: Float = 0, phase: NSEvent.Phase = []) {
        w.sendEvent(NSEvent._gestureEvent(type: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, magnification: magnification, rotation: rotation, phase: phase))
    }

    func testMagnifyAndRotateGesturesReportValues() {
        MainActor.assumeIsolated {
            final class Log { var scales: [CGFloat] = []; var endedScale: CGFloat = 0; var angles: [Double] = []; var newStyle: [CGFloat] = []; var anchors: [UnitPoint] = [] }
            let log = Log()
            struct Pad: View {
                let log: Log
                var body: some View {
                    Color.blue.frame(width: 200, height: 100)
                        .gesture(MagnificationGesture().onChanged { log.scales.append($0) }.onEnded { log.endedScale = $0 })
                        .simultaneousGesture(RotationGesture().onChanged { log.angles.append($0.degrees) })
                        .highPriorityGesture(MagnifyGesture().onChanged { log.newStyle.append($0.magnification); log.anchors.append($0.startAnchor) })
                }
            }
            let (w, h) = host(Pad(log: log))
            XCTAssertEqual(recognizers(h).count, 3)
            let p = NSPoint(x: 150, y: 125)      // the pad is centred in the host: x 50...250, y 50...150 (window space)
            gesture(w, .beginGesture, p)
            gesture(w, .magnify, p, magnification: 0.5, phase: .began)
            gesture(w, .magnify, p, magnification: 0.25, phase: .changed)
            gesture(w, .rotate, p, rotation: 30, phase: .began)
            gesture(w, .endGesture, p)
            XCTAssertEqual(log.scales, [1.5, 1.75])
            XCTAssertEqual(log.endedScale, 1.75)
            XCTAssertEqual(log.newStyle, [1.5, 1.75])
            XCTAssertEqual(log.angles.count, 1)
            XCTAssertEqual(log.angles[0], -30, accuracy: 1e-9, "SwiftUI's angle is clockwise-positive in its y-down space")
            XCTAssertEqual(log.anchors.first?.x ?? -1, 0.5, accuracy: 0.01)
            XCTAssertEqual(log.anchors.first?.y ?? -1, 0.25, accuracy: 0.01, "anchor in the pad's flipped space")
            w.close()
        }
    }

    func testDragTapAndLongPressGestures() {
        MainActor.assumeIsolated {
            final class Log { var drags: [CGSize] = []; var endedAt: CGPoint? = nil; var taps = 0; var presses = 0; var pressing: [Bool] = [] }
            let log = Log()
            struct Pad: View {
                let log: Log
                var body: some View {
                    VStack(spacing: 0) {
                        Color.red.frame(width: 200, height: 100)
                            .gesture(DragGesture(minimumDistance: 0).onChanged { log.drags.append($0.translation) }.onEnded { log.endedAt = $0.location })
                        Color.green.frame(width: 200, height: 50)
                            .gesture(TapGesture(count: 1).onEnded { log.taps += 1 })
                            .onLongPressGesture(minimumDuration: 0.2, perform: { log.presses += 1 }, onPressingChanged: { log.pressing.append($0) })
                    }
                }
            }
            let (w, h) = host(Pad(log: log))
            let all = recognizers(h)
            XCTAssertEqual(all.count, 3)
            // Drag across the red pad (window x 50...250, y 75...175): translation in the pad's y-down space.
            let start = NSPoint(x: 50, y: 150)
            mouse(w, .leftMouseDown, start)
            mouse(w, .leftMouseDragged, NSPoint(x: 60, y: 140), t: 0.01)
            mouse(w, .leftMouseDragged, NSPoint(x: 80, y: 130), t: 0.02)
            mouse(w, .leftMouseUp, NSPoint(x: 80, y: 130), t: 0.03)
            XCTAssertEqual(log.drags.last, CGSize(width: 30, height: 20))
            XCTAssertEqual(log.endedAt, CGPoint(x: 30, y: 45), "location in the pad's own flipped coordinates")
            // Tap on the green pad.
            let green = NSPoint(x: 100, y: 50)   // the green pad: window y 25...75
            mouse(w, .leftMouseDown, green); mouse(w, .leftMouseUp, green)
            XCTAssertEqual(log.taps, 1)
            // Long press: the press recognizer fires after the duration; the pressing callback follows.
            guard let press = all.compactMap({ $0 as? NSPressGestureRecognizer }).first else { XCTFail("no press recognizer"); w.close(); return }
            mouse(w, .leftMouseDown, green)
            press._pressTimerFired()
            XCTAssertEqual(log.presses, 1)
            mouse(w, .leftMouseUp, green)
            XCTAssertEqual(log.pressing, [true, false])
            w.close()
        }
    }
}

