// System clipboard through the Win32 clipboard API (CF_UNICODETEXT plus registered
// formats for other pasteboard types).

#if os(Windows)
import Foundation
import WinSDK

@MainActor
final class Win32Pasteboard: PlatformPasteboard {
    private static let textType = "public.utf8-plain-text"
    private var formats: [String: UINT] = [:]

    private func format(for type: String) -> UINT {
        if type == Win32Pasteboard.textType { return UINT(CF_UNICODETEXT) }
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
        for (type, f) in formats where IsClipboardFormatAvailable(f) {
            guard let h = GetClipboardData(f), let p = GlobalLock(h) else { continue }
            let size = Int(GlobalSize(h))
            result.append(PlatformPasteboardEntry(type: type, data: Data(bytes: p, count: size)))
            GlobalUnlock(h)
        }
        return result
    }
}
#endif
