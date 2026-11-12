// String drawing (AppKit's NSStringDrawing additions on NSString / NSAttributedString).
//
// Milestone 1 scope: a single font and color per string (taken from the attributes, else
// the font set with NSFont.set(), else the user font), left aligned, line breaks on "\n",
// wrapping inside draw(in:). Paragraph styles and multiple runs come with NSLayoutManager.

import Foundation

/// Measured sizes by string, font and wrap width. A layout pass asks every label for its
/// intrinsic size, and each backend measures by building a text layout (a DirectWrite
/// layout on Windows, Core Text lines, Pango), so a label whose text has not changed is
/// measured once rather than on every pass; a stepper's held repeat re-lays its window
/// ten times a second, and on Windows the measuring was most of each frame.
@MainActor
internal enum _NSTextMeasureCache {
    private struct Key: Hashable { let text: String; let font: NSFont._Identity; let maxWidth: CGFloat? }
    private static var sizes: [Key: NSSize] = [:]
    /// Entries kept before the cache starts over (a bound on memory, not a working set).
    static let limit = 4096
    static var hits = 0, misses = 0

    static func measure(_ text: String, font: NSFont, maxWidth: CGFloat?) -> NSSize {
        let key = Key(text: text, font: font._identity, maxWidth: maxWidth)
        if let s = sizes[key] { hits += 1; return s }
        misses += 1
        let s = Platform.backend.text.measure(text, font: font.handle, maxWidth: maxWidth)
        if sizes.count >= limit { sizes.removeAll(keepingCapacity: true) }
        sizes[key] = s
        return s
    }

    static func removeAll() { sizes.removeAll() }
}

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
        let size = _NSTextMeasureCache.measure(string, font: font, maxWidth: maxWidth)
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
        return _NSTextMeasureCache.measure(self as String, font: font, maxWidth: nil)
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
