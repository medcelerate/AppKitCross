import Foundation

/// A network protocol (TCP, UDP). Concrete protocols subclass this.
public class NWProtocol: @unchecked Sendable {
    init() {}
}

/// Identifies a protocol in a stack.
public class NWProtocolDefinition: Equatable, CustomDebugStringConvertible, @unchecked Sendable {
    public final let name: String

    init(name: String) { self.name = name }

    public static func == (lhs: NWProtocolDefinition, rhs: NWProtocolDefinition) -> Bool { lhs.name == rhs.name }
    public var debugDescription: String { name }
}

/// Options for one protocol in a stack. Concrete protocols subclass this.
public class NWProtocolOptions: @unchecked Sendable {
    init() {}
    func _copy() -> NWProtocolOptions { self }
}

/// Per-message protocol metadata. Concrete protocols subclass this.
public class NWProtocolMetadata: @unchecked Sendable {
    init() {}
}

/// TCP.
public class NWProtocolTCP: NWProtocol, @unchecked Sendable {
    public static let definition = NWProtocolDefinition(name: "tcp")

    /// TCP options. `noDelay` (TCP_NODELAY), `enableKeepalive` and the keepalive timings
    /// (SO_KEEPALIVE, TCP_KEEPIDLE/TCP_KEEPALIVE, TCP_KEEPINTVL, TCP_KEEPCNT, in seconds;
    /// 0 keeps the system default) are applied to the socket. `connectionTimeout` (seconds;
    /// 0 waits indefinitely) fails a connection that is not ready in time with ETIMEDOUT.
    public class Options: NWProtocolOptions, @unchecked Sendable {
        public var noDelay: Bool = false
        public var enableKeepalive: Bool = false
        public var keepaliveCount: Int = 0
        public var keepaliveIdle: Int = 0
        public var keepaliveInterval: Int = 0
        public var connectionTimeout: Int = 0

        public override init() { super.init() }

        override func _copy() -> NWProtocolOptions {
            let copy = Options()
            copy.noDelay = noDelay
            copy.enableKeepalive = enableKeepalive
            copy.keepaliveCount = keepaliveCount
            copy.keepaliveIdle = keepaliveIdle
            copy.keepaliveInterval = keepaliveInterval
            copy.connectionTimeout = connectionTimeout
            return copy
        }
    }
}

/// UDP.
public class NWProtocolUDP: NWProtocol, @unchecked Sendable {
    public static let definition = NWProtocolDefinition(name: "udp")

    /// UDP options.
    public class Options: NWProtocolOptions, @unchecked Sendable {
        /// Checksums are always computed by these platforms' stacks; the flag is kept for
        /// source compatibility.
        public var preferNoChecksum: Bool = false

        public override init() { super.init() }

        override func _copy() -> NWProtocolOptions {
            let copy = Options()
            copy.preferNoChecksum = preferNoChecksum
            return copy
        }
    }
}

/// Settings for connections, listeners and browsers.
public final class NWParameters: CustomDebugStringConvertible, @unchecked Sendable {
    /// The protocols a connection is built from.
    public class ProtocolStack {
        private let lock = NSLock()
        private var _applicationProtocols: [NWProtocolOptions]
        private var _transportProtocol: NWProtocolOptions?

        init(transport: NWProtocolOptions?, application: [NWProtocolOptions] = []) {
            _transportProtocol = transport
            _applicationProtocols = application
        }

        /// Application protocols above the transport (TLS, WebSocket, framers). This port
        /// implements none, so a connection or listener with any here traps on start.
        public var applicationProtocols: [NWProtocolOptions] {
            get { lock.locked { _applicationProtocols } }
            set { lock.locked { _applicationProtocols = newValue } }
        }

        public var transportProtocol: NWProtocolOptions? {
            get { lock.locked { _transportProtocol } }
            set { lock.locked { _transportProtocol = newValue } }
        }
    }

    /// Traffic class hint. Stored for source compatibility; these platforms' sockets have
    /// no equivalent that applies without extra privileges, so it does not change traffic.
    public enum ServiceClass: Sendable {
        case bestEffort
        case background
        case interactiveVideo
        case interactiveVoice
        case responsiveData
        case signaling
    }

