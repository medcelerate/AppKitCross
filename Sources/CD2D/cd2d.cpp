#include "cd2d.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <vector>

struct CD2DFactory { ID2D1Factory *factory = nullptr; };
struct CD2DTarget { ID2D1HwndRenderTarget *target = nullptr; };
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
    return r;
}

void cd2d_target_release(CD2DTarget *target) {
    if (!target) return;
    safeRelease(target->target);
    delete target;
}

void cd2d_target_resize(CD2DTarget *target, uint32_t w, uint32_t h) {
    if (target && target->target) target->target->Resize(D2D1::SizeU(w ? w : 1, h ? h : 1));
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
