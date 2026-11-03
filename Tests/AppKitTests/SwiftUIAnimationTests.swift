// SwiftUI animations: timing curves, withAnimation/.animation transactions, animated
// layout, animatable modifiers and transitions, driven by a fake clock through CARuntime.

import XCTest
@testable import AppKit
@testable import SwiftUI
import QuartzCore

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
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

final class SwiftUIAnimationTests: XCTestCase, @unchecked Sendable {
    func testCurves() {
        XCTAssertEqual(Animation.linear(duration: 1).progress(at: 0.25), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Animation.easeInOut(duration: 1).progress(at: 0.5), 0.5, accuracy: 0.01)
        XCTAssertLessThan(Animation.easeIn(duration: 1).progress(at: 0.25), 0.25)
        XCTAssertGreaterThan(Animation.easeOut(duration: 1).progress(at: 0.25), 0.25)
        XCTAssertEqual(Animation.default.progress(at: 10), 1)
        XCTAssertEqual(Animation.default.delay(1).progress(at: 0.5), 0)
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.5)
        XCTAssertGreaterThan(spring.progress(at: 0.35), 1, "an under-damped spring overshoots")
        XCTAssertEqual(spring.progress(at: spring.totalDuration), 1, accuracy: 0.01)
        let rep = Animation.linear(duration: 1).repeatCount(2, autoreverses: true)
        XCTAssertEqual(rep.progress(at: 1.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(rep.totalDuration, 2)
    }

    struct Mover: View {
        @State var moved = false
        var body: some View {
            HStack(spacing: 0) {
                if moved { Spacer() }
                Color.red.frame(width: 50, height: 50).id("box")
                if !moved { Spacer() }
            }
            .frame(width: 300)
            .onTapGesture { withAnimation(.linear(duration: 1)) { moved.toggle() } }
        }
    }

    func testWithAnimationInterpolatesLayout() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 100
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let (w, h) = host(Mover(), width: 300, height: 100)
            let box = allViews(h).compactMap { $0 as? _ShapeDrawingView }.first!
            XCTAssertEqual(box.frame.minX, 0, accuracy: 0.5)
            let root = h.hostingRoot as! _ViewRoot
            let mover = root.firstNode { $0.viewType == Mover.self }!
            // Toggle inside withAnimation.
            withAnimation(.linear(duration: 1)) { (mover.box.value as! Mover).moved = true }
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(root.isAnimating)
            XCTAssertEqual(box.frame.minX, 0, accuracy: 0.5, "starts where it was")
            clock = 100.5
            CARuntime.tick()
            XCTAssertEqual(box.frame.minX, 125, accuracy: 1, "halfway at t = 0.5")
            clock = 101.1
            CARuntime.tick()
            XCTAssertEqual(box.frame.minX, 250, accuracy: 0.5)
            XCTAssertFalse(root.isAnimating)
            w.close()
        }
    }

    struct Fader: View {
        @State var dim = false
        var body: some View {
            Color.blue.frame(width: 40, height: 40).opacity(dim ? 0.2 : 1).offset(x: dim ? 100 : 0).scaleEffect(dim ? 0.5 : 1)
                .animation(.linear(duration: 2), value: dim)
        }
    }

    func testAnimationModifierDrivesProperties() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 50
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let (w, h) = host(Fader(), width: 200, height: 100)
            let containers = allViews(h).compactMap { $0 as? _ContainerView }
            XCTAssertEqual(containers.count, 3)
            let root = h.hostingRoot as! _ViewRoot
            let fader = root.firstNode { $0.viewType == Fader.self }!
            (fader.box.value as! Fader).dim = true     // no withAnimation: the .animation scope animates it
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(root.isAnimating)
            clock = 51
            CARuntime.tick()
            let opacityView = containers.first { $0.alphaValue < 0.99 }
            XCTAssertNotNil(opacityView)
            XCTAssertEqual(opacityView!.alphaValue, 0.6, accuracy: 0.05, "halfway between 1 and 0.2")
            // Wrappers nest outermost first: scaleEffect, offset, opacity.
            let offsetView = containers.first { ($0.layer?.affineTransform().tx ?? 0) > 1 && abs(($0.layer?.affineTransform().a ?? 1) - 1) < 1e-6 }
            XCTAssertNotNil(offsetView)
            XCTAssertEqual(offsetView!.layer!.affineTransform().tx, 50, accuracy: 2)
            let scaled = containers.first { ($0.layer?.affineTransform().a ?? 1) < 0.99 }
            XCTAssertEqual(scaled?.layer?.affineTransform().a ?? 0, 0.75, accuracy: 0.05)
            clock = 53
            CARuntime.tick()
            XCTAssertEqual(opacityView!.alphaValue, 0.2, accuracy: 0.01)
            XCTAssertEqual(offsetView!.layer!.affineTransform().tx, 100, accuracy: 0.5)
            XCTAssertFalse(root.isAnimating)
            w.close()
        }
    }

    struct Appearing: View {
        @State var shown = false
        var body: some View {
            VStack {
                if shown { Text("Hello").transition(.opacity) }
                Text("Base")
            }
        }
    }

    func testTransitionsOnInsertionAndRemoval() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 10
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let (w, h) = host(Appearing())
            let root = h.hostingRoot as! _ViewRoot
            let node = root.firstNode { $0.viewType == Appearing.self }!
            withAnimation(.linear(duration: 1)) { (node.box.value as! Appearing).shown = true }
            h.layoutSubtreeIfNeeded()
            let container = allViews(h).compactMap { $0 as? _ContainerView }.first!
            XCTAssertEqual(container.alphaValue, 0, accuracy: 0.01, "fades in from transparent")
            clock = 10.5
            CARuntime.tick()
            XCTAssertEqual(container.alphaValue, 0.5, accuracy: 0.05)
            clock = 11.1
            CARuntime.tick()
            XCTAssertEqual(container.alphaValue, 1, accuracy: 0.01)
            // Removal keeps the view until the fade-out ends.
            withAnimation(.linear(duration: 1)) { (node.box.value as! Appearing).shown = false }
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(allViews(h).contains(container), "still in the hierarchy while fading out")
            clock = 11.6
            CARuntime.tick()
            XCTAssertEqual(container.alphaValue, 0.5, accuracy: 0.05)
            clock = 12.2
            CARuntime.tick()
            XCTAssertFalse(allViews(h).contains(container), "gone after the transition")
            XCTAssertFalse(root.isAnimating)
            w.close()
        }
    }
}

