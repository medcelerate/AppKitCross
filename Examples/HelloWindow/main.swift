// Milestone 1 sample: open a window and draw into it with AppKit APIs only.
// Builds against this package on Windows and against Apple's AppKit on macOS unchanged.

import AppKit
import Metal
import MetalKit
import SwiftUI
import UniformTypeIdentifiers

/// `HelloWindow --no-layer-backing` keeps the windows' views unbacked (the Milestone 1-8
/// drawing path); otherwise their content views are layer-backed (Milestone 9).
let layerBacked = !CommandLine.arguments.contains("--no-layer-backing")

final class CanvasView: NSView {
    private var clicks: [NSPoint] = []
    var showsGrid = true { didSet { needsDisplay = true } }
    var circleSize: CGFloat = 120 { didSet { needsDisplay = true } }
    var circleColor: NSColor = .systemBlue { didSet { needsDisplay = true } }
    /// Rotation of the needle in the circle, driven by the rotate gesture (radians, counterclockwise).
    var needleAngle: CGFloat = 0 { didSet { needsDisplay = true } }

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
        circleColor.withAlphaComponent(0.85).setFill()
        box.fill()
        circleColor.shadow(withLevel: 0.3)?.setStroke()
        box.lineWidth = 3
        box.stroke()

        // A circle (pinch to resize it, rotate to turn its needle: trackpad, touch screen or Ctrl+wheel)
        let circle = NSBezierPath(ovalIn: NSRect(x: 360 - circleSize / 2, y: 120 - circleSize / 2, width: circleSize, height: circleSize))
        NSColor.systemOrange.setFill()
        circle.fill()
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: 360, y: 120))
        needle.line(to: NSPoint(x: 360 + cos(needleAngle) * circleSize * 0.45, y: 120 + sin(needleAngle) * circleSize * 0.45))
        needle.lineWidth = 3
        NSColor.white.setStroke()
        needle.stroke()

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

    override func magnify(with event: NSEvent) {
        circleSize = min(200, max(40, circleSize * (1 + event.magnification)))
    }
    override func rotate(with event: NSEvent) {
        needleAngle += CGFloat(event.rotation) * .pi / 180
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
        case Selector(("colourChanged:")):
            let names: [String: NSColor] = ["Blue": .systemBlue, "Red": .systemRed, "Green": .systemGreen]
            canvas.circleColor = names[(sender as? NSPopUpButton)?.titleOfSelectedItem ?? ""] ?? .systemBlue
            return true
        case Selector(("quit:")): NSApp.terminate(sender); return true
        case Selector(("exportPDF:")):
            guard let content = NSApp.keyWindow?.contentView else { return true }
            let save = NSSavePanel()
            save.allowedFileTypes = ["pdf"]
            save.nameFieldStringValue = (NSApp.keyWindow?.title ?? "HelloWindow") + ".pdf"
            if save.runModal() == .OK, let url = save.url {
                let data = content.dataWithPDF(inside: content.bounds)
                try? data.write(to: url)
                print("exported \(data.count) bytes of PDF to \(url.path)")
            }
            return true
        case Selector(("closeGlass:")):
            glassWindow?.close()
            glassWindow = nil
            return true
        case Selector(("showGlassWindow:")):
            showGlassWindow()
            return true
        case Selector(("showLayoutDemo:")):
            showLayoutDemo()
            return true
        case Selector(("showSwiftUIDemo:")):
            showSwiftUIDemo()
            return true
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
        // Printing (ADR-0022): both reach the key window through the responder chain; Print…
        // paginates its content view (the Layout Demo's tabs, the canvas) with the print panel
        // as a sheet. Export PDF writes the key window's content with dataWithPDF(inside:).
        // AppKit's shared print info clips a view wider than the printable area (its default
        // horizontal pagination); the demo windows are wider than a portrait page, so they
        // shrink to the page width instead, as a document app would set up its own info.
        NSPrintInfo.shared.horizontalPagination = .fit
        let pageSetup = file.addItem(withTitle: "Page Setup\u{2026}", action: Selector(("runPageLayout:")), keyEquivalent: "p")
        pageSetup.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Print\u{2026}", action: Selector(("print:")), keyEquivalent: "p")
        file.addItem(withTitle: "Export as PDF\u{2026}", action: Selector(("exportPDF:")), keyEquivalent: "")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)
        // Edit menu: nil targets reach the field editor through the responder chain.
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let view = NSMenu(title: "View")
        gridMenuItem = view.addItem(withTitle: "Show Grid", action: Selector(("toggleGridMenu:")), keyEquivalent: "g")
        view.addItem(withTitle: "Layout Demo", action: Selector(("showLayoutDemo:")), keyEquivalent: "l")
        view.addItem(withTitle: "SwiftUI Demo", action: Selector(("showSwiftUIDemo:")), keyEquivalent: "u")
        gridMenuItem.state = .on
        viewItem.submenu = view
        main.addItem(viewItem)
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "About HelloWindow", action: Selector(("showAbout:")), keyEquivalent: "")
        let copyGreeting = help.addItem(withTitle: "Copy Greeting", action: Selector(("copyGreeting:")), keyEquivalent: "c")
        copyGreeting.keyEquivalentModifierMask = [.command, .shift]
        let glass = help.addItem(withTitle: "Glass Window", action: Selector(("showGlassWindow:")), keyEquivalent: "g")
        glass.keyEquivalentModifierMask = [.command, .shift]
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
        // Milestone 9: a layer-backed content view makes every view a layer, so the window
        // hands its tree to DirectComposition (APPKITWIN_SOFTWARE_LAYERS=1 keeps the
        // software compositor; `--no-layer-backing` leaves the views unbacked).
        if layerBacked { canvas.wantsLayer = true }

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

        // A pop-up button choosing the circle's colour, and a context menu on the canvas.
        let colours = NSPopUpButton(frame: NSRect(x: 280, y: 60, width: 0, height: 0), pullsDown: false)
        colours.addItems(withTitles: ["Blue", "Red", "Green"])
        colours.target = self
        colours.action = Selector(("colourChanged:"))
        colours.sizeToFit()
        colours.autoresizingMask = [.maxYMargin]
        canvas.addSubview(colours)
        let context = NSMenu(title: "Canvas")
        context.addItem(withTitle: "Clear Dots", action: Selector(("clearDots:")), keyEquivalent: "")
        context.addItem(withTitle: "Toggle Grid", action: Selector(("toggleGridMenu:")), keyEquivalent: "")
        canvas.menu = context

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
        // Bounds around the stroked path: a hosted layer rasterises only its bounds (the
        // software compositor happens to draw the path wherever it falls).
        ring.bounds = CGRect(x: -12, y: -12, width: 24, height: 24)
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
        // The "CA" text spins about its vertical axis under a perspective sublayerTransform:
        // DirectComposition renders the real 3D placement; software backends show the
        // affine approximation (a horizontal squeeze).
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 120
        pulse.layer!.sublayerTransform = perspective
        let label = CATextLayer()
        label.bounds = CGRect(x: 0, y: 0, width: 50, height: 20)
        label.position = CGPoint(x: 63, y: 18)
        label.string = "CA"
        label.fontSize = 15
        label.foregroundColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let spin = CABasicAnimation(keyPath: "transform.rotation.y")
        spin.fromValue = 0
        spin.toValue = 2 * CGFloat.pi
        spin.duration = 3
        spin.repeatCount = .infinity
        label.add(spin, forKey: "spin")
        pulse.layer!.addSublayer(label)
        canvas.addSubview(pulse)
        self.canvas = canvas
        window.center()
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(canvas)

        // `HelloWindow --swiftui` opens the SwiftUI demo window (for scripted runs and screenshots).
        if CommandLine.arguments.contains("--swiftui") { showSwiftUIDemo() }
        // `HelloWindow --layout` opens the Layout Demo window.
        if CommandLine.arguments.contains("--layout") { showLayoutDemo() }
        // `HelloWindow --screenshot <dir>` renders every open window's content into
        // <dir>/<window>-<platform>.png (through the view hierarchy, as the window draws
        // it) and exits. Used for docs/comparisons.md.
        if let i = CommandLine.arguments.firstIndex(of: "--screenshot"), i + 1 < CommandLine.arguments.count {
            writeScreenshots(to: CommandLine.arguments[i + 1])
        }
        // `HelloWindow --print-pdf <file>` prints the Layout Demo's content view to a PDF
        // without the panels (ADR-0022: pagination through NSPrintOperation, the platform's
        // PDF writer) and exits; the container run checks the page count.
        if let i = CommandLine.arguments.firstIndex(of: "--print-pdf"), i + 1 < CommandLine.arguments.count {
            showLayoutDemo()
            if let content = layoutWindowController?.window?.contentView {
                let info = NSPrintInfo(dictionary: [.jobSavingURL: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
                                                    .jobDisposition: NSPrintInfo.JobDisposition.save.rawValue])
                info.verticalPagination = .automatic
                info.horizontalPagination = .fit
                let op = NSPrintOperation(view: content, printInfo: info)
                op.showsPrintPanel = false
                op.showsProgressPanel = false
                let ok = op.run()
                print("print-pdf: \(ok ? "wrote" : "failed") \(CommandLine.arguments[i + 1]) (\(op.pageRange.length) page(s))")
            }
            NSApp.terminate(nil)
        }
        // `HelloWindow --metal` opens the Layout Demo on its Metal tab (for scripted runs);
        // APPKITWIN_LAYOUT_TAB=form|split|table|metal|combo|outline|pages|collection|grid|box|controls|date|diffable|panels|popover picks a tab the same way.
        if CommandLine.arguments.contains("--metal") {
            showLayoutDemo()
            (layoutWindowController?.window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = 3
        }
        if let tab = ProcessInfo.processInfo.environment["APPKITWIN_LAYOUT_TAB"], let index = AppDelegate.layoutTabs.firstIndex(of: tab) {
            showLayoutDemo()
            (layoutWindowController?.window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = index
        }
        // `HelloWindow --panels-selftest`: the Panels tab, then the Fonts panel made key (a real
        // activation on this backend) and a size chosen in it; prints whether the text view's
        // selection took the font and exits 0 or 1 (ADR-0031, the Windows PC check).
        if CommandLine.arguments.contains("--panels-selftest") {
            showLayoutDemo()
            let tabs = layoutWindowController?.window?.contentViewController as? NSTabViewController
            tabs?.selectedTabViewItemIndex = AppDelegate.layoutTabs.firstIndex(of: "panels") ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { PanelsSelfTest.run(step: 0) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    var layoutWindowController: NSWindowController?
    var glassWindow: NSWindow?
    static let layoutTabs = ["form", "split", "table", "metal", "combo", "outline", "pages", "collection", "grid", "box", "controls", "date", "diffable", "panels", "popover"]

    /// Milestone 3b: a frameless, translucent window over the system backdrop.
    // MARK: Screenshots for the comparison page

    /// Renders a popover's window (body, arrow and content) to <dir>/layout-popover-open-<platform>.png.
    @MainActor static func writePopoverScreenshot(_ w: NSWindow, to dir: String, platform: String) {
        guard let cv = w.contentView else { return }
        w.display()
        guard let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else { return }
        cv.cacheDisplay(in: cv.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        let path = "\(dir)/layout-popover-open-\(platform).png"
        try? png.write(to: URL(fileURLWithPath: path))
        print("screenshot: \(path)")
    }

    @MainActor func writeScreenshots(to dir: String) {
        #if os(Windows)
        let platform = "windows"
        #elseif os(Linux)
        let platform = "linux"
        #else
        let platform = "macos"
        #endif
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // APPKITWIN_POPOVER_OPEN=1 with the Popover tab: show the transient popover first so
        // its window is rendered too.
        if ProcessInfo.processInfo.environment["APPKITWIN_POPOVER_OPEN"] == "1",
           let tabs = layoutWindowController?.window?.contentViewController as? NSTabViewController,
           let demo = tabs.children.compactMap({ $0 as? PopoverDemoViewController }).first {
            tabs.selectedTabViewItemIndex = AppDelegate.layoutTabs.firstIndex(of: "popover") ?? 0
            demo.view.window?.layoutIfNeeded()
            demo.view.window?.display()
            demo.show(.transient, from: demo.transientButton)
        }
        for w in NSApp.windows where w.isVisible {
            guard let cv = w.contentView else { continue }
            // A popover's window renders as its own file: the body with the arrow.
            if w._isPopoverWindow { AppDelegate.writePopoverScreenshot(w, to: dir, platform: platform); continue }
            // The Layout Demo's Form tab is the interesting one unless APPKITWIN_LAYOUT_TAB picks another.
            let layoutTab = ProcessInfo.processInfo.environment["APPKITWIN_LAYOUT_TAB"] ?? "form"
            if let tabs = w.contentViewController as? NSTabViewController { tabs.selectedTabViewItemIndex = AppDelegate.layoutTabs.firstIndex(of: layoutTab) ?? 0 }
            w.display()
            let name: String
            switch w.title {
            case "SwiftUI Demo":
                let tab = ProcessInfo.processInfo.environment["APPKITWIN_DEMO_TAB"] ?? "controls"
                name = tab == "controls" ? "swiftui-demo" : "swiftui-\(tab)"
            case "Layout Demo": name = layoutTab == "form" ? "layout-demo" : "layout-\(layoutTab)"
            case "Colors": name = "color-panel"
            case "Fonts": name = "font-panel"
            default: name = "hellowindow"
            }
            guard let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else { continue }
            cv.cacheDisplay(in: cv.bounds, to: rep)
            // The views draw over the window's background, which the window paints itself:
            // composite the hierarchy over it so the file shows what the screen shows.
            let composed = NSImage(size: cv.bounds.size)
            composed.lockFocus()
            w.effectiveAppearance.performAsCurrentDrawingAppearance {
                w.backgroundColor.setFill()
                NSBezierPath.fill(NSRect(origin: .zero, size: cv.bounds.size))
            }
            if let cg = rep.cgImage { NSGraphicsContext.current?.cgContext.draw(cg, in: NSRect(origin: .zero, size: cv.bounds.size)) }
            composed.unlockFocus()
            guard let final = composed.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let finalRep = NSBitmapImageRep(cgImage: final)
            if let png = finalRep.representation(using: .png, properties: [:]) {
                let path = (dir as NSString).appendingPathComponent("\(name)-\(platform).png")
                try? png.write(to: URL(fileURLWithPath: path))
                print("screenshot: \(path)")
            }
        }
        fflush(nil)
        NSApp.terminate(nil)
    }

    // MARK: SwiftUI demo (ADR-0010)

    var swiftUIWindow: NSWindow?

    @MainActor func showSwiftUIDemo() {
        if let w = swiftUIWindow { w.makeKeyAndOrderFront(nil); return }
        let hosting = NSHostingView(rootView: SwiftUIDemo())
        let size = hosting.sizeThatFits(.unspecified)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(size.width, 360), height: max(size.height, 300)),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "SwiftUI Demo"
        hosting.frame = w.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        swiftUIWindow = w
    }

    @MainActor func showGlassWindow() {
        if let g = glassWindow { g.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Glass"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isMovableByWindowBackground = true
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: w.contentRect(forFrameRect: w.frame).size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.autoresizingMask = [.width, .height]
        w.contentView = effect
        let title = NSTextField(labelWithString: "Liquid glass")
        title.font = NSFont.boldSystemFont(ofSize: 22)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        let field = NSTextField()
        field.placeholderString = "Type over the backdrop"
        field.translatesAutoresizingMaskIntoConstraints = false
        let close = NSButton(title: "Close", target: self, action: Selector(("closeGlass:")))
        close.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(title); effect.addSubview(field); effect.addSubview(close)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: effect.topAnchor, constant: 40),
            field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 24),
            field.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            field.widthAnchor.constraint(equalToConstant: 240),
            close.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -24),
            close.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -20),
        ])
        glassWindow = w
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    /// A second window built with view controllers and Auto Layout: a tab view controller
    /// whose first tab is a form in a stack view and whose second is a split view.
    @MainActor func showLayoutDemo() {
        if let wc = layoutWindowController { wc.showWindow(nil); return }
        let tabs = NSTabViewController()
        tabs.addChild(FormViewController())
        let split = NSSplitViewController()
        let sidebar = ColorViewController(color: NSColor(red: 0.85, green: 0.9, blue: 1, alpha: 1), text: "Sidebar")
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 80
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: ColorViewController(color: NSColor(red: 1, green: 0.95, blue: 0.85, alpha: 1), text: "Drag the divider")))
        split.title = "Split"
        split.view.frame = NSRect(x: 0, y: 0, width: 420, height: 260)
        tabs.addChild(split)
        tabs.addChild(TableDemoViewController())
        tabs.addChild(MetalDemoViewController())
        tabs.addChild(ComboDemoViewController())
        tabs.addChild(OutlineDemoViewController())
        tabs.addChild(PagesDemoViewController())
        tabs.addChild(CollectionDemoViewController())
        tabs.addChild(GridDemoViewController())
        tabs.addChild(BoxDemoViewController())
        tabs.addChild(ControlsDemoViewController())
        tabs.addChild(DateDemoViewController())
        tabs.addChild(DiffableDemoViewController())
        tabs.addChild(PanelsDemoViewController())
        tabs.addChild(PopoverDemoViewController())
        tabs.view.frame = NSRect(x: 0, y: 0, width: 840, height: 300)   // wide enough for the fifteen tabs
        let window = NSWindow(contentViewController: tabs)
        window.title = "Layout Demo"
        if layerBacked { window.contentView?.wantsLayer = true }
        let wc = NSWindowController(window: window)
        layoutWindowController = wc
        window.center()
        wc.showWindow(nil)
    }

    func windowDidResize(_ notification: Notification) {
        window.contentView?.needsDisplay = true
    }
}

