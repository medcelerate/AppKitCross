// NSCell (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell
@MainActor open class NSCell: NSObject, NSCopying, NSCoding, NSUserInterfaceItemIdentification, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    // MARK: Storage
    internal var _objectValue: Any? = nil
    internal var _image: NSImage? = nil
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

    /// Marks the control view dirty after a value change.
    internal func _changed() { _controlView?.needsDisplay = true }

    /// Font actually used for drawing.
    internal var _effectiveFont: NSFont { _font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize(for: _controlSize)) }

    internal var _textColor: NSColor { _isEnabled ? .controlTextColor : .disabledControlTextColor }

    internal var _textAttributes: [NSAttributedString.Key: Any] { [.font: _effectiveFont, .foregroundColor: _textColor] }

    open override var description: String { MainActor.assumeIsolated { "<\(Swift.type(of: self)) '\(stringValue)'>" } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/init()
    @MainActor public override init() { unimplemented() }
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
    @MainActor open var allowsEditingTextAttributes: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/allowsmixedstate
    @MainActor open var allowsMixedState: Bool {
        get { _allowsMixedState }
        set { _allowsMixedState = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/allowsundo
    @MainActor open var allowsUndo: Bool {
        get { unimplemented() }
        set { unimplemented() }
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
    @MainActor open var controlTint: NSControlTint {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/controlview
    @MainActor open var controlView: NSView? {
        get { _controlView }
        set { _controlView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/defaultfocusringtype
    @MainActor class public var defaultFocusRingType: NSFocusRingType { NSFocusRingType(rawValue: 2)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/defaultmenu
    @MainActor class public var defaultMenu: NSMenu? { unimplemented() }
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
    @MainActor open func draggingImageComponents(withFrame frame: NSRect, in view: NSView) -> [NSDraggingImageComponent] { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/draw(withexpansionframe:in:)
    @MainActor open func draw(withExpansionFrame cellFrame: NSRect, in view: NSView) { unimplemented() }
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
    @MainActor open func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) { unimplemented() }
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
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/drawingrect(forbounds:)
    @MainActor open func drawingRect(forBounds rect: NSRect) -> NSRect { (_isBordered || _isBezeled) ? rect.insetBy(dx: 2, dy: 2) : rect }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/edit(withframe:in:editor:delegate:event:)
    @MainActor open func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/endediting(_:)
    @MainActor open func endEditing(_ textObj: NSText) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/expansionframe(withframe:in:)
    @MainActor open func expansionFrame(withFrame cellFrame: NSRect, in view: NSView) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/fieldeditor(for:)
    @MainActor open func fieldEditor(for controlView: NSView) -> NSTextView? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/floatvalue
    @MainActor open var floatValue: Float {
        get { Float(doubleValue) }
        set { objectValue = Double(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/focusringmaskbounds(forframe:in:)
    @MainActor open func focusRingMaskBounds(forFrame cellFrame: NSRect, in controlView: NSView) -> NSRect { unimplemented() }
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
    @MainActor open func getPeriodicDelay(_ delay: UnsafeMutablePointer<Float>, interval: UnsafeMutablePointer<Float>) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/hasvalidobjectvalue
    @MainActor open var hasValidObjectValue: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/highlight(_:withframe:in:)
    @MainActor open func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) { isHighlighted = flag }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/highlightcolor(withframe:in:)
    @MainActor open func highlightColor(withFrame cellFrame: NSRect, in controlView: NSView) -> NSColor? { unimplemented() }
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
    @MainActor open var importsGraphics: Bool {
        get { unimplemented() }
        set { unimplemented() }
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
    @MainActor open func menu(for event: NSEvent, in cellFrame: NSRect, of view: NSView) -> NSMenu? { unimplemented() }
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
    @MainActor class public var prefersTrackingUntilMouseUp: Bool { unimplemented() }
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
    @MainActor open func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/sendaction(on:)
    @MainActor open func sendAction(on mask: NSEvent.EventTypeMask) -> Int { let old = _sendActionMask; _sendActionMask = Int(mask.rawValue); return old }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/sendsactiononendediting
    @MainActor open var sendsActionOnEndEditing: Bool {
        get { unimplemented() }
        set { unimplemented() }
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
    @MainActor open func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText { unimplemented() }
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
    @MainActor open func takeDoubleValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takefloatvaluefrom(_:)
    @MainActor open func takeFloatValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takeintvaluefrom(_:)
    @MainActor open func takeIntValueFrom(_ sender: Any?) { if let c = sender as? NSControl { intValue = c.intValue } else if let c = sender as? NSCell { intValue = c.intValue } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takeintegervaluefrom(_:)
    @MainActor open func takeIntegerValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takeobjectvaluefrom(_:)
    @MainActor open func takeObjectValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/takestringvaluefrom(_:)
    @MainActor open func takeStringValueFrom(_ sender: Any?) { unimplemented() }
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
    @MainActor open var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/usessinglelinemode
    @MainActor open var usesSingleLineMode: Bool {
        get { _usesSingleLineMode }
        set { _usesSingleLineMode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/wantsnotificationformarkedtext
    @MainActor open var wantsNotificationForMarkedText: Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscell/wraps
    @MainActor open var wraps: Bool {
        get { _wraps }
        set { _wraps = newValue }
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityFrame() -> NSRect { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityParent() -> Any? { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func isAccessibilityFocused() -> Bool { unimplemented() }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { unimplemented() }
}
