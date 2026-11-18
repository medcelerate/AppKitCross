// NSFormCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// One titled entry of an NSForm (ADR-0032): the title on the left at `titleWidth`, then a
// bezeled text entry filling the rest of the cell. The cell's value (`stringValue`,
// `objectValue`) is the entry's text; `title` is the label. The enclosing NSMatrix edits
// the entry in the window's field editor laid over `_entryTextRect(forBounds:)`.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell
@MainActor open class NSFormCell: NSActionCell {
    // MARK: Storage
    private var _title = ""
    private var _attributedTitle: NSAttributedString? = nil
    private var _titleFont: NSFont? = nil
    private var _titleAlignment: NSTextAlignment = .right
    private var _titleBaseWritingDirection: NSWritingDirection = .natural
    private var _explicitTitleWidth: CGFloat? = nil
    private var _placeholderString: String? = nil
    private var _placeholderAttributedString: NSAttributedString? = nil
    private var _preferredTextFieldWidth: CGFloat = 0

    /// The width NSForm gives every entry's title so the entries line up.
    internal var _formTitleWidth: CGFloat? = nil
    /// True while the field editor shows the entry's text.
    internal var _hidesEntryText = false

    /// Space between the title and the entry.
    private static let titleGap: CGFloat = 4

    private func _setUpEntry() {
        _isEditable = true
        _isSelectable = true
        _isBezeled = true
        _type = .textCellType
        _usesSingleLineMode = true
        _alignment = .natural
    }

