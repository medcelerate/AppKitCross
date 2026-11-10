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

## 3D transforms (2026-11-10)

A node under a 3D rotation or a perspective `sublayerTransform` carries the full 4x4
(`transform3D`, PR 16) and DirectComposition applies it to the visual. The software
compositor (Cairo on Linux, the Direct2D canvas on Windows windows without composition,
and the host backend's reference compositor) only has an affine CTM, so it used to draw
the affine part and the perspective was lost there.

Core Animation flattens a layer's sublayers into the layer's plane, so the map from a
sublayer's plane into its superlayer's is a 2D homography (the 4x4 restricted to z = 0,
with the perspective divide). `CALayer._planeTransform` builds that map for a layer: the
geometry flip, anchor, `transform`, `position` and the superlayer's `sublayerTransform`
combined in 3D, which `_nodeTransform` (the scene) and `_compose` (the software
compositor) share. When the map is affine the layer is placed through the CTM as before;
when it is projective the layer's subtree is rasterised to an offscreen surface (at the
context's scale, more where the projection magnifies) and drawn through the homography
by `_CAProjective.draw`: the extent is split into a mesh of up to 8x8 cells, each drawn
with the affine transform fitted to its projected corners (centre on the projected
centre, axes the mean projected edge vectors) and clipped to them. The mesh is only as
fine as the curvature needs: the corner one affine fit misplaces must land within half a
device pixel, so a nearly affine layer is one draw. Neighbouring cells overlap by a third
of a pixel so anti-aliased clip edges leave no seams. This is the portable choice:
neither Cairo nor Direct2D's bitmap canvas draws images through a projective matrix,
and a per-pixel inverse mapping would cost a CPU pass per frame.

Consequences: `convert(_:from:)` and `hitTest` go through the homography and its inverse
(a point behind the eye misses), so a mouse event over a rotated card lands on the card
where it is drawn; a layer with `isDoubleSided == false` whose projection mirrors its
plane is culled with its subtree, at scene build time and in the software compositor;
`CATransformLayer` orders its sublayers by projected depth, other layers by `zPosition`
then sublayer order as Core Animation does; the host backend's reference compositor
flattens a projective node's subtree the same way, so `LayerPerspectiveTests` can compare
the hosted and software composites against the analytically projected quad. Not done:
a `CATransformLayer` still flattens its sublayers at its own plane rather than keeping
their 3D transforms for the ancestor's projection.
