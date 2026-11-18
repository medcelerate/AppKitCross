// The crash handler on Linux (and the macOS host build, for the tests): SIGSEGV, SIGBUS,
// SIGILL, SIGFPE, SIGTRAP and SIGABRT write a text report (signal, fault address, thread,
// backtrace, the memory map for symbolicating it) and then hand the signal to whoever had
// it before (the Swift runtime's backtracer when SWIFT_BACKTRACE enabled it, else the
// default action, which ends the process with the signal and a core dump if allowed).
//
// Everything the handler does is async-signal-safe or as close as a crash handler gets:
// paths and names are prepared at install time, numbers are formatted by hand, the file is
// written with open/write, and backtrace() is called once at install so its first call
// (which may load libgcc_s) does not happen inside the handler. The handler runs on an
// alternate stack so a stack overflow can still be reported.
#if !defined(_WIN32)

#define _GNU_SOURCE
#include "ccrashreport.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/syscall.h>
#endif
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#include <pthread.h>
#endif
#if __has_include(<execinfo.h>)
#include <execinfo.h>
#define CCRASH_HAS_EXECINFO 1
#endif

#define CCRASH_PATH_MAX 4096

static char g_directory[CCRASH_PATH_MAX];
static char g_app[256];
static char g_bundle[256];
static char g_exe[CCRASH_PATH_MAX];
static char g_last[CCRASH_PATH_MAX];
static volatile sig_atomic_t g_installed;
static volatile sig_atomic_t g_handling;

static const int g_signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP, SIGABRT };
#define CCRASH_NSIGNALS ((int)(sizeof g_signals / sizeof g_signals[0]))
static struct sigaction g_previous[CCRASH_NSIGNALS];
static char g_altstack[64 * 1024];

// MARK: Async-signal-safe text

typedef struct { char *p; size_t left; } buf_t;

static void put(buf_t *b, const char *s) {
    while (*s && b->left > 1) { *b->p++ = *s++; b->left--; }
    *b->p = 0;
}
static void put_u(buf_t *b, unsigned long long v) {
    char tmp[24]; int n = 0;
    do { tmp[n++] = (char)('0' + v % 10); v /= 10; } while (v && n < 23);
    while (n && b->left > 1) { *b->p++ = tmp[--n]; b->left--; }
    *b->p = 0;
}
static void put_hex(buf_t *b, unsigned long long v) {
    char tmp[17]; int n = 0;
    do { tmp[n++] = "0123456789abcdef"[v & 15]; v >>= 4; } while (v && n < 16);
    put(b, "0x");
    while (n && b->left > 1) { *b->p++ = tmp[--n]; b->left--; }
    *b->p = 0;
}
static void put_2(buf_t *b, int v) { if (v < 10) put(b, "0"); put_u(b, (unsigned)v); }

static void write_all(int fd, const char *s, size_t n) {
    while (n > 0) {
        ssize_t w = write(fd, s, n);
        if (w < 0) { if (errno == EINTR) continue; return; }
        s += w; n -= (size_t)w;
    }
}
static void write_str(int fd, const char *s) { write_all(fd, s, strlen(s)); }

static const char *signal_name(int sig) {
    switch (sig) {
    case SIGSEGV: return "SIGSEGV (segmentation fault)";
    case SIGBUS: return "SIGBUS (bus error)";
    case SIGILL: return "SIGILL (illegal instruction: a Swift runtime trap, such as fatalError or a failed precondition, on x86_64)";
    case SIGFPE: return "SIGFPE (arithmetic exception)";
    case SIGTRAP: return "SIGTRAP (trap: a Swift runtime trap, such as fatalError or a failed precondition, on arm64)";
    case SIGABRT: return "SIGABRT (abort)";
    default: return "signal";
    }
}

