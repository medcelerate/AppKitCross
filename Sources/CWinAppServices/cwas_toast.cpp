// Toast notifications for an unpackaged desktop app (ADR-0043). See cwas.h.
//
// An unpackaged app gets toasts by registering an AppUserModelID under
// HKCU\Software\Classes\AppUserModelId (display name, icon), giving the shell a Start-menu
// shortcut that carries that ID, and creating the notifier with that ID. Without the shortcut
// Windows 11 accepts every toast (Show succeeds, history lists it) and displays none, and it
// takes the shell some seconds to pick up a new shortcut: toasts shown in that window never
// surface. So the shim makes the shortcut when it creates the notifier and, while the shell
// has not yet displayed one of the app's toasts, shows a fresh toast again a few times
// (see `retryUntilDisplayed`).
//
// A click on a live banner raises the toast object's Activated event; a click in the
// notification center does not (checked on the PC: the toast just closed). The shell delivers
// those to the app's COM activator, the class named by the shortcut's ToastActivatorCLSID, so
// the shim registers one (HKCU\Software\Classes\CLSID\{clsid}\LocalServer32 and the class
// object in this process). Both paths go through `deliverActivation`, which reports a toast
// once, while it is still the one shown under its tag. The activation arguments carry the tag
// (ToastXML.swift). The shim keeps every shown toast and its handlers alive until it is
// activated, dismissed by the user, or removed. A click after the app quit starts the app
// (COM runs LocalServer32 with -Embedding) but is not reported to it.
//
// Plain COM over the WinRT ABI headers (no WRL, no C++/WinRT): the three event handlers are
// small hand-written agile objects.
//
// Every WinRT call runs on one thread the shim owns, which joins the multithreaded apartment.
// The Swift side calls in from the main thread (a single-threaded apartment, since the Win32
// backend initializes OLE for drag and drop), from the notification center's queue and from
// trigger timers. A notifier created in one of those apartments and used from another fails
// with RPC_E_WRONG_THREAD, so none of them touches WinRT directly.
#if defined(_WIN32)
#include "cwas.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <roapi.h>
#include <winstring.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propsys.h>
#include <windows.foundation.h>
#include <windows.foundation.collections.h>
#include <windows.data.xml.dom.h>
#include <windows.ui.notifications.h>
#include <NotificationActivationCallback.h>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <cwchar>
#include <condition_variable>
#include <deque>
#include <functional>
#include <thread>
#include <map>
#include <mutex>
#include <string>
#include <vector>

using namespace ABI::Windows::Foundation;
using namespace ABI::Windows::Foundation::Collections;
using namespace ABI::Windows::Data::Xml::Dom;
using namespace ABI::Windows::UI::Notifications;

static std::wstring widen(const char *s) {
    if (!s) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
    return w;
}

static std::string narrow(const wchar_t *w, UINT32 length) {
    if (!w || length == 0) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w, (int)length, nullptr, 0, nullptr, nullptr);
    std::string s(n > 0 ? n : 0, '\0');
    if (n > 0) WideCharToMultiByte(CP_UTF8, 0, w, (int)length, &s[0], n, nullptr, nullptr);
    return s;
}

static std::string narrow(HSTRING h) {
    UINT32 length = 0;
    const wchar_t *raw = WindowsGetStringRawBuffer(h, &length);
    return narrow(raw, length);
}

/// An owned HSTRING.
struct HStr {
    HSTRING h = nullptr;
    explicit HStr(const std::wstring &s) { WindowsCreateString(s.c_str(), (UINT32)s.size(), &h); }
    explicit HStr(const wchar_t *s) { WindowsCreateString(s, (UINT32)wcslen(s), &h); }
    ~HStr() { if (h) WindowsDeleteString(h); }
    HStr(const HStr &) = delete;
    HStr &operator=(const HStr &) = delete;
};

template <typename T> static void release(T *&p) { if (p) { p->Release(); p = nullptr; } }

struct LiveToast {
    IToastNotification *toast = nullptr;
    uint64_t serial = 0;   // which show this is, so a retry can tell it was replaced or removed
    std::wstring group;
    std::vector<std::wstring> inputIds;
};

static std::mutex g_lock;
static CO_MTA_USAGE_COOKIE g_mtaCookie = nullptr;
static IToastNotifier *g_notifier = nullptr;
static IToastNotificationHistory *g_history = nullptr;
static std::wstring g_aumid;
static uint64_t g_nextSerial = 0;
/// Set once the shell has reported anything about one of the app's toasts (a click, a close,
/// a timeout into the notification center): it displays them, so no re-show is needed.
static std::atomic<bool> g_shellShowedToast(false);
static CLSID g_activatorClsid = {};
static DWORD g_activatorCookie = 0;
/// GetTickCount64 when this process made or repaired the Start-menu shortcut; 0 otherwise.
static ULONGLONG g_shortcutMadeAt = 0;
static cwas_toast_activated_fn g_activated = nullptr;
static cwas_toast_dismissed_fn g_dismissed = nullptr;
static void *g_context = nullptr;
static std::map<std::wstring, LiveToast> g_live;   // keyed by group + "\n" + tag

