// ImageIO-backed images for the macOS host build (Apple's ImageIO; on Windows and Linux
// the platform backends decode and encode, see HostBackend).

import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO) && !os(Windows) && !os(Linux)
import CoreGraphics
import ImageIO

@MainActor
final class HostOffscreen: PlatformOffscreenSurface {
    let context: CGContext
    init(context: CGContext) { self.context = context }
    func makeImage() -> CGImage? { context.makeImage() }
}

@MainActor
final class HostImageBackend: PlatformImageBackend {
    func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func encode(_ image: CGImage, format: String, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, format as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality as String: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    func makeOffscreen(size: CGSize, scale: CGFloat) -> PlatformOffscreenSurface? {
        let w = max(1, Int((size.width * scale).rounded(.up))), h = max(1, Int((size.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        return HostOffscreen(context: ctx)
    }
}
#endif
