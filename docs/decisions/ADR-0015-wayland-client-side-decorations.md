# ADR-0015: Client-side window decorations on Wayland

Date: 2026-11-10. Status: accepted.

## Context

Wayland has no window manager that frames every client: a toplevel is a bare surface
unless the compositor offers server-side decorations through `xdg-decoration`
(`zxdg_decoration_manager_v1`), and the most common desktop compositor, GNOME's Mutter,
does not offer them at all. KDE, sway and the other wlroots compositors do. Until now the
Wayland backend asked for a server-side frame and otherwise showed nothing: no title, no
close button, no way to move or resize the window with the pointer.

AppKit's own model has the frame drawn by the window server with the window's title and
standard buttons; applications see the frame only through `frameRect(forContentRect:)`,
`standardWindowButton(_:)` and `NSWindow.StyleMask`. The port already draws the standard
buttons itself for windows whose content covers the title bar (`fullSizeContentView`,
`NSWindowButtons.swift`), because no platform frame supplies them there.

## Decision

The Wayland window negotiates `xdg-decoration` and takes the compositor's answer; without
the protocol, or when the answer is client side, the package decorates the window itself.
The negotiation and all geometry are in one platform-neutral value type,
`ClientSideDecorationLayout` (`Platform/ClientSideDecoration.swift`), so the rules are
testable on every platform; the Wayland window feeds it its style mask, chrome, configure
states and pointer positions.

- **Mode.** Titled windows ask for a server-side frame (`APPKITWIN_WAYLAND_DECORATIONS=
  client|server` overrides the request, for testing on compositors that would grant one).
  `.server` when granted, `.client` otherwise and always without the protocol; `.none`
  for borderless windows and `nonactivatingPanel` pop-ups (menus), which get no frame.
- **Surface.** In client mode the surface is the frame plus a 24-point transparent shadow
  margin on every side. `xdg_surface.set_window_geometry` reports the frame, so the
  compositor sizes, places, tiles and maximises the window by its visible rectangle and
  its configure sizes are frame sizes. The opaque region is the frame less its rounded
  corners; the input region is the frame widened by 10 points into the shadow where it
  resizes. Maximised, tiled and full-screen states drop the margin and the corners (the
  frame fills its slot); full screen drops the band too.
- **Frame.** AppKit's 28-point title band above the content, so `frameRect(forContentRect:)`
  and `contentRect(forFrameRect:)` differ by the band exactly as on macOS and the window's
  coordinates have the content at the origin and the band above it (where macOS puts its
  title bar). With `fullSizeContentView` the band is 0 and the content reaches the top:
  the window's overlay buttons and its draggable top band from PR #16 apply unchanged.
- **Drawing.** The core paints the band: `PlatformWindow.hasClientSideTitleBar` tells
  `NSWindow` to show its standard buttons (the same `_NSWindowButtonsView` as for
  `fullSizeContentView`, laid out at the top of the frame instead of the content) and to
  answer `platformWindowDrawTitleBar(into:dirtyRect:)` with a flat bar in the window's
  effective appearance (light or dark, key or inactive, the window background when
  `titlebarAppearsTransparent`), the title centred in `titleBarFont`, and the buttons.
  The backend paints what is outside the content and the band: the shadow (nested rounded
  rectangles whose opacity rises towards the frame, stronger for the key window) and a
  hairline border inside the frame. Everything is rasterised at the backing scale.
- **Input.** The layout classifies each pointer position: a resize handle (5 points inside
  the frame edge, 10 outside, corners 18 points wide) starts `xdg_toplevel.resize` with
  the matching edge and shows the matching cursor (`ns-resize`, `nwse-resize`, …, from the
  cursor theme, overriding the core's cursor while hovering); the band asks the window's
  `platformWindowHitTest`, which says `.caption` except on a button, and a caption press
  starts `xdg_toplevel.move`, a double click calls `platformWindowTitleBarDoubleClicked`
  (`performZoom:`); a button press is dispatched as an ordinary mouse event, so the
  existing target/action wiring to `performClose:`, `performMiniaturize:` and
  `performZoom:` runs. `isMovableByWindowBackground` and the `fullSizeContentView` drag
  band go the same way, which they did not on Wayland before.
- **Key state.** The compositor's `activated` configure state makes the window key as
  keyboard focus does, so the band and buttons show the active look on seats without a
  keyboard (the headless sway in the container) and the inactive look when the user
  switches windows.

X11 is unchanged: its window managers always frame top-level windows. Windows keeps the
DWM frame and its custom frame for `fullSizeContentView`.

## Consequences

- Under Mutter and other compositors without `xdg-decoration`, titled windows now have a
  title, buttons, a shadow, moving and resizing. Under sway and KDE nothing changes unless
  the compositor answers client side (or the override forces it).
- `NSWindow.frame` on Wayland includes the band in client mode, as it does on macOS, so
  code that computes content sizes from frames through the AppKit conversions stays
  right; code that assumed frame == content on Wayland (none in the package) would not.
- The shadow costs a 24-point ring of ARGB pixels around every decorated window and a
  full repaint when the key state or the decoration mode changes; the content area keeps
  its partial damage.
- Not done: a `wp_viewporter`/fractional-scale path (the band is rasterised at the integer
  buffer scale like the content), the `cursor-shape-v1` protocol (cursors come from the
  XCursor theme), `xdg_toplevel.show_window_menu` on a right click of the band, and
  `set_minimized` from the band's button on compositors that have no way to restore
  (already the case for `miniaturize()`).
- Tests: `ClientSideDecorationTests` cover the mode table, the geometry the compositor is
  told, hit-testing of band, edges and corners, the window's buttons moving into the band
  and the band's drawing; `tools/linux/run-wayland.sh` runs HelloWindow with the override
  under headless sway, screenshots it, and checks that a `resize set` through the
  compositor lands on the frame size sway reports.
