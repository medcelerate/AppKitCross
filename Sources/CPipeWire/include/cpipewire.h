// C interface of the PipeWire output and capture backend for the AVFAudio module
// (ADR-0014, ADR-0028).
//
// libpipewire-0.3 is dlopen'ed at runtime: `cpw_available` is false without the library
// or a running daemon, and the AVFAudio module then tries ALSA. Built without the
// PipeWire headers (libpipewire-0.3-dev), every function reports unavailability.

#ifndef CPIPEWIRE_H
#define CPIPEWIRE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CPWStream CPWStream;
typedef void (*cpw_render_fn)(void *context, float *interleaved, uint32_t frames);
typedef void (*cpw_capture_fn)(void *context, const float *interleaved, uint32_t frames);

typedef struct CPWSinkInfo {
    char name[256];          // node.name
    char description[256];   // node.description
    uint32_t sampleRate;     // audio.rate when known, else 0
    uint32_t channels;       // audio.channels when known, else 0
} CPWSinkInfo;

typedef struct CPWStreamInfo {
    double sampleRate;
    uint32_t channels;
    uint32_t quantumFrames;    // frames per process callback (the graph quantum)
    double latencySeconds;     // pw_stream_get_time delay plus one quantum
    char target[256];          // the sink the stream connected to, when known
} CPWStreamInfo;

/// Loads the library and connects to the daemon once; `error` says why not.
bool cpw_available(char *error, size_t errorLength);
/// Enumerates Audio/Sink nodes (a registry round trip with a timeout).
uint32_t cpw_sink_count(void);
bool cpw_sink(uint32_t index, CPWSinkInfo *info);
/// Audio/Source nodes, from the same round trip as the sinks (call cpw_sink_count first,
/// or cpw_source_count, which enumerates again).
uint32_t cpw_source_count(void);
bool cpw_source(uint32_t index, CPWSinkInfo *info);
/// The node names of the default sink and source ("default" metadata), from the last
/// enumeration; empty when unknown.
void cpw_default_sink_name(char *name, size_t length);
void cpw_default_source_name(char *name, size_t length);

/// Creates a playback stream asking for Float32 at `rate` Hz and `channels` channels.
CPWStream *cpw_open(uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength);
/// The same, connected to the node named `target` (NULL or "": the default sink, and the
/// stream follows the default when it changes).
CPWStream *cpw_open_target(const char *target, uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength);
/// A capture stream from `target` (NULL: the default source) delivering Float32.
CPWStream *cpw_open_capture(const char *target, uint32_t rate, uint32_t channels, cpw_capture_fn capture, void *context, char *error, size_t errorLength);
void cpw_stream_info(CPWStream *stream, CPWStreamInfo *info);
bool cpw_start(CPWStream *stream, char *error, size_t errorLength);
/// Returns once the process callback can no longer run.
void cpw_stop(CPWStream *stream);
void cpw_close(CPWStream *stream);

// Device notifications: a registry listener and the "default" metadata on a thread loop
// of their own. `name` is the node name.
#define CPW_DEFAULT_SINK_CHANGED 0
#define CPW_DEFAULT_SOURCE_CHANGED 1
#define CPW_DEVICE_ADDED 2
#define CPW_DEVICE_REMOVED 3
typedef void (*cpw_device_fn)(void *context, int event, const char *name);
/// Starts watching (callback NULL stops). False without PipeWire.
bool cpw_watch_devices(cpw_device_fn callback, void *context);

#ifdef __cplusplus
}
#endif
#endif
