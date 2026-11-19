// A small mDNS/DNS-SD responder, browser and resolver (RFC 6762, RFC 6763) on one IPv4
// multicast socket bound to 0.0.0.0:5353 and joined to 224.0.0.251 on every interface.
// All state lives on `queue`; the reactor only reads datagrams and hands them over.

import Foundation

/// A service this process advertises.
struct MDNSLocalService: Equatable {
    /// `<instance>.<_type>.<_tcp>.local`.
    let instance: DNSName
    /// `<_type>.<_tcp>.local`.
    let type: DNSName
    let port: UInt16
    let txt: Data
}

/// The record cache shared by browsing and resolution. Times are seconds on a
/// monotonic clock, passed in so the logic is testable.
struct MDNSCache {
    struct Key: Hashable {
        let name: DNSName
        let type: UInt16
    }

    struct Entry {
        let record: DNSRecord
        let received: Double
        var expires: Double
    }

    private(set) var entries: [Key: [[UInt8]: Entry]] = [:]

    mutating func insert(_ record: DNSRecord, now: Double) {
        let key = Key(name: record.name, type: record.type)
        let rdata = record.data.bytes
        var set = entries[key] ?? [:]
        if record.ttl == 0 {
            // Goodbye: keep the record for one more second (RFC 6762 section 10.1).
            if var entry = set[rdata] {
                entry.expires = min(entry.expires, now + 1)
                set[rdata] = entry
            }
        } else {
            if record.cacheFlush {
                // Section 10.2: other records of this name and type that are more than a
                // second old are stale.
                for (other, var entry) in set where other != rdata && entry.received < now - 1 {
                    entry.expires = min(entry.expires, now + 1)
                    set[other] = entry
                }
            }
            set[rdata] = Entry(record: record, received: now, expires: now + Double(record.ttl))
        }
        entries[key] = set.isEmpty ? nil : set
    }

    /// Drops expired records; true when anything was removed.
    mutating func purge(now: Double) -> Bool {
        var changed = false
        for (key, set) in entries {
            let live = set.filter { $0.value.expires > now }
            if live.count != set.count {
                changed = true
                entries[key] = live.isEmpty ? nil : live
            }
        }
        return changed
    }

    /// Live records, newest first.
    func records(_ name: DNSName, _ type: UInt16, now: Double) -> [DNSRecord] {
        (entries[Key(name: name, type: type)] ?? [:]).values
            .filter { $0.expires > now }
            .sorted { $0.received > $1.received }
            .map(\.record)
    }

    /// Records worth listing as known answers in a query: more than half their TTL left.
    func knownAnswers(_ name: DNSName, _ type: UInt16, now: Double) -> [DNSRecord] {
        (entries[Key(name: name, type: type)] ?? [:]).values.compactMap { entry in
            let remaining = entry.expires - now
            guard remaining > Double(entry.record.ttl) / 2 else { return nil }
            var record = entry.record
            record.ttl = UInt32(remaining)
            return record
        }
    }

    /// Instances of a service type: instance label to TXT rdata.
    func instances(of type: DNSName, now: Double) -> [String: Data] {
        var result: [String: Data] = [:]
        for record in records(type, DNSType.ptr, now: now) {
            guard case .ptr(let target) = record.data, target.isChild(of: type) else { continue }
            let txt = records(target, DNSType.txt, now: now).first.flatMap { record -> Data? in
                if case .txt(let data) = record.data { return data }
                return nil
            }
            result[target.labels[0]] = txt ?? Data()
        }
        return result
    }

    /// The SRV target and port of an instance, if known.
    func service(_ instance: DNSName, now: Double) -> (target: DNSName, port: UInt16)? {
        for record in records(instance, DNSType.srv, now: now) {
            if case .srv(_, _, let port, let target) = record.data { return (target, port) }
        }
        return nil
    }

    /// The addresses of a host, IPv4 first; link-local IPv6 is skipped (no scope known).
    func addresses(of host: DNSName, port: UInt16, now: Double) -> [SocketAddress] {
        var addresses: [SocketAddress] = []
        for record in records(host, DNSType.a, now: now) {
            if case .a(let bytes) = record.data { addresses.append(SocketAddress(ipv4: bytes, port: port)) }
        }
        for record in records(host, DNSType.aaaa, now: now) {
            if case .aaaa(let bytes) = record.data, !IPv6Address(_bytes: bytes).isLinkLocal {
                addresses.append(SocketAddress(ipv6: bytes, port: port))
            }
        }
        return addresses
    }
}

/// Builds responses to queries for this process's services. Pure.
enum MDNSResponder {
    static let serviceEnumeration = DNSName(["_services", "_dns-sd", "_udp", "local"])

