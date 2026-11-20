// The socket layer: BSD sockets on Linux and macOS, Winsock 2 on Windows. Everything
// above this file speaks `NativeSocket`, `SocketAddress`, `SocketError` and `Sock`.

import Foundation
#if canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
import ucrt
#elseif canImport(Darwin)
import Darwin
#endif

extension NSLock {
    @inline(__always)
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// MARK: - Handles and constants

#if os(Windows)
typealias NativeSocket = SOCKET
let kInvalidSocket: SOCKET = ~SOCKET(0)
typealias SockLen = Int32

// Winsock values (winsock2.h, ws2def.h, ws2ipdef.h). Spelled out because several are
// enum members or cast macros that do not import as plain integers.
let kAF_INET: Int32 = 2
let kAF_INET6: Int32 = 23
let kSOCK_STREAM: Int32 = 1
let kSOCK_DGRAM: Int32 = 2
let kIPPROTO_IP: Int32 = 0
let kIPPROTO_TCP: Int32 = 6
let kIPPROTO_UDP: Int32 = 17
let kIPPROTO_IPV6: Int32 = 41
let kSOL_SOCKET: Int32 = 0xFFFF
let kSO_REUSEADDR: Int32 = 0x0004
let kSO_KEEPALIVE: Int32 = 0x0008
let kSO_LINGER: Int32 = 0x0080
let kSO_ERROR: Int32 = 0x1007
let kTCP_NODELAY: Int32 = 0x0001
let kTCP_KEEPIDLE: Int32 = 3
let kTCP_KEEPCNT: Int32 = 16
let kTCP_KEEPINTVL: Int32 = 17
let kIPV6_V6ONLY: Int32 = 27
let kIP_MULTICAST_IF: Int32 = 9
let kIP_MULTICAST_TTL: Int32 = 10
let kIP_MULTICAST_LOOP: Int32 = 11
let kIP_ADD_MEMBERSHIP: Int32 = 12
let kSHUT_WR: Int32 = 1 // SD_SEND
let kPOLLIN: Int16 = 0x0100 // POLLRDNORM; WSAPoll rejects POLLPRI
let kPOLLOUT: Int16 = 0x0010 // POLLWRNORM
let kPOLLERR: Int16 = 0x0001
let kPOLLHUP: Int16 = 0x0002
let kPOLLNVAL: Int16 = 0x0004
let kFIONBIO = Int32(bitPattern: 0x8004_667E)
#else
typealias NativeSocket = Int32
let kInvalidSocket: Int32 = -1
typealias SockLen = socklen_t

let kAF_INET = Int32(AF_INET)
let kAF_INET6 = Int32(AF_INET6)
#if canImport(Glibc)
let kSOCK_STREAM = Int32(SOCK_STREAM.rawValue)
let kSOCK_DGRAM = Int32(SOCK_DGRAM.rawValue)
#else
let kSOCK_STREAM = SOCK_STREAM
let kSOCK_DGRAM = SOCK_DGRAM
#endif
let kIPPROTO_IP = Int32(IPPROTO_IP)
let kIPPROTO_TCP = Int32(IPPROTO_TCP)
let kIPPROTO_UDP = Int32(IPPROTO_UDP)
let kIPPROTO_IPV6 = Int32(IPPROTO_IPV6)
let kSOL_SOCKET = Int32(SOL_SOCKET)
let kSO_REUSEADDR = Int32(SO_REUSEADDR)
let kSO_REUSEPORT = Int32(SO_REUSEPORT)
let kSO_KEEPALIVE = Int32(SO_KEEPALIVE)
let kSO_LINGER = Int32(SO_LINGER)
let kSO_ERROR = Int32(SO_ERROR)
let kTCP_NODELAY = Int32(TCP_NODELAY)
#if canImport(Darwin)
let kTCP_KEEPIDLE = Int32(TCP_KEEPALIVE)
#else
let kTCP_KEEPIDLE = Int32(TCP_KEEPIDLE)
#endif
let kTCP_KEEPCNT = Int32(TCP_KEEPCNT)
let kTCP_KEEPINTVL = Int32(TCP_KEEPINTVL)
let kIPV6_V6ONLY = Int32(IPV6_V6ONLY)
let kIP_MULTICAST_IF = Int32(IP_MULTICAST_IF)
let kIP_MULTICAST_TTL = Int32(IP_MULTICAST_TTL)
let kIP_MULTICAST_LOOP = Int32(IP_MULTICAST_LOOP)
let kIP_ADD_MEMBERSHIP = Int32(IP_ADD_MEMBERSHIP)
let kSHUT_WR = Int32(SHUT_WR)
let kPOLLIN = Int16(POLLIN)
let kPOLLOUT = Int16(POLLOUT)
let kPOLLERR = Int16(POLLERR)
let kPOLLHUP = Int16(POLLHUP)
let kPOLLNVAL = Int16(POLLNVAL)
#endif

// MARK: - Errors

/// A failed socket call: the platform error and its POSIX equivalent.
struct SocketError: Error {
    let code: POSIXErrorCode
    let wouldBlock: Bool
    let inProgress: Bool
    let interrupted: Bool

