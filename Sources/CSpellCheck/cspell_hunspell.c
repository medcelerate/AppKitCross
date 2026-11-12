// hunspell backend of cspell.h (Linux). libhunspell is opened with dlopen and dictionaries
// are found in $DICPATH and the usual system directories, so a machine without either
// still runs: cspell_backend() then answers "none" and AppKit falls back to its word list.
#if !defined(_WIN32)
#include "cspell.h"
#include <dirent.h>
#include <dlfcn.h>
#include <iconv.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdio.h>
#include <sys/stat.h>

typedef struct Hunhandle Hunhandle;
static Hunhandle *(*h_create)(const char *, const char *);
static void (*h_destroy)(Hunhandle *);
static int (*h_spell)(Hunhandle *, const char *);
static int (*h_suggest)(Hunhandle *, char ***, const char *);
static void (*h_free_list)(Hunhandle *, char ***, int);
static int (*h_add)(Hunhandle *, const char *);
static char *(*h_get_dic_encoding)(Hunhandle *);
static int loaded = -1;

struct cspell_checker {
    Hunhandle *handle;
    iconv_t to_dict;     // UTF-8 -> dictionary encoding, or (iconv_t)-1 for UTF-8 dictionaries
    iconv_t from_dict;
};

static int load(void) {
    if (loaded >= 0) return loaded;
    const char *names[] = { "libhunspell-1.7.so.0", "libhunspell-1.6.so.0", "libhunspell-1.7.so", "libhunspell.so", NULL };
    void *lib = NULL;
    for (int i = 0; names[i] && !lib; i++) lib = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (!lib) { loaded = 0; return 0; }
    h_create = (Hunhandle *(*)(const char *, const char *))dlsym(lib, "Hunspell_create");
    h_destroy = (void (*)(Hunhandle *))dlsym(lib, "Hunspell_destroy");
    h_spell = (int (*)(Hunhandle *, const char *))dlsym(lib, "Hunspell_spell");
    h_suggest = (int (*)(Hunhandle *, char ***, const char *))dlsym(lib, "Hunspell_suggest");
    h_free_list = (void (*)(Hunhandle *, char ***, int))dlsym(lib, "Hunspell_free_list");
    h_add = (int (*)(Hunhandle *, const char *))dlsym(lib, "Hunspell_add");
    h_get_dic_encoding = (char *(*)(Hunhandle *))dlsym(lib, "Hunspell_get_dic_encoding");
    loaded = (h_create && h_destroy && h_spell && h_suggest && h_free_list && h_add) ? 1 : 0;
    return loaded;
}

static const char *dirs[] = { NULL /* $DICPATH */, "/usr/share/hunspell", "/usr/share/myspell", "/usr/share/myspell/dicts", "/usr/local/share/hunspell", NULL };

static int exists(const char *path) { struct stat st; return stat(path, &st) == 0; }

/// Finds <dir>/<name>.aff and .dic for a language ("en-US" is tried as en_US, then en).
static int find_dictionary(const char *language, char *aff, char *dic, size_t size) {
    char name[64];
    snprintf(name, sizeof name, "%s", language);
    for (char *p = name; *p; p++) if (*p == '-') *p = '_';
    dirs[0] = getenv("DICPATH");
    for (int attempt = 0; attempt < 2; attempt++) {
        for (int i = 0; i < 6; i++) {
            if (i > 0 && !dirs[i]) break;
            if (!dirs[i]) continue;
            snprintf(aff, size, "%s/%s.aff", dirs[i], name);
            snprintf(dic, size, "%s/%s.dic", dirs[i], name);
            if (exists(aff) && exists(dic)) return 1;
        }
        char *underscore = strchr(name, '_');
        if (!underscore) break;
        *underscore = 0;   // en_US -> en
    }
    return 0;
}

const char *cspell_backend(void) {
    if (!load()) return "none";
    char *langs = cspell_languages();
    int any = langs && langs[0];
    cspell_free(langs);
    return any ? "hunspell" : "none";
}

