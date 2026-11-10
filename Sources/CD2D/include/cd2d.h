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
/// and an ID2D1DeviceContext drawing into a persistent canvas bitmap. Every cd2d_target_*
/// call works on it; end_draw blits the canvas into the back buffer and presents with
/// vsync, telling DWM which region (cd2d_target_set_dirty) changed, so frames may repaint
/// only what changed.
/// Returns NULL when the device or swap chain cannot be created (the caller may fall
/// back to cd2d_target_create_hwnd).
CD2DTarget *cd2d_target_create_swapchain(CD2DFactory *factory, void *hwnd, uint32_t pixelWidth, uint32_t pixelHeight, float dpi);
/// Creates a window target for a translucent window (Milestone 3b). Like
/// cd2d_target_create_swapchain, but the swap chain comes from
/// CreateSwapChainForComposition with DXGI_ALPHA_MODE_PREMULTIPLIED (an HWND swap chain
/// cannot carry alpha) and is presented through DirectComposition: an IDCompositionDevice
/// on the DXGI device, a target for `hwnd` (topmost) whose root visual shows the swap
/// chain, committed after every Present. The back-buffer bitmap is premultiplied, so
/// pixels left at (0,0,0,0) show whatever DWM draws behind the window (the system
/// backdrop set with DWMWA_SYSTEMBACKDROP_TYPE). The window should carry
/// WS_EX_NOREDIRECTIONBITMAP so no opaque redirection surface sits under the visual.
/// begin_draw/end_draw/resize/set_dpi and all drawing calls work unchanged. Returns
/// NULL when D3D11, DXGI 1.2 or DirectComposition is unavailable.
CD2DTarget *cd2d_target_create_composition_swapchain(CD2DFactory *factory, void *hwnd, uint32_t pixelWidth, uint32_t pixelHeight, float dpi);
/// Swap-chain presentation options beyond the two constructors above (HDR, ADR-0016).
typedef struct CD2DSwapChainOptions {
    /// A composition swap chain under DirectComposition (cd2d_target_create_composition_swapchain).
    bool composition;
    /// An HDR chain: DXGI_FORMAT_R16G16B16A16_FLOAT back buffers in scRGB
    /// (DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709, linear, 1.0 = 80 nits). Drawing is
    /// unchanged: every frame still goes into the 8-bit sRGB canvas, which end_draw
    /// converts to linear and scales by `sdrWhiteNits` / 80 on its way into the back
    /// buffer, so the window's white matches the desktop's SDR white. Creation fails
    /// (returns NULL) when the chain refuses the format or colour space; the caller then
    /// creates the 8-bit chain instead.
    bool hdr;
    /// The monitor's SDR white level in nits (DISPLAYCONFIG_SDR_WHITE_LEVEL; 80 = none).
    float sdrWhiteNits;
} CD2DSwapChainOptions;
CD2DTarget *cd2d_target_create_swapchain_with_options(CD2DFactory *factory, void *hwnd, uint32_t pixelWidth, uint32_t pixelHeight, float dpi, const CD2DSwapChainOptions *options);
/// True when the target is an HDR (FP16 scRGB) swap chain.
bool cd2d_target_is_hdr(CD2DTarget *target);
/// Changes the SDR white level an HDR target scales its frames by (the user moved the
/// SDR brightness slider, or the window moved to another HDR monitor). Ignored otherwise.
void cd2d_target_set_sdr_white_level(CD2DTarget *target, float sdrWhiteNits);
/// Whether a D3D11 device and DXGI 1.2 are available, so windows will present through a
/// flip-model swap chain (and can be created with WS_EX_NOREDIRECTIONBITMAP, which only
/// works at CreateWindowExW). Probed once; the answer is cached.
bool cd2d_presentation_available(void);