    var nwError: NWError { .posix(code) }

    /// The error of the last failed socket call on this thread.
    static func last() -> SocketError {
        #if os(Windows)
        return SocketError(winsock: WSAGetLastError())
        #else
        return SocketError(errno: errno)
        #endif
    }

    #if os(Windows)
    init(winsock value: Int32) {
        wouldBlock = value == 10035 // WSAEWOULDBLOCK
        inProgress = value == 10035 || value == 10036 || value == 10037 // WOULDBLOCK, INPROGRESS, ALREADY
        interrupted = value == 10004 // WSAEINTR
        switch value {
        case 10004: code = .EINTR
        case 10013: code = .EACCES
        case 10014: code = .EFAULT
        case 10022: code = .EINVAL
        case 10024: code = .EMFILE
        case 10035: code = .EWOULDBLOCK
        case 10036: code = .EINPROGRESS
        case 10037: code = .EALREADY
        case 10038: code = .ENOTSOCK
        case 10040: code = .EMSGSIZE
        case 10047: code = .EAFNOSUPPORT
        case 10048: code = .EADDRINUSE
        case 10049: code = .EADDRNOTAVAIL
        case 10050: code = .ENETDOWN
        case 10051: code = .ENETUNREACH
        case 10052: code = .ENETRESET
        case 10053: code = .ECONNABORTED
        case 10054: code = .ECONNRESET
        case 10055: code = .ENOBUFS
        case 10056: code = .EISCONN
        case 10057: code = .ENOTCONN
        case 10058: code = .EPIPE // WSAESHUTDOWN
        case 10060: code = .ETIMEDOUT
        case 10061: code = .ECONNREFUSED
        case 10064, 10065: code = .EHOSTUNREACH // WSAEHOSTDOWN, WSAEHOSTUNREACH
        default: code = .EIO
        }
    }
    #else
    init(errno value: Int32) {
        code = POSIXErrorCode(rawValue: value) ?? .EIO
        wouldBlock = value == EAGAIN || value == EWOULDBLOCK
        inProgress = value == EINPROGRESS || value == EALREADY
        interrupted = value == EINTR
    }
    #endif

    init(_ code: POSIXErrorCode) {
        self.code = code
        wouldBlock = false
        inProgress = false
        interrupted = false
    }
}

/// The outcome of a non-blocking read or write.
enum IOResult {
    case done(Int)
    case wouldBlock
    case failed(SocketError)
}

// MARK: - Addresses

/// An IPv4 or IPv6 socket address as plain values.
struct SocketAddress: Hashable, Sendable, CustomStringConvertible {
    let family: Int32
    let bytes: [UInt8]
    let port: UInt16
    let scopeID: UInt32

