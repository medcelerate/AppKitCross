// Combine (ADR-0008): on macOS these run against Apple's Combine, on Windows and Linux
// against the OpenCombine port in Sources/Combine. Same source either way.

import XCTest
import Foundation
import Combine

private final class Counter {
    var value = 0
    var text = ""
}

private final class Model: ObservableObject {
    @Published var count = 0
    @Published var name = "a"
}

private struct Point: Codable, Equatable {
    var x: Int
    var y: Int
}

final class CombineTests: XCTestCase, @unchecked Sendable {

    /// Spins the main run loop until `condition` holds or `timeout` elapses.
    private func spin(timeout: TimeInterval = 2, until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }

    // MARK: Publishers and subjects

    func testJustAndFuture() {
        var received: [Int] = []
        var finished = false
        let c1 = Just(7).sink(receiveCompletion: { _ in finished = true },
                              receiveValue: { received.append($0) })
        XCTAssertEqual(received, [7])
        XCTAssertTrue(finished)
        c1.cancel()

        var promiseHandle: ((Result<String, Never>) -> Void)?
        let future = Future<String, Never> { promise in promiseHandle = promise }
        var futureValue: String?
        let c2 = future.sink { futureValue = $0 }
        XCTAssertNil(futureValue)
        promiseHandle?(.success("done"))
        XCTAssertEqual(futureValue, "done")
        // A Future replays its result to late subscribers.
        var late: String?
        let c3 = future.sink { late = $0 }
        XCTAssertEqual(late, "done")
        c2.cancel(); c3.cancel()
    }

    func testPassthroughAndCurrentValueSubjects() {
        let passthrough = PassthroughSubject<Int, Never>()
        var a: [Int] = []
        passthrough.send(0)                           // nobody listening: dropped
        let c1 = passthrough.sink { a.append($0) }
        passthrough.send(1); passthrough.send(2)
        XCTAssertEqual(a, [1, 2])

        let current = CurrentValueSubject<Int, Never>(10)
        var b: [Int] = []
        let c2 = current.sink { b.append($0) }
        XCTAssertEqual(b, [10])                       // replays the current value
        current.send(11)
        current.value = 12
        XCTAssertEqual(current.value, 12)
        XCTAssertEqual(b, [10, 11, 12])

        var completed = false
        let c3 = current.sink(receiveCompletion: { _ in completed = true }, receiveValue: { _ in })
        current.send(completion: .finished)
        XCTAssertTrue(completed)
        c1.cancel(); c2.cancel(); c3.cancel()
    }

    func testFailureCompletion() {
        struct Boom: Error {}
        let subject = PassthroughSubject<Int, Boom>()
        var failure: Boom?
        var values: [Int] = []
        let c = subject.sink(receiveCompletion: { completion in
            if case .failure(let error) = completion { failure = error }
        }, receiveValue: { values.append($0) })
        subject.send(1)
        subject.send(completion: .failure(Boom()))
        subject.send(2)                               // after completion: ignored
        XCTAssertEqual(values, [1])
        XCTAssertNotNil(failure)
        c.cancel()
    }

    // MARK: Operators

    func testMapFilterCompactMapFlatMap() {
        var out: [String] = []
        let evens: Publishers.Filter<Publishers.Sequence<ClosedRange<Int>, Never>> =
            (1...6).publisher.filter { (n: Int) -> Bool in n % 2 == 0 }
        let tens: Publishers.Map<Publishers.Filter<Publishers.Sequence<ClosedRange<Int>, Never>>, Int> =
            evens.map { (n: Int) -> Int in n * 10 }
        let strings = tens.compactMap { (n: Int) -> String? in n == 40 ? nil : String(n) }
        let shouted = strings.flatMap { (s: String) -> Just<String> in Just(s + "!") }
        let c = shouted.collect().sink { (all: [String]) in out = all }
        XCTAssertEqual(out, ["20!", "60!"])
        c.cancel()
    }

    func testMergeCombineLatestZip() {
        let a = PassthroughSubject<Int, Never>()
        let b = PassthroughSubject<Int, Never>()

        var merged: [Int] = []
        let c1 = a.merge(with: b).sink { merged.append($0) }

        var latest: [String] = []
        let c2 = a.combineLatest(b).map { "\($0)\($1)" }.sink { latest.append($0) }

        var zipped: [String] = []
        let c3 = a.zip(b).map { "\($0)\($1)" }.sink { zipped.append($0) }

        a.send(1)
        b.send(2)
        a.send(3)
        a.send(4)
        b.send(5)

        XCTAssertEqual(merged, [1, 2, 3, 4, 5])
        XCTAssertEqual(latest, ["12", "32", "42", "45"])
        XCTAssertEqual(zipped, ["12", "35"])
        c1.cancel(); c2.cancel(); c3.cancel()
    }

