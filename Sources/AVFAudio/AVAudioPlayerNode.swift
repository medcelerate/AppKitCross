// AVAudioPlayerNode: schedules buffers and file segments for playback. The control side
// hands items to the render side through a lock-free command ring; completions come back
// through another ring and are delivered off the audio thread.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioplayernodebufferoptions
public struct AVAudioPlayerNodeBufferOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let loops = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 0)
    public static let interrupts = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 1)
    public static let interruptsAtLoop = AVAudioPlayerNodeBufferOptions(rawValue: 1 << 2)
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioplayernodecompletioncallbacktype
public enum AVAudioPlayerNodeCompletionCallbackType: Int, Sendable {
    case dataConsumed = 0
    case dataRendered = 1
    case dataPlayedBack = 2
}

public typealias AVAudioPlayerNodeCompletionHandler = (AVAudioPlayerNodeCompletionCallbackType) -> Void

/// One scheduled buffer or file segment. The render thread owns `position`.
final class _ScheduledItem {
    let buffer: AVAudioPCMBuffer
    let frameCount: Int
    let options: AVAudioPlayerNodeBufferOptions
    let callbackType: AVAudioPlayerNodeCompletionCallbackType
    let completion: AVAudioPlayerNodeCompletionHandler?
    /// Player-time sample at which to start, or -1 for "next".
    let startSampleTime: Int64
    let channelData: UnsafePointer<UnsafeMutablePointer<Float>>
    let stride: Int
    var position = 0

    init(buffer: AVAudioPCMBuffer, options: AVAudioPlayerNodeBufferOptions, callbackType: AVAudioPlayerNodeCompletionCallbackType, completion: AVAudioPlayerNodeCompletionHandler?, startSampleTime: Int64) {
        self.buffer = buffer
        frameCount = Int(buffer.frameLength)
        self.options = options; self.callbackType = callbackType; self.completion = completion; self.startSampleTime = startSampleTime
        channelData = buffer.floatChannelData!
        stride = buffer.stride
    }
}

struct _PlayerCommand {
    enum Kind: Int32 { case schedule, play, pause, stop }
    var kind: Kind
    var item: Unmanaged<_ScheduledItem>?
    var nodeSampleTime: Int64       // play(at:): -1 for now
}

struct _CompletionEvent {
    var item: Unmanaged<_ScheduledItem>
    var dueSampleTime: Int64        // node sample time at which to fire (dataPlayedBack)
    var fires = true                // false: release the item without calling its handler
}

/// The render-side state of a player node. Only one thread touches the render-side
/// fields at a time: the audio thread while the engine renders live, otherwise the
/// control thread that submitted the command (see `AVAudioPlayerNode._submit`).
final class _PlayerRenderState {
    let commands = _SPSCRing<_PlayerCommand>(capacity: 1024)
    let completions = _SPSCRing<_CompletionEvent>(capacity: 1024)
    private let queueCapacity = 1024
    private let queue: UnsafeMutablePointer<Unmanaged<_ScheduledItem>?>
    private var qHead = 0, qCount = 0
    private let deferredCapacity = 256
    private let deferred: UnsafeMutablePointer<_CompletionEvent>
    private var deferredCount = 0
    var playing = false
    var playerSampleTime: Int64 = 0
    var playStartNodeTime: Int64 = -1
    let timeOffset = _AtomicInt64(0)
    let timeValid = _AtomicBool(false)
    private var interruptAtLoop: Unmanaged<_ScheduledItem>?

    init() {
        queue = .allocate(capacity: queueCapacity); queue.initialize(repeating: nil, count: queueCapacity)
        deferred = .allocate(capacity: deferredCapacity)
    }

    deinit {
        for i in 0..<qCount { queue[(qHead + i) % queueCapacity]?.release() }
        for i in 0..<deferredCount { deferred[i].item.release() }
        while let c = commands.pop() { c.item?.release() }
        while let e = completions.pop() { e.item.release() }
        queue.deallocate(); deferred.deallocate()
    }

