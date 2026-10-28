# ADR-0003: CoreGraphics is implemented over Direct2D; Direct3D 12 owns presentation

Status: accepted. Date: 2026-10-28.

## Decision

`CGContext` is backed by an `ID2D1DeviceContext`. Text goes through DirectWrite. The
window surface is, in Milestone 1, an `ID2D1HwndRenderTarget` for simplicity; in
Milestone 3 it becomes a DXGI flip-model swap chain on a D3D12 device with Direct2D
rendering through `D3D11On12`. Compositing (`CALayer`) uses DirectComposition.

## Rationale

CoreGraphics is a retained-path, antialiased 2D vector API with per-context transform,
clip and alpha state. Direct2D has the same model (geometries, brushes, transforms,
layers, clip rects, antialias modes) and is the native Windows 2D rasterizer, so the
mapping is nearly one-to-one and hardware accelerated. Writing a software rasterizer or
depending on Skia would not be "native" and would duplicate what the OS ships.

Direct3D 12 alone is a poor fit for CoreGraphics semantics (no vector paths, no text),
which is why it owns presentation rather than drawing.

## Consequences

- `WinSDK` exposes Direct2D (`d2d1.h` through `d2d1_3.h`), D3D12, DXGI and WIC with C
  vtables. It does not expose `dwrite.h`, `dcomp.h` or `d3d11on12.h` (verified against
  `stdlib/public/Platform/um.modulemap` on 2026-10-28), and those headers are C++-only,
  so DirectWrite (Milestone 2) and DirectComposition (Milestone 4) will be reached
  through Swift's C++ interoperability (`-cxx-interoperability-mode=default`) rather than
  C module maps. Milestone 1 needs only Direct2D.
- Direct2D is COM, and unlike D3D11/DXGI its C headers carry no vtables (verified on the
  first Windows build, 2026-10-28: every `ID2D1*` is an incomplete type in C mode). Swift
  therefore talks to a small C++ target, `Sources/CD2D`, that exposes `extern "C"`
  functions over opaque handles. DirectWrite and DirectComposition will join that shim.
