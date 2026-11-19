// C interface of the WinMM backend for the CoreMIDI module (ADR-0050): MIDI output
// devices through midiOut*. The header is plain C so the Swift side never sees windows.h.

#ifndef CWINMIDI_H
#define CWINMIDI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CWinMIDIOutputInfo {
    char name[128];             // MIDIOUTCAPSW.szPname as UTF-8
    uint16_t manufacturerID;    // wMid (MM_MICROSOFT is 1)
    uint16_t productID;         // wPid
    uint16_t technology;        // wTechnology (MOD_MIDIPORT, MOD_SWSYNTH, ...)
    uint32_t driverVersion;     // vDriverVersion
} CWinMIDIOutputInfo;

typedef struct CWinMIDIOutput CWinMIDIOutput;

/// midiOutGetNumDevs.
uint32_t cwinmidi_output_count(void);
/// midiOutGetDevCapsW for device `index`.
bool cwinmidi_output_info(uint32_t index, CWinMIDIOutputInfo *info);
/// midiOutOpen with CALLBACK_NULL; NULL on failure with the MMRESULT in `result`.
CWinMIDIOutput *cwinmidi_open(uint32_t index, uint32_t *result);
/// midiOutShortMsg: status in the low byte, then data 1 and data 2. Returns the MMRESULT.
uint32_t cwinmidi_send_short(CWinMIDIOutput *output, uint32_t message);
/// midiOutPrepareHeader / midiOutLongMsg / midiOutUnprepareHeader for a complete SysEx;
/// waits for the driver to finish with the buffer. Returns the MMRESULT.
uint32_t cwinmidi_send_long(CWinMIDIOutput *output, const uint8_t *bytes, uint32_t count);
/// midiOutReset and midiOutClose; frees `output`.
void cwinmidi_close(CWinMIDIOutput *output);

#ifdef __cplusplus
}
#endif
#endif