    func testMergeAndCombineLatestCompletion() {
        // Synchronous upstreams: Just completes inside its own request.
        var merged: [Int] = []
        var mergedDone = false
        let c1 = Just(1).merge(with: Just(2), Just(3))
            .sink(receiveCompletion: { _ in mergedDone = true }, receiveValue: { merged.append($0) })
        XCTAssertEqual(merged, [1, 2, 3])
        XCTAssertTrue(mergedDone)

        var many: [Int] = []
        let c2 = Publishers.MergeMany([Just(4), Just(5)]).collect().sink { many = $0 }
        XCTAssertEqual(many, [4, 5])

        // combineLatest finishes only when both finish; a side that finishes without a
        // value ends it right away.
        let a = PassthroughSubject<Int, Never>()
        let b = PassthroughSubject<String, Never>()
        var pairs: [String] = []
        var pairsDone = false
        let c3 = a.combineLatest(b) { "\($0)\($1)" }
            .sink(receiveCompletion: { _ in pairsDone = true }, receiveValue: { pairs.append($0) })
        a.send(1)
        b.send("x")
        a.send(completion: .finished)
        b.send("y")                                   // a's last value is still combined
        XCTAssertEqual(pairs, ["1x", "1y"])
        XCTAssertFalse(pairsDone)
        b.send(completion: .finished)
        XCTAssertTrue(pairsDone)

        var emptyDone = false
        var emptyValues = 0
        let c4 = Empty<Int, Never>().combineLatest(Just(1))
            .sink(receiveCompletion: { _ in emptyDone = true }, receiveValue: { _ in emptyValues += 1 })
        XCTAssertTrue(emptyDone)
        XCTAssertEqual(emptyValues, 0)

        // Backpressure: a merge buffers until the downstream asks.
        var pulled: [Int] = []
        let c5 = [10, 20, 30].publisher.merge(with: [40].publisher).first().sink { pulled.append($0) }
        XCTAssertEqual(pulled, [10])
        c1.cancel(); c2.cancel(); c3.cancel(); c4.cancel(); c5.cancel()
    }

    func testReduceScanRemoveDuplicatesFirstLast() {
        var sum = 0
        let c1 = [1, 2, 3, 4].publisher.reduce(0, +).sink { sum = $0 }
        XCTAssertEqual(sum, 10)

        var running: [Int] = []
        let c2 = [1, 2, 3].publisher.scan(0, +).sink { running.append($0) }
        XCTAssertEqual(running, [1, 3, 6])

        var dedup: [Int] = []
        let c3 = [1, 1, 2, 2, 2, 3, 1].publisher.removeDuplicates().sink { dedup.append($0) }
        XCTAssertEqual(dedup, [1, 2, 3, 1])

        var first: Int?
        var last: Int?
        let c4 = [5, 6, 7].publisher.first().sink { first = $0 }
        let c5 = [5, 6, 7].publisher.last().sink { last = $0 }
        XCTAssertEqual(first, 5)
        XCTAssertEqual(last, 7)
        c1.cancel(); c2.cancel(); c3.cancel(); c4.cancel(); c5.cancel()
    }

    func testDebounceOnRunLoop() {
        let subject = PassthroughSubject<Int, Never>()
        var received: [Int] = []
        let c = subject
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { received.append($0) }
        subject.send(1)
        subject.send(2)
        subject.send(3)
        XCTAssertEqual(received, [])
        spin { !received.isEmpty }
        XCTAssertEqual(received, [3])
        c.cancel()
    }

    func testDelayAndReceiveOnDispatchQueue() {
        let expectation = expectation(description: "delivered off the test thread")
        var value = 0
        let c = Just(42)
            .delay(for: .milliseconds(10), scheduler: DispatchQueue.global())
            .receive(on: DispatchQueue.global())
            .sink { v in
                value = v
                expectation.fulfill()
            }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(value, 42)
        c.cancel()
    }

