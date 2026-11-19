// Windows MIDI Services output for the CoreMIDI module (ADR-0050). See cwinmidi2.h.
//
// Two layers. The availability check (`checkPlatform`) needs nothing beyond the Windows SDK:
// it declares the one statics interface it calls, IMidiApiStatics, by hand with the IID
// Microsoft publishes for it (the "no build-time reference" path of the detect-midi-services
// sample), so even a build without the MIDI headers can say whether the PC has Windows MIDI
// Services. Everything else (session, enumeration, watcher, connections, sending) goes
// through the C++/WinRT projection of `Windows.Devices.Midi2`, which exists only when the
// build machine generated it from the NuGet package's .winmd (`cppwinrt.exe`, see ADR-0050)
// and put it on the include path. Without it, or without C++ exceptions (C++/WinRT reports
// failures by throwing), the projection layer compiles out and the check reports why.
//
// The API resolves either from Windows itself (System32, once the API ships in Windows) or
// from an app-local Windows.Devices.Midi2.dll and .pri next to the executable (the NuGet
// package's runtimes\win-x64\native, under Microsoft's preview go-live terms). Plain
// RoGetActivationFactory finds only the first; the check, like C++/WinRT's own activation,
// falls back to DllGetActivationFactory on the app-local module.
//
// Threading: every WinRT call runs on one thread the shim owns, which joins the
// multithreaded apartment, so no caller's apartment (the Win32 backend's main thread is an
// STA) is ever touched; this is the pattern of cwas_toast.cpp. The WinRT objects are kept in
// a heap block that is never freed, so static destruction at exit cannot release them after
// COM is gone.
#if defined(_WIN32)
#include "cwinmidi2.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <inspectable.h>
#include <activation.h>
#include <roapi.h>
#include <winstring.h>
#include <atomic>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "runtimeobject")
#pragma comment(lib, "ole32")

#if __has_include(<winrt/Windows.Devices.Midi2.h>) && __has_include(<winrt/Windows.Devices.Midi2.Enumeration.h>) \
    && (defined(__cpp_exceptions) || defined(_CPPUNWIND))
#define CWINMIDI2_PROJECTION 1
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Midi2.h>
#include <winrt/Windows.Devices.Midi2.Enumeration.h>
// C++/WinRT's imports (RoGetActivationFactory, SysAllocString, ...) live in the umbrella.
#pragma comment(lib, "windowsapp")
#pragma comment(lib, "oleaut32")
namespace midi2 = winrt::Windows::Devices::Midi2;
namespace midi2enum = winrt::Windows::Devices::Midi2::Enumeration;
#else
#define CWINMIDI2_PROJECTION 0
#endif

// MARK: - Helpers

static void putError(char *error, size_t length, const std::string &message) {
    if (!error || length == 0) return;
    size_t n = message.size() < length - 1 ? message.size() : length - 1;
    memcpy(error, message.data(), n);
    error[n] = 0;
}

[[maybe_unused]] static void copyString(char *dest, size_t capacity, const std::string &value) {
    size_t n = value.size() < capacity - 1 ? value.size() : capacity - 1;
    memcpy(dest, value.data(), n);
    dest[n] = 0;
}

static std::string hex32(uint32_t value) {
    char buffer[16];
    snprintf(buffer, sizeof buffer, "0x%08lx", (unsigned long)value);
    return buffer;
}

[[maybe_unused]] static std::string narrow(const wchar_t *w, size_t length) {
    if (!w || length == 0) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w, (int)length, nullptr, 0, nullptr, nullptr);
    std::string s(n > 0 ? n : 0, '\0');
    if (n > 0) WideCharToMultiByte(CP_UTF8, 0, w, (int)length, &s[0], n, nullptr, nullptr);
    return s;
}

[[maybe_unused]] static std::wstring widen(const char *s) {
    if (!s) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
    return w;
}

[[maybe_unused]] static uint64_t fnv1a64(const std::string &value) {
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (unsigned char c : value) {
        hash ^= c;
        hash *= 0x100000001b3ULL;
    }
    return hash;
}

