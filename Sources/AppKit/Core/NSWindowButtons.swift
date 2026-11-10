// The standard window buttons (close, miniaturize, zoom) for windows whose content covers
// the title bar, and for title bars the platform leaves to the package (Wayland client-side
// decorations): neither the Win32 custom frame nor an undecorated X11 or Wayland window
// supplies caption controls, so this port draws them itself, in an overlay root above the
// content view that hosting views managing their own subviews never see.
//
// The backend picks the look (ADR-0022): macOS and Linux show AppKit's traffic lights at
// the top-left; Windows shows its own caption buttons at the top-right (minimise,
// maximise/restore, close; Fluent glyphs, hover and pressed fills, close in red), and the
// Win32 window reports them as HTMINBUTTON/HTMAXBUTTON/HTCLOSE so the snap layouts flyout
// of Windows 11 appears over the maximise button.
//
// The row is flipped and spans the title band, like AppKit's theme frame, so an application
// that moves a button with `setFrameOrigin(_:)` (y from the top) keeps its position across
// relayouts; the window only places buttons it has not moved.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One standard button. `standardWindowButton(_:)` returns these.
@MainActor
final class _NSWindowButton: NSButton {
    let kind: NSWindow.ButtonType
    /// The look: traffic light or Windows caption button.
    var style: PlatformWindowButtonStyle = .trafficLights {
        didSet { if style != oldValue { needsDisplay = true; invalidateIntrinsicContentSize() } }
    }
    /// Traffic lights: the pointer is over the group, so the glyphs show, as on macOS.
    var showsGlyph = false { didSet { if showsGlyph != oldValue { needsDisplay = true } } }
    /// Caption buttons: the pointer is over this button, so it shows its hover fill.
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    /// Grey when the window is not key.
    var isActive = true { didSet { if isActive != oldValue { needsDisplay = true } } }
    /// The application moved or resized the button (`setFrameOrigin`, `frame`): the row
    /// leaves it where it is, as AppKit's theme frame does.
    private(set) var hasCustomFrame = false
    /// Set by the row while it places the button, so its own placement is not "custom".
    fileprivate var placedByRow = false
    private var pressed = false

    static let trafficLightSize = NSSize(width: 12, height: 12)
    /// Windows 11 caption buttons are 46 by 32 at 100 %; the band here is 28 points tall.
    static let captionSize = NSSize(width: 46, height: _NSWindowButtonsView.height)

