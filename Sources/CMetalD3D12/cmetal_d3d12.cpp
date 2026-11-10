// Direct3D 12 backend for the Metal module (ADR-0004): the implementation of the C
// interface in include/cmetal_d3d12.h.
//
// Model. Every handle wraps COM objects plus the bookkeeping the Swift side does not
// see (resource states, descriptor indices, bound state of a command list). Execution
// is synchronous from the Swift side (execute, then wait on the fence), so resource
// state tracking happens at record time: lists are recorded and executed in the same
// order, which keeps the tracked state equal to the GPU state.
//
// Memory. Buffers are committed resources on a CUSTOM heap with write-back system
// memory (the same memory an upload heap uses, minus the upload heap's GENERIC_READ
// restriction), so they are persistently mapped for the CPU, readable by the GPU as
// vertex/index/constant data and valid copy sources and destinations. Textures are
// committed resources on the default heap; uploads and readbacks go through staging
// buffers on a device-owned utility command list.
//
// Descriptors. RTVs, DSVs and texture SRVs live in CPU-only heaps with free lists.
// Each draw copies the bound textures into a shader-visible ring and creates the bound
// samplers in a sampler ring; the rings wrap after waiting for the queues to go idle.
//
// Root signature (see the header): root CBVs b0..b7 for the vertex stage (parameters
// 0..7) and the pixel stage (8..15), an SRV table t0..t7 per stage (16, 17) and a
// sampler table s0..s7 per stage (18, 19). Vertex attributes are declared to the input
// assembler under both `ATTRIBUTEn` and `TEXCOORDn` (n = Metal attribute index), so a
// vertex shader may use either semantic.
//
// Shaders. HLSL is compiled with dxcompiler.dll (+ dxil.dll for signing) when both are
// found: in APPKITWIN_DXC_DIR, next to the executable or on the PATH, or in the newest
// installed Windows 10/11 SDK; otherwise (or with APPKITWIN_NO_DXC=1) with
// d3dcompiler_47 at shader model 5.1.
//
// Diagnostics. APPKITWIN_D3D12_DEBUG=1 (or `debug` to cm_device_create) enables the
// debug layer when the Graphics Tools are installed, prints its messages and the device
// removal reason to stderr, and reports live objects when the device is released.

#include "cmetal_d3d12.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <unknwn.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <dxgidebug.h>
#include <d3dcompiler.h>
#include <dxcapi.h>

#include <algorithm>
#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

// MARK: - Small COM helpers

template <class T> struct Com {
    T *p = nullptr;
    Com() = default;
    Com(const Com &) = delete;
    Com &operator=(const Com &) = delete;
    ~Com() { reset(); }
    void reset() { if (p) { p->Release(); p = nullptr; } }
    T **put() { reset(); return &p; }
    void **putVoid() { reset(); return reinterpret_cast<void **>(&p); }
    T *operator->() const { return p; }
    T *get() const { return p; }
    explicit operator bool() const { return p != nullptr; }
};

bool gVerbose = false;
std::atomic<long> gLiveShaders{0};   // shaders are device-independent blobs