// `HelloWindow --metal-selftest` checks the Metal device offscreen and exits with the
// number of failed checks (the test target needs the host backend, so this is how the
// Direct3D 12 device is verified on Windows).
if CommandLine.arguments.contains("--metal-selftest") { exit(MetalSelfTest.run()) }

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()

/// Offscreen checks of the system Metal device: buffers and blits, texture upload and
/// readback, a cleared render pass with a triangle (where the device rasterizes), a
/// texture copy and shader diagnostics. The device is released at the end so the
/// Direct3D 12 shim can report leaked objects (APPKITWIN_D3D12_DEBUG=1).
enum MetalSelfTest {
    static let shaders = """
    cbuffer Frame { float4 tint; };
    struct VSIn { float2 position : ATTRIBUTE0; float4 color : ATTRIBUTE1; };
    struct VSOut { float4 position : SV_Position; float4 color : COLOR0; };
    VSOut triangleVertex(VSIn v) { VSOut o; o.position = float4(v.position, 0, 1); o.color = v.color * tint; return o; }
    float4 triangleFragment(VSOut i) : SV_Target { return i.color; }
    Texture2D image;
    SamplerState imageSampler;
    float4 sampledFragment(VSOut i) : SV_Target { return image.Sample(imageSampler, i.color.xy); }
    """
    /// The triangle in Metal Shading Language, translated to HLSL by the device (ADR-0006).
    static let mslShaders = """
    #include <metal_stdlib>
    using namespace metal;
    struct Frame { float4 tint; };
    struct VSIn { float2 position [[attribute(0)]]; float4 color [[attribute(1)]]; };
    struct VSOut { float4 position [[position]]; float4 color; };
    vertex VSOut mslVertex(VSIn v [[stage_in]], constant Frame& frame [[buffer(0)]]) {
        VSOut o;
        o.position = float4(v.position, 0, 1);
        o.color = v.color * frame.tint;
        return o;
    }
    fragment half4 mslFragment(VSOut i [[stage_in]]) { return half4(i.color); }
    """
    struct Vertex { var x: Float, y: Float, r: Float, g: Float, b: Float, a: Float }

    static func render(_ queue: any MTLCommandQueue, _ pass: MTLRenderPassDescriptor, _ pipeline: any MTLRenderPipelineState, _ vertices: any MTLBuffer, tint: inout [Float], texture: (any MTLTexture)? = nil, sampler: (any MTLSamplerState)? = nil) -> Bool {
        guard let cb = queue.makeCommandBuffer(), let encoder = cb.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&tint, length: 16, index: 0)
        encoder.setVertexBuffer(vertices, offset: 0, index: 1)
        if let texture { encoder.setFragmentTexture(texture, index: 0) }
        if let sampler { encoder.setFragmentSamplerState(sampler, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        return cb.status == .completed
    }

    nonisolated(unsafe) static var failures: Int32 = 0
    static func check(_ condition: Bool, _ what: String) {
        print("\(condition ? "PASS" : "FAIL"): \(what)")
        if !condition { failures += 1 }
    }
    static func pixel(_ texture: any MTLTexture, _ x: Int, _ y: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&out, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        return out
    }

    static func run() -> Int32 {
        exercise()
        print("device released")
        fflush(nil)
        return failures
    }

    static func exercise() {
        #if os(Windows)
        let made: (any MTLDevice)? = ProcessInfo.processInfo.environment["APPKITWIN_METAL_REFERENCE"] == "1" ? MTLCreateSystemDefaultDevice() : MTLD3D12Device()
        #else
        let made = MTLCreateSystemDefaultDevice()
        #endif
        guard let device = made, let queue = device.makeCommandQueue() else { check(false, "device and queue"); return }
        print("device: \(device.name) rasterizes=\(device.supportsRasterization)")
        #if os(Linux)
        if !(device is MTLVulkanDevice) { print("Vulkan device unavailable: \(MTLVulkanDevice.unavailabilityReason.isEmpty ? "APPKITWIN_METAL_REFERENCE=1" : MTLVulkanDevice.unavailabilityReason)") }
        #endif

        // Buffers and a blit copy.
        var floats: [Float] = [1, 2, 3, 4]
        if let a = device.makeBuffer(bytes: &floats, length: 16, options: .storageModeShared), let b = device.makeBuffer(length: 16, options: []), let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.copy(from: a, sourceOffset: 4, to: b, destinationOffset: 0, size: 12)
            blit.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            check(cb.status == .completed, "blit command buffer completes")
            check(b.contents().load(as: Float.self) == 2 && b.contents().load(fromByteOffset: 8, as: Float.self) == 4, "buffer copy lands (\(b.contents().load(as: Float.self)), \(b.contents().load(fromByteOffset: 8, as: Float.self)))")
        } else { check(false, "buffers and blit encoder") }

        // Texture upload and readback round trip.
        if let tex = device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 8, height: 4, mipmapped: false)) {
            var pixels = [UInt8](repeating: 0, count: 8 * 4 * 4)
            for i in 0..<(8 * 4) { pixels[i * 4] = UInt8(i); pixels[i * 4 + 1] = 100; pixels[i * 4 + 2] = 200; pixels[i * 4 + 3] = 255 }
            tex.replace(region: MTLRegionMake2D(0, 0, 8, 4), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 32)
            var back = [UInt8](repeating: 0, count: pixels.count)
            tex.getBytes(&back, bytesPerRow: 32, from: MTLRegionMake2D(0, 0, 8, 4), mipmapLevel: 0)
            check(back == pixels, "texture upload reads back identically")
            check(pixel(tex, 3, 1) == [11, 100, 200, 255], "partial readback of pixel (3,1): \(pixel(tex, 3, 1))")
        } else { check(false, "texture creation") }

        // Clear + triangle, two clear colours, then a texture copy.
        do {
            let options = MTLCompileOptions()
            options.shaderLanguage = .hlsl
            let library = try device.makeLibrary(source: shaders, options: options)
            let pd = MTLRenderPipelineDescriptor()
            pd.vertexFunction = library.makeFunction(name: "triangleVertex")
            pd.fragmentFunction = library.makeFunction(name: "triangleFragment")
            pd.colorAttachments[0].pixelFormat = .bgra8Unorm
            let vd = MTLVertexDescriptor()
            vd.attributes[0].format = .float2
            vd.attributes[0].bufferIndex = 1
            vd.attributes[1].format = .float4
            vd.attributes[1].offset = 8
            vd.attributes[1].bufferIndex = 1
            vd.layouts[1].stride = MemoryLayout<Vertex>.stride
            pd.vertexDescriptor = vd
            let pipeline = try device.makeRenderPipelineState(descriptor: pd)
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]
            guard let target = device.makeTexture(descriptor: td), let copy = device.makeTexture(descriptor: td) else { check(false, "render target creation"); return }
            let triangle = [Vertex(x: 0, y: 0.9, r: 0, g: 1, b: 0, a: 1), Vertex(x: 0.9, y: -0.9, r: 0, g: 1, b: 0, a: 1), Vertex(x: -0.9, y: -0.9, r: 0, g: 1, b: 0, a: 1)]
            guard let vertices = triangle.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: []) }) else { check(false, "vertex buffer"); return }
            var tint: [Float] = [1, 1, 1, 1]
            for clear in [MTLClearColorMake(1, 0, 0, 1), MTLClearColorMake(0, 0, 1, 1)] {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].clearColor = clear
                check(render(queue, pass, pipeline, vertices, tint: &tint), "render command buffer completes")
                let expectedCorner: [UInt8] = [UInt8(clear.blue * 255), UInt8(clear.green * 255), UInt8(clear.red * 255), 255]
                check(pixel(target, 1, 1) == expectedCorner && pixel(target, 62, 1) == expectedCorner, "corners are the clear colour \(expectedCorner): \(pixel(target, 1, 1)) \(pixel(target, 62, 1))")
                if device.supportsRasterization { check(pixel(target, 32, 32) == [0, 255, 0, 255], "centre is the green triangle: \(pixel(target, 32, 32))") }
            }
            if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
                blit.copy(from: target, to: copy)
                blit.endEncoding()
                cb.commit()
                cb.waitUntilCompleted()
                check(pixel(copy, 1, 1) == [255, 0, 0, 255] && (!device.supportsRasterization || pixel(copy, 32, 40) == [0, 255, 0, 255]), "texture copy carries the frame: \(pixel(copy, 1, 1)) \(pixel(copy, 32, 40))")
            }

            // The same triangle from MSL: the library translates it to HLSL (ADR-0006).
            do {
                let mslLibrary = try device.makeLibrary(source: mslShaders, options: nil)
                check(Set(mslLibrary.functionNames) == ["mslVertex", "mslFragment"], "MSL library lists its entry points: \(mslLibrary.functionNames)")
                let md = MTLRenderPipelineDescriptor()
                md.vertexFunction = mslLibrary.makeFunction(name: "mslVertex")
                md.fragmentFunction = mslLibrary.makeFunction(name: "mslFragment")
                md.colorAttachments[0].pixelFormat = .bgra8Unorm
                md.vertexDescriptor = vd
                let mslPipeline = try device.makeRenderPipelineState(descriptor: md)
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1)
                var halfTint: [Float] = [1, 0.5, 1, 1]
                check(render(queue, pass, mslPipeline, vertices, tint: &halfTint), "MSL render command buffer completes")
                if device.supportsRasterization { check(pixel(target, 32, 32) == [0, 128, 0, 255] || pixel(target, 32, 32) == [0, 127, 0, 255], "MSL triangle is tinted half green: \(pixel(target, 32, 32))") }
            } catch { check(false, "MSL triangle pipeline: \(error)") }

            if device.supportsRasterization {
                // Sampling: every vertex carries uv (0.75, 0.75) in its colour, so the whole
                // triangle shows texel (1, 1) of a 2x2 image with point sampling.
                let sd = MTLRenderPipelineDescriptor()
                sd.vertexFunction = library.makeFunction(name: "triangleVertex")
                sd.fragmentFunction = library.makeFunction(name: "sampledFragment")
                sd.colorAttachments[0].pixelFormat = .bgra8Unorm
                sd.vertexDescriptor = vd
                let sampled = try device.makeRenderPipelineState(descriptor: sd)
                let id = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
                id.usage = .shaderRead
                guard let image = device.makeTexture(descriptor: id) else { check(false, "sampled texture"); return }
                let texels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 40, 80, 120, 255]   // BGRA: blue, green, red, (40,80,120)
                image.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: texels, bytesPerRow: 8)
                let uvTriangle = triangle.map { Vertex(x: $0.x, y: $0.y, r: 0.75, g: 0.75, b: 0, a: 1) }
                guard let uvVertices = uvTriangle.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: []) }) else { check(false, "uv vertex buffer"); return }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
                let sampler = device.makeSamplerState(descriptor: MTLSamplerDescriptor())
                check(render(queue, pass, sampled, uvVertices, tint: &tint, texture: image, sampler: sampler), "sampled render completes")
                check(pixel(target, 32, 32) == [40, 80, 120, 255] && pixel(target, 1, 1) == [0, 0, 0, 255], "fragment samples texel (1,1) through t0/s0: \(pixel(target, 32, 32)) corner \(pixel(target, 1, 1))")

                // A depth attachment: the pass clears and binds it; the colour result is unchanged.
                let dd = MTLRenderPipelineDescriptor()
                dd.vertexFunction = library.makeFunction(name: "triangleVertex")
                dd.fragmentFunction = library.makeFunction(name: "triangleFragment")
                dd.colorAttachments[0].pixelFormat = .bgra8Unorm
                dd.depthAttachmentPixelFormat = .depth32Float
                dd.vertexDescriptor = vd
                let depthPipeline = try device.makeRenderPipelineState(descriptor: dd)
                let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 64, height: 64, mipmapped: false)
                depthDesc.usage = .renderTarget
                guard let depth = device.makeTexture(descriptor: depthDesc) else { check(false, "depth texture"); return }
                let depthPass = MTLRenderPassDescriptor()
                depthPass.colorAttachments[0].texture = target
                depthPass.colorAttachments[0].loadAction = .clear
                depthPass.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)
                depthPass.depthAttachment.texture = depth
                depthPass.depthAttachment.loadAction = .clear
                depthPass.depthAttachment.clearDepth = 1
                check(render(queue, depthPass, depthPipeline, vertices, tint: &tint), "render with a depth attachment completes")
                check(pixel(target, 32, 32) == [0, 255, 0, 255] && pixel(target, 1, 1) == [255, 255, 255, 255], "triangle over a cleared depth attachment: \(pixel(target, 32, 32)) corner \(pixel(target, 1, 1))")
            }
        } catch { check(false, "triangle pipeline: \(error)") }

        // Compiler diagnostics reach the caller.
        if device.supportsRasterization {
            do {
                let options = MTLCompileOptions()
                options.shaderLanguage = .hlsl
                let library = try device.makeLibrary(source: "float4 brokenVertex(uint id : SV_VertexID) : SV_Position { return undefined_symbol; }", options: options)
                let pd = MTLRenderPipelineDescriptor()
                pd.vertexFunction = library.makeFunction(name: "brokenVertex")
                pd.colorAttachments[0].pixelFormat = .bgra8Unorm
                _ = try device.makeRenderPipelineState(descriptor: pd)
                check(false, "broken shader is rejected")
            } catch { check("\(error)".contains("undefined_symbol"), "broken shader diagnostics: \(error)") }
        }
    }
}


