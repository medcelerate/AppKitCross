// Cairo-backed images (PNG) and offscreen surfaces for Linux.

#if os(Linux)
import Foundation
import CoreGraphics
import CCairo

@MainActor
final class LinuxOffscreen: PlatformOffscreenSurface {
    let context: CGContext

    init?(size: CGSize, scale: CGFloat) {
        let w = max(1, Int((size.width * scale).rounded(.up))), h = max(1, Int((size.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: 0) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        context = ctx
    }

    func makeImage() -> CGImage? { context.makeImage() }
}

/// PNG through cairo's stream readers and writers. Other formats need gdk-pixbuf, which is
/// not linked yet.
@MainActor
final class LinuxImageBackend: PlatformImageBackend {
    private final class Reader {
        let data: Data
        var offset = 0
        init(_ d: Data) { data = d }
    }

    func decode(_ data: Data) -> CGImage? {
        guard data.count > 8, data[0] == 0x89, data[1] == 0x50 else { return nil }   // PNG signature
        let reader = Reader(data)
        let unmanaged = Unmanaged.passRetained(reader)
        defer { unmanaged.release() }
        let surface = cairo_image_surface_create_from_png_stream({ closure, buffer, length in
            guard let closure, let buffer else { return CAIRO_STATUS_READ_ERROR }
            let r = Unmanaged<Reader>.fromOpaque(closure).takeUnretainedValue()
            let n = Int(length)
            guard r.offset + n <= r.data.count else { return CAIRO_STATUS_READ_ERROR }
            r.data.withUnsafeBytes { src in _ = memcpy(buffer, src.baseAddress! + r.offset, n) }
            r.offset += n
            return CAIRO_STATUS_SUCCESS
        }, unmanaged.toOpaque())
        guard let surface, cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else { return nil }
        defer { cairo_surface_destroy(surface) }
        cairo_surface_flush(surface)
        let w = Int(cairo_image_surface_get_width(surface)), h = Int(cairo_image_surface_get_height(surface))
        let stride = Int(cairo_image_surface_get_stride(surface))
        guard let base = cairo_image_surface_get_data(surface), cairo_image_surface_get_format(surface) == CAIRO_FORMAT_ARGB32 || cairo_image_surface_get_format(surface) == CAIRO_FORMAT_RGB24 else { return nil }
        var copy = Data(bytes: base, count: stride * h)
        if cairo_image_surface_get_format(surface) == CAIRO_FORMAT_RGB24 {
            // RGB24 leaves the alpha byte undefined; make it opaque.
            copy.withUnsafeMutableBytes { buf in
                for row in 0..<h { for x in 0..<w { buf[row * stride + x * 4 + 3] = 255 } }
            }
        }
        return CGImage.fromBGRA(width: w, height: h, stride: stride, data: copy)
    }

    private final class Writer { var data = Data() }

    func encode(_ image: CGImage, format: String, quality: Double) -> Data? {
        guard format.lowercased() == "png" else { return nil }
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(image.width), Int32(image.height)),
              let dst = cairo_image_surface_get_data(surface) else { return nil }
        defer { cairo_surface_destroy(surface) }
        let stride = Int(cairo_image_surface_get_stride(surface))
        image.data.withUnsafeBytes { src in
            guard let base = src.baseAddress else { return }
            for row in 0..<image.height { memcpy(dst + row * stride, base + row * image.bytesPerRow, min(stride, image.bytesPerRow)) }
        }
        cairo_surface_mark_dirty(surface)
        let writer = Writer()
        let unmanaged = Unmanaged.passRetained(writer)
        defer { unmanaged.release() }
        let status = cairo_surface_write_to_png_stream(surface, { closure, bytes, length in
            guard let closure, let bytes else { return CAIRO_STATUS_WRITE_ERROR }
            Unmanaged<Writer>.fromOpaque(closure).takeUnretainedValue().data.append(bytes, count: Int(length))
            return CAIRO_STATUS_SUCCESS
        }, unmanaged.toOpaque())
        return status == CAIRO_STATUS_SUCCESS ? writer.data : nil
    }

    func makeOffscreen(size: CGSize, scale: CGFloat) -> PlatformOffscreenSurface? { LinuxOffscreen(size: size, scale: scale) }
}
#endif
