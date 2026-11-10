# ADR-0018: Toolbars and status items

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

AppKit's `NSToolbar` is part of the window frame: the window server draws it under the
title bar (or in the title bar for the unified styles), the window's frame grows by it
while the content keeps its size, items come from a delegate by identifier, the user can
customize and the configuration autosaves. `NSStatusItem` puts an icon in the menu bar's
status area with a button and a menu.

Neither Windows nor Linux has a window-frame toolbar: Win32 windows have a menu bar and a
client area; X11 and Wayland windows have whatever the window manager frames them with.
Both have a status area for applications, with their own protocols: the notification area
(`Shell_NotifyIcon`, icons and tool tips, click messages) and the StatusNotifierItem
D-Bus protocol used by KDE, waybar and GNOME's AppIndicator extension (an item object
with an icon pixmap, a tool tip and activation methods, registered with a watcher).

## Decision

### Toolbar placement

The toolbar is a view the package draws (`_NSToolbarView`, NSToolbarView.swift), an
overlay root of the window like the standard buttons from PR 16: above the content, below
the buttons, never a subview of the content view, so hosting views that manage their own
subviews never see it. Its items are drawn with the port's own views (`_NSToolbarItemButton`
for image items, the item's `view` for view items, `NSSegmentedControl` for groups,
`NSSearchField` for the search item), so Win32, X11, Wayland and the host backend show the
same toolbar.

- **Below the title bar** (titled windows whose content does not cover the title bar):
  the band comes out of the platform's content area. `contentRect(forFrameRect:)` subtracts
  it and `frameRect(forContentRect:)` adds it, so a window that gets a toolbar grows by
  the band with its top edge fixed and its content view keeps its size, as on macOS; the
  content view sits at the origin and the toolbar above it. The band is filled with the
  title-bar colour of the window's appearance and key state (the same colours as the
  client-side title band of ADR-0015), with a baseline separator at the bottom when
  `showsBaselineSeparator`. The empty band drags the window.
- **Over the content** (`fullSizeContentView`): the content keeps its full size and
  `contentLayoutRect` excludes the band. With the `.unified` and `.unifiedCompact` styles
  (and `.automatic`, which resolves to unified for such windows and to expanded for the
  others) the item row shares the top 52 or 38 points with the standard buttons, starting
  after them; `.expanded` and `.preference` keep the 28-point title band above the row.
  The band is not painted when `titlebarAppearsTransparent`, so the content shows through
  as it does under the buttons.
- **Styles and modes.** `displayMode` picks icons, labels or both (`.default` is icon and
  label for expanded, icon only for unified), `sizeMode` picks 24- or 18-point icons;
  the band's height follows (56/38/28 points expanded, 52 unified, 38 compact).
- **Layout.** Navigational items lead; `centeredItemIdentifiers` sit in the middle when no
  flexible space decides the layout; a tracking separator pins the items before it to the
  split view's leading pane. When the row does not fit, the items with the lowest
  `visibilityPriority` (the rightmost among equals) leave for the chevron at the trailing
  edge, whose menu lists their menu forms (a submenu for groups and menu items); the
  items know this through `isVisible` and `visibleItems`.
- **Customization.** `runCustomizationPalette(_:)` opens a sheet (`beginSheet`) with the
  allowed items not in the toolbar in a pop-up and an Add button, the removable items and
  a Remove button, the display mode, the size mode, Use Default Set and Done; the
  delegate's `canBeInsertedAt` and `immovableItemIdentifiers` are honoured. There is no
  dragging. `autosavesConfiguration` writes AppKit's dictionary ("TB Item Identifiers",
  "TB Display Mode", "TB Size Mode", "TB Is Shown") under "NSToolbar Configuration
  <identifier>" in `UserDefaults.standard` and reads it back when the toolbar loads.
