// NSText (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext
@MainActor open class NSText: NSView, NSChangeSpelling, NSIgnoreMisspelledWords {
    // MARK: Storage
    internal var _string = ""
    private var _selectedRange = NSRange(location: 0, length: 0)      // UTF-16 offsets
    private var _font: NSFont? = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private var _textColor: NSColor? = .textColor
    private var _backgroundColor: NSColor? = .textBackgroundColor
    private var _drawsBackground = true
    private var _isEditable = true
    private var _isSelectable = true
    private var _isFieldEditor = false
    private var _isRichText = false
    private var _importsGraphics = false
    private var _usesFontPanel = true
    private var _alignment: NSTextAlignment = .natural
    private var _baseWritingDirection: NSWritingDirection = .natural
    internal weak var _textDelegate: (any NSTextDelegate)? = nil
    private var _minSize = NSSize.zero
    private var _maxSize = NSSize(width: 10_000_000, height: 10_000_000)
    private var _isHorizontallyResizable = false
    private var _isVerticallyResizable = true
    /// True between `textDidBeginEditing` and `textDidEndEditing`.
    internal var _isEditingSession = false
    internal var _selectionAnchor: Int? = nil
    /// Input-method composition in progress (drawn underlined).
    internal var _markedRange: NSRange? = nil
    internal var _markedSelection = NSRange(location: 0, length: 0)
    internal var _clickCount = 0
    /// Horizontal scroll of the content for single-line field editors.
    internal var _scrollX: CGFloat = 0

    open override var isFlipped: Bool { true }
    open override var acceptsFirstResponder: Bool { _isEditable || _isSelectable }
    open override var isOpaque: Bool { _drawsBackground && (_backgroundColor?.alphaComponent ?? 0) >= 1 }

    // MARK: Text model (UTF-16 offsets, as NSRange)

    internal var _units: [UInt16] { Array(_string.utf16) }
    internal var _length: Int { _string.utf16.count }

    internal func _clamped(_ r: NSRange) -> NSRange {
        let n = _length
        let loc = min(max(0, r.location), n)
        return NSRange(location: loc, length: min(max(0, r.length), n - loc))
    }

    internal func _substring(_ r: NSRange) -> String {
        let c = _clamped(r)
        return String(decoding: _units[c.location..<(c.location + c.length)], as: UTF16.self)
    }

    /// Replaces `range` and moves the selection after the inserted text.
    internal func _replace(_ range: NSRange, with text: String, notify: Bool = true) {
        let r = _clamped(range)
        var units = _units
        units.replaceSubrange(r.location..<(r.location + r.length), with: Array(text.utf16))
        _string = String(decoding: units, as: UTF16.self)
        _selectedRange = NSRange(location: r.location + text.utf16.count, length: 0)
        _markedRange = nil
        _invalidateLayout()
        if notify { _noteDidChange() }
        _scrollSelectionIntoView()
        needsDisplay = true
    }

    internal func _noteDidChange() {
        let n = Notification(name: NSText.didChangeNotification, object: self)
        NotificationCenter.default.post(n)
        _textDelegate?.textDidChange(n)
    }

    // MARK: Layout (lines of UTF-16 ranges)

    internal struct _Line { var range: NSRange; var y: CGFloat; var width: CGFloat; var endsWithNewline: Bool }
    private var _lines: [_Line]? = nil

