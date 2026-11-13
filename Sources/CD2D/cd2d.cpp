#include "cd2d.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d2d1.h>
#include <d2d1_1.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dxgi1_3.h>
#include <dxgi1_6.h>
#include <dxgidebug.h>
#include <d2d1effects.h>
#include <dcomp.h>
#include <d3d9types.h>
#include <dwrite.h>
#include <wincodec.h>
#include <shlwapi.h>
#include <commdlg.h>
#include <shobjidl.h>
#include <winspool.h>
#include <commdlg.h>
#include <documenttarget.h>
#include <prntvpt.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlguid.h>
#include <ole2.h>
#include <string>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <cstring>
#include <cstdio>

struct CD2DFactory { ID2D1Factory *factory = nullptr; };
struct CD2DTarget {
    ID2D1RenderTarget *target = nullptr;          // used for all drawing calls
    ID2D1HwndRenderTarget *hwnd = nullptr;        // non-null for legacy window targets
    // Swap-chain presentation (Milestone 3). All non-null only for swap-chain targets;
    // `target` then points at `dc`.
    ID3D11Device *d3dDevice = nullptr;
    ID3D11DeviceContext *d3dContext = nullptr;
    IDXGISwapChain1 *swapChain = nullptr;
    ID2D1Device *d2dDevice = nullptr;
    ID2D1DeviceContext *dc = nullptr;
    ID2D1Bitmap1 *backBuffer = nullptr;
    // Partial repaint: drawing goes to a persistent canvas; end_draw copies what changed
    // into the back buffer (this frame's rect and the previous one's, since the two
    // buffers alternate) and presents with that rect as the dirty region.
    ID2D1Bitmap1 *canvas = nullptr;
    D2D1_RECT_U dirty = {};                       // this frame, pixels; whole when !hasDirty
    bool hasDirty = false;
    bool canvasFresh = true;                      // new or resized: the next frame copies everything
    // DirectComposition presentation (Milestone 3b). Non-null only for composition
    // swap-chain targets; the back buffer is then premultiplied.
    IDCompositionDevice *dcompDevice = nullptr;
    IDCompositionTarget *dcompTarget = nullptr;
    IDCompositionVisual *dcompVisual = nullptr;
    D2D1_ALPHA_MODE alphaMode = D2D1_ALPHA_MODE_IGNORE;   // of the swap-chain back buffer
    // HDR presentation (ADR-0016): FP16 scRGB back buffers; the canvas stays 8-bit sRGB
    // and end_draw runs it through sRGB → linear (colour management) and a white-level
    // scale (colour matrix) instead of a copy.
    DXGI_FORMAT chainFormat = DXGI_FORMAT_B8G8R8A8_UNORM;
    bool hdr = false;
    float sdrWhiteNits = 80;
    ID2D1Effect *toLinear = nullptr;
    ID2D1Effect *whiteScale = nullptr;
    float dpi = 96;
    bool lost = false;                            // device removed/reset: end_draw reports it
    // Composition surface targets (Milestone 9): BeginDraw hands out a region of a larger
    // atlas, so every transform the caller sets is shifted by this origin (DIPs).
    float originX = 0, originY = 0;
};
struct CD2DBrush { ID2D1SolidColorBrush *brush = nullptr; };
struct CD2DStrokeStyle { ID2D1StrokeStyle *style = nullptr; };
struct CD2DPath {
    ID2D1PathGeometry *geometry = nullptr;
    ID2D1GeometrySink *sink = nullptr;
    bool figureOpen = false;
};

template <typename T> static void safeRelease(T *&p) { if (p) { p->Release(); p = nullptr; } }

extern "C" {

CD2DFactory *cd2d_factory_create(void) {
    ID2D1Factory *f = nullptr;
    if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &f))) return nullptr;
    CD2DFactory *r = new CD2DFactory();
    r->factory = f;
    return r;
}

void cd2d_factory_release(CD2DFactory *factory) {
    if (!factory) return;
    safeRelease(factory->factory);
    delete factory;
}

CD2DTarget *cd2d_target_create_hwnd(CD2DFactory *factory, void *hwnd, uint32_t w, uint32_t h, float dpi) {
    if (!factory || !factory->factory) return nullptr;
    D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED),
        dpi, dpi);
    D2D1_HWND_RENDER_TARGET_PROPERTIES hp = D2D1::HwndRenderTargetProperties(
        (HWND)hwnd, D2D1::SizeU(w ? w : 1, h ? h : 1), D2D1_PRESENT_OPTIONS_RETAIN_CONTENTS);
    ID2D1HwndRenderTarget *t = nullptr;
    if (FAILED(factory->factory->CreateHwndRenderTarget(&props, &hp, &t))) return nullptr;
    CD2DTarget *r = new CD2DTarget();
    r->target = t;
    r->hwnd = t;
    return r;
}

// ---------------------------------------------------------------- swap-chain target

static bool isDeviceLost(HRESULT hr) {
    return hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET || hr == D2DERR_RECREATE_TARGET;
}

/// Wraps swap-chain buffer 0 in an ID2D1Bitmap1 and makes it the device context's target.
static bool createBackBufferBitmap(CD2DTarget *t) {
    IDXGISurface *surface = nullptr;
    HRESULT hr = t->swapChain->GetBuffer(0, __uuidof(IDXGISurface), reinterpret_cast<void **>(&surface));
    if (FAILED(hr)) { t->lost = true; return false; }
    D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(t->chainFormat, t->alphaMode), t->dpi, t->dpi);
    hr = t->dc->CreateBitmapFromDxgiSurface(surface, &props, &t->backBuffer);
    surface->Release();
    if (FAILED(hr)) { t->lost = true; return false; }
    // The canvas the frames accumulate in, same size and format as the back buffer.
    D2D1_SIZE_U size = t->backBuffer->GetPixelSize();
    D2D1_BITMAP_PROPERTIES1 canvasProps = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, t->alphaMode), t->dpi, t->dpi);
    hr = t->dc->CreateBitmap(size, nullptr, 0, &canvasProps, &t->canvas);
    if (FAILED(hr)) { safeRelease(t->backBuffer); t->lost = true; return false; }
    if (t->hdr) {
        if (t->toLinear) t->toLinear->SetInput(0, t->canvas);
        else { safeRelease(t->canvas); safeRelease(t->backBuffer); t->lost = true; return false; }
    }
    t->canvasFresh = true;
    t->hasDirty = false;
    t->dc->SetTarget(t->canvas);
    t->dc->SetDpi(t->dpi, t->dpi);
    return true;
}

static void releaseBackBufferBitmap(CD2DTarget *t) {
    if (t->dc) t->dc->SetTarget(nullptr);
    safeRelease(t->canvas);
    safeRelease(t->backBuffer);
    // ResizeBuffers needs every reference to the buffers gone, including any the D3D
    // immediate context still holds for in-flight work.
    if (t->d3dContext) { t->d3dContext->ClearState(); t->d3dContext->Flush(); }
}

/// The white-level scale of an HDR target: scRGB 1.0 is 80 nits, the desktop shows SDR
/// white at the monitor's SDR white level, so the frame is multiplied by their ratio.
static void applyWhiteLevel(CD2DTarget *t) {
    if (!t->whiteScale) return;
    float s = t->sdrWhiteNits > 0 ? t->sdrWhiteNits / 80.0f : 1.0f;
    D2D1_MATRIX_5X4_F m = {};
    m.m[0][0] = s; m.m[1][1] = s; m.m[2][2] = s; m.m[3][3] = 1;   // alpha unscaled, no offset
    t->whiteScale->SetValue(D2D1_COLORMATRIX_PROP_COLOR_MATRIX, m);
}

/// Builds the HDR presentation chain on `t->dc`: canvas (sRGB, 8-bit) → colour management
/// (sRGB → scRGB, i.e. linear with 1.0 = 80 nits) → colour matrix (× SDR white / 80), both
/// computing in 16-bit float so values above 1.0 survive. The canvas is wired in by
/// createBackBufferBitmap.
static bool createHDREffects(CD2DTarget *t) {
    ID2D1ColorContext *srgb = nullptr, *scrgb = nullptr;
    bool ok = false;
    do {
        if (FAILED(t->dc->CreateColorContext(D2D1_COLOR_SPACE_SRGB, nullptr, 0, &srgb))) break;
        if (FAILED(t->dc->CreateColorContext(D2D1_COLOR_SPACE_SCRGB, nullptr, 0, &scrgb))) break;
        if (FAILED(t->dc->CreateEffect(CLSID_D2D1ColorManagement, &t->toLinear))) break;
        if (FAILED(t->toLinear->SetValue(D2D1_COLORMANAGEMENT_PROP_SOURCE_COLOR_CONTEXT, srgb))) break;
        if (FAILED(t->toLinear->SetValue(D2D1_COLORMANAGEMENT_PROP_DESTINATION_COLOR_CONTEXT, scrgb))) break;
        t->toLinear->SetValue(D2D1_COLORMANAGEMENT_PROP_ALPHA_MODE, D2D1_COLORMANAGEMENT_ALPHA_MODE_PREMULTIPLIED);
        t->toLinear->SetValue(D2D1_COLORMANAGEMENT_PROP_QUALITY, D2D1_COLORMANAGEMENT_QUALITY_NORMAL);
        t->toLinear->SetValue(D2D1_PROPERTY_PRECISION, D2D1_BUFFER_PRECISION_16BPC_FLOAT);
        if (FAILED(t->dc->CreateEffect(CLSID_D2D1ColorMatrix, &t->whiteScale))) break;
        t->whiteScale->SetValue(D2D1_PROPERTY_PRECISION, D2D1_BUFFER_PRECISION_16BPC_FLOAT);
        t->whiteScale->SetValue(D2D1_COLORMATRIX_PROP_CLAMP_OUTPUT, FALSE);
        t->whiteScale->SetValue(D2D1_COLORMATRIX_PROP_ALPHA_MODE, D2D1_COLORMATRIX_ALPHA_MODE_PREMULTIPLIED);
        t->whiteScale->SetInputEffect(0, t->toLinear);
        applyWhiteLevel(t);
        ok = true;
    } while (false);
    safeRelease(srgb);
    safeRelease(scrgb);
    if (!ok) { safeRelease(t->toLinear); safeRelease(t->whiteScale); }
    return ok;
}

static HRESULT createD3DDevice(ID3D11Device **device, ID3D11DeviceContext **context) {
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    // APPKITWIN_DXGI_DEBUG=1 also asks for the D3D11 debug layer (needs the optional
    // "Graphics Tools" feature; silently dropped below when it is not installed).
    char dbg[8] = {};
    if (GetEnvironmentVariableA("APPKITWIN_DXGI_DEBUG", dbg, sizeof dbg) == 1 && dbg[0] == '1') flags |= D3D11_CREATE_DEVICE_DEBUG;
    static const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0,
        D3D_FEATURE_LEVEL_9_3, D3D_FEATURE_LEVEL_9_2, D3D_FEATURE_LEVEL_9_1 };
    const D3D_DRIVER_TYPE drivers[] = { D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP };
    HRESULT hr = E_FAIL;
    for (D3D_DRIVER_TYPE driver : drivers) {
        for (int attempt = 0; attempt < 2; attempt++) {
            UINT f = flags;
            if (attempt == 1) {
                // The debug layer needs the optional "Graphics Tools" feature; retry without it.
                if (!(f & D3D11_CREATE_DEVICE_DEBUG)) break;
                f &= ~D3D11_CREATE_DEVICE_DEBUG;
            }
            D3D_FEATURE_LEVEL got;
            hr = D3D11CreateDevice(nullptr, driver, nullptr, f, levels, ARRAYSIZE(levels), D3D11_SDK_VERSION, device, &got, context);
            if (hr == E_INVALIDARG)   // pre-11.1 runtime does not know D3D_FEATURE_LEVEL_11_1
                hr = D3D11CreateDevice(nullptr, driver, nullptr, f, levels + 1, ARRAYSIZE(levels) - 1, D3D11_SDK_VERSION, device, &got, context);
            if (SUCCEEDED(hr)) return hr;
        }
    }
    return hr;
}

