// Menu pop-ups. A menu opens in a borderless, non-activating window drawn by the package,
// so pop-up buttons, context menus and SwiftUI menus look and behave the same on every
// backend. While a menu is open NSApplication routes every mouse and key event to the
// tracker (see NSApplication.sendEvent); windows underneath never see them, as in AppKit.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: Layout

/// Row geometry of a menu, in the (flipped) menu view's coordinates.
@MainActor
struct _NSMenuLayout {
    static let itemHeight: CGFloat = 22
    static let separatorHeight: CGFloat = 11
    static let verticalPadding: CGFloat = 5
    static let stateColumnWidth: CGFloat = 22
    static let leadingPadding: CGFloat = 12
    static let trailingPadding: CGFloat = 14
    static let keyEquivalentGap: CGFloat = 24
    static let submenuArrowWidth: CGFloat = 16
    static let imageSize: CGFloat = 16
    static let indentation: CGFloat = 12

    struct Row {
        let item: NSMenuItem
        let index: Int          // index in menu.items
        let frame: NSRect
    }

    let rows: [Row]
    let size: NSSize
    let font: NSFont
    let textLeft: CGFloat
    let hasSubmenus: Bool

    init(menu: NSMenu, font: NSFont, skippingFirst: Bool = false, minimumWidth: CGFloat = 0) {
        self.font = font
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let left = menu.showsStateColumn ? _NSMenuLayout.stateColumnWidth : _NSMenuLayout.leadingPadding
        textLeft = left
        var items = Array(menu.items.enumerated())
        if skippingFirst, !items.isEmpty { items.removeFirst() }
        var hasSubmenus = false
        var width: CGFloat = 0
        var rows: [Row] = []
        var y = _NSMenuLayout.verticalPadding
        for (index, item) in items where !item.isHidden && !item.isAlternate {
            let height: CGFloat
            if item.isSeparatorItem { height = _NSMenuLayout.separatorHeight }
            else if let v = item.view { height = max(v.frame.height, _NSMenuLayout.itemHeight) }
            else { height = _NSMenuLayout.itemHeight }
            var w = left + CGFloat(item.indentationLevel) * _NSMenuLayout.indentation
            if let v = item.view { w += v.frame.width }
            else {
                if item.image != nil { w += _NSMenuLayout.imageSize + 6 }
                w += item.title.size(withAttributes: attrs).width
                let key = item._keyEquivalentLabel
                if !key.isEmpty { w += _NSMenuLayout.keyEquivalentGap + key.size(withAttributes: attrs).width }
            }
            if item.hasSubmenu { hasSubmenus = true }
            width = max(width, w)
            rows.append(Row(item: item, index: index, frame: NSRect(x: 0, y: y, width: 0, height: height)))
            y += height
        }
        self.hasSubmenus = hasSubmenus
        width += _NSMenuLayout.trailingPadding + (hasSubmenus ? _NSMenuLayout.submenuArrowWidth : 0)
        width = max(width, menu.minimumWidth, minimumWidth)
        let finalSize = NSSize(width: width.rounded(.up), height: (y + _NSMenuLayout.verticalPadding).rounded(.up))
        size = finalSize
        self.rows = rows.map { Row(item: $0.item, index: $0.index, frame: NSRect(x: 0, y: $0.frame.minY, width: finalSize.width, height: $0.frame.height)) }
    }

    func row(at point: NSPoint) -> Row? { rows.first { $0.frame.contains(point) } }
    func row(forItemIndex index: Int) -> Row? { rows.first { $0.index == index } }
}

// MARK: View

/// Draws one open menu.
@MainActor
final class _NSMenuView: NSView {
    let ownerMenu: NSMenu
    private(set) var layout: _NSMenuLayout
    var highlightedRow: Int? {        // index into layout.rows
        didSet { if highlightedRow != oldValue { needsDisplay = true } }
    }
    var highlightedItem: NSMenuItem? { highlightedRow.map { layout.rows[$0].item } }

