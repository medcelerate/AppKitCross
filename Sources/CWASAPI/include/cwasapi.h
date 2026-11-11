// C interface of the WASAPI output and capture backend for the AVFAudio module (ADR-0014,
// ADR-0028).
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

// Capture (ADR-0028): a shared-mode, event-driven IAudioCaptureClient stream delivering
// the device's mix format as interleaved Float32 (Int16 mix formats are converted).
typedef struct CWASAPICaptureStream CWASAPICaptureStream;
typedef void (*cwasapi_capture_fn)(void *context, const float *interleaved, uint32_t frames);

/// Re-enumerates the active capture endpoints; returns how many there are.
uint32_t cwasapi_input_device_count(char *error, size_t errorLength);
bool cwasapi_input_device(uint32_t index, CWASAPIDeviceInfo *info);
bool cwasapi_default_input_device(CWASAPIDeviceInfo *info, char *error, size_t errorLength);

/// Opens a shared-mode capture stream on `deviceID` (NULL: the default console endpoint).
CWASAPICaptureStream *cwasapi_open_capture(const char *deviceID, cwasapi_capture_fn capture, void *context, char *error, size_t errorLength);
void cwasapi_capture_info(CWASAPICaptureStream *stream, CWASAPIStreamInfo *info);
bool cwasapi_capture_start(CWASAPICaptureStream *stream, char *error, size_t errorLength);
/// Returns once the capture thread has exited.
void cwasapi_capture_stop(CWASAPICaptureStream *stream);
void cwasapi_capture_close(CWASAPICaptureStream *stream);

// Device notifications (IMMNotificationClient). Events for the console role only.
#define CWASAPI_DEFAULT_OUTPUT_CHANGED 0   // deviceID: the new default render endpoint ("" when none)
#define CWASAPI_DEFAULT_INPUT_CHANGED 1    // deviceID: the new default capture endpoint
#define CWASAPI_DEVICE_ADDED 2             // added, or its state became active
#define CWASAPI_DEVICE_REMOVED 3           // removed, unplugged, disabled or not present
/// Runs on a COM thread of the system's: must not block.
typedef void (*cwasapi_device_fn)(void *context, int event, const char *deviceID);
/// Registers `callback` (NULL unregisters). False when the enumerator cannot be created.
bool cwasapi_watch_devices(cwasapi_device_fn callback, void *context);

#ifdef __cplusplus
}
#endif
#endif
