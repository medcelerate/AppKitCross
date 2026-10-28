// Image seam: decoding/encoding bitmaps and drawing into offscreen surfaces.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An offscreen drawing surface for NSImage.lockFocus and friends.
@MainActor
public protocol PlatformOffscreenSurface: AnyObject {
    var context: CGContext { get }
    /// Ends drawing and returns the pixels as an image.
    func makeImage() -> CGImage?
}

@MainActor
public protocol PlatformImageBackend: AnyObject {
    /// Decodes PNG/JPEG/BMP/GIF/TIFF data.
    func decode(_ data: Data) -> CGImage?
    /// Encodes to the given UTI-like format ("public.png", "public.jpeg").
    func encode(_ image: CGImage, format: String, quality: Double) -> Data?
    /// Creates a surface of `size` points at `scale`. The context is in points, y-up.
    func makeOffscreen(size: CGSize, scale: CGFloat) -> PlatformOffscreenSurface?
}
