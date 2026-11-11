// PipeWire output and capture streams and device notifications (ADR-0014, ADR-0028). See
// cpipewire.h.

#include "cpipewire.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if __has_include(<pipewire/pipewire.h>)
#include <dlfcn.h>
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/utils/result.h>
#include <pipewire/extensions/metadata.h>
#include <pthread.h>

// Every libpipewire entry point used, resolved with dlsym.
#define CPW_FUNCTIONS(X) \
    X(pw_init, void, (int *argc, char **argv[])) \
    X(pw_thread_loop_new, struct pw_thread_loop *, (const char *name, const struct spa_dict *props)) \
    X(pw_thread_loop_destroy, void, (struct pw_thread_loop *loop)) \
    X(pw_thread_loop_get_loop, struct pw_loop *, (struct pw_thread_loop *loop)) \
    X(pw_thread_loop_start, int, (struct pw_thread_loop *loop)) \
    X(pw_thread_loop_stop, void, (struct pw_thread_loop *loop)) \
    X(pw_thread_loop_lock, void, (struct pw_thread_loop *loop)) \
    X(pw_thread_loop_unlock, void, (struct pw_thread_loop *loop)) \
    X(pw_thread_loop_signal, void, (struct pw_thread_loop *loop, bool wait_for_accept)) \
    X(pw_thread_loop_timed_wait, int, (struct pw_thread_loop *loop, int wait_max_sec)) \
    X(pw_context_new, struct pw_context *, (struct pw_loop *main_loop, struct pw_properties *props, size_t user_data_size)) \
    X(pw_context_destroy, void, (struct pw_context *context)) \
    X(pw_context_connect, struct pw_core *, (struct pw_context *context, struct pw_properties *properties, size_t user_data_size)) \
    X(pw_core_disconnect, int, (struct pw_core *core)) \
    X(pw_proxy_destroy, void, (struct pw_proxy *proxy)) \
    X(pw_properties_new, struct pw_properties *, (const char *key, ...)) \
    X(pw_stream_new_simple, struct pw_stream *, (struct pw_loop *loop, const char *name, struct pw_properties *props, const struct pw_stream_events *events, void *data)) \
    X(pw_stream_destroy, void, (struct pw_stream *stream)) \
    X(pw_stream_connect, int, (struct pw_stream *stream, enum pw_direction direction, uint32_t target_id, enum pw_stream_flags flags, const struct spa_pod **params, uint32_t n_params)) \
    X(pw_stream_disconnect, int, (struct pw_stream *stream)) \
    X(pw_stream_set_active, int, (struct pw_stream *stream, bool active)) \
    X(pw_stream_dequeue_buffer, struct pw_buffer *, (struct pw_stream *stream)) \
    X(pw_stream_queue_buffer, int, (struct pw_stream *stream, struct pw_buffer *buffer)) \
    X(pw_stream_get_time_n, int, (struct pw_stream *stream, struct pw_time *time, size_t size)) \
    X(pw_stream_get_state, enum pw_stream_state, (struct pw_stream *stream, const char **error)) \
    X(pw_get_library_version, const char *, (void))

#define CPW_DECLARE(name, ret, args) static ret (*p_##name) args;
CPW_FUNCTIONS(CPW_DECLARE)

static void *g_library;
static bool g_loaded;
static bool g_initialised;
static char g_error[256];

