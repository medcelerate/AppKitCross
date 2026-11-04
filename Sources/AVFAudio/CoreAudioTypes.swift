// The CoreAudioTypes structures and constants AVFAudio's API is expressed in
// (AudioStreamBasicDescription, AudioBufferList, AudioTimeStamp, AudioChannelLayout).
// Names, layouts and values are Apple's; on macOS Apple's own CoreAudioTypes is the
// reference these are checked against.

import Foundation

#if !canImport(Darwin)
public typealias OSStatus = Int32
#endif

public typealias AudioFormatID = UInt32
public typealias AudioFormatFlags = UInt32
public typealias AudioChannelLayoutTag = UInt32
public typealias AudioChannelLabel = UInt32
public typealias AudioChannelBitmap = UInt32
public typealias AudioFileTypeID = UInt32

/// Four-character code helper (`'lpcm'`).
@inline(__always) func _fourCC(_ s: StaticString) -> UInt32 {
    var v: UInt32 = 0
    s.withUTF8Buffer { for b in $0 { v = (v << 8) | UInt32(b) } }
    return v
}

public let kAudioFormatLinearPCM: AudioFormatID = 0x6C70636D   // 'lpcm'

public let kAudioFormatFlagIsFloat: AudioFormatFlags = 1 << 0
public let kAudioFormatFlagIsBigEndian: AudioFormatFlags = 1 << 1
public let kAudioFormatFlagIsSignedInteger: AudioFormatFlags = 1 << 2
public let kAudioFormatFlagIsPacked: AudioFormatFlags = 1 << 3
public let kAudioFormatFlagIsAlignedHigh: AudioFormatFlags = 1 << 4
public let kAudioFormatFlagIsNonInterleaved: AudioFormatFlags = 1 << 5
public let kAudioFormatFlagIsNonMixable: AudioFormatFlags = 1 << 6
public let kAudioFormatFlagsAreAllClear: AudioFormatFlags = 0x80000000
public let kAudioFormatFlagsNativeEndian: AudioFormatFlags = 0
public let kAudioFormatFlagsNativeFloatPacked: AudioFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
public let kAudioFormatFlagsCanonical: AudioFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
public let kLinearPCMFormatFlagIsFloat = kAudioFormatFlagIsFloat
public let kLinearPCMFormatFlagIsBigEndian = kAudioFormatFlagIsBigEndian
public let kLinearPCMFormatFlagIsSignedInteger = kAudioFormatFlagIsSignedInteger
public let kLinearPCMFormatFlagIsPacked = kAudioFormatFlagIsPacked
public let kLinearPCMFormatFlagIsNonInterleaved = kAudioFormatFlagIsNonInterleaved

public let kAudioFileWAVEType: AudioFileTypeID = 0x57415645   // 'WAVE'
public let kAudioFileAIFFType: AudioFileTypeID = 0x41494646   // 'AIFF'
public let kAudioFileAIFCType: AudioFileTypeID = 0x41494643   // 'AIFC'
public let kAudioFileCAFType: AudioFileTypeID = 0x63616666    // 'caff'

// AudioFile.h result codes (the OSStatus values AVAudioFile throws in NSOSStatusErrorDomain).
public let kAudioFileUnspecifiedError: OSStatus = 0x7768743F          // 'wht?'
public let kAudioFileUnsupportedFileTypeError: OSStatus = 0x7479703F  // 'typ?'
public let kAudioFileUnsupportedDataFormatError: OSStatus = 0x666D743F // 'fmt?'
public let kAudioFileUnsupportedPropertyError: OSStatus = 0x7074793F  // 'pty?'
public let kAudioFileBadPropertySizeError: OSStatus = 0x2173697A      // '!siz'
public let kAudioFilePermissionsError: OSStatus = 0x70726D3F          // 'prm?'
public let kAudioFileNotOptimizedError: OSStatus = 0x6F70746D         // 'optm'
public let kAudioFileInvalidChunkError: OSStatus = 0x63686B3F         // 'chk?'
public let kAudioFileDoesNotAllow64BitDataSizeError: OSStatus = 0x6F66663F // 'off?'
public let kAudioFileInvalidPacketOffsetError: OSStatus = 0x70636B3F  // 'pck?'
public let kAudioFileInvalidFileError: OSStatus = 0x6474613F          // 'dta?'
public let kAudioFileOperationNotSupportedError: OSStatus = 0x6F703F3F // 'op??'
public let kAudioFileNotOpenError: OSStatus = -38
public let kAudioFileEndOfFileError: OSStatus = -39
public let kAudioFilePositionError: OSStatus = -40
public let kAudioFileFileNotFoundError: OSStatus = -43

