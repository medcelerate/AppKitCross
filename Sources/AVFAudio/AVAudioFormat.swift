// AVAudioFormat: an AudioStreamBasicDescription plus an optional channel layout.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioformat
open class AVAudioFormat: NSObject, NSSecureCoding, @unchecked Sendable {
    private let asbd: UnsafeMutablePointer<AudioStreamBasicDescription>
    private let _channelLayout: AVAudioChannelLayout?
    private var _magicCookie: Data?

    private init(asbd desc: AudioStreamBasicDescription, layout: AVAudioChannelLayout?) {
        asbd = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
        asbd.initialize(to: desc)
        _channelLayout = layout
        super.init()
    }

    /// An empty format (0 channels, 0 Hz), which is what unconnected busses report.
    public override convenience init() { self.init(asbd: AudioStreamBasicDescription(), layout: nil) }

    deinit { asbd.deallocate() }

    public convenience init?(streamDescription: UnsafePointer<AudioStreamBasicDescription>) {
        self.init(streamDescription: streamDescription, channelLayout: nil)
    }

    public convenience init?(streamDescription: UnsafePointer<AudioStreamBasicDescription>, channelLayout layout: AVAudioChannelLayout?) {
        let d = streamDescription.pointee
        guard d.mSampleRate > 0, d.mChannelsPerFrame > 0 else { return nil }
        if let layout, layout.channelCount != d.mChannelsPerFrame { return nil }
        self.init(asbd: d, layout: layout)
    }

    /// Float32, non-interleaved, the "standard" format of the engine.
    public convenience init?(standardFormatWithSampleRate sampleRate: Double, channels: AVAudioChannelCount) {
        self.init(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)
    }

    public convenience init(standardFormatWithSampleRate sampleRate: Double, channelLayout layout: AVAudioChannelLayout) {
        self.init(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, interleaved: false, channelLayout: layout)
    }

    /// Nil for more than two channels (those need a channel layout); a zero sample rate or
    /// channel count gives a degenerate format and `.otherFormat` an empty one, as Apple's.
    public convenience init?(commonFormat format: AVAudioCommonFormat, sampleRate: Double, channels: AVAudioChannelCount, interleaved: Bool) {
        guard channels <= 2 else { return nil }
        guard let d = AVAudioFormat._asbd(for: format, sampleRate: sampleRate, channels: channels, interleaved: interleaved) else {
            self.init(asbd: AudioStreamBasicDescription(), layout: nil)
            return
        }
        self.init(asbd: d, layout: nil)
    }

    public convenience init(commonFormat format: AVAudioCommonFormat, sampleRate: Double, interleaved: Bool, channelLayout layout: AVAudioChannelLayout) {
        guard let d = AVAudioFormat._asbd(for: format, sampleRate: sampleRate, channels: layout.channelCount, interleaved: interleaved) else {
            preconditionFailure("AVAudioFormat: invalid common format \(format)")
        }
        self.init(asbd: d, layout: layout)
    }