/// Shared body of cd2d_target_create_swapchain (HWND swap chain, opaque) and
/// cd2d_target_create_composition_swapchain (composition swap chain, premultiplied,
/// presented through a DirectComposition visual).
static CD2DTarget *createSwapChainTarget(CD2DFactory *factory, void *hwnd, uint32_t w, uint32_t h, float dpi, bool composition, bool hdr, float sdrWhiteNits) {
    if (!factory || !factory->factory || !hwnd) return nullptr;
    ID2D1Factory1 *factory1 = nullptr;
    if (FAILED(factory->factory->QueryInterface(__uuidof(ID2D1Factory1), reinterpret_cast<void **>(&factory1)))) return nullptr;

    CD2DTarget *t = new CD2DTarget();
    t->dpi = dpi;
    t->alphaMode = composition ? D2D1_ALPHA_MODE_PREMULTIPLIED : D2D1_ALPHA_MODE_IGNORE;
    t->hdr = hdr;
    t->sdrWhiteNits = sdrWhiteNits > 0 ? sdrWhiteNits : 80;
    t->chainFormat = hdr ? DXGI_FORMAT_R16G16B16A16_FLOAT : DXGI_FORMAT_B8G8R8A8_UNORM;
    IDXGIDevice *dxgiDevice = nullptr;
    IDXGIAdapter *adapter = nullptr;
    IDXGIFactory2 *dxgiFactory = nullptr;
    bool ok = false;
    do {
        if (FAILED(createD3DDevice(&t->d3dDevice, &t->d3dContext))) break;
        if (FAILED(t->d3dDevice->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void **>(&dxgiDevice)))) break;
        if (FAILED(factory1->CreateDevice(dxgiDevice, &t->d2dDevice))) break;
        if (FAILED(t->d2dDevice->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &t->dc))) break;
        if (FAILED(dxgiDevice->GetAdapter(&adapter))) break;
        if (FAILED(adapter->GetParent(__uuidof(IDXGIFactory2), reinterpret_cast<void **>(&dxgiFactory)))) break;

        DXGI_SWAP_CHAIN_DESC1 desc = {};
        desc.Width = w ? w : 1;
        desc.Height = h ? h : 1;
        desc.Format = t->chainFormat;
        desc.Stereo = FALSE;
        desc.SampleDesc.Count = 1;
        desc.SampleDesc.Quality = 0;
        desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        desc.BufferCount = 2;
        // Composition swap chains require DXGI_SCALING_STRETCH; the visual shows the
        // buffer 1:1 anyway because the chain is resized with the window.
        desc.Scaling = composition ? DXGI_SCALING_STRETCH : DXGI_SCALING_NONE;
        desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
        desc.AlphaMode = composition ? DXGI_ALPHA_MODE_PREMULTIPLIED : DXGI_ALPHA_MODE_IGNORE;
        desc.Flags = 0;
        if (composition) {
            if (FAILED(dxgiFactory->CreateSwapChainForComposition(t->d3dDevice, &desc, nullptr, &t->swapChain))) break;
            if (FAILED(DCompositionCreateDevice(dxgiDevice, __uuidof(IDCompositionDevice), reinterpret_cast<void **>(&t->dcompDevice)))) break;
            if (FAILED(t->dcompDevice->CreateTargetForHwnd((HWND)hwnd, TRUE, &t->dcompTarget))) break;
            if (FAILED(t->dcompDevice->CreateVisual(&t->dcompVisual))) break;
            if (FAILED(t->dcompVisual->SetContent(t->swapChain))) break;
            if (FAILED(t->dcompTarget->SetRoot(t->dcompVisual))) break;
            if (FAILED(t->dcompDevice->Commit())) break;
        } else {
            if (FAILED(dxgiFactory->CreateSwapChainForHwnd(t->d3dDevice, (HWND)hwnd, &desc, nullptr, nullptr, &t->swapChain))) break;
        }
        // Alt+Enter full-screen switching is not an AppKit behaviour.
        dxgiFactory->MakeWindowAssociation((HWND)hwnd, DXGI_MWA_NO_ALT_ENTER);
        if (hdr) {
            // FP16 buffers are scRGB: say so explicitly (IDXGISwapChain3, Windows 10), and
            // give up on HDR when the chain cannot carry that colour space.
            IDXGISwapChain3 *chain3 = nullptr;
            if (FAILED(t->swapChain->QueryInterface(__uuidof(IDXGISwapChain3), reinterpret_cast<void **>(&chain3))) || !chain3) break;
            UINT support = 0;
            HRESULT hr = chain3->CheckColorSpaceSupport(DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709, &support);
            if (SUCCEEDED(hr) && (support & DXGI_SWAP_CHAIN_COLOR_SPACE_SUPPORT_FLAG_PRESENT)) hr = chain3->SetColorSpace1(DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709);
            else hr = E_FAIL;
            chain3->Release();
            if (FAILED(hr)) break;
            if (!createHDREffects(t)) break;
        }
        if (!createBackBufferBitmap(t)) break;
        // The HWND target draws text grayscale-antialiased (premultiplied alpha disables
        // ClearType); keep that on the opaque swap-chain bitmap so frames match, and so the
        // premultiplied swap chain of M3b changes nothing.
        t->dc->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
        ok = true;
    } while (false);

    safeRelease(dxgiFactory);
    safeRelease(adapter);
    safeRelease(dxgiDevice);
    safeRelease(factory1);
    if (!ok) { cd2d_target_release(t); return nullptr; }
    t->target = t->dc;   // ID2D1DeviceContext is an ID2D1RenderTarget; drawing calls are unchanged
    t->dc->AddRef();     // `target` owns its own reference, released in cd2d_target_release
    return t;
}

CD2DTarget *cd2d_target_create_swapchain(CD2DFactory *factory, void *hwnd, uint32_t w, uint32_t h, float dpi) {
    return createSwapChainTarget(factory, hwnd, w, h, dpi, false, false, 80);
}

CD2DTarget *cd2d_target_create_composition_swapchain(CD2DFactory *factory, void *hwnd, uint32_t w, uint32_t h, float dpi) {
    return createSwapChainTarget(factory, hwnd, w, h, dpi, true, false, 80);
}

CD2DTarget *cd2d_target_create_swapchain_with_options(CD2DFactory *factory, void *hwnd, uint32_t w, uint32_t h, float dpi, const CD2DSwapChainOptions *options) {
    if (!options) return createSwapChainTarget(factory, hwnd, w, h, dpi, false, false, 80);
    return createSwapChainTarget(factory, hwnd, w, h, dpi, options->composition, options->hdr, options->sdrWhiteNits);
}

bool cd2d_target_is_hdr(CD2DTarget *target) {
    return target && target->swapChain && target->hdr;
}

void cd2d_target_set_sdr_white_level(CD2DTarget *target, float sdrWhiteNits) {
    if (!target || !target->hdr) return;
    target->sdrWhiteNits = sdrWhiteNits > 0 ? sdrWhiteNits : 80;
    applyWhiteLevel(target);
}

bool cd2d_presentation_available(void) {
    static int cached = -1;
    if (cached >= 0) return cached == 1;
    ID3D11Device *device = nullptr;
    ID3D11DeviceContext *context = nullptr;
    IDXGIDevice *dxgiDevice = nullptr;
    IDXGIAdapter *adapter = nullptr;
    IDXGIFactory2 *factory2 = nullptr;
    bool ok = SUCCEEDED(createD3DDevice(&device, &context))
        && SUCCEEDED(device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void **>(&dxgiDevice)))
        && SUCCEEDED(dxgiDevice->GetAdapter(&adapter))
        && SUCCEEDED(adapter->GetParent(__uuidof(IDXGIFactory2), reinterpret_cast<void **>(&factory2)));
    safeRelease(factory2);
    safeRelease(adapter);
    safeRelease(dxgiDevice);
    safeRelease(context);
    safeRelease(device);
    cached = ok ? 1 : 0;
    return ok;
}

// ---------------------------------------------------------------- monitor HDR state

struct CachedDisplayHDR { CD2DDisplayHDR info; bool found; ULONGLONG when; };
static std::unordered_map<HMONITOR, CachedDisplayHDR> g_displayHDRCache;

/// The SDR white level and advanced-colour state of the display path whose GDI device
/// name is `deviceName` (QueryDisplayConfig; the names match MONITORINFOEX.szDevice).
static void queryDisplayConfig(const wchar_t *deviceName, CD2DDisplayHDR *out) {
    UINT32 pathCount = 0, modeCount = 0;
    for (int attempt = 0; attempt < 4; attempt++) {
        if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount) != ERROR_SUCCESS) return;
        std::vector<DISPLAYCONFIG_PATH_INFO> paths(pathCount);
        std::vector<DISPLAYCONFIG_MODE_INFO> modes(modeCount);
        LONG status = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &pathCount, paths.data(), &modeCount, modes.data(), nullptr);
        if (status == ERROR_INSUFFICIENT_BUFFER) continue;   // a display arrived between the two calls
        if (status != ERROR_SUCCESS) return;
        for (UINT32 i = 0; i < pathCount; i++) {
            DISPLAYCONFIG_SOURCE_DEVICE_NAME source = {};
            source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            source.header.size = sizeof source;
            source.header.adapterId = paths[i].sourceInfo.adapterId;
            source.header.id = paths[i].sourceInfo.id;
            if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS) continue;
            if (wcscmp(source.viewGdiDeviceName, deviceName) != 0) continue;
            DISPLAYCONFIG_SDR_WHITE_LEVEL white = {};
            white.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SDR_WHITE_LEVEL;
            white.header.size = sizeof white;
            white.header.adapterId = paths[i].targetInfo.adapterId;
            white.header.id = paths[i].targetInfo.id;
            // SDRWhiteLevel is in thousandths of 80 nits (1000 = 80 nits).
            if (DisplayConfigGetDeviceInfo(&white.header) == ERROR_SUCCESS && white.SDRWhiteLevel > 0) out->sdrWhiteNits = white.SDRWhiteLevel * 80.0f / 1000.0f;
            DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO color = {};
            color.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
            color.header.size = sizeof color;
            color.header.adapterId = paths[i].targetInfo.adapterId;
            color.header.id = paths[i].targetInfo.id;
            if (DisplayConfigGetDeviceInfo(&color.header) == ERROR_SUCCESS) {
                out->advancedColorSupported = color.advancedColorSupported != 0;
                out->advancedColorEnabled = color.advancedColorEnabled != 0;
                if (color.bitsPerColorChannel) out->bitsPerColor = color.bitsPerColorChannel;
            }
            return;
        }
        return;
    }
}

bool cd2d_display_hdr_info(void *hmonitor, CD2DDisplayHDR *out) {
    if (!out) return false;
    CD2DDisplayHDR info = {};
    info.colorSpace = DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709;
    info.bitsPerColor = 8;
    info.minLuminance = 0;
    info.maxLuminance = 80;
    info.maxFullFrameLuminance = 80;
    info.sdrWhiteNits = 80;
    *out = info;
    HMONITOR monitor = (HMONITOR)hmonitor;
    if (!monitor) return false;
    ULONGLONG now = GetTickCount64();
    auto cached = g_displayHDRCache.find(monitor);
    if (cached != g_displayHDRCache.end() && now - cached->second.when < 1000) { *out = cached->second.info; return cached->second.found; }

    bool found = false;
    IDXGIFactory1 *factory = nullptr;
    if (SUCCEEDED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void **>(&factory))) && factory) {
        IDXGIAdapter1 *adapter = nullptr;
        for (UINT a = 0; !found && factory->EnumAdapters1(a, &adapter) != DXGI_ERROR_NOT_FOUND; a++) {
            IDXGIOutput *output = nullptr;
            for (UINT o = 0; !found && adapter->EnumOutputs(o, &output) != DXGI_ERROR_NOT_FOUND; o++) {
                IDXGIOutput6 *output6 = nullptr;
                if (SUCCEEDED(output->QueryInterface(__uuidof(IDXGIOutput6), reinterpret_cast<void **>(&output6))) && output6) {
                    DXGI_OUTPUT_DESC1 desc = {};
                    if (SUCCEEDED(output6->GetDesc1(&desc)) && desc.Monitor == monitor) {
                        found = true;
                        info.colorSpace = desc.ColorSpace;
                        info.bitsPerColor = desc.BitsPerColor;
                        info.minLuminance = desc.MinLuminance;
                        info.maxLuminance = desc.MaxLuminance;
                        info.maxFullFrameLuminance = desc.MaxFullFrameLuminance;
                    }
                    output6->Release();
                } else {
                    // Pre-1703 DXGI: the plain description only tells whether this is the monitor.
                    DXGI_OUTPUT_DESC desc = {};
                    if (SUCCEEDED(output->GetDesc(&desc)) && desc.Monitor == monitor) found = true;
                }
                output->Release();
            }
            adapter->Release();
        }
        factory->Release();
    }
    if (found) {
        MONITORINFOEXW mi = {};
        mi.cbSize = sizeof mi;
        if (GetMonitorInfoW(monitor, &mi)) queryDisplayConfig(mi.szDevice, &info);
    }
    info.hdr = info.colorSpace == DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020 || (info.advancedColorEnabled && info.maxLuminance > 80);
    char force[8] = {};
    DWORD n = GetEnvironmentVariableA("APPKITWIN_HDR", force, sizeof force);
    if (n == 1 && force[0] == '0') info.hdr = false;
    if (n == 1 && force[0] == '1') info.hdr = true;
    g_displayHDRCache[monitor] = { info, found, now };
    *out = info;
    return found;
}

void cd2d_display_hdr_invalidate(void) {
    g_displayHDRCache.clear();
}

bool cd2d_target_is_swapchain(CD2DTarget *target) {
    return target && target->swapChain;
}

bool cd2d_target_is_composition(CD2DTarget *target) {
    return target && target->dcompDevice;
}

void cd2d_target_release(CD2DTarget *target) {
    if (!target) return;
    releaseBackBufferBitmap(target);   // no-op for HWND and offscreen targets
    safeRelease(target->whiteScale);
    safeRelease(target->toLinear);
    safeRelease(target->target);
    safeRelease(target->dc);
    safeRelease(target->d2dDevice);
    // The visual tree holds the swap chain; drop it (and the HWND target) before the
    // chain and the DXGI device the composition device was created on.
    if (target->dcompTarget) target->dcompTarget->SetRoot(nullptr);
    if (target->dcompVisual) target->dcompVisual->SetContent(nullptr);
    if (target->dcompDevice) target->dcompDevice->Commit();
    safeRelease(target->dcompVisual);
    safeRelease(target->dcompTarget);
    safeRelease(target->dcompDevice);
    safeRelease(target->swapChain);
    safeRelease(target->d3dContext);
    safeRelease(target->d3dDevice);
    target->hwnd = nullptr;
    delete target;
}

void cd2d_target_resize(CD2DTarget *target, uint32_t w, uint32_t h) {
    if (!target) return;
    if (target->hwnd) { target->hwnd->Resize(D2D1::SizeU(w ? w : 1, h ? h : 1)); return; }
    if (!target->swapChain || target->lost) return;
    releaseBackBufferBitmap(target);
    HRESULT hr = target->swapChain->ResizeBuffers(0, w ? w : 1, h ? h : 1, DXGI_FORMAT_UNKNOWN, 0);
    if (FAILED(hr)) { target->lost = true; return; }
    createBackBufferBitmap(target);
}

void cd2d_target_set_dpi(CD2DTarget *target, float dpi) {
    if (!target) return;
    target->dpi = dpi;
    if (target->target) target->target->SetDpi(dpi, dpi);
}

void cd2d_target_begin_draw(CD2DTarget *target) {
    if (!target || !target->target) return;
    target->target->BeginDraw();
    // A new or resized canvas holds undefined pixels: start it transparent (black on an
    // opaque chain) so a partial first paint cannot show memory garbage.
    if (target->swapChain && target->canvasFresh) target->target->Clear(D2D1::ColorF(0, 0, 0, 0));
}

bool cd2d_target_canvas_is_fresh(CD2DTarget *target) {
    return target && target->swapChain && target->canvasFresh;
}

void cd2d_target_set_dirty(CD2DTarget *target, int32_t left, int32_t top, int32_t right, int32_t bottom) {
    if (!target || !target->swapChain) return;
    target->dirty = D2D1::RectU((UINT32)(left < 0 ? 0 : left), (UINT32)(top < 0 ? 0 : top), (UINT32)(right < 0 ? 0 : right), (UINT32)(bottom < 0 ? 0 : bottom));
    target->hasDirty = true;
}

