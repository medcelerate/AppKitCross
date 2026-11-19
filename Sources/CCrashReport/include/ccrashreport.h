// C seam over the process crash handler (ADR-0046): an unhandled-exception filter that
// writes a minidump and a text report on Windows (ccrashreport_win.c), a signal handler
// that writes a backtrace report on Linux (and on the macOS host build, where only the
// tests use it; ccrashreport_posix.c). AppKit installs it at launch through
// Platform/CrashReporting.swift. Strings are UTF-8.
#ifndef CCRASHREPORT_H
#define CCRASHREPORT_H

#ifdef __cplusplus
extern "C" {
#endif

/// Installs the handler. Reports go to `directory` (created if missing) as
/// `<appName>-<timestamp>.txt` (and `.dmp` on Windows); `bundleIdentifier` and `appName`
/// are written into the report header. Returns 1 when the handler is in place, 0 when the
/// directory cannot be created. Calling it again replaces the directory and names.
int ccrash_install(const char *directory, const char *appName, const char *bundleIdentifier);

/// Sets where reports go and the names in their header without installing any handler
/// (ccrash_write_report, tests). Returns 0 when the directory cannot be created.
int ccrash_configure(const char *directory, const char *appName, const char *bundleIdentifier);

/// Whether the handler is installed.
int ccrash_installed(void);

/// The path of the last report this process wrote (empty when none). For tests.
const char *ccrash_last_report(void);

/// Writes a report for the current thread without crashing (the "reason" goes into the
/// header in place of the exception or signal). Returns 1 when a report was written.
int ccrash_write_report(const char *reason);

/// Crashes the process on purpose (APPKITWIN_CRASH_TEST): 0 = write through a null pointer,
/// 1 = a trap instruction (what Swift's fatalError and a failed precondition execute),
/// 2 = abort().
void ccrash_crash_now(int kind);

#ifdef __cplusplus
}
#endif

#endif
