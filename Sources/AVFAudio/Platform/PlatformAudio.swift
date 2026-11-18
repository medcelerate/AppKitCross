// The seam between the audio engine and the operating system's audio output: device
// enumeration and an event-driven output stream that pulls interleaved Float32 from a
// render callback. WASAPI, PipeWire and ALSA implement it; the null backend renders into
// the void on a timer, for machines without a device and for tests.

import Foundation

public struct PlatformAudioDevice: Sendable, Equatable {
    public var id: String
    public var name: String
    public var sampleRate: Double
    public var channelCount: Int
    public var isDefault: Bool
    public init(id: String, name: String, sampleRate: Double, channelCount: Int, isDefault: Bool) {
        self.id = id; self.name = name; self.sampleRate = sampleRate; self.channelCount = channelCount; self.isDefault = isDefault
    }
}

/// Fills `frameCount` frames of interleaved Float32 (the stream's channel count). Runs on
/// the backend's audio thread: no allocation, no locks.
public typealias PlatformAudioRenderCallback = (_ output: UnsafeMutablePointer<Float>, _ frameCount: Int) -> Void

public struct PlatformAudioError: Error, CustomStringConvertible {
    public var message: String
    public var code: Int
    public init(_ message: String, code: Int = 0) { self.message = message; self.code = code }
    public var description: String { message }
    public var localizedDescription: String { message }
}

public protocol PlatformAudioBackend: AnyObject {
    /// "WASAPI", "PipeWire", "ALSA" or "Null".
    var name: String { get }
    func outputDevices() throws -> [PlatformAudioDevice]
    func defaultOutputDevice() throws -> PlatformAudioDevice?
    /// Opens an output stream on `device` (nil: the default). The backend picks the format
    /// closest to the request (nil: the device's own) and reports it on the stream.
    func openOutputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, render: @escaping PlatformAudioRenderCallback) throws -> any PlatformAudioOutputStream
}

/// Receives `frameCount` frames of interleaved Float32 (the stream's channel count) on the
/// backend's capture thread: no allocation, no locks.
public typealias PlatformAudioCaptureCallback = (_ input: UnsafePointer<Float>, _ frameCount: Int) -> Void

/// What changed in the system's device configuration.
public enum PlatformAudioDeviceChange: Sendable, Equatable {
    /// The default output (or input, `isInput`) endpoint is now `id` (empty: none).
    case defaultDeviceChanged(isInput: Bool, id: String)
    /// A device appeared.
    case deviceAdded(id: String)
    /// A device was unplugged, disabled or removed.
    case deviceRemoved(id: String)
}

/// Input capture and device notifications. Backends without them keep the defaults:
/// no input devices, and no notifications.
public protocol PlatformAudioInputBackend: PlatformAudioBackend {
    func inputDevices() throws -> [PlatformAudioDevice]
    func defaultInputDevice() throws -> PlatformAudioDevice?
    /// Opens a capture stream on `device` (nil: the default input).
    func openInputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, capture: @escaping PlatformAudioCaptureCallback) throws -> any PlatformAudioInputStream
    /// Installs (nil removes) the handler for device changes; it runs on a thread of the
    /// backend's, so it must not block.
    func setDeviceChangeHandler(_ handler: (@Sendable (PlatformAudioDeviceChange) -> Void)?)
}

public protocol PlatformAudioInputStream: AnyObject {
    var deviceName: String { get }
    var sampleRate: Double { get }
    var channelCount: Int { get }
    /// Frames per capture callback (the device period).
    var bufferFrameCount: Int { get }
    /// Capture latency from the microphone to the callback, in seconds.
    var latency: TimeInterval { get }
    func start() throws
    /// Returns once no capture callback is running.
    func stop()
    func close()
}

public protocol PlatformAudioOutputStream: AnyObject {
    var deviceName: String { get }
    var sampleRate: Double { get }
    var channelCount: Int { get }
    /// Frames per render callback (the device period).
    var bufferFrameCount: Int { get }
    /// Output latency from the render callback to the speaker, in seconds.
    var latency: TimeInterval { get }
    func start() throws
    /// Returns once no render callback is running; `start()` may follow.
    func stop()
    func close()
}

