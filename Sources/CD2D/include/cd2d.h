// C interface over the Direct2D C++ COM interfaces.
//
// d2d1.h only forward-declares its interfaces in C mode (no vtables), so Swift cannot
// call Direct2D directly. This shim keeps the C++ on this side and hands Swift opaque
// handles. Coordinates are DIPs; colors are straight (non-premultiplied) floats.
#ifndef CD2D_H
#define CD2D_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CD2DFactory CD2DFactory;
typedef struct CD2DTarget CD2DTarget;
typedef struct CD2DBrush CD2DBrush;
typedef struct CD2DStrokeStyle CD2DStrokeStyle;
typedef struct CD2DPath CD2DPath;

typedef struct CD2DMatrix { float m11, m12, m21, m22, dx, dy; } CD2DMatrix;

enum { CD2D_CAP_FLAT = 0, CD2D_CAP_SQUARE = 1, CD2D_CAP_ROUND = 2 };
enum { CD2D_JOIN_MITER = 0, CD2D_JOIN_BEVEL = 1, CD2D_JOIN_ROUND = 2 };

CD2DFactory *cd2d_factory_create(void);
void cd2d_factory_release(CD2DFactory *factory);

/// Creates a render target for a window. `hwnd` is the HWND cast to void*.
CD2DTarget *cd2d_target_create_hwnd(CD2DFactory *factory, void *hwnd, uint32_t pixelWidth, uint32_t pixelHeight, float dpi);
void cd2d_target_release(CD2DTarget *target);
void cd2d_target_resize(CD2DTarget *target, uint32_t pixelWidth, uint32_t pixelHeight);
void cd2d_target_set_dpi(CD2DTarget *target, float dpi);
void cd2d_target_begin_draw(CD2DTarget *target);
/// Returns false when the target was lost and must be recreated.
bool cd2d_target_end_draw(CD2DTarget *target);
void cd2d_target_clear(CD2DTarget *target, float r, float g, float b, float a);
void cd2d_target_set_transform(CD2DTarget *target, const CD2DMatrix *m);
void cd2d_target_set_antialias(CD2DTarget *target, bool antialias);

CD2DBrush *cd2d_brush_create(CD2DTarget *target, float r, float g, float b, float a);
void cd2d_brush_set_color(CD2DBrush *brush, float r, float g, float b, float a);
void cd2d_brush_release(CD2DBrush *brush);

CD2DStrokeStyle *cd2d_stroke_style_create(CD2DFactory *factory, int cap, int join, float miterLimit,
                                          const float *dashes, uint32_t dashCount, float dashOffset);
void cd2d_stroke_style_release(CD2DStrokeStyle *style);

/// A path geometry with its sink open. Call cd2d_path_close before drawing with it.
CD2DPath *cd2d_path_create(CD2DFactory *factory, bool evenOdd);
void cd2d_path_begin_figure(CD2DPath *path, float x, float y);
void cd2d_path_add_line(CD2DPath *path, float x, float y);
void cd2d_path_add_quad(CD2DPath *path, float cx, float cy, float x, float y);
void cd2d_path_add_bezier(CD2DPath *path, float c1x, float c1y, float c2x, float c2y, float x, float y);
void cd2d_path_end_figure(CD2DPath *path, bool closed);
void cd2d_path_close(CD2DPath *path);
void cd2d_path_release(CD2DPath *path);

void cd2d_target_fill_path(CD2DTarget *target, CD2DPath *path, CD2DBrush *brush);
void cd2d_target_stroke_path(CD2DTarget *target, CD2DPath *path, CD2DBrush *brush, float width, CD2DStrokeStyle *style);
void cd2d_target_fill_rect(CD2DTarget *target, float left, float top, float right, float bottom, CD2DBrush *brush);
void cd2d_target_stroke_rect(CD2DTarget *target, float left, float top, float right, float bottom, CD2DBrush *brush, float width, CD2DStrokeStyle *style);
void cd2d_target_push_clip_rect(CD2DTarget *target, float left, float top, float right, float bottom, bool antialias);
void cd2d_target_pop_clip_rect(CD2DTarget *target);
void cd2d_target_push_clip_path(CD2DTarget *target, CD2DPath *path);
void cd2d_target_pop_clip_path(CD2DTarget *target);

// DirectWrite
typedef struct CD2DTextFormat CD2DTextFormat;
typedef struct CD2DTextLayout CD2DTextLayout;

/// `family` is a NUL-terminated UTF-16 family name; `weight` 100-950; size in DIPs.
CD2DTextFormat *cd2d_text_format_create(const uint16_t *family, float size, int32_t weight, bool italic);
void cd2d_text_format_release(CD2DTextFormat *format);
/// Font metrics scaled to the format's size (ascent/descent positive).
bool cd2d_text_format_metrics(CD2DTextFormat *format, float *ascent, float *descent, float *lineGap, float *capHeight, float *xHeight);
CD2DTextLayout *cd2d_text_layout_create(CD2DTextFormat *format, const uint16_t *text, uint32_t length, float maxWidth, float maxHeight, bool wrap);
void cd2d_text_layout_metrics(CD2DTextLayout *layout, float *width, float *height, float *baseline);
void cd2d_text_layout_release(CD2DTextLayout *layout);
/// Draws with the layout's top-left at (x, y) in the target's current transform.
void cd2d_target_draw_text_layout(CD2DTarget *target, CD2DTextLayout *layout, float x, float y, CD2DBrush *brush);

#ifdef __cplusplus
}
#endif
#endif
