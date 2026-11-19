// OSLog for Windows and Linux (ADR-0050): Apple's unified-logging Swift API under its own
// names, writing one line per message instead of feeding a log store.
//
// Coverage: `Logger` (all initializers and level methods), `OSLog` (`init(subsystem:category:)`,
// `OSLog.Category`, `.default`, `.disabled`, `isEnabled(type:)`), `OSLogType`, `OSLogMessage`
// and `OSLogInterpolation` with Apple's overloads for String, every concrete integer type,
// Float/Double, Bool, CustomStringConvertible, NSObject, Error, `Any.Type` and raw pointers,
// plus the formatting types (`OSLogPrivacy`, `OSLogStringAlignment`, `OSLogIntegerFormatting`,
// `OSLogFloatFormatting`, `OSLogBoolFormat`, `OSLogPointerFormat`) and `os_log` in its
// `StaticString` + `CVarArg` and `OSLogMessage` forms.
//
// Output: `<ISO8601 time> <process>[<pid>] [<subsystem>:<category>] <LEVEL> <message>` on
// stderr (Windows: also `OutputDebugStringW`, visible in a debugger or DebugView).
// Visibility follows `log stream`'s default: debug and info messages are dropped unless
// `APPKITWIN_LOG_LEVEL=debug` or `=info` (also accepted: `notice`/`default`, `error`, `fault`).
// Privacy follows Apple: `.private`/`.sensitive` values and `.auto` dynamic values (strings,
// objects, errors, pointers) print as `<private>` unless `APPKITWIN_LOG_PRIVATE=1`.
// Interpolated values are autoclosures evaluated only when the level is enabled.
//
// Limitations: no log store (`OSLogStore`, `OSLogEntry` are absent), no signposts
// (`OSSignposter`, `os_signpost`), no `OSLogInt32ExtendedFormat`/`OSLogIntExtendedFormat`
// overloads; `trace` logs as debug, `warning` as error, `critical` as fault, as on Apple.

import Foundation

/// The C `os_log_type_t`, imported by Swift as `OSLogType`.
public struct OSLogType: Hashable, Equatable, RawRepresentable, Sendable {
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public var rawValue: UInt8
}

extension OSLogType {
    public static let `default` = OSLogType(0x00)
    public static let info = OSLogType(0x01)
    public static let debug = OSLogType(0x02)
    public static let error = OSLogType(0x10)
    public static let fault = OSLogType(0x11)
}

/// A log object: a subsystem and category pair, or one of the two shared objects.
open class OSLog: NSObject, @unchecked Sendable {
    let subsystem: String
    let category: String
    let isDisabled: Bool

    init(subsystem: String, category: String, disabled: Bool) {
        self.subsystem = subsystem
        self.category = category
        self.isDisabled = disabled
        super.init()
    }

    public static let disabled = OSLog(subsystem: "", category: "", disabled: true)
    public static let `default` = OSLog(subsystem: "", category: "", disabled: false)

    public convenience init(subsystem: String, category: String) {
        self.init(subsystem: subsystem, category: category, disabled: false)
    }

    public struct Category: Sendable {
        public let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        public static let pointsOfInterest = Category(rawValue: "PointsOfInterest")
        public static let dynamicTracing = Category(rawValue: "DynamicTracing")
        public static let dynamicStackTracing = Category(rawValue: "DynamicStackTracing")
    }

    public convenience init(subsystem: String, category: OSLog.Category) {
        self.init(subsystem: subsystem, category: category.rawValue, disabled: false)
    }

    /// Whether a message of `type` is written (see the file header for the environment).
    public func isEnabled(type: OSLogType) -> Bool {
        !isDisabled && _OSLogConfiguration.isEnabled(type)
    }

    open override var description: String {
        isDisabled ? "<OS_os_log: disabled>" : "<OS_os_log: \(subsystem):\(category)>"
    }
}

/// Apple's `Logger`: a value naming a subsystem and category with one method per level.
public struct Logger: @unchecked Sendable {
    let logObject: OSLog

    public init(subsystem: String, category: String) {
        logObject = OSLog(subsystem: subsystem, category: category)
    }

    public init() {
        logObject = .default
    }

    public init(_ logObj: OSLog) {
        logObject = logObj
    }

    public func log(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .default, log: logObject) }
    public func log(level: OSLogType, _ message: OSLogMessage) { _OSLogOutput.emit(message, type: level, log: logObject) }
    public func trace(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .debug, log: logObject) }
    public func debug(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .debug, log: logObject) }
    public func info(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .info, log: logObject) }
    public func notice(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .default, log: logObject) }
    public func warning(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .error, log: logObject) }
    public func error(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .error, log: logObject) }
    public func critical(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .fault, log: logObject) }
    public func fault(_ message: OSLogMessage) { _OSLogOutput.emit(message, type: .fault, log: logObject) }
}

// MARK: - os_log

public func os_log(_ type: OSLogType, dso: UnsafeRawPointer = #dsohandle, log: OSLog = .default, _ message: StaticString, _ args: any CVarArg...) {
    _OSLogOutput.emitFormat(message, args, type: type, log: log)
}

public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = #dsohandle, log: OSLog = .default, type: OSLogType = .default, _ args: any CVarArg...) {
    _OSLogOutput.emitFormat(message, args, type: type, log: log)
}

public func os_log(_ message: OSLogMessage) {
    _OSLogOutput.emit(message, type: .default, log: .default)
}

public func os_log(_ logLevel: OSLogType = .default, log logObject: OSLog = .default, _ message: OSLogMessage) {
    _OSLogOutput.emit(message, type: logLevel, log: logObject)
}
