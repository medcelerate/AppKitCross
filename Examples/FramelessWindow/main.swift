// FramelessWindow: a window without a title bar whose content draws its own rounded shape,
// moves when dragged anywhere on its background, shows the system backdrop where the
// platform has one (Mica/Acrylic on Windows 11, vibrancy on macOS) and keeps AppKit's
// standard close/minimize/zoom buttons through `.fullSizeContentView`. A second,
// `.borderless` panel shows the shape without any buttons at all.

import AppKit

/// Paints a rounded card with a border; everything outside the card stays clear, so the
/// (non-opaque) window takes the card's shape.
final class CardView: NSView {
    var cornerRadius: CGFloat = 22
    var tint: NSColor = NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.36, alpha: 0.92)
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius)
        tint.setFill()
        card.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        card.lineWidth = 1.5
        card.stroke()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSelectorHandling {
    var window: NSWindow!
    var status: NSTextField!
    var panel: NSPanel?
    var backdrop: NSVisualEffectView!

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("closeWindow:")): window.performClose(sender); return true
        case Selector(("minimizeWindow:")): window.performMiniaturize(sender); return true
        case Selector(("zoomWindow:")): window.performZoom(sender); return true
        case Selector(("toggleBackdrop:")):
            backdrop.isHidden = (sender as? NSButton)?.state != .on
            report(backdrop.isHidden ? "backdrop off" : "backdrop on")
            return true
        case Selector(("showPanel:")): showPanel(); return true
        case Selector(("closePanel:")): panel?.close(); panel = nil; return true
        case Selector(("quit:")): NSApp.terminate(sender); return true
        default: return false
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(title: "Main")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Borderless Panel", action: Selector(("showPanel:")), keyEquivalent: "p")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)
        // Window menu items with nil targets reach the key window through the responder chain.
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: Selector(("performMiniaturize:")), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: Selector(("performZoom:")), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Close", action: Selector(("performClose:")), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main

        // Title bar hidden and transparent, content under it: AppKit draws the three
        // standard buttons itself over the content (NSWindow+fullSizeContentView).
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Frameless"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 320, height: 200)
        window.delegate = self

        let card = CardView(frame: NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size))
        card.autoresizingMask = [.width, .height]
        window.contentView = card

        // The system backdrop behind the window (DWM Mica/Acrylic on Windows 11, vibrancy on
        // macOS, a tinted fill where there is none), clipped to the card's corners.
        backdrop = NSVisualEffectView(frame: card.bounds.insetBy(dx: 1, dy: 1))
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = card.cornerRadius
        backdrop.layer?.masksToBounds = true
        backdrop.autoresizingMask = [.width, .height]
        card.addSubview(backdrop)

        let title = NSTextField(labelWithString: "Frameless window")
        title.font = NSFont.boldSystemFont(ofSize: 22)
        title.textColor = .white
        let hint = NSTextField(labelWithString: "Drag anywhere to move. Top-left: the standard window buttons.")
        hint.textColor = NSColor.white.withAlphaComponent(0.8)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.preferredMaxLayoutWidth = 400
        status = NSTextField(labelWithString: "ready")
        status.textColor = NSColor.white.withAlphaComponent(0.8)

        let close = NSButton(title: "Close", target: self, action: Selector(("closeWindow:")))
        let minimize = NSButton(title: "Minimize", target: self, action: Selector(("minimizeWindow:")))
        let zoom = NSButton(title: "Zoom", target: self, action: Selector(("zoomWindow:")))
        let panelButton = NSButton(title: "Panel", target: self, action: Selector(("showPanel:")))
        let backdropToggle = NSButton(checkboxWithTitle: "Backdrop", target: self, action: Selector(("toggleBackdrop:")))
        backdropToggle.state = .on
        backdropToggle.contentTintColor = .white
        let buttons = NSStackView(views: [close, minimize, zoom, panelButton, backdropToggle])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let column = NSStackView(views: [title, hint, buttons, status])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -24),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 48),
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        if CommandLine.arguments.contains("--panel") { showPanel() }
    }

    /// A `.borderless` panel: no title bar, no buttons, its own rounded shape, moved by
    /// dragging its background and closed by its button (or Escape through the chain).
    @MainActor func showPanel() {
        if let p = panel { p.makeKeyAndOrderFront(nil); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        p.title = "Borderless"
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        let card = CardView(frame: NSRect(origin: .zero, size: p.frame.size))
        card.tint = NSColor(calibratedRed: 0.55, green: 0.2, blue: 0.3, alpha: 0.95)
        card.cornerRadius = 30
        p.contentView = card
        let label = NSTextField(labelWithString: "Borderless panel: no title bar, no buttons.")
        label.textColor = .white
        let close = NSButton(title: "Close", target: self, action: Selector(("closePanel:")))
        close.keyEquivalent = "\u{1B}"
        let column = NSStackView(views: [label, close])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        panel = p
        let origin = NSPoint(x: window.frame.maxX - 60, y: window.frame.minY - 40)
        p.setFrameOrigin(origin)
        p.makeKeyAndOrderFront(nil)
    }

    private func report(_ what: String) {
        let f = window.frame
        status.stringValue = "\(what): \(Int(f.width))×\(Int(f.height)) at \(Int(f.origin.x)),\(Int(f.origin.y))"
    }

    func windowDidResize(_ notification: Notification) { report(window.isZoomed ? "zoomed" : "resized") }
    func windowDidMove(_ notification: Notification) { report("moved") }
    func windowDidMiniaturize(_ notification: Notification) { report("minimized") }
    func windowDidDeminiaturize(_ notification: Notification) { report("restored") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
