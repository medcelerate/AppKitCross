// NSColorWell (hand-written; seeded from the generated stub, see tools/apigen)
//
// A control showing a colour that opens the shared colour panel when clicked (ADR-0022).
// While a well is active the panel's target is the well and its action `takeColorFrom:`,
// so the panel's changes land in the well, which then sends its own action. Wells are
// drag sources and destinations for colours (`NSPasteboard.PasteboardType.color`).

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell
@MainActor open class NSColorWell: NSControl, NSDraggingSource {
    // MARK: Storage
    private var _color: NSColor = .black
    private var _isActive = false
    private var _isBordered = true
    private var _style: NSColorWell.Style = .default
    private var _pulldownAction: Selector? = nil
    private weak var _pulldownTarget: AnyObject? = nil
    private var _supportsAlpha = true
    private var _image: NSImage? = nil
    private var _tracking = false
    private var _mouseDownPoint: NSPoint = .zero
    private var _dragStarted = false
    private var _dropHighlight = false
    private final class _WeakWell { weak var well: NSColorWell?; init(_ w: NSColorWell) { well = w } }
    nonisolated(unsafe) private static var _activeWells: [_WeakWell] = []
    internal static let takeColorAction = Selector(("takeColorFrom:"))

    @MainActor open override class func _makeDefaultCell() -> NSCell? { NSActionCell(textCell: "") }

