// ALSA output stream (ADR-0014). See calsa.h.

#include "calsa.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if __has_include(<alsa/asoundlib.h>)
#include <dlfcn.h>
#include <pthread.h>
#include <sched.h>
#include <alsa/asoundlib.h>

#define CALSA_FUNCTIONS(X) \
    X(snd_pcm_open, int, (snd_pcm_t **pcm, const char *name, snd_pcm_stream_t stream, int mode)) \
    X(snd_pcm_close, int, (snd_pcm_t *pcm)) \
    X(snd_pcm_hw_params_sizeof, size_t, (void)) \
    X(snd_pcm_hw_params_any, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params)) \
    X(snd_pcm_hw_params_set_access, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params, snd_pcm_access_t access)) \
    X(snd_pcm_hw_params_set_format, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params, snd_pcm_format_t format)) \
    X(snd_pcm_hw_params_set_rate_near, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params, unsigned int *val, int *dir)) \
    X(snd_pcm_hw_params_set_channels_near, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params, unsigned int *val)) \
    X(snd_pcm_hw_params_set_period_size_near, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params, snd_pcm_uframes_t *val, int *dir)) \
    X(snd_pcm_hw_params_set_buffer_size_near, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params, snd_pcm_uframes_t *val)) \
    X(snd_pcm_hw_params, int, (snd_pcm_t *pcm, snd_pcm_hw_params_t *params)) \
    X(snd_pcm_hw_params_get_period_size, int, (const snd_pcm_hw_params_t *params, snd_pcm_uframes_t *val, int *dir)) \
    X(snd_pcm_hw_params_get_buffer_size, int, (const snd_pcm_hw_params_t *params, snd_pcm_uframes_t *val)) \
    X(snd_pcm_hw_params_get_rate, int, (const snd_pcm_hw_params_t *params, unsigned int *val, int *dir)) \
    X(snd_pcm_hw_params_get_channels, int, (const snd_pcm_hw_params_t *params, unsigned int *val)) \
    X(snd_pcm_prepare, int, (snd_pcm_t *pcm)) \
    X(snd_pcm_drop, int, (snd_pcm_t *pcm)) \
    X(snd_pcm_writei, snd_pcm_sframes_t, (snd_pcm_t *pcm, const void *buffer, snd_pcm_uframes_t size)) \
    X(snd_pcm_recover, int, (snd_pcm_t *pcm, int err, int silent)) \
    X(snd_pcm_delay, int, (snd_pcm_t *pcm, snd_pcm_sframes_t *delayp)) \
    X(snd_pcm_name, const char *, (snd_pcm_t *pcm)) \
    X(snd_device_name_hint, int, (int card, const char *iface, void ***hints)) \
    X(snd_device_name_get_hint, char *, (const void *hint, const char *id)) \
    X(snd_device_name_free_hint, int, (void **hints)) \
    X(snd_strerror, const char *, (int errnum)) \
    X(snd_lib_error_set_handler, int, (snd_lib_error_handler_t handler))

#define CALSA_DECLARE(name, ret, args) static ret (*p_##name) args;
CALSA_FUNCTIONS(CALSA_DECLARE)

static void *g_library;
static bool g_loaded;
static char g_error[256];

static void quietErrorHandler(const char *file, int line, const char *function, int err, const char *fmt, ...) {
    (void)file; (void)line; (void)function; (void)err; (void)fmt;
}

