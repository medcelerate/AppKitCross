// NSTextFieldCell (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell
@MainActor open class NSTextFieldCell: NSActionCell {
    // MARK: Storage
    private var _bezelStyle: NSTextField.BezelStyle = .squareBezel
    private var _backgroundColor: NSColor? = nil
    private var _drawsBackground = false
    private var _textColorValue: NSColor? = nil
    private var _placeholderString: String? = nil
    private var _placeholderAttributedString: NSAttributedString? = nil
    private var _allowedInputSourceLocales: [String]? = nil

    @MainActor internal override func _copyCellState(from other: NSCell) {
        super._copyCellState(from: other)
        guard let o = other as? NSTextFieldCell else { return }
        _bezelStyle = o._bezelStyle; _backgroundColor = o._backgroundColor; _drawsBackground = o._drawsBackground
        _textColorValue = o._textColorValue; _placeholderString = o._placeholderString
        _placeholderAttributedString = o._placeholderAttributedString; _allowedInputSourceLocales = o._allowedInputSourceLocales
    }

    internal override var _textColor: NSColor {
        // Emphasized (a selected row in a key window): light text over the selection colour.
        if _backgroundStyle == .emphasized, _isEnabled, _textColorValue == nil || _textColorValue == .labelColor || _textColorValue == .textColor || _textColorValue == .controlTextColor { return .alternateSelectedControlTextColor }
        return _isEnabled ? (_textColorValue ?? .textColor) : .disabledControlTextColor
    }

    /// Rect the text is laid out in (bezel inset + 2 pt padding).
    @MainActor internal func _textRect(forBounds rect: NSRect) -> NSRect {
        var r = rect
        if _isBezeled || _isBordered { r = r.insetBy(dx: 3, dy: 1) }
        return r.insetBy(dx: 2, dy: 0)
    }

    @MainActor internal var _isMultiline: Bool { !_usesSingleLineMode && _wraps }

    @MainActor internal var _attributes: [NSAttributedString.Key: Any] { [.font: _effectiveFont, .foregroundColor: _textColor] }

    /// The text drawn and measured for the value (a secure cell's bullets).
    @MainActor internal var _displayedString: String { stringValue }

    @MainActor internal func _measure(maxWidth: CGFloat?) -> NSSize {
        let shown = _displayedString
        var s = shown.size(withAttributes: _attributes)
        if _isMultiline, let maxWidth, maxWidth > 0 {
            s = _NSTextMeasureCache.measure(shown, font: _effectiveFont, maxWidth: maxWidth)
        }
        if shown.isEmpty { s.height = _effectiveFont.ascender - _effectiveFont.descender }
        return s
    }

    @MainActor open override var cellSize: NSSize {
        var s = _measure(maxWidth: nil)
        s.width += 4; s.height += 2
        if _isBezeled || _isBordered { s.width += 6; s.height += 4 }
        return s
    }

    @MainActor open override func titleRect(forBounds rect: NSRect) -> NSRect { _textRect(forBounds: rect) }

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        if _drawsBackground {
            (_backgroundColor ?? .textBackgroundColor).setFill()
            NSBezierPath.fill(cellFrame)
        }
        if _isBezeled {
            let focused = (controlView.window?.firstResponder === controlView) && (controlView.window?.isKeyWindow ?? false)
            (focused ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor.withAlphaComponent(0.7)).setStroke()
            let path = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: _bezelStyle == .roundedBezel ? cellFrame.height / 2 : 3, yRadius: _bezelStyle == .roundedBezel ? cellFrame.height / 2 : 3)
            path.lineWidth = focused ? 2 : 1
            path.stroke()
        } else if _isBordered {
            NSColor.separatorColor.setStroke()
            NSBezierPath.stroke(cellFrame.insetBy(dx: 0.5, dy: 0.5))
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    /// True while the field editor shows the text.
    internal var _hidesText = false
    /// NSTextField's `placeholderAttributedStrings` (macOS 26), longest first as given.
    internal var _placeholderCandidates: [NSAttributedString] = []

    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if _hidesText { return }
        let rect = _textRect(forBounds: cellFrame)
        let flipped = controlView.isFlipped
        if stringValue.isEmpty {
            var attrs = _attributes
            attrs[.foregroundColor] = NSColor.placeholderTextColor
            if !_placeholderCandidates.isEmpty {
                // NSTextField.placeholderAttributedStrings: the first that fits the width, else the last.
                let fitting = _placeholderCandidates.first { $0.size().width <= rect.width } ?? _placeholderCandidates.last!
                _drawText(fitting.string, attributes: attrs.merging(fitting.length > 0 ? fitting.attributes(at: 0, effectiveRange: nil) : [:]) { $1 }, in: rect, alignment: _alignment, flipped: flipped)
            } else if let a = _placeholderAttributedString, a.length > 0 {
                _drawText(a.string, attributes: attrs.merging(a.attributes(at: 0, effectiveRange: nil)) { $1 }, in: rect, alignment: _alignment, flipped: flipped)
            } else if let p = _placeholderString, !p.isEmpty {
                _drawText(p, attributes: attrs, in: rect, alignment: _alignment, flipped: flipped)
            }
            return
        }
        let shown = _displayedString
        if _isMultiline {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.clip(to: rect)
            shown.draw(in: rect, withAttributes: _attributes)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            _drawText(shown, attributes: _attributes, in: rect, alignment: _alignment, flipped: flipped)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/init(coder:)
    public required init(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _isEditable = true
        _isSelectable = true
        _isBezeled = true
        _drawsBackground = true
        _usesSingleLineMode = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/allowedinputsourcelocales
    @MainActor open var allowedInputSourceLocales: [String]? {
        get { _allowedInputSourceLocales }
        set { _allowedInputSourceLocales = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/backgroundcolor
    @MainActor open var backgroundColor: NSColor? {
        get { _backgroundColor }
        set { _backgroundColor = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/bezelstyle
    @MainActor open var bezelStyle: NSTextField.BezelStyle {
        get { _bezelStyle }
        set { _bezelStyle = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _drawsBackground }
        set { _drawsBackground = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/placeholderattributedstring
    @MainActor open var placeholderAttributedString: NSAttributedString? {
        get { _placeholderAttributedString }
        set { _placeholderAttributedString = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/placeholderstring
    @MainActor open var placeholderString: String? {
        get { _placeholderString }
        set { _placeholderString = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/setupfieldeditorattributes(_:)
    @MainActor open override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        let editor = super.setUpFieldEditorAttributes(textObj)
        if let c = textColor, isEnabled { editor.textColor = c }
        return editor
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/setwantsnotificationformarkedtext(_:)
    @MainActor open func setWantsNotificationForMarkedText(_ flag: Bool) { _wantsNotificationForMarkedText = flag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfieldcell/textcolor
    @MainActor open var textColor: NSColor? {
        get { _textColorValue }
        set { _textColorValue = newValue; _changed() }
    }
}
