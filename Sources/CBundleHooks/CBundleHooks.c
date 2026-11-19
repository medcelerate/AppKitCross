// See CBundleHooks.h (ADR-0045).

#include "CBundleHooks.h"
#include <stddef.h>

#define SWIFTCALL __attribute__((swiftcall))
#define SELF __attribute__((swift_context))
// `Any?` is address-only in the Swift convention: it is returned through a buffer the caller
// passes (an indirect result), never in registers, so the four-word hooks take that buffer.
#define INDIRECT __attribute__((swift_indirect_result))

akc_words2 (*akc_dispatch_w2_w2w2w2)(int32_t, void *, akc_words2, akc_words2, akc_words2) = NULL;
akc_words2 (*akc_dispatch_w2_w2w2)(int32_t, void *, akc_words2, akc_words2) = NULL;
akc_words4 (*akc_dispatch_w4_w2)(int32_t, void *, akc_words2) = NULL;
void *(*akc_dispatch_w1)(int32_t, void *) = NULL;
akc_words2 (*akc_dispatch_w2)(int32_t, void *) = NULL;

#define HOOK_W2_W2W2W2(n, id) static SWIFTCALL akc_words2 n(akc_words2 a, akc_words2 b, akc_words2 c, SELF void *self) { return akc_dispatch_w2_w2w2w2(id, self, a, b, c); }
#define HOOK_W2_W2W2(n, id) static SWIFTCALL akc_words2 n(akc_words2 a, akc_words2 b, SELF void *self) { return akc_dispatch_w2_w2w2(id, self, a, b); }
#define HOOK_W4_W2(n, id) static SWIFTCALL void n(INDIRECT akc_words4 *out, akc_words2 a, SELF void *self) { *out = akc_dispatch_w4_w2(id, self, a); }
#define HOOK_W1(n, id) static SWIFTCALL void *n(SELF void *self) { return akc_dispatch_w1(id, self); }
#define HOOK_W2(n, id) static SWIFTCALL akc_words2 n(SELF void *self) { return akc_dispatch_w2(id, self); }

HOOK_W2_W2W2W2(hook_localized_string, AKC_HOOK_LOCALIZED_STRING)
HOOK_W1(hook_preferred_localizations, AKC_HOOK_PREFERRED_LOCALIZATIONS)
HOOK_W1(hook_localizations, AKC_HOOK_LOCALIZATIONS)
HOOK_W2(hook_development_localization, AKC_HOOK_DEVELOPMENT_LOCALIZATION)
HOOK_W1(hook_info_dictionary, AKC_HOOK_INFO_DICTIONARY)
HOOK_W2(hook_bundle_identifier, AKC_HOOK_BUNDLE_IDENTIFIER)
HOOK_W4_W2(hook_object_for_info_key, AKC_HOOK_OBJECT_FOR_INFO_KEY)
HOOK_W2(hook_resource_url, AKC_HOOK_RESOURCE_URL)
HOOK_W2(hook_resource_path, AKC_HOOK_RESOURCE_PATH)
HOOK_W2_W2W2(hook_url_for_resource, AKC_HOOK_URL_FOR_RESOURCE)
HOOK_W2_W2W2W2(hook_url_for_resource_subdir, AKC_HOOK_URL_FOR_RESOURCE_SUBDIR)
HOOK_W2_W2W2(hook_path_for_resource, AKC_HOOK_PATH_FOR_RESOURCE)
HOOK_W2_W2W2W2(hook_path_for_resource_dir, AKC_HOOK_PATH_FOR_RESOURCE_DIR)

const void *akc_bundle_hook(int32_t hook) {
    switch (hook) {
    case AKC_HOOK_LOCALIZED_STRING: return (const void *)&hook_localized_string;
    case AKC_HOOK_PREFERRED_LOCALIZATIONS: return (const void *)&hook_preferred_localizations;
    case AKC_HOOK_LOCALIZATIONS: return (const void *)&hook_localizations;
    case AKC_HOOK_DEVELOPMENT_LOCALIZATION: return (const void *)&hook_development_localization;
    case AKC_HOOK_INFO_DICTIONARY: return (const void *)&hook_info_dictionary;
    case AKC_HOOK_BUNDLE_IDENTIFIER: return (const void *)&hook_bundle_identifier;
    case AKC_HOOK_OBJECT_FOR_INFO_KEY: return (const void *)&hook_object_for_info_key;
    case AKC_HOOK_RESOURCE_URL: return (const void *)&hook_resource_url;
    case AKC_HOOK_RESOURCE_PATH: return (const void *)&hook_resource_path;
    case AKC_HOOK_URL_FOR_RESOURCE: return (const void *)&hook_url_for_resource;
    case AKC_HOOK_URL_FOR_RESOURCE_SUBDIR: return (const void *)&hook_url_for_resource_subdir;
    case AKC_HOOK_PATH_FOR_RESOURCE: return (const void *)&hook_path_for_resource;
    case AKC_HOOK_PATH_FOR_RESOURCE_DIR: return (const void *)&hook_path_for_resource_dir;
    default: return NULL;
    }
}

typedef SWIFTCALL akc_words2 (*fn_w2_w2w2w2)(akc_words2, akc_words2, akc_words2, SELF void *);
typedef SWIFTCALL akc_words2 (*fn_w2_w2w2)(akc_words2, akc_words2, SELF void *);
typedef SWIFTCALL void (*fn_w4_w2)(INDIRECT akc_words4 *, akc_words2, SELF void *);
typedef SWIFTCALL void *(*fn_w1)(SELF void *);
typedef SWIFTCALL akc_words2 (*fn_w2)(SELF void *);

akc_words2 akc_call_w2_w2w2w2(const void *fn, void *self, akc_words2 a, akc_words2 b, akc_words2 c) { return ((fn_w2_w2w2w2)fn)(a, b, c, self); }
akc_words2 akc_call_w2_w2w2(const void *fn, void *self, akc_words2 a, akc_words2 b) { return ((fn_w2_w2w2)fn)(a, b, self); }
akc_words4 akc_call_w4_w2(const void *fn, void *self, akc_words2 a) { akc_words4 r; ((fn_w4_w2)fn)(&r, a, self); return r; }
void *akc_call_w1(const void *fn, void *self) { return ((fn_w1)fn)(self); }
akc_words2 akc_call_w2(const void *fn, void *self) { return ((fn_w2)fn)(self); }
