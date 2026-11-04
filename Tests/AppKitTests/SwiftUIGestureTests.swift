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


final class SwiftUIGestureCardTests: XCTestCase, @unchecked Sendable {
    /// The HelloWindow Gestures tab: a card under offset/scale/rotation modifiers with a
    /// drag gesture that moves it. The translation must not shrink as the card moves.
    func testDraggingACardThatMovesWithTheDrag() {
        MainActor.assumeIsolated {
            final class Model { var offset = CGSize.zero; var start = CGSize.zero; var pressed = false; var presses = 0; var taps = 0 }
            let m = Model()
            struct Card: View {
                let m: Model
                @State private var tick = 0
                var body: some View {
                    VStack(spacing: 0) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15))
                            RoundedRectangle(cornerRadius: 10).fill(Color.blue)
                                .frame(width: 120, height: 80)
                                .scaleEffect(1)
                                .rotationEffect(.zero)
                                .offset(m.offset)
                                .gesture(DragGesture().onChanged { v in m.offset = CGSize(width: m.start.width + v.translation.width, height: m.start.height + v.translation.height); tick += 1 }
                                                      .onEnded { _ in m.start = m.offset })
                        }
                        .frame(width: 300, height: 150)
                        Text("Taps: \(m.taps)")
                            .padding(8)
                            .onTapGesture { m.taps += 1 }
                            .onLongPressGesture(minimumDuration: 0.6, perform: { m.presses += 1 }, onPressingChanged: { m.pressed = $0 })
                    }
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Card(m: m))
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            @MainActor func mouse(_ type: NSEvent.EventType, _ p: NSPoint, t: TimeInterval) {
                w.sendEvent(NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: t, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
                h.layoutSubtreeIfNeeded()
            }
            // The card is centred in the 300x150 stage at the top: window x 90...210, y 85...165.
            let c = NSPoint(x: 150, y: 125)
            mouse(.leftMouseDown, c, t: 0)
            for i in 1...10 { mouse(.leftMouseDragged, NSPoint(x: c.x + CGFloat(i) * 10, y: c.y), t: Double(i) * 0.02) }
            XCTAssertEqual(m.offset.width, 100, accuracy: 0.5, "the full 100-point drag reaches the card even though it moves under the pointer")
            XCTAssertEqual(m.offset.height, 0, accuracy: 0.5)
            mouse(.leftMouseUp, NSPoint(x: c.x + 100, y: c.y), t: 0.3)
            XCTAssertEqual(m.start.width, 100, accuracy: 0.5)
            // Tap and long press on the label below the stage (window y 0...50 band).
            let label = NSPoint(x: 150, y: 30)
            mouse(.leftMouseDown, label, t: 1); mouse(.leftMouseUp, label, t: 1.05)
            XCTAssertEqual(m.taps, 1)
            mouse(.leftMouseDown, label, t: 2)
            let press = (w.contentView!.subviews.flatMap { all($0) }).flatMap(\.gestureRecognizers).compactMap { $0 as? NSPressGestureRecognizer }.first
            XCTAssertNotNil(press)
            press?._pressTimerFired()
            XCTAssertEqual(m.pressed, true)
            XCTAssertEqual(m.presses, 1)
            mouse(.leftMouseUp, label, t: 2.8)
            XCTAssertEqual(m.pressed, false)
            XCTAssertEqual(m.taps, 1, "the release that ends a long press is not a tap")
            w.close()
        }
    }
    @MainActor private func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
}

final class SwiftUIGestureScaledCardTests: XCTestCase, @unchecked Sendable {
    /// The demo card scales with a magnification gesture while it is already under
    /// scale/rotation/offset effects driven by the same state.
    func testMagnifyingACardUnderEffects() {
        MainActor.assumeIsolated {
            final class Model { var scale: CGFloat = 1; var scaleStart: CGFloat = 1; var angle = Angle.zero; var offset = CGSize.zero }
            let m = Model()
            struct Card: View {
                let m: Model
                @State private var tick = 0
                var body: some View {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15))
                        RoundedRectangle(cornerRadius: 10).fill(Color.blue)
                            .frame(width: 120, height: 80)
                            .overlay(Text("x").foregroundColor(.white))
                            .scaleEffect(m.scale)
                            .rotationEffect(m.angle)
                            .offset(m.offset)
                            .gesture(DragGesture().onChanged { v in m.offset = v.translation; tick += 1 })
                            .simultaneousGesture(MagnificationGesture().onChanged { m.scale = min(3, max(0.3, m.scaleStart * $0)); tick += 1 }.onEnded { _ in m.scaleStart = m.scale })
                            .simultaneousGesture(RotationGesture().onChanged { m.angle = $0 })
                    }
                    .frame(width: 300, height: 200)
                }
            }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Card(m: m))
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            @MainActor func g(_ type: NSEvent.EventType, magnification: CGFloat = 0, phase: NSEvent.Phase = []) {
                w.sendEvent(NSEvent._gestureEvent(type: type, location: NSPoint(x: 150, y: 100), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, magnification: magnification, phase: phase))
                h.layoutSubtreeIfNeeded()
            }
            g(.beginGesture)
            g(.magnify, magnification: 0.1, phase: .changed)
            XCTAssertEqual(m.scale, 1.1, accuracy: 1e-6)
            g(.magnify, magnification: 0.1, phase: .changed)
            XCTAssertEqual(m.scale, 1.2, accuracy: 1e-6)
            g(.endGesture)
            XCTAssertEqual(m.scaleStart, 1.2, accuracy: 1e-6)
            g(.beginGesture)
            g(.magnify, magnification: -0.1, phase: .changed)
            XCTAssertEqual(m.scale, 1.2 * 0.9, accuracy: 1e-6)
            g(.endGesture)
            w.close()
        }
    }
}
