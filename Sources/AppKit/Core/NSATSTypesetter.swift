// NSATSTypesetter (hand-written; seeded from the generated stub, see tools/apigen)
// The concrete system typesetter: NSLayoutManager's default `typesetter` (ADR-0040). Its
// behaviour is NSTypesetter's; the overrides exist because Apple's class declares them.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter
open class NSATSTypesetter: NSTypesetter {
    nonisolated(unsafe) private static let _shared = NSATSTypesetter()
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/shared
    class public var shared: NSATSTypesetter { _shared }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/boundingbox(forcontrolglyphat:for:proposedlinefragment:glyphposition:characterindex:)
    open override func boundingBox(forControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer, proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
        super.boundingBox(forControlGlyphAt: glyphIndex, for: textContainer, proposedLineFragment: proposedRect, glyphPosition: glyphPosition, characterIndex: charIndex)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/getlinefragmentrect(_:usedrect:forparagraphseparatorglyphrange:atproposedorigin:)
    open override func getLineFragmentRect(_ lineFragmentRect: UnsafeMutablePointer<NSRect>, usedRect lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, forParagraphSeparatorGlyphRange paragraphSeparatorGlyphRange: NSRange, atProposedOrigin lineOrigin: NSPoint) {
        super.getLineFragmentRect(lineFragmentRect, usedRect: lineFragmentUsedRect, forParagraphSeparatorGlyphRange: paragraphSeparatorGlyphRange, atProposedOrigin: lineOrigin)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/hyphenationfactor(forglyphat:)
    open override func hyphenationFactor(forGlyphAt glyphIndex: Int) -> Float { super.hyphenationFactor(forGlyphAt: glyphIndex) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/layoutparagraph(at:)
    open override func layoutParagraph(at lineFragmentOrigin: UnsafeMutablePointer<NSPoint>) -> Int { super.layoutParagraph(at: lineFragmentOrigin) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/linespacing(afterglyphat:withproposedlinefragmentrect:)
    open override func lineSpacing(afterGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat { super.lineSpacing(afterGlyphAt: glyphIndex, withProposedLineFragmentRect: rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/paragraphspacing(afterglyphat:withproposedlinefragmentrect:)
    open override func paragraphSpacing(afterGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat { super.paragraphSpacing(afterGlyphAt: glyphIndex, withProposedLineFragmentRect: rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/paragraphspacing(beforeglyphat:withproposedlinefragmentrect:)
    open override func paragraphSpacing(beforeGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat { super.paragraphSpacing(beforeGlyphAt: glyphIndex, withProposedLineFragmentRect: rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/sethardinvalidation(_:forglyphrange:)
    open override func setHardInvalidation(_ flag: Bool, forGlyphRange glyphRange: NSRange) { super.setHardInvalidation(flag, forGlyphRange: glyphRange) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/setparagraphglyphrange(_:separatorglyphrange:)
    open override func setParagraphGlyphRange(_ paragraphRange: NSRange, separatorGlyphRange paragraphSeparatorRange: NSRange) { super.setParagraphGlyphRange(paragraphRange, separatorGlyphRange: paragraphSeparatorRange) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/shouldbreakline(byhyphenatingbeforecharacterat:)
    open override func shouldBreakLine(byHyphenatingBeforeCharacterAt charIndex: Int) -> Bool { super.shouldBreakLine(byHyphenatingBeforeCharacterAt: charIndex) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/shouldbreakline(bywordbeforecharacterat:)
    open override func shouldBreakLine(byWordBeforeCharacterAt charIndex: Int) -> Bool { super.shouldBreakLine(byWordBeforeCharacterAt: charIndex) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/substitutefont(for:)
    open override func substituteFont(for originalFont: NSFont) -> NSFont { super.substituteFont(for: originalFont) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/texttab(forglyphlocation:writingdirection:maxlocation:)
    open override func textTab(forGlyphLocation glyphLocation: CGFloat, writingDirection direction: NSWritingDirection, maxLocation: CGFloat) -> NSTextTab? { super.textTab(forGlyphLocation: glyphLocation, writingDirection: direction, maxLocation: maxLocation) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsatstypesetter/willsetlinefragmentrect(_:forglyphrange:usedrect:baselineoffset:)
    open override func willSetLineFragmentRect(_ lineRect: UnsafeMutablePointer<NSRect>, forGlyphRange glyphRange: NSRange, usedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>) {
        super.willSetLineFragmentRect(lineRect, forGlyphRange: glyphRange, usedRect: usedRect, baselineOffset: baselineOffset)
    }
}
