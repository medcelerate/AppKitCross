# ADR-0050: Observation-driven SwiftUI, OSLog, Network and CoreMIDI for the first commercial port

Date: 2026-11-19. Status: accepted.

## Context

Sibyl (ClockworksTech's real-time multichannel speech-to-text for live show comms) is the
first commercial Mac app ported with AppKitCross and the first with heavy audio, networking
and MIDI. Beside AppKit and SwiftUI it imports `OSLog` (a `Logger` per subsystem), `Network`
(`NWListener`/`NWConnection` for OSC over UDP and TCP, a MOS link, a loopback MCP server,
Bonjour peer discovery with `NWBrowser`) and `CoreMIDI` (MIDI Show Control and channel
voice messages out), none of which the port had. Its whole UI is `@Observable` models read
through `@Environment(AppModel.self)` and `@Bindable`, which the port did not track: views
rendered once and never updated. It also used a dozen SwiftUI views and modifiers the port
lacked (`NavigationSplitView`, `HSplitView`, `.inspector`, `.searchable`, `openWindow(id:)`,
`Transferable` drag and drop, `Tab`, `ScrollViewReader`, `.fileExporter`, `Text(_:format:)`,
`.contentShape`, ...). The remaining Apple-only pieces (the macOS 26 speech engines, CoreML
Whisper and diarization, Sparkle, the CoreAudio HAL) are compiled out in the app with
`#if os(macOS)`; the app's audio capture moved to `AVAudioEngine.inputNode` (ADR-0028) and
its Whisper engine to a vendored whisper.cpp off macOS.

## Decision

### Observation-driven views

`Observation` ships with every Swift 5.9+ toolchain, Windows and Linux included, and the
port's floor (macOS 14) is Observation's, so the port tracks it rather than asking apps to
rewrite models as `ObservableObject`. Every body evaluation and primitive construction in
`_ViewNode.update` runs inside `withObservationTracking`; the first change to any observable
property the pass read marks that node stale (hopping to the main queue when the mutation
is elsewhere) and the host re-runs it at the next display cycle, which is when Apple's
SwiftUI re-renders too. Tracking re-arms on every pass. `Environment` gains Apple's
`init(_ objectType:)` (trapping with Apple's message when no ancestor set the object) and
the optional form, `View.environment(_:)` stores an `Observable` object by type beside
`environmentObject`'s, and `Bindable` is declared with its dynamic-member `Binding`
subscript. `@State` holding an observable class needs nothing: the tracking covers it.

### Three system-framework modules

`OSLog`, `Network` and `CoreMIDI` are built under Apple's names on Windows and Linux as
library products, and as `OSLogPortable`, `NetworkPortable` and `CoreMIDIPortable` on macOS
for the tests only (a module named `Network` in the build directory would shadow Apple's for
every macOS target; the pattern of ADR-0043). AppKit does not depend on them: an app names
the products it imports, behind `#if os(Linux) || os(Windows)` in its manifest as AGENTS.md
describes.

**OSLog.** `Logger` with Apple's `OSLogMessage` interpolation (`privacy:`, `align:`, integer,
float, bool and pointer `format:`), `OSLog`, `OSLogType` and the `os_log` forms. A message is
one stderr line (`<time> <process>[<pid>] [<subsystem>:<category>] <LEVEL> <message>`; on
Windows also `OutputDebugString`). Private and sensitive values print as `<private>` unless
`APPKITWIN_LOG_PRIVATE=1`, and `.auto` is private for strings, objects and pointers, public
for numbers, as on Apple. `APPKITWIN_LOG_LEVEL` (default `notice`, like `log stream`) gates
what is written; messages below it never evaluate their interpolations. Signposts and the
log store are not declared.

**Network.** `NWConnection`, `NWListener`, `NWBrowser`, `NWEndpoint`, `NWParameters`,
`NWError`, `NWPath` and `NWTXTRecord` over BSD sockets (POSIX) and Winsock (Windows), with
one reactor thread polling every socket and delivering each object's callbacks on the queue
it was started with. TCP connects are non-blocking with `getaddrinfo` resolution and IPv6
fallback; UDP "connections" bind and connect a datagram socket; `requiredLocalEndpoint`,
`allowLocalEndpointReuse` and an ephemeral `port` work on the listener. Bonjour is a small
mDNS/DNS-SD responder and browser in Swift over multicast UDP (`224.0.0.251:5353`): a
listener with a `service` advertises PTR, SRV, TXT and A records and answers queries; the
browser queries a type and parses answers into `.service` endpoints that expire with their
TTL; a connection to a `.service` endpoint resolves it from the browser's cache or a
one-shot SRV/A query. It finds other instances of the same app on a LAN, which is all the
app needs; it is not a full DNS-SD daemon. TLS, `NWPathMonitor`, WebSocket and QUIC are not
declared.

**CoreMIDI.** The output subset: `MIDIClientCreateWithBlock`, output ports, destinations
enumerated with stable unique IDs (FNV-1a of name and index), `MIDIObjectFindByUniqueID`,
string and integer properties, `MIDIPacketList` (packets back to back, running status,
SysEx across packets) and `MIDIEventList` (UMP MIDI 1.0 and 2.0 channel voice, system and
7-bit SysEx converted to MIDI 1.0 bytes for the byte backends), with Apple's 16 error codes. Backends, one per
process, named in one stderr line when the first client is created:

| Backend | Where | Path |
|---|---|---|
| Windows MIDI Services (`CWinMIDI2`) | Windows 11 25H2 (build 26200) and later, with the `Windows.Devices.Midi2` API resolvable (in Windows once it ships there; until then `Windows.Devices.Midi2.dll` and `.pri` from the NuGet package next to the executable) and the service in Full mode | UMP: event lists go out as built (MIDI 1.0 and 2.0 alike; the service translates for MIDI 1.0 devices), packet lists converted bytes to UMP in group 0 |
| WinMM (`CWinMIDI`) | Windows 10, Windows 11 24H2 (its older Windows MIDI Services never gets the API), Legacy API mode, a disabled `midisrv`, or a build without the API headers | MIDI 1.0 bytes: short messages, SysEx through prepared headers |
| ALSA sequencer (`CALSASeq`, libasound `dlopen`ed as `CALSA` does) | Linux | MIDI 1.0 bytes |
| null | macOS (the tests), or `APPKITWIN_MIDI_BACKEND=null` | records what was sent |

`CWinMIDI2` asks the three questions of Microsoft's detect-midi-services sample (Windows
build, does `MidiApi` resolve, `EnsureServiceAvailable()`) through a hand-declared
`IMidiApiStatics`, so it needs nothing at build time to decide; the session, endpoint
watcher and sends go through the C++/WinRT projection, which the build machine generates
with `cppwinrt.exe` from the `Windows.Devices.Midi2` NuGet package's `.winmd` (written
against 0.99.92-preview.11, the API lock) and puts on the C++ include path. Without those
headers the shim compiles to the check alone and Windows falls back to WinMM, saying why.
`APPKITWIN_MIDI_BACKEND=winmm` or `=midi2` forces one; a forced but unavailable Windows MIDI
Services reports the reason and has no destinations rather than falling back. One endpoint
is one destination (a multi-port MIDI 1.0 interface is one endpoint with a group per port;
byte sends use group 0). The earlier App SDK (`Microsoft.Windows.Devices.Midi2` with
`MidiDesktopAppSdkInitializer`) is superseded and not supported. Setup changes are
found by rescanning the destination list (every 2 s while a client exists, and at once on a
Windows MIDI Services endpoint-watcher event) and delivered as
`.msgSetupChanged`. On corelibs `CFString` is `NSString` (the CoreText alias), so
`"Sibyl" as CFString` compiles; `noErr` is declared `@_disfavoredOverload` so a file
importing AVFAudio too is not ambiguous. Inputs, virtual endpoints, devices and entities,
thru connections and timestamps are not declared.

