// Linux font engine: Pango for itemisation, shaping and fallback; HarfBuzz for glyph
// metrics, outlines and tables; Cairo for drawing on the context behind CGContext.

#if os(Linux)
import Foundation
import CoreGraphics
import CCairo

final class CTPangoFont: CTEngineFont {
    let font: UnsafeMutablePointer<PangoFont>
    let description: OpaquePointer        // PangoFontDescription*, owned
    let hb: OpaquePointer                 // hb_font_t*, owned by the PangoFont
    let size: CGFloat
    private let engine: CTPangoEngine
    private(set) var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    private(set) var underlinePosition: CGFloat = 0, underlineThickness: CGFloat = 1
    private(set) var capHeight: CGFloat = 0, xHeight: CGFloat = 0
    let unitsPerEm: UInt32
    let familyName: String, styleName: String, fullName: String, postScriptName: String
    let isBold: Bool, isItalic: Bool, isMonospace: Bool
    let weight: CGFloat, slant: CGFloat
    /// Scaled font units per point (HarfBuzz positions divided by this are points).
    private let unitScale: CGFloat

    init?(description: OpaquePointer, size: CGFloat, engine: CTPangoEngine) {
        guard let font = pango_context_load_font(engine.context, description),
              let hb = pango_font_get_hb_font(font) else { return nil }
        self.font = font
        self.description = pango_font_description_copy(description)!
        self.hb = hb
        self.size = size
        self.engine = engine
        var sx: Int32 = 0, sy: Int32 = 0
        hb_font_get_scale(hb, &sx, &sy)
        unitScale = sy > 0 ? CGFloat(sy) / size : CGFloat(PANGO_SCALE)
        let face = hb_font_get_face(hb)
        unitsPerEm = hb_face_get_upem(face)
        if let metrics = pango_font_get_metrics(font, nil) {
            ascent = CGFloat(pango_font_metrics_get_ascent(metrics)) / CGFloat(PANGO_SCALE)
            descent = CGFloat(pango_font_metrics_get_descent(metrics)) / CGFloat(PANGO_SCALE)
            let height = CGFloat(pango_font_metrics_get_height(metrics)) / CGFloat(PANGO_SCALE)
            leading = max(0, height - ascent - descent)
            underlinePosition = CGFloat(pango_font_metrics_get_underline_position(metrics)) / CGFloat(PANGO_SCALE)
            underlineThickness = max(0.5, CGFloat(pango_font_metrics_get_underline_thickness(metrics)) / CGFloat(PANGO_SCALE))
            pango_font_metrics_unref(metrics)
        }
        var pos: hb_position_t = 0
        if hb_ot_metrics_get_position(hb, HB_OT_METRICS_TAG_CAP_HEIGHT, &pos) != 0, pos > 0 { capHeight = CGFloat(pos) / unitScale } else { capHeight = ascent * 0.7 }
        if hb_ot_metrics_get_position(hb, HB_OT_METRICS_TAG_X_HEIGHT, &pos) != 0, pos > 0 { xHeight = CGFloat(pos) / unitScale } else { xHeight = ascent * 0.5 }
        func name(_ id: hb_ot_name_id_t) -> String {
            var len: UInt32 = 0
            _ = hb_ot_name_get_utf8(face, id, nil, &len, nil)
            guard len > 0 else { return "" }
            var buf = [CChar](repeating: 0, count: Int(len) + 1)
            var cap = UInt32(buf.count)
            _ = hb_ot_name_get_utf8(face, id, nil, &cap, &buf)
            return String(cString: buf)
        }
        let described = pango_font_describe(font)
        let family = described.flatMap { pango_font_description_get_family($0) }.map { String(cString: $0) } ?? name(hb_ot_name_id_t(1))
        familyName = family
        let sub = name(hb_ot_name_id_t(2))
        styleName = sub.isEmpty ? "Regular" : sub
        let full = name(hb_ot_name_id_t(4))
        fullName = full.isEmpty ? family : full
        let ps = name(hb_ot_name_id_t(6))
        postScriptName = ps.isEmpty ? (family + "-" + styleName).replacingOccurrences(of: " ", with: "") : ps
        let w = described.map { Int(pango_font_description_get_weight($0).rawValue) } ?? 400
        weight = CGFloat(w - 400) / 750
        isBold = w >= 600
        let style = described.map { pango_font_description_get_style($0) } ?? PANGO_STYLE_NORMAL
        isItalic = style != PANGO_STYLE_NORMAL
        slant = isItalic ? -0.2 : 0
        if let described { pango_font_description_free(described) }
        if let pface = pango_font_get_face(font), let fam = pango_font_face_get_family(pface) {
            isMonospace = pango_font_family_is_monospace(fam) != 0
        } else {
            isMonospace = false
        }
    }

