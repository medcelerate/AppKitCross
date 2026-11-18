// NSTokenFieldCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A text field cell whose value is an array of represented objects, each drawn as a
// token (a pill, a rounded square, or plain text per `tokenStyle`) before the text being
// typed. The tokens live here and are laid out from the leading edge of the text rect;
// the field editor edits only what follows them (ADR-0021).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell
@MainActor open class NSTokenFieldCell: NSTextFieldCell {
    // MARK: Storage
    internal var _tokens: [Any] = []
    internal var _selectedToken = -1
    private var _tokenStyle: NSTokenField.TokenStyle = .default
    private var _tokenizingCharacterSet: CharacterSet = NSTokenFieldCell.defaultTokenizingCharacterSet
    private var _completionDelay: TimeInterval = NSTokenFieldCell.defaultCompletionDelay
    private weak var _delegate: (any NSTokenFieldCellDelegate)?
    /// The text typed after the tokens (kept here while no editor is up).
    internal var _trailingText = ""

    static let tokenSpacing: CGFloat = 3
    static let tokenPadding: CGFloat = 7
    static let menuChevronWidth: CGFloat = 10

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _tokens = _tokenize(string)
    }
    public required init(coder: NSCoder) { super.init(coder: coder) }

    private var _tokenField: NSTokenField? { _controlView as? NSTokenField }

    // MARK: Tokens

    /// A token for each piece of `string` between tokenizing characters (trimmed, non-empty).
    @MainActor internal func _tokenize(_ string: String) -> [Any] {
        _pieces(string).compactMap { _represented(for: $0) }
    }
    internal func _pieces(_ string: String) -> [String] {
        string.unicodeScalars.split(whereSeparator: { _tokenizingCharacterSet.contains($0) }).map { String(String.UnicodeScalarView($0)).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The represented object for an editing string: the delegate's, else the string.
    @MainActor internal func _represented(for string: String) -> Any? {
        if let f = _tokenField, let d = f._tokenDelegate, let o = d.tokenField(f, representedObjectForEditing: string) { return o }
        if let d = _delegate, let o = d.tokenFieldCell(self, representedObjectForEditing: string) { return o }
        return string
    }
    @MainActor internal func _displayString(for object: Any) -> String {
        if let f = _tokenField, let d = f._tokenDelegate, let s = d.tokenField(f, displayStringForRepresentedObject: object) { return s }
        if let d = _delegate, let s = d.tokenFieldCell(self, displayStringForRepresentedObject: object) { return s }
        if let s = object as? String { return s }
        return String(describing: object)
    }
    @MainActor internal func _editingString(for object: Any) -> String {
        if let f = _tokenField, let d = f._tokenDelegate, let s = d.tokenField(f, editingStringForRepresentedObject: object) { return s }
        if let d = _delegate, let s = d.tokenFieldCell(self, editingStringForRepresentedObject: object) { return s }
        return _displayString(for: object)
    }
    @MainActor internal func _hasMenu(_ object: Any) -> Bool {
        if let f = _tokenField, let d = f._tokenDelegate { return d.tokenField(f, hasMenuForRepresentedObject: object) }
        if let d = _delegate { return d.tokenFieldCell(self, hasMenuForRepresentedObject: object) }
        return false
    }
    @MainActor internal func _menu(for object: Any) -> NSMenu? {
        if let f = _tokenField, let d = f._tokenDelegate { return d.tokenField(f, menuForRepresentedObject: object) }
        if let d = _delegate { return d.tokenFieldCell(self, menuForRepresentedObject: object) }
        return nil
    }
    @MainActor internal func _style(for object: Any) -> NSTokenField.TokenStyle {
        var style: NSTokenField.TokenStyle = .default
        if let f = _tokenField, let d = f._tokenDelegate { style = d.tokenField(f, styleForRepresentedObject: object) }
        else if let d = _delegate { style = d.tokenFieldCell(self, styleForRepresentedObject: object) }
        return style == .default ? _tokenStyle : style
    }
    /// Filters tokens about to be added through the delegate's `shouldAdd`.
    @MainActor internal func _filtered(_ tokens: [Any], at index: Int) -> [Any] {
        guard !tokens.isEmpty else { return tokens }
        if let f = _tokenField, let d = f._tokenDelegate { return d.tokenField(f, shouldAdd: tokens, at: index) }
        if let d = _delegate { return d.tokenFieldCell(self, shouldAdd: tokens, at: index) }
        return tokens
    }

    /// The text of the field: the tokens' display strings joined by the tokenizing
    /// character, then whatever is typed after them.
    @MainActor internal var _joined: String {
        let sep = _separator
        var s = _tokens.map { _displayString(for: $0) }.joined(separator: sep)
        if !_trailingText.isEmpty { s += (s.isEmpty ? "" : sep) + _trailingText }
        return s
    }
    internal var _separator: String {
        if _tokenizingCharacterSet.contains(",") { return ", " }
        if let first = (0x21...0x7E).compactMap({ Unicode.Scalar($0) }).first(where: { _tokenizingCharacterSet.contains($0) }) { return String(Character(first)) + " " }
        return " "
    }

    // MARK: Geometry

    internal var _tokenFont: NSFont { _effectiveFont }

    /// The frame of each token laid out from the leading edge of the text rect (the
    /// menu chevron's width included), in token order.
    @MainActor internal func _tokenRects(in cellFrame: NSRect) -> [NSRect] {
        let text = super._textRect(forBounds: cellFrame)
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        let h = min(text.height, _tokenFont.ascender - _tokenFont.descender + 4)
        var x = rtl ? text.maxX : text.minX
        var rects: [NSRect] = []
        for t in _tokens {
            let w = _tokenWidth(t)
            if rtl { x -= w }
            rects.append(NSRect(x: x, y: text.midY - h / 2, width: w, height: h))
            if rtl { x -= NSTokenFieldCell.tokenSpacing } else { x += w + NSTokenFieldCell.tokenSpacing }
        }
        return rects
    }
    @MainActor internal func _tokenWidth(_ token: Any) -> CGFloat {
        let s = _displayString(for: token)
        var w = s.size(withAttributes: [.font: _tokenFont]).width
        let style = _style(for: token)
        if style != .none { w += 2 * NSTokenFieldCell.tokenPadding }
        else { w += _separator.size(withAttributes: [.font: _tokenFont]).width }
        if _hasMenu(token) { w += NSTokenFieldCell.menuChevronWidth }
        return w.rounded(.up)
    }
    /// The width the tokens take, spacing included.
    @MainActor internal func _tokensWidth(in cellFrame: NSRect) -> CGFloat {
        let rects = _tokenRects(in: cellFrame)
        guard !rects.isEmpty else { return 0 }
        return rects.reduce(0) { $0 + $1.width } + CGFloat(rects.count) * NSTokenFieldCell.tokenSpacing
    }

    /// The typed text (and the field editor) sits after the tokens, with at least 40 pt.
    @MainActor internal override func _textRect(forBounds rect: NSRect) -> NSRect {
        var r = super._textRect(forBounds: rect)
        let used = _tokensWidth(in: rect)
        guard used > 0 else { return r }
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        let w = max(40, r.width - used)
        if !rtl { r.origin.x += min(used, max(0, r.width - 40)) }
        r.size.width = w
        return r
    }

    /// The index of the token under a point of the cell frame, and whether the point is
    /// on its menu chevron.
    @MainActor internal func _token(at point: NSPoint, in cellFrame: NSRect) -> (index: Int, onMenu: Bool)? {
        let rtl = _controlView?.userInterfaceLayoutDirection == .rightToLeft
        for (i, r) in _tokenRects(in: cellFrame).enumerated() where r.contains(point) {
            guard _hasMenu(_tokens[i]) else { return (i, false) }
            let chevron = rtl ? NSRect(x: r.minX, y: r.minY, width: NSTokenFieldCell.menuChevronWidth + 4, height: r.height)
                              : NSRect(x: r.maxX - NSTokenFieldCell.menuChevronWidth - 4, y: r.minY, width: NSTokenFieldCell.menuChevronWidth + 4, height: r.height)
            return (i, chevron.contains(point))
        }
        return nil
    }

    @MainActor open override var cellSize: NSSize {
        var s = super.cellSize
        s.width += _tokens.reduce(0) { $0 + _tokenWidth($1) + NSTokenFieldCell.tokenSpacing }
        s.height = max(s.height, 22)
        return s
    }

    // MARK: Drawing

    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rects = _tokenRects(in: cellFrame)
        let flipped = controlView.isFlipped
        let rtl = controlView.userInterfaceLayoutDirection == .rightToLeft
        let focused = (controlView.window?.firstResponder as? NSText)?.superview === controlView || controlView.window?.firstResponder === controlView
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clip(to: super._textRect(forBounds: cellFrame))
        for (i, token) in _tokens.enumerated() {
            let r = rects[i]
            let style = _style(for: token)
            let selected = i == _selectedToken && focused
            let accent = NSColor.controlAccentColor
            var textColor: NSColor = _isEnabled ? accent.blended(withFraction: 0.35, of: .black) ?? accent : .disabledControlTextColor
            switch style {
            case .none:
                textColor = _isEnabled ? _textColor : .disabledControlTextColor
                if selected {
                    NSColor.selectedTextBackgroundColor.setFill()
                    NSBezierPath.fill(r)
                }
            case .plainSquared:
                (selected ? accent : accent.withAlphaComponent(0.6)).setStroke()
                let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
                p.lineWidth = 1
                p.stroke()
                if selected { accent.setFill(); p.fill(); textColor = .white }
            case .squared, .rounded, .default:
                let radius: CGFloat = style == .squared ? 3 : r.height / 2
                (selected ? accent : accent.withAlphaComponent(_isEnabled ? 0.22 : 0.12)).setFill()
                NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
                if selected { textColor = .white }
            }
            var textRect = r
            if style != .none { textRect = r.insetBy(dx: NSTokenFieldCell.tokenPadding, dy: 0) }
            if _hasMenu(token) {
                if rtl { textRect.origin.x += NSTokenFieldCell.menuChevronWidth }
                textRect.size.width -= NSTokenFieldCell.menuChevronWidth
                let cx = rtl ? r.minX + NSTokenFieldCell.tokenPadding : r.maxX - NSTokenFieldCell.tokenPadding
                let dy: CGFloat = flipped ? 1 : -1
                let chevron = NSBezierPath()
                chevron.move(to: NSPoint(x: cx - 2.5, y: r.midY + dy * 1.2))
                chevron.line(to: NSPoint(x: cx, y: r.midY - dy * 1.2))
                chevron.line(to: NSPoint(x: cx + 2.5, y: r.midY + dy * 1.2))
                chevron.lineWidth = 1.2
                chevron.lineCapStyle = .round
                chevron.lineJoinStyle = .round
                textColor.setStroke()
                chevron.stroke()
            }
            let display = _displayString(for: token) + (style == .none ? _separator : "")
            _drawText(display, attributes: [.font: _tokenFont, .foregroundColor: textColor], in: textRect, alignment: style == .none ? .natural : .center, flipped: flipped)
        }
        NSGraphicsContext.restoreGraphicsState()
        // The typed text after the tokens, or the placeholder when there is nothing at all.
        if _hidesText { return }
        let rect = _textRect(forBounds: cellFrame)
        if _trailingText.isEmpty {
            if _tokens.isEmpty, let p = placeholderString, !p.isEmpty {
                var attrs = _attributes
                attrs[.foregroundColor] = NSColor.placeholderTextColor
                _drawText(p, attributes: attrs, in: rect, alignment: _alignment, flipped: flipped)
            }
            return
        }
        _drawText(_trailingText, attributes: _attributes, in: rect, alignment: .natural, flipped: flipped)
    }

    // MARK: Values

    @MainActor open override var stringValue: String {
        get { _joined }
        set {
            _tokens = _tokenize(newValue)
            _trailingText = ""
            _selectedToken = -1
            _changed()
        }
    }
    @MainActor open override var objectValue: Any? {
        get { _tokens }
        set {
            switch newValue {
            case let a as [Any]: _tokens = a
            case let s as String: _tokens = _tokenize(s)
            case nil: _tokens = []
            case let other: _tokens = [other as Any]
            }
            _trailingText = ""
            _selectedToken = -1
            _changed()
        }
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell/completiondelay
    @MainActor open var completionDelay: TimeInterval {
        get { _completionDelay }
        set { _completionDelay = max(0, newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell/defaultcompletiondelay
    @MainActor class public var defaultCompletionDelay: TimeInterval { 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell/defaulttokenizingcharacterset
    @MainActor class public var defaultTokenizingCharacterSet: CharacterSet { CharacterSet(charactersIn: ",") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell/delegate
    @MainActor open var delegate: (any NSTokenFieldCellDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell/tokenstyle
    @MainActor open var tokenStyle: NSTokenField.TokenStyle {
        get { _tokenStyle }
        set { _tokenStyle = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfieldcell/tokenizingcharacterset
    @MainActor open var tokenizingCharacterSet: CharacterSet! {
        get { _tokenizingCharacterSet }
        set { _tokenizingCharacterSet = newValue ?? NSTokenFieldCell.defaultTokenizingCharacterSet }
    }
}
