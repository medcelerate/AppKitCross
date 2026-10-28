#include "cd2d.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <string>
#include <vector>
#include <cstring>

struct CD2DFactory { ID2D1Factory *factory = nullptr; };
struct CD2DTarget {
    ID2D1RenderTarget *target = nullptr;          // used for all drawing calls
    ID2D1HwndRenderTarget *hwnd = nullptr;        // non-null for window targets
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

void cd2d_target_release(CD2DTarget *target) {
    if (!target) return;
    safeRelease(target->target);
    target->hwnd = nullptr;
    delete target;
}

void cd2d_target_resize(CD2DTarget *target, uint32_t w, uint32_t h) {
    if (target && target->hwnd) target->hwnd->Resize(D2D1::SizeU(w ? w : 1, h ? h : 1));
}

void cd2d_target_set_dpi(CD2DTarget *target, float dpi) {
    if (target && target->target) target->target->SetDpi(dpi, dpi);
}

void cd2d_target_begin_draw(CD2DTarget *target) {
    if (target && target->target) target->target->BeginDraw();
}

bool cd2d_target_end_draw(CD2DTarget *target) {
    if (!target || !target->target) return false;
    HRESULT hr = target->target->EndDraw();
    return hr != D2DERR_RECREATE_TARGET;
}

void cd2d_target_clear(CD2DTarget *target, float r, float g, float b, float a) {
    if (target && target->target) target->target->Clear(D2D1::ColorF(r, g, b, a));
}

void cd2d_target_set_transform(CD2DTarget *target, const CD2DMatrix *m) {
    if (!target || !target->target || !m) return;
    target->target->SetTransform(D2D1::Matrix3x2F(m->m11, m->m12, m->m21, m->m22, m->dx, m->dy));
}

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

bool cd2d_file_dialog(void *ownerHwnd, const CD2DFileDialogOptions *o, const uint16_t *title, const uint16_t *okLabel,
                      const uint16_t *defaultName, const uint16_t *directory, const uint16_t *extensions,
                      uint16_t **paths, uint32_t *length) {
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
    if (defaultName && defaultName[0]) dlg->SetFileName(reinterpret_cast<LPCWSTR>(defaultName));
    if (directory && directory[0]) {
        IShellItem *folder = nullptr;
        if (SUCCEEDED(SHCreateItemFromParsingName(reinterpret_cast<LPCWSTR>(directory), nullptr, IID_PPV_ARGS(&folder))) && folder) {
            dlg->SetFolder(folder);
            folder->Release();
        }
    }
    std::vector<std::wstring> specs;
    std::vector<COMDLG_FILTERSPEC> filters;
    if (extensions && extensions[0]) {
        std::wstring all(reinterpret_cast<const wchar_t *>(extensions));
        std::wstring pattern;
        size_t start = 0;
        while (start <= all.size()) {
            size_t end = all.find(L';', start);
            if (end == std::wstring::npos) end = all.size();
            std::wstring ext = all.substr(start, end - start);
            if (!ext.empty()) { if (!pattern.empty()) pattern += L";"; pattern += L"*." + ext; }
            start = end + 1;
        }
        std::wstring label = L"Supported files (";
        for (size_t i = 0; i < pattern.size(); i++) label += pattern[i] == L';' ? L", " : std::wstring(1, pattern[i]);
        label += L")";
        specs.push_back(label);
        specs.push_back(pattern);
        filters.push_back({ specs[0].c_str(), specs[1].c_str() });
        if (o->allowsOtherTypes) {
            specs.push_back(L"All files");
            specs.push_back(L"*.*");
            filters.push_back({ specs[2].c_str(), specs[3].c_str() });
        }
        dlg->SetFileTypes((UINT)filters.size(), filters.data());
        if (!o->isSave && !pattern.empty()) {
            size_t dot = pattern.find(L'.');
            if (dot != std::wstring::npos) {
                size_t semi = pattern.find(L';');
                std::wstring first = pattern.substr(dot + 1, (semi == std::wstring::npos ? pattern.size() : semi) - dot - 1);
                dlg->SetDefaultExtension(first.c_str());
            }
        } else if (o->isSave && !pattern.empty()) {
            size_t dot = pattern.find(L'.');
            size_t semi = pattern.find(L';');
            if (dot != std::wstring::npos) dlg->SetDefaultExtension(pattern.substr(dot + 1, (semi == std::wstring::npos ? pattern.size() : semi) - dot - 1).c_str());
        }
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
