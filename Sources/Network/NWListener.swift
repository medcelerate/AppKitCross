import Foundation

/// An object you use to listen for incoming network connections.
///
/// TCP listeners accept connections and hand each to `newConnectionHandler` in `.setup`
/// state. UDP listeners read from one socket and create a connection per remote address;
/// those connections send through the listener's socket. A `service` is advertised over
/// Bonjour (mDNS on `.local.`) once the listener is ready.
public final class NWListener: CustomDebugStringConvertible, @unchecked Sendable {
    /// A Bonjour service to advertise.
    public struct Service: Equatable, CustomDebugStringConvertible, Sendable {
        /// The instance name; nil uses the machine's host name.
        public let name: String?
        /// The service type, such as `_http._tcp`.
        public let type: String
        /// The domain; nil means `local.`, the only domain this port supports.
        public let domain: String?
        /// TXT record rdata.
        public private(set) var txtRecord: Data?
        /// Keep the name on a conflict with another service in this process instead of
        /// appending " (2)". Conflicts with other hosts are not detected.
        public var noAutoRename: Bool = false

        public var txtRecordObject: NWTXTRecord? {
            get { txtRecord.map { NWTXTRecord($0) } }
            set { txtRecord = newValue?.data }
        }

        public init(name: String? = nil, type: String, domain: String? = nil, txtRecord: Data? = nil) {
            self.name = name
            self.type = type
            self.domain = domain
            self.txtRecord = txtRecord
        }

        public init(name: String? = nil, type: String, domain: String? = nil, txtRecord: NWTXTRecord) {
            self.init(name: name, type: type, domain: domain, txtRecord: txtRecord.data)
        }

        public var debugDescription: String {
            "\(name ?? "<default>").\(type).\(domain ?? "local.")"
        }
    }

