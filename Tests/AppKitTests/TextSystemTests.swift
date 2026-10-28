// The text system: NSTextStorage edits reach the layout manager, which lays paragraphs
// out into a container with CoreText and answers geometry and hit-testing questions.

import XCTest
@testable import AppKit

final class TextSystemTests: XCTestCase, @unchecked Sendable {
    @MainActor private func system(_ text: String, width: CGFloat = 200) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        lm.addTextContainer(container)
        return (storage, lm, container)
    }

    private final class EditSpy: NSObject, NSTextStorageDelegate {
        var processed: [(NSTextStorageEditActions, NSRange, Int)] = []
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            processed.append((editedMask, editedRange, delta))
        }
    }

    func testStorageEditsAreBatchedAndReported() {
        MainActor.assumeIsolated {
            let (storage, lm, _) = system("hello")
            let spy = EditSpy()
            storage.delegate = spy
            storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")
            XCTAssertEqual(storage.string, "hello world")
            XCTAssertEqual(spy.processed.count, 1)
            XCTAssertTrue(spy.processed[0].0.contains(.editedCharacters))
            XCTAssertEqual(spy.processed[0].1, NSRange(location: 5, length: 6))
            XCTAssertEqual(spy.processed[0].2, 6)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 5))
            storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "HELLO")
            XCTAssertEqual(spy.processed.count, 1, "batched until endEditing")
            storage.endEditing()
            XCTAssertEqual(spy.processed.count, 2)
            XCTAssertTrue(spy.processed[1].0.contains(.editedAttributes))
            XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.red)
            XCTAssertEqual(storage.words.count, 2)
            XCTAssertEqual(storage.paragraphs.count, 1)
            XCTAssertTrue(lm.textStorage === storage)
            XCTAssertEqual(lm.numberOfGlyphs, 11)
            storage.removeLayoutManager(lm)
            XCTAssertNil(lm.textStorage)
        }
    }

    func testLayoutWrapsIntoLineFragments() {
        MainActor.assumeIsolated {
            let (storage, lm, container) = system("one two three four five six seven eight nine ten", width: 120)
            let font = NSFont.systemFont(ofSize: 13)
            let lineHeight = lm.defaultLineHeight(for: font)
            var fragments: [NSRange] = []
            lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: storage.length)) { rect, used, c, range, _ in
                XCTAssertTrue(c === container)
                XCTAssertEqual(rect.height, lineHeight, accuracy: 1)
                XCTAssertLessThanOrEqual(used.maxX, 120.5)
                XCTAssertEqual(used.minX, 5, accuracy: 0.01, "line fragment padding")
                fragments.append(range)
            }
            XCTAssertGreaterThan(fragments.count, 2)
            XCTAssertEqual(fragments.first?.location, 0)
            XCTAssertEqual(fragments.last.map { $0.location + $0.length }, storage.length)
            let used = lm.usedRect(for: container)
            XCTAssertEqual(used.height, lineHeight * CGFloat(fragments.count), accuracy: 1)
            XCTAssertEqual(lm.glyphRange(for: container), NSRange(location: 0, length: storage.length))
            // Lines start at words.
            for r in fragments.dropFirst() { XCTAssertNotEqual((storage.string as NSString).character(at: r.location), 0x20) }
            // Widening the container relays out onto fewer lines.
            container.size = NSSize(width: 1000, height: CGFloat.greatestFiniteMagnitude)
            var count = 0
            lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: storage.length)) { _, _, _, _, _ in count += 1 }
            XCTAssertEqual(count, 1)
        }
    }

    func testParagraphsNewlinesAndTheExtraFragment() {
        MainActor.assumeIsolated {
            let (storage, lm, container) = system("first\nsecond\n")
            var ranges: [NSRange] = []
            lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: storage.length)) { _, _, _, r, _ in ranges.append(r) }
            XCTAssertEqual(ranges, [NSRange(location: 0, length: 6), NSRange(location: 6, length: 7)])
            XCTAssertTrue(lm.extraLineFragmentTextContainer === container, "a trailing newline leaves an empty last line")
            XCTAssertGreaterThan(lm.extraLineFragmentRect.minY, lm.lineFragmentRect(forGlyphAt: 6, effectiveRange: nil).minY)
            // The caret after the newline sits on the next line.
            let secondLine = lm.lineFragmentRect(forGlyphAt: 6, effectiveRange: nil)
            XCTAssertGreaterThan(secondLine.minY, 0)
            XCTAssertEqual(lm.location(forGlyphAt: 6).x, 5, accuracy: 0.01)
            // Alignment through a paragraph style.
            let style = NSMutableParagraphStyle()
            style.alignment = .right
            storage.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: 5))
            let right = lm.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
            XCTAssertEqual(right.maxX, 200 - 5, accuracy: 1, "right-aligned to the padded edge")
            XCTAssertEqual(lm.lineFragmentUsedRect(forGlyphAt: 6, effectiveRange: nil).minX, 5, accuracy: 0.01, "the second paragraph keeps its own alignment")
            let empty = NSTextStorage()
            let lm2 = NSLayoutManager()
            empty.addLayoutManager(lm2)
            lm2.addTextContainer(NSTextContainer(size: NSSize(width: 100, height: 100)))
            XCTAssertGreaterThan(lm2.extraLineFragmentRect.height, 5, "empty text still has an insertion line")
        }
    }

    func testHitTestingAndSelectionRects() {
        MainActor.assumeIsolated {
            let (storage, lm, container) = system("abc def\nghi", width: 300)
            let p3 = lm.location(forGlyphAt: 3)
            var fraction: CGFloat = 0
            let hit = lm.characterIndex(for: NSPoint(x: p3.x + 1, y: 2), in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
            XCTAssertEqual(hit, 3)
            XCTAssertLessThan(fraction, 0.5)
            let secondLineY = lm.lineFragmentRect(forGlyphAt: 8, effectiveRange: nil).midY
            XCTAssertEqual(lm.characterIndex(for: NSPoint(x: 0, y: secondLineY), in: container, fractionOfDistanceBetweenInsertionPoints: nil), 8)
            XCTAssertEqual(lm.characterIndex(for: NSPoint(x: 1000, y: secondLineY), in: container, fractionOfDistanceBetweenInsertionPoints: nil) + 1, storage.length)
            // Selection rects: one per line, the first extended to the edge for its newline.
            var rects: [NSRect] = []
            let sel = NSRange(location: 4, length: 6)
            lm.enumerateEnclosingRects(forGlyphRange: sel, withinSelectedGlyphRange: sel, in: container) { r, _ in rects.append(r) }
            XCTAssertEqual(rects.count, 2)
            XCTAssertEqual(rects[0].maxX, 300 - 5, accuracy: 1)
            XCTAssertEqual(rects[1].minX, 5, accuracy: 0.01)
            XCTAssertGreaterThan(rects[1].width, 5)
            let bounds = lm.boundingRect(forGlyphRange: NSRange(location: 0, length: 3), in: container)
            XCTAssertEqual(bounds.minX, 5, accuracy: 0.01)
            XCTAssertGreaterThan(bounds.width, 10)
        }
    }

    func testMixedFontsAndTemporaryAttributes() {
        MainActor.assumeIsolated {
            let (storage, lm, container) = system("small BIG", width: 400)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 30), range: NSRange(location: 6, length: 3))
            let line = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            XCTAssertGreaterThan(line.height, lm.defaultLineHeight(for: NSFont.systemFont(ofSize: 13)) + 10, "the line grows to the larger font")
            let wide = lm.boundingRect(forGlyphRange: NSRange(location: 6, length: 3), in: container).width
            let narrow = lm.boundingRect(forGlyphRange: NSRange(location: 0, length: 3), in: container).width
            XCTAssertGreaterThan(wide, narrow * 1.5)
            lm.addTemporaryAttribute(.underlineStyle, value: 1, forCharacterRange: NSRange(location: 0, length: 5))
            var r = NSRange()
            XCTAssertEqual(lm.temporaryAttribute(.underlineStyle, atCharacterIndex: 2, effectiveRange: &r) as? Int, 1)
            XCTAssertEqual(r, NSRange(location: 0, length: 5))
            XCTAssertNil(lm.temporaryAttribute(.underlineStyle, atCharacterIndex: 7, effectiveRange: nil))
            lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: NSRange(location: 0, length: 9))
            XCTAssertNil(lm.temporaryAttribute(.underlineStyle, atCharacterIndex: 2, effectiveRange: nil))
        }
    }

    func testTextViewUsesItsTextSystem() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            w.contentView!.addSubview(tv)
            tv.string = "Hello text system"
            XCTAssertEqual(tv.textStorage?.string, "Hello text system")
            XCTAssertTrue(tv.layoutManager?.textStorage === tv.textStorage)
            XCTAssertTrue(tv.textContainer?.textView === tv)
            XCTAssertEqual(tv.textContainer?.size.width ?? 0, 200, accuracy: 0.01, "the container tracks the view width")
            tv.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 5), with: "Goodbye")
            XCTAssertEqual(tv.string, "Goodbye text system", "edits to the storage show through the view")
            tv.insertText("!", replacementRange: NSRange(location: tv.string.utf16.count, length: 0))
            XCTAssertEqual(tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, tv.font)
            tv.font = NSFont.systemFont(ofSize: 24)
            XCTAssertEqual((tv.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.pointSize, 24)
            tv.setFrameSize(NSSize(width: 80, height: 100))
            XCTAssertGreaterThan(tv._layoutLines().count, 1, "narrowing the view wraps through the container")
            w.close()
        }
    }
}