    init(menu: NSMenu, layout: _NSMenuLayout) {
        self.ownerMenu = menu
        self.layout = layout
        super.init(frame: NSRect(origin: .zero, size: layout.size))
        for row in layout.rows {
            if let v = row.item.view {
                v.frame = NSRect(x: layout.textLeft, y: row.frame.minY, width: v.frame.width, height: row.frame.height)
                addSubview(v)
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// The menu fills its window, so the whole window is client area: never a draggable
    /// title band (a borderless window's top 28 points otherwise count as one), or the
    /// platform turns moves and clicks over the first rows into non-client traffic.
    override var isOpaque: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // Accessibility (ADR-0013): the view is ignored; the window stands for the menu and the
    // drawn rows are its AXMenuItem children (an item with a custom view is that view).
    override func accessibilityChildren() -> [Any]? {
        layout.rows.compactMap { row -> Any? in
            if row.item.isSeparatorItem { return nil }
            return row.item.view ?? row.item
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: layout.font]
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        border.lineWidth = 1
        border.stroke()
        // Only the rows in view are drawn: a scrolled menu lists hundreds of rows, and
        // laying every title out on each repaint kept the main thread busy for the whole
        // frame (on Windows the menu froze and the process spun a core while it was open).
        let visible = dirtyRect.intersection(visibleRect.isEmpty ? bounds : visibleRect)
        for (i, row) in layout.rows.enumerated() where row.frame.intersects(visible) {
            let item = row.item
            let f = row.frame
            if item.isSeparatorItem {
                NSColor.separatorColor.setFill()
                NSBezierPath.fill(NSRect(x: f.minX + 10, y: f.midY.rounded() - 0.5, width: f.width - 20, height: 1))
                continue
            }
            let highlighted = i == highlightedRow && item.isEnabled
            if highlighted {
                NSColor.selectedMenuItemColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: f.minX + 5, y: f.minY, width: f.width - 10, height: f.height), xRadius: 4, yRadius: 4).fill()
            }
            let textColor: NSColor = highlighted ? .selectedMenuItemTextColor : (item.isEnabled ? .labelColor : .disabledControlTextColor)
            if item.view != nil { continue }
            var x = layout.textLeft + CGFloat(item.indentationLevel) * _NSMenuLayout.indentation
            if ownerMenu.showsStateColumn, item.state != .off {
                _drawStateMark(item.state, in: NSRect(x: f.minX + 7, y: f.midY - 5, width: 10, height: 10), color: textColor)
            }
            if let image = item.image {
                image.draw(in: NSRect(x: x, y: f.midY - _NSMenuLayout.imageSize / 2, width: _NSMenuLayout.imageSize, height: _NSMenuLayout.imageSize))
                x += _NSMenuLayout.imageSize + 6
            }
            var textAttrs = attrs
            textAttrs[.foregroundColor] = textColor
            let titleSize = item.title.size(withAttributes: textAttrs)
            item.title.draw(at: NSPoint(x: x, y: f.midY - titleSize.height / 2), withAttributes: textAttrs)
            let right = f.maxX - _NSMenuLayout.trailingPadding - (layout.hasSubmenus ? _NSMenuLayout.submenuArrowWidth : 0)
            let key = item._keyEquivalentLabel
            if !key.isEmpty {
                let ks = key.size(withAttributes: textAttrs)
                var keyAttrs = textAttrs
                if !highlighted && item.isEnabled { keyAttrs[.foregroundColor] = NSColor.secondaryLabelColor }
                key.draw(at: NSPoint(x: right - ks.width, y: f.midY - ks.height / 2), withAttributes: keyAttrs)
            }
            if item.hasSubmenu {
                let arrow = NSBezierPath()
                let ax = f.maxX - _NSMenuLayout.trailingPadding - 2
                arrow.move(to: NSPoint(x: ax - 4, y: f.midY - 4))
                arrow.line(to: NSPoint(x: ax, y: f.midY))
                arrow.line(to: NSPoint(x: ax - 4, y: f.midY + 4))
                arrow.lineWidth = 1.5
                arrow.lineCapStyle = .round
                arrow.lineJoinStyle = .round
                textColor.setStroke()
                arrow.stroke()
            }
        }
    }

    private func _drawStateMark(_ state: NSControl.StateValue, in rect: NSRect, color: NSColor) {
        let mark = NSBezierPath()
        if state == .mixed {
            mark.move(to: NSPoint(x: rect.minX + 1, y: rect.midY))
            mark.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY))
        } else {
            mark.move(to: NSPoint(x: rect.minX, y: rect.midY))
            mark.line(to: NSPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - 1))
            mark.line(to: NSPoint(x: rect.maxX, y: rect.minY + 1))
        }
        mark.lineWidth = 1.8
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        color.setStroke()
        mark.stroke()
    }
}

