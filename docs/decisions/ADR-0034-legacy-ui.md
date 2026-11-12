# ADR-0034: Legacy and miscellaneous UI: gradients, NSAnimation, rulers, drawers, scrubbers

Date: 2026-11-12. Status: accepted, awaiting verification on the Windows PC.

## Context

The generated stub burn-down splits the remaining `unimplemented()` members into groups.
This one is the legacy and miscellaneous UI set: `NSGradient`, `NSAnimation` and
`NSViewAnimation`, `NSRulerView` and `NSRulerMarker`, `NSDrawer`, and the `NSScrubber`
family (`NSScrubberArrangedView`, `NSScrubberItemView`, `NSScrubberTextItemView`,
`NSScrubberImageItemView`, `NSScrubberSelectionView`, `NSScrubberSelectionStyle`,
`NSScrubberLayout`, `NSScrubberLayoutAttributes`, `NSScrubberFlowLayout`,
`NSScrubberProportionalLayout`): about 250 generated stubs. All seventeen classes are now
hand-written in `Sources/AppKit/Core`; what stays unimplemented is `NSCoding` (as for the
other hand-written classes), making scrubber items from nibs, and a `rulerViewClass`
subclass (below).

Platform facts that shape the design:

- The port's CoreGraphics on Direct2D and Cairo has fills, strokes and clips but no
  shading or gradient primitive; the macOS host build uses Apple's CoreGraphics.
- Win32 keeps an owned window above its owner and X11 window managers keep a transient
  window above its parent, so a child window cannot slide out from *behind* its parent.
- There is no modal event-tracking loop in the port: `NSApplication.nextEvent(matching:...)`
  only reads the posted-event queue; controls track the mouse through the
  mouseDown/Dragged/Up events the window routes to the pressed view.
- There is no Touch Bar off the Mac.

## Decision

### NSGradient

Stops are kept sorted by location (a stable sort keeps equal locations as a hard edge);
colours are interpolated component-wise in RGBA between neighbouring stops, clamped to the
end colours outside them. Drawing is backend-neutral: the axis is cut into about two bands
per point (at most 1024), each filled with the colour at its middle, in a space rotated so
the axis runs along x; antialiasing is off for the bands so neighbours share edges exactly
(no seams and no double-painted overlap for translucent colours), while the rect or path
clip of `draw(in:...)` keeps the outer edge antialiased. Radial gradients paint rings, the
even-odd area between the circles at successive locations, which is exact for nested
circles (highlights, spots) and an approximation for circles that are not nested. The
`drawsBefore/AfterEndingLocation` options paint the extension beyond the axis or outside
the larger circle / inside the smaller one with the end colours. `draw(in:angle:)` puts the
axis through the rect's centre so the stops span the rect's projection;
`draw(in:relativeCenterPosition:)` starts at a point at the relative position and ends at a
circle around the rect's centre that encloses it. The extent of unclipped extension bands
comes from the clip's bounding box; `boundingBoxOfClipPath` (CoreGraphics' name) was added
to the Direct2D and Cairo contexts. The convenience initialisers' colour space is AppKit's
generic RGB, which the port's `NSColorSpace` does not model yet, so `colorSpace` of such a
gradient calls into the unimplemented `NSColorSpace.genericRGB`.

### NSAnimation and NSViewAnimation