    internal var _attributes: [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: _effectiveFont]
        a[.foregroundColor] = _textColor ?? NSColor.textColor
        return a
    }
    internal var _effectiveFont: NSFont { _font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize) }
    internal var _lineHeight: CGFloat { let f = _effectiveFont; return (f.ascender - f.descender + f.leading).rounded(.up) }
    internal var _contentInset: NSSize { _isFieldEditor ? NSSize(width: 0, height: 0) : NSSize(width: 5, height: 0) }
    internal var _wrapWidth: CGFloat? {
        if _isFieldEditor || _isHorizontallyResizable { return nil }
        return max(1, bounds.width - 2 * _contentInset.width)
    }

    internal func _invalidateLayout() { _lines = nil }

    internal func _width(_ r: NSRange) -> CGFloat {
        let s = _substring(r)
        return s.isEmpty ? 0 : s.size(withAttributes: _attributes).width
    }

    internal func _layoutLines() -> [_Line] {
        if let l = _lines { return l }
        var lines: [_Line] = []
        let units = _units
        let n = units.count
        let lh = _lineHeight
        var start = 0
        var y = _contentInset.height
        func emit(_ range: NSRange, newline: Bool) {
            lines.append(_Line(range: range, y: y, width: _width(range), endsWithNewline: newline))
            y += lh
        }
        while start <= n {
            var end = start
            while end < n && units[end] != 0x0A { end += 1 }
            let hasNewline = end < n
            let paragraph = NSRange(location: start, length: end - start)
            if let wrap = _wrapWidth, _width(paragraph) > wrap, paragraph.length > 0 {
                // Word wrap: fill each line greedily, breaking at spaces when possible.
                var lineStart = paragraph.location
                while lineStart < end {
                    var lineEnd = lineStart + 1
                    var lastSpace: Int? = nil
                    while lineEnd <= end {
                        if _width(NSRange(location: lineStart, length: lineEnd - lineStart)) > wrap { break }
                        if lineEnd < end && units[lineEnd] == 0x20 { lastSpace = lineEnd + 1 }
                        lineEnd += 1
                    }
                    var cut = lineEnd - 1
                    if cut <= lineStart { cut = lineStart + 1 }
                    if lineEnd <= end, let sp = lastSpace, sp > lineStart, cut < end { cut = sp }
                    if lineEnd > end { cut = end }
                    emit(NSRange(location: lineStart, length: cut - lineStart), newline: cut == end && hasNewline)
                    lineStart = cut
                }
            } else {
                emit(paragraph, newline: hasNewline)
            }
            start = end + 1
        }
        _lines = lines
        return lines
    }

    internal func _line(containing offset: Int) -> Int {
        let lines = _layoutLines()
        for (i, l) in lines.enumerated() {
            let end = l.range.location + l.range.length
            if offset < end || (offset == end && (l.endsWithNewline == false || i == lines.count - 1)) { return i }
            if offset == end && !l.endsWithNewline { return i }
        }
        return max(0, lines.count - 1)
    }

    /// Left x of a line for the alignment.
    internal func _lineX(_ line: _Line) -> CGFloat {
        let avail = bounds.width - 2 * _contentInset.width
        switch _alignment {
        case .center: return _contentInset.width + max(0, (avail - line.width) / 2) - _scrollX
        case .right: return _contentInset.width + max(0, avail - line.width) - _scrollX
        default: return _contentInset.width - _scrollX
        }
    }

    /// Caret rectangle for an offset, in bounds coordinates (flipped).
    internal func _caretRect(for offset: Int) -> NSRect {
        let lines = _layoutLines()
        guard !lines.isEmpty else { return NSRect(x: _contentInset.width, y: _contentInset.height, width: 1, height: _lineHeight) }
        let i = _line(containing: offset)
        let l = lines[i]
        let x = _lineX(l) + _width(NSRange(location: l.range.location, length: max(0, min(offset, l.range.location + l.range.length) - l.range.location)))
        return NSRect(x: x, y: l.y, width: 1, height: _lineHeight)
    }

    /// Nearest character offset to a point in bounds coordinates.
    internal func _offset(at point: NSPoint) -> Int {
        let lines = _layoutLines()
        guard !lines.isEmpty else { return 0 }
        var li = 0
        for (i, l) in lines.enumerated() where point.y >= l.y { li = i }
        let l = lines[li]
        let x0 = _lineX(l)
        var best = l.range.location
        var bestDistance = CGFloat.infinity
        for k in 0...l.range.length {
            let d = abs(x0 + _width(NSRange(location: l.range.location, length: k)) - point.x)
            if d < bestDistance { bestDistance = d; best = l.range.location + k }
        }
        return best
    }

    internal var _contentSize: NSSize {
        let lines = _layoutLines()
        let w = (lines.map(\.width).max() ?? 0) + 2 * _contentInset.width
        let h = CGFloat(max(1, lines.count)) * _lineHeight + 2 * _contentInset.height
        return NSSize(width: w, height: h)
    }

    /// Keeps the caret visible in single-line field editors by scrolling horizontally.
    internal func _scrollSelectionIntoView() {
        guard _isFieldEditor else { return }
        let caret = _caretRect(for: _selectedRange.location + _selectedRange.length)
        let visibleRight = bounds.width - _contentInset.width
        if caret.minX > visibleRight { _scrollX += caret.minX - visibleRight }
        else if caret.minX < _contentInset.width { _scrollX = max(0, _scrollX - (_contentInset.width - caret.minX)) }
        if _scrollX > 0 { _scrollX = min(_scrollX, max(0, _contentSize.width - bounds.width)) }
    }

    // MARK: Editing session

    internal func _beginEditingIfNeeded() {
        guard _isEditable, !_isEditingSession else { return }
        if let d = _textDelegate, !d.textShouldBeginEditing(self) { return }
        _isEditingSession = true
        let n = Notification(name: NSText.didBeginEditingNotification, object: self)
        NotificationCenter.default.post(n)
        _textDelegate?.textDidBeginEditing(n)
    }

    /// Ends the session; returns false when the delegate refuses.
    @discardableResult
    internal func _endEditing(movement: NSTextMovement) -> Bool {
        guard _isEditingSession else { return true }
        if let d = _textDelegate, !d.textShouldEndEditing(self) { return false }
        _isEditingSession = false
        _markedRange = nil
        let n = Notification(name: NSText.didEndEditingNotification, object: self, userInfo: ["NSTextMovement": movement.rawValue])
        NotificationCenter.default.post(n)
        _textDelegate?.textDidEndEditing(n)
        return true
    }

    open override func becomeFirstResponder() -> Bool {
        guard acceptsFirstResponder else { return false }
        _beginEditingIfNeeded()
        needsDisplay = true
        return true
    }

    open override func resignFirstResponder() -> Bool {
        guard _endEditing(movement: .other) else { return false }
        needsDisplay = true
        return true
    }

    open override func resetCursorRects() {
        if _isEditable || _isSelectable { addCursorRect(bounds, cursor: .iBeam) }
    }

    // MARK: Mouse

    open override func mouseDown(with event: NSEvent) {
        guard _isEditable || _isSelectable else { super.mouseDown(with: event); return }
        if window?.firstResponder !== self { _ = window?.makeFirstResponder(self) }
        let p = convert(event.locationInWindow, from: nil)
        let offset = _offset(at: p)
        _clickCount = event.clickCount
        switch event.clickCount {
        case 2: selectedRange = _wordRange(at: offset); _selectionAnchor = nil
        case 3: selectedRange = _lineRange(at: offset); _selectionAnchor = nil
        default:
            if event.modifierFlags.contains(.shift), let a = _selectionAnchor ?? Optional(_selectedRange.location) {
                selectedRange = NSRange(location: min(a, offset), length: abs(offset - a))
                _selectionAnchor = a
            } else {
                selectedRange = NSRange(location: offset, length: 0)
                _selectionAnchor = offset
            }
        }
    }

    open override func mouseDragged(with event: NSEvent) {
        guard _clickCount == 1, let anchor = _selectionAnchor else { return }
        let p = convert(event.locationInWindow, from: nil)
        let offset = _offset(at: p)
        selectedRange = NSRange(location: min(anchor, offset), length: abs(offset - anchor))
    }

    internal func _wordRange(at offset: Int) -> NSRange {
        let units = _units
        guard !units.isEmpty else { return NSRange(location: 0, length: 0) }
        func isWord(_ u: UInt16) -> Bool { let s = UnicodeScalar(u).map { Character($0) }; return s.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false }
        var start = min(offset, units.count), end = start
        if start < units.count && isWord(units[start]) || (start == units.count || !isWord(units[start])) && start > 0 && isWord(units[start - 1]) {
            if !(start < units.count && isWord(units[start])) { start -= 1; end = start }
            while start > 0 && isWord(units[start - 1]) { start -= 1 }
            while end < units.count && isWord(units[end]) { end += 1 }
        } else if start < units.count {
            end = start + 1
        }
        return NSRange(location: start, length: end - start)
    }

    internal func _lineRange(at offset: Int) -> NSRange {
        let lines = _layoutLines()
        guard !lines.isEmpty else { return NSRange(location: 0, length: 0) }
        return lines[_line(containing: offset)].range
    }

    // MARK: Drawing

    open override func draw(_ dirtyRect: NSRect) {
        if _drawsBackground, let bg = _backgroundColor {
            bg.setFill()
            NSBezierPath.fill(bounds)
        }
        let lines = _layoutLines()
        let lh = _lineHeight
        let focused = window?.firstResponder === self
        let sel = _clamped(_selectedRange)
        for l in lines {
            let x = _lineX(l)
            // Selection highlight over this line's part of the selection.
            if sel.length > 0 {
                let a = max(sel.location, l.range.location), b = min(sel.location + sel.length, l.range.location + l.range.length + (l.endsWithNewline ? 1 : 0))
                if b > a || (sel.location <= l.range.location && sel.location + sel.length > l.range.location + l.range.length) {
                    let x0 = x + _width(NSRange(location: l.range.location, length: max(0, a - l.range.location)))
                    let x1 = x + _width(NSRange(location: l.range.location, length: max(0, min(b, l.range.location + l.range.length) - l.range.location))) + (b > l.range.location + l.range.length ? 4 : 0)
                    (focused ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
                    NSBezierPath.fill(NSRect(x: x0, y: l.y, width: max(0, x1 - x0), height: lh))
                }
            }
            if l.range.length > 0 {
                _substring(l.range).draw(at: NSPoint(x: x, y: l.y), withAttributes: _attributes)
            }
            // Marked (composing) text: underline.
            if let m = _markedRange, m.length > 0 {
                let a = max(m.location, l.range.location), b = min(m.location + m.length, l.range.location + l.range.length)
                if b > a {
                    let x0 = x + _width(NSRange(location: l.range.location, length: a - l.range.location))
                    let x1 = x + _width(NSRange(location: l.range.location, length: b - l.range.location))
                    (_textColor ?? .textColor).setFill()
                    NSBezierPath.fill(NSRect(x: x0, y: l.y + lh - 2, width: x1 - x0, height: 1))
                }
            }
        }
        if focused && _isEditable && sel.length == 0 {
            let caret = _caretRect(for: sel.location)
            (_textColor ?? .textColor).setFill()
            NSBezierPath.fill(NSRect(x: caret.minX.rounded(), y: caret.minY, width: 1, height: caret.height))
        }
    }

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _invalidateLayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/init(coder:)
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/aligncenter(_:)
    @MainActor open func alignCenter(_ sender: Any?) { alignment = .center }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/alignleft(_:)
    @MainActor open func alignLeft(_ sender: Any?) { alignment = .left }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/alignright(_:)
    @MainActor open func alignRight(_ sender: Any?) { alignment = .right }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/alignment
    @MainActor open var alignment: NSTextAlignment {
        get { _alignment }
        set { _alignment = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/backgroundcolor
    @MainActor open var backgroundColor: NSColor? {
        get { _backgroundColor }
        set { _backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/basewritingdirection
    @MainActor open var baseWritingDirection: NSWritingDirection {
        get { _baseWritingDirection }
        set { _baseWritingDirection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/changefont(_:)
    @MainActor open func changeFont(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/checkspelling(_:)
    @MainActor open func checkSpelling(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/copy(_:)
    @MainActor open func copy(_ sender: Any?) {
        let sel = _clamped(_selectedRange)
        guard sel.length > 0 else { return }
        let pb = NSPasteboard.general
        _ = pb.clearContents()
        _ = pb.setString(_substring(sel), forType: .string)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/copyfont(_:)
    @MainActor open func copyFont(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/copyruler(_:)
    @MainActor open func copyRuler(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/cut(_:)
    @MainActor open func cut(_ sender: Any?) {
        guard _isEditable, _clamped(_selectedRange).length > 0 else { return }
        copy(sender)
        delete(sender)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/delegate
    @MainActor open var delegate: (any NSTextDelegate)? {
        get { _textDelegate }
        set { _textDelegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/delete(_:)
    @MainActor open func delete(_ sender: Any?) {
        guard _isEditable else { return }
        let sel = _clamped(_selectedRange)
        guard sel.length > 0 else { return }
        _replace(sel, with: "")
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/didbegineditingnotification
    static public var didBeginEditingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextDidBeginEditingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/didchangenotification
    static public var didChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/didendeditingnotification
    static public var didEndEditingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSTextDidEndEditingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _drawsBackground }
        set { _drawsBackground = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/font
    @MainActor open var font: NSFont? {
        get { _font }
        set { _font = newValue; _invalidateLayout(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/importsgraphics
    @MainActor open var importsGraphics: Bool {
        get { _importsGraphics }
        set { _importsGraphics = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/iseditable
    @MainActor open var isEditable: Bool {
        get { _isEditable }
        set { _isEditable = newValue; if newValue { _isSelectable = true }; window?.invalidateCursorRects(for: self) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/isfieldeditor
    @MainActor open var isFieldEditor: Bool {
        get { _isFieldEditor }
        set { _isFieldEditor = newValue; _invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/ishorizontallyresizable
    @MainActor open var isHorizontallyResizable: Bool {
        get { _isHorizontallyResizable }
        set { _isHorizontallyResizable = newValue; _invalidateLayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/isrichtext
    @MainActor open var isRichText: Bool {
        get { _isRichText }
        set { _isRichText = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/isrulervisible
    @MainActor open var isRulerVisible: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/isselectable
    @MainActor open var isSelectable: Bool {
        get { _isSelectable }
        set { _isSelectable = newValue; if !newValue { _isEditable = false } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/isverticallyresizable
    @MainActor open var isVerticallyResizable: Bool {
        get { _isVerticallyResizable }
        set { _isVerticallyResizable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/maxsize
    @MainActor open var maxSize: NSSize {
        get { _maxSize }
        set { _maxSize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/minsize
    @MainActor open var minSize: NSSize {
        get { _minSize }
        set { _minSize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/movementuserinfokey
    @available(macOS 10.13, *)
    static public var movementUserInfoKey: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/paste(_:)
    @MainActor open func paste(_ sender: Any?) {
        guard _isEditable, var text = NSPasteboard.general.string(forType: .string) else { return }
        if _isFieldEditor { text = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ") }
        _replace(_selectedRange, with: text)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/pastefont(_:)
    @MainActor open func pasteFont(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/pasteruler(_:)
    @MainActor open func pasteRuler(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/readrtfd(fromfile:)
    @MainActor open func readRTFD(fromFile path: String) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/replacecharacters(in:with:)
    @MainActor open func replaceCharacters(in range: NSRange, with string: String) { _replace(range, with: string) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/replacecharacters(in:withrtf:)
    @MainActor open func replaceCharacters(in range: NSRange, withRTF rtfData: Data) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/replacecharacters(in:withrtfd:)
    @MainActor open func replaceCharacters(in range: NSRange, withRTFD rtfdData: Data) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/rtf(from:)
    @MainActor open func rtf(from range: NSRange) -> Data? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/rtfd(from:)
    @MainActor open func rtfd(from range: NSRange) -> Data? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/scrollrangetovisible(_:)
    @MainActor open func scrollRangeToVisible(_ range: NSRange) {
        let r = _caretRect(for: _clamped(range).location)
        _ = scrollToVisible(r)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/selectall(_:)
    @MainActor open func selectAll(_ sender: Any?) { selectedRange = NSRange(location: 0, length: _length) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/selectedrange
    @MainActor open var selectedRange: NSRange {
        get { _clamped(_selectedRange) }
        set {
            _selectedRange = _clamped(newValue)
            _scrollSelectionIntoView()
            _selectionDidChange()
            needsDisplay = true
        }
    }

    /// Subclasses (NSTextView) post their selection notification here.
    internal func _selectionDidChange() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/setfont(_:range:)
    @MainActor open func setFont(_ font: NSFont, range: NSRange) { self.font = font }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/settextcolor(_:range:)
    @MainActor open func setTextColor(_ color: NSColor?, range: NSRange) { textColor = color }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/showguesspanel(_:)
    @MainActor open func showGuessPanel(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/sizetofit()
    @MainActor open func sizeToFit() {
        let s = _contentSize
        setFrameSize(NSSize(width: _isHorizontallyResizable ? max(_minSize.width, min(_maxSize.width, s.width)) : frame.width,
                            height: _isVerticallyResizable ? max(_minSize.height, min(_maxSize.height, s.height)) : frame.height))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/string
    @MainActor open var string: String {
        get { _string }
        set {
            _string = newValue
            _selectedRange = NSRange(location: 0, length: 0)
            _markedRange = nil
            _scrollX = 0
            _invalidateLayout()
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/subscript(_:)
    @MainActor open func `subscript`(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/superscript(_:)
    @MainActor open func superscript(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/textcolor
    @MainActor open var textColor: NSColor? {
        get { _textColor }
        set { _textColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/toggleruler(_:)
    @MainActor open func toggleRuler(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/underline(_:)
    @MainActor open func underline(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/unscript(_:)
    @MainActor open func unscript(_ sender: Any?) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/usesfontpanel
    @MainActor open var usesFontPanel: Bool {
        get { _usesFontPanel }
        set { _usesFontPanel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstext/writertfd(tofile:atomically:)
    @MainActor open func writeRTFD(toFile path: String, atomically flag: Bool) -> Bool { unimplemented() }
    // Requirement of NSChangeSpelling
    open func changeSpelling(_ sender: Any?) { }
    // Requirement of NSIgnoreMisspelledWords
    open func ignoreSpelling(_ sender: Any?) { }
}
