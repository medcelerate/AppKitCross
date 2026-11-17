// NSTypesetter (hand-written; seeded from the generated stub, see tools/apigen)
// The TextKit 1 typesetter, as far as the port's NSLayoutManager uses one (ADR-0040): the
// layout manager breaks lines with CoreText and asks its typesetter, line by line, for the
// paragraph and line spacing, telling it where it is (paragraph, line, container) and
// letting it adjust each line fragment rect before it is stored. The glyph-storage calls a
// custom `layoutParagraph(at:)` would make are not modelled: the layout manager lays out
// CoreText lines, not glyphs.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter
open class NSTypesetter: NSObject {
    private var _attributedString: NSAttributedString?
    private weak var _layoutManager: NSLayoutManager?
    private weak var _container: NSTextContainer?
    private var _style: NSParagraphStyle?
    private var _units: [UInt16] = []
    private var _lineStart = 0
    private var _inLayout = false
    private var _explicitParagraph: (range: NSRange, separator: NSRange)?
    private var _bidiProcessingEnabled = true
    private var _hyphenationFactor: Float = 0
    private var _lineFragmentPadding: CGFloat = 5
    private var _typesetterBehavior: NSLayoutManager.TypesetterBehavior = .latestBehavior
    private var _usesFontLeading = true

    private static let _glyphStorageReason = "the port's NSLayoutManager lays out CoreText lines, not glyph storage a typesetter fills (ADR-0040)"

    // MARK: Layout state, set by NSLayoutManager while it lays out

    /// The layout manager starts a line at `index` of `units` (its CoreText string).
    internal func _begin(layoutManager: NSLayoutManager, container: NSTextContainer, style: NSParagraphStyle?, paragraphStart: Bool, at index: Int, units: [UInt16]) {
        let wasInLayout = _inLayout
        _layoutManager = layoutManager
        _attributedString = layoutManager.textStorage
        _container = container
        _style = style
        _units = units
        _lineStart = index
        _inLayout = true
        _explicitParagraph = nil
        _usesFontLeading = layoutManager.usesFontLeading
        _typesetterBehavior = layoutManager.typesetterBehavior
        if paragraphStart || !wasInLayout { beginParagraph() }
        beginLine(withGlyphAt: index)
    }

    /// The layout manager finished laying out a range.
    internal func _end() {
        _inLayout = false
        _units = []
    }

