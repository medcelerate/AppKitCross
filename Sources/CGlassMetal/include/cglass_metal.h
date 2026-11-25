// The Liquid Glass program on Apple's Metal (ADR-0052 stage 2), for the macOS host build:
// a C interface over an Objective-C shim, so AppKit (which shadows Apple's frameworks with
// the port's own modules) never imports Apple's Metal module.

#ifndef CGLASS_METAL_H
#define CGLASS_METAL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CGMProgram CGMProgram;

/// Compiles `source` (MSL, fast math off) on the system's default device; NULL with the
/// reason in `error` when there is no device or the source does not compile.
CGMProgram *cgm_program_create(const char *source, char *error, size_t errorCapacity);
void cgm_program_release(CGMProgram *program);
/// The device's name (static storage owned by the program).
const char *cgm_program_device_name(CGMProgram *program);

/// One run: `raw` (premultiplied BGRA, `stride` bytes a row) through the box passes of
/// `boxRadius` (0: none), the saturation (`constants` row 9, w; 1 skips it), the luminance
/// probe and the lens, into `out` (`outWidth` by `outHeight`, tightly packed).
/// `runBackdropStage` false skips everything but the lens (the backdrop is already
/// blurred and the luminance is in the constants). `constants` holds 48 floats.
/// `luminanceOut` receives the probe (-1 for no coverage) when not NULL.
bool cgm_program_run(CGMProgram *program, const uint8_t *raw, uint32_t width, uint32_t height, uint32_t stride,
                     bool runBackdropStage, uint32_t boxRadius, const float *constants,
                     uint8_t *out, uint32_t outWidth, uint32_t outHeight, float *luminanceOut);

#ifdef __cplusplus
}
#endif

#endif