/// A form laid out entirely with Auto Layout: labels and fields in a vertical stack.
final class FormViewController: NSViewController, NSSelectorHandling {
    let status = NSTextField(labelWithString: "Fill in the form.")

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Form"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        for (label, placeholder) in [("Name", "Jane Appleseed"), ("Email", "jane@example.com"), ("City", "Cupertino")] {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            let l = NSTextField(labelWithString: label + ":")
            l.setContentHuggingPriority(.required, for: .horizontal)
            let f = NSTextField()
            f.placeholderString = placeholder
            f.widthAnchor.constraint(equalToConstant: 220).isActive = true
            row.addArrangedSubview(l)
            row.addArrangedSubview(f)
            stack.addArrangedSubview(row)
        }
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let ok = NSButton(title: "Submit", target: self, action: Selector(("submit:")))
        ok.keyEquivalent = "\r"
        buttons.addArrangedSubview(NSButton(title: "Reset", target: self, action: Selector(("reset:"))))
        buttons.addArrangedSubview(ok)
        stack.addArrangedSubview(buttons)
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        view = root
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("submit:")): status.stringValue = "Submitted at \(Date())"; return true
        case Selector(("reset:")): status.stringValue = "Fill in the form."; return true
        default: return false
        }
    }
}

/// The everyday controls (search field, token field, path control, stepper, level
/// indicators, progress indicators) on one tab, each wired to the status line.
final class ControlsDemoViewController: NSViewController, NSSelectorHandling, NSTokenFieldDelegate {
    let status = NSTextField(labelWithString: "Type in the search field; tokens split on commas.")
    let search = NSSearchField(frame: .zero)
    let tokens = NSTokenField(frame: .zero)
    let path = NSPathControl(frame: .zero)
    let popUpPath = NSPathControl(frame: .zero)
    let stepper = NSStepper(frame: .zero)
    let stepperValue = NSTextField(frame: .zero)
    let capacity = NSLevelIndicator(frame: .zero)
    let rating = NSLevelIndicator(frame: .zero)
    let relevancy = NSLevelIndicator(frame: .zero)
    let bar = NSProgressIndicator(frame: .zero)
    let busy = NSProgressIndicator(frame: .zero)
    let spinner = NSProgressIndicator(frame: .zero)

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Controls"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 300))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        func row(_ label: String, _ views: [NSView]) -> NSStackView {
            let r = NSStackView()
            r.orientation = .horizontal
            r.spacing = 8
            let l = NSTextField(labelWithString: label)
            l.setContentHuggingPriority(.required, for: .horizontal)
            l.widthAnchor.constraint(equalToConstant: 84).isActive = true
            r.addArrangedSubview(l)
            for v in views { r.addArrangedSubview(v) }
            return r
        }

        search.placeholderString = "Search planets"
        search.target = self
        search.action = Selector(("searched:"))
        search.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let menu = NSMenu(title: "Recents")
        let recentsTitle = NSMenuItem(title: "Recent Searches", action: nil, keyEquivalent: ""); recentsTitle.tag = NSSearchField.recentsTitleMenuItemTag
        let recents = NSMenuItem(title: "%@", action: nil, keyEquivalent: ""); recents.tag = NSSearchField.recentsMenuItemTag
        let none = NSMenuItem(title: "No Recent Searches", action: nil, keyEquivalent: ""); none.tag = NSSearchField.noRecentsMenuItemTag
        let clear = NSMenuItem(title: "Clear Recents", action: nil, keyEquivalent: ""); clear.tag = NSSearchField.clearRecentsMenuItemTag
        for m in [recentsTitle, recents, none, clear] { menu.addItem(m) }
        search.searchMenuTemplate = menu
        stack.addArrangedSubview(row("Search:", [search]))

        tokens.delegate = self
        tokens.objectValue = ["Mercury", "Venus"]
        tokens.placeholderString = "Planets, comma separated"
        tokens.target = self
        tokens.action = Selector(("tokensChanged:"))
        tokens.widthAnchor.constraint(equalToConstant: 280).isActive = true
        stack.addArrangedSubview(row("Tokens:", [tokens]))

        path.url = URL(fileURLWithPath: "/Users/jane/Documents/Planets/Mars.txt")
        path.target = self
        path.action = Selector(("pathClicked:"))
        path.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.addArrangedSubview(row("Path:", [path]))
        popUpPath.pathStyle = .popUp
        popUpPath.url = URL(fileURLWithPath: "/Users/jane/Documents")
        popUpPath.isEditable = true
        popUpPath.target = self
        popUpPath.action = Selector(("pathClicked:"))
        popUpPath.widthAnchor.constraint(equalToConstant: 160).isActive = true
        stack.addArrangedSubview(row("Pop-up:", [popUpPath]))

        stepper.minValue = 0; stepper.maxValue = 10; stepper.integerValue = 3
        stepper.target = self
        stepper.action = Selector(("stepped:"))
        stepperValue.integerValue = 3
        stepperValue.widthAnchor.constraint(equalToConstant: 40).isActive = true
        stepperValue.target = self
        stepperValue.action = Selector(("stepperTyped:"))
        capacity.levelIndicatorStyle = .discreteCapacity
        capacity.minValue = 0; capacity.maxValue = 10; capacity.warningValue = 6; capacity.criticalValue = 8
        capacity.integerValue = 3
        capacity.widthAnchor.constraint(equalToConstant: 120).isActive = true
        capacity.numberOfTickMarks = 11
        stack.addArrangedSubview(row("Stepper:", [stepper, stepperValue, capacity]))

        rating.levelIndicatorStyle = .rating
        rating.minValue = 0; rating.maxValue = 5; rating.integerValue = 4
        rating.isEditable = true
        rating.target = self
        rating.action = Selector(("rated:"))
        relevancy.levelIndicatorStyle = .relevancy
        relevancy.minValue = 0; relevancy.maxValue = 100; relevancy.doubleValue = 65
        relevancy.widthAnchor.constraint(equalToConstant: 100).isActive = true
        stack.addArrangedSubview(row("Levels:", [rating, relevancy]))

        bar.isIndeterminate = false
        bar.minValue = 0; bar.maxValue = 100; bar.doubleValue = 30
        bar.widthAnchor.constraint(equalToConstant: 160).isActive = true
        busy.isIndeterminate = true
        busy.widthAnchor.constraint(equalToConstant: 100).isActive = true
        busy.startAnimation(nil)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        stack.addArrangedSubview(row("Progress:", [bar, busy, spinner]))

        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
    }

    /// `APPKITWIN_STEPPER_PROBE=1` prints the stepper's upper half in X screen pixels once
    /// the window is up, and each stepped value with its offset since the first step of the hold
    /// (tools/linux/stepper-hold.sh; on Windows, read stdout while holding the upper half).
    let probing = ProcessInfo.processInfo.environment["APPKITWIN_STEPPER_PROBE"] != nil
    /// The time of the first step of a hold, for the probe's offsets (reset a second after the last step).
    private var probeStart: CFTimeInterval = 0
    private var probeLast: CFTimeInterval = 0
    override func viewDidAppear() {
        super.viewDidAppear()
        guard probing else { return }
        // A second later the window is placed and laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.printStepperProbe() }
    }
    private func printStepperProbe() {
        guard let w = view.window, let screen = w.screen ?? NSScreen.main else { return }
        let r = stepper.convert(stepper.bounds, to: nil)
        let s = w.convertToScreen(r)
        // X screen coordinates: origin top-left, points to pixels at the backing scale.
        let scale = w.backingScaleFactor
        let x = Int((s.midX * scale).rounded())
        let y = Int(((screen.frame.maxY - (s.minY + s.height * 0.75)) * scale).rounded())
        print("stepper at \(x) \(y)"); fflush(nil)
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("searched:")): status.stringValue = search.stringValue.isEmpty ? "Search cleared." : "Searching for \"\(search.stringValue)\""; return true
        case Selector(("tokensChanged:")): status.stringValue = "Tokens: \((tokens.objectValue as? [Any] ?? []).map { "\($0)" }.joined(separator: " | "))"; return true
        case Selector(("pathClicked:")):
            let p = sender as? NSPathControl
            status.stringValue = "Clicked \(p?.clickedPathItem?.title ?? "?") → \(p?.clickedPathItem?.url?.path ?? p?.url?.path ?? "")"
            return true
        case Selector(("stepped:")):
            stepperValue.integerValue = stepper.integerValue
            capacity.integerValue = stepper.integerValue
            bar.doubleValue = Double(stepper.integerValue) * 10
            status.stringValue = "Stepper: \(stepper.integerValue)"
            if probing {
                // "stepper value N +0.512s": the offset since the first step of this hold, so a
                // log shows the autorepeat delay (0.5 s) and rate (10 per second) exactly.
                let now = CACurrentMediaTime()
                if now - probeLast > 1 { probeStart = now }
                probeLast = now
                print(String(format: "stepper value %d +%.3fs", stepper.integerValue, now - probeStart)); fflush(nil)
            }
            return true
        case Selector(("stepperTyped:")):
            stepper.integerValue = stepperValue.integerValue
            capacity.integerValue = stepper.integerValue
            return true
        case Selector(("rated:")): status.stringValue = "Rating: \(rating.integerValue) of 5"; return true
        default: return false
        }
    }

    static let planets = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
        let matches = ControlsDemoViewController.planets.filter { $0.lowercased().hasPrefix(substring.lowercased()) }
        return matches.isEmpty ? nil : matches
    }
    func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool { (representedObject as? String) == "Earth" }
    func tokenField(_ tokenField: NSTokenField, menuForRepresentedObject representedObject: Any) -> NSMenu? {
        let m = NSMenu(title: "")
        m.addItem(NSMenuItem(title: "Home planet", action: nil, keyEquivalent: ""))
        return m
    }
}

