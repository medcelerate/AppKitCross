// The PipeWire output and capture backend (Linux), over the CPipeWire shim, with device
// notifications from a registry listener and the "default" metadata.

#if os(Linux)
import Foundation
import CPipeWire

final class PipeWireAudioBackend: PlatformAudioInputBackend {
    var name: String { "PipeWire" }

    /// Nil when the library or the daemon is missing (the reason goes to stderr once).
    static func makeIfAvailable() -> PipeWireAudioBackend? {
        var error = [CChar](repeating: 0, count: 256)
        guard cpw_available(&error, error.count) else {
            if ProcessInfo.processInfo.environment["APPKITWIN_AUDIO_LOG"] != nil {
                FileHandle.standardError.write("AppKitCross audio: PipeWire unavailable: \(String(cString: error))\n".data(using: .utf8)!)
            }
            return nil
        }
        return PipeWireAudioBackend()
    }

    private static func string<T>(_ value: inout T) -> String {
        withUnsafePointer(to: &value) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
    }

    private static func defaultName(_ get: (UnsafeMutablePointer<CChar>?, Int) -> Void) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        get(&buffer, buffer.count)
        return String(cString: buffer)
    }

    /// Sinks (or sources) from one registry round trip; the default comes from the
    /// "default" metadata, or is the first when the metadata is missing.
    private func nodes(input: Bool) -> [PlatformAudioDevice] {
        let count = input ? cpw_source_count() : cpw_sink_count()
        let defaultName = Self.defaultName { input ? cpw_default_source_name($0, $1) : cpw_default_sink_name($0, $1) }
        var devices: [PlatformAudioDevice] = []
        for i in 0..<count {
            var info = CPWSinkInfo()
            guard input ? cpw_source(i, &info) : cpw_sink(i, &info) else { continue }
            let name = Self.string(&info.name)
            let description = Self.string(&info.description)
            devices.append(PlatformAudioDevice(id: name, name: description.isEmpty ? name : description,
                                               sampleRate: Double(info.sampleRate == 0 ? 48000 : info.sampleRate),
                                               channelCount: Int(info.channels == 0 ? (input ? 1 : 2) : info.channels),
                                               isDefault: defaultName.isEmpty ? i == 0 : name == defaultName))
        }
        return devices
    }

    func outputDevices() throws -> [PlatformAudioDevice] { nodes(input: false) }

    func defaultOutputDevice() throws -> PlatformAudioDevice? {
        let devices = nodes(input: false)
        return devices.first { $0.isDefault } ?? devices.first ?? PlatformAudioDevice(id: "", name: "PipeWire default sink", sampleRate: 48000, channelCount: 2, isDefault: true)
    }

    /// `device` nil (or the default) connects with no target, so PipeWire moves the stream
    /// along when the default changes; an explicit device pins it to that node.
    func openOutputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, render: @escaping PlatformAudioRenderCallback) throws -> any PlatformAudioOutputStream {
        try PipeWireOutputStream(target: device?.id, rate: UInt32(sampleRate ?? 48000), channels: UInt32(channelCount ?? 2), render: render)
    }

    func inputDevices() throws -> [PlatformAudioDevice] { nodes(input: true) }

    func defaultInputDevice() throws -> PlatformAudioDevice? {
        let devices = nodes(input: true)
        return devices.first { $0.isDefault } ?? devices.first
    }

    func openInputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, capture: @escaping PlatformAudioCaptureCallback) throws -> any PlatformAudioInputStream {
        try PipeWireInputStream(target: device?.id, rate: UInt32(sampleRate ?? 48000), channels: UInt32(channelCount ?? 0), capture: capture)
    }

    private let watchLock = NSLock()
    private var watchHandler: (@Sendable (PlatformAudioDeviceChange) -> Void)?
    private var watching = false
    private var watchContext: Unmanaged<PipeWireAudioBackend>?

    func setDeviceChangeHandler(_ handler: (@Sendable (PlatformAudioDeviceChange) -> Void)?) {
        watchLock.lock(); defer { watchLock.unlock() }
        watchHandler = handler
        let callback: cpw_device_fn = { context, event, name in
            guard let context else { return }
            let backend = Unmanaged<PipeWireAudioBackend>.fromOpaque(context).takeUnretainedValue()
            let id = name.map { String(cString: $0) } ?? ""
            let change: PlatformAudioDeviceChange
            switch event {
            case CPW_DEFAULT_SINK_CHANGED: change = .defaultDeviceChanged(isInput: false, id: id)
            case CPW_DEFAULT_SOURCE_CHANGED: change = .defaultDeviceChanged(isInput: true, id: id)
            case CPW_DEVICE_ADDED: change = .deviceAdded(id: id)
            default: change = .deviceRemoved(id: id)
            }
            backend.watchLock.lock(); let h = backend.watchHandler; backend.watchLock.unlock()
            h?(change)
        }
        if handler != nil && !watching {
            // The watch holds the backend until it is removed.
            let context = Unmanaged.passRetained(self)
            watching = cpw_watch_devices(callback, context.toOpaque())
            if watching { watchContext = context } else { context.release() }
        } else if handler == nil && watching {
            _ = cpw_watch_devices(nil, nil)
            watching = false
            watchContext?.release()
            watchContext = nil
        }
    }
}

