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
| Windows MIDI Services (`CWinMIDI2`) | Windows 11 25H2 (build 26200) and later, with the `Windows.Devices.Midi2` API resolvable (from Windows once it ships there; until then `Windows.Devices.Midi2.dll` and `.pri` from the NuGet package next to the executable) and the service in Full or Hybrid mode | UMP: event lists go out as built (MIDI 1.0 and 2.0 alike; the service translates for MIDI 1.0 devices), packet lists converted bytes to UMP in group 0 |
| WinMM (`CWinMIDI`) | Windows 10, Windows 11 24H2 (its older Windows MIDI Services never gets the API), Legacy API mode, a disabled `midisrv`, or no resolvable `Windows.Devices.Midi2` | MIDI 1.0 bytes: short messages, SysEx through prepared headers |
| ALSA sequencer (`CALSASeq`, libasound `dlopen`ed as `CALSA` does) | Linux | MIDI 1.0 bytes |
| null | macOS (the tests), or `APPKITWIN_MIDI_BACKEND=null` | records what was sent |

`CWinMIDI2` asks the three questions of Microsoft's detect-midi-services sample (Windows
build, does `MidiApi` resolve, `EnsureServiceAvailable()`), then creates the session and the
endpoint watcher, enumerates, opens connections and sends, all through the raw WinRT ABI:
C vtable structs, IIDs, enums and runtime class names in the checked-in
`Sources/CWinMIDI2/include/midi2abi.h`, generated from the API's `.winmd` by
`tools/midi2abi/midi2abi.py`. It compiles on a clean PC with only the Windows SDK: no
C++/WinRT projection, no `cppwinrt.exe`, no C++ exceptions (every call's HRESULT is checked
and reported as "<method> failed (0x...)"). When the API does not resolve, Windows falls back
to WinMM, saying why. `APPKITWIN_MIDI_BACKEND=winmm` or `=midi2`
forces one; a forced but unavailable Windows MIDI Services reports the reason and has no
destinations rather than falling back. One endpoint is one destination (a multi-port MIDI 1.0
interface is one endpoint with a group per port; byte sends use group 0).

**Windows MIDI Services, as Microsoft ships it (researched 2026-11-19).** Two WinRT APIs
exist; only the first is a target:

