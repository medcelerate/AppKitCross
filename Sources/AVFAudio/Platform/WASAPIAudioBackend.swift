// The WASAPI output and capture backend (Windows), over the CWASAPI shim, with endpoint
// notifications from IMMNotificationClient.

#if os(Windows)
import Foundation
import CWASAPI

final class WASAPIAudioBackend: PlatformAudioInputBackend {
    var name: String { "WASAPI" }

    private func errorText(_ buffer: [CChar]) -> String { String(cString: buffer) }

    private static func device(_ info: inout CWASAPIDeviceInfo, isDefault: Bool? = nil) -> PlatformAudioDevice {
        PlatformAudioDevice(id: withUnsafePointer(to: &info.id) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) },
                            name: withUnsafePointer(to: &info.name) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) },
                            sampleRate: info.sampleRate, channelCount: Int(info.channels), isDefault: isDefault ?? info.isDefault)
    }

    func inputDevices() throws -> [PlatformAudioDevice] {
        var error = [CChar](repeating: 0, count: 256)
        let count = cwasapi_input_device_count(&error, error.count)
        if count == 0 && error[0] != 0 { throw PlatformAudioError("WASAPI: \(errorText(error))") }
        var devices: [PlatformAudioDevice] = []
        for i in 0..<count {
            var info = CWASAPIDeviceInfo()
            guard cwasapi_input_device(i, &info) else { continue }
            devices.append(Self.device(&info))
        }
        return devices
    }

    func defaultInputDevice() throws -> PlatformAudioDevice? {
        var info = CWASAPIDeviceInfo()
        var error = [CChar](repeating: 0, count: 256)
        guard cwasapi_default_input_device(&info, &error, error.count) else { return nil }
        return Self.device(&info, isDefault: true)
    }

    func openInputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, capture: @escaping PlatformAudioCaptureCallback) throws -> any PlatformAudioInputStream {
        try WASAPIInputStream(deviceID: device?.id, capture: capture)
    }

    private let watchLock = NSLock()
    private var watchHandler: (@Sendable (PlatformAudioDeviceChange) -> Void)?
    private var watching = false
    private var watchContext: Unmanaged<WASAPIAudioBackend>?

    func setDeviceChangeHandler(_ handler: (@Sendable (PlatformAudioDeviceChange) -> Void)?) {
        watchLock.lock(); defer { watchLock.unlock() }
        watchHandler = handler
        let callback: cwasapi_device_fn = { context, event, id in
            guard let context else { return }
            let backend = Unmanaged<WASAPIAudioBackend>.fromOpaque(context).takeUnretainedValue()
            let deviceID = id.map { String(cString: $0) } ?? ""
            let change: PlatformAudioDeviceChange
            switch event {
            case CWASAPI_DEFAULT_OUTPUT_CHANGED: change = .defaultDeviceChanged(isInput: false, id: deviceID)
            case CWASAPI_DEFAULT_INPUT_CHANGED: change = .defaultDeviceChanged(isInput: true, id: deviceID)
            case CWASAPI_DEVICE_ADDED: change = .deviceAdded(id: deviceID)
            default: change = .deviceRemoved(id: deviceID)
            }
            backend.watchLock.lock(); let h = backend.watchHandler; backend.watchLock.unlock()
            h?(change)
        }
        if handler != nil && !watching {
            // The watch holds the backend until it is removed.
            let context = Unmanaged.passRetained(self)
            watching = cwasapi_watch_devices(callback, context.toOpaque())
            if watching { watchContext = context } else { context.release() }
        } else if handler == nil && watching {
            _ = cwasapi_watch_devices(nil, nil)
            watching = false
            watchContext?.release()
            watchContext = nil
        }
    }

    func outputDevices() throws -> [PlatformAudioDevice] {
        var error = [CChar](repeating: 0, count: 256)
        let count = cwasapi_output_device_count(&error, error.count)
        if count == 0 && error[0] != 0 { throw PlatformAudioError("WASAPI: \(errorText(error))") }
        var devices: [PlatformAudioDevice] = []
        for i in 0..<count {
            var info = CWASAPIDeviceInfo()
            guard cwasapi_output_device(i, &info) else { continue }
            devices.append(PlatformAudioDevice(id: withUnsafePointer(to: &info.id) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) },
                                               name: withUnsafePointer(to: &info.name) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) },
                                               sampleRate: info.sampleRate, channelCount: Int(info.channels), isDefault: info.isDefault))
        }
        return devices
    }

    func defaultOutputDevice() throws -> PlatformAudioDevice? {
        var info = CWASAPIDeviceInfo()
        var error = [CChar](repeating: 0, count: 256)
        guard cwasapi_default_output_device(&info, &error, error.count) else { return nil }
        return PlatformAudioDevice(id: withUnsafePointer(to: &info.id) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) },
                                   name: withUnsafePointer(to: &info.name) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) },
                                   sampleRate: info.sampleRate, channelCount: Int(info.channels), isDefault: true)
    }

    func openOutputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, render: @escaping PlatformAudioRenderCallback) throws -> any PlatformAudioOutputStream {
        try WASAPIOutputStream(deviceID: device?.id, render: render)
    }
}