void logf(const char *fmt, ...) {
    if (!gVerbose) return;
    char line[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    fprintf(stderr, "cmetal_d3d12: %s\n", line);
    fflush(stderr);
    OutputDebugStringA("cmetal_d3d12: ");
    OutputDebugStringA(line);
    OutputDebugStringA("\n");
}

void setError(char *out, uint32_t capacity, const char *text) {
    if (!out || capacity == 0) return;
    snprintf(out, capacity, "%s", text ? text : "");
}

void setErrorHR(char *out, uint32_t capacity, const char *what, HRESULT hr) {
    char buf[256];
    snprintf(buf, sizeof buf, "%s failed (HRESULT 0x%08lX)", what, static_cast<unsigned long>(hr));
    setError(out, capacity, buf);
}

// MARK: - Descriptor heaps

struct DescriptorPool {
    Com<ID3D12DescriptorHeap> heap;
    uint32_t size = 0, increment = 0, next = 0;
    D3D12_CPU_DESCRIPTOR_HANDLE cpuStart{};
    D3D12_GPU_DESCRIPTOR_HANDLE gpuStart{};
    std::vector<uint32_t> freeList;

    bool create(ID3D12Device *device, D3D12_DESCRIPTOR_HEAP_TYPE type, uint32_t count, bool shaderVisible) {
        D3D12_DESCRIPTOR_HEAP_DESC d{};
        d.Type = type;
        d.NumDescriptors = count;
        d.Flags = shaderVisible ? D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE : D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
        if (FAILED(device->CreateDescriptorHeap(&d, IID_PPV_ARGS(heap.put())))) return false;
        size = count;
        increment = device->GetDescriptorHandleIncrementSize(type);
        cpuStart = heap->GetCPUDescriptorHandleForHeapStart();
        if (shaderVisible) gpuStart = heap->GetGPUDescriptorHandleForHeapStart();
        return true;
    }
    uint32_t allocate() {
        if (!freeList.empty()) { uint32_t i = freeList.back(); freeList.pop_back(); return i; }
        if (next < size) return next++;
        return UINT32_MAX;
    }
    void release(uint32_t i) { if (i != UINT32_MAX) freeList.push_back(i); }
    D3D12_CPU_DESCRIPTOR_HANDLE cpu(uint32_t i) const { return D3D12_CPU_DESCRIPTOR_HANDLE{cpuStart.ptr + static_cast<SIZE_T>(i) * increment}; }
    D3D12_GPU_DESCRIPTOR_HANDLE gpu(uint32_t i) const { return D3D12_GPU_DESCRIPTOR_HANDLE{gpuStart.ptr + static_cast<UINT64>(i) * increment}; }
};

// MARK: - Shader compiler loading

typedef HRESULT(__stdcall *DxcCreateInstanceFn)(REFCLSID, REFIID, LPVOID *);

struct DxcState {
    std::once_flag once;
    HMODULE dxil = nullptr;
    HMODULE compiler = nullptr;
    DxcCreateInstanceFn createInstance = nullptr;
    bool available = false;
    std::string where;
};
DxcState gDxc;

bool tryLoadDxcFrom(const std::wstring &dir) {
    std::wstring dxilPath = dir.empty() ? L"dxil.dll" : dir + L"\\dxil.dll";
    std::wstring dxcPath = dir.empty() ? L"dxcompiler.dll" : dir + L"\\dxcompiler.dll";
    HMODULE dxil = LoadLibraryW(dxilPath.c_str());
    if (!dxil) return false;
    HMODULE dxc = LoadLibraryW(dxcPath.c_str());
    if (!dxc) { FreeLibrary(dxil); return false; }
    auto fn = reinterpret_cast<DxcCreateInstanceFn>(GetProcAddress(dxc, "DxcCreateInstance"));
    if (!fn) { FreeLibrary(dxc); FreeLibrary(dxil); return false; }
    gDxc.dxil = dxil;
    gDxc.compiler = dxc;
    gDxc.createInstance = fn;
    gDxc.available = true;
    char utf8[MAX_PATH * 2] = {};
    WideCharToMultiByte(CP_UTF8, 0, dir.empty() ? L"(search path)" : dir.c_str(), -1, utf8, sizeof utf8, nullptr, nullptr);
    gDxc.where = utf8;
    return true;
}

// The newest Windows SDK's bin\<version>\x64 that holds both DLLs.
bool tryLoadDxcFromWindowsKits() {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots", 0, KEY_READ | KEY_WOW64_32KEY, &key) != ERROR_SUCCESS) return false;
    wchar_t root[MAX_PATH] = {};
    DWORD size = sizeof root, type = 0;
    bool ok = RegQueryValueExW(key, L"KitsRoot10", nullptr, &type, reinterpret_cast<LPBYTE>(root), &size) == ERROR_SUCCESS && type == REG_SZ;
    std::vector<std::wstring> versions;
    if (ok) {
        for (DWORD i = 0;; i++) {
            wchar_t name[256];
            DWORD nameLen = 256;
            if (RegEnumKeyExW(key, i, name, &nameLen, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
            versions.emplace_back(name);
        }
    }
    RegCloseKey(key);
    if (!ok) return false;
    std::sort(versions.begin(), versions.end(), [](const std::wstring &a, const std::wstring &b) { return a > b; });
    std::wstring base = root;
    if (!base.empty() && base.back() != L'\\') base += L'\\';
    for (const auto &v : versions) {
        if (tryLoadDxcFrom(base + L"bin\\" + v + L"\\x64")) return true;
    }
    return false;
}

void loadDxc() {
    std::call_once(gDxc.once, [] {
        wchar_t env[MAX_PATH] = {};
        // APPKITWIN_NO_DXC=1 forces the d3dcompiler path (to test the fallback).
        if (GetEnvironmentVariableW(L"APPKITWIN_NO_DXC", env, MAX_PATH) > 0 && env[0] == L'1') { gDxc.available = false; return; }
        if (GetEnvironmentVariableW(L"APPKITWIN_DXC_DIR", env, MAX_PATH) > 0 && tryLoadDxcFrom(env)) return;
        if (tryLoadDxcFrom(L"")) return;
        if (tryLoadDxcFromWindowsKits()) return;
        gDxc.available = false;
    });
}

// MARK: - Handles

} // namespace

struct CMQueue;

struct CMDevice {
    Com<IDXGIFactory4> factory;
    Com<IDXGIAdapter1> adapter;
    Com<ID3D12Device> device;
    CMDeviceInfo info{};
    bool debug = false;
    std::mutex mutex;
    Com<ID3D12InfoQueue> infoQueue;               // debug layer messages (verbose mode)

    Com<ID3D12RootSignature> rootSignature;
    DescriptorPool rtvs, dsvs, srvs;              // CPU-only
    DescriptorPool srvRing, samplerRing;          // shader-visible rings (next = head)
    uint32_t nullSrv = UINT32_MAX;

    // Utility list for synchronous uploads/readbacks.
    Com<ID3D12CommandAllocator> utilAllocator;
    Com<ID3D12GraphicsCommandList> utilList;

    std::vector<CMQueue *> queues;                // live queues, for idle waits
    std::vector<CMCommandList *> lists;           // every live list (to forget a released queue)
    std::vector<CMCommandList *> listPool;        // released lists kept for reuse
    std::vector<CMTexture *> texturePool;         // released textures kept for reuse (MTKView recreates drawables per frame)

    std::atomic<long> liveBuffers{0}, liveTextures{0}, livePipelines{0}, liveLists{0}, liveQueues{0}, liveSwapChains{0};
};

struct CMQueue {
    CMDevice *device = nullptr;
    Com<ID3D12CommandQueue> queue;
    Com<ID3D12Fence> fence;
    HANDLE event = nullptr;
    uint64_t lastSignaled = 0;
};

// Objects a command list references stay alive until the list has executed (Metal's
// command buffers retain their resources; the Swift side drops its references as soon
// as the list is recorded): `listRefs` counts referencing lists, `released` says the
// caller is done, and the object is destroyed when both allow it.
struct CMRetained {
    int32_t listRefs = 0;
    bool released = false;
};

struct CMBuffer : CMRetained {
    CMDevice *device = nullptr;
    Com<ID3D12Resource> resource;
    uint64_t length = 0;
    void *mapped = nullptr;
    D3D12_GPU_VIRTUAL_ADDRESS gpu = 0;
    // Buffers rest in COMMON (promotion covers reads; copies transition explicitly and back).
    D3D12_RESOURCE_STATES state = D3D12_RESOURCE_STATE_COMMON;
};

struct CMTexture : CMRetained {
    CMDevice *device = nullptr;
    Com<ID3D12Resource> resource;
    uint32_t width = 0, height = 0, mipLevels = 1;
    DXGI_FORMAT format = DXGI_FORMAT_UNKNOWN;      // the view format the caller asked for
    bool isDepth = false, hasStencil = false, renderTarget = false, shaderRead = false;
    D3D12_RESOURCE_STATES state = D3D12_RESOURCE_STATE_COMMON;
    uint32_t rtv = UINT32_MAX, dsv = UINT32_MAX, srv = UINT32_MAX;
    Com<ID3D12Resource> readback;                  // cached staging buffer for cm_texture_read
    uint64_t readbackSize = 0;
    bool fromSwapChain = false;
};

struct CMShader {
    std::vector<uint8_t> bytes;
};

struct CMPipeline : CMRetained {
    CMDevice *device = nullptr;
    Com<ID3D12PipelineState> state;
    uint32_t strides[16] = {};
};

struct CMCommandList {
    CMDevice *device = nullptr;
    Com<ID3D12CommandAllocator> allocator;
    Com<ID3D12GraphicsCommandList> list;
    bool open = false;
    CMQueue *executedOn = nullptr;
    uint64_t fenceValue = 0;

    // Bound state, flushed at draw time.
    CMPipeline *pipeline = nullptr;
    struct { CMBuffer *buffer; uint64_t offset; uint32_t stride; bool dirty; } vertexBuffers[16] = {};
    struct { CMBuffer *buffer; uint64_t offset; bool dirty; } constantBuffers[2][8] = {};
    CMTexture *textures[2][8] = {};
    bool texturesDirty[2] = {true, true};
    struct { uint32_t filter, addressU, addressV; } samplers[2][8] = {};
    bool samplersDirty[2] = {true, true};
    bool viewportSet = false, scissorSet = false;
    float targetWidth = 0, targetHeight = 0;
    D3D12_PRIMITIVE_TOPOLOGY topology = D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
    std::vector<CMBuffer *> transientBuffers;      // staging buffers owned until the next reset
    std::vector<CMBuffer *> bufferRefs;            // objects retained until the next reset
    std::vector<CMTexture *> textureRefs;
    std::vector<CMPipeline *> pipelineRefs;
};

struct CMSwapChain {
    CMDevice *device = nullptr;
    CMQueue *queue = nullptr;
    Com<IDXGISwapChain3> swapChain;
    HWND hwnd = nullptr;
    DXGI_FORMAT format = DXGI_FORMAT_UNKNOWN;
    uint32_t bufferCount = 0, width = 0, height = 0;
    std::vector<CMTexture *> buffers;
    char lastError[256] = {};
};

namespace {

// MARK: - Formats

bool isDepthFormat(DXGI_FORMAT f) {
    return f == DXGI_FORMAT_D16_UNORM || f == DXGI_FORMAT_D32_FLOAT || f == DXGI_FORMAT_D24_UNORM_S8_UINT || f == DXGI_FORMAT_D32_FLOAT_S8X24_UINT;
}
bool hasStencil(DXGI_FORMAT f) { return f == DXGI_FORMAT_D24_UNORM_S8_UINT || f == DXGI_FORMAT_D32_FLOAT_S8X24_UINT; }

DXGI_FORMAT typelessFor(DXGI_FORMAT f) {
    switch (f) {
    case DXGI_FORMAT_D16_UNORM: return DXGI_FORMAT_R16_TYPELESS;
    case DXGI_FORMAT_D32_FLOAT: return DXGI_FORMAT_R32_TYPELESS;
    case DXGI_FORMAT_D24_UNORM_S8_UINT: return DXGI_FORMAT_R24G8_TYPELESS;
    case DXGI_FORMAT_D32_FLOAT_S8X24_UINT: return DXGI_FORMAT_R32G8X24_TYPELESS;
    default: return f;
    }
}
DXGI_FORMAT srvFormatFor(DXGI_FORMAT f) {
    switch (f) {
    case DXGI_FORMAT_D16_UNORM: return DXGI_FORMAT_R16_UNORM;
    case DXGI_FORMAT_D32_FLOAT: return DXGI_FORMAT_R32_FLOAT;
    case DXGI_FORMAT_D24_UNORM_S8_UINT: return DXGI_FORMAT_R24_UNORM_X8_TYPELESS;
    case DXGI_FORMAT_D32_FLOAT_S8X24_UINT: return DXGI_FORMAT_R32_FLOAT_X8X24_TYPELESS;
    default: return f;
    }
}

// MARK: - Barriers and waits

void transition(ID3D12GraphicsCommandList *list, ID3D12Resource *resource, D3D12_RESOURCE_STATES &state, D3D12_RESOURCE_STATES to) {
    if (state == to) return;
    D3D12_RESOURCE_BARRIER b{};
    b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    b.Transition.pResource = resource;
    b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    b.Transition.StateBefore = state;
    b.Transition.StateAfter = to;
    list->ResourceBarrier(1, &b);
    state = to;
}

// Prints the debug layer's stored messages and a device-removal reason (verbose mode).
void drainMessages(CMDevice *d) {
    if (!gVerbose || !d || !d->device) return;
    if (d->infoQueue) {
        UINT64 count = d->infoQueue->GetNumStoredMessages();
        for (UINT64 i = 0; i < count; i++) {
            SIZE_T length = 0;
            d->infoQueue->GetMessage(i, nullptr, &length);
            std::vector<char> storage(length);
            auto *m = reinterpret_cast<D3D12_MESSAGE *>(storage.data());
            if (length && SUCCEEDED(d->infoQueue->GetMessage(i, m, &length))) logf("[debug layer %d] %s", static_cast<int>(m->Severity), m->pDescription);
        }
        if (count) d->infoQueue->ClearStoredMessages();
    }
    HRESULT removed = d->device->GetDeviceRemovedReason();
    if (removed != S_OK) logf("device removed: 0x%08lX", static_cast<unsigned long>(removed));
}

// Verbose: the device-removed reason at a named step (S_OK prints nothing).
void logDeviceState(CMDevice *d, const char *step) {
    if (!gVerbose || !d || !d->device) return;
    HRESULT removed = d->device->GetDeviceRemovedReason();
    if (removed != S_OK) logf("%s: device removed 0x%08lX", step, static_cast<unsigned long>(removed));
}

void queueWait(CMQueue *q, uint64_t value) {
    if (!q || value == 0) return;
    if (q->fence->GetCompletedValue() < value && SUCCEEDED(q->fence->SetEventOnCompletion(value, q->event))) WaitForSingleObject(q->event, INFINITE);
    drainMessages(q->device);
}

uint64_t queueSignal(CMQueue *q) {
    uint64_t v = ++q->lastSignaled;
    q->queue->Signal(q->fence.get(), v);
    return v;
}

// Waits for every live queue of the device (the descriptor rings wrap on this).
void deviceWaitIdle(CMDevice *d) {
    for (CMQueue *q : d->queues) queueWait(q, q->lastSignaled);
}

uint32_t ringAllocate(CMDevice *d, DescriptorPool &ring, uint32_t count) {
    if (ring.next + count > ring.size) {
        deviceWaitIdle(d);
        ring.next = 0;
    }
    uint32_t i = ring.next;
    ring.next += count;
    return i;
}

// Runs `record` on the device's utility list, executes it on `queue` and waits.
template <class F> bool runUtility(CMDevice *d, CMQueue *queue, F record) {
    if (!queue) return false;
    std::lock_guard<std::mutex> lock(d->mutex);
    if (FAILED(d->utilAllocator->Reset())) return false;
    if (FAILED(d->utilList->Reset(d->utilAllocator.get(), nullptr))) return false;
    record(d->utilList.get());
    if (FAILED(d->utilList->Close())) return false;
    ID3D12CommandList *lists[] = {d->utilList.get()};
    queue->queue->ExecuteCommandLists(1, lists);
    queueWait(queue, queueSignal(queue));
    return true;
}

// MARK: - Root signature

bool createRootSignature(CMDevice *d, char *errorOut, uint32_t errorCapacity) {
    D3D12_DESCRIPTOR_RANGE srvRange{};
    srvRange.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
    srvRange.NumDescriptors = 8;
    srvRange.BaseShaderRegister = 0;
    srvRange.RegisterSpace = 0;
    srvRange.OffsetInDescriptorsFromTableStart = 0;
    D3D12_DESCRIPTOR_RANGE samplerRange = srvRange;
    samplerRange.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SAMPLER;

    D3D12_ROOT_PARAMETER params[20] = {};
    for (int stage = 0; stage < 2; stage++) {
        D3D12_SHADER_VISIBILITY vis = stage == 0 ? D3D12_SHADER_VISIBILITY_VERTEX : D3D12_SHADER_VISIBILITY_PIXEL;
        for (int slot = 0; slot < 8; slot++) {
            D3D12_ROOT_PARAMETER &p = params[stage * 8 + slot];
            p.ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
            p.Descriptor.ShaderRegister = slot;
            p.Descriptor.RegisterSpace = 0;
            p.ShaderVisibility = vis;
        }
        D3D12_ROOT_PARAMETER &t = params[16 + stage];
        t.ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        t.DescriptorTable.NumDescriptorRanges = 1;
        t.DescriptorTable.pDescriptorRanges = &srvRange;
        t.ShaderVisibility = vis;
        D3D12_ROOT_PARAMETER &s = params[18 + stage];
        s.ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        s.DescriptorTable.NumDescriptorRanges = 1;
        s.DescriptorTable.pDescriptorRanges = &samplerRange;
        s.ShaderVisibility = vis;
    }
    D3D12_ROOT_SIGNATURE_DESC desc{};
    desc.NumParameters = 20;
    desc.pParameters = params;
    desc.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;
    Com<ID3DBlob> blob, error;
    HRESULT hr = D3D12SerializeRootSignature(&desc, D3D_ROOT_SIGNATURE_VERSION_1, blob.put(), error.put());
    if (FAILED(hr)) {
        setError(errorOut, errorCapacity, error ? static_cast<const char *>(error->GetBufferPointer()) : "root signature serialization failed");
        return false;
    }
    hr = d->device->CreateRootSignature(0, blob->GetBufferPointer(), blob->GetBufferSize(), IID_PPV_ARGS(d->rootSignature.put()));
    if (FAILED(hr)) { setErrorHR(errorOut, errorCapacity, "CreateRootSignature", hr); return false; }
    return true;
}

// MARK: - Draw-time binding flush

void bindDefaults(CMCommandList *l) {
    l->list->SetGraphicsRootSignature(l->device->rootSignature.get());
    ID3D12DescriptorHeap *heaps[] = {l->device->srvRing.heap.get(), l->device->samplerRing.heap.get()};
    l->list->SetDescriptorHeaps(2, heaps);
}

void resetBindings(CMCommandList *l) {
    l->pipeline = nullptr;
    memset(l->vertexBuffers, 0, sizeof l->vertexBuffers);
    memset(l->constantBuffers, 0, sizeof l->constantBuffers);
    memset(l->textures, 0, sizeof l->textures);
    memset(l->samplers, 0, sizeof l->samplers);
    l->texturesDirty[0] = l->texturesDirty[1] = true;
    l->samplersDirty[0] = l->samplersDirty[1] = true;
    l->viewportSet = l->scissorSet = false;
    l->topology = D3D_PRIMITIVE_TOPOLOGY_UNDEFINED;
}

D3D12_PRIMITIVE_TOPOLOGY topologyFor(uint32_t t) {
    switch (t) {
    case 1: return D3D_PRIMITIVE_TOPOLOGY_POINTLIST;
    case 2: return D3D_PRIMITIVE_TOPOLOGY_LINELIST;
    case 3: return D3D_PRIMITIVE_TOPOLOGY_LINESTRIP;
    case 4: return D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
    case 5: return D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP;
    default: return D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST;
    }
}

bool prepareDraw(CMCommandList *l, uint32_t topology) {
    if (!l->open || !l->pipeline) return false;
    CMDevice *d = l->device;
    ID3D12GraphicsCommandList *list = l->list.get();
    D3D12_PRIMITIVE_TOPOLOGY topo = topologyFor(topology);
    if (topo != l->topology) { list->IASetPrimitiveTopology(topo); l->topology = topo; }
    if (!l->viewportSet) {
        D3D12_VIEWPORT vp{0, 0, l->targetWidth, l->targetHeight, 0, 1};
        list->RSSetViewports(1, &vp);
        l->viewportSet = true;
    }
    if (!l->scissorSet) {
        D3D12_RECT r{0, 0, static_cast<LONG>(l->targetWidth), static_cast<LONG>(l->targetHeight)};
        list->RSSetScissorRects(1, &r);
        l->scissorSet = true;
    }
    for (uint32_t slot = 0; slot < 16; slot++) {
        auto &vb = l->vertexBuffers[slot];
        if (!vb.dirty) continue;
        vb.dirty = false;
        if (!vb.buffer) { list->IASetVertexBuffers(slot, 1, nullptr); continue; }
        D3D12_VERTEX_BUFFER_VIEW view{};
        view.BufferLocation = vb.buffer->gpu + vb.offset;
        view.SizeInBytes = vb.offset < vb.buffer->length ? static_cast<UINT>(vb.buffer->length - vb.offset) : 0;
        view.StrideInBytes = vb.stride ? vb.stride : l->pipeline->strides[slot];
        list->IASetVertexBuffers(slot, 1, &view);
    }
    for (int stage = 0; stage < 2; stage++) {
        for (uint32_t slot = 0; slot < 8; slot++) {
            auto &cb = l->constantBuffers[stage][slot];
            if (!cb.dirty) continue;
            cb.dirty = false;
            if (cb.buffer) list->SetGraphicsRootConstantBufferView(stage * 8 + slot, cb.buffer->gpu + cb.offset);
        }
        if (l->texturesDirty[stage]) {
            l->texturesDirty[stage] = false;
            uint32_t base = ringAllocate(d, d->srvRing, 8);
            for (uint32_t slot = 0; slot < 8; slot++) {
                CMTexture *t = l->textures[stage][slot];
                uint32_t src = t && t->srv != UINT32_MAX ? t->srv : d->nullSrv;
                d->device->CopyDescriptorsSimple(1, d->srvRing.cpu(base + slot), d->srvs.cpu(src), D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
            }
            list->SetGraphicsRootDescriptorTable(16 + stage, d->srvRing.gpu(base));
        }
        if (l->samplersDirty[stage]) {
            l->samplersDirty[stage] = false;
            uint32_t base = ringAllocate(d, d->samplerRing, 8);
            for (uint32_t slot = 0; slot < 8; slot++) {
                auto &s = l->samplers[stage][slot];
                D3D12_SAMPLER_DESC sd{};
                sd.Filter = static_cast<D3D12_FILTER>(s.filter);
                auto addr = [](uint32_t a) { return a >= 1 && a <= 5 ? static_cast<D3D12_TEXTURE_ADDRESS_MODE>(a) : D3D12_TEXTURE_ADDRESS_MODE_CLAMP; };
                sd.AddressU = addr(s.addressU);
                sd.AddressV = addr(s.addressV);
                sd.AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
                sd.MaxAnisotropy = (s.filter & D3D12_ANISOTROPIC_FILTERING_BIT) ? 16 : 1;
                sd.ComparisonFunc = D3D12_COMPARISON_FUNC_NEVER;
                sd.MaxLOD = D3D12_FLOAT32_MAX;
                d->device->CreateSampler(&sd, d->samplerRing.cpu(base + slot));
            }
            list->SetGraphicsRootDescriptorTable(18 + stage, d->samplerRing.gpu(base));
        }
    }
    return true;
}

// MARK: - Textures

bool createTextureViews(CMDevice *d, CMTexture *t, bool renderTarget, bool shaderRead) {
    if (renderTarget) {
        if (t->isDepth) {
            t->dsv = d->dsvs.allocate();
            if (t->dsv == UINT32_MAX) return false;
            D3D12_DEPTH_STENCIL_VIEW_DESC dv{};
            dv.Format = t->format;
            dv.ViewDimension = D3D12_DSV_DIMENSION_TEXTURE2D;
            d->device->CreateDepthStencilView(t->resource.get(), &dv, d->dsvs.cpu(t->dsv));
        } else {
            t->rtv = d->rtvs.allocate();
            if (t->rtv == UINT32_MAX) return false;
            D3D12_RENDER_TARGET_VIEW_DESC rv{};
            rv.Format = t->format;
            rv.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
            d->device->CreateRenderTargetView(t->resource.get(), &rv, d->rtvs.cpu(t->rtv));
        }
    }
    if (shaderRead) {
        t->srv = d->srvs.allocate();
        if (t->srv == UINT32_MAX) return false;
        D3D12_SHADER_RESOURCE_VIEW_DESC sv{};
        sv.Format = srvFormatFor(t->format);
        sv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
        sv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
        sv.Texture2D.MipLevels = t->mipLevels;
        d->device->CreateShaderResourceView(t->resource.get(), &sv, d->srvs.cpu(t->srv));
    }
    return true;
}

void destroyTexture(CMTexture *t) {
    CMDevice *d = t->device;
    d->rtvs.release(t->rtv);
    d->dsvs.release(t->dsv);
    d->srvs.release(t->srv);
    d->liveTextures--;
    delete t;
}

// A released, unreferenced texture goes back to a small pool (its descriptors and
// readback buffer with it) so a view that recreates its drawable per frame does not
// allocate per frame.
void recycleTexture(CMTexture *t) {
    CMDevice *d = t->device;
    if (t->fromSwapChain || d->texturePool.size() >= 6) { destroyTexture(t); return; }
    d->liveTextures--;
    d->texturePool.push_back(t);
}

void destroyBuffer(CMBuffer *b) {
    if (b->mapped) b->resource->Unmap(0, nullptr);
    b->device->liveBuffers--;
    delete b;
}

void destroyPipeline(CMPipeline *p) {
    p->device->livePipelines--;
    delete p;
}

template <class T> void retain(std::vector<T *> &refs, T *object) {
    if (!object || (!refs.empty() && refs.back() == object)) return;
    object->listRefs++;
    refs.push_back(object);
}

// Drops the list's references (after its fence) and destroys what the caller released.
void releaseListRefs(CMCommandList *l) {
    for (CMBuffer *b : l->bufferRefs) if (--b->listRefs == 0 && b->released) destroyBuffer(b);
    for (CMTexture *t : l->textureRefs) if (--t->listRefs == 0 && t->released) recycleTexture(t);
    for (CMPipeline *p : l->pipelineRefs) if (--p->listRefs == 0 && p->released) destroyPipeline(p);
    l->bufferRefs.clear();
    l->textureRefs.clear();
    l->pipelineRefs.clear();
}

// MARK: - Shader compilation

std::wstring widen(const char *s) {
    if (!s) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    std::wstring out(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, &out[0], n);
    return out;
}

CMShader *compileWithDxc(const char *source, uint32_t length, const char *entry, const char *profile, char *errorOut, uint32_t errorCapacity) {
    Com<IDxcUtils> utils;
    Com<IDxcCompiler3> compiler;
    HRESULT hr = gDxc.createInstance(CLSID_DxcUtils, IID_PPV_ARGS(utils.put()));
    if (SUCCEEDED(hr)) hr = gDxc.createInstance(CLSID_DxcCompiler, IID_PPV_ARGS(compiler.put()));
    if (FAILED(hr)) { setErrorHR(errorOut, errorCapacity, "DxcCreateInstance", hr); return nullptr; }
    DxcBuffer buffer{source, length, DXC_CP_UTF8};
    std::wstring wEntry = widen(entry), wProfile = widen(profile);
    LPCWSTR args[] = {L"-E", wEntry.c_str(), L"-T", wProfile.c_str(), L"-Qstrip_reflect"};
    Com<IDxcResult> result;
    hr = compiler->Compile(&buffer, args, static_cast<UINT32>(sizeof args / sizeof args[0]), nullptr, IID_PPV_ARGS(result.put()));
    if (FAILED(hr) || !result) { setErrorHR(errorOut, errorCapacity, "IDxcCompiler3::Compile", hr); return nullptr; }
    HRESULT status = S_OK;
    result->GetStatus(&status);
    Com<IDxcBlobUtf8> errors;
    result->GetOutput(DXC_OUT_ERRORS, IID_PPV_ARGS(errors.put()), nullptr);
    if (FAILED(status)) {
        setError(errorOut, errorCapacity, errors && errors->GetStringLength() ? errors->GetStringPointer() : "HLSL compilation failed");
        return nullptr;
    }
    Com<IDxcBlob> object;
    result->GetOutput(DXC_OUT_OBJECT, IID_PPV_ARGS(object.put()), nullptr);
    if (!object || object->GetBufferSize() == 0) { setError(errorOut, errorCapacity, "dxc produced no object"); return nullptr; }
    CMShader *s = new CMShader;
    s->bytes.assign(static_cast<const uint8_t *>(object->GetBufferPointer()), static_cast<const uint8_t *>(object->GetBufferPointer()) + object->GetBufferSize());
    return s;
}

CMShader *compileWithFxc(const char *source, uint32_t length, const char *entry, const char *profile, char *errorOut, uint32_t errorCapacity) {
    // Shader model 6.x profiles become 5.1 for d3dcompiler.
    std::string p = profile ? profile : "";
    size_t us = p.find('_');
    if (us != std::string::npos && us + 1 < p.size() && p[us + 1] >= '6') p = p.substr(0, us) + "_5_1";
    Com<ID3DBlob> blob, errors;
    HRESULT hr = D3DCompile(source, length, "shader.hlsl", nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry, p.c_str(), D3DCOMPILE_ENABLE_STRICTNESS, 0, blob.put(), errors.put());
    if (FAILED(hr) || !blob) {
        if (errors && errors->GetBufferSize()) setError(errorOut, errorCapacity, static_cast<const char *>(errors->GetBufferPointer()));
        else setErrorHR(errorOut, errorCapacity, "D3DCompile", hr);
        return nullptr;
    }
    CMShader *s = new CMShader;
    s->bytes.assign(static_cast<const uint8_t *>(blob->GetBufferPointer()), static_cast<const uint8_t *>(blob->GetBufferPointer()) + blob->GetBufferSize());
    return s;
}

// MARK: - Swap chain buffers

bool acquireSwapChainBuffers(CMSwapChain *sc, char *errorOut, uint32_t errorCapacity) {
    CMDevice *d = sc->device;
    for (uint32_t i = 0; i < sc->bufferCount; i++) {
        CMTexture *t = new CMTexture;
        t->device = d;
        HRESULT hr = sc->swapChain->GetBuffer(i, IID_PPV_ARGS(t->resource.put()));
        if (FAILED(hr)) { delete t; setErrorHR(errorOut, errorCapacity, "IDXGISwapChain::GetBuffer", hr); return false; }
        t->width = sc->width;
        t->height = sc->height;
        t->mipLevels = 1;
        t->format = sc->format;
        t->state = D3D12_RESOURCE_STATE_PRESENT;
        t->fromSwapChain = true;
        if (!createTextureViews(d, t, true, true)) { delete t; setError(errorOut, errorCapacity, "descriptor heaps exhausted"); return false; }
        d->liveTextures++;
        sc->buffers.push_back(t);
    }
    return true;
}

void releaseSwapChainBuffers(CMSwapChain *sc) {
    for (CMTexture *t : sc->buffers) destroyTexture(t);
    sc->buffers.clear();
}

// MARK: - Device teardown

// Waits for the list's last execution, then lets go of everything it referenced.
void finishList(CMCommandList *l) {
    if (l->executedOn) { queueWait(l->executedOn, l->fenceValue); l->executedOn = nullptr; l->fenceValue = 0; }
    for (CMBuffer *b : l->transientBuffers) cm_buffer_release(b);
    l->transientBuffers.clear();
    releaseListRefs(l);
}

void destroyCommandList(CMCommandList *l) {
    finishList(l);
    CMDevice *d = l->device;
    d->lists.erase(std::remove(d->lists.begin(), d->lists.end(), l), d->lists.end());
    d->liveLists--;
    delete l;
}

void reportLiveObjects(CMDevice *d, ULONG finalRefCount) {
    fprintf(stderr, "cmetal_d3d12: device released; ID3D12Device final reference count %lu (0 = no leaked children); live handles: buffers %ld, textures %ld, shaders %ld, pipelines %ld, command lists %ld, queues %ld, swap chains %ld\n",
            static_cast<unsigned long>(finalRefCount), d->liveBuffers.load(), d->liveTextures.load(), gLiveShaders.load(), d->livePipelines.load(), d->liveLists.load(), d->liveQueues.load(), d->liveSwapChains.load());
    fflush(stderr);
    // DXGI live-object report (goes to the debugger output; needs dxgidebug.dll).
    HMODULE dxgiDebug = LoadLibraryW(L"dxgidebug.dll");
    if (!dxgiDebug) return;
    typedef HRESULT(WINAPI * GetDebugInterfaceFn)(UINT, REFIID, void **);
    auto getDebug = reinterpret_cast<GetDebugInterfaceFn>(GetProcAddress(dxgiDebug, "DXGIGetDebugInterface1"));
    if (!getDebug) return;
    Com<IDXGIDebug1> debug;
    if (SUCCEEDED(getDebug(0, IID_PPV_ARGS(debug.put())))) {
        const GUID allObjects = {0xe48ae283, 0xda80, 0x490b, {0x87, 0xe6, 0x43, 0xe9, 0xa9, 0xcf, 0xda, 0x8}};   // DXGI_DEBUG_ALL
        debug->ReportLiveObjects(allObjects, static_cast<DXGI_DEBUG_RLO_FLAGS>(DXGI_DEBUG_RLO_DETAIL | DXGI_DEBUG_RLO_IGNORE_INTERNAL));
    }
}

} // namespace

extern "C" {

// MARK: - Device

CMDevice *cm_device_create(bool debug) {
    char env[8] = {};
    gVerbose = debug || (GetEnvironmentVariableA("APPKITWIN_D3D12_DEBUG", env, sizeof env) > 0 && env[0] == '1')
        || (GetEnvironmentVariableA("APPKITWIN_D3D12_LOG", env, sizeof env) > 0 && env[0] == '1');   // logging without the debug layer
    CMDevice *d = new CMDevice;
    d->debug = debug;
    if (debug) {
        Com<ID3D12Debug> dbg;
        if (SUCCEEDED(D3D12GetDebugInterface(IID_PPV_ARGS(dbg.put())))) { dbg->EnableDebugLayer(); logf("D3D12 debug layer enabled"); }
        else logf("D3D12 debug layer unavailable (install the Graphics Tools optional feature); continuing without it");
    }
    HRESULT hr = CreateDXGIFactory2(debug ? DXGI_CREATE_FACTORY_DEBUG : 0, IID_PPV_ARGS(d->factory.put()));
    if (FAILED(hr) && debug) hr = CreateDXGIFactory2(0, IID_PPV_ARGS(d->factory.put()));
    if (FAILED(hr)) { logf("CreateDXGIFactory2 failed 0x%08lX", hr); delete d; return nullptr; }

    // Hardware adapters by performance preference, then WARP.
    Com<IDXGIFactory6> factory6;
    d->factory->QueryInterface(IID_PPV_ARGS(factory6.put()));
    for (UINT i = 0;; i++) {
        Com<IDXGIAdapter1> adapter;
        HRESULT e = factory6 ? factory6->EnumAdapterByGpuPreference(i, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(adapter.put()))
                             : d->factory->EnumAdapters1(i, adapter.put());
        if (FAILED(e)) break;
        DXGI_ADAPTER_DESC1 desc{};
        adapter->GetDesc1(&desc);
        if (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;
        if (SUCCEEDED(D3D12CreateDevice(adapter.get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(d->device.put())))) {
            d->adapter.p = adapter.p; adapter.p = nullptr;
            break;
        }
    }
    if (!d->device) {
        Com<IDXGIAdapter1> warp;
        if (SUCCEEDED(d->factory->EnumWarpAdapter(IID_PPV_ARGS(warp.put()))) && SUCCEEDED(D3D12CreateDevice(warp.get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(d->device.put())))) {
            d->adapter.p = warp.p; warp.p = nullptr;
            logf("no hardware D3D12 adapter; using WARP");
        }
    }
    if (!d->device) { logf("no D3D12 device available"); delete d; return nullptr; }

    DXGI_ADAPTER_DESC1 desc{};
    d->adapter->GetDesc1(&desc);
    WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, d->info.name, sizeof d->info.name - 1, nullptr, nullptr);
    d->info.dedicatedVideoMemory = desc.DedicatedVideoMemory;
    d->info.isSoftware = (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) != 0;
    d->info.isLowPower = !d->info.isSoftware && desc.DedicatedVideoMemory == 0;

    bool ok = d->rtvs.create(d->device.get(), D3D12_DESCRIPTOR_HEAP_TYPE_RTV, 512, false)
           && d->dsvs.create(d->device.get(), D3D12_DESCRIPTOR_HEAP_TYPE_DSV, 128, false)
           && d->srvs.create(d->device.get(), D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 8192, false)
           && d->srvRing.create(d->device.get(), D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 65536, true)
           && d->samplerRing.create(d->device.get(), D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER, 2048, true);
    char error[512] = {};
    ok = ok && createRootSignature(d, error, sizeof error);
    ok = ok && SUCCEEDED(d->device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(d->utilAllocator.put())));
    ok = ok && SUCCEEDED(d->device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, d->utilAllocator.get(), nullptr, IID_PPV_ARGS(d->utilList.put())));
    if (ok) d->utilList->Close();
    if (ok) {
        d->nullSrv = d->srvs.allocate();
        D3D12_SHADER_RESOURCE_VIEW_DESC nv{};
        nv.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        nv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
        nv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
        nv.Texture2D.MipLevels = 1;
        d->device->CreateShaderResourceView(nullptr, &nv, d->srvs.cpu(d->nullSrv));
    }
    if (!ok) { logf("device setup failed: %s", error); cm_device_release(d); return nullptr; }
    if (debug && SUCCEEDED(d->device->QueryInterface(IID_PPV_ARGS(d->infoQueue.put())))) {
        // Render targets carry no optimized clear value (Metal clears to any colour), so
        // the per-clear performance warning is expected noise.
        D3D12_MESSAGE_ID denied[] = {D3D12_MESSAGE_ID_CLEARRENDERTARGETVIEW_MISMATCHINGCLEARVALUE, D3D12_MESSAGE_ID_CLEARDEPTHSTENCILVIEW_MISMATCHINGCLEARVALUE};
        D3D12_INFO_QUEUE_FILTER filter{};
        filter.DenyList.NumIDs = 2;
        filter.DenyList.pIDList = denied;
        d->infoQueue->AddStorageFilterEntries(&filter);
    }
    loadDxc();
    logf("device '%s' (%llu MB dedicated), shaders via %s", d->info.name, static_cast<unsigned long long>(desc.DedicatedVideoMemory >> 20), gDxc.available ? gDxc.where.c_str() : "d3dcompiler (shader model 5.1)");
    return d;
}

void cm_device_release(CMDevice *d) {
    if (!d) return;
    for (CMCommandList *l : d->listPool) destroyCommandList(l);
    d->listPool.clear();
    for (CMTexture *t : d->texturePool) { d->liveTextures++; destroyTexture(t); }
    d->texturePool.clear();
    drainMessages(d);
    d->infoQueue.reset();
    d->utilList.reset();
    d->utilAllocator.reset();
    d->rootSignature.reset();
    d->rtvs.heap.reset(); d->dsvs.heap.reset(); d->srvs.heap.reset(); d->srvRing.heap.reset(); d->samplerRing.heap.reset();
    ID3D12Device *device = d->device.p;
    d->device.p = nullptr;
    ULONG rc = device ? device->Release() : 0;
    if (gVerbose) reportLiveObjects(d, rc);
    d->adapter.reset();
    d->factory.reset();
    delete d;
}

void cm_device_info(CMDevice *d, CMDeviceInfo *info) {
    if (!info) return;
    if (d) *info = d->info; else memset(info, 0, sizeof *info);
}

bool cm_device_lost(CMDevice *d) { return !d || !d->device || d->device->GetDeviceRemovedReason() != S_OK; }

// MARK: - Queue

CMQueue *cm_queue_create(CMDevice *d) {
    if (!d) return nullptr;
    CMQueue *q = new CMQueue;
    q->device = d;
    D3D12_COMMAND_QUEUE_DESC desc{};
    desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    if (FAILED(d->device->CreateCommandQueue(&desc, IID_PPV_ARGS(q->queue.put())))
        || FAILED(d->device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(q->fence.put())))) { delete q; return nullptr; }
    q->event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!q->event) { delete q; return nullptr; }
    std::lock_guard<std::mutex> lock(d->mutex);
    d->queues.push_back(q);
    d->liveQueues++;
    return q;
}