### SwiftUI containers and modifiers the app needed

`NavigationSplitView` (two and three columns, `columnVisibility`, column widths),
`HSplitView`/`VSplitView` and `.inspector` over the port's `NSSplitView` (panes sized from
each column's min/ideal/max; divider drags clamped); `.searchable` as an `NSSearchField` in
the toolbar; `Window`/`WindowGroup` scenes with an id opened by `openWindow(id:)` instead of
at launch, with `dismissWindow`; `Transferable` (`CodableRepresentation`,
`DataRepresentation`, `ProxyRepresentation`) with `.draggable`/`.dropDestination` over
`NSItemProvider`; the accessibility environment values; `Tab`-based `TabView`,
`Button(_:systemImage:)`, `TextField(_:value:format:)`, `Text(_:format:)`,
`ScrollViewReader`, `.fileExporter` over `NSSavePanel`, `.contentShape`, sortable
`TableColumn(_:value:)`, `ShapeStyle` statics and the rest of the list in
`Tests/AppKitTests/SwiftUISibylGapTests.swift`. Symbol effects and content transitions are
declared as documented no-ops (the port draws no SF Symbol animations).

## Consequences

- An `@Observable` app ports without model changes; the cost is one tracking scope per
  body evaluation. Observation's `onChange` fires before the new value is stored, so the
  port schedules the update rather than re-rendering inline, which is also what keeps a
  model mutated from a background thread safe.
- `import OSLog`, `import Network` and `import CoreMIDI` compile unchanged in the app; the
  limits above trap with `unimplemented()` where a declared member is not written, and
  undeclared API fails at compile time (AGENTS.md's three kinds of missing).
- The mDNS implementation shares the multicast group with the platform's own responder
  (Bonjour for Windows, Avahi); it answers only for its own services and ignores the rest.
- Sibyl itself (its own repository) compiles out the Apple engines, Sparkle and the HAL with
  `#if os(macOS)`, captures through `AVAudioEngine.inputNode` with the port's
  `_inputDeviceUID`, lists devices through `PlatformAudio`, and runs Whisper on whisper.cpp
  (CPU) with the show vocabulary as the initial prompt; the consumer lessons are in its PR.

## Verification

`SwiftUIObservationTests` (5), `OSLogTests` (12), `CoreMIDITests` (12), `NetworkTests`,
`SwiftUIContainerGapTests` (12) and `SwiftUISibylGapTests` on the macOS host build and in
the Linux container; the Windows PC run is relayed by the orchestrating session. Sibyl
builds on macOS with Apple's frameworks unchanged (140 tests), on the macOS host build
against the port with whisper.cpp, and in the Linux container.
