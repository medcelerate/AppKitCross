# ADR-0019: Attached sheets

Date: 2026-11-10. Status: accepted.

## Context

AppKit's sheets are document-modal dialogs attached to a window: the sheet has no title
bar of its own, slides out from under the parent's title bar (or its toolbar), sits centred
on the parent, moves and minimises with it, stays above it, has no entry of its own in the
window list, and blocks the parent's content from input until it ends. Alerts
(`NSAlert.beginSheetModal`), the open and save panels (`beginSheetModal(for:)`), SwiftUI's
`.sheet`, `.alert` and `.confirmationDialog`, the document architecture's close and save
prompts (ADR-0017) and the toolbar customization palette (ADR-0018) all present through
`NSWindow.beginSheet`.

Until now the port showed every sheet as an ordinary titled window parked at the top
centre of its parent: the parent stayed interactive, a second `beginSheet` showed a second
window instead of queueing, and the window system listed the sheet like any other window
(docs/ROADMAP.md: "sheets (presented as modal windows)").

The window systems differ in what an "attached" window is:

- **Win32** has owned windows: an owner keeps its owned windows above it, hides them when
  it is minimised and keeps them out of the taskbar (without `WS_EX_APPWINDOW`). It does
  not move them with the owner.
- **X11** has transient-for windows (`WM_TRANSIENT_FOR`): window managers stack them above
  the main window, iconify them with it and, with the EWMH dialog type and skip-taskbar
  state, leave them out of the task list. Decorations are removed with Motif hints. Nothing
  moves them with the main window; an override-redirect window would also escape the
  manager's iconification and focus handling, which a sheet needs.
- **Wayland** has two candidates. `xdg_popup` is positioned by the compositor relative to
  its parent and moves with it, but its model is a menu's: a grabbing popup is dismissed by
  a click outside it and needs the serial of a recent input event, a non-grabbing popup
  gets no keyboard focus, nested popups must chain, and compositors may slide or flip it to
  fit the output. A `wl_subsurface` is part of its parent's surface tree: placed by the
  client at an offset from the parent, composited above it, mapped and minimised with it,
  without any entry of its own, and the client receives its pointer events on its own
  `wl_surface`. Keyboard focus stays with the parent toplevel.

## Decision

Sheets become a core feature of `NSWindow` with one platform hook, and each window system
attaches the sheet with its native mechanism behind that hook.

### Core (`NSWindow`, `NSApplication`, `NSAlert`)

- `beginSheet(_:completionHandler:)` appends the sheet to the parent's `sheets`. The first
  sheet is presented at once; further sheets wait in the queue and are presented as the
  sheet before them ends, as on macOS. `attachedSheet` is the sheet presented now.
  `beginCriticalSheet(_:)` inserts at the front of the queue and presents at once, in front
  of a sheet already up. `willBeginSheetNotification` is posted when a sheet is presented,
  `didEndSheetNotification` when one ends.
- Presentation attaches the sheet to the parent through the platform hook, gives it the
  parent's position (see below), orders it front, makes it key and slides it in. The sheet
  keeps its own `styleMask` (so a titled sheet still `canBecomeKey`; a borderless one can
  while it is a sheet); the platform shows it without a frame, so its frame equals its
  content rect while attached.
- **Position.** The attachment line is the top of `contentLayoutRect` (below the title bar,
  and below the toolbar band on a window that has one), the sheet centred on it. The
  delegate's `window(_:willPositionSheet:using:)` receives that rect in window coordinates
  (origin at the attachment point, the sheet's width, height 0) and may move it. When the
  parent's frame changes (`platformWindowDidChangeFrame`: a drag, a resize, a monitor
  change) the parent re-places its presented sheets, which is what moves a sheet with its
  parent on Win32 and X11, where the window system does not.
- **Animation.** The sheet unrolls from the attachment line: its frame grows downwards from
  one point high to its full height over 0.25 s (ease-out) with the content view pinned to
  the top, and rolls back up over 0.2 s when it ends; a `CADisplayLink` on Core Animation's
  frame clock drives the steps (`CARuntime.now`, so tests use a fake clock). A window with
  `animationBehavior == .none`, or `NSWindow._sheetAnimationDuration == 0`, skips it; the
  duration defaults to 0 on the headless host backend (tests, the macOS host build), where
  nothing spins the run loop for frames.
