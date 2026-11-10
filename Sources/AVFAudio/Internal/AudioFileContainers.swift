// WAV (RIFF), AIFF / AIFF-C and CAF containers for AVAudioFile: header parsing, raw PCM frame
// access and header writing. Sample decoding to Float32 lives in `_PCMCodec`.

import Foundation

/// Random-access bytes: a file handle or an in-memory Data.
protocol _ByteSource: AnyObject {
    var length: Int { get }
    func read(at offset: Int, count: Int) -> Data
}

final class _DataByteSource: _ByteSource {
    let data: Data
    init(_ data: Data) { self.data = data }
    var length: Int { data.count }
    func read(at offset: Int, count: Int) -> Data {
        guard offset < data.count, count > 0 else { return Data() }
        let end = min(data.count, offset + count)
        return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end))
    }
}

final class _FileByteSource: _ByteSource {
    let handle: FileHandle
    let length: Int
    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        length = Int(handle.seekToEndOfFile())
    }
    func read(at offset: Int, count: Int) -> Data {
        guard offset < length, count > 0 else { return Data() }
        handle.seek(toFileOffset: UInt64(offset))
        return handle.readData(ofLength: min(count, length - offset))
    }
    func close() { handle.closeFile() }
}

/// The sample encoding of a container's data chunk.
struct _PCMEncoding: Equatable {
    var bitsPerSample: Int
    var isFloat: Bool
    var isBigEndian: Bool
    var isSigned: Bool          // 8-bit WAV is unsigned
    var channels: Int
    var sampleRate: Double
    var bytesPerSample: Int { (bitsPerSample + 7) / 8 }
    var bytesPerFrame: Int { bytesPerSample * channels }

    var asbd: AudioStreamBasicDescription {
        var d = AudioStreamBasicDescription()
        d.mSampleRate = sampleRate
        d.mFormatID = kAudioFormatLinearPCM
        d.mFormatFlags = (isFloat ? kAudioFormatFlagIsFloat : (isSigned ? kAudioFormatFlagIsSignedInteger : 0)) | kAudioFormatFlagIsPacked
        if isBigEndian { d.mFormatFlags |= kAudioFormatFlagIsBigEndian }
        d.mBitsPerChannel = UInt32(bitsPerSample)
        d.mChannelsPerFrame = UInt32(channels)
        d.mFramesPerPacket = 1
        d.mBytesPerFrame = UInt32(bytesPerFrame)
        d.mBytesPerPacket = d.mBytesPerFrame
        return d
    }
}

enum _ContainerKind { case wave, aiff, aifc, caf }

/// A parsed container: where the frames are and how they are encoded.
struct _ContainerInfo {
    var kind: _ContainerKind
    var encoding: _PCMEncoding
    var dataOffset: Int
    var frameCount: Int
}

enum _ContainerError: Error {
    case unsupportedType, unsupportedFormat, invalid(String)
    var status: OSStatus {
        switch self {
        case .unsupportedType: return kAudioFileUnsupportedFileTypeError
        case .unsupportedFormat: return kAudioFileUnsupportedDataFormatError
        case .invalid: return kAudioFileInvalidFileError
        }
    }
    var message: String {
        switch self {
        case .unsupportedType: return "unsupported file type"
        case .unsupportedFormat: return "unsupported data format"
        case .invalid(let s): return "invalid file: \(s)"
        }
    }
}

private extension Data {
    func u16LE(_ o: Int) -> UInt16 { UInt16(self[startIndex + o]) | UInt16(self[startIndex + o + 1]) << 8 }
    func u32LE(_ o: Int) -> UInt32 { UInt32(u16LE(o)) | UInt32(u16LE(o + 2)) << 16 }
    func u16BE(_ o: Int) -> UInt16 { UInt16(self[startIndex + o]) << 8 | UInt16(self[startIndex + o + 1]) }
    func u32BE(_ o: Int) -> UInt32 { UInt32(u16BE(o)) << 16 | UInt32(u16BE(o + 2)) }
    func fourCC(_ o: Int) -> String { String(decoding: self[(startIndex + o)..<(startIndex + o + 4)], as: UTF8.self) }
    func u64BE(_ o: Int) -> UInt64 { UInt64(u32BE(o)) << 32 | UInt64(u32BE(o + 4)) }
}

