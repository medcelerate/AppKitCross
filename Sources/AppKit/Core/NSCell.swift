// NSCell (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() say why (ADR-0038).
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell
@MainActor open class NSCell: NSObject, NSCopying, NSCoding, NSUserInterfaceItemIdentification, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    // MARK: Storage
    internal var _objectValue: Any? = nil
    internal var _image: NSImage? = nil
    /// The text a title drawing last put on screen (`_drawTruncatingText`), for tests.
    internal var _lastDrawnTitle: String? = nil
    internal var _state: NSControl.StateValue = .off
    internal var _isEnabled = true
    internal var _isHighlighted = false
    internal var _font: NSFont? = nil
    internal var _alignment: NSTextAlignment = .natural
    internal var _type: NSCell.CellType = .textCellType
    internal var _controlSize: NSControl.ControlSize = .regular
    internal var _isBordered = false
    internal var _isBezeled = false
    internal var _isEditable = false
    internal var _isSelectable = false
    internal var _isScrollable = false
    internal var _isContinuous = false
    internal var _wraps = false
    internal var _tag = 0
    internal var _lineBreakMode: NSLineBreakMode = .byWordWrapping
    internal weak var _controlView: NSView?
    internal var _representedObject: Any? = nil
    internal var _formatter: Formatter? = nil
    internal var _allowsMixedState = false
    internal var _backgroundStyle: NSView.BackgroundStyle = .normal
    internal var _truncatesLastVisibleLine = false
    internal var _usesSingleLineMode = false
    internal var _focusRingType: NSFocusRingType = .default
    internal var _refusesFirstResponder = false
    internal var _showsFirstResponder = true
    internal var _baseWritingDirection: NSWritingDirection = .natural
    internal var _menu: NSMenu? = nil
    internal var _sendActionMask: Int = Int(NSEvent.EventTypeMask.leftMouseUp.rawValue)
    internal var _allowsUndo = true
    internal var _allowsEditingTextAttributes = false
    internal var _importsGraphics = false
    internal var _controlTint: NSControlTint = .defaultControlTint
    internal var _sendsActionOnEndEditing = false
    internal var _userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection = .leftToRight
    internal var _wantsNotificationForMarkedText = false

    /// Marks the control view dirty after a value change.
    internal func _changed() { _controlView?.needsDisplay = true }

    /// Font actually used for drawing.
    internal var _effectiveFont: NSFont { _font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: _controlSize)) }

    internal var _textColor: NSColor { _isEnabled ? .controlTextColor : .disabledControlTextColor }

    internal var _textAttributes: [NSAttributedString.Key: Any] { [.font: _effectiveFont, .foregroundColor: _textColor] }

    open override var description: String { MainActor.assumeIsolated { "<\(Swift.type(of: self)) '\(stringValue)'>" } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/init()
    /// A null cell (`.nullCellType`) with no value; macOS 15 reports allowsEditingTextAttributes
    /// true for it (and false for a text cell).
    @MainActor public override init() {
        super.init()
        _type = .nullCellType
        _allowsEditingTextAttributes = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/init(coder:)
    @MainActor public required init(coder: NSCoder) { super.init() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/init(imagecell:)
    @MainActor public init(imageCell image: NSImage?) {
        super.init()
        _image = image
        _type = .imageCellType
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/init(textcell:)
    @MainActor public init(textCell string: String) {
        super.init()
        _objectValue = string
        _type = .textCellType
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/acceptsfirstresponder
    @MainActor open var acceptsFirstResponder: Bool { !_refusesFirstResponder }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/action
    @MainActor open var action: Selector? {
        get { nil }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/alignment
    @MainActor open var alignment: NSTextAlignment {
        get { _alignment }
        set { _alignment = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/allowseditingtextattributes
    /// Stored; the field editor is rich text while it is set (`setUpFieldEditorAttributes`).
    @MainActor open var allowsEditingTextAttributes: Bool {
        get { _allowsEditingTextAttributes }
        set { _allowsEditingTextAttributes = newValue; if !newValue { _importsGraphics = false } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/allowsmixedstate
    @MainActor open var allowsMixedState: Bool {
        get { _allowsMixedState }
        set { _allowsMixedState = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/allowsundo
    /// Stored (default true); handed to the field editor in `setUpFieldEditorAttributes`.
    @MainActor open var allowsUndo: Bool {
        get { _allowsUndo }
        set { _allowsUndo = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/attributedstringvalue
    @MainActor open var attributedStringValue: NSAttributedString {
        get { (_objectValue as? NSAttributedString) ?? NSAttributedString(string: stringValue, attributes: _textAttributes) }
        set { _objectValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/backgroundstyle
    @MainActor open var backgroundStyle: NSView.BackgroundStyle {
        get { _backgroundStyle }
        set { _backgroundStyle = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/basewritingdirection
    @MainActor open var baseWritingDirection: NSWritingDirection {
        get { _baseWritingDirection }
        set { _baseWritingDirection = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/calcdrawinfo(_:)
    @MainActor open func calcDrawInfo(_ rect: NSRect) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/cellattribute(_:)
    @MainActor open func cellAttribute(_ parameter: NSCell.Attribute) -> Int {
        switch parameter {
        case .cellDisabled: return _isEnabled ? 0 : 1
        case .cellState: return _state.rawValue
        case .cellHighlighted: return _isHighlighted ? 1 : 0
        case .cellEditable: return _isEditable ? 1 : 0
        default: return 0
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/cellsize
    @MainActor open var cellSize: NSSize {
        var s = stringValue.isEmpty ? NSSize(width: 0, height: _effectiveFont.ascender - _effectiveFont.descender) : stringValue.size(withAttributes: _textAttributes)
        s.width += 4; s.height += 2
        if _isBordered || _isBezeled { s.width += 4; s.height += 4 }
        return s
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/cellsize(forbounds:)
    @MainActor open func cellSize(forBounds rect: NSRect) -> NSSize { cellSize }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/compare(_:)
    @MainActor open func compare(_ otherCell: Any) -> ComparisonResult { stringValue.compare((otherCell as? NSCell)?.stringValue ?? "") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/continuetracking(last:current:in:)
    @MainActor open func continueTracking(last lastPoint: NSPoint, current currentPoint: NSPoint, in controlView: NSView) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/controlsize
    @MainActor open var controlSize: NSControl.ControlSize {
        get { _controlSize }
        set { _controlSize = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/controltint
    /// Stored (default `.defaultControlTint`); the port's controls draw with the accent colour.
    @MainActor open var controlTint: NSControlTint {
        get { _controlTint }
        set { _controlTint = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/controlview
    @MainActor open var controlView: NSView? {
        get { _controlView }
        set { _controlView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/defaultfocusringtype
    @MainActor class public var defaultFocusRingType: NSFocusRingType { NSFocusRingType(rawValue: 2)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/defaultmenu
    /// Nil: a cell has no default contextual menu (macOS).
    @MainActor class public var defaultMenu: NSMenu? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/doublevalue
    @MainActor open var doubleValue: Double {
        get {
            if let d = _objectValue as? Double { return d }
            if let n = _objectValue as? Int { return Double(n) }
            if let s = _objectValue as? String { return Double(s) ?? 0 }
            return 0
        }
        set { objectValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/draggingimagecomponents(withframe:in:)
    /// An icon component (the cell as drawn) and, for a text cell, a label component (its
    /// text), each covering `frame` (macOS gives both the whole frame). The images draw the
    /// cell when the drag image is composed, not now.
    @MainActor open func draggingImageComponents(withFrame frame: NSRect, in view: NSView) -> [NSDraggingImageComponent] {
        let bounds = NSRect(origin: .zero, size: frame.size)
        let flipped = view.isFlipped
        let icon = NSDraggingImageComponent(key: .icon)
        icon.frame = frame
        icon.contents = NSImage(size: frame.size, flipped: flipped) { [weak self, weak view] _ in
            guard let self, let view else { return false }
            if self._type == .textCellType { if let image = self._image { image.draw(in: self.imageRect(forBounds: bounds)) } } else { self.draw(withFrame: bounds, in: view) }
            return true
        }
        guard _type == .textCellType else { return [icon] }
        let label = NSDraggingImageComponent(key: .label)
        label.frame = frame
        label.contents = NSImage(size: frame.size, flipped: flipped) { [weak self, weak view] _ in
            guard let self, let view else { return false }
            self.drawInterior(withFrame: bounds, in: view)
            return true
        }
        return [icon, label]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/draw(withexpansionframe:in:)
    /// Draws the cell in the expansion tool tip's frame (`draw(withFrame:in:)`).
    @MainActor open func draw(withExpansionFrame cellFrame: NSRect, in view: NSView) { draw(withFrame: cellFrame, in: view) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/draw(withframe:in:)
    @MainActor open func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        if _isBezeled || _isBordered {
            NSColor.textBackgroundColor.setFill()
            NSBezierPath.fill(cellFrame)
            NSColor.separatorColor.setStroke()
            NSBezierPath.stroke(cellFrame.insetBy(dx: 0.5, dy: 0.5))
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/drawfocusringmask(withframe:in:)
    /// Fills `focusRingMaskBounds` (empty for a plain cell, so nothing is drawn).
    @MainActor open func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        let r = focusRingMaskBounds(forFrame: cellFrame, in: controlView)
        guard !r.isEmpty else { return }
        NSColor.black.setFill()
        NSBezierPath.fill(r)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/drawinterior(withframe:in:)
    @MainActor open func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard _type == .textCellType, !stringValue.isEmpty else { return }
        let rect = titleRect(forBounds: cellFrame)
        _drawText(stringValue, attributes: _textAttributes, in: rect, alignment: _alignment, flipped: controlView.isFlipped)
    }

    /// Draws single-line text vertically centred in `rect` with horizontal `alignment`.
    @MainActor internal func _drawText(_ text: String, attributes: [NSAttributedString.Key: Any], in rect: NSRect, alignment: NSTextAlignment, flipped: Bool) {
        let size = text.size(withAttributes: attributes)
        var x = rect.minX
        switch alignment {
        case .center: x = rect.midX - size.width / 2
        case .right: x = rect.maxX - size.width
        case .natural, .justified: if _controlView?.userInterfaceLayoutDirection == .rightToLeft { x = rect.maxX - size.width }
        default: break
        }
        let yTop = flipped ? rect.midY - size.height / 2 : rect.midY + size.height / 2
        let origin = flipped ? NSPoint(x: x, y: yTop) : NSPoint(x: x, y: yTop - size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clip(to: rect)
        text.draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
    /// The text a title drawing last put on screen (`_drawTruncatingText`), for tests.
    /// Draws one line of `text` vertically centred in `rect` (`alignment` as `_drawText`),
    /// tail-truncated with an ellipsis when it is wider than the rect, as AppKit's button and
    /// pop-up titles are. The cut is made here, by measuring, rather than by a truncating
    /// paragraph style: the port's string drawing wraps inside a rect and ignores the line
    /// break mode, so the clipped second line took the tail with no "…" (Windows showed
    /// "Clear This Channel's" in a narrowed button).
    @MainActor internal func _drawTruncatingText(_ text: String, attributes: [NSAttributedString.Key: Any], in rect: NSRect, alignment: NSTextAlignment = .left, flipped: Bool) {
        let shown = NSCell._truncatedTail(text, attributes: attributes, width: rect.width)
        _lastDrawnTitle = shown
        _drawText(shown, attributes: attributes, in: rect, alignment: shown == text ? alignment : .left, flipped: flipped)
    }
    /// `text` cut at a character so that it and a trailing "…" fit `width` (trailing spaces
    /// before the ellipsis dropped); the text itself when it fits.
    @MainActor internal static func _truncatedTail(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> String {
        guard text.size(withAttributes: attributes).width > width + 0.5 else { return text }
        let ellipsis = "\u{2026}"
        let chars = Array(text)
        func candidate(_ n: Int) -> String {
            var head = String(chars[0..<n])
            while head.last?.isWhitespace == true { head.removeLast() }
            return head + ellipsis
        }
        // The longest prefix whose truncated form fits (widths grow with the prefix).
        var lo = 0, hi = chars.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if candidate(mid).size(withAttributes: attributes).width <= width + 0.5 { lo = mid } else { hi = mid - 1 }
        }
        return lo == 0 ? (ellipsis.size(withAttributes: attributes).width <= width + 0.5 ? ellipsis : "") : candidate(lo)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/drawingrect(forbounds:)
    @MainActor open func drawingRect(forBounds rect: NSRect) -> NSRect { (_isBordered || _isBezeled) ? rect.insetBy(dx: 2, dy: 2) : rect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/edit(withframe:in:editor:delegate:event:)
    /// Starts editing a text cell in `textObj` (normally the window's field editor): the
    /// editor is set up (`setUpFieldEditorAttributes`), takes the cell's text and font, is
    /// placed over `rect` in `controlView`, gets `delegate` and becomes first responder; a
    /// mouse-down `event` goes on to it, otherwise the insertion point is at the start (macOS).
    /// The cell's value is not updated until the control takes the editor's text.
    @MainActor open func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        _beginFieldEditor(textObj, frame: rect, in: controlView, delegate: delegate)
        if let event { textObj.mouseDown(with: event) } else { textObj.selectedRange = NSRange(location: 0, length: 0) }
    }

    @MainActor internal func _beginFieldEditor(_ textObj: NSText, frame rect: NSRect, in controlView: NSView, delegate: Any?) {
        guard _type == .textCellType else { return }
        _controlView = controlView
        let editor = setUpFieldEditorAttributes(textObj)
        editor.font = _effectiveFont
        if _allowsEditingTextAttributes, let tv = editor as? NSTextView, let storage = tv.textStorage {
            storage.setAttributedString(attributedStringValue)
        } else {
            editor.string = stringValue
        }
        editor.frame = rect
        editor.delegate = delegate as? NSTextDelegate
        if editor.superview !== controlView { controlView.addSubview(editor) }
        _ = controlView.window?.makeFirstResponder(editor)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/endediting(_:)
    /// Ends an editing session: the editor loses its delegate and first-responder status (the
    /// window takes it), leaves the view and is emptied. The cell keeps its value (macOS).
    @MainActor open func endEditing(_ textObj: NSText) {
        textObj.delegate = nil
        if let w = textObj.window, w.firstResponder === textObj { _ = w.makeFirstResponder(nil) }
        textObj.removeFromSuperview()
        textObj.string = ""
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/expansionframe(withframe:in:)
    /// Zero: a plain cell has no expansion tool tip (text field cells answer their own).
    @MainActor open func expansionFrame(withFrame cellFrame: NSRect, in view: NSView) -> NSRect { .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/fieldeditor(for:)
    /// Nil: the window's shared field editor is used (macOS's default).
    @MainActor open func fieldEditor(for controlView: NSView) -> NSTextView? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/floatvalue
    @MainActor open var floatValue: Float {
        get { Float(doubleValue) }
        set { objectValue = Double(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/focusringmaskbounds(forframe:in:)
    /// Zero for a plain cell (macOS); subclasses that draw a focus ring answer their shape.
    @MainActor open func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect { .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/focusringtype
    @MainActor open var focusRingType: NSFocusRingType {
        get { _focusRingType }
        set { _focusRingType = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/font
    @MainActor open var font: NSFont? {
        get { _font }
        set { _font = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/formatter
    @MainActor open var formatter: Formatter? {
        get { _formatter }
        set { _formatter = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/getperiodicdelay(_:interval:)
    /// 0.2 s before the first repeat, then every 0.025 s (macOS's values for a plain cell).
    @MainActor open func getPeriodicDelay(_ delay: UnsafeMutablePointer<Float>, interval: UnsafeMutablePointer<Float>) { delay.pointee = 0.2; interval.pointee = 0.025 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/hasvalidobjectvalue
    /// False only when a formatter cannot show the value it was given.
    @MainActor open var hasValidObjectValue: Bool {
        guard let f = _formatter, let v = _objectValue else { return true }
        return f.string(for: v) != nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/highlight(_:withframe:in:)
    @MainActor open func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) { isHighlighted = flag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/highlightcolor(withframe:in:)
    /// The secondary selection colour (macOS 15's answer for a plain or text field cell).
    @MainActor open func highlightColor(withFrame cellFrame: NSRect, in controlView: NSView) -> NSColor? { .secondarySelectedControlColor }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/hittest(for:in:of:)
    @MainActor open func hitTest(for event: NSEvent, in cellFrame: NSRect, of controlView: NSView) -> NSCell.HitResult { cellFrame.contains(controlView.convert(event.locationInWindow, from: nil)) ? .contentArea : [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/image
    @MainActor open var image: NSImage? {
        get { _image }
        set { _image = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/imagerect(forbounds:)
    @MainActor open func imageRect(forBounds rect: NSRect) -> NSRect { drawingRect(forBounds: rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/importsgraphics
    /// Stored; setting it also allows editing text attributes (AppKit).
    @MainActor open var importsGraphics: Bool {
        get { _importsGraphics }
        set { _importsGraphics = newValue; if newValue { _allowsEditingTextAttributes = true } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/intvalue
    @MainActor open var intValue: Int32 {
        get { Int32(truncatingIfNeeded: integerValue) }
        set { objectValue = Int(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/integervalue
    @MainActor open var integerValue: Int {
        get {
            if let n = _objectValue as? Int { return n }
            if let d = _objectValue as? Double { return Int(d) }
            if let s = _objectValue as? String { return Int(s) ?? Int(Double(s) ?? 0) }
            return 0
        }
        set { objectValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/interiorbackgroundstyle
    @MainActor open var interiorBackgroundStyle: NSView.BackgroundStyle { _backgroundStyle }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/isbezeled
    @MainActor open var isBezeled: Bool {
        get { _isBezeled }
        set { _isBezeled = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/isbordered
    @MainActor open var isBordered: Bool {
        get { _isBordered }
        set { _isBordered = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/iscontinuous
    @MainActor open var isContinuous: Bool {
        get { _isContinuous }
        set { _isContinuous = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/iseditable
    @MainActor open var isEditable: Bool {
        get { _isEditable }
        set { _isEditable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/isenabled
    @MainActor open var isEnabled: Bool {
        get { _isEnabled }
        set { _isEnabled = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/ishighlighted
    @MainActor open var isHighlighted: Bool {
        get { _isHighlighted }
        set { _isHighlighted = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/isopaque
    @MainActor open var isOpaque: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/isscrollable
    @MainActor open var isScrollable: Bool {
        get { _isScrollable }
        set { _isScrollable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/isselectable
    @MainActor open var isSelectable: Bool {
        get { _isSelectable }
        set { _isSelectable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/keyequivalent
    @MainActor open var keyEquivalent: String { "" }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/linebreakmode
    @MainActor open var lineBreakMode: NSLineBreakMode {
        get { _lineBreakMode }
        set { _lineBreakMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/menu
    @MainActor open var menu: NSMenu? {
        get { _menu }
        set { _menu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/menu(for:in:of:)
    /// The cell's menu (nil when it has none; `defaultMenu` is nil).
    @MainActor open func menu(for event: NSEvent, in cellFrame: NSRect, of view: NSView) -> NSMenu? { _menu ?? NSCell.defaultMenu }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/mousedownflags
    @MainActor open var mouseDownFlags: Int { 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/nextstate
    @MainActor open var nextState: Int {
        switch _state {
        case .on: return NSControl.StateValue.off.rawValue
        case .off: return (_allowsMixedState ? NSControl.StateValue.mixed : NSControl.StateValue.on).rawValue
        default: return NSControl.StateValue.on.rawValue
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/objectvalue
    @MainActor open var objectValue: Any? {
        get { _objectValue }
        set { _objectValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/performclick(_:)
    @MainActor open func performClick(_ sender: Any?) {
        guard _isEnabled else { return }
        if let control = _controlView as? NSControl { control.performClick(sender) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/preferstrackinguntilmouseup
    @MainActor class public var prefersTrackingUntilMouseUp: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/refusesfirstresponder
    @MainActor open var refusesFirstResponder: Bool {
        get { _refusesFirstResponder }
        set { _refusesFirstResponder = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/representedobject
    @MainActor open var representedObject: Any? {
        get { _representedObject }
        set { _representedObject = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/resetcursorrect(_:in:)
    @MainActor open func resetCursorRect(_ cellFrame: NSRect, in controlView: NSView) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/select(withframe:in:editor:delegate:start:length:)
    /// `edit(withFrame:in:editor:delegate:event:)` without an event, then selects the range.
    @MainActor open func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        _beginFieldEditor(textObj, frame: rect, in: controlView, delegate: delegate)
        textObj.selectedRange = NSRange(location: selStart, length: selLength)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/sendaction(on:)
    @MainActor open func sendAction(on mask: NSEvent.EventTypeMask) -> Int { let old = _sendActionMask; _sendActionMask = Int(mask.rawValue); return old }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/sendsactiononendediting
    /// Stored (default false).
    @MainActor open var sendsActionOnEndEditing: Bool {
        get { _sendsActionOnEndEditing }
        set { _sendsActionOnEndEditing = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/setcellattribute(_:to:)
    @MainActor open func setCellAttribute(_ parameter: NSCell.Attribute, to value: Int) {
        switch parameter {
        case .cellDisabled: isEnabled = value == 0
        case .cellState: state = NSControl.StateValue(rawValue: value)
        case .cellHighlighted: isHighlighted = value != 0
        case .cellEditable: isEditable = value != 0
        default: break
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/setnextstate()
    @MainActor open func setNextState() { state = NSControl.StateValue(rawValue: nextState) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/setupfieldeditorattributes(_:)
    /// Configures the editor for this cell: text colour (dimmed when disabled), no
    /// background, the cell's alignment, editability, rich text and graphics, undo.
    @MainActor open func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
        textObj.textColor = _textColor
        textObj.drawsBackground = false
        textObj.alignment = _alignment
        textObj.isEditable = _isEditable
        textObj.isSelectable = _isEditable || _isSelectable
        textObj.isRichText = _allowsEditingTextAttributes
        textObj.importsGraphics = _importsGraphics
        textObj.isFieldEditor = true
        if let tv = textObj as? NSTextView { tv.allowsUndo = _allowsUndo }
        return textObj
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/showsfirstresponder
    @MainActor open var showsFirstResponder: Bool {
        get { _showsFirstResponder }
        set { _showsFirstResponder = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/starttracking(at:in:)
    @MainActor open func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool { true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/state
    @MainActor open var state: NSControl.StateValue {
        get { _state }
        set { _state = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/stoptracking(last:current:in:mouseisup:)
    @MainActor open func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/stringvalue
    @MainActor open var stringValue: String {
        get {
            if let s = _objectValue as? String { return s }
            if let a = _objectValue as? NSAttributedString { return a.string }
            if let f = _formatter, let v = _objectValue, let s = f.string(for: v) { return s }
            if let v = _objectValue { return "\(v)" }
            return ""
        }
        set { _objectValue = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/tag
    @MainActor open var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takedoublevaluefrom(_:)
    @MainActor open func takeDoubleValueFrom(_ sender: Any?) { if let c = sender as? NSControl { doubleValue = c.doubleValue } else if let c = sender as? NSCell { doubleValue = c.doubleValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takefloatvaluefrom(_:)
    @MainActor open func takeFloatValueFrom(_ sender: Any?) { if let c = sender as? NSControl { floatValue = c.floatValue } else if let c = sender as? NSCell { floatValue = c.floatValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takeintvaluefrom(_:)
    @MainActor open func takeIntValueFrom(_ sender: Any?) { if let c = sender as? NSControl { intValue = c.intValue } else if let c = sender as? NSCell { intValue = c.intValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takeintegervaluefrom(_:)
    @MainActor open func takeIntegerValueFrom(_ sender: Any?) { if let c = sender as? NSControl { integerValue = c.integerValue } else if let c = sender as? NSCell { integerValue = c.integerValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takeobjectvaluefrom(_:)
    @MainActor open func takeObjectValueFrom(_ sender: Any?) { if let c = sender as? NSControl { objectValue = c.objectValue } else if let c = sender as? NSCell { objectValue = c.objectValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takestringvaluefrom(_:)
    @MainActor open func takeStringValueFrom(_ sender: Any?) { if let c = sender as? NSControl { stringValue = c.stringValue } else if let c = sender as? NSCell { stringValue = c.stringValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/target
    @MainActor open var target: AnyObject? {
        get { nil }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/title
    @MainActor open var title: String {
        get { stringValue }
        set { stringValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/titlerect(forbounds:)
    @MainActor open func titleRect(forBounds rect: NSRect) -> NSRect { drawingRect(forBounds: rect).insetBy(dx: 2, dy: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/trackmouse(with:in:of:untilmouseup:)
    @MainActor open func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView, untilMouseUp flag: Bool) -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/truncateslastvisibleline
    @MainActor open var truncatesLastVisibleLine: Bool {
        get { _truncatesLastVisibleLine }
        set { _truncatesLastVisibleLine = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/type
    @MainActor open var type: NSCell.CellType {
        get { _type }
        set { _type = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/userinterfacelayoutdirection
    /// Stored (default left to right, whatever the application's direction; macOS).
    @MainActor open var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { _userInterfaceLayoutDirection }
        set { _userInterfaceLayoutDirection = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/usessinglelinemode
    @MainActor open var usesSingleLineMode: Bool {
        get { _usesSingleLineMode }
        set { _usesSingleLineMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/wantsnotificationformarkedtext
    /// Set by `NSTextFieldCell.setWantsNotificationForMarkedText(_:)`.
    @MainActor open var wantsNotificationForMarkedText: Bool { _wantsNotificationForMarkedText }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/wraps
    @MainActor open var wraps: Bool {
        get { _wraps }
        set { _wraps = newValue }
    }
    // Requirement of NSCopying
    //
    // A copy is a new cell of the same class with the same settings (NSMatrix makes its
    // cells from a prototype this way). The new cell comes from the required
    // `init(coder:)`; each class copies its own storage in `_copyCellState(from:)`.
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = Swift.type(of: self).init(coder: NSCoder())
        c._copyCellState(from: self)
        return c
    }

    /// Copies the settings of `other` (a cell of the same class) into this new cell.
    /// Subclasses with their own storage override it and call super.
    @MainActor internal func _copyCellState(from other: NSCell) {
        _objectValue = other._objectValue; _image = other._image; _state = other._state; _isEnabled = other._isEnabled
        _isHighlighted = other._isHighlighted; _font = other._font; _alignment = other._alignment; _type = other._type
        _controlSize = other._controlSize; _isBordered = other._isBordered; _isBezeled = other._isBezeled
        _isEditable = other._isEditable; _isSelectable = other._isSelectable; _isScrollable = other._isScrollable
        _isContinuous = other._isContinuous; _wraps = other._wraps; _tag = other._tag; _lineBreakMode = other._lineBreakMode
        _representedObject = other._representedObject; _formatter = other._formatter; _allowsMixedState = other._allowsMixedState
        _backgroundStyle = other._backgroundStyle; _truncatesLastVisibleLine = other._truncatesLastVisibleLine
        _usesSingleLineMode = other._usesSingleLineMode; _focusRingType = other._focusRingType
        _refusesFirstResponder = other._refusesFirstResponder; _showsFirstResponder = other._showsFirstResponder
        _baseWritingDirection = other._baseWritingDirection; _menu = other._menu; _sendActionMask = other._sendActionMask
        _allowsUndo = other._allowsUndo; _allowsEditingTextAttributes = other._allowsEditingTextAttributes; _importsGraphics = other._importsGraphics
        _controlTint = other._controlTint; _sendsActionOnEndEditing = other._sendsActionOnEndEditing
        _userInterfaceLayoutDirection = other._userInterfaceLayoutDirection; _wantsNotificationForMarkedText = other._wantsNotificationForMarkedText
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSAccessibilityElementProtocol
    /// The control view's frame; zero for a cell not in a view.
    open func accessibilityFrame() -> NSRect { MainActor.assumeIsolated { _controlView?.accessibilityFrame() ?? .zero } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityParent() -> Any? { MainActor.assumeIsolated { _controlView } }
    // Requirement of NSAccessibilityElementProtocol
    open func isAccessibilityFocused() -> Bool { MainActor.assumeIsolated { _controlView.map { $0.window?.firstResponder === $0 } ?? false } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { "" }
}