static std::wstring liveKey(const std::wstring &tag, const std::wstring &group) { return group + L"\n" + tag; }

static void ensureMTA() {
    if (!g_mtaCookie) CoIncrementMTAUsage(&g_mtaCookie);
}

/// The toast thread's work queue. Allocated once and never freed, so process exit cannot
/// destroy it under the waiting thread.
struct ToastThread {
    std::mutex lock;
    std::condition_variable ready;
    std::deque<std::function<void()>> jobs;
    std::thread::id id;
};
static ToastThread *g_toastThread = nullptr;
static std::once_flag g_toastThreadOnce;

static void toastThreadMain(ToastThread *t) {
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

/// Runs `work` on the toast thread and waits for it (inline when already there).
static void onToastThread(const std::function<void()> &work) {
    std::call_once(g_toastThreadOnce, [] {
        ToastThread *t = new ToastThread();
        std::thread thread(toastThreadMain, t);
        t->id = thread.get_id();
        thread.detach();
        g_toastThread = t;
    });
    ToastThread *t = g_toastThread;
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

static const char *apartmentName() {
    APTTYPE type;
    APTTYPEQUALIFIER qualifier;
    if (FAILED(CoGetApartmentType(&type, &qualifier))) return "none";
    switch (type) {
    case APTTYPE_MTA: return "MTA";
    case APTTYPE_STA: return "STA";
    case APTTYPE_MAINSTA: return "main STA";
    case APTTYPE_NA: return "NA";
    default: return "other";
    }
}

/// One line on stderr naming the calling thread and the toast thread, so a call that ever
/// lands in the wrong apartment again says where it came from.
static void traceThread(const char *what, const char *detail, DWORD caller, HRESULT hr) {
    fprintf(stderr, "UserNotifications: %s%s%s on toast thread %lu (%s), called from thread %lu, HRESULT 0x%08lx\n",
            what, detail && *detail ? " " : "", detail ? detail : "",
            (unsigned long)GetCurrentThreadId(), apartmentName(), (unsigned long)caller, (unsigned long)hr);
}

static std::wstring tagOf(IToastNotification *toast, std::wstring *group) {
    std::wstring tag;
    IToastNotification2 *t2 = nullptr;
    if (toast && SUCCEEDED(toast->QueryInterface(__uuidof(IToastNotification2), reinterpret_cast<void **>(&t2)))) {
        HSTRING h = nullptr;
        if (SUCCEEDED(t2->get_Tag(&h)) && h) {
            UINT32 n = 0;
            const wchar_t *raw = WindowsGetStringRawBuffer(h, &n);
            tag.assign(raw, n);
            WindowsDeleteString(h);
        }
        if (group) {
            h = nullptr;
            if (SUCCEEDED(t2->get_Group(&h)) && h) {
                UINT32 n = 0;
                const wchar_t *raw = WindowsGetStringRawBuffer(h, &n);
                group->assign(raw, n);
                WindowsDeleteString(h);
            }
        }
        t2->Release();
    }
    return tag;
}

/// Forgets a live toast (it was activated, dismissed by the user, or removed) if `toast` is
/// still the one shown under its tag; returns its text box ids.
static std::vector<std::wstring> forget(IToastNotification *toast, const std::wstring &tag, const std::wstring &group, bool *found = nullptr) {
    std::vector<std::wstring> ids;
    IToastNotification *drop = nullptr;
    if (found) *found = false;
    {
        std::lock_guard<std::mutex> guard(g_lock);
        auto it = g_live.find(liveKey(tag, group));
        if (it != g_live.end() && (toast == nullptr || it->second.toast == toast)) {
            ids = it->second.inputIds;
            drop = it->second.toast;
            g_live.erase(it);
            if (found) *found = true;
        }
    }
    release(drop);
    return ids;
}

/// Whether `toast` is still the one shown under its tag. Events from a toast that a newer one
/// replaced, or that the app removed, are not reported.
static bool isLive(IToastNotification *toast, const std::wstring &tag, const std::wstring &group) {
    std::lock_guard<std::mutex> guard(g_lock);
    auto it = g_live.find(liveKey(tag, group));
    return it != g_live.end() && it->second.toast == toast;
}

static std::vector<std::wstring> inputIdsOf(IToastNotification *toast, const std::wstring &tag, const std::wstring &group) {
    std::lock_guard<std::mutex> guard(g_lock);
    auto it = g_live.find(liveKey(tag, group));
    if (it != g_live.end() && it->second.toast == toast) return it->second.inputIds;
    return {};
}

/// Common IUnknown for the agile event handlers.
template <typename Interface>
class Handler : public Interface {
    LONG refs = 1;
public:
    virtual ~Handler() {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IAgileObject) || riid == __uuidof(Interface)) {
            *object = static_cast<Interface *>(this);
            AddRef();
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return (ULONG)InterlockedIncrement(&refs); }
    ULONG STDMETHODCALLTYPE Release() override {
        LONG r = InterlockedDecrement(&refs);
        if (r == 0) delete this;
        return (ULONG)r;
    }
};

typedef ITypedEventHandler<ToastNotification *, IInspectable *> ActivatedHandler;
typedef ITypedEventHandler<ToastNotification *, ToastDismissedEventArgs *> DismissedHandler;
typedef ITypedEventHandler<ToastNotification *, ToastFailedEventArgs *> FailedHandler;

static int hexValue(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

static std::string percentDecoded(const std::string &s) {
    std::string out;
    for (size_t i = 0; i < s.size(); i++) {
        int hi, lo;
        if (s[i] == '%' && i + 2 < s.size() && (hi = hexValue(s[i + 1])) >= 0 && (lo = hexValue(s[i + 2])) >= 0) {
            out.push_back((char)(hi * 16 + lo));
            i += 2;
        } else {
            out.push_back(s[i]);
        }
    }
    return out;
}

/// Splits ToastXML's activation arguments, "{tag} {action}" each percent-encoded. False for
/// arguments in any other form.
static bool parseArguments(const std::string &arguments, std::string *tag, std::string *action) {
    size_t space = arguments.find(' ');
    if (space == std::string::npos) return false;
    *tag = percentDecoded(arguments.substr(0, space));
    *action = percentDecoded(arguments.substr(space + 1));
    return true;
}

/// The group of the live toast with this tag (the COM activator gets no toast object).
static bool liveGroupOf(const std::wstring &tag, std::wstring *group) {
    std::lock_guard<std::mutex> guard(g_lock);
    for (auto &entry : g_live) {
        size_t newline = entry.first.find(L'\n');
        if (newline != std::wstring::npos && entry.first.compare(newline + 1, std::wstring::npos, tag) == 0) {
            *group = entry.second.group;
            return true;
        }
    }
    return false;
}

/// Reports a click or button press once. `sender` is the toast object (the Activated event) or
/// null (the COM activator); `inputs` maps text box ids to the typed text.
static void deliverActivation(IToastNotification *sender, const std::string &arguments,
                              const std::map<std::wstring, std::wstring> &inputs, const char *via) {
    std::string tagUtf8, action;
    std::wstring group;
    if (sender) {
        std::wstring tag = tagOf(sender, &group);
        std::string encodedTag;
        if (!parseArguments(arguments, &encodedTag, &action)) action = arguments;
        tagUtf8 = narrow(tag.c_str(), (UINT32)tag.size());
    } else if (!parseArguments(arguments, &tagUtf8, &action)) {
        fprintf(stderr, "UserNotifications: activation with arguments \"%s\" that are not this app's; ignored\n", arguments.c_str());
        return;
    }
    std::wstring tag = widen(tagUtf8.c_str());
    g_shellShowedToast = true;
    bool found = false;
    std::vector<std::wstring> ids;
    if (sender || liveGroupOf(tag, &group)) ids = forget(sender, tag, group, &found);
    if (GetEnvironmentVariableA("APPKITWIN_TRACE_TOASTS", nullptr, 0) > 0 || !found) {
        fprintf(stderr, "UserNotifications: activation of toast %s action %s via %s%s\n", tagUtf8.c_str(), action.c_str(), via,
                found ? "" : " (not a toast this process shows, or already reported; ignored)");
    }
    if (!found) return;
    std::string packed;
    for (const std::wstring &id : ids) {
        auto it = inputs.find(id);
        if (it == inputs.end()) continue;
        packed.append(narrow(id.c_str(), (UINT32)id.size()));
        packed.push_back('\0');
        packed.append(narrow(it->second.c_str(), (UINT32)it->second.size()));
        packed.push_back('\0');
    }
    packed.push_back('\0');
    if (g_activated) g_activated(g_context, tagUtf8.c_str(), action.c_str(), ids.empty() ? nullptr : packed.data());
}

class ActivatedSink : public Handler<ActivatedHandler> {
public:
    HRESULT STDMETHODCALLTYPE Invoke(IToastNotification *sender, IInspectable *args) override {
        std::wstring group;
        std::wstring tag = tagOf(sender, &group);
        std::string arguments;
        std::map<std::wstring, std::wstring> inputs;
        std::vector<std::wstring> ids = inputIdsOf(sender, tag, group);
        IToastActivatedEventArgs *a = nullptr;
        if (args && SUCCEEDED(args->QueryInterface(__uuidof(IToastActivatedEventArgs), reinterpret_cast<void **>(&a)))) {
            HSTRING h = nullptr;
            if (SUCCEEDED(a->get_Arguments(&h)) && h) { arguments = narrow(h); WindowsDeleteString(h); }
            a->Release();
        }
        IToastActivatedEventArgs2 *a2 = nullptr;
        if (!ids.empty() && args && SUCCEEDED(args->QueryInterface(__uuidof(IToastActivatedEventArgs2), reinterpret_cast<void **>(&a2)))) {
            IPropertySet *set = nullptr;
            if (SUCCEEDED(a2->get_UserInput(&set)) && set) {
                IMap<HSTRING, IInspectable *> *map = nullptr;
                if (SUCCEEDED(set->QueryInterface(__uuidof(IMap<HSTRING, IInspectable *>), reinterpret_cast<void **>(&map)))) {
                    for (const std::wstring &id : ids) {
                        HStr key(id);
                        boolean has = false;
                        if (FAILED(map->HasKey(key.h, &has)) || !has) continue;
                        IInspectable *value = nullptr;
                        if (FAILED(map->Lookup(key.h, &value)) || !value) continue;
                        IPropertyValue *pv = nullptr;
                        if (SUCCEEDED(value->QueryInterface(__uuidof(IPropertyValue), reinterpret_cast<void **>(&pv)))) {
                            HSTRING text = nullptr;
                            if (SUCCEEDED(pv->GetString(&text))) {
                                UINT32 n = 0;
                                const wchar_t *raw = text ? WindowsGetStringRawBuffer(text, &n) : nullptr;
                                inputs[id] = raw ? std::wstring(raw, n) : std::wstring();
                                if (text) WindowsDeleteString(text);
                            }
                            pv->Release();
                        }
                        value->Release();
                    }
                    map->Release();
                }
                set->Release();
            }
            a2->Release();
        }
        deliverActivation(sender, arguments, inputs, "the Activated event");
        return S_OK;
    }
};

/// The COM activator: the shell calls Activate for clicks in the notification center (and for
/// banner clicks, which the Activated event may also report; deliverActivation reports one).
class ActivationCallback : public INotificationActivationCallback {
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(INotificationActivationCallback)) {
            *object = static_cast<INotificationActivationCallback *>(this);
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return 2; }    // a static object
    ULONG STDMETHODCALLTYPE Release() override { return 1; }
    HRESULT STDMETHODCALLTYPE Activate(LPCWSTR appUserModelId, LPCWSTR invokedArgs,
                                       const NOTIFICATION_USER_INPUT_DATA *data, ULONG count) override {
        (void)appUserModelId;
        std::map<std::wstring, std::wstring> inputs;
        for (ULONG i = 0; data && i < count; i++) {
            if (data[i].Key) inputs[data[i].Key] = data[i].Value ? data[i].Value : L"";
        }
        std::string arguments = invokedArgs ? narrow(invokedArgs, (UINT32)wcslen(invokedArgs)) : std::string();
        deliverActivation(nullptr, arguments, inputs, "the COM activator");
        return S_OK;
    }
};

class ActivatorFactory : public IClassFactory {
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **object) override {
        if (!object) return E_POINTER;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IClassFactory)) {
            *object = static_cast<IClassFactory *>(this);
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return 2; }
    ULONG STDMETHODCALLTYPE Release() override { return 1; }
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown *outer, REFIID riid, void **object) override;
    HRESULT STDMETHODCALLTYPE LockServer(BOOL) override { return S_OK; }
};

