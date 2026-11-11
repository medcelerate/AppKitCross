// AVAudioNode and the I/O node classes.

import Foundation

public typealias AVAudioNodeTapBlock = (AVAudioPCMBuffer, AVAudioTime) -> Void

/// A connection between an output bus and an input bus, in the format the source renders.
final class _Connection {
    let source: AVAudioNode
    let sourceBus: AVAudioNodeBus
    let destination: AVAudioNode
    let destinationBus: AVAudioNodeBus
    let format: AVAudioFormat
    init(source: AVAudioNode, sourceBus: AVAudioNodeBus, destination: AVAudioNode, destinationBus: AVAudioNodeBus, format: AVAudioFormat) {
        self.source = source; self.sourceBus = sourceBus; self.destination = destination; self.destinationBus = destinationBus; self.format = format
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudionode
open class AVAudioNode: NSObject {
    weak var _engine: AVAudioEngine?
    var _inputConnections: [AVAudioNodeBus: _Connection] = [:]
    var _outputConnections: [AVAudioNodeBus: [_Connection]] = [:]
    var _taps: [AVAudioNodeBus: _TapState] = [:]
    let _lastSampleTime = _AtomicInt64(-1)
    let _lastHostTime = _AtomicInt64(0)
    let _lastRate = _AtomicDouble(0)
    let _latency = _AtomicDouble(0)
    let _presentationLatency = _AtomicDouble(0)

    public override init() { super.init() }

    open var engine: AVAudioEngine? { _engine }
    open var numberOfInputs: Int { 0 }
    open var numberOfOutputs: Int { 1 }

    /// The format of the connection into `bus` (an empty format when unconnected).
    open func inputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        _engine?._lock.lock(); defer { _engine?._lock.unlock() }
        return _inputConnections[bus]?.format ?? AVAudioFormat()
    }

    /// The format of the connection out of `bus`, or the node's default output format.
    open func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        _engine?._lock.lock(); defer { _engine?._lock.unlock() }
        return _outputConnections[bus]?.first?.format ?? _defaultOutputFormat(forBus: bus)
    }

    /// What `outputFormat(forBus:)` reports before the bus is connected.
    func _defaultOutputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { AVAudioFormat() }

    open func name(forInputBus bus: AVAudioNodeBus) -> String? { nil }
    open func name(forOutputBus bus: AVAudioNodeBus) -> String? { nil }

    /// Delivers the bus's output to `tapBlock` in buffers of about `bufferSize` frames, from
    /// a thread of the engine's (the render thread hands the frames over without blocking).
    /// `format` nil means the bus's output format; otherwise it must be Float32 at the same
    /// sample rate and channel count.
    open func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block tapBlock: @escaping AVAudioNodeTapBlock) {
        let engine = _engine
        engine?._lock.lock(); defer { engine?._lock.unlock() }
        let busFormat = _outputConnections[bus]?.first?.format ?? _defaultOutputFormat(forBus: bus)
        let tapFormat = format ?? busFormat
        precondition(tapFormat.commonFormat == .pcmFormatFloat32 && (busFormat.channelCount == 0 || (tapFormat.channelCount == busFormat.channelCount && tapFormat.sampleRate == busFormat.sampleRate)),
                     "AVAudioNode.installTap: the tap format must be Float32 at the bus's sample rate and channel count")
        if let old = _taps[bus] { old.detach() }
        let size = min(max(Int(bufferSize), 100), 16384)
        _taps[bus] = _TapState(node: self, bus: bus, bufferSize: size, format: tapFormat, block: tapBlock)
        engine?._graphChanged()
    }

    open func removeTap(onBus bus: AVAudioNodeBus) {
        let engine = _engine
        engine?._lock.lock(); defer { engine?._lock.unlock() }
        guard let tap = _taps.removeValue(forKey: bus) else { return }
        tap.detach()
        engine?._graphChanged()
    }

    /// Clears the node's processing state (a player node also stops and clears its schedule).
    open func reset() {}

    /// The time of the last render cycle this node took part in (nil before the first).
    open var lastRenderTime: AVAudioTime? {
        let s = _lastSampleTime.value
        guard s >= 0 else { return nil }
        return AVAudioTime(hostTime: UInt64(_lastHostTime.value), sampleTime: s, atRate: _lastRate.value)
    }

    /// Processing latency of the node itself (zero for every node here).
    open var latency: TimeInterval { _latency.value }

    /// Latency from this node's output to the device (zero in manual rendering mode).
    open var outputPresentationLatency: TimeInterval { _presentationLatency.value }

    /// Whether the graph needs to pull this node (sources render on demand).
    var _isSource: Bool { false }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioionode
open class AVAudioIONode: AVAudioNode {
    /// The latency of the audio hardware (zero in manual rendering mode).
    open var presentationLatency: TimeInterval { _presentationLatency.value }
    open var isVoiceProcessingEnabled: Bool { false }
    open func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        if enabled { throw _osStatusError(-10868, "AVAudioIONode: voice processing is not available") }
    }
}

/// Hands captured frames from an input stream's thread to the render thread.
final class _InputCapture {
    let ring: _FrameRing
    let channels: Int
    let period: Int
    /// The stream's interleaved channel count (set before the stream starts).
    var streamChannels: Int
    private let scratch: UnsafeMutablePointer<Float>
    private let scratchFrames = 2048
    /// Frames dropped because the render side did not keep up, or invented because the
    /// capture side was late (diagnostics).
    let overruns = _AtomicInt64(0)
    let underruns = _AtomicInt64(0)
    /// Render thread: whether the backlog has reached the headroom it reads with (after the
    /// start and after every underrun the input waits for it, so jitter between the capture
    /// and render threads does not cut holes in the signal).
    var primed = false