// MARK: Scrolling clip

/// The window's content when the menu is taller than the screen: the menu view scrolled
/// up by `offset` inside it, with an arrow band at the top or bottom edge wherever there
/// is more to scroll, as AppKit's long menus do. With a menu that fits it is a plain host.
@MainActor
final class _NSMenuClipView: NSView {
    static let arrowBandHeight: CGFloat = 16
    let menuView: _NSMenuView
    private let upArrow = _NSMenuScrollArrow(direction: -1)
    private let downArrow = _NSMenuScrollArrow(direction: 1)

    init(menuView: _NSMenuView) {
        self.menuView = menuView
        super.init(frame: NSRect(origin: .zero, size: menuView.frame.size))
        addSubview(menuView)
        addSubview(upArrow)
        addSubview(downArrow)
        layoutArrows()
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        offset = min(offset, maxOffset)
        layoutArrows()
    }

    var maxOffset: CGFloat { max(0, menuView.frame.height - bounds.height) }
    var offset: CGFloat = 0 {
        didSet {
            offset = min(max(offset, 0), maxOffset)
            menuView.setFrameOrigin(NSPoint(x: 0, y: -offset))
            layoutArrows()
            needsDisplay = true
        }
    }
    private func layoutArrows() {
        let h = _NSMenuClipView.arrowBandHeight
        upArrow.frame = NSRect(x: 0, y: 0, width: bounds.width, height: h)
        downArrow.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        upArrow.isHidden = offset <= 0
        downArrow.isHidden = offset >= maxOffset
    }
    func arrowDirection(at point: NSPoint) -> Int? {
        if !upArrow.isHidden, upArrow.frame.contains(point) { return -1 }
        if !downArrow.isHidden, downArrow.frame.contains(point) { return 1 }
        return nil
    }
    func scrollRowToVisible(_ rowFrame: NSRect) {
        guard maxOffset > 0 else { return }
        let band = _NSMenuClipView.arrowBandHeight
        let top = offset + (offset > 0 ? band : 0), bottom = offset + bounds.height - (offset < maxOffset ? band : 0)
        if rowFrame.minY < top { offset = rowFrame.minY - band }
        else if rowFrame.maxY > bottom { offset = rowFrame.maxY + band - bounds.height }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
    }

    // Accessibility: the clip is invisible; the window's children are the menu's rows.
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { menuView.accessibilityChildren() }
}

/// One scroll arrow band of a long menu.
@MainActor
final class _NSMenuScrollArrow: NSView {
    let direction: Int
    init(direction: Int) {
        self.direction = direction
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        let arrow = NSBezierPath()
        let cx = bounds.midX, cy = bounds.midY
        if direction < 0 {
            arrow.move(to: NSPoint(x: cx - 4, y: cy + 2)); arrow.line(to: NSPoint(x: cx, y: cy - 2)); arrow.line(to: NSPoint(x: cx + 4, y: cy + 2))
        } else {
            arrow.move(to: NSPoint(x: cx - 4, y: cy - 2)); arrow.line(to: NSPoint(x: cx, y: cy + 2)); arrow.line(to: NSPoint(x: cx + 4, y: cy - 2))
        }
        arrow.close()
        NSColor.labelColor.setFill()
        arrow.fill()
    }
}

// MARK: Window

