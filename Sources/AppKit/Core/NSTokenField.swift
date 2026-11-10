// NSTokenField (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A text field whose value is a list of tokens. Typing a tokenizing character (or
// Return, Tab, or ending editing) turns the text before it into a token; Backspace at
// the start of the text selects the last token and deletes it when pressed again; Left
// and Right move the selection along the tokens; a token with a menu opens it from its
// chevron; a double-click turns a token back into text. The delegate's completions for
// the typed text show in a list under the field (ADR-0021), navigated with Up and Down
// and taken with Return or Tab.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfield
@MainActor open class NSTokenField: NSTextField {
    internal var _tokenCell: NSTokenFieldCell? { _cell as? NSTokenFieldCell }
    internal var _tokenDelegate: (any NSTokenFieldDelegate)? { delegate as? NSTokenFieldDelegate }
    private var _completionTimer: Timer? = nil
    internal var _completionPopUp: _NSTokenCompletionPopUp? = nil
    internal var _completions: [Any] = []
    internal var _selectedCompletion = -1

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSTokenFieldCell(textCell: "") }

    private var _editor: NSTextView? { _fieldEditor }

    // MARK: Editing

    /// The editor starts empty: the tokens are drawn by the cell, the editor holds the
    /// text after them.
    @MainActor internal override var _editorInitialString: String {
        let t = _tokenCell?._trailingText ?? ""
        _tokenCell?._trailingText = ""
        return t
    }

    /// Tokenizing characters in the typed text cut tokens off its start; the rest stays
    /// in the editor. Then the completions for what is left are looked up.
    @MainActor internal override func _editorTextDidChange(_ editor: NSTextView) {
        guard let cell = _tokenCell else { return }
        cell._selectedToken = -1
        let text = editor.string
        if let lastSep = text.unicodeScalars.lastIndex(where: { cell.tokenizingCharacterSet.contains($0) }) {
            let head = String(String.UnicodeScalarView(text.unicodeScalars[text.unicodeScalars.startIndex..<lastSep]))
            let tail = String(String.UnicodeScalarView(text.unicodeScalars[text.unicodeScalars.index(after: lastSep)...])).trimmingCharacters(in: .whitespacesAndNewlines)
            _addTokens(cell._tokenize(head))
            editor.string = tail
            editor.selectedRange = NSRange(location: (tail as NSString).length, length: 0)
            _relayoutEditor()
            needsDisplay = true
        }
        _scheduleCompletion()
    }

    /// Editing ends (or Return): the typed text becomes a token too.
    @MainActor internal override func _takeEditorValue(_ editor: NSTextView) {
        guard let cell = _tokenCell else { return }
        _closeCompletions()
        let text = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { _addTokens(cell._tokenize(text)) }
        editor.string = ""
        cell._trailingText = ""
        _relayoutEditor()
        needsDisplay = true
        invalidateIntrinsicContentSize()
        _accessibilityValueChanged()
    }

    @MainActor private func _addTokens(_ tokens: [Any]) {
        guard let cell = _tokenCell, !tokens.isEmpty else { return }
        let added = cell._filtered(tokens, at: cell._tokens.count)
        cell._tokens.append(contentsOf: added)
        invalidateIntrinsicContentSize()
        _accessibilityValueChanged()
    }

    @MainActor private func _removeToken(at i: Int) {
        guard let cell = _tokenCell, cell._tokens.indices.contains(i) else { return }
        cell._tokens.remove(at: i)
        cell._selectedToken = -1
        _relayoutEditor()
        needsDisplay = true
        invalidateIntrinsicContentSize()
        _accessibilityValueChanged()
    }

    /// Turns a token back into its editing string in the editor (a double-click).
    @MainActor internal func _editToken(at i: Int) {
        guard let cell = _tokenCell, cell._tokens.indices.contains(i) else { return }
        let text = cell._editingString(for: cell._tokens[i])
        // Tokens after the edited one are tokenized again behind the text.
        let after = Array(cell._tokens[(i + 1)...])
        cell._tokens.removeSubrange(i...)
        cell._selectedToken = -1
        if _editor == nil { _ = window?.makeFirstResponder(self) }
        if let e = _editor {
            let sep = cell._separator
            let tail = after.isEmpty ? "" : sep + after.map { cell._displayString(for: $0) }.joined(separator: sep)
            e.string = text + tail
            e.selectedRange = NSRange(location: 0, length: (text as NSString).length)
            _relayoutEditor()
        } else {
            cell._tokens.append(contentsOf: after)
        }
        needsDisplay = true
    }

    private var _caretAtStart: Bool {
        guard let e = _editor else { return false }
        return e.selectedRange.location == 0 && e.selectedRange.length == 0
    }

    @MainActor internal override func _editorDoCommand(by selector: Selector) -> Bool {
        if super._editorDoCommand(by: selector) { return true }
        guard let cell = _tokenCell else { return false }
        let name = NSStringFromSelector(selector)
        let popUp = _completionPopUp != nil
        switch name {
        case "moveUp:" where popUp:
            _selectCompletion(max(0, _selectedCompletion - 1)); return true
        case "moveDown:" where popUp:
            _selectCompletion(min(_completions.count - 1, _selectedCompletion + 1)); return true
        case "insertNewline:" where popUp && _selectedCompletion >= 0, "insertTab:" where popUp && _selectedCompletion >= 0:
            _acceptCompletion(_selectedCompletion); return true
        case "cancelOperation:" where popUp:
            _closeCompletions(); return true
        case "insertTab:", "insertBacktab:":
            // The typed text becomes a token before focus moves on.
            if let e = _editor, !e.string.isEmpty { _addTokens(cell._tokenize(e.string)); e.string = ""; _relayoutEditor() }
            return false
        case "deleteBackward:":
            guard _caretAtStart, !cell._tokens.isEmpty else { return false }
            if cell._selectedToken >= 0 { _removeToken(at: cell._selectedToken) }
            else { cell._selectedToken = cell._tokens.count - 1; needsDisplay = true }
            return true
        case "deleteForward:":
            guard cell._selectedToken >= 0 else { return false }
            _removeToken(at: cell._selectedToken)
            return true
        case "moveLeft:", "moveBackward:":
            guard _caretAtStart, !cell._tokens.isEmpty else { return false }
            if cell._selectedToken < 0 { cell._selectedToken = cell._tokens.count - 1 }
            else if cell._selectedToken > 0 { cell._selectedToken -= 1 }
            needsDisplay = true
            return true
        case "moveRight:", "moveForward:":
            guard cell._selectedToken >= 0 else { return false }
            cell._selectedToken = cell._selectedToken < cell._tokens.count - 1 ? cell._selectedToken + 1 : -1
            needsDisplay = true
            return true
        default:
            return false
        }
    }

    @MainActor open override func textDidEndEditing(_ notification: Notification) {
        _closeCompletions()
        super.textDidEndEditing(notification)
    }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _relayoutEditor()
    }

    // MARK: Mouse

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell = _tokenCell else { super.mouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if let hit = cell._token(at: p, in: _cellFrame) {
            if _editor == nil { _ = window?.makeFirstResponder(self) }
            if hit.onMenu, let menu = cell._menu(for: cell._tokens[hit.index]), let w = window {
                cell._selectedToken = hit.index
                needsDisplay = true
                let r = cell._tokenRects(in: _cellFrame)[hit.index]
                _ = _NSMenuTracker.begin(menu: menu, anchor: w.convertToScreen(convert(r, to: nil)), placement: .besideAnchor(edge: .maxY), openedWithMouseDown: true)
                return
            }
            if event.clickCount == 2 { _editToken(at: hit.index); return }
            cell._selectedToken = hit.index
            _editor?.selectedRange = NSRange(location: 0, length: 0)
            needsDisplay = true
            return
        }
        cell._selectedToken = -1
        super.mouseDown(with: event)
    }

    // MARK: Completions

    private func _scheduleCompletion() {
        _completionTimer?.invalidate()
        _completionTimer = nil
        let delay = completionDelay
        if delay <= 0 { _showCompletions(); return }
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?._showCompletions() }
        }
        RunLoop.main.add(t, forMode: .common)
        _completionTimer = t
    }

    /// Asks the delegate for completions of the typed text and shows them (or hides the list).
    @MainActor internal func _showCompletions() {
        guard let cell = _tokenCell, let e = _editor, let d = _tokenDelegate else { _closeCompletions(); return }
        let text = e.string
        guard !text.isEmpty else { _closeCompletions(); return }
        var selected = 0
        let found: [Any]? = withUnsafeMutablePointer(to: &selected) { d.tokenField(self, completionsForSubstring: text, indexOfToken: cell._tokens.count, indexOfSelectedItem: $0) }
        guard let list = found, !list.isEmpty else { _closeCompletions(); return }
        _completions = list
        _selectedCompletion = min(max(-1, selected), list.count - 1)
        if _completionPopUp == nil, let w = window {
            let anchor = w.convertToScreen(convert(cell._textRect(forBounds: _cellFrame), to: nil))
            _completionPopUp = _NSTokenCompletionPopUp(field: self, anchor: anchor)
        }
        _completionPopUp?.reload()
    }

    @MainActor internal func _closeCompletions() {
        _completionTimer?.invalidate()
        _completionTimer = nil
        _completions = []
        _selectedCompletion = -1
        _completionPopUp?.close()
        _completionPopUp = nil
    }

    @MainActor internal func _selectCompletion(_ i: Int) {
        guard _completions.indices.contains(i) else { return }
        _selectedCompletion = i
        _completionPopUp?.reload()
    }

    /// Takes a completion as the token (through the delegate's represented object).
    @MainActor internal func _acceptCompletion(_ i: Int) {
        guard _completions.indices.contains(i), let cell = _tokenCell, let e = _editor else { return }
        let chosen = _completions[i]
        _closeCompletions()
        let string = (chosen as? String) ?? cell._displayString(for: chosen)
        if let obj = cell._represented(for: string) { _addTokens([obj]) }
        e.string = ""
        _relayoutEditor()
        needsDisplay = true
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfield/completiondelay
    @MainActor open var completionDelay: TimeInterval {
        get { _tokenCell?.completionDelay ?? 0 }
        set { _tokenCell?.completionDelay = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfield/defaultcompletiondelay
    @MainActor class public var defaultCompletionDelay: TimeInterval { NSTokenFieldCell.defaultCompletionDelay }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfield/defaulttokenizingcharacterset
    @MainActor class public var defaultTokenizingCharacterSet: CharacterSet { NSTokenFieldCell.defaultTokenizingCharacterSet }
    // SKIPPED (override type (any NSTokenFieldDelegate)? differs from superclass (any NSTextFieldDelegate)?): @MainActor var delegate: (any NSTokenFieldDelegate)? { get set }
    // NSTokenFieldDelegate refines NSTextFieldDelegate, so a token field delegate is assigned to `delegate` as is.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfield/tokenstyle
    @MainActor open var tokenStyle: NSTokenField.TokenStyle {
        get { _tokenCell?.tokenStyle ?? .default }
        set { _tokenCell?.tokenStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstokenfield/tokenizingcharacterset
    @MainActor open var tokenizingCharacterSet: CharacterSet! {
        get { _tokenCell?.tokenizingCharacterSet }
        set { _tokenCell?.tokenizingCharacterSet = newValue }
    }
    // MARK: Accessibility (ADR-0013)
    //
    // An AXTextField whose value is the tokens' text; setting it tokenizes the string.
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : stringValue }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard isEditable, isEnabled else { return false }
        _closeCompletions()
        if let e = _editor { e.string = "" }
        stringValue = value.stringValue
        _relayoutEditor()
        _fireAction()
        return true
    }
}


// MARK: - The completion list

/// The borderless window the completions show in. Like a menu window it never becomes
/// key: the token field's window keeps the keyboard and the field routes Up, Down,
/// Return and Escape here through its editor.
@MainActor
final class _NSTokenCompletionWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isReleasedWhenClosed = false
        hasShadow = true
    }
    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The list itself: one row per completion, the selected one highlighted; a click takes a row.
@MainActor
final class _NSTokenCompletionListView: NSView {
    weak var field: NSTokenField?
    static let rowHeight: CGFloat = 20
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        guard let field else { return }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for (i, c) in field._completions.enumerated() {
            let r = NSRect(x: 1, y: 1 + CGFloat(i) * _NSTokenCompletionListView.rowHeight, width: bounds.width - 2, height: _NSTokenCompletionListView.rowHeight)
            let selected = i == field._selectedCompletion
            if selected {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 0), xRadius: 4, yRadius: 4).fill()
            }
            let text = (c as? String) ?? field._tokenCell?._displayString(for: c) ?? String(describing: c)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: selected ? NSColor.alternateSelectedControlTextColor : NSColor.controlTextColor]
            let size = text.size(withAttributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.clip(to: r)
            text.draw(at: NSPoint(x: r.minX + 8, y: r.midY - size.height / 2), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    /// The row under a point of the view.
    func row(at p: NSPoint) -> Int {
        let i = Int(((p.y - 1) / _NSTokenCompletionListView.rowHeight).rounded(.down))
        return (field?._completions.indices.contains(i) ?? false) ? i : -1
    }
    override func mouseDown(with event: NSEvent) {
        let i = row(at: convert(event.locationInWindow, from: nil))
        if i >= 0 { field?._selectCompletion(i) }
    }
    override func mouseUp(with event: NSEvent) {
        let i = row(at: convert(event.locationInWindow, from: nil))
        if i >= 0 { field?._acceptCompletion(i) }
    }
}

/// One open completion list: the window under the field's text.
@MainActor
final class _NSTokenCompletionPopUp {
    private weak var field: NSTokenField?
    let window: _NSTokenCompletionWindow
    let list: _NSTokenCompletionListView
    private let anchor: NSRect
    static let maxRows = 8

    init(field: NSTokenField, anchor: NSRect) {
        self.field = field
        self.anchor = anchor
        window = _NSTokenCompletionWindow(contentRect: NSRect(origin: anchor.origin, size: NSSize(width: max(anchor.width, 160), height: 40)))
        list = _NSTokenCompletionListView(frame: .zero)
        list.field = field
        window.contentView = list
    }

    /// Sizes the window to the rows (at most eight) and places it under the field's text
    /// (above it when the screen has no room below), then shows it.
    func reload() {
        guard let field else { return }
        let rows = min(_NSTokenCompletionPopUp.maxRows, field._completions.count)
        let height = CGFloat(rows) * _NSTokenCompletionListView.rowHeight + 2
        let width = max(anchor.width, 160)
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - height - 2)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.y < visible.minY, anchor.maxY + height <= visible.maxY { origin.y = anchor.maxY + 2 }
            if origin.x + width > visible.maxX { origin.x = max(visible.minX, visible.maxX - width) }
        }
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
        list.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        list.needsDisplay = true
        if !window.isVisible { window.orderFront(nil) }
    }

    func close() { window.close() }
}
