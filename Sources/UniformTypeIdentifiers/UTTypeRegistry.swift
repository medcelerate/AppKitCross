// The type database behind UTType: the generated UTCoreTypes table, types declared at
// run time through `UTType(exportedAs:)` / `UTType(importedAs:)`, and Apple's `dyn.*`
// encoding for types that only exist as a tag.

import Foundation

/// One declared type. `parents` are the direct supertypes' identifiers.
struct UTTypeRecord: Sendable {
    let identifier: String
    let parents: [String]
    let filenameExtensions: [String]
    let mimeTypes: [String]
    let localizedDescription: String?
    let referenceURL: String?
    let version: Int?
    let isDeclared: Bool
    let isDynamic: Bool

    init(_ identifier: String, _ parents: [String], _ extensions: [String], _ mimeTypes: [String],
         _ description: String?, _ referenceURL: String?, _ version: Int?, isDeclared: Bool = true, isDynamic: Bool = false) {
        self.identifier = identifier
        self.parents = parents
        self.filenameExtensions = extensions
        self.mimeTypes = mimeTypes
        self.localizedDescription = description
        self.referenceURL = referenceURL
        self.version = version
        self.isDeclared = isDeclared
        self.isDynamic = isDynamic
    }

    /// A type whose identifier is known but that nothing declares (`isDeclared == false`).
    static func undeclared(_ identifier: String, parents: [String] = []) -> UTTypeRecord {
        UTTypeRecord(identifier, parents, [], [], nil, nil, nil, isDeclared: false)
    }

    func tags(_ tagClass: UTTagClass) -> [String] {
        switch tagClass {
        case .filenameExtension: return filenameExtensions
        case .mimeType: return mimeTypes
        default: return []
        }
    }
}

/// Process-wide registry: the core types plus whatever the app declared.
final class UTTypeRegistry: @unchecked Sendable {
    static let shared = UTTypeRegistry()

    private let lock = NSLock()
    private var byIdentifier: [String: UTTypeRecord] = [:]      // lowercased identifier
    private var order: [String] = []                             // declaration order, for lookups by tag

    private init() {
        for record in utCoreTypesTable { insert(record) }
    }

    private func insert(_ record: UTTypeRecord) {
        let key = record.identifier.lowercased()
        if byIdentifier[key] == nil { order.append(key) }
        byIdentifier[key] = record
    }

    func lookup(_ identifier: String) -> UTTypeRecord? {
        lock.lock(); defer { lock.unlock() }
        return byIdentifier[identifier.lowercased()]
    }

    /// Declares `identifier` (an exported or imported type). Core types are never
    /// redeclared; a second declaration of an app type replaces the first.
    func declare(_ identifier: String, conformingTo parent: String?) -> UTTypeRecord {
        declare(identifier, conformingTo: parent.map { [$0] } ?? [], extensions: [], mimeTypes: [], description: nil)
    }

    /// A full declaration, as an Info.plist `UTExportedTypeDeclarations` entry gives it.
    @discardableResult
    func declare(_ identifier: String, conformingTo parents: [String], extensions: [String], mimeTypes: [String], description: String?) -> UTTypeRecord {
        lock.lock(); defer { lock.unlock() }
        if let existing = byIdentifier[identifier.lowercased()], utCoreIdentifiers.contains(identifier.lowercased()) { return existing }
        let record = UTTypeRecord(identifier, parents, extensions, mimeTypes, description, nil, nil)
        insert(record)
        return record
    }

    private lazy var utCoreIdentifiers: Set<String> = Set(utCoreTypesTable.map { $0.identifier.lowercased() })

    /// Every declared type carrying `tag` in `tagClass`, preferred types first: a type
    /// whose preferred tag this is beats one that merely lists it, and `public.*`
    /// declarations beat third-party ones, as LaunchServices ranks them.
    func types(tag: String, tagClass: UTTagClass) -> [UTTypeRecord] {
        lock.lock(); defer { lock.unlock() }
        let needle = tag.lowercased()
        var matches: [(rank: Int, index: Int, record: UTTypeRecord)] = []
        for (index, key) in order.enumerated() {
            guard let record = byIdentifier[key] else { continue }
            let tags = record.tags(tagClass).map { $0.lowercased() }
            guard let position = tags.firstIndex(of: needle) else { continue }
            let rank = (position == 0 ? 0 : 2) + (record.identifier.hasPrefix("public.") ? 0 : 1)
            matches.append((rank, index, record))
        }
        return matches.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.index < $1.index }.map { $0.record }
    }
}

// MARK: Dynamic identifiers

