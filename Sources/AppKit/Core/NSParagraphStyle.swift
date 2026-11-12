// NSParagraphStyle (hand-written; seeded from the generated stub, see tools/apigen)
// Immutable paragraph attributes; NSMutableParagraphStyle exposes the setters.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle
open class NSParagraphStyle: NSObject, NSCopying, NSMutableCopying, NSSecureCoding, NSCoding {
    #if !canImport(Darwin)
    /// First stored word: a non-zero CF type ID, see Support/CFBridgeLayout.swift.
    private let _cfinfo = _swiftObjectCFInfo
    #endif
    internal var _alignment: NSTextAlignment = .natural
    internal var _allowsDefaultTighteningForTruncation = false
    internal var _baseWritingDirection: NSWritingDirection = .natural
    internal var _defaultTabInterval: CGFloat = 0
    internal var _firstLineHeadIndent: CGFloat = 0
    internal var _headIndent: CGFloat = 0
    internal var _headerLevel = 0
    internal var _hyphenationFactor: Float = 0
    internal var _lineBreakMode: NSLineBreakMode = .byWordWrapping
    internal var _lineBreakStrategy: NSParagraphStyle.LineBreakStrategy = []
    internal var _lineHeightMultiple: CGFloat = 0
    internal var _lineSpacing: CGFloat = 0
    internal var _maximumLineHeight: CGFloat = 0
    internal var _minimumLineHeight: CGFloat = 0
    internal var _paragraphSpacing: CGFloat = 0
    internal var _paragraphSpacingBefore: CGFloat = 0
    internal var _tabStops: [NSTextTab] = []
    internal var _tailIndent: CGFloat = 0
    internal var _textBlocks: [NSTextBlock] = []
    internal var _textLists: [NSTextList] = []
    internal var _tighteningFactorForTruncation: Float = 0.05
    internal var _usesDefaultHyphenation = false

    public override init() { super.init() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/init(coder:)
    public required init?(coder: NSCoder) { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/encode(with:)
    open func encode(with coder: NSCoder) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/default
    class public var `default`: NSParagraphStyle { NSParagraphStyle() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/defaultwritingdirection(forlanguage:)
    public class func defaultWritingDirection(forLanguage languageName: String?) -> NSWritingDirection { .leftToRight }

    internal func _copyValues(into other: NSParagraphStyle) {
        other._alignment = _alignment; other._allowsDefaultTighteningForTruncation = _allowsDefaultTighteningForTruncation
        other._baseWritingDirection = _baseWritingDirection; other._defaultTabInterval = _defaultTabInterval
        other._firstLineHeadIndent = _firstLineHeadIndent; other._headIndent = _headIndent; other._headerLevel = _headerLevel
        other._hyphenationFactor = _hyphenationFactor; other._lineBreakMode = _lineBreakMode; other._lineBreakStrategy = _lineBreakStrategy
        other._lineHeightMultiple = _lineHeightMultiple; other._lineSpacing = _lineSpacing; other._maximumLineHeight = _maximumLineHeight
        other._minimumLineHeight = _minimumLineHeight; other._paragraphSpacing = _paragraphSpacing; other._paragraphSpacingBefore = _paragraphSpacingBefore
        other._tabStops = _tabStops; other._tailIndent = _tailIndent; other._textBlocks = _textBlocks; other._textLists = _textLists
        other._tighteningFactorForTruncation = _tighteningFactorForTruncation; other._usesDefaultHyphenation = _usesDefaultHyphenation
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/copy(with:)
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSParagraphStyle()
        _copyValues(into: c)
        return c
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/mutablecopy(with:)
    open func mutableCopy(with zone: NSZone? = nil) -> Any {
        let c = NSMutableParagraphStyle()
        _copyValues(into: c)
        return c
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSParagraphStyle else { return false }
        return o._alignment == _alignment && o._lineBreakMode == _lineBreakMode && o._lineSpacing == _lineSpacing
            && o._paragraphSpacing == _paragraphSpacing && o._paragraphSpacingBefore == _paragraphSpacingBefore
            && o._headIndent == _headIndent && o._tailIndent == _tailIndent && o._firstLineHeadIndent == _firstLineHeadIndent
            && o._lineHeightMultiple == _lineHeightMultiple && o._minimumLineHeight == _minimumLineHeight && o._maximumLineHeight == _maximumLineHeight
            && o._baseWritingDirection == _baseWritingDirection
            && o._defaultTabInterval == _defaultTabInterval && o._headerLevel == _headerLevel
            && o._tabStops == _tabStops
            // Lists and blocks compare by identity: two lists with the same format are
            // still different lists (AppKit renumbers each on its own).
            && o._textLists.count == _textLists.count && zip(o._textLists, _textLists).allSatisfy { $0 === $1 }
            && o._textBlocks.count == _textBlocks.count && zip(o._textBlocks, _textBlocks).allSatisfy { $0 === $1 }
    }
    open override var hash: Int { Int(_alignment.rawValue) ^ Int(_lineBreakMode.rawValue) << 3 ^ Int(_lineSpacing * 8) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/alignment
    open var alignment: NSTextAlignment { _alignment }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/allowsdefaulttighteningfortruncation
    open var allowsDefaultTighteningForTruncation: Bool { _allowsDefaultTighteningForTruncation }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/basewritingdirection
    open var baseWritingDirection: NSWritingDirection { _baseWritingDirection }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/defaulttabinterval
    open var defaultTabInterval: CGFloat { _defaultTabInterval }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/firstlineheadindent
    open var firstLineHeadIndent: CGFloat { _firstLineHeadIndent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/headindent
    open var headIndent: CGFloat { _headIndent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/headerlevel
    open var headerLevel: Int { _headerLevel }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/hyphenationfactor
    open var hyphenationFactor: Float { _hyphenationFactor }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/linebreakmode
    open var lineBreakMode: NSLineBreakMode { _lineBreakMode }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/linebreakstrategy
    open var lineBreakStrategy: NSParagraphStyle.LineBreakStrategy { _lineBreakStrategy }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/lineheightmultiple
    open var lineHeightMultiple: CGFloat { _lineHeightMultiple }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/linespacing
    open var lineSpacing: CGFloat { _lineSpacing }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/maximumlineheight
    open var maximumLineHeight: CGFloat { _maximumLineHeight }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/minimumlineheight
    open var minimumLineHeight: CGFloat { _minimumLineHeight }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/paragraphspacing
    open var paragraphSpacing: CGFloat { _paragraphSpacing }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/paragraphspacingbefore
    open var paragraphSpacingBefore: CGFloat { _paragraphSpacingBefore }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/tabstops
    open var tabStops: [NSTextTab] { _tabStops }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/tailindent
    open var tailIndent: CGFloat { _tailIndent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/textblocks
    open var textBlocks: [NSTextBlock] { _textBlocks }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/textlists
    open var textLists: [NSTextList] { _textLists }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/tighteningfactorfortruncation
    open var tighteningFactorForTruncation: Float { _tighteningFactorForTruncation }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsparagraphstyle/usesdefaulthyphenation
    open var usesDefaultHyphenation: Bool { _usesDefaultHyphenation }
}