    func testDecodeWithJSONDecoder() {
        let json = Data(#"{"x":1,"y":2}"#.utf8)
        var point: Point?
        var failed = false
        let c = Just(json)
            .decode(type: Point.self, decoder: JSONDecoder())
            .sink(receiveCompletion: { if case .failure = $0 { failed = true } },
                  receiveValue: { point = $0 })
        XCTAssertEqual(point, Point(x: 1, y: 2))
        XCTAssertFalse(failed)

        var encoded: Data?
        let c2 = Just(Point(x: 3, y: 4)).encode(encoder: JSONEncoder()).sink(
            receiveCompletion: { _ in }, receiveValue: { encoded = $0 })
        XCTAssertEqual(try JSONDecoder().decode(Point.self, from: XCTUnwrap(encoded)), Point(x: 3, y: 4))
        c.cancel(); c2.cancel()
    }

    // MARK: Subscribers

    func testSinkAndAssign() {
        let counter = Counter()
        let subject = PassthroughSubject<Int, Never>()
        let c1 = subject.assign(to: \.value, on: counter)
        let c2 = subject.map(String.init).assign(to: \.text, on: counter)
        subject.send(3)
        XCTAssertEqual(counter.value, 3)
        XCTAssertEqual(counter.text, "3")
        c1.cancel(); c2.cancel()
        subject.send(4)
        XCTAssertEqual(counter.value, 3)
    }

    func testAnyCancellableCancellation() {
        let subject = PassthroughSubject<Int, Never>()
        var received: [Int] = []
        var cancellables = Set<AnyCancellable>()
        subject.sink { received.append($0) }.store(in: &cancellables)
        subject.send(1)
        XCTAssertEqual(received, [1])
        cancellables.removeAll()                      // deinit of AnyCancellable cancels
        subject.send(2)
        XCTAssertEqual(received, [1])

        var cancelled = false
        let c = AnyCancellable { cancelled = true }
        c.cancel()
        XCTAssertTrue(cancelled)
    }

    // MARK: ObservableObject and @Published

    func testPublishedAndObservableObject() {
        let model = Model()
        var counts: [Int] = []
        var willChange = 0
        let c1 = model.$count.sink { counts.append($0) }
        let c2 = model.objectWillChange.sink { _ in willChange += 1 }
        XCTAssertEqual(counts, [0])                   // current value on subscription
        model.count = 1
        model.name = "b"
        model.count = 2
        XCTAssertEqual(counts, [0, 1, 2])
        XCTAssertEqual(willChange, 3)                 // once per @Published mutation
        XCTAssertEqual(model.count, 2)
        c1.cancel(); c2.cancel()
    }

    func testPublishedProjectedValueIsBeforeDidSet() {
        let model = Model()
        var seenBeforeAssignment: Int?
        let c = model.$count.dropFirst().sink { seenBeforeAssignment = model.count + 100 * $0 }
        model.count = 1
        // objectWillChange/`$count` fire before the stored value changes: old value 0 + 100 * 1.
        XCTAssertEqual(seenBeforeAssignment, 100)
        c.cancel()
    }

    // MARK: Foundation integration

    func testNotificationCenterPublisher() {
        let name = Notification.Name("AppKitCrossCombineTest")
        let sender = Counter()
        var names: [String] = []
        let c = NotificationCenter.default.publisher(for: name, object: sender)
            .compactMap { $0.userInfo?["k"] as? String }
            .sink { names.append($0) }
        NotificationCenter.default.post(name: name, object: sender, userInfo: ["k": "one"])
        NotificationCenter.default.post(name: name, object: Counter(), userInfo: ["k": "other"])  // wrong object
        NotificationCenter.default.post(name: name, object: sender, userInfo: ["k": "two"])
        XCTAssertEqual(names, ["one", "two"])
        c.cancel()
        NotificationCenter.default.post(name: name, object: sender, userInfo: ["k": "three"])
        XCTAssertEqual(names, ["one", "two"])
    }

    func testTimerPublisherAutoconnect() {
        var ticks: [Date] = []
        let c = Timer.publish(every: 0.02, on: .main, in: .default)
            .autoconnect()
            .sink { ticks.append($0) }
        spin { ticks.count >= 3 }
        XCTAssertGreaterThanOrEqual(ticks.count, 3)
        XCTAssertTrue(zip(ticks, ticks.dropFirst()).allSatisfy { $0 <= $1 })
        c.cancel()
        let count = ticks.count
        spin(timeout: 0.1) { false }
        XCTAssertEqual(ticks.count, count)            // cancelled: no more ticks
    }

    func testRunLoopScheduler() {
        var ran = false
        RunLoop.main.schedule { ran = true }
        spin { ran }
        XCTAssertTrue(ran)

        var later = false
        RunLoop.main.schedule(after: RunLoop.main.now.advanced(by: .milliseconds(20))) { later = true }
        XCTAssertFalse(later)
        spin { later }
        XCTAssertTrue(later)
    }
}
