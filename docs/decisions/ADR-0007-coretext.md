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
