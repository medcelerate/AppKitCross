// NSTextField (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield
@MainActor open class NSTextField: NSControl, NSUserInterfaceValidations, NSAccessibilityNavigableStaticText, NSAccessibilityStaticText, NSTextContent {
    // MARK: Storage
    private weak var _delegate: (any NSTextFieldDelegate)?
    private var _maximumNumberOfLines = 1
    private var _preferredMaxLayoutWidth: CGFloat = 0
    private var _allowsEditingTextAttributes = false
    private var _importsGraphics = false
    private var _allowsDefaultTighteningForTruncation = false
    private var _lineBreakStrategy: NSParagraphStyle.LineBreakStrategy = []
    private var _isAutomaticTextCompletionEnabled = true
    private var _allowsCharacterPickerTouchBarItem = true
    private var _contentType: NSTextContentType? = nil

    // Inline editing state (no field editor yet: the field edits its own string).
    private var _isEditing = false
    private var _selection = NSRange(location: 0, length: 0)   // UTF-16 offsets into stringValue
    private var _editedSinceBegin = false

    internal var _fieldCell: NSTextFieldCell? { _cell as? NSTextFieldCell }

    @MainActor open override func resetCursorRects() {
        if isEnabled && (isEditable || isSelectable) { addCursorRect(bounds, cursor: .iBeam) }
    }

