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
@MainActor open class NSTextField: NSControl, NSTextDelegate, NSUserInterfaceValidations, NSAccessibilityNavigableStaticText, NSAccessibilityStaticText, NSTextContent {
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

    // Editing happens in the window's field editor (an NSTextView) placed over the cell's text rect.
    private var _editor: NSTextView? = nil
    private var _editedSinceBegin = false
    private var _handingOffToEditor = false

    internal var _fieldCell: NSTextFieldCell? { _cell as? NSTextFieldCell }

    @MainActor open override func resetCursorRects() {
        if isEnabled && (isEditable || isSelectable) { addCursorRect(bounds, cursor: .iBeam) }
    }

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSTextFieldCell(textCell: "") }


    // MARK: Field editor

    /// The field editor while this field is being edited.
    public var currentEditor: NSText? { _editor }

    private func _editorFrame() -> NSRect {
        guard let cell = _fieldCell else { return bounds }
        return cell._textRect(forBounds: bounds)
    }

    /// Starts an editing session: configures the window's field editor over the text
    /// rect, makes it first responder and (with an event) hands the click to it.
    @discardableResult
    private func _beginEditing(with event: NSEvent? = nil) -> Bool {
        guard let w = window, isEnabled, isEditable || isSelectable else { return false }
        if _editor != nil { return true }
        guard let editor = w.fieldEditor(true, for: self) as? NSTextView else { return false }
        if let cell = _fieldCell { cell._hidesText = true }
        editor.string = _editorInitialString
        editor.font = font
        editor.textColor = textColor
        editor.drawsBackground = false
        editor.alignment = alignment
        editor.isEditable = isEditable
        editor.isSelectable = isEditable || isSelectable
        editor.isFieldEditor = true
        editor.delegate = self
        editor.frame = _editorFrame()
        editor.autoresizingMask = [.width, .height]
        _editor = editor
        _editedSinceBegin = false
        addSubview(editor)
        _handingOffToEditor = true
        let became = w.makeFirstResponder(editor)
        _handingOffToEditor = false
        guard became else { _detachEditor(); return false }
        if let e = event { editor.mouseDown(with: e) } else { editor.selectAll(nil) }
        needsDisplay = true
        return true
    }

    private func _detachEditor() {
        guard let editor = _editor else { return }
        editor.delegate = nil
        editor.removeFromSuperview()
        _editor = nil
        if let cell = _fieldCell { cell._hidesText = false }
        needsDisplay = true
    }

    // MARK: Editor hooks for subclasses (the search and token fields)

    /// The field editor, while editing (typed `NSTextView`).
    @MainActor internal var _fieldEditor: NSTextView? { _editor }
    /// Re-places the field editor over the (possibly changed) text rect.
    @MainActor internal func _relayoutEditor() { _editor?.frame = _editorFrame() }
    /// What the field editor starts with when editing begins.
    @MainActor internal var _editorInitialString: String { stringValue }
    /// The editor's text changed: keep the model current without redrawing the editor's text.
    @MainActor internal func _editorTextDidChange(_ editor: NSTextView) { _cell?.stringValue = editor.string }
    /// Editing ended (or Return was pressed): take the editor's text as the value.
    @MainActor internal func _takeEditorValue(_ editor: NSTextView) { stringValue = editor.string }
    /// A key-binding command the field editor is about to perform (`cancelOperation:`,
    /// `moveUp:`, ...). The delegate's `control(_:textView:doCommandBy:)` sees it first;
    /// subclasses then take what they need. Returns true when the command was handled.
    @MainActor internal func _editorDoCommand(by selector: Selector) -> Bool {
        guard let editor = _editor else { return false }
        return _delegate?.control(self, textView: editor, doCommandBy: selector) ?? false
    }

    /// The editor reported the end of a session: take the text and send the action.
    /// Return keeps the field editing with everything selected, as AppKit does; Tab moves
    /// focus; anything else detaches the editor.
    private func _finishEditing(movement: NSTextMovement) {
        guard let editor = _editor else { return }
        _takeEditorValue(editor)
        if movement == .return {
            _fireAction()
            _editedSinceBegin = false
            if _editor === editor {          // the action may have ended editing itself
                editor.selectAll(nil)
                editor._beginEditingIfNeeded()
            }
            return
        }
        let edited = _editedSinceBegin
        _detachEditor()
        if edited && movement != .cancel { _fireAction() }
        switch movement {
        case .tab: window?.selectKeyView(following: self)
        case .backtab: window?.selectKeyView(preceding: self)
        default: if let w = window, w.firstResponder === editor { _ = w.makeFirstResponder(nil) }
        }
    }

    @MainActor open override func becomeFirstResponder() -> Bool {
        guard isEditable || isSelectable else { return false }
        return _beginEditing()
    }

    @MainActor open override func resignFirstResponder() -> Bool {
        // The window moves first-responder status to the editor during the handoff.
        _handingOffToEditor || _editor == nil
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, isEditable || isSelectable else { super.mouseDown(with: event); return }
        if let e = _editor { e.mouseDown(with: event); return }
        _beginEditing(with: event)
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        _cell?.draw(withFrame: _cellFrame, in: self)
    }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _editor?.frame = _editorFrame()
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
        if _editor == nil { _ = window?.makeFirstResponder(self) }
        _editor?.selectAll(nil)
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
        if let e = _editor, (notification.object as? NSTextView) === e {
            _editedSinceBegin = true
            _editorTextDidChange(e)
            _accessibilityValueChanged()
        }
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: self)
        _delegate?.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textdidendediting(_:)
    @MainActor open func textDidEndEditing(_ notification: Notification) {
        if let e = _editor, (notification.object as? NSTextView) === e {
            let raw = notification.userInfo?["NSTextMovement"] as? Int ?? NSTextMovement.other.rawValue
            _finishEditing(movement: NSTextMovement(rawValue: raw) ?? .other)
        }
        NotificationCenter.default.post(name: NSControl.textDidEndEditingNotification, object: self)
        _delegate?.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: self))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textshouldbeginediting(_:)
    @MainActor open func textShouldBeginEditing(_ textObject: NSText) -> Bool { _delegate?.control(self, textShouldBeginEditing: textObject) ?? true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextfield/textshouldendediting(_:)
    @MainActor open func textShouldEndEditing(_ textObject: NSText) -> Bool { _delegate?.control(self, textShouldEndEditing: textObject) ?? true }
    // MARK: Accessibility (ADR-0013)
    //
    // A label is AXStaticText whose value is its string; an editable field is
    // AXTextField (AXSecureTextField for secure fields) with the placeholder and the
    // editor's selection, and assistive technology may set its text.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? (isEditable ? .textField : .staticText) }
    open override func accessibilitySubrole() -> NSAccessibility.Subrole? { _a11y.subrole ?? (_cell is NSSecureTextFieldCell ? .secureTextField : nil) }
    open override func accessibilityPlaceholderValue() -> String? { _a11y.placeholder ?? placeholderString }
    /// Editable fields are labelled by their placeholder when nothing else names them.
    open override func accessibilityLabel() -> String? { _a11y.label ?? (isEditable ? placeholderString : nil) }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : _accessibilityString }
    private var _accessibilityString: String { _cell is NSSecureTextFieldCell ? String(repeating: "\u{2022}", count: stringValue.count) : stringValue }
    override func _accessibilityValueIsSettable() -> Bool { isEditable && isEnabled }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard isEditable, isEnabled else { return false }
        if let e = _editor { e.string = value.stringValue; e.didChangeText() } else { stringValue = value.stringValue }
        _fireAction()
        return true
    }
    override func _accessibilityIsFocusable() -> Bool { (isEditable || isSelectable) && isEnabled && !isHiddenOrHasHiddenAncestor }
    /// The field editor's selection while editing, else the whole text unselected.
    open override func accessibilitySelectedTextRange() -> NSRange { _editor?.selectedRange ?? NSRange(location: 0, length: 0) }
    open override func accessibilityPerformConfirm() -> Bool { guard isEditable else { return false }; _fireAction(); return true }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityString(for range: NSRange) -> String? { (_accessibilityString as NSString)._accessibilitySubstring(range) }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityLine(for index: Int) -> Int { 0 }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityRange(forLine lineNumber: Int) -> NSRange { lineNumber == 0 ? NSRange(location: 0, length: (_accessibilityString as NSString).length) : NSRange(location: NSNotFound, length: 0) }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityFrame(for range: NSRange) -> NSRect { accessibilityFrame() }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityValue() -> String? { _accessibilityString }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? { accessibilityString(for: range).map { NSAttributedString(string: $0) } }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityVisibleCharacterRange() -> NSRange { NSRange(location: 0, length: (_accessibilityString as NSString).length) }
    open func accessibilityNumberOfCharacters() -> Int { (_accessibilityString as NSString).length }
    // Requirement of NSTextContent
    open var contentType: NSTextContentType? {
        get { MainActor.assumeIsolated { _contentType } }
        set { MainActor.assumeIsolated { _contentType = newValue } }
    }
}
