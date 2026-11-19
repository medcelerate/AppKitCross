// TextKit 1 incremental relayout (ADR-0040): an edit re-typesets the paragraphs it touches
// (a text block's paragraphs together), the paragraphs after it move by the edit's length
// and height deltas, and the result is the layout a full pass gives the same text, to the
// point and to the pixel.

import XCTest
@testable import AppKit

final class TextKit1IncrementalLayoutTests: XCTestCase, @unchecked Sendable {
    @MainActor private static var font: NSFont { NSFont.systemFont(ofSize: 13) }

    /// `lines` paragraphs; every seventh wraps at 300 points.
    private func longText(_ lines: Int = 3000) -> String {
        (0..<lines).map { i in i % 7 == 3 ? "Line \(i) is a longer one that wraps across the container width at least once or twice, with words" : "Line \(i) with some words in it" }
            .joined(separator: "\n")
    }

    @MainActor private func textKit1(_ text: NSAttributedString, width: CGFloat = 300, height: CGFloat = .greatestFiniteMagnitude, containers: Int = 1) -> (NSTextStorage, NSLayoutManager, [NSTextContainer]) {
        let ts = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        ts.addLayoutManager(lm)
        var cs: [NSTextContainer] = []
        for _ in 0..<containers {
            let c = NSTextContainer(size: NSSize(width: width, height: height))
            lm.addTextContainer(c)
            cs.append(c)
        }
        return (ts, lm, cs)
    }

