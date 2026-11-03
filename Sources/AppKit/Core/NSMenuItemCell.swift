// NSMenuItemCell (hand-written; seeded from the generated stub, see tools/apigen)
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
/// A cell that draws one menu item. Open menus draw their rows directly (see
/// NSMenuPopUp.swift); this cell exists for NSPopUpButtonCell and for code that lays out
/// items itself.
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell
@MainActor open class NSMenuItemCell: NSButtonCell {
    // MARK: Storage
    private var _menuItem: NSMenuItem?
    private var _needsSizing = true
    private var _needsDisplay = true

    private var _itemFont: NSFont { _font ?? NSFont.menuFont(ofSize: NSFont.systemFontSize) }
    private var _itemAttributes: [NSAttributedString.Key: Any] { [.font: _itemFont, .foregroundColor: _textColor] }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/init(coder:)
    public required init(coder: NSCoder) { super.init(coder: coder) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _isBordered = false
    }
    @MainActor public override init(imageCell image: NSImage?) {
        super.init(imageCell: image)
        _isBordered = false
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/calcsize()
    @MainActor open func calcSize() { _needsSizing = false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/drawborderandbackground(withframe:in:)
    @MainActor open func drawBorderAndBackground(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard _isHighlighted, _menuItem?.isEnabled ?? true else { return }
        NSColor.selectedMenuItemColor.setFill()
        NSBezierPath(roundedRect: cellFrame.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/drawimage(withframe:in:)
    @MainActor open func drawImage(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let image = _menuItem?.image else { return }
        let r = NSRect(x: cellFrame.minX + stateImageWidth, y: cellFrame.midY - _NSMenuLayout.imageSize / 2, width: _NSMenuLayout.imageSize, height: _NSMenuLayout.imageSize)
        image.draw(in: r)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/drawkeyequivalent(withframe:in:)
    @MainActor open func drawKeyEquivalent(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let label = _menuItem?._keyEquivalentLabel, !label.isEmpty else { return }
        _drawText(label, attributes: _itemAttributes, in: keyEquivalentRect(forBounds: cellFrame), alignment: .right, flipped: controlView.isFlipped)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/drawseparatoritem(withframe:in:)
    @MainActor open func drawSeparatorItem(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor.separatorColor.setFill()
        NSBezierPath.fill(NSRect(x: cellFrame.minX + 10, y: cellFrame.midY.rounded() - 0.5, width: cellFrame.width - 20, height: 1))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/drawstateimage(withframe:in:)
    @MainActor open func drawStateImage(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let item = _menuItem, item.state != .off else { return }
        let r = stateImageRect(forBounds: cellFrame)
        let mark = NSBezierPath()
        if item.state == .mixed {
            mark.move(to: NSPoint(x: r.minX + 1, y: r.midY)); mark.line(to: NSPoint(x: r.maxX - 1, y: r.midY))
        } else {
            mark.move(to: NSPoint(x: r.minX, y: r.midY))
            mark.line(to: NSPoint(x: r.minX + r.width * 0.38, y: controlView.isFlipped ? r.maxY - 1 : r.minY + 1))
            mark.line(to: NSPoint(x: r.maxX, y: controlView.isFlipped ? r.minY + 1 : r.maxY - 1))
        }
        mark.lineWidth = 1.8
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        _textColor.setStroke()
        mark.stroke()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/drawtitle(withframe:in:)
    @MainActor open func drawTitle(withFrame cellFrame: NSRect, in controlView: NSView) {
        _drawText(_menuItem?.title ?? stringValue, attributes: _itemAttributes, in: titleRect(forBounds: cellFrame), alignment: .left, flipped: controlView.isFlipped)
    }
    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        if _menuItem?.isSeparatorItem == true { drawSeparatorItem(withFrame: cellFrame, in: controlView); return }
        drawBorderAndBackground(withFrame: cellFrame, in: controlView)
        drawStateImage(withFrame: cellFrame, in: controlView)
        drawImage(withFrame: cellFrame, in: controlView)
        drawTitle(withFrame: cellFrame, in: controlView)
        drawKeyEquivalent(withFrame: cellFrame, in: controlView)
    }
    @MainActor open override var cellSize: NSSize {
        if _menuItem?.isSeparatorItem == true { return NSSize(width: stateImageWidth + _NSMenuLayout.trailingPadding, height: _NSMenuLayout.separatorHeight) }
        let key = keyEquivalentWidth
        let w = stateImageWidth + imageWidth + titleWidth + (key > 0 ? _NSMenuLayout.keyEquivalentGap + key : 0) + _NSMenuLayout.trailingPadding
        return NSSize(width: w, height: _NSMenuLayout.itemHeight)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/imagewidth
    @MainActor open var imageWidth: CGFloat { _menuItem?.image == nil ? 0 : _NSMenuLayout.imageSize + 6 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/keyequivalentrect(forbounds:)
    @MainActor open func keyEquivalentRect(forBounds cellFrame: NSRect) -> NSRect {
        let w = keyEquivalentWidth
        return NSRect(x: cellFrame.maxX - _NSMenuLayout.trailingPadding - w, y: cellFrame.minY, width: w, height: cellFrame.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/keyequivalentwidth
    @MainActor open var keyEquivalentWidth: CGFloat {
        guard let label = _menuItem?._keyEquivalentLabel, !label.isEmpty else { return 0 }
        return label.size(withAttributes: _itemAttributes).width
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/menuitem
    @MainActor open var menuItem: NSMenuItem? {
        get { _menuItem }
        set { _menuItem = newValue; _needsSizing = true; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/needsdisplay
    @MainActor open var needsDisplay: Bool {
        get { _needsDisplay }
        set { _needsDisplay = newValue; if newValue { _changed() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/needssizing
    @MainActor open var needsSizing: Bool {
        get { _needsSizing }
        set { _needsSizing = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/stateimagerect(forbounds:)
    @MainActor open func stateImageRect(forBounds cellFrame: NSRect) -> NSRect {
        NSRect(x: cellFrame.minX + 7, y: cellFrame.midY - 5, width: 10, height: 10)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/stateimagewidth
    @MainActor open var stateImageWidth: CGFloat { (_menuItem?.menu?.showsStateColumn ?? true) ? _NSMenuLayout.stateColumnWidth : _NSMenuLayout.leadingPadding }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/tag
    @MainActor open override var tag: Int {
        get { _menuItem?.tag ?? super.tag }
        set { if let i = _menuItem { i.tag = newValue } else { super.tag = newValue } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/titlerect(forbounds:)
    @MainActor open override func titleRect(forBounds cellFrame: NSRect) -> NSRect {
        let x = cellFrame.minX + stateImageWidth + imageWidth + CGFloat(_menuItem?.indentationLevel ?? 0) * _NSMenuLayout.indentation
        let key = keyEquivalentWidth
        let right = cellFrame.maxX - _NSMenuLayout.trailingPadding - (key > 0 ? key + _NSMenuLayout.keyEquivalentGap : 0)
        return NSRect(x: x, y: cellFrame.minY, width: max(0, right - x), height: cellFrame.height)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsmenuitemcell/titlewidth
    @MainActor open var titleWidth: CGFloat { (_menuItem?.title ?? stringValue).size(withAttributes: _itemAttributes).width }
}
