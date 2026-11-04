// AVAudioMixerNode: sums its input busses (with each source's volume and pan) into one
// output, converting sample rate and channel count on the way.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiomixernode
open class AVAudioMixerNode: AVAudioNode, AVAudioMixing {
    let _outputVolume = _AtomicFloat(1)
    let _mixingSource = _MixingSource()

    public override init() { super.init() }

    open override var numberOfInputs: Int { 8 }

    /// The mixer's own gain, applied to the sum.
    open var outputVolume: Float {
        get { _outputVolume.value }
        set { _outputVolume.value = newValue }
    }

    /// The lowest input bus with nothing connected to it.
    open var nextAvailableInputBus: AVAudioNodeBus {
        _engine?._lock.lock(); defer { _engine?._lock.unlock() }
        var bus = 0
        while _inputConnections[bus] != nil { bus += 1 }
        return bus
    }

    func _defaultMixerOutputFormat() -> AVAudioFormat {
        _engine?._hardwareFormat() ?? AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    }
    override func _defaultOutputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { _defaultMixerOutputFormat() }

    // AVAudioMixing (for a mixer feeding another mixer).
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
