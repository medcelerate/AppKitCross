// AVAudioTime: a point in time as a host time, a sample time at a rate, or both.
//
// Host time is the platform's monotonic clock in nanoseconds (mach_absolute_time's unit
// on Apple platforms; QueryPerformanceCounter and CLOCK_MONOTONIC here, scaled).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiotime
open class AVAudioTime: NSObject, @unchecked Sendable {
    private let _hostTime: UInt64
    private let _hostTimeValid: Bool
    private let _sampleTime: AVAudioFramePosition
    private let _sampleTimeValid: Bool
    private let _sampleRate: Double

    public init(audioTimeStamp ts: UnsafePointer<AudioTimeStamp>, sampleRate: Double) {
        let t = ts.pointee
        _hostTimeValid = t.mFlags.contains(.hostTimeValid)
        _hostTime = _hostTimeValid ? t.mHostTime : 0
        _sampleTimeValid = t.mFlags.contains(.sampleTimeValid)
        _sampleTime = _sampleTimeValid ? AVAudioFramePosition(t.mSampleTime) : 0
        _sampleRate = sampleRate
    }
    public init(hostTime: UInt64) {
        _hostTime = hostTime; _hostTimeValid = true; _sampleTime = 0; _sampleTimeValid = false; _sampleRate = 0
    }
    public init(sampleTime: AVAudioFramePosition, atRate sampleRate: Double) {
        _hostTime = 0; _hostTimeValid = false; _sampleTime = sampleTime; _sampleTimeValid = true; _sampleRate = sampleRate
    }
    public init(hostTime: UInt64, sampleTime: AVAudioFramePosition, atRate sampleRate: Double) {
        _hostTime = hostTime; _hostTimeValid = true; _sampleTime = sampleTime; _sampleTimeValid = true; _sampleRate = sampleRate
    }

    public class func hostTime(forSeconds seconds: TimeInterval) -> UInt64 { UInt64(max(0, seconds) * 1_000_000_000) }
    public class func seconds(forHostTime hostTime: UInt64) -> TimeInterval { Double(hostTime) / 1_000_000_000 }

    open var isHostTimeValid: Bool { _hostTimeValid }
    open var hostTime: UInt64 { _hostTime }
    open var isSampleTimeValid: Bool { _sampleTimeValid }
    open var sampleTime: AVAudioFramePosition { _sampleTime }
    open var sampleRate: Double { _sampleRate }

    open var audioTimeStamp: AudioTimeStamp {
        var t = AudioTimeStamp()
        if _hostTimeValid { t.mHostTime = _hostTime; t.mFlags.insert(.hostTimeValid) }
        if _sampleTimeValid { t.mSampleTime = Double(_sampleTime); t.mFlags.insert(.sampleTimeValid) }
        return t
    }

    /// Adds a host time to a sample-only time from an anchor that has both, assuming a
    /// steady rate. Returns self when both halves are set already; nil when the anchor
    /// lacks a half, the rates differ, or the receiver has only a host time (Apple's
    /// implementation extrapolates in that one direction only).
    open func extrapolateTime(fromAnchor anchorTime: AVAudioTime) -> AVAudioTime? {
        guard anchorTime.isHostTimeValid, anchorTime.isSampleTimeValid else { return nil }
        if _hostTimeValid && _sampleTimeValid { return AVAudioTime(hostTime: _hostTime, sampleTime: _sampleTime, atRate: _sampleRate) }
        guard _sampleTimeValid, anchorTime.sampleRate == _sampleRate, _sampleRate > 0 else { return nil }
        let seconds = Double(_sampleTime - anchorTime.sampleTime) / _sampleRate
        let host = Int64(anchorTime.hostTime) + Int64(seconds * 1_000_000_000)
        return AVAudioTime(hostTime: UInt64(max(0, host)), sampleTime: _sampleTime, atRate: _sampleRate)
    }

    /// The sample time at `anchor`'s rate that this host time corresponds to (for
    /// `AVAudioPlayerNode.play(at:)` with a host-only time).
    func _sampleTime(fromAnchor anchor: AVAudioTime) -> AVAudioFramePosition? {
        guard _hostTimeValid, anchor.isHostTimeValid, anchor.isSampleTimeValid, anchor.sampleRate > 0 else { return nil }
        let seconds = (Double(_hostTime) - Double(anchor.hostTime)) / 1_000_000_000
        return anchor.sampleTime + AVAudioFramePosition((seconds * anchor.sampleRate).rounded())
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? AVAudioTime else { return false }
        return _hostTimeValid == o._hostTimeValid && _hostTime == o._hostTime && _sampleTimeValid == o._sampleTimeValid
            && _sampleTime == o._sampleTime && _sampleRate == o._sampleRate
    }
    open override var hash: Int { Int(truncatingIfNeeded: _hostTime) ^ Int(truncatingIfNeeded: _sampleTime) }

    open override var description: String {
        var s = "<AVAudioTime 0x\(String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)): "
        if _hostTimeValid { s += String(format: "%.6f s ", AVAudioTime.seconds(forHostTime: _hostTime)) }
        if _sampleTimeValid { s += " \(_sampleTime) fr (/\(Int(_sampleRate)) Hz) " }
        return s + ">"
    }
}

/// The current host time (monotonic nanoseconds).
func _currentHostTime() -> UInt64 {
    UInt64(max(0, ProcessInfo.processInfo.systemUptime) * 1_000_000_000)
}