public enum PlatformAudio {
    private static let lock = NSLock()
    private static var _backend: (any PlatformAudioBackend)?

    /// The backend in use: the platform's native one unless `APPKITWIN_AUDIO_BACKEND`
    /// names another (`null`, `wasapi`, `pipewire`, `alsa`). Settable for tests.
    public static var backend: any PlatformAudioBackend {
        get {
            lock.lock(); defer { lock.unlock() }
            if let b = _backend { return b }
            let b = makeDefaultBackend()
            _backend = b
            return b
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _backend = newValue
        }
    }

    static func makeDefaultBackend() -> any PlatformAudioBackend {
        let requested = ProcessInfo.processInfo.environment["APPKITWIN_AUDIO_BACKEND"]?.lowercased()
        if requested == "null" { return NullAudioBackend() }
        // Platform checks, not canImport: a client built with every shim's module map on
        // the search path (tools/library-compat.sh) would otherwise compile the other
        // platform's backend and fail to link it.
        #if os(Windows)
        if requested == nil || requested == "wasapi" { return WASAPIAudioBackend() }
        #endif
        #if os(Linux)
        if requested == nil || requested == "pipewire", let pw = PipeWireAudioBackend.makeIfAvailable() { return pw }
        if requested == nil || requested == "alsa", let alsa = ALSAAudioBackend.makeIfAvailable() { return alsa }
        #endif
        if let requested, requested != "null" {
            FileHandle.standardError.write("AppKitCross audio: backend '\(requested)' is unavailable, using the null backend\n".data(using: .utf8)!)
        }
        return NullAudioBackend()
    }
}

/// Renders into a scratch buffer on a timer thread: the engine runs and time passes, but
/// nothing is heard. Two outputs ("null" and "null-2", for device selection) and one input
/// that captures a 440 Hz sine at amplitude 0.25 (so recording and metering have a known
/// signal on machines without a microphone).
public final class NullAudioBackend: PlatformAudioInputBackend {
    public init() {}
    public var name: String { "Null" }
    public let device = PlatformAudioDevice(id: "null", name: "Null Output", sampleRate: 48000, channelCount: 2, isDefault: true)
    public let secondDevice = PlatformAudioDevice(id: "null-2", name: "Null Output 2", sampleRate: 44100, channelCount: 2, isDefault: false)
    public let inputDevice = PlatformAudioDevice(id: "null-in", name: "Null Input", sampleRate: 48000, channelCount: 1, isDefault: true)
    private let lock = NSLock()
    private var handler: (@Sendable (PlatformAudioDeviceChange) -> Void)?
    private var removed: Set<String> = []