static ActivationCallback g_activationCallback;
static ActivatorFactory g_activatorFactory;

HRESULT STDMETHODCALLTYPE ActivatorFactory::CreateInstance(IUnknown *outer, REFIID riid, void **object) {
    if (outer) return CLASS_E_NOAGGREGATION;
    return g_activationCallback.QueryInterface(riid, object);
}

class DismissedSink : public Handler<DismissedHandler> {
public:
    HRESULT STDMETHODCALLTYPE Invoke(IToastNotification *sender, IToastDismissedEventArgs *args) override {
        std::wstring group;
        std::wstring tag = tagOf(sender, &group);
        ToastDismissalReason reason = ToastDismissalReason_UserCanceled;
        if (args) args->get_Reason(&reason);
        int code = reason == ToastDismissalReason_UserCanceled ? 0 : reason == ToastDismissalReason_ApplicationHidden ? 1 : 2;
        // A timed-out toast moved to Action Center and can still be clicked: keep its handlers.
        bool live = false;
        if (code != 2) forget(sender, tag, group, &live);
        else live = isLive(sender, tag, group);
        if (!live) return S_OK;
        if (code != 1) g_shellShowedToast = true;
        std::string tagUtf8 = narrow(tag.c_str(), (UINT32)tag.size());
        if (g_dismissed) g_dismissed(g_context, tagUtf8.c_str(), code, 0);
        return S_OK;
    }
};

