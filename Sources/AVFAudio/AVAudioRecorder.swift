// AVAudioRecorder: records the default input device to a linear PCM file (WAV, AIFF,
// AIFF-C or CAF, from the path extension). The capture stream hands frames to a ring; a
// writer thread converts them to the file's format with AVAudioConverter, meters them and
// writes them, so the capture thread never touches the file.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiorecorderdelegate
public protocol AVAudioRecorderDelegate: NSObjectProtocol {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool)
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?)
}

extension AVAudioRecorderDelegate {
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}
    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {}
}

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiorecorder
open class AVAudioRecorder: NSObject, @unchecked Sendable {
    private let _url: URL
    private let _settings: [String: Any]
    private let _fileFormat: AVAudioFormat
    private let lock = NSRecursiveLock()
    private var file: AVAudioFile?
    private var stream: (any PlatformAudioInputStream)?
    private var streamFormat: AVAudioFormat?
    private var ring: _FrameRing?
    private var converter: AVAudioConverter?
    private var writer: Thread?
    private let wake = DispatchSemaphore(value: 0)
    private let writerDone = DispatchSemaphore(value: 0)
    private let capturing = _AtomicBool(false)      // the capture side keeps frames
    private let writerRunning = _AtomicBool(false)
    private var _isRecording = false
    private var framesWritten: Int64 = 0
    private var stopAfterFrames: Int64 = -1
    private var startedAt: Date?
    private var _meteringEnabled = false
    private var peak: [Float] = [], average: [Float] = []
    private var meterPeak: [Float] = [], meterAverage: [Float] = []
    private var delayedStart: DispatchWorkItem?
    private var encodeError: Error?
    open weak var delegate: (any AVAudioRecorderDelegate)?

    /// `settings` are AVAudioSettings keys; the format must be linear PCM. An existing file
    /// at `url` is replaced when recording is prepared.
    public init(url: URL, settings: [String: Any]) throws {
        _url = url
        _settings = settings
        guard let format = AVAudioFormat(settings: settings), format.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM else {
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioRecorder: only linear PCM can be recorded here (settings \(settings))")
        }
        switch url.pathExtension.lowercased() {
        case "wav", "wave", "aif", "aiff", "aifc", "caf", "caff": break
        default: throw _osStatusError(kAudioFileUnsupportedFileTypeError, "AVAudioRecorder: unsupported file type .\(url.pathExtension)")
        }
        _fileFormat = format
        let channels = Int(format.channelCount)
        peak = Array(repeating: -160, count: channels); average = peak; meterPeak = peak; meterAverage = peak
        super.init()
    }

    public convenience init(url: URL, format: AVAudioFormat) throws {
        try self.init(url: url, settings: format.settings)
    }

    deinit {
        _stopWriter()
        _teardown()
    }

    open var url: URL { _url }
    open var settings: [String: Any] { lock.withLock { file?.fileFormat.settings ?? _settings } }
    open var format: AVAudioFormat { lock.withLock { file?.fileFormat ?? _fileFormat } }
    open var isRecording: Bool { lock.withLock { _isRecording } }

    /// Seconds recorded so far (zero once stopped).
    open var currentTime: TimeInterval {
        lock.withLock { file == nil ? 0 : Double(framesWritten) / _fileFormat.sampleRate }
    }

    /// The input clock in seconds (wall-clock time since the stream started, or zero).
    open var deviceCurrentTime: TimeInterval {
        lock.withLock { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }
    }

    // MARK: Recording

