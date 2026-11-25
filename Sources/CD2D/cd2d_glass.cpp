// Liquid Glass as Direct2D custom effects (ADR-0052 stage 2).
//
// Three effects share one implementation (GlassEffect, a draw transform with a 48-float
// constant blob): the lens (glass_lens.hlsl `main`, two inputs: the backdrop and the
// one-pixel luminance probe, output (0, 0, W, H) in output pixels), the box pass with the
// saturation (glass_backdrop.hlsl `box`, output the crop it reads) and the luminance probe
// (glass_backdrop.hlsl `luminance`, output one pixel at the origin). Each effect wants its
// inputs whole: the shaders read anywhere in them.
//
// Round 1 drew the lens over a backdrop the CPU had blurred, uploaded at the sample scale.
// Round 3 renders the frame beneath the glass into a bitmap on the window's own device
// (cd2d_glass_frame_*), and cd2d_glass_draw_from_frame runs the whole program as one effect
// graph per surface: the frame (halved by the built-in Scale effect for a material), the
// crop (with the strip below a band mirrored in by a flip and a composite), six box passes,
// the probe, the lens, drawn into the window. Nothing is read back.
//
// Shaders are compiled at run time from the HLSL AppKit embeds (D3DCompile from
// d3dcompiler_47.dll, loaded dynamically, IEEE strictness, ps_4_0).

#include "cd2d.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d2d1_1.h>
#include <d2d1_1helper.h>
#include <d2d1effects.h>
#include <d2d1effectauthor.h>
#include <d3dcompiler.h>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

extern "C" void *cd2d_target_native_render_target(CD2DTarget *t);
extern "C" CD2DTarget *cd2d_target_wrap_native(void *renderTarget);

enum GlassKind { kLens = 0, kBox = 1, kLuminance = 2 };

// {6C2B3D1E-52A4-4F0B-9D31-7A0E4B128852} and the two that follow it.
static const CLSID kEffectIDs[3] = {
    {0x6c2b3d1e, 0x52a4, 0x4f0b, {0x9d, 0x31, 0x7a, 0x0e, 0x4b, 0x12, 0x88, 0x52}},
    {0x6c2b3d1e, 0x52a4, 0x4f0b, {0x9d, 0x31, 0x7a, 0x0e, 0x4b, 0x12, 0x88, 0x53}},
    {0x6c2b3d1e, 0x52a4, 0x4f0b, {0x9d, 0x31, 0x7a, 0x0e, 0x4b, 0x12, 0x88, 0x54}},
};
// {8F1D2C44-0B6E-4A77-A358-219C607E14D3} and the two that follow it.
static const GUID kShaderIDs[3] = {
    {0x8f1d2c44, 0x0b6e, 0x4a77, {0xa3, 0x58, 0x21, 0x9c, 0x60, 0x7e, 0x14, 0xd3}},
    {0x8f1d2c44, 0x0b6e, 0x4a77, {0xa3, 0x58, 0x21, 0x9c, 0x60, 0x7e, 0x14, 0xd4}},
    {0x8f1d2c44, 0x0b6e, 0x4a77, {0xa3, 0x58, 0x21, 0x9c, 0x60, 0x7e, 0x14, 0xd5}},
};

static std::vector<BYTE> gBytecode[3];
static std::string gCompileError;
static bool gPrepared = false;

class GlassEffect final : public ID2D1EffectImpl, public ID2D1DrawTransform {
public:
    template <int Kind> static HRESULT CALLBACK Create(IUnknown **effect) {
        if (!effect) return E_POINTER;
        *effect = static_cast<ID2D1EffectImpl *>(new GlassEffect(Kind));
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
        if (gBytecode[kind].empty()) return E_FAIL;
        HRESULT hr = context->LoadPixelShader(kShaderIDs[kind], gBytecode[kind].data(), (UINT32)gBytecode[kind].size());
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
        HRESULT hr = info->SetPixelShader(kShaderIDs[kind], D2D1_PIXEL_OPTIONS_NONE);
        if (FAILED(hr)) return hr;
        // The lens samples its backdrop bilinearly (the software look-up); the box and the
        // probe read whole texels.
        D2D1_INPUT_DESCRIPTION input = {kind == kLens ? D2D1_FILTER_MIN_MAG_MIP_LINEAR : D2D1_FILTER_MIN_MAG_MIP_POINT, 0};
        hr = info->SetInputDescription(0, input);
        if (FAILED(hr) || kind != kLens) return hr;
        D2D1_INPUT_DESCRIPTION probe = {D2D1_FILTER_MIN_MAG_MIP_POINT, 0};
        return info->SetInputDescription(1, probe);
    }

