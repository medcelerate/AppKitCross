// Rendering and output. The formatting is pure (`_OSLogFormatter`) so tests can check the
// text; `_OSLogOutput` decides visibility and writes the line.

import Foundation
#if os(Windows)
import WinSDK
#endif

// MARK: - Configuration

/// The environment-driven switches (read once; tests override them through `_OSLogTestHooks`).
///
/// - `APPKITWIN_LOG_LEVEL`: `debug`, `info`, `notice` (the default; `default` is accepted
///   too), `error` or `fault`. Messages below it are dropped without evaluating their
///   interpolations, like the default visibility of `log stream`.
/// - `APPKITWIN_LOG_PRIVATE=1`: print private and sensitive values instead of `<private>`.
struct _OSLogConfiguration: Sendable {
    /// Severity rank: debug 0, info 1, default/notice 2, error 3, fault 4.
    var minimumRank: Int
    var revealPrivate: Bool

    static func fromEnvironment() -> _OSLogConfiguration {
        let env = ProcessInfo.processInfo.environment
        let rank: Int
        switch env["APPKITWIN_LOG_LEVEL"]?.lowercased() {
        case "debug", "trace": rank = 0
        case "info": rank = 1
        case "error", "warning": rank = 3
        case "fault", "critical": rank = 4
        default: rank = 2
        }
        return _OSLogConfiguration(minimumRank: rank, revealPrivate: env["APPKITWIN_LOG_PRIVATE"] == "1")
    }

    static func rank(of type: OSLogType) -> Int {
        switch type {
        case .debug: return 0
        case .info: return 1
        case .error: return 3
        case .fault: return 4
        default: return 2
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current = fromEnvironment()

    static var current: _OSLogConfiguration {
        get { lock.lock(); defer { lock.unlock() }; return _current }
        set { lock.lock(); _current = newValue; lock.unlock() }
    }

    static func isEnabled(_ type: OSLogType) -> Bool {
        rank(of: type) >= current.minimumRank
    }
}

// MARK: - Formatter

enum _OSLogFormatter {
    /// The message text with privacy, alignment and formats applied.
    static func render(message: OSLogMessage, revealPrivate: Bool? = nil) -> String {
        let reveal = revealPrivate ?? _OSLogConfiguration.current.revealPrivate
        var text = ""
        for segment in message.interpolation.segments {
            switch segment {
            case .literal(let literal):
                text += literal
            case .argument(let argument):
                text += align(redact(argument, reveal: reveal), argument.align)
            }
        }
        return text
    }

    static func redact(_ argument: OSLogInterpolation.Argument, reveal: Bool) -> String {
        let hidden: Bool
        switch argument.privacy.option {
        case .public: hidden = false
        case .private, .sensitive: hidden = true
        case .auto: hidden = argument.dynamic
        }
        if !hidden || reveal { return argument.render() }
        if argument.privacy.mask == .hash {
            return "<mask.hash: '\(hashMask(argument.render()))'>"
        }
        return "<private>"
    }

    /// A stable, salt-free digest standing in for Apple's per-boot salted hash.
    static func hashMask(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return withUnsafeBytes(of: hash.bigEndian) { Data($0).base64EncodedString() }
    }

    static func align(_ text: String, _ alignment: OSLogStringAlignment) -> String {
        guard let columns = alignment.columns?() else { return text }
        let padding = columns - text.count
        guard padding > 0 else { return text }
        let spaces = String(repeating: " ", count: padding)
        return alignment.leftAligned ? text + spaces : spaces + text
    }

    static func formatInteger<T: FixedWidthInteger>(_ value: T, _ format: OSLogIntegerFormatting) -> String {
        var digits: String
        var negative = false
        switch format.radix {
        case .decimal:
            negative = value < 0
            digits = String(value.magnitude)
        case .hex, .octal:
            // printf's %x/%o print the two's-complement bits of the argument's width.
            let bits = UInt64(truncatingIfNeeded: value) & (T.bitWidth >= 64 ? .max : (UInt64(1) << T.bitWidth) - 1)
            digits = String(bits, radix: format.radix == .hex ? 16 : 8, uppercase: format.uppercase)
        }
        if let minDigits = format.minDigits?(), digits.count < minDigits {
            digits = String(repeating: "0", count: minDigits - digits.count) + digits
        }
        if format.includePrefix {
            switch format.radix {
            case .hex where value != 0: digits = (format.uppercase ? "0X" : "0x") + digits
            case .octal where !digits.hasPrefix("0"): digits = "0" + digits
            default: break
            }
        }
        if negative { return "-" + digits }
        if format.explicitPositiveSign && format.radix == .decimal { return "+" + digits }
        return digits
    }

    static func formatFloat(_ value: Double, _ format: OSLogFloatFormatting) -> String {
        var spec = "%"
        if format.explicitPositiveSign { spec += "+" }
        if let precision = format.precision?() { spec += ".\(max(0, precision))" }
        let conversion: String
        switch format.notation {
        case .fixed: conversion = "f"
        case .exponential: conversion = "e"
        case .hybrid: conversion = "g"
        case .hex: conversion = "a"
        }
        spec += format.uppercase ? conversion.uppercased() : conversion
        return String(format: spec, value)
    }

    static func formatPointer(_ buffer: UnsafeRawBufferPointer, _ format: OSLogPointerFormat) -> String {
        guard let base = buffer.baseAddress else { return "(null)" }
        let bytes = Array(buffer)
        switch format {
        case .uuid where bytes.count == 16:
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString
        case .ipv6Address where bytes.count == 16:
            return stride(from: 0, to: 16, by: 2).map { String(UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]), radix: 16) }.joined(separator: ":")
        default:
            if bytes.isEmpty { return String(format: "%p", Int(bitPattern: base)) }
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    static func levelName(_ type: OSLogType) -> String {
        switch type {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "NOTICE"
        }
    }

    /// The full output line (without the trailing newline).
    static func line(_ text: String, type: OSLogType, log: OSLog, date: Date = Date()) -> String {
        let time = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current))
        let info = ProcessInfo.processInfo
        var line = "\(time) \(info.processName)[\(info.processIdentifier)] "
        if !log.subsystem.isEmpty || !log.category.isEmpty {
            line += "[\(log.subsystem):\(log.category)] "
        }
        return line + "\(levelName(type)) \(text)"
    }