void cm_queue_release(CMQueue *q) {
    if (!q) return;
    queueWait(q, q->lastSignaled);
    CMDevice *d = q->device;
    {
        std::lock_guard<std::mutex> lock(d->mutex);
        d->queues.erase(std::remove(d->queues.begin(), d->queues.end(), q), d->queues.end());
        // Lists that last ran on this queue are complete now; forget the queue.
        for (CMCommandList *l : d->lists) if (l->executedOn == q) { l->executedOn = nullptr; l->fenceValue = 0; }
    }
    CloseHandle(q->event);
    d->liveQueues--;
    delete q;
}

uint64_t cm_queue_signal(CMQueue *q) { return q ? queueSignal(q) : 0; }
bool cm_queue_fence_reached(CMQueue *q, uint64_t value) { return !q || q->fence->GetCompletedValue() >= value; }
void cm_queue_wait(CMQueue *q, uint64_t value) { queueWait(q, value); }

// MARK: - Buffers

CMBuffer *cm_buffer_create(CMDevice *d, uint64_t length) {
    if (!d || length == 0) return nullptr;
    CMBuffer *b = new CMBuffer;
    b->device = d;
    b->length = length;
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_CUSTOM;
    heap.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_WRITE_BACK;
    heap.MemoryPoolPreference = D3D12_MEMORY_POOL_L0;
    D3D12_RESOURCE_DESC desc{};
    desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    desc.Width = (length + 255) & ~static_cast<uint64_t>(255);   // constant-buffer granularity
    desc.Height = 1;
    desc.DepthOrArraySize = 1;
    desc.MipLevels = 1;
    desc.Format = DXGI_FORMAT_UNKNOWN;
    desc.SampleDesc.Count = 1;
    desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    HRESULT hr = d->device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &desc, D3D12_RESOURCE_STATE_COMMON, nullptr, IID_PPV_ARGS(b->resource.put()));
    if (FAILED(hr)) { logf("buffer creation failed 0x%08lX", hr); drainMessages(d); delete b; return nullptr; }
    if (FAILED(b->resource->Map(0, nullptr, &b->mapped))) { delete b; return nullptr; }
    b->gpu = b->resource->GetGPUVirtualAddress();
    d->liveBuffers++;
    return b;
}