    init(ipv4 bytes: [UInt8], port: UInt16) {
        precondition(bytes.count == 4)
        family = kAF_INET
        self.bytes = bytes
        self.port = port
        scopeID = 0
    }

    init(ipv6 bytes: [UInt8], port: UInt16, scopeID: UInt32 = 0) {
        precondition(bytes.count == 16)
        family = kAF_INET6
        self.bytes = bytes
        self.port = port
        self.scopeID = scopeID
    }

    /// The address for an `NWEndpoint.Host` literal; nil for names.
    init?(host: NWEndpoint.Host, port: UInt16) {
        switch host {
        case .ipv4(let address): self.init(ipv4: address._bytes, port: port)
        case .ipv6(let address): self.init(ipv6: address._bytes, port: port, scopeID: UInt32(address.interface?.index ?? 0))
        case .name: return nil
        }
    }

    init?(_ address: UnsafePointer<sockaddr>) {
        let family = Int32(address.pointee.sa_family)
        if family == kAF_INET {
            let parsed: SocketAddress = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                var value = pointer.pointee
                let offset = MemoryLayout<sockaddr_in>.offset(of: \sockaddr_in.sin_addr)!
                let bytes = withUnsafeBytes(of: &value) { Array($0[offset..<(offset + 4)]) }
                return SocketAddress(ipv4: bytes, port: UInt16(bigEndian: value.sin_port))
            }
            self = parsed
        } else if family == kAF_INET6 {
            let parsed: SocketAddress = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                var value = pointer.pointee
                let offset = MemoryLayout<sockaddr_in6>.offset(of: \sockaddr_in6.sin6_addr)!
                let bytes = withUnsafeBytes(of: &value) { Array($0[offset..<(offset + 16)]) }
                return SocketAddress(ipv6: bytes, port: UInt16(bigEndian: value.sin6_port), scopeID: UInt32(value.sin6_scope_id))
            }
            self = parsed
        } else {
            return nil
        }
    }

    /// Calls `body` with this address as a `sockaddr`.
    func withSockAddr<R>(_ body: (UnsafePointer<sockaddr>, SockLen) -> R) -> R {
        if family == kAF_INET {
            var value = sockaddr_in()
            #if canImport(Darwin)
            value.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            #endif
            value.sin_family = numericCast(kAF_INET)
            value.sin_port = port.bigEndian
            let offset = MemoryLayout<sockaddr_in>.offset(of: \sockaddr_in.sin_addr)!
            withUnsafeMutableBytes(of: &value) { raw in
                for index in 0..<4 { raw[offset + index] = bytes[index] }
            }
            return withUnsafePointer(to: &value) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, SockLen(MemoryLayout<sockaddr_in>.size)) }
            }
        } else {
            var value = sockaddr_in6()
            #if canImport(Darwin)
            value.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            #endif
            value.sin6_family = numericCast(kAF_INET6)
            value.sin6_port = port.bigEndian
            value.sin6_scope_id = numericCast(scopeID)
            let offset = MemoryLayout<sockaddr_in6>.offset(of: \sockaddr_in6.sin6_addr)!
            withUnsafeMutableBytes(of: &value) { raw in
                for index in 0..<16 { raw[offset + index] = bytes[index] }
            }
            return withUnsafePointer(to: &value) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, SockLen(MemoryLayout<sockaddr_in6>.size)) }
            }
        }
    }

    var host: NWEndpoint.Host {
        if family == kAF_INET { return .ipv4(IPv4Address(_bytes: bytes)) }
        let interface = scopeID == 0 ? nil : Sock.interfaceName(index: Int(scopeID)).map {
            NWInterface(name: $0, index: Int(scopeID), type: .other)
        }
        let v6 = IPv6Address(_bytes: bytes, interface: interface)
        if v6.isIPv4Mapped, let v4 = v6.asIPv4 { return .ipv4(v4) }
        return .ipv6(v6)
    }

    var endpoint: NWEndpoint {
        .hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
    }

    func withPort(_ port: UInt16) -> SocketAddress {
        family == kAF_INET ? SocketAddress(ipv4: bytes, port: port) : SocketAddress(ipv6: bytes, port: port, scopeID: scopeID)
    }

    /// Loopback, link-local and private-use addresses (RFC 1918, RFC 4193).
    var isLocalNetwork: Bool {
        var v4 = family == kAF_INET ? bytes : nil
        if family == kAF_INET6 {
            let v6 = IPv6Address(_bytes: bytes)
            if v6.isLoopback || v6.isLinkLocal || v6.isUniqueLocal { return true }
            v4 = v6.isIPv4Mapped ? Array(bytes[12..<16]) : nil
        }
        guard let b = v4 else { return false }
        return b[0] == 127 || b[0] == 10 || (b[0] == 172 && b[1] & 0xF0 == 16)
            || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254)
    }

    var description: String { endpoint.debugDescription }
}

