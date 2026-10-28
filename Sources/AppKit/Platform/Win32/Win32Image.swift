// WIC-backed image decoding and Direct2D offscreen surfaces through the CD2D shim.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CD2D

@MainActor
final class Win32Offscreen: PlatformOffscreenSurface {
    private let handle: OpaquePointer          // CD2DOffscreen*
    let context: CGContext
    private let width: Int, height: Int

    init?(size: CGSize, scale: CGFloat, factory: OpaquePointer) {
        width = max(1, Int((size.width * scale).rounded(.up)))
        height = max(1, Int((size.height * scale).rounded(.up)))
        guard let h = cd2d_offscreen_create(factory, UInt32(width), UInt32(height), Float(96 * scale)),
              let target = cd2d_offscreen_target(h) else { return nil }
        handle = h
        cd2d_target_begin_draw(target)
        cd2d_target_clear(target, 0, 0, 0, 0)
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        context = CGContext(target: target, factory: factory, baseTransform: flip, width: width, height: height)
    }

    func makeImage() -> CGImage? {
        guard let target = cd2d_offscreen_target(handle) else { return nil }
        context.releaseImageCache()
        _ = cd2d_target_end_draw(target)
        var data = Data(count: width * height * 4)
        let stride = data.withUnsafeMutableBytes { buf -> UInt32 in
            cd2d_offscreen_read(handle, buf.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(buf.count))
        }
        cd2d_target_begin_draw(target)       // keep the surface drawable for further lockFocus use
        guard stride > 0 else { return nil }
        return CGImage.fromBGRA(width: width, height: height, stride: Int(stride), data: data)
    }

    deinit {
        if let target = cd2d_offscreen_target(handle) { _ = cd2d_target_end_draw(target) }
        cd2d_offscreen_release(handle)
    }
}

@MainActor
final class Win32BitmapOffscreen: PlatformOffscreenSurface {
    let context: CGContext
    init(context: CGContext) { self.context = context }
    func makeImage() -> CGImage? { context.makeImage() }
}

@MainActor
final class Win32ImageBackend: PlatformImageBackend {
    func decode(_ data: Data) -> CGImage? {
        var w: UInt32 = 0, h: UInt32 = 0, stride: UInt32 = 0
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        let ok = data.withUnsafeBytes { buf -> Bool in
            cd2d_image_decode(buf.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(buf.count), &w, &h, &stride, &pixels)
        }
        guard ok, let pixels else { return nil }
        defer { cd2d_image_free(pixels) }
        let copy = Data(bytes: pixels, count: Int(stride) * Int(h))
        return CGImage.fromBGRA(width: Int(w), height: Int(h), stride: Int(stride), data: copy)
    }

    func encode(_ image: CGImage, format: String, quality: Double) -> Data? {
        let fmt = format.contains("jpeg") || format.contains("jpg") ? "jpeg" : "png"
        var bytes: UnsafeMutablePointer<UInt8>? = nil
        var length: UInt32 = 0
        let ok = image.data.withUnsafeBytes { buf -> Bool in
            cd2d_image_encode(buf.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(image.width), UInt32(image.height), UInt32(image.bytesPerRow), fmt, Float(quality), &bytes, &length)
        }
        guard ok, let bytes else { return nil }
        defer { cd2d_image_free(bytes) }
        return Data(bytes: bytes, count: Int(length))
    }

    func makeOffscreen(size: CGSize, scale: CGFloat) -> PlatformOffscreenSurface? {
        if let factory = (Platform.backend as? Win32Backend)?.d2dFactory {
            return Win32Offscreen(size: size, scale: scale, factory: factory)
        }
        // Headless host backend (unit tests): a bitmap CGContext on CoreGraphics' own factory.
        let w = max(1, Int((size.width * scale).rounded(.up))), h = max(1, Int((size.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        return Win32BitmapOffscreen(context: ctx)
    }
}
#endif
