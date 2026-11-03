# ADR-0011: A Vulkan backend for the `Metal` module on Linux

Status: accepted. Date: 2026-11-03. Extends ADR-0004 and ADR-0006.

## Decision

`Sources/CMetalVulkan` is a C++17 shim with an `extern "C"` interface
(`cmetal_vulkan.h`), declared in `Package.swift` only on Linux, the way `CMetalD3D12` is
declared only on Windows. `Sources/Metal/MTLVulkanDevice.swift` implements `MTLDevice`
and the rest of the object model over that interface, behind `#if os(Linux)`, with the
same shape as `MTLD3D12Device`: command buffers record closures and replay them into a
`VkCommandBuffer` on commit; drawables are Vulkan images read back on present.

Vulkan is loaded at runtime. The shim `dlopen`s `libvulkan.so.1` (then `libvulkan.so`)
and resolves everything through `vkGetInstanceProcAddr`; nothing links against the
loader, so the package builds and the suite runs on a machine with no Vulkan at all. The
headers (`<vulkan/vulkan.h>` from `libvulkan-dev`) are a build-time dependency only;
when they are absent the shim compiles to stubs whose creators return `NULL`, exactly
like the D3D12 placeholder of ADR-0004, and the Metal module falls back to the
reference device.

Device selection on Linux (`MTLDeviceRegistry.defaultDevice()`): the Vulkan device
when `MTLVulkanDevice()` succeeds, which needs a loader, an instance, a physical device
with a queue family that supports graphics and compute, and Vulkan 1.3 (dynamic
rendering and extended dynamic state); the reference device
otherwise and always under `APPKITWIN_METAL_REFERENCE=1`. `APPKITWIN_VULKAN_DEBUG=1`
enables `VK_LAYER_KHRONOS_validation` when the loader lists it and routes its messages
to stderr through `VK_EXT_debug_utils`; without the layer the switch is a no-op.

A presentable queue (`VK_KHR_surface` support) is reported in the device info and is
what swap-chain presentation will need; it is not required to select the device, since
the first presentation path is the readback seam below, and headless Vulkan devices
(lavapipe in the container) have no surface support without a window system.

## Concept mapping

MoltenVK maps Vulkan onto Metal; this backend goes the other way with the same table:

| Metal | Vulkan |
| --- | --- |
| `MTLDevice` | `VkInstance` + `VkPhysicalDevice` + `VkDevice`, one graphics/compute queue family |
| `MTLCommandQueue` | a `VkQueue` handle (shared and locked when the family has one queue) plus a fence ring; `cm_queue_signal`/`cm_queue_wait` are empty submissions with fences |
| `MTLCommandBuffer` | one `VkCommandPool` + primary `VkCommandBuffer`, reset per commit |
| `MTLRenderCommandEncoder` | `vkCmdBeginRendering`/`vkCmdEndRendering` (dynamic rendering, no `VkRenderPass`/`VkFramebuffer`); load actions become `loadOp`, clear colours `VkClearValue` |
| `MTLBlitCommandEncoder` | `vkCmdCopyBuffer`, `vkCmdCopyImage`, `vkCmdCopyBufferToImage`, `vkCmdCopyImageToBuffer`, `vkCmdFillBuffer`, with layout transitions around them |
| `MTLComputeCommandEncoder` | `vkCmdBindPipeline(COMPUTE)` + `vkCmdDispatch` |
| `MTLBuffer` | `VkBuffer` in host-visible, host-coherent memory, persistently mapped (`storageModeShared`); usage vertex, index, uniform, storage, transfer |
| `MTLTexture` | `VkImage` (2D, optimal tiling, device-local) with one `VkImageView`, kept in `VK_IMAGE_LAYOUT_GENERAL` for its whole life so no use needs a layout transition; `replace`/`getBytes` stage through a host buffer on the device's utility queue |
| `MTLSamplerState` | `VkSampler` (filter and address modes mapped) |
| `MTLDepthStencilState` | dynamic state at draw time: `vkCmdSetDepthTestEnable`, `vkCmdSetDepthWriteEnable`, `vkCmdSetDepthCompareOp`, `vkCmdSetStencil*` |
| `MTLRenderPipelineState` | `VkPipeline` (graphics) with `VkPipelineRenderingCreateInfo` for the attachment formats; viewport, scissor, topology, cull mode, front face and depth/stencil are dynamic |
| `MTLComputePipelineState` | `VkPipeline` (compute) |
| `MTLFunction` | `VkShaderModule` + entry-point name |
| `MTLDrawable` | an image read back by `MTKView` (readback seam); later a `VkSwapchainKHR` image through `VK_KHR_xcb_surface`/`VK_KHR_wayland_surface` |
| Resource binding | one `VkPipelineLayout` for everything (below) and one descriptor set per draw/dispatch from a per-command-buffer pool |
| Hazard tracking | Metal orders encoders, and dispatches and copies within an encoder; the shim emits a full memory barrier (all commands, all access) at every render-pass begin, dispatch and copy, which is correct on every GPU and free on lavapipe |