class FailedSink : public Handler<FailedHandler> {
public:
    HRESULT STDMETHODCALLTYPE Invoke(IToastNotification *sender, IToastFailedEventArgs *args) override {
        std::wstring group;
        std::wstring tag = tagOf(sender, &group);
        HRESULT error = E_FAIL;
        if (args) args->get_ErrorCode(&error);
        bool live = false;
        forget(sender, tag, group, &live);
        if (!live) return S_OK;
        std::string tagUtf8 = narrow(tag.c_str(), (UINT32)tag.size());
        fprintf(stderr, "UserNotifications: toast %s failed (HRESULT 0x%08lx)\n", tagUtf8.c_str(), (unsigned long)error);
        if (g_dismissed) g_dismissed(g_context, tagUtf8.c_str(), -1, (int32_t)error);
        return S_OK;
    }
};

static void setString(HKEY key, const wchar_t *name, const std::wstring &value) {
    RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE *>(value.c_str()), (DWORD)((value.size() + 1) * sizeof(wchar_t)));
}

static std::wstring clsidString(const CLSID &clsid) {
    wchar_t buffer[64] = {0};
    StringFromGUID2(clsid, buffer, ARRAYSIZE(buffer));
    return buffer;
}

/// Registers the AppUserModelID (display name, icon, and the activator's CLSID as
/// CustomActivator) and returns that CLSID: the one already registered for the ID, else a new
/// one. False when the key cannot be written.
static bool registerAumid(const std::wstring &aumid, const std::wstring &name, const std::wstring &icon, CLSID *activator) {
    std::wstring path = L"Software\\Classes\\AppUserModelId\\" + aumid;
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0, KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
    setString(key, L"DisplayName", name);
    if (!icon.empty()) setString(key, L"IconUri", icon);
    wchar_t existing[64] = {0};
    DWORD bytes = sizeof(existing) - sizeof(wchar_t);
    DWORD type = 0;
    bool have = RegQueryValueExW(key, L"CustomActivator", nullptr, &type, reinterpret_cast<BYTE *>(existing), &bytes) == ERROR_SUCCESS
        && type == REG_SZ && SUCCEEDED(CLSIDFromString(existing, activator));
    if (!have && SUCCEEDED(CoCreateGuid(activator))) {
        setString(key, L"CustomActivator", clsidString(*activator));
        have = true;
    }
    RegCloseKey(key);
    return have;
}