    static func records(for service: MDNSLocalService, host: DNSName, addresses: [[UInt8]], ttl: UInt32)
        -> (ptr: DNSRecord, srv: DNSRecord, txt: DNSRecord, a: [DNSRecord]) {
        let ptr = DNSRecord(name: service.type, type: DNSType.ptr, cacheFlush: false, ttl: ttl, data: .ptr(service.instance))
        let srv = DNSRecord(name: service.instance, type: DNSType.srv, cacheFlush: true, ttl: ttl,
                            data: .srv(priority: 0, weight: 0, port: service.port, target: host))
        let txt = DNSRecord(name: service.instance, type: DNSType.txt, cacheFlush: true, ttl: ttl, data: .txt(service.txt))
        return (ptr, srv, txt, hostRecords(host: host, addresses: addresses, ttl: ttl))
    }

    static func hostRecords(host: DNSName, addresses: [[UInt8]], ttl: UInt32) -> [DNSRecord] {
        addresses.map { DNSRecord(name: host, type: DNSType.a, cacheFlush: true, ttl: ttl, data: .a($0)) }
    }

    /// The records answering `query`, or nil when it asks about nothing of ours.
    static func reply(to query: DNSMessage, services: [MDNSLocalService], host: DNSName,
                      addresses: [[UInt8]], ttl: UInt32) -> DNSMessage? {
        var answers: [DNSRecord] = []
        var additionals: [DNSRecord] = []
        func suppressed(_ record: DNSRecord) -> Bool {
            query.answers.contains { $0.name == record.name && $0.type == record.type && $0.data == record.data && $0.ttl >= record.ttl / 2 }
        }
        func answer(_ record: DNSRecord) {
            if !suppressed(record), !answers.contains(record) { answers.append(record) }
        }
        func extra(_ record: DNSRecord) {
            if !additionals.contains(record) { additionals.append(record) }
        }
        for question in query.questions {
            func wants(_ type: UInt16) -> Bool { question.type == type || question.type == DNSType.any }
            for service in services {
                let set = records(for: service, host: host, addresses: addresses, ttl: ttl)
                if question.name == service.type && wants(DNSType.ptr) {
                    answer(set.ptr)
                    extra(set.srv)
                    extra(set.txt)
                    set.a.forEach(extra)
                }
                if question.name == serviceEnumeration && wants(DNSType.ptr) {
                    answer(DNSRecord(name: serviceEnumeration, type: DNSType.ptr, cacheFlush: false, ttl: ttl, data: .ptr(service.type)))
                }
                if question.name == service.instance {
                    if wants(DNSType.srv) { answer(set.srv); set.a.forEach(extra) }
                    if wants(DNSType.txt) { answer(set.txt) }
                }
            }
            if question.name == host && wants(DNSType.a) && !services.isEmpty {
                hostRecords(host: host, addresses: addresses, ttl: ttl).forEach(answer)
            }
        }
        guard !answers.isEmpty else { return nil }
        additionals.removeAll { answers.contains($0) }
        return DNSMessage(flags: DNSMessage.responseFlags, answers: answers, additionals: additionals)
    }
}

/// The process-wide mDNS endpoint.
final class MDNSEngine: ReactorHandler, @unchecked Sendable {
    static let shared = MDNSEngine()

    static let group: [UInt8] = [224, 0, 0, 251]
    static let port: UInt16 = 5353
    /// TTL of our records. Short (RFC 6762 suggests 120 s for host records) so peers that
    /// vanish without a goodbye drop out of browse results within two minutes.
    static let ttl: UInt32 = 120
    private static let maximumQueryInterval: Double = 60
    private static let resolveTimeout: Double = 5

    private struct Browse {
        let type: DNSName
        let handler: (Result<[String: Data], NWError>) -> Void
        var last: [String: Data]?
        var interval: Double
        var nextQuery: Double
    }

    private struct Resolution {
        let instance: DNSName
        let deadline: Double
        var nextQuery: Double
        let completion: (Result<[SocketAddress], NWError>) -> Void
    }

    private struct Registration {
        let service: MDNSLocalService
        var announcements: Int
        var nextAnnouncement: Double
    }

    let queue = DispatchQueue(label: "Network.mDNS")
    let hostName: DNSName
    private let idLock = NSLock()
    private var lastID = 0

    // Confined to `queue`.
    private var socket: NativeSocket = kInvalidSocket
    private var failure: (error: NWError, at: Double)?
    private var interfaces: [LocalInterface] = []
    private var joined: Set<[UInt8]> = []
    private var lastInterfaceScan: Double = 0
    private var registrations: [Int: Registration] = [:]
    private var browses: [Int: Browse] = [:]
    private var resolutions: [Int: Resolution] = [:]
    private var cache = MDNSCache()
    private var timer: DispatchSourceTimer?

