// NSLayoutManager (hand-written; seeded from the generated stub, see tools/apigen)
// Lays a text storage out into text containers as line fragments typeset by CoreText.
// Glyph indices are character (UTF-16) indices: one nominal glyph per unit, so the
// glyph/character conversions are the identity and CoreText clusters stay internal.
// Coordinates are flipped (y down) as in AppKit's text system.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif

/// One laid-out line.
internal struct _NSLineFragment {
    var charRange: NSRange            // including a trailing newline, if any
    var newlineLength: Int            // 0, 1 or 2 (CR LF)
    var rect: NSRect                  // line fragment rect, container coordinates
    var usedRect: NSRect
    var container: Int
    var baseline: CGFloat             // from rect.minY
    var textX: CGFloat                // x of the CoreText line origin within the container
    var line: CTLine                  // string indices are `lineBase` less than document indices
    var drawnLine: CTLine             // truncated for the clipping modes, else `line`
    /// The document index of the line's string index 0: the start of the paragraph (or
    /// text block) it was typeset with, moved along with the text by later edits.
    var lineBase: Int
    var visibleEnd: Int { charRange.location + charRange.length - newlineLength }
    /// The x offset (from `textX`) of document index `i`.
    func offset(_ i: Int) -> CGFloat { CTLineGetOffsetForStringIndex(line, i - lineBase, nil) }
    /// The document index nearest `x` (from `textX`).
    func index(atX x: CGFloat) -> Int { CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0)) + lineBase }
}

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager
open class NSLayoutManager: NSObject, NSSecureCoding, NSCoding, NSGlyphStorage {
    private weak var _textStorage: NSTextStorage?
    private var _textContainers: [NSTextContainer] = []
    private var _temporary: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
    private var _fragments: [_NSLineFragment] = []
    private var _extraRect = NSRect.zero, _extraUsedRect = NSRect.zero
    private var _extraContainer: Int? = nil
    private var _layoutValid = false
    /// Whether the fragments' colours were resolved under a dark appearance; a draw under
    /// the other appearance lays out again (a text view's colour is dynamic).
    private var _layoutIsDark: Bool?
    private var _laidOutLength = 0
    private var _allowsNonContiguousLayout = false
    private var _backgroundLayoutEnabled = true
    private var _usesFontLeading = true
    private var _showsInvisibleCharacters = false
    private var _showsControlCharacters = false
    private var _hyphenationFactor: Float = 0
    private var _defaultAttachmentScaling: NSImageScaling = .scaleNone
    private var _typesetterBehavior: NSLayoutManager.TypesetterBehavior = .latestBehavior
    private var _limitsLayoutForSuspiciousContents = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/delegate
    open weak var delegate: (any NSLayoutManagerDelegate)?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/init()
    public override init() { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/init(coder:)
    public required init?(coder: NSCoder) { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/encode(with:)
    open func encode(with coder: NSCoder) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    // MARK: Text storage and containers

    internal func _setTextStorage(_ storage: NSTextStorage?) {
        _textStorage = storage
        _invalidateAll()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textstorage
    open var textStorage: NSTextStorage? {
        get { _textStorage }
        set {
            if let old = _textStorage, old !== newValue { old.removeLayoutManager(self) }
            if let new = newValue, new !== _textStorage { new.addLayoutManager(self) } else if newValue == nil { _setTextStorage(nil) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/replacetextstorage(_:)
    open func replaceTextStorage(_ newTextStorage: NSTextStorage) {
        let managers = _textStorage?.layoutManagers ?? [self]
        for lm in managers {
            lm._textStorage?.removeLayoutManager(lm)
            newTextStorage.addLayoutManager(lm)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textcontainers
    open var textContainers: [NSTextContainer] { _textContainers }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/addtextcontainer(_:)
    open func addTextContainer(_ container: NSTextContainer) { insertTextContainer(container, at: _textContainers.count) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/inserttextcontainer(_:at:)
    open func insertTextContainer(_ container: NSTextContainer, at index: Int) {
        _textContainers.insert(container, at: min(max(0, index), _textContainers.count))
        container._layoutManager = self
        _invalidateAll()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/removetextcontainer(at:)
    open func removeTextContainer(at index: Int) {
        guard _textContainers.indices.contains(index) else { return }
        let c = _textContainers.remove(at: index)
        if c._layoutManager === self { c._layoutManager = nil }
        _invalidateAll()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textcontainerchangedgeometry(_:)
    open func textContainerChangedGeometry(_ container: NSTextContainer) {
        _invalidateAll()
        delegate?.layoutManager(self, textContainer: container, didChangeGeometryFrom: container.size)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textcontainerchangedtextview(_:)
    open func textContainerChangedTextView(_ container: NSTextContainer) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/firsttextview
    open var firstTextView: NSTextView? { _textContainers.first?._textView }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textviewforbeginningofselection
    open var textViewForBeginningOfSelection: NSTextView? { firstTextView }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/layoutmanagerownsfirstresponder(in:)
    open func layoutManagerOwnsFirstResponder(in window: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            guard let fr = window.firstResponder as? NSTextView else { return false }
            return _textContainers.contains { $0._textView === fr }
        }
    }

    // MARK: Invalidation

    /// Drops every cached line: the next layout pass typesets the whole text.
    private func _invalidateAll() {
        _layoutValid = false
        _invalidations &+= 1
        // A pass is splicing into these arrays: it drops its work when it ends.
        if _inPass { return }
        _usedRects = [:]
        _units = []
        _attachments = [:]
        _fragments = []
        _blockFrames = []
        _laidOutLength = 0
        _extraContainer = nil
        delegate?.layoutManagerDidInvalidateLayout(self)
    }

    private func _redisplay() {
        MainActor.assumeIsolated {
            for c in _textContainers { c._textView?._layoutManagerDidChange() }
        }
    }

    /// The layout units an edit touches become one dirty unit and the units after it move
    /// by `delta`: `oldLength` characters at `location` became `oldLength + delta`. A unit
    /// that ends where the edit starts counts as touched (a line break typed or deleted
    /// there joins or splits it), and so does a text block next to the edit (a paragraph
    /// that joins or leaves a table changes where the table's run ends). Returns the dirty
    /// range, or nil when nothing is cached (the next pass lays everything out).
    @discardableResult
    private func _noteEdit(at location: Int, oldLength: Int, delta: Int) -> NSRange? {
        // During a pass `_units` is being rebuilt: the pass drops its work instead.
        if _inPass { _invalidateAll(); return nil }
        guard !_units.isEmpty else { return nil }
        let editEnd = location + oldLength
        // The first unit ending at or after the edit, the last starting at or before its end.
        var lo = 0, hi = _units.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if _units[mid].range.location + _units[mid].range.length < location { lo = mid + 1 } else { hi = mid }
        }
        var a = min(lo, _units.count - 1)
        lo = 0; hi = _units.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if _units[mid].range.location <= editEnd { lo = mid + 1 } else { hi = mid }
        }
        var b = max(a, lo - 1)
        if a > 0, _units[a - 1].isBlock { a -= 1 }
        if b + 1 < _units.count, _units[b + 1].isBlock { b += 1 }
        let start = _units[a].range.location
        let end = _units[b].range.location + _units[b].range.length + delta
        var fragments = 0, blockFrames = 0
        for k in a...b { fragments += _units[k].fragmentCount; blockFrames += _units[k].blockFrameCount }
        if delta != 0 {
            for k in (b + 1)..<_units.count { _units[k].range.location += delta }
            // Attachments after the edit move with their characters.
            if !_attachments.isEmpty {
                var moved: [Int: _NSLaidOutAttachment] = [:]
                for (i, v) in _attachments where i < location || i >= editEnd { moved[i >= editEnd ? i + delta : i] = v }
                _attachments = moved
            }
        }
        let dirty = NSRange(location: start, length: max(0, end - start))
        _units.replaceSubrange(a...b, with: [_LayoutUnit(dirty: dirty, fragmentCount: fragments, blockFrameCount: blockFrames)])
        return dirty
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/processediting(for:edited:range:changeinlength:invalidatedrange:)
    open func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        let charactersChanged = editMask.contains(.editedCharacters)
        // Temporary attributes that change layout and lose their text: their other paragraphs
        // lay out again too (in the edited text's coordinates).
        var dropped: [NSRange] = []
        if charactersChanged, delta != 0 {
            // Temporary attributes follow the text they decorate.
            let editEnd = newCharRange.location + newCharRange.length - delta
            _temporary = _temporary.compactMap { entry in
                var r = entry.range
                if r.location >= editEnd { r.location += delta }
                else if r.location + r.length > newCharRange.location {
                    if !entry.attrs.keys.allSatisfy(NSLayoutManager._displayOnlyKeys.contains) {
                        let end = r.location + r.length >= editEnd ? r.location + r.length + delta : newCharRange.location + newCharRange.length
                        let start = min(r.location, newCharRange.location)
                        dropped.append(NSRange(location: start, length: max(0, end - start)))
                    }
                    return nil
                }
                return r.length > 0 ? (r, entry.attrs) : nil
            }
        }
        let d = charactersChanged ? delta : 0
        _noteEdit(at: newCharRange.location, oldLength: max(0, newCharRange.length - d), delta: d)
        for r in dropped { _noteEdit(at: r.location, oldLength: r.length, delta: 0) }
        _layoutValid = false
        delegate?.layoutManagerDidInvalidateLayout(self)
        _redisplay()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textstorage(_:edited:range:changeinlength:invalidatedrange:)
    open func textStorage(_ str: NSTextStorage, edited editedMask: Int, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        processEditing(for: str, edited: NSTextStorageEditActions(rawValue: UInt(editedMask)), range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
    }
    /// The layout of the paragraphs around `charRange` (the text blocks they are in, whole)
    /// is discarded; the next layout pass typesets them again and moves the lines after them.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatelayout(forcharacterrange:actualcharacterrange:)
    open func invalidateLayout(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) {
        let r = _clampTemp(charRange)
        let dirty = _noteEdit(at: r.location, oldLength: r.length, delta: 0)
        actualCharRange?.pointee = dirty ?? NSRange(location: 0, length: _length)
        _layoutValid = false
        delegate?.layoutManagerDidInvalidateLayout(self)
    }
    /// Temporary attributes changed over `ranges`: their paragraphs lay out again.
    private func _invalidateLayout(for ranges: [NSRange]) {
        guard !ranges.isEmpty else { return }
        for r in ranges { _noteEdit(at: r.location, oldLength: r.length, delta: 0) }
        _layoutValid = false
        delegate?.layoutManagerDidInvalidateLayout(self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatelayout(forcharacterrange:issoft:actualcharacterrange:)
    open func invalidateLayout(forCharacterRange charRange: NSRange, isSoft flag: Bool, actualCharacterRange actualCharRange: NSRangePointer?) {
        invalidateLayout(forCharacterRange: charRange, actualCharacterRange: actualCharRange)
    }
    /// Glyphs are the characters (one per UTF-16 unit), so this invalidates the layout of
    /// the range; a length change outside an editing pass (which the text storage reports
    /// through `processEditing`) discards the whole layout.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidateglyphs(forcharacterrange:changeinlength:actualcharacterrange:)
    open func invalidateGlyphs(forCharacterRange charRange: NSRange, changeInLength delta: Int, actualCharacterRange actualCharRange: NSRangePointer?) {
        actualCharRange?.pointee = charRange
        if delta != 0 { _invalidateAll(); return }
        _noteEdit(at: charRange.location, oldLength: max(0, charRange.length), delta: 0)
        _layoutValid = false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidateglyphs(onlayoutinvalidationforglyphrange:)
    open func invalidateGlyphs(onLayoutInvalidationForGlyphRange glyphRange: NSRange) {
        _noteEdit(at: glyphRange.location, oldLength: max(0, glyphRange.length), delta: 0)
        _layoutValid = false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatedisplay(forcharacterrange:)
    open func invalidateDisplay(forCharacterRange charRange: NSRange) { _redisplay() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatedisplay(forglyphrange:)
    open func invalidateDisplay(forGlyphRange glyphRange: NSRange) { _redisplay() }

    // MARK: Layout

    private var _length: Int { _textStorage?.length ?? 0 }

    /// NSFont / NSColor attributes expressed for CoreText, with temporary attributes merged
    /// (the conversion TextKit 2 shares, ADR-0040), for the whole text.
    internal func _coreTextString() -> NSAttributedString {
        guard let storage = _textStorage else { return NSAttributedString(string: "") }
        let appearance: NSAppearance? = MainActor.assumeIsolated { firstTextView?.effectiveAppearance }
        let linkAttributes: [NSAttributedString.Key: Any]? = MainActor.assumeIsolated { firstTextView?.linkTextAttributes }
        let converted = _NSCoreTextConversion.convert(storage, range: NSRange(location: 0, length: storage.length), documentOffset: 0,
                                                      appearance: appearance, linkAttributes: linkAttributes, temporary: _temporary,
                                                      container: _textContainers.first, attachmentSizeOverrides: _attachmentSizeOverrides)
        return _masked(converted.string)
    }

    /// A secure field's text as its echo (run by run, so the attributes stay where they were).
    private func _masked(_ s: NSAttributedString) -> NSAttributedString {
        guard let echo = _secureEcho else { return s }
        let masked = NSMutableAttributedString(attributedString: s)
        let text = masked.string as NSString
        var runs: [NSRange] = []
        masked.enumerateAttributes(in: NSRange(location: 0, length: masked.length), options: []) { _, r, _ in runs.append(r) }
        for r in runs.reversed() {
            masked.replaceCharacters(in: r, with: _NSSecureEcho.mask(text.substring(with: r), with: echo))
        }
        return masked
    }

    /// Set on a secure field's editor (NSSecureTextField): the glyphs drawn for the text,
    /// one per character ("" draws nothing, for `echosBullets == false`). The storage keeps
    /// the real text; only what is laid out and drawn changes, keeping offsets one to one.
    internal var _secureEcho: String? {
        didSet { if _secureEcho != oldValue { _invalidateAll() } }
    }

    /// Attachments by character index: the attachment and its laid-out size and baseline offset.
    internal var _attachments: [Int: (attachment: NSTextAttachment, size: CGSize, baselineOffset: CGFloat)] = [:]
    private var _attachmentSizeOverrides: [Int: CGSize] = [:]
    private func _paragraphStyle(at index: Int) -> NSParagraphStyle? {
        guard let storage = _textStorage, storage.length > 0 else { return nil }
        return storage.attribute(.paragraphStyle, at: min(index, storage.length - 1), effectiveRange: nil) as? NSParagraphStyle
    }

    private func _font(at index: Int) -> NSFont {
        MainActor.assumeIsolated {
            if let storage = _textStorage, storage.length > 0, let f = storage.attribute(.font, at: min(index, storage.length - 1), effectiveRange: nil) as? NSFont { return f }
            if let tv = firstTextView, let f = tv.typingAttributes[.font] as? NSFont { return f }
            return NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
    }

    private func _newlineLength(at i: Int, in units: [UInt16]) -> Int { _NSLineTypesetter.newlineLength(at: i, in: units) }

    /// Where the next line goes while laying out (one column of text).
    private struct _Cursor {
        var container: Int
        var y: CGFloat
        var linesInContainer: Int
    }

    /// A unit of layout: one paragraph, or the paragraphs of one outermost text block or
    /// table, which lay out together. Its lines are the next `fragmentCount` of
    /// `_fragments` (and its boxes the next `blockFrameCount` of `_blockFrames`), in unit
    /// order. A pass that finds a unit clean moves its lines, in place, to where the unit now
    /// starts instead of typesetting it again, the way AppKit re-typesets only the paragraphs
    /// an edit invalidated. The units tile the text.
    private struct _LayoutUnit {
        var range: NSRange
        /// Edited or invalidated since it was laid out: the next pass typesets it.
        var dirty: Bool
        var isBlock = false
        /// Laid out at the top of the text (no space before its first paragraph).
        var atTop = false
        /// The document index its lines' character ranges start at (edits move `range` at
        /// once; a pass moves the lines).
        var origin = 0
        var start = _Cursor(container: 0, y: 0, linesInContainer: 0)
        var end = _Cursor(container: 0, y: 0, linesInContainer: 0)
        var fragmentCount = 0
        var blockFrameCount = 0

        init(dirty range: NSRange, fragmentCount: Int = 0, blockFrameCount: Int = 0) {
            self.range = range; dirty = true
            self.fragmentCount = fragmentCount; self.blockFrameCount = blockFrameCount
        }
        init(range: NSRange, isBlock: Bool, start: _Cursor, end: _Cursor, fragmentCount: Int, blockFrameCount: Int) {
            self.range = range; dirty = false; self.isBlock = isBlock; atTop = range.location == 0; origin = range.location
            self.start = start; self.end = end
            self.fragmentCount = fragmentCount; self.blockFrameCount = blockFrameCount
        }
    }
    private var _units: [_LayoutUnit] = []
    /// The container geometry `_units` were typeset in. A unit's lines hold only at that
    /// geometry: a pass that finds the containers changed lays every unit out again, however
    /// the change arrived (a container's size set while it had no layout manager, or an
    /// invalidation during a pass, which `_invalidateAll` alone could not undo).
    private var _unitsGeometry: [_ContainerGeometry] = []
    /// Bumped by `_invalidateAll`: a pass that sees it move while it runs drops its units.
    private var _invalidations = 0
    /// A pass is laying units out (until its lines are complete, before the delegate and
    /// the text views hear of them).
    private var _inPass = false

    private struct _ContainerGeometry: Equatable {
        var size: CGSize
        var padding: CGFloat
        var alignmentWidth: CGFloat?
        var lineBreakMode: NSLineBreakMode
        var maximumNumberOfLines: Int
        var exclusions: [CGRect]
        init(_ c: NSTextContainer) {
            size = c.size; padding = c.lineFragmentPadding; alignmentWidth = c._alignmentWidth
            lineBreakMode = c.lineBreakMode; maximumNumberOfLines = c.maximumNumberOfLines
            exclusions = c.exclusionPaths.map { p in MainActor.assumeIsolated { p.bounds } }
        }
    }
    /// Paragraphs typeset by layout passes, and units reused by moving them: tests bound the
    /// work an edit costs with these.
    internal var _typesetParagraphCount = 0
    internal var _reusedUnitCount = 0

    /// Reads the text a window at a time, to find where paragraphs end without copying the
    /// whole string (which corelibs' NSAttributedString.string does) on every edit.
    private struct _TextScanner {
        let storage: NSAttributedString
        let length: Int
        private var windowStart = 0
        private var window: [UInt16] = []
        init(_ storage: NSAttributedString) { self.storage = storage; length = storage.length }

        mutating func unit(at i: Int) -> UInt16 {
            if i < windowStart || i >= windowStart + window.count {
                windowStart = i
                window = Array(storage.attributedSubstring(from: NSRange(location: i, length: min(4096, length - i))).string.utf16)
            }
            return window[i - windowStart]
        }

        /// The end of the paragraph starting at `index` (after its line break), with the line
        /// typesetter's rules (LF, CR, CR LF, U+2028, U+2029, form feed).
        mutating func paragraphEnd(from index: Int) -> Int {
            var i = index
            while i < length {
                let u = unit(at: i)
                if u == 0x0D { return (i + 1 < length && unit(at: i + 1) == 0x0A) ? i + 2 : i + 1 }
                if u == 0x0A || u == 0x2028 || u == 0x2029 || u == 0x0C { return i + 1 }
                i += 1
            }
            return length
        }
    }

    /// The temporary attributes that change layout, handed to each unit's conversion as the
    /// pass walks the text forwards.
    private struct _TemporaryWalker {
        let sorted: [(range: NSRange, attrs: [NSAttributedString.Key: Any])]
        private var next = 0
        private var active: [(range: NSRange, attrs: [NSAttributedString.Key: Any])] = []
        init(_ temporary: [(range: NSRange, attrs: [NSAttributedString.Key: Any])]) {
            sorted = temporary.filter { !$0.attrs.keys.allSatisfy(NSLayoutManager._displayOnlyKeys.contains) }.sorted { $0.range.location < $1.range.location }
        }
        /// Those over `range`, clipped to it, in its own indices (ranges only move forwards).
        mutating func local(to range: NSRange) -> [(range: NSRange, attrs: [NSAttributedString.Key: Any])] {
            guard !sorted.isEmpty else { return [] }
            let end = range.location + range.length
            while next < sorted.count, sorted[next].range.location < end { active.append(sorted[next]); next += 1 }
            active.removeAll { $0.range.location + $0.range.length <= range.location }
            return active.compactMap { t in
                let lo = max(t.range.location, range.location), hi = min(t.range.location + t.range.length, end)
                return hi > lo ? (NSRange(location: lo - range.location, length: hi - lo), t.attrs) : nil
            }
        }
    }

    private func _ensureLayout() {
        // A text view fitting its frame to the new layout can change the wrapping width (a
        // scroll view shows its scroller and narrows the clip view), which invalidates the
        // layout again: lay out until it holds, so callers never read an emptied layout.
        // Asked from inside a pass (a callout it made): the lines so far are what there is.
        if _inPass { return }
        var passes = 0
        while !_layoutValid, passes < 4 {
            passes += 1
            _layoutPass()
        }
    }

    /// What a typesetter set on the laid-out glyphs (`setNotShownAttribute`, `setLocation`, …);
    /// the next layout pass recomputes the glyphs and drops them, as AppKit regenerates them.
    private var _notShownOverrides: [Int: Bool] = [:]
    private var _drawsOutsideOverrides: Set<Int> = []
    private var _intAttributes: [Int: [Int: Int]] = [:]
    private var _locationOverrides: [Int: NSPoint] = [:]

    /// Lays the text out unit by unit: clean units move to where they now start, dirty ones
    /// (and any whose surroundings changed) are typeset again and spliced into the lines.
    private func _layoutPass() {
        _layoutValid = true
        _usedRects = [:]
        _notShownOverrides = [:]; _drawsOutsideOverrides = []; _intAttributes = [:]; _locationOverrides = [:]
        _inPass = true
        defer { _inPass = false }
        var cached = _units
        _units = []
        _extraContainer = nil
        _laidOutLength = 0
        guard let storage = _textStorage, !_textContainers.isEmpty else {
            _fragments = []; _blockFrames = []; _attachments = [:]
            return
        }
        let length = storage.length
        // Semantic colours resolve under the text view's appearance (a dark field editor
        // draws light text), not whatever appearance happens to be current during layout.
        let appearance: NSAppearance? = MainActor.assumeIsolated { firstTextView?.effectiveAppearance }
        let isDark = appearance?.isDark ?? MainActor.assumeIsolated { NSAppearance.currentIsDark }
        // Links draw with the text view's link attributes (blue and underlined by default).
        let linkAttributes: [NSAttributedString.Key: Any]? = MainActor.assumeIsolated { firstTextView?.linkTextAttributes }
        // The cache holds when it covers this text and was resolved under this appearance.
        let cachedLength = cached.last.map { $0.range.location + $0.range.length } ?? 0
        let geometry = _textContainers.map(_ContainerGeometry.init)
        let inconsistency = _cacheInconsistency(cached)
        if let inconsistency { fputs("NSLayoutManager: cached layout is inconsistent (\(inconsistency)); laying everything out again\n", stderr) }
        if NSView._traceInvalidation, !cached.isEmpty, geometry != _unitsGeometry {
            _textTrace("layout manager geometry \(_unitsGeometry.map { $0.size.width }) -> \(geometry.map { $0.size.width }): every paragraph again")
        }
        if _layoutIsDark != isDark || cachedLength != length || _secureEcho != nil || geometry != _unitsGeometry
            || inconsistency != nil {
            cached = []
            _fragments = []; _blockFrames = []; _attachments = [:]
        }
        _layoutIsDark = isDark
        _unitsGeometry = geometry
        let invalidations = _invalidations
        let first = _textContainers[0]
        // In containers of bounded height (pages, columns, line limits) a unit's position
        // decides which container its lines land in: units are reused only up to the first
        // one typeset again.
        let bounded = _textContainers.count > 1 || first.size.height < CGFloat.greatestFiniteMagnitude / 2 || first.maximumNumberOfLines > 0
        var scanner = _TextScanner(storage)
        var temporary = _TemporaryWalker(_temporary)
        var cursor = _Cursor(container: 0, y: 0, linesInContainer: 0)
        // `_fragments[..<fi]` are laid out; the cached units not yet visited follow, in
        // order, after `drop` lines that units typeset again replace (likewise the boxes).
        var fi = 0, bi = 0, drop = 0, dropBoxes = 0
        _out = []; _outBlockFrames = []
        func splice() {
            guard drop > 0 || dropBoxes > 0 || !_out.isEmpty || !_outBlockFrames.isEmpty else { return }
            _fragments.replaceSubrange(fi..<min(_fragments.count, fi + drop), with: _out)
            _blockFrames.replaceSubrange(bi..<min(_blockFrames.count, bi + dropBoxes), with: _outBlockFrames)
            fi += _out.count; bi += _outBlockFrames.count
            drop = 0; dropBoxes = 0
            _out = []; _outBlockFrames = []
        }
        var index = 0, next = 0
        var typeset = false
        while index < length, cursor.container < _textContainers.count {
            // Cached units the new layout has passed are replaced by it.
            while next < cached.count, cached[next].range.location < index {
                drop += cached[next].fragmentCount; dropBoxes += cached[next].blockFrameCount
                next += 1
            }
            if next < cached.count, cached[next].range.location == index, !cached[next].dirty,
               (index == 0) == cached[next].atTop, cursor.container == cached[next].start.container,
               !bounded || (!typeset && cursor.y == cached[next].start.y && cursor.linesInContainer == cached[next].start.linesInContainer) {
                splice()
                let run = bounded ? next + 1 : _cleanRun(from: next, in: &cached, at: index, y: cursor.y)
                _place(cached[next..<run], fragmentsFrom: fi, blockFramesFrom: bi, at: index, y: cursor.y)
                let dy = cursor.y - cached[next].start.y, startLines = cached[next].start.linesInContainer
                for k in next..<run {
                    fi += cached[k].fragmentCount; bi += cached[k].blockFrameCount
                    cached[k].origin = cached[k].range.location
                    if dy != 0 { cached[k].start.y += dy; cached[k].end.y += dy }
                }
                let last = cached[run - 1]
                if bounded { cursor = last.end } else {
                    cursor.container = last.end.container
                    cursor.y = last.end.y
                    cursor.linesInContainer += last.end.linesInContainer - startLines
                }
                _reusedUnitCount += run - next
                index = last.range.location + last.range.length
                _units.append(contentsOf: cached[next..<run])
                next = run
                continue
            }
            typeset = true
            _precedingLines = fi > 0
            let (unit, stop) = _layoutUnit(from: index, scanner: &scanner, temporary: &temporary, appearance: appearance, linkAttributes: linkAttributes, cursor: &cursor)
            if stop < unit.range.location + unit.range.length {
                // The containers ran out inside the unit: its lines so far stay laid out,
                // the unit and the rest of the text wait for more room.
                index = unit.range.location
                _laidOutLength = stop
                break
            }
            _units.append(unit)
            index = stop
        }
        while next < cached.count { drop += cached[next].fragmentCount; dropBoxes += cached[next].blockFrameCount; next += 1 }
        splice()
        if fi < _fragments.count { _fragments.removeSubrange(fi...) }
        if bi < _blockFrames.count { _blockFrames.removeSubrange(bi...) }
        _inPass = false
        if NSView._traceInvalidation {
            _textTrace("layout manager pass widths \(geometry.map { $0.size.width }) units \(_units.count) lines \(_fragments.count) reused \(_reusedUnitCount)")
            // Whether the lines fit what the typesetter was given: the widest line, how many
            // reach past their container, and the first line with its text and width.
            let widest = _fragments.map(\.usedRect.maxX).max() ?? 0
            let over = _fragments.filter { $0.container < _textContainers.count && $0.usedRect.maxX > _textContainers[$0.container].size.width - _textContainers[$0.container].lineFragmentPadding + 0.5 }.count
            if let f = _fragments.first {
                let text = (storage.string as NSString).substring(with: f.charRange)
                _textTrace("layout manager lines widest used maxX \(widest) past the container \(over); first line chars \(f.charRange.length) used \(f.usedRect) rect \(f.rect) lineBreakMode container \(first.lineBreakMode.rawValue) style \(_paragraphStyle(at: 0)?.lineBreakMode.rawValue ?? -1) text \(text.debugDescription)")
            }
        }
        if _invalidations != invalidations {
            // Invalidated while it ran (something the pass called out to changed the
            // geometry): what it laid out holds for nothing, and the next pass starts over.
            _invalidateAll()
            return
        }
        if index < length {
            // What did not fit waits, dirty, for more room.
            if _laidOutLength == 0 { _laidOutLength = index }
            _units.append(_LayoutUnit(dirty: NSRange(location: index, length: length - index), fragmentCount: fi - _units.reduce(0) { $0 + $1.fragmentCount },
                                      blockFrameCount: bi - _units.reduce(0) { $0 + $1.blockFrameCount }))
            _finishPass(length: length)
            return
        }
        _laidOutLength = index
        _finishPass(length: length, cursor: cursor)
    }

    /// Lines a unit being typeset produces, spliced into `_fragments` after it (and its
    /// boxes, into `_blockFrames`).
    private var _out: [_NSLineFragment] = []
    private var _outBlockFrames: [_BlockFrame] = []
    /// Whether lines precede the unit being typeset (a paragraph's space before applies).
    private var _precedingLines = false

    /// The extra line fragment (after a trailing newline or for empty text), then the
    /// delegate and the text views hear the layout is complete.
    private func _finishPass(length: Int, cursor: _Cursor? = nil) {
        if let cursor, _laidOutLength >= length, cursor.container < _textContainers.count, length == 0 || _fragments.last?.newlineLength ?? 0 > 0 {
            let ci = cursor.container
            let container = _textContainers[ci]
            let font = _font(at: max(0, length - 1))
            let height = MainActor.assumeIsolated { (font.ascender - font.descender + font.leading).rounded(.up) }
            let top = _fragments.isEmpty ? 0 : cursor.y
            if container.size.height >= CGFloat.greatestFiniteMagnitude / 2 || top + height <= container.size.height || _fragments.isEmpty {
                _extraContainer = ci
                _extraRect = NSRect(x: 0, y: top, width: container.size.width, height: height)
                _extraUsedRect = NSRect(x: container.lineFragmentPadding, y: top, width: 0, height: height)
            }
        }
        for c in _textContainers { delegate?.layoutManager(self, didCompleteLayoutFor: c, atEnd: true) }
        MainActor.assumeIsolated {
            for c in _textContainers { c._textView?._layoutManagerDidLayout() }
        }
    }

    /// The end of the run of clean units from `start` that all move by the same amounts as
    /// it (no dirty unit, no edit, between them): one move places them all.
    private func _cleanRun(from start: Int, in units: inout [_LayoutUnit], at index: Int, y: CGFloat) -> Int {
        let dc = index - units[start].origin
        return units.withUnsafeBufferPointer { us in
            var k = start + 1
            while k < us.count, !us[k].dirty, !us[k].atTop, us[k].range.location - us[k].origin == dc,
                  us[k].start.y == us[k - 1].end.y, us[k].start.container == us[start].start.container { k += 1 }
            return k
        }
    }

    /// Clean units' lines (from `_fragments[fi]`, their boxes from `_blockFrames[bi]`),
    /// moved in place to document index `index` and y `y`, as the first of them moves.
    private func _place(_ units: ArraySlice<_LayoutUnit>, fragmentsFrom fi: Int, blockFramesFrom bi: Int, at index: Int, y: CGFloat) {
        guard let first = units.first else { return }
        let dc = index - first.origin, dy = y - first.start.y
        guard dc != 0 || dy != 0 else { return }
        var lines = 0, boxes = 0
        for u in units { lines += u.fragmentCount; boxes += u.blockFrameCount }
        _fragments.withUnsafeMutableBufferPointer { fs in
            for k in fi..<(fi + lines) {
                fs[k].charRange.location += dc; fs[k].lineBase += dc
                fs[k].rect.origin.y += dy; fs[k].usedRect.origin.y += dy
            }
        }
        guard boxes > 0 else { return }
        _blockFrames.withUnsafeMutableBufferPointer { bs in
            for k in bi..<(bi + boxes) {
                bs[k].charRange.location += dc
                bs[k].bounds.origin.y += dy; bs[k].layout.origin.y += dy
            }
        }
    }

    /// Typesets the unit starting at document index `index`: its paragraph, or the run of
    /// paragraphs in its outermost text block. Returns the unit and where layout stopped
    /// (its end, or earlier when the containers ran out).
    private func _layoutUnit(from index: Int, scanner: inout _TextScanner, temporary: inout _TemporaryWalker,
                             appearance: NSAppearance?, linkAttributes: [NSAttributedString.Key: Any]?, cursor: inout _Cursor) -> (_LayoutUnit, Int) {
        let storage = _textStorage!
        var isBlock = false
        let end: Int
        if _secureEcho != nil {
            end = scanner.length   // the echo is laid out as one piece, as it is drawn
        } else if let block = _paragraphStyle(at: index)?.textBlocks.first {
            isBlock = true
            let table = (block as? NSTextTableBlock)?.table
            var i = index
            repeat {
                i = scanner.paragraphEnd(from: i)
            } while i < scanner.length && {
                guard let b = _paragraphStyle(at: i)?.textBlocks.first else { return false }
                if let table { return (b as? NSTextTableBlock)?.table === table }
                return b === block
            }()
            end = i
        } else {
            end = scanner.paragraphEnd(from: index)
        }
        let range = NSRange(location: index, length: end - index)
        let start = cursor
        let firstFragment = _out.count, firstBlockFrame = _outBlockFrames.count
        let converted = _NSCoreTextConversion.convert(storage.attributedSubstring(from: range), range: NSRange(location: 0, length: range.length), documentOffset: index,
                                                      appearance: appearance, linkAttributes: linkAttributes, temporary: temporary.local(to: range),
                                                      container: _textContainers.first, attachmentSizeOverrides: _attachmentSizeOverrides)
        let ct = _masked(converted.string)
        let ts = CTTypesetterCreateWithAttributedString(ct)
        let units = Array(ct.string.utf16)
        var local = 0
        while local < units.count, cursor.container < _textContainers.count {
            let blocks = _paragraphStyle(at: index + local)?.textBlocks ?? []
            if let cell = blocks.first as? NSTextTableBlock {
                local = _layoutTable(cell.table, from: local, base: index, units: units, typesetter: ts, cursor: &cursor)
            } else if let block = blocks.first {
                local = _layoutBlock(block, from: local, base: index, units: units, typesetter: ts, cursor: &cursor)
            } else {
                let pEnd = _paragraphEnd(from: local, units: units)
                let container = _textContainers[cursor.container]
                let column = NSRect(x: 0, y: 0, width: container.size.width, height: container.size.height)
                local = _layoutLines(NSRange(location: local, length: pEnd - local), base: index, in: column, units: units, typesetter: ts, cursor: &cursor, breaksContainers: true)
            }
        }
        var p = 0
        while p < units.count { p = _paragraphEnd(from: p, units: units); _typesetParagraphCount += 1 }
        if !_attachments.isEmpty { for k in _attachments.keys where k >= index && k < end { _attachments[k] = nil } }
        for (k, v) in converted.attachments { _attachments[index + k] = v }
        let unit = _LayoutUnit(range: range, isBlock: isBlock, start: start, end: cursor,
                               fragmentCount: _out.count - firstFragment, blockFrameCount: _outBlockFrames.count - firstBlockFrame)
        return (unit, index + local)
    }

    /// The end of the paragraph starting at `index` (after its newline).
    private func _paragraphEnd(from index: Int, units: [UInt16]) -> Int { _NSLineTypesetter.paragraphEnd(from: index, units: units) }

    /// The paragraphs from `index` whose outermost text block satisfies `belongs` (indices
    /// into `units`, which start at document index `base`).
    private func _run(from index: Int, base: Int, units: [UInt16], while belongs: (NSTextBlock) -> Bool) -> Int {
        var i = index
        while i < units.count, let b = _paragraphStyle(at: base + i)?.textBlocks.first, belongs(b) { i = _paragraphEnd(from: i, units: units) }
        return max(i, _paragraphEnd(from: index, units: units))
    }

    /// Lays `range` (indices into `units`, the typesetter's text, which starts at document
    /// index `base`) out as lines inside `column` (container coordinates; the fragments are
    /// `column.width` wide at `column.minX`), from `cursor.y`. Returns where it stopped:
    /// the range's end, or earlier when the containers ran out.
    private func _layoutLines(_ range: NSRange, base: Int, in column: NSRect, units: [UInt16], typesetter ts: CTTypesetter, cursor: inout _Cursor, breaksContainers: Bool) -> Int {
        let end = range.location + range.length
        var index = range.location
        var paragraphStart = index == 0 || _newlineLength(at: index - 1, in: units) > 0 || (index >= 2 && units[index - 2] == 0x0D && units[index - 1] == 0x0A)
        var firstInColumn = true
        var column = column
        let typesetter = _nsTypesetter
        while index < end {
            guard cursor.container < _textContainers.count else { break }
            let container = _textContainers[cursor.container]
            let style = _paragraphStyle(at: base + index)
            typesetter._begin(layoutManager: self, container: container, style: style, paragraphStart: paragraphStart, at: base + index, units: units, base: base)
            let t = _NSLineTypesetter.line(typesetter: ts, units: units, index: index, end: end, style: style, paragraphStart: paragraphStart,
                                           columnMinX: column.minX, columnWidth: column.width, container: container, usesFontLeading: _usesFontLeading)
            let proposed = NSRect(x: column.minX, y: cursor.y, width: column.width, height: t.height)
            // Space before a paragraph, except at the top of the text or of a block's column.
            let spacingBefore = paragraphStart && (_precedingLines || !_out.isEmpty) && !(firstInColumn && !breaksContainers) ? typesetter.paragraphSpacing(beforeGlyphAt: base + index, withProposedLineFragmentRect: proposed) : 0
            let top = cursor.y + spacingBefore
            let maxLines = container.maximumNumberOfLines
            let overflow = (container.size.height < CGFloat.greatestFiniteMagnitude / 2 && top + t.height > container.size.height)
                || (maxLines > 0 && cursor.linesInContainer >= maxLines)
            if breaksContainers && overflow && cursor.linesInContainer > 0 {
                cursor.container += 1; cursor.y = 0; cursor.linesInContainer = 0
                if cursor.container < _textContainers.count { column.size.width = _textContainers[cursor.container].size.width }
                continue
            }
            // The typesetter may adjust the rects before they are stored (a subclass hook).
            var rect = NSRect(x: column.minX, y: top, width: column.width, height: t.height)
            var used = NSRect(x: t.textX, y: top, width: t.usedWidth, height: t.height)
            var baseline = t.ascent
            let lineRange = NSRange(location: base + index, length: t.count)
            typesetter.willSetLineFragmentRect(&rect, forGlyphRange: lineRange, usedRect: &used, baselineOffset: &baseline)
            let fragment = _NSLineFragment(charRange: lineRange, newlineLength: t.newlineLength,
                                           rect: rect, usedRect: used,
                                           container: cursor.container, baseline: baseline, textX: used.minX, line: t.line, drawnLine: t.drawnLine, lineBase: base)
            _out.append(fragment)
            typesetter.endLine(withGlyphRange: lineRange)
            if t.newlineLength > 0 { typesetter.endParagraph() }
            cursor.linesInContainer += 1
            firstInColumn = false
            cursor.y = rect.minY + rect.height + typesetter.lineSpacing(afterGlyphAt: base + index + t.count - 1, withProposedLineFragmentRect: rect)
            if t.newlineLength > 0 { cursor.y += typesetter.paragraphSpacing(afterGlyphAt: base + index + t.count - 1, withProposedLineFragmentRect: rect) }
            paragraphStart = t.newlineLength > 0
            index += t.count
        }
        typesetter._end()
        return index
    }

    // MARK: Text blocks and tables

    /// A block's box as laid out, for drawing its background and for `boundsRect(for:...)`.
    internal struct _BlockFrame {
        var block: NSTextBlock
        var bounds: NSRect
        var layout: NSRect
        var charRange: NSRange
        var container: Int
    }
    private var _blockFrames: [_BlockFrame] = []

    /// A plain text block: its paragraphs in the block's content rect, then the box around them.
    private func _layoutBlock(_ block: NSTextBlock, from index: Int, base: Int, units: [UInt16], typesetter ts: CTTypesetter, cursor: inout _Cursor) -> Int {
        let end = _run(from: index, base: base, units: units) { $0 === block }
        let chars = NSRange(location: base + index, length: end - index)
        let container = _textContainers[cursor.container]
        let outer = NSRect(x: 0, y: 0, width: container.size.width, height: CGFloat.greatestFiniteMagnitude / 4)
        let content = block.rectForLayout(at: NSPoint(x: 0, y: cursor.y), in: outer, textContainer: container, characterRange: chars)
        var inner = _Cursor(container: cursor.container, y: content.minY, linesInContainer: cursor.linesInContainer)
        let stop = _layoutLines(NSRange(location: index, length: end - index), base: base, in: content, units: units, typesetter: ts, cursor: &inner, breaksContainers: false)
        let used = NSRect(x: content.minX, y: content.minY, width: content.width, height: max(0, inner.y - content.minY))
        let bounds = block.boundsRect(forContentRect: used, in: outer, textContainer: container, characterRange: chars)
        _outBlockFrames.append(_BlockFrame(block: block, bounds: bounds, layout: content, charRange: NSRange(location: base + index, length: stop - index), container: cursor.container))
        cursor.y = bounds.maxY
        cursor.linesInContainer = inner.linesInContainer
        return stop
    }

    /// A table: the columns first (from the cells' natural widths), then row by row, each
    /// row's cells side by side and the row as tall as the tallest cell.
    private func _layoutTable(_ table: NSTextTable, from index: Int, base: Int, units: [UInt16], typesetter ts: CTTypesetter, cursor: inout _Cursor) -> Int {
        let end = _run(from: index, base: base, units: units) { ($0 as? NSTextTableBlock)?.table === table }
        // Cells: consecutive paragraphs with the same cell block (ranges in `units`).
        var cells: [(block: NSTextTableBlock, range: NSRange)] = []
        var i = index
        while i < end {
            let pEnd = _paragraphEnd(from: i, units: units)
            let b = (_paragraphStyle(at: base + i)?.textBlocks.first as? NSTextTableBlock) ?? NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
            if let last = cells.last, last.block === b {
                cells[cells.count - 1].range.length = pEnd - last.range.location
            } else {
                cells.append((b, NSRange(location: i, length: pEnd - i)))
            }
            i = pEnd
        }
        func chars(_ r: NSRange) -> NSRange { NSRange(location: base + r.location, length: r.length) }
        let container = _textContainers[cursor.container]
        let padding = container.lineFragmentPadding
        let outer = NSRect(x: 0, y: cursor.y, width: container.size.width, height: CGFloat.greatestFiniteMagnitude / 4)
        // Natural widths: each paragraph of the cell on one line.
        var natural: [ObjectIdentifier: (block: NSTextTableBlock, width: CGFloat)] = [:]
        for cell in cells {
            var w: CGFloat = 0
            var p = cell.range.location
            while p < cell.range.location + cell.range.length {
                let pEnd = _paragraphEnd(from: p, units: units)
                let line = CTTypesetterCreateLine(ts, CFRangeMake(p, pEnd - p))
                w = max(w, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)))
                p = pEnd
            }
            let basis = container.size.width
            w += 2 * padding + cell.block._inset(.minX, basis: basis) + cell.block._inset(.maxX, basis: basis)
            let key = ObjectIdentifier(cell.block)
            natural[key] = (cell.block, max(natural[key]?.width ?? 0, w.rounded(.up)))
        }
        table._layoutColumns(in: outer, natural: natural)
        let tableTop = cursor.y
        var rowTop = table._contentRect.minY
        var k = 0
        while k < cells.count {
            // A row: the cells sharing the first one's starting row.
            let row = cells[k].block.startingRow
            var r = k
            while r < cells.count, cells[r].block.startingRow == row { r += 1 }
            if r == k { r = k + 1 }
            var rowBottom = rowTop
            var laid: [(cell: Int, firstFragment: Int, bounds: NSRect, content: NSRect)] = []
            for c in k..<r {
                let cell = cells[c]
                let content = cell.block.rectForLayout(at: NSPoint(x: table._contentRect.minX, y: rowTop), in: outer, textContainer: container, characterRange: chars(cell.range))
                var inner = _Cursor(container: cursor.container, y: content.minY, linesInContainer: cursor.linesInContainer)
                let first = _out.count
                _ = _layoutLines(cell.range, base: base, in: content, units: units, typesetter: ts, cursor: &inner, breaksContainers: false)
                let used = NSRect(x: content.minX, y: content.minY, width: content.width, height: max(0, inner.y - content.minY))
                let bounds = cell.block.boundsRect(forContentRect: used, in: outer, textContainer: container, characterRange: chars(cell.range))
                rowBottom = max(rowBottom, bounds.maxY)
                laid.append((c, first, bounds, used))
            }
            // Every cell of the row is as tall as the row; vertical alignment moves its lines.
            for (n, entry) in laid.enumerated() {
                let cell = cells[entry.cell]
                var b = entry.bounds
                let slack = rowBottom - b.maxY
                b.size.height = rowBottom - b.minY
                let shift: CGFloat
                switch cell.block.verticalAlignment {
                case .middleAlignment: shift = (slack / 2).rounded()
                case .bottomAlignment: shift = slack
                default: shift = 0
                }
                let lastFragment = n + 1 < laid.count ? laid[n + 1].firstFragment : _out.count
                if shift != 0 {
                    for f in entry.firstFragment..<lastFragment {
                        _out[f].rect.origin.y += shift
                        _out[f].usedRect.origin.y += shift
                    }
                }
                _outBlockFrames.append(_BlockFrame(block: cell.block, bounds: b, layout: entry.content, charRange: chars(cell.range), container: cursor.container))
            }
            rowTop = rowBottom
            k = r
        }
        let tableChars = NSRange(location: base + index, length: end - index)
        let tableContent = NSRect(x: table._contentRect.minX, y: table._contentRect.minY, width: table._contentRect.width, height: max(0, rowTop - table._contentRect.minY))
        let tableBounds = table.boundsRect(forContentRect: tableContent, in: outer, textContainer: container, characterRange: tableChars)
        // The table's own box draws beneath its cells.
        _outBlockFrames.insert(_BlockFrame(block: table, bounds: tableBounds, layout: tableContent, charRange: tableChars, container: cursor.container),
                            at: _outBlockFrames.count - cells.count)
        cursor.y = max(tableBounds.maxY, tableTop)
        return end
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ensurelayout(for:)
    open func ensureLayout(for container: NSTextContainer) { _ensureLayout() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ensurelayout(forboundingrect:in:)
    open func ensureLayout(forBoundingRect bounds: NSRect, in container: NSTextContainer) { _ensureLayout() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ensurelayout(forcharacterrange:)
    open func ensureLayout(forCharacterRange charRange: NSRange) { _ensureLayout() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ensurelayout(forglyphrange:)
    open func ensureLayout(forGlyphRange glyphRange: NSRange) { _ensureLayout() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ensureglyphs(forcharacterrange:)
    open func ensureGlyphs(forCharacterRange charRange: NSRange) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ensureglyphs(forglyphrange:)
    open func ensureGlyphs(forGlyphRange glyphRange: NSRange) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/firstunlaidcharacterindex()
    open func firstUnlaidCharacterIndex() -> Int { _ensureLayout(); return _laidOutLength }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/firstunlaidglyphindex()
    open func firstUnlaidGlyphIndex() -> Int { firstUnlaidCharacterIndex() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/getfirstunlaidcharacterindex(_:glyphindex:)
    open func getFirstUnlaidCharacterIndex(_ charIndex: UnsafeMutablePointer<Int>?, glyphIndex: UnsafeMutablePointer<Int>?) {
        let i = firstUnlaidCharacterIndex()
        charIndex?.pointee = i
        glyphIndex?.pointee = i
    }

    // MARK: Fragment lookup

    /// The fragment holding character `index` (the one it starts in; after a trailing newline
    /// the index belongs to the next line or the extra fragment).
    internal func _fragmentIndex(forCharacter index: Int) -> Int? {
        _ensureLayout()
        guard !_fragments.isEmpty else { return nil }
        if index >= _laidOutLength {
            if _extraContainer != nil { return nil }
            return _fragments.count - 1
        }
        var lo = 0, hi = _fragments.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if _fragments[mid].charRange.location + _fragments[mid].charRange.length <= index { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    internal var _lineFragments: [_NSLineFragment] { _ensureLayout(); return _fragments }
    internal var _laidOutBlockFrames: [_BlockFrame] { _ensureLayout(); return _blockFrames }

    /// Why `units` cannot be reused over the current line arrays, or nil when they can: the
    /// units must tile the text from 0 in order, and own exactly the lines and boxes there
    /// are. A pass that finds the cache broken lays everything out again rather than moving
    /// lines that are not there (which traps).
    private func _cacheInconsistency(_ units: [_LayoutUnit]) -> String? {
        guard !units.isEmpty else { return nil }
        var at = 0, lines = 0, boxes = 0
        for (k, u) in units.enumerated() {
            if u.range.location != at || u.range.length < 0 { return "unit \(k) \(u.range) does not start at \(at)" }
            if u.fragmentCount < 0 || u.blockFrameCount < 0 { return "unit \(k) has negative counts" }
            at += u.range.length; lines += u.fragmentCount; boxes += u.blockFrameCount
        }
        if lines != _fragments.count { return "units own \(lines) lines, there are \(_fragments.count)" }
        if boxes != _blockFrames.count { return "units own \(boxes) boxes, there are \(_blockFrames.count)" }
        return nil
    }

    /// Tests: whether the laid-out units and lines are consistent with each other and with
    /// the text (nil), or what is wrong.
    internal var _layoutInconsistency: String? {
        _ensureLayout()
        if let why = _cacheInconsistency(_units) { return why }
        let length = _textStorage?.length ?? 0
        var at = 0
        for (k, f) in _fragments.enumerated() {
            if f.charRange.location != at { return "line \(k) \(f.charRange) does not start at \(at)" }
            at = f.charRange.location + f.charRange.length
        }
        if at != _laidOutLength || _laidOutLength > length { return "lines end at \(at), laid out \(_laidOutLength) of \(length)" }
        return nil
    }

    /// Caret x (container coordinates) for a character index, within its fragment.
    internal func _caret(forCharacter index: Int) -> (rect: NSRect, container: Int)? {
        _ensureLayout()
        guard let fi = _fragmentIndex(forCharacter: index) else {
            guard let ec = _extraContainer else { return nil }
            return (NSRect(x: _extraUsedRect.minX, y: _extraRect.minY, width: 1, height: _extraRect.height), ec)
        }
        let f = _fragments[fi]
        let i = min(index, f.visibleEnd)
        let x = f.textX + f.offset(i)
        return (NSRect(x: x, y: f.rect.minY, width: 1, height: f.rect.height), f.container)
    }

    // MARK: Glyph and character ranges (identity mapping)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/numberofglyphs
    open var numberOfGlyphs: Int { _length }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/isvalidglyphindex(_:)
    open func isValidGlyphIndex(_ glyphIndex: Int) -> Bool { glyphIndex >= 0 && glyphIndex < _length }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/characterindexforglyph(at:)
    open func characterIndexForGlyph(at glyphIndex: Int) -> Int { glyphIndex }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphindexforcharacter(at:)
    open func glyphIndexForCharacter(at charIndex: Int) -> Int { charIndex }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/characterrange(forglyphrange:actualglyphrange:)
    open func characterRange(forGlyphRange glyphRange: NSRange, actualGlyphRange: NSRangePointer?) -> NSRange {
        actualGlyphRange?.pointee = glyphRange
        return glyphRange
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphrange(forcharacterrange:actualcharacterrange:)
    open func glyphRange(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) -> NSRange {
        actualCharRange?.pointee = charRange
        return charRange
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyph(at:)
    open func glyph(at glyphIndex: Int) -> NSGlyph {
        guard let s = _textStorage, glyphIndex >= 0, glyphIndex < s.length else { return NSGlyph(0) }
        return NSGlyph((s.string as NSString).character(at: glyphIndex))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyph(at:isvalidindex:)
    open func glyph(at glyphIndex: Int, isValidIndex: UnsafeMutablePointer<ObjCBool>?) -> NSGlyph {
        isValidIndex?.pointee = ObjCBool(isValidGlyphIndex(glyphIndex))
        return glyph(at: glyphIndex)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/getglyphs(_:range:)
    open func getGlyphs(_ glyphArray: UnsafeMutablePointer<NSGlyph>?, range glyphRange: NSRange) -> Int {
        for i in 0..<glyphRange.length { glyphArray?[i] = glyph(at: glyphRange.location + i) }
        return glyphRange.length
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/propertyforglyph(at:)
    open func propertyForGlyph(at glyphIndex: Int) -> NSLayoutManager.GlyphProperty {
        guard let s = _textStorage, glyphIndex < s.length else { return [] }
        let u = (s.string as NSString).character(at: glyphIndex)
        if u == 0x0A || u == 0x0D || u == 0x09 || u == 0x2028 || u == 0x2029 { return .controlCharacter }
        return []
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/range(ofnominallyspacedglyphscontaining:)
    open func range(ofNominallySpacedGlyphsContaining glyphIndex: Int) -> NSRange {
        guard let fi = _fragmentIndex(forCharacter: glyphIndex) else { return NSRange(location: glyphIndex, length: 0) }
        return _fragments[fi].charRange
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/notshownattribute(forglyphat:)
    open func notShownAttribute(forGlyphAt glyphIndex: Int) -> Bool {
        _ensureLayout()
        return _notShownOverrides[glyphIndex] ?? propertyForGlyph(at: glyphIndex).contains(.controlCharacter)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/drawsoutsidelinefragment(forglyphat:)
    open func drawsOutsideLineFragment(forGlyphAt glyphIndex: Int) -> Bool { _ensureLayout(); return _drawsOutsideOverrides.contains(glyphIndex) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/truncatedglyphrange(inlinefragmentforglyphat:)
    open func truncatedGlyphRange(inLineFragmentForGlyphAt glyphIndex: Int) -> NSRange {
        guard let fi = _fragmentIndex(forCharacter: glyphIndex) else { return NSRange(location: NSNotFound, length: 0) }
        let f = _fragments[fi]
        if f.drawnLine === f.line { return NSRange(location: NSNotFound, length: 0) }
        let shown = CTLineGetGlyphCount(f.drawnLine) - 1
        return NSRange(location: f.charRange.location + shown, length: max(0, f.charRange.length - f.newlineLength - shown))
    }

    // MARK: Geometry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphrange(for:)
    open func glyphRange(for container: NSTextContainer) -> NSRange {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return NSRange(location: 0, length: 0) }
        // Lines run through the containers in order: the first and last in this one.
        guard let lo = _fragments.firstIndex(where: { $0.container == ci }), let hi = _fragments.lastIndex(where: { $0.container == ci }) else { return NSRange(location: _laidOutLength, length: 0) }
        let first = _fragments[lo], last = _fragments[hi]
        return NSRange(location: first.charRange.location, length: last.charRange.location + last.charRange.length - first.charRange.location)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textcontainer(forglyphat:effectiverange:)
    open func textContainer(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSTextContainer? {
        textContainer(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange, withoutAdditionalLayout: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textcontainer(forglyphat:effectiverange:withoutadditionallayout:)
    open func textContainer(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> NSTextContainer? {
        guard let fi = _fragmentIndex(forCharacter: glyphIndex) else {
            guard let ec = _extraContainer, _textContainers.indices.contains(ec) else { return nil }
            effectiveGlyphRange?.pointee = NSRange(location: _laidOutLength, length: 0)
            return _textContainers[ec]
        }
        let c = _textContainers[_fragments[fi].container]
        effectiveGlyphRange?.pointee = glyphRange(for: c)
        return c
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/linefragmentrect(forglyphat:effectiverange:)
    open func lineFragmentRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSRect {
        lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange, withoutAdditionalLayout: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/linefragmentrect(forglyphat:effectiverange:withoutadditionallayout:)
    open func lineFragmentRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> NSRect {
        guard let fi = _fragmentIndex(forCharacter: glyphIndex) else {
            effectiveGlyphRange?.pointee = NSRange(location: _laidOutLength, length: 0)
            return _extraContainer != nil ? _extraRect : .zero
        }
        effectiveGlyphRange?.pointee = _fragments[fi].charRange
        return _fragments[fi].rect
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/linefragmentusedrect(forglyphat:effectiverange:)
    open func lineFragmentUsedRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSRect {
        lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange, withoutAdditionalLayout: false)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/linefragmentusedrect(forglyphat:effectiverange:withoutadditionallayout:)
    open func lineFragmentUsedRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> NSRect {
        guard let fi = _fragmentIndex(forCharacter: glyphIndex) else {
            effectiveGlyphRange?.pointee = NSRange(location: _laidOutLength, length: 0)
            return _extraContainer != nil ? _extraUsedRect : .zero
        }
        effectiveGlyphRange?.pointee = _fragments[fi].charRange
        return _fragments[fi].usedRect
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/extralinefragmentrect
    open var extraLineFragmentRect: NSRect { _ensureLayout(); return _extraContainer != nil ? _extraRect : .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/extralinefragmentusedrect
    open var extraLineFragmentUsedRect: NSRect { _ensureLayout(); return _extraContainer != nil ? _extraUsedRect : .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/extralinefragmenttextcontainer
    open var extraLineFragmentTextContainer: NSTextContainer? {
        _ensureLayout()
        guard let ec = _extraContainer, _textContainers.indices.contains(ec) else { return nil }
        return _textContainers[ec]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/location(forglyphat:)
    open func location(forGlyphAt glyphIndex: Int) -> NSPoint {
        _ensureLayout()
        if let set = _locationOverrides[glyphIndex] { return set }
        guard let fi = _fragmentIndex(forCharacter: glyphIndex) else { return NSPoint(x: _extraUsedRect.minX, y: _extraRect.height) }
        let f = _fragments[fi]
        return NSPoint(x: f.textX + f.offset(min(glyphIndex, f.visibleEnd)), y: f.baseline)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/usedrect(for:)
    open func usedRect(for container: NSTextContainer) -> NSRect {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return .zero }
        if let known = _usedRects[ci] { return known }
        var r = NSRect.null
        // Plain comparisons over the lines (a union per line is most of a keystroke's cost
        // in a long document in a debug build).
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        _fragments.withUnsafeBufferPointer { lines in
            var i = 0
            while i < lines.count {
                if lines[i].container == ci {
                    let u = lines[i].usedRect
                    if u.origin.x < minX { minX = u.origin.x }
                    if u.origin.y < minY { minY = u.origin.y }
                    if u.origin.x + u.size.width > maxX { maxX = u.origin.x + u.size.width }
                    if u.origin.y + u.size.height > maxY { maxY = u.origin.y + u.size.height }
                }
                i += 1
            }
        }
        if minX <= maxX { r = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) }
        if _extraContainer == ci { r = r.union(_extraUsedRect) }
        // The union of the fragments' used rects, as AppKit reports it: its origin is the
        // leftmost glyph run, so right-aligned text in a wide container measures its own
        // width rather than the container's.
        let used = r.isNull ? .zero : NSRect(x: r.minX, y: 0, width: r.width, height: r.maxY)
        _usedRects[ci] = used
        return used
    }
    /// `usedRect(for:)` by container index, until the lines change.
    private var _usedRects: [Int: NSRect] = [:]
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/boundingrect(forglyphrange:in:)
    open func boundingRect(forGlyphRange glyphRange: NSRange, in container: NSTextContainer) -> NSRect {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return .zero }
        var result = NSRect.null
        let end = glyphRange.location + glyphRange.length
        for f in _fragments where f.container == ci {
            let fEnd = f.charRange.location + f.charRange.length
            guard f.charRange.location < max(end, glyphRange.location + 1), fEnd > glyphRange.location || (glyphRange.length == 0 && f.charRange.location == glyphRange.location) else { continue }
            let a = max(glyphRange.location, f.charRange.location), b = min(end, f.visibleEnd)
            let x0 = f.textX + f.offset(a)
            let x1 = f.textX + f.offset(max(a, b))
            result = result.union(NSRect(x: x0, y: f.rect.minY, width: max(1, x1 - x0), height: f.rect.height))
        }
        if result.isNull, _extraContainer == ci, glyphRange.location >= _laidOutLength { return NSRect(x: _extraUsedRect.minX, y: _extraRect.minY, width: 1, height: _extraRect.height) }
        return result.isNull ? .zero : result
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphrange(forboundingrect:in:)
    open func glyphRange(forBoundingRect bounds: NSRect, in container: NSTextContainer) -> NSRange {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return NSRange(location: 0, length: 0) }
        var lo = Int.max, hi = 0
        for f in _fragments where f.container == ci && f.rect.intersects(bounds) {
            lo = min(lo, f.charRange.location); hi = max(hi, f.charRange.location + f.charRange.length)
        }
        return lo == Int.max ? NSRange(location: 0, length: 0) : NSRange(location: lo, length: hi - lo)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphrange(forboundingrectwithoutadditionallayout:in:)
    open func glyphRange(forBoundingRectWithoutAdditionalLayout bounds: NSRect, in container: NSTextContainer) -> NSRange {
        glyphRange(forBoundingRect: bounds, in: container)
    }

    // MARK: Hit testing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphindex(for:in:)
    open func glyphIndex(for point: NSPoint, in container: NSTextContainer) -> Int {
        glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphindex(for:in:fractionofdistancethroughglyph:)
    open func glyphIndex(for point: NSPoint, in container: NSTextContainer, fractionOfDistanceThroughGlyph partialFraction: UnsafeMutablePointer<CGFloat>?) -> Int {
        _ensureLayout()
        partialFraction?.pointee = 0
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return 0 }
        let fs = _fragments.enumerated().filter { $0.element.container == ci }
        guard let first = fs.first else { return _laidOutLength }
        if point.y < first.element.rect.minY { return first.element.charRange.location }
        var chosen = first
        for f in fs where point.y >= f.element.rect.minY { chosen = f }
        // Side-by-side fragments (table cells): the one under the point, or the nearest in x.
        let row = fs.filter { point.y >= $0.element.rect.minY && point.y < $0.element.rect.maxY }
        if row.count > 1 {
            chosen = row.min { a, b in
                func d(_ r: NSRect) -> CGFloat { point.x < r.minX ? r.minX - point.x : point.x > r.maxX ? point.x - r.maxX : 0 }
                return d(a.element.rect) < d(b.element.rect)
            } ?? chosen
        }
        if let ec = _extraContainer, ec == ci, point.y >= _extraRect.minY { return _laidOutLength }
        let f = chosen.element
        let x = point.x - f.textX
        var index = f.index(atX: x)
        index = max(f.charRange.location, min(index, f.visibleEnd))
        // Fraction through the glyph the point is over (0 at its leading edge).
        if index < f.visibleEnd {
            let x0 = f.offset(index), x1 = f.offset(index + 1)
            if x1 > x0 { partialFraction?.pointee = max(0, min(1, (x - x0) / (x1 - x0))) }
        } else if index == f.visibleEnd, index > f.charRange.location {
            // Past the last glyph: report it with a fraction of 1 (caller rounds up).
            let x0 = f.offset(index - 1), x1 = f.offset(index)
            index -= 1
            partialFraction?.pointee = x1 > x0 ? max(0, min(1, (x - x0) / (x1 - x0))) : 1
        }
        return index
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/characterindex(for:in:fractionofdistancebetweeninsertionpoints:)
    open func characterIndex(for point: NSPoint, in container: NSTextContainer, fractionOfDistanceBetweenInsertionPoints partialFraction: UnsafeMutablePointer<CGFloat>?) -> Int {
        var fraction: CGFloat = 0
        let g = glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        partialFraction?.pointee = fraction
        return g
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/fractionofdistancethroughglyph(for:in:)
    open func fractionOfDistanceThroughGlyph(for point: NSPoint, in container: NSTextContainer) -> CGFloat {
        var f: CGFloat = 0
        _ = glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &f)
        return f
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/getlinefragmentinsertionpoints(forcharacterat:alternatepositions:indisplayorder:positions:characterindexes:)
    open func getLineFragmentInsertionPoints(forCharacterAt charIndex: Int, alternatePositions aFlag: Bool, inDisplayOrder dFlag: Bool, positions: UnsafeMutablePointer<CGFloat>?, characterIndexes charIndexes: UnsafeMutablePointer<Int>?) -> Int {
        guard let fi = _fragmentIndex(forCharacter: charIndex) else { return 0 }
        let f = _fragments[fi]
        var n = 0
        for i in f.charRange.location...f.visibleEnd {
            positions?[n] = f.textX + f.offset(i)
            charIndexes?[n] = i
            n += 1
        }
        return n
    }

    // MARK: Enumeration

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/enumeratelinefragments(forglyphrange:using:)
    open func enumerateLineFragments(forGlyphRange glyphRange: NSRange, using block: @escaping (NSRect, NSRect, NSTextContainer, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void) {
        _ensureLayout()
        var stop = ObjCBool(false)
        let end = glyphRange.location + glyphRange.length
        for f in _fragments where f.charRange.location < end && f.charRange.location + f.charRange.length > glyphRange.location {
            block(f.rect, f.usedRect, _textContainers[f.container], f.charRange, &stop)
            if stop.boolValue { return }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/enumerateenclosingrects(forglyphrange:withinselectedglyphrange:in:using:)
    open func enumerateEnclosingRects(forGlyphRange glyphRange: NSRange, withinSelectedGlyphRange selectedRange: NSRange, in textContainer: NSTextContainer, using block: @escaping (NSRect, UnsafeMutablePointer<ObjCBool>) -> Void) {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === textContainer }) else { return }
        var stop = ObjCBool(false)
        let end = glyphRange.location + glyphRange.length
        for f in _fragments where f.container == ci && f.charRange.location < end && f.charRange.location + f.charRange.length > glyphRange.location {
            let a = max(glyphRange.location, f.charRange.location)
            let b = min(end, f.visibleEnd)
            let x0 = f.textX + f.offset(a)
            var x1 = f.textX + f.offset(max(a, b))
            // A selected line break extends the highlight to the container's edge.
            if end > f.visibleEnd && f.newlineLength > 0 { x1 = max(x1, f.rect.maxX - textContainer.lineFragmentPadding) }
            block(NSRect(x: x0, y: f.rect.minY, width: max(0, x1 - x0), height: f.rect.height), &stop)
            if stop.boolValue { return }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/rectarray(forcharacterrange:withinselectedcharacterrange:in:rectcount:)
    open func rectArray(forCharacterRange charRange: NSRange, withinSelectedCharacterRange selCharRange: NSRange, in container: NSTextContainer, rectCount: UnsafeMutablePointer<Int>) -> NSRectArray? {
        rectArray(forGlyphRange: charRange, withinSelectedGlyphRange: selCharRange, in: container, rectCount: rectCount)
    }
    private var _rectBuffer: UnsafeMutablePointer<NSRect>? = nil
    private var _rectBufferCount = 0
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/rectarray(forglyphrange:withinselectedglyphrange:in:rectcount:)
    open func rectArray(forGlyphRange glyphRange: NSRange, withinSelectedGlyphRange selGlyphRange: NSRange, in container: NSTextContainer, rectCount: UnsafeMutablePointer<Int>) -> NSRectArray? {
        var rects: [NSRect] = []
        enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: selGlyphRange, in: container) { r, _ in rects.append(r) }
        rectCount.pointee = rects.count
        guard !rects.isEmpty else { return nil }
        if _rectBufferCount < rects.count {
            _rectBuffer?.deallocate()
            _rectBuffer = UnsafeMutablePointer<NSRect>.allocate(capacity: rects.count)
            _rectBufferCount = rects.count
        }
        for (i, r) in rects.enumerated() { _rectBuffer![i] = r }
        return _rectBuffer
    }
    deinit { _rectBuffer?.deallocate() }

    // MARK: Drawing

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/drawbackground(forglyphrange:at:)
    open func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        _ensureLayout()
        MainActor.assumeIsolated {
            guard let storage = _textStorage, let ctx = NSGraphicsContext.current else { return }
            // Text blocks and table cells, outermost first.
            if !_blockFrames.isEmpty {
                let end = glyphsToShow.location + glyphsToShow.length
                let view: NSView = firstTextView ?? NSView(frame: .zero)
                for b in _blockFrames where b.charRange.location < max(end, glyphsToShow.location + 1) && b.charRange.location + b.charRange.length > glyphsToShow.location {
                    b.block.drawBackground(withFrame: b.bounds.offsetBy(dx: origin.x, dy: origin.y), in: view, characterRange: b.charRange, layoutManager: self)
                }
            }
            for t in _temporary {
                guard let color = t.attrs[.backgroundColor] as? NSColor, let container = textContainer(forGlyphAt: t.range.location, effectiveRange: nil) else { continue }
                color.setFill()
                enumerateEnclosingRects(forGlyphRange: t.range, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { r, _ in
                    NSBezierPath.fill(r.offsetBy(dx: origin.x, dy: origin.y))
                }
            }
            // Background colour attribute runs.
            let end = min(storage.length, glyphsToShow.location + glyphsToShow.length)
            if end > glyphsToShow.location {
                storage.enumerateAttribute(.backgroundColor, in: NSRange(location: glyphsToShow.location, length: end - glyphsToShow.location), options: []) { value, range, _ in
                    guard let color = value as? NSColor, let container = textContainer(forGlyphAt: range.location, effectiveRange: nil) else { return }
                    color.setFill()
                    enumerateEnclosingRects(forGlyphRange: range, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { r, _ in
                        NSBezierPath.fill(r.offsetBy(dx: origin.x, dy: origin.y))
                    }
                }
            }
            // The selection of the first text view.
            if let tv = firstTextView, let container = tv.textContainer, tv.selectedRange.length > 0 {
                let sel = tv.selectedRange
                let shown = NSRange(location: max(sel.location, glyphsToShow.location), length: 0)
                let shownEnd = min(sel.location + sel.length, glyphsToShow.location + glyphsToShow.length)
                if shownEnd > shown.location {
                    tv._selectionHighlightColor.setFill()
                    enumerateEnclosingRects(forGlyphRange: NSRange(location: shown.location, length: shownEnd - shown.location), withinSelectedGlyphRange: sel, in: container) { r, _ in
                        NSBezierPath.fill(r.offsetBy(dx: origin.x, dy: origin.y))
                    }
                }
            }
            _ = ctx
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/drawglyphs(forglyphrange:at:)
    open func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        MainActor.assumeIsolated {
            // Laid out (measured) under one appearance, drawn under another: resolve again
            // (a text view printing from a dark window lays its colours out light for the
            // page, and dark again for the screen).
            // (the pass sees the appearance changed and typesets every unit again).
            if let dark = _layoutIsDark, dark != (firstTextView?.effectiveAppearance.isDark ?? NSAppearance.currentIsDark) { _layoutValid = false }
        }
        _ensureLayout()
        MainActor.assumeIsolated {
            guard let gc = NSGraphicsContext.current else { return }
            let ctx = gc.cgContext
            let flipped = gc.isFlipped
            let end = glyphsToShow.location + glyphsToShow.length
            for f in _fragments where f.charRange.location < end && f.charRange.location + f.charRange.length > glyphsToShow.location {
                ctx.saveGState()
                ctx.translateBy(x: origin.x + f.textX, y: origin.y + f.rect.minY + f.baseline)
                if flipped { ctx.scaleBy(x: 1, y: -1) }
                ctx.textPosition = .zero
                CTLineDraw(f.drawnLine, ctx)
                ctx.restoreGState()
            }
            _drawAttachments(forGlyphRange: glyphsToShow, at: origin)
            _drawStrikethroughs(forGlyphRange: glyphsToShow, at: origin)
            _drawSpellingMarks(forGlyphRange: glyphsToShow, at: origin)
        }
    }

    /// CoreText draws underlines from the line's attributes; strikethrough is the layout
    /// manager's to draw (as AppKit's does), one stroke per fragment in the text colour.
    @MainActor private func _drawStrikethroughs(forGlyphRange range: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let whole = NSIntersectionRange(NSRange(location: 0, length: storage.length), range)
        guard whole.length > 0 else { return }
        storage.enumerateAttribute(.strikethroughStyle, in: whole, options: []) { value, run, _ in
            guard let style = (value as? NSNumber)?.intValue ?? (value as? Int), style != 0 else { return }
            let attrs = storage.attributes(at: run.location, effectiveRange: nil)
            let color = (attrs[.strikethroughColor] as? NSColor) ?? (attrs[.foregroundColor] as? NSColor) ?? NSColor.textColor
            color.setFill()
            var at = run.location
            let end = run.location + run.length
            while at < end, let fi = _fragmentIndex(forCharacter: at) {
                let f = _fragments[fi]
                let stop = min(end, f.visibleEnd)
                guard stop > at else { break }
                drawStrikethrough(forGlyphRange: NSRange(location: at, length: stop - at), strikethroughType: NSUnderlineStyle(rawValue: style),
                                  baselineOffset: f.baseline, lineFragmentRect: f.rect, lineFragmentGlyphRange: f.charRange, containerOrigin: origin)
                at = max(stop, f.charRange.location + f.charRange.length)
            }
        }
    }

    /// The rect an attachment occupies (container coordinates, flipped), from its line.
    internal func _attachmentRect(at index: Int) -> NSRect? {
        // The fragment lookup lays the text out, which fills the attachment table.
        guard let fi = _fragmentIndex(forCharacter: index), let a = _attachments[index] else { return nil }
        let f = _fragments[fi]
        let x = f.textX + f.offset(index)
        let baselineY = f.rect.minY + f.baseline
        return NSRect(x: x, y: baselineY - a.size.height - a.baselineOffset, width: a.size.width, height: a.size.height)
    }

    @MainActor private func _drawAttachments(forGlyphRange range: NSRange, at origin: NSPoint) {
        guard !_attachments.isEmpty else { return }
        let end = range.location + range.length
        let view = firstTextView
        let sel = view?.selectedRange ?? NSRange(location: NSNotFound, length: 0)
        for (index, entry) in _attachments where index >= range.location && index < end {
            guard let r = _attachmentRect(at: index), r.width > 0 || r.height > 0 else { continue }
            let rect = r.offsetBy(dx: origin.x, dy: origin.y)
            let selected = sel.location != NSNotFound && index >= sel.location && index < sel.location + sel.length
            if let cell = entry.attachment.attachmentCell as? NSCell, !(cell is NSTextAttachmentCell) {
                showAttachmentCell(cell, in: rect, characterIndex: index)
            } else {
                entry.attachment._draw(in: rect, characterIndex: index, layoutManager: self, view: view, selected: selected)
            }
        }
    }

    /// Misspelled words (temporary `.spellingState`) get AppKit's dotted underline: red for
    /// spelling, green for grammar.
    @MainActor private func _drawSpellingMarks(forGlyphRange range: NSRange, at origin: NSPoint) {
        guard !NSGraphicsContext._printing else { return }   // screen-only, as in AppKit
        let marks = _temporary.filter { ($0.attrs[.spellingState] as? NSNumber)?.intValue ?? 0 != 0 }
        guard !marks.isEmpty else { return }
        let end = range.location + range.length
        for m in marks where m.range.location < end && m.range.location + m.range.length > range.location {
            let state = (m.attrs[.spellingState] as? NSNumber)?.intValue ?? 1
            (state & 2 != 0 && state & 1 == 0 ? NSColor.systemGreen : NSColor.systemRed).setFill()
            // From the mark's own fragment (a pass over every fragment per mark made drawing a
            // long, misspelt document quadratic).
            guard var fi = _fragmentIndex(forCharacter: m.range.location) else { continue }
            while fi < _fragments.count, _fragments[fi].charRange.location < m.range.location + m.range.length {
                let f = _fragments[fi]
                fi += 1
                guard f.visibleEnd > m.range.location else { continue }
                let a = max(m.range.location, f.charRange.location), b = min(m.range.location + m.range.length, f.visibleEnd)
                guard b > a else { continue }
                let x0 = f.textX + f.offset(a), x1 = f.textX + f.offset(b)
                let y = origin.y + f.rect.minY + f.baseline + 2
                var x = origin.x + x0
                while x < origin.x + x1 {
                    NSBezierPath.fill(NSRect(x: x, y: y, width: min(2, origin.x + x1 - x), height: 2))
                    x += 3
                }
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/fillbackgroundrectarray(_:count:forcharacterrange:color:)
    open func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        MainActor.assumeIsolated {
            color.setFill()
            for i in 0..<rectCount { NSBezierPath.fill(rectArray[i]) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/drawunderline(forglyphrange:underlinetype:baselineoffset:linefragmentrect:linefragmentglyphrange:containerorigin:)
    open func drawUnderline(forGlyphRange glyphRange: NSRange, underlineType underlineVal: NSUnderlineStyle, baselineOffset: CGFloat, lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        guard underlineVal.rawValue != 0, let fi = _fragmentIndex(forCharacter: glyphRange.location) else { return }
        let f = _fragments[fi]
        let a = max(glyphRange.location, f.charRange.location), b = min(glyphRange.location + glyphRange.length, f.visibleEnd)
        guard b > a else { return }
        let x0 = f.textX + f.offset(a), x1 = f.textX + f.offset(b)
        let thickness: CGFloat = underlineVal.contains(.thick) ? 2 : 1
        MainActor.assumeIsolated {
            NSBezierPath.fill(NSRect(x: containerOrigin.x + x0, y: containerOrigin.y + lineRect.minY + baselineOffset + 1, width: x1 - x0, height: thickness))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/underlineglyphrange(_:underlinetype:linefragmentrect:linefragmentglyphrange:containerorigin:)
    open func underlineGlyphRange(_ glyphRange: NSRange, underlineType underlineVal: NSUnderlineStyle, lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        guard let fi = _fragmentIndex(forCharacter: glyphRange.location) else { return }
        drawUnderline(forGlyphRange: glyphRange, underlineType: underlineVal, baselineOffset: _fragments[fi].baseline, lineFragmentRect: lineRect, lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/drawstrikethrough(forglyphrange:strikethroughtype:baselineoffset:linefragmentrect:linefragmentglyphrange:containerorigin:)
    open func drawStrikethrough(forGlyphRange glyphRange: NSRange, strikethroughType strikethroughVal: NSUnderlineStyle, baselineOffset: CGFloat, lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        guard strikethroughVal.rawValue != 0, let fi = _fragmentIndex(forCharacter: glyphRange.location) else { return }
        let f = _fragments[fi]
        let a = max(glyphRange.location, f.charRange.location), b = min(glyphRange.location + glyphRange.length, f.visibleEnd)
        guard b > a else { return }
        let x0 = f.textX + f.offset(a), x1 = f.textX + f.offset(b)
        let font = _font(at: a)
        MainActor.assumeIsolated {
            NSBezierPath.fill(NSRect(x: containerOrigin.x + x0, y: containerOrigin.y + lineRect.minY + baselineOffset - font.xHeight / 2, width: x1 - x0, height: 1))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/strikethroughglyphrange(_:strikethroughtype:linefragmentrect:linefragmentglyphrange:containerorigin:)
    open func strikethroughGlyphRange(_ glyphRange: NSRange, strikethroughType strikethroughVal: NSUnderlineStyle, lineFragmentRect lineRect: NSRect, lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        guard let fi = _fragmentIndex(forCharacter: glyphRange.location) else { return }
        drawStrikethrough(forGlyphRange: glyphRange, strikethroughType: strikethroughVal, baselineOffset: _fragments[fi].baseline, lineFragmentRect: lineRect, lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/showattachmentcell(_:in:characterindex:)
    open func showAttachmentCell(_ cell: NSCell, in rect: NSRect, characterIndex attachmentIndex: Int) {
        MainActor.assumeIsolated { if let v = firstTextView { cell.draw(withFrame: rect, in: v) } }
    }

    // MARK: Temporary attributes

    private func _clampTemp(_ r: NSRange) -> NSRange {
        let n = _length
        let loc = min(max(0, r.location), n)
        return NSRange(location: loc, length: min(max(0, r.length), n - loc))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/temporaryattributes(atcharacterindex:effectiverange:)
    open func temporaryAttributes(atCharacterIndex charIndex: Int, effectiveRange effectiveCharRange: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        var out: [NSAttributedString.Key: Any] = [:]
        var lo = 0, hi = _length
        for t in _temporary {
            if t.range.location <= charIndex && charIndex < t.range.location + t.range.length {
                for (k, v) in t.attrs { out[k] = v }
                lo = max(lo, t.range.location); hi = min(hi, t.range.location + t.range.length)
            } else if t.range.location > charIndex { hi = min(hi, t.range.location) }
            else { lo = max(lo, t.range.location + t.range.length) }
        }
        effectiveCharRange?.pointee = NSRange(location: lo, length: max(0, hi - lo))
        return out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/temporaryattributes(atcharacterindex:longesteffectiverange:in:)
    open func temporaryAttributes(atCharacterIndex location: Int, longestEffectiveRange range: NSRangePointer?, in rangeLimit: NSRange) -> [NSAttributedString.Key: Any] {
        var r = NSRange()
        let a = temporaryAttributes(atCharacterIndex: location, effectiveRange: &r)
        range?.pointee = NSIntersectionRange(r, rangeLimit)
        return a
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/temporaryattribute(_:atcharacterindex:effectiverange:)
    open func temporaryAttribute(_ attrName: NSAttributedString.Key, atCharacterIndex location: Int, effectiveRange range: NSRangePointer?) -> Any? {
        temporaryAttributes(atCharacterIndex: location, effectiveRange: range)[attrName]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/temporaryattribute(_:atcharacterindex:longesteffectiverange:in:)
    open func temporaryAttribute(_ attrName: NSAttributedString.Key, atCharacterIndex location: Int, longestEffectiveRange range: NSRangePointer?, in rangeLimit: NSRange) -> Any? {
        temporaryAttributes(atCharacterIndex: location, longestEffectiveRange: range, in: rangeLimit)[attrName]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/settemporaryattributes(_:forcharacterrange:)
    open func setTemporaryAttributes(_ attrs: [NSAttributedString.Key: Any], forCharacterRange charRange: NSRange) {
        let r = _clampTemp(charRange)
        let replaced = _temporary.filter { NSIntersectionRange($0.range, r).length > 0 || ($0.range.length == 0) }
        _temporary.removeAll { NSIntersectionRange($0.range, r).length > 0 || ($0.range.length == 0) }
        if r.length > 0, !attrs.isEmpty { _temporary.append((r, attrs)) }
        // Attributes that change layout (a colour, a font) lay their paragraphs out again.
        var changed = replaced.filter { !$0.attrs.keys.allSatisfy(NSLayoutManager._displayOnlyKeys.contains) }.map(\.range)
        if !attrs.keys.allSatisfy(NSLayoutManager._displayOnlyKeys.contains) { changed.append(r) }
        _invalidateLayout(for: changed)
        _redisplay()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/addtemporaryattributes(_:forcharacterrange:)
    open func addTemporaryAttributes(_ attrs: [NSAttributedString.Key: Any] = [:], forCharacterRange charRange: NSRange) {
        let r = _clampTemp(charRange)
        guard r.length > 0 else { return }
        var merged = temporaryAttributes(atCharacterIndex: r.location, effectiveRange: nil)
        for (k, v) in attrs { merged[k] = v }
        setTemporaryAttributes(merged, forCharacterRange: r)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/addtemporaryattribute(_:value:forcharacterrange:)
    open func addTemporaryAttribute(_ attrName: NSAttributedString.Key, value: Any, forCharacterRange charRange: NSRange) {
        addTemporaryAttributes([attrName: value], forCharacterRange: charRange)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/removetemporaryattribute(_:forcharacterrange:)
    /// Temporary attributes drawn over the laid-out text without changing its layout.
    private static let _displayOnlyKeys: Set<NSAttributedString.Key> = [.spellingState, .backgroundColor]

    open func removeTemporaryAttribute(_ attrName: NSAttributedString.Key, forCharacterRange charRange: NSRange) {
        let r = _clampTemp(charRange)
        _temporary = _temporary.compactMap { t in
            guard NSIntersectionRange(t.range, r).length > 0 else { return t }
            var a = t.attrs
            a[attrName] = nil
            return a.isEmpty ? nil : (t.range, a)
        }
        if !NSLayoutManager._displayOnlyKeys.contains(attrName) { _invalidateLayout(for: [r]) }
        _redisplay()
    }

    // MARK: Fonts

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/defaultlineheight(for:)
    open func defaultLineHeight(for theFont: NSFont) -> CGFloat {
        MainActor.assumeIsolated { (theFont.ascender - theFont.descender + (_usesFontLeading ? theFont.leading : 0)).rounded(.up) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/defaultbaselineoffset(for:)
    open func defaultBaselineOffset(for theFont: NSFont) -> CGFloat { MainActor.assumeIsolated { theFont.ascender } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/substitutefont(for:)
    open func substituteFont(for originalFont: NSFont) -> NSFont { originalFont }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/usesdefaulthyphenation
    open var usesDefaultHyphenation: Bool {
        get { _usesDefaultHyphenation }
        set { _usesDefaultHyphenation = newValue }
    }
    private var _usesDefaultHyphenation = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/usesscreenfonts
    open var usesScreenFonts: Bool {
        get { _usesScreenFonts }
        set { _usesScreenFonts = newValue }
    }
    private var _usesScreenFonts = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/usesfontleading
    open var usesFontLeading: Bool {
        get { _usesFontLeading }
        set { _usesFontLeading = newValue; _invalidateAll() }
    }

    // MARK: Settings

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/allowsnoncontiguouslayout
    open var allowsNonContiguousLayout: Bool { get { _allowsNonContiguousLayout } set { _allowsNonContiguousLayout = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/hasnoncontiguouslayout
    open var hasNonContiguousLayout: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/backgroundlayoutenabled
    open var backgroundLayoutEnabled: Bool { get { _backgroundLayoutEnabled } set { _backgroundLayoutEnabled = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/defaultattachmentscaling
    open var defaultAttachmentScaling: NSImageScaling { get { _defaultAttachmentScaling } set { _defaultAttachmentScaling = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/hyphenationfactor
    open var hyphenationFactor: Float { get { _hyphenationFactor } set { _hyphenationFactor = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/limitslayoutforsuspiciouscontents
    open var limitsLayoutForSuspiciousContents: Bool { get { _limitsLayoutForSuspiciousContents } set { _limitsLayoutForSuspiciousContents = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/showscontrolcharacters
    open var showsControlCharacters: Bool { get { _showsControlCharacters } set { _showsControlCharacters = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/showsinvisiblecharacters
    open var showsInvisibleCharacters: Bool { get { _showsInvisibleCharacters } set { _showsInvisibleCharacters = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/typesetterbehavior
    open var typesetterBehavior: NSLayoutManager.TypesetterBehavior { get { _typesetterBehavior } set { _typesetterBehavior = newValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/typesetter
    open var typesetter: NSTypesetter {
        get { _nsTypesetter }
        set { _nsTypesetter = newValue; _invalidateAll() }
    }
    /// The NSTypesetter asked for spacing while laying out (ADR-0040).
    private var _nsTypesetter: NSTypesetter = NSATSTypesetter.shared
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphgenerator
    open var glyphGenerator: NSGlyphGenerator {
        get { unimplemented("NSLayoutManager.glyphGenerator — glyphs come from CoreText line by line; NSGlyphGenerator is a generated stub with no glyph storage to drive") }
        set { unimplemented("NSLayoutManager.glyphGenerator — glyphs come from CoreText line by line; NSGlyphGenerator is a generated stub with no glyph storage to drive") }
    }

    // MARK: Glyph storage (NSGlyphStorage) and manual layout: not used by the CoreText typesetter

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/attributedstring()
    open func attributedString() -> NSAttributedString { _textStorage ?? NSAttributedString(string: "") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/layoutoptions()
    open func layoutOptions() -> Int { 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/insertglyphs(_:length:forstartingglyphat:characterindex:)
    open func insertGlyphs(_ glyphs: UnsafePointer<NSGlyph>, length: Int, forStartingGlyphAt glyphIndex: Int, characterIndex charIndex: Int) { unimplemented("NSLayoutManager.insertGlyphs — the port keeps one glyph per character (CoreText shapes each line when it is drawn), so there is no glyph storage to edit") }
    // The manual-layout setters below are what a typesetter calls while laying out. The
    // port's CoreText layout has already placed the glyphs; a value set here replaces the
    // laid-out one in the queries until the next layout pass recomputes it (as AppKit's next
    // typesetting pass would). Drawing still follows the CoreText lines.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setintattribute(_:value:forglyphat:)
    open func setIntAttribute(_ attributeTag: Int, value val: Int, forGlyphAt glyphIndex: Int) {
        _ensureLayout()
        _intAttributes[glyphIndex, default: [:]][attributeTag] = val
    }
    /// 0 for an attribute never set (AppKit's default for the soft, elastic, bidi-level and
    /// inscribe attributes).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/intattribute(_:forglyphat:)
    open func intAttribute(_ attributeTag: Int, forGlyphAt glyphIndex: Int) -> Int { _ensureLayout(); return _intAttributes[glyphIndex]?[attributeTag] ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/insertglyph(_:atglyphindex:characterindex:)
    open func insertGlyph(_ glyph: NSGlyph, atGlyphIndex glyphIndex: Int, characterIndex charIndex: Int) { unimplemented("NSLayoutManager.insertGlyph — the port keeps one glyph per character (CoreText shapes each line when it is drawn), so there is no glyph storage to edit") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/replaceglyph(at:withglyph:)
    open func replaceGlyph(at glyphIndex: Int, withGlyph newGlyph: NSGlyph) { unimplemented("NSLayoutManager.replaceGlyph — the port keeps one glyph per character (CoreText shapes each line when it is drawn), so there is no glyph storage to edit") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/deleteglyphs(in:)
    open func deleteGlyphs(in glyphRange: NSRange) { unimplemented("NSLayoutManager.deleteGlyphs — the port keeps one glyph per character (CoreText shapes each line when it is drawn), so there is no glyph storage to edit") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setcharacterindex(_:forglyphat:)
    open func setCharacterIndex(_ charIndex: Int, forGlyphAt glyphIndex: Int) { unimplemented("NSLayoutManager.setCharacterIndex — the port keeps one glyph per character (CoreText shapes each line when it is drawn), so there is no glyph storage to edit") }
    /// The fragments of the range move to `container` (by index among the text containers).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/settextcontainer(_:forglyphrange:)
    open func setTextContainer(_ container: NSTextContainer, forGlyphRange glyphRange: NSRange) {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return }
        for i in _fragments.indices where NSIntersectionRange(_fragments[i].charRange, glyphRange).length > 0 { _fragments[i].container = ci }
        _usedRects = [:]
    }
    /// The rects of the fragment holding the range (its baseline moves with the rect).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlinefragmentrect(_:forglyphrange:usedrect:)
    open func setLineFragmentRect(_ fragmentRect: NSRect, forGlyphRange glyphRange: NSRange, usedRect: NSRect) {
        _ensureLayout()
        guard let fi = _fragmentIndex(forCharacter: glyphRange.location) else { return }
        _fragments[fi].baseline += fragmentRect.minY - _fragments[fi].rect.minY
        _fragments[fi].textX += fragmentRect.minX - _fragments[fi].rect.minX
        _fragments[fi].rect = fragmentRect
        _fragments[fi].usedRect = usedRect
        _usedRects = [:]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setextralinefragmentrect(_:usedrect:textcontainer:)
    open func setExtraLineFragmentRect(_ fragmentRect: NSRect, usedRect: NSRect, textContainer container: NSTextContainer) {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return }
        _extraRect = fragmentRect
        _extraUsedRect = usedRect
        _extraContainer = ci
        _usedRects = [:]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlocation(_:forstartofglyphrange:)
    open func setLocation(_ location: NSPoint, forStartOfGlyphRange glyphRange: NSRange) {
        _ensureLayout()
        _locationOverrides[glyphRange.location] = location
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlocations(_:startingglyphindexes:count:forglyphrange:)
    open func setLocations(_ locations: NSPointArray, startingGlyphIndexes glyphIndexes: UnsafeMutablePointer<Int>, count: Int, forGlyphRange glyphRange: NSRange) {
        _ensureLayout()
        for i in 0..<count { _locationOverrides[glyphIndexes[i]] = locations[i] }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setnotshownattribute(_:forglyphat:)
    open func setNotShownAttribute(_ flag: Bool, forGlyphAt glyphIndex: Int) { _ensureLayout(); _notShownOverrides[glyphIndex] = flag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setdrawsoutsidelinefragment(_:forglyphat:)
    open func setDrawsOutsideLineFragment(_ flag: Bool, forGlyphAt glyphIndex: Int) {
        _ensureLayout()
        if flag { _drawsOutsideOverrides.insert(glyphIndex) } else { _drawsOutsideOverrides.remove(glyphIndex) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setattachmentsize(_:forglyphrange:)
    open func setAttachmentSize(_ attachmentSize: NSSize, forGlyphRange glyphRange: NSRange) {
        for i in glyphRange.location..<(glyphRange.location + max(1, glyphRange.length)) { _attachmentSizeOverrides[i] = attachmentSize }
        _invalidateAll()
        _redisplay()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/attachmentsize(forglyphat:)
    open func attachmentSize(forGlyphAt glyphIndex: Int) -> NSSize {
        _ensureLayout()
        return _attachments[glyphIndex]?.size ?? NSSize(width: -1, height: -1)    // AppKit's "no attachment" answer
    }
    private func _blockFrame(_ block: NSTextBlock, at glyphIndex: Int) -> _BlockFrame? {
        _ensureLayout()
        return _blockFrames.first { $0.block === block && glyphIndex >= $0.charRange.location && glyphIndex < $0.charRange.location + max(1, $0.charRange.length) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/boundsrect(for:at:effectiverange:)
    open func boundsRect(for block: NSTextBlock, at glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSRect {
        guard let f = _blockFrame(block, at: glyphIndex) else { effectiveGlyphRange?.pointee = NSRange(location: NSNotFound, length: 0); return .zero }
        effectiveGlyphRange?.pointee = f.charRange
        return f.bounds
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/boundsrect(for:glyphrange:)
    open func boundsRect(for block: NSTextBlock, glyphRange: NSRange) -> NSRect { boundsRect(for: block, at: glyphRange.location, effectiveRange: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/layoutrect(for:at:effectiverange:)
    open func layoutRect(for block: NSTextBlock, at glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSRect {
        guard let f = _blockFrame(block, at: glyphIndex) else { effectiveGlyphRange?.pointee = NSRange(location: NSNotFound, length: 0); return .zero }
        effectiveGlyphRange?.pointee = f.charRange
        return f.layout
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/layoutrect(for:glyphrange:)
    open func layoutRect(for block: NSTextBlock, glyphRange: NSRange) -> NSRect { layoutRect(for: block, at: glyphRange.location, effectiveRange: nil) }
    /// Typesetters call these while laying out; the CoreText layout records its own rects,
    /// so a value set here lasts until the next layout pass.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setboundsrect(_:for:glyphrange:)
    open func setBoundsRect(_ rect: NSRect, for block: NSTextBlock, glyphRange: NSRange) {
        _ensureLayout()
        if let i = _blockFrames.firstIndex(where: { $0.block === block && NSIntersectionRange($0.charRange, glyphRange).length > 0 }) { _blockFrames[i].bounds = rect }
        else { _blockFrames.append(_BlockFrame(block: block, bounds: rect, layout: rect, charRange: glyphRange, container: 0)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlayoutrect(_:for:glyphrange:)
    open func setLayoutRect(_ rect: NSRect, for block: NSTextBlock, glyphRange: NSRange) {
        _ensureLayout()
        if let i = _blockFrames.firstIndex(where: { $0.block === block && NSIntersectionRange($0.charRange, glyphRange).length > 0 }) { _blockFrames[i].layout = rect }
        else { _blockFrames.append(_BlockFrame(block: block, bounds: rect, layout: rect, charRange: glyphRange, container: 0)) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ruleraccessoryview(for:paragraphstyle:ruler:enabled:)
    /// A formatting strip with the paragraph's alignment (left, centre, right, justified)
    /// that sends the text view's align actions; AppKit's strip also has spacing and list
    /// pop-ups (ADR-0039).
    open func rulerAccessoryView(for view: NSTextView, paragraphStyle style: NSParagraphStyle, ruler: NSRulerView, enabled isEnabled: Bool) -> NSView? {
        MainActor.assumeIsolated { _NSRulerAccessoryView(textView: view, style: style, enabled: isEnabled) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/rulermarkers(for:paragraphstyle:ruler:)
    /// The first-line, head and tail indent markers and one marker per tab stop (ADR-0034).
    open func rulerMarkers(for view: NSTextView, paragraphStyle style: NSParagraphStyle, ruler: NSRulerView) -> [NSRulerMarker] {
        MainActor.assumeIsolated { _rulerMarkers(for: view, paragraphStyle: style, ruler: ruler) }
    }
}
