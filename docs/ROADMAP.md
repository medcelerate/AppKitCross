# Roadmap

Milestones are ordered so that each one produces something runnable. "Done" criteria
are concrete and testable.

## M0: Foundation (this milestone)

- [x] Architecture and decision records.
- [x] Full public API inventory extracted from the macOS SDK (`api-inventory/`).
- [x] Stub generator with coverage report (`tools/apigen`).
- [x] Package layout that builds on macOS (host) and Windows.
- [ ] CI: macOS host build + test, Windows build (GitHub Actions `windows-latest` with
      the swift.org toolchain).

## M1: Open a window and draw

Done when `swift run HelloWindow` on Windows shows a resizable, DPI-aware window whose
custom `NSView` subclass draws filled/stroked paths and text via `draw(_:)`, closes
cleanly, and `NSApplicationDelegate` lifecycle callbacks fire in AppKit order.

Status (2026-10-28): HelloWindow builds with Swift 6.4.1 on Windows 11 and runs: window
with title and standard frame, Direct2D drawing of the sample (grid, rounded rect, circle,
dashed curve), mouse clicks dispatched to the view in AppKit coordinates, key events,
programmatic resize with clean repaint, close through `NSWindow.close()` with app
termination. The core is covered by `Tests/AppKitTests` on the macOS host backend.
Live drag-resize is verified too. Not yet done for M1: text drawing (`NSFont`,
`NSString.draw`, DirectWrite through the CD2D shim) and DPI-change verification across
monitors.

- `NSApplication` run loop over the Win32 message loop; `NSApp`, `NSApplicationMain`
  equivalents; `applicationDidFinishLaunching`, `applicationShouldTerminate`,
  `applicationWillTerminate`.
- `NSWindow`: creation with `styleMask`, `contentView`, `title`, `frame`/`setFrame`,
  `makeKeyAndOrderFront`, `close`, `delegate` resize/close callbacks, `backingScaleFactor`,
  `convertToScreen`/`convertFromScreen`.
- `NSScreen`: `main`, `screens`, `frame`, `visibleFrame`, `backingScaleFactor`.
- `NSView`: hierarchy, `frame`/`bounds`, `isFlipped`, `needsDisplay`/`setNeedsDisplay(_:)`,
  `draw(_:)`, `hitTest`, `convert(_:to:)`, autoresizing masks.
- `NSResponder` chain and `NSEvent` for mouse/keyboard with correct AppKit coordinates.
- `NSGraphicsContext.current` bridging to a Direct2D-backed `CGContext`.
- `CoreGraphics` (Windows): `CGContext` fill/stroke/clip/transform/text, `CGPath`,
  `CGColor`, `CGColorSpace` (sRGB only), `CGImage` from raw bytes.
- `NSColor` (sRGB + system colors), `NSBezierPath`, `NSFont` minimal, `NSString.draw(at:)`.

## M2: Controls and text

`NSButton`, `NSTextField` (DirectWrite layout, IME via `ITextStoreACP`), `NSSlider`,
`NSImageView`, `NSScrollView`/`NSClipView`, `NSMenu`/`NSMenuItem` mapped to Win32 menus,
`NSCursor`, `NSPasteboard` over OLE clipboard, `NSAlert`, `NSOpenPanel`/`NSSavePanel`
over `IFileDialog`. Target/action and `NSControl` validation.

Status (2026-10-28): done and verified on Windows: `NSCell`/`NSControl`/`NSButton`
(push, checkbox, radio), `NSTextField` labels and inline single-line editing (no field
editor or IME yet), `NSMenu`/`NSMenuItem` on a Win32 menu bar with key equivalents and
validation, selector-free target/action (`NSSelectorHandling`, `setActionHandler`).
`NSScrollView`/`NSClipView`/`NSScroller` verified too. Done, awaiting Windows
verification: `NSImage`/`NSImageView`/`NSBitmapImageRep` (WIC decode/encode, Direct2D
bitmaps, `lockFocus` via a WIC render target), `NSSlider`, `NSCursor` with cursor rects.
Decision: Ctrl maps to `.command` and the Windows key to `.control`. Remaining:
`NSPasteboard` (OLE clipboard), `NSAlert` and modal sessions, open/save panels
(`IFileDialog`), field editor/IME for text fields.

## M3: DirectX 12 presentation

Replace the Direct2D HWND render target with a DXGI flip-model swap chain on a D3D12
device; D2D draws through `D3D11On12`. Per-monitor-v2 DPI, HDR surfaces, vsync and
`NSWindow.displaysWhenScreenProfileChanges` equivalents.

## M4: Core Animation

`QuartzCore` over DirectComposition / `Windows.UI.Composition`: `CALayer` tree,
implicit animations, `CATransaction`, `CADisplayLink`, layer-backed `NSView`
(`wantsLayer`, `updateLayer`). This is what SwiftUI's rendering needs.

## M5: Auto Layout and view controllers

`NSLayoutConstraint`, `NSLayoutAnchor`, `NSStackView` (Cassowary solver),
`NSViewController` / `NSWindowController` / `NSSplitViewController` / `NSTabViewController`.

## M6: SwiftUI hosting seam

`NSHostingView`, `NSHostingController`, `NSViewRepresentable`, `NSViewControllerRepresentable`,
`NSHostingSizingOptions`. At this point a SwiftUI implementation can be developed
against this AppKit.

## M3b: Frameless and translucent windows (after M3)

Requested test target: a borderless (or `.fullSizeContentView` + transparent title bar)
`NSWindow` with an `NSVisualEffectView`-style "liquid glass" backdrop. On Windows 11 that
maps to `WM_NCCALCSIZE` custom non-client handling (keeping DWM shadow/snap/resize),
`DwmExtendFrameIntoClientArea`, `DWMWA_SYSTEMBACKDROP_TYPE` (acrylic/mica) and
`DWMWA_WINDOW_CORNER_PREFERENCE`, with a premultiplied-alpha swap chain so the backdrop
shows through. Depends on M3's DXGI/DirectComposition presentation.

## M7: Metal translation layer (separate track)

Only needed for `MTKView`/`CAMetalLayer` and apps that use Metal directly. Options to
evaluate when we get here: a Swift `Metal` module over D3D12 (shader translation via
Metal Shading Language → DXIL is the hard part) or over Vulkan via SPIR-V. Not a
prerequisite for SwiftUI.

## M8: Linux backend

New `Platform/Linux` (Wayland/X11 + Vulkan + Skia or Cairo for `CGContext`). The core
and the SwiftUI layer should need no changes; that is the test of the architecture.

## Reference projects

- [SwiftOpenUI](https://github.com/codelynx/swiftopenui) (MIT): a SwiftUI reimplementation
  with a stable Win32 + Direct2D + DirectWrite backend in Swift (`BackendWin32`, `CWin32`).
  Reference for COM-from-Swift idioms and DirectWrite access (M1/M2), and a candidate
  SwiftUI core to host on this AppKit once the M6 seam exists. It bypasses AppKit entirely.

## Explicit non-goals

- Loading nibs, storyboards or `NSKeyedArchiver` archives produced on macOS.
- Running macOS binaries. This is a source-level port.
- Pixel-identical rendering of system controls. Controls follow Windows conventions
  where AppKit leaves appearance to the system.
