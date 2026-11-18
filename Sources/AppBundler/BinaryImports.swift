// Reading which shared libraries a binary loads, without the platform's tools: the import
// and delay-import tables of a Windows PE file, and the DT_NEEDED / DT_RUNPATH entries of an
// ELF file. The bundler walks these from the executable to collect every DLL or .so the app
// needs (ADR-0046).

import Foundation

public enum BinaryFormatError: Error, CustomStringConvertible {
    case notPE(String)
    case notELF(String)
    case truncated(String)

    public var description: String {
        switch self {
        case .notPE(let s): return "not a PE file: \(s)"
        case .notELF(let s): return "not a 64-bit little-endian ELF file: \(s)"
        case .truncated(let s): return "truncated or malformed: \(s)"
        }
    }
}

struct ByteReader {
    let data: Data
    let name: String

    func u16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { throw BinaryFormatError.truncated(name) }
        return data.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
    }
    func u32(_ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw BinaryFormatError.truncated(name) }
        return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }
    func u64(_ offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else { throw BinaryFormatError.truncated(name) }
        return data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
    }
    /// A NUL-terminated string at `offset`.
    func cString(_ offset: Int) throws -> String {
        guard offset >= 0, offset < data.count else { throw BinaryFormatError.truncated(name) }
        var end = offset
        while end < data.count, data[data.startIndex + end] != 0 { end += 1 }
        return String(decoding: data[(data.startIndex + offset)..<(data.startIndex + end)], as: UTF8.self)
    }
}

/// The DLLs a PE image imports, in table order: the import table, then the delay-load table.
public func peImportedLibraries(_ data: Data, name: String = "image") throws -> [String] {
    let r = ByteReader(data: data, name: name)
    guard data.count > 0x40, try r.u16(0) == 0x5A4D else { throw BinaryFormatError.notPE(name) }
    let pe = Int(try r.u32(0x3C))
    guard try r.u32(pe) == 0x0000_4550 else { throw BinaryFormatError.notPE(name) }
    let sectionCount = Int(try r.u16(pe + 6))
    let optionalSize = Int(try r.u16(pe + 20))
    let optional = pe + 24
    let magic = try r.u16(optional)
    let directories: Int, directoryCount: Int, imageBase: UInt64
    switch magic {
    case 0x10B: // PE32
        imageBase = UInt64(try r.u32(optional + 28))
        directoryCount = Int(try r.u32(optional + 92))
        directories = optional + 96
    case 0x20B: // PE32+
        imageBase = try r.u64(optional + 24)
        directoryCount = Int(try r.u32(optional + 108))
        directories = optional + 112
    default:
        throw BinaryFormatError.notPE("\(name) (optional header magic \(String(magic, radix: 16)))")
    }
    struct Section { let va: UInt32; let size: UInt32; let raw: UInt32; let rawSize: UInt32 }
    var sections: [Section] = []
    let table = optional + optionalSize
    for i in 0..<sectionCount {
        let s = table + i * 40
        sections.append(Section(va: try r.u32(s + 12), size: try r.u32(s + 8), raw: try r.u32(s + 20), rawSize: try r.u32(s + 16)))
    }
    func offset(_ rva: UInt32) -> Int? {
        for s in sections where rva >= s.va && rva < s.va &+ max(s.size, s.rawSize) {
            return Int(rva - s.va) + Int(s.raw)
        }
        return nil
    }
    func directory(_ index: Int) throws -> UInt32? {
        guard index < directoryCount else { return nil }
        let rva = try r.u32(directories + index * 8)
        return rva == 0 ? nil : rva
    }

    var names: [String] = []
    if let rva = try directory(1), var entry = offset(rva) {
        // IMAGE_IMPORT_DESCRIPTOR: 20 bytes, Name at +12; an all-zero entry ends the table.
        while entry + 20 <= data.count {
            let nameRVA = try r.u32(entry + 12)
            if nameRVA == 0, try r.u32(entry) == 0, try r.u32(entry + 16) == 0 { break }
            if let at = offset(nameRVA) { names.append(try r.cString(at)) }
            entry += 20
        }
    }
    if let rva = try directory(13), var entry = offset(rva) {
        // ImgDelayDescr: 32 bytes, Attributes at +0 (bit 0: RVAs, else VAs), DllNameRVA at +4.
        while entry + 32 <= data.count {
            let attributes = try r.u32(entry)
            let raw = try r.u32(entry + 4)
            if raw == 0 { break }
            let nameRVA = attributes & 1 == 1 ? raw : UInt32(truncatingIfNeeded: UInt64(raw) &- imageBase)
            if let at = offset(nameRVA) { names.append(try r.cString(at)) }
            entry += 32
        }
    }
    return names
}

/// The dynamic section of a 64-bit little-endian ELF file: the sonames it needs, in order,
/// and its DT_RUNPATH (or DT_RPATH) when it has one.
public struct ELFDynamicInfo: Equatable, Sendable {
    public var needed: [String]
    public var runpath: String?
    public var soname: String?
}

public func elfDynamicInfo(_ data: Data, name: String = "image") throws -> ELFDynamicInfo {
    let r = ByteReader(data: data, name: name)
    guard data.count >= 64, try r.u32(0) == 0x464C_457F, data[data.startIndex + 4] == 2, data[data.startIndex + 5] == 1 else {
        throw BinaryFormatError.notELF(name)
    }
    let phoff = Int(try r.u64(0x20))
    let phentsize = Int(try r.u16(0x36))
    let phnum = Int(try r.u16(0x38))
    struct Load { let vaddr: UInt64; let offset: UInt64; let size: UInt64 }
    var loads: [Load] = []
    var dynamic: (offset: Int, size: Int)?
    for i in 0..<phnum {
        let p = phoff + i * phentsize
        let type = try r.u32(p)
        if type == 1 { loads.append(Load(vaddr: try r.u64(p + 16), offset: try r.u64(p + 8), size: try r.u64(p + 32))) }
        if type == 2 { dynamic = (Int(try r.u64(p + 8)), Int(try r.u64(p + 32))) }
    }
    guard let dyn = dynamic else { return ELFDynamicInfo(needed: [], runpath: nil, soname: nil) }
    var neededOffsets: [UInt64] = []
    var strtab: UInt64?, runpath: UInt64?, rpath: UInt64?, soname: UInt64?
    var e = dyn.offset
    while e + 16 <= dyn.offset + dyn.size {
        let tag = try r.u64(e), value = try r.u64(e + 8)
        if tag == 0 { break }
        switch tag {
        case 1: neededOffsets.append(value)
        case 5: strtab = value
        case 14: soname = value
        case 15: rpath = value
        case 29: runpath = value
        default: break
        }
        e += 16
    }
    guard let strtabAddress = strtab else { throw BinaryFormatError.truncated("\(name): no DT_STRTAB") }
    // DT_STRTAB is an address: map it to a file offset through the PT_LOAD segments.
    var strtabOffset = strtabAddress
    for l in loads where strtabAddress >= l.vaddr && strtabAddress < l.vaddr + l.size {
        strtabOffset = strtabAddress - l.vaddr + l.offset
        break
    }
    func string(_ o: UInt64) throws -> String { try r.cString(Int(strtabOffset + o)) }
    return ELFDynamicInfo(needed: try neededOffsets.map(string),
                          runpath: try (runpath ?? rpath).map(string),
                          soname: try soname.map(string))
}
