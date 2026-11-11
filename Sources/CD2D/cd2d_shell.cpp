// The shell for NSWorkspace (ADR-0022): icons from the system image lists, Explorer,
// the Recycle Bin, file associations, ShellExecute, the taskbar overlay and a few
// process facts. C++ because these are COM interfaces (IImageList, IAssocHandler,
// ITaskbarList3, IShellItem); the Swift side (Win32Workspace.swift) owns the policy.

#include "cd2d.h"
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <commoncontrols.h>
#include <wtsapi32.h>
#include <appmodel.h>
#include <string>
#include <vector>
#include <cstring>
#include <cstdlib>

namespace {

template <typename T> void safeRelease(T *&p) { if (p) { p->Release(); p = nullptr; } }

struct ComInit {
    ComInit() { CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED); }
};
static void ensureCom() { static ComInit once; }

/// An HICON as premultiplied BGRA (top-down). The colour plane is drawn into a 32-bit
/// DIB with DrawIconEx, which composes the alpha (or the mask) for every icon format.
static bool iconPixels(HICON icon, int size, uint8_t **out, uint32_t *w, uint32_t *h) {
    if (!icon || size <= 0) return false;
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = size;
    bi.bmiHeader.biHeight = -size;
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    HDC screen = GetDC(nullptr);
    HDC dc = CreateCompatibleDC(screen);
    void *bits = nullptr;
    HBITMAP bmp = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    bool ok = false;
    if (bmp && bits) {
        HGDIOBJ old = SelectObject(dc, bmp);
        memset(bits, 0, size_t(size) * size_t(size) * 4);
        // DrawIconEx with DI_NORMAL onto a zeroed 32-bit surface leaves the icon's alpha
        // in place for 32-bit icons; masked icons come out opaque where drawn.
        if (DrawIconEx(dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL)) {
            GdiFlush();
            uint8_t *px = static_cast<uint8_t *>(bits);
            size_t n = size_t(size) * size_t(size);
            bool anyAlpha = false;
            for (size_t i = 0; i < n; i++) if (px[i * 4 + 3]) { anyAlpha = true; break; }
            if (!anyAlpha) {
                // No alpha channel: treat every pixel the icon touched as opaque, using
                // the mask to find the untouched ones.
                ICONINFO info = {};
                if (GetIconInfo(icon, &info)) {
                    if (info.hbmMask) {
                        HDC mdc = CreateCompatibleDC(screen);
                        BITMAPINFO mi = bi;
                        void *mbits = nullptr;
                        HBITMAP mbmp = CreateDIBSection(mdc, &mi, DIB_RGB_COLORS, &mbits, nullptr, 0);
                        if (mbmp && mbits) {
                            HGDIOBJ mold = SelectObject(mdc, mbmp);
                            memset(mbits, 0xFF, n * 4);
                            DrawIconEx(mdc, 0, 0, icon, size, size, 0, nullptr, DI_MASK);
                            GdiFlush();
                            uint8_t *m = static_cast<uint8_t *>(mbits);
                            for (size_t i = 0; i < n; i++) px[i * 4 + 3] = m[i * 4] ? 0 : 0xFF;
                            SelectObject(mdc, mold);
                        } else {
                            for (size_t i = 0; i < n; i++) px[i * 4 + 3] = 0xFF;
                        }
                        if (mbmp) DeleteObject(mbmp);
                        DeleteDC(mdc);
                    }
                    if (info.hbmColor) DeleteObject(info.hbmColor);
                    if (info.hbmMask) DeleteObject(info.hbmMask);
                }
            }
            *out = static_cast<uint8_t *>(malloc(n * 4));
            if (*out) {
                memcpy(*out, px, n * 4);
                *w = uint32_t(size);
                *h = uint32_t(size);
                ok = true;
            }
        }
        SelectObject(dc, old);
    }
    if (bmp) DeleteObject(bmp);
    DeleteDC(dc);
    ReleaseDC(nullptr, screen);
    return ok;
}

