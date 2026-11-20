// One thread that polls every registered socket and tells its owner when it can read
// or write. Owners do their non-blocking I/O inside the callback and deliver results to
// their own dispatch queues; nothing user-visible runs on this thread.

import Foundation
#if canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#endif

/// Receives readiness for a registered socket on the reactor thread. Implementations
/// must not block, and must stop asking for an event they cannot consume (or the poll
/// spins).
protocol ReactorHandler: AnyObject {
    func reactorReady(_ socket: NativeSocket, readable: Bool, writable: Bool, failed: Bool)
}

final class Reactor: @unchecked Sendable {
    static let shared = Reactor()

    private struct Entry {
        let handler: ReactorHandler
        var read: Bool
        var write: Bool
    }

    private let lock = NSLock()
    private var entries: [NativeSocket: Entry] = [:]
    private var closing: [NativeSocket] = []
    private var wakePending = false
    /// A UDP socket connected to itself: writing one byte interrupts the poll.
    private let wakeSocket: NativeSocket

    private init() {
        Sock.startup()
        guard case .success(let wake) = Sock.open(family: kAF_INET, type: kSOCK_DGRAM) else {
            fatalError("Network: cannot create the reactor's wake-up socket")
        }
        let loopback = SocketAddress(ipv4: [127, 0, 0, 1], port: 0)
        guard Sock.bind(wake, loopback) == nil, let bound = Sock.localAddress(wake),
              case .connected = Sock.connect(wake, bound) else {
            fatalError("Network: cannot bind the reactor's wake-up socket to loopback")
        }
        Sock.setNonBlocking(wake)
        wakeSocket = wake
        let thread = Thread { [unowned self] in self.run() }
        thread.name = "Network.Reactor"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Starts watching `socket`. The reactor keeps `handler` alive until `close`.
    func register(_ socket: NativeSocket, handler: ReactorHandler, read: Bool, write: Bool) {
        lock.locked { entries[socket] = Entry(handler: handler, read: read, write: write) }
        wake()
    }

    /// Changes which events `socket` is watched for.
    func update(_ socket: NativeSocket, read: Bool, write: Bool) {
        let changed: Bool = lock.locked {
            guard var entry = entries[socket], entry.read != read || entry.write != write else { return false }
            entry.read = read
            entry.write = write
            entries[socket] = entry
            return true
        }
        if changed { wake() }
    }

    /// Stops watching `socket` and closes it on the reactor thread, after the poll that
    /// may still reference it has returned, so a reused descriptor is never polled for the
    /// wrong owner. Also closes sockets that were never registered.
    func close(_ socket: NativeSocket) {
        lock.locked {
            entries[socket] = nil
            closing.append(socket)
        }
        wake()
    }

    private func wake() {
        let needed: Bool = lock.locked {
            if wakePending { return false }
            wakePending = true
            return true
        }
        guard needed else { return }
        var byte: UInt8 = 1
        _ = withUnsafeBytes(of: &byte) { Sock.write(wakeSocket, $0) }
    }

    private func drainWake() {
        var buffer = [UInt8](repeating: 0, count: 64)
        while case .done = buffer.withUnsafeMutableBytes({ Sock.read(wakeSocket, $0) }) {}
    }

    #if os(Windows)
    private typealias PollDescriptor = WSAPOLLFD
    #else
    private typealias PollDescriptor = pollfd
    #endif

    private func run() {
        var descriptors: [PollDescriptor] = []
        while true {
            let toClose: [NativeSocket] = lock.locked {
                wakePending = false
                descriptors.removeAll(keepingCapacity: true)
                descriptors.append(PollDescriptor(fd: wakeSocket, events: kPOLLIN, revents: 0))
                for (socket, entry) in entries where entry.read || entry.write {
                    var events: Int16 = 0
                    if entry.read { events |= kPOLLIN }
                    if entry.write { events |= kPOLLOUT }
                    descriptors.append(PollDescriptor(fd: socket, events: events, revents: 0))
                }
                let sockets = closing
                closing.removeAll()
                return sockets
            }
            for socket in toClose { Sock.close(socket) }

            #if os(Windows)
            let count = descriptors.withUnsafeMutableBufferPointer { WSAPoll($0.baseAddress, ULONG($0.count), -1) }
            #else
            let count = descriptors.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), -1) }
            #endif
            if count <= 0 { continue } // EINTR, or a transient failure: rebuild and retry.

            for descriptor in descriptors where descriptor.revents != 0 {
                if descriptor.fd == wakeSocket {
                    drainWake()
                    continue
                }
                let entry = lock.locked { entries[descriptor.fd] }
                guard let entry else { continue }
                let events = descriptor.revents
                let failed = events & (kPOLLERR | kPOLLHUP | kPOLLNVAL) != 0
                entry.handler.reactorReady(descriptor.fd,
                                           readable: events & kPOLLIN != 0 || (failed && entry.read),
                                           writable: events & kPOLLOUT != 0 || (failed && entry.write),
                                           failed: failed)
            }
        }
    }
}