static bool loadLibrary(void) {
    if (g_loaded) return true;
    const char *names[] = { "libpipewire-0.3.so.0", "libpipewire-0.3.so", NULL };
    for (int i = 0; names[i] && !g_library; i++) g_library = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (!g_library) { snprintf(g_error, sizeof g_error, "libpipewire-0.3.so.0 not found"); return false; }
#define CPW_RESOLVE(name, ret, args) \
    p_##name = (ret (*) args)dlsym(g_library, #name); \
    if (!p_##name) { snprintf(g_error, sizeof g_error, "libpipewire lacks %s", #name); dlclose(g_library); g_library = NULL; return false; }
    CPW_FUNCTIONS(CPW_RESOLVE)
    g_loaded = true;
    return true;
}

// A connection used for enumeration and the availability probe.
struct Probe {
    struct pw_thread_loop *loop;
    struct pw_context *context;
    struct pw_core *core;
    struct pw_registry *registry;
    struct pw_metadata *metadata;
    struct spa_hook coreListener, registryListener, metadataListener;
    int pendingSeq;
    bool done, failed;
};

static CPWSinkInfo g_sinks[64];
static uint32_t g_sinkCount;
static CPWSinkInfo g_sources[64];
static uint32_t g_sourceCount;
static char g_defaultSink[256];
static char g_defaultSource[256];

/// The "name" member of a metadata value such as {"name":"alsa_output.pci-0000"}.
static void jsonName(const char *value, char *out, size_t length) {
    out[0] = 0;
    if (!value) return;
    const char *p = strstr(value, "\"name\"");
    if (!p) return;
    p = strchr(p + 6, ':');
    if (!p) return;
    p = strchr(p, '"');
    if (!p) return;
    p++;
    size_t n = 0;
    while (*p && *p != '"' && n + 1 < length) out[n++] = *p++;
    out[n] = 0;
}

static void onRegistryGlobal(void *data, uint32_t id, uint32_t permissions, const char *type, uint32_t version, const struct spa_dict *props);

static int onProbeMetadataProperty(void *data, uint32_t subject, const char *key, const char *type, const char *value) {
    (void)data; (void)subject; (void)type;
    if (!key) return 0;
    if (strcmp(key, "default.audio.sink") == 0) jsonName(value, g_defaultSink, sizeof g_defaultSink);
    else if (strcmp(key, "default.audio.source") == 0) jsonName(value, g_defaultSource, sizeof g_defaultSource);
    return 0;
}

static const struct pw_metadata_events probeMetadataEvents = { PW_VERSION_METADATA_EVENTS, .property = onProbeMetadataProperty };

static void describeNode(CPWSinkInfo *s, const struct spa_dict *props) {
    memset(s, 0, sizeof *s);
    const char *name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
    const char *desc = spa_dict_lookup(props, PW_KEY_NODE_DESCRIPTION);
    const char *rate = spa_dict_lookup(props, "audio.rate");
    const char *channels = spa_dict_lookup(props, "audio.channels");
    if (name) strncpy(s->name, name, sizeof s->name - 1);
    if (desc) strncpy(s->description, desc, sizeof s->description - 1); else if (name) strncpy(s->description, name, sizeof s->description - 1);
    if (rate) s->sampleRate = (uint32_t)atoi(rate);
    if (channels) s->channels = (uint32_t)atoi(channels);
}

static void onRegistryGlobal(void *data, uint32_t id, uint32_t permissions, const char *type, uint32_t version, const struct spa_dict *props) {
    (void)permissions; (void)version;
    struct Probe *p = data;
    if (!props) return;
    if (strcmp(type, PW_TYPE_INTERFACE_Metadata) == 0) {
        const char *name = spa_dict_lookup(props, "metadata.name");
        if (name && strcmp(name, "default") == 0 && !p->metadata) {
            p->metadata = pw_registry_bind(p->registry, id, PW_TYPE_INTERFACE_Metadata, PW_VERSION_METADATA, 0);
            if (p->metadata) pw_metadata_add_listener(p->metadata, &p->metadataListener, &probeMetadataEvents, p);
        }
        return;
    }
    if (strcmp(type, PW_TYPE_INTERFACE_Node) != 0) return;
    const char *mediaClass = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    if (!mediaClass) return;
    if (strcmp(mediaClass, "Audio/Sink") == 0 && g_sinkCount < 64) describeNode(&g_sinks[g_sinkCount++], props);
    else if (strcmp(mediaClass, "Audio/Source") == 0 && g_sourceCount < 64) describeNode(&g_sources[g_sourceCount++], props);
}

static void onCoreDone(void *data, uint32_t id, int seq) {
    struct Probe *p = data;
    if (id == PW_ID_CORE && seq == p->pendingSeq) { p->done = true; p_pw_thread_loop_signal(p->loop, false); }
}

static void onCoreError(void *data, uint32_t id, int seq, int res, const char *message) {
    (void)seq; (void)res;
    struct Probe *p = data;
    if (id == PW_ID_CORE) { p->failed = true; snprintf(g_error, sizeof g_error, "PipeWire core error: %s", message ? message : "?"); p_pw_thread_loop_signal(p->loop, false); }
}

static const struct pw_core_events coreEvents = { PW_VERSION_CORE_EVENTS, .done = onCoreDone, .error = onCoreError };
static const struct pw_registry_events registryEvents = { PW_VERSION_REGISTRY_EVENTS, .global = onRegistryGlobal };

static pthread_mutex_t g_enumerateLock = PTHREAD_MUTEX_INITIALIZER;

/// Waits (with the loop locked) for the reply to a core sync.
static bool roundTrip(struct Probe *p) {
    p->done = false;
    p->pendingSeq = pw_core_sync(p->core, PW_ID_CORE, 0);
    int waits = 0;
    while (!p->done && !p->failed && waits++ < 3) p_pw_thread_loop_timed_wait(p->loop, 1);
    return p->done && !p->failed;
}

/// Connects, walks the registry once (and reads the default devices) and disconnects.
/// False when no daemon answers.
static bool enumerate(void) {
    if (!loadLibrary()) return false;
    if (!g_initialised) { p_pw_init(NULL, NULL); g_initialised = true; }
    pthread_mutex_lock(&g_enumerateLock);
    struct Probe p;
    memset(&p, 0, sizeof p);
    p.loop = p_pw_thread_loop_new("AppKitCross probe", NULL);
    if (!p.loop) { snprintf(g_error, sizeof g_error, "pw_thread_loop_new failed"); pthread_mutex_unlock(&g_enumerateLock); return false; }
    p.context = p_pw_context_new(p_pw_thread_loop_get_loop(p.loop), NULL, 0);
    if (!p.context) { snprintf(g_error, sizeof g_error, "pw_context_new failed"); p_pw_thread_loop_destroy(p.loop); pthread_mutex_unlock(&g_enumerateLock); return false; }
    p_pw_thread_loop_start(p.loop);
    p_pw_thread_loop_lock(p.loop);
    p.core = p_pw_context_connect(p.context, NULL, 0);
    bool ok = false;
    if (!p.core) {
        snprintf(g_error, sizeof g_error, "no PipeWire daemon (pw_context_connect failed)");
    } else {
        g_sinkCount = 0;
        g_sourceCount = 0;
        g_defaultSink[0] = 0;
        g_defaultSource[0] = 0;
        pw_core_add_listener(p.core, &p.coreListener, &coreEvents, &p);
        p.registry = pw_core_get_registry(p.core, PW_VERSION_REGISTRY, 0);
        pw_registry_add_listener(p.registry, &p.registryListener, &registryEvents, &p);
        ok = roundTrip(&p);
        // A second round trip delivers the bound metadata's properties.
        if (ok && p.metadata) roundTrip(&p);
        if (!ok && !p.failed) snprintf(g_error, sizeof g_error, "PipeWire daemon did not answer");
        if (p.metadata) { spa_hook_remove(&p.metadataListener); p_pw_proxy_destroy((struct pw_proxy *)p.metadata); }
        spa_hook_remove(&p.registryListener);
        spa_hook_remove(&p.coreListener);
        p_pw_proxy_destroy((struct pw_proxy *)p.registry);
        p_pw_core_disconnect(p.core);
    }
    p_pw_thread_loop_unlock(p.loop);
    p_pw_thread_loop_stop(p.loop);
    p_pw_context_destroy(p.context);
    p_pw_thread_loop_destroy(p.loop);
    pthread_mutex_unlock(&g_enumerateLock);
    return ok;
}

bool cpw_available(char *error, size_t errorLength) {
    bool ok = enumerate();
    if (!ok && error && errorLength) { strncpy(error, g_error, errorLength - 1); error[errorLength - 1] = 0; }
    return ok;
}

uint32_t cpw_sink_count(void) { enumerate(); return g_sinkCount; }

bool cpw_sink(uint32_t index, CPWSinkInfo *info) {
    if (index >= g_sinkCount || !info) return false;
    *info = g_sinks[index];
    return true;
}

uint32_t cpw_source_count(void) { enumerate(); return g_sourceCount; }

bool cpw_source(uint32_t index, CPWSinkInfo *info) {
    if (index >= g_sourceCount || !info) return false;
    *info = g_sources[index];
    return true;
}

void cpw_default_sink_name(char *name, size_t length) { if (name && length) { strncpy(name, g_defaultSink, length - 1); name[length - 1] = 0; } }
void cpw_default_source_name(char *name, size_t length) { if (name && length) { strncpy(name, g_defaultSource, length - 1); name[length - 1] = 0; } }

struct CPWStream {
    struct pw_thread_loop *loop;
    struct pw_stream *stream;
    struct spa_hook listener;
    cpw_render_fn render;
    cpw_capture_fn capture;
    void *context;
    CPWStreamInfo info;
    uint32_t requestedRate, requestedChannels;
    bool active;
    bool errored;
    char error[256];
};

static void onProcess(void *data) {
    struct CPWStream *s = data;
    struct pw_buffer *b = p_pw_stream_dequeue_buffer(s->stream);
    if (!b) return;
    struct spa_buffer *buf = b->buffer;
    float *dst = buf->datas[0].data;
    if (!dst) { p_pw_stream_queue_buffer(s->stream, b); return; }
    uint32_t stride = sizeof(float) * s->info.channels;
    if (s->capture) {
        // Capture: hand over what the chunk holds.
        struct spa_chunk *chunk = buf->datas[0].chunk;
        uint32_t offset = chunk->offset < buf->datas[0].maxsize ? chunk->offset : 0;
        uint32_t size = chunk->size;
        if (offset + size > buf->datas[0].maxsize) size = buf->datas[0].maxsize - offset;
        uint32_t frames = stride ? size / stride : 0;
        if (frames > 0 && s->active) s->capture(s->context, (const float *)((const uint8_t *)dst + offset), frames);
        p_pw_stream_queue_buffer(s->stream, b);
        return;
    }
    uint32_t frames = buf->datas[0].maxsize / stride;
    if (b->requested > 0 && b->requested < frames) frames = (uint32_t)b->requested;
    if (s->active) s->render(s->context, dst, frames); else memset(dst, 0, (size_t)frames * stride);
    buf->datas[0].chunk->offset = 0;
    buf->datas[0].chunk->stride = (int32_t)stride;
    buf->datas[0].chunk->size = frames * stride;
    p_pw_stream_queue_buffer(s->stream, b);
}

static void onParamChanged(void *data, uint32_t id, const struct spa_pod *param) {
    struct CPWStream *s = data;
    if (id != SPA_PARAM_Format || !param) return;
    struct spa_audio_info_raw info;
    memset(&info, 0, sizeof info);
    if (spa_format_audio_raw_parse(param, &info) < 0) return;
    if (info.rate) s->info.sampleRate = info.rate;
    if (info.channels) s->info.channels = info.channels;
}

static void onStateChanged(void *data, enum pw_stream_state old, enum pw_stream_state state, const char *error) {
    (void)old;
    struct CPWStream *s = data;
    if (state == PW_STREAM_STATE_ERROR) {
        s->errored = true;
        snprintf(s->error, sizeof s->error, "PipeWire stream error: %s", error ? error : "?");
    }
    p_pw_thread_loop_signal(s->loop, false);
}

static const struct pw_stream_events streamEvents = {
    PW_VERSION_STREAM_EVENTS,
    .state_changed = onStateChanged,
    .param_changed = onParamChanged,
    .process = onProcess,
};

static CPWStream *openStream(bool capture, const char *target, uint32_t rate, uint32_t channels, cpw_render_fn render, cpw_capture_fn captureFn, void *context, char *error, size_t errorLength) {
    if (!loadLibrary()) { if (error) snprintf(error, errorLength, "%s", g_error); return NULL; }
    if (!g_initialised) { p_pw_init(NULL, NULL); g_initialised = true; }
    struct CPWStream *s = calloc(1, sizeof *s);
    s->render = render;
    s->capture = captureFn;
    s->context = context;
    s->requestedRate = rate ? rate : 48000;
    s->requestedChannels = channels ? channels : (capture ? 1 : 2);
    s->info.sampleRate = s->requestedRate;
    s->info.channels = s->requestedChannels;
    s->info.quantumFrames = 1024;
    bool targeted = target && target[0];
    snprintf(s->info.target, sizeof s->info.target, "%s", targeted ? target : (capture ? "default source" : "default sink"));
    s->loop = p_pw_thread_loop_new(capture ? "AppKitCross capture" : "AppKitCross audio", NULL);
    if (!s->loop) { if (error) snprintf(error, errorLength, "pw_thread_loop_new failed"); free(s); return NULL; }
    char latency[64];
    snprintf(latency, sizeof latency, "%u/%u", 512u, s->requestedRate);
    struct pw_properties *props = p_pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, capture ? "Capture" : "Playback",
                                                      PW_KEY_MEDIA_ROLE, capture ? "Communication" : "Music",
                                                      PW_KEY_APP_NAME, "AppKitCross", PW_KEY_NODE_LATENCY, latency,
                                                      // "target.object" since PipeWire 0.3.44; "node.target" before.
                                                      targeted ? "target.object" : NULL, target, targeted ? "node.target" : NULL, target, NULL);
    s->stream = p_pw_stream_new_simple(p_pw_thread_loop_get_loop(s->loop), capture ? "AppKitCross input" : "AppKitCross output", props, &streamEvents, s);
    if (!s->stream) { if (error) snprintf(error, errorLength, "pw_stream_new_simple failed"); p_pw_thread_loop_destroy(s->loop); free(s); return NULL; }
    uint8_t buffer[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buffer, sizeof buffer);
    struct spa_audio_info_raw raw = SPA_AUDIO_INFO_RAW_INIT(.format = SPA_AUDIO_FORMAT_F32, .rate = s->requestedRate, .channels = s->requestedChannels);
    if (s->requestedChannels == 1) raw.position[0] = SPA_AUDIO_CHANNEL_MONO;
    else if (s->requestedChannels == 2) { raw.position[0] = SPA_AUDIO_CHANNEL_FL; raw.position[1] = SPA_AUDIO_CHANNEL_FR; }
    const struct spa_pod *params[1];
    params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &raw);
    p_pw_thread_loop_start(s->loop);
    p_pw_thread_loop_lock(s->loop);
    int res = p_pw_stream_connect(s->stream, capture ? PW_DIRECTION_INPUT : PW_DIRECTION_OUTPUT, PW_ID_ANY,
                                  PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS | PW_STREAM_FLAG_INACTIVE,
                                  params, 1);
    if (res < 0) {
        p_pw_thread_loop_unlock(s->loop);
        if (error) snprintf(error, errorLength, "pw_stream_connect: %s", spa_strerror(res));
        cpw_close(s);
        return NULL;
    }
    // Wait for the stream to be paused (connected) or to fail.
    int waits = 0;
    for (;;) {
        enum pw_stream_state state = p_pw_stream_get_state(s->stream, NULL);
        if (state == PW_STREAM_STATE_PAUSED || state == PW_STREAM_STATE_STREAMING || s->errored) break;
        if (waits++ >= 5) { s->errored = true; snprintf(s->error, sizeof s->error, "PipeWire stream did not connect"); break; }
        p_pw_thread_loop_timed_wait(s->loop, 1);
    }
    p_pw_thread_loop_unlock(s->loop);
    if (s->errored) { if (error) snprintf(error, errorLength, "%s", s->error); cpw_close(s); return NULL; }
    return s;
}

