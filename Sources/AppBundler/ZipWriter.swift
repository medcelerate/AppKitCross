// A store-only (uncompressed) ZIP writer: the fallback when neither `zip` nor `tar -a`
// (bsdtar, in Windows 10 and later) is available. Entries keep their Unix permission bits so
// the executable stays executable after unzipping on Linux. No ZIP64: entries and the archive
// must stay under 4 GB.

import Foundation

public enum ZipWriter {
    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            for b in raw { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }

    public struct Entry {
        public var path: String          // forward slashes; directories end in "/"
        public var data: Data
        public var mode: UInt16          // Unix permission bits
        public init(path: String, data: Data, mode: UInt16) { self.path = path; self.data = data; self.mode = mode }
    }

    /// Every file and directory under `directory`, named `<prefix>/<relative path>`.
    public static func entries(of directory: URL, prefix: String) throws -> [Entry] {
        let fm = FileManager.default
        var result = [Entry(path: prefix + "/", data: Data(), mode: 0o755)]
        guard let walker = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return result }
        var items: [(String, URL, Bool)] = []
        let base = directory.standardizedFileURL.path
        for case let url as URL in walker {
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base) else { continue }
            var relative = String(full.dropFirst(base.count))
            while relative.hasPrefix("/") { relative.removeFirst() }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            items.append((relative.replacingOccurrences(of: "\\", with: "/"), url, isDirectory))
        }
        items.sort { $0.0 < $1.0 }
        for (relative, url, isDirectory) in items {
            if isDirectory {
                result.append(Entry(path: "\(prefix)/\(relative)/", data: Data(), mode: 0o755))
            } else {
                let perms = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
                result.append(Entry(path: "\(prefix)/\(relative)", data: try Data(contentsOf: url), mode: perms))
            }
        }
        return result
    }

    public static func write(_ entries: [Entry], to url: URL) throws {
        var out = Data()
        var central = Data()
        func le16(_ v: UInt16, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func le32(_ v: UInt32, _ d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        // 1980-01-01 00:00 in DOS time: reproducible archives.
        let dosTime: UInt16 = 0, dosDate: UInt16 = (0 << 9) | (1 << 5) | 1
        for e in entries {
            let name = Data(e.path.utf8)
            let crc = crc32(e.data)
            let size = UInt32(e.data.count)
            let offset = UInt32(out.count)
            let isDirectory = e.path.hasSuffix("/")
            // Local file header
            le32(0x0403_4B50, &out); le16(20, &out); le16(0x0800, &out); le16(0, &out)
            le16(dosTime, &out); le16(dosDate, &out); le32(crc, &out); le32(size, &out); le32(size, &out)
            le16(UInt16(name.count), &out); le16(0, &out); out.append(name); out.append(e.data)
            // Central directory header: made by Unix (3), version 2.0.
            le32(0x0201_4B50, &central); le16((3 << 8) | 20, &central); le16(20, &central); le16(0x0800, &central); le16(0, &central)
            le16(dosTime, &central); le16(dosDate, &central); le32(crc, &central); le32(size, &central); le32(size, &central)
            le16(UInt16(name.count), &central); le16(0, &central); le16(0, &central); le16(0, &central); le16(0, &central)
            let unixMode = UInt32((isDirectory ? 0o040000 : 0o100000) | UInt32(e.mode))
            le32((unixMode << 16) | (isDirectory ? 0x10 : 0), &central)
            le32(offset, &central); central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        le32(0x0605_4B50, &out); le16(0, &out); le16(0, &out)
        le16(UInt16(entries.count), &out); le16(UInt16(entries.count), &out)
        le32(UInt32(central.count), &out); le32(centralOffset, &out); le16(0, &out)
        try out.write(to: url)
    }

    /// The entry names in a ZIP file's central directory (tests).
    public static func listNames(_ data: Data) -> [String] {
        let r = ByteReader(data: data, name: "zip")
        var eocd = data.count - 22
        while eocd >= 0, (try? r.u32(eocd)) != 0x0605_4B50 { eocd -= 1 }
        guard eocd >= 0, let count = try? r.u16(eocd + 10), let start = try? r.u32(eocd + 16) else { return [] }
        var names: [String] = []
        var p = Int(start)
        for _ in 0..<count {
            guard let n = try? r.u16(p + 28), let x = try? r.u16(p + 30), let c = try? r.u16(p + 32) else { break }
            names.append(String(decoding: data[(data.startIndex + p + 46)..<(data.startIndex + p + 46 + Int(n))], as: UTF8.self))
            p += 46 + Int(n) + Int(x) + Int(c)
        }
        return names
    }
}