static bool loadLibrary(void) {
    if (g_loaded) return true;
    const char *names[] = { "libasound.so.2", "libasound.so", NULL };
    for (int i = 0; names[i] && !g_library; i++) g_library = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (!g_library) { snprintf(g_error, sizeof g_error, "libasound.so.2 not found"); return false; }
#define CALSA_RESOLVE(name, ret, args) \
    p_##name = (ret (*) args)dlsym(g_library, #name); \
    if (!p_##name) { snprintf(g_error, sizeof g_error, "libasound lacks %s", #name); dlclose(g_library); g_library = NULL; return false; }
    CALSA_FUNCTIONS(CALSA_RESOLVE)
    // libasound prints its configuration complaints to stderr (a machine without a sound
    // device has no "default" PCM); the Swift side reports the failure instead.
    p_snd_lib_error_set_handler(quietErrorHandler);
    g_loaded = true;
    return true;
}

bool calsa_available(char *error, size_t errorLength) {
    if (loadLibrary()) return true;
    if (error && errorLength) { strncpy(error, g_error, errorLength - 1); error[errorLength - 1] = 0; }
    return false;
}

static CALSADeviceInfo g_devices[64];
static uint32_t g_deviceCount;

uint32_t calsa_device_count(void) {
    if (!loadLibrary()) return 0;
    g_deviceCount = 0;
    void **hints = NULL;
    if (p_snd_device_name_hint(-1, "pcm", &hints) < 0 || !hints) return 0;
    for (void **h = hints; *h && g_deviceCount < 64; h++) {
        char *name = p_snd_device_name_get_hint(*h, "NAME");
        char *desc = p_snd_device_name_get_hint(*h, "DESC");
        char *ioid = p_snd_device_name_get_hint(*h, "IOID");
        if (name && (!ioid || strcmp(ioid, "Input") != 0)) {
            CALSADeviceInfo *d = &g_devices[g_deviceCount++];
            memset(d, 0, sizeof *d);
            strncpy(d->name, name, sizeof d->name - 1);
            if (desc) {
                strncpy(d->description, desc, sizeof d->description - 1);
                char *nl = strchr(d->description, '\n');
                if (nl) *nl = 0;
            } else {
                strncpy(d->description, name, sizeof d->description - 1);
            }
        }
        free(name); free(desc); free(ioid);
    }
    p_snd_device_name_free_hint(hints);
    return g_deviceCount;
}

bool calsa_device(uint32_t index, CALSADeviceInfo *info) {
    if (index >= g_deviceCount || !info) return false;
    *info = g_devices[index];
    return true;
}

struct CALSAStream {
    snd_pcm_t *pcm;
    calsa_render_fn render;
    void *context;
    CALSAStreamInfo info;
    float *scratch;
    int16_t *scratch16;
    pthread_t thread;
    volatile bool running;
    bool threadStarted;
};

CALSAStream *calsa_open(const char *device, uint32_t rate, uint32_t channels, calsa_render_fn render, void *context, char *error, size_t errorLength) {
    if (!loadLibrary()) { if (error) snprintf(error, errorLength, "%s", g_error); return NULL; }
    struct CALSAStream *s = calloc(1, sizeof *s);
    s->render = render;
    s->context = context;
    const char *name = device && device[0] ? device : "default";
    int err = p_snd_pcm_open(&s->pcm, name, SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) { if (error) snprintf(error, errorLength, "snd_pcm_open(%s): %s", name, p_snd_strerror(err)); free(s); return NULL; }
    snd_pcm_hw_params_t *params = alloca(p_snd_pcm_hw_params_sizeof());
    memset(params, 0, p_snd_pcm_hw_params_sizeof());
    p_snd_pcm_hw_params_any(s->pcm, params);
    p_snd_pcm_hw_params_set_access(s->pcm, params, SND_PCM_ACCESS_RW_INTERLEAVED);
    s->info.floatOutput = p_snd_pcm_hw_params_set_format(s->pcm, params, SND_PCM_FORMAT_FLOAT_LE) >= 0;
    if (!s->info.floatOutput && (err = p_snd_pcm_hw_params_set_format(s->pcm, params, SND_PCM_FORMAT_S16_LE)) < 0) {
        if (error) snprintf(error, errorLength, "no Float32 or Int16 format: %s", p_snd_strerror(err));
        calsa_close(s); return NULL;
    }
    unsigned int r = rate ? rate : 48000, c = channels ? channels : 2;
    int dir = 0;
    p_snd_pcm_hw_params_set_rate_near(s->pcm, params, &r, &dir);
    p_snd_pcm_hw_params_set_channels_near(s->pcm, params, &c);
    snd_pcm_uframes_t period = r / 100, buffer = period * 4;   // 10 ms periods, 40 ms buffer
    dir = 0;
    p_snd_pcm_hw_params_set_period_size_near(s->pcm, params, &period, &dir);
    p_snd_pcm_hw_params_set_buffer_size_near(s->pcm, params, &buffer);
    if ((err = p_snd_pcm_hw_params(s->pcm, params)) < 0) {
        if (error) snprintf(error, errorLength, "snd_pcm_hw_params: %s", p_snd_strerror(err));
        calsa_close(s); return NULL;
    }
    p_snd_pcm_hw_params_get_period_size(params, &period, &dir);
    p_snd_pcm_hw_params_get_buffer_size(params, &buffer);
    p_snd_pcm_hw_params_get_rate(params, &r, &dir);
    p_snd_pcm_hw_params_get_channels(params, &c);
    s->info.sampleRate = r;
    s->info.channels = c;
    s->info.periodFrames = (uint32_t)period;
    s->info.bufferFrames = (uint32_t)buffer;
    s->info.latencySeconds = (double)buffer / r;
    const char *pcmName = p_snd_pcm_name(s->pcm);
    strncpy(s->info.deviceName, pcmName ? pcmName : name, sizeof s->info.deviceName - 1);
    s->scratch = calloc((size_t)period * c, sizeof(float));
    s->scratch16 = calloc((size_t)period * c, sizeof(int16_t));
    return s;
}

void calsa_stream_info(CALSAStream *stream, CALSAStreamInfo *info) {
    if (!stream || !info) return;
    snd_pcm_sframes_t delay = 0;
    if (stream->running && p_snd_pcm_delay(stream->pcm, &delay) == 0 && delay > 0) stream->info.latencySeconds = (double)delay / stream->info.sampleRate;
    *info = stream->info;
}

static void *renderThread(void *param) {
    struct CALSAStream *s = param;
    struct sched_param sp = { .sched_priority = 60 };
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp);   // works when permitted, harmless otherwise
    uint32_t period = s->info.periodFrames, channels = s->info.channels;
    p_snd_pcm_prepare(s->pcm);
    while (s->running) {
        s->render(s->context, s->scratch, period);
        const void *data = s->scratch;
        if (!s->info.floatOutput) {
            size_t n = (size_t)period * channels;
            for (size_t i = 0; i < n; i++) {
                float v = s->scratch[i] * 32768.0f;
                if (v > 32767.0f) v = 32767.0f; else if (v < -32768.0f) v = -32768.0f;
                s->scratch16[i] = (int16_t)v;
            }
            data = s->scratch16;
        }
        snd_pcm_uframes_t left = period;
        const char *p = data;
        size_t frameBytes = (s->info.floatOutput ? sizeof(float) : sizeof(int16_t)) * channels;
        while (left > 0 && s->running) {
            snd_pcm_sframes_t written = p_snd_pcm_writei(s->pcm, p, left);
            if (written < 0) {
                if (p_snd_pcm_recover(s->pcm, (int)written, 1) < 0) { s->running = false; break; }
                continue;
            }
            left -= (snd_pcm_uframes_t)written;
            p += (size_t)written * frameBytes;
        }
    }
    p_snd_pcm_drop(s->pcm);
    return NULL;
}

