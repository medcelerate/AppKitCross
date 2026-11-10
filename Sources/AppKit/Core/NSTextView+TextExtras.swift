// NSTextView as an editor (ADR-0030): the find bar, spell checking, completion,
// substitutions, smart insert and delete, lists, tables, attachments and the rich
// pasteboard. The public members live in NSTextView.swift (they must be overridable);
// their machinery is here.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension NSTextView {
    // MARK: Attributed edits

    /// Replaces `range` with attributed text after asking `shouldChangeText`, puts the
    /// insertion point after it and reports the change. False when refused.
    @discardableResult
    internal func _replaceAttributed(_ range: NSRange, with text: NSAttributedString, selectAfter: Bool = true) -> Bool {
        let r = _clamped(range)
        guard shouldChangeText(in: r, replacementString: text.string) else { return false }
        _finder?.noteClientStringWillChange()
        textStorage?.replaceCharacters(in: r, with: text)
        _markedRange = nil
        _invalidateLayout()
        if selectAfter { setSelectedRange(NSRange(location: r.location + text.length, length: 0)) }
        didChangeText()
        needsDisplay = true
        return true
    }

    /// The finder's replacement: keeps the replaced text's attributes.
    internal func _finderReplace(_ range: NSRange, with string: String) {
        let r = _clamped(range)
        let attrs = r.length > 0 ? (textStorage?.attributes(at: r.location, effectiveRange: nil) ?? typingAttributes) : typingAttributes
        textStorage?.replaceCharacters(in: r, with: NSAttributedString(string: string, attributes: attrs))
        _invalidateLayout()
        needsDisplay = true
    }

    /// Rects of a character range in view coordinates.
    internal func _rects(forCharacterRange range: NSRange) -> [NSRect] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        var out: [NSRect] = []
        let origin = textContainerOrigin
        lm.enumerateEnclosingRects(forGlyphRange: range, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { r, _ in
            out.append(r.offsetBy(dx: origin.x - self._scrollX, dy: origin.y))
        }
        return out
    }

    // MARK: Find

    /// The finder, made when the view uses the find bar or panel.
    internal var _finder: NSTextFinder? {
        get { _extras.finder }
        set { _extras.finder = newValue }
    }

    internal func _makeFinderIfNeeded() -> NSTextFinder {
        if let f = _extras.finder { _attachFinderContainer(f); return f }
        let f = NSTextFinder()
        let client = _NSTextViewFinderClient(self)
        _extras.finderClient = client
        f.client = client
        f.isIncrementalSearchingEnabled = _extras.incrementalSearching
        _extras.finder = f
        _attachFinderContainer(f)
        return f
    }

    private func _attachFinderContainer(_ f: NSTextFinder) {
        if usesFindBar, let scroll = enclosingScrollView {
            if f.findBarContainer !== scroll { f.findBarContainer = scroll }
        } else if f.findBarContainer == nil || !usesFindBar {
            f.findBarContainer = _NSFindPanelContainer.shared
        }
    }

    /// NSFindPanelAction tags and NSTextFinder.Action raw values coincide (1–10).
    internal func _performFind(tag: Int) {
        guard usesFindBar || usesFindPanel, let action = NSTextFinder.Action(rawValue: tag == 0 ? 1 : tag) else { NSSound.beep(); return }
        _makeFinderIfNeeded().performAction(action)
    }

    /// Match highlights beneath the text and the ring around the current match.
    internal func _drawFindHighlights(above: Bool) {
        guard let f = _extras.finder, f.findBarContainer?.isFindBarVisible == true else { return }
        if !above {
            guard f.isIncrementalSearchingEnabled else { return }
            for m in f.incrementalMatchRanges { for r in _rects(forCharacterRange: m.rangeValue) { NSTextFinder.drawIncrementalMatchHighlight(in: r) } }
            return
        }
        guard let current = f._currentMatch, current == selectedRange else { return }
        for r in _rects(forCharacterRange: current) {
            let ring = NSBezierPath(roundedRect: r.insetBy(dx: -2, dy: -1), xRadius: 4, yRadius: 4)
            NSColor(srgbRed: 1, green: 0.85, blue: 0, alpha: 1).setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    // MARK: Spelling

    internal var _spellTag: Int {
        if _extras.spellTag == 0 { _extras.spellTag = NSSpellChecker.uniqueSpellDocumentTag() }
        return _extras.spellTag
    }

    /// Marks misspelt words in `range` (whole words around it) with the spelling state.
    internal func _markSpelling(in range: NSRange? = nil, skippingWordAtInsertionPoint: Bool = false) {
        guard let lm = layoutManager else { return }
        let s = string as NSString
        let r = range.map { NSUnionRange(_paragraphsRange($0), NSRange(location: 0, length: 0)) } ?? NSRange(location: 0, length: s.length)
        lm.removeTemporaryAttribute(.spellingState, forCharacterRange: r)
        guard isContinuousSpellCheckingEnabled || range != nil || !skippingWordAtInsertionPoint else { return }
        let checker = NSSpellChecker.shared
        let caret = selectedRange.length == 0 ? selectedRange.location : -1
        for w in NSSpellChecker._words(in: string, from: r.location, to: NSMaxRange(r)) {
            if skippingWordAtInsertionPoint && caret >= w.location && caret <= NSMaxRange(w) { continue }
            if checker._isMisspelled(s.substring(with: w), tag: _spellTag) { setSpellingState(NSAttributedString.SpellingState.spelling.rawValue, range: w) }
        }
    }

    /// The paragraphs around a range.
    internal func _paragraphsRange(_ r: NSRange) -> NSRange {
        (string as NSString).paragraphRange(for: _clamped(r))
    }

    /// After an edit: check again soon (coalesced), not flagging the word being typed.
    internal func _spellingAfterEdit() {
        guard isContinuousSpellCheckingEnabled, !isFieldEditor else { return }
        guard !_extras.spellCheckPending else { return }
        _extras.spellCheckPending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self._extras.spellCheckPending = false
                self._markSpelling(skippingWordAtInsertionPoint: true)
            }
        }
    }

    /// Learned or ignored words change what is misspelt everywhere in the view.
    internal func _spellingDidChange() {
        if isContinuousSpellCheckingEnabled { _markSpelling(skippingWordAtInsertionPoint: false) }
        else { layoutManager?.removeTemporaryAttribute(.spellingState, forCharacterRange: NSRange(location: 0, length: (string as NSString).length)) }
    }

    /// Finds the next misspelling after the selection (wrapping), selects it and updates
    /// the Spelling panel.
    internal func _checkSpellingFromSelection() {
        let checker = NSSpellChecker.shared
        let start = NSMaxRange(selectedRange)
        let r = checker.checkSpelling(of: string, startingAt: start, language: nil, wrap: true, inSpellDocumentWithTag: _spellTag, wordCount: nil)
        guard r.location != NSNotFound else {
            checker.updateSpellingPanel(withMisspelledWord: "")
            NSSound.beep()
            return
        }
        setSelectedRange(r)
        scrollRangeToVisible(r)
        if isContinuousSpellCheckingEnabled || true { setSpellingState(NSAttributedString.SpellingState.spelling.rawValue, range: r) }
        checker.updateSpellingPanel(withMisspelledWord: (string as NSString).substring(with: r))
    }

    /// The misspelt word at a character index, if the spelling state marks one there.
    internal func _misspelledWord(at index: Int) -> NSRange? {
        guard let lm = layoutManager, index >= 0, index < (string as NSString).length else { return nil }
        var r = NSRange(location: 0, length: 0)
        guard let state = lm.temporaryAttribute(.spellingState, atCharacterIndex: index, effectiveRange: &r) as? NSNumber, state.intValue != 0 else { return nil }
        return r
    }

    /// The context menu: spelling guesses for a misspelt word, Ignore and Learn, then the
    /// editing commands and the Spelling and Grammar submenu.
    internal func _contextMenu(for event: NSEvent) -> NSMenu {
        let menu = NSMenu(title: "Text")
        let p = convert(event.locationInWindow, from: nil)
        let index = _offset(at: p)
        let word = _misspelledWord(at: index) ?? (index > 0 ? _misspelledWord(at: index - 1) : nil)
        if let w = word {
            setSelectedRange(w)
            let s = (string as NSString).substring(with: w)
            let guesses = NSSpellChecker.shared.guesses(forWordRange: w, in: string, language: nil, inSpellDocumentWithTag: _spellTag) ?? []
            if guesses.isEmpty {
                let none = NSMenuItem(title: "No Guesses Found", action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
            }
            for g in guesses.prefix(8) {
                let item = NSMenuItem(title: g, action: Selector(("changeSpelling:")), keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let ignore = NSMenuItem(title: "Ignore Spelling", action: Selector(("ignoreSpelling:")), keyEquivalent: "")
            ignore.target = self
            ignore.representedObject = s
            menu.addItem(ignore)
            let learn = NSMenuItem(title: "Learn Spelling", action: Selector(("_learnSpellingFromMenu:")), keyEquivalent: "")
            learn.target = self
            learn.representedObject = s
            menu.addItem(learn)
            menu.addItem(.separator())
        }
        for (title, action) in [("Cut", "cut:"), ("Copy", "copy:"), ("Paste", "paste:")] {
            let item = NSMenuItem(title: title, action: Selector((action)), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let spelling = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        spelling.submenu = NSTextView._spellingMenu(target: self)
        menu.addItem(spelling)
        let subs = NSMenuItem(title: "Substitutions", action: nil, keyEquivalent: "")
        let subsMenu = NSMenu(title: "Substitutions")
        for (title, action) in [("Show Substitutions", "orderFrontSubstitutionsPanel:"), ("Smart Copy/Paste", "toggleSmartInsertDelete:"),
                                ("Smart Quotes", "toggleAutomaticQuoteSubstitution:"), ("Smart Dashes", "toggleAutomaticDashSubstitution:"),
                                ("Text Replacement", "toggleAutomaticTextReplacement:")] {
            let item = NSMenuItem(title: title, action: Selector((action)), keyEquivalent: "")
            item.target = self
            subsMenu.addItem(item)
        }
        subs.submenu = subsMenu
        menu.addItem(subs)
        if let custom = _viewDelegateForExtras?.textView(self, menu: menu, for: event, at: index) { return custom }
        return menu
    }

    /// Edit > Spelling and Grammar, as AppKit builds it.
    internal static func _spellingMenu(target: NSTextView?) -> NSMenu {
        let m = NSMenu(title: "Spelling and Grammar")
        for (title, action, key) in [("Show Spelling and Grammar", "showGuessPanel:", ":"), ("Check Document Now", "checkSpelling:", ";"),
                                     ("", "", ""), ("Check Spelling While Typing", "toggleContinuousSpellChecking:", ""),
                                     ("Check Grammar With Spelling", "toggleGrammarChecking:", ""), ("Correct Spelling Automatically", "toggleAutomaticSpellingCorrection:", "")] {
            if title.isEmpty { m.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: Selector((action)), keyEquivalent: key)
            item.target = target
            m.addItem(item)
        }
        return m
    }

    /// Autocorrection and text replacement when a word has just been finished by `typed`.
    internal func _substituteAfterWord(typed: String) {
        guard typed.unicodeScalars.count == 1, let u = typed.unicodeScalars.first,
              CharacterSet.whitespacesAndNewlines.contains(u) || CharacterSet.punctuationCharacters.contains(u) else { return }
        let s = string as NSString
        let end = selectedRange.location - (typed as NSString).length
        guard end > 0 else { return }
        var start = end
        while start > 0 {
            guard let c = UnicodeScalar(s.character(at: start - 1)), CharacterSet.alphanumerics.contains(c) || c == "'" else { break }
            start -= 1
        }
        let word = NSRange(location: start, length: end - start)
        guard word.length > 0 else { return }
        let text = s.substring(with: word)
        var replacement: String? = nil
        if isAutomaticTextReplacementEnabled { replacement = NSSpellChecker.shared.userReplacementsDictionary[text] }
        if replacement == nil, isAutomaticSpellingCorrectionEnabled {
            replacement = NSSpellChecker.shared.correction(forWordRange: word, in: string, language: NSSpellChecker.shared.language(), inSpellDocumentWithTag: _spellTag)
        }
        guard let rep = replacement, rep != text else { return }
        let caret = selectedRange.location
        let delta = (rep as NSString).length - word.length
        guard shouldChangeText(in: word, replacementString: rep) else { return }
        _finderReplace(word, with: rep)
        setSelectedRange(NSRange(location: caret + delta, length: 0))
        didChangeText()
    }

    /// Smart quotes and dashes for a typed character; nil leaves it as typed.
    internal func _smartSubstitution(for typed: String, at location: Int) -> (String, NSRange)? {
        let s = string as NSString
        let before: unichar? = location > 0 ? s.character(at: location - 1) : nil
        func opens(_ c: unichar?) -> Bool {
            guard let c, let u = UnicodeScalar(c) else { return true }
            return CharacterSet.whitespacesAndNewlines.contains(u) || "([{\u{2014}\u{2013}".unicodeScalars.contains(u)
        }
        if isAutomaticQuoteSubstitutionEnabled, typed == "\"" || typed == "'" {
            let q = NSSpellChecker.shared.userQuotesArray(forLanguage: NSSpellChecker.shared.language())
            let double = typed == "\""
            let quote = opens(before) ? (double ? q[0] : q[2]) : (double ? q[1] : q[3])
            return (quote, NSRange(location: location, length: 0))
        }
        if isAutomaticDashSubstitutionEnabled, typed == "-", before == 0x2D {
            return ("\u{2014}", NSRange(location: location - 1, length: 1))
        }
        return nil
    }

    // MARK: Completion

    internal func _completeWord() {
        let r = rangeForUserCompletion
        guard r.location != NSNotFound, r.length > 0 else { NSSound.beep(); return }
        var selected = 0
        let words = withUnsafeMutablePointer(to: &selected) { completions(forPartialWordRange: r, indexOfSelectedItem: $0) } ?? []
        guard !words.isEmpty else { NSSound.beep(); return }
        if words.count == 1 {
            insertCompletion(words[0], forPartialWordRange: r, movement: NSTextMovement.return.rawValue, isFinal: true)
            return
        }
        // The list as a menu at the insertion point; choosing an item completes with it.
        let menu = NSMenu(title: "Completions")
        let partial = (string as NSString).substring(with: r)
        for (i, w) in words.prefix(30).enumerated() {
            let item = NSMenuItem(title: w, action: Selector(("_insertCompletionFromMenu:")), keyEquivalent: "")
            item.target = self
            item.representedObject = NSValue(range: r)
            if i == selected { item.state = .on }
            menu.addItem(item)
        }
        _extras.completionPartial = partial
        let caret = _caretRect(for: NSMaxRange(r))
        _ = menu.popUp(positioning: menu.item(at: max(0, min(selected, menu.numberOfItems - 1))), at: NSPoint(x: caret.minX, y: caret.maxY), in: self)
    }

    // MARK: Smart insert and delete

    internal func _smartInsert(_ pasteString: String, replacing r: NSRange) -> (before: String?, after: String?) {
        guard smartInsertDeleteEnabled else { return (nil, nil) }
        let s = string as NSString
        func isWordChar(_ c: unichar) -> Bool { UnicodeScalar(c).map { CharacterSet.alphanumerics.contains($0) } ?? false }
        let paste = pasteString as NSString
        guard paste.length > 0 else { return (nil, nil) }
        var before: String? = nil, after: String? = nil
        if r.location > 0, isWordChar(s.character(at: r.location - 1)), isWordChar(paste.character(at: 0)) { before = " " }
        let end = NSMaxRange(r)
        if end < s.length, isWordChar(s.character(at: end)), isWordChar(paste.character(at: paste.length - 1)) { after = " " }
        return (before, after)
    }

    internal func _smartDeleteRange(_ r: NSRange) -> NSRange {
        guard smartInsertDeleteEnabled, r.length > 0 else { return r }
        let s = string as NSString
        func isSpace(_ i: Int) -> Bool { i >= 0 && i < s.length && s.character(at: i) == 0x20 }
        func isBoundary(_ i: Int) -> Bool {
            guard i >= 0, i < s.length, let u = UnicodeScalar(s.character(at: i)) else { return true }
            return CharacterSet.whitespacesAndNewlines.contains(u) || CharacterSet.punctuationCharacters.contains(u)
        }
        // A whole word with a space on both sides takes one of the spaces with it.
        let isWord = !isBoundary(r.location) && !isBoundary(NSMaxRange(r) - 1)
        guard isWord else { return r }
        if isSpace(NSMaxRange(r)) && (r.location == 0 || isBoundary(r.location - 1)) { return NSRange(location: r.location, length: r.length + 1) }
        if isSpace(r.location - 1) && (NSMaxRange(r) >= s.length || isBoundary(NSMaxRange(r))) { return NSRange(location: r.location - 1, length: r.length + 1) }
        return r
    }

    // MARK: Lists

    /// The marker at the start of a list paragraph: "\t<marker>\t", as a range.
    internal func _markerRange(inParagraph p: NSRange) -> NSRange? {
        let s = string as NSString
        guard p.length >= 2, s.character(at: p.location) == 0x09 else { return nil }
        var i = p.location + 1
        while i < NSMaxRange(p), i - p.location < 24 {
            let c = s.character(at: i)
            if c == 0x09 { return NSRange(location: p.location, length: i + 1 - p.location) }
            if c == 0x0A { return nil }
            i += 1
        }
        return nil
    }

    internal func _paragraphStyle(at index: Int) -> NSParagraphStyle? {
        guard let st = textStorage, st.length > 0 else { return typingAttributes[.paragraphStyle] as? NSParagraphStyle }
        // The empty paragraph at the end of the text has the style typing will give it.
        if index >= st.length, [0x0A, 0x0D, 0x2029].contains((st.string as NSString).character(at: st.length - 1)) {
            if let pending = _extras.pendingParagraphStyle, pending.location == st.length { return pending.style }
            return typingAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return st.attribute(.paragraphStyle, at: min(max(0, index), st.length - 1), effectiveRange: nil) as? NSParagraphStyle
    }

    /// The paragraph style of a list item at nesting `lists.count`: hanging indent with a
    /// tab stop for the marker and one for the text.
    internal static func _listStyle(_ lists: [NSTextList], basedOn base: NSParagraphStyle?) -> NSParagraphStyle {
        let style = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        let level = CGFloat(lists.count)
        let indent = 36 * level
        style.textLists = lists
        style.headIndent = lists.isEmpty ? 0 : indent
        style.firstLineHeadIndent = 0
        style.tabStops = lists.isEmpty ? [] : [NSTextTab(textAlignment: .left, location: indent - 25), NSTextTab(textAlignment: .left, location: indent)]
        return style
    }

    /// The marker text for the item of `lists.last` at `location`.
    internal func _marker(for lists: [NSTextList], at location: Int, number: Int? = nil) -> String {
        guard let list = lists.last, let st = textStorage else { return "" }
        let n = number ?? max(list.startingItemNumber, st.itemNumber(in: list, at: location))
        var m = list.marker(forItemNumber: n)
        if list.listOptions.contains(.prependEnclosingMarker), lists.count > 1 {
            let parents = Array(lists.dropLast())
            m = _marker(for: parents, at: _parentItemLocation(parents.last!, before: location)) + m
        }
        return m
    }

    private func _parentItemLocation(_ parent: NSTextList, before location: Int) -> Int {
        var p = _paragraphsRange(NSRange(location: location, length: 0)).location
        while p > 0 {
            let prev = _paragraphsRange(NSRange(location: p - 1, length: 0))
            if _paragraphStyle(at: prev.location)?.textLists.last === parent { return prev.location }
            p = prev.location
        }
        return location
    }

    /// Writes the right number into every item's marker of the list around `location`.
    internal func _renumberList(at location: Int) {
        guard let st = textStorage, st.length > 0, let outer = _paragraphStyle(at: location)?.textLists.first else { return }
        let whole = st.range(of: outer, at: min(location, st.length - 1))
        guard whole.location != NSNotFound else { return }
        var p = whole.location
        var sel = selectedRange
        var end = NSMaxRange(whole)
        st.beginEditing()
        while p < end {
            let para = (st.string as NSString).paragraphRange(for: NSRange(location: p, length: 0))
            if let lists = _paragraphStyle(at: p)?.textLists, !lists.isEmpty, let mr = _markerRange(inParagraph: para) {
                let marker = "\t" + _marker(for: lists, at: p) + "\t"
                let current = (st.string as NSString).substring(with: mr)
                if current != marker {
                    st.replaceCharacters(in: mr, with: marker)
                    let delta = (marker as NSString).length - mr.length
                    if sel.location >= NSMaxRange(mr) { sel.location += delta } else if sel.location > mr.location { sel.location = mr.location + (marker as NSString).length }
                    end += delta
                    p = NSMaxRange(para) + delta
                    continue
                }
            }
            p = NSMaxRange(para)
        }
        st.endEditing()
        _invalidateLayout()
        if sel != selectedRange { setSelectedRange(_clamped(sel)) }
    }

    /// Makes the selected paragraphs items of a new list with `format`, or, when they are
    /// already items of a list with that format, plain paragraphs again (a toggle, as the
    /// list menu behaves). A nil format removes the list.
    internal func _applyList(markerFormat format: NSTextList.MarkerFormat?) {
        guard isEditable, isRichText || true, let st = textStorage else { return }
        let paragraphs = _paragraphsRange(selectedRange)
        let existing = _paragraphStyle(at: paragraphs.location)?.textLists ?? []
        let removing = format == nil || existing.last?.markerFormat == format
        let list = format.map { NSTextList(markerFormat: $0, options: [], startingItemNumber: 1) }
        guard shouldChangeText(in: paragraphs, replacementString: nil) else { return }
        _finder?.noteClientStringWillChange()
        st.beginEditing()
        var p = paragraphs.location
        var end = NSMaxRange(paragraphs)
        var n = 1
        let caretWasAtStart = selectedRange.location == paragraphs.location
        var sel = selectedRange
        while p < end || (p == end && p == st.length && paragraphs.length == 0 && n == 1) {
            let para = (st.string as NSString).paragraphRange(for: NSRange(location: p, length: 0))
            let style = _paragraphStyle(at: p)
            var lists = style?.textLists ?? []
            let mr = _markerRange(inParagraph: para)
            if removing {
                lists.removeAll()
            } else if let l = list {
                if lists.isEmpty { lists = [l] } else { lists[lists.count - 1] = l }
            }
            let newStyle = NSTextView._listStyle(lists, basedOn: style)
            let marker = lists.isEmpty ? "" : "\t" + (lists.last!.marker(forItemNumber: n)) + "\t"
            let oldLen = mr?.length ?? 0
            let insertAt = mr ?? NSRange(location: para.location, length: 0)
            let attrs = st.length > 0 ? st.attributes(at: min(para.location, st.length - 1), effectiveRange: nil) : typingAttributes
            st.replaceCharacters(in: insertAt, with: NSAttributedString(string: marker, attributes: attrs))
            let delta = (marker as NSString).length - oldLen
            // The selection moves with the text after the marker.
            if sel.location >= NSMaxRange(insertAt) { sel.location += delta }
            else if sel.location > insertAt.location { sel.location = insertAt.location + (marker as NSString).length }
            else if NSMaxRange(sel) > insertAt.location { sel.length += delta }
            let newPara = NSRange(location: para.location, length: max(0, para.length + delta))
            if newPara.length > 0 { st.addAttribute(.paragraphStyle, value: newStyle, range: newPara) }
            else { _extras.pendingParagraphStyle = (para.location, newStyle) }
            end += delta
            n += 1
            p = NSMaxRange(newPara)
            if newPara.length == 0 { break }
        }
        st.endEditing()
        _invalidateLayout()
        let markerLen = _markerRange(inParagraph: _paragraphsRange(NSRange(location: paragraphs.location, length: 0)))?.length ?? 0
        if caretWasAtStart && sel.length == 0 { sel.location = paragraphs.location + markerLen }
        setSelectedRange(_clamped(sel))
        didChangeText()
    }

    /// Return in a list item: a new item with the next marker, or, on an empty item, the
    /// end of the list (one level out when nested). False when not in a list.
    internal func _listNewline() -> Bool {
        guard isRichText || true, let st = textStorage, selectedRange.length == 0 else { return false }
        let caret = selectedRange.location
        let para = _paragraphsRange(NSRange(location: caret, length: 0))
        guard let style = _paragraphStyle(at: para.location), let list = style.textLists.last, para.length > 0 || caret > 0,
              let mr = _markerRange(inParagraph: para) else { return false }
        _ = list
        let contentEnd = NSMaxRange(para) - ((para.length > 0 && (string as NSString).character(at: NSMaxRange(para) - 1) == 0x0A) ? 1 : 0)
        if contentEnd == NSMaxRange(mr) {
            // Empty item: out one level (or out of the list).
            _changeListLevel(by: -1)
            return true
        }
        let lists = style.textLists
        let attrs = st.attributes(at: min(max(0, caret - 1), st.length - 1), effectiveRange: nil)
        var a = attrs
        a[.paragraphStyle] = style
        let marker = "\t" + _marker(for: lists, at: para.location, number: st.itemNumber(in: lists.last!, at: para.location) + 1) + "\t"
        guard _replaceAttributed(NSRange(location: caret, length: 0), with: NSAttributedString(string: "\n" + marker, attributes: a)) else { return true }
        _renumberList(at: caret + 1)
        return true
    }

    /// Tab at the start of an item's text nests it one level deeper; Shift-Tab (or `by: -1`)
    /// brings it out. False when the insertion point is not there.
    @discardableResult
    internal func _changeListLevel(by step: Int, onlyAtItemStart: Bool = false) -> Bool {
        guard let st = textStorage, selectedRange.length == 0 else { return false }
        let caret = selectedRange.location
        let para = _paragraphsRange(NSRange(location: caret, length: 0))
        guard let style = _paragraphStyle(at: para.location), !style.textLists.isEmpty, let mr = _markerRange(inParagraph: para) else { return false }
        if onlyAtItemStart && caret != NSMaxRange(mr) { return false }
        var lists = style.textLists
        if step > 0 {
            // Reuse the nested list of the previous item at that depth, else make one.
            var nested: NSTextList? = nil
            if para.location > 0, let prev = _paragraphStyle(at: para.location - 1)?.textLists, prev.count == lists.count + 1, prev[lists.count - 1] === lists.last { nested = prev.last }
            lists.append(nested ?? NSTextList(markerFormat: NSTextView._nestedFormat(lists.last!.markerFormat, depth: lists.count), options: [], startingItemNumber: 1))
        } else {
            lists.removeLast()
        }
        guard shouldChangeText(in: para, replacementString: nil) else { return true }
        let newStyle = NSTextView._listStyle(lists, basedOn: style)
        st.beginEditing()
        let attrs = st.attributes(at: para.location, effectiveRange: nil)
        let marker = lists.isEmpty ? "" : "\t\u{FFFD}\t"     // placeholder, numbered below
        st.replaceCharacters(in: mr, with: NSAttributedString(string: marker, attributes: attrs))
        let delta = (marker as NSString).length - mr.length
        let newPara = NSRange(location: para.location, length: para.length + delta)
        if newPara.length > 0 { st.addAttribute(.paragraphStyle, value: newStyle, range: newPara) }
        else { _extras.pendingParagraphStyle = (para.location, newStyle) }
        st.endEditing()
        _invalidateLayout()
        if lists.isEmpty {
            // Out of the list: renumber what follows in the old list.
            setSelectedRange(NSRange(location: para.location, length: 0))
            if NSMaxRange(newPara) < st.length { _renumberList(at: NSMaxRange(newPara)) }
        } else {
            let m = "\t" + _marker(for: lists, at: para.location) + "\t"
            st.replaceCharacters(in: NSRange(location: para.location, length: (marker as NSString).length), with: m)
            setSelectedRange(NSRange(location: para.location + (m as NSString).length, length: 0))
            _renumberList(at: para.location)
        }
        if para.location > 0, let prevLists = _paragraphStyle(at: para.location - 1)?.textLists, !prevLists.isEmpty { _renumberList(at: para.location - 1) }
        didChangeText()
        return true
    }

    /// Nested lists step through bullets (disc, circle, square) or keep the numbering kind.
    internal static func _nestedFormat(_ f: NSTextList.MarkerFormat, depth: Int) -> NSTextList.MarkerFormat {
        let steps = [("{disc}", "{circle}"), ("{circle}", "{square}"), ("{square}", "{disc}"),
                     ("{decimal}", "{lower-alpha}"), ("{lower-alpha}", "{lower-roman}"), ("{lower-roman}", "{decimal}")]
        for (from, to) in steps where f.rawValue.contains(from) {
            return NSTextList.MarkerFormat(rawValue: f.rawValue.replacingOccurrences(of: from, with: to))
        }
        return f
    }

    // MARK: Tables

    /// Inserts a table of empty cells at the insertion point's paragraph.
    internal func _insertTable(rows: Int, columns: Int) {
        guard isEditable, rows > 0, columns > 0 else { return }
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.setContentWidth(100, type: .percentageValueType)
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        var attrs = typingAttributes
        let out = NSMutableAttributedString(string: "")
        let base = _paragraphStyle(at: selectedRange.location)
        for r in 0..<rows {
            for c in 0..<columns {
                let cell = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                cell.setWidth(1, type: .absoluteValueType, for: .border)
                cell.setBorderColor(NSColor(white: 0.6, alpha: 1))
                cell.setWidth(4, type: .absoluteValueType, for: .padding)
                let style = (base?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                style.textBlocks = [cell]
                style.textLists = []
                attrs[.paragraphStyle] = style
                out.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }
        let s = string as NSString
        var at = selectedRange.location
        let prefix: String
        if at > 0 && s.character(at: at - 1) != 0x0A { prefix = "\n" } else { prefix = "" }
        if !prefix.isEmpty { out.insert(NSAttributedString(string: prefix, attributes: typingAttributes.filter { $0.key != .paragraphStyle }), at: 0) }
        // Text after the table starts a plain paragraph.
        if NSMaxRange(selectedRange) >= s.length {
            var after = typingAttributes
            after[.paragraphStyle] = NSParagraphStyle.default
            out.append(NSAttributedString(string: "", attributes: after))
        }
        guard _replaceAttributed(selectedRange, with: out, selectAfter: false) else { return }
        at += (prefix as NSString).length
        setSelectedRange(NSRange(location: at, length: 0))
    }

    /// Tab in a table cell moves to the next cell; false when not in a table.
    internal func _moveToAdjacentCell(forward: Bool) -> Bool {
        guard let st = textStorage, st.length > 0 else { return false }
        let caret = min(selectedRange.location, st.length - 1)
        guard let cell = _paragraphStyle(at: caret)?.textBlocks.first as? NSTextTableBlock else { return false }
        let here = st.range(of: cell, at: caret)
        guard here.location != NSNotFound else { return false }
        let target = forward ? NSMaxRange(here) : here.location - 1
        guard target >= 0, target < st.length, let next = _paragraphStyle(at: target)?.textBlocks.first as? NSTextTableBlock, next.table === cell.table else {
            NSSound.beep()
            return true
        }
        let r = st.range(of: next, at: target)
        // Select the cell's text (without its final newline), as AppKit does.
        var len = r.length
        if len > 0, (st.string as NSString).character(at: NSMaxRange(r) - 1) == 0x0A { len -= 1 }
        setSelectedRange(NSRange(location: r.location, length: len))
        return true
    }

    // MARK: Attachments and the pasteboard

    /// Attributed text for pasted or dropped images and files (each becomes an attachment).
    internal func _attachments(fromFileURLs urls: [URL]) -> NSAttributedString? {
        let out = NSMutableAttributedString(string: "")
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = url.lastPathComponent
            let a = NSTextAttachment(fileWrapper: wrapper)
            var attrs = typingAttributes
            attrs[.attachment] = a
            out.append(NSAttributedString(string: "\u{FFFC}", attributes: attrs))
        }
        return out.length > 0 ? out : nil
    }

    internal func _attachment(fromImageData data: Data, type: NSPasteboard.PasteboardType) -> NSAttributedString {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = type == .tiff ? "Pasted Graphic.tiff" : "Pasted Graphic.png"
        var attrs = typingAttributes
        attrs[.attachment] = NSTextAttachment(fileWrapper: wrapper)
        return NSAttributedString(string: "\u{FFFC}", attributes: attrs)
    }

    /// The richest content of a pasteboard this view takes.
    internal func _readContent(from pb: NSPasteboard, type: NSPasteboard.PasteboardType? = nil) -> NSAttributedString? {
        let types = type.map { [$0] } ?? readablePasteboardTypes
        for t in types {
            switch t {
            case .rtfd where isRichText && importsGraphics:
                if let d = pb.data(forType: .rtfd), let w = _RTFDArchive.unarchive(d), let s = _RTFReader.readRTFD(w) { return s }
            case .rtf where isRichText:
                if let d = pb.data(forType: .rtf), let s = _RTFReader(data: d).read() { return s }
            case .png, .tiff:
                guard isRichText && importsGraphics, let d = pb.data(forType: t) else { continue }
                return _attachment(fromImageData: d, type: t)
            case .fileURL:
                guard isRichText && importsGraphics, let raw = pb.string(forType: .fileURL), let url = URL(string: raw) ?? Optional(URL(fileURLWithPath: raw)) else { continue }
                if let s = _attachments(fromFileURLs: [url]) { return s }
            case .string:
                if var s = pb.string(forType: .string) {
                    if isFieldEditor { s = s.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ") }
                    return NSAttributedString(string: s, attributes: typingAttributes)
                }
            default: continue
            }
        }
        return nil
    }

    /// AppKit's marker for text copied as whole words, which pastes with smart spacing.
    internal static let _smartPasteType = NSPasteboard.PasteboardType("NeXT smart paste pasteboard type")

    /// Inserts pasted text; `smart` (a word selection was copied) adds spaces around it.
    internal func _insertPasted(_ content: NSAttributedString, smart: Bool = false) {
        let r = selectedRange
        var text = content
        if smart, !content.containsAttachments(in: NSRange(location: 0, length: content.length)) {
            let (before, after) = _smartInsert(content.string, replacing: r)
            if before != nil || after != nil {
                let m = NSMutableAttributedString(attributedString: content)
                if let b = before { m.insert(NSAttributedString(string: b, attributes: typingAttributes), at: 0) }
                if let a = after { m.append(NSAttributedString(string: a, attributes: typingAttributes)) }
                text = m
            }
        }
        _replaceAttributed(r, with: text)
    }

    /// Writes the selection as plain text, and as RTF (RTFD with attachments) when rich.
    internal func _writeSelection(to pb: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let sel = selectedRange
        guard sel.length > 0, let st = textStorage else { return false }
        let sub = st.attributedSubstring(from: sel)
        _ = pb.clearContents()
        var wrote = false
        // A double-click (word) selection is copied for smart pasting.
        if smartInsertDeleteEnabled && _clickCount == 2 { _ = pb.setData(Data(), forType: NSTextView._smartPasteType) }
        for t in types {
            switch t {
            case .string:
                wrote = pb.setString(sub.string.replacingOccurrences(of: "\u{FFFC}", with: ""), forType: .string) || wrote
            case .rtf where isRichText:
                if let d = _RTFWriter(attributedString: sub, range: NSRange(location: 0, length: sub.length)).write() { wrote = pb.setData(d, forType: .rtf) || wrote }
            case .rtfd where isRichText && sub.containsAttachments(in: NSRange(location: 0, length: sub.length)):
                if let d = sub.rtfd(from: NSRange(location: 0, length: sub.length)) { wrote = pb.setData(d, forType: .rtfd) || wrote }
            default: break
            }
        }
        return wrote
    }

    internal var _viewDelegateForExtras: (any NSTextViewDelegate)? { delegate as? NSTextViewDelegate }
}

/// NSTextView's state for the editor features, kept apart from the core text state.
@MainActor final class _NSTextViewExtras {
    var finder: NSTextFinder?
    var finderClient: _NSTextViewFinderClient?
    var incrementalSearching = false
    var usesFindPanel = false
    var spellTag = 0
    var spellCheckPending = false
    var completionPartial: String?
    /// The style of an empty last paragraph (no character carries it yet).
    var pendingParagraphStyle: (location: Int, style: NSParagraphStyle)?
    var isAutomaticDashSubstitutionEnabled = false
    var isAutomaticTextReplacementEnabled = false
    var isAutomaticTextCompletionEnabled = false
    var isAutomaticLinkDetectionEnabled = false
    var isAutomaticDataDetectionEnabled = false
    var usesRuler = false
    var usesInspectorBar = false
    var linkTextAttributes: [NSAttributedString.Key: Any]? = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
    var displaysLinkToolTips = true
    var allowsImageEditing = false
    var allowsDocumentBackgroundColorChange = false
    var acceptsGlyphInfo = false
    var allowedInputSourceLocales: [String]? = nil
    var usesRolloverButtonForSelection = false
    var selectionGranularity: NSSelectionGranularity = .selectByCharacter
    var defaultParagraphStyle: NSParagraphStyle? = nil
    var allowsCharacterPickerTouchBarItem = true
}

// MARK: - Character attribute commands, scroll view factories

extension NSTextView {
    /// Applies `value` (nil removes) to the selection, or to the typing attributes.
    internal func _setCharacterAttribute(_ key: NSAttributedString.Key, _ value: Any?) {
        let r = selectedRange
        if r.length == 0 || !isRichText {
            var t = typingAttributes
            t[key] = value
            typingAttributes = t
            if !isRichText, r.length == 0 { return }
        }
        guard let st = textStorage, isEditable, shouldChangeText(in: r, replacementString: nil) else { return }
        let target = isRichText ? r : NSRange(location: 0, length: st.length)
        if let v = value { st.addAttribute(key, value: v, range: target) } else { st.removeAttribute(key, range: target) }
        _invalidateLayout()
        didChangeText()
    }

    internal func _adjustKern(by step: CGFloat) {
        let at = max(0, min(selectedRange.location, (textStorage?.length ?? 1) - 1))
        let current = ((textStorage?.length ?? 0) > 0 ? (textStorage?.attribute(.kern, at: at, effectiveRange: nil) as? NSNumber)?.doubleValue : nil) ?? 0
        _setCharacterAttribute(.kern, NSNumber(value: current + Double(step)))
    }

    internal func _adjustBaseline(by step: CGFloat) {
        let at = max(0, min(selectedRange.location, (textStorage?.length ?? 1) - 1))
        let current = ((textStorage?.length ?? 0) > 0 ? (textStorage?.attribute(.baselineOffset, at: at, effectiveRange: nil) as? NSNumber)?.doubleValue : nil) ?? 0
        _setCharacterAttribute(.baselineOffset, NSNumber(value: current + Double(step)))
    }

    /// A text view in a scroll view, sized and resizing as AppKit's factory methods make it.
    internal static func _scrollable(rich: Bool, document: Bool = true) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let size = scroll.contentSize
        let tv = NSTextView(frame: NSRect(origin: .zero, size: size))
        tv.minSize = NSSize(width: 0, height: size.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = rich
        tv.importsGraphics = rich && document
        if document {
            tv.usesFindBar = true
            tv.isIncrementalSearchingEnabled = true
            tv.allowsUndo = true
            if !rich { tv.font = NSFont.userFixedPitchFont(ofSize: 0) ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular) }
        }
        scroll.documentView = tv
        return scroll
    }
}

// MARK: - The list and table panels

/// Format > Lists: a marker format list and Apply / Remove.
@MainActor final class _NSListPanel: NSObject {
    static var shared: _NSListPanel?
    private let panel: NSPanel
    private let formats = NSPopUpButton(frame: NSRect(x: 16, y: 56, width: 220, height: 26), pullsDown: false)
    private weak var textView: NSTextView?
    static let choices: [(String, NSTextList.MarkerFormat)] = [("\u{2022} Bullet", .disc), ("\u{25E6} Circle", .circle), ("\u{25AA} Square", .square),
                                                               ("\u{2043} Hyphen", .hyphen), ("\u{2713} Check", .check), ("1. 2. 3.", NSTextList.MarkerFormat("{decimal}.")),
                                                               ("a. b. c.", NSTextList.MarkerFormat("{lower-alpha}.")), ("A. B. C.", NSTextList.MarkerFormat("{upper-alpha}.")),
                                                               ("i. ii. iii.", NSTextList.MarkerFormat("{lower-roman}.")), ("I. II. III.", NSTextList.MarkerFormat("{upper-roman}."))]

    static func show(for tv: NSTextView) {
        let p = shared ?? _NSListPanel()
        shared = p
        p.textView = tv
        p.panel.makeKeyAndOrderFront(nil)
    }

    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 252, height: 96), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Lists"
        panel.isReleasedWhenClosed = false
        super.init()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 252, height: 96))
        formats.addItems(withTitles: _NSListPanel.choices.map(\.0))
        content.addSubview(formats)
        let apply = NSButton(title: "Apply", target: self, action: Selector(("_listApply:")))
        apply.frame = NSRect(x: 150, y: 14, width: 86, height: 28)
        let remove = NSButton(title: "Remove", target: self, action: Selector(("_listRemove:")))
        remove.frame = NSRect(x: 56, y: 14, width: 86, height: 28)
        content.addSubview(apply)
        content.addSubview(remove)
        panel.contentView = content
        setActionHandler(for: Selector(("_listApply:"))) { [weak self] _ in
            guard let self, let tv = self.textView else { return }
            let i = max(0, self.formats.indexOfSelectedItem)
            tv._applyList(markerFormat: _NSListPanel.choices[i].1)
        }
        setActionHandler(for: Selector(("_listRemove:"))) { [weak self] _ in self?.textView?._applyList(markerFormat: nil) }
    }
}

/// Format > Table: rows and columns, then Insert.
@MainActor final class _NSTablePanel: NSObject {
    static var shared: _NSTablePanel?
    private let panel: NSPanel
    private let rows = NSTextField(string: "3")
    private let columns = NSTextField(string: "3")
    private weak var textView: NSTextView?

    static func show(for tv: NSTextView) {
        let p = shared ?? _NSTablePanel()
        shared = p
        p.textView = tv
        p.panel.makeKeyAndOrderFront(nil)
    }

    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 110), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Table"
        panel.isReleasedWhenClosed = false
        super.init()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 110))
        let rl = NSTextField(labelWithString: "Rows:"), cl = NSTextField(labelWithString: "Columns:")
        rl.frame = NSRect(x: 16, y: 74, width: 70, height: 18); rows.frame = NSRect(x: 96, y: 72, width: 60, height: 22)
        cl.frame = NSRect(x: 16, y: 46, width: 70, height: 18); columns.frame = NSRect(x: 96, y: 44, width: 60, height: 22)
        let insert = NSButton(title: "Insert", target: self, action: Selector(("_tableInsert:")))
        insert.frame = NSRect(x: 118, y: 8, width: 86, height: 28)
        for v in [rl, rows, cl, columns, insert] as [NSView] { content.addSubview(v) }
        panel.contentView = content
        setActionHandler(for: Selector(("_tableInsert:"))) { [weak self] _ in
            guard let self, let tv = self.textView else { return }
            tv._insertTable(rows: max(1, min(50, self.rows.integerValue)), columns: max(1, min(20, self.columns.integerValue)))
            self.panel.orderOut(nil)
        }
    }
}
