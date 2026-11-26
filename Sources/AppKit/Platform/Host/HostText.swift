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

    /// Laid-out lines for drawing, by string, font, colour and wrap width. Building them
    /// (an attributed string, a typesetter, shaping) is most of what drawing a label costs on
    /// the port's Core Text, and a view drawing the same label every frame (a scroll frame
    /// paints a control under several dirty rectangles) laid it out every time (ADR-0054).
    /// `CTLine` is immutable, so a line is drawn as often as asked.
    private struct LinesKey: Hashable {
        let text: String
        let font: ObjectIdentifier
        let color: [CGFloat]
        let colorSpace: String
        let maxWidth: CGFloat?
    }
    /// The font is held with its lines so its identity cannot be reused by another font.
    private var drawnLines: [LinesKey: (font: HostFont, lines: [CTLine])] = [:]
    /// Entries kept before the cache starts over (a bound on memory, not a working set).
    static let drawnLinesLimit = 2048
    /// Lines laid out (cache misses) and strings drawn, for `APPKITWIN_TRACE_FRAMES` and tests.
    static var linesLaidOut = 0, stringsDrawn = 0
    static var drawMilliseconds = 0.0

    private func cachedLines(_ text: String, font f: HostFont, color: CGColor, maxWidth: CGFloat?) -> [CTLine] {
        // Optional on Apple's CGColor (a pattern colour has none), plain on the port's.
        let maybeComponents: [CGFloat]? = color.components
        guard let components = maybeComponents else { return lines(text, font: f, color: color, maxWidth: maxWidth) }
        let space = color.colorSpace.map { String(describing: $0.name) } ?? ""   // CFString? on Apple, String here
        let key = LinesKey(text: text, font: ObjectIdentifier(f), color: components, colorSpace: space, maxWidth: maxWidth)
        if let hit = drawnLines[key], hit.font === f { return hit.lines }
        let ls = lines(text, font: f, color: color, maxWidth: maxWidth)
        HostTextBackend.linesLaidOut &+= 1
        if drawnLines.count >= HostTextBackend.drawnLinesLimit { drawnLines.removeAll(keepingCapacity: true) }
        drawnLines[key] = (f, ls)
        return ls
    }

    func draw(_ text: String, font: PlatformFontHandle, color: CGColor, topLeft: CGPoint, maxWidth: CGFloat?, flipped: Bool, in context: CGContext) {
        guard let f = font as? HostFont else { return }
        let t0 = NSView._traceFrames ? NSView._traceClock() : 0
        defer {
            HostTextBackend.stringsDrawn &+= 1
            if NSView._traceFrames { HostTextBackend.drawMilliseconds += NSView._traceClock() - t0 }
        }
        let ls = cachedLines(text, font: f, color: color, maxWidth: maxWidth)
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
