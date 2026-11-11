// AVAudioConverter for linear PCM: sample format (Int16, Int32, Float32, Float64),
// interleaving, channel count (channelMap, downmix) and sample rate (the band-limited
// resampler, with Apple's "normal" priming: no latency at the output, trailing frames
// synthesized as silence at the end of the stream). Codecs are not available: a format
// that is not linear PCM makes the initializer return nil.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioconverterprimemethod
public enum AVAudioConverterPrimeMethod: Int, @unchecked Sendable {
    case pre = 0
    case normal = 1
    case none = 2
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioconverterprimeinfo
public struct AVAudioConverterPrimeInfo {
    public var leadingFrames: AVAudioFrameCount
    public var trailingFrames: AVAudioFrameCount
    public init() { leadingFrames = 0; trailingFrames = 0 }
    public init(leadingFrames: AVAudioFrameCount, trailingFrames: AVAudioFrameCount) {
        self.leadingFrames = leadingFrames; self.trailingFrames = trailingFrames
    }
}

public enum AVAudioConverterInputStatus: Int, @unchecked Sendable {
    case haveData = 0
    case noDataNow = 1
    case endOfStream = 2
}

public enum AVAudioConverterOutputStatus: Int, @unchecked Sendable {
    case haveData = 0
    case inputRanDry = 1
    case endOfStream = 2
    case error = 3
}

#if !canImport(Darwin)
/// Foundation's `NSErrorPointer` (an autoreleasing pointer on Apple platforms); the
/// open-source Foundation has none, so the converter's out-error parameter uses a plain
/// pointer there, which `&error` passes the same way.
public typealias NSErrorPointer = UnsafeMutablePointer<NSError?>?
#endif

public typealias AVAudioConverterInputBlock = @Sendable (AVAudioPacketCount, UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer?

/// kAudioConverterErr_FormatNotSupported ('fmt?') and kAudio_ParamError.
let _kAudioConverterErr_FormatNotSupported: OSStatus = 0x666D743F
let _kAudio_ParamError: OSStatus = -50

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioconverter
open class AVAudioConverter: NSObject, @unchecked Sendable {
    private let _inputFormat: AVAudioFormat
    private let _outputFormat: AVAudioFormat
    private let lock = NSRecursiveLock()
    private var _channelMap: [NSNumber]
    private var _explicitMap = false
    private var _downmix = false
    private var matrix: _ChannelMatrix
    private let resampler: _Resampler?
    private let chunk = 1024
    private let inPlanes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let mapped: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let inChannels: Int, outChannels: Int
    // Stream state for convert(to:error:withInputFrom:).
    private var pending: AVAudioPCMBuffer?
    private var pendingOffset = 0
    private var endOfStream = false
    private var inputTotal: Int64 = 0
    private var outputTotal: Int64 = 0

    public init?(from fromFormat: AVAudioFormat, to toFormat: AVAudioFormat) {
        guard fromFormat.commonFormat != .otherFormat, toFormat.commonFormat != .otherFormat,
              fromFormat.channelCount > 0, toFormat.channelCount > 0, fromFormat.sampleRate > 0, toFormat.sampleRate > 0 else { return nil }
        _inputFormat = fromFormat
        _outputFormat = toFormat
        let ins = Int(fromFormat.channelCount), outs = Int(toFormat.channelCount)
        inChannels = ins
        outChannels = outs
        matrix = .standard(inputs: ins, outputs: outs)
        _channelMap = (0..<outs).map { NSNumber(value: $0 < ins ? $0 : (ins == 1 ? 0 : -1)) }
        if fromFormat.sampleRate != toFormat.sampleRate {
            let ratio = fromFormat.sampleRate / toFormat.sampleRate
            resampler = _Resampler(channels: outChannels, ratio: ratio, maxStretch: max(ratio, 1 / ratio), maxOutputFrames: chunk)
        } else {
            resampler = nil
        }
        inPlanes = .allocate(capacity: inChannels)
        for c in 0..<inChannels { inPlanes[c] = .allocate(capacity: chunk) }
        mapped = .allocate(capacity: outChannels)
        for c in 0..<outChannels { mapped[c] = .allocate(capacity: chunk) }
        super.init()
    }

    deinit {
        for c in 0..<inChannels { inPlanes[c].deallocate() }
        for c in 0..<outChannels { mapped[c].deallocate() }
        inPlanes.deallocate(); mapped.deallocate()
    }

    /// Forgets the stream: the next conversion starts afresh (and calls the input block).
    open func reset() {
        lock.lock(); defer { lock.unlock() }
        resampler?.reset()
        pending = nil; pendingOffset = 0; endOfStream = false; inputTotal = 0; outputTotal = 0
    }

    open var inputFormat: AVAudioFormat { _inputFormat }
    open var outputFormat: AVAudioFormat { _outputFormat }

    /// Output channel n copies input channel `channelMap[n]` (negative: silence).
    open var channelMap: [NSNumber] {
        get { lock.withLock { _channelMap } }
        set {
            lock.lock(); defer { lock.unlock() }
            _channelMap = newValue
            _explicitMap = true
            _rebuildMatrix()
        }
    }

    open var magicCookie: Data?

    /// Mix channels when the counts differ instead of dropping or duplicating them.
    open var downmix: Bool {
        get { lock.withLock { _downmix } }
        set { lock.lock(); _downmix = newValue; _rebuildMatrix(); lock.unlock() }
    }

    private func _rebuildMatrix() {
        if _explicitMap { matrix = .map(_channelMap.map { $0.intValue }, inputs: inChannels, outputs: outChannels) }
        else if _downmix && inChannels > outChannels { matrix = .downmix(inputs: inChannels, outputs: outChannels) }
        else { matrix = .standard(inputs: inChannels, outputs: outChannels) }
    }

    /// Accepted for compatibility; integer outputs are rounded, not dithered.
    open var dither: Bool = false
    /// Accepted; the resampler has one quality (see ADR-0028).
    open var sampleRateConverterQuality: Int = AVAudioQuality.high.rawValue
    open var sampleRateConverterAlgorithm: String?
    /// The priming method. `.normal` and `.pre` behave alike here (the resampler adds no
    /// output latency and synthesizes the trailing frames); `.none` too.
    open var primeMethod: AVAudioConverterPrimeMethod = .normal
    open var primeInfo: AVAudioConverterPrimeInfo {
        get {
            guard resampler != nil else { return AVAudioConverterPrimeInfo() }
            return AVAudioConverterPrimeInfo(leadingFrames: 16, trailingFrames: 16)
        }
        set { }
    }

    // MARK: Simple conversion

    /// Converts without a sample-rate change (format, interleaving and channels only).
    open func convert(to outputBuffer: AVAudioPCMBuffer, from inputBuffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        guard resampler == nil else {
            throw _osStatusError(_kAudioConverterErr_FormatNotSupported, "AVAudioConverter: a sample-rate conversion needs convert(to:error:withInputFrom:)")
        }
        guard inputBuffer.format.isEqual(_inputFormat), outputBuffer.format.isEqual(_outputFormat) else {
            throw _osStatusError(_kAudio_ParamError, "AVAudioConverter: the buffers are not in the converter's formats")
        }
        let frames = Int(inputBuffer.frameLength)
        guard Int(outputBuffer.frameCapacity) >= frames else {
            throw _osStatusError(_kAudio_ParamError, "AVAudioConverter: the output buffer is smaller than the input")
        }
        var done = 0
        while done < frames {
            let n = min(chunk, frames - done)
            _readMapped(inputBuffer, from: done, count: n)
            _writeOut(outputBuffer, at: done, count: n)
            done += n
        }
        outputBuffer.frameLength = AVAudioFrameCount(frames)
    }

    /// Reads `count` frames of `buffer` from `offset` into `mapped` (output channel layout).
    private func _readMapped(_ buffer: AVAudioPCMBuffer, from offset: Int, count: Int) {
        for c in 0..<inChannels { buffer._readFloats(channel: c, frame: offset, count: count, into: inPlanes[c]) }
        matrix.apply(UnsafePointer(inPlanes), into: UnsafePointer(mapped), frames: count)
    }

    private func _writeOut(_ buffer: AVAudioPCMBuffer, at offset: Int, count: Int) {
        for c in 0..<outChannels { buffer._writeFloats(channel: c, frame: offset, count: count, from: mapped[c]) }
    }

    // MARK: Streaming conversion

    /// Fills `outputBuffer` to its capacity, pulling input from `inputBlock` as needed.
    open func convert(to outputBuffer: AVAudioBuffer, error outError: NSErrorPointer, withInputFrom inputBlock: @escaping AVAudioConverterInputBlock) -> AVAudioConverterOutputStatus {
        lock.lock(); defer { lock.unlock() }
        guard let out = outputBuffer as? AVAudioPCMBuffer, out.format.isEqual(_outputFormat) else {
            outError?.pointee = _osStatusError(_kAudio_ParamError, "AVAudioConverter: the output buffer is not in the output format")
            return .error
        }
        let capacity = Int(out.frameCapacity)
        var produced = 0
        var ranDry = false
        var failed: NSError?

        /// Makes sure `pending` has frames; false when no more input is available now.
        func refill(_ wanted: Int) -> Bool {
            if let p = pending, pendingOffset < Int(p.frameLength) { return true }
            pending = nil; pendingOffset = 0
            if endOfStream { return false }
            var status = AVAudioConverterInputStatus.haveData
            let buffer = inputBlock(AVAudioPacketCount(max(1, wanted)), &status)
            switch status {
            case .haveData:
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.format.isEqual(_inputFormat) else {
                    failed = _osStatusError(_kAudio_ParamError, "AVAudioConverter: the input block returned a buffer not in the input format")
                    return false
                }
                if pcm.frameLength == 0 { return refill(wanted) }
                pending = pcm
                return true
            case .noDataNow:
                ranDry = true
                return false
            case .endOfStream:
                endOfStream = true
                return false
            }
        }

        if let resampler {
            let outRate = _outputFormat.sampleRate, inRate = _inputFormat.sampleRate
            while produced < capacity && failed == nil {
                var want = min(chunk, capacity - produced)
                if endOfStream {
                    let expected = Int64((Double(inputTotal) * outRate / inRate).rounded())
                    want = Int(min(Int64(want), expected - outputTotal))
                    if want <= 0 { break }
                }
                var need = resampler.inputFramesNeeded(for: want)
                while need > 0 && failed == nil {
                    if refill(need), let p = pending {
                        let take = min(need, Int(p.frameLength) - pendingOffset, chunk, resampler.freeSpace)
                        if take <= 0 { break }
                        _readMapped(p, from: pendingOffset, count: take)
                        resampler.push(UnsafePointer(mapped), frames: take)
                        pendingOffset += take
                        inputTotal += Int64(take)
                        need -= take
                    } else if endOfStream {
                        // Recompute the target now that the length is known, then pad.
                        let expected = Int64((Double(inputTotal) * outRate / inRate).rounded())
                        want = Int(min(Int64(want), expected - outputTotal))
                        if want <= 0 { need = 0; break }
                        need = resampler.inputFramesNeeded(for: want)
                        resampler.pushSilence(frames: min(need, resampler.freeSpace))
                        need = resampler.inputFramesNeeded(for: want)
                    } else {
                        break
                    }
                }
                if want <= 0 { break }
                while want > 0 && resampler.inputFramesNeeded(for: want) > 0 { want -= 1 }
                if want == 0 { break }
                resampler.produce(UnsafePointer(mapped), frames: want)
                _writeOut(out, at: produced, count: want)
                produced += want
                outputTotal += Int64(want)
                if ranDry { break }
            }
        } else {
            while produced < capacity && failed == nil {
                let want = min(chunk, capacity - produced)
                guard refill(want), let p = pending else { break }
                let take = min(want, Int(p.frameLength) - pendingOffset)
                _readMapped(p, from: pendingOffset, count: take)
                _writeOut(out, at: produced, count: take)
                pendingOffset += take
                produced += take
            }
        }
        out.frameLength = AVAudioFrameCount(produced)
        if let failed { outError?.pointee = failed; return .error }
        if produced > 0 { return .haveData }
        return endOfStream ? .endOfStream : .inputRanDry
    }

    // MARK: Encoding (linear PCM is not encoded)

    /// Bit rate when encoding; linear PCM is not encoded, so 0.
    open var bitRate: Int {
        get { 0 }
        set { }
    }
    open var bitRateStrategy: String? {
        get { nil }
        set { }
    }
    /// The output's bytes per frame (a PCM packet is one frame).
    open var maximumOutputPacketSize: Int { Int(outputFormat.streamDescription.pointee.mBytesPerPacket) }
    open var availableEncodeBitRates: [NSNumber]? { nil }
    open var applicableEncodeBitRates: [NSNumber]? { nil }
    open var availableEncodeSampleRates: [NSNumber]? { nil }
    open var applicableEncodeSampleRates: [NSNumber]? { nil }
    open var availableEncodeChannelLayoutTags: [NSNumber]? { nil }
}
