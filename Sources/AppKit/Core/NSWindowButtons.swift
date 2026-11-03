// The standard window buttons (close, miniaturize, zoom) for windows whose content covers
// the title bar: AppKit draws its traffic lights over such content, and so does this port,
// on every platform, since neither the Win32 custom frame nor an undecorated X11 or
// Wayland window supplies caption controls. The buttons live in an overlay root above the
// content view, so hosting views that manage their own subviews never see them.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One traffic light. `standardWindowButton(_:)` returns these.
@MainActor
final class _NSWindowButton: NSButton {
    let kind: NSWindow.ButtonType
    /// The pointer is over the group: glyphs show, as on macOS.
    var showsGlyph = false { didSet { if showsGlyph != oldValue { needsDisplay = true } } }
    /// Grey when the window is not key.
    var isActive = true { didSet { if isActive != oldValue { needsDisplay = true } } }
    private var pressed = false

    init(kind: NSWindow.ButtonType) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
        isBordered = false
        title = ""
        refusesFirstResponder = true
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 12, height: 12) }

    private var fill: NSColor {
        guard isEnabled, isActive else { return NSColor(white: 0.82, alpha: 1) }
        switch kind {
        case .closeButton: return NSColor(red: 1.0, green: 0.373, blue: 0.341, alpha: 1)
        case .miniaturizeButton: return NSColor(red: 1.0, green: 0.741, blue: 0.180, alpha: 1)
        default: return NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let circle = NSBezierPath(ovalIn: r)
        var color = fill
        if pressed { color = color.withAlphaComponent(0.6) }
        color.setFill()
        circle.fill()
        NSColor(white: 0, alpha: 0.15).setStroke()
        circle.lineWidth = 0.5
        circle.stroke()
        guard showsGlyph, isEnabled else { return }
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.5
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let d: CGFloat = 2.6
        switch kind {
        case .closeButton:
            glyph.move(to: NSPoint(x: c.x - d, y: c.y - d)); glyph.line(to: NSPoint(x: c.x + d, y: c.y + d))
            glyph.move(to: NSPoint(x: c.x - d, y: c.y + d)); glyph.line(to: NSPoint(x: c.x + d, y: c.y - d))
        case .miniaturizeButton:
            glyph.move(to: NSPoint(x: c.x - d - 0.5, y: c.y)); glyph.line(to: NSPoint(x: c.x + d + 0.5, y: c.y))
        default:
            glyph.move(to: NSPoint(x: c.x - d - 0.5, y: c.y)); glyph.line(to: NSPoint(x: c.x + d + 0.5, y: c.y))
            glyph.move(to: NSPoint(x: c.x, y: c.y - d - 0.5)); glyph.line(to: NSPoint(x: c.x, y: c.y + d + 0.5))
        }
        NSColor(white: 0, alpha: 0.55).setStroke()
        glyph.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, pressed else { return }
        pressed = false
        needsDisplay = true
        if bounds.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) { _fireAction() }
    }
}

/// The row of three buttons at the window's top-left.
@MainActor
final class _NSWindowButtonsView: NSView {
    let close = _NSWindowButton(kind: .closeButton)
    let miniaturize = _NSWindowButton(kind: .miniaturizeButton)
    let zoom = _NSWindowButton(kind: .zoomButton)
    var buttons: [_NSWindowButton] { [close, miniaturize, zoom] }
    static let height: CGFloat = 28
    static let width: CGFloat = 72

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: _NSWindowButtonsView.width, height: _NSWindowButtonsView.height))
        wantsLayer = true
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: 12 + CGFloat(i) * 20, y: (_NSWindowButtonsView.height - 12) / 2, width: 12, height: 12)
            addSubview(b)
        }
    }
    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { true }      // the gaps drag the window, as on macOS
    override var acceptsFirstResponder: Bool { false }

    /// Places the row at the top-left of a content area of `size` and applies the style mask.
    func layout(in size: NSSize, styleMask: NSWindow.StyleMask, isKey: Bool) {
        frame = NSRect(x: 0, y: size.height - _NSWindowButtonsView.height, width: _NSWindowButtonsView.width, height: _NSWindowButtonsView.height)
        close.isEnabled = styleMask.contains(.closable)
        miniaturize.isEnabled = styleMask.contains(.miniaturizable)
        zoom.isEnabled = styleMask.contains(.resizable)
        for b in buttons { b.isActive = isKey }
    }

    /// Tracks the pointer: glyphs show while it is over the row.
    func updateHover(_ windowPoint: NSPoint?) {
        let over = windowPoint.map { frame.contains($0) } ?? false
        for b in buttons { b.showsGlyph = over }
    }
}
