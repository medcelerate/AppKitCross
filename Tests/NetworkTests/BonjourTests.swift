import Foundation
import XCTest
#if canImport(NetworkPortable)
@testable import NetworkPortable
#else
@testable import Network
#endif

/// Advertises with a listener and finds it with a browser in the same process, then
/// connects to the found service. Skips when the mDNS socket cannot be opened (port 5353
/// held exclusively, or no multicast).
final class BonjourTests: XCTestCase {
    private let queue = DispatchQueue(label: "BonjourTests")

    func testListenerAdvertisesAndBrowserFindsAndConnects() throws {
        let type = "_nwtest\(UInt16.random(in: 1000...9999))._tcp"
        let name = "Test \(UUID().uuidString.prefix(8))"

        let received = expectation(description: "server received")
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(name: name, type: type, txtRecord: NWTXTRecord(["peer": "x"]))
        let outcome = Locked<NWListener.State?>(nil)
        let settled = expectation(description: "listener settled")
        let registered = expectation(description: "registered")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed:
                if outcome.with({ old in defer { old = state }; return old == nil }) { settled.fulfill() }
            default: break
            }
        }
        listener.serviceRegistrationUpdateHandler = { change in
            if case .add(let endpoint) = change {
                XCTAssertEqual(endpoint, .service(name: name, type: type, domain: "local.", interface: nil))
                registered.fulfill()
            }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 2, maximumLength: 100) { data, _, _, _ in
                XCTAssertEqual(data, Data("hi".utf8))
                received.fulfill()
                connection.cancel()
            }
        }
        listener.start(queue: queue)
        defer { listener.cancel() }
        wait(for: [settled], timeout: 5)
        if case .failed(let error) = outcome.get {
            throw XCTSkip("mDNS unavailable here: \(error)")
        }
        wait(for: [registered], timeout: 5)

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: .tcp)
        let found = expectation(description: "found")
        let endpoint = Locked<NWEndpoint?>(nil)
        browser.browseResultsChangedHandler = { results, changes in
            for result in results {
                guard case .service(let resultName, _, _, _) = result.endpoint, resultName == name else { continue }
                XCTAssertEqual(result.metadata, .bonjour(NWTXTRecord(["peer": "x"])))
                XCTAssertTrue(changes.contains(.added(result)))
                if endpoint.with({ old in defer { old = result.endpoint }; return old == nil }) { found.fulfill() }
            }
        }
        browser.start(queue: queue)
        defer { browser.cancel() }
        wait(for: [found], timeout: 10)

        let connection = NWConnection(to: try XCTUnwrap(endpoint.get), using: .tcp)
        let ready = expectation(description: "ready")
        connection.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        connection.start(queue: queue)
        wait(for: [ready], timeout: 10)
        connection.send(content: Data("hi".utf8), completion: .idempotent)
        wait(for: [received], timeout: 5)
        connection.cancel()

        // Cancelling the listener withdraws the service from the browser.
        let removed = expectation(description: "removed")
        browser.browseResultsChangedHandler = { results, _ in
            if !results.contains(where: { $0.endpoint == endpoint.get }) { removed.fulfill() }
        }
        listener.cancel()
        wait(for: [removed], timeout: 5)
    }
}