/// The date picker's styles: textual with a stepper, plain textual (time only), and the
/// graphical calendar and clock, all on one date.
final class DateDemoViewController: NSViewController, NSSelectorHandling {
    let status = NSTextField(labelWithString: "Pick a date.")
    let textual = NSDatePicker(frame: .zero)
    let timeOnly = NSDatePicker(frame: .zero)
    let graphical = NSDatePicker(frame: .zero)
    /// A fixed date so the renders compare across platforms.
    static let demoDate: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 10; c.hour = 14; c.minute = 30
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Date"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 300))
        let posix = Locale(identifier: "en_US_POSIX")
        let utc = TimeZone(identifier: "UTC")
        for p in [textual, timeOnly, graphical] {
            p.locale = posix
            p.timeZone = utc
            p.dateValue = DateDemoViewController.demoDate
            p.target = self
            p.action = Selector(("dateChanged:"))
            p.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(p)
        }
        timeOnly.datePickerStyle = .textField
        timeOnly.datePickerElements = .hourMinute
        graphical.datePickerStyle = .clockAndCalendar
        graphical.minDate = DateDemoViewController.demoDate.addingTimeInterval(-20 * 86400)
        let l1 = NSTextField(labelWithString: "Stepper:"), l2 = NSTextField(labelWithString: "Time:")
        for l in [l1, l2] { l.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(l) }
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            l1.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            l1.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            textual.leadingAnchor.constraint(equalTo: l1.trailingAnchor, constant: 8),
            textual.centerYAnchor.constraint(equalTo: l1.centerYAnchor),
            l2.leadingAnchor.constraint(equalTo: textual.trailingAnchor, constant: 16),
            l2.centerYAnchor.constraint(equalTo: l1.centerYAnchor),
            timeOnly.leadingAnchor.constraint(equalTo: l2.trailingAnchor, constant: 8),
            timeOnly.centerYAnchor.constraint(equalTo: l1.centerYAnchor),
            graphical.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            graphical.topAnchor.constraint(equalTo: textual.bottomAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action == Selector(("dateChanged:")), let p = sender as? NSDatePicker else { return false }
        for other in [textual, timeOnly, graphical] where other !== p { other.dateValue = p.dateValue }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        status.stringValue = "Date: \(f.string(from: p.dateValue)) UTC"
        return true
    }
}

/// A coloured pane with a centred label, for the split view.
/// An NSTableView in a scroll view (sortable headers, multiple selection) over a
/// segmented control that filters the rows.
final class TableDemoViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSelectorHandling {
    struct Planet { let name: String; let moons: Int; let kind: String }
    let all = [Planet(name: "Mercury", moons: 0, kind: "Rocky"), Planet(name: "Venus", moons: 0, kind: "Rocky"), Planet(name: "Earth", moons: 1, kind: "Rocky"),
               Planet(name: "Mars", moons: 2, kind: "Rocky"), Planet(name: "Jupiter", moons: 95, kind: "Gas"), Planet(name: "Saturn", moons: 146, kind: "Gas"),
               Planet(name: "Uranus", moons: 28, kind: "Ice"), Planet(name: "Neptune", moons: 16, kind: "Ice")]
    var rows: [Planet] = []
    let table = NSTableView(frame: .zero)
    let filter = NSSegmentedControl(labels: ["All", "Rocky", "Gas", "Ice"], trackingMode: .selectOne, target: nil, action: nil)
    let status = NSTextField(labelWithString: "Click a header to sort; Cmd and Shift extend the selection.")

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Table"
        rows = all
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        filter.selectedSegment = 0
        filter.target = self
        filter.action = Selector(("filterChanged:"))
        filter.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(filter)
        let columns: [(String, String, CGFloat, NSSortDescriptor)] = [
            ("name", "Planet", 140, sortDescriptor(key: "name", keyPath: \Planet.name)),
            ("moons", "Moons", 70, sortDescriptor(key: "moons", keyPath: \Planet.moons)),
            ("kind", "Kind", 80, sortDescriptor(key: "kind", keyPath: \Planet.kind)),
        ]
        for (id, title, width, prototype) in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.sortDescriptorPrototype = prototype
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.target = self
        table.action = Selector(("rowClicked:"))
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            filter.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            filter.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: filter.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        switch tableColumn?.identifier.rawValue {
        case "moons": return rows[row].moons
        case "kind": return rows[row].kind
        default: return rows[row].name
        }
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        applyFilterAndSort()
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let names = table.selectedRowIndexes.map { rows[$0].name }
        status.stringValue = names.isEmpty ? "Nothing selected." : "Selected: " + names.joined(separator: ", ")
    }

    private func applyFilterAndSort() {
        let kinds = ["All", "Rocky", "Gas", "Ice"]
        let kind = kinds[max(0, filter.selectedSegment)]
        rows = kind == "All" ? all : all.filter { $0.kind == kind }
        if let d = table.sortDescriptors.first {
            rows.sort { a, b in
                if sorts(d, by: "moons", keyPath: \Planet.moons) { return d.ascending ? a.moons < b.moons : a.moons > b.moons }
                if sorts(d, by: "kind", keyPath: \Planet.kind) { return d.ascending ? a.kind < b.kind : a.kind > b.kind }
                return d.ascending ? a.name < b.name : a.name > b.name
            }
        }
        table.reloadData()
    }

    // Apple's Foundation sorts by key-value coding keys; swift-corelibs-foundation only by
    // key paths (its `key` is unavailable). The table compares descriptors either way.
    private func sortDescriptor<V: Comparable>(key: String, keyPath: KeyPath<Planet, V>) -> NSSortDescriptor {
        #if canImport(Darwin)
        return NSSortDescriptor(key: key, ascending: true)
        #else
        return NSSortDescriptor(keyPath: keyPath, ascending: true)
        #endif
    }
    private func sorts<V: Comparable>(_ d: NSSortDescriptor, by key: String, keyPath: KeyPath<Planet, V>) -> Bool {
        #if canImport(Darwin)
        return d.key == key
        #else
        return d.keyPath == (keyPath as AnyKeyPath)
        #endif
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action.description {
        case "filterChanged:":
            table.deselectAll(nil)      // the rows change identity: reloadData keeps selection by index
            applyFilterAndSort()
            return true
        case "rowClicked:": return true
        default: return false
        }
    }
}

/// Popovers of each behaviour on push buttons (the application-defined one closes from
/// its own button and detaches when dragged), and an NSSwitch. APPKITWIN_POPOVER_OPEN=1
/// shows the transient popover on launch (for screenshots).
final class PopoverDemoViewController: NSViewController, NSPopoverDelegate, NSSelectorHandling {
    let transientButton = NSButton(title: "Transient", target: nil, action: nil)
    let semitransientButton = NSButton(title: "Semitransient", target: nil, action: nil)
    let definedButton = NSButton(title: "Application-defined", target: nil, action: nil)
    let toggle = NSSwitch(frame: .zero)
    let toggleLabel = NSTextField(labelWithString: "Wi-Fi")
    let status = NSTextField(labelWithString: "Click a button for a popover; Space toggles the switch.")
    var popovers: [NSPopover.Behavior: NSPopover] = [:]

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Popover"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        for (b, action) in [(transientButton, "showTransient:"), (semitransientButton, "showSemitransient:"), (definedButton, "showDefined:")] {
            b.target = self
            b.action = Selector((action))
            buttons.addArrangedSubview(b)
        }
        toggle.target = self
        toggle.action = Selector(("switched:"))
        toggle.state = .on
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(toggleLabel)
        row.addArrangedSubview(toggle)
        for v in [buttons, row, status] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            buttons.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            row.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 28),
            row.leadingAnchor.constraint(equalTo: buttons.leadingAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if ProcessInfo.processInfo.environment["APPKITWIN_POPOVER_OPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                view.window?.layoutIfNeeded()
                show(.transient, from: transientButton)
            }
        }
    }

    /// One popover per behaviour, made on first use; the application-defined one carries
    /// a Close button and detaches into a titled window when dragged.
    func popover(for behavior: NSPopover.Behavior) -> NSPopover {
        if let p = popovers[behavior] { return p }
        let p = NSPopover()
        p.behavior = behavior
        p.delegate = self
        let vc = NSViewController(nibName: nil, bundle: nil)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: behavior == .applicationDefined ? 96 : 64))
        let name: String
        switch behavior {
        case .transient: name = "Transient: a click anywhere outside closes it."
        case .semitransient: name = "Semitransient: a click in the parent window closes it."
        default: name = "Application-defined: only Close closes it. Drag to detach."
        }
        let text = NSTextField(wrappingLabelWithString: name)
        text.frame = NSRect(x: 12, y: content.frame.height - 48, width: 196, height: 40)
        content.addSubview(text)
        if behavior == .applicationDefined {
            let close = NSButton(title: "Close", target: self, action: Selector(("closeDefined:")))
            close.frame = NSRect(x: 12, y: 10, width: 80, height: 24)
            content.addSubview(close)
        }
        vc.view = content
        vc.title = "Popover"
        p.contentViewController = vc
        popovers[behavior] = p
        return p
    }

    func show(_ behavior: NSPopover.Behavior, from button: NSButton) {
        let p = popover(for: behavior)
        if p.isShown { p.close(); return }
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { popover.behavior == .applicationDefined }
    func popoverDidShow(_ notification: Notification) {
        if let p = notification.object as? NSPopover { status.stringValue = "Popover shown (\(p.behavior == .transient ? "transient" : p.behavior == .semitransient ? "semitransient" : "application-defined"))" }
    }
    func popoverDidClose(_ notification: Notification) {
        let reason = (notification.userInfo?[NSPopover.closeReasonUserInfoKey] as? NSPopover.CloseReason) == .detachToWindow ? "detached" : "closed"
        status.stringValue = "Popover \(reason)"
    }
    func popoverDidDetach(_ popover: NSPopover) { status.stringValue = "Popover detached into a window" }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action.description {
        case "showTransient:": show(.transient, from: transientButton); return true
        case "showSemitransient:": show(.semitransient, from: semitransientButton); return true
        case "showDefined:": show(.applicationDefined, from: definedButton); return true
        case "closeDefined:": popovers[.applicationDefined]?.performClose(sender); return true
        case "switched:": status.stringValue = "Switch is \(toggle.state == .on ? "on" : "off")"; return true
        default: return false
        }
    }
}