    private init() {
        // A host name of our own, so our A records never contradict the operating
        // system's responder (which would treat identical names as a conflict).
        let suffix = String(UInt32.random(in: 0...0xFF_FFFF), radix: 16)
        hostName = DNSName([Sock.hostLabel() + "-" + suffix, "local"])
    }

    static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    private func nextID() -> Int {
        idLock.locked { lastID += 1; return lastID }
    }

    /// `_type._tcp` plus the domain as a DNS name; nil for a malformed type. Traps for
    /// domains other than `local.` (wide-area DNS-SD is not implemented).
    static func serviceType(_ type: String, domain: String?) -> DNSName? {
        if let domain, !["", "local", "local."].contains(domain.lowercased()) {
            unimplemented("Bonjour in the domain \"\(domain)\" (only local. is supported)")
        }
        let labels = type.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
        guard labels.count >= 2, ["_tcp", "_udp"].contains(labels.last!.lowercased()),
              labels.allSatisfy({ $0.hasPrefix("_") && (2...63).contains($0.utf8.count) }) else { return nil }
        return DNSName(labels + ["local"])
    }

    // MARK: API (any thread; callbacks run on `queue`)

    func register(name: String?, type: String, domain: String?, port: UInt16, txt: Data, noAutoRename: Bool,
                  completion: @escaping (Result<NWEndpoint, NWError>) -> Void) -> Int {
        let typeName = Self.serviceType(type, domain: domain)
        let id = nextID()
        queue.async { [self] in
            guard let typeName else { completion(.failure(.dns(_DNSServiceError.badParam))); return }
            var label = name ?? Sock.hostLabel()
            guard (1...63).contains(label.utf8.count) else { completion(.failure(.dns(_DNSServiceError.badParam))); return }
            guard ensureRunning() else { completion(.failure(failure!.error)); return }
            let base = label
            var attempt = 1
            while registrations.values.contains(where: { $0.service.instance == typeName.prepending(label) }) {
                guard !noAutoRename else { completion(.failure(.dns(_DNSServiceError.nameConflict))); return }
                attempt += 1
                label = "\(base) (\(attempt))"
            }
            let service = MDNSLocalService(instance: typeName.prepending(label), type: typeName, port: port, txt: txt)
            registrations[id] = Registration(service: service, announcements: 0, nextAnnouncement: Self.now())
            announceDue()
            completion(.success(.service(name: label, type: type, domain: "local.", interface: nil)))
            notifyBrowses()
        }
        return id
    }

    func unregister(_ id: Int) {
        queue.async { [self] in
            guard let registration = registrations.removeValue(forKey: id) else { return }
            var goodbye = MDNSResponder.records(for: registration.service, host: hostName, addresses: [], ttl: 0)
            goodbye.a = []
            sendMulticast(DNSMessage(flags: DNSMessage.responseFlags, answers: [goodbye.ptr, goodbye.srv, goodbye.txt]))
            notifyBrowses()
        }
    }

    func browse(type: String, domain: String?, handler: @escaping (Result<[String: Data], NWError>) -> Void) -> Int {
        let typeName = Self.serviceType(type, domain: domain)
        let id = nextID()
        queue.async { [self] in
            guard let typeName else { handler(.failure(.dns(_DNSServiceError.badParam))); return }
            guard ensureRunning() else { handler(.failure(failure!.error)); return }
            browses[id] = Browse(type: typeName, handler: handler, last: nil, interval: 1, nextQuery: Self.now())
            queryDue()
            notifyBrowses()
        }
        return id
    }

    func stopBrowse(_ id: Int) {
        queue.async { [self] in browses[id] = nil }
    }

    /// Resolves an instance to addresses: this process's own services directly, others
    /// from the cache or by SRV/A queries for up to five seconds.
    func resolve(instance: String, type: String, domain: String,
                 completion: @escaping (Result<[SocketAddress], NWError>) -> Void) {
        let typeName = Self.serviceType(type, domain: domain)
        let id = nextID()
        queue.async { [self] in
            guard let typeName else { completion(.failure(.dns(_DNSServiceError.badParam))); return }
            let name = typeName.prepending(instance)
            if let local = registrations.values.first(where: { $0.service.instance == name }) {
                let port = local.service.port
                completion(.success([SocketAddress(ipv4: [127, 0, 0, 1], port: port)]
                    + hostAddresses().filter { $0 != [127, 0, 0, 1] }.map { SocketAddress(ipv4: $0, port: port) }))
                return
            }
            guard ensureRunning() else { completion(.failure(failure!.error)); return }
            if let addresses = cachedAddresses(name) {
                completion(.success(addresses))
                return
            }
            let now = Self.now()
            resolutions[id] = Resolution(instance: name, deadline: now + Self.resolveTimeout, nextQuery: now + 1, completion: completion)
            sendResolveQuery(name)
        }
    }

