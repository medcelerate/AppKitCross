// C interface of the Direct3D 12 backend for the Metal module (ADR-0004).
//
// Opaque handles wrap COM objects; every call takes the handle it operates on. The
// implementation (cmetal_d3d12.cpp) lands in its own pull request from the Windows
// machine; until then every creator returns NULL and the Metal module falls back to the
// reference device.

#ifndef CMETAL_D3D12_H
#define CMETAL_D3D12_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CMDevice CMDevice;
typedef struct CMQueue CMQueue;
typedef struct CMCommandList CMCommandList;
typedef struct CMBuffer CMBuffer;
typedef struct CMTexture CMTexture;
typedef struct CMShader CMShader;         // compiled DXIL/DXBC blob for one entry point
typedef struct CMPipeline CMPipeline;
typedef struct CMSwapChain CMSwapChain;

typedef struct CMDeviceInfo {
    char name[128];
    uint64_t dedicatedVideoMemory;
    bool isSoftware;      // WARP
    bool isLowPower;
} CMDeviceInfo;

/// Creates a D3D12 device on the default adapter (debug layer when `debug`).
CMDevice *cm_device_create(bool debug);
void cm_device_release(CMDevice *device);
void cm_device_info(CMDevice *device, CMDeviceInfo *info);
bool cm_device_lost(CMDevice *device);

/// Direct command queue with a fence for completion tracking.
CMQueue *cm_queue_create(CMDevice *device);
void cm_queue_release(CMQueue *queue);
/// Signals the queue's fence; returns the value to wait for.
uint64_t cm_queue_signal(CMQueue *queue);
bool cm_queue_fence_reached(CMQueue *queue, uint64_t value);
void cm_queue_wait(CMQueue *queue, uint64_t value);

/// Buffers live in an upload heap (CPU-writable, GPU-readable): `storageModeShared`.
CMBuffer *cm_buffer_create(CMDevice *device, uint64_t length);
void cm_buffer_release(CMBuffer *buffer);
void *cm_buffer_map(CMBuffer *buffer);
uint64_t cm_buffer_gpu_address(CMBuffer *buffer);

/// 2D textures as committed resources. `dxgiFormat` is DXGI_FORMAT; `renderTarget`
/// adds an RTV (or DSV for depth formats), `shaderRead` an SRV.
CMTexture *cm_texture_create(CMDevice *device, uint32_t width, uint32_t height, uint32_t mipLevels, uint32_t dxgiFormat, bool renderTarget, bool shaderRead);
void cm_texture_release(CMTexture *texture);
/// Uploads rows through a staging buffer and a copy on `queue` (synchronous).
bool cm_texture_upload(CMDevice *device, CMQueue *queue, CMTexture *texture, uint32_t level, const void *rows, uint32_t bytesPerRow, uint32_t height);
/// Reads level 0 back into `out` (synchronous).
bool cm_texture_read(CMDevice *device, CMQueue *queue, CMTexture *texture, void *out, uint32_t bytesPerRow, uint32_t height);

/// Compiles HLSL (`profile` such as "vs_6_0" / "ps_6_0", falling back to 5_1 with
/// D3DCompile when dxcompiler.dll is absent). Error text is copied into `errorOut`.
CMShader *cm_shader_compile_hlsl(const char *source, uint32_t sourceLength, const char *entryPoint, const char *profile, char *errorOut, uint32_t errorCapacity);
/// Wraps a precompiled DXIL/DXBC blob.
CMShader *cm_shader_from_blob(const void *bytes, uint32_t length);
void cm_shader_release(CMShader *shader);

typedef struct CMVertexAttribute { uint32_t semanticIndex; uint32_t dxgiFormat; uint32_t bufferIndex; uint32_t offset; } CMVertexAttribute;
typedef struct CMVertexLayout { uint32_t stride; bool perInstance; } CMVertexLayout;
typedef struct CMBlend {
    bool enabled;
    uint32_t srcRGB, dstRGB, opRGB, srcAlpha, dstAlpha, opAlpha;   // D3D12_BLEND / D3D12_BLEND_OP
    uint8_t writeMask;                                             // D3D12_COLOR_WRITE_ENABLE
} CMBlend;
typedef struct CMPipelineDesc {
    CMShader *vertex;
    CMShader *fragment;                       // may be NULL (depth-only)
    uint32_t colorFormats[8];                 // DXGI_FORMAT, 0 = unused
    CMBlend blends[8];
    uint32_t depthFormat;                     // DXGI_FORMAT or 0
    bool depthWrite;
    uint32_t depthCompare;                    // D3D12_COMPARISON_FUNC
    uint32_t cullMode;                        // D3D12_CULL_MODE
    bool frontCounterClockwise;
    bool wireframe;
    uint32_t topologyType;                    // D3D12_PRIMITIVE_TOPOLOGY_TYPE
    const CMVertexAttribute *attributes;
    uint32_t attributeCount;
    const CMVertexLayout *layouts;
    uint32_t layoutCount;
    uint32_t sampleCount;
} CMPipelineDesc;