    init(kind: NSWindow.ButtonType, style: PlatformWindowButtonStyle = .trafficLights) {
        self.kind = kind
        self.style = style
        super.init(frame: NSRect(origin: .zero, size: style == .caption ? _NSWindowButton.captionSize : _NSWindowButton.trafficLightSize))
        isBordered = false
        title = ""
        refusesFirstResponder = true
    }
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { style == .caption ? _NSWindowButton.captionSize : _NSWindowButton.trafficLightSize }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        if !placedByRow, newOrigin != frame.origin { hasCustomFrame = true }
        super.setFrameOrigin(newOrigin)
    }
    override func setFrameSize(_ newSize: NSSize) {
        if !placedByRow, newSize != frame.size { hasCustomFrame = true }
        super.setFrameSize(newSize)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .trafficLights: drawTrafficLight()
        case .caption: drawCaptionButton()
        }
    }

    private var trafficLightFill: NSColor {
        guard isEnabled, isActive else { return NSColor(white: 0.82, alpha: 1) }
        switch kind {
        case .closeButton: return NSColor(red: 1.0, green: 0.373, blue: 0.341, alpha: 1)
        case .miniaturizeButton: return NSColor(red: 1.0, green: 0.741, blue: 0.180, alpha: 1)
        default: return NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1)
        }
    }

    private func drawTrafficLight() {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let circle = NSBezierPath(ovalIn: r)
        var color = trafficLightFill
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

    /// Windows 11: a flat 46-wide cell; a subtle fill on hover (red for close), a lighter
    /// one while pressed; 10-point Fluent glyphs, grey when the window is inactive, lighter
    /// still when the button is disabled; the maximise glyph becomes "restore" once zoomed.
    private func drawCaptionButton() {
        let dark = effectiveAppearance.isDark
        let closeHot = kind == .closeButton && isEnabled && (isHovered || pressed)
        if isEnabled, isHovered || pressed {
            let fill: NSColor
            if closeHot {
                fill = NSColor(red: 0.769, green: 0.169, blue: 0.110, alpha: pressed ? 0.9 : 1)   // #C42B1C
            } else {
                fill = NSColor(white: dark ? 1 : 0, alpha: pressed ? 0.04 : 0.06)
            }
            fill.setFill()
            NSBezierPath(rect: bounds).fill()
        }
        var glyphColor: NSColor
        if closeHot {
            glyphColor = NSColor(white: 1, alpha: pressed ? 0.7 : 1)
        } else if !isEnabled {
            glyphColor = NSColor(white: dark ? 1 : 0, alpha: 0.36)
        } else if !isActive {
            glyphColor = NSColor(white: dark ? 1 : 0, alpha: 0.5)
        } else {
            glyphColor = NSColor(white: dark ? 1 : 0, alpha: pressed ? 0.6 : 0.9)
        }
        if !isEnabled, !isActive { glyphColor = glyphColor.withAlphaComponent(0.25) }
        glyphColor.setStroke()
        // Pixel-aligned at integral scales: the 10-point glyph box is centred on a half point.
        let c = NSPoint(x: bounds.midX.rounded(.down) + 0.5, y: bounds.midY.rounded(.down) + 0.5)
        let h: CGFloat = 5
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineCapStyle = .square
        switch kind {
        case .miniaturizeButton:
            path.move(to: NSPoint(x: c.x - h, y: c.y)); path.line(to: NSPoint(x: c.x + h, y: c.y))
        case .zoomButton where window?.isZoomed ?? false:
            // Restore: the front square, and the back one offset up and to the right,
            // visible only where the front does not cover it.
            let front = NSRect(x: c.x - h, y: c.y - h, width: 8, height: 8)
            path.appendRect(front)
            path.move(to: NSPoint(x: front.minX + 2, y: front.maxY)); path.line(to: NSPoint(x: front.minX + 2, y: front.maxY + 2))
            path.line(to: NSPoint(x: front.maxX + 2, y: front.maxY + 2)); path.line(to: NSPoint(x: front.maxX + 2, y: front.minY + 2))
            path.line(to: NSPoint(x: front.maxX, y: front.minY + 2))
        case .zoomButton:
            path.appendRect(NSRect(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h))
        default:
            path.move(to: NSPoint(x: c.x - h, y: c.y - h)); path.line(to: NSPoint(x: c.x + h, y: c.y + h))
            path.move(to: NSPoint(x: c.x - h, y: c.y + h)); path.line(to: NSPoint(x: c.x + h, y: c.y - h))
        }
        path.stroke()
    }

    // MARK: Tracking

    private var pressRect: NSRect { style == .caption ? bounds : bounds.insetBy(dx: -4, dy: -4) }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = pressRect.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, pressed else { return }
        pressed = false
        needsDisplay = true
        if pressRect.contains(convert(event.locationInWindow, from: nil)) { _fireAction() }
    }
}

/// The row of the three standard buttons: a flipped strip across the title band whose
/// buttons sit at its left (traffic lights) or its right (caption buttons). Only the
/// buttons themselves hit-test; the rest of the strip is transparent to the toolbar and
/// the content below it, and drags the window through the band rule of `NSWindow`.
@MainActor
final class _NSWindowButtonsView: NSView {
    let close: _NSWindowButton
    let miniaturize: _NSWindowButton
    let zoom: _NSWindowButton
    /// In the order they are laid out, leading to trailing.
    var buttons: [_NSWindowButton] { style == .caption ? [miniaturize, zoom, close] : [close, miniaturize, zoom] }
    static let height: CGFloat = 28
    /// The width the traffic lights take at the leading edge (three circles and their margins).
    static let width: CGFloat = 72
    /// The width the caption buttons take at the trailing edge.
    static let captionWidth: CGFloat = 3 * _NSWindowButton.captionSize.width
    /// The horizontal extent the buttons of a style occupy, from the edge they sit at.
    static func extent(for style: PlatformWindowButtonStyle) -> CGFloat { style == .caption ? captionWidth : width }

