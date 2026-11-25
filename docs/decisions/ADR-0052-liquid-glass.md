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
split so a backend can take the blur first and leave the lens to software. The GPU
programs came with stage 2 (below); the software pass stays every backend's fallback and
the reference they are tested against.

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
  `glassEffectID` transitions; the sidebar lit by the desktop through Mica (needs the
  non-opaque window); the scroll-edge extension for edges other than the strip below a
  band. The GPU stage and the reference tooling are stage 2 (below); the macOS 26
  captures themselves are still to be taken.

## Stage 2: the GPU programs (2026-11-24)

### Decision

One glass program per graphics API, each running the stages of the software pass with the
software pass's arithmetic over the same inputs, so the two agree to a few 1/255 steps and
the software pass stays both the fallback and the reference the tests compare with
(`Platform/GlassProgram.swift`, `PlatformGlassProgram`, `PlatformGlassRequest`):

1. **Backdrop**: three box passes per axis of radius `max(1, (r + 1) / 2)` over the raw
   sample, as integer sums of the border-clamped bytes divided with truncation. That is the
   software running sum exactly, bit for bit, rather than a true Gaussian: a different kernel
   would have made "agrees with the reference" a matter of taste. Then the saturation pull
   from luminance, rounded as the software rounds.
2. **Luminance probe**: the alpha-weighted mean luminance of the blurred sample, a one-group
   reduction, which picks the variant of an adaptive surface inside the program. The request
   carries both variants (the light veil, rim and sheen and the dark ones), so nothing is
   read back to decide.
3. **Lens**: per output pixel the rounded rectangle's signed distance and normal, the
   refraction through the bevel, the bilinear look-up (border-clamped, the software
   convention), veil, tint, rim, sheen, lift, coverage: the per-pixel program above, line for
   line. A flat material is the same program with no bevel, rim or sheen and a radius of 0,
   so the band and the sidebar go through it too.

The constants are one block of twelve float4 rows (`GlassConstants` in the sources,
`PlatformGlassRequest.constants` packs them), identical in all three languages. The sources
are `Sources/AppKit/Platform/Shaders`: `glass.metal`, `glass_{box,saturate,luminance,lens}.comp`
with `glass_common.glsl`, and `glass_lens.hlsl`. `tools/glass/embed-shaders.py` embeds them
into `GlassShaders.swift` (MSL and HLSL as text, compiled at run time; the GLSL as SPIR-V,
compiled by `tools/glass/build-spirv.sh` in the Linux container with glslang, next to the
FNV-1a hash of its source, which a test recomputes so an edit without a re-embed fails the
suite). The directory is excluded from the AppKit target.

Per platform:

| | program | stages on the GPU | result |
|---|---|---|---|
| macOS host | `glass.metal` on Apple's Metal (`HostGlassMetalProgram` over the Objective-C `CGlassMetal` shim, fast math off) | all three | read back into a `CGImage`, cached with the sample as the software pass's shaded image |
| Linux | the GLSL compute shaders as SPIR-V on the Metal module's Vulkan shim (`LinuxGlassVulkanProgram`, `CMetalVulkan` directly, ADR-0012's binding model: storage buffers in set 1) | all three | read back into the cairo image the window draws |
| Windows | `glass_lens.hlsl` as the pixel shader of a Direct2D custom effect (`Win32GlassProgram`, `Sources/CD2D/cd2d_glass.cpp`) on the window's own device context | the lens | drawn in place: `DrawImage` of the effect into the window, nothing read back |

Departures from the scope written above, deliberately:

- **Direct2D, not D3D12, on Windows.** The window composites through Direct2D on a D3D11
  device (the swap chain, PR 17 and Milestone 3), and the D3D12 device belongs to the Metal
  module. A D3D12 compute pass would upload the backdrop to one device and read the shaded
  surface back for the other on every draw; a Direct2D effect runs on the device that
  already holds the window's canvas, which is the point of the stage. The HLSL is compiled
  at run time (`D3DCompile` from `d3dcompiler_47.dll`, loaded dynamically, IEEE strictness,
  `ps_4_0`, so a feature level 9 device falls back to software) rather than at build time:
  no shader compiler is needed in the Windows build and the embedded text is the source of
  truth on every platform.
