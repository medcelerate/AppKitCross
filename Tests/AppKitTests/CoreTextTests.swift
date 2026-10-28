// CoreText behaviour that must hold on every platform: on macOS these run against Apple's
// CoreText (the specification), on Windows and Linux against the package's module.

import XCTest
@testable import AppKit
#if canImport(CoreText)
import CoreText
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreText)
final class CoreTextTests: XCTestCase, @unchecked Sendable {
    private func systemFont(_ size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private func attributed(_ s: String, font: CTFont, extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        for (k, v) in extra { attrs[k] = v }
        return NSAttributedString(string: s, attributes: attrs)
    }

    func testFontMetricsAndNames() {
        let f = systemFont(20)
        XCTAssertEqual(CTFontGetSize(f), 20)
        XCTAssertGreaterThan(CTFontGetAscent(f), 10)
        XCTAssertGreaterThan(CTFontGetDescent(f), 1)
        XCTAssertGreaterThan(CTFontGetCapHeight(f), 8)
        XCTAssertLessThan(CTFontGetCapHeight(f), CTFontGetAscent(f) + 0.01)
        XCTAssertGreaterThan(CTFontGetXHeight(f), 4)
        XCTAssertGreaterThan(CTFontGetUnitsPerEm(f), 100)
        XCTAssertFalse((CTFontCopyFamilyName(f) as String).isEmpty)
        XCTAssertFalse((CTFontCopyPostScriptName(f) as String).isEmpty)
        let bigger = CTFontCreateCopyWithAttributes(f, 30, nil, nil)
        XCTAssertEqual(CTFontGetSize(bigger), 30)
        XCTAssertEqual(CTFontCopyFamilyName(bigger) as String, CTFontCopyFamilyName(f) as String)
        let bold = CTFontCreateCopyWithSymbolicTraits(f, 0, nil, .traitBold, .traitBold)
        XCTAssertNotNil(bold)
        if let bold { XCTAssertTrue(CTFontGetSymbolicTraits(bold).contains(.traitBold)) }
        let mono = CTFontCreateUIFontForLanguage(.userFixedPitch, 12, nil)
        XCTAssertNotNil(mono)
        if let mono { XCTAssertTrue(CTFontGetSymbolicTraits(mono).contains(.traitMonoSpace)) }
    }

    func testGlyphsAdvancesAndPaths() {
        let f = systemFont(24)
        let chars: [UniChar] = Array("Hi W".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        XCTAssertTrue(CTFontGetGlyphsForCharacters(f, chars, &glyphs, chars.count))
        XCTAssertTrue(glyphs.allSatisfy { $0 != 0 })
        var advances = [CGSize](repeating: .zero, count: chars.count)
        let total = CTFontGetAdvancesForGlyphs(f, .horizontal, glyphs, &advances, chars.count)
        XCTAssertGreaterThan(advances[0].width, 5)
        XCTAssertGreaterThan(advances[3].width, advances[1].width, "W is wider than i")
        XCTAssertEqual(total, advances.reduce(0) { $0 + Double($1.width) }, accuracy: 0.01)
        var rects = [CGRect](repeating: .zero, count: chars.count)
        let union = CTFontGetBoundingRectsForGlyphs(f, .horizontal, glyphs, &rects, chars.count)
        XCTAssertGreaterThan(rects[0].height, 10)
        XCTAssertGreaterThan(union.width, 5)
        let path = CTFontCreatePathForGlyph(f, glyphs[0], nil)
        XCTAssertNotNil(path)
        if let path {
            let b = path.boundingBox
            XCTAssertGreaterThan(b.height, 10)
            XCTAssertLessThan(abs(b.minY), 3, "the H sits on the baseline")
        }
        // Unmapped: a private-use character.
        let pua: [UniChar] = [0xE000]
        var g: [CGGlyph] = [1]
        _ = CTFontGetGlyphsForCharacters(f, pua, &g, 1)
        XCTAssertTrue(CTFontHasTable(f, 0x636D_6170))   // "cmap"
    }

    func testLineLayoutAndHitTesting() {
        let f = systemFont(16)
        let line = CTLineCreateWithAttributedString(attributed("Hello world", font: f))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        XCTAssertGreaterThan(width, 60)
        XCTAssertEqual(ascent, CTFontGetAscent(f), accuracy: 0.5)
        XCTAssertEqual(descent, CTFontGetDescent(f), accuracy: 0.5)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(CTRunGetGlyphCount(runs[0]), 11)
        XCTAssertEqual(CTLineGetGlyphCount(line), 11)
        var positions = [CGPoint](repeating: .zero, count: 11)
        CTRunGetPositions(runs[0], CFRangeMake(0, 0), &positions)
        XCTAssertEqual(positions[0].x, 0, accuracy: 0.01)
        XCTAssertGreaterThan(positions[10].x, positions[9].x)
        var indices = [CFIndex](repeating: 0, count: 11)
        CTRunGetStringIndices(runs[0], CFRangeMake(0, 0), &indices)
        XCTAssertEqual(indices, Array(0..<11))
        // Offsets and hit testing agree.
        let x5 = CTLineGetOffsetForStringIndex(line, 5, nil)
        XCTAssertGreaterThan(x5, 20)
        XCTAssertEqual(CTLineGetStringIndexForPosition(line, CGPoint(x: x5 + 0.5, y: 0)), 5)
        XCTAssertEqual(CTLineGetStringIndexForPosition(line, CGPoint(x: -5, y: 0)), 0)
        XCTAssertEqual(CTLineGetStringIndexForPosition(line, CGPoint(x: width + 50, y: 0)), 11)
        XCTAssertEqual(CTLineGetOffsetForStringIndex(line, 0, nil), 0, accuracy: 0.01)
        XCTAssertEqual(Double(CTLineGetOffsetForStringIndex(line, 11, nil)), width, accuracy: 0.5)
        XCTAssertEqual(CTLineGetTrailingWhitespaceWidth(CTLineCreateWithAttributedString(attributed("ab ", font: f))), Double(CTFontGetAdvancesForGlyphs(f, .horizontal, [CTFontGetGlyphWithName(f, "space" as CFString)], nil, 1)), accuracy: 2)
        // Mixed fonts produce two runs; kerning widens.
        let two = NSMutableAttributedString(attributedString: attributed("ab", font: f))
        two.append(attributed("cd", font: systemFont(30)))
        XCTAssertEqual((CTLineGetGlyphRuns(CTLineCreateWithAttributedString(two)) as! [CTRun]).count, 2)
        let kerned = CTLineCreateWithAttributedString(attributed("Hello", font: f, extra: [NSAttributedString.Key(kCTKernAttributeName as String): 5]))
        XCTAssertGreaterThan(CTLineGetTypographicBounds(kerned, nil, nil, nil), CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed("Hello", font: f)), nil, nil, nil) + 15)
    }

