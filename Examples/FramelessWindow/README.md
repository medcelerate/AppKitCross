# FramelessWindow

An AppKit app whose main window has no visible title bar.

What it demonstrates:

- `styleMask` with `.fullSizeContentView`, `titleVisibility = .hidden` and
  `titlebarAppearsTransparent`: the content covers the title bar and AppKit draws the
  standard close/minimize/zoom buttons over it (the port's own buttons on Windows and Linux).
- A non-opaque window (`isOpaque = false`, clear `backgroundColor`) whose content view paints
  a rounded card, so the window takes that shape; `hasShadow` keeps the shadow.
- `isMovableByWindowBackground`: drag anywhere on the card to move the window.
- `NSVisualEffectView` with `.behindWindow` blending: the system backdrop where the platform
  has one (DWM Mica/Acrylic on Windows 11, vibrancy on macOS), clipped to the card's corners
  through the view's layer. The "Backdrop" checkbox hides it to compare.
- Close, Minimize and Zoom buttons calling `performClose`, `performMiniaturize` and
  `performZoom`; a Window menu whose nil-target items reach the key window through the
  responder chain; `NSWindowDelegate` callbacks reporting resize, move, minimize and restore.
- A `.borderless` `NSPanel` (File > Borderless Panel, or `--panel`): no title bar and no
  buttons at all, its own rounded shape, moved by its background, closed by its button or Escape.

Run it:

```bash
swift run FramelessWindow
swift run FramelessWindow --panel   # opens the borderless panel too
```