/// Two NSComboBoxes: one over its own items with completion, one over a data source.
/// APPKITWIN_COMBO_POPUP=1 opens the first one's list on launch (for screenshots).
final class ComboDemoViewController: NSViewController, NSComboBoxDataSource, NSComboBoxDelegate, NSSelectorHandling {
    let fruits = ["Apple", "Apricot", "Banana", "Blueberry", "Cherry", "Fig", "Grape", "Kiwi", "Lemon", "Mango", "Orange", "Pear"]
    let sizes = ["Small", "Medium", "Large", "Extra large"]
    let fruit = NSComboBox(frame: .zero)
    let size = NSComboBox(frame: .zero)
    let status = NSTextField(labelWithString: "Type a fruit (it completes), or open the list; Down opens it too.")

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Combo"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let fruitLabel = NSTextField(labelWithString: "Fruit:")
        let sizeLabel = NSTextField(labelWithString: "Size:")
        fruit.addItems(withObjectValues: fruits)
        fruit.completes = true
        fruit.placeholderString = "Pick or type a fruit"
        fruit.numberOfVisibleItems = 6
        fruit.delegate = self
        fruit.target = self
        fruit.action = Selector(("fruitChanged:"))
        size.usesDataSource = true
        size.dataSource = self
        size.delegate = self
        size.isEditable = false
        size.selectItem(at: 1)
        size.target = self
        size.action = Selector(("sizeChanged:"))
        for v in [fruitLabel, sizeLabel, fruit, size, status] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            fruitLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            fruitLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            fruit.centerYAnchor.constraint(equalTo: fruitLabel.centerYAnchor),
            fruit.leadingAnchor.constraint(equalTo: fruitLabel.trailingAnchor, constant: 8),
            fruit.widthAnchor.constraint(equalToConstant: 200),
            sizeLabel.topAnchor.constraint(equalTo: fruitLabel.bottomAnchor, constant: 24),
            sizeLabel.leadingAnchor.constraint(equalTo: fruitLabel.leadingAnchor),
            size.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            size.leadingAnchor.constraint(equalTo: fruit.leadingAnchor),
            size.widthAnchor.constraint(equalTo: fruit.widthAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if ProcessInfo.processInfo.environment["APPKITWIN_COMBO_POPUP"] == "1" {
            fruit.selectItem(at: 2)
            // Once the windows are laid out and mapped and the initial key-window hand-off is
            // over (an X11 window resigning key dismisses the list), so it hangs under the field.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [fruit] in
                fruit.window?.layoutIfNeeded()
                _ = fruit.accessibilityPerformShowMenu()
            }
        }
    }

    func numberOfItems(in comboBox: NSComboBox) -> Int { sizes.count }
    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? { sizes[index] }
    func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int { sizes.firstIndex(of: string) ?? NSNotFound }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let c = notification.object as? NSComboBox else { return }
        status.stringValue = "\(c === fruit ? "Fruit" : "Size") selected: \(c.objectValueOfSelectedItem.map { "\($0)" } ?? "none") (item \(c.indexOfSelectedItem))"
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action.description {
        case "fruitChanged:": status.stringValue = "Fruit: \(fruit.stringValue)"; return true
        case "sizeChanged:": status.stringValue = "Size: \(size.stringValue)"; return true
        default: return false
        }
    }
}

/// An NSOutlineView over a small folder tree: disclosure triangles, two columns,
/// Option-click and the arrow keys expand and collapse.
final class OutlineDemoViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node {
        let name: String
        let kind: String
        let children: [Node]
        init(_ name: String, kind: String = "Folder", _ children: [Node] = []) { self.name = name; self.kind = kind; self.children = children }
    }
    let roots: [Node] = [
        Node("Documents", [
            Node("Reports", [Node("Q1.pdf", kind: "PDF"), Node("Q2.pdf", kind: "PDF")]),
            Node("Notes.txt", kind: "Text"),
            Node("Budget.numbers", kind: "Spreadsheet"),
        ]),
        Node("Pictures", [Node("Holiday", [Node("beach.png", kind: "Image"), Node("sunset.png", kind: "Image")]), Node("cat.jpg", kind: "Image")]),
        Node("Music", [Node("song.mp3", kind: "Audio")]),
        Node("README.md", kind: "Markdown"),
    ]
    let outline = NSOutlineView(frame: .zero)
    let status = NSTextField(labelWithString: "Click a triangle (Option-click for the subtree); Left and Right collapse and expand.")

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Outline"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.title = "Name"
        name.width = 220
        let kind = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kind.title = "Kind"
        kind.width = 110
        outline.addTableColumn(name)
        outline.addTableColumn(kind)
        outline.dataSource = self
        outline.delegate = self
        outline.rowHeight = 22
        outline.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = outline
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
        outline.expandItem(roots[0])
        outline.expandItem(roots[1], expandChildren: true)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { ((item as? Node)?.children ?? roots).count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node)?.children ?? roots)[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Node)?.children.isEmpty ?? true) }
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        guard let n = item as? Node else { return nil }
        return tableColumn?.identifier.rawValue == "kind" ? n.kind : n.name
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        if let n = outline.item(atRow: outline.selectedRow) as? Node { status.stringValue = "Selected: \(n.name) (level \(outline.level(forItem: n)))" }
        else { status.stringValue = "Nothing selected." }
    }
}

/// The Layout Demo's Pages tab: an `NSPageController` over three pages with Back and
/// Next buttons, a segmented control bound through `takeSelectedIndexFrom`, a transition
/// style pop-up, and a trailing title bar accessory while the tab shows. The pages
/// highlight under the pointer through `NSTrackingArea` (ADR-0023).
final class PagesDemoViewController: NSViewController, NSPageControllerDelegate, NSSelectorHandling {
    /// A page that lights up while the pointer is over it and shows the hand over its hot spot.
    final class HoverPage: NSView {
        var color = NSColor.white
        var name = ""
        var hovering = false { didSet { needsDisplay = true } }
        var inHotSpot = false { didSet { needsDisplay = true } }
        var hotSpot: NSRect { NSRect(x: bounds.maxX - 70, y: bounds.minY + 16, width: 54, height: 54) }
        override var isOpaque: Bool { true }
        override func updateTrackingAreas() {
            trackingAreas.forEach { removeTrackingArea($0) }
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: ["part": "page"]))
            addTrackingArea(NSTrackingArea(rect: hotSpot, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow], owner: self, userInfo: ["part": "hot"]))
            super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) {
            if event.trackingArea?.userInfo?["part"] as? String == "hot" { inHotSpot = true } else { hovering = true }
        }
        override func mouseExited(with event: NSEvent) {
            if event.trackingArea?.userInfo?["part"] as? String == "hot" { inHotSpot = false } else { hovering = false }
        }
        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func draw(_ dirtyRect: NSRect) {
            (hovering ? color.blended(withFraction: 0.15, of: .black) ?? color : color).setFill()
            NSBezierPath(rect: bounds).fill()
            if hovering {
                // Orange, so it reads apart from the blue keyboard focus ring.
                NSColor.systemOrange.setStroke()
                let ring = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
                ring.lineWidth = 3
                ring.stroke()
            }
            (inHotSpot ? NSColor.systemOrange : NSColor.labelColor.withAlphaComponent(0.4)).setFill()
            NSBezierPath(roundedRect: hotSpot, xRadius: 8, yRadius: 8).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.labelColor]
            name.draw(at: NSPoint(x: 20, y: bounds.maxY - 50), withAttributes: attrs)
            let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            "Hover to highlight; the square shows the hand. Scroll, swipe or arrow to page.".draw(at: NSPoint(x: 20, y: bounds.minY + 16), withAttributes: hint)
        }
    }

    let pages = NSPageController()
    let picker = NSSegmentedControl(labels: ["Red", "Green", "Blue"], trackingMode: .selectOne, target: nil, action: nil)
    let style = NSPopUpButton(frame: .zero, pullsDown: false)
    let status = NSTextField(labelWithString: "Page 1 of 3")
    let accessory = NSTitlebarAccessoryViewController()
    let objects: [(String, NSColor)] = [("Red", NSColor(red: 1, green: 0.85, blue: 0.85, alpha: 1)), ("Green", NSColor(red: 0.85, green: 1, blue: 0.85, alpha: 1)), ("Blue", NSColor(red: 0.85, green: 0.9, blue: 1, alpha: 1))]

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Pages"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let back = NSButton(title: "Back", target: pages, action: Selector(("navigateBack:")))
        let next = NSButton(title: "Next", target: pages, action: Selector(("navigateForward:")))
        picker.target = pages
        picker.action = Selector(("takeSelectedIndexFrom:"))
        picker.selectedSegment = 0
        style.addItems(withTitles: ["Stack history", "Stack book", "Horizontal strip"])
        style.target = self
        style.action = Selector(("styleChanged:"))
        pages.delegate = self
        pages.arrangedObjects = objects.map { $0.0 }
        let bar = NSStackView(views: [back, next, picker, style])
        bar.orientation = .horizontal
        bar.spacing = 8
        for v in [bar, pages.view, status] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            pages.view.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            pages.view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            pages.view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            pages.view.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
        // The title bar accessory: a label at the trailing end of the title bar.
        let label = NSTextField(labelWithString: "Pages ⌘")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.sizeToFit()
        accessory.view = label
        accessory.layoutAttribute = .trailing
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let w = view.window, !w.titlebarAccessoryViewControllers.contains(where: { $0 === accessory }) { w.addTitlebarAccessoryViewController(accessory) }
    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        accessory.removeFromParent()
    }

    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier { "page" }
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
        let vc = NSViewController()
        vc.view = HoverPage(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        return vc
    }
    func pageController(_ pageController: NSPageController, prepare viewController: NSViewController, with object: Any?) {
        guard let page = viewController.view as? HoverPage, let name = object as? String, let entry = objects.first(where: { $0.0 == name }) else { return }
        page.name = name
        page.color = entry.1
        page.needsDisplay = true
    }
    func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
        status.stringValue = "Page \(pageController.selectedIndex + 1) of 3"
        picker.selectedSegment = pageController.selectedIndex
        pageController.completeTransition()
    }
    func pageControllerWillStartLiveTransition(_ pageController: NSPageController) { status.stringValue = "Paging…" }
    func pageControllerDidEndLiveTransition(_ pageController: NSPageController) { status.stringValue = "Page \(pageController.selectedIndex + 1) of 3" }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch NSStringFromSelector(action) {
        case "styleChanged:":
            pages.transitionStyle = [.stackHistory, .stackBook, .horizontalStrip][max(0, style.indexOfSelectedItem)]
            return true
        default: return false
        }
    }
}

// MARK: Collection, grid and box tabs (ADR-0020)

/// An `NSCollectionView` of colour swatches in two sections under a flow layout with
/// section headers: click, Cmd and Shift select; arrows move; the header's button
/// collapses its section.
final class CollectionDemoViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, NSSelectorHandling {
    final class SwatchItem: NSCollectionViewItem {
        final class SwatchView: NSView {
            weak var item: SwatchItem?
            var color = NSColor.gray
            override func draw(_ dirtyRect: NSRect) {
                let selected = item?.isSelected == true
                let highlighted = item?.highlightState == .forSelection
                if selected || highlighted {
                    (selected ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.5)).setFill()
                    NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
                }
                color.setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 4, yRadius: 4).fill()
            }
        }
        override func loadView() {
            let v = SwatchView(frame: NSRect(x: 0, y: 0, width: 56, height: 56))
            v.item = self
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 9)
            label.alignment = .center
            label.frame = NSRect(x: 3, y: 40, width: 50, height: 13)
            label.autoresizingMask = [.width]
            v.addSubview(label)
            textField = label
            view = v
        }
    }
    final class Header: NSView, NSCollectionViewSectionHeaderView {
        let label = NSTextField(labelWithString: "")
        var sectionCollapseButton: NSButton?
        required init?(coder: NSCoder) { super.init(coder: coder); setUp() }
        override init(frame: NSRect) { super.init(frame: frame); setUp() }
        private func setUp() {
            label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
            label.frame = NSRect(x: 6, y: 3, width: 200, height: 16)
            addSubview(label)
            let b = NSButton(title: "Hide", target: nil, action: Selector(("toggleSectionCollapse:")))
            b.controlSize = .small
            b.bezelStyle = .rounded
            addSubview(b)
            sectionCollapseButton = b
            placeButton()
        }
        // The header is made with a zero frame and sized by the collection view afterwards,
        // so the button is placed from the bounds rather than by an autoresizing mask.
        private func placeButton() { sectionCollapseButton?.frame = NSRect(x: max(0, bounds.width - 66), y: 0, width: 60, height: 22) }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            placeButton()
        }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: bounds).fill()
            NSColor.separatorColor.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)).fill()
        }
    }
    struct Swatch { let name: String; let color: NSColor }
    let sections: [(String, [Swatch])] = [
        ("Warm", [Swatch(name: "Red", color: .systemRed), Swatch(name: "Orange", color: .systemOrange), Swatch(name: "Yellow", color: .systemYellow), Swatch(name: "Pink", color: .systemPink), Swatch(name: "Brown", color: .systemBrown)]),
        ("Cool", [Swatch(name: "Green", color: .systemGreen), Swatch(name: "Teal", color: .systemTeal), Swatch(name: "Blue", color: .systemBlue), Swatch(name: "Indigo", color: .systemIndigo), Swatch(name: "Purple", color: .systemPurple), Swatch(name: "Mint", color: .systemMint)]),
    ]
    let collection = NSCollectionView(frame: .zero)
    let status = NSTextField(labelWithString: "Click a swatch; Cmd and Shift extend the selection; arrows move.")

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Collection"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let flow = NSCollectionViewFlowLayout()
        flow.itemSize = NSSize(width: 56, height: 56)
        flow.minimumInteritemSpacing = 8
        flow.minimumLineSpacing = 8
        flow.sectionInset = NSEdgeInsets(top: 6, left: 8, bottom: 8, right: 8)
        flow.headerReferenceSize = NSSize(width: 0, height: 22)
        flow.sectionHeadersPinToVisibleBounds = true
        collection.collectionViewLayout = flow
        collection.register(SwatchItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("swatch"))
        collection.register(Header.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader, withIdentifier: NSUserInterfaceItemIdentifier("header"))
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.backgroundColors = [.controlBackgroundColor]
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = collection
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
        // `APPKITWIN_COLLECTION_SELECT=1` selects two swatches on launch (for the screenshots).
        if ProcessInfo.processInfo.environment["APPKITWIN_COLLECTION_SELECT"] != nil {
            collection.selectionIndexPaths = [IndexPath(item: 1, section: 0), IndexPath(item: 2, section: 1)]
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].1.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("swatch"), for: indexPath) as! SwatchItem
        let swatch = sections[indexPath.section].1[indexPath.item]
        (item.view as? SwatchItem.SwatchView)?.color = swatch.color
        item.textField?.stringValue = swatch.name
        item.view.needsDisplay = true
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier("header"), for: indexPath) as! Header
        header.label.stringValue = sections[indexPath.section].0
        let flow = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout
        header.sectionCollapseButton?.title = flow?.section(atIndexIsCollapsed: indexPath.section) == true ? "Show" : "Hide"
        header.sectionCollapseButton?.target = self
        header.sectionCollapseButton?.action = Selector(("toggleSection:"))
        header.sectionCollapseButton?.tag = indexPath.section
        return header
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updateStatus() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateStatus() }
    private func updateStatus() {
        let names = collection.selectionIndexPaths.sorted().map { sections[$0.section].1[$0.item].name }
        status.stringValue = names.isEmpty ? "Nothing selected." : "Selected: " + names.joined(separator: ", ")
    }
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action.description == "toggleSection:", let button = sender as? NSButton else { return false }
        collection.toggleSectionCollapse(button.tag)
        button.title = (collection.collectionViewLayout as? NSCollectionViewFlowLayout)?.section(atIndexIsCollapsed: button.tag) == true ? "Show" : "Hide"
        return true
    }
}

