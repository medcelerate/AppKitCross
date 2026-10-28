// Milestone 1 sample: open a window and draw into it with AppKit APIs only.
// Builds against this package on Windows and against Apple's AppKit on macOS unchanged.

import AppKit
import Metal
import MetalKit

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

        // `HelloWindow --metal` opens the Layout Demo on its Metal tab (for scripted runs).
        if CommandLine.arguments.contains("--metal") {
            showLayoutDemo()
            (layoutWindowController?.window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = 2
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    var layoutWindowController: NSWindowController?
    var glassWindow: NSWindow?

    /// Milestone 3b: a frameless, translucent window over the system backdrop.
    @MainActor func showGlassWindow() {
        if let g = glassWindow { g.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
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
        tabs.addChild(MetalDemoViewController())
        tabs.view.frame = NSRect(x: 0, y: 0, width: 440, height: 300)
        let window = NSWindow(contentViewController: tabs)
        window.title = "Layout Demo"
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

/// A coloured pane with a centred label, for the split view.
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
/// centre and corner pixels of every 30th frame are read back and printed.
final class MetalDemoViewController: NSViewController, MTKViewDelegate {
    private var frame = 0
    private let label = NSTextField(labelWithString: "")
    private var queue: (any MTLCommandQueue)?
    private var pipeline: (any MTLRenderPipelineState)?
    private var vertices: (any MTLBuffer)?
    private let logsPixels = CommandLine.arguments.contains("--metal-log")

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
            options.shaderLanguage = .hlsl
            let library = try device.makeLibrary(source: MetalDemoViewController.shaderSource, options: options)
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
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        frame += 1
        let t = Double(frame) / 60
        view.clearColor = MTLClearColorMake(0.5 + 0.5 * sin(t), 0.5 + 0.5 * sin(t * 1.3 + 2), 0.5 + 0.5 * sin(t * 0.7 + 4), 1)
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
            print("frame \(frame) clear BGRA=\(expected) corner BGRA=\(corner) centre BGRA=\(centre)")
            fflush(nil)
        }
    }
}