    // MARK: os_log format strings

    /// Renders a printf-style `os_log` format: `{public}`/`{private}`/`{sensitive}` decorate
    /// a specifier; `%@` and `%s` are private by default, scalars public, as on Apple.
    static func renderFormat(_ format: String, _ args: [any CVarArg], revealPrivate: Bool) -> String {
        var output = ""
        var argIndex = 0
        let chars = Array(format)
        var i = 0
        func nextArg() -> (any CVarArg)? {
            defer { argIndex += 1 }
            return argIndex < args.count ? args[argIndex] : nil
        }
        while i < chars.count {
            let c = chars[i]
            guard c == "%" else { output.append(c); i += 1; continue }
            i += 1
            guard i < chars.count else { output.append("%"); break }
            if chars[i] == "%" { output.append("%"); i += 1; continue }
            var privacy = ""
            if chars[i] == "{" {
                var j = i + 1
                while j < chars.count && chars[j] != "}" { j += 1 }
                privacy = String(chars[(i + 1)..<min(j, chars.count)])
                i = min(j + 1, chars.count)
            }
            var spec = "%"
            while i < chars.count, "-+ #0'0123456789.*hlqLjzt".contains(chars[i]) {
                if chars[i] != "'" { spec.append(chars[i]) }
                i += 1
            }
            guard i < chars.count else { output += spec; break }
            let conversion = chars[i]
            i += 1
            let arg = nextArg()
            let dynamic = conversion == "@" || conversion == "s" || conversion == "S"
            let options = privacy.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let hidden = options.contains("private") || options.contains("sensitive") || (dynamic && !options.contains("public"))
            if hidden && !revealPrivate { output += "<private>"; continue }
            guard let arg else { output += "(null)"; continue }
            if conversion == "@" {
                output += String(describing: arg)
            } else if conversion == "s", let string = arg as? String {
                output += string
            } else {
                spec.append(conversion)
                output += String(format: spec, arg)
            }
        }
        return output
    }
}

// MARK: - Output

enum _OSLogOutput {
    private static let lock = NSLock()
    /// Test hook: when set, lines go here instead of stderr.
    nonisolated(unsafe) static var sink: ((String) -> Void)?

    static func emit(_ message: OSLogMessage, type: OSLogType, log: OSLog) {
        guard log.isEnabled(type: type) else { return }
        write(_OSLogFormatter.line(_OSLogFormatter.render(message: message), type: type, log: log))
    }

    static func emitFormat(_ format: StaticString, _ args: [any CVarArg], type: OSLogType, log: OSLog) {
        guard log.isEnabled(type: type) else { return }
        let text = _OSLogFormatter.renderFormat(format.description, args, revealPrivate: _OSLogConfiguration.current.revealPrivate)
        write(_OSLogFormatter.line(text, type: type, log: log))
    }

    static func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        if let sink {
            sink(line)
            return
        }
        FileHandle.standardError.write(Data((line + "\n").utf8))
        #if os(Windows)
        (line + "\n").withCString(encodedAs: UTF16.self) { OutputDebugStringW($0) }
        #endif
    }
}

/// Internal switches for the tests.
enum _OSLogTestHooks {
    static var configuration: _OSLogConfiguration {
        get { _OSLogConfiguration.current }
        set { _OSLogConfiguration.current = newValue }
    }

    static func capture(_ body: () -> Void) -> [String] {
        var lines: [String] = []
        let box = NSLock()
        _OSLogOutput.sink = { line in box.lock(); lines.append(line); box.unlock() }
        body()
        _OSLogOutput.sink = nil
        return lines
    }
}
