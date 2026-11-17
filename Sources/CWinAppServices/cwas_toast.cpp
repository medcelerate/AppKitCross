// Toast notifications for an unpackaged desktop app (ADR-0043). See cwas.h.
//
// An unpackaged app gets toasts by registering an AppUserModelID under
// HKCU\Software\Classes\AppUserModelId (display name, icon) and creating the notifier with
// that ID. Activation without a COM activator reaches the app only through the toast
// object's Activated event, so the shim keeps every shown toast (and its handlers) alive until
// it is activated, dismissed by the user, or removed: a toast clicked in Action Center while
// the app runs still reports back; one clicked after the app quit starts nothing.
//
// Plain COM over the WinRT ABI headers (no WRL, no C++/WinRT): the three event handlers are
// small hand-written agile objects.
#if defined(_WIN32)
#include "cwas.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <roapi.h>
#include <winstring.h>
#include <shobjidl.h>
#include <windows.foundation.h>
#include <windows.foundation.collections.h>
#include <windows.data.xml.dom.h>
#include <windows.ui.notifications.h>
#include <cstdio>
#include <cstring>
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
    std::wstring group;
    std::vector<std::wstring> inputIds;
};

static std::mutex g_lock;
static CO_MTA_USAGE_COOKIE g_mtaCookie = nullptr;
static IToastNotifier *g_notifier = nullptr;
static IToastNotificationHistory *g_history = nullptr;
static std::wstring g_aumid;
static cwas_toast_activated_fn g_activated = nullptr;
static cwas_toast_dismissed_fn g_dismissed = nullptr;
static void *g_context = nullptr;
static std::map<std::wstring, LiveToast> g_live;   // keyed by group + "\n" + tag

static std::wstring liveKey(const std::wstring &tag, const std::wstring &group) { return group + L"\n" + tag; }

static void ensureMTA() {
    if (!g_mtaCookie) CoIncrementMTAUsage(&g_mtaCookie);
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
static std::vector<std::wstring> forget(IToastNotification *toast, const std::wstring &tag, const std::wstring &group) {
    std::vector<std::wstring> ids;
    IToastNotification *drop = nullptr;
    {
        std::lock_guard<std::mutex> guard(g_lock);
        auto it = g_live.find(liveKey(tag, group));
        if (it != g_live.end() && (toast == nullptr || it->second.toast == toast)) {
            ids = it->second.inputIds;
            drop = it->second.toast;
            g_live.erase(it);
        }
    }
    release(drop);
    return ids;
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

class ActivatedSink : public Handler<ActivatedHandler> {
public:
    HRESULT STDMETHODCALLTYPE Invoke(IToastNotification *sender, IInspectable *args) override {
        std::wstring group;
        std::wstring tag = tagOf(sender, &group);
        std::string arguments;
        std::string inputs;
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
                                std::string idUtf8 = narrow(id.c_str(), (UINT32)id.size());
                                inputs.append(idUtf8);
                                inputs.push_back('\0');
                                inputs.append(text ? narrow(text) : std::string());
                                inputs.push_back('\0');
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
        inputs.push_back('\0');
        forget(sender, tag, group);
        std::string tagUtf8 = narrow(tag.c_str(), (UINT32)tag.size());
        if (g_activated) g_activated(g_context, tagUtf8.c_str(), arguments.c_str(), ids.empty() ? nullptr : inputs.data());
        return S_OK;
    }
};

class DismissedSink : public Handler<DismissedHandler> {
public:
    HRESULT STDMETHODCALLTYPE Invoke(IToastNotification *sender, IToastDismissedEventArgs *args) override {
        std::wstring group;
        std::wstring tag = tagOf(sender, &group);
        ToastDismissalReason reason = ToastDismissalReason_UserCanceled;
        if (args) args->get_Reason(&reason);
        int code = reason == ToastDismissalReason_UserCanceled ? 0 : reason == ToastDismissalReason_ApplicationHidden ? 1 : 2;
        // A timed-out toast moved to Action Center and can still be clicked: keep its handlers.
        if (code != 2) forget(sender, tag, group);
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
        forget(sender, tag, group);
        std::string tagUtf8 = narrow(tag.c_str(), (UINT32)tag.size());
        fprintf(stderr, "UserNotifications: toast %s failed (HRESULT 0x%08lx)\n", tagUtf8.c_str(), (unsigned long)error);
        if (g_dismissed) g_dismissed(g_context, tagUtf8.c_str(), -1, (int32_t)error);
        return S_OK;
    }
};

static void registerAumid(const std::wstring &aumid, const std::wstring &name, const std::wstring &icon) {
    std::wstring path = L"Software\\Classes\\AppUserModelId\\" + aumid;
    HKEY key = nullptr;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, path.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) return;
    RegSetValueExW(key, L"DisplayName", 0, REG_SZ, reinterpret_cast<const BYTE *>(name.c_str()), (DWORD)((name.size() + 1) * sizeof(wchar_t)));
    if (!icon.empty()) {
        RegSetValueExW(key, L"IconUri", 0, REG_SZ, reinterpret_cast<const BYTE *>(icon.c_str()), (DWORD)((icon.size() + 1) * sizeof(wchar_t)));
    }
    RegCloseKey(key);
}

extern "C" int32_t cwas_toast_init(const char *aumid, const char *display_name, const char *icon_path,
                                   cwas_toast_activated_fn activated, cwas_toast_dismissed_fn dismissed, void *context) {
    std::lock_guard<std::mutex> guard(g_lock);
    if (g_notifier) return S_OK;
    ensureMTA();
    g_aumid = widen(aumid);
    g_activated = activated;
    g_dismissed = dismissed;
    g_context = context;
    registerAumid(g_aumid, widen(display_name), widen(icon_path));
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

extern "C" int cwas_toast_setting(void) {
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
    return SUCCEEDED(hr) ? (int)setting : -1;
}

extern "C" int32_t cwas_toast_show(const char *xml, const char *tag, const char *group, int suppress_popup, const char *input_ids) {
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

extern "C" void cwas_toast_remove(const char *tag, const char *group) {
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

extern "C" void cwas_toast_clear(void) {
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

#endif
