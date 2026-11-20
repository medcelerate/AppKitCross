// DNS message encoding and decoding for mDNS/DNS-SD (RFC 1035, RFC 6762, RFC 6763).
// Pure functions over bytes; no sockets.

import Foundation

/// A domain name as labels. Labels are raw strings: a DNS-SD instance name may contain
/// dots and spaces and is still one label. Comparison ignores ASCII case.
struct DNSName: Hashable, CustomStringConvertible, Sendable {
    let labels: [String]

    init(_ labels: [String]) {
        self.labels = labels
    }

    /// Splits dotted text into labels (no escapes); a trailing dot is ignored.
    init(dotted: String) {
        labels = dotted.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
    }

    /// The case-folded form used for comparison.
    var key: [String] { labels.map { $0.lowercased() } }

    static func == (lhs: DNSName, rhs: DNSName) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    func prepending(_ label: String) -> DNSName { DNSName([label] + labels) }

    /// True when this name is `label.parent` for a single leading label.
    func isChild(of parent: DNSName) -> Bool {
        labels.count == parent.labels.count + 1 && Array(key.dropFirst()) == parent.key
    }

    var description: String { labels.joined(separator: ".") + "." }
}

enum DNSType {
    static let a: UInt16 = 1
    static let ptr: UInt16 = 12
    static let txt: UInt16 = 16
    static let aaaa: UInt16 = 28
    static let srv: UInt16 = 33
    static let nsec: UInt16 = 47
    static let any: UInt16 = 255
}

/// Record data for the types DNS-SD uses; anything else is kept as raw bytes.
enum DNSRecordData: Equatable, Sendable {
    case a([UInt8])
    case aaaa([UInt8])
    case ptr(DNSName)
    case srv(priority: UInt16, weight: UInt16, port: UInt16, target: DNSName)
    case txt(Data)
    case other([UInt8])

    /// Uncompressed rdata, used both on the wire and as the cache identity.
    var bytes: [UInt8] {
        var writer = DNSWriter()
        writer.rdata(self)
        return writer.bytes
    }
}

struct DNSRecord: Equatable, Sendable {
    var name: DNSName
    var type: UInt16
    /// The mDNS cache-flush bit (top bit of the class): this is the complete set of
    /// records of this name and type.
    var cacheFlush: Bool
    var ttl: UInt32
    var data: DNSRecordData
}

struct DNSQuestion: Equatable, Sendable {
    var name: DNSName
    var type: UInt16
    /// The mDNS QU bit (top bit of the class).
    var unicastResponse: Bool = false
}

struct DNSMessage: Equatable, Sendable {
    var id: UInt16 = 0
    var flags: UInt16 = 0
    var questions: [DNSQuestion] = []
    var answers: [DNSRecord] = []
    var authorities: [DNSRecord] = []
    var additionals: [DNSRecord] = []

    var isResponse: Bool { flags & 0x8000 != 0 }

    /// Flags of an mDNS response: QR and AA.
    static let responseFlags: UInt16 = 0x8400

    func encoded() -> [UInt8] {
        var writer = DNSWriter()
        writer.u16(id)
        writer.u16(flags)
        writer.u16(UInt16(questions.count))
        writer.u16(UInt16(answers.count))
        writer.u16(UInt16(authorities.count))
        writer.u16(UInt16(additionals.count))
        for question in questions {
            writer.name(question.name)
            writer.u16(question.type)
            writer.u16(question.unicastResponse ? 0x8001 : 0x0001)
        }
        for record in answers + authorities + additionals {
            writer.record(record)
        }
        return writer.bytes
    }

    init(id: UInt16 = 0, flags: UInt16 = 0, questions: [DNSQuestion] = [], answers: [DNSRecord] = [],
         authorities: [DNSRecord] = [], additionals: [DNSRecord] = []) {
        self.id = id
        self.flags = flags
        self.questions = questions
        self.answers = answers
        self.authorities = authorities
        self.additionals = additionals
    }

    /// Decodes a message; nil when it is malformed.
    init?(decoding bytes: [UInt8]) {
        var reader = DNSReader(bytes: bytes)
        do {
            id = try reader.u16()
            flags = try reader.u16()
            let questionCount = try reader.u16()
            let answerCount = try reader.u16()
            let authorityCount = try reader.u16()
            let additionalCount = try reader.u16()
            for _ in 0..<questionCount {
                let name = try reader.name()
                let type = try reader.u16()
                let qclass = try reader.u16()
                questions.append(DNSQuestion(name: name, type: type, unicastResponse: qclass & 0x8000 != 0))
            }
            for _ in 0..<answerCount { answers.append(try reader.record()) }
            for _ in 0..<authorityCount { authorities.append(try reader.record()) }
            for _ in 0..<additionalCount { additionals.append(try reader.record()) }
        } catch {
            return nil
        }
    }
}

