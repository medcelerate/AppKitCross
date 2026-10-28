# ADR-0005: Native hosting of the Core Animation layer tree

Date: 2026-10-29. Status: accepted (AppKit side implemented; DirectComposition side in progress).

## Context

M4 renders `CALayer` trees with a software compositor: every frame of an animation
re-rasterises the whole window into the swap chain. Each layer's drawing already runs on
the GPU through Direct2D, but placement, opacity, clipping and animation interpolation are
replayed in full each frame. Apple's QuartzCore hands the tree to the WindowServer, which
keeps one surface per layer and composites them on the GPU; Windows has the same model in
DirectComposition (DWM visuals). We want animating transforms and opacity to cost no
redraws, and CAMetalLayer to contribute its own swap chain as a visual later.

## Decision

QuartzCore flattens a layer tree into a retained-mode scene (`_CALayerScene`, exposed to
the platform as `PlatformLayerScene`) and the window offers it to the platform through
`PlatformWindow.hostLayerScene(_:)`. A node is one visual: a parent index, a 2D affine
transform in points mapping its local space (y-down, origin at its top-left) into the
parent's local space, a size, an opacity, an optional clip (rect plus corner radius and
masked corners), and optional content.

Content is not pixels but a `version` plus a `draw(CGContext)` closure. The platform keeps
one surface per node id and re-rasterises only when the version changes, drawing straight
into the surface (DirectComposition's `IDCompositionSurface::BeginDraw` yields a D2D
context, which `CGContext` already wraps), so there is no CPU readback. Versions are kept
by `CALayer`: `_rasterVersion` moves on any change that is not purely compositing
(position, transform, opacity, hidden, anchor point, z-position, sublayer transform are
compositing-only), `_borderVersion` on border changes, `_treeVersion` on any change in the
subtree; animations of raster properties stamp the frame counter so the node redraws each
frame.

Rules:

- Hosting activates only when the window's content view is layer-backed, so every view is
  a visual and the swap chain holds nothing but the window background. Mixed trees stay in
  software. Views that host a foreign layer tree (`view.layer = tree`) are added to the
  scene as children of their superview's node.
- A layer the visual model cannot express — a mask, a shadow, a sublayer transform — is
  flattened: its subtree becomes one node drawn by the software compositor
  (`render(in:)`), redrawn each frame while anything in it animates.
- Borders are their own node after the children, since Core Animation draws them above
  sublayers.
- The platform may decline (`false`) at any commit and the window falls back to software.
- Commits are coalesced: a change marks the window's scene dirty and requests a frame;
  the frame callback ticks animations and then commits every dirty window. `display()` and
  `displayIfNeeded()` commit synchronously, as does the paint callback.

The host backend (`HostWindow.layerHostingEnabled`) implements a reference compositor on
top of the same scene so tests compare the hosted composite with the software one pixel
for pixel (within one anti-aliased edge).

## Consequences

- Windows: `Win32Window` builds an `IDCompositionVisual` tree from the scene under the
  swap-chain visual, keyed by node id, with `SetTransform`, `SetOpacity`, `SetClip`
  (`IDCompositionRectangleClip`) and an `IDCompositionSurface` per content node. Opaque
  windows move to the composition swap chain already used for translucent ones.
- Shadows and masks are not accelerated yet (DirectComposition has shadow and clip
  effects; a later ADR can map them instead of flattening).
- Group opacity is applied per draw, as in the software compositor, not as a true
  transparency group.
- Linux keeps the software compositor; a Wayland/Vulkan backend could implement the same
  seam.
