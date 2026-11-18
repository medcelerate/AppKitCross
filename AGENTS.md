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
every call works; grep before you rely on a rarely used member (section 5).

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

var packageDeps: [Package.Dependency] = []
var appDeps: [Target.Dependency] = []
if usePort {
    packageDeps.append(.package(url: "https://github.com/medcelerate/AppKitCross.git", branch: "main"))
    appDeps += [.product(name: "AppKit", package: "AppKitCross"),
                .product(name: "SwiftUI", package: "AppKitCross")]
    #if os(Linux) || os(Windows)
    // Only what the app imports: Combine, UniformTypeIdentifiers, ImageIO, AVFAudio, ...
    appDeps += [.product(name: "Combine", package: "AppKitCross"),
                .product(name: "UniformTypeIdentifiers", package: "AppKitCross")]
    #endif
}

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v14)],
    dependencies: packageDeps,
    targets: [
        .target(name: "MyAppCore", dependencies: appDeps),
        .executableTarget(name: "MyApp", dependencies: ["MyAppCore"]),
        .testTarget(name: "MyAppTests", dependencies: ["MyAppCore"]),
    ]
)
```

- **`.macOS(.v14)` is the floor.** The port's modules are built for macOS 14, and the
  compiler refuses to import them into a target with a lower deployment target
  (`compiling for macOS 10.15, but module 'SwiftUI' has a minimum deployment target of macOS 14`).
  Raise the app's `platforms` line; for third-party dependencies you cannot edit, see
  section 3.
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
corrupts both. For a path dependency on a local checkout, mount it too
(`-v /path/to/AppKitCross:/port:ro`) and point the manifest's `path:` at `/port`.

**Windows 11**: the swift.org toolchain, Visual Studio Build Tools with the Windows 10/11 SDK
(CI uses the `windows-2022` image; VS 2026's STL needs a newer Clang than Swift 6.2's).
Build **one job at a time**:

```bash
swift build -j 1
swift test -j 1        # with APPKITWIN_HOST_BACKEND=1 set
```

Swift 6.2's driver sometimes drops a job when two start together and exits 1 with no
`error:` line ([docs/ci-windows-runner.md](docs/ci-windows-runner.md)). An exit code 1 with
no diagnostic is that, not your code.

**Third-party SwiftUI packages in the app's graph** (Shimmer, MarkdownUI, ...) do not depend
on AppKitCross, so SwiftPM builds them with no edge to the port's modules and no C shim module
maps. They need the two-step build that [tools/library-compat.sh](tools/library-compat.sh)
does: (1) `swift build --target SwiftUI` (and `--target ImageIO` off macOS) so the port's
modules are in the Modules directory first; (2) `swift build` with, on every compile,
`-Xcc -fmodule-map-file=<abs path>` for each `Sources/C*/module.modulemap`,
`Sources/C*/include/module.modulemap` and `.build/debug/C*.build/module.modulemap`, plus
`-Xcc -I<dir>` for each `Sources/C*` and `Sources/C*/include` (on Linux also
`pkg-config --cflags-only-I pangocairo x11 dbus-1`). Extra flags: on macOS
`-Xswiftc -target -Xswiftc <arch>-apple-macosx14.0` (the libraries declare 10.15 to 12); on
Windows `-Xswiftc -Xfrontend -Xswiftc -disable-round-trip-debug-types -j 1`;
`-Xswiftc -no-color-diagnostics` everywhere. Copy the script and change its paths rather
than retyping the flags. Which libraries work is in
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

A host-backend UI test that hosts SwiftUI, lays it out and writes a PNG (passes on the macOS
host build and in the Linux container; on the host backend the bitmap is at 2x):

```swift
import XCTest
import AppKit
import SwiftUI
@testable import MyAppCore

