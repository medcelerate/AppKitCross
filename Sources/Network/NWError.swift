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

// `POSIXErrorCode` comes from the C library overlay (Darwin, Glibc). On Windows
// swift-corelibs-foundation declares one too, but it stops at the file-system errors: none
// of the socket codes (`ECONNREFUSED`, `ETIMEDOUT`, `EADDRINUSE`, ...) exist, so `NWError`
// could not carry them. This module therefore declares its own `POSIXErrorCode` there, the
// full ucrt `errno.h` numbering (what the C runtime's `errno` and `strerror` use), and
// `NWError.posix` carries it, as Apple's carries Darwin's. A file that imports both
// Foundation and Network and spells the bare type name sees an ambiguity on Windows;
// `NWError.posix(let code)` and `code.rawValue` work everywhere. `DNSServiceErrorType` and
// `OSStatus` come from dnssd and MacTypes on Apple platforms; elsewhere they are declared
// here with Apple's underlying types.
#if os(Windows)
public enum POSIXErrorCode: Int32, Sendable, Hashable {
    case EPERM = 1, ENOENT = 2, ESRCH = 3, EINTR = 4, EIO = 5, ENXIO = 6, E2BIG = 7, ENOEXEC = 8
    case EBADF = 9, ECHILD = 10, EAGAIN = 11, ENOMEM = 12, EACCES = 13, EFAULT = 14, EBUSY = 16
    case EEXIST = 17, EXDEV = 18, ENODEV = 19, ENOTDIR = 20, EISDIR = 21, EINVAL = 22, ENFILE = 23
    case EMFILE = 24, ENOTTY = 25, EFBIG = 27, ENOSPC = 28, ESPIPE = 29, EROFS = 30, EMLINK = 31
    case EPIPE = 32, EDOM = 33, ERANGE = 34, EDEADLK = 36, ENAMETOOLONG = 38, ENOLCK = 39
    case ENOSYS = 40, ENOTEMPTY = 41, EILSEQ = 42, STRUNCATE = 80
    case EADDRINUSE = 100, EADDRNOTAVAIL = 101, EAFNOSUPPORT = 102, EALREADY = 103, EBADMSG = 104
    case ECANCELED = 105, ECONNABORTED = 106, ECONNREFUSED = 107, ECONNRESET = 108
    case EDESTADDRREQ = 109, EHOSTUNREACH = 110, EIDRM = 111, EINPROGRESS = 112, EISCONN = 113
    case ELOOP = 114, EMSGSIZE = 115, ENETDOWN = 116, ENETRESET = 117, ENETUNREACH = 118
    case ENOBUFS = 119, ENODATA = 120, ENOLINK = 121, ENOMSG = 122, ENOPROTOOPT = 123, ENOSR = 124
    case ENOSTR = 125, ENOTCONN = 126, ENOTRECOVERABLE = 127, ENOTSOCK = 128, ENOTSUP = 129
    case EOPNOTSUPP = 130, EOTHER = 131, EOVERFLOW = 132, EOWNERDEAD = 133, EPROTO = 134
    case EPROTONOSUPPORT = 135, EPROTOTYPE = 136, ETIME = 137, ETIMEDOUT = 138, ETXTBSY = 139
    case EWOULDBLOCK = 140
}
#endif
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
