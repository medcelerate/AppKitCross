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
        // 30 s: the Windows CI runner has taken over 5 s to run a global-queue block
        // while the test binary and two compiler jobs shared its four cores.
        wait(for: [expectation], timeout: 30)
        XCTAssertEqual(value, 42)
        c.cancel()
    }

    /// A value and the completion behind it are scheduled on a concurrent queue with the
    /// same delay; the value must still arrive first (the port once let the completion
    /// overtake it and dropped the value). Apple's Combine gives no such guarantee on a
    /// concurrent queue (about one round in 200 loses the value on macOS), so this checks
    /// the port's Delay only.
    func testDelayKeepsValueBeforeCompletionOnConcurrentQueue() throws {
        #if canImport(Darwin)
        throw XCTSkip("Apple's Combine may deliver the completion before a delayed value on a concurrent queue")
        #endif
        var lost = 0
        for _ in 0..<200 {
            let expectation = expectation(description: "completed")
            var values: [Int] = []
            let c = Just(7)
                .delay(for: .milliseconds(1), scheduler: DispatchQueue.global())
                .sink(receiveCompletion: { _ in expectation.fulfill() }, receiveValue: { values.append($0) })
            wait(for: [expectation], timeout: 30)
            if values != [7] { lost += 1 }
            c.cancel()
        }
        XCTAssertEqual(lost, 0, "delayed values lost before their completion")
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

    // MARK: collect(.byTime) / collect(.byTimeOrCount)
    //
    // Driven by `VirtualTimeScheduler`, so the same expectations run against Apple's
    // Combine on macOS (where they were first observed) and the port elsewhere.

    private final class ArraySubscriber: Subscriber {
        typealias Input = [Int]
        typealias Failure = TestError
        let initialDemand: Subscribers.Demand
        var subscription: Subscription?
        var values: [[Int]] = []
        var completion: Subscribers.Completion<TestError>?
        init(initialDemand: Subscribers.Demand) { self.initialDemand = initialDemand }
        func receive(subscription: Subscription) {
            self.subscription = subscription
            subscription.request(initialDemand)
        }
        func receive(_ input: [Int]) -> Subscribers.Demand { values.append(input); return .none }
        func receive(completion: Subscribers.Completion<TestError>) { self.completion = completion }
    }

    func testCollectByTimeEmitsEachInterval() {
        let scheduler = VirtualTimeScheduler()
        let subject = PassthroughSubject<Int, TestError>()
        let sub = ArraySubscriber(initialDemand: .unlimited)
        subject.collect(.byTime(scheduler, .seconds(1))).subscribe(sub)
        XCTAssertEqual(scheduler.activeTimers, 1)        // the timer starts on subscription
        subject.send(1); subject.send(2)
        scheduler.advance(by: .milliseconds(999))
        XCTAssertEqual(sub.values, [])
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(sub.values, [[1, 2]])
        scheduler.advance(by: .seconds(1))               // empty interval: nothing sent
        XCTAssertEqual(sub.values, [[1, 2]])
        subject.send(3)
        subject.send(completion: .finished)
        XCTAssertEqual(scheduler.activeTimers, 0)        // completion stops the timer
        XCTAssertNil(sub.completion)                     // flush and completion go through the scheduler
        scheduler.advance(by: 0)
        XCTAssertEqual(sub.values, [[1, 2], [3]])
        XCTAssertEqual(sub.completion, .finished)
    }

    func testCollectByTimeFailureDropsBuffer() {
        let scheduler = VirtualTimeScheduler()
        let subject = PassthroughSubject<Int, TestError>()
        let sub = ArraySubscriber(initialDemand: .unlimited)
        subject.collect(.byTime(scheduler, .seconds(1))).subscribe(sub)
        subject.send(1)
        subject.send(completion: .failure(TestError()))
        scheduler.advance(by: .seconds(2))
        XCTAssertEqual(sub.values, [])
        XCTAssertEqual(sub.completion, .failure(TestError()))
    }

    func testCollectByTimeWaitsForDemand() {
        let scheduler = VirtualTimeScheduler()
        let subject = PassthroughSubject<Int, TestError>()
        let sub = ArraySubscriber(initialDemand: .max(1))
        subject.collect(.byTime(scheduler, .seconds(1))).subscribe(sub)
        subject.send(1)
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(sub.values, [[1]])
        subject.send(2)
        scheduler.advance(by: .seconds(1))               // no demand: the buffer is kept
        XCTAssertEqual(sub.values, [[1]])
        subject.send(3)
        sub.subscription?.request(.max(1))
        XCTAssertEqual(sub.values, [[1]])                // sent on the next interval, not at once
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(sub.values, [[1], [2, 3]])
        subject.send(4)
        subject.send(completion: .finished)              // finishing flushes even without demand
        scheduler.advance(by: 0)
        XCTAssertEqual(sub.values, [[1], [2, 3], [4]])
        XCTAssertEqual(sub.completion, .finished)
    }

    func testCollectByTimeOrCount() {
        let scheduler = VirtualTimeScheduler()
        let subject = PassthroughSubject<Int, TestError>()
        let sub = ArraySubscriber(initialDemand: .unlimited)
        subject.collect(.byTimeOrCount(scheduler, .seconds(1), 2)).subscribe(sub)
        subject.send(1); subject.send(2)
        XCTAssertEqual(sub.values, [])                   // a full buffer is sent through the scheduler
        scheduler.advance(by: 0)
        XCTAssertEqual(sub.values, [[1, 2]])
        subject.send(3)
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(sub.values, [[1, 2], [3]])
        subject.send(4); subject.send(5); subject.send(6)
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(sub.values, [[1, 2], [3], [4, 5], [6]])
    }

    func testCollectByTimeOrCountRequestsCountPerDemand() {
        let scheduler = VirtualTimeScheduler()
        let subject = PassthroughSubject<Int, TestError>()
        var requests: [Subscribers.Demand] = []
        let sub = ArraySubscriber(initialDemand: .max(1))
        subject.handleEvents(receiveRequest: { requests.append($0) })
            .collect(.byTimeOrCount(scheduler, .seconds(1), 2))
            .subscribe(sub)
        XCTAssertEqual(requests, [.max(2)])
        subject.send(1); subject.send(2)
        subject.send(3)                                  // beyond upstream demand: the subject drops it
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(sub.values, [[1, 2]])
        sub.subscription?.request(.max(2))
        XCTAssertEqual(requests, [.max(2), .max(4)])
        subject.send(4)
        scheduler.advance(by: .seconds(1))
        XCTAssertEqual(sub.values, [[1, 2], [4]])
        subject.send(completion: .finished)
        scheduler.advance(by: 0)
        XCTAssertEqual(sub.completion, .finished)
    }

    func testCollectByTimeCancelStopsTimer() {
        let scheduler = VirtualTimeScheduler()
        let subject = PassthroughSubject<Int, TestError>()
        let sub = ArraySubscriber(initialDemand: .unlimited)
        subject.collect(.byTime(scheduler, .seconds(1))).subscribe(sub)
        subject.send(1)
        XCTAssertEqual(scheduler.activeTimers, 1)
        sub.subscription?.cancel()
        XCTAssertEqual(scheduler.activeTimers, 0)
        scheduler.advance(by: .seconds(3))
        subject.send(2)
        XCTAssertEqual(sub.values, [])
        XCTAssertNil(sub.completion)
    }

    func testCollectByTimeOnRunLoop() {
        var batches: [[Int]] = []
        var finished = false
        let subject = PassthroughSubject<Int, Never>()
        let c = subject.collect(.byTime(RunLoop.main, .milliseconds(30)))
            .sink(receiveCompletion: { _ in finished = true }, receiveValue: { batches.append($0) })
        subject.send(1); subject.send(2)
        spin { !batches.isEmpty }
        XCTAssertEqual(batches, [[1, 2]])
        subject.send(3)
        subject.send(completion: .finished)
        spin { finished }
        XCTAssertEqual(batches, [[1, 2], [3]])
        c.cancel()
    }

    /// Full buffers, the final flush and the completion are scheduled on a concurrent
    /// queue; the port delivers them in order (like its Delay). Apple's Combine makes no
    /// such promise on a concurrent queue, so this checks the port only.
    func testCollectByTimeOrCountKeepsOrderOnConcurrentQueue() throws {
        #if canImport(Darwin)
        throw XCTSkip("Apple's Combine does not order deliveries on a concurrent queue")
        #endif
        for _ in 0..<20 {
            let expectation = expectation(description: "completed")
            let lock = NSLock()
            var batches: [[Int]] = []
            let subject = PassthroughSubject<Int, Never>()
            let c = subject.collect(.byTimeOrCount(DispatchQueue.global(), .milliseconds(5), 3))
                .sink(receiveCompletion: { _ in expectation.fulfill() },
                      receiveValue: { batch in lock.lock(); batches.append(batch); lock.unlock() })
            for i in 0..<300 { subject.send(i) }
            subject.send(completion: .finished)
            wait(for: [expectation], timeout: 30)
            lock.lock()
            XCTAssertEqual(batches.flatMap { $0 }, Array(0..<300))
            XCTAssertTrue(batches.allSatisfy { !$0.isEmpty && $0.count <= 3 })
            lock.unlock()
            c.cancel()
        }
    }

    // MARK: Optional.Publisher / Result.Publisher (Apple's spelling, no OCombine namespace)

    func testOptionalAndResultPublisherTypes() {
        let optional: Optional<Int>.Publisher = Optional(3).publisher
        let result: Result<Int, TestError>.Publisher = Result<Int, TestError>.success(4).publisher
        var values: [Int] = []
        let c1 = optional.sink { values.append($0) }
        let c2 = result.sink(receiveCompletion: { _ in }, receiveValue: { values.append($0) })
        let failed: Result<Int, TestError>.Publisher = .init(TestError())
        var failure: Subscribers.Completion<TestError>?
        let c3 = failed.sink(receiveCompletion: { failure = $0 }, receiveValue: { _ in })
        XCTAssertEqual(values, [3, 4])
        XCTAssertEqual(failure, .failure(TestError()))
        XCTAssertEqual(Optional<Int>.none.publisher, Optional<Int>.Publisher(nil))
        c1.cancel(); c2.cancel(); c3.cancel()
    }
}

