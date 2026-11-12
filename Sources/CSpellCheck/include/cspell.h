// C seam over the platform spell checkers (ADR-0030): the Windows Spell Checking API
// (ISpellCheckerFactory, cspell_win.cpp) and hunspell on Linux (loaded with dlopen, so the
// library and its dictionaries are optional at run time; cspell_hunspell.c).
// Strings are UTF-8. Lists come back NUL-separated and end with an empty string (a double
// NUL); free them with cspell_free.
#ifndef CSPELL_H
#define CSPELL_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cspell_checker cspell_checker;

/// "windows", "hunspell", or "none" when no checker can be loaded.
const char *cspell_backend(void);
/// Languages with a dictionary ("en-US", "de-DE", ...), or NULL.
char *cspell_languages(void);
/// A checker for `language` (BCP 47 or POSIX form), or NULL when it has no dictionary.
cspell_checker *cspell_open(const char *language);
void cspell_close(cspell_checker *checker);
/// 1 when the word is spelt correctly, 0 when it is not, -1 on failure.
int cspell_check(cspell_checker *checker, const char *word);
/// Suggestions for a misspelt word, best first, or NULL.
char *cspell_suggest(cspell_checker *checker, const char *word);
/// Adds a word to the checker's session dictionary.
void cspell_add(cspell_checker *checker, const char *word);
void cspell_free(char *list);

#ifdef __cplusplus
}
#endif
#endif
