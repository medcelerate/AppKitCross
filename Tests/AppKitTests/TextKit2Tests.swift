// TextKit 2 (ADR-0040): the content storage's paragraphs over storage edits, layout
// fragments that match TextKit 1's lines, viewport layout, selection navigation, the text
// view under both engines, and NSTypesetter as NSLayoutManager uses it.

import XCTest
@testable import AppKit

final class TextKit2Tests: XCTestCase, @unchecked Sendable {
    @MainActor private static var font: NSFont { NSFont.systemFont(ofSize: 13) }

    /// A content storage, layout manager and container over `text`.
    @MainActor private func textKit2(_ text: String, width: CGFloat = 200, attributes: [NSAttributedString.Key: Any]? = nil) -> (NSTextContentStorage, NSTextLayoutManager, NSTextContainer) {
        let cs = NSTextContentStorage()
        cs.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes ?? [.font: TextKit2Tests.font]))
        let lm = NSTextLayoutManager()
        cs.addTextLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        lm.textContainer = container
        return (cs, lm, container)
    }

    @MainActor private func textKit1(_ storage: NSAttributedString, width: CGFloat) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let ts = NSTextStorage(attributedString: storage)
        let lm = NSLayoutManager()
        ts.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        lm.addTextContainer(container)
        return (ts, lm, container)
    }

    private func paragraphs(_ cs: NSTextContentStorage) -> [NSTextParagraph] {
        var out: [NSTextParagraph] = []
        _ = cs.enumerateTextElements(from: nil, options: []) { e in out.append(e as! NSTextParagraph); return true }
        return out
    }

    private func ranges(_ ps: [NSTextParagraph]) -> [NSRange] { ps.map { $0.elementRange!._nsRange! } }

    // MARK: Content storage

    func testParagraphEnumerationFollowsStorageEdits() {
        MainActor.assumeIsolated {
            let (cs, _, _) = textKit2("one\ntwo\nthree")
            let before = paragraphs(cs)
            XCTAssertEqual(before.map(\.attributedString.string), ["one\n", "two\n", "three"])
            XCTAssertEqual(ranges(before), [NSRange(location: 0, length: 4), NSRange(location: 4, length: 4), NSRange(location: 8, length: 5)])
            XCTAssertEqual(before[1].paragraphContentRange?._nsRange, NSRange(location: 4, length: 3))
            XCTAssertEqual(before[1].paragraphSeparatorRange?._nsRange, NSRange(location: 7, length: 1))
            XCTAssertNil(before[2].paragraphSeparatorRange)

            // Typing inside the last paragraph rebuilds it (and the one before, whose
            // separator could merge) and keeps the first.
            cs.textStorage!.replaceCharacters(in: NSRange(location: 10, length: 0), with: "XX")
            let typed = paragraphs(cs)
            XCTAssertEqual(typed.map(\.attributedString.string), ["one\n", "two\n", "thXXree"])
            XCTAssertTrue(typed[0] === before[0], "an untouched paragraph keeps its identity")

            // An edit in the first paragraph shifts the ones after it in place.
            cs.textStorage!.replaceCharacters(in: NSRange(location: 1, length: 1), with: "NNN")
            let shifted = paragraphs(cs)
            XCTAssertEqual(shifted.map(\.attributedString.string), ["oNNNe\n", "two\n", "thXXree"])
            XCTAssertTrue(shifted[2] === typed[2])
            XCTAssertEqual(ranges(shifted), [NSRange(location: 0, length: 6), NSRange(location: 6, length: 4), NSRange(location: 10, length: 7)])

            // A new line break splits a paragraph; deleting one merges two.
            cs.textStorage!.replaceCharacters(in: NSRange(location: 7, length: 0), with: "\n")
            XCTAssertEqual(paragraphs(cs).map(\.attributedString.string), ["oNNNe\n", "t\n", "wo\n", "thXXree"])
            cs.textStorage!.replaceCharacters(in: NSRange(location: 5, length: 1), with: "")
            XCTAssertEqual(paragraphs(cs).map(\.attributedString.string), ["oNNNet\n", "wo\n", "thXXree"])

            // An attribute change rebuilds just its paragraph.
            let mid = paragraphs(cs)
            cs.textStorage!.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 7, length: 2))
            let restyled = paragraphs(cs)
            XCTAssertTrue(restyled[0] === mid[0] && restyled[2] === mid[2])
            XCTAssertFalse(restyled[1] === mid[1])
            XCTAssertEqual(restyled[1].attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.red)

            // CR LF is one separator; deleting everything leaves no paragraphs.
            cs.textStorage!.setAttributedString(NSAttributedString(string: "a\r\nb"))
            XCTAssertEqual(ranges(paragraphs(cs)), [NSRange(location: 0, length: 3), NSRange(location: 3, length: 1)])
            cs.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
            XCTAssertTrue(paragraphs(cs).isEmpty)
            XCTAssertTrue(cs.documentRange.isEmpty)

            // Reverse enumeration and element lookup by range.
            cs.textStorage!.setAttributedString(NSAttributedString(string: "a\nb\nc"))
            var reversed: [String] = []
            _ = cs.enumerateTextElements(from: nil, options: .reverse) { reversed.append(($0 as! NSTextParagraph).attributedString.string); return true }
            XCTAssertEqual(reversed, ["c", "b\n", "a\n"])
            XCTAssertEqual(cs.textElements(for: NSTextRange._make(NSRange(location: 1, length: 2))).count, 2)
            XCTAssertEqual(cs.offset(from: cs.documentRange.location, to: cs.documentRange.endLocation), 5)
            XCTAssertNil(cs.location(cs.documentRange.endLocation, offsetBy: 1))
        }
    }

    func testTextRangeOperations() {
        let r = NSTextRange._make(NSRange(location: 2, length: 5))
        let s = NSTextRange._make(NSRange(location: 5, length: 5))
        XCTAssertTrue(r.intersects(s))
        XCTAssertEqual(r.intersection(s)?._nsRange, NSRange(location: 5, length: 2))
        XCTAssertEqual(r.union(s)._nsRange, NSRange(location: 2, length: 8))
        XCTAssertTrue(r.contains(_NSTextIndexLocation(2)))
        XCTAssertFalse(r.contains(_NSTextIndexLocation(7)))
        XCTAssertTrue(r.contains(NSTextRange._make(NSRange(location: 3, length: 2))))
        XCTAssertNil(NSTextRange(location: _NSTextIndexLocation(4), end: _NSTextIndexLocation(3)))
        XCTAssertTrue(r.isEqual(to: NSTextRange._make(NSRange(location: 2, length: 5))))
        XCTAssertNil(r.intersection(NSTextRange._make(NSRange(location: 8, length: 1))))
        XCTAssertTrue(NSTextRange(location: _NSTextIndexLocation(3)).isEmpty)
    }

    // MARK: Layout

    /// TextKit 1's line fragments for `text`, as (rect, used rect).
    @MainActor private func textKit1Lines(_ text: NSAttributedString, width: CGFloat) -> [(NSRect, NSRect)] {
        let (ts, lm, _) = textKit1(text, width: width)
        var out: [(NSRect, NSRect)] = []
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: ts.length)) { rect, used, _, _, _ in out.append((rect, used)) }
        if lm.extraLineFragmentTextContainer != nil { out.append((lm.extraLineFragmentRect, lm.extraLineFragmentUsedRect)) }
        return out
    }

    /// TextKit 2's lines for `text` in container coordinates, as (line top, height, used x, used width).
    @MainActor private func textKit2Lines(_ text: NSAttributedString, width: CGFloat) -> [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        let (cs, lm, _) = textKit2("", width: width)
        defer { _ = cs }
        cs.textStorage!.setAttributedString(text)
        var out: [(CGFloat, CGFloat, CGFloat, CGFloat)] = []
        _ = lm.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { f in
            XCTAssertEqual(f.state, .layoutAvailable)
            for l in f.textLineFragments {
                let tb = l.typographicBounds
                out.append((f.layoutFragmentFrame.minY + tb.minY, tb.height, f.layoutFragmentFrame.minX + tb.minX, tb.width))
            }
            return true
        }
        return out
    }

    func testWrappedParagraphFragmentsMatchTextKit1() {
        MainActor.assumeIsolated {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 6
            style.paragraphSpacingBefore = 3
            style.firstLineHeadIndent = 12
            style.headIndent = 4
            style.lineSpacing = 2
            let centred = NSMutableParagraphStyle()
            centred.alignment = .center
            let text = NSMutableAttributedString(string: "The quick brown fox jumps over the lazy dog and keeps running far beyond the fence.\n",
                                                 attributes: [.font: TextKit2Tests.font, .paragraphStyle: style])
            text.append(NSAttributedString(string: "A centred line that wraps around once or twice here.\n", attributes: [.font: NSFont.systemFont(ofSize: 18), .paragraphStyle: centred]))
            text.append(NSAttributedString(string: "\nTabs\tand\tend.\n", attributes: [.font: TextKit2Tests.font]))
            for width: CGFloat in [120, 200, 333] {
                let one = textKit1Lines(text, width: width)
                let two = textKit2Lines(text, width: width)
                XCTAssertGreaterThan(one.count, 5)
                XCTAssertEqual(one.count, two.count, "width \(width): line count")
                for (k, (a, b)) in zip(one, two).enumerated() {
                    XCTAssertEqual(a.0.minY, b.0, accuracy: 0.5, "width \(width) line \(k): top")
                    XCTAssertEqual(a.0.height, b.1, accuracy: 0.5, "width \(width) line \(k): height")
                    XCTAssertEqual(a.1.minX, b.2, accuracy: 0.5, "width \(width) line \(k): x")
                    XCTAssertEqual(a.1.width, b.3, accuracy: 0.5, "width \(width) line \(k): width")
                }
            }
            // An empty document has one extra line fragment, as TextKit 1 does.
            let empty = NSAttributedString(string: "")
            XCTAssertEqual(textKit2Lines(empty, width: 200).count, 1)
            XCTAssertEqual(textKit1Lines(empty, width: 200).count, 1)
        }
    }

    func testFragmentGeometryHitTestingAndSegments() {
        MainActor.assumeIsolated {
            let (cs, lm, _) = textKit2("alpha beta gamma delta epsilon zeta eta theta\nsecond", width: 120)
            lm.ensureLayout(for: lm.documentRange)
            let first = lm.textLayoutFragment(for: _NSTextIndexLocation(0))!
            XCTAssertGreaterThan(first.textLineFragments.count, 1, "the first paragraph wraps")
            let second = lm.textLayoutFragment(for: _NSTextIndexLocation(cs.textStorage!.length))!
            XCTAssertFalse(first === second)
            XCTAssertEqual(second.layoutFragmentFrame.minY, first.layoutFragmentFrame.maxY, accuracy: 0.001)
            XCTAssertTrue(lm.textLayoutFragment(for: CGPoint(x: 10, y: second.layoutFragmentFrame.midY)) === second)
            XCTAssertEqual(lm.usageBoundsForTextContainer.height, second.layoutFragmentFrame.maxY, accuracy: 0.001)
            // A point maps to the caret before the nearest glyph edge.
            let line0 = first.textLineFragments[0]
            let x = first.layoutFragmentFrame.minX + line0.typographicBounds.minX + line0.locationForCharacter(at: 3).x
            XCTAssertEqual(lm._caretOffset(at: CGPoint(x: x + 0.5, y: line0.typographicBounds.midY)), 3)
            // Selection segments: one per line, extended over the selected line break.
            var rects: [CGRect] = []
            lm.enumerateTextSegments(in: NSTextRange._make(NSRange(location: 2, length: 48)), type: .selection, options: []) { range, rect, _, container in
                XCTAssertNotNil(range)
                XCTAssertTrue(container === lm.textContainer)
                rects.append(rect)
                return true
            }
            XCTAssertEqual(rects.count, first.textLineFragments.count + 1)
            XCTAssertGreaterThanOrEqual(rects[first.textLineFragments.count - 1].maxX, 114.5, "a selected line break reaches the container's edge")
            // A caret segment is caret-wide at the character.
            var caret = CGRect.null
            lm.enumerateTextSegments(in: NSTextRange(location: _NSTextIndexLocation(3)), type: .selection, options: []) { _, r, _, _ in caret = r; return false }
            XCTAssertEqual(caret.width, 1)
            XCTAssertEqual(caret.minX, x, accuracy: 0.001)
            // Invalidation returns fragments to estimates; enumeration lays them out again.
            lm.invalidateLayout(for: lm.documentRange)
            XCTAssertNotEqual(first.state, .layoutAvailable)
            XCTAssertNotNil(lm.enumerateTextLayoutFragments(from: nil, options: .ensuresLayout) { _ in true })
            XCTAssertEqual(first.state, .layoutAvailable)
        }
    }

    private final class Viewport: NSObject, NSTextViewportLayoutControllerDelegate {
        var bounds: CGRect
        var configured: [NSTextLayoutFragment] = []
        var will = 0, did = 0
        init(_ bounds: CGRect) { self.bounds = bounds }
        func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect { bounds }
        func textViewportLayoutController(_ textViewportLayoutController: NSTextViewportLayoutController, configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment) {
            configured.append(textLayoutFragment)
        }
        func textViewportLayoutControllerWillLayout(_ textViewportLayoutController: NSTextViewportLayoutController) { will += 1 }
        func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) { did += 1 }
    }

    func testViewportLayoutOnlyCoversTheVisibleRange() {
        MainActor.assumeIsolated {
            let text = (0..<300).map { "Paragraph \($0) has a few words in it to wrap." }.joined(separator: "\n")
            let (cs, lm, _) = textKit2(text, width: 160)
            defer { _ = cs }
            let viewport = Viewport(CGRect(x: 0, y: 0, width: 160, height: 120))
            let controller = lm.textViewportLayoutController
            controller.delegate = viewport
            controller.layoutViewport()
            XCTAssertEqual(viewport.will, 1)
            XCTAssertEqual(viewport.did, 1)
            XCTAssertFalse(viewport.configured.isEmpty)
            var laid = 0, estimated = 0
            _ = lm.enumerateTextLayoutFragments(from: nil, options: []) { f in
                if f.state == .layoutAvailable { laid += 1 } else { estimated += 1 }
                return true
            }
            XCTAssertEqual(laid, viewport.configured.count, "only the fragments in the viewport are laid out")
            XCTAssertGreaterThan(estimated, 250)
            for f in viewport.configured { XCTAssertTrue(f.layoutFragmentFrame.intersects(viewport.bounds)) }
            let range = controller.viewportRange!._nsRange!
            XCTAssertEqual(range.location, 0)
            XCTAssertLessThan(range.length, (text as NSString).length / 10)
            // Scrolling down lays out the new viewport only.
            viewport.configured = []
            viewport.bounds = CGRect(x: 0, y: 2000, width: 160, height: 120)
            controller.layoutViewport()
            XCTAssertFalse(viewport.configured.isEmpty)
            for f in viewport.configured { XCTAssertTrue(f.layoutFragmentFrame.intersects(viewport.bounds), "\(f.layoutFragmentFrame)") }
            XCTAssertGreaterThan(controller.viewportRange!._nsRange!.location, 0)
            let total = lm.usageBoundsForTextContainer.height
            XCTAssertGreaterThan(total, 2000)
        }
    }

    // MARK: Selection navigation

    @MainActor private func move(_ lm: NSTextLayoutManager, _ caret: Int, _ dir: NSTextSelectionNavigation.Direction, _ dest: NSTextSelectionNavigation.Destination, extending: Bool = false, from selection: NSTextSelection? = nil) -> NSTextSelection {
        let sel = selection ?? NSTextSelection(_NSTextIndexLocation(caret), affinity: .downstream)
        return lm.textSelectionNavigation.destinationSelection(for: sel, direction: dir, destination: dest, extending: extending, confined: false)!
    }

    func testSelectionNavigationByWordLineAndParagraph() {
        MainActor.assumeIsolated {
            let text = "Hello brave new world, this line wraps around.\nSecond paragraph.\nThird."
            let (cs, lm, _) = textKit2(text, width: 130)
            defer { _ = cs }
            func caret(_ s: NSTextSelection) -> Int { s.textRanges[0]._nsRange!.location }
            // Characters and words.
            XCTAssertEqual(caret(move(lm, 0, .forward, .character)), 1)
            XCTAssertEqual(caret(move(lm, 0, .right, .word)), 5)
            XCTAssertEqual(caret(move(lm, 5, .right, .word)), 11)
            XCTAssertEqual(caret(move(lm, 13, .left, .word)), 12)
            XCTAssertEqual(caret(move(lm, 12, .left, .word)), 6)
            // A range collapses to its edge first.
            let range = NSTextSelection(range: NSTextRange._make(NSRange(location: 2, length: 5)), affinity: .downstream, granularity: .character)
            XCTAssertEqual(caret(move(lm, 0, .left, .character, from: range)), 2)
            XCTAssertEqual(caret(move(lm, 0, .right, .character, from: range)), 7)
            // Extending keeps the anchor.
            let ext = move(lm, 6, .right, .word, extending: true)
            XCTAssertEqual(ext.textRanges[0]._nsRange, NSRange(location: 6, length: 5))
            let ext2 = move(lm, 0, .right, .word, extending: true, from: ext)
            XCTAssertEqual(ext2.textRanges[0]._nsRange, NSRange(location: 6, length: 9))
            let back = move(lm, 0, .left, .character, extending: true, from: NSTextSelection(_NSTextIndexLocation(6), affinity: .downstream))
            XCTAssertEqual(back.textRanges[0]._nsRange, NSRange(location: 5, length: 1))

            // Lines: the first paragraph wraps; the end of a line is upstream of the wrap.
            let fragment = lm.textLayoutFragment(for: _NSTextIndexLocation(0))!
            let lines = fragment.textLineFragments
            XCTAssertGreaterThan(lines.count, 2)
            let lineEnd = move(lm, 2, .forward, .line)
            XCTAssertEqual(caret(lineEnd), lines[0].characterRange.length)
            XCTAssertEqual(lineEnd.affinity, .upstream)
            XCTAssertEqual(caret(move(lm, 0, .backward, .line, from: lineEnd)), 0, "the start of the line the upstream caret is on")
            // Down keeps the x; a second move down reuses the anchor position.
            let down = move(lm, 3, .down, .line)
            XCTAssertTrue(NSLocationInRange(caret(down), NSRange(location: lines[1].characterRange.location, length: lines[1].characterRange.length)))
            let down2 = move(lm, 0, .down, .line, from: down)
            XCTAssertEqual(down2.anchorPositionOffset, down.anchorPositionOffset)
            XCTAssertTrue(NSLocationInRange(caret(down2), NSRange(location: lines[2].characterRange.location, length: lines[2].characterRange.length + 1)))
            XCTAssertEqual(caret(move(lm, 2, .up, .line)), 0, "up from the first line goes to the start")
            let length = (text as NSString).length
            XCTAssertEqual(caret(move(lm, length - 2, .down, .line)), length, "down from the last line goes to the end")

            // Paragraphs: to the end of this one, then the next.
            let p1 = (text as NSString).range(of: "\n").location
            XCTAssertEqual(caret(move(lm, 3, .forward, .paragraph)), p1)
            XCTAssertEqual(caret(move(lm, p1, .forward, .paragraph)), (text as NSString).range(of: "\nThird").location)
            XCTAssertEqual(caret(move(lm, p1 + 3, .backward, .paragraph)), p1 + 1)
            XCTAssertEqual(caret(move(lm, p1 + 1, .backward, .paragraph)), 0)
            // Document.
            XCTAssertEqual(caret(move(lm, 9, .forward, .document)), length)
            XCTAssertEqual(caret(move(lm, 9, .backward, .document)), 0)

            // Deletion ranges.
            let nav = lm.textSelectionNavigation
            XCTAssertEqual(nav.deletionRanges(for: NSTextSelection(_NSTextIndexLocation(11), affinity: .downstream), direction: .backward, destination: .word, allowsDecomposition: false).first?._nsRange, NSRange(location: 6, length: 5))
            XCTAssertEqual(nav.deletionRanges(for: NSTextSelection(_NSTextIndexLocation(0), affinity: .downstream), direction: .forward, destination: .character, allowsDecomposition: false).first?._nsRange, NSRange(location: 0, length: 1))
            XCTAssertTrue(nav.deletionRanges(for: NSTextSelection(_NSTextIndexLocation(0), affinity: .downstream), direction: .backward, destination: .character, allowsDecomposition: true).isEmpty)

            // Granularity: a word and a paragraph around a selection.
            let wordSel = nav.textSelection(for: .word, enclosing: NSTextSelection(_NSTextIndexLocation(8), affinity: .downstream))
            XCTAssertEqual(wordSel.textRanges[0]._nsRange, NSRange(location: 6, length: 5))
            let paraSel = nav.textSelection(for: .paragraph, enclosing: NSTextSelection(_NSTextIndexLocation(p1 + 3), affinity: .downstream))
            XCTAssertEqual(paraSel.textRanges[0]._nsRange, NSRange(location: p1 + 1, length: 18))
        }
    }

    func testSelectionsInteractingAtPoints() {
        MainActor.assumeIsolated {
            let (cs, lm, _) = textKit2("one two three\nfour five", width: 300)
            defer { _ = cs }
            let nav = lm.textSelectionNavigation
            let f = lm.textLayoutFragment(for: _NSTextIndexLocation(0))!
            let line = f.textLineFragments[0]
            func point(_ i: Int) -> CGPoint { CGPoint(x: line.typographicBounds.minX + line.locationForCharacter(at: i).x + 0.5, y: line.typographicBounds.midY) }
            let click = nav.textSelections(interactingAt: point(4), inContainerAt: lm.documentRange.location, anchors: [], modifiers: [], selecting: false, bounds: .zero)
            XCTAssertEqual(click.first?.textRanges.first?._nsRange, NSRange(location: 4, length: 0))
            let shift = nav.textSelections(interactingAt: point(9), inContainerAt: lm.documentRange.location, anchors: click, modifiers: .extend, selecting: false, bounds: .zero)
            XCTAssertEqual(shift.first?.textRanges.first?._nsRange, NSRange(location: 4, length: 5))
            // A drag from a double-clicked word extends by words.
            let word = nav.textSelection(for: .word, enclosing: point(5), inContainerAt: lm.documentRange.location)!
            XCTAssertEqual(word.textRanges.first?._nsRange, NSRange(location: 4, length: 3))
            let drag = nav.textSelections(interactingAt: point(10), inContainerAt: lm.documentRange.location, anchors: [word], modifiers: [], selecting: true, bounds: .zero)
            XCTAssertEqual(drag.first?.textRanges.first?._nsRange, NSRange(location: 4, length: 9))
            XCTAssertEqual(drag.first?.granularity, .word)
            let para = nav.textSelection(for: .paragraph, enclosing: point(2), inContainerAt: lm.documentRange.location)!
            XCTAssertEqual(para.textRanges.first?._nsRange, NSRange(location: 0, length: 14))
            // Below the text, past the last line's end: the end.
            let below = nav.textSelections(interactingAt: CGPoint(x: 290, y: 500), inContainerAt: lm.documentRange.location, anchors: [], modifiers: [], selecting: false, bounds: .zero)
            XCTAssertEqual(below.first?.textRanges.first?._nsRange?.location, 23)
        }
    }

    func testRenderingAttributes() {
        MainActor.assumeIsolated {
            let (cs, lm, _) = textKit2("abcdefghij")
            lm.addRenderingAttribute(.backgroundColor, value: NSColor.yellow, for: NSTextRange._make(NSRange(location: 2, length: 4)))
            lm.addRenderingAttribute(.spellingState, value: 1, for: NSTextRange._make(NSRange(location: 4, length: 4)))
            var runs: [(NSRange, Int)] = []
            lm.enumerateRenderingAttributes(from: _NSTextIndexLocation(0), reverse: false) { _, attrs, r in runs.append((r._nsRange!, attrs.count)); return true }
            XCTAssertEqual(runs.map(\.0), [NSRange(location: 2, length: 2), NSRange(location: 4, length: 2), NSRange(location: 6, length: 2)])
            XCTAssertEqual(runs.map(\.1), [1, 2, 1])
            lm.removeRenderingAttribute(.backgroundColor, for: lm.documentRange)
            runs = []
            lm.enumerateRenderingAttributes(from: _NSTextIndexLocation(0), reverse: false) { _, attrs, r in runs.append((r._nsRange!, attrs.count)); return true }
            XCTAssertEqual(runs.map(\.0), [NSRange(location: 4, length: 2), NSRange(location: 6, length: 2)])
            // They follow edits before them and go with the text they decorate.
            cs.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 0), with: "XY")
            runs = []
            lm.enumerateRenderingAttributes(from: _NSTextIndexLocation(0), reverse: false) { _, _, r in runs.append((r._nsRange!, 0)); return true }
            XCTAssertEqual(runs.map(\.0), [NSRange(location: 6, length: 2), NSRange(location: 8, length: 2)])
            lm.invalidateRenderingAttributes(for: lm.documentRange)
            runs = []
            lm.enumerateRenderingAttributes(from: _NSTextIndexLocation(0), reverse: false) { _, _, r in runs.append((r._nsRange!, 0)); return true }
            XCTAssertTrue(runs.isEmpty)
            XCTAssertNotNil(NSTextLayoutManager.linkRenderingAttributes[.foregroundColor])
        }
    }

    // MARK: NSTypesetter

    private final class SpacedTypesetter: NSATSTypesetter {
        var paragraphs = 0
        override func paragraphSpacing(beforeGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat { 20 }
        override func beginParagraph() { paragraphs += 1 }
    }

    func testLayoutManagerAsksItsTypesetter() {
        MainActor.assumeIsolated {
            let (ts, lm, _) = textKit1(NSAttributedString(string: "one\ntwo\nthree", attributes: [.font: TextKit2Tests.font]), width: 200)
            XCTAssertTrue(lm.typesetter === NSATSTypesetter.shared)
            XCTAssertTrue(NSTypesetter.sharedSystemTypesetter === NSATSTypesetter.shared)
            let plainSecond = lm.lineFragmentRect(forGlyphAt: 4, effectiveRange: nil).minY
            let spaced = SpacedTypesetter()
            lm.typesetter = spaced
            XCTAssertEqual(lm.lineFragmentRect(forGlyphAt: 4, effectiveRange: nil).minY, plainSecond + 20, accuracy: 0.001)
            XCTAssertEqual(lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY, 0, "no space before the first paragraph")
            XCTAssertEqual(spaced.paragraphs, 3)
            // The convenience surface lays out through the layout manager.
            let laid = spaced.layoutCharacters(in: NSRange(location: 0, length: ts.length), for: lm, maximumNumberOfLineFragments: 2)
            XCTAssertEqual(laid, NSRange(location: 0, length: 8))
            var next = 0
            spaced.layoutGlyphs(in: lm, startingAtGlyphIndex: 4, maxNumberOfLineFragments: 1, nextGlyphIndex: &next)
            XCTAssertEqual(next, 8)
            XCTAssertEqual(spaced.actionForControlCharacter(at: 3), .paragraphBreakAction)
            XCTAssertEqual(spaced.hyphenationFactor, 0)
            let tabStyle = NSMutableParagraphStyle()
            tabStyle.tabStops = [NSTextTab(textAlignment: .left, location: 50, options: [:])]
            tabStyle.defaultTabInterval = 30
            ts.addAttribute(.paragraphStyle, value: tabStyle, range: NSRange(location: 0, length: ts.length))
            lm.ensureLayout(for: lm.textContainers[0])
            XCTAssertEqual(spaced.baselineOffset(in: lm, glyphIndex: 0), lm.location(forGlyphAt: 0).y)
        }
    }

    // MARK: The text view

    /// A TextKit 2 (or 1) text view in a scroll view in a window.
    @MainActor private func textView(textKit2: Bool, size: NSSize = NSSize(width: 300, height: 200)) -> (NSWindow, NSScrollView, NSTextView) {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: size), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.hasVerticalScroller = true
        let tv = NSTextView(usingTextLayoutManager: textKit2)
        tv.frame = NSRect(origin: .zero, size: scroll.contentSize)
        tv.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        w.contentView!.addSubview(scroll)
        return (w, scroll, tv)
    }

    func testTextViewChoosesTextKit2AndFallsBackToTextKit1() {
        MainActor.assumeIsolated {
            let tv = NSTextView(usingTextLayoutManager: true)
            let tlm = tvTextLayoutManager(tv)
            XCTAssertNotNil(tv.textContentStorage)
            XCTAssertTrue(tv.textContentStorage?.textStorage === tv.textStorage)
            XCTAssertTrue(tv.textContainer?.textLayoutManager === tlm)
            XCTAssertTrue(tlm.textContentManager === tv.textContentStorage)
            XCTAssertNil(tv.textContainer?.layoutManager)
            XCTAssertNil(NSTextView(usingTextLayoutManager: false).textLayoutManager)
            if ProcessInfo.processInfo.environment["APPKITWIN_TEXTKIT"] != "2" {
                XCTAssertNil(NSTextView(frame: .zero).textLayoutManager, "the port defaults to TextKit 1")
            }
            // A container with a text layout manager brings TextKit 2 along.
            let own = NSTextContentStorage()
            let ownLayout = NSTextLayoutManager()
            own.addTextLayoutManager(ownLayout)
            let container = NSTextContainer(size: NSSize(width: 200, height: 1000))
            ownLayout.textContainer = container
            let adopted = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100), textContainer: container)
            XCTAssertTrue(adopted.textLayoutManager === ownLayout)
            XCTAssertTrue(adopted.textStorage === own.textStorage)
            adopted.string = "adopted"
            XCTAssertEqual(own.textStorage?.string, "adopted")

            // Asking for the layout manager switches to TextKit 1 for good.
            tv.string = "Some text"
            tv.setSpellingState(1, range: NSRange(location: 0, length: 4))
            let lm = tv.layoutManager
            XCTAssertNotNil(lm)
            XCTAssertNil(tv.textLayoutManager)
            XCTAssertNil(tv.textContentStorage)
            XCTAssertNil(tv.textContainer?.textLayoutManager)
            XCTAssertTrue(lm?.textStorage === tv.textStorage)
            XCTAssertTrue(tv.textContainer?.layoutManager === lm)
            XCTAssertNotNil(lm?.temporaryAttribute(.spellingState, atCharacterIndex: 1, effectiveRange: nil), "spelling marks carry over")
            XCTAssertEqual(lm?.numberOfGlyphs, 9)
            tv.insertText("!")
            XCTAssertEqual(tv.string, "!Some text")

            // Text tables and field editors switch too.
            let tables = NSTextView(usingTextLayoutManager: true)
            tables.string = "cell"
            let table = NSTextTable()
            table.numberOfColumns = 1
            let style = NSMutableParagraphStyle()
            style.textBlocks = [NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)]
            tables.textStorage?.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: 4))
            XCTAssertNil(tables.textLayoutManager, "text tables lay out in TextKit 1")
            let editor = NSTextView(usingTextLayoutManager: true)
            editor.isFieldEditor = true
            XCTAssertNil(editor.textLayoutManager)
        }
    }

    @MainActor private func tvTextLayoutManager(_ tv: NSTextView) -> NSTextLayoutManager {
        guard let tlm = tv.textLayoutManager else { XCTFail("not TextKit 2"); return NSTextLayoutManager() }
        return tlm
    }

    func testTextKit2TypingWrappingAndKeyboardSelection() {
        MainActor.assumeIsolated {
            let (w, _, tv) = textView(textKit2: true, size: NSSize(width: 200, height: 160))
            tv.font = NSFont.systemFont(ofSize: 13)
            w.makeKeyAndOrderFront(nil)
            _ = w.makeFirstResponder(tv)
            tv.insertText("Hello brave new world, this paragraph wraps in the narrow view.")
            tv.insertNewline(nil)
            tv.insertText("Second")
            let tlm = tvTextLayoutManager(tv)
            let text = tv.string as NSString
            XCTAssertEqual(tv.selectedRange(), NSRange(location: text.length, length: 0))
            XCTAssertEqual(tlm.textSelections.first?.textRanges.first?._nsRange, tv.selectedRange(), "the layout manager's selection follows")
            w.contentView?.layoutSubtreeIfNeeded()
            let lines = tv._layoutLines()
            XCTAssertGreaterThan(lines.count, 3, "the first paragraph wraps")
            XCTAssertGreaterThanOrEqual(tv.frame.height, lines.last!.y + tv._lineHeight - 1)

            tv.moveWordLeft(nil)
            XCTAssertEqual(tv.selectedRange().location, text.length - 6)
            tv.moveLeft(nil)
            XCTAssertEqual(tv.selectedRange().location, text.length - 7)
            tv.moveToBeginningOfDocument(nil)
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: 0))
            tv.moveWordRightAndModifySelection(nil)
            tv.moveWordRightAndModifySelection(nil)
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: 11))
            tv.moveLeftAndModifySelection(nil)
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: 10))
            tv.moveRight(nil)
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 10, length: 0))
            // Down keeps the column; to the end of the line; the paragraph.
            let firstLine = lines[0]
            tv.moveDown(nil)
            XCTAssertTrue(NSLocationInRange(tv.selectedRange().location, NSRange(location: lines[1].range.location, length: lines[1].range.length + 1)))
            tv.moveUp(nil)
            XCTAssertEqual(tv.selectedRange().location, 10)
            tv.moveToEndOfLine(nil)
            XCTAssertEqual(tv.selectedRange().location, NSMaxRange(firstLine.range))
            XCTAssertEqual(tv._caretRect(for: tv.selectedRange().location).minY, tv._caretRect(for: 0).minY, accuracy: 0.5, "the end-of-line caret stays on its line")
            tv.moveToBeginningOfLine(nil)
            XCTAssertEqual(tv.selectedRange().location, 0)
            tv.selectParagraph(nil)
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: text.range(of: "\n").location + 1))
            tv.moveToEndOfDocument(nil)
            tv.deleteWordBackward(nil)
            XCTAssertEqual(tv.string.hasSuffix("view.\n"), true)
            tv.deleteBackward(nil)
            XCTAssertTrue(tv.string.hasSuffix("view."))
            tv.moveLeft(nil)
            tv.selectWord(nil)
            XCTAssertEqual(tv.selectedRange(), NSRange(location: (tv.string as NSString).length - 5, length: 4), "the word before the full stop, as a double-click")
            XCTAssertNotNil(tv.textLayoutManager, "still TextKit 2")
        }
    }

    @MainActor private func mouse(_ type: NSEvent.EventType, at p: NSPoint, in tv: NSTextView, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        let inWindow = tv.convert(p, to: nil)
        return NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: flags, timestamp: 0, windowNumber: tv.window!.windowNumber,
                                  context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
    }

    func testTextKit2MouseSelection() {
        MainActor.assumeIsolated {
            let (w, _, tv) = textView(textKit2: true)
            tv.string = "alpha beta gamma\ndelta epsilon"
            w.makeKeyAndOrderFront(nil)
            w.contentView?.layoutSubtreeIfNeeded()
            @MainActor func point(_ i: Int) -> NSPoint { let c = tv._caretRect(for: i); return NSPoint(x: c.minX + 0.5, y: c.midY) }
            tv.mouseDown(with: mouse(.leftMouseDown, at: point(6), in: tv))
            tv.mouseUp(with: mouse(.leftMouseUp, at: point(6), in: tv))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 0))
            tv.mouseDown(with: mouse(.leftMouseDown, at: point(14), in: tv, flags: .shift))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 8))
            // A drag from a click.
            tv.mouseDown(with: mouse(.leftMouseDown, at: point(2), in: tv))
            tv.mouseDragged(with: mouse(.leftMouseDragged, at: point(20), in: tv))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 18))
            tv.mouseUp(with: mouse(.leftMouseUp, at: point(20), in: tv))
            // Double-click selects a word; dragging extends by words. Triple-click: the paragraph.
            tv.mouseDown(with: mouse(.leftMouseDown, at: point(7), in: tv, clicks: 2))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 4))
            tv.mouseDragged(with: mouse(.leftMouseDragged, at: point(13), in: tv))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 10))
            tv.mouseUp(with: mouse(.leftMouseUp, at: point(13), in: tv))
            tv.mouseDown(with: mouse(.leftMouseDown, at: point(20), in: tv, clicks: 3))
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 17, length: 13))
            XCTAssertNotNil(tv.textLayoutManager)
        }
    }

    func testTextKit2ViewportInAScrollView() {
        MainActor.assumeIsolated {
            let (w, scroll, tv) = textView(textKit2: true)
            tv.string = (0..<400).map { "Line \($0) of a long document." }.joined(separator: "\n")
            w.makeKeyAndOrderFront(nil)
            w.display()
            let tlm = tvTextLayoutManager(tv)
            @MainActor func laid() -> [NSTextLayoutFragment] {
                var out: [NSTextLayoutFragment] = []
                _ = tlm.enumerateTextLayoutFragments(from: nil, options: []) { f in if f.state == .layoutAvailable { out.append(f) }; return true }
                return out
            }
            XCTAssertLessThan(laid().count, 40, "only the visible fragments")
            XCTAssertGreaterThan(tv.frame.height, 2000, "the view is as tall as the (estimated) text")
            // Scrolling lays out what comes into view.
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 3000))
            scroll.reflectScrolledClipView(scroll.contentView)
            w.display()
            let visible = tv.visibleRect.offsetBy(dx: -tv.textContainerOrigin.x, dy: -tv.textContainerOrigin.y)
            let shown = laid().filter { $0.layoutFragmentFrame.intersects(visible) }
            XCTAssertFalse(shown.isEmpty)
            let range = tlm.textViewportLayoutController.viewportRange?._nsRange
            XCTAssertNotNil(range)
            XCTAssertGreaterThan(range?.location ?? 0, 1000)
            XCTAssertLessThan(laid().count, 80)
            // Typing keeps the layout it does not touch, and works with estimates above.
            let kept = shown[0]
            let keptTop = kept.layoutFragmentFrame.minY
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            tv.insertText("!")
            w.display()
            XCTAssertTrue(tv.string.hasSuffix("document.!"))
            XCTAssertEqual(kept.state, .layoutAvailable, "an edit elsewhere keeps this fragment's layout")
            XCTAssertEqual(kept.layoutFragmentFrame.minY, keptTop, accuracy: 0.001, "and its place")
        }
    }

    @MainActor private func pngImage(_ size: NSSize) -> Data {
        let image = NSImage(size: size, flipped: false) { r in NSColor.systemBlue.setFill(); NSBezierPath.fill(r); return true }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// ADR-0030's features without leaving TextKit 2: attachments, RTF (lists, links,
    /// highlights), find rects and spelling marks.
    func testTextExtrasUnderTextKit2() {
        MainActor.assumeIsolated {
            let (w, _, tv) = textView(textKit2: true, size: NSSize(width: 400, height: 300))
            tv.isRichText = true
            tv.importsGraphics = true
            tv.usesFindBar = true
            w.makeKeyAndOrderFront(nil)
            let wrapper = FileWrapper(regularFileWithContents: pngImage(NSSize(width: 40, height: 30)))
            wrapper.preferredFilename = "pic.png"
            let text = NSMutableAttributedString(string: "Before ", attributes: [.font: TextKit2Tests.font])
            text.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
            text.append(NSAttributedString(string: " after, with a link.\nOne\nTwo", attributes: [.font: TextKit2Tests.font]))
            text.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 22, length: 4))
            tv.textStorage?.setAttributedString(text)
            tv.setSelectedRange(NSRange(location: text.length - 7, length: 7))
            tv._applyList(markerFormat: .decimal)
            w.display()
            let tlm = tvTextLayoutManager(tv)
            // The attachment occupies one character, raises its line and has a frame.
            let frame = tv._attachmentFrame(at: 7)
            XCTAssertNotNil(frame)
            XCTAssertEqual(frame?.width ?? 0, 40, accuracy: 0.5)
            XCTAssertEqual(frame?.height ?? 0, 30, accuracy: 0.5)
            let fragment = tlm.textLayoutFragment(for: _NSTextIndexLocation(7))!
            XCTAssertGreaterThanOrEqual(fragment.textLineFragments[0].typographicBounds.height, 30)
            // RTF round trip of the view's contents, read back into a TextKit 2 view.
            let st = tv.textStorage!
            let data = _RTFWriter(attributedString: st, range: NSRange(location: 0, length: st.length)).write()!
            let back = _RTFReader(data: data).read()!
            let (_, _, other) = textView(textKit2: true, size: NSSize(width: 400, height: 300))
            other.textStorage?.setAttributedString(back)
            XCTAssertNotNil(other.textLayoutManager, "lists and links stay in TextKit 2")
            XCTAssertNotNil(back.attribute(.link, at: 23, effectiveRange: nil))
            XCTAssertFalse(((back.attribute(.paragraphStyle, at: back.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.textLists ?? []).isEmpty)
            // Find highlights and selections draw from the layout manager's segments.
            let rects = tv._rects(forCharacterRange: NSRange(location: 0, length: 6))
            XCTAssertEqual(rects.count, 1)
            XCTAssertGreaterThan(rects[0].width, 20)
            // Spelling marks are rendering attributes; the context menu finds them.
            tv.setSpellingState(1, range: NSRange(location: 0, length: 6))
            XCTAssertEqual(tv._misspelledWord(at: 2), NSRange(location: 0, length: 6))
            tv.setSpellingState(0, range: NSRange(location: 0, length: 6))
            XCTAssertNil(tv._misspelledWord(at: 2))
            XCTAssertNotNil(tv.textLayoutManager, "nothing here needed TextKit 1")
        }
    }

    /// The same short rich text drawn by both engines: identical pixels.
    func testTextKit2DrawsTheSamePixelsAsTextKit1() throws {
        try requireHostBackend()
        try MainActor.assumeIsolated {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 4
            let text = NSMutableAttributedString(string: "TextEdit under TextKit 2 draws exactly what TextKit 1 draws, wrapped.\n",
                                                 attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: style])
            text.append(NSAttributedString(string: "Bold red and ", attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.systemRed]))
            text.append(NSAttributedString(string: "underlined\tstruck.", attributes: [.font: NSFont.systemFont(ofSize: 13), .underlineStyle: 1, .strikethroughStyle: 1]))
            @MainActor func render(_ textKit2: Bool) throws -> NSBitmapImageRep {
                let (w, _, tv) = textView(textKit2: textKit2, size: NSSize(width: 260, height: 160))
                tv.isRichText = true
                tv.textStorage?.setAttributedString(text)
                tv.setSelectedRange(NSRange(location: 5, length: 9))
                w.display()
                XCTAssertEqual(tv.textLayoutManager != nil, textKit2)
                let rep = try XCTUnwrap(tv.bitmapImageRepForCachingDisplay(in: tv.bounds))
                tv.cacheDisplay(in: tv.bounds, to: rep)
                return rep
            }
            let one = try render(false), two = try render(true)
            XCTAssertEqual(one.pixelsWide, two.pixelsWide)
            XCTAssertEqual(one.pixelsHigh, two.pixelsHigh)
            var differing = 0, inked = 0
            for y in 0..<one.pixelsHigh {
                for x in 0..<one.pixelsWide {
                    let a = one.colorAt(x: x, y: y), b = two.colorAt(x: x, y: y)
                    if let a, a.brightnessComponent < 0.6 { inked += 1 }
                    if a != b { differing += 1 }
                }
            }
            XCTAssertGreaterThan(inked, 200, "text was drawn")
            XCTAssertEqual(differing, 0, "both engines draw the same pixels")
        }
    }
}
