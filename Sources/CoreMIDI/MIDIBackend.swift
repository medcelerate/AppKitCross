// The platform seam: what CoreMIDI's output subset needs from Windows MIDI Services, WinMM,
// the ALSA sequencer or the in-memory test backend.

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
    /// True when the platform takes Universal MIDI Packets (Windows MIDI Services): the
    /// server then sends `MIDISendEventList`'s words untouched and converts `MIDISend`'s
    /// bytes to UMP, instead of turning everything into MIDI 1.0 bytes.
    var acceptsUMP: Bool { get }
    /// Whole UMP messages, as the app built them.
    func sendUMP(_ words: [UInt32], to destination: MIDIPlatformDestination) -> OSStatus
    /// The line written to stderr when the first client is created (after "CoreMIDI: "),
    /// or nil for none.
    func startupLine(destinationCount: Int) -> String?
}

extension MIDIPlatformBackend {
    var acceptsUMP: Bool { false }

    /// A byte backend handed UMP converts it to MIDI 1.0 messages first.
    func sendUMP(_ words: [UInt32], to destination: MIDIPlatformDestination) -> OSStatus {
        var converter = _UMPConverter()
        converter.feed(words)
        for message in converter.messages {
            let status: OSStatus
            switch message {
            case .short(let bytes): status = sendShort(bytes, to: destination)
            case .sysEx(let bytes): status = sendLong(bytes, to: destination)
            }
            if status != noErr { return status }
        }
        return noErr
    }

    func startupLine(destinationCount: Int) -> String? { nil }
}

/// Picks the backend: `APPKITWIN_MIDI_BACKEND=null`, else on Windows Windows MIDI Services
/// when the PC has it (`=winmm` and `=midi2` force one) and WinMM otherwise, the ALSA
/// sequencer on Linux, and the in-memory backend everywhere else (the macOS test build).
func _makeMIDIBackend() -> MIDIPlatformBackend {
    let choice = ProcessInfo.processInfo.environment["APPKITWIN_MIDI_BACKEND"]?.lowercased()
    if choice == "null" {
        return NullMIDIBackend()
    }
    #if os(Windows)
    return _makeWindowsMIDIBackend(choice: choice)
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

    struct SentUMP: Equatable {
        var destinationName: String
        var words: [UInt32]
    }

    var outputs = NullMIDIBackend.defaultDestinations
    /// Behave like Windows MIDI Services (take UMP) instead of a byte API.
    var acceptsUMP = false
    private(set) var sent: [Sent] = []
    private(set) var sentUMP: [SentUMP] = []
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

    func sendUMP(_ words: [UInt32], to destination: MIDIPlatformDestination) -> OSStatus {
        sentUMP.append(SentUMP(destinationName: destination.name, words: words))
        return noErr
    }

    func clearSent() {
        sent = []
        sentUMP = []
    }
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

    /// Everything sent so far as UMP (only with `setAcceptsUMP(true)`).
    static var sentUMP: [NullMIDIBackend.SentUMP] {
        MIDIServer.shared.withBackend { ($0 as? NullMIDIBackend)?.sentUMP ?? [] }
    }

    /// Makes the null backend take UMP, as Windows MIDI Services does.
    static func setAcceptsUMP(_ value: Bool) {
        MIDIServer.shared.withBackend { ($0 as? NullMIDIBackend)?.acceptsUMP = value }
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
