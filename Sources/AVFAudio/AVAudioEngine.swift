// AVAudioEngine: the node graph, its connections, the output stream and manual rendering.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioenginemanualrenderingerror
public enum AVAudioEngineManualRenderingError: OSStatus, Error, Sendable {
    case invalidMode = -80800
    case initialized = -80801
    case notRunning = -80802
}

public enum AVAudioEngineManualRenderingStatus: Int, Sendable {
    case error = -1
    case success = 0
    case insufficientDataFromInputNode = 1
    case cannotDoInCurrentContext = 2
}

public enum AVAudioEngineManualRenderingMode: Int, Sendable {
    case offline = 0
    case realtime = 1
}

public typealias AVAudioEngineManualRenderingBlock = (AVAudioFrameCount, UnsafeMutablePointer<AudioBufferList>, UnsafeMutablePointer<OSStatus>?) -> AVAudioEngineManualRenderingStatus

extension Notification.Name {
    /// Posted (object: the engine) when the engine's input or output device goes away or
    /// the default device it follows changes. The engine has stopped itself by then;
    /// `start()` reopens it on the device now current.
    public static let AVAudioEngineConfigurationChange = Notification.Name("AVAudioEngineConfigurationChangeNotification")
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioengine
open class AVAudioEngine: NSObject {
    let _lock = NSRecursiveLock()
    private var _attached: [ObjectIdentifier: AVAudioNode] = [:]
    private let _outputNode = AVAudioOutputNode()
    private var _mainMixer: AVAudioMixerNode?
    private var _inputNodeStorage: AVAudioInputNode?
    private var _isRunning = false
    private var _graphDirty = true
    private var _graph: _RenderGraph?
    /// Graphs built while a render thread is live are kept until the stream stops: the
    /// render thread may still be using one.
    private var _liveGraphs: [_RenderGraph] = []
    private let _activeGraphBits = _AtomicInt64(0)
    private var _stream: (any PlatformAudioOutputStream)?
    private var _streamFormat: AVAudioFormat?
    /// Whether a render callback may be executing (set under `_lock`).
    var _liveRendering = false
    let _sampleTime = _AtomicInt64(0)
    private var _manual = false
    private var _manualMode: AVAudioEngineManualRenderingMode = .offline
    private var _manualFormat: AVAudioFormat?
    private var _manualMaxFrames: AVAudioFrameCount = 0
    private var _manualSampleTime: AVAudioFramePosition = 0
    private var _autoShutdown = false
    private var _renderingBuffer: AVAudioPCMBuffer?
    private var _inputStream: (any PlatformAudioInputStream)?
    private var _inputStreamFormat: AVAudioFormat?
    private var _outputDeviceSelection: String?
    private var _inputDeviceSelection: String?
    /// The devices the open streams are on (ids from `PlatformAudio`), for device-removal
    /// notifications.
    private var _openOutputDeviceID: String?
    private var _openInputDeviceID: String?

    public override init() {
        super.init()
        _outputNode._engine = self
        _attached[ObjectIdentifier(_outputNode)] = _outputNode
    }

    deinit {
        _DeviceWatch.shared.unregister(self)
        _stream?.stop()
        _stream?.close()
        _inputStream?.stop()
        _inputStream?.close()
    }

    /// The attached nodes, for the graph builder (the caller holds `_lock`).
    func _attachedNodesLocked() -> [AVAudioNode] { Array(_attached.values) }

    // MARK: Nodes

    open func attach(_ node: AVAudioNode) {
        _lock.lock(); defer { _lock.unlock() }
        guard _attached[ObjectIdentifier(node)] == nil else { return }
        precondition(node._engine == nil, "AVAudioEngine.attach: the node is attached to another engine")
        _attached[ObjectIdentifier(node)] = node
        node._engine = self
        _graphChanged()
    }

    open func detach(_ node: AVAudioNode) {
        _lock.lock(); defer { _lock.unlock() }
        guard node !== _outputNode, _attached.removeValue(forKey: ObjectIdentifier(node)) != nil else { return }
        disconnectNodeInput(node)
        disconnectNodeOutput(node)
        node._engine = nil
        if node === _mainMixer { _mainMixer = nil }
        _graphChanged()
    }

