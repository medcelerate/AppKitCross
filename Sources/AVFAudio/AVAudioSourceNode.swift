// AVAudioSourceNode and AVAudioSinkNode: client blocks on the render thread, supplying
// audio to the graph and receiving it from the input chain.

import Foundation

public typealias AVAudioSourceNodeRenderBlock = (UnsafeMutablePointer<ObjCBool>, UnsafePointer<AudioTimeStamp>, AVAudioFrameCount, UnsafeMutablePointer<AudioBufferList>) -> OSStatus

public typealias AVAudioSinkNodeReceiverBlock = (UnsafePointer<AudioTimeStamp>, AVAudioFrameCount, UnsafePointer<AudioBufferList>) -> OSStatus

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiosourcenode
open class AVAudioSourceNode: AVAudioNode, AVAudioMixing {
    let _block: AVAudioSourceNodeRenderBlock
    /// The block's own format (nil: the connection format).
    let _blockFormat: AVAudioFormat?
    let _mixingSource = _MixingSource()

    public init(renderBlock block: @escaping AVAudioSourceNodeRenderBlock) {
        _block = block
        _blockFormat = nil
        super.init()
    }

    /// `format` is the block's format; the output bus takes the connection format and the
    /// node converts (sample rate, sample format, interleaving, channel count).
    public init(format: AVAudioFormat, renderBlock block: @escaping AVAudioSourceNodeRenderBlock) {
        precondition(format.commonFormat != .otherFormat, "AVAudioSourceNode: the block format must be linear PCM in a common format")
        _block = block
        _blockFormat = format
        super.init()
    }

    open override var numberOfInputs: Int { 0 }
    override var _isSource: Bool { true }

    override func _defaultOutputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        if let f = _blockFormat, let s = AVAudioFormat(standardFormatWithSampleRate: f.sampleRate, channels: f.channelCount) { return s }
        return AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
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

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiosinknode
///
/// The engine pulls a sink node every render cycle (it has no output bus to be pulled
/// through); connect it from the input node in the input's format.
open class AVAudioSinkNode: AVAudioNode {
    let _block: AVAudioSinkNodeReceiverBlock

    public init(receiverBlock block: @escaping AVAudioSinkNodeReceiverBlock) {
        _block = block
        super.init()
    }

    open override var numberOfInputs: Int { 1 }
    open override var numberOfOutputs: Int { 0 }
}

/// The render side of a source node: an AudioBufferList in the block's format, and the
/// conversion to the connection's planar Float32.
final class _SourceRenderState {
    private let block: AVAudioSourceNodeRenderBlock
    private let blockFormat: AVAudioFormat
    private let blockChannels: Int
    private let outChannels: Int
    private let capacity: Int
    private let list: UnsafeMutableAudioBufferListPointer
    private let storage: UnsafeMutableRawPointer
    private let bytesPerBuffer: Int
    private let isSilence = UnsafeMutablePointer<ObjCBool>.allocate(capacity: 1)
    private let timestamp = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)
    private let planes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let mapped: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let matrix: _ChannelMatrix
    private let resampler: _Resampler?
    private let rate: Double
    private var blockSampleTime: Int64 = 0
    /// Whether the block format is the connection format (the block writes `out` directly).
    private let direct: Bool

