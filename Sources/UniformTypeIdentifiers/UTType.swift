// UniformTypeIdentifiers for Windows and Linux (ADR-0009): `UTType` with Apple's API
// over the generated UTCoreTypes table. There is no LaunchServices database on these
// platforms, so the declared types are the SDK's core types plus whatever the app
// declares with `UTType(exportedAs:)` / `UTType(importedAs:)`; everything else is a
// dynamic (`dyn.*`) type, encoded the way Apple encodes them.

import Foundation

public struct UTType: Sendable {
    let record: UTTypeRecord

    init(record: UTTypeRecord) { self.record = record }

    /// A core type by identifier; the generated constants go through here.
    init(coreType identifier: String) {
        guard let record = UTTypeRegistry.shared.lookup(identifier) else {
            preconditionFailure("UniformTypeIdentifiers: core type \(identifier) is missing from the table")
        }
        self.record = record
    }
}

// MARK: Identification

extension UTType {
    /// A declared or dynamic type by identifier; nil when nothing declares `identifier`
    /// and it is not a well-formed `dyn.*` identifier.
    public init?(_ identifier: String) {
        if let record = UTTypeRegistry.shared.lookup(identifier) { self.record = record }
        else if let record = UTDynamicType.record(for: identifier) { self.record = record }
        else { return nil }
    }

    /// The preferred declared type for a filename extension, dynamic if none declares it.
    public init?(filenameExtension: String, conformingTo supertype: UTType = .data) {
        self.init(tag: filenameExtension, tagClass: .filenameExtension, conformingTo: supertype)
    }

    /// The preferred declared type for a MIME type, dynamic if none declares it.
    public init?(mimeType: String, conformingTo supertype: UTType = .data) {
        self.init(tag: mimeType, tagClass: .mimeType, conformingTo: supertype)
    }

    public var identifier: String { record.identifier }
    public var preferredFilenameExtension: String? { record.filenameExtensions.first }
    public var preferredMIMEType: String? { record.mimeTypes.first }
    /// The SDK's English description for core types; nil for app-declared and dynamic
    /// types, which have no bundle to read a localized description from.
    public var localizedDescription: String? { record.localizedDescription }
    public var version: Int? { record.version }
    public var referenceURL: URL? { record.referenceURL.flatMap { URL(string: $0) } }
    public var isDynamic: Bool { record.isDynamic }
    public var isDeclared: Bool { record.isDeclared }
    public var isPublic: Bool { record.identifier.lowercased().hasPrefix("public.") }
}

// MARK: Conformance

extension UTType {
    public func conforms(to type: UTType) -> Bool {
        if identifier.caseInsensitiveCompare(type.identifier) == .orderedSame { return true }
        var seen = Set<String>()
        var frontier = record.parents
        while let parent = frontier.popLast() {
            let key = parent.lowercased()
            if !seen.insert(key).inserted { continue }
            if key == type.identifier.lowercased() { return true }
            if let next = UTTypeRegistry.shared.lookup(parent) { frontier += next.parents }
        }
        return false
    }

    public func isSupertype(of type: UTType) -> Bool { self != type && type.conforms(to: self) }
    public func isSubtype(of type: UTType) -> Bool { self != type && conforms(to: type) }

    /// Every type this one conforms to, transitively.
    public var supertypes: Set<UTType> {
        var result = Set<UTType>()
        var frontier = record.parents
        while let parent = frontier.popLast() {
            let type = UTType(parent) ?? UTType(record: .undeclared(parent))
            if !result.insert(type).inserted { continue }
            frontier += type.record.parents
        }
        return result
    }
}

// MARK: Tags

