// C interface of the Vulkan backend for the Metal module on Linux (ADR-0011).
//
// Opaque handles wrap Vulkan objects; every call takes the handle it operates on. The
// loader (`libvulkan.so.1`) is dlopen'ed at runtime, so nothing links against Vulkan:
// `cmv_device_create` returns NULL when there is no loader, no suitable device, or the
// headers were absent at build time, and the Metal module falls back to the reference
// device. Enumeration values are Vulkan's (VkFormat, VkBlendFactor, VkCompareOp, ...)
// except where noted; the Swift side maps Metal's enums to them.

#ifndef CMETAL_VULKAN_H
#define CMETAL_VULKAN_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CMVDevice CMVDevice;
typedef struct CMVQueue CMVQueue;
typedef struct CMVCommandList CMVCommandList;
typedef struct CMVBuffer CMVBuffer;
typedef struct CMVTexture CMVTexture;
typedef struct CMVShader CMVShader;         // VkShaderModule plus one entry point
typedef struct CMVPipeline CMVPipeline;     // graphics or compute VkPipeline
typedef struct CMVSampler CMVSampler;

typedef struct CMVDeviceInfo {
    char name[256];
    uint64_t deviceLocalMemory;
    uint32_t apiVersion;              // VK_API_VERSION of the physical device
    uint32_t vendorID, deviceID;
    bool isSoftware;                  // VK_PHYSICAL_DEVICE_TYPE_CPU (lavapipe, SwiftShader)
    bool isIntegrated;
    bool presentable;                 // VK_KHR_swapchain is available on the device
    bool validation;                  // the validation layer was enabled
    uint32_t maxComputeWorkGroupInvocations;
    uint32_t maxComputeWorkGroupSize[3];
    uint32_t subgroupSize;
    uint32_t minUniformBufferOffsetAlignment;
    uint32_t minStorageBufferOffsetAlignment;
    uint32_t maxVertexInputBindings;
} CMVDeviceInfo;

/// True when the loader could be dlopen'ed (this does not create an instance).
bool cmv_available(void);
/// Why the last `cmv_device_create` returned NULL (static storage).
const char *cmv_last_error(void);

/// Creates an instance and a logical device on the best physical device with a queue
/// family that supports graphics and compute, requiring Vulkan 1.3. `debug` enables the
/// validation layer and debug-utils messages to stderr when the loader has them.
CMVDevice *cmv_device_create(bool debug);
void cmv_device_release(CMVDevice *device);
void cmv_device_info(CMVDevice *device, CMVDeviceInfo *info);
bool cmv_device_lost(CMVDevice *device);
/// Whether `vkFormat` can be a sampled 2D image with optimal tiling (and a colour or
/// depth attachment when `attachment`).
bool cmv_device_supports_format(CMVDevice *device, uint32_t vkFormat, bool attachment);
void cmv_device_wait_idle(CMVDevice *device);

/// Queues share the device's graphics/compute VkQueue (locked); each has its own fence ring.
CMVQueue *cmv_queue_create(CMVDevice *device);
void cmv_queue_release(CMVQueue *queue);
/// Submits an empty batch with a fence; returns the value `cmv_queue_wait` takes.
uint64_t cmv_queue_signal(CMVQueue *queue);
bool cmv_queue_fence_reached(CMVQueue *queue, uint64_t value);
void cmv_queue_wait(CMVQueue *queue, uint64_t value);

/// Buffers live in host-visible, host-coherent memory, persistently mapped
/// (`storageModeShared`), usable as vertex, index, uniform, storage and transfer buffers.
CMVBuffer *cmv_buffer_create(CMVDevice *device, uint64_t length);
void cmv_buffer_release(CMVBuffer *buffer);
void *cmv_buffer_map(CMVBuffer *buffer);
uint64_t cmv_buffer_length(CMVBuffer *buffer);

enum { CMV_TEXTURE_SHADER_READ = 1, CMV_TEXTURE_SHADER_WRITE = 2, CMV_TEXTURE_RENDER_TARGET = 4 };

