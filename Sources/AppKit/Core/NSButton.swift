// NSButton (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton
@MainActor open class NSButton: NSControl, NSUserInterfaceValidations, NSAccessibilityButton, NSUserInterfaceCompression {
    // MARK: Bindings (ADR-0032, NSKeyValueBinding+Views.swift)

    internal override class var _definedViewBindings: [NSBindingName] { super._definedViewBindings + [.title] }
    internal override func _applyViewBinding(_ b: _NSBinding) -> Bool { _applyButtonBinding(b) || super._applyViewBinding(b) }
    internal override func _bindingsWillFireAction() { _pushButtonValueBinding() }

    // MARK: Storage
    private var _tracking = false
    private var _trackingInside = false

    internal var _buttonCell: NSButtonCell? { _cell as? NSButtonCell }

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSButtonCell(textCell: "") }

    @MainActor private convenience init(_title: String, type: NSButton.ButtonType, target: Any?, action: Selector?) {
        self.init(frame: .zero)
        setButtonType(type)
        title = _title
        self.target = target as AnyObject?
        self.action = action
        sizeToFit()
    }

    private func _modifierMatch(_ event: NSEvent) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        var pressed = event.modifierFlags.intersection(relevant)
        // A key equivalent that is itself a shifted character ("*", "+", "?") implies Shift,
        // as in AppKit: the typed character already proves the shift state.
        if pressed.contains(.shift), !keyEquivalentModifierMask.contains(.shift),
           keyEquivalent.count == 1, !keyEquivalent.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            pressed.remove(.shift)
        }
        return pressed == keyEquivalentModifierMask.intersection(relevant)
    }

    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder }
    /// A click acts without taking the keyboard focus (the Tab key still reaches it).
    @MainActor internal override var _takesFirstResponderOnMouseDown: Bool { false }

    @MainActor open override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        highlight(true)
        window?.displayIfNeeded()
        highlight(false)
        // The state changes after the highlight is shown and just before the action, as a
        // click's mouse-up does: a display pass in between (a SwiftUI host re-rendering)
        // would otherwise put the old state back before the action reads it.
        if let c = _buttonCell, !c.showsStateBy.isEmpty || c._isSwitchLike { setNextState() }
        _fireAction()
    }
    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        _tracking = true
        _trackingInside = true
        highlight(true)
    }
    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _tracking else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != _trackingInside {
            _trackingInside = inside
            highlight(inside)
        }
    }
    @MainActor open override func mouseUp(with event: NSEvent) {
        guard _tracking else { return }
        _tracking = false
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        highlight(false)
        if inside {
            if let c = _buttonCell, !c.showsStateBy.isEmpty || c._isSwitchLike { setNextState() }
            _fireAction()
        }
    }
    @MainActor open override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { performClick(self); return }
        super.keyDown(with: event)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/init(checkboxwithtitle:target:action:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(checkboxWithTitle title: String, target: Any?, action: Selector?) { self.init(_title: title, type: .switch, target: target, action: action) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/init(image:target:action:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(image: NSImage, target: Any?, action: Selector?) { self.init(_title: "", type: .momentaryPushIn, target: target, action: action); self.image = image }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/init(radiobuttonwithtitle:target:action:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(radioButtonWithTitle title: String, target: Any?, action: Selector?) { self.init(_title: title, type: .radio, target: target, action: action) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/init(title:image:target:action:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(title: String, image: NSImage, target: Any?, action: Selector?) { self.init(_title: title, type: .momentaryPushIn, target: target, action: action); self.image = image }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/init(title:target:action:)
    @available(macOS 10.12, *)
    @MainActor public convenience init(title: String, target: Any?, action: Selector?) { self.init(_title: title, type: .momentaryPushIn, target: target, action: action) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/activecompressionoptions
    @available(macOS 10.13, *)
    @MainActor open var activeCompressionOptions: NSUserInterfaceCompressionOptions { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/allowsmixedstate
    @MainActor open var allowsMixedState: Bool {
        get { _buttonCell?.allowsMixedState ?? false }
        set { _buttonCell?.allowsMixedState = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/alternateimage
    @MainActor open var alternateImage: NSImage? {
        get { _buttonCell?.alternateImage ?? nil }
        set { _buttonCell?.alternateImage = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/alternatetitle
    @MainActor open var alternateTitle: String {
        get { _buttonCell?.alternateTitle ?? "" }
        set { _buttonCell?.alternateTitle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/attributedalternatetitle
    @MainActor open var attributedAlternateTitle: NSAttributedString {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/attributedtitle
    @MainActor open var attributedTitle: NSAttributedString {
        get { _buttonCell?.attributedTitle ?? NSAttributedString(string: "") }
        set { _buttonCell?.attributedTitle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/bezelcolor
    @available(macOS 10.12, *)
    @MainActor open var bezelColor: NSColor? {
        get { _buttonCell?.backgroundColor }
        set { _buttonCell?.backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/bezelstyle
    @MainActor open var bezelStyle: NSButton.BezelStyle {
        get { _buttonCell?.bezelStyle ?? .rounded }
        set { _buttonCell?.bezelStyle = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/bordershape
    @available(macOS 26.0, *)
    @MainActor open var borderShape: NSControl.BorderShape {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/compress(withprioritizedcompressionoptions:)
    @available(macOS 10.13, *)
    @MainActor open func compress(withPrioritizedCompressionOptions prioritizedOptions: [NSUserInterfaceCompressionOptions]) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/contenttintcolor
    @available(macOS 10.14, *)
    @MainActor open var contentTintColor: NSColor? {
        get { nil }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/getperiodicdelay(_:interval:)
    @MainActor open func getPeriodicDelay(_ delay: UnsafeMutablePointer<Float>, interval: UnsafeMutablePointer<Float>) { _buttonCell?.getPeriodicDelay(delay, interval: interval) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/hasdestructiveaction
    @available(macOS 11.0, *)
    @MainActor open var hasDestructiveAction: Bool {
        get { false }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/highlight(_:)
    @MainActor open func highlight(_ flag: Bool) { _cell?.isHighlighted = flag; needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/image
    @MainActor open var image: NSImage? {
        get { _buttonCell?.image ?? nil }
        set { _buttonCell?.image = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/imagehugstitle
    @available(macOS 10.12, *)
    @MainActor open var imageHugsTitle: Bool {
        get { false }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/imageposition
    @MainActor open var imagePosition: NSControl.ImagePosition {
        get { _buttonCell?.imagePosition ?? .noImage }
        set { _buttonCell?.imagePosition = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/imagescaling
    @MainActor open var imageScaling: NSImageScaling {
        get { _buttonCell?.imageScaling ?? .scaleProportionallyDown }
        set { _buttonCell?.imageScaling = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/isbordered
    @MainActor open var isBordered: Bool {
        get { _buttonCell?.isBordered ?? true }
        set { _buttonCell?.isBordered = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/isspringloaded
    @available(macOS 10.10, *)
    @MainActor open var isSpringLoaded: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/istransparent
    @MainActor open var isTransparent: Bool {
        get { _buttonCell?.isTransparent ?? false }
        set { _buttonCell?.isTransparent = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/keyequivalent
    @MainActor open var keyEquivalent: String {
        get { _buttonCell?.keyEquivalent ?? "" }
        set { _buttonCell?.keyEquivalent = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/keyequivalentmodifiermask
    @MainActor open var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        get { _buttonCell?.keyEquivalentModifierMask ?? [] }
        set { _buttonCell?.keyEquivalentModifierMask = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/maxacceleratorlevel
    @available(macOS 10.10, *)
    @MainActor open var maxAcceleratorLevel: Int {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/minimumsize(withprioritizedcompressionoptions:)
    @available(macOS 10.13, *)
    @MainActor open func minimumSize(withPrioritizedCompressionOptions prioritizedOptions: [NSUserInterfaceCompressionOptions]) -> NSSize { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/performkeyequivalent(with:)
    @MainActor open override func performKeyEquivalent(with key: NSEvent) -> Bool {
        guard isEnabled, !isHiddenOrHasHiddenAncestor, !keyEquivalent.isEmpty else { return false }
        let typed = key.charactersIgnoringModifiers ?? ""
        let matches = typed == keyEquivalent || (keyEquivalent == "\r" && (typed == "\r" || typed == "\n"))
        guard matches, _modifierMatch(key) else { return false }
        performClick(self)
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/setbuttontype(_:)
    @MainActor open func setButtonType(_ type: NSButton.ButtonType) { _buttonCell?.setButtonType(type); needsDisplay = true }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/setnextstate()
    @MainActor open func setNextState() { _cell?.setNextState(); needsDisplay = true; _accessibilityValueChanged() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/setperiodicdelay(_:interval:)
    @MainActor open func setPeriodicDelay(_ delay: Float, interval: Float) { _buttonCell?.setPeriodicDelay(delay, interval: interval) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/showsborderonlywhilemouseinside
    @MainActor open var showsBorderOnlyWhileMouseInside: Bool {
        get { _buttonCell?.showsBorderOnlyWhileMouseInside ?? false }
        set { _buttonCell?.showsBorderOnlyWhileMouseInside = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/sound
    @MainActor open var sound: NSSound? {
        get { _buttonCell?.sound ?? nil }
        set { _buttonCell?.sound = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/state
    @MainActor open var state: NSControl.StateValue {
        get { _buttonCell?.state ?? .off }
        set { _buttonCell?.state = newValue; needsDisplay = true; _accessibilityValueChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/symbolconfiguration
    @available(macOS 11.0, *)
    @MainActor open var symbolConfiguration: NSImage.SymbolConfiguration? {
        get { nil }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/tintprominence
    @available(macOS 26.0, *)
    @MainActor open var tintProminence: NSTintProminence {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbutton/title
    @MainActor open var title: String {
        get { _cell?.title ?? "" }
        set { _cell?.title = newValue; needsDisplay = true; _accessibilityNameChanged() }
    }

    // MARK: Accessibility (ADR-0013)
    //
    // Push buttons are AXButton, check boxes AXCheckBox, radio buttons AXRadioButton,
    // all labelled by their title; the state is the value of the two-state kinds, and
    // the press action clicks the button.
    open override func accessibilityRole() -> NSAccessibility.Role? {
        if let r = _a11y.role { return r }
        switch _buttonCell?._buttonType {
        case .switch?: return .checkBox
        case .radio?: return .radioButton
        default: return .button
        }
    }
    open override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        if let s = _a11y.subrole { return s }
        return (_buttonCell?._buttonType == .pushOnPushOff || _buttonCell?._buttonType == .toggle) ? .toggle : nil
    }
    // Requirement of NSAccessibilityButton
    open override func accessibilityLabel() -> String? { _a11y.label ?? (title.isEmpty ? (toolTip ?? image?.name()) : title) }
    open override func accessibilityTitle() -> String? { _a11y.title ?? title }
    /// The state for check boxes, radio and toggle buttons; nil for a push button.
    open override func accessibilityValue() -> Any? {
        if _a11y.hasValue { return _a11y.value }
        guard let cell = _buttonCell, cell._isSwitchLike || !cell.showsStateBy.isEmpty else { return nil }
        return state.rawValue
    }
    override func _accessibilityValueIsSettable() -> Bool { (_buttonCell?._isSwitchLike ?? false) || !(_buttonCell?.showsStateBy.isEmpty ?? true) }
    override func _accessibilitySetValue(_ value: PlatformAccessibilityValue) -> Bool {
        guard _accessibilityValueIsSettable(), let d = value.doubleValue else { return false }
        let wanted: NSControl.StateValue = d == 0 ? .off : (d == 2 ? .mixed : .on)
        if state != wanted { performClick(nil) }
        return state == wanted || wanted == .mixed
    }
    // Requirement of NSAccessibilityButton
    open override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isHiddenOrHasHiddenAncestor else { return false }
        performClick(nil)
        return true
    }
}
