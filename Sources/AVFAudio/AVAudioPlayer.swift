// AVAudioPlayer: plays one sound file through a shared engine (one output stream per
// process, every player a node on its main mixer).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioplayerdelegate
public protocol AVAudioPlayerDelegate: NSObjectProtocol {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool)
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?)
}

extension AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {}
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {}
}

/// The engine every `AVAudioPlayer` (and `NSSound`) plays through.
final class _SharedPlayerEngine {
    static let shared = _SharedPlayerEngine()
    let engine = AVAudioEngine()
    private let lock = NSLock()
    private var users = 0

    func attach(_ node: AVAudioPlayerNode, format: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func detach(_ node: AVAudioPlayerNode) {
        lock.lock(); defer { lock.unlock() }
        engine.detach(node)
    }

    /// Starts the engine for a player; false when there is no output.
    func acquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        users += 1
        return true
    }

    func release() {
        lock.lock(); defer { lock.unlock() }
        users = max(0, users - 1)
    }
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudioplayer
open class AVAudioPlayer: NSObject {
    private let node = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer
    private let fileFormat: AVAudioFormat
    private let _url: URL?
    private let _data: Data?
    private let lock = NSRecursiveLock()
    private var _isPlaying = false
    private var _numberOfLoops = 0
    private var _loopsRemaining = 0
    private var _pausedAtFrame: Int64 = 0
    private var _startFrame: Int64 = 0
    private var _playbackStartOffset: Int64 = 0   // player sample time at which this run started
    private var _generation = 0
    private var _prepared = false
    private var _rateEnabled = false
    private var _rate: Float = 1
    private var _meteringEnabled = false
    private var _peak: [Float] = []
    private var _average: [Float] = []
    private var _meterPeak: [Float] = []
    private var _meterAverage: [Float] = []
    private var _fadeTimer: DispatchSourceTimer?
    private var _delayedStart: DispatchWorkItem?
    open weak var delegate: (any AVAudioPlayerDelegate)?

    public convenience init(contentsOf url: URL) throws { try self.init(contentsOf: url, fileTypeHint: nil) }
    public convenience init(data: Data) throws { try self.init(data: data, fileTypeHint: nil) }

    public init(contentsOf url: URL, fileTypeHint utiString: String?) throws {
        let file = try AVAudioFile(forReading: url)
        guard let b = try file._readAll() else { throw AVError(.fileFailedToParse)._nsError("AVAudioPlayer: \(url.lastPathComponent) holds no audio") }
        buffer = b
        fileFormat = file.fileFormat
        _url = url
        _data = nil
        super.init()
        _attach()
    }

    public init(data: Data, fileTypeHint utiString: String?) throws {
        let decoded = try AVAudioFile._decode(data: data)
        buffer = decoded.buffer
        fileFormat = decoded.format
        _url = nil
        _data = data
        super.init()
        _attach()
    }

    deinit {
        _fadeTimer?.cancel()
        node.stop()
        _SharedPlayerEngine.shared.detach(node)
    }

    private func _attach() {
        _SharedPlayerEngine.shared.attach(node, format: buffer.format)
        let channels = Int(buffer.format.channelCount)
        _peak = Array(repeating: -160, count: channels); _average = _peak; _meterPeak = _peak; _meterAverage = _peak
    }

    // MARK: Transport

    /// Starts the shared engine; false when there is no output device.
    open func prepareToPlay() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if _prepared { return true }
        _prepared = _SharedPlayerEngine.shared.acquire()
        return _prepared
    }

