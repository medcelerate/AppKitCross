// NSToolbarItem: one entry of a toolbar. Image items are drawn by the toolbar view as
// buttons (NSToolbarView.swift); view items place their view. Validation goes through
// the target's `validateToolbarItem(_:)` (NSToolbarItemValidation) when the target
// adopts it, as AppKit does, and otherwise asks whether anything in the responder chain
// performs the action at all.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem
@MainActor open class NSToolbarItem: NSObject, NSCopying, NSMenuItemValidation, NSValidatedUserInterfaceItem {
    private let _itemIdentifier: NSToolbarItem.Identifier
    private var _label = ""
    private var _paletteLabel = ""
    private var _title = ""
    private var _toolTip: String?
    private var _image: NSImage?
    private var _view: NSView?
    private weak var _target: AnyObject?
    private var _action: Selector?
    private var _isEnabled = true
    private var _isBordered = false
    private var _isHidden = false
    private var _isNavigational = false
    private var _autovalidates = true
    private var _visibilityPriority: NSToolbarItem.VisibilityPriority = .standard
    private var _menuFormRepresentation: NSMenuItem?
    private var _tag = 0
    private var _minSize = NSSize.zero
    private var _maxSize = NSSize.zero
    private var _possibleLabels: Set<String> = []
    private var _styleRaw = 0
    private var _backgroundTintColor: NSColor?
    private var _badge: Any?
    internal weak var _toolbar: NSToolbar?
    /// The toolbar view knows which items fit; the rest are in the overflow menu.
    internal var _isShownInToolbar = false
    /// `isHidden` without its availability gate, for the toolbar's own code.
    internal var _hiddenInToolbar: Bool { _isHidden }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/init(itemidentifier:)
    @MainActor public init(itemIdentifier: NSToolbarItem.Identifier) {
        _itemIdentifier = itemIdentifier
        super.init()
    }

    open override var description: String { MainActor.assumeIsolated { "<\(type(of: self)) '\(_itemIdentifier.rawValue)' label='\(_label)'>" } }

