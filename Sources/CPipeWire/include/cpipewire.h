// C interface of the PipeWire output backend for the AVFAudio module (ADR-0014).
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

/// Creates a playback stream asking for Float32 at `rate` Hz and `channels` channels.
CPWStream *cpw_open(uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength);
void cpw_stream_info(CPWStream *stream, CPWStreamInfo *info);
bool cpw_start(CPWStream *stream, char *error, size_t errorLength);
/// Returns once the process callback can no longer run.
void cpw_stop(CPWStream *stream);
void cpw_close(CPWStream *stream);

#ifdef __cplusplus
}
#endif
#endif
