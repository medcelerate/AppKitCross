// The typesetting both text engines share (ADR-0040): AppKit attributes expressed for
// CoreText, and the line breaker that turns a paragraph into lines. TextKit 1's
// NSLayoutManager and TextKit 2's NSTextLayoutFragment both call these, so the two engines
// break, measure and place lines identically.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif

/// One attachment as laid out: the attachment, its size and the offset of its bottom edge
/// from the baseline (positive upwards).
internal typealias _NSLaidOutAttachment = (attachment: NSTextAttachment, size: CGSize, baselineOffset: CGFloat)

/// AppKit attributes (NSFont, NSColor, paragraph styles, attachments) as CoreText attributes.
internal enum _NSCoreTextConversion {
    struct Result {
        /// The CoreText attributed string for the converted range (indices start at 0).
        var string: NSAttributedString
        /// Attachments by index into `string`.
        var attachments: [Int: _NSLaidOutAttachment]
    }

    /// Converts `range` of `source`. `temporary` runs (in `source` indices) override the
    /// stored attributes, as TextKit 1's temporary and TextKit 2's rendering attributes do;
    /// `documentOffset` is the document index of `range.location` (attachments are asked for
    /// their metrics at document indices, and `attachmentSizeOverrides` is keyed by them).
    static func convert(_ source: NSAttributedString, range: NSRange, documentOffset: Int,
                        appearance: NSAppearance?, linkAttributes: [NSAttributedString.Key: Any]?,
                        temporary: [(range: NSRange, attrs: [NSAttributedString.Key: Any])],
                        container: NSTextContainer?, attachmentSizeOverrides: [Int: CGSize] = [:]) -> Result {
        let text = (source.string as NSString).substring(with: range)
        let out = NSMutableAttributedString(string: text)
        let n = range.length
        guard n > 0 else { return Result(string: out, attachments: [:]) }
        // Tab stops reach CoreText through a CTParagraphStyle (alignment, indents and spacing
        // are applied by the line typesetter, line by line).
        var ctStyles: [ObjectIdentifier: CTParagraphStyle] = [:]
        func ctStyle(_ ps: NSParagraphStyle) -> CTParagraphStyle? {
            guard !ps.tabStops.isEmpty || ps.defaultTabInterval > 0 else { return nil }
            if let cached = ctStyles[ObjectIdentifier(ps)] { return cached }
            let made = _ctParagraphStyle(tabStops: ps.tabStops, defaultTabInterval: ps.defaultTabInterval)
            ctStyles[ObjectIdentifier(ps)] = made
            return made
        }
        // `into` is in `source` indices.
        func convert(_ attrs: [NSAttributedString.Key: Any], into sourceRange: NSRange) {
            var ct: [NSAttributedString.Key: Any] = [:]
            MainActor.assumeIsolated {
                let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                ct[NSAttributedString.Key(kCTFontAttributeName as String)] = font._coreTextFont
                let color = (attrs[.foregroundColor] as? NSColor) ?? NSColor.textColor
                let underlineColor = attrs[.underlineColor] as? NSColor
                var cg = color.cgColor, ucg = underlineColor?.cgColor
                appearance?.performAsCurrentDrawingAppearance { cg = color.cgColor; ucg = underlineColor?.cgColor }
                ct[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = cg
                if let u = attrs[.underlineStyle] as? NSNumber, u.intValue != 0 { ct[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = u }
                if let ucg { ct[NSAttributedString.Key(kCTUnderlineColorAttributeName as String)] = ucg }
                // Outline (positive) and fill-and-stroke (negative) glyphs, as a percentage of the size.
                if let w = attrs[.strokeWidth] as? NSNumber, w.doubleValue != 0 {
                    ct[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = w
                    if let sc = attrs[.strokeColor] as? NSColor {
                        var scg = sc.cgColor
                        appearance?.performAsCurrentDrawingAppearance { scg = sc.cgColor }
                        ct[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = scg
                    }
                }
            }
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle, let cts = ctStyle(ps) { ct[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = cts }
            if let k = attrs[.kern] as? NSNumber { ct[NSAttributedString.Key(kCTKernAttributeName as String)] = k }
            if let b = attrs[.baselineOffset] as? NSNumber { ct[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] = b }
            out.addAttributes(ct, range: NSRange(location: sourceRange.location - range.location, length: sourceRange.length))
        }
        // Links draw with the text view's link attributes (blue and underlined by default).
        source.enumerateAttributes(in: range, options: []) { stored, run, _ in
            var attrs = stored
            if stored[.link] != nil, let la = linkAttributes { for (k, v) in la { attrs[k] = v } }
            var merged = attrs
            for t in temporary where t.range.location < run.location + run.length && t.range.location + t.range.length > run.location {
                // Split the run where temporary attributes apply.
                let lo = max(run.location, t.range.location), hi = min(run.location + run.length, t.range.location + t.range.length)
                for (k, v) in t.attrs { merged[k] = v }
                convert(merged, into: NSRange(location: lo, length: hi - lo))
                merged = attrs
            }
            convert(attrs, into: run)
            for t in temporary where t.range.location < run.location + run.length && t.range.location + t.range.length > run.location {
                let lo = max(run.location, t.range.location), hi = min(run.location + run.length, t.range.location + t.range.length)
                var m = attrs
                for (k, v) in t.attrs { m[k] = v }
                convert(m, into: NSRange(location: lo, length: hi - lo))
            }
        }
        // Attachments: their characters advance by the attachment's width and raise the
        // line to its height (a run delegate); the attachment draws after the glyphs.
        var attachments: [Int: _NSLaidOutAttachment] = [:]
        let units = source.string as NSString
        source.enumerateAttribute(.attachment, in: range, options: []) { value, run, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            for i in run.location..<(run.location + run.length) where units.character(at: i) == 0xFFFC {
                let local = i - range.location
                var m = attachment._layoutMetrics(in: container, characterIndex: documentOffset + local)
                if let override = attachmentSizeOverrides[documentOffset + local] { m.size = override }
                attachments[local] = (attachment, m.size, m.baselineOffset)
                if let delegate = _runDelegate(width: m.size.width, ascent: max(0, m.size.height + m.baselineOffset), descent: max(0, -m.baselineOffset)) {
                    out.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: delegate, range: NSRange(location: local, length: 1))
                }
                out.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: _clearColor, range: NSRange(location: local, length: 1))
            }
        }
        return Result(string: out, attachments: attachments)
    }

    static let _clearColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// Metrics a run delegate reports, retained by the delegate.
    private final class _DelegateMetrics {
        let width: CGFloat, ascent: CGFloat, descent: CGFloat
        init(width: CGFloat, ascent: CGFloat, descent: CGFloat) { self.width = width; self.ascent = ascent; self.descent = descent }
    }

    static func _runDelegate(width: CGFloat, ascent: CGFloat, descent: CGFloat) -> CTRunDelegate? {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).release() },
            getAscent: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).takeUnretainedValue().ascent },
            getDescent: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).takeUnretainedValue().descent },
            getWidth: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).takeUnretainedValue().width })
        let box = Unmanaged.passRetained(_DelegateMetrics(width: width, ascent: ascent, descent: descent)).toOpaque()
        guard let d = CTRunDelegateCreate(&callbacks, box) else { Unmanaged<_DelegateMetrics>.fromOpaque(box).release(); return nil }
        return d
    }

    /// A CoreText paragraph style carrying only tab stops.
    static func _ctParagraphStyle(tabStops: [NSTextTab], defaultTabInterval: CGFloat) -> CTParagraphStyle {
        let tabs: [CTTextTab] = tabStops.map { t in
            let a: CTTextAlignment
            switch t.alignment {
            case .right: a = .right
            case .center: a = .center
            default: a = .left
            }
            return CTTextTabCreate(a, Double(t.location), nil)
        }
        #if canImport(Darwin)
        var array: CFArray = tabs as CFArray
        #else
        var array: CFArray = NSArray(array: tabs)
        #endif
        var interval = defaultTabInterval
        return withUnsafeBytes(of: &array) { tp in
            withUnsafeBytes(of: &interval) { ip in
                var settings = [CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: tp.baseAddress!)]
                if defaultTabInterval > 0 { settings.append(CTParagraphStyleSetting(spec: .defaultTabInterval, valueSize: MemoryLayout<CGFloat>.size, value: ip.baseAddress!)) }
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }
}