char *cspell_languages(void) {
    if (!load()) return NULL;
    size_t cap = 256, len = 0;
    char *out = (char *)malloc(cap);
    if (!out) return NULL;
    dirs[0] = getenv("DICPATH");
    for (int i = 0; i < 6; i++) {
        if (i > 0 && !dirs[i]) break;
        if (!dirs[i]) continue;
        DIR *d = opendir(dirs[i]);
        if (!d) continue;
        struct dirent *e;
        while ((e = readdir(d))) {
            size_t n = strlen(e->d_name);
            if (n < 5 || strcmp(e->d_name + n - 4, ".dic") != 0 || e->d_name[0] == '.' || strncmp(e->d_name, "hyph_", 5) == 0) continue;
            char lang[64];
            snprintf(lang, sizeof lang, "%.*s", (int)(n - 4), e->d_name);
            char aff[512];
            snprintf(aff, sizeof aff, "%s/%s.aff", dirs[i], lang);
            if (!exists(aff)) continue;
            for (char *p = lang; *p; p++) if (*p == '_') *p = '-';
            // Skip duplicates (a dictionary installed in two directories).
            int dup = 0;
            for (size_t k = 0; k < len; k += strlen(out + k) + 1) if (strcmp(out + k, lang) == 0) { dup = 1; break; }
            if (dup) continue;
            size_t need = strlen(lang) + 1;
            if (len + need + 1 > cap) { cap = (len + need + 1) * 2; char *grown = (char *)realloc(out, cap); if (!grown) { closedir(d); free(out); return NULL; } out = grown; }
            memcpy(out + len, lang, need);
            len += need;
        }
        closedir(d);
    }
    out[len] = 0;
    return out;
}

cspell_checker *cspell_open(const char *language) {
    if (!load() || !language) return NULL;
    char aff[512], dic[512];
    if (!find_dictionary(language, aff, dic, sizeof aff)) return NULL;
    Hunhandle *h = h_create(aff, dic);
    if (!h) return NULL;
    cspell_checker *c = (cspell_checker *)calloc(1, sizeof *c);
    if (!c) { h_destroy(h); return NULL; }
    c->handle = h;
    c->to_dict = (iconv_t)-1;
    c->from_dict = (iconv_t)-1;
    const char *enc = h_get_dic_encoding ? h_get_dic_encoding(h) : NULL;
    if (enc && strcasecmp(enc, "UTF-8") != 0 && strcasecmp(enc, "UTF8") != 0) {
        c->to_dict = iconv_open(enc, "UTF-8");
        c->from_dict = iconv_open("UTF-8", enc);
    }
    return c;
}

void cspell_close(cspell_checker *c) {
    if (!c) return;
    if (c->to_dict != (iconv_t)-1) iconv_close(c->to_dict);
    if (c->from_dict != (iconv_t)-1) iconv_close(c->from_dict);
    h_destroy(c->handle);
    free(c);
}

/// A malloc'd copy of `s` in the other encoding (or a plain copy).
static char *convert(iconv_t cd, const char *s) {
    size_t inLeft = strlen(s);
    if (cd == (iconv_t)-1) { char *d = (char *)malloc(inLeft + 1); if (d) memcpy(d, s, inLeft + 1); return d; }
    size_t cap = inLeft * 4 + 4, outLeft = cap - 1;
    char *out = (char *)malloc(cap);
    if (!out) return NULL;
    char *in = (char *)s, *o = out;
    iconv(cd, NULL, NULL, NULL, NULL);
    if (iconv(cd, &in, &inLeft, &o, &outLeft) == (size_t)-1) { free(out); return NULL; }
    *o = 0;
    return out;
}

int cspell_check(cspell_checker *c, const char *word) {
    if (!c || !word) return -1;
    char *w = convert(c->to_dict, word);
    if (!w) return 0;   // not representable in the dictionary's encoding
    int ok = h_spell(c->handle, w) != 0;
    free(w);
    return ok;
}

char *cspell_suggest(cspell_checker *c, const char *word) {
    if (!c || !word) return NULL;
    char *w = convert(c->to_dict, word);
    if (!w) return NULL;
    char **list = NULL;
    int n = h_suggest(c->handle, &list, w);
    free(w);
    size_t cap = 1, len = 0;
    for (int i = 0; i < n; i++) cap += strlen(list[i]) * 4 + 1;
    char *out = (char *)malloc(cap);
    if (!out) { if (list) h_free_list(c->handle, &list, n); return NULL; }
    for (int i = 0; i < n; i++) {
        char *u = convert(c->from_dict, list[i]);
        if (!u) continue;
        size_t k = strlen(u) + 1;
        memcpy(out + len, u, k);
        len += k;
        free(u);
    }
    out[len] = 0;
    if (list) h_free_list(c->handle, &list, n);
    return out;
}

void cspell_add(cspell_checker *c, const char *word) {
    if (!c || !word) return;
    char *w = convert(c->to_dict, word);
    if (w) { h_add(c->handle, w); free(w); }
}

void cspell_free(char *list) { free(list); }
#endif
