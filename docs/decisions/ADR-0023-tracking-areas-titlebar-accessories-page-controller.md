# ADR-0023: Tracking areas, title bar accessories and the page controller

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

Three pieces of AppKit's view-controller and view layer were still generated stubs:

- `NSTrackingArea`, the rectangle of a view that reports the pointer entering, leaving
  and moving inside it. AppKit evaluates every area of a window against the pointer and
  against the activity the area asks for (key window, active application, first
  responder), sends `mouseEntered`/`mouseExited`/`mouseMoved`/`cursorUpdate` to the owner,
  and asks views to rebuild their areas (`updateTrackingAreas`) when their geometry
  changes. SwiftUI's `.onHover` and `.onContinuousHover` are built on it. The port's
  backends deliver `mouseMoved` events but nothing matched them against views: the
  SwiftUI hover handlers were wired to `mouseEntered` messages that never came.
- `NSTitlebarAccessoryViewController`, a view the window places in its title bar beside
  the standard buttons and the title (`.leading`, `.trailing`, `.left`, `.right`) or in a
  band below the title bar and the toolbar (`.bottom`). On macOS the window server owns
  the title bar; here the title bar is the compositor's (X11 with server decorations, the
  Win32 system frame), the package's (Wayland client-side decorations, ADR-0015) or the
  content's (`fullSizeContentView`, where the package draws the buttons over the content).
- `NSPageController`, which pages through `arrangedObjects` with one view controller per
  page, cached by identifier, with animated transitions in three styles and a live
  transition driven by a two-finger horizontal scroll.

## Decision

### Tracking areas

`NSTrackingArea` is a plain object (rect, options, a weak owner, user info). `NSView`
keeps the areas added to it; the window does the matching (`NSWindow._evaluateTrackingAreas`,
NSWindow.swift):

- **When.** On every `mouseMoved` the backends send, on `mouseUp` (a drag just ended), on
  drags for the areas with `enabledDuringMouseDrag`, and without the pointer moving when
  the activity changes: the window becomes or resigns key, the application activates or
  deactivates, the first responder changes. A view whose frame, bounds, visibility or
  window changed marks itself; before the next evaluation (and at the next display, so a
  view that moved out from under a still pointer exits) the window runs
  `updateTrackingAreas()` on the marked views, which posts
  `didUpdateTrackingAreasNotification` after the subclass rebuilt its areas.
- **Where the pointer is.** The X11 backend turns `LeaveNotify` and the Win32 backend
  `WM_MOUSELEAVE` (asked for with `TrackMouseEvent` on each entry) into the same far-away
  `mouseMoved` the Wayland backend already sent when the pointer left the surface; the
  window reads that as "outside", so every area exits and the hover states of the chrome
  reset. The areas are matched by rectangle in window coordinates, clipped to the view's
  `visibleRect` (the part a scroll view hides does not track); `inVisibleRect` is the
  visible rect itself, so it follows the view and the scrolling without a rebuild. Hidden
  views exit their areas.
- **Activity.** `activeAlways`, `activeInActiveApp` (`NSApplication.isActive`),
  `activeInKeyWindow` and `activeWhenFirstResponder` (the view, a descendant, or the
  view controller whose view it is) are honoured; an area that names no scope behaves as
  `activeInKeyWindow` (AppKit raises). `assumeInside` starts the area inside, so the first
  event is the exit.
- **Delivery.** Exits are sent before entries. The events carry the area
  (`NSEvent.trackingArea`, and so its `userInfo`). The messages go to the owner when it is
  a responder (a view, a view controller, the window) and to the area's view otherwise;
  an `NSCursor` owner takes `mouseEntered`/`mouseExited` itself, which sets it when
  `setOnMouseEntered`. `mouseMoved` goes to the owners of the areas that asked for it and
  hold the pointer, whatever `acceptsMouseMovedEvents` says. `cursorUpdate` goes to the
  owner on entry; while any such area (or an `NSCursor`-owned one) holds the pointer the
  cursor rects stand back, and leaving it hands the cursor back to them. The window ends
  the `cursorUpdate` chain with the arrow, as AppKit's does.
