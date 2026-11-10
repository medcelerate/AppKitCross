# ADR-0012: A Vulkan backend for the `Metal` module on Linux

Status: accepted. Date: 2026-11-03; presentation added 2026-11-10. Extends ADR-0004, ADR-0005 and ADR-0006.

## Decision

`Sources/CMetalVulkan` is a C++17 shim with an `extern "C"` interface
(`cmetal_vulkan.h`), declared in `Package.swift` only on Linux, the way `CMetalD3D12` is
declared only on Windows. `Sources/Metal/MTLVulkanDevice.swift` implements `MTLDevice`
and the rest of the object model over that interface, behind `#if os(Linux)`, with the
same shape as `MTLD3D12Device`: command buffers record closures and replay them into a
`VkCommandBuffer` on commit; drawables are swap-chain images presented to the window
system (below), or plain images read back where there is no surface.

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

A presentable device (`VK_KHR_swapchain`, with `VK_KHR_xlib_surface` and
`VK_KHR_wayland_surface` on the instance) is reported in the device info
(`MTLVulkanDevice.isHeadless`, `supportsXlibPresentation`, `supportsWaylandPresentation`);
it is not required to select the device, since a device without it still renders and
`MTKView` falls back to the readback seam below. Lavapipe in the container presents to
X11 and Wayland surfaces through Mesa's software window-system integration, so the
swap-chain path runs under Xvfb and under a headless sway too.

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
| `MTLDrawable` | a `VkSwapchainKHR` image (`MTLVulkanSwapChain`, below) on the native surface the window placed under the view, through `VK_KHR_xlib_surface`/`VK_KHR_wayland_surface`; elsewhere an image read back by `MTKView` (readback seam) |
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

The Windows design (ADR-0004, PR 17) is mirrored: `MTKView`'s backing layer is a
`CAMetalLayer`, and the view renders straight into a swap chain the window system shows,
instead of reading the frame back. On Windows that chain is a DXGI composition swap chain
set as the content of the view's visual in the window's DirectComposition tree
(ADR-0005). The Linux windows composite their layers in software, so they offer the
layer-hosting seam's counterpart for native content: `PlatformWindow.makePresentationSurface(frame:)`
places a native surface within the content area at the view's frame, above everything the
window draws itself, and the view presents into it:

- X11 (`LinuxWindow`): a child `Window` of the toplevel (`XCreateSimpleWindow`, no
  background so the server never clears it, no input mask so pointer and key events
  propagate to the toplevel as if it were not there), moved and sized with
  `XMoveResizeWindow` in pixels. The chain's `VkSurfaceKHR` comes from
  `VK_KHR_xlib_surface` over the backend's `Display*` and that child.
- Wayland (`WaylandWindow`): a `wl_subsurface` of the window's surface
  (`wl_subcompositor`, bound from the registry), desynchronised so the chain's commits show
  as they come, positioned in the parent's logical coordinates (shadow margin and title
  band included, ADR-0015) and given the window's buffer scale, so a chain of
  `drawableSize` pixels covers the view's points on a 2x output. `wl_subsurface.set_position`
  takes effect at the parent's next commit, so a moved surface marks the window dirty. The
  `VkSurfaceKHR` comes from `VK_KHR_wayland_surface` over the `wl_display*` and that
  `wl_surface*`.

`MTLVulkanSwapChain` (`Sources/Metal/MTLVulkanDevice.swift`) wraps the shim's
`cmv_swapchain_*` calls, the way `MTLD3D12SwapChain` wraps `cm_swapchain_*`:

- Formats are `CAMetalLayer`'s: `bgra8Unorm`, `bgra8Unorm_srgb`, `rgba16Float`, mapped to
  `VK_FORMAT_B8G8R8A8_UNORM`, `B8G8R8A8_SRGB`, `R16G16B16A16_SFLOAT`; the surface must list
  the format or the chain is not made, and the view then falls back to the readback path
  naming the reason (`MTKView._presentationError`), as lavapipe does for `rgba16Float`.
- `displaySyncEnabled` picks `VK_PRESENT_MODE_FIFO_KHR` (vsync, always available);
  off, it takes `MAILBOX`, then `IMMEDIATE`, where the surface offers them, else FIFO. A
  change re-creates the chain.
- The chain is sized in pixels and re-created (with `oldSwapchain`) on `resize`: the
  view's `drawableSize` follows window resizes and `viewDidChangeBackingProperties`, the
  surface is re-sized first, and a frame is drawn at the new size at once. X11 reports the
  child window's size as the surface's current extent, which the chain takes; Wayland
  leaves the extent to the client. `VK_ERROR_OUT_OF_DATE_KHR` and `VK_SUBOPTIMAL_KHR`
  re-create the chain at the next acquire.
