// AVAudioUnitTimeEffect, AVAudioUnitTimePitch and AVAudioUnitVarispeed: units that consume
// input at a different rate from the output they produce. The render graph pulls their
// input on demand (see `_TimeEffectState` in Internal/TimeStretch.swift).

import Foundation

public let kAudioUnitType_FormatConverter: UInt32 = 0x61756663   // 'aufc'
public let kAudioUnitSubType_NewTimePitch: UInt32 = 0x6E757470   // 'nutp'
public let kAudioUnitSubType_Varispeed: UInt32 = 0x76617269      // 'vari'

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiouniteffect
open class AVAudioUnitTimeEffect: AVAudioUnit {
    let _bypass = _AtomicBool(false)

    public override init(audioComponentDescription: AudioComponentDescription) {
        super.init(audioComponentDescription: audioComponentDescription)
    }

    open var bypass: Bool {
        get { _bypass.value }
        set { _bypass.value = newValue }
    }

    /// The render-side processor for a connection of `channels` channels at `rate`.
    func _makeTimeEffectState(channels: Int, rate: Double, maxFrames: Int) -> _TimeEffectState {
        _PassThroughTimeEffect()
    }
}

/// A time effect with no processing of its own (an unknown component description).
final class _PassThroughTimeEffect: _TimeEffectState {
    var inputSampleTime: Int64 = 0
    var isBypassed: Bool { true }
    func inputFramesWanted(forOutput frames: Int) -> Int { 0 }
    func push(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {}
    func produce(_ out: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiounittimepitch
open class AVAudioUnitTimePitch: AVAudioUnitTimeEffect {
    let _rate = _AtomicFloat(1)
    let _pitch = _AtomicFloat(0)
    let _overlap = _AtomicFloat(8)

    public convenience init() {
        self.init(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_FormatConverter, componentSubType: kAudioUnitSubType_NewTimePitch, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    }

    public override init(audioComponentDescription: AudioComponentDescription) {
        super.init(audioComponentDescription: audioComponentDescription)
    }

    open override var name: String { "AUNewTimePitch" }

    /// Playback rate, 1/32 to 32 (values outside are clamped, as Apple's parameter is).
    open var rate: Float {
        get { _rate.value }
        set { _rate.value = max(1.0 / 32, min(32, newValue)) }
    }

    /// Pitch shift in cents, -2400 to 2400.
    open var pitch: Float {
        get { _pitch.value }
        set { _pitch.value = max(-2400, min(2400, newValue)) }
    }

    /// Overlap of the analysis frames, 3 to 32 (more overlap: fewer artefacts, more CPU).
    /// Takes effect at the next graph build, which setting it schedules.
    open var overlap: Float {
        get { _overlap.value }
        set {
            _overlap.value = max(3, min(32, newValue))
            if let engine = _engine { engine._lock.lock(); engine._graphChanged(); engine._lock.unlock() }
        }
    }

    override func _makeTimeEffectState(channels: Int, rate: Double, maxFrames: Int) -> _TimeEffectState {
        _TimePitchState(unit: self, channels: channels, rate: rate, maxFrames: maxFrames)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiounitvarispeed
open class AVAudioUnitVarispeed: AVAudioUnitTimeEffect {
    let _rate = _AtomicFloat(1)

    public convenience init() {
        self.init(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_FormatConverter, componentSubType: kAudioUnitSubType_Varispeed, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    }

    public override init(audioComponentDescription: AudioComponentDescription) {
        super.init(audioComponentDescription: audioComponentDescription)
    }

    open override var name: String { "AUVarispeed" }

    /// Playback rate, 0.25 to 4; the pitch follows (2 is an octave up).
    open var rate: Float {
        get { _rate.value }
        set { _rate.value = max(0.25, min(4, newValue)) }
    }

    override func _makeTimeEffectState(channels: Int, rate: Double, maxFrames: Int) -> _TimeEffectState {
        _VarispeedState(unit: self, channels: channels, maxFrames: maxFrames)
    }
}