    open var attachedNodes: Set<AVAudioNode> {
        _lock.lock(); defer { _lock.unlock() }
        return Set(_attached.values)
    }

    open var outputNode: AVAudioOutputNode { _outputNode }

    /// Created and attached on first access, as Apple's engine does; it captures from the
    /// default input device (or `_inputDeviceUID`) once connected or tapped.
    open var inputNode: AVAudioInputNode {
        _lock.lock(); defer { _lock.unlock() }
        if let n = _inputNodeStorage { return n }
        let n = AVAudioInputNode()
        _inputNodeStorage = n
        attach(n)
        return n
    }

    /// Created and connected to the output node on first access, as Apple's engine does.
    open var mainMixerNode: AVAudioMixerNode {
        _lock.lock(); defer { _lock.unlock() }
        if let m = _mainMixer { return m }
        let m = AVAudioMixerNode()
        _mainMixer = m
        attach(m)
        connect(m, to: _outputNode, format: nil)
        return m
    }

    // MARK: Connections

    open func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) {
        _lock.lock(); defer { _lock.unlock() }
        let bus = (node2 as? AVAudioMixerNode)?.nextAvailableInputBus ?? 0
        connect(node1, to: node2, fromBus: 0, toBus: bus, format: format)
    }

    open func connect(_ node1: AVAudioNode, to node2: AVAudioNode, fromBus bus1: AVAudioNodeBus, toBus bus2: AVAudioNodeBus, format: AVAudioFormat?) {
        _lock.lock(); defer { _lock.unlock() }
        precondition(_attached[ObjectIdentifier(node1)] != nil && _attached[ObjectIdentifier(node2)] != nil, "AVAudioEngine.connect: both nodes must be attached")
        let f = format ?? _implicitFormat(from: node1, bus: bus1, to: node2)
        precondition(f.channelCount > 0 && f.sampleRate > 0, "AVAudioEngine.connect: the format is empty and neither node has one")
        precondition(f.commonFormat == .pcmFormatFloat32 && !f.isInterleaved, "AVAudioEngine.connect: connections must use the standard (Float32, non-interleaved) format")
        if let old = node2._inputConnections[bus2] { _remove(old) }
        let c = _Connection(source: node1, sourceBus: bus1, destination: node2, destinationBus: bus2, format: f)
        node2._inputConnections[bus2] = c
        node1._outputConnections[bus1, default: []].append(c)
        _graphChanged()
    }

    open func connect(_ sourceNode: AVAudioNode, toConnectionPoints destNodes: [AVAudioConnectionPoint], fromBus sourceBus: AVAudioNodeBus, format: AVAudioFormat?) {
        _lock.lock(); defer { _lock.unlock() }
        disconnectNodeOutput(sourceNode, bus: sourceBus)
        for point in destNodes {
            guard let dest = point.node else { continue }
            connect(sourceNode, to: dest, fromBus: sourceBus, toBus: point.bus, format: format)
        }
    }

    private func _implicitFormat(from node1: AVAudioNode, bus: AVAudioNodeBus, to node2: AVAudioNode) -> AVAudioFormat {
        if let existing = node1._outputConnections[bus]?.first?.format { return existing }
        if node1 is AVAudioInputNode { return node1._defaultOutputFormat(forBus: bus) }
        if node2 === _outputNode { return _hardwareFormat() }
        if node1 is AVAudioMixerNode { return (node2._inputConnections[0]?.format) ?? (node1 as! AVAudioMixerNode)._defaultMixerOutputFormat() }
        let d = node1._defaultOutputFormat(forBus: bus)
        if d.channelCount > 0 { return d }
        if let down = node2._outputConnections[0]?.first?.format { return down }
        return _hardwareFormat()
    }

    private func _remove(_ c: _Connection) {
        c.destination._inputConnections[c.destinationBus] = nil
        c.source._outputConnections[c.sourceBus]?.removeAll { $0 === c }
        switch c.source {
        case let p as AVAudioPlayerNode: p._mixingSource.removeDestinations(forMixer: c.destination, bus: c.destinationBus)
        case let m as AVAudioMixerNode: m._mixingSource.removeDestinations(forMixer: c.destination, bus: c.destinationBus)
        case let s as AVAudioSourceNode: s._mixingSource.removeDestinations(forMixer: c.destination, bus: c.destinationBus)
        case let i as AVAudioInputNode: i._mixingSource.removeDestinations(forMixer: c.destination, bus: c.destinationBus)
        default: break
        }
    }

