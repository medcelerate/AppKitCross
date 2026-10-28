// NSImageCell (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagecell
@MainActor open class NSImageCell: NSCell {
    private var _imageAlignment: NSImageAlignment = .alignCenter
    private var _imageScaling: NSImageScaling = .scaleProportionallyDown
    private var _imageFrameStyle: NSImageView.FrameStyle = .none

    /// Rect in which `image` is drawn inside `bounds` according to scaling and alignment.
    @MainActor internal func _imageRect(for image: NSImage, in bounds: NSRect) -> NSRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        var w = size.width, h = size.height
        switch _imageScaling {
        case .scaleProportionallyDown:
            let f = min(1, min(bounds.width / w, bounds.height / h)); w *= f; h *= f
        case .scaleProportionallyUpOrDown:
            let f = min(bounds.width / w, bounds.height / h); w *= f; h *= f
        case .scaleAxesIndependently:
            w = bounds.width; h = bounds.height
        default: break
        }
        var x = bounds.midX - w / 2, y = bounds.midY - h / 2
        switch _imageAlignment {
        case .alignTop, .alignTopLeft, .alignTopRight: y = bounds.maxY - h
        case .alignBottom, .alignBottomLeft, .alignBottomRight: y = bounds.minY
        default: break
        }
        switch _imageAlignment {
        case .alignLeft, .alignTopLeft, .alignBottomLeft: x = bounds.minX
        case .alignRight, .alignTopRight, .alignBottomRight: x = bounds.maxX - w
        default: break
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }

    @MainActor open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        _controlView = controlView
        var inner = cellFrame
        switch _imageFrameStyle {
        case .none: break
        default:
            NSColor.separatorColor.setStroke()
            NSBezierPath.stroke(cellFrame.insetBy(dx: 0.5, dy: 0.5))
            inner = cellFrame.insetBy(dx: 2, dy: 2)
        }
        guard let image = _image else { return }
        let rect = _imageRect(for: image, in: inner)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clip(to: inner)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: _isEnabled ? 1 : 0.5, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    @MainActor open override var cellSize: NSSize { _image?.size ?? .zero }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagecell/imagealignment
    @MainActor open var imageAlignment: NSImageAlignment {
        get { _imageAlignment }
        set { _imageAlignment = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagecell/imageframestyle
    @MainActor open var imageFrameStyle: NSImageView.FrameStyle {
        get { _imageFrameStyle }
        set { _imageFrameStyle = newValue; _changed() }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsimagecell/imagescaling
    @MainActor open var imageScaling: NSImageScaling {
        get { _imageScaling }
        set { _imageScaling = newValue; _changed() }
    }
}