bool cd2d_target_end_draw(CD2DTarget *target) {
    if (!target || !target->target) return false;
    HRESULT hr = target->target->EndDraw();
    if (!target->swapChain) return hr != D2DERR_RECREATE_TARGET;
    if (target->lost || isDeviceLost(hr)) return false;
    if (!target->backBuffer || !target->canvas) { target->lost = true; return false; }
    // The canvas is copied whole into the back buffer every frame (a GPU blit): the two
    // buffers alternate and keeping a history of what each one holds proved fragile. What
    // was repainted this frame is what DWM is told changed.
    D2D1_SIZE_U size = target->backBuffer->GetPixelSize();
    D2D1_RECT_U whole = D2D1::RectU(0, 0, size.width, size.height);
    HRESULT copied;
    if (target->hdr && target->whiteScale) {
        // FP16 back buffer: the 8-bit sRGB canvas goes through the linearising and
        // white-level effects (the formats differ, so a copy is not possible anyway).
        target->dc->SetTarget(target->backBuffer);
        target->dc->BeginDraw();
        target->dc->SetTransform(D2D1::Matrix3x2F::Identity());
        target->dc->DrawImage(target->whiteScale, nullptr, nullptr, D2D1_INTERPOLATION_MODE_NEAREST_NEIGHBOR, D2D1_COMPOSITE_MODE_SOURCE_COPY);
        copied = target->dc->EndDraw();
        target->dc->SetTarget(target->canvas);
    } else {
        D2D1_POINT_2U dest = D2D1::Point2U(0, 0);
        copied = target->backBuffer->CopyFromBitmap(&dest, target->canvas, &whole);
    }
    if (FAILED(copied)) { target->lost = true; return false; }
    bool partial = target->hasDirty && !target->canvasFresh;
    D2D1_RECT_U changed = partial ? target->dirty : whole;
    if (changed.right > size.width) changed.right = size.width;
    if (changed.bottom > size.height) changed.bottom = size.height;
    if (changed.left >= changed.right || changed.top >= changed.bottom) partial = false;
    target->hasDirty = false;
    target->canvasFresh = false;
    HRESULT present;
    if (partial) {
        RECT rect = { (LONG)changed.left, (LONG)changed.top, (LONG)changed.right, (LONG)changed.bottom };
        DXGI_PRESENT_PARAMETERS params = {};
        params.DirtyRectsCount = 1;
        params.pDirtyRects = &rect;
        present = target->swapChain->Present1(1, 0, &params);
    } else {
        present = target->swapChain->Present(1, 0);
    }
    if (isDeviceLost(present)) { target->lost = true; return false; }
    // A composition swap chain reaches the screen only when the visual tree commits.
    if (target->dcompDevice) target->dcompDevice->Commit();
    return true;
}

int32_t cd2d_debug_report_live_objects(void) {
    // DXGIGetDebugInterface1 (dxgi.dll, Windows 8.1+) loads dxgidebug.dll on demand and fails
    // cleanly when it is not installed.
    IDXGIInfoQueue *queue = nullptr;
    IDXGIDebug *debug = nullptr;
    if (FAILED(DXGIGetDebugInterface1(0, __uuidof(IDXGIInfoQueue), reinterpret_cast<void **>(&queue))) || !queue) return -1;
    if (FAILED(DXGIGetDebugInterface1(0, __uuidof(IDXGIDebug), reinterpret_cast<void **>(&debug))) || !debug) { queue->Release(); return -1; }
    queue->ClearStoredMessages(DXGI_DEBUG_ALL);
    debug->ReportLiveObjects(DXGI_DEBUG_ALL, DXGI_DEBUG_RLO_FLAGS(DXGI_DEBUG_RLO_DETAIL | DXGI_DEBUG_RLO_IGNORE_INTERNAL));
    UINT64 count = queue->GetNumStoredMessages(DXGI_DEBUG_ALL);
    int32_t lines = 0;
    for (UINT64 i = 0; i < count; i++) {
        SIZE_T length = 0;
        if (FAILED(queue->GetMessage(DXGI_DEBUG_ALL, i, nullptr, &length)) || length == 0) continue;
        std::vector<unsigned char> buffer(length);
        DXGI_INFO_QUEUE_MESSAGE *msg = reinterpret_cast<DXGI_INFO_QUEUE_MESSAGE *>(buffer.data());
        if (FAILED(queue->GetMessage(DXGI_DEBUG_ALL, i, msg, &length))) continue;
        fprintf(stderr, "[dxgi-debug] %.*s\n", (int)msg->DescriptionByteLength, msg->pDescription);
        lines++;
    }
    fflush(stderr);
    debug->Release();
    queue->Release();
    return lines;
}

void cd2d_target_clear(CD2DTarget *target, float r, float g, float b, float a) {
    if (target && target->target) target->target->Clear(D2D1::ColorF(r, g, b, a));
}

void cd2d_target_set_transform(CD2DTarget *target, const CD2DMatrix *m) {
    if (!target || !target->target || !m) return;
    target->target->SetTransform(D2D1::Matrix3x2F(m->m11, m->m12, m->m21, m->m22, m->dx + target->originX, m->dy + target->originY));
}

void *cd2d_target_render_target(CD2DTarget *target) { return target ? target->target : nullptr; }

void cd2d_target_set_antialias(CD2DTarget *target, bool aa) {
    if (target && target->target)
        target->target->SetAntialiasMode(aa ? D2D1_ANTIALIAS_MODE_PER_PRIMITIVE : D2D1_ANTIALIAS_MODE_ALIASED);
}

CD2DBrush *cd2d_brush_create(CD2DTarget *target, float r, float g, float b, float a) {
    if (!target || !target->target) return nullptr;
    ID2D1SolidColorBrush *br = nullptr;
    if (FAILED(target->target->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), &br))) return nullptr;
    CD2DBrush *res = new CD2DBrush();
    res->brush = br;
    return res;
}

void cd2d_brush_set_color(CD2DBrush *brush, float r, float g, float b, float a) {
    if (brush && brush->brush) brush->brush->SetColor(D2D1::ColorF(r, g, b, a));
}

void cd2d_brush_release(CD2DBrush *brush) {
    if (!brush) return;
    safeRelease(brush->brush);
    delete brush;
}

CD2DStrokeStyle *cd2d_stroke_style_create(CD2DFactory *factory, int cap, int join, float miterLimit,
                                          const float *dashes, uint32_t dashCount, float dashOffset) {
    if (!factory || !factory->factory) return nullptr;
    D2D1_CAP_STYLE c = cap == CD2D_CAP_ROUND ? D2D1_CAP_STYLE_ROUND : cap == CD2D_CAP_SQUARE ? D2D1_CAP_STYLE_SQUARE : D2D1_CAP_STYLE_FLAT;
    D2D1_LINE_JOIN j = join == CD2D_JOIN_ROUND ? D2D1_LINE_JOIN_ROUND : join == CD2D_JOIN_BEVEL ? D2D1_LINE_JOIN_BEVEL : D2D1_LINE_JOIN_MITER_OR_BEVEL;
    D2D1_STROKE_STYLE_PROPERTIES props = D2D1::StrokeStyleProperties(
        c, c, c, j, miterLimit, dashCount ? D2D1_DASH_STYLE_CUSTOM : D2D1_DASH_STYLE_SOLID, dashOffset);
    ID2D1StrokeStyle *s = nullptr;
    if (FAILED(factory->factory->CreateStrokeStyle(&props, dashCount ? dashes : nullptr, dashCount, &s))) return nullptr;
    CD2DStrokeStyle *res = new CD2DStrokeStyle();
    res->style = s;
    return res;
}

void cd2d_stroke_style_release(CD2DStrokeStyle *style) {
    if (!style) return;
    safeRelease(style->style);
    delete style;
}

CD2DPath *cd2d_path_create(CD2DFactory *factory, bool evenOdd) {
    if (!factory || !factory->factory) return nullptr;
    ID2D1PathGeometry *g = nullptr;
    if (FAILED(factory->factory->CreatePathGeometry(&g))) return nullptr;
    ID2D1GeometrySink *sink = nullptr;
    if (FAILED(g->Open(&sink))) { g->Release(); return nullptr; }
    sink->SetFillMode(evenOdd ? D2D1_FILL_MODE_ALTERNATE : D2D1_FILL_MODE_WINDING);
    CD2DPath *p = new CD2DPath();
    p->geometry = g;
    p->sink = sink;
    return p;
}

void cd2d_path_begin_figure(CD2DPath *p, float x, float y) {
    if (!p || !p->sink) return;
    if (p->figureOpen) p->sink->EndFigure(D2D1_FIGURE_END_OPEN);
    p->sink->BeginFigure(D2D1::Point2F(x, y), D2D1_FIGURE_BEGIN_FILLED);
    p->figureOpen = true;
}

void cd2d_path_add_line(CD2DPath *p, float x, float y) {
    if (p && p->sink && p->figureOpen) p->sink->AddLine(D2D1::Point2F(x, y));
}

void cd2d_path_add_quad(CD2DPath *p, float cx, float cy, float x, float y) {
    if (p && p->sink && p->figureOpen)
        p->sink->AddQuadraticBezier(D2D1::QuadraticBezierSegment(D2D1::Point2F(cx, cy), D2D1::Point2F(x, y)));
}

void cd2d_path_add_bezier(CD2DPath *p, float c1x, float c1y, float c2x, float c2y, float x, float y) {
    if (p && p->sink && p->figureOpen)
        p->sink->AddBezier(D2D1::BezierSegment(D2D1::Point2F(c1x, c1y), D2D1::Point2F(c2x, c2y), D2D1::Point2F(x, y)));
}

void cd2d_path_end_figure(CD2DPath *p, bool closed) {
    if (!p || !p->sink || !p->figureOpen) return;
    p->sink->EndFigure(closed ? D2D1_FIGURE_END_CLOSED : D2D1_FIGURE_END_OPEN);
    p->figureOpen = false;
}

void cd2d_path_close(CD2DPath *p) {
    if (!p || !p->sink) return;
    if (p->figureOpen) { p->sink->EndFigure(D2D1_FIGURE_END_OPEN); p->figureOpen = false; }
    p->sink->Close();
    safeRelease(p->sink);
}

void cd2d_path_release(CD2DPath *p) {
    if (!p) return;
    if (p->sink) { if (p->figureOpen) p->sink->EndFigure(D2D1_FIGURE_END_OPEN); p->sink->Close(); safeRelease(p->sink); }
    safeRelease(p->geometry);
    delete p;
}

void cd2d_target_fill_path(CD2DTarget *t, CD2DPath *p, CD2DBrush *b) {
    if (t && t->target && p && p->geometry && b && b->brush) t->target->FillGeometry(p->geometry, b->brush);
}

void cd2d_target_stroke_path(CD2DTarget *t, CD2DPath *p, CD2DBrush *b, float width, CD2DStrokeStyle *s) {
    if (t && t->target && p && p->geometry && b && b->brush)
        t->target->DrawGeometry(p->geometry, b->brush, width, s ? s->style : nullptr);
}

void cd2d_target_fill_rect(CD2DTarget *t, float l, float tp, float r, float bt, CD2DBrush *b) {
    if (t && t->target && b && b->brush) t->target->FillRectangle(D2D1::RectF(l, tp, r, bt), b->brush);
}

void cd2d_target_stroke_rect(CD2DTarget *t, float l, float tp, float r, float bt, CD2DBrush *b, float width, CD2DStrokeStyle *s) {
    if (t && t->target && b && b->brush) t->target->DrawRectangle(D2D1::RectF(l, tp, r, bt), b->brush, width, s ? s->style : nullptr);
}

void cd2d_target_push_clip_rect(CD2DTarget *t, float l, float tp, float r, float bt, bool aa) {
    if (t && t->target)
        t->target->PushAxisAlignedClip(D2D1::RectF(l, tp, r, bt), aa ? D2D1_ANTIALIAS_MODE_PER_PRIMITIVE : D2D1_ANTIALIAS_MODE_ALIASED);
}

void cd2d_target_pop_clip_rect(CD2DTarget *t) {
    if (t && t->target) t->target->PopAxisAlignedClip();
}

void cd2d_target_push_clip_path(CD2DTarget *t, CD2DPath *p) {
    if (!t || !t->target || !p || !p->geometry) return;
    ID2D1Layer *layer = nullptr;
    if (FAILED(t->target->CreateLayer(nullptr, &layer))) return;
    t->target->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), p->geometry), layer);
    layer->Release();   // the target holds its own reference while pushed
}

void cd2d_target_pop_clip_path(CD2DTarget *t) {
    if (t && t->target) t->target->PopLayer();
}

// ---------------------------------------------------------------- Bitmaps / WIC

struct CD2DBitmap { ID2D1Bitmap *bitmap = nullptr; };
struct CD2DOffscreen {
    IWICBitmap *wic = nullptr;
    ID2D1RenderTarget *rt = nullptr;
    CD2DTarget *target = nullptr;
    uint32_t width = 0, height = 0;
};

static IWICImagingFactory *wicFactory() {
    static IWICImagingFactory *f = nullptr;
    if (!f) {
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&f));
    }
    return f;
}

bool cd2d_image_decode(const uint8_t *bytes, uint32_t length, uint32_t *width, uint32_t *height, uint32_t *stride, uint8_t **pixels) {
    IWICImagingFactory *f = wicFactory();
    if (!f || !bytes || !length) return false;
    IWICStream *stream = nullptr;
    if (FAILED(f->CreateStream(&stream))) return false;
    bool ok = false;
    if (SUCCEEDED(stream->InitializeFromMemory(const_cast<BYTE *>(bytes), length))) {
        IWICBitmapDecoder *decoder = nullptr;
        if (SUCCEEDED(f->CreateDecoderFromStream(stream, nullptr, WICDecodeMetadataCacheOnDemand, &decoder))) {
            IWICBitmapFrameDecode *frame = nullptr;
            if (SUCCEEDED(decoder->GetFrame(0, &frame))) {
                IWICFormatConverter *conv = nullptr;
                if (SUCCEEDED(f->CreateFormatConverter(&conv))) {
                    if (SUCCEEDED(conv->Initialize(frame, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone, nullptr, 0.0, WICBitmapPaletteTypeCustom))) {
                        UINT w = 0, h = 0;
                        conv->GetSize(&w, &h);
                        UINT st = w * 4;
                        uint8_t *buf = (uint8_t *)malloc((size_t)st * h);
                        if (buf && SUCCEEDED(conv->CopyPixels(nullptr, st, st * h, buf))) {
                            *width = w; *height = h; *stride = st; *pixels = buf;
                            ok = true;
                        } else if (buf) free(buf);
                    }
                    conv->Release();
                }
                frame->Release();
            }
            decoder->Release();
        }
    }
    stream->Release();
    return ok;
}

void cd2d_image_free(uint8_t *pixels) { free(pixels); }