/// UMP words per message, by message type (the top nibble of the first word).
[[maybe_unused]] static const uint32_t kWordsForType[16] = {1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4};

// MARK: - The MTA thread

/// The shim's work queue. Allocated once and never freed (see the file comment).
struct MidiThread {
    std::mutex lock;
    std::condition_variable ready;
    std::deque<std::function<void()>> jobs;
    std::thread::id id;
};
static MidiThread *g_thread = nullptr;
static std::once_flag g_threadOnce;

static void midiThreadMain(MidiThread *t) {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    for (;;) {
        std::function<void()> job;
        {
            std::unique_lock<std::mutex> l(t->lock);
            t->ready.wait(l, [t] { return !t->jobs.empty(); });
            job = std::move(t->jobs.front());
            t->jobs.pop_front();
        }
        job();
    }
}

/// Runs `work` on the MIDI thread and waits for it (inline when already there). `work`
/// must not throw: every job below catches at its own boundary.
static void onMidiThread(const std::function<void()> &work) {
    std::call_once(g_threadOnce, [] {
        MidiThread *t = new MidiThread();
        std::thread thread(midiThreadMain, t);
        t->id = thread.get_id();
        thread.detach();
        g_thread = t;
    });
    MidiThread *t = g_thread;
    if (std::this_thread::get_id() == t->id) { work(); return; }
    std::mutex doneLock;
    std::condition_variable doneReady;
    bool done = false;
    {
        std::lock_guard<std::mutex> l(t->lock);
        t->jobs.push_back([&] {
            work();
            std::lock_guard<std::mutex> d(doneLock);
            done = true;
            doneReady.notify_one();
        });
    }
    t->ready.notify_one();
    std::unique_lock<std::mutex> d(doneLock);
    doneReady.wait(d, [&] { return done; });
}

// MARK: - Platform check (no MIDI headers needed)

/// Windows.Devices.Midi2.IMidiApiStatics, declared by hand: the IID is the one Microsoft
/// publishes in the API metadata and the detect-midi-services sample; method order is the
/// vtable order (EnsureServiceAvailable, GetCurrentlySelectedApiMode).
struct IMidiApiStaticsABI : public IInspectable {
    virtual HRESULT STDMETHODCALLTYPE EnsureServiceAvailable(unsigned char *result) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetCurrentlySelectedApiMode(int32_t *result) = 0;
};
static const IID kIID_IMidiApiStatics = {0x8087b303, 0x0519, 0xc0de, {0x31, 0xd1, 0xee, 0x00, 0x10, 0x00, 0x00, 0x00}};

/// The real build number (GetVersionEx lies to a process without a Windows 10 manifest).
static DWORD windowsBuildNumber() {
    typedef LONG(WINAPI * RtlGetVersionProc)(PRTL_OSVERSIONINFOW);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    RtlGetVersionProc rtlGetVersion = ntdll ? (RtlGetVersionProc)GetProcAddress(ntdll, "RtlGetVersion") : nullptr;
    RTL_OSVERSIONINFOW info;
    memset(&info, 0, sizeof info);
    info.dwOSVersionInfoSize = sizeof info;
    if (!rtlGetVersion || rtlGetVersion(&info) != 0) return 0;
    return info.dwBuildNumber;
}

/// Windows 11 25H2. 24H2 (26100) has an older Windows MIDI Services that never gets the API.
static const DWORD kMinimumBuild = 26200;