    /// A linear PCM format from an AVAudioSettings dictionary.
    public convenience init?(settings: [String: Any]) {
        func number(_ key: String) -> Double? {
            if let n = settings[key] as? NSNumber { return n.doubleValue }
            if let d = settings[key] as? Double { return d }
            if let i = settings[key] as? Int { return Double(i) }
            if let f = settings[key] as? Float { return Double(f) }
            if let b = settings[key] as? Bool { return b ? 1 : 0 }
            return nil
        }
        let formatID = number(AVFormatIDKey).map { AudioFormatID($0) } ?? kAudioFormatLinearPCM
        guard formatID == kAudioFormatLinearPCM, let rate = number(AVSampleRateKey), rate > 0 else { return nil }
        // Apple's defaults: one channel, 16-bit integer.
        let channels = AVAudioChannelCount(number(AVNumberOfChannelsKey) ?? 1)
        guard channels > 0 else { return nil }
        var layout: AVAudioChannelLayout? = settings[AVChannelLayoutKey] as? AVAudioChannelLayout
        if layout == nil, let data = settings[AVChannelLayoutKey] as? Data, data.count >= MemoryLayout<AudioChannelLayout>.size {
            layout = data.withUnsafeBytes { AVAudioChannelLayout(layout: $0.baseAddress!.assumingMemoryBound(to: AudioChannelLayout.self)) }
        }
        if channels > 2 && layout == nil { return nil }
        if let layout, layout.channelCount != channels { return nil }
        let isFloat = (number(AVLinearPCMIsFloatKey) ?? 0) != 0
        let bits = Int(number(AVLinearPCMBitDepthKey) ?? 16)
        guard bits >= 8, bits <= 64 else { return nil }
        if isFloat && bits != 32 && bits != 64 { return nil }
        let bigEndian = (number(AVLinearPCMIsBigEndianKey) ?? 0) != 0
        let nonInterleaved = (number(AVLinearPCMIsNonInterleaved) ?? 0) != 0
        var d = AudioStreamBasicDescription()
        d.mSampleRate = rate
        d.mFormatID = kAudioFormatLinearPCM
        d.mFormatFlags = (isFloat ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger) | kAudioFormatFlagIsPacked
        if bigEndian { d.mFormatFlags |= kAudioFormatFlagIsBigEndian }
        if nonInterleaved { d.mFormatFlags |= kAudioFormatFlagIsNonInterleaved }
        d.mBitsPerChannel = UInt32(bits)
        d.mChannelsPerFrame = channels
        d.mFramesPerPacket = 1
        let bytesPerSample = UInt32((bits + 7) / 8)
        d.mBytesPerFrame = nonInterleaved ? bytesPerSample : bytesPerSample * channels
        d.mBytesPerPacket = d.mBytesPerFrame
        self.init(asbd: d, layout: layout ?? (channels > 2 ? AVAudioChannelLayout._standard(channels: channels) : nil))
    }

    static func _asbd(for format: AVAudioCommonFormat, sampleRate: Double, channels: AVAudioChannelCount, interleaved: Bool) -> AudioStreamBasicDescription? {
        var d = AudioStreamBasicDescription()
        d.mSampleRate = sampleRate
        d.mFormatID = kAudioFormatLinearPCM
        d.mChannelsPerFrame = channels
        d.mFramesPerPacket = 1
        let bytes: UInt32
        switch format {
        case .pcmFormatFloat32: d.mFormatFlags = kAudioFormatFlagsNativeFloatPacked; bytes = 4
        case .pcmFormatFloat64: d.mFormatFlags = kAudioFormatFlagsNativeFloatPacked; bytes = 8
        case .pcmFormatInt16: d.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked; bytes = 2
        case .pcmFormatInt32: d.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked; bytes = 4
        case .otherFormat: return nil
        }
        if !interleaved { d.mFormatFlags |= kAudioFormatFlagIsNonInterleaved }
        d.mBitsPerChannel = bytes * 8
        d.mBytesPerFrame = interleaved ? bytes * channels : bytes
        d.mBytesPerPacket = d.mBytesPerFrame
        return d
    }

    open var isStandard: Bool { commonFormat == .pcmFormatFloat32 && !isInterleaved }

    open var commonFormat: AVAudioCommonFormat {
        let d = asbd.pointee
        guard d.mFormatID == kAudioFormatLinearPCM, d.mFormatFlags & kAudioFormatFlagIsBigEndian == 0, d.mFormatFlags & kAudioFormatFlagIsPacked != 0 else { return .otherFormat }
        let isFloat = d.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let signed = d.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        switch (isFloat, signed, d.mBitsPerChannel) {
        case (true, _, 32): return .pcmFormatFloat32
        case (true, _, 64): return .pcmFormatFloat64
        case (false, true, 16): return .pcmFormatInt16
        case (false, true, 32): return .pcmFormatInt32
        default: return .otherFormat
        }
    }

    open var channelCount: AVAudioChannelCount { asbd.pointee.mChannelsPerFrame }
    open var sampleRate: Double { asbd.pointee.mSampleRate }
    open var isInterleaved: Bool { asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 }
    open var streamDescription: UnsafePointer<AudioStreamBasicDescription> { UnsafePointer(asbd) }
    open var channelLayout: AVAudioChannelLayout? { _channelLayout }
    open var magicCookie: Data? {
        get { _magicCookie }
        set { _magicCookie = newValue }
    }

