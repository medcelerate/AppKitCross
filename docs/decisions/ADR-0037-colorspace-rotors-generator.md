# ADR-0037: NSColorSpace, accessibility rotors and the generator's `+Types` rule

Date: 2026-11-16. Status: accepted.

## Context

Three generated-stub leftovers, in one change:

1. `NSColorSpace` was generated (26 stubs). ADR-0036 left every NSColorSpace-based member
   unimplemented because of it: `NSBitmapImageRep.colorSpace`, `converting(to:renderingIntent:)`,
   `retagging(with:)`, and behind them `NSScreen.colorSpace` and `canRepresent`. The parallel
   NSColor work (`colorSpace`, `usingColorSpace(_:)`) needs it as well.
2. `NSAccessibilitySearchKey` (42 string constants, all `unimplemented()`) and
   `NSAccessibilityCustomRotor` with its `ItemResult` and `SearchParameters` (25 stubs) were
   generated. Rotors are an open ADR-0013 item.
3. `Generated/NSView+Types.swift` held 32 stubs although NSView is hand-written, and every
   regeneration brought back `NSGestureRecognizer`, `NSStatusItem`, `NSToolbar`,
   `NSToolbarItem`, `NSToolbarItemGroup`, `NSBrowser` and `NSMatrix` `+Types` files and
   reordered `NSSound+Types.swift`. Those files had been deleted and reverted by hand at
   every merge.

## Decision

**Generator rule.** `apigen.py` still writes `Generated/<Name>+Types.swift` for a hand-written
type's nested types, but `nested_only()` now skips every nested type that Core declares.
`core_nested_types()` scans `Sources/AppKit/Core` for types declared one level inside a
top-level class, struct, enum or extension (`NSToolbar.DisplayMode`, `NSView.Invalidations`).
The strays came from nested types that Core already declared without a `skipMembers` entry:
the duplicates only went away because someone deleted the files. With this rule a nested type
moved into Core is never emitted again. A hand-written type whose nested types all live in Core
gets no companion, and `skipMembers` is no longer needed for nested types. The `NSSound` churn
came from the symbol graph's relationship order, which differs between extractions.
Nested types are now emitted clang-imported first (`c:` identifiers), then Swift-overlay ones.
That order is stable, and it reorders eight existing companions once.

The rule does not turn every hand-written type's companion into Core code. The 86 companions
mostly hold enums and option sets with probed raw values, which are real implementations.
Moving them by hand would only add risk. NSView's companion is moved because its contents
were stubs. `GeneratorDriftTests` scans the checked-in Core and `+Types` files with the same
rule, and fails if any companion declares a nested type Core also declares. It also fails if a
companion exists for NSView, NSColorSpace, the rotor, or the seven former strays. A clean
`python3 tools/apigen/apigen.py` on this branch leaves `git status` clean.

**NSView nested types** move to `Core/NSView+Types.swift`:

- The value types are copied unchanged.
- `Invalidating` is implemented through the enclosing-instance subscript: a new value that
  differs runs the invalidation on the view. Its unavailable `wrappedValue` traps as in AppKit.
- `Invalidations.Display`/`Layout`/`Constraints`/`IntrinsicContentSize`/`RestorableState`
  and `Tuple` set the matching NSView flag or call the matching method.
- `LayoutRegion` and `AdaptivityAxis` are implemented. `edgeInsets(for:)`, `rect(for:)` and
  `layoutGuide(for:)` answer from the safe area and margins guides. Corner adaptation is
  recorded but changes nothing, because the port reports no window corner radius.
- `NSViewInvalidating` becomes hand-written, so `.display`, `.layout` and the other static
  members live in AppKit's constrained extensions. That makes `@Invalidating(.display)`
  resolve. The generator could only emit them as unconstrained optional-requirement stubs.

**NSColorSpace.** Every space is a profile in the ICC sense:

- RGB spaces map linear RGB to XYZ relative to D50 through a 3×3 matrix (Bradford-adapted
  colorants, as ICC stores them), with one transfer curve per channel.
- Gray spaces have one curve, and their Y maps to the D50 white.
- CMYK goes through device RGB naively.

The twelve standard spaces carry the names, models, component counts and CoreGraphics names
AppKit reports (all probed on macOS 15). Their primaries and curves are:

- sRGB and extended sRGB: Rec. 709, IEC 61966-2-1 curve.
- Display P3: P3 primaries, sRGB curve.
- Adobe RGB (1998): γ 563/256.
- Generic RGB: Apple's phosphors, γ 1.8.
- Generic Gray: γ 1.8.
- Gray Gamma 2.2 and Device Gray: γ 2.2.
- Device RGB: treated as sRGB.

Conversions agree with AppKit within 0.01. The tests use sRGB→P3, sRGB→Adobe and sRGB→gray
values probed from macOS.

- `iccProfileData` synthesises an ICC v4 display profile (`mluc` names, `XYZ` colorants,
  `para` curves). It is nil for the device spaces, as in AppKit, and for CMYK, because the port
  has no CMYK profile.