static std::wstring utf16(const uint16_t *s) { return s ? std::wstring(reinterpret_cast<const wchar_t *>(s)) : std::wstring(); }

/// GUID_CONSOLE_DISPLAY_STATE (6FE69556-704A-47A0-8F24-C28D936FDA47), spelled out so no
/// GUID library is needed at link time.
static const GUID kConsoleDisplayState = {0x6fe69556, 0x704a, 0x47a0, {0x8f, 0x24, 0xc2, 0x8d, 0x93, 0x6f, 0xda, 0x47}};

static bool copyOut(const std::wstring &s, uint16_t *buffer, uint32_t capacity) {
    if (!buffer || capacity == 0 || s.size() + 1 > capacity) return false;
    memcpy(buffer, s.c_str(), (s.size() + 1) * sizeof(wchar_t));
    return true;
}

} // namespace

extern "C" {

bool cd2d_shell_icon(const uint16_t *path, bool useFileAttributes, bool isDirectory, uint32_t sizePx,
                     uint8_t **bgra, uint32_t *width, uint32_t *height) {
    if (!path || !bgra || !width || !height) return false;
    ensureCom();
    SHFILEINFOW info = {};
    UINT flags = SHGFI_SYSICONINDEX;
    DWORD attributes = 0;
    if (useFileAttributes) { flags |= SHGFI_USEFILEATTRIBUTES; attributes = isDirectory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL; }
    if (!SHGetFileInfoW(reinterpret_cast<LPCWSTR>(path), attributes, &info, sizeof(info), flags)) return false;
    int list = SHIL_LARGE, size = 32;
    if (sizePx > 48) { list = SHIL_JUMBO; size = 256; }
    else if (sizePx > 32) { list = SHIL_EXTRALARGE; size = 48; }
    else if (sizePx <= 16) { list = SHIL_SMALL; size = 16; }
    IImageList *images = nullptr;
    if (FAILED(SHGetImageList(list, IID_PPV_ARGS(&images))) || !images) return false;
    HICON icon = nullptr;
    HRESULT hr = images->GetIcon(info.iIcon, ILD_TRANSPARENT, &icon);
    images->Release();
    if (FAILED(hr) || !icon) return false;
    // Jumbo lists pad small icons into 256 px; draw at the requested size instead.
    int drawSize = list == SHIL_JUMBO ? int(sizePx) : size;
    bool ok = iconPixels(icon, drawSize, bgra, width, height);
    DestroyIcon(icon);
    return ok;
}

bool cd2d_shell_reveal(const uint16_t *paths, uint32_t count) {
    if (!paths || count == 0) return false;
    ensureCom();
    std::vector<PIDLIST_ABSOLUTE> items;
    const wchar_t *p = reinterpret_cast<const wchar_t *>(paths);
    for (uint32_t i = 0; i < count; i++) {
        size_t len = wcslen(p);
        if (PIDLIST_ABSOLUTE pidl = ILCreateFromPathW(p)) items.push_back(pidl);
        p += len + 1;
    }
    if (items.empty()) return false;
    bool ok = false;
    // All items share the first one's folder; the folder's own PIDL is the parent.
    PIDLIST_ABSOLUTE folder = ILClone(items[0]);
    if (folder && ILRemoveLastID(folder)) {
        std::vector<PCUITEMID_CHILD> children;
        for (PIDLIST_ABSOLUTE item : items) {
            if (ILIsParent(folder, item, TRUE)) children.push_back(ILFindLastID(item));
        }
        ok = SUCCEEDED(SHOpenFolderAndSelectItems(folder, UINT(children.size()), children.empty() ? nullptr : children.data(), 0));
    }
    if (folder) ILFree(folder);
    for (PIDLIST_ABSOLUTE item : items) ILFree(item);
    return ok;
}

bool cd2d_shell_recycle(const uint16_t *path) {
    if (!path) return false;
    std::wstring doubleNul = utf16(path);
    doubleNul.push_back(L'\0');
    SHFILEOPSTRUCTW op = {};
    op.wFunc = FO_DELETE;
    op.pFrom = doubleNul.c_str();
    op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;
    int r = SHFileOperationW(&op);
    return r == 0 && !op.fAnyOperationsAborted;
}

bool cd2d_shell_default_handler(const uint16_t *assoc, bool isProtocol, uint16_t *buffer, uint32_t capacity) {
    if (!assoc || !buffer) return false;
    ASSOCF flags = ASSOCF_NOTRUNCATE;
    if (isProtocol) flags |= ASSOCF_IS_PROTOCOL;
    DWORD len = capacity;
    HRESULT hr = AssocQueryStringW(flags, ASSOCSTR_EXECUTABLE, reinterpret_cast<LPCWSTR>(assoc), L"open", reinterpret_cast<LPWSTR>(buffer), &len);
    if (FAILED(hr) || len == 0) return false;
    // OpenWith.exe is Windows asking the user: not a handler.
    std::wstring exe = utf16(buffer);
    std::wstring lower = exe;
    for (auto &c : lower) c = towlower(c);
    if (lower.find(L"openwith.exe") != std::wstring::npos) return false;
    return true;
}

uint16_t *cd2d_shell_handlers(const uint16_t *extension, uint32_t *length) {
    if (!extension || !length) return nullptr;
    ensureCom();
    IEnumAssocHandlers *handlers = nullptr;
    if (FAILED(SHAssocEnumHandlers(reinterpret_cast<LPCWSTR>(extension), ASSOC_FILTER_RECOMMENDED, &handlers)) || !handlers) return nullptr;
    std::wstring out;
    IAssocHandler *handler = nullptr;
    ULONG fetched = 0;
    while (handlers->Next(1, &handler, &fetched) == S_OK && handler) {
        LPWSTR name = nullptr;
        if (SUCCEEDED(handler->GetName(&name)) && name) {
            out.append(name);
            out.push_back(L'\0');
            CoTaskMemFree(name);
        }
        handler->Release();
        handler = nullptr;
    }
    handlers->Release();
    if (out.empty()) return nullptr;
    uint16_t *result = static_cast<uint16_t *>(malloc((out.size() + 1) * sizeof(wchar_t)));
    if (!result) return nullptr;
    memcpy(result, out.c_str(), (out.size() + 1) * sizeof(wchar_t));
    *length = uint32_t(out.size());
    return result;
}

bool cd2d_shell_execute(void *ownerHwnd, const uint16_t *file, const uint16_t *parameters, int32_t show, uint32_t *pid) {
    if (!file) return false;
    ensureCom();
    SHELLEXECUTEINFOW info = {};
    info.cbSize = sizeof(info);
    // No SEE_MASK_NOASYNC: with it the shell finishes DDE and the like by pumping messages
    // on this thread, re-entering the window procedure that asked for the open; this
    // thread has a message loop and outlives the call, so the shell may use its own.
    info.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
    info.hwnd = static_cast<HWND>(ownerHwnd);
    info.lpVerb = L"open";
    info.lpFile = reinterpret_cast<LPCWSTR>(file);
    info.lpParameters = (parameters && parameters[0]) ? reinterpret_cast<LPCWSTR>(parameters) : nullptr;
    info.nShow = show;
    if (!ShellExecuteExW(&info)) return false;
    if (pid) *pid = info.hProcess ? GetProcessId(info.hProcess) : 0;
    if (info.hProcess) CloseHandle(info.hProcess);
    return true;
}

bool cd2d_shell_set_overlay_icon(void *hwnd, void *hicon, const uint16_t *description) {
    if (!hwnd) return false;
    ensureCom();
    static ITaskbarList3 *taskbar = nullptr;
    if (!taskbar) {
        if (FAILED(CoCreateInstance(__uuidof(TaskbarList), nullptr, CLSCTX_INPROC_SERVER, __uuidof(ITaskbarList3), reinterpret_cast<void **>(&taskbar))) || !taskbar) return false;
        if (FAILED(taskbar->HrInit())) { safeRelease(taskbar); return false; }
    }
    return SUCCEEDED(taskbar->SetOverlayIcon(static_cast<HWND>(hwnd), static_cast<HICON>(hicon), description ? reinterpret_cast<LPCWSTR>(description) : L""));
}

bool cd2d_shell_app_user_model_id(uint32_t pid, uint16_t *buffer, uint32_t capacity) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return false;
    UINT32 len = capacity;
    LONG r = GetApplicationUserModelId(process, &len, reinterpret_cast<PWSTR>(buffer));
    CloseHandle(process);
    return r == ERROR_SUCCESS && len > 1;
}

