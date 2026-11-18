# ADR-0013: Accessibility

Status: accepted (2026-11-04)

## Context

AppKit exposes every view, window and the application to assistive technology through
the `NSAccessibility` protocol: a role, a label, a value, a frame, a parent and children,
focus, and actions such as press and increment. Controls answer these from their own
state, custom views override the methods or call the `setAccessibility...` setters, and
`NSAccessibility.post(element:notification:)` tells the system about changes. On macOS
the window server and the accessibility client (VoiceOver) do the rest.

Windows and Linux have their own accessibility stacks. Windows exposes applications to
Narrator, Accessibility Insights and `inspect.exe` through UI Automation: a window
answers `WM_GETOBJECT` with a COM provider tree (`IRawElementProviderSimple`,
`IRawElementProviderFragment`, a `FragmentRoot` on the HWND) whose elements implement
control patterns (Invoke, Toggle, Value, RangeValue, Selection, SelectionItem, Text) and
raise events with `UiaRaise*Event`. Linux desktops use AT-SPI2 over D-Bus: an
application embeds itself with the registry (`org.a11y.atspi.Socket.Embed`) and serves
objects implementing `org.a11y.atspi.Accessible`, `Component`, `Action`, `Value`,
`Text` and friends, emitting `org.a11y.atspi.Event.*` signals.

The port already declared the protocols on the right types (so source compiled) but
nothing reached the platform: screen readers saw empty windows.

## Decision

- The core owns the answers. `NSView` derives role, label, title, value, help, frame
  (screen coordinates), parent, children, enabled, focused and hidden from its state,
  and stores what the `setAccessibility...` methods set as overrides that win over the
  derived values. A plain `NSView` is not an element: its subviews stand in for it in
  the parent's children, as AppKit's ignored elements do. Controls are elements and
  give their roles (`NSButton` is AXButton/AXCheckBox/AXRadioButton labelled by its
  title, `NSTextField` AXStaticText or AXTextField, `NSTextView` AXTextArea, `NSSlider`
  AXSlider with its range, `NSPopUpButton` AXPopUpButton, `NSImageView` AXImage,
  `NSTableView` AXTable whose children are its AXRow views with AXCell children,
  `NSScrollView` AXScrollArea, `NSTabView` AXTabGroup, ...). Field editors are not
  elements; the text field they edit stands for them, including for focus.
  `NSWindow` is the root of a window's tree (AXWindow with its title and key state) and
  `NSApplication` lists the windows, key window first. `NSAccessibility` is hand-written
  so `post(element:notification:)` forwards to the seam.
- One platform seam (`Platform/Accessibility.swift`): `NSWindow` conforms to
  `PlatformAccessibilityProvider` and hands the platform window a snapshot tree of
  `PlatformAccessibilityElement` values (stable ids, role and subrole strings, label,
  value, frame, flags, actions, children) on request, performs actions, sets values,
  moves focus and selects rows by element id. The core tells the platform window about
  changes through `accessibilityDidChange` (focus, value, name, structure, selection),
  which the host backend records for tests and platforms without assistive technology
  ignore. A snapshot keeps the platform half free of AppKit calls per attribute: UI
  Automation and AT-SPI ask one property at a time, and the tree is small.
- SwiftUI's `accessibilityLabel`, `accessibilityValue`, `accessibilityHidden`,
  `accessibilityIdentifier` and `accessibilityHint` set the overrides on the content's
  backing AppKit views (the first view for label, value, identifier and hint; every view
  for hidden). `Text` is AXStaticText with its string as value; a `Button` with custom
  content is an AXButton labelled by the text inside it.