/// An IPv4 interface address that can carry multicast.
struct LocalInterface: Equatable {
    let name: String
    let index: Int
    let ipv4: [UInt8]
    let isLoopback: Bool
}

// MARK: - Calls

/// Thin wrappers over the socket calls. Every socket is created non-blocking-capable;
/// callers set non-blocking mode explicitly.
enum Sock {
    #if os(Windows)
    private static let winsockStarted: Bool = {
        var data = WSADATA()
        return WSAStartup(0x0202, &data) == 0
    }()
    #endif

    /// Initialises the socket library once (Winsock); a no-op elsewhere.
    static func startup() {
        #if os(Windows)
        _ = winsockStarted
        #endif
    }

    static func open(family: Int32, type: Int32) -> Result<NativeSocket, SocketError> {
        startup()
        let proto = type == kSOCK_STREAM ? kIPPROTO_TCP : kIPPROTO_UDP
        #if os(Windows)
        let handle = WinSDK.socket(family, type, proto)
        #elseif canImport(Glibc)
        let handle = Glibc.socket(family, type, proto)
        #else
        let handle = Darwin.socket(family, type, proto)
        #endif
        guard handle != kInvalidSocket else { return .failure(.last()) }
        #if canImport(Darwin)
        _ = setInt(handle, kSOL_SOCKET, SO_NOSIGPIPE, 1)
        #endif
        return .success(handle)
    }

    static func close(_ handle: NativeSocket) {
        #if os(Windows)
        _ = closesocket(handle)
        #elseif canImport(Glibc)
        _ = Glibc.close(handle)
        #else
        _ = Darwin.close(handle)
        #endif
    }

    @discardableResult
    static func setNonBlocking(_ handle: NativeSocket) -> Bool {
        #if os(Windows)
        var mode: u_long = 1
        return ioctlsocket(handle, kFIONBIO, &mode) == 0
        #else
        let flags = fcntl(handle, F_GETFL, 0)
        return flags >= 0 && fcntl(handle, F_SETFL, flags | O_NONBLOCK) == 0
        #endif
    }

    @discardableResult
    static func setInt(_ handle: NativeSocket, _ level: Int32, _ name: Int32, _ value: Int32) -> Bool {
        var value = value
        #if os(Windows)
        return withUnsafeBytes(of: &value) {
            setsockopt(handle, level, name, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(MemoryLayout<Int32>.size))
        } == 0
        #else
        return setsockopt(handle, level, name, &value, SockLen(MemoryLayout<Int32>.size)) == 0
        #endif
    }

    /// Sets an option some stacks take as a byte (IP_MULTICAST_TTL/LOOP on BSD) and
    /// others as an int.
    @discardableResult
    static func setByteOrInt(_ handle: NativeSocket, _ level: Int32, _ name: Int32, _ value: UInt8) -> Bool {
        if setInt(handle, level, name, Int32(value)) { return true }
        #if os(Windows)
        return false
        #else
        var byte = value
        return setsockopt(handle, level, name, &byte, SockLen(1)) == 0
        #endif
    }

