# ADR-0052: Opt-in Liquid Glass

Date: 2026-11-20. Status: accepted.

## Context

macOS 26 draws toolbars, sidebars and many controls on Liquid Glass: a lens over the
content beneath, blurred, lightly veiled, with a highlight along its upper edge and a soft
shadow under it, flatter and more opaque when the window is inactive. Apps built against
the 26 SDK reach for it directly (`NSGlassEffectView`, `NSGlassEffectContainerView`,
SwiftUI's `glassEffect`, `Glass`, `GlassEffectContainer`, `glassEffectID` and the `.glass`
and `.glassProminent` button styles), and Sibyl (ADR-0050) is the first port whose Mac
build does. The port had the API only as `unimplemented()` stubs, and its own chrome keeps
the pre-26 look: a flat band behind the toolbar, a plain sidebar column, bordered buttons.

The port's look is a product decision made per app (the caption band and the control
styling are opt-in flags of their own, worked in parallel), so glass had to be opt-in as
well: the default pixels stay exactly as they are, and an app that wants the 26 look turns
it on. It also had to render without an OS compositor: Windows' DWM backdrops (PR 77)
blur the desktop behind the whole window rectangle and nothing else, X11 has no blur at
all, and the Wayland blur protocols (KDE's, the GNOME extensions') are out of scope.

## Decision

### The switch

`APPKITWIN_LIQUID_GLASS=1` in the environment, else the `AppKitCrossLiquidGlass` Info.plist
key (a Boolean; the environment wins). Read once (`_LiquidGlass.isEnabled`); tests pin it
with `_LiquidGlass._override`. Off, every surface this ADR touches draws through the code
path it had before, so the pixels are unchanged; the hand-written glass views and the
SwiftUI modifiers keep working with a sensible fallback (below), never a trap.

### One in-window glass pass, in Core

