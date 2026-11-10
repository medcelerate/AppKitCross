// The package-drawn toolbar: the view a window places under its title band (or inside it,
// next to the standard buttons, for the unified styles on `fullSizeContentView` windows),
// the buttons that stand for image items, the overflow chevron and its menu, and the
// customization sheet. Everything is drawn with the port's own views, so the toolbar
// looks and behaves the same on Win32, X11, Wayland and the host backend (ADR-0018).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: Metrics

/// Where the window puts the toolbar and how tall it is for a style, display and size mode.
struct _NSToolbarMetrics: Equatable {
    /// `belowTitleBar`: the band comes out of the content area (the window frame grows by
    /// it); `overContent`: the content keeps its size and extends under the band
    /// (`fullSizeContentView`), `contentLayoutRect` excludes it.
    enum Placement { case belowTitleBar, overContent }
    var placement: Placement
    /// The band's full height, `topInset` included.
    var height: CGFloat
    /// Space above the item row: the title band of a `fullSizeContentView` window whose
    /// toolbar is not unified, where the standard buttons sit.
    var topInset: CGFloat
    var iconSize: CGFloat
    var buttonSize: NSSize
    var showsLabels: Bool
    var showsIcons: Bool
    var labelFontSize: CGFloat
    /// Space kept free at the leading edge for the window's standard buttons when they
    /// are the traffic lights at the left.
    var leadingInset: CGFloat
    /// Space kept free at the trailing edge for the caption buttons at the right (Windows).
    var trailingInset: CGFloat
    var itemGap: CGFloat

    static func resolve(style: NSWindow.ToolbarStyle, displayMode: NSToolbar.DisplayMode, sizeMode: NSToolbar.SizeMode, contentCoversTitleBar: Bool,
                        buttonStyle: PlatformWindowButtonStyle = .trafficLights) -> _NSToolbarMetrics {
        var resolved = style
        if resolved == .automatic { resolved = contentCoversTitleBar ? .unified : .expanded }
        let unified = resolved == .unified || resolved == .unifiedCompact
        let topInset: CGFloat = contentCoversTitleBar && !unified ? NSWindow._titleBarBandHeight : 0
        let small = sizeMode == .small
        let icon: CGFloat = small ? 18 : 24
        let button = small ? NSSize(width: 30, height: 22) : NSSize(width: 38, height: 28)
        var mode = displayMode
        if mode == .default { mode = (resolved == .expanded || resolved == .preference) ? .iconAndLabel : .iconOnly }
        if resolved == .unifiedCompact && mode == .iconAndLabel { mode = .iconOnly }
        let labels = mode != .iconOnly
        let icons = mode != .labelOnly
        let labelSize: CGFloat = small ? 10 : 11
        let height: CGFloat
        switch (resolved, mode) {
        case (.unifiedCompact, _): height = 38
        case (.unified, .iconAndLabel): height = 66
        case (.unified, .labelOnly): height = 38
        case (.unified, _): height = 52
        case (_, .iconAndLabel): height = small ? 50 : 56
        case (_, .labelOnly): height = small ? 26 : 28
        default: height = small ? 32 : 38
        }
        return _NSToolbarMetrics(placement: contentCoversTitleBar ? .overContent : .belowTitleBar, height: height + topInset, topInset: topInset,
                                 iconSize: icon, buttonSize: button, showsLabels: labels, showsIcons: icons, labelFontSize: labelSize,
                                 leadingInset: contentCoversTitleBar && unified ? max(8, _NSWindowButtonsView.leadingInset(for: buttonStyle)) : 8,
                                 trailingInset: contentCoversTitleBar && unified ? max(8, _NSWindowButtonsView.trailingInset(for: buttonStyle)) : 8, itemGap: 8)
    }
}

// MARK: Glyphs for the standard items

/// Vector drawings for the items AppKit supplies with system images.
enum _NSToolbarGlyph {
    case sidebar, inspector, print, colors, fonts, customize, share