/// The borderless window a menu opens in. It never becomes key: the window that opened the
/// menu keeps the keyboard, and NSApplication hands the events to the tracker.
@MainActor
final class _NSMenuWindow: NSPanel {
    let menuView: _NSMenuView
    private let clip: _NSMenuClipView
    init(menu: NSMenu, layout: _NSMenuLayout) {
        menuView = _NSMenuView(menu: menu, layout: layout)
        clip = _NSMenuClipView(menuView: menuView)
        super.init(contentRect: NSRect(origin: .zero, size: layout.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        contentView = clip
        isReleasedWhenClosed = false
    }
    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: Scrolling (a menu taller than the screen)

    /// How far the rows are scrolled up, in points (0 when the whole menu fits).
    var scrollOffset: CGFloat {
        get { clip.offset }
        set {
            // The clip takes the window's (possibly clamped) size before the offset applies.
            let size = contentRect(forFrameRect: frame).size
            if clip.frame.size != size { clip.setFrameSize(size) }
            clip.offset = newValue
        }
    }
    var maxScrollOffset: CGFloat { clip.maxOffset }
    var isScrollable: Bool { clip.maxOffset > 0 }
    func scroll(by delta: CGFloat) { clip.offset += delta }
    /// The scroll arrow band under a window point: -1 the top band, 1 the bottom one.
    func scrollDirection(at pointInWindow: NSPoint) -> Int? { clip.arrowDirection(at: clip.convert(pointInWindow, from: nil)) }
    /// Scrolls so the row (menu view coordinates) is fully visible, clear of the arrows.
    func scrollRowToVisible(_ rowFrame: NSRect) { clip.scrollRowToVisible(rowFrame) }

    // Accessibility (ADR-0013): an open menu is an AXMenu at the top of its window's tree
    // (UI Automation's Menu, AT-SPI's menu), labelled by the menu's title.
    override func accessibilityRole() -> NSAccessibility.Role? { .menu }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { nil }
    override func accessibilityLabel() -> String? { menuView.ownerMenu.title.isEmpty ? nil : menuView.ownerMenu.title }
    override func accessibilityPerformCancel() -> Bool { menuView.ownerMenu._a11yCancel() }
}

// MARK: Tracker

/// Where a menu is placed relative to a rectangle in screen coordinates.
enum _NSMenuPlacement {
    /// A pop-up button: the item at `itemIndex` sits over the anchor rectangle, its title
    /// aligned with the button's.
    case overAnchor(itemIndex: Int, titleInset: CGFloat)
    /// A pull-down button: the menu hangs below (or beside) the anchor.
    case besideAnchor(edge: NSRectEdge)
    /// A context menu: the top-left corner at the anchor's top-left; with `itemIndex`, that
    /// item's top-left instead.
    case atPoint(itemIndex: Int?)
}

/// Tracks one open menu hierarchy: windows per open level, highlight, submenus, keyboard.
@MainActor
final class _NSMenuTracker {
    private(set) static var current: _NSMenuTracker?
    static var isTracking: Bool { current != nil }

    struct Level {
        let menu: NSMenu
        let window: _NSMenuWindow
        let parentRow: Int?         // row in the parent level that opened this submenu
    }
    private(set) var levels: [Level] = []
    private let completion: @MainActor (NSMenuItem?) -> Void
    private let font: NSFont
    private let openedWithMouseDown: Bool
    private let skipsFirstItem: Bool
    private let minimumWidth: CGFloat
    private var openPoint: NSPoint?
    private var movedSinceOpen = false
    private var sawFirstMouseUp = false
    private(set) var finished = false
    private(set) var chosenItem: NSMenuItem?
    /// The control that opened the menu (a pop-up button): its accessibility children
    /// are the open menu, so it hears when the menu comes and goes.
    weak var accessibilityOwner: NSView? {
        didSet { if let o = accessibilityOwner, let m = rootMenu { o._accessibilityMenuDidOpen(m) } }
    }

    var rootMenu: NSMenu? { levels.first?.menu }
    var highlightedItem: NSMenuItem? { levels.last?.window.menuView.highlightedItem }

    /// Opens `menu` and starts tracking. The completion runs after the windows close and
    /// the chosen item's action has been sent.
    @discardableResult
    static func begin(menu: NSMenu, anchor: NSRect, placement: _NSMenuPlacement, font: NSFont? = nil, openedWithMouseDown: Bool,
                      skipsFirstItem: Bool = false, minimumWidth: CGFloat = 0,
                      completion: @escaping @MainActor (NSMenuItem?) -> Void = { _ in }) -> _NSMenuTracker {
        current?.cancel()
        let t = _NSMenuTracker(font: font ?? menu.font ?? NSFont.menuFont(ofSize: NSFont.systemFontSize),
                               openedWithMouseDown: openedWithMouseDown, skipsFirstItem: skipsFirstItem, minimumWidth: minimumWidth, completion: completion)
        current = t
        t.openPoint = Platform.backend.mouseLocation
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        t.open(menu, anchor: anchor, placement: placement, parentRow: nil)
        return t
    }

    private init(font: NSFont, openedWithMouseDown: Bool, skipsFirstItem: Bool, minimumWidth: CGFloat, completion: @escaping @MainActor (NSMenuItem?) -> Void) {
        self.font = font
        self.openedWithMouseDown = openedWithMouseDown
        self.skipsFirstItem = skipsFirstItem
        self.minimumWidth = minimumWidth
        self.completion = completion
    }

    func isMenuWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return levels.contains { $0.window === window }
    }

    // MARK: Opening and closing levels

    private func open(_ menu: NSMenu, anchor: NSRect, placement: _NSMenuPlacement, parentRow: Int?) {
        menu.update()
        menu.delegate?.menuWillOpen(menu)
        let layout = _NSMenuLayout(menu: menu, font: font, skippingFirst: parentRow == nil && skipsFirstItem, minimumWidth: parentRow == nil ? minimumWidth : 0)
        let window = _NSMenuWindow(menu: menu, layout: layout)
        var origin: NSPoint       // bottom-left of the window, screen coordinates
        let size = layout.size
        switch placement {
        case .overAnchor(let itemIndex, let titleInset):
            let row = layout.row(forItemIndex: itemIndex) ?? layout.rows.first
            let rowMidY = row.map { $0.frame.midY } ?? size.height / 2
            origin = NSPoint(x: anchor.minX + titleInset - layout.textLeft, y: anchor.midY + rowMidY - size.height)
        case .besideAnchor(let edge):
            switch edge {
            case .maxX: origin = NSPoint(x: anchor.maxX, y: anchor.maxY - size.height)
            case .minX: origin = NSPoint(x: anchor.minX - size.width, y: anchor.maxY - size.height)
            default: origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height)
            }
        case .atPoint(let itemIndex):
            let rowTop = itemIndex.flatMap { layout.row(forItemIndex: $0) }?.frame.minY ?? 0
            origin = NSPoint(x: anchor.minX, y: anchor.maxY + rowTop - size.height)
        }
        // Keep the menu on the screen that holds the anchor.
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        var frameSize = size
        var scrollOffset: CGFloat = 0
        if let visible = screen?.visibleFrame {
            if size.height > visible.height {
                // Taller than the screen: the window takes the screen's height and the rows
                // scroll inside it (arrow bands at the edges). A pop-up still opens with its
                // selected item over the button where the scroll range allows.
                frameSize.height = visible.height.rounded(.down)
                origin.y = visible.minY
                if case .overAnchor(let itemIndex, _) = placement, let row = layout.row(forItemIndex: itemIndex) {
                    let rowCenterFromTop = visible.maxY - anchor.midY        // where the row should sit, from the window's top
                    scrollOffset = row.frame.midY - rowCenterFromTop
                }
                scrollOffset = min(max(scrollOffset, 0), size.height - frameSize.height)
            }
            if origin.x + frameSize.width > visible.maxX { origin.x = max(visible.minX, visible.maxX - frameSize.width) }
            if origin.x < visible.minX { origin.x = visible.minX }
            if origin.y < visible.minY {
                // No room below: a pull-down flips above its anchor, anything else slides up.
                if case .besideAnchor(let edge) = placement, edge != .minX, edge != .maxX, anchor.maxY + frameSize.height <= visible.maxY {
                    origin.y = anchor.maxY
                } else {
                    origin.y = visible.minY
                }
            }
            if origin.y + frameSize.height > visible.maxY { origin.y = max(visible.minY, visible.maxY - frameSize.height) }
        }
        window.setFrame(NSRect(origin: origin, size: frameSize), display: false)
        window.scrollOffset = scrollOffset
        levels.append(Level(menu: menu, window: window, parentRow: parentRow))
        window.orderFront(nil)
        window._accessibilityNotify(.menuOpened(window._accessibilityElementID))
        // A pop-up opens with its selected item highlighted, as AppKit's does, so Down
        // moves to the next item rather than back to the first (and Return re-chose the
        // current one: the binding never changed).
        if case .overAnchor(let itemIndex, _) = placement, let r = layout.rows.firstIndex(where: { $0.index == itemIndex }),
           !layout.rows[r].item.isSeparatorItem, layout.rows[r].item.isEnabled {
            setHighlight(r, in: levels.count - 1, openSubmenus: false)
        }
        if parentRow != nil, levels.count >= 2 {
            // The parent item now shows its submenu open (UIA ExpandCollapse).
            let parent = levels[levels.count - 2]
            parent.window._accessibilityNotify(.value(parent.window.menuView.layout.rows[parentRow!].item._accessibilityElementID))
        }
    }