// MARK: Native layer hosting (the Windows DirectComposition path, via the reference compositor)

final class SwiftUIHostedAnimationTests: XCTestCase, @unchecked Sendable {
    struct Fader: View {
        @State var dim = false
        var body: some View {
            VStack {
                Toggle("Enabled", isOn: Binding(get: { !dim }, set: { dim = !$0 }).animation(.linear(duration: 2)))
                Color.blue.frame(width: 40, height: 40).opacity(dim ? 0.2 : 1)
                if dim { Text("Disabled").transition(.move(edge: .leading).combined(with: .opacity)) }
            }
        }
    }

    func testOpacityAndTransitionReachTheHostedScene() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 50
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView!.wantsLayer = true
            let hostWindow = w._platformWindow as! HostWindow
            hostWindow.layerHostingEnabled = true
            w._updateLayerHosting()
            XCTAssertTrue(w._hostsLayersNatively)
            let h = NSHostingView(rootView: Fader())
            h.frame = NSRect(x: 0, y: 0, width: 200, height: 160)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            w.display()
            let before = hostWindow.sceneCommitCount
            allViews(h).compactMap { $0 as? NSButton }.first?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            let root = h.hostingRoot as! _ViewRoot
            XCTAssertTrue(root.isAnimating)
            clock = 51
            CARuntime.tick()
            w.displayIfNeeded()
            XCTAssertGreaterThan(hostWindow.sceneCommitCount, before, "an animation frame recommits the hosted scene")
            let faded = allViews(h).first { $0.alphaValue < 0.99 && $0.alphaValue > 0.01 }
            XCTAssertNotNil(faded, "the bar's view carries the interpolated alpha")
            let scene = hostWindow.hostedScene!
            let fadedNode = scene.nodes.first { abs(CGFloat($0.opacity) - (faded?.alphaValue ?? -1)) < 0.01 }
            XCTAssertNotNil(fadedNode, "the scene node carries the same opacity: \(scene.nodes.map(\.opacity))")
            clock = 53
            CARuntime.tick()
            w.displayIfNeeded()
            XCTAssertFalse(root.isAnimating)
            let texts = allViews(h).compactMap { $0 as? _TextView }.map { $0.storage.string }
            XCTAssertTrue(texts.contains("Disabled"))
            let disabled = allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string == "Disabled" }!
            // After the transition the text is fully present: visible in the scene at its final place.
            var v: NSView? = disabled
            while let view = v { XCTAssertEqual(view.alphaValue, 1, accuracy: 0.01, "\(type(of: view))"); v = view.superview }
            let s2 = hostWindow.hostedScene!
            XCTAssertTrue(s2.nodes.contains { $0.opacity < 0.21 && $0.opacity > 0.19 }, "the bar ends at 0.2: \(s2.nodes.map(\.opacity))")
            w.close()
        }
    }
}