/// HKCU\Software\Classes\CLSID\{activator}\LocalServer32 = this executable, so COM can reach
/// (or start) the app for a click in the notification center.
static void registerActivatorServer(const CLSID &activator, const std::wstring &name) {
    wchar_t exe[4 * MAX_PATH] = {0};
    DWORD length = GetModuleFileNameW(nullptr, exe, ARRAYSIZE(exe));
    if (length == 0 || length >= ARRAYSIZE(exe)) return;
    std::wstring path = L"Software\\Classes\\CLSID\\" + clsidString(activator);
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        setString(key, nullptr, name + L" notification activator");
        RegCloseKey(key);
    }
    path += L"\\LocalServer32";
    if (RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
        setString(key, nullptr, L"\"" + std::wstring(exe) + L"\"");
        RegCloseKey(key);
    }
}

/// PKEY_AppUserModel_ID, spelled out so the shim needs no propsys import library.
static const PROPERTYKEY kAppUserModelID = {{0x9F4C2855, 0x9F79, 0x4B39, {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}, 5};
/// PKEY_AppUserModel_ToastActivatorCLSID.
static const PROPERTYKEY kToastActivatorCLSID = {{0x9F4C2855, 0x9F79, 0x4B39, {0xA8, 0xD0, 0xE1, 0xD4, 0x2D, 0xE1, 0xD5, 0xF3}}, 26};

static std::wstring fileSafe(const std::wstring &s) {
    std::wstring out;
    for (wchar_t c : s) out.push_back(wcschr(L"\\/:*?\"<>|", c) || c < 32 ? L'_' : c);
    return out;
}

/// Reads the target, AppUserModelID and toast activator of the shortcut at `path`; false when
/// there is none.
static bool readShortcut(const std::wstring &path, std::wstring *target, std::wstring *aumid, CLSID *activator) {
    if (GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES) return false;
    IShellLinkW *link = nullptr;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void **>(&link)))) return false;
    bool ok = false;
    IPersistFile *file = nullptr;
    IPropertyStore *store = nullptr;
    if (SUCCEEDED(link->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&file))) && SUCCEEDED(file->Load(path.c_str(), STGM_READ))) {
        ok = true;
        wchar_t buffer[4 * MAX_PATH] = {0};
        if (SUCCEEDED(link->GetPath(buffer, ARRAYSIZE(buffer), nullptr, SLGP_RAWPATH))) *target = buffer;
        if (SUCCEEDED(link->QueryInterface(__uuidof(IPropertyStore), reinterpret_cast<void **>(&store)))) {
            PROPVARIANT value;
            PropVariantInit(&value);
            if (SUCCEEDED(store->GetValue(kAppUserModelID, &value)) && value.vt == VT_LPWSTR && value.pwszVal) *aumid = value.pwszVal;
            PropVariantClear(&value);
            PropVariantInit(&value);
            if (SUCCEEDED(store->GetValue(kToastActivatorCLSID, &value)) && value.vt == VT_CLSID && value.puuid) *activator = *value.puuid;
            PropVariantClear(&value);
        }
    }
    release(store);
    release(file);
    release(link);
    return ok;
}

