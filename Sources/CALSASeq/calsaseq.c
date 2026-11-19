// ALSA sequencer output for the CoreMIDI module (ADR-0050). See calsaseq.h.
//
// libasound is dlopen'ed like CALSA's PCM backend, so the binary runs (with no MIDI
// destinations) on machines without it. The snd_seq_ev_set_* helpers are macros over the
// event struct; events are filled in by hand below.

#include "calsaseq.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if __has_include(<alsa/asoundlib.h>)
#include <dlfcn.h>
#include <errno.h>
#include <alsa/asoundlib.h>

#define CALSASEQ_FUNCTIONS(X) \
    X(snd_seq_open, int, (snd_seq_t **handle, const char *name, int streams, int mode)) \
    X(snd_seq_close, int, (snd_seq_t *handle)) \
    X(snd_seq_client_id, int, (snd_seq_t *handle)) \
    X(snd_seq_set_client_name, int, (snd_seq_t *seq, const char *name)) \
    X(snd_seq_create_simple_port, int, (snd_seq_t *seq, const char *name, unsigned int caps, unsigned int type)) \
    X(snd_seq_client_info_malloc, int, (snd_seq_client_info_t **ptr)) \
    X(snd_seq_client_info_free, void, (snd_seq_client_info_t *ptr)) \
    X(snd_seq_client_info_set_client, void, (snd_seq_client_info_t *info, int client)) \
    X(snd_seq_client_info_get_client, int, (const snd_seq_client_info_t *info)) \
    X(snd_seq_client_info_get_name, const char *, (snd_seq_client_info_t *info)) \
    X(snd_seq_query_next_client, int, (snd_seq_t *handle, snd_seq_client_info_t *info)) \
    X(snd_seq_port_info_malloc, int, (snd_seq_port_info_t **ptr)) \
    X(snd_seq_port_info_free, void, (snd_seq_port_info_t *ptr)) \
    X(snd_seq_port_info_set_client, void, (snd_seq_port_info_t *info, int client)) \
    X(snd_seq_port_info_set_port, void, (snd_seq_port_info_t *info, int port)) \
    X(snd_seq_port_info_get_port, int, (const snd_seq_port_info_t *info)) \
    X(snd_seq_port_info_get_capability, unsigned int, (const snd_seq_port_info_t *info)) \
    X(snd_seq_port_info_get_name, const char *, (const snd_seq_port_info_t *info)) \
    X(snd_seq_query_next_port, int, (snd_seq_t *handle, snd_seq_port_info_t *info)) \
    X(snd_seq_event_output_direct, int, (snd_seq_t *handle, snd_seq_event_t *ev)) \
    X(snd_seq_drain_output, int, (snd_seq_t *handle)) \
    X(snd_strerror, const char *, (int errnum)) \
    X(snd_lib_error_set_handler, int, (snd_lib_error_handler_t handler))

#define CALSASEQ_DECLARE(name, ret, args) static ret (*p_##name) args;
CALSASEQ_FUNCTIONS(CALSASEQ_DECLARE)

static void *g_library;
static bool g_loaded;
static char g_error[256];
static snd_seq_t *g_seq;
static int g_ownClient = -1;
static int g_ownPort = -1;

static void quietErrorHandler(const char *file, int line, const char *function, int err, const char *fmt, ...) {
    (void)file; (void)line; (void)function; (void)err; (void)fmt;
}

