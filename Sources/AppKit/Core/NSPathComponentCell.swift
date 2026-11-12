// NSPathComponentCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The text field cell `NSPathCell` draws each component with: its title, an optional
// image before the title, and the URL of the path up to that component.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcomponentcell
@MainActor open class NSPathComponentCell: NSTextFieldCell {
    private var _url: URL? = nil

    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _isBezeled = false
        _isBordered = false
        _isEditable = false
        _isSelectable = false
        drawsBackground = false
        _usesSingleLineMode = true
        _lineBreakMode = .byTruncatingMiddle
    }
    public required init(coder: NSCoder) { super.init(coder: coder) }

    /// The image's side (square) when there is one.
    internal var _imageSide: CGFloat { _image == nil ? 0 : 16 }

    @MainActor open override var cellSize: NSSize {
        var s = stringValue.isEmpty ? NSSize(width: 0, height: _effectiveFont.ascender - _effectiveFont.descender) : stringValue.size(withAttributes: _attributes)
        s.width += 6
        if _image != nil { s.width += _imageSide + 4 }
        s.height = max(s.height + 2, _imageSide)
        return s
    }

    /// The image at the leading edge, then the title (clipped at the trailing edge).
    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rtl = controlView.userInterfaceLayoutDirection == .rightToLeft
        var textRect = cellFrame.insetBy(dx: 3, dy: 0)
        if let image = _image {
            let side = _imageSide
            let x = rtl ? cellFrame.maxX - 3 - side : cellFrame.minX + 3
            image.draw(in: NSRect(x: x, y: cellFrame.midY - side / 2, width: side, height: side))
            if rtl { textRect.size.width -= side + 4 } else { textRect.origin.x += side + 4; textRect.size.width -= side + 4 }
        }
        guard !stringValue.isEmpty, textRect.width > 0 else { return }
        _drawText(stringValue, attributes: _attributes, in: textRect, alignment: .natural, flipped: controlView.isFlipped)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcomponentcell/image
    @MainActor open override var image: NSImage? {
        get { _image }
        set { _image = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcomponentcell/url
    @MainActor open var url: URL? {
        get { _url }
        set { _url = newValue }
    }
}