    private func closeLevels(from index: Int) {
        guard index < levels.count else { return }
        let closing = levels[index...]
        levels.removeSubrange(index...)
        for level in closing.reversed() {
            level.window._accessibilityNotify(.menuClosed(level.window._accessibilityElementID))
            level.window.menuView.highlightedRow = nil
            level.window.close()
            level.menu.delegate?.menuDidClose(level.menu)
        }
        if index == 0, let owner = accessibilityOwner, let root = closing.first?.menu { owner._accessibilityMenuDidClose(root) }
    }

    private func openSubmenu(ofRow row: Int, in levelIndex: Int) {
        let level = levels[levelIndex]
        let r = level.window.menuView.layout.rows[row]
        guard let submenu = r.item.submenu, r.item.isEnabled else { return }
        if levels.count > levelIndex + 1 {
            if levels[levelIndex + 1].parentRow == row { return }
            closeLevels(from: levelIndex + 1)
        }
        let rowRect = level.window.menuView.convert(r.frame, to: nil)
        let screenRect = level.window.convertToScreen(rowRect)
        open(submenu, anchor: NSRect(x: screenRect.maxX - 4, y: screenRect.minY, width: 0, height: screenRect.height + _NSMenuLayout.verticalPadding),
             placement: .besideAnchor(edge: .maxX), parentRow: row)
    }

