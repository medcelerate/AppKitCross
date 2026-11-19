import Foundation

/// A local or remote endpoint in a network connection.
public enum NWEndpoint: Hashable, CustomDebugStringConvertible, Sendable {
    case hostPort(host: NWEndpoint.Host, port: NWEndpoint.Port)
    case service(name: String, type: String, domain: String, interface: NWInterface?)
    case unix(path: String)
    case url(_ url: URL)

    /// A name or address that identifies a network host.
    public enum Host: Hashable, CustomDebugStringConvertible, ExpressibleByStringLiteral, Sendable {
        public typealias StringLiteralType = String

        case name(String, NWInterface?)
        case ipv4(IPv4Address)
        case ipv6(IPv6Address)

        public init(stringLiteral: NWEndpoint.Host.StringLiteralType) {
            self.init(stringLiteral)
        }

        /// Parses IPv4 and IPv6 literals (with an optional `%interface` scope); anything
        /// else becomes a host name.
        public init(_ string: String) {
            if let v4 = IPv4Address(string) {
                self = .ipv4(v4)
            } else if let v6 = IPv6Address(string) {
                self = .ipv6(v6)
            } else if let percent = string.lastIndex(of: "%"),
                      let interface = NWInterface._named(String(string[string.index(after: percent)...])) {
                self = .name(String(string[..<percent]), interface)
            } else {
                self = .name(string, nil)
            }
        }

        public var interface: NWInterface? {
            switch self {
            case .name(_, let interface): return interface
            case .ipv4(let address): return address.interface
            case .ipv6(let address): return address.interface
            }
        }

        public var debugDescription: String {
            switch self {
            case .name(let name, let interface):
                return interface.map { "\(name)%\($0.name)" } ?? name
            case .ipv4(let address): return address.debugDescription
            case .ipv6(let address): return address.debugDescription
            }
        }
    }

    /// A port number used to identify a specific endpoint.
    public struct Port: Hashable, CustomDebugStringConvertible, ExpressibleByIntegerLiteral, RawRepresentable, Sendable {
        public typealias IntegerLiteralType = UInt16
        public typealias RawValue = UInt16

        public static let any = Port(0)
        public static let ssh = Port(22)
        public static let smtp = Port(25)
        public static let http = Port(80)
        public static let pop = Port(110)
        public static let imap = Port(143)
        public static let https = Port(443)
        public static let imaps = Port(993)
        public static let socks = Port(1080)

        public var rawValue: UInt16 { _value }
        private let _value: UInt16

        private init(_ value: UInt16) { _value = value }

        /// A decimal port number, or a service name looked up in the services database.
        public init?(_ service: String) {
            if let number = UInt16(service) {
                _value = number
            } else if let number = Sock.servicePort(named: service) {
                _value = number
            } else {
                return nil
            }
        }

        public init(integerLiteral value: NWEndpoint.Port.IntegerLiteralType) {
            _value = value
        }

        public init?(rawValue: UInt16) {
            _value = rawValue
        }

        public var debugDescription: String { String(_value) }
    }

    public var interface: NWInterface? {
        switch self {
        case .hostPort(let host, _): return host.interface
        case .service(_, _, _, let interface): return interface
        case .unix, .url: return nil
        }
    }

    public var debugDescription: String {
        switch self {
        case .hostPort(let host, let port):
            if case .ipv6 = host { return "[\(host.debugDescription)]:\(port.rawValue)" }
            return "\(host.debugDescription):\(port.rawValue)"
        case .service(let name, let type, let domain, _):
            return "\(name).\(type).\(domain)"
        case .unix(let path):
            return path
        case .url(let url):
            return url.absoluteString
        }
    }
}

/// A network interface.
public struct NWInterface: Hashable, CustomDebugStringConvertible, Sendable {
    /// Interface types.
    public enum InterfaceType: Sendable {
        case other
        case wifi
        case cellular
        case wiredEthernet
        case loopback
    }

    public let type: NWInterface.InterfaceType
    public let name: String
    public let index: Int

    init(name: String, index: Int, type: InterfaceType) {
        self.name = name
        self.index = index
        self.type = type
    }

    public var debugDescription: String { name }

    /// The interface with this name or decimal index, if one exists.
    static func _named(_ name: String) -> NWInterface? {
        if let index = Int(name), index > 0 {
            return Sock.interfaceName(index: index).map { NWInterface(name: $0, index: index, type: .other) }
        }
        guard let index = Sock.interfaceIndex(name: name) else { return nil }
        return NWInterface(name: name, index: index, type: .other)
    }
}