    @discardableResult
    open func play() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepareToPlay() else { return false }
        if _isPlaying { return true }
        if _rateEnabled && _rate != 1 { unimplemented("AVAudioPlayer.rate (time stretching)") }
        _isPlaying = true
        _generation += 1
        _loopsRemaining = _numberOfLoops
        _startRun(from: _pausedAtFrame)
        return true
    }

    /// Starts at `time` on the device clock (`deviceCurrentTime` plus a delay).
    @discardableResult
    open func play(atTime time: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepareToPlay() else { return false }
        let delay = time - deviceCurrentTime
        if delay <= 0 { return play() }
        _delayedStart?.cancel()
        let item = DispatchWorkItem { [weak self] in _ = self?.play() }
        _delayedStart = item
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
        return true
    }

    private func _startRun(from frame: Int64) {
        let total = Int64(buffer.frameLength)
        let start = max(0, min(frame, total))
        _startFrame = start
        node.stop()
        _playbackStartOffset = 0
        let generation = _generation
        let rate = buffer.format.sampleRate
        // The first pass plays from `start`; each further loop plays the whole buffer.
        if start < total {
            let segment = _segment(from: start)
            _scheduleSegment(segment, generation: generation)
        }
        if _loopsRemaining != 0 {
            let whole = _segment(from: 0)
            _scheduleLoop(whole, generation: generation)
        }
        if _meteringEnabled { _installMeter() }
        node.play(at: nil)
        _ = rate
    }

    private func _segment(from frame: Int64) -> AVAudioPCMBuffer {
        let total = Int64(buffer.frameLength)
        if frame == 0 { return buffer }
        let count = Int(total - frame)
        let seg = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(max(1, count)))!
        for c in 0..<Int(buffer.format.channelCount) { seg.floatChannelData![c].update(from: buffer.floatChannelData![c] + Int(frame), count: count) }
        seg.frameLength = AVAudioFrameCount(count)
        return seg
    }

    private func _scheduleSegment(_ segment: AVAudioPCMBuffer, generation: Int) {
        node.scheduleBuffer(segment, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?._segmentFinished(generation: generation)
        }
    }

    /// Schedules the whole buffer for the remaining loops: once per loop when finite,
    /// with the `.loops` option when infinite.
    private func _scheduleLoop(_ whole: AVAudioPCMBuffer, generation: Int) {
        if _loopsRemaining < 0 {
            node.scheduleBuffer(whole, at: nil, options: .loops, completionCallbackType: .dataPlayedBack, completionHandler: nil)
        } else {
            for i in 0..<_loopsRemaining {
                let last = i == _loopsRemaining - 1
                node.scheduleBuffer(whole, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    if last { self?._segmentFinished(generation: generation) }
                }
            }
        }
    }

    private func _segmentFinished(generation: Int) {
        lock.lock()
        guard generation == _generation, _isPlaying else { lock.unlock(); return }
        if _loopsRemaining > 0 {
            // A finite loop run: the last loop's handler ends it; the first segment's does not.
            _loopsRemaining = 0
            lock.unlock()
            return
        }
        _isPlaying = false
        _pausedAtFrame = 0
        _startFrame = 0
        node.stop()
        _SharedPlayerEngine.shared.release()
        _prepared = false
        let delegate = self.delegate
        lock.unlock()
        DispatchQueue.main.async { delegate?.audioPlayerDidFinishPlaying(self, successfully: true) }
    }

    open func pause() {
        lock.lock(); defer { lock.unlock() }
        _delayedStart?.cancel()
        guard _isPlaying else { return }
        _pausedAtFrame = _currentFrame()
        _isPlaying = false
        _generation += 1
        node.stop()
    }

    /// Stops; `currentTime` keeps its value and `play()` resumes there.
    open func stop() {
        lock.lock(); defer { lock.unlock() }
        _delayedStart?.cancel()
        if _isPlaying { _pausedAtFrame = _currentFrame() }
        _isPlaying = false
        _generation += 1
        node.stop()
        if _prepared { _SharedPlayerEngine.shared.release(); _prepared = false }
    }

    private func _currentFrame() -> Int64 {
        let total = Int64(buffer.frameLength)
        guard total > 0 else { return 0 }
        guard _isPlaying, let last = node.lastRenderTime, let pt = node.playerTime(forNodeTime: last) else { return _pausedAtFrame }
        let elapsed = max(0, pt.sampleTime)
        let position = _startFrame + elapsed
        if _numberOfLoops == 0 { return min(position, total) }
        return position % total
    }

    open var isPlaying: Bool { lock.withLock { _isPlaying } }
    open var numberOfChannels: Int { Int(buffer.format.channelCount) }
    open var duration: TimeInterval { Double(buffer.frameLength) / buffer.format.sampleRate }
    open var currentDevice: String? {
        get { nil }
        set { }
    }
    open var url: URL? { _url }
    open var data: Data? { _data }

    open var pan: Float {
        get { node.pan }
        set { node.pan = newValue }
    }
    open var volume: Float {
        get { node.volume }
        set { _fadeTimer?.cancel(); _fadeTimer = nil; node.volume = newValue }
    }

    /// Ramps the volume linearly over `duration` seconds.
    open func setVolume(_ volume: Float, fadeDuration duration: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _fadeTimer?.cancel()
        guard duration > 0 else { node.volume = volume; return }
        let start = node.volume, startTime = Date()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let t = min(1, Date().timeIntervalSince(startTime) / duration)
            self.node.volume = start + (volume - start) * Float(t)
            if t >= 1 { self.lock.lock(); self._fadeTimer?.cancel(); self._fadeTimer = nil; self.lock.unlock() }
        }
        _fadeTimer = timer
        timer.resume()
    }

    open var enableRate: Bool {
        get { _rateEnabled }
        set { _rateEnabled = newValue }
    }
    /// Time stretching is not implemented: a rate other than 1 traps at `play()`.
    open var rate: Float {
        get { _rate }
        set { _rate = newValue }
    }

    open var currentTime: TimeInterval {
        get { lock.withLock { Double(_currentFrame()) / buffer.format.sampleRate } }
        set {
            lock.lock(); defer { lock.unlock() }
            let frame = Int64(max(0, newValue) * buffer.format.sampleRate)
            _pausedAtFrame = min(frame, Int64(buffer.frameLength))
            if _isPlaying { _generation += 1; _loopsRemaining = _numberOfLoops; _startRun(from: _pausedAtFrame) }
        }
    }

    /// The shared output's clock, in seconds.
    open var deviceCurrentTime: TimeInterval {
        let engine = _SharedPlayerEngine.shared.engine
        guard let t = engine.outputNode.lastRenderTime, t.sampleRate > 0 else { return 0 }
        return Double(t.sampleTime) / t.sampleRate
    }

    /// 0 plays once, n plays n+1 times, -1 loops until stopped.
    open var numberOfLoops: Int {
        get { _numberOfLoops }
        set { _numberOfLoops = newValue }
    }

    open var settings: [String: Any] { fileFormat.settings }
    open var format: AVAudioFormat { buffer.format }

    // MARK: Metering

    open var isMeteringEnabled: Bool {
        get { _meteringEnabled }
        set {
            lock.lock(); defer { lock.unlock() }
            guard newValue != _meteringEnabled else { return }
            _meteringEnabled = newValue
            if newValue { _installMeter() } else { node.removeTap(onBus: 0) }
        }
    }

    private func _installMeter() {
        guard _meteringEnabled, node.engine != nil else { return }
        let channels = Int(buffer.format.channelCount)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            var peaks = [Float](repeating: -160, count: channels), averages = peaks
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { return }
            for c in 0..<channels {
                var peak: Float = 0, sum: Float = 0
                for i in 0..<n { let v = abs(data[c][i]); peak = max(peak, v); sum += v * v }
                peaks[c] = peak > 0 ? 20 * log10(peak) : -160
                let rms = (sum / Float(n)).squareRoot()
                averages[c] = rms > 0 ? 20 * log10(rms) : -160
            }
            self.lock.lock(); self._peak = peaks; self._average = averages; self.lock.unlock()
        }
    }

    open func updateMeters() {
        lock.lock(); defer { lock.unlock() }
        _meterPeak = _peak; _meterAverage = _average
    }
    /// Decibels, -160 for silence.
    open func peakPower(forChannel channelNumber: Int) -> Float {
        lock.lock(); defer { lock.unlock() }
        return channelNumber < _meterPeak.count ? _meterPeak[channelNumber] : -160
    }
    open func averagePower(forChannel channelNumber: Int) -> Float {
        lock.lock(); defer { lock.unlock() }
        return channelNumber < _meterAverage.count ? _meterAverage[channelNumber] : -160
    }
}
