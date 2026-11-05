// NSTextView (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview
@MainActor open class NSTextView: NSText, NSSelectorHandling, NSColorChanging, NSMenuItemValidation, NSUserInterfaceValidations, NSTextInputClient, NSTextLayoutOrientationProvider, NSDraggingSource, NSTextInput, NSAccessibilityNavigableStaticText, NSAccessibilityStaticText, NSTextContent, NSCandidateListTouchBarItemDelegate, NSTouchBarDelegate {
    // MARK: Storage
    private var _typingAttributes: [NSAttributedString.Key: Any] = [:]
    private var _insertionPointColor: NSColor? = nil
    private var _selectedTextAttributes: [NSAttributedString.Key: Any] = [.backgroundColor: NSColor.selectedTextBackgroundColor]
    private var _markedTextAttributes: [NSAttributedString.Key: Any]? = [.underlineStyle: 1]
    private var _textContainerInset = NSSize.zero
    private var _allowsUndo = false
    private var _usesFindBar = false
    private var _isContinuousSpellCheckingEnabled = false
    private var _smartInsertDeleteEnabled = true
    private var _isAutomaticQuoteSubstitutionEnabled = false
    private var _isGrammarCheckingEnabled = false
    private var _isAutomaticSpellingCorrectionEnabled = false
    // The text system (ADR-0007): storage → layout manager → container, created with the view.
    private var _storage: NSTextStorage
    private var _layoutManager: NSLayoutManager
    private var _container: NSTextContainer

    private var _viewDelegate: (any NSTextViewDelegate)? { _textDelegate as? NSTextViewDelegate }

    /// The field editor's Return key must reach it before key equivalents (default buttons).
    internal var _consumesReturnKey: Bool { isFieldEditor && isEditable }

    // MARK: Key handling (standard key bindings)

    open override func keyDown(with event: NSEvent) {
        guard isEditable || isSelectable else { super.keyDown(with: event); return }
        if !_interpret(event) { super.keyDown(with: event) }
    }