    // MARK: Socket

    private func ensureRunning() -> Bool {
        if socket != kInvalidSocket { return true }
        if let failure, Self.now() - failure.at < 10 { return false }
        switch openSocket() {
        case .success(let handle):
            socket = handle
            failure = nil
            refreshInterfaces()
            Reactor.shared.register(handle, handler: self, read: true, write: false)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
            return true
        case .failure(let error):
            failure = (error, Self.now())
            return false
        }
    }

    private func openSocket() -> Result<NativeSocket, NWError> {
        let handle: NativeSocket
        switch Sock.open(family: kAF_INET, type: kSOCK_DGRAM) {
        case .success(let opened): handle = opened
        case .failure(let error): return .failure(error.nwError)
        }
        // Share 5353 with the system responder (mDNSResponder, avahi, Windows' DNS
        // client), which all bind it with address reuse.
        Sock.setInt(handle, kSOL_SOCKET, kSO_REUSEADDR, 1)
        #if !os(Windows)
        Sock.setInt(handle, kSOL_SOCKET, kSO_REUSEPORT, 1)
        #endif
        if let error = Sock.bind(handle, SocketAddress(ipv4: [0, 0, 0, 0], port: Self.port)) {
            Sock.close(handle)
            return .failure(error.nwError)
        }
        Sock.setNonBlocking(handle)
        Sock.setByteOrInt(handle, kIPPROTO_IP, kIP_MULTICAST_TTL, 255)
        Sock.setByteOrInt(handle, kIPPROTO_IP, kIP_MULTICAST_LOOP, 1)
        return .success(handle)
    }

    private func refreshInterfaces() {
        lastInterfaceScan = Self.now()
        interfaces = Sock.ipv4Interfaces()
        for interface in interfaces where !joined.contains(interface.ipv4) {
            if Sock.joinMulticast(socket, group: Self.group, interface: interface.ipv4) { joined.insert(interface.ipv4) }
        }
        if joined.isEmpty, Sock.joinMulticast(socket, group: Self.group, interface: [0, 0, 0, 0]) {
            joined.insert([0, 0, 0, 0])
        }
    }

    /// Addresses for our A records: the non-loopback IPv4 interfaces, or loopback when
    /// the machine has none.
    private func hostAddresses() -> [[UInt8]] {
        let addresses = interfaces.filter { !$0.isLoopback }.map(\.ipv4)
        return addresses.isEmpty ? [[127, 0, 0, 1]] : addresses
    }

    private func sendMulticast(_ message: DNSMessage) {
        guard socket != kInvalidSocket else { return }
        let bytes = message.encoded()
        let group = SocketAddress(ipv4: Self.group, port: Self.port)
        let outgoing = interfaces.filter { !$0.isLoopback }
        let targets = outgoing.isEmpty ? interfaces.filter(\.isLoopback) : outgoing
        if targets.isEmpty {
            _ = bytes.withUnsafeBytes { Sock.sendTo(socket, $0, group) }
            return
        }
        for interface in targets {
            _ = Sock.setMulticastInterface(socket, interface.ipv4)
            _ = bytes.withUnsafeBytes { Sock.sendTo(socket, $0, group) }
        }
    }

    private func sendUnicast(_ message: DNSMessage, to address: SocketAddress) {
        guard socket != kInvalidSocket else { return }
        _ = message.encoded().withUnsafeBytes { Sock.sendTo(socket, $0, address) }
    }

    func reactorReady(_ socket: NativeSocket, readable: Bool, writable: Bool, failed: Bool) {
        guard readable else { return }
        var packets: [([UInt8], SocketAddress)] = []
        var buffer = [UInt8](repeating: 0, count: 9_000)
        while true {
            let (result, from) = buffer.withUnsafeMutableBytes { Sock.receiveFrom(socket, $0) }
            guard case .done(let count) = result else { break }
            if let from { packets.append((Array(buffer[0..<count]), from)) }
        }
        guard !packets.isEmpty else { return }
        let received = packets
        queue.async { [self] in
            for (bytes, from) in received { handle(bytes, from: from) }
        }
    }

    // MARK: Protocol

