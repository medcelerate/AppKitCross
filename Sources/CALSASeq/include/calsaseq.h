// C interface of the ALSA sequencer backend for the CoreMIDI module (ADR-0050): MIDI
// output to the sequencer's write-capable ports. libasound is dlopen'ed at run time, as in
// CALSA; without the headers (libasound2-dev) at build time every function reports
// unavailability.

#ifndef CALSASEQ_H
#define CALSASEQ_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CALSASeqPortInfo {
    int32_t client;
    int32_t port;
    char clientName[128];
    char portName[128];
} CALSASeqPortInfo;

/// Loads libasound, opens the sequencer and creates one application output port named
/// `portName` under client name `clientName`. Idempotent; false with a message on failure.
bool calsaseq_open(const char *clientName, const char *portName, char *error, size_t errorLength);
/// Rescans the ports other clients offer for writing (WRITE | SUBS_WRITE); returns the count.
uint32_t calsaseq_destination_count(void);
/// The `index`th port of the last scan.
bool calsaseq_destination(uint32_t index, CALSASeqPortInfo *info);
/// Sends a 1-3 byte MIDI 1.0 message directly (no queue) to `client:port`; 0 or -errno.
int calsaseq_send_short(int32_t client, int32_t port, const uint8_t *bytes, size_t count);
/// Sends a complete SysEx (F0 ... F7) directly to `client:port`; 0 or -errno.
int calsaseq_send_sysex(int32_t client, int32_t port, const uint8_t *bytes, size_t count);
/// Closes the sequencer handle (the next calsaseq_open reopens it).
void calsaseq_close(void);

#ifdef __cplusplus
}
#endif
#endif
