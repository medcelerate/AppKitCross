//
//  Publishers.CollectByTime.swift
//  Combine (AppKitCross addition; upstream OpenCombine 0.14.0 does not implement it)
//
//  Behaviour matches Apple's Combine as observed on macOS with a virtual-time scheduler
//  (see `testCollectByTime*` in Tests/AppKitTests/CombineTests.swift, which run against
//  both):
//  - a repeating timer starts on subscription, first firing one stride later;
//  - each firing publishes the buffer if it is non-empty and the downstream has demand,
//    otherwise the buffer is kept for a later firing;
//  - `.byTimeOrCount` also publishes, through the scheduler, as soon as `count` elements
//    are buffered, and asks upstream for `count` elements per element of downstream
//    demand; `.byTime` forwards demand unchanged and keeps upstream demand open;
//  - finishing publishes what is buffered (regardless of demand) and then finishes, both
//    through the scheduler; a failure drops the buffer and forwards the failure;
//  - cancellation and completion cancel the timer.
//

extension Publisher {

    /// Collects elements by a given time-grouping strategy, and emits a single array of
    /// the collection.
    ///
    /// Use `collect(_:options:)` to emit arrays of elements on a schedule specified by
    /// a `Scheduler` and `Stride` that you provide. At the end of each scheduled
    /// interval, the publisher sends an array that contains the items it collected.
    /// If the upstream publisher finishes before filling the buffer, the publisher sends
    /// an array that contains items it received. This may be fewer than the number of
    /// elements specified in the requested `Stride`.
    ///
    /// If the upstream publisher fails with an error, this publisher forwards the error
    /// to the downstream receiver instead of sending its output.
    ///
    /// The example above collects timestamps generated on a one-second `Timer` in groups
    /// (`Stride`) of five:
    ///
    ///     let sub = Timer.publish(every: 1, on: .main, in: .default)
    ///         .autoconnect()
    ///         .collect(.byTime(RunLoop.main, .seconds(5)))
    ///         .sink { print("\($0)", terminator: "\n\n") }
    ///
    /// > Note: When this publisher uses a `.byTimeOrCount` strategy and receives a
    /// request for `.max(n)` elements, it requests `.max(count * n)` from the upstream
    /// publisher.
    ///
    /// - Parameters:
    ///   - strategy: The timing group strategy used by the operator to collect and
    ///     publish elements.
    ///   - options: Scheduler options to use for the strategy.
    /// - Returns: A publisher that collects elements by a specified strategy, and emits
    ///   a single array of the collection.
    public func collect<Context: Scheduler>(
        _ strategy: Publishers.TimeGroupingStrategy<Context>,
        options: Context.SchedulerOptions? = nil
    ) -> Publishers.CollectByTime<Self, Context> {
        return .init(upstream: self, strategy: strategy, options: options)
    }
}

extension Publishers {

    /// A strategy for collecting received elements.
    public enum TimeGroupingStrategy<Context: Scheduler> {

        /// A grouping that collects and periodically publishes items.
        case byTime(Context, Context.SchedulerTimeType.Stride)

        /// A grouping that collects and publishes items periodically or when a buffer
        /// reaches a maximum size.
        case byTimeOrCount(Context, Context.SchedulerTimeType.Stride, Int)
    }

    /// A publisher that buffers and periodically publishes its items.
    public struct CollectByTime<Upstream: Publisher, Context: Scheduler>: Publisher {

        public typealias Output = [Upstream.Output]

        public typealias Failure = Upstream.Failure

        /// The publisher from which this publisher receives elements.
        public let upstream: Upstream

        /// The strategy with which to collect and publish elements.
        public let strategy: TimeGroupingStrategy<Context>

        /// Scheduler options to use for the strategy.
        public let options: Context.SchedulerOptions?

        public init(upstream: Upstream,
                    strategy: TimeGroupingStrategy<Context>,
                    options: Context.SchedulerOptions?) {
            self.upstream = upstream
            self.strategy = strategy
            self.options = options
        }

        public func receive<Downstream: Subscriber>(subscriber: Downstream)
            where Downstream.Failure == Failure, Downstream.Input == Output
        {
            upstream.subscribe(Inner(downstream: subscriber,
                                     strategy: strategy,
                                     options: options))
        }
    }
}

