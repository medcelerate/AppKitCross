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
        // Tab stops reach CoreText through a CTParagraphStyle (alignment, indents and spacing
        // are applied here, line by line).
        var ctStyles: [ObjectIdentifier: CTParagraphStyle] = [:]
        func ctStyle(_ ps: NSParagraphStyle) -> CTParagraphStyle? {
            guard !ps.tabStops.isEmpty || ps.defaultTabInterval > 0 else { return nil }
            if let cached = ctStyles[ObjectIdentifier(ps)] { return cached }
            let made = NSLayoutManager._ctParagraphStyle(tabStops: ps.tabStops, defaultTabInterval: ps.defaultTabInterval)
            ctStyles[ObjectIdentifier(ps)] = made
            return made
        }
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
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle, let cts = ctStyle(ps) { ct[NSAttributedString.Key(kCTParagraphStyleAttributeName as String)] = cts }
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
        // Attachments: their characters advance by the attachment's width and raise the
        // line to its height (a run delegate); the attachment draws after the glyphs.
        _attachments = [:]
        let units = storage.string as NSString
        let container = _textContainers.first
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: n), options: []) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            for i in range.location..<(range.location + range.length) where units.character(at: i) == 0xFFFC {
                var m = attachment._layoutMetrics(in: container, characterIndex: i)
                if let override = _attachmentSizeOverrides[i] { m.size = override }
                _attachments[i] = (attachment, m.size, m.baselineOffset)
                let delegate = NSLayoutManager._runDelegate(width: m.size.width, ascent: max(0, m.size.height + m.baselineOffset), descent: max(0, -m.baselineOffset))
                if let delegate {
                    out.addAttribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), value: delegate, range: NSRange(location: i, length: 1))
                }
                out.addAttribute(NSAttributedString.Key(kCTForegroundColorAttributeName as String), value: NSLayoutManager._clearColor, range: NSRange(location: i, length: 1))
            }
        }
        return out
    }

    /// Attachments by character index: the attachment and its laid-out size and baseline offset.
    internal var _attachments: [Int: (attachment: NSTextAttachment, size: CGSize, baselineOffset: CGFloat)] = [:]
    private var _attachmentSizeOverrides: [Int: CGSize] = [:]
    private static let _clearColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// Metrics a run delegate reports, retained by the delegate.
    private final class _DelegateMetrics {
        let width: CGFloat, ascent: CGFloat, descent: CGFloat
        init(width: CGFloat, ascent: CGFloat, descent: CGFloat) { self.width = width; self.ascent = ascent; self.descent = descent }
    }

    private static func _runDelegate(width: CGFloat, ascent: CGFloat, descent: CGFloat) -> CTRunDelegate? {
        var callbacks = CTRunDelegateCallbacks(
            version: kCTRunDelegateVersion1,
            dealloc: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).release() },
            getAscent: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).takeUnretainedValue().ascent },
            getDescent: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).takeUnretainedValue().descent },
            getWidth: { p in Unmanaged<_DelegateMetrics>.fromOpaque(p).takeUnretainedValue().width })
        let box = Unmanaged.passRetained(_DelegateMetrics(width: width, ascent: ascent, descent: descent)).toOpaque()
        guard let d = CTRunDelegateCreate(&callbacks, box) else { Unmanaged<_DelegateMetrics>.fromOpaque(box).release(); return nil }
        return d
    }

    /// A CoreText paragraph style carrying only tab stops.
    internal static func _ctParagraphStyle(tabStops: [NSTextTab], defaultTabInterval: CGFloat) -> CTParagraphStyle {
        let tabs: [CTTextTab] = tabStops.map { t in
            let a: CTTextAlignment
            switch t.alignment {
            case .right: a = .right
            case .center: a = .center
            default: a = .left
            }
            return CTTextTabCreate(a, Double(t.location), nil)
        }
        #if canImport(Darwin)
        var array: CFArray = tabs as CFArray
        #else
        var array: CFArray = NSArray(array: tabs)
        #endif
        var interval = defaultTabInterval
        return withUnsafeBytes(of: &array) { tp in
            withUnsafeBytes(of: &interval) { ip in
                var settings = [CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: tp.baseAddress!)]
                if defaultTabInterval > 0 { settings.append(CTParagraphStyleSetting(spec: .defaultTabInterval, valueSize: MemoryLayout<CGFloat>.size, value: ip.baseAddress!)) }
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
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

    /// Where the next line goes while laying out (one column of text).
    private struct _Cursor {
        var container: Int
        var y: CGFloat
        var linesInContainer: Int
    }

    private func _ensureLayout() {
        // A text view fitting its frame to the new layout can change the wrapping width (a
        // scroll view shows its scroller and narrows the clip view), which invalidates the
        // layout again: lay out until it holds, so callers never read an emptied layout.
        var passes = 0
        while !_layoutValid, passes < 4 {
            passes += 1
            _layoutPass()
        }
    }

    private func _layoutPass() {
        _layoutValid = true
        _fragments = []
        _blockFrames = []
        _extraContainer = nil
        guard _textStorage != nil, !_textContainers.isEmpty else { return }
        let ct = _coreTextString()
        let ts = CTTypesetterCreateWithAttributedString(ct)
        _typesetter = ts
        let units = Array(ct.string.utf16)
        let length = units.count
        var cursor = _Cursor(container: 0, y: 0, linesInContainer: 0)
        var index = 0
        while index < length, cursor.container < _textContainers.count {
            let blocks = _paragraphStyle(at: index)?.textBlocks ?? []
            if let cell = blocks.first as? NSTextTableBlock {
                index = _layoutTable(cell.table, from: index, units: units, typesetter: ts, cursor: &cursor)
            } else if let block = blocks.first {
                index = _layoutBlock(block, from: index, units: units, typesetter: ts, cursor: &cursor)
            } else {
                let end = _paragraphEnd(from: index, units: units)
                let container = _textContainers[cursor.container]
                let column = NSRect(x: 0, y: 0, width: container.size.width, height: container.size.height)
                index = _layoutLines(NSRange(location: index, length: end - index), in: column, units: units, typesetter: ts, cursor: &cursor, breaksContainers: true)
            }
        }
        _laidOutLength = index
        // The extra line fragment: after a trailing newline or for empty text.
        if index >= length, cursor.container < _textContainers.count, length == 0 || _fragments.last?.newlineLength ?? 0 > 0 {
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

    /// The end of the paragraph starting at `index` (after its newline).
    private func _paragraphEnd(from index: Int, units: [UInt16]) -> Int {
        var i = index
        while i < units.count {
            let nl = _newlineLength(at: i, in: units)
            if nl > 0 { return i + nl }
            i += 1
        }
        return units.count
    }

    /// The paragraphs from `index` whose outermost text block satisfies `belongs`.
    private func _run(from index: Int, units: [UInt16], while belongs: (NSTextBlock) -> Bool) -> Int {
        var i = index
        while i < units.count, let b = _paragraphStyle(at: i)?.textBlocks.first, belongs(b) { i = _paragraphEnd(from: i, units: units) }
        return max(i, _paragraphEnd(from: index, units: units))
    }

    /// Lays `range` out as lines inside `column` (container coordinates; the fragments are
    /// `column.width` wide at `column.minX`), from `cursor.y`. Returns where it stopped:
    /// the range's end, or earlier when the containers ran out.
    private func _layoutLines(_ range: NSRange, in column: NSRect, units: [UInt16], typesetter ts: CTTypesetter, cursor: inout _Cursor, breaksContainers: Bool) -> Int {
        let end = range.location + range.length
        var index = range.location
        var paragraphStart = index == 0 || _newlineLength(at: index - 1, in: units) > 0 || (index >= 2 && units[index - 2] == 0x0D && units[index - 1] == 0x0A)
        var firstInColumn = true
        var column = column
        while index < end {
            guard cursor.container < _textContainers.count else { break }
            let container = _textContainers[cursor.container]
            let style = _paragraphStyle(at: index)
            let padding = container.lineFragmentPadding
            let columnWidth = column.width
            let head = paragraphStart ? (style?.firstLineHeadIndent ?? 0) : (style?.headIndent ?? 0)
            let tail = style?.tailIndent ?? 0
            let width = max(1, (tail > 0 ? tail : columnWidth + tail) - head - 2 * padding)
            let mode = container.lineBreakMode == .byWordWrapping ? (style?.lineBreakMode ?? .byWordWrapping) : container.lineBreakMode
            var count: Int
            switch mode {
            case .byClipping, .byTruncatingHead, .byTruncatingTail, .byTruncatingMiddle:
                count = 0
                while index + count < end {
                    let nl = _newlineLength(at: index + count, in: units)
                    if nl > 0 { count += nl; break }
                    count += 1
                }
            case .byCharWrapping:
                count = CTTypesetterSuggestClusterBreakWithOffset(ts, index, Double(width + head), Double(head))
            default:
                count = CTTypesetterSuggestLineBreakWithOffset(ts, index, Double(width + head), Double(head))
            }
            count = max(1, min(count, end - index))
            let line = CTTypesetterCreateLineWithOffset(ts, CFRangeMake(index, count), Double(head))
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
            // Space before a paragraph, except at the top of the text or of a block's column.
            let spacingBefore = paragraphStart && !_fragments.isEmpty && !(firstInColumn && !breaksContainers) ? (style?.paragraphSpacingBefore ?? 0) : 0
            let top = cursor.y + spacingBefore
            let maxLines = container.maximumNumberOfLines
            let overflow = (container.size.height < CGFloat.greatestFiniteMagnitude / 2 && top + height > container.size.height)
                || (maxLines > 0 && cursor.linesInContainer >= maxLines)
            if breaksContainers && overflow && cursor.linesInContainer > 0 {
                cursor.container += 1; cursor.y = 0; cursor.linesInContainer = 0
                if cursor.container < _textContainers.count { column.size.width = _textContainers[cursor.container].size.width }
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
            let textX = column.minX + padding + head + flushOffset
            let nl = _newlineLength(at: index + count - 1, in: units) > 0 ? (count >= 2 && units[index + count - 2] == 0x0D && units[index + count - 1] == 0x0A ? 2 : 1) : 0
            let fragment = _NSLineFragment(charRange: NSRange(location: index, length: count), newlineLength: nl,
                                           rect: NSRect(x: column.minX, y: top, width: columnWidth, height: height),
                                           usedRect: NSRect(x: textX, y: top, width: lineWidth - trailing, height: height),
                                           container: cursor.container, baseline: ascent, textX: textX, line: line, drawnLine: drawn)
            _fragments.append(fragment)
            cursor.linesInContainer += 1
            firstInColumn = false
            cursor.y = top + height + (style?.lineSpacing ?? 0)
            if nl > 0 { cursor.y += style?.paragraphSpacing ?? 0 }
            paragraphStart = nl > 0
            index += count
        }
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
    private func _layoutBlock(_ block: NSTextBlock, from index: Int, units: [UInt16], typesetter ts: CTTypesetter, cursor: inout _Cursor) -> Int {
        let end = _run(from: index, units: units) { $0 === block }
        let container = _textContainers[cursor.container]
        let outer = NSRect(x: 0, y: 0, width: container.size.width, height: CGFloat.greatestFiniteMagnitude / 4)
        let content = block.rectForLayout(at: NSPoint(x: 0, y: cursor.y), in: outer, textContainer: container, characterRange: NSRange(location: index, length: end - index))
        var inner = _Cursor(container: cursor.container, y: content.minY, linesInContainer: cursor.linesInContainer)
        let stop = _layoutLines(NSRange(location: index, length: end - index), in: content, units: units, typesetter: ts, cursor: &inner, breaksContainers: false)
        let used = NSRect(x: content.minX, y: content.minY, width: content.width, height: max(0, inner.y - content.minY))
        let bounds = block.boundsRect(forContentRect: used, in: outer, textContainer: container, characterRange: NSRange(location: index, length: end - index))
        _blockFrames.append(_BlockFrame(block: block, bounds: bounds, layout: content, charRange: NSRange(location: index, length: stop - index), container: cursor.container))
        cursor.y = bounds.maxY
        cursor.linesInContainer = inner.linesInContainer
        return stop
    }

    /// A table: the columns first (from the cells' natural widths), then row by row, each
    /// row's cells side by side and the row as tall as the tallest cell.
    private func _layoutTable(_ table: NSTextTable, from index: Int, units: [UInt16], typesetter ts: CTTypesetter, cursor: inout _Cursor) -> Int {
        let end = _run(from: index, units: units) { ($0 as? NSTextTableBlock)?.table === table }
        // Cells: consecutive paragraphs with the same cell block.
        var cells: [(block: NSTextTableBlock, range: NSRange)] = []
        var i = index
        while i < end {
            let pEnd = _paragraphEnd(from: i, units: units)
            let b = (_paragraphStyle(at: i)?.textBlocks.first as? NSTextTableBlock) ?? NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: 0, columnSpan: 1)
            if let last = cells.last, last.block === b {
                cells[cells.count - 1].range.length = pEnd - last.range.location
            } else {
                cells.append((b, NSRange(location: i, length: pEnd - i)))
            }
            i = pEnd
        }
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
                let content = cell.block.rectForLayout(at: NSPoint(x: table._contentRect.minX, y: rowTop), in: outer, textContainer: container, characterRange: cell.range)
                var inner = _Cursor(container: cursor.container, y: content.minY, linesInContainer: cursor.linesInContainer)
                let first = _fragments.count
                _ = _layoutLines(cell.range, in: content, units: units, typesetter: ts, cursor: &inner, breaksContainers: false)
                let used = NSRect(x: content.minX, y: content.minY, width: content.width, height: max(0, inner.y - content.minY))
                let bounds = cell.block.boundsRect(forContentRect: used, in: outer, textContainer: container, characterRange: cell.range)
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
                let lastFragment = n + 1 < laid.count ? laid[n + 1].firstFragment : _fragments.count
                if shift != 0 {
                    for f in entry.firstFragment..<lastFragment {
                        _fragments[f].rect.origin.y += shift
                        _fragments[f].usedRect.origin.y += shift
                    }
                }
                _blockFrames.append(_BlockFrame(block: cell.block, bounds: b, layout: entry.content, charRange: cell.range, container: cursor.container))
            }
            rowTop = rowBottom
            k = r
        }
        let tableContent = NSRect(x: table._contentRect.minX, y: table._contentRect.minY, width: table._contentRect.width, height: max(0, rowTop - table._contentRect.minY))
        let tableBounds = table.boundsRect(forContentRect: tableContent, in: outer, textContainer: container, characterRange: NSRange(location: index, length: end - index))
        // The table's own box draws beneath its cells.
        _blockFrames.insert(_BlockFrame(block: table, bounds: tableBounds, layout: tableContent, charRange: NSRange(location: index, length: end - index), container: cursor.container),
                            at: _blockFrames.count - cells.count)
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
            _drawSpellingMarks(forGlyphRange: glyphsToShow, at: origin)
        }
    }

    /// The rect an attachment occupies (container coordinates, flipped), from its line.
    internal func _attachmentRect(at index: Int) -> NSRect? {
        guard let a = _attachments[index], let fi = _fragmentIndex(forCharacter: index) else { return nil }
        let f = _fragments[fi]
        let x = f.textX + CTLineGetOffsetForStringIndex(f.line, index, nil)
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
        let marks = _temporary.filter { ($0.attrs[.spellingState] as? NSNumber)?.intValue ?? 0 != 0 }
        guard !marks.isEmpty else { return }
        let end = range.location + range.length
        for m in marks where m.range.location < end && m.range.location + m.range.length > range.location {
            let state = (m.attrs[.spellingState] as? NSNumber)?.intValue ?? 1
            (state & 2 != 0 && state & 1 == 0 ? NSColor.systemGreen : NSColor.systemRed).setFill()
            for f in _fragments where f.charRange.location < m.range.location + m.range.length && f.visibleEnd > m.range.location {
                let a = max(m.range.location, f.charRange.location), b = min(m.range.location + m.range.length, f.visibleEnd)
                guard b > a else { continue }
                let x0 = f.textX + CTLineGetOffsetForStringIndex(f.line, a, nil), x1 = f.textX + CTLineGetOffsetForStringIndex(f.line, b, nil)
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
        let before = _temporary.contains { NSIntersectionRange($0.range, r).length > 0 && !$0.attrs.keys.allSatisfy(NSLayoutManager._displayOnlyKeys.contains) }
        if r.length > 0, !attrs.isEmpty { _temporary.append((r, attrs)) }
        if before || !attrs.keys.allSatisfy(NSLayoutManager._displayOnlyKeys.contains) { _invalidateAll() }
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
        if !NSLayoutManager._displayOnlyKeys.contains(attrName) { _invalidateAll() }
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
    open func rulerAccessoryView(for view: NSTextView, paragraphStyle style: NSParagraphStyle, ruler: NSRulerView, enabled isEnabled: Bool) -> NSView? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nslayoutmanager/rulermarkers(for:paragraphstyle:ruler:)
    open func rulerMarkers(for view: NSTextView, paragraphStyle style: NSParagraphStyle, ruler: NSRulerView) -> [NSRulerMarker] { unimplemented() }
}