extension UTType {
    /// The preferred declared type carrying `tag` and conforming to `supertype`, or a
    /// dynamic type when no declared type does.
    public init?(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) {
        let candidates = UTTypeRegistry.shared.types(tag: tag, tagClass: tagClass)
        if let match = candidates.first(where: { supertype == nil || UTType(record: $0).conforms(to: supertype!) }) {
            self.record = match
            return
        }
        guard tagClass == .filenameExtension || tagClass == .mimeType, !tag.isEmpty else { return nil }
        let dynamic = UTDynamicType.identifier(tag: tag, tagClass: tagClass, conformingTo: supertype?.identifier)
        guard let record = UTDynamicType.record(for: dynamic) else { return nil }
        self.record = record
    }

    /// All declared types carrying `tag`, preferred first.
    public static func types(tag: String, tagClass: UTTagClass, conformingTo supertype: UTType?) -> [UTType] {
        UTTypeRegistry.shared.types(tag: tag, tagClass: tagClass).map(UTType.init(record:))
            .filter { supertype == nil || $0.conforms(to: supertype!) }
    }

    /// The type's tags by class; only filename extensions and MIME types are modelled.
    public var tags: [UTTagClass: [String]] {
        var result: [UTTagClass: [String]] = [:]
        if !record.filenameExtensions.isEmpty { result[.filenameExtension] = record.filenameExtensions }
        if !record.mimeTypes.isEmpty { result[.mimeType] = record.mimeTypes }
        return result
    }
}

// MARK: App-declared types

extension UTType {
    /// A type this app exports. Without an Info.plist to read the declaration from, the
    /// type is declared here with `parentType` as its only supertype, and later lookups
    /// by identifier or tag find it (Apple only finds types the bundle declares).
    public init(exportedAs identifier: String, conformingTo parentType: UTType? = nil) {
        record = UTTypeRegistry.shared.declare(identifier, conformingTo: parentType?.identifier)
    }

    /// A type another app owns that this app imports; declared the same way.
    public init(importedAs identifier: String, conformingTo parentType: UTType? = nil) {
        record = UTTypeRegistry.shared.declare(identifier, conformingTo: parentType?.identifier)
    }
}

// MARK: Protocols

extension UTType: Equatable, Hashable {
    public static func == (lhs: UTType, rhs: UTType) -> Bool { lhs.identifier.caseInsensitiveCompare(rhs.identifier) == .orderedSame }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier.lowercased()) }
}

extension UTType: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { identifier }
    public var debugDescription: String {
        "\(identifier) (\(isDynamic ? "dynamic" : "not dynamic"), \(isDeclared ? "declared" : "not declared"))"
    }
}

extension UTType: Codable {
    private enum CodingKeys: String, CodingKey { case identifier }

    /// Encodes the identifier. Decoding also accepts Apple's keyed form
    /// (`{"identifier": …, "constantIndex": …}`), so archives cross platforms.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }

    public init(from decoder: any Decoder) throws {
        let identifier: String
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
            identifier = value
        } else {
            identifier = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .identifier)
        }
        // An identifier nothing here declares still names a type (declared elsewhere).
        self.record = UTType(identifier)?.record ?? .undeclared(identifier)
    }
}

// MARK: Foundation additions (UTAdditions.h)

extension URL {
    /// Appends `partialName`, then `contentType`'s preferred extension unless the name's
    /// own extension already denotes a type conforming to `contentType`.
    public func appendingPathComponent(_ partialName: String, conformingTo contentType: UTType) -> URL {
        var url = appendingPathComponent(partialName)
        let existing = (partialName as NSString).pathExtension
        if existing.isEmpty || UTType(filenameExtension: existing, conformingTo: .item)?.conforms(to: contentType) != true {
            url = url.appendingPathExtension(for: contentType)
        }
        return url
    }

    public mutating func appendPathComponent(_ partialName: String, conformingTo contentType: UTType) {
        self = appendingPathComponent(partialName, conformingTo: contentType)
    }

    /// Appends `contentType`'s preferred extension, if it has one.
    public func appendingPathExtension(for contentType: UTType) -> URL {
        guard let ext = contentType.preferredFilenameExtension else { return self }
        return appendingPathExtension(ext)
    }

    public mutating func appendPathExtension(for contentType: UTType) {
        self = appendingPathExtension(for: contentType)
    }
}
