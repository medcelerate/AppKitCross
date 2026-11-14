// NSMenuItem (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem
open class NSMenuItem: NSObject, NSCopying, NSCoding, NSValidatedUserInterfaceItem, NSUserInterfaceItemIdentification, NSAccessibilityElementProtocol, NSAccessibilityProtocol {
    // MARK: Storage
    private var _title: String
    private var _attributedTitle: NSAttributedString? = nil
    private var _action: Selector?
    private weak var _target: AnyObject?
    private var _keyEquivalent: String
    private var _keyEquivalentModifierMask: NSEvent.ModifierFlags = .command
    private var _isEnabled = true
    private var _isHidden = false
    private var _state: NSControl.StateValue = .off
    private var _tag = 0
    private var _submenu: NSMenu? = nil
    internal weak var _menu: NSMenu?
    private var _representedObject: Any? = nil
    private var _toolTip: String? = nil
    private var _indentationLevel = 0
    private var _isAlternate = false
    private var _isSeparator = false
    private var _isSectionHeader = false
    private var _image: NSImage? = nil
    private var _onStateImage: NSImage? = nil
    private var _offStateImage: NSImage? = nil
    private var _mixedStateImage: NSImage? = nil
    private var _view: NSView? = nil
    private var _subtitle: String? = nil
    private var _badge: NSMenuItemBadge? = nil
    private var _allowsKeyEquivalentWhenHidden = false
    private var _allowsAutomaticKeyEquivalentLocalization = true
    private var _allowsAutomaticKeyEquivalentMirroring = true
    private var _identifier: NSUserInterfaceItemIdentifier? = nil
    nonisolated(unsafe) private static var _usesUserKeyEquivalents = true

    /// Command id used by the platform menu bar.
    internal let _commandID: Int
    nonisolated(unsafe) private static var _nextCommandID = 1000

    private func _notifyChanged() { _menu?.itemChanged(self) }

    open override var description: String { "<NSMenuItem '\(_title)'>" }

    /// Human-readable key equivalent as the platform shows it (e.g. "Ctrl+S").
    internal var _keyEquivalentLabel: String {
        guard !_keyEquivalent.isEmpty else { return "" }
        var parts: [String] = []
        if _keyEquivalentModifierMask.contains(.command) { parts.append("Ctrl") }
        if _keyEquivalentModifierMask.contains(.option) { parts.append("Alt") }
        if _keyEquivalentModifierMask.contains(.shift) { parts.append("Shift") }
        if _keyEquivalentModifierMask.contains(.control) { parts.append("Win") }
        let key: String
        switch _keyEquivalent {
        case "\r": key = "Enter"
        case "\t": key = "Tab"
        case "\u{7F}": key = "Backspace"
        case "\u{F728}": key = "Delete"
        case "\u{1B}": key = "Esc"
        case " ": key = "Space"
        default: key = _keyEquivalent.uppercased()
        }
        return (parts + [key]).joined(separator: "+")
    }

    /// Whether `event` is this item's key equivalent.
    @MainActor internal func _matches(_ event: NSEvent) -> Bool {
        guard !_keyEquivalent.isEmpty, _isEnabled, !_isHidden || _allowsKeyEquivalentWhenHidden else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        var required = _keyEquivalentModifierMask.intersection(relevant)
        let typed = event.charactersIgnoringModifiers ?? ""
        // An uppercase key equivalent implies Shift.
        if _keyEquivalent.count == 1, _keyEquivalent != _keyEquivalent.lowercased() { required.insert(.shift) }
        guard event.modifierFlags.intersection(relevant) == required else { return false }
        return typed.lowercased() == _keyEquivalent.lowercased()
    }

    /// Description for the platform menu bar.
    @MainActor internal func _platformItem() -> PlatformMenuItem {
        PlatformMenuItem(id: _commandID, title: _title, isSeparator: _isSeparator, isEnabled: _isEnabled && !_isSectionHeader,
                         isChecked: _state == .on, isHidden: _isHidden, keyEquivalentLabel: _keyEquivalentLabel,
                         submenu: _submenu?._platformMenu())
    }

