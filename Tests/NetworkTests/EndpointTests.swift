import Foundation
import XCTest
#if canImport(NetworkPortable)
@testable import NetworkPortable
#else
@testable import Network
#endif

final class EndpointTests: XCTestCase {
    func testHostParsesAddressLiteralsAndNames() {
        XCTAssertEqual(NWEndpoint.Host("127.0.0.1"), .ipv4(.loopback))
        XCTAssertEqual(NWEndpoint.Host("::1"), .ipv6(.loopback))
        if case .name(let name, nil) = NWEndpoint.Host("example.com") {
            XCTAssertEqual(name, "example.com")
        } else {
            XCTFail("expected a name")
        }
        let literal: NWEndpoint.Host = "10.0.0.2"
        XCTAssertEqual(literal.debugDescription, "10.0.0.2")
        XCTAssertNil(IPv4Address("256.1.1.1"))
        XCTAssertNil(IPv4Address("1.2.3"))
    }

    func testIPv6TextRoundTrips() {
        let cases = ["::", "::1", "fe80::1", "2001:db8::8:800:200c:417a", "2001:db8::1:0:0:1", "::ffff:192.0.2.1", "ff02::fb"]
        for text in cases {
            guard let address = IPv6Address(text) else { XCTFail("parse \(text)"); continue }
            XCTAssertEqual(address.debugDescription, text)
        }
        XCTAssertEqual(IPv6Address("2001:0db8:0000:0000:0000:0000:0000:0001")?.debugDescription, "2001:db8::1")
        XCTAssertNil(IPv6Address("1::2::3"))
        XCTAssertNil(IPv6Address("12345::"))
        XCTAssertTrue(IPv6Address("fe80::1")!.isLinkLocal)
        XCTAssertEqual(IPv6Address("::ffff:10.1.2.3")?.asIPv4, IPv4Address("10.1.2.3"))
        XCTAssertEqual(IPv6Address("ff02::1")?.multicastScope, .linkLocal)
    }

    func testPorts() {
        XCTAssertEqual(NWEndpoint.Port(rawValue: 8080)?.rawValue, 8080)
        XCTAssertEqual(NWEndpoint.Port.any.rawValue, 0)
        let literal: NWEndpoint.Port = 443
        XCTAssertEqual(literal, .https)
        XCTAssertEqual(NWEndpoint.Port("80"), .http)
        XCTAssertEqual(NWEndpoint.Port("http"), .http)
        XCTAssertNil(NWEndpoint.Port("not-a-service-name"))
    }

    func testEndpointDescriptions() {
        XCTAssertEqual(NWEndpoint.hostPort(host: "127.0.0.1", port: 80).debugDescription, "127.0.0.1:80")
        XCTAssertEqual(NWEndpoint.hostPort(host: "::1", port: 80).debugDescription, "[::1]:80")
        XCTAssertEqual(NWEndpoint.service(name: "A", type: "_x._tcp", domain: "local.", interface: nil).debugDescription,
                       "A._x._tcp.local.")
    }

    func testErrorDescriptions() {
        let refused = NWError.posix(.ECONNREFUSED)
        XCTAssertTrue(refused.debugDescription.contains("Connection refused"), refused.debugDescription)
        XCTAssertTrue(refused.localizedDescription.contains("Connection refused"), refused.localizedDescription)
        XCTAssertEqual(NWError.dns(-65554).debugDescription, "-65554: NoSuchRecord")
        XCTAssertNotEqual(NWError.posix(.ECONNREFUSED), NWError.posix(.ETIMEDOUT))
    }

    func testTXTRecord() {
        var record = NWTXTRecord(["peer": "abc", "v": "1"])
        record.setEntry(.empty, for: "flag")
        let decoded = NWTXTRecord(record.data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded["peer"], "abc")
        XCTAssertEqual(decoded.getEntry(for: "flag"), .empty)
        XCTAssertEqual(decoded.dictionary, ["peer": "abc", "v": "1", "flag": ""])
        record.removeEntry(key: "peer")
        XCTAssertNil(record["peer"])
        XCTAssertEqual(record.count, 2)
    }

    func testParametersCopyAndDefaults() {
        let tcp = NWParameters.tcp
        XCTAssertTrue(tcp.defaultProtocolStack.transportProtocol is NWProtocolTCP.Options)
        XCTAssertTrue(NWParameters.udp.defaultProtocolStack.transportProtocol is NWProtocolUDP.Options)
        tcp.serviceClass = .signaling
        tcp.allowLocalEndpointReuse = true
        let copy = tcp.copy()
        XCTAssertEqual(copy.serviceClass, .signaling)
        XCTAssertTrue(copy.allowLocalEndpointReuse)
        XCTAssertFalse(NWParameters.tcp === NWParameters.tcp, "each access returns fresh parameters")
    }
}