    open var settings: [String: Any] {
        let d = asbd.pointee
        var s: [String: Any] = [
            AVFormatIDKey: Int(d.mFormatID),
            AVSampleRateKey: d.mSampleRate,
            AVNumberOfChannelsKey: Int(d.mChannelsPerFrame),
        ]
        if d.mFormatID == kAudioFormatLinearPCM {
            s[AVLinearPCMBitDepthKey] = Int(d.mBitsPerChannel)
            s[AVLinearPCMIsFloatKey] = d.mFormatFlags & kAudioFormatFlagIsFloat != 0
            s[AVLinearPCMIsBigEndianKey] = d.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
            s[AVLinearPCMIsNonInterleaved] = d.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        }
        if let l = _channelLayout { s[AVChannelLayoutKey] = l }
        return s
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AVAudioFormat else { return false }
        if other === self { return true }
        guard asbd.pointee == other.asbd.pointee else { return false }
        switch (_channelLayout, other._channelLayout) {
        case (nil, nil): return true
        case let (a?, b?): return a.isEqual(b)
        default: return false
        }
    }
    open override var hash: Int {
        let d = asbd.pointee
        return Int(d.mSampleRate) ^ Int(d.mChannelsPerFrame) << 8 ^ Int(d.mFormatFlags) << 16 ^ Int(d.mBitsPerChannel) << 24
    }

    open override var description: String {
        let d = asbd.pointee
        if d.mChannelsPerFrame == 0 && d.mSampleRate == 0 && d.mFormatID == 0 {
            return "<AVAudioFormat 0x\(String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)):  0 ch,      0 Hz>"
        }
        let kind: String
        switch commonFormat {
        case .pcmFormatFloat32: kind = "Float32"
        case .pcmFormatFloat64: kind = "Float64"
        case .pcmFormatInt16: kind = "Int16"
        case .pcmFormatInt32: kind = "Int32"
        case .otherFormat: kind = d.mFormatID == kAudioFormatLinearPCM ? "\(d.mBitsPerChannel)-bit \(d.mFormatFlags & kAudioFormatFlagIsFloat != 0 ? "float" : "int")" : "'\(_fourCCString(d.mFormatID))'"
        }
        let addr = String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)
        return "<AVAudioFormat 0x\(addr):  \(d.mChannelsPerFrame) ch,  \(Int(d.mSampleRate)) Hz, \(kind), \(isInterleaved ? "interleaved" : "deinterleaved")>"
    }

    /// Bytes per sample of one channel (0 for non-PCM).
    var _bytesPerSample: Int { Int((asbd.pointee.mBitsPerChannel + 7) / 8) }
    /// Number of `AudioBuffer`s a PCM buffer of this format has.
    var _bufferCount: Int { isInterleaved ? 1 : Int(channelCount) }

    // NSSecureCoding
    public class var supportsSecureCoding: Bool { true }
    public required init?(coder: NSCoder) {
        var d = AudioStreamBasicDescription()
        d.mSampleRate = coder.decodeDouble(forKey: "sampleRate")
        d.mFormatID = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "formatID"))
        d.mFormatFlags = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "formatFlags"))
        d.mBytesPerPacket = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "bytesPerPacket"))
        d.mFramesPerPacket = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "framesPerPacket"))
        d.mBytesPerFrame = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "bytesPerFrame"))
        d.mChannelsPerFrame = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "channelsPerFrame"))
        d.mBitsPerChannel = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "bitsPerChannel"))
        asbd = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
        asbd.initialize(to: d)
        _channelLayout = coder.decodeObject(of: AVAudioChannelLayout.self, forKey: "channelLayout")
        super.init()
    }
    open func encode(with coder: NSCoder) {
        let d = asbd.pointee
        coder.encode(d.mSampleRate, forKey: "sampleRate")
        coder.encode(Int64(d.mFormatID), forKey: "formatID")
        coder.encode(Int64(d.mFormatFlags), forKey: "formatFlags")
        coder.encode(Int64(d.mBytesPerPacket), forKey: "bytesPerPacket")
        coder.encode(Int64(d.mFramesPerPacket), forKey: "framesPerPacket")
        coder.encode(Int64(d.mBytesPerFrame), forKey: "bytesPerFrame")
        coder.encode(Int64(d.mChannelsPerFrame), forKey: "channelsPerFrame")
        coder.encode(Int64(d.mBitsPerChannel), forKey: "bitsPerChannel")
        if let l = _channelLayout { coder.encode(l, forKey: "channelLayout") }
    }
}

func _fourCCString(_ v: UInt32) -> String {
    let bytes = [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    return String(decoding: bytes, as: UTF8.self)
}