static HRESULT midiApiStatics(IMidiApiStaticsABI **statics) {
    static const wchar_t className[] = L"Windows.Devices.Midi2.MidiApi";
    HSTRING_HEADER header;
    HSTRING name = nullptr;
    HRESULT hr = WindowsCreateStringReference(className, (UINT32)(sizeof className / sizeof className[0] - 1), &header, &name);
    if (FAILED(hr)) return hr;
    hr = RoGetActivationFactory(name, kIID_IMidiApiStatics, (void **)statics);
    if (SUCCEEDED(hr)) return hr;
    // An app-local copy is not registered; ask the module itself. The search is limited to
    // System32 and the executable's folder, never the current directory.
    HMODULE module = LoadLibraryExW(L"Windows.Devices.Midi2.dll", nullptr,
                                    LOAD_LIBRARY_SEARCH_SYSTEM32 | LOAD_LIBRARY_SEARCH_APPLICATION_DIR);
    if (!module) return hr;
    typedef HRESULT(STDMETHODCALLTYPE * GetFactoryProc)(HSTRING, IActivationFactory **);
    GetFactoryProc getFactory = (GetFactoryProc)GetProcAddress(module, "DllGetActivationFactory");
    if (!getFactory) return HRESULT_FROM_WIN32(GetLastError());
    IActivationFactory *factory = nullptr;
    hr = getFactory(name, &factory);
    if (FAILED(hr)) return hr;
    hr = factory->QueryInterface(kIID_IMidiApiStatics, (void **)statics);
    factory->Release();
    return hr;
}

/// The three questions of Microsoft's detect-midi-services sample. Runs on the MIDI thread.
static bool checkPlatform(std::string &message) {
    DWORD build = windowsBuildNumber();
    if (build < kMinimumBuild) {
        message = "Windows MIDI Services needs Windows 11 25H2 (build 26200) or later; this is build " + std::to_string(build);
        return false;
    }
    IMidiApiStaticsABI *statics = nullptr;
    HRESULT hr = midiApiStatics(&statics);
    if (FAILED(hr) || !statics) {
        message = "Windows.Devices.Midi2.MidiApi did not resolve (HRESULT " + hex32((uint32_t)hr) +
                  "): the Windows MIDI Services API is not in this Windows yet and no Windows.Devices.Midi2.dll is next to the executable";
        return false;
    }
    unsigned char serviceAvailable = 0;
    int32_t mode = -1;
    hr = statics->EnsureServiceAvailable(&serviceAvailable);
    statics->GetCurrentlySelectedApiMode(&mode);
    statics->Release();
    if (FAILED(hr) || !serviceAvailable) {
        message = "MidiApi.EnsureServiceAvailable() is false (API mode " + std::to_string(mode) +
                  "; Legacy API mode or the midisrv service disabled)";
        return false;
    }
    return true;
}

// MARK: - Shared state

struct ChangeObserver {
    std::mutex lock;
    cwinmidi2_change_fn callback = nullptr;
    void *context = nullptr;
};
static ChangeObserver *g_observer = new ChangeObserver();

[[maybe_unused]] static void notifyChanged() {
    cwinmidi2_change_fn callback;
    void *context;
    {
        std::lock_guard<std::mutex> l(g_observer->lock);
        callback = g_observer->callback;
        context = g_observer->context;
    }
    if (callback) callback(context);
}

struct Endpoint {
    std::string name;
    std::string manufacturer;
    std::string id;
    int32_t purpose = 0;
    uint16_t vendorID = 0;
    uint16_t productID = 0;
};

#if CWINMIDI2_PROJECTION

struct MidiState {
    midi2::MidiSession session{nullptr};
    midi2enum::MidiEndpointDeviceWatcher watcher{nullptr};
    uint64_t sendImmediately = 0;
    std::mutex listLock;                 // guards endpoints
    std::vector<Endpoint> endpoints;
    std::atomic<bool> dirty{true};       // set by watcher events; the list is rebuilt lazily
};
static MidiState *g_state = nullptr;     // set once by `cwinmidi2_available`, never freed

struct CWinMIDI2Connection {
    midi2::MidiEndpointConnection connection{nullptr};
    winrt::guid connectionId{};
};

static std::string describe(const winrt::hresult_error &e) {
    return winrt::to_string(e.message()) + " (HRESULT " + hex32((uint32_t)e.code()) + ")";
}

