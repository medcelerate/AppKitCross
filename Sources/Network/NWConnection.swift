import Foundation
#if canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#endif

/// A bidirectional data connection between a local endpoint and a remote endpoint.
///
/// TCP connections resolve host names with getaddrinfo off the reactor thread and try
/// each address in turn with a non-blocking connect. When every address fails the
/// connection enters `.waiting` with the last error and retries with backoff (1 s doubling
/// to 30 s) until it connects or is cancelled; `NWProtocolTCP.Options.connectionTimeout`
/// turns that into `.failed(ETIMEDOUT)`. UDP connections bind a socket and `connect()` it
/// to the remote so plain sends work; each receive delivers one datagram.
public final class NWConnection: CustomDebugStringConvertible, @unchecked Sendable {
    /// Connection states.
    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case preparing
        case ready
        case failed(NWError)
        case cancelled
    }

    /// How a send's completion is reported.
    public enum SendCompletion {
        /// Calls the closure once the content has been handed to the network stack, or
        /// with the error that stopped it.
        @preconcurrency case contentProcessed(@Sendable (_ error: NWError?) -> Void)
        /// No completion is needed.
        case idempotent
    }

    /// Describes the content of a send or receive.
    public class ContentContext: @unchecked Sendable {
        public final let identifier: String
        public final let expirationMilliseconds: UInt64
        public final let relativePriority: Double
        public final let antecedent: NWConnection.ContentContext?
        /// A final context closes the sending direction once its content is complete.
        public final let isFinal: Bool
        public var protocolMetadata: [NWProtocolMetadata] { _metadata }
        private let _metadata: [NWProtocolMetadata]

        public init(identifier: String, expiration: UInt64 = 0, priority: Double = 0.5, isFinal: Bool = false,
                    antecedent: NWConnection.ContentContext? = nil, metadata: [NWProtocolMetadata]? = []) {
            self.identifier = identifier
            expirationMilliseconds = expiration
            relativePriority = priority
            self.isFinal = isFinal
            self.antecedent = antecedent
            _metadata = metadata ?? []
        }

        /// One message on the connection; does not close the stream.
        public static let defaultMessage = ContentContext(identifier: "Default Message")
        /// The last message: completing it closes the sending direction (TCP FIN).
        public static let finalMessage = ContentContext(identifier: "Final Message", isFinal: true)
        /// The whole stream as one final context.
        public static let defaultStream = ContentContext(identifier: "Default Stream", isFinal: true)
    }

    public let endpoint: NWEndpoint
    public let parameters: NWParameters

    // MARK: State (guarded by `lock`)

    private enum Origin {
        case outbound
        case acceptedStream(NativeSocket)
        case listenerDatagram(UDPDemultiplexer, SocketAddress)
    }

    private struct PendingSend {
        var data: Data
        var offset = 0
        let hasContent: Bool
        let closesStream: Bool
        let completion: SendCompletion
    }

    private struct PendingReceive {
        let minimum: Int
        let maximum: Int
        let wholeMessage: Bool
        let completion: @Sendable (Data?, ContentContext?, Bool, NWError?) -> Void
    }

    private let lock = NSLock()
    private let origin: Origin
    private let isDatagram: Bool
    private var _state: State = .setup
    private var _queue: DispatchQueue?
    private var _stateUpdateHandler: (@Sendable (State) -> Void)?
    private var _viabilityUpdateHandler: (@Sendable (Bool) -> Void)?
    private var _pathUpdateHandler: (@Sendable (NWPath) -> Void)?
    private var _currentPath: NWPath?

    private var socket: NativeSocket = kInvalidSocket
    private var interest = (read: false, write: false)
    private var connecting = false
    private var candidates: [SocketAddress] = []
    private var lastError: NWError?
    private var attempt = 0
    private var retryDelay: Double = 1
    private var retryTimer: DispatchSourceTimer?
    private var timeoutTimer: DispatchSourceTimer?
    private var connectPollTimer: DispatchSourceTimer?
    private var attemptTimer: DispatchSourceTimer?

    private var sends: [PendingSend] = []
    private var receives: [PendingReceive] = []
    private var inbound = Data()
    private var datagrams: [Data] = []
    private var readEOF = false
    private var outbox: [() -> Void] = []

    private static let maximumQueuedDatagrams = 512
    private static let readChunk = 64 * 1024
    private static let attemptTimeout: Double = 3

    // MARK: Initialisers

    public init(to: NWEndpoint, using: NWParameters) {
        endpoint = to
        parameters = using
        origin = .outbound
        isDatagram = using._isUDP
    }

    public convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) {
        self.init(to: .hostPort(host: host, port: port), using: using)
    }

    /// A connection a listener accepted; its socket is connected and non-blocking.
    init(accepted socket: NativeSocket, remote: SocketAddress, parameters: NWParameters) {
        endpoint = remote.endpoint
        self.parameters = parameters
        origin = .acceptedStream(socket)
        isDatagram = false
        self.socket = socket
    }

    /// A UDP peer of a listener; datagrams arrive through the listener's socket.
    init(datagramPeer remote: SocketAddress, demultiplexer: UDPDemultiplexer, parameters: NWParameters) {
        endpoint = remote.endpoint
        self.parameters = parameters
        origin = .listenerDatagram(demultiplexer, remote)
        isDatagram = true
    }

    deinit {
        // Only reachable for a connection that was never started (the reactor keeps
        // started ones alive until they close).
        if case .acceptedStream = origin, socket != kInvalidSocket, _queue == nil {
            Sock.close(socket)
        }
    }

    // MARK: Public properties

    public var state: State { lock.locked { _state } }

    public var queue: DispatchQueue? { lock.locked { _queue } }

    public var currentPath: NWPath? { lock.locked { _currentPath } }

    @preconcurrency public var stateUpdateHandler: (@Sendable (_ state: NWConnection.State) -> Void)? {
        get { lock.locked { _stateUpdateHandler } }
        set { lock.locked { _stateUpdateHandler = newValue } }
    }

    /// Stored for source compatibility. Without path monitoring a connection never
    /// becomes non-viable, so this is never called.
    @preconcurrency public var viabilityUpdateHandler: (@Sendable (_ newIsViable: Bool) -> Void)? {
        get { lock.locked { _viabilityUpdateHandler } }
        set { lock.locked { _viabilityUpdateHandler = newValue } }
    }

    /// Called with the established path when the connection becomes ready.
    @preconcurrency public var pathUpdateHandler: (@Sendable (_ newPath: NWPath) -> Void)? {
        get { lock.locked { _pathUpdateHandler } }
        set { lock.locked { _pathUpdateHandler = newValue } }
    }

    public var debugDescription: String {
        "[\(parameters._transportName) \(endpoint.debugDescription) \(state)]"
    }

    // MARK: Lifecycle

    public func start(queue: DispatchQueue) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        guard _queue == nil, case .setup = _state else { return }
        parameters._requireSupportedStack(for: "NWConnection")
        _queue = queue
        transitionLocked(.preparing)
        switch origin {
        case .outbound:
            if let tcp = parameters._tcpOptions, tcp.connectionTimeout > 0 {
                timeoutTimer = makeTimer(after: Double(tcp.connectionTimeout)) { connection in
                    connection.lock.lock()
                    defer { connection.flushLocked(); connection.lock.unlock() }
                    switch connection._state {
                    case .preparing, .waiting: connection.failLocked(.posix(.ETIMEDOUT))
                    default: break
                    }
                }
            }
            beginConnectLocked()
        case .acceptedStream(let accepted):
            Reactor.shared.register(accepted, handler: self, read: false, write: false)
            becomeReadyLocked()
        case .listenerDatagram:
            becomeReadyLocked()
        }
    }

    /// Closes the connection. Outstanding sends and receives complete with ECANCELED,
    /// the state becomes `.cancelled`, and the update handlers are released.
    public func cancel() {
        cancel(force: false)
    }

    /// Like `cancel()`, but resets a TCP connection (RST) instead of closing it.
    public func forceCancel() {
        cancel(force: true)
    }

    private func cancel(force: Bool) {
        var detach: (UDPDemultiplexer, SocketAddress)?
        lock.lock()
        if case .cancelled = _state { lock.unlock(); return }
        if force, socket != kInvalidSocket, !isDatagram { Sock.setLingerZero(socket) }
        closeSocketLocked()
        cancelTimersLocked()
        if case .listenerDatagram(let demultiplexer, let remote) = origin { detach = (demultiplexer, remote) }
        abortPendingLocked(with: .posix(.ECANCELED))
        transitionLocked(.cancelled)
        if _queue == nil { outbox.removeAll() }
        flushLocked()
        lock.unlock()
        if let (demultiplexer, remote) = detach { demultiplexer.remove(remote) }
    }

    // MARK: Sending

    @preconcurrency
    public func send(content: Data?, contentContext: NWConnection.ContentContext = .defaultMessage,
                     isComplete: Bool = true, completion: NWConnection.SendCompletion) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        switch _state {
        case .cancelled:
            completeLocked(completion, .posix(.ECANCELED))
            return
        case .failed(let error):
            completeLocked(completion, error)
            return
        default:
            break
        }
        sends.append(PendingSend(data: content ?? Data(), hasContent: content != nil,
                                 closesStream: !isDatagram && isComplete && contentContext.isFinal,
                                 completion: completion))
        if case .ready = _state {
            writeLocked()
            updateInterestLocked()
        }
    }

    /// Sends any `DataProtocol` value (Apple's generic overload).
    @preconcurrency @inlinable
    public func send<Content: DataProtocol>(content: Content?, contentContext: NWConnection.ContentContext = .defaultMessage,
                                            isComplete: Bool = true, completion: NWConnection.SendCompletion) {
        if let data = content as? Data {
            send(content: data, contentContext: contentContext, isComplete: isComplete, completion: completion)
        } else if let content {
            send(content: Data(content), contentContext: contentContext, isComplete: isComplete, completion: completion)
        } else {
            send(content: nil as Data?, contentContext: contentContext, isComplete: isComplete, completion: completion)
        }
    }

    // MARK: Receiving

    /// Receives between `minimumIncompleteLength` and `maximumLength` bytes on a stream
    /// (fewer only at end of stream, when `isComplete` is true), or one datagram on UDP.
    @preconcurrency
    public func receive(minimumIncompleteLength: Int, maximumLength: Int,
                        completion: @escaping @Sendable (_ content: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void) {
        enqueueReceive(PendingReceive(minimum: max(minimumIncompleteLength, 1), maximum: max(maximumLength, 1),
                                      wholeMessage: false, completion: completion))
    }

    /// Receives one complete message: a datagram on UDP, or everything up to the end of
    /// the stream on TCP.
    @preconcurrency
    public func receiveMessage(completion: @escaping @Sendable (_ content: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void) {
        enqueueReceive(PendingReceive(minimum: 1, maximum: Int.max, wholeMessage: true, completion: completion))
    }

    private func enqueueReceive(_ receive: PendingReceive) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        switch _state {
        case .cancelled:
            outbox.append { receive.completion(nil, nil, true, .posix(.ECANCELED)) }
            return
        case .failed(let error):
            outbox.append { receive.completion(nil, nil, true, error) }
            return
        default:
            break
        }
        receives.append(receive)
        if case .ready = _state {
            satisfyReceivesLocked()
            updateInterestLocked()
        }
    }

    /// A datagram for a listener-owned UDP peer.
    func deliverDatagram(_ data: Data) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        switch _state {
        case .cancelled, .failed: return
        default: break
        }
        datagrams.append(data)
        if datagrams.count > Self.maximumQueuedDatagrams { datagrams.removeFirst() }
        if case .ready = _state { satisfyReceivesLocked() }
    }

    // MARK: Connecting

    private func beginConnectLocked() {
        attempt += 1
        let thisAttempt = attempt
        let port: UInt16
        let hostName: String
        switch endpoint {
        case .hostPort(let host, let endpointPort):
            if let address = SocketAddress(host: host, port: endpointPort.rawValue) {
                candidates = [address]
                tryNextCandidateLocked()
                return
            }
            guard case .name(let name, _) = host else { return }
            hostName = name
            port = endpointPort.rawValue
        case .url(let url):
            guard let host = url.host, let urlPort = url.port.map(UInt16.init) ?? Self.defaultPort(for: url.scheme) else {
                failLocked(.posix(.EINVAL))
                return
            }
            let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
            if let address = SocketAddress(host: NWEndpoint.Host(bare), port: urlPort) {
                candidates = [address]
                tryNextCandidateLocked()
                return
            }
            hostName = bare
            port = urlPort
        case .service(let name, let type, let domain, _):
            MDNSEngine.shared.resolve(instance: name, type: type, domain: domain) { [self] result in
                lock.lock()
                defer { flushLocked(); lock.unlock() }
                guard attempt == thisAttempt, isConnectingStateLocked else { return }
                switch result {
                case .success(let addresses):
                    candidates = addresses
                    tryNextCandidateLocked()
                case .failure(let error):
                    enterWaitingLocked(error)
                }
            }
            return
        case .unix:
            unimplemented("NWConnection to a .unix endpoint")
        }
        let type = isDatagram ? kSOCK_DGRAM : kSOCK_STREAM
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Sock.resolve(host: hostName, port: port, type: type)
            lock.lock()
            defer { flushLocked(); lock.unlock() }
            guard attempt == thisAttempt, isConnectingStateLocked else { return }
            switch result {
            case .success(let addresses):
                candidates = addresses
                tryNextCandidateLocked()
            case .failure(let error):
                enterWaitingLocked(error)
            }
        }
    }

    private static func defaultPort(for scheme: String?) -> UInt16? {
        switch scheme?.lowercased() {
        case "http", "ws": return 80
        case "https", "wss": return 443
        default: return nil
        }
    }

    private var isConnectingStateLocked: Bool {
        switch _state {
        case .preparing, .waiting: return true
        default: return false
        }
    }

    private func tryNextCandidateLocked() {
        while !candidates.isEmpty {
            let address = candidates.removeFirst()
            let handle: NativeSocket
            switch Sock.open(family: address.family, type: isDatagram ? kSOCK_DGRAM : kSOCK_STREAM) {
            case .success(let opened): handle = opened
            case .failure(let error): lastError = error.nwError; continue
            }
            Sock.setNonBlocking(handle)
            configureLocked(handle)
            if let local = parameters.requiredLocalEndpoint {
                if parameters.allowLocalEndpointReuse { Sock.setInt(handle, kSOL_SOCKET, kSO_REUSEADDR, 1) }
                guard let bindAddress = Self.localBindAddress(local, family: address.family) else {
                    Sock.close(handle)
                    lastError = .posix(.EADDRNOTAVAIL)
                    continue
                }
                if let error = Sock.bind(handle, bindAddress) {
                    Sock.close(handle)
                    lastError = error.nwError
                    continue
                }
            }
            switch Sock.connect(handle, address) {
            case .connected:
                socket = handle
                Reactor.shared.register(handle, handler: self, read: false, write: false)
                becomeReadyLocked()
                return
            case .inProgress:
                socket = handle
                connecting = true
                interest = (false, true)
                Reactor.shared.register(handle, handler: self, read: false, write: true)
                if !candidates.isEmpty {
                    // More addresses to try (a multi-homed Bonjour peer, IPv6 then IPv4):
                    // do not let an unreachable one hold up the rest for the full SYN timeout.
                    attemptTimer = makeTimer(after: Self.attemptTimeout) { connection in
                        connection.lock.lock()
                        defer { connection.flushLocked(); connection.lock.unlock() }
                        if connection.connecting, connection.socket == handle {
                            connection.connectFailedLocked(.posix(.ETIMEDOUT))
                        }
                    }
                }
                #if os(Windows)
                // WSAPoll before Windows 10 2004 does not report a refused connect; check
                // SO_ERROR on a timer as well.
                connectPollTimer = makeTimer(after: 0.25, repeating: 0.25) { connection in
                    connection.lock.lock()
                    defer { connection.flushLocked(); connection.lock.unlock() }
                    if connection.connecting, let error = Sock.pendingError(connection.socket) {
                        connection.connectFailedLocked(error.nwError)
                    }
                }
                #endif
                return
            case .failed(let error):
                Sock.close(handle)
                lastError = error.nwError
            }
        }
        enterWaitingLocked(lastError ?? .posix(.ECONNREFUSED))
    }

    /// The address to bind for `requiredLocalEndpoint`, in the connection's family.
    private static func localBindAddress(_ endpoint: NWEndpoint, family: Int32) -> SocketAddress? {
        guard case .hostPort(let host, let port) = endpoint else { return nil }
        if let address = SocketAddress(host: host, port: port.rawValue) {
            if address.family == family { return address }
            if family == kAF_INET6, address.family == kAF_INET {
                return SocketAddress(ipv6: [UInt8](repeating: 0, count: 10) + [0xFF, 0xFF] + address.bytes, port: port.rawValue)
            }
            return nil
        }
        return family == kAF_INET
            ? SocketAddress(ipv4: [0, 0, 0, 0], port: port.rawValue)
            : SocketAddress(ipv6: [UInt8](repeating: 0, count: 16), port: port.rawValue)
    }

    private func configureLocked(_ handle: NativeSocket) {
        guard let tcp = parameters._tcpOptions else { return }
        NWConnection.applyTCPOptions(tcp, to: handle)
    }

    static func applyTCPOptions(_ tcp: NWProtocolTCP.Options, to handle: NativeSocket) {
        if tcp.noDelay { Sock.setInt(handle, kIPPROTO_TCP, kTCP_NODELAY, 1) }
        if tcp.enableKeepalive {
            Sock.setInt(handle, kSOL_SOCKET, kSO_KEEPALIVE, 1)
            if tcp.keepaliveIdle > 0 { Sock.setInt(handle, kIPPROTO_TCP, kTCP_KEEPIDLE, Int32(clamping: tcp.keepaliveIdle)) }
            if tcp.keepaliveInterval > 0 { Sock.setInt(handle, kIPPROTO_TCP, kTCP_KEEPINTVL, Int32(clamping: tcp.keepaliveInterval)) }
            if tcp.keepaliveCount > 0 { Sock.setInt(handle, kIPPROTO_TCP, kTCP_KEEPCNT, Int32(clamping: tcp.keepaliveCount)) }
        }
    }

    private func finishConnectLocked() {
        if let error = Sock.pendingError(socket) {
            connectFailedLocked(error.nwError)
            return
        }
        // Writable without a pending error can still be a failed connect on some stacks;
        // a connected socket has a peer.
        guard Sock.remoteAddress(socket) != nil else {
            connectFailedLocked(.posix(.ECONNREFUSED))
            return
        }
        becomeReadyLocked()
    }

    private func connectFailedLocked(_ error: NWError) {
        connecting = false
        connectPollTimer?.cancel()
        connectPollTimer = nil
        attemptTimer?.cancel()
        attemptTimer = nil
        closeSocketLocked()
        lastError = error
        tryNextCandidateLocked()
    }

    private func enterWaitingLocked(_ error: NWError) {
        transitionLocked(.waiting(error))
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        let thisAttempt = attempt
        retryTimer?.cancel()
        retryTimer = makeTimer(after: delay) { connection in
            connection.lock.lock()
            defer { connection.flushLocked(); connection.lock.unlock() }
            guard connection.attempt == thisAttempt, case .waiting = connection._state else { return }
            connection.beginConnectLocked()
        }
    }

    private func becomeReadyLocked() {
        connecting = false
        connectPollTimer?.cancel()
        connectPollTimer = nil
        attemptTimer?.cancel()
        attemptTimer = nil
        timeoutTimer?.cancel()
        timeoutTimer = nil
        retryTimer?.cancel()
        retryTimer = nil
        let local: SocketAddress?
        let remote: NWEndpoint?
        switch origin {
        case .listenerDatagram(let demultiplexer, let peer):
            local = demultiplexer.localAddress
            remote = peer.endpoint
        default:
            local = socket == kInvalidSocket ? nil : Sock.localAddress(socket)
            remote = (socket == kInvalidSocket ? nil : Sock.remoteAddress(socket))?.endpoint ?? endpoint
        }
        let path = NWPath(status: .satisfied, localEndpoint: local?.endpoint, remoteEndpoint: remote)
        _currentPath = path
        transitionLocked(.ready)
        if let handler = _pathUpdateHandler { outbox.append { handler(path) } }
        writeLocked()
        satisfyReceivesLocked()
        updateInterestLocked()
    }

    // MARK: I/O

    private func updateInterestLocked() {
        guard socket != kInvalidSocket else { return }
        let ready: Bool
        if case .ready = _state { ready = true } else { ready = false }
        let read = ready && !receives.isEmpty && !readEOF
        let write = connecting || (ready && !sends.isEmpty)
        guard read != interest.read || write != interest.write else { return }
        interest = (read, write)
        Reactor.shared.update(socket, read: read, write: write)
    }

    private func readLocked() {
        guard socket != kInvalidSocket else { return }
        var buffer = [UInt8](repeating: 0, count: Self.readChunk)
        if isDatagram {
            while true {
                let result = buffer.withUnsafeMutableBytes { Sock.read(socket, $0) }
                switch result {
                case .done(let count):
                    datagrams.append(Data(buffer[0..<count]))
                    if datagrams.count > Self.maximumQueuedDatagrams { datagrams.removeFirst() }
                case .wouldBlock:
                    return
                case .failed(let error):
                    // ICMP errors (port unreachable: ECONNREFUSED, or ECONNRESET on
                    // Windows) surface on connected UDP sockets; they do not end a flow.
                    if [.ECONNREFUSED, .ECONNRESET, .EMSGSIZE].contains(error.code) { continue }
                    failLocked(error.nwError)
                    return
                }
            }
        }
        // Read ahead at most what the pending receives can take, so an unconsumed stream
        // applies back-pressure instead of growing without bound.
        let limit = receives.contains { $0.wholeMessage }
            ? Int.max : max(4 * Self.readChunk, receives.map(\.minimum).max() ?? 0)
        while !readEOF && inbound.count < limit {
            let result = buffer.withUnsafeMutableBytes { Sock.read(socket, $0) }
            switch result {
            case .done(0):
                readEOF = true
            case .done(let count):
                inbound.append(contentsOf: buffer[0..<count])
            case .wouldBlock:
                return
            case .failed(let error):
                failLocked(error.nwError)
                return
            }
        }
    }

    private func writeLocked() {
        while !sends.isEmpty {
            var item = sends[0]
            if isDatagram {
                if item.hasContent {
                    let result: IOResult
                    switch origin {
                    case .listenerDatagram(let demultiplexer, let remote):
                        result = demultiplexer.send(item.data, to: remote)
                    default:
                        guard socket != kInvalidSocket else { return }
                        result = item.data.withUnsafeBytes { Sock.write(socket, $0) }
                    }
                    switch result {
                    case .wouldBlock:
                        return
                    case .failed(let error):
                        sends.removeFirst()
                        completeLocked(item.completion, error.nwError)
                        continue
                    case .done:
                        break
                    }
                }
                sends.removeFirst()
                completeLocked(item.completion, nil)
                continue
            }
            guard socket != kInvalidSocket else { return }
            while item.offset < item.data.count {
                let offset = item.offset
                let result = item.data.withUnsafeBytes { raw in
                    Sock.write(socket, UnsafeRawBufferPointer(rebasing: raw[offset...]))
                }
                switch result {
                case .done(let count):
                    item.offset += count
                case .wouldBlock:
                    sends[0] = item
                    return
                case .failed(let error):
                    failLocked(error.nwError)
                    return
                }
            }
            sends.removeFirst()
            if item.closesStream { Sock.shutdownWrite(socket) }
            completeLocked(item.completion, nil)
        }
    }

    private func satisfyReceivesLocked() {
        while let receive = receives.first {
            if isDatagram {
                guard !datagrams.isEmpty else { return }
                let datagram = datagrams.removeFirst()
                receives.removeFirst()
                outbox.append { receive.completion(datagram, .defaultMessage, true, nil) }
            } else if receive.wholeMessage {
                guard readEOF else { return }
                let content = inbound
                inbound = Data()
                receives.removeFirst()
                outbox.append { receive.completion(content.isEmpty ? nil : content, .finalMessage, true, nil) }
            } else {
                guard inbound.count >= receive.minimum || readEOF else { return }
                let count = min(inbound.count, receive.maximum)
                let content = count > 0 ? Data(inbound.prefix(count)) : nil
                inbound = count == inbound.count ? Data() : Data(inbound.dropFirst(count))
                let complete = readEOF && inbound.isEmpty
                receives.removeFirst()
                let context: ContentContext = complete ? .finalMessage : .defaultMessage
                outbox.append { receive.completion(content, context, complete, nil) }
            }
        }
    }

    // MARK: Failure and teardown

    private func failLocked(_ error: NWError) {
        switch _state {
        case .cancelled, .failed: return
        default: break
        }
        closeSocketLocked()
        cancelTimersLocked()
        abortPendingLocked(with: error)
        transitionLocked(.failed(error))
    }

    private func abortPendingLocked(with error: NWError) {
        let pendingReceives = receives
        receives.removeAll()
        // Data already received is still delivered before the error.
        for receive in pendingReceives {
            if !inbound.isEmpty && !receive.wholeMessage {
                let content = inbound
                inbound = Data()
                outbox.append { receive.completion(content, .defaultMessage, false, nil) }
            } else {
                outbox.append { receive.completion(nil, nil, true, error) }
            }
        }
        let pendingSends = sends
        sends.removeAll()
        for send in pendingSends { completeLocked(send.completion, error) }
    }

    private func closeSocketLocked() {
        connecting = false
        guard socket != kInvalidSocket else { return }
        Reactor.shared.close(socket)
        socket = kInvalidSocket
        interest = (false, false)
    }

    private func cancelTimersLocked() {
        for timer in [retryTimer, timeoutTimer, connectPollTimer, attemptTimer] { timer?.cancel() }
        attemptTimer = nil
        retryTimer = nil
        timeoutTimer = nil
        connectPollTimer = nil
    }

    // MARK: Delivery

    private func transitionLocked(_ newState: State) {
        if case .cancelled = _state { return }
        guard _state != newState else { return }
        _state = newState
        if let handler = _stateUpdateHandler { outbox.append { handler(newState) } }
        if case .cancelled = newState {
            _stateUpdateHandler = nil
            _viabilityUpdateHandler = nil
            _pathUpdateHandler = nil
        }
    }

    private func completeLocked(_ completion: SendCompletion, _ error: NWError?) {
        if case .contentProcessed(let body) = completion { outbox.append { body(error) } }
    }

    /// Hands queued callbacks to the connection's queue, in order.
    private func flushLocked() {
        guard !outbox.isEmpty, let queue = _queue else { return }
        let work = outbox
        outbox.removeAll()
        queue.async { for item in work { item() } }
    }

    private func makeTimer(after delay: Double, repeating interval: Double? = nil,
                           _ body: @escaping (NWConnection) -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        if let interval {
            timer.schedule(deadline: .now() + delay, repeating: interval)
        } else {
            timer.schedule(deadline: .now() + delay)
        }
        // Strong on purpose: like Apple's, a started connection stays alive until it is
        // ready, failed or cancelled, all of which cancel these timers.
        timer.setEventHandler { body(self) }
        timer.resume()
        return timer
    }
}

extension NWConnection: ReactorHandler {
    func reactorReady(_ socket: NativeSocket, readable: Bool, writable: Bool, failed: Bool) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        guard socket == self.socket else { return }
        if connecting {
            if writable || failed { finishConnectLocked() }
            return
        }
        guard case .ready = _state else { return }
        if readable || failed {
            readLocked()
            satisfyReceivesLocked()
        }
        if writable, case .ready = _state { writeLocked() }
        updateInterestLocked()
    }
}
