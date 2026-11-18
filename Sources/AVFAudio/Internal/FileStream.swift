// Streaming a scheduled file segment from disk: a decode thread (one per process) reads
// the file in chunks, converts them to the player node's format (channel count, then
// sample rate) and fills a frame ring per scheduled segment; the render thread consumes
// the ring and never touches the file. In manual rendering mode (no real-time deadline)
// the render thread waits for the decoder instead of rendering silence.

import Foundation

final class _FileStream {
    let channels: Int
    /// Output frames (at the node's rate) the segment holds.
    private(set) var total: Int
    let ring: _FrameRing
    let finished = _AtomicBool(false)
    let cancelled = _AtomicBool(false)
    let filled = DispatchSemaphore(value: 0)
    private let reader: AVAudioFile
    private let startFrame: AVAudioFramePosition
    private let count: Int
    private var readPosition = 0
    private var produced = 0
    private let chunk = 8192
    private let readBuffer: AVAudioPCMBuffer
    private let planes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let mapped: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let fileChannels: Int
    private let matrix: _ChannelMatrix
    private let resampler: _Resampler?
    /// Render-thread scratch: the destination lanes at an offset.
    private let offsetPlanes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    /// Nil when the file cannot be reopened for reading.
    init?(file: AVAudioFile, startingFrame: AVAudioFramePosition, frameCount: Int, rate: Double, channels: AVAudioChannelCount) {
        guard let reader = try? AVAudioFile(forReading: file.url) else { return nil }
        let pf = reader.processingFormat
        guard let rb = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: AVAudioFrameCount(chunk)) else { return nil }
        self.reader = reader
        readBuffer = rb
        self.channels = Int(channels)
        fileChannels = Int(pf.channelCount)
        startFrame = startingFrame
        count = frameCount
        let ratio = pf.sampleRate / rate
        total = ratio == 1 ? frameCount : Int((Double(frameCount) / ratio).rounded(.down))
        resampler = ratio == 1 ? nil : _Resampler(channels: Int(channels), ratio: ratio, maxStretch: max(ratio, 1 / ratio), maxOutputFrames: chunk)
        matrix = fileChannels == 1 || fileChannels == Int(channels) ? .standard(inputs: fileChannels, outputs: Int(channels)) : (fileChannels > Int(channels) && channels == 1 ? .downmix(inputs: fileChannels, outputs: 1) : .standard(inputs: fileChannels, outputs: Int(channels)))
        ring = _FrameRing(channels: Int(channels), capacity: 65536)
        planes = .allocate(capacity: fileChannels)
        for c in 0..<fileChannels { planes[c] = .allocate(capacity: chunk) }
        let cap = Int(Double(chunk) * max(1, 1 / ratio)) + 64
        mapped = .allocate(capacity: Int(channels))
        for c in 0..<Int(channels) { mapped[c] = .allocate(capacity: max(chunk, cap)) }
        offsetPlanes = .allocate(capacity: Int(channels))
        offsetPlanes.initialize(repeating: mapped[0], count: Int(channels))
    }

    deinit {
        for c in 0..<fileChannels { planes[c].deallocate() }
        for c in 0..<channels { mapped[c].deallocate() }
        planes.deallocate(); mapped.deallocate(); offsetPlanes.deallocate()
    }

    /// Reads up to `frames` file frames into `mapped` (the node's channel layout).
    private func readFile(_ frames: Int) -> Int {
        let n = min(frames, chunk, count - readPosition)
        guard n > 0 else { return 0 }
        reader.framePosition = startFrame + AVAudioFramePosition(readPosition)
        guard (try? reader.read(into: readBuffer, frameCount: AVAudioFrameCount(n))) != nil else { return 0 }
        let got = Int(readBuffer.frameLength)
        for c in 0..<fileChannels { readBuffer._readFloats(channel: c, frame: 0, count: got, into: planes[c]) }
        matrix.apply(UnsafePointer(planes), into: UnsafePointer(mapped), frames: got)
        readPosition += got
        return got
    }

    /// Decode thread (or the scheduling thread before the stream is shared): decodes while
    /// the ring has room. Returns whether it made progress.
    @discardableResult
    func fill() -> Bool {
        guard !finished.value, !cancelled.value else { return false }
        var progressed = false
        while produced < total && !cancelled.value {
            if let resampler {
                let want = min(chunk, total - produced)
                guard ring.freeSpace >= want else { break }
                var need = resampler.inputFramesNeeded(for: want)
                while need > 0 {
                    let got = readPosition < count ? readFile(min(need, resampler.freeSpace)) : 0
                    if got > 0 { resampler.push(UnsafePointer(mapped), frames: got); need -= got }
                    else { resampler.pushSilence(frames: need); need = 0 }
                }
                resampler.produce(UnsafePointer(mapped), frames: want)
                ring.write(UnsafePointer(mapped), frames: want)
                produced += want
            } else {
                let want = min(chunk, total - produced)
                guard ring.freeSpace >= want else { break }
                let got = readFile(want)
                if got == 0 { total = produced; break }       // the file is shorter than its header said
                ring.write(UnsafePointer(mapped), frames: got)
                produced += got
            }
            progressed = true
        }
        if produced >= total { finished.value = true }
        filled.signal()
        return progressed
    }

    /// Render thread: up to `frames` frames into `out[c] + offset`. Offline (no deadline)
    /// it waits for the decoder; in real time it returns what is there.
    func read(into out: UnsafePointer<UnsafeMutablePointer<Float>>, offset: Int, frames: Int, offline: Bool) -> Int {
        if offline {
            var waits = 0
            while ring.count < frames && !finished.value && waits < 500 {
                _FileStreamer.shared.kick()
                _ = filled.wait(timeout: .now() + .milliseconds(10))
                waits += 1
            }
        }
        let n = min(frames, ring.count)
        if n > 0 {
            for c in 0..<channels { offsetPlanes[c] = out[c] + offset }
            _ = ring.read(into: UnsafePointer(offsetPlanes), frames: n)
        }
        if !finished.value && ring.count < ring.capacity / 2 { _FileStreamer.shared.kick() }
        return n
    }

    /// Nothing more will come: the decoder is done and the ring is empty.
    var isExhausted: Bool { finished.value && ring.count == 0 }
}

/// The decode thread every file stream shares.
final class _FileStreamer: @unchecked Sendable {
    static let shared = _FileStreamer()
    private let lock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var streams: [_FileStream] = []
    private var started = false

    func add(_ stream: _FileStream) {
        lock.lock()
        streams.append(stream)
        let start = !started
        started = true
        lock.unlock()
        if start {
            let t = Thread { [self] in run() }
            t.name = "AVFAudio file reader"
            t.qualityOfService = .userInitiated
            t.start()
        }
        kick()
    }

    /// Safe from the render thread: a semaphore signal never blocks.
    func kick() { wake.signal() }

    private func run() {
        while true {
            _ = wake.wait(timeout: .now() + .milliseconds(50))
            lock.lock()
            streams.removeAll { $0.cancelled.value || $0.finished.value }
            let snapshot = streams
            lock.unlock()
            for s in snapshot { s.fill() }
        }
    }
}
