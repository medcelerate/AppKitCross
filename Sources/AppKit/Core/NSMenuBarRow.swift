// The menu bar row of a unified caption (ADR-0053). On Windows a window whose unified
// title bar is its caption has no non-client area for user32's HMENU bar, which Windows
// places above the client area from the window style alone, so the application's main
// menu is drawn by the package in a row directly under the title band, as an overlay root
// like the toolbar. The row behaves as the Windows menu bar does: a click opens a menu,
// the pointer moving across the titles switches between open menus, Alt+letter opens the
// menu whose title starts with the letter, F10 or an Alt tap enters keyboard mode (a title
// highlighted, Left/Right to move, Down or Return to open, Escape to leave); the menus
// themselves are the package's pop-ups (NSMenuPopUp.swift). Key equivalents keep their
// path through `NSApplication.sendEvent`, HMENU bar or not.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
final class _NSMenuBarRowView: NSView {
    static let height: CGFloat = Win32WindowPolicy.menuBarRowHeight
    static let font: NSFont = NSFont.menuBarFont(ofSize: 13)
    private static let titlePadding: CGFloat = 10
    private static let leadingMargin: CGFloat = 6

    /// A top-level item and where its title is drawn (the row is flipped: y from the top).
    struct Title { let item: NSMenuItem; let frame: NSRect }
    private(set) var titles: [Title] = []
    /// The title under the pointer.
    private(set) var hoveredIndex: Int? { didSet { if hoveredIndex != oldValue { needsDisplay = true } } }
    /// The title highlighted in keyboard mode (no menu open yet).
    private(set) var keyboardIndex: Int? { didSet { if keyboardIndex != oldValue { needsDisplay = true } } }
    /// The title whose menu is open.
    private(set) var openIndex: Int? { didSet { if openIndex != oldValue { needsDisplay = true } } }
    private var openGeneration = 0
    /// The pointer's last reported screen position, and where it was when the open menu
    /// opened. The pointer crossing to another title switches menus only once it has
    /// really moved since: Windows re-reports the unchanged position when a menu window
    /// opens or closes, which after Left or Right switched menus from the keyboard would
    /// hand the bar straight back to the title the pointer rests on (native menu bars let
    /// the keyboard win until the mouse moves).
    private var lastPointerScreen: NSPoint?
    private var pointerAtOpen: NSPoint?
    /// Alt went down and no key or click followed yet: releasing it toggles keyboard mode.
    private var altArmed = false