    // ID2D1Transform: every input is wanted whole.
    HRESULT STDMETHODCALLTYPE MapOutputRectToInputRects(const D2D1_RECT_L *, D2D1_RECT_L *inputRects, UINT32 count) const override {
        if (count != inputCount()) return E_INVALIDARG;
        for (UINT32 i = 0; i < count; i++) inputRects[i] = inputs[i];
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE MapInputRectsToOutputRect(const D2D1_RECT_L *inputRects, const D2D1_RECT_L *, UINT32 count,
                                                         D2D1_RECT_L *outputRect, D2D1_RECT_L *outputOpaqueSubRect) override {
        if (count != inputCount()) return E_INVALIDARG;
        for (UINT32 i = 0; i < count; i++) inputs[i] = inputRects[i];
        *outputRect = output();
        *outputOpaqueSubRect = D2D1::RectL(0, 0, 0, 0);
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE MapInvalidRect(UINT32, D2D1_RECT_L, D2D1_RECT_L *invalidOutputRect) const override {
        *invalidOutputRect = output();
        return S_OK;
    }
    UINT32 STDMETHODCALLTYPE GetInputCount() const override { return inputCount(); }

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
    explicit GlassEffect(int kind) : kind(kind) { memset(constants, 0, sizeof(constants)); }
    ~GlassEffect() { if (drawInfo) drawInfo->Release(); }
    UINT32 inputCount() const { return kind == kLens ? 2 : 1; }
    D2D1_RECT_L output() const {
        switch (kind) {
        case kLens: return D2D1::RectL(0, 0, (LONG)std::ceil(constants[0]), (LONG)std::ceil(constants[1]));
        case kBox: return D2D1::RectL((LONG)constants[0], (LONG)constants[1], (LONG)(constants[0] + constants[2]), (LONG)(constants[1] + constants[3]));
        default: return D2D1::RectL(0, 0, 1, 1);
        }
    }

    LONG refs = 1;
    int kind;
    ID2D1DrawInfo *drawInfo = nullptr;
    float constants[48];
    D2D1_RECT_L inputs[2] = {{0, 0, 0, 0}, {0, 0, 0, 0}};
};

static HRESULT CALLBACK setConstants(IUnknown *effect, const BYTE *data, UINT32 size) {
    return static_cast<GlassEffect *>(static_cast<ID2D1EffectImpl *>(effect))->SetConstants(data, size);
}
static HRESULT CALLBACK getConstants(const IUnknown *effect, BYTE *data, UINT32 size, UINT32 *actual) {
    return static_cast<const GlassEffect *>(static_cast<const ID2D1EffectImpl *>(effect))->GetConstants(data, size, actual);
}

static std::wstring effectXML(const wchar_t *name, int inputs) {
    std::wstring xml =
        L"<?xml version='1.0'?><Effect>"
        L"<Property name='DisplayName' type='string' value='AppKitCross Liquid Glass ";
    xml += name;
    xml += L"'/><Property name='Author' type='string' value='AppKitCross'/>"
           L"<Property name='Category' type='string' value='Stylize'/>"
           L"<Property name='Description' type='string' value='A Liquid Glass stage (ADR-0052)'/><Inputs>";
    xml += L"<Input name='Source'/>";
    if (inputs > 1) xml += L"<Input name='Probe'/>";
    xml += L"</Inputs><Property name='Constants' type='blob'><Property name='DisplayName' type='string' value='Constants'/></Property></Effect>";
    return xml;
}

/// Registers the three effects with the factory behind `dc` once (factories are kept
/// referenced so the pointers stay unique).
static bool registerEffects(ID2D1DeviceContext *dc) {
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
    hr = factory1->RegisterEffectFromString(kEffectIDs[kLens], effectXML(L"Lens", 2).c_str(), bindings, 1, GlassEffect::Create<kLens>);
    if (SUCCEEDED(hr)) hr = factory1->RegisterEffectFromString(kEffectIDs[kBox], effectXML(L"Box", 1).c_str(), bindings, 1, GlassEffect::Create<kBox>);
    if (SUCCEEDED(hr)) hr = factory1->RegisterEffectFromString(kEffectIDs[kLuminance], effectXML(L"Luminance", 1).c_str(), bindings, 1, GlassEffect::Create<kLuminance>);
    if (FAILED(hr)) { factory1->Release(); return false; }
    registered.push_back(factory1);   // keeps the reference
    return true;
}

/// The effects one surface's graph uses, made once per device context and reused for every
/// surface (Direct2D takes the graph's state at each DrawImage).
struct GlassGraph {
    ID2D1DeviceContext *dc = nullptr;
    ID2D1Effect *lens = nullptr, *luminance = nullptr, *box[6] = {};
    ID2D1Effect *scale = nullptr, *flip = nullptr, *cropReal = nullptr, *cropMirror = nullptr, *composite = nullptr;
    void release() {
        ID2D1Effect *all[] = {lens, luminance, box[0], box[1], box[2], box[3], box[4], box[5], scale, flip, cropReal, cropMirror, composite};
        for (ID2D1Effect *e : all) if (e) e->Release();
        if (dc) dc->Release();
        *this = GlassGraph();
    }
};

static GlassGraph *graphFor(ID2D1DeviceContext *dc) {
    static GlassGraph cache[4];
    static unsigned next = 0;
    for (GlassGraph &g : cache) if (g.dc == dc && g.lens) return &g;
    if (!registerEffects(dc)) return nullptr;
    GlassGraph g;
    bool ok = SUCCEEDED(dc->CreateEffect(kEffectIDs[kLens], &g.lens)) && SUCCEEDED(dc->CreateEffect(kEffectIDs[kLuminance], &g.luminance));
    for (int i = 0; ok && i < 6; i++) ok = SUCCEEDED(dc->CreateEffect(kEffectIDs[kBox], &g.box[i]));
    ok = ok && SUCCEEDED(dc->CreateEffect(CLSID_D2D1Scale, &g.scale)) && SUCCEEDED(dc->CreateEffect(CLSID_D2D12DAffineTransform, &g.flip))
        && SUCCEEDED(dc->CreateEffect(CLSID_D2D1Crop, &g.cropReal)) && SUCCEEDED(dc->CreateEffect(CLSID_D2D1Crop, &g.cropMirror))
        && SUCCEEDED(dc->CreateEffect(CLSID_D2D1Composite, &g.composite));
    if (!ok) { g.release(); return nullptr; }
    // The fixed properties: a 2x2 mean (bilinear at exactly half the scale, the border
    // clamped), a nearest-neighbour flip, a two-input source-over composite.
    g.scale->SetValue(D2D1_SCALE_PROP_SCALE, D2D1::Vector2F(0.5f, 0.5f));
    g.scale->SetValue(D2D1_SCALE_PROP_INTERPOLATION_MODE, D2D1_SCALE_INTERPOLATION_MODE_LINEAR);
    g.scale->SetValue(D2D1_SCALE_PROP_BORDER_MODE, D2D1_BORDER_MODE_HARD);
    g.flip->SetValue(D2D1_2DAFFINETRANSFORM_PROP_INTERPOLATION_MODE, D2D1_2DAFFINETRANSFORM_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
    g.flip->SetValue(D2D1_2DAFFINETRANSFORM_PROP_BORDER_MODE, D2D1_BORDER_MODE_HARD);
    g.composite->SetInputCount(2);
    dc->AddRef();
    g.dc = dc;
    GlassGraph &slot = cache[next++ % 4];
    slot.release();
    slot = g;
    return &slot;
}

/// The window target's device context, AddRef'd; NULL for a target that is none.
static ID2D1DeviceContext *deviceContext(CD2DTarget *target) {
    auto *rt = static_cast<ID2D1RenderTarget *>(cd2d_target_native_render_target(target));
    if (!rt) return nullptr;
    ID2D1DeviceContext *dc = nullptr;
    if (FAILED(rt->QueryInterface(__uuidof(ID2D1DeviceContext), reinterpret_cast<void **>(&dc)))) return nullptr;
    return dc;
}

/// Draws `image` (in output pixels, (0, 0, W, H)) into `dc`, whose transform maps output
/// pixels to its user space in DIPs; in pixel units the DPI scale is ours to add.
static void drawInPixels(ID2D1DeviceContext *dc, ID2D1Image *image) {
    D2D1_MATRIX_3X2_F world;
    dc->GetTransform(&world);
    D2D1_UNIT_MODE mode = dc->GetUnitMode();
    float dpiX = 96, dpiY = 96;
    dc->GetDpi(&dpiX, &dpiY);
    dc->SetUnitMode(D2D1_UNIT_MODE_PIXELS);
    dc->SetTransform(D2D1::Matrix3x2F(world.m11, world.m12, world.m21, world.m22, world.dx, world.dy) * D2D1::Matrix3x2F::Scale(dpiX / 96, dpiY / 96));
    dc->DrawImage(image, D2D1_INTERPOLATION_MODE_LINEAR, D2D1_COMPOSITE_MODE_SOURCE_OVER);
    dc->SetTransform(world);
    dc->SetUnitMode(mode);
}

static bool setBlob(ID2D1Effect *effect, const float *k) {
    return SUCCEEDED(effect->SetValue(0, D2D1_PROPERTY_TYPE_BLOB, reinterpret_cast<const BYTE *>(k), 48 * sizeof(float)));
}

/// The frame beneath the glass on the window's device: a bitmap target at 96 DPI (a DIP is a
/// pixel; the caller's transform scales), drawn through its own device context.
struct CD2DGlassFrame {
    ID2D1DeviceContext *dc = nullptr;
    ID2D1Bitmap1 *bitmap = nullptr;
    CD2DTarget *target = nullptr;
    bool drawing = false;
};

extern "C" {

bool cd2d_glass_prepare(const char *lensHLSL, const char *backdropHLSL, char *error, uint32_t capacity) {
    auto fail = [&](const std::string &message) {
        gCompileError = message;
        if (error && capacity) { strncpy(error, message.c_str(), capacity - 1); error[capacity - 1] = 0; }
        return false;
    };
    if (gPrepared) return gBytecode[kLens].empty() ? fail(gCompileError) : true;
    gPrepared = true;
    if (!lensHLSL || !backdropHLSL) return fail("no shader source");
    HMODULE compiler = LoadLibraryW(L"d3dcompiler_47.dll");
    if (!compiler) return fail("d3dcompiler_47.dll is not available");
    auto compile = reinterpret_cast<pD3DCompile>(GetProcAddress(compiler, "D3DCompile"));
    if (!compile) return fail("D3DCompile is not exported");
    struct Job { int kind; const char *source; const char *name; const char *entry; };
    const Job jobs[] = {{kLens, lensHLSL, "glass_lens.hlsl", "main"}, {kBox, backdropHLSL, "glass_backdrop.hlsl", "box"},
                        {kLuminance, backdropHLSL, "glass_backdrop.hlsl", "luminance"}};
    for (const Job &job : jobs) {
        ID3DBlob *code = nullptr, *messages = nullptr;
        // IEEE strictness keeps the float steps the software pass takes (no fused or reordered math).
        HRESULT hr = compile(job.source, strlen(job.source), job.name, nullptr, nullptr, job.entry, "ps_4_0",
                             D3DCOMPILE_OPTIMIZATION_LEVEL3 | D3DCOMPILE_IEEE_STRICTNESS, 0, &code, &messages);
        std::string text;
        if (messages) { text.assign(static_cast<const char *>(messages->GetBufferPointer()), messages->GetBufferSize()); messages->Release(); }
        if (FAILED(hr) || !code) {
            if (code) code->Release();
            for (auto &b : gBytecode) b.clear();
            return fail(std::string("D3DCompile failed for ") + job.entry + ": " + text);
        }
        const BYTE *bytes = static_cast<const BYTE *>(code->GetBufferPointer());
        gBytecode[job.kind].assign(bytes, bytes + code->GetBufferSize());
        code->Release();
    }
    return true;
}

bool cd2d_glass_draw(CD2DTarget *target, const uint8_t *backdrop, uint32_t backdropWidth, uint32_t backdropHeight, uint32_t stride,
                     const float *constants, uint32_t width, uint32_t height) {
    if (gBytecode[kLens].empty() || !target || !backdrop || !constants || backdropWidth == 0 || backdropHeight == 0 || width == 0 || height == 0) return false;
    ID2D1DeviceContext *dc = deviceContext(target);
    if (!dc) return false;
    bool ok = false;
    do {
        GlassGraph *g = graphFor(dc);
        if (!g) break;
        D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_NONE,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
        ID2D1Bitmap1 *bitmap = nullptr;
        if (FAILED(dc->CreateBitmap(D2D1::SizeU(backdropWidth, backdropHeight), backdrop, stride, &props, &bitmap)) || !bitmap) break;
        // The luminance is in the constants here; the probe input is bound but not read.
        g->lens->SetInput(0, bitmap);
        g->lens->SetInput(1, bitmap);
        bitmap->Release();
        float k[48];
        memcpy(k, constants, sizeof(k));
        k[0] = (float)width; k[1] = (float)height;
        k[44] = 0; k[45] = 0;   // the backdrop lies at the effect's origin
        if (!setBlob(g->lens, k)) break;
        drawInPixels(dc, g->lens);
        ok = true;
    } while (false);
    dc->Release();
    return ok;
}

CD2DGlassFrame *cd2d_glass_frame_create(CD2DTarget *like, uint32_t width, uint32_t height) {
    if (gBytecode[kLens].empty() || !like || width == 0 || height == 0) return nullptr;
    ID2D1DeviceContext *windowDC = deviceContext(like);
    if (!windowDC) return nullptr;
    ID2D1Device *device = nullptr;
    windowDC->GetDevice(&device);
    windowDC->Release();
    if (!device) return nullptr;
    CD2DGlassFrame *f = new CD2DGlassFrame();
    HRESULT hr = device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &f->dc);
    device->Release();
    if (SUCCEEDED(hr)) {
        D2D1_BITMAP_PROPERTIES1 props = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET,
            D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED), 96, 96);
        hr = f->dc->CreateBitmap(D2D1::SizeU(width, height), nullptr, 0, &props, &f->bitmap);
    }
    if (FAILED(hr) || !f->bitmap) { cd2d_glass_frame_release(f); return nullptr; }
    f->dc->SetTarget(f->bitmap);
    f->dc->SetDpi(96, 96);
    f->target = cd2d_target_wrap_native(f->dc);
    if (!f->target) { cd2d_glass_frame_release(f); return nullptr; }
    cd2d_target_begin_draw(f->target);
    cd2d_target_clear(f->target, 0, 0, 0, 0);
    f->drawing = true;
    return f;
}

CD2DTarget *cd2d_glass_frame_target(CD2DGlassFrame *frame) { return frame ? frame->target : nullptr; }

bool cd2d_glass_frame_finish(CD2DGlassFrame *frame) {
    if (!frame || !frame->drawing) return frame != nullptr;
    frame->drawing = false;
    return cd2d_target_end_draw(frame->target);
}

void cd2d_glass_frame_release(CD2DGlassFrame *frame) {
    if (!frame) return;
    if (frame->drawing) cd2d_glass_frame_finish(frame);
    if (frame->target) cd2d_target_release(frame->target);   // releases its reference to dc
    if (frame->bitmap) frame->bitmap->Release();
    if (frame->dc) frame->dc->Release();
    delete frame;
}

bool cd2d_glass_draw_from_frame(CD2DTarget *target, CD2DGlassFrame *frame, bool halved,
                                uint32_t cropX, uint32_t cropY, uint32_t cropWidth, uint32_t cropHeight, int32_t mirrorBelow,
                                uint32_t boxRadius, const float *constants, uint32_t width, uint32_t height) {
    if (gBytecode[kLens].empty() || !target || !frame || !frame->bitmap || frame->drawing || !constants || cropWidth == 0 || cropHeight == 0 || width == 0 || height == 0) return false;
    ID2D1DeviceContext *dc = deviceContext(target);
    if (!dc) return false;
    bool ok = false;
    do {
        GlassGraph *g = graphFor(dc);
        if (!g) break;
        // The frame, halved for a material (the eighth-scale frame is the quarter halved).
        ID2D1Image *source = frame->bitmap;
        ID2D1Image *scaled = nullptr;
        if (halved) {
            g->scale->SetInput(0, frame->bitmap);
            g->scale->GetOutput(&scaled);
            source = scaled;
        }
        // The crop, with the strip below a band's edge mirrored above it: rows [y, E) are
        // rows below E in reverse (y' = 2E - 1 - y for whole rows, a flip about E).
        const float x0 = (float)cropX, y0 = (float)cropY, x1 = x0 + cropWidth, y1 = y0 + cropHeight;
        ID2D1Image *cropped = nullptr;
        if (mirrorBelow > 0 && (uint32_t)mirrorBelow < cropHeight) {
            const float edge = y0 + (float)mirrorBelow;
            g->cropReal->SetInput(0, source);
            g->cropReal->SetValue(D2D1_CROP_PROP_RECT, D2D1::Vector4F(x0, edge, x1, y1));
            g->flip->SetInput(0, source);
            g->flip->SetValue(D2D1_2DAFFINETRANSFORM_PROP_TRANSFORM_MATRIX, D2D1::Matrix3x2F(1, 0, 0, -1, 0, 2 * edge));
            g->cropMirror->SetInputEffect(0, g->flip);
            g->cropMirror->SetValue(D2D1_CROP_PROP_RECT, D2D1::Vector4F(x0, y0, x1, edge));
            g->composite->SetInputEffect(0, g->cropReal);
            g->composite->SetInputEffect(1, g->cropMirror);
            g->composite->GetOutput(&cropped);
        } else {
            g->cropReal->SetInput(0, source);
            g->cropReal->SetValue(D2D1_CROP_PROP_RECT, D2D1::Vector4F(x0, y0, x1, y1));
            g->cropReal->GetOutput(&cropped);
        }
        if (scaled) scaled->Release();
        // Six box passes, across then down three times, the last saturating; or the
        // saturation alone without a blur.
        float k[48] = {};
        k[0] = x0; k[1] = y0; k[2] = (float)cropWidth; k[3] = (float)cropHeight;
        const float saturation = constants[39];
        ID2D1Image *blurred = cropped;
        int passes = boxRadius > 0 ? 6 : (saturation != 1 ? 1 : 0);
        bool failed = false;
        for (int i = 0; i < passes && !failed; i++) {
            k[4] = boxRadius > 0 ? (float)boxRadius : 0;
            k[5] = (i % 2 == 0) ? 1.0f : 0.0f;
            k[6] = (i == passes - 1 && saturation != 1) ? 1.0f : 0.0f;
            k[7] = saturation;
            g->box[i]->SetInput(0, blurred);
            failed = !setBlob(g->box[i], k);
            if (blurred != cropped) blurred->Release();
            g->box[i]->GetOutput(&blurred);
        }
        if (blurred != cropped) cropped->Release();   // else `blurred` holds the reference
        if (failed) { blurred->Release(); break; }
        // The probe and the lens.
        g->luminance->SetInput(0, blurred);
        if (!setBlob(g->luminance, k)) { blurred->Release(); break; }
        g->lens->SetInput(0, blurred);
        g->lens->SetInputEffect(1, g->luminance);
        blurred->Release();
        float lens[48];
        memcpy(lens, constants, sizeof(lens));
        lens[0] = (float)width; lens[1] = (float)height;
        lens[38] = -1;               // probe the luminance
        lens[44] = x0; lens[45] = y0;  // the crop's origin in the effect's space
        if (!setBlob(g->lens, lens)) break;
        drawInPixels(dc, g->lens);
        ok = true;
    } while (false);
    dc->Release();
    return ok;
}

}
