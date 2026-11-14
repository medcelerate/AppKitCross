// Portable image file writers and the TIFF reader (ADR-0036). Hand-written support for
// NSBitmapImageRep, not AppKit API: `tiffRepresentation` is a baseline TIFF on every
// platform (cairo's codecs on Linux know only PNG), BMP export needs no platform codec,
// and a TIFF the port wrote reads back where the platform decoder has no TIFF support.

import Foundation

/// 8-bit RGBA pixels, rows top first, `width * 4` bytes each, alpha not premultiplied.
internal struct _NSRGBAPixels {
    var width: Int
    var height: Int
    var bytes: [UInt8]
    var hasAlpha: Bool
}

internal enum _NSTIFFCodec {
    /// TIFF compression schemes the writer applies (others fall back to none, as AppKit
    /// does with a scheme it cannot apply).
    static let writableCompressions: [NSBitmapImageRep.TIFFCompression] = [.none, .packBits]

    // MARK: Writing (big-endian "MM", one IFD per image, one strip each)

    static func encode(_ images: [(pixels: _NSRGBAPixels, dpi: (x: Double, y: Double))], compression: NSBitmapImageRep.TIFFCompression) -> Data {
        let packBits = compression == .packBits
        var out = [UInt8]()
        func u16(_ v: Int) { out += [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func u32(_ v: Int) { out += [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func patch32(_ at: Int, _ v: Int) { out[at] = UInt8((v >> 24) & 0xFF); out[at + 1] = UInt8((v >> 16) & 0xFF); out[at + 2] = UInt8((v >> 8) & 0xFF); out[at + 3] = UInt8(v & 0xFF) }
        out += [0x4D, 0x4D]; u16(42)
        var nextIFDPointer = out.count; u32(0)
        for (pixels, dpi) in images {
            let spp = pixels.hasAlpha ? 4 : 3
            var strip = [UInt8](); strip.reserveCapacity(pixels.width * pixels.height * spp)
            for y in 0..<pixels.height {
                var row = [UInt8](); row.reserveCapacity(pixels.width * spp)
                for x in 0..<pixels.width {
                    let i = (y * pixels.width + x) * 4
                    row += pixels.bytes[i..<(i + spp)]
                }
                strip += packBits ? _packBits(row) : row
            }
            // Out-of-line values first: the strip, bits per sample, resolutions.
            let stripOffset = out.count; out += strip
            if out.count % 2 == 1 { out.append(0) }
            let bpsOffset = out.count; for _ in 0..<spp { u16(8) }
            let xresOffset = out.count; u32(Int((dpi.x * 10000).rounded())); u32(10000)
            let yresOffset = out.count; u32(Int((dpi.y * 10000).rounded())); u32(10000)
            if out.count % 2 == 1 { out.append(0) }
            let ifd = out.count
            patch32(nextIFDPointer, ifd)
            var entries: [(tag: Int, type: Int, count: Int, value: Int)] = [
                (256, 4, 1, pixels.width), (257, 4, 1, pixels.height),
                (258, 3, spp, bpsOffset), (259, 3, 1, packBits ? 32773 : 1),
                (262, 3, 1, 2), (273, 4, 1, stripOffset), (277, 3, 1, spp),
                (278, 4, 1, pixels.height), (279, 4, 1, strip.count),
                (282, 5, 1, xresOffset), (283, 5, 1, yresOffset), (284, 3, 1, 1), (296, 3, 1, 2),
            ]
            if pixels.hasAlpha { entries.append((338, 3, 1, 2)) }   // unassociated alpha
            entries.sort { $0.tag < $1.tag }
            u16(entries.count)
            for e in entries {
                u16(e.tag); u16(e.type); u32(e.count)
                // A SHORT value that fits sits left-justified in the 4 bytes.
                if e.type == 3 && e.count == 1 { u16(e.value); u16(0) } else if e.type == 3 && e.count * 2 <= 4 { u16(e.value); u16(0) } else { u32(e.value) }
            }
            nextIFDPointer = out.count; u32(0)
        }
        return Data(out)
    }

    static func _packBits(_ row: [UInt8]) -> [UInt8] {
        var out = [UInt8](), i = 0
        while i < row.count {
            var run = 1
            while i + run < row.count && run < 128 && row[i + run] == row[i] { run += 1 }
            if run > 1 {
                out.append(UInt8(bitPattern: Int8(1 - run))); out.append(row[i]); i += run
            } else {
                var lit = 1
                while i + lit < row.count && lit < 128 && (i + lit + 1 >= row.count || row[i + lit] != row[i + lit + 1]) { lit += 1 }
                out.append(UInt8(lit - 1)); out += row[i..<(i + lit)]; i += lit
            }
        }
        return out
    }

    // MARK: Reading (baseline: 8-bit chunky gray/RGB, none or PackBits)

    static func isTIFF(_ d: Data) -> Bool {
        d.count >= 8 && ((d[d.startIndex] == 0x4D && d[d.startIndex + 1] == 0x4D) || (d[d.startIndex] == 0x49 && d[d.startIndex + 1] == 0x49))
    }

    static func decode(_ data: Data) -> [_NSRGBAPixels] {
        let b = [UInt8](data)
        guard b.count >= 8 else { return [] }
        let big = b[0] == 0x4D
        func u16(_ o: Int) -> Int { guard o + 1 < b.count else { return 0 }; return big ? Int(b[o]) << 8 | Int(b[o + 1]) : Int(b[o + 1]) << 8 | Int(b[o]) }
        func u32(_ o: Int) -> Int { guard o + 3 < b.count else { return 0 }; return big ? (Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])) : (Int(b[o + 3]) << 24 | Int(b[o + 2]) << 16 | Int(b[o + 1]) << 8 | Int(b[o])) }
        guard u16(2) == 42 else { return [] }
        var images: [_NSRGBAPixels] = []
        var ifd = u32(4)
        var seen = Set<Int>()
        while ifd > 0, ifd + 2 < b.count, seen.insert(ifd).inserted {
            var tags: [Int: [Int]] = [:]
            let n = u16(ifd)
            for k in 0..<n {
                let e = ifd + 2 + k * 12
                let tag = u16(e), type = u16(e + 2), count = u32(e + 4)
                let size = type == 3 ? 2 : (type == 4 ? 4 : (type == 1 ? 1 : 0))
                guard size > 0 else { continue }
                let inline = size * count <= 4
                let base = inline ? e + 8 : u32(e + 8)
                tags[tag] = (0..<min(count, 1 << 20)).map { i in size == 2 ? u16(base + i * 2) : size == 4 ? u32(base + i * 4) : (base + i < b.count ? Int(b[base + i]) : 0) }
            }
            ifd = u32(ifd + 2 + n * 12)
            guard let w = tags[256]?.first, let h = tags[257]?.first, w > 0, h > 0 else { continue }
            let spp = tags[277]?.first ?? 1
            let compression = tags[259]?.first ?? 1
            let photometric = tags[262]?.first ?? 1
            guard (tags[258] ?? [8]).allSatisfy({ $0 == 8 }), (tags[284]?.first ?? 1) == 1,
                  compression == 1 || compression == 32773, photometric == 1 || photometric == 2 else { continue }
            let offsets = tags[273] ?? [], counts = tags[279] ?? []
            var raw = [UInt8]()
            for (i, o) in offsets.enumerated() {
                let c = i < counts.count ? counts[i] : b.count - o
                guard o >= 0, o + c <= b.count else { continue }
                let chunk = Array(b[o..<(o + c)])
                raw += compression == 32773 ? _unpackBits(chunk) : chunk
            }
            let colorSamples = photometric == 2 ? 3 : 1
            let hasAlpha = spp > colorSamples
            let associated = tags[338]?.first == 1
            guard raw.count >= w * h * spp else { continue }
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            for p in 0..<(w * h) {
                let s = p * spp
                var r = raw[s], g = raw[s], bl = raw[s]
                if colorSamples == 3 { g = raw[s + 1]; bl = raw[s + 2] }
                let a = hasAlpha ? raw[s + colorSamples] : 255
                if associated && a > 0 && a < 255 {
                    func un(_ v: UInt8) -> UInt8 { UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a))) }
                    r = un(r); g = un(g); bl = un(bl)
                }
                rgba[p * 4] = r; rgba[p * 4 + 1] = g; rgba[p * 4 + 2] = bl; rgba[p * 4 + 3] = a
            }
            images.append(_NSRGBAPixels(width: w, height: h, bytes: rgba, hasAlpha: hasAlpha))
        }
        return images
    }

    static func _unpackBits(_ d: [UInt8]) -> [UInt8] {
        var out = [UInt8](), i = 0
        while i < d.count {
            let n = Int(Int8(bitPattern: d[i])); i += 1
            if n >= 0 { let end = min(d.count, i + n + 1); out += d[i..<end]; i = end }
            else if n != -128, i < d.count { out += [UInt8](repeating: d[i], count: 1 - n); i += 1 }
        }
        return out
    }
}

