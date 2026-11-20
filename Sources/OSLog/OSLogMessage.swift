// OSLogMessage and its interpolation, with Apple's formatting and privacy option types.
// Every interpolated value is kept as the autoclosure Apple's overloads take, so nothing is
// evaluated unless the message's level is enabled (`_OSLogFormatter` renders it).

import Foundation

// MARK: - Privacy

public struct OSLogPrivacy: Sendable {
    public enum Mask: Hashable, Sendable {
        case hash
        case none
        case _mailName
        case _mailAddress
        case _mailSubject
        case _mailSummary
        case _mailAccount
        case _mailbox
        case _mailboxPath
        case _mailAttachmentFileName
    }

    enum PrivacyOption: Hashable, Sendable {
        case `public`, `private`, sensitive, auto
    }

    let option: PrivacyOption
    let mask: Mask

    init(_ option: PrivacyOption, mask: Mask = .none) {
        self.option = option
        self.mask = mask
    }

    public static var `public`: OSLogPrivacy { OSLogPrivacy(.public) }
    public static var `private`: OSLogPrivacy { OSLogPrivacy(.private) }
    public static func `private`(mask: OSLogPrivacy.Mask) -> OSLogPrivacy { OSLogPrivacy(.private, mask: mask) }
    public static var sensitive: OSLogPrivacy { OSLogPrivacy(.sensitive) }
    public static func sensitive(mask: OSLogPrivacy.Mask) -> OSLogPrivacy { OSLogPrivacy(.sensitive, mask: mask) }
    public static var auto: OSLogPrivacy { OSLogPrivacy(.auto) }
    public static func auto(mask: OSLogPrivacy.Mask) -> OSLogPrivacy { OSLogPrivacy(.auto, mask: mask) }
}

// MARK: - Alignment

public struct OSLogStringAlignment {
    let columns: (() -> Int)?
    let leftAligned: Bool

    public static var none: OSLogStringAlignment { OSLogStringAlignment(columns: nil, leftAligned: false) }
    public static func right(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment {
        OSLogStringAlignment(columns: columns, leftAligned: false)
    }
    public static func left(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment {
        OSLogStringAlignment(columns: columns, leftAligned: true)
    }
}

// MARK: - Integer formatting

public struct OSLogIntegerFormatting {
    enum Radix { case decimal, hex, octal }
    let radix: Radix
    let explicitPositiveSign: Bool
    let includePrefix: Bool
    let uppercase: Bool
    let minDigits: (() -> Int)?

    public static func decimal(explicitPositiveSign: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .decimal, explicitPositiveSign: explicitPositiveSign, includePrefix: false, uppercase: false, minDigits: minDigits)
    }
    public static func decimal(explicitPositiveSign: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .decimal, explicitPositiveSign: explicitPositiveSign, includePrefix: false, uppercase: false, minDigits: nil)
    }
    public static var decimal: OSLogIntegerFormatting { .decimal(explicitPositiveSign: false) }

    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .hex, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: minDigits)
    }
    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .hex, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: nil)
    }
    public static var hex: OSLogIntegerFormatting { .hex(explicitPositiveSign: false, includePrefix: false, uppercase: false) }

    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false, minDigits: @autoclosure @escaping () -> Int) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .octal, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: minDigits)
    }
    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .octal, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: nil)
    }
    public static var octal: OSLogIntegerFormatting { .octal(explicitPositiveSign: false, includePrefix: false, uppercase: false) }
}

// MARK: - Float formatting

public struct OSLogFloatFormatting {
    enum Notation: Hashable { case fixed, hex, exponential, hybrid }
    let notation: Notation
    let precision: (() -> Int)?
    let explicitPositiveSign: Bool
    let uppercase: Bool

