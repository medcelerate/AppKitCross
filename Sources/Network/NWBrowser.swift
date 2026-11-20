import Foundation

/// An object you use to browse for available network services (Bonjour on `.local.`).
public final class NWBrowser: CustomDebugStringConvertible, @unchecked Sendable {
    /// What to browse for.
    public enum Descriptor: Sendable {
        /// Bonjour services of a type, such as `_http._tcp`; domain nil means `local.`.
        case bonjour(type: String, domain: String?)
        /// Like `bonjour`, with each result's TXT record in its metadata.
        case bonjourWithTXTRecord(type: String, domain: String?)
        /// Not implemented by this port; starting such a browser traps.
        case applicationService(name: String)
    }

    /// A discovered service.
    public struct Result: Hashable, Sendable {
        /// Extra information about a result.
        public enum Metadata: Equatable, CustomDebugStringConvertible, Sendable {
            case none
            case bonjour(_ record: NWTXTRecord)

            public var debugDescription: String {
                switch self {
                case .none: return "none"
                case .bonjour(let record): return record.debugDescription
                }
            }
        }

        /// A difference between two sets of results.
        public enum Change: Hashable, Sendable {
            /// Flags describing what changed between two results for the same endpoint.
            public struct Flags: OptionSet, Hashable, Sendable {
                public let rawValue: UInt8
                public init(rawValue: UInt8) { self.rawValue = rawValue }

                public static let identical = Flags(rawValue: 1 << 0)
                public static let interfaceAdded = Flags(rawValue: 1 << 1)
                public static let interfaceRemoved = Flags(rawValue: 1 << 2)
                public static let metadataChanged = Flags(rawValue: 1 << 3)
            }

            case identical
            case added(NWBrowser.Result)
            case removed(NWBrowser.Result)
            case changed(old: NWBrowser.Result, new: NWBrowser.Result, flags: NWBrowser.Result.Change.Flags)

            public init(between old: NWBrowser.Result?, _ new: NWBrowser.Result?) {
                switch (old, new) {
                case (nil, nil): self = .identical
                case (nil, let new?): self = .added(new)
                case (let old?, nil): self = .removed(old)
                case (let old?, let new?):
                    if old.metadata == new.metadata && old.interfaces == new.interfaces {
                        self = .identical
                    } else {
                        var flags: Flags = []
                        if old.metadata != new.metadata { flags.insert(.metadataChanged) }
                        if !Set(new.interfaces).subtracting(old.interfaces).isEmpty { flags.insert(.interfaceAdded) }
                        if !Set(old.interfaces).subtracting(new.interfaces).isEmpty { flags.insert(.interfaceRemoved) }
                        self = .changed(old: old, new: new, flags: flags)
                    }
                }
            }

            public static func == (lhs: Change, rhs: Change) -> Bool {
                switch (lhs, rhs) {
                case (.identical, .identical): return true
                case (.added(let a), .added(let b)), (.removed(let a), .removed(let b)): return a == b
                case (.changed(let a, let b, let f), .changed(let c, let d, let g)): return a == c && b == d && f == g
                default: return false
                }
            }

            public func hash(into hasher: inout Hasher) {
                switch self {
                case .identical: hasher.combine(0)
                case .added(let result): hasher.combine(1); hasher.combine(result)
                case .removed(let result): hasher.combine(2); hasher.combine(result)
                case .changed(let old, let new, let flags): hasher.combine(3); hasher.combine(old); hasher.combine(new); hasher.combine(flags)
                }
            }
        }

        public let endpoint: NWEndpoint
        /// The interfaces a result was seen on. This port does not track arrival
        /// interfaces, so the list is empty.
        public let interfaces: [NWInterface]
        public let metadata: NWBrowser.Result.Metadata

        init(endpoint: NWEndpoint, interfaces: [NWInterface] = [], metadata: Metadata) {
            self.endpoint = endpoint
            self.interfaces = interfaces
            self.metadata = metadata
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(endpoint)
        }

