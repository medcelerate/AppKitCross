// Windows MIDI Services output for the CoreMIDI module (ADR-0050). See cwinmidi2.h.
//
// Two layers. The availability check (`checkPlatform`) needs nothing beyond the Windows SDK:
// it declares the one statics interface it calls, IMidiApiStatics, by hand with the IID
// Microsoft publishes for it (the "no build-time reference" path of the detect-midi-services
// sample), so even a build without the MIDI headers can say whether the PC has Windows MIDI
// Services. Everything else (session, enumeration, watcher, connections, sending) goes
// through a C++/WinRT projection, which exists only when the build machine generated it with
// cppwinrt.exe from a .winmd and put it on the include path (ADR-0050, "Build PC setup").
// Without one, or without C++ exceptions (C++/WinRT reports failures by throwing), the
// projection layer compiles out and the check reports why.
//
// Which API. Two WinRT APIs carry the same session/endpoint/connection surface:
//   1. `Windows.Devices.Midi2` (projection `winrt/Windows.Devices.Midi2.h`), the API
//      Microsoft supports: in box in Windows 11 25H2 and later once it ships there, until
//      then Windows.Devices.Midi2.dll and .pri from the NuGet package next to the executable.
//      Preferred whenever its projection is present.
//   2. `Microsoft.Windows.Devices.Midi2` (projection `winrt/Microsoft.Windows.Devices.Midi2.h`),
//      the out-of-band preview App SDK (1.0.x release candidates) installed centrally by the
//      "Windows MIDI Services SDK Runtime and Tools" installer. Microsoft has superseded it and
//      is dropping it; it is used only when its projection is the one present, or with
//      CWINMIDI2_USE_APP_SDK defined.
//
// Activation. `resolveApi` is the one place a factory is found, tried in order and logged:
//   (a) RoGetActivationFactory on the class name: the system registration (System32 once
//       the API is in Windows; for the App SDK, only if something registered or detoured it);
//   (b) the app-local module beside the executable, through its DllGetActivationFactory;
//   (c) the App SDK runtime, located as Microsoft's initializer does (registry key
//       HKLM\SOFTWARE\Microsoft\Windows MIDI Services\Desktop App SDK Runtime, value
//       "Installed"; else the installer's default folder, "Windows MIDI Services\Desktop App
//       SDK Runtime" under %ProgramFiles%), through its
//       DllGetActivationFactory. Microsoft's own initializer instead CoCreates the runtime's
//       MidiClientInitializer, which detours every Ro* activation function in the process;
//       the shim does not install detours. Route (c) only serves the App SDK projection; for
//       the in-box projection a runtime found there is reported, not used.
// When (b) or (c) won, C++/WinRT's own activations (MidiSession::Create and the rest) are sent
// through `resolveFactory` by setting C++/WinRT's `winrt_activation_handler` hook (unless
// another component set it first), so they use the same module.
//
// Every check appends to an attempt log, which `cwinmidi2_available` returns as its error and
// `cwinmidi2_routes` returns always, so the CoreMIDI start-up line names every route tried.
//
// Threading: every WinRT call runs on one thread the shim owns, which joins the
// multithreaded apartment, so no caller's apartment (the Win32 backend's main thread is an
// STA) is ever touched; this is the pattern of cwas_toast.cpp. The WinRT objects are kept in
// a heap block that is never freed, so static destruction at exit cannot release them after
// COM is gone. The activation hook may be called on any thread C++/WinRT activates from.
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
#include <cwchar>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "runtimeobject")
#pragma comment(lib, "ole32")
#pragma comment(lib, "advapi32")

#if defined(__cpp_exceptions) || defined(_CPPUNWIND)
#define CWINMIDI2_EXCEPTIONS 1
#else
#define CWINMIDI2_EXCEPTIONS 0
#endif

#if __has_include(<winrt/Windows.Devices.Midi2.h>) && __has_include(<winrt/Windows.Devices.Midi2.Enumeration.h>)
#define CWINMIDI2_HAVE_INBOX_PROJECTION 1
#else
#define CWINMIDI2_HAVE_INBOX_PROJECTION 0
#endif
#if __has_include(<winrt/Microsoft.Windows.Devices.Midi2.h>)
#define CWINMIDI2_HAVE_APPSDK_PROJECTION 1
#else
#define CWINMIDI2_HAVE_APPSDK_PROJECTION 0
#endif