final class PipeWireOutputStream: PlatformAudioOutputStream {
    private var stream: OpaquePointer?
    private let render: PlatformAudioRenderCallback
    private var info = CPWStreamInfo()

    init(target: String?, rate: UInt32, channels: UInt32, render: @escaping PlatformAudioRenderCallback) throws {
        self.render = render
        var error = [CChar](repeating: 0, count: 256)
        let callback: cpw_render_fn = { context, out, frames in
            guard let context, let out else { return }
            let stream = Unmanaged<PipeWireOutputStream>.fromOpaque(context).takeUnretainedValue()
            stream.render(out, Int(frames))
        }
        guard let s = cpw_open_target(target, rate, channels, callback, Unmanaged.passUnretained(self).toOpaque(), &error, error.count) else {
            throw PlatformAudioError("PipeWire: \(String(cString: error))")
        }
        stream = s
        cpw_stream_info(s, &info)
    }

    deinit { close() }

    var deviceName: String { withUnsafePointer(to: &info.target) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) } }
    var sampleRate: Double { info.sampleRate }
    var channelCount: Int { Int(info.channels) }
    var bufferFrameCount: Int { Int(info.quantumFrames) }
    var latency: TimeInterval {
        if let stream { cpw_stream_info(stream, &info) }
        return info.latencySeconds
    }

    func start() throws {
        guard let stream else { throw PlatformAudioError("PipeWire: the stream is closed") }
        var error = [CChar](repeating: 0, count: 256)
        guard cpw_start(stream, &error, error.count) else { throw PlatformAudioError("PipeWire: \(String(cString: error))") }
        cpw_stream_info(stream, &info)
    }

    func stop() { if let stream { cpw_stop(stream) } }

    func close() {
        if let stream { cpw_close(stream) }
        stream = nil
    }
}
final class PipeWireInputStream: PlatformAudioInputStream {
    private var stream: OpaquePointer?
    private let capture: PlatformAudioCaptureCallback
    private var info = CPWStreamInfo()

    init(target: String?, rate: UInt32, channels: UInt32, capture: @escaping PlatformAudioCaptureCallback) throws {
        self.capture = capture
        var error = [CChar](repeating: 0, count: 256)
        let callback: cpw_capture_fn = { context, input, frames in
            guard let context, let input else { return }
            let stream = Unmanaged<PipeWireInputStream>.fromOpaque(context).takeUnretainedValue()
            stream.capture(input, Int(frames))
        }
        guard let s = cpw_open_capture(target, rate, channels, callback, Unmanaged.passUnretained(self).toOpaque(), &error, error.count) else {
            throw PlatformAudioError("PipeWire: \(String(cString: error))")
        }
        stream = s
        cpw_stream_info(s, &info)
    }

    deinit { close() }

    var deviceName: String { withUnsafePointer(to: &info.target) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) } }
    var sampleRate: Double { info.sampleRate }
    var channelCount: Int { Int(info.channels) }
    var bufferFrameCount: Int { Int(info.quantumFrames) }
    var latency: TimeInterval {
        if let stream { cpw_stream_info(stream, &info) }
        return info.latencySeconds
    }

    func start() throws {
        guard let stream else { throw PlatformAudioError("PipeWire: the capture stream is closed") }
        var error = [CChar](repeating: 0, count: 256)
        guard cpw_start(stream, &error, error.count) else { throw PlatformAudioError("PipeWire: \(String(cString: error))") }
        cpw_stream_info(stream, &info)
    }

    func stop() { if let stream { cpw_stop(stream) } }

    func close() {
        if let stream { cpw_close(stream) }
        stream = nil
    }
}
#endif