enum _Containers {
    /// Sniffs the container and parses its header.
    static func parse(_ source: _ByteSource) throws -> _ContainerInfo {
        let head = source.read(at: 0, count: 12)
        guard head.count == 12 else { throw _ContainerError.unsupportedType }
        if head.fourCC(0) == "RIFF" && head.fourCC(8) == "WAVE" { return try parseWave(source) }
        if head.fourCC(0) == "FORM" && (head.fourCC(8) == "AIFF" || head.fourCC(8) == "AIFC") { return try parseAIFF(source, aifc: head.fourCC(8) == "AIFC") }
        if head.fourCC(0) == "caff" { return try parseCAF(source) }
        throw _ContainerError.unsupportedType
    }

    private static func parseWave(_ source: _ByteSource) throws -> _ContainerInfo {
        var offset = 12
        var encoding: _PCMEncoding?
        var dataOffset = -1, dataSize = 0
        while offset + 8 <= source.length {
            let h = source.read(at: offset, count: 8)
            guard h.count == 8 else { break }
            let id = h.fourCC(0)
            var size = Int(h.u32LE(4))
            let body = offset + 8
            if id == "fmt " {
                let f = source.read(at: body, count: min(size, 40))
                guard f.count >= 16 else { throw _ContainerError.invalid("short fmt chunk") }
                var tag = Int(f.u16LE(0))
                let channels = Int(f.u16LE(2))
                let rate = Double(f.u32LE(4))
                let bits = Int(f.u16LE(14))
                if tag == 0xFFFE {
                    guard f.count >= 40 else { throw _ContainerError.invalid("short extensible fmt chunk") }
                    tag = Int(f.u16LE(24))       // first two bytes of the sub-format GUID
                }
                guard tag == 1 || tag == 3 else { throw _ContainerError.unsupportedFormat }
                guard channels > 0, rate > 0, bits >= 8, bits <= 64, bits % 8 == 0 else { throw _ContainerError.unsupportedFormat }
                if tag == 3 && bits != 32 && bits != 64 { throw _ContainerError.unsupportedFormat }
                encoding = _PCMEncoding(bitsPerSample: bits, isFloat: tag == 3, isBigEndian: false, isSigned: bits > 8, channels: channels, sampleRate: rate)
            } else if id == "data" {
                dataOffset = body
                if size == 0xFFFFFFFF || body + size > source.length { size = source.length - body }
                dataSize = size
            }
            offset = body + size + (size & 1)
        }
        guard let enc = encoding else { throw _ContainerError.invalid("no fmt chunk") }
        guard dataOffset >= 0 else { throw _ContainerError.invalid("no data chunk") }
        return _ContainerInfo(kind: .wave, encoding: enc, dataOffset: dataOffset, frameCount: dataSize / enc.bytesPerFrame)
    }

    private static func parseAIFF(_ source: _ByteSource, aifc: Bool) throws -> _ContainerInfo {
        var offset = 12
        var encoding: _PCMEncoding?
        var frames = 0
        var dataOffset = -1, dataSize = 0
        while offset + 8 <= source.length {
            let h = source.read(at: offset, count: 8)
            guard h.count == 8 else { break }
            let id = h.fourCC(0)
            let size = Int(h.u32BE(4))
            let body = offset + 8
            if id == "COMM" {
                let c = source.read(at: body, count: min(size, 30))
                guard c.count >= 18 else { throw _ContainerError.invalid("short COMM chunk") }
                let channels = Int(c.u16BE(0))
                frames = Int(c.u32BE(2))
                let bits = Int(c.u16BE(6))
                let rate = _extendedToDouble(c, at: 8)
                var isFloat = false, bigEndian = true
                if aifc {
                    guard c.count >= 22 else { throw _ContainerError.invalid("short AIFC COMM chunk") }
                    switch c.fourCC(18) {
                    case "NONE", "twos": break
                    case "sowt": bigEndian = false
                    case "fl32", "FL32": isFloat = true
                    case "fl64", "FL64": isFloat = true
                    default: throw _ContainerError.unsupportedFormat
                    }
                }
                guard channels > 0, rate > 0, bits >= 8, bits <= 64 else { throw _ContainerError.unsupportedFormat }
                let storedBits = ((bits + 7) / 8) * 8
                encoding = _PCMEncoding(bitsPerSample: storedBits, isFloat: isFloat, isBigEndian: bigEndian, isSigned: true, channels: channels, sampleRate: rate)
            } else if id == "SSND" {
                let s = source.read(at: body, count: 8)
                guard s.count == 8 else { throw _ContainerError.invalid("short SSND chunk") }
                let skip = Int(s.u32BE(0))
                dataOffset = body + 8 + skip
                dataSize = min(size - 8 - skip, source.length - dataOffset)
            }
            offset = body + size + (size & 1)
        }
        guard let enc = encoding else { throw _ContainerError.invalid("no COMM chunk") }
        guard dataOffset >= 0 else { throw _ContainerError.invalid("no SSND chunk") }
        let available = dataSize / enc.bytesPerFrame
        return _ContainerInfo(kind: aifc ? .aifc : .aiff, encoding: enc, dataOffset: dataOffset, frameCount: min(frames, available))
    }

