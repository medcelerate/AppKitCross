// CTTypesetter (CTTypesetter.h): shapes an attributed string once and answers line-break
// questions and line requests over it. Line breaking is a UAX #14 subset shared by every
// platform so layout is identical on Windows and Linux.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A shaped stretch with one font and one attribute dictionary; indices are absolute.
final class CTSegment {
    let font: CTFont
    let attributes: [NSAttributedString.Key: Any]
    var run: CTShapedRun
    init(font: CTFont, attributes: [NSAttributedString.Key: Any], run: CTShapedRun) {
        self.font = font
        self.attributes = attributes
        self.run = run
    }
}

extension NSAttributedString.Key {
    static let ctFont = NSAttributedString.Key(kCTFontAttributeName as String)
    static let ctForegroundColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
    static let ctForegroundColorFromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
    static let ctBackgroundColor = NSAttributedString.Key(kCTBackgroundColorAttributeName as String)
    static let ctKern = NSAttributedString.Key(kCTKernAttributeName as String)
    static let ctTracking = NSAttributedString.Key(kCTTrackingAttributeName as String)
    static let ctParagraphStyle = NSAttributedString.Key(kCTParagraphStyleAttributeName as String)
    static let ctUnderlineStyle = NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)
    static let ctUnderlineColor = NSAttributedString.Key(kCTUnderlineColorAttributeName as String)
    static let ctStrokeWidth = NSAttributedString.Key(kCTStrokeWidthAttributeName as String)
    static let ctStrokeColor = NSAttributedString.Key(kCTStrokeColorAttributeName as String)
    static let ctBaselineOffset = NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)
    static let ctSuperscript = NSAttributedString.Key(kCTSuperscriptAttributeName as String)
    static let ctLanguage = NSAttributedString.Key(kCTLanguageAttributeName as String)
}

/// - SeeAlso: https://developer.apple.com/documentation/coretext/cttypesetter
public final class CTTypesetter: NSObject {
    let attributed: NSAttributedString
    let text: CTText
    private(set) var segments: [CTSegment] = []
    /// Width charged to each UTF-16 index (a cluster's width sits on its first unit).
    private(set) var charAdvance: [CGFloat] = []
    private(set) var prefix: [CGFloat] = []        // prefix[i] = sum of charAdvance[0..<i]
    private(set) var isClusterStart: [Bool] = []   // count + 1 entries
    private(set) var canBreakBefore: [Bool] = []   // count + 1 entries

    static let tabInterval: CGFloat = 28

    nonisolated(unsafe) static var defaultFont: CTFont = CTFontCreateUIFontForLanguage(.user, 12, nil) ?? CTFontCreateWithName("Helvetica", 12, nil)

    init(attributedString: NSAttributedString) {
        attributed = NSAttributedString(attributedString: attributedString)
        text = CTText(attributed.string as NSString)
        super.init()
        shapeAll()
    }

    private func shapeAll() {
        let count = text.count
        charAdvance = [CGFloat](repeating: 0, count: count)
        isClusterStart = [Bool](repeating: false, count: count + 1)
        isClusterStart[count] = true
        guard count > 0 else { prefix = [0]; canBreakBefore = [true]; return }
        attributed.enumerateAttributes(in: NSRange(location: 0, length: count), options: []) { attrs, range, _ in
            let font = (attrs[.ctFont] as? CTFont) ?? CTTypesetter.defaultFont
            let units = Array(text.units[range.location..<range.location + range.length])
            let language = attrs[.ctLanguage] as? String
            let kern = _ctNumber(attrs[.ctKern]).map { CGFloat($0) } ?? 0
            let tracking = _ctNumber(attrs[.ctTracking]).map { CGFloat($0) } ?? 0
            for var run in CTRuntime.engine.shape(units, font: font.engine, language: language) {
                run.range.location += range.location
                for i in run.clusters.indices { run.clusters[i] += range.location }
                for i in run.glyphs.indices {
                    let unit = text.units[run.clusters[i]]
                    if CTText.isNewline(unit) || unit == 0x09 { run.advances[i] = unit == 0x09 ? CTTypesetter.tabInterval : 0; run.glyphs[i] = run.glyphs[i] }
                    else if kern != 0 || tracking != 0 { run.advances[i] += kern + tracking }
                    charAdvance[run.clusters[i]] += run.advances[i]
                    isClusterStart[run.clusters[i]] = true
                }
                let segFont = run.font === font.engine ? font : CTFont(engine: run.font, matrix: font.matrix)
                segments.append(CTSegment(font: segFont, attributes: attrs, run: run))
            }
        }
        segments.sort { $0.run.range.location < $1.run.range.location }
        prefix = [CGFloat](repeating: 0, count: count + 1)
        for i in 0..<count { prefix[i + 1] = prefix[i] + charAdvance[i] }
        canBreakBefore = [Bool](repeating: false, count: count + 1)
        canBreakBefore[count] = true
        for i in 1..<count where isClusterStart[i] {
            canBreakBefore[i] = CTTypesetter.breakAllowed(before: i, in: text.units)
        }
    }