    public func outputDevices() throws -> [PlatformAudioDevice] {
        lock.lock(); defer { lock.unlock() }
        return [device, secondDevice].filter { !removed.contains($0.id) }
    }
    public func defaultOutputDevice() throws -> PlatformAudioDevice? { device }
    public func openOutputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, render: @escaping PlatformAudioRenderCallback) throws -> any PlatformAudioOutputStream {
        let target = device ?? self.device
        lock.lock(); let gone = removed.contains(target.id); lock.unlock()
        if gone { throw PlatformAudioError("Null: \(target.name) was removed") }
        return NullOutputStream(deviceName: target.name, sampleRate: sampleRate ?? target.sampleRate, channelCount: channelCount ?? target.channelCount, render: render)
    }

    public func inputDevices() throws -> [PlatformAudioDevice] { [inputDevice] }
    public func defaultInputDevice() throws -> PlatformAudioDevice? { inputDevice }
    public func openInputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, capture: @escaping PlatformAudioCaptureCallback) throws -> any PlatformAudioInputStream {
        NullInputStream(sampleRate: sampleRate ?? inputDevice.sampleRate, channelCount: channelCount ?? inputDevice.channelCount, capture: capture)
    }

    public func setDeviceChangeHandler(_ handler: (@Sendable (PlatformAudioDeviceChange) -> Void)?) {
        lock.lock(); self.handler = handler; lock.unlock()
    }

    /// Delivers `change` as a device would (tests): a removed device stops opening.
    public func simulate(_ change: PlatformAudioDeviceChange) {
        lock.lock()
        if case .deviceRemoved(let id) = change { removed.insert(id) }
        if case .deviceAdded(let id) = change { removed.remove(id) }
        let h = handler
        lock.unlock()
        h?(change)
    }

    /// A thread that calls `body` every `frames` frames of wall-clock time until stopped.
    final class PeriodicThread {
        private let running = _AtomicBool(false)
        private var thread: Thread?
        private let finished = DispatchSemaphore(value: 0)

        func start(name: String, period: Double, body: @escaping () -> Void) {
            guard !running.value else { return }
            running.value = true
            let t = Thread { [self] in
                var next = Date()
                while running.value {
                    body()
                    next = next.addingTimeInterval(period)
                    let wait = next.timeIntervalSinceNow
                    if wait > 0 { Thread.sleep(forTimeInterval: wait) } else { next = Date() }
                }
                finished.signal()
            }
            t.name = name
            t.qualityOfService = .userInteractive
            thread = t
            t.start()
        }

        func stop() {
            guard running.value else { return }
            running.value = false
            finished.wait()
            thread = nil
        }
    }

    public final class NullOutputStream: PlatformAudioOutputStream {
        public let deviceName: String
        public let sampleRate: Double
        public let channelCount: Int
        public let bufferFrameCount = 480
        public var latency: TimeInterval { Double(bufferFrameCount) * 2 / sampleRate }
        private let render: PlatformAudioRenderCallback
        private let thread = PeriodicThread()
        private let buffer: UnsafeMutablePointer<Float>
        /// Everything rendered so far, when `recording` is on (tests).
        public var recording = false
        public private(set) var recorded: [Float] = []
        private let recordLock = NSLock()

        init(deviceName: String, sampleRate: Double, channelCount: Int, render: @escaping PlatformAudioRenderCallback) {
            self.deviceName = deviceName; self.sampleRate = sampleRate; self.channelCount = channelCount; self.render = render
            buffer = .allocate(capacity: 480 * channelCount)
        }
        deinit { thread.stop(); buffer.deallocate() }

        public func start() throws {
            thread.start(name: "AVFAudio null output", period: Double(bufferFrameCount) / sampleRate) { [self] in
                render(buffer, bufferFrameCount)
                if recording {
                    recordLock.lock()
                    recorded.append(contentsOf: UnsafeBufferPointer(start: buffer, count: bufferFrameCount * channelCount))
                    recordLock.unlock()
                }
            }
        }

        public func stop() { thread.stop() }
        public func close() { stop() }
    }

    public final class NullInputStream: PlatformAudioInputStream {
        public let deviceName = "Null Input"
        public let sampleRate: Double
        public let channelCount: Int
        public let bufferFrameCount = 480
        public var latency: TimeInterval { Double(bufferFrameCount) / sampleRate }
        private let capture: PlatformAudioCaptureCallback
        private let thread = PeriodicThread()
        private let buffer: UnsafeMutablePointer<Float>
        private var phase: Double = 0

        init(sampleRate: Double, channelCount: Int, capture: @escaping PlatformAudioCaptureCallback) {
            self.sampleRate = sampleRate; self.channelCount = channelCount; self.capture = capture
            buffer = .allocate(capacity: 480 * max(1, channelCount))
        }
        deinit { thread.stop(); buffer.deallocate() }

        public func start() throws {
            thread.start(name: "AVFAudio null input", period: Double(bufferFrameCount) / sampleRate) { [self] in
                let step = 2 * Double.pi * 440 / sampleRate
                for f in 0..<bufferFrameCount {
                    let v = Float(0.25 * sin(phase))
                    phase += step
                    if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                    for c in 0..<channelCount { buffer[f * channelCount + c] = v }
                }
                capture(buffer, bufferFrameCount)
            }
        }

        public func stop() { thread.stop() }
        public func close() { stop() }
    }
}