        public static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.endpoint == rhs.endpoint && lhs.metadata == rhs.metadata && lhs.interfaces == rhs.interfaces
        }
    }

    /// Browser states.
    public enum State: Equatable, Sendable {
        case setup
        case ready
        case failed(NWError)
        case cancelled
        case waiting(NWError)
    }

    public let descriptor: NWBrowser.Descriptor
    public let parameters: NWParameters

    private let lock = NSLock()
    private var _state: State = .setup
    private var _queue: DispatchQueue?
    private var _results: Set<Result> = []
    private var _stateUpdateHandler: (@Sendable (State) -> Void)?
    private var _browseResultsChangedHandler: (@Sendable (Set<Result>, Set<Result.Change>) -> Void)?
    private var browseID: Int?
    private var outbox: [() -> Void] = []

    public init(for descriptor: NWBrowser.Descriptor, using parameters: NWParameters) {
        self.descriptor = descriptor
        self.parameters = parameters
    }

    public var state: State { lock.locked { _state } }

    public var browseResults: Set<NWBrowser.Result> { lock.locked { _results } }

    public var queue: DispatchQueue? { lock.locked { _queue } }

    @preconcurrency public var stateUpdateHandler: (@Sendable (_ newState: NWBrowser.State) -> Void)? {
        get { lock.locked { _stateUpdateHandler } }
        set { lock.locked { _stateUpdateHandler = newValue } }
    }

    @preconcurrency public var browseResultsChangedHandler: (@Sendable (_ newResults: Set<NWBrowser.Result>, _ changes: Set<NWBrowser.Result.Change>) -> Void)? {
        get { lock.locked { _browseResultsChangedHandler } }
        set { lock.locked { _browseResultsChangedHandler = newValue } }
    }

    public var debugDescription: String { "[browser \(descriptor) \(state)]" }

    public func start(queue: DispatchQueue) {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        guard _queue == nil, case .setup = _state else { return }
        let type: String, domain: String?, includeTXT: Bool
        switch descriptor {
        case .bonjour(let t, let d): type = t; domain = d; includeTXT = false
        case .bonjourWithTXTRecord(let t, let d): type = t; domain = d; includeTXT = true
        case .applicationService: unimplemented("NWBrowser.Descriptor.applicationService")
        }
        _queue = queue
        browseID = MDNSEngine.shared.browse(type: type, domain: domain) { [self] result in
            lock.lock()
            defer { flushLocked(); lock.unlock() }
            switch result {
            case .failure(let error):
                transitionLocked(.failed(error))
            case .success(let instances):
                guard case .ready = _state else { return }
                let results = Set(instances.map { name, txt in
                    Result(endpoint: .service(name: name, type: type, domain: "local.", interface: nil),
                           metadata: includeTXT ? .bonjour(NWTXTRecord(txt)) : .none)
                })
                updateResultsLocked(results)
            }
        }
        transitionLocked(.ready)
    }

    public func cancel() {
        lock.lock()
        defer { flushLocked(); lock.unlock() }
        if case .cancelled = _state { return }
        if let browseID { MDNSEngine.shared.stopBrowse(browseID) }
        browseID = nil
        transitionLocked(.cancelled)
    }

    private func updateResultsLocked(_ results: Set<Result>) {
        let old = Dictionary(_results.map { ($0.endpoint, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(results.map { ($0.endpoint, $0) }, uniquingKeysWith: { a, _ in a })
        var changes: Set<Result.Change> = []
        for endpoint in Set(old.keys).union(new.keys) {
            let change = Result.Change(between: old[endpoint], new[endpoint])
            if change != .identical { changes.insert(change) }
        }
        guard !changes.isEmpty else { return }
        _results = results
        if let handler = _browseResultsChangedHandler { outbox.append { handler(results, changes) } }
    }

    private func transitionLocked(_ newState: State) {
        if case .cancelled = _state { return }
        if case .failed = _state, newState != .cancelled { return }
        guard _state != newState else { return }
        _state = newState
        if let handler = _stateUpdateHandler { outbox.append { handler(newState) } }
        if case .cancelled = newState {
            _stateUpdateHandler = nil
            _browseResultsChangedHandler = nil
        }
    }

    private func flushLocked() {
        guard !outbox.isEmpty, let queue = _queue else { return }
        let work = outbox
        outbox.removeAll()
        queue.async { for item in work { item() } }
    }
}
