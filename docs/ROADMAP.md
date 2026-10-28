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
(push, checkbox, radio; the Return button draws with the accent fill), `NSTextField`
labels and inline single-line editing (no field editor or IME yet), `NSMenu`/`NSMenuItem`
on a Win32 menu bar with key equivalents and validation (panels do not carry the bar),
selector-free target/action (`NSSelectorHandling`, `setActionHandler`),
`NSScrollView`/`NSClipView`/`NSScroller`, `NSImage`/`NSImageView`/`NSBitmapImageRep`
(WIC decode/encode, Direct2D bitmaps, `lockFocus` via a WIC render target), `NSSlider`,
`NSCursor` with cursor rects, `NSPasteboard` (CF_UNICODETEXT both ways), `NSAlert` and
modal sessions (`runModal`, disabled owner window). Done, awaiting Windows verification:
`NSOpenPanel`/`NSSavePanel` over `IFileDialog`. Decision: Ctrl maps to `.command` and
the Windows key to `.control`. Deferred: field editor/IME for text fields (M5 with the
text system).

## M3: DirectX 12 presentation

Replace the Direct2D HWND render target with a DXGI flip-model swap chain on a D3D12
device; D2D draws through `D3D11On12`. Per-monitor-v2 DPI, HDR surfaces, vsync and
`NSWindow.displaysWhenScreenProfileChanges` equivalents.

Status (2026-10-28): M3a merged (PR #1, built by the Windows session): windows present
through an `IDXGISwapChain1` (flip-sequential, 2 buffers, BGRA, vsync) with an
`ID2D1DeviceContext` drawing into a back-buffer `ID2D1Bitmap1`; D3D11 device with WARP
fallback and the HWND target as a last resort (`APPKITWIN_LEGACY_D2D=1` forces it);
device loss goes through the existing recreate path; `APPKITWIN_DXGI_DEBUG=1` prints
live DXGI objects. Swap-chain frames repaint the whole client area. Text antialiasing is
forced to grayscale on the swap chain so frames match the HWND target. Open: D3D12 +
D3D11On12 (only needed for Metal/M7 sharing), HDR, a real monitor-DPI-change test, and
DirectComposition hosting (M3b/M4b).

## M4: Core Animation

`QuartzCore` over DirectComposition / `Windows.UI.Composition`: `CALayer` tree,
implicit animations, `CATransaction`, `CADisplayLink`, layer-backed `NSView`
(`wantsLayer`, `updateLayer`). This is what SwiftUI's rendering needs.

Status (2026-10-28): the QuartzCore module is real and cross-platform (pure Swift over
CGContext, so the macOS test run covers it): `CALayer` tree with geometry, transforms
(`CATransform3D`), flipped geometry, masks, corner radius, borders, contents images,
shadows (offset only, no blur), hit testing and coordinate conversion; `CAShapeLayer`,
`CAGradientLayer` (banded), `CATextLayer` (drawn by AppKit's string drawing),
`CATransformLayer`, `CAScrollLayer`, `CAReplicatorLayer`, `CAConstraintLayoutManager`;
`CATransaction` with completion blocks; explicit and implicit animations (`CABasicAnimation`,
`CAKeyframeAnimation`, `CASpringAnimation`, `CAAnimationGroup`, `CATransition` as a fade)
with timing functions and fill modes; `CADisplayLink`. Presentation is a software
compositor: the layer tree is rendered into the window's CGContext on each frame; the
frame clock is a one-shot timer from the platform backend (`scheduleFrame`, WM_TIMER on
Windows). AppKit: `wantsLayer` makes the subtree layer-backed (views draw through
`CALayerDelegate`), `layer =` hosts a foreign tree, `animator()` plus `NSAnimationContext`
animate frame/alpha on layer-backed views, `displayLink(target:selector:)`. Not done:
DirectComposition visuals (the compositor stays in-process until M3's DXGI presentation
settles), group opacity (opacity applies per primitive), blurred shadows, `mask` alpha
masks (shape masks clip to the path), `CAMetalLayer`/`CAOpenGLLayer` presentation (M7).

## M5: Auto Layout and view controllers

`NSLayoutConstraint`, `NSLayoutAnchor`, `NSStackView` (Cassowary solver),
`NSViewController` / `NSWindowController` / `NSSplitViewController` / `NSTabViewController`.

Status (2026-10-28): done on macOS, awaiting Windows verification. A kiwi-style Cassowary
solver (`Layout/Cassowary.swift`) and a layout engine (`Layout/LayoutEngine.swift`) that
rebuilds the tableau per pass from the active constraints of a window's view tree, with
intrinsic content sizes through hugging / compression priorities, frames of views that
translate their autoresizing mask pinned, layout guides, `fittingSize`. Engine coordinates
are y-down so constants keep Apple's sign conventions across flipped and unflipped views.
`NSLayoutConstraint` (activation on the common ancestor, priorities, identifiers, the
visual format language with metrics, predicates, priorities and alignment options),
anchors (`NSLayoutXAxisAnchor`/`YAxisAnchor`/`Dimension`, `anchorWithOffset`, system
spacing), `NSLayoutGuide`, `layoutMarginsGuide`/`safeAreaLayoutGuide` (the bounds).
`NSStackView` generates constraints like AppKit's (gravity areas, fill, fillEqually,
fillProportionally, equalSpacing, equalCentering, custom spacing, edge insets, alignment,
hidden-view detaching with delegate calls). `NSViewController` (view loading, lifecycle
calls driven by the view entering/leaving a window, children, responder chain, modal
presentation, transitions), `NSWindowController` (lazy window loading, content view
controller), `NSSplitView` (manual layout with holding priorities, divider dragging and
cursors, collapse) + `NSSplitViewItem` + `NSSplitViewController` (sidebar/inspector
toggles), `NSTabView` (drawn tab strip, selection by click) + `NSTabViewItem` +
`NSTabViewController`. Not done: incremental solver updates (each pass rebuilds), RTL
leading/trailing, baselines beyond `baselineOffsetFromBottom`, sheets (presented as modal
windows), popovers, storyboards/nibs, `NSSplitViewItem` accessory view controllers.

## M6: SwiftUI hosting seam

`NSHostingView`, `NSHostingController`, `NSViewRepresentable`, `NSViewControllerRepresentable`,
`NSHostingSizingOptions`. At this point a SwiftUI implementation can be developed
against this AppKit.

Status (2026-10-28): done (`Sources/AppKit/Hosting/NSHostingSeam.swift`). Apple keeps these
types in SwiftUI and reaches AppKit through private hooks; here the hooks are the public
seam: content conforms to `NSHostingContent` and produces an `NSHostingRoot` (attach /
detach, `contentDidChange`, `environmentDidChange`, `sizeThatFits(proposal)`, `layout(in:)`,
immediate-mode `draw`, event handling, responder hit testing); the host side is
`NSHostingRootHost` (host view, window, backing layer, environment, invalidation, display
links, ideal-size changes). `NSHostingView` (layer-backed, flipped, intrinsic size from the
root, events forwarded to the root first), `NSHostingController` (`sizingOptions`,
`preferredContentSize`, `sizeThatFits(in:)`), `NSHostingSizingOptions`,
`NSViewRepresentable` / `NSViewControllerRepresentable` with coordinators and contexts, and
`NSViewRepresentableHostingRoot` as the reference root. A SwiftUI port makes its `View`
refine `NSHostingContent` and builds its render tree on `CALayer`/`NSView` through the host.

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
