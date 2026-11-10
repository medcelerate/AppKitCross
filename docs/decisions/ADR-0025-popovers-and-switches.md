# ADR-0025: Popovers and switches

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

`NSPopover` shows a view controller in a rounded panel with an arrow pointing at a
rectangle of a view, on the preferred edge of that rectangle (or the opposite one when
the screen has no room), as a child window of the positioning view's window: it moves
with its parent, floats above it, closes on clicks outside it per its `behavior`, and can
be dragged off into a titled window (`isDetached`, or a window the delegate provides).
`NSSwitch` is the toggle-switch control: a track whose knob slides between off and on.

Neither window system has a popover. Windows has owned popup windows, X11 transients,
Wayland popups (`xdg_popup`, a menu's model: placed by the compositor from an anchor,
dismissed by a click outside under an input grab) and subsurfaces. ADR-0019 (attached
sheets, PR 43) already settled how a frameless window attaches to another on each
platform through `PlatformWindow.attachSheet(to:)`: a Win32 owned borderless popup without
`WS_EX_APPWINDOW`, an X11 transient with the EWMH dialog type and skip-taskbar states and
a user-specified position, a Wayland `wl_subsurface` of the parent's surface. Neither
toolkit draws a switch; Windows has a toggle switch in XAML only.

## Decision

### The popover window

A popover is `_NSPopoverWindow`: a borderless `NSWindow` that can become key (its content
may hold text fields), never main, transparent (`isOpaque` false, a clear background) with
the platform's shadow, at the floating level. It is attached to the positioning view's
window through the same `attachSheet(to:)` seam as a sheet and added as a child window
(`addChildWindow`), so the parent closing closes it and the parent's `didMove`/`didResize`
notifications re-place it. The platform files of PR 43 (`Backend.swift`, `HostBackend`,
`Win32Window`, `LinuxWindow`, `WaylandWindow`) are taken over verbatim here so that
either branch merges cleanly whichever lands first; the sheet core of PR 43 is not
needed by popovers and is not included.

