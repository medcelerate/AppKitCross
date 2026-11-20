# ADR-0007: CoreText on Windows and Linux

Date: 2026-10-29. Status: accepted.

## Context

Text reached the platforms through a three-call seam (`PlatformTextBackend`: make a
font, measure a string, draw a string) with DirectWrite behind it on Windows and
PangoCairo on Linux. That is enough for labels and the field editor but not for
attributed strings with mixed fonts, for the text system (`NSTextStorage`,
`NSLayoutManager`), for `CATextLayer` fidelity, or for a SwiftUI `Text`. On macOS the
core already runs its string drawing over Apple's CoreText (`HostTextBackend`), so the
CoreText API is the natural layer to make real everywhere.

## Decision

A `CoreText` module in the package, declared only on Windows and Linux, as `CoreGraphics`
is: on macOS the core compiles against Apple's CoreText so signatures stay honest, and
the same tests run against Apple's implementation (the specification) and ours.

Shape:

- Opaque CF-style classes `CTFont`, `CTFontDescriptor`, `CTLine`, `CTRun`, `CTTypesetter`,
  `CTFramesetter`, `CTFrame`, `CTParagraphStyle` with Apple's C function names and
  signatures. CF container types in those signatures (`CFString`, `CFArray`, `CFDictionary`,
  `CFAttributedString`) are the corelibs Foundation classes (`NSString`, `NSArray`, ...),
  which the usual `as` casts bridge, so code written for Apple's CoreText compiles
  unchanged. `CFRange` and `CFRangeMake` come from corelibs CoreFoundation, which the
  module re-exports.
- One internal engine protocol (`CTEngine`) does what needs a platform: load a font by
  name or by UI role, read its metrics and tables, map characters to glyphs, shape a run
  of text into glyph runs with font fallback, find line-break opportunities, outline a
  glyph, and draw glyphs into a `CGContext`. Everything else (typesetting, line
  breaking, alignment, truncation, frames, hit testing) is shared Swift.
- Linux engine: Pango for itemisation, shaping and fallback (`pango_itemize` +
  `pango_shape_full`, `pango_get_log_attrs` for breaks), FreeType through `pango_fc_font`
  for tables, outlines and glyph metrics, `pango_cairo_show_glyph_string` for drawing on
  the Cairo context behind `CGContext`.
- Windows engine: DirectWrite through the `CDirectWrite` C module (`IDWriteFontFace` for
  glyphs, metrics, advances and outlines; `IDWriteTextAnalyzer` for script analysis,
  shaping with fallback and line breakpoints; `ID2D1RenderTarget::DrawGlyphRun` for
  drawing on the Direct2D target behind `CGContext`).
- AppKit's `HostTextBackend` (CoreText over the seam) becomes the text backend on every
  platform; the Pango and DirectWrite string backends go away. `NSFont` is a `CTFont`
  underneath, and attributed strings draw through `CTFramesetter`.

Conventions: text is laid out left to right with Pango or DirectWrite handling
bidirectional runs inside a line as the engine reports them; glyph positions are in
points with the line origin on the baseline; string indices are UTF-16 as on Apple.

## Consequences

- `NSAttributedString` drawing honours per-range fonts, colours, kerning, underline and
  paragraph style (alignment, line break mode, line spacing).
- `NSTextStorage` / `NSLayoutManager` / `NSTextContainer` can be implemented on
  `CTTypesetter` next; `NSTextView` then switches to the real text system.
- Not covered yet: vertical text, font features and variations beyond weight/slant,
  emoji colour glyphs on Linux (Pango draws them where the font has them), glyph
  rendering modes (subpixel positioning follows the engine's default).

## Amendment (2026-11-20): per-run font fallback on Windows

The Windows engine shapes with `IDWriteTextLayout` and a collecting renderer (not the
`IDWriteTextAnalyzer` path the decision above names), and until now it left font fallback
implicit in the layout. A Sibyl label on the PC showed U+25B8 (Segoe UI has no glyph for
it) as a dot. `cdw_shape` now does the fallback itself, before it draws:

- `IDWriteFactory2::GetSystemFontFallback` provides the system fallback, which is also set
  on the layout (`IDWriteTextLayout2::SetFontFallback`), so no custom or empty fallback can
  apply.
- `IDWriteFontFallback::MapCharacters` splits the text from the primary family (base
  weight and style). Each stretch it maps to another family is pinned to that family on the
  layout (`SetFontCollection` + `SetFontFamilyName`, and `SetFontSize` when it returns a
  scale). A second pass checks the primary face's cmap: an inked character still on the
  primary face whose glyph index is 0 is mapped again from the fallback chain alone (no base
  family). Controls, spaces, joiners, variation selectors and format characters are not
  counted as misses.
- The renderer returns one run per resolved face, each with its own `CDWFont`. The
  typesetter measures with those runs' advances and `CTRun` draws those glyphs with that
  face (`DrawGlyphRun`), so the width a line reports (and `sizeThatFits`) is the width it
  draws. Characters the primary font has keep the primary face as before.
- CJK and emoji (surrogate pairs such as U+1F600) go through the same path. Emoji draw in
  monochrome: `ID2D1RenderTarget::DrawGlyphRun` has no colour glyph layers.

`CoreTextFallbackTests` is the contract: a real glyph and a non-zero advance for U+25B8,
U+1F600 and CJK, and a line width equal to the sum of its runs' advances. It runs against
Apple's CoreText on macOS and against the port's engines on Windows and Linux.