private struct TestError: Error, Equatable {}

/// A scheduler whose clock moves only when a test advances it. Work runs in time order
/// (insertion order for equal times); repeating work reschedules itself until cancelled.
private final class VirtualTimeScheduler: Scheduler {
    struct SchedulerTimeType: Strideable, Hashable {
        var nanoseconds: Int

        func distance(to other: Self) -> Stride { Stride(other.nanoseconds - nanoseconds) }
        func advanced(by n: Stride) -> Self { Self(nanoseconds: nanoseconds + n.magnitude) }
        static func < (a: Self, b: Self) -> Bool { a.nanoseconds < b.nanoseconds }

        struct Stride: SchedulerTimeIntervalConvertible, Comparable, SignedNumeric, Hashable {
            var magnitude: Int
            init(_ value: Int) { magnitude = value }
            init(integerLiteral value: Int) { magnitude = value }
            init?<T: BinaryInteger>(exactly source: T) {
                guard let value = Int(exactly: source) else { return nil }
                magnitude = value
            }
            static func seconds(_ s: Int) -> Stride { Stride(s * 1_000_000_000) }
            static func seconds(_ s: Double) -> Stride { Stride(Int(s * 1e9)) }
            static func milliseconds(_ ms: Int) -> Stride { Stride(ms * 1_000_000) }
            static func microseconds(_ us: Int) -> Stride { Stride(us * 1_000) }
            static func nanoseconds(_ ns: Int) -> Stride { Stride(ns) }
            static func < (a: Stride, b: Stride) -> Bool { a.magnitude < b.magnitude }
            static func + (a: Stride, b: Stride) -> Stride { Stride(a.magnitude + b.magnitude) }
            static func - (a: Stride, b: Stride) -> Stride { Stride(a.magnitude - b.magnitude) }
            static func * (a: Stride, b: Stride) -> Stride { Stride(a.magnitude * b.magnitude) }
            static func += (a: inout Stride, b: Stride) { a = a + b }
            static func -= (a: inout Stride, b: Stride) { a = a - b }
            static func *= (a: inout Stride, b: Stride) { a = a * b }
        }
    }
    typealias SchedulerOptions = Never

