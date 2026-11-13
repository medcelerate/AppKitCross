// NSControl (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol
@MainActor open class NSControl: NSView {
    // MARK: Bindings (ADR-0032, NSKeyValueBinding+Views.swift)

    internal override class var _definedViewBindings: [NSBindingName] { super._definedViewBindings + [.enabled, .value] }
    internal override func _applyViewBinding(_ b: _NSBinding) -> Bool { _applyControlBinding(b) || super._applyViewBinding(b) }
    internal override func _viewBindingDidAttach(_ b: _NSBinding) { _controlBindingDidAttach(b); super._viewBindingDidAttach(b) }
    /// The control is about to send its action: bound values go back to the model first.
    internal func _bindingsWillFireAction() { _pushControlValueBinding() }

    // MARK: Storage
    internal var _cell: NSCell?
    private var _ignoresMultiClick = false
    private var _refusesFirstResponder = false
    private var _allowsExpansionToolTips = false
    nonisolated(unsafe) private static var _cellClass: AnyClass? = nil

    /// Subclasses with a default cell type override this; NSControl itself has none.
    @MainActor open class func _makeDefaultCell() -> NSCell? { nil }

    /// The frame the cell draws into.
    @MainActor internal var _cellFrame: NSRect { bounds }

    /// Delivers the control's action; NSCell.performClick and subclasses use it.
    @MainActor internal func _fireAction() {
        _bindingsWillFireAction()
        _ = sendAction(action, to: target)
    }

    open override var description: String { MainActor.assumeIsolated { "<\(type(of: self)) frame=\(frame) '\(stringValue)'>" } }

