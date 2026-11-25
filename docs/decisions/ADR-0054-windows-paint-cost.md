# ADR-0054: The Windows base paint cost

Date: 2026-11-25. Status: proposed; round 1 measures, the fixes follow the PC's profile.

## Context

PR 99 (Liquid Glass GPU stage, ADR-0052) measured `Examples/Glass --autoscroll 10
--interval 0` in a 900x600 pt window on the Windows PC (RTX desktop, 2560x1440 at 100%):
with glass off a scroll frame's paint averages 10.9 ms against 1.3 ms for the same scene on
the macOS host backend. Two things are mixed in that number:

- The example's "paint" wraps `displayIfNeeded`, which on Windows includes `EndDraw`, the
  canvas-to-back-buffer copy and `Present(1, 0)`. Under vsync `Present` blocks until a
  buffer frees: glass off runs at exactly 59.8 fps, so part of the 10.9 ms is the wait.
- The rest is port-wide: a scroll frame paints about seven rectangles (the exposed strip,
  the floating controls where they were and where their pixels went, the scroller knob;
  PR 96), each a walk of every view tree, and a walk costs about 3 ms on Windows whatever
  its pixel count (a 225x160 px backdrop render 3.25 ms, a 113x80 one 3.42 ms) against
  about 0.3 ms on the host. That points at per-call overhead, not fill rate.

Reading the paint path for per-call costs that do not depend on pixels:

- **Text.** `NSString.draw` on Windows (`Win32TextBackend.draw`) creates a DirectWrite
  `IDWriteTextLayout` on every draw and releases it after; measuring is cached
  (`_NSTextMeasureCache`), drawing is not. Core Text lines shape through `cdw_shape`
  (a text format and layout per call) and `cdw_draw_glyphs` creates a solid colour brush
  for every glyph run.
- **Paths.** Every `fillPath`/`strokePath` builds a fresh `ID2D1PathGeometry` (factory
  call, sink, figures, close) and every stroke a fresh `ID2D1StrokeStyle`; an
  `NSBezierPath(ovalIn:)` or rounded rect therefore costs a geometry where Direct2D has
  `FillEllipse` and `FillRoundedRectangle`.
- **Images.** `CGContext` caches uploaded bitmaps per context, and the window makes a new
  context every paint, so every image drawn in a frame (toolbar glyphs, control images) is
  uploaded again with `CreateBitmap`.
- **Walks.** Each paint rectangle runs a full walk: saves, transforms, clips (antialiased
  axis-aligned clips per view) and `draw(_:)` for every view meeting the rectangle, so
  a view under two rectangles draws twice.

None of these were measured on the PC, so round 1 adds the measurement.

## Decision (round 1: the profile)

`APPKITWIN_TRACE_FRAMES=1` grows two lines per paint, and stays one load and branch per
call when off:

- `frames paint ...` (NSWindow, every backend) now also prints the number of tree walks
  and, per walk, views drawn / views entered (`NSView._paintViewsDrawn`,
  `_paintViewsVisited`; `NSWindow._lastPaintWalks` for tests).
- `frames d2d paint X ms = draw Y + finish Z (rects, walks, views drawn): ...` (Win32):
  the shim's call count and CPU milliseconds for each category that ran: `geometry`
  (path geometry creation and population), `stroke-style`, `brush`, `text-layout`
  (DirectWrite layout creation), `text-shape`, `text-draw`, `fill-rect`, `fill-path`,
  `stroke-rect`, `stroke-path`, `clip-rect`, `clip-layer`, `bitmap-create`,
  `bitmap-draw`, `offscreen` (WIC bitmap targets), `transform`, `clear`, `end-draw`,
  `copy`, `present`. `draw` is the time to the end of the view walk, `finish` EndDraw,
  the copy and Present. Every 60 paints a `frames d2d mean of 60 paints` line averages
  the lot.

Counters live in the CD2D shim (`cd2d_stats_*`, a `QueryPerformanceCounter` pair per
call while on); CDirectWrite reports through `cd2d_stats_begin`/`end`. Times are CPU time
inside the call: Direct2D batches drawing, so fills and strokes record cheaply and their
GPU work lands in `end-draw`.

`APPKITWIN_PRESENT_INTERVAL=0` presents with sync interval 0, for measuring the paint
without the vsync wait; normal runs keep `Present(1, 0)`.

## Consequences

Round 2 implements what the profile justifies and records it here.
