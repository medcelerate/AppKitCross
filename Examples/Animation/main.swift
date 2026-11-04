// Animation: Core Animation explicit and implicit animations on a layer-backed view (a
// position animation, an opacity animation, a 3D flip under a perspective transform and a
// CAKeyframeAnimation along a path), with play/pause and a SwiftUI `withAnimation`
// counterpart hosted in the same window. Same source on macOS, Windows and Linux.

import AppKit
import SwiftUI

/// The layer scene and its animations. Pause freezes each layer at its presentation value
/// and removes the animations; play adds them back with `timeOffset` set to the elapsed
/// time, so they resume where they stopped (public CAMediaTiming API only).
@MainActor
final class Stage {
    let box = CALayer()
    let dot = CAShapeLayer()
    let flipHost = CALayer()
    let card = CATextLayer()
    let pulse = CALayer()
    private(set) var isPlaying = false
    private var elapsed: CFTimeInterval = 0
    private var playedAt: CFTimeInterval = 0
    private let colors = [NSColor.systemBlue, .systemRed, .systemGreen, .systemPurple, .systemTeal]
    private var colorIndex = 0

    func install(in root: CALayer) {
        box.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
        box.position = CGPoint(x: 60, y: 230)
        box.backgroundColor = colors[0].cgColor
        box.cornerRadius = 10
        root.addSublayer(box)

        dot.path = CGPath(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18), transform: nil)
        dot.bounds = CGRect(x: -10, y: -10, width: 20, height: 20)
        dot.fillColor = NSColor.systemOrange.cgColor
        dot.position = CGPoint(x: 40, y: 90)
        root.addSublayer(dot)
        // A layer rasterises within its bounds: the track covers the stage.
        let track = CAShapeLayer()
        track.frame = root.bounds
        track.path = Stage.trackPath
        track.fillColor = nil
        track.strokeColor = NSColor.systemGray.cgColor
        track.lineWidth = 2
        track.lineDashPattern = [6, 4]
        root.insertSublayer(track, below: dot)

        // The card flips about its vertical axis under a perspective sublayerTransform.
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 300
        flipHost.sublayerTransform = perspective
        flipHost.frame = CGRect(x: 320, y: 70, width: 160, height: 100)
        root.addSublayer(flipHost)
        card.bounds = CGRect(x: 0, y: 0, width: 120, height: 70)
        card.position = CGPoint(x: 80, y: 50)
        card.backgroundColor = NSColor.systemIndigo.cgColor
        card.cornerRadius = 8
        card.string = "3D flip"
        card.fontSize = 18
        card.alignmentMode = .center
        card.foregroundColor = NSColor.white.cgColor
        flipHost.addSublayer(card)

        pulse.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        pulse.position = CGPoint(x: 400, y: 230)
        pulse.cornerRadius = 20
        pulse.backgroundColor = NSColor.systemPink.cgColor
        root.addSublayer(pulse)
    }

    static var trackPath: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 40, y: 90))
        p.addCurve(to: CGPoint(x: 200, y: 90), control1: CGPoint(x: 80, y: 170), control2: CGPoint(x: 160, y: 10))
        p.addCurve(to: CGPoint(x: 40, y: 90), control1: CGPoint(x: 240, y: 170), control2: CGPoint(x: 0, y: 10))
        return p
    }

    /// Fresh animation objects (Core Animation copies them on `add`, so each play needs new ones).
    private func animations() -> [(CALayer, CAAnimation, String)] {
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = 60; slide.toValue = 260
        slide.duration = 1.6; slide.autoreverses = true; slide.repeatCount = .infinity
        slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let along = CAKeyframeAnimation(keyPath: "position")
        along.path = Stage.trackPath
        along.duration = 5; along.repeatCount = .infinity
        along.calculationMode = .paced

        let flip = CABasicAnimation(keyPath: "transform.rotation.y")
        flip.fromValue = 0; flip.toValue = 2 * CGFloat.pi
        flip.duration = 3; flip.repeatCount = .infinity

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0.2
        fade.duration = 0.7; fade.autoreverses = true; fade.repeatCount = .infinity
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1; grow.toValue = 1.5
        grow.duration = 0.7; grow.autoreverses = true; grow.repeatCount = .infinity
        let group = CAAnimationGroup()
        group.animations = [fade, grow]
        group.duration = 1.4; group.repeatCount = .infinity

        return [(box, slide, "slide"), (dot, along, "along"), (card, flip, "flip"), (pulse, group, "pulse")]
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        playedAt = CACurrentMediaTime()
        for (layer, animation, key) in animations() {
            animation.timeOffset = elapsed
            layer.add(animation, forKey: key)
        }
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        elapsed += CACurrentMediaTime() - playedAt
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [box, dot, card, pulse] {
            if let p = layer.presentation() {
                layer.position = p.position; layer.opacity = p.opacity; layer.transform = p.transform
            }
            layer.removeAllAnimations()
        }
        CATransaction.commit()
    }

    func reset() {
        pause()
        elapsed = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.position = CGPoint(x: 60, y: 230); box.opacity = 1; box.transform = CATransform3DIdentity
        dot.position = CGPoint(x: 40, y: 90)
        card.transform = CATransform3DIdentity
        pulse.opacity = 1; pulse.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    /// Implicit animations: property changes inside a transaction animate with its duration.
    func jump() {
        colorIndex = (colorIndex + 1) % colors.count
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.8)
        box.backgroundColor = colors[colorIndex].cgColor
        box.cornerRadius = box.cornerRadius > 20 ? 10 : 28
        pulse.position = CGPoint(x: pulse.position.x > 380 ? 300 : 400, y: pulse.position.y)
        CATransaction.commit()
    }
}