final class WASAPIOutputStream: PlatformAudioOutputStream {
    private var stream: OpaquePointer?
    private let render: PlatformAudioRenderCallback
    private var info = CWASAPIStreamInfo()
    private var context: Unmanaged<WASAPIOutputStream>?

    init(deviceID: String?, render: @escaping PlatformAudioRenderCallback) throws {
        self.render = render
        var error = [CChar](repeating: 0, count: 256)
        let ctx = Unmanaged.passUnretained(self)
        context = ctx
        let callback: cwasapi_render_fn = { context, out, frames in
            guard let context, let out else { return }
            let stream = Unmanaged<WASAPIOutputStream>.fromOpaque(context).takeUnretainedValue()
            stream.render(out, Int(frames))
        }
        guard let s = cwasapi_open(deviceID, callback, ctx.toOpaque(), &error, error.count) else {
            throw PlatformAudioError("WASAPI: \(String(cString: error))")
        }
        stream = s
        cwasapi_stream_info(s, &info)
    }

    deinit { close() }

    var deviceName: String { withUnsafePointer(to: &info.deviceName) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) } }
    var sampleRate: Double { info.sampleRate }
    var channelCount: Int { Int(info.channels) }
    var bufferFrameCount: Int { Int(info.periodFrames) }
    var latency: TimeInterval { info.latencySeconds }
    /// Whether IAudioClient3's low-latency shared-mode period is in use.
    var isLowLatency: Bool { info.lowLatency }

    func start() throws {
        guard let stream else { throw PlatformAudioError("WASAPI: the stream is closed") }
        var error = [CChar](repeating: 0, count: 256)
        guard cwasapi_start(stream, &error, error.count) else { throw PlatformAudioError("WASAPI: \(String(cString: error))") }
    }

    func stop() { if let stream { cwasapi_stop(stream) } }

    func close() {
        if let stream { cwasapi_close(stream) }
        stream = nil
    }
}
final class WASAPIInputStream: PlatformAudioInputStream {
    private var stream: OpaquePointer?
    private let capture: PlatformAudioCaptureCallback
    private var info = CWASAPIStreamInfo()

    init(deviceID: String?, capture: @escaping PlatformAudioCaptureCallback) throws {
        self.capture = capture
        var error = [CChar](repeating: 0, count: 256)
        let callback: cwasapi_capture_fn = { context, input, frames in
            guard let context, let input else { return }
            let stream = Unmanaged<WASAPIInputStream>.fromOpaque(context).takeUnretainedValue()
            stream.capture(input, Int(frames))
        }
        guard let s = cwasapi_open_capture(deviceID, callback, Unmanaged.passUnretained(self).toOpaque(), &error, error.count) else {
            throw PlatformAudioError("WASAPI: \(String(cString: error))")
        }
        stream = s
        cwasapi_capture_info(s, &info)
    }

    deinit { close() }

    var deviceName: String { withUnsafePointer(to: &info.deviceName) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) } }
    var sampleRate: Double { info.sampleRate }
    var channelCount: Int { Int(info.channels) }
    var bufferFrameCount: Int { Int(info.periodFrames) }
    var latency: TimeInterval { info.latencySeconds }

    func start() throws {
        guard let stream else { throw PlatformAudioError("WASAPI: the capture stream is closed") }
        var error = [CChar](repeating: 0, count: 256)
        guard cwasapi_capture_start(stream, &error, error.count) else { throw PlatformAudioError("WASAPI: \(String(cString: error))") }
    }

    func stop() { if let stream { cwasapi_capture_stop(stream) } }

    func close() {
        if let stream { cwasapi_capture_close(stream) }
        stream = nil
    }
}
#endif