    // MARK: Line breaking (UAX #14 subset)

    private static func isCJK(_ u: UInt16) -> Bool {
        (0x2E80...0x9FFF).contains(u) || (0xAC00...0xD7AF).contains(u) || (0xF900...0xFAFF).contains(u) || (0xFF00...0xFFEF).contains(u)
    }
    private static func isClosingPunctuation(_ u: UInt16) -> Bool {
        switch u {
        case 0x29, 0x5D, 0x7D, 0x2C, 0x2E, 0x3B, 0x3A, 0x21, 0x3F, 0x3001, 0x3002, 0xFF0C, 0xFF0E, 0xFF1B, 0xFF1A, 0xFF01, 0xFF1F, 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0xFF09, 0x2019, 0x201D: return true
        default: return false
        }
    }
    private static func isOpeningPunctuation(_ u: UInt16) -> Bool {
        switch u {
        case 0x28, 0x5B, 0x7B, 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0xFF08, 0x2018, 0x201C: return true
        default: return false
        }
    }

    static func breakAllowed(before i: Int, in units: [UInt16]) -> Bool {
        let prev = units[i - 1], cur = units[i]
        if prev == 0x200B { return true }                                    // zero-width space
        if cur == 0x00A0 || prev == 0x00A0 { return false }                  // no-break space
        if CTText.isWhitespace(prev) && !CTText.isWhitespace(cur) { return true }
        if CTText.isWhitespace(cur) { return false }
        if isClosingPunctuation(cur) { return false }
        if isOpeningPunctuation(prev) { return false }
        if prev == 0x2D && !isClosingPunctuation(cur) && !(0x30...0x39).contains(cur) { return true }   // after a hyphen
        if isCJK(prev) || isCJK(cur) { return true }
        return false
    }

    /// Width of `range` without its trailing whitespace.
    func width(_ location: Int, _ end: Int, trimTrailingWhitespace: Bool) -> CGFloat {
        var e = end
        if trimTrailingWhitespace { while e > location && CTText.isWhitespace(text.units[e - 1]) { e -= 1 } }
        return prefix[e] - prefix[location]
    }

    /// Length of the newline sequence starting at `i` (2 for CR LF), or 0.
    func newlineLength(at i: Int) -> Int {
        guard i < text.count, CTText.isNewline(text.units[i]) else { return 0 }
        if text.units[i] == 0x0D, i + 1 < text.count, text.units[i + 1] == 0x0A { return 2 }
        return 1
    }

    func suggestBreak(from start: Int, width: Double, offset: Double, clusters: Bool) -> Int {
        let count = text.count
        guard start < count else { return 0 }
        let limit = CGFloat(width) - CGFloat(offset)
        var lastBreak = -1
        var i = start
        while i < count {
            let nl = newlineLength(at: i)
            if nl > 0 { return i + nl - start }          // a hard break ends the line and belongs to it
            if i > start, isClusterStart[i], clusters || canBreakBefore[i] {
                if self.width(start, i, trimTrailingWhitespace: true) <= limit { lastBreak = i } else { break }
            }
            i += 1
        }
        if i >= count, self.width(start, count, trimTrailingWhitespace: true) <= limit { return count - start }
        if lastBreak > start { return lastBreak - start }
        if !clusters {
            // No word fits: fall back to the longest cluster run, at least one cluster.
            return suggestBreak(from: start, width: width, offset: offset, clusters: true)
        }
        var end = start + 1
        while end < count && !isClusterStart[end] { end += 1 }
        return end - start
    }