/// Makes sure a shortcut in the user's Start-menu Programs folder starts this executable with
/// the toast AppUserModelID. Its name is the display name; a different program's shortcut of
/// that name is left alone and the ID names ours instead. An existing shortcut to this
/// executable gets the ID and the activator added. Returns S_OK when it was already right,
/// S_FALSE when it was made or repaired, or a failure.
static HRESULT ensureStartShortcut(const std::wstring &aumid, const std::wstring &name, const CLSID &activator) {
    PWSTR folder = nullptr;
    if (FAILED(SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE, nullptr, &folder))) return E_FAIL;
    std::wstring directory = folder;
    CoTaskMemFree(folder);
    wchar_t exe[4 * MAX_PATH] = {0};
    DWORD length = GetModuleFileNameW(nullptr, exe, ARRAYSIZE(exe));
    if (length == 0 || length >= ARRAYSIZE(exe)) return E_FAIL;

    std::wstring path = directory + L"\\" + fileSafe(name.empty() ? aumid : name) + L".lnk";
    std::wstring target, existingId;
    CLSID existingActivator = {};
    auto right = [&] { return existingId == aumid && _wcsicmp(target.c_str(), exe) == 0 && IsEqualGUID(existingActivator, activator); };
    if (readShortcut(path, &target, &existingId, &existingActivator)) {
        if (right()) return S_OK;
        if (existingId != aumid && _wcsicmp(target.c_str(), exe) != 0) {
            path = directory + L"\\" + fileSafe(aumid) + L".lnk";
            target.clear();
            existingId.clear();
            existingActivator = CLSID{};
            if (readShortcut(path, &target, &existingId, &existingActivator) && right()) return S_OK;
        }
    }

    std::wstring exeDirectory(exe);
    exeDirectory = exeDirectory.substr(0, exeDirectory.find_last_of(L"\\/"));
    IShellLinkW *link = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void **>(&link));
    if (FAILED(hr)) return hr;
    IPropertyStore *store = nullptr;
    IPersistFile *file = nullptr;
    do {
        link->SetPath(exe);
        link->SetWorkingDirectory(exeDirectory.c_str());
        if (FAILED(hr = link->QueryInterface(__uuidof(IPropertyStore), reinterpret_cast<void **>(&store)))) break;
        PROPVARIANT value;
        PropVariantInit(&value);
        size_t bytes = (aumid.size() + 1) * sizeof(wchar_t);
        value.pwszVal = static_cast<LPWSTR>(CoTaskMemAlloc(bytes));
        if (!value.pwszVal) { hr = E_OUTOFMEMORY; break; }
        memcpy(value.pwszVal, aumid.c_str(), bytes);
        value.vt = VT_LPWSTR;
        hr = store->SetValue(kAppUserModelID, value);
        PropVariantClear(&value);
        if (FAILED(hr)) break;
        PropVariantInit(&value);
        value.puuid = static_cast<CLSID *>(CoTaskMemAlloc(sizeof(CLSID)));
        if (!value.puuid) { hr = E_OUTOFMEMORY; break; }
        *value.puuid = activator;
        value.vt = VT_CLSID;
        hr = store->SetValue(kToastActivatorCLSID, value);
        PropVariantClear(&value);
        if (FAILED(hr) || FAILED(hr = store->Commit())) break;
        if (FAILED(hr = link->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&file)))) break;
        if (FAILED(hr = file->Save(path.c_str(), TRUE))) break;
        hr = S_FALSE;
    } while (false);
    release(file);
    release(store);
    release(link);
    return hr;
}

/// Windows writes HKCU\...\Notifications\Settings\<aumid> when it first displays one of the
/// app's toasts: the sign that the shell knows the app.
static bool shellKnowsApp() {
    std::wstring path = L"Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings\\" + g_aumid;
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, KEY_READ, &key) != ERROR_SUCCESS) return false;
    RegCloseKey(key);
    return true;
}

static int32_t toastInit(const char *aumid, const char *display_name, const char *icon_path,
                         cwas_toast_activated_fn activated, cwas_toast_dismissed_fn dismissed, void *context) {
    std::lock_guard<std::mutex> guard(g_lock);
    if (g_notifier) return S_OK;
    ensureMTA();
    g_aumid = widen(aumid);
    g_activated = activated;
    g_dismissed = dismissed;
    g_context = context;
    std::wstring name = widen(display_name);
    bool haveActivator = registerAumid(g_aumid, name, widen(icon_path), &g_activatorClsid);
    if (haveActivator) {
        registerActivatorServer(g_activatorClsid, name.empty() ? g_aumid : name);
        HRESULT registered = CoRegisterClassObject(g_activatorClsid, &g_activatorFactory, CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &g_activatorCookie);
        std::string clsid = narrow(clsidString(g_activatorClsid).c_str(), 38);
        fprintf(stderr, "UserNotifications: notification activator %s for %s, HRESULT 0x%08lx\n", clsid.c_str(), aumid, (unsigned long)registered);
    } else {
        fprintf(stderr, "UserNotifications: no notification activator for %s; clicks in the notification center will not reach the app\n", aumid);
    }
    HRESULT shortcut = ensureStartShortcut(g_aumid, name, g_activatorClsid);
    if (shortcut == S_FALSE) {
        g_shortcutMadeAt = GetTickCount64();
        fprintf(stderr, "UserNotifications: made the Start-menu shortcut for %s; Windows shows its toasts once the shell has picked it up\n", aumid);
    } else if (FAILED(shortcut)) {
        fprintf(stderr, "UserNotifications: no Start-menu shortcut for %s (HRESULT 0x%08lx); Windows may not display its toasts\n", aumid, (unsigned long)shortcut);
    }
    PWSTR existing = nullptr;
    if (SUCCEEDED(GetCurrentProcessExplicitAppUserModelID(&existing))) {
        CoTaskMemFree(existing);
    } else {
        SetCurrentProcessExplicitAppUserModelID(g_aumid.c_str());
    }

    IToastNotificationManagerStatics *statics = nullptr;
    HStr managerClass(RuntimeClass_Windows_UI_Notifications_ToastNotificationManager);
    HRESULT hr = RoGetActivationFactory(managerClass.h, __uuidof(IToastNotificationManagerStatics), reinterpret_cast<void **>(&statics));
    if (FAILED(hr)) return hr;
    HStr id(g_aumid);
    hr = statics->CreateToastNotifierWithId(id.h, &g_notifier);
    IToastNotificationManagerStatics2 *statics2 = nullptr;
    if (SUCCEEDED(statics->QueryInterface(__uuidof(IToastNotificationManagerStatics2), reinterpret_cast<void **>(&statics2)))) {
        statics2->get_History(&g_history);
        statics2->Release();
    }
    statics->Release();
    return hr;
}

