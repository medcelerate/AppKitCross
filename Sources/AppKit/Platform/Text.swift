// Text seam. The core measures and draws strings through this; backends use CoreText
// (host) or DirectWrite (Windows). All sizes are in points.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A platform font instance.
public protocol PlatformFontHandle: AnyObject {
    var pointSize: CGFloat { get }
    var ascent: CGFloat { get }          // positive
    var descent: CGFloat { get }         // positive
    var leading: CGFloat { get }
    var capHeight: CGFloat { get }
    var xHeight: CGFloat { get }
    var familyName: String { get }
    var postScriptName: String { get }
    var isFixedPitch: Bool { get }
}

@MainActor
public protocol PlatformTextBackend: AnyObject {
    /// Creates a font. `family` nil means the system UI font. `weight` is in AppKit's
    /// -1...1 scale, 0 regular. Returns nil when a named font cannot be found.
    func makeFont(family: String?, size: CGFloat, weight: CGFloat, italic: Bool, monospaced: Bool) -> PlatformFontHandle?
    /// Size of `text` laid out with `font`; wrapped at `maxWidth` when given. Newlines break lines.
    func measure(_ text: String, font: PlatformFontHandle, maxWidth: CGFloat?) -> CGSize
    /// Draws `text` with the top-left corner of its box at `topLeft` in the context's current
    /// user space. `flipped` says whether that user space has y increasing downwards.
    func draw(_ text: String, font: PlatformFontHandle, color: CGColor, topLeft: CGPoint, maxWidth: CGFloat?, flipped: Bool, in context: CGContext)
}
