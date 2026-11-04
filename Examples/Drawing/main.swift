// Drawing: a gallery view with a custom draw(_:) (paths, a gradient, text, images) beside
// a freehand sketch canvas with mouse tracking, undo/redo and export to PNG. Same source
// on macOS, Windows and Linux.

import AppKit

/// Everything drawn by hand in draw(_:), with NSBezierPath, string drawing and NSImage.
final class GalleryView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        NSBezierPath.fill(bounds)

        // A linear gradient painted as strips (NSGradient is not ported yet; this is the
        // same arithmetic CAGradientLayer uses on the software backends).
        let band = NSRect(x: 16, y: 16, width: bounds.width - 32, height: 60)
        let from = NSColor(calibratedRed: 0.2, green: 0.5, blue: 1, alpha: 1), to = NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.6, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: band, xRadius: 8, yRadius: 8).addClip()
        let strips = 64
        for i in 0..<strips {
            let t = CGFloat(i) / CGFloat(strips - 1)
            NSColor(calibratedRed: from.redComponent + (to.redComponent - from.redComponent) * t,
                    green: from.greenComponent + (to.greenComponent - from.greenComponent) * t,
                    blue: from.blueComponent + (to.blueComponent - from.blueComponent) * t, alpha: 1).setFill()
            let w = band.width / CGFloat(strips)
            NSBezierPath.fill(NSRect(x: band.minX + w * CGFloat(i), y: band.minY, width: w + 0.5, height: band.height))
        }
        NSGraphicsContext.restoreGraphicsState()

        // Paths: a star, a dashed curve and a thick stroked circle.
        let star = NSBezierPath()
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let r: CGFloat = i % 2 == 0 ? 36 : 15
            let p = NSPoint(x: 70 + r * cos(angle), y: 140 + r * sin(angle))
            if i == 0 { star.move(to: p) } else { star.line(to: p) }
        }
        star.close()
        NSColor.systemYellow.setFill(); star.fill()
        NSColor.systemOrange.setStroke(); star.lineWidth = 2; star.lineJoinStyle = .round; star.stroke()
        let curve = NSBezierPath()
        curve.move(to: NSPoint(x: 130, y: 170))
        curve.curve(to: NSPoint(x: 330, y: 120), controlPoint1: NSPoint(x: 180, y: 60), controlPoint2: NSPoint(x: 260, y: 220))
        curve.lineWidth = 4; curve.lineCapStyle = .round
        let dash: [CGFloat] = [10, 6]
        curve.setLineDash(dash, count: dash.count, phase: 0)
        NSColor.systemGreen.setStroke(); curve.stroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 280, y: 150, width: 48, height: 48))
        ring.lineWidth = 6; NSColor.systemTeal.setStroke(); ring.stroke()

        // Text: a one-line string at a point, a wrapped paragraph in a rect.
        "Drawn with draw(_:)".draw(at: NSPoint(x: 16, y: 200),
                                   withAttributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.labelColor])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        "Paths, a gradient, text and images, all from NSBezierPath, string drawing and NSImage in one custom view."
            .draw(in: NSRect(x: 16, y: 232, width: bounds.width - 32, height: 48),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])

        // Images: one built offscreen with lockFocus, drawn opaque, scaled and translucent.
        let badge = GalleryView.badge
        badge.draw(in: NSRect(x: 16, y: 290, width: 64, height: 64))
        badge.draw(in: NSRect(x: 96, y: 290, width: 96, height: 64), from: .zero, operation: .sourceOver, fraction: 1)
        badge.draw(in: NSRect(x: 208, y: 290, width: 64, height: 64), from: .zero, operation: .sourceOver, fraction: 0.4)
    }

    static let badge: NSImage = {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 60, height: 60)).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: 28, height: 28), xRadius: 6, yRadius: 6).fill()
        image.unlockFocus()
        return image
    }()
}

/// Freehand strokes with the mouse; undo and redo through two stacks of strokes.
final class SketchView: NSView {
    struct Stroke { var points: [NSPoint]; var color: NSColor; var width: CGFloat }
    private(set) var strokes: [Stroke] = []
    private var redoStack: [Stroke] = []
    private var current: Stroke?
    var color: NSColor = .black
    var lineWidth: CGFloat = 3
    var onChange: () -> Void = {}
    var canUndo: Bool { !strokes.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath.fill(bounds)
        for stroke in strokes + (current.map { [$0] } ?? []) {
            let path = NSBezierPath()
            path.lineWidth = stroke.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            guard let first = stroke.points.first else { continue }
            path.move(to: first)
            if stroke.points.count == 1 { path.line(to: first) }
            for p in stroke.points.dropFirst() { path.line(to: p) }
            stroke.color.setStroke()
            path.stroke()
        }
        if strokes.isEmpty && current == nil {
            "Draw here with the mouse".draw(at: NSPoint(x: 12, y: 12), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor])
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        current = Stroke(points: [convert(event.locationInWindow, from: nil)], color: color, width: lineWidth)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        current?.points.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let s = current else { return }
        current = nil
        push(s)
    }