    /// The toolbar re-lays out when an item's appearance changes.
    internal func _changed(layout: Bool = true) { _toolbar?._itemDidChange(self, layout: layout) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/action
    @MainActor open var action: Selector? {
        get { _action }
        set { _action = newValue; _changed(layout: false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/allowsduplicatesintoolbar
    /// The standard space items may appear more than once; everything else once.
    @MainActor open var allowsDuplicatesInToolbar: Bool {
        _itemIdentifier == .space || _itemIdentifier == .flexibleSpace || _itemIdentifier == .separator
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/autovalidates
    @MainActor open var autovalidates: Bool {
        get { _autovalidates }
        set { _autovalidates = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/backgroundtintcolor
    @available(macOS 26.0, *)
    @MainActor open var backgroundTintColor: NSColor? {
        get { _backgroundTintColor }
        set { _backgroundTintColor = newValue; _changed(layout: false) }
    }
    /// A badge that can be attached to an NSToolbarItem. This provides a way to display small visual indicators that can be used to highlight important information, such as unread notifications or status indicators.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/badge
    @available(macOS 26.0, *)
    @MainActor open var badge: NSItemBadge? {
        get { _badge as? NSItemBadge }
        set { _badge = newValue; _changed(layout: false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/image
    @MainActor open var image: NSImage? {
        get { _image }
        set { _image = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/isbordered
    @available(macOS 10.15, *)
    @MainActor open var isBordered: Bool {
        get { _isBordered }
        set { _isBordered = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/isenabled
    @MainActor open var isEnabled: Bool {
        get { _isEnabled }
        set {
            _isEnabled = newValue
            if let c = _view as? NSControl { c.isEnabled = newValue }
            _changed(layout: false)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/ishidden
    @available(macOS 15.0, *)
    @MainActor open var isHidden: Bool {
        get { _isHidden }
        set { _isHidden = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/isnavigational
    @available(macOS 11.0, *)
    @MainActor open var isNavigational: Bool {
        get { _isNavigational }
        set { _isNavigational = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/isvisible
    /// True while the item is in its toolbar and shown there (not hidden, not in the
    /// overflow menu, the toolbar itself visible).
    @available(macOS 12.0, *)
    @MainActor open var isVisible: Bool { _toolbar?.isVisible == true && !_isHidden && _isShownInToolbar }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/itemidentifier
    @MainActor open var itemIdentifier: NSToolbarItem.Identifier { _itemIdentifier }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/label
    @MainActor open var label: String {
        get { _label }
        set { _label = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/maxsize
    @MainActor open var maxSize: NSSize {
        get { _maxSize }
        set { _maxSize = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/menuformrepresentation
    @MainActor open var menuFormRepresentation: NSMenuItem? {
        get { _menuFormRepresentation }
        set { _menuFormRepresentation = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/minsize
    @MainActor open var minSize: NSSize {
        get { _minSize }
        set { _minSize = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/palettelabel
    /// Falls back to the label, as in AppKit.
    @MainActor open var paletteLabel: String {
        get { _paletteLabel.isEmpty ? _label : _paletteLabel }
        set { _paletteLabel = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/possiblelabels
    @available(macOS 13.0, *)
    @MainActor open var possibleLabels: Set<String> {
        get { _possibleLabels }
        set { _possibleLabels = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/style
    @available(macOS 26.0, *)
    @MainActor open var style: NSToolbarItem.Style {
        get { NSToolbarItem.Style(rawValue: _styleRaw) ?? .plain }
        set { _styleRaw = newValue.rawValue; _changed(layout: false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/tag
    @MainActor open var tag: Int {
        get { _tag }
        set { _tag = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/target
    @MainActor open var target: AnyObject? {
        get { _target }
        set { _target = newValue; _changed(layout: false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/title
    /// Bordered items without an image show their title in the button, as in AppKit.
    @available(macOS 10.15, *)
    @MainActor open var title: String {
        get { _title }
        set { _title = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/tooltip
    @MainActor open var toolTip: String? {
        get { _toolTip }
        set { _toolTip = newValue; _changed(layout: false) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/toolbar
    @MainActor open var toolbar: NSToolbar? { _toolbar }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/validate()
    /// Image items (and view items whose view is a control with the item's action) are
    /// enabled when a target performs the action; a target that adopts
    /// `NSToolbarItemValidation` has the last word. Items without an action keep their state.
    @MainActor open func validate() {
        guard let action = _resolvedAction else { return }
        if let v = _view, !(v is NSControl) { return }
        guard let target = _resolvedTarget(for: action) else { isEnabled = false; return }
        if let validator = target as? NSToolbarItemValidation {
            isEnabled = validator.validateToolbarItem(self)
        } else {
            isEnabled = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/view
    @MainActor open var view: NSView? {
        get { _view }
        set {
            if let old = _view, old !== newValue { old.removeFromSuperview() }
            _view = newValue
            if let c = newValue as? NSControl { c.isEnabled = _isEnabled }
            _changed()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority
    @MainActor open var visibilityPriority: NSToolbarItem.VisibilityPriority {
        get { _visibilityPriority }
        set { _visibilityPriority = newValue; _changed() }
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        MainActor.assumeIsolated {
            let c = NSToolbarItem(itemIdentifier: _itemIdentifier)
            c._copyProperties(from: self)
            return c
        }
    }

    /// Copies the user-settable properties (for `copy(with:)` of this class and subclasses).
    internal func _copyProperties(from other: NSToolbarItem) {
        _label = other._label; _paletteLabel = other._paletteLabel; _title = other._title; _toolTip = other._toolTip
        _image = other._image; _target = other._target; _action = other._action; _isEnabled = other._isEnabled
        _isBordered = other._isBordered; _isHidden = other._isHidden; _isNavigational = other._isNavigational
        _autovalidates = other._autovalidates; _visibilityPriority = other._visibilityPriority
        _menuFormRepresentation = other._menuFormRepresentation; _tag = other._tag; _minSize = other._minSize; _maxSize = other._maxSize
        _possibleLabels = other._possibleLabels; _styleRaw = other._styleRaw; _backgroundTintColor = other._backgroundTintColor; _badge = other._badge
    }

    // MARK: Target/action (TargetAction.swift)

    /// The action the item sends: its own, or its control view's.
    internal var _resolvedAction: Selector? { action ?? (_view as? NSControl)?.action }

    /// Who would receive `action`: the explicit target (the item's, else the control's),
    /// or the first responder in the chain of the toolbar's window, the application and
    /// its delegate that performs it. Nil when nobody does.
    internal func _resolvedTarget(for action: Selector) -> AnyObject? {
        if let t = target ?? (_view as? NSControl)?.target { return ActionRegistry.canPerform(action, on: t) ? t : nil }
        var responder: NSResponder? = _toolbar?._window?.firstResponder ?? _toolbar?._window
        while let r = responder {
            if ActionRegistry.canPerform(action, on: r) { return r }
            responder = r.nextResponder
        }
        let app = NSApplication.shared
        if ActionRegistry.canPerform(action, on: app) { return app }
        if let d = app.delegate, ActionRegistry.canPerform(action, on: d) { return d }
        return nil
    }

    /// Sends the action (a click on an image item, or a choice in the overflow menu).
    @MainActor internal func _fireAction() {
        guard let action else { return }
        _ = NSApplication.shared.sendAction(action, to: target, from: self)
    }

    /// The menu item that stands for this item in the overflow menu (and the customization
    /// palette's lists): the `menuFormRepresentation`, else one made from the label.
    internal func _menuRepresentation() -> NSMenuItem? {
        if let m = _menuFormRepresentation { return m }
        if _itemIdentifier == .space || _itemIdentifier == .flexibleSpace || _itemIdentifier == .separator { return nil }
        let title = _label.isEmpty ? _title : _label
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = _image
        item.isEnabled = _isEnabled
        item.representedObject = self
        return item
    }
}

extension NSToolbarItem {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier
    public struct Identifier: RawRepresentable, Hashable, Equatable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/cloudsharing
        @available(macOS 10.12, *)
        static public var cloudSharing: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarCloudSharingItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/customizetoolbar
        static public var customizeToolbar: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarCustomizeToolbarItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/flexiblespace
        static public var flexibleSpace: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarFlexibleSpaceItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/inspectortrackingseparator
        @available(macOS 14.0, *)
        static public var inspectorTrackingSeparator: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarInspectorTrackingSeparatorItemIdentifier") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/print
        static public var print: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarPrintItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/separator
        static public var separator: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarSeparatorItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/showcolors
        static public var showColors: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarShowColorsItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/showfonts
        static public var showFonts: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarShowFontsItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/sidebartrackingseparator
        @available(macOS 11.0, *)
        static public var sidebarTrackingSeparator: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarSidebarTrackingSeparatorItemIdentifier") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/space
        static public var space: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarSpaceItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/toggleinspector
        @available(macOS 14.0, *)
        static public var toggleInspector: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarToggleInspectorItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/togglesidebar
        @available(macOS 10.11, *)
        static public var toggleSidebar: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarToggleSidebarItem") }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/identifier/writingtoolsitemidentifier
        @available(macOS 15.2, *)
        static public var writingToolsItemIdentifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier(rawValue: "NSToolbarWritingToolsItem") }
    }
}

@available(macOS 26.0, *)
extension NSToolbarItem {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/style
    @available(macOS 26.0, *)
    public enum Style: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/style/plain
        case plain = 0 // APIGEN: raw value unverified (symbol newer than the probe OS)
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/style/prominent
        case prominent = 1 // APIGEN: raw value unverified (symbol newer than the probe OS)
    }
}

extension NSToolbarItem {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority
    public struct VisibilityPriority: RawRepresentable, Comparable, Equatable, Hashable, Sendable {
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public init(_ rawValue: Int) { self.rawValue = rawValue }

        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority/high
        static public var high: NSToolbarItem.VisibilityPriority { NSToolbarItem.VisibilityPriority(rawValue: 1000) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority/low
        static public var low: NSToolbarItem.VisibilityPriority { NSToolbarItem.VisibilityPriority(rawValue: -1000) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority/standard
        static public var standard: NSToolbarItem.VisibilityPriority { NSToolbarItem.VisibilityPriority(rawValue: 0) }
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbaritem/visibilitypriority/user
        static public var user: NSToolbarItem.VisibilityPriority { NSToolbarItem.VisibilityPriority(rawValue: 2000) }
    }
}