// MARK: Diffable data sources tab (ADR-0029)

/// A table (with section header rows) and a collection view, each driven by a diffable data
/// source from the same snapshot. The buttons change the snapshot and apply it to both:
/// Shuffle reorders the items across the two sections, Insert adds one, Delete removes the
/// table's selected row (or the first item), Reload redraws every item with a new generation.
/// `APPKITWIN_DIFFABLE_STEPS=shuffle,insert,delete,reload` runs steps on launch (screenshots).
final class DiffableDemoViewController: NSViewController, NSSelectorHandling {
    let table = NSTableView(frame: .zero)
    let collection = NSCollectionView(frame: .zero)
    let status = NSTextField(labelWithString: "Shuffle, insert, delete or reload: both views follow the snapshot.")
    var tableSource: NSTableViewDiffableDataSource<String, Int>!
    var collectionSource: NSCollectionViewDiffableDataSource<String, Int>!
    var model: [(String, [Int])] = [("Warm", [1, 2, 3, 4]), ("Cool", [5, 6, 7, 8])]
    var next = 9
    var generation = 1
    var seed: UInt64 = 2026

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Diffable"
    }
    required init?(coder: NSCoder) { nil }

    static func color(_ n: Int) -> NSColor {
        NSColor(calibratedHue: CGFloat((n * 37) % 360) / 360, saturation: 0.55, brightness: 0.9, alpha: 1)
    }
    func label(_ n: Int) -> String { generation > 1 ? "Item \(n) · r\(generation)" : "Item \(n)" }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 260))
        // The table: one column, a header row per section.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.title = "Item"
        column.width = 160
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.style = .fullWidth
        tableSource = NSTableViewDiffableDataSource<String, Int>(tableView: table) { [unowned self] tableView, _, _, n in
            let id = NSUserInterfaceItemIdentifier("diffableCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? Self.makeCell(id)
            cell.textField?.stringValue = self.label(n)
            cell.imageView?.image = Self.dot(Self.color(n))
            return cell
        }
        tableSource.sectionHeaderViewProvider = { tableView, _, section in
            let id = NSUserInterfaceItemIdentifier("diffableHeader")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? Self.makeCell(id, header: true)
            cell.textField?.stringValue = section
            return cell
        }
        let tableScroll = NSScrollView()
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.documentView = table
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tableScroll)

        // The collection: swatches in two sections.
        let flow = NSCollectionViewFlowLayout()
        flow.itemSize = NSSize(width: 56, height: 56)
        flow.minimumInteritemSpacing = 6
        flow.minimumLineSpacing = 6
        flow.sectionInset = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        collection.collectionViewLayout = flow
        collection.register(CollectionDemoViewController.SwatchItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("swatch"))
        collection.backgroundColors = [.controlBackgroundColor]
        collectionSource = NSCollectionViewDiffableDataSource<String, Int>(collectionView: collection) { [unowned self] cv, ip, n in
            let item = cv.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("swatch"), for: ip) as! CollectionDemoViewController.SwatchItem
            (item.view as? CollectionDemoViewController.SwatchItem.SwatchView)?.color = Self.color(n)
            item.textField?.stringValue = self.generation > 1 ? "\(n) r\(self.generation)" : "\(n)"
            item.view.needsDisplay = true
            return item
        }
        let collectionScroll = NSScrollView()
        collectionScroll.hasVerticalScroller = true
        collectionScroll.borderType = .bezelBorder
        collectionScroll.documentView = collection
        collectionScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(collectionScroll)

        let buttons = NSStackView(views: ["Shuffle", "Insert", "Delete", "Reload"].map { title in
            let b = NSButton(title: title, target: self, action: Selector(("diffable\(title):")))
            b.bezelStyle = .rounded
            return b
        })
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(buttons)
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            buttons.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tableScroll.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            tableScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tableScroll.widthAnchor.constraint(equalToConstant: 180),
            tableScroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            collectionScroll.topAnchor.constraint(equalTo: tableScroll.topAnchor),
            collectionScroll.leadingAnchor.constraint(equalTo: tableScroll.trailingAnchor, constant: 10),
            collectionScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            collectionScroll.bottomAnchor.constraint(equalTo: tableScroll.bottomAnchor),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
        apply(animating: false)
        for step in (ProcessInfo.processInfo.environment["APPKITWIN_DIFFABLE_STEPS"] ?? "").split(separator: ",") {
            perform(String(step))
        }
    }

    static func makeCell(_ id: NSUserInterfaceItemIdentifier, header: Bool = false) -> NSTableCellView {
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 160, height: 20))
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.frame = NSRect(x: header ? 4 : 24, y: 2, width: 140, height: 16)
        text.autoresizingMask = [.width]
        if header { text.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize); text.textColor = .secondaryLabelColor }
        cell.addSubview(text)
        cell.textField = text
        if !header {
            let image = NSImageView(frame: NSRect(x: 4, y: 3, width: 14, height: 14))
            cell.addSubview(image)
            cell.imageView = image
        }
        return cell
    }

    static func dot(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 12, height: 12)).fill()
        image.unlockFocus()
        return image
    }

    func snapshot(reloading: Bool = false) -> NSDiffableDataSourceSnapshot<String, Int> {
        var s = NSDiffableDataSourceSnapshot<String, Int>()
        for (section, items) in model {
            s.appendSections([section])
            s.appendItems(items, toSection: section)
        }
        if reloading { s.reloadItems(s.itemIdentifiers) }
        return s
    }

    func apply(animating: Bool, reloading: Bool = false) {
        let s = snapshot(reloading: reloading)
        tableSource.apply(s, animatingDifferences: animating)
        collectionSource.apply(s, animatingDifferences: animating)
        status.stringValue = "\(s.numberOfItems) items in \(s.numberOfSections) sections."
    }

    /// A small deterministic generator, so scripted runs render the same on every platform.
    func random(_ n: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(max(1, n)))
    }

    func perform(_ step: String) {
        switch step {
        case "shuffle":
            var all = model.flatMap { $0.1 }
            for i in stride(from: all.count - 1, to: 0, by: -1) { all.swapAt(i, random(i + 1)) }
            let split = all.count / 2
            model = [(model[0].0, Array(all[..<split])), (model[1].0, Array(all[split...]))]
        case "insert":
            let section = random(2)
            model[section].1.insert(next, at: random(model[section].1.count + 1))
            next += 1
        case "delete":
            let selected = table.selectedRow >= 0 ? tableSource.itemIdentifier(forRow: table.selectedRow) : nil
            guard let victim = selected ?? model.flatMap({ $0.1 }).first else { return }
            for i in model.indices { model[i].1.removeAll { $0 == victim } }
        case "reload":
            generation += 1
            apply(animating: true, reloading: true)
            return
        default:
            return
        }
        apply(animating: true)
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        let name = action.description
        guard name.hasPrefix("diffable"), name.hasSuffix(":") else { return false }
        perform(String(name.dropFirst("diffable".count).dropLast()).lowercased())
        return true
    }
}

/// An `NSGridView` form: labels and fields in two columns, a merged title row, a row
/// that can be hidden, and trailing/centre placements.
final class GridDemoViewController: NSViewController, NSSelectorHandling {
    let grid: NSGridView
    let optionalRow: NSGridRow
    let status = NSTextField(labelWithString: "The grid sizes its columns to the content.")

    init() {
        let heading = NSTextField(labelWithString: "Shipping address")
        heading.font = NSFont.boldSystemFont(ofSize: 13)
        func field(_ placeholder: String, width: CGFloat = 180) -> NSTextField {
            let f = NSTextField(string: "")
            f.placeholderString = placeholder
            f.widthAnchor.constraint(equalToConstant: width).isActive = true
            return f
        }
        let rows: [[NSView]] = [
            [heading, NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Name:"), field("Full name")],
            [NSTextField(labelWithString: "Street:"), field("Street and number")],
            [NSTextField(labelWithString: "Company:"), field("Optional")],
            [NSTextField(labelWithString: "City:"), field("City", width: 120)],
        ]
        grid = NSGridView(views: rows)
        optionalRow = grid.row(at: 3)
        super.init(nibName: nil, bundle: nil)
        title = "Grid"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 0, length: 1))
        grid.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .leading
        grid.row(at: 0).bottomPadding = 4
        grid.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(grid)
        let toggle = NSButton(checkboxWithTitle: "Show the company row", target: self, action: Selector(("toggleRow:")))
        toggle.state = .on
        toggle.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toggle)
        status.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(status)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            toggle.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            toggle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        view = root
        if ProcessInfo.processInfo.environment["APPKITWIN_GRID_HIDE_ROW"] != nil { optionalRow.isHidden = true; toggle.state = .off }
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action.description == "toggleRow:" else { return false }
        optionalRow.isHidden = (sender as? NSButton)?.state != .on
        status.stringValue = optionalRow.isHidden ? "The company row is hidden; the rows below moved up." : "The grid sizes its columns to the content."
        return true
    }
}

/// `NSBox` in its types: a titled primary box around controls, a custom box with its
/// own fill, border and corner radius, a separator, and the title positions.
final class BoxDemoViewController: NSViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Box"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let primary = NSBox(frame: NSRect(x: 16, y: 14, width: 190, height: 120))
        primary.title = "Options"
        let check1 = NSButton(checkboxWithTitle: "Enable sound", target: nil, action: nil)
        check1.state = .on
        check1.frame = NSRect(x: 4, y: 56, width: 160, height: 20)
        let check2 = NSButton(checkboxWithTitle: "Show badges", target: nil, action: nil)
        check2.frame = NSRect(x: 4, y: 30, width: 160, height: 20)
        let check3 = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)
        check3.frame = NSRect(x: 4, y: 4, width: 160, height: 20)
        for c in [check1, check2, check3] { primary.contentView?.addSubview(c) }
        root.addSubview(primary)

        let custom = NSBox(frame: NSRect(x: 220, y: 14, width: 184, height: 120))
        custom.boxType = .custom
        custom.title = "Custom"
        custom.titlePosition = .belowTop
        custom.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12)     // reads in light and dark appearances
        custom.borderColor = .systemBlue
        custom.borderWidth = 2
        custom.cornerRadius = 10
        let note = NSTextField(labelWithString: "Fill, border and\ncorner radius of its own.")
        note.frame = NSRect(x: 4, y: 20, width: 160, height: 36)
        custom.contentView?.addSubview(note)
        root.addSubview(custom)

        let separator = NSBox(frame: NSRect(x: 16, y: 150, width: 388, height: 1))
        separator.boxType = .separator
        root.addSubview(separator)

        let positions: [(String, NSBox.TitlePosition)] = [("Above top", .aboveTop), ("At bottom", .atBottom), ("Below bottom", .belowBottom)]
        for (i, (name, position)) in positions.enumerated() {
            let b = NSBox(frame: NSRect(x: 16 + CGFloat(i) * 132, y: 166, width: 124, height: 78))
            b.title = name
            b.titlePosition = position
            root.addSubview(b)
        }
        view = root
    }
}

