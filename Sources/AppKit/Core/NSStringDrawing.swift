// String drawing (AppKit's NSStringDrawing additions on NSString / NSAttributedString).
//
// Milestone 1 scope: a single font and color per string (taken from the attributes, else
// the font set with NSFont.set(), else the user font), left aligned, line breaks on "\n",
// wrapping inside draw(in:). Paragraph styles and multiple runs come with NSLayoutManager.

import Foundation

@MainActor
private func _resolve(_ attrs: [NSAttributedString.Key: Any]?) -> (NSFont, NSColor) {
    let font = (attrs?[.font] as? NSFont) ?? NSGraphicsContext.current?._font ?? NSFont.userFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
    let color = (attrs?[.foregroundColor] as? NSColor) ?? .textColor
    return (font, color)
}

@MainActor
private func _draw(_ string: String, font: NSFont, color: NSColor, at point: NSPoint, maxWidth: CGFloat?, inRectTop: Bool) {
    guard let gc = NSGraphicsContext.current else { return }
    let flipped = gc.isFlipped
    let backend = Platform.backend.text
    // draw(at:) puts the box's origin at `point`: bottom-left in y-up contexts, top-left in flipped ones.
    var topLeft = point
    if !flipped && !inRectTop {
        let size = backend.measure(string, font: font.handle, maxWidth: maxWidth)
        topLeft.y += size.height
    }
    backend.draw(string, font: font.handle, color: color.cgColor, topLeft: topLeft, maxWidth: maxWidth, flipped: flipped, in: gc.cgContext)
}

extension NSString {
    @MainActor public func draw(at point: NSPoint, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {
        let (font, color) = _resolve(attrs)
        _draw(self as String, font: font, color: color, at: point, maxWidth: nil, inRectTop: false)
    }

    @MainActor public func draw(in rect: NSRect, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {
        let (font, color) = _resolve(attrs)
        let flipped = NSGraphicsContext.current?.isFlipped ?? false
        let top = NSPoint(x: rect.minX, y: flipped ? rect.minY : rect.maxY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.clip(to: rect)
        _draw(self as String, font: font, color: color, at: top, maxWidth: rect.width, inRectTop: true)
        NSGraphicsContext.restoreGraphicsState()
    }

    @MainActor public func size(withAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSSize {
        let (font, _) = _resolve(attrs)
        return Platform.backend.text.measure(self as String, font: font.handle, maxWidth: nil)
    }
}

extension String {
    @MainActor public func draw(at point: NSPoint, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {
        (self as NSString).draw(at: point, withAttributes: attrs)
    }
    @MainActor public func draw(in rect: NSRect, withAttributes attrs: [NSAttributedString.Key: Any]? = nil) {
        (self as NSString).draw(in: rect, withAttributes: attrs)
    }
    @MainActor public func size(withAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSSize {
        (self as NSString).size(withAttributes: attrs)
    }
}

extension NSAttributedString {
    @MainActor private var _firstRunAttributes: [NSAttributedString.Key: Any]? {
        length > 0 ? attributes(at: 0, effectiveRange: nil) : nil
    }
    @MainActor public func draw(at point: NSPoint) {
        (string as NSString).draw(at: point, withAttributes: _firstRunAttributes)
    }
    @MainActor public func draw(in rect: NSRect) {
        (string as NSString).draw(in: rect, withAttributes: _firstRunAttributes)
    }
    @MainActor public func size() -> NSSize {
        (string as NSString).size(withAttributes: _firstRunAttributes)
    }
}
