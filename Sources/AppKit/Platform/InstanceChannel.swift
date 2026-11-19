// The single-instance channel (ADR-0045): the first process of an application listens on a
// per-user endpoint named after its identity; a later launch connects, hands over its
// arguments and exits, the way a second `open` of a Mac app reaches the running one.
//
// Windows: a named pipe `\\.\pipe\AppKitCross-<identity>-<user>-<session>` created with
// FILE_FLAG_FIRST_PIPE_INSTANCE (Platform/Win32/Win32InstanceChannel.swift); the sender
// lets the listener take the foreground (AllowSetForegroundWindow). Linux (and the macOS
// host, for the tests): a Unix domain socket in `$XDG_RUNTIME_DIR` (else the temporary
// folder), unlinked and re-made when the last owner died.

import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A per-user rendezvous point for one application identity.
public protocol PlatformInstanceChannel: AnyObject {
    /// Delivers `message` to the process listening, if any; true when it was taken.
    func send(_ message: Data) -> Bool
    /// Starts listening; false when another process already does. `handler` runs on a
    /// background thread once per message.
    func listen(_ handler: @escaping @Sendable (Data) -> Void) -> Bool
    /// Stops listening and removes the endpoint.
    func close()
}

public enum PlatformInstanceChannels {
    /// The channel for an identity on this platform.
    public static func make(identifier: String) -> any PlatformInstanceChannel {
        #if os(Windows)
        return Win32InstanceChannel(identifier: identifier)
        #else
        return POSIXInstanceChannel(identifier: identifier)
        #endif
    }

    /// The identity as a file or pipe name: letters, digits, `.`, `-`, `_`.
    static func sanitized(_ identifier: String) -> String {
        String(identifier.unicodeScalars.map { c in
            (CharacterSet.alphanumerics.contains(c) && c.isASCII) || c == "." || c == "-" || c == "_" ? Character(c) : "_"
        })
    }
}

#if !os(Windows)
/// A Unix domain socket listener on a background thread.
final class POSIXInstanceChannel: PlatformInstanceChannel, @unchecked Sendable {
    let path: String
    private var listener: Int32 = -1
    private let lock = NSLock()

    init(identifier: String, directory: String? = nil) {
        let env = ProcessInfo.processInfo.environment
        var dir = directory ?? env["XDG_RUNTIME_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? NSTemporaryDirectory()
        var name = "AppKitCross-\(getuid())-" + PlatformInstanceChannels.sanitized(identifier)
        // sun_path holds about 100 bytes: long identities keep a stable hash instead.
        if (dir as NSString).appendingPathComponent(name + ".sock").utf8.count > 100 {
            var h: UInt64 = 1469598103934665603
            for b in identifier.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            name = "AppKitCross-\(getuid())-" + String(h, radix: 36)
            if (dir as NSString).appendingPathComponent(name + ".sock").utf8.count > 100 { dir = "/tmp" }
        }
        path = (dir as NSString).appendingPathComponent(name + ".sock")
    }

    private func address() -> (sockaddr_un, socklen_t) {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: addr.sun_path) - 1))
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        return (addr, socklen_t(MemoryLayout<sockaddr_un>.size))
    }

    private static func makeSocket() -> Int32 {
        #if canImport(Glibc)
        return socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #else
        return socket(AF_UNIX, SOCK_STREAM, 0)
        #endif
    }

    func send(_ message: Data) -> Bool {
        let fd = Self.makeSocket()
        guard fd >= 0 else { return false }
        defer { _ = Glibc_close(fd) }
        var (addr, len) = address()
        let connected = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard connected == 0 else { return false }
        var sent = 0
        let ok = message.withUnsafeBytes { raw -> Bool in
            while sent < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
        guard ok else { return false }
        // Wait for the listener's one-byte acknowledgement (it has read everything).
        var ack: UInt8 = 0
        shutdown(fd, Int32(SHUT_WR))
        return read(fd, &ack, 1) == 1
    }

    func listen(_ handler: @escaping @Sendable (Data) -> Void) -> Bool {
        let fd = Self.makeSocket()
        guard fd >= 0 else { return false }
        var (addr, len) = address()
        func bindNow() -> Int32 {
            withUnsafePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        }
        if bindNow() != 0 {
            // A socket file with nobody behind it is left over from a process that died.
            guard FileManager.default.fileExists(atPath: path), !send(Data()) else { _ = Glibc_close(fd); return false }
            unlink(path)
            guard bindNow() == 0 else { _ = Glibc_close(fd); return false }
        }
        chmod(path, 0o600)
        guard Glibc_listen(fd, 8) == 0 else { _ = Glibc_close(fd); unlink(path); return false }
        lock.lock(); listener = fd; lock.unlock()
        let thread = Thread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 {
                    if errno == EINTR { continue }
                    return
                }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let n = read(client, &buffer, buffer.count)
                    if n <= 0 { break }
                    data.append(buffer, count: n)
                }
                var ack: UInt8 = 1
                _ = write(client, &ack, 1)
                _ = Glibc_close(client)
                if self == nil { return }
                if !data.isEmpty { handler(data) }
            }
        }
        thread.name = "AppKitCross instance channel"
        thread.start()
        return true
    }

    func close() {
        lock.lock(); let fd = listener; listener = -1; lock.unlock()
        guard fd >= 0 else { return }
        shutdown(fd, Int32(SHUT_RDWR))
        _ = Glibc_close(fd)
        unlink(path)
    }

    deinit { close() }
}

// The module's own `close`/`listen` members shadow the C functions inside the class.
@inline(__always) private func Glibc_close(_ fd: Int32) -> Int32 { close(fd) }
@inline(__always) private func Glibc_listen(_ fd: Int32, _ backlog: Int32) -> Int32 { listen(fd, backlog) }
#endif
