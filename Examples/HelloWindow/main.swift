// Milestone 1 sample: open a window and draw into it with AppKit APIs only.
// Builds against this package on Windows and against Apple's AppKit on macOS unchanged.

import AppKit

final class CanvasView: NSView {
    private var clicks: [NSPoint] = []
    var showsGrid = true { didSet { needsDisplay = true } }
    var circleSize: CGFloat = 120 { didSet { needsDisplay = true } }

    func clearDots() {
        clicks.removeAll()
        needsDisplay = true
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)

        // Background grid
        if showsGrid {
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
        }

        // Filled rounded rectangle with a stroke
        let box = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 220, height: 140), xRadius: 16, yRadius: 16)
        NSColor.systemBlue.withAlphaComponent(0.85).setFill()
        box.fill()
        NSColor.systemBlue.shadow(withLevel: 0.3)?.setStroke()
        box.lineWidth = 3
        box.stroke()

        // A circle
        let circle = NSBezierPath(ovalIn: NSRect(x: 360 - circleSize / 2, y: 120 - circleSize / 2, width: circleSize, height: circleSize))
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
        "Hello from AppKit on Windows".draw(at: NSPoint(x: 40, y: bounds.height - 34),
                                            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.labelColor])
        "Click to add dots, press c to clear. \(clicks.count) dot(s).".draw(at: NSPoint(x: 40, y: bounds.height - 56),
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
            clearDots()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Document view for the scroll view: 40 numbered rows, flipped so row 1 is at the top.
final class RowsView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        NSBezierPath.fill(dirtyRect)
        let font = NSFont.systemFont(ofSize: 13)
        for row in 0..<40 {
            let y = CGFloat(row) * 24
            guard NSRect(x: 0, y: y, width: bounds.width, height: 24).intersects(dirtyRect) else { continue }
            if row % 2 == 1 {
                NSColor.alternatingContentBackgroundColors[1].setFill()
                NSBezierPath.fill(NSRect(x: 0, y: y, width: bounds.width, height: 24))
            }
            "Row \(row + 1)".draw(at: NSPoint(x: 8, y: y + 4), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSelectorHandling {
    var window: NSWindow!
    var canvas: CanvasView!
    var greeting: NSTextField!
    var gridMenuItem: NSMenuItem!
    var gridCheckbox: NSButton!

    // Actions arrive here by selector name (no Objective-C runtime on Windows).
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("clearDots:")): canvas.clearDots(); return true
        case Selector(("toggleGrid:")):
            canvas.showsGrid = (sender as? NSButton)?.state == .on
            gridMenuItem.state = canvas.showsGrid ? .on : .off
            return true
        case Selector(("toggleGridMenu:")):
            canvas.showsGrid.toggle()
            gridMenuItem.state = canvas.showsGrid ? .on : .off
            gridCheckbox.state = gridMenuItem.state
            return true
        case Selector(("quit:")): NSApp.terminate(sender); return true
        case Selector(("openFile:")):
            let panel = NSOpenPanel()
            panel.title = "Choose a file"
            panel.allowedFileTypes = ["png", "jpg", "jpeg", "bmp", "gif", "txt"]
            panel.allowsOtherFileTypes = true
            if panel.runModal() == .OK, let url = panel.url {
                greeting.stringValue = url.lastPathComponent
            } else {
                greeting.stringValue = "Open cancelled"
            }
            return true
        case Selector(("showAbout:")):
            let alert = NSAlert()
            alert.messageText = "HelloWindow"
            alert.informativeText = "AppKit on Windows, milestone 2. Choose a button; the greeting label reports which."
            alert.addButton(withTitle: "Great")
            alert.addButton(withTitle: "Later")
            let response = alert.runModal()
            greeting.stringValue = response == .alertFirstButtonReturn ? "You chose Great" : "You chose Later"
            return true
        case Selector(("copyGreeting:")):
            _ = NSPasteboard.general.clearContents()
            _ = NSPasteboard.general.setString(greeting.stringValue.isEmpty ? "Hello from AppKit on Windows" : greeting.stringValue, forType: .string)
            return true
        case Selector(("sizeChanged:")):
            canvas.circleSize = CGFloat((sender as? NSSlider)?.doubleValue ?? 120)
            return true
        case Selector(("nameEntered:")):
            let name = (sender as? NSTextField)?.stringValue ?? ""
            greeting.stringValue = name.isEmpty ? "" : "Hello, \(name)!"
            return true
        default: return false
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Main menu: AppKit menus become the window's menu bar on Windows.
        let main = NSMenu(title: "Main")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open\u{2026}", action: Selector(("openFile:")), keyEquivalent: "o")
        file.addItem(withTitle: "Clear Dots", action: Selector(("clearDots:")), keyEquivalent: "k")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let view = NSMenu(title: "View")
        gridMenuItem = view.addItem(withTitle: "Show Grid", action: Selector(("toggleGridMenu:")), keyEquivalent: "g")
        gridMenuItem.state = .on
        viewItem.submenu = view
        main.addItem(viewItem)
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "About HelloWindow", action: Selector(("showAbout:")), keyEquivalent: "")
        help.addItem(withTitle: "Copy Greeting", action: Selector(("copyGreeting:")), keyEquivalent: "c")
        helpItem.submenu = help
        main.addItem(helpItem)
        NSApp.mainMenu = main

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Hello, AppKit on Windows"
        window.delegate = self
        let canvas = CanvasView(frame: window.contentView!.bounds)
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas

        // Milestone 2: a push button and a checkbox wired with target/action.
        let clear = NSButton(title: "Clear dots", target: self, action: Selector(("clearDots:")))
        clear.frame.origin = NSPoint(x: canvas.bounds.maxX - clear.frame.width - 16, y: 16)
        clear.autoresizingMask = [.minXMargin, .maxYMargin]
        clear.keyEquivalent = "\r"
        canvas.addSubview(clear)
        let grid = NSButton(checkboxWithTitle: "Show grid", target: self, action: Selector(("toggleGrid:")))
        grid.state = .on
        grid.frame.origin = NSPoint(x: clear.frame.minX - grid.frame.width - 16, y: clear.frame.midY - grid.frame.height / 2)
        grid.autoresizingMask = [.minXMargin, .maxYMargin]
        canvas.addSubview(grid)
        gridCheckbox = grid

        // A text field and a label that echoes it (Enter or focus loss sends the action).
        let prompt = NSTextField(labelWithString: "Your name:")
        prompt.frame.origin = NSPoint(x: 40, y: canvas.bounds.height - 96)
        prompt.autoresizingMask = [.minYMargin]
        canvas.addSubview(prompt)
        let field = NSTextField(string: "")
        field.placeholderString = "type here, then press Enter"
        field.frame = NSRect(x: prompt.frame.maxX + 8, y: prompt.frame.minY - 4, width: 180, height: 24)
        field.autoresizingMask = [.minYMargin]
        field.target = self
        field.action = Selector(("nameEntered:"))
        canvas.addSubview(field)
        let greeting = NSTextField(labelWithString: "")
        greeting.frame = NSRect(x: field.frame.maxX + 8, y: prompt.frame.minY, width: 160, height: prompt.frame.height)
        greeting.autoresizingMask = [.minYMargin, .width]
        canvas.addSubview(greeting)
        self.greeting = greeting

        // A scroll view over a tall document with numbered rows.
        let scroll = NSScrollView(frame: NSRect(x: canvas.bounds.maxX - 180, y: 60, width: 164, height: 200))
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.minXMargin, .height]
        scroll.documentView = RowsView(frame: NSRect(x: 0, y: 0, width: 140, height: 40 * 24))
        canvas.addSubview(scroll)

        // An image drawn offscreen with lockFocus, shown by an NSImageView.
        let badge = NSImage(size: NSSize(width: 64, height: 64))
        badge.lockFocus()
        NSColor.systemPurple.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 60, height: 60)).fill()
        NSColor.white.setFill()
        let star = NSBezierPath()
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let r: CGFloat = i % 2 == 0 ? 24 : 10
            let p = NSPoint(x: 32 + r * cos(angle), y: 32 - r * sin(angle))
            if i == 0 { star.move(to: p) } else { star.line(to: p) }
        }
        star.close()
        star.fill()
        badge.unlockFocus()
        let imageView = NSImageView(frame: NSRect(x: scroll.frame.minX - 80, y: 60, width: 64, height: 64))
        imageView.image = badge
        imageView.imageFrameStyle = .grayBezel
        imageView.autoresizingMask = [.minXMargin, .maxYMargin]
        canvas.addSubview(imageView)

        // A slider controlling the circle's size.
        let slider = NSSlider(value: 120, minValue: 40, maxValue: 200, target: self, action: Selector(("sizeChanged:")))
        slider.frame = NSRect(x: 40, y: 20, width: 220, height: 21)
        slider.numberOfTickMarks = 5
        slider.autoresizingMask = [.maxYMargin]
        canvas.addSubview(slider)

        // Core Animation: a layer-backed badge with a pulsing ring, a gradient and a text
        // layer; the ring animates without any view redraw code.
        let pulse = NSView(frame: NSRect(x: 280, y: 12, width: 90, height: 36))
        pulse.wantsLayer = true
        pulse.autoresizingMask = [.maxYMargin]
        let gradient = CAGradientLayer()
        gradient.anchorPoint = .zero
        gradient.frame = pulse.bounds
        gradient.colors = [CGColor(srgbRed: 0.15, green: 0.35, blue: 0.9, alpha: 1), CGColor(srgbRed: 0.5, green: 0.2, blue: 0.8, alpha: 1)]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = 8
        gradient.masksToBounds = true
        pulse.layer!.addSublayer(gradient)
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        ring.lineWidth = 3
        ring.position = CGPoint(x: 20, y: 18)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.6
        grow.toValue = 1.2
        grow.duration = 0.9
        grow.autoreverses = true
        grow.repeatCount = .infinity
        grow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ring.add(grow, forKey: "pulse")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0.3
        fade.duration = 0.9
        fade.autoreverses = true
        fade.repeatCount = .infinity
        ring.add(fade, forKey: "fade")
        pulse.layer!.addSublayer(ring)
        let label = CATextLayer()
        label.anchorPoint = .zero
        label.frame = CGRect(x: 38, y: 8, width: 50, height: 20)
        label.string = "CA"
        label.fontSize = 15
        label.foregroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        pulse.layer!.addSublayer(label)
        canvas.addSubview(pulse)
        self.canvas = canvas
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
