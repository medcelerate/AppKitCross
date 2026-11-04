# AudioPlayer

An `AVAudioEngine` in one AppKit window, same source on every platform (ADR-0014).

What it demonstrates:

- `AVAudioEngine` with two `AVAudioPlayerNode`s into `mainMixerNode`: one plays a WAV or
  AIFF opened through `NSOpenPanel` (or a generated melody before a file is opened), the
  other loops a generated 440 Hz sine scheduled with `AVAudioPlayerNodeBufferOptions.loops`.
- Play and pause (`scheduleBuffer` from the paused frame, `playerTime(forNodeTime:)` for the
  position), loop, stop, a `dataPlayedBack` completion handler that resets the button.
- A level meter from `installTap(onBus:bufferSize:format:block:)` on the main mixer.
- The main mixer's `outputVolume` on a slider.
- The status line reports the output device (backend, name, sample rate, period and
  latency on Windows and Linux; format and presentation latency on macOS), or why the
  engine could not start when the machine has no output device.
- `--render out.wav` switches the engine to manual rendering mode, writes two seconds of
  the mix through `AVAudioFile` and exits, so CI without a sound device checks the path.

Run it:

```bash
swift run AudioPlayer
swift run AudioPlayer path/to/file.wav
swift run AudioPlayer --render out.wav [file.wav]   # offline render, then exit
```

On Windows the engine plays through WASAPI (shared mode, event driven, the low-latency
period when the driver offers one); on Linux through PipeWire, or ALSA when PipeWire is
absent. `APPKITWIN_AUDIO_BACKEND=null` runs the engine with no device.
