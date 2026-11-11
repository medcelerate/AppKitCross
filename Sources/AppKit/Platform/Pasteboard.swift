// Pasteboard seam: the general pasteboard is the system clipboard; other named
// pasteboards stay in-process.

import Foundation

/// One clipboard entry: a type identifier (AppKit pasteboard type UTI) and its bytes.
public struct PlatformPasteboardEntry: Sendable, Equatable {
    public var type: String
    public var data: Data
    public init(type: String, data: Data) { self.type = type; self.data = data }
}

@MainActor
public protocol PlatformPasteboard: AnyObject {
    /// Replaces the clipboard contents.
    func write(_ entries: [PlatformPasteboardEntry])
    /// Reads every entry the platform can express as an AppKit type.
    func read() -> [PlatformPasteboardEntry]
    /// Increments whenever the contents change (from this or other applications).
    var changeCount: Int { get }
}

/// Clipboard bitmap helpers shared by the platform pasteboards (ADR-0030).
enum PlatformClipboardImage {
    /// The pasteboard type a bitmap read from the system clipboard arrives as.
    static let bmpType = "com.microsoft.bmp"

    /// A BMP file for a packed DIB (CF_DIB / CF_DIBV5: a BITMAPINFOHEADER or V4/V5 header,
    /// then masks or colour table, then the pixels): the 14-byte file header in front.
    static func bmpFile(fromDIB dib: Data) -> Data? {
        let b = [UInt8](dib)
        guard b.count >= 40 else { return nil }
        func u32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        let headerSize = u32(0)
        guard headerSize >= 40, headerSize <= b.count else { return nil }
        let bitCount = u16(14), compression = u32(16), colorsUsed = u32(32)
        let palette = (colorsUsed != 0 ? colorsUsed : (bitCount <= 8 ? 1 << bitCount : 0)) * 4
        // BI_BITFIELDS (3) / BI_ALPHABITFIELDS (6) after a plain 40-byte header carry their masks.
        let masks = headerSize == 40 ? (compression == 3 ? 12 : compression == 6 ? 16 : 0) : 0
        let offset = 14 + headerSize + masks + palette
        let fileSize = 14 + b.count
        guard offset <= fileSize else { return nil }
        var out = Data([0x42, 0x4D])
        for v in [fileSize, 0, offset] { out.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]) }
        out.append(dib)
        return out
    }
}