    private func enqueue(_ item: Unmanaged<_ScheduledItem>, front: Bool) {
        guard qCount < queueCapacity else { finish(item, now: true); return }
        if front {
            qHead = (qHead + queueCapacity - 1) % queueCapacity
            queue[qHead] = item
        } else {
            queue[(qHead + qCount) % queueCapacity] = item
        }
        qCount += 1
    }

    private func dequeue() -> Unmanaged<_ScheduledItem>? {
        guard qCount > 0 else { return nil }
        let item = queue[qHead]
        queue[qHead] = nil
        qHead = (qHead + 1) % queueCapacity
        qCount -= 1
        return item
    }

    private var current: Unmanaged<_ScheduledItem>? { qCount > 0 ? queue[qHead] : nil }

    /// Moves an item to the completion ring (or the deferred list for dataPlayedBack).
    /// `dueSampleTime` < 0 means the playback clock never passes it (manual rendering
    /// mode): the handler is not called, as Apple's engine does not call it there.
    private func finish(_ item: Unmanaged<_ScheduledItem>, now: Bool, dueSampleTime: Int64 = 0) {
        if !now {
            if dueSampleTime < 0 {
                if !completions.push(_CompletionEvent(item: item, dueSampleTime: 0, fires: false)) { item.release() }
                return
            }
            if deferredCount < deferredCapacity {
                deferred[deferredCount] = _CompletionEvent(item: item, dueSampleTime: dueSampleTime)
                deferredCount += 1
                return
            }
        }
        if !completions.push(_CompletionEvent(item: item, dueSampleTime: 0)) { item.release() }
    }

    private func clearQueue() {
        while let item = dequeue() { finish(item, now: true) }
        if let i = interruptAtLoop { finish(i, now: true); interruptAtLoop = nil }
    }

    /// Applies every pending command. `nodeSampleTime` is the time of the next frame.
    func processCommands(nodeSampleTime: Int64) {
        while let c = commands.pop() {
            switch c.kind {
            case .schedule:
                guard let item = c.item else { break }
                let options = item.takeUnretainedValue().options
                if options.contains(.interrupts) {
                    if let cur = dequeue() { finish(cur, now: true) }
                    enqueue(item, front: true)
                } else if options.contains(.interruptsAtLoop), let cur = current, cur.takeUnretainedValue().options.contains(.loops) {
                    if let old = interruptAtLoop { finish(old, now: true) }
                    interruptAtLoop = item
                } else {
                    enqueue(item, front: false)
                }
            case .play:
                if !playing {
                    playing = true
                    playStartNodeTime = c.nodeSampleTime
                }
            case .pause:
                playing = false
                timeValid.value = false
            case .stop:
                playing = false
                timeValid.value = false
                playerSampleTime = 0
                playStartNodeTime = -1
                clearQueue()
                flushDeferred(nodeSampleTime: Int64.max)
            }
        }
    }

    /// Fires deferred (dataPlayedBack) completions whose time has come.
    func flushDeferred(nodeSampleTime: Int64) {
        var i = 0
        while i < deferredCount {
            if deferred[i].dueSampleTime <= nodeSampleTime {
                if !completions.push(deferred[i]) { deferred[i].item.release() }
                deferred[i] = deferred[deferredCount - 1]
                deferredCount -= 1
            } else {
                i += 1
            }
        }
    }

