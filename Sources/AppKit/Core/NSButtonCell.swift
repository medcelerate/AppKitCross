// NSButtonCell (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell
@MainActor open class NSButtonCell: NSActionCell {
    // MARK: Storage
    internal var _buttonType: NSButton.ButtonType = .momentaryPushIn
    private var _alternateTitle = ""
    private var _alternateImage: NSImage? = nil
    private var _bezelStyle: NSButton.BezelStyle = .rounded
    private var _isTransparent = false
    private var _highlightsBy: NSCell.StyleMask = [.pushInCellMask, .changeGrayCellMask]
    private var _showsStateBy: NSCell.StyleMask = []
    private var _imagePosition: NSControl.ImagePosition = .imageLeft
    private var _imageScaling: NSImageScaling = .scaleProportionallyDown
    private var _backgroundColor: NSColor? = nil
    private var _keyEquivalent = ""
    private var _keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    private var _imageDimsWhenDisabled = true
    private var _showsBorderOnlyWhileMouseInside = false
    private var _sound: NSSound? = nil
    private var _periodicDelay: Float = 0.4
    private var _periodicInterval: Float = 0.075

    /// True for checkbox and radio buttons: a state indicator with the title beside it.
    internal var _isSwitchLike: Bool { _buttonType == .switch || _buttonType == .radio }

    internal var _indicatorSize: CGFloat {
        switch _controlSize { case .mini: return 10; case .small: return 12; default: return 14 }
    }