    open var identifier: NSUserInterfaceItemIdentifier? {
        get { _identifier }
        set { _identifier = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/init(coder:)
    public required convenience init(coder: NSCoder) { self.init(title: "", action: nil, keyEquivalent: "") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/init(title:action:keyequivalent:)
    public init(title string: String, action selector: Selector?, keyEquivalent charCode: String) {
        _title = string
        _action = selector
        _keyEquivalent = charCode
        _commandID = NSMenuItem._nextCommandID
        NSMenuItem._nextCommandID += 1
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/action
    open var action: Selector? {
        get { _action }
        set { _action = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/allowsautomatickeyequivalentlocalization
    @available(macOS 12.0, *)
    open var allowsAutomaticKeyEquivalentLocalization: Bool {
        get { _allowsAutomaticKeyEquivalentLocalization }
        set { _allowsAutomaticKeyEquivalentLocalization = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/allowsautomatickeyequivalentmirroring
    @available(macOS 12.0, *)
    open var allowsAutomaticKeyEquivalentMirroring: Bool {
        get { _allowsAutomaticKeyEquivalentMirroring }
        set { _allowsAutomaticKeyEquivalentMirroring = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/allowskeyequivalentwhenhidden
    @available(macOS 10.13, *)
    open var allowsKeyEquivalentWhenHidden: Bool {
        get { _allowsKeyEquivalentWhenHidden }
        set { _allowsKeyEquivalentWhenHidden = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/attributedtitle
    open var attributedTitle: NSAttributedString? {
        get { _attributedTitle }
        set { _attributedTitle = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/badge
    @available(macOS 14.0, *)
    open var badge: NSMenuItemBadge? {
        get { _badge }
        set { _badge = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/hassubmenu
    open var hasSubmenu: Bool { _submenu != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/image
    open var image: NSImage? {
        get { _image }
        set { _image = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/importfromdeviceidentifier
    @available(macOS 10.14, *)
    static public var importFromDeviceIdentifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue: "NSMenuItemImportFromDeviceIdentifier") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/indentationlevel
    open var indentationLevel: Int {
        get { _indentationLevel }
        set { _indentationLevel = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/isalternate
    open var isAlternate: Bool {
        get { _isAlternate }
        set { _isAlternate = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/isenabled
    open var isEnabled: Bool {
        get { _isEnabled }
        set { guard _isEnabled != newValue else { return }; _isEnabled = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/ishidden
    open var isHidden: Bool {
        get { _isHidden }
        set { guard _isHidden != newValue else { return }; _isHidden = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/ishiddenorhashiddenancestor
    open var isHiddenOrHasHiddenAncestor: Bool { _isHidden || (parent?.isHiddenOrHasHiddenAncestor ?? false) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/ishighlighted
    open var isHighlighted: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/issectionheader
    @available(macOS 14.0, *)
    open var isSectionHeader: Bool { _isSectionHeader }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/isseparatoritem
    open var isSeparatorItem: Bool { _isSeparator }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/keyequivalent
    open var keyEquivalent: String {
        get { _keyEquivalent }
        set { guard _keyEquivalent != newValue else { return }; _keyEquivalent = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/keyequivalentmodifiermask
    open var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        get { _keyEquivalentModifierMask }
        set { guard _keyEquivalentModifierMask != newValue else { return }; _keyEquivalentModifierMask = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/menu
    open var menu: NSMenu? {
        get { _menu }
        set { _menu = newValue; _submenu?._supermenu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/mixedstateimage
    open var mixedStateImage: NSImage! {
        get { _mixedStateImage }
        set { _mixedStateImage = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/offstateimage
    open var offStateImage: NSImage? {
        get { _offStateImage }
        set { _offStateImage = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/onstateimage
    open var onStateImage: NSImage! {
        get { _onStateImage }
        set { _onStateImage = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/parent
    open var parent: NSMenuItem? { _menu?._supermenu?.items.first { $0.submenu === _menu } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/representedobject
    open var representedObject: Any? {
        get { _representedObject }
        set { _representedObject = newValue }
    }
    /// Creates a menu item representing a section header with the provided title.
    /// Section header items are used to provide context to a grouping of menu items.
    /// Items created using this method are non-interactive and do not perform an action.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/sectionheader(title:)
    @available(macOS 14.0, *)
    public static func sectionHeader(title: String) -> NSMenuItem { unimplemented() }
    /// Creates a menu item representing a section header with the provided title.
    /// Section header items are used to provide context to a grouping of menu items.
    /// Items created using this method are non-interactive and do not perform an action.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/sectionheader(withtitle:)
    @available(macOS 14.0, *)
    public static func sectionHeader(withTitle title: String) -> NSMenuItem { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/separator()
    public class func separator() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item._isSeparator = true
        item._isEnabled = false
        return item
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/settitlewithmnemonic(_:)
    open func setTitleWithMnemonic(_ stringWithAmpersand: String) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/state
    open var state: NSControl.StateValue {
        get { _state }
        set { guard _state != newValue else { return }; _state = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/submenu
    open var submenu: NSMenu? {
        get { _submenu }
        set {
            _submenu?._supermenu = nil
            _submenu = newValue
            newValue?._supermenu = _menu
            _notifyChanged()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/subtitle
    @available(macOS 14.4, *)
    open var subtitle: String? {
        get { _subtitle }
        set { _subtitle = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/tag
    open var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/target
    open var target: AnyObject? {
        get { _target }
        set { _target = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/title
    open var title: String {
        get { _title }
        set { guard _title != newValue else { return }; _title = newValue; _notifyChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/tooltip
    open var toolTip: String? {
        get { _toolTip }
        set { _toolTip = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/userkeyequivalent
    open var userKeyEquivalent: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/usesuserkeyequivalents
    class public var usesUserKeyEquivalents: Bool {
        get { _usesUserKeyEquivalents }
        set { _usesUserKeyEquivalents = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/view
    open var view: NSView? {
        get { _view }
        set {
            MainActor.assumeIsolated {
                if _view?._enclosingMenuItem === self { _view?._enclosingMenuItem = nil }
                newValue?._enclosingMenuItem = self
            }
            _view = newValue; _notifyChanged()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitem/writingtoolsitems
    @available(macOS 15.2, *)
    class public var writingToolsItems: [NSMenuItem] { unimplemented() }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSMenuItem(title: _title, action: _action, keyEquivalent: _keyEquivalent)
        c._target = _target; c._keyEquivalentModifierMask = _keyEquivalentModifierMask; c._isEnabled = _isEnabled
        c._isHidden = _isHidden; c._state = _state; c._tag = _tag; c._representedObject = _representedObject
        c._toolTip = _toolTip; c._isSeparator = _isSeparator; c._submenu = (_submenu?.copy() as? NSMenu)
        return c
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // MARK: Accessibility (ADR-0013, NSMenuAccessibility.swift)
    // AXMenuBarItem in the main menu, AXMenuItem elsewhere: the title, enabled state, check
    // mark and key equivalent; the submenu is the child. Pressing performs the item or
    // opens its submenu.
    internal var _accessibilityID = 0
    open func accessibilityRole() -> NSAccessibility.Role? { MainActor.assumeIsolated { _a11yRole } }
    open func accessibilityTitle() -> String? { _title }
    open func accessibilityLabel() -> String? { nil }
    open func accessibilityHelp() -> String? { _toolTip }
    open func isAccessibilityElement() -> Bool { !_isSeparator }
    open func isAccessibilityEnabled() -> Bool { _isEnabled }
    open func isAccessibilitySelected() -> Bool { MainActor.assumeIsolated { _a11yIsHighlighted } }
    open func accessibilityChildren() -> [Any]? { _submenu.map { [$0] } ?? [] }
    open func accessibilityPerformPress() -> Bool { MainActor.assumeIsolated { _a11yPress() } }
    open func accessibilityPerformPick() -> Bool { accessibilityPerformPress() }
    open func accessibilityPerformCancel() -> Bool { MainActor.assumeIsolated { _menu?._a11yCancel() ?? false } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityFrame() -> NSRect { MainActor.assumeIsolated { _a11yFrame } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityParent() -> Any? { _menu }
    // Requirement of NSAccessibilityElementProtocol
    /// The highlighted item of an open menu is the one keyboard navigation is on.
    open func isAccessibilityFocused() -> Bool { MainActor.assumeIsolated { _a11yIsHighlighted } }
    // Requirement of NSAccessibilityElementProtocol
    open func accessibilityIdentifier() -> String { _identifier?.rawValue ?? "" }
}
