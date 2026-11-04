// AVAudioBuffer and AVAudioPCMBuffer: a format plus an AudioBufferList of sample memory.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiobuffer
open class AVAudioBuffer: NSObject, NSCopying, NSMutableCopying {
    let _format: AVAudioFormat
    let _list: UnsafeMutableAudioBufferListPointer
    /// Owned sample memory (one allocation for all buffers), nil for no-copy buffers.
    private var _storage: UnsafeMutableRawPointer?
    private var _deallocator: ((UnsafePointer<AudioBufferList>) -> Void)?

    init(format: AVAudioFormat, list: UnsafeMutableAudioBufferListPointer, storage: UnsafeMutableRawPointer?, deallocator: ((UnsafePointer<AudioBufferList>) -> Void)?) {
        _format = format; _list = list; _storage = storage; _deallocator = deallocator
        super.init()
    }

    deinit {
        if let d = _deallocator { d(_list.unsafePointer) }
        _storage?.deallocate()
        UnsafeMutableRawPointer(_list.unsafeMutablePointer).deallocate()
    }

    open var format: AVAudioFormat { _format }
    open var audioBufferList: UnsafePointer<AudioBufferList> { _list.unsafePointer }
    open var mutableAudioBufferList: UnsafeMutablePointer<AudioBufferList> { _list.unsafeMutablePointer }

    open func copy(with zone: NSZone? = nil) -> Any { preconditionFailure("AVAudioBuffer is abstract") }
    open func mutableCopy(with zone: NSZone? = nil) -> Any { copy(with: zone) }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer
open class AVAudioPCMBuffer: AVAudioBuffer {
    private let _frameCapacity: AVAudioFrameCount
    private var _frameLength: AVAudioFrameCount = 0
    /// Per-channel data pointers, stable for the buffer's lifetime.
    private let _channelPointers: UnsafeMutablePointer<UnsafeMutableRawPointer>
    private let _channelCount: Int