// Civil date from a Unix day count (Howard Hinnant's algorithm): gmtime is not
// async-signal-safe.
static void civil(long long days, int *y, int *m, int *d) {
    days += 719468;
    long long era = (days >= 0 ? days : days - 146096) / 146097;
    unsigned doe = (unsigned)(days - era * 146097);
    unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long long yy = (long long)yoe + era * 400;
    unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    unsigned mp = (5 * doy + 2) / 153;
    *d = (int)(doy - (153 * mp + 2) / 5 + 1);
    *m = (int)(mp < 10 ? mp + 3 : mp - 9);
    *y = (int)(yy + (*m <= 2));
}

static void put_timestamp(buf_t *b, time_t t, int forFileName) {
    long long secs = (long long)t;
    long long days = secs >= 0 ? secs / 86400 : (secs - 86399) / 86400;
    long long rem = secs - days * 86400;
    int y, m, d; civil(days, &y, &m, &d);
    put_u(b, (unsigned)y); put(b, "-"); put_2(b, m); put(b, "-"); put_2(b, d);
    put(b, forFileName ? "_" : " ");
    put_2(b, (int)(rem / 3600)); put(b, forFileName ? "-" : ":");
    put_2(b, (int)(rem / 60 % 60)); put(b, forFileName ? "-" : ":");
    put_2(b, (int)(rem % 60));
    if (!forFileName) put(b, " UTC");
}

static unsigned long long thread_id(void) {
#if defined(__linux__)
    return (unsigned long long)syscall(SYS_gettid);
#elif defined(__APPLE__)
    uint64_t tid = 0; pthread_threadid_np(NULL, &tid); return tid;
#else
    return 0;
#endif
}

// MARK: The report

static int write_report(int sig, siginfo_t *info, const char *reason) {
    if (!g_directory[0]) return 0;
    time_t now = time(NULL);
    char path[CCRASH_PATH_MAX];
    buf_t pb = { path, sizeof path };
    put(&pb, g_directory); put(&pb, "/"); put(&pb, g_app); put(&pb, "-");
    put_timestamp(&pb, now, 1); put(&pb, "-"); put_u(&pb, (unsigned long long)getpid()); put(&pb, ".txt");
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return 0;

    char head[2048];
    buf_t b = { head, sizeof head };
    put(&b, "AppKitCross crash report\n");
    put(&b, "Application: "); put(&b, g_app); put(&b, "\n");
    put(&b, "Bundle identifier: "); put(&b, g_bundle); put(&b, "\n");
    put(&b, "Executable: "); put(&b, g_exe); put(&b, "\n");
    put(&b, "Process: "); put_u(&b, (unsigned long long)getpid()); put(&b, "\n");
    put(&b, "Thread: "); put_u(&b, thread_id()); put(&b, "\n");
    put(&b, "Time: "); put_timestamp(&b, now, 0); put(&b, "\n");
    if (reason) {
        put(&b, "Reason: "); put(&b, reason); put(&b, "\n");
    } else {
        put(&b, "Signal: "); put_u(&b, (unsigned)sig); put(&b, " "); put(&b, signal_name(sig)); put(&b, "\n");
        if (info) {
            put(&b, "Signal code: "); put_u(&b, (unsigned)info->si_code); put(&b, "\n");
            if (sig == SIGSEGV || sig == SIGBUS || sig == SIGILL || sig == SIGFPE || sig == SIGTRAP) {
                put(&b, "Fault address: "); put_hex(&b, (unsigned long long)(uintptr_t)info->si_addr); put(&b, "\n");
            }
        }
    }
    write_all(fd, head, (size_t)(b.p - head));

#if CCRASH_HAS_EXECINFO
    void *frames[128];
    int n = backtrace(frames, 128);
    write_str(fd, "\nBacktrace (module(+offset) [address]; `swift demangle` reads the Swift names):\n");
    backtrace_symbols_fd(frames, n, fd);
#else
    write_str(fd, "\nBacktrace: not available on this C library\n");
#endif

#if defined(__linux__)
    // The memory map: with it, an address in the backtrace becomes module + offset even
    // for frames backtrace_symbols could not name (addr2line -e <module> <offset>).
    int maps = open("/proc/self/maps", O_RDONLY | O_CLOEXEC);
    if (maps >= 0) {
        write_str(fd, "\nMemory map (/proc/self/maps):\n");
        char chunk[4096];
        ssize_t r;
        while ((r = read(maps, chunk, sizeof chunk)) > 0) write_all(fd, chunk, (size_t)r);
        close(maps);
    }
#endif
    close(fd);

    // The last report's path, for ccrash_last_report and the line on stderr.
    buf_t lb = { g_last, sizeof g_last };
    put(&lb, path);
    write_str(STDERR_FILENO, "AppKitCross: crash report written to ");
    write_str(STDERR_FILENO, path);
    write_str(STDERR_FILENO, "\n");
    return 1;
}