    // MARK: Highlight

    private func setHighlight(_ row: Int?, in levelIndex: Int, openSubmenus: Bool) {
        let level = levels[levelIndex]
        let view = level.window.menuView
        if view.highlightedRow != row {
            view.highlightedRow = row
            if let row, !keyboardScrollSuppressed { level.window.scrollRowToVisible(view.layout.rows[row].frame) }
            level.menu.delegate?.menu(level.menu, willHighlight: row.map { view.layout.rows[$0].item })
            // Keyboard (or mouse) navigation is on this item: screen readers follow focus.
            if let row { level.window._accessibilityNotify(.focus(view.layout.rows[row].item._accessibilityElementID)) }
        }
        if let row, openSubmenus, view.layout.rows[row].item.hasSubmenu, view.layout.rows[row].item.isEnabled {
            openSubmenu(ofRow: row, in: levelIndex)
        } else if levels.count > levelIndex + 1, levels[levelIndex + 1].parentRow != row {
            closeLevels(from: levelIndex + 1)
        }
    }

    /// The deepest level whose window contains the screen point, and the row under it (none
    /// over a scroll arrow band).
    private func hit(_ point: NSPoint) -> (level: Int, row: Int?)? {
        for (i, level) in levels.enumerated().reversed() where level.window.frame.contains(point) {
            let inWindow = level.window.convertPoint(fromScreen: point)
            if level.window.scrollDirection(at: inWindow) != nil { return (i, nil) }
            let local = level.window.menuView.convert(inWindow, from: nil)
            let rows = level.window.menuView.layout.rows
            return (i, rows.firstIndex { $0.frame.contains(local) })
        }
        return nil
    }

    // MARK: Scrolling long menus

    /// True while the mouse drives the highlight: the rows under the pointer never scroll
    /// away from it (only keyboard navigation scrolls the highlighted row into view).
    private var keyboardScrollSuppressed = false
    private var scrollTimer: _NSFrameTimer?
    private var scrollingLevel: Int?
    private var scrollingDirection = 0