// 0: no projection layer; 1: Windows.Devices.Midi2; 2: Microsoft.Windows.Devices.Midi2.
#if CWINMIDI2_EXCEPTIONS && CWINMIDI2_HAVE_INBOX_PROJECTION && !defined(CWINMIDI2_USE_APP_SDK)
#define CWINMIDI2_PROJECTION 1
#elif CWINMIDI2_EXCEPTIONS && CWINMIDI2_HAVE_APPSDK_PROJECTION
#define CWINMIDI2_PROJECTION 2
#else
#define CWINMIDI2_PROJECTION 0
#endif

#if CWINMIDI2_PROJECTION
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
// C++/WinRT's imports (RoGetActivationFactory, SysAllocString, ...) live in the umbrella.
#pragma comment(lib, "windowsapp")
#pragma comment(lib, "oleaut32")
#endif
#if CWINMIDI2_PROJECTION == 1
#include <winrt/Windows.Devices.Midi2.h>
#include <winrt/Windows.Devices.Midi2.Enumeration.h>
namespace midi2 = winrt::Windows::Devices::Midi2;
namespace midi2enum = winrt::Windows::Devices::Midi2::Enumeration;
#elif CWINMIDI2_PROJECTION == 2
#include <winrt/Microsoft.Windows.Devices.Midi2.h>
// The App SDK keeps the enumeration types in the root namespace.
namespace midi2 = winrt::Microsoft::Windows::Devices::Midi2;
namespace midi2enum = winrt::Microsoft::Windows::Devices::Midi2;
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

static std::string narrow(const wchar_t *w, size_t length) {
    if (!w || length == 0) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w, (int)length, nullptr, 0, nullptr, nullptr);
    std::string s(n > 0 ? n : 0, '\0');
    if (n > 0) WideCharToMultiByte(CP_UTF8, 0, w, (int)length, &s[0], n, nullptr, nullptr);
    return s;
}