CPWStream *cpw_open(uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength) {
    return openStream(false, NULL, rate, channels, render, NULL, context, error, errorLength);
}

CPWStream *cpw_open_target(const char *target, uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength) {
    return openStream(false, target, rate, channels, render, NULL, context, error, errorLength);
}

CPWStream *cpw_open_capture(const char *target, uint32_t rate, uint32_t channels, cpw_capture_fn capture, void *context, char *error, size_t errorLength) {
    return openStream(true, target, rate, channels, NULL, capture, context, error, errorLength);
}

void cpw_stream_info(CPWStream *stream, CPWStreamInfo *info) {
    if (!stream || !info) return;
    struct pw_time t;
    memset(&t, 0, sizeof t);
    p_pw_thread_loop_lock(stream->loop);
    if (p_pw_stream_get_time_n(stream->stream, &t, sizeof t) == 0 && t.rate.denom > 0) {
        stream->info.latencySeconds = (double)t.delay * t.rate.num / t.rate.denom;
#if PW_CHECK_VERSION(0, 3, 50)
        if (t.size > 0) stream->info.quantumFrames = (uint32_t)t.size;
#endif
    }
    p_pw_thread_loop_unlock(stream->loop);
    stream->info.latencySeconds += (double)stream->info.quantumFrames / stream->info.sampleRate;
    *info = stream->info;
}

