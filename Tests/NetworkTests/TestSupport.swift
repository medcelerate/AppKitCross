import Foundation
import XCTest
#if canImport(NetworkPortable)
@testable import NetworkPortable
#else
@testable import Network
#endif

/// A thread-safe box for values that test callbacks collect.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func with<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var get: Value { with { $0 } }
}

extension XCTestCase {
    /// Starts a listener on 127.0.0.1 and waits for `.ready`. Accepted connections are
    /// started on `queue` and passed to `accepted`.
    func startLoopbackListener(_ parameters: NWParameters = .tcp, port: NWEndpoint.Port = .any,
                               queue: DispatchQueue,
                               accepted: @escaping @Sendable (NWConnection) -> Void = { _ in }) throws -> NWListener {
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            accepted(connection)
        }
        listener.start(queue: queue)
        wait(for: [ready], timeout: 5)
        return listener
    }

    /// Starts a connection and waits for `.ready`.
    func connect(to port: NWEndpoint.Port, using parameters: NWParameters = .tcp, queue: DispatchQueue) -> NWConnection {
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        let ready = expectation(description: "connection ready")
        connection.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        connection.start(queue: queue)
        wait(for: [ready], timeout: 5)
        return connection
    }
}
