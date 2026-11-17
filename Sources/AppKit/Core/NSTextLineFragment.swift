// NSTextLineFragment (hand-written; seeded from the generated stub, see tools/apigen)
// One typeset line of a TextKit 2 layout fragment (ADR-0040), holding its CoreText line.
// `typographicBounds` is in the layout fragment's coordinates; `glyphOrigin` is the
// baseline origin relative to `typographicBounds.origin`. Character indices are into
// `attributedString` (the paragraph's string for lines a layout fragment made).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(CoreText)
import CoreText
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment
@available(macOS 12.0, *)
open class NSTextLineFragment: NSObject, NSSecureCoding, NSCoding {
    private let _attributedString: NSAttributedString
    private let _characterRange: NSRange
    /// The CoreText line (string indices are `attributedString` indices); nil for the extra
    /// line fragment after a trailing line break or of an empty document.
    internal let _line: CTLine?
    internal let _drawnLine: CTLine?
    internal var _typographicBounds: CGRect
    internal let _glyphOrigin: CGPoint
    /// The length of the line break the line ends with (0, 1 or 2).
    internal let _newlineLength: Int

    internal init(_attributedString: NSAttributedString, range: NSRange, line: CTLine?, drawnLine: CTLine?, typographicBounds: CGRect, glyphOrigin: CGPoint, newlineLength: Int) {
        self._attributedString = _attributedString
        _characterRange = range
        _line = line
        _drawnLine = drawnLine
        _typographicBounds = typographicBounds
        _glyphOrigin = glyphOrigin
        _newlineLength = newlineLength
        super.init()
    }

    /// Typesets `range` of `attributedString` as one line (no wrapping).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/init(attributedstring:range:)
    public init(attributedString: NSAttributedString, range: NSRange) {
        let conv = _NSCoreTextConversion.convert(attributedString, range: range, documentOffset: range.location, appearance: nil,
                                                 linkAttributes: nil, temporary: [], container: nil)
        // Index the line by `attributedString` positions: pad the converted text with the
        // characters before `range`.
        let full = NSMutableAttributedString(string: (attributedString.string as NSString).substring(to: range.location))
        full.append(conv.string)
        let ts = CTTypesetterCreateWithAttributedString(full)
        let line = CTTypesetterCreateLine(ts, CFRangeMake(range.location, range.length))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        _attributedString = attributedString.copy() as? NSAttributedString ?? attributedString
        _characterRange = range
        _line = line
        _drawnLine = line
        _typographicBounds = CGRect(x: 0, y: 0, width: width, height: (ascent + descent + leading).rounded(.up))
        _glyphOrigin = CGPoint(x: 0, y: ascent)
        let units = Array(attributedString.string.utf16)
        let end = range.location + range.length
        _newlineLength = end >= 2 && end <= units.count && units[end - 2] == 0x0D && units[end - 1] == 0x0A ? 2 : _NSLineTypesetter.newlineLength(at: end - 1, in: units) > 0 ? 1 : 0
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/init(string:attributes:range:)
    public convenience init(string: String, attributes: [NSAttributedString.Key : Any] = [:], range: NSRange) {
        self.init(attributedString: NSAttributedString(string: string, attributes: attributes), range: range)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/init(coder:)
    public required init?(coder aDecoder: NSCoder) {
        _attributedString = NSAttributedString(string: "")
        _characterRange = NSRange(location: 0, length: 0)
        _line = nil
        _drawnLine = nil
        _typographicBounds = .zero
        _glyphOrigin = .zero
        _newlineLength = 0
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/encode(with:)
    open func encode(with coder: NSCoder) {}
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/supportssecurecoding
    class public var supportsSecureCoding: Bool { true }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/attributedstring
    open var attributedString: NSAttributedString { _attributedString }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/characterrange
    open var characterRange: NSRange { _characterRange }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/typographicbounds
    open var typographicBounds: CGRect { _typographicBounds }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/glyphorigin
    open var glyphOrigin: CGPoint { _glyphOrigin }

    /// The last index a caret can sit at in this line (before its line break).
    internal var _visibleEnd: Int { _characterRange.location + _characterRange.length - _newlineLength }

    /// The caret x for `index`, relative to `typographicBounds.origin`.
    internal func _caretOffset(_ index: Int) -> CGFloat {
        guard let line = _line else { return _glyphOrigin.x }
        return _glyphOrigin.x + CGFloat(CTLineGetOffsetForStringIndex(line, max(_characterRange.location, min(index, _visibleEnd)), nil))
    }

    /// The character nearest `point` (in the line fragment's coordinates, relative to
    /// `typographicBounds.origin`), as an `attributedString` index.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/characterindex(for:)
    open func characterIndex(for point: CGPoint) -> Int {
        guard let line = _line else { return _characterRange.location }
        let i = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - _glyphOrigin.x, y: 0))
        return max(_characterRange.location, min(i, _visibleEnd))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/fractionofdistancethroughglyph(for:)
    open func fractionOfDistanceThroughGlyph(for point: CGPoint) -> CGFloat {
        guard let line = _line else { return 0 }
        let x = point.x - _glyphOrigin.x
        var index = CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
        index = max(_characterRange.location, min(index, _visibleEnd))
        if index >= _visibleEnd, index > _characterRange.location { index -= 1 }
        let x0 = CGFloat(CTLineGetOffsetForStringIndex(line, index, nil)), x1 = CGFloat(CTLineGetOffsetForStringIndex(line, index + 1, nil))
        return x1 > x0 ? max(0, min(1, (x - x0) / (x1 - x0))) : 0
    }
    /// Where the character at `index` starts: x relative to `typographicBounds.origin`, y at
    /// the baseline.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/locationforcharacter(at:)
    open func locationForCharacter(at index: Int) -> CGPoint { CGPoint(x: _caretOffset(index), y: _glyphOrigin.y) }

    /// Draws the line with `typographicBounds.origin` at `point`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextlinefragment/draw(at:in:)
    open func draw(at point: CGPoint, in context: CGContext) {
        guard let line = _drawnLine else { return }
        let flipped = MainActor.assumeIsolated { NSGraphicsContext.current?.isFlipped ?? true }
        context.saveGState()
        context.translateBy(x: point.x + _glyphOrigin.x, y: point.y + _glyphOrigin.y)
        if flipped { context.scaleBy(x: 1, y: -1) }
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
