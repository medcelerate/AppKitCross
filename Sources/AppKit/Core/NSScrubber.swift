// NSScrubber (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// There is no Touch Bar off the Mac, so a scrubber is an ordinary view: a horizontally
// scrolling strip of items (ADR-0034). The items sit in a document view inside a scroll
// view without scrollers; the layout (flow by default) gives their frames, and only the
// items in the visible rect have views, asked of the data source and recycled by
// identifier through `makeItem(withIdentifier:owner:)`. The selection style's views are
// placed at the selected item, the background one below the items and the overlay one
// above.
//
// With the mouse: a click selects the item under it. A drag scrolls the strip in free
// mode and moves the highlight across items in fixed mode; a continuous scrubber selects
// as the pointer passes over items. The wheel (either axis) scrolls; arrow buttons page.
// After a scroll the item nearest the alignment point snaps to it when `itemAlignment`
// is set. Setting `selectedIndex` does not call the delegate, as in AppKit.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber
@available(macOS 10.12, *)
@MainActor open class NSScrubber: NSView {
    private weak var _dataSource: (any NSScrubberDataSource)?
    private weak var _delegate: (any NSScrubberDelegate)?
    private var _layout: NSScrubberLayout = NSScrubberFlowLayout()
    private var _backgroundColor: NSColor?
    private var _backgroundView: NSView?
    private var _floatsSelectionViews = false
    private var _isContinuous = false
    private var _itemAlignment: NSScrubber.Alignment = .none
    private var _mode: NSScrubber.Mode = .free
    private var _selectedIndex = -1
    private var _highlightedIndex = -1
    private var _selectionBackgroundStyle: NSScrubberSelectionStyle?
    private var _selectionOverlayStyle: NSScrubberSelectionStyle?
    private var _showsAdditionalContentIndicators = false
    private var _showsArrowButtons = false

    private var _count = 0
    private var _loaded = false
    private var _registeredClasses: [NSUserInterfaceItemIdentifier: AnyClass] = [:]
    private var _registeredNibs: [NSUserInterfaceItemIdentifier: NSNib] = [:]
    private var _spare: [NSUserInterfaceItemIdentifier: [NSScrubberItemView]] = [:]
    /// The views of the items in the visible rect, by index.
    private var _itemViews: [Int: NSScrubberItemView] = [:]
    private var _selectionBackgroundView: NSScrubberSelectionView?
    private var _selectionOverlayView: NSScrubberSelectionView?
    private var _visibleRange = NSRange(location: 0, length: 0)
    private var _inBatch = false
    private var _layoutPending = false
    private var _laidOut = false

    private let _scrollView: _NSScrubberScrollView
    private let _documentView = NSView(frame: .zero)
    private let _leftArrow = _NSScrubberArrowButton(frame: .zero)
    private let _rightArrow = _NSScrubberArrowButton(frame: .zero)
    private let _indicators = _NSScrubberIndicatorView(frame: .zero)