/// 2D images (optimal tiling, device-local) kept in VK_IMAGE_LAYOUT_GENERAL, with one
/// view over every level. `usage` is a mask of CMV_TEXTURE_*; transfer usage is implied.
CMVTexture *cmv_texture_create(CMVDevice *device, uint32_t width, uint32_t height, uint32_t mipLevels, uint32_t vkFormat, uint32_t usage, uint32_t sampleCount);
void cmv_texture_release(CMVTexture *texture);
uint32_t cmv_texture_format(CMVTexture *texture);
/// Uploads `height` rows of a region of `level` through a staging buffer on the device's
/// utility queue (synchronous). `bytesPerRow` must be a multiple of the texel size.
bool cmv_texture_upload(CMVDevice *device, CMVTexture *texture, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height, const void *rows, uint32_t bytesPerRow);
/// Reads a region of `level` back into `out` (synchronous).
bool cmv_texture_read(CMVDevice *device, CMVTexture *texture, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height, void *out, uint32_t bytesPerRow);

/// Wraps a SPIR-V module; `stage` is a VkShaderStageFlagBits value (vertex 1, fragment
/// 16, compute 32). Error text is copied into `errorOut`.
CMVShader *cmv_shader_from_spirv(CMVDevice *device, const void *words, uint32_t length, const char *entryPoint, uint32_t stage, char *errorOut, uint32_t errorCapacity);
void cmv_shader_release(CMVShader *shader);

/// Filters are VkFilter (0 nearest, 1 linear), `mipMode` VkSamplerMipmapMode, address
/// modes VkSamplerAddressMode, `compareOp` VkCompareOp (used when `compare`).
CMVSampler *cmv_sampler_create(CMVDevice *device, uint32_t minFilter, uint32_t magFilter, uint32_t mipMode, uint32_t addressU, uint32_t addressV, uint32_t addressW,
                               bool compare, uint32_t compareOp, float lodMin, float lodMax, uint32_t maxAnisotropy, uint32_t borderColor);
void cmv_sampler_release(CMVSampler *sampler);

typedef struct CMVVertexAttribute { uint32_t location; uint32_t vkFormat; uint32_t binding; uint32_t offset; } CMVVertexAttribute;
typedef struct CMVVertexLayout { uint32_t binding; uint32_t stride; bool perInstance; } CMVVertexLayout;
typedef struct CMVBlend {
    bool enabled;
    uint32_t srcRGB, dstRGB, opRGB, srcAlpha, dstAlpha, opAlpha;   // VkBlendFactor / VkBlendOp
    uint8_t writeMask;                                             // VkColorComponentFlags (R 1, G 2, B 4, A 8)
} CMVBlend;
typedef struct CMVPipelineDesc {
    CMVShader *vertex;
    CMVShader *fragment;                      // may be NULL (depth-only)
    uint32_t colorFormats[8];                 // VkFormat, 0 = unused
    CMVBlend blends[8];
    uint32_t depthFormat;                     // VkFormat or 0
    uint32_t stencilFormat;                   // VkFormat or 0 (same image as depth when both)
    uint32_t topologyClass;                   // 0 point, 1 line, 2 triangle (the draw's topology is dynamic)
    bool wireframe;
    bool alphaToCoverage;
    bool alphaToOne;
    bool rasterizationEnabled;
    const CMVVertexAttribute *attributes;
    uint32_t attributeCount;
    const CMVVertexLayout *layouts;
    uint32_t layoutCount;
    uint32_t sampleCount;
} CMVPipelineDesc;

/// Graphics pipeline over the shared pipeline layout (ADR-0011 binding model). Viewport,
/// scissor, topology, cull mode, front face, depth/stencil state, stencil masks and
/// reference, and blend constants are dynamic.
CMVPipeline *cmv_pipeline_create(CMVDevice *device, const CMVPipelineDesc *desc, char *errorOut, uint32_t errorCapacity);
CMVPipeline *cmv_compute_pipeline_create(CMVDevice *device, CMVShader *kernel, char *errorOut, uint32_t errorCapacity);
void cmv_pipeline_release(CMVPipeline *pipeline);

/// Command lists: one per MTLCommandBuffer, recorded on the CPU and executed on commit.
/// `stage` in the binding calls is 0 for the vertex/kernel half of the binding model and
/// 1 for the fragment half. Load actions are Metal's (0 dontCare, 1 load, 2 clear);
/// store actions are Metal's (0 dontCare, 1 store; resolve variants store).
CMVCommandList *cmv_commandlist_create(CMVDevice *device);
void cmv_commandlist_release(CMVCommandList *list);
void cmv_commandlist_reset(CMVCommandList *list);
void cmv_commandlist_begin_render_pass(CMVCommandList *list, CMVTexture **colors, const uint32_t *loadActions, const uint32_t *storeActions, const float *clearColors /* 4 per target */, uint32_t colorCount,
                                       CMVTexture *depth, uint32_t depthLoadAction, uint32_t depthStoreAction, float clearDepth,
                                       CMVTexture *stencil, uint32_t stencilLoadAction, uint32_t stencilStoreAction, uint32_t clearStencil);
