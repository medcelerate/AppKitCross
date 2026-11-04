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

- Narrator reads HelloWindow's controls on Windows and the UI Automation tree shows them
  with the right control types; `tools/linux/run.sh` runs an accessibility bus under
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
- Limitations: the `org.a11y.atspi.Cache` interface is not served (clients that insist
  on it, as some versions of libatspi do for interface lists, fall back to the
  `GetInterfaces` method, which is served); AT-SPI text granularities (word, line) report
  the whole text; UIA text ranges carry no formatting attributes; structure changes are
  reported as "children invalidated" without the added or removed child; menus and menu
  items are not in the tree yet; `NSAccessibilityElement` (virtual elements for custom
  views) and custom rotors and actions are still stubs; the native Win32 menu bar is served by the system's own UIA proxy, whose ExpandCollapse
  does not open our menus (mouse and Alt do); and the Wayland bridge reports
  extents against the primary output's logical size because Wayland has no global
  coordinates.