    /// Renders `frames` frames into `out` (planar, `channels` lanes). Returns false when the
    /// output is silence.
    func render(into out: UnsafePointer<UnsafeMutablePointer<Float>>, channels: Int, frames: Int, nodeSampleTime: Int64, latencyFrames: Int64) -> Bool {
        processCommands(nodeSampleTime: nodeSampleTime)
        flushDeferred(nodeSampleTime: nodeSampleTime)
        guard playing else {
            for c in 0..<channels { out[c].update(repeating: 0, count: frames) }
            return false
        }
        var written = 0
        if playStartNodeTime > nodeSampleTime {
            let delay = Int(min(Int64(frames), playStartNodeTime - nodeSampleTime))
            for c in 0..<channels { out[c].update(repeating: 0, count: delay) }
            written = delay
        }
        timeOffset.value = nodeSampleTime + Int64(written) - playerSampleTime
        timeValid.value = true
        var produced = false
        while written < frames {
            guard let itemRef = current else { break }
            let item = itemRef.takeUnretainedValue()
            let remaining = frames - written
            if item.startSampleTime > playerSampleTime {
                // Silence until the item's start time.
                let gap = Int(min(Int64(remaining), item.startSampleTime - playerSampleTime))
                for c in 0..<channels { (out[c] + written).update(repeating: 0, count: gap) }
                written += gap
                playerSampleTime += Int64(gap)
                continue
            }
            let n = min(remaining, item.frameCount - item.position)
            if n > 0 {
                let st = item.stride
                for c in 0..<min(channels, Int(item.buffer.format.channelCount)) {
                    let src = item.channelData[c]
                    let dst = out[c] + written
                    if st == 1 { dst.update(from: src + item.position, count: n) }
                    else { for i in 0..<n { dst[i] = src[(item.position + i) * st] } }
                }
                for c in Int(item.buffer.format.channelCount)..<channels where c >= 0 { (out[c] + written).update(repeating: 0, count: n) }
                item.position += n
                written += n
                playerSampleTime += Int64(n)
                produced = true
            }
            if item.position >= item.frameCount {
                if item.options.contains(.loops), interruptAtLoop == nil {
                    item.position = 0
                    if item.frameCount == 0 { _ = dequeue(); finish(itemRef, now: true) }
                } else {
                    _ = dequeue()
                    let due = latencyFrames < 0 ? -1 : nodeSampleTime + Int64(written) + latencyFrames
                    finish(itemRef, now: item.callbackType != .dataPlayedBack, dueSampleTime: due)
                    if let next = interruptAtLoop { enqueue(next, front: true); interruptAtLoop = nil }
                }
            }
        }
        if written < frames {
            for c in 0..<channels { (out[c] + written).update(repeating: 0, count: frames - written) }
            playerSampleTime += Int64(frames - written)
        }
        // dataPlayedBack completions fire at the start of a later cycle, once the node
        // time has passed the item's end plus the output latency (as Apple's do: in manual
        // rendering mode that is the next render call).
        return produced
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioplayernode
open class AVAudioPlayerNode: AVAudioNode, AVAudioMixing, _Deliverable {
    let _state = _PlayerRenderState()
    let _mixingSource = _MixingSource()
    private let _isPlaying = _AtomicBool(false)
    private let producerLock = NSLock()
    private var overflow: [_PlayerCommand] = []

    public override init() {
        super.init()
        _DeliveryHub.shared.register(self)
    }

    deinit { _DeliveryHub.shared.unregister(self) }

    open override var numberOfInputs: Int { 0 }
    override var _isSource: Bool { true }

    /// Before connection a player node reports 44.1 kHz stereo, as Apple's does.
    override func _defaultOutputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    }

    // MARK: Scheduling

    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionHandler: AVAudioNodeCompletionHandler? = nil) {
        scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataConsumed, completionHandler: completionHandler.map { h in { _ in h() } })
    }

    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType, completionHandler: AVAudioPlayerNodeCompletionHandler? = nil) {
        scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: callbackType, completionHandler: completionHandler)
    }

    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [], completionHandler: AVAudioNodeCompletionHandler? = nil) {
        scheduleBuffer(buffer, at: when, options: options, completionCallbackType: .dataConsumed, completionHandler: completionHandler.map { h in { _ in h() } })
    }

    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [], completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType, completionHandler: AVAudioPlayerNodeCompletionHandler? = nil) {
        let format = outputFormat(forBus: 0)
        precondition(buffer.format.commonFormat == .pcmFormatFloat32, "AVAudioPlayerNode.scheduleBuffer: buffers must be Float32 (got \(buffer.format))")
        precondition(format.channelCount == 0 || buffer.format.channelCount == format.channelCount,
                     "AVAudioPlayerNode.scheduleBuffer: required condition is false: _outputFormat.channelCount == buffer.format.channelCount")
        let item = _ScheduledItem(buffer: buffer, options: options, callbackType: callbackType, completion: completionHandler, startSampleTime: _startSampleTime(when))
        _submit(_PlayerCommand(kind: .schedule, item: Unmanaged.passRetained(item), nodeSampleTime: -1))
    }

    open func scheduleFile(_ file: AVAudioFile, at when: AVAudioTime?, completionHandler: AVAudioNodeCompletionHandler? = nil) {
        scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(clamping: file.length), at: when, completionCallbackType: .dataConsumed, completionHandler: completionHandler.map { h in { _ in h() } })
    }

    open func scheduleFile(_ file: AVAudioFile, at when: AVAudioTime?, completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType, completionHandler: AVAudioPlayerNodeCompletionHandler? = nil) {
        scheduleSegment(file, startingFrame: 0, frameCount: AVAudioFrameCount(clamping: file.length), at: when, completionCallbackType: callbackType, completionHandler: completionHandler)
    }

    open func scheduleSegment(_ file: AVAudioFile, startingFrame startFrame: AVAudioFramePosition, frameCount numberFrames: AVAudioFrameCount, at when: AVAudioTime?, completionHandler: AVAudioNodeCompletionHandler? = nil) {
        scheduleSegment(file, startingFrame: startFrame, frameCount: numberFrames, at: when, completionCallbackType: .dataConsumed, completionHandler: completionHandler.map { h in { _ in h() } })
    }

    /// Reads the segment now (on the calling thread), converts it to the node's output
    /// sample rate and channel count, and schedules the result.
    open func scheduleSegment(_ file: AVAudioFile, startingFrame startFrame: AVAudioFramePosition, frameCount numberFrames: AVAudioFrameCount, at when: AVAudioTime?, completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType, completionHandler: AVAudioPlayerNodeCompletionHandler? = nil) {
        let format = outputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : file.processingFormat.sampleRate
        let channels = format.channelCount > 0 ? format.channelCount : file.processingFormat.channelCount
        let buffer = _readSegment(file, startingFrame: startFrame, frameCount: numberFrames, rate: rate, channels: channels)
        let item = _ScheduledItem(buffer: buffer, options: [], callbackType: callbackType, completion: completionHandler, startSampleTime: _startSampleTime(when))
        _submit(_PlayerCommand(kind: .schedule, item: Unmanaged.passRetained(item), nodeSampleTime: -1))
    }

    private func _readSegment(_ file: AVAudioFile, startingFrame: AVAudioFramePosition, frameCount: AVAudioFrameCount, rate: Double, channels: AVAudioChannelCount) -> AVAudioPCMBuffer {
        let pf = file.processingFormat
        let start = max(0, min(startingFrame, file.length))
        let count = Int(min(AVAudioFramePosition(frameCount), file.length - start))
        let empty = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!, frameCapacity: 1)!
        guard count > 0, let raw = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: AVAudioFrameCount(count)) else { return empty }
        file.framePosition = start
        guard (try? file.read(into: raw, frameCount: AVAudioFrameCount(count))) != nil, raw.frameLength > 0 else { return empty }
        // Channel count first (mono <-> stereo), then the rate.
        var source = raw
        if pf.channelCount != channels {
            let mapped = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: pf.sampleRate, channels: channels)!, frameCapacity: raw.frameLength)!
            mapped.frameLength = raw.frameLength
            let n = Int(raw.frameLength)
            let tmp = UnsafeMutablePointer<Float>.allocate(capacity: n); defer { tmp.deallocate() }
            let inCh = Int(pf.channelCount), outCh = Int(channels)
            if inCh == 1 {
                raw._readFloats(channel: 0, frame: 0, count: n, into: tmp)
                for c in 0..<outCh { mapped.floatChannelData![c].update(from: tmp, count: n) }
            } else if outCh == 1 {
                let acc = mapped.floatChannelData![0]
                acc.update(repeating: 0, count: n)
                for c in 0..<inCh { raw._readFloats(channel: c, frame: 0, count: n, into: tmp); for i in 0..<n { acc[i] += tmp[i] / Float(inCh) } }
            } else {
                for c in 0..<outCh {
                    if c < inCh { raw._readFloats(channel: c, frame: 0, count: n, into: mapped.floatChannelData![c]) }
                    else { mapped.floatChannelData![c].update(repeating: 0, count: n) }
                }
            }
            source = mapped
        }
        return _RateConverter.convert(source, to: rate) ?? empty
    }

    private func _startSampleTime(_ when: AVAudioTime?) -> Int64 {
        guard let when, when.isSampleTimeValid else { return -1 }
        let rate = outputFormat(forBus: 0).sampleRate
        if when.sampleRate > 0, rate > 0, when.sampleRate != rate { return Int64(Double(when.sampleTime) * rate / when.sampleRate) }
        return when.sampleTime
    }

    // MARK: Transport

    open func play() { play(at: nil) }

    /// Starts rendering at `when` (a node time; nil or a host-only time means now).
    open func play(at when: AVAudioTime?) {
        var at: Int64 = -1
        if let when, when.isSampleTimeValid {
            at = when.sampleTime
        } else if let when, when.isHostTimeValid, let last = lastRenderTime, let t = when._sampleTime(fromAnchor: last) {
            at = t
        }
        _isPlaying.value = true
        _submit(_PlayerCommand(kind: .play, item: nil, nodeSampleTime: at))
    }

    open func pause() {
        _isPlaying.value = false
        _submit(_PlayerCommand(kind: .pause, item: nil, nodeSampleTime: -1))
    }

    /// Clears every scheduled item (their completion handlers are called) and stops.
    open func stop() {
        _isPlaying.value = false
        _submit(_PlayerCommand(kind: .stop, item: nil, nodeSampleTime: -1))
    }

    open override func reset() { stop() }

    open func prepare(withFrameCount frameCount: AVAudioFrameCount) {}

    open var isPlaying: Bool { _isPlaying.value }

    /// Converts a player time (0 at `play()`) to the engine's node time; nil when not playing.
    open func nodeTime(forPlayerTime playerTime: AVAudioTime) -> AVAudioTime? {
        guard _state.timeValid.value, playerTime.isSampleTimeValid else { return nil }
        let rate = playerTime.sampleRate > 0 ? playerTime.sampleRate : _lastRate.value
        return AVAudioTime(sampleTime: playerTime.sampleTime + _state.timeOffset.value, atRate: rate)
    }

    open func playerTime(forNodeTime nodeTime: AVAudioTime) -> AVAudioTime? {
        guard _state.timeValid.value, nodeTime.isSampleTimeValid else { return nil }
        let rate = nodeTime.sampleRate > 0 ? nodeTime.sampleRate : _lastRate.value
        return AVAudioTime(sampleTime: nodeTime.sampleTime - _state.timeOffset.value, atRate: rate)
    }

    /// Queues a command for the render thread, or applies it at once when no render thread
    /// can be running (the engine is stopped, in manual rendering mode, or the node is not
    /// attached). The engine lock keeps the two cases from overlapping.
    func _submit(_ command: _PlayerCommand) {
        producerLock.lock(); defer { producerLock.unlock() }
        let engine = _engine
        engine?._lock.lock(); defer { engine?._lock.unlock() }
        overflow.append(command)
        while let next = overflow.first, _state.commands.push(next) { overflow.removeFirst() }
        if !(engine?._liveRendering ?? false) {
            _state.processCommands(nodeSampleTime: engine?._sampleTime.value ?? 0)
            _DeliveryHub.shared.signal()
        }
    }

    /// Delivery thread: calls the completion handlers the render side finished with.
    func _deliver() {
        while let e = _state.completions.pop() {
            let item = e.item.takeRetainedValue()
            if e.fires { item.completion?(item.callbackType) }
        }
        _pumpOverflow()
    }

    /// Moves commands that did not fit in the ring earlier into it now that there is room.
    private func _pumpOverflow() {
        producerLock.lock(); defer { producerLock.unlock() }
        while let next = overflow.first, _state.commands.push(next) { overflow.removeFirst() }
    }

    // MARK: AVAudioMixing

    open func destination(forMixer mixer: AVAudioNode, bus: AVAudioNodeBus) -> AVAudioMixingDestination? {
        _mixingSource.destination(forMixer: mixer, bus: bus, connected: _outputConnections[0]?.contains { $0.destination === mixer && $0.destinationBus == bus } ?? false)
    }
    open var volume: Float {
        get { _mixingSource.node.volume.value }
        set { _mixingSource.node.volume.value = newValue; _mixingSource.forEachDestination { $0.volume.value = newValue } }
    }
    open var pan: Float {
        get { _mixingSource.node.pan.value }
        set { _mixingSource.node.pan.value = newValue; _mixingSource.forEachDestination { $0.pan.value = newValue } }
    }
    open var renderingAlgorithm: AVAudio3DMixingRenderingAlgorithm {
        get { _mixingSource.node.renderingAlgorithm }
        set { _mixingSource.node.renderingAlgorithm = newValue }
    }
    open var sourceMode: AVAudio3DMixingSourceMode {
        get { _mixingSource.node.sourceMode }
        set { _mixingSource.node.sourceMode = newValue }
    }
    open var pointSourceInHeadMode: AVAudio3DMixingPointSourceInHeadMode {
        get { _mixingSource.node.pointSourceInHeadMode }
        set { _mixingSource.node.pointSourceInHeadMode = newValue }
    }
    open var rate: Float {
        get { _mixingSource.node.rate }
        set { _mixingSource.node.rate = newValue }
    }
    open var reverbBlend: Float {
        get { _mixingSource.node.reverbBlend }
        set { _mixingSource.node.reverbBlend = newValue }
    }
    open var obstruction: Float {
        get { _mixingSource.node.obstruction }
        set { _mixingSource.node.obstruction = newValue }
    }
    open var occlusion: Float {
        get { _mixingSource.node.occlusion }
        set { _mixingSource.node.occlusion = newValue }
    }
    open var position: AVAudio3DPoint {
        get { _mixingSource.node.position }
        set { _mixingSource.node.position = newValue }
    }
}

// Swift concurrency variants of the scheduling calls (Apple's async overlay).
extension AVAudioPlayerNode {
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType) async {
        await withCheckedContinuation { c in scheduleBuffer(buffer, completionCallbackType: callbackType) { _ in c.resume() } }
    }
    public func scheduleBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime?, options: AVAudioPlayerNodeBufferOptions = [], completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType) async {
        await withCheckedContinuation { c in scheduleBuffer(buffer, at: when, options: options, completionCallbackType: callbackType) { _ in c.resume() } }
    }
    public func scheduleFile(_ file: AVAudioFile, at when: AVAudioTime?, completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType) async {
        await withCheckedContinuation { c in scheduleFile(file, at: when, completionCallbackType: callbackType) { _ in c.resume() } }
    }
    public func scheduleSegment(_ file: AVAudioFile, startingFrame startFrame: AVAudioFramePosition, frameCount numberFrames: AVAudioFrameCount, at when: AVAudioTime?, completionCallbackType callbackType: AVAudioPlayerNodeCompletionCallbackType) async {
        await withCheckedContinuation { c in scheduleSegment(file, startingFrame: startFrame, frameCount: numberFrames, at: when, completionCallbackType: callbackType) { _ in c.resume() } }
    }
}
