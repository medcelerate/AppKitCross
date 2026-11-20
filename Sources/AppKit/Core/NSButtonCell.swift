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
    private var _attributedAlternateTitle: NSAttributedString? = nil
    private var _gradientType: NSButton.GradientType = .none
    private var _keyEquivalentFont: NSFont? = nil
    /// NSButton's image tint (`contentTintColor`), compression and image-hugging settings.
    internal var _contentTintColor: NSColor? = nil
    internal var _imageHugsTitle = false
    internal var _hidesText = false, _hidesImage = false
    /// NSButton's `hasDestructiveAction`: a red title, never the accent bezel.
    internal var _hasDestructiveAction = false

    @MainActor internal override func _copyCellState(from other: NSCell) {
        super._copyCellState(from: other)
        guard let o = other as? NSButtonCell else { return }
        _buttonType = o._buttonType; _alternateTitle = o._alternateTitle; _alternateImage = o._alternateImage
        _bezelStyle = o._bezelStyle; _isTransparent = o._isTransparent; _highlightsBy = o._highlightsBy; _showsStateBy = o._showsStateBy
        _imagePosition = o._imagePosition; _imageScaling = o._imageScaling; _backgroundColor = o._backgroundColor
        _keyEquivalent = o._keyEquivalent; _keyEquivalentModifierMask = o._keyEquivalentModifierMask
        _imageDimsWhenDisabled = o._imageDimsWhenDisabled; _showsBorderOnlyWhileMouseInside = o._showsBorderOnlyWhileMouseInside
        _sound = o._sound; _periodicDelay = o._periodicDelay; _periodicInterval = o._periodicInterval
        _attributedAlternateTitle = o._attributedAlternateTitle; _gradientType = o._gradientType; _keyEquivalentFont = o._keyEquivalentFont
        _contentTintColor = o._contentTintColor; _imageHugsTitle = o._imageHugsTitle; _hidesText = o._hidesText; _hidesImage = o._hidesImage
        _hasDestructiveAction = o._hasDestructiveAction
    }

    /// The accent colour for an "on" state or a default bezel: grey in an inactive window
    /// under the macOS control look (ADR-0051), the accent otherwise.
    internal var _stateAccentColor: NSColor {
        _NSControlStyle.isActive(_controlView) ? NSColor.controlAccentColor : _NSControlStyle.inactiveAccent
    }

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
            ((on || mixed) && enabled ? _stateAccentColor : NSColor.controlBackgroundColor).setFill()
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
            ((on || mixed) && enabled ? _stateAccentColor : NSColor.controlBackgroundColor).setFill()
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

    // MARK: Image and title layout

    /// The image shown now: the alternate image while the state or highlight shows contents.
    internal var _displayedImage: NSImage? {
        let showsAlternate = (_state != .off && _showsStateBy.contains(.contentsCellMask)) || (_isHighlighted && _highlightsBy.contains(.contentsCellMask))
        if showsAlternate, let alt = _alternateImage { return alt }
        return _image
    }
    /// The position the cell lays out with: no image without one, image only without a
    /// title, and the button's compression (hide text needs an image left, hide images a title).
    internal func _layoutPosition(hidesText: Bool, hidesImage: Bool) -> NSControl.ImagePosition {
        let hasImage = _displayedImage != nil, hasTitle = !stringValue.isEmpty
        if !hasImage || _imagePosition == .noImage { return .noImage }
        if hidesImage && hasTitle { return .noImage }
        if !hasTitle || _imagePosition == .imageOnly { return .imageOnly }
        if hidesText { return .imageOnly }
        return _imagePosition
    }
    internal var _effectiveImagePosition: NSControl.ImagePosition { _layoutPosition(hidesText: _hidesText, hidesImage: _hidesImage) }
    private static let _imageTitleGap: CGFloat = 4
    private var _titleSize: NSSize {
        stringValue.isEmpty ? NSSize(width: 0, height: _effectiveFont.ascender - _effectiveFont.descender) : stringValue.size(withAttributes: _textAttributes)
    }
    /// The content (image and title) size for a layout position.
    internal func _contentSize(for position: NSControl.ImagePosition) -> NSSize {
        let t = _titleSize, i = _displayedImage?.size ?? .zero, g = NSButtonCell._imageTitleGap
        switch position {
        case .noImage: return t
        case .imageOnly: return i
        case .imageOverlaps: return NSSize(width: max(t.width, i.width), height: max(t.height, i.height))
        case .imageAbove, .imageBelow: return NSSize(width: max(t.width, i.width), height: t.height + g + i.height)
        default: return NSSize(width: t.width + g + i.width, height: max(t.height, i.height))
        }
    }
    /// The cell size with a layout position (NSButton's compressed sizes ask for others).
    internal func _cellSize(for position: NSControl.ImagePosition) -> NSSize {
        var s = _contentSize(for: position)
        if _isSwitchLike {
            s = _titleSize
            s.width += _indicatorSize + 10
            s.height = max(s.height, _indicatorSize) + 4
        } else if position == .imageOnly {
            s.width += _isBordered ? 16 : 0
            s.height += _isBordered ? 8 : 0
        } else {
            s.width += 28
            s.height += 8
        }
        return s
    }
    @MainActor open override var cellSize: NSSize { _cellSize(for: _effectiveImagePosition) }
    /// The image and title rects inside `frame` for the current position (AppKit centres the
    /// pair; `imageHugsTitle` keeps them together for leading/trailing positions too).
    internal func _imageAndTitleRects(in frame: NSRect, flipped: Bool) -> (image: NSRect, title: NSRect) {
        let position = _effectiveImagePosition
        let t = _titleSize, g = NSButtonCell._imageTitleGap
        var i = _displayedImage?.size ?? .zero
        // Scale the image down (or to fit) into the frame as imageScaling asks.
        let avail = frame.insetBy(dx: 2, dy: 2).size
        switch _imageScaling {
        case .scaleAxesIndependently: if position == .imageOnly { i = avail }
        case .scaleProportionallyUpOrDown:
            if position == .imageOnly, i.width > 0, i.height > 0 { let k = min(avail.width / i.width, avail.height / i.height); i = NSSize(width: i.width * k, height: i.height * k) }
        case .scaleNone: break
        default:
            if i.width > avail.width || i.height > avail.height, i.width > 0, i.height > 0 {
                let k = min(avail.width / i.width, avail.height / i.height); i = NSSize(width: i.width * k, height: i.height * k)
            }
        }
        let leading = NSApp?.userInterfaceLayoutDirection == .rightToLeft ? NSControl.ImagePosition.imageRight : .imageLeft
        var pos = position
        if pos == .imageLeading { pos = leading } else if pos == .imageTrailing { pos = leading == .imageLeft ? .imageRight : .imageLeft }
        func centered(_ size: NSSize, x: CGFloat? = nil, y: CGFloat? = nil) -> NSRect {
            NSRect(x: (x ?? frame.midX - size.width / 2).rounded(), y: (y ?? frame.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        }
        switch pos {
        case .noImage: return (.zero, centered(t))
        case .imageOnly: return (centered(i), .zero)
        case .imageOverlaps: return (centered(i), centered(t))
        case .imageAbove, .imageBelow:
            let total = i.height + g + t.height
            let top = frame.midY - total / 2
            // "Above" is towards the top of the screen: the smaller y in a flipped view.
            let imageFirst = (pos == .imageAbove) == flipped
            let iy = imageFirst ? top : top + t.height + g
            let ty = imageFirst ? top + i.height + g : top
            return (centered(i, y: iy), centered(t, y: ty))
        default:
            let total = i.width + g + t.width
            let left = frame.midX - total / 2
            let imageLeft = pos == .imageLeft
            let ix = imageLeft ? left : left + t.width + g
            let tx = imageLeft ? left + i.width + g : left
            return (centered(i, x: ix), centered(t, x: tx))
        }
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
        let position = _effectiveImagePosition
        let rects = _imageAndTitleRects(in: frame, flipped: controlView.isFlipped)
        if position != .noImage, let image = _displayedImage { drawImage(image, withFrame: rects.image, in: controlView) }
        if position != .imageOnly {
            let titleFrame = position == .noImage || position == .imageOverlaps ? frame : NSRect(x: rects.title.minX, y: frame.minY, width: rects.title.width + 1, height: frame.height)
            _ = drawTitle(attributedTitle, withFrame: titleFrame, in: controlView)
        }
    }
    /// The colour a template image takes: `contentTintColor`, else the title's colour
    /// (white on an accent bezel), dimmed when disabled.
    private var _templateColor: NSColor {
        let pressed = (_isHighlighted && _highlightsBy.contains(.pushInCellMask)) || (_state != .off && _showsStateBy.contains(.changeBackgroundCellMask))
        var c: NSColor = _contentTintColor ?? (((pressed || _isAccentBezel) && _isBordered) ? .white : .controlTextColor)
        if !_isEnabled && _imageDimsWhenDisabled { c = NSColor.disabledControlTextColor }
        return c
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
    /// The alternate title with the cell's font, control text colour and a centred,
    /// tail-truncating paragraph style (macOS 15), or as set; empty without an alternate title.
    @MainActor open var attributedAlternateTitle: NSAttributedString {
        get {
            if let a = _attributedAlternateTitle, a.string == _alternateTitle { return a }
            guard !_alternateTitle.isEmpty else { return NSAttributedString(string: "") }
            let ps = NSMutableParagraphStyle()
            ps.alignment = _alignment
            ps.lineBreakMode = .byTruncatingTail
            return NSAttributedString(string: _alternateTitle, attributes: [.font: _effectiveFont, .foregroundColor: NSColor.controlTextColor, .paragraphStyle: ps])
        }
        set { _attributedAlternateTitle = newValue; _alternateTitle = newValue.string; _changed() }
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
    /// The default button draws the accent bezel, unless it is destructive (macOS keeps a
    /// destructive default plain, its title red) or, under the macOS control look, its
    /// window is not key (the accent greys out with the window).
    private var _isAccentBezel: Bool { _isDefaultButton && !_hasDestructiveAction }
    @MainActor open func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        guard _isBordered, !_isTransparent else { return }
        if _NSControlStyle.macControls { return _drawMacBezel(withFrame: frame, in: controlView) }
        let r = frame.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        let pressed = _isHighlighted && _highlightsBy.contains(.pushInCellMask)
        let stateOn = _state != .off && _showsStateBy.contains(.changeBackgroundCellMask)
        var fill: NSColor = _backgroundColor ?? .controlColor
        if !_isEnabled { fill = NSColor.controlColor.withAlphaComponent(0.6) }
        else if pressed || stateOn || _isAccentBezel { fill = NSColor.controlAccentColor }
        else if _isHighlighted && _highlightsBy.contains(.changeBackgroundCellMask) { fill = NSColor.selectedControlColor }
        fill.setFill()
        path.fill()
        (_isEnabled ? NSColor.separatorColor.withAlphaComponent(0.6) : NSColor.separatorColor.withAlphaComponent(0.3)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    /// The macOS push button (ADR-0051): a bezel shaded from white at the top to a light
    /// grey at the bottom (dark: a grey a shade lighter at the top), a hairline, and a
    /// one-point shadow under it. Pressed and "on" bezels are a darker shading; the
    /// default button is the accent, shaded the same way, grey in an inactive window.
    @MainActor private func _drawMacBezel(withFrame frame: NSRect, in controlView: NSView) {
        let flipped = controlView.isFlipped
        let radius: CGFloat = 6
        // The shadow: the bezel's shape one point towards the bottom of the screen.
        let shadowRect = frame.insetBy(dx: 0.5, dy: 0.5).offsetBy(dx: 0, dy: flipped ? 1 : -1)
        let dark = NSAppearance.currentIsDark
        NSColor(white: 0, alpha: dark ? 0.25 : 0.1).setFill()
        NSBezierPath(roundedRect: shadowRect, xRadius: radius, yRadius: radius).fill()
        let r = frame.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        let pressed = _isHighlighted && _highlightsBy.contains(.pushInCellMask)
        let stateOn = _state != .off && _showsStateBy.contains(.changeBackgroundCellMask)
        let top: NSColor, bottom: NSColor
        if !_isEnabled {
            top = dark ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.98, alpha: 1)
            bottom = dark ? NSColor(white: 0.3, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        } else if pressed || stateOn || _isAccentBezel {
            let accent = _isAccentBezel && !pressed && !stateOn ? _stateAccentColor : NSColor.controlAccentColor
            let base = accent.usingColorSpace(.deviceRGB) ?? accent
            let k: CGFloat = pressed && (stateOn || _isAccentBezel) ? 0.8 : 1
            top = NSColor(srgbRed: min(1, base.redComponent * k + 0.08), green: min(1, base.greenComponent * k + 0.08), blue: min(1, base.blueComponent * k + 0.08), alpha: 1)
            bottom = NSColor(srgbRed: base.redComponent * k, green: base.greenComponent * k, blue: base.blueComponent * k, alpha: 1)
            if !(stateOn || _isAccentBezel) {
                // A plain button pressed: a darker grey, not the accent (macOS 11+).
                let g = NSGradient(starting: dark ? NSColor(white: 0.5, alpha: 1) : NSColor(white: 0.86, alpha: 1), ending: dark ? NSColor(white: 0.44, alpha: 1) : NSColor(white: 0.8, alpha: 1))
                g?.draw(in: path, angle: flipped ? 90 : -90)
                _strokeMacBezelHairline(path, dark: dark)
                return
            }
        } else if _backgroundColor != nil {
            top = _backgroundColor!; bottom = _backgroundColor!
        } else {
            top = dark ? NSColor(white: 0.42, alpha: 1) : NSColor.white
            bottom = dark ? NSColor(white: 0.36, alpha: 1) : NSColor(white: 0.94, alpha: 1)
        }
        // Angle: the start colour at the top of the screen (a flipped view's minY).
        NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: flipped ? 90 : -90)
        _strokeMacBezelHairline(path, dark: dark)
    }
    private func _strokeMacBezelHairline(_ path: NSBezierPath, dark: Bool) {
        (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: _isEnabled ? 0.16 : 0.08)).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
    /// Whether the mac bezel's title is white (over an accent or pressed fill).
    private var _titleOnAccent: Bool {
        let pressed = (_isHighlighted && _highlightsBy.contains(.pushInCellMask)) || (_state != .off && _showsStateBy.contains(.changeBackgroundCellMask))
        if _NSControlStyle.macControls, pressed, !(_state != .off && _showsStateBy.contains(.changeBackgroundCellMask)), !_isAccentBezel { return false }
        return (pressed || (_isAccentBezel && _isEnabled)) && _isBordered
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/drawimage(_:withframe:in:)
    /// Draws the image into `frame`; a template image is tinted (`_templateColor`), and a
    /// disabled cell dims a colour image when `imageDimsWhenDisabled`.
    @MainActor open func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        guard frame.width > 0, frame.height > 0 else { return }
        if image.isTemplate, let tinted = image._tintedForTemplate(_templateColor, size: frame.size) {
            tinted.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: (!_isEnabled && _imageDimsWhenDisabled) ? 0.5 : 1, respectFlipped: true, hints: nil)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/drawtitle(_:withframe:in:)
    @MainActor open func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        var attrs = _textAttributes
        if _titleOnAccent { attrs[.foregroundColor] = NSColor.white }
        else if _hasDestructiveAction, _isEnabled { attrs[.foregroundColor] = NSColor.systemRed }
        let text = (_isHighlighted && _highlightsBy.contains(.contentsCellMask) && !_alternateTitle.isEmpty) ? _alternateTitle : title.string
        _drawText(text, attributes: attrs, in: frame, alignment: _alignment, flipped: controlView.isFlipped)
        let size = text.size(withAttributes: attrs)
        return NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/getperiodicdelay(_:interval:)
    @MainActor open override func getPeriodicDelay(_ delay: UnsafeMutablePointer<Float>, interval: UnsafeMutablePointer<Float>) { delay.pointee = _periodicDelay; interval.pointee = _periodicInterval }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbuttoncell/gradienttype
    /// Stored; unused, as on macOS since 10.12 (setting it has no effect on drawing).
    @MainActor open var gradientType: NSButton.GradientType {
        get { _gradientType }
        set { _gradientType = newValue }
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
    /// The font a key equivalent would be drawn in: the cell's font unless set (macOS 15
    /// answers the 13-point system font). Buttons do not draw their key equivalents.
    @MainActor open var keyEquivalentFont: NSFont? {
        get { _keyEquivalentFont ?? _effectiveFont }
        set { _keyEquivalentFont = newValue }
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
    @MainActor open func setKeyEquivalentFont(_ fontName: String, size fontSize: CGFloat) {
        if let f = NSFont(name: fontName, size: fontSize) { _keyEquivalentFont = f }
    }
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