    /// Listener states.
    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case ready
        case failed(NWError)
        case cancelled
    }

    /// A change to the listener's advertised service.
    public enum ServiceRegistrationChange: Sendable {
        case add(NWEndpoint)
        case remove(NWEndpoint)
    }

    public let parameters: NWParameters
    private let requestedPort: NWEndpoint.Port

    private let lock = NSLock()
    private var _state: State = .setup
    private var _queue: DispatchQueue?
    private var _newConnectionHandler: (@Sendable (NWConnection) -> Void)?
    private var _stateUpdateHandler: (@Sendable (State) -> Void)?
    private var _serviceRegistrationUpdateHandler: (@Sendable (ServiceRegistrationChange) -> Void)?
    private var _service: Service?
    private var _port: NWEndpoint.Port?
    private var socket: NativeSocket = kInvalidSocket
    private var demultiplexer: UDPDemultiplexer?
    private var registrationID: Int?
    private var registeredEndpoint: NWEndpoint?
    private var outbox: [() -> Void] = []

    /// Creates a listener. The port in `parameters.requiredLocalEndpoint` is used when
    /// `on` is `.any`; port 0 picks an ephemeral port, reported by `port` once ready.
    public init(using: NWParameters, on: NWEndpoint.Port = .any) throws {
        if let local = using.requiredLocalEndpoint, case .hostPort = local {} else if using.requiredLocalEndpoint != nil {
            throw NWError.posix(.EINVAL)
        }
        parameters = using
        requestedPort = on
    }

    // MARK: Properties

    public var state: State { lock.locked { _state } }

    public var queue: DispatchQueue? { lock.locked { _queue } }

    /// The bound port, once the listener is ready.
    public var port: NWEndpoint.Port? { lock.locked { _port } }

    @preconcurrency public var newConnectionHandler: (@Sendable (_ connection: NWConnection) -> Void)? {
        get { lock.locked { _newConnectionHandler } }
        set { lock.locked { _newConnectionHandler = newValue } }
    }

    @preconcurrency public var stateUpdateHandler: (@Sendable (_ newState: NWListener.State) -> Void)? {
        get { lock.locked { _stateUpdateHandler } }
        set { lock.locked { _stateUpdateHandler = newValue } }
    }

    @preconcurrency public var serviceRegistrationUpdateHandler: (@Sendable (_ change: NWListener.ServiceRegistrationChange) -> Void)? {
        get { lock.locked { _serviceRegistrationUpdateHandler } }
        set { lock.locked { _serviceRegistrationUpdateHandler = newValue } }
    }

    /// The Bonjour service to advertise. Setting it on a ready listener re-registers.
    public var service: NWListener.Service? {
        get { lock.locked { _service } }
        set {
            lock.lock()
            defer { flushLocked(); lock.unlock() }
            _service = newValue
            if case .ready = _state {
                unregisterServiceLocked()
                registerServiceLocked()
            }
        }
    }

    public var debugDescription: String {
        let port = self.port.map { String($0.rawValue) } ?? "-"
        return "[listener \(parameters._transportName) port \(port) \(state)]"
    }

    // MARK: Lifecycle

    public func start(queue: DispatchQueue) {
        lock.lock()
        guard _queue == nil, case .setup = _state else { lock.unlock(); return }
        parameters._requireSupportedStack(for: "NWListener")
        _queue = queue
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { self.open() }
    }

    public func cancel() {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        if case .cancelled = _state { return }
        teardownLocked()
        transitionLocked(.cancelled)
    }

    private func open() {
        let isUDP = parameters._isUDP
        let type = isUDP ? kSOCK_DGRAM : kSOCK_STREAM
        var port = requestedPort.rawValue
        var addresses: [SocketAddress] = []
        if case .hostPort(let host, let localPort)? = parameters.requiredLocalEndpoint {
            if port == 0 { port = localPort.rawValue }
            if let literal = SocketAddress(host: host, port: port) {
                addresses = [literal]
            } else if case .name(let name, _) = host {
                switch Sock.resolve(host: name, port: port, type: type) {
                case .success(let resolved): addresses = resolved
                case .failure(let error): finishOpen(.failure(error)); return
                }
            }
        }
        let wildcard = addresses.isEmpty
        if wildcard {
            addresses = [SocketAddress(ipv6: [UInt8](repeating: 0, count: 16), port: port),
                         SocketAddress(ipv4: [0, 0, 0, 0], port: port)]
        }
        var lastError: NWError = .posix(.EADDRNOTAVAIL)
        for address in addresses {
            let handle: NativeSocket
            switch Sock.open(family: address.family, type: type) {
            case .success(let opened): handle = opened
            case .failure(let error): lastError = error.nwError; continue
            }
            if wildcard && address.family == kAF_INET6 { Sock.setInt(handle, kIPPROTO_IPV6, kIPV6_V6ONLY, 0) }
            if parameters.allowLocalEndpointReuse {
                #if os(Windows)
                // On Windows SO_REUSEADDR lets another socket take over a bound TCP port,
                // and a listener can rebind over TIME_WAIT without it; only UDP shares.
                if isUDP { Sock.setInt(handle, kSOL_SOCKET, kSO_REUSEADDR, 1) }
                #else
                Sock.setInt(handle, kSOL_SOCKET, kSO_REUSEADDR, 1)
                if isUDP { Sock.setInt(handle, kSOL_SOCKET, kSO_REUSEPORT, 1) }
                #endif
            }
            if let error = Sock.bind(handle, address) ?? (isUDP ? nil : Sock.listen(handle)) {
                Sock.close(handle)
                lastError = error.nwError
                continue
            }
            Sock.setNonBlocking(handle)
            finishOpen(.success(handle))
            return
        }
        finishOpen(.failure(lastError))
    }

    private func finishOpen(_ result: Result<NativeSocket, NWError>) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        switch result {
        case .failure(let error):
            transitionLocked(.failed(error))
        case .success(let handle):
            guard case .setup = _state else {
                Sock.close(handle)
                return
            }
            let local = Sock.localAddress(handle)
            _port = local.flatMap { NWEndpoint.Port(rawValue: $0.port) }
            if parameters._isUDP {
                let demultiplexer = UDPDemultiplexer(socket: handle, localAddress: local, parameters: parameters)
                demultiplexer.onNewPeer = { [weak self] connection in self?.offer([connection]) }
                self.demultiplexer = demultiplexer
                Reactor.shared.register(handle, handler: demultiplexer, read: true, write: false)
            } else {
                socket = handle
                Reactor.shared.register(handle, handler: self, read: true, write: false)
            }
            transitionLocked(.ready)
            registerServiceLocked()
        }
    }

    /// Hands new connections to `newConnectionHandler`, or closes them without one.
    private func offer(_ connections: [NWConnection]) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        guard case .ready = _state, let handler = _newConnectionHandler else {
            for connection in connections { connection.cancel() }
            return
        }
        for connection in connections { outbox.append { handler(connection) } }
    }

    // MARK: Bonjour

    private func registerServiceLocked() {
        guard let service = _service, let port = _port else { return }
        var id = 0
        id = MDNSEngine.shared.register(name: service.name, type: service.type, domain: service.domain,
                                        port: port.rawValue, txt: service.txtRecord ?? Data(),
                                        noAutoRename: service.noAutoRename) { [self] result in
            lock.lock()
            defer { flushLocked(); lock.unlock() }
            guard registrationID == id else { return }
            switch result {
            case .success(let endpoint):
                registeredEndpoint = endpoint
                if let handler = _serviceRegistrationUpdateHandler { outbox.append { handler(.add(endpoint)) } }
            case .failure(let error):
                registrationID = nil
                teardownLocked()
                transitionLocked(.failed(error))
            }
        }
        registrationID = id
    }

    private func unregisterServiceLocked() {
        if let id = registrationID { MDNSEngine.shared.unregister(id) }
        registrationID = nil
        if let endpoint = registeredEndpoint, let handler = _serviceRegistrationUpdateHandler {
            outbox.append { handler(.remove(endpoint)) }
        }
        registeredEndpoint = nil
    }

    // MARK: Internals

    private func teardownLocked() {
        unregisterServiceLocked()
        if socket != kInvalidSocket {
            Reactor.shared.close(socket)
            socket = kInvalidSocket
        }
        demultiplexer?.shutdown()
        demultiplexer = nil
    }

    private func transitionLocked(_ newState: State) {
        if case .cancelled = _state { return }
        guard _state != newState else { return }
        _state = newState
        if let handler = _stateUpdateHandler { outbox.append { handler(newState) } }
        if case .cancelled = newState {
            _stateUpdateHandler = nil
            _newConnectionHandler = nil
            _serviceRegistrationUpdateHandler = nil
        }
    }

    private func flushLocked() {
        guard !outbox.isEmpty, let queue = _queue else { return }
        let work = outbox
        outbox.removeAll()
        queue.async { for item in work { item() } }
    }
}

