// The colour panel's package-drawn content (ADR-0022): the mode bar, the preview swatch
// with its hex field, the wheel, the sliders (gray, RGB, CMYK, HSB), the colour lists,
// the crayons, the opacity slider, the accessory view and the favourites row. Every
// control reports a change to the panel with whether it is final (the mouse went up),
// so the panel can honour `isContinuous`.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Colour arithmetic

internal enum _NSColorMath {
    static func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }

    static func hex(_ c: NSColor) -> String {
        String(format: "%02X%02X%02X", Int((clamp(c.redComponent) * 255).rounded()), Int((clamp(c.greenComponent) * 255).rounded()), Int((clamp(c.blueComponent) * 255).rounded()))
    }

    static func color(hex: String, alpha: CGFloat) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    static func cmyk(_ c: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let k = 1 - max(r, g, b)
        if k >= 1 { return (0, 0, 0, 1) }
        return ((1 - r - k) / (1 - k), (1 - g - k) / (1 - k), (1 - b - k) / (1 - k), k)
    }

    static func color(cyan: CGFloat, magenta: CGFloat, yellow: CGFloat, black: CGFloat, alpha: CGFloat) -> NSColor {
        NSColor(red: (1 - clamp(cyan)) * (1 - clamp(black)), green: (1 - clamp(magenta)) * (1 - clamp(black)), blue: (1 - clamp(yellow)) * (1 - clamp(black)), alpha: alpha)
    }

    /// Linear interpolation through `stops` in RGB.
    static func interpolate(_ stops: [NSColor], at t: CGFloat) -> NSColor {
        guard stops.count > 1 else { return stops.first ?? .black }
        let scaled = clamp(t) * CGFloat(stops.count - 1)
        let i = min(stops.count - 2, Int(scaled))
        let f = scaled - CGFloat(i)
        let a = stops[i], b = stops[i + 1]
        return NSColor(red: a.redComponent + (b.redComponent - a.redComponent) * f, green: a.greenComponent + (b.greenComponent - a.greenComponent) * f,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * f, alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * f)
    }
}

// MARK: - A gradient slider

/// A horizontal slider over a gradient of what each position would give, 0...1.
@MainActor
internal final class _NSColorSliderView: NSView {
    var value: CGFloat = 0 { didSet { needsDisplay = true } }
    var stops: [NSColor] = [.black, .white] { didSet { needsDisplay = true } }
    var showsCheckerboard = false
    var onChange: ((CGFloat, Bool) -> Void)?
    private var tracking = false

    override var acceptsFirstResponder: Bool { isEnabledForTracking }
    var isEnabledForTracking = true

    private var trackRect: NSRect { NSRect(x: bounds.minX + 7, y: bounds.midY - 5, width: bounds.width - 14, height: 10) }

    override func draw(_ dirtyRect: NSRect) {
        let track = trackRect
        let path = NSBezierPath(roundedRect: track, xRadius: 5, yRadius: 5)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if showsCheckerboard { NSColorWell._drawCheckerboard(in: track, cell: 5) }
        let strips = 48
        let w = track.width / CGFloat(strips)
        for i in 0..<strips {
            _NSColorMath.interpolate(stops, at: (CGFloat(i) + 0.5) / CGFloat(strips)).setFill()
            NSBezierPath.fill(NSRect(x: track.minX + CGFloat(i) * w, y: track.minY, width: w + 1, height: track.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        path.stroke()
        let x = track.minX + _NSColorMath.clamp(value) * track.width
        let knob = NSBezierPath(ovalIn: NSRect(x: x - 7, y: bounds.midY - 7, width: 14, height: 14))
        NSColor.white.setFill()
        knob.fill()
        (window?.firstResponder === self ? NSColor.controlAccentColor : NSColor(white: 0.4, alpha: 1)).setStroke()
        knob.lineWidth = 1
        knob.stroke()
    }

    private func value(at p: NSPoint) -> CGFloat { _NSColorMath.clamp((p.x - trackRect.minX) / max(1, trackRect.width)) }

    override func mouseDown(with event: NSEvent) {
        guard isEnabledForTracking else { return }
        tracking = true
        window?.makeFirstResponder(self)
        value = value(at: convert(event.locationInWindow, from: nil))
        onChange?(value, false)
    }
    override func mouseDragged(with event: NSEvent) {
        guard tracking else { return }
        value = value(at: convert(event.locationInWindow, from: nil))
        onChange?(value, false)
    }
    override func mouseUp(with event: NSEvent) {
        guard tracking else { return }
        tracking = false
        onChange?(value, true)
    }
    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 0.1 : 1 / 255
        switch event.charactersIgnoringModifiers {
        case "\u{F702}", "\u{F701}": value = _NSColorMath.clamp(value - step); onChange?(value, true)
        case "\u{F703}", "\u{F700}": value = _NSColorMath.clamp(value + step); onChange?(value, true)
        default: super.keyDown(with: event)
        }
    }

    // Accessibility: a slider in percent. A plain NSView is ignored unless it says it is an
    // element, so these views opt in (UIA then lists them as Slider with RangeValue).
    override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .slider }
    override func accessibilityValue() -> Any? { _a11y.hasValue ? _a11y.value : MainActor.assumeIsolated { Double((value * 100).rounded()) } }
    override func accessibilityMinValue() -> Any? { 0.0 }
    override func accessibilityMaxValue() -> Any? { 100.0 }
    override func _accessibilityValueIsSettable() -> Bool { isEnabledForTracking }
    override func _accessibilitySetValue(_ v: PlatformAccessibilityValue) -> Bool {
        guard isEnabledForTracking, let d = v.doubleValue else { return false }
        value = _NSColorMath.clamp(CGFloat(d) / 100)
        onChange?(value, true)
        return true
    }
    override func accessibilityPerformIncrement() -> Bool { MainActor.assumeIsolated { value = _NSColorMath.clamp(value + 0.01); onChange?(value, true); return true } }
    override func accessibilityPerformDecrement() -> Bool { MainActor.assumeIsolated { value = _NSColorMath.clamp(value - 0.01); onChange?(value, true); return true } }
}

// MARK: - The hue/saturation wheel

@MainActor
internal final class _NSColorWheelView: NSView {
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 1 { didSet { if brightness != oldValue { needsDisplay = true } } }
    var onChange: ((CGFloat, CGFloat, Bool) -> Void)?
    private var tracking = false
    private var cache: (side: CGFloat, brightness: CGFloat, image: NSImage)? = nil