    /// Nil when the format has no bytes per frame or the capacity does not fit.
    public init?(pcmFormat format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0, format.channelCount > 0 else { return nil }
        let channels = Int(format.channelCount)
        let bufferCount = format._bufferCount
        let bytesPerBuffer = Int(frameCapacity) * bytesPerFrame
        guard bytesPerBuffer <= Int(UInt32.max) else { return nil }
        let list = AudioBufferList.allocate(maximumBuffers: bufferCount)
        let total = max(1, bytesPerBuffer * bufferCount)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: total, alignment: 16)
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: total)
        _channelPointers = UnsafeMutablePointer<UnsafeMutableRawPointer>.allocate(capacity: channels)
        _channelCount = channels
        let bytesPerSample = format._bytesPerSample
        for b in 0..<bufferCount {
            let base = storage.advanced(by: b * bytesPerBuffer)
            list[b] = AudioBuffer(mNumberChannels: format.isInterleaved ? UInt32(channels) : 1, mDataByteSize: 0, mData: base)
        }
        for c in 0..<channels {
            _channelPointers[c] = format.isInterleaved ? storage.advanced(by: c * bytesPerSample) : storage.advanced(by: c * bytesPerBuffer)
        }
        _frameCapacity = frameCapacity
        super.init(format: format, list: list, storage: storage, deallocator: nil)
    }

    /// Wraps caller-owned memory; `deallocator` runs when the buffer is freed.
    public init?(pcmFormat format: AVAudioFormat, bufferListNoCopy bufferList: UnsafePointer<AudioBufferList>, deallocator: ((UnsafePointer<AudioBufferList>) -> Void)? = nil) {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard bytesPerFrame > 0, src.count > 0, src.count == format._bufferCount else { return nil }
        let size = Int(src[0].mDataByteSize)
        guard size > 0 else { return nil }
        for b in 0..<src.count { guard src[b].mData != nil, Int(src[b].mDataByteSize) == size else { return nil } }
        let list = AudioBufferList.allocate(maximumBuffers: src.count)
        for b in 0..<src.count { list[b] = src[b] }
        let channels = Int(format.channelCount)
        _channelPointers = UnsafeMutablePointer<UnsafeMutableRawPointer>.allocate(capacity: channels)
        _channelCount = channels
        for c in 0..<channels {
            _channelPointers[c] = format.isInterleaved ? list[0].mData!.advanced(by: c * format._bytesPerSample) : list[c].mData!
        }
        _frameCapacity = AVAudioFrameCount(size / bytesPerFrame)
        _frameLength = _frameCapacity
        super.init(format: format, list: list, storage: nil, deallocator: deallocator)
    }

    deinit { _channelPointers.deallocate() }

    open var frameCapacity: AVAudioFrameCount { _frameCapacity }

    /// The number of valid frames; setting it updates the buffer list's byte sizes. A
    /// value above the capacity is a programming error (Apple's engine traps too).
    open var frameLength: AVAudioFrameCount {
        get { _frameLength }
        set {
            precondition(newValue <= _frameCapacity, "AVAudioPCMBuffer: required condition is false: length <= _imp->_frameCapacity")
            _frameLength = newValue
            let bytes = UInt32(Int(_frameLength) * Int(_format.streamDescription.pointee.mBytesPerFrame))
            for b in 0..<_list.count { _list[b].mDataByteSize = bytes }
        }
    }

    /// Samples between consecutive frames of one channel: the channel count when
    /// interleaved, 1 otherwise.
    open var stride: Int { _format.isInterleaved ? Int(_format.channelCount) : 1 }

    open var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? {
        guard _format.commonFormat == .pcmFormatFloat32 else { return nil }
        return UnsafeRawPointer(_channelPointers).assumingMemoryBound(to: UnsafeMutablePointer<Float>.self)
    }
    open var int16ChannelData: UnsafePointer<UnsafeMutablePointer<Int16>>? {
        guard _format.commonFormat == .pcmFormatInt16 else { return nil }
        return UnsafeRawPointer(_channelPointers).assumingMemoryBound(to: UnsafeMutablePointer<Int16>.self)
    }
    open var int32ChannelData: UnsafePointer<UnsafeMutablePointer<Int32>>? {
        guard _format.commonFormat == .pcmFormatInt32 else { return nil }
        return UnsafeRawPointer(_channelPointers).assumingMemoryBound(to: UnsafeMutablePointer<Int32>.self)
    }
    /// Float64 channel pointers (Apple exposes these through the buffer list only).
    var _doubleChannelData: UnsafePointer<UnsafeMutablePointer<Double>>? {
        guard _format.commonFormat == .pcmFormatFloat64 else { return nil }
        return UnsafeRawPointer(_channelPointers).assumingMemoryBound(to: UnsafeMutablePointer<Double>.self)
    }

    open override func copy(with zone: NSZone? = nil) -> Any {
        let c = AVAudioPCMBuffer(pcmFormat: _format, frameCapacity: _frameCapacity)!
        c.frameLength = _frameLength
        for b in 0..<_list.count {
            if let s = _list[b].mData, let d = c._list[b].mData { d.copyMemory(from: s, byteCount: Int(_list[b].mDataByteSize)) }
        }
        return c
    }

    open override var description: String {
        "<AVAudioPCMBuffer: \(_format.channelCount) ch, \(Int(_format.sampleRate)) Hz, \(_frameLength)/\(_frameCapacity) frames>"
    }

    /// Reads sample `frame` of `channel` as a Float whatever the common format.
    func _sample(channel: Int, frame: Int) -> Float {
        let i = frame * stride
        switch _format.commonFormat {
        case .pcmFormatFloat32: return floatChannelData![channel][i]
        case .pcmFormatInt16: return Float(int16ChannelData![channel][i]) / 32768
        case .pcmFormatInt32: return Float(Double(int32ChannelData![channel][i]) / 2147483648)
        case .pcmFormatFloat64: return Float(_doubleChannelData![channel][i])
        case .otherFormat: return 0
        }
    }

    /// Converts `frames` frames starting at `frame` of `channel` to Float32 into `out`.
    func _readFloats(channel: Int, frame: Int, count: Int, into out: UnsafeMutablePointer<Float>) {
        let st = stride
        switch _format.commonFormat {
        case .pcmFormatFloat32:
            let p = floatChannelData![channel]
            if st == 1 { out.update(from: p + frame, count: count) } else { for i in 0..<count { out[i] = p[(frame + i) * st] } }
        case .pcmFormatInt16:
            let p = int16ChannelData![channel]
            for i in 0..<count { out[i] = Float(p[(frame + i) * st]) * (1.0 / 32768) }
        case .pcmFormatInt32:
            let p = int32ChannelData![channel]
            for i in 0..<count { out[i] = Float(Double(p[(frame + i) * st]) / 2147483648) }
        case .pcmFormatFloat64:
            let p = _doubleChannelData![channel]
            for i in 0..<count { out[i] = Float(p[(frame + i) * st]) }
        case .otherFormat:
            out.update(repeating: 0, count: count)
        }
    }

    /// Writes Float32 samples into frames starting at `frame` of `channel`, converting to
    /// the buffer's common format (integer formats round and clip).
    func _writeFloats(channel: Int, frame: Int, count: Int, from src: UnsafePointer<Float>) {
        let st = stride
        switch _format.commonFormat {
        case .pcmFormatFloat32:
            let p = floatChannelData![channel]
            if st == 1 { (p + frame).update(from: src, count: count) } else { for i in 0..<count { p[(frame + i) * st] = src[i] } }
        case .pcmFormatInt16:
            let p = int16ChannelData![channel]
            for i in 0..<count { p[(frame + i) * st] = _floatToInt16(src[i]) }
        case .pcmFormatInt32:
            let p = int32ChannelData![channel]
            for i in 0..<count { p[(frame + i) * st] = _floatToInt32(src[i]) }
        case .pcmFormatFloat64:
            let p = _doubleChannelData![channel]
            for i in 0..<count { p[(frame + i) * st] = Double(src[i]) }
        case .otherFormat: break
        }
    }
}

@inline(__always) func _floatToInt16(_ x: Float) -> Int16 {
    let v = (x * 32768).rounded()
    return v >= 32767 ? 32767 : (v <= -32768 ? -32768 : Int16(v))
}
@inline(__always) func _floatToInt32(_ x: Float) -> Int32 {
    let v = (Double(x) * 2147483648).rounded()
    return v >= 2147483647 ? 2147483647 : (v <= -2147483648 ? -2147483648 : Int32(v))
}
