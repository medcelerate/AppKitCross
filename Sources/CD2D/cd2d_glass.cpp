// The Liquid Glass lens as a Direct2D custom effect (ADR-0052 stage 2).
//
// One effect, one input (the blurred backdrop at the sample scale, uploaded as a bitmap at
// 96 DPI so a DIP is a sample pixel), one draw transform whose output is (0, 0, W, H) in
// output pixels and whose input is the whole backdrop (the shader reads it anywhere: the
// refraction and the border clamp). The pixel shader is compiled at run time from the HLSL
// AppKit embeds (Platform/Shaders/glass_lens.hlsl) and the constants are one blob property.
// The effect draws on the window's own device context, in pixel units, so nothing is read
// back and nothing is uploaded at the backing scale.

#include "cd2d.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d2d1_1.h>
#include <d2d1_1helper.h>
#include <d2d1effectauthor.h>
#include <d3dcompiler.h>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

extern "C" void *cd2d_target_native_render_target(CD2DTarget *t);

// {6C2B3D1E-52A4-4F0B-9D31-7A0E4B128852}
static const CLSID kGlassLensEffect = {0x6c2b3d1e, 0x52a4, 0x4f0b, {0x9d, 0x31, 0x7a, 0x0e, 0x4b, 0x12, 0x88, 0x52}};
// {8F1D2C44-0B6E-4A77-A358-219C607E14D3}
static const GUID kGlassLensShader = {0x8f1d2c44, 0x0b6e, 0x4a77, {0xa3, 0x58, 0x21, 0x9c, 0x60, 0x7e, 0x14, 0xd3}};

static std::vector<BYTE> gBytecode;
static std::string gCompileError;
static bool gPrepared = false;

static const float kZeroConstants[48] = {};

class GlassLensEffect final : public ID2D1EffectImpl, public ID2D1DrawTransform {
public:
    static HRESULT CALLBACK Create(IUnknown **effect) {
        if (!effect) return E_POINTER;
        *effect = static_cast<ID2D1EffectImpl *>(new GlassLensEffect());
        return S_OK;
    }

