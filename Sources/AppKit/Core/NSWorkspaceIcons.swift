// Icons the workspace draws itself (ADR-0022): a document, a folder and an application
// for platforms or themes without one, a badge for the dock tile, and the composition of
// a badge onto an icon. Every platform shows the same drawings for the same answers.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
enum _NSWorkspaceIcons {
    /// A generic icon for the target at `size` points.
    static func drawn(for target: PlatformIconTarget, size: CGFloat) -> NSImage {
        switch target {
        case .folder:
            return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in folder(in: r); return true }
        case .application, .process:
            return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in application(in: r); return true }
        case .fileExtension(let ext):
            return document(label: ext, size: size)
        case .file(let path):
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in folder(in: r); return true }
            }
            return document(label: (path as NSString).pathExtension, size: size)
        }
    }

    private static func document(label: String, size: CGFloat) -> NSImage {
        let text = String(label.uppercased().prefix(4))
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let page = NSRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.05, width: r.width * 0.68, height: r.height * 0.9)
            let fold = page.width * 0.3
            let path = NSBezierPath()
            path.move(to: NSPoint(x: page.minX, y: page.minY))
            path.line(to: NSPoint(x: page.maxX, y: page.minY))
            path.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
            path.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
            path.line(to: NSPoint(x: page.minX, y: page.maxY))
            path.close()
            NSColor.white.setFill(); path.fill()
            NSColor(white: 0.55, alpha: 1).setStroke(); path.lineWidth = max(1, size / 32); path.stroke()
            let corner = NSBezierPath()
            corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
            corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
            corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
            NSColor(white: 0.85, alpha: 1).setFill(); corner.fill()
            NSColor(white: 0.55, alpha: 1).setStroke(); corner.lineWidth = max(1, size / 32); corner.stroke()
            if !text.isEmpty {
                let font = NSFont.boldSystemFont(ofSize: max(6, size * 0.2))
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.35, alpha: 1)]
                let s = NSAttributedString(string: text, attributes: attributes)
                let w = s.size().width
                s.draw(at: NSPoint(x: page.midX - w / 2, y: page.minY + page.height * 0.15))
            }
            return true
        }
    }

    private static func folder(in r: NSRect) {
        let body = NSRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.15, width: r.width * 0.88, height: r.height * 0.6)
        let tab = NSRect(x: body.minX, y: body.maxY - r.height * 0.02, width: body.width * 0.4, height: r.height * 0.14)
        let radius = r.width * 0.06
        NSColor(red: 0.42, green: 0.66, blue: 0.9, alpha: 1).setFill()
        NSBezierPath(roundedRect: tab, xRadius: radius, yRadius: radius).fill()
        NSColor(red: 0.55, green: 0.76, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()
    }

    private static func application(in r: NSRect) {
        let box = r.insetBy(dx: r.width * 0.1, dy: r.height * 0.1)
        NSColor(red: 0.3, green: 0.5, blue: 0.85, alpha: 1).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.width * 0.22, yRadius: box.height * 0.22).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: box.insetBy(dx: box.width * 0.3, dy: box.height * 0.3)).fill()
    }

    /// Up to three icons fanned behind each other (`icon(forFiles:)`).
    static func stack(of icons: [NSImage]) -> NSImage {
        let size = icons.first?.size ?? NSSize(width: NSWorkspace._iconSize, height: NSWorkspace._iconSize)
        return NSImage(size: size, flipped: false) { r in
            for (i, icon) in icons.reversed().enumerated() {
                let offset = CGFloat(icons.count - 1 - i) * size.width * 0.08
                icon.draw(in: r.insetBy(dx: size.width * 0.08, dy: size.height * 0.08).offsetBy(dx: offset, dy: -offset))
            }
            return true
        }
    }

    /// The dock badge: a red pill with the label in white, 16 points high, as pixels.
    static func badge(_ label: String, scale: CGFloat) -> CGImage? {
        let height: CGFloat = 16
        let font = NSFont.boldSystemFont(ofSize: 11)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        let width = max(height, ceil(textSize.width) + 8)
        guard let surface = Platform.backend.image.makeOffscreen(size: CGSize(width: width, height: height), scale: scale) else { return nil }
        let gc = NSGraphicsContext(cgContext: surface.context, flipped: false)
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = gc
        NSColor(red: 0.93, green: 0.2, blue: 0.2, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: height / 2, yRadius: height / 2).fill()
        text.draw(at: NSPoint(x: (width - textSize.width) / 2, y: (height - textSize.height) / 2))
        NSGraphicsContext.current = saved
        return surface.makeImage()
    }

    /// `icon` drawn at `size` with the badge (pixels at `scale`) in the top-right corner.
    static func compose(icon: NSImage, size: NSSize, badge: CGImage?, scale: CGFloat) -> CGImage? {
        guard let surface = Platform.backend.image.makeOffscreen(size: size, scale: scale) else { return nil }
        let gc = NSGraphicsContext(cgContext: surface.context, flipped: false)
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = gc
        icon.draw(in: NSRect(origin: .zero, size: size))
        if let badge {
            let h = size.height * 0.28, w = h * CGFloat(badge.width) / CGFloat(badge.height)
            let rect = NSRect(x: size.width - w - size.width * 0.02, y: size.height - h - size.height * 0.02, width: w, height: h)
            NSImage(cgImage: badge, size: NSSize(width: w, height: h)).draw(in: rect)
        }
        NSGraphicsContext.current = saved
        return surface.makeImage()
    }
}