    private func _setUp() {
        registerForDraggedTypes([.color])
        setActionHandler(for: NSColorWell.takeColorAction) { [weak self] sender in self?.takeColorFrom(sender) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        _setUp()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        MainActor.assumeIsolated { _setUp() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/init(style:)
    @available(macOS 13.0, *)
    @MainActor public convenience init(style: NSColorWell.Style) {
        self.init(frame: NSRect(x: 0, y: 0, width: style == .expanded ? 64 : (style == .minimal ? 28 : 44), height: style == .minimal ? 20 : 24))
        _style = style
    }

    open override var description: String { MainActor.assumeIsolated { "<NSColorWell frame=\(frame) \(_color)\(_isActive ? " active" : "")>" } }

    @MainActor open override var intrinsicContentSize: NSSize {
        switch _styleRaw {
        case 1: return NSSize(width: 28, height: 20)
        case 2: return NSSize(width: 64, height: 24)
        default: return NSSize(width: 44, height: 24)
        }
    }
    /// The style as a number, so the class needs no availability gate internally.
    private var _styleRaw: Int { _style.rawValue }

    @MainActor open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder }
    @MainActor open override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    /// The rectangle the colour fills: inside the bezel for a bordered well, the bounds otherwise.
    internal var _swatchRect: NSRect {
        var r = bounds
        if _styleRaw == 2 { r.size.width -= 18 }
        return (_isBordered && _styleRaw == 0) ? r.insetBy(dx: 5, dy: 5) : r.insetBy(dx: 1, dy: 1)
    }
    /// The pull-down segment of an expanded well.
    internal var _pulldownRect: NSRect? {
        guard _styleRaw == 2 else { return nil }
        return NSRect(x: bounds.maxX - 18, y: bounds.minY, width: 18, height: bounds.height)
    }

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = _styleRaw == 1 ? 4 : 6
        let bezel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if _isBordered || _styleRaw != 0 {
            NSColor.controlColor.setFill()
            bezel.fill()
        }
        drawWell(inside: _swatchRect)
        if let pull = _pulldownRect {
            NSColor.separatorColor.setFill()
            NSBezierPath.fill(NSRect(x: pull.minX, y: pull.minY + 4, width: 1, height: pull.height - 8))
            let chevron = NSBezierPath()
            let cx = pull.midX, cy = pull.midY
            chevron.move(to: NSPoint(x: cx - 3.5, y: cy + 1.5))
            chevron.line(to: NSPoint(x: cx, y: cy - 2))
            chevron.line(to: NSPoint(x: cx + 3.5, y: cy + 1.5))
            chevron.lineWidth = 1.5
            (isEnabled ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
            chevron.stroke()
        }
        if _isBordered || _styleRaw != 0 {
            (_isActive || _dropHighlight ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            bezel.lineWidth = _isActive || _dropHighlight ? 2 : 1
            bezel.stroke()
        } else if _isActive || _dropHighlight {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            ring.stroke()
        }
        if !isEnabled {
            NSColor.windowBackgroundColor.withAlphaComponent(0.5).setFill()
            bezel.fill()
        }
    }

    /// Draws the colour (over a checkerboard when it is translucent) in `insideRect`.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/drawwell(inside:)
    @MainActor open func drawWell(inside insideRect: NSRect) {
        let radius: CGFloat = _styleRaw == 0 && _isBordered ? 2 : 4
        let path = NSBezierPath(roundedRect: insideRect, xRadius: radius, yRadius: radius)
        if _color.alphaComponent < 1 {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSColorWell._drawCheckerboard(in: insideRect)
            NSGraphicsContext.restoreGraphicsState()
        }
        _color.setFill()
        path.fill()
        if let image = _image {
            image.draw(in: insideRect.insetBy(dx: 2, dy: 2))
        }
    }

    /// The checkerboard translucent colours show over, in the panel and the wells.
    internal static func _drawCheckerboard(in rect: NSRect, cell: CGFloat = 6) {
        NSColor.white.setFill()
        NSBezierPath.fill(rect)
        NSColor(white: 0.75, alpha: 1).setFill()
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : cell)
            while x < rect.maxX {
                NSBezierPath.fill(NSRect(x: x, y: y, width: min(cell, rect.maxX - x), height: min(cell, rect.maxY - y)))
                x += cell * 2
            }
            y += cell
            row += 1
        }
    }

    // MARK: Mouse

    @MainActor open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        _tracking = true
        _dragStarted = false
        _mouseDownPoint = convert(event.locationInWindow, from: nil)
    }
    @MainActor open override func mouseDragged(with event: NSEvent) {
        guard _tracking, !_dragStarted else { return }
        let p = convert(event.locationInWindow, from: nil)
        if abs(p.x - _mouseDownPoint.x) > 4 || abs(p.y - _mouseDownPoint.y) > 4 {
            _dragStarted = true
            _tracking = false
            _ = NSColorPanel.dragColor(_color, with: event, from: self)
        }
    }
    @MainActor open override func mouseUp(with event: NSEvent) {
        guard _tracking else { return }
        _tracking = false
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        if let pull = _pulldownRect, pull.contains(p), let action = _pulldownAction {
            _ = NSApplication.shared.sendAction(action, to: _pulldownTarget, from: self)
            return
        }
        if _isActive { deactivate() } else { activate(true) }
    }
    @MainActor open override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { if _isActive { deactivate() } else { activate(true) }; return }
        super.keyDown(with: event)
    }

    @MainActor open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, _isActive { deactivate() }
    }

    // MARK: Dragging (ADR-0011)

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .generic }

    @MainActor open override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEnabled, sender.draggingPasteboard.availableType(from: [.color]) != nil else { return [] }
        _dropHighlight = true
        needsDisplay = true
        return .generic
    }
    @MainActor open override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        _dropHighlight = false
        needsDisplay = true
    }
    @MainActor open override func draggingEnded(_ sender: any NSDraggingInfo) {
        _dropHighlight = false
        needsDisplay = true
    }
    @MainActor open override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        _dropHighlight = false
        guard isEnabled, let c = NSColor(from: sender.draggingPasteboard) else { needsDisplay = true; return false }
        color = _supportsAlpha ? c : c.withAlphaComponent(1)
        _fireAction()
        return true
    }

    // MARK: Activation

    /// Makes this the well the colour panel edits (the only one when `exclusive`), with
    /// the well's colour, and shows the panel.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/activate(_:)
    @MainActor open func activate(_ exclusive: Bool) {
        if exclusive {
            for w in NSColorWell._activeWells.compactMap({ $0.well }) where w !== self { w.deactivate() }
        }
        _isActive = true
        NSColorWell._activeWells.removeAll { $0.well == nil || $0.well === self }
        NSColorWell._activeWells.append(_WeakWell(self))
        let panel = NSColorPanel.shared
        panel.showsAlpha = _supportsAlpha
        panel.setTarget(self)
        panel.setAction(NSColorWell.takeColorAction)
        panel.color = _color
        panel.orderFront(self)
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/color
    @MainActor open var color: NSColor {
        get { _color }
        set {
            _color = newValue
            needsDisplay = true
            if _isActive, NSColorPanel.sharedColorPanelExists, NSColorPanel.shared._target === self, !NSColorPanel.shared.color.isEqual(newValue) {
                NSColorPanel.shared.color = newValue
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/colorwellstyle
    @available(macOS 13.0, *)
    @MainActor open var colorWellStyle: NSColorWell.Style {
        get { _style }
        set { _style = newValue; invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/deactivate()
    @MainActor open func deactivate() {
        guard _isActive else { return }
        _isActive = false
        NSColorWell._activeWells.removeAll { $0.well == nil || $0.well === self }
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared._target === self {
            NSColorPanel.shared.setTarget(nil)
            NSColorPanel.shared.setAction(nil)
        }
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/image
    @available(macOS 13.0, *)
    @MainActor open var image: NSImage? {
        get { _image }
        set { _image = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/isactive
    @MainActor open var isActive: Bool { _isActive }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/isbordered
    @MainActor open var isBordered: Bool {
        get { _isBordered }
        set { _isBordered = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/maximumlinearexposure
    @available(macOS 26.0, *)
    @MainActor open var maximumLinearExposure: CGFloat {
        get { 1 }
        set { }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/pulldownaction
    @available(macOS 13.0, *)
    @MainActor open var pulldownAction: Selector? {
        get { _pulldownAction }
        set { _pulldownAction = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/pulldowntarget
    @available(macOS 13.0, *)
    @MainActor open var pulldownTarget: AnyObject? {
        get { _pulldownTarget }
        set { _pulldownTarget = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/supportsalpha
    @available(macOS 14.0, *)
    @MainActor open var supportsAlpha: Bool {
        get { _supportsAlpha }
        set { _supportsAlpha = newValue; if _isActive, NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.showsAlpha = newValue } }
    }
    /// Takes the sender's colour (the colour panel's, or another well's) and sends the action.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorwell/takecolorfrom(_:)
    @MainActor open func takeColorFrom(_ sender: Any?) {
        let c: NSColor?
        if let p = sender as? NSColorPanel { c = p.color } else if let w = sender as? NSColorWell { c = w.color } else { c = (sender as? NSColor) }
        guard let c else { return }
        _color = _supportsAlpha ? c : c.withAlphaComponent(1)
        needsDisplay = true
        _fireAction()
    }

    // MARK: Accessibility (ADR-0013): AXColorWell, the colour as its value, press opens the panel.
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .colorWell }
    open override func accessibilityValue() -> Any? {
        if _a11y.hasValue { return _a11y.value }
        return MainActor.assumeIsolated { String(format: "rgb %.3g %.3g %.3g %.3g", Double(_color.redComponent), Double(_color.greenComponent), Double(_color.blueComponent), Double(_color.alphaComponent)) }
    }
    open override func accessibilityLabel() -> String? { _a11y.label ?? toolTip }
    open override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated {
            guard isEnabled else { return false }
            if _isActive { deactivate() } else { activate(true) }
            return true
        }
    }
}
