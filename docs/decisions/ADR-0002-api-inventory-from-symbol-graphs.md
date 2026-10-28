# ADR-0002: The API inventory comes from `swift-symbolgraph-extract`, not hand-copied docs

Status: accepted. Date: 2026-10-28.

## Decision

`tools/apigen/extract.sh` runs `swift-symbolgraph-extract` against the macOS SDK for
AppKit, Foundation, CoreGraphics, QuartzCore and CoreText. The symbol graphs carry, for
every public symbol, the exact Swift declaration (as the SDK imports it), access level,
availability, inheritance/conformance/override relationships, whether a protocol
requirement is optional, and header doc comments. A condensed inventory is committed to
`api-inventory/`; raw graphs are regenerated and git-ignored.

Enum raw values and string constants (notification names, attribute keys) are not in
the symbol graph, so `tools/apigen/probe.sh` compiles a generated Swift program against
the real SDK that prints them, and the result is committed as
`api-inventory/AppKit.values.json`.

## Alternatives rejected

- `swift-api-digester -dump-sdk`: only emits the Swift overlay (about 60 types), not the
  Clang-imported classes.
- Scraping developer.apple.com: not machine-precise about signatures and rate limited.
- `swift-ide-test -print-module`: not shipped in Xcode toolchains.
