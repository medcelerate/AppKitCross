# ADR-0001: The port is written in Swift and reuses Apple's module names

Status: accepted. Date: 2026-10-28.

## Decision

The port is a SwiftPM package whose public modules are named `AppKit`, `CoreGraphics`,
`QuartzCore` and `CoreText`, implemented in Swift over the `WinSDK` module plus small C
module maps for headers `WinSDK` lacks (DirectWrite, DirectComposition).

## Consequences

- `import AppKit` in client code is unchanged between macOS and Windows.
- On macOS, only `AppKit` is declared as a local target. Verified on 2026-10-28 with
  Swift 6.2.3: a local `AppKit` module shadows the system framework and links; a local
  `CoreGraphics` module breaks Apple's Foundation (`CGRect.init(x:y:width:height:)`
  disappears because Foundation re-exports the real CoreGraphics overlay). Hence
  `Package.swift` declares the graphics modules under `#if os(Windows)` only.
- The macOS host build type-checks the shared core against Apple's real CoreGraphics,
  which catches signature drift in our Windows CoreGraphics early.