/// What a monitor's output reports about HDR (DXGI_OUTPUT_DESC1, DISPLAYCONFIG_*).
typedef struct CD2DDisplayHDR {
    /// The output's current DXGI_COLOR_SPACE_TYPE (12 = RGB_FULL_G2084_NONE_P2020 while
    /// Windows HDR is on).
    uint32_t colorSpace;
    uint32_t bitsPerColor;
    /// Luminances in nits from the output description.
    float minLuminance, maxLuminance, maxFullFrameLuminance;
    /// The SDR white level (DISPLAYCONFIG_SDR_WHITE_LEVEL) in nits; 80 when Windows
    /// does not report one (HDR off).
    float sdrWhiteNits;
    /// DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO: the monitor can do HDR / HDR is on.
    bool advancedColorSupported, advancedColorEnabled;
    /// The decision: present this monitor's windows through an HDR chain (the colour
    /// space is G2084/P2020, or advanced colour is on and the panel exceeds 80 nits).
    /// `APPKITWIN_HDR=0` forces false, `APPKITWIN_HDR=1` forces true.
    bool hdr;
} CD2DDisplayHDR;
/// Fills `out` for the monitor (an HMONITOR cast to void*). Returns false when the
/// monitor has no DXGI output (a remote session, no adapter); `out` then describes an
/// SDR display. Answers are cached for a second per monitor.
bool cd2d_display_hdr_info(void *hmonitor, CD2DDisplayHDR *out);
/// Forgets the cached answers (WM_DISPLAYCHANGE).
void cd2d_display_hdr_invalidate(void);
/// True when the target presents through a swap chain (created with
/// cd2d_target_create_swapchain or cd2d_target_create_composition_swapchain).
bool cd2d_target_is_swapchain(CD2DTarget *target);
/// Swap-chain targets draw into a persistent canvas: tells end_draw which pixels this
/// frame touched (client pixels), presented as the dirty region. Without a call the
/// frame counts as whole.
void cd2d_target_set_dirty(CD2DTarget *target, int32_t left, int32_t top, int32_t right, int32_t bottom);
/// True until the first end_draw after the canvas was created or resized: the caller
/// should paint the whole client area that frame.
bool cd2d_target_canvas_is_fresh(CD2DTarget *target);
/// True when the target is a premultiplied composition swap chain
/// (cd2d_target_create_composition_swapchain): the caller clears it to transparent
/// before drawing a frame.
bool cd2d_target_is_composition(CD2DTarget *target);
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
/// The ID2D1RenderTarget* behind `target` (for sibling shims such as CDirectWrite), or NULL.
void *cd2d_target_render_target(CD2DTarget *target);

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

// DirectComposition visual tree (Milestone 9, ADR-0005)
//
// A retained tree of IDCompositionVisuals under a composition swap-chain target's visual,
// keyed by the caller's node ids (any non-zero int64; 0 names the tree root). Children
// composite above their parent's content; the swap chain (window background) sits below
// everything. Coordinates are pixels in the parent visual's space: the caller folds the
// DPI scale into translations, clip rects and surface sizes.
//
// An update is bracketed by begin_update/end_update: every visual that should survive is
// ensured (in back-to-front order under its parent) between the two, visuals that are not
// ensured are destroyed by end_update, which also reorders children that moved and commits
// the device.
typedef struct CD2DCompTree CD2DCompTree;

/// Creates a tree on a composition swap-chain target (cd2d_target_create_composition_swapchain);
/// returns NULL for any other target. The tree must be released before the target.
CD2DCompTree *cd2d_comp_tree_create(CD2DTarget *target);
void cd2d_comp_tree_release(CD2DCompTree *tree);
void cd2d_comp_tree_begin_update(CD2DCompTree *tree);
/// Creates the visual for `id` if needed and places it as the next child (front-most so far
/// in this update) of `parentId` (0 = root). `parentId` must have been ensured earlier in
/// this update. Returns false when the visual cannot be created.
bool cd2d_comp_tree_ensure_visual(CD2DCompTree *tree, int64_t id, int64_t parentId);
/// Local → parent space, as a 3x2 matrix (row-vector convention: x' = x*m11 + y*m21 + dx).
void cd2d_comp_tree_set_transform(CD2DCompTree *tree, int64_t id, float m11, float m12, float m21, float m22, float dx, float dy);
/// Touch gestures (WM_GESTURE). `cd2d_gestures_enable` asks for every gesture on the
/// window (zoom, rotate, pan, press-and-tap, two-finger tap) instead of the default set.
void cd2d_gestures_enable(void *hwnd);
/// Decodes a WM_GESTURE's lParam. `id` is the GID_* value, `begin`/`end`/`inertia` the
/// GF_* flags, `x`/`y` the screen location, `argument` the raw ullArguments (zoom: finger
/// distance in pixels; pan: distance between fingers) and `angle` the rotation in radians
/// for GID_ROTATE. Always closes the handle. Returns false when the message carries no info.
typedef struct CD2DGesture {
    uint32_t id;
    bool begin, end, inertia;
    int32_t x, y;
    uint64_t argument;
    double angle;
} CD2DGesture;
bool cd2d_gesture_decode(intptr_t lParam, CD2DGesture *out);
/// A full 4x4 local → parent matrix (16 floats, row-major, row-vector convention, applied
/// after the 2D transform through the visual's effect group, with perspective). NULL removes it.
void cd2d_comp_tree_set_transform3d(CD2DCompTree *tree, int64_t id, const float *m);
/// 0..1, applied to the visual's content and subtree (IDCompositionVisual3::SetOpacity, or an
/// effect group where Visual3 is unavailable).
void cd2d_comp_tree_set_opacity(CD2DCompTree *tree, int64_t id, float opacity);
/// Clips the visual's content and children to a rectangle in its local space with
/// per-corner radii (an IDCompositionRectangleClip); `enabled` false removes the clip.
void cd2d_comp_tree_set_clip(CD2DCompTree *tree, int64_t id, bool enabled, float left, float top, float right, float bottom,
                             float radiusTopLeft, float radiusTopRight, float radiusBottomLeft, float radiusBottomRight);
