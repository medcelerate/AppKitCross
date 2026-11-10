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
/// nothing is heard.
public final class NullAudioBackend: PlatformAudioBackend {
    public init() {}
    public var name: String { "Null" }
    public let device = PlatformAudioDevice(id: "null", name: "Null Output", sampleRate: 48000, channelCount: 2, isDefault: true)
    public func outputDevices() throws -> [PlatformAudioDevice] { [device] }
    public func defaultOutputDevice() throws -> PlatformAudioDevice? { device }
    public func openOutputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, render: @escaping PlatformAudioRenderCallback) throws -> any PlatformAudioOutputStream {
        NullOutputStream(sampleRate: sampleRate ?? self.device.sampleRate, channelCount: channelCount ?? self.device.channelCount, render: render)
    }

    public final class NullOutputStream: PlatformAudioOutputStream {
        public let deviceName = "Null Output"
        public let sampleRate: Double
        public let channelCount: Int
        public let bufferFrameCount = 480
        public var latency: TimeInterval { Double(bufferFrameCount) * 2 / sampleRate }
        private let render: PlatformAudioRenderCallback
        private let running = _AtomicBool(false)
        private var thread: Thread?
        private let finished = DispatchSemaphore(value: 0)
        private let buffer: UnsafeMutablePointer<Float>
        /// Everything rendered so far, when `recording` is on (tests).
        public var recording = false
        public private(set) var recorded: [Float] = []
        private let recordLock = NSLock()

        init(sampleRate: Double, channelCount: Int, render: @escaping PlatformAudioRenderCallback) {
            self.sampleRate = sampleRate; self.channelCount = channelCount; self.render = render
            buffer = .allocate(capacity: 480 * channelCount)
        }
        deinit { buffer.deallocate() }

        public func start() throws {
            guard !running.value else { return }
            running.value = true
            let t = Thread { [self] in
                let period = Double(bufferFrameCount) / sampleRate
                var next = Date()
                while running.value {
                    render(buffer, bufferFrameCount)
                    if recording {
                        recordLock.lock()
                        recorded.append(contentsOf: UnsafeBufferPointer(start: buffer, count: bufferFrameCount * channelCount))
                        recordLock.unlock()
                    }
                    next = next.addingTimeInterval(period)
                    let wait = next.timeIntervalSinceNow
                    if wait > 0 { Thread.sleep(forTimeInterval: wait) } else { next = Date() }
                }
                finished.signal()
            }
            t.name = "AVFAudio null output"
            t.qualityOfService = .userInteractive
            thread = t
            t.start()
        }

        public func stop() {
            guard running.value else { return }
            running.value = false
            finished.wait()
            thread = nil
        }

        public func close() { stop() }
    }
}
