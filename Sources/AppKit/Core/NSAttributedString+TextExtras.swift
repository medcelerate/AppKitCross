// NSAttributedString's AppKit additions for attachments, lists, tables and word
// boundaries (ADR-0030); the generator skips these members (tools/apigen/config.json,
// `skipMembers`).

import Foundation

extension NSAttributedString {
    /// An attachment character carrying `attachment`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(attachment:)
    public convenience init(attachment: NSTextAttachment) {
        self.init(string: "\u{FFFC}", attributes: [.attachment: attachment])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/init(attachment:attributes:)
    @available(macOS 15.0, *)
    public convenience init(attachment: NSTextAttachment, attributes: [NSAttributedString.Key : Any] = [:]) {
        var attrs = attributes
        attrs[.attachment] = attachment
        self.init(string: "\u{FFFC}", attributes: attrs)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/containsattachments
    public var containsAttachments: Bool { containsAttachments(in: NSRange(location: 0, length: length)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/containsattachments(in:)
    @available(macOS 10.11, *)
    public func containsAttachments(in range: NSRange) -> Bool {
        var found = false
        enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
            if value is NSTextAttachment { found = true; stop.pointee = true }
        }
        return found
    }

    /// The word around `location` (an attachment or other single character on its own).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/doubleclick(at:)
    public func doubleClick(at location: Int) -> NSRange {
        let s = string as NSString
        guard s.length > 0 else { return NSRange(location: 0, length: 0) }
        let i = min(max(0, location), s.length - 1)
        func isWord(_ k: Int) -> Bool {
            guard k >= 0, k < s.length, let u = UnicodeScalar(s.character(at: k)) else { return false }
            return CharacterSet.alphanumerics.contains(u) || u == "_" || u == "'" || u == "\u{2019}"
        }
        guard isWord(i) else { return NSRange(location: i, length: 1) }
        var a = i, b = i + 1
        while a > 0 && isWord(a - 1) { a -= 1 }
        while b < s.length && isWord(b) { b += 1 }
        return NSRange(location: a, length: b - a)
    }
    /// The start of the next word after `location`, or of the word before it.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/nextword(from:forward:)
    public func nextWord(from location: Int, forward isForward: Bool) -> Int {
        let s = string as NSString
        func isWord(_ k: Int) -> Bool {
            guard k >= 0, k < s.length, let u = UnicodeScalar(s.character(at: k)) else { return false }
            return CharacterSet.alphanumerics.contains(u)
        }
        var i = min(max(0, location), s.length)
        if isForward {
            while i < s.length && isWord(i) { i += 1 }
            while i < s.length && !isWord(i) { i += 1 }
        } else {
            while i > 0 && !isWord(i - 1) { i -= 1 }
            while i > 0 && isWord(i - 1) { i -= 1 }
        }
        return i
    }

    // MARK: Lists and blocks

    /// The paragraph range at `index`.
    internal func _paragraphRange(at index: Int) -> NSRange {
        (string as NSString).paragraphRange(for: NSRange(location: min(max(0, index), length), length: 0))
    }

    private func _paragraphStyleAt(_ i: Int) -> NSParagraphStyle? {
        guard i >= 0, i < length else { return nil }
        return attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle
    }

    /// The run of whole paragraphs around `location` whose style satisfies `belongs`.
    private func _paragraphRun(at location: Int, _ belongs: (NSParagraphStyle) -> Bool) -> NSRange {
        guard length > 0, let here = _paragraphStyleAt(min(location, length - 1)), belongs(here) else { return NSRange(location: NSNotFound, length: 0) }
        var start = _paragraphRange(at: min(location, length - 1))
        while start.location > 0, let s = _paragraphStyleAt(start.location - 1), belongs(s) { start = _paragraphRange(at: start.location - 1) }
        var end = _paragraphRange(at: min(location, length - 1))
        while NSMaxRange(end) < length, let s = _paragraphStyleAt(NSMaxRange(end)), belongs(s) { end = _paragraphRange(at: NSMaxRange(end)) }
        return NSRange(location: start.location, length: NSMaxRange(end) - start.location)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/range(of:at:)-6sffn
    public func range(of list: NSTextList, at location: Int) -> NSRange {
        _paragraphRun(at: location) { $0.textLists.contains { $0 === list } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/range(of:at:)-5rf0r
    public func range(of block: NSTextBlock, at location: Int) -> NSRange {
        _paragraphRun(at: location) { $0.textBlocks.contains { $0 === block } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/range(of:at:)-8pbsv
    public func range(of table: NSTextTable, at location: Int) -> NSRange {
        _paragraphRun(at: location) { $0.textBlocks.contains { ($0 as? NSTextTableBlock)?.table === table } }
    }
    /// The number of the item at `location` in `list`: its position among the paragraphs of
    /// the list at the list's own level, from `startingItemNumber`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsattributedstring/itemnumber(in:at:)
    public func itemNumber(in list: NSTextList, at location: Int) -> Int {
        let r = range(of: list, at: location)
        guard r.location != NSNotFound else { return 0 }
        var n = list.startingItemNumber - 1
        var p = r.location
        let target = _paragraphRange(at: min(location, max(0, length - 1))).location
        while p <= target && p < NSMaxRange(r) {
            if let s = _paragraphStyleAt(p), s.textLists.last === list { n += 1 }
            let pr = _paragraphRange(at: p)
            guard NSMaxRange(pr) > p else { break }
            p = NSMaxRange(pr)
        }
        return n
    }
}

extension NSMutableAttributedString {
    /// Removes attachment attributes from characters other than U+FFFC, and attachment
    /// characters that have no attachment.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableattributedstring/fixattachmentattribute(in:)
    public func fixAttachmentAttribute(in range: NSRange) {
        let s = string as NSString
        var strays: [NSRange] = []
        var orphans: [Int] = []
        enumerateAttribute(.attachment, in: range, options: []) { value, r, _ in
            for i in r.location..<NSMaxRange(r) {
                let isChar = s.character(at: i) == 0xFFFC
                if value != nil && !isChar { strays.append(NSRange(location: i, length: 1)) }
                if value == nil && isChar { orphans.append(i) }
            }
        }
        for r in strays { removeAttribute(.attachment, range: r) }
        for i in orphans.reversed() { deleteCharacters(in: NSRange(location: i, length: 1)) }
    }
}
