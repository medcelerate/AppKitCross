# AGENTS.md: porting a Mac app to Windows and Linux with AppKitCross

This file is for an agent (or a person) working in **someone else's Mac app repository** who
wants that app to build, test, run and ship on Windows and Linux. If you are changing
AppKitCross itself, read [CLAUDE.md](CLAUDE.md) and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
instead.

Paths are relative to the AppKitCross checkout; in a dependent package that is
`<scratch path>/checkouts/AppKitCross/` (`.build/checkouts/AppKitCross/` by default).

## 1. What the package is, and is not

AppKitCross implements Apple's frameworks under **Apple's module names and signatures** so an
unmodified Mac app compiles on Windows (Win32, Direct2D, DirectWrite, DirectComposition,
Direct3D 12) and Linux (X11 or Wayland, Cairo, Pango). It is not a cross-platform toolkit with
its own API: you never write AppKitCross-specific code to use it.

| Module | Windows / Linux | macOS host build |
| --- | --- | --- |
| `AppKit`, `Cocoa`, `SwiftUI`, `Metal`, `MetalKit` | the port | the port (shadows Apple's; headless) |
| `QuartzCore` | the port | the port, inside the package |
| `CoreGraphics`, `CoreText` | the port (Direct2D/DirectWrite or Cairo/Pango) | Apple's |
| `Combine`, `UniformTypeIdentifiers`, `ImageIO` | the port | Apple's |
| `AVFAudio`, `AVFoundation` (audio only) | the port | Apple's |
| `UserNotifications`, `ServiceManagement` | the port (ADR-0043) | Apple's |

Not available anywhere: Observation-driven SwiftUI (`@Observable` models do not update views;
use `ObservableObject`), SwiftData, Core Data, WebKit, MapKit, AVKit, nibs and storyboards
(code-built UI only), the Objective-C runtime (`@objc`, `#selector`, `perform(_:)` with
dynamic dispatch, `import ObjectiveC`), SF Symbols glyphs (`Image(systemName:)` draws nothing).

Three kinds of "missing", and how each shows up:

1. **Not declared**: a SwiftUI type or modifier the port lacks fails at compile time
   (`cannot find 'X' in scope`, `has no member 'y'`).
2. **Declared but not written yet**: the AppKit member compiles and traps when called with
   `` AppKitCross: `name` is not implemented yet `` (`unimplemented()`), or
   `` AppKitCross: optional requirement `name` has no default yet ``.
3. **Apple-only** (ADR-0044): Touch Bar, Writing Tools, the macOS speech engine, Sharing
   services, OpenGL, Help Books and a few Core members. They compile and trap with
   `` `name` exists only on macOS (Apple hardware, service or engine) ``. The port will never
   implement these.

[docs/API-COVERAGE.md](docs/API-COVERAGE.md) lists every AppKit type with its status, the
number of members still stubbed and the Apple-only list. A clean build does **not** mean
every call works; grep before you rely on a rarely used member (section 5, step 7).

## 2. Add the dependency

Products by platform: `AppKit`, `Cocoa`, `SwiftUI`, `Metal`, `MetalKit` everywhere; `Combine`,
`UniformTypeIdentifiers`, `ImageIO`, `AVFAudio`, `AVFoundation`, `UserNotifications`,
`ServiceManagement` **only on Windows and Linux**. SwiftPM refuses a product that does not
exist on the host even under `condition: .when(platforms:)`
(`product 'Combine' ... not found in package 'AppKitCross'`), so gate those with `#if os` in
the manifest:

```swift
// swift-tools-version:5.9
import PackageDescription
import Foundation

// macOS normally builds against Apple's frameworks; APPKITCROSS=1 builds against the port
// (type-check and test loop, section 4). Windows and Linux always use the port.
#if os(macOS)
let usePort = ProcessInfo.processInfo.environment["APPKITCROSS"] == "1"
#else
let usePort = true
#endif

// A local checkout instead of GitHub: APPKITCROSS_PATH=/path/to/AppKitCross. SwiftPM names a
// path dependency after its directory, so `port` must be that directory's last component.
let portPath = ProcessInfo.processInfo.environment["APPKITCROSS_PATH"]
let port = portPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "AppKitCross"

var packageDeps: [Package.Dependency] = []
var appDeps: [Target.Dependency] = []
if usePort {
    packageDeps.append(portPath.map { .package(path: $0) }
        ?? .package(url: "https://github.com/medcelerate/AppKitCross.git", branch: "main"))
    appDeps += [.product(name: "AppKit", package: port), .product(name: "SwiftUI", package: port)]
    #if os(Linux) || os(Windows)
    // Only what the app imports: Combine, UniformTypeIdentifiers, ImageIO, AVFAudio, ...
    appDeps += [.product(name: "Combine", package: port),
                .product(name: "UniformTypeIdentifiers", package: port)]
    #endif
}
// `#if APPKITCROSS` in the app's code: true on every port build, the macOS host build too.
let portSettings: [SwiftSetting] = usePort ? [.define("APPKITCROSS")] : []

let package = Package(
    name: "MyApp",
    // The port needs 14; the Apple build keeps whatever the app declared before.
    platforms: [usePort ? .macOS(.v14) : .macOS(.v13)],
    dependencies: packageDeps,
    targets: [
        .target(name: "MyAppCore", dependencies: appDeps, swiftSettings: portSettings),
        .executableTarget(name: "MyApp", dependencies: ["MyAppCore"], swiftSettings: portSettings),
        .testTarget(name: "MyAppTests", dependencies: ["MyAppCore"], swiftSettings: portSettings),
    ]
)
```

**`#if APPKITCROSS`, not `#if os(macOS)`, marks a port gap.** The macOS host build is
`os(macOS)` too, so `#if os(macOS)` cannot hide a gap from the loop you will use most;
`os(macOS)` only separates Windows and Linux.

- **`.macOS(.v14)` is the floor.** The port's modules are built for macOS 14, and the
  compiler refuses to import them into a target with a lower deployment target
  (`compiling for macOS 10.15, but module 'SwiftUI' has a minimum deployment target of macOS 14`).
  Raise it for port builds only, as above. The `swift-tools-version:5.9` line is what was
  tested; an app with one executable target can put `appDeps` and the settings on that target
  and `@testable import` it from its tests, no split needed; for third-party dependencies you cannot edit,
  see section 3.
- There are no release tags yet: depend on `branch: "main"` (or pin a `revision:`).
- `UserNotifications` and `ServiceManagement` also resolve through `AppKit` off macOS, as on
  macOS, but naming them does no harm.
- An app that is an **Xcode project** (`.xcodeproj`) has no manifest to add this to: write a
  `Package.swift` beside it whose targets point at the existing source folders (`path:`,
  `exclude:` for `Assets.xcassets`, `Info.plist`, `*.entitlements`, `Preview Content`), and keep
  the Xcode project for the Mac build.
- Swift language mode: the port's main-actor annotations are Swift, not imported Objective-C,
  so they are **not** implicitly `@preconcurrency`. Code Apple's SDK accepts in Swift 5 mode
  (a nonisolated class touching `NSTextView.textStorage`) can be an error here. Add
  `@MainActor` to the type that touches AppKit; it is correct on macOS too.

## 3. Build on each platform

Swift 6.2 or newer everywhere (CI: Xcode 26 on macOS, `6.2-RELEASE` on Windows,
`swift:6.2-noble` on Linux; the Windows test machine runs 6.4.1).

**macOS (host build).** Use a separate scratch path so the port build and the Apple build
never share a manifest cache or module directory:

```bash
APPKITCROSS=1 swift build --scratch-path .build-port
APPKITCROSS=1 swift test --scratch-path .build-port
```

Never build the port into the default `.build`: its `SwiftUI`/`AppKit` modules stay in
`.build/.../Modules` and a later plain build picks them up (`compiling for macOS 13.0, but
module 'SwiftUI' has a minimum deployment target of macOS 14.0`). If it happened, delete
`.build`.

**Linux**, apt packages (from `Package.swift`'s `providers` and CI's install line):

```bash
sudo apt-get install -y pkg-config libcairo2-dev libpango1.0-dev libx11-dev libxi-dev \
    libwayland-dev libxkbcommon-dev libdbus-1-dev libpipewire-0.3-dev libasound2-dev \
    libhunspell-1.7-0 hunspell-en-us
swift build
```

Optional: `libvulkan-dev mesa-vulkan-drivers glslang-tools` for the Vulkan Metal backend
(without them `Metal` falls back to the CPU reference device), `xvfb` and `sway` to run
windows headless. From a Mac, use the repository's image (Swift 6.2, all of the above):

```bash
docker build -t appkitcross-linux -f tools/linux/Dockerfile .          # in the AppKitCross checkout
docker run --rm -v "$PWD":/app -w /app appkitcross-linux \
    bash -c "swift build --scratch-path .build-linux && APPKITWIN_HOST_BACKEND=1 swift test --scratch-path .build-linux"
```

Always give the container its own `--scratch-path`: sharing `.build` with the macOS build
corrupts both. For a local checkout, mount it under its own name
(`-v /path/to/AppKitCross:/AppKitCross:ro -e APPKITCROSS_PATH=/AppKitCross`). Add
`.build-port/` and `.build-linux/` to the app's `.gitignore`. The port's own sources print
hundreds of Swift 6 concurrency warnings and notes while they compile; they are not the
app's. Read build output through `grep "error:"`, or keep only lines under the app's own
`Sources/` and `Tests/`.

**Windows 11**: the swift.org toolchain, Visual Studio Build Tools with the Windows 10/11 SDK
(CI uses the `windows-2022` image; VS 2026's STL needs a newer Clang than Swift 6.2's).
Build **one job at a time**:

```bash
swift build -j 1       # -j 1 with Swift 6.2; 6.4.1 builds without it
swift test -j 1        # with APPKITWIN_HOST_BACKEND=1 set
```

Swift 6.2's driver sometimes drops a job when two start together and exits 1 with no
`error:` line ([docs/ci-windows-runner.md](docs/ci-windows-runner.md)). An exit code 1 with
no diagnostic is that, not your code.

**Third-party SwiftUI packages in the app's graph** (Shimmer, MarkdownUI, ...) do not depend
on AppKitCross, so SwiftPM builds them with no edge to the port's modules and no C shim module
maps. Copy [tools/library-compat.sh](tools/library-compat.sh) and change its paths: it builds
in two steps, (1) `swift build --target SwiftUI` (and `--target ImageIO` off macOS) so the
port's modules are in the Modules directory first, (2) `swift build` passing
`-Xcc -fmodule-map-file=` and `-Xcc -I` for every C shim of the port, plus
`-Xswiftc -target -Xswiftc <arch>-apple-macosx14.0` on macOS (the libraries declare 10.15 to
12) and `-Xswiftc -Xfrontend -Xswiftc -disable-round-trip-debug-types -j 1` on Windows. Which libraries work is in
[docs/compatibility/swiftui-libraries.md](docs/compatibility/swiftui-libraries.md); a library
that switches `#if os(macOS) ... #else import UIKit` can never build off macOS without an
upstream change to `#if canImport(AppKit)`.

## 4. Run and verify headless

The macOS host build has **no windows**: AppKit runs on the headless host backend, and
`swift run MyApp` starts, opens nothing and never exits. On the Mac, verify through tests.
On Windows and Linux a plain run uses the native backend.

| Goal | How |
| --- | --- |
| Unit and UI tests on Windows/Linux | `APPKITWIN_HOST_BACKEND=1 swift test` (the suite expects the headless backend; unset it before running the app, or no window appears and stderr says so) |
| Run under X11 without a display | `Xvfb :99 -screen 0 1280x800x24 & export DISPLAY=:99; APPKITWIN_LINUX_BACKEND=x11 .build/debug/MyApp` |
| Screenshot the whole X screen | `xwd -root -silent \| convert xwd:- shot.png` (`x11-apps`, `imagemagick`; see `tools/linux/run.sh`) |
| Wayland | `tools/linux/run-wayland.sh` (headless sway, `grim`) |
| Render one view to PNG, any backend | `cacheDisplay` (below) |

**No `@MainActor` on `XCTestCase` subclasses or test methods.** Corelibs XCTest (Linux,
Windows) crashes in test discovery on them (`Could not cast value of type '(...) ->
@MainActor () throws -> ()'`, signal 6), and the macOS host build cannot catch it. Keep test
classes nonisolated and wrap main-actor work in `MainActor.assumeIsolated { }`.

A host-backend UI test that hosts SwiftUI, lays it out and writes a PNG (passes on the macOS
host build and in the Linux container; on the host backend the bitmap is at 2x):

```swift
import XCTest
import AppKit
import SwiftUI
@testable import MyAppCore

final class ScreenTests: XCTestCase {
    func testContentRenders() throws {
        MainActor.assumeIsolated {
            let host = NSHostingView(rootView: ContentView())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try? png.write(to: URL(fileURLWithPath: NSTemporaryDirectory() + "content.png"))
            // Find controls by walking host.subviews: NSButton, NSTextField, ...
        }
    }
}
```

Testing an `App` scene: put the views in a library target (`MyAppCore` above) and test the
views; `@testable import` of the executable target also works (checked on the macOS host
build). A `@main` type
in `main.swift` fails here (`call to main actor-isolated static method 'main()'`): put
`@main struct MyApp: App` in a file not named `main.swift`.

Runtime switches (the full table is in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#runtime-switches)):

| Variable | Use it for |
| --- | --- |
| `APPKITWIN_HOST_BACKEND=1` | headless backend (tests, CI without a display) |
| `APPKITWIN_LINUX_BACKEND=x11\|wayland` | force a Linux window system |
| `APPKITWIN_TRACE=1` | every invalidation, SwiftUI node update (`setNeedsUpdate <View>`) and layout pass: repaint loops, a busy idle CPU |
| `APPKITWIN_TRACE_FRAMES=1` | what each frame costs (solve, layout, draw, tick lateness) |
| `APPKITWIN_TRACE_TEXTINPUT=1` | every input method step (`[textinput] ...`): composition that does not reach a text view, a candidate window in the wrong place |
| `APPKITWIN_INFO_PLIST=<path>` | the Info.plist the app reads when the executable has none beside it (document types, `CFBundleName`, UTIs) |
| `APPKITWIN_FILE_DIALOG=package` | the package-drawn open/save panel instead of the system one (screenshots, tests) |
| `APPKITWIN_SOFTWARE_LAYERS=1` | Windows: software compositing instead of DirectComposition (blank or flickering layers) |
| `APPKITWIN_METAL_REFERENCE=1` | the CPU Metal device instead of Direct3D 12 or Vulkan |

## 5. Porting recipe

Work in this order; each step's failures hide the next step's.

1. **Pre-flight greps** (each saves a Linux round trip; the macOS host build cannot see
   them): `grep -rn "@MainActor" Tests/` (remove it from `XCTestCase` classes and test
   methods, section 4); `grep -rln "URLSession\|URLRequest" Sources/` (add the
   `FoundationNetworking` import, step 10); `grep -rn "#Preview\|SecureField\|onReceive\|onDelete" Sources/`
   (known gaps, step 4).
2. **Manifest.** Add the dependency as in section 2, raise `platforms` to `.macOS(.v14)`,
   split the views into a library target if you want to test them, and keep one scratch path
   per platform. If the upstream package declares Swift tools 6.0 but its code was written for
   Swift 5, set `swiftSettings: [.swiftLanguageMode(.v5)]` on its targets.
3. **Build on the macOS host first** (`APPKITCROSS=1 swift build --scratch-path .build-port`).
   It is the fastest loop and catches most API gaps; it cannot catch Linux/Windows-only
   issues such as corelibs Foundation differences (`ObservableObject` was missing in a file
   that imported only Foundation and AppKit until the port's AppKit re-exported Combine).
4. **Fix what breaks first.** In the two real apps vendored here these were, in order:
   - Objective-C: `@objc` on a delegate method, `#selector`, `NSObject.perform`. Wrap the
     attribute in `#if canImport(ObjectiveC)` (`Examples/DailyTodo/.../ReminderScheduler.swift`);
     for target/action use `Selector(("name:"))`.
   - Actor isolation (section 2): add `@MainActor` to coordinators and helpers that touch AppKit.
   - Frameworks the port lacks (WebKit, MapKit, StoreKit, Sparkle, ...): see step 6.
   - SwiftUI API the port lacks: expect several in any app. Known missing (2026-11-18):
     `#Preview` (wrap previews in `#if !APPKITCROSS`), `SecureField`, `onReceive`,
     `ForEach.onDelete`, `remove(atOffsets:)`, `lineLimit(_: ClosedRange)`,
     `TextField(_:text:axis:)`, and `Section { } header: { }` without a footer (reported as
     the misleading `generic parameter 'Footer' could not be inferred`). Check
     [docs/compatibility/swiftui-apps.md](docs/compatibility/swiftui-apps.md) for what real
     apps hit, then shim (step 6) and file a gap (section 7).
   - Corelibs Foundation strictness: `NSLock.lock()` is unavailable in `async` functions
     (take it in a synchronous helper); `UserDefaults.didChangeNotification` is not posted for
     a set (the port's `@AppStorage` handles it; your own observers will not fire).
5. **Run the tests** with `APPKITWIN_HOST_BACKEND=1` on Linux (container) and Windows, then
   run the app (Xvfb or a real desktop). Read every trap message (below).
6. **Shim what is missing** without touching upstream logic: one file in the app module
   (for example `PortShims/SwiftUIPortShims.swift`) under `#if APPKITCROSS`, declaring the
   few names the app uses with Apple's exact signatures and doing the closest honest thing,
   or nothing while saying so on stderr. A missing framework (WebKit, StoreKit, ...) is
   gated with `#if canImport(X)` instead; a missing member of the port's own SwiftUI or
   AppKit cannot be, since the module imports fine.

   [docs/compatibility/swiftui-shims.md](docs/compatibility/swiftui-shims.md) has a ready-made
   file covering every gap listed in step 4, each with the compiler messages it answers.

   Keep the names Apple's, so deleting the file is the whole migration; when the port adds
   a name, the shim turns into an ambiguity error, which is the cue to delete that part.
   A call that cannot work on the port goes behind `#if !APPKITCROSS` with an `#else` that
   tells the user the feature is unavailable. Never edit the AppKitCross checkout.
7. **Read a trap and choose.** A trap prints `<Module>/<File>.swift:<line>: Fatal error:
   AppKitCross: ...` with the member name (`#function`, so without the type; the file names
   the type). Find it in the source and in `docs/API-COVERAGE.md`:

   ```bash
   # in the checkout: .build-port/checkouts/AppKitCross, or your APPKITCROSS_PATH
   grep -rn "unimplemented()\|appleOnlyUnavailable(" Sources/AppKit/Generated/NSImage.swift | head
   ```

   | Trap | What to do |
   | --- | --- |
   | `exists only on macOS` | Never coming. `#if !APPKITCROSS` around the call (for example a Share button over `NSSharingServicePicker`), or a different API |
   | `is not implemented yet`, on a path the user needs | File a gap (section 7); meanwhile `#if !APPKITCROSS` with a degraded `#else` |
   | `is not implemented yet`, on a cosmetic path | `#if !APPKITCROSS` it away and note it |
   | `optional requirement ... has no default yet` | Implement that delegate method in your type (any body Apple documents as the default) |

   Never patch the port's sources from the app repository, and never paper over a trap with a
   dummy value in a shim that claims to be the real API.
8. **Platform conventions the port switches for you** (do not "fix" these in the app):
   Command shortcuts are **Ctrl** on Windows and Linux (`keyboardShortcut("s")` answers
   Ctrl+S, and menus show "Ctrl+S"); Alt is `.option` and the Windows/Super key is
   `.control`. The main menu becomes the window's menu bar on
   Windows; X11 and Wayland have no menu bar, so key equivalents work but the menu is only
   reachable through accessibility (put anything important in the window or a toolbar too).
   A SwiftUI app quits when its last window closes off macOS (no Dock to reopen it), unless
   it has a status item or its delegate answers
   `applicationShouldTerminateAfterLastWindowClosed`. Window chrome, caption buttons and
   Wayland client-side decorations are the port's.
9. **Performance rules** the ports of real apps had to learn (each one spun a core):
   - Never invalidate from `draw(_:)`: no `needsDisplay = true`, no control or cell setter
     (they invalidate), no layout changes. A draw that schedules the next draw is a busy loop
     on Windows, where each paint can also re-run SwiftUI bodies.
   - In `updateNSView` / `updateNSViewController` and anything a SwiftUI body calls, compare
     before you set: SwiftUI evaluates bodies often and every setter invalidates.
   - Draw only the rows inside `dirtyRect` (a 400-row menu that drew everything starved the
     Win32 message pump).
   - Stop timers and display links when their window closes or is ordered out.
   - Check idle: with the app open and untouched, CPU should be near zero.
     `APPKITWIN_TRACE=1` shows what keeps redrawing (`setNeedsDisplay <View>`,
     `setNeedsUpdate <ViewType>`); in a host-backend test,
     `NSView._invalidationCount` (port-only) must not grow across idle frames.
10. **Check the details corelibs changes** (they fail only off macOS, so build in the Linux
   container early): `URLSession`, `URLRequest` and friends need
   `#if canImport(FoundationNetworking)` / `import FoundationNetworking` / `#endif`; file paths under `FileManager`'s application
   support directory (`%LOCALAPPDATA%`/`%APPDATA%` on Windows, `~/.local/share` on Linux),
   CR LF in files and clipboard text on Windows (the pasteboard converts; your own file I/O
   does not), POSIX permissions on Windows, time zone and date formatting names.

## 6. Platform behaviour the app author must know

- **Notifications** (`UserNotifications`, ADR-0043): Windows toasts and the freedesktop
  notification server. An unpackaged Windows app needs a Start-menu shortcut carrying its
  AppUserModelID and a COM toast activator; the port creates both the first time
  `UNUserNotificationCenter.current()` is used (`<Start menu>\Programs\<name>.lnk`) and
  re-shows toasts for 30 s while the shell indexes it. An installer that makes its own
  shortcut with the same ID turns this into a no-op. Notifications are not delivered while
  the app is not running (no daemon holds an unpackaged app's schedule), and Windows has no
  badge for an unpackaged app (the badge goes to the taskbar button through `NSDockTile`).
- **Login items** (`SMAppService.mainApp`): the `HKCU\...\Run` key (Startup-folder shortcut
  as a fallback) on Windows, `~/.config/autostart/<app id>.desktop` on Linux. Code that checks
  it runs from an `.app` bundle will refuse off macOS (Daily To Do does).
- **File dialogs**: `NSOpenPanel`/`NSSavePanel` and SwiftUI's document scenes use
  `IFileOpenDialog`/`IFileSaveDialog` on Windows and the xdg-desktop-portal `FileChooser` on
  Linux; with no portal on the session bus the package-drawn panel is used. File types come
  from `UTType`s and the Info.plist's `CFBundleDocumentTypes` (ADR-0017).
- **Info.plist**: `APPKITWIN_INFO_PLIST`, else `Info.plist` beside the executable, in
  `Resources/`, or in the executable target's SwiftPM resource bundle (section 8). Without it
  the app is named after its executable, and imported UTIs (for example Markdown) have no
  extensions off macOS, so those files will not open.
- **Printing** (ADR-0022): the port's print panel everywhere (`APPKITWIN_PRINT_PANEL=native`
  for Windows' own); PDF output through the platform's writer; CUPS on Linux.
- **Secure text**: `NSSecureTextField` (and so any `SecureField` shim built on a text field)
  draws its text in clear on the port today; only accessibility masks it. Do not ship a
  password or API-key field without saying so; this is a known gap.
- **Accessibility** (ADR-0013): `NSAccessibility` maps to UI Automation (Narrator,
  Accessibility Insights) and AT-SPI2 (Orca). Standard controls need nothing; custom views
  need the same `setAccessibility...` calls as on macOS.
- **Audio and GPU**: `AVAudioEngine` over WASAPI, PipeWire or ALSA (ADR-0014; no `AVPlayer`
  or video); Metal over Direct3D 12 or Vulkan with MSL translated (ADR-0004, ADR-0012).

## 7. Report a port gap

Open an issue at <https://github.com/medcelerate/AppKitCross/issues> with the
"Port gap" template (`.github/ISSUE_TEMPLATE/port-gap.md`). Include:

- **API**: the exact Apple symbol (`NSImage.init(systemSymbolName:accessibilityDescription:)`,
  `View.scrollPosition(id:)`) and its module.
- **Platform**: Windows / Linux X11 / Linux Wayland / macOS host build, toolchain
  (`swift --version`) and the AppKitCross commit (`Package.resolved`).
- **Kind**: compile error, trap (paste the whole `AppKitCross: ...` line with file and line),
  or wrong behaviour (expected per Apple's documentation, and what happened instead).
- **Minimal repro**: the smallest code that shows it, ideally a host-backend XCTest like the
  one in section 4.
- **App context**: which open-source app hit it and how you worked around it.

## 8. Shipping

<!-- FILLED(app-bundle-identity) from PR 89 / ADR-0045: true once PR 89 is on main. -->
**App layout, resources and identity** (ADR-0045,
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#app-layout-on-windows-and-linux)): the app folder is
the executable plus the `.resources` bundles `swift build` writes beside it; no restructuring.
`Bundle.main` searches `Resources/`, then the executable target's SwiftPM bundle, then the
folder, so an app that declares its `Info.plist`, `Assets.xcassets` (read uncompiled: image,
app icon and data sets) and `.lproj` folders as target resources finds them as on macOS.
- **Strings**: `.strings`, `.stringsdict` (plural rules) and `.xcstrings` are read;
  `NSLocalizedString`, `String(localized:)`, `LocalizedStringResource` and SwiftUI `Text` keys
  resolve them. The language comes from `-AppleLanguages`, the Windows UI languages, or
  `LANGUAGE`/`LC_*`/`LANG` on Linux (`LANG=de_DE.UTF-8 ./MyApp` to test).
- **Identity**: `CFBundleIdentifier` (else `AppKitCross.<exe>`) is the Wayland app id, the X11
  `WM_CLASS`, the desktop entry id and the crash-report folder. `CFBundleIconName` or
  `CFBundleIconFile` (`.png`/`.ico`, not `.icns`) becomes the window icon.
- **Single instance**: with a `CFBundleIdentifier`, a second launch hands its files and URLs
  to the running app (the document controller or `application(_:open:)`) and exits. Opt out with the Info.plist key
  `AppKitCrossAllowsMultipleInstances` or `APPKITWIN_MULTIPLE_INSTANCES=1`.
- **File associations** (per user, only when asked): run `MyApp --appkitcross-register` /
  `--appkitcross-unregister` from an installer, or set the Info.plist key
  `AppKitCrossRegistersFileTypes` to register at launch. `CFBundleDocumentTypes` and
  `CFBundleURLTypes` say what is registered.
- `APPKITWIN_CORELIBS_BUNDLE=1` turns off the port's `Bundle` routing if you suspect it.

<!-- FILLED(release-bundle-tool) from PR 87 / ADR-0046: true once PR 87 is on main. -->
**Release builds and the app folder** (ADR-0046, [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#shipping-an-app)):

```bash
swift build -c release                                    # Windows with Swift 6.2: add -j 1
swift package --allow-writing-to-package-directory bundle --product MyApp -c release --zip
```

The `bundle` command plugin (from AppKitCross, nothing to declare) writes `.build/bundle/MyApp/`,
a folder that runs on a machine without Swift, and with `--zip`
`MyApp-<version>-<windows|linux>-<arch>.zip`: the executable, the shared libraries the target
machine lacks (Swift runtime and VC++ runtime on Windows; Swift runtime, Cairo, Pango, GLib on
Linux, which needs `patchelf`), the SwiftPM resource bundles, and `Info.plist`, `Resources/`
and icons from the app's directory (`--info-plist`, `--resources`, `--icon` override them).
`--appimage` needs `appimagetool`. A `WARNING: not found` line (exit status 2) means the folder
will not start elsewhere. Build Linux folders on the oldest distribution you support (glibc
comes from the system). Crash reports go to `%LOCALAPPDATA%\<bundle id>\Crashes` or
`~/.local/share/<bundle id>/Crashes`; `APPKITWIN_CRASH_TEST=1` crashes a second after launch
to check them.

**Input methods** (ADR-0047): CJK input works in `NSTextView`, `NSTextField` and the SwiftUI
text fields built on them, through TSF (IMM32 as fallback) on Windows, `text-input-v3` on
Wayland and XIM (ibus, fcitx5) on X11. A custom text view needs what it needs on macOS:
`NSTextInputClient`, including `firstRect(forCharacterRange:actualRange:)` so the candidate
window opens under the text. To test, `APPKITWIN_TRACE_TEXTINPUT=1` logs every composition step,
`APPKITWIN_IME_LAYOUT=00000411` opens Japanese on Windows without a system change, and
`tools/linux/ime-e2e.sh` types pinyin through ibus in the Linux image.

**macOS**: ship as before, built against Apple's frameworks (no `APPKITCROSS`).

## Further reading

[llms.txt](llms.txt) indexes the docs; start with [docs/API-COVERAGE.md](docs/API-COVERAGE.md)
and [docs/compatibility/swiftui-apps.md](docs/compatibility/swiftui-apps.md) (every gap the
vendored apps `Examples/DailyTodo` and `Examples/MDVault` hit, with root causes).
