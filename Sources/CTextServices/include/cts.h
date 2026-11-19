// C interface over the Text Services Framework (TSF) for a window's text input (ADR-0047).
//
// A document is a text store (ITextStoreACP) plus a TSF context in its own document
// manager. The store keeps a copy of the text around the focused text view's selection,
// which the window hands it with `cts_document_sync`. The input method (Microsoft IME for
// Japanese, Chinese or Korean, or any text service) reads and edits that copy under locks;
// when a lock in which it edited ends, the store reports the new text, selection,
// composition and clauses through `edited`, and the window turns them into the
// NSTextInputClient calls (marked text, insertText). The view then draws the composition.
//
// One thread manager serves every document of the UI thread. Everything runs on that thread
// (an STA); callbacks arrive there too, never while the store is locked.
#ifndef CTS_H
#define CTS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CTSDocument CTSDocument;

/// One clause of the composition: `start`/`length` in the store, `thick` when the input
/// method shows it as the clause being converted (TF_ATTR_TARGET_*) or with a bold line.
typedef struct CTSClause {
    int32_t start;
    int32_t length;
    int32_t thick;
} CTSClause;

typedef struct CTSCallbacks {
    void *user;
    /// Before the store grants a lock: the window syncs the store if the view changed.
    void (*refresh)(void *user);
    /// After a lock in which the input method edited: the store's text (UTF-16, `length`
    /// units), selection, composition (`compositionStart` -1 when none) and its clauses.
    void (*edited)(void *user, const uint16_t *text, int32_t length, int32_t selectionStart, int32_t selectionEnd,
                   int32_t compositionStart, int32_t compositionLength, const CTSClause *clauses, int32_t clauseCount);
    /// Screen rectangle of the store's units `start`..`start+count` as left, top, right,
    /// bottom in pixels. Returns 0 when there is no layout for them.
    int32_t (*rect)(void *user, int32_t start, int32_t count, int32_t *ltrb);
    /// The input method's candidate list opened with `count` entries, changed, or closed (0).
    void (*candidates)(void *user, int32_t count);
} CTSCallbacks;

/// Creates the document for the window `hwnd` (and the thread's thread manager on first use).
/// Returns NULL when TSF is not available; `*hresult` says why.
CTSDocument *cts_document_create(const CTSCallbacks *callbacks, void *hwnd, int32_t *hresult);
void cts_document_destroy(CTSDocument *document);

/// The document gets (1) or loses (0) the keyboard focus. Losing it focuses an empty
/// document manager, which turns the input method off for the window.
void cts_document_set_focus(CTSDocument *document, int focused);
/// Replaces the store's copy of the text and selection with the view's; the input method
/// is told what changed. Deferred until the lock ends when called inside one.
void cts_document_sync(CTSDocument *document, const uint16_t *text, int32_t length, int32_t selectionStart, int32_t selectionEnd);
/// The caret or text moved on screen: the input method reads the rectangles again.
void cts_document_layout_changed(CTSDocument *document);
/// Ends the composition: the input method keeps its text as committed text.
void cts_document_end_composition(CTSDocument *document);
/// Whether a composition is active.
int cts_document_composing(CTSDocument *document);
/// Number of candidates the input method lists (0 when none).
int cts_document_candidate_count(CTSDocument *document);

/// The input method's open state (Japanese: on = kana input, off = direct input).
void cts_document_set_ime_open(CTSDocument *document, int open);
int cts_document_ime_open(CTSDocument *document);
/// The input mode's conversion bits (TF_CONVERSIONMODE_*): 0x1 native (kana), 0x10 roman.
void cts_document_set_conversion(CTSDocument *document, int32_t mode);
int32_t cts_document_conversion(CTSDocument *document);

/// Offers a key message to the text services before the window translates it; returns 1
/// when an input method took it (the window must not act on it). `message` is WM_KEYDOWN
/// or WM_KEYUP.
int cts_process_key(uint32_t message, uint64_t wParam, int64_t lParam);

/// Makes the Microsoft IME (Japanese) this process's active text service (a test hook for
/// machines where the input language cannot be switched by hand). Returns an HRESULT.
int32_t cts_activate_microsoft_ime_jp(void);

/// 1: one stderr line per store call and lock (`[textinput] tsf ...`).
void cts_set_trace(int on);

#ifdef __cplusplus
}
#endif

#endif /* CTS_H */
