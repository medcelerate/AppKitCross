# Architecture

## Goals

1. **Source compatibility.** Code written against Apple's AppKit (Swift) compiles and
   behaves the same on Windows. Public names, signatures, nullability, actor isolation
   and documented semantics follow the macOS SDK. The inventory extracted from the SDK
   (`api-inventory/`) is authoritative.
2. **Native hosting.** Windows, input, display, text and compositing go through the
   platform's own APIs rather than a portable toolkit:
   - Win32 (`user32`) for HWND lifecycle, the message loop, input and DPI.
   - DXGI + Direct3D 12 for swap chains and GPU presentation.
   - Direct2D for 2D vector rasterization behind `CGContext`.
   - DirectWrite for text shaping and rasterization behind `CoreText`.
   - DirectComposition / `Windows.UI.Composition` for the `CALayer` tree.
   - WinRT where Win32 has no equivalent (app lifecycle, toasts, settings).
3. **Layered so SwiftUI can sit on top.** SwiftUI on macOS depends on AppKit only
   through a narrow set of hosting types (`NSHostingView`, `NSHostingController`,
   `NSViewRepresentable`) plus Core Animation. Those seams are first-class milestones.
4. **Portable core.** Everything that is not an OS call lives in `Sources/AppKit/Core`
   and is platform independent. A Linux backend later swaps only `Platform/`.

## Module map

```
┌──────────────────────────────────────────────────────────┐
│ SwiftUI (future)                                         │
├──────────────────────────────────────────────────────────┤
│ AppKit                                                   │
│  Core/        NSApplication, NSWindow, NSView, NSEvent … │
│  Generated/   compiled stubs for the rest of the surface │
│  Platform/    Backend protocols                          │
│     Win32/    HWND, message loop, DXGI/D3D12 surfaces    │
│     Host/     headless backend for tests on macOS/Linux  │
├────────────────┬────────────────┬────────────────────────┤
│ QuartzCore     │ CoreText       │ CoreGraphics           │
│ (CALayer over  │ (DirectWrite)  │ (CGContext over D2D,   │
│  DirectComp.)  │                │  CGPath, CGColor, …)   │
├────────────────┴────────────────┴────────────────────────┤
│ Foundation (swift-corelibs-foundation, swift-foundation) │
├──────────────────────────────────────────────────────────┤
│ WinSDK (Win32, D3D12, DXGI, D2D, WIC)   DirectWrite/DirectComposition via C++ interop │
└──────────────────────────────────────────────────────────┘
```

Module names are the Apple names so `import AppKit` / `import CoreGraphics` compile
unchanged. On macOS only `AppKit` is built locally (it shadows the system framework
cleanly); the graphics modules are provided by Apple's SDK so that the shared core is
type-checked against the real signatures.

## The platform seam

`Platform/Backend.swift` declares the protocols the core talks to:

| Protocol | Responsibility | Win32 implementation |
| --- | --- | --- |
| `PlatformApplication` | run loop, termination, activation, event pumping | `GetMessageW`/`DispatchMessageW`, `PostQuitMessage` |
| `PlatformWindow` | create/show/hide/resize/title/level, map OS events to `NSEvent` | `CreateWindowExW`, `WndProc`, `SetWindowPos`, `DwmExtendFrameIntoClientArea` |
| `PlatformDisplay` | screens, DPI, color space | `EnumDisplayMonitors`, `GetDpiForMonitor` |
| `PlatformRenderSurface` | per-window drawing target handed to `NSGraphicsContext` | Milestone 1: `ID2D1HwndRenderTarget`. Milestone 3: DXGI flip-model swap chain on D3D12 with D2D via `D3D11On12` |

The core owns all policy (responder chain, view hierarchy, dirty-rect tracking,
key/main window state, layout). The backend owns only mechanism.

Coordinate systems: AppKit is bottom-left origin and points; Windows is top-left and
device pixels. The flip and DPI scale happen once, at the seam, in `PlatformWindow`:
the core only ever sees AppKit coordinates.

## Drawing path (Milestone 1)

1. `NSWindow.display()` or `WM_PAINT` arrives.
2. Backend begins a frame on the surface and wraps it in a `CGContext`.
3. Core creates `NSGraphicsContext(cgContext:flipped:)`, sets it current, and walks
   the view tree calling `draw(_:)` with clip/transform set per view.
4. Backend ends the frame and presents.

Layer-backed views (`wantsLayer`) are Milestone 4 and use the `CALayer` tree instead.

## Objective-C runtime dependence

AppKit's API leaks the ObjC runtime in a few places: `@objc optional` protocol
requirements, `responds(to:)`, `perform(_:)`, KVO, target/action with `Selector`,
`NSCoding`. The port handles these without an ObjC runtime:

- Optional protocol requirements become requirements with default implementations in a
  protocol extension (same technique as swift-corelibs-foundation).
- `Selector`-based target/action is kept as API but dispatched through a registry
  keyed by `NSObject` identity and selector string, with a Swift closure fallback.
- `NSCoding` compiles (corelibs provides `NSCoder`) but archive compatibility with
  macOS nibs is out of scope. Storyboards/nibs are not supported; code-built UI only.

## Metal

AppKit itself never needs Metal; `MTKView` lives in MetalKit and `CAMetalLayer` in
QuartzCore. SwiftUI needs neither for ordinary rendering. A Metal API translation layer
(Metal objects over D3D12 or Vulkan) is therefore a separate, later track
(see ROADMAP M7). Direct2D/DirectWrite give the 2D fidelity CoreGraphics and CoreText
need without a translation layer.

## Why Swift for the port itself

The target consumer is Swift (SwiftUI). Swift on Windows is a supported swift.org
platform with Foundation, Dispatch and XCTest, and the `WinSDK` module already exposes
Win32, DXGI, D3D12, D2D and WIC. Writing the port in C++ would add an FFI boundary for
every AppKit object and make `@MainActor`/`Sendable` annotations impossible to honour.
