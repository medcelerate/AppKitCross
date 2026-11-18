// NSTextAttachmentCell (hand-written; was pending in tools/apigen)
//
// The cell an attachment uses to size and draw itself in a layout manager. AppKit's
// protocol requires `cellSize()` as a method while NSCell has a `cellSize` property; Swift
// allows the method in this subclass alongside the inherited property, so both exist as
// in AppKit. The cell draws its image scaled into the frame the layout manager gives it.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nstextattachmentcell
@MainActor open class NSTextAttachmentCell: NSCell, NSTextAttachmentCellProtocol {
    nonisolated(unsafe) private weak var _attachment: NSTextAttachment?

    /// A cell with no image.
    public override init() { super.init(imageCell: nil) }
    public override init(imageCell image: NSImage?) { super.init(imageCell: image) }
    public override init(textCell string: String) { super.init(textCell: string) }
    public required init(coder: NSCoder) { super.init(coder: coder) }

    // Requirement of NSTextAttachmentCellProtocol
    /// The attachment that owns the cell (not retained: the attachment owns the cell).
    nonisolated open var attachment: NSTextAttachment? {
        get { _attachment }
        set { _attachment = newValue }
    }
    // Requirement of NSTextAttachmentCellProtocol
    /// The image's size; a cell without an image is an empty 0×0 box.
    open nonisolated func cellSize() -> NSSize {
        MainActor.assumeIsolated { image?.size ?? .zero }
    }
    // Requirement of NSTextAttachmentCellProtocol
    /// The cell sits on the baseline.
    open nonisolated func cellBaselineOffset() -> NSPoint { .zero }
    // Requirement of NSTextAttachmentCellProtocol
    open nonisolated func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        NSRect(origin: cellBaselineOffset(), size: cellSize())
    }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        image?.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if isHighlighted {
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45).setFill()
            NSBezierPath.fill(cellFrame)
        }
    }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {
        draw(withFrame: cellFrame, in: controlView)
    }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        draw(withFrame: cellFrame, in: controlView, characterIndex: charIndex)
    }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView?) { isHighlighted = flag }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open func wantsToTrackMouse() -> Bool { true }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open func wantsToTrackMouse(for theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, atCharacterIndex charIndex: Int) -> Bool { wantsToTrackMouse() }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool { false }
    // Requirement of NSTextAttachmentCellProtocol
    @MainActor open func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, atCharacterIndex charIndex: Int, untilMouseUp flag: Bool) -> Bool {
        trackMouse(with: theEvent, in: cellFrame, of: controlView, untilMouseUp: flag)
    }
}
