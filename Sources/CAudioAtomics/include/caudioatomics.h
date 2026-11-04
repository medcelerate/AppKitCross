// Atomic loads and stores for the audio module's lock-free queues (ADR-0014).
//
// The Swift `Synchronization` module needs macOS 15, above this package's deployment
// target, so the handful of atomics the real-time path needs are these inline wrappers
// over the clang builtins. Every function is lock-free on the three platforms. The
// AVFAudio module imports this as an implementation detail (`internal import`), so
// nothing that links AVFAudio needs the module map.

#ifndef CAUDIOATOMICS_H
#define CAUDIOATOMICS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline int64_t caa_load_i64(const int64_t *p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
static inline void caa_store_i64(int64_t *p, int64_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }
static inline int64_t caa_add_i64(int64_t *p, int64_t v) { return __atomic_add_fetch(p, v, __ATOMIC_ACQ_REL); }
static inline bool caa_cas_i64(int64_t *p, int64_t expected, int64_t desired) {
    return __atomic_compare_exchange_n(p, &expected, desired, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
}
static inline int32_t caa_load_i32(const int32_t *p) { return __atomic_load_n(p, __ATOMIC_ACQUIRE); }
static inline void caa_store_i32(int32_t *p, int32_t v) { __atomic_store_n(p, v, __ATOMIC_RELEASE); }
static inline int32_t caa_exchange_i32(int32_t *p, int32_t v) { return __atomic_exchange_n(p, v, __ATOMIC_ACQ_REL); }
static inline float caa_load_f32(const int32_t *p) {
    int32_t bits = __atomic_load_n(p, __ATOMIC_ACQUIRE);
    float f; __builtin_memcpy(&f, &bits, sizeof f); return f;
}
static inline void caa_store_f32(int32_t *p, float v) {
    int32_t bits; __builtin_memcpy(&bits, &v, sizeof bits);
    __atomic_store_n(p, bits, __ATOMIC_RELEASE);
}
static inline double caa_load_f64(const int64_t *p) {
    int64_t bits = __atomic_load_n(p, __ATOMIC_ACQUIRE);
    double d; __builtin_memcpy(&d, &bits, sizeof d); return d;
}
static inline void caa_store_f64(int64_t *p, double v) {
    int64_t bits; __builtin_memcpy(&bits, &v, sizeof bits);
    __atomic_store_n(p, bits, __ATOMIC_RELEASE);
}

#ifdef __cplusplus
}
#endif
#endif
