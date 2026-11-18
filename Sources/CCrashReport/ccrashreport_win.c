// The crash handler on Windows: an unhandled-exception filter that writes a minidump
// (MiniDumpWriteDump) and a text report (exception code and address, the module and offset
// it is in, the thread, a stack walk with symbol names where DbgHelp finds them) and then
// lets the exception go on to the previous filter and Windows Error Reporting, so the
// process still ends with the exception's code.
//
// abort() does not raise an exception (the CRT ends the process through __fastfail, which
// skips the filter), so SIGABRT gets a handler too that writes the same report from a
// captured context. Swift's fatalError and failed preconditions execute a trap instruction
// (STATUS_ILLEGAL_INSTRUCTION or STATUS_BREAKPOINT), which the filter sees.
//
// The filter runs in the crashing process: the heap may be damaged, so the report is
// built in static buffers, and the thread keeps 64 KB of stack in reserve
// (SetThreadStackGuarantee) so a stack overflow is reported too.
#if defined(_WIN32)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dbghelp.h>
#include <shlobj.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "ccrashreport.h"

#define CCRASH_PATH_MAX 1024

static wchar_t g_directory[CCRASH_PATH_MAX];
static char g_app[256];
static char g_bundle[256];
static char g_last[CCRASH_PATH_MAX * 3];
static volatile LONG g_installed;
static volatile LONG g_handling;
static LPTOP_LEVEL_EXCEPTION_FILTER g_previousFilter;
static char g_text[64 * 1024];

static void copy(char *dst, size_t size, const char *src) {
    if (!src) src = "";
    size_t n = strlen(src);
    if (n >= size) n = size - 1;
    memcpy(dst, src, n);
    dst[n] = 0;
}

static const char *exception_name(DWORD code) {
    switch (code) {
    case EXCEPTION_ACCESS_VIOLATION: return "EXCEPTION_ACCESS_VIOLATION";
    case EXCEPTION_ILLEGAL_INSTRUCTION: return "EXCEPTION_ILLEGAL_INSTRUCTION (a Swift runtime trap: fatalError, a failed precondition, an unwrapped nil, an overflow)";
    case EXCEPTION_BREAKPOINT: return "EXCEPTION_BREAKPOINT (a trap instruction)";
    case EXCEPTION_STACK_OVERFLOW: return "EXCEPTION_STACK_OVERFLOW";
    case EXCEPTION_INT_DIVIDE_BY_ZERO: return "EXCEPTION_INT_DIVIDE_BY_ZERO";
    case EXCEPTION_INT_OVERFLOW: return "EXCEPTION_INT_OVERFLOW";
    case EXCEPTION_IN_PAGE_ERROR: return "EXCEPTION_IN_PAGE_ERROR";
    case EXCEPTION_DATATYPE_MISALIGNMENT: return "EXCEPTION_DATATYPE_MISALIGNMENT";
    case EXCEPTION_PRIV_INSTRUCTION: return "EXCEPTION_PRIV_INSTRUCTION";
    case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "EXCEPTION_ARRAY_BOUNDS_EXCEEDED";
    case EXCEPTION_FLT_DIVIDE_BY_ZERO: return "EXCEPTION_FLT_DIVIDE_BY_ZERO";
    case EXCEPTION_FLT_INVALID_OPERATION: return "EXCEPTION_FLT_INVALID_OPERATION";
    case 0xC0000409: return "STATUS_STACK_BUFFER_OVERRUN (fail fast)";
    case 0xE06D7363: return "a C++ exception";
    case 0x40000015: return "SIGABRT (abort)";
    default: return "exception";
    }
}

// The module that contains `address`, as a UTF-8 path, and its base.
static void module_for(const void *address, char *name, size_t size, DWORD64 *base) {
    HMODULE module = NULL;
    name[0] = 0;
    *base = 0;
    if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCWSTR)address, &module) && module) {
        wchar_t wide[MAX_PATH];
        DWORD n = GetModuleFileNameW(module, wide, MAX_PATH);
        if (n > 0) WideCharToMultiByte(CP_UTF8, 0, wide, (int)n + 1, name, (int)size, NULL, NULL);
        *base = (DWORD64)(ULONG_PTR)module;
    }
}

static const char *base_name(const char *path) {
    const char *slash = strrchr(path, '\\');
    return slash ? slash + 1 : path;
}