bool cpw_start(CPWStream *stream, char *error, size_t errorLength) {
    if (!stream) return false;
    p_pw_thread_loop_lock(stream->loop);
    stream->active = true;
    int res = p_pw_stream_set_active(stream->stream, true);
    p_pw_thread_loop_unlock(stream->loop);
    if (res < 0) { stream->active = false; if (error) snprintf(error, errorLength, "pw_stream_set_active: %s", spa_strerror(res)); return false; }
    return true;
}

void cpw_stop(CPWStream *stream) {
    if (!stream) return;
    p_pw_thread_loop_lock(stream->loop);
    stream->active = false;
    p_pw_stream_set_active(stream->stream, false);
    p_pw_thread_loop_unlock(stream->loop);
}

void cpw_close(CPWStream *stream) {
    if (!stream) return;
    if (stream->loop) {
        p_pw_thread_loop_lock(stream->loop);
        stream->active = false;
        if (stream->stream) { p_pw_stream_disconnect(stream->stream); p_pw_stream_destroy(stream->stream); }
        p_pw_thread_loop_unlock(stream->loop);
        p_pw_thread_loop_stop(stream->loop);
        p_pw_thread_loop_destroy(stream->loop);
    }
    free(stream);
}

// MARK: Device notifications

struct WatchedNode { uint32_t id; char name[256]; };

