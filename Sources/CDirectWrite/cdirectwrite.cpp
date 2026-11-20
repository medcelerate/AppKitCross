// DirectWrite shim for the CoreText module (see cdirectwrite.h). Fonts are IDWriteFontFace
// objects at a size; shaping goes through IDWriteTextLayout with a collecting renderer so
// DirectWrite handles scripts and bidi. Font fallback is explicit and per run: the system
// IDWriteFontFallback splits the text by MapCharacters, ranges the primary face lacks are
// pinned to the fallback family, and each resolved face comes back as its own run.

#include "cdirectwrite.h"

#ifdef _WIN32
#define NOMINMAX
#include <windows.h>
#include <dwrite_3.h>
#include <d2d1.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cstring>

namespace {

template <typename T> struct ComPtr {
    T *p = nullptr;
    ComPtr() = default;
    explicit ComPtr(T *raw) : p(raw) {}
    ComPtr(const ComPtr &o) : p(o.p) { if (p) p->AddRef(); }
    ComPtr &operator=(const ComPtr &o) { if (o.p) o.p->AddRef(); if (p) p->Release(); p = o.p; return *this; }
    ~ComPtr() { if (p) p->Release(); }
    T **put() { if (p) { p->Release(); p = nullptr; } return &p; }
    T *operator->() const { return p; }
    explicit operator bool() const { return p != nullptr; }
};

IDWriteFactory *factory() {
    static IDWriteFactory *f = nullptr;
    if (!f) DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(&f));
    return f;
}

IDWriteFontCollection *systemCollection() {
    static IDWriteFontCollection *c = nullptr;
    if (!c && factory()) factory()->GetSystemFontCollection(&c, FALSE);
    return c;
}

std::wstring widen(const char *utf8) {
    if (!utf8) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &w[0], n);
    return w;
}

size_t narrow(const std::wstring &w, char *buf, size_t cap) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
    size_t len = n > 0 ? static_cast<size_t>(n - 1) : 0;
    if (buf && cap > 0) {
        if (len + 1 <= cap) WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, buf, static_cast<int>(cap), nullptr, nullptr);
        else buf[0] = 0;
    }
    return len;
}

std::wstring localizedString(IDWriteLocalizedStrings *strings) {
    if (!strings) return L"";
    UINT32 index = 0;
    BOOL exists = FALSE;
    strings->FindLocaleName(L"en-us", &index, &exists);
    if (!exists) index = 0;
    UINT32 len = 0;
    strings->GetStringLength(index, &len);
    std::wstring s(len + 1, L'\0');
    strings->GetString(index, &s[0], len + 1);
    s.resize(len);
    return s;
}

std::wstring lower(std::wstring s) { std::transform(s.begin(), s.end(), s.begin(), ::towlower); return s; }
std::wstring stripSpaces(const std::wstring &s) { std::wstring o; for (wchar_t c : s) if (c != L' ') o += c; return o; }

} // namespace

struct CDWFont {
    LONG refs = 1;
    ComPtr<IDWriteFontFace> face;
    ComPtr<IDWriteFont> font;           // may be null for fallback faces the collection cannot map back
    float size = 12;
    DWRITE_FONT_METRICS metrics{};
    std::wstring family, style, full, postscript;
    DWRITE_FONT_WEIGHT weight = DWRITE_FONT_WEIGHT_NORMAL;
    DWRITE_FONT_STYLE fontStyle = DWRITE_FONT_STYLE_NORMAL;
    bool monospace = false;

    float scale() const { return metrics.designUnitsPerEm ? size / metrics.designUnitsPerEm : 0; }

