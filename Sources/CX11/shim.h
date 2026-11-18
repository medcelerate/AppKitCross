// Xlib for the Linux window backend.
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <X11/cursorfont.h>
#include <X11/extensions/XInput2.h>

// MARK: - Input methods (XIM, ADR-0047)
//
// XIM's setup calls are variadic (XCreateIC, XGetIMValues, XVaCreateNestedList), which Swift
// cannot call, so these inline helpers wrap them. On-the-spot preedit (XIMPreeditCallbacks)
// reaches Swift through the handler table, whose XIMCallback slots must live as long as the
// input context (the window owns the table).
#include <X11/Xlib.h>
#include <locale.h>
#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>

typedef struct AppKitXIMHandlers {
    void *user;
    void (*start)(void *user);
    void (*done)(void *user);
    /// `length` characters at `first` change. `kind` 0: deleted; 1: replaced by `text`
    /// (`count` UCS-4 characters, one `feedback` each); 2: only their feedback changes.
    void (*draw)(void *user, int caret, int first, int length, int kind, const uint32_t *text, int count, const unsigned long *feedback);
    /// Moves the caret (`direction` is an XIMCaretDirection); returns the new position.
    int (*caret)(void *user, int position, int direction);
    XIMCallback startCallback, doneCallback, drawCallback, caretCallback;
} AppKitXIMHandlers;

static int appkitwin_xim_start(XIC ic, XPointer client, XPointer call) {
    (void)ic; (void)call;
    AppKitXIMHandlers *h = (AppKitXIMHandlers *)client;
    if (h && h->start) h->start(h->user);
    return -1;      // no limit on the preedit's length
}

static void appkitwin_xim_done(XIC ic, XPointer client, XPointer call) {
    (void)ic; (void)call;
    AppKitXIMHandlers *h = (AppKitXIMHandlers *)client;
    if (h && h->done) h->done(h->user);
}

static void appkitwin_xim_draw(XIC ic, XPointer client, XPointer call) {
    (void)ic;
    AppKitXIMHandlers *h = (AppKitXIMHandlers *)client;
    XIMPreeditDrawCallbackStruct *d = (XIMPreeditDrawCallbackStruct *)call;
    if (!h || !h->draw || !d) return;
    uint32_t *text = NULL;
    int count = 0, kind = 0;
    const unsigned long *feedback = NULL;
    if (d->text) {
        feedback = d->text->feedback;
        if (d->text->encoding_is_wchar && d->text->string.wide_char) {
            count = d->text->length;
            text = (uint32_t *)malloc(sizeof(uint32_t) * (size_t)(count + 1));
            for (int i = 0; text && i < count; i++) text[i] = (uint32_t)d->text->string.wide_char[i];
            kind = 1;
        } else if (!d->text->encoding_is_wchar && d->text->string.multi_byte) {
            size_t n = mbstowcs(NULL, d->text->string.multi_byte, 0);
            if (n != (size_t)-1) {
                wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (n + 1));
                text = (uint32_t *)malloc(sizeof(uint32_t) * (n + 1));
                if (w && text) {
                    mbstowcs(w, d->text->string.multi_byte, n + 1);
                    for (size_t i = 0; i < n; i++) text[i] = (uint32_t)w[i];
                    count = (int)n;
                    kind = 1;
                }
                free(w);
            }
        } else {
            count = d->text->length;
            kind = 2;
        }
    }
    h->draw(h->user, d->caret, d->chg_first, d->chg_length, kind, text, count, feedback);
    free(text);
}

static void appkitwin_xim_caret(XIC ic, XPointer client, XPointer call) {
    (void)ic;
    AppKitXIMHandlers *h = (AppKitXIMHandlers *)client;
    XIMPreeditCaretCallbackStruct *c = (XIMPreeditCaretCallbackStruct *)call;
    if (!h || !h->caret || !c) return;
    c->position = h->caret(h->user, c->position, (int)c->direction);
}

/// Opens the input method of the user's locale (XMODIFIERS names the server: ibus, fcitx).
/// Xlib needs a UTF-8 LC_CTYPE for non-Latin text; without a server Xlib's own input method
/// still composes dead keys. Returns NULL when there is none at all.
static XIM appkitwin_xim_open(Display *display) {
    const char *loc = setlocale(LC_CTYPE, "");
    if (!loc || !XSupportsLocale()) setlocale(LC_CTYPE, "C.UTF-8");
    if (!XSetLocaleModifiers("")) XSetLocaleModifiers("@im=none");
    XIM im = XOpenIM(display, NULL, NULL, NULL);
    if (!im) {
        XSetLocaleModifiers("@im=none");
        im = XOpenIM(display, NULL, NULL, NULL);
    }
    return im;
}

/// Makes the window's input context: on-the-spot preedit when the input method offers it
/// (`*onTheSpot` = 1), else root-window preedit (the input method draws it, as for dead keys).
static XIC appkitwin_xic_create(XIM im, Window window, AppKitXIMHandlers *h, int *onTheSpot) {
    XIMStyles *styles = NULL;
    int callbacks = 0;
    if (XGetIMValues(im, XNQueryInputStyle, &styles, NULL) == NULL && styles) {
        for (int i = 0; i < styles->count_styles; i++) {
            if (styles->supported_styles[i] == (XIMPreeditCallbacks | XIMStatusNothing)) callbacks = 1;
        }
        XFree(styles);
    }
    XIC ic = NULL;
    if (callbacks && h) {
        h->startCallback.client_data = (XPointer)h; h->startCallback.callback = (XIMProc)appkitwin_xim_start;
        h->doneCallback.client_data = (XPointer)h; h->doneCallback.callback = (XIMProc)appkitwin_xim_done;
        h->drawCallback.client_data = (XPointer)h; h->drawCallback.callback = (XIMProc)appkitwin_xim_draw;
        h->caretCallback.client_data = (XPointer)h; h->caretCallback.callback = (XIMProc)appkitwin_xim_caret;
        XVaNestedList preedit = XVaCreateNestedList(0, XNPreeditStartCallback, &h->startCallback, XNPreeditDoneCallback, &h->doneCallback,
                                                    XNPreeditDrawCallback, &h->drawCallback, XNPreeditCaretCallback, &h->caretCallback, NULL);
        ic = XCreateIC(im, XNInputStyle, XIMPreeditCallbacks | XIMStatusNothing, XNClientWindow, window, XNFocusWindow, window,
                       XNPreeditAttributes, preedit, NULL);
        XFree(preedit);
    }
    if (onTheSpot) *onTheSpot = ic != NULL;
    if (!ic) ic = XCreateIC(im, XNInputStyle, XIMPreeditNothing | XIMStatusNothing, XNClientWindow, window, XNFocusWindow, window, NULL);
    return ic;
}

/// The events the input context needs on the window (XNFilterEvents).
static long appkitwin_xic_filter_events(XIC ic) {
    long mask = 0;
    XGetICValues(ic, XNFilterEvents, &mask, NULL);
    return mask;
}

/// Where the candidate window goes: the caret's baseline in window pixels.
static void appkitwin_xic_set_spot(XIC ic, int x, int y) {
    XPoint spot;
    spot.x = (short)x;
    spot.y = (short)y;
    XVaNestedList list = XVaCreateNestedList(0, XNSpotLocation, &spot, NULL);
    XSetICValues(ic, XNPreeditAttributes, list, NULL);
    XFree(list);
}

/// Drops the input method's preedit (its committed part, if any, is discarded).
static void appkitwin_xic_reset(XIC ic) {
    char *s = Xutf8ResetIC(ic);
    if (s) XFree(s);
}