    @MainActor var image: NSImage {
        let kind = self
        return NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            let color = NSColor.labelColor
            color.setStroke()
            color.setFill()
            let r = rect.insetBy(dx: 3, dy: 3)
            switch kind {
            case .sidebar, .inspector:
                let box = NSBezierPath(roundedRect: r.insetBy(dx: 0.75, dy: 2.75), xRadius: 2, yRadius: 2)
                box.lineWidth = 1.5
                box.stroke()
                let column = kind == .sidebar ? NSRect(x: r.minX + 1.5, y: r.minY + 3.5, width: 5.5, height: r.height - 7)
                                              : NSRect(x: r.maxX - 7, y: r.minY + 3.5, width: 5.5, height: r.height - 7)
                NSBezierPath(rect: column).fill()
            case .print:
                NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY + 4, width: r.width, height: 9), xRadius: 2, yRadius: 2).fill()
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(rect: NSRect(x: r.minX + 4, y: r.minY, width: r.width - 8, height: 6)).fill()
                color.setFill()
                NSBezierPath(rect: NSRect(x: r.minX + 4, y: r.maxY - 5, width: r.width - 8, height: 5)).fill()
                let paper = NSBezierPath(rect: NSRect(x: r.minX + 4.75, y: r.minY + 0.75, width: r.width - 9.5, height: 5.5))
                paper.lineWidth = 1.5
                paper.stroke()
            case .colors:
                NSColor.systemRed.setFill(); NSBezierPath(ovalIn: NSRect(x: r.minX, y: r.midY - 1, width: 9, height: 9)).fill()
                NSColor.systemBlue.setFill(); NSBezierPath(ovalIn: NSRect(x: r.maxX - 9, y: r.midY - 1, width: 9, height: 9)).fill()
                NSColor.systemYellow.setFill(); NSBezierPath(ovalIn: NSRect(x: r.midX - 4.5, y: r.minY, width: 9, height: 9)).fill()
            case .fonts:
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: color]
                let s = "A".size(withAttributes: attrs)
                "A".draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), withAttributes: attrs)
            case .customize:
                for (i, knob) in [0.3, 0.7, 0.45].enumerated() {
                    let y = r.minY + 3 + CGFloat(i) * 6
                    let line = NSBezierPath()
                    line.move(to: NSPoint(x: r.minX, y: y)); line.line(to: NSPoint(x: r.maxX, y: y))
                    line.lineWidth = 1.5
                    line.stroke()
                    NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * knob - 2.5, y: y - 2.5, width: 5, height: 5)).fill()
                }
            case .share:
                let box = NSBezierPath()
                box.move(to: NSPoint(x: r.minX + 3, y: r.midY)); box.line(to: NSPoint(x: r.minX, y: r.midY)); box.line(to: NSPoint(x: r.minX, y: r.minY))
                box.line(to: NSPoint(x: r.maxX, y: r.minY)); box.line(to: NSPoint(x: r.maxX, y: r.midY)); box.line(to: NSPoint(x: r.maxX - 3, y: r.midY))
                box.lineWidth = 1.5
                box.stroke()
                let arrow = NSBezierPath()
                arrow.move(to: NSPoint(x: r.midX, y: r.minY + 4)); arrow.line(to: NSPoint(x: r.midX, y: r.maxY))
                arrow.move(to: NSPoint(x: r.midX - 4, y: r.maxY - 4)); arrow.line(to: NSPoint(x: r.midX, y: r.maxY)); arrow.line(to: NSPoint(x: r.midX + 4, y: r.maxY - 4))
                arrow.lineWidth = 1.5
                arrow.lineCapStyle = .round
                arrow.stroke()
            }
            return true
        }
    }
}

// MARK: Item buttons

/// The button drawn for an image item: the item's image (or its title) centred, a bezel
/// when the item is bordered, a press highlight, and the item's action on release.
@MainActor
final class _NSToolbarItemButton: NSButton {
    weak var item: NSToolbarItem?
    var iconSize: CGFloat = 24
    var showsIcon = true
    private(set) var pressed = false