    var wheelRect: NSRect {
        let side = max(10, min(bounds.width, bounds.height) - 4)
        return NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }

    private func wheelImage(side: CGFloat) -> NSImage {
        let b = (brightness * 20).rounded() / 20
        if let c = cache, c.side == side, c.brightness == b { return c.image }
        let rings = 14, sectors = 90
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            for ring in 0..<rings {
                let inner = radius * CGFloat(ring) / CGFloat(rings)
                let outer = radius * CGFloat(ring + 1) / CGFloat(rings) + 0.6
                let sat = (CGFloat(ring) + 0.5) / CGFloat(rings)
                for s in 0..<sectors {
                    let a0 = 360 * CGFloat(s) / CGFloat(sectors), a1 = 360 * CGFloat(s + 1) / CGFloat(sectors) + 0.8
                    let path = NSBezierPath()
                    path.appendArc(withCenter: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
                    if inner > 0 { path.appendArc(withCenter: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: true) } else { path.line(to: center) }
                    path.close()
                    NSColor(hue: (CGFloat(s) + 0.5) / CGFloat(sectors), saturation: sat, brightness: b, alpha: 1).setFill()
                    path.fill()
                }
            }
            return true
        }
        cache = (side, b, image)
        return image
    }

    func markerPoint() -> NSPoint {
        let r = wheelRect
        let radius = r.width / 2 * _NSColorMath.clamp(saturation)
        let angle = hue * 2 * .pi
        return NSPoint(x: r.midX + cos(angle) * radius, y: r.midY + sin(angle) * radius)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = wheelRect
        wheelImage(side: r.width).draw(in: r)
        NSColor.separatorColor.setStroke()
        NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        let p = markerPoint()
        let marker = NSBezierPath(ovalIn: NSRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        marker.lineWidth = 2
        NSColor.white.setStroke()
        marker.stroke()
        let inner = NSBezierPath(ovalIn: NSRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
        NSColor(white: 0, alpha: 0.5).setStroke()
        inner.lineWidth = 1
        inner.stroke()
    }

    private func pick(at p: NSPoint, final: Bool) {
        let r = wheelRect
        let dx = p.x - r.midX, dy = p.y - r.midY
        let dist = sqrt(dx * dx + dy * dy)
        var angle = atan2(dy, dx) / (2 * .pi)
        if angle < 0 { angle += 1 }
        hue = dist < 0.5 ? hue : angle
        saturation = _NSColorMath.clamp(dist / (r.width / 2))
        needsDisplay = true
        onChange?(hue, saturation, final)
    }

    override func mouseDown(with event: NSEvent) {
        tracking = true
        pick(at: convert(event.locationInWindow, from: nil), final: false)
    }
    override func mouseDragged(with event: NSEvent) {
        guard tracking else { return }
        pick(at: convert(event.locationInWindow, from: nil), final: false)
    }
    override func mouseUp(with event: NSEvent) {
        guard tracking else { return }
        tracking = false
        onChange?(hue, saturation, true)
    }

    override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .colorWell }
    override func accessibilityLabel() -> String? { _a11y.label ?? "Color wheel" }
    override func accessibilityValue() -> Any? {
        if _a11y.hasValue { return _a11y.value }
        return MainActor.assumeIsolated { String(format: "hue %d° saturation %d%%", Int((hue * 360).rounded()), Int((saturation * 100).rounded())) }
    }
}

// MARK: - The preview swatch

/// The current colour, draggable out and a drop target for colours.
@MainActor
internal final class _NSColorSwatchView: NSView, NSDraggingSource {
    var color: NSColor = .white { didSet { needsDisplay = true } }
    var onDrop: ((NSColor) -> Void)?
    private var mouseDownPoint: NSPoint? = nil

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.color])
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if color.alphaComponent < 1 { NSColorWell._drawCheckerboard(in: bounds) }
        color.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        if abs(p.x - start.x) > 4 || abs(p.y - start.y) > 4 {
            mouseDownPoint = nil
            _ = NSColorPanel.dragColor(color, with: event, from: self)
        }
    }
    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .generic }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.availableType(from: [.color]) != nil ? .generic : []
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let c = NSColor(from: sender.draggingPasteboard) else { return false }
        onDrop?(c)
        return true
    }

    override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .colorWell }
    override func accessibilityLabel() -> String? { _a11y.label ?? "Current color" }
    override func accessibilityValue() -> Any? { MainActor.assumeIsolated { _NSColorMath.hex(color) } }
}