    /// Core Audio Format: big-endian chunks with 64-bit sizes; `desc` describes linear PCM
    /// (kCAFLinearPCMFormatFlagIsFloat = 1, IsLittleEndian = 2), `data` starts with a
    /// 4-byte edit count and may have size -1 (to the end of the file).
    private static func parseCAF(_ source: _ByteSource) throws -> _ContainerInfo {
        var offset = 8
        var encoding: _PCMEncoding?
        var dataOffset = -1, dataSize = 0
        while offset + 12 <= source.length {
            let h = source.read(at: offset, count: 12)
            guard h.count == 12 else { break }
            let id = h.fourCC(0)
            let rawSize = Int64(bitPattern: h.u64BE(4))
            let body = offset + 12
            var size = rawSize < 0 ? source.length - body : Int(min(rawSize, Int64(source.length - body)))
            if id == "desc" {
                let d = source.read(at: body, count: 32)
                guard d.count == 32 else { throw _ContainerError.invalid("short desc chunk") }
                let rate = Double(bitPattern: d.u64BE(0))
                guard d.fourCC(8) == "lpcm" else { throw _ContainerError.unsupportedFormat }
                let flags = d.u32BE(12)
                let channels = Int(d.u32BE(24)), bits = Int(d.u32BE(28))
                let isFloat = flags & 1 != 0
                guard channels > 0, rate > 0, bits >= 8, bits <= 64, bits % 8 == 0, !isFloat || bits == 32 || bits == 64 else { throw _ContainerError.unsupportedFormat }
                encoding = _PCMEncoding(bitsPerSample: bits, isFloat: isFloat, isBigEndian: flags & 2 == 0, isSigned: true, channels: channels, sampleRate: rate)
            } else if id == "data" {
                dataOffset = body + 4
                dataSize = max(0, size - 4)
                if rawSize < 0 { size = source.length - body }
            }
            offset = body + size
        }
        guard let enc = encoding else { throw _ContainerError.invalid("no desc chunk") }
        guard dataOffset >= 0 else { throw _ContainerError.invalid("no data chunk") }
        return _ContainerInfo(kind: .caf, encoding: enc, dataOffset: dataOffset, frameCount: dataSize / enc.bytesPerFrame)
    }

    /// The 80-bit IEEE 754 extended used by AIFF for the sample rate.
    static func _extendedToDouble(_ d: Data, at o: Int) -> Double {
        let exponent = Int(d.u16BE(o) & 0x7FFF)
        let negative = d[d.startIndex + o] & 0x80 != 0
        let mantissaHi = UInt64(d.u32BE(o + 2)), mantissaLo = UInt64(d.u32BE(o + 6))
        let mantissa = mantissaHi << 32 | mantissaLo
        if exponent == 0 && mantissa == 0 { return 0 }
        let value = Double(mantissa) * pow(2, Double(exponent - 16383 - 63))
        return negative ? -value : value
    }