bool cd2d_shell_file_description(const uint16_t *exePath, uint16_t *buffer, uint32_t capacity) {
    if (!exePath || !buffer) return false;
    DWORD handle = 0;
    DWORD size = GetFileVersionInfoSizeW(reinterpret_cast<LPCWSTR>(exePath), &handle);
    if (size == 0) return false;
    std::vector<uint8_t> data(size);
    if (!GetFileVersionInfoW(reinterpret_cast<LPCWSTR>(exePath), 0, size, data.data())) return false;
    struct Translation { WORD language, codePage; } *translations = nullptr;
    UINT count = 0;
    std::vector<Translation> candidates;
    if (VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation", reinterpret_cast<LPVOID *>(&translations), &count) && translations) {
        for (UINT i = 0; i < count / sizeof(Translation); i++) candidates.push_back(translations[i]);
    }
    candidates.push_back({0x0409, 0x04B0});
    candidates.push_back({0x0409, 0x04E4});
    for (const Translation &t : candidates) {
        wchar_t key[64];
        swprintf(key, 64, L"\\StringFileInfo\\%04x%04x\\FileDescription", t.language, t.codePage);
        LPWSTR value = nullptr;
        UINT len = 0;
        if (VerQueryValueW(data.data(), key, reinterpret_cast<LPVOID *>(&value), &len) && value && len > 1) {
            std::wstring s(value, len - 1);
            while (!s.empty() && s.back() == L'\0') s.pop_back();
            if (!s.empty()) return copyOut(s, buffer, capacity);
        }
    }
    return false;
}