    var style: PlatformWindowButtonStyle {
        didSet {
            guard style != oldValue else { return }
            for b in [close, miniaturize, zoom] { b.style = style; b.showsGlyph = false; b.isHovered = false }
            placeButtons()
            needsDisplay = true
        }
    }

    init(style: PlatformWindowButtonStyle = .trafficLights) {
        self.style = style
        close = _NSWindowButton(kind: .closeButton, style: style)
        miniaturize = _NSWindowButton(kind: .miniaturizeButton, style: style)
        zoom = _NSWindowButton(kind: .zoomButton, style: style)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: _NSWindowButtonsView.height))
        wantsLayer = true
        for b in [close, miniaturize, zoom] { addSubview(b) }
        placeButtons()
    }
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }       // y from the top, as AppKit's theme frame
    override var mouseDownCanMoveWindow: Bool { true }      // the gaps drag the window, as on macOS
    override var acceptsFirstResponder: Bool { false }

    /// The default places, in the row's flipped coordinates, for buttons the application
    /// has not moved: circles 20 points apart from x = 12, centred in the band; caption
    /// cells abutting the trailing edge, minimise, maximise, close.
    private func placeButtons() {
        for (i, b) in buttons.enumerated() where !b.hasCustomFrame {
            b.placedByRow = true
            switch style {
            case .trafficLights:
                b.frame = NSRect(x: 12 + CGFloat(i) * 20, y: (_NSWindowButtonsView.height - 12) / 2, width: 12, height: 12)
            case .caption:
                let w = _NSWindowButton.captionSize.width
                b.frame = NSRect(x: bounds.width - w * CGFloat(3 - i), y: 0, width: w, height: _NSWindowButton.captionSize.height)
            }
            b.placedByRow = false
        }
    }

    /// The union of the buttons' frames (row coordinates): what hovers the traffic lights'
    /// glyphs and what the row claims for dragging between them.
    var buttonsFrame: NSRect {
        let visible = buttons.filter { !$0.isHidden }
        guard let first = visible.first else { return .null }
        var r = first.frame
        for b in visible.dropFirst() { r = r.union(b.frame) }
        return style == .caption ? r : r.insetBy(dx: -8, dy: -8)
    }

    /// Only the buttons (and the strip around them) answer; the rest of the band belongs to
    /// the toolbar and the content below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let p = _fromSuperview(point)
        guard bounds.contains(p) else { return nil }
        for b in buttons.reversed() { if let hit = b.hitTest(p) { return hit } }
        return buttonsFrame.contains(p) ? self : nil
    }

    /// Places the row across the top of a content area of `size` and applies the style mask.
    func layout(in size: NSSize, styleMask: NSWindow.StyleMask, isKey: Bool) {
        let widthChanged = frame.width != size.width
        frame = NSRect(x: 0, y: size.height - _NSWindowButtonsView.height, width: size.width, height: _NSWindowButtonsView.height)
        if widthChanged { placeButtons() }
        close.isEnabled = styleMask.contains(.closable)
        miniaturize.isEnabled = styleMask.contains(.miniaturizable)
        zoom.isEnabled = styleMask.contains(.resizable)
        zoom.needsDisplay = true        // maximise or restore glyph
        for b in buttons { b.isActive = isKey }
    }

    /// Tracks the pointer: the traffic lights show their glyphs while it is over the
    /// group; a caption button shows its hover fill while it is over that button.
    func updateHover(_ windowPoint: NSPoint?) {
        let p = windowPoint.map { convert($0, from: nil) }
        switch style {
        case .trafficLights:
            let over = p.map { buttonsFrame.contains($0) } ?? false
            for b in buttons { b.showsGlyph = over }
        case .caption:
            for b in buttons { b.isHovered = p.map { !b.isHidden && b.isEnabled && b.frame.contains($0) } ?? false }
        }
    }
}
