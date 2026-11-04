// The WASAPI output backend (Windows), over the CWASAPI shim.

#if canImport(CWASAPI)
import Foundation
import CWASAPI

final class WASAPIAudioBackend: PlatformAudioBackend {
    var name: String { "WASAPI" }

    private func errorText(_ buffer: [CChar]) -> String { String(cString: buffer) }

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
#endif
