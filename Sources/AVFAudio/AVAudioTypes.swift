// AVFAudio's scalar types, the settings keys of AVAudioSettings.h and the small value
// types (AVAudio3DPoint and friends).

import Foundation

public typealias AVAudioFramePosition = Int64
public typealias AVAudioFrameCount = UInt32
public typealias AVAudioPacketCount = UInt32
public typealias AVAudioChannelCount = UInt32
public typealias AVAudioNodeBus = Int
public typealias AVMusicTimeStamp = Double
public typealias AVAudioNodeCompletionHandler = () -> Void

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiocommonformat
public enum AVAudioCommonFormat: UInt, Sendable {
    case otherFormat = 0
    case pcmFormatFloat32 = 1
    case pcmFormatFloat64 = 2
    case pcmFormatInt16 = 3
    case pcmFormatInt32 = 4
}

public struct AVAudio3DPoint: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public init() { x = 0; y = 0; z = 0 }
    public init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
}
public typealias AVAudio3DVector = AVAudio3DPoint
public func AVAudioMake3DPoint(_ x: Float, _ y: Float, _ z: Float) -> AVAudio3DPoint { AVAudio3DPoint(x: x, y: y, z: z) }
public func AVAudioMake3DVector(_ x: Float, _ y: Float, _ z: Float) -> AVAudio3DVector { AVAudio3DPoint(x: x, y: y, z: z) }

public struct AVAudio3DVectorOrientation: Equatable, Sendable {
    public var forward: AVAudio3DVector
    public var up: AVAudio3DVector
    public init() { forward = AVAudio3DVector(); up = AVAudio3DVector() }
    public init(forward: AVAudio3DVector, up: AVAudio3DVector) { self.forward = forward; self.up = up }
}
public func AVAudioMake3DVectorOrientation(_ forward: AVAudio3DVector, _ up: AVAudio3DVector) -> AVAudio3DVectorOrientation {
    AVAudio3DVectorOrientation(forward: forward, up: up)
}

public struct AVAudio3DAngularOrientation: Equatable, Sendable {
    public var yaw: Float
    public var pitch: Float
    public var roll: Float
    public init() { yaw = 0; pitch = 0; roll = 0 }
    public init(yaw: Float, pitch: Float, roll: Float) { self.yaw = yaw; self.pitch = pitch; self.roll = roll }
}
public func AVAudioMake3DAngularOrientation(_ yaw: Float, _ pitch: Float, _ roll: Float) -> AVAudio3DAngularOrientation {
    AVAudio3DAngularOrientation(yaw: yaw, pitch: pitch, roll: roll)
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioquality
public enum AVAudioQuality: Int, Sendable {
    case min = 0
    case low = 0x20
    case medium = 0x40
    case high = 0x60
    case max = 0x7F
}

// AVAudioSettings.h. The values are the key names, as in Apple's SDK.
public let AVFormatIDKey = "AVFormatIDKey"
public let AVSampleRateKey = "AVSampleRateKey"
public let AVNumberOfChannelsKey = "AVNumberOfChannelsKey"
public let AVLinearPCMBitDepthKey = "AVLinearPCMBitDepthKey"
public let AVLinearPCMIsBigEndianKey = "AVLinearPCMIsBigEndianKey"
public let AVLinearPCMIsFloatKey = "AVLinearPCMIsFloatKey"
public let AVLinearPCMIsNonInterleaved = "AVLinearPCMIsNonInterleaved"
public let AVAudioFileTypeKey = "AVAudioFileTypeKey"
public let AVEncoderAudioQualityKey = "AVEncoderAudioQualityKey"
public let AVEncoderAudioQualityForVBRKey = "AVEncoderAudioQualityForVBRKey"
public let AVEncoderBitRateKey = "AVEncoderBitRateKey"
public let AVEncoderBitRatePerChannelKey = "AVEncoderBitRatePerChannelKey"
public let AVEncoderBitRateStrategyKey = "AVEncoderBitRateStrategyKey"
public let AVEncoderBitDepthHintKey = "AVEncoderBitDepthHintKey"
public let AVSampleRateConverterAlgorithmKey = "AVSampleRateConverterAlgorithmKey"
public let AVSampleRateConverterAudioQualityKey = "AVSampleRateConverterAudioQualityKey"
public let AVChannelLayoutKey = "AVChannelLayoutKey"
