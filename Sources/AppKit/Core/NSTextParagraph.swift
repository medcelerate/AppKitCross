// NSTextParagraph (hand-written; seeded from the generated stub, see tools/apigen)
// A paragraph element: its attributed string, including the paragraph separator (ADR-0040).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextparagraph
@available(macOS 12.0, *)
open class NSTextParagraph: NSTextElement {
    private let _attributedString: NSAttributedString

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextparagraph/init(attributedstring:)
    public init(attributedString: NSAttributedString?) {
        _attributedString = (attributedString?.copy() as? NSAttributedString) ?? NSAttributedString(string: "")
        super.init(textContentManager: nil)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextparagraph/attributedstring
    open var attributedString: NSAttributedString { _attributedString }

    /// The length of the separator ending the paragraph (0 for the last one without one).
    internal var _separatorLength: Int {
        let units = Array(_attributedString.string.utf16)
        let n = units.count
        guard n > 0 else { return 0 }
        if n >= 2, units[n - 2] == 0x0D, units[n - 1] == 0x0A { return 2 }
        return _NSLineTypesetter.newlineLength(at: n - 1, in: units) > 0 ? 1 : 0
    }

    /// The paragraph's text without its separator, in document locations.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextparagraph/paragraphcontentrange
    open var paragraphContentRange: NSTextRange? {
        guard let range = elementRange else { return nil }
        guard let start = _offset(of: range.location) else { return range }
        return NSTextRange._make(NSRange(location: start, length: _attributedString.length - _separatorLength))
    }
    /// The separator ending the paragraph, in document locations (nil without one).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextparagraph/paragraphseparatorrange
    open var paragraphSeparatorRange: NSTextRange? {
        let sep = _separatorLength
        guard sep > 0, let range = elementRange, let start = _offset(of: range.location) else { return nil }
        return NSTextRange._make(NSRange(location: start + _attributedString.length - sep, length: sep))
    }
}
