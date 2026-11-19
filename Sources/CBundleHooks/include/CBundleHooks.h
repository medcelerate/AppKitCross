// Swift-calling-convention trampolines for Foundation.Bundle's vtable (ADR-0045).
//
// swift-corelibs-foundation's Bundle cannot be subclassed from another module (its vtable names
// implementation-only CoreFoundation types), so the port routes the members it fixes by placing
// these functions in Bundle's vtable slots. Each is declared with clang's `swiftcall` convention
// and takes the receiver as its `swift_context` parameter (LLVM's swiftself: the register a Swift
// method receives `self` in), so it can stand in for the method; it forwards to a plain C-ABI
// dispatcher the port sets from Swift, with the hook's index. Values cross as the words the Swift
// convention passes them in: String, String? and URL? are two words, arrays and dictionaries one,
// Any? four (returned indirectly: it is address-only).

#ifndef CBUNDLEHOOKS_H
#define CBUNDLEHOOKS_H

#include <stdint.h>

typedef struct { void *w0; void *w1; } akc_words2;
typedef struct { void *w0; void *w1; void *w2; void *w3; } akc_words4;

/// The hooks, by index (`akc_bundle_hook(index)`).
enum {
    AKC_HOOK_LOCALIZED_STRING = 0,          // (key, value?, table?) -> String
    AKC_HOOK_PREFERRED_LOCALIZATIONS,       // () -> [String]
    AKC_HOOK_LOCALIZATIONS,                 // () -> [String]
    AKC_HOOK_DEVELOPMENT_LOCALIZATION,      // () -> String?
    AKC_HOOK_INFO_DICTIONARY,               // () -> [String: Any]?
    AKC_HOOK_BUNDLE_IDENTIFIER,             // () -> String?
    AKC_HOOK_OBJECT_FOR_INFO_KEY,           // (String) -> Any?
    AKC_HOOK_RESOURCE_URL,                  // () -> URL?
    AKC_HOOK_RESOURCE_PATH,                 // () -> String?
    AKC_HOOK_URL_FOR_RESOURCE,              // (name?, ext?) -> URL?
    AKC_HOOK_URL_FOR_RESOURCE_SUBDIR,       // (name?, ext?, subdir?) -> URL?
    AKC_HOOK_PATH_FOR_RESOURCE,             // (name?, type?) -> String?
    AKC_HOOK_PATH_FOR_RESOURCE_DIR,         // (name?, type?, dir?) -> String?
    AKC_HOOK_COUNT
};

/// The dispatchers, one per shape, set by the port before any hook is installed.
extern akc_words2 (*akc_dispatch_w2_w2w2w2)(int32_t hook, void *self, akc_words2 a, akc_words2 b, akc_words2 c);
extern akc_words2 (*akc_dispatch_w2_w2w2)(int32_t hook, void *self, akc_words2 a, akc_words2 b);
extern akc_words4 (*akc_dispatch_w4_w2)(int32_t hook, void *self, akc_words2 a);
extern void *(*akc_dispatch_w1)(int32_t hook, void *self);
extern akc_words2 (*akc_dispatch_w2)(int32_t hook, void *self);

/// The Swift-convention entry point of a hook.
const void *akc_bundle_hook(int32_t hook);

/// Calls an original implementation (a Swift method taken from the vtable) with `self`.
akc_words2 akc_call_w2_w2w2w2(const void *fn, void *self, akc_words2 a, akc_words2 b, akc_words2 c);
akc_words2 akc_call_w2_w2w2(const void *fn, void *self, akc_words2 a, akc_words2 b);
akc_words4 akc_call_w4_w2(const void *fn, void *self, akc_words2 a);
void *akc_call_w1(const void *fn, void *self);
akc_words2 akc_call_w2(const void *fn, void *self);

#endif