/// One line as the line typesetter breaks and measures it.
internal struct _NSTypesetLine {
    /// Characters in the line, including a trailing line break.
    var count: Int
    /// 0, 1 or 2 (CR LF).
    var newlineLength: Int
    var line: CTLine
    /// Truncated for the truncating break modes, else `line`.
    var drawnLine: CTLine
    /// Distance from the top of the line to its baseline.
    var ascent: CGFloat
    var height: CGFloat
    /// x of the CoreText line origin, in the column's coordinate space.
    var textX: CGFloat
    /// The typographic width without trailing whitespace.
    var usedWidth: CGFloat
}

/// Breaks text into lines and places each one horizontally, the way TextKit 1 does.
internal enum _NSLineTypesetter {
    /// The length of the line break at `i` (0 when there is none): LF, CR, CR LF, U+2028,
    /// U+2029 and form feed end a line and a paragraph.
    static func newlineLength(at i: Int, in units: [UInt16]) -> Int {
        guard i >= 0, i < units.count else { return 0 }
        let u = units[i]
        if u == 0x0D { return (i + 1 < units.count && units[i + 1] == 0x0A) ? 2 : 1 }
        return (u == 0x0A || u == 0x2028 || u == 0x2029 || u == 0x0C) ? 1 : 0
    }