// MARK: - Favourites

/// Ten swatch slots kept in the user defaults: click an empty one to keep the current
/// colour, a filled one to take it back, drop a colour on one to replace it, and
/// right-click to clear it.
@MainActor
internal final class _NSColorFavoritesView: NSView, NSDraggingSource {
    static let slotCount = 10
    static let defaultsKey = "NSColorPanelSwatches"
    private(set) var colors: [NSColor?] = Array(repeating: nil, count: _NSColorFavoritesView.slotCount)
    var current: NSColor = .white
    var onPick: ((NSColor) -> Void)?
    private var mouseDownSlot: Int? = nil
    private var mouseDownPoint: NSPoint = .zero
    private var dropSlot: Int? = nil

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.color])
        load()
    }
    required init?(coder: NSCoder) { nil }

    private func load() {
        guard let stored = UserDefaults.standard.stringArray(forKey: _NSColorFavoritesView.defaultsKey) else { return }
        for (i, s) in stored.prefix(_NSColorFavoritesView.slotCount).enumerated() {
            guard s.count == 8, let v = UInt32(s, radix: 16) else { continue }
            colors[i] = NSColor(red: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255, blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
        }
    }
    private func save() {
        let strings = colors.map { c -> String in
            guard let c else { return "" }
            return _NSColorMath.hex(c) + String(format: "%02X", Int((_NSColorMath.clamp(c.alphaComponent) * 255).rounded()))
        }
        UserDefaults.standard.set(strings, forKey: _NSColorFavoritesView.defaultsKey)
        UserDefaults.standard.synchronize()
    }

    func set(_ color: NSColor?, at slot: Int) {
        guard slot >= 0, slot < colors.count else { return }
        colors[slot] = color
        save()
        needsDisplay = true
    }

    private var cell: CGFloat { min(bounds.height, (bounds.width - CGFloat(_NSColorFavoritesView.slotCount - 1) * 4) / CGFloat(_NSColorFavoritesView.slotCount)) }
    func rect(of slot: Int) -> NSRect {
        let c = cell
        let total = c * CGFloat(_NSColorFavoritesView.slotCount) + 4 * CGFloat(_NSColorFavoritesView.slotCount - 1)
        let x0 = bounds.minX + (bounds.width - total) / 2
        return NSRect(x: x0 + CGFloat(slot) * (c + 4), y: bounds.midY - c / 2, width: c, height: c)
    }
    private func slot(at p: NSPoint) -> Int? { (0..<_NSColorFavoritesView.slotCount).first { rect(of: $0).insetBy(dx: -2, dy: -2).contains(p) } }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<_NSColorFavoritesView.slotCount {
            let r = rect(of: i)
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            if let c = colors[i] {
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                if c.alphaComponent < 1 { NSColorWell._drawCheckerboard(in: r, cell: 4) }
                c.setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.quaternaryLabelColor.setFill()
                path.fill()
            }
            (dropSlot == i ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseDownSlot = slot(at: p)
        mouseDownPoint = p
    }
    override func mouseDragged(with event: NSEvent) {
        guard let s = mouseDownSlot, let c = colors[s] else { return }
        let p = convert(event.locationInWindow, from: nil)
        if abs(p.x - mouseDownPoint.x) > 4 || abs(p.y - mouseDownPoint.y) > 4 {
            mouseDownSlot = nil
            _ = NSColorPanel.dragColor(c, with: event, from: self)
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard let s = mouseDownSlot else { return }
        mouseDownSlot = nil
        guard rect(of: s).insetBy(dx: -2, dy: -2).contains(convert(event.locationInWindow, from: nil)) else { return }
        if let c = colors[s] { onPick?(c) } else { set(current, at: s) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let s = slot(at: convert(event.locationInWindow, from: nil)) { set(nil, at: s) }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .generic }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.color]) != nil else { return [] }
        let p = convert(sender.draggingLocation, from: nil)
        let s = slot(at: p)
        if s != dropSlot { dropSlot = s; needsDisplay = true }
        return s == nil ? [] : .generic
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { dropSlot = nil; needsDisplay = true }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { dropSlot = nil; needsDisplay = true }
        guard let s = slot(at: convert(sender.draggingLocation, from: nil)), let c = NSColor(from: sender.draggingPasteboard) else { return false }
        set(c, at: s)
        return true
    }

    override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .group }
    override func accessibilityLabel() -> String? { _a11y.label ?? "Favorite colors" }
}

