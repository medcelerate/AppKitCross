// NSBox (hand-written; seeded from the generated stub, see tools/apigen)
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// A titled, bordered box around a content view. The primary and secondary types draw
// the rounded group box of macOS (a faint fill and a hairline border), `custom` draws
// `fillColor`, `borderColor`, `borderWidth` and `cornerRadius` with the `borderType`,
// `separator` is a one-point line and `oldStyle` a bevelled frame. The title sits at
// one of the six positions (or none), and the content view is inset by the border and
// `contentViewMargins` (`contentView` autoresizes with the box).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox
@MainActor open class NSBox: NSView {
    private var _boxType: NSBox.BoxType = .primary
    private var _borderType: NSBorderType = .lineBorder
    private var _titlePosition: NSBox.TitlePosition = .atTop
    private var _title = "Title"
    private var _titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private var _titleCell: NSTextFieldCell
    private var _contentView: NSView?
    private var _contentViewMargins = NSSize(width: 5, height: 5)
    private var _borderColor: NSColor = .separatorColor
    private var _fillColor: NSColor = .clear
    private var _borderWidth: CGFloat = 1
    private var _cornerRadius: CGFloat = 5
    private var _isTransparent = false
    private var _laying = false

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsview/init(frame:)
    @MainActor public override init(frame frameRect: NSRect) {
        _titleCell = NSTextFieldCell(textCell: "Title")
        super.init(frame: frameRect)
        _titleCell.font = _titleFont
        _titleCell.alignment = .center
        _titleCell.isBordered = false
        _titleCell.isBezeled = false
        _titleCell.drawsBackground = false
        let content = NSView(frame: .zero)
        _contentView = content
        addSubview(content)
        _layoutContent()
    }
    public required init?(coder: NSCoder) { unimplemented() }

    @MainActor open override var isFlipped: Bool { true }