    // IUnknown
    ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&refs);
        if (r == 0) delete this;
        return (ULONG)r;
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) override {
        if (!out) return E_POINTER;
        if (riid == __uuidof(ID2D1EffectImpl) || riid == __uuidof(IUnknown)) *out = static_cast<ID2D1EffectImpl *>(this);
        else if (riid == __uuidof(ID2D1DrawTransform) || riid == __uuidof(ID2D1Transform) || riid == __uuidof(ID2D1TransformNode)) *out = static_cast<ID2D1DrawTransform *>(this);
        else { *out = nullptr; return E_NOINTERFACE; }
        AddRef();
        return S_OK;
    }

    // ID2D1EffectImpl
    HRESULT STDMETHODCALLTYPE Initialize(ID2D1EffectContext *context, ID2D1TransformGraph *graph) override {
        if (gBytecode.empty()) return E_FAIL;
        HRESULT hr = context->LoadPixelShader(kGlassLensShader, gBytecode.data(), (UINT32)gBytecode.size());
        if (FAILED(hr)) return hr;
        return graph->SetSingleTransformNode(static_cast<ID2D1DrawTransform *>(this));
    }
    HRESULT STDMETHODCALLTYPE PrepareForRender(D2D1_CHANGE_TYPE) override {
        if (!drawInfo) return E_FAIL;
        return drawInfo->SetPixelShaderConstantBuffer(reinterpret_cast<const BYTE *>(constants), sizeof(constants));
    }
    HRESULT STDMETHODCALLTYPE SetGraph(ID2D1TransformGraph *) override { return E_NOTIMPL; }

    // ID2D1DrawTransform
    HRESULT STDMETHODCALLTYPE SetDrawInfo(ID2D1DrawInfo *info) override {
        if (!info) return E_POINTER;
        if (drawInfo) drawInfo->Release();
        drawInfo = info;
        drawInfo->AddRef();
        HRESULT hr = info->SetPixelShader(kGlassLensShader, D2D1_PIXEL_OPTIONS_NONE);
        if (FAILED(hr)) return hr;
        D2D1_INPUT_DESCRIPTION input = {D2D1_FILTER_MIN_MAG_MIP_LINEAR, 0};
        return info->SetInputDescription(0, input);
    }

    // ID2D1Transform: the output is the surface, the input is wanted whole.
    HRESULT STDMETHODCALLTYPE MapOutputRectToInputRects(const D2D1_RECT_L *, D2D1_RECT_L *inputRects, UINT32 count) const override {
        if (count != 1) return E_INVALIDARG;
        inputRects[0] = inputRect;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE MapInputRectsToOutputRect(const D2D1_RECT_L *inputRects, const D2D1_RECT_L *, UINT32 count,
                                                         D2D1_RECT_L *outputRect, D2D1_RECT_L *outputOpaqueSubRect) override {
        if (count != 1) return E_INVALIDARG;
        inputRect = inputRects[0];
        *outputRect = surface();
        *outputOpaqueSubRect = D2D1::RectL(0, 0, 0, 0);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE MapInvalidRect(UINT32, D2D1_RECT_L, D2D1_RECT_L *invalidOutputRect) const override {
        *invalidOutputRect = surface();
        return S_OK;
    }
    UINT32 STDMETHODCALLTYPE GetInputCount() const override { return 1; }

    // The "Constants" blob property.
    HRESULT SetConstants(const BYTE *data, UINT32 size) {
        if (!data || size != sizeof(constants)) return E_INVALIDARG;
        memcpy(constants, data, size);
        return S_OK;
    }
    HRESULT GetConstants(BYTE *data, UINT32 size, UINT32 *actual) const {
        if (actual) *actual = sizeof(constants);
        if (data) {
            if (size < sizeof(constants)) return E_INVALIDARG;
            memcpy(data, constants, sizeof(constants));
        }
        return S_OK;
    }

private:
    GlassLensEffect() { memcpy(constants, kZeroConstants, sizeof(constants)); }
    ~GlassLensEffect() { if (drawInfo) drawInfo->Release(); }
    D2D1_RECT_L surface() const { return D2D1::RectL(0, 0, (LONG)std::ceil(constants[0]), (LONG)std::ceil(constants[1])); }

    LONG refs = 1;
    ID2D1DrawInfo *drawInfo = nullptr;
    float constants[48];
    D2D1_RECT_L inputRect = {0, 0, 0, 0};
};

static HRESULT CALLBACK setConstants(IUnknown *effect, const BYTE *data, UINT32 size) {
    return static_cast<GlassLensEffect *>(static_cast<ID2D1EffectImpl *>(effect))->SetConstants(data, size);
}
static HRESULT CALLBACK getConstants(const IUnknown *effect, BYTE *data, UINT32 size, UINT32 *actual) {
    return static_cast<const GlassLensEffect *>(static_cast<const ID2D1EffectImpl *>(effect))->GetConstants(data, size, actual);
}

static const wchar_t kEffectXML[] =
    L"<?xml version='1.0'?>"
    L"<Effect>"
    L"<Property name='DisplayName' type='string' value='AppKitCross Liquid Glass Lens'/>"
    L"<Property name='Author' type='string' value='AppKitCross'/>"
    L"<Property name='Category' type='string' value='Stylize'/>"
    L"<Property name='Description' type='string' value='The Liquid Glass lens stage (ADR-0052)'/>"
    L"<Inputs><Input name='Source'/></Inputs>"
    L"<Property name='Constants' type='blob'><Property name='DisplayName' type='string' value='Constants'/></Property>"
    L"</Effect>";

/// Registers the effect with the factory behind `dc` once (factories are kept referenced so
/// the pointers stay unique).
static bool registerEffect(ID2D1DeviceContext *dc) {
    static std::vector<ID2D1Factory1 *> registered;
    ID2D1Factory *factory = nullptr;
    dc->GetFactory(&factory);
    if (!factory) return false;
    ID2D1Factory1 *factory1 = nullptr;
    HRESULT hr = factory->QueryInterface(__uuidof(ID2D1Factory1), reinterpret_cast<void **>(&factory1));
    factory->Release();
    if (FAILED(hr) || !factory1) return false;
    for (ID2D1Factory1 *f : registered) {
        if (f == factory1) { factory1->Release(); return true; }
    }
    const D2D1_PROPERTY_BINDING bindings[] = {{L"Constants", setConstants, getConstants}};
    hr = factory1->RegisterEffectFromString(kGlassLensEffect, kEffectXML, bindings, 1, GlassLensEffect::Create);
    if (FAILED(hr)) { factory1->Release(); return false; }
    registered.push_back(factory1);   // keeps the reference
    return true;
}

/// One effect per device context, the last few kept.
static ID2D1Effect *effectFor(ID2D1DeviceContext *dc) {
    struct Entry { ID2D1DeviceContext *dc; ID2D1Effect *effect; };
    static Entry cache[4] = {};
    static unsigned next = 0;
    for (Entry &e : cache) if (e.dc == dc && e.effect) return e.effect;
    ID2D1Effect *effect = nullptr;
    if (FAILED(dc->CreateEffect(kGlassLensEffect, &effect)) || !effect) return nullptr;
    Entry &slot = cache[next++ % 4];
    if (slot.effect) slot.effect->Release();
    if (slot.dc) slot.dc->Release();
    dc->AddRef();
    slot = {dc, effect};
    return effect;
}

extern "C" {

bool cd2d_glass_prepare(const char *hlsl, char *error, uint32_t capacity) {
    auto fail = [&](const std::string &message) {
        gCompileError = message;
        if (error && capacity) { strncpy(error, message.c_str(), capacity - 1); error[capacity - 1] = 0; }
        return false;
    };
    if (gPrepared) return gBytecode.empty() ? fail(gCompileError) : true;
    gPrepared = true;
    if (!hlsl) return fail("no shader source");
    HMODULE compiler = LoadLibraryW(L"d3dcompiler_47.dll");
    if (!compiler) return fail("d3dcompiler_47.dll is not available");
    auto compile = reinterpret_cast<pD3DCompile>(GetProcAddress(compiler, "D3DCompile"));
    if (!compile) return fail("D3DCompile is not exported");
    ID3DBlob *code = nullptr, *messages = nullptr;
    // IEEE strictness keeps the float steps the software pass takes (no fused or reordered math).
    HRESULT hr = compile(hlsl, strlen(hlsl), "glass_lens.hlsl", nullptr, nullptr, "main", "ps_4_0",
                         D3DCOMPILE_OPTIMIZATION_LEVEL3 | D3DCOMPILE_IEEE_STRICTNESS, 0, &code, &messages);
    std::string text;
    if (messages) { text.assign(static_cast<const char *>(messages->GetBufferPointer()), messages->GetBufferSize()); messages->Release(); }
    if (FAILED(hr) || !code) {
        if (code) code->Release();
        return fail("D3DCompile failed: " + text);
    }
    const BYTE *bytes = static_cast<const BYTE *>(code->GetBufferPointer());
    gBytecode.assign(bytes, bytes + code->GetBufferSize());
    code->Release();
    return true;
}

bool cd2d_glass_draw(CD2DTarget *target, const uint8_t *backdrop, uint32_t backdropWidth, uint32_t backdropHeight, uint32_t stride,
                     const float *constants, uint32_t width, uint32_t height) {
    if (gBytecode.empty() || !target || !backdrop || !constants || backdropWidth == 0 || backdropHeight == 0 || width == 0 || height == 0) return false;
    auto *rt = static_cast<ID2D1RenderTarget *>(cd2d_target_native_render_target(target));
    if (!rt) return false;
    ID2D1DeviceContext *dc = nullptr;
    if (FAILED(rt->QueryInterface(__uuidof(ID2D1DeviceContext), reinterpret_cast<void **>(&dc))) || !dc) return false;
    bool ok = false;
    do {
        if (!registerEffect(dc)) break;
        ID2D1Effect *effect = effectFor(dc);
        if (!effect) break;
        D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_NONE,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
        ID2D1Bitmap1 *bitmap = nullptr;
        if (FAILED(dc->CreateBitmap(D2D1::SizeU(backdropWidth, backdropHeight), backdrop, stride, &props, &bitmap)) || !bitmap) break;
        effect->SetInput(0, bitmap);
        bitmap->Release();
        float k[48];
        memcpy(k, constants, sizeof(k));
        k[0] = (float)width; k[1] = (float)height;
        if (FAILED(effect->SetValue(0, D2D1_PROPERTY_TYPE_BLOB, reinterpret_cast<const BYTE *>(k), sizeof(k)))) break;
        // The caller's transform maps output pixels to user space in DIPs; in pixel units
        // the DPI scale is ours to add.
        D2D1_MATRIX_3X2_F world;
        dc->GetTransform(&world);
        D2D1_UNIT_MODE mode = dc->GetUnitMode();
        float dpiX = 96, dpiY = 96;
        dc->GetDpi(&dpiX, &dpiY);
        dc->SetUnitMode(D2D1_UNIT_MODE_PIXELS);
        dc->SetTransform(D2D1::Matrix3x2F(world.m11, world.m12, world.m21, world.m22, world.dx, world.dy) * D2D1::Matrix3x2F::Scale(dpiX / 96, dpiY / 96));
        dc->DrawImage(effect, D2D1_INTERPOLATION_MODE_LINEAR, D2D1_COMPOSITE_MODE_SOURCE_OVER);
        dc->SetTransform(world);
        dc->SetUnitMode(mode);
        ok = true;
    } while (false);
    dc->Release();
    return ok;
}

}
