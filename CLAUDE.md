# AppKitCross conventions

- Public API names, signatures and semantics must match Apple's AppKit exactly. The
  inventory in `api-inventory/` is the source of truth; do not invent members.
- `Sources/AppKit/Core` is hand-written and owns a class entirely. Once a type is
  listed in `tools/apigen/config.json` under `handwritten`, the generator stops
  emitting it. Seed a new hand-written type by copying its file from `Generated/`.
- Everything else under `Sources/AppKit/Generated` is machine-generated. Never edit
  those files by hand; fix `tools/apigen/apigen.py` and regenerate.
- Unimplemented behaviour calls `unimplemented()` from `Support/Unimplemented.swift`.
  Do not silently return dummy values from a stub.
- Platform code lives behind the protocols in `Platform/Backend.swift`. AppKit core
  files never import `WinSDK` directly.
- The macOS host build exists for type-checking and tests only. Windows-only modules
  (`CoreGraphics`, `CDirectWrite`, `CDirectComposition`) are only declared in
  `Package.swift` when building on Windows; on macOS the core compiles against Apple's
  real CoreGraphics so signatures stay honest.
- Swift language mode is 5 with strict concurrency warnings. AppKit types that are
  `@MainActor` in Apple's SDK stay `@MainActor` here.
