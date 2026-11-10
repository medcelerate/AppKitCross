// NSPathControl (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// The control over an `NSPathCell`. Standard style: a click on a component records it as
// `clickedPathItem` and sends the action (the double action on a double click); the URL
// is the application's to change. Pop-up style: a click opens a menu of the ancestors
// (and "Choose…" when editable, which runs an open panel); choosing one sets the URL and
// sends the action.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol
@MainActor open class NSPathControl: NSControl {
    internal var _pathCell: NSPathCell? { _cell as? NSPathCell }
    private weak var _delegate: (any NSPathControlDelegate)?
    private var _isEditable = false
    private var _items: [NSPathControlItem] = []
    private var _itemsURL: URL? = nil
    private var _clickedItem: NSPathControlItem? = nil
    private var _localDragMask: NSDragOperation = []
    private var _remoteDragMask: NSDragOperation = []
    private var _componentElements: [_NSPathComponentAccessibilityElement] = []

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSPathCell(textCell: "") }

    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setActionHandler(for: Selector(("_choosePathItem:"))) { [weak self] sender in
            guard let self, let item = (sender as? NSMenuItem)?.representedObject as? NSPathControlItem else { return }
            self._clickedItem = item
            self._pathCell?._clickedCell = self._pathCell?.pathComponentCells.first { $0.url == item.url }
            self.url = item.url
            self._fireAction()
        }
        setActionHandler(for: Selector(("_choosePath:"))) { [weak self] _ in self?._runOpenPanel() }
    }
    public required init?(coder: NSCoder) { super.init(coder: coder) }

    @MainActor open override var acceptsFirstResponder: Bool { false }

    // MARK: Items

    /// The items mirror the cell's component cells (rebuilt when the URL changes).
    private func _syncItems() {
        guard let cell = _pathCell else { _items = []; return }
        if _itemsURL == cell.url, _items.count == cell.pathComponentCells.count { return }
        _items = cell.pathComponentCells.map { c in
            let item = NSPathControlItem()
            item.title = c.stringValue
            item.image = c.image
            item._url = c.url
            return item
        }
        _itemsURL = cell.url
    }

    @MainActor private func _item(for cell: NSPathComponentCell?) -> NSPathControlItem? {
        guard let cell, let i = _pathCell?.pathComponentCells.firstIndex(where: { $0 === cell }) else { return nil }
        _syncItems()
        return _items.indices.contains(i) ? _items[i] : nil
    }

    // MARK: Mouse

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell = _pathCell else { super.mouseDown(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        if cell.pathStyle == .popUp {
            _openPopUpMenu()
            return
        }
        let hit = cell.pathComponentCell(at: p, withFrame: _cellFrame, in: self)
        cell._clickedCell = hit
        _clickedItem = _item(for: hit)
        needsDisplay = true
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        guard let cell = _pathCell, cell.pathStyle == .standard else { return }
        let p = convert(event.locationInWindow, from: nil)
        let hit = cell.pathComponentCell(at: p, withFrame: _cellFrame, in: self)
        let clicked = cell._clickedCell
        defer { cell._clickedCell = nil; needsDisplay = true }
        guard let clicked, hit === clicked else { _clickedItem = nil; return }
        if event.clickCount == 2, let d = doubleAction { _ = sendAction(d, to: target) } else { _fireAction() }
    }

    // MARK: The pop-up menu

    /// The menu the pop-up style shows: `menu` when one is set, else one item per
    /// component (deepest first) and, when editable, "Choose…" above a separator.
    @MainActor internal func _popUpMenu() -> NSMenu {
        if let m = menu { return m }
        let m = NSMenu(title: "")
        if _isEditable {
            let choose = NSMenuItem(title: "Choose…", action: Selector(("_choosePath:")), keyEquivalent: "")
            choose.target = self
            m.addItem(choose)
            m.addItem(NSMenuItem.separator())
        }
        for item in pathItems.reversed() {
            let mi = NSMenuItem(title: item.title, action: Selector(("_choosePathItem:")), keyEquivalent: "")
            mi.target = self
            mi.image = item.image
            mi.representedObject = item
            m.addItem(mi)
        }
        return m
    }

    @MainActor private func _openPopUpMenu() {
        guard let cell = _pathCell, let w = window else { return }
        let menu = _popUpMenu()
        _delegate?.pathControl(self, willPopUp: menu)
        cell.delegate?.pathCell(cell, willPopUp: menu)
        cell._menuOpen = true
        needsDisplay = true
        let anchor = w.convertToScreen(convert(_cellFrame, to: nil))
        _ = _NSMenuTracker.begin(menu: menu, anchor: anchor, placement: .besideAnchor(edge: .maxY), openedWithMouseDown: true, minimumWidth: _cellFrame.width) { [weak self] _ in
            self?._pathCell?._menuOpen = false
            self?.needsDisplay = true
        }
    }

    /// "Choose…": an open panel for the allowed types; its choice becomes the URL.
    @MainActor private func _runOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = allowedTypes
        panel.directoryURL = url?.hasDirectoryPath == true ? url : url?.deletingLastPathComponent()
        _delegate?.pathControl(self, willDisplay: panel)
        _pathCell?.delegate?.pathCell(_pathCell!, willDisplay: panel)
        let response = panel.runModal()
        guard response == .OK, let chosen = panel.urls.first ?? panel.url else { return }
        url = chosen
        _clickedItem = pathItems.last
        _fireAction()
    }

    // MARK: API

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/allowedtypes
    @available(macOS 10.10, *)
    @MainActor open var allowedTypes: [String]? {
        get { _pathCell?.allowedTypes }
        set { _pathCell?.allowedTypes = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/backgroundcolor
    @MainActor open var backgroundColor: NSColor? {
        get { _pathCell?.backgroundColor }
        set { _pathCell?.backgroundColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/clickedpathcomponentcell()
    @MainActor open func clickedPathComponentCell() -> NSPathComponentCell? { _pathCell?.clickedPathComponentCell ?? _pathCell?.pathComponentCells.first { $0.url == _clickedItem?.url } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/clickedpathitem
    @available(macOS 10.10, *)
    @MainActor open var clickedPathItem: NSPathControlItem? { _clickedItem }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/delegate
    @MainActor open var delegate: (any NSPathControlDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/doubleaction
    @MainActor open var doubleAction: Selector? {
        get { _pathCell?.doubleAction }
        set { _pathCell?.doubleAction = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/iseditable
    @available(macOS 10.10, *)
    @MainActor open var isEditable: Bool {
        get { _isEditable }
        set { _isEditable = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/menu
    @MainActor open override var menu: NSMenu? {
        get { super.menu }
        set { super.menu = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/pathcomponentcells()
    @MainActor open func pathComponentCells() -> [NSPathComponentCell] { _pathCell?.pathComponentCells ?? [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/pathitems
    @available(macOS 10.10, *)
    @MainActor open var pathItems: [NSPathControlItem] {
        get { _syncItems(); return _items }
        set {
            let cells: [NSPathComponentCell] = newValue.map { item in
                let c = NSPathComponentCell(textCell: item.title)
                c.attributedStringValue = item.attributedTitle
                c.image = item.image
                c.url = item.url
                return c
            }
            _pathCell?.pathComponentCells = cells
            _items = newValue
            _itemsURL = _pathCell?.url
            _clickedItem = nil
            invalidateIntrinsicContentSize()
            needsDisplay = true
            _accessibilityStructureChanged()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/pathstyle
    @MainActor open var pathStyle: NSPathControl.Style {
        get { _pathCell?.pathStyle ?? .standard }
        set { _pathCell?.pathStyle = newValue; invalidateIntrinsicContentSize(); needsDisplay = true; _accessibilityStructureChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/placeholderattributedstring
    @available(macOS 10.10, *)
    @MainActor open var placeholderAttributedString: NSAttributedString? {
        get { _pathCell?.placeholderAttributedString }
        set { _pathCell?.placeholderAttributedString = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/placeholderstring
    @available(macOS 10.10, *)
    @MainActor open var placeholderString: String? {
        get { _pathCell?.placeholderString }
        set { _pathCell?.placeholderString = newValue; needsDisplay = true }
    }
    /// Dragging path items out of the control is not provided; the masks are stored.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/setdraggingsourceoperationmask(_:forlocal:)
    @MainActor open func setDraggingSourceOperationMask(_ mask: NSDragOperation, forLocal isLocal: Bool) {
        if isLocal { _localDragMask = mask } else { _remoteDragMask = mask }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/setpathcomponentcells(_:)
    @MainActor open func setPathComponentCells(_ cells: [NSPathComponentCell]) {
        _pathCell?.pathComponentCells = cells
        _itemsURL = nil
        _clickedItem = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
        _accessibilityStructureChanged()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nspathcontrol/url
    @MainActor open var url: URL? {
        get { _pathCell?.url }
        set {
            _pathCell?.url = newValue
            _itemsURL = nil
            invalidateIntrinsicContentSize()
            needsDisplay = true
            _accessibilityStructureChanged()
        }
    }
    // MARK: Accessibility (ADR-0013)
    //
    // The standard style is a group whose children are one button per path component
    // (pressing one is a click on it); the pop-up style is an AXPopUpButton showing the
    // last component, whose press opens the menu.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? (pathStyle == .popUp ? .popUpButton : .group) }
    open override func accessibilityLabel() -> String? { _a11y.label ?? toolTip }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : (pathStyle == .popUp ? pathItems.last?.title : url?.path) }
    @MainActor open override func accessibilityChildren() -> [Any]? {
        if let c = _a11y.children { return c }
        guard pathStyle == .standard else { return [] }
        let n = pathComponentCells().count
        while _componentElements.count < n { _componentElements.append(_NSPathComponentAccessibilityElement(control: self, index: _componentElements.count)) }
        if _componentElements.count > n { _componentElements.removeLast(_componentElements.count - n) }
        return _componentElements
    }
    open override func accessibilityPerformPress() -> Bool {
        guard isEnabled, pathStyle == .popUp else { return false }
        _openPopUpMenu()
        return true
    }
    open override func accessibilityPerformShowMenu() -> Bool { accessibilityPerformPress() }
    @MainActor internal func _accessibilityComponentFrame(_ i: Int) -> NSRect {
        guard let cell = _pathCell else { return .zero }
        let rects = cell._componentRects(in: _cellFrame, rightToLeft: userInterfaceLayoutDirection == .rightToLeft)
        guard rects.indices.contains(i) else { return .zero }
        let r = convert(rects[i], to: nil)
        return window?.convertToScreen(r) ?? r
    }
    @MainActor internal func _accessibilityPressComponent(_ i: Int) -> Bool {
        guard isEnabled, let cell = _pathCell, cell.pathComponentCells.indices.contains(i) else { return false }
        let c = cell.pathComponentCells[i]
        cell._clickedCell = c
        _clickedItem = _item(for: c)
        _fireAction()
        cell._clickedCell = nil
        needsDisplay = true
        return true
    }
}

/// One component of a standard-style `NSPathControl` in the accessibility tree (ADR-0013).
@MainActor
internal final class _NSPathComponentAccessibilityElement: _NSAccessibilityVirtualElement {
    private weak var control: NSPathControl?
    let index: Int
    let _accessibilityElementID = _NSAccessibilityIDs.next()
    init(control: NSPathControl, index: Int) { self.control = control; self.index = index }
    var _accessibilityOwnerView: NSView? { control }
    func _accessibilityElement() -> PlatformAccessibilityElement {
        var e = PlatformAccessibilityElement(id: _accessibilityElementID, role: NSAccessibility.Role.button.rawValue, frame: control?._accessibilityComponentFrame(index) ?? .zero)
        let cells = control?.pathComponentCells() ?? []
        e.label = cells.indices.contains(index) ? cells[index].stringValue : nil
        e.isEnabled = control?.isEnabled ?? false
        e.index = index
        e.actions = [.press]
        return e
    }
    func _accessibilityPerform(_ action: PlatformAccessibilityAction) -> Bool {
        guard action == .press else { return false }
        return control?._accessibilityPressComponent(index) ?? false
    }
}
