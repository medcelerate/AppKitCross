# Glass

Liquid Glass (ADR-0052) over content that scrolls: the material, measurable.

What it demonstrates:

- A toolbar band over a document that scrolls beneath it: with the switch on the band is
  the glass material carrying the document's colours (the scroll-edge effect mirrors the
  content just below the band into it), each item sits on a glass capsule with the rim and
  sheen of a lens, and the pointer brightens an item.
- `NSGlassEffectContainerView` with two `NSGlassEffectView` buttons closer than its
  `spacing`: they merge into one capsule.
- A `.clear` lens (interactive: it brightens under the pointer and while pressed) and a
  `.regular` one with a `tintColor` (the Tint item cycles it).
- SwiftUI: `GlassEffectContainer`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`,
  `glassEffect(.regular.interactive())` (brightens under the pointer, grows while pressed)
  and `glassEffect(.regular.tint(.orange))`.
- The Scroll item scrolls the content at frame rate, so every glass surface re-samples the
  backdrop each frame: the lenses bend the bands' edges into their rims and flip between the
  light and dark variant over the dark and light bands. `APPKITWIN_TRACE_FRAMES=1` prints
  the draw times and each glass stage's (the shared frame, every sample's crop and blur,
  every lens's shade). Measure with a release build (`swift run -c release Glass`): the
  per-pixel stages are many times slower unoptimised.

Run it:

```bash
APPKITWIN_LIQUID_GLASS=1 swift run Glass
```

Without `APPKITWIN_LIQUID_GLASS=1` every surface draws the pre-26 look (a flat band,
bordered buttons, the translucent tint for the glass views), so the two runs compare the
switch.
