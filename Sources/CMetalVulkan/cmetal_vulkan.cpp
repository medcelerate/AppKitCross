// Vulkan backend for the Metal module on Linux (ADR-0012): the implementation of
// cmetal_vulkan.h. The loader is dlopen'ed and every entry point resolved through
// vkGetInstanceProcAddr, so this file has no link-time Vulkan dependency. Without the
// headers it compiles to stubs whose creators return NULL.

#include "cmetal_vulkan.h"

#include <cstdio>
#include <cstring>
#include <string>

static char g_lastError[512] = "";
static void setError(const char *message) { snprintf(g_lastError, sizeof g_lastError, "%s", message); }
const char *cmv_last_error(void) { return g_lastError; }

#if __has_include(<vulkan/vulkan.h>)

#define VK_NO_PROTOTYPES 1
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <mutex>
#include <set>
#include <vector>

// MARK: Loader

#define CMV_FUNCTIONS(X) \
    X(vkCreateInstance) X(vkDestroyInstance) X(vkEnumerateInstanceLayerProperties) X(vkEnumerateInstanceExtensionProperties) \
    X(vkEnumeratePhysicalDevices) X(vkGetPhysicalDeviceProperties) X(vkGetPhysicalDeviceProperties2) X(vkGetPhysicalDeviceQueueFamilyProperties) \
    X(vkGetPhysicalDeviceMemoryProperties) X(vkGetPhysicalDeviceFeatures) X(vkGetPhysicalDeviceFormatProperties) X(vkEnumerateDeviceExtensionProperties) \
    X(vkCreateDevice) X(vkDestroyDevice) X(vkGetDeviceQueue) X(vkDeviceWaitIdle) X(vkQueueSubmit) X(vkQueueWaitIdle) \
    X(vkCreateFence) X(vkDestroyFence) X(vkResetFences) X(vkGetFenceStatus) X(vkWaitForFences) \
    X(vkCreateBuffer) X(vkDestroyBuffer) X(vkGetBufferMemoryRequirements) X(vkAllocateMemory) X(vkFreeMemory) X(vkBindBufferMemory) X(vkMapMemory) X(vkUnmapMemory) \
    X(vkCreateImage) X(vkDestroyImage) X(vkGetImageMemoryRequirements) X(vkBindImageMemory) X(vkCreateImageView) X(vkDestroyImageView) \
    X(vkCreateShaderModule) X(vkDestroyShaderModule) X(vkCreateSampler) X(vkDestroySampler) \
    X(vkCreateDescriptorSetLayout) X(vkDestroyDescriptorSetLayout) X(vkCreatePipelineLayout) X(vkDestroyPipelineLayout) \
    X(vkCreateGraphicsPipelines) X(vkCreateComputePipelines) X(vkDestroyPipeline) \
    X(vkCreateDescriptorPool) X(vkDestroyDescriptorPool) X(vkResetDescriptorPool) X(vkAllocateDescriptorSets) X(vkUpdateDescriptorSets) \
    X(vkCreateCommandPool) X(vkDestroyCommandPool) X(vkResetCommandPool) X(vkAllocateCommandBuffers) X(vkFreeCommandBuffers) \
    X(vkBeginCommandBuffer) X(vkEndCommandBuffer) X(vkResetCommandBuffer) \
    X(vkCmdPipelineBarrier) X(vkCmdCopyBuffer) X(vkCmdCopyImage) X(vkCmdCopyBufferToImage) X(vkCmdCopyImageToBuffer) X(vkCmdFillBuffer) X(vkCmdBlitImage) \
    X(vkCmdBeginRendering) X(vkCmdEndRendering) X(vkCmdBindPipeline) X(vkCmdBindDescriptorSets) X(vkCmdBindVertexBuffers) X(vkCmdBindIndexBuffer) \
    X(vkCmdDraw) X(vkCmdDrawIndexed) X(vkCmdDispatch) \
    X(vkCmdSetViewport) X(vkCmdSetScissor) X(vkCmdSetPrimitiveTopology) X(vkCmdSetCullMode) X(vkCmdSetFrontFace) \
    X(vkCmdSetDepthTestEnable) X(vkCmdSetDepthWriteEnable) X(vkCmdSetDepthCompareOp) X(vkCmdSetStencilTestEnable) X(vkCmdSetStencilOp) \
    X(vkCmdSetStencilCompareMask) X(vkCmdSetStencilWriteMask) X(vkCmdSetStencilReference) X(vkCmdSetBlendConstants)

struct Vk {
#define CMV_DECLARE(name) PFN_##name name = nullptr;
    CMV_FUNCTIONS(CMV_DECLARE)
#undef CMV_DECLARE
    PFN_vkGetInstanceProcAddr getInstanceProcAddr = nullptr;
    PFN_vkCreateDebugUtilsMessengerEXT createDebugUtilsMessengerEXT = nullptr;
    PFN_vkDestroyDebugUtilsMessengerEXT destroyDebugUtilsMessengerEXT = nullptr;
    // Presentation (VK_KHR_surface / VK_KHR_swapchain and the window-system surfaces),
    // resolved when the instance has them; NULL otherwise.
    PFN_vkDestroySurfaceKHR destroySurfaceKHR = nullptr;
    PFN_vkGetPhysicalDeviceSurfaceSupportKHR getPhysicalDeviceSurfaceSupportKHR = nullptr;
    PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR getPhysicalDeviceSurfaceCapabilitiesKHR = nullptr;
    PFN_vkGetPhysicalDeviceSurfaceFormatsKHR getPhysicalDeviceSurfaceFormatsKHR = nullptr;
    PFN_vkGetPhysicalDeviceSurfacePresentModesKHR getPhysicalDeviceSurfacePresentModesKHR = nullptr;
    PFN_vkCreateSwapchainKHR createSwapchainKHR = nullptr;
    PFN_vkDestroySwapchainKHR destroySwapchainKHR = nullptr;
    PFN_vkGetSwapchainImagesKHR getSwapchainImagesKHR = nullptr;
    PFN_vkAcquireNextImageKHR acquireNextImageKHR = nullptr;
    PFN_vkQueuePresentKHR queuePresentKHR = nullptr;
    PFN_vkCreateSemaphore createSemaphore = nullptr;
    PFN_vkDestroySemaphore destroySemaphore = nullptr;
    // The Xlib and Wayland surface creators take platform structs; they are declared here
    // so the shim needs neither <X11/Xlib.h> nor <wayland-client.h> (the window backend
    // hands over the Display*/Window and wl_display*/wl_surface* as plain pointers).
    PFN_vkVoidFunction createXlibSurfaceKHR = nullptr;
    PFN_vkVoidFunction createWaylandSurfaceKHR = nullptr;
};
struct CMVXlibSurfaceCreateInfo { VkStructureType sType; const void *pNext; VkFlags flags; void *dpy; unsigned long window; };
struct CMVWaylandSurfaceCreateInfo { VkStructureType sType; const void *pNext; VkFlags flags; void *display; void *surface; };
typedef VkResult (VKAPI_PTR *CMVCreateXlibSurface)(VkInstance, const CMVXlibSurfaceCreateInfo *, const VkAllocationCallbacks *, VkSurfaceKHR *);
typedef VkResult (VKAPI_PTR *CMVCreateWaylandSurface)(VkInstance, const CMVWaylandSurfaceCreateInfo *, const VkAllocationCallbacks *, VkSurfaceKHR *);
static const VkStructureType kXlibSurfaceCreateInfo = (VkStructureType)1000004000;      // VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR
static const VkStructureType kWaylandSurfaceCreateInfo = (VkStructureType)1000006000;   // VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR
static Vk vk;
static void *g_loader = nullptr;
static std::mutex g_loaderMutex;

static bool loadLoader() {
    std::lock_guard<std::mutex> lock(g_loaderMutex);
    if (g_loader) return true;
    const char *names[] = {"libvulkan.so.1", "libvulkan.so"};
    for (const char *n : names) {
        g_loader = dlopen(n, RTLD_NOW | RTLD_LOCAL);
        if (g_loader) break;
    }
    if (!g_loader) { setError("no Vulkan loader (libvulkan.so.1) could be loaded"); return false; }
    vk.getInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(g_loader, "vkGetInstanceProcAddr");
    if (!vk.getInstanceProcAddr) { setError("vkGetInstanceProcAddr missing from the loader"); dlclose(g_loader); g_loader = nullptr; return false; }
    vk.vkCreateInstance = (PFN_vkCreateInstance)vk.getInstanceProcAddr(nullptr, "vkCreateInstance");
    vk.vkEnumerateInstanceLayerProperties = (PFN_vkEnumerateInstanceLayerProperties)vk.getInstanceProcAddr(nullptr, "vkEnumerateInstanceLayerProperties");
    vk.vkEnumerateInstanceExtensionProperties = (PFN_vkEnumerateInstanceExtensionProperties)vk.getInstanceProcAddr(nullptr, "vkEnumerateInstanceExtensionProperties");
    return vk.vkCreateInstance != nullptr;
}