static bool loadLibrary(void) {
    if (g_loaded) return true;
    const char *names[] = { "libasound.so.2", "libasound.so", NULL };
    for (int i = 0; names[i] && !g_library; i++) g_library = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (!g_library) { snprintf(g_error, sizeof g_error, "libasound.so.2 not found"); return false; }
#define CALSASEQ_RESOLVE(name, ret, args) \
    p_##name = (ret (*) args)dlsym(g_library, #name); \
    if (!p_##name) { snprintf(g_error, sizeof g_error, "libasound lacks %s", #name); dlclose(g_library); g_library = NULL; return false; }
    CALSASEQ_FUNCTIONS(CALSASEQ_RESOLVE)
    // A machine without the snd-seq module makes libasound print to stderr; the Swift side
    // reports the failure once instead.
    p_snd_lib_error_set_handler(quietErrorHandler);
    g_loaded = true;
    return true;
}

static void copyError(char *error, size_t errorLength) {
    if (error && errorLength) { strncpy(error, g_error, errorLength - 1); error[errorLength - 1] = 0; }
}

bool calsaseq_open(const char *clientName, const char *portName, char *error, size_t errorLength) {
    if (g_seq) return true;
    if (!loadLibrary()) { copyError(error, errorLength); return false; }
    int err = p_snd_seq_open(&g_seq, "default", SND_SEQ_OPEN_DUPLEX, 0);
    if (err < 0) {
        snprintf(g_error, sizeof g_error, "snd_seq_open: %s", p_snd_strerror(err));
        g_seq = NULL;
        copyError(error, errorLength);
        return false;
    }
    p_snd_seq_set_client_name(g_seq, clientName && clientName[0] ? clientName : "AppKitCross");
    g_ownClient = p_snd_seq_client_id(g_seq);
    // An output port: other clients read (and subscribe to read) what it sends.
    g_ownPort = p_snd_seq_create_simple_port(g_seq, portName && portName[0] ? portName : "Output",
                                             SND_SEQ_PORT_CAP_READ | SND_SEQ_PORT_CAP_SUBS_READ,
                                             SND_SEQ_PORT_TYPE_MIDI_GENERIC | SND_SEQ_PORT_TYPE_APPLICATION);
    if (g_ownPort < 0) {
        snprintf(g_error, sizeof g_error, "snd_seq_create_simple_port: %s", p_snd_strerror(g_ownPort));
        p_snd_seq_close(g_seq);
        g_seq = NULL;
        copyError(error, errorLength);
        return false;
    }
    return true;
}

void calsaseq_close(void) {
    if (g_seq) p_snd_seq_close(g_seq);
    g_seq = NULL;
    g_ownClient = -1;
    g_ownPort = -1;
}

#define CALSASEQ_MAX_PORTS 128
static CALSASeqPortInfo g_ports[CALSASEQ_MAX_PORTS];
static uint32_t g_portCount;

uint32_t calsaseq_destination_count(void) {
    g_portCount = 0;
    if (!g_seq) return 0;
    snd_seq_client_info_t *clientInfo = NULL;
    snd_seq_port_info_t *portInfo = NULL;
    if (p_snd_seq_client_info_malloc(&clientInfo) < 0) return 0;
    if (p_snd_seq_port_info_malloc(&portInfo) < 0) { p_snd_seq_client_info_free(clientInfo); return 0; }
    const unsigned int wanted = SND_SEQ_PORT_CAP_WRITE | SND_SEQ_PORT_CAP_SUBS_WRITE;
    p_snd_seq_client_info_set_client(clientInfo, -1);
    while (p_snd_seq_query_next_client(g_seq, clientInfo) >= 0 && g_portCount < CALSASEQ_MAX_PORTS) {
        int client = p_snd_seq_client_info_get_client(clientInfo);
        if (client == SND_SEQ_CLIENT_SYSTEM || client == g_ownClient) continue;
        p_snd_seq_port_info_set_client(portInfo, client);
        p_snd_seq_port_info_set_port(portInfo, -1);
        while (p_snd_seq_query_next_port(g_seq, portInfo) >= 0 && g_portCount < CALSASEQ_MAX_PORTS) {
            unsigned int caps = p_snd_seq_port_info_get_capability(portInfo);
            if ((caps & wanted) != wanted || (caps & SND_SEQ_PORT_CAP_NO_EXPORT)) continue;
            CALSASeqPortInfo *info = &g_ports[g_portCount++];
            memset(info, 0, sizeof *info);
            info->client = client;
            info->port = p_snd_seq_port_info_get_port(portInfo);
            const char *clientName = p_snd_seq_client_info_get_name(clientInfo);
            const char *portName = p_snd_seq_port_info_get_name(portInfo);
            strncpy(info->clientName, clientName ? clientName : "", sizeof info->clientName - 1);
            strncpy(info->portName, portName ? portName : "", sizeof info->portName - 1);
        }
    }
    p_snd_seq_port_info_free(portInfo);
    p_snd_seq_client_info_free(clientInfo);
    return g_portCount;
}

bool calsaseq_destination(uint32_t index, CALSASeqPortInfo *info) {
    if (index >= g_portCount || !info) return false;
    *info = g_ports[index];
    return true;
}

static void prepareEvent(snd_seq_event_t *ev, int32_t client, int32_t port) {
    memset(ev, 0, sizeof *ev);
    ev->queue = SND_SEQ_QUEUE_DIRECT;            // snd_seq_ev_set_direct
    ev->source.port = (unsigned char)g_ownPort;  // snd_seq_ev_set_source
    ev->dest.client = (unsigned char)client;     // snd_seq_ev_set_dest
    ev->dest.port = (unsigned char)port;
}

static int output(snd_seq_event_t *ev) {
    int err = p_snd_seq_event_output_direct(g_seq, ev);
    return err < 0 ? err : 0;
}

int calsaseq_send_short(int32_t client, int32_t port, const uint8_t *bytes, size_t count) {
    if (!g_seq) return -ENODEV;
    if (!bytes || count == 0) return -EINVAL;
    snd_seq_event_t ev;
    prepareEvent(&ev, client, port);
    uint8_t status = bytes[0];
    uint8_t d1 = count > 1 ? bytes[1] & 0x7F : 0;
    uint8_t d2 = count > 2 ? bytes[2] & 0x7F : 0;
    unsigned char channel = status & 0x0F;
    switch (status & 0xF0) {
    case 0x80:
        ev.type = SND_SEQ_EVENT_NOTEOFF;
        ev.data.note.channel = channel; ev.data.note.note = d1; ev.data.note.velocity = d2;
        break;
    case 0x90:
        ev.type = SND_SEQ_EVENT_NOTEON;
        ev.data.note.channel = channel; ev.data.note.note = d1; ev.data.note.velocity = d2;
        break;
    case 0xA0:
        ev.type = SND_SEQ_EVENT_KEYPRESS;
        ev.data.note.channel = channel; ev.data.note.note = d1; ev.data.note.velocity = d2;
        break;
    case 0xB0:
        ev.type = SND_SEQ_EVENT_CONTROLLER;
        ev.data.control.channel = channel; ev.data.control.param = d1; ev.data.control.value = d2;
        break;
    case 0xC0:
        ev.type = SND_SEQ_EVENT_PGMCHANGE;
        ev.data.control.channel = channel; ev.data.control.value = d1;
        break;
    case 0xD0:
        ev.type = SND_SEQ_EVENT_CHANPRESS;
        ev.data.control.channel = channel; ev.data.control.value = d1;
        break;
    case 0xE0:
        ev.type = SND_SEQ_EVENT_PITCHBEND;
        ev.data.control.channel = channel; ev.data.control.value = (int)((d2 << 7) | d1) - 8192;
        break;
    default:
        switch (status) {
        case 0xF1: ev.type = SND_SEQ_EVENT_QFRAME; ev.data.control.value = d1; break;
        case 0xF2: ev.type = SND_SEQ_EVENT_SONGPOS; ev.data.control.value = (d2 << 7) | d1; break;
        case 0xF3: ev.type = SND_SEQ_EVENT_SONGSEL; ev.data.control.value = d1; break;
        case 0xF6: ev.type = SND_SEQ_EVENT_TUNE_REQUEST; break;
        case 0xF8: ev.type = SND_SEQ_EVENT_CLOCK; break;
        case 0xFA: ev.type = SND_SEQ_EVENT_START; break;
        case 0xFB: ev.type = SND_SEQ_EVENT_CONTINUE; break;
        case 0xFC: ev.type = SND_SEQ_EVENT_STOP; break;
        case 0xFE: ev.type = SND_SEQ_EVENT_SENSING; break;
        case 0xFF: ev.type = SND_SEQ_EVENT_RESET; break;
        default: return -EINVAL;
        }
        break;
    }
    return output(&ev);
}

int calsaseq_send_sysex(int32_t client, int32_t port, const uint8_t *bytes, size_t count) {
    if (!g_seq) return -ENODEV;
    if (!bytes || count == 0) return -EINVAL;
    snd_seq_event_t ev;
    prepareEvent(&ev, client, port);
    ev.type = SND_SEQ_EVENT_SYSEX;
    // snd_seq_ev_set_variable: the payload travels by pointer, flagged variable-length.
    ev.flags &= ~SND_SEQ_EVENT_LENGTH_MASK;
    ev.flags |= SND_SEQ_EVENT_LENGTH_VARIABLE;
    ev.data.ext.len = (unsigned int)count;
    ev.data.ext.ptr = (void *)bytes;
    return output(&ev);
}

#else   // no ALSA headers at build time

bool calsaseq_open(const char *clientName, const char *portName, char *error, size_t errorLength) {
    (void)clientName; (void)portName;
    if (error && errorLength) snprintf(error, errorLength, "built without the ALSA headers (install libasound2-dev)");
    return false;
}
uint32_t calsaseq_destination_count(void) { return 0; }
bool calsaseq_destination(uint32_t index, CALSASeqPortInfo *info) { (void)index; (void)info; return false; }
int calsaseq_send_short(int32_t client, int32_t port, const uint8_t *bytes, size_t count) {
    (void)client; (void)port; (void)bytes; (void)count;
    return -19;   // ENODEV
}
int calsaseq_send_sysex(int32_t client, int32_t port, const uint8_t *bytes, size_t count) {
    (void)client; (void)port; (void)bytes; (void)count;
    return -19;   // ENODEV
}
void calsaseq_close(void) {}

#endif
