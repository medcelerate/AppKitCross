// Font fallback contract for the CoreText engines: a character the requested font lacks is
// shaped in a fallback font, so it has a real glyph (not .notdef) and a real advance, and the
// width the line measures is the width its glyph runs draw. On macOS this runs against Apple's
// CoreText (the specification); on Windows and Linux against the package's engines (the
// Windows engine splits runs with IDWriteFontFallback::MapCharacters, ADR-0007).

import XCTest
#if canImport(CoreText)
import CoreText
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreText)
final class CoreTextFallbackTests: XCTestCase, @unchecked Sendable {
    private func systemFont(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private func line(_ s: String, size: CGFloat = 13) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): systemFont(size)]))
    }

    /// Per glyph: (glyph, advance, string index, x), over every run in line order.
    private func glyphs(_ l: CTLine) -> [(glyph: CGGlyph, advance: CGFloat, index: Int, x: CGFloat)] {
        var out: [(CGGlyph, CGFloat, Int, CGFloat)] = []
        for run in CTLineGetGlyphRuns(l) as! [CTRun] {
            let n = CTRunGetGlyphCount(run)
            var g = [CGGlyph](repeating: 0, count: n)
            var a = [CGSize](repeating: .zero, count: n)
            var i = [CFIndex](repeating: 0, count: n)
            var p = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &g)
            CTRunGetAdvances(run, CFRangeMake(0, 0), &a)
            CTRunGetStringIndices(run, CFRangeMake(0, 0), &i)
            CTRunGetPositions(run, CFRangeMake(0, 0), &p)
            for k in 0..<n { out.append((g[k], a[k].width, i[k], p[k].x)) }
        }
        return out
    }

    /// U+25B8 (Segoe UI lacks it), an emoji (U+1F600, a surrogate pair) and CJK each come
    /// out as real glyphs with real advances.
    func testCharactersOutsideThePrimaryFontGetFallbackGlyphs() throws {
        #if os(Linux)
        throw XCTSkip("the Linux text engine has no per-run font fallback yet, and the container has no CJK font")
        #endif
        for s in ["\u{25B8}", "\u{1F600}", "\u{65E5}\u{672C}\u{8A9E}", "a\u{25B8}b"] {
            let l = line(s)
            let gs = glyphs(l)
            let name = s.unicodeScalars.map { String($0.value, radix: 16) }
            XCTAssertFalse(gs.isEmpty, "no glyphs for \(name)")
            for g in gs {
                XCTAssertNotEqual(g.glyph, 0, "missing glyph (.notdef) at index \(g.index) of \(name)")
                XCTAssertGreaterThan(g.advance, 1, "zero advance at index \(g.index) of \(name)")
            }
            XCTAssertGreaterThan(CTLineGetTypographicBounds(l, nil, nil, nil), 1)
        }
    }

    /// The width the line reports (what sizeThatFits measures) is the sum of the advances its
    /// runs draw with, and the fallback character adds its own width.
    func testMeasuredWidthMatchesDrawnRunsWithFallback() throws {
        #if os(Linux)
        throw XCTSkip("the Linux text engine has no per-run font fallback yet, and the container has no CJK font")
        #endif
        let text = "Download the Tiny Whisper model first \u{2014} Settings \u{25B8} Languages \u{25B8} Install."
        let l = line(text)
        let width = CTLineGetTypographicBounds(l, nil, nil, nil)
        let gs = glyphs(l)
        let sum = gs.reduce(0) { $0 + $1.advance }
        XCTAssertEqual(Double(sum), width, accuracy: 0.5)
        if let last = gs.max(by: { $0.x < $1.x }) { XCTAssertEqual(Double(last.x + last.advance), width, accuracy: 0.5) }
        let without = CTLineGetTypographicBounds(line(text.replacingOccurrences(of: "\u{25B8}", with: "")), nil, nil, nil)
        XCTAssertGreaterThan(width, without + 4, "each \u{25B8} takes its own width")
        // Every character of the string is covered by a glyph.
        let covered = Set(gs.map(\.index))
        for (i, u) in Array(text.utf16).enumerated() where !(0xDC00...0xDFFF).contains(u) {
            XCTAssertTrue(covered.contains(i), "character \(i) has no glyph")
        }
    }
}
#endif