- **The backdrop stage stays on the CPU on Windows** for now. The frame beneath the glass is
  still a CPU bitmap there (a WIC render target, `_GlassFrame`), so the raw sample is in
  system memory whichever stage runs first, the blur at the sample scale costs a few
  hundredths of a millisecond (the host trace: 0.03 to 0.06 ms a surface), and the
  per-pixel lens at the backing scale is what dominated. The effect takes the blurred
  sample (uploaded at the sample scale, a few kilobytes) and the CPU's exact luminance.
  Moving the frame itself to a GPU bitmap (a device-context target on the window's device)
  is the next step if the PC's trace shows the frame render dominating; the box and
  luminance stages then go into the effect graph, and the shaders for them exist already.
- **Any outline other than a rounded rectangle keeps the software lens** (SwiftUI's
  `glassEffect(in:)` with its own shape): the chamfer distance transform of the coverage
  mask is a CPU pass, and shipping a distance field to three APIs for a rare case is not
  worth it yet. Those surfaces draw exactly as before.
- **On the host and Linux the result is read back**, one synchronous round trip per stale
  surface, because those windows composite on the CPU (the host's bitmap context, cairo).
  It is cheaper than the software lens but not free (below).

Selection (`_GlassGPU.program`): the platform's program when it starts, unless
`APPKITWIN_LIQUID_GLASS_GPU` is `0`, `no`, `false` or `off`, which forces the software pass.
Both stay behind `APPKITWIN_LIQUID_GLASS`: with glass off nothing here runs. A program that
cannot start (no Metal device, no Vulkan 1.3 loader or `APPKITWIN_METAL_REFERENCE=1`, no
`d3dcompiler_47.dll`) leaves the software pass in place, and one that fails to draw is
dropped for the rest of the process with one line on stderr, the surface drawn by software
that same paint. `APPKITWIN_TRACE_FRAMES=1` names the program once and times every GPU draw
(`glass Direct2D 288x88 px (lens): 0.05 ms`).

The Vulkan shim binds every buffer slot as a uniform and a storage buffer at once; the
uniform view is now clamped to the device's `maxUniformBufferRange`, so the program's pixel
buffers (larger than 64 KB) stay valid descriptors.

### Tolerance

A program agrees with the software pass when no channel of the shaded surface differs by
more than 3/255 and the mean difference is at most 0.25/255. The arithmetic is the same;
what differs is float rounding (op order, `round` at exact halves) and, on Windows, the
sampler's bilinear filter instead of the software's. Measured on the host (Metal, Apple M4
Pro): the whole `Examples/Glass` window through the program against the same window through
software differs by at most 3/255 in any channel, 0.008/255 on average. The Vulkan program
on lavapipe passes the same tests in the container. Windows is checked on the PC (the
effect cannot run where this was written); its tests run the effect into a bitmap context
and compare as the others do.

### Performance

`Examples/Glass --autoscroll 5 --interval 0`, release, macOS host at 2x (900 by 600 points,
the band and nine lenses re-sampled every frame):

| | paint mean | p95 | fps free-running |
|---|---|---|---|
| glass on, GPU (Metal) | 7.7 ms | 9.4 ms | 106 |
| glass on, software (`APPKITWIN_LIQUID_GLASS_GPU=0`) | 9.4 ms | 10.1 ms | 89 |
| glass off | 1.3 ms | 1.6 ms | 338 |

The trace splits the GPU frame into 3.3 ms of lens programs (eleven surfaces, about 0.3 ms
each, almost all of it the synchronous command-buffer round trip the read-back needs), 1.9 ms
rendering the frame beneath the glass twice (the lens and material scales) and 1 ms of crops.
The host was never the budget; it shows the read-back's price. Windows draws in place, so
each surface costs its draw call and the upload of a sample-scale bitmap, and the CPU work
left per frame is the frame render, the crops and the blur. The budget: under 8 ms a scroll
frame with glass in a release build at 1x on the PC (software: 18 to 21 ms).

**PC round 1** (PR 99 at d880a2c; RTX desktop, 2560x1440 at 100 %, release,
`--autoscroll 10 --interval 0`):

| | paint mean | p95 | fps free-running |
|---|---|---|---|
| glass on, Direct2D program | 16.3 ms | 18.4 ms | 44 |
| glass on, software | 19.1 ms | | 39 |
| glass off | 10.9 ms | 16.1 ms | 60 |

The GPU draws are not the cost. The trace puts the eleven Direct2D lens and material draws
at 0.63 ms a frame together (0.04 to 0.08 ms each). The CPU work is two renders of the window
beneath the glass, 6.2 ms between them: 3.25 ms at a quarter scale (225x160 px) and 3.4 ms at
an eighth (113x80 px). Their cost does not scale with their pixels, so it is the view tree's
draw calls through the WIC software target, not rasterising.

What the 8 ms budget does not account for is the glass-off baseline: 10.9 ms against 1.3 ms on
the host. Two things in it:

- The demo's "paint" wraps `displayIfNeeded`, which on Windows includes `EndDraw` and
  `Present(1, 0)` on a two-buffer flip-sequential chain. That blocks until a buffer is free,
  so part of it is the vertical blank. Glass off runs at 59.8 fps, the refresh rate. The
  trace's own "draw" (`platformWindowDraw`, no present) is the number to read for the paint.
- The rest is a port-wide Direct2D draw cost: the window paints seven rectangles a scroll
  frame, and a tree walk costs about 3 ms whatever the pixel size. That is a follow-up of
  its own, not glass: profile per-rectangle tree walks, per-draw path geometries and
  DirectWrite layouts on the PC.

Round 2 renders the window beneath the glass once per paint. The material's eighth-scale
frame is the lens frame halved, each pixel the mean of a 2x2 block (`_GlassFrame.halved`).
That removes one tree walk, about 3.4 ms on the PC. Host 2x, the same run: 6.5 ms with the
GPU program (was 7.7), 8.8 ms in software. With glass on, the PC then costs the baseline plus
one CPU frame render (about 3.3 ms) plus the crops, blur and draws (about 1 ms).

Meeting 8 ms with glass at 1x needs two further pieces:

- the frame beneath the glass rendered on the GPU, as a device-context bitmap target on the
  window's device rather than a WIC bitmap, so the tree walk costs Direct2D's GPU path;
- the base paint follow-up.

Both are recorded as the next steps; the stage-2 shaders for the box and luminance stages are
ready for the GPU frame.

### Round 3: the frame beneath the glass on the GPU

Evan's call after PC round 1: keep going towards 8 ms in this PR by moving the frame beneath
the glass onto the GPU on Windows. That frame is the one CPU cost the glass adds that grows
with the window. The port-wide base paint is a separate session's PR; this one stays out of
the general paint path.

**The frame.** The program can make the frame (`PlatformGlassProgram.makeFrame`):

- On Windows, `cd2d_glass_frame_create` makes a bitmap target on a second device context of
  the window's own `ID2D1Device`, at 96 DPI so a DIP is a pixel.
- `Win32GlassFrame` draws into it through a `CGContext` whose base transform takes points to
  those pixels, made with the window context's factory (`CGContext._d2dFactory`) so its
  geometry belongs to the same device.
- Core paints the window beneath the glass into it exactly as into the CPU offscreen
  (`_GlassRegistry.paintBeneath`, shared by both paths), once per paint and only at the
  lens scale.
- The material's frame is that bitmap halved on the device (`_GlassGPUFrame` with the halved
  geometry), not a second paint.

**The graph.** Each surface draws from a crop of the frame
(`PlatformGlassFrameSource`, `cd2d_glass_draw_from_frame`) as one Direct2D effect graph on the
window's device context:

1. For a material, the built-in Scale effect at exactly 0.5 with linear filtering. Bilinear
   at a 2x2 block's shared corner is the block's mean, which is the CPU halving's.
2. The crop (built-in Crop). For a band over a document that does not run under it, a flip
   about the edge (built-in 2D affine transform, nearest neighbour) composited above it, which
   is the mirrored strip.
3. Six box passes and the saturation. `glass_backdrop.hlsl`'s `box` is a custom effect that
   reads whole texels and writes whole bytes, so the truncating sums are the software
   running sum's.
4. The luminance probe: `luminance`, a custom effect whose one-pixel output is the
   alpha-weighted mean.
5. The lens (`glass_lens.hlsl`), which reads the probe as its second input (`k[9].z < 0`) and
   the backdrop at the crop's origin (`k[11].xy`).

Nothing is read back, nothing uploaded. The trace line is
`glass Direct2D from the GPU frame WxH px (lens): ms`, and the frame's is
`glass frame WxH px at 0.25x (GPU)`.

Departures and fallbacks:

- **The mirror's condition is structural on the GPU frame.** The surface's rows lie outside
  the content view, which is ADR-0018's case of nothing but the window background beneath
  the band. The CPU frame counts background pixels instead; there is no pixel to count
  without a read-back. The two agree for every window the port draws: a
  `fullSizeContentView` window's content reaches under the band and is sampled directly.
- **The probe's mean reaches the lens as an 8-bit value**, so the variant pick near the 0.35
  threshold can differ from the software pass's by 1/255 of luminance.
- **The CPU frame stays the fallback.** When `makeFrame` returns nil (a target that is no
  device context), the CPU frame is used from then on (`_GlassGPU.framesUnavailable`), with
  round 1's path: the CPU backdrop stage and the lens effect. The software pass is still
  behind it, and `APPKITWIN_LIQUID_GLASS_GPU=0` still forces it.
- A sample drawn from the GPU frame keeps no image: `_GlassSample.isGPUFrame` is set, and
  the invalidation bookkeeping (the window rectangle, the mirrored strip) is kept as before.

**Fixed in passing:** a glass surface with nothing to sample (no window content beneath, a
zero-size crop) made the renderer drop the GPU program for the process, because a draw that
returned false read as a failure. It now draws the software fallback fill and keeps the
program.

**Tests.** `LiquidGlassGPUTests.testGPUFramePlumbingMatchesSoftware` runs Core's round-3
path on the host and in the Linux container with a program that renders its frame on the CPU
and draws each surface from its crop, doing the halving, the crop and the mirror as the
effect graph does. Across a window with two lenses and the toolbar band, that program
through the GPU-frame path matches the same program through Core's CPU frame within the
tolerance, with one frame render per paint. The effect graph itself runs on Windows only.
The PC checks it against the stored captures and against the GPU=0 run.

Two things the test turned up:

- corelibs Foundation's `CGRect.intersects` counts rectangles that only share an edge. The
  structural mirror test asks for an overlap of positive area.
- On Linux the software pass's flat material (the band drawn as its blurred image scaled up
  by cairo, then fills) differs from any program's per-pixel material by up to 79/255 at the
  band's edges, where cairo's filter fades into transparency; Apple's CoreGraphics and the
  programs agree. The programs' material is the reference-faithful one, so the software
  pass's flat path on Linux is a follow-up, not a tolerance change.