    void fillNames() {
        ComPtr<IDWriteFont> f = font;
        if (!f && systemCollection()) systemCollection()->GetFontFromFontFace(face.p, f.put());
        if (f) {
            ComPtr<IDWriteFontFamily> fam;
            if (SUCCEEDED(f->GetFontFamily(fam.put())) && fam) {
                ComPtr<IDWriteLocalizedStrings> names;
                if (SUCCEEDED(fam->GetFamilyNames(names.put()))) family = localizedString(names.p);
            }
            ComPtr<IDWriteLocalizedStrings> faceNames;
            if (SUCCEEDED(f->GetFaceNames(faceNames.put()))) style = localizedString(faceNames.p);
            ComPtr<IDWriteLocalizedStrings> info;
            BOOL exists = FALSE;
            if (SUCCEEDED(f->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_FULL_NAME, info.put(), &exists)) && exists) full = localizedString(info.p);
            if (SUCCEEDED(f->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME, info.put(), &exists)) && exists) postscript = localizedString(info.p);
            weight = f->GetWeight();
            fontStyle = f->GetStyle();
            if (!font) font = f;
        } else {
            // Fallback faces picked by IDWriteTextLayout can come from outside the system
            // collection (GetFontFromFontFace fails with DWRITE_E_NOFONT); IDWriteFontFace3
            // carries the names and traits itself.
            ComPtr<IDWriteFontFace3> face3;
            if (SUCCEEDED(face->QueryInterface(__uuidof(IDWriteFontFace3), reinterpret_cast<void **>(face3.put()))) && face3) {
                ComPtr<IDWriteLocalizedStrings> names;
                if (SUCCEEDED(face3->GetFamilyNames(names.put()))) family = localizedString(names.p);
                ComPtr<IDWriteLocalizedStrings> faceNames;
                if (SUCCEEDED(face3->GetFaceNames(faceNames.put()))) style = localizedString(faceNames.p);
                ComPtr<IDWriteLocalizedStrings> info;
                BOOL exists = FALSE;
                if (SUCCEEDED(face3->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_FULL_NAME, info.put(), &exists)) && exists) full = localizedString(info.p);
                if (SUCCEEDED(face3->GetInformationalStrings(DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME, info.put(), &exists)) && exists) postscript = localizedString(info.p);
                weight = face3->GetWeight();
                fontStyle = face3->GetStyle();
            }
        }
        if (style.empty()) style = L"Regular";
        if (full.empty()) full = family + L" " + style;
        if (postscript.empty()) postscript = stripSpaces(family) + L"-" + stripSpaces(style);
        face->GetMetrics(&metrics);
        // Monospace: compare the advances of a few glyphs.
        UINT32 cps[3] = { 'i', 'm', 'W' };
        UINT16 g[3] = {};
        if (SUCCEEDED(face->GetGlyphIndices(cps, 3, g)) && g[0] && g[1] && g[2]) {
            DWRITE_GLYPH_METRICS gm[3] = {};
            if (SUCCEEDED(face->GetDesignGlyphMetrics(g, 3, gm, FALSE))) monospace = gm[0].advanceWidth == gm[1].advanceWidth && gm[1].advanceWidth == gm[2].advanceWidth;
        }
    }
};

