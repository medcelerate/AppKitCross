// AVAudioUnit, AVAudioUnitEffect and AVAudioUnitEQ (a bank of biquad filters per channel).
// Audio Units as a plug-in system do not exist here: the base classes carry the API shape
// and the EQ is a built-in effect.

import Foundation

public struct AudioComponentDescription: Equatable, Sendable {
    public var componentType: UInt32
    public var componentSubType: UInt32
    public var componentManufacturer: UInt32
    public var componentFlags: UInt32
    public var componentFlagsMask: UInt32
    public init() { componentType = 0; componentSubType = 0; componentManufacturer = 0; componentFlags = 0; componentFlagsMask = 0 }
    public init(componentType: UInt32, componentSubType: UInt32, componentManufacturer: UInt32, componentFlags: UInt32, componentFlagsMask: UInt32) {
        self.componentType = componentType; self.componentSubType = componentSubType; self.componentManufacturer = componentManufacturer
        self.componentFlags = componentFlags; self.componentFlagsMask = componentFlagsMask
    }
}

public let kAudioUnitType_Effect: UInt32 = 0x61756678          // 'aufx'
public let kAudioUnitSubType_NBandEQ: UInt32 = 0x6E626571      // 'nbeq'
public let kAudioUnitManufacturer_Apple: UInt32 = 0x6170706C   // 'appl'

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiounit
open class AVAudioUnit: AVAudioNode {
    let _description: AudioComponentDescription
    init(audioComponentDescription: AudioComponentDescription) {
        _description = audioComponentDescription
        super.init()
    }
    open override var numberOfInputs: Int { 1 }
    open var audioComponentDescription: AudioComponentDescription { _description }
    open var name: String { "AVAudioUnit" }
    open var manufacturerName: String { "AppKitWin" }
    open var version: Int { 1 }
    open func loadAudioUnitPreset(at url: URL) throws { throw _osStatusError(-10851, "AVAudioUnit: presets are not supported") }
    override func _defaultOutputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        _inputConnections[0]?.format ?? AVAudioFormat()
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiouniteffect
open class AVAudioUnitEffect: AVAudioUnit {
    let _bypass = _AtomicBool(false)
    public override init(audioComponentDescription: AudioComponentDescription) { super.init(audioComponentDescription: audioComponentDescription) }
    open var bypass: Bool {
        get { _bypass.value }
        set { _bypass.value = newValue }
    }
    /// The render-side processor for a connection of `channels` channels at `rate`.
    func _makeEffectState(channels: Int, rate: Double) -> _EffectState { _PassThroughEffect() }
}

final class _PassThroughEffect: _EffectState {
    func process(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, channels: Int, frames: Int, rate: Double) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiouniteqfiltertype
public enum AVAudioUnitEQFilterType: Int, Sendable {
    case parametric = 0
    case lowPass = 1
    case highPass = 2
    case resonantLowPass = 3
    case resonantHighPass = 4
    case bandPass = 5
    case bandStop = 6
    case lowShelf = 7
    case highShelf = 8
    case resonantLowShelf = 9
    case resonantHighShelf = 10
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiouniteqfilterparameters
open class AVAudioUnitEQFilterParameters: NSObject {
    let _type = _AtomicInt32(0)
    let _frequency = _AtomicFloat(1000)
    let _bandwidth = _AtomicFloat(0.5)
    let _gain = _AtomicFloat(0)
    let _bypass = _AtomicBool(true)
    override init() { super.init() }
    open var filterType: AVAudioUnitEQFilterType {
        get { AVAudioUnitEQFilterType(rawValue: Int(_type.value)) ?? .parametric }
        set { _type.value = Int32(newValue.rawValue) }
    }
    /// Hz, 20 ... (sampleRate / 2).
    open var frequency: Float {
        get { _frequency.value }
        set { _frequency.value = newValue }
    }
    /// Octaves, 0.05 ... 5.
    open var bandwidth: Float {
        get { _bandwidth.value }
        set { _bandwidth.value = newValue }
    }
    /// dB, -96 ... 24.
    open var gain: Float {
        get { _gain.value }
        set { _gain.value = newValue }
    }
    open var bypass: Bool {
        get { _bypass.value }
        set { _bypass.value = newValue }
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiouniteq
open class AVAudioUnitEQ: AVAudioUnitEffect {
    private let _bands: [AVAudioUnitEQFilterParameters]
    let _globalGain = _AtomicFloat(0)

    public init(numberOfBands: Int) {
        _bands = (0..<max(0, numberOfBands)).map { _ in AVAudioUnitEQFilterParameters() }
        super.init(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_NBandEQ, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    }

    open var bands: [AVAudioUnitEQFilterParameters] { _bands }
    /// dB, -96 ... 24.
    open var globalGain: Float {
        get { _globalGain.value }
        set { _globalGain.value = newValue }
    }
    open override var name: String { "AUNBandEQ" }
    open override var manufacturerName: String { "Apple" }

    override func _makeEffectState(channels: Int, rate: Double) -> _EffectState {
        _EQState(eq: self, channels: channels, rate: rate)
    }
}

/// Biquads (RBJ cookbook) per band and channel; coefficients are recomputed on the render
/// thread when a band's parameters change (a few transcendental calls, no allocation).
final class _EQState: _EffectState {
    private let eq: AVAudioUnitEQ
    private let channels: Int
    private let bands: Int
    private struct Coefficients { var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0 }
    private struct Key: Equatable { var type: Int32; var frequency: Float; var bandwidth: Float; var gain: Float }
    private var coefficients: [Coefficients]
    private var keys: [Key]
    /// z1/z2 per (band, channel).
    private let state: UnsafeMutablePointer<Float>

    init(eq: AVAudioUnitEQ, channels: Int, rate: Double) {
        self.eq = eq
        self.channels = channels
        bands = eq.bands.count
        coefficients = Array(repeating: Coefficients(), count: bands)
        keys = Array(repeating: Key(type: -1, frequency: 0, bandwidth: 0, gain: 0), count: bands)
        state = .allocate(capacity: max(1, bands * channels * 2))
        state.initialize(repeating: 0, count: max(1, bands * channels * 2))
    }

    deinit { state.deallocate() }

    private func update(band i: Int, rate: Double) {
        let p = eq.bands[i]
        let key = Key(type: p._type.value, frequency: p._frequency.value, bandwidth: p._bandwidth.value, gain: p._gain.value)
        guard key != keys[i] else { return }
        keys[i] = key
        let f0 = Double(max(10, min(key.frequency, Float(rate / 2 - 1))))
        let w0 = 2 * Double.pi * f0 / rate
        let cw = cos(w0), sw = sin(w0)
        let bw = Double(max(0.05, min(key.bandwidth, 5)))
        let alpha = sw * sinh(log(2) / 2 * bw * w0 / sw)
        let A = pow(10, Double(key.gain) / 40)
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0
        switch AVAudioUnitEQFilterType(rawValue: Int(key.type)) ?? .parametric {
        case .parametric:
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
        case .lowPass, .resonantLowPass:
            b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .highPass, .resonantHighPass:
            b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .bandPass:
            b0 = alpha; b1 = 0; b2 = -alpha
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .bandStop:
            b0 = 1; b1 = -2 * cw; b2 = 1
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .lowShelf, .resonantLowShelf:
            let s = 2 * A.squareRoot() * alpha
            b0 = A * ((A + 1) - (A - 1) * cw + s); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - s)
            a0 = (A + 1) + (A - 1) * cw + s; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - s
        case .highShelf, .resonantHighShelf:
            let s = 2 * A.squareRoot() * alpha
            b0 = A * ((A + 1) + (A - 1) * cw + s); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - s)
            a0 = (A + 1) - (A - 1) * cw + s; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - s
        }
        coefficients[i] = Coefficients(b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0), a1: Float(a1 / a0), a2: Float(a2 / a0))
    }

    func process(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, channels: Int, frames: Int, rate: Double) {
        guard !eq._bypass.value else { return }
        let ch = min(channels, self.channels)
        for i in 0..<bands {
            guard !eq.bands[i]._bypass.value else { continue }
            update(band: i, rate: rate)
            let c = coefficients[i]
            for channel in 0..<ch {
                let s = state + (i * self.channels + channel) * 2
                var z1 = s[0], z2 = s[1]
                let x = planes[channel]
                for n in 0..<frames {
                    let input = x[n]
                    let y = c.b0 * input + z1
                    z1 = c.b1 * input - c.a1 * y + z2
                    z2 = c.b2 * input - c.a2 * y
                    x[n] = y
                }
                s[0] = z1; s[1] = z2
            }
        }
        let g = eq._globalGain.value
        if g != 0 {
            let lin = Float(pow(10, Double(g) / 20))
            for channel in 0..<ch { let x = planes[channel]; for n in 0..<frames { x[n] *= lin } }
        }
    }
}
