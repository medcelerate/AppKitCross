// A view's pixels as an image (drag images of collection items and table rows). Hand-written
// support code, not AppKit API.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension NSView {
    /// An image of `bounds` (view coordinates) showing the view's drawing inside `rects`
    /// only (transparent elsewhere), rendered now with `cacheDisplay(in:to:)`.
    @MainActor internal func _snapshotImage(of rects: [NSRect], in bounds: NSRect) -> NSImage {
        let image = NSImage(size: bounds.size)
        guard bounds.width > 0, bounds.height > 0, let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return image }
        cacheDisplay(in: bounds, to: rep)
        guard rects.count != 1 || rects[0] != bounds, let full = rep.cgImage else {
            image.addRepresentation(rep)
            return image
        }
        // Keep only the rects: draw the full picture clipped to them.
        let flipped = isFlipped
        return NSImage(size: bounds.size, flipped: flipped) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.clip(to: rects.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) })
            NSImage(cgImage: full, size: bounds.size).draw(in: NSRect(origin: .zero, size: bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            ctx.restoreGState()
            return true
        }
    }
}
