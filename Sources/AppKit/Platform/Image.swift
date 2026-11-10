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

/// Decoding and encoding are pure functions of their bytes on every backend (ImageIO,
/// cairo's PNG streams, WIC) and run on the calling thread, so `NSImage(data:)` and
/// `NSBitmapImageRep(data:)` work off the main actor as Apple's do (Nuke decodes on its
/// pipeline's tasks); the backends keep no state, which makes them `Sendable`.
@MainActor
public protocol PlatformImageBackend: AnyObject, Sendable {
    /// Decodes PNG/JPEG/BMP/GIF/TIFF data.
    nonisolated func decode(_ data: Data) -> CGImage?
    /// Encodes to the given UTI-like format ("public.png", "public.jpeg").
    nonisolated func encode(_ image: CGImage, format: String, quality: Double) -> Data?
    /// Creates a surface of `size` points at `scale`. The context is in points, y-up.
    func makeOffscreen(size: CGSize, scale: CGFloat) -> PlatformOffscreenSurface?
}

extension Platform {
    /// The process-wide image codec, usable from any thread (`Platform.backend.image` is
    /// the same codec behind the main-actor backend).
    nonisolated public static let imageCodec: any PlatformImageBackend = {
        #if canImport(ImageIO) && canImport(CoreGraphics) && !os(Windows) && !os(Linux)
        return HostImageBackend()
        #elseif os(Linux)
        return LinuxImageBackend()
        #elseif os(Windows)
        return Win32ImageBackend()
        #else
        return NoImageBackend()
        #endif
    }()
}
