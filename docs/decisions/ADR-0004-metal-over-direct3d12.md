# ADR-0004: A `Metal` module over Direct3D 12, with HLSL shaders first

Status: accepted. Date: 2026-10-28.

## Decision

`Sources/Metal` is a Swift module with Metal's object model (`MTLDevice`,
`MTLCommandQueue`, `MTLCommandBuffer`, encoders, buffers, textures, pipeline states,
libraries, drawables) as protocols, exactly as Apple's. Devices come from a backend:

- `MTLReferenceDevice` (all platforms): a CPU implementation of resources, blits and
  render-pass clears, with no rasterization. It exists so the API is testable and so
  `MTKView` works everywhere (a cleared, presented drawable), and it is what tests use.
- `MTLD3D12Device` (Windows): D3D12 through the `CMetalD3D12` C++ shim, sharing the
  DXGI/D3D11 presentation of Milestone 3 (`CAMetalLayer` presents into the window's
  swap chain). The shim's C interface is fixed by `cmetal_d3d12.h`; the implementation
  lands in its own pull request from the Windows machine.

Shaders: `MTLLibrary` accepts HLSL source and precompiled DXIL/DXBC on Windows
(`device.makeLibrary(source:)` compiles HLSL with `D3DCompile`; entry points are
`MTLFunction` names). Metal Shading Language is not compiled on Windows yet; a future
MSL frontend (or a DXIL-from-MSL translator) can plug into the same `MTLLibrary` factory
without API changes. `MTLCompileOptions.languageVersion` is accepted and ignored.

`MetalKit` provides `MTKView` and `MTKViewDelegate` over AppKit's `NSView` and the
Core Animation display link; it draws reference-device drawables through CoreGraphics.

## Rationale

Metal's object model maps onto D3D12 closely (command queues/lists, PSOs, descriptor
tables, resource states). Vulkan would also fit but adds a loader dependency on
Windows; D3D12 is the OS API and shares presentation with the rest of the port. The
hard part is shader translation, which has no mature open-source MSL-to-DXIL path; the
HLSL-first rule lets applications that already ship both shader dialects (most engines)
run now, while keeping Metal's API surface for everything else.

## Consequences

- `import Metal` resolves to this module in the package on every platform; Apple's
  Metal is never linked on Windows or Linux.
- Rasterization only exists on Windows once the D3D12 shim lands; the reference device
  reports `supportsRasterization == false` and draw calls are accepted and ignored.
- Linux follows later with a Vulkan backend behind the same `MTLDeviceBackend`.