**What glass alone can reach.** With the GPU frame, a scroll frame's glass work on Windows is:

- one paint of the window beneath the glass into a GPU bitmap, which is the same tree walk
  as the base paint, at a quarter of the backing scale;
- per surface, one effect graph (round 1 measured the lens draw at 0.04 to 0.08 ms; the graph
  adds GPU passes, not CPU).

What it cannot reach is the cost of that tree walk itself, measured at about 3.3 ms through
the WIC software target. Through the GPU device context it should be cheaper, and by how much
is round 3's PC number. The rest of the gap to 8 ms is the base paint (10.9 ms with glass off
on the PC against 1.3 ms on the host). That belongs to the separate base-paint PR: one tree
walk over the dirty union, cached DirectWrite layouts, simple-shape fills. Every one of those
also cuts the glass frame's tree walk, since it is the same walk. The budget for glass's own
share is the difference glass on minus glass off: 5.4 ms in PC round 1 (16.3 against
10.9), and round 3 aims below 2 ms.

### Fidelity

The constants were tuned against Apple's descriptions, not against pixels: the machine this
was written on runs macOS 15.8, where `NSGlassEffectView` does not exist, so no reference
could be taken here. Stage 2 adds the means to take them:

- `Examples/Glass/ReferenceScene.swift` and `ReferenceSceneGlass.swift` describe four
  scenes with public AppKit and SwiftUI names alone, so the same files compile against the
  port and against Apple's SDK: `light`, `dark` and `over-dark` (light appearance over deep
  colours), each with regular, clear and tinted capsules, a rounded panel and a small circle
  over colour bands, a checker strip and discs; and `interactive`, a regular capsule beside
  SwiftUI's `glassEffect(.regular.interactive())`, in the states `rest`, `hover` and `press`.
