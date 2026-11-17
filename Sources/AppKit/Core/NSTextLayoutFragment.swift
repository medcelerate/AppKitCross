// NSTextLayoutFragment (hand-written; seeded from the generated stub, see tools/apigen)
// The layout of one TextKit 2 element (ADR-0040): its paragraph typeset into line
// fragments by the line typesetter TextKit 1 uses, so both engines break and place lines
// identically. `layoutFragmentFrame` is in container coordinates; the lines'
// `typographicBounds` are relative to its origin. Paragraph spacing before is inside the
// fragment (except at the top of the document, as in TextKit 1); line spacing and
// paragraph spacing after are part of its height, so the next fragment starts where
// TextKit 1's next line does.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment
@available(macOS 12.0, *)
open class NSTextLayoutFragment: NSObject, NSSecureCoding, NSCoding {
    private let _textElement: NSTextElement?
    private let _explicitRange: NSTextRange?
    internal weak var _textLayoutManager: NSTextLayoutManager?
    private var _layoutQueue: OperationQueue?

    // Layout state, kept by the layout manager.
    internal var _lines: [NSTextLineFragment] = []
    internal var _state: State = .none
    internal var _origin: CGPoint = .zero
    internal var _size: CGSize = .zero
    /// The container width and position flags the lines were laid out for.
    internal var _laidOutWidth: CGFloat = -1
    internal var _laidOutAsLast = false
    internal var _laidOutAtStart = false
    internal var _estimatedHeight: CGFloat?
    /// Attachments by index into the paragraph string, as laid out.
    internal var _attachments: [Int: _NSLaidOutAttachment] = [:]
    internal var _topMargin: CGFloat = 0
    internal var _bottomMargin: CGFloat = 0
    internal var _paragraphString = NSAttributedString(string: "")
    internal var _renderingNeedsValidation = true
    /// Whether the colours were resolved under a dark appearance (nil: no view's appearance).
    internal var _laidOutDark: Bool?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/init(textelement:range:)
    public init(textElement: NSTextElement, range rangeInElement: NSTextRange?) {
        _textElement = textElement
        _explicitRange = rangeInElement.flatMap { r in textElement.elementRange.map { r.isEqual(to: $0) } == true ? nil : r }
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/init(coder:)
    public required init?(coder: NSCoder) {
        _textElement = nil
        _explicitRange = nil
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/encode(with:)
    open func encode(with coder: NSCoder) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    // MARK: Element and range

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/textelement
    open var textElement: NSTextElement? { _textElement }
    /// The element's range (it follows the element when edits before it move it).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/rangeinelement
    open var rangeInElement: NSTextRange {
        _explicitRange ?? _textElement?.elementRange ?? NSTextRange(location: _NSTextIndexLocation(0))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/textlayoutmanager
    open var textLayoutManager: NSTextLayoutManager? { _textLayoutManager }
    /// Layout is synchronous; the queue is kept for clients.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/layoutqueue
    open var layoutQueue: OperationQueue? {
        get { _layoutQueue }
        set { _layoutQueue = newValue }
    }

    /// The document offset of the fragment's first character.
    internal var _documentOffset: Int { _offset(of: rangeInElement.location) ?? 0 }

    // MARK: Geometry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/state
    open var state: NSTextLayoutFragment.State { _state }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/layoutfragmentframe
    open var layoutFragmentFrame: CGRect {
        _textLayoutManager?._ensurePositions()
        return CGRect(origin: _origin, size: _size)
    }
    /// The area the fragment draws in, relative to its frame's origin.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/renderingsurfacebounds
    open var renderingSurfaceBounds: CGRect {
        var r = CGRect(origin: .zero, size: _size)
        for l in _lines { r = r.union(l.typographicBounds) }
        for (i, _) in _attachments { if let a = _attachmentRect(local: i) { r = r.union(a) } }
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/topmargin
    open var topMargin: CGFloat { _topMargin }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/bottommargin
    open var bottomMargin: CGFloat { _bottomMargin }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/leadingpadding
    open var leadingPadding: CGFloat { _textLayoutManager?.textContainer?.lineFragmentPadding ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/trailingpadding
    open var trailingPadding: CGFloat { _textLayoutManager?.textContainer?.lineFragmentPadding ?? 0 }
    /// Attachments draw their image or cell; no attachment views are hosted (ADR-0040).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/textattachmentviewproviders
    open var textAttachmentViewProviders: [NSTextAttachmentViewProvider] { [] }

    /// The line fragments, laid out on first use.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/textlinefragments
    open var textLineFragments: [NSTextLineFragment] {
        if _state != .layoutAvailable { _textLayoutManager?._layout(self) }
        return _lines
    }
    /// The line holding `textLocation`; at a line boundary, upstream affinity picks the line
    /// that ends there.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/textlinefragment(for:isupstreamaffinity:)
    @available(macOS 14.0, *)
    open func textLineFragment(for textLocation: any NSTextLocation, isUpstreamAffinity: Bool) -> NSTextLineFragment? {
        guard let o = _offset(of: textLocation) else { return nil }
        return _lineIndex(forLocal: o - _documentOffset, upstream: isUpstreamAffinity).map { textLineFragments[$0] }
    }
    /// The line at `verticalOffset` (relative to the frame's top); without an exact match, the
    /// nearest line.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/textlinefragment(forverticaloffset:requiresexactmatch:)
    @available(macOS 14.0, *)
    open func textLineFragment(forVerticalOffset verticalOffset: CGFloat, requiresExactMatch: Bool) -> NSTextLineFragment? {
        let lines = textLineFragments
        if let l = lines.first(where: { verticalOffset >= $0.typographicBounds.minY && verticalOffset < $0.typographicBounds.maxY }) { return l }
        guard !requiresExactMatch, !lines.isEmpty else { return nil }
        return verticalOffset < lines[0].typographicBounds.minY ? lines.first : lines.last
    }
    /// The attachment's frame relative to the layout fragment frame's origin.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/framefortextattachment(at:)
    open func frameForTextAttachment(at location: any NSTextLocation) -> CGRect {
        guard let o = _offset(of: location) else { return .zero }
        _ = textLineFragments
        return _attachmentRect(local: o - _documentOffset) ?? .zero
    }
    /// Returns the fragment to an unlaid state; the layout manager lays it out again when
    /// it is needed.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/invalidatelayout()
    open func invalidateLayout() {
        _lines = []
        _attachments = [:]
        _state = .none
        _laidOutWidth = -1
        _textLayoutManager?._fragmentInvalidated(self)
    }

    // MARK: Lines

    /// The index of the line holding paragraph-local `local`.
    internal func _lineIndex(forLocal local: Int, upstream: Bool = false) -> Int? {
        let lines = textLineFragments
        guard !lines.isEmpty else { return nil }
        for (i, l) in lines.enumerated() {
            let start = l.characterRange.location, end = start + l.characterRange.length
            if upstream, i > 0, local == start, lines[i - 1]._newlineLength == 0 { return i - 1 }
            if local < end || (local == end && l.characterRange.length == 0) { return i }
        }
        return lines.count - 1
    }

    /// The rects `local` (paragraph-local) covers, one per line, relative to the frame origin.
    /// A covered line break extends the rect to the container's edge.
    internal func _enclosingRects(_ local: NSRange, extendsOverLineBreaks: Bool = true) -> [CGRect] {
        let end = local.location + local.length
        let padding = leadingPadding
        var out: [CGRect] = []
        for l in textLineFragments where l.characterRange.location < end && l.characterRange.location + l.characterRange.length > local.location {
            let a = max(local.location, l.characterRange.location)
            let b = min(end, l._visibleEnd)
            let tb = l.typographicBounds
            let x0 = tb.minX + l._caretOffset(a)
            var x1 = tb.minX + l._caretOffset(max(a, b))
            if extendsOverLineBreaks, end > l._visibleEnd, l._newlineLength > 0 { x1 = max(x1, _size.width - padding) }
            out.append(CGRect(x: x0, y: tb.minY, width: max(0, x1 - x0), height: tb.height))
        }
        return out
    }

    internal func _attachmentRect(local: Int) -> CGRect? {
        guard let a = _attachments[local], let li = _lines.firstIndex(where: { local >= $0.characterRange.location && local < $0.characterRange.location + $0.characterRange.length }) else { return nil }
        let l = _lines[li]
        let x = l.typographicBounds.minX + l._caretOffset(local)
        let baselineY = l.typographicBounds.minY + l.glyphOrigin.y
        return CGRect(x: x, y: baselineY - a.size.height - a.baselineOffset, width: a.size.width, height: a.size.height)
    }

    // MARK: Layout

    /// Typesets the paragraph into lines for `container` (TextKit 1's line typesetter).
    internal func _layout(container: NSTextContainer, appearance: NSAppearance?, linkAttributes: [NSAttributedString.Key: Any]?,
                          rendering: [(range: NSRange, attrs: [NSAttributedString.Key: Any])], usesFontLeading: Bool,
                          isLast: Bool, extraLineFont: NSFont, paragraphString: NSAttributedString) {
        let docOffset = _documentOffset
        let atStart = docOffset == 0
        _paragraphString = paragraphString
        let conv = _NSCoreTextConversion.convert(paragraphString, range: NSRange(location: 0, length: paragraphString.length), documentOffset: docOffset,
                                                 appearance: appearance, linkAttributes: linkAttributes, temporary: rendering, container: container)
        _attachments = conv.attachments
        let units = Array(conv.string.string.utf16)
        var lines: [NSTextLineFragment] = []
        var y: CGFloat = 0
        _topMargin = 0
        _bottomMargin = 0
        let width = container.size.width
        if !units.isEmpty {
            let ts = CTTypesetterCreateWithAttributedString(conv.string)
            var index = 0
            var paragraphStart = true
            while index < units.count {
                let style = paragraphString.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
                let t = _NSLineTypesetter.line(typesetter: ts, units: units, index: index, end: units.count, style: style, paragraphStart: paragraphStart,
                                               columnMinX: 0, columnWidth: width, container: container, usesFontLeading: usesFontLeading)
                let spacingBefore = paragraphStart && !atStart ? (style?.paragraphSpacingBefore ?? 0) : 0
                if paragraphStart && lines.isEmpty { _topMargin = spacingBefore }
                let top = y + spacingBefore
                lines.append(NSTextLineFragment(_attributedString: paragraphString, range: NSRange(location: index, length: t.count), line: t.line, drawnLine: t.drawnLine,
                                                typographicBounds: CGRect(x: t.textX, y: top, width: t.usedWidth, height: t.height),
                                                glyphOrigin: CGPoint(x: 0, y: t.ascent), newlineLength: t.newlineLength))
                y = top + t.height + (style?.lineSpacing ?? 0)
                if t.newlineLength > 0 {
                    let after = style?.paragraphSpacing ?? 0
                    y += after
                    _bottomMargin = after
                }
                paragraphStart = t.newlineLength > 0
                index += t.count
            }
        }
        // The extra line fragment: after a trailing line break, or for an empty document.
        if isLast, units.isEmpty || (lines.last?._newlineLength ?? 0) > 0 {
            let height = _NSLineTypesetter.emptyLineHeight(extraLineFont)
            let ascent = MainActor.assumeIsolated { extraLineFont.ascender }
            let top = lines.isEmpty ? 0 : y
            lines.append(NSTextLineFragment(_attributedString: paragraphString, range: NSRange(location: units.count, length: 0), line: nil, drawnLine: nil,
                                            typographicBounds: CGRect(x: container.lineFragmentPadding, y: top, width: 0, height: height),
                                            glyphOrigin: CGPoint(x: 0, y: ascent), newlineLength: 0))
            y = top + height
        }
        _lines = lines
        let used = lines.reduce(CGFloat(0)) { max($0, $1.typographicBounds.maxX) } + container.lineFragmentPadding
        _size = CGSize(width: width < CGFloat.greatestFiniteMagnitude / 2 ? width : used, height: y)
        _state = .layoutAvailable
        _laidOutWidth = width
        _laidOutAsLast = isLast
        _laidOutAtStart = atStart
    }

    // MARK: Drawing

    /// Draws the fragment with its frame's origin at `point`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/draw(at:in:)
    open func draw(at point: CGPoint, in context: CGContext) {
        MainActor.assumeIsolated {
            _drawBackground(at: point)
            _drawForeground(at: point, in: context)
        }
    }

    /// Background colour runs (rendering attributes first, as TextKit 1's temporary ones).
    @MainActor internal func _drawBackground(at point: CGPoint) {
        let lm = _textLayoutManager
        if _renderingNeedsValidation, let lm { _renderingNeedsValidation = false; lm.renderingAttributesValidator?(lm, self) }
        _ = textLineFragments
        let n = _paragraphString.length
        for t in lm?._renderingAttributes(local: self) ?? [] {
            guard let color = t.attrs[.backgroundColor] as? NSColor else { continue }
            color.setFill()
            for r in _enclosingRects(t.range) { NSBezierPath.fill(r.offsetBy(dx: point.x, dy: point.y)) }
        }
        guard n > 0 else { return }
        _paragraphString.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: n), options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            color.setFill()
            for r in _enclosingRects(range) { NSBezierPath.fill(r.offsetBy(dx: point.x, dy: point.y)) }
        }
    }

    /// Glyphs, attachments, strikethrough and the spelling underline.
    @MainActor internal func _drawForeground(at point: CGPoint, in context: CGContext) {
        let lines = textLineFragments
        for l in lines where l._drawnLine != nil {
            l.draw(at: CGPoint(x: point.x + l.typographicBounds.minX, y: point.y + l.typographicBounds.minY), in: context)
        }
        let lm = _textLayoutManager
        let view = lm?._textView
        let docOffset = _documentOffset
        if !_attachments.isEmpty {
            let selections = lm?.textSelections.flatMap(\.textRanges).compactMap(\._nsRange) ?? []
            for (local, entry) in _attachments {
                guard let r = _attachmentRect(local: local), r.width > 0 || r.height > 0 else { continue }
                let rect = r.offsetBy(dx: point.x, dy: point.y)
                let index = docOffset + local
                let selected = selections.contains { index >= $0.location && index < NSMaxRange($0) }
                if let cell = entry.attachment.attachmentCell as? NSCell, !(cell is NSTextAttachmentCell) {
                    if let view { cell.draw(withFrame: rect, in: view) }
                } else {
                    entry.attachment._draw(in: rect, characterIndex: index, layoutManager: nil, textContainer: lm?.textContainer, view: view, selected: selected)
                }
            }
        }
        let n = _paragraphString.length
        if n > 0 {
            _paragraphString.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: n), options: []) { value, run, _ in
                guard let style = (value as? NSNumber)?.intValue ?? (value as? Int), style != 0 else { return }
                let attrs = _paragraphString.attributes(at: run.location, effectiveRange: nil)
                let color = (attrs[.strikethroughColor] as? NSColor) ?? (attrs[.foregroundColor] as? NSColor) ?? NSColor.textColor
                color.setFill()
                for l in lines where l.characterRange.location < NSMaxRange(run) && l._visibleEnd > run.location {
                    let a = max(run.location, l.characterRange.location), b = min(NSMaxRange(run), l._visibleEnd)
                    guard b > a else { continue }
                    let font = (_paragraphString.attribute(.font, at: a, effectiveRange: nil) as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    let tb = l.typographicBounds
                    let x0 = tb.minX + l._caretOffset(a), x1 = tb.minX + l._caretOffset(b)
                    NSBezierPath.fill(NSRect(x: point.x + x0, y: point.y + tb.minY + l.glyphOrigin.y - font.xHeight / 2, width: x1 - x0, height: 1))
                }
            }
        }
        // Misspelled words (the `.spellingState` rendering attribute): AppKit's dotted
        // underline, red for spelling, green for grammar; screen only.
        guard !NSGraphicsContext._printing, let lm else { return }
        for m in lm._renderingAttributes(local: self) {
            guard let state = (m.attrs[.spellingState] as? NSNumber)?.intValue, state != 0 else { continue }
            (state & 2 != 0 && state & 1 == 0 ? NSColor.systemGreen : NSColor.systemRed).setFill()
            for l in lines where l.characterRange.location < NSMaxRange(m.range) && l._visibleEnd > m.range.location {
                let a = max(m.range.location, l.characterRange.location), b = min(NSMaxRange(m.range), l._visibleEnd)
                guard b > a else { continue }
                let tb = l.typographicBounds
                let x0 = tb.minX + l._caretOffset(a), x1 = tb.minX + l._caretOffset(b)
                let y = point.y + tb.minY + l.glyphOrigin.y + 2
                var x = point.x + x0
                while x < point.x + x1 {
                    NSBezierPath.fill(NSRect(x: x, y: y, width: min(2, point.x + x1 - x), height: 2))
                    x += 3
                }
            }
        }
    }
}

@available(macOS 12.0, *)
extension NSTextLayoutFragment {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/enumerationoptions
    @available(macOS 12.0, *)
    public struct EnumerationOptions: OptionSet, Sendable, Equatable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/enumerationoptions/ensuresextralinefragment
        static public var ensuresExtraLineFragment: NSTextLayoutFragment.EnumerationOptions { NSTextLayoutFragment.EnumerationOptions(rawValue: 8) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/enumerationoptions/ensureslayout
        static public var ensuresLayout: NSTextLayoutFragment.EnumerationOptions { NSTextLayoutFragment.EnumerationOptions(rawValue: 4) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/enumerationoptions/estimatessize
        static public var estimatesSize: NSTextLayoutFragment.EnumerationOptions { NSTextLayoutFragment.EnumerationOptions(rawValue: 2) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/enumerationoptions/reverse
        static public var reverse: NSTextLayoutFragment.EnumerationOptions { NSTextLayoutFragment.EnumerationOptions(rawValue: 1) }
    }
}

@available(macOS 12.0, *)
extension NSTextLayoutFragment {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlayoutfragment/state-swift.enum
    @available(macOS 12.0, *)
    public enum State: Int, Sendable, Equatable, Hashable {
        case calculatedUsageBounds = 2
        case estimatedUsageBounds = 1
        case layoutAvailable = 3
        case none = 0
    }
}