void cm_buffer_release(CMBuffer *b) {
    if (!b || b->released) return;
    b->released = true;
    if (b->listRefs == 0) destroyBuffer(b);
}

void *cm_buffer_map(CMBuffer *b) { return b ? b->mapped : nullptr; }
uint64_t cm_buffer_gpu_address(CMBuffer *b) { return b ? b->gpu : 0; }

// MARK: - Textures

CMTexture *cm_texture_create(CMDevice *d, uint32_t width, uint32_t height, uint32_t mipLevels, uint32_t dxgiFormat, bool renderTarget, bool shaderRead) {
    if (!d || width == 0 || height == 0 || dxgiFormat == 0) return nullptr;
    for (size_t i = 0; i < d->texturePool.size(); i++) {
        CMTexture *p = d->texturePool[i];
        if (p->width == width && p->height == height && p->mipLevels == std::max(1u, mipLevels) && p->format == static_cast<DXGI_FORMAT>(dxgiFormat)
            && p->renderTarget == renderTarget && p->shaderRead == shaderRead) {
            d->texturePool.erase(d->texturePool.begin() + static_cast<ptrdiff_t>(i));
            p->released = false;
            d->liveTextures++;
            return p;
        }
    }
    CMTexture *t = new CMTexture;
    t->device = d;
    t->width = width;
    t->height = height;
    t->mipLevels = std::max(1u, mipLevels);
    t->format = static_cast<DXGI_FORMAT>(dxgiFormat);
    t->renderTarget = renderTarget;
    t->shaderRead = shaderRead;
    t->isDepth = isDepthFormat(t->format);
    t->hasStencil = hasStencil(t->format);
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC desc{};
    desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    desc.Width = width;
    desc.Height = height;
    desc.DepthOrArraySize = 1;
    desc.MipLevels = static_cast<UINT16>(t->mipLevels);
    desc.Format = t->isDepth && shaderRead ? typelessFor(t->format) : t->format;
    desc.SampleDesc.Count = 1;
    desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
    if (renderTarget) desc.Flags |= t->isDepth ? D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL : D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    if (t->isDepth && !shaderRead) desc.Flags |= D3D12_RESOURCE_FLAG_DENY_SHADER_RESOURCE;
    HRESULT hr = d->device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &desc, D3D12_RESOURCE_STATE_COMMON, nullptr, IID_PPV_ARGS(t->resource.put()));
    if (FAILED(hr)) { logf("texture creation failed 0x%08lX (format %u, %ux%u)", hr, dxgiFormat, width, height); drainMessages(d); delete t; return nullptr; }
    d->liveTextures++;
    if (!createTextureViews(d, t, renderTarget, shaderRead)) { logf("descriptor heaps exhausted"); destroyTexture(t); return nullptr; }
    return t;
}

