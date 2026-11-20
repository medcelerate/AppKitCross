import Foundation
import XCTest
#if canImport(NetworkPortable)
@testable import NetworkPortable
#else
@testable import Network
#endif

final class MDNSWireTests: XCTestCase {
    private let type = DNSName(["_sibyl", "_tcp", "local"])
    private let host = DNSName(["box-1a2b", "local"])

    private func service(_ name: String, port: UInt16 = 4242, txt: [String: String] = ["id": "1"]) -> MDNSLocalService {
        MDNSLocalService(instance: type.prepending(name), type: type, port: port, txt: NWTXTRecord(txt).data)
    }

    func testRecordsRoundTrip() {
        let set = MDNSResponder.records(for: service("Desk Mic. 2"), host: host, addresses: [[192, 168, 1, 20]], ttl: 120)
        let aaaa = DNSRecord(name: host, type: DNSType.aaaa, cacheFlush: true, ttl: 120,
                             data: .aaaa(Array(IPv6Address("fd00::5")!.rawValue)))
        let message = DNSMessage(id: 7, flags: DNSMessage.responseFlags,
                                 questions: [DNSQuestion(name: type, type: DNSType.ptr, unicastResponse: true)],
                                 answers: [set.ptr], additionals: [set.srv, set.txt] + set.a + [aaaa])
        let decoded = DNSMessage(decoding: message.encoded())
        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded?.answers.first?.data, .ptr(type.prepending("Desk Mic. 2")))
        XCTAssertTrue(decoded?.additionals[0].cacheFlush ?? false)
        XCTAssertTrue(decoded?.questions[0].unicastResponse ?? false)
    }

    func testDecodesCompressedNames() {
        // Header, one answer: PTR _http._tcp.local -> Printer.<pointer to _http._tcp.local>.
        func label(_ text: String) -> [UInt8] { [UInt8(text.utf8.count)] + Array(text.utf8) }
        var bytes: [UInt8] = [0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0]
        let nameOffset = bytes.count
        bytes += label("_http")
        bytes += label("_tcp")
        bytes += label("local")
        bytes += [0, 0, 12, 0, 1, 0, 0, 0, 120]
        var rdata = label("Printer")
        rdata += [0xC0, UInt8(nameOffset)]
        bytes += [0, UInt8(rdata.count)]
        bytes += rdata
        let message = DNSMessage(decoding: bytes)
        XCTAssertEqual(message?.answers.first?.data, .ptr(DNSName(["Printer", "_http", "_tcp", "local"])))
    }

    func testRejectsMalformedAndLoopingMessages() {
        XCTAssertNil(DNSMessage(decoding: [0, 0, 0x84]))
        // A name that points at itself.
        let looping: [UInt8] = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0xC0, 12, 0, 12, 0, 1]
        XCTAssertNil(DNSMessage(decoding: looping))
    }

    func testResponderAnswersBrowseAndCacheYieldsInstances() {
        let services = [service("Alpha"), service("Beta", port: 5000, txt: ["id": "2"])]
        let query = DNSMessage(questions: [DNSQuestion(name: type, type: DNSType.ptr)])
        guard let reply = MDNSResponder.reply(to: query, services: services, host: host,
                                              addresses: [[10, 0, 0, 9]], ttl: 120),
              let wire = DNSMessage(decoding: reply.encoded()) else { return XCTFail("no reply") }
        XCTAssertEqual(wire.answers.count, 2)

        var cache = MDNSCache()
        for record in wire.answers + wire.additionals { cache.insert(record, now: 100) }
        let instances = cache.instances(of: type, now: 101)
        XCTAssertEqual(Set(instances.keys), ["Alpha", "Beta"])
        XCTAssertEqual(NWTXTRecord(instances["Beta"]!)["id"], "2")
        let beta = cache.service(type.prepending("Beta"), now: 101)
        XCTAssertEqual(beta?.port, 5000)
        XCTAssertEqual(beta.map { cache.addresses(of: $0.target, port: $0.port, now: 101) },
                       [SocketAddress(ipv4: [10, 0, 0, 9], port: 5000)])

        // TTL expiry removes them.
        XCTAssertTrue(cache.purge(now: 100 + 121))
        XCTAssertTrue(cache.instances(of: type, now: 100 + 121).isEmpty)
    }

    func testKnownAnswerSuppressionAndOtherQuestions() {
        let services = [service("Alpha")]
        let set = MDNSResponder.records(for: services[0], host: host, addresses: [[10, 0, 0, 9]], ttl: 120)
        var known = set.ptr
        known.ttl = 100
        let suppressed = DNSMessage(questions: [DNSQuestion(name: type, type: DNSType.ptr)], answers: [known])
        XCTAssertNil(MDNSResponder.reply(to: suppressed, services: services, host: host, addresses: [[10, 0, 0, 9]], ttl: 120))

        let srvQuery = DNSMessage(questions: [DNSQuestion(name: type.prepending("Alpha"), type: DNSType.srv)])
        let srvReply = MDNSResponder.reply(to: srvQuery, services: services, host: host, addresses: [[10, 0, 0, 9]], ttl: 120)
        XCTAssertEqual(srvReply?.answers, [set.srv])
        XCTAssertEqual(srvReply?.additionals, set.a)

        let unrelated = DNSMessage(questions: [DNSQuestion(name: DNSName(["_other", "_tcp", "local"]), type: DNSType.ptr)])
        XCTAssertNil(MDNSResponder.reply(to: unrelated, services: services, host: host, addresses: [[10, 0, 0, 9]], ttl: 120))
    }

    func testGoodbyeAndCacheFlush() {
        var cache = MDNSCache()
        let instance = type.prepending("Alpha")
        let srv = { (port: UInt16) in
            DNSRecord(name: instance, type: DNSType.srv, cacheFlush: true, ttl: 120,
                      data: .srv(priority: 0, weight: 0, port: port, target: self.host))
        }
        cache.insert(srv(1000), now: 0)
        // The peer restarted on a new port: cache-flush retires the old SRV after 1 s.
        cache.insert(srv(2000), now: 10)
        _ = cache.purge(now: 12)
        XCTAssertEqual(cache.service(instance, now: 12)?.port, 2000)

        let ptr = DNSRecord(name: type, type: DNSType.ptr, cacheFlush: false, ttl: 120, data: .ptr(instance))
        cache.insert(ptr, now: 0)
        var goodbye = ptr
        goodbye.ttl = 0
        cache.insert(goodbye, now: 5)
        XCTAssertFalse(cache.instances(of: type, now: 5.5).isEmpty)
        XCTAssertTrue(cache.instances(of: type, now: 6.5).isEmpty)
    }

    func testServiceTypeValidation() {
        XCTAssertEqual(MDNSEngine.serviceType("_sibyl._tcp", domain: nil), type)
        XCTAssertEqual(MDNSEngine.serviceType("_sibyl._tcp.", domain: "local."), type)
        XCTAssertNil(MDNSEngine.serviceType("sibyl", domain: nil))
        XCTAssertNil(MDNSEngine.serviceType("_sibyl._sctp", domain: nil))
    }
}