    func handle(_ bytes: [UInt8], from: SocketAddress) {
        guard let message = DNSMessage(decoding: bytes) else { return }
        if message.isResponse {
            // RFC 6762 section 6: responses come from port 5353; anything else is not
            // a multicast DNS responder.
            guard from.port == Self.port else { return }
            let now = Self.now()
            for record in message.answers + message.additionals
            where [DNSType.ptr, DNSType.srv, DNSType.txt, DNSType.a, DNSType.aaaa].contains(record.type) {
                cache.insert(record, now: now)
            }
            notifyBrowses()
            progressResolutions()
        } else {
            answer(message, from: from)
        }
    }

    private func answer(_ query: DNSMessage, from: SocketAddress) {
        let services = registrations.values.map(\.service)
        guard !services.isEmpty else { return }
        let legacy = from.port != Self.port
        guard var reply = MDNSResponder.reply(to: query, services: services, host: hostName,
                                              addresses: hostAddresses(), ttl: legacy ? 10 : Self.ttl) else { return }
        if legacy {
            // A one-shot resolver (section 6.7): unicast, echoing the ID and questions.
            reply.id = query.id
            reply.questions = query.questions
            sendUnicast(reply, to: from)
        } else if query.questions.allSatisfy(\.unicastResponse) {
            sendUnicast(reply, to: from)
        } else {
            sendMulticast(reply)
        }
    }

    private func tick() {
        let now = Self.now()
        if cache.purge(now: now) { notifyBrowses() }
        if now - lastInterfaceScan > 30 { refreshInterfaces() }
        queryDue()
        announceDue()
        progressResolutions()
    }

    private func announceDue() {
        let now = Self.now()
        var records: [DNSRecord] = []
        for (id, var registration) in registrations where registration.announcements < 3 && registration.nextAnnouncement <= now {
            let set = MDNSResponder.records(for: registration.service, host: hostName, addresses: hostAddresses(), ttl: Self.ttl)
            for record in [set.ptr, set.srv, set.txt] + set.a where !records.contains(record) { records.append(record) }
            registration.announcements += 1
            registration.nextAnnouncement = now + Double(1 << registration.announcements)
            registrations[id] = registration
        }
        if !records.isEmpty { sendMulticast(DNSMessage(flags: DNSMessage.responseFlags, answers: records)) }
    }

    private func queryDue() {
        let now = Self.now()
        var questions: [DNSQuestion] = []
        var known: [DNSRecord] = []
        for (id, var browse) in browses where browse.nextQuery <= now {
            if !questions.contains(where: { $0.name == browse.type }) {
                questions.append(DNSQuestion(name: browse.type, type: DNSType.ptr))
                known += cache.knownAnswers(browse.type, DNSType.ptr, now: now)
            }
            browse.nextQuery = now + browse.interval
            browse.interval = min(browse.interval * 2, Self.maximumQueryInterval)
            browses[id] = browse
        }
        if !questions.isEmpty { sendMulticast(DNSMessage(questions: questions, answers: known)) }
    }

    private func notifyBrowses() {
        let now = Self.now()
        for (id, var browse) in browses {
            var instances = cache.instances(of: browse.type, now: now)
            for registration in registrations.values where registration.service.type == browse.type {
                instances[registration.service.instance.labels[0]] = registration.service.txt
            }
            guard instances != browse.last else { continue }
            browse.last = instances
            browses[id] = browse
            browse.handler(.success(instances))
        }
    }

    private func cachedAddresses(_ instance: DNSName) -> [SocketAddress]? {
        let now = Self.now()
        guard let service = cache.service(instance, now: now) else { return nil }
        let addresses = cache.addresses(of: service.target, port: service.port, now: now)
        return addresses.isEmpty ? nil : addresses
    }

    private func sendResolveQuery(_ instance: DNSName) {
        var questions = [DNSQuestion(name: instance, type: DNSType.srv)]
        if let service = cache.service(instance, now: Self.now()) {
            questions.append(DNSQuestion(name: service.target, type: DNSType.a))
        }
        sendMulticast(DNSMessage(questions: questions))
    }

    private func progressResolutions() {
        let now = Self.now()
        for (id, var resolution) in resolutions {
            if let addresses = cachedAddresses(resolution.instance) {
                resolutions[id] = nil
                resolution.completion(.success(addresses))
            } else if now >= resolution.deadline {
                resolutions[id] = nil
                resolution.completion(.failure(.dns(_DNSServiceError.noSuchRecord)))
            } else if now >= resolution.nextQuery {
                resolution.nextQuery = now + 1
                resolutions[id] = resolution
                sendResolveQuery(resolution.instance)
            }
        }
    }
}
