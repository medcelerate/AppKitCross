// The Windows (WinMM) and Linux (ALSA sequencer) backends. Each compiles only on its
// platform; the macOS test build uses `NullMIDIBackend`.

import Foundation

/// A fixed-size C `char[]` imported as a tuple, decoded as UTF-8 up to its NUL.
func _MIDICString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
}

func _MIDIReportUnavailable(_ message: String) {
    FileHandle.standardError.write(Data("AppKitCross CoreMIDI: \(message)\n".utf8))
}

#if os(Windows)
import CWinMIDI

/// MIDI output over WinMM (`midiOut*`). Keys are device indices, which shift when devices
/// come and go; the server closes every open device on a setup change and reopens lazily.
final class WinMMMIDIBackend: MIDIPlatformBackend {
    private var handles: [String: OpaquePointer] = [:]

    func destinations() -> [MIDIPlatformDestination] {
        let count = cwinmidi_output_count()
        var result: [MIDIPlatformDestination] = []
        for index in 0..<count {
            var info = CWinMIDIOutputInfo()
            guard cwinmidi_output_info(index, &info) else { continue }
            let name = _MIDICString(info.name)
            result.append(MIDIPlatformDestination(
                key: "winmm:\(index)",
                name: name,
                displayName: name,
                manufacturer: info.manufacturerID == 1 ? "Microsoft Corporation" : nil,   // MM_MICROSOFT
                model: name))
        }
        return result
    }

    private func index(of destination: MIDIPlatformDestination) -> UInt32? {
        guard destination.key.hasPrefix("winmm:") else { return nil }
        return UInt32(destination.key.dropFirst("winmm:".count))
    }

    func open(_ destination: MIDIPlatformDestination) -> OSStatus {
        if handles[destination.key] != nil { return noErr }
        guard let index = index(of: destination) else { return kMIDIUnknownEndpoint }
        var result: UInt32 = 0
        guard let handle = cwinmidi_open(index, &result) else {
            _MIDIReportUnavailable("midiOutOpen(\(destination.name)) failed with MMRESULT \(result)")
            return kMIDINoConnection
        }
        handles[destination.key] = handle
        return noErr
    }

    func close(_ destination: MIDIPlatformDestination) {
        if let handle = handles.removeValue(forKey: destination.key) { cwinmidi_close(handle) }
    }

    func sendShort(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        guard let handle = handles[destination.key], !bytes.isEmpty else { return kMIDINoConnection }
        var message = UInt32(bytes[0])
        if bytes.count > 1 { message |= UInt32(bytes[1]) << 8 }
        if bytes.count > 2 { message |= UInt32(bytes[2]) << 16 }
        return cwinmidi_send_short(handle, message) == 0 ? noErr : kMIDIMessageSendErr
    }

    func sendLong(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        guard let handle = handles[destination.key], !bytes.isEmpty else { return kMIDINoConnection }
        let result = bytes.withUnsafeBufferPointer { cwinmidi_send_long(handle, $0.baseAddress, UInt32($0.count)) }
        return result == 0 ? noErr : kMIDIMessageSendErr
    }
}
#endif

#if os(Linux)
import CALSASeq

/// MIDI output over the ALSA sequencer: every other client's port that accepts writes and
/// write subscriptions is a destination; events go out directly (no queue) from one
/// application port. Without libasound or the snd-seq kernel module there are no
/// destinations (reported once on stderr).
final class ALSASequencerMIDIBackend: MIDIPlatformBackend {
    private var ready = false
    private var reported = false

    private func ensureOpen() -> Bool {
        if ready { return true }
        var error = [CChar](repeating: 0, count: 256)
        ready = calsaseq_open(ProcessInfo.processInfo.processName, "CoreMIDI Output", &error, error.count)
        if !ready && !reported {
            reported = true
            _MIDIReportUnavailable("ALSA sequencer unavailable (\(String(cString: error))); no MIDI destinations")
        }
        return ready
    }

    func destinations() -> [MIDIPlatformDestination] {
        guard ensureOpen() else { return [] }
        let count = calsaseq_destination_count()
        var result: [MIDIPlatformDestination] = []
        for index in 0..<count {
            var info = CALSASeqPortInfo()
            guard calsaseq_destination(index, &info) else { continue }
            let clientName = _MIDICString(info.clientName)
            let portName = _MIDICString(info.portName)
            let name = portName.isEmpty ? clientName : portName
            result.append(MIDIPlatformDestination(
                key: "\(info.client):\(info.port)",
                name: name,
                displayName: name.hasPrefix(clientName) ? name : "\(clientName) \(name)",
                manufacturer: nil,
                model: clientName))
        }
        return result
    }

    private func address(of destination: MIDIPlatformDestination) -> (Int32, Int32)? {
        let parts = destination.key.split(separator: ":")
        guard parts.count == 2, let client = Int32(parts[0]), let port = Int32(parts[1]) else { return nil }
        return (client, port)
    }

    func open(_ destination: MIDIPlatformDestination) -> OSStatus {
        guard ensureOpen() else { return kMIDINoConnection }
        return address(of: destination) == nil ? kMIDIUnknownEndpoint : noErr
    }

    func close(_ destination: MIDIPlatformDestination) {}

    func sendShort(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        guard let (client, port) = address(of: destination) else { return kMIDIUnknownEndpoint }
        let result = bytes.withUnsafeBufferPointer { calsaseq_send_short(client, port, $0.baseAddress, $0.count) }
        return result == 0 ? noErr : kMIDIMessageSendErr
    }

    func sendLong(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        guard let (client, port) = address(of: destination) else { return kMIDIUnknownEndpoint }
        let result = bytes.withUnsafeBufferPointer { calsaseq_send_sysex(client, port, $0.baseAddress, $0.count) }
        return result == 0 ? noErr : kMIDIMessageSendErr
    }
}
#endif