    /// The segments overlapping `range`, sliced to it, as runs with line-relative positions.
    func makeLine(range: NSRange) -> CTLine {
        let end = range.location + range.length
        var runs: [CTRun] = []
        var pen: CGFloat = 0
        for seg in segments where seg.run.range.location < end && seg.run.range.location + seg.run.range.length > range.location {
            var glyphs: [CGGlyph] = [], advances: [CGSize] = [], positions: [CGPoint] = [], indices: [Int] = [], spaces: [Bool] = []
            let baseline = _ctNumber(seg.attributes[.ctBaselineOffset]).map { CGFloat($0) } ?? 0
                + (_ctNumber(seg.attributes[.ctSuperscript]).map { CGFloat(Int($0)) * seg.font.engine.size * 0.33 } ?? 0)
            for i in seg.run.glyphs.indices {
                let c = seg.run.clusters[i]
                guard c >= range.location, c < end else { continue }
                var adv = seg.run.advances[i]
                if text.units[c] == 0x09 { adv = CTTypesetter.tabInterval - pen.truncatingRemainder(dividingBy: CTTypesetter.tabInterval) }
                glyphs.append(seg.run.glyphs[i])
                positions.append(CGPoint(x: pen + seg.run.offsets[i].x, y: seg.run.offsets[i].y + baseline))
                advances.append(CGSize(width: adv, height: 0))
                indices.append(c)
                spaces.append(CTText.isWhitespace(text.units[c]))
                pen += adv
            }
            guard !glyphs.isEmpty else { continue }
            let lo = max(range.location, seg.run.range.location), hi = min(end, seg.run.range.location + seg.run.range.length)
            runs.append(CTRun(font: seg.font, attributes: seg.attributes, glyphs: glyphs, positions: positions, advances: advances,
                              stringIndices: indices, isWhitespace: spaces, stringRange: NSRange(location: lo, length: hi - lo),
                              status: seg.run.isRightToLeft ? [.rightToLeft, .nonMonotonic] : .noStatus))
        }
        let fallbackFont: CTFont = {
            if let f = runs.first?.font { return f }
            let at = min(range.location, max(0, text.count - 1))
            return text.count > 0 ? (attributed.attribute(.ctFont, at: at, effectiveRange: nil) as? CTFont) ?? CTTypesetter.defaultFont : CTTypesetter.defaultFont
        }()
        var trailing: CGFloat = 0
        var j = end
        while j > range.location && CTText.isWhitespace(text.units[j - 1]) { trailing += charAdvance[j - 1]; j -= 1 }
        return CTLine(runs: runs, stringRange: range, width: pen, trailingWhitespaceWidth: trailing, fallbackFont: fallbackFont)
    }
}

public func CTTypesetterGetTypeID() -> CFTypeID { 4 }

public func CTTypesetterCreateWithAttributedString(_ string: CFAttributedString) -> CTTypesetter {
    CTTypesetter(attributedString: string)
}

public func CTTypesetterCreateWithAttributedStringAndOptions(_ string: CFAttributedString, _ options: CFDictionary?) -> CTTypesetter? {
    CTTypesetter(attributedString: string)
}

public func CTTypesetterCreateLine(_ typesetter: CTTypesetter, _ stringRange: CFRange) -> CTLine {
    CTTypesetterCreateLineWithOffset(typesetter, stringRange, 0)
}

public func CTTypesetterCreateLineWithOffset(_ typesetter: CTTypesetter, _ stringRange: CFRange, _ offset: Double) -> CTLine {
    var r = stringRange
    if r.length == 0 { r.length = typesetter.text.count - r.location }
    r.location = max(0, min(r.location, typesetter.text.count))
    r.length = max(0, min(r.length, typesetter.text.count - r.location))
    return typesetter.makeLine(range: r.nsRange)
}

public func CTTypesetterSuggestLineBreak(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double) -> CFIndex {
    typesetter.suggestBreak(from: startIndex, width: width, offset: 0, clusters: false)
}

public func CTTypesetterSuggestLineBreakWithOffset(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double, _ offset: Double) -> CFIndex {
    typesetter.suggestBreak(from: startIndex, width: width, offset: offset, clusters: false)
}

public func CTTypesetterSuggestClusterBreak(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double) -> CFIndex {
    typesetter.suggestBreak(from: startIndex, width: width, offset: 0, clusters: true)
}

public func CTTypesetterSuggestClusterBreakWithOffset(_ typesetter: CTTypesetter, _ startIndex: CFIndex, _ width: Double, _ offset: Double) -> CFIndex {
    typesetter.suggestBreak(from: startIndex, width: width, offset: offset, clusters: true)
}

public let kCTTypesetterOptionDisableBidiProcessing: CFString = "CTTypesetterOptionDisableBidiProcessing"
public let kCTTypesetterOptionForcedEmbeddingLevel: CFString = "CTTypesetterOptionForcedEmbeddingLevel"
public let kCTTypesetterOptionAllowUnboundedLayout: CFString = "CTTypesetterOptionAllowUnboundedLayout"