    init(item: NSToolbarItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 38, height: 28))
        title = ""
        refusesFirstResponder = true
        setAccessibilityLabel(item.label.isEmpty ? item.title : item.label)
        setAccessibilitySubrole(.toolbarButton)
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Mirrors the item's state onto the button.
    func refresh() {
        guard let item else { return }
        isEnabled = item.isEnabled
        isBordered = item.isBordered
        toolTip = item.toolTip
        setAccessibilityLabel(item.label.isEmpty ? item.title : item.label)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let r = bounds
        let highlighted = pressed && isEnabled
        if isBordered {
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (highlighted ? NSColor.selectedControlColor : NSColor.controlColor).setFill()
            path.fill()
            NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 1
            path.stroke()
        } else if highlighted {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let alpha: CGFloat = isEnabled ? 1 : 0.35
        if showsIcon, let image = item.image {
            let size = image.size
            let scale = size.width > 0 && size.height > 0 ? min(iconSize / size.width, iconSize / size.height, 1) : 1
            let w = size.width * scale, h = size.height * scale
            let dest = NSRect(x: (r.width - w) / 2, y: (r.height - h) / 2, width: w, height: h)
            image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: alpha)
            if let m = item as? NSMenuToolbarItem, m.showsIndicator { _drawIndicator(alpha: alpha) }
        } else {
            let text = item.title.isEmpty ? item.label : item.title
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha)]
            let s = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2), withAttributes: attrs)
            if let m = item as? NSMenuToolbarItem, m.showsIndicator { _drawIndicator(alpha: alpha) }
        }
    }

    private func _drawIndicator(alpha: CGFloat) {
        let p = NSBezierPath()
        let x = bounds.maxX - 6, y = bounds.minY + 5
        p.move(to: NSPoint(x: x - 3, y: y + 2)); p.line(to: NSPoint(x: x, y: y)); p.line(to: NSPoint(x: x + 3, y: y + 2))
        p.lineWidth = 1.2
        NSColor.labelColor.withAlphaComponent(alpha).setStroke()
        p.stroke()
    }

    /// The width the button wants: the fixed size, or the title's width for titled items.
    func preferredWidth(_ standard: CGFloat) -> CGFloat {
        guard let item else { return standard }
        if showsIcon, item.image != nil { return standard + ((item as? NSMenuToolbarItem)?.showsIndicator == true ? 8 : 0) }
        let text = item.title.isEmpty ? item.label : item.title
        let w = text.size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width + 20
        return max(standard, w.rounded(.up)) + ((item as? NSMenuToolbarItem)?.showsIndicator == true ? 8 : 0)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, pressed else { return }
        pressed = false
        needsDisplay = true
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        _activate(indicator: bounds.maxX - convert(event.locationInWindow, from: nil).x <= 12)
    }

    /// Fires the item: a menu item opens its menu (always without an action, or from its
    /// indicator); everything else sends the action.
    func _activate(indicator: Bool) {
        guard let item else { return }
        if let m = item as? NSMenuToolbarItem, m.action == nil || (indicator && m.showsIndicator) {
            m._popUpMenu(below: self)
            return
        }
        item._fireAction()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        _activate(indicator: false)
        return true
    }
    override func accessibilityPerformShowMenu() -> Bool {
        guard isEnabled, let m = item as? NSMenuToolbarItem else { return false }
        m._popUpMenu(below: self)
        return true
    }
}

/// The chevron at the trailing edge when items do not fit; opens the overflow menu.
@MainActor
final class _NSToolbarOverflowButton: NSButton {
    weak var toolbarView: _NSToolbarView?
    private var pressed = false
    static let width: CGFloat = 24

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: _NSToolbarOverflowButton.width, height: 28))
        title = ""
        isBordered = false
        refusesFirstResponder = true
        setAccessibilityLabel("More toolbar items")
        setAccessibilityRole(.menuButton)
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if pressed {
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        let p = NSBezierPath()
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        for dx: CGFloat in [-4, 2] {
            p.move(to: NSPoint(x: c.x + dx - 2, y: c.y - 4)); p.line(to: NSPoint(x: c.x + dx + 2, y: c.y)); p.line(to: NSPoint(x: c.x + dx - 2, y: c.y + 4))
        }
        p.lineWidth = 1.5
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        NSColor.labelColor.setStroke()
        p.stroke()
    }

    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }
        pressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { toolbarView?._openOverflowMenu(from: self) }
    }
    override func accessibilityPerformPress() -> Bool { toolbarView?._openOverflowMenu(from: self); return true }
    override func accessibilityPerformShowMenu() -> Bool { accessibilityPerformPress() }
}

