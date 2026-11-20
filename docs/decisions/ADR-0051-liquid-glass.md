# ADR-0051: Opt-in Liquid Glass

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
hundred by a few dozen pixels. The backend's material pass blurs it; the surface draws the
blurred sample clipped to its outline, lays the veil over it (white at 40 % in light
appearance, a dark grey in dark; more of it when the window is inactive), the tint if any,
and for a lens the rim (a one-point ring inside the outline under a vertical gradient from
white at the top to a faint shadow at the bottom) and a three-ring soft shadow below.
Materials (a band, a column, an effect view's material) get the blur and veil only.

The sample is cached per surface (`_GlassSample`, kept by `_GlassRegistry`) and taken
again only when a view that is not the surface or one of its subviews dirties a rectangle
intersecting the surface, when the surface moves or changes scale, or when the appearance
changes; every invalidation passes through `NSWindow._viewNeedsDisplay`, which is where the
registry hears of it, and the surface marks itself for display when its sample goes stale.
Nothing is invalidated from inside a draw (the Daily To Do lesson): a sample is only ever
taken during a paint, and a stale one is noted, not repainted, by the invalidation that
caused it. The per-rect paint path (PR 92) is untouched; a surface clipped to part of a
dirty rect draws that part from its cache.

### Platform

`PlatformMaterialBackend` (`Platform/Material.swift`) is the pixel pass: `blur(_:radius:)`
over premultiplied 32-bit pixels. `SoftwareMaterialBackend` (three separable box blurs,
the classic Gaussian approximation) is every backend's default through an extension on
`PlatformBackend`; Direct2D's Gaussian blur effect or a Vulkan pass can replace it on a
backend by overriding `material` without Core changing. The offscreen surfaces come from
the existing `PlatformImageBackend.makeOffscreen`, whose pixels are premultiplied BGRA on
all three backends (Direct2D bitmaps, cairo image surfaces, the host's bitmap context), so
the one blur serves them all.

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
tests. The container keeps the spacing but draws each glass view on its own: the morphing
bridge macOS animates between neighbours closer than `spacing` is not drawn. With the
switch off a glass view draws the translucent window-colour tint a within-window
`NSVisualEffectView` draws. `NSVisualEffectView` within the window takes the glass material
with the switch on (HUD and dark materials keep their dark veil, a selection its colour);
behind-window blending is as before.

### SwiftUI API

`Glass` (`regular`, `clear`, `identity`, `tint(_:)`, `interactive(_:)`),
`DefaultGlassEffectShape` (the capsule), `glassEffect(_:in:isEnabled:)`,
`GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`,
`Namespace` (new; `@Namespace` had no port), `GlassButtonStyle`/`.glass` and
`GlassProminentButtonStyle`/`.glassProminent`. `glassEffect` puts an `NSGlassEffectView`
clipped to the shape behind the view with the switch on, and is the view itself off (no
wrapper view: the hierarchy is the one without the modifier). `glassEffectID` and
`glassEffectUnion` accept their identifiers and draw nothing extra. The glass button styles
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

- Nine pixel tests (`LiquidGlassPixelTests`): blurred content beneath (red on the left,
  blue on the right, a blend at the edge that is softened yet present, lifted by the
  veil), the rim highlight along the top and none along the bottom, the inactive window's
  flatter and less saturated glass, the dark veil in dark appearance, the sample cache
  (kept across the surface's own redraw and an invalidation outside it, stale after one
  beneath it), the switch-off flat tint with no rim, the SwiftUI fallbacks (no extra view
  from `glassEffect`, a glass button identical in PNG to the bordered one) and the
  sidebar pane flag, plus the software blur's ramp and alpha. They run on the host and in
  the Linux container; Windows draws the same Core pass over Direct2D offscreens and is
  checked on the PC.
- Cost: a glass surface's first draw and every resample paint the window once more, into a
  surface of a sixteenth of the pixels (a quarter of the backing scale in each direction),
  plus three box-blur passes over it. A view animating beneath a glass
  surface resamples it every frame, which is what glass means; a toolbar over static
  content never resamples.
- Not done: the container's morphing merge and `glassEffectID` transitions; a GPU blur on
  Windows and Linux; the sidebar lit by the desktop through Mica (needs the non-opaque
  window); the scroll-edge effect macOS 26 fades in under a toolbar as content scrolls
  beneath it, which would need the content to extend under the band (ADR-0018 keeps the
  band outside the content area).
