// The Windows (Windows MIDI Services, WinMM) and Linux (ALSA sequencer) backends. Each
// compiles only on its platform; the macOS test build uses `NullMIDIBackend`.

import Foundation

/// A fixed-size C `char[]` imported as a tuple, decoded as UTF-8 up to its NUL.
func _MIDICString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
}

func _MIDIReportUnavailable(_ message: String) {
    fputs("AppKitCross CoreMIDI: \(message)\n", stderr)
}

#if os(Windows)
import CWinMIDI
import CWinMIDI2

/// Windows MIDI Services when the PC has it (Windows 11 25H2 or later with the
/// `Windows.Devices.Midi2` API resolvable and the service in Full mode), WinMM otherwise.
/// `APPKITWIN_MIDI_BACKEND=winmm` forces WinMM; `=midi2` forces Windows MIDI Services and
/// reports why it is unavailable (it then has no destinations) instead of falling back.
/// Either way the start-up line carries the shim's attempt log (`cwinmidi2_routes`), which
/// names every activation route tried and its HRESULT.
func _makeWindowsMIDIBackend(choice: String?) -> MIDIPlatformBackend {
    if choice == "winmm" {
        return WinMMMIDIBackend(reason: "APPKITWIN_MIDI_BACKEND=winmm")
    }
    let available = cwinmidi2_available(nil, 0)
    let routes = _MIDIServicesRoutes()
    if available {
        return WindowsMIDIServicesBackend(routes: routes)
    }
    if choice == "midi2" {
        _MIDIReportUnavailable("APPKITWIN_MIDI_BACKEND=midi2 but Windows MIDI Services is unavailable: \(routes)")
        return WindowsMIDIServicesBackend(routes: routes, forcedButUnavailable: true)
    }
    return WinMMMIDIBackend(reason: "Windows MIDI Services unavailable", routes: routes)
}

/// The shim's attempt log, "Windows MIDI Services: ..." (empty if the shim gave none).
private func _MIDIServicesRoutes() -> String {
    let length = cwinmidi2_routes(nil, 0)
    var buffer = [CChar](repeating: 0, count: length + 1)
    _ = cwinmidi2_routes(&buffer, buffer.count)
    return String(cString: buffer)
}

/// Coalesces the shim's endpoint-change callbacks (a burst of watcher events at start-up
/// and on every plug) into one server rescan, off the watcher's thread.
private final class _MIDIServicesChangeRelay: @unchecked Sendable {
    static let shared = _MIDIServicesChangeRelay()
    private let lock = NSLock()
    private var pending = false
    private let queue = DispatchQueue(label: "AppKitCross.CoreMIDI.midi2-changes")

    func changed() {
        lock.lock()
        let schedule = !pending
        pending = true
        lock.unlock()
        guard schedule else { return }
        queue.asyncAfter(deadline: .now() + 0.1) {
            self.lock.lock()
            self.pending = false
            self.lock.unlock()
            MIDIServer.shared.refresh(force: true)
        }
    }
}

/// MIDI output over Windows MIDI Services (`Windows.Devices.Midi2`, through `CWinMIDI2`).
/// Destinations are UMP endpoints keyed by endpoint device id; the service accepts MIDI 1.0
/// and MIDI 2.0 UMP alike and translates for MIDI 1.0 devices, so event lists go through as
/// built and packet lists are converted to UMP (group 0). The endpoint watcher triggers a
/// rescan at once; the 2-second poll still runs.
final class WindowsMIDIServicesBackend: MIDIPlatformBackend {
    private var connections: [String: OpaquePointer] = [:]
    /// The shim's attempt log, for the start-up line.
    private let routes: String
    /// Set when `APPKITWIN_MIDI_BACKEND=midi2` forced this backend on a PC without it.
    private let unavailableReason: String?

