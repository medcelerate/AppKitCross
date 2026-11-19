import Foundation
import XCTest
#if canImport(NetworkPortable)
@testable import NetworkPortable
#else
@testable import Network
#endif

final class ConnectionTests: XCTestCase {
    private let queue = DispatchQueue(label: "NetworkTests")

    func testListenerReportsEphemeralPortAndReady() throws {
        let listener = try startLoopbackListener(queue: queue)
        defer { listener.cancel() }
        XCTAssertEqual(listener.state, .ready)
        let port = try XCTUnwrap(listener.port)
        XCTAssertNotEqual(port, .any)
    }

    func testSendIsReceivedByAcceptedConnection() throws {
        let server = Locked<NWConnection?>(nil)
        let accepted = expectation(description: "accepted")
        let listener = try startLoopbackListener(queue: queue) { connection in
            server.with { $0 = connection }
            accepted.fulfill()
        }
        defer { listener.cancel() }
        let client = connect(to: listener.port!, queue: queue)
        defer { client.cancel() }
        XCTAssertEqual(client.currentPath?.status, .satisfied)

        let sent = expectation(description: "sent")
        client.send(content: Data("hello".utf8), completion: .contentProcessed { error in
            XCTAssertNil(error)
            sent.fulfill()
        })
        wait(for: [accepted, sent], timeout: 5)

        let received = expectation(description: "received")
        let connection = try XCTUnwrap(server.get)
        connection.receive(minimumIncompleteLength: 5, maximumLength: 1024) { data, _, isComplete, error in
            XCTAssertEqual(data, Data("hello".utf8))
            XCTAssertFalse(isComplete, "a default message does not end the stream")
            XCTAssertNil(error)
            received.fulfill()
        }
        wait(for: [received], timeout: 5)

        // A final message with no content ends the stream: the receiver sees isComplete.
        let finished = expectation(description: "end of stream")
        client.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
            XCTAssertNil(data)
            XCTAssertTrue(isComplete)
            XCTAssertNil(error)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        connection.cancel()
    }

    func testStreamOfSendsIsReassembled() throws {
        let server = Locked<NWConnection?>(nil)
        let accepted = expectation(description: "accepted")
        let listener = try startLoopbackListener(queue: queue) { connection in
            server.with { $0 = connection }
            accepted.fulfill()
        }
        defer { listener.cancel() }
        let client = connect(to: listener.port!, queue: queue)
        defer { client.cancel() }

        var expected = Data()
        for index in 0..<8 {
            let chunk = Data(repeating: UInt8(index), count: 3000)
            expected.append(chunk)
            client.send(content: chunk, isComplete: false, completion: .idempotent)
        }
        wait(for: [accepted], timeout: 5)

        let received = expectation(description: "received")
        server.get?.receive(minimumIncompleteLength: expected.count, maximumLength: expected.count) { data, _, _, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, expected)
            received.fulfill()
        }
        wait(for: [received], timeout: 5)

