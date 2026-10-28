// PangoCairo-backed text for Linux.

#if os(Linux)
import Foundation
import CoreGraphics
import CCairo

final class LinuxFont: PlatformFontHandle {
    let description: OpaquePointer       // PangoFontDescription*
    let pointSize: CGFloat
    let familyName: String
    let ascent: CGFloat, descent: CGFloat, leading: CGFloat, capHeight: CGFloat, xHeight: CGFloat
    let isFixedPitch: Bool
    var postScriptName: String { familyName }

    init?(family: String, size: CGFloat, weight: Int32, italic: Bool, fixedPitch: Bool, context: OpaquePointer) {
        guard let desc = pango_font_description_new() else { return nil }
        pango_font_description_set_family(desc, family)
        pango_font_description_set_absolute_size(desc, Double(size) * Double(PANGO_SCALE))
        pango_font_description_set_weight(desc, PangoWeight(rawValue: UInt32(weight)))
        pango_font_description_set_style(desc, italic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL)
        description = desc
        pointSize = size
        familyName = family
        isFixedPitch = fixedPitch
        var a = size * 0.8, d = size * 0.2, lg: CGFloat = 0
        if let metrics = pango_context_get_metrics(context, desc, nil) {
            a = CGFloat(pango_font_metrics_get_ascent(metrics)) / CGFloat(PANGO_SCALE)
            d = CGFloat(pango_font_metrics_get_descent(metrics)) / CGFloat(PANGO_SCALE)
            let h = CGFloat(pango_font_metrics_get_height(metrics)) / CGFloat(PANGO_SCALE)
            lg = max(0, h - a - d)
            pango_font_metrics_unref(metrics)
        }
        ascent = a; descent = d; leading = lg
        capHeight = a * 0.72
        xHeight = a * 0.52
    }

    deinit { pango_font_description_free(description) }
}

@MainActor
final class LinuxTextBackend: PlatformTextBackend {
    private let fontMap: UnsafeMutablePointer<PangoFontMap>?
    private let context: OpaquePointer?

    init() {
        fontMap = pango_cairo_font_map_get_default()
        context = fontMap.flatMap { pango_font_map_create_context($0) }
    }

    func makeFont(family: String?, size: CGFloat, weight: CGFloat, italic: Bool, monospaced: Bool) -> PlatformFontHandle? {
        guard let context else { return nil }
        // AppKit weight -1...1 -> Pango 100...900 (regular 400, bold 700).
        let pw = Int32(min(900, max(100, (400 + weight * 750).rounded())))
        let name = family ?? (monospaced ? "Monospace" : "Sans")
        return LinuxFont(family: name, size: size, weight: pw, italic: italic, fixedPitch: monospaced, context: context)
    }

    private func layout(_ text: String, font: LinuxFont, maxWidth: CGFloat?, on cr: OpaquePointer?) -> OpaquePointer? {
        let l: OpaquePointer?
        if let cr { l = pango_cairo_create_layout(cr) } else if let context { l = pango_layout_new(context) } else { return nil }
        guard let l else { return nil }
        pango_layout_set_font_description(l, font.description)
        pango_layout_set_text(l, text, -1)
        if let w = maxWidth {
            pango_layout_set_width(l, Int32(w * CGFloat(PANGO_SCALE)))
            pango_layout_set_wrap(l, PANGO_WRAP_WORD_CHAR)
        }
        return l
    }

    func measure(_ text: String, font: PlatformFontHandle, maxWidth: CGFloat?) -> CGSize {
        guard let f = font as? LinuxFont, let l = layout(text, font: f, maxWidth: maxWidth, on: nil) else { return .zero }
        defer { g_object_unref(UnsafeMutableRawPointer(l)) }
        var w: Int32 = 0, h: Int32 = 0
        pango_layout_get_pixel_size(l, &w, &h)
        return CGSize(width: CGFloat(w), height: CGFloat(h))
    }

    func draw(_ text: String, font: PlatformFontHandle, color: CGColor, topLeft: CGPoint, maxWidth: CGFloat?, flipped: Bool, in context: CGContext) {
        guard let f = font as? LinuxFont, let l = layout(text, font: f, maxWidth: maxWidth, on: context.cairo) else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(l)) }
        context.drawPangoLayout(l, topLeft: topLeft, flipped: flipped, color: color)
    }
}
#endif
