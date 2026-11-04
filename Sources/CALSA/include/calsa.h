// C interface of the ALSA output backend for the AVFAudio module (ADR-0014): the fallback
// when PipeWire is absent. libasound is dlopen'ed at runtime; without the headers
// (libasound2-dev) at build time every function reports unavailability.

#ifndef CALSA_H
#define CALSA_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CALSAStream CALSAStream;
typedef void (*calsa_render_fn)(void *context, float *interleaved, uint32_t frames);

typedef struct CALSADeviceInfo {
    char name[256];          // the PCM name to open ("default", "hw:0,0", ...)
    char description[256];
} CALSADeviceInfo;

typedef struct CALSAStreamInfo {
    char deviceName[256];
    double sampleRate;
    uint32_t channels;
    uint32_t periodFrames;
    uint32_t bufferFrames;
    double latencySeconds;
    bool floatOutput;          // SND_PCM_FORMAT_FLOAT_LE accepted, else S16_LE
} CALSAStreamInfo;

bool calsa_available(char *error, size_t errorLength);
uint32_t calsa_device_count(void);
bool calsa_device(uint32_t index, CALSADeviceInfo *info);

/// Opens `device` (NULL: "default") for interleaved playback near `rate` / `channels`.
CALSAStream *calsa_open(const char *device, uint32_t rate, uint32_t channels, calsa_render_fn render, void *context, char *error, size_t errorLength);
void calsa_stream_info(CALSAStream *stream, CALSAStreamInfo *info);
bool calsa_start(CALSAStream *stream, char *error, size_t errorLength);
void calsa_stop(CALSAStream *stream);
void calsa_close(CALSAStream *stream);

#ifdef __cplusplus
}
#endif
#endif