/// Runs `body` on the MIDI thread, turning any exception into `message` and false.
static bool guarded(std::string &message, const std::function<bool()> &body) {
    bool ok = false;
    onMidiThread([&] {
        try {
            ok = body();
        } catch (const winrt::hresult_error &e) {
            message = describe(e);
            ok = false;
        } catch (const std::exception &e) {
            message = e.what();
            ok = false;
        } catch (...) {
            message = "unknown C++ exception";
            ok = false;
        }
    });
    return ok;
}

static std::string sessionName() {
    wchar_t path[MAX_PATH];
    DWORD n = GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring name(path, n);
    size_t slash = name.find_last_of(L"\\/");
    if (slash != std::wstring::npos) name = name.substr(slash + 1);
    size_t dot = name.find_last_of(L'.');
    if (dot != std::wstring::npos) name = name.substr(0, dot);
    std::string result = narrow(name.c_str(), name.size());
    return result.empty() ? std::string("CoreMIDI") : result;
}

/// FindAll, keeping what an app sends to: normal endpoints and the in-box GM synth (the
/// diagnostic loopbacks, ping and virtual-device responders are left out). MIDI thread.
static std::vector<Endpoint> enumerateEndpoints() {
    std::vector<Endpoint> result;
    auto list = midi2enum::MidiEndpointDeviceInformation::FindAll(
        midi2enum::MidiEndpointDeviceInformationSortOrder::Name,
        midi2enum::MidiEndpointDeviceInformationFilters::AllStandardEndpoints);
    if (!list) return result;
    for (uint32_t i = 0; i < list.Size(); i++) {
        midi2enum::MidiEndpointDeviceInformation info = list.GetAt(i);
        if (!info) continue;
        midi2enum::MidiEndpointDevicePurpose purpose = info.EndpointPurpose();
        if (purpose != midi2enum::MidiEndpointDevicePurpose::NormalMessageEndpoint &&
            purpose != midi2enum::MidiEndpointDevicePurpose::InBoxGeneralMidiSynth) continue;
        Endpoint endpoint;
        endpoint.name = winrt::to_string(info.Name());
        endpoint.id = winrt::to_string(info.EndpointDeviceId());
        endpoint.purpose = (int32_t)purpose;
        midi2enum::MidiEndpointTransportSuppliedInfo transport = info.GetTransportSuppliedInfo();
        if (transport) {
            endpoint.manufacturer = winrt::to_string(transport.ManufacturerName());
            endpoint.vendorID = transport.VendorId();
            endpoint.productID = transport.ProductId();
        }
        if (endpoint.name.empty()) endpoint.name = endpoint.id;
        result.push_back(endpoint);
    }
    return result;
}

/// Rebuilds the cached list when a watcher event (or nothing yet) made it stale.
static void refreshIfDirty() {
    if (!g_state || !g_state->dirty.exchange(false)) return;
    std::string ignored;
    std::vector<Endpoint> fresh;
    bool ok = guarded(ignored, [&] {
        fresh = enumerateEndpoints();
        return true;
    });
    if (!ok) {
        g_state->dirty = true;   // try again next time
        return;
    }
    std::lock_guard<std::mutex> l(g_state->listLock);
    g_state->endpoints = std::move(fresh);
}