typedef struct { char *p; size_t left; } buf_t;
static void putf(buf_t *b, const char *format, ...) {
    if (b->left <= 1) return;
    va_list args;
    va_start(args, format);
    int n = _vsnprintf_s(b->p, b->left, _TRUNCATE, format, args);
    va_end(args);
    if (n < 0) { size_t used = strlen(b->p); b->p += used; b->left -= used; return; }
    b->p += n; b->left -= (size_t)n;
}

// Walks the stack from `context` (a copy: StackWalk64 changes it).
static void put_backtrace(buf_t *b, HANDLE process, HANDLE thread, const CONTEXT *original) {
    CONTEXT context = *original;
    STACKFRAME64 frame;
    memset(&frame, 0, sizeof frame);
    DWORD machine;
#if defined(_M_X64) || defined(__x86_64__)
    machine = IMAGE_FILE_MACHINE_AMD64;
    frame.AddrPC.Offset = context.Rip;
    frame.AddrFrame.Offset = context.Rbp;
    frame.AddrStack.Offset = context.Rsp;
#elif defined(_M_ARM64) || defined(__aarch64__)
    machine = IMAGE_FILE_MACHINE_ARM64;
    frame.AddrPC.Offset = context.Pc;
    frame.AddrFrame.Offset = context.Fp;
    frame.AddrStack.Offset = context.Sp;
#else
    putf(b, "  (no stack walk on this architecture)\n");
    return;
#endif
    frame.AddrPC.Mode = AddrModeFlat;
    frame.AddrFrame.Mode = AddrModeFlat;
    frame.AddrStack.Mode = AddrModeFlat;

    static char symbolBuffer[sizeof(SYMBOL_INFO) + 512];
    for (int i = 0; i < 128; i++) {
        if (!StackWalk64(machine, process, thread, &frame, &context, NULL, SymFunctionTableAccess64, SymGetModuleBase64, NULL)) break;
        DWORD64 pc = frame.AddrPC.Offset;
        if (pc == 0) break;
        char module[MAX_PATH * 3];
        DWORD64 base;
        module_for((const void *)(ULONG_PTR)pc, module, sizeof module, &base);
        putf(b, "%3d  %-28s 0x%016llx", i, module[0] ? base_name(module) : "?", (unsigned long long)pc);
        if (base) putf(b, " (+0x%llx)", (unsigned long long)(pc - base));
        SYMBOL_INFO *symbol = (SYMBOL_INFO *)symbolBuffer;
        memset(symbolBuffer, 0, sizeof symbolBuffer);
        symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen = 511;
        DWORD64 displacement = 0;
        if (SymFromAddr(process, pc, &displacement, symbol)) {
            putf(b, " %s + %llu", symbol->Name, (unsigned long long)displacement);
            IMAGEHLP_LINE64 line;
            memset(&line, 0, sizeof line);
            line.SizeOfStruct = sizeof line;
            DWORD lineDisplacement = 0;
            if (SymGetLineFromAddr64(process, pc, &lineDisplacement, &line) && line.FileName)
                putf(b, " (%s:%lu)", line.FileName, (unsigned long)line.LineNumber);
        }
        putf(b, "\n");
    }
}

