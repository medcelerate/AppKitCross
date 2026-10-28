// Windows font engine over the CDirectWrite shim. Glyphs draw as filled outlines through
// CGContext (so clipping and the CTM apply); DrawGlyphRun can replace that later.

#if os(Windows)
import Foundation
import CoreGraphics
import CDirectWrite

final class CTDirectWriteFont: CTEngineFont {
    let handle: OpaquePointer            // CDWFont*, owned
    let size: CGFloat
    private let m: CDWFontMetrics
    let familyName: String, styleName: String, fullName: String, postScriptName: String
    private var pathCache: [CGGlyph: CGPath?] = [:]

    init(handle: OpaquePointer) {
        self.handle = handle
        size = CGFloat(cdw_font_size(handle))
        var metrics = CDWFontMetrics()
        cdw_font_metrics(handle, &metrics)
        m = metrics
        func name(_ which: Int32) -> String {
            var buf = [CChar](repeating: 0, count: 256)
            _ = cdw_font_name(handle, which, &buf, buf.count)
            return String(cString: buf)
        }
        familyName = name(0)
        styleName = name(1)
        fullName = name(2)
        postScriptName = name(3)
    }

    deinit { cdw_font_release(handle) }

    var ascent: CGFloat { CGFloat(m.ascent) }
    var descent: CGFloat { CGFloat(m.descent) }
    var leading: CGFloat { CGFloat(m.lineGap) }
    var capHeight: CGFloat { CGFloat(m.capHeight) }
    var xHeight: CGFloat { CGFloat(m.xHeight) }
    var underlinePosition: CGFloat { CGFloat(m.underlinePosition) }
    var underlineThickness: CGFloat { max(0.5, CGFloat(m.underlineThickness)) }
    var unitsPerEm: UInt32 { m.unitsPerEm }
    var glyphCount: Int { Int(m.glyphCount) }
    var isBold: Bool { m.isBold }
    var isItalic: Bool { m.isItalic }
    var isMonospace: Bool { m.isMonospace }
    var weight: CGFloat { CGFloat(Int(m.weight) - 400) / 750 }
    var slant: CGFloat { m.isItalic ? -0.2 : 0 }
    var boundingBox: CGRect { CGRect(x: 0, y: -descent, width: size, height: ascent + descent) }

    func glyphs(for units: [UInt16]) -> [CGGlyph] {
        var scalars: [UInt32] = []
        var slots: [Int] = []
        var i = 0
        while i < units.count {
            var scalar = UInt32(units[i])
            var width = 1
            if (0xD800...0xDBFF).contains(units[i]), i + 1 < units.count, (0xDC00...0xDFFF).contains(units[i + 1]) {
                scalar = 0x10000 + ((UInt32(units[i]) - 0xD800) << 10) + (UInt32(units[i + 1]) - 0xDC00)
                width = 2
            }
            scalars.append(scalar)
            slots.append(i)
            i += width
        }
        var mapped = [UInt16](repeating: 0, count: scalars.count)
        if !scalars.isEmpty { cdw_font_glyphs(handle, scalars, UInt32(scalars.count), &mapped) }
        var out = [CGGlyph](repeating: 0, count: units.count)
        for (n, slot) in slots.enumerated() { out[slot] = mapped[n] }
        return out
    }

    func advances(for glyphs: [CGGlyph]) -> [CGSize] {
        guard !glyphs.isEmpty else { return [] }
        var adv = [Float](repeating: 0, count: glyphs.count)
        cdw_font_advances(handle, glyphs, UInt32(glyphs.count), &adv)
        return adv.map { CGSize(width: CGFloat($0), height: 0) }
    }

    func boundingRects(for glyphs: [CGGlyph]) -> [CGRect] {
        guard !glyphs.isEmpty else { return [] }
        var r = [Float](repeating: 0, count: glyphs.count * 4)
        cdw_font_bounds(handle, glyphs, UInt32(glyphs.count), &r)
        return (0..<glyphs.count).map { CGRect(x: CGFloat(r[$0 * 4]), y: CGFloat(r[$0 * 4 + 1]), width: CGFloat(r[$0 * 4 + 2]), height: CGFloat(r[$0 * 4 + 3])) }
    }

    private final class Builder { let path = CGMutablePath() }