    deinit {
        pango_font_description_free(description)
        g_object_unref(UnsafeMutableRawPointer(font))
    }

    var glyphCount: Int { Int(hb_face_get_glyph_count(hb_font_get_face(hb))) }

    var boundingBox: CGRect {
        var extents = hb_font_extents_t()
        _ = hb_font_get_h_extents(hb, &extents)
        return CGRect(x: 0, y: -descent, width: size, height: ascent + descent)
    }

    func glyphs(for units: [UInt16]) -> [CGGlyph] {
        var out = [CGGlyph](repeating: 0, count: units.count)
        var i = 0
        while i < units.count {
            var scalar = UInt32(units[i])
            var width = 1
            if (0xD800...0xDBFF).contains(units[i]), i + 1 < units.count, (0xDC00...0xDFFF).contains(units[i + 1]) {
                scalar = 0x10000 + ((UInt32(units[i]) - 0xD800) << 10) + (UInt32(units[i + 1]) - 0xDC00)
                width = 2
            }
            var g: hb_codepoint_t = 0
            if hb_font_get_nominal_glyph(hb, scalar, &g) != 0, g <= UInt32(UInt16.max) { out[i] = CGGlyph(g) }
            i += width
        }
        return out
    }

    func advances(for glyphs: [CGGlyph]) -> [CGSize] {
        glyphs.map { CGSize(width: CGFloat(hb_font_get_glyph_h_advance(hb, hb_codepoint_t($0))) / unitScale, height: 0) }
    }

    func boundingRects(for glyphs: [CGGlyph]) -> [CGRect] {
        glyphs.map { g in
            var e = hb_glyph_extents_t()
            guard hb_font_get_glyph_extents(hb, hb_codepoint_t(g), &e) != 0 else { return .zero }
            return CGRect(x: CGFloat(e.x_bearing) / unitScale, y: CGFloat(e.y_bearing + e.height) / unitScale,
                          width: CGFloat(e.width) / unitScale, height: CGFloat(-e.height) / unitScale)
        }
    }