Glass is drawn by Core, not by a backend. When a glass surface draws, it asks the window
for what lies beneath it: the window paints itself again (background, content view, the
toolbar band, the title bar accessories, in `platformWindowDraw`'s order) into an
offscreen surface covering the glass rectangle plus the blur margin, and the paint stops
the moment it reaches the glass view (`NSView._glassStop`; `CALayer._composeStopLayer`
carries the same stop through a layer-backed subtree, which the layer compositor walks
instead of `_displayHierarchy`, and stops the layer being drawn from composing itself
again from inside its own `draw`). The sample is taken at a quarter of the backing scale,
since the blur hides the resolution and a toolbar band or sidebar column then costs a few
hundred by a few dozen pixels. The backend's material pass turns the sample into the
glass (the pipeline below), and the surface draws the result clipped to its outline, with
a three-ring soft shadow below a lens.

The sample is cached per surface (`_GlassSample`, kept by `_GlassRegistry`) and taken
again only when a view that is not the surface or one of its subviews dirties a rectangle
intersecting the surface, when the surface moves or changes scale, or when the appearance
changes; every invalidation passes through `NSWindow._viewNeedsDisplay`, which is where the
registry hears of it, and the surface marks itself for display when its sample goes stale.
The shaded image is cached with it, keyed by the lens parameters and the outline, so a
hover or a key-window change re-shades without re-sampling and a plain redraw does
neither. Nothing is invalidated from inside a draw (the Daily To Do lesson): a sample is
only ever taken during a paint, and a stale one is noted, not repainted, by the
invalidation that caused it. The per-rect paint path (PR 92) is untouched; a surface
clipped to part of a dirty rect draws that part from its cache. Content scrolling under a
surface dirties it every frame, so the glass follows at frame rate; a surface over static
content never resamples, and an idle window issues no invalidation.

### The material pipeline

Apple describes Liquid Glass (WWDC25 "Meet Liquid Glass", the HIG's Materials page) as a
lens: the content behind it, blurred and made a little more vivid, bent at the edge where
the glass is thick, lit by a highlight that follows the light and the shape's curvature,
with a thin rim and a soft shadow, adapting between a light and a dark variant to what is
behind it, and brightening and swelling under the pointer. The port models each of those
as a stage of `PlatformMaterialBackend` (`Platform/Material.swift`), so a backend with a
GPU compositor implements the same stages as shader passes and Core does not change:

1. **Backdrop** (`blur(_:radius:saturation:)`, at the sample scale): a Gaussian
   approximation (three separable box passes) of radius 16 pt for a lens, 10 pt for clear
   glass, 24 pt for a toolbar band or sidebar material; then saturation, every colour
   pulled from its luminance by 1.3 (1.35 for a material, 1.15 for clear).
2. **Luminance** (`averageLuminance`): the alpha-weighted mean of the blurred backdrop.
   Regular glass in light appearance is light over a backdrop above 0.35 and dark below
   it (the dark veil, a fainter rim, a softer sheen); dark appearance is always dark;
   `Glass.clear` keeps the lighter veil of its variant. A prominent button stays light
   under its accent tint.
3. **Lens** (`shade(_:in:shape:parameters:)`, at the backing scale over the shape alone):
   the outline is a signed distance field, analytic for a rounded rectangle or capsule and
   a chamfer distance transform of a coverage mask for any other outline (SwiftUI's
   `glassEffect(in:)` with its own shape), with the outward normal from its gradient. Per
   output pixel, with `d` the distance (negative inside), `n` the normal and `L` the light
   direction (above and a little to the left, in the surface's own orientation whether
   the view is flipped or not):

   ```
   t     = clamp(1 + d / edgeWidth, 0, 1)            // 1 at the rim, 0 edgeWidth inside
   p'    = p + n * refraction * t²                   // the lens looks outward through the bevel
   c     = backdrop(p')                               // bilinear, through the blur margin
   c     = mix(c, veil, veilAlpha); c = mix(c, tint, tintAlpha)
   rim   = clamp(1 + d / rimWidth, 0, 1) * rimAlpha
   c    += (1 - c) * rim * max(n·L, 0)                // light where the edge faces the light
   c    *= 1 - rim * max(-n·L, 0) * 0.45              // dark where it faces away
   s     = clamp(1 + d / (2 * edgeWidth), 0, 1)       // the sheen reaches twice the bevel's depth
   c    += (1 - c) * (n·L)² * s² * specular           // a soft band down the lit bevel, not a line
   c    += (1 - c) * brighten                         // hover 0.1, press 0.2
   out   = c * coverage(d)                            // antialiased at the outline
   ```

   A lens has a 6 pt bevel bending the backdrop by 3 pt at the rim, a 1 pt rim at 0.55
   (0.3 in the dark variant, halved when the window is inactive) and a sheen of 0.5 (0.35
   in the dark variant); a material (band, sidebar, within-window effect view) has none of
   them, only the veil, so it never runs the lens stage: the graphics backend draws its
   blurred backdrop up to size and the veil, tint and lift are fills over it.
4. **Scroll-edge extension**: a toolbar band in this port sits above the content view
   (ADR-0018 grows the frame by the band), so nothing but the window background lies
   beneath it and a faithful sample would be flat grey, which is what the first PC run
   saw. macOS 26's scroll edge effect carries the document into the bar; the band's
   material does the same by mirroring the content just below the band's bottom edge into
   the sample (`_GlassSpec.extendsFrom`), when at least 97 % of the pixels under the band
   are the window background (a `fullSizeContentView` window whose content runs under the
   band samples the content itself). The mirror joins the real content in the sample's
   bottom margin without a seam, and the registry re-samples the band when that strip is
   dirtied, so scrolling under the band moves the material.
5. **Interactivity**: `Glass.interactive` (`NSGlassEffectView._isInteractive`), a glass
   button and a toolbar item brighten under the pointer (a tracking area) and more while
   pressed, and a pressed surface grows from its one-point inset back to its bounds (the
   capsule's rect grows by 0.75 pt a side). The container (below) carries the states of its
   members into the merged shape.

**One frame per paint.** The second PC run scrolled at seven frames a second: every glass
surface painted the window beneath itself again, at full resolution, every frame. The
registry now renders the content beneath the glass once per paint into a shared frame
(`_GlassFrame`: the window's content, band and accessory area at the sample scale, a
quarter of the backing scale for lenses and an eighth for materials, stopping at the first
glass surface in the paint order), and each surface crops its rectangle plus the blur
margin from it; the band's mirrored strip is a crop of the same frame rather than a second
render. The frame lives until a view outside the glass dirties the window, so a paint that
touches no content beneath glass renders nothing; and a dirty rectangle marks only the
surfaces it reaches (the band when content scrolls under it, a lens when something under
the lens changes), the others keep their blurred sample and shaded image. On the host at
2x (`Examples/Glass`, 900 by 600 points, the band and nine lenses) a whole-window paint in
a release build takes 4 ms without glass and about 12 ms with it; the same paint in a
debug build takes 77 ms, because the per-pixel loops run unoptimised (they were 250 ms
before the shared frame and the material short path). Performance is measured on release
builds; the per-pixel stages are the ones a GPU backend replaces, which is the path to 60
Hz on every platform. On Windows the scroll itself dirtied the whole content area in that
run; the clip view's scroll by copy (PR 92, round 10c, `NSClipView.copiesOnScroll`) moves
the pixels it already has and dirties the exposed strip alone. A copy moves the content
beneath any glass over the scrolled area without a view dirtying it, so the window's
`_scrollBacking` tells the registry the area moved: the samples over it (and the band
mirroring from it) go stale and their surfaces redraw, nothing else does, and the scrolled
frame matches a full repaint (a host-backend test checks it).

**Measured on the PC** (release, 1x, `Examples/Glass --autoscroll 10`): a scroll frame
paints in 18 ms with glass and 4 ms without, while the frame rate sat at 29 and 51 fps.
The rate was the demo's own doing, not the pump's: a repeating 16.7 ms `Timer` whose
callback paints for longer than the interval misses its next fire and runs at half rate
(the host shows the same, 33 ms gaps for 14 ms paints), and the Windows timer's 15.6 ms
granularity rounds the glass-off cadence up too. `--interval 0` drives frames back to
back and reports the gap between frame starts, which is the number to read for what the
paint and the pump allow (host 2x release: 79 fps with glass, 237 without).

**The PC baseline** (release, 1x, `Examples/Glass --autoscroll 10`, the scroll by copy
engaged, 106 copies in 5 s), the numbers this ADR's software pass ships with:

| | paint mean | fps at 16.7 ms | fps free-running |
|---|---|---|---|
| glass on | 21.2 ms | 27 | 37 |
| glass off | 6.5 ms | 45 | 60 (11 ms mean, 61 ms max) |

Glass costs about 15 ms a scroll frame there: the band's crop and blur, and nine lenses
each re-sampled and re-shaded because the content under every one of them moved (the
demo puts all of them over the scroll view). Every frame still paints seven rectangles
whose union is the whole content: the strip the scroll exposed, each view over the clip
view twice (where it was and where the copy carried its pixels, which is what a copy
under an overlay costs), the band and the rows the base marks for its own lists. The
Win32 backing keeps one dirty rectangle, so the union is what the platform repaints even
though the port draws the parts. Shrinking that union is the follow-up on the live-list
repaint branch after this merges: overlays the copy could skip, and lenses whose backdrop
did not move not redrawing. The band already re-samples its own rectangle alone (a crop of
the sample-scale frame), not the content.

**The GPU stage on Windows: scope.** At 21 ms a scroll frame with glass cannot hold 60 Hz
in software on the PC, so the seam is the next step there, not an option. What it takes:

1. The frame beneath the glass rendered into a Direct2D bitmap render target (an
   `ID2D1BitmapRenderTarget` or a device-context bitmap with `D2D1_BITMAP_OPTIONS_TARGET`)
   rather than a CPU-readable offscreen, at the sample scale, by the same
   `_drawBeneathGlass` paint; `PlatformImageBackend.makeOffscreen` on Windows gains a
   GPU-resident variant, or `PlatformMaterialBackend` gains an entry that takes the
   backend's own surface handle. The material protocol's images become an opaque
   `PlatformMaterialImage` (a `CGImage` on the host and Linux, a D2D bitmap on Windows)
   so no stage reads pixels back; the software backend wraps a `CGImage` as today.
2. The blur and saturation stages as Direct2D built-in effects (`CLSID_D2D1GaussianBlur`
   with `D2D1_GAUSSIANBLUR_OPTIMIZATION_SPEED`, `CLSID_D2D1Saturation`), which run on the
   GPU without any shader of the port's own, so the blur is a few microseconds of GPU
   time per surface. The luminance probe stays a CPU reduction over the sample-scale
   bitmap (a few hundred pixels per surface) or becomes a 1x1 downscale effect.
3. The lens stage as a custom Direct2D effect (`ID2D1EffectImpl` with a pixel shader
   registered through `ID2D1Factory1::RegisterEffectFromString`) running the per-pixel
   program above: the blurred backdrop as input 0, the coverage mask as input 1 for
   path outlines (the rounded rectangle's signed distance is analytic in the shader), the
   `PlatformGlassParameters` as the constant buffer. The HLSL is compiled once at build
   time (`fxc` / `dxc` in the Windows job, the blob embedded as bytes) because Direct2D
   wants a compiled shader; a D3D12 compute pass over the same inputs is the alternative
   when the D3D12 Metal backend lands and the window composites through it, with one
   dispatch per surface and a copy into the swap chain.
4. The output stays a D2D bitmap drawn into the window's render target by the existing
   draw-image path; `drawImage` takes the opaque image. The shaded bitmap is cached per
   surface as today, re-shaded when the backdrop or parameters change.
5. Tests: the pixel tests read the shaded output back (one `CopyFromRenderTarget` per
   test), so the same twenty tests run against the GPU backend on the Windows job; the
   budget test is the demo's `--autoscroll` on the PC, a scroll frame with glass under 8 ms
   at 1x. The Linux (Vulkan) and host (Metal) ports of the stages are the same shape and
   follow when the Windows one is measured.

Every backend ships the software pipeline. The offscreen surfaces come from the existing
`PlatformImageBackend.makeOffscreen`, whose pixels are premultiplied BGRA on all three
backends (Direct2D bitmaps, cairo image surfaces, the host's bitmap context), so one
implementation serves them all. A GPU implementation (a Direct2D effect graph or a D3D12
compute pass on Windows, Vulkan on Linux, Metal on the host) overrides `material` on its
`PlatformBackend` with the three stages as shaders over the same inputs; the stages are
split so a backend can take the blur first and leave the lens to software. None is written
yet: the machine this ADR was written on cannot build the Windows or Linux GPU paths, and
the software pass meets the frame budget at the sizes glass is used at.

Windows' DWM backdrop is unchanged and still what a behind-window `NSVisualEffectView`
asks for (Mica/Acrylic over the whole rectangle, per PR 77's rule that a rounded or
uncovered non-opaque window gets tint only). Glass within the window is this pass on every
platform; a sidebar material lit by the desktop through Mica is a follow-up that needs the
window non-opaque (a composition window that repaints whole), which is the caption task's
territory.

### AppKit API

`NSGlassEffectView` (`contentView`, `cornerRadius`, `tintColor`, `style`) and
`NSGlassEffectContainerView` (`contentView`, `spacing`) are hand-written now
(`tools/apigen/config.json`). The port's types carry no `@available(macOS 26.0, *)`: the
macOS host build runs on macOS 15, where a 26-gated type could never be exercised by the
tests. The container merges: glass views whose frames, grown by half the `spacing`, touch
(or that share a `glassEffectUnion` identifier) draw as one capsule around them, drawn by
the container with one sample, and the members draw no surface of their own; the groups
are recomputed in the container's `layout` when a member is added, moved or resized. The
morph macOS animates between the separate and merged shapes is not drawn. With the switch
off a glass view draws the translucent window-colour tint a within-window
`NSVisualEffectView` draws. `NSVisualEffectView` within the window takes the glass material
with the switch on (HUD and dark materials keep their dark veil, a selection its colour);
behind-window blending is as before.

### SwiftUI API

`Glass` (`regular`, `clear`, `identity`, `tint(_:)`, `interactive(_:)`),
`DefaultGlassEffectShape` (the capsule), `glassEffect(_:in:isEnabled:)`,
`GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`,
`Namespace` (new; `@Namespace` had no port), `GlassButtonStyle`/`.glass` and
`GlassProminentButtonStyle`/`.glassProminent`. `glassEffect` puts an `NSGlassEffectView`
clipped to the shape behind the view with the switch on (the capsule analytic, any other
shape through the coverage mask; `interactive` sets the view's hover and press states),
and is the view itself off (no wrapper view: the hierarchy is the one without the
modifier). `GlassEffectContainer` is an `NSGlassEffectContainerView` around its content,
spacing 40 by default as on macOS, so neighbouring effects merge. `glassEffectUnion`
carries its identifier to the surfaces through the environment and the container merges
those whatever their distance; `glassEffectID` accepts its identifier and draws no
transition. The glass button styles
are new `_ButtonStyleKind` cases; `Button` is backed by `_GlassButton`, an `NSButton` that
with a glass style and the switch on draws its label on the glass capsule
(`_MaterialBackground.control`) and leaves the bezel to the glass, the cell still sizing it
as a bordered button; a prominent one is tinted with the accent and titled in white. Off,
both styles are the bordered button, pixel for pixel (the pixel test compares the PNGs).

### The chrome hook

`_MaterialBackground.draw(_:in:of:)` is the one call a surface makes before its own fill:
with the switch on it draws the material for the kind (`toolbarBand`, `toolbarItem`,
`sidebar`, `control`) and answers true, off it draws nothing and answers false, so the
caller keeps today's drawing untouched. The call sites are the toolbar band and the
toolbar item capsule in `NSToolbarView.swift` (two lines, placed so the sibling title-bar
work can move them with the band) and the navigation split view's sidebar pane
(`_SplitPaneView.isSidebar`, set for the pane keyed `sidebar`). With the switch on every
enabled toolbar item sits on a glass capsule, as on macOS 26, and the band and the sidebar
column are the glass material over the window.

## Consequences

- Twenty-one pixel tests (`LiquidGlassPixelTests`): the glass is a blurred function of the
  backdrop (red on the left, blue on the right, a softened edge; a different backdrop gives
  different glass; black and white stripes lose over 90 % of their variance through it);
  the rim highlight along the top and none along the bottom; refraction (the lens stage
  over a synthetic backdrop shows the colour beyond the edge inside the rim only with
  refraction on, the centre untouched); the specular sheen and rim following the light
  (top brighter than the body, bottom darker, left brighter than right, the sheen a band
  that is still pronounced two pixels in and fades by six); a coverage-mask
  outline (a diamond) shaded with its lit and unlit edges; the light/dark variant flipping
  with the backdrop's luminance; the dark veil in dark appearance; the inactive window's
  flatter glass; hover and press brightening and the pressed surface growing to its
  bounds; the container merging neighbours within its spacing and not beyond, and on a
  union identifier; the SwiftUI container and `glassEffectUnion`; the toolbar band carrying
  the colour of the document below it (host backend) and grey with the switch off; the
  sample cache (kept across the surface's own redraw and an invalidation outside it, stale
  after one beneath it, the shaded image kept with it); the shared frame (three lenses
  sample one render of the window, content dirtied under one lens re-samples that lens
  alone, an unchanged window samples nothing); a scroll by copy under a lens staling its
  sample and the scrolled frame matching a repaint (host backend); the switch-off flat tint with no
  rim and no groups; the SwiftUI fallbacks (no extra view from `glassEffect`, a glass
  button identical in PNG to the bordered one); the sidebar pane flag; the software blur,
  saturation and luminance probe. They run on the host and in the Linux container;
  Windows draws the same Core pass over Direct2D offscreens and is checked on the PC.
- `Examples/Glass` puts colourful bands and discs under a toolbar, a merged pair of glass
  buttons, a clear and a tinted lens and the SwiftUI glass API, scrolls them at frame rate
  from a toolbar item, and writes a screenshot with `--screenshot`.
- Cost: a paint that dirtied content beneath glass renders the window beneath the glass
  once more, into a frame of a sixteenth of the pixels (a sixty-fourth for materials),
  then per stale surface a crop, three box-blur passes over it and, for a lens, the lens
  pass over the shape at the backing scale. A view animating beneath a glass surface
  resamples it every frame, which is what glass means; a toolbar over static content never
  resamples; a hover re-shades from the cached backdrop. `APPKITWIN_TRACE_FRAMES=1` prints
  each stage's time next to the paint's.
- Not done: the morph animation between a container's separate and merged shapes and
  `glassEffectID` transitions; the GPU stages on Windows, Linux and the host (the seam is
  there, software serves all three); the sidebar lit by the desktop through Mica (needs
  the non-opaque window); the scroll-edge extension for edges other than the strip below
  a band; reference captures from a macOS 26 machine to tune the constants against.