extern "C" {

CDWFont *cdw_font_create(const char *nameUTF8, float size, int weight, bool italic, bool monospace, bool *found) {
    if (found) *found = false;
    IDWriteFontCollection *coll = systemCollection();
    if (!coll) return nullptr;
    std::wstring family;
    int styleWeight = 0;
    bool styleItalic = false;
    if (!nameUTF8) {
        family = monospace ? L"Consolas" : L"Segoe UI";
    } else {
        std::wstring name = widen(nameUTF8);
        std::wstring base = name, styleText;
        size_t dash = name.find(L'-');
        if (dash != std::wstring::npos) { base = name.substr(0, dash); styleText = lower(name.substr(dash + 1)); }
        // Exact family, then a spaceless match (PostScript-style names), then trailing style words.
        UINT32 index = 0; BOOL exists = FALSE;
        coll->FindFamilyName(base.c_str(), &index, &exists);
        if (!exists) {
            std::wstring want = lower(stripSpaces(base));
            UINT32 count = coll->GetFontFamilyCount();
            for (UINT32 i = 0; i < count && !exists; i++) {
                ComPtr<IDWriteFontFamily> fam;
                if (FAILED(coll->GetFontFamily(i, fam.put()))) continue;
                ComPtr<IDWriteLocalizedStrings> names;
                if (FAILED(fam->GetFamilyNames(names.put()))) continue;
                std::wstring fname = localizedString(names.p);
                std::wstring key = lower(stripSpaces(fname));
                if (key == want) { family = fname; exists = TRUE; break; }
                if (want.size() > key.size() && want.compare(0, key.size(), key) == 0) {
                    // "SegoeUIBold": family prefix plus a style word.
                    styleText = want.substr(key.size());
                    family = fname; exists = TRUE; break;
                }
            }
            if (!exists) return nullptr;
        } else {
            family = base;
        }
        if (styleText.find(L"bold") != std::wstring::npos) styleWeight = DWRITE_FONT_WEIGHT_BOLD;
        else if (styleText.find(L"semibold") != std::wstring::npos || styleText.find(L"demibold") != std::wstring::npos) styleWeight = DWRITE_FONT_WEIGHT_SEMI_BOLD;
        else if (styleText.find(L"light") != std::wstring::npos) styleWeight = DWRITE_FONT_WEIGHT_LIGHT;
        else if (styleText.find(L"black") != std::wstring::npos || styleText.find(L"heavy") != std::wstring::npos) styleWeight = DWRITE_FONT_WEIGHT_BLACK;
        else if (styleText.find(L"medium") != std::wstring::npos) styleWeight = DWRITE_FONT_WEIGHT_MEDIUM;
        if (styleText.find(L"italic") != std::wstring::npos || styleText.find(L"oblique") != std::wstring::npos) styleItalic = true;
    }
    UINT32 index = 0; BOOL exists = FALSE;
    if (FAILED(coll->FindFamilyName(family.c_str(), &index, &exists)) || !exists) return nullptr;
    ComPtr<IDWriteFontFamily> fam;
    if (FAILED(coll->GetFontFamily(index, fam.put()))) return nullptr;
    DWRITE_FONT_WEIGHT w = static_cast<DWRITE_FONT_WEIGHT>(weight > 0 ? weight : (styleWeight > 0 ? styleWeight : DWRITE_FONT_WEIGHT_NORMAL));
    DWRITE_FONT_STYLE st = (italic || styleItalic) ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL;
    ComPtr<IDWriteFont> font;
    if (FAILED(fam->GetFirstMatchingFont(w, DWRITE_FONT_STRETCH_NORMAL, st, font.put()))) return nullptr;
    ComPtr<IDWriteFontFace> face;
    if (FAILED(font->CreateFontFace(face.put()))) return nullptr;
    CDWFont *f = new CDWFont();
    f->face = face;
    f->font = font;
    f->size = size;
    f->fillNames();
    if (found) *found = true;
    return f;
}

CDWFont *cdw_font_retain(CDWFont *font) { if (font) InterlockedIncrement(&font->refs); return font; }
void cdw_font_release(CDWFont *font) { if (font && InterlockedDecrement(&font->refs) == 0) delete font; }

CDWFont *cdw_font_with_size(CDWFont *font, float size) {
    if (!font) return nullptr;
    CDWFont *f = new CDWFont();
    f->face = font->face; f->font = font->font; f->size = size;
    f->metrics = font->metrics; f->family = font->family; f->style = font->style; f->full = font->full; f->postscript = font->postscript;
    f->weight = font->weight; f->fontStyle = font->fontStyle; f->monospace = font->monospace;
    return f;
}

float cdw_font_size(CDWFont *font) { return font ? font->size : 0; }

void cdw_font_metrics(CDWFont *font, CDWFontMetrics *out) {
    if (!font || !out) return;
    float s = font->scale();
    const DWRITE_FONT_METRICS &m = font->metrics;
    out->ascent = m.ascent * s;
    out->descent = m.descent * s;
    out->lineGap = m.lineGap * s;
    out->capHeight = (m.capHeight ? m.capHeight : m.ascent * 0.7f) * s;
    out->xHeight = (m.xHeight ? m.xHeight : m.ascent * 0.5f) * s;
    out->underlinePosition = m.underlinePosition * s;     // DirectWrite: negative below the baseline
    out->underlineThickness = m.underlineThickness * s;
    out->unitsPerEm = m.designUnitsPerEm;
    out->glyphCount = font->face->GetGlyphCount();
    out->weight = font->weight;
    out->isBold = font->weight >= DWRITE_FONT_WEIGHT_SEMI_BOLD;
    out->isItalic = font->fontStyle != DWRITE_FONT_STYLE_NORMAL;
    out->isMonospace = font->monospace;
}

size_t cdw_font_name(CDWFont *font, int which, char *buf, size_t capacity) {
    if (!font) return 0;
    const std::wstring *s = which == 0 ? &font->family : which == 1 ? &font->style : which == 2 ? &font->full : &font->postscript;
    return narrow(*s, buf, capacity);
}

void cdw_font_glyphs(CDWFont *font, const uint32_t *codepoints, uint32_t count, uint16_t *glyphs) {
    if (!font || !count) return;
    if (FAILED(font->face->GetGlyphIndices(codepoints, count, glyphs))) for (uint32_t i = 0; i < count; i++) glyphs[i] = 0;
}

void cdw_font_advances(CDWFont *font, const uint16_t *glyphs, uint32_t count, float *advances) {
    if (!font || !count) return;
    std::vector<DWRITE_GLYPH_METRICS> gm(count);
    float s = font->scale();
    if (SUCCEEDED(font->face->GetDesignGlyphMetrics(glyphs, count, gm.data(), FALSE))) {
        for (uint32_t i = 0; i < count; i++) advances[i] = gm[i].advanceWidth * s;
    } else {
        for (uint32_t i = 0; i < count; i++) advances[i] = 0;
    }
}

void cdw_font_bounds(CDWFont *font, const uint16_t *glyphs, uint32_t count, float *rects) {
    if (!font || !count) return;
    std::vector<DWRITE_GLYPH_METRICS> gm(count);
    float s = font->scale();
    if (FAILED(font->face->GetDesignGlyphMetrics(glyphs, count, gm.data(), FALSE))) { for (uint32_t i = 0; i < count * 4; i++) rects[i] = 0; return; }
    for (uint32_t i = 0; i < count; i++) {
        const DWRITE_GLYPH_METRICS &g = gm[i];
        float x = g.leftSideBearing * s;
        float w = (static_cast<float>(g.advanceWidth) - g.leftSideBearing - g.rightSideBearing) * s;
        float top = (static_cast<float>(g.verticalOriginY) - g.topSideBearing) * s;
        float h = (static_cast<float>(g.advanceHeight) - g.topSideBearing - g.bottomSideBearing) * s;
        rects[i * 4] = x; rects[i * 4 + 1] = top - h; rects[i * 4 + 2] = w; rects[i * 4 + 3] = h;
    }
}

namespace {
// Collects a glyph outline from GetGlyphRunOutline (y down → flipped to y up).
struct PathSinkImpl final : ID2D1SimplifiedGeometrySink {
    CDWPathSink sink; void *context; LONG refs = 1;
    PathSinkImpl(CDWPathSink s, void *c) : sink(s), context(c) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **out) noexcept override {
        if (riid == __uuidof(IUnknown) || riid == __uuidof(ID2D1SimplifiedGeometrySink)) { *out = this; AddRef(); return S_OK; }
        *out = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() noexcept override { ULONG r = InterlockedDecrement(&refs); if (!r) delete this; return r; }
    void STDMETHODCALLTYPE SetFillMode(D2D1_FILL_MODE) noexcept override {}
    void STDMETHODCALLTYPE SetSegmentFlags(D2D1_PATH_SEGMENT) noexcept override {}
    void STDMETHODCALLTYPE BeginFigure(D2D1_POINT_2F p, D2D1_FIGURE_BEGIN) noexcept override { sink(context, 0, p.x, -p.y, 0, 0, 0, 0); }
    void STDMETHODCALLTYPE AddLines(const D2D1_POINT_2F *pts, UINT32 n) noexcept override { for (UINT32 i = 0; i < n; i++) sink(context, 1, pts[i].x, -pts[i].y, 0, 0, 0, 0); }
    void STDMETHODCALLTYPE AddBeziers(const D2D1_BEZIER_SEGMENT *b, UINT32 n) noexcept override {
        for (UINT32 i = 0; i < n; i++) sink(context, 2, b[i].point1.x, -b[i].point1.y, b[i].point2.x, -b[i].point2.y, b[i].point3.x, -b[i].point3.y);
    }
    void STDMETHODCALLTYPE EndFigure(D2D1_FIGURE_END) noexcept override { sink(context, 3, 0, 0, 0, 0, 0, 0); }
    HRESULT STDMETHODCALLTYPE Close() noexcept override { return S_OK; }
};
}

bool cdw_font_glyph_path(CDWFont *font, uint16_t glyph, CDWPathSink sink, void *context) {
    if (!font) return false;
    PathSinkImpl *impl = new PathSinkImpl(sink, context);
    HRESULT hr = font->face->GetGlyphRunOutline(font->size, &glyph, nullptr, nullptr, 1, FALSE, FALSE, impl);
    impl->Release();
    return SUCCEEDED(hr);
}

bool cdw_font_table(CDWFont *font, uint32_t tag, const void **data, uint32_t *size, void **context) {
    if (!font) return false;
    BOOL exists = FALSE;
    // DirectWrite tags are little-endian packed characters; ours are big-endian four-char codes.
    UINT32 dwTag = ((tag & 0xFF) << 24) | ((tag & 0xFF00) << 8) | ((tag & 0xFF0000) >> 8) | (tag >> 24);
    HRESULT hr = font->face->TryGetFontTable(dwTag, data, size, context, &exists);
    return SUCCEEDED(hr) && exists;
}

void cdw_font_table_release(CDWFont *font, void *context) { if (font && context) font->face->ReleaseFontTable(context); }

bool cdw_draw_glyphs(CD2DTarget *target, CDWFont *font, const uint16_t *glyphs, const float *positionsXY, uint32_t count, float r, float g, float b, float a) {
    ID2D1RenderTarget *rt = static_cast<ID2D1RenderTarget *>(cd2d_target_render_target(target));
    if (!rt || !font || !font->face || !glyphs || !positionsXY) return false;
    if (count == 0) return true;
    ComPtr<ID2D1SolidColorBrush> brush;
    if (FAILED(rt->CreateSolidColorBrush(D2D1::ColorF(r, g, b, a), brush.put())) || !brush) return false;
    // The context's user space is y up; DirectWrite draws y down. Flip the y axis in front of
    // the current transform (the same flip the outline sink applies) and place each glyph by
    // offset: a glyph at user (x, y) sits at (x, -y) in the flipped space, which is an
    // ascender offset of +y. Advances are zero so every glyph is positioned absolutely.
    D2D1_MATRIX_3X2_F current;
    rt->GetTransform(&current);
    rt->SetTransform(D2D1::Matrix3x2F(1, 0, 0, -1, 0, 0) * current);
    std::vector<float> advances(count, 0.0f);
    std::vector<DWRITE_GLYPH_OFFSET> offsets(count);
    for (uint32_t i = 0; i < count; i++) {
        offsets[i].advanceOffset = positionsXY[i * 2];
        offsets[i].ascenderOffset = positionsXY[i * 2 + 1];
    }
    DWRITE_GLYPH_RUN run{};
    run.fontFace = font->face.p;
    run.fontEmSize = font->size;
    run.glyphCount = count;
    run.glyphIndices = glyphs;
    run.glyphAdvances = advances.data();
    run.glyphOffsets = offsets.data();
    run.isSideways = FALSE;
    run.bidiLevel = 0;
    rt->DrawGlyphRun(D2D1::Point2F(0, 0), &run, brush.p, DWRITE_MEASURING_MODE_NATURAL);
    rt->SetTransform(current);
    return true;
}

uint32_t cdw_family_count(void) { IDWriteFontCollection *c = systemCollection(); return c ? c->GetFontFamilyCount() : 0; }

size_t cdw_family_name(uint32_t index, char *buf, size_t capacity) {
    IDWriteFontCollection *c = systemCollection();
    if (!c) return 0;
    ComPtr<IDWriteFontFamily> fam;
    if (FAILED(c->GetFontFamily(index, fam.put()))) return 0;
    ComPtr<IDWriteLocalizedStrings> names;
    if (FAILED(fam->GetFamilyNames(names.put()))) return 0;
    return narrow(localizedString(names.p), buf, capacity);
}

// MARK: Shaping

struct CDWShapedRun {
    CDWFont *font;
    uint32_t textStart, textLength;
    std::vector<uint16_t> glyphs;
    std::vector<float> advances;
    std::vector<float> offsets;
    std::vector<uint32_t> clusters;
    bool rtl;
};

struct CDWShaped {
    std::vector<CDWShapedRun> runs;
    ~CDWShaped() { for (auto &r : runs) cdw_font_release(r.font); }
};

namespace {
// Whether two font face objects are the same face: the layout creates its own
// IDWriteFontFace for the base font, so pointer identity is not enough.
bool sameFace(IDWriteFontFace *a, IDWriteFontFace *b) {
    if (a == b) return true;
    if (!a || !b) return false;
    if (a->GetIndex() != b->GetIndex() || a->GetSimulations() != b->GetSimulations()) return false;
    UINT32 na = 0, nb = 0;
    if (FAILED(a->GetFiles(&na, nullptr)) || FAILED(b->GetFiles(&nb, nullptr)) || na != nb || na == 0) return false;
    std::vector<IDWriteFontFile *> fa(na, nullptr), fb(nb, nullptr);
    bool same = SUCCEEDED(a->GetFiles(&na, fa.data())) && SUCCEEDED(b->GetFiles(&nb, fb.data()));
    for (UINT32 i = 0; same && i < na; i++) {
        const void *ka = nullptr, *kb = nullptr; UINT32 la = 0, lb = 0;
        IDWriteFontFileLoader *loaderA = nullptr, *loaderB = nullptr;
        same = SUCCEEDED(fa[i]->GetReferenceKey(&ka, &la)) && SUCCEEDED(fb[i]->GetReferenceKey(&kb, &lb)) && la == lb && memcmp(ka, kb, la) == 0
            && SUCCEEDED(fa[i]->GetLoader(&loaderA)) && SUCCEEDED(fb[i]->GetLoader(&loaderB)) && loaderA == loaderB;
        if (loaderA) loaderA->Release();
        if (loaderB) loaderB->Release();
    }
    for (auto *f : fa) if (f) f->Release();
    for (auto *f : fb) if (f) f->Release();
    return same;
}

struct CollectingRenderer final : IDWriteTextRenderer {
    LONG refs = 1;
    CDWShaped *out;
    CDWFont *base;
    explicit CollectingRenderer(CDWShaped *o, CDWFont *b) : out(o), base(b) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **o) noexcept override {
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWritePixelSnapping) || riid == __uuidof(IDWriteTextRenderer)) { *o = this; AddRef(); return S_OK; }
        *o = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() noexcept override { ULONG r = InterlockedDecrement(&refs); if (!r) delete this; return r; }
    HRESULT STDMETHODCALLTYPE IsPixelSnappingDisabled(void *, BOOL *disabled) noexcept override { *disabled = TRUE; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetCurrentTransform(void *, DWRITE_MATRIX *m) noexcept override { *m = DWRITE_MATRIX{1, 0, 0, 1, 0, 0}; return S_OK; }
    HRESULT STDMETHODCALLTYPE GetPixelsPerDip(void *, FLOAT *ppd) noexcept override { *ppd = 1; return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawGlyphRun(void *, FLOAT, FLOAT, DWRITE_MEASURING_MODE, const DWRITE_GLYPH_RUN *run,
                                           const DWRITE_GLYPH_RUN_DESCRIPTION *desc, IUnknown *) noexcept override {
        CDWShapedRun r;
        if (sameFace(run->fontFace, base->face.p)) {
            r.font = cdw_font_retain(base);
        } else {
            CDWFont *f = new CDWFont();
            f->face = ComPtr<IDWriteFontFace>(run->fontFace); run->fontFace->AddRef();
            f->size = run->fontEmSize;
            f->fillNames();
            r.font = f;
        }
        r.textStart = desc->textPosition;
        r.textLength = desc->stringLength;
        r.rtl = (run->bidiLevel & 1) != 0;
        for (UINT32 i = 0; i < run->glyphCount; i++) {
            r.glyphs.push_back(run->glyphIndices[i]);
            r.advances.push_back(run->glyphAdvances ? run->glyphAdvances[i] : 0);
            r.offsets.push_back(run->glyphOffsets ? run->glyphOffsets[i].advanceOffset : 0);
            r.offsets.push_back(run->glyphOffsets ? run->glyphOffsets[i].ascenderOffset : 0);
        }
        // clusterMap: text index → first glyph of its cluster. Invert to glyph → cluster start
        // (text index). Glyphs are in visual order: for LTR a cluster's glyphs run up to the
        // next cluster's first glyph, for RTL up to the previous cluster's (in text order).
        r.clusters.assign(run->glyphCount, 0);
        std::vector<std::pair<UINT32, UINT32>> starts;   // (text index, glyph index) per cluster
        for (UINT32 t = 0; t < desc->stringLength; t++) {
            if (t == 0 || desc->clusterMap[t - 1] != desc->clusterMap[t]) starts.emplace_back(t, desc->clusterMap[t]);
        }
        for (size_t c = 0; c < starts.size(); c++) {
            UINT32 g = starts[c].second;
            UINT32 end = run->glyphCount;
            if (!r.rtl && c + 1 < starts.size()) end = starts[c + 1].second;
            if (r.rtl && c > 0) end = starts[c - 1].second;
            for (UINT32 k = g; k < end && k < run->glyphCount; k++) r.clusters[k] = starts[c].first;
        }
        out->runs.push_back(std::move(r));
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE DrawUnderline(void *, FLOAT, FLOAT, const DWRITE_UNDERLINE *, IUnknown *) noexcept override { return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawStrikethrough(void *, FLOAT, FLOAT, const DWRITE_STRIKETHROUGH *, IUnknown *) noexcept override { return S_OK; }
    HRESULT STDMETHODCALLTYPE DrawInlineObject(void *, FLOAT, FLOAT, IDWriteInlineObject *, BOOL, BOOL, IUnknown *) noexcept override { return S_OK; }
};
}

} // extern "C"

namespace {

// MARK: Per-run font fallback
//
// The layout's own fallback is not left implicit: the text is first split into runs with
// the system IDWriteFontFallback (MapCharacters), each run whose characters the primary
// face lacks is pinned to the family DirectWrite picks for it (SetFontFamilyName and
// SetFontCollection on that range), and the layout is told to use the system fallback for
// anything left (IDWriteTextLayout2::SetFontFallback). The renderer then hands back one glyph
// run per resolved face, and those runs (glyphs, advances, offsets) are what the CoreText
// layer both measures and draws, so widths and ink always come from the same face.

IDWriteFontFallback *systemFallback() {
    static IDWriteFontFallback *fb = nullptr;
    static bool tried = false;
    if (!tried && factory()) {
        tried = true;
        ComPtr<IDWriteFactory2> f2;
        if (SUCCEEDED(factory()->QueryInterface(__uuidof(IDWriteFactory2), reinterpret_cast<void **>(f2.put()))) && f2)
            f2->GetSystemFontFallback(&fb);
    }
    return fb;
}

// The text MapCharacters reads: one left-to-right paragraph in one locale.
struct FallbackSource final : IDWriteTextAnalysisSource {
    LONG refs = 1;
    const WCHAR *text; UINT32 length; std::wstring locale;
    FallbackSource(const WCHAR *t, UINT32 n, std::wstring l) : text(t), length(n), locale(std::move(l)) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **o) noexcept override {
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IDWriteTextAnalysisSource)) { *o = this; AddRef(); return S_OK; }
        *o = nullptr; return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() noexcept override { return InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() noexcept override { ULONG r = InterlockedDecrement(&refs); if (!r) delete this; return r; }
    HRESULT STDMETHODCALLTYPE GetTextAtPosition(UINT32 pos, WCHAR const **s, UINT32 *n) noexcept override {
        if (pos >= length) { *s = nullptr; *n = 0; } else { *s = text + pos; *n = length - pos; }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetTextBeforePosition(UINT32 pos, WCHAR const **s, UINT32 *n) noexcept override {
        if (pos == 0 || pos > length) { *s = nullptr; *n = 0; } else { *s = text; *n = pos; }
        return S_OK;
    }
    DWRITE_READING_DIRECTION STDMETHODCALLTYPE GetParagraphReadingDirection() noexcept override { return DWRITE_READING_DIRECTION_LEFT_TO_RIGHT; }
    HRESULT STDMETHODCALLTYPE GetLocaleName(UINT32 pos, UINT32 *n, WCHAR const **name) noexcept override {
        *n = pos < length ? length - pos : 0; *name = locale.c_str(); return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetNumberSubstitution(UINT32 pos, UINT32 *n, IDWriteNumberSubstitution **sub) noexcept override {
        *n = pos < length ? length - pos : 0; *sub = nullptr; return S_OK;
    }
};

// A text range pinned to a fallback family.
struct FallbackRun {
    UINT32 start, length;
    std::wstring family;
    ComPtr<IDWriteFontCollection> collection;
    float scale;
};

// Characters that are not expected to have ink of their own (controls, spaces, joiners,
// variation selectors, bidi and other format characters): their glyph 0 is not a miss.
bool isInkless(UINT32 c) {
    if (c < 0x21 || (c >= 0x7F && c <= 0xA0)) return true;
    if (c == 0xAD || c == 0x034F || c == 0x061C || c == 0x115F || c == 0x1160 || c == 0x180E || c == 0x3000 || c == 0x3164 || c == 0xFEFF) return true;
    if ((c >= 0x2000 && c <= 0x200F) || (c >= 0x2028 && c <= 0x202F) || (c >= 0x205F && c <= 0x206F)) return true;
    if ((c >= 0xFE00 && c <= 0xFE0F) || (c >= 0xFFF0 && c <= 0xFFFC) || (c >= 0xE0000 && c <= 0xE0FFF)) return true;
    return false;
}

UINT32 codePointAt(const WCHAR *t, UINT32 n, UINT32 i, UINT32 *width) {
    UINT32 u = static_cast<uint16_t>(t[i]);
    *width = 1;
    if (u >= 0xD800 && u <= 0xDBFF && i + 1 < n) {
        UINT32 v = static_cast<uint16_t>(t[i + 1]);
        if (v >= 0xDC00 && v <= 0xDFFF) { *width = 2; return 0x10000 + ((u - 0xD800) << 10) + (v - 0xDC00); }
    }
    return u;
}

bool familyIs(IDWriteFont *font, const std::wstring &family, std::wstring *name, ComPtr<IDWriteFontCollection> *collection) {
    ComPtr<IDWriteFontFamily> fam;
    if (FAILED(font->GetFontFamily(fam.put())) || !fam) return true;     // unknown: leave the range to the layout
    ComPtr<IDWriteLocalizedStrings> names;
    if (SUCCEEDED(fam->GetFamilyNames(names.put()))) *name = localizedString(names.p);
    fam->GetFontCollection(collection->put());
    return name->empty() || lower(*name) == lower(family);
}

// Maps `start..<start+length` with the system fallback and appends a run for every stretch
// it resolves to a family other than `primary`. `base` is the family MapCharacters tries first
// (nullptr: the fallback chain only, for characters the primary face is known to lack).
void mapRange(IDWriteFontFallback *fb, FallbackSource *src, UINT32 start, UINT32 length, const WCHAR *base,
              const std::wstring &primary, const CDWFont *font, std::vector<FallbackRun> &out) {
    UINT32 pos = start, end = start + length;
    while (pos < end) {
        UINT32 mapped = 0;
        ComPtr<IDWriteFont> mappedFont;
        FLOAT scale = 1;
        if (FAILED(fb->MapCharacters(src, pos, end - pos, systemCollection(), base, font->weight, font->fontStyle,
                                     DWRITE_FONT_STRETCH_NORMAL, &mapped, mappedFont.put(), &scale)) || mapped == 0) break;
        if (mappedFont) {
            std::wstring name;
            ComPtr<IDWriteFontCollection> coll;
            if (!familyIs(mappedFont.p, primary, &name, &coll)) out.push_back(FallbackRun{pos, mapped, name, coll, scale > 0 ? scale : 1});
        }
        pos += mapped;
    }
}

// The fallback runs for `text`: MapCharacters from the primary family, then, for inked
// characters the primary face itself has no glyph for (index 0) and that the first pass left
// on the primary family, MapCharacters again from the fallback chain alone.
std::vector<FallbackRun> fallbackRuns(const WCHAR *text, UINT32 count, CDWFont *font, const std::wstring &locale) {
    std::vector<FallbackRun> runs;
    IDWriteFontFallback *fb = systemFallback();
    if (!fb || !systemCollection()) return runs;
    FallbackSource *src = new FallbackSource(text, count, locale);
    mapRange(fb, src, 0, count, font->family.c_str(), font->family, font, runs);
    // Characters still on the primary face: check its cmap.
    std::vector<bool> covered(count, false);
    for (const FallbackRun &r : runs) for (UINT32 i = r.start; i < r.start + r.length && i < count; i++) covered[i] = true;
    std::vector<FallbackRun> extra;
    UINT32 i = 0;
    while (i < count) {
        UINT32 w = 1;
        UINT32 c = codePointAt(text, count, i, &w);
        bool missing = false;
        if (!covered[i] && !isInkless(c)) {
            UINT16 g = 0;
            missing = SUCCEEDED(font->face->GetGlyphIndices(&c, 1, &g)) && g == 0;
        }
        if (!missing) { i += w; continue; }
        // A stretch of missing characters, with the joiners and selectors between them
        // (an emoji ZWJ sequence stays one stretch); trailing inkless ones stay primary.
        UINT32 s = i, last = i;
        while (i < count) {
            UINT32 cw = 1;
            UINT32 cc = codePointAt(text, count, i, &cw);
            if (covered[i]) break;
            UINT16 g = 0;
            bool inkless = isInkless(cc);
            bool miss = inkless || (SUCCEEDED(font->face->GetGlyphIndices(&cc, 1, &g)) && g == 0);
            if (!miss) break;
            i += cw;
            if (!inkless || cc == 0x200D || (cc >= 0xFE00 && cc <= 0xFE0F) || (cc >= 0xE0000 && cc <= 0xE0FFF)) last = i;
        }
        mapRange(fb, src, s, last - s, nullptr, font->family, font, extra);
        i = last;
    }
    src->Release();
    runs.insert(runs.end(), extra.begin(), extra.end());
    std::sort(runs.begin(), runs.end(), [](const FallbackRun &a, const FallbackRun &b) { return a.start < b.start; });
    return runs;
}

} // namespace

extern "C" {

CDWShaped *cdw_shape(const uint16_t *text, uint32_t count, CDWFont *font, const char *localeUTF8) {
    if (!font || !count || !factory()) return nullptr;
    std::wstring locale = localeUTF8 ? widen(localeUTF8) : L"en-us";
    if (locale.empty()) locale = L"en-us";
    DWRITE_FONT_WEIGHT w = font->weight;
    DWRITE_FONT_STYLE st = font->fontStyle;
    const WCHAR *wtext = reinterpret_cast<const WCHAR *>(text);
    ComPtr<IDWriteTextFormat> format;
    if (FAILED(factory()->CreateTextFormat(font->family.c_str(), nullptr, w, st, DWRITE_FONT_STRETCH_NORMAL, font->size, locale.c_str(), format.put()))) return nullptr;
    format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    ComPtr<IDWriteTextLayout> layout;
    if (FAILED(factory()->CreateTextLayout(wtext, count, format.p, 1e7f, 1e7f, layout.put()))) return nullptr;
    // Per-run fallback (see fallbackRuns): pin each run the primary face cannot show to the
    // family the system fallback picks, and keep the system fallback for whatever remains.
    if (IDWriteFontFallback *fb = systemFallback()) {
        ComPtr<IDWriteTextLayout2> layout2;
        if (SUCCEEDED(layout->QueryInterface(__uuidof(IDWriteTextLayout2), reinterpret_cast<void **>(layout2.put()))) && layout2)
            layout2->SetFontFallback(fb);
    }
    for (const FallbackRun &r : fallbackRuns(wtext, count, font, locale)) {
        DWRITE_TEXT_RANGE range{r.start, r.length};
        if (r.collection) layout->SetFontCollection(r.collection.p, range);
        layout->SetFontFamilyName(r.family.c_str(), range);
        if (r.scale != 1) layout->SetFontSize(font->size * r.scale, range);
    }
    CDWShaped *shaped = new CDWShaped();
    CollectingRenderer *renderer = new CollectingRenderer(shaped, font);
    HRESULT hr = layout->Draw(nullptr, renderer, 0, 0);
    renderer->Release();
    if (FAILED(hr)) { delete shaped; return nullptr; }
    std::sort(shaped->runs.begin(), shaped->runs.end(), [](const CDWShapedRun &a, const CDWShapedRun &b) { return a.textStart < b.textStart; });
    return shaped;
}

uint32_t cdw_shaped_run_count(CDWShaped *shaped) { return shaped ? static_cast<uint32_t>(shaped->runs.size()) : 0; }

bool cdw_shaped_run(CDWShaped *shaped, uint32_t index, CDWRun *out) {
    if (!shaped || !out || index >= shaped->runs.size()) return false;
    const CDWShapedRun &r = shaped->runs[index];
    out->font = r.font;
    out->textStart = r.textStart;
    out->textLength = r.textLength;
    out->glyphCount = static_cast<uint32_t>(r.glyphs.size());
    out->glyphs = r.glyphs.data();
    out->advances = r.advances.data();
    out->offsets = r.offsets.data();
    out->clusters = r.clusters.data();
    out->rightToLeft = r.rtl;
    return true;
}

void cdw_shaped_release(CDWShaped *shaped) { delete shaped; }

} // extern "C"

#else
// Not Windows: the target is only declared on Windows, but keep the unit translatable.
extern "C" {
CDWFont *cdw_font_create(const char *, float, int, bool, bool, bool *found) { if (found) *found = false; return nullptr; }
}
#endif