    /// True while editing: Return commits the field before key equivalents run.
    internal var _consumesReturnKey: Bool { _isEditing && isEditable }

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSTextFieldCell(textCell: "") }


    // MARK: Editing helpers

    private var _utf16: [UInt16] { Array(stringValue.utf16) }

    private func _setString(_ units: [UInt16]) {
        stringValue = String(decoding: units, as: UTF16.self)
        _editedSinceBegin = true
        textDidChange(Notification(name: NSControl.textDidChangeNotification, object: self))
    }

    private func _replaceSelection(with text: String) {
        var units = _utf16
        let r = _clampedSelection
        units.replaceSubrange(r.location..<(r.location + r.length), with: Array(text.utf16))
        _selection = NSRange(location: r.location + text.utf16.count, length: 0)
        _setString(units)
    }

    private var _clampedSelection: NSRange {
        let n = _utf16.count
        let loc = min(max(0, _selection.location), n)
        return NSRange(location: loc, length: min(max(0, _selection.length), n - loc))
    }

    /// Caret x offset (points, from the text rect's left edge) for a UTF-16 offset.
    private func _xOffset(for offset: Int) -> CGFloat {
        guard let cell = _fieldCell else { return 0 }
        let prefix = String(decoding: _utf16.prefix(offset), as: UTF16.self)
        return prefix.isEmpty ? 0 : prefix.size(withAttributes: cell._attributes).width
    }

    private func _offset(forX x: CGFloat) -> Int {
        let units = _utf16
        var best = 0
        var bestDistance = CGFloat.infinity
        for i in 0...units.count {
            let d = abs(_xOffset(for: i) - x)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    private func _textRect() -> NSRect { _fieldCell?._textRect(forBounds: bounds) ?? bounds }

    private func _endEditing(sendAction: Bool) {
        guard _isEditing else { return }
        _isEditing = false
        textDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: self))
        if sendAction { _fireAction() }
        needsDisplay = true
    }

    @MainActor open override func becomeFirstResponder() -> Bool {
        guard isEditable || isSelectable else { return false }
        if isEditable && !_isEditing {
            _isEditing = true
            _editedSinceBegin = false
            textDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: self))
        }
        needsDisplay = true
        return true
    }

    @MainActor open override func resignFirstResponder() -> Bool {
        _endEditing(sendAction: _editedSinceBegin)
        needsDisplay = true
        return true
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, isEditable || isSelectable else { super.mouseDown(with: event); return }
        if window?.firstResponder !== self { _ = window?.makeFirstResponder(self) }
        let p = convert(event.locationInWindow, from: nil)
        let offset = _offset(forX: p.x - _textRect().minX)
        _selection = event.clickCount >= 2 ? NSRange(location: 0, length: _utf16.count) : NSRange(location: offset, length: 0)
        needsDisplay = true
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard window?.firstResponder === self else { return }
        let p = convert(event.locationInWindow, from: nil)
        let offset = _offset(forX: p.x - _textRect().minX)
        let anchor = _selection.length == 0 ? _selection.location : _selection.location
        _selection = NSRange(location: min(anchor, offset), length: abs(offset - anchor))
        needsDisplay = true
    }

    @MainActor open override func keyDown(with event: NSEvent) {
        guard _isEditing, isEditable else { super.keyDown(with: event); return }
        let chars = event.charactersIgnoringModifiers ?? ""
        let flags = event.modifierFlags
        let n = _utf16.count
        let sel = _clampedSelection
        switch chars {
        case "\r", "\u{3}":
            // Ending editing sends the action (resignFirstResponder); Enter always sends it.
            _editedSinceBegin = true
            _ = window?.makeFirstResponder(nil)
            return
        case "\t":
            _ = window?.makeFirstResponder(nil)
            return
        case "\u{1B}":
            _selection = NSRange(location: n, length: 0)
            needsDisplay = true
            return
        case "\u{7F}", "\u{8}":            // backspace
            if sel.length > 0 { _replaceSelection(with: "") }
            else if sel.location > 0 { _selection = NSRange(location: sel.location - 1, length: 1); _replaceSelection(with: "") }
            needsDisplay = true
            return
        case "\u{F728}":                   // forward delete
            if sel.length > 0 { _replaceSelection(with: "") }
            else if sel.location < n { _selection = NSRange(location: sel.location, length: 1); _replaceSelection(with: "") }
            needsDisplay = true
            return
        case "\u{F702}":                   // left
            let target = max(0, (sel.length > 0 && !flags.contains(.shift)) ? sel.location : sel.location - 1)
            _selection = flags.contains(.shift) ? NSRange(location: max(0, sel.location - 1), length: sel.length + (sel.location > 0 ? 1 : 0)) : NSRange(location: target, length: 0)
            needsDisplay = true
            return
        case "\u{F703}":                   // right
            if flags.contains(.shift) { _selection = NSRange(location: sel.location, length: min(n - sel.location, sel.length + 1)) }
            else { _selection = NSRange(location: min(n, sel.length > 0 ? sel.location + sel.length : sel.location + 1), length: 0) }
            needsDisplay = true
            return
        case "\u{F729}", "\u{F700}":      // home / up
            _selection = NSRange(location: 0, length: 0); needsDisplay = true; return
        case "\u{F72B}", "\u{F701}":      // end / down
            _selection = NSRange(location: n, length: 0); needsDisplay = true; return
        default:
            break
        }
        if (flags.contains(.command) || flags.contains(.control)) && chars.lowercased() == "a" {
            _selection = NSRange(location: 0, length: n)
            needsDisplay = true
            return
        }
        if flags.contains(.command) || flags.contains(.control) { super.keyDown(with: event); return }
        guard let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && ($0.value < 0xF700 || $0.value > 0xF8FF) }) else {
            super.keyDown(with: event)
            return
        }
        _replaceSelection(with: text)
        needsDisplay = true
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        _cell?.draw(withFrame: _cellFrame, in: self)
        guard _isEditing, window?.firstResponder === self, let cell = _fieldCell else { return }
        let rect = cell._textRect(forBounds: bounds)
        let font = cell._effectiveFont
        let lineHeight = font.ascender - font.descender
        let top = isFlipped ? rect.midY - lineHeight / 2 : rect.midY + lineHeight / 2
        let sel = _clampedSelection
        if sel.length > 0 {
            let x0 = rect.minX + _xOffset(for: sel.location), x1 = rect.minX + _xOffset(for: sel.location + sel.length)
            NSColor.selectedTextBackgroundColor.setFill()
            NSBezierPath.fill(NSRect(x: x0, y: isFlipped ? top : top - lineHeight, width: x1 - x0, height: lineHeight))
            cell.drawInterior(withFrame: bounds, in: self)
        }
        let cx = rect.minX + _xOffset(for: sel.location + (sel.length > 0 ? sel.length : 0))
        (textColor ?? .textColor).setFill()
        NSBezierPath.fill(NSRect(x: cx.rounded(), y: isFlipped ? top : top - lineHeight, width: 1, height: lineHeight))
    }

    @MainActor open override var intrinsicContentSize: NSSize {
        guard let cell = _fieldCell else { return super.intrinsicContentSize }
        if cell._isMultiline && _preferredMaxLayoutWidth > 0 {
            var s = cell._measure(maxWidth: _preferredMaxLayoutWidth)
            s.width += 4; s.height += 2
            return s
        }
        return cell.cellSize
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/init(labelwithattributedstring:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(labelWithAttributedString attributedStringValue: NSAttributedString) {
        self.init(labelWithString: attributedStringValue.string)
        self.attributedStringValue = attributedStringValue
        sizeToFit()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/init(labelwithstring:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(labelWithString stringValue: String) {
        self.init(frame: .zero)
        self.stringValue = stringValue
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byClipping
        usesSingleLineMode = true
        sizeToFit()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/init(string:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(string stringValue: String) {
        self.init(frame: .zero)
        self.stringValue = stringValue
        sizeToFit()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/init(wrappinglabelwithstring:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(wrappingLabelWithString stringValue: String) {
        self.init(labelWithString: stringValue)
        isSelectable = true
        usesSingleLineMode = false
        _cell?.wraps = true
        lineBreakMode = .byWordWrapping
        _maximumNumberOfLines = 0
        sizeToFit()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/acceptsfirstresponder
    @MainActor open override var acceptsFirstResponder: Bool { (isEditable || isSelectable) && isEnabled && !refusesFirstResponder }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/allowscharacterpickertouchbaritem
    @available(macOS 10.12, *)
    @MainActor open var allowsCharacterPickerTouchBarItem: Bool {
        get { _allowsCharacterPickerTouchBarItem }
        set { _allowsCharacterPickerTouchBarItem = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/allowsdefaulttighteningfortruncation
    @available(macOS 10.11, *)
    @MainActor open var allowsDefaultTighteningForTruncation: Bool {
        get { _allowsDefaultTighteningForTruncation }
        set { _allowsDefaultTighteningForTruncation = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/allowseditingtextattributes
    @MainActor open var allowsEditingTextAttributes: Bool {
        get { _allowsEditingTextAttributes }
        set { _allowsEditingTextAttributes = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/allowswritingtools
    @available(macOS 15.2, *)
    @MainActor open var allowsWritingTools: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/allowswritingtoolsaffordance
    @available(macOS 15.4, *)
    @MainActor open var allowsWritingToolsAffordance: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/backgroundcolor
    @MainActor open var backgroundColor: NSColor? {
        get { _fieldCell?.backgroundColor ?? nil }
        set { _fieldCell?.backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/bezelstyle
    @MainActor open var bezelStyle: NSTextField.BezelStyle {
        get { _fieldCell?.bezelStyle ?? .squareBezel }
        set { _fieldCell?.bezelStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/delegate
    @MainActor open var delegate: (any NSTextFieldDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _fieldCell?.drawsBackground ?? false }
        set { _fieldCell?.drawsBackground = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/importsgraphics
    @MainActor open var importsGraphics: Bool {
        get { _importsGraphics }
        set { _importsGraphics = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/isautomatictextcompletionenabled
    @available(macOS 10.12, *)
    @MainActor open var isAutomaticTextCompletionEnabled: Bool {
        get { _isAutomaticTextCompletionEnabled }
        set { _isAutomaticTextCompletionEnabled = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/isbezeled
    @MainActor open var isBezeled: Bool {
        get { _cell?.isBezeled ?? false }
        set { _cell?.isBezeled = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/isbordered
    @MainActor open var isBordered: Bool {
        get { _cell?.isBordered ?? false }
        set { _cell?.isBordered = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/iseditable
    @MainActor open var isEditable: Bool {
        get { _cell?.isEditable ?? false }
        set { _cell?.isEditable = newValue; if newValue { _cell?.isSelectable = true } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/isselectable
    @MainActor open var isSelectable: Bool {
        get { _cell?.isSelectable ?? false }
        set { _cell?.isSelectable = newValue; if !newValue { _cell?.isEditable = false } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/linebreakstrategy
    @available(macOS 10.15, *)
    @MainActor open var lineBreakStrategy: NSParagraphStyle.LineBreakStrategy {
        get { _lineBreakStrategy }
        set { _lineBreakStrategy = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/maximumnumberoflines
    @available(macOS 10.11, *)
    @MainActor open var maximumNumberOfLines: Int {
        get { _maximumNumberOfLines }
        set { _maximumNumberOfLines = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/placeholderattributedstring
    @available(macOS 10.10, *)
    @MainActor open var placeholderAttributedString: NSAttributedString? {
        get { _fieldCell?.placeholderAttributedString ?? nil }
        set { _fieldCell?.placeholderAttributedString = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/placeholderattributedstrings
    @available(macOS 26.0, *)
    @MainActor open var placeholderAttributedStrings: [NSAttributedString] {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/placeholderstring
    @available(macOS 10.10, *)
    @MainActor open var placeholderString: String? {
        get { _fieldCell?.placeholderString ?? nil }
        set { _fieldCell?.placeholderString = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/placeholderstrings
    @available(macOS 26.0, *)
    @MainActor open var placeholderStrings: [String] {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/preferredmaxlayoutwidth
    @MainActor open var preferredMaxLayoutWidth: CGFloat {
        get { _preferredMaxLayoutWidth }
        set { _preferredMaxLayoutWidth = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/resolvesnaturalalignmentwithbasewritingdirection
    @available(macOS 26.0, *)
    @MainActor open var resolvesNaturalAlignmentWithBaseWritingDirection: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/selecttext(_:)
    @MainActor open func selectText(_ sender: Any?) {
        guard isEditable || isSelectable else { return }
        _ = window?.makeFirstResponder(self)
        _selection = NSRange(location: 0, length: _utf16.count)
        needsDisplay = true
    }
    // SKIPPED (pending type NSTextSuggestionsDelegate): @MainActor var suggestionsDelegate: (any NSTextSuggestionsDelegate)? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textcolor
    @MainActor open var textColor: NSColor? {
        get { _fieldCell?.textColor ?? nil }
        set { _fieldCell?.textColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textdidbeginediting(_:)
    @MainActor open func textDidBeginEditing(_ notification: Notification) {
        NotificationCenter.default.post(name: NSControl.textDidBeginEditingNotification, object: self)
        _delegate?.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textdidchange(_:)
    @MainActor open func textDidChange(_ notification: Notification) {
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: self)
        _delegate?.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textdidendediting(_:)
    @MainActor open func textDidEndEditing(_ notification: Notification) {
        NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: self)
        _delegate?.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textshouldbeginediting(_:)
    @MainActor open func textShouldBeginEditing(_ textObject: NSText) -> Bool { _delegate?.control(self, textShouldBeginEditing: textObject) ?? true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textshouldendediting(_:)
    @MainActor open func textShouldEndEditing(_ textObject: NSText) -> Bool { _delegate?.control(self, textShouldEndEditing: textObject) ?? true }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityString(for range: NSRange) -> String? { unimplemented() }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityLine(for index: Int) -> Int { unimplemented() }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityRange(forLine lineNumber: Int) -> NSRange { unimplemented() }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityFrame(for range: NSRange) -> NSRect { unimplemented() }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityValue() -> String? { unimplemented() }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? { unimplemented() }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityVisibleCharacterRange() -> NSRange { unimplemented() }
    // Requirement of NSTextContent
    open var contentType: NSTextContentType? {
        get { MainActor.assumeIsolated { _contentType } }
        set { MainActor.assumeIsolated { _contentType = newValue } }
    }
}