// MARK: The toolbar view

/// Lays out and draws one toolbar. Flipped: y grows downwards from the band's top.
@MainActor
final class _NSToolbarView: NSView {
    unowned let toolbar: NSToolbar
    private(set) var metrics = _NSToolbarMetrics.resolve(style: .expanded, displayMode: .default, sizeMode: .default, contentCoversTitleBar: false)
    private var buttons: [ObjectIdentifier: _NSToolbarItemButton] = [:]
    private let overflowButton = _NSToolbarOverflowButton()
    /// Items that did not fit, in toolbar order (the overflow menu lists them).
    private(set) var overflowItems: [NSToolbarItem] = []
    /// Where each shown item sits (its button or view frame), for labels and selection.
    private var slots: [(item: NSToolbarItem, frame: NSRect)] = []
    private var separators: [NSRect] = []
    static let overflowChosen = Selector(("_toolbarOverflowItemChosen:"))

    init(toolbar: NSToolbar) {
        self.toolbar = toolbar
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 56))
        wantsLayer = true
        overflowButton.toolbarView = self
        overflowButton.isHidden = true
        addSubview(overflowButton)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Toolbar")
        setActionHandler(for: _NSToolbarView.overflowChosen) { [weak self] sender in self?._overflowItemChosen(sender) }
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// The band drags the window where no control takes the click, as on macOS.
    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }

    /// Applies the window's style: the window calls this before placing the view.
    func apply(style: NSWindow.ToolbarStyle, contentCoversTitleBar: Bool) {
        let m = _NSToolbarMetrics.resolve(style: style, displayMode: toolbar.displayMode, sizeMode: toolbar.sizeMode, contentCoversTitleBar: contentCoversTitleBar,
                                          buttonStyle: window?._windowButtonStyle ?? Platform.backend.windowButtonStyle)
        if m != metrics { metrics = m; needsLayout = true; needsDisplay = true }
    }

    /// The items currently shown, in order.
    var shownItems: [NSToolbarItem] { slots.map { $0.item } }

    /// Buttons re-read their items (enabled state, tool tips) without a re-layout.
    func _refreshItemViews() {
        for b in buttons.values { b.refresh() }
    }

    private func button(for item: NSToolbarItem) -> _NSToolbarItemButton {
        if let b = buttons[ObjectIdentifier(item)] { return b }
        let b = _NSToolbarItemButton(item: item)
        buttons[ObjectIdentifier(item)] = b
        addSubview(b)
        return b
    }

    override func layout() {
        super.layout()
        let m = metrics
        let items = toolbar.items.filter { !$0._hiddenInToolbar }
        let itemSet = Set(items.map { ObjectIdentifier($0) })
        // Drop buttons of items that left.
        for (id, b) in buttons where !itemSet.contains(id) { b.removeFromSuperview(); buttons[id] = nil }
        // Measure.
        struct Entry { let item: NSToolbarItem; var width: CGFloat; let flexible: Bool; let isSeparator: Bool; let kind: Kind; enum Kind { case button, view, space, separator } }
        var entries: [Entry] = []
        for item in items {
            let id = item.itemIdentifier
            if id == .flexibleSpace { entries.append(Entry(item: item, width: 0, flexible: true, isSeparator: false, kind: .space)); continue }
            if id == .space { entries.append(Entry(item: item, width: m.buttonSize.width, flexible: false, isSeparator: false, kind: .space)); continue }
            if id == .separator || id == .sidebarTrackingSeparator || id == .inspectorTrackingSeparator || item is NSTrackingSeparatorToolbarItem {
                entries.append(Entry(item: item, width: 1, flexible: false, isSeparator: true, kind: .separator)); continue
            }
            if let v = item.view {
                var w = v.frame.width
                if let s = item as? NSSearchToolbarItem { w = s.preferredWidthForSearchField }
                if item.minSize.width > 0 { w = max(w, item.minSize.width) }
                if item.maxSize.width > 0 { w = min(w, item.maxSize.width) }
                var width = w
                if m.showsLabels, !item.label.isEmpty { width = max(width, _labelWidth(item.label)) }
                entries.append(Entry(item: item, width: width, flexible: false, isSeparator: false, kind: .view))
            } else {
                let b = button(for: item)
                b.iconSize = m.iconSize
                b.showsIcon = m.showsIcons
                b.refresh()
                var width = b.preferredWidth(m.buttonSize.width)
                if m.showsLabels, !item.label.isEmpty { width = max(width, _labelWidth(item.label)) }
                entries.append(Entry(item: item, width: width, flexible: false, isSeparator: false, kind: .button))
            }
        }
        // Navigational items lead.
        let navigational = entries.filter { $0.item.isNavigational }
        entries = navigational + entries.filter { !$0.item.isNavigational }
        // Overflow: drop the lowest-priority items (rightmost first among equals) until
        // the fixed widths fit, keeping room for the chevron.
        let available = bounds.width - m.leadingInset - m.trailingInset
        func needed(_ es: [Entry]) -> CGFloat { es.reduce(0) { $0 + $1.width } + CGFloat(max(0, es.count - 1)) * m.itemGap }
        var overflow: [NSToolbarItem] = []
        var shown = entries
        if needed(shown) > available {
            let reserve = _NSToolbarOverflowButton.width + m.itemGap
            while needed(shown) + reserve > available, let victim = shown.indices.filter({ shown[$0].kind != .space && shown[$0].kind != .separator }).min(by: { a, b in
                let pa = shown[a].item.visibilityPriority, pb = shown[b].item.visibilityPriority
                return pa != pb ? pa < pb : a > b
            }) {
                overflow.append(shown[victim].item)
                shown.remove(at: victim)
            }
            // Trailing spaces and separators serve nothing once items are gone.
            while let last = shown.last, last.kind == .space || last.kind == .separator { shown.removeLast() }
        }
        overflowItems = items.filter { item in overflow.contains { $0 === item } }
        for item in toolbar.items { item._isShownInToolbar = shown.contains { $0.item === item } }
        // Flexible spaces share what is left; a tracking separator pins its position.
        let usable = available - (overflow.isEmpty ? 0 : _NSToolbarOverflowButton.width + m.itemGap)
        let fixed = needed(shown)
        let flexCount = shown.filter { $0.flexible }.count
        let flex = flexCount > 0 ? max(0, usable - fixed) / CGFloat(flexCount) : 0
        let centered = toolbar.centeredItemIdentifiers
        var x = m.leadingInset
        slots.removeAll()
        separators.removeAll()
        let rowHeight = bounds.height - m.topInset
        let rowTop: CGFloat = m.topInset + (m.showsLabels && m.showsIcons ? 4 : ((rowHeight - m.buttonSize.height) / 2).rounded())
        var frames: [NSRect] = []
        for e in shown {
            var w = e.width
            if e.flexible { w = flex }
            if let t = e.item as? NSTrackingSeparatorToolbarItem, let tx = t._trackedX { x = max(x, tx) }
            frames.append(NSRect(x: x, y: rowTop, width: w, height: m.buttonSize.height))
            x += w + m.itemGap
        }
        // Centered items: shift the run so its middle sits at the band's middle when there
        // is no flexible space deciding the layout.
        if !centered.isEmpty, flexCount == 0 {
            let run = shown.indices.filter { centered.contains(shown[$0].item.itemIdentifier) }
            if let first = run.first, let last = run.last {
                let runRect = frames[first].union(frames[last])
                let shift = (bounds.width / 2 - runRect.midX).rounded()
                if shift > 0, frames[last].maxX + shift <= m.leadingInset + usable {
                    for i in first..<frames.count { frames[i].origin.x += shift }
                }
            }
        }
        for (e, f) in zip(shown, frames) {
            switch e.kind {
            case .button:
                let b = button(for: e.item)
                let bw = b.preferredWidth(m.buttonSize.width)
                b.frame = NSRect(x: (f.midX - bw / 2).rounded(), y: f.minY, width: bw, height: m.buttonSize.height)
                b.isHidden = false
                slots.append((e.item, b.frame))
            case .view:
                guard let v = e.item.view else { continue }
                if v.superview !== self { addSubview(v) }
                var vw = v.frame.width
                if let s = e.item as? NSSearchToolbarItem { vw = s.preferredWidthForSearchField }
                if e.item.minSize.width > 0 { vw = max(vw, e.item.minSize.width) }
                if e.item.maxSize.width > 0 { vw = min(vw, e.item.maxSize.width) }
                let vh = min(v.frame.height > 0 ? v.frame.height : m.buttonSize.height, m.buttonSize.height + 4)
                v.frame = NSRect(x: (f.midX - vw / 2).rounded(), y: (f.midY - vh / 2).rounded(), width: vw, height: vh)
                v.isHidden = false
                slots.append((e.item, v.frame))
            case .separator:
                separators.append(NSRect(x: f.minX.rounded(), y: m.topInset + 6, width: 1, height: rowHeight - 12))
                slots.append((e.item, f))
            case .space:
                slots.append((e.item, f))
            }
        }
        for item in overflowItems {
            buttons[ObjectIdentifier(item)]?.isHidden = true
            item.view?.isHidden = true
        }
        overflowButton.isHidden = overflowItems.isEmpty
        overflowButton.frame = NSRect(x: bounds.width - m.trailingInset - _NSToolbarOverflowButton.width, y: rowTop, width: _NSToolbarOverflowButton.width, height: m.buttonSize.height)
    }

    private func _labelWidth(_ label: String) -> CGFloat {
        label.size(withAttributes: [.font: NSFont.systemFont(ofSize: metrics.labelFontSize)]).width.rounded(.up) + 6
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.isDark
        let key = window?.isKeyWindow ?? true
        let chrome = window?._chrome ?? PlatformWindowChrome()
        if metrics.placement == .belowTitleBar || !chrome.transparentTitleBar || metrics.topInset > 0 {
            // The band: AppKit's title bar colour, so the toolbar reads as part of the frame.
            let fill: NSColor
            if key { fill = dark ? NSColor(white: 0.23, alpha: 1) : NSColor(white: 0.91, alpha: 1) }
            else { fill = dark ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.96, alpha: 1) }
            fill.setFill()
            NSBezierPath.fill(bounds)
        }
        if let selected = toolbar.selectedItemIdentifier, let slot = slots.first(where: { $0.item.itemIdentifier == selected }) {
            let r = slot.frame.insetBy(dx: -4, dy: -3)
            NSColor.labelColor.withAlphaComponent(dark ? 0.16 : 0.09).setFill()
            NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        }
        NSColor.separatorColor.setFill()
        for s in separators { NSBezierPath.fill(s) }
        if metrics.showsLabels {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: metrics.labelFontSize), .foregroundColor: NSColor.labelColor]
            let disabledAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: metrics.labelFontSize), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.35)]
            for slot in slots where !slot.item.label.isEmpty && slot.item.itemIdentifier != .space && slot.item.itemIdentifier != .flexibleSpace && !(slot.item.view == nil && !metrics.showsIcons) {
                if slot.item.itemIdentifier == .separator || slot.item is NSTrackingSeparatorToolbarItem { continue }
                let a = slot.item.isEnabled ? attrs : disabledAttrs
                let s = slot.item.label.size(withAttributes: a)
                let y = metrics.showsIcons ? slot.frame.maxY + 2 : slot.frame.midY - s.height / 2
                slot.item.label.draw(at: NSPoint(x: (slot.frame.midX - s.width / 2).rounded(), y: y.rounded()), withAttributes: a)
            }
        }
        if toolbar.showsBaselineSeparator, metrics.placement == .belowTitleBar {
            NSColor.separatorColor.setFill()
            NSBezierPath.fill(NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        }
    }

    // MARK: Overflow menu

    /// The menu listing the items that did not fit: each item's menu form, a submenu for
    /// groups and menu items, the search field's label for a search item.
    func _overflowMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        for item in overflowItems {
            if let group = item as? NSToolbarItemGroup {
                let parent = NSMenuItem(title: group.label.isEmpty ? group.title : group.label, action: nil, keyEquivalent: "")
                let sub = NSMenu(title: parent.title)
                sub.autoenablesItems = false
                for s in group.subitems {
                    let mi = NSMenuItem(title: s.label.isEmpty ? s.title : s.label, action: _NSToolbarView.overflowChosen, keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = s
                    mi.image = s.image
                    mi.isEnabled = group.isEnabled
                    sub.addItem(mi)
                }
                parent.submenu = sub
                parent.isEnabled = group.isEnabled
                menu.addItem(parent)
                continue
            }
            if let m = item as? NSMenuToolbarItem {
                let parent = NSMenuItem(title: m.label.isEmpty ? m.title : m.label, action: nil, keyEquivalent: "")
                parent.submenu = m.menu
                parent.image = m.image
                parent.isEnabled = m.isEnabled
                menu.addItem(parent)
                continue
            }
            guard let mi = item._menuRepresentation() else { continue }
            if mi.action == nil && mi.submenu == nil {
                mi.target = self
                mi.action = _NSToolbarView.overflowChosen
                mi.representedObject = item
            }
            mi.isEnabled = item.isEnabled && (item.view == nil || item.view is NSControl || item is NSSearchToolbarItem)
            menu.addItem(mi)
        }
        return menu
    }

    func _openOverflowMenu(from button: NSView) {
        guard let w = window else { return }
        let anchor = w.convertToScreen(button.convert(button.bounds, to: nil))
        _ = _NSMenuTracker.begin(menu: _overflowMenu(), anchor: anchor, placement: .besideAnchor(edge: .minY), openedWithMouseDown: false)
    }

    private func _overflowItemChosen(_ sender: Any?) {
        guard let item = (sender as? NSMenuItem)?.representedObject as? NSToolbarItem else { return }
        if let s = item as? NSSearchToolbarItem { s.beginSearchInteraction(); return }
        if item.action != nil { item._fireAction() }
        else if let c = item.view as? NSControl { c.performClick(nil) }
    }

    // MARK: Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }
}