void cd2d_shell_register_notifications(void *hwnd) {
    if (!hwnd) return;
    WTSRegisterSessionNotification(static_cast<HWND>(hwnd), NOTIFY_FOR_THIS_SESSION);
    RegisterPowerSettingNotification(static_cast<HWND>(hwnd), &kConsoleDisplayState, DEVICE_NOTIFY_WINDOW_HANDLE);
}

bool cd2d_shell_display_state(const void *lParam, uint32_t *state) {
    const POWERBROADCAST_SETTING *setting = static_cast<const POWERBROADCAST_SETTING *>(lParam);
    if (!setting || !state || !IsEqualGUID(setting->PowerSetting, kConsoleDisplayState) || setting->DataLength < sizeof(DWORD)) return false;
    *state = *reinterpret_cast<const DWORD *>(setting->Data);
    return true;
}

int32_t cd2d_shell_process_architecture(uint32_t pid) {
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return 0;
    USHORT processMachine = 0, nativeMachine = 0;
    int32_t result = 0;
    if (IsWow64Process2(process, &processMachine, &nativeMachine)) {
        USHORT machine = processMachine == IMAGE_FILE_MACHINE_UNKNOWN ? nativeMachine : processMachine;
        switch (machine) {
        case IMAGE_FILE_MACHINE_AMD64: result = 0x01000007; break;
        case IMAGE_FILE_MACHINE_ARM64: result = 0x0100000c; break;
        case IMAGE_FILE_MACHINE_I386: result = 0x00000007; break;
        default: break;
        }
    }
    CloseHandle(process);
    return result;
}

void cd2d_shell_free(void *buffer) { free(buffer); }

} // extern "C"