bool cd2d_image_encode(const uint8_t *pixels, uint32_t width, uint32_t height, uint32_t stride, const char *format, float quality, uint8_t **bytes, uint32_t *length) {
    IWICImagingFactory *f = wicFactory();
    if (!f || !pixels) return false;
    GUID container = (format && strcmp(format, "jpeg") == 0) ? GUID_ContainerFormatJpeg : GUID_ContainerFormatPng;
    IStream *mem = SHCreateMemStream(nullptr, 0);
    if (!mem) return false;
    bool ok = false;
    IWICBitmapEncoder *encoder = nullptr;
    if (SUCCEEDED(f->CreateEncoder(container, nullptr, &encoder)) && SUCCEEDED(encoder->Initialize(mem, WICBitmapEncoderNoCache))) {
        IWICBitmapFrameEncode *frame = nullptr;
        IPropertyBag2 *props = nullptr;
        if (SUCCEEDED(encoder->CreateNewFrame(&frame, &props))) {
            if (props && container == GUID_ContainerFormatJpeg) {
                PROPBAG2 opt = {}; opt.pstrName = const_cast<LPOLESTR>(L"ImageQuality");
                VARIANT v; VariantInit(&v); v.vt = VT_R4; v.fltVal = quality;
                props->Write(1, &opt, &v);
            }
            if (SUCCEEDED(frame->Initialize(props))) {
                WICPixelFormatGUID fmt = GUID_WICPixelFormat32bppPBGRA;
                frame->SetSize(width, height);
                frame->SetPixelFormat(&fmt);
                if (SUCCEEDED(frame->WritePixels(height, stride, stride * height, const_cast<BYTE *>(pixels))) &&
                    SUCCEEDED(frame->Commit()) && SUCCEEDED(encoder->Commit())) {
                    STATSTG st = {};
                    if (SUCCEEDED(mem->Stat(&st, STATFLAG_NONAME))) {
                        uint32_t n = (uint32_t)st.cbSize.QuadPart;
                        uint8_t *out = (uint8_t *)malloc(n ? n : 1);
                        LARGE_INTEGER zero = {};
                        mem->Seek(zero, STREAM_SEEK_SET, nullptr);
                        ULONG read = 0;
                        if (out && SUCCEEDED(mem->Read(out, n, &read))) { *bytes = out; *length = read; ok = true; }
                        else if (out) free(out);
                    }
                }
            }
            if (props) props->Release();
            frame->Release();
        }
    }
    if (encoder) encoder->Release();
    mem->Release();
    return ok;
}

CD2DBitmap *cd2d_bitmap_create(CD2DTarget *t, uint32_t width, uint32_t height, uint32_t stride, const uint8_t *pixels) {
    if (!t || !t->target || !pixels) return nullptr;
    D2D1_BITMAP_PROPERTIES props = D2D1::BitmapProperties(D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
    ID2D1Bitmap *bm = nullptr;
    if (FAILED(t->target->CreateBitmap(D2D1::SizeU(width, height), pixels, stride, &props, &bm))) return nullptr;
    CD2DBitmap *r = new CD2DBitmap();
    r->bitmap = bm;
    return r;
}

void cd2d_bitmap_release(CD2DBitmap *b) {
    if (!b) return;
    safeRelease(b->bitmap);
    delete b;
}

void cd2d_target_draw_bitmap(CD2DTarget *t, CD2DBitmap *b, float dl, float dt, float dr, float db, float opacity, bool linear,
                             float sl, float st, float sr, float sb) {
    if (!t || !t->target || !b || !b->bitmap) return;
    D2D1_RECT_F dst = D2D1::RectF(dl, dt, dr, db);
    D2D1_RECT_F src = D2D1::RectF(sl, st, sr, sb);
    t->target->DrawBitmap(b->bitmap, dst, opacity, linear ? D2D1_BITMAP_INTERPOLATION_MODE_LINEAR : D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR, src);
}

CD2DOffscreen *cd2d_offscreen_create(CD2DFactory *factory, uint32_t w, uint32_t h, float dpi) {
    IWICImagingFactory *wf = wicFactory();
    if (!factory || !factory->factory || !wf) return nullptr;
    IWICBitmap *wic = nullptr;
    if (FAILED(wf->CreateBitmap(w ? w : 1, h ? h : 1, GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad, &wic))) return nullptr;
    D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_DEFAULT, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), dpi, dpi);
    ID2D1RenderTarget *rt = nullptr;
    if (FAILED(factory->factory->CreateWicBitmapRenderTarget(wic, &props, &rt))) { wic->Release(); return nullptr; }
    CD2DOffscreen *o = new CD2DOffscreen();
    o->wic = wic; o->rt = rt; o->width = w; o->height = h;
    o->target = new CD2DTarget();
    o->target->target = rt;
    return o;
}

CD2DTarget *cd2d_offscreen_target(CD2DOffscreen *o) { return o ? o->target : nullptr; }

uint32_t cd2d_offscreen_read(CD2DOffscreen *o, uint8_t *buffer, uint32_t size) {
    if (!o || !o->wic || !buffer) return 0;
    uint32_t stride = o->width * 4;
    if (size < stride * o->height) return 0;
    if (FAILED(o->wic->CopyPixels(nullptr, stride, size, buffer))) return 0;
    return stride;
}

void cd2d_offscreen_release(CD2DOffscreen *o) {
    if (!o) return;
    if (o->target) { o->target->target = nullptr; delete o->target; }
    safeRelease(o->rt);
    safeRelease(o->wic);
    delete o;
}

// ---------------------------------------------------------------- File dialogs

static std::vector<std::wstring> cd2d_split(const std::wstring &s, wchar_t sep) {
    std::vector<std::wstring> out;
    size_t start = 0;
    while (start <= s.size()) {
        size_t end = s.find(sep, start);
        if (end == std::wstring::npos) end = s.size();
        out.push_back(s.substr(start, end - start));
        start = end + 1;
    }
    return out;
}

bool cd2d_file_dialog(void *ownerHwnd, const CD2DFileDialogOptions *o, const uint16_t *title, const uint16_t *okLabel,
                      const uint16_t *defaultName, const uint16_t *directory, const uint16_t *extensions,
                      const uint16_t *labels, const uint16_t *defaultExtension, uint16_t **paths, uint32_t *length) {
    if (!o || !paths || !length) return false;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    IFileDialog *dlg = nullptr;
    HRESULT hr = o->isSave ? CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dlg))
                           : CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dlg));
    if (FAILED(hr) || !dlg) return false;
    FILEOPENDIALOGOPTIONS flags = 0;
    dlg->GetOptions(&flags);
    flags |= FOS_FORCEFILESYSTEM;
    if (!o->isSave) {
        if (o->allowsMultiple) flags |= FOS_ALLOWMULTISELECT;
        if (o->canChooseDirectories && !o->canChooseFiles) flags |= FOS_PICKFOLDERS;
        flags |= FOS_FILEMUSTEXIST;
    } else {
        flags |= FOS_OVERWRITEPROMPT;
    }
    if (o->showsHidden) flags |= FOS_FORCESHOWHIDDEN;
    dlg->SetOptions(flags);
    if (title && title[0]) dlg->SetTitle(reinterpret_cast<LPCWSTR>(title));
    if (okLabel && okLabel[0]) dlg->SetOkButtonLabel(reinterpret_cast<LPCWSTR>(okLabel));
    if (directory && directory[0]) {
        IShellItem *folder = nullptr;
        if (SUCCEEDED(SHCreateItemFromParsingName(reinterpret_cast<LPCWSTR>(directory), nullptr, IID_PPV_ARGS(&folder))) && folder) {
            dlg->SetFolder(folder);
            folder->Release();
        }
    }
    // One filter per group ("Plain Text Document (*.txt, *.text)"); names and patterns
    // are kept in vectors sized up front so the COMDLG_FILTERSPEC pointers stay valid.
    std::vector<std::wstring> names, patterns;
    std::vector<COMDLG_FILTERSPEC> filters;
    std::wstring defaultExt = defaultExtension ? std::wstring(reinterpret_cast<const wchar_t *>(defaultExtension)) : L"";
    size_t selectedIndex = 0;
    if (extensions && extensions[0]) {
        std::vector<std::wstring> groups = cd2d_split(reinterpret_cast<const wchar_t *>(extensions), L'|');
        std::vector<std::wstring> groupNames = labels ? cd2d_split(reinterpret_cast<const wchar_t *>(labels), L'|') : std::vector<std::wstring>();
        std::vector<std::wstring> groupFirst;
        std::wstring all;
        for (size_t g = 0; g < groups.size(); g++) {
            std::wstring pattern, first;
            for (const std::wstring &ext : cd2d_split(groups[g], L';')) {
                if (ext.empty()) continue;
                if (first.empty()) first = ext;
                if (!pattern.empty()) pattern += L";";
                pattern += L"*." + ext;
            }
            if (pattern.empty()) continue;
            std::wstring shown;
            for (wchar_t c : pattern) shown += c == L';' ? std::wstring(L", ") : std::wstring(1, c);
            std::wstring name = g < groupNames.size() && !groupNames[g].empty() ? groupNames[g] : L"Supported files";
            names.push_back(name + L" (" + shown + L")");
            patterns.push_back(pattern);
            groupFirst.push_back(first);
            if (!all.empty()) all += L";";
            all += pattern;
        }
        size_t typeOffset = 0;
        if (!o->isSave && patterns.size() > 1) {
            names.insert(names.begin(), L"All supported files");
            patterns.insert(patterns.begin(), all);
            typeOffset = 1;
        }
        if (o->allowsOtherTypes) { names.push_back(L"All files"); patterns.push_back(L"*.*"); }
        for (size_t i = 0; i < names.size(); i++) filters.push_back({ names[i].c_str(), patterns[i].c_str() });
        if (!filters.empty()) dlg->SetFileTypes((UINT)filters.size(), filters.data());
        // The group holding the default extension is shown first (an open dialog starts on
        // "All supported files"); the default extension completes a typed name.
        size_t selected = 0;
        if (!defaultExt.empty()) {
            std::wstring needle = L"*." + defaultExt;
            bool found = false;
            for (size_t i = 0; i < groupFirst.size() && !found; i++) {
                const std::wstring &pat = patterns[i + typeOffset];
                size_t at = pat.find(needle);
                while (at != std::wstring::npos && !found) {
                    size_t after = at + needle.size();
                    if (after == pat.size() || pat[after] == L';') { selected = i + typeOffset; found = true; }
                    at = pat.find(needle, after);
                }
            }
        } else if (!groupFirst.empty()) {
            defaultExt = groupFirst[0];
        }
        if (!filters.empty()) dlg->SetFileTypeIndex((UINT)selected + 1);
        selectedIndex = selected + 1;
        if (!defaultExt.empty()) dlg->SetDefaultExtension(defaultExt.c_str());
    }
    // The name goes in after the file types, the selected type and the default extension:
    // changing the type index afterwards makes the dialog re-derive the name from the new
    // filter, which drops the extension of a name set earlier.
    if (defaultName && defaultName[0]) dlg->SetFileName(reinterpret_cast<LPCWSTR>(defaultName));
    // APPKITWIN_FILE_DIALOG_TRACE=1: what the dialog was given, and whether Explorer hides
    // known extensions (HideFileExt), which also hides them in the dialog's name box: the
    // name box then shows "Untitled" for "Untitled.txt" while the saved file keeps ".txt".
    if (GetEnvironmentVariableW(L"APPKITWIN_FILE_DIALOG_TRACE", nullptr, 0) > 0) {
        DWORD hide = 0, size = sizeof(hide);
        if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced", L"HideFileExt", RRF_RT_REG_DWORD, nullptr, &hide, &size) != ERROR_SUCCESS) hide = 0xFFFFFFFF;
        fwprintf(stderr, L"[file-dialog] %ls name=\"%ls\" defaultExtension=\"%ls\" filters=%u selected=%u HideFileExt=%ld\n",
                 o->isSave ? L"save" : L"open", defaultName ? reinterpret_cast<const wchar_t *>(defaultName) : L"",
                 defaultExt.c_str(), (unsigned)filters.size(), (unsigned)selectedIndex, (long)hide);
        for (size_t i = 0; i < filters.size(); i++) fwprintf(stderr, L"[file-dialog]   %u: %ls = %ls\n", (unsigned)i + 1, filters[i].pszName, filters[i].pszSpec);
    }
    hr = dlg->Show((HWND)ownerHwnd);
    if (FAILED(hr)) { dlg->Release(); return false; }
    std::wstring joined;
    auto append = [&](IShellItem *item) {
        PWSTR path = nullptr;
        if (item && SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) && path) {
            joined += path;
            joined.push_back(L'\0');
            CoTaskMemFree(path);
        }
    };
    if (!o->isSave && o->allowsMultiple) {
        IFileOpenDialog *open = nullptr;
        if (SUCCEEDED(dlg->QueryInterface(IID_PPV_ARGS(&open))) && open) {
            IShellItemArray *items = nullptr;
            if (SUCCEEDED(open->GetResults(&items)) && items) {
                DWORD n = 0; items->GetCount(&n);
                for (DWORD i = 0; i < n; i++) { IShellItem *it = nullptr; if (SUCCEEDED(items->GetItemAt(i, &it)) && it) { append(it); it->Release(); } }
                items->Release();
            }
            open->Release();
        }
    } else {
        IShellItem *item = nullptr;
        if (SUCCEEDED(dlg->GetResult(&item)) && item) { append(item); item->Release(); }
    }
    dlg->Release();
    if (joined.empty()) return false;
    uint16_t *out = (uint16_t *)malloc((joined.size() + 1) * sizeof(uint16_t));
    if (!out) return false;
    memcpy(out, joined.data(), joined.size() * sizeof(uint16_t));
    out[joined.size()] = 0;
    *paths = out;
    *length = (uint32_t)joined.size();
    return true;
}

void cd2d_file_dialog_free(uint16_t *paths) { free(paths); }

// ---------------------------------------------------------------- Printing (ADR-0022)

static bool copyUTF16(const std::wstring &joined, uint16_t **out, uint32_t *length) {
    uint16_t *buf = (uint16_t *)malloc((joined.size() + 2) * sizeof(uint16_t));
    if (!buf) return false;
    memcpy(buf, joined.data(), joined.size() * sizeof(uint16_t));
    buf[joined.size()] = 0;
    buf[joined.size() + 1] = 0;
    *out = buf;
    *length = (uint32_t)joined.size();
    return true;
}

bool cd2d_printer_names(uint16_t **names, uint32_t *length) {
    if (!names || !length) return false;
    DWORD needed = 0, count = 0;
    EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 4, nullptr, 0, &needed, &count);
    if (needed == 0) return false;
    std::vector<BYTE> buffer(needed);
    if (!EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 4, buffer.data(), needed, &needed, &count)) return false;
    wchar_t defaultName[256] = {};
    DWORD defaultLength = 256;
    bool hasDefault = GetDefaultPrinterW(defaultName, &defaultLength) != 0;
    PRINTER_INFO_4W *info = reinterpret_cast<PRINTER_INFO_4W *>(buffer.data());
    std::wstring joined;
    if (hasDefault) { joined += defaultName; joined.push_back(L'\0'); }
    for (DWORD i = 0; i < count; i++) {
        if (!info[i].pPrinterName) continue;
        if (hasDefault && wcscmp(info[i].pPrinterName, defaultName) == 0) continue;
        joined += info[i].pPrinterName;
        joined.push_back(L'\0');
    }
    if (joined.empty()) return false;
    return copyUTF16(joined, names, length);
}

