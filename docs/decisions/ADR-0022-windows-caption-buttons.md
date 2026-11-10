# ADR-0022: Windows caption buttons for package-drawn window buttons

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

A `.fullSizeContentView` window has no system title bar on this port: the Win32 window
uses a custom frame (`WM_NCCALCSIZE` makes the client area the whole window, ADR for
M3b), so Windows draws no caption and no caption buttons; an undecorated X11 window has
none either, and a Wayland window without server-side decorations is decorated by the
package (ADR-0015). Since 2026-11-03 `NSWindow` has drawn AppKit's close / miniaturize /
zoom traffic lights over such content at the top-left on every platform
(`NSWindowButtons.swift`), and the unified toolbar of ADR-0018 starts its items after
them. On the Windows PC the round macOS buttons at the left look foreign: every other
window on the desktop has minimise, maximise and close at the top-right, and Windows 11
offers its snap layouts flyout when the pointer rests on the maximise button, which a
custom-drawn button only gets when the window reports it as `HTMAXBUTTON`.

Apple's API is silent about how the buttons look; applications reach them through
`standardWindowButton(_:)`, move or hide them, and expect the gaps between them to drag
the window. Whatever the look, those semantics must hold.

## Decision

The backend chooses the look through `PlatformBackend.windowButtonStyle`
(`PlatformWindowButtonStyle`): `.trafficLights` by default (macOS, X11, Wayland, the host
backend), `.caption` on Win32. The window and the toolbar read the style; nothing else
changes per platform.

### The caption style

- **Placement.** Minimise, maximise/restore and close, in that order, abut the trailing
  edge of the band at the top of the content (`_NSWindowButtonsView.captionWidth`,
  3 × 46 points; the band is 28 points tall, Windows' own buttons are 46 × 32 at 100 %).
  The traffic lights keep their place at the left (72 points, 12-point circles 20 apart).
- **Drawing.** Flat cells: no fill at rest, a 6 % fill of the text colour on hover and a
  lighter one while pressed; the close button fills `#C42B1C` (Windows' close red) with a
  white glyph when hovered or pressed. Glyphs are the 10-point Fluent shapes drawn as
  1-point strokes: a line, a square (two overlapping squares once the window is zoomed,
  the "restore" glyph), an X; 90 % of the text colour in a key window, 50 % in an
  inactive one, 36 % when the style mask disables the button (a non-resizable window still
  shows its maximise button, greyed, as Windows does).
- **Hover.** One button at a time (`_NSWindowButton.isHovered`), from the window's
  `mouseMoved` events; the traffic lights keep showing their glyphs for the whole group.
  A pointer that leaves the window ends the hover: the Win32 backend now arms
  `TrackMouseEvent` for the client area and the non-client buttons and reports
  `WM_MOUSELEAVE` / `WM_NCMOUSELEAVE` as a move far outside, the convention the Wayland
  backend already used.

### The hit test and Windows 11 snap layouts

`PlatformWindowHitRegion` gains `.closeButton`, `.miniaturizeButton` and `.zoomButton`:
`NSWindow.platformWindowHitTest` answers them for an enabled standard button under the
point (a disabled one is `.client`; the gaps around the buttons are `.caption`, so they
drag the window as on macOS). `Win32WindowPolicy.hitCode(for:)` maps them to `HTCLOSE`,
`HTMINBUTTON` and `HTMAXBUTTON` for `WM_NCHITTEST`, after the resize bands of a
resizable, non-maximised window, which keep priority as they do on Windows' own frames.
Reporting `HTMAXBUTTON` is what makes Windows 11 show the snap layouts flyout over the
maximise button, and the system cursor and accessibility hit testing name the buttons.

Reporting a non-client code changes the messages the window gets over the buttons:
`WM_NCMOUSEMOVE`, `WM_NCLBUTTONDOWN`, `WM_NCLBUTTONUP` (screen coordinates in `lParam`)
instead of the client ones. `DefWindowProc` would track a system caption button the frame
does not have, so the Win32 window turns a press on a button into the window's own
`leftMouseDown` after taking the capture; the drag and the release then arrive as client
messages like any control's, and `_NSWindowButton` fires `performClose:` /
`performMiniaturize:` / `performZoom:` on a release inside, exactly as a click delivered
from the client area does. `WM_NCMOUSEMOVE` over a button becomes a `mouseMoved`
(hover); over other non-client area (the 8-pixel resize band along the top of the
buttons) the pointer is reported as gone, so no button stays lit under a resize cursor.
Other backends ignore the new regions (their hit tests compare against `.caption`).

### `standardWindowButton(_:)` semantics

The row of buttons is now a flipped strip spanning the band, like AppKit's theme frame,
and only the buttons and the margin around them hit-test; the rest of the strip is
transparent to the toolbar and the content. An application that moves a button
(`setFrameOrigin`, `frame`: y from the top, as in AppKit's flipped frame) or resizes it
marks it as custom (`hasCustomFrame`) and the window leaves it there across relayouts; it
still takes clicks and still answers the backend as that button. Hidden buttons are
skipped. `NSWindow.standardWindowButton(_:for:)` returns a button in the backend's style.

### The unified toolbar

`_NSToolbarMetrics` keeps `leadingInset` for the traffic lights (72 + 4 points) and a
`trailingInset` for the caption buttons (138 + 4 points); the other is 8. So on Windows
the unified items start at the left of a covered title bar and the overflow chevron stops
before the buttons; on macOS and Linux nothing moves. `.expanded` and `.preference` keep
the 28-point title band above the row on every platform, with the buttons in it.

### Wayland and X11 keep the traffic lights

The Wayland client-side decorations (ADR-0015) and undecorated X11 windows keep the
macOS look. The desktops there do not agree on a convention (GNOME's header bars put a
close button at the right and often nothing else; KDE's Breeze puts all three at the
right; both let the user reorder them), and the band of ADR-0015 was designed and
screenshotted around the traffic lights. A Linux style that follows the desktop's
`org.gnome.desktop.wm.preferences button-layout` is possible on the same seam (a third
`PlatformWindowButtonStyle` case) and is left as a follow-up.

## Consequences

- On Windows, a `fullSizeContentView` window looks like a Windows window: caption buttons
  at the top-right, a red close, hover and pressed feedback, snap layouts on maximise.
  Macs keep their real buttons; Linux is unchanged (the Linux container renders the same
  examples as before, `docs/images`).
- `PlatformWindowHitRegion` has three more cases; a backend that switches over it
  exhaustively must add them (none does today). `PlatformBackend.windowButtonStyle` has
  a default, so other backends need nothing.
- Applications that assumed the close button at x = 12 of the content (none in the
  package) see it at the right on Windows, as their users expect; code that positions
  buttons itself works on every platform.
- The buttons are 28 points tall where Windows' are 32: they share the band of the
  unified toolbar and the title band of ADR-0015, which stay 28.
- Not done: the Windows 10 look (square glyphs are the same; the hover colours are
  close enough), a right-click system menu on the buttons, keyboard access (Alt+Space
  is the system menu, which a custom frame does not have), the Linux desktop-following
  style above.
