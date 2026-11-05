// The PipeWire output backend (Linux), over the CPipeWire shim.

#if os(Linux)
import Foundation
import CPipeWire

final class PipeWireAudioBackend: PlatformAudioBackend {
    var name: String { "PipeWire" }

    /// Nil when the library or the daemon is missing (the reason goes to stderr once).
    static func makeIfAvailable() -> PipeWireAudioBackend? {
        var error = [CChar](repeating: 0, count: 256)
        guard cpw_available(&error, error.count) else {
            if ProcessInfo.processInfo.environment["APPKITWIN_AUDIO_LOG"] != nil {
                FileHandle.standardError.write("AppKitWin audio: PipeWire unavailable: \(String(cString: error))\n".data(using: .utf8)!)
            }
            return nil
        }
        return PipeWireAudioBackend()
    }

    func outputDevices() throws -> [PlatformAudioDevice] {
        let count = cpw_sink_count()
        var devices: [PlatformAudioDevice] = []
        for i in 0..<count {
            var info = CPWSinkInfo()
            guard cpw_sink(i, &info) else { continue }
            let name = withUnsafePointer(to: &info.name) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
            let description = withUnsafePointer(to: &info.description) { String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }
            devices.append(PlatformAudioDevice(id: name, name: description.isEmpty ? name : description, sampleRate: Double(info.sampleRate == 0 ? 48000 : info.sampleRate), channelCount: Int(info.channels == 0 ? 2 : info.channels), isDefault: i == 0))
        }
        return devices
    }

    func defaultOutputDevice() throws -> PlatformAudioDevice? {
        try outputDevices().first ?? PlatformAudioDevice(id: "", name: "PipeWire default sink", sampleRate: 48000, channelCount: 2, isDefault: true)
    }

    func openOutputStream(device: PlatformAudioDevice?, sampleRate: Double?, channelCount: Int?, render: @escaping PlatformAudioRenderCallback) throws -> any PlatformAudioOutputStream {
        try PipeWireOutputStream(rate: UInt32(sampleRate ?? 48000), channels: UInt32(channelCount ?? 2), render: render)
    }
}

final class PipeWireOutputStream: PlatformAudioOutputStream {
    private var stream: OpaquePointer?
    private let render: PlatformAudioRenderCallback
    private var info = CPWStreamInfo()

    init(rate: UInt32, channels: UInt32, render: @escaping PlatformAudioRenderCallback) throws {
        self.render = render
        var error = [CChar](repeating: 0, count: 256)
        let callback: cpw_render_fn = { context, out, frames in
            guard let context, let out else { return }
            let stream = Unmanaged<PipeWireOutputStream>.fromOpaque(context).takeUnretainedValue()
            stream.render(out, Int(frames))
        }
        guard let s = cpw_open(rate, channels, callback, Unmanaged.passUnretained(self).toOpaque(), &error, error.count) else {
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
#endif
