// Windows MIDI Services output for the CoreMIDI module (ADR-0050). See cwinmidi2.h.
//
// Written against the raw WinRT ABI of `Windows.Devices.Midi2` (in box in Windows 11 25H2
// and later once it ships there; until then Windows.Devices.Midi2.dll and .pri from the NuGet
// package next to the executable), so it builds with the Windows SDK alone: no C++/WinRT
// projection, no cppwinrt.exe, no exceptions. The interfaces, IIDs, enums and runtime class
// names come from include/midi2abi.h, generated from the API's .winmd by
// tools/midi2abi/midi2abi.py; the few Windows.Foundation shapes it does not generate
// (IVectorView<T>, the TypedEventHandler delegates) are declared below. Every call checks its
// HRESULT; failures come back as `false` with the method and HRESULT in the message.
//
// ABI conventions (see the header comment of midi2abi.h): an interface is a struct whose
// first member is its vtable; a method's return value is its trailing out parameter; a result
// typed `IInspectable *` is the default interface of its runtime class, so the code
// QueryInterfaces it for the interface it calls. Objects are held by `Ref`, which releases.
//
// Activation. `resolveApi` is the one place the API is located, tried in order and logged:
//   (a) RoGetActivationFactory on the class name: the system registration (System32 once
//       the API is in Windows);
//   (b) the app-local Windows.Devices.Midi2.dll beside the executable, through its
//       DllGetActivationFactory;
//   (c) the superseded preview App SDK runtime (`Microsoft.Windows.Devices.Midi2`, a
//       different namespace), located as Microsoft's initializer does (registry key
//       HKLM\SOFTWARE\Microsoft\Windows MIDI Services\Desktop App SDK Runtime, value
//       "Installed"; else the installer's default folder): only reported, never used, so a PC
//       that has only it says why Windows MIDI Services is not in use.
// Every later activation (MidiSession, MidiClock, MidiEndpointDeviceInformation,
// MidiEndpointDeviceWatcher) goes through `resolveFactory`: the system registration first,
// then the module route (b) loaded.
//
// Every check appends to an attempt log, which `cwinmidi2_available` returns as its error and
// `cwinmidi2_routes` returns always, so the CoreMIDI start-up line names every route tried.
//
// Threading: every WinRT call runs on one thread the shim owns, which joins the
// multithreaded apartment, so no caller's apartment (the Win32 backend's main thread is an
// STA) is ever touched; this is the pattern of cwas_toast.cpp. The WinRT objects are kept in
// a heap block that is never freed, so static destruction at exit cannot release them after
// COM is gone. Watcher events arrive on WinRT thread-pool threads; their handlers only set a
// flag and call the change callback.
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
#include <eventtoken.h>
#include "midi2abi.h"
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

// MARK: - Helpers

static void putError(char *error, size_t length, const std::string &message) {
    if (!error || length == 0) return;
    size_t n = message.size() < length - 1 ? message.size() : length - 1;
    memcpy(error, message.data(), n);
    error[n] = 0;
}

static void copyString(char *dest, size_t capacity, const std::string &value) {
    size_t n = value.size() < capacity - 1 ? value.size() : capacity - 1;
    memcpy(dest, value.data(), n);
    dest[n] = 0;
}

static std::string hex32(uint32_t value) {
    char buffer[16];
    snprintf(buffer, sizeof buffer, "0x%08lx", (unsigned long)value);
    return buffer;
}

