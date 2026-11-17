// Layout Demo tab "coredepth" (ADR-0036): a nine-slice image stretched to three sizes and
// tiled, a turned view, tool tips, PNG/TIFF/BMP export of the panel, and a window that
// remembers its frame (frame autosave) and keeps a 4:3 content proportion while resized.
// ADR-0038 adds an event monitor (local and global; every event it sees is traced to stderr
// as "coredepth2 monitor …", keys with their Shift and Option characters from the keyboard
// layout) and a sheet run through the legacy NSApp.beginSheet(_:modalFor:modalDelegate:…).
// ADR-0039 adds a top strip: glyph outlines with their bounding rects and advances (NSFont
// glyph metrics, NSBezierPath.appendGlyph), a path that answers clicks with a hit test, a
// palette menu popped up from code, a pasteboard round trip, and buttons with images
// (template tint, image positions). Results go to the status line and stderr as "coredepth3 …".

import AppKit
import Foundation

/// Draws one bubble image three ways: stretched by its cap insets at two sizes, tiled.
final class NineSliceDemoView: NSView {
    static let bubble: NSImage = {
        // A 24×24 bubble: a 2-pt dark border, a light fill and a dot in the middle that
        // shows how the centre slice stretches (or repeats, tiled).
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { r in
            NSColor(calibratedRed: 0.2, green: 0.35, blue: 0.75, alpha: 1).setFill()
            NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
            NSColor(calibratedRed: 0.86, green: 0.91, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
            NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 4, height: 4)).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return image
    }()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let image = NineSliceDemoView.bubble
        image.resizingMode = .stretch
        image.draw(in: NSRect(x: 10, y: 10, width: 24, height: 24), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.draw(in: NSRect(x: 44, y: 10, width: 160, height: 40), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.draw(in: NSRect(x: 10, y: 60, width: 194, height: 90), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.resizingMode = .tile
        image.draw(in: NSRect(x: 214, y: 10, width: 120, height: 140), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        image.resizingMode = .stretch
        let label = "corners stay 8 pt · stretched | tiled →" as NSString
        label.draw(at: NSPoint(x: 10, y: 156), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
    }
}

/// A label turned by `frameRotation`: drawing, hit testing and conversion follow it.
final class TurnedLabelView: NSView {
    var clicks = 0
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.withAlphaComponent(0.25).setFill()
        bounds.fill()
        ("Turned 20° — click me (\(clicks))" as NSString).draw(at: NSPoint(x: 6, y: 6), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
    }
    override func mouseDown(with event: NSEvent) { clicks += 1; needsDisplay = true }
}

/// "Hg" drawn as glyph outlines, each glyph's bounding rect outlined and its advance marked.
final class GlyphMetricsDemoView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let font = NSFont.systemFont(ofSize: 56)
        var glyphs: [NSGlyph] = "Hg".unicodeScalars.map { font.glyph(withName: String($0)) }
        if glyphs.contains(0) { glyphs = [font.glyph(withName: "H"), font.glyph(withName: "g")] }
        var x: CGFloat = 12
        let baseline: CGFloat = 26
        for g in glyphs {
            let r = font.boundingRect(forGlyph: g).offsetBy(dx: x, dy: baseline)
            NSColor.systemOrange.setStroke()
            NSBezierPath.stroke(r)
            let adv = font.advancement(forGlyph: g).width
            NSColor.systemBlue.setStroke()
            NSBezierPath.strokeLine(from: NSPoint(x: x + adv, y: 6), to: NSPoint(x: x + adv, y: bounds.height - 6))
            x += adv
        }
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: 12, y: baseline))
        outline.appendGlyphs(&glyphs, count: glyphs.count, in: font)
        NSColor.labelColor.setFill()
        outline.fill()
        NSColor.secondaryLabelColor.setStroke()
        NSBezierPath.strokeLine(from: NSPoint(x: 4, y: baseline), to: NSPoint(x: bounds.width - 4, y: baseline))
    }
}