final class ScreenTests: XCTestCase {
    func testContentRenders() throws {
        // Not `@MainActor func test...`: corelibs XCTest (Linux, Windows) crashes in test
        // discovery on main-actor test methods (swift_dynamicCastFailure in __allTests).
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
| `APPKITWIN_INFO_PLIST=<path>` | the Info.plist the app reads when the executable has none beside it (document types, `CFBundleName`, UTIs) |
| `APPKITWIN_FILE_DIALOG=package` | the package-drawn open/save panel instead of the system one (screenshots, tests) |
| `APPKITWIN_SOFTWARE_LAYERS=1` | Windows: software compositing instead of DirectComposition (blank or flickering layers) |
| `APPKITWIN_METAL_REFERENCE=1` | the CPU Metal device instead of Direct3D 12 or Vulkan |
| `APPKITWIN_LAYOUT_DIRECTION=rtl` | right-to-left layout |
| `APPKITWIN_PRINT_PANEL=native` | Windows: the system print dialog |

## 5. Porting recipe

Work in this order; each step's failures hide the next step's.

1. **Manifest.** Add the dependency as in section 2, raise `platforms` to `.macOS(.v14)`,
   split the views into a library target if you want to test them, and keep one scratch path
   per platform. If the upstream package declares Swift tools 6.0 but its code was written for
   Swift 5, set `swiftSettings: [.swiftLanguageMode(.v5)]` on its targets.
2. **Build on the macOS host first** (`APPKITCROSS=1 swift build --scratch-path .build-port`).
   It is the fastest loop and catches most API gaps; it cannot catch Linux/Windows-only
   issues such as corelibs Foundation differences (`ObservableObject` was missing in a file
   that imported only Foundation and AppKit until the port's AppKit re-exported Combine).
3. **Fix what breaks first.** In the two real apps vendored here these were, in order:
   - Objective-C: `@objc` on a delegate method, `#selector`, `NSObject.perform`. Wrap the
     attribute in `#if canImport(ObjectiveC)` (`Examples/DailyTodo/.../ReminderScheduler.swift`);
     for target/action use `Selector(("name:"))`.
   - Actor isolation (section 2): add `@MainActor` to coordinators and helpers that touch AppKit.
   - Frameworks the port lacks (WebKit, MapKit, StoreKit, Sparkle, ...): see step 5.
   - SwiftUI API the port lacks: a compile error naming the type. Check
     [docs/compatibility/swiftui-apps.md](docs/compatibility/swiftui-apps.md) (what each real
     app hit and how it was fixed) before writing a workaround, then file a gap (section 7).
   - Corelibs Foundation strictness: `NSLock.lock()` is unavailable in `async` functions
     (take it in a synchronous helper); `UserDefaults.didChangeNotification` is not posted for
     a set (the port's `@AppStorage` handles it; your own observers will not fire).
4. **Run the tests** with `APPKITWIN_HOST_BACKEND=1` on Linux (container) and Windows, then
   run the app (Xvfb or a real desktop). Read every trap message (below).
5. **Shim an Apple-only or missing framework** without touching upstream logic: a small file
   or target compiled only off macOS that declares the few names the app uses, with Apple's
   exact signatures, doing the closest honest thing (or nothing, and saying so on stderr):

   ```swift
   #if !canImport(StoreKit)              // Windows and Linux
   enum StoreShim { static var isAvailable: Bool { false } }
   #endif
   ```

   Keep the shim's names Apple's so deleting it later is the whole migration. Put a call
   that cannot work off macOS behind `#if os(macOS)` in the app, with an `#else` that tells
   the user the feature is unavailable. Do not edit `.build/checkouts/AppKitCross`.
6. **Read a trap and choose.** A trap prints `<Module>/<File>.swift:<line>: Fatal error:
   AppKitCross: ...` with the member name (`#function`, so without the type; the file names
   the type). Find it in the source and in `docs/API-COVERAGE.md`:

   ```bash
   grep -rn "unimplemented()\|appleOnlyUnavailable(" .build/checkouts/AppKitCross/Sources/AppKit/Generated/NSImage.swift | head
   ```

   | Trap | What to do |
   | --- | --- |
   | `exists only on macOS` | Never coming. `#if os(macOS)` around the call, or a different API |
   | `is not implemented yet`, on a path the user needs | File a gap (section 7); meanwhile `#if os(macOS)` with a degraded `#else` |
   | `is not implemented yet`, on a cosmetic path | `#if os(macOS)` it away and note it |
   | `optional requirement ... has no default yet` | Implement that delegate method in your type (any body Apple documents as the default) |

   Never patch the port's sources from the app repository, and never paper over a trap with a
   dummy value in a shim that claims to be the real API.
7. **Platform conventions the port switches for you** (do not "fix" these in the app):
   Command shortcuts are **Ctrl** on Windows and Linux (`keyboardShortcut("s")` answers
   Ctrl+S, and menus show "Ctrl+S"); Alt is `.option` and the Windows/Super key is
   `.control`. The main menu becomes the window's menu bar on
   Windows; X11 and Wayland have no menu bar, so key equivalents work but the menu is only
   reachable through accessibility (put anything important in the window or a toolbar too).
   A SwiftUI app quits when its last window closes off macOS (no Dock to reopen it), unless
   it has a status item or its delegate answers
   `applicationShouldTerminateAfterLastWindowClosed`. Window chrome, caption buttons and
   Wayland client-side decorations are the port's.
8. **Performance rules** the ports of real apps had to learn (each one spun a core):
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
9. **Check the details corelibs changes**: file paths under `FileManager`'s application
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
- **Info.plist**: read from `APPKITWIN_INFO_PLIST`, else `Info.plist` beside the executable,
  else `Bundle.main`. Without it the app is named after its executable, and imported UTIs
  (for example Markdown) have no extensions off macOS, so those files will not open.
- **Printing** (ADR-0022): the port's print panel everywhere (`APPKITWIN_PRINT_PANEL=native`
  for Windows' own); PDF output through the platform's writer; CUPS on Linux.
- **Accessibility** (ADR-0013): `NSAccessibility` maps to UI Automation (Narrator,
  Accessibility Insights) and AT-SPI2 (Orca). Standard controls need nothing; custom views
  need the same `setAccessibility...` calls as on macOS.
- **Audio** (ADR-0014): `AVAudioEngine` over WASAPI, PipeWire or ALSA. `AVPlayer` and video
  are not ported.
- **Metal** (ADR-0004, ADR-0012): Direct3D 12 on Windows, Vulkan on Linux, MSL translated;
  `MTKView` presents through a swap chain on both.

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

<!-- PLACEHOLDER(app-bundle-identity): replace this section's first part when the
"bundle, resources, localization and app identity" PR merges (ADR-0045,
docs/DEVELOPMENT.md "App layout on Windows and Linux"). It should cover: the folder layout
beside the executable (Info.plist, Resources, .lproj localizations, the icon), how
Bundle.main and Bundle.module resolve there, CFBundleIdentifier as the app's identity
(AUMID, desktop file id), file associations and single-instance hand-off. -->

**App layout, resources and identity**: *pending (the app bundle and identity work, ADR-0045).*
Today: SwiftPM resources (`Bundle.module`) work off macOS; give the app an Info.plist through
`APPKITWIN_INFO_PLIST` or beside the executable (section 6).

<!-- PLACEHOLDER(release-bundle-tool): replace when the release CI and
`swift package bundle` command plugin PR merges. It should cover: the plugin invocation,
what the runnable app folder and zip contain on each platform, release build flags
(-c release, Windows -j 1), the release CI workflow to copy, and docs/DEVELOPMENT.md
"Shipping an app". -->

**Packaging (`swift package bundle`) and release builds**: *pending (the release CI and
bundle plugin work).* Today: `swift build -c release` (`-j 1` on Windows) and ship
`.build/release/<App>` with the toolchain's runtime libraries beside it on Windows.

<!-- PLACEHOLDER(ime-text-input): replace when the IME text input PR merges. It should
cover: what works with input methods on Windows (IMM32/TSF) and Linux (X11 XIM, Wayland
text-input-v3 / ibus / fcitx), what the app must do (NSTextInputClient for custom text
views), and how to test composition (APPKITWIN_IME_LAYOUT on Windows). -->

**Input methods (IME)**: *pending (the IME text input work).* Today: Windows composition
reaches `NSTextView`, `NSTextField` and SwiftUI text fields (`APPKITWIN_IME_LAYOUT=00000411`
tests Japanese without changing system settings); Linux has no IME yet.

**macOS**: ship the app as before, built against Apple's frameworks (no `APPKITCROSS`).

## Further reading

- [README.md](README.md): what runs today, with screenshots on all three platforms.
- [docs/API-COVERAGE.md](docs/API-COVERAGE.md): per-type implementation status.
- [docs/compatibility/swiftui-apps.md](docs/compatibility/swiftui-apps.md): every gap two
  real apps hit, with root causes; `Examples/DailyTodo` and `Examples/MDVault` are the apps.
- [docs/compatibility/swiftui-libraries.md](docs/compatibility/swiftui-libraries.md):
  third-party SwiftUI packages, verdict per platform.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/decisions/](docs/decisions/): how and why.
- [docs/ROADMAP.md](docs/ROADMAP.md): milestone state; what is verified on real Windows.