static bool loadInstanceFunctions(VkInstance instance) {
    bool ok = true;
    // Global commands (vkCreateInstance and the enumerations) are only resolvable with a NULL instance.
#define CMV_LOAD(name) vk.name = (PFN_##name)vk.getInstanceProcAddr(instance, #name); if (!vk.name) vk.name = (PFN_##name)vk.getInstanceProcAddr(nullptr, #name); if (!vk.name) { setError("missing " #name " (Vulkan 1.3 is required)"); ok = false; }
    CMV_FUNCTIONS(CMV_LOAD)
#undef CMV_LOAD
    vk.createDebugUtilsMessengerEXT = (PFN_vkCreateDebugUtilsMessengerEXT)vk.getInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    vk.destroyDebugUtilsMessengerEXT = (PFN_vkDestroyDebugUtilsMessengerEXT)vk.getInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
#define CMV_LOAD_OPTIONAL(field, name) vk.field = (decltype(vk.field))vk.getInstanceProcAddr(instance, name);
    CMV_LOAD_OPTIONAL(destroySurfaceKHR, "vkDestroySurfaceKHR")
    CMV_LOAD_OPTIONAL(getPhysicalDeviceSurfaceSupportKHR, "vkGetPhysicalDeviceSurfaceSupportKHR")
    CMV_LOAD_OPTIONAL(getPhysicalDeviceSurfaceCapabilitiesKHR, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR")
    CMV_LOAD_OPTIONAL(getPhysicalDeviceSurfaceFormatsKHR, "vkGetPhysicalDeviceSurfaceFormatsKHR")
    CMV_LOAD_OPTIONAL(getPhysicalDeviceSurfacePresentModesKHR, "vkGetPhysicalDeviceSurfacePresentModesKHR")
    CMV_LOAD_OPTIONAL(createSwapchainKHR, "vkCreateSwapchainKHR")
    CMV_LOAD_OPTIONAL(destroySwapchainKHR, "vkDestroySwapchainKHR")
    CMV_LOAD_OPTIONAL(getSwapchainImagesKHR, "vkGetSwapchainImagesKHR")
    CMV_LOAD_OPTIONAL(acquireNextImageKHR, "vkAcquireNextImageKHR")
    CMV_LOAD_OPTIONAL(queuePresentKHR, "vkQueuePresentKHR")
    CMV_LOAD_OPTIONAL(createSemaphore, "vkCreateSemaphore")
    CMV_LOAD_OPTIONAL(destroySemaphore, "vkDestroySemaphore")
    CMV_LOAD_OPTIONAL(createXlibSurfaceKHR, "vkCreateXlibSurfaceKHR")
    CMV_LOAD_OPTIONAL(createWaylandSurfaceKHR, "vkCreateWaylandSurfaceKHR")
#undef CMV_LOAD_OPTIONAL
    return ok;
}

bool cmv_available(void) { return loadLoader(); }

// MARK: Objects

struct CMVBuffer {
    CMVDevice *device;
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    void *mapped = nullptr;
    uint64_t length = 0;
};

struct CMVTexture {
    CMVDevice *device;
    VkImage image = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkFormat format = VK_FORMAT_UNDEFINED;
    VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT;
    uint32_t width = 0, height = 0, levels = 1, samples = 1;
    uint32_t texelSize = 4;
    bool storage = false;
    /// GENERAL for the image's whole life (ADR-0012), except swap-chain images, which sit
    /// in PRESENT_SRC_KHR between a present and the next acquire.
    VkImageLayout layout = VK_IMAGE_LAYOUT_GENERAL;
    /// False for swap-chain images: the chain owns the VkImage, the wrapper only its view.
    bool ownsImage = true;
};

struct CMVShader {
    CMVDevice *device;
    VkShaderModule module = VK_NULL_HANDLE;
    std::string entryPoint;
    VkShaderStageFlagBits stage = VK_SHADER_STAGE_VERTEX_BIT;
};

struct CMVSampler {
    CMVDevice *device;
    VkSampler sampler = VK_NULL_HANDLE;
};

struct CMVPipeline {
    CMVDevice *device;
    VkPipeline pipeline = VK_NULL_HANDLE;
    bool compute = false;
    std::set<uint32_t> vertexBindings;
};

struct CMVQueue {
    CMVDevice *device;
    uint64_t next = 1;
    std::vector<std::pair<uint64_t, VkFence>> pending;   // in submission order
    std::vector<VkFence> spare;
};

// Binding model of ADR-0012: set 0 holds two halves (vertex/kernel, fragment) of 8
// uniform buffers, 8 sampled images, 8 samplers and 8 storage images; set 1 holds the
// `space1` storage buffers (8 per half).
enum { kSlots = 8, kHalf = 32, kSet0Bindings = 64, kSet1Bindings = 16 };
enum { kBindUniform = 0, kBindSampled = 8, kBindSampler = 16, kBindStorageImage = 24 };

struct CMVDevice {
    VkInstance instance = VK_NULL_HANDLE;
    VkDebugUtilsMessengerEXT messenger = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    uint32_t family = 0;
    VkQueue queue = VK_NULL_HANDLE;
    std::mutex queueMutex;
    VkPhysicalDeviceProperties properties{};
    VkPhysicalDeviceMemoryProperties memory{};
    VkDescriptorSetLayout setLayout0 = VK_NULL_HANDLE, setLayout1 = VK_NULL_HANDLE;
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkCommandPool utilityPool = VK_NULL_HANDLE;
    VkCommandBuffer utilityBuffer = VK_NULL_HANDLE;
    VkFence utilityFence = VK_NULL_HANDLE;
    std::mutex utilityMutex;
    CMVBuffer *dummyBuffer = nullptr;
    CMVTexture *dummyTexture = nullptr;
    VkSampler dummySampler = VK_NULL_HANDLE;
    bool lost = false;
    bool presentable = false;
    bool xlibSurfaces = false;
    bool waylandSurfaces = false;
    bool validation = false;
    bool fillModeNonSolid = false;
    uint32_t subgroupSize = 32;
};

struct BufferBinding { CMVBuffer *buffer = nullptr; uint64_t offset = 0; };

struct CMVCommandList {
    CMVDevice *device;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkCommandBuffer cb = VK_NULL_HANDLE;
    std::vector<VkDescriptorPool> descriptorPools;
    size_t descriptorPoolIndex = 0;
    std::vector<CMVBuffer *> temporaries;
    bool recording = false;
    bool rendering = false;
    uint32_t renderWidth = 0, renderHeight = 0;
    CMVPipeline *graphics = nullptr;
    CMVPipeline *compute = nullptr;
    bool bindingsDirty = true;
    BufferBinding shaderBuffers[2][kSlots];
    CMVTexture *textures[2][kSlots] = {};
    CMVSampler *samplers[2][kSlots] = {};
    BufferBinding vertexBuffers[32];
    VkDescriptorSet lastSets[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    // Dynamic state, re-emitted when a pipeline is bound.
    VkViewport viewport{0, 0, 1, 1, 0, 1};
    VkRect2D scissor{{0, 0}, {1, 1}};
    bool viewportSet = false, scissorSet = false;
    VkCullModeFlags cullMode = VK_CULL_MODE_NONE;
    VkFrontFace frontFace = VK_FRONT_FACE_CLOCKWISE;
    bool depthTest = false, depthWrite = false;
    VkCompareOp depthCompare = VK_COMPARE_OP_ALWAYS;
    bool stencilTest = false;
    VkStencilOpState front{VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_COMPARE_OP_ALWAYS, 0xFFFFFFFFu, 0xFFFFFFFFu, 0};
    VkStencilOpState back{VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_STENCIL_OP_KEEP, VK_COMPARE_OP_ALWAYS, 0xFFFFFFFFu, 0xFFFFFFFFu, 0};
    uint32_t stencilReference = 0;
    float blendConstants[4] = {0, 0, 0, 0};
    VkPrimitiveTopology topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkFence lastFence = VK_NULL_HANDLE;   // the fence of the last execution (owned by the queue)
};

// MARK: Helpers

static uint32_t findMemoryType(CMVDevice *d, uint32_t typeBits, VkMemoryPropertyFlags required, VkMemoryPropertyFlags preferred) {
    for (int pass = 0; pass < 2; pass++) {
        VkMemoryPropertyFlags want = pass == 0 ? (required | preferred) : required;
        for (uint32_t i = 0; i < d->memory.memoryTypeCount; i++) {
            if ((typeBits & (1u << i)) && (d->memory.memoryTypes[i].propertyFlags & want) == want) return i;
        }
    }
    return UINT32_MAX;
}

static uint32_t texelSizeOf(VkFormat f) {
    switch (f) {
    case VK_FORMAT_R8_UNORM: case VK_FORMAT_R8_SNORM: case VK_FORMAT_R8_UINT: case VK_FORMAT_R8_SINT: case VK_FORMAT_R8_SRGB: case VK_FORMAT_S8_UINT: return 1;
    case VK_FORMAT_R8G8_UNORM: case VK_FORMAT_R8G8_SNORM: case VK_FORMAT_R8G8_UINT: case VK_FORMAT_R8G8_SINT: case VK_FORMAT_R8G8_SRGB:
    case VK_FORMAT_R16_UNORM: case VK_FORMAT_R16_SNORM: case VK_FORMAT_R16_UINT: case VK_FORMAT_R16_SINT: case VK_FORMAT_R16_SFLOAT: case VK_FORMAT_D16_UNORM: return 2;
    case VK_FORMAT_R8G8B8A8_UNORM: case VK_FORMAT_R8G8B8A8_SNORM: case VK_FORMAT_R8G8B8A8_UINT: case VK_FORMAT_R8G8B8A8_SINT: case VK_FORMAT_R8G8B8A8_SRGB:
    case VK_FORMAT_B8G8R8A8_UNORM: case VK_FORMAT_B8G8R8A8_SRGB: case VK_FORMAT_A2B10G10R10_UNORM_PACK32: case VK_FORMAT_A2B10G10R10_UINT_PACK32:
    case VK_FORMAT_B10G11R11_UFLOAT_PACK32: case VK_FORMAT_E5B9G9R9_UFLOAT_PACK32:
    case VK_FORMAT_R16G16_UNORM: case VK_FORMAT_R16G16_SNORM: case VK_FORMAT_R16G16_UINT: case VK_FORMAT_R16G16_SINT: case VK_FORMAT_R16G16_SFLOAT:
    case VK_FORMAT_R32_UINT: case VK_FORMAT_R32_SINT: case VK_FORMAT_R32_SFLOAT: case VK_FORMAT_D32_SFLOAT: case VK_FORMAT_D24_UNORM_S8_UINT: case VK_FORMAT_X8_D24_UNORM_PACK32: return 4;
    case VK_FORMAT_R16G16B16A16_UNORM: case VK_FORMAT_R16G16B16A16_SNORM: case VK_FORMAT_R16G16B16A16_UINT: case VK_FORMAT_R16G16B16A16_SINT: case VK_FORMAT_R16G16B16A16_SFLOAT:
    case VK_FORMAT_R32G32_UINT: case VK_FORMAT_R32G32_SINT: case VK_FORMAT_R32G32_SFLOAT: case VK_FORMAT_D32_SFLOAT_S8_UINT: return 8;
    case VK_FORMAT_R32G32B32A32_UINT: case VK_FORMAT_R32G32B32A32_SINT: case VK_FORMAT_R32G32B32A32_SFLOAT: return 16;
    default: return 4;
    }
}

static VkImageAspectFlags aspectOf(VkFormat f) {
    switch (f) {
    case VK_FORMAT_D16_UNORM: case VK_FORMAT_D32_SFLOAT: case VK_FORMAT_X8_D24_UNORM_PACK32: return VK_IMAGE_ASPECT_DEPTH_BIT;
    case VK_FORMAT_S8_UINT: return VK_IMAGE_ASPECT_STENCIL_BIT;
    case VK_FORMAT_D24_UNORM_S8_UINT: case VK_FORMAT_D32_SFLOAT_S8_UINT: case VK_FORMAT_D16_UNORM_S8_UINT: return VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT;
    default: return VK_IMAGE_ASPECT_COLOR_BIT;
    }
}

static void copyError(char *out, uint32_t capacity, const std::string &message) {
    if (out && capacity) snprintf(out, capacity, "%s", message.c_str());
}

/// A full barrier: every prior command's writes are visible to every later command.
static void fullBarrier(VkCommandBuffer cb) {
    VkMemoryBarrier barrier{VK_STRUCTURE_TYPE_MEMORY_BARRIER, nullptr, VK_ACCESS_MEMORY_WRITE_BIT | VK_ACCESS_MEMORY_READ_BIT, VK_ACCESS_MEMORY_WRITE_BIT | VK_ACCESS_MEMORY_READ_BIT};
    vk.vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 1, &barrier, 0, nullptr, 0, nullptr);
}

/// Records one-shot work on the utility command buffer and waits for it. The submission
/// waits on `waitSemaphore` and signals `signalSemaphore` when given (swap-chain
/// acquire/present hand-offs).
template <typename F> static bool runUtility(CMVDevice *d, F record, VkSemaphore waitSemaphore = VK_NULL_HANDLE, VkSemaphore signalSemaphore = VK_NULL_HANDLE) {
    std::lock_guard<std::mutex> lock(d->utilityMutex);
    vk.vkResetCommandPool(d->device, d->utilityPool, 0);
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, nullptr, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, nullptr};
    if (vk.vkBeginCommandBuffer(d->utilityBuffer, &begin) != VK_SUCCESS) return false;
    record(d->utilityBuffer);
    if (vk.vkEndCommandBuffer(d->utilityBuffer) != VK_SUCCESS) return false;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &d->utilityBuffer;
    VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    if (waitSemaphore) { submit.waitSemaphoreCount = 1; submit.pWaitSemaphores = &waitSemaphore; submit.pWaitDstStageMask = &waitStage; }
    if (signalSemaphore) { submit.signalSemaphoreCount = 1; submit.pSignalSemaphores = &signalSemaphore; }
    vk.vkResetFences(d->device, 1, &d->utilityFence);
    VkResult r;
    {
        std::lock_guard<std::mutex> q(d->queueMutex);
        r = vk.vkQueueSubmit(d->queue, 1, &submit, d->utilityFence);
    }
    if (r != VK_SUCCESS) { if (r == VK_ERROR_DEVICE_LOST) d->lost = true; return false; }
    r = vk.vkWaitForFences(d->device, 1, &d->utilityFence, VK_TRUE, UINT64_MAX);
    if (r == VK_ERROR_DEVICE_LOST) d->lost = true;
    return r == VK_SUCCESS;
}

static void transitionToGeneral(VkCommandBuffer cb, CMVTexture *t) {
    VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcQueueFamilyIndex = barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = t->image;
    barrier.subresourceRange = {t->aspect, 0, t->levels, 0, 1};
    vk.vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
}

// MARK: Device

static VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT severity, VkDebugUtilsMessageTypeFlagsEXT, const VkDebugUtilsMessengerCallbackDataEXT *data, void *) {
    const char *level = severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT ? "error" : severity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT ? "warning" : "info";
    fprintf(stderr, "AppKitWin Vulkan %s: %s\n", level, data && data->pMessage ? data->pMessage : "");
    return VK_FALSE;
}

static CMVBuffer *createBuffer(CMVDevice *d, uint64_t length);
static CMVTexture *createTexture(CMVDevice *d, uint32_t w, uint32_t h, uint32_t levels, VkFormat format, uint32_t usage, uint32_t samples);