    // MARK: Type, border and title

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/boxtype
    @MainActor open var boxType: NSBox.BoxType {
        get { _boxType }
        set { _boxType = newValue; _layoutContent(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/bordertype
    @MainActor open var borderType: NSBorderType {
        get { _borderType }
        set { _borderType = newValue; _layoutContent(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/title
    @MainActor open var title: String {
        get { _title }
        set { _title = newValue; _titleCell.stringValue = newValue; _layoutContent(); needsDisplay = true; _accessibilityNameChanged() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/titlefont
    @MainActor open var titleFont: NSFont {
        get { _titleFont }
        set { _titleFont = newValue; _titleCell.font = newValue; _layoutContent(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/titleposition
    @MainActor open var titlePosition: NSBox.TitlePosition {
        get { _titlePosition }
        set { _titlePosition = newValue; _layoutContent(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/titlecell
    @MainActor open var titleCell: Any { _titleCell }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/istransparent
    @MainActor open var isTransparent: Bool {
        get { _isTransparent }
        set { _isTransparent = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/bordercolor
    @MainActor open var borderColor: NSColor {
        get { _borderColor }
        set { _borderColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/fillcolor
    @MainActor open var fillColor: NSColor {
        get { _fillColor }
        set { _fillColor = newValue; needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/borderwidth
    @MainActor open var borderWidth: CGFloat {
        get { _borderWidth }
        set { _borderWidth = max(0, newValue); _layoutContent(); needsDisplay = true }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/cornerradius
    @MainActor open var cornerRadius: CGFloat {
        get { _cornerRadius }
        set { _cornerRadius = max(0, newValue); needsDisplay = true }
    }

    // MARK: Content

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/contentview
    @MainActor open var contentView: NSView? {
        get { _contentView }
        set {
            guard newValue !== _contentView else { return }
            _contentView?.removeFromSuperview()
            _contentView = newValue
            if let v = newValue { addSubview(v) }
            _layoutContent()
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/contentviewmargins
    @MainActor open var contentViewMargins: NSSize {
        get { _contentViewMargins }
        set { _contentViewMargins = newValue; _layoutContent(); needsDisplay = true }
    }

    // MARK: Geometry

    /// The height the title band takes (the title's line height plus a little air).
    private var _titleHeight: CGFloat {
        guard _titlePosition != .noTitle, _boxType != .separator else { return 0 }
        return (_titleFont.ascender - _titleFont.descender + 2).rounded(.up)
    }
    private var _titleSize: NSSize {
        guard _titlePosition != .noTitle else { return .zero }
        let s = (_title as NSString).size(withAttributes: [.font: _titleFont])
        return NSSize(width: s.width.rounded(.up) + 8, height: _titleHeight)
    }
    /// The thickness of the border line.
    private var _borderThickness: CGFloat {
        switch _boxType {
        case .separator: return 1
        case .custom: return _borderType == .noBorder ? 0 : _borderWidth
        default: return _borderType == .noBorder ? 0 : 1
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/borderrect
    ///
    /// The frame of the border, in the box's coordinates: the bounds less the title
    /// band, which sits outside the border for the "above" and "below" positions and
    /// straddles it for "at top" and "at bottom".
    @MainActor open var borderRect: NSRect {
        var r = bounds
        if _boxType == .separator {
            // A separator is a line across the long axis, centred.
            if r.width >= r.height { return NSRect(x: r.minX, y: r.midY.rounded(.down), width: r.width, height: 1) }
            return NSRect(x: r.midX.rounded(.down), y: r.minY, width: 1, height: r.height)
        }
        let th = _titleHeight
        switch _titlePosition {
        case .aboveTop: r.origin.y += th; r.size.height -= th
        case .atTop: r.origin.y += th / 2; r.size.height -= th / 2
        case .belowBottom: r.size.height -= th
        case .atBottom: r.size.height -= th / 2
        default: break
        }
        return NSRect(x: r.minX, y: r.minY, width: max(0, r.width), height: max(0, r.height))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/titlerect
    @MainActor open var titleRect: NSRect {
        guard _titlePosition != .noTitle, _boxType != .separator else { return .zero }
        let s = _titleSize
        let b = borderRect
        let x: CGFloat = userInterfaceLayoutDirection == .rightToLeft ? b.maxX - 10 - s.width : b.minX + 10
        switch _titlePosition {
        case .aboveTop: return NSRect(x: x, y: 0, width: s.width, height: s.height)
        case .atTop: return NSRect(x: x, y: b.minY - s.height / 2, width: s.width, height: s.height)
        case .belowTop: return NSRect(x: x, y: b.minY + _borderThickness + 2, width: s.width, height: s.height)
        case .aboveBottom: return NSRect(x: x, y: b.maxY - _borderThickness - 2 - s.height, width: s.width, height: s.height)
        case .atBottom: return NSRect(x: x, y: b.maxY - s.height / 2, width: s.width, height: s.height)
        case .belowBottom: return NSRect(x: x, y: bounds.maxY - s.height, width: s.width, height: s.height)
        case .noTitle: return .zero
        }
    }
    /// The content view's frame: the border rect inset by the border and the margins,
    /// less the title band for titles drawn inside the border.
    private var _contentFrame: NSRect {
        guard _boxType != .separator else { return .zero }
        var r = borderRect.insetBy(dx: _borderThickness, dy: _borderThickness)
        let th = _titleHeight
        switch _titlePosition {
        case .atTop: r.origin.y += th / 2; r.size.height -= th / 2
        case .belowTop: r.origin.y += th + 2; r.size.height -= th + 2
        case .atBottom: r.size.height -= th / 2
        case .aboveBottom: r.size.height -= th + 2
        default: break
        }
        r = r.insetBy(dx: _contentViewMargins.width, dy: _contentViewMargins.height)
        return NSRect(x: r.minX, y: r.minY, width: max(0, r.width), height: max(0, r.height))
    }
    private func _layoutContent() {
        guard !_laying, let c = _contentView else { return }
        _laying = true
        let f = _contentFrame
        if c.frame != f { c.frame = f }
        c.autoresizingMask = [.width, .height]
        _laying = false
    }
    @MainActor open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _layoutContent()
        needsDisplay = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/setframefromcontentframe(_:)
    @MainActor open func setFrameFromContentFrame(_ contentFrame: NSRect) {
        let inset = _contentFrame
        let dx = bounds.width - inset.width, dy = bounds.height - inset.height
        frame = NSRect(x: contentFrame.minX - inset.minX, y: contentFrame.minY - (frame.height - inset.maxY), width: contentFrame.width + dx, height: contentFrame.height + dy)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbox/sizetofit()
    ///
    /// Fits the box around its content view's subviews (or its fitting size).
    @MainActor open func sizeToFit() {
        guard let c = _contentView else { return }
        var content = NSRect.zero
        for s in c.subviews { content = content.isEmpty ? s.frame : content.union(s.frame) }
        if content.isEmpty { content = NSRect(origin: .zero, size: c.fittingSize) }
        let inset = _contentFrame
        let dx = bounds.width - inset.width, dy = bounds.height - inset.height
        setFrameSize(NSSize(width: content.maxX + dx, height: content.maxY + dy))
    }
    @MainActor open override var intrinsicContentSize: NSSize {
        guard let c = _contentView else { return super.intrinsicContentSize }
        let s = c.fittingSize
        guard s.width > 0 || s.height > 0 else { return super.intrinsicContentSize }
        let inset = _contentFrame
        return NSSize(width: s.width + bounds.width - inset.width, height: s.height + bounds.height - inset.height)
    }

    // MARK: Drawing

    @MainActor open override func draw(_ dirtyRect: NSRect) {
        guard !_isTransparent else { return }
        let b = borderRect
        // A title that straddles the border leaves a gap in it: the border is drawn
        // through a clip that excludes the title's rect, as AppKit does.
        let straddles = _titlePosition == .atTop || _titlePosition == .atBottom
        if straddles {
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: bounds)
            clip.appendRect(titleRect)
            clip.windingRule = .evenOdd
            clip.addClip()
        }
        defer {
            if straddles { NSGraphicsContext.restoreGraphicsState() }
            if _titlePosition != .noTitle && _boxType != .separator {
                _titleCell.textColor = .labelColor
                _titleCell.draw(withFrame: titleRect, in: self)
            }
        }
        switch _boxType {
        case .separator:
            NSColor.separatorColor.setFill()
            NSBezierPath(rect: b).fill()
            return
        case .custom:
            let path = _borderType == .noBorder || _cornerRadius == 0 ? NSBezierPath(rect: b) : NSBezierPath(roundedRect: b, xRadius: _cornerRadius, yRadius: _cornerRadius)
            _fillColor.setFill()
            path.fill()
            if _borderType != .noBorder && _borderWidth > 0 {
                let inner = b.insetBy(dx: _borderWidth / 2, dy: _borderWidth / 2)
                let stroke = _cornerRadius == 0 ? NSBezierPath(rect: inner) : NSBezierPath(roundedRect: inner, xRadius: max(0, _cornerRadius - _borderWidth / 2), yRadius: max(0, _cornerRadius - _borderWidth / 2))
                stroke.lineWidth = _borderWidth
                _borderColor.setStroke()
                stroke.stroke()
                if _borderType == .grooveBorder || _borderType == .bezelBorder {
                    NSColor.white.withAlphaComponent(0.5).setStroke()
                    let groove = NSBezierPath(rect: b.insetBy(dx: _borderWidth + 0.5, dy: _borderWidth + 0.5))
                    groove.stroke()
                }
            }
        case .primary, .secondary:
            // The macOS group box: a faint fill and a hairline, rounded.
            let path = NSBezierPath(roundedRect: b, xRadius: 5, yRadius: 5)
            NSColor.quaternaryLabelColor.withAlphaComponent(0.05).setFill()
            path.fill()
            if _borderType != .noBorder {
                NSColor.separatorColor.setStroke()
                let stroke = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
                stroke.lineWidth = 1
                stroke.stroke()
            }
        default:
            // The old style: a bevelled frame, light on the top-left and dark on the bottom-right.
            NSColor.controlColor.setFill()
            NSBezierPath(rect: b).fill()
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: b.minX, y: b.minY, width: b.width, height: 1)).fill()
            NSBezierPath(rect: NSRect(x: b.minX, y: b.minY, width: 1, height: b.height)).fill()
            NSColor.darkGray.setFill()
            NSBezierPath(rect: NSRect(x: b.minX, y: b.maxY - 1, width: b.width, height: 1)).fill()
            NSBezierPath(rect: NSRect(x: b.maxX - 1, y: b.minY, width: 1, height: b.height)).fill()
        }
    }

    // MARK: Accessibility (ADR-0013)
    // AXGroup titled by the box title; the content view's subviews are the children.
    open override func isAccessibilityElement() -> Bool { _a11y.isElement ?? true }
    open override func accessibilityRole() -> NSAccessibility.Role? { _a11y.role ?? .group }
    open override func accessibilityTitle() -> String? { _a11y.title ?? (_titlePosition == .noTitle || _title.isEmpty ? nil : _title) }
    open override func accessibilityLabel() -> String? { _a11y.label ?? (_titlePosition == .noTitle || _title.isEmpty ? nil : _title) }
    override func _accessibilityIsFocusable() -> Bool { false }
}