void cm_texture_release(CMTexture *t) {
    if (!t || t->fromSwapChain || t->released) return;   // swap-chain buffers belong to the swap chain
    t->released = true;
    if (t->listRefs == 0) recycleTexture(t);
}

bool cm_texture_upload(CMDevice *d, CMQueue *queue, CMTexture *t, uint32_t level, const void *rows, uint32_t bytesPerRow, uint32_t height) {
    if (!d || !queue || !t || !rows || level >= t->mipLevels) return false;
    D3D12_RESOURCE_DESC desc = t->resource->GetDesc();
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    UINT numRows = 0;
    UINT64 rowSize = 0, total = 0;
    d->device->GetCopyableFootprints(&desc, level, 1, 0, &footprint, &numRows, &rowSize, &total);
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_UPLOAD;
    D3D12_RESOURCE_DESC bd{};
    bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    bd.Width = total;
    bd.Height = 1;
    bd.DepthOrArraySize = 1;
    bd.MipLevels = 1;
    bd.SampleDesc.Count = 1;
    bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    Com<ID3D12Resource> staging;
    if (FAILED(d->device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &bd, D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, IID_PPV_ARGS(staging.put())))) return false;
    void *mapped = nullptr;
    if (FAILED(staging->Map(0, nullptr, &mapped))) return false;
    uint8_t *dst = static_cast<uint8_t *>(mapped) + footprint.Offset;
    const uint8_t *src = static_cast<const uint8_t *>(rows);
    UINT copyRows = std::min<UINT>(numRows, height);
    size_t copyBytes = std::min<size_t>(bytesPerRow, static_cast<size_t>(rowSize));
    for (UINT r = 0; r < copyRows; r++) memcpy(dst + static_cast<size_t>(r) * footprint.Footprint.RowPitch, src + static_cast<size_t>(r) * bytesPerRow, copyBytes);
    staging->Unmap(0, nullptr);
    return runUtility(d, queue, [&](ID3D12GraphicsCommandList *list) {
        transition(list, t->resource.get(), t->state, D3D12_RESOURCE_STATE_COPY_DEST);
        D3D12_TEXTURE_COPY_LOCATION dstLoc{};
        dstLoc.pResource = t->resource.get();
        dstLoc.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        dstLoc.SubresourceIndex = level;
        D3D12_TEXTURE_COPY_LOCATION srcLoc{};
        srcLoc.pResource = staging.get();
        srcLoc.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        srcLoc.PlacedFootprint = footprint;
        list->CopyTextureRegion(&dstLoc, 0, 0, 0, &srcLoc, nullptr);
    });
}