static int toastSetting(void) {
    IToastNotifier *notifier = nullptr;
    {
        std::lock_guard<std::mutex> guard(g_lock);
        notifier = g_notifier;
        if (notifier) notifier->AddRef();
    }
    if (!notifier) return -1;
    NotificationSetting setting = NotificationSetting_Enabled;
    HRESULT hr = notifier->get_Setting(&setting);
    notifier->Release();
    // An AppUserModelID that has never shown a toast has no notification settings entry yet,
    // and get_Setting fails with ERROR_NOT_FOUND. Windows creates the entry, enabled, on the
    // first toast, so that is "enabled". Only the Disabled… values mean the user, policy or the
    // manifest turned the app off.
    if (hr == HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) return (int)NotificationSetting_Enabled;
    return SUCCEEDED(hr) ? (int)setting : -1;
}

static int32_t toastShow(const char *xml, const char *tag, const char *group, int suppress_popup, const char *input_ids, uint64_t *serial = nullptr) {
    IToastNotifier *notifier = nullptr;
    {
        std::lock_guard<std::mutex> guard(g_lock);
        notifier = g_notifier;
        if (notifier) notifier->AddRef();
    }
    if (!notifier) return E_UNEXPECTED;

    HRESULT hr = S_OK;
    IInspectable *inspectable = nullptr;
    IXmlDocument *document = nullptr;
    IXmlDocumentIO *io = nullptr;
    IToastNotificationFactory *factory = nullptr;
    IToastNotification *toast = nullptr;
    IToastNotification2 *toast2 = nullptr;
    std::wstring wtag = widen(tag), wgroup = widen(group);
    std::vector<std::wstring> ids;
    for (const char *p = input_ids; p && *p; p += strlen(p) + 1) ids.push_back(widen(p));

    do {
        HStr documentClass(RuntimeClass_Windows_Data_Xml_Dom_XmlDocument);
        if (FAILED(hr = RoActivateInstance(documentClass.h, &inspectable))) break;
        if (FAILED(hr = inspectable->QueryInterface(__uuidof(IXmlDocument), reinterpret_cast<void **>(&document)))) break;
        if (FAILED(hr = document->QueryInterface(__uuidof(IXmlDocumentIO), reinterpret_cast<void **>(&io)))) break;
        HStr text(widen(xml));
        if (FAILED(hr = io->LoadXml(text.h))) break;
        HStr toastClass(RuntimeClass_Windows_UI_Notifications_ToastNotification);
        if (FAILED(hr = RoGetActivationFactory(toastClass.h, __uuidof(IToastNotificationFactory), reinterpret_cast<void **>(&factory)))) break;
        if (FAILED(hr = factory->CreateToastNotification(document, &toast))) break;
        if (FAILED(hr = toast->QueryInterface(__uuidof(IToastNotification2), reinterpret_cast<void **>(&toast2)))) break;
        HStr htag(wtag), hgroup(wgroup);
        toast2->put_Tag(htag.h);
        toast2->put_Group(hgroup.h);
        toast2->put_SuppressPopup(suppress_popup ? true : false);

        EventRegistrationToken token;
        ActivatedSink *onActivated = new ActivatedSink();
        hr = toast->add_Activated(onActivated, &token);
        onActivated->Release();
        if (FAILED(hr)) break;
        DismissedSink *onDismissed = new DismissedSink();
        hr = toast->add_Dismissed(onDismissed, &token);
        onDismissed->Release();
        if (FAILED(hr)) break;
        FailedSink *onFailed = new FailedSink();
        hr = toast->add_Failed(onFailed, &token);
        onFailed->Release();
        if (FAILED(hr)) break;

        // Remember it before showing: Activated can arrive before Show returns.
        IToastNotification *replaced = nullptr;
        {
            std::lock_guard<std::mutex> guard(g_lock);
            LiveToast &live = g_live[liveKey(wtag, wgroup)];
            replaced = live.toast;
            toast->AddRef();
            live.toast = toast;
            live.group = wgroup;
            live.inputIds = ids;
            live.serial = ++g_nextSerial;
            if (serial) *serial = live.serial;
        }
        release(replaced);
        hr = notifier->Show(toast);
        if (FAILED(hr)) forget(toast, wtag, wgroup);
    } while (false);

    release(toast2);
    release(toast);
    release(factory);
    release(io);
    release(document);
    release(inspectable);
    notifier->Release();
    return hr;
}

