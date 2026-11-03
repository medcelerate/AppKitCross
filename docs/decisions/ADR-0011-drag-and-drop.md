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
- Drags to and from other applications are the platform backends' half (stage B,
  2026-11-03), behind one seam (`Platform/DragDrop.swift`). The destination logic the
  tracker uses (`_NSDragDestinationDriver`: find the registered view under a point, send
  entered/updated/exited, perform the drop, tell every destination it ended) is shared
  with drags the window system delivers to this application's windows through four
  `PlatformWindowOwner` methods, so a drag from another application behaves exactly like
  one from another view. Two shapes of backend:
  - Platforms that run drags themselves take over at `beginDrag`: OLE on Windows
    (`DoDragDrop` with an `IDataObject`/`IDropSource` in the CD2D shim, every window
    registered as an `IDropTarget`, the shell drag-image helper showing the pointer image)
    and the Wayland data device (`wl_data_source`, `start_drag` with an icon surface,
    `wl_data_offer` on enter). Their own windows receive the drag back through the same
    callbacks as foreign ones; the tracker hears the outcome through `PlatformDragSource`.
  - X11 keeps the pointer with the application (the implicit grab), so the tracker stays
    in charge and asks the backend about the window under the pointer only while none of
    this application's windows is there; the backend speaks XDND 5 (`XdndEnter`/
    `Position`/`Status`/`Drop`/`Finished`) to the topmost `XdndAware` window, found by
    walking the root's children beneath our own, and serves `XdndSelection`. Inbound,
    every window carries `XdndAware`.
  - Data moves as the platform expects: text as CF_UNICODETEXT / `text/plain;charset=utf-8`
    (also UTF8_STRING, STRING, TEXT on X11), files as CF_HDROP / `text/uri-list` with one
    pasteboard item per file, other AppKit types as a registered `AppKitWin:<type>` format
    or `application/x-appkitwin.<type>` MIME type. A foreign drag's representations load on
    demand through a pasteboard data provider (an X selection conversion, a Wayland pipe);
    a uri-list is read at enter so the item count is known.
  - The same machinery gives Linux its system clipboard: the X11 CLIPBOARD selection
    (TARGETS, TIMESTAMP, INCR transfers; the change count follows the owner and its
    TIMESTAMP) and the Wayland selection over the data device.
- `NSItemProvider`, `NSItemProviderWriting` and `NSItemProviderReading` are provided in
  `Sources/AppKit/Support` where Foundation lacks them, with synchronous loading; SwiftUI
  always goes through the completion-handler API so the same code runs on Apple's
  asynchronous provider. A pasteboard item fed from a provider loads each representation
  on demand and waits (bounded) for the completion.

## Consequences

- Any AppKit or SwiftUI code that drags between its own views works today on every
  backend, and the test suite drives it with synthetic events.
- Cross-application drags and file drops work on all three window systems. X11 is
  covered end to end in the container by `X11DragDropTests`, where a second X client on
  its own thread plays the other application (both directions), and `X11ClipboardTests`;
  Windows is verified by hand on the Windows machine (Explorer file drops, dragging text
  into other applications); Wayland is verified by reading only, since the headless sway
  in the container has no seat to drive a drag with.
- Limitations: `NSDraggingSession` promises, spring-loading and the `slideBack`
  animation are not provided; the X11 backend does not implement `XdndProxy`; on Wayland a
  drop's file list is read at enter and falls back to one item when the source answers
  only after the drop; OLE drags block `beginDraggingSession` until the drop (as AppKit
  does), with the frame clock and main queue serviced from a timer meanwhile.