    @MainActor internal override func _copyCellState(from other: NSCell) {
        super._copyCellState(from: other)
        guard let o = other as? NSFormCell else { return }
        _title = o._title; _attributedTitle = o._attributedTitle; _titleFont = o._titleFont; _titleAlignment = o._titleAlignment
        _titleBaseWritingDirection = o._titleBaseWritingDirection; _explicitTitleWidth = o._explicitTitleWidth
        _placeholderString = o._placeholderString; _placeholderAttributedString = o._placeholderAttributedString
        _preferredTextFieldWidth = o._preferredTextFieldWidth
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/init(coder:)
    public required init(coder: NSCoder) {
        super.init(coder: coder)
        _setUpEntry()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/init(textcell:)
    /// The string is the title; the entry starts empty.
    @MainActor public override init(textCell string: String?) {
        super.init(textCell: "")
        _title = string ?? ""
        _setUpEntry()
    }

    // MARK: Title

    private var _effectiveTitleFont: NSFont { _titleFont ?? _effectiveFont }
    private var _titleAttributes: [NSAttributedString.Key: Any] {
        [.font: _effectiveTitleFont, .foregroundColor: _isEnabled ? NSColor.controlTextColor : NSColor.disabledControlTextColor]
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/title
    @MainActor open override var title: String {
        get { _attributedTitle?.string ?? _title }
        set { _title = newValue; _attributedTitle = nil; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/attributedtitle
    @MainActor open var attributedTitle: NSAttributedString {
        get { _attributedTitle ?? NSAttributedString(string: _title, attributes: _titleAttributes) }
        set { _attributedTitle = newValue; _title = newValue.string; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/titlefont
    @MainActor open var titleFont: NSFont {
        get { _effectiveTitleFont }
        set { _titleFont = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/titlealignment
    @MainActor open var titleAlignment: NSTextAlignment {
        get { _titleAlignment }
        set { _titleAlignment = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/titlebasewritingdirection
    @MainActor open var titleBaseWritingDirection: NSWritingDirection {
        get { _titleBaseWritingDirection }
        set { _titleBaseWritingDirection = newValue; _changed() }
    }

    /// The title's natural width: its text plus a little padding.
    private var _naturalTitleWidth: CGFloat {
        let t = title
        return t.isEmpty ? 0 : ceil(t.size(withAttributes: _titleAttributes).width) + 4
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/titlewidth
    /// A width set here wins; otherwise the form's shared width, otherwise the title's own.
    @MainActor open var titleWidth: CGFloat {
        get { _explicitTitleWidth ?? _formTitleWidth ?? _naturalTitleWidth }
        set { _explicitTitleWidth = newValue < 0 ? nil : newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/titlewidth(_:)
    @MainActor open func titleWidth(_ size: NSSize) -> CGFloat { min(titleWidth, max(0, size.width)) }
    /// The title's own width, for NSForm's shared width (ignores the shared width).
    internal var _ownTitleWidth: CGFloat { _explicitTitleWidth ?? _naturalTitleWidth }

    // MARK: Entry

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/placeholderstring
    @MainActor open var placeholderString: String? {
        get { _placeholderString ?? _placeholderAttributedString?.string }
        set { _placeholderString = newValue; _placeholderAttributedString = nil; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/placeholderattributedstring
    @MainActor open var placeholderAttributedString: NSAttributedString? {
        get { _placeholderAttributedString }
        set { _placeholderAttributedString = newValue; _placeholderString = nil; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/preferredtextfieldwidth
    @MainActor open var preferredTextFieldWidth: CGFloat {
        get { _preferredTextFieldWidth }
        set { _preferredTextFieldWidth = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsformcell/isopaque
    /// Opaque when the bezeled entry fills the whole cell (no title).
    @MainActor open override var isOpaque: Bool { _isBezeled && title.isEmpty }

    /// The entry's frame within the cell frame.
    internal func _entryFrame(forBounds rect: NSRect) -> NSRect {
        let tw = titleWidth(rect.size)
        let x = rect.minX + tw + (tw > 0 ? NSFormCell.titleGap : 0)
        return NSRect(x: x, y: rect.minY, width: max(0, rect.maxX - x), height: rect.height)
    }
    /// The title's frame within the cell frame.
    internal func _titleFrame(forBounds rect: NSRect) -> NSRect {
        NSRect(x: rect.minX, y: rect.minY, width: titleWidth(rect.size), height: rect.height)
    }
    /// Where the entry's text is laid out (bezel inset plus padding, as NSTextFieldCell).
    internal func _entryTextRect(forBounds rect: NSRect) -> NSRect {
        var r = _entryFrame(forBounds: rect)
        if _isBezeled || _isBordered { r = r.insetBy(dx: 3, dy: 1) }
        return r.insetBy(dx: 2, dy: 0)
    }

    @MainActor open override func titleRect(forBounds rect: NSRect) -> NSRect { _titleFrame(forBounds: rect) }
    @MainActor open override func drawingRect(forBounds rect: NSRect) -> NSRect { _entryTextRect(forBounds: rect) }

    @MainActor open override var cellSize: NSSize {
        let text = stringValue.isEmpty ? NSSize(width: 0, height: _effectiveFont.ascender - _effectiveFont.descender) : stringValue.size(withAttributes: _textAttributes)
        let entryWidth = _preferredTextFieldWidth > 0 ? _preferredTextFieldWidth : text.width + 10
        let tw = titleWidth
        let titleHeight = _effectiveTitleFont.ascender - _effectiveTitleFont.descender
        return NSSize(width: ceil(tw + (tw > 0 ? NSFormCell.titleGap : 0) + entryWidth), height: ceil(max(text.height, titleHeight) + 6))
    }
    @MainActor open override func cellSize(forBounds rect: NSRect) -> NSSize { cellSize }

    // MARK: Drawing

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        let flipped = controlView.isFlipped
        let titleFrame = _titleFrame(forBounds: cellFrame)
        if titleFrame.width > 0 {
            let attrs = _attributedTitle.map { $0.attributes(at: 0, effectiveRange: nil) } ?? _titleAttributes
            _drawText(title, attributes: attrs.isEmpty ? _titleAttributes : attrs, in: titleFrame.insetBy(dx: 1, dy: 0), alignment: _titleAlignment, flipped: flipped)
        }
        let entry = _entryFrame(forBounds: cellFrame)
        guard entry.width > 0 else { return }
        if _isBezeled || _isBordered {
            NSColor.textBackgroundColor.setFill()
            NSBezierPath.fill(entry)
            let editing = (controlView as? NSControl)?.currentEditor() != nil && _hidesEntryText
            let stroke: NSColor = editing ? .keyboardFocusIndicatorColor : NSColor.separatorColor.withAlphaComponent(0.7)
            stroke.setStroke()
            let path = NSBezierPath(roundedRect: entry.insetBy(dx: 0.5, dy: 0.5), xRadius: _isBezeled ? 3 : 0, yRadius: _isBezeled ? 3 : 0)
            path.lineWidth = editing ? 2 : 1
            path.stroke()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if _hidesEntryText { return }
        let rect = _entryTextRect(forBounds: cellFrame)
        let flipped = controlView.isFlipped
        let text = stringValue
        if text.isEmpty {
            if let p = placeholderString, !p.isEmpty {
                var attrs = _textAttributes
                attrs[.foregroundColor] = NSColor.placeholderTextColor
                _drawText(p, attributes: attrs, in: rect, alignment: _alignment, flipped: flipped)
            }
            return
        }
        var attrs = _textAttributes
        if _isEnabled { attrs[.foregroundColor] = NSColor.textColor }
        _drawText(text, attributes: attrs, in: rect, alignment: _alignment, flipped: flipped)
    }
}