        // Then a receive smaller than what is buffered returns at most maximumLength.
        client.send(content: Data(repeating: 9, count: 100), completion: .idempotent)
        let partial = expectation(description: "partial")
        server.get?.receive(minimumIncompleteLength: 10, maximumLength: 40) { data, _, _, _ in
            XCTAssertEqual(data?.count, 40)
            partial.fulfill()
        }
        wait(for: [partial], timeout: 5)
        server.get?.cancel()
    }

    func testServerCloseDeliversCompletion() throws {
        let listener = try startLoopbackListener(queue: queue) { connection in
            connection.send(content: Data("bye".utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
        defer { listener.cancel() }
        let client = connect(to: listener.port!, queue: queue)
        defer { client.cancel() }

        let collected = Locked(Data())
        let done = expectation(description: "complete")
        @Sendable func receiveLoop() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data { collected.with { $0.append(data) } }
                XCTAssertNil(error)
                if isComplete { done.fulfill() } else { receiveLoop() }
            }
        }
        receiveLoop()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(collected.get, Data("bye".utf8))
    }

    func testConnectingToClosedPortWaitsOrFails() throws {
        let listener = try startLoopbackListener(queue: queue)
        let port = try XCTUnwrap(listener.port)
        let cancelled = expectation(description: "listener cancelled")
        listener.stateUpdateHandler = { if case .cancelled = $0 { cancelled.fulfill() } }
        listener.cancel()
        wait(for: [cancelled], timeout: 5)
        Thread.sleep(forTimeInterval: 0.1) // the reactor closes the socket after its poll

        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let refused = expectation(description: "refused")
        connection.stateUpdateHandler = { state in
            switch state {
            case .waiting(let error), .failed(let error):
                XCTAssertEqual(error, .posix(.ECONNREFUSED))
                refused.fulfill()
            default:
                break
            }
        }
        connection.start(queue: queue)
        wait(for: [refused], timeout: 5)
        let gone = expectation(description: "cancelled")
        connection.stateUpdateHandler = { if case .cancelled = $0 { gone.fulfill() } }
        connection.cancel()
        wait(for: [gone], timeout: 5)
    }

    func testConnectionTimeoutFails() throws {
        // A name that cannot resolve keeps the connection waiting; the timeout fails it.
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.transportProtocol as! NWProtocolTCP.Options).connectionTimeout = 1
        let connection = NWConnection(host: "nonexistent.invalid", port: 9, using: parameters)
        let failed = expectation(description: "failed")
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                XCTAssertEqual(error, .posix(.ETIMEDOUT))
                failed.fulfill()
            }
        }
        connection.start(queue: queue)
        wait(for: [failed], timeout: 5)
        connection.cancel()
    }

    func testPendingReceiveCompletesWithCancelError() throws {
        let listener = try startLoopbackListener(queue: queue)
        defer { listener.cancel() }
        let client = connect(to: listener.port!, queue: queue)
        let aborted = expectation(description: "aborted")
        client.receive(minimumIncompleteLength: 1, maximumLength: 10) { data, _, _, error in
            XCTAssertNil(data)
            XCTAssertEqual(error, .posix(.ECANCELED))
            aborted.fulfill()
        }
        client.cancel()
        wait(for: [aborted], timeout: 5)
        XCTAssertEqual(client.state, .cancelled)
    }

    func testUDPDatagramsBothWays() throws {
        let serverSide = Locked<NWConnection?>(nil)
        let request = expectation(description: "request")
        let listener = try startLoopbackListener(.udp, queue: queue) { connection in
            serverSide.with { $0 = connection }
            connection.receiveMessage { data, _, isComplete, error in
                XCTAssertEqual(data, Data("ping".utf8))
                XCTAssertTrue(isComplete)
                XCTAssertNil(error)
                connection.send(content: Data("pong".utf8), completion: .idempotent)
                request.fulfill()
            }
        }
        defer { listener.cancel() }
        let client = connect(to: listener.port!, using: .udp, queue: queue)
        defer { client.cancel() }

        let reply = expectation(description: "reply")
        client.receiveMessage { data, _, isComplete, error in
            XCTAssertEqual(data, Data("pong".utf8))
            XCTAssertTrue(isComplete)
            XCTAssertNil(error)
            reply.fulfill()
        }
        client.send(content: Data("ping".utf8), completion: .contentProcessed { XCTAssertNil($0) })
        wait(for: [request, reply], timeout: 5)
        XCTAssertEqual(serverSide.get?.endpoint, client.currentPath?.localEndpoint)
        serverSide.get?.cancel()
    }

    func testRequiredLocalEndpointWithReuseRebindsSamePort() throws {
        let first = NWParameters.tcp
        first.allowLocalEndpointReuse = true
        let server = Locked<NWConnection?>(nil)
        let accepted = expectation(description: "accepted")
        let listener = try startLoopbackListener(first, queue: queue) { connection in
            server.with { $0 = connection }
            accepted.fulfill()
        }
        let port = try XCTUnwrap(listener.port)
        let client = connect(to: port, queue: queue)
        wait(for: [accepted], timeout: 5)
        // The server closes first, leaving the port in TIME_WAIT.
        server.get?.cancel()
        client.cancel()
        let cancelled = expectation(description: "listener cancelled")
        listener.stateUpdateHandler = { if case .cancelled = $0 { cancelled.fulfill() } }
        listener.cancel()
        wait(for: [cancelled], timeout: 5)
        Thread.sleep(forTimeInterval: 0.1)

        let second = NWParameters.tcp
        second.allowLocalEndpointReuse = true
        let again = try startLoopbackListener(second, port: port, queue: queue)
        defer { again.cancel() }
        XCTAssertEqual(again.port, port)
        let check = connect(to: port, queue: queue)
        check.cancel()
    }

    func testBindingAPortInUseFails() throws {
        let listener = try startLoopbackListener(queue: queue)
        defer { listener.cancel() }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: listener.port!)
        let clash = try NWListener(using: parameters)
        let failed = expectation(description: "failed")
        clash.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                XCTAssertEqual(error, .posix(.EADDRINUSE))
                failed.fulfill()
            }
        }
        clash.newConnectionHandler = { _ in }
        clash.start(queue: queue)
        wait(for: [failed], timeout: 5)
        clash.cancel()
    }
}