    public static var fixed: OSLogFloatFormatting { .fixed(explicitPositiveSign: false, uppercase: false) }
    public static func fixed(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(notation: .fixed, precision: precision, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func fixed(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(notation: .fixed, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }

    public static var hex: OSLogFloatFormatting { .hex(explicitPositiveSign: false, uppercase: false) }
    public static func hex(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(notation: .hex, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }

    public static var exponential: OSLogFloatFormatting { .exponential(explicitPositiveSign: false, uppercase: false) }
    public static func exponential(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(notation: .exponential, precision: precision, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func exponential(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(notation: .exponential, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }

    public static var hybrid: OSLogFloatFormatting { .hybrid(explicitPositiveSign: false, uppercase: false) }
    public static func hybrid(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(notation: .hybrid, precision: precision, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
    public static func hybrid(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(notation: .hybrid, precision: nil, explicitPositiveSign: explicitPositiveSign, uppercase: uppercase)
    }
}

// MARK: - Bool and pointer formats

public enum OSLogBoolFormat: Hashable, Sendable {
    case truth
    case answer
}

public enum OSLogPointerFormat: Hashable, Sendable {
    case ipv6Address
    case timeval
    case timespec
    case uuid
    case sockaddr
    case none
}

// MARK: - Interpolation

public struct OSLogInterpolation: StringInterpolationProtocol {
    public typealias StringLiteralType = String

    /// One interpolated value: how to produce its text, and whether `.auto` hides it.
    struct Argument {
        let render: () -> String
        let privacy: OSLogPrivacy
        let align: OSLogStringAlignment
        /// Strings, objects, errors and pointers: private under `.auto`, as on Apple.
        let dynamic: Bool
    }

    enum Segment {
        case literal(String)
        case argument(Argument)
    }

    var segments: [Segment] = []

    public init(literalCapacity: Int, interpolationCount: Int) {
        segments.reserveCapacity(interpolationCount * 2 + 1)
    }

    public mutating func appendLiteral(_ literal: String) {
        segments.append(.literal(literal))
    }

    mutating func append(_ render: @escaping () -> String, privacy: OSLogPrivacy, align: OSLogStringAlignment = .none, dynamic: Bool) {
        segments.append(.argument(Argument(render: render, privacy: privacy, align: align, dynamic: dynamic)))
    }
}

// Error
extension OSLogInterpolation {
    public mutating func appendInterpolation(_ error: @autoclosure @escaping () -> any Error, privacy: OSLogPrivacy = .auto, attributes: String = "") {
        append({ String(describing: error()) }, privacy: privacy, dynamic: true)
    }
    public mutating func appendInterpolation(_ error: @autoclosure @escaping () -> (any Error)?, privacy: OSLogPrivacy = .auto, attributes: String = "") {
        append({ error().map { String(describing: $0) } ?? "(null)" }, privacy: privacy, dynamic: true)
    }
}

// Float and Double
extension OSLogInterpolation {
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Float, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        append({ _OSLogFormatter.formatFloat(Double(number()), format) }, privacy: privacy, align: align, dynamic: false)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Float, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto, attributes: String) {
        appendInterpolation(number(), format: format, align: align, privacy: privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Double, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        append({ _OSLogFormatter.formatFloat(number(), format) }, privacy: privacy, align: align, dynamic: false)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Double, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto, attributes: String) {
        appendInterpolation(number(), format: format, align: align, privacy: privacy)
    }
}

// Integers: Apple declares one overload per concrete type plus a generic one that
// requires `attributes:`.
extension OSLogInterpolation {
    mutating func appendInteger<T: FixedWidthInteger>(_ number: @escaping () -> T, _ format: OSLogIntegerFormatting, _ align: OSLogStringAlignment, _ privacy: OSLogPrivacy) {
        append({ _OSLogFormatter.formatInteger(number(), format) }, privacy: privacy, align: align, dynamic: false)
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int8, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int16, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int32, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int64, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt8, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt16, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt32, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt64, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        appendInteger(number, format, align, privacy)
    }
    public mutating func appendInterpolation<T>(_ number: @autoclosure @escaping () -> T, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto, attributes: String) where T: FixedWidthInteger {
        appendInteger(number, format, align, privacy)
    }
}

// NSObject
extension OSLogInterpolation {
    public mutating func appendInterpolation(_ argumentObject: @autoclosure @escaping () -> NSObject, privacy: OSLogPrivacy = .auto) {
        append({ argumentObject().description }, privacy: privacy, dynamic: true)
    }
    public mutating func appendInterpolation(_ argumentObject: @autoclosure @escaping () -> NSObject, privacy: OSLogPrivacy = .auto, attributes: String) {
        appendInterpolation(argumentObject(), privacy: privacy)
    }
    public mutating func appendInterpolation(_ object: @autoclosure @escaping () -> NSObject?, privacy: OSLogPrivacy = .auto, attributes: String = "") {
        append({ object()?.description ?? "(null)" }, privacy: privacy, dynamic: true)
    }
}

// Pointers
extension OSLogInterpolation {
    public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawBufferPointer, format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto) {
        append({ _OSLogFormatter.formatPointer(pointer(), format) }, privacy: privacy, dynamic: true)
    }
    public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawBufferPointer, format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto, attributes: String) {
        appendInterpolation(pointer(), format: format, privacy: privacy)
    }
    public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawPointer, bytes: @autoclosure @escaping () -> Int, format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto) {
        append({ _OSLogFormatter.formatPointer(UnsafeRawBufferPointer(start: pointer(), count: bytes()), format) }, privacy: privacy, dynamic: true)
    }
    public mutating func appendInterpolation(_ pointer: @autoclosure @escaping () -> UnsafeRawPointer, bytes: @autoclosure @escaping () -> Int, format: OSLogPointerFormat = .none, privacy: OSLogPrivacy = .auto, attributes: String) {
        appendInterpolation(pointer(), bytes: bytes(), format: format, privacy: privacy)
    }
}

// Bool
extension OSLogInterpolation {
    public mutating func appendInterpolation(_ boolean: @autoclosure @escaping () -> Bool, format: OSLogBoolFormat = .truth, privacy: OSLogPrivacy = .auto) {
        append({
            switch format {
            case .truth: return boolean() ? "true" : "false"
            case .answer: return boolean() ? "YES" : "NO"
            }
        }, privacy: privacy, dynamic: false)
    }
}

// String
extension OSLogInterpolation {
    public mutating func appendInterpolation(_ argumentString: @autoclosure @escaping () -> String, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        append(argumentString, privacy: privacy, align: align, dynamic: true)
    }
    public mutating func appendInterpolation(_ argumentString: @autoclosure @escaping () -> String, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto, attributes: String) {
        appendInterpolation(argumentString(), align: align, privacy: privacy)
    }
}

// CustomStringConvertible and metatypes
extension OSLogInterpolation {
    public mutating func appendInterpolation<T>(_ value: @autoclosure @escaping () -> T, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) where T: CustomStringConvertible {
        append({ value().description }, privacy: privacy, align: align, dynamic: true)
    }
    public mutating func appendInterpolation<T>(_ value: @autoclosure @escaping () -> T, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto, attributes: String) where T: CustomStringConvertible {
        appendInterpolation(value(), align: align, privacy: privacy)
    }
    public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Any.Type, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        append({ String(describing: value()) }, privacy: privacy, align: align, dynamic: true)
    }
    public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> any Any.Type, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto, attributes: String) {
        appendInterpolation(value(), align: align, privacy: privacy)
    }
}

// MARK: - Message

public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    public typealias StringInterpolation = OSLogInterpolation
    public typealias StringLiteralType = String
    public typealias ExtendedGraphemeClusterLiteralType = String
    public typealias UnicodeScalarLiteralType = String

    public let interpolation: OSLogInterpolation

    public init(stringInterpolation: OSLogInterpolation) {
        interpolation = stringInterpolation
    }

    public init(stringLiteral value: String) {
        var interpolation = OSLogInterpolation(literalCapacity: value.utf8.count, interpolationCount: 0)
        interpolation.appendLiteral(value)
        self.interpolation = interpolation
    }

    /// Apple's encoded buffer size: a two-byte header plus a two-byte descriptor and an
    /// eight-byte payload per argument.
    public var bufferSize: Int {
        let arguments = interpolation.segments.reduce(0) { count, segment in
            if case .argument = segment { return count + 1 }
            return count
        }
        return 2 + arguments * 10
    }
}
