# Drawing

Custom drawing and a freehand sketch canvas in one AppKit window, same source on every platform.

What it demonstrates:

- An `NSView` subclass overriding `draw(_:)`: `NSBezierPath` fills and strokes (a star, a
  dashed Bézier curve, a thick ring), a linear gradient painted as strips (`NSGradient` is not
  ported yet), string drawing with attributes at a point and wrapped in a rect, and an
  `NSImage` built offscreen with `lockFocus` drawn opaque, scaled and with a fraction.
- A sketch canvas tracking `mouseDown`, `mouseDragged` and `mouseUp`, with a colour pop-up
  and a width slider.
- Undo and redo kept in two stroke stacks on the view, wired to Edit > Undo (⌘Z), Redo (⇧⌘Z)
  and Clear (⌘K) and to buttons that enable and disable with the stacks. `UndoManager` is
  not in swift-corelibs-foundation, so the port has no `NSResponder.undoManager`; the stacks
  stand in for it.
- Export to PNG through `bitmapImageRepForCachingDisplay`, `cacheDisplay(in:to:)` and
  `NSBitmapImageRep.representation(using: .png)`, with `NSSavePanel` choosing the file.

Run it:

```bash
swift run Drawing
swift run Drawing --export sketch.png   # writes the canvas and exits
```