extension Publishers.CollectByTime {
    private final class Inner<Downstream: Subscriber>
        : Subscriber,
          Subscription,
          CustomStringConvertible,
          CustomReflectable,
          CustomPlaygroundDisplayConvertible
        where Downstream.Input == [Upstream.Output],
              Downstream.Failure == Upstream.Failure
    {
        typealias Input = Upstream.Output

        typealias Failure = Upstream.Failure

        private let lock = UnfairLock.allocate()

        private let downstreamLock = UnfairRecursiveLock.allocate()

        private let downstream: Downstream

        private let scheduler: Context

        private let stride: Context.SchedulerTimeType.Stride

        /// `nil` for `.byTime`.
        private let count: Int?

        private let options: Context.SchedulerOptions?

        // Guarded by `lock`.
        private var state = SubscriptionStatus.awaitingSubscription
        private var buffer: [Input] = []
        private var downstreamDemand = Subscribers.Demand.none
        private var timer: Cancellable?

        // Arrays and the completion waiting for delivery, oldest first. Each scheduled
        // block (and each timer firing) delivers the oldest one under `downstreamLock`,
        // so a concurrent scheduler cannot reorder them, as in `Publishers.Delay`.
        private enum Pending {
            case value([Input])
            case completion(Subscribers.Completion<Failure>)
        }
        private var pending: [Pending] = []   // guarded by `lock`

        init(downstream: Downstream,
             strategy: Publishers.TimeGroupingStrategy<Context>,
             options: Context.SchedulerOptions?) {
            self.downstream = downstream
            switch strategy {
            case let .byTime(scheduler, stride):
                self.scheduler = scheduler
                self.stride = stride
                self.count = nil
            case let .byTimeOrCount(scheduler, stride, count):
                self.scheduler = scheduler
                self.stride = stride
                self.count = Swift.max(count, 1)
            }
            self.options = options
        }

        deinit {
            lock.deallocate()
            downstreamLock.deallocate()
        }

        // MARK: Subscriber

        func receive(subscription: Subscription) {
            lock.lock()
            guard case .awaitingSubscription = state else {
                lock.unlock()
                subscription.cancel()
                return
            }
            state = .subscribed(subscription)
            lock.unlock()
            let timer = scheduler.schedule(after: scheduler.now.advanced(by: stride),
                                           interval: stride,
                                           tolerance: scheduler.minimumTolerance,
                                           options: options) {
                self.timerFired()
            }
            lock.lock()
            if case .subscribed = state {
                self.timer = timer
                lock.unlock()
            } else {
                lock.unlock()
                timer.cancel()
            }
            downstreamLock.lock()
            downstream.receive(subscription: self)
            downstreamLock.unlock()
        }

        func receive(_ input: Input) -> Subscribers.Demand {
            lock.lock()
            guard case .subscribed = state else {
                lock.unlock()
                return .none
            }
            buffer.append(input)
            guard let count = count else {
                lock.unlock()
                // `.byTime` keeps upstream demand open; the buffer absorbs it.
                return .max(1)
            }
            var scheduled = 0
            while buffer.count >= count && downstreamDemand > 0 {
                downstreamDemand -= 1
                pending.append(.value(Array(buffer.prefix(count))))
                buffer.removeFirst(count)
                scheduled += 1
            }
            lock.unlock()
            for _ in 0..<scheduled {
                scheduler.schedule(options: options) {
                    self.deliverNext()
                }
            }
            return .none
        }

        func receive(completion: Subscribers.Completion<Failure>) {
            lock.lock()
            guard case let .subscribed(subscription) = state else {
                lock.unlock()
                return
            }
            state = .pendingTerminal(subscription)
            let timer = self.timer.take()
            var deliveries = 1
            switch completion {
            case .finished where !buffer.isEmpty:
                pending.append(.value(buffer.take()))
                deliveries += 1
            case .finished, .failure:
                buffer = []
            }
            pending.append(.completion(completion))
            lock.unlock()
            timer?.cancel()
            for _ in 0..<deliveries {
                scheduler.schedule(options: options) {
                    self.deliverNext()
                }
            }
        }

        // MARK: Subscription

        func request(_ demand: Subscribers.Demand) {
            demand.assertNonZero()
            lock.lock()
            guard case let .subscribed(subscription) = state else {
                lock.unlock()
                return
            }
            downstreamDemand += demand
            lock.unlock()
            subscription.request(count.map { demand * $0 } ?? demand)
        }

        func cancel() {
            lock.lock()
            guard let subscription = state.subscription else {
                lock.unlock()
                return
            }
            state = .terminal
            let timer = self.timer.take()
            buffer = []
            pending = []
            lock.unlock()
            timer?.cancel()
            subscription.cancel()
        }

        // MARK: Delivery

        private func timerFired() {
            downstreamLock.lock()
            defer { downstreamLock.unlock() }
            lock.lock()
            guard case .subscribed = state,
                  !buffer.isEmpty,
                  downstreamDemand > 0 else {
                lock.unlock()
                return
            }
            downstreamDemand -= 1
            if let count = count, buffer.count > count {
                pending.append(.value(Array(buffer.prefix(count))))
                buffer.removeFirst(count)
            } else {
                pending.append(.value(buffer.take()))
            }
            lock.unlock()
            deliverNext()
        }

        private func deliverNext() {
            downstreamLock.lock()
            defer { downstreamLock.unlock() }
            lock.lock()
            guard !pending.isEmpty else {
                lock.unlock()
                return
            }
            switch pending.removeFirst() {
            case .value(let output):
                guard state.subscription != nil else {
                    lock.unlock()
                    return
                }
                lock.unlock()
                let newDemand = downstream.receive(output)
                guard newDemand > 0 else { return }
                lock.lock()
                guard case let .subscribed(subscription) = state else {
                    lock.unlock()
                    return
                }
                downstreamDemand += newDemand
                lock.unlock()
                subscription.request(count.map { newDemand * $0 } ?? newDemand)
            case .completion(let completion):
                guard case .pendingTerminal = state else {
                    lock.unlock()
                    return
                }
                state = .terminal
                lock.unlock()
                downstream.receive(completion: completion)
            }
        }

        var description: String { return "CollectByTime" }

        var customMirror: Mirror {
            lock.lock()
            defer { lock.unlock() }
            let children: [Mirror.Child] = [
                ("downstream", downstream),
                ("buffer", buffer),
                ("downstreamDemand", downstreamDemand)
            ]
            return Mirror(self, children: children)
        }

        var playgroundDescription: Any { return description }
    }
}
