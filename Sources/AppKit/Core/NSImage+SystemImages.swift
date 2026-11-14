// System images (ADR-0036): the artwork behind AppKit's named images (`NSImage.addTemplateName`
// and friends) and a small catalogue of SF Symbols names, drawn with NSBezierPath into
// template images so they tint like AppKit's. A name without artwork here gives nil, as an
// unknown name does on macOS. Hand-written support code, not AppKit API.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
internal enum _NSSystemImages {
    /// Symbol name → (drawing in a 16×16 box, whether it is a template).
    private static let drawings: [String: (template: Bool, draw: (NSRect) -> Void)] = {
        var d: [String: (Bool, (NSRect) -> Void)] = [:]
        func stroke(_ build: @escaping (NSBezierPath) -> Void, width: CGFloat = 1.6) -> (NSRect) -> Void {
            { _ in let p = NSBezierPath(); p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round; build(p); NSColor.black.setStroke(); p.stroke() }
        }
        func fill(_ build: @escaping (NSBezierPath) -> Void) -> (NSRect) -> Void {
            { _ in let p = NSBezierPath(); build(p); NSColor.black.setFill(); p.fill() }
        }
        func line(_ p: NSBezierPath, _ pts: [(CGFloat, CGFloat)]) { p.move(to: NSPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { p.line(to: NSPoint(x: q.0, y: q.1)) } }
        d["plus"] = (true, stroke { line($0, [(8, 2.5), (8, 13.5)]); line($0, [(2.5, 8), (13.5, 8)]) })
        d["minus"] = (true, stroke { line($0, [(2.5, 8), (13.5, 8)]) })
        d["xmark"] = (true, stroke { line($0, [(3.5, 3.5), (12.5, 12.5)]); line($0, [(3.5, 12.5), (12.5, 3.5)]) })
        d["checkmark"] = (true, stroke { line($0, [(3, 8.5), (6.5, 4.5), (13, 12)]) })
        d["chevron.left"] = (true, stroke { line($0, [(10.5, 2.5), (5, 8), (10.5, 13.5)]) })
        d["chevron.right"] = (true, stroke { line($0, [(5.5, 2.5), (11, 8), (5.5, 13.5)]) })
        d["chevron.up"] = (true, stroke { line($0, [(2.5, 5.5), (8, 11), (13.5, 5.5)]) })
        d["chevron.down"] = (true, stroke { line($0, [(2.5, 10.5), (8, 5), (13.5, 10.5)]) })
        d["arrowtriangle.left.fill"] = (true, fill { line($0, [(11, 3), (4, 8), (11, 13)]); $0.close() })
        d["arrowtriangle.right.fill"] = (true, fill { line($0, [(5, 3), (12, 8), (5, 13)]); $0.close() })
        d["play.fill"] = (true, fill { line($0, [(4.5, 2.5), (13, 8), (4.5, 13.5)]); $0.close() })
        d["pause.fill"] = (true, fill { $0.appendRect(NSRect(x: 4, y: 3, width: 3, height: 10)); $0.appendRect(NSRect(x: 9, y: 3, width: 3, height: 10)) })
        d["stop.fill"] = (true, fill { $0.appendRect(NSRect(x: 3.5, y: 3.5, width: 9, height: 9)) })
        d["circle"] = (true, stroke { $0.appendOval(in: NSRect(x: 2, y: 2, width: 12, height: 12)) })
        d["circle.fill"] = (true, fill { $0.appendOval(in: NSRect(x: 2, y: 2, width: 12, height: 12)) })
        d["ellipsis"] = (true, fill { for x in [3.0, 8.0, 13.0] { $0.appendOval(in: NSRect(x: x - 1.4, y: 6.6, width: 2.8, height: 2.8)) } })
        d["line.3.horizontal"] = (true, stroke { for y in [4.0, 8.0, 12.0] { line($0, [(2.5, y), (13.5, y)]) } })
        d["list.bullet"] = (true, stroke { for y in [4.0, 8.0, 12.0] { line($0, [(6, y), (13.5, y)]); $0.appendOval(in: NSRect(x: 2, y: y - 0.8, width: 1.6, height: 1.6)) } })
        d["square.grid.2x2"] = (true, stroke({ for (x, y) in [(2.5, 2.5), (9, 2.5), (2.5, 9), (9, 9)] { $0.appendRect(NSRect(x: x, y: y, width: 4.5, height: 4.5)) } }, width: 1.2))
        d["magnifyingglass"] = (true, stroke { $0.appendOval(in: NSRect(x: 2.5, y: 5.5, width: 8, height: 8)); line($0, [(9.3, 6.7), (13.5, 2.5)]) })
        d["arrow.clockwise"] = (true, stroke {
            $0.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 5.5, startAngle: 80, endAngle: -200, clockwise: true)
            line($0, [(5.5, 14.5), (8.9, 13.5), (7.2, 10.6)])
        })
        d["exclamationmark.triangle"] = (false, { _ in
            let t = NSBezierPath(); t.move(to: NSPoint(x: 8, y: 14.5)); t.line(to: NSPoint(x: 15, y: 1.5)); t.line(to: NSPoint(x: 1, y: 1.5)); t.close()
            NSColor.systemYellow.setFill(); t.fill()
            let m = NSBezierPath(); m.lineWidth = 1.8; m.lineCapStyle = .round
            m.move(to: NSPoint(x: 8, y: 10.5)); m.line(to: NSPoint(x: 8, y: 6)); NSColor.black.setStroke(); m.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.1, y: 2.8, width: 1.8, height: 1.8)).fill()
        })
        d["info.circle"] = (true, { _ in
            let c = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 13, height: 13)); c.lineWidth = 1.4; NSColor.black.setStroke(); c.stroke()
            let i = NSBezierPath(); i.lineWidth = 1.8; i.lineCapStyle = .round; i.move(to: NSPoint(x: 8, y: 4.5)); i.line(to: NSPoint(x: 8, y: 8.5)); i.stroke()
            NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 7.1, y: 10.2, width: 1.8, height: 1.8)).fill()
        })
        d["square.and.arrow.up"] = (true, stroke { line($0, [(5.5, 9.5), (2.5, 9.5), (2.5, 1.5), (13.5, 1.5), (13.5, 9.5), (10.5, 9.5)]); line($0, [(8, 5), (8, 14.5)]); line($0, [(5, 11.8), (8, 14.5), (11, 11.8)]) })
        d["trash"] = (true, stroke { line($0, [(2.5, 12.5), (13.5, 12.5)]); line($0, [(6, 12.5), (6.5, 14.5), (9.5, 14.5), (10, 12.5)]); line($0, [(3.8, 12.5), (4.8, 1.8), (11.2, 1.8), (12.2, 12.5)]) })
        d["folder"] = (true, stroke { line($0, [(1.5, 2.5), (1.5, 13), (6, 13), (7.5, 11.5), (14.5, 11.5), (14.5, 2.5)]); $0.close() })
        d["doc"] = (true, stroke { line($0, [(3.5, 1.5), (3.5, 14.5), (9.5, 14.5), (12.5, 11.5), (12.5, 1.5)]); $0.close(); line($0, [(9.5, 14.5), (9.5, 11.5), (12.5, 11.5)]) })
        d["person"] = (true, stroke { $0.appendOval(in: NSRect(x: 5.5, y: 8.5, width: 5, height: 5)); $0.appendArc(withCenter: NSPoint(x: 8, y: 1.5), radius: 5.5, startAngle: 0, endAngle: 180) })
        d["person.2"] = (true, stroke({ for cx in [5.5, 10.5] { $0.appendOval(in: NSRect(x: cx - 2, y: 8.5, width: 4, height: 4)); $0.appendArc(withCenter: NSPoint(x: cx, y: 2), radius: 4, startAngle: 0, endAngle: 180) } }, width: 1.3))
        d["house"] = (true, stroke { line($0, [(1.5, 8), (8, 14), (14.5, 8)]); line($0, [(3.5, 9.5), (3.5, 1.5), (12.5, 1.5), (12.5, 9.5)]) })
        d["lock"] = (true, { _ in
            NSColor.black.setFill(); NSBezierPath(roundedRect: NSRect(x: 3, y: 1.5, width: 10, height: 7.5), xRadius: 1.5, yRadius: 1.5).fill()
            let s = NSBezierPath(); s.lineWidth = 1.6; s.appendArc(withCenter: NSPoint(x: 8, y: 10), radius: 3, startAngle: 180, endAngle: 0, clockwise: true)
            s.move(to: NSPoint(x: 5, y: 10)); s.line(to: NSPoint(x: 5, y: 9)); s.move(to: NSPoint(x: 11, y: 10)); s.line(to: NSPoint(x: 11, y: 9)); NSColor.black.setStroke(); s.stroke()
        })
        d["lock.open"] = (true, { _ in
            NSColor.black.setFill(); NSBezierPath(roundedRect: NSRect(x: 3, y: 1.5, width: 10, height: 7.5), xRadius: 1.5, yRadius: 1.5).fill()
            let s = NSBezierPath(); s.lineWidth = 1.6; s.appendArc(withCenter: NSPoint(x: 11, y: 11), radius: 3, startAngle: 180, endAngle: 0, clockwise: true)
            s.move(to: NSPoint(x: 8, y: 11)); s.line(to: NSPoint(x: 8, y: 9)); NSColor.black.setStroke(); s.stroke()
        })
        d["gearshape"] = (true, { _ in
            let p = NSBezierPath()
            for i in 0..<16 {
                let a = CGFloat(i) * .pi / 8, r: CGFloat = i % 2 == 0 ? 7 : 5.4
                let pt = NSPoint(x: 8 + r * cos(a), y: 8 + r * sin(a))
                if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
            }
            p.close()
            p.appendOval(in: NSRect(x: 5.5, y: 5.5, width: 5, height: 5))
            p.windingRule = .evenOdd
            NSColor.black.setFill(); p.fill()
        })
        d["star"] = (true, stroke({ p in
            for i in 0..<10 { let a = CGFloat(i) * .pi / 5 + .pi / 2, r: CGFloat = i % 2 == 0 ? 6.5 : 2.7
                let pt = NSPoint(x: 8 + r * cos(a), y: 7.5 + r * sin(a)); if i == 0 { p.move(to: pt) } else { p.line(to: pt) } }
            p.close() }, width: 1.2))
        d["star.fill"] = (true, fill { p in
            for i in 0..<10 { let a = CGFloat(i) * .pi / 5 + .pi / 2, r: CGFloat = i % 2 == 0 ? 6.5 : 2.7
                let pt = NSPoint(x: 8 + r * cos(a), y: 7.5 + r * sin(a)); if i == 0 { p.move(to: pt) } else { p.line(to: pt) } }
            p.close() })
        d["arrow.up.left.and.arrow.down.right"] = (true, stroke { line($0, [(2.5, 13.5), (6.5, 9.5)]); line($0, [(2.5, 9.5), (2.5, 13.5), (6.5, 13.5)]); line($0, [(13.5, 2.5), (9.5, 6.5)]); line($0, [(9.5, 2.5), (13.5, 2.5), (13.5, 6.5)]) })
        d["arrow.down.right.and.arrow.up.left"] = (true, stroke { line($0, [(2.5, 13.5), (6.5, 9.5)]); line($0, [(2.5, 9.5), (6.5, 9.5), (6.5, 13.5)]); line($0, [(13.5, 2.5), (9.5, 6.5)]); line($0, [(9.5, 2.5), (9.5, 6.5), (13.5, 6.5)]) })
        d["eye"] = (true, stroke { $0.move(to: NSPoint(x: 1.5, y: 8)); $0.curve(to: NSPoint(x: 14.5, y: 8), controlPoint1: NSPoint(x: 5, y: 13.5), controlPoint2: NSPoint(x: 11, y: 13.5)); $0.curve(to: NSPoint(x: 1.5, y: 8), controlPoint1: NSPoint(x: 11, y: 2.5), controlPoint2: NSPoint(x: 5, y: 2.5)); $0.appendOval(in: NSRect(x: 6, y: 6, width: 4, height: 4)) })
        d["book"] = (true, stroke({ line($0, [(8, 3), (8, 13.5)]); line($0, [(8, 13.5), (1.5, 13.5), (1.5, 3), (8, 3), (14.5, 3), (14.5, 13.5), (8, 13.5)]) }, width: 1.3))
        return d
    }()

    /// AppKit's named images and the symbol drawn for each.
    private static let namedImages: [String: String] = [
        "NSAddTemplate": "plus", "NSRemoveTemplate": "minus", "NSStopProgressTemplate": "xmark",
        "NSMenuOnStateTemplate": "checkmark", "NSMenuMixedStateTemplate": "minus",
        "NSGoLeftTemplate": "chevron.left", "NSGoRightTemplate": "chevron.right",
        "NSGoBackTemplate": "chevron.left", "NSGoForwardTemplate": "chevron.right",
        "NSLeftFacingTriangleTemplate": "arrowtriangle.left.fill", "NSRightFacingTriangleTemplate": "arrowtriangle.right.fill",
        "NSRefreshTemplate": "arrow.clockwise", "NSRevealFreestandingTemplate": "magnifyingglass",
        "NSActionTemplate": "gearshape", "NSShareTemplate": "square.and.arrow.up", "NSQuickLookTemplate": "eye",
        "NSLockLockedTemplate": "lock", "NSLockUnlockedTemplate": "lock.open", "NSHomeTemplate": "house",
        "NSListViewTemplate": "list.bullet", "NSIconViewTemplate": "square.grid.2x2", "NSBookmarksTemplate": "book",
        "NSEnterFullScreenTemplate": "arrow.up.left.and.arrow.down.right", "NSExitFullScreenTemplate": "arrow.down.right.and.arrow.up.left",
        "NSSlideshowTemplate": "play.fill", "NSCaution": "exclamationmark.triangle", "NSInfo": "info.circle",
        "NSTrashEmpty": "trash", "NSTrashFull": "trash", "NSFolder": "folder", "NSMultipleDocuments": "doc",
        "NSUser": "person", "NSUserGuest": "person", "NSEveryone": "person.2", "NSUserGroup": "person.2",
        "NSStatusAvailable": "status:green", "NSStatusPartiallyAvailable": "status:yellow",
        "NSStatusUnavailable": "status:red", "NSStatusNone": "status:clear",
        "NSTouchBarAddTemplate": "plus", "NSTouchBarRemoveTemplate": "minus", "NSTouchBarPlayTemplate": "play.fill",
        "NSTouchBarPauseTemplate": "pause.fill", "NSTouchBarSearchTemplate": "magnifyingglass", "NSTouchBarShareTemplate": "square.and.arrow.up",
        "NSTouchBarDeleteTemplate": "trash", "NSTouchBarFolderTemplate": "folder", "NSTouchBarGoBackTemplate": "chevron.left",
        "NSTouchBarGoForwardTemplate": "chevron.right", "NSTouchBarGoUpTemplate": "chevron.up", "NSTouchBarGoDownTemplate": "chevron.down",
        "NSTouchBarRefreshTemplate": "arrow.clockwise", "NSTouchBarUserTemplate": "person", "NSTouchBarUserGroupTemplate": "person.2",
        "NSTouchBarQuickLookTemplate": "eye", "NSTouchBarRecordStopTemplate": "stop.fill", "NSTouchBarListViewTemplate": "list.bullet",
        "NSTouchBarIconViewTemplate": "square.grid.2x2", "NSTouchBarBookmarksTemplate": "book",
    ]

    /// Whether a symbol name has artwork.
    static func hasSymbol(_ name: String) -> Bool { drawings[name] != nil }

    /// A template image of the symbol at `pointSize` (16 pt by default), or nil.
    static func symbol(_ name: String, pointSize: CGFloat = 16) -> NSImage? {
        guard let entry = drawings[name] else { return nil }
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.scaleBy(x: rect.width / 16, y: rect.height / 16)
            entry.draw(NSRect(x: 0, y: 0, width: 16, height: 16))
            ctx.restoreGState()
            return true
        }
        image.isTemplate = entry.template
        return image
    }

    /// The artwork for one of AppKit's image names, or nil.
    static func named(_ name: String) -> NSImage? {
        if name == "NSApplicationIcon" { return NSApplication.shared.applicationIconImage }
        guard let symbolName = namedImages[name] else { return nil }
        if symbolName.hasPrefix("status:") {
            let color: NSColor
            switch symbolName.dropFirst(7) {
            case "green": color = .systemGreen
            case "yellow": color = .systemYellow
            case "red": color = .systemRed
            default: color = .clear
            }
            return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
                let dot = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 10, height: 10))
                color.setFill(); dot.fill()
                NSColor(white: 0, alpha: 0.35).setStroke(); dot.lineWidth = 0.5; dot.stroke()
                return true
            }
        }
        return symbol(symbolName)
    }
}