- `Glass --reference <scene> <state> <out.png>` draws a scene through the port
  (`APPKITWIN_HOST_SCALE=1` gives the host display a scale of 1 for the 1x captures).
  The port's captures are committed as `docs/images/glass/port-<scene>-<state>@<n>x.png`
  with `port-manifest.json`.
- `tools/glass/capture-references.sh` runs on a macOS 26 Mac. It builds `tools/glass/reference`
  against Apple's SDK, outside the package so the port's AppKit does not shadow it. It
  captures every scene and state with real glass through ScreenCaptureKit, at the display's
  scale and at 1x (resampled by the window server unless the display is 1x; the manifest
  records which), into `docs/images/glass/macos26-<scene>-<state>@<n>x.png` and
  `macos26-manifest.json`. Then it draws the port's captures and prints the comparison for
  each pair: per surface, the interior colour and luminance, the luminance spread (how
  blurred the glass is), and the top and bottom rim against the interior. Capture conditions
  are fixed: a 480x300 pt content area at a fixed position, the window key with its shadow
  off, the pointer parked away for `rest`, and a 1.2 s settle before each capture. Hover warps
  the pointer onto the interactive surface. Press posts a mouse down, which needs
  Accessibility permission for the terminal; without it the press captures are skipped and
  listed in the manifest.