    private(set) var now = SchedulerTimeType(nanoseconds: 0)
    var minimumTolerance: SchedulerTimeType.Stride { 0 }
    private(set) var activeTimers = 0
    private var sequence = 0
    private var queue: [(time: SchedulerTimeType, order: Int, work: () -> Void)] = []

    private func enqueue(_ time: SchedulerTimeType, _ work: @escaping () -> Void) {
        sequence += 1
        queue.append((time, sequence, work))
    }

    func schedule(options: Never?, _ action: @escaping () -> Void) {
        enqueue(now, action)
    }

    func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride,
                  options: Never?, _ action: @escaping () -> Void) {
        enqueue(date, action)
    }

    func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride,
                  tolerance: SchedulerTimeType.Stride, options: Never?,
                  _ action: @escaping () -> Void) -> Cancellable {
        final class Flag { var cancelled = false }
        let flag = Flag()
        activeTimers += 1
        func fire(at time: SchedulerTimeType) {
            enqueue(time) {
                guard !flag.cancelled else { return }
                action()
                fire(at: time.advanced(by: interval))
            }
        }
        fire(at: date)
        return AnyCancellable { [weak self] in
            guard !flag.cancelled else { return }
            flag.cancelled = true
            self?.activeTimers -= 1
        }
    }

    /// Runs everything due up to `now + stride`, then moves the clock there.
    func advance(by stride: SchedulerTimeType.Stride) {
        let target = now.advanced(by: stride)
        while let index = queue.indices
            .filter({ queue[$0].time.nanoseconds <= target.nanoseconds })
            .min(by: { (queue[$0].time.nanoseconds, queue[$0].order) < (queue[$1].time.nanoseconds, queue[$1].order) }) {
            let item = queue.remove(at: index)
            if item.time.nanoseconds > now.nanoseconds { now = item.time }
            item.work()
        }
        now = target
    }
}
