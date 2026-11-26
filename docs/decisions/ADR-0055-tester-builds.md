# ADR-0055: Tester builds of a ported app (Sibyl for Windows)

Status: accepted (2026-11-25). Extends ADR-0046.

## Context

ADR-0046 gave a dependent `swift package bundle`: a folder that runs on a machine without
Swift, checked in CI with the port's own examples. Sibyl (ADR-0050, its own repository at
ClockworksTech/Sibyl) is the first app whose Windows build is handed to people outside the
project, and the first run at that showed what the folder alone does not carry:

- Libraries the app opens at run time are invisible to the import walk. Sibyl loads
  `Windows.Devices.Midi2.dll` + `.pri` (MIDI 2.0 on Windows 11 25H2, from the preview NuGet
  package, signed by the project's maintainer rather than Microsoft) and `TurboActivate.dll`
  (licensing) with `LoadLibrary`; without them the app still runs, but on WinMM and with
  licensing unenforced. The bundler had no way to add them; a hand copy after bundling was
  lost by `--zip`.
- A tester needs to know what they got: how to run it, what is known not to work, where a
  crash report lands and what to send back, and exactly which commits built the binary.
  None of that is the bundler's business, so it has to come from the app's repository.
- A download needs a checksum, and the zip needs to be proven outside the build tree, with
  the toolchain off PATH, before it is sent: the only Windows machines are Evan's PC and
  GitHub's runners, and a zip that only ran beside the toolchain has proven little.

## Decision

### `--include` and a `.sha256` sidecar in the bundler

`swift package bundle` takes `--include <path>` (repeatable; a file or directory copied
beside the executable under its own name, last, so it wins over a same-named file the walk
found), for the run-time libraries above and for anything a user should find at the top of
the folder. A missing path is an error, not a thinner folder. `--zip` also writes
`<zip>.sha256` in `sha256sum` format and prints the digest; the hash is the port's own
SHA-256 (`Sources/AppBundler/SHA256.swift`, FIPS 180-4 vectors in the tests), since
CryptoKit is Apple-only and a dependency on swift-crypto would be paid by every consumer's
build for one hash of one file.

### `tools/windows/verify-bundle.ps1`

What the tester will do, scripted: check the sidecar, unzip under `%TEMP%`, refuse links and
a folder without `swiftCore.dll`/`Foundation.dll`, run the executable for ten seconds with
PATH cut to the Windows directories and `LOCALAPPDATA` pointed at a scratch folder, require
it alive (an exit of `0xC0000135` is named as a missing DLL), print what it wrote under that
`LOCALAPPDATA` (where app support and crash reports land) and fail if a `Crashes` folder
appeared. The release CI job does the same inline for the port's examples; the script is for
apps built outside this repository, on a PC or in their own CI.

### The app's repository owns the tester material

Sibyl's branch `claude/windows-tester-build` adds `Scripts/package_windows.ps1` (release
bundle through the plugin, then `BUILD-INFO.txt` with the Sibyl and AppKitCross commits and
the toolchain, the tester README as `README.md`, whisper.cpp's licence under `Licenses/`,
`-Include` extras, `TurboActivate.dll` when `Vendor/TurboActivate` has one; zipped with
Windows' own `tar` as `Sibyl-<version>+g<sha>-windows-<arch>.zip` with a `.sha256`;
`-Verify` runs the script above from the AppKitCross checkout), the README
(`docs/port/README-WINDOWS-TESTERS.md`: a test build, how to run, the ADR-0050 gaps, where
crash reports are and what to send, the `APPKITWIN_*` switches), `Resources/Sibyl.png`
(256 px from the `.icns`, so the port has a window icon: it reads `.png`/`.ico`, not
`.icns`) and a `windows.yml` workflow (windows-2022, Swift 6.2, `-j 1`) that uploads the zip
and sidecar as a run artifact on demand and on pushes to main. The script copies its extras
itself rather than through `--include`, so it works against any AppKitCross main; once the
app's pin passes this ADR it can collapse to one `bundle --zip --include ...` command.

### What is not done

No code signing (SmartScreen warns; the README says so), no installer, no Start-menu
shortcut (Sibyl posts no user notifications, which were the one reason ADR-0043 needed
one), and no Linux tester build yet (the same script shape would do, with `--appimage`).

## Consequences

- Any dependent can ship run-time libraries and tester files in one `bundle` command, and
  gets a checksum for free.
- A tester build is checked the way a tester runs it before it leaves the machine.
- The app's repository, not the port's, says what its testers should know; the port's docs
  (`docs/DEVELOPMENT.md`, "Tester builds") give the recipe to follow.