final class SwiftUIDisplaySettlesTests: XCTestCase, @unchecked Sendable {
    struct Demo: View {
        @State var tab = "a"
        @State var text = ""
        @State var amount = 0.4
        @State var enabled = true
        var body: some View {
            TabView(selection: $tab) {
                VStack(alignment: .leading) {
                    Text("Title").font(.title)
                    HStack { TextField("Name", text: $text); Button("Go") {} }
                    Toggle("Enabled", isOn: $enabled.animation(.easeInOut(duration: 0.3)))
                    Slider(value: $amount, in: 0...1).disabled(!enabled)
                    RoundedRectangle(cornerRadius: 8).fill(Color.blue).opacity(enabled ? 1 : 0.3)
                        .frame(width: 100 * amount + 20, height: 20).animation(.easeOut(duration: 0.25), value: amount)
                    if !enabled { Text("Disabled").transition(.move(edge: .leading).combined(with: .opacity)) }
                    GeometryReader { p in Text("\(Int(p.size.width))") }
                    List { ForEach(["a", "b"], id: \.self) { Text($0) } }
                }.tabItem { Text("Controls") }.tag("a")
                Text("Other").tabItem { Text("Other") }.tag("b")
            }
        }
    }

    /// A displayed window stays displayed: no pass re-invalidates it, so the platform is
    /// not asked to repaint forever (which on Windows starves the frame timer).
    func testDisplayAndAnimationsSettle() {
        MainActor.assumeIsolated {
            var clock: CFTimeInterval = 10
            let saved = CARuntime.now
            CARuntime.now = { clock }
            defer { CARuntime.now = saved }
            let (w, h) = host(Demo(), width: 360, height: 400)
            let platform = w._platformWindow as! HostWindow
            w.display()
            let painted = platform.paintCount
            for _ in 0..<3 { w.displayIfNeeded(); h.layoutSubtreeIfNeeded() }
            XCTAssertEqual(platform.paintCount, painted, "a settled window does not repaint")
            XCTAssertFalse(CARuntime.hasPendingWork)
            // Toggle with an animation: frames run while it animates, then stop.
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Enabled" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            let root = h.hostingRoot as! _ViewRoot
            XCTAssertTrue(root.isAnimating)
            for step in 1...8 {
                clock = 10 + Double(step) * 0.05
                CARuntime.tick()
                w.displayIfNeeded()
            }
            XCTAssertFalse(root.isAnimating, "the display link stops once every animation has finished")
            XCTAssertFalse(CARuntime.hasPendingWork)
            let after = platform.paintCount
            for _ in 0..<3 { w.displayIfNeeded() }
            XCTAssertEqual(platform.paintCount, after)
            XCTAssertTrue(allViews(h).compactMap { $0 as? _TextView }.contains { $0.storage.string == "Disabled" })
            let bar = allViews(h).first { $0.alphaValue < 0.31 && $0.alphaValue > 0.29 }
            XCTAssertNotNil(bar, "the bar faded to 0.3")
            // Toggle back on: the bar fades up and the Disabled line leaves after its transition.
            allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Enabled" }?.performClick(nil)
            h.layoutSubtreeIfNeeded()
            XCTAssertTrue(root.isAnimating)
            for step in 1...8 {
                clock = 11 + Double(step) * 0.05
                CARuntime.tick()
                w.displayIfNeeded()
            }
            XCTAssertFalse(root.isAnimating)
            XCTAssertEqual(bar?.alphaValue ?? 0, 1, accuracy: 0.01, "the bar is opaque again")
            XCTAssertFalse(allViews(h).compactMap { $0 as? _TextView }.contains { $0.storage.string == "Disabled" }, "the Disabled line is gone")
            // A control whose frame disagrees with its placement by a fraction (fractional text
            // widths on Windows) must not re-layout the whole root on every pass.
            let go = allViews(h).compactMap { $0 as? NSButton }.first { $0.title == "Go" }!
            let placed = go.frame.size
            go.setFrameSize(NSSize(width: placed.width + 0.4, height: placed.height))
            XCTAssertFalse(h.needsLayout, "a frame change alone does not invalidate the hosting layout")
            w.contentView!.layoutSubtreeIfNeeded()
            w.displayIfNeeded()                      // the resized control redraws once
            let paintsAfter = platform.paintCount
            for _ in 0..<3 { w.contentView!.layoutSubtreeIfNeeded(); w.displayIfNeeded() }
            XCTAssertEqual(platform.paintCount, paintsAfter, "and then nothing repaints")
            XCTAssertEqual(go.frame.size.width, placed.width + 0.4, accuracy: 0.001, "nothing re-placed the control")
            w.close()
        }
    }
}