bool cm_texture_read(CMDevice *d, CMQueue *queue, CMTexture *t, void *out, uint32_t bytesPerRow, uint32_t height) {
    if (!d || !queue || !t || !out) return false;
    D3D12_RESOURCE_DESC desc = t->resource->GetDesc();
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    UINT numRows = 0;
    UINT64 rowSize = 0, total = 0;
    d->device->GetCopyableFootprints(&desc, 0, 1, 0, &footprint, &numRows, &rowSize, &total);
    if (!t->readback || t->readbackSize < total) {
        t->readback.reset();
        D3D12_HEAP_PROPERTIES heap{};
        heap.Type = D3D12_HEAP_TYPE_READBACK;
        D3D12_RESOURCE_DESC bd{};
        bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        bd.Width = total;
        bd.Height = 1;
        bd.DepthOrArraySize = 1;
        bd.MipLevels = 1;
        bd.SampleDesc.Count = 1;
        bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        HRESULT hr = d->device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &bd, D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(t->readback.put()));
        if (FAILED(hr)) { logf("readback buffer creation failed 0x%08lX (%ux%u)", hr, t->width, t->height); drainMessages(d); return false; }
        t->readbackSize = total;
    }
    bool ok = runUtility(d, queue, [&](ID3D12GraphicsCommandList *list) {
        transition(list, t->resource.get(), t->state, D3D12_RESOURCE_STATE_COPY_SOURCE);
        D3D12_TEXTURE_COPY_LOCATION srcLoc{};
        srcLoc.pResource = t->resource.get();
        srcLoc.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        srcLoc.SubresourceIndex = 0;
        D3D12_TEXTURE_COPY_LOCATION dstLoc{};
        dstLoc.pResource = t->readback.get();
        dstLoc.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        dstLoc.PlacedFootprint = footprint;
        list->CopyTextureRegion(&dstLoc, 0, 0, 0, &srcLoc, nullptr);
    });
    if (!ok) { logf("texture readback: utility list failed (%ux%u, swap chain %d)", t->width, t->height, t->fromSwapChain ? 1 : 0); drainMessages(d); return false; }
    void *mapped = nullptr;
    D3D12_RANGE readRange{0, static_cast<SIZE_T>(total)};
    HRESULT mapResult = t->readback->Map(0, &readRange, &mapped);
    if (FAILED(mapResult)) { logf("texture readback: Map failed 0x%08lX", mapResult); drainMessages(d); return false; }
    const uint8_t *src = static_cast<const uint8_t *>(mapped) + footprint.Offset;
    uint8_t *dst = static_cast<uint8_t *>(out);
    UINT copyRows = std::min<UINT>(numRows, height);
    size_t copyBytes = std::min<size_t>(bytesPerRow, static_cast<size_t>(rowSize));
    for (UINT r = 0; r < copyRows; r++) memcpy(dst + static_cast<size_t>(r) * bytesPerRow, src + static_cast<size_t>(r) * footprint.Footprint.RowPitch, copyBytes);
    D3D12_RANGE noWrite{0, 0};
    t->readback->Unmap(0, &noWrite);
    return true;
}

// MARK: - Shaders

CMShader *cm_shader_compile_hlsl(const char *source, uint32_t sourceLength, const char *entryPoint, const char *profile, char *errorOut, uint32_t errorCapacity) {
    setError(errorOut, errorCapacity, "");
    if (!source || !entryPoint || !profile) { setError(errorOut, errorCapacity, "missing source, entry point or profile"); return nullptr; }
    loadDxc();
    CMShader *s = nullptr;
    std::string p = profile;
    size_t us = p.find('_');
    bool wantsSM6 = us != std::string::npos && us + 1 < p.size() && p[us + 1] >= '6';
    if (gDxc.available && wantsSM6) s = compileWithDxc(source, sourceLength, entryPoint, profile, errorOut, errorCapacity);
    else s = compileWithFxc(source, sourceLength, entryPoint, profile, errorOut, errorCapacity);
    if (s) gLiveShaders++;
    return s;
}

CMShader *cm_shader_from_blob(const void *bytes, uint32_t length) {
    if (!bytes || length == 0) return nullptr;
    CMShader *s = new CMShader;
    s->bytes.assign(static_cast<const uint8_t *>(bytes), static_cast<const uint8_t *>(bytes) + length);
    gLiveShaders++;
    return s;
}

void cm_shader_release(CMShader *s) {
    if (!s) return;
    gLiveShaders--;
    delete s;
}

// MARK: - Pipelines

CMPipeline *cm_pipeline_create(CMDevice *d, const CMPipelineDesc *desc, char *errorOut, uint32_t errorCapacity) {
    setError(errorOut, errorCapacity, "");
    if (!d || !desc) { setError(errorOut, errorCapacity, "no device or descriptor"); return nullptr; }
    if (!desc->vertex || desc->vertex->bytes.empty()) { setError(errorOut, errorCapacity, "pipeline needs a vertex shader"); return nullptr; }
    for (uint32_t i = 0; i < desc->attributeCount; i++) {
        if (desc->attributes[i].bufferIndex >= 16) { setError(errorOut, errorCapacity, "vertex attribute buffer index out of range (0..15)"); return nullptr; }
        if (desc->attributes[i].dxgiFormat == 0) { setError(errorOut, errorCapacity, "vertex attribute has an unsupported format"); return nullptr; }
    }

    D3D12_GRAPHICS_PIPELINE_STATE_DESC p{};
    p.pRootSignature = d->rootSignature.get();
    p.VS = {desc->vertex->bytes.data(), desc->vertex->bytes.size()};
    if (desc->fragment && !desc->fragment->bytes.empty()) p.PS = {desc->fragment->bytes.data(), desc->fragment->bytes.size()};
    p.BlendState.AlphaToCoverageEnable = FALSE;
    p.BlendState.IndependentBlendEnable = TRUE;
    uint32_t colorCount = 0;
    for (uint32_t i = 0; i < 8; i++) {
        const CMBlend &b = desc->blends[i];
        D3D12_RENDER_TARGET_BLEND_DESC &rt = p.BlendState.RenderTarget[i];
        rt.BlendEnable = b.enabled ? TRUE : FALSE;
        rt.LogicOpEnable = FALSE;
        rt.SrcBlend = b.srcRGB ? static_cast<D3D12_BLEND>(b.srcRGB) : D3D12_BLEND_ONE;
        rt.DestBlend = b.dstRGB ? static_cast<D3D12_BLEND>(b.dstRGB) : D3D12_BLEND_ZERO;
        rt.BlendOp = b.opRGB ? static_cast<D3D12_BLEND_OP>(b.opRGB) : D3D12_BLEND_OP_ADD;
        rt.SrcBlendAlpha = b.srcAlpha ? static_cast<D3D12_BLEND>(b.srcAlpha) : D3D12_BLEND_ONE;
        rt.DestBlendAlpha = b.dstAlpha ? static_cast<D3D12_BLEND>(b.dstAlpha) : D3D12_BLEND_ZERO;
        rt.BlendOpAlpha = b.opAlpha ? static_cast<D3D12_BLEND_OP>(b.opAlpha) : D3D12_BLEND_OP_ADD;
        rt.LogicOp = D3D12_LOGIC_OP_NOOP;
        rt.RenderTargetWriteMask = desc->colorFormats[i] ? (b.writeMask & 0xF) : D3D12_COLOR_WRITE_ENABLE_ALL;
        if (desc->colorFormats[i]) {
            p.RTVFormats[i] = static_cast<DXGI_FORMAT>(desc->colorFormats[i]);
            colorCount = i + 1;
        }
    }
    p.NumRenderTargets = colorCount;
    p.SampleMask = UINT_MAX;
    p.RasterizerState.FillMode = desc->wireframe ? D3D12_FILL_MODE_WIREFRAME : D3D12_FILL_MODE_SOLID;
    p.RasterizerState.CullMode = desc->cullMode >= 1 && desc->cullMode <= 3 ? static_cast<D3D12_CULL_MODE>(desc->cullMode) : D3D12_CULL_MODE_NONE;
    p.RasterizerState.FrontCounterClockwise = desc->frontCounterClockwise ? TRUE : FALSE;
    p.RasterizerState.DepthClipEnable = TRUE;
    p.RasterizerState.MultisampleEnable = desc->sampleCount > 1 ? TRUE : FALSE;
    p.DepthStencilState.DepthEnable = desc->depthFormat != 0 ? TRUE : FALSE;
    p.DepthStencilState.DepthWriteMask = desc->depthWrite ? D3D12_DEPTH_WRITE_MASK_ALL : D3D12_DEPTH_WRITE_MASK_ZERO;
    p.DepthStencilState.DepthFunc = desc->depthCompare >= 1 && desc->depthCompare <= 8 ? static_cast<D3D12_COMPARISON_FUNC>(desc->depthCompare) : D3D12_COMPARISON_FUNC_ALWAYS;
    p.DepthStencilState.StencilEnable = FALSE;
    p.DSVFormat = static_cast<DXGI_FORMAT>(desc->depthFormat);
    p.PrimitiveTopologyType = desc->topologyType == 1 ? D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT
                            : desc->topologyType == 2 ? D3D12_PRIMITIVE_TOPOLOGY_TYPE_LINE
                            : D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    p.SampleDesc.Count = std::max(1u, desc->sampleCount);

    // Each attribute under two semantics, so shaders may declare ATTRIBUTEn or TEXCOORDn.
    std::vector<D3D12_INPUT_ELEMENT_DESC> elements;
    for (uint32_t i = 0; i < desc->attributeCount; i++) {
        const CMVertexAttribute &a = desc->attributes[i];
        bool perInstance = a.bufferIndex < desc->layoutCount && desc->layouts[a.bufferIndex].perInstance;
        for (const char *semantic : {"ATTRIBUTE", "TEXCOORD"}) {
            D3D12_INPUT_ELEMENT_DESC e{};
            e.SemanticName = semantic;
            e.SemanticIndex = a.semanticIndex;
            e.Format = static_cast<DXGI_FORMAT>(a.dxgiFormat);
            e.InputSlot = a.bufferIndex;
            e.AlignedByteOffset = a.offset;
            e.InputSlotClass = perInstance ? D3D12_INPUT_CLASSIFICATION_PER_INSTANCE_DATA : D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA;
            e.InstanceDataStepRate = perInstance ? 1 : 0;
            elements.push_back(e);
        }
    }
    p.InputLayout = {elements.empty() ? nullptr : elements.data(), static_cast<UINT>(elements.size())};

    CMPipeline *pipe = new CMPipeline;
    pipe->device = d;
    for (uint32_t i = 0; i < desc->layoutCount && i < 16; i++) pipe->strides[i] = desc->layouts[i].stride;
    HRESULT hr = d->device->CreateGraphicsPipelineState(&p, IID_PPV_ARGS(pipe->state.put()));
    if (FAILED(hr)) {
        char buf[512];
        snprintf(buf, sizeof buf, "CreateGraphicsPipelineState failed (HRESULT 0x%08lX)%s", static_cast<unsigned long>(hr),
                 hr == E_INVALIDARG ? ": check that the vertex shader's input semantics (ATTRIBUTEn/TEXCOORDn) match the vertex descriptor, that the render target formats match, and that shader model 6 blobs are signed (dxil.dll)" : "");
        setError(errorOut, errorCapacity, buf);
        delete pipe;
        return nullptr;
    }
    d->livePipelines++;
    return pipe;
}

void cm_pipeline_release(CMPipeline *p) {
    if (!p || p->released) return;
    p->released = true;
    if (p->listRefs == 0) destroyPipeline(p);
}

// MARK: - Command lists

