# ADR-0028: Audio follow-ups: time stretching, conversion, source and sink nodes, streaming, devices and capture

Date: 2026-11-10. Status: accepted. Extends ADR-0014.

## Context

ADR-0014 shipped `AVFAudio`/`AVFoundation` with playback only: player, mixer, EQ and
output nodes, whole-file decoding of WAV and AIFF, the default output device, and a list
of follow-ups that were absent rather than stubbed. Applications reach for the rest early:
`AVAudioUnitTimePitch` for speed controls, `AVAudioPlayer.rate`, `AVAudioConverter` for
anything that touches a codec boundary or a device format, `AVAudioSourceNode` for
synthesizers, `inputNode` and `AVAudioRecorder` for anything with a microphone, and
`AVAudioEngineConfigurationChange` so headphones being unplugged do not leave the app
playing into nothing.

## Decision

Apple's API, names and semantics (from the macOS 26 SDK headers) for every new type; the
offline parts are tested against Apple's AVFAudio on macOS as a specification, as in
ADR-0014. One port-specific route, for device selection, is named with a leading
underscore and documented below.

### Time stretching: a phase vocoder with identity phase locking

`AVAudioUnitTimeEffect`, `AVAudioUnitTimePitch` (`rate` 1/32 to 32, `pitch` -2400 to
2400 cents, `overlap` 3 to 32, `bypass`) and `AVAudioUnitVarispeed` (`rate` 0.25 to 4)
are engine nodes. Time-pitch is a phase vocoder (`Internal/TimeStretch.swift`): Hann
windows of 2048 frames at 44.1/48 kHz (4096 to 96 kHz, 8192 above), a synthesis hop of
`2048 / overlap` (Apple's `overlap` maps directly onto the vocoder's overlap factor; 8 by
default, so 256 frames), an analysis hop of `hop * rate / pitchRatio`, and identity phase
locking (Laroche and Dolson): peaks (local maxima over two neighbours) advance by their
instantaneous frequency, the bins in a peak's region of influence keep their phase
relation to it. When the analysis hop exceeds a quarter frame (speed-ups beyond 2x at the
default overlap), the instantaneous frequency comes from a second analysis frame a
quarter frame earlier instead of the previous frame, so large speed-ups do not alias.
The output is normalized by the exact sum of squared windows for each output phase, so
any overlap, including Apple's minimum of 3, reconstructs at unit gain. The pitch shift
is the vocoder's time scale times a resampling by the pitch ratio afterwards.

Why a phase vocoder rather than WSOLA: Apple's unit is a vocoder-family algorithm (its
`overlap` parameter is the vocoder's overlap factor, a meaningless knob for WSOLA), it has
to handle polyphonic music as well as speech, and it has to cover a 1024:1 range of
time scales. WSOLA is cheaper and excellent on speech but its similarity search breaks
down on dense polyphony and needs search windows that grow with the stretch; phase
locking removes most of the vocoder's "phasiness". The vocoder's weakness is transients,
which smear over about one frame (43 ms at 48 kHz); no transient detection is attempted.

Quality target (and what the tests measure): a stationary tone comes out at the input
frequency times the pitch ratio within 0.5 %, at the input level within 1 dB, with the
best-fitting sine leaving a residual at least 20 dB down (measured: 440.00 Hz at rates 2
and 0.5, 880.00 Hz at +1200 cents, residual 98 to 119 dB down), and the output lasts
`input / rate` to within one frame. Apple's unit passes the same checks.

Varispeed and the pitch stage use a new band-limited resampler (`Internal/Resampler.swift`,
Smith's bandlimited interpolation: one Kaiser-windowed sinc prototype with 16 zero
crossings, 256 table entries per crossing, read at `t / max(1, ratio)` so the cutoff
follows the lower rate), whose ratio may change between render cycles. At ratio 1 on an
integral position it copies exactly. ADR-0014's fixed-ratio converter stays for the
mixer, whose output is checked sample for sample.

