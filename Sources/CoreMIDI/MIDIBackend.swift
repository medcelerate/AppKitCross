// The platform seam: what CoreMIDI's output subset needs from WinMM, the ALSA sequencer or
// the in-memory test backend.

import Foundation

/// One output a backend can reach.
struct MIDIPlatformDestination: Equatable {
    /// Backend-specific address (WinMM device index, ALSA "client:port", null-backend slot).
    var key: String
    var name: String
    var displayName: String?
    var manufacturer: String?
    var model: String?
}

protocol MIDIPlatformBackend: AnyObject {
    /// Current outputs, in platform order. Called under the server lock (also by the
    /// 2-second setup poll).
    func destinations() -> [MIDIPlatformDestination]
    /// Prepares a destination for sending; returns `noErr` or a `kMIDI…` status.
    func open(_ destination: MIDIPlatformDestination) -> OSStatus
    func close(_ destination: MIDIPlatformDestination)
    /// A 1-3 byte channel or system message.
    func sendShort(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus
    /// A complete SysEx, F0 through F7.
    func sendLong(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus
}

/// Picks the backend: `APPKITWIN_MIDI_BACKEND=null`, else WinMM on Windows, the ALSA
/// sequencer on Linux, and the in-memory backend everywhere else (the macOS test build).
func _makeMIDIBackend() -> MIDIPlatformBackend {
    if ProcessInfo.processInfo.environment["APPKITWIN_MIDI_BACKEND"]?.lowercased() == "null" {
        return NullMIDIBackend()
    }
    #if os(Windows)
    return WinMMMIDIBackend()
    #elseif os(Linux)
    return ALSASequencerMIDIBackend()
    #else
    return NullMIDIBackend()
    #endif
}

/// An in-memory backend with two fake outputs that records everything sent to it.
final class NullMIDIBackend: MIDIPlatformBackend {
    struct Sent: Equatable {
        var destinationName: String
        var bytes: [UInt8]
        var isSysEx: Bool
    }

    static let defaultDestinations = [
        MIDIPlatformDestination(key: "null:0", name: "Null MIDI Out A", displayName: "AppKitCross Null MIDI Out A", manufacturer: "AppKitCross", model: "Null Output"),
        MIDIPlatformDestination(key: "null:1", name: "Null MIDI Out B", displayName: "AppKitCross Null MIDI Out B", manufacturer: "AppKitCross", model: "Null Output"),
    ]

    var outputs = NullMIDIBackend.defaultDestinations
    private(set) var sent: [Sent] = []
    private(set) var opened: Set<String> = []

    func destinations() -> [MIDIPlatformDestination] { outputs }

    func open(_ destination: MIDIPlatformDestination) -> OSStatus {
        guard outputs.contains(where: { $0.key == destination.key }) else { return kMIDIUnknownEndpoint }
        opened.insert(destination.key)
        return noErr
    }

    func close(_ destination: MIDIPlatformDestination) {
        opened.remove(destination.key)
    }

    func sendShort(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        sent.append(Sent(destinationName: destination.name, bytes: bytes, isSysEx: false))
        return noErr
    }

    func sendLong(_ bytes: [UInt8], to destination: MIDIPlatformDestination) -> OSStatus {
        sent.append(Sent(destinationName: destination.name, bytes: bytes, isSysEx: true))
        return noErr
    }

    func clearSent() { sent = [] }
}

/// Internal switches for the tests (null backend only).
enum _MIDITestHooks {
    /// The active null backend, or nil when a platform backend is in use.
    static var nullBackend: NullMIDIBackend? {
        MIDIServer.shared.withBackend { $0 as? NullMIDIBackend }
    }

    /// Everything sent so far through the null backend.
    static var sent: [NullMIDIBackend.Sent] {
        MIDIServer.shared.withBackend { ($0 as? NullMIDIBackend)?.sent ?? [] }
    }

    static func clearSent() {
        MIDIServer.shared.withBackend { ($0 as? NullMIDIBackend)?.clearSent() }
    }

    /// Replaces the null backend's outputs. With `refresh`, the server rescans at once
    /// (and notifies on a change); without it, the 2-second poll finds the change.
    static func setDestinations(_ destinations: [MIDIPlatformDestination], refresh: Bool = true) {
        MIDIServer.shared.withBackend { ($0 as? NullMIDIBackend)?.outputs = destinations }
        if refresh { MIDIServer.shared.refresh(force: true) }
    }

    static func resetDestinations() {
        setDestinations(NullMIDIBackend.defaultDestinations)
    }
}