- **Drawing.** `_NSPopoverFrameView` is the window's content view: it draws the body (a
  6-point rounded rectangle) and the arrow (22 points wide, 11 high) as one outline,
  filled with `windowBackgroundColor` and stroked with `separatorColor`, under the
  window's appearance (`NSPopover.appearance`, else the positioning view's effective
  appearance: a vibrant appearance lets a little through where the platform composites
  alpha, `.vibrantDark` gives the HUD look, `.darkAqua` a solid dark body). The content
  view controller's view fills the body. Around the outline the window is transparent
  where the window system composites alpha (DirectComposition, Wayland, the host backend);
  a plain X11 window has the default visual and no alpha, so there the frame view paints
  the surround with the parent window's background colour (`PlatformWindow.
  supportsTransparency`, new in the seam, false for `LinuxWindow`). The shadow is the
  platform's: DWM on Windows, the compositor on X11; Wayland subsurfaces have none (the
  stroke gives the edge).
- **Placement** (`_NSPopoverPlacement`, pure and tested): the preferred edge is named in
  the positioning view's coordinates (a flipped view's `.maxY` is its bottom), converted to
  a screen-space side. The popover sits on that side of the positioning rect (the view's
  bounds when the rect is empty), centred on it, if the screen's visible frame has room
  for the body and the arrow there; else on the opposite side; else beside it; else on
  the side with the most room. It then slides along the edge to stay on screen and the
  arrow stays over the anchor's middle, stopped short of the rounded corners.
- **Behaviour.** `NSApplication.sendEvent` tells the shown popovers about every mouse down
  (`NSPopover._noteEvent`), after the menu and combo-box trackers and before the event is
  dispatched, so the click still reaches what is under it. `.transient` closes on a click
  in any window but its own (and popovers opened from inside it) or on no window at all;
  `.semitransient` closes on a click in the window that holds the positioning view;
  `.applicationDefined` only through `close()`/`performClose(_:)`. Closing by a click goes
  through `performClose`, so `popoverShouldClose` can refuse (the generator config now
  defaults that optional method to true, as AppKit assumes). The popover's window
  resigning key (the parent's title bar clicked, another application) closes a transient
  popover and a semitransient one whose parent took the keyboard. Escape in the popover
  closes it unless the behaviour is application-defined. A shown popover is kept alive by
  the application until it closes, as a shown panel would be.
- **Keyboard.** The popover's window is made key. On Wayland the subsurface cannot take
  focus: keys arrive at the parent toplevel, and `NSWindow.sendEvent` hands key events to a
  child window that is key (the same route ADR-0019 uses for sheets).
- **Animation.** With `animates` the window starts 8 points into the anchor and eases out
  to its place on a `CADisplayLink` over `CARuntime.now` (`_NSPopoverPop`); `didShow` is
  posted when the slide ends. `NSPopover._animationDuration` (0 in tests) sets the length;
  closing is immediate.
- **Detaching.** Dragging the popover's background (its frame view; controls take the
  mouse themselves) past 4 points asks the delegate: with `popoverShouldDetach` true and no
  window from `detachableWindow(for:)`, the content view controller moves into a titled,
  closable, resizable window the framework makes at the body's place (shifted by the drag;
  the drag does not continue, the title bar does), `isDetached` becomes true, the popover
  stays shown and closing that window closes the popover; with a window from
  `detachableWindow(for:)` that window shows at the body's place and the popover closes
  with the `.detachToWindow` reason. `popoverDidDetach` follows either way.
- **Lifecycle.** `show(relativeTo:of:preferredEdge:)` posts `willShow`, attaches, places,
  orders in, makes key, then `didShow`; `close` posts `willClose` and `didClose` with the
  reason under `closeReasonUserInfoKey`. `show(relativeTo:)` on an `NSToolbarItem` anchors
  on the item's view or its drawn frame in the toolbar band. `contentSize` zero means the
  content view's frame (else its fitting size); setting it or `positioningRect` while
  shown re-places the window. `NSViewController.present(_:asPopoverRelativeTo:…)` makes a
  popover and `dismiss` closes it. Not done: the close animation, a scale in the pop,
  `hasFullSizeContent` (stored only).
- **Accessibility.** The popover's window is the `AXPopover` element (UIA Window, AT-SPI
  window) with the content tree under it; the popover object answers the element
  protocol for `NSAccessibility.post`.

### The switch

`NSSwitch` is an `NSControl` with an `NSActionCell` for target, action, tag and control
size, drawing itself: a pill track (regular 38×22, small 32×18, mini 26×15) filled with
`controlAccentColor` in proportion to the knob's position over a grey track, a white knob
with a soft edge that stretches while pressed, both per appearance. The knob position is
animated on a `CADisplayLink` over `CARuntime.now` (`NSSwitch._animationDuration`, 0 in
tests). A click (down and up inside) or Space toggles the state and sends the action;
dragging the knob past the middle sets the state on release and sends the action only if
it changed; setting `state` does neither, and `.mixed` reads as on. Right-to-left layout
mirrors the track. Accessibility: `AXCheckBox` with the `AXSwitch` subrole, the state as
the value, settable, press toggles — UIA shows a Button with the Toggle pattern, AT-SPI a
toggle button with the checkable/checked states.

### SwiftUI

`.toggleStyle(.switch)` puts a `_ToggleStyleKind` in the environment and `Toggle` then
builds a `_SwiftUISwitchRow` (the label, then an `NSSwitch` at the trailing edge, taking
the offered width) instead of the check-box `NSButton`. `.popover(isPresented:
attachmentAnchor:arrowEdge:content:)` and `.popover(item:…)` present a transient
`NSPopover` holding an `NSHostingView`, anchored on the modified view's frame in the
hosting view (`.rect` sources resolve against it, `.point` is a unit point in it), with
the arrow on the given edge of the popover (`.top`, the default, hangs it below the view;
leading/trailing follow the layout direction). Dismissing from inside or a click outside
clears the binding.

## Consequences

- Both PR 43 and this branch carry the same platform hunks; whichever merges second
  merges cleanly. The sheet core (`beginSheet` and friends) is unchanged here.
- `PlatformWindow.supportsTransparency` is a new seam member with a default of true; only
  X11 answers false. An ARGB visual for X11 under a compositing manager (and shaped
  windows for the rest) would remove the opaque surround and is left for later.
- On Wayland a popover is a subsurface of its parent: it cannot be placed outside the
  compositor's idea of the parent surface's stacking, has no shadow, and gets its keys
  through the parent. An `xdg_popup` would give compositor placement and a grab but
  would not take keyboard focus for text fields; the subsurface was chosen for parity
  with sheets.
- Layout Demo: a `popover` tab (`APPKITWIN_LAYOUT_TAB=popover`) with one button per
  behaviour and an `NSSwitch`; `APPKITWIN_POPOVER_OPEN=1` shows the transient popover on
  launch and the headless screenshot writes the popover's own window as
  `layout-popover-open-<platform>.png`. `tools/linux/compare.sh` renders the tab and an
  X screen capture with the popover open. `PopoverTests` (18 tests) cover placement,
  edge flipping, following the parent, the drawn arrow over transparency, the three
  behaviours with synthesized events, the delegate and notification order, keys through
  the parent, both detach paths, the pop animation on a fake clock, the view controller
  presentation, the switch's mouse, keyboard, drag, drawing and accessibility, and the
  SwiftUI toggle style and popover modifier.