struct Watch {
    struct pw_thread_loop *loop;
    struct pw_context *context;
    struct pw_core *core;
    struct pw_registry *registry;
    struct pw_metadata *metadata;
    struct spa_hook registryListener, metadataListener;
    struct WatchedNode nodes[128];
    uint32_t nodeCount;
    bool initialSync;            // nodes reported before the first sync are not "added"
    struct spa_hook coreListener;
    int syncSeq;
    cpw_device_fn callback;
    void *context2;
    char defaultSink[256], defaultSource[256];
};

static struct Watch *g_watch;

static int onWatchMetadataProperty(void *data, uint32_t subject, const char *key, const char *type, const char *value) {
    (void)subject; (void)type;
    struct Watch *w = data;
    if (!key) return 0;
    char name[256];
    if (strcmp(key, "default.audio.sink") == 0) {
        jsonName(value, name, sizeof name);
        if (strcmp(name, w->defaultSink) != 0) {
            bool first = w->defaultSink[0] == 0;     // the initial value, not a change
            snprintf(w->defaultSink, sizeof w->defaultSink, "%s", name);
            if (!first) w->callback(w->context2, CPW_DEFAULT_SINK_CHANGED, name);
        }
    } else if (strcmp(key, "default.audio.source") == 0) {
        jsonName(value, name, sizeof name);
        if (strcmp(name, w->defaultSource) != 0) {
            bool first = w->defaultSource[0] == 0;
            snprintf(w->defaultSource, sizeof w->defaultSource, "%s", name);
            if (!first) w->callback(w->context2, CPW_DEFAULT_SOURCE_CHANGED, name);
        }
    }
    return 0;
}

