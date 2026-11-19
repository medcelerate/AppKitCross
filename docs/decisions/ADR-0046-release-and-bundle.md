# ADR-0046: Release builds, app folders and crash reports

Status: accepted (2026-11-18)

## Context

A developer who depends on AppKitCross could build and run their app with `swift run`, but
had no way to hand it to a user. Users have no Swift toolchain: the app needs the Swift
runtime, Foundation and ICU, libdispatch and (on Windows) the Visual C++ runtime beside it,
plus its Info.plist, resources and SwiftPM resource bundles. Every CI build and PC check so
far was a debug build, so nothing said the optimizer leaves the port working. And a crash
on a user's machine left nothing behind to diagnose.

## Decision

### 1. Dependent packages build with a plain `swift build`

A package that declares `.product(name: "SwiftUI", package: "AppKitCross")` builds with
`swift build` and no extra flags on all three platforms; `Examples/Dependent` (a ten-line
SwiftUI app with a resource) proves it in CI. What `tools/library-compat.sh` adds is not
needed by a declared dependent:

| library-compat.sh does | for a declared dependent | why |
| --- | --- | --- |
| builds `--target SwiftUI` first | not needed | SwiftPM orders the build by the declared dependency. The two steps exist only because the third-party libraries in LibraryCompat import `SwiftUI` without depending on AppKitCross. |
| `-Xcc -fmodule-map-file=` for every C shim | not needed | SwiftPM passes the module maps (and pkg-config flags of system-library targets) of every C target in a Swift target's dependency closure; again only undeclared importers miss them. |
| `-target <arch>-apple-macosx14.0` on macOS | `platforms: [.macOS(.v14)]` in the dependent's manifest, or depend on the port only off macOS | the port's modules declare macOS 14 on the host build. `Examples/Dependent` uses `condition: .when(platforms: [.windows, .linux])` so a Mac build uses Apple's frameworks, which is what a shipping cross-platform app wants. |
| `-Xfrontend -disable-round-trip-debug-types` (Windows) | not needed | it works around a frontend assertion in one third-party library (SwiftUICharts) on Swift 6.4.1; nothing in the port or a plain dependent trips it. |
| `-j 1` (Windows, Swift 6.2) | still needed on Swift 6.2 | a swift-driver bug (docs/ci-windows-runner.md) that loses a job when two start together. It is a property of the toolchain and the build invocation; a manifest cannot set it: `unsafeFlags` are refused in dependencies, `swiftSettings` cannot limit the driver's parallelism, and a build-tool plugin runs inside the build it would have to throttle. CI passes `-j 1`; Swift releases with the driver fix do not need it. |

So nothing had to move into the manifest; what remains is documented in
docs/DEVELOPMENT.md ("Shipping an app").

### 2. Release configuration in CI

`macos-release`, `linux-release` and `windows-release` build `-c release`, run the whole
test suite in release (`swift test -c release`, testable imports on) and run in parallel
with the debug jobs, so they add runner time but not wall-clock time. `-Ounchecked` is not
used. The Windows job keeps `-j 1`; its release build of the whole package takes about 16
minutes on `windows-2022`. The Swift 6.2 Windows
toolchain CI installs is an asserts build, and its release *test* build (testable imports)
tripped an assertion in the SIL deserializer ("Value Type mismatch?") on SwiftUI's deprecated
`accessibility(hidden:)`: an opaque-result function forwarding to another opaque-result
function that forwarded to a third. `-Xfrontend -disable-cmo` did not avoid it; giving the
private helper a concrete result type and calling it directly from the deprecated spellings
did, without changing any public signature.

The first release runs of the bundled apps found a calling-convention bug in the ADR-0045
`Bundle` hooks: `object(forInfoDictionaryKey:)` returns `Any?`, which is address-only and so
comes back through a caller-provided buffer, but its C trampoline returned four register
words. Debug builds happened to read nil; release builds crashed (DailyTodo through
`UNUserNotificationCenter`, SIGSEGV on Linux, 0xC000001D on Windows). The trampoline now
takes a `swift_indirect_result` buffer, and BundleTests calls the method on Linux.

### 3. `swift package bundle`

A command plugin, `AppBundle` (verb `bundle`, a plugin product so dependents get it), builds
an executable product and runs `AppKitCrossBundle`, an executable whose logic lives in the
`AppBundler` library (tested in `AppBundlerTests`):

```
swift package --allow-writing-to-package-directory bundle --product MyApp [-c release] [--zip] [--appimage]
```

It writes `.build/bundle/<Name>/` (`--output` changes the parent) with everything beside
the executable:

- **Windows**: the DLL closure of the executable, read from the PE import and delay-import
  tables (no `dumpbin` needed), resolved in the loader's order (executable directory,
  System32, Windows directory, PATH). DLLs under the Windows directory and API sets stay;
  everything else is copied: the Swift runtime (`swiftCore`, `swift_Concurrency`,
  `swiftDispatch`, `dispatch`, `BlocksRuntime`, `Foundation`, `FoundationEssentials`,
  `_FoundationICU`, `swiftWinSDK`, `swiftCRT`, …), any DLL the build produced, and the
  Visual C++ runtime (`vcruntime140*.dll`, `msvcp140*.dll`) app-locally from the Visual
  Studio redistributable directory (falling back to the System32 copy). The Universal CRT is
  part of Windows 10 and later. A debug build's import of the debug CRT is reported, since
  it may not be redistributed.
- **Linux**: the `.so` closure, walked through each library's `DT_NEEDED` (parsed from the
  ELF dynamic section) with paths from `ldd`, stopping at system libraries: glibc and the
  loader, libgcc_s and libstdc++, the GPU/display stack (GL, Vulkan loader, X11/xcb,
  Wayland, xkbcommon), fonts (fontconfig, FreeType, HarfBuzz, FriBidi), D-Bus and sound
  (the AppImage excludelist's reasoning: these must match the running system). The Swift
  runtime and Cairo, Pango, GLib, pixman and friends are copied. SwiftPM links executables
  with RUNPATH `$ORIGIN` and the Swift runtime libraries carry it too; a copied library
  whose own dependencies are copied gets RUNPATH `$ORIGIN` through `patchelf` when it is on
  PATH (otherwise those resolve from the system, which is said in the output).
  Libraries the port opens with `dlopen` (hunspell, ALSA, the Vulkan loader) are optional
  features found on the system. `libpipewire-0.3` is the exception: the shim dlopens it too,
  but the `CPipeWireSystem` pkg-config entry also links it, so it is a load-time requirement
  (left to the system; every current desktop distribution has it).
- **macOS**: the executable and app files only; the Swift runtime is part of the OS and a
  real Mac app is built with Xcode.
- **All**: the SwiftPM resource bundles of the product's targets (`<Pkg>_<Target>.resources`;
  the generated `Bundle.module` accessor looks beside the executable first), and the app's
  `Info.plist`, `Resources/` and `*.ico`/`*.png` from the nearest directory, from the
  executable target's directory up to (not including) the package root, that has an
  application `Info.plist`, a `Resources/Info.plist` or a `Resources/` directory
  (`--info-plist`, `--resources`, `--icon` override). The root is shared by every product,
  and on Windows swift-build drops resource-bundle files there (below); the first PC run
  bundled TextEdit's bundle plist into DailyTodo that way. So the root is searched only for
  a target whose sources live there, and a plist with `CFBundlePackageType` BNDL or an
  identifier ending in `.resources` is never taken, by the bundler or by the port's
  `Bundle.main` lookup (ADR-0045 searches the executable target's own bundle, where
  swift-build puts such a plist on Windows). The names are the port's: `Info.plist` or
  `<exe>-Info.plist`, in `Resources/` first; with none, the version for the archive name
  comes from a plist in the executable target's bundle. The walk does go above the target's
  own directory, since a vendored app keeps its plist beside its sources
  (`Examples/MDVault/Resources/Info.plist` above `Sources/MDVault`). `/Info.plist` is
  git-ignored.
- **PDB (Windows)**: SwiftPM's release configuration writes no PDB, so a crash report could
  only give module offsets. The plugin adds `-g -debug-info-format=codeview` and
  `-Xlinker -debug` to a Windows release build (`--no-debug-info` opts out) and copies
  `<Name>.pdb` beside the executable, where DbgHelp finds it on the user's machine. CI
  passes the same flags to its release build so the plugin's build reuses it, and checks
  that the report names `ccrash_crash_now`. The on-disk layout of the bundle identity (ADR-0045, a parallel
  session) decides where these finally go; the copying is one function
  (`Bundler.copyAppFiles`) to change when it lands.

`--zip` writes `<Name>-<version>-<platform>-<arch>.zip` (version from `--version`, else
`CFBundleShortVersionString`, else 0.0.0) with `tar -a` (bsdtar, Windows 10+) or `zip`, and
falls back to a built-in store-only writer. `--appimage` on Linux runs `appimagetool` when
it is on PATH (AppDir with `AppRun`, a `.desktop` file and the PNG icon or a placeholder)
and otherwise says it skipped. No installers, no MSIX.

CI bundles `MDVault`, `DailyTodo` and `Examples/Dependent` on Linux and Windows and runs them
without the toolchain: on Linux with `/usr/lib/swift/linux` moved away and again in a bare
`ubuntu:24.04` container with only the system libraries above installed; on Windows with
PATH cut down to the Windows directories. The zips are uploaded as artifacts.

### 4. Crash reports

`CCrashReport` (C, behind `Platform/CrashReporting.swift`; AppKit core does not import
WinSDK) is installed by `NSApplication.init` on Windows and Linux:

- **Windows**: `SetUnhandledExceptionFilter` writes `<app>-<time>-<pid>.dmp`
  (`MiniDumpWriteDump`: thread info, unloaded modules, indirectly referenced memory) and
  `.txt` (exception code and name, address, module and offset, thread, an access
  violation's operation and address, a `StackWalk64` trace with DbgHelp symbols where the
  PDB is found; without one DbgHelp offers the nearest export, "main + 1360341", so a match
  more than 1 MB from its symbol or past its size is left out) under `%LOCALAPPDATA%\<bundle id>\Crashes`, then passes the exception on (the
  previous filter, then Windows Error Reporting). `abort()` ends the process through
  `__fastfail`, which skips the filter, so a SIGABRT handler writes the same report from a
  captured context. The thread keeps 64 KB of stack in reserve so a stack overflow is
  reported. Swift's runtime traps (fatalError, preconditions, force-unwrapping nil) arrive
  as `EXCEPTION_ILLEGAL_INSTRUCTION`/`EXCEPTION_BREAKPOINT`. Swift 6.2 has no runtime
  backtracer on Windows, so the DbgHelp trace is the backtrace.
- **Linux**: SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP and SIGABRT on an alternate stack
  write `<app>-<time>-<pid>.txt` under `$XDG_DATA_HOME/<bundle id>/Crashes`
  (`~/.local/share/...`): signal, fault address, thread, `backtrace_symbols_fd`
  (module+offset) and `/proc/self/maps` for offline symbolication. The handler is
  async-signal-safe (static buffers, hand-formatted numbers, `backtrace` warmed at install)
  and then restores the previous action and re-raises, so the Swift runtime's backtracer
  (`SWIFT_BACKTRACE`) still prints when enabled and the exit status is the signal's.
- The reports directory is created with the first report (on Linux with `mkdir`, which is
  async-signal-safe), so a launch that never crashes leaves nothing on disk.
- The bundle identifier is `Bundle.main.bundleIdentifier`, else the executable's name.
  `APPKITWIN_CRASH_REPORTER=0` turns it off, `APPKITWIN_CRASH_DIR` moves the reports, and
  `APPKITWIN_CRASH_TEST=1|trap|abort` crashes on purpose a second after
  `finishLaunching`. It is not installed under XCTest or on the macOS host build (Apple's
  reporter owns crashes there).
- `NSSetUncaughtExceptionHandler`: off macOS there is nothing to honour. swift-corelibs-
  foundation has no Objective-C exception machinery, so `NSException.raise()` is not
  available and nothing reaches an uncaught-exception handler; Swift errors that escape
  end in a runtime trap, which the handler above reports. On the macOS host build Apple's
  Foundation keeps its own behaviour.

### Upstream: swift-build copies resource bundles into the package root on Windows

Seen with Swift 6.4.1 on Windows: whenever a resource bundle is created or changes, the
build's "Touch `<X>.bundle`" step runs, with the package root as working directory,

```
cmd.exe /c copy /b <.build>\...\<Pkg>_<Target>.bundle +,,
```

`copy /b <file> +,,` updates a file's timestamp; given a directory it copies the
directory's top-level files into the working directory instead. A package root then gains
the bundle's `Info.plist` (`CFBundlePackageType` BNDL, `CFBundleIdentifier
<pkg>.<Target>.resources`) and any top-level resource (`Examples/Dependent` got
`Greeting.txt`). Consumers who find those untracked files in their package root after a
Windows build are seeing this; they are safe to delete. Filing it is the maintainer's call;
a draft:

> **Windows: "Touch" of a resource bundle copies its files into the package root**
>
> On Windows, building a package with a resource-bearing target (`resources: [.copy(...)]`)
> leaves the bundle's top-level files (`Info.plist`, copied resources) in the package
> root. With `-v`, after "Create directory", "Copy Resources" and "Process plist" for
> `<Pkg>_<Target>.bundle`, the Touch step runs
> `cmd.exe /c copy /b <path>\<Pkg>_<Target>.bundle +,,` with the package root as the
> working directory. `copy /b <dir> +,,` does not update a directory's timestamp; it copies
> the directory's files into the current directory. Reproduce: `swift package init --type
> executable`, add a resource, `swift build` on Windows, `git status`. Expected: nothing new
> in the package root. Seen with Swift 6.4.1 (swift-build). A fix would touch the
> directory another way (e.g. `SetFileTime`, or skip touching directories).

## Consequences

- A dependent ships an app folder or zip that runs on a machine without Swift; CI checks
  that on Linux (bare Ubuntu) and Windows (PATH without the toolchain) on every PR.
- Release CI roughly doubles runner minutes, not wall-clock time.
- The Linux folder runs on distributions at least as new as the one it was built on (glibc
  and libstdc++ come from the system): build on the oldest distribution you support.
- Windows minidumps open in Visual Studio or WinDbg with the PDB from the same build; keep
  the PDB of every release you ship.