/// The session, the send-immediately timestamp and the endpoint watcher. MIDI thread.
static bool startSession(std::string &message) {
    MidiState *state = new MidiState();
    std::wstring name = widen(sessionName().c_str());
    state->session = midi2::MidiSession::Create(winrt::hstring(name));
    if (!state->session) {
        message = "MidiSession.Create returned null";
        delete state;
        return false;
    }
    state->sendImmediately = midi2::MidiClock::TimestampConstantSendImmediately();
    // The watcher keeps the cached list current; without it the list is rebuilt on every
    // read (the CoreMIDI server rescans every 2 s while a client exists).
    try {
        state->watcher = midi2enum::MidiEndpointDeviceWatcher::Create(
            midi2enum::MidiEndpointDeviceInformationFilters::AllStandardEndpoints);
        if (state->watcher) {
            state->watcher.Added([state](midi2enum::MidiEndpointDeviceWatcher const &,
                                         midi2enum::MidiEndpointDeviceInformationAddedEventArgs const &) {
                state->dirty = true;
                notifyChanged();
            });
            state->watcher.Removed([state](midi2enum::MidiEndpointDeviceWatcher const &,
                                           midi2enum::MidiEndpointDeviceInformationRemovedEventArgs const &) {
                state->dirty = true;
                notifyChanged();
            });
            state->watcher.Updated([state](midi2enum::MidiEndpointDeviceWatcher const &,
                                           midi2enum::MidiEndpointDeviceInformationUpdatedEventArgs const &) {
                state->dirty = true;
                notifyChanged();
            });
            state->watcher.Start();
        }
    } catch (const winrt::hresult_error &e) {
        fprintf(stderr, "CoreMIDI: MidiEndpointDeviceWatcher unavailable (%s); rescanning on every read\n", describe(e).c_str());
        state->watcher = nullptr;
    }
    g_state = state;
    return true;
}

#endif // CWINMIDI2_PROJECTION

// MARK: - C interface

static std::once_flag g_availableOnce;
static bool g_available = false;
static std::string *g_availableMessage = new std::string();

bool cwinmidi2_available(char *error, size_t errorLength) {
    std::call_once(g_availableOnce, [] {
        std::string message;
        bool platform = false;
        onMidiThread([&] {
            try {
                platform = checkPlatform(message);
            } catch (...) {
                message = "the Windows MIDI Services check threw";
                platform = false;
            }
        });
#if CWINMIDI2_PROJECTION
        if (platform) {
            platform = guarded(message, [&] { return startSession(message); });
        }
#else
        if (platform) {
#if !(defined(__cpp_exceptions) || defined(_CPPUNWIND))
            message = "Windows MIDI Services is available, but CWinMIDI2 was compiled without C++ exceptions, which C++/WinRT needs";
#else
            message = "Windows MIDI Services is available, but CWinMIDI2 was built without the C++/WinRT projection of Windows.Devices.Midi2 (winrt/Windows.Devices.Midi2.h; see ADR-0050)";
#endif
            platform = false;
        }
#endif
        g_available = platform;
        *g_availableMessage = message;
    });
    if (!g_available) putError(error, errorLength, *g_availableMessage);
    return g_available;
}

uint32_t cwinmidi2_destination_count(void) {
#if CWINMIDI2_PROJECTION
    if (!g_state) return 0;
    if (!g_state->watcher) g_state->dirty = true;
    refreshIfDirty();
    std::lock_guard<std::mutex> l(g_state->listLock);
    return (uint32_t)g_state->endpoints.size();
#else
    return 0;
#endif
}

bool cwinmidi2_destination(uint32_t index, CWinMIDI2EndpointInfo *info) {
#if CWINMIDI2_PROJECTION
    if (!g_state || !info) return false;
    std::lock_guard<std::mutex> l(g_state->listLock);
    if (index >= g_state->endpoints.size()) return false;
    const Endpoint &endpoint = g_state->endpoints[index];
    memset(info, 0, sizeof *info);
    copyString(info->name, sizeof info->name, endpoint.name);
    copyString(info->manufacturer, sizeof info->manufacturer, endpoint.manufacturer);
    copyString(info->endpointDeviceId, sizeof info->endpointDeviceId, endpoint.id);
    info->stableID = fnv1a64(endpoint.id);
    info->purpose = endpoint.purpose;
    info->vendorID = endpoint.vendorID;
    info->productID = endpoint.productID;
    return true;
#else
    (void)index;
    (void)info;
    return false;
#endif
}