    var isKeyboardActive: Bool { keyboardIndex != nil }
    var isMenuOpen: Bool { openIndex != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { true }
    /// A menu bar never drags the window, on Windows or on macOS.
    override var mouseDownCanMoveWindow: Bool { false }
    // The application's AXMenuBar already stands for the main menu (ADR-0013).
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { [] }

    // MARK: Content

    /// The main menu's visible top-level items with a submenu, as the HMENU bar lists them.
    static func menuItems() -> [NSMenuItem] {
        guard let menu = NSApplication._shared?.mainMenu else { return [] }
        return menu.items.filter { !$0.isHidden && !$0.isSeparatorItem && $0.submenu != nil }
    }

    /// Re-reads the main menu; lays the titles out again only when they changed.
    func reload() {
        let items = _NSMenuBarRowView.menuItems()
        let same = items.count == titles.count && zip(items, titles).allSatisfy { $0 === $1.item && $0.title == $1.item.title }
        if same, !titles.isEmpty || items.isEmpty { return }
        layoutTitles(items)
    }

    private func layoutTitles(_ items: [NSMenuItem]) {
        let attrs: [NSAttributedString.Key: Any] = [.font: _NSMenuBarRowView.font]
        var x = _NSMenuBarRowView.leadingMargin
        var out: [Title] = []
        for item in items {
            let w = item.title.size(withAttributes: attrs).width.rounded(.up) + 2 * _NSMenuBarRowView.titlePadding
            out.append(Title(item: item, frame: NSRect(x: x, y: 0, width: w, height: bounds.height)))
            x += w
        }
        titles = out
        if let k = keyboardIndex, k >= titles.count { keyboardIndex = titles.isEmpty ? nil : titles.count - 1 }
        if let o = openIndex, o >= titles.count { closeMenu() }
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.height != frame.height
        super.setFrameSize(newSize)
        if changed { layoutTitles(titles.map { $0.item }) }
    }

    /// The title at a point in the row's coordinates.
    func titleIndex(at point: NSPoint) -> Int? { titles.firstIndex { $0.frame.contains(point) } }
    /// The title at a screen point (the menu tracker asks while a menu is open).
    func titleIndex(atScreenPoint p: NSPoint) -> Int? {
        guard let w = window else { return nil }
        let local = convert(w.convertPoint(fromScreen: p), from: nil)
        return titleIndex(at: local)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.isDark
        let key = window?.isKeyWindow ?? true
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
        // The hairline under the bar, as under Windows' own.
        NSColor.separatorColor.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        let highlighted = openIndex ?? keyboardIndex ?? hoveredIndex
        for (i, t) in titles.enumerated() {
            guard t.frame.intersects(dirtyRect) else { continue }
            if i == highlighted, t.item.isEnabled {
                let stronger = i == openIndex || i == keyboardIndex
                NSColor.labelColor.withAlphaComponent(dark ? (stronger ? 0.18 : 0.12) : (stronger ? 0.10 : 0.06)).setFill()
                NSBezierPath(roundedRect: t.frame.insetBy(dx: 1, dy: 3), xRadius: 4, yRadius: 4).fill()
            }
            let color: NSColor = !t.item.isEnabled ? .disabledControlTextColor : key ? .labelColor : .secondaryLabelColor
            let attrs: [NSAttributedString.Key: Any] = [.font: _NSMenuBarRowView.font, .foregroundColor: color]
            let size = t.item.title.size(withAttributes: attrs)
            let origin = NSPoint(x: t.frame.minX + _NSMenuBarRowView.titlePadding, y: ((bounds.height - size.height) / 2).rounded())
            t.item.title.draw(at: origin, withAttributes: attrs)
            if isKeyboardActive || isMenuOpen, let first = t.item.title.first, !first.isWhitespace {
                // The access key underlined while the keyboard drives the bar, as Windows does.
                let cw = String(first).size(withAttributes: attrs).width
                color.setFill()
                NSBezierPath.fill(NSRect(x: origin.x, y: origin.y + size.height - 2, width: cw, height: 1))
            }
        }
    }

    // MARK: Mouse

    /// The window reports every pointer move (and the pointer leaving, as nil).
    func updateHover(_ windowPoint: NSPoint?) {
        guard let p = windowPoint, !isHidden else { hoveredIndex = nil; return }
        if let w = window { lastPointerScreen = w.convertPoint(toScreen: p) }
        let local = convert(p, from: nil)
        hoveredIndex = bounds.contains(local) ? titleIndex(at: local) : nil
    }

    override func mouseDown(with event: NSEvent) {
        altArmed = false
        let local = convert(event.locationInWindow, from: nil)
        guard let i = titleIndex(at: local), titles[i].item.isEnabled else { deactivateKeyboard(); return }
        if openIndex == i { closeMenu() } else { openMenu(at: i, openedWithMouseDown: true) }
    }
    override func mouseMoved(with event: NSEvent) { updateHover(event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { hoveredIndex = nil }

    // MARK: Menus

    /// Opens the menu of the title at `index` (closing an open one), as the tracker of
    /// NSMenuPopUp.swift hanging below the title; `fromKeyboard` highlights its first item.
    func openMenu(at index: Int, openedWithMouseDown: Bool, fromKeyboard: Bool = false) {
        guard titles.indices.contains(index), let menu = titles[index].item.submenu, titles[index].item.isEnabled, let w = window else { return }
        openGeneration += 1
        let generation = openGeneration
        keyboardIndex = nil
        openIndex = index
        pointerAtOpen = lastPointerScreen
        _NSMenuBarRowView.active = self
        let anchor = w.convertToScreen(convert(titles[index].frame, to: nil))
        let tracker = _NSMenuTracker.begin(menu: menu, anchor: anchor, placement: .besideAnchor(edge: .minY), font: _NSMenuBarRowView.font,
                                           openedWithMouseDown: openedWithMouseDown) { [weak self] _ in
            guard let self, self.openGeneration == generation else { return }
            self.openIndex = nil
            if _NSMenuBarRowView.active === self, !self.isKeyboardActive { _NSMenuBarRowView.active = nil }
        }
        tracker.menuBarRow = self
        if fromKeyboard { tracker.handle(NSEvent._menuKey(125)) }
    }

    func closeMenu() {
        guard openIndex != nil else { return }
        openGeneration += 1
        openIndex = nil
        if let t = _NSMenuTracker.current, t.menuBarRow === self { t.cancel() }
        if _NSMenuBarRowView.active === self, !isKeyboardActive { _NSMenuBarRowView.active = nil }
    }

    /// Whether the pointer, now at screen point `p` over a title (the menu tracker asks while
    /// a menu is open), has moved since the open menu opened; records the position.
    func pointerMoved(toScreen p: NSPoint) -> Bool {
        defer { lastPointerScreen = p }
        guard let o = pointerAtOpen else { return true }
        return abs(p.x - o.x) > 2 || abs(p.y - o.y) > 2
    }

    /// Left or Right while a menu is open: the neighbouring title's menu (wrapping).
    func openAdjacentMenu(_ delta: Int) {
        guard !titles.isEmpty else { return }
        let from = openIndex ?? keyboardIndex ?? (delta > 0 ? -1 : titles.count)
        var i = from
        for _ in 0..<titles.count {
            i = (i + delta + titles.count) % titles.count
            if titles[i].item.isEnabled { openMenu(at: i, openedWithMouseDown: false, fromKeyboard: true); return }
        }
    }

    // MARK: Keyboard mode

    /// Enters keyboard mode with the first enabled title highlighted (F10, an Alt tap).
    func activateKeyboard() {
        guard !isHidden, let first = titles.firstIndex(where: { $0.item.isEnabled }) else { return }
        if isMenuOpen { closeMenu() }
        keyboardIndex = first
        _NSMenuBarRowView.active = self
    }

    func deactivateKeyboard() {
        altArmed = false
        guard isKeyboardActive else { return }
        keyboardIndex = nil
        if _NSMenuBarRowView.active === self, !isMenuOpen { _NSMenuBarRowView.active = nil }
    }

    private func moveKeyboard(_ delta: Int) {
        guard let k = keyboardIndex, !titles.isEmpty else { return }
        var i = k
        for _ in 0..<titles.count {
            i = (i + delta + titles.count) % titles.count
            if titles[i].item.isEnabled { keyboardIndex = i; return }
        }
    }

    /// The title whose access key is `character`: the first letter of the title, as
    /// Windows takes it when a title carries no `&` marker (AppKit titles never do).
    func titleIndex(forMnemonic character: Character) -> Int? {
        let c = String(character).lowercased()
        return titles.firstIndex { t in
            guard t.item.isEnabled, let first = t.item.title.first(where: { !$0.isWhitespace }) else { return false }
            return String(first).lowercased() == c
        }
    }

    /// A key while the row is in keyboard mode. Consumes what the bar understands.
    func handleKeyboardModeKey(_ event: NSEvent) -> Bool {
        guard isKeyboardActive else { return false }
        let plainModifiers = event.modifierFlags.intersection([.command, .control, .shift]).isEmpty
        switch event.keyCode {
        case 123: moveKeyboard(-1); return true                                   // left
        case 124: moveKeyboard(1); return true                                    // right
        case 125, 36, 76, 49:                                                     // down, return, enter, space
            if let k = keyboardIndex { openMenu(at: k, openedWithMouseDown: false, fromKeyboard: true) }
            return true
        case 53, 109: deactivateKeyboard(); return true                           // escape, F10 again
        default:
            if plainModifiers, let c = event.charactersIgnoringModifiers?.first, let i = titleIndex(forMnemonic: c) {
                openMenu(at: i, openedWithMouseDown: false, fromKeyboard: true)
                return true
            }
            deactivateKeyboard()
            return false
        }
    }

    // MARK: Application routing

    /// The row that owns the keyboard: in keyboard mode, or showing a menu.
    private(set) static weak var active: _NSMenuBarRowView?

    /// Called by `NSApplication.sendEvent` for every key and mouse event (after the menu
    /// key equivalents, which keep precedence). Returns true when the row took the event.
    static func _handleApplicationEvent(_ event: NSEvent) -> Bool {
        let window = event.window ?? NSApplication._shared?.keyWindow
        guard let row = active ?? window?._menuBarRow, !row.isHidden, row.window != nil else { return false }
        switch event.type {
        case .flagsChanged:
            let altDown = event.modifierFlags.contains(.option)
            if altDown {
                // Alt alone, no other modifier: arm; a key pressed with it disarms below.
                row.altArmed = event.modifierFlags.intersection([.command, .control, .shift]).isEmpty
            } else if row.altArmed {
                row.altArmed = false
                if row.isKeyboardActive { row.deactivateKeyboard() } else if !row.isMenuOpen { row.activateKeyboard() }
            }
            return false
        case .keyDown:
            row.altArmed = false
            if row.isKeyboardActive { return row.handleKeyboardModeKey(event) }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if flags == .option, let c = event.charactersIgnoringModifiers?.first, let i = row.titleIndex(forMnemonic: c) {
                row.openMenu(at: i, openedWithMouseDown: false, fromKeyboard: true)
                return true
            }
            if event.keyCode == 109, flags.isEmpty {                                // F10
                row.activateKeyboard()
                return true
            }
            return false
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            row.altArmed = false
            // A click anywhere but the row ends keyboard mode (the click still lands).
            if row.isKeyboardActive, event.window !== row.window || row.titleIndex(at: row.convert(event.locationInWindow, from: nil)) == nil {
                row.deactivateKeyboard()
            }
            return false
        default:
            return false
        }
    }
}