/// The description of a linear PCM (or other) audio stream, as CoreAudio lays it out.
public struct AudioStreamBasicDescription: Equatable {
    public var mSampleRate: Float64
    public var mFormatID: AudioFormatID
    public var mFormatFlags: AudioFormatFlags
    public var mBytesPerPacket: UInt32
    public var mFramesPerPacket: UInt32
    public var mBytesPerFrame: UInt32
    public var mChannelsPerFrame: UInt32
    public var mBitsPerChannel: UInt32
    public var mReserved: UInt32
    public init() {
        mSampleRate = 0; mFormatID = 0; mFormatFlags = 0; mBytesPerPacket = 0; mFramesPerPacket = 0
        mBytesPerFrame = 0; mChannelsPerFrame = 0; mBitsPerChannel = 0; mReserved = 0
    }
    public init(mSampleRate: Float64, mFormatID: AudioFormatID, mFormatFlags: AudioFormatFlags, mBytesPerPacket: UInt32, mFramesPerPacket: UInt32, mBytesPerFrame: UInt32, mChannelsPerFrame: UInt32, mBitsPerChannel: UInt32, mReserved: UInt32) {
        self.mSampleRate = mSampleRate; self.mFormatID = mFormatID; self.mFormatFlags = mFormatFlags
        self.mBytesPerPacket = mBytesPerPacket; self.mFramesPerPacket = mFramesPerPacket; self.mBytesPerFrame = mBytesPerFrame
        self.mChannelsPerFrame = mChannelsPerFrame; self.mBitsPerChannel = mBitsPerChannel; self.mReserved = mReserved
    }
}

/// One buffer of an `AudioBufferList`: interleaved data for `mNumberChannels` channels.
public struct AudioBuffer {
    public var mNumberChannels: UInt32
    public var mDataByteSize: UInt32
    public var mData: UnsafeMutableRawPointer?
    public init() { mNumberChannels = 0; mDataByteSize = 0; mData = nil }
    public init(mNumberChannels: UInt32, mDataByteSize: UInt32, mData: UnsafeMutableRawPointer?) {
        self.mNumberChannels = mNumberChannels; self.mDataByteSize = mDataByteSize; self.mData = mData
    }
}

/// A variable-length list of buffers: `mBuffers` is the first of `mNumberBuffers` laid out
/// contiguously. Use `UnsafeMutableAudioBufferListPointer` to index them.
public struct AudioBufferList {
    public var mNumberBuffers: UInt32
    public var mBuffers: AudioBuffer
    public init() { mNumberBuffers = 0; mBuffers = AudioBuffer() }
    public init(mNumberBuffers: UInt32, mBuffers: AudioBuffer) { self.mNumberBuffers = mNumberBuffers; self.mBuffers = mBuffers }
    /// Bytes needed for a list of `maximumBuffers` buffers.
    public static func sizeInBytes(maximumBuffers: Int) -> Int {
        MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)! + max(1, maximumBuffers) * MemoryLayout<AudioBuffer>.stride
    }
    /// Allocates a zeroed list with room for `maximumBuffers` buffers; the caller frees it.
    public static func allocate(maximumBuffers: Int) -> UnsafeMutableAudioBufferListPointer {
        let bytes = sizeInBytes(maximumBuffers: maximumBuffers)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: MemoryLayout<AudioBufferList>.alignment)
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
        let p = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        p.pointee.mNumberBuffers = UInt32(maximumBuffers)
        return UnsafeMutableAudioBufferListPointer(p)
    }
}

/// Indexed access to the buffers of an `AudioBufferList` (the CoreAudio overlay type).
public struct UnsafeMutableAudioBufferListPointer {
    public let unsafeMutablePointer: UnsafeMutablePointer<AudioBufferList>
    public init(_ p: UnsafeMutablePointer<AudioBufferList>) { unsafeMutablePointer = p }
    public init?(_ p: UnsafeMutablePointer<AudioBufferList>?) { guard let p else { return nil }; unsafeMutablePointer = p }
    public var unsafePointer: UnsafePointer<AudioBufferList> { UnsafePointer(unsafeMutablePointer) }
    public var count: Int {
        get { Int(unsafeMutablePointer.pointee.mNumberBuffers) }
        nonmutating set { unsafeMutablePointer.pointee.mNumberBuffers = UInt32(newValue) }
    }
    private var buffersPointer: UnsafeMutablePointer<AudioBuffer> {
        UnsafeMutableRawPointer(unsafeMutablePointer).advanced(by: MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)!)
            .assumingMemoryBound(to: AudioBuffer.self)
    }
    public subscript(index: Int) -> AudioBuffer {
        get { precondition(index >= 0 && index < count, "AudioBufferList index out of range"); return buffersPointer[index] }
        nonmutating set { precondition(index >= 0 && index < count, "AudioBufferList index out of range"); buffersPointer[index] = newValue }
    }
}

extension UnsafeMutableAudioBufferListPointer: MutableCollection, RandomAccessCollection {
    public var startIndex: Int { 0 }
    public var endIndex: Int { count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }
}

public struct SMPTETime: Equatable {
    public var mSubframes: Int16 = 0
    public var mSubframeDivisor: Int16 = 0
    public var mCounter: UInt32 = 0
    public var mType: UInt32 = 0
    public var mFlags: UInt32 = 0
    public var mHours: Int16 = 0
    public var mMinutes: Int16 = 0
    public var mSeconds: Int16 = 0
    public var mFrames: Int16 = 0
    public init() {}
}