extension NWListener: ReactorHandler {
    func reactorReady(_ socket: NativeSocket, readable: Bool, writable: Bool, failed: Bool) {
        guard readable else { return }
        let localOnly = parameters.acceptLocalOnly
        let tcp = parameters._tcpOptions
        var accepted: [NWConnection] = []
        acceptLoop: while true {
            switch Sock.accept(socket) {
            case .success(let (client, remote)):
                guard let remote, !localOnly || remote.isLocalNetwork else {
                    Sock.close(client)
                    continue
                }
                Sock.setNonBlocking(client)
                if let tcp { NWConnection.applyTCPOptions(tcp, to: client) }
                accepted.append(NWConnection(accepted: client, remote: remote, parameters: parameters.copy()))
            case .failure(let error):
                // ECONNABORTED: the peer gave up while queued; keep draining.
                if error.code == .ECONNABORTED { continue }
                break acceptLoop
            }
        }
        if !accepted.isEmpty { offer(accepted) }
    }
}

/// The socket of a UDP listener, shared by the per-peer connections it creates.
final class UDPDemultiplexer: ReactorHandler, @unchecked Sendable {
    let localAddress: SocketAddress?
    private let socket: NativeSocket
    private let parameters: NWParameters
    private let lock = NSLock()
    private var peers: [SocketAddress: NWConnection] = [:]
    private var listening = true
    private var closed = false
    var onNewPeer: ((NWConnection) -> Void)?

    init(socket: NativeSocket, localAddress: SocketAddress?, parameters: NWParameters) {
        self.socket = socket
        self.localAddress = localAddress
        self.parameters = parameters
    }

    func reactorReady(_ socket: NativeSocket, readable: Bool, writable: Bool, failed: Bool) {
        guard readable else { return }
        var received: [(SocketAddress, Data)] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let (result, from) = buffer.withUnsafeMutableBytes { Sock.receiveFrom(socket, $0) }
            guard case .done(let count) = result else { break }
            if let from { received.append((from, Data(buffer[0..<count]))) }
        }
        var deliveries: [(NWConnection, Data)] = []
        var created: [NWConnection] = []
        let notify: ((NWConnection) -> Void)? = lock.locked {
            for (from, data) in received {
                if let peer = peers[from] {
                    deliveries.append((peer, data))
                } else if listening {
                    let peer = NWConnection(datagramPeer: from, demultiplexer: self, parameters: parameters.copy())
                    peers[from] = peer
                    created.append(peer)
                    deliveries.append((peer, data))
                }
            }
            return onNewPeer
        }
        for (peer, data) in deliveries { peer.deliverDatagram(data) }
        if let notify { for peer in created { notify(peer) } }
    }

    func send(_ data: Data, to remote: SocketAddress) -> IOResult {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return .failed(SocketError(.ENOTCONN)) }
        return data.withUnsafeBytes { Sock.sendTo(socket, $0, remote) }
    }

    func remove(_ remote: SocketAddress) {
        lock.locked {
            peers[remote] = nil
            closeIfIdleLocked()
        }
    }

    /// The listener was cancelled: accept no new peers, and close the socket once the
    /// existing peers are gone.
    func shutdown() {
        lock.locked {
            listening = false
            onNewPeer = nil
            closeIfIdleLocked()
        }
    }

    private func closeIfIdleLocked() {
        guard !listening, peers.isEmpty, !closed else { return }
        closed = true
        Reactor.shared.close(socket)
    }
}