    private let lock = NSLock()
    private var _requiredLocalEndpoint: NWEndpoint?
    private var _allowLocalEndpointReuse = false
    private var _acceptLocalOnly = false
    private var _includePeerToPeer = false
    private var _serviceClass: ServiceClass = .bestEffort

    public final let defaultProtocolStack: NWParameters.ProtocolStack

    /// Parameters with no transport protocol. A connection or listener needs TCP or UDP
    /// in `defaultProtocolStack.transportProtocol` before it starts.
    public init() {
        defaultProtocolStack = ProtocolStack(transport: nil)
    }

    init(transport: NWProtocolOptions) {
        defaultProtocolStack = ProtocolStack(transport: transport)
    }

    /// Default TCP parameters.
    public class var tcp: NWParameters { NWParameters(transport: NWProtocolTCP.Options()) }

    /// Default UDP parameters.
    public class var udp: NWParameters { NWParameters(transport: NWProtocolUDP.Options()) }

    /// The local address and port to bind to. A listener binds here (port 0 or `.any`
    /// picks an ephemeral port); a connection binds its socket here before connecting.
    public final var requiredLocalEndpoint: NWEndpoint? {
        get { lock.locked { _requiredLocalEndpoint } }
        set { lock.locked { _requiredLocalEndpoint = newValue } }
    }

    /// Sets SO_REUSEADDR (and on UDP SO_REUSEPORT where it exists) before binding.
    public final var allowLocalEndpointReuse: Bool {
        get { lock.locked { _allowLocalEndpointReuse } }
        set { lock.locked { _allowLocalEndpointReuse = newValue } }
    }

    /// Listeners accept only peers on loopback, link-local or private (RFC 1918, ULA)
    /// addresses.
    public final var acceptLocalOnly: Bool {
        get { lock.locked { _acceptLocalOnly } }
        set { lock.locked { _acceptLocalOnly = newValue } }
    }

    /// Peer-to-peer interfaces (AWDL) do not exist on these platforms, so this has no
    /// effect; Bonjour always uses the ordinary interfaces.
    public final var includePeerToPeer: Bool {
        get { lock.locked { _includePeerToPeer } }
        set { lock.locked { _includePeerToPeer = newValue } }
    }

    public final var serviceClass: NWParameters.ServiceClass {
        get { lock.locked { _serviceClass } }
        set { lock.locked { _serviceClass = newValue } }
    }

    public final func copy() -> NWParameters {
        let copy = NWParameters()
        copy.defaultProtocolStack.transportProtocol = defaultProtocolStack.transportProtocol?._copy()
        copy.defaultProtocolStack.applicationProtocols = defaultProtocolStack.applicationProtocols
        copy.requiredLocalEndpoint = requiredLocalEndpoint
        copy.allowLocalEndpointReuse = allowLocalEndpointReuse
        copy.acceptLocalOnly = acceptLocalOnly
        copy.includePeerToPeer = includePeerToPeer
        copy.serviceClass = serviceClass
        return copy
    }

    public final var debugDescription: String {
        var parts: [String] = [_transportName]
        if let local = requiredLocalEndpoint { parts.append("local: \(local.debugDescription)") }
        if allowLocalEndpointReuse { parts.append("reuse local address") }
        if acceptLocalOnly { parts.append("local only") }
        return parts.joined(separator: ", ")
    }

    // MARK: Internal

    var _tcpOptions: NWProtocolTCP.Options? { defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options }
    var _isUDP: Bool { defaultProtocolStack.transportProtocol is NWProtocolUDP.Options }

    var _transportName: String {
        switch defaultProtocolStack.transportProtocol {
        case is NWProtocolTCP.Options: return "tcp"
        case is NWProtocolUDP.Options: return "udp"
        default: return "no transport"
        }
    }

    /// Traps for stacks this port cannot run: no transport, or application protocols.
    func _requireSupportedStack(for symbol: String) {
        if !defaultProtocolStack.applicationProtocols.isEmpty {
            unimplemented("\(symbol) with application protocols (TLS, WebSocket, framers)")
        }
        let transport = defaultProtocolStack.transportProtocol
        if !(transport is NWProtocolTCP.Options || transport is NWProtocolUDP.Options) {
            unimplemented("\(symbol) without a TCP or UDP transport protocol")
        }
    }
}
