// The delivery thread: the one consumer of every completion and tap ring. The render
// thread only pushes events and signals the semaphore; this thread calls the handlers.

import Foundation

protocol _Deliverable: AnyObject {
    /// Drains whatever the render thread left; called on the delivery thread.
    func _deliver()
}

final class _DeliveryHub {
    static let shared = _DeliveryHub()
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var members: [ObjectIdentifier: _Deliverable] = [:]
    private var started = false

    func register(_ member: _Deliverable) {
        lock.lock()
        members[ObjectIdentifier(member)] = member
        let start = !started
        started = true
        lock.unlock()
        if start {
            let thread = Thread { [self] in self.run() }
            thread.name = "AVFAudio delivery"
            thread.qualityOfService = .userInteractive
            thread.start()
        }
    }

    func unregister(_ member: _Deliverable) {
        lock.lock(); members[ObjectIdentifier(member)] = nil; lock.unlock()
    }

    /// Safe from the render thread: a semaphore signal never blocks.
    func signal() { semaphore.signal() }

    private func run() {
        while true {
            semaphore.wait()
            lock.lock()
            let snapshot = Array(members.values)
            lock.unlock()
            for m in snapshot { m._deliver() }
        }
    }
}

/// A tap on a node's output bus: the render thread writes planar frames and a chunk
/// descriptor per cycle; the delivery thread assembles buffers of `bufferSize` frames.
final class _TapState: _Deliverable {
    struct Chunk { var sampleTime: Int64; var hostTime: Int64; var frames: Int32 }
    weak var node: AVAudioNode?
    let bus: AVAudioNodeBus
    let bufferSize: Int
    let format: AVAudioFormat
    let block: AVAudioNodeTapBlock
    let ring: _FrameRing
    let chunks = _SPSCRing<Chunk>(capacity: 256)
    private let detached = _AtomicBool(false)
    private var pendingSampleTime: Int64 = -1
    private var pendingHostTime: Int64 = 0
    private var pendingFrames = 0
    private let planes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private var available = 0        // frames of the current batch already read from the ring

    init(node: AVAudioNode, bus: AVAudioNodeBus, bufferSize: Int, format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock) {
        self.node = node; self.bus = bus; self.bufferSize = bufferSize; self.format = format; self.block = block
        let channels = Int(format.channelCount)
        ring = _FrameRing(channels: channels, capacity: bufferSize * 8)
        planes = .allocate(capacity: channels)
        for c in 0..<channels { planes[c] = .allocate(capacity: bufferSize) }
        _DeliveryHub.shared.register(self)
    }

    deinit {
        for c in 0..<Int(format.channelCount) { planes[c].deallocate() }
        planes.deallocate()
    }

    func detach() {
        detached.value = true
        _DeliveryHub.shared.unregister(self)
    }

    /// Render thread.
    func push(_ src: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int, sampleTime: Int64, hostTime: Int64) {
        guard frames > 0, !detached.value else { return }
        if ring.write(src, frames: frames) {
            _ = chunks.push(Chunk(sampleTime: sampleTime, hostTime: hostTime, frames: Int32(frames)))
        }
    }

    func _deliver() {
        while !detached.value {
            // Pull chunk descriptors until a whole buffer is available.
            while pendingFrames < bufferSize, let c = chunks.pop() {
                if pendingFrames == 0 { pendingSampleTime = c.sampleTime; pendingHostTime = c.hostTime }
                pendingFrames += Int(c.frames)
            }
            guard pendingFrames >= bufferSize else { return }
            guard ring.read(into: UnsafePointer(planes), frames: bufferSize) else { return }
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(bufferSize))!
            for c in 0..<Int(format.channelCount) { buffer._writeFloats(channel: c, frame: 0, count: bufferSize, from: planes[c]) }
            buffer.frameLength = AVAudioFrameCount(bufferSize)
            let time = AVAudioTime(hostTime: UInt64(pendingHostTime), sampleTime: pendingSampleTime, atRate: format.sampleRate)
            pendingFrames -= bufferSize
            pendingSampleTime += Int64(bufferSize)
            pendingHostTime += Int64(Double(bufferSize) / format.sampleRate * 1_000_000_000)
            block(buffer, time)
        }
    }
}