Real-time safety: every buffer (FFT tables and scratch, the input and overlap-add rings,
the per-channel phase state, the resampler's history) is allocated when the graph is
built on the control thread; the render thread reads `rate` and `pitch` from atomics and
only computes. `overlap` changes the frame layout, so setting it rebuilds the graph.

The render graph gains a time-effect kind: it asks the unit how many input frames it
wants before it can produce the cycle's output, pulls them from upstream (in pieces no
larger than the source's scratch, each piece a new pass over the upstream nodes) and
pushes them. Upstream sample time is the unit's own input clock. The vocoder maps output
frame `j` to input frame `j * rate` with no offset, so playback starts without a gap; the
first cycle pulls half a frame more input.

`AVAudioPlayer.rate` (0.5 to 2, Apple's range) works when `enableRate` is set before
`prepareToPlay()`/`play()`: the player's node then goes through its own time-pitch unit
on the shared engine.

### AVAudioConverter, and the mixer's channel negotiation

`AVAudioConverter` converts linear PCM: Int16, Int32, Float32 and Float64, interleaved or
not, any channel counts (Apple's default mapping, verified against Apple's converter:
channel n to n, mono duplicated into every output; `channelMap`; `downmix`, averaging to
mono and using the ITU-R BS.775 coefficients for 5.1-ordered layouts into stereo) and any
sample rates (the resampler above). `convert(to:from:)` does everything but sample-rate
conversion and throws `'fmt?'` for that, as Apple's documents;
`convert(to:error:withInputFrom:)` does everything, pulling input through the block, with
`noDataNow` returning what could be converted and `endOfStream` synthesizing the trailing
frames so the output length is `input * outRate / inRate`, rounded (Apple's default
`.normal` priming: no latency at the output). Codecs are not available: a non-PCM format
makes the initializer return nil, and the encoder properties report nothing to encode.
The same channel matrix serves the engine: a mixer input whose channel count has no
direct mixing law (anything other than mono or stereo into stereo, or anything into mono)
is downmixed or mapped with it instead of being truncated; source nodes and the input
node use the converter's sample-format and channel code for their block formats.

### Source and sink nodes

`AVAudioSourceNode(renderBlock:)` and `(format:renderBlock:)` with Apple's block
signatures and `AVAudioMixing`. The block renders into a preallocated `AudioBufferList`
(it may swap the data pointers for its own, as the header allows); with a block format
different from the connection format the node converts sample format, interleaving,
channel count and sample rate on the render thread without allocating. The silence flag
is honoured. `AVAudioSinkNode(receiverBlock:)` receives its input on the render thread;
as it has no output bus, the graph pulls sinks every cycle after the output chain. As on
Apple's engine, sinks are meant for the input chain and run only while the engine renders
to a device.

### Streaming scheduled files, and CAF

`scheduleFile` and `scheduleSegment` stream from disk when the segment is longer than the
stream ring (64 Ki frames, 1.4 s at 48 kHz): one decode thread per process reopens the
file (so the caller's `AVAudioFile` position is untouched), reads 8 Ki-frame chunks,
converts channel count and sample rate to the node's format and fills a frame ring per
segment; the ring is filled before the schedule returns, so playback starts at once. The
render thread reads the ring and kicks the reader when it is half empty. If the reader is
late in real time the node renders silence for the rest of the cycle and carries on (the
player time keeps running, as for any underrun); in manual rendering mode, which has no
deadline, the render thread waits for the reader instead, so offline renders are exact.
Shorter segments are still decoded when scheduled. Memory per streamed segment is the
ring, about 512 KB for stereo, whatever the file's length.

`AVAudioFile` reads and writes CAF (`caff`, the `desc` chunk for linear PCM, both
endiannesses, integer 8 to 32 bits and float 32/64; `data` chunks of unknown size read to
the end of the file); writing produces little-endian PCM, as Core Audio does by default.

### Devices: selection, enumeration and configuration changes

The seam (`Platform/PlatformAudio.swift`) grows `PlatformAudioInputBackend`: input device
enumeration and default, `openInputStream` (an event-driven capture stream delivering
interleaved Float32 to a callback on the backend's thread) and a device-change handler
(`PlatformAudioDeviceChange`: the default output or input changed, a device was added,
a device was removed). WASAPI implements it with `IAudioCaptureClient` and an
`IMMNotificationClient` (registered from a thread of its own in the multithreaded
apartment, kept alive with `CoIncrementMTAUsage`, so it outlives an STA caller); PipeWire
with a capture `pw_stream` (`target.object`, falling back to `node.target` on older
servers) and a registry listener plus the `default` metadata object
(`default.audio.sink`/`default.audio.source`) on a thread loop of its own; the null
backend with two outputs, one input that captures a 440 Hz sine at amplitude 0.25 (so
recording and metering have a known signal without a microphone) and `simulate(_:)` for
tests. ALSA stays output-only.

Device selection, the chosen API: Apple selects a device through Core Audio: on macOS
`kAudioOutputUnitProperty_CurrentDevice` on `outputNode.audioUnit` or
`AUAudioUnit.setDeviceID` on `outputNode.auAudioUnit`, both in terms of `AudioDeviceID`s
from the HAL, none of which exists here; on iOS through `AVAudioSession` routes, which
cannot name an output. Rather than invent a Core Audio, the port exposes:

- `AVAudioPlayer.currentDevice` (Apple's, macOS 10.13): the device UID string; setting it
  moves the player (players on different devices get engines of their own).
- On `AVAudioEngine`, outside Apple's API and marked as such by the leading underscore
  (the convention of ADR-0014's `_outputDescription`): `_outputDeviceUID` and
  `_inputDeviceUID` (get/set, `String?`, nil following the system default; setting the
  output while running moves the stream at once and keeps running) and
  `_currentOutputDeviceUID` (the device the stream is open on). The UIDs are
  `PlatformAudioDevice.id`s: the endpoint ID string on Windows, the node name on Linux.
- Enumeration through the public seam: `PlatformAudio.backend.outputDevices()`, and
  `inputDevices()` on a `PlatformAudioInputBackend`.

Configuration changes follow Apple: when the default device an engine follows changes,
or the device it renders to or captures from goes away, the engine stops itself and posts
`AVAudioEngineConfigurationChange` (object: the engine) from a queue of its own;
`start()` reopens on the device now current, falling back to the default when a selected
device has vanished. Changes about other devices are ignored. The engines behind
`AVAudioPlayer` restart themselves on the notification and resume their playing players;
an `AVAudioEngine` app restarts in its handler, as on macOS (the example does).

### Input capture and AVAudioRecorder

`AVAudioEngine.inputNode` is created and attached on first access, reports the input
device's format (an empty format when there is none) and captures once it is connected
or tapped: the capture callback writes into a lock-free ring, the render thread reads it,
keeping `frames + 2` capture periods of headroom (waiting for it at the start and after
an underrun) and dropping the oldest frames when clock drift between the two devices
builds a backlog. Taps on the input node work even when nothing downstream pulls it.
`setManualRenderingInputPCMFormat(_:inputBlock:)` feeds the input node in manual
rendering mode (any common PCM format, converted).

`AVAudioRecorder` records the default input to WAV, AIFF, AIFF-C or CAF (from the
extension) in the settings' linear PCM format: the capture callback fills a ring, a
writer thread converts with `AVAudioConverter` (sample rate, channels, sample format),
meters and writes; `record`, `record(atTime:)`, `record(forDuration:)`, `pause`, `stop`
(finishes the file and calls the delegate), `deleteRecording`, `currentTime`,
`deviceCurrentTime`, metering. It needs no output device.

## Consequences

- `AVAudioUnitTimePitch`, `AVAudioUnitVarispeed`, `AVAudioConverter`,
  `AVAudioSourceNode`, `AVAudioSinkNode`, `AVAudioRecorder`, `inputNode` and CAF compile
  and work unchanged on the three platforms. Still absent: the other effects and
  generators, `AVAudioEnvironmentNode`, `AVAudioSequencer`, `AVAudioSession`, codecs.
- Time stretching costs two real FFTs of 2048 points per hop and channel (one more
  above 2x speed-up at the default overlap); at 48 kHz stereo and overlap 8 that is about
  750 FFTs a second, a few percent of a core in a release build.
- The time-pitch output is not bit-identical to Apple's (different algorithms); tests
  compare frequencies, levels, residuals and lengths, not samples.
- A streamed segment that the reader cannot keep up with in real time plays a gap rather
  than blocking the device thread.
- Device-change handling stops the engine, so a configuration change is audible as a
  short gap until the app (or `AVAudioPlayer`) restarts it, as on macOS.
- The `PlatformAudioBackend` protocol is unchanged; capture and notifications are a
  refinement, so out-of-tree backends keep compiling.

## Verification

`Tests/AppKitTests/AudioFollowupTests.swift` (17 tests). Offline, against Apple's AVFAudio
on macOS and the port everywhere: time-pitch rate 2 and 0.5 keep the pitch (zero
crossings), the level and the fitted-sine residual, and scale the length; +1200 cents
doubles the frequency at the same length; varispeed 2 doubles the frequency and halves
the length; bypass passes through exactly; converter round trips through Int16, Int32,
Float64 and Float32, interleaved and not, with Int16 scaling; mono to stereo, a swapped
`channelMap`, downmix; 44.1 to 48 to 44.1 kHz through the block API (length, frequency,
level, alignment; the port's converter adds no delay); source nodes with their block
(volume, frame accounting) and with a 24 kHz interleaved Int16 block format; the manual
rendering input block; CAF round trips at 16, 24 and 32-bit float; a 3-second file
segment streamed from disk equals the decoded file sample for sample. Port only (the null
backend's real-time path): input tap and sink node receive the captured 440 Hz tone; the
recorder writes WAV and CAF across a pause, meters, resamples 48 to 44.1 kHz, and the file
reads back with the tone; device selection, moving while running, a default change and an
unplug each stop the engine with the notification, `start()` recovers, unrelated changes
are ignored; `AVAudioPlayer.rate` and `currentDevice`. `AudioTests` keeps its 15 tests; the
looping section of `testPlayerNodeSchedulingAndCompletions` now schedules before `play()`,
which made it deterministic on Apple's engine (25 runs, no failure; it used to fail on the
macOS runner when Apple applied the schedule a cycle late). The Windows PC checks WASAPI
capture, device switching, unplug recovery and the audible speed and pitch by ear (see
the pull request's checklist).