    func path(for glyph: CGGlyph) -> CGPath? {
        if let cached = pathCache[glyph] { return cached }
        let b = Builder()
        let ok = cdw_font_glyph_path(handle, glyph, { ctx, op, x1, y1, x2, y2, x3, y3 in
            let b = Unmanaged<Builder>.fromOpaque(ctx!).takeUnretainedValue()
            switch op {
            case 0: b.path.move(to: CGPoint(x: CGFloat(x1), y: CGFloat(y1)))
            case 1: b.path.addLine(to: CGPoint(x: CGFloat(x1), y: CGFloat(y1)))
            case 2: b.path.addCurve(to: CGPoint(x: CGFloat(x3), y: CGFloat(y3)), control1: CGPoint(x: CGFloat(x1), y: CGFloat(y1)), control2: CGPoint(x: CGFloat(x2), y: CGFloat(y2)))
            default: b.path.closeSubpath()
            }
        }, Unmanaged.passUnretained(b).toOpaque())
        let result: CGPath? = ok && !b.path.isEmpty ? b.path : nil
        pathCache[glyph] = result
        return result
    }

    func hasTable(_ tag: UInt32) -> Bool { table(tag) != nil }

    func table(_ tag: UInt32) -> Data? {
        var data: UnsafeRawPointer? = nil
        var size: UInt32 = 0
        var context: UnsafeMutableRawPointer? = nil
        guard cdw_font_table(handle, tag, &data, &size, &context), let data, size > 0 else { return nil }
        defer { cdw_font_table_release(handle, context) }
        return Data(bytes: data, count: Int(size))
    }

    func availableTables() -> [UInt32] {
        ["cmap", "head", "hhea", "hmtx", "maxp", "name", "OS/2", "post", "glyf", "loca", "CFF ", "GSUB", "GPOS", "GDEF", "kern"].map { UInt32(fourCharacterCode: $0) }.filter { hasTable($0) }
    }

    func glyph(named name: String) -> CGGlyph { 0 }   // DirectWrite exposes no glyph names

    func draw(glyphs: [CGGlyph], positions: [CGPoint], color: CGColor, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(color)
        for (i, g) in glyphs.enumerated() {
            guard let p = path(for: g) else { continue }
            ctx.saveGState()
            ctx.translateBy(x: positions[i].x, y: positions[i].y)
            ctx.addPath(p)
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    func withSize(_ size: CGFloat) -> CTEngineFont {
        guard let h = cdw_font_with_size(handle, Float(size)) else { return self }
        return CTDirectWriteFont(handle: h)
    }
}

final class CTDirectWriteEngine: CTEngine {
    var familyNames: [String] {
        (0..<cdw_family_count()).compactMap { i in
            var buf = [CChar](repeating: 0, count: 256)
            return cdw_family_name(i, &buf, buf.count) > 0 ? String(cString: buf) : nil
        }
    }

    func makeFont(name: String?, size: CGFloat, weight: CGFloat?, italic: Bool?, uiType: CTFontUIFontType) -> CTEngineFont? {
        var found = false
        let dwWeight: Int32 = weight.map { Int32(min(900, max(100, (400 + $0 * 750).rounded()))) } ?? 0
        guard let h = cdw_font_create(name, Float(size), dwWeight, italic ?? false, uiType == .userFixedPitch, &found) else { return nil }
        return CTDirectWriteFont(handle: h)
    }

    func shape(_ units: [UInt16], font: CTEngineFont, language: String?) -> [CTShapedRun] {
        guard let f = font as? CTDirectWriteFont, !units.isEmpty, let shaped = cdw_shape(units, UInt32(units.count), f.handle, language) else { return [] }
        defer { cdw_shaped_release(shaped) }
        var runs: [CTShapedRun] = []
        for i in 0..<cdw_shaped_run_count(shaped) {
            var r = CDWRun()
            guard cdw_shaped_run(shaped, i, &r) else { continue }
            let count = Int(r.glyphCount)
            let runFont: CTEngineFont = r.font == f.handle ? f : CTDirectWriteFont(handle: cdw_font_retain(r.font))
            var run = CTShapedRun(font: runFont, glyphs: [], advances: [], offsets: [], clusters: [],
                                  range: NSRange(location: Int(r.textStart), length: Int(r.textLength)), isRightToLeft: r.rightToLeft)
            for g in 0..<count {
                run.glyphs.append(r.glyphs[g])
                run.advances.append(CGFloat(r.advances[g]))
                run.offsets.append(CGPoint(x: CGFloat(r.offsets[g * 2]), y: CGFloat(r.offsets[g * 2 + 1])))
                run.clusters.append(Int(r.textStart) + Int(r.clusters[g]))
            }
            runs.append(run)
        }
        return runs
    }
}
#endif
