// Glass: Liquid Glass (ADR-0052) made visible and measurable. Colourful content scrolls under
// a toolbar band, under a pair of glass buttons that merge in an `NSGlassEffectContainerView`,
// under a clear and a tinted `NSGlassEffectView`, and under a SwiftUI `GlassEffectContainer`
// with the `.glass` and `.glassProminent` button styles and an interactive `glassEffect`.
// Run with `APPKITWIN_LIQUID_GLASS=1` for the material; without it every surface draws the
// pre-26 look, so the two runs compare the switch. The toolbar's play item scrolls the
// content at frame rate, so the glass re-samples every frame (`APPKITWIN_TRACE_FRAMES=1`
// prints the draw times).

import AppKit
import SwiftUI

/// Bands of saturated colour with discs on them: a backdrop whose blur, refraction and
/// variant flips are easy to see.
@MainActor
final class ColourfulView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let bandHeight: CGFloat = 90
        let colours: [NSColor] = [
            NSColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1), NSColor(red: 0.98, green: 0.65, blue: 0.2, alpha: 1),
            NSColor(red: 0.3, green: 0.75, blue: 0.4, alpha: 1), NSColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1),
            NSColor(red: 0.55, green: 0.35, blue: 0.9, alpha: 1), NSColor(white: 0.12, alpha: 1), NSColor(white: 0.95, alpha: 1),
        ]
        var y: CGFloat = 0, i = 0
        while y < bounds.height {
            let band = NSRect(x: 0, y: y, width: bounds.width, height: bandHeight)
            if band.intersects(dirtyRect) {
                colours[i % colours.count].setFill()
                band.fill()
                // Discs in the complementary tone, so a lens edge has detail to bend.
                let disc = colours[(i + 3) % colours.count]
                disc.withAlphaComponent(0.85).setFill()
                var x: CGFloat = 30 + CGFloat(i % 3) * 40
                while x < bounds.width {
                    NSBezierPath(ovalIn: NSRect(x: x, y: y + 20, width: 50, height: 50)).fill()
                    x += 160
                }
                let label = NSAttributedString(string: "Band \(i + 1)", attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: i % colours.count == 6 ? NSColor.black : NSColor.white])
                label.draw(at: NSPoint(x: bounds.width - 140, y: y + 30))
            }
            y += bandHeight; i += 1
        }
    }
}