**The macOS 26 references are pending.** The command to produce and commit them, on a macOS 26
Mac with Xcode 26 and its command-line tools selected (`xcode-select -p`):

```bash
git clone https://github.com/medcelerate/AppKitCross.git && cd AppKitCross   # or: git fetch origin && git switch claude/glass-gpu-c4d3e9
git switch claude/glass-gpu-c4d3e9
bash tools/glass/capture-references.sh
git add docs/images/glass && git commit -m "Liquid Glass: macOS 26 reference captures (ADR-0052)" && git push
```

No constant changed in stage 2: retuning without references would be guessing in another
direction (the published WWDC25 and HIG material describes the look but gives no numbers). What to check first when the captures exist, from Apple's material as presented
(WWDC25, the HIG) against this pass:

1. The far edge. The port darkens the bevel facing away from the light (`rim * 0.45`);
   Apple's glass shows a second, weaker highlight there (light reflected inside the lens),
   so its bottom rim is likely brighter than its interior, not darker.
2. Blur against lensing. Apple's regular glass looks less blurred and more lens-like than a
   16 pt blur under a 0.42 white veil: content stays legible through it and bends strongly
   near the edge. The blur radius, the veil and the refraction depth are the three numbers
   the comparison's spread and interior colour decide.
3. Clear glass. Apple's clear variant has almost no frosting; the port's keeps a 10 pt blur
   and a 0.16 veil.
4. The adaptive threshold (0.35) and the dark veil, from the over-dark scene.

Each change goes in with its before and after numbers from the comparison, here.

PC round 1 compared the port's Windows captures with the host's. At 1x the mean difference
was 0.07 to 0.20/255, and the maximum of 18 to 27 came at glyph antialiasing only. At 1.5x it
was 0.9 to 1.1/255 against the resampled 2x captures. The 1.5x captures came out 721x451 px:
the window the platform rounds to whole pixels at 150 %. `Glass --reference` now draws
exactly the scene's 480x300 pt.

The inactive window's glass is brighter than the key window's in light appearance
(13 to 18 levels on the PC). That is by design: inactive glass is flatter and more opaque,
with a 0.6 veil against 0.42, as macOS draws an inactive window's materials. It is one more
thing for the macOS 26 captures to confirm.