    static func setLingerZero(_ handle: NativeSocket) {
        var value = linger()
        value.l_onoff = 1
        value.l_linger = 0
        #if os(Windows)
        _ = withUnsafeBytes(of: &value) {
            setsockopt(handle, kSOL_SOCKET, kSO_LINGER, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(MemoryLayout<linger>.size))
        }
        #else
        _ = setsockopt(handle, kSOL_SOCKET, kSO_LINGER, &value, SockLen(MemoryLayout<linger>.size))
        #endif
    }

    static func bind(_ handle: NativeSocket, _ address: SocketAddress) -> SocketError? {
        let result = address.withSockAddr { pointer, length in
            #if os(Windows)
            WinSDK.bind(handle, pointer, length)
            #elseif canImport(Glibc)
            Glibc.bind(handle, pointer, length)
            #else
            Darwin.bind(handle, pointer, length)
            #endif
        }
        return result == 0 ? nil : .last()
    }

    static func listen(_ handle: NativeSocket, backlog: Int32 = 128) -> SocketError? {
        #if os(Windows)
        let result = WinSDK.listen(handle, backlog)
        #elseif canImport(Glibc)
        let result = Glibc.listen(handle, backlog)
        #else
        let result = Darwin.listen(handle, backlog)
        #endif
        return result == 0 ? nil : .last()
    }

    enum ConnectResult {
        case connected
        case inProgress
        case failed(SocketError)
    }

    static func connect(_ handle: NativeSocket, _ address: SocketAddress) -> ConnectResult {
        while true {
            let result = address.withSockAddr { pointer, length in
                #if os(Windows)
                WinSDK.connect(handle, pointer, length)
                #elseif canImport(Glibc)
                Glibc.connect(handle, pointer, length)
                #else
                Darwin.connect(handle, pointer, length)
                #endif
            }
            if result == 0 { return .connected }
            let error = SocketError.last()
            if error.interrupted { continue }
            return error.inProgress ? .inProgress : .failed(error)
        }
    }