// MARK: - Crayons

@MainActor
internal final class _NSColorCrayonView: NSView {
    static let columns = 8
    let crayons = NSColorList.crayons
    var selected: Int? = nil { didSet { needsDisplay = true } }
    var onPick: ((NSColor) -> Void)?
    private let labelHeight: CGFloat = 18

    private var rows: Int { (crayons.count + _NSColorCrayonView.columns - 1) / _NSColorCrayonView.columns }
    func rect(of index: Int) -> NSRect {
        let cols = _NSColorCrayonView.columns
        let grid = NSRect(x: bounds.minX, y: bounds.minY + labelHeight, width: bounds.width, height: bounds.height - labelHeight)
        let cw = grid.width / CGFloat(cols), ch = grid.height / CGFloat(rows)
        let col = index % cols, row = index / cols
        // Row 0 at the top (the view is not flipped).
        return NSRect(x: grid.minX + CGFloat(col) * cw, y: grid.maxY - CGFloat(row + 1) * ch, width: cw, height: ch).insetBy(dx: 2, dy: 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, crayon) in crayons.enumerated() {
            let r = rect(of: i)
            let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            crayon.1.setFill()
            path.fill()
            if selected == i {
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
        }
        let name = selected.map { crayons[$0].0 } ?? ""
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        let size = name.size(withAttributes: attrs)
        name.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.minY + (labelHeight - size.height) / 2), withAttributes: attrs)
    }

    func select(matching color: NSColor) {
        selected = crayons.firstIndex { abs($0.1.redComponent - color.redComponent) < 0.01 && abs($0.1.greenComponent - color.greenComponent) < 0.01 && abs($0.1.blueComponent - color.blueComponent) < 0.01 }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = crayons.indices.first(where: { rect(of: $0).contains(p) }) else { return }
        selected = i
        onPick?(crayons[i].1)
    }

    override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .group }
    override func accessibilityLabel() -> String? { _a11y.label ?? "Crayons" }
}

// MARK: - Colour lists

/// A cell drawing a swatch before the colour's name.
@MainActor
internal final class _NSColorListCell: NSTextFieldCell {
    weak var picker: _NSColorListPicker?
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        if let c = picker?.color(named: stringValue) {
            let r = NSRect(x: cellFrame.minX + 4, y: cellFrame.midY - 6, width: 18, height: 12)
            let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            c.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
        }
        var text = cellFrame
        text.origin.x += 26
        text.size.width -= 26
        super.drawInterior(withFrame: text, in: controlView)
    }
}

@MainActor
internal final class _NSColorListPicker: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let popUp = NSPopUpButton(frame: .zero)
    let scroll = NSScrollView(frame: .zero)
    let table = NSTableView(frame: .zero)
    private(set) var lists: [NSColorList] = []
    private var keys: [String] = []
    var onPick: ((NSColor) -> Void)?
    private var syncing = false
    private static let popUpAction = Selector(("_colorListChanged:"))

    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("AppKitCross.ColorPanel.ListEntry"))
        let cell = _NSColorListCell(textCell: "")
        cell.picker = self
        column.dataCell = cell
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 18
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Colors")
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        popUp.target = self
        popUp.action = _NSColorListPicker.popUpAction
        setActionHandler(for: _NSColorListPicker.popUpAction) { [weak self] _ in self?.listChanged() }
        addSubview(popUp)
        addSubview(scroll)
        NotificationCenter.default.addObserver(forName: NSColorList.didChangeNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadKeys() }
        }
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        popUp.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 24)
        scroll.frame = NSRect(x: 0, y: 30, width: bounds.width, height: max(10, bounds.height - 30))
        scroll.tile()
        if let c = table.tableColumns.first { c.width = max(10, scroll.contentView.bounds.width) }
        table.tile()
    }

    var selectedList: NSColorList? { popUp.indexOfSelectedItem >= 0 && popUp.indexOfSelectedItem < lists.count ? lists[popUp.indexOfSelectedItem] : nil }

    func reload(lists newLists: [NSColorList]) {
        let previous = selectedList?.name
        lists = newLists
        popUp.removeAllItems()
        popUp.addItems(withTitles: lists.map { $0.name ?? "Untitled" })
        if let p = previous, let i = lists.firstIndex(where: { $0.name == p }) { popUp.selectItem(at: i) } else if !lists.isEmpty { popUp.selectItem(at: 0) }
        reloadKeys()
    }

    private func reloadKeys() {
        keys = selectedList?.allKeys ?? []
        table.reloadData()
    }

    private func listChanged() {
        reloadKeys()
    }

    func color(named name: String) -> NSColor? { selectedList?.color(withKey: name) }

    func numberOfRows(in tableView: NSTableView) -> Int { keys.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { row < keys.count ? keys[row] : nil }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, table.selectedRow >= 0, table.selectedRow < keys.count, let c = color(named: keys[table.selectedRow]) else { return }
        onPick?(c)
    }
}