final class ColorViewController: NSViewController {
    let color: NSColor
    let text: String
    init(color: NSColor, text: String) {
        self.color = color
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    final class PaneView: NSView {
        var color = NSColor.white
        override var isOpaque: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }

    override func loadView() {
        let pane = PaneView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        pane.color = color
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: pane.centerYAnchor),
        ])
        view = pane
    }
}


/// An MTKView on the system device: the clear colour cycles every frame through the
/// display link and an HLSL pipeline draws a spinning triangle over it (the reference
/// device does not rasterize, so there only the clear shows). With `--metal-log` the
/// device is named on start (with the reason no Vulkan device was made, on Linux) and the
/// centre and corner pixels of every 30th frame are read back and printed after the
/// frame's command buffer completes, with the drawable size and whether the frame went
/// through a swap chain (Windows, DirectComposition) or the readback path.
final class MetalDemoViewController: NSViewController, MTKViewDelegate {
    private var frame = 0
    private let label = NSTextField(labelWithString: "")
    private var queue: (any MTLCommandQueue)?
    private var pipeline: (any MTLRenderPipelineState)?
    private var vertices: (any MTLBuffer)?
    private let logsPixels = CommandLine.arguments.contains("--metal-log")

    /// With `--metal-msl` the same triangle ships as Metal Shading Language and goes
    /// through the MSL → HLSL translator (ADR-0006).
    static let usesMSL = CommandLine.arguments.contains("--metal-msl")
    /// With `--metal-static` the clear colour stays (0.2, 0.6, 0.9) and the triangle does
    /// not turn, so a screenshot can be checked for the presented pixels (tools/linux).
    static let isStatic = CommandLine.arguments.contains("--metal-static")

    /// Constants at buffer 0 (`b0`), vertices at buffer 1 with attributes 0 and 1.
    static let shaderSource = """
    cbuffer Frame { float2 scale; float angle; float padding; };
    struct VSIn { float2 position : ATTRIBUTE0; float4 color : ATTRIBUTE1; };
    struct VSOut { float4 position : SV_Position; float4 color : COLOR0; };
    VSOut triangleVertex(VSIn v) {
        float s = sin(angle), c = cos(angle);
        float2 p = float2(v.position.x * c - v.position.y * s, v.position.x * s + v.position.y * c) * scale;
        VSOut o;
        o.position = float4(p, 0, 1);
        o.color = v.color;
        return o;
    }
    float4 triangleFragment(VSOut i) : SV_Target { return i.color; }
    """

