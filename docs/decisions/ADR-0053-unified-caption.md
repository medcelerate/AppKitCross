# ADR-0053: Opt-in unified caption on Windows

Date: 2026-11-21. Status: accepted, awaiting verification on the Windows PC.

## Context

A ported Mac app with a unified toolbar shows three strips on Windows: the system caption
(title, minimise, maximise, close), the Win32 menu bar (`HMENU`, ADR for M1), then the
package-drawn unified toolbar band of ADR-0018 with the window's title and subtitle, its
icon items, the search field and the title bar accessory (ADR-0023). The title appears
twice and the toolbar costs a third row. Seeing Sibyl (ADR-0050) on the PC, Evan asked for
the Apple-style window chrome, the band as the caption, "while keeping the menubar as
Windows expects it", and then that it be an option: the classic Windows caption stays the
default, and nothing changes for an app that does not opt in.

What the port already had: a `fullSizeContentView` window on Win32 uses a custom frame
(`WM_NCCALCSIZE` makes the client area the whole window, M3b), draws the Windows caption
buttons at the top-right of the band and reports them as `HTMINBUTTON`/`HTMAXBUTTON`/
`HTCLOSE` (ADR-0022, PR 46), drags the window from the band (`HTCAPTION`), and lays the
unified toolbar out between the traffic-light inset and the buttons. What it lacked: such a
window had no menu bar at all. `Win32WindowPolicy.carriesMenuBar` excludes it, because
user32 places the `HMENU` bar from the window style alone, above the client area and under
the system caption; with the client area covering the window (`WM_NCCALCSIZE`) the bar has
nowhere to be drawn, and keeping a non-client strip for it would put it *above* the band,
not under it. So the question was less the caption than the menu bar.

## Decision

### The opt-in

A window gets the unified caption when it follows the standard macOS recipe for a custom
unified title bar: `styleMask` contains `.fullSizeContentView` and
`titlebarAppearsTransparent` is true (`Win32WindowPolicy.captionMode(styleMask:chrome:switch:)`,
`PlatformWindowChrome.unifiedCaption`). Nothing new in the API: AppKit's own members, with
AppKit's own meaning. Everything else keeps the classic caption: a plain titled window, a
transparent title bar alone, and `fullSizeContentView` alone, which keeps exactly the
custom frame and buttons it had (and still no menu row), so no existing app changes.

The runtime switch `APPKITWIN_UNIFIED_CAPTION` (environment first, then the
`AppKitCrossUnifiedCaption` Info.plist key; `PlatformFeatureSwitch`) has two jobs:
`0` forces the classic caption on every window, recipe or not (comparison runs on the
PC); `1` maps SwiftUI scene windows onto the recipe. SwiftUI apps have no styleMask of
their own: with the switch on, `_AppRunner._windowGeometry` gives every `WindowGroup`,
`DocumentGroup` and `openWindow` window `.fullSizeContentView` and a transparent title bar,
its title still visible so the unified band shows it (as `.hiddenTitleBar` does, minus the
hidden title). The Settings scene keeps the classic caption whatever the switch: on
Windows it carries no menu bar either. The alternative, keying the mapping on
`.windowToolbarStyle(.unified)`, was rejected: `.automatic` already resolves to unified for
every SwiftUI window, so the style says nothing an app chose, and a toolbar attaches after
the window exists, too late to decide the frame without a visible restyle.

The backend decides availability: `PlatformBackend.usesUnifiedCaption(styleMask:chrome:)`
is false everywhere but Win32 (and the host backend when a test sets
`drawsUnifiedCaption`, which runs the Win32 policy on macOS and in the Linux container).
Linux is unchanged: the Wayland client-side decorations of ADR-0015 and the undecorated
X11 windows keep their band, their traffic lights and their key-equivalent-only menus.

### The band is the caption

Nothing in the band changes from ADR-0018, ADR-0022 and ADR-0023: the unified toolbar
overlays the top of the content area with the title and subtitle, the items, the search
field and the title bar accessories; the caption buttons sit in its top-right; the gaps
answer `HTCAPTION`, the buttons their own codes (snap layouts over maximise), a toolbar
item is client; double-click, right-click and the system menu are `DefWindowProc`'s through
those codes. One addition: a recipe window without a toolbar shows its title centred in
the 28-point title band (`_NSWindowButtonsView.titleText`), between the inset the buttons
take and the other edge, so a SwiftUI window without a `.toolbar` still has a title.

### The menu bar: a package-drawn row under the band

The `HMENU` bar cannot go under a client-area caption, so a recipe window that would carry
the application menu (titled, not a panel, not `utilityWindow`, an application with a
main menu) draws it itself: `_NSMenuBarRowView` (`Core/NSMenuBarRow.swift`), an overlay
root like the toolbar, 24 points tall, directly under the band (under the title band when
there is no toolbar, above any bottom title bar accessory), listing the main menu's
visible top-level items in the menu font. The row is a chrome band like the toolbar band
under a system title bar: `contentRect(forFrameRect:)` subtracts it, the frame grows by it
when it appears so the content keeps its size, and `contentLayoutRect` ends under it. The
content still extends under the toolbar band, as `fullSizeContentView` means.

