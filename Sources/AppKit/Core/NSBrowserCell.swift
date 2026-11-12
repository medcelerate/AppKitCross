// NSBrowserCell (hand-written; seeded from the generated stub, see tools/apigen)
//
// A row of an NSBrowser column (ADR-0032): an optional image, the title, and for a branch
// (not `isLeaf`) a chevron at the trailing edge. A highlighted cell fills its row with the
// selection colour — the accent colour while its column's matrix has keyboard focus in
// the key window, the unemphasized grey otherwise — with light text over the accent.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell
@MainActor open class NSBrowserCell: NSCell {
    private var _alternateImage: NSImage? = nil
    private var _isLeaf = false
    private var _isLoaded = false

    @MainActor internal override func _copyCellState(from other: NSCell) {
        super._copyCellState(from: other)
        guard let o = other as? NSBrowserCell else { return }
        _alternateImage = o._alternateImage; _isLeaf = o._isLeaf; _isLoaded = o._isLoaded
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/init(coder:)
    public required init(coder: NSCoder) {
        super.init(coder: coder)
        _lineBreakMode = .byTruncatingTail
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/init(imagecell:)
    @MainActor public override init(imageCell image: NSImage?) {
        super.init(imageCell: image)
        _lineBreakMode = .byTruncatingTail
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/init(textcell:)
    @MainActor public override init(textCell string: String) {
        super.init(textCell: string)
        _lineBreakMode = .byTruncatingTail
    }

    // MARK: Branch images

    /// Draws a chevron pointing to the trailing edge in `rect`.
    nonisolated private static func _drawChevron(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        let w = min(rect.width, rect.height) * 0.3
        let cx = rect.midX, cy = rect.midY
        path.move(to: NSPoint(x: cx - w / 2, y: cy - w))
        path.line(to: NSPoint(x: cx + w / 2, y: cy))
        path.line(to: NSPoint(x: cx - w / 2, y: cy + w))
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
    private static func _chevronImage(color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 12), flipped: false) { rect in
            _drawChevron(in: rect, color: color)
            return true
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/branchimage
    @MainActor class public var branchImage: NSImage? { _chevronImage(color: .secondaryLabelColor) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/highlightedbranchimage
    @MainActor class public var highlightedBranchImage: NSImage? { _chevronImage(color: .alternateSelectedControlTextColor) }

    // MARK: Properties

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/image
    @MainActor open override var image: NSImage? {
        get { _image }
        set { _image = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/alternateimage
    @MainActor open var alternateImage: NSImage? {
        get { _alternateImage }
        set { _alternateImage = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/isleaf
    @MainActor open var isLeaf: Bool {
        get { _isLeaf }
        set { _isLeaf = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/isloaded
    @MainActor open var isLoaded: Bool {
        get { _isLoaded }
        set { _isLoaded = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/reset()
    /// Unhighlights the cell and turns it off.
    @MainActor open func reset() { _isHighlighted = false; _state = .off; _changed() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/set()
    /// Highlights the cell and turns it on.
    @MainActor open func set() { _isHighlighted = true; _state = .on; _changed() }

    /// Whether the selection is drawn emphasized: the control view has keyboard focus in
    /// the key window.
    private func _isEmphasized(in controlView: NSView) -> Bool {
        guard let w = controlView.window else { return false }
        return w.firstResponder === controlView && w.isKeyWindow
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbrowsercell/highlightcolor(in:)
    @MainActor open func highlightColor(in controlView: NSView) -> NSColor? {
        _isEmphasized(in: controlView) ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor
    }

    // MARK: Drawing

    private var _showsSelection: Bool { _isHighlighted || _state == .on }

    @MainActor open override var cellSize: NSSize {
        var s = super.cellSize
        if let img = _image { s.width += img.size.width + 4; s.height = max(s.height, img.size.height) }
        if !_isLeaf { s.width += 16 }
        return s
    }

    @MainActor open override func titleRect(forBounds rect: NSRect) -> NSRect {
        var r = rect.insetBy(dx: 4, dy: 0)
        if let img = _image { r.origin.x += img.size.width + 4; r.size.width -= img.size.width + 4 }
        if !_isLeaf { r.size.width -= 14 }
        r.size.width = max(0, r.width)
        return r
    }

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        if _showsSelection, let color = highlightColor(in: controlView) {
            color.setFill()
            NSBezierPath.fill(cellFrame)
        }
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    @MainActor open override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let emphasized = _showsSelection && _isEmphasized(in: controlView)
        let flipped = controlView.isFlipped
        if let img = (emphasized ? (_alternateImage ?? _image) : _image) {
            let s = img.size
            let r = NSRect(x: cellFrame.minX + 4, y: cellFrame.midY - s.height / 2, width: s.width, height: s.height)
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: _isEnabled ? 1 : 0.5, respectFlipped: true, hints: nil)
        }
        let text = stringValue
        if !text.isEmpty {
            var attrs = _textAttributes
            if emphasized { attrs[.foregroundColor] = NSColor.alternateSelectedControlTextColor }
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            attrs[.paragraphStyle] = para
            _drawText(text, attributes: attrs, in: titleRect(forBounds: cellFrame), alignment: _alignment, flipped: flipped)
        }
        if !_isLeaf {
            let r = NSRect(x: cellFrame.maxX - 14, y: cellFrame.minY, width: 10, height: cellFrame.height)
            NSBrowserCell._drawChevron(in: r, color: emphasized ? .alternateSelectedControlTextColor : (_isEnabled ? .secondaryLabelColor : .tertiaryLabelColor))
        }
    }
}
