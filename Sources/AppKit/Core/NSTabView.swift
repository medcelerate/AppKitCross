// NSTabView (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview
@MainActor open class NSTabView: NSView {
    // MARK: Storage
    private var _items: [NSTabViewItem] = []
    private var _selected: NSTabViewItem? = nil
    private weak var _delegate: (any NSTabViewDelegate)? = nil
    private var _tabViewType: NSTabView.TabType = .topTabsBezelBorder
    private var _tabPosition: NSTabView.TabPosition = .top
    private var _borderType: NSTabView.TabViewBorderType = .bezel
    private var _allowsTruncatedLabels = true
    private var _drawsBackground = true
    private var _controlSize: NSControl.ControlSize = .regular
    private var _controlTint: NSControlTint = .defaultControlTint
    private var _font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private var _tabBarHeight: CGFloat { _tabPosition == .none ? 0 : 24 }

    open override var isFlipped: Bool { true }

    // MARK: Accessibility (ADR-0013)
    // AXTabGroup: the selected tab's label is the value; the children are the tab bar
    // (a segmented control, when drawn) and the selected page's views.
    open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .tabGroup }
    open override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : selectedTabViewItem?.label }
    open func accessibilityTabs() -> [Any]? { tabViewItems }
    override func _accessibilityIsFocusable() -> Bool { false }
    /// The tabs (as virtual elements) first, then the selected page's elements.
    open override func accessibilityChildren() -> [Any]? {
        if let c = _a11y.children { return c }
        let tabs: [Any] = _tabPosition == .none ? [] : _items
        return tabs + (super.accessibilityChildren() ?? [])
    }
    /// A tab's rect in screen coordinates, for its virtual element.
    internal func _accessibilityTabFrame(_ item: NSTabViewItem) -> NSRect {
        guard let i = _items.firstIndex(where: { $0 === item }) else { return .zero }
        let r = convert(_tabRects()[i], to: nil)
        return window?.convertToScreen(r) ?? r
    }

    /// Tab strip rects per item (in bounds coordinates), laid out centred along the top edge.
    private func _tabRects() -> [NSRect] {
        guard _tabPosition != .none else { return _items.map { _ in .zero } }
        let widths = _items.map { $0.sizeOfLabel(false).width }
        let total = widths.reduce(0, +)
        var x = (bounds.width - total) / 2
        let y: CGFloat = _tabPosition == .bottom ? bounds.height - _tabBarHeight : 0
        return widths.map { w in
            defer { x += w }
            return NSRect(x: x, y: y, width: w, height: _tabBarHeight)
        }
    }

    internal func _tabsChanged() { needsDisplay = true }

    internal func _itemViewChanged(_ item: NSTabViewItem) {
        if item === _selected { _showSelectedView() }
    }

    /// Puts the selected item's view (and only it) in the content area.
    private func _showSelectedView() {
        for s in subviews where !_items.contains(where: { $0.view === s && $0 === _selected }) { s.removeFromSuperview() }
        guard let v = _selected?.view else { return }
        v.frame = contentRect
        v.autoresizingMask = [.width, .height]
        if v.superview !== self { addSubview(v) }
        needsDisplay = true
    }

    open override func layout() {
        super.layout()
        if let v = _selected?.view, v.frame != contentRect { v.frame = contentRect }
    }

    open override func draw(_ dirtyRect: NSRect) {
        let content = contentRect
        if _drawsBackground && _tabViewType != .noTabsNoBorder {
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(rect: content).fill()
        }
        if _borderType != .none && _tabViewType != .noTabsNoBorder {
            NSColor.separatorColor.setStroke()
            let p = NSBezierPath(rect: content.insetBy(dx: 0.5, dy: 0.5))
            p.lineWidth = 1
            p.stroke()
        }
        guard _tabPosition != .none else { return }
        for (i, item) in _items.enumerated() {
            let r = _tabRects()[i]
            let selected = item === _selected
            (selected ? NSColor.controlAccentColor : NSColor.controlColor).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 0, dy: 2), xRadius: 4, yRadius: 4).fill()
            item._tabState = selected ? .selectedTab : .backgroundTab
            if selected {
                let font = _font
                let size = item.label.size(withAttributes: [.font: font])
                item.label.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: [.font: font, .foregroundColor: NSColor.white])
            } else {
                item.drawLabel(_allowsTruncatedLabels, in: r)
            }
        }
    }

    open override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let item = tabViewItem(at: p) { selectTabViewItem(item); return }
        super.mouseDown(with: event)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/addtabviewitem(_:)
    @MainActor open func addTabViewItem(_ tabViewItem: NSTabViewItem) { insertTabViewItem(tabViewItem, at: _items.count) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/allowstruncatedlabels
    @MainActor open var allowsTruncatedLabels: Bool {
        get { _allowsTruncatedLabels }
        set { _allowsTruncatedLabels = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/contentrect
    @MainActor open var contentRect: NSRect {
        var r = bounds
        if _tabPosition == .top { r.origin.y += _tabBarHeight; r.size.height -= _tabBarHeight }
        else if _tabPosition == .bottom { r.size.height -= _tabBarHeight }
        if _tabViewType != .noTabsNoBorder && _borderType != .none { r = r.insetBy(dx: 1, dy: 1) }
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/controlsize
    @MainActor open var controlSize: NSControl.ControlSize {
        get { _controlSize }
        set { _controlSize = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/controltint
    @MainActor open var controlTint: NSControlTint {
        get { _controlTint }
        set { _controlTint = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/delegate
    @MainActor open var delegate: (any NSTabViewDelegate)? {
        get { _delegate }
        set { _delegate = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/drawsbackground
    @MainActor open var drawsBackground: Bool {
        get { _drawsBackground }
        set { _drawsBackground = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/font
    @MainActor open var font: NSFont {
        get { _font }
        set { _font = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/indexoftabviewitem(_:)
    @MainActor open func indexOfTabViewItem(_ tabViewItem: NSTabViewItem) -> Int { _items.firstIndex { $0 === tabViewItem } ?? NSNotFound }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/indexoftabviewitem(withidentifier:)
    @MainActor open func indexOfTabViewItem(withIdentifier identifier: Any) -> Int {
        _items.firstIndex { item in
            if let a = item.identifier as? AnyHashable, let b = identifier as? AnyHashable { return a == b }
            return (item.identifier as AnyObject) === (identifier as AnyObject)
        } ?? NSNotFound
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/inserttabviewitem(_:at:)
    @MainActor open func insertTabViewItem(_ tabViewItem: NSTabViewItem, at index: Int) {
        tabViewItem._tabView?.removeTabViewItem(tabViewItem)
        _items.insert(tabViewItem, at: min(index, _items.count))
        tabViewItem._tabView = self
        if _selected == nil { selectTabViewItem(tabViewItem) }
        _delegate?.tabViewDidChangeNumberOfTabViewItems(self)
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/minimumsize
    @MainActor open var minimumSize: NSSize {
        let w = _tabRects().reduce(CGFloat(0)) { $0 + $1.width }
        return NSSize(width: w + 20, height: _tabBarHeight + 20)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/numberoftabviewitems
    @MainActor open var numberOfTabViewItems: Int { _items.count }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/removetabviewitem(_:)
    @MainActor open func removeTabViewItem(_ tabViewItem: NSTabViewItem) {
        guard let i = _items.firstIndex(where: { $0 === tabViewItem }) else { return }
        _items.remove(at: i)
        tabViewItem._tabView = nil
        if _selected === tabViewItem {
            tabViewItem.view?.removeFromSuperview()
            _selected = nil
            if !_items.isEmpty { selectTabViewItem(at: min(i, _items.count - 1)) }
        }
        _delegate?.tabViewDidChangeNumberOfTabViewItems(self)
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selectfirsttabviewitem(_:)
    @MainActor open func selectFirstTabViewItem(_ sender: Any?) { if !_items.isEmpty { selectTabViewItem(at: 0) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selectlasttabviewitem(_:)
    @MainActor open func selectLastTabViewItem(_ sender: Any?) { if !_items.isEmpty { selectTabViewItem(at: _items.count - 1) } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selectnexttabviewitem(_:)
    @MainActor open func selectNextTabViewItem(_ sender: Any?) {
        guard let s = _selected, let i = _items.firstIndex(where: { $0 === s }), i + 1 < _items.count else { return }
        selectTabViewItem(at: i + 1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selectprevioustabviewitem(_:)
    @MainActor open func selectPreviousTabViewItem(_ sender: Any?) {
        guard let s = _selected, let i = _items.firstIndex(where: { $0 === s }), i > 0 else { return }
        selectTabViewItem(at: i - 1)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selecttabviewitem(_:)
    @MainActor open func selectTabViewItem(_ tabViewItem: NSTabViewItem?) {
        guard tabViewItem !== _selected else { return }
        if let d = _delegate, !d.tabView(self, shouldSelect: tabViewItem), _delegateImplementsShouldSelect { return }
        _delegate?.tabView(self, willSelect: tabViewItem)
        _selected?.view?.removeFromSuperview()
        _selected?._tabState = .backgroundTab
        _selected = tabViewItem
        tabViewItem?._tabState = .selectedTab
        _showSelectedView()
        if let r = tabViewItem?.initialFirstResponder, let w = window { _ = w.makeFirstResponder(r) }
        _delegate?.tabView(self, didSelect: tabViewItem)
    }

    /// The defaulted protocol method returns false; only honour a veto from a real override.
    private var _delegateImplementsShouldSelect: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selecttabviewitem(at:)
    @MainActor open func selectTabViewItem(at index: Int) { guard _items.indices.contains(index) else { return }; selectTabViewItem(_items[index]) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selecttabviewitem(withidentifier:)
    @MainActor open func selectTabViewItem(withIdentifier identifier: Any) {
        let i = indexOfTabViewItem(withIdentifier: identifier)
        if i != NSNotFound { selectTabViewItem(at: i) }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/selectedtabviewitem
    @MainActor open var selectedTabViewItem: NSTabViewItem? { _selected }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/tabposition
    @available(macOS 10.12, *)
    @MainActor open var tabPosition: NSTabView.TabPosition {
        get { _tabPosition }
        set { _tabPosition = newValue; needsLayout = true; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/tabviewbordertype
    @available(macOS 10.12, *)
    @MainActor open var tabViewBorderType: NSTabView.TabViewBorderType {
        get { _borderType }
        set { _borderType = newValue; needsLayout = true; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/tabviewitem(at:)
    @MainActor open func tabViewItem(at point: NSPoint) -> NSTabViewItem? {
        for (i, r) in _tabRects().enumerated() where r.contains(point) { return _items[i] }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/tabviewitem(at:)
    @MainActor open func tabViewItem(at index: Int) -> NSTabViewItem { _items[index] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/tabviewitems
    @MainActor open var tabViewItems: [NSTabViewItem] {
        get { _items }
        set {
            for item in _items { removeTabViewItem(item) }
            for item in newValue { addTabViewItem(item) }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/tabviewtype
    @MainActor open var tabViewType: NSTabView.TabType {
        get { _tabViewType }
        set {
            _tabViewType = newValue
            switch newValue {
            case .topTabsBezelBorder: _tabPosition = .top; _borderType = .bezel
            case .bottomTabsBezelBorder: _tabPosition = .bottom; _borderType = .bezel
            case .leftTabsBezelBorder, .rightTabsBezelBorder: _tabPosition = .top; _borderType = .bezel   // side tabs draw on top for now
            case .noTabsBezelBorder: _tabPosition = .none; _borderType = .bezel
            case .noTabsLineBorder: _tabPosition = .none; _borderType = .line
            case .noTabsNoBorder: _tabPosition = .none; _borderType = .none
            }
            needsLayout = true
            needsDisplay = true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nstabview/takeselectedtabviewitemfromsender(_:)
    @MainActor open func takeSelectedTabViewItemFromSender(_ sender: Any?) {
        if let c = sender as? NSControl { selectTabViewItem(at: c.integerValue) }
    }
}