    open func disconnectNodeInput(_ node: AVAudioNode, bus: AVAudioNodeBus) {
        _lock.lock(); defer { _lock.unlock() }
        guard let c = node._inputConnections[bus] else { return }
        _remove(c)
        _graphChanged()
    }

    open func disconnectNodeInput(_ node: AVAudioNode) {
        _lock.lock(); defer { _lock.unlock() }
        for (_, c) in node._inputConnections { _remove(c) }
        _graphChanged()
    }

    open func disconnectNodeOutput(_ node: AVAudioNode, bus: AVAudioNodeBus) {
        _lock.lock(); defer { _lock.unlock() }
        for c in node._outputConnections[bus] ?? [] { _remove(c) }
        _graphChanged()
    }

    open func disconnectNodeOutput(_ node: AVAudioNode) {
        _lock.lock(); defer { _lock.unlock() }
        for (_, cs) in node._outputConnections { for c in cs { _remove(c) } }
        _graphChanged()
    }

    open func inputConnectionPoint(for node: AVAudioNode, inputBus bus: AVAudioNodeBus) -> AVAudioConnectionPoint? {
        _lock.lock(); defer { _lock.unlock() }
        guard let c = node._inputConnections[bus] else { return nil }
        return AVAudioConnectionPoint(node: c.source, bus: c.sourceBus)
    }

    open func outputConnectionPoints(for node: AVAudioNode, outputBus bus: AVAudioNodeBus) -> [AVAudioConnectionPoint] {
        _lock.lock(); defer { _lock.unlock() }
        return (node._outputConnections[bus] ?? []).map { AVAudioConnectionPoint(node: $0.destination, bus: $0.destinationBus) }
    }

    /// Marks the compiled graph stale; rebuilt at the next start, prepare or render, or at
    /// once while running.
    func _graphChanged() {
        _graphDirty = true
        if _isRunning {
            // A tap or connection on the input node while running opens the capture stream.
            if !_manual, _inputStream == nil, _inputIsUsed {
                if (try? _openInputStream()) != nil { try? _inputStream?.start() }
            }
            _rebuildGraph()
        }
    }

    // MARK: Formats and the stream

    /// The output device's format, or the manual rendering format.
    func _hardwareFormat() -> AVAudioFormat {
        _lock.lock(); defer { _lock.unlock() }
        if _manual, let f = _manualFormat { return f }
        if let f = _streamFormat { return f }
        if let d = try? PlatformAudio.backend.defaultOutputDevice(), let f = AVAudioFormat(standardFormatWithSampleRate: d.sampleRate, channels: AVAudioChannelCount(max(1, d.channelCount))) { return f }
        return AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    }

    /// The device stream's description for logging ("WASAPI: Speakers, 48000 Hz, 2 ch, 10.7 ms").
    public var _outputDescription: String? {
        _lock.lock(); defer { _lock.unlock() }
        guard let s = _stream else { return nil }
        return "\(PlatformAudio.backend.name): \(s.deviceName), \(Int(s.sampleRate)) Hz, \(s.channelCount) ch, period \(s.bufferFrameCount) frames, latency \(String(format: "%.1f", s.latency * 1000)) ms"
    }

    /// The selected output device, or nil for the default (the selection falls back to
    /// the default when that device is gone).
    private func _resolveOutputDevice() -> PlatformAudioDevice? {
        let backend = PlatformAudio.backend
        if let uid = _outputDeviceSelection, let d = (try? backend.outputDevices())?.first(where: { $0.id == uid }) { return d }
        return nil
    }

    private func _resolveInputDevice(_ backend: any PlatformAudioInputBackend) -> PlatformAudioDevice? {
        if let uid = _inputDeviceSelection, let d = (try? backend.inputDevices())?.first(where: { $0.id == uid }) { return d }
        return nil
    }

