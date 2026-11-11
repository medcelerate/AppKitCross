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
        guard openClipboard() else { return }
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

    /// Another process (a clipboard manager, Windows clipboard history, the application
    /// that just copied) often holds the clipboard open for a moment after a change.
    private func openClipboard() -> Bool {
        for attempt in 0..<20 {
            if OpenClipboard(nil) { return true }
            Sleep(DWORD(attempt < 5 ? 2 : 10))
        }
        return false
    }

    /// Whether the last read could not open the clipboard; NSPasteboard reads again then.
    private(set) var lastReadFailed = false

    func read() -> [PlatformPasteboardEntry] {
        guard openClipboard() else {
            lastReadFailed = true
            _PasteboardTrace.log("Win32 read: OpenClipboard failed after retries (error \(GetLastError()))")
            return []
        }
        lastReadFailed = false
        defer { CloseClipboard() }
        if _PasteboardTrace.enabled {
            var names: [String] = []
            var f = EnumClipboardFormats(0)
            while f != 0 {
                var buf = [WCHAR](repeating: 0, count: 128)
                let n = GetClipboardFormatNameW(f, &buf, Int32(buf.count))
                names.append(n > 0 ? "\(f) \(String(decoding: buf[0..<Int(n)], as: UTF16.self))" : "\(f)")
                f = EnumClipboardFormats(f)
            }
            _PasteboardTrace.log("Win32 read: sequence \(GetClipboardSequenceNumber()), owner \(String(describing: GetClipboardOwner())), formats: [\(names.joined(separator: ", "))]")
        }
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
        // bitmap (CF_DIB / CF_DIBV5, which Windows synthesises from CF_BITMAP, or CF_BITMAP
        // itself) as a BMP file.
        for (type, name) in Win32Pasteboard.standardNames where !result.contains(where: { $0.type == type }) {
            if var d = data(Win32Pasteboard.registered(name)) {
                if type == "public.rtf", let nul = d.firstIndex(of: 0) { d = d.prefix(upTo: nul) }
                result.append(PlatformPasteboardEntry(type: type, data: d))
            }
        }
        if !result.contains(where: { $0.type == "public.png" || $0.type == PlatformClipboardImage.bmpType }) {
            let bmp = data(UINT(CF_DIB)).flatMap(PlatformClipboardImage.bmpFile(fromDIB:))
                ?? data(UINT(CF_DIBV5)).flatMap(PlatformClipboardImage.bmpFile(fromDIB:))
                ?? Win32Pasteboard.dibFromBitmap().flatMap(PlatformClipboardImage.bmpFile(fromDIB:))
            if let bmp { result.append(PlatformPasteboardEntry(type: PlatformClipboardImage.bmpType, data: bmp)) }
            if _PasteboardTrace.enabled {
                _PasteboardTrace.log("Win32 read: bitmap: CF_DIB \(data(UINT(CF_DIB))?.count ?? -1) bytes, CF_DIBV5 \(data(UINT(CF_DIBV5))?.count ?? -1) bytes, CF_BITMAP available \(IsClipboardFormatAvailable(UINT(CF_BITMAP))), BMP \(bmp?.count ?? -1) bytes")
            }
        }
        _PasteboardTrace.log("Win32 read: resolved \(result.map { "\($0.type) (\($0.data.count) bytes)" })")
        return result
    }

    /// A 32-bit top-down DIB of the clipboard's CF_BITMAP, for when Windows does not
    /// synthesise CF_DIB (the clipboard must be open).
    private static func dibFromBitmap() -> Data? {
        guard IsClipboardFormatAvailable(UINT(CF_BITMAP)), let h = GetClipboardData(UINT(CF_BITMAP)) else { return nil }
        let hbm = HBITMAP(OpaquePointer(h))
        var bm = BITMAP()
        guard GetObjectW(HGDIOBJ(hbm), Int32(MemoryLayout<BITMAP>.size), &bm) != 0, bm.bmWidth > 0, bm.bmHeight > 0 else { return nil }
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = bm.bmWidth
        info.bmiHeader.biHeight = bm.bmHeight
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        let pixelBytes = Int(bm.bmWidth) * Int(bm.bmHeight) * 4
        var pixels = [UInt8](repeating: 0, count: pixelBytes)
        guard let dc = GetDC(nil) else { return nil }
        defer { ReleaseDC(nil, dc) }
        let lines = pixels.withUnsafeMutableBytes { GetDIBits(dc, hbm, 0, UINT(bm.bmHeight), $0.baseAddress, &info, UINT(DIB_RGB_COLORS)) }
        guard lines > 0 else { return nil }
        var header = info.bmiHeader
        header.biSizeImage = DWORD(pixelBytes)
        var out = withUnsafeBytes(of: &header) { Data($0) }
        out.append(contentsOf: pixels)
        return out
    }
}
#endif
