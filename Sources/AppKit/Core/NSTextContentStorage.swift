// NSTextContentStorage (hand-written; seeded from the generated stub, see tools/apigen)
// A TextKit 2 document over an NSTextStorage (ADR-0040). It observes the storage and keeps
// one NSTextParagraph per paragraph; an edit rebuilds the paragraphs it touches and shifts
// the others in place, so unchanged paragraphs (and their layout) keep their identity.
// Paragraphs end where TextKit 1's lines do: LF, CR, CR LF, U+2028, U+2029, form feed.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage
@available(macOS 12.0, *)
open class NSTextContentStorage: NSTextContentManager, NSTextStorageObserving {
    private var _textStorage: NSTextStorage?
    /// The paragraphs in document order, each with its `elementRange` (nil until needed).
    private var _paragraphs: [NSTextParagraph]? = nil
    private var _includesTextListMarkers = true

    public override init() {
        super.init()
        textStorage = NSTextStorage()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        textStorage = NSTextStorage()
    }

    private var _storageDelegate: (any NSTextContentStorageDelegate)? { delegate as? NSTextContentStorageDelegate }

    // MARK: The backing store

    // Requirement of NSTextStorageObserving
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/textstorage
    open var textStorage: NSTextStorage? {
        get { _textStorage }
        set {
            guard newValue !== _textStorage else { return }
            if let old = _textStorage, old.textStorageObserver === self { old.textStorageObserver = nil }
            _textStorage = newValue
            newValue?.textStorageObserver = self
            _paragraphs = nil
            _noteFullChange()
        }
    }
    /// The document's contents; setting replaces them.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/attributedstring
    open var attributedString: NSAttributedString? {
        get { _textStorage }
        set {
            if _textStorage == nil { textStorage = NSTextStorage() }
            _textStorage?.setAttributedString(newValue ?? NSAttributedString(string: ""))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/attributedstring(for:)
    open func attributedString(for textElement: NSTextElement) -> NSAttributedString? {
        if let p = textElement as? NSTextParagraph { return p.attributedString }
        guard let storage = _textStorage, let r = textElement.elementRange?._nsRange, NSMaxRange(r) <= storage.length else { return nil }
        return storage.attributedSubstring(from: r)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/textelement(for:)
    open func textElement(for attributedString: NSAttributedString) -> NSTextElement? {
        let p = NSTextParagraph(attributedString: attributedString)
        p.textContentManager = self
        return p
    }
    /// The port's lists keep their marker text in the storage (as TextKit 1 does), so the
    /// markers are always part of the paragraphs; the setting is kept for clients.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/includestextlistmarkers
    @available(macOS 26.0, *)
    open var includesTextListMarkers: Bool {
        get { _includesTextListMarkers }
        set { _includesTextListMarkers = newValue }
    }

    // MARK: Locations

    private var _length: Int { _textStorage?.length ?? 0 }

    // Requirement of NSTextElementProvider
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/documentrange
    open override var documentRange: NSTextRange { NSTextRange._make(NSRange(location: 0, length: _length)) }
    /// Nil when the result would fall outside the document.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/location(_:offsetby:)
    open func location(_ location: any NSTextLocation, offsetBy offset: Int) -> (any NSTextLocation)? {
        guard let o = _offset(of: location) else { return nil }
        let n = o + offset
        return n >= 0 && n <= _length ? _NSTextIndexLocation(n) : nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/offset(from:to:)
    open func offset(from: any NSTextLocation, to: any NSTextLocation) -> Int {
        guard let a = _offset(of: from), let b = _offset(of: to) else { return 0 }
        return b - a
    }
    /// The range widened to whole composed character sequences, or nil when it needs no
    /// adjustment.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/adjustedrange(from:foreditingtextselection:)
    open func adjustedRange(from textRange: NSTextRange, forEditingTextSelection: Bool) -> NSTextRange? {
        guard let r = textRange._nsRange, let storage = _textStorage, NSMaxRange(r) <= storage.length else { return nil }
        let s = storage.string as NSString
        var adjusted = r
        if r.length > 0 { adjusted = s.rangeOfComposedCharacterSequences(for: r) }
        else if r.location < s.length { let c = s.rangeOfComposedCharacterSequence(at: r.location); if c.location != r.location { adjusted = NSRange(location: NSMaxRange(c), length: 0) } }
        return adjusted == r ? nil : NSTextRange._make(adjusted)
    }

    // MARK: Paragraphs

    private func _makeParagraph(_ range: NSRange) -> NSTextParagraph {
        let p = _storageDelegate?.textContentStorage(self, textParagraphWith: range)
            ?? NSTextParagraph(attributedString: _textStorage?.attributedSubstring(from: range))
        p.elementRange = NSTextRange._make(range)
        p.textContentManager = self
        return p
    }

    /// The paragraph ranges of `units` starting at `from`, up to the first paragraph boundary
    /// at or after `stop`.
    private func _scan(_ units: [UInt16], from: Int, stop: Int) -> [NSRange] {
        var out: [NSRange] = []
        var p = from
        while p < units.count {
            let e = _NSLineTypesetter.paragraphEnd(from: p, units: units)
            out.append(NSRange(location: p, length: e - p))
            p = e
            if p >= stop { break }
        }
        return out
    }

    internal var _allParagraphs: [NSTextParagraph] {
        if let p = _paragraphs { return p }
        guard let storage = _textStorage else { return [] }
        let units = Array(storage.string.utf16)
        let made = _scan(units, from: 0, stop: units.count).map(_makeParagraph)
        _paragraphs = made
        return made
    }

    /// The index of the paragraph containing `offset` (the last one at the end).
    internal func _paragraphIndex(containing offset: Int) -> Int? {
        let ps = _allParagraphs
        guard !ps.isEmpty else { return nil }
        var lo = 0, hi = ps.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if let r = ps[mid].elementRange?._nsRange, NSMaxRange(r) <= offset { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // Requirement of NSTextElementProvider
    /// Enumerates paragraphs from the one containing `textLocation` (the first, or the last
    /// with `.reverse`, when nil) until `block` returns false; returns the far edge of the
    /// last paragraph enumerated.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/enumeratetextelements(from:options:using:)
    open override func enumerateTextElements(from textLocation: (any NSTextLocation)?, options: NSTextContentManager.EnumerationOptions = [], using block: (NSTextElement) -> Bool) -> (any NSTextLocation)? {
        let ps = _allParagraphs
        guard !ps.isEmpty else { return nil }
        let reverse = options.contains(.reverse)
        var i: Int
        if let loc = textLocation, let o = _offset(of: loc) {
            guard let found = _paragraphIndex(containing: o) else { return nil }
            i = found
            // Backwards from a paragraph's start begins with the paragraph before it.
            if reverse, let r = ps[i].elementRange?._nsRange, r.location == o, o > 0, i > 0 { i -= 1 }
        } else {
            i = reverse ? ps.count - 1 : 0
        }
        var last: (any NSTextLocation)? = nil
        while i >= 0 && i < ps.count {
            let p = ps[i]
            i += reverse ? -1 : 1
            if let d = delegate, !d.textContentManager(self, shouldEnumerate: p, options: options) { continue }
            let element = delegate?.textContentManager(self, textElementAt: p.elementRange!.location) ?? p
            last = reverse ? element.elementRange?.location : element.elementRange?.endLocation
            if !block(element) { break }
        }
        return last
    }
    // Requirement of NSTextElementProvider
    /// Replaces the text in `range` with the elements' text (deletes it for nil).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentmanager/replacecontents(in:with:)
    open override func replaceContents(in range: NSTextRange, with textElements: [NSTextElement]?) {
        guard let storage = _textStorage, let r = range._nsRange, NSMaxRange(r) <= storage.length else { return }
        let replacement = NSMutableAttributedString(string: "")
        for e in textElements ?? [] { if let s = attributedString(for: e) { replacement.append(s) } }
        performEditingTransaction { storage.replaceCharacters(in: r, with: replacement) }
    }

    // MARK: Observing the storage

    // Requirement of NSTextStorageObserving
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/processediting(for:edited:range:changeinlength:invalidatedrange:)
    open func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        guard textStorage === _textStorage else { return }
        let oldRange = NSRange(location: newCharRange.location, length: max(0, newCharRange.length - delta))
        defer { _noteEdit(old: oldRange, new: newCharRange) }
        guard var ps = _paragraphs else { return }
        let units = Array(textStorage.string.utf16)
        if ps.isEmpty {
            _paragraphs = _scan(units, from: 0, stop: units.count).map(_makeParagraph)
            return
        }
        func oldRangeOf(_ k: Int) -> NSRange { ps[k].elementRange?._nsRange ?? NSRange(location: 0, length: 0) }
        func indexContaining(_ o: Int) -> Int {
            var lo = 0, hi = ps.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if NSMaxRange(oldRangeOf(mid)) <= o { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }
        // The old paragraphs the edit touches, with the one before it when text inserted at
        // a paragraph's start can join that one's CR into a CR LF.
        var i0 = indexContaining(oldRange.location)
        if i0 > 0, editMask.contains(.editedCharacters), oldRangeOf(i0).location == oldRange.location,
           (ps[i0 - 1].attributedString.string as NSString).hasSuffix("\r") { i0 -= 1 }
        let i1 = indexContaining(NSMaxRange(oldRange))
        let start = oldRangeOf(i0).location
        let spanEnd = NSMaxRange(oldRangeOf(i1)) + delta
        // Scan new paragraphs until a boundary where an unchanged old paragraph begins.
        var made: [NSRange] = []
        var p = start
        var j = i1 + 1
        while p < units.count {
            let e = _NSLineTypesetter.paragraphEnd(from: p, units: units)
            made.append(NSRange(location: p, length: e - p))
            p = e
            while j < ps.count, oldRangeOf(j).location + delta < p { j += 1 }
            if p >= spanEnd, j >= ps.count || oldRangeOf(j).location + delta == p { break }
        }
        if p >= units.count { j = ps.count }
        let tail = Array(ps[j...])
        if delta != 0 {
            for t in tail { if let r = t.elementRange?._nsRange { t.elementRange = NSTextRange._make(NSRange(location: r.location + delta, length: r.length)) } }
        }
        ps.replaceSubrange(i0..<ps.count, with: made.map(_makeParagraph) + tail)
        _paragraphs = ps
    }
    // Requirement of NSTextStorageObserving
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextcontentstorage/performeditingtransaction(for:using:)
    open func performEditingTransaction(for textStorage: NSTextStorage, using transaction: () -> Void) {
        performEditingTransaction {
            textStorage.beginEditing()
            transaction()
            textStorage.endEditing()
        }
    }
}
