// Lock-free primitives for the real-time path: atomic scalars over CAudioAtomics (inline
// clang builtins; the Synchronization module needs macOS 15) and single-producer /
// single-consumer rings of trivial elements. Nothing here allocates or blocks after
// construction, so the render thread can use it freely.

import Foundation
@_implementationOnly import CAudioAtomics

/// A heap cell the C atomics operate on (Swift has no atomic stored properties here).
final class _AtomicInt64 {
    private let p: UnsafeMutablePointer<Int64>
    init(_ value: Int64 = 0) { p = .allocate(capacity: 1); p.initialize(to: value) }
    deinit { p.deallocate() }
    var value: Int64 {
        get { caa_load_i64(p) }
        set { caa_store_i64(p, newValue) }
    }
    @discardableResult func add(_ delta: Int64) -> Int64 { caa_add_i64(p, delta) }
    func compareExchange(expected: Int64, desired: Int64) -> Bool { caa_cas_i64(p, expected, desired) }
}

final class _AtomicInt32 {
    private let p: UnsafeMutablePointer<Int32>
    init(_ value: Int32 = 0) { p = .allocate(capacity: 1); p.initialize(to: value) }
    deinit { p.deallocate() }
    var value: Int32 {
        get { caa_load_i32(p) }
        set { caa_store_i32(p, newValue) }
    }
    func exchange(_ value: Int32) -> Int32 { caa_exchange_i32(p, value) }
}

final class _AtomicBool {
    private let p: UnsafeMutablePointer<Int32>
    init(_ value: Bool = false) { p = .allocate(capacity: 1); p.initialize(to: value ? 1 : 0) }
    deinit { p.deallocate() }
    var value: Bool {
        get { caa_load_i32(p) != 0 }
        set { caa_store_i32(p, newValue ? 1 : 0) }
    }
}

final class _AtomicFloat {
    private let p: UnsafeMutablePointer<Int32>
    init(_ value: Float = 0) { p = .allocate(capacity: 1); p.initialize(to: 0); caa_store_f32(p, value) }
    deinit { p.deallocate() }
    var value: Float {
        get { caa_load_f32(p) }
        set { caa_store_f32(p, newValue) }
    }
}

final class _AtomicDouble {
    private let p: UnsafeMutablePointer<Int64>
    init(_ value: Double = 0) { p = .allocate(capacity: 1); p.initialize(to: 0); caa_store_f64(p, value) }
    deinit { p.deallocate() }
    var value: Double {
        get { caa_load_f64(p) }
        set { caa_store_f64(p, newValue) }
    }
}

/// A single-producer, single-consumer ring. `Element` must be trivial (no references the
/// compiler would retain): the queues carry `Unmanaged` references and plain scalars.
final class _SPSCRing<Element> {
    private let storage: UnsafeMutablePointer<Element>
    private let capacity: Int
    private let head = _AtomicInt64(0)   // consumer index
    private let tail = _AtomicInt64(0)   // producer index

    init(capacity: Int) {
        var c = 1
        while c < capacity { c <<= 1 }
        self.capacity = c
        storage = .allocate(capacity: c)
    }

    deinit { storage.deallocate() }

    /// Producer side. False when full.
    func push(_ element: Element) -> Bool {
        let t = tail.value, h = head.value
        if t - h >= Int64(capacity) { return false }
        storage[Int(t & Int64(capacity - 1))] = element
        tail.value = t + 1
        return true
    }

    /// Consumer side.
    func pop() -> Element? {
        let h = head.value, t = tail.value
        if h == t { return nil }
        let e = storage[Int(h & Int64(capacity - 1))]
        head.value = h + 1
        return e
    }

    /// Consumer side: the next element without removing it.
    func peek() -> Element? {
        let h = head.value, t = tail.value
        if h == t { return nil }
        return storage[Int(h & Int64(capacity - 1))]
    }

    var isEmpty: Bool { head.value == tail.value }
    var count: Int { Int(tail.value - head.value) }
    var freeSpace: Int { capacity - count }
}

/// A single-producer, single-consumer ring of Float32 frames (planar: one lane per channel),
/// for taps. The producer is the render thread; the consumer the delivery thread.
final class _FrameRing {
    let channels: Int
    let capacity: Int           // frames, power of two
    private let lanes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let head = _AtomicInt64(0)
    private let tail = _AtomicInt64(0)

    init(channels: Int, capacity: Int) {
        var c = 1
        while c < capacity { c <<= 1 }
        self.channels = channels
        self.capacity = c
        lanes = .allocate(capacity: channels)
        for ch in 0..<channels {
            lanes[ch] = .allocate(capacity: c)
            lanes[ch].initialize(repeating: 0, count: c)
        }
    }

    deinit {
        for ch in 0..<channels { lanes[ch].deallocate() }
        lanes.deallocate()
    }

    var count: Int { Int(tail.value - head.value) }
    var freeSpace: Int { capacity - count }

    /// Producer: appends `frames` frames from `planes`; drops them when there is no room.
    @discardableResult func write(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) -> Bool {
        let t = tail.value, h = head.value
        if Int(t - h) + frames > capacity { return false }
        let mask = capacity - 1
        for ch in 0..<channels {
            let lane = lanes[ch], src = planes[ch]
            let i = Int(t & Int64(mask))
            let first = min(frames, capacity - i)
            (lane + i).update(from: src, count: first)
            if first < frames { lane.update(from: src + first, count: frames - first) }
        }
        tail.value = t + Int64(frames)
        return true
    }

    /// Consumer: removes `frames` frames into `planes` (false when fewer are available).
    func read(into planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) -> Bool {
        let h = head.value, t = tail.value
        if Int(t - h) < frames { return false }
        let mask = capacity - 1
        for ch in 0..<channels {
            let lane = lanes[ch], dst = planes[ch]
            let i = Int(h & Int64(mask))
            let first = min(frames, capacity - i)
            dst.update(from: lane + i, count: first)
            if first < frames { (dst + first).update(from: lane, count: frames - first) }
        }
        head.value = h + Int64(frames)
        return true
    }
}