CMVDevice *cmv_device_create(bool debug) {
    if (!loadLoader()) return nullptr;
    auto *d = new CMVDevice();

    // Instance: validation when asked for and present, debug utils with it, surface
    // extensions when the loader offers them (for the swap-chain follow-up).
    std::vector<const char *> layers, extensions;
    uint32_t count = 0;
    std::vector<VkExtensionProperties> available;
    if (vk.vkEnumerateInstanceExtensionProperties && vk.vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr) == VK_SUCCESS && count) {
        available.resize(count);
        vk.vkEnumerateInstanceExtensionProperties(nullptr, &count, available.data());
    }
    auto hasExtension = [&](const char *name) { return std::any_of(available.begin(), available.end(), [&](const VkExtensionProperties &e) { return strcmp(e.extensionName, name) == 0; }); };
    if (debug && vk.vkEnumerateInstanceLayerProperties) {
        uint32_t n = 0;
        vk.vkEnumerateInstanceLayerProperties(&n, nullptr);
        std::vector<VkLayerProperties> props(n);
        if (n) vk.vkEnumerateInstanceLayerProperties(&n, props.data());
        for (auto &p : props) if (strcmp(p.layerName, "VK_LAYER_KHRONOS_validation") == 0) { layers.push_back("VK_LAYER_KHRONOS_validation"); d->validation = true; }
        if (d->validation && hasExtension(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)) extensions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        if (!d->validation) fprintf(stderr, "AppKitWin: APPKITWIN_VULKAN_DEBUG=1 but VK_LAYER_KHRONOS_validation is not installed\n");
    }
    for (const char *name : {"VK_KHR_surface", "VK_KHR_xlib_surface", "VK_KHR_xcb_surface", "VK_KHR_wayland_surface"}) if (hasExtension(name)) extensions.push_back(name);
    bool hasSurface = hasExtension("VK_KHR_surface");
    d->xlibSurfaces = hasSurface && hasExtension("VK_KHR_xlib_surface");
    d->waylandSurfaces = hasSurface && hasExtension("VK_KHR_wayland_surface");

    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "AppKitWin";
    app.pEngineName = "AppKitWin Metal";
    app.apiVersion = VK_API_VERSION_1_3;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &app;
    ici.enabledLayerCount = (uint32_t)layers.size();
    ici.ppEnabledLayerNames = layers.data();
    ici.enabledExtensionCount = (uint32_t)extensions.size();
    ici.ppEnabledExtensionNames = extensions.data();
    VkResult r = vk.vkCreateInstance(&ici, nullptr, &d->instance);
    if (r != VK_SUCCESS) { setError(r == VK_ERROR_INCOMPATIBLE_DRIVER ? "no Vulkan 1.3 driver (vkCreateInstance: incompatible driver)" : "vkCreateInstance failed"); delete d; return nullptr; }
    if (!loadInstanceFunctions(d->instance)) { vk.vkDestroyInstance(d->instance, nullptr); delete d; return nullptr; }
    if (d->validation && vk.createDebugUtilsMessengerEXT) {
        VkDebugUtilsMessengerCreateInfoEXT mci{VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT};
        mci.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
        mci.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT;
        mci.pfnUserCallback = debugCallback;
        vk.createDebugUtilsMessengerEXT(d->instance, &mci, nullptr, &d->messenger);
    }

    // Physical device: a graphics+compute family and Vulkan 1.3; prefer hardware over CPU
    // implementations, discrete over integrated. APPKITWIN_VULKAN_DEVICE=n picks by index.
    count = 0;
    vk.vkEnumeratePhysicalDevices(d->instance, &count, nullptr);
    std::vector<VkPhysicalDevice> devices(count);
    if (count) vk.vkEnumeratePhysicalDevices(d->instance, &count, devices.data());
    const char *forced = getenv("APPKITWIN_VULKAN_DEVICE");
    int bestScore = -1;
    for (uint32_t i = 0; i < count; i++) {
        VkPhysicalDeviceProperties props{};
        vk.vkGetPhysicalDeviceProperties(devices[i], &props);
        if (props.apiVersion < VK_API_VERSION_1_3) continue;
        uint32_t families = 0;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &families, nullptr);
        std::vector<VkQueueFamilyProperties> qf(families);
        if (families) vk.vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &families, qf.data());
        int family = -1;
        for (uint32_t f = 0; f < families; f++) {
            if ((qf[f].queueFlags & VK_QUEUE_GRAPHICS_BIT) && (qf[f].queueFlags & VK_QUEUE_COMPUTE_BIT)) { family = (int)f; break; }
        }
        if (family < 0) continue;
        int score = props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ? 4 : props.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU ? 3 : props.deviceType == VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU ? 2 : 1;
        if (forced && atoi(forced) == (int)i) score = 100;
        if (score > bestScore) { bestScore = score; d->physical = devices[i]; d->family = (uint32_t)family; d->properties = props; }
    }
    if (!d->physical) {
        setError(count ? "no Vulkan 1.3 physical device with a graphics and compute queue" : "no Vulkan physical devices (no ICD installed)");
        if (d->messenger) vk.destroyDebugUtilsMessengerEXT(d->instance, d->messenger, nullptr);
        vk.vkDestroyInstance(d->instance, nullptr);
        delete d;
        return nullptr;
    }
    vk.vkGetPhysicalDeviceMemoryProperties(d->physical, &d->memory);
    VkPhysicalDeviceSubgroupProperties subgroup{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES};
    VkPhysicalDeviceProperties2 props2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, &subgroup};
    vk.vkGetPhysicalDeviceProperties2(d->physical, &props2);
    d->subgroupSize = subgroup.subgroupSize ? subgroup.subgroupSize : 32;

    uint32_t extCount = 0;
    vk.vkEnumerateDeviceExtensionProperties(d->physical, nullptr, &extCount, nullptr);
    std::vector<VkExtensionProperties> deviceExtensions(extCount);
    if (extCount) vk.vkEnumerateDeviceExtensionProperties(d->physical, nullptr, &extCount, deviceExtensions.data());
    std::vector<const char *> enabledDeviceExtensions;
    for (auto &e : deviceExtensions) if (strcmp(e.extensionName, VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0 && std::find(extensions.begin(), extensions.end(), std::string("VK_KHR_surface")) != extensions.end()) { enabledDeviceExtensions.push_back(VK_KHR_SWAPCHAIN_EXTENSION_NAME); d->presentable = true; }

    VkPhysicalDeviceFeatures supported{};
    vk.vkGetPhysicalDeviceFeatures(d->physical, &supported);
    VkPhysicalDeviceFeatures features{};
    features.fillModeNonSolid = supported.fillModeNonSolid;
    features.independentBlend = supported.independentBlend;
    features.samplerAnisotropy = supported.samplerAnisotropy;
    features.dualSrcBlend = supported.dualSrcBlend;
    d->fillModeNonSolid = supported.fillModeNonSolid;
    VkPhysicalDeviceVulkan13Features features13{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    features13.dynamicRendering = VK_TRUE;
    features13.synchronization2 = VK_FALSE;
    VkPhysicalDeviceVulkan12Features features12{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, &features13};
    float priority = 1;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = d->family;
    qci.queueCount = 1;
    qci.pQueuePriorities = &priority;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, &features12};
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.pEnabledFeatures = &features;
    dci.enabledExtensionCount = (uint32_t)enabledDeviceExtensions.size();
    dci.ppEnabledExtensionNames = enabledDeviceExtensions.data();
    r = vk.vkCreateDevice(d->physical, &dci, nullptr, &d->device);
    if (r != VK_SUCCESS) {
        setError("vkCreateDevice failed (dynamic rendering is required)");
        if (d->messenger) vk.destroyDebugUtilsMessengerEXT(d->instance, d->messenger, nullptr);
        vk.vkDestroyInstance(d->instance, nullptr);
        delete d;
        return nullptr;
    }
    vk.vkGetDeviceQueue(d->device, d->family, 0, &d->queue);

    // The shared pipeline layout.
    std::vector<VkDescriptorSetLayoutBinding> bindings0;
    for (uint32_t half = 0; half < 2; half++) {
        for (uint32_t i = 0; i < kSlots; i++) bindings0.push_back({half * kHalf + kBindUniform + i, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1, VK_SHADER_STAGE_ALL, nullptr});
        for (uint32_t i = 0; i < kSlots; i++) bindings0.push_back({half * kHalf + kBindSampled + i, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 1, VK_SHADER_STAGE_ALL, nullptr});
        for (uint32_t i = 0; i < kSlots; i++) bindings0.push_back({half * kHalf + kBindSampler + i, VK_DESCRIPTOR_TYPE_SAMPLER, 1, VK_SHADER_STAGE_ALL, nullptr});
        for (uint32_t i = 0; i < kSlots; i++) bindings0.push_back({half * kHalf + kBindStorageImage + i, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, VK_SHADER_STAGE_ALL, nullptr});
    }
    std::vector<VkDescriptorSetLayoutBinding> bindings1;
    for (uint32_t i = 0; i < kSet1Bindings; i++) bindings1.push_back({i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_ALL, nullptr});
    VkDescriptorSetLayoutCreateInfo slci{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    slci.bindingCount = (uint32_t)bindings0.size();
    slci.pBindings = bindings0.data();
    vk.vkCreateDescriptorSetLayout(d->device, &slci, nullptr, &d->setLayout0);
    slci.bindingCount = (uint32_t)bindings1.size();
    slci.pBindings = bindings1.data();
    vk.vkCreateDescriptorSetLayout(d->device, &slci, nullptr, &d->setLayout1);
    VkDescriptorSetLayout layouts[2] = {d->setLayout0, d->setLayout1};
    VkPipelineLayoutCreateInfo plci{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    plci.setLayoutCount = 2;
    plci.pSetLayouts = layouts;
    if (vk.vkCreatePipelineLayout(d->device, &plci, nullptr, &d->layout) != VK_SUCCESS) { setError("vkCreatePipelineLayout failed"); cmv_device_release(d); return nullptr; }

    // Utility command buffer for synchronous uploads, readbacks and initial transitions.
    VkCommandPoolCreateInfo cpci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, nullptr, VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, d->family};
    vk.vkCreateCommandPool(d->device, &cpci, nullptr, &d->utilityPool);
    VkCommandBufferAllocateInfo cbai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, nullptr, d->utilityPool, VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1};
    vk.vkAllocateCommandBuffers(d->device, &cbai, &d->utilityBuffer);
    VkFenceCreateInfo fci{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    vk.vkCreateFence(d->device, &fci, nullptr, &d->utilityFence);

    // Dummies for unset slots.
    d->dummyBuffer = createBuffer(d, 256);
    d->dummyTexture = createTexture(d, 1, 1, 1, VK_FORMAT_R8G8B8A8_UNORM, CMV_TEXTURE_SHADER_READ | CMV_TEXTURE_SHADER_WRITE, 1);
    VkSamplerCreateInfo sci{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    sci.magFilter = sci.minFilter = VK_FILTER_NEAREST;
    sci.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST;
    sci.addressModeU = sci.addressModeV = sci.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    sci.maxLod = VK_LOD_CLAMP_NONE;
    vk.vkCreateSampler(d->device, &sci, nullptr, &d->dummySampler);
    if (!d->dummyBuffer || !d->dummyTexture || !d->dummySampler) { setError("could not create the device's dummy resources"); cmv_device_release(d); return nullptr; }
    g_lastError[0] = 0;
    return d;
}

void cmv_device_release(CMVDevice *d) {
    if (!d) return;
    if (d->device) vk.vkDeviceWaitIdle(d->device);
    if (d->dummyBuffer) cmv_buffer_release(d->dummyBuffer);
    if (d->dummyTexture) cmv_texture_release(d->dummyTexture);
    if (d->dummySampler) vk.vkDestroySampler(d->device, d->dummySampler, nullptr);
    if (d->utilityFence) vk.vkDestroyFence(d->device, d->utilityFence, nullptr);
    if (d->utilityPool) vk.vkDestroyCommandPool(d->device, d->utilityPool, nullptr);
    if (d->layout) vk.vkDestroyPipelineLayout(d->device, d->layout, nullptr);
    if (d->setLayout0) vk.vkDestroyDescriptorSetLayout(d->device, d->setLayout0, nullptr);
    if (d->setLayout1) vk.vkDestroyDescriptorSetLayout(d->device, d->setLayout1, nullptr);
    if (d->device) vk.vkDestroyDevice(d->device, nullptr);
    if (d->messenger && vk.destroyDebugUtilsMessengerEXT) vk.destroyDebugUtilsMessengerEXT(d->instance, d->messenger, nullptr);
    if (d->instance) vk.vkDestroyInstance(d->instance, nullptr);
    delete d;
}

void cmv_device_info(CMVDevice *d, CMVDeviceInfo *info) {
    if (!d || !info) return;
    memset(info, 0, sizeof *info);
    snprintf(info->name, sizeof info->name, "%s", d->properties.deviceName);
    for (uint32_t i = 0; i < d->memory.memoryHeapCount; i++) if (d->memory.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) info->deviceLocalMemory += d->memory.memoryHeaps[i].size;
    info->apiVersion = d->properties.apiVersion;
    info->vendorID = d->properties.vendorID;
    info->deviceID = d->properties.deviceID;
    info->isSoftware = d->properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU;
    info->isIntegrated = d->properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
    info->presentable = d->presentable;
    info->xlibSurfaces = d->xlibSurfaces;
    info->waylandSurfaces = d->waylandSurfaces;
    info->validation = d->validation;
    info->maxComputeWorkGroupInvocations = d->properties.limits.maxComputeWorkGroupInvocations;
    for (int i = 0; i < 3; i++) info->maxComputeWorkGroupSize[i] = d->properties.limits.maxComputeWorkGroupSize[i];
    info->subgroupSize = d->subgroupSize;
    info->minUniformBufferOffsetAlignment = (uint32_t)d->properties.limits.minUniformBufferOffsetAlignment;
    info->minStorageBufferOffsetAlignment = (uint32_t)d->properties.limits.minStorageBufferOffsetAlignment;
    info->maxVertexInputBindings = d->properties.limits.maxVertexInputBindings;
}

bool cmv_device_lost(CMVDevice *d) { return d && d->lost; }

bool cmv_device_supports_format(CMVDevice *d, uint32_t vkFormat, bool attachment) {
    if (!d || vkFormat == 0) return false;
    VkFormatProperties p{};
    vk.vkGetPhysicalDeviceFormatProperties(d->physical, (VkFormat)vkFormat, &p);
    VkFormatFeatureFlags need = VK_FORMAT_FEATURE_TRANSFER_SRC_BIT | VK_FORMAT_FEATURE_TRANSFER_DST_BIT;
    if (aspectOf((VkFormat)vkFormat) == VK_IMAGE_ASPECT_COLOR_BIT) need |= VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
    if (attachment) need |= aspectOf((VkFormat)vkFormat) == VK_IMAGE_ASPECT_COLOR_BIT ? VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT : VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;
    return (p.optimalTilingFeatures & need) == need;
}

void cmv_device_wait_idle(CMVDevice *d) { if (d && d->device) vk.vkDeviceWaitIdle(d->device); }

// MARK: Queues

CMVQueue *cmv_queue_create(CMVDevice *d) {
    if (!d) return nullptr;
    auto *q = new CMVQueue();
    q->device = d;
    return q;
}

static VkFence takeFence(CMVQueue *q) {
    VkFence f;
    if (!q->spare.empty()) { f = q->spare.back(); q->spare.pop_back(); vk.vkResetFences(q->device->device, 1, &f); return f; }
    VkFenceCreateInfo fci{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    vk.vkCreateFence(q->device->device, &fci, nullptr, &f);
    return f;
}

/// Moves completed fences from `pending` to `spare` (pending stays ordered).
static void reclaimFences(CMVQueue *q) {
    while (!q->pending.empty() && vk.vkGetFenceStatus(q->device->device, q->pending.front().second) == VK_SUCCESS) {
        q->spare.push_back(q->pending.front().second);
        q->pending.erase(q->pending.begin());
    }
}

void cmv_queue_release(CMVQueue *q) {
    if (!q) return;
    for (auto &p : q->pending) { vk.vkWaitForFences(q->device->device, 1, &p.second, VK_TRUE, UINT64_MAX); vk.vkDestroyFence(q->device->device, p.second, nullptr); }
    for (VkFence f : q->spare) vk.vkDestroyFence(q->device->device, f, nullptr);
    delete q;
}

static uint64_t submit(CMVQueue *q, VkCommandBuffer cb) {
    CMVDevice *d = q->device;
    reclaimFences(q);
    VkFence fence = takeFence(q);
    VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.commandBufferCount = cb ? 1 : 0;
    si.pCommandBuffers = cb ? &cb : nullptr;
    VkResult r;
    {
        std::lock_guard<std::mutex> lock(d->queueMutex);
        r = vk.vkQueueSubmit(d->queue, 1, &si, fence);
    }
    if (r != VK_SUCCESS) { if (r == VK_ERROR_DEVICE_LOST) d->lost = true; q->spare.push_back(fence); return 0; }
    uint64_t value = q->next++;
    q->pending.push_back({value, fence});
    return value;
}

uint64_t cmv_queue_signal(CMVQueue *q) { return q ? submit(q, VK_NULL_HANDLE) : 0; }

bool cmv_queue_fence_reached(CMVQueue *q, uint64_t value) {
    if (!q || value == 0) return true;
    reclaimFences(q);
    for (auto &p : q->pending) if (p.first == value) return vk.vkGetFenceStatus(q->device->device, p.second) == VK_SUCCESS;
    return value < q->next;   // already reclaimed
}

void cmv_queue_wait(CMVQueue *q, uint64_t value) {
    if (!q || value == 0) return;
    for (auto &p : q->pending) {
        if (p.first == value) {
            VkResult r = vk.vkWaitForFences(q->device->device, 1, &p.second, VK_TRUE, UINT64_MAX);
            if (r == VK_ERROR_DEVICE_LOST) q->device->lost = true;
            break;
        }
    }
    reclaimFences(q);
}

// MARK: Buffers

static CMVBuffer *createBuffer(CMVDevice *d, uint64_t length) {
    if (!d || length == 0) return nullptr;
    auto *b = new CMVBuffer();
    b->device = d;
    b->length = length;
    VkBufferCreateInfo bci{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bci.size = length;
    bci.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT | VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vk.vkCreateBuffer(d->device, &bci, nullptr, &b->buffer) != VK_SUCCESS) { delete b; return nullptr; }
    VkMemoryRequirements req{};
    vk.vkGetBufferMemoryRequirements(d->device, b->buffer, &req);
    VkMemoryAllocateInfo mai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    mai.allocationSize = req.size;
    mai.memoryTypeIndex = findMemoryType(d, req.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (mai.memoryTypeIndex == UINT32_MAX || vk.vkAllocateMemory(d->device, &mai, nullptr, &b->memory) != VK_SUCCESS) { cmv_buffer_release(b); return nullptr; }
    if (vk.vkBindBufferMemory(d->device, b->buffer, b->memory, 0) != VK_SUCCESS || vk.vkMapMemory(d->device, b->memory, 0, VK_WHOLE_SIZE, 0, &b->mapped) != VK_SUCCESS) { cmv_buffer_release(b); return nullptr; }
    memset(b->mapped, 0, (size_t)length);
    return b;
}

CMVBuffer *cmv_buffer_create(CMVDevice *d, uint64_t length) { return createBuffer(d, length); }

void cmv_buffer_release(CMVBuffer *b) {
    if (!b) return;
    VkDevice dev = b->device->device;
    if (b->mapped) vk.vkUnmapMemory(dev, b->memory);
    if (b->buffer) vk.vkDestroyBuffer(dev, b->buffer, nullptr);
    if (b->memory) vk.vkFreeMemory(dev, b->memory, nullptr);
    delete b;
}

void *cmv_buffer_map(CMVBuffer *b) { return b ? b->mapped : nullptr; }
uint64_t cmv_buffer_length(CMVBuffer *b) { return b ? b->length : 0; }

// MARK: Textures

static CMVTexture *createTexture(CMVDevice *d, uint32_t w, uint32_t h, uint32_t levels, VkFormat format, uint32_t usage, uint32_t samples) {
    if (!d || w == 0 || h == 0 || format == VK_FORMAT_UNDEFINED) return nullptr;
    auto *t = new CMVTexture();
    t->device = d;
    t->format = format;
    t->aspect = aspectOf(format);
    t->width = w; t->height = h; t->levels = std::max(1u, levels); t->samples = std::max(1u, samples);
    t->texelSize = texelSizeOf(format);
    bool depth = t->aspect != VK_IMAGE_ASPECT_COLOR_BIT;
    VkImageCreateInfo ici{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ici.imageType = VK_IMAGE_TYPE_2D;
    ici.format = format;
    ici.extent = {w, h, 1};
    ici.mipLevels = t->levels;
    ici.arrayLayers = 1;
    ici.samples = (VkSampleCountFlagBits)t->samples;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (!depth) ici.usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
    else if (usage & CMV_TEXTURE_SHADER_READ) ici.usage |= VK_IMAGE_USAGE_SAMPLED_BIT;
    if (usage & CMV_TEXTURE_RENDER_TARGET) ici.usage |= depth ? VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if ((usage & CMV_TEXTURE_SHADER_WRITE) && !depth) {
        VkFormatProperties p{};
        vk.vkGetPhysicalDeviceFormatProperties(d->physical, format, &p);
        if (p.optimalTilingFeatures & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT) { ici.usage |= VK_IMAGE_USAGE_STORAGE_BIT; t->storage = true; }
    }
    ici.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    if (vk.vkCreateImage(d->device, &ici, nullptr, &t->image) != VK_SUCCESS) { delete t; return nullptr; }
    VkMemoryRequirements req{};
    vk.vkGetImageMemoryRequirements(d->device, t->image, &req);
    VkMemoryAllocateInfo mai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    mai.allocationSize = req.size;
    mai.memoryTypeIndex = findMemoryType(d, req.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 0);
    if (mai.memoryTypeIndex == UINT32_MAX) mai.memoryTypeIndex = findMemoryType(d, req.memoryTypeBits, 0, 0);
    if (mai.memoryTypeIndex == UINT32_MAX || vk.vkAllocateMemory(d->device, &mai, nullptr, &t->memory) != VK_SUCCESS || vk.vkBindImageMemory(d->device, t->image, t->memory, 0) != VK_SUCCESS) { cmv_texture_release(t); return nullptr; }
    VkImageViewCreateInfo vci{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vci.image = t->image;
    vci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    vci.format = format;
    // Views used for sampling or attachments carry one aspect; combined depth/stencil views use depth.
    vci.subresourceRange = {t->aspect & VK_IMAGE_ASPECT_DEPTH_BIT ? VK_IMAGE_ASPECT_DEPTH_BIT : t->aspect, 0, t->levels, 0, 1};
    if (t->aspect == (VK_IMAGE_ASPECT_DEPTH_BIT | VK_IMAGE_ASPECT_STENCIL_BIT)) vci.subresourceRange.aspectMask = t->aspect;
    if (vk.vkCreateImageView(d->device, &vci, nullptr, &t->view) != VK_SUCCESS) { cmv_texture_release(t); return nullptr; }
    // Every image lives in GENERAL (ADR-0012).
    if (!runUtility(d, [&](VkCommandBuffer cb) { transitionToGeneral(cb, t); })) { cmv_texture_release(t); return nullptr; }
    return t;
}

CMVTexture *cmv_texture_create(CMVDevice *d, uint32_t width, uint32_t height, uint32_t mipLevels, uint32_t vkFormat, uint32_t usage, uint32_t sampleCount) {
    return createTexture(d, width, height, mipLevels, (VkFormat)vkFormat, usage, sampleCount);
}

void cmv_texture_release(CMVTexture *t) {
    if (!t) return;
    VkDevice dev = t->device->device;
    if (t->view) vk.vkDestroyImageView(dev, t->view, nullptr);
    if (t->image && t->ownsImage) vk.vkDestroyImage(dev, t->image, nullptr);
    if (t->memory) vk.vkFreeMemory(dev, t->memory, nullptr);
    delete t;
}

uint32_t cmv_texture_format(CMVTexture *t) { return t ? (uint32_t)t->format : 0; }

static VkImageAspectFlags copyAspect(CMVTexture *t) { return t->aspect & VK_IMAGE_ASPECT_DEPTH_BIT ? VK_IMAGE_ASPECT_DEPTH_BIT : t->aspect; }

/// Records a buffer→image copy; `bytesPerRow` must be a multiple of the texel size.
static void recordBufferToImage(VkCommandBuffer cb, CMVBuffer *src, uint64_t srcOffset, uint32_t bytesPerRow, CMVTexture *dst, uint32_t level, uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    VkBufferImageCopy region{};
    region.bufferOffset = srcOffset;
    region.bufferRowLength = bytesPerRow / dst->texelSize;
    region.bufferImageHeight = h;
    region.imageSubresource = {copyAspect(dst), level, 0, 1};
    region.imageOffset = {(int32_t)x, (int32_t)y, 0};
    region.imageExtent = {w, h, 1};
    vk.vkCmdCopyBufferToImage(cb, src->buffer, dst->image, VK_IMAGE_LAYOUT_GENERAL, 1, &region);
}

/// Moves an image between layouts (swap-chain images; everything else stays GENERAL).
static void transitionLayout(VkCommandBuffer cb, CMVTexture *t, VkImageLayout from, VkImageLayout to) {
    VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    barrier.srcAccessMask = from == VK_IMAGE_LAYOUT_UNDEFINED ? 0 : VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    barrier.oldLayout = from;
    barrier.newLayout = to;
    barrier.srcQueueFamilyIndex = barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = t->image;
    barrier.subresourceRange = {t->aspect, 0, t->levels, 0, 1};
    vk.vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    t->layout = to;
}

static void recordImageToBuffer(VkCommandBuffer cb, CMVTexture *src, uint32_t level, uint32_t x, uint32_t y, uint32_t w, uint32_t h, CMVBuffer *dst, uint64_t dstOffset, uint32_t bytesPerRow) {
    VkBufferImageCopy region{};
    region.bufferOffset = dstOffset;
    region.bufferRowLength = bytesPerRow / src->texelSize;
    region.bufferImageHeight = h;
    region.imageSubresource = {copyAspect(src), level, 0, 1};
    region.imageOffset = {(int32_t)x, (int32_t)y, 0};
    region.imageExtent = {w, h, 1};
    // A presented swap-chain image (PRESENT_SRC) is read through GENERAL and put back,
    // so a frame's pixels can still be checked after its present (HelloWindow --metal-log).
    VkImageLayout presented = src->layout;
    if (presented != VK_IMAGE_LAYOUT_GENERAL) transitionLayout(cb, src, presented, VK_IMAGE_LAYOUT_GENERAL);
    vk.vkCmdCopyImageToBuffer(cb, src->image, VK_IMAGE_LAYOUT_GENERAL, dst->buffer, 1, &region);
    if (presented != VK_IMAGE_LAYOUT_GENERAL) transitionLayout(cb, src, VK_IMAGE_LAYOUT_GENERAL, presented);
}

bool cmv_texture_upload(CMVDevice *d, CMVTexture *t, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height, const void *rows, uint32_t bytesPerRow) {
    if (!d || !t || !rows || width == 0 || height == 0) return false;
    uint32_t tightRow = width * t->texelSize;
    CMVBuffer *staging = createBuffer(d, (uint64_t)tightRow * height);
    if (!staging) return false;
    for (uint32_t r = 0; r < height; r++) memcpy((char *)staging->mapped + (size_t)r * tightRow, (const char *)rows + (size_t)r * bytesPerRow, tightRow);
    bool ok = runUtility(d, [&](VkCommandBuffer cb) {
        fullBarrier(cb);
        recordBufferToImage(cb, staging, 0, tightRow, t, level, x, y, width, height);
        fullBarrier(cb);
    });
    cmv_buffer_release(staging);
    return ok;
}

bool cmv_texture_read(CMVDevice *d, CMVTexture *t, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height, void *out, uint32_t bytesPerRow) {
    if (!d || !t || !out || width == 0 || height == 0) return false;
    uint32_t tightRow = width * t->texelSize;
    CMVBuffer *staging = createBuffer(d, (uint64_t)tightRow * height);
    if (!staging) return false;
    bool ok = runUtility(d, [&](VkCommandBuffer cb) {
        fullBarrier(cb);
        recordImageToBuffer(cb, t, level, x, y, width, height, staging, 0, tightRow);
        fullBarrier(cb);
    });
    if (ok) for (uint32_t r = 0; r < height; r++) memcpy((char *)out + (size_t)r * bytesPerRow, (const char *)staging->mapped + (size_t)r * tightRow, tightRow);
    cmv_buffer_release(staging);
    return ok;
}

// MARK: Shaders, samplers, pipelines

CMVShader *cmv_shader_from_spirv(CMVDevice *d, const void *words, uint32_t length, const char *entryPoint, uint32_t stage, char *errorOut, uint32_t errorCapacity) {
    if (!d || !words || length < 20 || length % 4 != 0) { copyError(errorOut, errorCapacity, "SPIR-V module is empty or not a multiple of 4 bytes"); return nullptr; }
    if (*(const uint32_t *)words != 0x07230203u) { copyError(errorOut, errorCapacity, "not a SPIR-V module (bad magic number)"); return nullptr; }
    auto *s = new CMVShader();
    s->device = d;
    s->entryPoint = entryPoint ? entryPoint : "main";
    s->stage = (VkShaderStageFlagBits)stage;
    VkShaderModuleCreateInfo smci{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    smci.codeSize = length;
    smci.pCode = (const uint32_t *)words;
    VkResult r = vk.vkCreateShaderModule(d->device, &smci, nullptr, &s->module);
    if (r != VK_SUCCESS) { copyError(errorOut, errorCapacity, "vkCreateShaderModule failed (invalid SPIR-V?)"); delete s; return nullptr; }
    return s;
}

void cmv_shader_release(CMVShader *s) {
    if (!s) return;
    if (s->module) vk.vkDestroyShaderModule(s->device->device, s->module, nullptr);
    delete s;
}

CMVSampler *cmv_sampler_create(CMVDevice *d, uint32_t minFilter, uint32_t magFilter, uint32_t mipMode, uint32_t addressU, uint32_t addressV, uint32_t addressW,
                               bool compare, uint32_t compareOp, float lodMin, float lodMax, uint32_t maxAnisotropy, uint32_t borderColor) {
    if (!d) return nullptr;
    VkSamplerCreateInfo sci{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    sci.magFilter = (VkFilter)magFilter;
    sci.minFilter = (VkFilter)minFilter;
    sci.mipmapMode = (VkSamplerMipmapMode)mipMode;
    sci.addressModeU = (VkSamplerAddressMode)addressU;
    sci.addressModeV = (VkSamplerAddressMode)addressV;
    sci.addressModeW = (VkSamplerAddressMode)addressW;
    sci.anisotropyEnable = maxAnisotropy > 1 ? VK_TRUE : VK_FALSE;
    sci.maxAnisotropy = (float)std::max(1u, std::min(maxAnisotropy, (uint32_t)d->properties.limits.maxSamplerAnisotropy));
    sci.compareEnable = compare ? VK_TRUE : VK_FALSE;
    sci.compareOp = (VkCompareOp)compareOp;
    sci.minLod = lodMin;
    sci.maxLod = std::isfinite(lodMax) ? lodMax : VK_LOD_CLAMP_NONE;
    sci.borderColor = borderColor == 1 ? VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK : borderColor == 2 ? VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE : VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK;
    auto *s = new CMVSampler();
    s->device = d;
    if (vk.vkCreateSampler(d->device, &sci, nullptr, &s->sampler) != VK_SUCCESS) { delete s; return nullptr; }
    return s;
}

void cmv_sampler_release(CMVSampler *s) {
    if (!s) return;
    if (s->sampler) vk.vkDestroySampler(s->device->device, s->sampler, nullptr);
    delete s;
}

static const VkDynamicState kDynamicStates[] = {
    VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR, VK_DYNAMIC_STATE_PRIMITIVE_TOPOLOGY, VK_DYNAMIC_STATE_CULL_MODE, VK_DYNAMIC_STATE_FRONT_FACE,
    VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE, VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE, VK_DYNAMIC_STATE_DEPTH_COMPARE_OP,
    VK_DYNAMIC_STATE_STENCIL_TEST_ENABLE, VK_DYNAMIC_STATE_STENCIL_OP, VK_DYNAMIC_STATE_STENCIL_COMPARE_MASK, VK_DYNAMIC_STATE_STENCIL_WRITE_MASK, VK_DYNAMIC_STATE_STENCIL_REFERENCE,
    VK_DYNAMIC_STATE_BLEND_CONSTANTS,
};

CMVPipeline *cmv_pipeline_create(CMVDevice *d, const CMVPipelineDesc *desc, char *errorOut, uint32_t errorCapacity) {
    if (!d || !desc || !desc->vertex) { copyError(errorOut, errorCapacity, "a graphics pipeline needs a vertex shader"); return nullptr; }
    std::vector<VkPipelineShaderStageCreateInfo> stages;
    VkPipelineShaderStageCreateInfo vs{VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO};
    vs.stage = VK_SHADER_STAGE_VERTEX_BIT;
    vs.module = desc->vertex->module;
    vs.pName = desc->vertex->entryPoint.c_str();
    stages.push_back(vs);
    if (desc->fragment) {
        VkPipelineShaderStageCreateInfo fs = vs;
        fs.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
        fs.module = desc->fragment->module;
        fs.pName = desc->fragment->entryPoint.c_str();
        stages.push_back(fs);
    }

    std::vector<VkVertexInputBindingDescription> bindings;
    std::vector<VkVertexInputAttributeDescription> attributes;
    std::set<uint32_t> bindingSet;
    for (uint32_t i = 0; i < desc->layoutCount; i++) {
        const CMVVertexLayout &l = desc->layouts[i];
        if (l.stride == 0 || bindingSet.count(l.binding)) continue;
        bindings.push_back({l.binding, l.stride, l.perInstance ? VK_VERTEX_INPUT_RATE_INSTANCE : VK_VERTEX_INPUT_RATE_VERTEX});
        bindingSet.insert(l.binding);
    }
    for (uint32_t i = 0; i < desc->attributeCount; i++) {
        const CMVVertexAttribute &a = desc->attributes[i];
        if (a.vkFormat == 0 || !bindingSet.count(a.binding)) continue;
        attributes.push_back({a.location, a.binding, (VkFormat)a.vkFormat, a.offset});
    }
    VkPipelineVertexInputStateCreateInfo vertexInput{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    vertexInput.vertexBindingDescriptionCount = (uint32_t)bindings.size();
    vertexInput.pVertexBindingDescriptions = bindings.data();
    vertexInput.vertexAttributeDescriptionCount = (uint32_t)attributes.size();
    vertexInput.pVertexAttributeDescriptions = attributes.data();

    VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    assembly.topology = desc->topologyClass == 0 ? VK_PRIMITIVE_TOPOLOGY_POINT_LIST : desc->topologyClass == 1 ? VK_PRIMITIVE_TOPOLOGY_LINE_LIST : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    VkPipelineViewportStateCreateInfo viewport{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    viewport.viewportCount = 1;
    viewport.scissorCount = 1;

    VkPipelineRasterizationStateCreateInfo raster{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    raster.rasterizerDiscardEnable = desc->rasterizationEnabled ? VK_FALSE : VK_TRUE;
    raster.polygonMode = desc->wireframe && d->fillModeNonSolid ? VK_POLYGON_MODE_LINE : VK_POLYGON_MODE_FILL;
    raster.lineWidth = 1;

    VkPipelineMultisampleStateCreateInfo multisample{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    multisample.rasterizationSamples = (VkSampleCountFlagBits)std::max(1u, desc->sampleCount);
    multisample.alphaToCoverageEnable = desc->alphaToCoverage;
    multisample.alphaToOneEnable = desc->alphaToOne;

    VkPipelineDepthStencilStateCreateInfo depthStencil{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    depthStencil.depthTestEnable = VK_FALSE;
    depthStencil.depthWriteEnable = VK_FALSE;
    depthStencil.depthCompareOp = VK_COMPARE_OP_ALWAYS;
    depthStencil.maxDepthBounds = 1;

    std::vector<VkPipelineColorBlendAttachmentState> blends;
    std::vector<VkFormat> colorFormats;
    uint32_t colorCount = 0;
    for (uint32_t i = 0; i < 8; i++) if (desc->colorFormats[i]) colorCount = i + 1;
    for (uint32_t i = 0; i < colorCount; i++) {
        colorFormats.push_back((VkFormat)desc->colorFormats[i]);
        const CMVBlend &b = desc->blends[i];
        VkPipelineColorBlendAttachmentState s{};
        s.blendEnable = b.enabled;
        s.srcColorBlendFactor = (VkBlendFactor)b.srcRGB;
        s.dstColorBlendFactor = (VkBlendFactor)b.dstRGB;
        s.colorBlendOp = (VkBlendOp)b.opRGB;
        s.srcAlphaBlendFactor = (VkBlendFactor)b.srcAlpha;
        s.dstAlphaBlendFactor = (VkBlendFactor)b.dstAlpha;
        s.alphaBlendOp = (VkBlendOp)b.opAlpha;
        s.colorWriteMask = b.writeMask;
        blends.push_back(s);
    }
    VkPipelineColorBlendStateCreateInfo blend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blend.attachmentCount = (uint32_t)blends.size();
    blend.pAttachments = blends.data();

    VkPipelineDynamicStateCreateInfo dynamic{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dynamic.dynamicStateCount = sizeof kDynamicStates / sizeof kDynamicStates[0];
    dynamic.pDynamicStates = kDynamicStates;

    VkPipelineRenderingCreateInfo rendering{VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    rendering.colorAttachmentCount = (uint32_t)colorFormats.size();
    rendering.pColorAttachmentFormats = colorFormats.data();
    rendering.depthAttachmentFormat = (VkFormat)desc->depthFormat;
    rendering.stencilAttachmentFormat = (VkFormat)desc->stencilFormat;

    VkGraphicsPipelineCreateInfo gpci{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO, &rendering};
    gpci.stageCount = (uint32_t)stages.size();
    gpci.pStages = stages.data();
    gpci.pVertexInputState = &vertexInput;
    gpci.pInputAssemblyState = &assembly;
    gpci.pViewportState = &viewport;
    gpci.pRasterizationState = &raster;
    gpci.pMultisampleState = &multisample;
    gpci.pDepthStencilState = &depthStencil;
    gpci.pColorBlendState = &blend;
    gpci.pDynamicState = &dynamic;
    gpci.layout = d->layout;
    auto *p = new CMVPipeline();
    p->device = d;
    p->vertexBindings = bindingSet;
    VkResult r = vk.vkCreateGraphicsPipelines(d->device, VK_NULL_HANDLE, 1, &gpci, nullptr, &p->pipeline);
    if (r != VK_SUCCESS) { copyError(errorOut, errorCapacity, "vkCreateGraphicsPipelines failed (check the shader interface and attachment formats; APPKITWIN_VULKAN_DEBUG=1 prints the validation message)"); delete p; return nullptr; }
    return p;
}

CMVPipeline *cmv_compute_pipeline_create(CMVDevice *d, CMVShader *kernel, char *errorOut, uint32_t errorCapacity) {
    if (!d || !kernel) { copyError(errorOut, errorCapacity, "a compute pipeline needs a kernel"); return nullptr; }
    VkComputePipelineCreateInfo cpci{VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    cpci.stage = {VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, nullptr, 0, VK_SHADER_STAGE_COMPUTE_BIT, kernel->module, kernel->entryPoint.c_str(), nullptr};
    cpci.layout = d->layout;
    auto *p = new CMVPipeline();
    p->device = d;
    p->compute = true;
    if (vk.vkCreateComputePipelines(d->device, VK_NULL_HANDLE, 1, &cpci, nullptr, &p->pipeline) != VK_SUCCESS) { copyError(errorOut, errorCapacity, "vkCreateComputePipelines failed (is the entry point a compute shader?)"); delete p; return nullptr; }
    return p;
}

void cmv_pipeline_release(CMVPipeline *p) {
    if (!p) return;
    if (p->pipeline) vk.vkDestroyPipeline(p->device->device, p->pipeline, nullptr);
    delete p;
}

// MARK: Command lists

CMVCommandList *cmv_commandlist_create(CMVDevice *d) {
    if (!d) return nullptr;
    auto *l = new CMVCommandList();
    l->device = d;
    VkCommandPoolCreateInfo cpci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, nullptr, VK_COMMAND_POOL_CREATE_TRANSIENT_BIT, d->family};
    if (vk.vkCreateCommandPool(d->device, &cpci, nullptr, &l->pool) != VK_SUCCESS) { delete l; return nullptr; }
    VkCommandBufferAllocateInfo cbai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, nullptr, l->pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1};
    if (vk.vkAllocateCommandBuffers(d->device, &cbai, &l->cb) != VK_SUCCESS) { vk.vkDestroyCommandPool(d->device, l->pool, nullptr); delete l; return nullptr; }
    return l;
}

static void releaseTemporaries(CMVCommandList *l) {
    for (CMVBuffer *b : l->temporaries) cmv_buffer_release(b);
    l->temporaries.clear();
}

void cmv_commandlist_release(CMVCommandList *l) {
    if (!l) return;
    VkDevice dev = l->device->device;
    if (l->lastFence) vk.vkWaitForFences(dev, 1, &l->lastFence, VK_TRUE, UINT64_MAX);
    releaseTemporaries(l);
    for (VkDescriptorPool p : l->descriptorPools) vk.vkDestroyDescriptorPool(dev, p, nullptr);
    if (l->pool) vk.vkDestroyCommandPool(dev, l->pool, nullptr);
    delete l;
}

void cmv_commandlist_reset(CMVCommandList *l) {
    if (!l) return;
    VkDevice dev = l->device->device;
    if (l->lastFence) { vk.vkWaitForFences(dev, 1, &l->lastFence, VK_TRUE, UINT64_MAX); l->lastFence = VK_NULL_HANDLE; }
    releaseTemporaries(l);
    for (VkDescriptorPool p : l->descriptorPools) vk.vkResetDescriptorPool(dev, p, 0);
    l->descriptorPoolIndex = 0;
    vk.vkResetCommandPool(dev, l->pool, 0);
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, nullptr, VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, nullptr};
    l->recording = vk.vkBeginCommandBuffer(l->cb, &begin) == VK_SUCCESS;
    l->rendering = false;
    l->graphics = l->compute = nullptr;
    l->bindingsDirty = true;
    l->lastSets[0] = l->lastSets[1] = VK_NULL_HANDLE;
    for (int h = 0; h < 2; h++) for (int i = 0; i < kSlots; i++) { l->shaderBuffers[h][i] = {}; l->textures[h][i] = nullptr; l->samplers[h][i] = nullptr; }
    for (auto &v : l->vertexBuffers) v = {};
    l->viewportSet = l->scissorSet = false;
}

static VkDescriptorPool nextDescriptorPool(CMVCommandList *l) {
    if (l->descriptorPoolIndex < l->descriptorPools.size()) return l->descriptorPools[l->descriptorPoolIndex];
    const uint32_t sets = 256;
    VkDescriptorPoolSize sizes[] = {
        {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, sets * 2 * kSlots}, {VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, sets * 2 * kSlots}, {VK_DESCRIPTOR_TYPE_SAMPLER, sets * 2 * kSlots},
        {VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, sets * 2 * kSlots}, {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, sets * kSet1Bindings},
    };
    VkDescriptorPoolCreateInfo dpci{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    dpci.maxSets = sets * 2;
    dpci.poolSizeCount = sizeof sizes / sizeof sizes[0];
    dpci.pPoolSizes = sizes;
    VkDescriptorPool pool = VK_NULL_HANDLE;
    if (vk.vkCreateDescriptorPool(l->device->device, &dpci, nullptr, &pool) != VK_SUCCESS) return VK_NULL_HANDLE;
    l->descriptorPools.push_back(pool);
    return pool;
}

/// Allocates and writes the two descriptor sets for the current bindings, then binds them.
static void bindDescriptors(CMVCommandList *l, VkPipelineBindPoint bindPoint) {
    CMVDevice *d = l->device;
    if (!l->bindingsDirty && l->lastSets[0]) {
        vk.vkCmdBindDescriptorSets(l->cb, bindPoint, d->layout, 0, 2, l->lastSets, 0, nullptr);
        return;
    }
    VkDescriptorSet sets[2] = {VK_NULL_HANDLE, VK_NULL_HANDLE};
    for (int attempt = 0; attempt < 2 && !sets[0]; attempt++) {
        VkDescriptorPool pool = nextDescriptorPool(l);
        if (!pool) return;
        VkDescriptorSetLayout layouts[2] = {d->setLayout0, d->setLayout1};
        VkDescriptorSetAllocateInfo dsai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, nullptr, pool, 2, layouts};
        if (vk.vkAllocateDescriptorSets(d->device, &dsai, sets) != VK_SUCCESS) { sets[0] = sets[1] = VK_NULL_HANDLE; l->descriptorPoolIndex++; }
    }
    if (!sets[0]) return;

    std::vector<VkDescriptorBufferInfo> bufferInfos;
    std::vector<VkDescriptorImageInfo> imageInfos;
    bufferInfos.reserve(kSet0Bindings + kSet1Bindings);
    imageInfos.reserve(kSet0Bindings);
    std::vector<VkWriteDescriptorSet> writes;
    writes.reserve(kSet0Bindings + kSet1Bindings);
    auto write = [&](VkDescriptorSet set, uint32_t binding, VkDescriptorType type, const VkDescriptorBufferInfo *b, const VkDescriptorImageInfo *i) {
        VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
        w.dstSet = set;
        w.dstBinding = binding;
        w.descriptorCount = 1;
        w.descriptorType = type;
        w.pBufferInfo = b;
        w.pImageInfo = i;
        writes.push_back(w);
    };
    for (uint32_t half = 0; half < 2; half++) {
        for (uint32_t i = 0; i < kSlots; i++) {
            const BufferBinding &bb = l->shaderBuffers[half][i];
            CMVBuffer *buffer = bb.buffer ? bb.buffer : d->dummyBuffer;
            uint64_t offset = bb.buffer ? std::min(bb.offset, buffer->length - 1) : 0;
            bufferInfos.push_back({buffer->buffer, offset, VK_WHOLE_SIZE});
            write(sets[0], half * kHalf + kBindUniform + i, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, &bufferInfos.back(), nullptr);
            bufferInfos.push_back({buffer->buffer, offset, VK_WHOLE_SIZE});
            write(sets[1], half * kSlots + i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, &bufferInfos.back(), nullptr);
        }
        for (uint32_t i = 0; i < kSlots; i++) {
            CMVTexture *t = l->textures[half][i] ? l->textures[half][i] : d->dummyTexture;
            imageInfos.push_back({VK_NULL_HANDLE, t->view, VK_IMAGE_LAYOUT_GENERAL});
            write(sets[0], half * kHalf + kBindSampled + i, VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, nullptr, &imageInfos.back());
            CMVTexture *st = t->storage ? t : d->dummyTexture;
            imageInfos.push_back({VK_NULL_HANDLE, st->view, VK_IMAGE_LAYOUT_GENERAL});
            write(sets[0], half * kHalf + kBindStorageImage + i, VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, nullptr, &imageInfos.back());
        }
        for (uint32_t i = 0; i < kSlots; i++) {
            VkSampler s = l->samplers[half][i] ? l->samplers[half][i]->sampler : d->dummySampler;
            imageInfos.push_back({s, VK_NULL_HANDLE, VK_IMAGE_LAYOUT_UNDEFINED});
            write(sets[0], half * kHalf + kBindSampler + i, VK_DESCRIPTOR_TYPE_SAMPLER, nullptr, &imageInfos.back());
        }
    }
    vk.vkUpdateDescriptorSets(d->device, (uint32_t)writes.size(), writes.data(), 0, nullptr);
    vk.vkCmdBindDescriptorSets(l->cb, bindPoint, d->layout, 0, 2, sets, 0, nullptr);
    l->lastSets[0] = sets[0];
    l->lastSets[1] = sets[1];
    l->bindingsDirty = false;
}

static void emitDynamicState(CMVCommandList *l) {
    VkCommandBuffer cb = l->cb;
    if (!l->viewportSet) { l->viewport = {0, (float)l->renderHeight, (float)l->renderWidth, -(float)l->renderHeight, 0, 1}; }
    if (!l->scissorSet) { l->scissor = {{0, 0}, {l->renderWidth, l->renderHeight}}; }
    vk.vkCmdSetViewport(cb, 0, 1, &l->viewport);
    vk.vkCmdSetScissor(cb, 0, 1, &l->scissor);
    vk.vkCmdSetPrimitiveTopology(cb, l->topology);
    vk.vkCmdSetCullMode(cb, l->cullMode);
    vk.vkCmdSetFrontFace(cb, l->frontFace);
    vk.vkCmdSetDepthTestEnable(cb, l->depthTest);
    vk.vkCmdSetDepthWriteEnable(cb, l->depthWrite);
    vk.vkCmdSetDepthCompareOp(cb, l->depthCompare);
    vk.vkCmdSetStencilTestEnable(cb, l->stencilTest);
    vk.vkCmdSetStencilOp(cb, VK_STENCIL_FACE_FRONT_BIT, l->front.failOp, l->front.passOp, l->front.depthFailOp, l->front.compareOp);
    vk.vkCmdSetStencilOp(cb, VK_STENCIL_FACE_BACK_BIT, l->back.failOp, l->back.passOp, l->back.depthFailOp, l->back.compareOp);
    vk.vkCmdSetStencilCompareMask(cb, VK_STENCIL_FACE_FRONT_BIT, l->front.compareMask);
    vk.vkCmdSetStencilCompareMask(cb, VK_STENCIL_FACE_BACK_BIT, l->back.compareMask);
    vk.vkCmdSetStencilWriteMask(cb, VK_STENCIL_FACE_FRONT_BIT, l->front.writeMask);
    vk.vkCmdSetStencilWriteMask(cb, VK_STENCIL_FACE_BACK_BIT, l->back.writeMask);
    vk.vkCmdSetStencilReference(cb, VK_STENCIL_FACE_FRONT_AND_BACK, l->stencilReference);
    vk.vkCmdSetBlendConstants(cb, l->blendConstants);
}

static VkAttachmentLoadOp loadOp(uint32_t metal) { return metal == 2 ? VK_ATTACHMENT_LOAD_OP_CLEAR : metal == 1 ? VK_ATTACHMENT_LOAD_OP_LOAD : VK_ATTACHMENT_LOAD_OP_DONT_CARE; }
static VkAttachmentStoreOp storeOp(uint32_t metal) { return metal == 0 ? VK_ATTACHMENT_STORE_OP_DONT_CARE : VK_ATTACHMENT_STORE_OP_STORE; }

void cmv_commandlist_begin_render_pass(CMVCommandList *l, CMVTexture **colors, const uint32_t *loadActions, const uint32_t *storeActions, const float *clearColors, uint32_t colorCount,
                                       CMVTexture *depth, uint32_t depthLoadAction, uint32_t depthStoreAction, float clearDepth,
                                       CMVTexture *stencil, uint32_t stencilLoadAction, uint32_t stencilStoreAction, uint32_t clearStencil) {
    if (!l || !l->recording) return;
    if (l->rendering) cmv_commandlist_end_render_pass(l);
    fullBarrier(l->cb);
    std::vector<VkRenderingAttachmentInfo> colorInfos;
    uint32_t w = 0, h = 0;
    for (uint32_t i = 0; i < colorCount; i++) {
        CMVTexture *t = colors[i];
        VkRenderingAttachmentInfo a{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
        a.imageView = t ? t->view : VK_NULL_HANDLE;
        a.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
        a.loadOp = loadOp(loadActions[i]);
        a.storeOp = storeOp(storeActions[i]);
        a.clearValue.color = {{clearColors[i * 4], clearColors[i * 4 + 1], clearColors[i * 4 + 2], clearColors[i * 4 + 3]}};
        colorInfos.push_back(a);
        if (t) { w = w ? std::min(w, t->width) : t->width; h = h ? std::min(h, t->height) : t->height; }
    }
    VkRenderingAttachmentInfo depthInfo{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO}, stencilInfo{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    if (depth) {
        depthInfo.imageView = depth->view;
        depthInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
        depthInfo.loadOp = loadOp(depthLoadAction);
        depthInfo.storeOp = storeOp(depthStoreAction);
        depthInfo.clearValue.depthStencil = {clearDepth, clearStencil};
        w = w ? std::min(w, depth->width) : depth->width; h = h ? std::min(h, depth->height) : depth->height;
    }
    if (stencil) {
        stencilInfo.imageView = stencil->view;
        stencilInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
        stencilInfo.loadOp = loadOp(stencilLoadAction);
        stencilInfo.storeOp = storeOp(stencilStoreAction);
        stencilInfo.clearValue.depthStencil = {clearDepth, clearStencil};
        w = w ? std::min(w, stencil->width) : stencil->width; h = h ? std::min(h, stencil->height) : stencil->height;
    }
    if (w == 0 || h == 0) return;
    VkRenderingInfo ri{VK_STRUCTURE_TYPE_RENDERING_INFO};
    ri.renderArea = {{0, 0}, {w, h}};
    ri.layerCount = 1;
    ri.colorAttachmentCount = (uint32_t)colorInfos.size();
    ri.pColorAttachments = colorInfos.data();
    ri.pDepthAttachment = depth ? &depthInfo : nullptr;
    ri.pStencilAttachment = stencil ? &stencilInfo : nullptr;
    vk.vkCmdBeginRendering(l->cb, &ri);
    l->rendering = true;
    l->renderWidth = w;
    l->renderHeight = h;
    // Metal's encoder defaults.
    l->viewportSet = l->scissorSet = false;
    l->cullMode = VK_CULL_MODE_NONE;
    l->frontFace = VK_FRONT_FACE_CLOCKWISE;
    l->depthTest = l->depthWrite = false;
    l->depthCompare = VK_COMPARE_OP_ALWAYS;
    l->stencilTest = false;
    l->stencilReference = 0;
    l->graphics = nullptr;
    cmv_commandlist_clear_bindings(l);
}

void cmv_commandlist_end_render_pass(CMVCommandList *l) {
    if (!l || !l->rendering) return;
    vk.vkCmdEndRendering(l->cb);
    l->rendering = false;
    l->graphics = nullptr;
}

void cmv_commandlist_clear_bindings(CMVCommandList *l) {
    if (!l) return;
    for (int h = 0; h < 2; h++) for (int i = 0; i < kSlots; i++) { l->shaderBuffers[h][i] = {}; l->textures[h][i] = nullptr; l->samplers[h][i] = nullptr; }
    for (auto &v : l->vertexBuffers) v = {};
    l->bindingsDirty = true;
}

void cmv_commandlist_set_pipeline(CMVCommandList *l, CMVPipeline *p) {
    if (!l || !p || !l->recording) return;
    if (p->compute) {
        if (l->rendering) cmv_commandlist_end_render_pass(l);
        l->compute = p;
        vk.vkCmdBindPipeline(l->cb, VK_PIPELINE_BIND_POINT_COMPUTE, p->pipeline);
        return;
    }
    if (!l->rendering) return;
    l->graphics = p;
    vk.vkCmdBindPipeline(l->cb, VK_PIPELINE_BIND_POINT_GRAPHICS, p->pipeline);
    emitDynamicState(l);
}

void cmv_commandlist_set_viewport(CMVCommandList *l, float x, float y, float w, float h, float zmin, float zmax) {
    if (!l) return;
    // Metal's viewport has its origin at the top-left with +y down in the framebuffer and
    // +y up in clip space; a negative-height Vulkan viewport gives the same mapping.
    l->viewport = {x, y + h, w, -h, zmin, zmax};
    l->viewportSet = true;
    if (l->rendering && l->graphics) vk.vkCmdSetViewport(l->cb, 0, 1, &l->viewport);
}

void cmv_commandlist_set_scissor(CMVCommandList *l, int32_t x, int32_t y, int32_t w, int32_t h) {
    if (!l) return;
    l->scissor = {{x, y}, {(uint32_t)std::max(0, w), (uint32_t)std::max(0, h)}};
    l->scissorSet = true;
    if (l->rendering && l->graphics) vk.vkCmdSetScissor(l->cb, 0, 1, &l->scissor);
}

void cmv_commandlist_set_cull_mode(CMVCommandList *l, uint32_t mode) { if (!l) return; l->cullMode = mode; if (l->rendering && l->graphics) vk.vkCmdSetCullMode(l->cb, mode); }
void cmv_commandlist_set_front_face(CMVCommandList *l, uint32_t face) { if (!l) return; l->frontFace = (VkFrontFace)face; if (l->rendering && l->graphics) vk.vkCmdSetFrontFace(l->cb, l->frontFace); }

void cmv_commandlist_set_depth_state(CMVCommandList *l, bool testEnabled, bool writeEnabled, uint32_t compareOp) {
    if (!l) return;
    l->depthTest = testEnabled; l->depthWrite = writeEnabled; l->depthCompare = (VkCompareOp)compareOp;
    if (l->rendering && l->graphics) {
        vk.vkCmdSetDepthTestEnable(l->cb, testEnabled);
        vk.vkCmdSetDepthWriteEnable(l->cb, writeEnabled);
        vk.vkCmdSetDepthCompareOp(l->cb, l->depthCompare);
    }
}

void cmv_commandlist_set_stencil_state(CMVCommandList *l, bool enabled,
                                       uint32_t frontFail, uint32_t frontPass, uint32_t frontDepthFail, uint32_t frontCompare, uint32_t frontReadMask, uint32_t frontWriteMask,
                                       uint32_t backFail, uint32_t backPass, uint32_t backDepthFail, uint32_t backCompare, uint32_t backReadMask, uint32_t backWriteMask) {
    if (!l) return;
    l->stencilTest = enabled;
    l->front = {(VkStencilOp)frontFail, (VkStencilOp)frontPass, (VkStencilOp)frontDepthFail, (VkCompareOp)frontCompare, frontReadMask, frontWriteMask, l->stencilReference};
    l->back = {(VkStencilOp)backFail, (VkStencilOp)backPass, (VkStencilOp)backDepthFail, (VkCompareOp)backCompare, backReadMask, backWriteMask, l->stencilReference};
    if (l->rendering && l->graphics) emitDynamicState(l);
}

void cmv_commandlist_set_stencil_reference(CMVCommandList *l, uint32_t reference) {
    if (!l) return;
    l->stencilReference = reference;
    if (l->rendering && l->graphics) vk.vkCmdSetStencilReference(l->cb, VK_STENCIL_FACE_FRONT_AND_BACK, reference);
}

void cmv_commandlist_set_blend_constants(CMVCommandList *l, float r, float g, float b, float a) {
    if (!l) return;
    l->blendConstants[0] = r; l->blendConstants[1] = g; l->blendConstants[2] = b; l->blendConstants[3] = a;
    if (l->rendering && l->graphics) vk.vkCmdSetBlendConstants(l->cb, l->blendConstants);
}

void cmv_commandlist_set_vertex_buffer(CMVCommandList *l, uint32_t binding, CMVBuffer *buffer, uint64_t offset) {
    if (!l || binding >= 32) return;
    l->vertexBuffers[binding] = {buffer, offset};
}

void cmv_commandlist_set_shader_buffer(CMVCommandList *l, uint32_t stage, uint32_t slot, CMVBuffer *buffer, uint64_t offset) {
    if (!l || stage > 1 || slot >= kSlots) return;
    l->shaderBuffers[stage][slot] = {buffer, offset};
    l->bindingsDirty = true;
}

void cmv_commandlist_set_shader_texture(CMVCommandList *l, uint32_t stage, uint32_t slot, CMVTexture *texture) {
    if (!l || stage > 1 || slot >= kSlots) return;
    l->textures[stage][slot] = texture;
    l->bindingsDirty = true;
}

void cmv_commandlist_set_sampler(CMVCommandList *l, uint32_t stage, uint32_t slot, CMVSampler *sampler) {
    if (!l || stage > 1 || slot >= kSlots) return;
    l->samplers[stage][slot] = sampler;
    l->bindingsDirty = true;
}

static bool prepareDraw(CMVCommandList *l, uint32_t topology) {
    if (!l || !l->rendering || !l->graphics) return false;
    if (l->topology != (VkPrimitiveTopology)topology) { l->topology = (VkPrimitiveTopology)topology; vk.vkCmdSetPrimitiveTopology(l->cb, l->topology); }
    for (uint32_t b : l->graphics->vertexBindings) {
        const BufferBinding &vb = l->vertexBuffers[b];
        VkBuffer buffer = vb.buffer ? vb.buffer->buffer : l->device->dummyBuffer->buffer;
        VkDeviceSize offset = vb.buffer ? vb.offset : 0;
        vk.vkCmdBindVertexBuffers(l->cb, b, 1, &buffer, &offset);
    }
    bindDescriptors(l, VK_PIPELINE_BIND_POINT_GRAPHICS);
    return true;
}

void cmv_commandlist_draw(CMVCommandList *l, uint32_t topology, uint32_t vertexStart, uint32_t vertexCount, uint32_t instanceCount) {
    if (!prepareDraw(l, topology)) return;
    vk.vkCmdDraw(l->cb, vertexCount, std::max(1u, instanceCount), vertexStart, 0);
}

void cmv_commandlist_draw_indexed(CMVCommandList *l, uint32_t topology, uint32_t indexCount, bool index32, CMVBuffer *indexBuffer, uint64_t indexOffset, uint32_t instanceCount) {
    if (!indexBuffer || !prepareDraw(l, topology)) return;
    vk.vkCmdBindIndexBuffer(l->cb, indexBuffer->buffer, indexOffset, index32 ? VK_INDEX_TYPE_UINT32 : VK_INDEX_TYPE_UINT16);
    vk.vkCmdDrawIndexed(l->cb, indexCount, std::max(1u, instanceCount), 0, 0, 0);
}

void cmv_commandlist_dispatch(CMVCommandList *l, uint32_t x, uint32_t y, uint32_t z) {
    if (!l || !l->recording || !l->compute) return;
    if (l->rendering) cmv_commandlist_end_render_pass(l);
    fullBarrier(l->cb);
    bindDescriptors(l, VK_PIPELINE_BIND_POINT_COMPUTE);
    vk.vkCmdDispatch(l->cb, std::max(1u, x), std::max(1u, y), std::max(1u, z));
}

static bool beginTransfer(CMVCommandList *l) {
    if (!l || !l->recording) return false;
    if (l->rendering) cmv_commandlist_end_render_pass(l);
    fullBarrier(l->cb);
    return true;
}

void cmv_commandlist_copy_buffer(CMVCommandList *l, CMVBuffer *src, uint64_t srcOffset, CMVBuffer *dst, uint64_t dstOffset, uint64_t size) {
    if (!src || !dst || !beginTransfer(l)) return;
    if (srcOffset >= src->length || dstOffset >= dst->length) return;
    VkBufferCopy region{srcOffset, dstOffset, std::min({size, src->length - srcOffset, dst->length - dstOffset})};
    if (region.size == 0) return;
    vk.vkCmdCopyBuffer(l->cb, src->buffer, dst->buffer, 1, &region);
}

void cmv_commandlist_fill_buffer(CMVCommandList *l, CMVBuffer *dst, uint64_t offset, uint64_t size, uint8_t value) {
    if (!dst || !beginTransfer(l) || offset >= dst->length) return;
    size = std::min(size, dst->length - offset);
    if (size == 0) return;
    // vkCmdFillBuffer needs 4-byte alignment; the ragged ends go through a staging copy.
    uint64_t alignedStart = (offset + 3) & ~3ull, alignedEnd = (offset + size) & ~3ull;
    auto stagingCopy = [&](uint64_t at, uint64_t n) {
        if (n == 0) return;
        CMVBuffer *s = createBuffer(l->device, n);
        if (!s) return;
        memset(s->mapped, value, (size_t)n);
        l->temporaries.push_back(s);
        VkBufferCopy region{0, at, n};
        vk.vkCmdCopyBuffer(l->cb, s->buffer, dst->buffer, 1, &region);
    };
    if (alignedStart >= alignedEnd) { stagingCopy(offset, size); return; }
    stagingCopy(offset, alignedStart - offset);
    uint32_t word = (uint32_t)value * 0x01010101u;
    vk.vkCmdFillBuffer(l->cb, dst->buffer, alignedStart, alignedEnd - alignedStart, word);
    stagingCopy(alignedEnd, offset + size - alignedEnd);
}

void cmv_commandlist_copy_texture(CMVCommandList *l, CMVTexture *src, uint32_t srcLevel, uint32_t sx, uint32_t sy, CMVTexture *dst, uint32_t dstLevel, uint32_t dx, uint32_t dy, uint32_t width, uint32_t height) {
    if (!src || !dst || !beginTransfer(l) || width == 0 || height == 0) return;
    VkImageCopy region{};
    region.srcSubresource = {copyAspect(src), srcLevel, 0, 1};
    region.srcOffset = {(int32_t)sx, (int32_t)sy, 0};
    region.dstSubresource = {copyAspect(dst), dstLevel, 0, 1};
    region.dstOffset = {(int32_t)dx, (int32_t)dy, 0};
    region.extent = {width, height, 1};
    vk.vkCmdCopyImage(l->cb, src->image, VK_IMAGE_LAYOUT_GENERAL, dst->image, VK_IMAGE_LAYOUT_GENERAL, 1, &region);
}

void cmv_commandlist_copy_buffer_to_texture(CMVCommandList *l, CMVBuffer *src, uint64_t srcOffset, uint32_t bytesPerRow, CMVTexture *dst, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height) {
    if (!src || !dst || !beginTransfer(l) || width == 0 || height == 0) return;
    if (bytesPerRow % dst->texelSize != 0 || srcOffset % 4 != 0 || srcOffset % dst->texelSize != 0) {
        // Repack into an aligned staging buffer.
        uint32_t tight = width * dst->texelSize;
        CMVBuffer *s = createBuffer(l->device, (uint64_t)tight * height);
        if (!s) return;
        for (uint32_t r = 0; r < height; r++) memcpy((char *)s->mapped + (size_t)r * tight, (const char *)src->mapped + srcOffset + (size_t)r * bytesPerRow, tight);
        l->temporaries.push_back(s);
        recordBufferToImage(l->cb, s, 0, tight, dst, level, x, y, width, height);
        return;
    }
    recordBufferToImage(l->cb, src, srcOffset, bytesPerRow, dst, level, x, y, width, height);
}

void cmv_commandlist_copy_texture_to_buffer(CMVCommandList *l, CMVTexture *src, uint32_t level, uint32_t x, uint32_t y, uint32_t width, uint32_t height, CMVBuffer *dst, uint64_t dstOffset, uint32_t bytesPerRow) {
    if (!src || !dst || !beginTransfer(l) || width == 0 || height == 0) return;
    if (bytesPerRow % src->texelSize != 0 || dstOffset % 4 != 0 || dstOffset % src->texelSize != 0) return;   // the Swift side falls back to a readback
    recordImageToBuffer(l->cb, src, level, x, y, width, height, dst, dstOffset, bytesPerRow);
}

void cmv_commandlist_generate_mipmaps(CMVCommandList *l, CMVTexture *t) {
    if (!t || t->levels < 2 || !beginTransfer(l)) return;
    uint32_t w = t->width, h = t->height;
    for (uint32_t level = 1; level < t->levels; level++) {
        uint32_t nw = std::max(1u, w / 2), nh = std::max(1u, h / 2);
        VkImageBlit blit{};
        blit.srcSubresource = {copyAspect(t), level - 1, 0, 1};
        blit.srcOffsets[1] = {(int32_t)w, (int32_t)h, 1};
        blit.dstSubresource = {copyAspect(t), level, 0, 1};
        blit.dstOffsets[1] = {(int32_t)nw, (int32_t)nh, 1};
        vk.vkCmdBlitImage(l->cb, t->image, VK_IMAGE_LAYOUT_GENERAL, t->image, VK_IMAGE_LAYOUT_GENERAL, 1, &blit, VK_FILTER_LINEAR);
        fullBarrier(l->cb);
        w = nw; h = nh;
    }
}

uint64_t cmv_commandlist_execute(CMVCommandList *l, CMVQueue *q) {
    if (!l || !q || !l->recording) return 0;
    if (l->rendering) cmv_commandlist_end_render_pass(l);
    fullBarrier(l->cb);
    l->recording = false;
    if (vk.vkEndCommandBuffer(l->cb) != VK_SUCCESS) return 0;
    uint64_t value = submit(q, l->cb);
    l->lastFence = value && !q->pending.empty() ? q->pending.back().second : VK_NULL_HANDLE;
    return value;
}

// MARK: Swap chains (presentation)

struct CMVSwapChain {
    CMVDevice *device = nullptr;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkFormat format = VK_FORMAT_UNDEFINED;
    VkColorSpaceKHR colorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    uint32_t width = 0, height = 0, requestedImages = 2;
    bool vsync = true;
    VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;
    std::vector<CMVTexture *> images;             // wrappers over the chain's images (ownsImage = false)
    std::vector<VkSemaphore> presentSemaphores;   // one per image: transition done → present may read
    VkSemaphore acquireSemaphore = VK_NULL_HANDLE;
    VkFence acquireFence = VK_NULL_HANDLE;
    uint32_t current = UINT32_MAX;                // the acquired image, or none
    bool outOfDate = false;
    std::string lastError;
};

static void setChainError(CMVSwapChain *sc, const std::string &message) { sc->lastError = message; }

static void destroyChainImages(CMVSwapChain *sc) {
    for (CMVTexture *t : sc->images) cmv_texture_release(t);
    sc->images.clear();
    for (VkSemaphore s : sc->presentSemaphores) if (s) vk.destroySemaphore(sc->device->device, s, nullptr);
    sc->presentSemaphores.clear();
    sc->current = UINT32_MAX;
}

/// (Re)creates the VkSwapchainKHR for the chain's size, format and present mode.
static bool createChain(CMVSwapChain *sc) {
    CMVDevice *d = sc->device;
    vk.vkDeviceWaitIdle(d->device);
    VkSurfaceCapabilitiesKHR caps{};
    if (vk.getPhysicalDeviceSurfaceCapabilitiesKHR(d->physical, sc->surface, &caps) != VK_SUCCESS) { setChainError(sc, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed"); return false; }
    uint32_t count = 0;
    vk.getPhysicalDeviceSurfaceFormatsKHR(d->physical, sc->surface, &count, nullptr);
    std::vector<VkSurfaceFormatKHR> formats(count);
    if (count) vk.getPhysicalDeviceSurfaceFormatsKHR(d->physical, sc->surface, &count, formats.data());
    bool formatFound = false;
    for (auto &f : formats) if (f.format == sc->format || (count == 1 && f.format == VK_FORMAT_UNDEFINED)) { sc->colorSpace = f.colorSpace; formatFound = true; break; }
    if (!formatFound) { setChainError(sc, "the surface does not support VkFormat " + std::to_string((int)sc->format)); return false; }
    count = 0;
    vk.getPhysicalDeviceSurfacePresentModesKHR(d->physical, sc->surface, &count, nullptr);
    std::vector<VkPresentModeKHR> modes(count);
    if (count) vk.getPhysicalDeviceSurfacePresentModesKHR(d->physical, sc->surface, &count, modes.data());
    auto hasMode = [&](VkPresentModeKHR m) { return std::find(modes.begin(), modes.end(), m) != modes.end(); };
    sc->presentMode = VK_PRESENT_MODE_FIFO_KHR;   // always available
    if (!sc->vsync) {
        if (hasMode(VK_PRESENT_MODE_MAILBOX_KHR)) sc->presentMode = VK_PRESENT_MODE_MAILBOX_KHR;
        else if (hasMode(VK_PRESENT_MODE_IMMEDIATE_KHR)) sc->presentMode = VK_PRESENT_MODE_IMMEDIATE_KHR;
    }
    VkExtent2D extent{sc->width, sc->height};
    if (caps.currentExtent.width != UINT32_MAX && caps.currentExtent.width != 0 && caps.currentExtent.height != 0) {
        // X11 reports the window's size; the chain must match it (the window backend sizes
        // the child window before the chain), so take it when it disagrees.
        extent = caps.currentExtent;
    }
    extent.width = std::max(caps.minImageExtent.width, std::min(caps.maxImageExtent.width, extent.width));
    extent.height = std::max(caps.minImageExtent.height, std::min(caps.maxImageExtent.height, extent.height));
    if (extent.width == 0 || extent.height == 0) { setChainError(sc, "the surface has no size yet"); return false; }
    uint32_t imageCount = std::max(caps.minImageCount, sc->requestedImages);
    if (caps.maxImageCount) imageCount = std::min(imageCount, caps.maxImageCount);
    VkImageUsageFlags usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    for (VkImageUsageFlags u : {(VkImageUsageFlags)VK_IMAGE_USAGE_TRANSFER_SRC_BIT, (VkImageUsageFlags)VK_IMAGE_USAGE_TRANSFER_DST_BIT, (VkImageUsageFlags)VK_IMAGE_USAGE_SAMPLED_BIT}) if (caps.supportedUsageFlags & u) usage |= u;
    if (!(caps.supportedUsageFlags & VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) { setChainError(sc, "the surface's images cannot be colour attachments"); return false; }
    VkCompositeAlphaFlagBitsKHR alpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    if (!(caps.supportedCompositeAlpha & alpha)) {
        for (VkCompositeAlphaFlagBitsKHR a : {VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR, VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR, VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR}) if (caps.supportedCompositeAlpha & a) { alpha = a; break; }
    }
    VkSwapchainCreateInfoKHR sci{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    sci.surface = sc->surface;
    sci.minImageCount = imageCount;
    sci.imageFormat = sc->format;
    sci.imageColorSpace = sc->colorSpace;
    sci.imageExtent = extent;
    sci.imageArrayLayers = 1;
    sci.imageUsage = usage;
    sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    sci.preTransform = caps.currentTransform & VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR ? VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR : caps.currentTransform;
    sci.compositeAlpha = alpha;
    sci.presentMode = sc->presentMode;
    sci.clipped = VK_TRUE;
    sci.oldSwapchain = sc->swapchain;
    VkSwapchainKHR chain = VK_NULL_HANDLE;
    VkResult r = vk.createSwapchainKHR(d->device, &sci, nullptr, &chain);
    destroyChainImages(sc);
    if (sc->swapchain) vk.destroySwapchainKHR(d->device, sc->swapchain, nullptr);
    sc->swapchain = chain;
    if (r != VK_SUCCESS) { setChainError(sc, "vkCreateSwapchainKHR failed (" + std::to_string((int)r) + ")"); return false; }
    sc->width = extent.width;
    sc->height = extent.height;
    count = 0;
    vk.getSwapchainImagesKHR(d->device, chain, &count, nullptr);
    std::vector<VkImage> vkImages(count);
    if (count) vk.getSwapchainImagesKHR(d->device, chain, &count, vkImages.data());
    for (VkImage image : vkImages) {
        auto *t = new CMVTexture();
        t->device = d;
        t->image = image;
        t->ownsImage = false;
        t->format = sc->format;
        t->aspect = VK_IMAGE_ASPECT_COLOR_BIT;
        t->width = extent.width; t->height = extent.height; t->levels = 1; t->samples = 1;
        t->texelSize = texelSizeOf(sc->format);
        t->layout = VK_IMAGE_LAYOUT_UNDEFINED;
        VkImageViewCreateInfo vci{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        vci.image = image;
        vci.viewType = VK_IMAGE_VIEW_TYPE_2D;
        vci.format = sc->format;
        vci.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        if (vk.vkCreateImageView(d->device, &vci, nullptr, &t->view) != VK_SUCCESS) { delete t; setChainError(sc, "vkCreateImageView failed for a swap-chain image"); return false; }
        sc->images.push_back(t);
        VkSemaphoreCreateInfo semci{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VkSemaphore s = VK_NULL_HANDLE;
        vk.createSemaphore(d->device, &semci, nullptr, &s);
        sc->presentSemaphores.push_back(s);
    }
    if (sc->images.empty()) { setChainError(sc, "vkGetSwapchainImagesKHR returned no images"); return false; }
    sc->outOfDate = false;
    sc->lastError.clear();
    return true;
}

CMVSwapChain *cmv_swapchain_create(CMVDevice *d, uint32_t surfaceKind, void *display, uintptr_t window, uint32_t width, uint32_t height, uint32_t vkFormat, uint32_t imageCount, bool vsync) {
    if (!d) return nullptr;
    if (!d->presentable || !vk.createSwapchainKHR || !vk.acquireNextImageKHR || !vk.queuePresentKHR) { setError("the device has no VK_KHR_swapchain (no presentation support)"); return nullptr; }
    if (!display || !window || width == 0 || height == 0) { setError("cmv_swapchain_create: no surface or an empty size"); return nullptr; }
    auto *sc = new CMVSwapChain();
    sc->device = d;
    sc->format = (VkFormat)vkFormat;
    sc->width = width; sc->height = height;
    sc->requestedImages = std::max(1u, imageCount);
    sc->vsync = vsync;
    VkResult r = VK_ERROR_EXTENSION_NOT_PRESENT;
    if (surfaceKind == CMV_SURFACE_XLIB) {
        if (!d->xlibSurfaces || !vk.createXlibSurfaceKHR) { setError("VK_KHR_xlib_surface is not available"); delete sc; return nullptr; }
        CMVXlibSurfaceCreateInfo ci{kXlibSurfaceCreateInfo, nullptr, 0, display, (unsigned long)window};
        r = ((CMVCreateXlibSurface)vk.createXlibSurfaceKHR)(d->instance, &ci, nullptr, &sc->surface);
    } else if (surfaceKind == CMV_SURFACE_WAYLAND) {
        if (!d->waylandSurfaces || !vk.createWaylandSurfaceKHR) { setError("VK_KHR_wayland_surface is not available"); delete sc; return nullptr; }
        CMVWaylandSurfaceCreateInfo ci{kWaylandSurfaceCreateInfo, nullptr, 0, display, (void *)window};
        r = ((CMVCreateWaylandSurface)vk.createWaylandSurfaceKHR)(d->instance, &ci, nullptr, &sc->surface);
    } else {
        setError("unknown surface kind");
        delete sc;
        return nullptr;
    }
    if (r != VK_SUCCESS || !sc->surface) { setError("vkCreate*SurfaceKHR failed"); delete sc; return nullptr; }
    VkBool32 supported = VK_FALSE;
    if (vk.getPhysicalDeviceSurfaceSupportKHR(d->physical, d->family, sc->surface, &supported) != VK_SUCCESS || !supported) {
        setError("the device's queue family cannot present to this surface");
        vk.destroySurfaceKHR(d->instance, sc->surface, nullptr);
        delete sc;
        return nullptr;
    }
    VkSemaphoreCreateInfo semci{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    vk.createSemaphore(d->device, &semci, nullptr, &sc->acquireSemaphore);
    VkFenceCreateInfo fci{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    vk.vkCreateFence(d->device, &fci, nullptr, &sc->acquireFence);
    if (!createChain(sc)) { setError(sc->lastError.c_str()); cmv_swapchain_release(sc); return nullptr; }
    g_lastError[0] = 0;
    return sc;
}

void cmv_swapchain_release(CMVSwapChain *sc) {
    if (!sc) return;
    CMVDevice *d = sc->device;
    vk.vkDeviceWaitIdle(d->device);
    destroyChainImages(sc);
    if (sc->swapchain) vk.destroySwapchainKHR(d->device, sc->swapchain, nullptr);
    if (sc->acquireSemaphore) vk.destroySemaphore(d->device, sc->acquireSemaphore, nullptr);
    if (sc->acquireFence) vk.vkDestroyFence(d->device, sc->acquireFence, nullptr);
    if (sc->surface) vk.destroySurfaceKHR(d->instance, sc->surface, nullptr);
    delete sc;
}

bool cmv_swapchain_resize(CMVSwapChain *sc, uint32_t width, uint32_t height) {
    if (!sc || width == 0 || height == 0) return false;
    sc->width = width;
    sc->height = height;
    return createChain(sc);
}

void cmv_swapchain_set_vsync(CMVSwapChain *sc, bool vsync) { if (sc) sc->vsync = vsync; }

CMVTexture *cmv_swapchain_acquire(CMVSwapChain *sc) {
    if (!sc || !sc->swapchain) return nullptr;
    CMVDevice *d = sc->device;
    for (int attempt = 0; attempt < 2; attempt++) {
        if (sc->outOfDate && !createChain(sc)) return nullptr;
        uint32_t index = 0;
        vk.vkResetFences(d->device, 1, &sc->acquireFence);
        VkResult r = vk.acquireNextImageKHR(d->device, sc->swapchain, 2000000000ull, sc->acquireSemaphore, sc->acquireFence, &index);
        if (r == VK_ERROR_OUT_OF_DATE_KHR) { sc->outOfDate = true; continue; }
        if (r == VK_SUBOPTIMAL_KHR) sc->outOfDate = true;   // present this one, re-create afterwards
        else if (r != VK_SUCCESS) { setChainError(sc, r == VK_TIMEOUT ? "vkAcquireNextImageKHR timed out" : "vkAcquireNextImageKHR failed (" + std::to_string((int)r) + ")"); if (r == VK_ERROR_DEVICE_LOST) d->lost = true; return nullptr; }
        if (vk.vkWaitForFences(d->device, 1, &sc->acquireFence, VK_TRUE, 2000000000ull) != VK_SUCCESS) { setChainError(sc, "waiting for the acquired image timed out"); return nullptr; }
        CMVTexture *t = sc->images[index];
        // The image is ours: into GENERAL, after the presentation engine's semaphore.
        VkImageLayout from = t->layout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR ? VK_IMAGE_LAYOUT_PRESENT_SRC_KHR : VK_IMAGE_LAYOUT_UNDEFINED;
        if (!runUtility(d, [&](VkCommandBuffer cb) { transitionLayout(cb, t, from, VK_IMAGE_LAYOUT_GENERAL); }, sc->acquireSemaphore)) { setChainError(sc, "the acquire transition failed"); return nullptr; }
        sc->current = index;
        return t;
    }
    return nullptr;
}

bool cmv_swapchain_present(CMVSwapChain *sc) {
    if (!sc || sc->current == UINT32_MAX || !sc->swapchain) { if (sc) setChainError(sc, "present without an acquired image"); return false; }
    CMVDevice *d = sc->device;
    uint32_t index = sc->current;
    sc->current = UINT32_MAX;
    CMVTexture *t = sc->images[index];
    VkSemaphore done = sc->presentSemaphores[index];
    if (!runUtility(d, [&](VkCommandBuffer cb) { transitionLayout(cb, t, VK_IMAGE_LAYOUT_GENERAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR); }, VK_NULL_HANDLE, done)) { setChainError(sc, "the present transition failed"); return false; }
    VkPresentInfoKHR pi{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    pi.waitSemaphoreCount = 1;
    pi.pWaitSemaphores = &done;
    pi.swapchainCount = 1;
    pi.pSwapchains = &sc->swapchain;
    pi.pImageIndices = &index;
    VkResult r;
    {
        std::lock_guard<std::mutex> lock(d->queueMutex);
        r = vk.queuePresentKHR(d->queue, &pi);
    }
    if (r == VK_SUBOPTIMAL_KHR) { sc->outOfDate = true; return true; }
    if (r == VK_ERROR_OUT_OF_DATE_KHR) { sc->outOfDate = true; setChainError(sc, "the swap chain is out of date (re-created on the next acquire)"); return false; }
    if (r != VK_SUCCESS) { if (r == VK_ERROR_DEVICE_LOST) d->lost = true; setChainError(sc, "vkQueuePresentKHR failed (" + std::to_string((int)r) + ")"); return false; }
    return true;
}

uint32_t cmv_swapchain_present_mode(CMVSwapChain *sc) { return sc ? (uint32_t)sc->presentMode : 0; }
uint32_t cmv_swapchain_image_count(CMVSwapChain *sc) { return sc ? (uint32_t)sc->images.size() : 0; }
void cmv_swapchain_last_error(CMVSwapChain *sc, char *errorOut, uint32_t errorCapacity) { copyError(errorOut, errorCapacity, sc ? sc->lastError : "no swap chain"); }

#else   // no <vulkan/vulkan.h>: stubs, the Metal module falls back to the reference device.

bool cmv_available(void) { setError("built without the Vulkan headers (install libvulkan-dev)"); return false; }
CMVDevice *cmv_device_create(bool) { setError("built without the Vulkan headers (install libvulkan-dev)"); return nullptr; }
void cmv_device_release(CMVDevice *) {}
void cmv_device_info(CMVDevice *, CMVDeviceInfo *info) { if (info) memset(info, 0, sizeof *info); }
bool cmv_device_lost(CMVDevice *) { return true; }
bool cmv_device_supports_format(CMVDevice *, uint32_t, bool) { return false; }
void cmv_device_wait_idle(CMVDevice *) {}
CMVQueue *cmv_queue_create(CMVDevice *) { return nullptr; }
void cmv_queue_release(CMVQueue *) {}
uint64_t cmv_queue_signal(CMVQueue *) { return 0; }
bool cmv_queue_fence_reached(CMVQueue *, uint64_t) { return true; }
void cmv_queue_wait(CMVQueue *, uint64_t) {}
CMVBuffer *cmv_buffer_create(CMVDevice *, uint64_t) { return nullptr; }
void cmv_buffer_release(CMVBuffer *) {}
void *cmv_buffer_map(CMVBuffer *) { return nullptr; }
uint64_t cmv_buffer_length(CMVBuffer *) { return 0; }
CMVTexture *cmv_texture_create(CMVDevice *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t) { return nullptr; }
void cmv_texture_release(CMVTexture *) {}
uint32_t cmv_texture_format(CMVTexture *) { return 0; }
bool cmv_texture_upload(CMVDevice *, CMVTexture *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, const void *, uint32_t) { return false; }
bool cmv_texture_read(CMVDevice *, CMVTexture *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, void *, uint32_t) { return false; }
CMVShader *cmv_shader_from_spirv(CMVDevice *, const void *, uint32_t, const char *, uint32_t, char *, uint32_t) { return nullptr; }
void cmv_shader_release(CMVShader *) {}
CMVSampler *cmv_sampler_create(CMVDevice *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, bool, uint32_t, float, float, uint32_t, uint32_t) { return nullptr; }
void cmv_sampler_release(CMVSampler *) {}
CMVPipeline *cmv_pipeline_create(CMVDevice *, const CMVPipelineDesc *, char *, uint32_t) { return nullptr; }
CMVPipeline *cmv_compute_pipeline_create(CMVDevice *, CMVShader *, char *, uint32_t) { return nullptr; }
void cmv_pipeline_release(CMVPipeline *) {}
CMVCommandList *cmv_commandlist_create(CMVDevice *) { return nullptr; }
void cmv_commandlist_release(CMVCommandList *) {}
void cmv_commandlist_reset(CMVCommandList *) {}
void cmv_commandlist_begin_render_pass(CMVCommandList *, CMVTexture **, const uint32_t *, const uint32_t *, const float *, uint32_t, CMVTexture *, uint32_t, uint32_t, float, CMVTexture *, uint32_t, uint32_t, uint32_t) {}
void cmv_commandlist_end_render_pass(CMVCommandList *) {}
void cmv_commandlist_clear_bindings(CMVCommandList *) {}
void cmv_commandlist_set_pipeline(CMVCommandList *, CMVPipeline *) {}
void cmv_commandlist_set_viewport(CMVCommandList *, float, float, float, float, float, float) {}
void cmv_commandlist_set_scissor(CMVCommandList *, int32_t, int32_t, int32_t, int32_t) {}
void cmv_commandlist_set_cull_mode(CMVCommandList *, uint32_t) {}
void cmv_commandlist_set_front_face(CMVCommandList *, uint32_t) {}
void cmv_commandlist_set_depth_state(CMVCommandList *, bool, bool, uint32_t) {}
void cmv_commandlist_set_stencil_state(CMVCommandList *, bool, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t) {}
void cmv_commandlist_set_stencil_reference(CMVCommandList *, uint32_t) {}
void cmv_commandlist_set_blend_constants(CMVCommandList *, float, float, float, float) {}
void cmv_commandlist_set_vertex_buffer(CMVCommandList *, uint32_t, CMVBuffer *, uint64_t) {}
void cmv_commandlist_set_shader_buffer(CMVCommandList *, uint32_t, uint32_t, CMVBuffer *, uint64_t) {}
void cmv_commandlist_set_shader_texture(CMVCommandList *, uint32_t, uint32_t, CMVTexture *) {}
void cmv_commandlist_set_sampler(CMVCommandList *, uint32_t, uint32_t, CMVSampler *) {}
void cmv_commandlist_draw(CMVCommandList *, uint32_t, uint32_t, uint32_t, uint32_t) {}
void cmv_commandlist_draw_indexed(CMVCommandList *, uint32_t, uint32_t, bool, CMVBuffer *, uint64_t, uint32_t) {}
void cmv_commandlist_dispatch(CMVCommandList *, uint32_t, uint32_t, uint32_t) {}
void cmv_commandlist_copy_buffer(CMVCommandList *, CMVBuffer *, uint64_t, CMVBuffer *, uint64_t, uint64_t) {}
void cmv_commandlist_fill_buffer(CMVCommandList *, CMVBuffer *, uint64_t, uint64_t, uint8_t) {}
void cmv_commandlist_copy_texture(CMVCommandList *, CMVTexture *, uint32_t, uint32_t, uint32_t, CMVTexture *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t) {}
void cmv_commandlist_copy_buffer_to_texture(CMVCommandList *, CMVBuffer *, uint64_t, uint32_t, CMVTexture *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t) {}
void cmv_commandlist_copy_texture_to_buffer(CMVCommandList *, CMVTexture *, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, CMVBuffer *, uint64_t, uint32_t) {}
void cmv_commandlist_generate_mipmaps(CMVCommandList *, CMVTexture *) {}
uint64_t cmv_commandlist_execute(CMVCommandList *, CMVQueue *) { return 0; }
CMVSwapChain *cmv_swapchain_create(CMVDevice *, uint32_t, void *, uintptr_t, uint32_t, uint32_t, uint32_t, uint32_t, bool) { return nullptr; }
void cmv_swapchain_release(CMVSwapChain *) {}
bool cmv_swapchain_resize(CMVSwapChain *, uint32_t, uint32_t) { return false; }
void cmv_swapchain_set_vsync(CMVSwapChain *, bool) {}
CMVTexture *cmv_swapchain_acquire(CMVSwapChain *) { return nullptr; }
bool cmv_swapchain_present(CMVSwapChain *) { return false; }
uint32_t cmv_swapchain_present_mode(CMVSwapChain *) { return 0; }
uint32_t cmv_swapchain_image_count(CMVSwapChain *) { return 0; }
void cmv_swapchain_last_error(CMVSwapChain *, char *errorOut, uint32_t errorCapacity) { if (errorOut && errorCapacity) errorOut[0] = 0; }

#endif