- **Modality.** A window with an attached sheet is blocked: its `sendEvent` drops mouse
  events for its content and forwards key events to the attached sheet (that is how a sheet
  gets the keyboard on Wayland, where focus stays with the toplevel); `becomeKey` on it
  makes the sheet key instead; its close button refuses while the sheet is up
  (`platformWindowShouldClose`, `performClose`); closing it ends its sheets with `.cancel`.
  Escape ends a sheet with `.cancel` when no key equivalent (a Cancel button) took it and
  the sheet opted in (`_cancelsSheetOnEscape`: SwiftUI's `.sheet`, as on macOS; alerts and
  panels cancel through their buttons' Escape key equivalents).
- `endSheet(_:returnCode:)` removes the sheet from the queue, calls its completion handler
  with the code, slides it out and orders it out, re-attaches nothing, presents the next
  queued sheet or makes the parent key again. Closing or ordering out an attached sheet ends
  it with `.cancel`. `NSApplication.runModal(for:)` on a sheet runs its application-modal
  loop as before (the old `beginSheet` + `runModal` + `endSheet` pattern); the deprecated
  `NSApplication.endSheet(_:)` forwards to the sheet's parent.
- `NSAlert.beginSheetModal(for:)` begins its panel as a sheet of the window and ends it
  from its buttons; the open and save panels and SwiftUI go through `beginSheet` unchanged.
- Sheets the framework makes and nobody keeps (alert panels, SwiftUI sheets) are closed
  once their session ends (`_closesAfterSheetEnds`), so they do not linger hidden in the
  application's window list; and the application terminates after the last *visible*
  window closes, as in AppKit, so an ended sheet never keeps it running.

### Platform hook

`PlatformWindow.attachSheet(to:)` (Backend.swift) attaches a hidden window to a parent, or
detaches it with nil. While attached the window shows no frame of its own, is stacked above
the parent, hidden and minimised with it, and listed nowhere; `frameRect(forContentRect:)`
is the identity. The core sets the frame after attaching.

- **Host (macOS, tests).** Records the parent; the frame/content conversions become the
  identity. Tests read `HostWindow.sheetParent`.
- **Win32.** The owner is set with `GWLP_HWNDPARENT`, the style switches to a borderless
  popup (`WS_POPUP`, the shadow frame of ADR-0016 keeps the drop shadow, DWM border colour
  none) without `WS_EX_APPWINDOW`, so the taskbar and Alt-Tab skip it; the menu bar, which
  only titled windows carry, is removed. Detaching restores the style and clears the owner.
  Repositioning on `WM_MOVE`/`WM_SIZE` comes from the core.
- **X11.** `WM_TRANSIENT_FOR` to the parent, `_NET_WM_WINDOW_TYPE_DIALOG`,
  `_NET_WM_STATE_SKIP_TASKBAR` and `_NET_WM_STATE_SKIP_PAGER`, Motif hints for no
  decorations, user-specified position and a fixed size in the normal hints so the manager
  honours the core's placement. A managed transient rather than an override-redirect window,
  so the manager iconifies it with the parent and routes focus to it.
- **Wayland.** A `wl_subsurface` of the parent's surface rather than an `xdg_popup`, for the
  reasons above: the sheet is placed by `wl_subsurface.set_position` at the core's frame
  relative to the parent's surface (the parent's client-side shadow margin included),
  desynchronised so its own commits show as they come, above the parent's presentation
  subsurfaces. The window's `xdg_toplevel` role cannot be taken back from its `wl_surface`,
  so attaching creates a fresh surface for the subsurface (and detaching a fresh toplevel);
  attaching happens while the sheet is hidden. Pointer events arrive on the sheet's own
  surface; keyboard events arrive on the parent and the core forwards them. The parent's
  minimise, close and output changes apply to the subsurface as part of the surface tree.

## Consequences

- SwiftUI `.sheet`, `.alert`, `.confirmationDialog`, `NSAlert`, the file panels, the
  document prompts and the toolbar palette behave as on macOS without changes.
- The sheet's frame height is partial during the slide; `frame` readers see the window grow.
  `platformWindowDidChangeFrame` leaves the content view alone while a slide runs.
- A sheet is a real window on Win32 and X11 and a subsurface on Wayland, so Metal/Vulkan
  presentation surfaces inside a sheet work on all three (a subsurface of a subsurface).
- `NSApplication.beginSheet(_:modalFor:modalDelegate:didEnd:contextInfo:)` (selector-based,
  deprecated) stays unimplemented.
- Tests: `SheetTests` (attachment, position and the delegate hook, moving with the parent,
  input blocking and key forwarding, queueing and critical sheets, end-sheet return codes,
  Escape, `runModal(for:)`, the slide with a fake clock) and the SwiftUI sheet lifecycle
  test; the Linux container screenshots `Examples/Sheets`.
