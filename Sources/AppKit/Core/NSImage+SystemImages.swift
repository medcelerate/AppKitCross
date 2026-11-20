// System images (ADR-0036): the artwork behind AppKit's named images (`NSImage.addTemplateName`
// and friends) and a small catalogue of SF Symbols names, drawn with NSBezierPath into
// template images so they tint like AppKit's. A name without artwork here is composed from a
// catalogued base when SF Symbols' variant naming allows (`<base>.circle.fill`, `<base>.slash`
// and so on); otherwise it gives nil, as an unknown name does on macOS. Hand-written support code, not AppKit API.

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
        // Sibyl's channel symbols (its inspector's picker), 16-point line drawings.
        d["record.circle"] = (true, { _ in
            let ring = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 13, height: 13)); ring.lineWidth = 1.4; NSColor.black.setStroke(); ring.stroke()
            NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 6, height: 6)).fill()
        })
        d["headphones"] = (true, stroke {
            // The headband over the top (clockwise from the left, through 90°; counterclockwise
            // from 180° to 0° runs under the centre and drew a "u").
            $0.appendArc(withCenter: NSPoint(x: 8, y: 7), radius: 5.5, startAngle: 180, endAngle: 0, clockwise: true)
            $0.appendRoundedRect(NSRect(x: 2, y: 2.5, width: 3, height: 5), xRadius: 1, yRadius: 1)
            $0.appendRoundedRect(NSRect(x: 11, y: 2.5, width: 3, height: 5), xRadius: 1, yRadius: 1)
        })
        d["lightbulb"] = (true, stroke {
            // The bulb: 250° over the top, open at the bottom for the base (from 215° to -35°
            // counterclockwise ran the short way under the centre, leaving no top).
            $0.appendArc(withCenter: NSPoint(x: 8, y: 9.5), radius: 4.5, startAngle: -35, endAngle: 215, clockwise: false)
            line($0, [(5.5, 6.2), (6, 3.5), (10, 3.5), (10.5, 6.2)])
            line($0, [(6.5, 1.8), (9.5, 1.8)])
        })
        d["person.wave.2"] = (true, stroke({
            // A bust (head over a domed pair of shoulders) with two sound arcs to its right,
            // centred on the head. Each part is its own subpath: an arc appended after another
            // shape joins it with a line from the current point, which drew a tangled blob.
            $0.appendOval(in: NSRect(x: 4.2, y: 7.6, width: 5, height: 5))
            $0.move(to: NSPoint(x: 1.5, y: 2)); $0.line(to: NSPoint(x: 11.5, y: 2))
            $0.curve(to: NSPoint(x: 1.5, y: 2), controlPoint1: NSPoint(x: 11.5, y: 8.1), controlPoint2: NSPoint(x: 1.5, y: 8.1))
            $0.close()
            for (r, sweep) in [(CGFloat(5), CGFloat(38)), (8, 30)] {
                let a = sweep * .pi / 180
                $0.move(to: NSPoint(x: 6.7 + r * cos(-a), y: 10.1 + r * sin(-a)))
                $0.appendArc(withCenter: NSPoint(x: 6.7, y: 10.1), radius: r, startAngle: -sweep, endAngle: sweep, clockwise: false)
            }
        }, width: 1.4))
        d["person.3"] = (true, stroke {
            for x in [3.0, 8.0, 13.0] {
                $0.appendOval(in: NSRect(x: x - 1.6, y: 8.5, width: 3.2, height: 3.2))
                $0.appendArc(withCenter: NSPoint(x: x, y: 3.5), radius: 2.8, startAngle: 20, endAngle: 160, clockwise: false)
            }
        })
        d["camera"] = (true, stroke {
            $0.appendRoundedRect(NSRect(x: 1.5, y: 3, width: 13, height: 9), xRadius: 1.5, yRadius: 1.5)
            line($0, [(5.5, 3), (6.5, 1.5), (9.5, 1.5), (10.5, 3)])
            $0.appendOval(in: NSRect(x: 5.5, y: 5, width: 5, height: 5))
        })
        d["video"] = (true, stroke {
            $0.appendRoundedRect(NSRect(x: 1.5, y: 3.5, width: 9, height: 9), xRadius: 1.5, yRadius: 1.5)
            line($0, [(10.5, 6.5), (14.5, 4), (14.5, 12), (10.5, 9.5)])
        })
        d["flag.checkered"] = (true, { _ in
            let p = NSBezierPath(); p.lineWidth = 1.6; p.lineCapStyle = .round
            p.move(to: NSPoint(x: 3, y: 1.5)); p.line(to: NSPoint(x: 3, y: 14.5)); NSColor.black.setStroke(); p.stroke()
            let f = NSBezierPath(); f.move(to: NSPoint(x: 3, y: 14)); f.line(to: NSPoint(x: 13.5, y: 14)); f.line(to: NSPoint(x: 13.5, y: 7)); f.line(to: NSPoint(x: 3, y: 7)); f.close(); f.lineWidth = 1.2; f.stroke()
            NSColor.black.setFill()
            for (x, y) in [(3, 10.5), (6.5, 7), (6.5, 14), (10, 10.5)] { NSBezierPath(rect: NSRect(x: CGFloat(x), y: CGFloat(y) - 3.5, width: 3.5, height: 3.5)).fill() }
        })
        d["music.mic"] = (true, stroke {
            $0.appendOval(in: NSRect(x: 8.5, y: 8.5, width: 5.5, height: 5.5))
            line($0, [(9.2, 9.2), (2.5, 2.5)])
            line($0, [(5, 4), (6.5, 6.5)])
        })
        d["theatermasks"] = (true, stroke {
            // Each mask's chin curves below its brow line (through 270°).
            $0.appendArc(withCenter: NSPoint(x: 5.5, y: 9), radius: 4, startAngle: 180, endAngle: 0, clockwise: false)
            line($0, [(1.5, 9), (1.5, 13), (9.5, 13), (9.5, 9)])
            $0.appendArc(withCenter: NSPoint(x: 11, y: 6), radius: 3.5, startAngle: 180, endAngle: 0, clockwise: false)
            line($0, [(7.5, 6), (7.5, 9.5), (14.5, 9.5), (14.5, 6)])
        })
        d["wrench.and.screwdriver"] = (true, stroke {
            line($0, [(2.5, 13.5), (9, 7)])
            $0.appendArc(withCenter: NSPoint(x: 11, y: 5), radius: 2.8, startAngle: 60, endAngle: 330, clockwise: false)
            line($0, [(13.5, 13.5), (6, 6)])
            line($0, [(5, 3.5), (3, 1.5), (1.5, 3), (3.5, 5)])
        })
        d["rectangle.3.group"] = (true, stroke({
            $0.appendRoundedRect(NSRect(x: 1.5, y: 2, width: 6, height: 12), xRadius: 1, yRadius: 1)
            $0.appendRoundedRect(NSRect(x: 9, y: 8.5, width: 5.5, height: 5.5), xRadius: 1, yRadius: 1)
            $0.appendRoundedRect(NSRect(x: 9, y: 2, width: 5.5, height: 5), xRadius: 1, yRadius: 1)
        }, width: 1.2))
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

        // The symbols a real app (Sibyl) uses. Filled variants with a cut-out mark are one
        // even-odd path, so they need no blend mode (Direct2D's context ignores them).
        func poly(_ p: NSBezierPath, _ pts: [(CGFloat, CGFloat)]) { line(p, pts); p.close() }
        /// An arc anticlockwise from `a0` to `a1` degrees, starting a new subpath.
        func arc(_ p: NSBezierPath, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ a0: CGFloat, _ a1: CGFloat) {
            p.move(to: NSPoint(x: cx + r * cos(a0 * .pi / 180), y: cy + r * sin(a0 * .pi / 180)))
            p.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r, startAngle: a0, endAngle: a1, clockwise: false)
        }
        func dot(_ p: NSBezierPath, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) { p.appendOval(in: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)) }
        func seal(_ p: NSBezierPath) {
            for i in 0..<24 { let a = CGFloat(i) * .pi / 12 + .pi / 2, r: CGFloat = i % 2 == 0 ? 7 : 5.9
                let pt = NSPoint(x: 8 + r * cos(a), y: 8 + r * sin(a)); if i == 0 { p.move(to: pt) } else { p.line(to: pt) } }
            p.close()
        }
        /// A heavy checkmark as one outline (cut out of a filled shape).
        func checkOutline(_ p: NSBezierPath) { poly(p, [(4, 8.4), (5.2, 9.5), (7.1, 7.4), (10.9, 11.6), (12.1, 10.5), (7.1, 5.1)]) }
        func bubble(_ p: NSBezierPath) {
            p.appendRoundedRect(NSRect(x: 1.5, y: 4.5, width: 13, height: 9.5), xRadius: 2.5, yRadius: 2.5)
            line(p, [(4.5, 4.5), (3.5, 1.5), (7.5, 4.5)])
        }
        let boltPoints: [(CGFloat, CGFloat)] = [(9.5, 14.5), (3.5, 7.2), (7.4, 7.2), (6.5, 1.5), (12.5, 8.8), (8.6, 8.8)]
        func bell(_ p: NSBezierPath) {
            p.move(to: NSPoint(x: 2.5, y: 4.5)); p.line(to: NSPoint(x: 13.5, y: 4.5)); p.line(to: NSPoint(x: 12, y: 6.5)); p.line(to: NSPoint(x: 12, y: 9))
            p.curve(to: NSPoint(x: 4, y: 9), controlPoint1: NSPoint(x: 12, y: 14.5), controlPoint2: NSPoint(x: 4, y: 14.5))
            p.line(to: NSPoint(x: 4, y: 6.5)); p.close()
        }
        func letterA(_ p: NSBezierPath, x: CGFloat, width w: CGFloat, height h: CGFloat) {
            line(p, [(x, 2.5), (x + w / 2, 2.5 + h), (x + w, 2.5)]); line(p, [(x + w * 0.22, 2.5 + h * 0.4), (x + w * 0.78, 2.5 + h * 0.4)])
        }
        d["antenna.radiowaves.left.and.right"] = (true, stroke({
            line($0, [(8, 9), (8, 1.5)]); dot($0, 8, 9.5, 1)
            arc($0, 8, 9.5, 3.2, 130, 230); arc($0, 8, 9.5, 3.2, -50, 50)
            arc($0, 8, 9.5, 6, 135, 225); arc($0, 8, 9.5, 6, -45, 45)
        }, width: 1.3))
        d["arrow.counterclockwise"] = (true, stroke {
            $0.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 5.5, startAngle: 100, endAngle: 380, clockwise: false)
            line($0, [(10.5, 14.5), (7.1, 13.5), (8.8, 10.6)])
        })
        d["arrow.left"] = (true, stroke { line($0, [(13.5, 8), (2.5, 8)]); line($0, [(7, 12.5), (2.5, 8), (7, 3.5)]) })
        d["arrow.right"] = (true, stroke { line($0, [(2.5, 8), (13.5, 8)]); line($0, [(9, 12.5), (13.5, 8), (9, 3.5)]) })
        d["arrow.left.and.right"] = (true, stroke { line($0, [(2.5, 8), (13.5, 8)]); line($0, [(5.5, 11), (2.5, 8), (5.5, 5)]); line($0, [(10.5, 11), (13.5, 8), (10.5, 5)]) })
        d["arrow.left.and.right.square"] = (true, stroke({
            $0.appendRoundedRect(NSRect(x: 1.5, y: 1.5, width: 13, height: 13), xRadius: 2.5, yRadius: 2.5)
            line($0, [(4.5, 8), (11.5, 8)]); line($0, [(6.5, 10), (4.5, 8), (6.5, 6)]); line($0, [(9.5, 10), (11.5, 8), (9.5, 6)])
        }, width: 1.3))
        d["bell"] = (true, stroke({ bell($0); arc($0, 8, 4.5, 1.8, 180, 360) }, width: 1.3))
        d["bell.fill"] = (true, fill { bell($0); dot($0, 8, 3, 1.8) })
        d["bell.badge"] = (true, { r in
            stroke({ bell($0); arc($0, 8, 4.5, 1.8, 180, 360) }, width: 1.3)(r)
            fill { dot($0, 12.5, 12.5, 2.6) }(r)
        })
        d["bell.badge.fill"] = (true, fill { bell($0); dot($0, 8, 3, 1.8); dot($0, 12.8, 12.8, 2.6) })
        d["bolt"] = (true, stroke({ poly($0, boltPoints) }, width: 1.3))
        d["bolt.fill"] = (true, fill { poly($0, boltPoints) })
        d["bolt.horizontal"] = (true, stroke({ poly($0, boltPoints.map { (x, y) in (y, 16 - x) }) }, width: 1.3))
        d["bookmark"] = (true, stroke({ poly($0, [(4, 14.5), (12, 14.5), (12, 1.5), (8, 5), (4, 1.5)]) }, width: 1.4))
        d["cable.connector"] = (true, stroke({
            $0.appendRoundedRect(NSRect(x: 4.5, y: 5, width: 7, height: 6), xRadius: 1, yRadius: 1)
            line($0, [(6.5, 11), (6.5, 14.5)]); line($0, [(9.5, 11), (9.5, 14.5)]); line($0, [(8, 5), (8, 1.5)])
        }, width: 1.3))
        d["character.bubble"] = (true, stroke({ bubble($0); line($0, [(5.6, 6.5), (8, 12), (10.4, 6.5)]); line($0, [(6.5, 8.6), (9.5, 8.6)]) }, width: 1.2))
        d["text.bubble"] = (true, stroke({ bubble($0); line($0, [(4.5, 10.5), (11.5, 10.5)]); line($0, [(4.5, 7.5), (9.5, 7.5)]) }, width: 1.2))
        d["chart.bar.doc.horizontal"] = (true, stroke({
            $0.appendRoundedRect(NSRect(x: 2.5, y: 1.5, width: 11, height: 13), xRadius: 1.5, yRadius: 1.5)
            line($0, [(5, 11), (10.5, 11)]); line($0, [(5, 8), (8.5, 8)]); line($0, [(5, 5), (11, 5)])
        }, width: 1.3))
        d["checkmark.circle.fill"] = (true, { _ in
            let p = NSBezierPath(); dot(p, 8, 8, 7); checkOutline(p); p.windingRule = .evenOdd; NSColor.black.setFill(); p.fill()
        })
        d["minus.circle.fill"] = (true, { _ in
            let p = NSBezierPath(); dot(p, 8, 8, 7); p.appendRect(NSRect(x: 4.2, y: 7.1, width: 7.6, height: 1.8)); p.windingRule = .evenOdd; NSColor.black.setFill(); p.fill()
        })
        d["plus.circle.fill"] = (true, { _ in
            let p = NSBezierPath(); dot(p, 8, 8, 7)
            poly(p, [(4.2, 7.1), (7.1, 7.1), (7.1, 4.2), (8.9, 4.2), (8.9, 7.1), (11.8, 7.1), (11.8, 8.9), (8.9, 8.9), (8.9, 11.8), (7.1, 11.8), (7.1, 8.9), (4.2, 8.9)])
            p.windingRule = .evenOdd; NSColor.black.setFill(); p.fill()
        })
        d["xmark.circle.fill"] = (true, { _ in
            let p = NSBezierPath(); dot(p, 8, 8, 7)
            poly(p, [(4.8, 5.9), (5.9, 4.8), (8, 6.9), (10.1, 4.8), (11.2, 5.9), (9.1, 8), (11.2, 10.1), (10.1, 11.2), (8, 9.1), (5.9, 11.2), (4.8, 10.1), (6.9, 8)])
            p.windingRule = .evenOdd; NSColor.black.setFill(); p.fill()
        })
        d["checkmark.seal"] = (true, stroke({ seal($0); line($0, [(5.2, 8.2), (7.2, 6), (10.8, 10.2)]) }, width: 1.2))
        d["checkmark.seal.fill"] = (true, { _ in let p = NSBezierPath(); seal(p); checkOutline(p); p.windingRule = .evenOdd; NSColor.black.setFill(); p.fill() })
        d["xmark.seal"] = (true, stroke({ seal($0); line($0, [(5.8, 5.8), (10.2, 10.2)]); line($0, [(5.8, 10.2), (10.2, 5.8)]) }, width: 1.2))
        d["chevron.compact.left"] = (true, stroke { line($0, [(9.5, 2.5), (6.5, 8), (9.5, 13.5)]) })
        d["chevron.compact.right"] = (true, stroke { line($0, [(6.5, 2.5), (9.5, 8), (6.5, 13.5)]) })
        d["clock"] = (true, stroke({ dot($0, 8, 8, 6.5); line($0, [(8, 12), (8, 8), (11, 8)]) }, width: 1.3))
        d["desktopcomputer"] = (true, stroke({
            $0.appendRoundedRect(NSRect(x: 1.5, y: 5, width: 13, height: 9), xRadius: 1.2, yRadius: 1.2)
            line($0, [(8, 5), (8, 2.5)]); line($0, [(5, 2), (11, 2)])
        }, width: 1.3))
        d["eraser"] = (true, stroke({ poly($0, [(2, 7), (6.5, 2.5), (14, 10), (9.5, 14.5)]); line($0, [(4.5, 9.5), (9, 5)]); line($0, [(6.5, 2.5), (14, 2.5)]) }, width: 1.2))
        d["exclamationmark.triangle.fill"] = (true, { _ in
            let p = NSBezierPath(); poly(p, [(8, 14.8), (15.2, 1.5), (0.8, 1.5)])
            p.appendRoundedRect(NSRect(x: 7.1, y: 5.8, width: 1.8, height: 5.2), xRadius: 0.9, yRadius: 0.9); dot(p, 8, 3.7, 1)
            p.windingRule = .evenOdd; NSColor.black.setFill(); p.fill()
        })
        d["globe"] = (true, stroke({ dot($0, 8, 8, 6.5); $0.appendOval(in: NSRect(x: 5, y: 1.5, width: 6, height: 13)); line($0, [(1.5, 8), (14.5, 8)]); line($0, [(2.5, 11.2), (13.5, 11.2)]); line($0, [(2.5, 4.8), (13.5, 4.8)]) }, width: 1.1))
        d["highlighter"] = (true, stroke({ poly($0, [(4.5, 7), (9.5, 12.5), (13.5, 8.5), (8, 3.5)]); poly($0, [(4.5, 7), (2.5, 3.5), (8, 3.5)]); line($0, [(1.5, 1.5), (14.5, 1.5)]) }, width: 1.2))
        d["list.bullet.rectangle"] = (true, stroke({
            $0.appendRoundedRect(NSRect(x: 1.5, y: 2, width: 13, height: 12), xRadius: 2, yRadius: 2)
            for y in [5.0, 8.0, 11.0] { line($0, [(6.5, y), (12, y)]); dot($0, 4.3, y, 0.6) }
        }, width: 1.2))
        d["network"] = (true, stroke({
            dot($0, 8, 12.5, 2); dot($0, 3.5, 3.5, 2); dot($0, 12.5, 3.5, 2)
            line($0, [(7, 10.7), (4.5, 5.3)]); line($0, [(9, 10.7), (11.5, 5.3)]); line($0, [(5.5, 3.5), (10.5, 3.5)])
        }, width: 1.2))
        d["paintbrush"] = (true, stroke({
            line($0, [(14, 14), (7.5, 7.5)])
            $0.move(to: NSPoint(x: 7.5, y: 7.5)); $0.curve(to: NSPoint(x: 1.5, y: 1.5), controlPoint1: NSPoint(x: 4, y: 8.5), controlPoint2: NSPoint(x: 5, y: 3))
            $0.curve(to: NSPoint(x: 7.5, y: 7.5), controlPoint1: NSPoint(x: 6, y: 1.5), controlPoint2: NSPoint(x: 8.5, y: 4.5))
        }, width: 1.3))
        d["pianokeys"] = (true, { r in
            stroke({ $0.appendRect(NSRect(x: 1.5, y: 2, width: 13, height: 12)); line($0, [(5.8, 2), (5.8, 14)]); line($0, [(10.2, 2), (10.2, 14)]) }, width: 1.2)(r)
            fill { $0.appendRect(NSRect(x: 4.4, y: 7, width: 2.8, height: 7)); $0.appendRect(NSRect(x: 8.8, y: 7, width: 2.8, height: 7)) }(r)
        })
        d["point.3.connected.trianglepath.dotted"] = (true, { r in
            fill { dot($0, 8, 13, 1.8); dot($0, 2.8, 3.5, 1.8); dot($0, 13.2, 3.5, 1.8) }(r)
            stroke({ p in
                for (a, b) in [((8.0, 13.0), (2.8, 3.5)), ((8.0, 13.0), (13.2, 3.5)), ((2.8, 3.5), (13.2, 3.5))] {
                    for t in stride(from: 0.25, to: 0.8, by: 0.2) {     // dashes between the dots
                        let x0 = a.0 + (b.0 - a.0) * t, y0 = a.1 + (b.1 - a.1) * t
                        let x1 = a.0 + (b.0 - a.0) * (t + 0.08), y1 = a.1 + (b.1 - a.1) * (t + 0.08)
                        line(p, [(x0, y0), (x1, y1)])
                    }
                }
            }, width: 1.1)(r)
        })
        d["puzzlepiece.extension"] = (true, stroke({ $0.appendRect(NSRect(x: 2, y: 2, width: 9.5, height: 9.5)); arc($0, 6.75, 11.5, 2, 0, 180); arc($0, 11.5, 6.75, 2, -90, 90) }, width: 1.2))
        d["questionmark"] = (true, stroke({ $0.appendArc(withCenter: NSPoint(x: 8, y: 10.5), radius: 3, startAngle: 160, endAngle: -60, clockwise: true); line($0, [(9.5, 7.9), (8, 6.8), (8, 5.2)]); dot($0, 8, 2.5, 0.4) }, width: 1.8))
        d["questionmark.circle"] = (true, stroke({
            dot($0, 8, 8, 6.5)
            $0.appendArc(withCenter: NSPoint(x: 8, y: 9.8), radius: 2, startAngle: 160, endAngle: -60, clockwise: true); line($0, [(9, 8.1), (8, 7.3), (8, 6.3)]); dot($0, 8, 4.3, 0.3)
        }, width: 1.3))
        d["rectangle.expand.vertical"] = (true, stroke({
            // SF Symbols' artwork: a wide rectangle open at the middle of its top and bottom
            // edges, with an arrow leaving through each opening (up and down).
            line($0, [(5.5, 11.5), (1.5, 11.5), (1.5, 4.5), (5.5, 4.5)])
            line($0, [(10.5, 11.5), (14.5, 11.5), (14.5, 4.5), (10.5, 4.5)])
            line($0, [(8, 10.3), (8, 14.5)]); line($0, [(6, 12.5), (8, 14.5), (10, 12.5)])
            line($0, [(8, 5.7), (8, 1.5)]); line($0, [(6, 3.5), (8, 1.5), (10, 3.5)])
        }, width: 1.3))
        d["sidebar.trailing"] = (true, stroke({ $0.appendRoundedRect(NSRect(x: 1.5, y: 2.5, width: 13, height: 11), xRadius: 2, yRadius: 2); line($0, [(10, 2.5), (10, 13.5)]) }, width: 1.2))
        d["sidebar.leading"] = (true, stroke({ $0.appendRoundedRect(NSRect(x: 1.5, y: 2.5, width: 13, height: 11), xRadius: 2, yRadius: 2); line($0, [(6, 2.5), (6, 13.5)]) }, width: 1.2))
        d["speaker"] = (true, stroke({ poly($0, [(2, 6), (5, 6), (9, 2.5), (9, 13.5), (5, 10), (2, 10)]) }, width: 1.3))
        d["speaker.wave.2"] = (true, stroke({ poly($0, [(1.5, 6), (4.5, 6), (8, 2.5), (8, 13.5), (4.5, 10), (1.5, 10)]); arc($0, 8, 8, 3, -45, 45); arc($0, 8, 8, 5.5, -45, 45) }, width: 1.3))
        d["square.grid.3x3"] = (true, stroke({ for x in [1.8, 6.4, 11.0] { for y in [1.8, 6.4, 11.0] { $0.appendRect(NSRect(x: x, y: y, width: 3.2, height: 3.2)) } } }, width: 1))
        d["textformat.size.larger"] = (true, stroke({ letterA($0, x: 1.5, width: 4.5, height: 5.5); letterA($0, x: 6.5, width: 8, height: 11) }, width: 1.2))
        d["textformat.size.smaller"] = (true, stroke({ letterA($0, x: 1.5, width: 8, height: 11); letterA($0, x: 10, width: 4.5, height: 5.5) }, width: 1.2))
        d["tv"] = (true, stroke({ $0.appendRoundedRect(NSRect(x: 1.5, y: 4, width: 13, height: 9), xRadius: 1.5, yRadius: 1.5); line($0, [(5, 2), (11, 2)]) }, width: 1.3))
        d["tv.badge.wifi"] = (true, stroke({
            $0.appendRoundedRect(NSRect(x: 1.5, y: 4, width: 13, height: 9), xRadius: 1.5, yRadius: 1.5); line($0, [(5, 2), (11, 2)])
            arc($0, 8, 6, 2.2, 50, 130); arc($0, 8, 6, 4.4, 50, 130); dot($0, 8, 6.4, 0.3)
        }, width: 1.2))
        d["waveform"] = (true, stroke({ for (x, h) in [(2.0, 3.0), (4.4, 7.0), (6.8, 11.0), (9.2, 6.0), (11.6, 9.0), (14.0, 4.0)] { line($0, [(x, 8 - h / 2), (x, 8 + h / 2)]) } }, width: 1.4))
        return d
    }()

    typealias _Drawing = (template: Bool, draw: (NSRect) -> Void)

    /// The drawing for a symbol name: the catalogue's own, or one composed from a catalogued
    /// base the way SF Symbols names its variants (`<base>.circle`, `<base>.circle.fill`,
    /// `<base>.square`, `<base>.square.fill`, `<base>.fill`, `<base>.slash`); nil otherwise.
    private static func drawing(_ name: String) -> _Drawing? {
        if let d = drawings[name] { return d }
        func base(_ suffix: String) -> _Drawing? {
            guard name.hasSuffix(suffix), name.count > suffix.count else { return nil }
            // A base catalogued only in its filled form (`play.fill` for `play.circle`).
            let stem = String(name.dropLast(suffix.count))
            return drawing(stem) ?? (suffix == ".fill" ? nil : drawings[stem + ".fill"])
        }
        func inset(_ glyph: _Drawing, scale: CGFloat) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState(); ctx.translateBy(x: 8, y: 8); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -8, y: -8)
            glyph.draw(NSRect(x: 0, y: 0, width: 16, height: 16))
            ctx.restoreGState()
        }
        /// The glyph cut out of what is drawn (where the context has blend modes: Direct2D's
        /// does not yet, and there the glyph is not cut out).
        func knockOut(_ glyph: _Drawing, scale: CGFloat) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState(); ctx.setBlendMode(.destinationOut); inset(glyph, scale: scale); ctx.restoreGState()
        }
        func filled(_ shape: NSBezierPath) { NSColor.black.setFill(); shape.fill() }
        func outlined(_ shape: NSBezierPath) { shape.lineWidth = 1.3; NSColor.black.setStroke(); shape.stroke() }
        let disc = { NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 14, height: 14)) }
        let ring = { NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 13, height: 13)) }
        let box = { NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 14, height: 14), xRadius: 3, yRadius: 3) }
        let frame = { NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 13, height: 13), xRadius: 3, yRadius: 3) }
        if let g = base(".circle.fill") { return (g.template, { _ in filled(disc()); knockOut(g, scale: 0.55) }) }
        if let g = base(".square.fill") { return (g.template, { _ in filled(box()); knockOut(g, scale: 0.55) }) }
        if let g = base(".circle") { return (g.template, { _ in outlined(ring()); inset(g, scale: 0.55) }) }
        if let g = base(".square") { return (g.template, { _ in outlined(frame()); inset(g, scale: 0.55) }) }
        if let g = base(".fill") { return g }                  // the drawn glyph stands for its filled form
        if let g = base(".slash") {
            return (g.template, { r in
                g.draw(r)
                let slash = NSBezierPath(); slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 2.5, y: 13.5)); slash.line(to: NSPoint(x: 13.5, y: 2.5))
                if let ctx = NSGraphicsContext.current?.cgContext {    // a gap either side of the slash
                    ctx.saveGState(); ctx.setBlendMode(.destinationOut); slash.lineWidth = 3.6; NSColor.black.setStroke(); slash.stroke(); ctx.restoreGState()
                }
                slash.lineWidth = 1.6; NSColor.black.setStroke(); slash.stroke()
            })
        }
        return nil
    }

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
    static func hasSymbol(_ name: String) -> Bool { drawing(name) != nil }

    /// A template image of the symbol at `pointSize` (16 pt by default), or nil.
    static func symbol(_ name: String, pointSize: CGFloat = 16) -> NSImage? {
        guard let entry = drawing(name) else { return nil }
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