// MARK: - IP addresses

/// An IP address.
public protocol IPAddress: Sendable {
    var rawValue: Data { get }
    init?(_ rawValue: Data, _ interface: NWInterface?)
    init?(_ string: String)
    var interface: NWInterface? { get }
    var isLoopback: Bool { get }
    var isLinkLocal: Bool { get }
    var isMulticast: Bool { get }
}

/// An IP version 4 address.
public struct IPv4Address: IPAddress, Hashable, CustomDebugStringConvertible {
    public static let any = IPv4Address(bytes: (0, 0, 0, 0))
    public static let broadcast = IPv4Address(bytes: (255, 255, 255, 255))
    public static let loopback = IPv4Address(bytes: (127, 0, 0, 1))
    public static let allHostsGroup = IPv4Address(bytes: (224, 0, 0, 1))
    public static let allRoutersGroup = IPv4Address(bytes: (224, 0, 0, 2))
    public static let allReportsGroup = IPv4Address(bytes: (224, 0, 0, 22))
    public static let mdnsGroup = IPv4Address(bytes: (224, 0, 0, 251))

    let _bytes: [UInt8]
    public let interface: NWInterface?

    private init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        _bytes = [bytes.0, bytes.1, bytes.2, bytes.3]
        interface = nil
    }

    init(_bytes bytes: [UInt8], interface: NWInterface? = nil) {
        precondition(bytes.count == 4)
        _bytes = bytes
        self.interface = interface
    }

    public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
        guard rawValue.count == 4 else { return nil }
        _bytes = Array(rawValue)
        self.interface = interface
    }

    /// Parses dotted-quad notation with an optional `%interface` suffix.
    public init?(_ string: String) {
        var text = Substring(string)
        var interface: NWInterface?
        if let percent = text.firstIndex(of: "%") {
            guard let named = NWInterface._named(String(text[text.index(after: percent)...])) else { return nil }
            interface = named
            text = text[..<percent]
        }
        guard let bytes = _parseIPv4(text) else { return nil }
        _bytes = bytes
        self.interface = interface
    }

    public var rawValue: Data { Data(_bytes) }
    public var isLoopback: Bool { _bytes[0] == 127 }
    public var isLinkLocal: Bool { _bytes[0] == 169 && _bytes[1] == 254 }
    public var isMulticast: Bool { _bytes[0] & 0xF0 == 0xE0 }

    public var debugDescription: String {
        let text = _bytes.map(String.init).joined(separator: ".")
        return interface.map { "\(text)%\($0.name)" } ?? text
    }
}

/// An IP version 6 address.
public struct IPv6Address: IPAddress, Hashable, CustomDebugStringConvertible {
    public static let any = IPv6Address(_bytes: [UInt8](repeating: 0, count: 16))
    public static let loopback = IPv6Address(_bytes: [UInt8](repeating: 0, count: 15) + [1])
    public static let nodeLocalNodes = IPv6Address(_bytes: [0xFF, 0x01] + [UInt8](repeating: 0, count: 13) + [1])
    public static let linkLocalNodes = IPv6Address(_bytes: [0xFF, 0x02] + [UInt8](repeating: 0, count: 13) + [1])
    public static let linkLocalRouters = IPv6Address(_bytes: [0xFF, 0x02] + [UInt8](repeating: 0, count: 13) + [2])

    /// IPv6 multicast scopes.
    public enum Scope: UInt8 {
        case nodeLocal = 1
        case linkLocal = 2
        case siteLocal = 5
        case organizationLocal = 8
        case global = 14
    }

    let _bytes: [UInt8]
    public let interface: NWInterface?

    init(_bytes bytes: [UInt8], interface: NWInterface? = nil) {
        precondition(bytes.count == 16)
        _bytes = bytes
        self.interface = interface
    }