void cd2d_print_free(void *buffer) { free(buffer); }

bool cd2d_print_dialog(void *ownerHwnd, const uint16_t *printerName, CD2DPrintDialogSettings *s, uint16_t **chosenName, uint32_t *chosenLength) {
    if (!s) return false;
    s->driverSettings = nullptr;
    s->driverSettingsSize = 0;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    PRINTDLGEXW dlg = {};
    dlg.lStructSize = sizeof(dlg);
    dlg.hwndOwner = (HWND)ownerHwnd;
    if (!dlg.hwndOwner) dlg.hwndOwner = GetDesktopWindow();
    PRINTPAGERANGE range = { s->fromPage ? s->fromPage : 1, s->toPage ? s->toPage : (s->pageCount ? s->pageCount : 1) };
    dlg.lpPageRanges = &range;
    dlg.nMaxPageRanges = 1;
    dlg.nPageRanges = s->fromPage ? 1 : 0;
    dlg.nMinPage = 1;
    dlg.nMaxPage = s->pageCount ? s->pageCount : 1;
    dlg.nCopies = s->copies ? s->copies : 1;
    dlg.nStartPage = START_PAGE_GENERAL;
    dlg.Flags = PD_NOCURRENTPAGE | PD_NOSELECTION | (s->fromPage ? PD_PAGENUMS : PD_ALLPAGES) | (s->collate ? PD_COLLATE : 0);
    // Preselect the printer and orientation through DEVNAMES / DEVMODE.
    if (printerName && printerName[0]) {
        const wchar_t *name = reinterpret_cast<const wchar_t *>(printerName);
        size_t nameLength = wcslen(name);
        size_t bytes = sizeof(DEVNAMES) + (nameLength + 1 + 1 + 1) * sizeof(wchar_t);
        dlg.hDevNames = GlobalAlloc(GHND, bytes);
        if (dlg.hDevNames) {
            DEVNAMES *dn = (DEVNAMES *)GlobalLock(dlg.hDevNames);
            wchar_t *strings = reinterpret_cast<wchar_t *>(dn + 1);
            dn->wDriverOffset = (WORD)(sizeof(DEVNAMES) / sizeof(wchar_t));
            strings[0] = 0;
            dn->wDeviceOffset = (WORD)(dn->wDriverOffset + 1);
            wcscpy(strings + 1, name);
            dn->wOutputOffset = (WORD)(dn->wDeviceOffset + nameLength + 1);
            strings[1 + nameLength + 1] = 0;
            dn->wDefault = 0;
            GlobalUnlock(dlg.hDevNames);
        }
        HANDLE printer = nullptr;
        if (OpenPrinterW(const_cast<wchar_t *>(name), &printer, nullptr)) {
            LONG size = DocumentPropertiesW(dlg.hwndOwner, printer, const_cast<wchar_t *>(name), nullptr, nullptr, 0);
            if (size > 0) {
                dlg.hDevMode = GlobalAlloc(GHND, size);
                if (dlg.hDevMode) {
                    DEVMODEW *dm = (DEVMODEW *)GlobalLock(dlg.hDevMode);
                    if (DocumentPropertiesW(dlg.hwndOwner, printer, const_cast<wchar_t *>(name), dm, nullptr, DM_OUT_BUFFER) == IDOK) {
                        dm->dmFields |= DM_ORIENTATION;
                        dm->dmOrientation = s->landscape ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT;
                    }
                    GlobalUnlock(dlg.hDevMode);
                }
            }
            ClosePrinter(printer);
        }
    }
    HRESULT hr = PrintDlgExW(&dlg);
    bool printed = SUCCEEDED(hr) && dlg.dwResultAction == PD_RESULT_PRINT;
    if (printed) {
        s->copies = dlg.nCopies ? dlg.nCopies : 1;
        s->collate = (dlg.Flags & PD_COLLATE) != 0;
        if ((dlg.Flags & PD_PAGENUMS) && dlg.nPageRanges > 0) { s->fromPage = range.nFromPage; s->toPage = range.nToPage; }
        else { s->fromPage = 0; s->toPage = 0; }
        s->printToFile = (dlg.Flags & PD_PRINTTOFILE) != 0;
        if (dlg.hDevMode) {
            DEVMODEW *dm = (DEVMODEW *)GlobalLock(dlg.hDevMode);
            if (dm) {
                // The whole DEVMODE goes back to the caller for the job's print ticket.
                uint32_t size = dm->dmSize + dm->dmDriverExtra;
                if (size > 0 && size <= (uint32_t)GlobalSize(dlg.hDevMode)) {
                    s->driverSettings = malloc(size);
                    if (s->driverSettings) { memcpy(s->driverSettings, dm, size); s->driverSettingsSize = size; }
                }
                if (dm->dmFields & DM_ORIENTATION) s->landscape = dm->dmOrientation == DMORIENT_LANDSCAPE;
                if (dm->dmFields & DM_COPIES) s->copies = dm->dmCopies > 0 ? dm->dmCopies : s->copies;
                if ((dm->dmFields & DM_PAPERWIDTH) && (dm->dmFields & DM_PAPERLENGTH) && dm->dmPaperWidth > 0 && dm->dmPaperLength > 0) {
                    s->paperWidth = dm->dmPaperWidth / 10.0f * 72.0f / 25.4f;      // tenths of a millimetre to points
                    s->paperHeight = dm->dmPaperLength / 10.0f * 72.0f / 25.4f;
                } else if (dlg.hDevNames) {
                    // The paper size by its DEVMODE paper code, from the driver's table.
                    DEVNAMES *dn = (DEVNAMES *)GlobalLock(dlg.hDevNames);
                    if (dn) {
                        const wchar_t *device = reinterpret_cast<const wchar_t *>(dn) + dn->wDeviceOffset;
                        const wchar_t *port = reinterpret_cast<const wchar_t *>(dn) + dn->wOutputOffset;
                        DWORD n = DeviceCapabilitiesW(device, port, DC_PAPERS, nullptr, nullptr);
                        if (n > 0 && n < 4096) {
                            std::vector<WORD> codes(n);
                            std::vector<POINT> sizes(n);
                            DeviceCapabilitiesW(device, port, DC_PAPERS, reinterpret_cast<LPWSTR>(codes.data()), nullptr);
                            DeviceCapabilitiesW(device, port, DC_PAPERSIZE, reinterpret_cast<LPWSTR>(sizes.data()), nullptr);
                            for (DWORD i = 0; i < n; i++) {
                                if (codes[i] == dm->dmPaperSize && sizes[i].x > 0 && sizes[i].y > 0) {
                                    s->paperWidth = sizes[i].x / 10.0f * 72.0f / 25.4f;
                                    s->paperHeight = sizes[i].y / 10.0f * 72.0f / 25.4f;
                                    break;
                                }
                            }
                        }
                        GlobalUnlock(dlg.hDevNames);
                    }
                }
                GlobalUnlock(dlg.hDevMode);
            }
        }
        if (dlg.hDevNames && chosenName && chosenLength) {
            DEVNAMES *dn = (DEVNAMES *)GlobalLock(dlg.hDevNames);
            if (dn) {
                std::wstring device(reinterpret_cast<const wchar_t *>(dn) + dn->wDeviceOffset);
                copyUTF16(device, chosenName, chosenLength);
                GlobalUnlock(dlg.hDevNames);
            }
        }
    }
    if (dlg.hDevMode) GlobalFree(dlg.hDevMode);
    if (dlg.hDevNames) GlobalFree(dlg.hDevNames);
    if (dlg.hDC) DeleteDC(dlg.hDC);
    return printed;
}

struct CD2DPrintJob {
    ID3D11Device *d3dDevice = nullptr;
    ID3D11DeviceContext *d3dContext = nullptr;
    ID2D1Device *d2dDevice = nullptr;
    ID2D1DeviceContext *dc = nullptr;
    IPrintDocumentPackageTarget *target = nullptr;
    ID2D1PrintControl *printControl = nullptr;
    ID2D1CommandList *commandList = nullptr;
    float pageWidth = 0, pageHeight = 0;
    bool pageOpen = false;
};

static void releasePrintJob(CD2DPrintJob *job) {
    if (!job) return;
    safeRelease(job->commandList);
    safeRelease(job->printControl);
    safeRelease(job->target);
    safeRelease(job->dc);
    safeRelease(job->d2dDevice);
    safeRelease(job->d3dContext);
    safeRelease(job->d3dDevice);
    delete job;
}

/// A print ticket (IStream of the PrintTicket XML) from a DEVMODE through the print
/// ticket provider; NULL when the driver cannot convert it (the job then uses the
/// printer's defaults).
static IStream *printTicketFromDevMode(const wchar_t *printer, const void *devMode, uint32_t size) {
    if (!devMode || size < sizeof(DEVMODEW)) return nullptr;
    HPTPROVIDER provider = nullptr;
    if (FAILED(PTOpenProvider(printer, 1, &provider)) || !provider) return nullptr;
    IStream *stream = nullptr;
    if (SUCCEEDED(CreateStreamOnHGlobal(nullptr, TRUE, &stream)) && stream) {
        HRESULT hr = PTConvertDevModeToPrintTicket(provider, size, (PDEVMODE)const_cast<void *>(devMode), kPTJobScope, stream);
        LARGE_INTEGER zero = {};
        if (FAILED(hr) || FAILED(stream->Seek(zero, STREAM_SEEK_SET, nullptr))) { stream->Release(); stream = nullptr; }
    }
    PTCloseProvider(provider);
    return stream;
}

CD2DPrintJob *cd2d_print_job_create(CD2DFactory *factory, const uint16_t *printerName, const uint16_t *jobName, const void *driverSettings, uint32_t driverSettingsSize) {
    if (!factory || !factory->factory) return nullptr;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    wchar_t defaultName[256] = {};
    DWORD defaultLength = 256;
    const wchar_t *printer = reinterpret_cast<const wchar_t *>(printerName);
    if (!printer || !printer[0]) {
        if (!GetDefaultPrinterW(defaultName, &defaultLength)) return nullptr;
        printer = defaultName;
    }
    const wchar_t *job = jobName && jobName[0] ? reinterpret_cast<const wchar_t *>(jobName) : L"Untitled";
    ID2D1Factory1 *factory1 = nullptr;
    if (FAILED(factory->factory->QueryInterface(__uuidof(ID2D1Factory1), reinterpret_cast<void **>(&factory1)))) return nullptr;
    CD2DPrintJob *j = new CD2DPrintJob();
    IPrintDocumentPackageTargetFactory *targetFactory = nullptr;
    IDXGIDevice *dxgiDevice = nullptr;
    IStream *ticket = printTicketFromDevMode(printer, driverSettings, driverSettingsSize);
    bool ok = false;
    do {
        if (FAILED(CoCreateInstance(__uuidof(PrintDocumentPackageTargetFactory), nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&targetFactory))) || !targetFactory) break;
        if (FAILED(targetFactory->CreateDocumentPackageTargetForPrintJob(printer, job, nullptr, ticket, &j->target)) || !j->target) break;
        if (FAILED(createD3DDevice(&j->d3dDevice, &j->d3dContext))) break;
        if (FAILED(j->d3dDevice->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void **>(&dxgiDevice)))) break;
        if (FAILED(factory1->CreateDevice(dxgiDevice, &j->d2dDevice))) break;
        if (FAILED(j->d2dDevice->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &j->dc))) break;
        D2D1_PRINT_CONTROL_PROPERTIES props = {};
        props.fontSubset = D2D1_PRINT_FONT_SUBSET_MODE_DEFAULT;
        props.rasterDPI = 300.0f;
        props.colorSpace = D2D1_COLOR_SPACE_SRGB;
        IWICImagingFactory *wic = wicFactory();
        if (!wic) break;
        if (FAILED(j->d2dDevice->CreatePrintControl(wic, j->target, &props, &j->printControl))) break;
        ok = true;
    } while (false);
    safeRelease(dxgiDevice);
    safeRelease(targetFactory);
    safeRelease(factory1);
    safeRelease(ticket);
    if (!ok) { releasePrintJob(j); return nullptr; }
    return j;
}

CD2DTarget *cd2d_print_job_begin_page(CD2DPrintJob *job, float widthDips, float heightDips) {
    if (!job || !job->dc || job->pageOpen) return nullptr;
    safeRelease(job->commandList);
    if (FAILED(job->dc->CreateCommandList(&job->commandList))) return nullptr;
    job->dc->SetTarget(job->commandList);
    job->dc->SetDpi(96, 96);
    job->dc->BeginDraw();
    job->dc->SetTransform(D2D1::Matrix3x2F::Identity());
    job->pageWidth = widthDips;
    job->pageHeight = heightDips;
    job->pageOpen = true;
    CD2DTarget *t = new CD2DTarget();
    t->target = job->dc;
    job->dc->AddRef();
    t->dpi = 96;
    return t;
}

bool cd2d_print_job_end_page(CD2DPrintJob *job) {
    if (!job || !job->dc || !job->pageOpen) return false;
    job->pageOpen = false;
    HRESULT hr = job->dc->EndDraw();
    job->dc->SetTarget(nullptr);
    bool ok = SUCCEEDED(hr);
    if (job->commandList) {
        if (FAILED(job->commandList->Close())) ok = false;
        if (ok && job->printControl && FAILED(job->printControl->AddPage(job->commandList, D2D1::SizeF(job->pageWidth, job->pageHeight), nullptr))) ok = false;
        safeRelease(job->commandList);
    }
    return ok;
}

bool cd2d_print_job_close(CD2DPrintJob *job) {
    if (!job) return false;
    bool ok = job->printControl && SUCCEEDED(job->printControl->Close());
    releasePrintJob(job);
    return ok;
}

void cd2d_print_job_abort(CD2DPrintJob *job) {
    if (!job) return;
    if (job->pageOpen && job->dc) { job->dc->EndDraw(); job->dc->SetTarget(nullptr); }
    if (job->target) job->target->Cancel();
    releasePrintJob(job);
}

// ---------------------------------------------------------------- Colour dialog

bool cd2d_choose_color(void *ownerHwnd, uint32_t *rgb) {
    if (!rgb) return false;
    static COLORREF custom[16] = { 0 };
    CHOOSECOLORW cc;
    ZeroMemory(&cc, sizeof(cc));
    cc.lStructSize = sizeof(cc);
    cc.hwndOwner = static_cast<HWND>(ownerHwnd);
    cc.rgbResult = *rgb;
    cc.lpCustColors = custom;
    cc.Flags = CC_RGBINIT | CC_FULLOPEN | CC_ANYCOLOR;
    if (!ChooseColorW(&cc)) return false;
    *rgb = cc.rgbResult;
    return true;
}

