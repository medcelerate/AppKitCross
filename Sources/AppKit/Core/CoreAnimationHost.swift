// Connects QuartzCore to AppKit: the frame clock comes from the platform backend and
// CATextLayer text is drawn with AppKit's string drawing.

import Foundation
#if canImport(QuartzCore)
import QuartzCore
#endif

@MainActor
enum _CoreAnimationHost {
    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        CARuntime.frameRequester = {
            if NSView._traceInvalidation { NSView._trace("frame requested: \(CARuntime._pendingWorkDescription)") }
            let requested = NSView._traceFrames ? NSView._traceClock() : 0
            Platform.backend.scheduleFrame {
                let t0 = NSView._traceFrames ? NSView._traceClock() : 0
                CARuntime.tick()
                for w in NSApplication.shared.windows { w._commitLayerSceneIfNeeded() }
                if NSView._traceFrames {
                    NSView._trace(String(format: "frames tick %.1f ms after the request, %.1f ms", t0 - requested, NSView._traceClock() - t0))
                }
            }
        }
        CALayer._sceneExtraChildren = { layer in (layer.delegate as? NSView)?._hostedChildLayers ?? [] }
        CARuntime.textRenderer = { layer, ctx, flipped in
            drawText(of: layer, in: ctx, flipped: flipped)
        }
    }

    private static func drawText(of layer: CATextLayer, in ctx: CGContext, flipped: Bool) {
        let text: String
        var attrs: [NSAttributedString.Key: Any] = [:]
        if let s = layer.string as? String {
            text = s
        } else if let a = layer.string as? NSAttributedString {
            text = a.string
            if a.length > 0 { attrs = a.attributes(at: 0, effectiveRange: nil) }
        } else {
            return
        }
        guard !text.isEmpty else { return }
        var font = (attrs[.font] as? NSFont) ?? (layer.font as? NSFont) ?? (layer.font as? String).flatMap { NSFont(name: $0, size: layer.fontSize) } ?? NSFont.systemFont(ofSize: layer.fontSize)
        if attrs[.font] == nil, font.pointSize != layer.fontSize { font = font.withSize(layer.fontSize) }
        attrs[.font] = font
        if attrs[.foregroundColor] == nil {
            attrs[.foregroundColor] = layer.foregroundColor.flatMap { NSColor(cgColor: $0) } ?? NSColor.white
        }
        let gc = NSGraphicsContext(cgContext: ctx, flipped: flipped)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = gc
        defer { NSGraphicsContext.current = previous }
        let b = layer.bounds
        let size = text.size(withAttributes: attrs)
        var x = b.minX
        switch layer.alignmentMode {
        case .center: x = b.midX - size.width / 2
        case .right: x = b.maxX - size.width
        default: break
        }
        if layer.isWrapped {
            let r = NSRect(x: x, y: b.minY, width: b.width - (x - b.minX), height: b.height)
            text.draw(in: r, withAttributes: attrs)
        } else {
            let y = flipped ? b.minY : b.maxY - size.height
            text.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }
}