// MARK: - The panel's content view

@MainActor
internal final class _NSColorPanelView: NSView {
    weak var panel: NSColorPanel?
    var accessory: NSView? = nil
    var showsAlpha = false { didSet { needsLayout = true } }

    // Picker kinds in the mode bar: wheel, sliders, lists, crayons.
    private static let kindNames = ["Wheel", "Sliders", "Lists", "Crayons"]
    private var availableKinds: [Int] = [0, 1, 2, 3]
    private var kind = 0
    private var sliderMode: NSColorPanel.Mode = .RGB

    let modeControl: NSSegmentedControl
    let preview = _NSColorSwatchView(frame: .zero)
    let hexLabel = NSTextField(labelWithString: "Hex")
    let hexField = NSTextField(string: "")
    let sliderKind = NSPopUpButton(frame: .zero)
    let wheel = _NSColorWheelView(frame: .zero)
    let brightnessSlider = _NSColorSliderView(frame: .zero)
    let brightnessLabel = NSTextField(labelWithString: "Brightness")
    let brightnessField = NSTextField(string: "")
    var sliderLabels: [NSTextField] = []
    var sliders: [_NSColorSliderView] = []
    var sliderFields: [NSTextField] = []
    let listPicker = _NSColorListPicker(frame: .zero)
    let crayons = _NSColorCrayonView(frame: .zero)
    let alphaLabel = NSTextField(labelWithString: "Opacity")
    let alphaSlider = _NSColorSliderView(frame: .zero)
    let alphaField = NSTextField(string: "")
    let favorites = _NSColorFavoritesView(frame: .zero)

    private var color: NSColor = .white
    private static let modeAction = Selector(("_colorPanelMode:"))
    private static let sliderKindAction = Selector(("_colorPanelSliderKind:"))
    private static let hexAction = Selector(("_colorPanelHex:"))
    private static let fieldAction = Selector(("_colorPanelField:"))

    override init(frame: NSRect) {
        modeControl = NSSegmentedControl(labels: _NSColorPanelView.kindNames, trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: frame)
        modeControl.target = self
        modeControl.action = _NSColorPanelView.modeAction
        setActionHandler(for: _NSColorPanelView.modeAction) { [weak self] _ in self?.modeControlChanged() }
        addSubview(modeControl)
        preview.onDrop = { [weak self] c in self?.userChanged(c, final: true) }
        preview.toolTip = "Drag to copy the color"
        addSubview(preview)
        hexLabel.font = NSFont.systemFont(ofSize: 11)
        addSubview(hexLabel)
        hexField.target = self
        hexField.action = _NSColorPanelView.hexAction
        hexField.setAccessibilityLabel("Hex")
        setActionHandler(for: _NSColorPanelView.hexAction) { [weak self] _ in self?.hexChanged() }
        addSubview(hexField)
        sliderKind.addItems(withTitles: ["Gray Scale Slider", "RGB Sliders", "CMYK Sliders", "HSB Sliders"])
        sliderKind.selectItem(at: 1)
        sliderKind.target = self
        sliderKind.action = _NSColorPanelView.sliderKindAction
        setActionHandler(for: _NSColorPanelView.sliderKindAction) { [weak self] _ in self?.sliderKindChanged() }
        addSubview(sliderKind)
        wheel.onChange = { [weak self] h, s, final in
            guard let self else { return }
            self.userChanged(NSColor(hue: h, saturation: s, brightness: self.wheel.brightness, alpha: self.color.alphaComponent), final: final)
        }
        addSubview(wheel)
        brightnessLabel.font = NSFont.systemFont(ofSize: 11)
        addSubview(brightnessLabel)
        brightnessSlider.onChange = { [weak self] v, final in
            guard let self else { return }
            self.userChanged(NSColor(hue: self.wheel.hue, saturation: self.wheel.saturation, brightness: v, alpha: self.color.alphaComponent), final: final)
        }
        brightnessSlider.setAccessibilityLabel("Brightness")
        addSubview(brightnessSlider)
        brightnessField.alignment = .right
        brightnessField.tag = 100
        brightnessField.target = self
        brightnessField.action = _NSColorPanelView.fieldAction
        addSubview(brightnessField)
        for i in 0..<4 {
            let label = NSTextField(labelWithString: "")
            label.font = NSFont.systemFont(ofSize: 11)
            let slider = _NSColorSliderView(frame: .zero)
            let field = NSTextField(string: "")
            field.alignment = .right
            field.tag = i
            field.target = self
            field.action = _NSColorPanelView.fieldAction
            slider.onChange = { [weak self] v, final in self?.sliderChanged(i, value: v, final: final) }
            sliderLabels.append(label); sliders.append(slider); sliderFields.append(field)
            addSubview(label); addSubview(slider); addSubview(field)
        }
        setActionHandler(for: _NSColorPanelView.fieldAction) { [weak self] sender in self?.fieldChanged(sender as? NSTextField) }
        listPicker.onPick = { [weak self] c in self?.userChanged(c, final: true) }
        addSubview(listPicker)
        crayons.onPick = { [weak self] c in self?.userChanged(c, final: true) }
        addSubview(crayons)
        alphaLabel.font = NSFont.systemFont(ofSize: 11)
        addSubview(alphaLabel)
        alphaSlider.showsCheckerboard = true
        alphaSlider.setAccessibilityLabel("Opacity")
        alphaSlider.onChange = { [weak self] v, final in
            guard let self else { return }
            self.userChanged(self.color.withAlphaComponent(v), final: final)
        }
        addSubview(alphaSlider)
        alphaField.alignment = .right
        alphaField.tag = 101
        alphaField.target = self
        alphaField.action = _NSColorPanelView.fieldAction
        addSubview(alphaField)
        favorites.onPick = { [weak self] c in self?.userChanged(c, final: true) }
        addSubview(favorites)
        reloadLists()
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(bounds)
    }

