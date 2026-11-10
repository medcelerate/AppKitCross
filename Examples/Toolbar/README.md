# Toolbar

An AppKit window with an `NSToolbar` and an `NSStatusItem` (ADR-0018).

What it demonstrates:

- `NSToolbar` with a delegate: image items (Back/Forward are navigational), an
  `NSToolbarItemGroup` drawn as a segmented control, an `NSMenuToolbarItem` that drops a
  menu, an `NSSearchToolbarItem`, selectable Edit/Preview items with the selection
  highlight, and the standard Customize item.
- Validation: `NSToolbarItemValidation` on the delegate disables Forward until Back was
  clicked (`validateVisibleItems()`, also run when the window becomes key).
- Overflow: narrow the window and the lowest-priority items move into the » menu at the
  trailing edge (Preview goes first, Edit stays).
- Customization: `allowsUserCustomization` with the Customize Toolbar… sheet (add and
  remove items, display mode, size), `autosavesConfiguration` to UserDefaults under
  AppKit's `NSToolbar Configuration <identifier>` key.
- `NSWindow.toolbarStyle` and `NSToolbar.displayMode` from the pop-ups; the "content
  covers the title bar" checkbox switches `.fullSizeContentView`, where the unified
  styles place the toolbar in the title band next to the window buttons.
- An `NSStatusItem` with an image, a tool tip and a menu: the Windows notification area
  (right-click or left-click for the menu, hover for the tool tip), a StatusNotifierItem
  on Linux desktops with a tray, the host backend's registry elsewhere.

Run it:

```bash
swift run Toolbar
```