static void toastRemove(const char *tag, const char *group) {
    std::wstring wtag = widen(tag), wgroup = widen(group);
    IToastNotificationHistory *history = nullptr;
    {
        std::lock_guard<std::mutex> guard(g_lock);
        history = g_history;
        if (history) history->AddRef();
    }
    if (history) {
        HStr htag(wtag), hgroup(wgroup), id(g_aumid);
        history->RemoveGroupedTagWithId(htag.h, hgroup.h, id.h);
        history->Release();
    }
    forget(nullptr, wtag, wgroup);
}

static void toastClear(void) {
    IToastNotificationHistory *history = nullptr;
    std::map<std::wstring, LiveToast> live;
    {
        std::lock_guard<std::mutex> guard(g_lock);
        history = g_history;
        if (history) history->AddRef();
        live.swap(g_live);
    }
    if (history) {
        HStr id(g_aumid);
        history->ClearWithId(id.h);
        history->Release();
    }
    for (auto &entry : live) release(entry.second.toast);
}

/// The shell needs some seconds to pick up a Start-menu shortcut this process just made, and
/// drops the toasts shown before then. Until it has displayed one of the app's toasts (or for
/// 30 seconds after the shortcut was made), shows the toast again every 3 seconds, as long as it
/// is still the toast under its tag (not replaced, removed or clicked).
static void retryUntilDisplayed(std::string xml, std::string tag, std::string group, int suppress, std::string packedIds, uint64_t serial) {
    std::thread([=]() mutable {
        fprintf(stderr, "UserNotifications: the shell has not shown %s's toasts yet; showing toast %s again until it does\n",
                narrow(g_aumid.c_str(), (UINT32)g_aumid.size()).c_str(), tag.c_str());
        for (;;) {
            Sleep(3000);
            bool more = false;
            onToastThread([&] {
                if (g_shellShowedToast || shellKnowsApp() || GetTickCount64() - g_shortcutMadeAt > 30000) return;
                {
                    std::lock_guard<std::mutex> guard(g_lock);
                    auto it = g_live.find(liveKey(widen(tag.c_str()), widen(group.c_str())));
                    if (it == g_live.end() || it->second.serial != serial) return;
                }
                uint64_t next = 0;
                if (FAILED(toastShow(xml.c_str(), tag.c_str(), group.c_str(), suppress, packedIds.empty() ? nullptr : packedIds.c_str(), &next))) return;
                serial = next;
                more = true;
            });
            if (!more) break;
        }
    }).detach();
}

// The entry points: each runs its work on the toast thread (see the top of the file).

extern "C" int32_t cwas_toast_init(const char *aumid, const char *display_name, const char *icon_path,
                                   cwas_toast_activated_fn activated, cwas_toast_dismissed_fn dismissed, void *context) {
    DWORD caller = GetCurrentThreadId();
    int32_t hr = E_UNEXPECTED;
    onToastThread([&] {
        bool created = false;
        {
            std::lock_guard<std::mutex> guard(g_lock);
            created = g_notifier != nullptr;
        }
        hr = toastInit(aumid, display_name, icon_path, activated, dismissed, context);
        if (!created) traceThread("toast notifier for", aumid, caller, hr);
    });
    return hr;
}

extern "C" int cwas_toast_setting(void) {
    int setting = -1;
    onToastThread([&] { setting = toastSetting(); });
    return setting;
}

extern "C" int32_t cwas_toast_show(const char *xml, const char *tag, const char *group, int suppress_popup, const char *input_ids) {
    DWORD caller = GetCurrentThreadId();
    int32_t hr = E_UNEXPECTED;
    onToastThread([&] {
        uint64_t serial = 0;
        hr = toastShow(xml, tag, group, suppress_popup, input_ids, &serial);
        if (FAILED(hr) || GetEnvironmentVariableA("APPKITWIN_TRACE_TOASTS", nullptr, 0) > 0) traceThread("show toast", tag, caller, hr);
        if (SUCCEEDED(hr) && g_shortcutMadeAt != 0 && GetTickCount64() - g_shortcutMadeAt < 30000 && !g_shellShowedToast && !shellKnowsApp()) {
            std::string packed;
            for (const char *p = input_ids; p && *p; p += strlen(p) + 1) { packed.append(p); packed.push_back('\0'); }
            retryUntilDisplayed(xml, tag, group, suppress_popup, packed, serial);
        }
    });
    return hr;
}

extern "C" void cwas_toast_remove(const char *tag, const char *group) {
    onToastThread([&] { toastRemove(tag, group); });
}

extern "C" void cwas_toast_clear(void) {
    onToastThread([&] { toastClear(); });
}

#endif
