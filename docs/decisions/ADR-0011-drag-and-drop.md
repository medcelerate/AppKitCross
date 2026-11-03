# ADR-0011: Drag and drop

Status: accepted (2026-11-03)

## Context

AppKit's drag and drop has two halves: a source starts an `NSDraggingSession` from a
view, and destinations that registered pasteboard types receive the
`NSDraggingDestination` messages while the pointer moves over them. On macOS the window
server runs the drag, so it works across applications and the source's event loop keeps
running. Windows (OLE drag and drop) and X11 (XDND) each have their own protocol, and
Wayland a third; all three deliver drags to and from other applications, each with a
different threading and event model.

SwiftUI's `onDrag`/`onDrop` are built on the same session, with `NSItemProvider` carrying
the data. Foundation on Windows and Linux has no `NSItemProvider`.

## Decision

- Drags within the application are tracked by AppKit itself, independent of the platform:
  `NSView.beginDraggingSession` creates the session (its pasteboard is filled from the
  dragging items' writers at once) and a tracker takes every mouse and key event from
  `NSApplication.sendEvent`, as the menu tracker does. It moves a borderless,
  non-activating drag image window, finds the destination under the pointer across the
  application's windows by walking the hit view's superviews for registered types, sends
  `draggingEntered`/`draggingUpdated`/`draggingExited`, performs the drop on release
  (`prepareForDragOperation`, `performDragOperation`, `concludeDragOperation`), tells every
  destination that saw the drag `draggingEnded`, and reports to the source. Escape cancels.
  Option, Control and Command limit the operation to copy, link and generic as on macOS.
- `beginDraggingSession` returns at once (AppKit blocks until the drag ends); the source
  hears the outcome through `draggingSession(_:endedAt:operation:)`.
- NSView provides overridable implementations of the destination messages with AppKit's
  defaults (`draggingUpdated` repeats what `draggingEntered` answered), so a subclass
  overrides only what it needs. Type matching accepts a dragged type that conforms to a
  registered one through a small conformance table, so AppKit does not depend on
  UniformTypeIdentifiers.
- Drags to and from other applications are the platform backends' half, to be added per
  platform behind the same tracker: Win32 OLE (`IDropSource`/`IDropTarget`/`IDataObject`
  through a C shim), X11 XDND, Wayland `wl_data_device`. Until then a drag that leaves the
  application's windows simply finds no destination.
- `NSItemProvider`, `NSItemProviderWriting` and `NSItemProviderReading` are provided in
  `Sources/AppKit/Support` where Foundation lacks them, with synchronous loading; SwiftUI
  always goes through the completion-handler API so the same code runs on Apple's
  asynchronous provider. A pasteboard item fed from a provider loads each representation
  on demand and waits (bounded) for the completion.

## Consequences

- Any AppKit or SwiftUI code that drags between its own views works today on every
  backend, and the test suite drives it with synthetic events.
- Cross-application drags, file drops from Explorer or a file manager, and drag images
  that match the platform's are per-platform work, verified on the Windows machine and in
  the Linux container as the backends land.
