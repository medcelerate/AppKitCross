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
    var line: CTLine                  // string indices are absolute
    var drawnLine: CTLine             // truncated for the clipping modes, else `line`
    var visibleEnd: Int { charRange.location + charRange.length - newlineLength }
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
    private var _typesetter: CTTypesetter? = nil
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

    private func _invalidateAll() {
        _layoutValid = false
        _typesetter = nil
        _fragments = []
        _laidOutLength = 0
        _extraContainer = nil
        delegate?.layoutManagerDidInvalidateLayout(self)
    }

    private func _redisplay() {
        MainActor.assumeIsolated {
            for c in _textContainers { c._textView?._layoutManagerDidChange() }
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/processediting(for:edited:range:changeinlength:invalidatedrange:)
    open func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorageEditActions, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        if editMask.contains(.editedCharacters), delta != 0 {
            // Temporary attributes follow the text they decorate.
            let editEnd = newCharRange.location + newCharRange.length - delta
            _temporary = _temporary.compactMap { entry in
                var r = entry.range
                if r.location >= editEnd { r.location += delta }
                else if r.location + r.length > newCharRange.location { return nil }
                return r.length > 0 ? (r, entry.attrs) : nil
            }
        }
        _invalidateAll()
        _redisplay()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/textstorage(_:edited:range:changeinlength:invalidatedrange:)
    open func textStorage(_ str: NSTextStorage, edited editedMask: Int, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        processEditing(for: str, edited: NSTextStorageEditActions(rawValue: UInt(editedMask)), range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatelayout(forcharacterrange:actualcharacterrange:)
    open func invalidateLayout(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) {
        actualCharRange?.pointee = NSRange(location: 0, length: _textStorage?.length ?? 0)
        _invalidateAll()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatelayout(forcharacterrange:issoft:actualcharacterrange:)
    open func invalidateLayout(forCharacterRange charRange: NSRange, isSoft flag: Bool, actualCharacterRange actualCharRange: NSRangePointer?) {
        invalidateLayout(forCharacterRange: charRange, actualCharacterRange: actualCharRange)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidateglyphs(forcharacterrange:changeinlength:actualcharacterrange:)
    open func invalidateGlyphs(forCharacterRange charRange: NSRange, changeInLength delta: Int, actualCharacterRange actualCharRange: NSRangePointer?) {
        actualCharRange?.pointee = charRange
        _invalidateAll()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidateglyphs(onlayoutinvalidationforglyphrange:)
    open func invalidateGlyphs(onLayoutInvalidationForGlyphRange glyphRange: NSRange) { _invalidateAll() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatedisplay(forcharacterrange:)
    open func invalidateDisplay(forCharacterRange charRange: NSRange) { _redisplay() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/invalidatedisplay(forglyphrange:)
    open func invalidateDisplay(forGlyphRange glyphRange: NSRange) { _redisplay() }

    // MARK: Layout

    private var _length: Int { _textStorage?.length ?? 0 }

    /// NSFont / NSColor attributes expressed for CoreText, with temporary attributes merged.
    private func _coreTextString() -> NSAttributedString {
        guard let storage = _textStorage else { return NSAttributedString(string: "") }
        let out = NSMutableAttributedString(string: storage.string)
        let n = storage.length
        guard n > 0 else { return out }
        // Semantic colours resolve under the text view's appearance (a dark field editor
        // draws light text), not whatever appearance happens to be current during layout.
        let appearance: NSAppearance? = MainActor.assumeIsolated { firstTextView?.effectiveAppearance }
        _layoutIsDark = appearance?.isDark ?? MainActor.assumeIsolated { NSAppearance.currentIsDark }
        func convert(_ attrs: [NSAttributedString.Key: Any], into range: NSRange) {
            var ct: [NSAttributedString.Key: Any] = [:]
            MainActor.assumeIsolated {
                let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                ct[NSAttributedString.Key(kCTFontAttributeName as String)] = font._coreTextFont
                let color = (attrs[.foregroundColor] as? NSColor) ?? NSColor.textColor
                let underlineColor = attrs[.underlineColor] as? NSColor
                var cg = color.cgColor, ucg = underlineColor?.cgColor
                appearance?.performAsCurrentDrawingAppearance { cg = color.cgColor; ucg = underlineColor?.cgColor }
                ct[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = cg
                if let u = attrs[.underlineStyle] as? NSNumber, u.intValue != 0 { ct[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = u }
                if let ucg { ct[NSAttributedString.Key(kCTUnderlineColorAttributeName as String)] = ucg }
            }
            if let k = attrs[.kern] as? NSNumber { ct[NSAttributedString.Key(kCTKernAttributeName as String)] = k }
            if let b = attrs[.baselineOffset] as? NSNumber { ct[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] = b }
            out.addAttributes(ct, range: range)
        }
        storage.enumerateAttributes(in: NSRange(location: 0, length: n), options: []) { attrs, range, _ in
            var merged = attrs
            for t in _temporary where t.range.location < range.location + range.length && t.range.location + t.range.length > range.location {
                // Split the run where temporary attributes apply.
                let lo = max(range.location, t.range.location), hi = min(range.location + range.length, t.range.location + t.range.length)
                for (k, v) in t.attrs { merged[k] = v }
                convert(merged, into: NSRange(location: lo, length: hi - lo))
                merged = attrs
            }
            convert(attrs, into: range)
            for t in _temporary where t.range.location < range.location + range.length && t.range.location + t.range.length > range.location {
                let lo = max(range.location, t.range.location), hi = min(range.location + range.length, t.range.location + t.range.length)
                var m = attrs
                for (k, v) in t.attrs { m[k] = v }
                convert(m, into: NSRange(location: lo, length: hi - lo))
            }
        }
        return out
    }

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

    private func _newlineLength(at i: Int, in units: [UInt16]) -> Int {
        guard i < units.count else { return 0 }
        let u = units[i]
        if u == 0x0D { return (i + 1 < units.count && units[i + 1] == 0x0A) ? 2 : 1 }
        return (u == 0x0A || u == 0x2028 || u == 0x2029 || u == 0x0C) ? 1 : 0
    }

    private func _ensureLayout() {
        guard !_layoutValid else { return }
        _layoutValid = true
        _fragments = []
        _extraContainer = nil
        guard _textStorage != nil, !_textContainers.isEmpty else { return }
        let ct = _coreTextString()
        let ts = CTTypesetterCreateWithAttributedString(ct)
        _typesetter = ts
        let units = Array(ct.string.utf16)
        let length = units.count
        var ci = 0
        var y: CGFloat = 0
        var index = 0
        var paragraphStart = true
        var linesInContainer = 0
        var lastFragmentEnd: CGFloat = 0
        while index < length {
            guard ci < _textContainers.count else { break }
            let container = _textContainers[ci]
            let style = _paragraphStyle(at: index)
            let padding = container.lineFragmentPadding
            let containerWidth = container.size.width
            let head = paragraphStart ? (style?.firstLineHeadIndent ?? 0) : (style?.headIndent ?? 0)
            let tail = style?.tailIndent ?? 0
            let width = max(1, (tail > 0 ? tail : containerWidth + tail) - head - 2 * padding)
            let mode = container.lineBreakMode == .byWordWrapping ? (style?.lineBreakMode ?? .byWordWrapping) : container.lineBreakMode
            var count: Int
            switch mode {
            case .byClipping, .byTruncatingHead, .byTruncatingTail, .byTruncatingMiddle:
                count = 0
                while index + count < length {
                    let nl = _newlineLength(at: index + count, in: units)
                    if nl > 0 { count += nl; break }
                    count += 1
                }
            case .byCharWrapping:
                count = CTTypesetterSuggestClusterBreak(ts, index, Double(width))
            default:
                count = CTTypesetterSuggestLineBreak(ts, index, Double(width))
            }
            count = max(1, min(count, length - index))
            let line = CTTypesetterCreateLine(ts, CFRangeMake(index, count))
            var drawn = line
            switch mode {
            case .byTruncatingHead: drawn = CTLineCreateTruncatedLine(line, Double(width), .start, nil) ?? line
            case .byTruncatingTail: drawn = CTLineCreateTruncatedLine(line, Double(width), .end, nil) ?? line
            case .byTruncatingMiddle: drawn = CTLineCreateTruncatedLine(line, Double(width), .middle, nil) ?? line
            default: break
            }
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            if !_usesFontLeading { leading = 0 }
            if let s = style {
                if s.lineHeightMultiple > 0 { ascent *= s.lineHeightMultiple; descent *= s.lineHeightMultiple }
                let h = ascent + descent + leading
                if s.maximumLineHeight > 0, h > s.maximumLineHeight { ascent -= h - s.maximumLineHeight }
                if s.minimumLineHeight > 0, h < s.minimumLineHeight { ascent += s.minimumLineHeight - h }
            }
            let height = (ascent + descent + leading).rounded(.up)
            let spacingBefore = (paragraphStart && !_fragments.isEmpty) ? (style?.paragraphSpacingBefore ?? 0) : 0
            let top = y + spacingBefore
            let maxLines = container.maximumNumberOfLines
            let overflow = (container.size.height < CGFloat.greatestFiniteMagnitude / 2 && top + height > container.size.height)
                || (maxLines > 0 && linesInContainer >= maxLines)
            if overflow && linesInContainer > 0 {
                ci += 1; y = 0; linesInContainer = 0
                continue
            }
            let flush: CGFloat
            switch style?.alignment ?? .natural {
            case .center: flush = 0.5
            case .right: flush = 1
            case .left: flush = 0
            default: flush = style?.baseWritingDirection == .rightToLeft ? 1 : 0   // natural follows the paragraph's direction
            }
            let trailing = CGFloat(CTLineGetTrailingWhitespaceWidth(line))
            let flushOffset = max(0, width - (lineWidth - trailing)) * flush
            let textX = padding + head + flushOffset
            let nl = _newlineLength(at: index + count - 1, in: units) > 0 ? (count >= 2 && units[index + count - 2] == 0x0D && units[index + count - 1] == 0x0A ? 2 : 1) : 0
            let fragment = _NSLineFragment(charRange: NSRange(location: index, length: count), newlineLength: nl,
                                           rect: NSRect(x: 0, y: top, width: containerWidth, height: height),
                                           usedRect: NSRect(x: textX, y: top, width: lineWidth - trailing, height: height),
                                           container: ci, baseline: ascent, textX: textX, line: line, drawnLine: drawn)
            _fragments.append(fragment)
            linesInContainer += 1
            lastFragmentEnd = top + height
            y = top + height + (style?.lineSpacing ?? 0)
            if nl > 0 { y += style?.paragraphSpacing ?? 0 }
            paragraphStart = nl > 0
            index += count
        }
        _laidOutLength = index
        // The extra line fragment: after a trailing newline or for empty text.
        if index >= length, ci < _textContainers.count, length == 0 || _fragments.last?.newlineLength ?? 0 > 0 {
            let container = _textContainers[ci]
            let font = _font(at: max(0, length - 1))
            let height = MainActor.assumeIsolated { (font.ascender - font.descender + font.leading).rounded(.up) }
            let top = _fragments.isEmpty ? 0 : y
            if container.size.height >= CGFloat.greatestFiniteMagnitude / 2 || top + height <= container.size.height || _fragments.isEmpty {
                _extraContainer = ci
                _extraRect = NSRect(x: 0, y: top, width: container.size.width, height: height)
                _extraUsedRect = NSRect(x: container.lineFragmentPadding, y: top, width: 0, height: height)
            }
        }
        _ = lastFragmentEnd
        for c in _textContainers { delegate?.layoutManager(self, didCompleteLayoutFor: c, atEnd: true) }
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

    /// Caret x (container coordinates) for a character index, within its fragment.
    internal func _caret(forCharacter index: Int) -> (rect: NSRect, container: Int)? {
        _ensureLayout()
        guard let fi = _fragmentIndex(forCharacter: index) else {
            guard let ec = _extraContainer else { return nil }
            return (NSRect(x: _extraUsedRect.minX, y: _extraRect.minY, width: 1, height: _extraRect.height), ec)
        }
        let f = _fragments[fi]
        let i = min(index, f.visibleEnd)
        let x = f.textX + CTLineGetOffsetForStringIndex(f.line, i, nil)
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
    open func notShownAttribute(forGlyphAt glyphIndex: Int) -> Bool { propertyForGlyph(at: glyphIndex).contains(.controlCharacter) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/drawsoutsidelinefragment(forglyphat:)
    open func drawsOutsideLineFragment(forGlyphAt glyphIndex: Int) -> Bool { false }
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
        let fs = _fragments.filter { $0.container == ci }
        guard let first = fs.first, let last = fs.last else { return NSRange(location: _laidOutLength, length: 0) }
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
        guard let fi = _fragmentIndex(forCharacter: glyphIndex) else { return NSPoint(x: _extraUsedRect.minX, y: _extraRect.height) }
        let f = _fragments[fi]
        return NSPoint(x: f.textX + CTLineGetOffsetForStringIndex(f.line, min(glyphIndex, f.visibleEnd), nil), y: f.baseline)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/usedrect(for:)
    open func usedRect(for container: NSTextContainer) -> NSRect {
        _ensureLayout()
        guard let ci = _textContainers.firstIndex(where: { $0 === container }) else { return .zero }
        var r = NSRect.null
        for f in _fragments where f.container == ci { r = r.union(f.usedRect) }
        if _extraContainer == ci { r = r.union(_extraUsedRect) }
        if r.isNull { return .zero }
        // The union of the fragments' used rects, as AppKit reports it: its origin is the
        // leftmost glyph run, so right-aligned text in a wide container measures its own
        // width rather than the container's.
        return NSRect(x: r.minX, y: 0, width: r.width, height: r.maxY)
    }
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
            let x0 = f.textX + CTLineGetOffsetForStringIndex(f.line, a, nil)
            let x1 = f.textX + CTLineGetOffsetForStringIndex(f.line, max(a, b), nil)
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
        if let ec = _extraContainer, ec == ci, point.y >= _extraRect.minY { return _laidOutLength }
        let f = chosen.element
        let x = point.x - f.textX
        var index = CTLineGetStringIndexForPosition(f.line, CGPoint(x: x, y: 0))
        index = max(f.charRange.location, min(index, f.visibleEnd))
        // Fraction through the glyph the point is over (0 at its leading edge).
        if index < f.visibleEnd {
            let x0 = CTLineGetOffsetForStringIndex(f.line, index, nil), x1 = CTLineGetOffsetForStringIndex(f.line, index + 1, nil)
            if x1 > x0 { partialFraction?.pointee = max(0, min(1, (x - x0) / (x1 - x0))) }
        } else if index == f.visibleEnd, index > f.charRange.location {
            // Past the last glyph: report it with a fraction of 1 (caller rounds up).
            let x0 = CTLineGetOffsetForStringIndex(f.line, index - 1, nil), x1 = CTLineGetOffsetForStringIndex(f.line, index, nil)
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
            positions?[n] = f.textX + CTLineGetOffsetForStringIndex(f.line, i, nil)
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
            let x0 = f.textX + CTLineGetOffsetForStringIndex(f.line, a, nil)
            var x1 = f.textX + CTLineGetOffsetForStringIndex(f.line, max(a, b), nil)
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
            // Laid out (measured) under one appearance, drawn under another: resolve again.
            if firstTextView == nil, let dark = _layoutIsDark, dark != NSAppearance.currentIsDark { _layoutValid = false }
        }
        _ensureLayout()
        MainActor.assumeIsolated {
            guard let gc = NSGraphicsContext.current else { return }
            let ctx = gc.cgContext
            let flipped = gc.isFlipped
            let end = glyphsToShow.location + glyphsToShow.length
            for f in _fragments where f.charRange.location < end && f.charRange.location + f.charRange.length > glyphsToShow.location {
                ctx.saveGState()
                ctx.translateBy(x: origin.x + f.rect.minX + f.textX, y: origin.y + f.rect.minY + f.baseline)
                if flipped { ctx.scaleBy(x: 1, y: -1) }
                ctx.textPosition = .zero
                CTLineDraw(f.drawnLine, ctx)
                ctx.restoreGState()
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
        let x0 = f.textX + CTLineGetOffsetForStringIndex(f.line, a, nil), x1 = f.textX + CTLineGetOffsetForStringIndex(f.line, b, nil)
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
        let x0 = f.textX + CTLineGetOffsetForStringIndex(f.line, a, nil), x1 = f.textX + CTLineGetOffsetForStringIndex(f.line, b, nil)
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
        _temporary.removeAll { NSIntersectionRange($0.range, r).length > 0 || ($0.range.length == 0) }
        if r.length > 0, !attrs.isEmpty { _temporary.append((r, attrs)) }
        _invalidateAll()
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
    open func removeTemporaryAttribute(_ attrName: NSAttributedString.Key, forCharacterRange charRange: NSRange) {
        let r = _clampTemp(charRange)
        _temporary = _temporary.compactMap { t in
            guard NSIntersectionRange(t.range, r).length > 0 else { return t }
            var a = t.attrs
            a[attrName] = nil
            return a.isEmpty ? nil : (t.range, a)
        }
        _invalidateAll()
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
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/glyphgenerator
    open var glyphGenerator: NSGlyphGenerator {
        get { unimplemented() }
        set { unimplemented() }
    }

    // MARK: Glyph storage (NSGlyphStorage) and manual layout: not used by the CoreText typesetter

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/attributedstring()
    open func attributedString() -> NSAttributedString { _textStorage ?? NSAttributedString(string: "") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/layoutoptions()
    open func layoutOptions() -> Int { 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/insertglyphs(_:length:forstartingglyphat:characterindex:)
    open func insertGlyphs(_ glyphs: UnsafePointer<NSGlyph>, length: Int, forStartingGlyphAt glyphIndex: Int, characterIndex charIndex: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setintattribute(_:value:forglyphat:)
    open func setIntAttribute(_ attributeTag: Int, value val: Int, forGlyphAt glyphIndex: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/intattribute(_:forglyphat:)
    open func intAttribute(_ attributeTag: Int, forGlyphAt glyphIndex: Int) -> Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/insertglyph(_:atglyphindex:characterindex:)
    open func insertGlyph(_ glyph: NSGlyph, atGlyphIndex glyphIndex: Int, characterIndex charIndex: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/replaceglyph(at:withglyph:)
    open func replaceGlyph(at glyphIndex: Int, withGlyph newGlyph: NSGlyph) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/deleteglyphs(in:)
    open func deleteGlyphs(in glyphRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setcharacterindex(_:forglyphat:)
    open func setCharacterIndex(_ charIndex: Int, forGlyphAt glyphIndex: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/settextcontainer(_:forglyphrange:)
    open func setTextContainer(_ container: NSTextContainer, forGlyphRange glyphRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlinefragmentrect(_:forglyphrange:usedrect:)
    open func setLineFragmentRect(_ fragmentRect: NSRect, forGlyphRange glyphRange: NSRange, usedRect: NSRect) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setextralinefragmentrect(_:usedrect:textcontainer:)
    open func setExtraLineFragmentRect(_ fragmentRect: NSRect, usedRect: NSRect, textContainer container: NSTextContainer) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlocation(_:forstartofglyphrange:)
    open func setLocation(_ location: NSPoint, forStartOfGlyphRange glyphRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlocations(_:startingglyphindexes:count:forglyphrange:)
    open func setLocations(_ locations: NSPointArray, startingGlyphIndexes glyphIndexes: UnsafeMutablePointer<Int>, count: Int, forGlyphRange glyphRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setnotshownattribute(_:forglyphat:)
    open func setNotShownAttribute(_ flag: Bool, forGlyphAt glyphIndex: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setdrawsoutsidelinefragment(_:forglyphat:)
    open func setDrawsOutsideLineFragment(_ flag: Bool, forGlyphAt glyphIndex: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setattachmentsize(_:forglyphrange:)
    open func setAttachmentSize(_ attachmentSize: NSSize, forGlyphRange glyphRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/attachmentsize(forglyphat:)
    open func attachmentSize(forGlyphAt glyphIndex: Int) -> NSSize { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/boundsrect(for:at:effectiverange:)
    open func boundsRect(for block: NSTextBlock, at glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/boundsrect(for:glyphrange:)
    open func boundsRect(for block: NSTextBlock, glyphRange: NSRange) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/layoutrect(for:at:effectiverange:)
    open func layoutRect(for block: NSTextBlock, at glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/layoutrect(for:glyphrange:)
    open func layoutRect(for block: NSTextBlock, glyphRange: NSRange) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setboundsrect(_:for:glyphrange:)
    open func setBoundsRect(_ rect: NSRect, for block: NSTextBlock, glyphRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/setlayoutrect(_:for:glyphrange:)
    open func setLayoutRect(_ rect: NSRect, for block: NSTextBlock, glyphRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/ruleraccessoryview(for:paragraphstyle:ruler:enabled:)
    open func rulerAccessoryView(for view: NSTextView, paragraphStyle style: NSParagraphStyle, ruler: NSRulerView, enabled isEnabled: Bool) -> NSView? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/rulermarkers(for:paragraphstyle:ruler:)
    open func rulerMarkers(for view: NSTextView, paragraphStyle style: NSParagraphStyle, ruler: NSRulerView) -> [NSRulerMarker] { unimplemented() }
}