    public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
        guard rawValue.count == 16 else { return nil }
        _bytes = Array(rawValue)
        self.interface = interface
    }

    /// Parses RFC 4291 text (including `::` and an embedded IPv4 tail) with an optional
    /// `%interface` zone.
    public init?(_ string: String) {
        var text = Substring(string)
        var interface: NWInterface?
        if let percent = text.firstIndex(of: "%") {
            guard let named = NWInterface._named(String(text[text.index(after: percent)...])) else { return nil }
            interface = named
            text = text[..<percent]
        }
        guard let bytes = _parseIPv6(text) else { return nil }
        _bytes = bytes
        self.interface = interface
    }

    public var rawValue: Data { Data(_bytes) }
    public var isAny: Bool { _bytes.allSatisfy { $0 == 0 } }
    public var isLoopback: Bool { _bytes == IPv6Address.loopback._bytes }
    public var isIPv4Compatabile: Bool { _bytes[0..<12].allSatisfy { $0 == 0 } && !isAny && !isLoopback }
    public var isIPv4Mapped: Bool { _bytes[0..<10].allSatisfy { $0 == 0 } && _bytes[10] == 0xFF && _bytes[11] == 0xFF }
    public var asIPv4: IPv4Address? {
        guard isIPv4Mapped || isIPv4Compatabile else { return nil }
        return IPv4Address(_bytes: Array(_bytes[12..<16]), interface: interface)
    }
    public var is6to4: Bool { _bytes[0] == 0x20 && _bytes[1] == 0x02 }
    public var isLinkLocal: Bool { _bytes[0] == 0xFE && _bytes[1] & 0xC0 == 0x80 }
    public var isMulticast: Bool { _bytes[0] == 0xFF }
    public var isUniqueLocal: Bool { _bytes[0] == 0xFC || _bytes[0] == 0xFD }
    public var multicastScope: IPv6Address.Scope? {
        guard isMulticast else { return nil }
        return Scope(rawValue: _bytes[1] & 0x0F)
    }

    public var debugDescription: String {
        let text = _formatIPv6(_bytes)
        return interface.map { "\(text)%\($0.name)" } ?? text
    }
}

// MARK: - Text forms

func _parseIPv4(_ text: Substring) -> [UInt8]? {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var bytes: [UInt8] = []
    for part in parts {
        guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = UInt8(part) else { return nil }
        bytes.append(value)
    }
    return bytes
}

func _parseIPv6(_ text: Substring) -> [UInt8]? {
    guard !text.isEmpty else { return nil }
    let halves = text.components(separatedBy: "::")
    guard halves.count <= 2 else { return nil }

    func groups(_ part: String, allowIPv4Tail: Bool) -> [UInt16]? {
        if part.isEmpty { return [] }
        var result: [UInt16] = []
        let pieces = part.split(separator: ":", omittingEmptySubsequences: false)
        for (index, piece) in pieces.enumerated() {
            if index == pieces.count - 1, allowIPv4Tail, piece.contains(".") {
                guard let v4 = _parseIPv4(piece) else { return nil }
                result.append(UInt16(v4[0]) << 8 | UInt16(v4[1]))
                result.append(UInt16(v4[2]) << 8 | UInt16(v4[3]))
            } else {
                guard (1...4).contains(piece.count), let value = UInt16(piece, radix: 16) else { return nil }
                result.append(value)
            }
        }
        return result
    }

    let words: [UInt16]
    if halves.count == 1 {
        guard let all = groups(halves[0], allowIPv4Tail: true), all.count == 8 else { return nil }
        words = all
    } else {
        guard let head = groups(halves[0], allowIPv4Tail: false),
              let tail = groups(halves[1], allowIPv4Tail: true),
              head.count + tail.count <= 7 else { return nil }
        words = head + [UInt16](repeating: 0, count: 8 - head.count - tail.count) + tail
    }
    return words.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
}

/// RFC 5952 text: lowercase, no leading zeros, the longest run of two or more zero
/// groups collapsed to `::`, IPv4-mapped addresses with a dotted tail.
func _formatIPv6(_ bytes: [UInt8]) -> String {
    if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
        return "::ffff:" + bytes[12..<16].map(String.init).joined(separator: ".")
    }
    let words = stride(from: 0, to: 16, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
    var bestStart = -1, bestLength = 0, index = 0
    while index < 8 {
        if words[index] == 0 {
            var end = index
            while end < 8 && words[end] == 0 { end += 1 }
            if end - index > bestLength { bestStart = index; bestLength = end - index }
            index = end
        } else {
            index += 1
        }
    }
    func hex(_ range: Range<Int>) -> String {
        words[range].map { String($0, radix: 16) }.joined(separator: ":")
    }
    guard bestLength >= 2 else { return hex(0..<8) }
    return hex(0..<bestStart) + "::" + hex((bestStart + bestLength)..<8)
}
