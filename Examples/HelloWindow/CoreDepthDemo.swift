// Layout Demo tab "coredepth" (ADR-0036): a nine-slice image stretched to three sizes and
// tiled, a turned view, tool tips, PNG/TIFF/BMP export of the panel, and a window that
// remembers its frame (frame autosave) and keeps a 4:3 content proportion while resized.
// ADR-0038 adds an event monitor (local and global; every event it sees is traced to stderr
// as "coredepth2 monitor …", keys with their Shift and Option characters from the keyboard
// layout) and a sheet run through the legacy NSApp.beginSheet(_:modalFor:modalDelegate:…).

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

final class CoreDepthDemoViewController: NSViewController, NSSelectorHandling {
    let nineSlice = NineSliceDemoView(frame: NSRect(x: 16, y: 16, width: 344, height: 176))
    let status = NSTextField(labelWithString: "")
    var autosaveWindow: NSWindow?
    var monitors: [Any] = []
    var legacySheet: NSWindow?

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Core"
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 840, height: 270))
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
        view = root
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