    // MARK: Modes

    private static func kind(of mode: NSColorPanel.Mode) -> Int {
        switch mode {
        case .wheel: return 0
        case .gray, .RGB, .CMYK, .HSB: return 1
        case .colorList, .customPalette: return 2
        case .crayon: return 3
        case .none: return -1
        }
    }

    func setAvailableModes(_ mask: NSColorPanel.Options) {
        var kinds: [Int] = []
        if mask.contains(.wheelModeMask) { kinds.append(0) }
        if !mask.intersection([.grayModeMask, .rgbModeMask, .cmykModeMask, .hsbModeMask]).isEmpty { kinds.append(1) }
        if !mask.intersection([.colorListModeMask, .customPaletteModeMask]).isEmpty { kinds.append(2) }
        if mask.contains(.crayonModeMask) { kinds.append(3) }
        if kinds.isEmpty { kinds = [0] }
        availableKinds = kinds
        modeControl.segmentCount = kinds.count
        for (i, k) in kinds.enumerated() { modeControl.setLabel(_NSColorPanelView.kindNames[k], forSegment: i) }
        if let i = kinds.firstIndex(of: kind) { modeControl.selectedSegment = i } else if let first = kinds.first { setMode(_NSColorPanelView.mode(ofKind: first)) }
        needsLayout = true
    }

    private static func mode(ofKind kind: Int) -> NSColorPanel.Mode {
        switch kind {
        case 1: return .RGB
        case 2: return .colorList
        case 3: return .crayon
        default: return .wheel
        }
    }

    func setMode(_ mode: NSColorPanel.Mode) {
        let k = _NSColorPanelView.kind(of: mode)
        guard k >= 0 else { return }
        kind = k
        if k == 1 {
            sliderMode = mode
            sliderKind.selectItem(at: [NSColorPanel.Mode.gray, .RGB, .CMYK, .HSB].firstIndex(of: mode) ?? 1)
        }
        if let i = availableKinds.firstIndex(of: k) { modeControl.selectedSegment = i }
        sync(color: color)
        needsLayout = true
        needsDisplay = true
    }

    var currentMode: NSColorPanel.Mode {
        switch kind {
        case 1: return sliderMode
        case 2: return .colorList
        case 3: return .crayon
        default: return .wheel
        }
    }

    private func modeControlChanged() {
        let i = modeControl.selectedSegment
        guard i >= 0, i < availableKinds.count else { return }
        let mode = availableKinds[i] == 1 ? sliderMode : _NSColorPanelView.mode(ofKind: availableKinds[i])
        panel?.mode = mode
    }

    private func sliderKindChanged() {
        let modes: [NSColorPanel.Mode] = [.gray, .RGB, .CMYK, .HSB]
        let i = sliderKind.indexOfSelectedItem
        guard i >= 0, i < modes.count else { return }
        panel?.mode = modes[i]
    }

    func reloadLists() {
        listPicker.reload(lists: panel?._colorLists ?? NSColorList.availableColorLists)
    }

    // MARK: Layout

    private let margin: CGFloat = 12

    private var pickerHeight: CGFloat {
        switch kind {
        case 1:
            let rows = sliderMode == .gray ? 1 : (sliderMode == .CMYK ? 4 : 3)
            return CGFloat(rows) * 30 + 6
        case 2: return 184
        case 3: return 170
        default: return 190
        }
    }

    var preferredHeight: CGFloat {
        var h: CGFloat = 10 + 24 + 10 + 48 + pickerHeight
        if showsAlpha { h += 30 }
        if let a = accessory { h += a.frame.height + 8 }
        return h + 26 + 12
    }

