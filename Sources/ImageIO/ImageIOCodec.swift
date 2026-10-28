// The codec seam behind CGImageSource and CGImageDestination: container sniffing and
// header parsing shared by every platform, pixel decode/encode through WIC (Windows,
// via the CD2D shim) or Cairo's PNG reader and writer (Linux). ImageIO cannot depend on
// AppKit, so these call the C modules directly.

import Foundation
import CoreGraphics
#if os(Windows)
import CD2D
#elseif os(Linux)
import CCairo
#endif

enum ImageIOCodec {
    // MARK: Container formats

    /// Containers whose magic bytes are recognised; a sniffed type is only reported when
    /// the platform can also decode it.
    static let containers: [(uti: String, magic: [UInt8?])] = [
        ("public.png", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ("public.jpeg", [0xFF, 0xD8, 0xFF]),
        ("com.compuserve.gif", [0x47, 0x49, 0x46, 0x38]),
        ("com.microsoft.bmp", [0x42, 0x4D]),
        ("public.tiff", [0x49, 0x49, 0x2A, 0x00]),
        ("public.tiff", [0x4D, 0x4D, 0x00, 0x2A]),
        ("com.microsoft.ico", [0x00, 0x00, 0x01, 0x00]),
        ("org.webmproject.webp", [0x52, 0x49, 0x46, 0x46, nil, nil, nil, nil, 0x57, 0x45, 0x42, 0x50]),
    ]

    #if os(Windows)
    /// WIC's built-in decoders.
    static let decodableTypes = ["public.jpeg", "public.png", "com.compuserve.gif", "public.tiff", "com.microsoft.bmp", "com.microsoft.ico"]
    /// What `cd2d_image_encode` drives: the WIC PNG and JPEG encoders.
    static let encodableTypes = ["public.jpeg", "public.png"]
    #elseif os(Linux)
    /// Cairo reads and writes PNG only (gdk-pixbuf is not linked).
    static let decodableTypes = ["public.png"]
    static let encodableTypes = ["public.png"]
    #else
    static let decodableTypes: [String] = []
    static let encodableTypes: [String] = []
    #endif

    static func sniff(_ data: Data) -> String? {
        for (uti, magic) in containers where data.count >= magic.count {
            var matches = true
            for (i, byte) in magic.enumerated() where byte != nil && data[data.startIndex + i] != byte! { matches = false; break }
            if matches { return uti }
        }
        return nil
    }

    static func canonicalType(_ type: String, in list: [String]) -> String? {
        list.first { $0.caseInsensitiveCompare(type) == .orderedSame }
    }

    // MARK: Header parsing

    struct Header {
        var width: Int
        var height: Int
        var depth: Int
        var hasAlpha: Bool?
        var isIndexed = false
        var colorModel: String
        var dpiWidth: Double?
        var dpiHeight: Double?
        var pngGamma: Double?
        var pngInterlace: Int?
        var pngPixelsPerMeter: (x: Int, y: Int)?
    }

    /// The PNG IHDR (and pHYs/gAMA) chunks, so properties come without a decode.
    static func pngHeader(_ data: Data) -> Header? {
        guard data.count >= 33, sniff(data) == "public.png" else { return nil }
        let bytes = [UInt8](data)
        func be32(_ at: Int) -> Int { Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]) }
        guard String(decoding: bytes[12..<16], as: UTF8.self) == "IHDR" else { return nil }
        let width = be32(16), height = be32(20)
        let bitDepth = Int(bytes[24]), colorType = Int(bytes[25]), interlace = Int(bytes[28])
        guard width > 0, height > 0 else { return nil }
        var header = Header(width: width, height: height, depth: bitDepth, hasAlpha: nil, colorModel: "RGB")
        switch colorType {
        case 0: header.colorModel = "Gray"
        case 2: break
        case 3: header.isIndexed = true
        case 4: header.colorModel = "Gray"; header.hasAlpha = true
        case 6: header.hasAlpha = true
        default: break
        }
        header.pngInterlace = interlace
        // Walk the ancillary chunks before IDAT for pHYs and gAMA.
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = be32(offset)
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let body = offset + 8
            guard body + length + 4 <= bytes.count else { break }
            if type == "IDAT" || type == "IEND" { break }
            if type == "pHYs", length == 9, bytes[body + 8] == 1 {
                let x = be32(body), y = be32(body + 4)
                header.pngPixelsPerMeter = (x, y)
                header.dpiWidth = Double(x) * 0.0254
                header.dpiHeight = Double(y) * 0.0254
            } else if type == "gAMA", length == 4 {
                header.pngGamma = Double(be32(body)) / 100_000
            }
            offset = body + length + 4
        }
        return header
    }

    // MARK: Pixels

    /// The image's pixels as premultiplied BGRA rows, which both codecs consume.
    static func bgraPixels(_ image: CGImage) -> (data: Data, stride: Int) {
        guard image.bitsPerPixel == 32, image.bitsPerComponent == 8 else { unimplemented("ImageIO encode of \(image.bitsPerPixel)-bit pixels") }
        let little = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue
        let alpha = image.alphaInfo
        let alphaFirst: Bool, premultiplied: Bool, hasAlpha: Bool
        switch alpha {
        case .premultipliedFirst: (alphaFirst, premultiplied, hasAlpha) = (true, true, true)
        case .first: (alphaFirst, premultiplied, hasAlpha) = (true, false, true)
        case .noneSkipFirst: (alphaFirst, premultiplied, hasAlpha) = (true, true, false)
        case .premultipliedLast: (alphaFirst, premultiplied, hasAlpha) = (false, true, true)
        case .last: (alphaFirst, premultiplied, hasAlpha) = (false, false, true)
        case .noneSkipLast: (alphaFirst, premultiplied, hasAlpha) = (false, true, false)
        default: unimplemented("ImageIO encode of alpha layout \(alpha)")
        }
        // Memory order of the four components.
        let order: (r: Int, g: Int, b: Int, a: Int)
        switch (little, alphaFirst) {
        case (true, true): order = (2, 1, 0, 3)      // BGRA
        case (false, true): order = (1, 2, 3, 0)     // ARGB
        case (false, false): order = (0, 1, 2, 3)    // RGBA
        case (true, false): order = (3, 2, 1, 0)     // ABGR
        }
        if order.r == 2, order.a == 3, premultiplied, hasAlpha { return (image.data, image.bytesPerRow) }
        let width = image.width, height = image.height, srcStride = image.bytesPerRow
        var out = Data(count: width * 4 * height)
        image.data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                for y in 0..<height {
                    for x in 0..<width {
                        let s = y * srcStride + x * 4, d = y * width * 4 + x * 4
                        var r = Int(src[s + order.r]), g = Int(src[s + order.g]), b = Int(src[s + order.b])
                        let a = hasAlpha ? Int(src[s + order.a]) : 255
                        if !premultiplied, a < 255 { r = r * a / 255; g = g * a / 255; b = b * a / 255 }
                        dst[d] = UInt8(b); dst[d + 1] = UInt8(g); dst[d + 2] = UInt8(r); dst[d + 3] = UInt8(a)
                    }
                }
            }
        }
        return (out, width * 4)
    }

    /// Nearest-neighbour downscale so that the longer side is at most `maxPixelSize`.
    static func scaled(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        guard maxPixelSize > 0, max(image.width, image.height) > maxPixelSize else { return image }
        let scale = Double(maxPixelSize) / Double(max(image.width, image.height))
        let w = max(1, Int((Double(image.width) * scale).rounded())), h = max(1, Int((Double(image.height) * scale).rounded()))
        let (src, srcStride) = bgraPixels(image)
        var out = Data(count: w * 4 * h)
        src.withUnsafeBytes { (s: UnsafeRawBufferPointer) in
            out.withUnsafeMutableBytes { (d: UnsafeMutableRawBufferPointer) in
                for y in 0..<h {
                    let sy = min(image.height - 1, y * image.height / h)
                    for x in 0..<w {
                        let sx = min(image.width - 1, x * image.width / w)
                        let si = sy * srcStride + sx * 4, di = y * w * 4 + x * 4
                        for c in 0..<4 { d[di + c] = s[si + c] }
                    }
                }
            }
        }
        return CGImage.fromBGRA(width: w, height: h, stride: w * 4, data: out)
    }

    #if os(Windows)
    static func decode(_ data: Data) -> CGImage? {
        var w: UInt32 = 0, h: UInt32 = 0, stride: UInt32 = 0
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        let ok = data.withUnsafeBytes { buf -> Bool in
            cd2d_image_decode(buf.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(buf.count), &w, &h, &stride, &pixels)
        }
        guard ok, let pixels else { return nil }
        defer { cd2d_image_free(pixels) }
        return CGImage.fromBGRA(width: Int(w), height: Int(h), stride: Int(stride), data: Data(bytes: pixels, count: Int(stride) * Int(h)))
    }

    static func encode(_ image: CGImage, type: String, quality: Double) -> Data? {
        let format = type == "public.jpeg" ? "jpeg" : "png"
        let (pixels, stride) = bgraPixels(image)
        var bytes: UnsafeMutablePointer<UInt8>? = nil
        var length: UInt32 = 0
        let ok = pixels.withUnsafeBytes { buf -> Bool in
            cd2d_image_encode(buf.baseAddress?.assumingMemoryBound(to: UInt8.self), UInt32(image.width), UInt32(image.height), UInt32(stride), format, Float(quality), &bytes, &length)
        }
        guard ok, let bytes else { return nil }
        defer { cd2d_image_free(bytes) }
        return Data(bytes: bytes, count: Int(length))
    }
    #elseif os(Linux)
    private final class Reader {
        let data: Data
        var offset = 0
        init(_ d: Data) { data = d }
    }

    private final class Writer { var data = Data() }

    static func decode(_ data: Data) -> CGImage? {
        guard sniff(data) == "public.png" else { return nil }
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
        let format = cairo_image_surface_get_format(surface)
        guard format == CAIRO_FORMAT_ARGB32 || format == CAIRO_FORMAT_RGB24, let base = cairo_image_surface_get_data(surface) else { return nil }
        let w = Int(cairo_image_surface_get_width(surface)), h = Int(cairo_image_surface_get_height(surface))
        let stride = Int(cairo_image_surface_get_stride(surface))
        var copy = Data(bytes: base, count: stride * h)
        if format == CAIRO_FORMAT_RGB24 {
            // RGB24 leaves the alpha byte undefined; make it opaque.
            copy.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
                for row in 0..<h { for x in 0..<w { buf.storeBytes(of: UInt8(255), toByteOffset: row * stride + x * 4 + 3, as: UInt8.self) } }
            }
        }
        return CGImage.fromBGRA(width: w, height: h, stride: stride, data: copy)
    }

    static func encode(_ image: CGImage, type: String, quality: Double) -> Data? {
        guard type == "public.png" else { return nil }
        let (pixels, srcStride) = bgraPixels(image)
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(image.width), Int32(image.height)),
              let dst = cairo_image_surface_get_data(surface) else { return nil }
        defer { cairo_surface_destroy(surface) }
        let stride = Int(cairo_image_surface_get_stride(surface))
        pixels.withUnsafeBytes { src in
            guard let base = src.baseAddress else { return }
            for row in 0..<image.height { memcpy(dst + row * stride, base + row * srcStride, min(stride, srcStride)) }
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
    #else
    static func decode(_ data: Data) -> CGImage? { nil }
    static func encode(_ image: CGImage, type: String, quality: Double) -> Data? { nil }
    #endif
}

// MARK: Option dictionaries

extension NSDictionary {
    func imageIOValue(_ key: CFString) -> Any? { object(forKey: key) }

    func imageIODouble(_ key: CFString) -> Double? {
        switch imageIOValue(key) {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let f as Float: return Double(f)
        case let i as Int: return Double(i)
        default: return nil
        }
    }

    func imageIOBool(_ key: CFString) -> Bool? {
        switch imageIOValue(key) {
        case let n as NSNumber: return n.boolValue
        case let b as Bool: return b
        default: return nil
        }
    }
}
