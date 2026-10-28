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
/// Creates a window target presented through a DXGI flip-model swap chain (Milestone 3):
/// a D3D11 device (BGRA support), an IDXGISwapChain1 from CreateSwapChainForHwnd
/// (DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL, 2 buffers, B8G8R8A8_UNORM, DXGI_ALPHA_MODE_IGNORE)
/// and an ID2D1DeviceContext drawing into an ID2D1Bitmap1 over the back buffer. Every
/// cd2d_target_* call works on it; end_draw presents with vsync. The swap chain does not
/// retain contents between frames, so each frame must repaint the whole client area.
/// Returns NULL when the device or swap chain cannot be created (the caller may fall
/// back to cd2d_target_create_hwnd).
CD2DTarget *cd2d_target_create_swapchain(CD2DFactory *factory, void *hwnd, uint32_t pixelWidth, uint32_t pixelHeight, float dpi);
/// True when the target presents through a swap chain (created with cd2d_target_create_swapchain).
bool cd2d_target_is_swapchain(CD2DTarget *target);
void cd2d_target_release(CD2DTarget *target);
void cd2d_target_resize(CD2DTarget *target, uint32_t pixelWidth, uint32_t pixelHeight);
void cd2d_target_set_dpi(CD2DTarget *target, float dpi);
void cd2d_target_begin_draw(CD2DTarget *target);
/// Returns false when the target was lost and must be recreated (D2DERR_RECREATE_TARGET,
/// or DXGI_ERROR_DEVICE_REMOVED / DXGI_ERROR_DEVICE_RESET from the swap chain).
bool cd2d_target_end_draw(CD2DTarget *target);
/// Debug aid: asks the DXGI debug layer (dxgidebug.dll) for every live DXGI/D3D object
/// and writes the report to stderr. Returns the number of report lines, or -1 when the
/// debug layer is unavailable. Zero lines means nothing is alive.
int32_t cd2d_debug_report_live_objects(void);
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

// Bitmaps (BGRA, premultiplied, 8 bits per channel, top row first)
typedef struct CD2DBitmap CD2DBitmap;
typedef struct CD2DOffscreen CD2DOffscreen;

/// Decodes an image file in memory with WIC into a BGRA premultiplied buffer the caller
/// frees with cd2d_image_free. Returns false on failure.
bool cd2d_image_decode(const uint8_t *bytes, uint32_t length, uint32_t *width, uint32_t *height, uint32_t *stride, uint8_t **pixels);
void cd2d_image_free(uint8_t *pixels);
/// Encodes BGRA premultiplied pixels; `format` is "png" or "jpeg". Caller frees with cd2d_image_free.
bool cd2d_image_encode(const uint8_t *pixels, uint32_t width, uint32_t height, uint32_t stride, const char *format, float quality, uint8_t **bytes, uint32_t *length);

CD2DBitmap *cd2d_bitmap_create(CD2DTarget *target, uint32_t width, uint32_t height, uint32_t stride, const uint8_t *pixels);
void cd2d_bitmap_release(CD2DBitmap *bitmap);
/// Draws `bitmap` into dst (DIPs, current transform) from src (pixels), with opacity 0-1.
void cd2d_target_draw_bitmap(CD2DTarget *target, CD2DBitmap *bitmap, float dl, float dt, float dr, float db, float opacity, bool linear,
                             float sl, float st, float sr, float sb);

/// Offscreen render target of pixelWidth x pixelHeight at `dpi`. Its CD2DTarget can be used
/// with every cd2d_target_* call; begin_draw/end_draw apply.
CD2DOffscreen *cd2d_offscreen_create(CD2DFactory *factory, uint32_t pixelWidth, uint32_t pixelHeight, float dpi);
CD2DTarget *cd2d_offscreen_target(CD2DOffscreen *offscreen);
/// Copies the pixels out (BGRA premultiplied); buffer must hold stride*height bytes. Returns stride.
uint32_t cd2d_offscreen_read(CD2DOffscreen *offscreen, uint8_t *buffer, uint32_t bufferSize);
void cd2d_offscreen_release(CD2DOffscreen *offscreen);

// File dialogs (IFileDialog)
typedef struct CD2DFileDialogOptions {
    bool isSave, canChooseFiles, canChooseDirectories, allowsMultiple, allowsOtherTypes, showsHidden;
} CD2DFileDialogOptions;
/// Shows the dialog modally. Strings are NUL-terminated UTF-16 ("" = default); `extensions`
/// is ';'-separated. On success `paths` holds NUL-separated UTF-16 paths (`length` code units);
/// free with cd2d_file_dialog_free. Returns false when cancelled or failed.
bool cd2d_file_dialog(void *ownerHwnd, const CD2DFileDialogOptions *options, const uint16_t *title, const uint16_t *okLabel,
                      const uint16_t *defaultName, const uint16_t *directory, const uint16_t *extensions,
                      uint16_t **paths, uint32_t *length);
void cd2d_file_dialog_free(uint16_t *paths);

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