- `init(iccProfileData:)` reads RGB matrix/TRC and gray TRC profiles: v2 and v4, `curv` and
  `para` curves, `desc` and `mluc` names. A profile that matches a standard space (same name,
  colorants within 1e-3, curves within 2e-3) is equal to that space. Any other profile keeps its
  bytes. LUT-based and Lab profiles answer nil.
- `init(cgColorSpace:)` maps a standard CoreGraphics name to the standard space. Otherwise it
  reads the CGColorSpace's ICC data where the platform's CoreGraphics has it (Apple's on the
  macOS host build), or falls back to the CGColorSpace's model.
- `cgColorSpace` returns the platform CGColorSpace with Apple's name. The port's CoreGraphics
  gains `extendedSRGB`, `linearSRGB`, `adobeRGB1998`, `extendedGray`, `linearGray` and
  `genericCMYK`, the generic and device names, the `CGColorSpaceCreateDevice*` functions, and
  four-component CMYK colours in `CGColor.rgba`.
- Equality is by standard space, otherwise by ICC bytes or profile.
- `availableColorSpaces(with:)` lists the non-extended standard spaces by model, sorted by
  name as AppKit does. `.unknown` lists gray, then RGB, then CMYK.
- Secure coding archives `NSID` for a standard space and `NSICC` bytes for any other.
- The internal `_convert(_:to:)` is the one entry point for NSColor and NSBitmapImageRep:
  components without alpha in, components out, through D50.

`init(colorSyncProfile:)` and `colorSyncProfile` keep `unimplemented()` (ColorSync is
macOS-only).

Members ADR-0036 listed as blocked, now unblocked:

- `NSBitmapImageRep.colorSpace` maps the colour space name the way AppKit does: calibrated RGB
  is Generic RGB, calibrated white is Generic Gray, and the device names map to the device
  spaces. A retagged or converted rep reports its tag.
- `retagging(with:)` copies the samples into a new rep when the component counts agree.
- `converting(to:renderingIntent:)` writes an 8-bit meshed RGB or gray rep and keeps alpha.
  The intent is unused, because every space here is matrix/TRC.
- `NSScreen.colorSpace` is sRGB, and `canRepresent` is true only for `.sRGB`. The port
  composes in sRGB on Direct2D and Cairo.

**Search keys.** These are macOS 26 constants, so the raw-value probe (run on macOS 15) could
not record them. Their values are the accessibility search-predicate keys macOS has long
exchanged with assistive technology: `AX<Name>SearchKey`, `AXTextStateChangeType` and
`AXTextStateSync`. All 42 strings are present in the macOS 15 system libraries (checked in the
dyld shared cache). A probe on a macOS 26 host should confirm them when one is available.

**Rotors.** `NSAccessibilityCustomRotor`, `ItemResult` and `SearchParameters` are plain data,
as in AppKit:

- `init(label:)` makes a `.custom` rotor; `init(rotorType:)` starts with an empty label.
- The item-search and item-loading delegates are weak.
- Item results hold a target element, or a loading token with a custom label, plus a target
  range (zero-filled).
- Search parameters start zero-filled: no current item, `.previous`, an empty filter.

AppKit has no result limit in `SearchParameters`, so the brief's "result limit" is not added.
`accessibilityCustomRotors()`/`setAccessibilityCustomRotors(_:)` store the list on NSView and
NSAccessibilityElement. Exposing rotors to UI Automation (custom navigation) and AT-SPI
(collection or match rules) is the remaining ADR-0013 rotor item. Neither bridge reads the list
yet.

## Consequences

- Core's `unimplemented(` count goes from 657 to 651: NSView 11 → 8, NSBitmapImageRep
  6 → 3, NSScreen 15 → 13. The new Core files have 2 (the ColorSync pair).
- The generated `NSView+Types.swift`, `NSColorSpace.swift`, `NSViewInvalidating.swift`,
  `NSAccessibilitySearchKey.swift` and `NSAccessibilityCustomRotor.swift` are gone. That
  removes 32 + 26 + 5 + 42 + 25 stubs.
- `docs/API-COVERAGE.md` was stale on main (it still counted NSImage at 170 stubs) and is now
  regenerated.
- The NSColor work can call `NSColorSpace._convert(_:to:)` and the public class properties.
  No public NSColorSpace name differs from Apple's.
- Tests: `ColorSpaceTests` (9), `AccessibilityRotorTests` (4), `NSViewNestedTypesTests` (3)
  and `GeneratorDriftTests` (1), all on the host backend. The search-key and LayoutRegion
  cases need macOS 26 on a Mac host and run unconditionally on Windows and Linux.

Follow-ups: rotor navigation on UIA and AT-SPI; CMYK ICC profiles (a LUT-based reader and
writer); confirming the search-key values on a macOS 26 probe; moving more `+Types` companions
into Core where they hold stubs (NSAccessibility 22, NSImage 18, NSCursor 13, NSPasteboard 10).