    private final class PathBuilder {
        let path = CGMutablePath()
        let scale: CGFloat
        init(scale: CGFloat) { self.scale = scale }
        func p(_ x: Float, _ y: Float) -> CGPoint { CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale) }
    }

    func path(for glyph: CGGlyph) -> CGPath? {
        let builder = PathBuilder(scale: unitScale)
        guard let funcs = hb_draw_funcs_create() else { return nil }
        defer { hb_draw_funcs_destroy(funcs) }
        hb_draw_funcs_set_move_to_func(funcs, { _, data, _, x, y, _ in
            let b = Unmanaged<PathBuilder>.fromOpaque(data!).takeUnretainedValue(); b.path.move(to: b.p(x, y))
        }, nil, nil)
        hb_draw_funcs_set_line_to_func(funcs, { _, data, _, x, y, _ in
            let b = Unmanaged<PathBuilder>.fromOpaque(data!).takeUnretainedValue(); b.path.addLine(to: b.p(x, y))
        }, nil, nil)
        hb_draw_funcs_set_quadratic_to_func(funcs, { _, data, _, cx, cy, x, y, _ in
            let b = Unmanaged<PathBuilder>.fromOpaque(data!).takeUnretainedValue(); b.path.addQuadCurve(to: b.p(x, y), control: b.p(cx, cy))
        }, nil, nil)
        hb_draw_funcs_set_cubic_to_func(funcs, { _, data, _, c1x, c1y, c2x, c2y, x, y, _ in
            let b = Unmanaged<PathBuilder>.fromOpaque(data!).takeUnretainedValue(); b.path.addCurve(to: b.p(x, y), control1: b.p(c1x, c1y), control2: b.p(c2x, c2y))
        }, nil, nil)
        hb_draw_funcs_set_close_path_func(funcs, { _, data, _, _ in
            let b = Unmanaged<PathBuilder>.fromOpaque(data!).takeUnretainedValue(); b.path.closeSubpath()
        }, nil, nil)
        hb_font_draw_glyph(hb, hb_codepoint_t(glyph), funcs, Unmanaged.passUnretained(builder).toOpaque())
        return builder.path.isEmpty ? nil : builder.path
    }

    func hasTable(_ tag: UInt32) -> Bool { table(tag) != nil }

    func table(_ tag: UInt32) -> Data? {
        guard let blob = hb_face_reference_table(hb_font_get_face(hb), hb_tag_t(tag)) else { return nil }
        defer { hb_blob_destroy(blob) }
        var len: UInt32 = 0
        guard let bytes = hb_blob_get_data(blob, &len), len > 0 else { return nil }
        return Data(bytes: bytes, count: Int(len))
    }

    func availableTables() -> [UInt32] {
        let face = hb_font_get_face(hb)
        var count: UInt32 = hb_face_get_table_tags(face, 0, nil, nil)
        guard count > 0 else { return [] }
        var tags = [hb_tag_t](repeating: 0, count: Int(count))
        _ = hb_face_get_table_tags(face, 0, &count, &tags)
        return tags.map { UInt32($0) }
    }

    func glyph(named name: String) -> CGGlyph {
        var g: hb_codepoint_t = 0
        guard hb_font_get_glyph_from_name(hb, name, -1, &g) != 0, g <= UInt32(UInt16.max) else { return 0 }
        return CGGlyph(g)
    }

    func draw(glyphs: [CGGlyph], positions: [CGPoint], color: CGColor, in ctx: CGContext) {
        guard !glyphs.isEmpty, let scaled = pango_cairo_font_get_scaled_font(OpaquePointer(font)) else { return }
        let cr = ctx.cairo
        cairo_save(cr)
        let c = color.components
        if c.count >= 4 { cairo_set_source_rgba(cr, Double(c[0]), Double(c[1]), Double(c[2]), Double(c[3])) }
        else if c.count >= 2 { cairo_set_source_rgba(cr, Double(c[0]), Double(c[0]), Double(c[0]), Double(c[1])) }
        cairo_set_scaled_font(cr, scaled)
        // User space is y-up; glyph outlines are y-down, so mirror about the first baseline.
        let origin = positions[0]
        cairo_translate(cr, Double(origin.x), Double(origin.y))
        cairo_scale(cr, 1, -1)
        var cg = [cairo_glyph_t](repeating: cairo_glyph_t(), count: glyphs.count)
        for i in glyphs.indices {
            cg[i].index = UInt(glyphs[i])
            cg[i].x = Double(positions[i].x - origin.x)
            cg[i].y = Double(-(positions[i].y - origin.y))
        }
        cairo_show_glyphs(cr, &cg, Int32(cg.count))
        cairo_restore(cr)
    }

    func withSize(_ size: CGFloat) -> CTEngineFont {
        let d = pango_font_description_copy(description)!
        pango_font_description_set_absolute_size(d, Double(size) * Double(PANGO_SCALE))
        defer { pango_font_description_free(d) }
        return CTPangoFont(description: d, size: size, engine: engine) ?? self
    }
}

final class CTPangoEngine: CTEngine {
    let fontMap: UnsafeMutablePointer<PangoFontMap>
    let context: OpaquePointer                       // PangoContext*

    init() {
        fontMap = pango_cairo_font_map_get_default()!
        context = pango_font_map_create_context(fontMap)!
    }

    /// Installed families by lower-cased name, and by name with spaces removed (PostScript style).
    lazy var families: [String: String] = {
        var out: [String: String] = [:]
        var list: UnsafeMutablePointer<UnsafeMutablePointer<PangoFontFamily>?>? = nil
        var count: Int32 = 0
        pango_font_map_list_families(fontMap, &list, &count)
        if let list {
            for i in 0..<Int(count) {
                if let fam = list[i], let cname = pango_font_family_get_name(fam) {
                    let name = String(cString: cname)
                    out[name.lowercased()] = name
                    out[name.replacingOccurrences(of: " ", with: "").lowercased()] = name
                }
            }
            g_free(list)
        }
        return out
    }()