// ---------------------------------------------------------------- DirectWrite

struct CD2DTextFormat { IDWriteTextFormat *format = nullptr; };
struct CD2DTextLayout { IDWriteTextLayout *layout = nullptr; };

static IDWriteFactory *dwriteFactory() {
    static IDWriteFactory *f = nullptr;
    if (!f) DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(&f));
    return f;
}

CD2DTextFormat *cd2d_text_format_create(const uint16_t *family, float size, int32_t weight, bool italic) {
    IDWriteFactory *f = dwriteFactory();
    if (!f || !family) return nullptr;
    IDWriteTextFormat *fmt = nullptr;
    HRESULT hr = f->CreateTextFormat(reinterpret_cast<const WCHAR *>(family), nullptr,
                                     static_cast<DWRITE_FONT_WEIGHT>(weight),
                                     italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL,
                                     DWRITE_FONT_STRETCH_NORMAL, size, L"", &fmt);
    if (FAILED(hr)) return nullptr;
    fmt->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    CD2DTextFormat *r = new CD2DTextFormat();
    r->format = fmt;
    return r;
}

void cd2d_text_format_release(CD2DTextFormat *format) {
    if (!format) return;
    safeRelease(format->format);
    delete format;
}

bool cd2d_text_format_metrics(CD2DTextFormat *format, float *ascent, float *descent, float *lineGap, float *capHeight, float *xHeight) {
    if (!format || !format->format) return false;
    IDWriteFontCollection *collection = nullptr;
    if (FAILED(format->format->GetFontCollection(&collection)) || !collection) return false;
    WCHAR family[256];
    format->format->GetFontFamilyName(family, 256);
    UINT32 index = 0; BOOL exists = FALSE;
    collection->FindFamilyName(family, &index, &exists);
    bool ok = false;
    if (exists) {
        IDWriteFontFamily *fam = nullptr;
        if (SUCCEEDED(collection->GetFontFamily(index, &fam)) && fam) {
            IDWriteFont *font = nullptr;
            if (SUCCEEDED(fam->GetFirstMatchingFont(format->format->GetFontWeight(), format->format->GetFontStretch(), format->format->GetFontStyle(), &font)) && font) {
                DWRITE_FONT_METRICS m;
                font->GetMetrics(&m);
                float scale = format->format->GetFontSize() / (float)m.designUnitsPerEm;
                *ascent = m.ascent * scale;
                *descent = m.descent * scale;
                *lineGap = m.lineGap * scale;
                *capHeight = m.capHeight * scale;
                *xHeight = m.xHeight * scale;
                ok = true;
                font->Release();
            }
            fam->Release();
        }
    }
    collection->Release();
    return ok;
}

CD2DTextLayout *cd2d_text_layout_create(CD2DTextFormat *format, const uint16_t *text, uint32_t length, float maxWidth, float maxHeight, bool wrap) {
    IDWriteFactory *f = dwriteFactory();
    if (!f || !format || !format->format) return nullptr;
    IDWriteTextLayout *layout = nullptr;
    if (FAILED(f->CreateTextLayout(reinterpret_cast<const WCHAR *>(text), length, format->format, maxWidth, maxHeight, &layout))) return nullptr;
    layout->SetWordWrapping(wrap ? DWRITE_WORD_WRAPPING_WRAP : DWRITE_WORD_WRAPPING_NO_WRAP);
    CD2DTextLayout *r = new CD2DTextLayout();
    r->layout = layout;
    return r;
}

void cd2d_text_layout_metrics(CD2DTextLayout *layout, float *width, float *height, float *baseline) {
    if (!layout || !layout->layout) return;
    DWRITE_TEXT_METRICS m;
    layout->layout->GetMetrics(&m);
    *width = m.widthIncludingTrailingWhitespace;
    *height = m.height;
    DWRITE_LINE_METRICS lm; UINT32 n = 0;
    layout->layout->GetLineMetrics(&lm, 1, &n);
    *baseline = n ? lm.baseline : 0;
}

void cd2d_text_layout_release(CD2DTextLayout *layout) {
    if (!layout) return;
    safeRelease(layout->layout);
    delete layout;
}

void cd2d_target_draw_text_layout(CD2DTarget *t, CD2DTextLayout *layout, float x, float y, CD2DBrush *b) {
    if (t && t->target && layout && layout->layout && b && b->brush)
        t->target->DrawTextLayout(D2D1::Point2F(x, y), layout->layout, b->brush, D2D1_DRAW_TEXT_OPTIONS_NONE);
}

}  // extern "C"

// ---------------------------------------------------------------- DirectComposition tree (M9)

struct CD2DCompVisual {
    IDCompositionVisual *visual = nullptr;         // the v1 interface carries everything but opacity
    IDCompositionVisual3 *visual3 = nullptr;       // SetOpacity (Windows 8.1+); null → effect group
    IDCompositionEffectGroup *effect = nullptr;
    IDCompositionRectangleClip *clip = nullptr;
    IDCompositionMatrixTransform3D *transform3D = nullptr;   // on the effect group while a node is 3D
    IDCompositionSurface *surface = nullptr;
    uint32_t surfaceWidth = 0, surfaceHeight = 0;
    IUnknown *swapChain = nullptr;                 // foreign content (cd2d_comp_tree_set_swapchain), retained
    bool seen = false;                             // ensured in the current update
    int64_t attachedTo = -1;                       // parent id it is added under (0: root, -1: none)
    std::vector<int64_t> children, newChildren;    // ids, back to front
};

struct CD2DCompTree {
    CD2DTarget *target = nullptr;                  // not owned; outlives the tree
    IDCompositionDevice *device = nullptr;
    IDCompositionVisual *root = nullptr;           // container under the swap-chain visual
    std::vector<int64_t> rootChildren, newRootChildren;
    std::unordered_map<int64_t, CD2DCompVisual *> visuals;
    bool updating = false;
    // Surface drawing: one device context on the target's D2D device, retargeted at the
    // surface being drawn; `surfaceTarget` is the handle Swift wraps in a CGContext.
    ID2D1DeviceContext *dc = nullptr;
    ID2D1Bitmap1 *surfaceBitmap = nullptr;
    IDXGISurface *surfaceDxgi = nullptr;
    CD2DTarget surfaceTarget;
    int64_t drawing = 0;                           // id of the surface between begin/end draw
    uint32_t addFailures = 0, contentFailures = 0; // failed AddVisual / SetContent calls (trace aid)
    int32_t lastDrawStage = 0, lastDrawError = 0;  // why the last surface_begin_draw failed
    void *lastSurface = nullptr;                   // the last surface drawn and its atlas offset (trace aid)
    int32_t lastOffsetX = 0, lastOffsetY = 0;
    bool lastSurfaceCreated = false;
    int32_t lastSurfaceRefs = 0;                   // the surface's reference count after the draw began
};

static CD2DCompVisual *compVisual(CD2DCompTree *tree, int64_t id) {
    if (!tree) return nullptr;
    auto it = tree->visuals.find(id);
    return it == tree->visuals.end() ? nullptr : it->second;
}

/// The children `ids` are no longer under any visual (their parent was emptied or destroyed).
static void compDetachedChildren(CD2DCompTree *tree, const std::vector<int64_t> &ids) {
    for (int64_t id : ids) {
        auto it = tree->visuals.find(id);
        if (it != tree->visuals.end()) it->second->attachedTo = -1;
    }
}

static void compDestroyVisual(CD2DCompTree *tree, CD2DCompVisual *v) {
    compDetachedChildren(tree, v->children);
    if (v->visual) {
        v->visual->RemoveAllVisuals();
        v->visual->SetContent(nullptr);
        v->visual->SetClip(static_cast<IDCompositionClip *>(nullptr));
        v->visual->SetEffect(nullptr);
    }
    safeRelease(v->surface);
    safeRelease(v->swapChain);
    safeRelease(v->clip);
    safeRelease(v->transform3D);
    safeRelease(v->effect);
    safeRelease(v->visual3);
    safeRelease(v->visual);
    delete v;
}

/// Re-adds `children` under `parent` (id `parentId`, 0 for the root) in order, each above the
/// previous one. A visual still added under another parent is taken off it first: AddVisual
/// fails for a visual that has a parent, and the child would silently stay out of the tree.
static void compPlaceChildren(CD2DCompTree *tree, int64_t parentId, IDCompositionVisual *parent, const std::vector<int64_t> &children) {
    IDCompositionVisual *previous = nullptr;
    for (int64_t id : children) {
        CD2DCompVisual *c = compVisual(tree, id);
        if (!c || !c->visual) continue;
        if (c->attachedTo != -1 && c->attachedTo != parentId) {
            IDCompositionVisual *old = nullptr;
            if (c->attachedTo == 0) old = tree->root;
            else if (CD2DCompVisual *o = compVisual(tree, c->attachedTo)) old = o->visual;
            if (old) old->RemoveVisual(c->visual);
            c->attachedTo = -1;
        }
        if (SUCCEEDED(parent->AddVisual(c->visual, TRUE, previous))) {
            c->attachedTo = parentId;
            previous = c->visual;
        } else {
            tree->addFailures++;
        }
    }
}

extern "C" {

CD2DCompTree *cd2d_comp_tree_create(CD2DTarget *target) {
    if (!target || !target->dcompDevice || !target->dcompVisual || !target->d2dDevice) return nullptr;
    CD2DCompTree *t = new CD2DCompTree();
    t->target = target;
    t->device = target->dcompDevice;
    t->device->AddRef();
    bool ok = false;
    do {
        if (FAILED(t->device->CreateVisual(&t->root))) break;
        if (FAILED(target->dcompVisual->AddVisual(t->root, TRUE, nullptr))) break;
        if (FAILED(target->d2dDevice->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &t->dc))) break;
        // Match the window target: grayscale text on premultiplied surfaces.
        t->dc->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
        t->surfaceTarget.target = t->dc;
        t->surfaceTarget.alphaMode = D2D1_ALPHA_MODE_PREMULTIPLIED;
        ok = true;
    } while (false);
    if (!ok) { cd2d_comp_tree_release(t); return nullptr; }
    return t;
}

void cd2d_comp_tree_release(CD2DCompTree *tree) {
    if (!tree) return;
    if (tree->drawing) cd2d_comp_tree_surface_end_draw(tree, tree->drawing);
    // Out of the map first: destroying one visual updates its children's records.
    std::vector<CD2DCompVisual *> all;
    for (auto &entry : tree->visuals) all.push_back(entry.second);
    tree->visuals.clear();
    for (CD2DCompVisual *v : all) compDestroyVisual(tree, v);
    if (tree->root) {
        tree->root->RemoveAllVisuals();
        if (tree->target && tree->target->dcompVisual) tree->target->dcompVisual->RemoveVisual(tree->root);
    }
    if (tree->device) tree->device->Commit();
    safeRelease(tree->root);
    tree->surfaceTarget.target = nullptr;
    safeRelease(tree->dc);
    safeRelease(tree->device);
    delete tree;
}

void cd2d_comp_tree_begin_update(CD2DCompTree *tree) {
    if (!tree) return;
    tree->updating = true;
    tree->newRootChildren.clear();
    for (auto &entry : tree->visuals) { entry.second->seen = false; entry.second->newChildren.clear(); }
}

bool cd2d_comp_tree_ensure_visual(CD2DCompTree *tree, int64_t id, int64_t parentId) {
    if (!tree || !tree->root || id == 0) return false;
    CD2DCompVisual *v = compVisual(tree, id);
    if (!v) {
        v = new CD2DCompVisual();
        if (FAILED(tree->device->CreateVisual(&v->visual))) { delete v; return false; }
        v->visual->QueryInterface(__uuidof(IDCompositionVisual3), reinterpret_cast<void **>(&v->visual3));
        // Surfaces land at fractional pixel offsets under animating transforms: filter them
        // and soften their edges, as the software compositor's bitmap draw does.
        v->visual->SetBitmapInterpolationMode(DCOMPOSITION_BITMAP_INTERPOLATION_MODE_LINEAR);
        v->visual->SetBorderMode(DCOMPOSITION_BORDER_MODE_SOFT);
        tree->visuals[id] = v;
    }
    v->seen = true;
    if (parentId == 0) {
        tree->newRootChildren.push_back(id);
    } else {
        CD2DCompVisual *p = compVisual(tree, parentId);
        if (!p || !p->seen) return false;
        p->newChildren.push_back(id);
    }
    return true;
}

void cd2d_comp_tree_set_transform(CD2DCompTree *tree, int64_t id, float m11, float m12, float m21, float m22, float dx, float dy) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (v && v->visual) v->visual->SetTransform(D2D1::Matrix3x2F(m11, m12, m21, m22, dx, dy));
}

void cd2d_gestures_enable(void *hwnd) {
    GESTURECONFIG config = {0, GC_ALLGESTURES, 0};
    SetGestureConfig((HWND)hwnd, 0, 1, &config, sizeof(GESTURECONFIG));
}

bool cd2d_gesture_decode(intptr_t lParam, CD2DGesture *out) {
    GESTUREINFO gi = {};
    gi.cbSize = sizeof(GESTUREINFO);
    HGESTUREINFO handle = (HGESTUREINFO)lParam;
    BOOL ok = GetGestureInfo(handle, &gi);
    if (ok && out) {
        out->id = gi.dwID;
        out->begin = (gi.dwFlags & GF_BEGIN) != 0;
        out->end = (gi.dwFlags & GF_END) != 0;
        out->inertia = (gi.dwFlags & GF_INERTIA) != 0;
        out->x = gi.ptsLocation.x;
        out->y = gi.ptsLocation.y;
        out->argument = gi.ullArguments;
        out->angle = gi.dwID == GID_ROTATE ? GID_ROTATE_ANGLE_FROM_ARGUMENT(LODWORD(gi.ullArguments)) : 0.0;
    }
    CloseGestureInfoHandle(handle);
    return ok != FALSE;
}