/// Begins drawing the visual's content surface (created or recreated at `pixelWidth` x
/// `pixelHeight`, B8G8R8A8 premultiplied, cleared to transparent) and returns a target
/// whose Direct2D context draws into it at `dpi` (one DIP = one point): every
/// cd2d_target_* drawing call and CGContext work on it until surface_end_draw. Do not call
/// cd2d_target_begin_draw/end_draw/release on it. Returns NULL on failure (then nothing
/// is pending). Only one surface draw can be open at a time.
CD2DTarget *cd2d_comp_tree_surface_begin_draw(CD2DCompTree *tree, int64_t id, uint32_t pixelWidth, uint32_t pixelHeight, float dpi);
void cd2d_comp_tree_surface_end_draw(CD2DCompTree *tree, int64_t id);
/// Drops the visual's content surface (a node that no longer draws).
void cd2d_comp_tree_remove_surface(CD2DCompTree *tree, int64_t id);
/// Shows `dxgiSwapChain` (an IDXGISwapChain1 created for composition, by any device) as the
/// visual's content at its native pixel size, dropping any surface; NULL removes it.
/// Returns false when SetContent fails.
bool cd2d_comp_tree_set_swapchain(CD2DCompTree *tree, int64_t id, void *dxgiSwapChain);
/// Destroys a visual and its surface outside an update (end_update does this for every
/// visual the update did not ensure).
void cd2d_comp_tree_remove_visual(CD2DCompTree *tree, int64_t id);
/// Destroys the visuals the update did not ensure, reorders children, and commits.
void cd2d_comp_tree_end_update(CD2DCompTree *tree);
/// Number of live visuals (debug aid).
uint32_t cd2d_comp_tree_visual_count(CD2DCompTree *tree);

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

// The common colour dialog (ChooseColorW). `rgb` is COLORREF (0x00BBGGRR) in and out, with
// the 16 custom colours kept for the process. Returns false when cancelled.
bool cd2d_choose_color(void *ownerHwnd, uint32_t *rgb);

// Drag and drop (OLE; ADR-0011 stage B)
/// One representation of one dragged item. `type` is a NUL-terminated UTF-16 AppKit
/// pasteboard type; "public.utf8-plain-text" travels as CF_UNICODETEXT, "public.file-url"
/// (whose bytes are a UTF-8 file system path here) as CF_HDROP, and every other type as the
/// registered clipboard format "AppKitCross:<type>".
typedef struct CD2DDragEntry { uint32_t item; const uint16_t *type; const uint8_t *bytes; uint32_t length; } CD2DDragEntry;
typedef struct CD2DDragData CD2DDragData;    // an IDataObject being delivered to a window
typedef struct CD2DDragCallbacks {
    void *context;
    /// Destination messages for a registered HWND: `x`,`y` are screen pixels, `keyState` the
    /// MK_* flags, `allowed` the DROPEFFECT mask the source permits. Each returns the
    /// DROPEFFECT the window would perform (DROPEFFECT_NONE to refuse).
    uint32_t (*enter)(void *context, void *hwnd, CD2DDragData *data, bool fromThisApplication, int32_t x, int32_t y, uint32_t keyState, uint32_t allowed);
    uint32_t (*over)(void *context, void *hwnd, int32_t x, int32_t y, uint32_t keyState, uint32_t allowed);
    void (*leave)(void *context, void *hwnd);
    uint32_t (*drop)(void *context, void *hwnd, CD2DDragData *data, bool fromThisApplication, int32_t x, int32_t y, uint32_t keyState, uint32_t allowed);
    /// Called from OLE's loop while this application is the source (every pointer or key change).
    void (*sourceTick)(void *context);
} CD2DDragCallbacks;
/// Initialises OLE on this thread and installs the callbacks (once per process).
bool cd2d_dnd_initialize(const CD2DDragCallbacks *callbacks);
/// Makes a window a drop target / stops it being one.
bool cd2d_dnd_register(void *hwnd);
void cd2d_dnd_revoke(void *hwnd);
/// Runs an OLE drag to completion (modal: OLE pumps this thread's messages meanwhile).
/// The optional image is premultiplied BGRA, top row first, shown with its `hotspot`
/// under the pointer. Returns the DROPEFFECT performed (DROPEFFECT_NONE when cancelled).
uint32_t cd2d_dnd_do_drag(const CD2DDragEntry *entries, uint32_t count, uint32_t allowedEffects,
                          const uint8_t *imageBGRA, uint32_t width, uint32_t height, int32_t hotspotX, int32_t hotspotY);
/// Reads a delivered data object as entries (CF_UNICODETEXT, CF_HDROP with one item per
/// file, and the AppKitCross:* formats). Free with cd2d_drag_data_free_entries.
CD2DDragEntry *cd2d_drag_data_read(CD2DDragData *data, uint32_t *count);
void cd2d_drag_data_free_entries(CD2DDragEntry *entries, uint32_t count);

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