- Windows: a `CUIAutomation` C++ shim (declared in `Package.swift` on Windows only)
  keeps one COM provider per element id across snapshots, so clients see stable
  identities, and implements the fragment and fragment-root interfaces plus the Invoke,
  Toggle, Value, RangeValue, Selection, SelectionItem and Text patterns (text ranges over
  the element's value, with character, word and line units). `Win32Window` answers
  `WM_GETOBJECT` through `UiaReturnRawElementProvider`, pushes the flattened snapshot
  (frames converted to screen pixels, roles mapped to UIA control types) when the shim
  asks for a refresh, and raises focus, property, selection and structure events when
  `UiaClientsAreListening`. Providers opt into COM threading, so callbacks arrive on the
  UI thread (an STA). `WM_DESTROY` disconnects the providers.
- Linux: `AtspiBridge` (libdbus through a `CDBus` system library) finds the
  accessibility bus (`AT_SPI_BUS_ADDRESS`, then `org.a11y.Bus.GetAddress` on the session
  bus, then the X root window's `AT_SPI_BUS` property), embeds the application with the
  registry and serves `/org/a11y/atspi/accessible/root` (the application) and
  `/org/a11y/atspi/accessible/<id>` for every element with the Accessible, Application,
  Component, Action, Value, Text and EditableText interfaces, Properties and
  Introspectable. Both the X11 and the Wayland backends pump the connection from their
  poll loops and route window registration and changes to it; changes become
  `org.a11y.atspi.Event.Object` (`StateChanged`, `PropertyChange`, `TextChanged`,
  `ChildrenChanged`, `SelectionChanged`), `Event.Focus` and `Event.Window` signals.
  `APPKITWIN_ATSPI=0` keeps an application off the bus.

## Consequences

- On Windows the UI Automation tree shows HelloWindow's controls with the right control
  types and rectangles, every pattern acts on the window, and clients receive the focus,
  toggle, value and text events (`tools/windows/uia-events.ps1`); Narrator itself was not
  run by the remote session; `tools/linux/run.sh` runs an accessibility bus under
  Xvfb and `tools/linux/atspi-probe.py` walks HelloWindow's AT-SPI tree, presses the
  check box, sets the slider and the text field through D-Bus.
- Tests: `AccessibilityTests` (host backend) cover the tree, overrides, focus, actions,
  values, structure notifications, tables and the SwiftUI modifiers;
  `UIAutomationTests` drive the shim's COM objects without a window (Windows);
  `AtspiTests` play an assistive technology over a second bus connection (Linux with a
  bus). Each platform test skips where its platform is absent.
- Elements that are not views (the tabs of an `NSTabView`, the segments of an
  `NSSegmentedControl`) take part through an internal virtual-element protocol: the
  owning view lists them among its children with stable ids, and actions reach them by
  id. On Windows the core's change notifications are queued and raised on the next turn
  of the event loop, coalesced, so a snapshot is never pushed while the view hierarchy
  is mid-change or from inside a provider call.
- Limitations of the first version (several closed by the follow-ups below): the
  `org.a11y.atspi.Cache` interface is not served (clients that insist on it, as some
  versions of libatspi do for interface lists, fall back to the `GetInterfaces` method,
  which is served); AT-SPI text granularities (word, line) report the whole text; UIA
  text ranges carry no formatting attributes; custom rotors are stubs; the native Win32
  menu bar is served by the system's own UIA proxy, whose ExpandCollapse did not open our
  menus on the PC (mouse and Alt do).

## Follow-ups (2026-11-10)

- Menus. `NSMenu` and `NSMenuItem` are virtual elements: the main menu is an AXMenuBar
  of AXMenuBarItems, any other menu an AXMenu of AXMenuItems; an item reports its title,
  enabled state, check mark (`PlatformAccessibilityElement.checkedState`), key equivalent
  as drawn (`keyEquivalent`, "Ctrl+S") and its submenu as its child. Press (and pick)
  chooses an item of an open menu or opens its submenu, as a click would; on a closed item
  it performs the action, or opens the submenu as a menu of its own below the key
  window's content (the menu bar on platforms that draw none). A menu that is open on
  screen is live: the `_NSMenuWindow` the tracker shows it in is the AXMenu at the root
  of its window's tree, its drawn rows are the items with frames, the highlighted item is
  selected and focused (the tracker reports `.focus` on each highlight, so screen readers
  follow arrow keys), cancel on the menu closes it, and the window reports
  `.menuOpened`/`.menuClosed` (UIA MenuOpened/MenuClosed, AT-SPI showing/visible).
  `NSApplication.accessibilityChildren` lists the menu bar after the windows, and
  `NSApplication` serves it to backends through `PlatformAccessibilityApplication`.
- The native Win32 menu bar stays the system's. The HMENU lives in the non-client area;
  UI Automation already exposes it through the HWND's own MenuBar/MenuItem proxy (names,
  AcceleratorKey from the "\t" text, enabled and checked state, Invoke, ExpandCollapse),
  which Narrator, Accessibility Insights and every Win32 application use, and which
  merges with our client-area provider under the window. Mirroring the tree in our
  provider would put a second menu bar into the tree with no hit-test area of its own
  (the system owns the pixels) and two answers for the same items. What the proxy cannot
  do (open a menu whose ExpandCollapse it refuses) is a system-proxy limitation; the menus
  it opens are native popups, not our menu windows. On AT-SPI nothing draws a menu bar,
  so the bridge lists the AXMenuBar tree as a child of the application next to the windows
  (`atspi-probe.py` walks File/Edit/View/Help and View > Show Grid's check mark and key
  binding); pressing a bar item opens its menu as a live AXMenu window.
- Pop-up buttons: an `NSPopUpButton` is AXPopUpButton (UIA ComboBox) whose value is the
  selected title, expandable (`isExpanded`: UIA ExpandCollapse, AT-SPI expandable/expanded,
  has-popup); expand and press open the menu, collapse closes it; while it is open the
  pop-up's child is the open AXMenu of AXMenuItems with their on-screen frames, and press
  or pick on an item chooses it (selects it, sends the action, closes the menu). The
  pop-up reports `.childAdded`/`.childRemoved` naming the menu.
- SwiftUI parity: `Slider` labels its `NSSlider` with its label text and moves by its
  `step` (the slider's `altIncrementValue`, which `NSSlider`'s increment now prefers;
  values snap to the steps); `Picker` labels its pop-up or segmented control with the
  picker's label; `ProgressView` (drawn from shapes on main) is an AXProgressIndicator
  with its value in 0...total. Toggle and TextField already matched AppKit. The tree on
  macOS had the slider all along: the PC finding was a slider without a name (the
  Observable example's slider sits next to a separate Text), now named in the example
  with `.accessibilityLabel`. Stepper and DatePicker arrive with PR 44 over
  `NSStepper`/`NSDatePicker`, which answer their own roles. `NSButton.performClick` now
  flips the state after the highlight's display pass: a SwiftUI host re-rendering during
  that pass put a Toggle's old state back before the action read it (any press from the
  keyboard or assistive technology on a Toggle next to a Picker was lost).
- Frames on monitors of different scales: the window root carries `clientFrame` (the
  platform client area in the tree's screen points) and backends convert through
  `PlatformAccessibilityScreenMapping`: each frame relative to the client area, times the
  window's own backing scale, plus the client area's physical origin as the window system
  reports it (`ClientToScreen` on Win32, `XTranslateCoordinates` on X11). Nothing uses
  the primary monitor's height or scale, and a core frame lagging a DPI change cancels
  out. Win32 also invalidates the snapshot on WM_MOVE, WM_SIZE and WM_DPICHANGED: UIA
  clients keep providers across moves, and the rectangles were served from the old
  position (the likely cause of the PC's mismatch after moving a window to a monitor of
  another scale). The window root's rectangle is `GetWindowRect`. On Wayland, which has
  no global coordinates, extents are window-relative logical pixels (as GTK reports them
  there). `AccessibilityFollowUpTests` checks the conversion on the host backend with two
  displays at 100% and 200%.
- `NSAccessibilityElement` (hand-written now) is a virtual element custom views publish
  from `accessibilityChildren()`: role, subrole, label, title, value, help, identifier,
  enabled, selected, focused, min/max, index, custom actions, parent and children, with
  the frame either set in screen coordinates or given in the parent's space
  (`accessibilityFrameInParentSpace`, converted through the nearest view above it,
  nested elements adding their parents' offsets via `NSAccessibility.screenRect(fromView:rect:)`,
  implemented now with `screenPoint`). Actions from the platform call its
  `accessibilityPerform...` methods, which subclasses override; values call
  `setAccessibilityValue`. Virtual elements, menu items and custom actions are found by id
  through a weak registry, not only by walking the content view.
- Structure events name the child: adding, removing, hiding or showing a view sends
  `.childAdded(parent:child:)`/`.childRemoved(parent:child:)` after the `.structure`
  change, one per element the view contributes (itself, or the elements of an ignored
  container); UIA raises StructureChangeType_ChildAdded on the child and ChildRemoved on
  the parent with the child's runtime id, AT-SPI `ChildrenChanged` add/remove with the
  child and its index.
- Custom actions (`accessibilityCustomActions`, `NSAccessibilityCustomAction` hand-written
  with handler or target/selector): each has an id and a name in the snapshot. AT-SPI
  lists them after the role's actions in the Action interface (named actions are native
  there). UI Automation has no named-action pattern for providers — LegacyIAccessible has
  a single default action, already taken by the role's action — so each custom action is
  a Button child of its element named after the action whose Invoke performs it; the
  buttons cover their element's rectangle for screen-reader navigation but never answer
  a hit test (`CUIA_SKIP_HIT_TEST`).
- Still documented gaps: custom rotors, the AT-SPI Cache interface, AT-SPI text
  granularities finer than the whole text, formatting attributes on UIA text ranges.
