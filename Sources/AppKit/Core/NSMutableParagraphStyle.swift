// NSMutableParagraphStyle (hand-written; seeded from the generated stub, see tools/apigen)

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableparagraphstyle
open class NSMutableParagraphStyle: NSParagraphStyle {
    public override init() { super.init() }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableparagraphstyle/addtabstop(_:)
    open func addTabStop(_ anObject: NSTextTab) { _tabStops.append(anObject) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableparagraphstyle/removetabstop(_:)
    open func removeTabStop(_ anObject: NSTextTab) { _tabStops.removeAll { $0 === anObject } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmutableparagraphstyle/setparagraphstyle(_:)
    open func setParagraphStyle(_ obj: NSParagraphStyle) { obj._copyValues(into: self) }

    open override var alignment: NSTextAlignment { get { _alignment } set { _alignment = newValue } }
    open override var allowsDefaultTighteningForTruncation: Bool { get { _allowsDefaultTighteningForTruncation } set { _allowsDefaultTighteningForTruncation = newValue } }
    open override var baseWritingDirection: NSWritingDirection { get { _baseWritingDirection } set { _baseWritingDirection = newValue } }
    open override var defaultTabInterval: CGFloat { get { _defaultTabInterval } set { _defaultTabInterval = newValue } }
    open override var firstLineHeadIndent: CGFloat { get { _firstLineHeadIndent } set { _firstLineHeadIndent = newValue } }
    open override var headIndent: CGFloat { get { _headIndent } set { _headIndent = newValue } }
    open override var headerLevel: Int { get { _headerLevel } set { _headerLevel = newValue } }
    open override var hyphenationFactor: Float { get { _hyphenationFactor } set { _hyphenationFactor = newValue } }
    open override var lineBreakMode: NSLineBreakMode { get { _lineBreakMode } set { _lineBreakMode = newValue } }
    open override var lineBreakStrategy: NSParagraphStyle.LineBreakStrategy { get { _lineBreakStrategy } set { _lineBreakStrategy = newValue } }
    open override var lineHeightMultiple: CGFloat { get { _lineHeightMultiple } set { _lineHeightMultiple = newValue } }
    open override var lineSpacing: CGFloat { get { _lineSpacing } set { _lineSpacing = newValue } }
    open override var maximumLineHeight: CGFloat { get { _maximumLineHeight } set { _maximumLineHeight = newValue } }
    open override var minimumLineHeight: CGFloat { get { _minimumLineHeight } set { _minimumLineHeight = newValue } }
    open override var paragraphSpacing: CGFloat { get { _paragraphSpacing } set { _paragraphSpacing = newValue } }
    open override var paragraphSpacingBefore: CGFloat { get { _paragraphSpacingBefore } set { _paragraphSpacingBefore = newValue } }
    open override var tabStops: [NSTextTab] { get { _tabStops } set { _tabStops = newValue } }
    open override var tailIndent: CGFloat { get { _tailIndent } set { _tailIndent = newValue } }
    open override var textBlocks: [NSTextBlock] { get { _textBlocks } set { _textBlocks = newValue } }
    open override var textLists: [NSTextList] { get { _textLists } set { _textLists = newValue } }
    open override var tighteningFactorForTruncation: Float { get { _tighteningFactorForTruncation } set { _tighteningFactorForTruncation = newValue } }
    open override var usesDefaultHyphenation: Bool { get { _usesDefaultHyphenation } set { _usesDefaultHyphenation = newValue } }
}