struct DNSWriter {
    var bytes: [UInt8] = []

    mutating func u8(_ value: UInt8) { bytes.append(value) }
    mutating func u16(_ value: UInt16) { bytes.append(UInt8(value >> 8)); bytes.append(UInt8(value & 0xFF)) }
    mutating func u32(_ value: UInt32) { u16(UInt16(value >> 16)); u16(UInt16(value & 0xFFFF)) }

    /// Writes a name uncompressed. Labels longer than 63 bytes are truncated; callers
    /// validate names they own before getting here.
    mutating func name(_ name: DNSName) {
        for label in name.labels {
            let utf8 = Array(label.utf8.prefix(63))
            u8(UInt8(utf8.count))
            bytes.append(contentsOf: utf8)
        }
        u8(0)
    }

    mutating func rdata(_ data: DNSRecordData) {
        switch data {
        case .a(let address), .aaaa(let address), .other(let address):
            bytes.append(contentsOf: address)
        case .ptr(let target):
            name(target)
        case .srv(let priority, let weight, let port, let target):
            u16(priority)
            u16(weight)
            u16(port)
            name(target)
        case .txt(let text):
            // An empty TXT record is a single empty string (RFC 6763 section 6.1).
            if text.isEmpty { u8(0) } else { bytes.append(contentsOf: text) }
        }
    }

    mutating func record(_ record: DNSRecord) {
        name(record.name)
        u16(record.type)
        u16(record.cacheFlush ? 0x8001 : 0x0001)
        u32(record.ttl)
        let rdata = record.data.bytes
        u16(UInt16(rdata.count))
        bytes.append(contentsOf: rdata)
    }
}

struct DNSReader {
    struct Malformed: Error {}

    let bytes: [UInt8]
    var offset = 0

    mutating func u8() throws -> UInt8 {
        guard offset < bytes.count else { throw Malformed() }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u16() throws -> UInt16 {
        UInt16(try u8()) << 8 | UInt16(try u8())
    }

    mutating func u32() throws -> UInt32 {
        UInt32(try u16()) << 16 | UInt32(try u16())
    }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw Malformed() }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    /// Reads a possibly compressed name, following at most 32 pointers.
    mutating func name() throws -> DNSName {
        var labels: [String] = []
        var position = offset
        var jumped = false
        var jumps = 0
        while true {
            guard position < bytes.count else { throw Malformed() }
            let length = bytes[position]
            if length & 0xC0 == 0xC0 {
                guard position + 1 < bytes.count, jumps < 32 else { throw Malformed() }
                let target = Int(length & 0x3F) << 8 | Int(bytes[position + 1])
                if !jumped { offset = position + 2 }
                jumped = true
                jumps += 1
                position = target
                continue
            }
            guard length & 0xC0 == 0 else { throw Malformed() }
            position += 1
            if length == 0 { break }
            guard position + Int(length) <= bytes.count else { throw Malformed() }
            labels.append(String(decoding: bytes[position..<(position + Int(length))], as: UTF8.self))
            position += Int(length)
            guard labels.count <= 128 else { throw Malformed() }
        }
        if !jumped { offset = position }
        return DNSName(labels)
    }

    mutating func record() throws -> DNSRecord {
        let name = try name()
        let type = try u16()
        let rclass = try u16()
        let ttl = try u32()
        let length = Int(try u16())
        let end = offset + length
        guard end <= bytes.count else { throw Malformed() }
        let data: DNSRecordData
        switch type {
        case DNSType.a where length == 4:
            data = .a(try take(4))
        case DNSType.aaaa where length == 16:
            data = .aaaa(try take(16))
        case DNSType.ptr:
            data = .ptr(try self.name())
        case DNSType.srv:
            let priority = try u16(), weight = try u16(), port = try u16()
            data = .srv(priority: priority, weight: weight, port: port, target: try self.name())
        case DNSType.txt:
            data = .txt(Data(try take(length)))
        default:
            data = .other(try take(length))
        }
        guard offset <= end else { throw Malformed() }
        offset = end
        return DNSRecord(name: name, type: type, cacheFlush: rclass & 0x8000 != 0, ttl: ttl, data: data)
    }
}