/// SwiftUI's side: `withAnimation` moves, rotates and scales the square; the circle pulses
/// with a repeating `.animation(_:value:)` while the toggle is on.
struct SwiftUIPane: View {
    @State private var moved = false
    @State private var pulsing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(moved ? 180 : 0))
                    .scaleEffect(moved ? 1.4 : 1)
                    .offset(x: moved ? 200 : 0)
                Spacer()
                Circle().fill(Color.orange).frame(width: 28, height: 28)
                    .opacity(pulsing ? 0.25 : 1)
                    .scaleEffect(pulsing ? 1.5 : 1)
                    .animation(pulsing ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: pulsing)
            }
            .frame(height: 50)
            .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button(moved ? "Animate back" : "Animate") { withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) { moved.toggle() } }
                Toggle("Pulse", isOn: $pulsing)
                Text("SwiftUI withAnimation").foregroundColor(.secondary)
            }
        }
        .padding(12)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSSelectorHandling {
    var window: NSWindow!
    let stage = Stage()
    var playButton: NSButton!

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("togglePlay:")):
            if stage.isPlaying { stage.pause() } else { stage.play() }
            playButton.title = stage.isPlaying ? "Pause" : "Play"
            return true
        case Selector(("jump:")): stage.jump(); return true
        case Selector(("reset:")): stage.reset(); playButton.title = "Play"; return true
        case Selector(("quit:")): NSApp.terminate(sender); return true
        default: return false
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(title: "Main")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Play/Pause", action: Selector(("togglePlay:")), keyEquivalent: " ")
        file.addItem(withTitle: "Jump (implicit)", action: Selector(("jump:")), keyEquivalent: "j")
        file.addItem(withTitle: "Reset", action: Selector(("reset:")), keyEquivalent: "r")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)
        NSApp.mainMenu = main

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Animation"
        let content = window.contentView!
        content.wantsLayer = true

        // The stage: a layer-backed view whose layer hosts the scene (AppKit coordinates, y up).
        let stageView = NSView(frame: NSRect(x: 0, y: 140, width: 520, height: 280))
        stageView.wantsLayer = true
        stageView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        content.addSubview(stageView)
        stage.install(in: stageView.layer!)

        playButton = NSButton(title: "Play", target: self, action: Selector(("togglePlay:")))
        let jump = NSButton(title: "Jump (implicit)", target: self, action: Selector(("jump:")))
        let reset = NSButton(title: "Reset", target: self, action: Selector(("reset:")))
        let caption = NSTextField(labelWithString: "CA: slide, path, 3D flip, pulse")
        caption.textColor = .secondaryLabelColor
        let row = NSStackView(views: [playButton, jump, reset, caption])
        row.orientation = .horizontal
        row.spacing = 8
        row.frame = NSRect(x: 12, y: 104, width: 496, height: 28)
        content.addSubview(row)

        let hosting = NSHostingView(rootView: SwiftUIPane())
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 100)
        content.addSubview(hosting)

        window.center()
        window.makeKeyAndOrderFront(nil)
        if !CommandLine.arguments.contains("--paused") { stage.play(); playButton.title = "Pause" }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