    override func layout() {
        super.layout()
        let w = bounds.width - 2 * margin
        var y: CGFloat = 10
        modeControl.frame = NSRect(x: margin, y: y, width: w, height: 24)
        y += 34
        preview.frame = NSRect(x: margin, y: y, width: 48, height: 36)
        hexLabel.frame = NSRect(x: margin + 56, y: y + 10, width: 26, height: 16)
        hexField.frame = NSRect(x: margin + 84, y: y + 7, width: 68, height: 22)
        sliderKind.isHidden = kind != 1
        sliderKind.frame = NSRect(x: margin + w - 112, y: y + 6, width: 112, height: 24)
        y += 48
        let pickerTop = y
        let ph = pickerHeight
        wheel.isHidden = kind != 0
        brightnessSlider.isHidden = kind != 0
        brightnessLabel.isHidden = kind != 0
        brightnessField.isHidden = kind != 0
        if kind == 0 {
            wheel.frame = NSRect(x: margin, y: pickerTop, width: w, height: ph - 30)
            brightnessLabel.frame = NSRect(x: margin, y: pickerTop + ph - 26, width: 64, height: 16)
            brightnessSlider.frame = NSRect(x: margin + 66, y: pickerTop + ph - 30, width: w - 66 - 52, height: 24)
            brightnessField.frame = NSRect(x: margin + w - 48, y: pickerTop + ph - 29, width: 48, height: 22)
        }
        let rows = kind == 1 ? (sliderMode == .gray ? 1 : (sliderMode == .CMYK ? 4 : 3)) : 0
        for i in 0..<4 {
            let shown = i < rows
            sliderLabels[i].isHidden = !shown
            sliders[i].isHidden = !shown
            sliderFields[i].isHidden = !shown
            if shown {
                let ry = pickerTop + CGFloat(i) * 30
                sliderLabels[i].frame = NSRect(x: margin, y: ry + 4, width: 64, height: 16)
                sliders[i].frame = NSRect(x: margin + 66, y: ry, width: w - 66 - 52, height: 24)
                sliderFields[i].frame = NSRect(x: margin + w - 48, y: ry + 1, width: 48, height: 22)
            }
        }
        listPicker.isHidden = kind != 2
        if kind == 2 { listPicker.frame = NSRect(x: margin, y: pickerTop, width: w, height: ph - 4) }
        crayons.isHidden = kind != 3
        if kind == 3 { crayons.frame = NSRect(x: margin, y: pickerTop, width: w, height: ph - 4) }
        y += ph
        alphaLabel.isHidden = !showsAlpha
        alphaSlider.isHidden = !showsAlpha
        alphaField.isHidden = !showsAlpha
        if showsAlpha {
            alphaLabel.frame = NSRect(x: margin, y: y + 4, width: 64, height: 16)
            alphaSlider.frame = NSRect(x: margin + 66, y: y, width: w - 66 - 52, height: 24)
            alphaField.frame = NSRect(x: margin + w - 48, y: y + 1, width: 48, height: 22)
            y += 30
        }
        if let a = accessory {
            a.frame = NSRect(x: margin, y: y, width: w, height: a.frame.height)
            y += a.frame.height + 8
        }
        favorites.frame = NSRect(x: margin, y: y, width: w, height: 26)
    }

    // MARK: State

    private static func percent(_ v: CGFloat) -> String { String(Int((_NSColorMath.clamp(v) * 100).rounded())) }

