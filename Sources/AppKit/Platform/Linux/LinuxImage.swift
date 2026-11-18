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

/// PNG through cairo's stream readers and writers, and uncompressed 24/32-bit BMP (what a
/// Windows clipboard bitmap becomes, ADR-0030) by hand. Other formats need gdk-pixbuf,
/// which is not linked yet.
@MainActor
final class LinuxImageBackend: PlatformImageBackend {
    nonisolated init() {}
    private final class Reader {
        let data: Data
        var offset = 0
        init(_ d: Data) { data = d }
    }

    nonisolated func decode(_ data: Data) -> CGImage? {
        if data.count > 54, data[data.startIndex] == 0x42, data[data.startIndex + 1] == 0x4D { return LinuxImageBackend.decodeBMP([UInt8](data)) }
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
            copy.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
                for row in 0..<h { for x in 0..<w { buf.storeBytes(of: UInt8(255), toByteOffset: row * stride + x * 4 + 3, as: UInt8.self) } }
            }
        }
        return CGImage.fromBGRA(width: w, height: h, stride: stride, data: copy)
    }

    /// BI_RGB or BI_BITFIELDS (with the usual BGR(A) masks), 24 or 32 bits, either row order.
    nonisolated static func decodeBMP(_ b: [UInt8]) -> CGImage? {
        func u32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        let offset = u32(10), headerSize = u32(14)
        guard headerSize >= 40, b.count >= 14 + headerSize else { return nil }
        let w = u32(18), rawH = Int(Int32(truncatingIfNeeded: UInt32(u32(22))))
        let bits = u16(28), compression = u32(30)
        let h = abs(rawH)
        guard w > 0, h > 0, bits == 24 || bits == 32, compression == 0 || compression == 3 else { return nil }
        let rowBytes = ((w * bits + 31) / 32) * 4
        guard offset + rowBytes * h <= b.count else { return nil }
        let rowStride = w * 4
        var out = [UInt8](repeating: 255, count: rowStride * h)
        var anyAlpha = false
        for y in 0..<h {
            let src = offset + (rawH > 0 ? h - 1 - y : y) * rowBytes
            for x in 0..<w {
                let s = src + x * (bits / 8), d = y * rowStride + x * 4
                out[d] = b[s]; out[d + 1] = b[s + 1]; out[d + 2] = b[s + 2]
                if bits == 32 { out[d + 3] = b[s + 3]; if b[s + 3] != 0 { anyAlpha = true } }
            }
        }
        if bits == 32 {
            // An all-zero alpha byte means none (the common BI_RGB case): opaque. Otherwise
            // premultiply, as the BGRA images here are.
            for i in stride(from: 0, to: out.count, by: 4) {
                if !anyAlpha { out[i + 3] = 255; continue }
                let a = Int(out[i + 3])
                for k in 0..<3 { out[i + k] = UInt8(Int(out[i + k]) * a / 255) }
            }
        }
        return CGImage.fromBGRA(width: w, height: h, stride: rowStride, data: Data(out))
    }

    private final class Writer { var data = Data() }

    nonisolated func encode(_ image: CGImage, format: String, quality: Double) -> Data? {
        guard format.lowercased().hasSuffix("png") else { return nil }   // "png" or "public.png"
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
