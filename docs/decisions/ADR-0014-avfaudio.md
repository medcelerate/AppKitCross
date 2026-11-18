# ADR-0014: AVFAudio and AVFoundation, a Swift audio engine over WASAPI, PipeWire and ALSA

Date: 2026-11-04. Status: accepted; extended by ADR-0028 (time stretching, conversion, source and sink nodes, streaming, CAF, devices, capture).

## Context

AppKit applications play sound through `NSSound` and, far more often, through
AVFoundation's audio classes: `AVAudioPlayer` for a file, `AVAudioEngine` with player,
mixer and effect nodes for anything interactive, `AVAudioFile` to read and write PCM
files, `AVAudioFormat`/`AVAudioPCMBuffer` as the currency between them. Apple ships
these in the `AVFAudio` framework, re-exported by the `AVFoundation` umbrella. Windows
and Linux have neither, and `NSSound` in this port was a stub.

Evan decided the platform APIs: WASAPI on Windows (shared mode, event driven, the
IAudioClient3 low-latency periods where the driver offers them, no ASIO), PipeWire on
Linux with ALSA as the fallback when PipeWire is absent. Default output only; input
capture is out of scope.

## Decision

Two modules under Apple's names, `AVFAudio` (the implementation) and `AVFoundation`
(`@_exported import AVFAudio`), declared only on Windows and Linux, as Combine is
(ADR-0008): on macOS the package compiles against Apple's AVFAudio, so `AppKit`'s
`NSSound`, the `AudioPlayer` example and the test suite are checked against the real
API, and the tests are a specification the port has to meet. `APPKITWIN_HOST_AVFAUDIO=1`
builds ours on macOS too (shadowing Apple's inside the package), so the engine's own
tests run on the Mac with the null output backend; the macOS CI job runs the audio tests
both ways.

### API

Apple's names, signatures and semantics, from the AVFAudio headers of the macOS 26 SDK:

- `AVAudioFormat`, `AVAudioChannelLayout`, `AVAudioBuffer`, `AVAudioPCMBuffer`,
  `AVAudioTime`, with the CoreAudioTypes they are expressed in
  (`AudioStreamBasicDescription`, `AudioBufferList` and
  `UnsafeMutableAudioBufferListPointer`, `AudioTimeStamp`, `AudioChannelLayout`, the
  `kAudioFormat*` constants, the AudioFile.h status codes). `AVAudioCommonFormat`,
  the AVAudioSettings keys, `AVAudioQuality`, the 3D point and orientation structs.
- `AVAudioFile` for reading and writing: WAV (RIFF, PCM and IEEE float, extensible
  fmt chunks, 8 to 32-bit integer and 32/64-bit float) and AIFF / AIFF-C (big-endian
  integers, `sowt`, `fl32`/`fl64`), with the processing format (Float32 non-interleaved
  unless asked otherwise) converted on the way. The container is chosen from the path
  extension when writing, sniffed when reading. CAF is not implemented.
- `AVAudioEngine`, `AVAudioNode`, `AVAudioIONode`, `AVAudioInputNode`,
  `AVAudioOutputNode`, `AVAudioMixerNode`, `AVAudioPlayerNode` (`scheduleBuffer`,
  `scheduleFile`, `scheduleSegment` in all their overloads and the async variants,
  play/pause/stop, `play(at:)`, buffer options `loops`/`interrupts`/`interruptsAtLoop`,
  the three completion callback types), `AVAudioMixing` with its stereo and 3D
  protocols, `AVAudioMixingDestination`, `AVAudioConnectionPoint`, taps, manual
  rendering mode (`enableManualRenderingMode`, `renderOffline`, `manualRenderingBlock`).
- `AVAudioUnit`, `AVAudioUnitEffect` and `AVAudioUnitEQ` (RBJ biquads per band and
  channel, every `AVAudioUnitEQFilterType`, `globalGain`, `bypass`).
- `AVAudioPlayer` and `AVAudioPlayerDelegate`: play/pause/stop, `play(atTime:)`,
  `currentTime`, `duration`, `numberOfLoops`, `volume` with `setVolume(_:fadeDuration:)`,
  `pan`, `isMeteringEnabled`/`updateMeters`/`peakPower`/`averagePower`, `settings`,
  `format`, `url`/`data`, `deviceCurrentTime`.
- `AVFoundationErrorDomain` and `AVError` with Apple's codes; `AVAudioFile` and
  `AVAudioEngine` throw in `com.apple.coreaudio.avfaudio` with the AudioFile.h and
  AudioUnit status codes, as Apple's do (`'wht?'` for a file that does not exist).
- `NSSound` in AppKit, hand-written over `AVAudioPlayer`: files and data, `init(named:)`
  through `setName(_:)` and the main bundle's sound resources, play/pause/resume/stop,
  `loops`, `volume`, `currentTime`, the delegate on the main actor.

Absent rather than stubbed (a compile error, not a runtime trap): `AVAudioUnitTimePitch`,
`AVAudioUnitVarispeed`, the other effects and generators, `AVAudioConverter`,
`AVAudioSourceNode`/`AVAudioSinkNode`, `AVAudioEnvironmentNode`, `AVAudioSequencer`,
`AVAudioRecorder`, `AVAudioSession`, the `AUAudioUnit`/`AudioUnit` properties and
`CMAudioFormatDescription`. `AVAudioEngine.inputNode` and
`AVAudioInputNode.setManualRenderingInputPCMFormat` call `unimplemented()`;
`AVAudioPlayer.rate` other than 1 with `enableRate` traps at `play()` (no time
stretching).

### The engine

A pull-model graph compiled from the connection tables on the control thread
(`Internal/RenderGraph.swift`): each node gets planar Float32 scratch output; the output
node pulls its input, a mixer pulls every connected bus, converts channel count and
sample rate and sums with the source's volume and pan, an effect pulls its input and
processes in place, a player node renders from its schedule. Connections carry the
standard format at any sample rate; the mixer resamples inputs whose rate differs from
its output rate (a Kaiser-windowed polyphase sinc, 32 taps per unit of stretch, 512
phases with linear interpolation, no delay relative to the input), and the player node
converts a scheduled file's rate and channel count at scheduling time, as Apple
documents (buffers are assumed to be at the node's rate).

Apple's mixing laws, measured against Apple's engine in offline mode: stereo pan is a
linear balance (left gain `min(1, 1 - pan)`, right `min(1, 1 + pan)`); mono into stereo
is unity on both sides at pan 0 and constant-power (`cos`/`sin` of `(pan + 1) * pi / 4`)
otherwise; source volume and the mixer's `outputVolume` multiply straight through, with
no ramping.

Nothing on the render thread allocates, locks or frees. The control side talks to a
player node's render state through a single-producer / single-consumer ring of
commands (schedule, play, pause, stop), items being `Unmanaged` references the render
side owns until it pushes them into a completion ring; a delivery thread (one per
process, woken by a semaphore signal, which never blocks) is the only consumer of the
completion and tap rings and calls the handlers. Taps copy the node's output into a
frame ring and a chunk-descriptor ring; the delivery thread assembles buffers of the
requested size. Taps deliver only while a device renders, and `dataPlayedBack`
completions fire on a later cycle once the output clock has passed the buffer's end
plus the output latency; in manual rendering mode neither happens (there is no playback
clock), and `stop()` fires the handlers of items still queued but not a finished
buffer's `dataPlayedBack`, all as measured against Apple's engine. Parameters (volume, pan, output volume, EQ bands) are atomics the
render thread reads each cycle. When the engine is stopped or in manual rendering mode
there is no render thread, so a command is applied synchronously by the thread that
submitted it, under the engine lock that also guards start and stop. A graph rebuilt
while the stream runs is swapped in by an atomic pointer; graphs built while live are
retained until the stream stops, because the render thread may still be walking one.
The atomics are inline C over the clang builtins (`CAudioAtomics`, imported with
`@_implementationOnly` so no client of AVFAudio needs its module map: the Swift
`Synchronization` module needs macOS 15, above the package's deployment target, a
shadow `AppKit` with a higher target breaks the XCTest interface build, and a public
clang dependency of the shadow `AppKit` breaks it the same way. The compiler warns
that the attribute wants library evolution; nothing from the C module appears in any
public or inlinable declaration, which is the case the warning is about.)

### Backends

`PlatformAudio` (`Platform/PlatformAudio.swift`) is the seam, in the AVFAudio module
since Apple's framework does not depend on AppKit: device enumeration, the default
output, an event-driven output stream opened at a requested format that reports the
format it got, its period, its latency, start/stop/close. The stream pulls interleaved
Float32 from a render callback; the engine renders its output node's planar scratch and
interleaves. `APPKITWIN_AUDIO_BACKEND` names a backend (`wasapi`, `pipewire`, `alsa`,
`null`); otherwise the platform's native one, falling through PipeWire to ALSA on Linux
and to the null backend when nothing opens. `AVAudioEngine.start()` throws when the
device stream cannot open, as Apple's does without an output device.

- WASAPI (`CWASAPI`, extern "C" over the COM interfaces, as CD2D): `IMMDeviceEnumerator`
  for the endpoints and the default console device, `IAudioClient3` activated first
  (`GetSharedModeEnginePeriod` + `InitializeSharedAudioStream` with the minimum period),
  `IAudioClient::Initialize` with the default period otherwise, `IAudioRenderClient`,
  an event handle, a render thread in the MTA on the "Pro Audio" MMCSS task that fills
  whatever the padding leaves free on every event. The device's mix format (Float32, or
  Int16 converted in the shim) at the mix rate; the engine adapts to that rate.
  Latency is `GetStreamLatency` plus the buffer.
- PipeWire (`CPipeWire`): `libpipewire-0.3.so.0` dlopen'ed at runtime with the headers
  from `libpipewire-0.3-dev` at build time (the `CPipeWireSystem` system-library target
  only supplies the pkg-config include paths; without the headers the shim compiles to
  stubs, as `CMetalVulkan` does). A thread loop, `pw_stream` asking for Float32 at the
  requested rate with `PW_STREAM_FLAG_RT_PROCESS`, the process callback filling what the
  quantum asks for; sinks enumerated with one registry round trip; latency from
  `pw_stream_get_time_n` plus a quantum. PipeWire resamples to the graph rate itself.
- ALSA (`CALSA`): `libasound.so.2` dlopen'ed, `snd_pcm_open("default")` for interleaved
  Float32 (Int16 otherwise), 10 ms periods, a thread doing blocking `snd_pcm_writei`
  with `snd_pcm_recover` on underrun; latency from `snd_pcm_delay`.
- Null: a thread rendering 480-frame periods on the wall clock into a scratch buffer.
  CI machines and the Linux container have no sound device, so the tests that need a
  running engine use it and the backend test skips when no stream opens.

## Consequences

- `import AVFoundation` and `import AVFAudio` compile unchanged on the three platforms
  for the surface above; the asset, capture and video halves of AVFoundation do not
  exist, and using them is a compile error.
- Scheduled files are read whole at scheduling time (converted to the node's format),
  not streamed from disk; memory is the file's decoded size.
- Fan-out (one output bus to several destinations) renders the source once per cycle;
  destinations at different sample rates get the first consumer's frame count.
- Completion handlers and tap blocks run on the delivery thread (`AVAudioPlayer`'s and
  `NSSound`'s delegates on the main queue); Apple makes no promise about the thread
  either.
- `AVAudioEngine` posts no configuration-change notification yet: device changes
  (unplugging the default output) are not tracked; the stream keeps rendering into
  the old endpoint until the engine is stopped and started.

## Verification

`Tests/AppKitTests/AudioTests.swift`: format and buffer semantics, `AVAudioTime`
extrapolation, WAV and AIFF round trips at 16/24-bit and float, file errors, an offline
mix of two players with gains and pan compared sample for sample with the law above, a
44.1 kHz to 48 kHz conversion (level and frequency on both implementations, sample for
sample against the ideal tone on ours), player node ordering and the three completion
types, looping and `stop()`, scheduling at a player time, file and segment scheduling,
taps, the EQ, the null-backend real-time path, `AVAudioPlayer`'s state machine with
loops, pause, stop and metering, and the platform backend's stream (skipped where no
device opens). The suite runs against Apple's AVFAudio on macOS and against the port on
macOS (`APPKITWIN_HOST_AVFAUDIO=1`), Windows and Linux; `Examples/AudioPlayer --render`
checks the offline path in every CI job, and the Windows machine checks WASAPI playback
by ear (see `docs/ROADMAP.md`).