/// Graphics PSO with a root signature of: b0..b7 CBVs/SRVs for buffers (vertex and pixel),
/// t0..t7 textures, s0..s7 static-less samplers via a descriptor heap.
CMPipeline *cm_pipeline_create(CMDevice *device, const CMPipelineDesc *desc, char *errorOut, uint32_t errorCapacity);
void cm_pipeline_release(CMPipeline *pipeline);

/// Command lists: one per MTLCommandBuffer, recorded on the CPU and executed on commit.
CMCommandList *cm_commandlist_create(CMDevice *device);
void cm_commandlist_release(CMCommandList *list);
void cm_commandlist_reset(CMCommandList *list);
/// Begins a render pass: transitions targets, binds RTVs/DSV, clears per `loadAction`.
void cm_commandlist_begin_render_pass(CMCommandList *list, CMTexture **colors, const uint32_t *loadActions, const float *clearColors /* 4 per target */, uint32_t colorCount,
                                      CMTexture *depth, uint32_t depthLoadAction, float clearDepth);
void cm_commandlist_end_render_pass(CMCommandList *list);
void cm_commandlist_set_pipeline(CMCommandList *list, CMPipeline *pipeline);
void cm_commandlist_set_viewport(CMCommandList *list, float x, float y, float w, float h, float zmin, float zmax);
void cm_commandlist_set_scissor(CMCommandList *list, int32_t x, int32_t y, int32_t w, int32_t h);
void cm_commandlist_set_vertex_buffer(CMCommandList *list, uint32_t slot, CMBuffer *buffer, uint64_t offset, uint32_t stride);
void cm_commandlist_set_shader_buffer(CMCommandList *list, bool pixelStage, uint32_t slot, CMBuffer *buffer, uint64_t offset);
void cm_commandlist_set_shader_texture(CMCommandList *list, bool pixelStage, uint32_t slot, CMTexture *texture);
void cm_commandlist_set_sampler(CMCommandList *list, bool pixelStage, uint32_t slot, uint32_t filter, uint32_t addressU, uint32_t addressV);
void cm_commandlist_draw(CMCommandList *list, uint32_t topology, uint32_t vertexStart, uint32_t vertexCount, uint32_t instanceCount);
void cm_commandlist_draw_indexed(CMCommandList *list, uint32_t topology, uint32_t indexCount, bool index32, CMBuffer *indexBuffer, uint64_t indexOffset, uint32_t instanceCount);
void cm_commandlist_copy_buffer(CMCommandList *list, CMBuffer *src, uint64_t srcOffset, CMBuffer *dst, uint64_t dstOffset, uint64_t size);
void cm_commandlist_copy_texture(CMCommandList *list, CMTexture *src, CMTexture *dst);
/// Copies a `width` x `height` region of level 0 from (`srcX`, `srcY`) to (`dstX`, `dstY`).
void cm_commandlist_copy_texture_region(CMCommandList *list, CMTexture *src, uint32_t srcX, uint32_t srcY, CMTexture *dst, uint32_t dstX, uint32_t dstY, uint32_t width, uint32_t height);
/// Closes the list and executes it on `queue`; returns the fence value that completes it.
uint64_t cm_commandlist_execute(CMCommandList *list, CMQueue *queue);

/// Swap chain on an HWND for CAMetalLayer: `cm_swapchain_acquire` returns the current
/// back buffer as a texture, `cm_swapchain_present` presents it (vsync when `vsync`).
CMSwapChain *cm_swapchain_create(CMDevice *device, CMQueue *queue, void *hwnd, uint32_t width, uint32_t height, uint32_t dxgiFormat, uint32_t bufferCount);
/// Flip-model swap chain for DirectComposition (`CreateSwapChainForComposition`,
/// FLIP_SEQUENTIAL so a presented buffer keeps its pixels for readback): no HWND, the
/// caller shows `cm_swapchain_native` as the content of a composition visual. `opaque`
/// picks DXGI_ALPHA_MODE_IGNORE over PREMULTIPLIED.
CMSwapChain *cm_swapchain_create_composition(CMDevice *device, CMQueue *queue, uint32_t width, uint32_t height, uint32_t dxgiFormat, uint32_t bufferCount, bool opaque);
/// The IDXGISwapChain1 (not AddRef'd) for IDCompositionVisual::SetContent.
void *cm_swapchain_native(CMSwapChain *swapChain);
void cm_swapchain_release(CMSwapChain *swapChain);
bool cm_swapchain_resize(CMSwapChain *swapChain, uint32_t width, uint32_t height);
CMTexture *cm_swapchain_acquire(CMSwapChain *swapChain);
bool cm_swapchain_present(CMSwapChain *swapChain, bool vsync);

#ifdef __cplusplus
}
#endif

#endif
