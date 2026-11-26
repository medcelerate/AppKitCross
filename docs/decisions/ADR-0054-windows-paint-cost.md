# ADR-0054: The Windows base paint cost

Date: 2026-11-25. Status: accepted; PC round 2 (6697797) passed.

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

## The PC profile (round 1, 89cde80, glass off, 1x)

`Glass --autoscroll 10 --interval 0`, steady state, means of 60 paints:

| | vsync (default) | `APPKITWIN_PRESENT_INTERVAL=0` |
|---|---|---|
| example's paint mean | 11.0 ms | 4.0 ms (101.6 fps) |
| draw (to the end of the walk) | 3.9-4.2 ms | 3.9 ms |
| finish (EndDraw, copy, Present) | 6.4-6.9 ms | 0.4 ms |
| `present` | 6.1-6.6 ms | 0.07 ms |
| shim total without end-draw/present | ~0.75 ms | ~0.7 ms |

Per paint: 6 rects, 6 walks, 39 views drawn; `text-shape` 12.7 calls / 0.51 ms (the
largest shim cost), `text-draw` 14.7 / 0.04 ms, `geometry` 48 / 0.07 ms, `fill-path` 46,
`fill-rect` 26, `clip-rect` 59, `transform` 186, all at a few hundredths of a millisecond;
`end-draw` 0.30 ms. No bitmap uploads, offscreen targets or text layouts in a scroll frame.

What that says:

- **The 10.9 ms was mostly the vsync wait.** Back-to-back frames on a two-buffer flip
  chain block in `Present` until a buffer frees: 6-7 ms of the paint. Without the wait the
  whole paint is 4.0 ms, already under the 5 ms goal. Nothing is wrong with presenting; the
  example's number just measured it. The trace keeps `draw` and `finish` apart.
- **Direct2D is not the cost.** Geometry, fills, clips and transforms total well under a
  millisecond however many there are; the candidate fixes for them (FillEllipse, cached
  geometries and brushes) would save hundredths of a millisecond and are not done.
- **About 3.1 ms of the 3.9 ms draw is outside the shim**: Swift code in the walk and in the
  views. The one shim category that is real, `text-shape`, points at the part of it that
  repeats: every string drawn is laid out again (an attributed string, a typesetter, a
  line, the port's Core Text on DirectWrite) and the Glass bands ask
  `NSFont.systemFont(ofSize:weight:)` for their font in every `draw(_:)`, each answer a new
  platform font (a Core Text font with a descriptor copy, a DirectWrite face lookup) that
  the shim does not time.
- **A frame gap of 9.8 ms against a 4.0 ms paint** without vsync: 5.8 ms a frame goes
  outside `displayIfNeeded`. The pump's wait cannot be it at `--interval 0` (the timer is
  always due, so the wait is zero), which leaves the scroll step before the paint and the
  run loop's servicing. Round 2 splits it.
- The fifth walk's "10/5" (drawn above entered) was the counter: a layer-backed view draws
  through its layer delegate without entering `_displayHierarchy`, so it counted as drawn
  only. It now counts as entered too.

## Decision (round 2: the repeated text work)

- **Fonts are cached by request.** `NSFont`'s factory (`systemFont`, `init(name:size:)`,
  descriptors, `withSize`, the font manager's conversions all go through it) keeps the font
  it made for each (family, size, weight, italic, monospaced) and answers a repeat with the
  same object, as AppKit's shared font instances do. Fonts are immutable, so sharing is
  safe; a family that is not installed is remembered as a miss. Bounded at 1024 entries.
- **Drawn strings keep their lines.** The Core Text string backend (every platform's
  `NSString.draw`; Windows and Linux run the port's Core Text, the host Apple's) keeps the
  `CTLine`s it laid out for each (string, font, colour, wrap width) and draws them again
  without laying out. Measuring was already cached (`_NSTextMeasureCache`). Bounded at 2048
  entries; the font is held with its lines so its identity cannot be reused.
- **The trace grows what the shim cannot see.** `frames paint` now gives each walk's time
  next to its views drawn/entered, and the paint's strings drawn (with their time and how
  many had to be laid out) and platform fonts made (with their time). The Glass example's
  summary gains a `gap split` line: scroll step, paint, and the time outside the timer
  callback.