    func push(_ stroke: Stroke) {
        strokes.append(stroke)
        redoStack.removeAll()
        needsDisplay = true
        onChange()
    }
    func undo() { guard let s = strokes.popLast() else { return }; redoStack.append(s); needsDisplay = true; onChange() }
    func redo() { guard let s = redoStack.popLast() else { return }; strokes.append(s); needsDisplay = true; onChange() }
    func clear() { guard !strokes.isEmpty else { return }; redoStack = strokes.reversed() + redoStack; strokes.removeAll(); needsDisplay = true; onChange() }

    /// Renders the canvas through the view hierarchy into a PNG file.
    func exportPNG(to url: URL) -> Bool {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSSelectorHandling {
    var window: NSWindow!
    var sketch: SketchView!
    var undoButton: NSButton!, redoButton: NSButton!
    var status: NSTextField!

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("undo:")): sketch.undo(); return true
        case Selector(("redo:")): sketch.redo(); return true
        case Selector(("clearSketch:")): sketch.clear(); return true
        case Selector(("exportPNG:")):
            let panel = NSSavePanel()
            panel.title = "Export PNG"
            panel.nameFieldStringValue = "sketch.png"
            panel.allowedFileTypes = ["png"]
            if panel.runModal() == .OK, let url = panel.url {
                status.stringValue = sketch.exportPNG(to: url) ? "Exported \(url.lastPathComponent)" : "Export failed"
            }
            return true
        case Selector(("colorChanged:")):
            let names: [String: NSColor] = ["Black": .black, "Red": .systemRed, "Blue": .systemBlue, "Green": .systemGreen]
            sketch.color = names[(sender as? NSPopUpButton)?.titleOfSelectedItem ?? ""] ?? .black
            return true
        case Selector(("widthChanged:")): sketch.lineWidth = CGFloat((sender as? NSSlider)?.doubleValue ?? 3); return true
        case Selector(("quit:")): NSApp.terminate(sender); return true
        default: return false
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(title: "Main")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Export PNG\u{2026}", action: Selector(("exportPNG:")), keyEquivalent: "e")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Clear", action: Selector(("clearSketch:")), keyEquivalent: "k")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Drawing"
        let content = window.contentView!
        let gallery = GalleryView(frame: NSRect(x: 0, y: 0, width: 340, height: 420))
        gallery.autoresizingMask = [.height]
        content.addSubview(gallery)
        let divider = SeparatorView(frame: NSRect(x: 340, y: 0, width: 1, height: 420))
        divider.autoresizingMask = [.height]
        content.addSubview(divider)

        sketch = SketchView(frame: NSRect(x: 341, y: 44, width: 579, height: 376))
        sketch.autoresizingMask = [.width, .height]
        sketch.onChange = { [unowned self] in self.updateButtons() }
        content.addSubview(sketch)

        undoButton = NSButton(title: "Undo", target: self, action: Selector(("undo:")))
        redoButton = NSButton(title: "Redo", target: self, action: Selector(("redo:")))
        let clear = NSButton(title: "Clear", target: self, action: Selector(("clearSketch:")))
        let export = NSButton(title: "Export PNG\u{2026}", target: self, action: Selector(("exportPNG:")))
        let colors = NSPopUpButton(frame: .zero, pullsDown: false)
        colors.addItems(withTitles: ["Black", "Red", "Blue", "Green"])
        colors.target = self; colors.action = Selector(("colorChanged:"))
        let width = NSSlider(value: 3, minValue: 1, maxValue: 16, target: self, action: Selector(("widthChanged:")))
        width.frame.size.width = 80
        width.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let bar = NSStackView(views: [undoButton, redoButton, clear, export, colors, width])
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.frame = NSRect(x: 349, y: 8, width: 490, height: 28)
        content.addSubview(bar)
        status = NSTextField(labelWithString: "")
        status.textColor = .secondaryLabelColor
        status.alignment = .right
        status.frame = NSRect(x: 836, y: 12, width: 76, height: 20)
        status.autoresizingMask = [.minXMargin]
        content.addSubview(status)
        // A sample stroke, so undo and export have something to work on.
        sketch.push(SketchView.Stroke(points: (0...40).map { NSPoint(x: 40 + CGFloat($0) * 8, y: 180 + 60 * sin(CGFloat($0) / 4)) }, color: .systemBlue, width: 4))

        window.center()
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(sketch)
        // `Drawing --export <file.png>` writes the canvas and exits (scripted checks).
        if let i = CommandLine.arguments.firstIndex(of: "--export"), i + 1 < CommandLine.arguments.count {
            let ok = sketch.exportPNG(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            print(ok ? "exported \(CommandLine.arguments[i + 1])" : "export failed")
            fflush(nil)
            NSApp.terminate(nil)
        }
    }

    private func updateButtons() {
        undoButton.isEnabled = sketch.canUndo
        redoButton.isEnabled = sketch.canRedo
        status.stringValue = "\(sketch.strokes.count) stroke(s)"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// A one-point vertical rule between the gallery and the canvas.
final class SeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.separatorColor.setFill(); NSBezierPath.fill(bounds) }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