    var familyNames: [String] { Array(Set(families.values)).sorted() }

    /// The family's faces from Pango (regular first, then by weight, italics after uprights).
    func faces(inFamily family: String, size: CGFloat) -> [CTEngineFont] {
        guard let name = families[family.lowercased()] ?? families[family.replacingOccurrences(of: " ", with: "").lowercased()] else { return [] }
        var list: UnsafeMutablePointer<UnsafeMutablePointer<PangoFontFamily>?>? = nil
        var count: Int32 = 0
        pango_font_map_list_families(fontMap, &list, &count)
        defer { if let list { g_free(list) } }
        guard let list, let fam = (0..<Int(count)).lazy.compactMap({ list[$0] }).first(where: { pango_font_family_get_name($0).map { String(cString: $0) } == name }) else { return [] }
        var faces: UnsafeMutablePointer<UnsafeMutablePointer<PangoFontFace>?>? = nil
        var faceCount: Int32 = 0
        pango_font_family_list_faces(fam, &faces, &faceCount)
        defer { if let faces { g_free(faces) } }
        var out: [CTEngineFont] = []
        for i in 0..<Int(faceCount) {
            guard let faces, let face = faces[i], let desc = pango_font_face_describe(face) else { continue }
            pango_font_description_set_absolute_size(desc, Double(size) * Double(PANGO_SCALE))
            if let f = CTPangoFont(description: desc, size: size, engine: self), !out.contains(where: { $0.postScriptName == f.postScriptName }) { out.append(f) }
            pango_font_description_free(desc)
        }
        return out.sorted { a, b in
            if a.isItalic != b.isItalic { return !a.isItalic }
            if a.weight != b.weight { return abs(a.weight) < abs(b.weight) || (abs(a.weight) == abs(b.weight) && a.weight < b.weight) }
            return a.postScriptName < b.postScriptName
        }
    }

    private static let styleWords: [(String, (weight: Int?, italic: Bool?))] = [
        ("bolditalic", (700, true)), ("boldoblique", (700, true)), ("bold", (700, nil)), ("semibold", (600, nil)), ("demibold", (600, nil)),
        ("extrabold", (800, nil)), ("black", (900, nil)), ("heavy", (900, nil)), ("medium", (500, nil)), ("light", (300, nil)),
        ("extralight", (200, nil)), ("thin", (100, nil)), ("italic", (nil, true)), ("oblique", (nil, true)), ("regular", (400, nil)), ("roman", (400, nil)),
    ]

    func makeFont(name: String?, size: CGFloat, weight: CGFloat?, italic: Bool?, uiType: CTFontUIFontType) -> CTEngineFont? {
        var family: String
        var styleWeight: Int? = nil
        var styleItalic: Bool? = nil
        if let name {
            // "DejaVu Sans", "DejaVuSans-Bold", "DejaVu Sans Bold": family plus optional style words.
            let parts = name.split(separator: "-", maxSplits: 1).map(String.init)
            let key = parts[0].lowercased()
            if let fam = families[key] ?? families[key.replacingOccurrences(of: " ", with: "")] {
                family = fam
            } else {
                // Try stripping trailing style words from a spaced name.
                var words = parts[0].split(separator: " ").map(String.init)
                var found: String? = nil
                while words.count > 1, found == nil {
                    let style = words.removeLast().lowercased()
                    if let s = CTPangoEngine.styleWords.first(where: { $0.0 == style }) { styleWeight = s.1.weight ?? styleWeight; styleItalic = s.1.italic ?? styleItalic }
                    found = families[words.joined(separator: " ").lowercased()]
                }
                guard let f = found else { return nil }
                family = f
            }
            if parts.count > 1 {
                let style = parts[1].lowercased().replacingOccurrences(of: " ", with: "")
                for (word, v) in CTPangoEngine.styleWords where style.contains(word) {
                    if let w = v.weight { styleWeight = styleWeight ?? w }
                    if let i = v.italic { styleItalic = i }
                    if word.count >= style.count { break }
                }
            }
        } else {
            switch uiType {
            case .userFixedPitch: family = "Monospace"
            default: family = "Sans"
            }
        }
        guard let desc = pango_font_description_new() else { return nil }
        defer { pango_font_description_free(desc) }
        pango_font_description_set_family(desc, family)
        pango_font_description_set_absolute_size(desc, Double(size) * Double(PANGO_SCALE))
        let pangoWeight: Int32
        if let weight { pangoWeight = Int32(min(900, max(100, (400 + weight * 750).rounded()))) } else { pangoWeight = Int32(styleWeight ?? 400) }
        pango_font_description_set_weight(desc, PangoWeight(rawValue: UInt32(pangoWeight)))
        pango_font_description_set_style(desc, (italic ?? styleItalic ?? false) ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL)
        return CTPangoFont(description: desc, size: size, engine: self)
    }