/// SwiftUI's glass API over the same content.
struct GlassControls: View {
    @State private var count = 0
    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 10) {
                Button("Glass \(count)") { count += 1 }.buttonStyle(.glass)
                Button("Prominent") { count += 1 }.buttonStyle(.glassProminent)
                Text("Interactive").padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular.interactive())
                Text("Tinted").padding(.horizontal, 12).padding(.vertical, 6).glassEffect(.regular.tint(.orange))
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSSelectorHandling {
    var window: NSWindow!
    var scrollView: NSScrollView!
    var timer: Timer?
    static let back = NSToolbarItem.Identifier("back")
    static let forward = NSToolbarItem.Identifier("forward")
    static let play = NSToolbarItem.Identifier("play")
    static let tint = NSToolbarItem.Identifier("tint")
    static let act = Selector(("toolbarItemClicked:"))

    static func glyph(_ draw: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: 24, height: 24), flipped: false) { r in draw(r.insetBy(dx: 4, dy: 4)); return true }
    }
    static func arrow(forward: Bool) -> NSImage {
        glyph { r in
            let p = NSBezierPath()
            let x0 = forward ? r.minX : r.maxX, x1 = forward ? r.maxX : r.minX
            p.move(to: NSPoint(x: x0, y: r.midY)); p.line(to: NSPoint(x: x1, y: r.midY))
            let dir: CGFloat = forward ? -1 : 1
            p.move(to: NSPoint(x: x1 + dir * 6, y: r.midY + 6)); p.line(to: NSPoint(x: x1, y: r.midY)); p.line(to: NSPoint(x: x1 + dir * 6, y: r.midY - 6))
            p.lineWidth = 2; p.lineCapStyle = .round; p.lineJoinStyle = .round
            NSColor.labelColor.setStroke(); p.stroke()
        }
    }
    static func triangle() -> NSImage {
        glyph { r in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + 2, y: r.minY)); p.line(to: NSPoint(x: r.maxX, y: r.midY)); p.line(to: NSPoint(x: r.minX + 2, y: r.maxY)); p.close()
            NSColor.labelColor.setFill(); p.fill()
        }
    }
    static func disc(_ color: NSColor) -> NSImage { glyph { r in color.setFill(); NSBezierPath(ovalIn: r).fill() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `Glass --reference <scene> <state> <out.png>` draws one of the reference scenes
        // (light, dark, over-dark, interactive; states rest, hover, press;
        // ReferenceScene.swift) through the port and exits: the port's half of the comparison
        // with real macOS 26 glass (tools/glass/capture-references.sh, ADR-0052). The scale is
        // the display's (`APPKITWIN_HOST_SCALE=1` on the host for 1x).
        if let i = CommandLine.arguments.firstIndex(of: "--reference"), i + 3 < CommandLine.arguments.count,
           let scene = GlassReferenceScene(rawValue: CommandLine.arguments[i + 1]),
           let state = GlassReferenceScene.State(rawValue: CommandLine.arguments[i + 2]) {
            writeReference(scene, state: state, to: CommandLine.arguments[i + 3])
            NSApp.terminate(nil)
            return
        }
        if ProcessInfo.processInfo.environment["APPKITWIN_LIQUID_GLASS"] != "1" {
            print("Glass: APPKITWIN_LIQUID_GLASS is not set; every surface draws the pre-26 look. Run with APPKITWIN_LIQUID_GLASS=1 for the material.")
        }
        window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 900, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Liquid Glass"
        window.minSize = NSSize(width: 600, height: 400)
        let content = window.contentView!

        scrollView = NSScrollView(frame: content.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        let document = ColourfulView(frame: NSRect(x: 0, y: 0, width: 900, height: 2700))
        document.autoresizingMask = [.width]
        scrollView.documentView = document
        content.addSubview(scrollView)

        // A merged pair of glass buttons (closer than the container's spacing).
        let container = NSGlassEffectContainerView(frame: NSRect(x: 30, y: 30, width: 260, height: 44))
        container.spacing = 24
        container.autoresizingMask = [.maxXMargin, .maxYMargin]
        let previous = glassButton("Previous", frame: NSRect(x: 0, y: 0, width: 122, height: 44))
        let next = glassButton("Next", frame: NSRect(x: 130, y: 0, width: 122, height: 44))
        container.addSubview(previous); container.addSubview(next)
        content.addSubview(container)

        // A clear lens and a tinted one, apart.
        let clear = NSGlassEffectView(frame: NSRect(x: 320, y: 30, width: 150, height: 44))
        clear.style = .clear; clear.cornerRadius = 22
        clear._isInteractive = true    // brightens under the pointer and while pressed
        clear.contentView = label("Clear glass")
        clear.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(clear)
        let tinted = NSGlassEffectView(frame: NSRect(x: 500, y: 30, width: 150, height: 44))
        tinted.cornerRadius = 12; tinted.tintColor = NSColor.systemOrange
        tinted.contentView = label("Tinted glass")
        tinted.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(tinted)

        // The SwiftUI API, floating at the top right of the content.
        let hosting = NSHostingView(rootView: GlassControls())
        let size = hosting.fittingSize
        hosting.frame = NSRect(x: content.bounds.width - size.width - 24, y: content.bounds.height - size.height - 24, width: size.width, height: size.height)
        hosting.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(hosting)

        let toolbar = NSToolbar(identifier: "glass.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // `Glass --screenshot <file.png>` paints the window (content and toolbar band) into a
        // PNG and exits, for the comparison page and the PC checklist.
        if let i = CommandLine.arguments.firstIndex(of: "--screenshot"), i + 1 < CommandLine.arguments.count {
            scroll(by: 130)
            writeScreenshot(to: CommandLine.arguments[i + 1])
            NSApp.terminate(nil)
        }
        // `Glass --autoscroll <seconds>` (or `APPKITWIN_GLASS_AUTOSCROLL=<seconds>`) scrolls
        // the content at 60 Hz for that long without a click, prints a line per second
        // (frames, mean and p95 paint time) and a summary, then exits: the performance
        // measurement of a release build on the PC.
        // `--interval <ms>` (default 16.7) is the time between frames; 0 drives them back to
        // back, so the summary's frame gap shows what the platform's paint and pump allow.
        let env = ProcessInfo.processInfo.environment["APPKITWIN_GLASS_AUTOSCROLL"]
        let arg = CommandLine.arguments.firstIndex(of: "--autoscroll").flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil }
        let interval = CommandLine.arguments.firstIndex(of: "--interval").flatMap { $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil }
            ?? ProcessInfo.processInfo.environment["APPKITWIN_GLASS_INTERVAL"].flatMap(Double.init) ?? 1000 / 60
        if let seconds = (arg ?? env).flatMap(Double.init), seconds > 0 {
            window.display()
            startAutoScroll(measuringFor: seconds, interval: interval / 1000)
        }
    }

    private func writeScreenshot(to path: String) {
        window.display()
        let band = window.frame.height - NSWindow.contentRect(forFrameRect: window.frame, styleMask: window.styleMask).height
        let size = NSSize(width: window.contentView!.bounds.width, height: window.contentView!.bounds.height + band)
        guard let surface = Platform.backend.image.makeOffscreen(size: size, scale: window.backingScaleFactor) else { return }
        window.platformWindowDraw(into: surface.context, dirtyRect: NSRect(origin: .zero, size: size))
        guard let image = surface.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("screenshot: \(path) (\(image.width)x\(image.height))")
    }

    private func writeReference(_ scene: GlassReferenceScene, state: GlassReferenceScene.State, to path: String) {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: GlassReferenceScene.size), styleMask: [.titled], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: scene.appearance)
        w.contentView = scene.makeContent()
        w.makeKeyAndOrderFront(nil)
        w.layoutIfNeeded()
        let content = w.contentView!
        if state != .rest, let surface = scene.surfaces.first(where: { $0.interactive }) {
            // The pointer over the interactive surface (and the button down for a press),
            // delivered to the glass view as the event loop would.
            let point = NSPoint(x: surface.frame.midX, y: surface.frame.midY)
            var glass: [NSView] = []
            func collect(_ v: NSView) { if v is NSGlassEffectView { glass.append(v) }; v.subviews.forEach(collect) }
            collect(content)
            for g in glass where g.convert(g.bounds, to: nil).contains(point) {
                if let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: point, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                                      context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) { g.mouseEntered(with: enter) }
                if state == .press, let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { g.mouseDown(with: down) }
            }
        }
        w.display()
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("reference \(scene.rawValue) \(state.rawValue): \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
    }

    private func glassButton(_ title: String, frame: NSRect) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: frame)
        glass.cornerRadius = frame.height / 2
        let button = NSButton(title: title, target: self, action: Selector(("buttonClicked:")))
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        glass.contentView = button
        return glass
    }
    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .center
        l.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        return l
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.back, Self.forward, .flexibleSpace, Self.tint, Self.play] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.back, Self.forward, Self.tint, Self.play, .flexibleSpace, .space] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        item.target = self
        item.action = Self.act
        switch id {
        case Self.back: item.label = "Back"; item.image = Self.arrow(forward: false); item.isNavigational = true
        case Self.forward: item.label = "Forward"; item.image = Self.arrow(forward: true); item.isNavigational = true
        case Self.play: item.label = "Scroll"; item.toolTip = "Scroll the content under the glass"; item.image = Self.triangle()
        case Self.tint: item.label = "Tint"; item.image = Self.disc(.systemOrange)
        default: return nil
        }
        return item
    }

    func toolbarItemClicked(_ sender: Any?) {
        guard let item = sender as? NSToolbarItem else { return }
        switch item.itemIdentifier {
        case Self.back: scroll(by: -scrollView.contentSize.height)
        case Self.forward: scroll(by: scrollView.contentSize.height)
        case Self.play: toggleAutoScroll()
        case Self.tint: cycleTint()
        default: break
        }
    }
    func buttonClicked(_ sender: Any?) {
        guard let b = sender as? NSButton else { return }
        scroll(by: b.title == "Next" ? 90 : -90)
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Self.act: toolbarItemClicked(sender); return true
        case Selector(("buttonClicked:")): buttonClicked(sender); return true
        default: return false
        }
    }

    // MARK: Scrolling

    private func scroll(by delta: CGFloat) {
        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.bounds.height ?? 0) - clip.bounds.height)
        var origin = clip.bounds.origin
        origin.y = min(maxY, max(0, origin.y + delta))
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
    private func toggleAutoScroll() {
        if let t = timer { t.invalidate(); timer = nil; return }
        startAutoScroll(measuringFor: nil, interval: 1.0 / 60)
    }

    /// Scrolls two points a frame every `interval`. With a duration, every frame is painted
    /// synchronously (`displayIfNeeded`, the platform's paint) and timed, as is the gap
    /// from one frame's start to the next (the timer's cadence plus the paint: what the
    /// run loop and the platform's pump allow); the stats go to stdout once a second and
    /// in a summary, and the app exits when the time is up.
    private func startAutoScroll(measuringFor seconds: Double?, interval: Double) {
        var paints: [Double] = [], gaps: [Double] = []
        var secondPaints: [Double] = [], secondGaps: [Double] = []
        let start = Date()
        var lastReport = start
        var lastFrameStart: UInt64?
        timer = Timer.scheduledTimer(withTimeInterval: max(0.0001, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let frameStart = DispatchTime.now().uptimeNanoseconds
                let clip = self.scrollView.contentView
                let maxY = max(0, (self.scrollView.documentView?.bounds.height ?? 0) - clip.bounds.height)
                var origin = clip.bounds.origin
                origin.y += 2
                if origin.y > maxY { origin.y = 0 }
                clip.scroll(to: origin)
                self.scrollView.reflectScrolledClipView(clip)
                guard let seconds else { return }
                let t0 = DispatchTime.now().uptimeNanoseconds
                self.window.displayIfNeeded()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
                paints.append(ms); secondPaints.append(ms)
                if let previous = lastFrameStart {
                    let gap = Double(frameStart - previous) / 1_000_000
                    gaps.append(gap); secondGaps.append(gap)
                }
                lastFrameStart = frameStart
                let now = Date()
                if now.timeIntervalSince(lastReport) >= 1 {
                    print(String(format: "autoscroll %4.1f s: %3d frames, paint mean %.2f ms, p95 %.2f ms, max %.2f ms; frame gap mean %.2f ms, p95 %.2f ms", now.timeIntervalSince(start), secondPaints.count, Self.mean(secondPaints), Self.p95(secondPaints), secondPaints.max() ?? 0, Self.mean(secondGaps), Self.p95(secondGaps)))
                    secondPaints.removeAll(); secondGaps.removeAll(); lastReport = now
                }
                if now.timeIntervalSince(start) >= seconds {
                    self.timer?.invalidate(); self.timer = nil
                    let glass = ProcessInfo.processInfo.environment["APPKITWIN_LIQUID_GLASS"] == "1" ? "on" : "off"
                    let elapsed = now.timeIntervalSince(start)
                    print(String(format: "autoscroll summary (glass %@, %.0fx, interval %.1f ms): %d frames in %.1f s (%.1f fps), paint mean %.2f ms, p95 %.2f ms, max %.2f ms; frame gap mean %.2f ms, p95 %.2f ms, min %.2f ms", glass, self.window.backingScaleFactor, interval * 1000, paints.count, elapsed, Double(paints.count) / elapsed, Self.mean(paints), Self.p95(paints), paints.max() ?? 0, Self.mean(gaps), Self.p95(gaps), gaps.min() ?? 0))
                    NSApp.terminate(nil)
                }
            }
        }
    }
    private static func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }
    private static func p95(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let sorted = v.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
    }
    private var tints: [NSColor?] = [.systemOrange, .systemPink, .systemTeal, nil]
    private func cycleTint() {
        tints.append(tints.removeFirst())
        for v in window.contentView!.subviews.compactMap({ $0 as? NSGlassEffectView }) where v.style == .regular { v.tintColor = tints[0] }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
