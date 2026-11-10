# ADR-0016: HDR presentation on Windows

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

AppKit applications learn about a display's headroom above white from `NSScreen`
(`maximumExtendedDynamicRangeColorComponentValue`, `maximumPotential…`,
`maximumReference…`) and render HDR content through Metal (`CAMetalLayer` with an
`.rgba16Float` format and `wantsExtendedDynamicRangeContent`). macOS composes SDR
windows on an EDR display so that colour component 1.0 is the display's SDR white; values
above 1.0 are brighter than white up to the headroom.

Windows has the same model since Windows 10 1703: a monitor in HDR mode advertises
`DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020` on its `DXGI_OUTPUT_DESC1`, DWM composes
everything in scRGB (linear, Rec. 709 primaries, 1.0 = 80 nits), 8-bit sRGB swap chains
are placed at the user's SDR white level (`DISPLAYCONFIG_SDR_WHITE_LEVEL`, typically
200 nits), and an application that wants to use the headroom presents an
`R16G16B16A16_FLOAT` swap chain in `DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709` and scales
its own SDR content by the white level itself.

The port's windows presented through an 8-bit `B8G8R8A8_UNORM` chain (M3), which DWM
treats as SDR: correct, but the window can never show anything brighter than SDR white,
and `NSScreen`'s EDR members were stubs.

## Decision

### Monitor state

`cd2d_display_hdr_info(HMONITOR)` in the CD2D shim enumerates the DXGI outputs for the
one whose `DXGI_OUTPUT_DESC1.Monitor` matches (colour space, bits per colour, min / max /
max full-frame luminance) and walks `QueryDisplayConfig` for the path whose source GDI
name is the monitor's device name to read the SDR white level (in thousandths of
80 nits) and `DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO` (HDR supported / enabled). Answers
are cached for a second per monitor and dropped on `WM_DISPLAYCHANGE`. The decision
`hdr` is: colour space is G2084/P2020, or advanced colour is on and the panel's peak
exceeds 80 nits. `APPKITWIN_HDR=0` / `=1` forces it, so the pipeline can be exercised on
an SDR monitor (DWM tone-maps the FP16 chain) and switched off on an HDR one.

### The window's chain

`Win32Window.ensureRenderTarget` asks for the window's monitor and creates the chain
through `cd2d_target_create_swapchain_with_options` with `hdr` and the white level.
An HDR chain has `R16G16B16A16_FLOAT` back buffers and `SetColorSpace1(G10 P709)` after
`CheckColorSpaceSupport`; when the chain refuses, the 8-bit chain is created instead and
the trace says so. Composition (translucent, layer-hosting) chains take the same path:
DirectComposition accepts FP16 premultiplied buffers.

Drawing does not change. Every frame still goes into the persistent 8-bit sRGB canvas
(`B8G8R8A8_UNORM`), so Direct2D's blending, grayscale text antialiasing and the partial
repaint logic are the same on both kinds of chain. What changes is the copy into the back
buffer: on an HDR chain `cd2d_target_end_draw` draws the canvas through two Direct2D
effects into the FP16 buffer, the colour-management effect (sRGB colour context →
scRGB colour context: the sRGB transfer curve to linear) and a colour matrix with
`sdrWhiteNits / 80` on the diagonal, both in 16-bit float precision and without
clamping, so the window's white lands exactly where DWM puts other SDR windows.
`cd2d_target_set_sdr_white_level` changes the matrix in place.

The window remembers which monitor its chain was made for; `WM_MOVE`, `WM_SIZE` and
`WM_DISPLAYCHANGE` re-check through `MonitorFromWindow`: a monitor of the other kind
rebuilds the chain (the existing device-loss path), a changed white level on the same
kind rescales.

### What the API shows

Only Apple's members, with Apple's meaning:

- `NSScreen.maximumExtendedDynamicRangeColorComponentValue`: peak luminance over the
  SDR white level while HDR is on, 1 otherwise.
- `maximumPotentialExtendedDynamicRangeColorComponentValue`: the same ratio for a
  monitor that supports HDR whether or not it is on, 1 for one that does not.
- `maximumReferenceExtendedDynamicRangeColorComponentValue`: 0; Windows has no
  reference modes.
- `NSWindow.screen` already follows the HWND's monitor (PR #15).

They travel through `PlatformDisplay` (three new fields, defaulting to 1 / 1 / 0, so the
host, X11 and Wayland backends report an SDR display).

### Metal

`MTKView.colorPixelFormat` is mirrored onto its `CAMetalLayer.pixelFormat`, as on macOS,
and the D3D12 composition swap chain under the layer takes that format. An
`.rgba16Float` chain is explicitly set to `DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709`, so a
view that draws values above 1.0 shows them as HDR on an HDR monitor; a `.bgra8Unorm`
view stays SDR and DWM places it at the SDR white level like the window around it. A
Metal view does not inherit the window's decision: as on macOS, the application chooses
the format and reads the headroom from `NSScreen`.

## Consequences

- Nothing changes on an SDR monitor, or when the D3D11 device, `IDXGISwapChain3` or the
  effects are unavailable (Windows 8.1 and earlier): the 8-bit chain is used and the
  trace records why.
- An HDR frame costs one effect pass over the whole canvas per present instead of a copy;
  the dirty rect still limits what DWM recomposes.
- Colour management of the content itself (an `NSColorSpace` on the window or the
  images) is not attempted: the content is sRGB, as it is on an SDR monitor.
- Verification needs an HDR monitor; the Windows CI runner has none, so the PR's
  checklist asks the PC session to read the `win32 window … swap chain hdr …` trace and
  compare the window's white against an SDR application next to it.