    private func _drawIndicator(in rect: NSRect, flipped: Bool) {
        let on = _state == .on, mixed = _state == .mixed
        let enabled = _isEnabled
        if _buttonType == .radio {
            let circle = NSBezierPath(ovalIn: rect)
            ((on || mixed) && enabled ? NSColor.controlAccentColor : NSColor.controlBackgroundColor).setFill()
            circle.fill()
            (enabled ? NSColor.separatorColor.withAlphaComponent(0.5) : NSColor.separatorColor).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            if on {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.32, dy: rect.height * 0.32)).fill()
            }
        } else {
            let box = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            ((on || mixed) && enabled ? NSColor.controlAccentColor : NSColor.controlBackgroundColor).setFill()
            box.fill()
            (enabled ? NSColor.separatorColor.withAlphaComponent(0.5) : NSColor.separatorColor).setStroke()
            box.lineWidth = 1
            box.stroke()
            if on {
                let mark = NSBezierPath()
                let w = rect.width, h = rect.height
                let yUp: (CGFloat) -> CGFloat = { flipped ? rect.minY + h * (1 - $0) : rect.minY + h * $0 }
                mark.move(to: NSPoint(x: rect.minX + w * 0.25, y: yUp(0.5)))
                mark.line(to: NSPoint(x: rect.minX + w * 0.43, y: yUp(0.3)))
                mark.line(to: NSPoint(x: rect.minX + w * 0.77, y: yUp(0.72)))
                mark.lineWidth = 2
                mark.lineCapStyle = .round
                mark.lineJoinStyle = .round
                NSColor.white.setStroke()
                mark.stroke()
            } else if mixed {
                NSColor.white.setFill()
                NSBezierPath.fill(NSRect(x: rect.minX + rect.width * 0.25, y: rect.midY - 1, width: rect.width * 0.5, height: 2))
            }
        }
    }

    @MainActor open override var cellSize: NSSize {
        var s = stringValue.isEmpty ? NSSize(width: 0, height: _effectiveFont.ascender - _effectiveFont.descender) : stringValue.size(withAttributes: _textAttributes)
        if _isSwitchLike {
            s.width += _indicatorSize + 10
            s.height = max(s.height, _indicatorSize) + 4
        } else {
            s.width += 28
            s.height += 8
        }
        return s
    }
    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        if _isSwitchLike {
            let size = _indicatorSize
            let box = NSRect(x: cellFrame.minX + 2, y: cellFrame.midY - size / 2, width: size, height: size)
            _drawIndicator(in: box, flipped: controlView.isFlipped)
            let titleFrame = NSRect(x: box.maxX + 6, y: cellFrame.minY, width: max(0, cellFrame.maxX - box.maxX - 6), height: cellFrame.height)
            _drawText(stringValue, attributes: _textAttributes, in: titleFrame, alignment: .left, flipped: controlView.isFlipped)
            return
        }
        drawBezel(withFrame: cellFrame, in: controlView)
        drawInterior(withFrame: cellFrame, in: controlView)
    }
    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var frame = cellFrame
        if _isHighlighted && _highlightsBy.contains(.pushInCellMask) { frame = frame.offsetBy(dx: 0, dy: controlView.isFlipped ? 1 : -1) }
        _ = drawTitle(attributedTitle, withFrame: frame, in: controlView)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/init(coder:)
    public required init(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/init(imagecell:)
    @MainActor public override init(imageCell image: NSImage?) {
        super.init(imageCell: image)
        _isBordered = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _isBordered = true
        _alignment = .center
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/alternateimage
    @MainActor open var alternateImage: NSImage? {
        get { _alternateImage }
        set { _alternateImage = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/alternatetitle
    @MainActor open var alternateTitle: String {
        get { _alternateTitle }
        set { _alternateTitle = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/attributedalternatetitle
    @MainActor open var attributedAlternateTitle: NSAttributedString {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/attributedtitle
    @MainActor open var attributedTitle: NSAttributedString {
        get { attributedStringValue }
        set { attributedStringValue = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/backgroundcolor
    @MainActor open var backgroundColor: NSColor? {
        get { _backgroundColor }
        set { _backgroundColor = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/bezelstyle
    @MainActor open var bezelStyle: NSButton.BezelStyle {
        get { _bezelStyle }
        set { _bezelStyle = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/drawbezel(withframe:in:)
    /// AppKit draws the push button whose key equivalent is Return with the accent colour.
    private var _isDefaultButton: Bool {
        _isEnabled && _keyEquivalent == "\r" && (_bezelStyle == .rounded || _bezelStyle == .push || _bezelStyle == .automatic || _bezelStyle == .flexiblePush)
    }
    @MainActor open func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        guard _isBordered, !_isTransparent else { return }
        let r = frame.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        let pressed = _isHighlighted && _highlightsBy.contains(.pushInCellMask)
        let stateOn = _state != .off && _showsStateBy.contains(.changeBackgroundCellMask)
        var fill: NSColor = _backgroundColor ?? .controlColor
        if !_isEnabled { fill = NSColor.controlColor.withAlphaComponent(0.6) }
        else if pressed || stateOn || _isDefaultButton { fill = NSColor.controlAccentColor }
        else if _isHighlighted && _highlightsBy.contains(.changeBackgroundCellMask) { fill = NSColor.selectedControlColor }
        fill.setFill()
        path.fill()
        (_isEnabled ? NSColor.separatorColor.withAlphaComponent(0.6) : NSColor.separatorColor.withAlphaComponent(0.3)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/drawimage(_:withframe:in:)
    @MainActor open func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) { }   // NSImage drawing arrives with the image pipeline.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/drawtitle(_:withframe:in:)
    @MainActor open func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let pressed = (_isHighlighted && _highlightsBy.contains(.pushInCellMask)) || (_state != .off && _showsStateBy.contains(.changeBackgroundCellMask))
        var attrs = _textAttributes
        if (pressed || (_isDefaultButton && _isEnabled)) && _isBordered { attrs[.foregroundColor] = NSColor.white }
        let text = (_isHighlighted && _highlightsBy.contains(.contentsCellMask) && !_alternateTitle.isEmpty) ? _alternateTitle : title.string
        _drawText(text, attributes: attrs, in: frame, alignment: _alignment, flipped: controlView.isFlipped)
        let size = text.size(withAttributes: attrs)
        return NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/getperiodicdelay(_:interval:)
    @MainActor open override func getPeriodicDelay(_ delay: UnsafeMutablePointer<Float>, interval: UnsafeMutablePointer<Float>) { delay.pointee = _periodicDelay; interval.pointee = _periodicInterval }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/gradienttype
    @MainActor open var gradientType: NSButton.GradientType {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/highlightsby
    @MainActor open var highlightsBy: NSCell.StyleMask {
        get { _highlightsBy }
        set { _highlightsBy = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/imagedimswhendisabled
    @MainActor open var imageDimsWhenDisabled: Bool {
        get { _imageDimsWhenDisabled }
        set { _imageDimsWhenDisabled = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/imageposition
    @MainActor open var imagePosition: NSControl.ImagePosition {
        get { _imagePosition }
        set { _imagePosition = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/imagescaling
    @MainActor open var imageScaling: NSImageScaling {
        get { _imageScaling }
        set { _imageScaling = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/isopaque
    @MainActor open override var isOpaque: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/istransparent
    @MainActor open var isTransparent: Bool {
        get { _isTransparent }
        set { _isTransparent = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/keyequivalent
    @MainActor open override var keyEquivalent: String {
        get { _keyEquivalent }
        set { _keyEquivalent = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/keyequivalentfont
    @MainActor open var keyEquivalentFont: NSFont? {
        get { unimplemented() }
        set { unimplemented() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/keyequivalentmodifiermask
    @MainActor open var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        get { _keyEquivalentModifierMask }
        set { _keyEquivalentModifierMask = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/mouseentered(with:)
    @MainActor open func mouseEntered(with event: NSEvent) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/mouseexited(with:)
    @MainActor open func mouseExited(with event: NSEvent) { }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/performclick(_:)
    @MainActor open override func performClick(_ sender: Any?) { (_controlView as? NSButton)?.performClick(sender) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/setbuttontype(_:)
    @MainActor open func setButtonType(_ type: NSButton.ButtonType) {
        _buttonType = type
        switch type {
        case .momentaryLight: _highlightsBy = [.changeBackgroundCellMask]; _showsStateBy = []
        case .momentaryPushIn: _highlightsBy = [.pushInCellMask, .changeGrayCellMask]; _showsStateBy = []
        case .momentaryChange: _highlightsBy = [.contentsCellMask]; _showsStateBy = []
        case .pushOnPushOff: _highlightsBy = [.pushInCellMask, .changeGrayCellMask]; _showsStateBy = [.changeBackgroundCellMask]
        case .onOff: _highlightsBy = [.changeBackgroundCellMask]; _showsStateBy = [.changeBackgroundCellMask]
        case .toggle: _highlightsBy = [.pushInCellMask]; _showsStateBy = [.contentsCellMask]
        case .switch: _highlightsBy = [.contentsCellMask]; _showsStateBy = [.contentsCellMask]; _isBordered = false; _alignment = .natural
        case .radio: _highlightsBy = [.contentsCellMask]; _showsStateBy = [.contentsCellMask]; _isBordered = false; _alignment = .natural
        case .accelerator, .multiLevelAccelerator: _highlightsBy = [.pushInCellMask]; _showsStateBy = []
        default: break
        }
        _changed()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/setkeyequivalentfont(_:size:)
    @MainActor open func setKeyEquivalentFont(_ fontName: String, size fontSize: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/setperiodicdelay(_:interval:)
    @MainActor open func setPeriodicDelay(_ delay: Float, interval: Float) { _periodicDelay = delay; _periodicInterval = interval }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/showsborderonlywhilemouseinside
    @MainActor open var showsBorderOnlyWhileMouseInside: Bool {
        get { _showsBorderOnlyWhileMouseInside }
        set { _showsBorderOnlyWhileMouseInside = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/showsstateby
    @MainActor open var showsStateBy: NSCell.StyleMask {
        get { _showsStateBy }
        set { _showsStateBy = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/sound
    @MainActor open var sound: NSSound? {
        get { _sound }
        set { _sound = newValue }
    }
    // SKIPPED (override type String! differs from superclass String): @MainActor var title: String! { get set }
}