static const struct pw_metadata_events watchMetadataEvents = { PW_VERSION_METADATA_EVENTS, .property = onWatchMetadataProperty };

static void onWatchGlobal(void *data, uint32_t id, uint32_t permissions, const char *type, uint32_t version, const struct spa_dict *props) {
    (void)permissions; (void)version;
    struct Watch *w = data;
    if (!props) return;
    if (strcmp(type, PW_TYPE_INTERFACE_Metadata) == 0) {
        const char *name = spa_dict_lookup(props, "metadata.name");
        if (name && strcmp(name, "default") == 0 && !w->metadata) {
            w->metadata = pw_registry_bind(w->registry, id, PW_TYPE_INTERFACE_Metadata, PW_VERSION_METADATA, 0);
            if (w->metadata) pw_metadata_add_listener(w->metadata, &w->metadataListener, &watchMetadataEvents, w);
        }
        return;
    }
    if (strcmp(type, PW_TYPE_INTERFACE_Node) != 0) return;
    const char *mediaClass = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    const char *name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
    if (!mediaClass || !name || (strcmp(mediaClass, "Audio/Sink") != 0 && strcmp(mediaClass, "Audio/Source") != 0)) return;
    if (w->nodeCount < 128) {
        w->nodes[w->nodeCount].id = id;
        snprintf(w->nodes[w->nodeCount].name, sizeof w->nodes[w->nodeCount].name, "%s", name);
        w->nodeCount++;
    }
    if (w->initialSync) w->callback(w->context2, CPW_DEVICE_ADDED, name);
}