CMCommandList *cm_commandlist_create(CMDevice *d) {
    if (!d) return nullptr;
    {
        std::lock_guard<std::mutex> lock(d->mutex);
        if (!d->listPool.empty()) {
            CMCommandList *l = d->listPool.back();
            d->listPool.pop_back();
            return l;
        }
    }
    CMCommandList *l = new CMCommandList;
    l->device = d;
    if (FAILED(d->device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(l->allocator.put())))
        || FAILED(d->device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, l->allocator.get(), nullptr, IID_PPV_ARGS(l->list.put())))) { delete l; return nullptr; }
    l->list->Close();
    std::lock_guard<std::mutex> lock(d->mutex);
    d->lists.push_back(l);
    d->liveLists++;
    return l;
}

void cm_commandlist_release(CMCommandList *l) {
    if (!l) return;
    if (l->open) { l->list->Close(); l->open = false; }
    finishList(l);
    CMDevice *d = l->device;
    std::lock_guard<std::mutex> lock(d->mutex);
    if (d->listPool.size() < 8) d->listPool.push_back(l);
    else destroyCommandList(l);
}

void cm_commandlist_reset(CMCommandList *l) {
    if (!l) return;
    if (l->open) { l->list->Close(); l->open = false; }
    finishList(l);
    if (FAILED(l->allocator->Reset())) return;
    if (FAILED(l->list->Reset(l->allocator.get(), nullptr))) return;
    l->open = true;
    resetBindings(l);
    bindDefaults(l);
}

void cm_commandlist_begin_render_pass(CMCommandList *l, CMTexture **colors, const uint32_t *loadActions, const float *clearColors, uint32_t colorCount,
                                      CMTexture *depth, uint32_t depthLoadAction, float clearDepth) {
    if (!l || !l->open) return;
    ID3D12GraphicsCommandList *list = l->list.get();
    CMDevice *d = l->device;
    resetBindings(l);
    D3D12_CPU_DESCRIPTOR_HANDLE rtvs[8] = {};
    uint32_t rtvCount = 0;
    l->targetWidth = l->targetHeight = 0;
    for (uint32_t i = 0; i < colorCount && i < 8; i++) {
        CMTexture *t = colors ? colors[i] : nullptr;
        if (!t || t->rtv == UINT32_MAX) continue;
        retain(l->textureRefs, t);
        transition(list, t->resource.get(), t->state, D3D12_RESOURCE_STATE_RENDER_TARGET);
        rtvs[rtvCount++] = d->rtvs.cpu(t->rtv);
        if (l->targetWidth == 0) { l->targetWidth = static_cast<float>(t->width); l->targetHeight = static_cast<float>(t->height); }
        if (loadActions && loadActions[i] == 2) {
            const float black[4] = {0, 0, 0, 0};
            list->ClearRenderTargetView(d->rtvs.cpu(t->rtv), clearColors ? clearColors + 4 * i : black, 0, nullptr);
        }
    }
    D3D12_CPU_DESCRIPTOR_HANDLE dsv{};
    bool hasDepth = depth && depth->dsv != UINT32_MAX;
    if (hasDepth) {
        retain(l->textureRefs, depth);
        transition(list, depth->resource.get(), depth->state, D3D12_RESOURCE_STATE_DEPTH_WRITE);
        dsv = d->dsvs.cpu(depth->dsv);
        if (l->targetWidth == 0) { l->targetWidth = static_cast<float>(depth->width); l->targetHeight = static_cast<float>(depth->height); }
        if (depthLoadAction == 2) {
            D3D12_CLEAR_FLAGS flags = D3D12_CLEAR_FLAG_DEPTH;
            if (depth->hasStencil) flags |= D3D12_CLEAR_FLAG_STENCIL;
            list->ClearDepthStencilView(dsv, flags, clearDepth, 0, 0, nullptr);
        }
    }
    list->OMSetRenderTargets(rtvCount, rtvCount ? rtvs : nullptr, FALSE, hasDepth ? &dsv : nullptr);
}

void cm_commandlist_end_render_pass(CMCommandList *l) {
    if (!l || !l->open) return;
    l->list->OMSetRenderTargets(0, nullptr, FALSE, nullptr);
    l->targetWidth = l->targetHeight = 0;
}

void cm_commandlist_set_pipeline(CMCommandList *l, CMPipeline *p) {
    if (!l || !l->open || !p) return;
    retain(l->pipelineRefs, p);
    l->pipeline = p;
    l->list->SetPipelineState(p->state.get());
}

void cm_commandlist_set_viewport(CMCommandList *l, float x, float y, float w, float h, float zmin, float zmax) {
    if (!l || !l->open) return;
    D3D12_VIEWPORT vp{x, y, w, h, zmin, zmax};
    l->list->RSSetViewports(1, &vp);
    l->viewportSet = true;
}

void cm_commandlist_set_scissor(CMCommandList *l, int32_t x, int32_t y, int32_t w, int32_t h) {
    if (!l || !l->open) return;
    D3D12_RECT r{x, y, x + w, y + h};
    l->list->RSSetScissorRects(1, &r);
    l->scissorSet = true;
}

void cm_commandlist_set_vertex_buffer(CMCommandList *l, uint32_t slot, CMBuffer *buffer, uint64_t offset, uint32_t stride) {
    if (!l || slot >= 16) return;
    retain(l->bufferRefs, buffer);
    l->vertexBuffers[slot] = {buffer, offset, stride, true};
}

void cm_commandlist_set_shader_buffer(CMCommandList *l, bool pixelStage, uint32_t slot, CMBuffer *buffer, uint64_t offset) {
    if (!l || slot >= 8) return;
    retain(l->bufferRefs, buffer);
    l->constantBuffers[pixelStage ? 1 : 0][slot] = {buffer, offset, true};
}

