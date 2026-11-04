// C interface of the WASAPI output backend for the AVFAudio module (ADR-0014).
//
// Shared-mode, event-driven rendering on a multimedia-class thread. `cwasapi_open` uses
// IAudioClient3's low-latency shared-mode periods when the device offers them and falls
// back to IAudioClient's default period otherwise. The stream renders the device's mix
// format (Float32 or Int16, converted from the callback's Float32) at the mix sample
// rate; the caller's engine adapts to that rate.

#ifndef CWASAPI_H
#define CWASAPI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CWASAPIStream CWASAPIStream;

/// Fills `frames` frames of interleaved Float32 for `channels` channels.
typedef void (*cwasapi_render_fn)(void *context, float *interleaved, uint32_t frames);

typedef struct CWASAPIDeviceInfo {
    char id[512];        // endpoint ID string, UTF-8
    char name[256];      // friendly name, UTF-8
    double sampleRate;   // mix format
    uint32_t channels;
    bool isDefault;
} CWASAPIDeviceInfo;

typedef struct CWASAPIStreamInfo {
    char deviceName[256];
    double sampleRate;
    uint32_t channels;
    uint32_t periodFrames;     // frames per event
    uint32_t bufferFrames;     // the shared buffer
    double latencySeconds;     // IAudioClient::GetStreamLatency plus the buffer
    bool lowLatency;           // IAudioClient3 shared-mode period in use
    bool floatOutput;          // the mix format is Float32 (otherwise Int16 conversion)
} CWASAPIStreamInfo;

/// Re-enumerates the active render endpoints; returns how many there are.
uint32_t cwasapi_output_device_count(char *error, size_t errorLength);
bool cwasapi_output_device(uint32_t index, CWASAPIDeviceInfo *info);
bool cwasapi_default_output_device(CWASAPIDeviceInfo *info, char *error, size_t errorLength);

/// Opens a shared-mode stream on `deviceID` (NULL: the default console endpoint).
CWASAPIStream *cwasapi_open(const char *deviceID, cwasapi_render_fn render, void *context, char *error, size_t errorLength);
void cwasapi_stream_info(CWASAPIStream *stream, CWASAPIStreamInfo *info);
bool cwasapi_start(CWASAPIStream *stream, char *error, size_t errorLength);
/// Returns once the render thread has exited.
void cwasapi_stop(CWASAPIStream *stream);
void cwasapi_close(CWASAPIStream *stream);

#ifdef __cplusplus
}
#endif
#endif
