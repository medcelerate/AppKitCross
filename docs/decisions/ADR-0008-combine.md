# ADR-0008: Combine from OpenCombine

Date: 2026-10-28. Status: accepted.

## Context

The SwiftUI stack this project is building toward sits on Combine: `ObservableObject`,
`@Published`, `objectWillChange`, `onReceive`, `Timer.publish`, `NotificationCenter`
publishers and the scheduler conformances of `RunLoop`, `DispatchQueue` and
`OperationQueue` are all Combine API, and application code written against AppKit uses
them freely. Apple ships Combine only on its own platforms; on Windows and Linux there is
no module of that name, so `import Combine` fails before any AppKit code is reached.

[OpenCombine](https://github.com/OpenCombine/OpenCombine) (MIT) is a mature, tested
reimplementation of Combine's public surface that already builds on Linux and Windows.
It is published as the modules `OpenCombine`, `OpenCombineFoundation` and
`OpenCombineDispatch`, with a few `OCombine` namespaces that exist only to coexist with
Apple's Combine when both are imported. Code written for Apple's Combine does not
compile against it unchanged.

## Decision

A `Combine` module in the package, declared only on Windows and Linux (the same
arrangement as `CoreGraphics` and `CoreText`, ADR-0007): on macOS the package and the
tests use Apple's Combine, so the tests are a specification the port has to meet.

The module is OpenCombine 0.14.0 with these changes:

- Module name `Combine`; `OpenCombine.X` qualifications become `Combine.X`.
- `OpenCombineFoundation` and `OpenCombineDispatch` are merged into the same module and
  their `OCombine` wrappers are flattened to Apple's shape: `NotificationCenter.Publisher`
  and `NotificationCenter.publisher(for:object:)`, `Timer.TimerPublisher` and
  `Timer.publish(every:tolerance:on:in:options:)`, `URLSession.DataTaskPublisher` and
  `dataTaskPublisher(for:)`, `RunLoop`/`OperationQueue`/`DispatchQueue` conforming to
  `Scheduler` directly with nested `SchedulerTimeType` and `SchedulerOptions`,
  `JSONEncoder`/`JSONDecoder`/`PropertyListEncoder`/`PropertyListDecoder` as
  `TopLevelEncoder`/`TopLevelDecoder`. The `ocombine` accessors are gone.
- The `COpenCombineHelpers` C++ target (locks over `os_unfair_lock`/pthread/`std::mutex`,
  an atomic identifier counter, `SIGTRAP`/`DebugBreak`) is replaced by Swift in
  `Helpers/Locking.swift` and `Helpers/PlatformHelpers.swift`: `NSLock`/`NSRecursiveLock`
  from corelibs Foundation (SRWLOCK on Windows, pthread on Linux), a lock-protected
  counter, and `raise(SIGTRAP)` / `DebugBreak()`. `assertOwner()` is a no-op, as it was
  on non-Darwin upstream. Keeping the C++ target would have meant a second C++ module in
  the package for three functions.
- The Darwin branches (`CFRunLoopTimer`, `canImport(Darwin)` selections, the WASI stubs)
  are dropped where they would be dead code here; `Foundation/Portability.swift` keeps
  only the corelibs path and names its timer wrapper `PortableTimer` so it cannot be
  mistaken for `Foundation.Timer` inside `extension Timer`.
- `RootProtocols`, `Publisher+Concurrency`, `Publishers.Catch/Encode/MapKeyPath` are the
  generated `.swift` files from upstream; the `.gyb` templates are not carried over.
- `Publishers.Merge`...`Merge8`, `Publishers.MergeMany` and `Publishers.CombineLatest`/
  `CombineLatest3`/`CombineLatest4` with their `Publisher.merge(with:)` and
  `combineLatest` overloads are written here (`Publishers/Publishers.Merge.swift`,
  `Publishers/Publishers.CombineLatest.swift`): upstream lists them in
  `RemainingCombineInterface.swift` and has not implemented them, and SwiftUI-style code
  uses both constantly. The declarations are Apple's; each arity type-erases its
  upstreams into one shared subscription that handles demand, buffering (merge) or the
  latest-value table (combineLatest), completion and cancellation.

OpenCombine's `LICENSE` is in `Sources/Combine/` with a `NOTICE` describing the origin
and the changes above. Upstream file headers are kept.

## What is included

Everything in OpenCombine 0.14.0's three library targets plus the merge and combineLatest
families: the root protocols,
`AnyPublisher`/`AnySubscriber`/`AnyCancellable`, `Just`/`Future`/`Deferred`/`Empty`/`Fail`/
`Record`, the subjects, `@Published` and `ObservableObject`, every `Publishers.*`
operator upstream implements (map/filter/flatMap/zip/switchToLatest/debounce/
throttle/delay/timeout/share/multicast/buffer/... ), `Subscribers.Sink`/`Assign`/`Demand`,
`ImmediateScheduler`, the `async` bridges (`Publisher.values`, `Future.value`), the
Foundation publishers and schedulers listed above, and `DispatchQueue: Scheduler`
(libdispatch is in the toolchain on both platforms, so it compiles cleanly with
corelibs). `URLSession.dataTaskPublisher` compiles against `FoundationNetworking` and is
included.

## What differs from Apple's Combine

- `Publishers.CollectByTime` and `collect(_ strategy: TimeGroupingStrategy, options:)`
  are the one piece of Apple's surface still missing: absent rather than stubbed, so
  using them is a compile error, not a runtime `unimplemented()`.
- `Publishers.Merge` and `CombineLatest` are this project's implementation, verified
  against Apple's behaviour only by the tests listed below (interleaving, buffering under
  limited demand, completion ordering, early completion of `combineLatest` when a side
  finishes without a value).
- `assertOwner()` never traps.
- `NotificationCenter.Publisher` filters by sender identity itself when the sender is
  not an `NSObject`: corelibs Foundation's `addObserver(forName:object:queue:using:)`
  only honours the object filter for `NSObject` senders (it compares with `isEqual`),
  and Apple's publisher matches any object by identity.
- Thread-safety semantics match upstream OpenCombine, which tracks Apple's observable
  behaviour closely but is not bit-for-bit.
- `Timer.publish` ignores `tolerance`, as Apple's does.

## Verification

`Tests/AppKitTests/CombineTests.swift` runs against Apple's Combine on macOS and against
this module in the Linux container (`APPKITWIN_HOST_BACKEND=1 swift test --filter
CombineTests`): subjects, `Future`, the operator chain, merge/combineLatest/zip,
debounce on `RunLoop.main`, delay and `receive(on:)` on a `DispatchQueue`, `decode` /
`encode` through `JSONDecoder`/`JSONEncoder`, sink/assign, `AnyCancellable`,
`@Published`/`objectWillChange` ordering, `NotificationCenter.publisher`,
`Timer.publish(...).autoconnect()` and the `RunLoop` scheduler.
