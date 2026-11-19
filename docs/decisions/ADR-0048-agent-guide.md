# ADR-0048: A consumer guide for agents porting Mac apps (AGENTS.md)

Date: 2026-11-18. Status: accepted.

## Context

The repository's `CLAUDE.md` and `docs/DEVELOPMENT.md` are written for contributors to the
port: the generator, `Core` versus `Generated`, the platform seam. An agent working in
**someone else's Mac app repository** needs different things: how to add the package, the
exact build and test commands on each platform, how to verify a UI with no display, what to
do when a call traps, and which macOS behaviours the port changes. Those facts were spread
over the README, DEVELOPMENT.md, `tools/library-compat.sh`, the two real-app gap tables in
`docs/compatibility/swiftui-apps.md`, ADR-0017, ADR-0043 and ADR-0044, and some were written
nowhere (the manifest product gating, the corelibs XCTest main-actor crash).

## Decision

1. **Two audiences, two files.** `CLAUDE.md` stays the contributor file (one added line points
   consumers away). `AGENTS.md` at the root is the consumer guide, in the `AGENTS.md`
   convention coding agents already look for. It is ordered as the work happens: what the
   package is, the dependency, builds, headless verification, the porting checklist, platform
   behaviour, reporting gaps, shipping. It stays under about 400 lines and links to the deep
   docs instead of repeating them.
2. **`llms.txt`** at the root (llmstxt.org format) indexes the docs for tools that read it.
   No `llms-full.txt`: the docs it would concatenate are far over 100 KB.
3. **Every command is checked.** The build, test and screenshot steps were run on a package
   that depends on AppKitCross, on the macOS host build and in the Linux container, before
   validation. Doing that found three facts the guide now states: products that exist only
   off macOS must be gated with `#if os` in the manifest (`condition: .when(platforms:)` still
   fails product lookup on macOS); `@MainActor` XCTest methods crash corelibs test discovery
   (use `MainActor.assumeIsolated`); and an env-gated manifest (`APPKITCROSS=1`) with its own
   `--scratch-path` lets one checkout build against Apple's frameworks and the port in turn.
4. **Validation by fresh agents.** A general-purpose agent with no access to the authoring
   session gets only the path to `AGENTS.md`, a small outside MIT SwiftUI app (not vendored;
   cloned into a scratch directory) and the instruction to make it build and pass its own
   tests on the macOS host build, reporting every place the guide was wrong, missing or
   ambiguous. The guide is fixed from the report and a second, different agent repeats the
   exercise. Results are recorded below and in the pull request.
5. **Sibling work as placeholders.** The app bundle and identity work (ADR-0045), the
   `swift package bundle` plugin with release CI, and IME text input were in flight; the
   "Shipping" section carries `<!-- PLACEHOLDER(...) -->` blocks naming each, with what works
   today, to be replaced when those land.
6. **A port-gap issue template** (`.github/ISSUE_TEMPLATE/port-gap.md`) with the fields the
   guide asks for: API, platform, toolchain and commit, kind, trap message, minimal repro.

## Validation

The app: [tuanductran/cat-age-calculator](https://github.com/tuanductran/cat-age-calculator)
at `bd960ab` (MIT, 1,506 lines of Swift, a SwiftPM package declaring macOS 13, importing
AppKit, Combine and SwiftUI, 19 XCTest tests; a URLSession client for an AI assistant).
Cloned into a scratch directory, not vendored.

- **Run 1** (guide at the first draft): built and passed its 19 tests plus four
  screen-render tests the agent added, on the macOS host build, in the Linux container and on
  the unchanged Apple build. No `AppKitCross:` trap fired. It reported ten problems; the ones
  that changed the guide: a path dependency is named after its directory, not `AppKitCross`
  (hard stop); `#if os(macOS)` cannot hide a gap from the host build, so the manifest now
  defines `APPKITCROSS`; eight common SwiftUI APIs the port lacks were not listed; `@MainActor`
  test classes (not only methods) crash corelibs discovery; `FoundationNetworking`; keep the
  app's own deployment target for the Apple build; `NSSecureTextField` draws text in clear.
  Checking the fixes found one more: a port build into the default `.build` leaves the port's
  modules where a later Apple build picks them up.
- **Run 2** (a different agent, fresh copy, the revised guide): built and passed the 19 tests
  on the macOS host build and in the Linux container in about six minutes, and every compile
  error was on the guide's list. Its points: ready-made shims for all listed gaps (now
  `docs/compatibility/swiftui-shims.md`, its own file), the exact compiler messages, pre-flight
  greps so the Linux-only failures do not each cost a container round trip, the warning
  volume, the tools version and single-target apps. All are in the guide.

Port gaps both runs found, for the port's list: the eight SwiftUI names in
`swiftui-shims.md`, `SecureField`/`NSSecureTextField` masking, and `@discardableResult` on
`NSPasteboard.clearContents()` and `setString(_:forType:)`. All are closed by ADR-0049.

## Consequences

- The guide is a second place that states build flags and switches; when `tools/library-compat.sh`,
  CI's toolchain or the runtime switches change, `AGENTS.md` must change with them.
- Validation so far covers the macOS host build and the Linux container. A Windows run of the same exercise is a
  follow-up for the Windows test machine.
