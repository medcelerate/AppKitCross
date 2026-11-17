// The per-user login item (ADR-0043): the Run key value, the Startup-folder shortcut and the
// user's on/off switch Task Manager keeps for both. See cwas.h.
#if defined(_WIN32)
#include "cwas.h"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shellapi.h>
#include <string>

static const wchar_t *kRunKey = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const wchar_t *kApprovedRun = L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run";
static const wchar_t *kApprovedFolder = L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\StartupFolder";

static std::wstring widen(const char *s) {
    if (!s) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
    return w;
}

static void ensureMTA() {
    static CO_MTA_USAGE_COOKIE cookie = nullptr;
    if (!cookie) CoIncrementMTAUsage(&cookie);
}

extern "C" int cwas_run_get(const char *name, char *buffer, int32_t capacity) {
    std::wstring value = widen(name);
    DWORD size = 0;
    if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, value.c_str(), RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND, nullptr, nullptr, &size) != ERROR_SUCCESS) return 0;
    std::wstring data(size / sizeof(wchar_t) + 1, L'\0');
    if (RegGetValueW(HKEY_CURRENT_USER, kRunKey, value.c_str(), RRF_RT_REG_SZ | RRF_RT_REG_EXPAND_SZ | RRF_NOEXPAND, nullptr, &data[0], &size) != ERROR_SUCCESS) return 0;
    data.resize(wcslen(data.c_str()));
    if (buffer && capacity > 0) {
        int n = WideCharToMultiByte(CP_UTF8, 0, data.c_str(), -1, buffer, capacity, nullptr, nullptr);
        if (n == 0) buffer[0] = 0;
        buffer[capacity - 1] = 0;
    }
    return 1;
}

extern "C" int cwas_run_set(const char *name, const char *command) {
    std::wstring value = widen(name), data = widen(command);
    LSTATUS s = RegSetKeyValueW(HKEY_CURRENT_USER, kRunKey, value.c_str(), REG_SZ, data.c_str(), (DWORD)((data.size() + 1) * sizeof(wchar_t)));
    return s == ERROR_SUCCESS ? 0 : (int)s;
}

extern "C" int cwas_run_delete(const char *name) {
    std::wstring value = widen(name);
    LSTATUS s = RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, value.c_str());
    return s == ERROR_SUCCESS || s == ERROR_FILE_NOT_FOUND ? 0 : (int)s;
}

extern "C" int cwas_startup_approved(int startup_folder, const char *name) {
    std::wstring value = widen(name);
    BYTE data[16] = {0};
    DWORD size = sizeof(data);
    if (RegGetValueW(HKEY_CURRENT_USER, startup_folder ? kApprovedFolder : kApprovedRun, value.c_str(), RRF_RT_REG_BINARY, nullptr, data, &size) != ERROR_SUCCESS || size == 0) return -1;
    // 02/06: enabled; 03/07: disabled by the user (the low bit), followed by a FILETIME.
    return (data[0] & 1) ? 0 : 1;
}

static std::wstring shortcutPath(const char *name) {
    PWSTR folder = nullptr;
    std::wstring path;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Startup, KF_FLAG_CREATE, nullptr, &folder))) {
        path = folder;
        path += L"\\";
        path += widen(name);
        path += L".lnk";
    }
    if (folder) CoTaskMemFree(folder);
    return path;
}

extern "C" int cwas_shortcut_exists(const char *name) {
    std::wstring path = shortcutPath(name);
    return !path.empty() && GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES ? 1 : 0;
}

extern "C" int32_t cwas_shortcut_create(const char *name, const char *target, const char *description) {
    ensureMTA();
    std::wstring path = shortcutPath(name);
    if (path.empty()) return E_FAIL;
    std::wstring wtarget = widen(target), wdescription = widen(description);
    std::wstring directory = wtarget.substr(0, wtarget.find_last_of(L"\\/"));
    IShellLinkW *link = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW, reinterpret_cast<void **>(&link));
    if (FAILED(hr)) return hr;
    link->SetPath(wtarget.c_str());
    link->SetWorkingDirectory(directory.c_str());
    link->SetDescription(wdescription.c_str());
    IPersistFile *file = nullptr;
    hr = link->QueryInterface(IID_IPersistFile, reinterpret_cast<void **>(&file));
    if (SUCCEEDED(hr)) {
        hr = file->Save(path.c_str(), TRUE);
        file->Release();
    }
    link->Release();
    return hr;
}

extern "C" int cwas_shortcut_delete(const char *name) {
    std::wstring path = shortcutPath(name);
    if (path.empty()) return 0;
    if (DeleteFileW(path.c_str())) return 0;
    DWORD e = GetLastError();
    return e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND ? 0 : (int)e;
}

extern "C" int cwas_open_uri(const char *uri) {
    std::wstring w = widen(uri);
    HINSTANCE r = ShellExecuteW(nullptr, L"open", w.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    return (INT_PTR)r > 32 ? 1 : 0;
}

#endif
