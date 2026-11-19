// C interface of the Windows MIDI Services backend for the CoreMIDI module (ADR-0050):
// MIDI output as Universal MIDI Packets through the `Windows.Devices.Midi2` WinRT API, the
// MIDI 2.0 stack of Windows 11 25H2 and later. The header is plain C so the Swift side never
// sees windows.h or C++/WinRT.
//
// Written against the `Windows.Devices.Midi2` API as of Windows MIDI Services In-box
// Preview 11 (NuGet package `Windows.Devices.Midi2` 0.99.92-preview.11, the release Microsoft
// calls "API surface lock"; Preview 14, 2026-11-17, still names it the API to build against).
// The earlier App SDK (`Microsoft.Windows.Devices.Midi2`, release candidates 1-4, with the
// `MidiDesktopAppSdkInitializer` bootstrap) is superseded and not supported here.
//
// Strings are UTF-8. Every function is safe to call from any thread: WinRT work runs on one
// multithreaded-apartment thread the shim owns, as in CWinAppServices. No C++ exception
// crosses this interface; failures come back as `false`/NULL with a message in `error`.
//
// Built without the C++/WinRT projection of the API (`winrt/Windows.Devices.Midi2.h`, made
// by cppwinrt.exe from the NuGet package's .winmd) or without C++ exceptions, the shim still
// compiles: `cwinmidi2_available` then reports why and returns false, and the caller uses WinMM.

#ifndef CWINMIDI2_H
#define CWINMIDI2_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CWinMIDI2EndpointInfo {
    char name[256];                 // MidiEndpointDeviceInformation.Name
    char manufacturer[128];         // GetTransportSuppliedInfo().ManufacturerName, may be empty
    char endpointDeviceId[512];     // EndpointDeviceId (\\?\swd#midisrv#...), the key for open
    uint64_t stableID;              // FNV-1a 64 of endpointDeviceId
    int32_t purpose;                // EndpointPurpose: 0 normal, 400 in-box General MIDI synth
    uint16_t vendorID;              // USB vendor/product from the transport, 0 when unknown
    uint16_t productID;
} CWinMIDI2EndpointInfo;

typedef struct CWinMIDI2Connection CWinMIDI2Connection;

/// Called after the endpoint list changed (a MidiEndpointDeviceWatcher Added, Removed or
/// Updated event), on a WinRT thread-pool thread, with no shim lock held.
typedef void (*cwinmidi2_change_fn)(void *context);

/// Called for each received UMP (words, 1-4 of them, and the service timestamp).
typedef void (*cwinmidi2_receive_fn)(void *context, const uint32_t *words, uint32_t wordCount, uint64_t timestamp);

/// Whether Windows MIDI Services can be used, asked the way Microsoft's detect-midi-services
/// sample does: Windows 11 25H2 (build 26200) or later; `Windows.Devices.Midi2.MidiApi`
/// resolves (from System32, or from a Windows.Devices.Midi2.dll next to the executable);
/// `MidiApi.EnsureServiceAvailable()` (demand-starts the service; false in Legacy API mode
/// or with the service disabled). Then creates the session and the endpoint watcher. The
/// answer is computed once and cached. On false, `error` says which check failed.
bool cwinmidi2_available(char *error, size_t errorLength);

/// Outputs: endpoints with purpose NormalMessageEndpoint or InBoxGeneralMidiSynth among
/// FindAll(Name, AllStandardEndpoints). The list is cached and refreshed on watcher events.
uint32_t cwinmidi2_destination_count(void);
/// Fills `info` for output `index` of the cached list; false when out of range.
bool cwinmidi2_destination(uint32_t index, CWinMIDI2EndpointInfo *info);

/// MidiSession.CreateEndpointConnection(endpointDeviceId) and Open(). NULL on failure.
CWinMIDI2Connection *cwinmidi2_open(const char *endpointDeviceId, char *error, size_t errorLength);
/// Sends whole UMP messages: the word count of each comes from its message type nibble
/// (1 word for types 0-2 and 6-7, 2 for 3-4 and 8-A, 3 for B-C, 4 for 5 and D-F), each
/// through SendSingleMessageWords with "send immediately". A truncated last message is an
/// error. Returns false on the first failed send.
bool cwinmidi2_send_ump(CWinMIDI2Connection *connection, const uint32_t *words, uint32_t wordCount, char *error, size_t errorLength);
/// MidiSession.DisconnectEndpointConnection; frees `connection`.
void cwinmidi2_close(CWinMIDI2Connection *connection);

/// Installs (or, with NULL, removes) the endpoint-change callback.
void cwinmidi2_set_change_callback(cwinmidi2_change_fn callback, void *context);

/// Input hook, declared for a later MIDI input subset: not implemented (CoreMIDI here is
/// output only). Always returns false with a message in `error`.
bool cwinmidi2_set_receive_callback(CWinMIDI2Connection *connection, cwinmidi2_receive_fn callback, void *context, char *error, size_t errorLength);

#ifdef __cplusplus
}
#endif
#endif