// Writes `<dir>\<app>-<timestamp>.dmp` and `.txt`. `pointers` may come from the filter or
// be built from a captured context (SIGABRT, ccrash_write_report).
static int write_report(EXCEPTION_POINTERS *pointers, const char *reason) {
    if (!g_directory[0]) return 0;
    SYSTEMTIME now;
    GetLocalTime(&now);
    wchar_t wideApp[256];
    MultiByteToWideChar(CP_UTF8, 0, g_app, -1, wideApp, 256);
    wchar_t stem[CCRASH_PATH_MAX + 300];
    _snwprintf_s(stem, sizeof stem / sizeof stem[0], _TRUNCATE, L"%s\\%s-%04u-%02u-%02u_%02u-%02u-%02u-%lu", g_directory, wideApp,
                 now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond, (unsigned long)GetCurrentProcessId());
    wchar_t dumpPath[CCRASH_PATH_MAX + 320], textPath[CCRASH_PATH_MAX + 320];
    _snwprintf_s(dumpPath, sizeof dumpPath / sizeof dumpPath[0], _TRUNCATE, L"%s.dmp", stem);
    _snwprintf_s(textPath, sizeof textPath / sizeof textPath[0], _TRUNCATE, L"%s.txt", stem);

    HANDLE process = GetCurrentProcess();
    HANDLE thread = GetCurrentThread();

    // The minidump first: it is the part a developer needs most, and DbgHelp's symbol
    // loading below may fail in a damaged process.
    int dumped = 0;
    HANDLE dumpFile = CreateFileW(dumpPath, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (dumpFile != INVALID_HANDLE_VALUE) {
        MINIDUMP_EXCEPTION_INFORMATION mei;
        mei.ThreadId = GetCurrentThreadId();
        mei.ExceptionPointers = pointers;
        mei.ClientPointers = FALSE;
        MINIDUMP_TYPE type = (MINIDUMP_TYPE)(MiniDumpNormal | MiniDumpWithThreadInfo | MiniDumpWithUnloadedModules | MiniDumpWithIndirectlyReferencedMemory);
        // Without an exception record (a report asked for, not a crash) the dump has no
        // exception stream; the thread list still holds this thread's stack.
        int hasException = pointers && pointers->ExceptionRecord;
        dumped = MiniDumpWriteDump(process, GetCurrentProcessId(), dumpFile, type, hasException ? &mei : NULL, NULL, NULL) ? 1 : 0;
        CloseHandle(dumpFile);
    }

    buf_t b = { g_text, sizeof g_text };
    g_text[0] = 0;
    wchar_t exeWide[MAX_PATH];
    char exe[MAX_PATH * 3] = "";
    DWORD exeLength = GetModuleFileNameW(NULL, exeWide, MAX_PATH);
    if (exeLength > 0) WideCharToMultiByte(CP_UTF8, 0, exeWide, (int)exeLength + 1, exe, sizeof exe, NULL, NULL);
    putf(&b, "AppKitCross crash report\n");
    putf(&b, "Application: %s\n", g_app);
    putf(&b, "Bundle identifier: %s\n", g_bundle);
    putf(&b, "Executable: %s\n", exe);
    putf(&b, "Process: %lu\n", (unsigned long)GetCurrentProcessId());
    putf(&b, "Thread: %lu\n", (unsigned long)GetCurrentThreadId());
    putf(&b, "Time: %04u-%02u-%02u %02u:%02u:%02u (local)\n", now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond);
    if (reason) putf(&b, "Reason: %s\n", reason);
    if (pointers && pointers->ExceptionRecord) {
        EXCEPTION_RECORD *record = pointers->ExceptionRecord;
        putf(&b, "Exception: 0x%08lX %s\n", (unsigned long)record->ExceptionCode, exception_name(record->ExceptionCode));
        char module[MAX_PATH * 3];
        DWORD64 base;
        module_for(record->ExceptionAddress, module, sizeof module, &base);
        putf(&b, "Address: 0x%016llx in %s", (unsigned long long)(ULONG_PTR)record->ExceptionAddress, module[0] ? module : "?");
        if (base) putf(&b, " (+0x%llx)", (unsigned long long)((ULONG_PTR)record->ExceptionAddress - base));
        putf(&b, "\n");
        if (record->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && record->NumberParameters >= 2) {
            const char *op = record->ExceptionInformation[0] == 0 ? "reading" : record->ExceptionInformation[0] == 1 ? "writing" : "executing";
            putf(&b, "Access violation %s 0x%016llx\n", op, (unsigned long long)record->ExceptionInformation[1]);
        }
    }
    putf(&b, "Minidump: %s\n", dumped ? "written next to this report" : "could not be written");

    // Symbols: the executable's directory (the PDB beside it) and the default path.
    putf(&b, "\nBacktrace (module, address, offset in the module, symbol where the PDB is found):\n");
    SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES | SYMOPT_FAIL_CRITICAL_ERRORS | SYMOPT_NO_PROMPTS);
    int symbols = SymInitializeW(process, NULL, TRUE) ? 1 : 0;
    if (pointers && pointers->ContextRecord) put_backtrace(&b, process, thread, pointers->ContextRecord);
    if (symbols) SymCleanup(process);

    int written = 0;
    HANDLE textFile = CreateFileW(textPath, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (textFile != INVALID_HANDLE_VALUE) {
        DWORD out = 0;
        written = WriteFile(textFile, g_text, (DWORD)strlen(g_text), &out, NULL) ? 1 : 0;
        CloseHandle(textFile);
    }
    WideCharToMultiByte(CP_UTF8, 0, textPath, -1, g_last, sizeof g_last, NULL, NULL);
    fprintf(stderr, "AppKitCross: crash report written to %s\n", g_last);
    fflush(stderr);
    return written;
}

static LONG WINAPI filter(EXCEPTION_POINTERS *pointers) {
    if (InterlockedExchange(&g_handling, 1) == 0) write_report(pointers, NULL);
    if (g_previousFilter) return g_previousFilter(pointers);
    return EXCEPTION_CONTINUE_SEARCH;
}

static void report_from_here(DWORD code, const char *reason) {
    CONTEXT context;
    memset(&context, 0, sizeof context);
    RtlCaptureContext(&context);
    EXCEPTION_RECORD record;
    memset(&record, 0, sizeof record);
    record.ExceptionCode = code;
#if defined(_M_X64) || defined(__x86_64__)
    record.ExceptionAddress = (PVOID)(ULONG_PTR)context.Rip;
#elif defined(_M_ARM64) || defined(__aarch64__)
    record.ExceptionAddress = (PVOID)(ULONG_PTR)context.Pc;
#endif
    EXCEPTION_POINTERS pointers = { &record, &context };
    write_report(&pointers, reason);
}

static void abort_handler(int sig) {
    (void)sig;
    if (InterlockedExchange(&g_handling, 1) == 0) report_from_here(0x40000015 /* STATUS_FATAL_APP_EXIT */, "abort() was called");
    // Returning lets the CRT finish abort(): the process ends with exit code 3.
}

static int make_directories(const wchar_t *path) {
    int result = SHCreateDirectoryExW(NULL, path, NULL);
    return result == ERROR_SUCCESS || result == ERROR_ALREADY_EXISTS || result == ERROR_FILE_EXISTS;
}

int ccrash_configure(const char *directory, const char *appName, const char *bundleIdentifier) {
    if (!directory) return 0;
    wchar_t wide[CCRASH_PATH_MAX];
    if (!MultiByteToWideChar(CP_UTF8, 0, directory, -1, wide, CCRASH_PATH_MAX)) return 0;
    for (wchar_t *c = wide; *c; c++) if (*c == L'/') *c = L'\\';
    size_t len = wcslen(wide);
    while (len > 3 && wide[len - 1] == L'\\') wide[--len] = 0;
    if (!make_directories(wide)) return 0;
    wcscpy_s(g_directory, CCRASH_PATH_MAX, wide);
    copy(g_app, sizeof g_app, appName && *appName ? appName : "app");
    for (char *c = g_app; *c; c++) if (strchr("\\/:*?\"<>| ", *c)) *c = '_';
    copy(g_bundle, sizeof g_bundle, bundleIdentifier);
    return 1;
}

int ccrash_install(const char *directory, const char *appName, const char *bundleIdentifier) {
    if (!ccrash_configure(directory, appName, bundleIdentifier)) return 0;
    if (InterlockedExchange(&g_installed, 1)) return 1;

    ULONG reserve = 64 * 1024;
    SetThreadStackGuarantee(&reserve);
    g_previousFilter = SetUnhandledExceptionFilter(filter);
    signal(SIGABRT, abort_handler);
    // No "abort() has been called" message box in a GUI app; the report says it.
    _set_abort_behavior(0, _WRITE_ABORT_MSG);
    return 1;
}

int ccrash_installed(void) { return g_installed ? 1 : 0; }

const char *ccrash_last_report(void) { return g_last; }

int ccrash_write_report(const char *reason) {
    CONTEXT context;
    memset(&context, 0, sizeof context);
    RtlCaptureContext(&context);
    EXCEPTION_POINTERS pointers = { NULL, &context };
    return write_report(&pointers, reason && *reason ? reason : "requested");
}

void ccrash_crash_now(int kind) {
    switch (kind) {
    case 1: __builtin_trap();
    case 2: abort();
    default: {
        volatile int *volatile p = (int *)0;
        *p = 42;
        break;
    }
    }
    abort();
}

#endif