    /// A press: where it began (window coordinates), the scroll offset then, whether it
    /// has moved far enough to be a drag.
    private struct _Press {
        let start: NSPoint
        let startOffset: CGFloat
        var dragged: Bool
    }
    private var _press: _Press?
    internal static let _arrowWidth: CGFloat = 20

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/init(coder:)
    public required init?(coder: NSCoder) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        _scrollView = _NSScrubberScrollView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        _scrollView.drawsBackground = false
        _scrollView.hasHorizontalScroller = false
        _scrollView.hasVerticalScroller = false
        _scrollView.scrubber = self
        _scrollView.documentView = _documentView
        addSubview(_scrollView)
        _layout._scrubber = self
        _leftArrow.pointsLeft = true
        _leftArrow.action = { [weak self] in self?._page(-1) }
        _rightArrow.action = { [weak self] in self?._page(1) }
        _indicators.scrubber = self
        _tileSubviews()
    }

    // MARK: Data

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/datasource
    @MainActor open var dataSource: (any NSScrubberDataSource)? {
        get { _dataSource }
        set { _dataSource = newValue; reloadData() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/delegate
    @MainActor open var delegate: (any NSScrubberDelegate)? {
        get { _delegate }
        set { _delegate = newValue; _relayout() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/numberofitems
    @MainActor open var numberOfItems: Int {
        if !_loaded { _loadCount() }
        return _count
    }
    private func _loadCount() {
        _loaded = true
        _count = _dataSource.map { max(0, $0.numberOfItems(for: self)) } ?? 0
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/reloaddata()
    @MainActor open func reloadData() {
        _recycleAll()
        _loadCount()
        if _selectedIndex >= _count { _selectedIndex = -1 }
        _relayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/reloaditems(at:)
    @MainActor open func reloadItems(at indexes: IndexSet) {
        for i in indexes { if let v = _itemViews.removeValue(forKey: i) { _recycle(v) } }
        _relayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/insertitems(at:)
    @MainActor open func insertItems(at indexes: IndexSet) {
        if _selectedIndex >= 0 {
            var s = _selectedIndex
            for i in indexes.sorted() where i <= s { s += 1 }
            _selectedIndex = s
        }
        _recycleAll()
        _loadCount()
        _relayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/removeitems(at:)
    @MainActor open func removeItems(at indexes: IndexSet) {
        if _selectedIndex >= 0 {
            if indexes.contains(_selectedIndex) { _selectedIndex = -1 }
            else { _selectedIndex -= indexes.count(in: 0..<_selectedIndex) }
        }
        _recycleAll()
        _loadCount()
        _relayout()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/moveitem(at:to:)
    @MainActor open func moveItem(at oldIndex: Int, to newIndex: Int) {
        if _selectedIndex == oldIndex { _selectedIndex = newIndex }
        else if oldIndex < _selectedIndex && newIndex >= _selectedIndex { _selectedIndex -= 1 }
        else if oldIndex > _selectedIndex && newIndex <= _selectedIndex { _selectedIndex += 1 }
        _recycleAll()
        _relayout()
    }
    /// Runs the updates, then lays out once.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/performsequentialbatchupdates(_:)
    @MainActor open func performSequentialBatchUpdates(_ updateBlock: () -> Void) {
        let outer = _inBatch
        _inBatch = true
        updateBlock()
        _inBatch = outer
        if !outer && _layoutPending { _relayout() }
    }

    // MARK: Item views

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/register(_:foritemidentifier:)
    @MainActor open func register(_ itemViewClass: AnyClass?, forItemIdentifier itemIdentifier: NSUserInterfaceItemIdentifier) {
        if let c = itemViewClass {
            precondition(c is NSScrubberItemView.Type, "NSScrubber: \(c) is not an NSScrubberItemView subclass")
            _registeredClasses[itemIdentifier] = c
        } else {
            _registeredClasses[itemIdentifier] = nil
        }
        _registeredNibs[itemIdentifier] = nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/register(_:foritemidentifier:)
    @MainActor open func register(_ nib: NSNib?, forItemIdentifier itemIdentifier: NSUserInterfaceItemIdentifier) {
        _registeredNibs[itemIdentifier] = nib
        if nib != nil { _registeredClasses[itemIdentifier] = nil }
    }
    /// A spare view of that identifier, else a new one of the registered class (made
    /// through `init?(coder:)`, as collection views make theirs).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/makeitem(withidentifier:owner:)
    @MainActor open func makeItem(withIdentifier itemIdentifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSScrubberItemView? {
        if var spare = _spare[itemIdentifier], let v = spare.popLast() {
            _spare[itemIdentifier] = spare
            v.isSelected = false
            v.isHighlighted = false
            return v
        }
        if let cls = _registeredClasses[itemIdentifier] as? NSScrubberItemView.Type {
            guard let v = cls.init(coder: _NSCollectionViewPlaceholderCoder()) else {
                preconditionFailure("NSScrubber: \(cls) could not be constructed for '\(itemIdentifier.rawValue)'")
            }
            v.identifier = itemIdentifier
            return v
        }
        if _registeredNibs[itemIdentifier] != nil { unimplemented("NSScrubber.makeItem(withIdentifier:owner:) from a nib") }
        return nil
    }
    /// The item's view while it is in the visible rect.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/itemviewforitem(at:)
    @MainActor open func itemViewForItem(at index: Int) -> NSScrubberItemView? { _itemViews[index] }

    private func _recycle(_ v: NSScrubberItemView) {
        v.removeFromSuperview()
        if let id = v.identifier { _spare[id, default: []].append(v) }
    }
    private func _recycleAll() {
        for (_, v) in _itemViews { _recycle(v) }
        _itemViews.removeAll()
    }

    // MARK: Layout

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/scrubberlayout
    @MainActor open var scrubberLayout: NSScrubberLayout {
        get { _layout }
        set {
            guard newValue !== _layout else { return }
            _layout._scrubber = nil
            _layout = newValue
            newValue._scrubber = self
            _recycleAll()
            _relayout()
        }
    }
    /// The layout asked for a new pass.
    internal func _layoutInvalidated() { _relayout() }

    /// The visible part of the content, in content (document view) coordinates.
    internal var _visibleContentRect: NSRect { _scrollView.contentView.bounds }

    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _tileSubviews()
        _relayout()
    }

    /// The scroll view between the arrow buttons, the background view behind it and the
    /// content indicators over it.
    private func _tileSubviews() {
        let arrows = _showsArrowButtons ? NSScrubber._arrowWidth : 0
        let strip = NSRect(x: arrows, y: 0, width: max(0, bounds.width - 2 * arrows), height: bounds.height)
        if _scrollView.frame != strip { _scrollView.frame = strip }
        _backgroundView?.frame = bounds
        if _showsArrowButtons {
            _leftArrow.frame = NSRect(x: 0, y: 0, width: arrows, height: bounds.height)
            _rightArrow.frame = NSRect(x: bounds.width - arrows, y: 0, width: arrows, height: bounds.height)
            if _leftArrow.superview !== self { addSubview(_leftArrow) }
            if _rightArrow.superview !== self { addSubview(_rightArrow) }
        } else {
            _leftArrow.removeFromSuperview()
            _rightArrow.removeFromSuperview()
        }
        if _showsAdditionalContentIndicators {
            _indicators.frame = strip
            if _indicators.superview !== self { addSubview(_indicators, positioned: .above, relativeTo: _scrollView) }
        } else {
            _indicators.removeFromSuperview()
        }
    }

    /// Prepares the layout, sizes the content and places the visible items.
    private func _relayout() {
        if _inBatch { _layoutPending = true; return }
        _layoutPending = false
        if !_loaded { _loadCount() }
        _layout.prepare()
        let clip = _scrollView.contentView.bounds.size
        let content = _layout.scrubberContentSize
        let size = NSSize(width: max(content.width, clip.width), height: clip.height)
        if _documentView.frame.size != size { _documentView.setFrameSize(size) }
        _clampScroll()
        _laidOut = true
        _placeItems()
    }

    /// Item views for the items in the visible rect; the others go back to the spares.
    private func _placeItems() {
        var attrs: [Int: NSScrubberLayoutAttributes] = [:]
        for a in _layout.layoutAttributesForItems(in: _visibleContentRect) where a.itemIndex >= 0 && a.itemIndex < _count {
            attrs[a.itemIndex] = a
        }
        for (i, v) in _itemViews where attrs[i] == nil {
            _itemViews[i] = nil
            _recycle(v)
        }
        if let ds = _dataSource {
            for i in attrs.keys.sorted() {
                let view: NSScrubberItemView
                if let v = _itemViews[i] { view = v } else {
                    view = ds.scrubber(self, viewForItemAt: i)
                    _itemViews[i] = view
                }
                if view.superview !== _documentView { _documentView.addSubview(view) }
                view.apply(attrs[i]!)
                view.isSelected = i == _selectedIndex
                view.isHighlighted = i == _highlightedIndex
            }
        }
        _placeSelectionViews()
        _indicators.needsDisplay = true
        let indices = attrs.keys
        let range = indices.isEmpty ? NSRange(location: 0, length: 0)
            : NSRange(location: indices.min()!, length: indices.max()! - indices.min()! + 1)
        if range != _visibleRange {
            _visibleRange = range
            _delegate?.scrubber(self, didChangeVisibleRange: range)
        }
    }

    private func _placeSelectionViews() {
        let frame = _selectedIndex >= 0 ? _layout.layoutAttributesForItem(at: _selectedIndex)?.frame : nil
        func place(_ view: inout NSScrubberSelectionView?, _ style: NSScrubberSelectionStyle?, above: Bool) {
            guard let style, let frame else {
                view?.removeFromSuperview()
                if style == nil { view = nil }
                return
            }
            if view == nil { view = style.makeSelectionView() }
            guard let v = view else { return }
            if v.superview !== _documentView {
                _documentView.addSubview(v, positioned: above ? .above : .below, relativeTo: nil)
            } else if above, _documentView.subviews.last !== v {
                _documentView.addSubview(v, positioned: .above, relativeTo: nil)
            }
            if v.frame != frame { v.frame = frame }
            v.isSelected = true
            v.isHighlighted = _highlightedIndex == _selectedIndex
        }
        place(&_selectionBackgroundView, _selectionBackgroundStyle, above: false)
        place(&_selectionOverlayView, _selectionOverlayStyle, above: true)
    }

    // MARK: Scrolling

    private var _scrollOffset: CGFloat { _scrollView.contentView.bounds.minX }
    private var _maxScrollOffset: CGFloat { max(0, _documentView.frame.width - _scrollView.contentView.bounds.width) }

    private func _scroll(to x: CGFloat) {
        let clamped = min(max(x, 0), _maxScrollOffset).rounded()
        guard clamped != _scrollOffset else { return }
        _scrollView.contentView.scroll(to: NSPoint(x: clamped, y: 0))
        _scrollView.reflectScrolledClipView(_scrollView.contentView)
    }
    private func _clampScroll() {
        if _scrollOffset > _maxScrollOffset || _scrollOffset < 0 { _scroll(to: _scrollOffset) }
    }

    /// The clip view moved.
    internal func _didScroll(from old: NSRect, to new: NSRect) {
        guard _laidOut else { return }
        if _layout.shouldInvalidateLayoutForChange(fromVisibleRect: old, toVisibleRect: new) { _relayout() } else { _placeItems() }
    }

    /// Scrolls so the item sits at `alignment` (`.none`: just into view).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/scrollitem(at:to:)
    @MainActor open func scrollItem(at index: Int, to alignment: NSScrubber.Alignment) {
        guard let f = _layout.layoutAttributesForItem(at: index)?.frame else { return }
        let w = _scrollView.contentView.bounds.width
        switch alignment {
        case .leading: _scroll(to: f.minX)
        case .center: _scroll(to: f.midX - w / 2)
        case .trailing: _scroll(to: f.maxX - w)
        case .none:
            let v = _visibleContentRect
            if f.minX < v.minX { _scroll(to: f.minX) } else if f.maxX > v.maxX { _scroll(to: f.maxX - w) }
        }
    }

    /// The item nearest the alignment point moves onto it.
    private func _snapToAlignment() {
        guard _itemAlignment != .none else { return }
        let v = _visibleContentRect
        let point: CGFloat
        switch _itemAlignment {
        case .leading: point = v.minX
        case .trailing: point = v.maxX
        default: point = v.midX
        }
        var best: (index: Int, distance: CGFloat)?
        for a in _layout.layoutAttributesForItems(in: v.insetBy(dx: -v.width, dy: 0)) {
            let edge: CGFloat
            switch _itemAlignment {
            case .leading: edge = a.frame.minX
            case .trailing: edge = a.frame.maxX
            default: edge = a.frame.midX
            }
            let d = abs(edge - point)
            if best == nil || d < best!.distance || (d == best!.distance && a.itemIndex < best!.index) { best = (a.itemIndex, d) }
        }
        if let b = best { scrollItem(at: b.index, to: _itemAlignment) }
    }

    /// An arrow button: half the visible width (an item in fixed mode) that way.
    private func _page(_ direction: CGFloat) {
        if _mode == .fixed, _count > 0 {
            let target = min(max((_selectedIndex < 0 ? 0 : _selectedIndex) + Int(direction), 0), _count - 1)
            _userSelect(target)
            if _itemAlignment == .none { scrollItem(at: target, to: .none) }
            return
        }
        _scroll(to: _scrollOffset + direction * _scrollView.contentView.bounds.width / 2)
        _snapToAlignment()
    }

    // MARK: Selection

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/selectedindex
    @MainActor open var selectedIndex: Int {
        get { _selectedIndex }
        set {
            let i = newValue >= 0 && newValue < numberOfItems ? newValue : -1
            guard i != _selectedIndex else { return }
            _itemViews[_selectedIndex]?.isSelected = false
            _selectedIndex = i
            _itemViews[i]?.isSelected = true
            if _layout.shouldInvalidateLayoutForSelectionChange { _relayout() } else { _placeSelectionViews() }
            if i >= 0, _itemAlignment != .none { scrollItem(at: i, to: _itemAlignment) }
        }
    }
    /// The item under the pointer while the user interacts; -1 otherwise.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/highlightedindex
    @MainActor open var highlightedIndex: Int { _highlightedIndex }

    private func _setHighlight(_ i: Int) {
        guard i != _highlightedIndex else { return }
        _itemViews[_highlightedIndex]?.isHighlighted = false
        _highlightedIndex = i
        _itemViews[i]?.isHighlighted = true
        if _layout.shouldInvalidateLayoutForHighlightChange { _relayout() } else { _placeSelectionViews() }
        if i >= 0 { _delegate?.scrubber(self, didHighlightItemAt: i) }
    }

    /// A selection the user made: the delegate hears of it.
    private func _userSelect(_ i: Int) {
        guard i >= 0 && i < _count else { return }
        selectedIndex = i
        _delegate?.scrubber(self, didSelectItemAt: i)
    }

    /// The item at a point of the content.
    private func _index(atContentPoint p: NSPoint) -> Int {
        let probe = NSRect(x: p.x, y: _visibleContentRect.minY, width: 1, height: max(1, _visibleContentRect.height))
        for a in _layout.layoutAttributesForItems(in: probe) where a.frame.minX <= p.x && p.x < a.frame.maxX {
            return a.itemIndex
        }
        return -1
    }
    private func _index(atWindowPoint p: NSPoint) -> Int {
        _index(atContentPoint: _documentView.convert(p, from: nil))
    }

    // MARK: Events

    /// The strip takes the mouse for its items (only the arrow buttons answer for themselves).
    @MainActor open override func hitTest(_ point: NSPoint) -> NSView? {
        guard let v = super.hitTest(point) else { return nil }
        if v is _NSScrubberArrowButton { return v }
        return self
    }

    @MainActor open override func mouseDown(with event: NSEvent) {
        _press = _Press(start: event.locationInWindow, startOffset: _scrollOffset, dragged: false)
        _delegate?.didBeginInteracting(with: self)
        let i = _index(atWindowPoint: event.locationInWindow)
        _setHighlight(i)
        if _isContinuous, i >= 0, i != _selectedIndex { _userSelect(i) }
    }

    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard var press = _press else { return }
        let dx = event.locationInWindow.x - press.start.x
        if !press.dragged && abs(dx) > 3 { press.dragged = true }
        _press = press
        guard press.dragged else { return }
        if _mode == .free && !_isContinuous {
            _setHighlight(-1)
            _scroll(to: press.startOffset - dx)
        } else {
            let i = _index(atWindowPoint: event.locationInWindow)
            if i >= 0 {
                _setHighlight(i)
                if _isContinuous, i != _selectedIndex { _userSelect(i) }
            }
        }
    }

    @MainActor open override func mouseUp(with event: NSEvent) {
        guard let press = _press else { return }
        _press = nil
        let i = _index(atWindowPoint: event.locationInWindow)
        var finished = press.dragged
        if !press.dragged {
            if i >= 0 { _userSelect(i); finished = true }
        } else if _mode == .free && !_isContinuous {
            _snapToAlignment()
        } else if !_isContinuous, _highlightedIndex >= 0 {
            _userSelect(_highlightedIndex)
        }
        _setHighlight(-1)
        if finished { _delegate?.didFinishInteracting(with: self) } else { _delegate?.didCancelInteracting(with: self) }
    }

    @MainActor open override func scrollWheel(with event: NSEvent) {
        var d = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { d *= 10 }
        _scroll(to: _scrollOffset - d)
        if !event.hasPreciseScrollingDeltas || event.phase == .ended { _snapToAlignment() }
    }

    // MARK: Appearance

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        if let c = _backgroundColor {
            c.setFill()
            NSBezierPath.fill(dirtyRect)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/backgroundcolor
    @MainActor open var backgroundColor: NSColor? {
        get { _backgroundColor }
        set { _backgroundColor = newValue; needsDisplay = true; _indicators.needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/backgroundview
    @MainActor open var backgroundView: NSView? {
        get { _backgroundView }
        set {
            guard newValue !== _backgroundView else { return }
            _backgroundView?.removeFromSuperview()
            _backgroundView = newValue
            if let v = newValue {
                v.frame = bounds
                addSubview(v, positioned: .below, relativeTo: _scrollView)
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/floatsselectionviews
    @MainActor open var floatsSelectionViews: Bool {
        get { _floatsSelectionViews }
        set { _floatsSelectionViews = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/iscontinuous
    @MainActor open var isContinuous: Bool {
        get { _isContinuous }
        set { _isContinuous = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/itemalignment
    @MainActor open var itemAlignment: NSScrubber.Alignment {
        get { _itemAlignment }
        set { _itemAlignment = newValue; _snapToAlignment() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/mode
    @MainActor open var mode: NSScrubber.Mode {
        get { _mode }
        set { _mode = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/selectionbackgroundstyle
    @MainActor open var selectionBackgroundStyle: NSScrubberSelectionStyle? {
        get { _selectionBackgroundStyle }
        set {
            guard newValue !== _selectionBackgroundStyle else { return }
            _selectionBackgroundView?.removeFromSuperview()
            _selectionBackgroundView = nil
            _selectionBackgroundStyle = newValue
            _placeSelectionViews()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/selectionoverlaystyle
    @MainActor open var selectionOverlayStyle: NSScrubberSelectionStyle? {
        get { _selectionOverlayStyle }
        set {
            guard newValue !== _selectionOverlayStyle else { return }
            _selectionOverlayView?.removeFromSuperview()
            _selectionOverlayView = nil
            _selectionOverlayStyle = newValue
            _placeSelectionViews()
        }
    }
    /// Fades at the ends of the strip while there is more content that way.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/showsadditionalcontentindicators
    @MainActor open var showsAdditionalContentIndicators: Bool {
        get { _showsAdditionalContentIndicators }
        set { _showsAdditionalContentIndicators = newValue; _tileSubviews() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsscrubber/showsarrowbuttons
    @MainActor open var showsArrowButtons: Bool {
        get { _showsArrowButtons }
        set {
            guard newValue != _showsArrowButtons else { return }
            _showsArrowButtons = newValue
            _tileSubviews()
            _relayout()
        }
    }

    /// Whether content lies beyond the leading / trailing end of the strip.
    internal var _hasMoreContent: (leading: Bool, trailing: Bool) {
        (_scrollOffset > 0.5, _scrollOffset < _maxScrollOffset - 0.5)
    }
    /// The scroll offset of the strip (for tests).
    internal var _contentOffset: CGFloat { _scrollOffset }
}

// MARK: - Parts

/// The strip's scroll view: no scrollers; tells the scrubber when it scrolls.
@MainActor final class _NSScrubberScrollView: NSScrollView {
    weak var scrubber: NSScrubber?
    private var _lastVisible = NSRect.zero
    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        let visible = cView.bounds
        guard visible != _lastVisible else { return }
        let old = _lastVisible
        _lastVisible = visible
        scrubber?._didScroll(from: old, to: visible)
    }
    // The scrubber takes the wheel itself (either axis scrolls the strip).
    override func scrollWheel(with event: NSEvent) { scrubber?.scrollWheel(with: event) }
}

/// A chevron button at an end of the strip.
@MainActor final class _NSScrubberArrowButton: NSView {
    var pointsLeft = false
    var action: (() -> Void)?
    private var pressed = false { didSet { if pressed != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        if pressed {
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4).fill()
        }
        let p = NSBezierPath()
        let cx = bounds.midX, cy = bounds.midY, s: CGFloat = 4
        if pointsLeft {
            p.move(to: NSPoint(x: cx + s / 2, y: cy + s)); p.line(to: NSPoint(x: cx - s / 2, y: cy)); p.line(to: NSPoint(x: cx + s / 2, y: cy - s))
        } else {
            p.move(to: NSPoint(x: cx - s / 2, y: cy + s)); p.line(to: NSPoint(x: cx + s / 2, y: cy)); p.line(to: NSPoint(x: cx - s / 2, y: cy - s))
        }
        p.lineWidth = 1.5
        NSColor.secondaryLabelColor.setStroke()
        p.stroke()
    }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { action?() }
    }
}

/// Fades over the ends of the strip where more content lies beyond.
@MainActor final class _NSScrubberIndicatorView: NSView {
    weak var scrubber: NSScrubber?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let s = scrubber else { return }
        let more = s._hasMoreContent
        let w: CGFloat = min(16, bounds.width / 4)
        let base = s.backgroundColor ?? NSColor.windowBackgroundColor
        guard let fade = NSGradient(starting: base, ending: base.withAlphaComponent(0)) else { return }
        if more.leading { fade.draw(in: NSRect(x: 0, y: 0, width: w, height: bounds.height), angle: 0) }
        if more.trailing { fade.draw(in: NSRect(x: bounds.width - w, y: 0, width: w, height: bounds.height), angle: 180) }
    }
}