    private func _openStream() throws {
        guard _stream == nil else { return }
        let backend = PlatformAudio.backend
        let device = _resolveOutputDevice()
        let stream = try backend.openOutputStream(device: device, sampleRate: nil, channelCount: nil) { [weak self] out, frames in
            self?._renderCallback(out, frames: frames)
        }
        _stream = stream
        _streamFormat = AVAudioFormat(standardFormatWithSampleRate: stream.sampleRate, channels: AVAudioChannelCount(stream.channelCount))
        _openOutputDeviceID = device?.id ?? (try? backend.defaultOutputDevice())?.id
        _graphDirty = true
        _DeviceWatch.shared.register(self)
    }

    /// Whether the input node is connected or tapped (so the engine captures).
    private var _inputIsUsed: Bool {
        guard let n = _inputNodeStorage else { return false }
        return !n._outputConnections.values.allSatisfy { $0.isEmpty } || !n._taps.isEmpty
    }

    /// The input device's format, or an empty format when there is none.
    func _inputHardwareFormat() -> AVAudioFormat {
        _lock.lock(); defer { _lock.unlock() }
        if _manual, let f = _inputNodeStorage?._manualFormat, let s = AVAudioFormat(standardFormatWithSampleRate: f.sampleRate, channels: f.channelCount) { return s }
        if let f = _inputStreamFormat { return f }
        guard let backend = PlatformAudio.backend as? any PlatformAudioInputBackend else { return AVAudioFormat() }
        let device = _resolveInputDevice(backend) ?? (try? backend.defaultInputDevice()) ?? nil
        guard let d = device, let f = AVAudioFormat(standardFormatWithSampleRate: d.sampleRate, channels: AVAudioChannelCount(max(1, d.channelCount))) else { return AVAudioFormat() }
        return f
    }

    private func _openInputStream() throws {
        guard _inputStream == nil, let node = _inputNodeStorage else { return }
        guard let backend = PlatformAudio.backend as? any PlatformAudioInputBackend else {
            throw PlatformAudioError("\(PlatformAudio.backend.name) has no audio input")
        }
        let format = node.outputFormat(forBus: 0)
        let device = _resolveInputDevice(backend)
        let capture = _InputCapture(channels: Int(format.channelCount), period: 480)
        let stream = try backend.openInputStream(device: device, sampleRate: format.sampleRate > 0 ? format.sampleRate : nil, channelCount: nil) { input, frames in
            capture.captured(input, frames: frames)
        }
        capture.streamChannels = stream.channelCount
        _inputStream = stream
        _inputStreamFormat = AVAudioFormat(standardFormatWithSampleRate: stream.sampleRate, channels: AVAudioChannelCount(stream.channelCount))
        _openInputDeviceID = device?.id ?? (try? backend.defaultInputDevice())?.id
        node._capture = capture
        _graphDirty = true
        _DeviceWatch.shared.register(self)
    }

    private func _closeInputStream() {
        _inputStream?.stop()
        _inputStream?.close()
        _inputStream = nil
        _inputStreamFormat = nil
        _openInputDeviceID = nil
        _inputNodeStorage?._capture = nil
    }

    // MARK: Devices (port-specific; see ADR-0028)

    /// The output device the engine renders to, as a `PlatformAudioDevice.id` (on Windows
    /// the endpoint ID, on Linux the PipeWire node name); nil follows the system default.
    /// Apple selects the device through the output unit's `kAudioOutputUnitProperty_
    /// CurrentDevice`, which has no counterpart here. Setting it while running moves the
    /// stream to the device at once.
    public var _outputDeviceUID: String? {
        get { _lock.withLock { _outputDeviceSelection } }
        set {
            _lock.lock(); defer { _lock.unlock() }
            guard newValue != _outputDeviceSelection else { return }
            _outputDeviceSelection = newValue
            guard !_manual, _stream != nil else { return }
            let wasRunning = _isRunning
            _stream?.stop()
            _liveRendering = false
            _liveGraphs.removeAll()
            _stream?.close()
            _stream = nil
            _streamFormat = nil
            _graphDirty = true
            if wasRunning {
                _isRunning = false
                do { try _startLocked() } catch {
                    FileHandle.standardError.write("AppKitCross audio: cannot move the engine to \(newValue ?? "the default output"): \(error)\n".data(using: .utf8)!)
                }
            }
        }
    }

