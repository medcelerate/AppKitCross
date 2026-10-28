//
//  Publishers.CombineLatest.swift
//  Combine (ported from OpenCombine)
//
//  AppKitWin addition: OpenCombine 0.14.0 lists CombineLatest in its remaining
//  interface and does not implement it. The declarations below are Apple's; the
//  implementation is shared by the three arities through `CombineLatestInner`, which
//  keeps the latest value of every type-erased upstream and emits a tuple whenever one
//  of them publishes once all have. It finishes when every upstream has finished, or
//  as soon as one finishes without ever publishing (no tuple can follow), and fails on
//  the first failure.

// swiftlint:disable file_length large_tuple

extension Publishers {

    /// A publisher that receives and combines the latest elements from two publishers.
    public struct CombineLatest<A: Publisher, B: Publisher>: Publisher
        where A.Failure == B.Failure
    {
        public typealias Output = (A.Output, B.Output)

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public init(_ a: A, _ b: B) {
            self.a = a
            self.b = b
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where B.Failure == Downstream.Failure,
                  Downstream.Input == (A.Output, B.Output)
        {
            CombineLatestInner(
                downstream: subscriber,
                upstreams: [a.eraseOutput(), b.eraseOutput()],
                combine: { ($0[0] as! A.Output, $0[1] as! B.Output) } // swiftlint:disable:this force_cast
            ).start()
        }
    }

    /// A publisher that receives and combines the latest elements from three
    /// publishers.
    public struct CombineLatest3<A: Publisher, B: Publisher, C: Publisher>: Publisher
        where A.Failure == B.Failure, B.Failure == C.Failure
    {
        public typealias Output = (A.Output, B.Output, C.Output)

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public init(_ a: A, _ b: B, _ c: C) {
            self.a = a
            self.b = b
            self.c = c
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where C.Failure == Downstream.Failure,
                  Downstream.Input == (A.Output, B.Output, C.Output)
        {
            CombineLatestInner(
                downstream: subscriber,
                upstreams: [a.eraseOutput(), b.eraseOutput(), c.eraseOutput()],
                combine: { ($0[0] as! A.Output, $0[1] as! B.Output, $0[2] as! C.Output) } // swiftlint:disable:this force_cast
            ).start()
        }
    }

    /// A publisher that receives and combines the latest elements from four publishers.
    public struct CombineLatest4<A: Publisher, B: Publisher, C: Publisher, D: Publisher>
        : Publisher
        where A.Failure == B.Failure, B.Failure == C.Failure, C.Failure == D.Failure
    {
        public typealias Output = (A.Output, B.Output, C.Output, D.Output)

        public typealias Failure = A.Failure

        public let a: A

        public let b: B

        public let c: C

        public let d: D

        public init(_ a: A, _ b: B, _ c: C, _ d: D) {
            self.a = a
            self.b = b
            self.c = c
            self.d = d
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where D.Failure == Downstream.Failure,
                  Downstream.Input == (A.Output, B.Output, C.Output, D.Output)
        {
            CombineLatestInner(
                downstream: subscriber,
                upstreams: [a.eraseOutput(), b.eraseOutput(), c.eraseOutput(), d.eraseOutput()],
                combine: { ($0[0] as! A.Output, $0[1] as! B.Output, $0[2] as! C.Output, $0[3] as! D.Output) } // swiftlint:disable:this force_cast
            ).start()
        }
    }
}

extension Publisher {

    /// Subscribes to an additional publisher and publishes a tuple upon receiving output
    /// from either publisher.
    public func combineLatest<P: Publisher>(_ other: P) -> Publishers.CombineLatest<Self, P>
        where Failure == P.Failure
    {
        return .init(self, other)
    }

    /// Subscribes to an additional publisher and invokes a closure upon receiving output
    /// from either publisher.
    public func combineLatest<P: Publisher, T>(
        _ other: P,
        _ transform: @escaping (Output, P.Output) -> T
    ) -> Publishers.Map<Publishers.CombineLatest<Self, P>, T>
        where Failure == P.Failure
    {
        return Publishers.CombineLatest(self, other).map(transform)
    }

    /// Subscribes to two additional publishers and publishes a tuple upon receiving
    /// output from any of the publishers.
    public func combineLatest<P: Publisher, Q: Publisher>(_ publisher1: P, _ publisher2: Q)
        -> Publishers.CombineLatest3<Self, P, Q>
        where Failure == P.Failure, P.Failure == Q.Failure
    {
        return .init(self, publisher1, publisher2)
    }

    /// Subscribes to two additional publishers and invokes a closure upon receiving
    /// output from any of the publishers.
    public func combineLatest<P: Publisher, Q: Publisher, T>(
        _ publisher1: P,
        _ publisher2: Q,
        _ transform: @escaping (Output, P.Output, Q.Output) -> T
    ) -> Publishers.Map<Publishers.CombineLatest3<Self, P, Q>, T>
        where Failure == P.Failure, P.Failure == Q.Failure
    {
        return Publishers.CombineLatest3(self, publisher1, publisher2).map(transform)
    }

    /// Subscribes to three additional publishers and publishes a tuple upon receiving
    /// output from any of the publishers.
    public func combineLatest<P: Publisher, Q: Publisher, R: Publisher>(
        _ publisher1: P,
        _ publisher2: Q,
        _ publisher3: R
    ) -> Publishers.CombineLatest4<Self, P, Q, R>
        where Failure == P.Failure, P.Failure == Q.Failure, Q.Failure == R.Failure
    {
        return .init(self, publisher1, publisher2, publisher3)
    }

    /// Subscribes to three additional publishers and invokes a closure upon receiving
    /// output from any of the publishers.
    public func combineLatest<P: Publisher, Q: Publisher, R: Publisher, T>(
        _ publisher1: P,
        _ publisher2: Q,
        _ publisher3: R,
        _ transform: @escaping (Output, P.Output, Q.Output, R.Output) -> T
    ) -> Publishers.Map<Publishers.CombineLatest4<Self, P, Q, R>, T>
        where Failure == P.Failure, P.Failure == Q.Failure, Q.Failure == R.Failure
    {
        return Publishers.CombineLatest4(self, publisher1, publisher2, publisher3)
            .map(transform)
    }
}

extension Publishers.CombineLatest: Equatable where A: Equatable, B: Equatable {
    public static func == (lhs: Publishers.CombineLatest<A, B>,
                           rhs: Publishers.CombineLatest<A, B>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b
    }
}

extension Publishers.CombineLatest3: Equatable
    where A: Equatable, B: Equatable, C: Equatable
{
    public static func == (lhs: Publishers.CombineLatest3<A, B, C>,
                           rhs: Publishers.CombineLatest3<A, B, C>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c
    }
}

extension Publishers.CombineLatest4: Equatable
    where A: Equatable, B: Equatable, C: Equatable, D: Equatable
{
    public static func == (lhs: Publishers.CombineLatest4<A, B, C, D>,
                           rhs: Publishers.CombineLatest4<A, B, C, D>) -> Bool {
        return lhs.a == rhs.a && lhs.b == rhs.b && lhs.c == rhs.c && lhs.d == rhs.d
    }
}

// MARK: - Implementation

extension Publisher {
    fileprivate func eraseOutput() -> AnyPublisher<Any, Failure> {
        return map { $0 as Any }.eraseToAnyPublisher()
    }
}

/// The subscription handed to the downstream of every CombineLatest publisher. One
/// `Side` per upstream forwards into it. Each upstream is asked for one value at a time
/// (all at once when downstream demand is unlimited); a side whose value could not be
/// delivered for lack of demand is paused until the downstream asks again.
private final class CombineLatestInner<Downstream: Subscriber>
    : Subscription,
      CustomStringConvertible,
      CustomReflectable,
      CustomPlaygroundDisplayConvertible
{
    typealias Output = Downstream.Input
    typealias Failure = Downstream.Failure

    private let lock = UnfairLock.allocate()
    private let downstreamLock = UnfairRecursiveLock.allocate()
    private var downstream: Downstream?
    private let upstreams: [AnyPublisher<Any, Failure>]
    private let combine: ([Any]) -> Output
    private var subscriptions: [Subscription?]
    private var unlimited: [Bool]
    private var latest: [Any?]
    private var valueCount = 0
    private var paused: Set<Int> = []
    private var pending = false
    private var demand = Subscribers.Demand.none
    private var active: Int
    private var terminated = false

    init(downstream: Downstream,
         upstreams: [AnyPublisher<Any, Failure>],
         combine: @escaping ([Any]) -> Output) {
        self.downstream = downstream
        self.upstreams = upstreams
        self.combine = combine
        subscriptions = Array(repeating: nil, count: upstreams.count)
        unlimited = Array(repeating: false, count: upstreams.count)
        latest = Array(repeating: nil, count: upstreams.count)
        active = upstreams.count
    }

    deinit {
        lock.deallocate()
        downstreamLock.deallocate()
    }

    func start() {
        guard let downstream = downstream else { return }
        downstreamLock.lock()
        downstream.receive(subscription: self)
        downstreamLock.unlock()
        for (index, upstream) in upstreams.enumerated() {
            upstream.subscribe(Side(parent: self, index: index))
        }
    }

    // MARK: Side events

    fileprivate func receive(subscription: Subscription, from side: Int) {
        lock.lock()
        guard !terminated, subscriptions[side] == nil else {
            lock.unlock()
            subscription.cancel()
            return
        }
        subscriptions[side] = subscription
        let wantsUnlimited = demand == .unlimited
        unlimited[side] = wantsUnlimited
        lock.unlock()
        subscription.request(wantsUnlimited ? .unlimited : .max(1))
    }

    fileprivate func receive(_ input: Any, from side: Int) -> Subscribers.Demand {
        lock.lock()
        guard !terminated, let downstream = downstream else {
            lock.unlock()
            return .none
        }
        if latest[side] == nil {
            valueCount += 1
        }
        latest[side] = input
        let more = unlimited[side] ? Subscribers.Demand.none : .max(1)
        guard valueCount == latest.count else {
            lock.unlock()
            return more
        }
        guard demand > 0 else {
            pending = true
            paused.insert(side)
            lock.unlock()
            return .none
        }
        demand -= 1
        pending = false
        let tuple = combine(latest.map { $0! })
        lock.unlock()
        downstreamLock.lock()
        let newDemand = downstream.receive(tuple)
        downstreamLock.unlock()
        lock.lock()
        demand += newDemand
        let toUnlimit = newDemand == .unlimited ? subscriptionsToUnlimit() : []
        lock.unlock()
        toUnlimit.forEach { $0.request(.unlimited) }
        return more
    }

    fileprivate func receive(completion: Subscribers.Completion<Failure>, from side: Int) {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return
        }
        subscriptions[side] = nil
        switch completion {
        case .failure:
            terminate(with: completion)
        case .finished:
            active -= 1
            if latest[side] == nil {
                // Nothing can ever be combined now: finish early, as Apple's does.
                terminate(with: .finished)
            } else {
                lock.unlock()
                finishIfDone()
            }
        }
    }

    // MARK: Subscription

    func request(_ demand: Subscribers.Demand) {
        demand.assertNonZero()
        lock.lock()
        guard !terminated, downstream != nil else {
            lock.unlock()
            return
        }
        self.demand += demand
        let toUnlimit = demand == .unlimited ? subscriptionsToUnlimit() : []
        lock.unlock()
        toUnlimit.forEach { $0.request(.unlimited) }
        deliverPending()
        finishIfDone()
    }

    func cancel() {
        lock.lock()
        terminated = true
        downstream = nil
        let subscriptions = self.subscriptions.compactMap { $0 }
        self.subscriptions = Array(repeating: nil, count: self.subscriptions.count)
        lock.unlock()
        subscriptions.forEach { $0.cancel() }
    }

    // MARK: Private

    /// Caller holds `lock`; this releases it.
    private func terminate(with completion: Subscribers.Completion<Failure>) {
        terminated = true
        let downstream = self.downstream.take()
        let others = subscriptions.compactMap { $0 }
        subscriptions = Array(repeating: nil, count: subscriptions.count)
        lock.unlock()
        others.forEach { $0.cancel() }
        downstreamLock.lock()
        downstream?.receive(completion: completion)
        downstreamLock.unlock()
    }

    /// Caller holds `lock`.
    private func subscriptionsToUnlimit() -> [Subscription] {
        var result: [Subscription] = []
        for index in subscriptions.indices where !unlimited[index] {
            unlimited[index] = true
            paused.remove(index)
            if let subscription = subscriptions[index] {
                result.append(subscription)
            }
        }
        return result
    }

    /// Emits the tuple held back for lack of demand, then resumes the paused sides.
    private func deliverPending() {
        lock.lock()
        guard !terminated, let downstream = downstream, pending, demand > 0 else {
            lock.unlock()
            return
        }
        pending = false
        demand -= 1
        let tuple = combine(latest.map { $0! })
        lock.unlock()
        downstreamLock.lock()
        let newDemand = downstream.receive(tuple)
        downstreamLock.unlock()
        lock.lock()
        demand += newDemand
        let toUnlimit = newDemand == .unlimited ? subscriptionsToUnlimit() : []
        let resume = paused.compactMap { subscriptions[$0] }
        paused.removeAll()
        lock.unlock()
        toUnlimit.forEach { $0.request(.unlimited) }
        resume.forEach { $0.request(.max(1)) }
    }

    private func finishIfDone() {
        lock.lock()
        guard !terminated, active == 0, !pending, let downstream = self.downstream.take()
        else {
            lock.unlock()
            return
        }
        terminated = true
        lock.unlock()
        downstreamLock.lock()
        downstream.receive(completion: .finished)
        downstreamLock.unlock()
    }

    var description: String { return "CombineLatest" }

    var customMirror: Mirror {
        lock.lock()
        defer { lock.unlock() }
        let children: [Mirror.Child] = [
            ("downstream", downstream as Any),
            ("demand", demand),
            ("latest", latest),
            ("active", active)
        ]
        return Mirror(self, children: children)
    }

    var playgroundDescription: Any { return description }

    /// The subscriber attached to one upstream.
    private final class Side: Subscriber {
        typealias Input = Any

        private let parent: CombineLatestInner
        private let index: Int
        let combineIdentifier = CombineIdentifier()

        init(parent: CombineLatestInner, index: Int) {
            self.parent = parent
            self.index = index
        }

        func receive(subscription: Subscription) {
            parent.receive(subscription: subscription, from: index)
        }

        func receive(_ input: Any) -> Subscribers.Demand {
            return parent.receive(input, from: index)
        }

        func receive(completion: Subscribers.Completion<Failure>) {
            parent.receive(completion: completion, from: index)
        }
    }
}
