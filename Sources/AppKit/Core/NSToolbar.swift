// NSToolbar: the model behind a window's toolbar. Items come from the delegate by
// identifier; the toolbar keeps their order, the selection, the display and size modes,
// visibility, and (with `autosavesConfiguration`) writes the configuration to
// UserDefaults under AppKit's "NSToolbar Configuration <identifier>" key with AppKit's
// "TB ..." entries. The drawing and layout are in NSToolbarView.swift; the window places
// the view under its title band (NSWindow.swift, ADR-0018).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar
@MainActor open class NSToolbar: NSObject {
    private let _identifier: NSToolbar.Identifier
    private weak var _delegate: (any NSToolbarDelegate)?
    private var _items: [NSToolbarItem] = []
    /// The items were loaded (from the autosaved configuration or the delegate's
    /// defaults) once a delegate and a window were both there.
    private var _loaded = false
    private var _selectedItemIdentifier: NSToolbarItem.Identifier?
    private var _displayMode: NSToolbar.DisplayMode = .default
    private var _sizeMode: NSToolbar.SizeMode = .default
    private var _isVisible = true
    private var _showsBaselineSeparator = true
    private var _allowsUserCustomization = false
    private var _allowsExtensionItems = false
    private var _allowsDisplayModeCustomization = true
    /// `allowsDisplayModeCustomization` without its availability gate (the palette).
    internal var _displayModeCustomizable: Bool { _allowsDisplayModeCustomization }
    private var _autosavesConfiguration = false
    private var _centeredItemIdentifiers: Set<NSToolbarItem.Identifier> = []
    private var _fullScreenAccessoryView: NSView?
    private var _fullScreenAccessoryViewMinHeight: CGFloat = 0
    private var _fullScreenAccessoryViewMaxHeight: CGFloat = 0
    private var _palette: _NSToolbarCustomizationPalette?
    internal weak var _window: NSWindow?
    /// The package-drawn view (NSToolbarView.swift), made when a window attaches.
    internal private(set) var _view: _NSToolbarView?

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/init()
    @available(macOS 10.13, *)
    @MainActor public override convenience init() { self.init(identifier: NSToolbar.Identifier(UUID().uuidString)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/init(identifier:)
    @MainActor public init(identifier: NSToolbar.Identifier) {
        _identifier = identifier
        super.init()
    }

    open override var description: String { MainActor.assumeIsolated { "<NSToolbar '\(_identifier)' \(_items.count) items\(_isVisible ? "" : " hidden")>" } }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/allowsdisplaymodecustomization
    @available(macOS 15.0, *)
    @MainActor open var allowsDisplayModeCustomization: Bool {
        get { _allowsDisplayModeCustomization }
        set { _allowsDisplayModeCustomization = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/allowsextensionitems
    @available(macOS 10.10, *)
    @MainActor open var allowsExtensionItems: Bool {
        get { _allowsExtensionItems }
        set { _allowsExtensionItems = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/allowsusercustomization
    @MainActor open var allowsUserCustomization: Bool {
        get { _allowsUserCustomization }
        set { _allowsUserCustomization = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/autosavesconfiguration
    @MainActor open var autosavesConfiguration: Bool {
        get { _autosavesConfiguration }
        set { _autosavesConfiguration = newValue; _autosave() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/centereditemidentifier
    @available(macOS 10.14, *)
    @MainActor open var centeredItemIdentifier: NSToolbarItem.Identifier? {
        get { _centeredItemIdentifiers.first }
        set { _centeredItemIdentifiers = newValue.map { [$0] } ?? []; _layout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/centereditemidentifiers
    @available(macOS 13.0, *)
    @MainActor open var centeredItemIdentifiers: Set<NSToolbarItem.Identifier> {
        get { _centeredItemIdentifiers }
        set { _centeredItemIdentifiers = newValue; _layout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/configuration
    /// AppKit's dictionary: the item identifiers, display mode, size mode and visibility.
    @MainActor open var configuration: [String : Any] {
        [NSToolbar._itemsKey: _items.map { $0.itemIdentifier.rawValue },
         NSToolbar._displayModeKey: _displayMode.rawValue,
         NSToolbar._sizeModeKey: _sizeMode.rawValue,
         NSToolbar._isShownKey: _isVisible]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/customizationpaletteisrunning
    @MainActor open var customizationPaletteIsRunning: Bool { _palette != nil }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/delegate
    @MainActor open var delegate: (any NSToolbarDelegate)? {
        get { _delegate }
        set { _delegate = newValue; _loadIfNeeded() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/didremoveitemnotification
    static public var didRemoveItemNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSToolbarDidRemoveItemNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/displaymode
    @MainActor open var displayMode: NSToolbar.DisplayMode {
        get { _displayMode }
        set { guard _displayMode != newValue else { return }; _displayMode = newValue; _window?._toolbarGeometryDidChange(); _autosave() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/fullscreenaccessoryview
    @MainActor open var fullScreenAccessoryView: NSView? {
        get { _fullScreenAccessoryView }
        set { _fullScreenAccessoryView = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/fullscreenaccessoryviewmaxheight
    @MainActor open var fullScreenAccessoryViewMaxHeight: CGFloat {
        get { _fullScreenAccessoryViewMaxHeight }
        set { _fullScreenAccessoryViewMaxHeight = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/fullscreenaccessoryviewminheight
    @MainActor open var fullScreenAccessoryViewMinHeight: CGFloat {
        get { _fullScreenAccessoryViewMinHeight }
        set { _fullScreenAccessoryViewMinHeight = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/identifier
    @MainActor open var identifier: NSToolbar.Identifier { _identifier }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/insertitem(withitemidentifier:at:)
    @MainActor open func insertItem(withItemIdentifier itemIdentifier: NSToolbarItem.Identifier, at index: Int) {
        _loadIfNeeded(force: true)
        _insert(itemIdentifier, at: index)
        _itemsDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/isvisible
    @MainActor open var isVisible: Bool {
        get { _isVisible }
        set { guard _isVisible != newValue else { return }; _isVisible = newValue; _window?._toolbarGeometryDidChange(); _autosave() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/itemidentifiers
    @available(macOS 15.0, *)
    @MainActor open var itemIdentifiers: [NSToolbarItem.Identifier] {
        get { _items.map { $0.itemIdentifier } }
        set { _loadIfNeeded(force: true); _setItems(newValue) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/items
    @MainActor open var items: [NSToolbarItem] { _items }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/removeitem(at:)
    @MainActor open func removeItem(at index: Int) {
        guard _items.indices.contains(index) else { return }
        _remove(at: index)
        _itemsDidChange()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/removeitem(identifier:)
    @available(macOS 15.0, *)
    @MainActor open func removeItem(identifier itemIdentifier: NSToolbarItem.Identifier) {
        guard let i = _items.firstIndex(where: { $0.itemIdentifier == itemIdentifier }) else { return }
        removeItem(at: i)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/runcustomizationpalette(_:)
    /// Opens the customization sheet (NSToolbarView.swift) on the toolbar's window.
    @MainActor open func runCustomizationPalette(_ sender: Any?) {
        guard _allowsUserCustomization, _palette == nil, let window = _window, let delegate = _delegate else { return }
        _loadIfNeeded(force: true)
        let palette = _NSToolbarCustomizationPalette(toolbar: self, allowed: delegate.toolbarAllowedItemIdentifiers(self))
        _palette = palette
        window.beginSheet(palette.window) { [weak self] _ in self?._palette = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/selecteditemidentifier
    @MainActor open var selectedItemIdentifier: NSToolbarItem.Identifier? {
        get { _selectedItemIdentifier }
        set { _selectedItemIdentifier = newValue; _view?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/setconfiguration(_:)
    @MainActor open func setConfiguration(_ configDict: [String : Any]) {
        _loadIfNeeded(force: true)
        if let ids = configDict[NSToolbar._itemsKey] as? [String] { _setItems(ids.map { NSToolbarItem.Identifier($0) }) }
        if let m = configDict[NSToolbar._displayModeKey] as? Int, let mode = NSToolbar.DisplayMode(rawValue: m) { displayMode = mode }
        if let m = configDict[NSToolbar._sizeModeKey] as? Int, let mode = NSToolbar.SizeMode(rawValue: m) { sizeMode = mode }
        if let shown = configDict[NSToolbar._isShownKey] as? Bool { isVisible = shown }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/showsbaselineseparator
    @MainActor open var showsBaselineSeparator: Bool {
        get { _showsBaselineSeparator }
        set { _showsBaselineSeparator = newValue; _view?.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/sizemode
    @MainActor open var sizeMode: NSToolbar.SizeMode {
        get { _sizeMode }
        set { guard _sizeMode != newValue else { return }; _sizeMode = newValue; _window?._toolbarGeometryDidChange(); _autosave() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/validatevisibleitems()
    /// Asks every visible item that autovalidates to validate itself.
    @MainActor open func validateVisibleItems() {
        for item in visibleItems ?? [] where item.autovalidates { item.validate() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/visibleitems
    /// The items shown in the toolbar (hidden items and those in the overflow menu are
    /// not); nil while the toolbar is hidden.
    @MainActor open var visibleItems: [NSToolbarItem]? {
        guard _isVisible else { return nil }
        _view?.layoutSubtreeIfNeeded()
        return _items.filter { !$0._hiddenInToolbar && $0._isShownInToolbar }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/willadditemnotification
    static public var willAddItemNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSToolbarWillAddItemNotification") }

    // MARK: Items

    /// The window attached the toolbar: load the items once a delegate is there too.
    internal func _attach(to window: NSWindow) {
        _window = window
        if _view == nil { _view = _NSToolbarView(toolbar: self) }
        _loadIfNeeded()
    }

    internal func _detach() {
        _view?.removeFromSuperview()
        _window = nil
    }

    /// Loads the items from the autosaved configuration or the delegate's defaults once
    /// the toolbar has a delegate and a window (or, with `force`, is edited before that).
    private func _loadIfNeeded(force: Bool = false) {
        guard !_loaded, let delegate = _delegate, force || _window != nil else { return }
        _loaded = true
        var ids = delegate.toolbarDefaultItemIdentifiers(self)
        if _autosavesConfiguration, let saved = UserDefaults.standard.dictionary(forKey: _autosaveKey) {
            if let savedIDs = saved[NSToolbar._itemsKey] as? [String] { ids = savedIDs.map { NSToolbarItem.Identifier($0) } }
            if let m = saved[NSToolbar._displayModeKey] as? Int, let mode = NSToolbar.DisplayMode(rawValue: m) { _displayMode = mode }
            if let m = saved[NSToolbar._sizeModeKey] as? Int, let mode = NSToolbar.SizeMode(rawValue: m) { _sizeMode = mode }
            if let shown = saved[NSToolbar._isShownKey] as? Bool { _isVisible = shown }
        }
        for id in ids { _insert(id, at: _items.count) }
        _itemsDidChange(autosave: false)
    }

    /// The item for `identifier`: a standard item, or the delegate's.
    private func _makeItem(_ identifier: NSToolbarItem.Identifier, willBeInserted: Bool) -> NSToolbarItem? {
        if let standard = NSToolbar._standardItem(identifier) { return standard }
        return _delegate?.toolbar(self, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: willBeInserted)
    }

    private func _insert(_ identifier: NSToolbarItem.Identifier, at index: Int) {
        guard let item = _makeItem(identifier, willBeInserted: true) else { return }
        if !item.allowsDuplicatesInToolbar, _items.contains(where: { $0.itemIdentifier == identifier }) { return }
        let at = max(0, min(index, _items.count))
        let note = Notification(name: NSToolbar.willAddItemNotification, object: self,
                                userInfo: [NSToolbarUserInfoKey.itemKey.rawValue: item, "newIndex": at])
        _delegate?.toolbarWillAddItem(note)
        NotificationCenter.default.post(note)
        item._toolbar = self
        _items.insert(item, at: at)
        if let v = item.view { _view?.addSubview(v) }
    }

    private func _remove(at index: Int) {
        let item = _items.remove(at: index)
        item._toolbar = nil
        item._isShownInToolbar = false
        item.view?.removeFromSuperview()
        let note = Notification(name: NSToolbar.didRemoveItemNotification, object: self, userInfo: [NSToolbarUserInfoKey.itemKey.rawValue: item])
        _delegate?.toolbarDidRemoveItem(note)
        NotificationCenter.default.post(note)
    }

    /// Makes the toolbar hold exactly `ids`, in that order, keeping the items that stay.
    private func _setItems(_ ids: [NSToolbarItem.Identifier]) {
        var remaining = _items
        var result: [NSToolbarItem] = []
        var removed: [NSToolbarItem] = []
        for id in ids {
            if let i = remaining.firstIndex(where: { $0.itemIdentifier == id }) {
                result.append(remaining.remove(at: i))
            } else if let item = _makeItem(id, willBeInserted: true) {
                if !item.allowsDuplicatesInToolbar, result.contains(where: { $0.itemIdentifier == id }) { continue }
                let note = Notification(name: NSToolbar.willAddItemNotification, object: self,
                                        userInfo: [NSToolbarUserInfoKey.itemKey.rawValue: item, "newIndex": result.count])
                _delegate?.toolbarWillAddItem(note)
                NotificationCenter.default.post(note)
                item._toolbar = self
                if let v = item.view { _view?.addSubview(v) }
                result.append(item)
            }
        }
        removed = remaining
        _items = result
        for item in removed {
            item._toolbar = nil
            item._isShownInToolbar = false
            item.view?.removeFromSuperview()
            let note = Notification(name: NSToolbar.didRemoveItemNotification, object: self, userInfo: [NSToolbarUserInfoKey.itemKey.rawValue: item])
            _delegate?.toolbarDidRemoveItem(note)
            NotificationCenter.default.post(note)
        }
        _itemsDidChange()
    }

    /// Reverts to the delegate's default set (the customization palette's button).
    internal func _useDefaultItems() {
        guard let d = _delegate else { return }
        _setItems(d.toolbarDefaultItemIdentifiers(self))
    }

    /// Whether the delegate allows `identifier` at `index` (customization palette).
    internal func _canInsert(_ identifier: NSToolbarItem.Identifier, at index: Int) -> Bool {
        _delegate?.toolbar(self, itemIdentifier: identifier, canBeInsertedAt: index) ?? true
    }
    internal var _selectableItemIdentifiers: [NSToolbarItem.Identifier] { _delegate?.toolbarSelectableItemIdentifiers(self) ?? [] }
    internal var _immovableItemIdentifiers: Set<NSToolbarItem.Identifier> { _delegate?.toolbarImmovableItemIdentifiers(self) ?? [] }
    internal var _allowedItemIdentifiers: [NSToolbarItem.Identifier] { _delegate?.toolbarAllowedItemIdentifiers(self) ?? [] }
    /// A fresh item for the palette's listing (not inserted).
    internal func _paletteItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? { _makeItem(identifier, willBeInserted: false) }

    private func _itemsDidChange(autosave: Bool = true) {
        _layout()
        if autosave { _autosave() }
    }

    internal func _itemDidChange(_ item: NSToolbarItem, layout: Bool) {
        if layout {
            if let v = item.view, v.superview !== _view { _view?.addSubview(v) }
            _layout()
        } else {
            _view?.needsDisplay = true
            _view?._refreshItemViews()
        }
    }

    private func _layout() {
        _view?.needsLayout = true
        _view?.needsDisplay = true
        _window?._platformWindow?.setNeedsDisplay(nil)
    }

    // MARK: Autosave

    static let _itemsKey = "TB Item Identifiers"
    static let _displayModeKey = "TB Display Mode"
    static let _sizeModeKey = "TB Size Mode"
    static let _isShownKey = "TB Is Shown"
    private var _autosaveKey: String { "NSToolbar Configuration \(_identifier)" }

    private func _autosave() {
        guard _autosavesConfiguration, _loaded else { return }
        UserDefaults.standard.set(configuration, forKey: _autosaveKey)
    }

    // MARK: Standard items

    /// The items AppKit supplies itself. The spaces and separators lay out; the others
    /// send the standard actions (`toggleSidebar:`, `printDocument:`, `orderFrontColorPanel:`,
    /// `orderFrontFontPanel:`, `toggleInspector:`, `runToolbarCustomizationPalette:`) through
    /// the responder chain and are disabled when nothing performs them; cloud sharing has
    /// no service behind it on these platforms and stays disabled.
    internal static func _standardItem(_ id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        func item(_ label: String, _ action: String?, _ glyph: _NSToolbarGlyph?) -> NSToolbarItem {
            let i = NSToolbarItem(itemIdentifier: id)
            i.label = label
            i.paletteLabel = label
            if let a = action { i.action = Selector((a)) }
            if let g = glyph { i.image = g.image }
            return i
        }
        switch id {
        case .space: return item("Space", nil, nil)
        case .flexibleSpace: return item("Flexible Space", nil, nil)
        case .separator: return item("Separator", nil, nil)
        case .sidebarTrackingSeparator, .inspectorTrackingSeparator: return item("Separator", nil, nil)
        case .toggleSidebar: return item("Sidebar", "toggleSidebar:", .sidebar)
        case .toggleInspector: return item("Inspector", "toggleInspector:", .inspector)
        case .print: return item("Print", "printDocument:", .print)
        case .showColors: return item("Colors", "orderFrontColorPanel:", .colors)
        case .showFonts: return item("Fonts", "orderFrontFontPanel:", .fonts)
        case .customizeToolbar: return item("Customize", "runToolbarCustomizationPalette:", .customize)
        case .cloudSharing:
            let i = item("Share", nil, .share)
            i.isEnabled = false
            i.autovalidates = false
            return i
        default: return nil
        }
    }
}

extension NSToolbar {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/displaymode
    public enum DisplayMode: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/displaymode/default
        case `default` = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/displaymode/iconandlabel
        case iconAndLabel = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/displaymode/icononly
        case iconOnly = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/displaymode/labelonly
        case labelOnly = 3
    }
}

extension NSToolbar {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/identifier
    public typealias Identifier = String
}

extension NSToolbar {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/sizemode
    public enum SizeMode: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/sizemode/default
        case `default` = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/sizemode/regular
        case regular = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstoolbar/sizemode/small
        case small = 2
    }
}