    @MainActor open override func draw(_ dirtyRect: NSRect) { _cell?.draw(withFrame: _cellFrame, in: self) }
    @MainActor open override var intrinsicContentSize: NSSize { _cell?.cellSize ?? super.intrinsicContentSize }
    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !_refusesFirstResponder }
    @MainActor open override func mouseDown(with event: NSEvent) { super.mouseDown(with: event) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/init(coder:)
    public required init?(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _cell = type(of: self)._makeDefaultCell()
        _cell?.controlView = self
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/abortediting()
    @MainActor open func abortEditing() -> Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/action
    @MainActor open var action: Selector? {
        get { _cell?.action }
        set { _cell?.action = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/alignment
    @MainActor open var alignment: NSTextAlignment {
        get { _cell?.alignment ?? .natural }
        set { _cell?.alignment = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/allowsexpansiontooltips
    @MainActor open var allowsExpansionToolTips: Bool {
        get { _allowsExpansionToolTips }
        set { _allowsExpansionToolTips = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/attributedstringvalue
    @MainActor open var attributedStringValue: NSAttributedString {
        get { _cell?.attributedStringValue ?? NSAttributedString(string: "") }
        set { _cell?.attributedStringValue = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/basewritingdirection
    @MainActor open var baseWritingDirection: NSWritingDirection {
        get { _cell?.baseWritingDirection ?? .natural }
        set { _cell?.baseWritingDirection = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/calcsize()
    @MainActor open func calcSize() { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/cell
    @MainActor open var cell: NSCell? {
        get { _cell }
        set { _cell = newValue; _cell?.controlView = self; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/cellclass
    @MainActor class public var cellClass: AnyClass? {
        get { _cellClass }
        set { _cellClass = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/controlsize
    @available(macOS 10.10, *)
    @MainActor open var controlSize: NSControl.ControlSize {
        get { _cell?.controlSize ?? .regular }
        set { _cell?.controlSize = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/currenteditor()
    @MainActor open func currentEditor() -> NSText? { nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/doublevalue
    @MainActor open var doubleValue: Double {
        get { _cell?.doubleValue ?? 0 }
        set { _cell?.doubleValue = newValue; needsDisplay = true; _accessibilityValueChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/draw(withexpansionframe:in:)
    @available(macOS 10.10, *)
    @MainActor open func draw(withExpansionFrame contentFrame: NSRect, in view: NSView) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/drawcell(_:)
    @MainActor open func drawCell(_ cell: NSCell) { if cell === _cell { needsDisplay = true } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/drawcellinside(_:)
    @MainActor open func drawCellInside(_ cell: NSCell) { if cell === _cell { needsDisplay = true } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/edit(withframe:editor:delegate:event:)
    @available(macOS 10.10, *)
    @MainActor open func edit(withFrame rect: NSRect, editor textObj: NSText, delegate: Any?, event: NSEvent) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/endediting(_:)
    @available(macOS 10.10, *)
    @MainActor open func endEditing(_ textObj: NSText) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/expansionframe(withframe:)
    @available(macOS 10.10, *)
    @MainActor open func expansionFrame(withFrame contentFrame: NSRect) -> NSRect { .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/floatvalue
    @MainActor open var floatValue: Float {
        get { _cell?.floatValue ?? 0 }
        set { _cell?.floatValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/font
    @MainActor open var font: NSFont? {
        get { _cell?.font ?? nil }
        set { _cell?.font = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/formatter
    @MainActor open var formatter: Formatter? {
        get { _cell?.formatter ?? nil }
        set { _cell?.formatter = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/ignoresmulticlick
    @MainActor open var ignoresMultiClick: Bool {
        get { _ignoresMultiClick }
        set { _ignoresMultiClick = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/intvalue
    @MainActor open var intValue: Int32 {
        get { _cell?.intValue ?? 0 }
        set { _cell?.intValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/integervalue
    @MainActor open var integerValue: Int {
        get { _cell?.integerValue ?? 0 }
        set { _cell?.integerValue = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/invalidateintrinsiccontentsize(for:)
    @MainActor open func invalidateIntrinsicContentSize(for cell: NSCell) { invalidateIntrinsicContentSize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/iscontinuous
    @MainActor open var isContinuous: Bool {
        get { _cell?.isContinuous ?? false }
        set { _cell?.isContinuous = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/isenabled
    @MainActor open var isEnabled: Bool {
        get { _cell?.isEnabled ?? true }
        set { _cell?.isEnabled = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/ishighlighted
    @available(macOS 10.10, *)
    @MainActor open var isHighlighted: Bool {
        get { _cell?.isHighlighted ?? false }
        set { _cell?.isHighlighted = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/linebreakmode
    @available(macOS 10.10, *)
    @MainActor open var lineBreakMode: NSLineBreakMode {
        get { _cell?.lineBreakMode ?? .byWordWrapping }
        set { _cell?.lineBreakMode = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/objectvalue
    @MainActor open var objectValue: Any? {
        get { _cell?.objectValue ?? nil }
        set { _cell?.objectValue = newValue; needsDisplay = true; _accessibilityValueChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/performclick(_:)
    @MainActor open func performClick(_ sender: Any?) { guard isEnabled else { return }; _fireAction() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/refusesfirstresponder
    @MainActor open var refusesFirstResponder: Bool {
        get { _refusesFirstResponder }
        set { _refusesFirstResponder = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/select(withframe:editor:delegate:start:length:)
    @available(macOS 10.10, *)
    @MainActor open func select(withFrame rect: NSRect, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/selectcell(_:)
    @MainActor open func selectCell(_ cell: NSCell) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/selectedcell()
    @MainActor open func selectedCell() -> NSCell? { _cell }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/selectedtag()
    @MainActor open func selectedTag() -> Int { selectedCell()?.tag ?? -1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/sendaction(_:to:)
    @MainActor open func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard let action else { return false }
        return NSApplication.shared.sendAction(action, to: target, from: self)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/sendaction(on:)
    @MainActor open func sendAction(on mask: NSEvent.EventTypeMask) -> Int { _cell?.sendAction(on: mask) ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/setneedsdisplay()
    @MainActor open func setNeedsDisplay() { needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/sizethatfits(_:)
    @available(macOS 10.10, *)
    @MainActor open func sizeThatFits(_ size: NSSize) -> NSSize { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/sizetofit()
    @MainActor open func sizeToFit() { if let c = _cell { setFrameSize(c.cellSize) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/stringvalue
    @MainActor open var stringValue: String {
        get { _cell?.stringValue ?? "" }
        set { _cell?.stringValue = newValue; invalidateIntrinsicContentSize(); needsDisplay = true; _accessibilityValueChanged() }
    }

    // MARK: Accessibility (ADR-0013)
    //
    // Controls are elements; their enabled state is the control's. Subclasses give the
    // role, label, value and actions.
    open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .unknown }
    open override func isAccessibilityEnabled() -> Bool { _a11y.isEnabled ?? isEnabled }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : (stringValue.isEmpty ? nil : stringValue) }
    /// Controls take mouse downs, so they never drag a window that is movable by background.
    @MainActor open override var mouseDownCanMoveWindow: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/tag
    @MainActor open override var tag: Int {
        get { _cell?.tag ?? 0 }
        set { _cell?.tag = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/takedoublevaluefrom(_:)
    @MainActor open func takeDoubleValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/takefloatvaluefrom(_:)
    @MainActor open func takeFloatValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/takeintvaluefrom(_:)
    @MainActor open func takeIntValueFrom(_ sender: Any?) { _cell?.takeIntValueFrom(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/takeintegervaluefrom(_:)
    @MainActor open func takeIntegerValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/takeobjectvaluefrom(_:)
    @MainActor open func takeObjectValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/takestringvaluefrom(_:)
    @MainActor open func takeStringValueFrom(_ sender: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/target
    @MainActor open var target: AnyObject? {
        get { _cell?.target }
        set { _cell?.target = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/textdidbegineditingnotification
    static public var textDidBeginEditingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSControlTextDidBeginEditingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/textdidchangenotification
    static public var textDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSControlTextDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/textdidendeditingnotification
    static public var textDidEndEditingNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSControlTextDidEndEditingNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/updatecell(_:)
    @MainActor open func updateCell(_ cell: NSCell) { if cell === _cell { needsDisplay = true } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/updatecellinside(_:)
    @MainActor open func updateCellInside(_ cell: NSCell) { if cell === _cell { needsDisplay = true } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/usessinglelinemode
    @available(macOS 10.10, *)
    @MainActor open var usesSingleLineMode: Bool {
        get { _cell?.usesSingleLineMode ?? false }
        set { _cell?.usesSingleLineMode = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscontrol/validateediting()
    @MainActor open func validateEditing() { }
}
