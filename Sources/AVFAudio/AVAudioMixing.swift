// The mixing protocols a source node adopts when it feeds a mixer, the connection point
// and the per-destination mixing parameters.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiostereomixing
public protocol AVAudioStereoMixing: NSObjectProtocol {
    /// -1 (left) ... 1 (right); 0 is centre.
    var pan: Float { get set }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudio3dmixingrenderingalgorithm
public enum AVAudio3DMixingRenderingAlgorithm: Int, Sendable {
    case equalPowerPanning = 0
    case sphericalHead = 1
    case HRTF = 2
    case soundField = 3
    case stereoPassThrough = 5
    case HRTFHQ = 6
    case auto = 7
}

public enum AVAudio3DMixingSourceMode: Int, Sendable {
    case spatializeIfMono = 0
    case bypass = 1
    case pointSource = 2
    case ambienceBed = 3
}

public enum AVAudio3DMixingPointSourceInHeadMode: Int, Sendable {
    case mono = 0
    case bypass = 1
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudio3dmixing
public protocol AVAudio3DMixing: NSObjectProtocol {
    var renderingAlgorithm: AVAudio3DMixingRenderingAlgorithm { get set }
    var sourceMode: AVAudio3DMixingSourceMode { get set }
    var pointSourceInHeadMode: AVAudio3DMixingPointSourceInHeadMode { get set }
    var rate: Float { get set }
    var reverbBlend: Float { get set }
    var obstruction: Float { get set }
    var occlusion: Float { get set }
    var position: AVAudio3DPoint { get set }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiomixing
public protocol AVAudioMixing: AVAudioStereoMixing, AVAudio3DMixing {
    func destination(forMixer mixer: AVAudioNode, bus: AVAudioNodeBus) -> AVAudioMixingDestination?
    /// 0 ... 1.
    var volume: Float { get set }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioconnectionpoint
open class AVAudioConnectionPoint: NSObject {
    private weak var _node: AVAudioNode?
    private let _bus: AVAudioNodeBus
    public init(node: AVAudioNode, bus: AVAudioNodeBus) { _node = node; _bus = bus }
    open var node: AVAudioNode? { _node }
    open var bus: AVAudioNodeBus { _bus }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? AVAudioConnectionPoint else { return false }
        return o._node === _node && o._bus == _bus
    }
    open override var hash: Int { (_node.map { ObjectIdentifier($0).hashValue } ?? 0) ^ _bus }
}

/// The mixing parameters of one source (or one source-to-mixer connection). Volume and pan
/// are atomics the render thread reads every cycle; the 3D parameters are stored but have
/// no effect, as on Apple's stereo mixer without an environment node.
final class _MixingParameters {
    let volume = _AtomicFloat(1)
    let pan = _AtomicFloat(0)
    var renderingAlgorithm: AVAudio3DMixingRenderingAlgorithm = .equalPowerPanning
    var sourceMode: AVAudio3DMixingSourceMode = .spatializeIfMono
    var pointSourceInHeadMode: AVAudio3DMixingPointSourceInHeadMode = .mono
    var rate: Float = 1
    var reverbBlend: Float = 0
    var obstruction: Float = 0
    var occlusion: Float = 0
    var position = AVAudio3DPoint()

    func copy(from other: _MixingParameters) {
        volume.value = other.volume.value
        pan.value = other.pan.value
        renderingAlgorithm = other.renderingAlgorithm; sourceMode = other.sourceMode
        pointSourceInHeadMode = other.pointSourceInHeadMode; rate = other.rate
        reverbBlend = other.reverbBlend; obstruction = other.obstruction; occlusion = other.occlusion
        position = other.position
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiomixingdestination
open class AVAudioMixingDestination: NSObject, AVAudioMixing {
    private let _connectionPoint: AVAudioConnectionPoint
    let _mixing = _MixingParameters()

    init(connectionPoint: AVAudioConnectionPoint, parameters: _MixingParameters) {
        _connectionPoint = connectionPoint
        _mixing.copy(from: parameters)
    }

    open var connectionPoint: AVAudioConnectionPoint { _connectionPoint }

    open func destination(forMixer mixer: AVAudioNode, bus: AVAudioNodeBus) -> AVAudioMixingDestination? {
        (_connectionPoint.node === mixer && _connectionPoint.bus == bus) ? self : nil
    }
    open var volume: Float {
        get { _mixing.volume.value }
        set { _mixing.volume.value = newValue }
    }
    open var pan: Float {
        get { _mixing.pan.value }
        set { _mixing.pan.value = newValue }
    }
    open var renderingAlgorithm: AVAudio3DMixingRenderingAlgorithm {
        get { _mixing.renderingAlgorithm }
        set { _mixing.renderingAlgorithm = newValue }
    }
    open var sourceMode: AVAudio3DMixingSourceMode {
        get { _mixing.sourceMode }
        set { _mixing.sourceMode = newValue }
    }
    open var pointSourceInHeadMode: AVAudio3DMixingPointSourceInHeadMode {
        get { _mixing.pointSourceInHeadMode }
        set { _mixing.pointSourceInHeadMode = newValue }
    }
    open var rate: Float {
        get { _mixing.rate }
        set { _mixing.rate = newValue }
    }
    open var reverbBlend: Float {
        get { _mixing.reverbBlend }
        set { _mixing.reverbBlend = newValue }
    }
    open var obstruction: Float {
        get { _mixing.obstruction }
        set { _mixing.obstruction = newValue }
    }
    open var occlusion: Float {
        get { _mixing.occlusion }
        set { _mixing.occlusion = newValue }
    }
    open var position: AVAudio3DPoint {
        get { _mixing.position }
        set { _mixing.position = newValue }
    }
}

/// Shared implementation of `AVAudioMixing` for the nodes that adopt it. A node-level
/// setter applies to every destination it already has (Apple's documented behaviour).
final class _MixingSource {
    let node: _MixingParameters = _MixingParameters()
    private var destinations: [ObjectIdentifier: [AVAudioNodeBus: AVAudioMixingDestination]] = [:]
    private let lock = NSLock()

    func destination(forMixer mixer: AVAudioNode, bus: AVAudioNodeBus, connected: Bool) -> AVAudioMixingDestination? {
        lock.lock(); defer { lock.unlock() }
        if let d = destinations[ObjectIdentifier(mixer)]?[bus] { return d }
        guard connected else { return nil }
        let d = AVAudioMixingDestination(connectionPoint: AVAudioConnectionPoint(node: mixer, bus: bus), parameters: node)
        destinations[ObjectIdentifier(mixer), default: [:]][bus] = d
        return d
    }

    /// Parameters the render graph reads for a connection into `mixer` bus `bus`.
    func parameters(forMixer mixer: AVAudioNode, bus: AVAudioNodeBus) -> _MixingParameters {
        lock.lock(); defer { lock.unlock() }
        return destinations[ObjectIdentifier(mixer)]?[bus]?._mixing ?? node
    }

    func forEachDestination(_ body: (_MixingParameters) -> Void) {
        lock.lock(); defer { lock.unlock() }
        for (_, byBus) in destinations { for (_, d) in byBus { body(d._mixing) } }
    }

    func removeDestinations(forMixer mixer: AVAudioNode, bus: AVAudioNodeBus?) {
        lock.lock(); defer { lock.unlock() }
        if let bus { destinations[ObjectIdentifier(mixer)]?[bus] = nil } else { destinations[ObjectIdentifier(mixer)] = nil }
    }
}