void cd2d_comp_tree_set_transform3d(CD2DCompTree *tree, int64_t id, const float *m) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (!v || !v->visual) return;
    if (!m) {
        if (v->transform3D) {
            if (v->effect) v->effect->SetTransform3D(static_cast<IDCompositionTransform3D *>(nullptr));
            safeRelease(v->transform3D);
        }
        return;
    }
    if (!v->effect) {
        if (FAILED(tree->device->CreateEffectGroup(&v->effect))) return;
        v->visual->SetEffect(v->effect);
    }
    if (!v->transform3D) {
        if (FAILED(tree->device->CreateMatrixTransform3D(&v->transform3D))) return;
        v->effect->SetTransform3D(v->transform3D);
    }
    D3DMATRIX mat;
    mat._11 = m[0];  mat._12 = m[1];  mat._13 = m[2];  mat._14 = m[3];
    mat._21 = m[4];  mat._22 = m[5];  mat._23 = m[6];  mat._24 = m[7];
    mat._31 = m[8];  mat._32 = m[9];  mat._33 = m[10]; mat._34 = m[11];
    mat._41 = m[12]; mat._42 = m[13]; mat._43 = m[14]; mat._44 = m[15];
    v->transform3D->SetMatrix(mat);
}

void cd2d_comp_tree_set_opacity(CD2DCompTree *tree, int64_t id, float opacity) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (!v || !v->visual) return;
    if (opacity < 0) opacity = 0;
    if (opacity > 1) opacity = 1;
    if (v->visual3) { v->visual3->SetOpacity(opacity); return; }
    if (!v->effect) {
        if (FAILED(tree->device->CreateEffectGroup(&v->effect))) return;
        v->visual->SetEffect(v->effect);
    }
    v->effect->SetOpacity(opacity);
}

void cd2d_comp_tree_set_clip(CD2DCompTree *tree, int64_t id, bool enabled, float left, float top, float right, float bottom,
                             float rtl, float rtr, float rbl, float rbr) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (!v || !v->visual) return;
    if (!enabled) {
        if (v->clip) { v->visual->SetClip(static_cast<IDCompositionClip *>(nullptr)); safeRelease(v->clip); }
        return;
    }
    if (!v->clip) {
        if (FAILED(tree->device->CreateRectangleClip(&v->clip))) return;
        v->visual->SetClip(v->clip);
    }
    v->clip->SetLeft(left); v->clip->SetTop(top); v->clip->SetRight(right); v->clip->SetBottom(bottom);
    v->clip->SetTopLeftRadiusX(rtl); v->clip->SetTopLeftRadiusY(rtl);
    v->clip->SetTopRightRadiusX(rtr); v->clip->SetTopRightRadiusY(rtr);
    v->clip->SetBottomLeftRadiusX(rbl); v->clip->SetBottomLeftRadiusY(rbl);
    v->clip->SetBottomRightRadiusX(rbr); v->clip->SetBottomRightRadiusY(rbr);
}

CD2DTarget *cd2d_comp_tree_surface_begin_draw(CD2DCompTree *tree, int64_t id, uint32_t w, uint32_t h, float dpi) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (!tree) return nullptr;
    tree->lastDrawStage = 0; tree->lastDrawError = 0;
    if (!v || !v->visual || !tree->dc || tree->drawing) { tree->lastDrawStage = 1; return nullptr; }
    if (!w) w = 1;
    if (!h) h = 1;
    if (v->swapChain) {
        // The node draws again: its swap chain gives way to a surface.
        v->visual->SetContent(nullptr);
        safeRelease(v->swapChain);
    }
    if (v->surface && (v->surfaceWidth != w || v->surfaceHeight != h)) {
        v->visual->SetContent(nullptr);
        safeRelease(v->surface);
    }
    tree->lastSurfaceCreated = !v->surface;
    if (!v->surface) {
        HRESULT hr = tree->device->CreateSurface(w, h, DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_ALPHA_MODE_PREMULTIPLIED, &v->surface);
        if (FAILED(hr)) { v->surface = nullptr; tree->lastDrawStage = 2; tree->lastDrawError = (int32_t)hr; return nullptr; }
        v->surfaceWidth = w; v->surfaceHeight = h;
        if (FAILED(v->visual->SetContent(v->surface))) tree->contentFailures++;
    }
    POINT offset = {};
    HRESULT beginHr = v->surface->BeginDraw(nullptr, __uuidof(IDXGISurface), reinterpret_cast<void **>(&tree->surfaceDxgi), &offset);
    if (FAILED(beginHr)) {
        tree->surfaceDxgi = nullptr;
        tree->lastDrawStage = 3; tree->lastDrawError = (int32_t)beginHr;
        return nullptr;
    }
    D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), dpi, dpi);
    HRESULT bitmapHr = tree->dc->CreateBitmapFromDxgiSurface(tree->surfaceDxgi, &props, &tree->surfaceBitmap);
    if (FAILED(bitmapHr)) {
        safeRelease(tree->surfaceDxgi);
        v->surface->EndDraw();
        tree->lastDrawStage = 4; tree->lastDrawError = (int32_t)bitmapHr;
        return nullptr;
    }
    tree->drawing = id;
    tree->lastSurface = v->surface;
    v->surface->AddRef();
    tree->lastSurfaceRefs = (int32_t)v->surface->Release();
    tree->lastOffsetX = offset.x; tree->lastOffsetY = offset.y;
    tree->dc->SetTarget(tree->surfaceBitmap);
    tree->dc->SetDpi(dpi, dpi);
    tree->dc->BeginDraw();
    // The region is a rectangle of an atlas: keep every drawing call (and the clear) inside
    // it. The clip is pushed in DIPs under the identity transform; the origin shifts every
    // transform the caller sets afterwards.
    float scale = dpi / 96.0f;
    float ox = offset.x / scale, oy = offset.y / scale;
    tree->surfaceTarget.dpi = dpi;
    tree->surfaceTarget.originX = ox;
    tree->surfaceTarget.originY = oy;
    tree->dc->SetTransform(D2D1::Matrix3x2F::Identity());
    tree->dc->PushAxisAlignedClip(D2D1::RectF(ox, oy, ox + w / scale, oy + h / scale), D2D1_ANTIALIAS_MODE_ALIASED);
    tree->dc->Clear(D2D1::ColorF(0, 0, 0, 0));
    return &tree->surfaceTarget;
}

void cd2d_comp_tree_surface_end_draw(CD2DCompTree *tree, int64_t id) {
    if (!tree || !tree->drawing || tree->drawing != id) return;
    CD2DCompVisual *v = compVisual(tree, id);
    tree->dc->PopAxisAlignedClip();
    tree->dc->EndDraw();
    tree->dc->SetTarget(nullptr);
    safeRelease(tree->surfaceBitmap);
    safeRelease(tree->surfaceDxgi);
    if (v && v->surface) v->surface->EndDraw();
    tree->surfaceTarget.originX = tree->surfaceTarget.originY = 0;
    tree->drawing = 0;
}

bool cd2d_comp_tree_set_swapchain(CD2DCompTree *tree, int64_t id, void *dxgiSwapChain) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (!v || !v->visual) return false;
    IUnknown *content = static_cast<IUnknown *>(dxgiSwapChain);
    if (content == v->swapChain) return true;
    if (tree->drawing == id) cd2d_comp_tree_surface_end_draw(tree, id);
    safeRelease(v->surface);
    v->surfaceWidth = v->surfaceHeight = 0;
    safeRelease(v->swapChain);
    if (content) {
        content->AddRef();
        v->swapChain = content;
        // A swap chain is shown pixel for pixel at the visual's origin: no filtering.
        v->visual->SetBitmapInterpolationMode(DCOMPOSITION_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
    } else {
        v->visual->SetBitmapInterpolationMode(DCOMPOSITION_BITMAP_INTERPOLATION_MODE_LINEAR);
    }
    return SUCCEEDED(v->visual->SetContent(content));
}

void cd2d_comp_tree_remove_surface(CD2DCompTree *tree, int64_t id) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (!v || !v->surface || tree->drawing == id) return;
    v->visual->SetContent(nullptr);
    safeRelease(v->surface);
    v->surfaceWidth = v->surfaceHeight = 0;
}

void cd2d_comp_tree_remove_visual(CD2DCompTree *tree, int64_t id) {
    CD2DCompVisual *v = compVisual(tree, id);
    if (!v) return;
    if (tree->drawing == id) cd2d_comp_tree_surface_end_draw(tree, id);
    // Detach from whichever parent lists it.
    for (auto &entry : tree->visuals) {
        auto &c = entry.second->children;
        auto it = std::find(c.begin(), c.end(), id);
        if (it != c.end()) { c.erase(it); entry.second->visual->RemoveVisual(v->visual); break; }
    }
    auto rit = std::find(tree->rootChildren.begin(), tree->rootChildren.end(), id);
    if (rit != tree->rootChildren.end()) { tree->rootChildren.erase(rit); tree->root->RemoveVisual(v->visual); }
    tree->visuals.erase(id);
    compDestroyVisual(tree, v);
    if (!tree->updating) tree->device->Commit();
}

void cd2d_comp_tree_end_update(CD2DCompTree *tree) {
    if (!tree || !tree->updating) return;
    if (tree->drawing) cd2d_comp_tree_surface_end_draw(tree, tree->drawing);
    // 1. Visuals the update did not ensure go away.
    std::vector<int64_t> dead;
    for (auto &entry : tree->visuals) if (!entry.second->seen) dead.push_back(entry.first);
    for (int64_t id : dead) {
        CD2DCompVisual *v = tree->visuals[id];
        tree->visuals.erase(id);
        compDestroyVisual(tree, v); // RemoveAllVisuals drops its (possibly reparented) children
    }
    // 2. Parents whose child list changed detach everything first (a visual cannot be added
    //    under a new parent while the old one still holds it), then re-add in order.
    bool rootDirty = tree->rootChildren != tree->newRootChildren;
    if (rootDirty) { tree->root->RemoveAllVisuals(); compDetachedChildren(tree, tree->rootChildren); }
    for (auto &entry : tree->visuals) {
        CD2DCompVisual *v = entry.second;
        if (v->children != v->newChildren) { v->visual->RemoveAllVisuals(); compDetachedChildren(tree, v->children); }
    }
    if (rootDirty) { compPlaceChildren(tree, 0, tree->root, tree->newRootChildren); tree->rootChildren = tree->newRootChildren; }
    for (auto &entry : tree->visuals) {
        CD2DCompVisual *v = entry.second;
        if (v->children != v->newChildren) { compPlaceChildren(tree, entry.first, v->visual, v->newChildren); v->children = v->newChildren; }
    }
    // A child listed under an unchanged parent but not attached to it (it was taken off a
    // stale parent above, or an earlier AddVisual failed) is re-added in place.
    for (auto &entry : tree->visuals) {
        CD2DCompVisual *v = entry.second;
        bool missing = false;
        for (int64_t id : v->children) {
            CD2DCompVisual *c = compVisual(tree, id);
            if (c && c->attachedTo != entry.first) { missing = true; break; }
        }
        if (missing) { v->visual->RemoveAllVisuals(); compDetachedChildren(tree, v->children); compPlaceChildren(tree, entry.first, v->visual, v->children); }
    }
    tree->updating = false;
    tree->device->Commit();
}

uint32_t cd2d_comp_tree_visual_count(CD2DCompTree *tree) {
    return tree ? (uint32_t)tree->visuals.size() : 0;
}

void cd2d_comp_tree_last_draw_info(CD2DCompTree *tree, void **surface, int32_t *offsetX, int32_t *offsetY, bool *created) {
    if (surface) *surface = tree ? tree->lastSurface : nullptr;
    if (offsetX) *offsetX = tree ? tree->lastOffsetX : 0;
    if (offsetY) *offsetY = tree ? tree->lastOffsetY : 0;
    if (created) *created = tree ? tree->lastSurfaceCreated : false;
}

int32_t cd2d_comp_tree_last_surface_refs(CD2DCompTree *tree) { return tree ? tree->lastSurfaceRefs : 0; }

void cd2d_comp_tree_last_draw_error(CD2DCompTree *tree, int32_t *stage, int32_t *hr) {
    if (stage) *stage = tree ? tree->lastDrawStage : 0;
    if (hr) *hr = tree ? tree->lastDrawError : 0;
}

void cd2d_comp_tree_failures(CD2DCompTree *tree, uint32_t *addFailures, uint32_t *contentFailures) {
    if (addFailures) *addFailures = tree ? tree->addFailures : 0;
    if (contentFailures) *contentFailures = tree ? tree->contentFailures : 0;
}

}  // extern "C"

// ---------------------------------------------------------------- Drag and drop (OLE)

namespace {

CD2DDragCallbacks g_dnd = {};
bool g_dndInitialized = false;
IDataObject *g_dndSourceObject = nullptr;        // the data object of the drag this application runs
IDropTargetHelper *g_dropTargetHelper = nullptr;

std::wstring utf16(const uint16_t *s) { return s ? std::wstring(reinterpret_cast<const wchar_t *>(s)) : std::wstring(); }

std::string utf8FromWide(const wchar_t *s, int length) {
    if (!s || length == 0) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, s, length, nullptr, 0, nullptr, nullptr);
    std::string out(n > 0 ? n : 0, '\0');
    if (n > 0) WideCharToMultiByte(CP_UTF8, 0, s, length, &out[0], n, nullptr, nullptr);
    return out;
}

std::wstring wideFromUTF8(const uint8_t *s, uint32_t length) {
    if (!s || length == 0) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, reinterpret_cast<const char *>(s), (int)length, nullptr, 0);
    std::wstring out(n > 0 ? n : 0, L'\0');
    if (n > 0) MultiByteToWideChar(CP_UTF8, 0, reinterpret_cast<const char *>(s), (int)length, &out[0], n);
    return out;
}

HGLOBAL globalFrom(const void *bytes, size_t length) {
    HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, length ? length : 1);
    if (!h) return nullptr;
    void *p = GlobalLock(h);
    if (p && length) memcpy(p, bytes, length);
    GlobalUnlock(h);
    return h;
}

HGLOBAL duplicateGlobal(HGLOBAL h) {
    if (!h) return nullptr;
    SIZE_T size = GlobalSize(h);
    const void *src = GlobalLock(h);
    HGLOBAL copy = globalFrom(src, size);
    GlobalUnlock(h);
    return copy;
}

CLIPFORMAT appKitFormat(const std::wstring &type) {
    std::wstring name = L"AppKitCross:" + type;
    return (CLIPFORMAT)RegisterClipboardFormatW(name.c_str());
}

/// The data object this application offers: formats held as HGLOBALs (or whatever a
/// caller stored through SetData, which the shell drag-image helper does).
class DataObject : public IDataObject {
    struct Entry { FORMATETC format; STGMEDIUM medium; };
    std::vector<Entry> entries;
    LONG refs = 1;
public:
    ~DataObject() { for (auto &e : entries) ReleaseStgMedium(&e.medium); }

    void addGlobal(CLIPFORMAT cf, HGLOBAL h) {
        FORMATETC f = { cf, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        STGMEDIUM m = {}; m.tymed = TYMED_HGLOBAL; m.hGlobal = h;
        entries.push_back({ f, m });
    }

    // IUnknown
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IDataObject) { *ppv = static_cast<IDataObject *>(this); AddRef(); return S_OK; }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override { ULONG r = InterlockedDecrement(&refs); if (r == 0) delete this; return r; }