    /// The end of the paragraph starting at `index` (after its line break).
    static func paragraphEnd(from index: Int, units: [UInt16]) -> Int {
        var i = index
        while i < units.count {
            let nl = newlineLength(at: i, in: units)
            if nl > 0 { return i + nl }
            i += 1
        }
        return units.count
    }

    /// Breaks the line starting at `index` (before `end`, the paragraph's or range's end) of
    /// the text `ts` typesets and measures and places it in a column `columnWidth` wide at
    /// `columnMinX`. `style` is the paragraph style at `index`.
    static func line(typesetter ts: CTTypesetter, units: [UInt16], index: Int, end: Int,
                     style: NSParagraphStyle?, paragraphStart: Bool,
                     columnMinX: CGFloat, columnWidth: CGFloat,
                     container: NSTextContainer, usesFontLeading: Bool) -> _NSTypesetLine {
        let padding = container.lineFragmentPadding
        let head = paragraphStart ? (style?.firstLineHeadIndent ?? 0) : (style?.headIndent ?? 0)
        let tail = style?.tailIndent ?? 0
        let width = max(1, (tail > 0 ? tail : columnWidth + tail) - head - 2 * padding)
        let mode = container.lineBreakMode == .byWordWrapping ? (style?.lineBreakMode ?? .byWordWrapping) : container.lineBreakMode
        var count: Int
        switch mode {
        case .byClipping, .byTruncatingHead, .byTruncatingTail, .byTruncatingMiddle:
            count = 0
            while index + count < end {
                let nl = newlineLength(at: index + count, in: units)
                if nl > 0 { count += nl; break }
                count += 1
            }
        case .byCharWrapping:
            count = CTTypesetterSuggestClusterBreakWithOffset(ts, index, Double(width + head), Double(head))
        default:
            count = CTTypesetterSuggestLineBreakWithOffset(ts, index, Double(width + head), Double(head))
        }
        count = max(1, min(count, end - index))
        let line = CTTypesetterCreateLineWithOffset(ts, CFRangeMake(index, count), Double(head))
        var drawn = line
        switch mode {
        case .byTruncatingHead: drawn = CTLineCreateTruncatedLine(line, Double(width), .start, nil) ?? line
        case .byTruncatingTail: drawn = CTLineCreateTruncatedLine(line, Double(width), .end, nil) ?? line
        case .byTruncatingMiddle: drawn = CTLineCreateTruncatedLine(line, Double(width), .middle, nil) ?? line
        default: break
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        if !usesFontLeading { leading = 0 }
        if let s = style {
            if s.lineHeightMultiple > 0 { ascent *= s.lineHeightMultiple; descent *= s.lineHeightMultiple }
            let h = ascent + descent + leading
            if s.maximumLineHeight > 0, h > s.maximumLineHeight { ascent -= h - s.maximumLineHeight }
            if s.minimumLineHeight > 0, h < s.minimumLineHeight { ascent += s.minimumLineHeight - h }
        }
        let height = (ascent + descent + leading).rounded(.up)
        let flush: CGFloat
        switch style?.alignment ?? .natural {
        case .center: flush = 0.5
        case .right: flush = 1
        case .left: flush = 0
        default: flush = style?.baseWritingDirection == .rightToLeft ? 1 : 0   // natural follows the paragraph's direction
        }
        let trailing = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
        // An unbounded column (a field editor's, a horizontally resizable view's) flushes
        // against the view's visible width instead, when the container names one.
        let flushWidth = columnWidth >= CGFloat.greatestFiniteMagnitude / 2 ? (container._alignmentWidth.map { max(1, $0 - head - 2 * padding) } ?? width) : width
        let flushOffset = max(0, flushWidth - (lineWidth - trailing)) * flush
        let textX = columnMinX + padding + head + flushOffset
        let nl = newlineLength(at: index + count - 1, in: units) > 0 ? (count >= 2 && units[index + count - 2] == 0x0D && units[index + count - 1] == 0x0A ? 2 : 1) : 0
        return _NSTypesetLine(count: count, newlineLength: nl, line: line, drawnLine: drawn, ascent: ascent,
                              height: height, textX: textX, usedWidth: lineWidth - trailing)
    }

    /// The height of an empty line (the extra line fragment) in `font`.
    static func emptyLineHeight(_ font: NSFont) -> CGFloat {
        MainActor.assumeIsolated { (font.ascender - font.descender + font.leading).rounded(.up) }
    }
}
