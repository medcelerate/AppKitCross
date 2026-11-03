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

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: layout.font]
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        border.lineWidth = 1
        border.stroke()
        for (i, row) in layout.rows.enumerated() {
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

// MARK: Window

/// The borderless window a menu opens in. It never becomes key: the window that opened the
/// menu keeps the keyboard, and NSApplication hands the events to the tracker.
@MainActor
final class _NSMenuWindow: NSPanel {
    let menuView: _NSMenuView
    init(menu: NSMenu, layout: _NSMenuLayout) {
        menuView = _NSMenuView(menu: menu, layout: layout)
        super.init(contentRect: NSRect(origin: .zero, size: layout.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        contentView = menuView
        isReleasedWhenClosed = false
    }
    required init?(coder: NSCoder) { nil }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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
        if let visible = screen?.visibleFrame {
            if origin.x + size.width > visible.maxX { origin.x = max(visible.minX, visible.maxX - size.width) }
            if origin.x < visible.minX { origin.x = visible.minX }
            if origin.y < visible.minY {
                // No room below: a pull-down flips above its anchor, anything else slides up.
                if case .besideAnchor(let edge) = placement, edge != .minX, edge != .maxX, anchor.maxY + size.height <= visible.maxY {
                    origin.y = anchor.maxY
                } else {
                    origin.y = visible.minY
                }
            }
            if origin.y + size.height > visible.maxY { origin.y = max(visible.minY, visible.maxY - size.height) }
        }
        window.setFrame(NSRect(origin: origin, size: size), display: false)
        levels.append(Level(menu: menu, window: window, parentRow: parentRow))
        window.orderFront(nil)
    }

    private func closeLevels(from index: Int) {
        guard index < levels.count else { return }
        let closing = levels[index...]
        levels.removeSubrange(index...)
        for level in closing.reversed() {
            level.window.menuView.highlightedRow = nil
            level.window.close()
            level.menu.delegate?.menuDidClose(level.menu)
        }
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
            level.menu.delegate?.menu(level.menu, willHighlight: row.map { view.layout.rows[$0].item })
        }
        if let row, openSubmenus, view.layout.rows[row].item.hasSubmenu, view.layout.rows[row].item.isEnabled {
            openSubmenu(ofRow: row, in: levelIndex)
        } else if levels.count > levelIndex + 1, levels[levelIndex + 1].parentRow != row {
            closeLevels(from: levelIndex + 1)
        }
    }

    /// The deepest level whose window contains the screen point, and the row under it.
    private func hit(_ point: NSPoint) -> (level: Int, row: Int?)? {
        for (i, level) in levels.enumerated().reversed() where level.window.frame.contains(point) {
            let local = level.window.menuView.convert(level.window.convertPoint(fromScreen: point), from: nil)
            let rows = level.window.menuView.layout.rows
            return (i, rows.firstIndex { $0.frame.contains(local) })
        }
        return nil
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