It behaves as Windows' bar does, and keyboard access is identical in effect:

- A click on a title opens its menu hanging below the title, as the package's pop-up
  (`_NSMenuTracker`, NSMenuPopUp.swift); the pointer moving to another title switches
  menus; a click on the open title closes it; a click anywhere else closes it and lands.
- Alt+letter opens the menu whose title starts with that letter: the access key Windows
  takes when a title has no `&` marker, which AppKit titles never have. F10, or an Alt tap
  (Alt pressed and released with nothing in between), enters keyboard mode with the first
  title highlighted and the access keys underlined; Left and Right move, Down, Return or
  Space open, a letter opens its menu, Escape, F10 or a click leave. Left and Right at the
  root of an open menu move to the neighbouring menu, wrapping.
- Key equivalents (Ctrl+S) take the path they always took, `NSMenu.performKeyEquivalent`
  from `NSApplication.sendEvent`, before the row sees the key, so an item's Option-key
  equivalent wins over a mnemonic. The row's events are routed from `sendEvent` too
  (`_NSMenuBarRowView._handleApplicationEvent`), after the key equivalents.
- Alt+Space and Alt+F4 go to `DefWindowProc` on any Win32 window without the `HMENU` bar
  (`Win32WindowPolicy.passesSystemKeyToDefWindowProc`): the system menu and the close were
  lost on custom frames before, because every `WM_SYSKEYDOWN` became an AppKit event.
- The row follows `NSApplication.mainMenu`: it appears and goes with the menu (a frame
  change) and re-reads retitled items in place, cheaply, since AppKit rebuilds the menu on
  every item state change.
- Colours follow the appearance and the key state (`windowBackgroundColor`, a hairline
  under the row, the label colours, a translucent rounded highlight for the hovered, open
  or keyboard title). Everything is in points, so DPI changes cost nothing.

The row is not an accessibility element: the application's AXMenuBar (ADR-0013) already
stands for the main menu, and UI Automation reaches the menus through it.

### From the first PC round: the system menu and the live theme flip

- **Right-click on the band.** `DefWindowProc` shows the system menu for `HTCAPTION` on a
  right-button release, but it hit-tests the point again with its own geometry, which on
  a custom frame (the client area is the whole window) is `HTCLIENT`: nothing appeared.
  The window handles `WM_NCRBUTTONUP` for the codes the band answers
  (`Win32WindowPolicy.showsSystemMenuOnRightClick`): `TrackPopupMenu` of `GetSystemMenu`
  at the pointer with the states Windows gives its own frames (`systemMenuState`: Restore
  only when maximised, Move/Size/Maximize only when not and only on resizable windows,
  Minimize on miniaturizable ones), the chosen command posted as `WM_SYSCOMMAND`.
  `TrackPopupMenu` runs through a one-line C shim (`cd2d_track_popup_menu_command`,
  `TPM_RETURNCMD`), because the Swift WinSDK overlay imports its `BOOL` return as a
  one-byte `Bool`: the id was lost, and reading four bytes from it crashed (PC round 2).
  Without `TPM_RETURNCMD` the menu posts a `WM_COMMAND` with the SC_ id after the call has
  returned (PC round 3, through the run loop's `DispatchMessageWorker`), so a flag around
  the call cannot catch it; `WM_COMMAND` still forwards any id in the system range
  (`isSystemCommand`) as `WM_SYSCOMMAND`, since the port's menu ids never reach it.
- **The theme flipping while running.** `NSApplication.effectiveAppearance` reads the
  system live and the views resolve their dynamic colours when they draw, but nothing told
  them to draw again: after a flip only what Windows happened to repaint (the band, through
  the frame redraw) changed, and the menu row, the band's title and every SwiftUI tree kept
  their old colours (the hosting environment also pinned the colour scheme to light). Now
  the Win32 window's `WM_SETTINGCHANGE` calls `NSApplication._systemAppearanceDidChange()`
  (once per flip, whichever window reports first): every window without an appearance of
  its own runs `viewDidChangeEffectiveAppearance` down its content and overlay trees,
  marks every view for display (layer-hosted views keep their rasterised contents until
  marked) and repaints whole; `NSHostingView` answers it by refreshing its environment
  (`isDarkAppearance` now follows `effectiveAppearance`, so `@Environment(\.colorScheme)`
  is right on a dark system from the start) and re-rendering its tree. This fixes the
  classic windows' SwiftUI content too (Sibyl's Settings).

### The classic bar: dark theme and the flash while typing

Two findings from the Windows PC about the classic (default) caption, fixed here because
both are the menu bar's:

- **Dark theme.** user32 paints the `HMENU` bar from the light theme whatever the app
  theme, so a dark system showed a white bar with black text under a dark caption. Windows
  has no public dark menu bar; the port does what every dark Win32 app does
  (`Win32DarkMenu.swift`): the uxtheme ordinals `SetPreferredAppMode(AllowDark)` at
  start-up and `AllowDarkModeForWindow` per window, which make the pop-ups and the system
  menu follow the system theme, and the undocumented `WM_UAHDRAWMENU` /
  `WM_UAHDRAWMENUITEM` messages, with which user32 asks the window to paint the bar's
  background and each title itself: `Win32WindowPolicy.darkMenuBarTheme` (`#202020`,
  white text, grey disabled and inactive text, a lighter fill for the hovered title and
  the open one) through `menuBarItemColors(itemState:)`, and the one-pixel line user32
  leaves under the bar repainted after `WM_NCPAINT` / `WM_NCACTIVATE`. Only in the dark
  theme and only on a window carrying the bar: light bars stay user32's, pixel for pixel,
  and a unified caption has no `HMENU` bar (its row follows the appearance itself).
  `WM_SETTINGCHANGE` (the theme flipped while running) re-applies the caption's immersive
  dark-mode attribute, flushes the menu themes and repaints the frame.
- **The flash.** `NSApplication` rebuilds the platform menu on every item state change
  (Undo enabling on a key press), and `Win32MenuBar.apply` swapped the bar (`SetMenu`,
  `DrawMenuBar`) each time, repainting it from a blank surface: the bar flashed white
  while typing in TextEdit (the PC could not catch it at 25 ms sampling; a title change
  on its own repaints only the caption). Now `Win32WindowPolicy.menuBarChanged(from:to:)`
  compares what the bar shows (visible top-level titles, order, enabled state); when that
  is unchanged the installed bars stay and only their pop-ups are refilled
  (`DeleteMenu` + `AppendMenuW` behind the scenes, nothing visible: an open pop-up
  refreshes itself through `willOpen`), so nothing repaints.

### SwiftUI content under the band

`NSHostingView` lays its tree out inside the window's `contentLayoutRect` when it is the
content view of a `fullSizeContentView` window (`_layoutBounds`): the safe area SwiftUI
keeps clear of on macOS. Before, a `.hiddenTitleBar` window's content ran under the band.
Without a toolbar or accessory the rect is the whole content, so a bare `.hiddenTitleBar`
window still draws to the top edge, as on macOS.

## Consequences

- `ClassicMenuBarTests` (2): what counts as a change of the bar, and the dark theme's
  colours per item state. `UnifiedCaptionTests` (18): the system menu policy and states, a
  live light/dark/light flip repainting the row and re-rendering a hosted tree's colour
  scheme, the policy matrix (default classic, the recipe alone opts in,
  `0` overrides, `1` maps SwiftUI), the switch reading, the system keys, the band layout
  with the row (frame growth, `contentLayoutRect`, button positions, toolbar insets), the
  hit regions and their `WM_NCHITTEST` codes, opting in and out at run time, the row
  following the main menu (and a panel carrying none), the title in a toolbar-less band,
  clicking and hovering the titles, keyboard mode and arrows, mnemonics and the Alt tap, a
  pixel check of the highlight, and the SwiftUI mapping (window and Settings) with the
  hosting view laying out under the band. All run on the host backend standing in for
  Win32, on macOS and in the Linux container; the Win32 window itself compiles only in CI
  and is verified on the PC per the pull request's checklist.
- Open on the PC: the look of the row next to Windows 11's own menu bars (font size,
  highlight), whether the DWM snap layouts flyout still appears with the row present,
  Alt+Space through the queued `WM_SYSCHAR`, the dark bar (the `UAH` messages are
  undocumented; the struct offsets assume x64) and the flash being gone.
- Not done: the Windows underline-access-keys setting (the row underlines in keyboard
  mode only), menu bar accessibility of its own, a Linux in-window menu bar (X11 has no
  menu bar at all today; the row could serve there, a decision of its own).
- Follow-ups from the PC, not this ADR's: the classic `HMENU` bar has no keyboard access
  (Alt+F, F10 do nothing, also on main): the window procedure already hands every
  `WM_SYSKEYDOWN`/`WM_SYSKEYUP` to `DefWindowProc` when it carries the bar, so the suspects
  are the input method's `preTranslate` taking the keys before dispatch (ADR-0047) and the
  `WM_SYSCHAR` drain in `key()`; it needs the PC to settle. Sibyl's brand accessory shows
  its mark at 150 % but not at 100 %: on the host the accessory's layout is identical at
  1x and 2x (hosting view and mark 24 × 24 at the same place), so the difference is in
  drawing the template image at 1x on Windows, to be traced on the PC with the image path.