- **SwiftUI.** The decoration container installs a tracking area in `updateTrackingAreas`
  for `.onHover` (entered/exited) and the new `.onContinuousHover(coordinateSpace:perform:)`
  (`HoverPhase.active(point)` on entry and every move, `.ended` on exit; the global space
  is the hosting view's, as `GeometryReader` reports it).

### Title bar accessories

The window keeps the accessory views in one more overlay root (`_NSTitlebarAccessoryHostView`,
NSTitlebarAccessoryViewController.swift): above the toolbar, below the standard buttons,
never a subview of the content view. One layout pass (`NSWindow._resolveTitlebarLayout`)
places the toolbar and every accessory:

- **Side accessories** (`.leading`, `.trailing`, `.left`, `.right`) go into the title row.
  Where the package draws the title band, that is the band: the 28-point band above the
  content under Wayland client-side decorations (drawn by `platformWindowDrawTitleBar`
  like the buttons) and the top 28 points of the content of a `fullSizeContentView`
  window (the Win32 custom frame). Under a server-side title bar (X11 with server
  decorations, the Win32 system frame, the host backend) they get a strip of their own
  under it, as tall as the tallest of them, taken out of the content area the way the
  toolbar band is: the frame grows by it with the top edge fixed, the content keeps its
  size. The strip is painted in the title-bar colour with a hairline under it, like the
  toolbar band, and its empty parts drag the window. Leading accessories stack outward
  after the standard buttons (or from the edge when there are none), trailing ones from
  the far edge; right to left mirrors leading and trailing while the buttons stay at the
  left, as on macOS; `.left` and `.right` are absolute. A unified toolbar that shares the
  row starts its items after the leading accessories and stops before the trailing ones.
- **Bottom accessories** stack under the toolbar (or under the title band when there is
  none), each full width and as tall as its view, in order. They come out of the frame
  like the toolbar band, except on a `fullSizeContentView` window where they overlay the
  content and `contentLayoutRect` excludes them along with the band.
- **Sizes.** With `automaticallyAdjustsSize` the view's `fittingSize` rules where it has
  one, else its frame; the window follows the view's frame changes
  (`frameDidChangeNotification`). `isHidden` takes the space away; `layoutAttribute`
  changes move the view. `fullScreenMinHeight` is stored (no full-screen tiling yet).
  The accessory's view takes the mouse where it is a control (`mouseDownCanMoveWindow`
  false) and drags the window otherwise.

### Page controller

`NSPageController` keeps the controller of the page on screen and a cache of
controllers per identifier (`pageController(_:identifierFor:)`); a controller not on
screen is reused for the next page, a new one comes from
`pageController(_:viewControllerForIdentifier:)`, gets `representedObject` and
`pageController(_:prepare:with:)`. Without a delegate (or when it does not answer
`identifierFor`, the generated default returns an empty identifier) the arranged objects
must be view controllers themselves. Page views are subviews of the controller's view,
framed by `pageController(_:frameFor:)` (default: the whole view).

- **Transitions** run on the port's animation machinery: a `CADisplayLink` on the Core
  Animation runtime, which every backend ticks from its frame timer and which tests drive
  with `CARuntime.now` and `CARuntime.tick()`. The incoming page is added, both pages are
  placed per the style and an eased progress, the outgoing page leaves at the end. The
  styles: `horizontalStrip` moves both pages side by side; `stackHistory` slides the new
  page in over the current one going forward and slides the top page out the way it came
  going back; `stackBook` turns the current page away revealing the next one going
  forward and brings the previous page in over it going back. Right to left mirrors the
  direction. `selectedIndex` changes at once; `selectedViewController` when the slide
  ends; a plain `selectedIndex` set shows the page without animation, `animator()` and
  the navigation methods animate. The keyboard focus held by an outgoing page moves to
  the incoming one.
- **Delegate order.** `prepare` when a page is readied, then `didTransitionTo` when the
  slide ends. `completeTransition()` settles the pages (the arrived page fills its frame);
  the delegate calls it from `didTransitionTo` after updating the content, and the
  controller calls it itself when the delegate does not.
- **Live transitions.** A horizontal scroll with phases (a two-finger swipe on a
  touchpad: the Win32 precision-touchpad pan, X11 and Wayland axis events with their
  sources) begins a live transition (`pageControllerWillStartLiveTransition`): the pages
  follow the fingers by the scroll's fraction of the width, the next or previous page is
  readied by the direction, and pulling against an edge resists at a quarter of the pull.
  When the fingers lift (`pageControllerDidEndLiveTransition`) the pages settle forward
  past the middle, else back. A wheel without phases pages one step per notch; `swipe`
  events (left: forward) and the Left and Right arrow keys page with an animation;
  `navigateForward:`, `navigateBack:` and `takeSelectedIndexFrom:` (a segmented
  control's selected segment, a control's integer value, a menu item's tag) are the
  standard actions.

### What is not done

- `NSView.addTrackingRect(_:owner:userData:assumeInside:)` and `removeTrackingRect(_:)`
  (the pre-10.5 API) stay stubs.
- `fullScreenMinHeight` is stored but there is no full-screen title bar hiding to apply
  it to; `preferredScrollEdgeEffectStyle` (macOS 26) stays a stub.
- The page controller takes no snapshot of the outgoing page: the real views slide, so a
  page that re-renders during a transition shows its new content at once.

## Consequences

- Hover effects, cursor changes per region and SwiftUI's hover modifiers work on every
  platform from the same mouse-move stream; cursor rects keep working as before.
- A window with accessories or a toolbar grows and shrinks through one band calculation
  (`_chromeBandHeight`), so `contentRect(forFrameRect:)`, `frameRect(forContentRect:)`,
  `contentLayoutRect` and the layer scene agree.
- Tests: `TrackingAreaTests` (option semantics against synthesized events, activity
  scopes, drags, cursor owners, the SwiftUI modifiers), `TitlebarAccessoryTests`
  (placement per attribute under a server-side title bar, a client-side band and a
  covered title bar, right to left, size following), `PageControllerTests` (navigation,
  caching, delegate order, the three styles, live paging, swipes and keys). The Layout
  Demo's Pages tab shows all three.
