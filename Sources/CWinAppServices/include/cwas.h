// C seam over the Windows app services behind UserNotifications and ServiceManagement
// (ADR-0043): WinRT toast notifications for an unpackaged app (cwas_toast.cpp) and the
// per-user login item, the Run key and the Startup folder (cwas_startup.cpp).
// Strings are UTF-8. Everything is safe to call from any thread: the shim keeps the process's
// multithreaded apartment alive (CoIncrementMTAUsage) and never initializes COM on the
// caller's thread, so it cannot change the apartment of the Win32 backend's UI thread.
#ifndef CWAS_H
#define CWAS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: Toasts

/// A click on a toast or one of its buttons, from a banner or the notification center, reported
/// once. The toast's launch string and each button's arguments are "{tag} {action}", both
/// percent-encoded; `arguments` is the decoded action. `user_inputs` lists the toast's text boxes as NUL-separated id/value
/// pairs ending with an empty string, or is NULL. Called on a thread-pool thread.
typedef void (*cwas_toast_activated_fn)(void *context, const char *tag, const char *arguments, const char *user_inputs);
/// A toast left the screen: reason 0 the user closed it, 1 the app removed it, 2 it timed
/// out (Action Center keeps it), -1 it could not be shown (`error` is the HRESULT).
typedef void (*cwas_toast_dismissed_fn)(void *context, const char *tag, int reason, int32_t error);

/// Registers the AppUserModelID for toasts (HKCU\Software\Classes\AppUserModelId\<aumid>
/// with its display name and, when given, an icon file), makes sure a Start-menu shortcut to
/// this executable carries that ID (Windows displays no toast of an unpackaged app without
/// one), registers a COM toast activator for it (HKCU\Software\Classes\CLSID\{clsid} with
/// LocalServer32, the CLSID kept as the ID's CustomActivator and set on the shortcut; clicks in
/// the notification center arrive only there), makes it the process's ID unless the process
/// already has one, and creates the toast notifier. Returns an HRESULT.
int32_t cwas_toast_init(const char *aumid, const char *display_name, const char *icon_path,
                        cwas_toast_activated_fn activated, cwas_toast_dismissed_fn dismissed, void *context);
/// The notifier's NotificationSetting: 0 enabled, 1 disabled for the app, 2 disabled for
/// the user, 3 disabled by group policy, 4 disabled by manifest; -1 before a successful init.
int cwas_toast_setting(void);
/// Shows a toast from its XML, replacing any toast with the same tag and group.
/// `input_ids` lists the ids of the toast's text boxes (NUL-separated, ending with an empty
/// string) or is NULL. `suppress_popup` sends it straight to Action Center. Returns an HRESULT.
int32_t cwas_toast_show(const char *xml, const char *tag, const char *group, int suppress_popup, const char *input_ids);
/// Removes a toast from the screen and from Action Center.
void cwas_toast_remove(const char *tag, const char *group);
/// Removes all of the app's toasts.
void cwas_toast_clear(void);

// MARK: Login item

/// Reads the value `name` of HKCU\Software\Microsoft\Windows\CurrentVersion\Run into
/// `buffer`: 1 when it exists, 0 when it does not.
int cwas_run_get(const char *name, char *buffer, int32_t capacity);
/// Writes the Run value: 0 on success, else a Win32 error code.
int cwas_run_set(const char *name, const char *command);
/// Deletes the Run value: 0 when it is gone (or never was), else a Win32 error code.
int cwas_run_delete(const char *name);
/// The user's switch for a startup entry (HKCU\…\Explorer\StartupApproved\Run, or
/// \StartupFolder when `startup_folder` is 1): 1 on, 0 off, -1 no record (on).
int cwas_startup_approved(int startup_folder, const char *name);
/// 1 when <Startup folder>\<name>.lnk exists.
int cwas_shortcut_exists(const char *name);
/// Creates <Startup folder>\<name>.lnk pointing at `target`. Returns an HRESULT.
int32_t cwas_shortcut_create(const char *name, const char *target, const char *description);
/// Deletes the shortcut: 0 when it is gone (or never was), else a Win32 error code.
int cwas_shortcut_delete(const char *name);

/// Opens a URI with the shell (ms-settings:startupapps and the like): 1 on success.
int cwas_open_uri(const char *uri);

#ifdef __cplusplus
}
#endif
#endif