static void handler(int sig, siginfo_t *info, void *context) {
    (void)context;
    if (!g_handling) {
        g_handling = 1;
        write_report(sig, info, NULL);
    }
    // Hand the signal to the previous owner: restore its action and raise again. A
    // synchronous fault would re-fault on return anyway; raise() makes SIGABRT and a
    // previous SA_SIGINFO handler see it too.
    for (int i = 0; i < CCRASH_NSIGNALS; i++) {
        if (g_signals[i] == sig) { sigaction(sig, &g_previous[i], NULL); break; }
    }
    raise(sig);
}

// MARK: Public

static int make_directories(const char *path) {
    char tmp[CCRASH_PATH_MAX];
    size_t n = strlen(path);
    if (n == 0 || n >= sizeof tmp) return 0;
    memcpy(tmp, path, n + 1);
    for (size_t i = 1; i < n; i++) {
        if (tmp[i] == '/') {
            tmp[i] = 0;
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return 0;
            tmp[i] = '/';
        }
    }
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return 0;
    return 1;
}

static void copy(char *dst, size_t size, const char *src) {
    if (!src) src = "";
    size_t n = strlen(src);
    if (n >= size) n = size - 1;
    memcpy(dst, src, n);
    dst[n] = 0;
}

int ccrash_configure(const char *directory, const char *appName, const char *bundleIdentifier) {
    if (!directory || !make_directories(directory)) return 0;
    copy(g_directory, sizeof g_directory, directory);
    // A trailing slash would double up in the file name.
    size_t len = strlen(g_directory);
    while (len > 1 && g_directory[len - 1] == '/') g_directory[--len] = 0;
    copy(g_app, sizeof g_app, appName && *appName ? appName : "app");
    for (char *c = g_app; *c; c++) if (*c == '/' || *c == ' ') *c = '_';
    copy(g_bundle, sizeof g_bundle, bundleIdentifier);
#if defined(__linux__)
    ssize_t r = readlink("/proc/self/exe", g_exe, sizeof g_exe - 1);
    g_exe[r > 0 ? r : 0] = 0;
#elif defined(__APPLE__)
    uint32_t size = sizeof g_exe;
    if (_NSGetExecutablePath(g_exe, &size) != 0) g_exe[0] = 0;
#endif
    return 1;
}

int ccrash_install(const char *directory, const char *appName, const char *bundleIdentifier) {
    if (!ccrash_configure(directory, appName, bundleIdentifier)) return 0;
    if (g_installed) return 1;

#if CCRASH_HAS_EXECINFO
    void *warm[4];
    (void)backtrace(warm, 4);
#endif
    stack_t ss;
    memset(&ss, 0, sizeof ss);
    ss.ss_sp = g_altstack;
    ss.ss_size = sizeof g_altstack;
    sigaltstack(&ss, NULL);

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&sa.sa_mask);
    for (int i = 0; i < CCRASH_NSIGNALS; i++) sigaction(g_signals[i], &sa, &g_previous[i]);
    g_installed = 1;
    return 1;
}

int ccrash_installed(void) { return g_installed ? 1 : 0; }

const char *ccrash_last_report(void) { return g_last; }

int ccrash_write_report(const char *reason) {
    return write_report(0, NULL, reason && *reason ? reason : "requested");
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
