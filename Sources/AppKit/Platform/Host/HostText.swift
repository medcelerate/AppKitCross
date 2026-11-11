// CoreText-backed text for the macOS host build.

import Foundation
#if canImport(CoreText) && canImport(CoreGraphics)
import CoreText
import CoreGraphics

final class HostFont: PlatformFontHandle {
    let ct: CTFont
    init(_ ct: CTFont) { self.ct = ct }
    var pointSize: CGFloat { CTFontGetSize(ct) }
    var ascent: CGFloat { CTFontGetAscent(ct) }
    var descent: CGFloat { CTFontGetDescent(ct) }
    var leading: CGFloat { CTFontGetLeading(ct) }
    var capHeight: CGFloat { CTFontGetCapHeight(ct) }
    var xHeight: CGFloat { CTFontGetXHeight(ct) }
    var familyName: String { CTFontCopyFamilyName(ct) as String }
    var postScriptName: String { CTFontCopyPostScriptName(ct) as String }
    var isFixedPitch: Bool { CTFontGetSymbolicTraits(ct).contains(.traitMonoSpace) }
    var styleName: String? { CTFontCopyName(ct, kCTFontStyleNameKey) as String? }
}

@MainActor
final class HostTextBackend: PlatformTextBackend {
    func makeFont(family: String?, size: CGFloat, weight: CGFloat, italic: Bool, monospaced: Bool) -> PlatformFontHandle? {
        var font: CTFont
        if let family {
            font = CTFontCreateWithName(family as CFString, size, nil)
            // CTFontCreateWithName falls back silently; detect a miss by comparing names.
            let got = (CTFontCopyFamilyName(font) as String).lowercased()
            let ps = (CTFontCopyPostScriptName(font) as String).lowercased()
            if got != family.lowercased() && ps != family.lowercased() { return nil }
        } else {
            font = CTFontCreateUIFontForLanguage(monospaced ? .userFixedPitch : .system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        if weight != 0 || italic {
            let attrs: [CFString: Any] = [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight, kCTFontSlantTrait: italic ? 0.2 : 0] as CFDictionary]
            let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
            let derived = CTFontCreateCopyWithAttributes(font, size, nil, desc)
            font = derived
        }
        return HostFont(font)
    }

    private func lines(_ text: String, font: HostFont, color: CGColor?, maxWidth: CGFloat?) -> [CTLine] {
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font.ct]
        if let color { attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        var result: [CTLine] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let attributed = NSAttributedString(string: String(paragraph), attributes: attrs)
            if let maxWidth, maxWidth > 0 {
                let setter = CTTypesetterCreateWithAttributedString(attributed)
                var start = 0
                let length = attributed.length
                if length == 0 { result.append(CTLineCreateWithAttributedString(attributed)) }
                while start < length {
                    let count = CTTypesetterSuggestLineBreak(setter, start, Double(maxWidth))
                    result.append(CTTypesetterCreateLine(setter, CFRangeMake(start, count)))
                    start += max(count, 1)
                }
            } else {
                result.append(CTLineCreateWithAttributedString(attributed))
            }
        }
        return result
    }

    func measure(_ text: String, font: PlatformFontHandle, maxWidth: CGFloat?) -> CGSize {
        guard let f = font as? HostFont else { return .zero }
        let ls = lines(text, font: f, color: nil, maxWidth: maxWidth)
        let lineHeight = f.ascent + f.descent + f.leading
        var width: CGFloat = 0
        for l in ls { width = max(width, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))) }
        return CGSize(width: width.rounded(.up), height: (lineHeight * CGFloat(ls.count)).rounded(.up))
    }

    func draw(_ text: String, font: PlatformFontHandle, color: CGColor, topLeft: CGPoint, maxWidth: CGFloat?, flipped: Bool, in context: CGContext) {
        guard let f = font as? HostFont else { return }
        let ls = lines(text, font: f, color: color, maxWidth: maxWidth)
        let lineHeight = f.ascent + f.descent + f.leading
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: topLeft.x, y: topLeft.y)
        if flipped { context.scaleBy(x: 1, y: -1) }      // CoreText wants y up
        for (i, l) in ls.enumerated() {
            context.textPosition = CGPoint(x: 0, y: -(f.ascent + CGFloat(i) * lineHeight))
            CTLineDraw(l, context)
        }
        context.restoreGState()
    }
}
#endif
