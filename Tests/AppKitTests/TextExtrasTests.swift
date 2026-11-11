// The editor features of the text system (ADR-0030): NSTextFinder and the find bar,
// NSSpellChecker over a known word list, attachments in layout and RTFD, lists and their
// numbering, and table layout.
//
// On macOS the test target also sees Apple's AppKit additions to Foundation types through
// XCTest, so the NSAttributedString members are reached through the port's internals.

import XCTest
@testable import AppKit

final class TextExtrasTests: XCTestCase, @unchecked Sendable {
    @MainActor private func key(_ w: NSWindow, _ chars: String, flags: NSEvent.ModifierFlags = [], plain: String? = nil) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                                 characters: chars, charactersIgnoringModifiers: plain ?? chars, isARepeat: false, keyCode: 0)!
        w.sendEvent(e)
    }

    @MainActor private func window(rich: Bool = true, text: String = "") -> (NSWindow, NSScrollView, NSTextView) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSTextView._scrollable(rich: rich)
        scroll.frame = w.contentView!.bounds
        w.contentView!.addSubview(scroll)
        let tv = scroll.documentView as! NSTextView
        tv.string = text
        w.makeKeyAndOrderFront(nil)
        _ = w.makeFirstResponder(tv)
        return (w, scroll, tv)
    }

    private func attachmentString(_ a: NSTextAttachment, font: NSFont? = nil) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key("NSAttachment"): a]
        if let font { attrs[NSAttributedString.Key("NSFont")] = font }
        return NSAttributedString(string: "\u{FFFC}", attributes: attrs)
    }

    @MainActor private func pngImage(_ size: NSSize) -> Data {
        let image = NSImage(size: size, flipped: false) { r in NSColor.systemBlue.setFill(); NSBezierPath.fill(r); return true }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    // MARK: Find

    func testFinderMatchingOptions() {
        let text = "Cat catalog concat cat. CAT" as NSString
        XCTAssertEqual(NSTextFinder._matches(of: "cat", in: text, ignoringCase: true, matching: .contains).count, 5)
        XCTAssertEqual(NSTextFinder._matches(of: "cat", in: text, ignoringCase: false, matching: .contains).count, 3)
        XCTAssertEqual(NSTextFinder._matches(of: "cat", in: text, ignoringCase: true, matching: .fullWord).map(\.location), [0, 19, 24])
        XCTAssertEqual(NSTextFinder._matches(of: "cat", in: text, ignoringCase: true, matching: .startsWith).map(\.location), [0, 4, 19, 24])
        XCTAssertEqual(NSTextFinder._matches(of: "cat", in: text, ignoringCase: true, matching: .endsWith).map(\.location), [0, 15, 19, 24])
    }

    func testFindBarShowsInScrollViewAndFindsNextAndPrevious() {
        MainActor.assumeIsolated {
            let (_, scroll, tv) = window(text: "one two one three one")
            tv.isIncrementalSearchingEnabled = true
            let contentBefore = scroll.contentView.frame
            let item = NSMenuItem(title: "Find…", action: Selector(("performFindPanelAction:")), keyEquivalent: "f")
            item.tag = NSFindPanelAction.showFindPanel.rawValue
            tv.performFindPanelAction(item)
            XCTAssertTrue(scroll.isFindBarVisible)
            let bar = try! XCTUnwrap(scroll.findBarView as? _NSFindBarView)
            XCTAssertTrue(bar.superview === scroll)
            XCTAssertLessThan(scroll.contentView.frame.height, contentBefore.height, "the bar takes room from the content")
            // Typing the search string selects the first match (incremental search).
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            bar.searchField.stringValue = "one"
            bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.searchField))
            XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 3))
            XCTAssertEqual(tv._finder?.incrementalMatchRanges.map(\.rangeValue), [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3), NSRange(location: 18, length: 3)])
            let next = NSMenuItem(title: "Find Next", action: Selector(("performFindPanelAction:")), keyEquivalent: "g")
            next.tag = NSFindPanelAction.next.rawValue
            tv.performFindPanelAction(next)
            XCTAssertEqual(tv.selectedRange, NSRange(location: 8, length: 3))
            tv.performFindPanelAction(next)
            tv.performFindPanelAction(next)
            XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 3), "wraps around")
            let previous = NSMenuItem(title: "Find Previous", action: nil, keyEquivalent: "")
            previous.tag = NSFindPanelAction.previous.rawValue
            tv.performFindPanelAction(previous)
            XCTAssertEqual(tv.selectedRange, NSRange(location: 18, length: 3))
            XCTAssertEqual(tv._finder?._status, "3 of 3")
            // Done hides the bar and gives the content its room back.
            tv._finder?.performAction(.hideFindInterface)
            XCTAssertFalse(scroll.isFindBarVisible)
            XCTAssertNil(bar.superview)
            XCTAssertEqual(scroll.contentView.frame.height, contentBefore.height)
        }
    }

    func testFindBarReplaceAndReplaceAll() {
        MainActor.assumeIsolated {
            let (_, scroll, tv) = window(text: "red fish, blue fish, Fish")
            let finder = tv._makeFinderIfNeeded()
            finder.performAction(.showReplaceInterface)
            XCTAssertTrue(scroll.isFindBarVisible)
            finder._searchStringChanged("fish", anchor: 0)
            finder._replaceString = "cat"
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            finder.performAction(.nextMatch)
            XCTAssertEqual(tv.selectedRange, NSRange(location: 4, length: 4))
            finder.performAction(.replaceAndFind)
            XCTAssertEqual(tv.string, "red cat, blue fish, Fish")
            XCTAssertEqual(tv.selectedRange, NSRange(location: 14, length: 4), "the next match is selected")
            finder.performAction(.replaceAll)
            XCTAssertEqual(tv.string, "red cat, blue cat, cat", "case-insensitive by default")
            // Full-word matching leaves "catalog" alone.
            tv.string = "cat catalog cat"
            finder._matchingType = .fullWord
            finder._searchStringChanged("cat", anchor: 0)
            finder._replaceString = "dog"
            finder.performAction(.replaceAll)
            XCTAssertEqual(tv.string, "dog catalog dog")
            // Set Search String takes the selection.
            tv.setSelectedRange(NSRange(location: 4, length: 7))
            finder.performAction(.setSearchString)
            XCTAssertEqual(finder._searchString, "catalog")
        }
    }

    // MARK: Spelling

    /// A checker that knows only these words, as CI machines may have no system dictionary.
    private func knownWords() -> _NSWordListSpellChecker {
        _NSWordListSpellChecker(words: ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "receive", "separate", "a"], usesSystemWords: false)
    }

    func testSpellCheckerFindsMisspellingsAndGuesses() {
        MainActor.assumeIsolated {
            let checker = NSSpellChecker.shared
            let saved = checker._engine
            defer { checker._engine = saved }
            checker._engine = knownWords()
            let text = "The quick brwon fox jumps over teh lazy dog"
            let first = checker.checkSpelling(of: text, startingAt: 0)
            XCTAssertEqual((text as NSString).substring(with: first), "brwon")
            let second = checker.checkSpelling(of: text, startingAt: NSMaxRange(first))
            XCTAssertEqual((text as NSString).substring(with: second), "teh")
            let none = checker.checkSpelling(of: text, startingAt: NSMaxRange(second))
            XCTAssertEqual(none.location, NSNotFound)
            let wrapped = checker.checkSpelling(of: text, startingAt: NSMaxRange(second), language: nil, wrap: true, inSpellDocumentWithTag: 0, wordCount: nil)
            XCTAssertEqual(wrapped, first)
            XCTAssertEqual(checker.guesses(forWordRange: first, in: text, language: nil, inSpellDocumentWithTag: 0)?.first, "brown")
            XCTAssertEqual(checker.guesses(forWordRange: second, in: text, language: nil, inSpellDocumentWithTag: 0)?.first, "the")
            XCTAssertEqual(checker.correction(forWordRange: second, in: text, language: "en", inSpellDocumentWithTag: 0), "the")
            XCTAssertEqual(checker.countWords(in: text, language: nil), 9)
            // Ignoring is per document; learning is global.
            let tag = NSSpellChecker.uniqueSpellDocumentTag()
            checker.ignoreWord("brwon", inSpellDocumentWithTag: tag)
            let r = checker.checkSpelling(of: text, startingAt: 0, language: nil, wrap: false, inSpellDocumentWithTag: tag, wordCount: nil)
            XCTAssertEqual((text as NSString).substring(with: r), "teh")
            XCTAssertEqual(checker.ignoredWords(inSpellDocumentWithTag: tag), ["brwon"])
            checker.closeSpellDocument(withTag: tag)
            XCTAssertNil(checker.ignoredWords(inSpellDocumentWithTag: tag))
            checker.learnWord("teh")
            XCTAssertTrue(checker.hasLearnedWord("teh"))
            XCTAssertEqual(checker.checkSpelling(of: "teh", startingAt: 0).location, NSNotFound)
            checker.unlearnWord("teh")
            XCTAssertFalse(checker.hasLearnedWord("teh"))
            // Completions: the list, shortest first, in the partial word's case.
            checker._engine = _NSWordListSpellChecker(words: ["separate", "separately", "sepal", "seven"], usesSystemWords: false)
            let completions = checker.completions(forPartialWordRange: NSRange(location: 0, length: 3), in: "Sep", language: nil, inSpellDocumentWithTag: 0)
            XCTAssertEqual(completions, ["Sepal", "Separate", "Separately"])
            // The built-in list: common words and inflections pass.
            let builtIn = _NSWordListSpellChecker(usesSystemWords: false)
            XCTAssertTrue(builtIn.isCorrect("documents"))
            XCTAssertTrue(builtIn.isCorrect("Running"))
            XCTAssertFalse(builtIn.isCorrect("documnet"))
        }
    }

    /// The operating system's checker (hunspell with an English dictionary, the Windows
    /// Spell Checking API), where the machine has one.
    func testSystemSpellCheckerWhenPresent() throws {
        guard let system = PlatformSpellChecking.makeSystemChecker() else { throw XCTSkip("no system spell checker on this machine") }
        guard system.availableLanguages.contains(where: { $0.hasPrefix("en") }), system.language.hasPrefix("en") || system.setLanguage("en_US") else {
            throw XCTSkip("no English dictionary (\(system.availableLanguages))")
        }
        // A checker that rejects the commonest words is not usable here (a CI runner's
        // service may answer without a working dictionary); the word-list path covers CI.
        guard ["the", "house", "receive", "separate"].allSatisfy(system.isCorrect) else { throw XCTSkip("the \(system.name) checker rejects common words on this machine") }
        XCTAssertTrue(system.isCorrect("receive"), system.name)
        XCTAssertFalse(system.isCorrect("recieve"), system.name)
        XCTAssertTrue(system.guesses(for: "recieve").contains("receive"), "\(system.guesses(for: "recieve"))")
        system.learn("frobnicate")
        XCTAssertTrue(system.isCorrect("frobnicate"))
    }

    func testContinuousSpellCheckingMarksAndContextMenu() {
        MainActor.assumeIsolated {
            let checker = NSSpellChecker.shared
            let saved = checker._engine
            defer { checker._engine = saved }
            checker._engine = knownWords()
            let (w, _, tv) = window(text: "the quick brwon fox")
            tv.isContinuousSpellCheckingEnabled = true
            let lm = tv.layoutManager!
            var r = NSRange(location: 0, length: 0)
            XCTAssertEqual((lm.temporaryAttribute(.spellingState, atCharacterIndex: 11, effectiveRange: &r) as? NSNumber)?.intValue, 1)
            XCTAssertEqual(r, NSRange(location: 10, length: 5))
            XCTAssertNil(lm.temporaryAttribute(.spellingState, atCharacterIndex: 4, effectiveRange: nil))
            // The context menu on the word offers the guess first, then Ignore and Learn.
            let p = tv.convert(tv._caretRect(for: 12).origin.applying(CGAffineTransform(translationX: 1, y: 3)), to: nil)
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            let menu = tv.menu(for: event)!
            XCTAssertEqual(menu.items.first?.title, "brown")
            XCTAssertTrue(menu.items.contains { $0.title == "Ignore Spelling" })
            XCTAssertTrue(menu.items.contains { $0.title == "Learn Spelling" })
            XCTAssertEqual(tv.selectedRange, NSRange(location: 10, length: 5), "the word is selected")
            tv.changeSpelling(menu.items.first)
            XCTAssertEqual(tv.string, "the quick brown fox")
            XCTAssertNil(lm.temporaryAttribute(.spellingState, atCharacterIndex: 11, effectiveRange: nil))
            // Check Spelling selects the next misspelling.
            tv.string = "teh dog"
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.checkSpelling(nil)
            XCTAssertEqual(tv.selectedRange, NSRange(location: 0, length: 3))
            tv.ignoreSpelling(nil)
            tv.isContinuousSpellCheckingEnabled = false
            XCTAssertNil(lm.temporaryAttribute(.spellingState, atCharacterIndex: 0, effectiveRange: nil))
        }
    }

    // MARK: Attachments

    func testAttachmentLaysOutAsOneGlyphAndRaisesTheLine() {
        MainActor.assumeIsolated {
            let font = NSFont.systemFont(ofSize: 13)
            let storage = NSTextStorage(string: "ab", attributes: [.font: font])
            let a = NSTextAttachment(data: nil, ofType: nil)
            a.bounds = CGRect(x: 0, y: 0, width: 40, height: 30)
            storage.insert(attachmentString(a, font: font), at: 1)
            let lm = NSLayoutManager()
            storage.addLayoutManager(lm)
            let container = NSTextContainer(size: NSSize(width: 400, height: 1000))
            lm.addTextContainer(container)
            XCTAssertEqual(storage.string, "a\u{FFFC}b")
            // The attachment is 40 wide: "b" starts 40 points after it.
            let x1 = lm.location(forGlyphAt: 1).x, x2 = lm.location(forGlyphAt: 2).x
            XCTAssertEqual(x2 - x1, 40, accuracy: 0.5)
            XCTAssertEqual(lm.attachmentSize(forGlyphAt: 1), NSSize(width: 40, height: 30))
            // The line is at least as tall as the attachment above the baseline.
            let line = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            XCTAssertGreaterThanOrEqual(line.height, 30)
            let rect = lm._attachmentRect(at: 1)!
            XCTAssertEqual(rect.size, NSSize(width: 40, height: 30))
            XCTAssertEqual(rect.maxY, line.minY + lm.location(forGlyphAt: 1).y, accuracy: 0.5, "sits on the baseline")
            // A cell decides its own size.
            let cell = NSTextAttachmentCell(imageCell: NSImage(size: NSSize(width: 12, height: 20)))
            a.attachmentCell = cell
            lm.invalidateLayout(forCharacterRange: NSRange(location: 0, length: 3), actualCharacterRange: nil)
            XCTAssertEqual(lm.attachmentSize(forGlyphAt: 1), NSSize(width: 12, height: 20))
            XCTAssertTrue(cell.attachment === a)
            XCTAssertEqual(cell.cellSize(), NSSize(width: 12, height: 20))
        }
    }

    func testAttachmentSelectionAndDeletionAreOneCharacter() {
        MainActor.assumeIsolated {
            let (w, _, tv) = window()
            tv.string = "xy"
            let a = NSTextAttachment(data: pngImage(NSSize(width: 16, height: 16)), ofType: "public.png")
            tv.setSelectedRange(NSRange(location: 1, length: 0))
            tv.insertText(attachmentString(a, font: NSFont.systemFont(ofSize: 13)), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(tv.string, "x\u{FFFC}y")
            XCTAssertEqual(tv.selectedRange, NSRange(location: 2, length: 0))
            XCTAssertEqual(tv.layoutManager!.attachmentSize(forGlyphAt: 1), NSSize(width: 16, height: 16), "the image's size")
            key(w, "\u{F702}")                         // left: over the attachment in one step
            XCTAssertEqual(tv.selectedRange, NSRange(location: 1, length: 0))
            key(w, "\u{F703}", flags: .shift)           // select it
            XCTAssertEqual(tv.selectedRange, NSRange(location: 1, length: 1))
            key(w, "\u{7F}")                           // delete removes it whole
            XCTAssertEqual(tv.string, "xy")
        }
    }

    func testPastingAnImageMakesAnAttachment() {
        MainActor.assumeIsolated {
            let (_, _, tv) = window(text: "ab")
            let paste = NSMenuItem(title: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
            let pb = NSPasteboard.general
            _ = pb.clearContents()
            XCTAssertFalse(tv.validateMenuItem(paste), "nothing to paste")
            // A bitmap as Windows puts it on the clipboard (CF_DIB), read as a BMP file.
            var dib = Data()
            func le(_ v: Int, _ n: Int) { for k in 0..<n { dib.append(UInt8((v >> (8 * k)) & 0xFF)) } }
            le(40, 4); le(2, 4); le(1, 4); le(1, 2); le(32, 2); le(0, 4); le(8, 4); le(0, 4); le(0, 4); le(0, 4); le(0, 4)
            dib.append(contentsOf: [0, 0, 255, 255, 255, 0, 0, 255])        // one red, one blue pixel (BGRA)
            let bmp = PlatformClipboardImage.bmpFile(fromDIB: dib)!
            XCTAssertEqual(Array(bmp.prefix(2)), [0x42, 0x4D])
            XCTAssertEqual(bmp.count, 14 + dib.count)
            XCTAssertEqual(Int(bmp[10]), 54, "pixels right after the 40-byte header")
            XCTAssertEqual(NSImage(data: bmp)?.size, NSSize(width: 2, height: 1))
            _ = pb.setData(bmp, forType: NSTextView._bmpType)
            XCTAssertTrue(tv.validateMenuItem(paste), "an image pastes into rich text")
            tv.setSelectedRange(NSRange(location: 1, length: 0))
            tv.paste(nil)
            XCTAssertEqual(tv.string, "a\u{FFFC}b")
            let a = tv.textStorage?.attribute(NSAttributedString.Key("NSAttachment"), at: 1, effectiveRange: nil) as? NSTextAttachment
            XCTAssertEqual(a?.fileWrapper?.preferredFilename, "Pasted Graphic.bmp")
            XCTAssertEqual(tv.layoutManager?.attachmentSize(forGlyphAt: 1), NSSize(width: 2, height: 1))
            // Plain text views take no images.
            tv.isRichText = false
            tv.importsGraphics = false
            XCTAssertFalse(tv.validateMenuItem(paste))
            _ = pb.clearContents()
        }
    }

    func testRTFDRoundTripKeepsAttachments() {
        MainActor.assumeIsolated {
            let png = pngImage(NSSize(width: 20, height: 10))
            let wrapper = FileWrapper(regularFileWithContents: png)
            wrapper.preferredFilename = "dot.png"
            let text = NSMutableAttributedString(string: "Before  after\n", attributes: [.font: NSFont.systemFont(ofSize: 12)])
            text.insert(attachmentString(NSTextAttachment(fileWrapper: wrapper), font: NSFont.systemFont(ofSize: 12)), at: 7)
            var writer = _RTFWriter(attributedString: text, range: NSRange(location: 0, length: text.length))
            writer.writesAttachments = true
            let rtf = writer.write()!
            let source = String(decoding: rtf, as: UTF8.self)
            XCTAssertTrue(source.contains("\\NeXTGraphic dot.png \\width400 \\height200"), source)
            XCTAssertEqual(writer.attachmentFiles.map(\.0), ["dot.png"])
            // Plain RTF leaves attachments out.
            let plain = String(decoding: _RTFWriter(attributedString: text, range: NSRange(location: 0, length: text.length)).write()!, as: UTF8.self)
            XCTAssertFalse(plain.contains("NeXTGraphic"))
            // Directory and flat RTFD.
            let directory = FileWrapper(directoryWithFileWrappers: ["TXT.rtf": FileWrapper(regularFileWithContents: rtf), "dot.png": FileWrapper(regularFileWithContents: png)])
            let back = _RTFReader.readRTFD(directory)!
            XCTAssertEqual(back.string, text.string)
            let attachment = back.attribute(NSAttributedString.Key("NSAttachment"), at: 7, effectiveRange: nil) as? NSTextAttachment
            XCTAssertEqual(attachment?.fileWrapper?.regularFileContents, png)
            XCTAssertEqual(attachment?.fileWrapper?.preferredFilename, "dot.png")
            let flat = _RTFDArchive.archive(directory)
            let unflat = _RTFDArchive.unarchive(flat)!
            XCTAssertEqual(unflat.fileWrappers?["dot.png"]?.regularFileContents, png)
            XCTAssertEqual(_RTFReader.readRTFD(unflat)?.string, text.string)
        }
    }

    // MARK: Lists

    func testListMarkers() {
        let decimal = NSTextList(markerFormat: NSTextList.MarkerFormat("{decimal}."), options: [], startingItemNumber: 1)
        XCTAssertEqual(decimal.marker(forItemNumber: 3), "3.")
        XCTAssertTrue(decimal.isOrdered)
        XCTAssertEqual(NSTextList(markerFormat: .disc, options: 0).marker(forItemNumber: 7), "\u{2022}")
        XCTAssertFalse(NSTextList(markerFormat: .disc, options: 0).isOrdered)
        XCTAssertEqual(NSTextList(markerFormat: .lowercaseAlpha, options: 0).marker(forItemNumber: 28), "ab")
        XCTAssertEqual(NSTextList(markerFormat: .uppercaseRoman, options: 0).marker(forItemNumber: 1994), "MCMXCIV")
        XCTAssertEqual(NSTextList(markerFormat: NSTextList.MarkerFormat("({lower-roman})"), options: 0).marker(forItemNumber: 4), "(iv)")
        XCTAssertEqual(NSTextList(markerFormat: .uppercaseHexadecimal, options: 0).marker(forItemNumber: 255), "FF")
        let copy = decimal.copy() as! NSTextList
        XCTAssertEqual(copy.markerFormat, decimal.markerFormat)
        XCTAssertFalse(copy === decimal)
    }

    func testListEditingNumbersAndNests() {
        MainActor.assumeIsolated {
            let (w, _, tv) = window()
            tv.string = "Apples"
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv._applyList(markerFormat: NSTextList.MarkerFormat("{decimal}."))
            XCTAssertEqual(tv.string, "\t1.\tApples")
            let style = tv._paragraphStyle(at: 0)!
            XCTAssertEqual(style.textLists.count, 1)
            XCTAssertEqual(style.headIndent, 36)
            XCTAssertEqual(style.tabStops.map(\.location), [11, 36])
            // Return continues the list.
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            key(w, "\r")
            for c in "Pears" { key(w, String(c)) }
            XCTAssertEqual(tv.string, "\t1.\tApples\n\t2.\tPears")
            // Tab at the start of the item's text nests it, and numbering restarts inside.
            let pearsStart = ("\t1.\tApples\n\t2.\t" as NSString).length
            tv.setSelectedRange(NSRange(location: pearsStart, length: 0))
            key(w, "\t")
            XCTAssertEqual(tv.string, "\t1.\tApples\n\ta.\tPears")
            XCTAssertEqual(tv._paragraphStyle(at: tv.selectedRange.location)!.textLists.count, 2)
            XCTAssertEqual(tv._paragraphStyle(at: tv.selectedRange.location)!.headIndent, 72)
            // Shift-Tab brings it back.
            key(w, "\u{19}", flags: .shift, plain: "\t")
            XCTAssertEqual(tv.string, "\t1.\tApples\n\t2.\tPears")
            // Return on an empty item ends the list.
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            key(w, "\r")
            XCTAssertEqual(tv.string, "\t1.\tApples\n\t2.\tPears\n\t3.\t")
            key(w, "\r")
            XCTAssertEqual(tv.string, "\t1.\tApples\n\t2.\tPears\n")
            XCTAssertTrue(tv._paragraphStyle(at: (tv.string as NSString).length)?.textLists.isEmpty ?? true)
            key(w, "x")
            XCTAssertTrue(tv._paragraphStyle(at: (tv.string as NSString).length - 1)?.textLists.isEmpty ?? true, "typing after the list is plain")
            XCTAssertEqual(tv._paragraphStyle(at: (tv.string as NSString).length - 1)?.headIndent ?? 0, 0)
            // Item numbers through the attributed string.
            let list = tv._paragraphStyle(at: 0)!.textLists[0]
            XCTAssertEqual(tv.textStorage!.itemNumber(in: list, at: 13), 2)
            XCTAssertEqual(tv.textStorage!.range(of: list, at: 0), NSRange(location: 0, length: 21))
            _ = w
        }
    }

    func testListsAndTablesSurviveRTF() {
        MainActor.assumeIsolated {
            let (_, _, tv) = window()
            tv.string = "One\nTwo"
            tv.setSelectedRange(NSRange(location: 0, length: 7))
            tv._applyList(markerFormat: .disc)
            let st = tv.textStorage!
            let data = _RTFWriter(attributedString: st, range: NSRange(location: 0, length: st.length)).write()!
            let source = String(decoding: data, as: UTF8.self)
            XCTAssertTrue(source.contains("\\listtable"))
            XCTAssertTrue(source.contains("\\ls1\\ilvl0"))
            let back = _RTFReader(data: data).read()!
            XCTAssertEqual(back.string, st.string)
            let lists0 = (back.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textLists ?? []
            let lists1 = (back.attribute(.paragraphStyle, at: back.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.textLists ?? []
            XCTAssertEqual(lists0.first?.markerFormat, .disc)
            XCTAssertTrue(lists0.first === lists1.first, "one list across both paragraphs")
            XCTAssertEqual((back.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent, 36)
            // A 2×2 table.
            tv.string = ""
            tv._insertTable(rows: 2, columns: 2)
            for (i, word) in ["a1", "b1", "a2", "b2"].enumerated() {
                let cells = cellRanges(tv.textStorage!)
                tv.setSelectedRange(NSRange(location: cells[i].location, length: 0))
                tv.insertText(word)
            }
            let t = tv.textStorage!
            XCTAssertEqual(t.string, "a1\nb1\na2\nb2\n")
            let rtf = _RTFWriter(attributedString: t, range: NSRange(location: 0, length: t.length)).write()!
            let rs = String(decoding: rtf, as: UTF8.self)
            XCTAssertTrue(rs.contains("\\trowd"))
            XCTAssertTrue(rs.contains("\\cellx"))
            XCTAssertTrue(rs.contains("\\intbl"))
            XCTAssertTrue(rs.contains("\\row"))
            let table = _RTFReader(data: rtf).read()!
            XCTAssertEqual(table.string, t.string)
            let blocks = (0..<4).map { i -> NSTextTableBlock? in
                let loc = [0, 3, 6, 9][i]
                return (table.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock
            }
            XCTAssertEqual(blocks.map { $0?.startingRow }, [0, 0, 1, 1])
            XCTAssertEqual(blocks.map { $0?.startingColumn }, [0, 1, 0, 1])
            XCTAssertTrue(blocks[0]?.table === blocks[3]?.table)
            XCTAssertEqual(blocks[0]?.table.numberOfColumns, 2)
        }
    }

    private func cellRanges(_ s: NSAttributedString) -> [NSRange] {
        var out: [NSRange] = []
        var i = 0
        let ns = s.string as NSString
        while i < ns.length {
            let p = ns.paragraphRange(for: NSRange(location: i, length: 0))
            out.append(p)
            i = NSMaxRange(p)
        }
        return out
    }

    // MARK: Tables

    func testTableLayoutRects() {
        MainActor.assumeIsolated {
            let font = NSFont.systemFont(ofSize: 12)
            let table = NSTextTable()
            table.numberOfColumns = 2
            table.layoutAlgorithm = .fixedLayoutAlgorithm
            table.setContentWidth(300, type: .absoluteValueType)
            let storage = NSTextStorage(string: "")
            var blocks: [NSTextTableBlock] = []
            for (row, col, text) in [(0, 0, "Left\n"), (0, 1, "Right cell\nwith two lines\n"), (1, 0, "Below\n"), (1, 1, "End\n")] {
                let b = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: col, columnSpan: 1)
                b.setWidth(5, type: .absoluteValueType, for: .padding)
                b.setWidth(1, type: .absoluteValueType, for: .border)
                blocks.append(b)
                let ps = NSMutableParagraphStyle()
                ps.textBlocks = [b]
                storage.append(NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: ps]))
            }
            storage.append(NSAttributedString(string: "After", attributes: [.font: font]))
            let lm = NSLayoutManager()
            storage.addLayoutManager(lm)
            let container = NSTextContainer(size: NSSize(width: 500, height: 2000))
            container.lineFragmentPadding = 0
            lm.addTextContainer(container)
            let s = storage.string as NSString
            let leftCell = lm.boundsRect(for: blocks[0], at: 0, effectiveRange: nil)
            let rightCell = lm.boundsRect(for: blocks[1], at: s.range(of: "Right").location, effectiveRange: nil)
            let below = lm.boundsRect(for: blocks[2], at: s.range(of: "Below").location, effectiveRange: nil)
            // Two equal columns of the 300-point table, side by side.
            XCTAssertEqual(leftCell.minX, 0, accuracy: 0.5)
            XCTAssertEqual(leftCell.width, 150, accuracy: 0.5)
            XCTAssertEqual(rightCell.minX, 150, accuracy: 0.5)
            XCTAssertEqual(rightCell.width, 150, accuracy: 0.5)
            XCTAssertEqual(leftCell.minY, rightCell.minY)
            // The row is as tall as its two-line cell; the next row starts under it.
            XCTAssertEqual(leftCell.height, rightCell.height)
            XCTAssertEqual(below.minY, rightCell.maxY, accuracy: 0.5)
            // Text sits inside the cell's border and padding.
            let rightText = lm.lineFragmentUsedRect(forGlyphAt: s.range(of: "Right").location, effectiveRange: nil)
            XCTAssertEqual(rightText.minX, 150 + 6, accuracy: 0.5)
            let content = lm.layoutRect(for: blocks[1], at: s.range(of: "Right").location, effectiveRange: nil)
            XCTAssertEqual(content.width, 150 - 12, accuracy: 0.5)
            // Text after the table follows it.
            let after = lm.lineFragmentRect(forGlyphAt: s.range(of: "After").location, effectiveRange: nil)
            XCTAssertGreaterThanOrEqual(after.minY, below.maxY - 0.5)
            // Hit testing picks the cell under the point.
            let hit = lm.glyphIndex(for: NSPoint(x: rightText.minX + 2, y: rightText.midY), in: container)
            XCTAssertEqual(hit, s.range(of: "Right").location)
            // The range helpers.
            XCTAssertEqual(storage.range(of: table, at: 2), NSRange(location: 0, length: s.range(of: "After").location))
            XCTAssertEqual(storage.range(of: blocks[1], at: s.range(of: "with").location), NSRange(location: 5, length: 26))
        }
    }

    func testTabStopsPositionListMarkerText() {
        MainActor.assumeIsolated {
            let font = NSFont.systemFont(ofSize: 12)
            let ps = NSTextView._listStyle([NSTextList(markerFormat: .disc, options: 0)], basedOn: nil)
            let storage = NSTextStorage(string: "\t\u{2022}\tItem", attributes: [.font: font, .paragraphStyle: ps])
            let lm = NSLayoutManager()
            storage.addLayoutManager(lm)
            let container = NSTextContainer(size: NSSize(width: 400, height: 1000))
            container.lineFragmentPadding = 0
            lm.addTextContainer(container)
            XCTAssertEqual(lm.location(forGlyphAt: 1).x, 11, accuracy: 0.5, "the marker at the first tab stop")
            XCTAssertEqual(lm.location(forGlyphAt: 3).x, 36, accuracy: 0.5, "the text at the head indent")
        }
    }
}