static std::string narrow(const std::wstring &w) {
    return narrow(w.c_str(), w.size());
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

/// Appends one step to the attempt log.
static void logStep(std::string &log, const std::string &step) {
    if (!log.empty()) log += "; ";
    log += step;
}

static bool fileExists(const std::wstring &path) {
    DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

static std::wstring withTrailingSlash(std::wstring path) {
    if (!path.empty() && path.back() != L'\\' && path.back() != L'/') path += L'\\';
    return path;
}

/// The folder of the executable, with a trailing backslash; empty when unknown.
static std::wstring executableDirectory() {
    std::wstring path(MAX_PATH, L'\0');
    for (;;) {
        DWORD n = GetModuleFileNameW(nullptr, &path[0], (DWORD)path.size());
        if (n == 0) return std::wstring();
        if (n < path.size()) {
            path.resize(n);
            break;
        }
        if (path.size() >= 32768) return std::wstring();
        path.resize(path.size() * 2);
    }
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return std::wstring();
    return path.substr(0, slash + 1);
}

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

// MARK: - Activation (no MIDI headers needed)

/// Windows.Devices.Midi2.IMidiApiStatics, declared by hand: the IID is the one Microsoft
/// publishes in the API metadata and the detect-midi-services sample; method order is the
/// vtable order (EnsureServiceAvailable, GetCurrentlySelectedApiMode).
struct IMidiApiStaticsABI : public IInspectable {
    virtual HRESULT STDMETHODCALLTYPE EnsureServiceAvailable(unsigned char *result) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetCurrentlySelectedApiMode(int32_t *result) = 0;
};
static const IID kIID_IMidiApiStatics = {0x8087b303, 0x0519, 0xc0de, {0x31, 0xd1, 0xee, 0x00, 0x10, 0x00, 0x00, 0x00}};

/// Windows.Devices.Midi2.IMidiApiStatics2 (Preview 11): IsSystemProvided.
struct IMidiApiStatics2ABI : public IInspectable {
    virtual HRESULT STDMETHODCALLTYPE IsSystemProvided(unsigned char *result) = 0;
};
static const IID kIID_IMidiApiStatics2 = {0x8087b303, 0x0519, 0xc0de, {0x31, 0xd1, 0xee, 0x00, 0x10, 0x00, 0x00, 0x02}};

static const IID kIID_IActivationFactory = {0x00000035, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const IID kIID_IUnknown = {0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};

/// The MidiSrv transport's class, registered by the Windows MIDI Services service install
/// (not by any SDK). Microsoft's App SDK initializer creates it to ask "is the service
/// installed"; it is used here the same way for the App SDK route, which has no MidiApi.
static const CLSID kCLSID_MidiSrvTransport = {0x2ba15e4e, 0x5417, 0x4a66, {0x85, 0xb8, 0x2b, 0x22, 0x60, 0xef, 0xbc, 0x84}};

/// What the check resolves, per API (see the file comment).
struct MidiApiInfo {
    const wchar_t *rootNamespace;   // the activations the module route serves
    const wchar_t *probeClass;      // the class the check resolves
    const wchar_t *moduleName;      // the implementation DLL, app-local or in the SDK runtime
    bool hasMidiApi;                // MidiApi statics (service and mode check) exist
    bool usesSdkRuntime;            // route (c) may serve it
};
[[maybe_unused]] static const MidiApiInfo kInBoxApi = {L"Windows.Devices.Midi2", L"Windows.Devices.Midi2.MidiApi",
                                      L"Windows.Devices.Midi2.dll", true, false};
[[maybe_unused]] static const MidiApiInfo kAppSdkApi = {L"Microsoft.Windows.Devices.Midi2", L"Microsoft.Windows.Devices.Midi2.MidiSession",
                                       L"Microsoft.Windows.Devices.Midi2.dll", false, true};
#if CWINMIDI2_PROJECTION == 2
static const MidiApiInfo &g_api = kAppSdkApi;
#else
static const MidiApiInfo &g_api = kInBoxApi;
#endif

static const wchar_t kSdkRuntimeKey[] = L"SOFTWARE\\Microsoft\\Windows MIDI Services\\Desktop App SDK Runtime";
static const wchar_t kSdkRuntimeValue[] = L"Installed";
static const wchar_t kSdkRuntimeModule[] = L"Microsoft.Windows.Devices.Midi2.dll";

#ifndef RRF_SUBKEY_WOW6464KEY
#define RRF_SUBKEY_WOW6464KEY 0x00010000
#endif

/// The module route (b) or (c) chose, or null when the system registration serves the API.
/// Set once by the check, before the activation hook is installed.
static std::atomic<HMODULE> g_routeModule{nullptr};

/// The Windows 11 25H2 floor (24H2, 26100, has an older Windows MIDI Services that never
/// gets the API). The real build number: GetVersionEx lies to a process without a Windows 10
/// manifest.
static const DWORD kMinimumBuild = 26200;

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

/// DllGetActivationFactory on `module`, then QueryInterface for `iid`.
static HRESULT factoryFromModule(HMODULE module, HSTRING name, REFIID iid, void **factory) {
    typedef HRESULT(STDMETHODCALLTYPE * GetFactoryProc)(HSTRING, IActivationFactory **);
    GetFactoryProc getFactory = (GetFactoryProc)GetProcAddress(module, "DllGetActivationFactory");
    if (!getFactory) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    IActivationFactory *activation = nullptr;
    HRESULT hr = getFactory(name, &activation);
    if (FAILED(hr)) return hr;
    if (!activation) return E_POINTER;
    hr = activation->QueryInterface(iid, factory);
    activation->Release();
    return hr;
}

/// RoGetActivationFactory, joining the MTA first when the calling thread has no apartment
/// (what C++/WinRT's default activation does).
static HRESULT systemFactory(HSTRING name, REFIID iid, void **factory) {
    HRESULT hr = RoGetActivationFactory(name, iid, factory);
    if (hr == CO_E_NOTINITIALIZED) {
        CO_MTA_USAGE_COOKIE cookie = nullptr;
        if (SUCCEEDED(CoIncrementMTAUsage(&cookie))) hr = RoGetActivationFactory(name, iid, factory);
    }
    return hr;
}

/// True when `name` is in the namespace the chosen module serves.
static bool inApiNamespace(HSTRING name) {
    UINT32 length = 0;
    const wchar_t *raw = WindowsGetStringRawBuffer(name, &length);
    size_t rootLength = wcslen(g_api.rootNamespace);
    if (!raw || length <= rootLength) return false;
    return wcsncmp(raw, g_api.rootNamespace, rootLength) == 0 && raw[rootLength] == L'.';
}

/// Every activation after the check: the system registration first, then, for the API's own
/// classes, the module route (b) or (c) chose.
[[maybe_unused]] static HRESULT resolveFactory(HSTRING name, REFIID iid, void **factory) {
    if (!factory) return E_POINTER;
    *factory = nullptr;
    HRESULT hr = systemFactory(name, iid, factory);
    if (SUCCEEDED(hr)) return hr;
    HMODULE module = g_routeModule.load();
    if (!module || !inApiNamespace(name)) return hr;
    HRESULT moduleHr = factoryFromModule(module, name, iid, factory);
    return SUCCEEDED(moduleHr) ? moduleHr : hr;
}

/// The App SDK runtime folder (trailing backslash), as Microsoft's initializer finds it:
/// HKLM\SOFTWARE\Microsoft\Windows MIDI Services\Desktop App SDK Runtime, value "Installed"
/// (64-bit view), else the installer's default folder. `source` says which.
static std::wstring sdkRuntimeDirectory(std::string &source) {
    wchar_t buffer[1024];
    DWORD size = sizeof buffer;
    LSTATUS status = RegGetValueW(HKEY_LOCAL_MACHINE, kSdkRuntimeKey, kSdkRuntimeValue,
                                  RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, buffer, &size);
    if (status == ERROR_SUCCESS && buffer[0] != 0) {
        source = "from the registry";
        return withTrailingSlash(std::wstring(buffer));
    }
    source = "default folder; registry value HKLM\\" + narrow(std::wstring(kSdkRuntimeKey)) + "\\" +
             narrow(std::wstring(kSdkRuntimeValue)) + " " + hex32((uint32_t)HRESULT_FROM_WIN32(status));
    wchar_t programFiles[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"ProgramW6432", programFiles, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) n = GetEnvironmentVariableW(L"ProgramFiles", programFiles, MAX_PATH);
    std::wstring root = (n == 0 || n >= MAX_PATH) ? std::wstring(L"C:\\Program Files") : std::wstring(programFiles, n);
    return withTrailingSlash(root) + L"Windows MIDI Services\\Desktop App SDK Runtime\\";
}

/// Loads `path` and resolves `name` through it. On success the module stays loaded and is
/// returned in `module`.
static HRESULT factoryFromPath(const std::wstring &path, HSTRING name, REFIID iid, void **factory, HMODULE &module,
                               std::string &step) {
    // LOAD_WITH_ALTERED_SEARCH_PATH: the module's own dependencies resolve from its folder,
    // as Microsoft's initializer loads the runtime.
    HMODULE loaded = LoadLibraryExW(path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!loaded) {
        HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
        step = "LoadLibrary failed (" + hex32((uint32_t)hr) + ")";
        return hr;
    }
    HRESULT hr = factoryFromModule(loaded, name, iid, factory);
    if (FAILED(hr)) {
        step = "loaded, but DllGetActivationFactory(" + narrow(std::wstring(g_api.probeClass)) + ") failed (" + hex32((uint32_t)hr) + ")";
        FreeLibrary(loaded);
        return hr;
    }
    step = "loaded";
    module = loaded;
    return S_OK;
}

/// Routes (a), (b) and (c) for the API's probe class, each logged. On success `factory`
/// holds the probe class's factory as `iid` and `g_routeModule` the module that served it
/// (null for the system registration).
static HRESULT resolveApi(REFIID iid, void **factory, std::string &log) {
    *factory = nullptr;
    const std::string api = narrow(std::wstring(g_api.rootNamespace));
    const std::string probe = narrow(std::wstring(g_api.probeClass));
    const std::string moduleName = narrow(std::wstring(g_api.moduleName));
    HSTRING_HEADER header;
    HSTRING name = nullptr;
    HRESULT hr = WindowsCreateStringReference(g_api.probeClass, (UINT32)wcslen(g_api.probeClass), &header, &name);
    if (FAILED(hr)) {
        logStep(log, "could not make the class name string (" + hex32((uint32_t)hr) + ")");
        return hr;
    }

    // (a) The system registration.
    HRESULT systemHr = systemFactory(name, iid, factory);
    if (SUCCEEDED(systemHr) && *factory) {
        logStep(log, (g_api.hasMidiApi ? "in-box API " : "registered API ") + probe + " resolved");
        return S_OK;
    }
    logStep(log, (g_api.hasMidiApi ? "in-box API not registered (" : api + " not registered (") + hex32((uint32_t)systemHr) + ")");

    // (b) The app-local module beside the executable.
    std::wstring directory = executableDirectory();
    std::wstring appLocal = directory + g_api.moduleName;
    if (directory.empty()) {
        logStep(log, "no app-local " + moduleName + " (executable folder unknown)");
    } else if (!fileExists(appLocal)) {
        logStep(log, "no app-local " + moduleName + " in " + narrow(directory));
    } else {
        HMODULE module = nullptr;
        std::string step;
        if (SUCCEEDED(factoryFromPath(appLocal, name, iid, factory, module, step))) {
            g_routeModule.store(module);
            logStep(log, "app-local " + narrow(appLocal) + ": " + step);
            return S_OK;
        }
        logStep(log, "app-local " + narrow(appLocal) + ": " + step);
    }

    // (c) The App SDK runtime.
    std::string source;
    std::wstring runtime = sdkRuntimeDirectory(source) + kSdkRuntimeModule;
    if (!fileExists(runtime)) {
        logStep(log, "no SDK runtime at " + narrow(runtime) + " (" + source + ")");
    } else if (!g_api.usesSdkRuntime) {
        logStep(log, "SDK runtime at " + narrow(runtime) + " (" + source +
                         "): present but not used: it is the superseded preview App SDK (Microsoft.Windows.Devices.Midi2) "
                         "and this build targets Windows.Devices.Midi2; put Windows.Devices.Midi2.dll and .pri beside the executable");
    } else {
        HMODULE module = nullptr;
        std::string step;
        if (SUCCEEDED(factoryFromPath(runtime, name, iid, factory, module, step))) {
            g_routeModule.store(module);
            logStep(log, "SDK runtime at " + narrow(runtime) + " (" + source + "): " + step);
            return S_OK;
        }
        logStep(log, "SDK runtime at " + narrow(runtime) + " (" + source + "): " + step);
    }
    return systemHr;
}

static std::string apiModeName(int32_t mode) {
    switch (mode) {
    case 0: return "API mode 0, Full Windows MIDI Services mode";
    case 1: return "API mode 1, Legacy API mode";
    case 2: return "API mode 2, Hybrid Legacy API mode";
    default: return "API mode " + std::to_string(mode);
    }
}

/// Windows build, does the API resolve, is the service usable. Runs on the MIDI thread.
static bool checkPlatform(std::string &log) {
    DWORD build = windowsBuildNumber();
    if (build < kMinimumBuild) {
        logStep(log, "Windows build " + std::to_string(build) + " is older than Windows 11 25H2 (build 26200), which the API needs");
        return false;
    }
    logStep(log, "Windows build " + std::to_string(build));

    if (g_api.hasMidiApi) {
        IMidiApiStaticsABI *statics = nullptr;
        if (FAILED(resolveApi(kIID_IMidiApiStatics, (void **)&statics, log)) || !statics) return false;
        IMidiApiStatics2ABI *statics2 = nullptr;
        if (SUCCEEDED(statics->QueryInterface(kIID_IMidiApiStatics2, (void **)&statics2)) && statics2) {
            unsigned char systemProvided = 0;
            if (SUCCEEDED(statics2->IsSystemProvided(&systemProvided))) {
                logStep(log, systemProvided ? "the copy that comes with Windows" : "the app's own copy");
            }
            statics2->Release();
        }
        unsigned char serviceAvailable = 0;
        int32_t mode = -1;
        HRESULT hr = statics->EnsureServiceAvailable(&serviceAvailable);
        statics->GetCurrentlySelectedApiMode(&mode);
        statics->Release();
        if (FAILED(hr) || !serviceAvailable) {
            logStep(log, "MidiApi.EnsureServiceAvailable() is false (" + apiModeName(mode) +
                             "; Legacy API mode or the midisrv service disabled)");
            return false;
        }
        logStep(log, "service available (" + apiModeName(mode) + ")");
        return true;
    }

    // The App SDK has no MidiApi: the factory proves the runtime, the MidiSrv transport
    // class the service, and MidiSession::Create (in startSession) demand-starts it.
    IActivationFactory *factory = nullptr;
    if (FAILED(resolveApi(kIID_IActivationFactory, (void **)&factory, log)) || !factory) return false;
    factory->Release();
    IUnknown *transport = nullptr;
    HRESULT hr = CoCreateInstance(kCLSID_MidiSrvTransport, nullptr, CLSCTX_INPROC_SERVER, kIID_IUnknown, (void **)&transport);
    if (FAILED(hr) || !transport) {
        logStep(log, "the Windows MIDI Services service is not installed (MidiSrv transport " + hex32((uint32_t)hr) + ")");
        return false;
    }
    transport->Release();
    logStep(log, "service installed");
    return true;
}

#if CWINMIDI2_PROJECTION
/// C++/WinRT's activation hook (winrt/base.h), installed when route (b) or (c) won.
static int32_t __stdcall midiActivationHandler(void *classId, winrt::guid const &iid, void **factory) noexcept {
    return resolveFactory((HSTRING)classId, *reinterpret_cast<const IID *>(&iid), factory);
}

/// Points C++/WinRT's activations at the chosen module, unless another component already
/// owns the hook (then C++/WinRT's own fallback, which loads <namespace>.dll by name from the
/// default search path, still finds an app-local Windows.Devices.Midi2.dll).
static void installActivationHook(std::string &log) {
    if (!g_routeModule.load()) return;
    if (winrt_activation_handler && winrt_activation_handler != midiActivationHandler) {
        logStep(log, "C++/WinRT activation hook already set by another component, left alone");
        return;
    }
    winrt_activation_handler = midiActivationHandler;
    logStep(log, "C++/WinRT activation hook installed");
}
#endif

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
#if CWINMIDI2_PROJECTION == 1
        // A runtime class in Windows.Devices.Midi2.Enumeration.
        midi2enum::MidiEndpointTransportSuppliedInfo transport = info.GetTransportSuppliedInfo();
        if (transport) {
            endpoint.manufacturer = winrt::to_string(transport.ManufacturerName());
            endpoint.vendorID = transport.VendorId();
            endpoint.productID = transport.ProductId();
        }
#else
        // A struct (fields) in the App SDK.
        midi2::MidiEndpointTransportSuppliedInfo transport = info.GetTransportSuppliedInfo();
        endpoint.manufacturer = winrt::to_string(transport.ManufacturerName);
        endpoint.vendorID = transport.VendorId;
        endpoint.productID = transport.ProductId;
#endif
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
static std::string *g_routes = new std::string();   // the attempt log, "Windows MIDI Services: ..."

/// The projection this build compiled, for the log.
static const char *projectionDescription() {
#if CWINMIDI2_PROJECTION == 1
    return "projection Windows.Devices.Midi2";
#elif CWINMIDI2_PROJECTION == 2
    return "projection Microsoft.Windows.Devices.Midi2 (preview App SDK)";
#else
    return "no projection";
#endif
}

bool cwinmidi2_available(char *error, size_t errorLength) {
    std::call_once(g_availableOnce, [] {
        std::string log;
        logStep(log, projectionDescription());
        bool platform = false;
        onMidiThread([&] {
#if CWINMIDI2_EXCEPTIONS
            try {
                platform = checkPlatform(log);
            } catch (...) {
                logStep(log, "the check threw a C++ exception");
                platform = false;
            }
#else
            platform = checkPlatform(log);
#endif
        });
#if CWINMIDI2_PROJECTION
        if (platform) {
            onMidiThread([&] { installActivationHook(log); });
            std::string sessionMessage;
            platform = guarded(sessionMessage, [&] { return startSession(sessionMessage); });
            logStep(log, platform ? std::string("session created") : "session failed: " + sessionMessage);
        }
#else
        if (platform) {
#if !CWINMIDI2_EXCEPTIONS
            logStep(log, "but CWinMIDI2 was compiled without C++ exceptions, which C++/WinRT needs");
#else
            logStep(log, "but CWinMIDI2 was built without a C++/WinRT projection (winrt/Windows.Devices.Midi2.h, "
                         "or winrt/Microsoft.Windows.Devices.Midi2.h; see ADR-0050)");
#endif
            platform = false;
        }
#endif
        g_available = platform;
        *g_routes = "Windows MIDI Services: " + log;
    });
    if (!g_available) putError(error, errorLength, *g_routes);
    return g_available;
}

size_t cwinmidi2_routes(char *buffer, size_t length) {
    cwinmidi2_available(nullptr, 0);
    putError(buffer, length, *g_routes);
    return g_routes->size();
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
    delete connection;
#endif
    // Without the projection `cwinmidi2_open` never returns a connection.
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