- **Validation.** `validate()` on an image item (or a view item whose view is a control)
  finds the target the way `sendAction` would (the explicit target, else the responder
  chain of the toolbar's window, the application, its delegate); nothing performing the
  action disables the item, a target adopting `NSToolbarItemValidation` decides, anything
  else enables it. `validateVisibleItems()` runs when the toolbar attaches, when the window
  becomes key and when its geometry changes. The standard items send AppKit's actions
  (`printDocument:`, `orderFrontColorPanel:`, `orderFrontFontPanel:`, `toggleSidebar:`,
  `toggleInspector:`, `runToolbarCustomizationPalette:`) and so are disabled until
  something in the chain performs them; cloud sharing has no service here and stays
  disabled.
- **Window.** `toolbar`, `toolbarStyle`, `toggleToolbarShown(_:)` and
  `runToolbarCustomizationPalette(_:)` are implemented; the window performs the last two
  as responder-chain actions so menu items with nil targets reach them. The toolbar view
  joins the window's accessibility tree as an `AXToolbar` with its items as buttons
  (ADR-0013) and the window's layer scene when the content is layer-hosted.
- **SwiftUI.** `.toolbar { ToolbarItem(placement:) { } }`, `ToolbarItemGroup`,
  `ToolbarItem(id:)` with `.toolbar(id:)` for customizable toolbars, `.toolbar(.hidden,
  for: .windowToolbar)` and the scene's `.windowToolbarStyle(_:)` build a window-level
  `NSToolbar` whose items host their content in `NSHostingView`s: navigation items lead,
  principal items are centred, the rest follow a flexible space.

### Status items

`NSStatusBar.system.statusItem(withLength:)` makes an `NSStatusItem` whose
`NSStatusBarButton` carries the title, image, tool tip, target and action. The item goes
to the platform through `PlatformStatusItemHost` / `PlatformStatusItem`
(Platform/StatusItem.swift): title, tool tip, the image rasterised at the main screen's
scale, visibility. The platform reports clicks with a screen position; the core sends
the button's action on a primary click, opens the menu (the package's own pop-up window,
NSMenuPopUp.swift, kept on the screen) when one is set, and opens it on a secondary
click too (an action instead when `sendAction(on:)` asked for right mouse ups), with
`NSApp.currentEvent` reporting the click. Visibility is remembered under the autosave
name as "NSStatusItem Visible <name>".

- **Windows:** one `NOTIFYICONDATA` per item on the backend's message window with
  `NOTIFYICON_VERSION_4`, an `HICON` made from the image's BGRA pixels (the application
  icon without one), the tool tip from the tool tip or the title, `NIN_SELECT` /
  `WM_LBUTTONDBLCLK` / `WM_CONTEXTMENU` as primary, double and secondary clicks at the
  pointer (the anchor Windows passes for keyboard selection and context menus). The
  message window is made the foreground window before the owner opens a menu and loses
  it when the user clicks elsewhere, which cancels the menu tracker, the documented
  way to keep a notification-area menu from staying open. Icons are added again on
  `TaskbarCreated`.
- **Linux:** one private session-bus connection serves each item as
  `/StatusNotifierItem` (then `/StatusNotifierItem2`, ...) with the
  `org.kde.StatusNotifierItem` properties (Category, Id, Title, Status, IconPixmap in
  ARGB32 network order, ToolTip, ItemIsMenu false, Menu "/NO_DBUSMENU"), Introspectable
  and Properties, registered with `org.kde.StatusNotifierWatcher` by object path (and
  again when a watcher appears later); `Activate` is the primary click and
  `SecondaryActivate` / `ContextMenu` the secondary one at the position the host sends
  in screen pixels (Wayland hosts send none; the menu then opens at the top-left of the
  first output). The connection is pumped from the X11 and Wayland poll loops like the
  AT-SPI bridge. There is no `com.canonical.dbusmenu` object, so GNOME's AppIndicator
  extension, which only opens dbusmenus on a right click, shows nothing there; KDE's
  tray and waybar call `ContextMenu`. `APPKITWIN_STATUS_NOTIFIER=0` keeps the
  application off the bus.
- **Host backend:** an in-process registry (`HostStatusItems`) whose items record what
  they would show and whose `click` hook delivers a user's click, for the tests.

## Consequences

- A toolbar costs a band of the window and an overlay repaint; `contentRect`/`frameRect`
  stay honest about it, so code converting sizes through the window's conversions is
  unaffected. Code that assumed the platform content area equals the content view's
  size (none in the package) would see the band.
- `NSSearchField` is the port's `NSTextField` with a rounded bezel and a placeholder; its
  own members (recents, the search menu) are still stubs.
- Not done: dragging in the customization palette, `NSToolbarItemGroup`'s collapsed
  representation (groups always expand to a segmented control), the sharing-service
  picker item, a dbusmenu for Linux trays that need one, custom `NSStatusItem.view`s
  (the platforms' status areas show icons and text only).
- Tests: `ToolbarTests` (delegate-driven items, insertion and removal with the
  notifications, selection, validation through the target and the chain, clicks, groups
  and menu items, overflow at a narrow width, the autosave round trip, the window's frame
  growing by the band and the unified overlay, a pixel check of the band under the title
  bar, the customization sheet, the accessibility tree), `StatusItemTests` (the button's
  state reaching the host item, clicks sending the action or opening the menu at the
  click, visibility under the autosave name, and on Linux with a session bus the
  StatusNotifierItem's properties and `Activate` over D-Bus), `SwiftUIToolbarTests`.
  `Examples/Toolbar` shows both; `tools/linux/run.sh` screenshots it under Xvfb.