    // MARK: Paragraph and line state

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/attributedstring
    open var attributedString: NSAttributedString? {
        get { _attributedString }
        set { _attributedString = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/layoutmanager
    open var layoutManager: NSLayoutManager? { _layoutManager }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/currenttextcontainer
    open var currentTextContainer: NSTextContainer? { _container }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/currentparagraphstyle
    open var currentParagraphStyle: NSParagraphStyle? { _style }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/textcontainers
    open var textContainers: NSArray? { _layoutManager.map { NSArray(array: $0.textContainers) } }

    /// The paragraph around the current line, and its separator.
    private var _paragraph: (range: NSRange, separator: NSRange) {
        if let p = _explicitParagraph { return p }
        guard _inLayout, !_units.isEmpty else { return (NSRange(location: NSNotFound, length: 0), NSRange(location: NSNotFound, length: 0)) }
        var start = min(_lineStart, _units.count)
        while start > 0 {
            let before = start - 1
            if _NSLineTypesetter.newlineLength(at: before, in: _units) > 0 || (before > 0 && _units[before - 1] == 0x0D && _units[before] == 0x0A) { break }
            start -= 1
        }
        let end = _NSLineTypesetter.paragraphEnd(from: start, units: _units)
        var separator = 0
        if end > start {
            if end - start >= 2, _units[end - 2] == 0x0D, _units[end - 1] == 0x0A { separator = 2 }
            else if _NSLineTypesetter.newlineLength(at: end - 1, in: _units) > 0 { separator = 1 }
        }
        return (NSRange(location: start, length: end - start), NSRange(location: end - separator, length: separator))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/paragraphcharacterrange
    open var paragraphCharacterRange: NSRange { _paragraph.range }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/paragraphglyphrange
    open var paragraphGlyphRange: NSRange { glyphRange(forCharacterRange: _paragraph.range, actualCharacterRange: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/paragraphseparatorcharacterrange
    open var paragraphSeparatorCharacterRange: NSRange { _paragraph.separator }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/paragraphseparatorglyphrange
    open var paragraphSeparatorGlyphRange: NSRange { glyphRange(forCharacterRange: _paragraph.separator, actualCharacterRange: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/setparagraphglyphrange(_:separatorglyphrange:)
    open func setParagraphGlyphRange(_ paragraphRange: NSRange, separatorGlyphRange paragraphSeparatorRange: NSRange) {
        _explicitParagraph = (characterRange(forGlyphRange: paragraphRange, actualGlyphRange: nil),
                              characterRange(forGlyphRange: paragraphSeparatorRange, actualGlyphRange: nil))
    }

    // MARK: Hooks around each paragraph and line (subclasses override; the defaults do nothing)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/beginparagraph()
    open func beginParagraph() {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/endparagraph()
    open func endParagraph() {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/beginline(withglyphat:)
    open func beginLine(withGlyphAt glyphIndex: Int) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/endline(withglyphrange:)
    open func endLine(withGlyphRange lineGlyphRange: NSRange) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/willsetlinefragmentrect(_:forglyphrange:usedrect:baselineoffset:)
    open func willSetLineFragmentRect(_ lineRect: NSRectPointer, forGlyphRange glyphRange: NSRange, usedRect: NSRectPointer, baselineOffset: UnsafeMutablePointer<CGFloat>) {}

    // MARK: Spacing (what NSLayoutManager asks for every line)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/linespacing(afterglyphat:withproposedlinefragmentrect:)
    open func lineSpacing(afterGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat { _style?.lineSpacing ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/paragraphspacing(afterglyphat:withproposedlinefragmentrect:)
    open func paragraphSpacing(afterGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat { _style?.paragraphSpacing ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/paragraphspacing(beforeglyphat:withproposedlinefragmentrect:)
    open func paragraphSpacing(beforeGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat { _style?.paragraphSpacingBefore ?? 0 }

    // MARK: Settings

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/bidiprocessingenabled
    open var bidiProcessingEnabled: Bool {
        get { _bidiProcessingEnabled }
        set { _bidiProcessingEnabled = newValue }
    }
    /// Hyphenation is off in the port: CoreText breaks lines at word boundaries.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/hyphenationfactor
    open var hyphenationFactor: Float {
        get { _hyphenationFactor }
        set { _hyphenationFactor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/hyphenationfactor(forglyphat:)
    open func hyphenationFactor(forGlyphAt glyphIndex: Int) -> Float {
        if let f = _style?.hyphenationFactor, f > 0 { return f }
        return _hyphenationFactor
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/linefragmentpadding
    open var lineFragmentPadding: CGFloat {
        get { _container?.lineFragmentPadding ?? _lineFragmentPadding }
        set { _lineFragmentPadding = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/typesetterbehavior
    open var typesetterBehavior: NSLayoutManager.TypesetterBehavior {
        get { _typesetterBehavior }
        set { _typesetterBehavior = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/usesfontleading
    open var usesFontLeading: Bool {
        get { _usesFontLeading }
        set { _usesFontLeading = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/defaulttypesetterbehavior
    class public var defaultTypesetterBehavior: NSLayoutManager.TypesetterBehavior { NSLayoutManager.TypesetterBehavior(rawValue: 4)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/sharedsystemtypesetter
    class public var sharedSystemTypesetter: NSTypesetter { NSATSTypesetter.shared }
    /// Every behaviour is typeset by the same CoreText typesetter.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/sharedsystemtypesetter(for:)
    public class func sharedSystemTypesetter(for behavior: NSLayoutManager.TypesetterBehavior) -> Any { NSATSTypesetter.shared }

    // MARK: Line breaking questions (CoreText breaks lines; these are AppKit's answers)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/shouldbreakline(bywordbeforecharacterat:)
    open func shouldBreakLine(byWordBeforeCharacterAt charIndex: Int) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/shouldbreakline(byhyphenatingbeforecharacterat:)
    open func shouldBreakLine(byHyphenatingBeforeCharacterAt charIndex: Int) -> Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/actionforcontrolcharacter(at:)
    open func actionForControlCharacter(at charIndex: Int) -> NSTypesetterControlCharacterAction {
        guard let s = _attributedString ?? _layoutManager?.textStorage, charIndex >= 0, charIndex < s.length else { return [] }
        switch (s.string as NSString).character(at: charIndex) {
        case 0x09: return .horizontalTabAction
        case 0x0A, 0x0D, 0x2029: return .paragraphBreakAction
        case 0x2028: return .lineBreakAction
        case 0x0C: return .containerBreakAction
        case 0x00..<0x20, 0x7F, 0x80..<0xA0, 0x200B...0x200F, 0xFEFF: return .zeroAdvancementAction
        default: return []
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/texttab(forglyphlocation:writingdirection:maxlocation:)
    open func textTab(forGlyphLocation glyphLocation: CGFloat, writingDirection direction: NSWritingDirection, maxLocation: CGFloat) -> NSTextTab? {
        let style = _style ?? .default
        let stops = style.tabStops.sorted { $0.location < $1.location }
        if direction == .rightToLeft {
            if let t = stops.last(where: { $0.location < glyphLocation }) { return t }
        } else if let t = stops.first(where: { $0.location > glyphLocation }) {
            return t.location <= maxLocation ? t : nil
        }
        let interval = style.defaultTabInterval
        guard interval > 0 else { return nil }
        let next = direction == .rightToLeft ? ((glyphLocation / interval).rounded(.up) - 1) * interval : ((glyphLocation / interval).rounded(.down) + 1) * interval
        guard next >= 0, next <= maxLocation else { return nil }
        return NSTextTab(textAlignment: .natural, location: next, options: [:])
    }

    // MARK: Geometry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/getlinefragmentrect(_:usedrect:remaining:forstartingglyphat:proposedrect:linespacing:paragraphspacingbefore:paragraphspacingafter:)
    open func getLineFragmentRect(_ lineFragmentRect: NSRectPointer!, usedRect lineFragmentUsedRect: NSRectPointer!, remaining remainingRect: NSRectPointer!, forStartingGlyphAt startingGlyphIndex: Int, proposedRect: NSRect, lineSpacing: CGFloat, paragraphSpacingBefore: CGFloat, paragraphSpacingAfter: CGFloat) {
        var proposal = proposedRect
        proposal.size.height += paragraphSpacingBefore + lineSpacing + paragraphSpacingAfter
        let charIndex = characterRange(forGlyphRange: NSRange(location: startingGlyphIndex, length: 0), actualGlyphRange: nil).location
        var remaining = CGRect.zero
        let rect = _container?.lineFragmentRect(forProposedRect: proposal, at: charIndex, writingDirection: _style?.baseWritingDirection ?? .natural, remaining: &remaining) ?? proposal
        let padding = lineFragmentPadding
        lineFragmentRect?.pointee = rect
        lineFragmentUsedRect?.pointee = rect.isEmpty ? .zero : NSRect(x: rect.minX + padding, y: rect.minY + paragraphSpacingBefore, width: max(0, rect.width - 2 * padding), height: proposedRect.height)
        remainingRect?.pointee = remaining
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/getlinefragmentrect(_:usedrect:forparagraphseparatorglyphrange:atproposedorigin:)
    open func getLineFragmentRect(_ lineFragmentRect: NSRectPointer, usedRect lineFragmentUsedRect: NSRectPointer, forParagraphSeparatorGlyphRange paragraphSeparatorGlyphRange: NSRange, atProposedOrigin lineOrigin: NSPoint) {
        let charIndex = characterRange(forGlyphRange: paragraphSeparatorGlyphRange, actualGlyphRange: nil).location
        var font: NSFont? = nil
        if let s = _attributedString ?? _layoutManager?.textStorage, s.length > 0 {
            font = s.attribute(.font, at: max(0, min(charIndex, s.length - 1)), effectiveRange: nil) as? NSFont
        }
        let height = _NSLineTypesetter.emptyLineHeight(font ?? MainActor.assumeIsolated { NSFont.systemFont(ofSize: NSFont.systemFontSize) })
        let width = max(0, (_container?.size.width ?? 0) - lineOrigin.x)
        lineFragmentRect.pointee = NSRect(x: lineOrigin.x, y: lineOrigin.y, width: width, height: height)
        lineFragmentUsedRect.pointee = NSRect(x: lineOrigin.x + lineFragmentPadding, y: lineOrigin.y, width: 0, height: height)
    }
    /// The distance from the top of the glyph's line fragment to its baseline.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/baselineoffset(in:glyphindex:)
    open func baselineOffset(in layoutMgr: NSLayoutManager, glyphIndex: Int) -> CGFloat { layoutMgr.location(forGlyphAt: glyphIndex).y }
    /// Control glyphs take no space of their own.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/boundingbox(forcontrolglyphat:for:proposedlinefragment:glyphposition:characterindex:)
    open func boundingBox(forControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(x: glyphPosition.x, y: proposedRect.minY, width: 0, height: proposedRect.height)
    }
    /// The port lays text out with the same (printer) metrics on screen and paper.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/printingadjustment(in:fornominallyspacedglyphrange:packedglyphs:count:)
    public class func printingAdjustment(in layoutMgr: NSLayoutManager, forNominallySpacedGlyphRange nominallySpacedGlyphsRange: NSRange, packedGlyphs: UnsafePointer<UInt8>, count packedGlyphsCount: Int) -> NSSize { .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/attributesforextralinefragment
    open var attributesForExtraLineFragment: [NSAttributedString.Key : Any] {
        if let tv = _layoutManager?.firstTextView { return MainActor.assumeIsolated { tv.typingAttributes } }
        if let s = _attributedString ?? _layoutManager?.textStorage, s.length > 0 { return s.attributes(at: s.length - 1, effectiveRange: nil) }
        return [:]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/substitutefont(for:)
    open func substituteFont(for originalFont: NSFont) -> NSFont { _layoutManager?.substituteFont(for: originalFont) ?? originalFont }

    // MARK: Glyphs and characters (one nominal glyph per UTF-16 unit, as in NSLayoutManager)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/characterrange(forglyphrange:actualglyphrange:)
    open func characterRange(forGlyphRange glyphRange: NSRange, actualGlyphRange: NSRangePointer?) -> NSRange {
        if let lm = _layoutManager { return lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: actualGlyphRange) }
        actualGlyphRange?.pointee = glyphRange
        return glyphRange
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/glyphrange(forcharacterrange:actualcharacterrange:)
    open func glyphRange(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) -> NSRange {
        if let lm = _layoutManager { return lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: actualCharRange) }
        actualCharRange?.pointee = charRange
        return charRange
    }

    // MARK: Driving layout

    /// Lays out (through the layout manager) at most `maxNumLines` line fragments from the
    /// start of `characterRange`; returns the characters they cover.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/layoutcharacters(in:for:maximumnumberoflinefragments:)
    open func layoutCharacters(in characterRange: NSRange, for layoutManager: NSLayoutManager, maximumNumberOfLineFragments maxNumLines: Int) -> NSRange {
        layoutManager.ensureLayout(forCharacterRange: characterRange)
        let lines = layoutManager._lineFragments.filter { $0.charRange.location + $0.charRange.length > characterRange.location }
        guard let first = lines.first else { return NSRange(location: characterRange.location, length: 0) }
        let last = lines[min(lines.count, max(1, maxNumLines)) - 1]
        let start = min(characterRange.location, first.charRange.location)
        return NSRange(location: start, length: last.charRange.location + last.charRange.length - start)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/layoutglyphs(in:startingatglyphindex:maxnumberoflinefragments:nextglyphindex:)
    open func layoutGlyphs(in layoutManager: NSLayoutManager, startingAtGlyphIndex startGlyphIndex: Int, maxNumberOfLineFragments maxNumLines: Int, nextGlyphIndex nextGlyph: UnsafeMutablePointer<Int>) {
        let start = layoutManager.characterIndexForGlyph(at: startGlyphIndex)
        let laid = layoutCharacters(in: NSRange(location: start, length: max(0, layoutManager.numberOfGlyphs - startGlyphIndex)), for: layoutManager, maximumNumberOfLineFragments: maxNumLines)
        nextGlyph.pointee = layoutManager.glyphIndexForCharacter(at: laid.location + laid.length)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/layoutparagraph(at:)
    open func layoutParagraph(at lineFragmentOrigin: NSPointPointer) -> Int { unimplemented("NSTypesetter.layoutParagraph(at:) — \(NSTypesetter._glyphStorageReason)") }

    // MARK: Glyph storage (set values last until the next layout pass; editing glyphs is not modelled)

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/setattachmentsize(_:forglyphrange:)
    open func setAttachmentSize(_ attachmentSize: NSSize, forGlyphRange glyphRange: NSRange) { _layoutManager?.setAttachmentSize(attachmentSize, forGlyphRange: glyphRange) }
    /// A hard invalidation makes the layout manager generate the range's glyphs again.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/sethardinvalidation(_:forglyphrange:)
    open func setHardInvalidation(_ flag: Bool, forGlyphRange glyphRange: NSRange) {
        guard flag, let lm = _layoutManager else { return }
        lm.invalidateGlyphs(forCharacterRange: lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil), changeInLength: 0, actualCharacterRange: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/deleteglyphs(in:)
    open func deleteGlyphs(in glyphRange: NSRange) { unimplemented("NSTypesetter.deleteGlyphs(in:) — \(NSTypesetter._glyphStorageReason)") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/insertglyph(_:atglyphindex:characterindex:)
    open func insertGlyph(_ glyph: NSGlyph, atGlyphIndex glyphIndex: Int, characterIndex: Int) { unimplemented("NSTypesetter.insertGlyph — \(NSTypesetter._glyphStorageReason)") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/substituteglyphs(in:withglyphs:)
    open func substituteGlyphs(in glyphRange: NSRange, withGlyphs glyphs: UnsafeMutablePointer<NSGlyph>!) { unimplemented("NSTypesetter.substituteGlyphs — \(NSTypesetter._glyphStorageReason)") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/setbidilevels(_:forglyphrange:)
    /// Recorded as each glyph's bidi-level attribute; drawing follows CoreText's own levels.
    open func setBidiLevels(_ levels: UnsafePointer<UInt8>!, forGlyphRange glyphRange: NSRange) {
        guard let lm = _layoutManager, let levels else { return }
        for i in 0..<glyphRange.length { lm.setIntAttribute(2, value: Int(levels[i]), forGlyphAt: glyphRange.location + i) }   // NSGlyphAttributeBidiLevel
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/setdrawsoutsidelinefragment(_:forglyphrange:)
    open func setDrawsOutsideLineFragment(_ flag: Bool, forGlyphRange glyphRange: NSRange) {
        guard let lm = _layoutManager else { return }
        for i in 0..<glyphRange.length { lm.setDrawsOutsideLineFragment(flag, forGlyphAt: glyphRange.location + i) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/setlinefragmentrect(_:forglyphrange:usedrect:baselineoffset:)
    /// Replaces the laid-out rects of the line holding the range until the next layout pass
    /// (the baseline moves with the rect); override `willSetLineFragmentRect` to change them
    /// while laying out.
    open func setLineFragmentRect(_ fragmentRect: NSRect, forGlyphRange glyphRange: NSRange, usedRect: NSRect, baselineOffset: CGFloat) {
        _layoutManager?.setLineFragmentRect(fragmentRect, forGlyphRange: glyphRange, usedRect: usedRect)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/setlocation(_:withadvancements:forstartofglyphrange:)
    /// The glyphs' locations, from `location` along the advancements, until the next layout
    /// pass (drawing follows the CoreText lines).
    open func setLocation(_ location: NSPoint, withAdvancements advancements: UnsafePointer<CGFloat>!, forStartOfGlyphRange glyphRange: NSRange) {
        guard let lm = _layoutManager else { return }
        var p = location
        for i in 0..<max(1, glyphRange.length) {
            lm.setLocation(p, forStartOfGlyphRange: NSRange(location: glyphRange.location + i, length: 1))
            guard let advancements, i < glyphRange.length else { break }
            p.x += advancements[i]
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstypesetter/setnotshownattribute(_:forglyphrange:)
    open func setNotShownAttribute(_ flag: Bool, forGlyphRange glyphRange: NSRange) {
        guard let lm = _layoutManager else { return }
        for i in 0..<glyphRange.length { lm.setNotShownAttribute(flag, forGlyphAt: glyphRange.location + i) }
    }
}