| | `Windows.Devices.Midi2` (in-box API) | `Microsoft.Windows.Devices.Midi2` (preview App SDK) |
|---|---|---|
| Status | The supported API: "in box in Windows 11 25H2 and later starting in 2027" ([porting guide](https://github.com/microsoft/MIDI/blob/main/docs/kb/porting-midi-libraries.md)); metadata locked at [In-box Preview 11](https://github.com/microsoft/MIDI/releases/tag/inbox-preview-11), still the API to build against at [In-box Preview 14](https://github.com/microsoft/MIDI/releases/tag/inbox-preview-14) (2026-11-17) | Out-of-band preview, releases RC 1 to [RC 4](https://github.com/microsoft/MIDI/releases/tag/rc-4) (1.0.14 to 1.0.17); "never supported for redistribution ... being dropped entirely in 2027"; In-box Preview 11 and 14 tell users to uninstall the "rc4 or similar SDK Runtime and Tools" |
| Where the code comes from | System32 once Windows has it; until then `Windows.Devices.Midi2.dll` and `.pri` beside the executable (NuGet `runtimes\win-x64\native`, `win-arm64\native`; "go live" terms in the Preview 11 notes) | Installed centrally by "Windows MIDI Services SDK Runtime and Tools" (e.g. 1.0.16-rc.3.x) into `%ProgramFiles%\Windows MIDI Services\Desktop App SDK Runtime\` (`Microsoft.Windows.Devices.Midi2.dll`, `.winmd`, `.pri`), folder recorded at `HKLM\SOFTWARE\Microsoft\Windows MIDI Services\Desktop App SDK Runtime`, value `Installed` ([installer WiX](https://github.com/microsoft/MIDI/blob/rc-3/src/app-sdk/sdk-runtime-installer/sdk-package/WindowsMidiServicesSdkRedist.wxs), [MidiDefs.h](https://github.com/microsoft/MIDI/blob/rc-3/src/api/Inc/MidiDefs.h)) |
| Activation Microsoft documents | `RoGetActivationFactory`; when that returns `REGDB_E_CLASSNOTREG` (not in Windows yet), `DllGetActivationFactory` on the app-local module, which C++/WinRT's own fallback also does ([detect-midi-services](https://github.com/microsoft/MIDI/blob/main/samples/cpp-winrt/detect-midi-services/main_detect_midi_services.cpp)) | `MidiDesktopAppSdkInitializer::InitializeSdkRuntime()` ([Initialization.hpp](https://github.com/microsoft/MIDI/blob/rc-3/src/app-sdk/client-initialization-redist/Microsoft.Windows.Devices.Midi2.Initialization.hpp)) CoCreates COM class `MidiClientInitializer` {c3263827-c3b0-bdbd-2500-ce63a3f3f2c3} (registered by the runtime DLL), interface `IMidiClientInitializer` {8087b303-d551-bce2-1ead-a2500d50c580} (`GetInstalledWindowsMidiServicesSdkVersion`, `EnsureServiceAvailable`), which Detours-hooks the Ro* activation functions for `Microsoft.Windows.Devices.Midi2.*` ([what SDK initialization does](https://github.com/microsoft/MIDI/blob/rc-3/docs/kb/what-is-sdk-initialization-doing.md)); `IsServiceInstalled()` CoCreates the MidiSrv transport {2BA15E4E-5417-4A66-85B8-2B2260EFBC84} |
| Service check | `Windows.Devices.Midi2.MidiApi` (static class): `IMidiApiStatics` {8087b303-0519-c0de-31d1-ee0010000000} (`EnsureServiceAvailable`, `GetCurrentlySelectedApiMode`: 0 Full, 1 Legacy, 2 Hybrid), `IMidiApiStatics2` {...0002} (`IsSystemProvided`) | No `MidiApi`; the initializer's `EnsureServiceAvailable` |
| Minimum Windows | Windows 11 25H2, build 26200; 24H2 (26100) never gets the API ([minimum requirements](https://github.com/microsoft/MIDI/blob/main/docs/kb/minimum-requirements.md)) | Same service; Microsoft no longer supports it on any build |
| Metadata | NuGet `Windows.Devices.Midi2` 0.99.92-preview.11, a GitHub release asset of In-box Preview 11 (not on nuget.org), `ref\native\Windows.Devices.Midi2.winmd` | NuGet `Microsoft.Windows.Devices.Midi2` (e.g. 1.0.16-rc.3.7, an [RC 3](https://github.com/microsoft/MIDI/releases/tag/rc-3) asset), or the `.winmd` the runtime installed |

So "`Windows.Devices.Midi2.MidiApi` did not resolve (0x80040154)" on a PC with only the RC
SDK runtime installed is expected: Windows does not have the in-box API yet, nothing put the
app-local DLL beside the executable (SwiftPM does not run the NuGet `.targets` that copy it),
and the RC runtime serves only the other namespace.

`CWinMIDI2` locates the API in one function, each step written to an attempt log: (a)
`RoGetActivationFactory` on `Windows.Devices.Midi2.MidiApi`; (b) the module beside the
executable (`Windows.Devices.Midi2.dll`) through `DllGetActivationFactory`; (c) the App SDK
runtime, found as Microsoft's initializer finds it (the registry value, else the default
folder), only reported: it serves the other namespace, so a PC that has only it says
"present but not used". Every later activation (`MidiSession`, `MidiClock`,
`MidiEndpointDeviceInformation`, `MidiEndpointDeviceWatcher`) asks the system registration
first, then the module (b) loaded, and QueryInterfaces the factory for the statics IID. The
log is the error on failure and part of the success line, so both name every route tried:

```
CoreMIDI: WinMM backend (Windows MIDI Services unavailable) [Windows MIDI Services: ABI Windows.Devices.Midi2; Windows build 26200; in-box API not registered (0x80040154); no app-local Windows.Devices.Midi2.dll in C:\Sibyl\; SDK runtime at C:\Program Files\Windows MIDI Services\Desktop App SDK Runtime\Microsoft.Windows.Devices.Midi2.dll (from the registry): present but not used: ...]
CoreMIDI: Windows MIDI Services backend (3 endpoints) [Windows MIDI Services: ABI Windows.Devices.Midi2; Windows build 26200; in-box API not registered (0x80040154); app-local C:\Sibyl\Windows.Devices.Midi2.dll: loaded; the app's own copy; service available (API mode 0, Full Windows MIDI Services mode); session created]
```

What the shim calls, per feature (all on its own MTA thread; the session, watcher and
connections live in a heap block that is never freed): availability, `IMidiApiStatics`
(`EnsureServiceAvailable`, `GetCurrentlySelectedApiMode`) and `IMidiApiStatics2`
(`IsSystemProvided`); session, `IMidiSessionStatics::Create` then `IMidiSession`;
timestamp, `IMidiClockStatics::get_TimestampConstantSendImmediately`; enumeration,
`IMidiEndpointDeviceInformationStatics::FindAll3(Name, AllStandardEndpoints)` read as
`IVectorView<MidiEndpointDeviceInformation>` (declared by hand in the `.cpp`), keeping
purposes `NormalMessageEndpoint` and `InBoxGeneralMidiSynth`, with `Name`,
`EndpointDeviceId` and `GetTransportSuppliedInfo` (`ManufacturerName`, `VendorId`,
`ProductId`); watcher, `IMidiEndpointDeviceWatcherStatics::Create2(AllStandardEndpoints)`,
`add_Added`/`add_Removed`/`add_Updated` with hand-written agile delegate objects answering
the `TypedEventHandler<MidiEndpointDeviceWatcher, ...EventArgs>` pinterface IIDs (each
marks the list stale and calls the change callback), then `Start`; open,
`IMidiSession::CreateEndpointConnection`, `IMidiEndpointConnectionSource::get_ConnectionId`,
`IMidiEndpointConnection::Open`; send, `SendSingleMessageWords` to `SendSingleMessageWords4`
by word count with "send immediately", success being the `Succeeded` flag of
`MidiSendMessageResults`; close, `IMidiSession::DisconnectEndpointConnection`.

Regenerating `midi2abi.h` for a new API version: get that version's
`Windows.Devices.Midi2.winmd` (`ref\native\` in the nupkg), install `dnfile` in a venv, run
`tools/midi2abi/midi2abi.py <winmd> --list` to see the classes, then
`tools/midi2abi/midi2abi.py <winmd> --classes <the list in the header's MIDI2ABI_CLASS_NAMES, plus any new ones> > Sources/CWinMIDI2/include/midi2abi.h`
(`tools/midi2abi/README.md`). Vtable order comes from the metadata, so a new version that
appends methods (or adds `IMidiSession2`-style interfaces) keeps working; update the
version named in the header and in this section, and diff the header to see what moved.
The pinterface IIDs are computed with the WinRT algorithm (SHA-1 of the signature under the
pinterface namespace) and check out against `IVectorView<String>`
(`2f13c006-a03a-5f69-b090-75a43e33423e`).

Build PC setup (Windows MIDI Services on the PC that builds and runs the port):

1. Windows 11 25H2 or later (`winver`: build 26200+), MIDI service enabled (Full mode).
2. Uninstall the old "Windows MIDI Services SDK Runtime and Tools" (any 1.0.x-rc) from
   Settings > Apps > Installed apps, as Microsoft's In-box Preview 11/14 notes say; optionally
   install the In-box Preview 14 Tools for MIDI Settings, Monitor and Troubleshooting.
3. Download `Windows.Devices.Midi2.0.99.92-preview.11.nupkg` from the
   [In-box Preview 11 release](https://github.com/microsoft/MIDI/releases/tag/inbox-preview-11)
   and unzip it (it is a zip).
4. Build (`swift build`): nothing else is generated or put on the include path.
5. Copy `runtimes\win-x64\native\Windows.Devices.Midi2.dll` and `Windows.Devices.Midi2.pri`
   (`win-arm64` on Arm) beside the built executable (`.build\<triple>\debug\` or the app
   folder). Remove them again once Windows has the API (the log then says "in-box API ...
   resolved").
6. Run; the `CoreMIDI:` line on stderr names the routes.

The C++/WinRT projection route the shim used before (a `winrt\` folder made by
`cppwinrt.exe`, `CWINMIDI2_USE_APP_SDK` for the App SDK, and C++/WinRT's
`winrt_activation_handler` hook) is gone; `Sources/CWinMIDI2/include/winrt/README.md` says
so. The second PC run, still with the projection build, confirmed the activation chain: with
the DLL and `.pri` beside the exe the line read "app-local dll loaded; service available
(API mode 0, Full Windows MIDI Services mode)" and fell back to WinMM only for the then
missing projection. That app-local `Windows.Devices.Midi2.dll` from the preview nupkg is
Authenticode-signed by "CN=Pete Brown" (the project's maintainer), not by Microsoft: fine
for a developer PC, a shipping build should wait for the in-box, Microsoft-signed copy or
state the signer in its release notes.

Not confirmed: the ABI layer has been compiled only on macOS against stand-in Windows
headers (`clang++ -fsyntax-only`), not yet with the real SDK or against a live service; a
PC run must still show enumeration, watcher events and sends. The earlier App SDK
(`Microsoft.Windows.Devices.Midi2` with `MidiDesktopAppSdkInitializer`) is superseded and no
longer has a build of its own. Setup changes are
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

### What the first Windows run of the app found

The PC run of Sibyl (relayed by the orchestrating session) exercised paths no test had:

- **App-level state.** A SwiftUI `App`'s own `@State` (`isExporting` behind a
  `.fileExporter`), its `@Observable` model read in `.commands` ("Start Capture" / "Stop
  Capture") and its `Settings` content had no node to re-render: the scene body ran once
  at launch. The runner now owns a node for the App (`_AppRunner._appNode`): the App's
  dynamic properties are installed in it and the scene body plus the menu build run under
  observation tracking against it. A change re-runs the scenes in update mode: a
  `Window`/`WindowGroup` scene re-evaluates its content into its open windows (so the
  bindings a file panel modifier reads see the new value), the `Settings` scene refreshes
  its window, `DocumentGroup` is skipped, and the menu bar is rebuilt from the commands.
- **The Settings window** is a dialog: `_SettingsWindow` is `_MenuBarExemptWindow`, so it
  carries no in-window menu bar on Windows and Linux (the main menu still handles its key
  equivalents), and it is sized like a `.contentSize` scene window (fixed for fixed content,
  resizable within the content's range otherwise, never taller than the screen).
- **Grouped forms** scroll (macOS's `.grouped` form is an inset-grouped list);
  `DisclosureGroup` content is a `VStack` (a padding on bare multi-view content placed its
  rows like a `ZStack`); `TextField`, `SecureField` and `Picker` show their title as a
  leading label inside a `Form`, `labelsHidden()` works, `LabeledContent` dims only text
  content; `Image(systemName:)` now draws (it never looked its name up), 48 more symbols
  are in the table with `.circle`/`.fill`/`.slash` composition; `Table` rows take the
  height of their wrapped cells through `heightOfRow`.
- **Windows MIDI Services**: see the matrix above; the PC had the superseded preview App
  SDK, not the in-box API, so the check now reports every route it tried.

The later runs found the costs that only a real workload shows:

- **Scene-level tracking** had taken in a window's content closure, so a field bound to
  the model re-ran every scene, re-rendered both windows and rebuilt the Win32 menu bar
  per keystroke; only the scene body is tracked now (App.swift).
- **Measurements** were memoised for one pass and cleared globally every pass, so a 50 Hz
  meter re-measured every transcript row with DirectWrite; they now survive across passes
  for subtrees whose inputs did not change (ADR-0010, "Measurement memo").
- **The clip view** painted its own white whatever `NSScrollView.drawsBackground` said,
  which hid every grouped-form card on a white page; it follows the scroll view now, and
  `SwiftUIGroupedFormPixelTests` reads the pixels.
- **The Win32 loop** waits at most 250 ms between services and, under
  `APPKITWIN_TRACE=1`, traces the main queue's latency, so the next run can tell a
  starved queue from slow main-thread work.
- **Windows MIDI Services without C++/WinRT**: `tools/midi2abi` and the raw ABI header,
  since the PC cannot run `cppwinrt`; the PC confirmed "Windows MIDI Services backend (1
  endpoint)" through the app-local DLL.
- **Repaint only what changed, and still paint.** Dropping the whole-host
  `setNeedsDisplay` from `scheduleUpdate` cut the per-tick cost (a meter tick marks no
  text view) but left model changes unpainted on Windows: `needsLayout` alone requested
  no frame. `NSView.needsLayout` now asks the window for a frame with a 1-px dirty area;
  the paint runs layout and what changes marks itself for the next frame
  (`SwiftUIFramePumpTests` drives frames with no explicit layout call). The host tests had
  hidden this by calling `layoutSubtreeIfNeeded` themselves.
- **Not the port's**: the empty `%LOCALAPPDATA%\<CFBundleName>` a bundled app creates at
  launch is corelibs Foundation's `HTTPCookieStorage.shared`, which the first
  `URLSessionConfiguration` touches (found with cdb on `KERNELBASE!CreateDirectoryW`:
  `FileManager.createDirectory` ← `HTTPCookieStorage.sync` ← `URLSessionConfiguration.init`
  ← Sibyl's eager `URLSession`); `URLCache.shared` likewise creates
  `%LOCALAPPDATA%\Temp\org.swift.foundation.URLCache\<bundle id>`. A bare executable
  with no Info.plist has no `CFBundleName`, so only the bundled build shows it. An earlier
  guess here blamed the preferences store; `UserDefaults` writes a flat
  `<identifier>.plist` under `%LOCALAPPDATA%` and creates no folder. The consumer fix is
  a lazy session (AGENTS.md, section 1).

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

`SwiftUIObservationTests` (5), `OSLogTests` (12), `CoreMIDITests` (15), `NetworkTests` (25),
`SwiftUIContainerGapTests` (12), `SwiftUISibylGapTests` (11), `SwiftUIAppTests` (App-state
re-render), `SwiftUIFormFixTests` (9) and `SwiftUITableRowHeightTests` (5) on the macOS host
build and in the Linux container; the Windows PC run is relayed by the orchestrating session. Sibyl
builds on macOS with Apple's frameworks unchanged (140 tests), on the macOS host build
against the port with whisper.cpp (144 tests plus hosting smoke tests of its windows), and in
the Linux container.
