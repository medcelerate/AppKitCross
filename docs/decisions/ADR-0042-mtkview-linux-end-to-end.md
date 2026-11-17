# ADR-0042: MTKView on Linux, end to end

Status: accepted. Date: 2026-11-17. Extends ADR-0012 (the Vulkan backend and its swap-chain
presentation, PR #35).

## Context

PR #35 made `MTKView` present through a `VkSwapchainKHR` on a native surface under the
view: a child X window (`VK_KHR_xlib_surface`) or a desynchronised `wl_subsurface`
(`VK_KHR_wayland_surface`), with the readback path as the fallback (ADR-0012,
"Presentation"). An audit of that path against the view's whole API, as an application
drives it, found three gaps that the presentation tests did not reach, because every one
of them drew a frame right after each change:

1. **Hiding.** The chain and surface were dropped only when the next drawable was asked
   for. A view drawn on demand (`enableSetNeedsDisplay`), a paused view, or a view whose
   *ancestor* was hidden never asks again, so its native surface stayed on screen above
   the window: the X child window and the subsurface are not part of the window's pixels
   and do not disappear with the view's own drawing.
2. **Moves without a resize.** The surface was re-placed only on the next drawable too. A
   view moved by `setFrameOrigin`, or by an ancestor's layout, left its surface (and the
   last frame in it) where it was until the next frame, which for an on-demand view may
   never come.
3. **Drawing modes.** `draw(_:)` ran the delegate on every window paint when the view was
   *paused* (`isPaused` alone), as well as with `enableSetNeedsDisplay`. Apple's table has
   three modes: timed updates (neither flag; the internal display link), draw notifications
   (`enableSetNeedsDisplay`, which also pauses the link) and explicit drawing (`isPaused`
   alone: only `draw()` runs a frame). A paused view that drew on every paint presented
   frames its app did not ask for, through the chain on Linux and Windows and through the
   readback on every platform.

The CI side had one gap as well: the lavapipe job runs `HelloWindow --metal-selftest`
without a display, which checks the device offscreen but never a *presented* frame, while
on Windows `MetalD3D12ParityTests` compares a presented `MTKView` frame against the
reference device.

The synchronisation of acquire and present was audited and is unchanged: the acquire
semaphore (plus a fence the CPU waits, so the side is in step) gates the transition into
`GENERAL`, a per-image present semaphore signalled by the transition into `PRESENT_SRC`
gates `vkQueuePresentKHR`, and `OUT_OF_DATE` / `SUBOPTIMAL` re-create the chain at the next
acquire. Per-image present semaphores are the safe choice here: an image is only acquired
again after the presentation engine released it, so its semaphore has been waited.

## Decision

**`viewDidHide` / `viewDidUnhide` reach descendants** (`NSView`, all platforms): Apple
documents both as "invoked when the view is hidden, either directly, or in response to an
ancestor being hidden". Setting `isHidden` now notifies the subviews that are not hidden
themselves, recursively, when the change is visible (no hidden ancestor above the view whose
flag changed). No hand-written or generated view overrode either method before.

**`MTKView` on Linux** uses them and the frame hooks:

- `viewDidHide` drops the chain and the native surface; `viewDidUnhide` clears the
  remembered creation error and marks the view for display, so the next frame (link or
  paint) makes a new surface and chain.
- `setFrameOrigin(_:)` and the start of `draw(_:)` (every window paint, which follows any
  layout change) re-place an existing surface at `convert(bounds, to: nil)` clipped to the
  content view, without drawing a frame; a view wholly outside the content area drops it.
  Resizes and backing-scale changes keep their existing path (`_resizeDrawable` re-sizes
  the chain and draws at once).
- `_presentationSurfaceFrame` (tooling, like `_swapChainPresentCount`) reports where the
  surface is, so the Wayland run, which cannot read pixels back, can check placement.

**Drawing modes** (`MTKView`, all platforms): a window paint runs the delegate only with
`enableSetNeedsDisplay`; a paused view shows its last frame (the readback path draws the
last presented texture, a chain keeps showing its last image). The display link is
unchanged: it runs only when neither flag is set, at `preferredFramesPerSecond`
(`CADisplayLink` skips ticks closer than 0.9 of the interval).

**Presented-frame self-test** (`HelloWindow --metal-selftest`, Linux): after the offscreen
checks it shows a window with a 64x48-point `MTKView` (explicit drawing), draws one cleared
frame, reads the drawable it presented back (`getBytes` on a chain image goes through
`GENERAL` and back to `PRESENT_SRC`), checks that the drawable is the view's
`drawableSize` and `colorPixelFormat`, and compares it against the same clear on the
reference device within one level per channel. With a window system (`DISPLAY` or
`WAYLAND_DISPLAY`, not the host backend) and a presentable device it also requires the
swap-chain path and a counted present; the window is mapped first by running the
application's event loop for half a second, since a Wayland FIFO present waits for the
compositor's frame callback. Headless, it compares the readback path's drawable. The CI job
runs it both ways: as before without a display, and under `xvfb-run` on the X11 backend.

## Testing

- `Milestone7Tests.testMTKViewDrawingModes` (host backend, every platform): a paint does
  not run the delegate of a paused view, `draw()` does, a paint after it shows the last
  frame, and `enableSetNeedsDisplay` makes a paint draw.
- `Milestone7Tests.testViewDidHideReachesDescendants`: ancestors' hide and unhide reach
  visible descendants once, not hidden ones, and not under an already hidden ancestor.
- `MetalVulkanPresentationTests` (X11 under Xvfb, Wayland under the headless sway; skipped
  with the reason on the host backend and without a presentable device) gains:
  `testDrawableMatchesTheViewSizeAndFormat` (the chain's image is the view's
  `drawableSize` in `bgra8Unorm` and `bgra8Unorm_srgb`), `testHidingTheViewDropsTheSurface`
  (the view and an ancestor), `testMovingTheViewMovesTheSurface` (origin moves without a
  frame, clipping, leaving the content area; pixels checked on X11) and
  `testDisplayLinkDrivesPresentsAtThePreferredRate` (timed updates present through the
  chain at 10 fps, a paused view stops).
- By hand in the container: HelloWindow's Metal tab (`--metal --metal-log --metal-static`)
  under Xvfb and under the headless sway, screenshots in `docs/screenshots/`.

The brief named the suite `MetalVulkanPresentTests`; the tests went into the existing
`MetalVulkanPresentationTests`, which the CI job and `tools/linux/run*.sh` already filter on.

## Consequences

- An on-demand or paused `MTKView` on Linux behaves like the rest of the window when it is
  hidden or moved: no stale native surface above the window.
- A paused `MTKView` no longer draws frames on window paints on any platform; an app that
  relied on that gets the explicit-drawing mode it asked for (call `draw()` or set
  `enableSetNeedsDisplay`).
- Known limit, unchanged from PR #35 and left for a follow-up: a view only partly inside the
  content area gets a surface clipped to it, while the chain stays `drawableSize`. On X11
  the child window's size is the surface's current extent, so the chain and the drawable
  disagree for as long as the view is clipped. The fix is to give X11 the unclipped frame
  (the server clips child windows to their parent) and crop the Wayland subsurface with
  `wp_viewporter`, which is not bound yet.
- Subviews of an `MTKView` still composite under the native surface on Linux (ADR-0012).