    init(routes: String, forcedButUnavailable: Bool = false) {
        self.routes = routes
        self.unavailableReason = forcedButUnavailable ? (routes.isEmpty ? "Windows MIDI Services unavailable" : routes) : nil
        if !forcedButUnavailable {
            cwinmidi2_set_change_callback({ _ in _MIDIServicesChangeRelay.shared.changed() }, nil)
        }
    }

    var acceptsUMP: Bool { true }

    func startupLine(destinationCount: Int) -> String? {
        if unavailableReason != nil {
            return _MIDIWindowsStartupLine(backend: "Windows MIDI Services backend",
                                           detail: "forced by APPKITWIN_MIDI_BACKEND=midi2 but unavailable", routes: routes)
        }
        return _MIDIWindowsStartupLine(backend: "Windows MIDI Services backend",
                                       detail: "\(destinationCount) endpoint\(destinationCount == 1 ? "" : "s")", routes: routes)
    }

    func destinations() -> [MIDIPlatformDestination] {
        guard unavailableReason == nil else { return [] }
        let count = cwinmidi2_destination_count()
        var result: [MIDIPlatformDestination] = []
        for index in 0..<count {
            var info = CWinMIDI2EndpointInfo()
            guard cwinmidi2_destination(index, &info) else { continue }
            let name = _MIDICString(info.name)
            let manufacturer = _MIDICString(info.manufacturer)
            result.append(MIDIPlatformDestination(
                key: _MIDICString(info.endpointDeviceId),
                name: name,
                displayName: name,
                manufacturer: manufacturer.isEmpty ? nil : manufacturer,
                model: name))
        }
        return result
    }

    func open(_ destination: MIDIPlatformDestination) -> OSStatus {
        if connections[destination.key] != nil { return noErr }
        guard unavailableReason == nil else { return kMIDINoConnection }
        var error = [CChar](repeating: 0, count: 512)
        guard let connection = cwinmidi2_open(destination.key, &error, error.count) else {
            _MIDIReportUnavailable("Windows MIDI Services could not open \(destination.name): \(String(cString: error))")
            return kMIDINoConnection
        }
        connections[destination.key] = connection
        return noErr
    }

    func close(_ destination: MIDIPlatformDestination) {
        if let connection = connections.removeValue(forKey: destination.key) { cwinmidi2_close(connection) }
    }

    func sendUMP(_ words: [UInt32], to destination: MIDIPlatformDestination) -> OSStatus {
        guard let connection = connections[destination.key] else { return kMIDINoConnection }
        var error = [CChar](repeating: 0, count: 512)
        let sent = words.withUnsafeBufferPointer {
            cwinmidi2_send_ump(connection, $0.baseAddress, UInt32($0.count), &error, error.count)
        }
        if !sent {
            _MIDIReportUnavailable("Windows MIDI Services send to \(destination.name) failed: \(String(cString: error))")
            return kMIDIMessageSendErr
        }
        return noErr
    }

    func sendShort(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        sendUMP(_MIDIBytesToUMP([.short(bytes)]), to: destination)
    }

    func sendLong(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        sendUMP(_MIDIBytesToUMP([.sysEx(bytes)]), to: destination)
    }
}

/// MIDI output over WinMM (`midiOut*`). Keys are device indices, which shift when devices
/// come and go; the server closes every open device on a setup change and reopens lazily.
final class WinMMMIDIBackend: MIDIPlatformBackend {
    private var handles: [String: OpaquePointer] = [:]
    /// Why Windows MIDI Services is not in use, and the shim's attempt log (empty when the
    /// check did not run), for the start-up line.
    private let reason: String
    private let routes: String

    init(reason: String, routes: String = "") {
        self.reason = reason
        self.routes = routes
    }

    func startupLine(destinationCount: Int) -> String? {
        _MIDIWindowsStartupLine(backend: "WinMM backend", detail: reason, routes: routes)
    }

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

    func startupLine(destinationCount: Int) -> String? {
        "ALSA sequencer backend"
    }

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