public struct AudioTimeStampFlags: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let sampleTimeValid = AudioTimeStampFlags(rawValue: 1 << 0)
    public static let hostTimeValid = AudioTimeStampFlags(rawValue: 1 << 1)
    public static let rateScalarValid = AudioTimeStampFlags(rawValue: 1 << 2)
    public static let wordClockTimeValid = AudioTimeStampFlags(rawValue: 1 << 3)
    public static let smpteTimeValid = AudioTimeStampFlags(rawValue: 1 << 4)
    public static let sampleHostTimeValid: AudioTimeStampFlags = [.sampleTimeValid, .hostTimeValid]
}

public struct AudioTimeStamp {
    public var mSampleTime: Float64 = 0
    public var mHostTime: UInt64 = 0
    public var mRateScalar: Float64 = 0
    public var mWordClockTime: UInt64 = 0
    public var mSMPTETime = SMPTETime()
    public var mFlags = AudioTimeStampFlags()
    public var mReserved: UInt32 = 0
    public init() {}
    public init(mSampleTime: Float64, mHostTime: UInt64, mRateScalar: Float64, mWordClockTime: UInt64, mSMPTETime: SMPTETime, mFlags: AudioTimeStampFlags, mReserved: UInt32) {
        self.mSampleTime = mSampleTime; self.mHostTime = mHostTime; self.mRateScalar = mRateScalar
        self.mWordClockTime = mWordClockTime; self.mSMPTETime = mSMPTETime; self.mFlags = mFlags; self.mReserved = mReserved
    }
}

public struct AudioChannelDescription: Equatable {
    public var mChannelLabel: AudioChannelLabel = 0
    public var mChannelFlags: UInt32 = 0
    public var mCoordinates: (Float32, Float32, Float32) = (0, 0, 0)
    public init() {}
    public static func == (a: AudioChannelDescription, b: AudioChannelDescription) -> Bool {
        a.mChannelLabel == b.mChannelLabel && a.mChannelFlags == b.mChannelFlags && a.mCoordinates == b.mCoordinates
    }
}

/// A channel layout: a tag, or a bitmap, or `mNumberChannelDescriptions` descriptions
/// laid out after `mChannelDescriptions`.
public struct AudioChannelLayout {
    public var mChannelLayoutTag: AudioChannelLayoutTag = 0
    public var mChannelBitmap: AudioChannelBitmap = 0
    public var mNumberChannelDescriptions: UInt32 = 0
    public var mChannelDescriptions = AudioChannelDescription()
    public init() {}
}

public let kAudioChannelLayoutTag_UseChannelDescriptions: AudioChannelLayoutTag = (0 << 16) | 0
public let kAudioChannelLayoutTag_UseChannelBitmap: AudioChannelLayoutTag = (1 << 16) | 0
public let kAudioChannelLayoutTag_Mono: AudioChannelLayoutTag = (100 << 16) | 1
public let kAudioChannelLayoutTag_Stereo: AudioChannelLayoutTag = (101 << 16) | 2
public let kAudioChannelLayoutTag_StereoHeadphones: AudioChannelLayoutTag = (102 << 16) | 2
public let kAudioChannelLayoutTag_Quadraphonic: AudioChannelLayoutTag = (108 << 16) | 4
public let kAudioChannelLayoutTag_MPEG_5_1_A: AudioChannelLayoutTag = (121 << 16) | 6
public let kAudioChannelLayoutTag_MPEG_7_1_A: AudioChannelLayoutTag = (126 << 16) | 8
public let kAudioChannelLayoutTag_DiscreteInOrder: AudioChannelLayoutTag = (147 << 16) | 0
public let kAudioChannelLayoutTag_Unknown: AudioChannelLayoutTag = 0xFFFF0000

public let kAudioChannelLabel_Unknown: AudioChannelLabel = 0xFFFFFFFF
public let kAudioChannelLabel_Unused: AudioChannelLabel = 0
public let kAudioChannelLabel_Mono: AudioChannelLabel = 42
public let kAudioChannelLabel_Left: AudioChannelLabel = 1
public let kAudioChannelLabel_Right: AudioChannelLabel = 2

@inline(__always) public func AudioChannelLayoutTag_GetNumberOfChannels(_ tag: AudioChannelLayoutTag) -> UInt32 { tag & 0xFFFF }

/// The domain Apple's AVFAudio classes throw in, with AudioFile.h / AudioUnit status codes.
public let _AVFAudioErrorDomain = "com.apple.coreaudio.avfaudio"
let _osStatusErrorDomain = _AVFAudioErrorDomain

func _osStatusError(_ status: OSStatus, _ description: String? = nil) -> NSError {
    var info: [String: Any] = [:]
    if let description { info[NSLocalizedDescriptionKey] = description }
    return NSError(domain: _osStatusErrorDomain, code: Int(status), userInfo: info)
}