- `nextDrawable()` acquires an image (`vkAcquireNextImageKHR` with a semaphore and a
  fence; the fence is waited so the CPU side is in step) and moves it into
  `VK_IMAGE_LAYOUT_GENERAL`, the layout every image of this backend lives in, with a
  utility submission that waits on the acquire semaphore. From then on the image is a
  texture like any other: render passes attach it, blits copy it, `getBytes` reads it.
- `present()` (called by the command buffer that drew into it, after its work completed,
  as `MTLDrawable.present` works on the other devices) moves the image to
  `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR` with a utility submission that signals the image's
  present semaphore, then `vkQueuePresentKHR` waits on it. A readback of a presented image
  (HelloWindow's `--metal-log`) goes through GENERAL and back.
- One queue: the device has a single `VkQueue` that every `MTLCommandQueue`, the utility
  submissions and the present all use (locked), so swap-chain images never change queue
  ownership. This keeps the single-device-queue rule the Direct3D 12 backend needs for
  composition back buffers, and makes the layout transitions plain barriers on one queue.

`MTKView` (`Sources/MetalKit/MTKView.swift`) asks the window for a surface the first time
it needs a drawable in a window with a presentable Vulkan device, keeps the surface at the
view's frame (clipped to the content view, re-placed when the frame or the backing scale
changes), and drops both chain and surface when the view leaves the window, is hidden, or
the device changes. The view's own `draw(_:)` still fills the clear colour into the window's
Cairo backing under the surface, so a window without a chain (the host backend, a headless
device, `APPKITWIN_METAL_READBACK=1`, a rejected format) shows the read-back frame there
instead: that is the software fallback, and the one path the host-backend tests use.

What the native surface cannot do, by construction: subviews of the `MTKView` composite
under it on Linux (the X child window and the subsurface are above the window's pixels),
where DirectComposition on Windows composites them above the chain's visual. Nothing in
HelloWindow but the device label is affected; a view that needs overlays over Metal
content draws them into the drawable. A Wayland FIFO present waits for the compositor's
frame callback, so a window the compositor does not show stalls that view's presents until
it is visible again (the display link only drives views in a window, and a hidden tab's
view leaves the hierarchy, dropping its chain).

## Testing

The container (`tools/linux/Dockerfile`) has no GPU. It installs Mesa's `lavapipe`
(`mesa-vulkan-drivers`, a CPU Vulkan 1.3 implementation), the loader, the headers,
`glslang-tools` and the validation layers, so the Vulkan device exists there and the
suite exercises it. `MetalVulkanPresentationTests` runs on the X11 backend under Xvfb
(`tools/linux/run.sh`, and the lavapipe CI job through `xvfb-run`) and on the Wayland
backend under the headless sway (`tools/linux/run-wayland.sh`): a cleared `MTKView` frame
presents through the chain, the window's pixels are read back from the X server
(`PlatformWindow.captureContent`, `XGetImage`) and checked at the view's centre and
corners, a resize re-creates the chain and draws at once, an unsupported format falls back
to readback and recovers; Wayland has no client-side readback, so there the scripts
screenshot HelloWindow's Metal tab with `--metal-static` (a fixed clear colour) through
`grim` and count the clear colour's pixels, as `run.sh` does with `xwd` under Xvfb. `MetalVulkanParityTests` runs the same scene (clears in unorm, float
and depth formats, uploads, texture and buffer copies, fills, a presented `MTKView`
frame) on the reference device and on the Vulkan device and compares every readback
within one level per channel; `MetalVulkanRenderTests` checks rasterization, depth,
stencil and blending against known pixels, since the reference device does not
rasterize. When `MTLVulkanDevice()` is nil they skip with a message. The macOS host build never declares the module and the
tests skip there, so `swift build && swift test` stay green. The suite must also stay
green in a container without the loader, which is the stub path above.

## Consequences

- Linux applications that use Metal get a GPU for buffers, textures, blits, compute,
  and (from stage 3) rasterization; `MTKView` keeps working with no GPU through the
  reference device.
- The binding model is the D3D12 one, so shaders need no per-platform `register`
  layout; `space1` structured buffers work on Vulkan first.
- `MTKView` presents through a `VkSwapchainKHR` on X11 and Wayland: no readback, the
  compositor shows the GPU's image; the readback path remains for windows without a
  native surface and for devices that cannot present.
- A native surface sits above the window's own pixels, so an `MTKView`'s subviews do not
  show over its frames on Linux (they do on Windows and macOS).
- Vulkan 1.3 is required (dynamic rendering and extended dynamic state keep the shim
  small). Older drivers fall back to the reference device rather than a partial path.
