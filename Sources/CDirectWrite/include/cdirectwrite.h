// extern "C" shim over DirectWrite for the CoreText module (ADR-0007): fonts by name,
// metrics, glyph mapping and metrics, outlines, tables, and shaping with fallback through
// IDWriteTextLayout. All sizes are DIPs (= points at scale 1); y grows up in the values
// returned here (DirectWrite's y-down numbers are flipped inside the shim).

#ifndef CDIRECTWRITE_H
#define CDIRECTWRITE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CDWFont CDWFont;
typedef struct CDWShaped CDWShaped;

typedef struct CDWFontMetrics {
    float ascent;              // positive
    float descent;             // positive
    float lineGap;
    float capHeight;
    float xHeight;
    float underlinePosition;   // negative below the baseline
    float underlineThickness;
    uint32_t unitsPerEm;
    uint16_t glyphCount;
    bool isBold;
    bool isItalic;
    bool isMonospace;
    int weight;                // DWRITE_FONT_WEIGHT (100..999)
} CDWFontMetrics;

/// A font by family name ("Segoe UI"), PostScript-style name ("SegoeUI-Bold") or face
/// name; `name` NULL gives the UI font (`monospace` picks the fixed-pitch one). `weight`
/// 0 keeps the name's or regular, otherwise a DWRITE_FONT_WEIGHT. Returns NULL when the
/// name matches no installed family (`found` false) or DirectWrite fails.
CDWFont *cdw_font_create(const char *nameUTF8, float size, int weight, bool italic, bool monospace, bool *found);
CDWFont *cdw_font_retain(CDWFont *font);
void cdw_font_release(CDWFont *font);
CDWFont *cdw_font_with_size(CDWFont *font, float size);
float cdw_font_size(CDWFont *font);
void cdw_font_metrics(CDWFont *font, CDWFontMetrics *out);
/// which: 0 family, 1 style, 2 full, 3 PostScript. Returns the UTF-8 length (excluding NUL).
size_t cdw_font_name(CDWFont *font, int which, char *buf, size_t capacity);

/// Glyph indices for Unicode scalars (0 for unmapped).
void cdw_font_glyphs(CDWFont *font, const uint32_t *codepoints, uint32_t count, uint16_t *glyphs);
/// Horizontal advances in DIPs.
void cdw_font_advances(CDWFont *font, const uint16_t *glyphs, uint32_t count, float *advances);
/// Ink bounds per glyph as x, y, width, height (4 floats per glyph; y up, origin at the baseline).
void cdw_font_bounds(CDWFont *font, const uint16_t *glyphs, uint32_t count, float *rects);
/// Outline callbacks: op 0 move(x1,y1), 1 line(x1,y1), 2 cubic(c1=x1,y1 c2=x2,y2 end=x3,y3), 3 close.
typedef void (*CDWPathSink)(void *context, int op, float x1, float y1, float x2, float y2, float x3, float y3);
bool cdw_font_glyph_path(CDWFont *font, uint16_t glyph, CDWPathSink sink, void *context);
/// Raw table bytes (valid until cdw_font_table_release with the same `context`).
bool cdw_font_table(CDWFont *font, uint32_t tag, const void **data, uint32_t *size, void **context);
void cdw_font_table_release(CDWFont *font, void *context);

/// Installed family names.
uint32_t cdw_family_count(void);
size_t cdw_family_name(uint32_t index, char *buf, size_t capacity);

/// Shapes UTF-16 text in `font` with DirectWrite's fallback and bidi handling (no wrapping).
CDWShaped *cdw_shape(const uint16_t *text, uint32_t count, CDWFont *font, const char *localeUTF8);
uint32_t cdw_shaped_run_count(CDWShaped *shaped);
typedef struct CDWRun {
    CDWFont *font;             // borrowed from the shaped object (retain to keep)
    uint32_t textStart;        // UTF-16 index into the shaped text
    uint32_t textLength;
    uint32_t glyphCount;
    const uint16_t *glyphs;
    const float *advances;     // DIPs
    const float *offsets;      // x, y per glyph (y up), DIPs
    const uint32_t *clusters;  // UTF-16 index (relative to textStart) of each glyph's cluster start
    bool rightToLeft;
} CDWRun;
bool cdw_shaped_run(CDWShaped *shaped, uint32_t index, CDWRun *out);
void cdw_shaped_release(CDWShaped *shaped);

#ifdef __cplusplus
}
#endif

#endif
