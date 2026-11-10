// C interface over the Text Services Framework (TSF) for one window's text input (ADR-0016).
//
// A document is a text store (ITextStoreACP) plus a TSF context: the input method (Microsoft
// IME for Japanese, Chinese or Korean, or any text service) reads the text through the store,
// edits it under locks, and draws its composition through ITfContextOwnerCompositionSink. The
// store does not keep text of its own: every read, edit and selection goes through the
// callbacks, which the window answers from its text view (the platform text input seam).
// Compositions reach the view as marked text, so the view draws the underline itself.
//
// Everything runs on the UI thread (an STA); callbacks arrive there too.
#ifndef CTS_H
#define CTS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CTSDocument CTSDocument;

typedef struct CTSCallbacks {
    void *user;
    /// Length of the document in UTF-16 code units.
    int32_t (*length)(void *user);
    /// Copies up to `count` UTF-16 units starting at `start`; returns the number copied.
    int32_t (*read)(void *user, int32_t start, int32_t count, uint16_t *out);
    /// The selection (caret when `count` is 0) in UTF-16 units.
    void (*selection)(void *user, int32_t *start, int32_t *count);
    void (*setSelection)(void *user, int32_t start, int32_t count);
    /// Replaces `count` units at `start` with `text`. `marked` is non-zero while the text is part
    /// of the input method's composition; the view then keeps it as marked text. On return the
    /// view has moved the selection to the end of the inserted text.
    void (*replace)(void *user, int32_t start, int32_t count, const uint16_t *text, int32_t textCount, int32_t marked);
    /// The composition covers `count` units at `start` (marked text).
    void (*markRange)(void *user, int32_t start, int32_t count);
    /// The composition ended: its text becomes ordinary text.
    void (*endComposition)(void *user);
    /// Screen rectangle of the units `start`..`start+count` as left, top, right, bottom in pixels.
    /// Returns 0 when there is no layout for them yet.
    int32_t (*rect)(void *user, int32_t start, int32_t count, int32_t *ltrb);
    /// The window's HWND for the text store's GetWnd.
    void *(*window)(void *user);
    /// The input method's candidate list changed to `count` entries (0 when it closed).
    void (*candidates)(void *user, int32_t count);
} CTSCallbacks;

/// Creates the document (thread manager, text store, context) for the window `hwnd`.
/// Returns NULL when TSF is not available.
CTSDocument *cts_document_create(const CTSCallbacks *callbacks, void *hwnd);
void cts_document_destroy(CTSDocument *document);

/// The document gets (1) or loses (0) keyboard focus; the input method follows it.
void cts_document_set_focus(CTSDocument *document, int focused);
/// The text or selection changed outside an edit session: TSF refreshes its view of them.
void cts_document_notify_change(CTSDocument *document, int32_t start, int32_t oldCount, int32_t newCount);
void cts_document_notify_selection(CTSDocument *document);

/// The input method's open state (Japanese: on = kana input, off = direct input).
void cts_document_set_ime_open(CTSDocument *document, int open);
int cts_document_ime_open(CTSDocument *document);
/// Number of candidates the input method currently lists (0 when none).
int cts_document_candidate_count(CTSDocument *document);
/// Reconversion: the input method converts the selected text again. Returns an HRESULT.
int32_t cts_document_reconvert(CTSDocument *document);
/// Whether a composition is active (TSF owns the marked text).
int cts_document_composing(CTSDocument *document);

#ifdef __cplusplus
}
#endif

#endif /* CTS_H */