    /// Creates the file and opens the input stream.
    open func prepareToRecord() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if file != nil { return true }
        do {
            try? FileManager.default.removeItem(at: _url)
            let f = try AVAudioFile(forWriting: _url, settings: _settings)
            guard let backend = PlatformAudio.backend as? any PlatformAudioInputBackend else {
                throw PlatformAudioError("\(PlatformAudio.backend.name) has no audio input")
            }
            let capture = _FrameRingBox()
            let s = try backend.openInputStream(device: nil, sampleRate: _fileFormat.sampleRate, channelCount: nil) { [capturing] input, frames in
                guard capturing.value, let ring = capture.ring else { return }
                ring.writeInterleaved(input, frames: frames)
                capture.signal?.signal()
            }
            let sf = AVAudioFormat(standardFormatWithSampleRate: s.sampleRate, channels: AVAudioChannelCount(s.channelCount))!
            let r = _FrameRing(channels: s.channelCount, capacity: max(65536, Int(s.sampleRate)))
            capture.ring = r
            capture.signal = wake
            guard let conv = AVAudioConverter(from: sf, to: f.processingFormat) else {
                throw PlatformAudioError("cannot convert \(sf) to \(f.processingFormat)")
            }
            if sf.channelCount > f.processingFormat.channelCount { conv.downmix = true }
            file = f
            stream = s
            streamFormat = sf
            ring = r
            converter = conv
            framesWritten = 0
            try s.start()
            startedAt = Date()
            _startWriter()
            return true
        } catch {
            if ProcessInfo.processInfo.environment["APPKITWIN_AUDIO_LOG"] != nil {
                FileHandle.standardError.write("AppKitCross audio: AVAudioRecorder.prepareToRecord: \(error)\n".data(using: .utf8)!)
            }
            _teardown()
            return false
        }
    }

    @discardableResult
    open func record() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepareToRecord() else { return false }
        _isRecording = true
        capturing.value = true
        return true
    }

    /// Starts at `time` on `deviceCurrentTime`'s clock.
    @discardableResult
    open func record(atTime time: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard prepareToRecord() else { return false }
        let delay = time - deviceCurrentTime
        if delay <= 0 { return record() }
        delayedStart?.cancel()
        let item = DispatchWorkItem { [weak self] in _ = self?.record() }
        delayedStart = item
        DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
        return true
    }

    @discardableResult
    open func record(forDuration duration: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        stopAfterFrames = Int64(max(0, duration) * _fileFormat.sampleRate)
        return record()
    }

    @discardableResult
    open func record(atTime time: TimeInterval, forDuration duration: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        stopAfterFrames = Int64(max(0, duration) * _fileFormat.sampleRate)
        return record(atTime: time)
    }

    /// Stops capturing into the file; `record()` continues the same file.
    open func pause() {
        lock.lock(); defer { lock.unlock() }
        delayedStart?.cancel()
        _isRecording = false
        capturing.value = false
    }

    /// Stops, finishes the file and tells the delegate.
    open func stop() {
        lock.lock()
        delayedStart?.cancel()
        _isRecording = false
        capturing.value = false
        lock.unlock()
        _stopWriter()
        lock.lock()
        let wasPrepared = file != nil
        _teardown()
        let delegate = self.delegate
        let error = encodeError
        lock.unlock()
        guard wasPrepared else { return }
        DispatchQueue.main.async {
            if let error { delegate?.audioRecorderEncodeErrorDidOccur(self, error: error) }
            delegate?.audioRecorderDidFinishRecording(self, successfully: error == nil)
        }
    }

    /// Deletes the file; the recorder must be stopped.
    open func deleteRecording() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !_isRecording, file == nil else { return false }
        do { try FileManager.default.removeItem(at: _url); return true } catch { return false }
    }

    /// Ends the writer thread (call without holding `lock`: the thread takes it).
    private func _stopWriter() {
        guard writerRunning.value else { return }
        writerRunning.value = false
        wake.signal()
        writerDone.wait()
    }

    /// Stops the stream, drains what it captured into the file and closes it (the writer
    /// thread has ended).
    private func _teardown() {
        _isRecording = false
        capturing.value = false
        stream?.stop()
        stream?.close()
        stream = nil
        writer = nil
        _drain(final: true)
        file?.close()
        file = nil
        ring = nil
        converter = nil
        startedAt = nil
        stopAfterFrames = -1
    }

    // MARK: The writer thread

    private func _startWriter() {
        writerRunning.value = true
        let t = Thread { [weak self] in
            while let self, self.writerRunning.value {
                _ = self.wake.wait(timeout: .now() + .milliseconds(20))
                self.lock.lock()
                if self.writerRunning.value { self._drain(final: false) }
                let limitReached = self.stopAfterFrames >= 0 && self.framesWritten >= self.stopAfterFrames
                self.lock.unlock()
                if limitReached { DispatchQueue.global().async { [weak self] in self?.stop() }; break }
            }
            self?.writerDone.signal()
        }
        t.name = "AVAudioRecorder writer"
        t.qualityOfService = .userInitiated
        writer = t
        t.start()
    }

    /// Moves captured frames through the converter into the file (under `lock`).
    private func _drain(final: Bool) {
        guard let ring, let converter, let file, let sf = streamFormat else { return }
        let chunk = 4096
        let input = AVAudioPCMBuffer(pcmFormat: sf, frameCapacity: AVAudioFrameCount(chunk))!
        let ratio = file.processingFormat.sampleRate / sf.sampleRate
        let output = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(Double(chunk) * ratio) + 64)!
        final class Supply: @unchecked Sendable { var buffer: AVAudioPCMBuffer?; var end = false }
        while true {
            let n = min(chunk, ring.count)
            let supply = Supply()
            if n > 0 {
                _ = ring.read(into: input.floatChannelData!, frames: n)
                input.frameLength = AVAudioFrameCount(n)
                supply.buffer = input
            } else if final {
                supply.end = true
            } else {
                return
            }
            var error: NSError?
            var guardCount = 0
            repeat {
                let status = converter.convert(to: output, error: &error) { _, outStatus in
                    if let b = supply.buffer { supply.buffer = nil; outStatus.pointee = .haveData; return b }
                    outStatus.pointee = supply.end ? .endOfStream : .noDataNow
                    return nil
                }
                if status == .error { encodeError = error; return }
                if output.frameLength > 0 {
                    if stopAfterFrames >= 0 { output.frameLength = AVAudioFrameCount(max(0, min(Int64(output.frameLength), stopAfterFrames - framesWritten))) }
                    _meter(output)
                    do { try file.write(from: output) } catch { encodeError = error; return }
                    framesWritten += Int64(output.frameLength)
                }
                guardCount += 1
                if status == .endOfStream || status == .inputRanDry || guardCount > 64 { break }
            } while true
            if supply.end { return }
        }
    }

    private func _meter(_ buffer: AVAudioPCMBuffer) {
        guard _meteringEnabled, let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        for c in 0..<min(peak.count, Int(buffer.format.channelCount)) {
            var p: Float = 0, sum: Float = 0
            for i in 0..<n { let v = abs(data[c][i]); p = max(p, v); sum += v * v }
            peak[c] = p > 0 ? 20 * log10(p) : -160
            let r = (sum / Float(n)).squareRoot()
            average[c] = r > 0 ? 20 * log10(r) : -160
        }
    }

    // MARK: Metering

    open var isMeteringEnabled: Bool {
        get { lock.withLock { _meteringEnabled } }
        set { lock.withLock { _meteringEnabled = newValue } }
    }

    open func updateMeters() {
        lock.lock(); defer { lock.unlock() }
        meterPeak = peak; meterAverage = average
    }

    /// Decibels full scale, -160 for silence.
    open func peakPower(forChannel channelNumber: Int) -> Float {
        lock.withLock { channelNumber < meterPeak.count ? meterPeak[channelNumber] : -160 }
    }

    open func averagePower(forChannel channelNumber: Int) -> Float {
        lock.withLock { channelNumber < meterAverage.count ? meterAverage[channelNumber] : -160 }
    }
}

/// The capture callback's view of the recorder's ring (set once the stream reports its
/// format, before it starts).
private final class _FrameRingBox: @unchecked Sendable {
    var ring: _FrameRing?
    var signal: DispatchSemaphore?
}