    @MainActor private func textKit1(_ text: String, width: CGFloat = 300) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let (ts, lm, cs) = textKit1(NSAttributedString(string: text, attributes: [.font: TextKit1IncrementalLayoutTests.font]), width: width)
        return (ts, lm, cs[0])
    }

    /// The layout `lm` holds equals a full layout of a copy of its text in the same geometry.
    @MainActor private func assertMatchesFullLayout(_ lm: NSLayoutManager, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard let storage = lm.textStorage, let c0 = lm.textContainers.first else { return XCTFail("no storage", file: file, line: line) }
        // A copy through the storage's own reader (corelibs' NSAttributedString(attributedString:)
        // does not read an NSTextStorage's backing); the layout manager holds its storage
        // weakly, so keep the copy alive.
        let (fullStorage, full, fullContainers) = textKit1(storage.attributedSubstring(from: NSRange(location: 0, length: storage.length)), width: c0.size.width, height: c0.size.height, containers: lm.textContainers.count)
        defer { withExtendedLifetime(fullStorage) {} }
        for (c, f) in zip(lm.textContainers, fullContainers) {
            f.lineFragmentPadding = c.lineFragmentPadding
            f.lineBreakMode = c.lineBreakMode
            f.maximumNumberOfLines = c.maximumNumberOfLines
            f._alignmentWidth = c._alignmentWidth
        }
        let a = lm._lineFragments, b = full._lineFragments
        let m = message()
        XCTAssertEqual(a.count, b.count, "line count \(m)", file: file, line: line)
        var reported = 0
        for (x, y) in zip(a, b) {
            let same = x.charRange == y.charRange && x.newlineLength == y.newlineLength && x.rect == y.rect && x.usedRect == y.usedRect
                && x.baseline == y.baseline && x.textX == y.textX && x.container == y.container
                && x.offset(x.visibleEnd) == y.offset(y.visibleEnd) && x.offset(x.charRange.location) == y.offset(y.charRange.location)
            if !same, reported < 3 {
                reported += 1
                XCTFail("fragment \(x.charRange) \(x.rect) \(x.usedRect) differs from the full layout's \(y.charRange) \(y.rect) \(y.usedRect) \(m)", file: file, line: line)
            }
        }
        let fa = lm._laidOutBlockFrames, fb = full._laidOutBlockFrames
        XCTAssertEqual(fa.count, fb.count, "block count \(m)", file: file, line: line)
        for (x, y) in zip(fa, fb) where x.block !== y.block || x.bounds != y.bounds || x.layout != y.layout || x.charRange != y.charRange {
            XCTFail("block frame \(x.charRange) \(x.bounds) differs from the full layout's \(y.charRange) \(y.bounds) \(m)", file: file, line: line)
            break
        }
        XCTAssertEqual(lm.extraLineFragmentRect, full.extraLineFragmentRect, "extra fragment \(m)", file: file, line: line)
        XCTAssertEqual(lm.firstUnlaidCharacterIndex(), full.firstUnlaidCharacterIndex(), m, file: file, line: line)
        XCTAssertEqual(lm.numberOfGlyphs, full.numberOfGlyphs, m, file: file, line: line)
        for (i, c) in lm.textContainers.enumerated() {
            XCTAssertEqual(lm.usedRect(for: c), full.usedRect(for: full.textContainers[i]), "used rect \(m)", file: file, line: line)
            XCTAssertEqual(lm.glyphRange(for: c), full.glyphRange(for: full.textContainers[i]), m, file: file, line: line)
        }
        // Queries that map document indices into the moved lines.
        let n = storage.length
        for g in stride(from: 0, to: n, by: max(1, n / 37)) {
            XCTAssertEqual(lm.location(forGlyphAt: g), full.location(forGlyphAt: g), "location of \(g) \(m)", file: file, line: line)
            let r = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let p = NSPoint(x: r.minX + 40, y: r.midY)
            XCTAssertEqual(lm.glyphIndex(for: p, in: c0), full.glyphIndex(for: p, in: full.textContainers[0]), "hit test at \(p) \(m)", file: file, line: line)
        }
    }

    // MARK: Work per edit

    /// A keystroke at the start, in the middle and at the end of a 3000-line document
    /// typesets a paragraph or two, and the result is the full layout's.
    func testEditsAtTheStartMiddleAndEndTypesetOnlyTheirParagraphs() {
        MainActor.assumeIsolated {
            let (ts, lm, c) = textKit1(longText())
            lm.ensureLayout(for: c)
            XCTAssertEqual(lm._typesetParagraphCount, 3000, "the first pass typesets every paragraph once")
            let length = (ts.string as NSString).length
            for (name, at) in [("start", 0), ("middle", length / 2), ("end", length)] {
                for s in ["x", "\n", "y"] {
                    let before = lm._typesetParagraphCount
                    let loc = at == length ? (ts.string as NSString).length : at
                    ts.replaceCharacters(in: NSRange(location: loc, length: 0), with: s)
                    lm.ensureLayout(for: c)
                    XCTAssertLessThanOrEqual(lm._typesetParagraphCount - before, 4, "typing \(s.debugDescription) at the \(name)")
                }
                assertMatchesFullLayout(lm, "after typing at the \(name)")
            }
        }
    }

    /// Return splits a paragraph and Backspace across the line break joins it again; a
    /// deletion across several paragraphs joins them all.
    func testParagraphSplitAndMerge() {
        MainActor.assumeIsolated {
            let (ts, lm, c) = textKit1(longText(200))
            lm.ensureLayout(for: c)
            let s = ts.string as NSString
            let inside = s.range(of: "Line 102 with").location + 7
            ts.replaceCharacters(in: NSRange(location: inside, length: 0), with: "\n")
            lm.ensureLayout(for: c)
            assertMatchesFullLayout(lm, "after Return")
            ts.replaceCharacters(in: NSRange(location: inside, length: 1), with: "")
            assertMatchesFullLayout(lm, "after Backspace across the break")
            // Backspace at the start of a paragraph joins it to the previous one.
            let start = (ts.string as NSString).range(of: "Line 150").location
            ts.replaceCharacters(in: NSRange(location: start - 1, length: 1), with: "")
            assertMatchesFullLayout(lm, "after joining two paragraphs")
            let from = (ts.string as NSString).range(of: "Line 60").location + 3
            let to = (ts.string as NSString).range(of: "Line 64").location + 2
            let before = lm._typesetParagraphCount
            ts.replaceCharacters(in: NSRange(location: from, length: to - from), with: "")
            lm.ensureLayout(for: c)
            XCTAssertLessThanOrEqual(lm._typesetParagraphCount - before, 3)
            assertMatchesFullLayout(lm, "after deleting across paragraphs")
            // CR LF typed in two steps: the LF joins the CR's paragraph break.
            let at = (ts.string as NSString).range(of: "Line 120").location
            ts.replaceCharacters(in: NSRange(location: at, length: 0), with: "\r")
            assertMatchesFullLayout(lm, "after a CR")
            ts.replaceCharacters(in: NSRange(location: at + 1, length: 0), with: "\n")
            assertMatchesFullLayout(lm, "after its LF")
        }
    }

    /// An edit that makes its paragraph wrap onto more lines moves every later line down by
    /// exactly the new lines' height, without typesetting them.
    func testEditChangingAParagraphsLineCountMovesTheLinesAfterIt() {
        MainActor.assumeIsolated {
            let (ts, lm, c) = textKit1(longText(400))
            lm.ensureLayout(for: c)
            let s = ts.string as NSString
            let after = s.range(of: "Line 300 ").location
            let rectBefore = lm.lineFragmentRect(forGlyphAt: after, effectiveRange: nil)
            let lines = lm._lineFragments.count
            let at = s.range(of: "Line 200 with").location + 8
            let before = lm._typesetParagraphCount
            let added = " and now a great deal more text, enough to wrap this paragraph onto a second and a third line at this width"
            ts.replaceCharacters(in: NSRange(location: at, length: 0), with: added)
            lm.ensureLayout(for: c)
            XCTAssertLessThanOrEqual(lm._typesetParagraphCount - before, 3)
            let grown = lm._lineFragments.count - lines
            XCTAssertGreaterThanOrEqual(grown, 2, "the paragraph wraps onto more lines")
            let rectAfter = lm.lineFragmentRect(forGlyphAt: after + (added as NSString).length, effectiveRange: nil)
            XCTAssertEqual(rectAfter.minY - rectBefore.minY, CGFloat(grown) * rectBefore.height, accuracy: 0.001)
            assertMatchesFullLayout(lm, "after the paragraph grew")
            ts.replaceCharacters(in: NSRange(location: at, length: (added as NSString).length), with: "")
            assertMatchesFullLayout(lm, "after it shrank back")
            XCTAssertEqual(lm.lineFragmentRect(forGlyphAt: after, effectiveRange: nil), rectBefore)
        }
    }

    /// Paragraph styles with spacing, a temporary colour and a paragraph style change each
    /// lay out only their paragraphs, and still match a full layout.
    func testAttributeEditsAndTemporaryAttributes() {
        MainActor.assumeIsolated {
            let text = NSMutableAttributedString(string: longText(300), attributes: [.font: TextKit1IncrementalLayoutTests.font])
            let spaced = NSMutableParagraphStyle()
            spaced.paragraphSpacing = 6
            spaced.paragraphSpacingBefore = 3
            text.addAttribute(.paragraphStyle, value: spaced, range: NSRange(location: 0, length: text.length))
            let (ts, lm, cs) = textKit1(text)
            let c = cs[0]
            lm.ensureLayout(for: c)
            let s = ts.string as NSString
            let para = s.paragraphRange(for: NSRange(location: s.range(of: "Line 150").location, length: 0))
            let centred = NSMutableParagraphStyle()
            centred.alignment = .center
            centred.paragraphSpacingBefore = 20
            var before = lm._typesetParagraphCount
            ts.addAttribute(.paragraphStyle, value: centred, range: para)
            lm.ensureLayout(for: c)
            XCTAssertLessThanOrEqual(lm._typesetParagraphCount - before, 3)
            assertMatchesFullLayout(lm, "after a paragraph style change")
            ts.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 18), range: NSRange(location: para.location + 2, length: 4))
            assertMatchesFullLayout(lm, "after a font change")
            before = lm._typesetParagraphCount
            lm.addTemporaryAttribute(.foregroundColor, value: NSColor.systemRed, forCharacterRange: NSRange(location: para.location, length: 3))
            lm.ensureLayout(for: c)
            XCTAssertLessThanOrEqual(lm._typesetParagraphCount - before, 3, "a temporary colour lays out its paragraph")
            before = lm._typesetParagraphCount
            lm.addTemporaryAttribute(.spellingState, value: NSNumber(value: 1), forCharacterRange: NSRange(location: 10, length: 3))
            lm.ensureLayout(for: c)
            XCTAssertEqual(lm._typesetParagraphCount - before, 0, "a spelling mark only redraws")
            // An edit before the coloured paragraph moves it, colour and all.
            ts.replaceCharacters(in: NSRange(location: 5, length: 0), with: "abc\n")
            lm.ensureLayout(for: c)
            let shown = lm.temporaryAttributes(atCharacterIndex: para.location + 4, effectiveRange: nil)
            XCTAssertNotNil(shown[.foregroundColor])
            XCTAssertNil(lm.textStorage?.attribute(.foregroundColor, at: para.location + 4, effectiveRange: nil))
            lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: ts.length), actualCharacterRange: nil)
            lm.ensureLayout(for: c)
            XCTAssertGreaterThanOrEqual(lm._typesetParagraphCount - before, 300, "invalidating everything typesets everything")
        }
    }

    // MARK: Text blocks and tables

    /// 20 paragraphs, a 2×2 table, 20 paragraphs.
    @MainActor private func tableDocument() -> (NSMutableAttributedString, [NSTextTableBlock]) {
        let font = TextKit1IncrementalLayoutTests.font
        let out = NSMutableAttributedString(string: (0..<20).map { "Before \($0)\n" }.joined(), attributes: [.font: font])
        let table = NSTextTable()
        table.numberOfColumns = 2
        var blocks: [NSTextTableBlock] = []
        for (row, col, text) in [(0, 0, "Left\n"), (0, 1, "Right cell\nwith two lines\n"), (1, 0, "Below\n"), (1, 1, "End\n")] {
            let b = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)
            b.setWidth(4, type: .absoluteValueType, for: .padding)
            b.setWidth(1, type: .absoluteValueType, for: .border)
            b.backgroundColor = .systemYellow
            blocks.append(b)
            let ps = NSMutableParagraphStyle()
            ps.textBlocks = [b]
            out.append(NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: ps]))
        }
        out.append(NSAttributedString(string: (0..<20).map { "After \($0)" }.joined(separator: "\n"), attributes: [.font: font]))
        return (out, blocks)
    }

    /// Typing in a table cell lays the table out again as one unit (its columns and rows
    /// depend on every cell); edits around it move it.
    func testEditInsideATableCell() {
        MainActor.assumeIsolated {
            let (doc, blocks) = tableDocument()
            let (ts, lm, cs) = textKit1(doc, width: 400)
            let c = cs[0]
            lm.ensureLayout(for: c)
            let s = ts.string as NSString
            let cell = s.range(of: "Right cell").location + 5
            var before = lm._typesetParagraphCount
            ts.replaceCharacters(in: NSRange(location: cell, length: 0), with: " and a much longer text that wraps inside the cell")
            lm.ensureLayout(for: c)
            XCTAssertLessThanOrEqual(lm._typesetParagraphCount - before, 7, "the table's five paragraphs and a neighbour or two")
            assertMatchesFullLayout(lm, "after typing in a cell")
            // Return inside the cell adds a paragraph to it.
            ts.replaceCharacters(in: NSRange(location: cell, length: 0), with: "\n")
            assertMatchesFullLayout(lm, "after Return in a cell")
            // An edit above the table moves its box and cells.
            let box = lm.boundsRect(for: blocks[0], at: (ts.string as NSString).range(of: "Left").location, effectiveRange: nil)
            before = lm._typesetParagraphCount
            ts.replaceCharacters(in: NSRange(location: 0, length: 0), with: "New first line\n")
            lm.ensureLayout(for: c)
            XCTAssertLessThanOrEqual(lm._typesetParagraphCount - before, 3, "the table is moved, not typeset")
            let moved = lm.boundsRect(for: blocks[0], at: (ts.string as NSString).range(of: "Left").location, effectiveRange: nil)
            XCTAssertEqual(moved.minY - box.minY, lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height, accuracy: 0.001)
            assertMatchesFullLayout(lm, "after an edit above the table")
            // A paragraph after the table joins it: the table's run grows by a paragraph.
            let after = (ts.string as NSString).range(of: "After 0")
            let ps = NSMutableParagraphStyle()
            ps.textBlocks = [blocks[3]]
            ts.addAttribute(.paragraphStyle, value: ps, range: after)
            assertMatchesFullLayout(lm, "after a paragraph joined the table")
            // And a cell paragraph leaves it.
            let below = (ts.string as NSString).range(of: "Below")
            ts.addAttribute(.paragraphStyle, value: NSParagraphStyle.default, range: (ts.string as NSString).paragraphRange(for: below))
            assertMatchesFullLayout(lm, "after a paragraph left the table")
        }
    }

    // MARK: Bounded containers

    /// Pages (containers of bounded height): lines after an edit may change container, so
    /// the pass typesets from the edit on, and matches a full layout.
    func testEditsInBoundedContainers() {
        MainActor.assumeIsolated {
            let text = NSAttributedString(string: longText(60), attributes: [.font: TextKit1IncrementalLayoutTests.font])
            let (ts, lm, cs) = textKit1(text, width: 300, height: 200, containers: 6)
            lm.ensureLayout(for: cs[0])
            let before = lm._typesetParagraphCount
            let at = (ts.string as NSString).range(of: "Line 40").location
            ts.replaceCharacters(in: NSRange(location: at, length: 0), with: "Inserted\n")
            lm.ensureLayout(for: cs[0])
            XCTAssertLessThan(lm._typesetParagraphCount - before, 40, "the pages before the edit are kept")
            assertMatchesFullLayout(lm, "after an edit on a later page")
            ts.replaceCharacters(in: NSRange(location: 3, length: 0), with: "a much longer insertion that wraps the first paragraph onto another line or two\n\n")
            assertMatchesFullLayout(lm, "after an edit on the first page")
        }
    }

    // MARK: Geometry changes

    /// A container that gets narrower or wider after a full layout wraps every paragraph at
    /// its new width (the units' lines hold only at the width they were typeset at), and an
    /// edit afterwards still matches a full layout.
    func testContainerWidthChangeRelaysOutEveryParagraph() {
        MainActor.assumeIsolated {
            let (ts, lm, c) = textKit1(longText(400), width: 300)
            let lines = lm._lineFragments.count
            for width: CGFloat in [180, 420, 300] {
                c.size = NSSize(width: width, height: c.size.height)
                assertMatchesFullLayout(lm, "at width \(width)")
            }
            XCTAssertEqual(lm._lineFragments.count, lines, "back at the first width, the first layout")
            c.size = NSSize(width: 200, height: c.size.height)
            _ = lm._lineFragments
            let at = (ts.string as NSString).range(of: "Line 200").location
            ts.replaceCharacters(in: NSRange(location: at, length: 0), with: "typed ")
            assertMatchesFullLayout(lm, "an edit after the width changed")
            for padding: CGFloat in [0, 12] {
                c.lineFragmentPadding = padding
                assertMatchesFullLayout(lm, "padding \(padding)")
            }
        }
    }

    /// The units remember the geometry they were typeset in: a container resized while it was
    /// not attached to the layout manager (so no `textContainerChangedGeometry` reached it)
    /// still lays every paragraph out again.
    func testGeometryChangedOutsideTheLayoutManagerStillRelaysOut() {
        MainActor.assumeIsolated {
            let (ts, lm, c) = textKit1(longText(200), width: 300)
            _ = lm._lineFragments
            c.layoutManager = nil
            c.size = NSSize(width: 160, height: c.size.height)
            c.layoutManager = lm
            lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: 0), actualCharacterRange: nil)
            assertMatchesFullLayout(lm, "after a detached resize")
            withExtendedLifetime(ts) {}
        }
    }

    /// A text view whose `linkTextAttributes` getter (which a layout pass reads) narrows its
    /// container: the invalidation inside the pass is not lost, the layout ends at the new width.
    func testGeometryChangeDuringAPassIsNotLost() {
        MainActor.assumeIsolated {
            final class Narrowing: NSTextView {
                var narrowTo: CGFloat?
                override var linkTextAttributes: [NSAttributedString.Key: Any]? {
                    get {
                        if let w = narrowTo { narrowTo = nil; textContainer?.size = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude) }
                        return super.linkTextAttributes
                    }
                    set { super.linkTextAttributes = newValue }
                }
            }
            let tv = Narrowing(frame: NSRect(x: 0, y: 0, width: 300, height: 400), textContainer: nil)
            tv.isVerticallyResizable = false
            tv.textStorage?.setAttributedString(NSAttributedString(string: longText(200), attributes: [.font: TextKit1IncrementalLayoutTests.font]))
            let lm = tv.layoutManager!
            _ = lm._lineFragments
            tv.textContainer?.widthTracksTextView = false
            tv.narrowTo = 150
            tv.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
            _ = lm._lineFragments       // the pass that narrows the container
            XCTAssertEqual(tv.textContainer?.size.width, 150)
            XCTAssertNil(tv.narrowTo)
            assertMatchesFullLayout(lm, "after a resize inside a pass")
        }
    }

    /// TextEdit's arrangement: a text view in a scroll view, narrowed with its window, wraps
    /// every paragraph at the new width (PC report on PR 91), and typing afterwards matches.
    func testTextViewInAScrollViewRewrapsWhenItsWindowNarrows() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let tv = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
            tv.autoresizingMask = [.width, .height]
            tv.textStorage?.setAttributedString(NSAttributedString(string: longText(600), attributes: [.font: TextKit1IncrementalLayoutTests.font]))
            scroll.documentView = tv
            window.contentView?.addSubview(scroll)
            window.display()
            let lm = tv.layoutManager!
            let wide = lm._lineFragments.count
            let wideWidth = tv.textContainer!.size.width
            let wideLongest = lm._lineFragments.map(\.usedRect.maxX).max() ?? 0
            for width in stride(from: 620, through: 300, by: -40) {
                window.setContentSize(NSSize(width: CGFloat(width), height: 460))
                window.display()
            }
            // Relative bounds only: line widths are the platform's font metrics (PR 90).
            XCTAssertLessThan(tv.textContainer!.size.width, 0.6 * wideWidth, "the container followed the window")
            XCTAssertGreaterThan(lm._lineFragments.count, wide, "narrower lines wrap more")
            let longest = lm._lineFragments.map(\.usedRect.maxX).max() ?? 0
            XCTAssertLessThan(longest, 0.6 * wideLongest, "every paragraph wrapped at the new width, none kept the old one")
            assertMatchesFullLayout(lm, "after the window narrowed")
            tv.setSelectedRange(NSRange(location: 500, length: 0))
            tv.insertText("ok", replacementRange: tv.selectedRange())
            window.display()
            assertMatchesFullLayout(lm, "typing after the window narrowed")
            window.close()
        }
    }

    // MARK: Random edits

    /// A small deterministic generator (SplitMix64).
    private struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    }

    /// One random edit of `ts`: typing, Return, deletions within and across paragraphs,
    /// pastes, paragraph style and font changes.
    @MainActor private func randomEdit(_ ts: NSTextStorage, _ rng: inout Random) {
        let n = ts.length
        let at = rng.int(n + 1)
        let words = ["a", "word", " ", "\n", "longer words that wrap across the line", "\t", "x\ny", "\r\n"]
        switch rng.int(8) {
        case 0, 1: ts.replaceCharacters(in: NSRange(location: at, length: 0), with: words[rng.int(words.count)])
        case 2: ts.replaceCharacters(in: NSRange(location: at, length: 0), with: "\n")
        case 3: if at > 0 { ts.replaceCharacters(in: NSRange(location: at - 1, length: 1), with: "") }
        case 4: ts.replaceCharacters(in: NSRange(location: at, length: min(n - at, rng.int(120))), with: "")
        case 5:
            let len = min(n - at, rng.int(60))
            ts.replaceCharacters(in: NSRange(location: at, length: len), with: "Pasted \(rng.int(1000)) text\nand a second paragraph")
        case 6:
            guard n > 0 else { return }
            let ps = NSMutableParagraphStyle()
            ps.alignment = [.left, .center, .right, .justified][rng.int(4)]
            ps.paragraphSpacing = CGFloat(rng.int(3) * 4)
            ps.paragraphSpacingBefore = CGFloat(rng.int(2) * 5)
            ps.firstLineHeadIndent = CGFloat(rng.int(3) * 10)
            let r = (ts.string as NSString).paragraphRange(for: NSRange(location: min(at, n - 1), length: 0))
            ts.addAttribute(.paragraphStyle, value: ps, range: r)
        default:
            guard n > 0 else { return }
            let len = min(n - min(at, n - 1), 1 + rng.int(30))
            ts.addAttribute(.font, value: NSFont.systemFont(ofSize: CGFloat(10 + rng.int(14))), range: NSRange(location: min(at, n - 1), length: len))
        }
    }

    /// Random edit sequences, laid out after each edit or after a few (and inside editing
    /// transactions), always match a full layout of the same text.
    func testRandomEditsMatchAFullLayout() {
        MainActor.assumeIsolated {
            for seed in [1, 7, 42] as [UInt64] {
                var rng = Random(state: seed)
                let (doc, _) = tableDocument()
                doc.append(NSAttributedString(string: "\n" + longText(80), attributes: [.font: TextKit1IncrementalLayoutTests.font]))
                let (ts, lm, cs) = textKit1(doc, width: 320)
                lm.ensureLayout(for: cs[0])
                for step in 0..<60 {
                    let batch = 1 + rng.int(3)
                    let transaction = rng.int(4) == 0
                    if transaction { ts.beginEditing() }
                    for _ in 0..<batch { randomEdit(ts, &rng) }
                    if transaction { ts.endEditing() }
                    assertMatchesFullLayout(lm, "seed \(seed) step \(step)")
                }
                let work = lm._typesetParagraphCount
                XCTAssertLessThan(work, 60 * 3 * 12 + 140, "seed \(seed): edits typeset their paragraphs, not the document (\(work))")
                // The layout manager holds its storage weakly: keep the text system alive to here.
                withExtendedLifetime((ts, cs)) {}
            }
        }
    }

    /// The same random edits typed into a text view draw the pixels a text view showing the
    /// final text from scratch draws.
    func testRandomEditsDrawTheSamePixelsAsAFullLayout() throws {
        try requireHostBackend()
        try MainActor.assumeIsolated {
            @MainActor func textView(_ text: NSAttributedString) -> (NSWindow, NSTextView) {
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
                w.isReleasedWhenClosed = false
                let tv = NSTextView(usingTextLayoutManager: false)
                tv.frame = w.contentView!.bounds
                tv.isRichText = true
                w.contentView!.addSubview(tv)
                tv.textStorage?.setAttributedString(text)
                w.display()
                return (w, tv)
            }
            @MainActor func render(_ tv: NSTextView) throws -> NSBitmapImageRep {
                tv.window?.display()
                let rep = try XCTUnwrap(tv.bitmapImageRepForCachingDisplay(in: tv.bounds))
                tv.cacheDisplay(in: tv.bounds, to: rep)
                return rep
            }
            var rng = Random(state: 2026)
            let (doc, _) = tableDocument()
            doc.append(NSAttributedString(string: "\n" + longText(30), attributes: [.font: TextKit1IncrementalLayoutTests.font]))
            let (w, edited) = textView(doc)
            for _ in 0..<40 {
                randomEdit(edited.textStorage!, &rng)
                w.display()
            }
            edited.setSelectedRange(NSRange(location: 0, length: 0))
            let (w2, fresh) = textView(edited.textStorage!.attributedSubstring(from: NSRange(location: 0, length: edited.textStorage!.length)))
            fresh.setSelectedRange(NSRange(location: 0, length: 0))
            let one = try render(edited), two = try render(fresh)
            XCTAssertEqual(one.pixelsWide, two.pixelsWide)
            XCTAssertEqual(one.pixelsHigh, two.pixelsHigh)
            var differing = 0, inked = 0
            for y in 0..<min(one.pixelsHigh, two.pixelsHigh) {
                for x in 0..<min(one.pixelsWide, two.pixelsWide) {
                    let a = one.colorAt(x: x, y: y), b = two.colorAt(x: x, y: y)
                    if let a, a.brightnessComponent < 0.6 { inked += 1 }
                    if a != b { differing += 1 }
                }
            }
            XCTAssertGreaterThan(inked, 500, "text was drawn")
            XCTAssertEqual(differing, 0, "incremental and full layout draw the same pixels")
            // Closed here, while the test holds them, so no window of this test is torn down
            // (or drawn by a frame clock) after it ends.
            w.close(); w2.close()
            withExtendedLifetime((w, w2, edited, fresh)) {}
        }
    }

    // MARK: Timing

    /// Milliseconds per keystroke (Return, "o", "k") in the middle of a 3000-line document,
    /// printed for ADR-0040's numbers (the work itself is bounded by the paragraph counts
    /// above, which do not depend on the machine's load).
    func testKeystrokeTimingInALongDocument() {
        MainActor.assumeIsolated {
            let (ts, lm, c) = textKit1(longText())
            lm.ensureLayout(for: c)
            let mid = (ts.string as NSString).length / 2
            let start = Date()
            for (k, s) in ["\n", "o", "k"].enumerated() {
                ts.replaceCharacters(in: NSRange(location: mid + k, length: 0), with: s)
                lm.ensureLayout(for: c)
                _ = lm.usedRect(for: c)
            }
            let ms = Date().timeIntervalSince(start) * 1000 / 3
            print("TextKit 1 keystroke at 3000 lines: \(String(format: "%.2f", ms)) ms")
        }
    }
}
