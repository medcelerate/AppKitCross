// WinMM MIDI output for the CoreMIDI module (ADR-0050). See cwinmidi.h. The target is only
// declared on Windows (linking winmm); the guard keeps a stray build elsewhere harmless.

#include "cwinmidi.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <stdlib.h>
#include <string.h>

struct CWinMIDIOutput {
    HMIDIOUT handle;
};

uint32_t cwinmidi_output_count(void) {
    return (uint32_t)midiOutGetNumDevs();
}

bool cwinmidi_output_info(uint32_t index, CWinMIDIOutputInfo *info) {
    if (!info) return false;
    MIDIOUTCAPSW caps;
    memset(&caps, 0, sizeof caps);
    if (midiOutGetDevCapsW((UINT_PTR)index, &caps, sizeof caps) != MMSYSERR_NOERROR) return false;
    memset(info, 0, sizeof *info);
    WideCharToMultiByte(CP_UTF8, 0, caps.szPname, -1, info->name, (int)sizeof info->name - 1, NULL, NULL);
    info->name[sizeof info->name - 1] = 0;
    info->manufacturerID = caps.wMid;
    info->productID = caps.wPid;
    info->technology = caps.wTechnology;
    info->driverVersion = caps.vDriverVersion;
    return true;
}

CWinMIDIOutput *cwinmidi_open(uint32_t index, uint32_t *result) {
    HMIDIOUT handle = NULL;
    MMRESULT r = midiOutOpen(&handle, (UINT)index, 0, 0, CALLBACK_NULL);
    if (result) *result = (uint32_t)r;
    if (r != MMSYSERR_NOERROR) return NULL;
    struct CWinMIDIOutput *output = calloc(1, sizeof *output);
    if (!output) { midiOutClose(handle); if (result) *result = MMSYSERR_NOMEM; return NULL; }
    output->handle = handle;
    return output;
}

uint32_t cwinmidi_send_short(CWinMIDIOutput *output, uint32_t message) {
    if (!output) return MMSYSERR_INVALHANDLE;
    return (uint32_t)midiOutShortMsg(output->handle, (DWORD)message);
}

uint32_t cwinmidi_send_long(CWinMIDIOutput *output, const uint8_t *bytes, uint32_t count) {
    if (!output) return MMSYSERR_INVALHANDLE;
    if (!bytes || count == 0) return MMSYSERR_INVALPARAM;
    char *buffer = malloc(count);
    if (!buffer) return MMSYSERR_NOMEM;
    memcpy(buffer, bytes, count);
    MIDIHDR header;
    memset(&header, 0, sizeof header);
    header.lpData = buffer;
    header.dwBufferLength = count;
    header.dwBytesRecorded = count;
    MMRESULT r = midiOutPrepareHeader(output->handle, &header, sizeof header);
    if (r != MMSYSERR_NOERROR) { free(buffer); return (uint32_t)r; }
    r = midiOutLongMsg(output->handle, &header, sizeof header);
    if (r == MMSYSERR_NOERROR) {
        // CALLBACK_NULL: poll MHDR_DONE. 31.25 kbit/s is about 3 bytes per ms on a DIN port;
        // allow a generous margin before giving up on the driver.
        DWORD limit = 1000 + count;
        for (DWORD waited = 0; !(((volatile DWORD *)&header.dwFlags)[0] & MHDR_DONE) && waited < limit; waited++) Sleep(1);
    }
    if (midiOutUnprepareHeader(output->handle, &header, sizeof header) == MIDIERR_STILLPLAYING) {
        midiOutReset(output->handle);   // returns the buffer to us
        midiOutUnprepareHeader(output->handle, &header, sizeof header);
    }
    free(buffer);
    return (uint32_t)r;
}

void cwinmidi_close(CWinMIDIOutput *output) {
    if (!output) return;
    midiOutReset(output->handle);
    midiOutClose(output->handle);
    free(output);
}

#endif