### Binding model

The D3D12 shim's root signature (ADR-0006) is kept as the contract, so the same HLSL,
and the same translated MSL, binds the same way on both GPU backends. Descriptor set 0
holds the per-stage slots; set 1 holds the pointer-style buffers the translator puts in
`space1`, which the D3D12 shim does not bind yet and this backend does:

| HLSL register | Vertex / kernel stage | Fragment stage |
| --- | --- | --- |
| `bN` (constant buffer) | set 0, binding N | set 0, binding 32 + N |
| `tN` (texture) | set 0, binding 8 + N | set 0, binding 40 + N |
| `sN` (sampler) | set 0, binding 16 + N | set 0, binding 48 + N |
| `uN` (storage image) | set 0, binding 24 + N | set 0, binding 56 + N |
| `tN, space1` / `uN, space1` (structured buffer) | set 1, binding N | set 1, binding 8 + N |

`setVertexBuffer(_:offset:index:)` binds the buffer as vertex input binding N when the
pipeline's vertex descriptor declares that layout, and as `bN` and `space1` slot N;
`setFragmentBuffer` binds `bN` and slot N of the fragment half; the compute encoder's
`setBuffer` binds the vertex/kernel half. Vertex attribute `[[attribute(n)]]` is
location n. Every binding has a stage mask of all stages, and slots the application has
not set point at a dummy buffer, a 1×1 texture or the default sampler, so descriptor
sets are always complete.

### Shaders

The D3D12 path compiles HLSL in process (`dxcompiler.dll`, then `D3DCompile`). Linux
has no in-process HLSL compiler the port can rely on, so the Vulkan device expects
**SPIR-V**:

- `makeLibrary(data:)` takes a SPIR-V module. The library lists its `OpEntryPoint`s
  (execution model → `MTLFunctionType`) and `makeFunction(name:)` wraps one of them.
  `MTLVulkanLibrary(device:spirv:)` builds a library from several modules keyed by
  function name, for the one-entry-point-per-module output of dxc and glslang.
- `makeLibrary(source:options:)` accepts HLSL and MSL as on the other devices (MSL is
  translated to HLSL by `MSLTranslator`, ADR-0006, which keeps the MSL function names
  and rejects what the GPU backends reject). The HLSL is compiled to SPIR-V lazily, per
  entry point, when a pipeline is created, through an external compiler on `PATH`:
  `dxc -spirv` when present, else `glslangValidator -D -V` (the `glslang-tools`
  package). Both are invoked with the register shifts of the binding model above. When
  neither is installed the pipeline throws `MTLLibraryError(.unsupported)` naming both
  tools and the `makeLibrary(data:)` path, so the failure is explicit rather than a
  silently empty frame.

This keeps the HLSL-first rule of ADR-0004: an application that ships HLSL (or MSL)
runs on Linux once a SPIR-V compiler is installed; an application that ships SPIR-V
needs nothing else. Vertex-input locations follow the order of the HLSL input struct's
members, which is also the `ATTRIBUTEn` order the D3D12 shim binds, so the same vertex
descriptor works on both.

### Presentation

`MTKView` presents GPU drawables by reading the texture back and drawing it through
CoreGraphics (the readback seam that `MTLD3D12Device` uses today, so the view's code
is unchanged). The X11 and Wayland windows therefore show Vulkan-rendered frames
through the existing Cairo window path. A `VkSwapchainKHR` on the window's
`xcb_connection_t`/`xcb_window_t` or `wl_display`/`wl_surface` through `CAMetalLayer`
is the follow-up, and needs the Vulkan instance created with
`VK_KHR_xcb_surface`/`VK_KHR_wayland_surface`, which the shim requests when the
loader offers them.

## Testing

The container (`tools/linux/Dockerfile`) has no GPU. It installs Mesa's `lavapipe`
(`mesa-vulkan-drivers`, a CPU Vulkan 1.3 implementation), the loader, the headers,
`glslang-tools` and the validation layers, so the Vulkan device exists there and the
suite exercises it. Tests render the same scene on the reference device and on the
Vulkan device and compare pixels within a tolerance; when `MTLVulkanDevice()` is nil
they skip with a message. The macOS host build never declares the module and the
tests skip there, so `swift build && swift test` stay green. The suite must also stay
green in a container without the loader, which is the stub path above.

## Consequences

- Linux applications that use Metal get a GPU for buffers, textures, blits, compute,
  and (from stage 3) rasterization; `MTKView` keeps working with no GPU through the
  reference device.
- The binding model is the D3D12 one, so shaders need no per-platform `register`
  layout; `space1` structured buffers work on Vulkan first.
- Presentation goes through a readback until the swap-chain seam lands; frame rate on
  a real GPU is bounded by that copy, as on Windows today.
- Vulkan 1.3 is required (dynamic rendering and extended dynamic state keep the shim
  small). Older drivers fall back to the reference device rather than a partial path.
