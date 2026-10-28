// Direct3D 12 backend for the Metal module: placeholder until the implementation pull
// request lands (ADR-0004). Every creator returns NULL so Metal uses the reference device.

#include "cmetal_d3d12.h"
#include <cstring>

extern "C" {

CMDevice *cm_device_create(bool) { return nullptr; }
void cm_device_release(CMDevice *) {}
void cm_device_info(CMDevice *, CMDeviceInfo *info) { if (info) std::memset(info, 0, sizeof *info); }
bool cm_device_lost(CMDevice *) { return true; }

CMQueue *cm_queue_create(CMDevice *) { return nullptr; }
void cm_queue_release(CMQueue *) {}
uint64_t cm_queue_signal(CMQueue *) { return 0; }
bool cm_queue_fence_reached(CMQueue *, uint64_t) { return true; }
void cm_queue_wait(CMQueue *, uint64_t) {}

CMBuffer *cm_buffer_create(CMDevice *, uint64_t) { return nullptr; }
void cm_buffer_release(CMBuffer *) {}
void *cm_buffer_map(CMBuffer *) { return nullptr; }
uint64_t cm_buffer_gpu_address(CMBuffer *) { return 0; }

CMTexture *cm_texture_create(CMDevice *, uint32_t, uint32_t, uint32_t, uint32_t, bool, bool) { return nullptr; }
void cm_texture_release(CMTexture *) {}
bool cm_texture_upload(CMDevice *, CMQueue *, CMTexture *, uint32_t, const void *, uint32_t, uint32_t) { return false; }
bool cm_texture_read(CMDevice *, CMQueue *, CMTexture *, void *, uint32_t, uint32_t) { return false; }

CMShader *cm_shader_compile_hlsl(const char *, uint32_t, const char *, const char *, char *errorOut, uint32_t errorCapacity) {
    if (errorOut && errorCapacity) { std::strncpy(errorOut, "D3D12 backend not built yet", errorCapacity - 1); errorOut[errorCapacity - 1] = 0; }
    return nullptr;
}
CMShader *cm_shader_from_blob(const void *, uint32_t) { return nullptr; }
void cm_shader_release(CMShader *) {}

CMPipeline *cm_pipeline_create(CMDevice *, const CMPipelineDesc *, char *errorOut, uint32_t errorCapacity) {
    if (errorOut && errorCapacity) { std::strncpy(errorOut, "D3D12 backend not built yet", errorCapacity - 1); errorOut[errorCapacity - 1] = 0; }
    return nullptr;
}
void cm_pipeline_release(CMPipeline *) {}

CMCommandList *cm_commandlist_create(CMDevice *) { return nullptr; }
void cm_commandlist_release(CMCommandList *) {}
void cm_commandlist_reset(CMCommandList *) {}
void cm_commandlist_begin_render_pass(CMCommandList *, CMTexture **, const uint32_t *, const float *, uint32_t, CMTexture *, uint32_t, float) {}
void cm_commandlist_end_render_pass(CMCommandList *) {}
void cm_commandlist_set_pipeline(CMCommandList *, CMPipeline *) {}
void cm_commandlist_set_viewport(CMCommandList *, float, float, float, float, float, float) {}
void cm_commandlist_set_scissor(CMCommandList *, int32_t, int32_t, int32_t, int32_t) {}
void cm_commandlist_set_vertex_buffer(CMCommandList *, uint32_t, CMBuffer *, uint64_t, uint32_t) {}
void cm_commandlist_set_shader_buffer(CMCommandList *, bool, uint32_t, CMBuffer *, uint64_t) {}
void cm_commandlist_set_shader_texture(CMCommandList *, bool, uint32_t, CMTexture *) {}
void cm_commandlist_set_sampler(CMCommandList *, bool, uint32_t, uint32_t, uint32_t, uint32_t) {}
void cm_commandlist_draw(CMCommandList *, uint32_t, uint32_t, uint32_t, uint32_t) {}
void cm_commandlist_draw_indexed(CMCommandList *, uint32_t, uint32_t, bool, CMBuffer *, uint64_t, uint32_t) {}
void cm_commandlist_copy_buffer(CMCommandList *, CMBuffer *, uint64_t, CMBuffer *, uint64_t, uint64_t) {}
void cm_commandlist_copy_texture(CMCommandList *, CMTexture *, CMTexture *) {}
uint64_t cm_commandlist_execute(CMCommandList *, CMQueue *) { return 0; }

CMSwapChain *cm_swapchain_create(CMDevice *, CMQueue *, void *, uint32_t, uint32_t, uint32_t, uint32_t) { return nullptr; }
void cm_swapchain_release(CMSwapChain *) {}
bool cm_swapchain_resize(CMSwapChain *, uint32_t, uint32_t) { return false; }
CMTexture *cm_swapchain_acquire(CMSwapChain *) { return nullptr; }
bool cm_swapchain_present(CMSwapChain *, bool) { return false; }

}