void cm_commandlist_set_shader_texture(CMCommandList *l, bool pixelStage, uint32_t slot, CMTexture *texture) {
    if (!l || !l->open || slot >= 8) return;
    int stage = pixelStage ? 1 : 0;
    retain(l->textureRefs, texture);
    if (texture) {
        transition(l->list.get(), texture->resource.get(), texture->state,
                   D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    }
    l->textures[stage][slot] = texture;
    l->texturesDirty[stage] = true;
}

void cm_commandlist_set_sampler(CMCommandList *l, bool pixelStage, uint32_t slot, uint32_t filter, uint32_t addressU, uint32_t addressV) {
    if (!l || slot >= 8) return;
    int stage = pixelStage ? 1 : 0;
    l->samplers[stage][slot] = {filter, addressU, addressV};
    l->samplersDirty[stage] = true;
}

void cm_commandlist_draw(CMCommandList *l, uint32_t topology, uint32_t vertexStart, uint32_t vertexCount, uint32_t instanceCount) {
    if (!l || vertexCount == 0 || !prepareDraw(l, topology)) return;
    l->list->DrawInstanced(vertexCount, std::max(1u, instanceCount), vertexStart, 0);
}

void cm_commandlist_draw_indexed(CMCommandList *l, uint32_t topology, uint32_t indexCount, bool index32, CMBuffer *indexBuffer, uint64_t indexOffset, uint32_t instanceCount) {
    if (!l || !indexBuffer || indexCount == 0 || !prepareDraw(l, topology)) return;
    retain(l->bufferRefs, indexBuffer);
    D3D12_INDEX_BUFFER_VIEW view{};
    view.BufferLocation = indexBuffer->gpu + indexOffset;
    view.SizeInBytes = indexOffset < indexBuffer->length ? static_cast<UINT>(indexBuffer->length - indexOffset) : 0;
    view.Format = index32 ? DXGI_FORMAT_R32_UINT : DXGI_FORMAT_R16_UINT;
    l->list->IASetIndexBuffer(&view);
    l->list->DrawIndexedInstanced(indexCount, std::max(1u, instanceCount), 0, 0, 0);
}

void cm_commandlist_copy_buffer(CMCommandList *l, CMBuffer *src, uint64_t srcOffset, CMBuffer *dst, uint64_t dstOffset, uint64_t size) {
    if (!l || !l->open || !src || !dst || size == 0) return;
    if (srcOffset + size > src->length || dstOffset + size > dst->length) return;
    ID3D12GraphicsCommandList *list = l->list.get();
    if (src == dst) {
        // D3D12 forbids copying within one resource: stage through a temporary that the
        // list keeps alive until its next reset or release (after the fence wait).
        CMBuffer *tmp = cm_buffer_create(l->device, size);
        if (!tmp) return;
        l->transientBuffers.push_back(tmp);
        cm_commandlist_copy_buffer(l, src, srcOffset, tmp, 0, size);
        cm_commandlist_copy_buffer(l, tmp, 0, dst, dstOffset, size);
        return;
    }
    retain(l->bufferRefs, src);
    retain(l->bufferRefs, dst);
    transition(list, src->resource.get(), src->state, D3D12_RESOURCE_STATE_COPY_SOURCE);
    transition(list, dst->resource.get(), dst->state, D3D12_RESOURCE_STATE_COPY_DEST);
    list->CopyBufferRegion(dst->resource.get(), dstOffset, src->resource.get(), srcOffset, size);
    // Back to COMMON, which buffers decay to anyway and which promotes to every read state.
    transition(list, src->resource.get(), src->state, D3D12_RESOURCE_STATE_COMMON);
    transition(list, dst->resource.get(), dst->state, D3D12_RESOURCE_STATE_COMMON);
}

void cm_commandlist_copy_texture(CMCommandList *l, CMTexture *src, CMTexture *dst) {
    if (!l || !l->open || !src || !dst || src == dst) return;
    retain(l->textureRefs, src);
    retain(l->textureRefs, dst);
    ID3D12GraphicsCommandList *list = l->list.get();
    transition(list, src->resource.get(), src->state, D3D12_RESOURCE_STATE_COPY_SOURCE);
    transition(list, dst->resource.get(), dst->state, D3D12_RESOURCE_STATE_COPY_DEST);
    if (src->width == dst->width && src->height == dst->height && src->mipLevels == dst->mipLevels && typelessFor(src->format) == typelessFor(dst->format)) {
        list->CopyResource(dst->resource.get(), src->resource.get());
        return;
    }
    D3D12_TEXTURE_COPY_LOCATION s{}, d{};
    s.pResource = src->resource.get();
    s.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    d.pResource = dst->resource.get();
    d.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    D3D12_BOX box{0, 0, 0, std::min(src->width, dst->width), std::min(src->height, dst->height), 1};
    list->CopyTextureRegion(&d, 0, 0, 0, &s, &box);
}

void cm_commandlist_copy_texture_region(CMCommandList *l, CMTexture *src, uint32_t srcX, uint32_t srcY, CMTexture *dst, uint32_t dstX, uint32_t dstY, uint32_t width, uint32_t height) {
    if (!l || !l->open || !src || !dst || width == 0 || height == 0) return;
    if (srcX + width > src->width || srcY + height > src->height || dstX + width > dst->width || dstY + height > dst->height) return;
    retain(l->textureRefs, src);
    retain(l->textureRefs, dst);
    ID3D12GraphicsCommandList *list = l->list.get();
    auto location = [](CMTexture *t) {
        D3D12_TEXTURE_COPY_LOCATION loc{};
        loc.pResource = t->resource.get();
        loc.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        return loc;
    };
    D3D12_BOX box{srcX, srcY, 0, srcX + width, srcY + height, 1};
    if (src != dst) {
        transition(list, src->resource.get(), src->state, D3D12_RESOURCE_STATE_COPY_SOURCE);
        transition(list, dst->resource.get(), dst->state, D3D12_RESOURCE_STATE_COPY_DEST);
        D3D12_TEXTURE_COPY_LOCATION s = location(src), d = location(dst);
        list->CopyTextureRegion(&d, dstX, dstY, 0, &s, &box);
        return;
    }
    // D3D12 forbids copying within one resource: stage the region in a transient texture
    // that the list's references keep alive until it has executed.
    CMTexture *tmp = cm_texture_create(l->device, width, height, 1, static_cast<uint32_t>(src->format), false, false);
    if (!tmp) return;
    retain(l->textureRefs, tmp);
    tmp->released = true;
    D3D12_TEXTURE_COPY_LOCATION s = location(src), t = location(tmp);
    transition(list, src->resource.get(), src->state, D3D12_RESOURCE_STATE_COPY_SOURCE);
    transition(list, tmp->resource.get(), tmp->state, D3D12_RESOURCE_STATE_COPY_DEST);
    list->CopyTextureRegion(&t, 0, 0, 0, &s, &box);
    transition(list, tmp->resource.get(), tmp->state, D3D12_RESOURCE_STATE_COPY_SOURCE);
    transition(list, dst->resource.get(), dst->state, D3D12_RESOURCE_STATE_COPY_DEST);
    D3D12_BOX whole{0, 0, 0, width, height, 1};
    list->CopyTextureRegion(&s, dstX, dstY, 0, &t, &whole);
}

uint64_t cm_commandlist_execute(CMCommandList *l, CMQueue *queue) {
    if (!l || !queue) return 0;
    if (l->open) {
        HRESULT hr = l->list->Close();
        l->open = false;
        if (FAILED(hr)) { logf("ID3D12GraphicsCommandList::Close failed 0x%08lX", static_cast<unsigned long>(hr)); drainMessages(l->device); return 0; }
    }
    logDeviceState(l->device, "before ExecuteCommandLists");
    ID3D12CommandList *lists[] = {l->list.get()};
    queue->queue->ExecuteCommandLists(1, lists);
    logDeviceState(l->device, "after ExecuteCommandLists");
    l->executedOn = queue;
    l->fenceValue = queueSignal(queue);
    return l->fenceValue;
}

// MARK: - Swap chain

/// Shared body of cm_swapchain_create (HWND) and cm_swapchain_create_composition (no HWND).
static CMSwapChain *createSwapChain(CMDevice *d, CMQueue *queue, HWND hwnd, uint32_t width, uint32_t height, uint32_t dxgiFormat, uint32_t bufferCount, bool composition, bool opaque) {
    if (!d || !queue || width == 0 || height == 0 || dxgiFormat == 0) return nullptr;
    CMSwapChain *sc = new CMSwapChain;
    sc->device = d;
    sc->queue = queue;
    sc->hwnd = hwnd;
    sc->format = static_cast<DXGI_FORMAT>(dxgiFormat);
    sc->bufferCount = std::max(2u, std::min(bufferCount, 16u));
    sc->width = width;
    sc->height = height;
    DXGI_SWAP_CHAIN_DESC1 desc{};
    desc.Width = width;
    desc.Height = height;
    desc.Format = sc->format;
    desc.SampleDesc.Count = 1;
    desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = sc->bufferCount;
    desc.Scaling = DXGI_SCALING_STRETCH;
    // A composition chain is read back after presenting (MTKView's pixel logging and the
    // parity tests), so its buffers keep their contents: FLIP_SEQUENTIAL.
    desc.SwapEffect = composition ? DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL : DXGI_SWAP_EFFECT_FLIP_DISCARD;
    desc.AlphaMode = composition ? (opaque ? DXGI_ALPHA_MODE_IGNORE : DXGI_ALPHA_MODE_PREMULTIPLIED) : DXGI_ALPHA_MODE_UNSPECIFIED;
    Com<IDXGISwapChain1> sc1;
    HRESULT hr = composition
        ? d->factory->CreateSwapChainForComposition(queue->queue.get(), &desc, nullptr, sc1.put())
        : d->factory->CreateSwapChainForHwnd(queue->queue.get(), sc->hwnd, &desc, nullptr, nullptr, sc1.put());
    if (FAILED(hr) || FAILED(sc1->QueryInterface(IID_PPV_ARGS(sc->swapChain.put())))) { logf("swap chain creation failed 0x%08lX (%s, %ux%u, format %u)", hr, composition ? "composition" : "hwnd", width, height, dxgiFormat); drainMessages(d); delete sc; return nullptr; }
    logf("swap chain created (%s, %ux%u, format %u, %u buffers)", composition ? "composition" : "hwnd", width, height, dxgiFormat, sc->bufferCount);
    logDeviceState(d, "after swap chain creation");
    if (hwnd) d->factory->MakeWindowAssociation(sc->hwnd, DXGI_MWA_NO_ALT_ENTER);
    if (sc->format == DXGI_FORMAT_R16G16B16A16_FLOAT) {
        // FP16 buffers are scRGB (linear, 709 primaries, 1.0 = 80 nits): say so, as the
        // window's own HDR chain does (ADR-0016), so DWM composes them as HDR content.
        UINT support = 0;
        if (SUCCEEDED(sc->swapChain->CheckColorSpaceSupport(DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709, &support)) && (support & DXGI_SWAP_CHAIN_COLOR_SPACE_SUPPORT_FLAG_PRESENT)) {
            HRESULT cs = sc->swapChain->SetColorSpace1(DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709);
            logf("swap chain colour space scRGB (G10 P709): 0x%08lX", cs);
        } else {
            logf("swap chain colour space scRGB not supported for presentation; left at the default");
        }
    }
    char error[256] = {};
    if (!acquireSwapChainBuffers(sc, error, sizeof error)) { logf("%s", error); cm_swapchain_release(sc); return nullptr; }
    logDeviceState(d, "after acquiring the back buffers");
    d->liveSwapChains++;
    return sc;
}

CMSwapChain *cm_swapchain_create(CMDevice *d, CMQueue *queue, void *hwnd, uint32_t width, uint32_t height, uint32_t dxgiFormat, uint32_t bufferCount) {
    if (!hwnd) return nullptr;
    return createSwapChain(d, queue, static_cast<HWND>(hwnd), width, height, dxgiFormat, bufferCount, false, true);
}

CMSwapChain *cm_swapchain_create_composition(CMDevice *d, CMQueue *queue, uint32_t width, uint32_t height, uint32_t dxgiFormat, uint32_t bufferCount, bool opaque) {
    return createSwapChain(d, queue, nullptr, width, height, dxgiFormat, bufferCount, true, opaque);
}

void *cm_swapchain_native(CMSwapChain *sc) {
    return sc ? static_cast<IDXGISwapChain1 *>(sc->swapChain.get()) : nullptr;
}

void cm_swapchain_last_error(CMSwapChain *sc, char *errorOut, uint32_t errorCapacity) {
    setError(errorOut, errorCapacity, sc ? sc->lastError : "no swap chain");
}

void cm_swapchain_release(CMSwapChain *sc) {
    if (!sc) return;
    queueWait(sc->queue, sc->queue->lastSignaled);
    releaseSwapChainBuffers(sc);
    if (sc->swapChain) sc->device->liveSwapChains--;
    delete sc;
}

bool cm_swapchain_resize(CMSwapChain *sc, uint32_t width, uint32_t height) {
    if (!sc || width == 0 || height == 0) return false;
    queueWait(sc->queue, sc->queue->lastSignaled);
    releaseSwapChainBuffers(sc);
    HRESULT hr = sc->swapChain->ResizeBuffers(sc->bufferCount, width, height, sc->format, 0);
    if (FAILED(hr)) { setErrorHR(sc->lastError, sizeof sc->lastError, "IDXGISwapChain::ResizeBuffers", hr); logf("ResizeBuffers to %ux%u failed 0x%08lX (device removed: 0x%08lX)", width, height, hr, static_cast<unsigned long>(sc->device->device->GetDeviceRemovedReason())); drainMessages(sc->device); return false; }
    logf("swap chain resized to %ux%u", width, height);
    sc->width = width;
    sc->height = height;
    char error[256] = {};
    if (!acquireSwapChainBuffers(sc, error, sizeof error)) { setError(sc->lastError, sizeof sc->lastError, error); logf("%s", error); return false; }
    return true;
}

CMTexture *cm_swapchain_acquire(CMSwapChain *sc) {
    if (!sc || sc->buffers.empty()) { if (sc) setError(sc->lastError, sizeof sc->lastError, "no back buffers (a resize failed)"); return nullptr; }
    UINT index = sc->swapChain->GetCurrentBackBufferIndex();
    logDeviceState(sc->device, "at acquire");
    if (index >= sc->buffers.size()) { setError(sc->lastError, sizeof sc->lastError, "back buffer index out of range"); return nullptr; }
    return sc->buffers[index];
}

bool cm_swapchain_present(CMSwapChain *sc, bool vsync) {
    if (!sc || sc->buffers.empty()) return false;
    CMTexture *back = sc->buffers[sc->swapChain->GetCurrentBackBufferIndex()];
    if (back->state != D3D12_RESOURCE_STATE_PRESENT) {
        runUtility(sc->device, sc->queue, [&](ID3D12GraphicsCommandList *list) { transition(list, back->resource.get(), back->state, D3D12_RESOURCE_STATE_PRESENT); });
    }
    HRESULT hr = sc->swapChain->Present(vsync ? 1 : 0, 0);
    if (FAILED(hr)) {
        setErrorHR(sc->lastError, sizeof sc->lastError, "IDXGISwapChain::Present", hr);
        logf("Present failed 0x%08lX (device removed: 0x%08lX)", hr, static_cast<unsigned long>(sc->device->device->GetDeviceRemovedReason()));
        drainMessages(sc->device);
        return false;
    }
    return true;
}

}