Progress runs from 0 to 1 over `duration` on Core Animation's clock (`CARuntime.now`), one
step per frame of a `CADisplayLink` like `_NSFrameTimer` and the sheet slide, so tests drive
it with a fake clock and `CARuntime.tick()`. Each step sets `currentProgress` (subclasses
override the setter to apply it, as in AppKit), reports the progress marks passed since the
previous step to the delegate and as `progressMarkNotification`s (user info
`NSAnimationProgressMark`), and starts or stops the animations linked with
`start(when:reachesProgress:)` / `stop(when:reachesProgress:)` (which add the mark).
Curves: ease-in-out is a half cosine, ease-in and ease-out its quarter halves. `currentValue`
is the delegate's `animation(_:valueForProgress:)` (the generator's default for that
optional requirement is the curve value, and `animationShouldStart` defaults to true).
Blocking mode (AppKit's default) steps in a loop inside `start()`, redisplaying the
application's windows between steps; the port has no private run-loop mode for it, so other
run-loop sources wait. The threaded non-blocking mode runs on the main thread's frame clock
like the non-blocking one. `NSViewAnimation` (0.5 s, ease-in-out) reads its dictionaries
when the animation first moves (start and end frames as `NSValue(rect:)` or `NSRect`,
defaulting to the current frame), interpolates frames with the curve value, fades alpha for
the fade effects, and at the end hides a view that faded out or whose end frame is empty
(a window is ordered out).

### NSRulerView and NSRulerMarker

`NSScrollView` creates rulers when `hasHorizontalRuler`/`hasVerticalRuler` are set, shows
them while `rulersVisible`, and tiles them inside the border: the horizontal ruler across
the top (over the corner), the vertical ruler down the left; scrolling redisplays them.
Across a ruler's thickness, from the outer edge: the accessory view's band, the markers'
band (the reserved thickness or the tallest marker), then the rule; the baseline is the
border between markers and rule. Marker locations and the origin offset are in the client
view's coordinates, everything else in the ruler's; conversion goes through the view
hierarchy and the client's `rulerView(_:locationFor:)`/`rulerView(_:pointForLocation:)`, so
scrolling and scaling move the marks with the content. Hash marks follow AppKit's unit
cycles: the labelled step grows by the step-up cycle until labels are 36 points apart
(24 vertical), then marks subdivide by the step-down cycle while they stay 5 points apart
(inches: labels every inch, marks down to eighths). Built-in units: inches, centimetres,
points and picas; `registerUnit` adds more. Labels are drawn beside the labelled marks.

Without a modal tracking loop, marker drags run on the ruler's mouse events: mouse-down on
a marker (or `trackMouse(with:adding:)` / `trackMarker(_:withMouseEvent:)`) starts the drag
and returns whether it started; dragged events move the marker through the client's
`willMove`/`willAdd`; mouse-up ends it with `didMove`, removes a removable marker dragged
more than the ruler's thickness off it (after `shouldRemove`), or adds a new marker with
`didAdd`. The ruler client methods on `NSView` (AppKit's informal protocol) default to
allowing every change and mapping locations to the view's own x or y.

`NSTextView` is a client: `usesRuler` is on by default, as in AppKit; the text view takes
its scroll view's horizontal ruler when its selection changes while the rulers show (or
`toggleRuler(_:)` shows them), and `updateRuler()` puts up
`NSLayoutManager.rulerMarkers(for:paragraphStyle:ruler:)`: first-line, head and tail indent
markers and one marker per tab stop of the selected paragraph's style. Moving one changes
that value in the paragraphs `rangeForUserParagraphAttributeChange` covers (an undoable
edit), dragging a tab stop off removes it, and a click on the rule drags in a new left tab
stop. The marker images are drawn by the package. `rulerAccessoryView(for:...)` stays
unimplemented. Swift cannot call `NSRulerView`'s (non-required) initialiser through a
metatype, so a `rulerViewClass` subclass cannot be instantiated by the scroll view; setting
`horizontalRulerView`/`verticalRulerView` works.

### NSDrawer

A drawer is a borderless child window of its parent against one edge. Since an owned window
stays above its owner, the drawer does not come out from behind the parent: its window grows
outward from the parent's edge while the drawer's panel is pinned to the outer edge, so the
outer edge appears first, as if it came out from under the parent. The slide is an
`NSAnimation` (ease-out, 0.2 s for a full slide) on the frame clock; it is off on the headless
host backend, as the sheet slide is, and the slide test turns it on. Along the edge the
drawer spans the parent's content area (left and right edges; the leading offset is from
the top) or its frame width (top and bottom), less the offsets; across it, `contentSize`
plus a 6-point border. `open()` uses the preferred edge unless the drawer would leave the
screen there and fits on the opposite edge. The parent's moves and resizes carry the drawer;
the parent closing closes it. Dragging the outer border resizes the content through
`drawerWillResizeContents(_:to:)` and the size limits. Delegate and notifications follow
AppKit's order (should, will, did); reopening while closing reverses the slide.

### NSScrubber

There is no Touch Bar off the Mac, so a scrubber is an ordinary view: a horizontally
scrolling strip. The items sit in a document view inside a scroll view without scrollers;
the layout (`NSScrubberFlowLayout` by default: `itemSize` 50×30, the flow delegate's sizes,
`itemSpacing`, centred vertically; `NSScrubberProportionalLayout`: the visible width divided
among `numberOfVisibleItems`) gives the frames, and only items in the visible rect have
views, asked of the data source and recycled by identifier. As for collection views, a class
registered with `register(_:forItemIdentifier:)` is made through `init?(coder:)` (the text and
image item views support it). The selection styles' views sit at the selected item, the
background one below the items and the overlay one above; the built-in rounded background
and outline overlay are drawn by the package in the accent colour. With the mouse, a click
selects; a drag scrolls in free mode and moves the highlight in fixed mode; a continuous
scrubber selects as the pointer passes items; the wheel (either axis) scrolls; arrow
buttons page; after a scroll the item nearest the alignment point snaps to it. Content
indicators fade the ends with an `NSGradient` while more content lies beyond.
`floatsSelectionViews` is stored (the selection view moves at once).

## Consequences

- `HelloWindow`'s Layout Demo gains a Legacy tab: a gradient swatch, a text view with its
  ruler, a drawer toggle and a scrubber.
- Tests: `LegacyUITests.swift` (21 tests in five suites; gradient pixels on the host backend
  only).
- Windows and Linux need checking by hand: drawer slide and border resize as a Win32 owned
  popup and an X11 transient, ruler marker drags, gradient banding at 150%, scrubber
  scrolling and selection.