    Entry *find(FORMATETC *f) {
        for (auto &e : entries) {
            if (e.format.cfFormat == f->cfFormat && (e.format.tymed & f->tymed) && (e.format.dwAspect & f->dwAspect)) return &e;
        }
        return nullptr;
    }

    // IDataObject
    HRESULT STDMETHODCALLTYPE GetData(FORMATETC *f, STGMEDIUM *m) override {
        if (!f || !m) return E_POINTER;
        Entry *e = find(f);
        if (!e) return DV_E_FORMATETC;
        *m = {};
        m->tymed = e->medium.tymed;
        switch (e->medium.tymed) {
        case TYMED_HGLOBAL: m->hGlobal = duplicateGlobal(e->medium.hGlobal); return m->hGlobal ? S_OK : E_OUTOFMEMORY;
        case TYMED_ISTREAM: m->pstm = e->medium.pstm; if (m->pstm) m->pstm->AddRef(); return S_OK;
        case TYMED_GDI: case TYMED_MFPICT: case TYMED_ENHMF:
            // Hand the stored handle out without transferring ownership: the caller's
            // ReleaseStgMedium then releases `pUnkForRelease` (us) instead of the handle.
            m->hGlobal = e->medium.hGlobal; m->pUnkForRelease = this; AddRef(); return S_OK;
        default: return DV_E_TYMED;
        }
    }
    HRESULT STDMETHODCALLTYPE GetDataHere(FORMATETC *, STGMEDIUM *) override { return E_NOTIMPL; }
    HRESULT STDMETHODCALLTYPE QueryGetData(FORMATETC *f) override { return f && find(f) ? S_OK : DV_E_FORMATETC; }
    HRESULT STDMETHODCALLTYPE GetCanonicalFormatEtc(FORMATETC *, FORMATETC *out) override { if (out) out->ptd = nullptr; return DATA_S_SAMEFORMATETC; }
    HRESULT STDMETHODCALLTYPE SetData(FORMATETC *f, STGMEDIUM *m, BOOL release) override {
        if (!f || !m) return E_POINTER;
        Entry *e = find(f);
        STGMEDIUM stored = {};
        if (release) {
            stored = *m;
        } else {
            stored.tymed = m->tymed;
            if (m->tymed == TYMED_HGLOBAL) stored.hGlobal = duplicateGlobal(m->hGlobal);
            else if (m->tymed == TYMED_ISTREAM) { stored.pstm = m->pstm; if (stored.pstm) stored.pstm->AddRef(); }
            else return DV_E_TYMED;
        }
        if (e) { ReleaseStgMedium(&e->medium); e->medium = stored; e->format = *f; }
        else entries.push_back({ *f, stored });
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE EnumFormatEtc(DWORD direction, IEnumFORMATETC **out) override {
        if (!out) return E_POINTER;
        if (direction != DATADIR_GET) return E_NOTIMPL;
        std::vector<FORMATETC> formats;
        for (auto &e : entries) formats.push_back(e.format);
        return SHCreateStdEnumFmtEtc((UINT)formats.size(), formats.data(), out);
    }
    HRESULT STDMETHODCALLTYPE DAdvise(FORMATETC *, DWORD, IAdviseSink *, DWORD *) override { return OLE_E_ADVISENOTSUPPORTED; }
    HRESULT STDMETHODCALLTYPE DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
    HRESULT STDMETHODCALLTYPE EnumDAdvise(IEnumSTATDATA **) override { return OLE_E_ADVISENOTSUPPORTED; }
};

class DropSource : public IDropSource {
    LONG refs = 1;
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IDropSource) { *ppv = static_cast<IDropSource *>(this); AddRef(); return S_OK; }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override { ULONG r = InterlockedDecrement(&refs); if (r == 0) delete this; return r; }
    HRESULT STDMETHODCALLTYPE QueryContinueDrag(BOOL escapePressed, DWORD keyState) override {
        if (g_dnd.sourceTick) g_dnd.sourceTick(g_dnd.context);
        if (escapePressed) return DRAGDROP_S_CANCEL;
        if (!(keyState & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON))) return DRAGDROP_S_DROP;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GiveFeedback(DWORD) override { return DRAGDROP_S_USEDEFAULTCURSORS; }
};

class DropTarget : public IDropTarget {
    LONG refs = 1;
    HWND hwnd;
public:
    explicit DropTarget(HWND h) : hwnd(h) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IDropTarget) { *ppv = static_cast<IDropTarget *>(this); AddRef(); return S_OK; }
        *ppv = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override { ULONG r = InterlockedDecrement(&refs); if (r == 0) delete this; return r; }

    HRESULT STDMETHODCALLTYPE DragEnter(IDataObject *data, DWORD keyState, POINTL pt, DWORD *effect) override {
        if (!effect) return E_POINTER;
        if (g_dropTargetHelper) { POINT p = { pt.x, pt.y }; g_dropTargetHelper->DragEnter(hwnd, data, &p, *effect); }
        uint32_t result = g_dnd.enter ? g_dnd.enter(g_dnd.context, hwnd, reinterpret_cast<CD2DDragData *>(data), data == g_dndSourceObject, pt.x, pt.y, keyState, *effect) : DROPEFFECT_NONE;
        *effect = result;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DragOver(DWORD keyState, POINTL pt, DWORD *effect) override {
        if (!effect) return E_POINTER;
        if (g_dropTargetHelper) { POINT p = { pt.x, pt.y }; g_dropTargetHelper->DragOver(&p, *effect); }
        *effect = g_dnd.over ? g_dnd.over(g_dnd.context, hwnd, pt.x, pt.y, keyState, *effect) : DROPEFFECT_NONE;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DragLeave() override {
        if (g_dropTargetHelper) g_dropTargetHelper->DragLeave();
        if (g_dnd.leave) g_dnd.leave(g_dnd.context, hwnd);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Drop(IDataObject *data, DWORD keyState, POINTL pt, DWORD *effect) override {
        if (!effect) return E_POINTER;
        if (g_dropTargetHelper) { POINT p = { pt.x, pt.y }; g_dropTargetHelper->Drop(data, &p, *effect); }
        *effect = g_dnd.drop ? g_dnd.drop(g_dnd.context, hwnd, reinterpret_cast<CD2DDragData *>(data), data == g_dndSourceObject, pt.x, pt.y, keyState, *effect) : DROPEFFECT_NONE;
        return S_OK;
    }
};

struct ReadEntry { uint32_t item; std::wstring type; std::string bytes; };

} // namespace

bool cd2d_dnd_initialize(const CD2DDragCallbacks *callbacks) {
    if (callbacks) g_dnd = *callbacks;
    if (g_dndInitialized) return true;
    HRESULT hr = OleInitialize(nullptr);
    g_dndInitialized = SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;
    if (g_dndInitialized && !g_dropTargetHelper) {
        CoCreateInstance(CLSID_DragDropHelper, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&g_dropTargetHelper));
    }
    return g_dndInitialized;
}

bool cd2d_dnd_register(void *hwnd) {
    if (!g_dndInitialized || !hwnd) return false;
    DropTarget *target = new DropTarget(static_cast<HWND>(hwnd));
    HRESULT hr = RegisterDragDrop(static_cast<HWND>(hwnd), target);
    target->Release();      // RegisterDragDrop holds its own reference
    return SUCCEEDED(hr);
}

void cd2d_dnd_revoke(void *hwnd) {
    if (g_dndInitialized && hwnd) RevokeDragDrop(static_cast<HWND>(hwnd));
}

uint32_t cd2d_dnd_do_drag(const CD2DDragEntry *entries, uint32_t count, uint32_t allowedEffects,
                          const uint8_t *imageBGRA, uint32_t width, uint32_t height, int32_t hotspotX, int32_t hotspotY) {
    if (!g_dndInitialized) return DROPEFFECT_NONE;
    DataObject *object = new DataObject();
    // Files travel together as one CF_HDROP; everything else is one format per entry.
    std::vector<std::wstring> paths;
    for (uint32_t i = 0; i < count; i++) {
        const CD2DDragEntry &e = entries[i];
        std::wstring type = utf16(e.type);
        if (type == L"public.file-url") {
            paths.push_back(wideFromUTF8(e.bytes, e.length));
        } else if (type == L"public.utf8-plain-text") {
            std::wstring text = wideFromUTF8(e.bytes, e.length);
            object->addGlobal(CF_UNICODETEXT, globalFrom(text.c_str(), (text.size() + 1) * sizeof(wchar_t)));
        } else {
            object->addGlobal(appKitFormat(type), globalFrom(e.bytes, e.length));
        }
    }
    if (!paths.empty()) {
        size_t chars = 1;
        for (auto &p : paths) chars += p.size() + 1;
        size_t size = sizeof(DROPFILES) + chars * sizeof(wchar_t);
        std::vector<uint8_t> buffer(size, 0);
        DROPFILES *df = reinterpret_cast<DROPFILES *>(buffer.data());
        df->pFiles = sizeof(DROPFILES);
        df->fWide = TRUE;
        wchar_t *out = reinterpret_cast<wchar_t *>(buffer.data() + sizeof(DROPFILES));
        for (auto &p : paths) { memcpy(out, p.c_str(), (p.size() + 1) * sizeof(wchar_t)); out += p.size() + 1; }
        *out = 0;
        object->addGlobal(CF_HDROP, globalFrom(buffer.data(), buffer.size()));
    }
    if (imageBGRA && width > 0 && height > 0) {
        BITMAPINFO bi = {};
        bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bi.bmiHeader.biWidth = (LONG)width;
        bi.bmiHeader.biHeight = -(LONG)height;
        bi.bmiHeader.biPlanes = 1;
        bi.bmiHeader.biBitCount = 32;
        bi.bmiHeader.biCompression = BI_RGB;
        void *bits = nullptr;
        HDC dc = GetDC(nullptr);
        HBITMAP bitmap = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
        ReleaseDC(nullptr, dc);
        if (bitmap && bits) {
            memcpy(bits, imageBGRA, (size_t)width * height * 4);
            IDragSourceHelper *helper = nullptr;
            if (SUCCEEDED(CoCreateInstance(CLSID_DragDropHelper, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&helper))) && helper) {
                SHDRAGIMAGE image = {};
                image.sizeDragImage = { (LONG)width, (LONG)height };
                image.ptOffset = { hotspotX, hotspotY };
                image.hbmpDragImage = bitmap;
                image.crColorKey = CLR_NONE;
                if (FAILED(helper->InitializeFromBitmap(&image, object))) DeleteObject(bitmap);   // success: the helper owns it
                helper->Release();
            } else {
                DeleteObject(bitmap);
            }
        } else if (bitmap) {
            DeleteObject(bitmap);
        }
    }
    DropSource *source = new DropSource();
    DWORD effect = DROPEFFECT_NONE;
    g_dndSourceObject = object;
    HRESULT hr = DoDragDrop(object, source, allowedEffects, &effect);
    g_dndSourceObject = nullptr;
    source->Release();
    object->Release();
    return hr == DRAGDROP_S_DROP ? effect : DROPEFFECT_NONE;
}

CD2DDragEntry *cd2d_drag_data_read(CD2DDragData *data, uint32_t *count) {
    if (count) *count = 0;
    IDataObject *object = reinterpret_cast<IDataObject *>(data);
    if (!object || !count) return nullptr;
    std::vector<ReadEntry> read;
    IEnumFORMATETC *formats = nullptr;
    if (FAILED(object->EnumFormatEtc(DATADIR_GET, &formats)) || !formats) return nullptr;
    FORMATETC f;
    bool haveText = false;
    while (formats->Next(1, &f, nullptr) == S_OK) {
        if (!(f.tymed & TYMED_HGLOBAL)) continue;
        std::wstring type;
        if (f.cfFormat == CF_UNICODETEXT) { if (haveText) continue; type = L"public.utf8-plain-text"; }
        else if (f.cfFormat == CF_HDROP) type = L"public.file-url";
        else {
            wchar_t name[256] = {};
            if (GetClipboardFormatNameW(f.cfFormat, name, 256) == 0) continue;
            std::wstring n(name);
            if (n.rfind(L"AppKitCross:", 0) != 0) continue;
            type = n.substr(10);
        }
        FORMATETC request = { f.cfFormat, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL };
        STGMEDIUM medium = {};
        if (FAILED(object->GetData(&request, &medium))) continue;
        if (medium.tymed == TYMED_HGLOBAL && medium.hGlobal) {
            if (f.cfFormat == CF_HDROP) {
                HDROP drop = static_cast<HDROP>(medium.hGlobal);
                UINT n = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
                for (UINT i = 0; i < n; i++) {
                    UINT len = DragQueryFileW(drop, i, nullptr, 0);
                    std::wstring path(len + 1, L'\0');
                    DragQueryFileW(drop, i, &path[0], len + 1);
                    path.resize(len);
                    read.push_back({ i, type, utf8FromWide(path.c_str(), (int)path.size()) });
                }
            } else {
                const void *p = GlobalLock(medium.hGlobal);
                SIZE_T size = GlobalSize(medium.hGlobal);
                if (p) {
                    if (f.cfFormat == CF_UNICODETEXT) {
                        const wchar_t *w = static_cast<const wchar_t *>(p);
                        size_t len = wcsnlen(w, size / sizeof(wchar_t));
                        read.push_back({ 0, type, utf8FromWide(w, (int)len) });
                        haveText = true;
                    } else {
                        read.push_back({ 0, type, std::string(static_cast<const char *>(p), size) });
                    }
                    GlobalUnlock(medium.hGlobal);
                }
            }
        }
        ReleaseStgMedium(&medium);
    }
    formats->Release();
    if (read.empty()) return nullptr;
    CD2DDragEntry *out = new CD2DDragEntry[read.size()];
    for (size_t i = 0; i < read.size(); i++) {
        uint16_t *type = new uint16_t[read[i].type.size() + 1];
        memcpy(type, read[i].type.c_str(), (read[i].type.size() + 1) * sizeof(uint16_t));
        uint8_t *bytes = new uint8_t[read[i].bytes.size() + 1];
        memcpy(bytes, read[i].bytes.data(), read[i].bytes.size());
        out[i] = { read[i].item, type, bytes, (uint32_t)read[i].bytes.size() };
    }
    *count = (uint32_t)read.size();
    return out;
}

void cd2d_drag_data_free_entries(CD2DDragEntry *entries, uint32_t count) {
    if (!entries) return;
    for (uint32_t i = 0; i < count; i++) { delete[] entries[i].type; delete[] entries[i].bytes; }
    delete[] entries;
}