    init(node: AVAudioSourceNode, connectionFormat: AVAudioFormat, maxFrames: Int) {
        block = node._block
        let bf = node._blockFormat ?? connectionFormat
        blockFormat = bf
        blockChannels = Int(bf.channelCount)
        outChannels = Int(connectionFormat.channelCount)
        rate = connectionFormat.sampleRate
        direct = node._blockFormat == nil || (bf.isStandard && bf.sampleRate == connectionFormat.sampleRate && bf.channelCount == connectionFormat.channelCount)
        let ratio = bf.sampleRate / connectionFormat.sampleRate
        resampler = ratio == 1 ? nil : _Resampler(channels: outChannels, ratio: ratio, maxStretch: max(ratio, 1 / ratio), maxOutputFrames: maxFrames)
        capacity = Int(Double(maxFrames) * max(1, ratio)) + 128
        let bufferCount = bf.isInterleaved ? 1 : blockChannels
        bytesPerBuffer = capacity * Int(bf.streamDescription.pointee.mBytesPerFrame)
        storage = .allocate(byteCount: max(16, bytesPerBuffer * bufferCount), alignment: 16)
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: max(16, bytesPerBuffer * bufferCount))
        list = AudioBufferList.allocate(maximumBuffers: bufferCount)
        planes = .allocate(capacity: blockChannels)
        for c in 0..<blockChannels { planes[c] = .allocate(capacity: capacity) }
        mapped = .allocate(capacity: outChannels)
        for c in 0..<outChannels { mapped[c] = .allocate(capacity: capacity) }
        matrix = .standard(inputs: blockChannels, outputs: outChannels)
        isSilence.initialize(to: false)
        timestamp.initialize(to: AudioTimeStamp())
    }

    deinit {
        UnsafeMutableRawPointer(list.unsafeMutablePointer).deallocate()
        storage.deallocate()
        for c in 0..<blockChannels { planes[c].deallocate() }
        for c in 0..<outChannels { mapped[c].deallocate() }
        planes.deallocate(); mapped.deallocate()
        isSilence.deallocate(); timestamp.deallocate()
    }

    /// Points the list at `frames` frames of storage (the block may swap the pointers).
    private func prepareList(frames: Int, directOut: UnsafePointer<UnsafeMutablePointer<Float>>?) {
        let bytes = UInt32(frames * Int(blockFormat.streamDescription.pointee.mBytesPerFrame))
        for b in 0..<list.count {
            let data: UnsafeMutableRawPointer = directOut.map { UnsafeMutableRawPointer($0[b]) } ?? storage.advanced(by: b * bytesPerBuffer)
            list[b] = AudioBuffer(mNumberChannels: blockFormat.isInterleaved ? UInt32(blockChannels) : 1, mDataByteSize: bytes, mData: data)
        }
    }

    private func callBlock(frames: Int, sampleTime: Int64, hostTime: Int64) -> Bool {
        isSilence.pointee = false
        timestamp.pointee = AudioTimeStamp()
        timestamp.pointee.mSampleTime = Float64(sampleTime)
        timestamp.pointee.mHostTime = UInt64(max(0, hostTime))
        timestamp.pointee.mRateScalar = 1
        timestamp.pointee.mFlags = [.sampleTimeValid, .hostTimeValid]
        let status = block(isSilence, UnsafePointer(timestamp), AVAudioFrameCount(frames), list.unsafeMutablePointer)
        return status == 0 && !isSilence.pointee.boolValue
    }

    /// Renders `frames` frames of the connection format into `out`.
    func render(into out: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int, sampleTime: Int64, hostTime: Int64) -> Bool {
        if direct {
            prepareList(frames: frames, directOut: out)
            let audible = callBlock(frames: frames, sampleTime: sampleTime, hostTime: hostTime)
            // The block may have pointed the buffers at its own memory.
            for c in 0..<outChannels {
                if let d = list[c].mData, d != UnsafeMutableRawPointer(out[c]) { out[c].update(from: d.assumingMemoryBound(to: Float.self), count: frames) }
            }
            if !audible { for c in 0..<outChannels { out[c].update(repeating: 0, count: frames) } }
            blockSampleTime = sampleTime + Int64(frames)
            return audible
        }
        guard let resampler else {
            let n = min(frames, capacity)
            prepareList(frames: n, directOut: nil)
            let audible = callBlock(frames: n, sampleTime: sampleTime, hostTime: hostTime)
            for c in 0..<blockChannels { _PCMListIO.read(list.unsafePointer, format: blockFormat, channel: c, frame: 0, count: n, into: planes[c]) }
            matrix.apply(UnsafePointer(planes), into: out, frames: n)
            if !audible { for c in 0..<outChannels { out[c].update(repeating: 0, count: frames) } }
            return audible
        }
        var audible = false
        var need = resampler.inputFramesNeeded(for: frames)
        while need > 0 {
            let n = min(need, capacity, resampler.freeSpace)
            if n <= 0 { break }
            prepareList(frames: n, directOut: nil)
            if callBlock(frames: n, sampleTime: blockSampleTime, hostTime: hostTime) { audible = true }
            blockSampleTime += Int64(n)
            for c in 0..<blockChannels { _PCMListIO.read(list.unsafePointer, format: blockFormat, channel: c, frame: 0, count: n, into: planes[c]) }
            matrix.apply(UnsafePointer(planes), into: UnsafePointer(mapped), frames: n)
            resampler.push(UnsafePointer(mapped), frames: n)
            need -= n
        }
        resampler.produce(out, frames: frames)
        _ = audible
        return true
    }
}

/// The render side of a sink node: hands its input to the block as a buffer list.
final class _SinkRenderState {
    private let block: AVAudioSinkNodeReceiverBlock
    private let channels: Int
    private let list: UnsafeMutableAudioBufferListPointer
    private let timestamp = UnsafeMutablePointer<AudioTimeStamp>.allocate(capacity: 1)
    /// Fractional frames owed at the sink's rate when it differs from the graph's.
    var fraction: Double = 0

    init(node: AVAudioSinkNode, channels: Int) {
        block = node._block
        self.channels = channels
        list = AudioBufferList.allocate(maximumBuffers: channels)
        timestamp.initialize(to: AudioTimeStamp())
    }

    deinit { UnsafeMutableRawPointer(list.unsafeMutablePointer).deallocate(); timestamp.deallocate() }

    func deliver(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int, sampleTime: Int64, hostTime: Int64) {
        for c in 0..<channels {
            list[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(planes[c]))
        }
        timestamp.pointee.mSampleTime = Float64(sampleTime)
        timestamp.pointee.mHostTime = UInt64(max(0, hostTime))
        timestamp.pointee.mRateScalar = 1
        timestamp.pointee.mFlags = [.sampleTimeValid, .hostTimeValid]
        _ = block(UnsafePointer(timestamp), AVAudioFrameCount(frames), list.unsafePointer)
    }
}