static void onWatchGlobalRemove(void *data, uint32_t id) {
    struct Watch *w = data;
    for (uint32_t i = 0; i < w->nodeCount; i++) {
        if (w->nodes[i].id != id) continue;
        char name[256];
        snprintf(name, sizeof name, "%s", w->nodes[i].name);
        w->nodes[i] = w->nodes[w->nodeCount - 1];
        w->nodeCount--;
        w->callback(w->context2, CPW_DEVICE_REMOVED, name);
        return;
    }
}

static void onWatchCoreDone(void *data, uint32_t id, int seq) {
    struct Watch *w = data;
    if (id == PW_ID_CORE && seq == w->syncSeq) w->initialSync = true;
}

static const struct pw_registry_events watchRegistryEvents = { PW_VERSION_REGISTRY_EVENTS, .global = onWatchGlobal, .global_remove = onWatchGlobalRemove };
static const struct pw_core_events watchCoreEvents = { PW_VERSION_CORE_EVENTS, .done = onWatchCoreDone };

static void stopWatch(void) {
    struct Watch *w = g_watch;
    if (!w) return;
    g_watch = NULL;
    p_pw_thread_loop_lock(w->loop);
    if (w->metadata) { spa_hook_remove(&w->metadataListener); p_pw_proxy_destroy((struct pw_proxy *)w->metadata); }
    if (w->registry) { spa_hook_remove(&w->registryListener); p_pw_proxy_destroy((struct pw_proxy *)w->registry); }
    if (w->core) { spa_hook_remove(&w->coreListener); p_pw_core_disconnect(w->core); }
    p_pw_thread_loop_unlock(w->loop);
    p_pw_thread_loop_stop(w->loop);
    p_pw_context_destroy(w->context);
    p_pw_thread_loop_destroy(w->loop);
    free(w);
}

