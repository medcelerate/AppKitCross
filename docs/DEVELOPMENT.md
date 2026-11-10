# Developing AppKitWin

Where things live, how the generated code is produced, and how each platform is built and
tested. The user-facing introduction is the [README](../README.md); the design is in
[ARCHITECTURE.md](ARCHITECTURE.md) and the [decision records](decisions/); the milestone
state is in [ROADMAP.md](ROADMAP.md).

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/AppKit/Core` | Hand-written implementations of AppKit classes. |
| `Sources/AppKit/Generated` | Generated stubs for the public AppKit surface that compile today. Regenerate with `tools/apigen`. |
| `Sources/AppKit/Platform` | Backend protocols plus the Win32/DirectX backend, the Linux backend and a headless host backend used for tests on macOS/Linux. |
| `Sources/CoreGraphics` (Windows and Linux only) | `CGContext`, `CGPath`, `CGColor`, `CGImage` over Direct2D or Cairo. |
| `Sources/CoreText` (Windows and Linux only) | CoreText's API over DirectWrite or Pango/HarfBuzz (ADR-0007). |
| `Sources/QuartzCore` | `CALayer` tree, animations and transactions over `CGContext` (software compositor; shadows Apple's module inside the package on macOS so tests cover it). |
| `Sources/Metal`, `Sources/MetalKit` | Metal's API as protocols with a CPU reference device and `MTKView`; the Direct3D 12 backend in `Sources/CMetalD3D12` (ADR-0004) on Windows and the Vulkan backend in `Sources/CMetalVulkan` (ADR-0012) on Linux, each used unless `APPKITWIN_METAL_REFERENCE=1`. On Windows `MTKView` presents through a DXGI composition swap chain shown by the window's DirectComposition tree; on the host backend (tests) frames are read back and drawn. |
| `Sources/Combine` (Windows and Linux only) | Apple's Combine API as a port of OpenCombine (ADR-0008); on macOS the package uses Apple's Combine. |
| `Sources/UniformTypeIdentifiers`, `Sources/ImageIO` (Windows and Linux only) | `UTType` over a table generated from the macOS SDK (`tools/uttypes`); `CGImageSource`/`CGImageDestination` over WIC or Cairo (ADR-0009). |
| `Sources/SwiftUI` | SwiftUI over this AppKit (ADR-0010): runtime, layout, views and modifiers; built on every platform. |
| `Sources/CD2D`, `Sources/CDirectWrite`, `Sources/CDirectComposition` (Windows only) | `extern "C"` shims over the Direct2D, DirectWrite and DirectComposition C++ interfaces, which have no C vtables. |
| `Sources/AppKit/Platform/Linux`, `Sources/CCairo`, `Sources/CX11`, `Sources/CWayland` | Linux backend: Wayland (xdg-shell) or X11 windows, Cairo drawing, PangoCairo text. |
| `Stubs/Pending` | Generated stubs that do not compile yet. Not part of any target. |
| `api-inventory` | Condensed public API inventory extracted from the macOS SDK. Source of truth for stubs and coverage. |
| `tools/apigen` | Extraction, probing and stub generation scripts. |
| `tools/linux` | Dockerfile, test and screenshot scripts for the Linux container. |
| `Sources/AVFAudio`, `Sources/AVFoundation` | The audio engine under Apple's module names (ADR-0014), with the WASAPI, PipeWire and ALSA shims in `Sources/CWASAPI`, `CPipeWire`, `CALSA`. |
| `Examples/HelloWindow` | The sample: AppKit drawing, controls, menus, a glass window, the Layout Demo and the SwiftUI demo. |
| `Examples/Calculator`, `FramelessWindow`, `Animation`, `Drawing`, `Observable`, `AudioPlayer` | Small, self-contained examples, one executable target each (see [Examples](#examples)). |
| `Examples/LibraryCompat` | A package of its own: third-party SwiftUI libraries as dependencies, one tab each, with the per-library verdicts and API gaps in [compatibility/swiftui-libraries.md](compatibility/swiftui-libraries.md). Built by `tools/library-compat.sh` (see below). |

## Conventions

- Public API names, signatures and semantics match Apple's AppKit exactly. The inventory in
  `api-inventory/` is the source of truth; nothing is invented.
- `Sources/AppKit/Core` is hand-written and owns a class entirely. Once a type is listed in
  `tools/apigen/config.json` under `handwritten`, the generator stops emitting it. Seed a new
  hand-written type by moving its file from `Generated/` and regenerating (nested types move
  to `Generated/<Name>+Types.swift`).
- Everything else under `Sources/AppKit/Generated` is machine-generated. Fix
  `tools/apigen/apigen.py` and regenerate rather than editing those files.
- Unimplemented behaviour calls `unimplemented()`; stubs never return dummy values.
- Platform code lives behind the protocols in `Platform/Backend.swift`. AppKit core files
  never import `WinSDK` directly.
- The macOS host build exists for type-checking and tests. Windows-only modules are only
  declared in `Package.swift` when building on Windows; on macOS the core compiles against
  Apple's real CoreGraphics, CoreText, Combine and friends so signatures stay honest and the
  tests act as the specification.

## Building and testing

macOS (host build, headless backend):

```bash
swift build && swift test
```

Windows 11 (swift.org toolchain 6.2 or newer, Visual Studio Build Tools, Windows 10/11 SDK):

```bash
swift build
swift run HelloWindow
APPKITWIN_HOST_BACKEND=1 swift test
```

On Windows the test suite also runs the Direct3D 12 device (`MetalD3D12DeviceTests`,
`MetalD3D12ParityTests`): on a machine without a GPU, and on CI, that is WARP. HelloWindow's
Metal tab (`APPKITWIN_LAYOUT_TAB=metal`, or `--metal`) is where swap-chain presentation is
exercised; `--metal-log` prints the device, and every 30th frame's clear colour, read-back
pixels, drawable size and presentation path (`swap chain` on a DirectComposition-hosted
window, `readback` otherwise).

Linux, in the container from `tools/linux/Dockerfile` (`swift:6.2-noble` with X11, Wayland,
Cairo and Pango):

```bash
docker build -t appkitwin-linux -f tools/linux/Dockerfile .
docker run --rm -v "$PWD":/src -w /src appkitwin-linux bash -c "swift build; APPKITWIN_HOST_BACKEND=1 swift test"
docker run --rm -v "$PWD":/src -w /src appkitwin-linux bash tools/linux/run.sh            # host tests, then the X11 backend tests (XDND, clipboard), HelloWindow and the examples under Xvfb
docker run --rm -v "$PWD":/src -w /src appkitwin-linux bash tools/linux/run.sh --wayland  # the same under a headless sway
```

### The library compatibility example

`Examples/LibraryCompat` is a separate SwiftPM package (so the core package has no
dependencies) that pulls in third-party SwiftUI libraries and builds them against this
`SwiftUI`. Those packages do not declare a dependency on AppKitWin, so its modules must be in
the build's `Modules` directory before they compile, and a client of `AppKit` needs the C
shim module maps (`CCairo`, `CD2D`, …) that SwiftPM only passes to declared dependents;
`tools/library-compat.sh` does both, on every platform:

```bash
tools/library-compat.sh            # build the example (step 1: SwiftUI, step 2: the libraries and the app)
tools/library-compat.sh --probe    # also build each library on its own and print its first error
tools/library-compat.sh --run      # build, then run it
Examples/LibraryCompat/.build/debug/LibraryCompat --screenshot /tmp/shots   # one PNG per tab, then exit
```

On macOS the script raises every target's deployment target to 14.0 (the libraries declare
10.15–12 and the host build's modules 14), which is what lets the host build type-check the
libraries against this SwiftUI rather than Apple's. Which libraries are linked into the app
on each platform is decided in `Examples/LibraryCompat/Package.swift`; a library that does
not compile stays declared there so the probe can re-check it.

The container has no GPU: Mesa's lavapipe (`mesa-vulkan-drivers`) is the Vulkan device the
Metal module runs on there, so the Metal tests and `HelloWindow --metal-selftest` exercise the
Vulkan backend (ADR-0012), and `tools/linux/run.sh` (`--wayland`) also captures HelloWindow's Metal
tab on each window backend. Without a Vulkan loader or ICD the Metal module falls back to the
reference device and the suite still passes; without `libvulkan-dev` the shim builds as stubs.
HLSL and MSL shaders are compiled to SPIR-V with `glslangValidator` (`glslang-tools`) or `dxc`
from `PATH`; SPIR-V can also be passed through `makeLibrary(data:)`.

Two Linux window backends share the Cairo drawing, PangoCairo text and the rest of the
platform code: Wayland (xdg-shell toplevels with wl_shm buffers, xkbcommon keyboards,
wl_cursor themes, server-side decorations through xdg-decoration) is preferred when
`WAYLAND_DISPLAY` is set and the connection succeeds, X11 is the fallback;
`APPKITWIN_LINUX_BACKEND=x11|wayland` forces one. Under sway the compositor draws the title
bar:

![HelloWindow on Linux under a headless sway](images/hellowindow-linux-wayland.png)

## Examples

Each example under `Examples/` is an executable target in `Package.swift` with a README that
says what it demonstrates. CI builds every one on macOS, Windows and both Linux jobs, and
`tools/linux/run.sh` runs each under Xvfb and writes `/tmp/<name>-linux.png` (plus
`Drawing --export`, the headless PNG path).

| Example | Shows | Run |
| --- | --- | --- |
| `HelloWindow` | The big tour: drawing, controls, menus, the glass window, the Layout Demo and the SwiftUI demo | `swift run HelloWindow` (`--swiftui`, `--layout`, `--metal`, `--screenshot <dir>`, `--metal-selftest`) |
| `Calculator` | SwiftUI `App` + `WindowGroup`, button grid, `keyboardShortcut` keys, fixed-size window, `CommandMenu` | `swift run Calculator` |
| `FramelessWindow` | `.fullSizeContentView` window with AppKit's window buttons, rounded non-opaque shape, movable by background, `NSVisualEffectView` backdrop, close/minimize/zoom, a `.borderless` panel | `swift run FramelessWindow` (`--panel`) |
| `Animation` | `CABasicAnimation`, `CAKeyframeAnimation` along a path, 3D flip with perspective, `CAAnimationGroup`, implicit `CATransaction` animations, play/pause, SwiftUI `withAnimation` | `swift run Animation` (`--paused`) |
| `Drawing` | `draw(_:)` with paths, gradient, text, images; sketch canvas with mouse tracking, undo/redo, PNG export through `NSSavePanel` | `swift run Drawing` (`--export file.png`) |
| `Observable` | `ObservableObject`/`@Published` model, live `List`, detail pane over a `Binding`, Combine `Timer.publish` | `swift run Observable` |
| `AudioPlayer` | `AVAudioEngine`, two `AVAudioPlayerNode`s (file, generated sine), play/pause/loop, `installTap` level meter, output device and latency, offline render through `AVAudioFile` | `swift run AudioPlayer` (`file.wav`, `--render out.wav`) |

The port has no Observation framework (`@Observable`) and no `UndoManager` (not in
swift-corelibs-foundation), so Observable uses `ObservableObject` and Drawing keeps its own
undo stacks; the READMEs say so.

## Threading

`NSApplication`, `NSWindow`, `NSView` and the other main-actor types are `@MainActor`, as in
Apple's SDK; `NSImage`, `NSColor`, `NSFont`, `NSBezierPath` and the text storage classes are
not. On Windows and Linux the backend owns the event loop: each pump waits on the main
dispatch queue's wake handle with its window events and drains the queue through
libdispatch's run-loop hook (`Platform/MainQueue.swift`), and steps the main `RunLoop` for
its timers, so `DispatchQueue.main.async`, hops to `@MainActor` from other threads and
`Timer` behave as on macOS. The headless host backend runs the main run loop directly.

## Runtime switches

| Variable | Effect |
| --- | --- |
| `APPKITWIN_SOFTWARE_LAYERS=1` | Software compositing instead of DirectComposition on Windows. |
| `APPKITWIN_LEGACY_TEXT=1` | The pre-CoreText text path on Windows. |
| `APPKITWIN_METAL_REFERENCE=1` | The CPU Metal device instead of Direct3D 12 (Windows) or Vulkan (Linux). |
| `APPKITWIN_VULKAN_DEBUG=1` | Enables `VK_LAYER_KHRONOS_validation` on the Vulkan device when installed, with its messages on stderr. |
| `APPKITWIN_VULKAN_DEVICE=n` | Picks Vulkan physical device `n` instead of the best one. |
| `APPKITWIN_DXGI_DEBUG=1` | Reports live DXGI objects at exit. |
| `APPKITWIN_LINUX_BACKEND=x11\|wayland` | Forces a Linux window backend. |
| `APPKITWIN_DEMO_TAB=data` | Opens the HelloWindow SwiftUI demo on that tab (controls, navigation, presentation, data); screenshots are named by tab. |
| `APPKITWIN_LAYOUT_TAB=table` | Opens the HelloWindow Layout Demo on that tab (form, split, table, metal); screenshots are named by tab. |
| `APPKITWIN_COMPAT_TAB=confetti` | Opens `LibraryCompat` on that library's tab (shimmer, confetti, wrapping, defaults, markdown, introspect, charts, nuke). |
| `APPKITWIN_HOST_BACKEND=1` | The headless backend the tests use; the suite expects it on Windows and Linux. |
| `APPKITWIN_IME_LAYOUT=00000411` | Windows: activates that keyboard layout for the process and opens its IME in native mode on focus (00000411 is Japanese), for testing composition without changing the system's input settings. |
| (gestures) | No switch: on Windows, Ctrl+wheel is delivered as a magnify gesture (a precision touchpad's pinch arrives that way) and touch screens send WM_GESTURE; on X11 gestures need XInput 2.4 (libinput); on Wayland the compositor must offer `zwp_pointer_gestures_v1`. |
| `APPKITWIN_LAYOUT_DIRECTION=rtl\|ltr` | Forces the application's layout direction; otherwise the macOS defaults keys (`AppleTextDirection`, `NSForceRightToLeftWritingDirection`) and then the locale's language decide. |
| `APPKITWIN_TRACE=1` | Logs every view invalidation, SwiftUI node update, root layout pass and ideal-size change (for repaint loops). |

## Audio backends and the offline render switch

`Sources/AVFAudio` (ADR-0014) is the audio engine, built on Windows and Linux; on macOS the
package uses Apple's AVFAudio so `NSSound`, the AudioPlayer example and `AudioTests` are
checked against the real API. `APPKITWIN_HOST_AVFAUDIO=1 swift test --filter AudioTests`
builds ours on the Mac as well (shadowing Apple's inside the package) and runs the engine
tests against it; the macOS CI job does both.

The engine talks to the device through `PlatformAudio` (`Sources/AVFAudio/Platform`):

| Backend | Platform | Shim | Notes |
| --- | --- | --- | --- |
| WASAPI | Windows | `Sources/CWASAPI` (C++ over COM) | Shared mode, event driven; `IAudioClient3` low-latency period when the driver offers one, `IAudioClient` default period otherwise; render thread on the "Pro Audio" MMCSS task; the device's mix format and rate. |
| PipeWire | Linux | `Sources/CPipeWire` (dlopen) | Needs `libpipewire-0.3-dev` at build time (the `CPipeWireSystem` target supplies the include paths); without the headers the shim is a stub. `pw_stream` with `RT_PROCESS`; PipeWire resamples to the graph rate. |
| ALSA | Linux | `Sources/CALSA` (dlopen) | Fallback when PipeWire is absent at runtime; `default` PCM, 10 ms periods, blocking writes. Needs `libasound2-dev` at build time. |
| Null | all | none | A timer thread rendering into a scratch buffer: the engine runs with no device (CI, the container, tests). |

`APPKITWIN_AUDIO_BACKEND=wasapi|pipewire|alsa|null` picks one; otherwise the platform's
native backend, falling through PipeWire to ALSA on Linux. `AVAudioEngine.start()` throws
when no device stream opens, and `APPKITWIN_AUDIO_LOG=1` prints why a Linux backend was
skipped. The engine logs nothing itself; `AVAudioEngine._outputDescription` (port only)
names the backend, device, rate, period and latency, and the AudioPlayer example shows it
in its status line.

Machines without a sound device (CI runners, the Linux container) verify the engine
through `AVAudioEngine`'s manual rendering mode: `swift run AudioPlayer --render out.wav`
renders two seconds of the example's mix through `AVAudioFile` and exits, which every CI
job and `tools/linux/run.sh` do, and `AudioTests` render offline and compare sample for
sample. Real playback is checked on the Windows machine (device name, latency, pause and
loop, a window drag without glitches) and recorded in the pull request.

## Regenerating the API inventory and stubs

```bash
tools/apigen/extract.sh          # macOS only: dumps symbol graphs from the SDK
tools/apigen/probe.sh            # macOS only: records enum raw values and string constants
python3 tools/apigen/apigen.py   # emits Generated/, Stubs/Pending/ and docs/API-COVERAGE.md
```

## Rendering comparisons

[comparisons.md](comparisons.md) shows the same windows on each platform. Regenerate the
macOS column headless and the Linux column under Xvfb:

```bash
swift run HelloWindow --swiftui --layout --screenshot docs/images/compare
docker run --rm -v "$PWD":/src -w /src appkitwin-linux bash tools/linux/compare.sh
```

The Windows column is captured from the live app on the Windows test machine.
