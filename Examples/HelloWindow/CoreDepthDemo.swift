// Layout Demo tab "coredepth" (ADR-0036): a nine-slice image stretched to three sizes and
// tiled, a turned view, tool tips, PNG/TIFF/BMP export of the panel, and a window that
// remembers its frame (frame autosave) and keeps a 4:3 content proportion while resized.

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

final class CoreDepthDemoViewController: NSViewController {
    let nineSlice = NineSliceDemoView(frame: NSRect(x: 16, y: 16, width: 344, height: 176))
    let status = NSTextField(labelWithString: "")
    var autosaveWindow: NSWindow?

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
            ("Export PNG…", #selector(exportPNG(_:))), ("Export TIFF…", #selector(exportTIFF(_:))), ("Export BMP…", #selector(exportBMP(_:))),
            ("Open Autosaved Window", #selector(openAutosaveWindow(_:))),
        ]
        for (i, (title, action)) in buttons.enumerated() {
            let b = NSButton(title: title, target: self, action: action)
            b.frame = NSRect(x: 400 + CGFloat(i % 2) * 190, y: 90 - CGFloat(i / 2) * 34, width: 180, height: 28)
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

    @objc func exportPNG(_ sender: Any?) { export(.png, name: "nine-slice.png") }
    @objc func exportTIFF(_ sender: Any?) { export(.tiff, name: "nine-slice.tiff") }
    @objc func exportBMP(_ sender: Any?) { export(.bmp, name: "nine-slice.bmp") }

    /// A window that comes back where it was left (across relaunches) and keeps 4:3 content.
    @objc func openAutosaveWindow(_ sender: Any?) {
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
