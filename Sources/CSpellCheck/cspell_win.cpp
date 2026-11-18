// Windows backend of cspell.h: the Spell Checking API (spellcheck.h, Windows 8 and later),
// the checker the system text controls use, with the user's installed language packs.
#if defined(_WIN32)
#include "cspell.h"
#include <windows.h>
#include <objbase.h>
#include <spellcheck.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

struct cspell_checker { ISpellChecker *checker; };

static std::wstring widen(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if (n > 1) MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
    return w;
}

static std::string narrow(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
    std::string s(n > 0 ? n - 1 : 0, '\0');
    if (n > 1) WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, nullptr, nullptr);
    return s;
}

static char *pack(const std::vector<std::string> &items) {
    size_t len = 1;
    for (auto &i : items) len += i.size() + 1;
    char *out = (char *)malloc(len);
    if (!out) return nullptr;
    size_t k = 0;
    for (auto &i : items) { memcpy(out + k, i.c_str(), i.size() + 1); k += i.size() + 1; }
    out[k] = 0;
    return out;
}

static ISpellCheckerFactory *factory() {
    static ISpellCheckerFactory *f = nullptr;
    static bool tried = false;
    if (tried) return f;
    tried = true;
    HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    (void)init;   // S_FALSE / RPC_E_CHANGED_MODE: COM is already up on this thread
    if (FAILED(CoCreateInstance(__uuidof(SpellCheckerFactory), nullptr, CLSCTX_INPROC_SERVER, __uuidof(ISpellCheckerFactory), reinterpret_cast<void **>(&f)))) f = nullptr;
    return f;
}

static std::vector<std::string> strings(IEnumString *e) {
    std::vector<std::string> out;
    if (!e) return out;
    LPOLESTR s = nullptr;
    while (e->Next(1, &s, nullptr) == S_OK) { out.push_back(narrow(s)); CoTaskMemFree(s); }
    e->Release();
    return out;
}

extern "C" const char *cspell_backend(void) { return factory() ? "windows" : "none"; }

extern "C" char *cspell_languages(void) {
    ISpellCheckerFactory *f = factory();
    if (!f) return nullptr;
    IEnumString *e = nullptr;
    if (FAILED(f->get_SupportedLanguages(&e))) return nullptr;
    return pack(strings(e));
}

extern "C" cspell_checker *cspell_open(const char *language) {
    ISpellCheckerFactory *f = factory();
    if (!f || !language) return nullptr;
    std::string tag(language);
    for (auto &ch : tag) if (ch == '_') ch = '-';
    std::wstring w = widen(tag.c_str());
    BOOL supported = FALSE;
    if (FAILED(f->IsSupported(w.c_str(), &supported)) || !supported) {
        // "en" alone: take the first installed dialect of it.
        IEnumString *e = nullptr;
        if (FAILED(f->get_SupportedLanguages(&e))) return nullptr;
        std::string match;
        for (auto &l : strings(e)) if (l.compare(0, tag.size(), tag) == 0 && (l.size() == tag.size() || l[tag.size()] == '-')) { match = l; break; }
        if (match.empty()) return nullptr;
        w = widen(match.c_str());
    }
    ISpellChecker *checker = nullptr;
    if (FAILED(f->CreateSpellChecker(w.c_str(), &checker)) || !checker) return nullptr;
    cspell_checker *c = (cspell_checker *)calloc(1, sizeof *c);
    if (!c) { checker->Release(); return nullptr; }
    c->checker = checker;
    return c;
}

extern "C" void cspell_close(cspell_checker *c) {
    if (!c) return;
    c->checker->Release();
    free(c);
}

extern "C" int cspell_check(cspell_checker *c, const char *word) {
    if (!c || !word) return -1;
    std::wstring w = widen(word);
    IEnumSpellingError *errors = nullptr;
    if (FAILED(c->checker->Check(w.c_str(), &errors)) || !errors) return -1;
    // Only errors that come with a corrective action are misspellings; the checker may also
    // report spans it merely has no opinion about (CORRECTIVE_ACTION_NONE).
    ISpellingError *error = nullptr;
    int ok = 1;
    while (ok && errors->Next(&error) == S_OK) {
        CORRECTIVE_ACTION action = CORRECTIVE_ACTION_NONE;
        if (SUCCEEDED(error->get_CorrectiveAction(&action)) && action != CORRECTIVE_ACTION_NONE) ok = 0;
        error->Release();
    }
    errors->Release();
    return ok;
}

extern "C" char *cspell_suggest(cspell_checker *c, const char *word) {
    if (!c || !word) return nullptr;
    std::wstring w = widen(word);
    IEnumString *e = nullptr;
    if (FAILED(c->checker->Suggest(w.c_str(), &e))) return nullptr;
    return pack(strings(e));
}

extern "C" void cspell_add(cspell_checker *c, const char *word) {
    if (!c || !word) return;
    std::wstring w = widen(word);
    // Add() writes the user's dictionary (AppKit's learnWord is persistent), which the
    // checker may not consult until later; Ignore() accepts the word in this session at once.
    c->checker->Add(w.c_str());
    c->checker->Ignore(w.c_str());
}

extern "C" void cspell_free(char *list) { free(list); }
#endif