    /// The input device the input node captures from (see `_outputDeviceUID`).
    public var _inputDeviceUID: String? {
        get { _lock.withLock { _inputDeviceSelection } }
        set {
            _lock.lock(); defer { _lock.unlock() }
            guard newValue != _inputDeviceSelection else { return }
            _inputDeviceSelection = newValue
            guard _inputStream != nil else { return }
            let running = _isRunning
            _closeInputStream()
            if running, (try? _openInputStream()) != nil { try? _inputStream?.start() }
            _rebuildGraph()
        }
    }

    /// The id of the device the output stream is open on (the default's id when following
    /// it); nil while no stream is open.
    public var _currentOutputDeviceUID: String? { _lock.withLock { _openOutputDeviceID } }

    /// Called by `_DeviceWatch` on its queue: stops the engine when the change concerns a
    /// device it renders to or captures from, and posts the configuration change.
    func _deviceChanged(_ change: PlatformAudioDeviceChange) {
        _lock.lock()
        guard _isRunning, !_manual else { _lock.unlock(); return }
        var affected = false
        switch change {
        case .defaultDeviceChanged(let isInput, let id):
            if isInput { affected = _inputStream != nil && _inputDeviceSelection == nil && id != _openInputDeviceID }
            else { affected = _outputDeviceSelection == nil && id != _openOutputDeviceID }
        case .deviceRemoved(let id):
            affected = id == _openOutputDeviceID || (_inputStream != nil && id == _openInputDeviceID)
        case .deviceAdded:
            affected = false
        }
        if affected { stop() }
        _lock.unlock()
        if affected { NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: self) }
    }

    private func _rebuildGraph() {
        let format = _hardwareFormat()
        let maxFrames: Int
        let latencyFrames: Int64
        if _manual {
            maxFrames = Int(_manualMaxFrames)
            latencyFrames = -1      // no playback clock: dataPlayedBack never fires (as Apple's)
        } else if let s = _stream {
            maxFrames = max(s.bufferFrameCount * 2, 1024)
            latencyFrames = Int64(s.latency * s.sampleRate)
        } else {
            maxFrames = 4096
            latencyFrames = 0
        }
        let graph = _RenderGraph(engine: self, outputNode: _outputNode, format: format, maxFrames: maxFrames, latencyFrames: latencyFrames, manualRendering: _manual)
        _graph = graph
        _graphDirty = false
        if _liveRendering { _liveGraphs.append(graph) }
        _activeGraphBits.value = Int64(Int(bitPattern: Unmanaged.passUnretained(graph).toOpaque()))
        _outputNode._latency.value = 0
    }

    /// The backend's render thread.
    private func _renderCallback(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let bits = _activeGraphBits.value
        guard bits != 0, let raw = UnsafeRawPointer(bitPattern: Int(bits)) else {
            out.update(repeating: 0, count: frames * (_stream?.channelCount ?? 2))
            return
        }
        let graph = Unmanaged<_RenderGraph>.fromOpaque(raw).takeUnretainedValue()
        let sampleTime = _sampleTime.value
        let hostTime = Int64(_currentHostTime())
        var done = 0
        while done < frames {
            let n = min(frames - done, graph.maxFrames)
            graph.render(frames: n, sampleTime: sampleTime + Int64(done), hostTime: hostTime, into: out + done * graph.channels)
            done += n
        }
        _sampleTime.value = sampleTime + Int64(frames)
    }

    // MARK: Transport

    /// Opens the output stream and compiles the graph so `start()` is quick.
    open func prepare() {
        _lock.lock(); defer { _lock.unlock() }
        if !_manual { try? _openStream() }
        if _graphDirty || _graph == nil { _rebuildGraph() }
    }

    open func start() throws {
        _lock.lock(); defer { _lock.unlock() }
        try _startLocked()
    }

    private func _startLocked() throws {
        if _isRunning { return }
        if _manual {
            if _graphDirty || _graph == nil { _rebuildGraph() }
            _isRunning = true
            return
        }
        do { try _openStream() } catch {
            throw _osStatusError(-10875, "AVAudioEngine.start: no output stream: \(error.localizedDescription)")
        }
        if _inputIsUsed {
            do { try _openInputStream() } catch {
                throw _osStatusError(-10875, "AVAudioEngine.start: no input stream: \(error.localizedDescription)")
            }
        }
        if _graphDirty || _graph == nil { _rebuildGraph() }
        _liveRendering = true
        if let g = _graph { _liveGraphs.append(g) }
        do {
            try _inputStream?.start()
            try _stream!.start()
        } catch {
            _inputStream?.stop()
            _liveRendering = false
            _liveGraphs.removeAll()
            throw _osStatusError(-10875, "AVAudioEngine.start: \(error.localizedDescription)")
        }
        _isRunning = true
    }

    /// Stops rendering but keeps the stream and the graph; `start()` resumes.
    open func pause() {
        _lock.lock(); defer { _lock.unlock() }
        guard _isRunning else { return }
        _stream?.stop()
        _inputStream?.stop()
        _liveRendering = false
        _liveGraphs.removeAll()
        _isRunning = false
    }

    /// Resets every node's processing state (player nodes stop and clear their schedules).
    open func reset() {
        _lock.lock(); defer { _lock.unlock() }
        for (_, n) in _attached { n.reset() }
    }

    /// Stops and releases the output stream.
    open func stop() {
        _lock.lock(); defer { _lock.unlock() }
        _stream?.stop()
        _inputStream?.stop()
        _liveRendering = false
        _liveGraphs.removeAll()
        _isRunning = false
        for (_, n) in _attached { if let p = n as? AVAudioPlayerNode, p.isPlaying { p.pause() } }
        if !_manual {
            _stream?.close()
            _stream = nil
            _streamFormat = nil
            _openOutputDeviceID = nil
            _closeInputStream()
            _graphDirty = true
        }
    }

    open var isRunning: Bool {
        _lock.lock(); defer { _lock.unlock() }
        return _isRunning
    }

    open var isAutoShutdownEnabled: Bool {
        get { _autoShutdown }
        set { _autoShutdown = newValue }
    }

    // MARK: Manual rendering

    /// Switches the engine to render on demand (`renderOffline`) into `pcmFormat`; must be
    /// called while stopped.
    open func enableManualRenderingMode(_ mode: AVAudioEngineManualRenderingMode, format pcmFormat: AVAudioFormat, maximumFrameCount: AVAudioFrameCount) throws {
        _lock.lock(); defer { _lock.unlock() }
        if _isRunning { throw _osStatusError(AVAudioEngineManualRenderingError.initialized.rawValue, "AVAudioEngine: stop the engine before enabling manual rendering") }
        guard pcmFormat.channelCount > 0, pcmFormat.sampleRate > 0, pcmFormat.commonFormat != .otherFormat, maximumFrameCount > 0 else {
            throw _osStatusError(-10868, "AVAudioEngine: unsupported manual rendering format")
        }
        _stream?.close(); _stream = nil; _streamFormat = nil
        _closeInputStream()
        _manual = true
        _manualMode = mode
        _manualFormat = pcmFormat
        _manualMaxFrames = maximumFrameCount
        _manualSampleTime = 0
        _sampleTime.value = 0
        _graphDirty = true
        _renderingBuffer = nil
        // Reconnect the chain into the output node in the new format if it was implicit.
        if let c = _outputNode._inputConnections[0], c.format.sampleRate != pcmFormat.sampleRate || c.format.channelCount != pcmFormat.channelCount {
            connect(c.source, to: _outputNode, fromBus: c.sourceBus, toBus: 0, format: AVAudioFormat(standardFormatWithSampleRate: pcmFormat.sampleRate, channels: pcmFormat.channelCount))
        }
    }

    open func disableManualRenderingMode() {
        _lock.lock(); defer { _lock.unlock() }
        stop()
        _manual = false
        _manualFormat = nil
        _graphDirty = true
    }

    /// Renders `numberOfFrames` frames (at most `manualRenderingMaximumFrameCount`) into
    /// `buffer`, which must be in the manual rendering format.
    open func renderOffline(_ numberOfFrames: AVAudioFrameCount, to buffer: AVAudioPCMBuffer) throws -> AVAudioEngineManualRenderingStatus {
        _lock.lock(); defer { _lock.unlock() }
        guard _manual else { throw _osStatusError(AVAudioEngineManualRenderingError.invalidMode.rawValue, "AVAudioEngine.renderOffline: not in manual rendering mode") }
        guard _isRunning else { throw _osStatusError(AVAudioEngineManualRenderingError.notRunning.rawValue, "AVAudioEngine.renderOffline: the engine is not running") }
        guard let format = _manualFormat, buffer.format.isEqual(format) else {
            throw _osStatusError(-10868, "AVAudioEngine.renderOffline: the buffer's format must be the manual rendering format")
        }
        let frames = Int(min(numberOfFrames, _manualMaxFrames, buffer.frameCapacity))
        if _graphDirty || _graph == nil { _rebuildGraph() }
        guard let graph = _graph else { return .error }
        graph.renderPlanar(frames: frames, sampleTime: _sampleTime.value, hostTime: Int64(_currentHostTime()))
        for c in 0..<Int(format.channelCount) { buffer._writeFloats(channel: c, frame: 0, count: frames, from: graph.planes[c]) }
        buffer.frameLength = AVAudioFrameCount(frames)
        _sampleTime.add(Int64(frames))
        _manualSampleTime += AVAudioFramePosition(frames)
        _DeliveryHub.shared.signal()
        return .success
    }

    open var manualRenderingBlock: AVAudioEngineManualRenderingBlock {
        return { [weak self] frames, list, outError in
            guard let self, let format = self._manualFormat else { outError?.pointee = AVAudioEngineManualRenderingError.invalidMode.rawValue; return .error }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list) else { outError?.pointee = -10868; return .error }
            do { return try self.renderOffline(frames, to: buffer) } catch {
                outError?.pointee = OSStatus(truncatingIfNeeded: (error as NSError).code)
                return .error
            }
        }
    }

    open var isInManualRenderingMode: Bool { _lock.withLock { _manual } }
    open var manualRenderingMode: AVAudioEngineManualRenderingMode { _lock.withLock { _manualMode } }
    open var manualRenderingFormat: AVAudioFormat { _lock.withLock { _manualFormat ?? AVAudioFormat() } }
    open var manualRenderingMaximumFrameCount: AVAudioFrameCount { _lock.withLock { _manualMaxFrames } }
    open var manualRenderingSampleTime: AVAudioFramePosition { _lock.withLock { _manualSampleTime } }
}