void cmv_commandlist_end_render_pass(CMVCommandList *list);
/// Forgets every shader buffer, texture and sampler binding (a new encoder starts empty).
void cmv_commandlist_clear_bindings(CMVCommandList *list);
void cmv_commandlist_set_pipeline(CMVCommandList *list, CMVPipeline *pipeline);
void cmv_commandlist_set_viewport(CMVCommandList *list, float x, float y, float w, float h, float zmin, float zmax);
void cmv_commandlist_set_scissor(CMVCommandList *list, int32_t x, int32_t y, int32_t w, int32_t h);
void cmv_commandlist_set_cull_mode(CMVCommandList *list, uint32_t vkCullMode);
void cmv_commandlist_set_front_face(CMVCommandList *list, uint32_t vkFrontFace);
void cmv_commandlist_set_depth_state(CMVCommandList *list, bool testEnabled, bool writeEnabled, uint32_t compareOp);
void cmv_commandlist_set_stencil_state(CMVCommandList *list, bool enabled,
                                       uint32_t frontFail, uint32_t frontPass, uint32_t frontDepthFail, uint32_t frontCompare, uint32_t frontReadMask, uint32_t frontWriteMask,
                                       uint32_t backFail, uint32_t backPass, uint32_t backDepthFail, uint32_t backCompare, uint32_t backReadMask, uint32_t backWriteMask);
void cmv_commandlist_set_stencil_reference(CMVCommandList *list, uint32_t reference);
void cmv_commandlist_set_blend_constants(CMVCommandList *list, float r, float g, float b, float a);
void cmv_commandlist_set_vertex_buffer(CMVCommandList *list, uint32_t binding, CMVBuffer *buffer, uint64_t offset);
void cmv_commandlist_set_shader_buffer(CMVCommandList *list, uint32_t stage, uint32_t slot, CMVBuffer *buffer, uint64_t offset);
void cmv_commandlist_set_shader_texture(CMVCommandList *list, uint32_t stage, uint32_t slot, CMVTexture *texture);
void cmv_commandlist_set_sampler(CMVCommandList *list, uint32_t stage, uint32_t slot, CMVSampler *sampler);
void cmv_commandlist_draw(CMVCommandList *list, uint32_t vkTopology, uint32_t vertexStart, uint32_t vertexCount, uint32_t instanceCount);
void cmv_commandlist_draw_indexed(CMVCommandList *list, uint32_t vkTopology, uint32_t indexCount, bool index32, CMVBuffer *indexBuffer, uint64_t indexOffset, uint32_t instanceCount);
void cmv_commandlist_dispatch(CMVCommandList *list, uint32_t x, uint32_t y, uint32_t z);
void cmv_commandlist_copy_buffer(CMVCommandList *list, CMVBuffer *src, uint64_t srcOffset, CMVBuffer *dst, uint64_t dstOffset, uint64_t size);
void cmv_commandlist_fill_buffer(CMVCommandList *list, CMVBuffer *dst, uint64_t offset, uint64_t size, uint8_t value);
void cmv_commandlist_copy_texture(CMVCommandList *list, CMVTexture *src, uint32_t srcLevel, uint32_t sx, uint32_t sy, CMVTexture *dst, uint32_t dstLevel, uint32_t dx, uint32_t dy, uint32_t width, uint32_t height);
void cmv_commandlist_copy_buffer_to_texture(CMVCommandList *list, CMVBuffer *src, uint64_t srcOffset, uint32_t bytesPerRow, CMVTexture *dst, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height);
void cmv_commandlist_copy_texture_to_buffer(CMVCommandList *list, CMVTexture *src, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height, CMVBuffer *dst, uint64_t dstOffset, uint32_t bytesPerRow);
void cmv_commandlist_generate_mipmaps(CMVCommandList *list, CMVTexture *texture);
/// Ends recording and submits on `queue`; returns the fence value that completes it.
uint64_t cmv_commandlist_execute(CMVCommandList *list, CMVQueue *queue);

#ifdef __cplusplus
}
#endif

#endif