/// A rounded star; a click reports whether `contains(_:)` hit it and flashes the flattened outline.
final class HitTestDemoView: NSView {
    var onHit: ((Bool, NSPoint) -> Void)?
    private var lastHit: Bool? = nil
    lazy var star: NSBezierPath = {
        let p = NSBezierPath()
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 44 : 18
            let a = CGFloat(i) * .pi / 5 + .pi / 2
            let pt = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close()
        return p
    }()
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        (lastHit == true ? NSColor.systemGreen : NSColor.systemPurple).withAlphaComponent(0.7).setFill()
        star.fill()
        let flat = star.reversed.flattened
        flat.lineWidth = 1
        NSColor.labelColor.setStroke()
        flat.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = star.contains(p)
        lastHit = hit
        needsDisplay = true
        onHit?(hit, p)
    }
}

final class CoreDepthDemoViewController: NSViewController, NSSelectorHandling {
    let nineSlice = NineSliceDemoView(frame: NSRect(x: 16, y: 16, width: 344, height: 176))
    let status = NSTextField(labelWithString: "")
    var autosaveWindow: NSWindow?
    var monitors: [Any] = []
    var legacySheet: NSWindow?
    weak var paletteAnchor: NSButton?
    weak var documentRoot: NSView?

    /// Opens scrolled to the top once the tab has its real size.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !scrolledToTop, let root = documentRoot, let scroll = view as? NSScrollView, scroll.contentSize.height > 0 else { return }
        scrolledToTop = true
        root.scroll(NSPoint(x: 0, y: max(0, root.frame.height - scroll.contentSize.height)))
    }
    private var scrolledToTop = false

    private func trace3(_ line: String) { FileHandle.standardError.write(Data("coredepth3 \(line)\n".utf8)) }

    /// One palette menu for the tab's lifetime: its items keep their on/off state between
    /// pop-ups (selectAny toggles the chosen item), so a second choice of a colour unticks it.
    private lazy var paletteMenu: NSMenu = NSMenu.palette(colors: [.systemRed, .systemOrange, .systemGreen, .systemBlue], titles: ["Red", "Orange", "Green", "Blue"]) { [weak self] m in
        let names = m.selectedItems.map(\.title).joined(separator: ", ")
        self?.status.stringValue = "Palette selection: \(names.isEmpty ? "none" : names)"
        self?.trace3("palette \(names)")
    }

    /// The palette popped up from code just below its button, item 0 under the point.
    private func popUpPalette() {
        guard let anchor = paletteAnchor else { return }
        let menu = paletteMenu
        let chosen = menu.popUp(positioning: menu.item(at: 0), at: NSPoint(x: 0, y: -4), in: anchor)
        trace3("popUp returned \(chosen)")
    }

    /// Writes an attributed string (RTF), a colour and a pasteboard item to a private
    /// pasteboard, reads them back and reports what survived.
    private func pasteboardRoundTrip() {
        let pb = NSPasteboard(name: NSPasteboard.Name("AppKitCross.coredepth3"))
        pb.clearContents()
        let text = NSAttributedString(string: "Round trip", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        let item = NSPasteboardItem()
        _ = item.setString("plain item", forType: NSPasteboard.PasteboardType("public.utf8-plain-text.coredepth3"))
        _ = pb.writeObjects([NSColor.systemTeal, item])
        if let rtf = text.rtf(from: NSRange(location: 0, length: text.length)) { _ = pb.setData(rtf, forType: .rtf) }
        let texts = pb.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }.map { [$0] } ?? []
        let colors = pb.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor] ?? []
        let bold = texts.first.map { ($0.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true } ?? false
        let line = "Pasteboard: text \"\(texts.first?.string ?? "-")\" bold \(bold), \(colors.count) colour(s), \(pb.pasteboardItems?.count ?? 0) item(s)"
        status.stringValue = line
        trace3(line)
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Core"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 390))
        // ADR-0039 strip (top).
        let glyphs = GlyphMetricsDemoView(frame: NSRect(x: 16, y: 280, width: 180, height: 96))
        glyphs.toolTip = "NSFont glyph bounding rects (orange) and advances (blue); outlines from NSBezierPath.appendGlyphs"
        root.addSubview(glyphs)
        let hits = HitTestDemoView(frame: NSRect(x: 206, y: 280, width: 120, height: 96))
        hits.toolTip = "Click: NSBezierPath.contains hit test"
        hits.onHit = { [weak self] hit, p in
            self?.status.stringValue = "Hit test at (\(Int(p.x)), \(Int(p.y))): \(hit ? "inside" : "outside") the star"
            self?.trace3("hit \(hit ? "inside" : "outside") \(Int(p.x)),\(Int(p.y))")
        }
        root.addSubview(hits)
        let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16))
        for (i, position) in [NSControl.ImagePosition.imageLeft, .imageAbove, .imageOnly].enumerated() {
            let b = NSButton(title: "Add", image: plus, target: nil, action: nil)
            b.imagePosition = position
            if i == 1 { b.contentTintColor = .systemRed }
            b.frame = NSRect(x: 336 + CGFloat(i) * 70, y: 300, width: 64, height: position == .imageAbove ? 52 : 28)
            root.addSubview(b)
        }
        let row3: [(String, Selector)] = [("Pop-up Palette", Selector(("popUpPalette:"))), ("Pasteboard Round-Trip", Selector(("pasteboardRoundTrip:")))]
        for (i, (title, action)) in row3.enumerated() {
            let b = NSButton(title: title, target: self, action: action)
            b.frame = NSRect(x: 560 + CGFloat(i) * 140, y: 330, width: 132, height: 28)
            if i == 0 { paletteAnchor = b }
            root.addSubview(b)
        }
        nineSlice.toolTip = "NSImage capInsets: nine slices"
        root.addSubview(nineSlice)
        let turned = TurnedLabelView(frame: NSRect(x: 420, y: 175, width: 210, height: 26))
        turned.frameCenterRotation = 20
        turned.toolTip = "frameRotation = 20"
        root.addSubview(turned)
        let buttons: [(String, Selector)] = [
            ("Export PNG…", Selector(("exportPNG:"))), ("Export TIFF…", Selector(("exportTIFF:"))), ("Export BMP…", Selector(("exportBMP:"))),
            ("Open Autosaved Window", Selector(("openAutosaveWindow:"))),
            ("Start Event Monitor", Selector(("toggleEventMonitor:"))), ("Legacy Sheet…", Selector(("showLegacySheet:"))),
        ]
        for (i, (title, action)) in buttons.enumerated() {
            let b = NSButton(title: title, target: self, action: action)
            b.frame = NSRect(x: 400 + CGFloat(i % 2) * 190, y: 124 - CGFloat(i / 2) * 34, width: 180, height: 28)
            root.addSubview(b)
        }
        status.frame = NSRect(x: 400, y: 16, width: 420, height: 18)
        status.textColor = .secondaryLabelColor
        root.addSubview(status)
        // The tab is taller than the Layout Demo window's default size: scroll it, opening
        // at the top (the ADR-0039 strip).
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 840, height: 270))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = root
        root.scroll(NSPoint(x: 0, y: root.frame.height - scroll.contentSize.height))
        documentRoot = root
        view = scroll
    }

    /// The nine-slice panel as it is drawn, at the window's backing scale.
    private func panelRep() -> NSBitmapImageRep? {
        guard let rep = nineSlice.bitmapImageRepForCachingDisplay(in: nineSlice.bounds) else { return nil }
        nineSlice.cacheDisplay(in: nineSlice.bounds, to: rep)
        return rep
    }

    private func export(_ type: NSBitmapImageRep.FileType, name: String) {
        guard let rep = panelRep(), let data = rep.representation(using: type, properties: [:]) else {
            status.stringValue = "No encoder for \(name) on this platform"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                self?.status.stringValue = "Wrote \(data.count) bytes to \(url.lastPathComponent)"
            } catch {
                self?.status.stringValue = "Could not write: \(error.localizedDescription)"
            }
        }
    }

    // Actions arrive by selector name (no Objective-C runtime on Windows and Linux).
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("exportPNG:")): export(.png, name: "nine-slice.png")
        case Selector(("exportTIFF:")): export(.tiff, name: "nine-slice.tiff")
        case Selector(("exportBMP:")): export(.bmp, name: "nine-slice.bmp")
        case Selector(("openAutosaveWindow:")): openAutosaveWindow(sender)
        case Selector(("toggleEventMonitor:")): toggleEventMonitor(sender as? NSButton)
        case Selector(("showLegacySheet:")): showLegacySheet()
        case Selector(("popUpPalette:")): popUpPalette()
        case Selector(("pasteboardRoundTrip:")): pasteboardRoundTrip()
        case Selector(("endLegacySheet:")): if let s = legacySheet { NSApp.endSheet(s, returnCode: (sender as? NSButton)?.tag ?? 0) }
        case Selector(("legacySheetDidEnd:returnCode:contextInfo:")):
            let code = (sender as? NSNumber)?.intValue ?? 0
            legacySheet?.orderOut(nil)
            legacySheet = nil
            status.stringValue = "Legacy sheet ended, return code \(code)"
            trace("legacy sheet didEnd returnCode \(code)")
        default: return false
        }
        return true
    }

    private func trace(_ line: String) {
        FileHandle.standardError.write(Data("coredepth2 \(line)\n".utf8))
    }

    /// Starts or stops a local monitor (keys and clicks in this application, passed on) and a
    /// global one (the same in other applications: Windows only; X11 and Wayland do not
    /// report other clients' input).
    private func toggleEventMonitor(_ button: NSButton?) {
        if !monitors.isEmpty {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            button?.title = "Start Event Monitor"
            status.stringValue = "Event monitor stopped"
            trace("monitor stopped")
            return
        }
        let describe: (NSEvent) -> String = { e in
            guard e.type == .keyDown else { return "\(e.type) at (\(Int(e.locationInWindow.x)), \(Int(e.locationInWindow.y)))" }
            let shifted = e.characters(byApplyingModifiers: .shift) ?? ""
            let option = e.characters(byApplyingModifiers: .option) ?? ""
            return "keyDown keyCode \(e.keyCode) chars '\(e.characters ?? "")' shift '\(shifted)' option '\(option)'"
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown], handler: { [weak self] e in
            let line = describe(e)
            self?.trace("monitor local \(line)")
            self?.status.stringValue = "Local: \(line)"
            return e
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown], handler: { [weak self] e in
            self?.trace("monitor global \(describe(e))")
        }) { monitors.append(m) }
        button?.title = "Stop Event Monitor"
        status.stringValue = "Event monitor on: type or click (here and in other apps)"
        trace("monitor started")
    }

    /// A sheet through the pre-10.9 call; its didEnd selector comes back here with the code.
    private func showLegacySheet() {
        guard legacySheet == nil, let parent = view.window else { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 110), styleMask: [.titled], backing: .buffered, defer: true)
        let label = NSTextField(labelWithString: "Begun with NSApp.beginSheet(_:modalFor:…)")
        label.frame = NSRect(x: 20, y: 66, width: 270, height: 20)
        sheet.contentView?.addSubview(label)
        for (i, (title, code)) in [("Cancel", 0), ("OK", 1)].enumerated() {
            let b = NSButton(title: title, target: self, action: Selector(("endLegacySheet:")))
            b.tag = code
            b.frame = NSRect(x: 110 + CGFloat(i) * 92, y: 16, width: 84, height: 28)
            if code == 1 { b.keyEquivalent = "\r" }
            sheet.contentView?.addSubview(b)
        }
        legacySheet = sheet
        NSApp.beginSheet(sheet, modalFor: parent, modalDelegate: self, didEnd: Selector(("legacySheetDidEnd:returnCode:contextInfo:")), contextInfo: nil)
        trace("legacy sheet begun")
    }

    /// A window that comes back where it was left (across relaunches) and keeps 4:3 content.
    func openAutosaveWindow(_ sender: Any?) {
        if let w = autosaveWindow { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 240), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = "Autosaved Frame"
        w.contentAspectRatio = NSSize(width: 4, height: 3)
        let restored = w.setFrameAutosaveName("CoreDepthDemoWindow")
        let label = NSTextField(wrappingLabelWithString: "Move or resize me, quit and relaunch: I open where you left me. Resizing keeps 4:3. Zoom and minimise from the title bar.")
        label.frame = NSRect(x: 16, y: 16, width: 288, height: 120)
        label.autoresizingMask = [.width, .height]
        w.contentView?.addSubview(label)
        w.makeKeyAndOrderFront(nil)
        autosaveWindow = w
        status.stringValue = restored ? "Frame: \(w.frameDescriptor)" : "Autosave name already in use"
    }
}