Not done, because the profile does not justify it: path geometry and brush caching,
`FillEllipse`/`FillRoundedRectangle`, the per-context bitmap cache (no uploads in a scroll
frame). One walk over all rectangles is held for round 2's per-walk times: Direct2D has no
cheap multi-rectangle clip (`clip(to: [CGRect])` is the union's box on Windows), so a single
walk would either draw everything inside the union's box or need a geometry clip layer per
view, and the shim's numbers show the per-view Direct2D overhead of a walk is small.

## Consequences

`PaintTextCostTests` (host) checks that repainting views that ask for their font and draw
their labels in `draw(_:)` makes no platform font and lays out no line, that two requests
for a font answer with the same object, and that no walk reports more views drawn than
entered. The pixel tests are unchanged.

PC round 2 measures the same runs: the `strings drawn ... fonts made` fields should show
nothing laid out and no fonts made in a steady scroll frame, and `draw` should fall by
what the text and fonts cost. If the walk itself is still most of the draw, the per-walk
times say whether merging walks is worth its clip cost.

## The PC result (round 2, 6697797, glass off, 1x, both monitors at 100%)

`Glass --autoscroll 10 --interval 0`:

| | round 1 | round 2 |
|---|---|---|
| draw (trace, steady frame / 60-paint mean) | 3.7-4.2 ms | 1.66-2.07 ms |
| paint without the vsync wait (example) | 4.03 ms | 2.22 ms (124.5 fps) |
| `text-shape` per paint | 12.7 / 0.51 ms | 0 |
| shim total without end-draw/present | ~0.75 ms | ~0.2 ms |
| paint under vsync (example) | 11.0 ms | 11.1 ms (the wait) |

Steady frame: 6 walks of 0.22, 0.37, 0.28, 0.27, 0.41 and 0.08 ms (about 1.6 ms, now
most of the draw); 14 strings drawn in 0.11 ms, none laid out; no fonts made. Over 1,178
paints, 1,154 laid out nothing, 23 laid out one line (a "Band N" label scrolling into view
for the first time) and the first paint 13; one font was made, on the first paint. The
scroll step before the paint is 0.17 ms. `Glass --screenshot` is byte-identical to round
1. Sweep: Sibyl idle 30 s used 78 ms of CPU; TextEdit typing, underline and undo,
MDVault scrolling an 82K-character note (no layouts or fonts while scrolling) and the
Toolbar example's display modes and resizes drew correctly.

**Which monitor.** `APPKITWIN_PRESENT_INTERVAL=0` has no effect on the PC's primary
monitor (59 Hz): `Present(0, 0)` still blocks to vsync there (11.1 ms paint), likely DWM
declining sync-interval-0 presents of a windowed flip chain on that display. It works on
the second monitor, where round 1's 4.03 ms and round 2's 2.22 ms were measured. Numbers
without the vsync wait must say which monitor they came from.

## Further follow-ups

- **Merging walks.** Six walks now cost about 1.6 ms of a 2 ms draw. A merged walk needs a
  clip for several rectangles that Direct2D does not make cheaply (see above); measure a
  geometry-group clip layer per walk against the six walks before doing it.
- **Time outside the timer callback.** With frames back to back, about 5.5 ms a frame
  passes between one autoscroll callback ending and the next starting, whatever the paint
  costs and with or without vsync. The scroll step is 0.17 ms, so it is the run loop and
  the Win32 pump (`PlatformMainQueue.service`, the `MsgWaitForMultipleObjectsEx` loop in
  `Win32Backend`), not drawing. `APPKITWIN_TRACE=1`'s once-a-second `pump` line (wakes,
  service time) is the place to start.
- **MDVault editor blank for a large note** (pre-existing, seen at PR 98/99 builds too;
  the text system's owner, ADR-0030/TextKit 1 incremental layout): the Editor tab of an
  82K-character note draws nothing (0 views drawn, frame ticks of 390-620 ms), with LF or
  CRLF line ends; afterwards toggling the mode does not repaint until the window reopens.
  Separately, with CRLF line ends the status bar counts 17 lines for 1,073 (only bare LFs
  count). Small notes render fine.
- **Toolbar "Label only" search item** (pre-existing; the toolbar's owner, ADR-0021
  controls / the toolbar item views): the search item reads "SearchSearch", its label
  drawn inside the field over the clipped placeholder.

## Follow-up: smear below the screen edge while scrolling (reported in PR 99 round 3)

`Examples/Glass --autoscroll 25` on a 150% monitor, window 2230x1457 pt straddling the
monitor seam with its lower part below the screen edge: the visible bottom rows show the
document smeared downward (the tops of the purple dots streak through the orange band).
Glass lenses are correct, so it is the base paint path, not ADR-0052.

Likely cause, from reading the code (unconfirmed): `paint()` takes `BeginPaint`'s
`rcPaint` as the frame's dirty rect and clips drawing to it. Windows clips a window's
update region to its visible part, so when the uncovered strip lies below the screen edge
it is never drawn, and the canvas there keeps stale rows. `scrollBacking` then copies the
whole clip view, stale rows included, upward by the scroll step, so each frame pulls
the never-painted rows into the visible rows just above the edge: streaks.

Candidate fix: `scrollBacking` refuses the copy (returns false, so the clip view repaints
whole) when the copy's source is not wholly on a monitor (`MonitorFromPoint(...,
MONITOR_DEFAULTTONULL)` on its corners, or the visible region from `GetRandomRgn`), or
clamps the source to the visible part and invalidates the rest. The PC confirms first:
with `APPKITWIN_TRACE=1`, the `win32 paint dirty` lines should show
`rcPaint` stopping at the screen edge while the `win32 scroll copy` source reaches past it.
