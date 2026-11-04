// The ALSA output backend (Linux, when PipeWire is absent), over the CALSA shim.

#if canImport(CALSA)
import Foundation
import CALSA

final class ALSAAudioBackend: PlatformAudioBackend {
    var name: String { "ALSA" }

    /// Nil without libasound or without an openable default device.
    static func makeIfAvailable() -> ALSAAudioBackend? {
        var error = [CChar](repeating: 0, count: 256)
        guard calsa_available(&error, error.count) else {
            if ProcessInfo.processInfo.environment["APPKITWIN_AUDIO_LOG"] != nil {
                FileHandle.standardError.write("AppKitWin audio: ALSA unavailable: \(String(cString: error))\n".data(using: .utf8)!)
            }
            return nil
        }
        // Probe the default device once so a machine without sound falls through.
        let probe: cwrap_probe = { _, _, _ in }
        guard let s = calsa_open(nil, 48000, 2, probe, nil, &error, error.count) else {
            if ProcessInfo.processInfo.environment["APPKITWIN_AUDIO_LOG"] != nil {
                FileHandle.standardError.write("AppKitWin audio: ALSA default device: \(String(cString: error))\n".data(using: .utf8)!)
            }
            return nil
        }
        calsa_close(s)
        return ALSAAudioBackend()
    }
    private typealias cwrap_probe = calsa_render_fn

    func outputDevices() throws -> [PlatformAudioDevice] {
        let count = calsa_device_count()
        var devices: [PlatformAudioDevice] = []
        for i in 0..<count {
            var info = CALSADeviceInfo()
            guard calsa_device(i, &info) else { continue }
            let name = withUnsafePointer(to: &info.name) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
            let description = withUnsafePointer(to: &info.description) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
            devices.append(PlatformAudioDevice(id: name, name: description, sampleRate: 48000, channelCount: 2, isDefault: name == "default"))
        }
        return devices
    }

    func defaultOutputDevice() throws -> PlatformAudioDevice? {
        PlatformAudioDevice(id: "default", name: "ALSA default", sampleRate: 48000, channelCount: 2, isDefault: true)
    }

    func openOutputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, render: @escaping PlatformAudioRenderCallback) throws -> any PlatformAudioOutputStream {
        try ALSAOutputStream(device: device?.id, rate: UInt32(sampleRate ?? 48000), channels: UInt32(channelCount ?? 2), render: render)
    }
}

final class ALSAOutputStream: PlatformAudioOutputStream {
    private var stream: OpaquePointer?
    private let render: PlatformAudioRenderCallback
    private var info = CALSAStreamInfo()

    init(device: String?, rate: UInt32, channels: UInt32, render: @escaping PlatformAudioRenderCallback) throws {
        self.render = render
        var error = [CChar](repeating: 0, count: 256)
        let callback: calsa_render_fn = { context, out, frames in
            guard let context, let out else { return }
            let stream = Unmanaged<ALSAOutputStream>.fromOpaque(context).takeUnretainedValue()
            stream.render(out, Int(frames))
        }
        guard let s = calsa_open(device, rate, channels, callback, Unmanaged.passUnretained(self).toOpaque(), &error, error.count) else {
            throw PlatformAudioError("ALSA: \(String(cString: error))")
        }
        stream = s
        calsa_stream_info(s, &info)
    }

    deinit { close() }

    var deviceName: String { withUnsafePointer(to: &info.deviceName) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) } }
    var sampleRate: Double { info.sampleRate }
    var channelCount: Int { Int(info.channels) }
    var bufferFrameCount: Int { Int(info.periodFrames) }
    var latency: TimeInterval {
        if let stream { calsa_stream_info(stream, &info) }
        return info.latencySeconds
    }

    func start() throws {
        guard let stream else { throw PlatformAudioError("ALSA: the stream is closed") }
        var error = [CChar](repeating: 0, count: 256)
        guard calsa_start(stream, &error, error.count) else { throw PlatformAudioError("ALSA: \(String(cString: error))") }
    }

    func stop() { if let stream { calsa_stop(stream) } }

    func close() {
        if let stream { calsa_close(stream) }
        stream = nil
    }
}
#endif