internal enum _NSBMPCodec {
    /// A 32-bit BITMAPV4HEADER bitmap (bottom-up, BGRA with an alpha mask), which
    /// Windows' Paint and every decoder open.
    static func encode(_ p: _NSRGBAPixels, dpi: (x: Double, y: Double)) -> Data {
        var out = [UInt8]()
        func u16(_ v: Int) { out += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int) { out += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        let pixelBytes = p.width * p.height * 4, headerSize = 14 + 108
        out += [0x42, 0x4D]; u32(headerSize + pixelBytes); u32(0); u32(headerSize)
        u32(108); u32(p.width); u32(p.height); u16(1); u16(32); u32(3)   // BI_BITFIELDS
        u32(pixelBytes); u32(Int(dpi.x / 0.0254)); u32(Int(dpi.y / 0.0254)); u32(0); u32(0)
        u32(0x00FF0000); u32(0x0000FF00); u32(0x000000FF); u32(0xFF000000)
        u32(0x73524742)   // LCS_sRGB
        for _ in 0..<12 { u32(0) }   // endpoints and gamma
        for y in (0..<p.height).reversed() {
            for x in 0..<p.width {
                let i = (y * p.width + x) * 4
                out += [p.bytes[i + 2], p.bytes[i + 1], p.bytes[i], p.hasAlpha ? p.bytes[i + 3] : 255]
            }
        }
        return Data(out)
    }
}