/// "<what> failed (0x...)".
static std::string failure(const char *what, HRESULT hr) {
    return std::string(what) + " failed (" + hex32((uint32_t)hr) + ")";
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

static std::wstring widen(const char *s) {
    if (!s) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
    return w;
}

static uint64_t fnv1a64(const std::string &value) {
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (unsigned char c : value) {
        hash ^= c;
        hash *= 0x100000001b3ULL;
    }
    return hash;
}

static bool sameIID(REFIID a, REFIID b) {
    return memcmp(&a, &b, sizeof(IID)) == 0;
}

/// UMP words per message, by message type (the top nibble of the first word).
static const uint32_t kWordsForType[16] = {1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4};

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

// MARK: - ABI plumbing

/// The runtime class names, `kClass_MidiSession` and so on, from the generated list.
#define X(name, string) static const wchar_t kClass_##name[] = string;
MIDI2ABI_CLASS_NAMES
#undef X

static const IID kIID_IUnknown = {0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const IID kIID_IAgileObject = {0x94ea2b94, 0xe9cc, 0x49e0, {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90}};

/// Release for the SDK's C++ interfaces (IUnknown, IInspectable, IActivationFactory)...
static void comRelease(IUnknown *object) { object->Release(); }
/// ...and for midi2abi.h's C vtable structs.
template <typename T>
static auto comRelease(T *object) -> decltype(object->lpVtbl, void()) {
    object->lpVtbl->Release(object);
}

/// Owns one reference.
template <typename T>
struct Ref {
    T *p = nullptr;
    Ref() = default;
    Ref(const Ref &) = delete;
    Ref &operator=(const Ref &) = delete;
    ~Ref() { reset(); }
    void reset() {
        if (p) comRelease(p);
        p = nullptr;
    }
    T **put() { reset(); return &p; }
    void **putVoid() { reset(); return reinterpret_cast<void **>(&p); }
    T *get() const { return p; }
    T *detach() { T *t = p; p = nullptr; return t; }
    explicit operator bool() const { return p != nullptr; }
};

/// QueryInterface on an `IInspectable *` result for the interface the caller uses.
template <typename T>
static HRESULT queryAs(IInspectable *object, REFIID iid, Ref<T> &out) {
    if (!object) return E_POINTER;
    return object->QueryInterface(iid, out.putVoid());
}

/// An owned HSTRING.
struct HStr {
    HSTRING h = nullptr;
    HStr() = default;
    HStr(const HStr &) = delete;
    HStr &operator=(const HStr &) = delete;
    ~HStr() { reset(); }
    void reset() {
        if (h) WindowsDeleteString(h);
        h = nullptr;
    }
    HSTRING *put() { reset(); return &h; }
    HRESULT set(const std::wstring &value) { return WindowsCreateString(value.c_str(), (UINT32)value.size(), put()); }
    std::string utf8() const {
        UINT32 length = 0;
        const wchar_t *raw = h ? WindowsGetStringRawBuffer(h, &length) : nullptr;
        return narrow(raw, length);
    }
};

/// Windows.Foundation.Collections.IVectorView<Windows.Devices.Midi2.Enumeration.
/// MidiEndpointDeviceInformation>, the standard vtable (midi2abi.h has only its IID). Items
/// are the class's default interface, received as IInspectable.
struct DeviceInfoVectorView;
struct DeviceInfoVectorViewVtbl {
    HRESULT(STDMETHODCALLTYPE *QueryInterface)(DeviceInfoVectorView *self, REFIID riid, void **object);
    ULONG(STDMETHODCALLTYPE *AddRef)(DeviceInfoVectorView *self);
    ULONG(STDMETHODCALLTYPE *Release)(DeviceInfoVectorView *self);
    HRESULT(STDMETHODCALLTYPE *GetIids)(DeviceInfoVectorView *self, ULONG *count, IID **iids);
    HRESULT(STDMETHODCALLTYPE *GetRuntimeClassName)(DeviceInfoVectorView *self, HSTRING *name);
    HRESULT(STDMETHODCALLTYPE *GetTrustLevel)(DeviceInfoVectorView *self, TrustLevel *level);
    HRESULT(STDMETHODCALLTYPE *GetAt)(DeviceInfoVectorView *self, uint32_t index, IInspectable **item);
    HRESULT(STDMETHODCALLTYPE *get_Size)(DeviceInfoVectorView *self, uint32_t *size);
    HRESULT(STDMETHODCALLTYPE *IndexOf)(DeviceInfoVectorView *self, IInspectable *value, uint32_t *index, boolean *found);
    HRESULT(STDMETHODCALLTYPE *GetMany)(DeviceInfoVectorView *self, uint32_t startIndex, uint32_t capacity, IInspectable **items, uint32_t *actual);
};
struct DeviceInfoVectorView { const DeviceInfoVectorViewVtbl *lpVtbl; };

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

/// Runs `work` on the MIDI thread and waits for it (inline when already there).
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

/// Runs `body` on the MIDI thread; false comes back with `message` set by `body`.
static bool onMidiThreadChecked(const std::function<bool()> &body) {
    bool ok = false;
    onMidiThread([&] { ok = body(); });
    return ok;
}

// MARK: - Activation

static const wchar_t kApiNamespace[] = L"Windows.Devices.Midi2";
static const wchar_t kModuleName[] = L"Windows.Devices.Midi2.dll";

static const wchar_t kSdkRuntimeKey[] = L"SOFTWARE\\Microsoft\\Windows MIDI Services\\Desktop App SDK Runtime";
static const wchar_t kSdkRuntimeValue[] = L"Installed";
static const wchar_t kSdkRuntimeModule[] = L"Microsoft.Windows.Devices.Midi2.dll";

#ifndef RRF_SUBKEY_WOW6464KEY
#define RRF_SUBKEY_WOW6464KEY 0x00010000
#endif

/// The module route (b) loaded, or null when the system registration serves the API.
/// Set once by the check, before any other activation.
static std::atomic<HMODULE> g_routeModule{nullptr};

/// The Windows 11 25H2 floor (24H2, 26100, has an older Windows MIDI Services that never
/// gets the API). The real build number: GetVersionEx lies to a process without a Windows 10
/// manifest.
static const DWORD kMinimumBuild = 26200;

static DWORD windowsBuildNumber() {
    typedef LONG(WINAPI * RtlGetVersionProc)(PRTL_OSVERSIONINFOW);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    RtlGetVersionProc rtlGetVersion = ntdll ? (RtlGetVersionProc)(void *)GetProcAddress(ntdll, "RtlGetVersion") : nullptr;
    RTL_OSVERSIONINFOW info;
    memset(&info, 0, sizeof info);
    info.dwOSVersionInfoSize = sizeof info;
    if (!rtlGetVersion || rtlGetVersion(&info) != 0) return 0;
    return info.dwBuildNumber;
}

/// DllGetActivationFactory on `module`, then QueryInterface for `iid`.
static HRESULT factoryFromModule(HMODULE module, HSTRING name, REFIID iid, void **factory) {
    typedef HRESULT(STDMETHODCALLTYPE * GetFactoryProc)(HSTRING, IActivationFactory **);
    GetFactoryProc getFactory = (GetFactoryProc)(void *)GetProcAddress(module, "DllGetActivationFactory");
    if (!getFactory) return HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
    IActivationFactory *activation = nullptr;
    HRESULT hr = getFactory(name, &activation);
    if (FAILED(hr)) return hr;
    if (!activation) return E_POINTER;
    hr = activation->QueryInterface(iid, factory);
    activation->Release();
    return hr;
}

/// RoGetActivationFactory, joining the MTA first when the calling thread has no apartment.
static HRESULT systemFactory(HSTRING name, REFIID iid, void **factory) {
    HRESULT hr = RoGetActivationFactory(name, iid, factory);
    if (hr == CO_E_NOTINITIALIZED) {
        CO_MTA_USAGE_COOKIE cookie = nullptr;
        if (SUCCEEDED(CoIncrementMTAUsage(&cookie))) hr = RoGetActivationFactory(name, iid, factory);
    }
    return hr;
}

/// True when `name` is in the namespace the app-local module serves.
static bool inApiNamespace(HSTRING name) {
    UINT32 length = 0;
    const wchar_t *raw = WindowsGetStringRawBuffer(name, &length);
    size_t rootLength = wcslen(kApiNamespace);
    if (!raw || length <= rootLength) return false;
    return wcsncmp(raw, kApiNamespace, rootLength) == 0 && raw[rootLength] == L'.';
}

/// Every activation after the check: the system registration first, then, for the API's own
/// classes, the module route (b) loaded.
static HRESULT resolveFactory(HSTRING name, REFIID iid, void **factory) {
    if (!factory) return E_POINTER;
    *factory = nullptr;
    HRESULT hr = systemFactory(name, iid, factory);
    if (SUCCEEDED(hr) && *factory) return hr;
    HMODULE module = g_routeModule.load();
    if (!module || !inApiNamespace(name)) return FAILED(hr) ? hr : E_POINTER;
    HRESULT moduleHr = factoryFromModule(module, name, iid, factory);
    return SUCCEEDED(moduleHr) ? moduleHr : hr;
}

/// The statics interface `iid` of runtime class `className` (a `kClass_` name).
template <typename T>
static HRESULT getStatics(const wchar_t *className, REFIID iid, Ref<T> &out) {
    HStr name;
    HRESULT hr = name.set(std::wstring(className));
    if (FAILED(hr)) return hr;
    return resolveFactory(name.h, iid, out.putVoid());
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
    // LOAD_WITH_ALTERED_SEARCH_PATH: the module's own dependencies resolve from its folder.
    HMODULE loaded = LoadLibraryExW(path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!loaded) {
        HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
        step = "LoadLibrary failed (" + hex32((uint32_t)hr) + ")";
        return hr;
    }
    HRESULT hr = factoryFromModule(loaded, name, iid, factory);
    if (FAILED(hr)) {
        step = "loaded, but DllGetActivationFactory(" + narrow(std::wstring(kClass_MidiApi)) + ") failed (" + hex32((uint32_t)hr) + ")";
        FreeLibrary(loaded);
        return hr;
    }
    step = "loaded";
    module = loaded;
    return S_OK;
}

/// Routes (a), (b) and (c) for MidiApi, each logged. On success `factory` holds the MidiApi
/// factory as `iid` and `g_routeModule` the module that served it (null for the system
/// registration).
static HRESULT resolveApi(REFIID iid, void **factory, std::string &log) {
    *factory = nullptr;
    const std::string probe = narrow(std::wstring(kClass_MidiApi));
    const std::string moduleName = narrow(std::wstring(kModuleName));
    HStr name;
    HRESULT hr = name.set(std::wstring(kClass_MidiApi));
    if (FAILED(hr)) {
        logStep(log, "could not make the class name string (" + hex32((uint32_t)hr) + ")");
        return hr;
    }

    // (a) The system registration.
    HRESULT systemHr = systemFactory(name.h, iid, factory);
    if (SUCCEEDED(systemHr) && *factory) {
        logStep(log, "in-box API " + probe + " resolved");
        return S_OK;
    }
    logStep(log, "in-box API not registered (" + hex32((uint32_t)systemHr) + ")");

    // (b) The app-local module beside the executable.
    std::wstring directory = executableDirectory();
    std::wstring appLocal = directory + kModuleName;
    if (directory.empty()) {
        logStep(log, "no app-local " + moduleName + " (executable folder unknown)");
    } else if (!fileExists(appLocal)) {
        logStep(log, "no app-local " + moduleName + " in " + narrow(directory));
    } else {
        HMODULE module = nullptr;
        std::string step;
        if (SUCCEEDED(factoryFromPath(appLocal, name.h, iid, factory, module, step))) {
            g_routeModule.store(module);
            logStep(log, "app-local " + narrow(appLocal) + ": " + step);
            return S_OK;
        }
        logStep(log, "app-local " + narrow(appLocal) + ": " + step);
    }

    // (c) The superseded App SDK runtime: reported, not used.
    std::string source;
    std::wstring runtime = sdkRuntimeDirectory(source) + kSdkRuntimeModule;
    if (!fileExists(runtime)) {
        logStep(log, "no SDK runtime at " + narrow(runtime) + " (" + source + ")");
    } else {
        logStep(log, "SDK runtime at " + narrow(runtime) + " (" + source +
                         "): present but not used: it is the superseded preview App SDK (Microsoft.Windows.Devices.Midi2) "
                         "and this build targets Windows.Devices.Midi2; put Windows.Devices.Midi2.dll and .pri beside the executable");
    }
    return FAILED(systemHr) ? systemHr : E_POINTER;
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

    Ref<IMidiApiStatics> statics;
    if (FAILED(resolveApi(IID_IMidiApiStatics, statics.putVoid(), log)) || !statics) return false;
    Ref<IMidiApiStatics2> statics2;
    if (SUCCEEDED(statics.get()->lpVtbl->QueryInterface(statics.get(), IID_IMidiApiStatics2, statics2.putVoid())) && statics2) {
        boolean systemProvided = 0;
        if (SUCCEEDED(statics2.get()->lpVtbl->IsSystemProvided(statics2.get(), &systemProvided))) {
            logStep(log, systemProvided ? "the copy that comes with Windows" : "the app's own copy");
        }
    }
    boolean serviceAvailable = 0;
    int32_t mode = -1;
    HRESULT hr = statics.get()->lpVtbl->EnsureServiceAvailable(statics.get(), &serviceAvailable);
    statics.get()->lpVtbl->GetCurrentlySelectedApiMode(statics.get(), &mode);
    if (FAILED(hr) || !serviceAvailable) {
        logStep(log, "MidiApi.EnsureServiceAvailable() is false (" + apiModeName(mode) +
                         "; Legacy API mode or the midisrv service disabled)");
        return false;
    }
    logStep(log, "service available (" + apiModeName(mode) + ")");
    return true;
}

// MARK: - Shared state

struct ChangeObserver {
    std::mutex lock;
    cwinmidi2_change_fn callback = nullptr;
    void *context = nullptr;
};
static ChangeObserver *g_observer = new ChangeObserver();

static void notifyChanged() {
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

/// The session, the watcher and the cached list. Set once by `cwinmidi2_available`, never
/// freed (nor are the references it holds).
struct MidiState {
    IMidiSession *session = nullptr;
    Enumeration_IMidiEndpointDeviceWatcher *watcher = nullptr;
    uint64_t sendImmediately = 0;
    std::mutex listLock;                 // guards endpoints
    std::vector<Endpoint> endpoints;
    std::atomic<bool> dirty{true};       // set by watcher events; the list is rebuilt lazily
};
static MidiState *g_state = nullptr;

struct CWinMIDI2Connection {
    IMidiEndpointConnection *connection = nullptr;
    GUID connectionId{};
};

// MARK: - Watcher event handlers

/// TypedEventHandler<MidiEndpointDeviceWatcher, MidiEndpointDevice...EventArgs>, implemented
/// by hand: a delegate is an IUnknown with Invoke(sender, args). One object per event, agile
/// (the watcher calls it from a thread-pool thread), answering the pinterface IID of its event.
/// The args are not read: like the list itself, the handler only marks the cache stale.
struct WatcherHandler;
struct WatcherHandlerVtbl {
    HRESULT(STDMETHODCALLTYPE *QueryInterface)(WatcherHandler *self, REFIID riid, void **object);
    ULONG(STDMETHODCALLTYPE *AddRef)(WatcherHandler *self);
    ULONG(STDMETHODCALLTYPE *Release)(WatcherHandler *self);
    HRESULT(STDMETHODCALLTYPE *Invoke)(WatcherHandler *self, IInspectable *sender, IInspectable *args);
};
struct WatcherHandler {
    const WatcherHandlerVtbl *lpVtbl;
    const IID *iid;                      // the delegate's pinterface IID
    std::atomic<ULONG> references;
    MidiState *state;
};

static HRESULT STDMETHODCALLTYPE watcherHandlerQueryInterface(WatcherHandler *self, REFIID riid, void **object) {
    if (!object) return E_POINTER;
    if (sameIID(riid, kIID_IUnknown) || sameIID(riid, kIID_IAgileObject) || sameIID(riid, *self->iid)) {
        self->references.fetch_add(1);
        *object = self;
        return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE watcherHandlerAddRef(WatcherHandler *self) {
    return self->references.fetch_add(1) + 1;
}

static ULONG STDMETHODCALLTYPE watcherHandlerRelease(WatcherHandler *self) {
    ULONG left = self->references.fetch_sub(1) - 1;
    if (left == 0) delete self;
    return left;
}

static HRESULT STDMETHODCALLTYPE watcherHandlerInvoke(WatcherHandler *self, IInspectable *sender, IInspectable *args) {
    (void)sender;
    (void)args;
    self->state->dirty = true;
    notifyChanged();
    return S_OK;
}

static const WatcherHandlerVtbl kWatcherHandlerVtbl = {watcherHandlerQueryInterface, watcherHandlerAddRef,
                                                       watcherHandlerRelease, watcherHandlerInvoke};

/// A handler with one reference, which the caller hands back with `watcherHandlerRelease`
/// after registering it (the watcher keeps its own).
static WatcherHandler *makeWatcherHandler(const IID &iid, MidiState *state) {
    WatcherHandler *handler = new WatcherHandler();
    handler->lpVtbl = &kWatcherHandlerVtbl;
    handler->iid = &iid;
    handler->references = 1;
    handler->state = state;
    return handler;
}

// MARK: - Session, enumeration, watcher

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

/// MidiEndpointDeviceInformation.FindAll(Name, AllStandardEndpoints), keeping what an app
/// sends to: normal endpoints and the in-box GM synth (the diagnostic loopbacks, ping and
/// virtual-device responders are left out). MIDI thread.
static bool enumerateEndpoints(std::vector<Endpoint> &result, std::string &message) {
    Ref<Enumeration_IMidiEndpointDeviceInformationStatics> statics;
    HRESULT hr = getStatics(kClass_Enumeration_MidiEndpointDeviceInformation, IID_Enumeration_IMidiEndpointDeviceInformationStatics, statics);
    if (FAILED(hr) || !statics) { message = failure("MidiEndpointDeviceInformation statics", hr); return false; }
    Ref<IInspectable> listObject;
    hr = statics.get()->lpVtbl->FindAll3(statics.get(), Enumeration_MidiEndpointDeviceInformationSortOrder_Name,
                                         Enumeration_MidiEndpointDeviceInformationFilters_AllStandardEndpoints, listObject.put());
    if (FAILED(hr)) { message = failure("MidiEndpointDeviceInformation.FindAll", hr); return false; }
    if (!listObject) return true;
    Ref<DeviceInfoVectorView> list;
    hr = queryAs(listObject.get(), IID_WF_Collections_IVectorView_MidiEndpointDeviceInformation, list);
    if (FAILED(hr) || !list) { message = failure("IVectorView<MidiEndpointDeviceInformation> QueryInterface", hr); return false; }
    uint32_t size = 0;
    hr = list.get()->lpVtbl->get_Size(list.get(), &size);
    if (FAILED(hr)) { message = failure("IVectorView.Size", hr); return false; }
    for (uint32_t i = 0; i < size; i++) {
        Ref<IInspectable> item;
        if (FAILED(list.get()->lpVtbl->GetAt(list.get(), i, item.put())) || !item) continue;
        Ref<Enumeration_IMidiEndpointDeviceInformation> info;
        if (FAILED(queryAs(item.get(), IID_Enumeration_IMidiEndpointDeviceInformation, info)) || !info) continue;
        Enumeration_IMidiEndpointDeviceInformation *p = info.get();
        int32_t purpose = -1;
        if (FAILED(p->lpVtbl->get_EndpointPurpose(p, &purpose))) continue;
        if (purpose != Enumeration_MidiEndpointDevicePurpose_NormalMessageEndpoint &&
            purpose != Enumeration_MidiEndpointDevicePurpose_InBoxGeneralMidiSynth) continue;
        Endpoint endpoint;
        HStr id, name;
        if (FAILED(p->lpVtbl->get_EndpointDeviceId(p, id.put()))) continue;
        endpoint.id = id.utf8();
        if (endpoint.id.empty()) continue;
        if (SUCCEEDED(p->lpVtbl->get_Name(p, name.put()))) endpoint.name = name.utf8();
        endpoint.purpose = purpose;
        Ref<IInspectable> transportObject;
        Ref<Enumeration_IMidiEndpointTransportSuppliedInfo> transport;
        if (SUCCEEDED(p->lpVtbl->GetTransportSuppliedInfo(p, transportObject.put())) && transportObject &&
            SUCCEEDED(queryAs(transportObject.get(), IID_Enumeration_IMidiEndpointTransportSuppliedInfo, transport)) && transport) {
            Enumeration_IMidiEndpointTransportSuppliedInfo *t = transport.get();
            HStr manufacturer;
            if (SUCCEEDED(t->lpVtbl->get_ManufacturerName(t, manufacturer.put()))) endpoint.manufacturer = manufacturer.utf8();
            uint16_t vendor = 0, product = 0;
            if (SUCCEEDED(t->lpVtbl->get_VendorId(t, &vendor))) endpoint.vendorID = vendor;
            if (SUCCEEDED(t->lpVtbl->get_ProductId(t, &product))) endpoint.productID = product;
        }
        if (endpoint.name.empty()) endpoint.name = endpoint.id;
        result.push_back(endpoint);
    }
    return true;
}

/// Rebuilds the cached list when a watcher event (or nothing yet) made it stale.
static void refreshIfDirty() {
    if (!g_state || !g_state->dirty.exchange(false)) return;
    std::string message;
    std::vector<Endpoint> fresh;
    bool ok = onMidiThreadChecked([&] { return enumerateEndpoints(fresh, message); });
    if (!ok) {
        g_state->dirty = true;   // try again next time
        return;
    }
    std::lock_guard<std::mutex> l(g_state->listLock);
    g_state->endpoints = std::move(fresh);
}

/// MidiEndpointDeviceWatcher.Create(AllStandardEndpoints) with Added, Removed and Updated
/// handlers, started. Null with `message` set on failure. MIDI thread.
static Enumeration_IMidiEndpointDeviceWatcher *startWatcher(MidiState *state, std::string &message) {
    Ref<Enumeration_IMidiEndpointDeviceWatcherStatics> statics;
    HRESULT hr = getStatics(kClass_Enumeration_MidiEndpointDeviceWatcher, IID_Enumeration_IMidiEndpointDeviceWatcherStatics, statics);
    if (FAILED(hr) || !statics) { message = failure("MidiEndpointDeviceWatcher statics", hr); return nullptr; }
    Ref<IInspectable> watcherObject;
    hr = statics.get()->lpVtbl->Create2(statics.get(), Enumeration_MidiEndpointDeviceInformationFilters_AllStandardEndpoints, watcherObject.put());
    if (FAILED(hr) || !watcherObject) { message = failure("MidiEndpointDeviceWatcher.Create", hr); return nullptr; }
    Ref<Enumeration_IMidiEndpointDeviceWatcher> watcher;
    hr = queryAs(watcherObject.get(), IID_Enumeration_IMidiEndpointDeviceWatcher, watcher);
    if (FAILED(hr) || !watcher) { message = failure("IMidiEndpointDeviceWatcher QueryInterface", hr); return nullptr; }
    Enumeration_IMidiEndpointDeviceWatcher *w = watcher.get();

    struct Registration {
        const IID &iid;
        HRESULT(STDMETHODCALLTYPE *add)(Enumeration_IMidiEndpointDeviceWatcher *, IInspectable *, EventRegistrationToken *);
        const char *what;
    };
    const Registration registrations[] = {
        {IID_WF_TypedEventHandler_MidiEndpointDeviceWatcher_MidiEndpointDeviceInformationAddedEventArgs, w->lpVtbl->add_Added, "MidiEndpointDeviceWatcher.Added"},
        {IID_WF_TypedEventHandler_MidiEndpointDeviceWatcher_MidiEndpointDeviceInformationRemovedEventArgs, w->lpVtbl->add_Removed, "MidiEndpointDeviceWatcher.Removed"},
        {IID_WF_TypedEventHandler_MidiEndpointDeviceWatcher_MidiEndpointDeviceInformationUpdatedEventArgs, w->lpVtbl->add_Updated, "MidiEndpointDeviceWatcher.Updated"},
    };
    for (const Registration &registration : registrations) {
        WatcherHandler *handler = makeWatcherHandler(registration.iid, state);
        EventRegistrationToken token{};
        hr = registration.add(w, reinterpret_cast<IInspectable *>(handler), &token);
        watcherHandlerRelease(handler);
        if (FAILED(hr)) { message = failure(registration.what, hr); return nullptr; }
    }
    hr = w->lpVtbl->Start(w);
    if (FAILED(hr)) { message = failure("MidiEndpointDeviceWatcher.Start", hr); return nullptr; }
    return watcher.detach();
}

/// The session, the send-immediately timestamp and the endpoint watcher. MIDI thread.
static bool startSession(std::string &message) {
    Ref<IMidiSessionStatics> sessionStatics;
    HRESULT hr = getStatics(kClass_MidiSession, IID_IMidiSessionStatics, sessionStatics);
    if (FAILED(hr) || !sessionStatics) { message = failure("MidiSession statics", hr); return false; }
    HStr name;
    hr = name.set(widen(sessionName().c_str()));
    if (FAILED(hr)) { message = failure("WindowsCreateString", hr); return false; }
    Ref<IInspectable> sessionObject;
    hr = sessionStatics.get()->lpVtbl->Create(sessionStatics.get(), name.h, sessionObject.put());
    if (FAILED(hr)) { message = failure("MidiSession.Create", hr); return false; }
    if (!sessionObject) { message = "MidiSession.Create returned null"; return false; }
    Ref<IMidiSession> session;
    hr = queryAs(sessionObject.get(), IID_IMidiSession, session);
    if (FAILED(hr) || !session) { message = failure("IMidiSession QueryInterface", hr); return false; }

    Ref<IMidiClockStatics> clock;
    hr = getStatics(kClass_MidiClock, IID_IMidiClockStatics, clock);
    if (FAILED(hr) || !clock) { message = failure("MidiClock statics", hr); return false; }
    uint64_t sendImmediately = 0;
    hr = clock.get()->lpVtbl->get_TimestampConstantSendImmediately(clock.get(), &sendImmediately);
    if (FAILED(hr)) { message = failure("MidiClock.TimestampConstantSendImmediately", hr); return false; }

    MidiState *state = new MidiState();
    state->session = session.detach();
    state->sendImmediately = sendImmediately;
    // The watcher keeps the cached list current; without it the list is rebuilt on every
    // read (the CoreMIDI server rescans every 2 s while a client exists).
    std::string watcherMessage;
    state->watcher = startWatcher(state, watcherMessage);
    if (!state->watcher) {
        fprintf(stderr, "CoreMIDI: MidiEndpointDeviceWatcher unavailable (%s); rescanning on every read\n", watcherMessage.c_str());
    }
    g_state = state;
    return true;
}

/// "Succeeded" is a flag bit of MidiSendMessageResults (what
/// MidiEndpointConnection.SendMessageSucceeded tests).
static bool sendSucceeded(int32_t result) {
    return (result & MidiSendMessageResults_Succeeded) != 0;
}

// MARK: - C interface

static std::once_flag g_availableOnce;
static bool g_available = false;
static std::string *g_routes = new std::string();   // the attempt log, "Windows MIDI Services: ..."

bool cwinmidi2_available(char *error, size_t errorLength) {
    std::call_once(g_availableOnce, [] {
        std::string log;
        logStep(log, "ABI Windows.Devices.Midi2");
        bool platform = false;
        onMidiThread([&] { platform = checkPlatform(log); });
        if (platform) {
            std::string sessionMessage;
            platform = onMidiThreadChecked([&] { return startSession(sessionMessage); });
            logStep(log, platform ? std::string("session created") : "session failed: " + sessionMessage);
        }
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
    if (!g_state) return 0;
    if (!g_state->watcher) g_state->dirty = true;
    refreshIfDirty();
    std::lock_guard<std::mutex> l(g_state->listLock);
    return (uint32_t)g_state->endpoints.size();
}

bool cwinmidi2_destination(uint32_t index, CWinMIDI2EndpointInfo *info) {
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
}

CWinMIDI2Connection *cwinmidi2_open(const char *endpointDeviceId, char *error, size_t errorLength) {
    if (!g_state) { putError(error, errorLength, "Windows MIDI Services is not initialized"); return nullptr; }
    if (!endpointDeviceId || !*endpointDeviceId) { putError(error, errorLength, "no endpoint device id"); return nullptr; }
    std::string message;
    CWinMIDI2Connection *result = nullptr;
    std::wstring id = widen(endpointDeviceId);
    bool ok = onMidiThreadChecked([&] {
        IMidiSession *session = g_state->session;
        HStr idString;
        HRESULT hr = idString.set(id);
        if (FAILED(hr)) { message = failure("WindowsCreateString", hr); return false; }
        Ref<IInspectable> connectionObject;
        hr = session->lpVtbl->CreateEndpointConnection(session, idString.h, connectionObject.put());
        if (FAILED(hr)) { message = failure("MidiSession.CreateEndpointConnection", hr); return false; }
        if (!connectionObject) { message = "MidiSession.CreateEndpointConnection returned null"; return false; }
        Ref<IMidiEndpointConnection> connection;
        hr = queryAs(connectionObject.get(), IID_IMidiEndpointConnection, connection);
        if (FAILED(hr) || !connection) { message = failure("IMidiEndpointConnection QueryInterface", hr); return false; }
        // ConnectionId is on IMidiEndpointConnectionSource, which the class also implements.
        GUID connectionId{};
        Ref<IMidiEndpointConnectionSource> source;
        hr = queryAs(connectionObject.get(), IID_IMidiEndpointConnectionSource, source);
        if (SUCCEEDED(hr) && source) hr = source.get()->lpVtbl->get_ConnectionId(source.get(), &connectionId);
        if (FAILED(hr)) { message = failure("MidiEndpointConnection.ConnectionId", hr); return false; }
        boolean opened = 0;
        hr = connection.get()->lpVtbl->Open(connection.get(), &opened);
        if (FAILED(hr) || !opened) {
            session->lpVtbl->DisconnectEndpointConnection(session, connectionId);
            message = FAILED(hr) ? failure("MidiEndpointConnection.Open()", hr) : std::string("MidiEndpointConnection.Open() returned false");
            return false;
        }
        result = new CWinMIDI2Connection();
        result->connection = connection.detach();
        result->connectionId = connectionId;
        return true;
    });
    if (!ok) {
        putError(error, errorLength, message);
        return nullptr;
    }
    return result;
}

bool cwinmidi2_send_ump(CWinMIDI2Connection *connection, const uint32_t *words, uint32_t wordCount, char *error, size_t errorLength) {
    if (!connection || !connection->connection || !g_state) { putError(error, errorLength, "no connection"); return false; }
    if (wordCount == 0) return true;
    if (!words) { putError(error, errorLength, "no words"); return false; }
    std::string message;
    bool ok = onMidiThreadChecked([&] {
        IMidiEndpointConnection *c = connection->connection;
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
            int32_t r = 0;
            HRESULT hr;
            switch (size) {
            case 1: hr = c->lpVtbl->SendSingleMessageWords(c, ts, w[0], &r); break;
            case 2: hr = c->lpVtbl->SendSingleMessageWords2(c, ts, w[0], w[1], &r); break;
            case 3: hr = c->lpVtbl->SendSingleMessageWords3(c, ts, w[0], w[1], w[2], &r); break;
            default: hr = c->lpVtbl->SendSingleMessageWords4(c, ts, w[0], w[1], w[2], w[3], &r); break;
            }
            if (FAILED(hr)) {
                message = failure("SendSingleMessageWords", hr) + " for word " + hex32(w[0]);
                return false;
            }
            if (!sendSucceeded(r)) {
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
}

void cwinmidi2_close(CWinMIDI2Connection *connection) {
    if (!connection) return;
    onMidiThread([&] {
        if (g_state && g_state->session) {
            g_state->session->lpVtbl->DisconnectEndpointConnection(g_state->session, connection->connectionId);
        }
        if (connection->connection) comRelease(connection->connection);
        connection->connection = nullptr;
    });
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