    func shape(_ units: [UInt16], font: CTEngineFont, language: String?) -> [CTShapedRun] {
        guard let pf = font as? CTPangoFont, !units.isEmpty else { return [] }
        // UTF-16 → UTF-8 with a byte-offset → unit-index map.
        let string = String(decoding: units, as: UTF16.self)
        var byteToUnit: [Int] = []
        var unitIndex = 0
        for scalar in string.unicodeScalars {
            let u8 = String(scalar).utf8.count
            for _ in 0..<u8 { byteToUnit.append(unitIndex) }
            unitIndex += scalar.utf16.count
        }
        byteToUnit.append(unitIndex)
        let utf8 = Array(string.utf8)
        let byteCount = utf8.count
        guard let attrs = pango_attr_list_new() else { return [] }
        defer { pango_attr_list_unref(attrs) }
        pango_attr_list_insert(attrs, pango_attr_font_desc_new(pf.description))
        if let language, let lang = pango_language_from_string(language) { pango_context_set_language(context, lang) }
        var runs: [CTShapedRun] = []
        utf8.withUnsafeBufferPointer { buf in
            let base = UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: CChar.self)
            guard let items = pango_itemize(context, base, 0, Int32(byteCount), attrs, nil) else { return }
            var node: UnsafeMutablePointer<GList>? = items
            while let n = node {
                if let item = n.pointee.data?.assumingMemoryBound(to: PangoItem.self) {
                    let offset = Int(item.pointee.offset), length = Int(item.pointee.length)
                    if let glyphs = pango_glyph_string_new() {
                        pango_shape_full(base + offset, Int32(length), base, Int32(byteCount), &item.pointee.analysis, glyphs)
                        let count = Int(glyphs.pointee.num_glyphs)
                        var run = CTShapedRun(font: pf, glyphs: [], advances: [], offsets: [], clusters: [],
                                              range: NSRange(location: byteToUnit[offset], length: byteToUnit[offset + length] - byteToUnit[offset]),
                                              isRightToLeft: item.pointee.analysis.level & 1 == 1)
                        if let itemFont = item.pointee.analysis.font, itemFont != pf.font {
                            // Fallback: wrap the resolved font.
                            if let described = pango_font_describe(itemFont) {
                                pango_font_description_set_absolute_size(described, Double(pf.size) * Double(PANGO_SCALE))
                                if let fb = CTPangoFont(description: described, size: pf.size, engine: self) { run.font = fb }
                                pango_font_description_free(described)
                            }
                        }
                        for g in 0..<count {
                            let info = glyphs.pointee.glyphs[g]
                            let raw = info.glyph
                            let glyph: CGGlyph = (raw & 0xF000_0000) != 0 || raw > UInt32(UInt16.max) ? 0 : CGGlyph(raw)
                            run.glyphs.append(glyph)
                            run.advances.append(CGFloat(info.geometry.width) / CGFloat(PANGO_SCALE))
                            run.offsets.append(CGPoint(x: CGFloat(info.geometry.x_offset) / CGFloat(PANGO_SCALE), y: -CGFloat(info.geometry.y_offset) / CGFloat(PANGO_SCALE)))
                            run.clusters.append(byteToUnit[offset + Int(glyphs.pointee.log_clusters[g])])
                        }
                        runs.append(run)
                        pango_glyph_string_free(glyphs)
                    }
                    pango_item_free(item)
                }
                node = n.pointee.next
            }
            g_list_free(items)
        }
        return runs
    }
}
#endif