CWinMIDI2Connection *cwinmidi2_open(const char *endpointDeviceId, char *error, size_t errorLength) {
#if CWINMIDI2_PROJECTION
    if (!g_state) { putError(error, errorLength, "Windows MIDI Services is not initialized"); return nullptr; }
    if (!endpointDeviceId || !*endpointDeviceId) { putError(error, errorLength, "no endpoint device id"); return nullptr; }
    std::string message;
    CWinMIDI2Connection *result = nullptr;
    std::wstring id = widen(endpointDeviceId);
    bool ok = guarded(message, [&] {
        midi2::MidiEndpointConnection connection = g_state->session.CreateEndpointConnection(winrt::hstring(id));
        if (!connection) {
            message = "MidiSession.CreateEndpointConnection returned null";
            return false;
        }
        if (!connection.Open()) {
            g_state->session.DisconnectEndpointConnection(connection.ConnectionId());
            message = "MidiEndpointConnection.Open() failed";
            return false;
        }
        result = new CWinMIDI2Connection();
        result->connection = connection;
        result->connectionId = connection.ConnectionId();
        return true;
    });
    if (!ok) {
        putError(error, errorLength, message);
        return nullptr;
    }
    return result;
#else
    (void)endpointDeviceId;
    putError(error, errorLength, "Windows MIDI Services support is not compiled in");
    return nullptr;
#endif
}

bool cwinmidi2_send_ump(CWinMIDI2Connection *connection, const uint32_t *words, uint32_t wordCount, char *error, size_t errorLength) {
#if CWINMIDI2_PROJECTION
    if (!connection || !g_state) { putError(error, errorLength, "no connection"); return false; }
    if (wordCount == 0) return true;
    if (!words) { putError(error, errorLength, "no words"); return false; }
    std::string message;
    bool ok = guarded(message, [&] {
        midi2::MidiEndpointConnection &c = connection->connection;
        uint64_t ts = g_state->sendImmediately;
        uint32_t index = 0;
        while (index < wordCount) {
            uint32_t size = kWordsForType[words[index] >> 28];
            if (index + size > wordCount) {
                message = "truncated UMP: message type " + std::to_string(words[index] >> 28) + " needs " +
                          std::to_string(size) + " words, " + std::to_string(wordCount - index) + " left";
                return false;
            }
            const uint32_t *w = words + index;
            midi2::MidiSendMessageResults r;
            switch (size) {
            case 1: r = c.SendSingleMessageWords(ts, w[0]); break;
            case 2: r = c.SendSingleMessageWords(ts, w[0], w[1]); break;
            case 3: r = c.SendSingleMessageWords(ts, w[0], w[1], w[2]); break;
            default: r = c.SendSingleMessageWords(ts, w[0], w[1], w[2], w[3]); break;
            }
            if (!midi2::MidiEndpointConnection::SendMessageSucceeded(r)) {
                message = "SendSingleMessageWords failed with MidiSendMessageResults " + hex32((uint32_t)r) +
                          " for word " + hex32(w[0]);
                return false;
            }
            index += size;
        }
        return true;
    });
    if (!ok) putError(error, errorLength, message);
    return ok;
#else
    (void)connection;
    (void)words;
    (void)wordCount;
    putError(error, errorLength, "Windows MIDI Services support is not compiled in");
    return false;
#endif
}

void cwinmidi2_close(CWinMIDI2Connection *connection) {
    if (!connection) return;
#if CWINMIDI2_PROJECTION
    std::string ignored;
    guarded(ignored, [&] {
        if (g_state && g_state->session) g_state->session.DisconnectEndpointConnection(connection->connectionId);
        connection->connection = nullptr;
        return true;
    });
#endif
    delete connection;
}

void cwinmidi2_set_change_callback(cwinmidi2_change_fn callback, void *context) {
    std::lock_guard<std::mutex> l(g_observer->lock);
    g_observer->callback = callback;
    g_observer->context = context;
}

bool cwinmidi2_set_receive_callback(CWinMIDI2Connection *connection, cwinmidi2_receive_fn callback, void *context, char *error, size_t errorLength) {
    (void)connection;
    (void)callback;
    (void)context;
    putError(error, errorLength, "MIDI input through Windows MIDI Services is not implemented (CoreMIDI is output only)");
    return false;
}

#endif // _WIN32
