import Foundation
#if canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
import ucrt
#elseif canImport(Darwin)
import Darwin
#endif
#if canImport(dnssd)
import dnssd
#endif

// `POSIXErrorCode` comes from the C library overlay (Darwin, Glibc) or Foundation
// (Windows). `DNSServiceErrorType` and `OSStatus` come from dnssd and MacTypes on Apple
// platforms; elsewhere they are declared here with Apple's underlying types.
#if !canImport(dnssd)
public typealias DNSServiceErrorType = Int32
#endif
#if !canImport(Darwin)
public typealias OSStatus = Int32
#endif

/// Errors reported by connections, listeners and browsers.
public enum NWError: Error, CustomDebugStringConvertible, Equatable {
    /// A POSIX error from the socket layer.
    case posix(POSIXErrorCode)
    /// A DNS or DNS-SD error (`kDNSServiceErr_*`).
    case dns(DNSServiceErrorType)
    /// A TLS error. This port has no TLS, so it never reports one.
    case tls(OSStatus)

    public var debugDescription: String {
        switch self {
        case .posix(let code):
            return "POSIXErrorCode(rawValue: \(code.rawValue)): \(_posixMessage(code))"
        case .dns(let code):
            return "\(code): \(_DNSServiceError.name(code))"
        case .tls(let status):
            return "\(status): TLS error"
        }
    }

    public static func == (a: NWError, b: NWError) -> Bool {
        switch (a, b) {
        case (.posix(let x), .posix(let y)): return x == y
        case (.dns(let x), .dns(let y)): return x == y
        case (.tls(let x), .tls(let y)): return x == y
        default: return false
        }
    }
}

extension NWError: CustomNSError {
    public static var errorDomain: String { "Network.NWError" }

    public var errorCode: Int {
        switch self {
        case .posix(let code): return Int(code.rawValue)
        case .dns(let code): return Int(code)
        case .tls(let status): return Int(status)
        }
    }

    public var errorUserInfo: [String: Any] {
        [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (Network.NWError error \(errorCode) - \(_shortMessage))"]
    }

    private var _shortMessage: String {
        switch self {
        case .posix(let code): return _posixMessage(code)
        case .dns(let code): return _DNSServiceError.name(code)
        case .tls: return "TLS error"
        }
    }
}

/// `kDNSServiceErr_*` values (dns_sd.h) used by this module, and their names.
enum _DNSServiceError {
    static let unknown: DNSServiceErrorType = -65537
    static let noSuchName: DNSServiceErrorType = -65538
    static let badParam: DNSServiceErrorType = -65540
    static let nameConflict: DNSServiceErrorType = -65548
    static let noSuchRecord: DNSServiceErrorType = -65554
    static let serviceNotRunning: DNSServiceErrorType = -65563
    static let timeout: DNSServiceErrorType = -65568

    static func name(_ code: DNSServiceErrorType) -> String {
        switch code {
        case 0: return "NoError"
        case -65537: return "Unknown"
        case -65538: return "NoSuchName"
        case -65539: return "NoMemory"
        case -65540: return "BadParam"
        case -65541: return "BadReference"
        case -65542: return "BadState"
        case -65543: return "BadFlags"
        case -65544: return "Unsupported"
        case -65545: return "NotInitialized"
        case -65547: return "AlreadyRegistered"
        case -65548: return "NameConflict"
        case -65549: return "Invalid"
        case -65550: return "Firewall"
        case -65551: return "Incompatible"
        case -65552: return "BadInterfaceIndex"
        case -65553: return "Refused"
        case -65554: return "NoSuchRecord"
        case -65555: return "NoAuth"
        case -65556: return "NoSuchKey"
        case -65562: return "Transient"
        case -65563: return "ServiceNotRunning"
        case -65568: return "Timeout"
        default: return "DNSServiceErrorType \(code)"
        }
    }
}

/// The C library's message for a POSIX error code.
func _posixMessage(_ code: POSIXErrorCode) -> String {
    #if os(Windows)
    // Foundation's Windows `POSIXErrorCode` numbering need not match the CRT's, so name
    // the codes this module produces instead of asking `strerror`.
    switch code {
    case .ECONNREFUSED: return "Connection refused"
    case .ECONNRESET: return "Connection reset by peer"
    case .ECONNABORTED: return "Software caused connection abort"
    case .ETIMEDOUT: return "Operation timed out"
    case .EADDRINUSE: return "Address already in use"
    case .EADDRNOTAVAIL: return "Can't assign requested address"
    case .ENETUNREACH: return "Network is unreachable"
    case .EHOSTUNREACH: return "No route to host"
    case .ENETDOWN: return "Network is down"
    case .ENOTCONN: return "Socket is not connected"
    case .EMSGSIZE: return "Message too long"
    case .ECANCELED: return "Operation canceled"
    case .EINVAL: return "Invalid argument"
    case .EACCES: return "Permission denied"
    case .EPIPE: return "Broken pipe"
    case .EAFNOSUPPORT: return "Address family not supported by protocol family"
    default: return "POSIX error \(code.rawValue)"
    }
    #else
    return String(cString: strerror(code.rawValue))
    #endif
}
