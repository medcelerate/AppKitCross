// System clipboard through the Win32 clipboard API (CF_UNICODETEXT plus registered
// formats for other pasteboard types).

#if os(Windows)
import Foundation
import WinSDK

@MainActor
final class Win32Pasteboard: PlatformPasteboard {
    private static let textType = "public.utf8-plain-text"
    private var formats: [String: UINT] = [:]

    /// Types other Windows applications exchange under their own registered names.
    private static let standardNames = ["public.png": "PNG", "public.rtf": "Rich Text Format"]
    private static func registered(_ name: String) -> UINT { name.withCString(encodedAs: UTF16.self) { RegisterClipboardFormatW($0) } }

    private func format(for type: String) -> UINT {
        if type == Win32Pasteboard.textType { return UINT(CF_UNICODETEXT) }
        if let name = Win32Pasteboard.standardNames[type] { return Win32Pasteboard.registered(name) }
        if let f = formats[type] { return f }
        let f = ("AppKitCross:" + type).withCString(encodedAs: UTF16.self) { RegisterClipboardFormatW($0) }
        formats[type] = f
        return f
    }

    var changeCount: Int { Int(GetClipboardSequenceNumber()) }

    func write(_ entries: [PlatformPasteboardEntry]) {
        guard OpenClipboard(nil) else { return }
        defer { CloseClipboard() }
        EmptyClipboard()
        for e in entries {
            let bytes: [UInt8]
            if e.type == Win32Pasteboard.textType {
                let text = String(decoding: e.data, as: UTF8.self)
                var u = Array(text.utf16); u.append(0)
                bytes = u.withUnsafeBytes { Array($0) }
            } else {
                bytes = [UInt8](e.data)
            }
            guard let h = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(max(1, bytes.count))), let p = GlobalLock(h) else { continue }
            bytes.withUnsafeBytes { src in p.copyMemory(from: src.baseAddress!, byteCount: bytes.count) }
            GlobalUnlock(h)
            if SetClipboardData(format(for: e.type), h) == nil { GlobalFree(h) }
        }
    }

    func read() -> [PlatformPasteboardEntry] {
        guard OpenClipboard(nil) else { return [] }
        defer { CloseClipboard() }
        var result: [PlatformPasteboardEntry] = []
        if IsClipboardFormatAvailable(UINT(CF_UNICODETEXT)), let h = GetClipboardData(UINT(CF_UNICODETEXT)), let p = GlobalLock(h) {
            let text = String(decodingCString: p.assumingMemoryBound(to: UInt16.self), as: UTF16.self)
            GlobalUnlock(h)
            result.append(PlatformPasteboardEntry(type: Win32Pasteboard.textType, data: Data(text.utf8)))
        }
        func data(_ f: UINT) -> Data? {
            guard IsClipboardFormatAvailable(f), let h = GetClipboardData(f), let p = GlobalLock(h) else { return nil }
            defer { GlobalUnlock(h) }
            return Data(bytes: p, count: Int(GlobalSize(h)))
        }
        for (type, f) in formats {
            if let d = data(f) { result.append(PlatformPasteboardEntry(type: type, data: d)) }
        }
        // What other applications put there: PNG and RTF by their registered names, and a
        // bitmap (CF_DIBV5 / CF_DIB, which Windows synthesises from CF_BITMAP) as a BMP file.
        for (type, name) in Win32Pasteboard.standardNames where !result.contains(where: { $0.type == type }) {
            if var d = data(Win32Pasteboard.registered(name)) {
                if type == "public.rtf", let nul = d.firstIndex(of: 0) { d = d.prefix(upTo: nul) }
                result.append(PlatformPasteboardEntry(type: type, data: d))
            }
        }
        if !result.contains(where: { $0.type == "public.png" || $0.type == PlatformClipboardImage.bmpType }),
           let dib = data(UINT(CF_DIBV5)) ?? data(UINT(CF_DIB)), let bmp = PlatformClipboardImage.bmpFile(fromDIB: dib) {
            result.append(PlatformPasteboardEntry(type: PlatformClipboardImage.bmpType, data: bmp))
        }
        return result
    }
}
#endif
