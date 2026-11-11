# AppKitCross

[![CI](https://github.com/medcelerate/AppKitCross/actions/workflows/ci.yml/badge.svg)](https://github.com/medcelerate/AppKitCross/actions/workflows/ci.yml)

AppKit and SwiftUI for Windows and Linux, in Swift. Code written against Apple's
frameworks compiles unchanged and runs on native Windows APIs (Win32, Direct2D,
DirectWrite, DirectComposition, Direct3D 12) or on Linux (X11 or Wayland, Cairo, Pango).

The package provides the modules by their Apple names: `AppKit`, `SwiftUI`, `CoreGraphics`,
`CoreText`, `QuartzCore`, `Metal`, `MetalKit`, `Combine`, `UniformTypeIdentifiers` and
`ImageIO`. Public API names, signatures and behaviour follow Apple's documentation exactly;
anything not yet implemented says so rather than pretending.

## The same windows on three platforms

The sample app, rendered by the same code on macOS, Linux and Windows.

<table>
  <tr>
    <th>macOS</th>
    <th>Linux (X11, Cairo, Pango)</th>
    <th>Windows (Direct2D, DirectWrite)</th>
  </tr>
  <tr>
    <td><img src="docs/images/compare/hellowindow-macos.png" width="300" alt="HelloWindow on macOS"></td>
    <td><img src="docs/images/compare/hellowindow-linux.png" width="300" alt="HelloWindow on Linux"></td>
    <td><img src="docs/images/compare/hellowindow-windows.png" width="300" alt="HelloWindow on Windows"></td>
  </tr>
  <tr>
    <td><img src="docs/images/compare/layout-demo-macos.png" width="300" alt="Layout Demo on macOS"></td>
    <td><img src="docs/images/compare/layout-demo-linux.png" width="300" alt="Layout Demo on Linux"></td>
    <td><img src="docs/images/compare/layout-demo-windows.png" width="300" alt="Layout Demo on Windows"></td>
  </tr>
  <tr>
    <td><img src="docs/images/compare/swiftui-demo-macos.png" width="300" alt="SwiftUI demo on macOS"></td>
    <td><img src="docs/images/compare/swiftui-demo-linux.png" width="300" alt="SwiftUI demo on Linux"></td>
    <td><img src="docs/images/compare/swiftui-demo-windows.png" width="300" alt="SwiftUI demo on Windows"></td>
  </tr>
</table>

Top to bottom: AppKit drawing, controls, a scroll view and a Core Animation badge; the
Auto Layout form; the SwiftUI demo. Notes on what differs, and how to regenerate the
images, are in [docs/comparisons.md](docs/comparisons.md).

## Status

Usable for real apps, with gaps. Windows, drawing, text, controls, menus, layout, Core
Animation, Metal, the text system and the SwiftUI runtime are in place and verified on a
Windows 11 machine and in a Linux container; the macOS build is headless and runs the test
suite against Apple's own frameworks as the specification.

Not there yet: Metal swap-chain presentation on Linux, IME on Linux. The full milestone table is
in [docs/ROADMAP.md](docs/ROADMAP.md), and [docs/API-COVERAGE.md](docs/API-COVERAGE.md)
lists every type with what is implemented.

## Getting started

You need Swift 6.2 or newer: on Windows 11 the swift.org toolchain with Visual Studio
Build Tools and the Windows SDK, on Linux a 6.2 toolchain with the Cairo, Pango, HarfBuzz,
X11, Wayland and xkbcommon development packages (or the container in `tools/linux`), on
macOS Xcode 16 or the swift.org toolchain.

```bash
git clone https://github.com/medcelerate/AppKitCross.git
cd AppKitCross
swift build
swift run HelloWindow            # the AppKit sample: drawing, controls, menus, a glass window
swift run HelloWindow --swiftui  # opens the SwiftUI demo window too
tools/library-compat.sh --run    # Examples/LibraryCompat: third-party SwiftUI packages on this port
```

## Examples

Small, self-contained programs under `Examples/`, each an executable target with its own
README. All of them build and run with the same source on macOS, Windows and Linux.

| Example | Shows | Run |
| --- | --- | --- |
| [HelloWindow](Examples/HelloWindow) | The big tour: AppKit drawing, controls, menus, a glass window, the Layout Demo (form, split view, table, Metal) and the SwiftUI demo | `swift run HelloWindow` (`--swiftui`, `--layout`, `--metal`, `--print-pdf out.pdf`) |
| [Calculator](Examples/Calculator) | A SwiftUI `App` with a `WindowGroup`, a button grid, keyboard input through `keyboardShortcut`, a fixed-size window and the standard menu bar with a `CommandMenu` | `swift run Calculator` |
| [FramelessWindow](Examples/FramelessWindow) | A title-bar-less `.fullSizeContentView` window with the standard window buttons, a rounded non-opaque shape, movable by background, the system backdrop through `NSVisualEffectView`, close/minimize/zoom, and a `.borderless` panel | `swift run FramelessWindow` (`--panel`) |
| [Animation](Examples/Animation) | Core Animation: explicit `CABasicAnimation`s (position, opacity, 3D flip under a perspective transform), a `CAKeyframeAnimation` along a path, implicit animations in a `CATransaction`, play/pause/reset, and a SwiftUI `withAnimation` pane | `swift run Animation` (`--paused`) |
| [Drawing](Examples/Drawing) | An `NSView` `draw(_:)` with paths, a gradient, text and images; a freehand sketch canvas with mouse tracking, undo/redo and export to PNG through `NSSavePanel` | `swift run Drawing` (`--export file.png`) |
| [Observable](Examples/Observable) | SwiftUI driven by an `ObservableObject` with `@Published` properties, a live-updating `List`, a detail pane editing through a `Binding`, and a Combine `Timer` publisher feeding the model | `swift run Observable` |
| [LibraryCompat](Examples/LibraryCompat) | Popular third-party SwiftUI packages (Shimmer, ConfettiSwiftUI, WrappingHStack, Defaults, swift-markdown-ui, SwiftUI-Introspect, SwiftUICharts, Nuke) built against this SwiftUI, one tab each; a package of its own, with the verdicts and the API gaps they found in [docs/compatibility/swiftui-libraries.md](docs/compatibility/swiftui-libraries.md) | `tools/library-compat.sh --run` (`--screenshot dir`) |
| [TextEdit](Examples/TextEdit) | A document-based application: `NSDocument`/`NSDocumentController` with plain-text and RTF documents declared in an `Info.plist`, New/Open/Open Recent/Save/Save As/Revert, the unsaved-changes alert on close and quit, the edited dot in the title bar, `NSOpenPanel`/`NSSavePanel` native or package-drawn | `swift run TextEdit` (`file.txt`, `--roundtrip out.rtf`, `--show-save-panel`) |
| [Sheets](Examples/Sheets) | Attached sheets (ADR-0019): an `NSAlert` sheet, the open panel as a sheet, a custom `beginSheet` window with a sheet of its own, the `runModal(for:)` pattern, two queued sheets, and SwiftUI `.sheet`/`.confirmationDialog`; the window is blocked while a sheet is up and the sheet follows it | `swift run Sheets` (`--alert`, `--custom`, `--swiftui-sheet`) |
| [AudioPlayer](Examples/AudioPlayer) | `AVAudioEngine` with two `AVAudioPlayerNode`s (a WAV, AIFF or CAF from `NSOpenPanel`, a generated sine), play/pause/loop/stop, rate and pitch sliders through `AVAudioUnitTimePitch`, an output device pop-up, a record button (`AVAudioRecorder`, played back through the file player), recovery from device changes, a level meter from a mixer tap, the output device and its latency in the status line; `--render` writes two seconds offline through `AVAudioFile` | `swift run AudioPlayer` (`file.wav`, `--render out.wav`, `--rate 1.5 --pitch 300`) |
| [Toolbar](Examples/Toolbar) | `NSToolbar` with image items, a segmented group, a menu item, a search field, validation, chevron overflow and the customization sheet (autosaved); an `NSStatusItem` with a menu in the platform's status area | `swift run Toolbar` |

Add the package to your own app and import the modules by their Apple names:

```swift
// Package.swift
dependencies: [.package(url: "https://github.com/medcelerate/AppKitCross.git", branch: "main")],
targets: [.executableTarget(name: "MyApp", dependencies: [
    .product(name: "AppKit", package: "AppKitCross"),
    .product(name: "SwiftUI", package: "AppKitCross"),
])]
```

A SwiftUI app:

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup("Hello") {
            VStack {
                Text("Hello from SwiftUI").font(.title)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }.padding()
        }
    }
}
```

An AppKit app:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Hello from AppKit"
        window.contentView = NSTextField(labelWithString: "Drawn by AppKitCross")
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

## Learn more

- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): repository layout, building and testing on
  each platform, runtime switches, regenerating the generated code.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/decisions](docs/decisions): how
  the port is put together and why.
- [docs/comparisons.md](docs/comparisons.md): the rendering comparisons in full size.

## License

AppKitCross is released under the Apache License, Version 2.0 (see [LICENSE](LICENSE)).
Bundled third-party code is listed in [NOTICE](NOTICE). AppKit and SwiftUI are Apple's
frameworks; this project implements their public API and is not affiliated with Apple.