/// Apple's `dyn.a…` encoding: a `?key=value:key=value` descriptor in a base-32 alphabet
/// with single-character abbreviations for the common keys and conformance targets.
enum UTDynamicType {
    static let alphabet: [Character] = Array("abcdefghkmnpqrstuvwxyz0123456789")
    static let keyConformsTo = "0", keyExtension = "1", keyOSType = "2", keyMIMEType = "3", keyPasteboardType = "4", keyURLScheme = "5"
    static let abbreviations: [(String, String)] = [
        ("6", "public.data"), ("7", "public.text"), ("8", "public.plain-text"), ("9", "public.utf16-plain-text"),
        ("A", "com.apple.traditional-mac-plain-text"), ("B", "public.image"), ("C", "public.video"),
        ("D", "public.audio"), ("E", "public.directory"), ("F", "public.folder"),
    ]

    static func encode(_ descriptor: String) -> String {
        var bits: [UInt8] = []
        bits.reserveCapacity(descriptor.utf8.count * 8 + 5)
        for byte in descriptor.utf8 { for i in (0..<8).reversed() { bits.append((byte >> i) & 1) } }
        while bits.count % 5 != 0 { bits.append(0) }
        var out = "dyn.a"
        for i in stride(from: 0, to: bits.count, by: 5) {
            var value = 0
            for j in 0..<5 { value = value << 1 | Int(bits[i + j]) }
            out.append(alphabet[value])
        }
        return out
    }

    static func decode(_ identifier: String) -> String? {
        guard identifier.hasPrefix("dyn.a") else { return nil }
        var bits: [UInt8] = []
        for c in identifier.dropFirst(5) {
            guard let value = alphabet.firstIndex(of: c) else { return nil }
            for i in (0..<5).reversed() { bits.append(UInt8((value >> i) & 1)) }
        }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: bits.count - bits.count % 8, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 { byte = byte << 1 | bits[i + j] }
            bytes.append(byte)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Tag-class abbreviations; any other class is spelled out.
    static let tagClassKeys: [(String, String)] = [
        (keyExtension, "public.filename-extension"), (keyOSType, "com.apple.ostype"), (keyMIMEType, "public.mime-type"),
        (keyPasteboardType, "com.apple.nspboard-type"), (keyURLScheme, "public.url-scheme"),
    ]

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ":", with: "\\:")
    }

    /// The identifier of the dynamic type carrying `tag` and conforming to `parent`. The
    /// descriptor is `key=value` fields joined by `:`, led by `?` when a conformance field
    /// is present (`?0=6:1=zzqx`, `1=zzqx`), as LaunchServices writes them.
    static func identifier(tag: String, tagClass: UTTagClass, conformingTo parent: String?) -> String {
        var fields: [String] = []
        if let parent {
            let value = abbreviations.first { $0.1 == parent.lowercased() }?.0 ?? parent
            fields.append("\(keyConformsTo)=\(escape(value))")
        }
        let key = tagClassKeys.first { $0.1 == tagClass.rawValue }?.0 ?? tagClass.rawValue
        fields.append("\(key)=\(escape(tag))")
        return encode((parent == nil ? "" : "?") + fields.joined(separator: ":"))
    }

    /// Splits a descriptor on unescaped `:` and removes the escapes.
    static func fields(of descriptor: String) -> [String] {
        var result: [String] = [], current = "", escaped = false
        for c in descriptor {
            if escaped { current.append(c); escaped = false }
            else if c == "\\" { escaped = true }
            else if c == ":" { result.append(current); current = "" }
            else { current.append(c) }
        }
        result.append(current)
        return result
    }

    /// Rebuilds the record a `dyn.*` identifier encodes, or nil if it does not decode.
    static func record(for identifier: String) -> UTTypeRecord? {
        guard var descriptor = decode(identifier), !descriptor.isEmpty else { return nil }
        if descriptor.hasPrefix("?") { descriptor.removeFirst() }
        var parents: [String] = [], extensions: [String] = [], mimeTypes: [String] = []
        for field in fields(of: descriptor) {
            guard let eq = field.firstIndex(of: "=") else { return nil }
            let key = String(field[..<eq]), value = String(field[field.index(after: eq)...])
            switch key {
            case keyConformsTo: parents.append(abbreviations.first { $0.0 == value }?.1 ?? value)
            case keyExtension: extensions.append(value)
            case keyMIMEType: mimeTypes.append(value)
            default: break
            }
        }
        return UTTypeRecord(identifier, parents, extensions, mimeTypes, nil, nil, nil, isDeclared: false, isDynamic: true)
    }
}