    /// Hovering an arrow band scrolls one row every 50 ms until the pointer leaves it.
    private func updateArrowScrolling(at point: NSPoint) {
        var found: (Int, Int)? = nil
        for (i, level) in levels.enumerated().reversed() where level.window.frame.contains(point) {
            if let d = level.window.scrollDirection(at: level.window.convertPoint(fromScreen: point)) { found = (i, d) }
            break
        }
        guard let (levelIndex, direction) = found else { stopArrowScrolling(); return }
        if scrollTimer != nil, scrollingLevel == levelIndex, scrollingDirection == direction { return }
        stopArrowScrolling()
        scrollingLevel = levelIndex
        scrollingDirection = direction
        let step = { [weak self] in
            guard let self, let i = self.scrollingLevel, i < self.levels.count else { return }
            let w = self.levels[i].window
            // The pointer left the band (no mouse-moved event reports a pointer outside every
            // window): stop rather than scroll to the end.
            let pointer = Platform.backend.mouseLocation
            guard w.frame.contains(pointer), w.scrollDirection(at: w.convertPoint(fromScreen: pointer)) == self.scrollingDirection else { self.stopArrowScrolling(); return }
            w.scroll(by: CGFloat(self.scrollingDirection) * _NSMenuLayout.itemHeight)
            if (self.scrollingDirection < 0 && w.scrollOffset <= 0) || (self.scrollingDirection > 0 && w.scrollOffset >= w.maxScrollOffset) { self.stopArrowScrolling() }
        }
        step()
        scrollTimer = _NSFrameTimer(delay: 0.05, interval: 0.05, action: step)
    }
    private func stopArrowScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        scrollingLevel = nil
        scrollingDirection = 0
    }
    private func scrollWheel(_ event: NSEvent) {
        let p = screenPoint(of: event)
        let index = levels.indices.reversed().first { levels[$0].window.frame.contains(p) } ?? levels.indices.last
        guard let index else { return }
        let w = levels[index].window
        guard w.isScrollable else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * _NSMenuLayout.itemHeight
        w.scroll(by: -delta)
        // The row under the (unmoved) pointer changed: refresh the highlight.
        if let h = hit(p) {
            keyboardScrollSuppressed = true
            defer { keyboardScrollSuppressed = false }
            if let row = h.row, !levels[h.level].window.menuView.layout.rows[row].item.isSeparatorItem { setHighlight(row, in: h.level, openSubmenus: false) }
            else { setHighlight(nil, in: h.level, openSubmenus: false) }
        }
    }

    private func screenPoint(of event: NSEvent) -> NSPoint {
        if let w = event.window { return w.convertPoint(toScreen: event.locationInWindow) }
        return event.locationInWindow
    }

    // MARK: Events (from NSApplication.sendEvent)

    /// Handles an event while tracking. Every event is consumed.
    func handle(_ event: NSEvent) {
        if NSView._traceInvalidation, event.type != .keyDown, event.type != .keyUp, event.type != .flagsChanged {
            let p = screenPoint(of: event)
            let h = hit(p).map { "level \($0.level) row \($0.row.map(String.init) ?? "none")" } ?? "outside"
            NSView._trace("menu mouse \(event.type) at \(p) from \(event.window.map { "'\($0.title)'" } ?? "no window") (\(event.locationInWindow)) menus \(levels.map { $0.window.frame }) -> \(h)")
        }
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let p = screenPoint(of: event)
            if let o = openPoint, abs(p.x - o.x) > 3 || abs(p.y - o.y) > 3 { movedSinceOpen = true }
            updateArrowScrolling(at: p)
            keyboardScrollSuppressed = true
            defer { keyboardScrollSuppressed = false }
            if let h = hit(p) {
                if let row = h.row {
                    let item = levels[h.level].window.menuView.layout.rows[row].item
                    setHighlight(item.isSeparatorItem ? nil : row, in: h.level, openSubmenus: true)
                } else {
                    setHighlight(nil, in: h.level, openSubmenus: false)
                }
                // Levels deeper than the hovered one close only when another item is hovered
                // (handled by setHighlight); shallower levels keep the parent item highlighted.
            } else if let last = levels.indices.last, levels[last].window.menuView.highlightedRow != nil,
                      !(levels[last].window.menuView.highlightedItem?.hasSubmenu ?? false) {
                levels[last].window.menuView.highlightedRow = nil
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let p = screenPoint(of: event)
            if hit(p) == nil { cancel() }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let p = screenPoint(of: event)
            if openedWithMouseDown && !sawFirstMouseUp && !movedSinceOpen {
                // Releasing the opening click without moving leaves the menu open.
                sawFirstMouseUp = true
                return
            }
            sawFirstMouseUp = true
            if let h = hit(p) {
                if let row = h.row {
                    let item = levels[h.level].window.menuView.layout.rows[row].item
                    if item.hasSubmenu { openSubmenu(ofRow: row, in: h.level) }
                    else if item.isEnabled && !item.isSeparatorItem { choose(level: h.level, row: row) }
                }
            } else {
                cancel()
            }
        case .keyDown:
            keyDown(event)
        case .scrollWheel:
            scrollWheel(event)
        default:
            break
        }
    }

    private func keyDown(_ event: NSEvent) {
        guard let last = levels.indices.last else { return }
        let view = levels[last].window.menuView
        let rows = view.layout.rows
        func selectable(_ i: Int) -> Bool { let it = rows[i].item; return !it.isSeparatorItem && it.isEnabled }
        func move(_ delta: Int) {
            guard !rows.isEmpty else { return }
            var i = view.highlightedRow ?? (delta > 0 ? -1 : rows.count)
            for _ in 0..<rows.count {
                i = (i + delta + rows.count) % rows.count
                if selectable(i) { setHighlight(i, in: last, openSubmenus: false); return }
            }
        }
        switch event.keyCode {
        case 125: move(1)                      // down
        case 126: move(-1)                     // up
        case 53:                               // escape
            if levels.count > 1 { closeLevels(from: levels.count - 1) } else { cancel() }
        case 123:                              // left
            if levels.count > 1 { closeLevels(from: levels.count - 1) }
        case 124:                              // right
            if let r = view.highlightedRow, rows[r].item.hasSubmenu {
                openSubmenu(ofRow: r, in: last)
                if let deeper = levels.indices.last, deeper != last { keyDown(NSEvent._menuKey(125)) }
            }
        case 36, 76, 49:                       // return, enter, space
            if let r = view.highlightedRow {
                if rows[r].item.hasSubmenu { openSubmenu(ofRow: r, in: last) } else { choose(level: last, row: r) }
            }
        default:
            // Type-select: the next item whose title starts with the typed character.
            guard let c = event.charactersIgnoringModifiers?.lowercased(), !c.isEmpty, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return }
            let start = view.highlightedRow ?? -1
            for k in 1...max(1, rows.count) {
                let i = (start + k) % rows.count
                if selectable(i), rows[i].item.title.lowercased().hasPrefix(c) { setHighlight(i, in: last, openSubmenus: false); break }
            }
        }
    }

    // MARK: Accessibility (ADR-0013)

    /// The level showing `menu`, if it is open.
    func levelIndex(of menu: NSMenu) -> Int? { levels.firstIndex { $0.menu === menu } }

    /// Where an open item is drawn, in screen coordinates.
    func screenFrame(of item: NSMenuItem) -> NSRect? {
        for level in levels {
            let view = level.window.menuView
            guard let row = view.layout.rows.first(where: { $0.item === item }) else { continue }
            return level.window.convertToScreen(view.convert(row.frame, to: nil))
        }
        return nil
    }

    func isHighlighted(_ item: NSMenuItem) -> Bool { levels.contains { $0.window.menuView.highlightedItem === item } }

    /// Assistive technology pressed an open item: open its submenu, or choose it.
    func accessibilityActivate(_ item: NSMenuItem) -> Bool {
        for (i, level) in levels.enumerated() {
            let rows = level.window.menuView.layout.rows
            guard let r = rows.firstIndex(where: { $0.item === item }) else { continue }
            guard item.isEnabled, !item.isSeparatorItem else { return false }
            if item.hasSubmenu {
                setHighlight(r, in: i, openSubmenus: false)
                openSubmenu(ofRow: r, in: i)
            } else {
                choose(level: i, row: r)
            }
            return true
        }
        return false
    }

    /// Closes the level showing `menu` and the ones above it (the whole menu when it is
    /// the root).
    func accessibilityClose(_ menu: NSMenu) -> Bool {
        guard let i = levelIndex(of: menu) else { return false }
        if i == 0 { cancel() } else { closeLevels(from: i) }
        return true
    }

    // MARK: Finishing

    private func choose(level: Int, row: Int) {
        let l = levels[level]
        let r = l.window.menuView.layout.rows[row]
        end(item: r.item, menu: l.menu, index: r.index)
    }

    /// Closes every open level without choosing anything.
    func cancel() { end(item: nil, menu: nil, index: nil) }

    private func end(item: NSMenuItem?, menu: NSMenu?, index: Int?) {
        guard !finished else { return }
        finished = true
        chosenItem = item
        stopArrowScrolling()
        let root = levels.first?.menu
        closeLevels(from: 0)
        if _NSMenuTracker.current === self { _NSMenuTracker.current = nil }
        if let root { NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: root) }
        if let menu, let index { menu.performActionForItem(at: index) }
        completion(item)
    }
}

extension NSEvent {
    /// A synthetic key-down for menu navigation (no window, no characters).
    static func _menuKey(_ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode)!
    }
}