    init(channels: Int, period: Int) {
        self.channels = max(1, channels)
        self.period = max(64, period)
        streamChannels = self.channels
        ring = _FrameRing(channels: self.channels, capacity: max(16384, self.period * 16))
        scratch = .allocate(capacity: scratchFrames * self.channels)
    }

    deinit { scratch.deallocate() }

    /// Capture thread.
    func captured(_ src: UnsafePointer<Float>, frames: Int) {
        let sc = streamChannels
        if sc == channels {
            if !ring.writeInterleaved(src, frames: frames) { overruns.add(Int64(frames)) }
            return
        }
        var done = 0
        while done < frames {
            let n = min(scratchFrames, frames - done)
            for f in 0..<n {
                let s = src + (done + f) * sc
                for c in 0..<channels { scratch[f * channels + c] = s[sc == 1 ? 0 : min(c, sc - 1)] }
            }
            if !ring.writeInterleaved(scratch, frames: n) { overruns.add(Int64(n)) }
            done += n
        }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioinputnode
///
/// The engine's input: the default (or selected) capture device while the engine renders
/// to a device, or the manual rendering input block in manual rendering mode.
open class AVAudioInputNode: AVAudioIONode, AVAudioMixing {
    let _mixingSource = _MixingSource()
    var _capture: _InputCapture?
    var _manualFormat: AVAudioFormat?
    var _manualBlock: AVAudioIONodeInputBlock?
    override init() { super.init() }
    open override var numberOfInputs: Int { 0 }

    /// The hardware input format (an empty format when there is no input device).
    override func _defaultOutputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        if let f = _manualFormat, let s = AVAudioFormat(standardFormatWithSampleRate: f.sampleRate, channels: f.channelCount) { return s }
        return _engine?._inputHardwareFormat() ?? AVAudioFormat()
    }

    open override func inputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        _engine?._lock.lock(); defer { _engine?._lock.unlock() }
        return _defaultOutputFormat(forBus: bus)
    }

    /// In manual rendering mode, the input node pulls `block` for its frames in `format`
    /// (converted to the node's output format). False when the format is not linear PCM.
    open func setManualRenderingInputPCMFormat(_ format: AVAudioFormat, inputBlock block: @escaping AVAudioIONodeInputBlock) -> Bool {
        guard format.commonFormat != .otherFormat, format.channelCount > 0, format.sampleRate > 0 else { return false }
        let engine = _engine
        engine?._lock.lock(); defer { engine?._lock.unlock() }
        _manualFormat = format
        _manualBlock = block
        engine?._graphChanged()
        return true
    }

    /// Render thread: the next `frames` captured frames (zeros where capture fell behind).
    func _renderInput(into out: UnsafePointer<UnsafeMutablePointer<Float>>, channels: Int, frames: Int, capture: _InputCapture?) -> Bool {
        if capture == nil, let block = _manualBlock, let format = _manualFormat {
            guard let list = block(AVAudioFrameCount(frames)) else {
                for c in 0..<channels { out[c].update(repeating: 0, count: frames) }
                return false
            }
            let fc = Int(format.channelCount)
            for c in 0..<channels { _PCMListIO.read(list, format: format, channel: fc == 1 ? 0 : min(c, fc - 1), frame: 0, count: frames, into: out[c]) }
            return true
        }
        guard let capture, capture.channels == channels else {
            for c in 0..<channels { out[c].update(repeating: 0, count: frames) }
            return false
        }
        // Keep `frames` plus two capture periods buffered: wait for that much at the start
        // and after an underrun. Clock drift between the capture and render devices: when
        // the backlog grows past a few periods more, drop the oldest frames so the latency
        // stays bounded.
        let target = frames + capture.period * 2
        let backlog = capture.ring.count
        if !capture.primed {
            guard backlog >= target else {
                for c in 0..<channels { out[c].update(repeating: 0, count: frames) }
                return false
            }
            capture.primed = true
        }
        if backlog > target + capture.period * 6 { capture.ring.discard(backlog - target) }
        let available = min(frames, capture.ring.count)
        if available > 0 { _ = capture.ring.read(into: out, frames: available) }
        if available < frames {
            for c in 0..<channels { (out[c] + available).update(repeating: 0, count: frames - available) }
            capture.underruns.add(Int64(frames - available))
            capture.primed = false
        }
        return available > 0
    }

    open var isVoiceProcessingBypassed: Bool {
        get { false }
        set { }
    }
    open var isVoiceProcessingAGCEnabled: Bool {
        get { false }
        set { }
    }
    open var isVoiceProcessingInputMuted: Bool {
        get { false }
        set { }
    }
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

public typealias AVAudioIONodeInputBlock = (AVAudioFrameCount) -> UnsafePointer<AudioBufferList>?

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiooutputnode
open class AVAudioOutputNode: AVAudioIONode {
    override init() { super.init() }
    open override var numberOfInputs: Int { 1 }
    open override var numberOfOutputs: Int { 0 }
    open override func inputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        _engine?._lock.lock(); defer { _engine?._lock.unlock() }
        return _inputConnections[bus]?.format ?? _engine?._hardwareFormat() ?? AVAudioFormat()
    }
    /// The hardware (or manual rendering) format.
    open override func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        _engine?._hardwareFormat() ?? AVAudioFormat()
    }
}

/// Terminates with a message naming the unimplemented symbol (see `unimplemented()` in
/// AppKit; the audio module has its own copy so it does not depend on AppKit).
@inline(never)
func unimplemented(_ symbol: String = #function, file: StaticString = #fileID, line: UInt = #line) -> Never {
    fatalError("AppKitCross: `\(symbol)` is not implemented yet", file: file, line: line)
}