bool calsa_start(CALSAStream *stream, char *error, size_t errorLength) {
    if (!stream) return false;
    if (stream->threadStarted) return true;
    stream->running = true;
    int err = pthread_create(&stream->thread, NULL, renderThread, stream);
    if (err != 0) { stream->running = false; if (error) snprintf(error, errorLength, "pthread_create failed (%d)", err); return false; }
    stream->threadStarted = true;
    return true;
}

void calsa_stop(CALSAStream *stream) {
    if (!stream || !stream->threadStarted) return;
    stream->running = false;
    pthread_join(stream->thread, NULL);
    stream->threadStarted = false;
}

void calsa_close(CALSAStream *stream) {
    if (!stream) return;
    calsa_stop(stream);
    if (stream->pcm) p_snd_pcm_close(stream->pcm);
    free(stream->scratch);
    free(stream->scratch16);
    free(stream);
}

#else   // no ALSA headers at build time

bool calsa_available(char *error, size_t errorLength) {
    if (error && errorLength) snprintf(error, errorLength, "built without the ALSA headers (install libasound2-dev)");
    return false;
}
uint32_t calsa_device_count(void) { return 0; }
bool calsa_device(uint32_t index, CALSADeviceInfo *info) { (void)index; (void)info; return false; }
CALSAStream *calsa_open(const char *device, uint32_t rate, uint32_t channels, calsa_render_fn render, void *context, char *error, size_t errorLength) {
    (void)device; (void)rate; (void)channels; (void)render; (void)context;
    if (error && errorLength) snprintf(error, errorLength, "built without the ALSA headers");
    return NULL;
}
void calsa_stream_info(CALSAStream *stream, CALSAStreamInfo *info) { (void)stream; (void)info; }
bool calsa_start(CALSAStream *stream, char *error, size_t errorLength) { (void)stream; (void)error; (void)errorLength; return false; }
void calsa_stop(CALSAStream *stream) { (void)stream; }
void calsa_close(CALSAStream *stream) { (void)stream; }

#endif