    static func _doubleToExtended(_ v: Double) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 10)
        guard v != 0 else { return bytes }
        var value = abs(v)
        var exponent = 16383 + 63
        while value >= 2 * 9223372036854775808.0 { value /= 2; exponent += 1 }
        while value < 9223372036854775808.0 { value *= 2; exponent -= 1 }
        let mantissa = UInt64(value)
        bytes[0] = UInt8(exponent >> 8) | (v < 0 ? 0x80 : 0)
        bytes[1] = UInt8(exponent & 0xFF)
        for i in 0..<8 { bytes[2 + i] = UInt8((mantissa >> (56 - 8 * i)) & 0xFF) }
        return bytes
    }

    /// The header for a new file of `kind`; `frameCount` is patched on close.
    static func header(kind: _ContainerKind, encoding e: _PCMEncoding, frameCount: Int) -> Data {
        var d = Data()
        func le16(_ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8(v >> 8 & 0xFF)) }
        func le32(_ v: Int) { le16(v & 0xFFFF); le16(v >> 16 & 0xFFFF) }
        func be16(_ v: Int) { d.append(UInt8(v >> 8 & 0xFF)); d.append(UInt8(v & 0xFF)) }
        func be32(_ v: Int) { be16(v >> 16 & 0xFFFF); be16(v & 0xFFFF) }
        func cc(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        let dataBytes = frameCount * e.bytesPerFrame
        switch kind {
        case .wave:
            let extensible = e.channels > 2 || (!e.isFloat && e.bitsPerSample > 16)
            let fmtSize = extensible ? 40 : 16
            cc("RIFF"); le32(4 + 8 + fmtSize + 8 + dataBytes); cc("WAVE")
            cc("fmt "); le32(fmtSize)
            le16(extensible ? 0xFFFE : (e.isFloat ? 3 : 1)); le16(e.channels); le32(Int(e.sampleRate))
            le32(Int(e.sampleRate) * e.bytesPerFrame); le16(e.bytesPerFrame); le16(e.bitsPerSample)
            if extensible {
                le16(22); le16(e.bitsPerSample)
                le32(e.channels == 1 ? 0x4 : (e.channels == 2 ? 0x3 : 0))
                le16(e.isFloat ? 3 : 1); le16(0x0000)
                // The rest of KSDATAFORMAT_SUBTYPE_PCM / IEEE_FLOAT: 00000010-8000-00aa00389b71.
                d.append(contentsOf: [0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71])
            }
            cc("data"); le32(dataBytes)
        case .aiff, .aifc:
            let commSize = kind == .aifc ? 18 + 4 + 2 : 18
            let commPadded = commSize + (commSize & 1)
            let fverSize = kind == .aifc ? 12 : 0
            cc("FORM"); be32(4 + fverSize + 8 + commPadded + 8 + 8 + dataBytes); cc(kind == .aifc ? "AIFC" : "AIFF")
            if kind == .aifc { cc("FVER"); be32(4); be32(0xA2805140) }
            cc("COMM"); be32(commSize)
            be16(e.channels); be32(frameCount); be16(e.bitsPerSample)
            d.append(contentsOf: _doubleToExtended(e.sampleRate))
            if kind == .aifc {
                cc(e.isFloat ? (e.bitsPerSample == 64 ? "fl64" : "fl32") : (e.isBigEndian ? "NONE" : "sowt"))
                be16(0)
            }
            if commSize & 1 == 1 { d.append(0) }
            cc("SSND"); be32(8 + dataBytes); be32(0); be32(0)
        case .caf:
            func be64(_ v: Int64) { be32(Int(UInt64(bitPattern: v) >> 32 & 0xFFFF_FFFF)); be32(Int(UInt64(bitPattern: v) & 0xFFFF_FFFF)) }
            cc("caff"); be16(1); be16(0)
            cc("desc"); be64(32)
            be64(Int64(bitPattern: e.sampleRate.bitPattern))
            cc("lpcm")
            be32((e.isFloat ? 1 : 0) | (e.isBigEndian ? 0 : 2))
            be32(e.bytesPerFrame); be32(1); be32(e.channels); be32(e.bitsPerSample)
            cc("data"); be64(Int64(4 + dataBytes)); be32(0)
        }
        return d
    }

    /// Offsets of the size fields `header` wrote, for patching when the file closes.
    static func sizePatches(kind: _ContainerKind, encoding e: _PCMEncoding, header: Data) -> [(offset: Int, bigEndian: Bool, isFrameCount: Bool, base: Int)] {
        let dataSizeOffset = header.count - 4
        switch kind {
        case .wave:
            return [(4, false, false, header.count - 8), (dataSizeOffset, false, false, 0)]
        case .aiff, .aifc:
            let commBody = kind == .aifc ? 12 + 12 + 8 : 12 + 8
            return [(4, true, false, header.count - 8), (commBody + 2, true, true, 0), (header.count - 12, true, false, 8)]
        case .caf:
            // The low word of the data chunk's 64-bit size (the high word is zero below 4 GB).
            return [(header.count - 8, true, false, 4)]
        }
    }
}

