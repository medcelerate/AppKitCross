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
    /// Find, spelling, substitution and the other editor settings (NSTextView+TextExtras).
    internal lazy var _extras = _NSTextViewExtras()

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
        case "\u{1B}": selector = option ? "complete:" : "cancelOperation:"
        case "\u{F708}": selector = "complete:"
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
    /// In a list item Return starts the next item (or ends the list on an empty one).
    @MainActor open func insertNewline(_ sender: Any?) {
        if isFieldEditor { _endEditing(movement: .return); return }
        guard isEditable else { return }
        if _listNewline() { return }
        insertText("\n")
    }
    /// Tab at the start of a list item's text nests it; in a table it moves to the next cell.
    @MainActor open func insertTab(_ sender: Any?) {
        if isFieldEditor { _endEditing(movement: .tab); return }
        guard isEditable else { return }
        if _changeListLevel(by: 1, onlyAtItemStart: true) { return }
        if _moveToAdjacentCell(forward: true) { return }
        insertText("\t")
    }
    /// Shift-Tab brings a list item out one level; in a table it moves to the previous cell.
    @MainActor open func insertBacktab(_ sender: Any?) {
        if isFieldEditor { _endEditing(movement: .backtab); return }
        guard isEditable else { return }
        if _changeListLevel(by: -1, onlyAtItemStart: false) { return }
        _ = _moveToAdjacentCell(forward: false)
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
        "pasteAsPlainText:": { $0.pasteAsPlainText($1) }, "pasteAsRichText:": { $0.pasteAsRichText($1) },
        "performFindPanelAction:": { $0.performFindPanelAction($1) }, "performTextFinderAction:": { $0.performTextFinderAction($1) },
        "checkSpelling:": { $0.checkSpelling($1) }, "showGuessPanel:": { $0.showGuessPanel($1) },
        "changeSpelling:": { $0.changeSpelling($1) }, "ignoreSpelling:": { $0.ignoreSpelling($1) },
        "_learnSpellingFromMenu:": { tv, sender in
            guard let word = (sender as? NSMenuItem)?.representedObject as? String else { return }
            NSSpellChecker.shared.learnWord(word)
            tv._spellingDidChange()
        },
        "checkTextInDocument:": { $0.checkTextInDocument($1) }, "checkTextInSelection:": { $0.checkTextInSelection($1) },
        "toggleContinuousSpellChecking:": { $0.toggleContinuousSpellChecking($1) }, "toggleGrammarChecking:": { $0.toggleGrammarChecking($1) },
        "toggleAutomaticSpellingCorrection:": { $0.toggleAutomaticSpellingCorrection($1) },
        "orderFrontSubstitutionsPanel:": { $0.orderFrontSubstitutionsPanel($1) }, "toggleSmartInsertDelete:": { $0.toggleSmartInsertDelete($1) },
        "toggleAutomaticQuoteSubstitution:": { $0.toggleAutomaticQuoteSubstitution($1) }, "toggleAutomaticDashSubstitution:": { $0.toggleAutomaticDashSubstitution($1) },
        "toggleAutomaticTextReplacement:": { $0.toggleAutomaticTextReplacement($1) }, "toggleAutomaticTextCompletion:": { $0.toggleAutomaticTextCompletion($1) },
        "toggleAutomaticLinkDetection:": { $0.toggleAutomaticLinkDetection($1) }, "toggleAutomaticDataDetection:": { $0.toggleAutomaticDataDetection($1) },
        "complete:": { $0.complete($1) },
        "_insertCompletionFromMenu:": { tv, sender in
            guard let item = sender as? NSMenuItem, let r = (item.representedObject as? NSValue)?.rangeValue else { return }
            tv.insertCompletion(item.title, forPartialWordRange: r, movement: NSTextMovement.return.rawValue, isFinal: true)
        },
        "orderFrontListPanel:": { $0.orderFrontListPanel($1) }, "orderFrontTablePanel:": { $0.orderFrontTablePanel($1) },
        "alignJustified:": { $0.alignJustified($1) }, "alignLeft:": { $0.alignLeft($1) }, "alignCenter:": { $0.alignCenter($1) }, "alignRight:": { $0.alignRight($1) },
        "loosenKerning:": { $0.loosenKerning($1) }, "tightenKerning:": { $0.tightenKerning($1) }, "useStandardKerning:": { $0.useStandardKerning($1) }, "turnOffKerning:": { $0.turnOffKerning($1) },
        "raiseBaseline:": { $0.raiseBaseline($1) }, "lowerBaseline:": { $0.lowerBaseline($1) },
        "useStandardLigatures:": { $0.useStandardLigatures($1) }, "useAllLigatures:": { $0.useAllLigatures($1) }, "turnOffLigatures:": { $0.turnOffLigatures($1) },
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
        case "pasteAsPlainText:", "pasteAsRichText:": return isEditable
        case "performFindPanelAction:", "performTextFinderAction:":
            guard usesFindBar || usesFindPanel else { return false }
            let action = NSTextFinder.Action(rawValue: menuItem.tag == 0 ? 1 : menuItem.tag) ?? .showFindInterface
            return _makeFinderIfNeeded().validateAction(action)
        case "toggleContinuousSpellChecking:": menuItem.state = isContinuousSpellCheckingEnabled ? .on : .off; return true
        case "toggleGrammarChecking:": menuItem.state = isGrammarCheckingEnabled ? .on : .off; return true
        case "toggleAutomaticSpellingCorrection:": menuItem.state = isAutomaticSpellingCorrectionEnabled ? .on : .off; return true
        case "toggleSmartInsertDelete:": menuItem.state = smartInsertDeleteEnabled ? .on : .off; return true
        case "toggleAutomaticQuoteSubstitution:": menuItem.state = isAutomaticQuoteSubstitutionEnabled ? .on : .off; return isEditable
        case "toggleAutomaticDashSubstitution:": menuItem.state = isAutomaticDashSubstitutionEnabled ? .on : .off; return isEditable
        case "toggleAutomaticTextReplacement:": menuItem.state = isAutomaticTextReplacementEnabled ? .on : .off; return isEditable
        case "toggleAutomaticTextCompletion:": menuItem.state = isAutomaticTextCompletionEnabled ? .on : .off; return isEditable
        case "toggleAutomaticLinkDetection:": menuItem.state = isAutomaticLinkDetectionEnabled ? .on : .off; return isEditable
        case "toggleAutomaticDataDetection:": menuItem.state = isAutomaticDataDetectionEnabled ? .on : .off; return isEditable
        case "checkSpelling:", "showGuessPanel:", "checkTextInDocument:": return !string.isEmpty || NSStringFromSelector(action) == "showGuessPanel:"
        case "changeSpelling:", "ignoreSpelling:", "_learnSpellingFromMenu:": return isEditable
        case "complete:": return isEditable && rangeForUserCompletion.location != NSNotFound
        case "orderFrontListPanel:", "orderFrontTablePanel:": return isEditable && isRichText
        default: return true
        }
    }

    // MARK: NSTextInputClient

    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard isEditable else { return }
        var text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        var range = replacementRange.location == NSNotFound ? (_markedRange ?? selectedRange) : replacementRange
        if _markedRange != nil && replacementRange.location == NSNotFound { range = _markedRange! }
        let typed = _markedRange == nil && replacementRange.location == NSNotFound
        _markedRange = nil
        // Smart quotes and dashes replace what was typed (ADR-0030).
        if typed, range.length == 0, let (sub, r) = _smartSubstitution(for: text, at: range.location) {
            text = sub
            range = r
        }
        if let rich = string as? NSAttributedString, isRichText, rich.length > 0 {
            _replaceAttributed(range, with: rich)
        } else {
            _editReplace(range, text)
        }
        if typed { _substituteAfterWord(typed: text) }
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

    /// Every edit: matches and misspellings are found again.
    internal override func _noteDidChange() {
        super._noteDidChange()
        _extras.finder?.noteClientStringWillChange()
        _spellingAfterEdit()
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
        updateDragTypeRegistration()
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
        // Text typed at the start of a paragraph takes that paragraph's style (a list item,
        // a table cell), not the previous paragraph's; an attachment's attribute never spreads.
        let s = _storage.string as NSString
        let atParagraphStart = r.location == 0 || (r.location <= s.length && [0x0A, 0x0D, 0x2029].contains(s.character(at: r.location - 1)))
        if atParagraphStart, r.location < s.length, let ps = _storage.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) {
            attrs[.paragraphStyle] = ps
        } else if atParagraphStart, let pending = _extras.pendingParagraphStyle, pending.location == r.location {
            attrs[.paragraphStyle] = pending.style
        } else if atParagraphStart, r.location >= s.length, let ps = attrs[.paragraphStyle] as? NSParagraphStyle, !ps.textBlocks.isEmpty || !ps.textLists.isEmpty {
            // A new last paragraph does not continue a table cell or a list item by itself
            // (Return in a list makes the next item explicitly).
            let plain = (ps.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            plain.textBlocks = []
            plain.textLists = []
            plain.headIndent = 0
            plain.firstLineHeadIndent = 0
            plain.tabStops = []
            attrs[.paragraphStyle] = plain
        }
        _extras.pendingParagraphStyle = nil
        attrs[.attachment] = nil
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
        _drawFindHighlights(above: false)
        _layoutManager.drawGlyphs(forGlyphRange: all, at: origin)
        _drawFindHighlights(above: true)
        if let m = _markedRange, m.length > 0 {
            (textColor ?? .textColor).setFill()
            _layoutManager.enumerateEnclosingRects(forGlyphRange: m, withinSelectedGlyphRange: m, in: _container) { r, _ in
                NSBezierPath.fill(NSRect(x: r.minX + origin.x, y: r.maxY + origin.y - 2, width: r.width, height: 1))
            }
        }
        let sel = selectedRange
        if shouldDrawInsertionPoint && sel.length == 0 {
            let caret = _caretRect(for: sel.location)
            drawInsertionPoint(in: NSRect(x: caret.minX.rounded(), y: caret.minY, width: 1, height: caret.height), color: insertionPointColor, turnedOn: true)
        }
    }

    // MARK: Context menu, links, pasteboard and dragging (ADR-0030)

    open override func menu(for event: NSEvent) -> NSMenu? {
        guard isSelectable, !isFieldEditor else { return super.menu(for: event) }
        return _contextMenu(for: event)
    }

    open override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, !event.modifierFlags.contains(.shift), let st = textStorage, st.length > 0 {
            let i = _offset(at: convert(event.locationInWindow, from: nil))
            if i < st.length, let link = st.attribute(.link, at: i, effectiveRange: nil) {
                clicked(onLink: link, at: i)
                return
            }
            if i < st.length, let a = st.attribute(.attachment, at: i, effectiveRange: nil) as? NSTextAttachment, let cell = a.attachmentCell,
               let r = _layoutManager._attachmentRect(at: i) {
                let frame = r.offsetBy(dx: _drawOrigin.x, dy: _drawOrigin.y)
                if frame.contains(convert(event.locationInWindow, from: nil)) {
                    super.mouseDown(with: event)
                    if event.clickCount == 2 { _viewDelegate?.textView(self, doubleClickedOn: cell, in: frame, at: i) }
                    else { _viewDelegate?.textView(self, clickedOn: cell, in: frame, at: i) }
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    open override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        _ = writeSelection(to: .general, types: writablePasteboardTypes)
    }
    open override func cut(_ sender: Any?) {
        guard isEditable, selectedRange.length > 0 else { return }
        copy(sender)
        delete(sender)
    }
    open override func delete(_ sender: Any?) {
        guard isEditable, selectedRange.length > 0 else { return }
        let r = smartDeleteRange(forProposedRange: selectedRange)
        _replaceAttributed(r, with: NSAttributedString(string: ""))
    }
    open override func paste(_ sender: Any?) {
        guard isEditable else { return }
        _ = readSelection(from: .general)
    }

    open override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { _dragOperation(sender) }
    open override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = _dragOperation(sender)
        if !op.isEmpty { setSelectedRange(NSRange(location: _offset(at: convert(sender.draggingLocation, from: nil)), length: 0)) }
        return op
    }
    open override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEditable else { return false }
        let at = _offset(at: convert(sender.draggingLocation, from: nil))
        guard let content = _readContent(from: sender.draggingPasteboard) else { return false }
        setSelectedRange(NSRange(location: at, length: 0))
        _ = window?.makeFirstResponder(self)
        _insertPasted(content)
        return true
    }
    private func _dragOperation(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable, let type = sender.draggingPasteboard.availableType(from: acceptableDragTypes) else { return [] }
        return dragOperation(for: sender, type: type)
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
    @MainActor open var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        isRichText && importsGraphics ? [.rtfd, .rtf, .fileURL, .png, .tiff, .string] : isRichText ? [.rtf, .string] : [.string]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/acceptsglyphinfo
    @MainActor open var acceptsGlyphInfo: Bool {
        get { _extras.acceptsGlyphInfo }
        set { _extras.acceptsGlyphInfo = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/alignjustified(_:)
    @MainActor open func alignJustified(_ sender: Any?) { alignment = .justified }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowedinputsourcelocales
    @MainActor open var allowedInputSourceLocales: [String]? {
        get { _extras.allowedInputSourceLocales }
        set { _extras.allowedInputSourceLocales = newValue }
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
        get { _extras.allowsCharacterPickerTouchBarItem }
        set { _extras.allowsCharacterPickerTouchBarItem = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowsdocumentbackgroundcolorchange
    @MainActor open var allowsDocumentBackgroundColorChange: Bool {
        get { _extras.allowsDocumentBackgroundColorChange }
        set { _extras.allowsDocumentBackgroundColorChange = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/allowsimageediting
    @MainActor open var allowsImageEditing: Bool {
        get { _extras.allowsImageEditing }
        set { _extras.allowsImageEditing = newValue }
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
    @MainActor open func checkTextInDocument(_ sender: Any?) {
        _markSpelling(in: NSRange(location: 0, length: (string as NSString).length))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/checktextinselection(_:)
    @MainActor open func checkTextInSelection(_ sender: Any?) {
        _markSpelling(in: selectedRange.length > 0 ? selectedRange : NSRange(location: 0, length: (string as NSString).length))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/cleanupafterdragoperation()
    /// Nothing is left over: drops insert at once.
    @MainActor open func cleanUpAfterDragOperation() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/clicked(onlink:at:)
    @MainActor open func clicked(onLink link: Any, at charIndex: Int) {
        if _viewDelegate?.textView(self, clickedOnLink: link, at: charIndex) == true { return }
        // No workspace to open URLs with here: an unhandled link click selects the link.
        if let st = textStorage, charIndex < st.length {
            var r = NSRange(location: 0, length: 0)
            _ = st.attribute(.link, at: charIndex, effectiveRange: &r)
            setSelectedRange(r)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/complete(_:)
    @MainActor open func complete(_ sender: Any?) { _completeWord() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/completions(forpartialwordrange:indexofselecteditem:)
    @MainActor open func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        index.pointee = 0
        let words = NSSpellChecker.shared.completions(forPartialWordRange: charRange, in: string, language: nil, inSpellDocumentWithTag: _spellTag) ?? []
        let chosen = _viewDelegate?.textView(self, completions: words, forPartialWordRange: charRange, indexOfSelectedItem: index) ?? words
        return chosen.isEmpty ? nil : chosen
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/defaultparagraphstyle
    @MainActor open var defaultParagraphStyle: NSParagraphStyle? {
        get { _extras.defaultParagraphStyle }
        set { _extras.defaultParagraphStyle = newValue; if let p = newValue { var t = typingAttributes; t[.paragraphStyle] = p; typingAttributes = t } }
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
        get { _extras.displaysLinkToolTips }
        set { _extras.displaysLinkToolTips = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/dragimageforselection(with:origin:)
    @MainActor open func dragImageForSelection(with event: NSEvent, origin: NSPointPointer?) -> NSImage? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/dragoperation(for:type:)
    @MainActor open func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        isEditable && acceptableDragTypes.contains(type) ? (dragInfo.draggingSourceOperationMask.contains(.copy) || dragInfo.draggingSourceOperationMask.isEmpty ? .copy : dragInfo.draggingSourceOperationMask.intersection([.copy, .generic, .move])) : []
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/dragselection(with:offset:slideback:)
    @MainActor open func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/drawbackground(in:)
    @MainActor open func drawBackground(in rect: NSRect) {
        if drawsBackground, let bg = backgroundColor { bg.setFill(); NSBezierPath.fill(rect) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/drawinsertionpoint(in:color:turnedon:)
    @MainActor open func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if flag { color.setFill(); NSBezierPath.fill(rect) } else { needsDisplay = true }
    }
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
    @MainActor open func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        // Not final: shown in place as the selection moves; final: inserted (or, on cancel, the
        // partial word restored).
        let r = _clamped(NSRange(location: charRange.location, length: max(charRange.length, selectedRange.location + selectedRange.length - charRange.location)))
        let text = movement == NSTextMovement.cancel.rawValue ? (_extras.completionPartial ?? (string as NSString).substring(with: charRange)) : word
        guard shouldChangeText(in: r, replacementString: text) else { return }
        _finderReplace(r, with: text)
        let end = r.location + (text as NSString).length
        setSelectedRange(flag ? NSRange(location: end, length: 0) : NSRange(location: charRange.location + charRange.length, length: max(0, end - charRange.location - charRange.length)))
        if flag { _extras.completionPartial = nil }
        didChangeText()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/inserttext(_:)
    @MainActor open func insertText(_ insertString: Any) { insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/insertionpointcolor
    @MainActor open var insertionPointColor: NSColor! {
        get { _insertionPointColor ?? textColor ?? .textColor }
        set { _insertionPointColor = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/invalidatetextcontainerorigin()
    @MainActor open func invalidateTextContainerOrigin() {
        needsDisplay = true   // textContainerOrigin is computed from the inset on demand
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticdashsubstitutionenabled
    @MainActor open var isAutomaticDashSubstitutionEnabled: Bool {
        get { _extras.isAutomaticDashSubstitutionEnabled }
        set { _extras.isAutomaticDashSubstitutionEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticdatadetectionenabled
    @MainActor open var isAutomaticDataDetectionEnabled: Bool {
        get { _extras.isAutomaticDataDetectionEnabled }
        set { _extras.isAutomaticDataDetectionEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomaticlinkdetectionenabled
    @MainActor open var isAutomaticLinkDetectionEnabled: Bool {
        get { _extras.isAutomaticLinkDetectionEnabled }
        set { _extras.isAutomaticLinkDetectionEnabled = newValue }
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
        get { _extras.isAutomaticTextCompletionEnabled }
        set { _extras.isAutomaticTextCompletionEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isautomatictextreplacementenabled
    @MainActor open var isAutomaticTextReplacementEnabled: Bool {
        get { _extras.isAutomaticTextReplacementEnabled }
        set { _extras.isAutomaticTextReplacementEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/iscoalescingundo
    @MainActor open var isCoalescingUndo: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/iscontinuousspellcheckingenabled
    @MainActor open var isContinuousSpellCheckingEnabled: Bool {
        get { _isContinuousSpellCheckingEnabled }
        set {
            guard newValue != _isContinuousSpellCheckingEnabled else { return }
            _isContinuousSpellCheckingEnabled = newValue
            _spellingDidChange()
        }
    }
    /// Stored only: grammar checking is not implemented (NSSpellChecker finds nothing).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isgrammarcheckingenabled
    @MainActor open var isGrammarCheckingEnabled: Bool {
        get { _isGrammarCheckingEnabled }
        set { _isGrammarCheckingEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/isincrementalsearchingenabled
    @MainActor open var isIncrementalSearchingEnabled: Bool {
        get { _extras.incrementalSearching }
        set { _extras.incrementalSearching = newValue; _extras.finder?.isIncrementalSearchingEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/iswritingtoolsactive
    @available(macOS 15.0, *)
    @MainActor open var isWritingToolsActive: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/layoutmanager
    @MainActor open var layoutManager: NSLayoutManager? { _layoutManager }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/linktextattributes
    @MainActor open var linkTextAttributes: [NSAttributedString.Key : Any]? {
        get { _extras.linkTextAttributes }
        set { _extras.linkTextAttributes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/loosenkerning(_:)
    @MainActor open func loosenKerning(_ sender: Any?) { _adjustKern(by: 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/lowerbaseline(_:)
    @MainActor open func lowerBaseline(_ sender: Any?) { _adjustBaseline(by: -1) }
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
    @MainActor open func orderFrontListPanel(_ sender: Any?) {
        // A menu item that names a marker format applies it at once; otherwise the panel opens.
        if let format = ((sender as? NSMenuItem)?.representedObject as? String) {
            _applyList(markerFormat: format.isEmpty ? nil : NSTextList.MarkerFormat(rawValue: format))
            return
        }
        _NSListPanel.show(for: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontsharingservicepicker(_:)
    @MainActor open func orderFrontSharingServicePicker(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontspacingpanel(_:)
    @MainActor open func orderFrontSpacingPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfrontsubstitutionspanel(_:)
    @MainActor open func orderFrontSubstitutionsPanel(_ sender: Any?) {
        NSSpellChecker.shared.substitutionsPanel.makeKeyAndOrderFront(sender)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/orderfronttablepanel(_:)
    @MainActor open func orderFrontTablePanel(_ sender: Any?) {
        // A menu item whose represented object is [rows, columns] inserts that table at once.
        if let size = (sender as? NSMenuItem)?.representedObject as? [Int], size.count == 2 { _insertTable(rows: size[0], columns: size[1]); return }
        _NSTablePanel.show(for: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/outline(_:)
    @MainActor open func outline(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/pasteasplaintext(_:)
    @MainActor open func pasteAsPlainText(_ sender: Any?) {
        guard isEditable, let s = NSPasteboard.general.string(forType: .string) else { return }
        _insertPasted(NSAttributedString(string: s, attributes: typingAttributes))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/pasteasrichtext(_:)
    @MainActor open func pasteAsRichText(_ sender: Any?) {
        guard isEditable, let c = _readContent(from: .general) else { return }
        _insertPasted(c)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/performfindpanelaction(_:)
    @MainActor open func performFindPanelAction(_ sender: Any?) {
        _performFind(tag: (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag ?? 1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/performvalidatedreplacement(in:with:)
    @available(macOS 10.14, *)
    @MainActor open func performValidatedReplacement(in range: NSRange, with attributedString: NSAttributedString) -> Bool {
        let r = _clamped(range)
        guard shouldChangeText(in: r, replacementString: attributedString.string) else { return false }
        // Attributes the replacement does not give come from the text it replaces.
        let base = r.length > 0 ? (textStorage?.attributes(at: r.location, effectiveRange: nil) ?? typingAttributes) : typingAttributes
        let m = NSMutableAttributedString(string: attributedString.string, attributes: base)
        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { a, sub, _ in m.addAttributes(a, range: sub) }
        textStorage?.replaceCharacters(in: r, with: m)
        _invalidateLayout()
        setSelectedRange(NSRange(location: r.location + m.length, length: 0))
        didChangeText()
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/preferredpasteboardtype(from:restrictedtotypesfrom:)
    @MainActor open func preferredPasteboardType(from availableTypes: [NSPasteboard.PasteboardType], restrictedToTypesFrom allowedTypes: [NSPasteboard.PasteboardType]?) -> NSPasteboard.PasteboardType? {
        readablePasteboardTypes.first { availableTypes.contains($0) && (allowedTypes?.contains($0) ?? true) }
    }
    // SKIPPED (unknown module (QuickLook QLPreviewItem)): @MainActor func quickLookPreviewableItems(inRanges ranges: [NSValue]) -> [any QLPreviewItem]
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/raisebaseline(_:)
    @MainActor open func raiseBaseline(_ sender: Any?) { _adjustBaseline(by: 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforusercharacterattributechange
    @MainActor open var rangeForUserCharacterAttributeChange: NSRange {
        isEditable && isRichText ? selectedRange : NSRange(location: NSNotFound, length: 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforusercompletion
    @MainActor open var rangeForUserCompletion: NSRange {
        // The word ending at the insertion point.
        let sel = selectedRange
        guard sel.length == 0, sel.location > 0 else { return NSRange(location: NSNotFound, length: 0) }
        let s = string as NSString
        var a = sel.location
        while a > 0 {
            guard let u = UnicodeScalar(s.character(at: a - 1)), CharacterSet.alphanumerics.contains(u) || u == "'" else { break }
            a -= 1
        }
        return a < sel.location ? NSRange(location: a, length: sel.location - a) : NSRange(location: NSNotFound, length: 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforuserparagraphattributechange
    @MainActor open var rangeForUserParagraphAttributeChange: NSRange {
        isEditable && isRichText ? _paragraphsRange(selectedRange) : NSRange(location: NSNotFound, length: 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangeforusertextchange
    @MainActor open var rangeForUserTextChange: NSRange {
        isEditable ? (_markedRange ?? selectedRange) : NSRange(location: NSNotFound, length: 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangesforusercharacterattributechange
    @MainActor open var rangesForUserCharacterAttributeChange: [NSValue]? {
        let r = rangeForUserCharacterAttributeChange; return r.location == NSNotFound ? nil : [NSValue(range: r)]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangesforuserparagraphattributechange
    @MainActor open var rangesForUserParagraphAttributeChange: [NSValue]? {
        let r = rangeForUserParagraphAttributeChange; return r.location == NSNotFound ? nil : [NSValue(range: r)]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/rangesforusertextchange
    @MainActor open var rangesForUserTextChange: [NSValue]? {
        let r = rangeForUserTextChange; return r.location == NSNotFound ? nil : [NSValue(range: r)]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/readselection(from:)
    @MainActor open func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let c = _readContent(from: pboard) else { return false }
        _insertPasted(c, smart: pboard.types?.contains(NSTextView._smartPasteType) == true)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/readselection(from:type:)
    @MainActor open func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let c = _readContent(from: pboard, type: type) else { return false }
        _insertPasted(c, smart: pboard.types?.contains(NSTextView._smartPasteType) == true)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/readablepasteboardtypes
    @MainActor open var readablePasteboardTypes: [NSPasteboard.PasteboardType] { acceptableDragTypes }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/registerforservices()
    @MainActor public class func registerForServices() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/replacetextcontainer(_:)
    @MainActor open func replaceTextContainer(_ newContainer: NSTextContainer) {
        guard newContainer !== _container else { return }
        if let lm = newContainer.layoutManager, lm !== _layoutManager, let i = lm.textContainers.firstIndex(where: { $0 === newContainer }) { lm.removeTextContainer(at: i) }
        if let i = _layoutManager.textContainers.firstIndex(where: { $0 === _container }) {
            _layoutManager.removeTextContainer(at: i)
            _layoutManager.insertTextContainer(newContainer, at: i)
        }
        textContainer = newContainer
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/scrollabledocumentcontenttextview()
    @available(macOS 10.14, *)
    @MainActor public class func scrollableDocumentContentTextView() -> NSScrollView { NSTextView._scrollable(rich: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/scrollableplaindocumentcontenttextview()
    @available(macOS 10.14, *)
    @MainActor public class func scrollablePlainDocumentContentTextView() -> NSScrollView { NSTextView._scrollable(rich: false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/scrollabletextview()
    @available(macOS 10.14, *)
    @MainActor public class func scrollableTextView() -> NSScrollView { NSTextView._scrollable(rich: true, document: false) }
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
    @MainActor open var selectionAffinity: NSSelectionAffinity { .downstream }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/selectiongranularity
    @MainActor open var selectionGranularity: NSSelectionGranularity {
        get { _extras.selectionGranularity }
        set { _extras.selectionGranularity = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/selectionrange(forproposedrange:granularity:)
    @MainActor open func selectionRange(forProposedRange proposedCharRange: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        let r = _clamped(proposedCharRange)
        switch granularity {
        case .selectByWord:
            let a = _wordRange(at: r.location), b = _wordRange(at: max(r.location, NSMaxRange(r) - (r.length > 0 ? 1 : 0)))
            return NSUnionRange(a, b)
        case .selectByParagraph: return _paragraphsRange(r)
        default: return r
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setalignment(_:range:)
    @MainActor open func setAlignment(_ alignment: NSTextAlignment, range: NSRange) {
        let r = _paragraphsRange(range)
        guard let st = textStorage, r.length > 0 else { return }
        st.beginEditing()
        st.enumerateAttribute(.paragraphStyle, in: r, options: []) { v, sub, _ in
            let ps = ((v as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            ps.alignment = alignment
            st.addAttribute(.paragraphStyle, value: ps, range: sub)
        }
        st.endEditing()
        _invalidateLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setbasewritingdirection(_:range:)
    @MainActor open func setBaseWritingDirection(_ writingDirection: NSWritingDirection, range: NSRange) {
        let r = _paragraphsRange(range)
        guard let st = textStorage, r.length > 0 else { return }
        st.beginEditing()
        st.enumerateAttribute(.paragraphStyle, in: r, options: []) { v, sub, _ in
            let ps = ((v as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            ps.baseWritingDirection = writingDirection
            st.addAttribute(.paragraphStyle, value: ps, range: sub)
        }
        st.endEditing()
        _invalidateLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setconstrainedframesize(_:)
    @MainActor open func setConstrainedFrameSize(_ desiredSize: NSSize) {
        setFrameSize(NSSize(width: isHorizontallyResizable ? max(minSize.width, min(maxSize.width, desiredSize.width)) : frame.width,
                            height: isVerticallyResizable ? max(minSize.height, min(maxSize.height, desiredSize.height)) : frame.height))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setlayoutorientation(_:)
    @MainActor open func setLayoutOrientation(_ orientation: NSLayoutManager.TextLayoutOrientation) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setneedsdisplay(_:avoidadditionallayout:)
    @MainActor open func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) { setNeedsDisplay(rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setselectedrange(_:)
    @MainActor open func setSelectedRange(_ charRange: NSRange) { _selectionAnchor = nil; selectedRange = charRange }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setselectedrange(_:affinity:stillselecting:)
    @MainActor open func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) { selectedRange = charRange }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setselectedranges(_:affinity:stillselecting:)
    @MainActor open func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        if let first = ranges.first { setSelectedRange(first.rangeValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/setspellingstate(_:range:)
    @MainActor open func setSpellingState(_ value: Int, range charRange: NSRange) {
        let v = _viewDelegate?.textView(self, shouldSetSpellingState: value, range: charRange) ?? value
        let r = _clamped(charRange)
        if v == 0 { layoutManager?.removeTemporaryAttribute(.spellingState, forCharacterRange: r) }
        else { layoutManager?.addTemporaryAttribute(.spellingState, value: NSNumber(value: v), forCharacterRange: r) }
    }
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
    @MainActor open var shouldDrawInsertionPoint: Bool {
        window?.firstResponder === self && isEditable && (window?.isKeyWindow ?? true)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/showfindindicator(for:)
    @MainActor open func showFindIndicator(for charRange: NSRange) {
        scrollRangeToVisible(charRange); _extras.finder?.findIndicatorNeedsUpdate = true; needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartdeleterange(forproposedrange:)
    @MainActor open func smartDeleteRange(forProposedRange proposedCharRange: NSRange) -> NSRange { _smartDeleteRange(_clamped(proposedCharRange)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsert(afterstringfor:replacing:)
    @MainActor open func smartInsert(afterStringFor pasteString: String, replacing charRangeToReplace: NSRange) -> String? {
        _smartInsert(pasteString, replacing: _clamped(charRangeToReplace)).after
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsert(beforestringfor:replacing:)
    @MainActor open func smartInsert(beforeStringFor pasteString: String, replacing charRangeToReplace: NSRange) -> String? {
        _smartInsert(pasteString, replacing: _clamped(charRangeToReplace)).before
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsert(for:replacing:before:after:)
    @MainActor open func smartInsert(for pasteString: String, replacing charRangeToReplace: NSRange, before beforeString: AutoreleasingUnsafeMutablePointer<NSString?>?, after afterString: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        let r = _smartInsert(pasteString, replacing: _clamped(charRangeToReplace))
        beforeString?.pointee = r.before.map { $0 as NSString }
        afterString?.pointee = r.after.map { $0 as NSString }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/smartinsertdeleteenabled
    @MainActor open var smartInsertDeleteEnabled: Bool {
        get { _smartInsertDeleteEnabled }
        set { _smartInsertDeleteEnabled = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/spellcheckerdocumenttag
    @MainActor open var spellCheckerDocumentTag: Int { _spellTag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/startspeaking(_:)
    @MainActor open func startSpeaking(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/stopspeaking(_:)
    @MainActor open func stopSpeaking(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/stronglyreferencestextstorage
    @available(macOS 10.12, *)
    @MainActor class public var stronglyReferencesTextStorage: Bool { true }
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
    /// TextKit 1 text views have none.
    @MainActor open var textContentStorage: NSTextContentStorage? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/texthighlightattributes
    @available(macOS 15.0, *)
    @MainActor open var textHighlightAttributes: [NSAttributedString.Key : Any] {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textlayoutmanager
    @available(macOS 12.0, *)
    /// TextKit 1 text views have none.
    @MainActor open var textLayoutManager: NSTextLayoutManager? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/textstorage
    @MainActor open var textStorage: NSTextStorage? { _storage }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/tightenkerning(_:)
    @MainActor open func tightenKerning(_ sender: Any?) { _adjustKern(by: -1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticdashsubstitution(_:)
    @MainActor open func toggleAutomaticDashSubstitution(_ sender: Any?) { isAutomaticDashSubstitutionEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticdatadetection(_:)
    @MainActor open func toggleAutomaticDataDetection(_ sender: Any?) { isAutomaticDataDetectionEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticlinkdetection(_:)
    @MainActor open func toggleAutomaticLinkDetection(_ sender: Any?) { isAutomaticLinkDetectionEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticquotesubstitution(_:)
    @MainActor open func toggleAutomaticQuoteSubstitution(_ sender: Any?) { isAutomaticQuoteSubstitutionEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomaticspellingcorrection(_:)
    @MainActor open func toggleAutomaticSpellingCorrection(_ sender: Any?) { isAutomaticSpellingCorrectionEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomatictextcompletion(_:)
    @available(macOS 10.12, *)
    @MainActor open func toggleAutomaticTextCompletion(_ sender: Any?) { isAutomaticTextCompletionEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggleautomatictextreplacement(_:)
    @MainActor open func toggleAutomaticTextReplacement(_ sender: Any?) { isAutomaticTextReplacementEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglecontinuousspellchecking(_:)
    @MainActor open func toggleContinuousSpellChecking(_ sender: Any?) { isContinuousSpellCheckingEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglegrammarchecking(_:)
    @MainActor open func toggleGrammarChecking(_ sender: Any?) { isGrammarCheckingEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglequicklookpreviewpanel(_:)
    @MainActor open func toggleQuickLookPreviewPanel(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/togglesmartinsertdelete(_:)
    @MainActor open func toggleSmartInsertDelete(_ sender: Any?) { smartInsertDeleteEnabled.toggle() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/toggletraditionalcharactershape(_:)
    @MainActor open func toggleTraditionalCharacterShape(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/turnoffkerning(_:)
    @MainActor open func turnOffKerning(_ sender: Any?) { _setCharacterAttribute(.kern, 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/turnoffligatures(_:)
    @MainActor open func turnOffLigatures(_ sender: Any?) { _setCharacterAttribute(.ligature, 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/typingattributes
    @MainActor open var typingAttributes: [NSAttributedString.Key : Any] {
        get { _typingAttributes.isEmpty ? _attributes : _typingAttributes }
        set {
            _typingAttributes = newValue
            // Plain text has one font and colour; rich text keeps what it has.
            guard !isRichText else { return }
            if let f = newValue[.font] as? NSFont { font = f }
            if let c = newValue[.foregroundColor] as? NSColor { textColor = c }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatecandidates()
    @available(macOS 10.12, *)
    @MainActor open func updateCandidates() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatedragtyperegistration()
    @MainActor open func updateDragTypeRegistration() {
        unregisterDraggedTypes()
        if isEditable { registerForDraggedTypes(acceptableDragTypes) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updatefontpanel()
    @MainActor open func updateFontPanel() { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/updateinsertionpointstateandrestarttimer(_:)
    @MainActor open func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) { needsDisplay = true }
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
    @MainActor open func useAllLigatures(_ sender: Any?) { _setCharacterAttribute(.ligature, 2) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usestandardkerning(_:)
    @MainActor open func useStandardKerning(_ sender: Any?) { _setCharacterAttribute(.kern, nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usestandardligatures(_:)
    @MainActor open func useStandardLigatures(_ sender: Any?) { _setCharacterAttribute(.ligature, nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesadaptivecolormappingfordarkappearance
    @available(macOS 10.14, *)
    @MainActor open var usesAdaptiveColorMappingForDarkAppearance: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesfindbar
    @MainActor open var usesFindBar: Bool {
        get { _usesFindBar }
        set { _usesFindBar = newValue; if let f = _extras.finder { f.findBarContainer = nil; _ = _makeFinderIfNeeded() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesfindpanel
    @MainActor open var usesFindPanel: Bool {
        get { _extras.usesFindPanel }
        set { _extras.usesFindPanel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesinspectorbar
    @MainActor open var usesInspectorBar: Bool {
        get { _extras.usesInspectorBar }
        set { _extras.usesInspectorBar = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesrolloverbuttonforselection
    @available(macOS 10.10, *)
    @MainActor open var usesRolloverButtonForSelection: Bool {
        get { _extras.usesRolloverButtonForSelection }
        set { _extras.usesRolloverButtonForSelection = newValue }
    }
    /// Stored only: the port has no NSRulerView yet, so no ruler is shown (ADR-0030).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/usesruler
    @MainActor open var usesRuler: Bool {
        get { _extras.usesRuler }
        set { _extras.usesRuler = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/willchangenotifyingtextviewnotification
    static public var willChangeNotifyingTextViewNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextViewWillChangeNotifyingTextViewNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/willswitchtonslayoutmanagernotification
    @available(macOS 12.0, *)
    static public var willSwitchToNSLayoutManagerNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextViewWillSwitchToNSLayoutManagerNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writablepasteboardtypes
    @MainActor open var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        isRichText ? (importsGraphics ? [.rtfd, .rtf, .string] : [.rtf, .string]) : [.string]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writeselection(to:type:)
    @MainActor open func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool { _writeSelection(to: pboard, types: [type]) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writeselection(to:types:)
    @MainActor open func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool { _writeSelection(to: pboard, types: types) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextview/writingtoolsbehavior
    @available(macOS 15.0, *)
    @MainActor open var writingToolsBehavior: NSWritingToolsBehavior {
        get { unimplemented() }
        set { unimplemented() }
    }
    // MARK: Spelling actions (NSText, NSChangeSpelling, NSIgnoreMisspelledWords)

    /// Selects the next misspelt word after the selection and shows it in the Spelling panel.
    open override func checkSpelling(_ sender: Any?) { _checkSpellingFromSelection() }
    /// Shows the Spelling panel on the next misspelling.
    open override func showGuessPanel(_ sender: Any?) {
        NSSpellChecker.shared.spellingPanel.makeKeyAndOrderFront(sender)
        _checkSpellingFromSelection()
    }
    /// Replaces the selection with the sender's title or string value (a guess).
    open override func changeSpelling(_ sender: Any?) {
        guard isEditable else { return }
        let word = (sender as? NSMenuItem)?.title ?? (sender as? NSControl)?.stringValue ?? ""
        guard !word.isEmpty, selectedRange.length > 0 else { return }
        let r = selectedRange
        guard shouldChangeText(in: r, replacementString: word) else { return }
        _finderReplace(r, with: word)
        setSelectedRange(NSRange(location: r.location, length: (word as NSString).length))
        didChangeText()
        layoutManager?.removeTemporaryAttribute(.spellingState, forCharacterRange: NSRange(location: r.location, length: (word as NSString).length))
    }
    /// Ignores the word (the sender's string, or the selection) in this document.
    open override func ignoreSpelling(_ sender: Any?) {
        let word = ((sender as? NSMenuItem)?.representedObject as? String) ?? (sender as? NSControl)?.stringValue ?? (string as NSString).substring(with: selectedRange)
        guard !word.isEmpty else { return }
        NSSpellChecker.shared.ignoreWord(word, inSpellDocumentWithTag: _spellTag)
        _spellingDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsresponder/performtextfinderaction(_:)
    open override func performTextFinderAction(_ sender: Any?) { performFindPanelAction(sender) }

    // Requirement of NSColorChanging (signature differs from the inherited member)
    // Requirement of NSColorChanging
    open func changeColor(_ sender: NSColorPanel?) { unimplemented() }
    // Requirement of NSTextInputClient
    open func doCommand(by selector: Selector) {
        MainActor.assumeIsolated {
            if let d = _viewDelegate, d.textView(self, doCommandBy: selector) { return }
            if isFieldEditor, let f = _textDelegate as? NSTextField, f._editorDoCommand(by: selector) { return }
            if let action = NSTextView._selectorDispatch[NSStringFromSelector(selector)] { action(self, nil) }
        }
    }
    // Requirement of NSTextLayoutOrientationProvider
    /// Horizontal: vertical layout is not implemented.
    open var layoutOrientation: NSLayoutManager.TextLayoutOrientation { .horizontal }
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
