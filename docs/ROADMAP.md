# Roadmap

Milestones are ordered so that each one produces something runnable. "Done" criteria
are concrete and testable.

## Status at a glance (2026-11-04)

| Milestone | State |
|---|---|
| M0 Foundation | done |
| M1 Window and drawing | done, verified on Windows |
| M2 Controls and text | done, verified on Windows; field editor (NSText/NSTextView) on main, Win32 IME wiring with the Windows session; menu pop-ups (`NSMenu.popUp`, `popUpContextMenu`, `NSView.menu` on right click) and `NSPopUpButton` drawn by the package in non-activating windows; drag and drop (`beginDraggingSession`, `registerForDraggedTypes`, the NSDraggingDestination messages; ADR-0011) within the application and with other applications: OLE on Windows, XDND on X11 (tested end to end in the container against a second X client), the Wayland data device; the same selection machinery gives Linux its system clipboard; the Win32, X11 and Wayland event pumps service the main dispatch queue and RunLoop timers (DispatchQueue.main, @MainActor hops, Timer); `NSTableView` (view-based rows made for the visible rect and recycled on scroll, `NSTableColumn`/`NSTableHeaderView`/`NSTableHeaderCell`/`NSTableCellView`/`NSTableRowView`, header sorting through `sortDescriptorPrototype`, single/multiple selection with Cmd and Shift, arrows and Cmd-A, alternating rows, grid, column autoresizing, the header tiled by `NSScrollView`) and `NSSegmentedControl`/`NSSegmentedCell` (selectOne/selectAny/momentary tracking, labels and images, distributions, keyboard), both on the Layout Demo's Table tab |
| M3a DXGI swap chain | done, verified on Windows (PR #1) |
| M3b Frameless glass window | done, verified on Windows (PR #2: custom frame, DWM backdrop, DirectComposition swap chain) |
| M4 Core Animation | done, verified on Windows; native layer hosting (ADR-0005) with DirectComposition visuals in PR #5, verified on Windows |
| M5 Auto Layout and controllers | done, verified on Windows |
| M6 SwiftUI hosting seam | done (tests on macOS; nothing visible to verify) |
| M7 Metal | done, verified on an RTX 2070 (D3D12 backend merged in PR #3; MSL → HLSL translations compiled through the shim's HLSL compiler by `MetalD3D12DeviceTests` on Windows; `MTKView` presents through a flip-model DXGI composition swap chain on DirectComposition-hosted windows, with `MetalD3D12ParityTests` comparing clears, uploads, blits, fills and a presented frame against the reference device); Linux Vulkan backend (ADR-0012): device, queues, buffers, textures, blits, compute, render pipelines with depth, stencil and blending, and `MTKView` presentation on X11 and Wayland, all verified on lavapipe in the container (`tools/linux/run.sh` captures the Metal tab on both backends), with `MetalVulkanParityTests` comparing clears, uploads, blits, fills and a presented frame against the reference device byte for byte; swap-chain presentation is the follow-up |
| M8 Linux | done for X11 and Wayland: HelloWindow renders under Xvfb and under a headless sway (screenshots in README), 98/98 tests pass in the `swift:6.2-noble` container |
| M9 CoreText and the text system | done on all three platforms: CoreText module (ADR-0007) with Pango/HarfBuzz and DirectWrite engines (PR #7, DrawGlyphRun parity in PR #8); NSTextStorage/NSLayoutManager/NSTextContainer over CTTypesetter, NSTextView on them; 98/98 tests on macOS, Linux and Windows |
| M10 SwiftUI | first version on main (ADR-0010): View/ViewBuilder, State/Binding/ObservedObject/StateObject/Environment, node-tree runtime over the M6 hosting seam, proposal-based layout (stacks, Spacer, frame, padding), Text through the text system, AppKit-backed Button/TextField/Toggle/Slider/Image/ScrollView, shapes, decorations, App/WindowGroup, representables; 17 SwiftUI tests, HelloWindow `--swiftui` demo (Controls, Navigation and Presentation tabs); withAnimation/.animation/transitions and the animatable modifiers interpolate on the display link; NavigationStack/NavigationLink/navigationDestination with a path binding, TabView with tabItem/tag, Picker (segmented, radio group), sheets over NSWindow.beginSheet, alerts over NSAlert; GeometryReader, @AppStorage/@SceneStorage over UserDefaults, @FocusState with focused(_:) and onSubmit; Picker menu style over NSPopUpButton, Menu (nested, toggles, dividers), contextMenu; List selection (single/set bindings, mouse with Cmd/Shift, arrows, Cmd-A) over the list row model; Table (TableColumn, widths, selection, sortOrder) over `NSTableView` with cells hosted as SwiftUI views, segmented Picker and the TabView bar over `NSSegmentedControl`; onDrag/onDrop/DropDelegate over the AppKit dragging session; App scenes install the standard menu bar (app, File, Edit, View, Window, Help) with `.commands` (CommandMenu, CommandGroup before/after/replacing the standard placements, `.keyboardShortcut` on items) and a Settings scene opened from the app menu's Settings… (Cmd-,) |
| M12 Gestures | first version: `NSGestureRecognizer` with the click, pan, press, magnification and rotation recognizers (hand-written; the window feeds the hit view's and its ancestors' recognizers before the view, `delays*` withhold events while a recognizer tracks, delegate veto and `_actionHandler` for hosts), gesture `NSEvent`s (magnify, rotate, swipe, beginGesture/endGesture, smartMagnify) dispatched to the view under the pointer; SwiftUI `Gesture` with TapGesture, LongPressGesture, DragGesture, MagnifyGesture/MagnificationGesture, RotateGesture/RotationGesture, `onChanged`/`onEnded`/`map`, `.gesture`/`.highPriorityGesture`/`.simultaneousGesture`/`.onLongPressGesture`; platforms: Windows WM_GESTURE on touch screens (zoom, rotate, pan as precise scroll with phases, two-finger tap as smart magnify) and Ctrl+wheel as a magnify gesture (how precision touchpads report pinch), X11 XInput 2.4 pinch/swipe gestures (libXi, selected when the server speaks 2.4), Wayland `zwp_pointer_gestures_v1` pinch/swipe; HelloWindow: pinch resizes the canvas circle, rotate turns its needle, SwiftUI demo "Gestures" tab; `GestureRecognizerTests`, `SwiftUIGestureTests` |
| M13 Right-to-left layout | first version: `NSApplication.userInterfaceLayoutDirection` from `APPKITWIN_LAYOUT_DIRECTION`, the macOS defaults keys or the locale's language; views inherit the direction from their superview and the application (`NSView.userInterfaceLayoutDirection`); the layout engine resolves leading and trailing per item's direction, so Auto Layout, anchors, VFL, layout guides and `NSStackView` mirror; cells draw natural-aligned text flush right and the layout manager follows a paragraph's base writing direction; SwiftUI's `layoutDirection` environment (set from the hosting view's direction, or with `.environment(\.layoutDirection, .rightToLeft)`) mirrors HStack order, leading/trailing alignments in VStack, ZStack, frame, overlay and background, padding edges, and natural text alignment; verified on the Windows machine (Layout Demo form and the SwiftUI demo mirror); not yet mirrored: `NSTableView` column order (cells do align right), and views placed with absolute frames (as on macOS); `RightToLeftTests` |
| M10 Combine | done: `Sources/Combine` ports OpenCombine 0.14.0 under Apple's module name (ADR-0008), plus Merge/CombineLatest which upstream lacks; 17 Combine tests pass on macOS (Apple's Combine) and Linux (the port); Windows by reading only |
| M11 Accessibility | first version (ADR-0013): the NSAccessibility protocol answers on views, windows and the application (roles, labels, values, screen frames, parent/children with ignored plain views, focus, press/increment/decrement/showMenu actions, the `setAccessibility...` overrides, `NSAccessibility.post`), SwiftUI's accessibilityLabel/Value/Hidden/Identifier/Hint modifiers, one snapshot-tree seam to the platform window; Windows: UI Automation through the `CUIAutomation` shim (fragment providers on the HWND answering WM_GETOBJECT, Invoke/Toggle/Value/RangeValue/Selection/SelectionItem/Text patterns, focus/property/structure events), verified on the Windows machine with UI Automation clients (tree, rectangles on a 150% monitor, Invoke/Toggle/RangeValue/Value and SelectionItem on table rows all act; focus, toggle-state, value and text-changed events arrive while tabbing and typing, `tools/windows/uia-events.ps1`), Narrator itself not run (the remote session cannot hear it); tabs of an `NSTabView` and segments of an `NSSegmentedControl` are elements of their own (TabItem / radio-button items), the native Win32 menu bar's own UIA proxy refuses ExpandCollapse (menus open by mouse or Alt); Linux: AT-SPI2 over D-Bus (`AtspiBridge`: Accessible, Application, Component, Action, Value, Text, EditableText, events), `tools/linux/run.sh` runs an accessibility bus under Xvfb and `atspi-probe.py` walks and drives HelloWindow's tree; tests: 11 host-backend `AccessibilityTests`, `UIAutomationTests` (Windows) and `AtspiTests` (Linux with a bus), skipped elsewhere |
| M10 Third-party SwiftUI libraries | `Examples/LibraryCompat` (its own package, `tools/library-compat.sh`): Shimmer and ConfettiSwiftUI build and run on all three platforms, WrappingHStack and Defaults on the macOS host build (they assume UIKit elsewhere), swift-markdown-ui, SwiftUI-Introspect, SwiftUICharts and Nuke do not compile; verdicts and the gap list in [compatibility/swiftui-libraries.md](compatibility/swiftui-libraries.md) |
| M10 UniformTypeIdentifiers and ImageIO | done on macOS and Linux (ADR-0009): `UTType` over the SDK's generated core-type table with Apple's `dyn.*` encoding; `CGImageSource`/`CGImageDestination` over Cairo PNG (Linux) and WIC through CD2D (Windows, awaiting Windows verification); 12 tests pass against Apple's modules on macOS and against ours in the Linux container |
| M12 Audio | first version (ADR-0014): `AVFAudio` and `AVFoundation` under Apple's module names on Windows and Linux (macOS uses Apple's): `AVAudioFormat`/`AVAudioPCMBuffer`/`AVAudioTime`/`AVAudioChannelLayout`, `AVAudioFile` reading and writing WAV and AIFF/AIFF-C, `AVAudioEngine` with player, mixer, output and EQ nodes, taps, manual rendering, `AVAudioPlayer`, the error domain, `NSSound` over `AVAudioPlayer`; a pure-Swift pull-model mixer (Apple's measured pan and gain laws, Kaiser-sinc rate conversion, lock-free command and completion rings, a delivery thread) over the `PlatformAudio` seam with WASAPI (IAudioClient3 low-latency shared mode, IAudioClient fallback, MMCSS render thread), PipeWire (dlopen'ed, `pw_stream` with RT process), ALSA (dlopen'ed fallback) and a null backend; `Examples/AudioPlayer` (file and sine players, loop, level meter, output device and latency in the status line, `--render` offline); 15 `AudioTests` run against Apple's AVFAudio on macOS and against the port on macOS (`APPKITWIN_HOST_AVFAUDIO=1`), Windows and Linux; Windows playback verification on the PC is recorded in the pull request |

The macOS host build and the Linux container run the full test suite (110 tests); Windows verification is done by
a remote session on a Windows 11 machine from the checklists in the commit history.

## M0: Foundation (this milestone)

- [x] Architecture and decision records.
- [x] Full public API inventory extracted from the macOS SDK (`api-inventory/`).
- [x] Stub generator with coverage report (`tools/apigen`).
- [x] Package layout that builds on macOS (host) and Windows.
- [x] CI: macOS host build + test, Windows build (GitHub Actions `windows-latest` with
      the swift.org toolchain), Linux build in the `swift:6.2-noble` container
      (`.github/workflows/ci.yml`).

## M1: Open a window and draw

Done when `swift run HelloWindow` on Windows shows a resizable, DPI-aware window whose
custom `NSView` subclass draws filled/stroked paths and text via `draw(_:)`, closes
cleanly, and `NSApplicationDelegate` lifecycle callbacks fire in AppKit order.

Status (2026-10-28): HelloWindow builds with Swift 6.4.1 on Windows 11 and runs: window
with title and standard frame, Direct2D drawing of the sample (grid, rounded rect, circle,
dashed curve), mouse clicks dispatched to the view in AppKit coordinates, key events,
programmatic resize with clean repaint, close through `NSWindow.close()` with app
termination. The core is covered by `Tests/AppKitTests` on the macOS host backend.
Live drag-resize is verified too. Text drawing came with M2/M9; DPI changes across
monitors are covered under M3.

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
the Windows key to `.control`. Field editor (2026-10-29): `NSText`/`NSTextView` are
hand-written (layout with wrapping, caret and selection, mouse selection, key-binding
selectors, copy/cut/paste, `NSTextInputClient` marked text); `NSTextField` edits through
the window's field editor (`fieldEditor(_:for:)`), Return commits and keeps the field
editing with everything selected, Tab/Backtab move focus via
`selectKeyView(following:/preceding:)`. Input methods reach the first responder through
`PlatformWindowOwner.platformWindowTextInput()`; the Win32 WM_IME_* half is with the
Windows session.

## M3: DirectX 12 presentation

Replace the Direct2D HWND render target with a DXGI flip-model swap chain on a D3D12
device; D2D draws through `D3D11On12`. Per-monitor-v2 DPI, HDR surfaces, vsync and
`NSWindow.displaysWhenScreenProfileChanges` equivalents.

Status (2026-10-28): M3a merged (PR #1, built by the Windows session): windows present
through an `IDXGISwapChain1` (flip-sequential, 2 buffers, BGRA, vsync) with an
`ID2D1DeviceContext` drawing into a back-buffer `ID2D1Bitmap1`; D3D11 device with WARP
fallback and the HWND target as a last resort (`APPKITWIN_LEGACY_D2D=1` forces it);
device loss goes through the existing recreate path; `APPKITWIN_DXGI_DEBUG=1` prints
live DXGI objects. Partial repaint (2026-11-03): swap-chain targets draw into a persistent canvas bitmap; `end_draw` blits the canvas into the back buffer and presents through `Present1` with the repainted rect as the dirty region, so a frame repaints (Direct2D work) and recomposes (DWM) only what `InvalidateRect` marked, while the blit keeps both alternating buffers whole; transparent (composition) windows repaint whole, since their cleared pixels must meet the DWM backdrop (`APPKITWIN_TRACE=1` prints `win32 paint dirty` with the rect). Text antialiasing is
forced to grayscale on the swap chain so frames match the HWND target. Monitor DPI
changes (2026-11-03): a window dragged between monitors of different scale keeps its
point size (WM_DPICHANGED sizes the frame from the point size at the new DPI, including
the menu bar and non-client insets from `AdjustWindowRectExForDpi`), the Direct2D target
takes the new DPI and the swap-chain canvas is resized by the WM_SIZE that follows, the
hosted DirectComposition tree is re-placed and its surfaces re-rasterised at the new
scale, and the core marks the whole window for repaint, sets every layer's
`contentsScale`, posts `didChangeBackingPropertiesNotification` and sends
`viewDidChangeBackingProperties` down the tree; a window that opens on a monitor whose
DPI differs from the system's is sized for that monitor at creation. `NSScreen.screens`
carries each monitor's effective DPI and `NSWindow.screen` is the monitor the HWND is on
(`MonitorFromWindow`). `BackingScaleTests` drives this on the host backend
(`HostWindow.setBackingScaleFactor`): point size kept, `lastImage` and a drawn rect's
pixel extent doubled, text ink doubled, a hosted layer scene rebuilt at the new scale,
`viewDidChangeBackingProperties` on every view, `window.screen` following the move.
Verified on Windows 11 with a 150% primary and a 100% secondary monitor: HelloWindow,
opened on the 150% monitor and dragged 150% → 100% → 150% (both directions of a scale
change), keeps its point size, text is crisp on both, nothing is clipped, a resize on
150% repaints cleanly, the Glass window's backdrop, corners and buttons are sharp at
150%, and a native-pixel crop of the Metal tab looks unscaled (a visual judgment, not a
measurement). The trace shows `screen … scale` then `backing scale …` on each move;
`NSWindow` posts `didChangeScreenNotification` on such moves. Not exercised: dragging the Glass window
itself across monitors.
Known limitation: screen frames are converted to points at each monitor's own scale, so
with mixed scales the point-space screen layout can overlap (window frames round-trip
exactly; only `NSScreen.frame` of secondary monitors is affected). Open: D3D12 +
D3D11On12 (only needed for Metal/M7 sharing), HDR, and DirectComposition hosting (M3b/M4b).

## M4: Core Animation

`QuartzCore` over DirectComposition / `Windows.UI.Composition`: `CALayer` tree,
implicit animations, `CATransaction`, `CADisplayLink`, layer-backed `NSView`
(`wantsLayer`, `updateLayer`). This is what SwiftUI's rendering needs.

Status (2026-10-28): the QuartzCore module is real and cross-platform (pure Swift over
CGContext, so the macOS test run covers it): `CALayer` tree with geometry, transforms
(`CATransform3D`; a 3D rotation or a perspective `sublayerTransform` reaches
DirectComposition as a full 4x4 through the visual's effect group, while the software
compositor draws the affine part), flipped geometry, masks, corner radius, borders, contents images,
shadows, hit testing and coordinate conversion; `CAShapeLayer`,
`CAGradientLayer` (banded), `CATextLayer` (drawn by AppKit's string drawing),
`CATransformLayer`, `CAScrollLayer`, `CAReplicatorLayer`, `CAConstraintLayoutManager`;
`CATransaction` with completion blocks; explicit and implicit animations (`CABasicAnimation`,
`CAKeyframeAnimation`, `CASpringAnimation`, `CAAnimationGroup`, `CATransition` as a fade)
with timing functions and fill modes; `CADisplayLink`. Presentation is a software
compositor: the layer tree is rendered into the window's CGContext on each frame; the
frame clock is a one-shot timer from the platform backend (`scheduleFrame`, WM_TIMER on
Windows). AppKit: `wantsLayer` makes the subtree layer-backed (views draw through
`CALayerDelegate`), `layer =` hosts a foreign tree, `animator()` plus `NSAnimationContext`
animate frame/alpha on layer-backed views, `displayLink(target:selector:)`. Offscreen
effects (2026-11-03): the software compositor renders a subtree to pixels when it needs
them, through a bitmap CGContext on every platform, for group opacity (`opacity` < 1 with
sublayers composites the subtree once, `allowsGroupOpacity`), blurred shadows (the
subtree's alpha, or `shadowPath`, blurred by three box passes with `shadowRadius` as the
standard deviation and cached while nothing changes; `shadowOffset` in the layer's own
orientation) and alpha masks (a mask with contents, sublayers or a delegate multiplies
the subtree's alpha; shape and rounded-rect masks stay clip paths). Native hosts flatten
such layers into one rasterised node, so DirectComposition shows the same pixels;
SwiftUI's `.shadow` sets the view's layer shadow. `LayerEffectsTests` checks the pixels.
Native hosting (2026-10-29, ADR-0005): a fully layer-backed window hands its tree to the platform
as a retained scene (`PlatformWindow.hostLayerScene`, nodes with transform/opacity/clip and
versioned `draw` closures; masks, shadows and sublayer transforms flatten their subtree);
the host backend's reference compositor matches the software composite in tests. The
DirectComposition visual tree (PR #5, `cd2d_comp_*` in CD2D, `Win32Window.hostLayerScene`)
reproduces the software output on the Windows machine and drops the animating badge from
8.4 % to 0.6 % of a core; `APPKITWIN_SOFTWARE_LAYERS=1` forces the software compositor and
HelloWindow `--no-layer-backing` leaves views unbacked. A layer draws only within its
bounds in both paths (as on macOS). Not done: group opacity (the software compositor
applies opacity per primitive, DirectComposition per subtree), blurred shadows, `mask`
alpha masks (shape masks clip to the path), `CAMetalLayer`/`CAOpenGLLayer` presentation
(M7). A DPI change re-rasterises the hosted tree at the new scale (M3 status,
`BackingScaleTests.testLayerBackedViewsRerasteriseAtTheNewScale`).

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

Status (2026-10-28): AppKit side done: `PlatformWindowChrome` (content into the title
bar, hidden title, transparent title bar, backdrop, transparency, shadow, movable by
background, rounded corners) derived from `NSWindow` properties and pushed to the
platform window; `platformWindowHitTest` decides caption vs client for dragging;
`NSVisualEffectView` (materials map to Mica/Acrylic behind the window, translucent tint
otherwise; HUD and dark materials carry the vibrant dark appearance). `NSAppearance`
with effective-appearance inheritance (application → window → view) and dynamic semantic
`NSColor`s (light and dark values resolved while a view draws; the application follows
the Windows theme). HelloWindow: Help > Glass Window. Win32 side done and verified on Windows 11 Pro 25H2
(build 26200.9711): windows whose content covers the frame (`fullSizeContentView` or
borderless) keep their Win32 styles but answer `WM_NCCALCSIZE` so the client area is the
whole window (maximised windows are inset by the frame), extend the DWM frame by one pixel
so the shadow and rounded corners stay, and answer `WM_NCHITTEST` with 8-px resize bands
and `NSWindow`'s caption/client decision; DWM attributes map the chrome (system backdrop
Mica/Mica Alt/Acrylic, corner preference, non-client rendering off for `hasShadow == false`,
immersive dark mode from the app theme); transparent windows present through a
premultiplied composition swap chain under a DirectComposition visual
(`cd2d_target_create_composition_swapchain`), cleared to transparent each frame. Not done:
`WS_EX_NOREDIRECTIONBITMAP` (Windows only honours it at creation and the chrome arrives
later; the backdrop shows through without it), a shadow for non-resizable borderless
windows (no DWM frame to extend). Window buttons (2026-11-03): a `.fullSizeContentView`
window draws AppKit's close/miniaturize/zoom buttons at its top-left on every platform
(`NSWindowButtons.swift`, an overlay root above the content view, hit-tested first, grey
when the window is not key, glyphs on hover); `standardWindowButton(_:)` returns them,
`NSWindow` handles `performClose:`/`performMiniaturize:`/`performZoom:` from menus and the
buttons, and `miniaturize`/`deminiaturize`/`zoom` reach the platform (`ShowWindow`,
`XIconifyWindow`/`_NET_WM_STATE`, `xdg_toplevel_set_minimized`/`set_maximized`).

## M7: Metal translation layer (separate track)

Only needed for `MTKView`/`CAMetalLayer` and apps that use Metal directly. Options to
evaluate when we get here: a Swift `Metal` module over D3D12 (shader translation via
Metal Shading Language → DXIL is the hard part) or over Vulkan via SPIR-V. Not a
prerequisite for SwiftUI.

Status (2026-10-28): decided in ADR-0004. `Sources/Metal` has Metal's object model as
protocols (`MTLDevice`, queues, command buffers, render/blit/compute encoders, buffers,
textures, libraries, pipeline states, drawables, descriptors, the common enums) and
`MTLReferenceDevice`: CPU resources, blits, render-pass clears, command-buffer
completion, library scanning (MSL or HLSL entry points), no rasterization. `Sources/MetalKit`
has `MTKView`/`MTKViewDelegate` on AppKit's display link, presenting reference drawables
through CoreGraphics. `Sources/CMetalD3D12` fixes the C interface of the Direct3D 12
backend (device, queue/fence, buffers, textures, HLSL compile, PSOs, command lists, HWND
swap chain) and implements it: hardware adapter (WARP fallback), fence-synchronised
command lists with resource retention, CPU-mapped buffers, default-heap textures with
upload/readback staging, dxc (shader model 6) with a d3dcompiler 5.1 fallback, PSOs over
one shared root signature, render passes with clears, draws, copies, and an HWND flip
swap chain (compiled, not yet exercised by MTKView). On Windows
`MTLCreateSystemDefaultDevice()` returns the D3D12 device unless
`APPKITWIN_METAL_REFERENCE=1`; HelloWindow's Metal tab draws an HLSL triangle on it
(`HelloWindow --metal`, `--metal-selftest` for offscreen checks). Shaders: HLSL/DXIL
first. MSL (2026-10-28, ADR-0006): `MSLTranslator` translates the practical Metal Shading
Language subset to HLSL at the source level (stage attributes → semantics, buffers /
textures / samplers → the shim's register layout, `constexpr sampler`s bound by the device,
column-major matrices with `mul`, intrinsic renames, `half` → `float`, kernels with
`[numthreads]`), with line-numbered diagnostics for the rest; `makeLibrary(source:)`
detects the dialect on every device so MSL function names work unchanged. Covered by
`MSLTranslatorTests` on macOS; `HelloWindow --metal-msl` draws the triangle from MSL and
`--metal-selftest` renders an MSL pipeline. Open on the shim: pointer-style buffer
arguments (`StructuredBuffer` tables in `space1`) and compute dispatch.

Windows presentation (2026-11-04): `MTKView`'s backing layer is a `CAMetalLayer`, and on a
window whose layer tree DirectComposition hosts (`NSWindow._hostsLayersNatively`; the view
asks the content view for `wantsLayer`, as every macOS window is layer-backed) the D3D12
device renders into `MTLD3D12SwapChain`, a flip-model DXGI swap chain created for
composition (`CreateSwapChainForComposition`, FLIP_SEQUENTIAL, two buffers, vsync
present). Its `IDXGISwapChain1` travels as the layer's `_nativeContent` into the scene node
and becomes the content of the node's visual (`cd2d_comp_tree_set_swapchain`), so the
frame is shown pixel for pixel at the visual's origin and the label subview composites
above it. The chain follows `drawableSize` (window resizes, `viewDidChangeBackingProperties`
on a DPI change) and a resize renders a frame at the new size at once. Elsewhere (the host
backend, `APPKITWIN_SOFTWARE_LAYERS=1`, the reference device) the drawable is a texture
read back and drawn through CoreGraphics, as before; `--metal-log` prints which path a
frame took. Every Metal command queue executes on the device's one direct queue, the
queue the chain is created on: a composition back buffer written from any other D3D12
queue removes the device with DXGI_ERROR_ACCESS_DENIED (seen on WARP and the RTX 2070),
and commit is synchronous anyway. The shim gained region texture copies (`cm_commandlist_copy_texture_region`),
and CPU-side blit work (fills, buffer ↔ texture copies through staging) now executes the
GPU commands recorded before it first, so a readback after a copy sees the copy. Tests on
Windows (WARP on CI, the GPU on the test PC): `MetalD3D12DeviceTests` (every MSL sample
of `MSLTranslatorTests` plus HelloWindow's HLSL and MSL compiled per stage, triangles from
HLSL and MSL, blit regions and order, the composition swap chain presenting, keeping and
resizing its buffers) and `MetalD3D12ParityTests` (the Vulkan parity scene and a
presented `MTKView` frame against the reference device). Verified on the test PC (RTX
2070 SUPER, DISPLAY1 150%, DISPLAY2 100%) at 405241c: the Windows suite 242 tests, 0
failures; HelloWindow's Metal tab presents through the swap chain on both monitors
(657x411 pixels at 150%, 438x274 at 100%, the device name in `--metal-log`), crisp
edges; a real corner drag at 150% printed four new sizes during the drag with the
triangle drawing throughout and no black flashes; `SetWindowPos` resizes at 100% and
the DPI re-size on a cross-monitor move each rendered crisp at the new size.

## M8: Linux backend

New `Platform/Linux` (Wayland/X11 + Vulkan + Skia or Cairo for `CGContext`). The core
and the SwiftUI layer should need no changes; that is the test of the architecture.

Status (2026-10-28): groundwork in place: `CoreGraphics/CGContextCairo.swift` (the
Direct2D context's API over Cairo, plus bitmap contexts), `CCairo`/`CX11` system library
modules, and `Platform/Linux` (Xlib windows with Cairo backing surfaces, a poll()-based
event loop that also serves posted blocks and the frame clock, key/mouse translation
with the same Ctrl-as-Command convention, cursors, PangoCairo text, PNG images, an
in-process pasteboard, zenity file dialogs; no native menu bar). The core needed no
changes beyond widening non-Darwin conditionals. `tools/linux/Dockerfile` builds on
`swift:6.2-noble`, runs the test suite on the host backend (`APPKITWIN_HOST_BACKEND=1`)
and HelloWindow under Xvfb for a screenshot (the sample renders fully: text, paths,
controls, scroll view, the Core Animation badge). The test suite runs on Linux
(2026-10-29, 71/71 on the host backend): swift-corelibs-xctest cannot call `@MainActor`
test methods, so test classes are nonisolated and each body runs in
`MainActor.assumeIsolated`; the CI job requires the run to pass.

Wayland (2026-10-28): `WaylandBackend`/`WaylandWindow` next to the X11 classes, over a
`CWayland` C target (libwayland-client, wayland-cursor, xkbcommon, and the xdg-shell and
xdg-decoration protocol tables as checked-in wayland-scanner output;
`tools/linux/gen-wayland-protocols.sh` regenerates them). Registry binding of
compositor, shm, seat, outputs, `xdg_wm_base` and `zxdg_decoration_manager_v1`;
xdg_toplevel windows with title, app id, min/max size, server-side decorations when the
compositor offers them, configure/resize through `platformWindowDidChangeFrame`, close
requests through `platformWindowShouldClose`/`WillClose`; two wl_shm buffers copied from
the same persistent Cairo backing surface the X11 window draws into (dirty rect clipped,
`wl_surface.damage_buffer`), surface frame callbacks firing the `scheduleFrame` clock
early (the 1/60 s timer remains the fallback); the poll()-based loop reads the display fd
with `prepare_read`/`read_events`. Input: xkbcommon keymaps from the seat with the same
Ctrl-as-Command mapping, `charactersIgnoringModifiers` from the level-0 keysym, pointer
motion/buttons/axis (one notch = 3 lines, batched per `wl_pointer.frame`) in content
coordinates, double-click counting; HiDPI by taking the largest scale of the outputs the
surface entered and `set_buffer_scale` (`WaylandScaleTests` checks the rule, and
`run-wayland.sh` moves HelloWindow to a second headless output at scale 2 and checks the
backing-scale trace and the unchanged logical size; X11 has one scale per display from
`Xft.dpi`, so no window ever changes scale there); cursors from the wl_cursor theme
(`XCURSOR_THEME`/`XCURSOR_SIZE`). Selection: Wayland when `WAYLAND_DISPLAY` is set and
the connection succeeds, else X11; `APPKITWIN_LINUX_BACKEND=x11|wayland` forces one;
`APPKITWIN_HOST_BACKEND=1` is unchanged. Verified in the container with
`tools/linux/run.sh --wayland`: sway 1.9 headless (pixman renderer, no seat), grim
screenshot in the README, plus an interaction pass through a virtual pointer and wtype
(clicks add dots at the right points, the text field takes typed text, the wheel
scrolls the list, the compositor's close request terminates the app). Not covered on
Wayland: client-side decorations (compositors without xdg-decoration show a bare
surface), window positions (`frame.origin` is never honoured; `mouseLocation` is relative
to the window under the pointer), `makeKey`/`orderBack` (no focus requests; xdg-activation
not used), key repeat, touch and tablet input, fractional scaling, the cursor-shape
protocol, IME (text-input-v3), `wp_viewporter`, and a GPU path.

Selections and drag and drop (2026-11-03, ADR-0011 stage B): the X11 pasteboard is the
CLIPBOARD selection (served from a hidden selection window; TARGETS, TIMESTAMP and INCR
on the way in) and drags use XDND 5 in both directions; on Wayland the clipboard and
drags go through the seat's data device (`wl_data_device_manager` v3, data sources
answering `send` over pipes, offers read the same way, an shm icon surface for the drag
image). `X11DragDropTests` and `X11ClipboardTests` run under Xvfb in `tools/linux/run.sh`
against a second X client in the test process.

Open on Linux: JPEG via gdk-pixbuf, IME, a Wayland seat in the container to drive data
device tests.

## M10: SwiftUI stack modules

The modules a SwiftUI implementation needs beside AppKit, each declared only on Windows
and Linux so the macOS build and tests run against Apple's.

Combine (2026-10-28, ADR-0008): `Sources/Combine` is OpenCombine 0.14.0 (MIT) renamed to
`Combine`, with `OpenCombineFoundation` and `OpenCombineDispatch` merged in and their
`OCombine` namespaces flattened to Apple's shape (`NotificationCenter.publisher(for:)`,
`Timer.publish(...)`, `RunLoop`/`DispatchQueue`/`OperationQueue: Scheduler`,
`URLSession.dataTaskPublisher`, `JSONEncoder: TopLevelEncoder`), the C++ helper target
replaced by `NSLock`-based Swift, and `Publishers.Merge`/`MergeMany`/`CombineLatest`
added since upstream has not implemented them. `Tests/AppKitTests/CombineTests.swift`
is the specification: it passes against Apple's Combine on macOS and against the port in
the Linux container. Not implemented: `Publishers.CollectByTime` (`collect(.byTime)`).
Windows is unverified until the next Windows session (nothing platform-specific beyond
`DebugBreak()` and corelibs Foundation).

## M10: Third-party SwiftUI libraries (Examples/LibraryCompat)

Status (2026-11-04): `Examples/LibraryCompat` builds eight popular SwiftUI packages against
this SwiftUI; the per-library verdicts and the API gaps are in
[compatibility/swiftui-libraries.md](compatibility/swiftui-libraries.md). Landed for it:
`Gradient`/`LinearGradient` (drawn as bands; no `CGGradient` yet), `.mask`, `PreferenceKey`
with `preference`/`anchorPreference`/`transformPreference`/`onPreferenceChange` and
resolved anchors, `.rotation3DEffect`, `.task`, `.redacted`, `.blendMode`, `PreviewProvider`,
`Image` from `CGImage`, `Color`/`NSColor`/`CGColor` bridging, `Color.Resolved`, and `View`
being main-actor isolated as Apple's is. Follow-ups the libraries asked for, largest first:

- `Layout` protocol (`Layout`, `Subviews`, `ProposedViewSize` cache, `AlignmentID`,
  `ViewDimensions`) and `Grid`/`GridRow`/`LazyVGrid`/`GridItem`: swift-markdown-ui's tables
  and flow layout, SwiftUICharts' legends.
- Text styling: `Font.Width`, `Font.smallCaps`/`lowercaseSmallCaps`/`uppercaseSmallCaps`,
  `Text.LineStyle`, `Text.monospacedDigit`, `.lineSpacing`, `.tracking`/`.kerning` on views,
  `@ScaledMetric`, and `AttributedString` SwiftUI attributes (`font`, `foregroundColor`,
  `backgroundColor`, `underlineStyle`, `strikethroughStyle`, `kern`) rendered by `Text`.
- Shapes: `InsettableShape`, `Shape.trim`/`scale`/`offset`, `Path.trimmedPath`/`addRelativeArc`
  /`forEach`, `AnyShapeStyle`, `RadialGradient`/`AngularGradient`, `CGGradient` in CoreGraphics
  on Windows and Linux (Direct2D and Cairo both have gradient brushes).
- View modifiers: `.position`, `.zIndex`, `.gesture` beyond tap/hover, `.labelStyle`/`LabelStyle`,
  `.symbolRenderingMode`/`.imageScale` (SF Symbols are Apple-only; `Image(systemName:)` has no
  glyphs here), `transformEnvironment`, `backgroundPreferenceValue`/`overlayPreferenceValue`.
- Compositing blend modes in the software and DirectComposition compositors (`.blendMode`
  sets the layer's compositing filter; nothing applies it yet).
- `CoreGraphics` submodules (`import CoreGraphics.CGGeometry`) and an `ObjectiveC` shim are
  Foundation-level gaps outside this package's scope; libraries that assume `!os(macOS)` means
  UIKit (Defaults, Nuke, WrappingHStack) need upstream `canImport(AppKit)` checks.

## M11: Accessibility

Status (2026-11-04, ADR-0013): see the status table. The core builds a snapshot tree
from the NSAccessibility answers of its views (`Platform/Accessibility.swift`), which
`Win32Window` serves to UI Automation and the X11/Wayland backends serve to AT-SPI2.
Verification: `AccessibilityTests` on the host backend (macOS and the Linux container),
`AtspiTests` plus `tools/linux/atspi-probe.py` under Xvfb with an accessibility bus
(the probe presses the check box, sets the slider and the text field over D-Bus), and
UI Automation clients on the Windows machine (PowerShell's UIA client read the tree and
invoked every pattern; `tools/windows/uia-events.ps1` saw the focus, toggle, value and
text events while tabbing through HelloWindow and typing; inspect.exe could not be driven
remotely, and Narrator could not be heard by the remote session). Not yet: menus and menu items
in the tree, `NSAccessibilityElement` virtual elements, custom rotors and actions, the
AT-SPI `Cache` interface, text granularities finer than the whole text on AT-SPI, and
structure events naming the added or removed child.

## M12: Audio

Status (2026-11-04, ADR-0014): see the status table. Follow-ups: `AVAudioUnitTimePitch`
and `AVAudioUnitVarispeed` (time stretching, which `AVAudioPlayer.rate` also needs),
`AVAudioConverter`, `AVAudioSourceNode`/`AVAudioSinkNode`, streaming scheduled files from
disk instead of decoding them whole, CAF, device-change tracking
(`AVAudioEngineConfigurationChange`), device selection (`PlatformAudio` enumerates; the
engine opens the default), input capture (`AVAudioInputNode`, `AVAudioRecorder`).

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