// MARK: Customization palette

/// The sheet behind `runCustomizationPalette(_:)`: pop-ups listing the allowed items
/// not in the toolbar and the items in it, Add and Remove buttons, the display and size
/// modes, "Use Default Set" and Done. Items are added at the end (or before the item the
/// delegate allows them at) and removed by identifier.
@MainActor
final class _NSToolbarCustomizationPalette: NSObject {
    let window: NSWindow
    unowned let toolbar: NSToolbar
    let allowed: [NSToolbarItem.Identifier]
    let addPopUp: NSPopUpButton
    let removePopUp: NSPopUpButton
    let addButton: NSButton
    let removeButton: NSButton
    let displayPopUp: NSPopUpButton
    let smallSize: NSButton
    let defaultsButton: NSButton
    let doneButton: NSButton
    private var addable: [NSToolbarItem.Identifier] = []
    private var removable: [NSToolbarItem.Identifier] = []

    private final class _FlippedView: NSView { override var isFlipped: Bool { true } }

    init(toolbar: NSToolbar, allowed: [NSToolbarItem.Identifier]) {
        self.toolbar = toolbar
        self.allowed = allowed
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 214), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Customize Toolbar"
        window.isReleasedWhenClosed = false
        let content = _FlippedView(frame: NSRect(x: 0, y: 0, width: 460, height: 214))
        window.contentView = content
        func label(_ s: String, _ y: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.frame = NSRect(x: 20, y: y + 3, width: 70, height: 20)
            l.alignment = .right
            content.addSubview(l)
            return l
        }
        _ = label("Add:", 20)
        addPopUp = NSPopUpButton(frame: NSRect(x: 98, y: 20, width: 230, height: 26), pullsDown: false)
        content.addSubview(addPopUp)
        addButton = NSButton(title: "Add", target: nil, action: nil)
        addButton.frame = NSRect(x: 340, y: 20, width: 100, height: 26)
        content.addSubview(addButton)
        _ = label("Remove:", 58)
        removePopUp = NSPopUpButton(frame: NSRect(x: 98, y: 58, width: 230, height: 26), pullsDown: false)
        content.addSubview(removePopUp)
        removeButton = NSButton(title: "Remove", target: nil, action: nil)
        removeButton.frame = NSRect(x: 340, y: 58, width: 100, height: 26)
        content.addSubview(removeButton)
        _ = label("Show:", 104)
        displayPopUp = NSPopUpButton(frame: NSRect(x: 98, y: 104, width: 160, height: 26), pullsDown: false)
        displayPopUp.addItems(withTitles: ["Icon and Label", "Icon Only", "Label Only"])
        content.addSubview(displayPopUp)
        smallSize = NSButton(checkboxWithTitle: "Use small size", target: nil, action: nil)
        smallSize.frame = NSRect(x: 270, y: 107, width: 170, height: 20)
        content.addSubview(smallSize)
        defaultsButton = NSButton(title: "Use Default Set", target: nil, action: nil)
        defaultsButton.frame = NSRect(x: 98, y: 160, width: 150, height: 28)
        content.addSubview(defaultsButton)
        doneButton = NSButton(title: "Done", target: nil, action: nil)
        doneButton.frame = NSRect(x: 340, y: 160, width: 100, height: 28)
        doneButton.keyEquivalent = "\r"
        content.addSubview(doneButton)
        super.init()
        for (button, selector) in [(addButton, "add:"), (removeButton, "remove:"), (defaultsButton, "useDefaults:"), (doneButton, "done:"), (smallSize, "sizeChanged:")] {
            button.target = self
            button.action = Selector((selector))
        }
        displayPopUp.target = self
        displayPopUp.action = Selector(("displayChanged:"))
        setActionHandler(for: Selector(("add:"))) { [weak self] _ in self?.add() }
        setActionHandler(for: Selector(("remove:"))) { [weak self] _ in self?.remove() }
        setActionHandler(for: Selector(("useDefaults:"))) { [weak self] _ in self?.toolbar._useDefaultItems(); self?.reload() }
        setActionHandler(for: Selector(("done:"))) { [weak self] _ in self?.done() }
        setActionHandler(for: Selector(("sizeChanged:"))) { [weak self] _ in
            guard let self else { return }
            self.toolbar.sizeMode = self.smallSize.state == .on ? .small : .regular
        }
        setActionHandler(for: Selector(("displayChanged:"))) { [weak self] _ in
            guard let self else { return }
            self.toolbar.displayMode = [NSToolbar.DisplayMode.iconAndLabel, .iconOnly, .labelOnly][max(0, self.displayPopUp.indexOfSelectedItem)]
        }
        reload()
    }

    /// Refills the pop-ups from the toolbar's state.
    func reload() {
        let present = toolbar.items.map { $0.itemIdentifier }
        addable = allowed.filter { id in
            guard let item = toolbar._paletteItem(id) else { return false }
            return item.allowsDuplicatesInToolbar || !present.contains(id)
        }
        addPopUp.removeAllItems()
        addPopUp.addItems(withTitles: addable.map { toolbar._paletteItem($0)?.paletteLabel ?? $0.rawValue })
        let immovable = toolbar._immovableItemIdentifiers
        removable = present.filter { !immovable.contains($0) }
        removePopUp.removeAllItems()
        removePopUp.addItems(withTitles: removable.map { id in toolbar.items.first { $0.itemIdentifier == id }?.paletteLabel ?? id.rawValue })
        addButton.isEnabled = !addable.isEmpty
        removeButton.isEnabled = !removable.isEmpty
        let mode = toolbar.displayMode == .default ? .iconAndLabel : toolbar.displayMode
        displayPopUp.selectItem(at: [NSToolbar.DisplayMode.iconAndLabel, .iconOnly, .labelOnly].firstIndex(of: mode) ?? 0)
        displayPopUp.isEnabled = toolbar._displayModeCustomizable
        smallSize.state = toolbar.sizeMode == .small ? .on : .off
    }

    func add() {
        let i = addPopUp.indexOfSelectedItem
        guard addable.indices.contains(i) else { return }
        let id = addable[i]
        let index = toolbar.items.count
        guard toolbar._canInsert(id, at: index) else { return }
        toolbar.insertItem(withItemIdentifier: id, at: index)
        reload()
    }

    func remove() {
        let i = removePopUp.indexOfSelectedItem
        guard removable.indices.contains(i) else { return }
        let id = removable[i]
        // Duplicates (spaces) go from the end, as the pop-up lists them in order.
        if let index = toolbar.items.lastIndex(where: { $0.itemIdentifier == id }) { toolbar.removeItem(at: index) }
        reload()
    }

    func done() {
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.orderOut(nil) }
    }
}
