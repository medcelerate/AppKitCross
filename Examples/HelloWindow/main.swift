// Milestone 1 sample: open a window and draw into it with AppKit APIs only.
// Builds against this package on Windows and against Apple's AppKit on macOS unchanged.

import AppKit

final class CanvasView: NSView {
    private var clicks: [NSPoint] = []

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)

        // Background grid
        NSColor.separatorColor.setStroke()
        var x: CGFloat = 0
        while x < bounds.width {
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: 0), to: NSPoint(x: x, y: bounds.height))
            x += 40
        }
        var y: CGFloat = 0
        while y < bounds.height {
            NSBezierPath.strokeLine(from: NSPoint(x: 0, y: y), to: NSPoint(x: bounds.width, y: y))
            y += 40
        }

        // Filled rounded rectangle with a stroke
        let box = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 220, height: 140), xRadius: 16, yRadius: 16)
        NSColor.systemBlue.withAlphaComponent(0.85).setFill()
        box.fill()
        NSColor.systemBlue.shadow(withLevel: 0.3)?.setStroke()
        box.lineWidth = 3
        box.stroke()

        // A circle
        let circle = NSBezierPath(ovalIn: NSRect(x: 300, y: 60, width: 120, height: 120))
        NSColor.systemOrange.setFill()
        circle.fill()

        // A dashed curve
        let curve = NSBezierPath()
        curve.move(to: NSPoint(x: 40, y: 220))
        curve.curve(to: NSPoint(x: 420, y: 240), controlPoint1: NSPoint(x: 150, y: 320), controlPoint2: NSPoint(x: 300, y: 140))
        curve.lineWidth = 4
        curve.lineCapStyle = .round
        let dash: [CGFloat] = [12, 8]
        curve.setLineDash(dash, count: dash.count, phase: 0)
        NSColor.systemGreen.setStroke()
        curve.stroke()

        // Text
        "Hello from AppKit on Windows".draw(at: NSPoint(x: 40, y: bounds.height - 48),
                                            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.labelColor])
        "Click to add dots, press c to clear. \(clicks.count) dot(s).".draw(at: NSPoint(x: 40, y: bounds.height - 72),
                                            withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])

        // Click markers
        NSColor.systemRed.setFill()
        for p in clicks {
            NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        clicks.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.characters == "c" {
            clicks.removeAll()
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Hello, AppKit on Windows"
        window.delegate = self
        let canvas = CanvasView(frame: window.contentView!.bounds)
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas
        window.center()
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(canvas)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowDidResize(_ notification: Notification) {
        window.contentView?.needsDisplay = true
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
