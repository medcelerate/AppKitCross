/// Network: the subset of Apple's Network.framework that AppKitCross apps use, under
/// Apple's module name, type names and signatures, over BSD sockets (Linux, and macOS
/// for the `NetworkPortable` test build) and Winsock 2 (Windows).
///
/// Implemented: `NWEndpoint` (`hostPort`, `service`, `url`; `Host`, `Port`),
/// `IPv4Address`/`IPv6Address`, `NWInterface`, `NWTXTRecord`, `NWError`, `NWPath` (status
/// and endpoints), `NWParameters` (`.tcp`, `.udp`, `requiredLocalEndpoint`,
/// `allowLocalEndpointReuse`, `acceptLocalOnly`, `includePeerToPeer`, `serviceClass`,
/// `defaultProtocolStack`), `NWProtocolTCP.Options`/`NWProtocolUDP.Options`, `NWConnection`
/// (TCP and UDP, non-blocking connect with getaddrinfo and address fallback, waiting with
/// retry, `connectionTimeout`, stream and datagram receive, final-message half close),
/// `NWListener` (TCP accept, UDP demultiplexed into per-peer connections, Bonjour
/// advertising) and `NWBrowser` (Bonjour browsing). One reactor thread polls every socket
/// (`poll`/`WSAPoll`); callbacks run on the queue passed to `start(queue:)`.
///
/// Bonjour is a small pure-Swift mDNS/DNS-SD responder and browser on 224.0.0.251:5353
/// (IPv4 only): PTR/SRV/TXT/A records, announcements, goodbyes, known-answer suppression,
/// cache-flush and TTL expiry. Limitations: no name probing or conflict renaming against
/// other hosts, `.local.` domain only, no IPv6 multicast. Not implemented (these trap with
/// `unimplemented()` or are not declared): TLS/DTLS/QUIC/WebSocket, `.unix` endpoints,
/// `NWPathMonitor`, connection groups, framers, application services, establishment and
/// data-transfer reports. `viabilityUpdateHandler` is stored but never called, because
/// no path monitoring exists to make a connection non-viable.

/// Terminates with a message naming the unimplemented Network symbol.
@inline(never)
func unimplemented(_ symbol: String = #function, file: StaticString = #fileID, line: UInt = #line) -> Never {
    fatalError("AppKitCross: `\(symbol)` is not implemented yet", file: file, line: line)
}