    /// The same shader in MSL: `constant Frame&` at `[[buffer(0)]]`, `[[stage_in]]` vertices.
    static let mslShaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Frame { float2 scale; float angle; float padding; };
    struct VertexIn { float2 position [[attribute(0)]]; float4 color [[attribute(1)]]; };
    struct VertexOut { float4 position [[position]]; float4 color; };
    vertex VertexOut triangleVertex(VertexIn v [[stage_in]], constant Frame& frame [[buffer(0)]]) {
        float s = sin(frame.angle), c = cos(frame.angle);
        float2 p = float2(v.position.x * c - v.position.y * s, v.position.x * s + v.position.y * c) * frame.scale;
        VertexOut o;
        o.position = float4(p, 0, 1);
        o.color = v.color;
        return o;
    }
    fragment float4 triangleFragment(VertexOut i [[stage_in]]) { return i.color; }
    """

    struct Vertex { var x: Float, y: Float, r: Float, g: Float, b: Float, a: Float }
    struct Frame { var scaleX: Float, scaleY: Float, angle: Float, padding: Float }

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Metal"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let device = MTLCreateSystemDefaultDevice()
        let mtk = MTKView(frame: NSRect(x: 0, y: 0, width: 420, height: 260), device: device)
        mtk.delegate = self
        mtk.preferredFramesPerSecond = 30
        mtk.colorPixelFormat = .bgra8Unorm
        label.stringValue = "Device: \(device?.name ?? "none")"
        if logsPixels {
            print("device: \(device?.name ?? "none") rasterizes=\(device?.supportsRasterization ?? false)")
            #if os(Linux)
            if !(device is MTLVulkanDevice) { print("Vulkan device unavailable: \(MTLVulkanDevice.unavailabilityReason.isEmpty ? "APPKITWIN_METAL_REFERENCE=1" : MTLVulkanDevice.unavailabilityReason)") }
            #endif
            fflush(nil)
        }
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        mtk.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: mtk.leadingAnchor, constant: 12),
            label.topAnchor.constraint(equalTo: mtk.topAnchor, constant: 12),
        ])
        view = mtk
        if let device { setUpTriangle(on: device, format: mtk.colorPixelFormat) }
    }

    private func setUpTriangle(on device: any MTLDevice, format: MTLPixelFormat) {
        queue = device.makeCommandQueue()
        let triangle = [Vertex(x: 0, y: 0.7, r: 1, g: 0.2, b: 0.2, a: 1), Vertex(x: 0.7, y: -0.5, r: 0.2, g: 1, b: 0.2, a: 1), Vertex(x: -0.7, y: -0.5, r: 0.2, g: 0.3, b: 1, a: 1)]
        vertices = triangle.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: []) }
        do {
            let options = MTLCompileOptions()
            options.shaderLanguage = Self.usesMSL ? .metal : .hlsl
            let library = try device.makeLibrary(source: Self.usesMSL ? MetalDemoViewController.mslShaderSource : MetalDemoViewController.shaderSource, options: options)
            if Self.usesMSL { label.stringValue += " (MSL)" }
            let desc = MTLRenderPipelineDescriptor()
            desc.label = "triangle"
            desc.vertexFunction = library.makeFunction(name: "triangleVertex")
            desc.fragmentFunction = library.makeFunction(name: "triangleFragment")
            desc.colorAttachments[0].pixelFormat = format
            let vd = MTLVertexDescriptor()
            vd.attributes[0].format = .float2
            vd.attributes[0].offset = 0
            vd.attributes[0].bufferIndex = 1
            vd.attributes[1].format = .float4
            vd.attributes[1].offset = 8
            vd.attributes[1].bufferIndex = 1
            vd.layouts[1].stride = MemoryLayout<Vertex>.stride
            desc.vertexDescriptor = vd
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            label.stringValue += " (triangle pipeline failed: \(error))"
            if logsPixels { print("triangle pipeline failed: \(error)"); fflush(nil) }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        frame += 1
        let t = Self.isStatic ? 0.3 : Double(frame) / 60
        view.clearColor = Self.isStatic ? MTLClearColorMake(0.2, 0.6, 0.9, 1) : MTLClearColorMake(0.5 + 0.5 * sin(t), 0.5 + 0.5 * sin(t * 1.3 + 2), 0.5 + 0.5 * sin(t * 0.7 + 4), 1)
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let queue, let cb = queue.makeCommandBuffer(), let encoder = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let pipeline, let vertices {
            let size = view.drawableSize
            var constants = Frame(scaleX: Float(min(size.width, size.height) / max(size.width, 1)), scaleY: Float(min(size.width, size.height) / max(size.height, 1)), angle: Float(t), padding: 0)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&constants, length: MemoryLayout<Frame>.stride, index: 0)
            encoder.setVertexBuffer(vertices, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        cb.present(drawable)
        let texture = view.currentTexture
        cb.commit()
        if logsPixels, frame % 30 == 1, let tex = texture {
            var centre = [UInt8](repeating: 0, count: 4), corner = [UInt8](repeating: 0, count: 4)
            tex.getBytes(&centre, bytesPerRow: 4, from: MTLRegionMake2D(tex.width / 2, tex.height / 2, 1, 1), mipmapLevel: 0)
            tex.getBytes(&corner, bytesPerRow: 4, from: MTLRegionMake2D(2, 2, 1, 1), mipmapLevel: 0)
            let c = view.clearColor
            let expected = [Int(c.blue * 255 + 0.5), Int(c.green * 255 + 0.5), Int(c.red * 255 + 0.5), 255]
            print("frame \(frame) clear BGRA=\(expected) corner BGRA=\(corner) centre BGRA=\(centre) size \(tex.width)x\(tex.height) presentation=\(view._presentsThroughSwapChain ? "swap chain" : "readback")\(view._presentationError.isEmpty ? "" : " error=\(view._presentationError)")")
            fflush(nil)
        }
    }
}


// MARK: - SwiftUI demo content

final class DemoModel: ObservableObject {
    @Published var items: [String] = ["Alpha", "Beta", "Gamma"]
    @Published var nextIndex = 4
}

struct SwiftUIDemo: View {
    /// `APPKITWIN_DEMO_TAB=data` (or navigation, presentation) opens on that tab; screenshots use it.
    @State private var tab = ProcessInfo.processInfo.environment["APPKITWIN_DEMO_TAB"] ?? "controls"
    var body: some View {
        TabView(selection: $tab) {
            ControlsDemo().tabItem { Text("Controls") }.tag("controls")
            NavigationDemo().tabItem { Text("Navigation") }.tag("navigation")
            PresentationDemo().tabItem { Text("Presentation") }.tag("presentation")
            DataDemo().tabItem { Text("Data") }.tag("data")
            GesturesDemo().tabItem { Text("Gestures") }.tag("gestures")
        }
        .padding(12)
        .frame(minWidth: 420, minHeight: 360)
    }
}

enum Fruit: String, CaseIterable, Hashable { case apple, pear, plum }

/// A card that drags, pinches and rotates (trackpad, touch screen, or Ctrl+wheel to zoom),
/// plus a tap counter and a long press.
struct GesturesDemo: View {
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero
    @State private var scale: CGFloat = 1
    @State private var scaleStart: CGFloat = 1
    @State private var angle = Angle.zero
    @State private var angleStart = Angle.zero
    @State private var taps = 0
    @State private var pressed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag, pinch, rotate the card; tap or hold the button.").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15))
                RoundedRectangle(cornerRadius: 10)
                    .fill(pressed ? Color.orange : Color.blue)
                    .frame(width: 120, height: 80)
                    .overlay(Text(String(format: "%.2fx  %.0f°", scale, angle.degrees)).foregroundColor(.white))
                    .scaleEffect(scale)
                    .rotationEffect(angle)
                    .offset(offset)
                    .gesture(DragGesture().onChanged { v in offset = CGSize(width: dragStart.width + v.translation.width, height: dragStart.height + v.translation.height) }
                                          .onEnded { _ in dragStart = offset })
                    .simultaneousGesture(MagnificationGesture().onChanged { scale = min(3, max(0.3, scaleStart * $0)) }.onEnded { _ in scaleStart = scale })
                    .simultaneousGesture(RotationGesture().onChanged { angle = .radians(angleStart.radians + $0.radians) }.onEnded { _ in angleStart = angle })
            }
            .frame(minHeight: 220)
            HStack {
                Text("Taps: \(taps)")
                    .padding(8)
                    .background(Color.gray.opacity(0.2))
                    .onTapGesture { taps += 1 }
                    .onLongPressGesture(minimumDuration: 0.6, perform: { taps = 0 }, onPressingChanged: { pressed = $0 })
                Text(pressed ? "holding (release to reset)" : "hold to reset").foregroundColor(.secondary)
                Spacer()
                Button("Reset card") { offset = .zero; dragStart = .zero; scale = 1; scaleStart = 1; angle = .zero; angleStart = .zero }
            }
        }
    }
}

struct Planet: Identifiable {
    let id: Int
    let name: String
    let moons: Int
    let radius: Double     // km
}

/// Table with a selection and a sort order; the data is sorted by the app, as on macOS.
struct DataDemo: View {
    @State private var selected: Set<Int> = []
    @State private var basket = "empty"
    @State private var basketTargeted = false
    @State private var files = "none"
    @State private var filesTargeted = false
    @State private var order = [KeyPathComparator(\Planet.name)]
    let planets = [Planet(id: 1, name: "Mercury", moons: 0, radius: 2440), Planet(id: 2, name: "Venus", moons: 0, radius: 6052),
                   Planet(id: 3, name: "Earth", moons: 1, radius: 6371), Planet(id: 4, name: "Mars", moons: 2, radius: 3390),
                   Planet(id: 5, name: "Jupiter", moons: 95, radius: 69911), Planet(id: 6, name: "Saturn", moons: 146, radius: 58232)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Click a header to sort, rows to select (Cmd and Shift extend).").foregroundColor(.secondary)
            Table(planets.sorted(using: order), selection: $selected, sortOrder: $order) {
                TableColumn("Planet", value: \.name)
                TableColumn("Moons", value: \.moons) { Text("\($0.moons)") }.width(60)
                TableColumn("Radius (km)", value: \.radius) { Text(String(format: "%.0f", $0.radius)) }.width(90)
            }
            .frame(minHeight: 180)
            Text("Selected: \(selected.sorted().map(String.init).joined(separator: ", "))")
            HStack(spacing: 12) {
                // Drag the chip onto the basket (a text drag, in-process).
                Text("Drag me")
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
                    .foregroundColor(.white)
                    .onDrag { NSItemProvider(object: "a dragged chip" as NSString) }
                Text(basketTargeted ? "Drop here" : "Basket: \(basket)")
                    .frame(width: 220, height: 40)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: basketTargeted ? .selectedContentBackgroundColor : .controlBackgroundColor)))
                    .onDrop(of: [.utf8PlainText], isTargeted: $basketTargeted) { providers in
                        guard let p = providers.first else { return false }
                        p.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
                            let s = data.map { String(decoding: $0, as: UTF8.self) } ?? "?"
                            DispatchQueue.main.async { basket = s }
                        }
                        return true
                    }
            }
            // Files dropped from another application (Explorer, a file manager): one item per file.
            Text(filesTargeted ? "Drop files here" : "Files: \(files)")
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: filesTargeted ? .selectedContentBackgroundColor : .controlBackgroundColor)))
                .onDrop(of: [.fileURL], isTargeted: $filesTargeted) { providers in
                    var names: [String] = []
                    for p in providers {
                        p.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            guard let data, let url = URL(string: String(decoding: data, as: UTF8.self)) else { return }
                            names.append(url.lastPathComponent)
                            DispatchQueue.main.async { files = names.joined(separator: ", ") }
                        }
                    }
                    return !providers.isEmpty
                }
        }
        .padding(12)
    }
}

struct NavigationDemo: View {
    @State private var path: [Int] = []
    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick a detail page:").foregroundColor(.secondary)
                ForEach(1...3, id: \.self) { n in NavigationLink("Detail \(n)", value: n) }
                NavigationLink("An inline destination", destination: Text("Pushed without a value").padding())
                Spacer()
                Text("Path depth: \(path.count)").font(.caption)
            }
            .padding(12)
            .navigationTitle("Navigation")
            .navigationDestination(for: Int.self) { n in
                VStack(spacing: 10) {
                    Text("Detail \(n)").font(.title2)
                    if n < 3 { NavigationLink("Deeper: Detail \(n + 1)", value: n + 1) }
                    Spacer()
                }
                .padding(12)
                .navigationTitle("Detail \(n)")
            }
        }
    }
}

struct PresentationDemo: View {
    @State private var fruit = Fruit.pear
    @State private var showSheet = false
    @State private var showAlert = false
    @State private var lastAnswer = "none"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Fruit", selection: $fruit) {
                ForEach(Fruit.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("As radio buttons", selection: $fruit) {
                ForEach(Fruit.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.radioGroup)
            Text("Selected: \(fruit.rawValue)")
            HStack {
                Menu("Actions") {
                    Button("Eat") { lastAnswer = "eat (menu)" }
                    Button("Keep") { lastAnswer = "keep (menu)" }
                    Divider()
                    Menu("More") {
                        Button("Share") { lastAnswer = "share" }
                        Button("Print") { lastAnswer = "print" }
                    }
                }
                Text("Right-click me").padding(6).contextMenu {
                    Button("Hello") { lastAnswer = "hello (context)" }
                    Button("Goodbye") { lastAnswer = "goodbye (context)" }
                }
            }
            HStack {
                Button("Show sheet") { showSheet = true }
                Button("Ask") { showAlert = true }
                Text("Last answer: \(lastAnswer)").foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .sheet(isPresented: $showSheet) { SheetDemo(fruit: fruit) }
        .alert("Eat the \(fruit.rawValue)?", isPresented: $showAlert) {
            Button("Eat", role: .destructive) { lastAnswer = "eat" }
            Button("Keep", role: .cancel) { lastAnswer = "keep" }
        } message: { Text("This cannot be undone.") }
    }
}

struct SheetDemo: View {
    let fruit: Fruit
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            Text("A sheet about the \(fruit.rawValue)").font(.headline)
            Text("It is attached to the demo window and closes with the button or its close box.").foregroundColor(.secondary)
            Button("Done") { dismiss() }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct ControlsDemo: View {
    @State private var name = ""
    @State private var count = 0
    @State private var enabled = true
    @State private var amount = 0.4
    @State private var selectedItem: String? = nil
    @StateObject private var model = DemoModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SwiftUI on AppKitCross").font(.title).bold()
            Text("State, bindings and layout running over this AppKit.").foregroundColor(.secondary)
            HStack {
                TextField("Your name", text: $name)
                Button("Greet") { count += 1 }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .shadow(color: Color(.sRGB, white: 0, opacity: 0.35), radius: 6, x: 0, y: 3)   // a blurred layer shadow
            Text(name.isEmpty ? "Type a name and press Greet." : "Hello, \(name)! (\(count) \(count == 1 ? "greeting" : "greetings"))")
            Group {
                Toggle("Enabled", isOn: $enabled.animation(.easeInOut(duration: 0.3)))
                HStack {
                    Slider(value: $amount, in: 0...1).disabled(!enabled)
                    Text(String(format: "%.0f%%", amount * 100)).frame(width: 44, alignment: .trailing)
                }
                // The bar animates its width with the slider and fades with the toggle.
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor).opacity(enabled ? 1 : 0.3)
                    .frame(width: 240 * CGFloat(amount) + 20, height: 20)
                    .animation(.easeOut(duration: 0.25), value: amount)
                if !enabled {
                    Text("Disabled").foregroundColor(.secondary).transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            Divider()
            HStack {
                Text("Items").font(.headline)
                Spacer()
                Button("Add") { model.items.append("Item \(model.nextIndex)"); model.nextIndex += 1 }
                Button("Remove") { if !model.items.isEmpty { model.items.removeLast() } }
            }
            List(model.items, id: \.self, selection: $selectedItem) { item in
                HStack {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                    Text(item)
                    Spacer()
                }
            }.frame(height: 120)
            Text("Selected: \(selectedItem ?? "none")").foregroundColor(.secondary)
        }
        .padding(4)
    }
}

/// The Layout Demo's Panels tab (ADR-0022): colour wells in the three styles, buttons that
/// open the Fonts and Colors panels, and a rich text view that both panels change through
/// the responder chain (`changeFont:` and `changeColor:` reach the first responder).
/// `APPKITWIN_PANELS_OPEN=color|font` opens a panel at launch for the comparison renders.
final class PanelsDemoViewController: NSViewController, NSSelectorHandling {
    let well = NSColorWell(frame: .zero)
    let minimalWell: NSColorWell = {
        if #available(macOS 13.0, *) { return NSColorWell(style: .minimal) }
        return NSColorWell(frame: NSRect(x: 0, y: 0, width: 28, height: 20))
    }()
    let expandedWell: NSColorWell = {
        if #available(macOS 13.0, *) { return NSColorWell(style: .expanded) }
        return NSColorWell(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
    }()
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))
    let status = NSTextField(labelWithString: "Click a well or open a panel; the selection in the text follows both.")

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Panels"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        let wellLabel = NSTextField(labelWithString: "Color wells:")
        well.color = NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        minimalWell.color = NSColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)
        expandedWell.color = NSColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
        for w in [well, minimalWell, expandedWell] {
            w.target = self
            w.action = Selector(("wellChanged:"))
        }
        let fonts = NSButton(title: "Fonts…", target: nil, action: Selector(("orderFrontFontPanel:")))
        let colors = NSButton(title: "Colors…", target: nil, action: Selector(("orderFrontColorPanel:")))
        let scroll = NSScrollView(frame: .zero)
        textView.isRichText = true
        textView.isEditable = true
        textView.textStorage?.setAttributedString(NSAttributedString(string: "Select some of this text, then pick a font or a colour.\nThe panels change the selection; typing continues in it.", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.textColor]))
        textView.setSelectedRange(NSRange(location: 12, length: 17))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        for v in [wellLabel, well, minimalWell, expandedWell, fonts, colors, scroll, status] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            wellLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            wellLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            well.centerYAnchor.constraint(equalTo: wellLabel.centerYAnchor),
            well.leadingAnchor.constraint(equalTo: wellLabel.trailingAnchor, constant: 8),
            well.widthAnchor.constraint(equalToConstant: 44), well.heightAnchor.constraint(equalToConstant: 24),
            minimalWell.centerYAnchor.constraint(equalTo: wellLabel.centerYAnchor),
            minimalWell.leadingAnchor.constraint(equalTo: well.trailingAnchor, constant: 8),
            minimalWell.widthAnchor.constraint(equalToConstant: 28), minimalWell.heightAnchor.constraint(equalToConstant: 20),
            expandedWell.centerYAnchor.constraint(equalTo: wellLabel.centerYAnchor),
            expandedWell.leadingAnchor.constraint(equalTo: minimalWell.trailingAnchor, constant: 8),
            expandedWell.widthAnchor.constraint(equalToConstant: 64), expandedWell.heightAnchor.constraint(equalToConstant: 24),
            colors.centerYAnchor.constraint(equalTo: wellLabel.centerYAnchor),
            colors.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            fonts.centerYAnchor.constraint(equalTo: wellLabel.centerYAnchor),
            fonts.trailingAnchor.constraint(equalTo: colors.leadingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: wellLabel.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.heightAnchor.constraint(equalToConstant: 120),
            status.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        let wantsColor: Bool
        switch ProcessInfo.processInfo.environment["APPKITWIN_PANELS_OPEN"] {
        case "color": wantsColor = true
        case "font": wantsColor = false
        default: return
        }
        @MainActor func open() { if wantsColor { NSApp.orderFrontColorPanel(nil) } else { NSFontManager.shared.orderFrontFontPanel(nil) } }
        // Screenshots capture at once; a live run waits for the window to be mapped first.
        if CommandLine.arguments.contains("--screenshot") { open() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { open() } }
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard NSStringFromSelector(action) == "wellChanged:", let w = sender as? NSColorWell else { return false }
        let c = w.color
        status.stringValue = String(format: "Well: #%02X%02X%02X, alpha %.2f", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255), Double(c.alphaComponent))
        return true
    }
}

/// The scripted Fonts panel check (`--panels-selftest`), in steps a second apart so the
/// window system's activation messages arrive between them, as they would for a user.
@MainActor enum PanelsSelfTest {
    static func run(step: Int) {
        let app = NSApplication.shared
        func describe(_ w: NSWindow?) -> String { w.map { "'\($0.title)' (first responder \(type(of: $0.firstResponder ?? $0)))" } ?? "nil" }
        func report(_ s: String) { FileHandle.standardError.write(Data("panels-selftest: \(s)\n".utf8)) }
        guard let demo = app.windows.first(where: { $0.title == "Layout Demo" }),
              let tv = demo.contentView.flatMap({ v in allViews(v).compactMap { $0 as? NSTextView }.first }) else {
            report("FAIL no Layout Demo text view"); exit(1)
        }
        switch step {
        case 0:
            demo.makeKeyAndOrderFront(nil)
            _ = demo.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: 0, length: 11))
            report("selected \(tv.selectedRange) in \(describe(demo)); key=\(describe(app.keyWindow)) main=\(describe(app.mainWindow))")
            // Click the "Fonts…" button with mouse events, as the user does: the click must
            // not move the keyboard focus off the text view.
            guard let fonts = demo.contentView.flatMap({ v in allViews(v).compactMap { $0 as? NSButton }.first { $0.title == "Fonts…" } }) else { report("FAIL no Fonts button"); exit(1) }
            let p = fonts.convert(NSPoint(x: fonts.bounds.midX, y: fonts.bounds.midY), to: nil)
            for (type, pressure) in [(NSEvent.EventType.leftMouseDown, 1 as Float), (.leftMouseUp, 0)] {
                if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: demo.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure) { app.sendEvent(e) }
            }
            report("clicked Fonts…; demo first responder \(type(of: demo.firstResponder ?? demo)); panel exists \(NSFontPanel.sharedFontPanelExists)")
            NSFontPanel.shared.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { run(step: 1) }
        case 1:
            report("panel shown; key=\(describe(app.keyWindow)) main=\(describe(app.mainWindow)) panel.isKey=\(NSFontPanel.shared.isKeyWindow) selection=\(tv.selectedRange)")
            let before = (tv.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
            // The same path as a click in the Size list: the panel's font and the manager's send.
            let family = (tv.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.familyName ?? "Segoe UI"
            let big = NSFont(name: family, size: 36) ?? NSFont.systemFont(ofSize: 36)
            NSFontPanel.shared.setPanelFont(big, isMultiple: false)
            NSFontManager.shared.modifyFontViaPanel(nil)
            let after = (tv.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
            let outside = (tv.textStorage?.attribute(.font, at: 20, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
            report("font at 2: \(before) -> \(after); outside the selection \(outside); key=\(describe(app.keyWindow)) main=\(describe(app.mainWindow))")
            demo.display()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let ok = after == 36 && outside != 36 && demo.firstResponder === tv
                report(ok ? "PASS" : "FAIL (first responder \(type(of: demo.firstResponder ?? demo)))")
                exit(ok ? 0 : 1)
            }
        default: break
        }
    }
    static func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
}