    /// Shows `c` in every control without reporting a change.
    func sync(color c: NSColor) {
        color = c
        preview.color = c
        favorites.current = c
        hexField.stringValue = _NSColorMath.hex(c)
        if c.saturationComponent > 0.001 { wheel.hue = c.hueComponent }
        wheel.saturation = c.saturationComponent
        wheel.brightness = c.brightnessComponent
        wheel.needsDisplay = true
        brightnessSlider.value = c.brightnessComponent
        brightnessSlider.stops = [.black, NSColor(hue: wheel.hue, saturation: wheel.saturation, brightness: 1, alpha: 1)]
        brightnessField.stringValue = _NSColorPanelView.percent(c.brightnessComponent)
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        switch sliderMode {
        case .gray:
            setRow(0, "White", c.whiteComponent, [.black, .white], _NSColorPanelView.percent(c.whiteComponent))
        case .CMYK:
            let (cy, m, ye, k) = _NSColorMath.cmyk(c)
            setRow(0, "Cyan", cy, [_NSColorMath.color(cyan: 0, magenta: m, yellow: ye, black: k, alpha: 1), _NSColorMath.color(cyan: 1, magenta: m, yellow: ye, black: k, alpha: 1)], _NSColorPanelView.percent(cy))
            setRow(1, "Magenta", m, [_NSColorMath.color(cyan: cy, magenta: 0, yellow: ye, black: k, alpha: 1), _NSColorMath.color(cyan: cy, magenta: 1, yellow: ye, black: k, alpha: 1)], _NSColorPanelView.percent(m))
            setRow(2, "Yellow", ye, [_NSColorMath.color(cyan: cy, magenta: m, yellow: 0, black: k, alpha: 1), _NSColorMath.color(cyan: cy, magenta: m, yellow: 1, black: k, alpha: 1)], _NSColorPanelView.percent(ye))
            setRow(3, "Black", k, [_NSColorMath.color(cyan: cy, magenta: m, yellow: ye, black: 0, alpha: 1), _NSColorMath.color(cyan: cy, magenta: m, yellow: ye, black: 1, alpha: 1)], _NSColorPanelView.percent(k))
        case .HSB:
            let h = wheel.hue, s = c.saturationComponent, v = c.brightnessComponent
            setRow(0, "Hue", h, (0...6).map { NSColor(hue: CGFloat($0) / 6, saturation: 1, brightness: 1, alpha: 1) }, String(Int((h * 360).rounded())))
            setRow(1, "Saturation", s, [NSColor(hue: h, saturation: 0, brightness: v, alpha: 1), NSColor(hue: h, saturation: 1, brightness: v, alpha: 1)], _NSColorPanelView.percent(s))
            setRow(2, "Brightness", v, [.black, NSColor(hue: h, saturation: s, brightness: 1, alpha: 1)], _NSColorPanelView.percent(v))
        default:
            setRow(0, "Red", r, [NSColor(red: 0, green: g, blue: b, alpha: 1), NSColor(red: 1, green: g, blue: b, alpha: 1)], String(Int((r * 255).rounded())))
            setRow(1, "Green", g, [NSColor(red: r, green: 0, blue: b, alpha: 1), NSColor(red: r, green: 1, blue: b, alpha: 1)], String(Int((g * 255).rounded())))
            setRow(2, "Blue", b, [NSColor(red: r, green: g, blue: 0, alpha: 1), NSColor(red: r, green: g, blue: 1, alpha: 1)], String(Int((b * 255).rounded())))
        }
        alphaSlider.value = c.alphaComponent
        alphaSlider.stops = [c.withAlphaComponent(0), c.withAlphaComponent(1)]
        alphaField.stringValue = _NSColorPanelView.percent(c.alphaComponent)
        crayons.select(matching: c)
        needsDisplay = true
    }

    private func setRow(_ i: Int, _ label: String, _ value: CGFloat, _ stops: [NSColor], _ text: String) {
        sliderLabels[i].stringValue = label
        sliderLabels[i].setAccessibilityLabel(label)
        sliders[i].value = value
        sliders[i].stops = stops
        sliders[i].setAccessibilityLabel(label)
        sliderFields[i].stringValue = text
        sliderFields[i].setAccessibilityLabel(label)
    }

    /// A control changed the colour.
    private func userChanged(_ c: NSColor, final: Bool) {
        panel?._userSetColor(c, final: final)
    }

    private func sliderChanged(_ row: Int, value v: CGFloat, final: Bool) {
        let a = color.alphaComponent
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        let c: NSColor
        switch sliderMode {
        case .gray: c = NSColor(white: v, alpha: a)
        case .CMYK:
            var (cy, m, ye, k) = _NSColorMath.cmyk(color)
            switch row { case 0: cy = v; case 1: m = v; case 2: ye = v; default: k = v }
            c = _NSColorMath.color(cyan: cy, magenta: m, yellow: ye, black: k, alpha: a)
        case .HSB:
            var h = wheel.hue, s = color.saturationComponent, br = color.brightnessComponent
            switch row { case 0: h = v; case 1: s = v; default: br = v }
            wheel.hue = h
            c = NSColor(hue: h, saturation: s, brightness: br, alpha: a)
        default:
            switch row {
            case 0: c = NSColor(red: v, green: g, blue: b, alpha: a)
            case 1: c = NSColor(red: r, green: v, blue: b, alpha: a)
            default: c = NSColor(red: r, green: g, blue: v, alpha: a)
            }
        }
        userChanged(c, final: final)
    }

    private func hexChanged() {
        guard let c = _NSColorMath.color(hex: hexField.stringValue, alpha: color.alphaComponent) else { hexField.stringValue = _NSColorMath.hex(color); return }
        userChanged(c, final: true)
    }

    private func fieldChanged(_ field: NSTextField?) {
        guard let field, let v = Double(field.stringValue.trimmingCharacters(in: .whitespaces)) else { sync(color: color); return }
        switch field.tag {
        case 100: brightnessSlider.value = _NSColorMath.clamp(CGFloat(v) / 100); brightnessSlider.onChange?(brightnessSlider.value, true)
        case 101: alphaSlider.value = _NSColorMath.clamp(CGFloat(v) / 100); alphaSlider.onChange?(alphaSlider.value, true)
        default:
            let row = field.tag
            let scale: CGFloat
            switch sliderMode {
            case .RGB: scale = 255
            case .HSB: scale = row == 0 ? 360 : 100
            default: scale = 100
            }
            sliderChanged(row, value: _NSColorMath.clamp(CGFloat(v) / scale), final: true)
        }
    }
}