extension NSRecursiveLock {
    @inline(__always) func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}

/// Forwards the backend's device notifications to the engines that have streams open.
final class _DeviceWatch: @unchecked Sendable {
    static let shared = _DeviceWatch()
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "AVFAudio device changes")
    private struct WeakEngine { weak var engine: AVAudioEngine? }
    private var engines: [ObjectIdentifier: WeakEngine] = [:]
    private weak var installedOn: AnyObject?

    func register(_ engine: AVAudioEngine) {
        lock.lock(); defer { lock.unlock() }
        engines[ObjectIdentifier(engine)] = WeakEngine(engine: engine)
        let backend = PlatformAudio.backend
        guard installedOn !== backend, let inputs = backend as? any PlatformAudioInputBackend else { return }
        (installedOn as? any PlatformAudioInputBackend)?.setDeviceChangeHandler(nil)
        installedOn = backend
        inputs.setDeviceChangeHandler { [weak self] change in self?.dispatch(change) }
    }

    func unregister(_ engine: AVAudioEngine) {
        lock.lock(); engines[ObjectIdentifier(engine)] = nil; lock.unlock()
    }

    private func dispatch(_ change: PlatformAudioDeviceChange) {
        queue.async { [self] in
            lock.lock()
            let live = engines.values.compactMap { $0.engine }
            engines = engines.filter { $0.value.engine != nil }
            lock.unlock()
            if ProcessInfo.processInfo.environment["APPKITWIN_AUDIO_LOG"] != nil {
                FileHandle.standardError.write("AppKitCross audio: device change \(change)\n".data(using: .utf8)!)
            }
            for e in live { e._deviceChanged(change) }
        }
    }
}