/// Sample decoding and encoding between a container's PCM bytes and Float32.
enum _PCMCodec {
    /// Decodes `frames` frames of interleaved bytes into planar floats (`out[channel]`).
    static func decode(_ bytes: UnsafeRawPointer, frames: Int, encoding e: _PCMEncoding, into out: UnsafeMutablePointer<UnsafeMutablePointer<Float>>, outOffset: Int) {
        let bps = e.bytesPerSample, ch = e.channels
        let p = bytes.assumingMemoryBound(to: UInt8.self)
        for f in 0..<frames {
            for c in 0..<ch {
                let o = (f * ch + c) * bps
                let v: Float
                switch (e.isFloat, e.bitsPerSample) {
                case (true, 32):
                    let bits = e.isBigEndian ? UInt32(p[o]) << 24 | UInt32(p[o + 1]) << 16 | UInt32(p[o + 2]) << 8 | UInt32(p[o + 3])
                                             : UInt32(p[o + 3]) << 24 | UInt32(p[o + 2]) << 16 | UInt32(p[o + 1]) << 8 | UInt32(p[o])
                    v = Float(bitPattern: bits)
                case (true, 64):
                    var bits: UInt64 = 0
                    for i in 0..<8 { bits = bits << 8 | UInt64(p[o + (e.isBigEndian ? i : 7 - i)]) }
                    v = Float(Double(bitPattern: bits))
                case (false, 8):
                    v = e.isSigned ? Float(Int8(bitPattern: p[o])) / 128 : (Float(p[o]) - 128) / 128
                case (false, 16):
                    let u = e.isBigEndian ? UInt16(p[o]) << 8 | UInt16(p[o + 1]) : UInt16(p[o + 1]) << 8 | UInt16(p[o])
                    v = Float(Int16(bitPattern: u)) / 32768
                case (false, 24):
                    let u = e.isBigEndian ? UInt32(p[o]) << 24 | UInt32(p[o + 1]) << 16 | UInt32(p[o + 2]) << 8
                                          : UInt32(p[o + 2]) << 24 | UInt32(p[o + 1]) << 16 | UInt32(p[o]) << 8
                    v = Float(Double(Int32(bitPattern: u)) / 2147483648)
                case (false, 32):
                    let u = e.isBigEndian ? UInt32(p[o]) << 24 | UInt32(p[o + 1]) << 16 | UInt32(p[o + 2]) << 8 | UInt32(p[o + 3])
                                          : UInt32(p[o + 3]) << 24 | UInt32(p[o + 2]) << 16 | UInt32(p[o + 1]) << 8 | UInt32(p[o])
                    v = Float(Double(Int32(bitPattern: u)) / 2147483648)
                default:
                    v = 0
                }
                out[c][outOffset + f] = v
            }
        }
    }

    /// Encodes planar floats into interleaved container bytes.
    static func encode(_ src: UnsafePointer<UnsafeMutablePointer<Float>>, srcOffset: Int, frames: Int, encoding e: _PCMEncoding, into out: UnsafeMutableRawPointer) {
        let bps = e.bytesPerSample, ch = e.channels
        let p = out.assumingMemoryBound(to: UInt8.self)
        for f in 0..<frames {
            for c in 0..<ch {
                let o = (f * ch + c) * bps
                let x = src[c][srcOffset + f]
                switch (e.isFloat, e.bitsPerSample) {
                case (true, 32):
                    let bits = x.bitPattern
                    for i in 0..<4 { p[o + i] = UInt8((bits >> (e.isBigEndian ? 24 - 8 * i : 8 * i)) & 0xFF) }
                case (true, 64):
                    let bits = Double(x).bitPattern
                    for i in 0..<8 { p[o + i] = UInt8((bits >> (e.isBigEndian ? 56 - 8 * i : 8 * i)) & 0xFF) }
                case (false, 8):
                    let v = max(-128, min(127, (x * 128).rounded()))
                    p[o] = e.isSigned ? UInt8(bitPattern: Int8(v)) : UInt8(Int(v) + 128)
                case (false, 16):
                    let u = UInt16(bitPattern: _floatToInt16(x))
                    if e.isBigEndian { p[o] = UInt8(u >> 8); p[o + 1] = UInt8(u & 0xFF) } else { p[o] = UInt8(u & 0xFF); p[o + 1] = UInt8(u >> 8) }
                case (false, 24):
                    let v = Double(x) * 8388608
                    let i = Int32(max(-8388608, min(8388607, v.rounded())))
                    let u = UInt32(bitPattern: i)
                    if e.isBigEndian { p[o] = UInt8(u >> 16 & 0xFF); p[o + 1] = UInt8(u >> 8 & 0xFF); p[o + 2] = UInt8(u & 0xFF) }
                    else { p[o] = UInt8(u & 0xFF); p[o + 1] = UInt8(u >> 8 & 0xFF); p[o + 2] = UInt8(u >> 16 & 0xFF) }
                case (false, 32):
                    let u = UInt32(bitPattern: _floatToInt32(x))
                    for i in 0..<4 { p[o + i] = UInt8((u >> (e.isBigEndian ? 24 - 8 * i : 8 * i)) & 0xFF) }
                default: break
                }
            }
        }
    }
}