bool cpw_watch_devices(cpw_device_fn callback, void *context) {
    stopWatch();
    if (!callback) return true;
    if (!loadLibrary()) return false;
    if (!g_initialised) { p_pw_init(NULL, NULL); g_initialised = true; }
    struct Watch *w = calloc(1, sizeof *w);
    w->callback = callback;
    w->context2 = context;
    w->loop = p_pw_thread_loop_new("AppKitCross devices", NULL);
    if (!w->loop) { free(w); return false; }
    w->context = p_pw_context_new(p_pw_thread_loop_get_loop(w->loop), NULL, 0);
    if (!w->context) { p_pw_thread_loop_destroy(w->loop); free(w); return false; }
    p_pw_thread_loop_start(w->loop);
    p_pw_thread_loop_lock(w->loop);
    w->core = p_pw_context_connect(w->context, NULL, 0);
    if (!w->core) {
        p_pw_thread_loop_unlock(w->loop);
        p_pw_thread_loop_stop(w->loop);
        p_pw_context_destroy(w->context);
        p_pw_thread_loop_destroy(w->loop);
        free(w);
        return false;
    }
    pw_core_add_listener(w->core, &w->coreListener, &watchCoreEvents, w);
    w->registry = pw_core_get_registry(w->core, PW_VERSION_REGISTRY, 0);
    pw_registry_add_listener(w->registry, &w->registryListener, &watchRegistryEvents, w);
    w->syncSeq = pw_core_sync(w->core, PW_ID_CORE, 0);
    p_pw_thread_loop_unlock(w->loop);
    g_watch = w;
    return true;
}

#else   // no PipeWire headers at build time

bool cpw_available(char *error, size_t errorLength) {
    if (error && errorLength) snprintf(error, errorLength, "built without the PipeWire headers (install libpipewire-0.3-dev)");
    return false;
}
uint32_t cpw_sink_count(void) { return 0; }
bool cpw_sink(uint32_t index, CPWSinkInfo *info) { (void)index; (void)info; return false; }
uint32_t cpw_source_count(void) { return 0; }
bool cpw_source(uint32_t index, CPWSinkInfo *info) { (void)index; (void)info; return false; }
void cpw_default_sink_name(char *name, size_t length) { if (name && length) name[0] = 0; }
void cpw_default_source_name(char *name, size_t length) { if (name && length) name[0] = 0; }
CPWStream *cpw_open(uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength) {
    (void)rate; (void)channels; (void)render; (void)context;
    if (error && errorLength) snprintf(error, errorLength, "built without the PipeWire headers");
    return NULL;
}
CPWStream *cpw_open_target(const char *target, uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength) {
    (void)target;
    return cpw_open(rate, channels, render, context, error, errorLength);
}
CPWStream *cpw_open_capture(const char *target, uint32_t rate, uint32_t channels, cpw_capture_fn capture, void *context, char *error, size_t errorLength) {
    (void)target; (void)rate; (void)channels; (void)capture; (void)context;
    if (error && errorLength) snprintf(error, errorLength, "built without the PipeWire headers");
    return NULL;
}
bool cpw_watch_devices(cpw_device_fn callback, void *context) { (void)callback; (void)context; return false; }
void cpw_stream_info(CPWStream *stream, CPWStreamInfo *info) { (void)stream; (void)info; }
bool cpw_start(CPWStream *stream, char *error, size_t errorLength) { (void)stream; (void)error; (void)errorLength; return false; }
void cpw_stop(CPWStream *stream) { (void)stream; }
void cpw_close(CPWStream *stream) { (void)stream; }

#endif