    /// Accepts one pending connection; nil with `wouldBlock` when none is waiting.
    static func accept(_ handle: NativeSocket) -> Result<(NativeSocket, SocketAddress?), SocketError> {
        var storage = sockaddr_storage()
        var length = SockLen(MemoryLayout<sockaddr_storage>.size)
        while true {
            let client = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                    #if os(Windows)
                    WinSDK.accept(handle, pointer, &length)
                    #elseif canImport(Glibc)
                    Glibc.accept(handle, pointer, &length)
                    #else
                    Darwin.accept(handle, pointer, &length)
                    #endif
                }
            }
            if client == kInvalidSocket {
                let error = SocketError.last()
                if error.interrupted { continue }
                return .failure(error)
            }
            #if canImport(Darwin)
            _ = setInt(client, kSOL_SOCKET, SO_NOSIGPIPE, 1)
            #endif
            let remote = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { SocketAddress($0) }
            }
            return .success((client, remote))
        }
    }

    static func write(_ handle: NativeSocket, _ buffer: UnsafeRawBufferPointer) -> IOResult {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return .done(0) }
        while true {
            #if os(Windows)
            let count = Int(WinSDK.send(handle, base.assumingMemoryBound(to: CChar.self), Int32(min(buffer.count, Int(Int32.max))), 0))
            #elseif canImport(Glibc)
            let count = Glibc.send(handle, base, buffer.count, Int32(MSG_NOSIGNAL))
            #else
            let count = Darwin.send(handle, base, buffer.count, 0)
            #endif
            if count >= 0 { return .done(count) }
            let error = SocketError.last()
            if error.interrupted { continue }
            return error.wouldBlock ? .wouldBlock : .failed(error)
        }
    }

    /// Reads into `buffer`; `.done(0)` is end of stream on a stream socket.
    static func read(_ handle: NativeSocket, _ buffer: UnsafeMutableRawBufferPointer) -> IOResult {
        while true {
            #if os(Windows)
            let count = Int(WinSDK.recv(handle, buffer.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(buffer.count), 0))
            #elseif canImport(Glibc)
            let count = Glibc.recv(handle, buffer.baseAddress!, buffer.count, 0)
            #else
            let count = Darwin.recv(handle, buffer.baseAddress!, buffer.count, 0)
            #endif
            if count >= 0 { return .done(count) }
            let error = SocketError.last()
            if error.interrupted { continue }
            return error.wouldBlock ? .wouldBlock : .failed(error)
        }
    }

    static func sendTo(_ handle: NativeSocket, _ buffer: UnsafeRawBufferPointer, _ address: SocketAddress) -> IOResult {
        while true {
            let count: Int = address.withSockAddr { pointer, length in
                // A zero-length datagram is legal; give the call a valid pointer for it.
                var empty: UInt8 = 0
                return withUnsafeMutablePointer(to: &empty) { emptyPointer in
                    let base = buffer.baseAddress ?? UnsafeRawPointer(emptyPointer)
                    #if os(Windows)
                    return Int(WinSDK.sendto(handle, base.assumingMemoryBound(to: CChar.self), Int32(buffer.count), 0, pointer, length))
                    #elseif canImport(Glibc)
                    return Glibc.sendto(handle, base, buffer.count, Int32(MSG_NOSIGNAL), pointer, length)
                    #else
                    return Darwin.sendto(handle, base, buffer.count, 0, pointer, length)
                    #endif
                }
            }
            if count >= 0 { return .done(count) }
            let error = SocketError.last()
            if error.interrupted { continue }
            return error.wouldBlock ? .wouldBlock : .failed(error)
        }
    }

    static func receiveFrom(_ handle: NativeSocket, _ buffer: UnsafeMutableRawBufferPointer) -> (IOResult, SocketAddress?) {
        var storage = sockaddr_storage()
        var length = SockLen(MemoryLayout<sockaddr_storage>.size)
        while true {
            let count: Int = withUnsafeMutablePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                    #if os(Windows)
                    Int(WinSDK.recvfrom(handle, buffer.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(buffer.count), 0, pointer, &length))
                    #elseif canImport(Glibc)
                    Glibc.recvfrom(handle, buffer.baseAddress!, buffer.count, 0, pointer, &length)
                    #else
                    Darwin.recvfrom(handle, buffer.baseAddress!, buffer.count, 0, pointer, &length)
                    #endif
                }
            }
            if count >= 0 {
                let from = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { SocketAddress($0) }
                }
                return (.done(count), from)
            }
            let error = SocketError.last()
            if error.interrupted { continue }
            #if os(Windows)
            // A datagram larger than the buffer: Winsock fails the call but consumes it.
            // WSAECONNRESET reports an ICMP port-unreachable for an earlier sendto.
            if error.code == .EMSGSIZE || error.code == .ECONNRESET { continue }
            #endif
            return (error.wouldBlock ? .wouldBlock : .failed(error), nil)
        }
    }

    static func shutdownWrite(_ handle: NativeSocket) {
        #if os(Windows)
        _ = WinSDK.shutdown(handle, kSHUT_WR)
        #elseif canImport(Glibc)
        _ = Glibc.shutdown(handle, kSHUT_WR)
        #else
        _ = Darwin.shutdown(handle, kSHUT_WR)
        #endif
    }

    /// The socket's pending error (SO_ERROR), nil when none.
    static func pendingError(_ handle: NativeSocket) -> SocketError? {
        var value: Int32 = 0
        var length = SockLen(MemoryLayout<Int32>.size)
        #if os(Windows)
        let result = withUnsafeMutableBytes(of: &value) {
            getsockopt(handle, kSOL_SOCKET, kSO_ERROR, $0.baseAddress!.assumingMemoryBound(to: CChar.self), &length)
        }
        if result != 0 { return .last() }
        return value == 0 ? nil : SocketError(winsock: value)
        #else
        if getsockopt(handle, kSOL_SOCKET, kSO_ERROR, &value, &length) != 0 { return .last() }
        return value == 0 ? nil : SocketError(errno: value)
        #endif
    }

    static func localAddress(_ handle: NativeSocket) -> SocketAddress? {
        var storage = sockaddr_storage()
        var length = SockLen(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(handle, $0, &length) }
        }
        guard result == 0 else { return nil }
        return withUnsafePointer(to: &storage) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { SocketAddress($0) } }
    }

    static func remoteAddress(_ handle: NativeSocket) -> SocketAddress? {
        var storage = sockaddr_storage()
        var length = SockLen(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(handle, $0, &length) }
        }
        guard result == 0 else { return nil }
        return withUnsafePointer(to: &storage) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { SocketAddress($0) } }
    }

    // MARK: Multicast

    private static func inAddr(_ bytes: [UInt8]) -> in_addr {
        var address = in_addr()
        withUnsafeMutableBytes(of: &address) { raw in
            for index in 0..<4 { raw[index] = bytes[index] }
        }
        return address
    }

    /// Joins an IPv4 multicast group on the interface with this address (0.0.0.0: the
    /// system's default).
    static func joinMulticast(_ handle: NativeSocket, group: [UInt8], interface: [UInt8]) -> Bool {
        var request = ip_mreq()
        request.imr_multiaddr = inAddr(group)
        request.imr_interface = inAddr(interface)
        #if os(Windows)
        return withUnsafeBytes(of: &request) {
            setsockopt(handle, kIPPROTO_IP, kIP_ADD_MEMBERSHIP, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(MemoryLayout<ip_mreq>.size))
        } == 0
        #else
        return setsockopt(handle, kIPPROTO_IP, kIP_ADD_MEMBERSHIP, &request, SockLen(MemoryLayout<ip_mreq>.size)) == 0
        #endif
    }

    /// Selects the interface outgoing multicast leaves from.
    static func setMulticastInterface(_ handle: NativeSocket, _ interface: [UInt8]) -> Bool {
        var address = inAddr(interface)
        #if os(Windows)
        return withUnsafeBytes(of: &address) {
            setsockopt(handle, kIPPROTO_IP, kIP_MULTICAST_IF, $0.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(MemoryLayout<in_addr>.size))
        } == 0
        #else
        return setsockopt(handle, kIPPROTO_IP, kIP_MULTICAST_IF, &address, SockLen(MemoryLayout<in_addr>.size)) == 0
        #endif
    }

    // MARK: Interfaces

    /// The IPv4 addresses of interfaces that are up.
    static func ipv4Interfaces() -> [LocalInterface] {
        #if os(Windows)
        startup()
        var size: ULONG = 16 * 1024
        for _ in 0..<4 {
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
            defer { buffer.deallocate() }
            let first = buffer.bindMemory(to: IP_ADAPTER_ADDRESSES.self, capacity: 1)
            // GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER
            let result = GetAdaptersAddresses(ULONG(kAF_INET), ULONG(0x0002 | 0x0004 | 0x0008), nil, first, &size)
            if result == ULONG(ERROR_BUFFER_OVERFLOW) { continue }
            guard result == ULONG(ERROR_SUCCESS) else { return [] }
            var interfaces: [LocalInterface] = []
            var adapter: UnsafeMutablePointer<IP_ADAPTER_ADDRESSES>? = first
            while let current = adapter {
                defer { adapter = current.pointee.Next }
                guard current.pointee.OperStatus == IfOperStatusUp else { continue }
                let isLoopback = current.pointee.IfType == 24 // IF_TYPE_SOFTWARE_LOOPBACK
                let name = current.pointee.FriendlyName.map { String(decodingCString: $0, as: UTF16.self) } ?? ""
                let index = Int(current.pointee.IfIndex)
                var unicast = current.pointee.FirstUnicastAddress
                while let address = unicast {
                    defer { unicast = address.pointee.Next }
                    guard let sockaddrPointer = address.pointee.Address.lpSockaddr,
                          let parsed = SocketAddress(UnsafePointer(sockaddrPointer)), parsed.family == kAF_INET else { continue }
                    interfaces.append(LocalInterface(name: name, index: index, ipv4: parsed.bytes, isLoopback: isLoopback))
                }
            }
            return interfaces
        }
        return []
        #else
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var interfaces: [LocalInterface] = []
        var cursor = head
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            let flags = Int(current.pointee.ifa_flags)
            guard flags & Int(IFF_UP) != 0, flags & Int(IFF_RUNNING) != 0,
                  let address = current.pointee.ifa_addr, Int32(address.pointee.sa_family) == kAF_INET,
                  let parsed = SocketAddress(UnsafePointer(address)) else { continue }
            let isLoopback = flags & Int(IFF_LOOPBACK) != 0
            guard isLoopback || flags & Int(IFF_MULTICAST) != 0 else { continue }
            let name = String(cString: current.pointee.ifa_name)
            interfaces.append(LocalInterface(name: name, index: Int(if_nametoindex(current.pointee.ifa_name)),
                                             ipv4: parsed.bytes, isLoopback: isLoopback))
        }
        return interfaces
        #endif
    }

    static func interfaceIndex(name: String) -> Int? {
        #if os(Windows)
        startup()
        #endif
        let index = if_nametoindex(name)
        return index == 0 ? nil : Int(index)
    }

    static func interfaceName(index: Int) -> String? {
        #if os(Windows)
        startup()
        var buffer = [CChar](repeating: 0, count: 256) // IF_NAMESIZE on Windows is 256
        #else
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        #endif
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        return String(cString: buffer)
    }

    // MARK: Names

    static func servicePort(named name: String) -> UInt16? {
        startup()
        guard let entry = getservbyname(name, "tcp") ?? getservbyname(name, "udp") else { return nil }
        return UInt16(bigEndian: UInt16(truncatingIfNeeded: entry.pointee.s_port))
    }

    /// Resolves a host name with getaddrinfo, in the system's preferred order. Blocks;
    /// call it off the reactor thread.
    static func resolve(host: String, port: UInt16, type: Int32) -> Result<[SocketAddress], NWError> {
        startup()
        #if os(Windows)
        var hints = ADDRINFOA()
        var list: UnsafeMutablePointer<ADDRINFOA>?
        #else
        var hints = addrinfo()
        var list: UnsafeMutablePointer<addrinfo>?
        #endif
        hints.ai_family = numericCast(AF_UNSPEC)
        // No AI_ADDRCONFIG: glibc then fails "localhost" on a machine without a
        // non-loopback address. Unusable families fail fast at connect and fall through.
        hints.ai_socktype = type
        let status = getaddrinfo(host, nil, &hints, &list)
        guard status == 0 else {
            return .failure(.dns(_DNSServiceError.noSuchRecord))
        }
        defer { freeaddrinfo(list) }
        var addresses: [SocketAddress] = []
        var cursor = list
        while let entry = cursor {
            defer { cursor = entry.pointee.ai_next }
            guard let address = entry.pointee.ai_addr, let parsed = SocketAddress(UnsafePointer(address)) else { continue }
            let withPort = parsed.withPort(port)
            if !addresses.contains(withPort) { addresses.append(withPort) }
        }
        return addresses.isEmpty ? .failure(.dns(_DNSServiceError.noSuchRecord)) : .success(addresses)
    }

    /// The machine's host name, first label only.
    static func hostLabel() -> String {
        let full = ProcessInfo.processInfo.hostName
        let first = full.split(separator: ".").first.map(String.init) ?? ""
        let cleaned = String(first.unicodeScalars.map { scalar -> Character in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")) ? Character(scalar) : "-"
        })
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "host" : String(trimmed.prefix(40))
    }
}