    /// Maps a key event onto the standard key-binding selectors, or inserts its text.
    /// Returns false when the event is not handled here (key equivalents fall through).
    @discardableResult
    internal func _interpret(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let command = flags.contains(.command) || flags.contains(.control)
        let plain = event.charactersIgnoringModifiers ?? ""
        var selector: String? = nil
        switch plain {
        case "\r", "\u{3}": selector = "insertNewline:"
        case "\t": selector = shift ? "insertBacktab:" : "insertTab:"
        case "\u{1B}": selector = "cancelOperation:"
        case "\u{7F}", "\u{8}": selector = option ? "deleteWordBackward:" : "deleteBackward:"
        case "\u{F728}": selector = option ? "deleteWordForward:" : "deleteForward:"
        case "\u{F702}": selector = command ? (shift ? "moveToBeginningOfLineAndModifySelection:" : "moveToBeginningOfLine:") : option ? (shift ? "moveWordLeftAndModifySelection:" : "moveWordLeft:") : (shift ? "moveLeftAndModifySelection:" : "moveLeft:")
        case "\u{F703}": selector = command ? (shift ? "moveToEndOfLineAndModifySelection:" : "moveToEndOfLine:") : option ? (shift ? "moveWordRightAndModifySelection:" : "moveWordRight:") : (shift ? "moveRightAndModifySelection:" : "moveRight:")
        case "\u{F700}": selector = command ? (shift ? "moveToBeginningOfDocumentAndModifySelection:" : "moveToBeginningOfDocument:") : (shift ? "moveUpAndModifySelection:" : "moveUp:")
        case "\u{F701}": selector = command ? (shift ? "moveToEndOfDocumentAndModifySelection:" : "moveToEndOfDocument:") : (shift ? "moveDownAndModifySelection:" : "moveDown:")
        case "\u{F729}": selector = shift ? "moveToBeginningOfDocumentAndModifySelection:" : "moveToBeginningOfDocument:"
        case "\u{F72B}": selector = shift ? "moveToEndOfDocumentAndModifySelection:" : "moveToEndOfDocument:"
        case "\u{F72C}": selector = "pageUp:"
        case "\u{F72D}": selector = "pageDown:"
        default: break
        }
        if selector == nil && command {
            switch plain.lowercased() {
            case "a": selector = "selectAll:"
            case "c": selector = "copy:"
            case "x": selector = "cut:"
            case "v": selector = "paste:"
            default: return false     // other key equivalents belong to menus
            }
        }
        if let s = selector {
            doCommand(by: Selector((s)))
            return true
        }
        guard let text = event.characters, !text.isEmpty,
              text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && ($0.value < 0xF700 || $0.value > 0xF8FF) }) else { return false }
        insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    private func _move(to offset: Int, extend: Bool) {
        let sel = selectedRange
        if extend {
            let anchor = _selectionAnchor ?? (sel.length == 0 ? sel.location : sel.location)
            _selectionAnchor = anchor
            selectedRange = NSRange(location: min(anchor, offset), length: abs(offset - anchor))
        } else {
            _selectionAnchor = nil
            selectedRange = NSRange(location: offset, length: 0)
        }
    }

    private var _wordBoundaryLeft: Int {
        let sel = selectedRange
        var i = sel.location
        let units = _units
        func isWord(_ u: UInt16) -> Bool { let c = UnicodeScalar(u).map { Character($0) }; return c.map { $0.isLetter || $0.isNumber } ?? false }
        while i > 0 && !isWord(units[i - 1]) { i -= 1 }
        while i > 0 && isWord(units[i - 1]) { i -= 1 }
        return i
    }

    private var _wordBoundaryRight: Int {
        let sel = selectedRange
        var i = sel.location + sel.length
        let units = _units
        func isWord(_ u: UInt16) -> Bool { let c = UnicodeScalar(u).map { Character($0) }; return c.map { $0.isLetter || $0.isNumber } ?? false }
        while i < units.count && !isWord(units[i]) { i += 1 }
        while i < units.count && isWord(units[i]) { i += 1 }
        return i
    }

    private func _verticalMove(_ delta: Int, extend: Bool) {
        let sel = selectedRange
        let head = extend ? (sel.location + sel.length == (_selectionAnchor ?? sel.location) ? sel.location : sel.location + sel.length) : sel.location
        let caret = _caretRect(for: head)
        let target = NSPoint(x: caret.minX, y: caret.minY + CGFloat(delta) * _lineHeight + _lineHeight / 2)
        let lines = _layoutLines()
        if delta < 0 && _line(containing: head) == 0 { _move(to: 0, extend: extend); return }
        if delta > 0 && _line(containing: head) == lines.count - 1 { _move(to: _length, extend: extend); return }
        _move(to: _offset(at: target), extend: extend)
    }

    // MARK: Standard key-binding actions

    @MainActor open func moveLeft(_ sender: Any?) {
        let sel = selectedRange
        _move(to: sel.length > 0 ? sel.location : max(0, sel.location - 1), extend: false)
    }
    @MainActor open func moveRight(_ sender: Any?) {
        let sel = selectedRange
        _move(to: sel.length > 0 ? sel.location + sel.length : min(_length, sel.location + 1), extend: false)
    }
    @MainActor open func moveLeftAndModifySelection(_ sender: Any?) {
        let sel = selectedRange
        let anchor = _selectionAnchor ?? sel.location + sel.length
        let head = anchor == sel.location ? sel.location + sel.length : sel.location
        _selectionAnchor = anchor
        _move(to: max(0, head - 1), extend: true)
    }
    @MainActor open func moveRightAndModifySelection(_ sender: Any?) {
        let sel = selectedRange
        let anchor = _selectionAnchor ?? sel.location
        let head = anchor == sel.location ? sel.location + sel.length : sel.location
        _selectionAnchor = anchor
        _move(to: min(_length, head + 1), extend: true)
    }
    @MainActor open func moveWordLeft(_ sender: Any?) { _move(to: _wordBoundaryLeft, extend: false) }
    @MainActor open func moveWordRight(_ sender: Any?) { _move(to: _wordBoundaryRight, extend: false) }
    @MainActor open func moveWordLeftAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location + selectedRange.length; _move(to: _wordBoundaryLeft, extend: true) }
    @MainActor open func moveWordRightAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location; _move(to: _wordBoundaryRight, extend: true) }
    @MainActor open func moveUp(_ sender: Any?) { _verticalMove(-1, extend: false) }
    @MainActor open func moveDown(_ sender: Any?) { _verticalMove(1, extend: false) }
    @MainActor open func moveUpAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location + selectedRange.length; _verticalMove(-1, extend: true) }
    @MainActor open func moveDownAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location; _verticalMove(1, extend: true) }
    @MainActor open func moveToBeginningOfLine(_ sender: Any?) { _move(to: _lineRange(at: selectedRange.location).location, extend: false) }
    @MainActor open func moveToEndOfLine(_ sender: Any?) { let r = _lineRange(at: selectedRange.location + selectedRange.length); _move(to: r.location + r.length, extend: false) }
    @MainActor open func moveToBeginningOfLineAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location + selectedRange.length; _move(to: _lineRange(at: selectedRange.location).location, extend: true) }
    @MainActor open func moveToEndOfLineAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location; let r = _lineRange(at: selectedRange.location + selectedRange.length); _move(to: r.location + r.length, extend: true) }
    @MainActor open func moveToBeginningOfDocument(_ sender: Any?) { _move(to: 0, extend: false) }
    @MainActor open func moveToEndOfDocument(_ sender: Any?) { _move(to: _length, extend: false) }
    @MainActor open func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location + selectedRange.length; _move(to: 0, extend: true) }
    @MainActor open func moveToEndOfDocumentAndModifySelection(_ sender: Any?) { _selectionAnchor = _selectionAnchor ?? selectedRange.location; _move(to: _length, extend: true) }
    @MainActor open func pageUp(_ sender: Any?) { _verticalMove(-max(1, Int(bounds.height / _lineHeight)), extend: false) }
    @MainActor open func pageDown(_ sender: Any?) { _verticalMove(max(1, Int(bounds.height / _lineHeight)), extend: false) }
    @MainActor open func deleteBackward(_ sender: Any?) {
        guard isEditable else { return }
        let sel = selectedRange
        if sel.length > 0 { _editReplace(sel, "") } else if sel.location > 0 { _editReplace(NSRange(location: sel.location - 1, length: 1), "") }
    }
    @MainActor open func deleteForward(_ sender: Any?) {
        guard isEditable else { return }
        let sel = selectedRange
        if sel.length > 0 { _editReplace(sel, "") } else if sel.location < _length { _editReplace(NSRange(location: sel.location, length: 1), "") }
    }
    @MainActor open func deleteWordBackward(_ sender: Any?) {
        guard isEditable else { return }
        let sel = selectedRange
        if sel.length > 0 { _editReplace(sel, ""); return }
        let b = _wordBoundaryLeft
        _editReplace(NSRange(location: b, length: sel.location - b), "")
    }
    @MainActor open func deleteWordForward(_ sender: Any?) {
        guard isEditable else { return }
        let sel = selectedRange
        if sel.length > 0 { _editReplace(sel, ""); return }
        let b = _wordBoundaryRight
        _editReplace(NSRange(location: sel.location, length: b - sel.location), "")
    }
    @MainActor open func insertNewline(_ sender: Any?) {
        if isFieldEditor { _endEditing(movement: .return); return }
        insertText("\n")
    }
    @MainActor open func insertTab(_ sender: Any?) {
        if isFieldEditor { _endEditing(movement: .tab); return }
        insertText("\t")
    }
    @MainActor open func insertBacktab(_ sender: Any?) {
        if isFieldEditor { _endEditing(movement: .backtab); return }
    }
    @MainActor open func cancelOperation(_ sender: Any?) {
        if isFieldEditor { _endEditing(movement: .cancel); return }
        _selectionAnchor = nil
        selectedRange = NSRange(location: selectedRange.location + selectedRange.length, length: 0)
    }
    @MainActor open func selectWord(_ sender: Any?) { selectedRange = _wordRange(at: selectedRange.location) }
    @MainActor open func selectLine(_ sender: Any?) { selectedRange = _lineRange(at: selectedRange.location) }
    @MainActor open func selectParagraph(_ sender: Any?) { selectLine(sender) }

    /// Replaces text after asking `shouldChangeText`, then reports the change.
    private func _editReplace(_ range: NSRange, _ text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        _replace(range, with: text, notify: false)
        didChangeText()
    }

    private static let _selectorDispatch: [String: (NSTextView, Any?) -> Void] = [
        "moveLeft:": { $0.moveLeft($1) }, "moveRight:": { $0.moveRight($1) }, "moveUp:": { $0.moveUp($1) }, "moveDown:": { $0.moveDown($1) },
        "moveLeftAndModifySelection:": { $0.moveLeftAndModifySelection($1) }, "moveRightAndModifySelection:": { $0.moveRightAndModifySelection($1) },
        "moveUpAndModifySelection:": { $0.moveUpAndModifySelection($1) }, "moveDownAndModifySelection:": { $0.moveDownAndModifySelection($1) },
        "moveWordLeft:": { $0.moveWordLeft($1) }, "moveWordRight:": { $0.moveWordRight($1) },
        "moveWordLeftAndModifySelection:": { $0.moveWordLeftAndModifySelection($1) }, "moveWordRightAndModifySelection:": { $0.moveWordRightAndModifySelection($1) },
        "moveToBeginningOfLine:": { $0.moveToBeginningOfLine($1) }, "moveToEndOfLine:": { $0.moveToEndOfLine($1) },
        "moveToBeginningOfLineAndModifySelection:": { $0.moveToBeginningOfLineAndModifySelection($1) }, "moveToEndOfLineAndModifySelection:": { $0.moveToEndOfLineAndModifySelection($1) },
        "moveToBeginningOfDocument:": { $0.moveToBeginningOfDocument($1) }, "moveToEndOfDocument:": { $0.moveToEndOfDocument($1) },
        "moveToBeginningOfDocumentAndModifySelection:": { $0.moveToBeginningOfDocumentAndModifySelection($1) }, "moveToEndOfDocumentAndModifySelection:": { $0.moveToEndOfDocumentAndModifySelection($1) },
        "pageUp:": { $0.pageUp($1) }, "pageDown:": { $0.pageDown($1) },
        "deleteBackward:": { $0.deleteBackward($1) }, "deleteForward:": { $0.deleteForward($1) },
        "deleteWordBackward:": { $0.deleteWordBackward($1) }, "deleteWordForward:": { $0.deleteWordForward($1) },
        "insertNewline:": { $0.insertNewline($1) }, "insertTab:": { $0.insertTab($1) }, "insertBacktab:": { $0.insertBacktab($1) },
        "cancelOperation:": { $0.cancelOperation($1) }, "selectAll:": { $0.selectAll($1) }, "selectWord:": { $0.selectWord($1) },
        "selectLine:": { $0.selectLine($1) }, "selectParagraph:": { $0.selectParagraph($1) },
        "copy:": { $0.copy($1) }, "cut:": { $0.cut($1) }, "paste:": { $0.paste($1) }, "delete:": { $0.delete($1) },
    ]

    // MARK: Responder-chain actions (menus, nil-target sends)

    /// The editing selectors double as responder-chain actions, so Edit menu items with a
    /// nil target reach the text view.
    public func respondsToSelectorAction(_ action: Selector) -> Bool {
        NSTextView._selectorDispatch[NSStringFromSelector(action)] != nil
    }

    public func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard let handler = NSTextView._selectorDispatch[NSStringFromSelector(action)] else { return false }
        handler(self, sender)
        return true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/validatemenuitem(_:)
    open func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        let hasSelection = selectedRange.length > 0
        switch NSStringFromSelector(action) {
        case "copy:": return isSelectable && hasSelection
        case "cut:", "delete:": return isEditable && hasSelection
        case "paste:": return isEditable && NSPasteboard.general.string(forType: .string) != nil
        case "selectAll:": return isSelectable && !string.isEmpty
        default: return true
        }
    }

    // MARK: NSTextInputClient

    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        var range = replacementRange.location == NSNotFound ? (_markedRange ?? selectedRange) : replacementRange
        if _markedRange != nil && replacementRange.location == NSNotFound { range = _markedRange! }
        _markedRange = nil
        _editReplace(range, text)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard isEditable else { return }
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        let range = replacementRange.location == NSNotFound ? (_markedRange ?? self.selectedRange) : replacementRange
        _replace(range, with: text, notify: false)
        if text.isEmpty {
            _markedRange = nil
        } else {
            _markedRange = NSRange(location: range.location, length: text.utf16.count)
            let selLoc = range.location + min(selectedRange.location, text.utf16.count)
            self.selectedRange = NSRange(location: selLoc, length: min(selectedRange.length, text.utf16.count - min(selectedRange.location, text.utf16.count)))
        }
        _markedSelection = selectedRange
        needsDisplay = true
    }

    public func unmarkText() {
        guard let m = _markedRange else { return }
        _markedRange = nil
        selectedRange = NSRange(location: m.location + m.length, length: 0)
        didChangeText()
    }

    public func selectedRange() -> NSRange { selectedRange }
    public func markedRange() -> NSRange { _markedRange ?? NSRange(location: NSNotFound, length: 0) }
    public func hasMarkedText() -> Bool { _markedRange != nil }
    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let r = _clamped(range)
        actualRange?.pointee = r
        return NSAttributedString(string: _substring(r), attributes: _attributes)
    }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle] }
    public func attributedString() -> NSAttributedString { NSAttributedString(string: string, attributes: _attributes) }
    public func windowLevel() -> Int { window?.level.rawValue ?? 0 }

    /// Screen rectangle of the first line of `range` (input methods place candidate windows there).
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let r = _clamped(range)
        actualRange?.pointee = r
        let start = _caretRect(for: r.location)
        let end = _caretRect(for: min(r.location + r.length, _lineRange(at: r.location).location + _lineRange(at: r.location).length))
        let local = NSRect(x: start.minX, y: start.minY, width: max(1, end.minX - start.minX), height: start.height)
        guard let w = window else { return local }
        return w.convertToScreen(convert(local, to: nil))
    }

    public func characterIndex(for point: NSPoint) -> Int {
        guard let w = window else { return 0 }
        let local = convert(w.convertFromScreen(NSRect(origin: point, size: .zero)).origin, from: nil)
        return _offset(at: local)
    }

    /// The caret or marked-text rectangle in window content coordinates, for input methods.
    internal var _inputMethodRect: NSRect {
        let r = _markedRange ?? NSRange(location: selectedRange.location, length: 0)
        let caret = _caretRect(for: r.location)
        return convert(caret, to: nil)
    }

    internal override func _selectionDidChange() {
        let n = Notification(name: NSTextView.didChangeSelectionNotification, object: self)
        NotificationCenter.default.post(n)
        _viewDelegate?.textViewDidChangeSelection(n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/init(coder:)
    public required init?(coder: NSCoder) {
        _storage = NSTextStorage()
        _layoutManager = NSLayoutManager()
        _container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        super.init(coder: coder)
        MainActor.assumeIsolated { _wireTextSystem() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/init(frame:)
    @MainActor public override convenience init(frame frameRect: NSRect) { self.init(frame: frameRect, textContainer: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/init(frame:textcontainer:)
    @MainActor public init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        // A container that already belongs to a layout manager brings its text system along.
        if let c = container, let lm = c.layoutManager {
            _container = c
            _layoutManager = lm
            _storage = lm.textStorage ?? NSTextStorage()
        } else {
            _container = container ?? NSTextContainer(size: NSSize(width: max(1, frameRect.width), height: CGFloat.greatestFiniteMagnitude))
            _layoutManager = NSLayoutManager()
            _storage = NSTextStorage()
        }
        super.init(frame: frameRect)
        _wireTextSystem()
    }

    private func _wireTextSystem() {
        if _layoutManager.textStorage !== _storage { _storage.addLayoutManager(_layoutManager) }
        if !_layoutManager.textContainers.contains(where: { $0 === _container }) { _layoutManager.addTextContainer(_container) }
        _container.textView = self
        _container.widthTracksTextView = true
        _container.heightTracksTextView = false
        if _storage.length == 0 { _storage.setAttributedString(NSAttributedString(string: "", attributes: typingAttributes)) }
        _syncContainerSize()
    }

    /// Container width follows the view unless the text runs on one line (field editors,
    /// horizontally resizable views).
    private func _syncContainerSize() {
        let unbounded = isFieldEditor || isHorizontallyResizable
        let width = unbounded ? CGFloat.greatestFiniteMagnitude : max(1, bounds.width - 2 * _textContainerInset.width)
        let size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if _container.size != size { _container.size = size }
        let padding: CGFloat = isFieldEditor ? 0 : 5
        if _container.lineFragmentPadding != padding { _container.lineFragmentPadding = padding }
    }

    private var _drawOrigin: NSPoint { NSPoint(x: textContainerOrigin.x - _scrollX, y: textContainerOrigin.y) }

    // MARK: NSText model hooks, backed by the text storage

    internal override func _getString() -> String { _storage.string }
    internal override func _setString(_ s: String) {
        _storage.setAttributedString(NSAttributedString(string: s, attributes: typingAttributes))
    }
    internal override func _storageReplace(_ r: NSRange, with text: String) {
        var attrs = typingAttributes
        if r.location > 0, r.location <= _storage.length {
            let before = _storage.attributes(at: r.location - 1, effectiveRange: nil)
            if before[.font] != nil { attrs = before }
        }
        _storage.replaceCharacters(in: r, with: NSAttributedString(string: text, attributes: attrs))
    }

    internal override func _invalidateLayout() {
        _syncContainerSize()
        _layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: _storage.length), actualCharacterRange: nil)
    }

    /// The layout manager laid the text out again (an edit, a geometry change).
    internal func _layoutManagerDidChange() { needsDisplay = true }

    internal override func _layoutLines() -> [_Line] {
        let origin = _drawOrigin
        var lines = _layoutManager._lineFragments.map { f in
            _Line(range: NSRange(location: f.charRange.location, length: f.charRange.length - f.newlineLength),
                  y: f.rect.minY + origin.y, width: f.usedRect.width, endsWithNewline: f.newlineLength > 0)
        }
        if _layoutManager.extraLineFragmentTextContainer != nil || lines.isEmpty {
            let extra = _layoutManager.extraLineFragmentRect
            lines.append(_Line(range: NSRange(location: _storage.length, length: 0), y: (lines.isEmpty ? 0 : extra.minY) + origin.y, width: 0, endsWithNewline: false))
        }
        return lines
    }

    internal override func _caretRect(for offset: Int) -> NSRect {
        let origin = _drawOrigin
        guard let c = _layoutManager._caret(forCharacter: offset) else {
            return NSRect(x: origin.x + _container.lineFragmentPadding, y: origin.y, width: 1, height: _lineHeight)
        }
        return NSRect(x: c.rect.minX + origin.x, y: c.rect.minY + origin.y, width: 1, height: c.rect.height)
    }

    internal override func _offset(at point: NSPoint) -> Int {
        let origin = _drawOrigin
        var fraction: CGFloat = 0
        let p = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let i = _layoutManager.characterIndex(for: p, in: _container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard fraction > 0.5 else { return i }
        let line = _lineRange(at: i)
        return min(i + 1, line.location + line.length)
    }

    internal override var _contentSize: NSSize {
        let used = _layoutManager.usedRect(for: _container)
        let padding = isFieldEditor ? 0 : _container.lineFragmentPadding
        return NSSize(width: (used.width + 2 * padding + 2 * _textContainerInset.width).rounded(.up),
                      height: max(used.height, _lineHeight) + 2 * _textContainerInset.height)
    }

    /// The colour the layout manager highlights this view's selection with.
    internal var _selectionHighlightColor: NSColor {
        let focused = window?.firstResponder === self && (window?.isKeyWindow ?? true)
        return focused ? (_selectedTextAttributes[.backgroundColor] as? NSColor) ?? .selectedTextBackgroundColor : .unemphasizedSelectedContentBackgroundColor
    }

    open override func draw(_ dirtyRect: NSRect) {
        if drawsBackground, let bg = backgroundColor {
            bg.setFill()
            NSBezierPath.fill(bounds)
        }
        let origin = _drawOrigin
        let all = NSRange(location: 0, length: _storage.length)
        _layoutManager.drawBackground(forGlyphRange: all, at: origin)
        _layoutManager.drawGlyphs(forGlyphRange: all, at: origin)
        if let m = _markedRange, m.length > 0 {
            (textColor ?? .textColor).setFill()
            _layoutManager.enumerateEnclosingRects(forGlyphRange: m, withinSelectedGlyphRange: m, in: _container) { r, _ in
                NSBezierPath.fill(NSRect(x: r.minX + origin.x, y: r.maxY + origin.y - 2, width: r.width, height: 1))
            }
        }
        let sel = selectedRange
        if window?.firstResponder === self && isEditable && sel.length == 0 {
            let caret = _caretRect(for: sel.location)
            insertionPointColor.setFill()
            NSBezierPath.fill(NSRect(x: caret.minX.rounded(), y: caret.minY, width: 1, height: caret.height))
        }
    }

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _syncContainerSize()
    }

    /// Colours were resolved at layout time, so a theme change lays the text out again.
    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        _invalidateLayout()
        needsDisplay = true
    }

    open override var isFieldEditor: Bool {
        get { super.isFieldEditor }
        set { super.isFieldEditor = newValue; _syncContainerSize() }
    }
    open override var isHorizontallyResizable: Bool {
        get { super.isHorizontallyResizable }
        set { super.isHorizontallyResizable = newValue; _syncContainerSize() }
    }
    open override var font: NSFont? {
        get { super.font }
        set {
            super.font = newValue
            let r = NSRange(location: 0, length: _storage.length)
            if let f = newValue { _storage.addAttribute(.font, value: f, range: r) } else { _storage.removeAttribute(.font, range: r) }
        }
    }
    open override var textColor: NSColor? {
        get { super.textColor }
        set {
            super.textColor = newValue
            let r = NSRange(location: 0, length: _storage.length)
            if let c = newValue { _storage.addAttribute(.foregroundColor, value: c, range: r) } else { _storage.removeAttribute(.foregroundColor, range: r) }
        }
    }
    open override var alignment: NSTextAlignment {
        get { super.alignment }
        set {
            super.alignment = newValue
            let ps = NSMutableParagraphStyle()
            ps.alignment = newValue
            _typingAttributes[.paragraphStyle] = ps
            _storage.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: _storage.length))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/init(usingtextlayoutmanager:)
    @MainActor public convenience init(usingTextLayoutManager: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/acceptabledragtypes
    @MainActor open var acceptableDragTypes: [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/acceptsglyphinfo
    @MainActor open var acceptsGlyphInfo: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/alignjustified(_:)
    @MainActor open func alignJustified(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowedinputsourcelocales
    @MainActor open var allowedInputSourceLocales: [String]? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowedwritingtoolsresultoptions
    @available(macOS 15.0, *)
    @MainActor open var allowedWritingToolsResultOptions: NSWritingToolsResultOptions {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowscharacterpickertouchbaritem
    @available(macOS 10.12, *)
    @MainActor open var allowsCharacterPickerTouchBarItem: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowsdocumentbackgroundcolorchange
    @MainActor open var allowsDocumentBackgroundColorChange: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowsimageediting
    @MainActor open var allowsImageEditing: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowsundo
    @MainActor open var allowsUndo: Bool {
        get { _allowsUndo }
        set { _allowsUndo = newValue }
    }
    // SKIPPED (override type NSColor differs from superclass NSColor?): @MainActor var backgroundColor: NSColor { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/breakundocoalescing()
    @MainActor open func breakUndoCoalescing() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/candidatelisttouchbaritem
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/changeattributes(_:)
    @MainActor open func changeAttributes(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/changecolor(_:)
    @MainActor open func changeColor(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/changedocumentbackgroundcolor(_:)
    @MainActor open func changeDocumentBackgroundColor(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/changelayoutorientation(_:)
    @MainActor open func changeLayoutOrientation(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/characterindexforinsertion(at:)
    @MainActor open func characterIndexForInsertion(at point: NSPoint) -> Int { _offset(at: point) }
    // SKIPPED (Foundation.NSTextCheckingTypes not in corelibs): @MainActor func checkText(in range: NSRange, types checkingTypes: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey : Any] = [:])
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/checktextindocument(_:)
    @MainActor open func checkTextInDocument(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/checktextinselection(_:)
    @MainActor open func checkTextInSelection(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/cleanupafterdragoperation()
    @MainActor open func cleanUpAfterDragOperation() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/clicked(onlink:at:)
    @MainActor open func clicked(onLink link: Any, at charIndex: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/complete(_:)
    @MainActor open func complete(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/completions(forpartialwordrange:indexofselecteditem:)
    @MainActor open func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/defaultparagraphstyle
    @MainActor open var defaultParagraphStyle: NSParagraphStyle? {
        get { unimplemented() }
        set { unimplemented() }
    }
    // SKIPPED (override type (any NSTextViewDelegate)? differs from superclass (any NSTextDelegate)?): @MainActor var delegate: (any NSTextViewDelegate)? { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/didchangeselectionnotification
    static public var didChangeSelectionNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextViewDidChangeSelectionNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/didchangetext()
    @MainActor open func didChangeText() { _noteDidChange() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/didchangetypingattributesnotification
    static public var didChangeTypingAttributesNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextViewDidChangeTypingAttributesNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/didswitchtonslayoutmanagernotification
    @available(macOS 12.0, *)
    static public var didSwitchToNSLayoutManagerNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextViewDidSwitchToNSLayoutManagerNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/displayslinktooltips
    @MainActor open var displaysLinkToolTips: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/dragimageforselection(with:origin:)
    @MainActor open func dragImageForSelection(with event: NSEvent, origin: NSPointPointer?) -> NSImage? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/dragoperation(for:type:)
    @MainActor open func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/dragselection(with:offset:slideback:)
    @MainActor open func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/drawbackground(in:)
    @MainActor open func drawBackground(in rect: NSRect) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/drawinsertionpoint(in:color:turnedon:)
    @MainActor open func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/drawtexthighlightbackground(for:origin:)
    @available(macOS 15.0, *)
    @MainActor open func drawTextHighlightBackground(for textRange: NSTextRange, origin: NSPoint) { unimplemented() }
    // SKIPPED (Foundation.NSTextCheckingTypes not in corelibs): @MainActor var enabledTextCheckingTypes: NSTextCheckingTypes { get set }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/fieldeditor()
    @available(macOS 10.14, *)
    @MainActor public class func fieldEditor() -> Self { unimplemented() }
    // SKIPPED (Foundation.NSTextCheckingTypes not in corelibs): @MainActor func handleTextCheckingResults(_ results: [NSTextCheckingResult], forRange range: NSRange, types checkingTypes: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey : Any] = [:], orthography: NSOrthography, wordCount: Int)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/highlight(_:)
    @available(macOS 15.0, *)
    @MainActor open func highlight(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/inlinepredictiontype
    @available(macOS 14.0, *)
    @MainActor open var inlinePredictionType: NSTextInputTraitType {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/insertcompletion(_:forpartialwordrange:movement:isfinal:)
    @MainActor open func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/inserttext(_:)
    @MainActor open func insertText(_ insertString: Any) { insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/insertionpointcolor
    @MainActor open var insertionPointColor: NSColor! {
        get { _insertionPointColor ?? textColor ?? .textColor }
        set { _insertionPointColor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/invalidatetextcontainerorigin()
    @MainActor open func invalidateTextContainerOrigin() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticdashsubstitutionenabled
    @MainActor open var isAutomaticDashSubstitutionEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticdatadetectionenabled
    @MainActor open var isAutomaticDataDetectionEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticlinkdetectionenabled
    @MainActor open var isAutomaticLinkDetectionEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticquotesubstitutionenabled
    @MainActor open var isAutomaticQuoteSubstitutionEnabled: Bool {
        get { _isAutomaticQuoteSubstitutionEnabled }
        set { _isAutomaticQuoteSubstitutionEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticspellingcorrectionenabled
    @MainActor open var isAutomaticSpellingCorrectionEnabled: Bool {
        get { _isAutomaticSpellingCorrectionEnabled }
        set { _isAutomaticSpellingCorrectionEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomatictextcompletionenabled
    @available(macOS 10.12, *)
    @MainActor open var isAutomaticTextCompletionEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomatictextreplacementenabled
    @MainActor open var isAutomaticTextReplacementEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/iscoalescingundo
    @MainActor open var isCoalescingUndo: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/iscontinuousspellcheckingenabled
    @MainActor open var isContinuousSpellCheckingEnabled: Bool {
        get { _isContinuousSpellCheckingEnabled }
        set { _isContinuousSpellCheckingEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isgrammarcheckingenabled
    @MainActor open var isGrammarCheckingEnabled: Bool {
        get { _isGrammarCheckingEnabled }
        set { _isGrammarCheckingEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isincrementalsearchingenabled
    @MainActor open var isIncrementalSearchingEnabled: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/iswritingtoolsactive
    @available(macOS 15.0, *)
    @MainActor open var isWritingToolsActive: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/layoutmanager
    @MainActor open var layoutManager: NSLayoutManager? { _layoutManager }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/linktextattributes
    @MainActor open var linkTextAttributes: [NSAttributedString.Key : Any]? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/loosenkerning(_:)
    @MainActor open func loosenKerning(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/lowerbaseline(_:)
    @MainActor open func lowerBaseline(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/markedtextattributes
    @MainActor open var markedTextAttributes: [NSAttributedString.Key : Any]? {
        get { _markedTextAttributes }
        set { _markedTextAttributes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/mathexpressioncompletiontype
    @available(macOS 15.0, *)
    @MainActor open var mathExpressionCompletionType: NSTextInputTraitType {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontlinkpanel(_:)
    @MainActor open func orderFrontLinkPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontlistpanel(_:)
    @MainActor open func orderFrontListPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontsharingservicepicker(_:)
    @MainActor open func orderFrontSharingServicePicker(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontspacingpanel(_:)
    @MainActor open func orderFrontSpacingPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontsubstitutionspanel(_:)
    @MainActor open func orderFrontSubstitutionsPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfronttablepanel(_:)
    @MainActor open func orderFrontTablePanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/outline(_:)
    @MainActor open func outline(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/pasteasplaintext(_:)
    @MainActor open func pasteAsPlainText(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/pasteasrichtext(_:)
    @MainActor open func pasteAsRichText(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/performfindpanelaction(_:)
    @MainActor open func performFindPanelAction(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/performvalidatedreplacement(in:with:)
    @available(macOS 10.14, *)
    @MainActor open func performValidatedReplacement(in range: NSRange, with attributedString: NSAttributedString) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/preferredpasteboardtype(from:restrictedtotypesfrom:)
    @MainActor open func preferredPasteboardType(from availableTypes: [NSPasteboard.PasteboardType], restrictedToTypesFrom allowedTypes: [NSPasteboard.PasteboardType]?) -> NSPasteboard.PasteboardType? { unimplemented() }
    // SKIPPED (unknown module (QuickLook QLPreviewItem)): @MainActor func quickLookPreviewableItems(inRanges ranges: [NSValue]) -> [any QLPreviewItem]
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/raisebaseline(_:)
    @MainActor open func raiseBaseline(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforusercharacterattributechange
    @MainActor open var rangeForUserCharacterAttributeChange: NSRange { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforusercompletion
    @MainActor open var rangeForUserCompletion: NSRange { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforuserparagraphattributechange
    @MainActor open var rangeForUserParagraphAttributeChange: NSRange { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforusertextchange
    @MainActor open var rangeForUserTextChange: NSRange { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangesforusercharacterattributechange
    @MainActor open var rangesForUserCharacterAttributeChange: [NSValue]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangesforuserparagraphattributechange
    @MainActor open var rangesForUserParagraphAttributeChange: [NSValue]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangesforusertextchange
    @MainActor open var rangesForUserTextChange: [NSValue]? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/readselection(from:)
    @MainActor open func readSelection(from pboard: NSPasteboard) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/readselection(from:type:)
    @MainActor open func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/readablepasteboardtypes
    @MainActor open var readablePasteboardTypes: [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/registerforservices()
    @MainActor public class func registerForServices() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/replacetextcontainer(_:)
    @MainActor open func replaceTextContainer(_ newContainer: NSTextContainer) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/scrollabledocumentcontenttextview()
    @available(macOS 10.14, *)
    @MainActor public class func scrollableDocumentContentTextView() -> NSScrollView { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/scrollableplaindocumentcontenttextview()
    @available(macOS 10.14, *)
    @MainActor public class func scrollablePlainDocumentContentTextView() -> NSScrollView { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/scrollabletextview()
    @available(macOS 10.14, *)
    @MainActor public class func scrollableTextView() -> NSScrollView { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/selectedranges
    @MainActor open var selectedRanges: [NSValue] {
        get { [NSValue(range: selectedRange)] }
        set { if let first = newValue.first { selectedRange = first.rangeValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/selectedtextattributes
    @MainActor open var selectedTextAttributes: [NSAttributedString.Key : Any] {
        get { _selectedTextAttributes }
        set { _selectedTextAttributes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/selectionaffinity
    @MainActor open var selectionAffinity: NSSelectionAffinity { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/selectiongranularity
    @MainActor open var selectionGranularity: NSSelectionGranularity {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/selectionrange(forproposedrange:granularity:)
    @MainActor open func selectionRange(forProposedRange proposedCharRange: NSRange, granularity: NSSelectionGranularity) -> NSRange { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setalignment(_:range:)
    @MainActor open func setAlignment(_ alignment: NSTextAlignment, range: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setbasewritingdirection(_:range:)
    @MainActor open func setBaseWritingDirection(_ writingDirection: NSWritingDirection, range: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setconstrainedframesize(_:)
    @MainActor open func setConstrainedFrameSize(_ desiredSize: NSSize) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setlayoutorientation(_:)
    @MainActor open func setLayoutOrientation(_ orientation: NSLayoutManager.TextLayoutOrientation) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setneedsdisplay(_:avoidadditionallayout:)
    @MainActor open func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setselectedrange(_:)
    @MainActor open func setSelectedRange(_ charRange: NSRange) { _selectionAnchor = nil; selectedRange = charRange }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setselectedrange(_:affinity:stillselecting:)
    @MainActor open func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) { selectedRange = charRange }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setselectedranges(_:affinity:stillselecting:)
    @MainActor open func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setspellingstate(_:range:)
    @MainActor open func setSpellingState(_ value: Int, range charRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/shouldchangetext(in:replacementstring:)
    @MainActor open func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard isEditable else { return false }
        return _viewDelegate?.textView(self, shouldChangeTextIn: affectedCharRange, replacementString: replacementString) ?? true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/shouldchangetext(inranges:replacementstrings:)
    @MainActor open func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        for (i, r) in affectedRanges.enumerated() where !shouldChangeText(in: r.rangeValue, replacementString: replacementStrings?[i]) { return false }
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/shoulddrawinsertionpoint
    @MainActor open var shouldDrawInsertionPoint: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/showfindindicator(for:)
    @MainActor open func showFindIndicator(for charRange: NSRange) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartdeleterange(forproposedrange:)
    @MainActor open func smartDeleteRange(forProposedRange proposedCharRange: NSRange) -> NSRange { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsert(afterstringfor:replacing:)
    @MainActor open func smartInsert(afterStringFor pasteString: String, replacing charRangeToReplace: NSRange) -> String? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsert(beforestringfor:replacing:)
    @MainActor open func smartInsert(beforeStringFor pasteString: String, replacing charRangeToReplace: NSRange) -> String? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsert(for:replacing:before:after:)
    @MainActor open func smartInsert(for pasteString: String, replacing charRangeToReplace: NSRange, before beforeString: AutoreleasingUnsafeMutablePointer<NSString?>?, after afterString: AutoreleasingUnsafeMutablePointer<NSString?>?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsertdeleteenabled
    @MainActor open var smartInsertDeleteEnabled: Bool {
        get { _smartInsertDeleteEnabled }
        set { _smartInsertDeleteEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/spellcheckerdocumenttag
    @MainActor open var spellCheckerDocumentTag: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/startspeaking(_:)
    @MainActor open func startSpeaking(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/stopspeaking(_:)
    @MainActor open func stopSpeaking(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/stronglyreferencestextstorage
    @available(macOS 10.12, *)
    @MainActor class public var stronglyReferencesTextStorage: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textcontainer
    @MainActor open var textContainer: NSTextContainer? {
        get { _container }
        set {
            guard let c = newValue, c !== _container else { return }
            if let i = _layoutManager.textContainers.firstIndex(where: { $0 === _container }) { _layoutManager.removeTextContainer(at: i) }
            _container.textView = nil
            _container = c
            if let lm = c.layoutManager, lm !== _layoutManager {
                _layoutManager = lm
                if let s = lm.textStorage { _storage = s }
            }
            _wireTextSystem()
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textcontainerinset
    @MainActor open var textContainerInset: NSSize {
        get { _textContainerInset }
        set { _textContainerInset = newValue; _syncContainerSize(); _invalidateLayout(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textcontainerorigin
    @MainActor open var textContainerOrigin: NSPoint { NSPoint(x: _textContainerInset.width, y: _textContainerInset.height) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textcontentstorage
    @available(macOS 12.0, *)
    @MainActor open var textContentStorage: NSTextContentStorage? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/texthighlightattributes
    @available(macOS 15.0, *)
    @MainActor open var textHighlightAttributes: [NSAttributedString.Key : Any] {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textlayoutmanager
    @available(macOS 12.0, *)
    @MainActor open var textLayoutManager: NSTextLayoutManager? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textstorage
    @MainActor open var textStorage: NSTextStorage? { _storage }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/tightenkerning(_:)
    @MainActor open func tightenKerning(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticdashsubstitution(_:)
    @MainActor open func toggleAutomaticDashSubstitution(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticdatadetection(_:)
    @MainActor open func toggleAutomaticDataDetection(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticlinkdetection(_:)
    @MainActor open func toggleAutomaticLinkDetection(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticquotesubstitution(_:)
    @MainActor open func toggleAutomaticQuoteSubstitution(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticspellingcorrection(_:)
    @MainActor open func toggleAutomaticSpellingCorrection(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomatictextcompletion(_:)
    @available(macOS 10.12, *)
    @MainActor open func toggleAutomaticTextCompletion(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomatictextreplacement(_:)
    @MainActor open func toggleAutomaticTextReplacement(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglecontinuousspellchecking(_:)
    @MainActor open func toggleContinuousSpellChecking(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglegrammarchecking(_:)
    @MainActor open func toggleGrammarChecking(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglequicklookpreviewpanel(_:)
    @MainActor open func toggleQuickLookPreviewPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglesmartinsertdelete(_:)
    @MainActor open func toggleSmartInsertDelete(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggletraditionalcharactershape(_:)
    @MainActor open func toggleTraditionalCharacterShape(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/turnoffkerning(_:)
    @MainActor open func turnOffKerning(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/turnoffligatures(_:)
    @MainActor open func turnOffLigatures(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/typingattributes
    @MainActor open var typingAttributes: [NSAttributedString.Key : Any] {
        get { _typingAttributes.isEmpty ? _attributes : _typingAttributes }
        set { _typingAttributes = newValue; if let f = newValue[.font] as? NSFont { font = f }; if let c = newValue[.foregroundColor] as? NSColor { textColor = c } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatecandidates()
    @available(macOS 10.12, *)
    @MainActor open func updateCandidates() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatedragtyperegistration()
    @MainActor open func updateDragTypeRegistration() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatefontpanel()
    @MainActor open func updateFontPanel() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updateinsertionpointstateandrestarttimer(_:)
    @MainActor open func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatequicklookpreviewpanel()
    @MainActor open func updateQuickLookPreviewPanel() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updateruler()
    @MainActor open func updateRuler() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatetexttouchbaritems()
    @available(macOS 10.12, *)
    @MainActor open func updateTextTouchBarItems() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatetouchbaritemidentifiers()
    @available(macOS 10.12, *)
    @MainActor open func updateTouchBarItemIdentifiers() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/useallligatures(_:)
    @MainActor open func useAllLigatures(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usestandardkerning(_:)
    @MainActor open func useStandardKerning(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usestandardligatures(_:)
    @MainActor open func useStandardLigatures(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesadaptivecolormappingfordarkappearance
    @available(macOS 10.14, *)
    @MainActor open var usesAdaptiveColorMappingForDarkAppearance: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesfindbar
    @MainActor open var usesFindBar: Bool {
        get { _usesFindBar }
        set { _usesFindBar = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesfindpanel
    @MainActor open var usesFindPanel: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesinspectorbar
    @MainActor open var usesInspectorBar: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesrolloverbuttonforselection
    @available(macOS 10.10, *)
    @MainActor open var usesRolloverButtonForSelection: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesruler
    @MainActor open var usesRuler: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/willchangenotifyingtextviewnotification
    static public var willChangeNotifyingTextViewNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextViewWillChangeNotifyingTextViewNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/willswitchtonslayoutmanagernotification
    @available(macOS 12.0, *)
    static public var willSwitchToNSLayoutManagerNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextViewWillSwitchToNSLayoutManagerNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writablepasteboardtypes
    @MainActor open var writablePasteboardTypes: [NSPasteboard.PasteboardType] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writeselection(to:type:)
    @MainActor open func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writeselection(to:types:)
    @MainActor open func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writingtoolsbehavior
    @available(macOS 15.0, *)
    @MainActor open var writingToolsBehavior: NSWritingToolsBehavior {
        get { unimplemented() }
        set { unimplemented() }
    }
    // Requirement of NSColorChanging (signature differs from the inherited member)
    // Requirement of NSColorChanging
    open func changeColor(_ sender: NSColorPanel?) { unimplemented() }
    // Requirement of NSTextInputClient
    open func doCommand(by selector: Selector) {
        MainActor.assumeIsolated {
            if let d = _viewDelegate, d.textView(self, doCommandBy: selector) { return }
            if let action = NSTextView._selectorDispatch[NSStringFromSelector(selector)] { action(self, nil) }
        }
    }
    // Requirement of NSTextLayoutOrientationProvider
    open var layoutOrientation: NSLayoutManager.TextLayoutOrientation { unimplemented() }
    // MARK: Accessibility (ADR-0013)
    //
    // A text view is AXTextArea with its string as value and its selection; a field
    // editor is not an element of its own (the text field it edits stands for it).
    open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? !isFieldEditor }
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .textArea }
    open override func isAccessibilityEnabled() -> Bool { _a11y.isEnabled ?? (isEditable || isSelectable) }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : string }
    override func _accessibilityValueIsSettable() -> Bool { isEditable }
    override func _accessibilityIsMultiline() -> Bool { !isFieldEditor }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard isEditable else { return false }
        string = value.stringValue
        didChangeText()
        return true
    }
    open override func accessibilitySelectedTextRange() -> NSRange { selectedRange }
    open func setAccessibilitySelectedTextRange(_ accessibilitySelectedTextRange: NSRange) { setSelectedRange(accessibilitySelectedTextRange) }
    open func accessibilitySelectedText() -> String? { (string as NSString)._accessibilitySubstring(selectedRange) }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityString(for range: NSRange) -> String? { (string as NSString)._accessibilitySubstring(range) }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityLine(for index: Int) -> Int {
        let s = string as NSString
        guard index <= s.length else { return -1 }
        var line = 0
        var i = 0
        while i < min(index, s.length) { if s.character(at: i) == 0x0A { line += 1 }; i += 1 }
        return line
    }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityRange(forLine lineNumber: Int) -> NSRange {
        let s = string as NSString
        var line = 0
        var start = 0
        var i = 0
        while i < s.length {
            if s.character(at: i) == 0x0A {
                if line == lineNumber { return NSRange(location: start, length: i + 1 - start) }
                line += 1
                start = i + 1
            }
            i += 1
        }
        return line == lineNumber ? NSRange(location: start, length: s.length - start) : NSRange(location: NSNotFound, length: 0)
    }
    // Requirement of NSAccessibilityNavigableStaticText
    open func accessibilityFrame(for range: NSRange) -> NSRect { accessibilityFrame() }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityValue() -> String? { string }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        guard let storage = textStorage, range.location != NSNotFound, NSMaxRange(range) <= storage.length else { return nil }
        return storage.attributedSubstring(from: range)
    }
    // Requirement of NSAccessibilityStaticText
    open func accessibilityVisibleCharacterRange() -> NSRange { NSRange(location: 0, length: (string as NSString).length) }
    open func accessibilityNumberOfCharacters() -> Int { (string as NSString).length }
    open func accessibilityInsertionPointLineNumber() -> Int { accessibilityLine(for: selectedRange.location) }
    // Requirement of NSTextContent
    open var contentType: NSTextContentType? {
        get { unimplemented() }
        set { unimplemented() }
    }
}
