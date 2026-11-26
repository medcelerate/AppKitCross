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
  every lens's shade). `Glass --autoscroll 5` (or `APPKITWIN_GLASS_AUTOSCROLL=5`) scrolls
  for five seconds without a click, painting and timing every frame, prints a line a
  second (frames, mean and p95 paint time, the gap from one frame's start to the next)
  and a summary, then exits. `--interval <ms>` sets the time between frames (16.7 by
  default; 0 drives frames back to back, so the gap shows what the paint and the
  platform's pump allow rather than the timer's cadence). Measure with a
  release build (`swift run -c release Glass --autoscroll 5`): the per-pixel stages are
  many times slower unoptimised. The glass runs on the platform's GPU program (ADR-0052
  stage 2); `APPKITWIN_LIQUID_GLASS_GPU=0` draws it with the software pass to compare.
- `Glass --reference <light|dark|over-dark|interactive> <rest|hover|press> <out.png>`
  draws one of the reference scenes (`ReferenceScene.swift` and `ReferenceSceneGlass.swift`,
  shared with `tools/glass/reference`, which captures the same scenes with real macOS 26
  glass; `tools/glass/capture-references.sh` runs both) and exits.

Run it:

```bash
APPKITWIN_LIQUID_GLASS=1 swift run Glass
```

Without `APPKITWIN_LIQUID_GLASS=1` every surface draws the pre-26 look (a flat band,
bordered buttons, the translucent tint for the glass views), so the two runs compare the
switch.
