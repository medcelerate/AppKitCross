import Foundation

/// A Bonjour TXT record: an ordered set of `key[=value]` strings (RFC 6763 section 6).
public struct NWTXTRecord: Sendable {
    /// The value of one TXT record key.
    public enum Entry: Hashable, CustomDebugStringConvertible, Sendable {
        /// The key is absent.
        case none
        /// The key is present without `=` (a boolean attribute).
        case empty
        case string(String)
        case data(Data)

        public var data: Data? {
            switch self {
            case .none, .empty: return nil
            case .string(let string): return Data(string.utf8)
            case .data(let data): return data
            }
        }

        public init(_ data: Data?) {
            guard let data else { self = .empty; return }
            if let string = String(data: data, encoding: .utf8) { self = .string(string) } else { self = .data(data) }
        }

        public var debugDescription: String {
            switch self {
            case .none: return "none"
            case .empty: return "empty"
            case .string(let string): return string
            case .data(let data): return "\(data.count) bytes"
            }
        }
    }

    private var entries: [(key: String, value: Entry)] = []

    public init(_ dictionary: [String: String] = [:]) {
        for key in dictionary.keys.sorted() {
            setEntry(.string(dictionary[key]!), for: key)
        }
    }

    /// Parses TXT rdata (length-prefixed strings). Malformed trailing bytes are ignored;
    /// a repeated key keeps its first value, as RFC 6763 requires.
    public init(_ data: Data) {
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset])
            offset += 1
            guard length > 0 else { continue }
            guard offset + length <= bytes.count else { break }
            let item = bytes[offset..<(offset + length)]
            offset += length
            let key: String
            let value: Entry
            if let equals = item.firstIndex(of: UInt8(ascii: "=")) {
                key = String(decoding: item[item.startIndex..<equals], as: UTF8.self)
                value = Entry(Data(item[(equals + 1)...]))
            } else {
                key = String(decoding: item, as: UTF8.self)
                value = .empty
            }
            guard !key.isEmpty, entries.firstIndex(where: { $0.key.lowercased() == key.lowercased() }) == nil else { continue }
            entries.append((key, value))
        }
    }

    @discardableResult
    public mutating func removeEntry(key: String) -> Bool {
        guard let index = indexOf(key) else { return false }
        entries.remove(at: index)
        return true
    }

    public func getEntry(for key: String) -> NWTXTRecord.Entry? {
        indexOf(key).map { entries[$0].value }
    }

    /// The TXT rdata. An empty record encodes as a single empty string, as on the wire.
    public var data: Data {
        var bytes: [UInt8] = []
        for (key, value) in entries {
            var item = Array(key.utf8)
            switch value {
            case .none: continue
            case .empty: break
            case .string, .data: item.append(UInt8(ascii: "=")); item.append(contentsOf: value.data ?? Data())
            }
            guard item.count <= 255 else { continue }
            bytes.append(UInt8(item.count))
            bytes.append(contentsOf: item)
        }
        return Data(bytes)
    }

    @discardableResult
    public mutating func setEntry(_ entry: NWTXTRecord.Entry, for key: String) -> Bool {
        guard !key.isEmpty, !key.contains("=") else { return false }
        if case .none = entry { return removeEntry(key: key) }
        if let index = indexOf(key) { entries[index].value = entry } else { entries.append((key, entry)) }
        return true
    }

    public subscript(key: String) -> String? {
        get {
            switch getEntry(for: key) {
            case .string(let string): return string
            case .data(let data): return String(data: data, encoding: .utf8)
            case .empty: return ""
            case .some(.none), nil: return nil
            }
        }
        set {
            if let newValue { setEntry(.string(newValue), for: key) } else { removeEntry(key: key) }
        }
    }

    public var dictionary: [String: String] {
        var result: [String: String] = [:]
        for (key, _) in entries { result[key] = self[key] }
        return result
    }

    private func indexOf(_ key: String) -> Int? {
        let lowered = key.lowercased()
        return entries.firstIndex { $0.key.lowercased() == lowered }
    }
}

extension NWTXTRecord: Equatable {
    public static func == (lhs: NWTXTRecord, rhs: NWTXTRecord) -> Bool {
        lhs.entries.count == rhs.entries.count
            && zip(lhs.entries, rhs.entries).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }
}

extension NWTXTRecord: Collection {
    public typealias Element = (key: String, value: NWTXTRecord.Entry)

    public struct Index: Comparable {
        let offset: Int
        public static func == (lhs: Index, rhs: Index) -> Bool { lhs.offset == rhs.offset }
        public static func < (lhs: Index, rhs: Index) -> Bool { lhs.offset < rhs.offset }
    }

    public subscript(position: NWTXTRecord.Index) -> NWTXTRecord.Element { entries[position.offset] }
    public var startIndex: NWTXTRecord.Index { Index(offset: 0) }
    public var endIndex: NWTXTRecord.Index { Index(offset: entries.count) }
    public func index(after i: NWTXTRecord.Index) -> NWTXTRecord.Index { Index(offset: i.offset + 1) }
}

extension NWTXTRecord: CustomDebugStringConvertible {
    public var debugDescription: String {
        entries.map { "\($0.key)=\($0.value.debugDescription)" }.joined(separator: ", ")
    }
}