    func testTypesetterBreaksAtWordsAndNewlines() {
        let f = systemFont(14)
        let text = attributed("one two three four\nfive six", font: f)
        let ts = CTTypesetterCreateWithAttributedString(text)
        let full = CTLineGetTypographicBounds(CTTypesetterCreateLine(ts, CFRangeMake(0, 18)), nil, nil, nil)
        let count = CTTypesetterSuggestLineBreak(ts, 0, full * 0.6)
        XCTAssertTrue(count == 8 || count == 14, "breaks after a word (\(count))")
        let line = CTTypesetterCreateLine(ts, CFRangeMake(0, count))
        XCTAssertLessThanOrEqual(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line), full * 0.6 + 0.01)
        XCTAssertEqual(CTTypesetterSuggestLineBreak(ts, 0, 100_000), 19, "a newline ends the line and belongs to it")
        XCTAssertEqual(CTTypesetterSuggestLineBreak(ts, 19, 100_000), 8)
        XCTAssertGreaterThanOrEqual(CTTypesetterSuggestClusterBreak(ts, 0, 1), 1, "at least one cluster")
        let truncated = CTLineCreateTruncatedLine(CTTypesetterCreateLine(ts, CFRangeMake(0, 18)), full * 0.5, .end, nil)!
        XCTAssertLessThanOrEqual(CTLineGetTypographicBounds(truncated, nil, nil, nil), full * 0.5 + 0.01)
        XCTAssertLessThan(CTLineGetGlyphCount(truncated), 18)
    }

    func testFramesetterLaysOutParagraphs() {
        let f = systemFont(12)
        var alignment = CTTextAlignment.center
        let settings = withUnsafePointer(to: &alignment) { p -> [CTParagraphStyleSetting] in
            [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: UnsafeRawPointer(p))]
        }
        let style = CTParagraphStyleCreate(settings, 1)
        var out = CTTextAlignment.left
        XCTAssertTrue(CTParagraphStyleGetValueForSpecifier(style, .alignment, MemoryLayout<CTTextAlignment>.size, &out))
        XCTAssertEqual(out, .center)
        let text = attributed("The quick brown fox jumps over the lazy dog, again and again.\nSecond paragraph.", font: f,
                              extra: [NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style])
        let fs = CTFramesetterCreateWithAttributedString(text)
        var fit = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), nil, CGSize(width: 120, height: CGFloat.greatestFiniteMagnitude), &fit)
        XCTAssertEqual(fit.length, text.length)
        XCTAssertLessThanOrEqual(size.width, 120.5)
        let lineHeight = CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)
        XCTAssertGreaterThanOrEqual(size.height, lineHeight * 4 - 1, "wraps onto several lines")
        let frame = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), CGPath(rect: CGRect(x: 10, y: 20, width: 120, height: 400), transform: nil), nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        XCTAssertGreaterThanOrEqual(lines.count, 4)
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)
        XCTAssertLessThan(origins[0].y, 400, "origins are relative to the path's box, first line near its top")
        XCTAssertGreaterThan(origins[0].y, 400 - 2 * lineHeight)
        XCTAssertGreaterThan(origins[0].y, origins[1].y)
        XCTAssertGreaterThan(origins[0].x, 0, "centred lines start right of the margin")
        XCTAssertEqual(CTFrameGetVisibleStringRange(frame).length, text.length)
        // A short frame clips: fewer lines visible.
        let short = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), CGPath(rect: CGRect(x: 0, y: 0, width: 120, height: lineHeight * 2.2), transform: nil), nil)
        XCTAssertEqual((CTFrameGetLines(short) as! [CTLine]).count, 2)
        XCTAssertLessThan(CTFrameGetVisibleStringRange(short).length, text.length)
    }

    func testDrawingProducesInk() {
        MainActor.assumeIsolated {
            let f = systemFont(24)
            let line = CTLineCreateWithAttributedString(attributed("Ink", font: f, extra: [NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 0, blue: 0, alpha: 1)]))
            guard let surface = Platform.backend.image.makeOffscreen(size: CGSize(width: 80, height: 40), scale: 1) else { return XCTFail("no offscreen surface") }
            let ctx = surface.context
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
            ctx.textPosition = CGPoint(x: 4, y: 10)
            CTLineDraw(line, ctx)
            guard let image = surface.makeImage() else { return XCTFail("no image") }
            let px = _pixels(image)
            var red = 0
            for i in stride(from: 0, to: px.count, by: 4) where px[i + 2] > 150 && px[i + 1] < 100 { red += 1 }   // BGRA
            XCTAssertGreaterThan(red, 30, "red glyph pixels were drawn")
            let bounds = CTLineGetImageBounds(line, ctx)
            XCTAssertGreaterThan(bounds.width, 20)
            XCTAssertGreaterThan(bounds.minX, 3)
        }
    }
}
#endif
