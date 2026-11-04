// PipeWire output stream (ADR-0014). See cpipewire.h.

#include "cpipewire.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if __has_include(<pipewire/pipewire.h>)
#include <dlfcn.h>
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/utils/result.h>

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
    struct spa_hook coreListener, registryListener;
    int pendingSeq;
    bool done, failed;
};

static CPWSinkInfo g_sinks[64];
static uint32_t g_sinkCount;

static void onRegistryGlobal(void *data, uint32_t id, uint32_t permissions, const char *type, uint32_t version, const struct spa_dict *props) {
    (void)data; (void)id; (void)permissions; (void)version;
    if (!props || strcmp(type, PW_TYPE_INTERFACE_Node) != 0) return;
    const char *mediaClass = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
    if (!mediaClass || strcmp(mediaClass, "Audio/Sink") != 0) return;
    if (g_sinkCount >= 64) return;
    CPWSinkInfo *s = &g_sinks[g_sinkCount++];
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

/// Connects, walks the registry once and disconnects. False when no daemon answers.
static bool enumerate(void) {
    if (!loadLibrary()) return false;
    if (!g_initialised) { p_pw_init(NULL, NULL); g_initialised = true; }
    struct Probe p;
    memset(&p, 0, sizeof p);
    p.loop = p_pw_thread_loop_new("AppKitWin probe", NULL);
    if (!p.loop) { snprintf(g_error, sizeof g_error, "pw_thread_loop_new failed"); return false; }
    p.context = p_pw_context_new(p_pw_thread_loop_get_loop(p.loop), NULL, 0);
    if (!p.context) { snprintf(g_error, sizeof g_error, "pw_context_new failed"); p_pw_thread_loop_destroy(p.loop); return false; }
    p_pw_thread_loop_start(p.loop);
    p_pw_thread_loop_lock(p.loop);
    p.core = p_pw_context_connect(p.context, NULL, 0);
    bool ok = false;
    if (!p.core) {
        snprintf(g_error, sizeof g_error, "no PipeWire daemon (pw_context_connect failed)");
    } else {
        g_sinkCount = 0;
        pw_core_add_listener(p.core, &p.coreListener, &coreEvents, &p);
        p.registry = pw_core_get_registry(p.core, PW_VERSION_REGISTRY, 0);
        pw_registry_add_listener(p.registry, &p.registryListener, &registryEvents, &p);
        p.pendingSeq = pw_core_sync(p.core, PW_ID_CORE, 0);
        int waits = 0;
        while (!p.done && !p.failed && waits++ < 3) p_pw_thread_loop_timed_wait(p.loop, 1);
        ok = p.done && !p.failed;
        if (!ok && !p.failed) snprintf(g_error, sizeof g_error, "PipeWire daemon did not answer");
        spa_hook_remove(&p.registryListener);
        spa_hook_remove(&p.coreListener);
        p_pw_proxy_destroy((struct pw_proxy *)p.registry);
        p_pw_core_disconnect(p.core);
    }
    p_pw_thread_loop_unlock(p.loop);
    p_pw_thread_loop_stop(p.loop);
    p_pw_context_destroy(p.context);
    p_pw_thread_loop_destroy(p.loop);
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

struct CPWStream {
    struct pw_thread_loop *loop;
    struct pw_stream *stream;
    struct spa_hook listener;
    cpw_render_fn render;
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

CPWStream *cpw_open(uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength) {
    if (!loadLibrary()) { if (error) snprintf(error, errorLength, "%s", g_error); return NULL; }
    if (!g_initialised) { p_pw_init(NULL, NULL); g_initialised = true; }
    struct CPWStream *s = calloc(1, sizeof *s);
    s->render = render;
    s->context = context;
    s->requestedRate = rate ? rate : 48000;
    s->requestedChannels = channels ? channels : 2;
    s->info.sampleRate = s->requestedRate;
    s->info.channels = s->requestedChannels;
    s->info.quantumFrames = 1024;
    snprintf(s->info.target, sizeof s->info.target, "default sink");
    s->loop = p_pw_thread_loop_new("AppKitWin audio", NULL);
    if (!s->loop) { if (error) snprintf(error, errorLength, "pw_thread_loop_new failed"); free(s); return NULL; }
    char latency[64];
    snprintf(latency, sizeof latency, "%u/%u", 512u, s->requestedRate);
    struct pw_properties *props = p_pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Playback", PW_KEY_MEDIA_ROLE, "Music",
                                                      PW_KEY_APP_NAME, "AppKitWin", PW_KEY_NODE_LATENCY, latency, NULL);
    s->stream = p_pw_stream_new_simple(p_pw_thread_loop_get_loop(s->loop), "AppKitWin output", props, &streamEvents, s);
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
    int res = p_pw_stream_connect(s->stream, PW_DIRECTION_OUTPUT, PW_ID_ANY,
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

#else   // no PipeWire headers at build time

bool cpw_available(char *error, size_t errorLength) {
    if (error && errorLength) snprintf(error, errorLength, "built without the PipeWire headers (install libpipewire-0.3-dev)");
    return false;
}
uint32_t cpw_sink_count(void) { return 0; }
bool cpw_sink(uint32_t index, CPWSinkInfo *info) { (void)index; (void)info; return false; }
CPWStream *cpw_open(uint32_t rate, uint32_t channels, cpw_render_fn render, void *context, char *error, size_t errorLength) {
    (void)rate; (void)channels; (void)render; (void)context;
    if (error && errorLength) snprintf(error, errorLength, "built without the PipeWire headers");
    return NULL;
}
void cpw_stream_info(CPWStream *stream, CPWStreamInfo *info) { (void)stream; (void)info; }
bool cpw_start(CPWStream *stream, char *error, size_t errorLength) { (void)stream; (void)error; (void)errorLength; return false; }
void cpw_stop(CPWStream *stream) { (void)stream; }
void cpw_close(CPWStream *stream) { (void)stream; }

#endif
