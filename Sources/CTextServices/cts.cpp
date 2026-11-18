// Text Services Framework for the window's text input (ADR-0047). See include/cts.h.
//
// The store keeps its own copy of the text (as Chromium's and Firefox's TSF stores do): the
// input method edits the copy under locks, and only when a lock ends are the edits handed
// to the window, which applies them to the view as marked or committed text and syncs the
// copy back. Lock requests that arrive while a lock is held (or while the store reports) are
// queued and granted afterwards. Clause underlines come from the composition's display
// attributes (GUID_PROP_ATTRIBUTE) read in ITfTextEditSink::OnEndEdit.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ole2.h>
#include <olectl.h>
#include <msctf.h>
#include <textstor.h>
#include <ctffunc.h>
#include <atomic>
#include <cstdio>
#include <cstdarg>
#include <string>
#include <vector>

#include "cts.h"

namespace {

bool g_trace = false;

void trace(const char *format, ...) {
    if (!g_trace) return;
    va_list args;
    va_start(args, format);
    std::fputs("[textinput] tsf ", stderr);
    std::vfprintf(stderr, format, args);
    std::fputc('\n', stderr);
    std::fflush(stderr);
    va_end(args);
}

// MARK: - The thread's thread manager (shared by every document)

struct Thread {
    ITfThreadMgr *threadMgr = nullptr;
    ITfKeystrokeMgr *keys = nullptr;
    ITfDocumentMgr *disabled = nullptr;     // focused when no text view has the focus
    TfClientId client = TF_CLIENTID_NULL;
    int documents = 0;
    int focused = 0;                        // documents with the focus (0 or 1)
};
Thread g_thread;

HRESULT threadAcquire() {
    if (g_thread.threadMgr) { g_thread.documents++; return S_OK; }
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    (void)hr;   // S_FALSE / RPC_E_CHANGED_MODE: COM is already up on this thread
    hr = CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr, reinterpret_cast<void **>(&g_thread.threadMgr));
    if (FAILED(hr) || !g_thread.threadMgr) { g_thread.threadMgr = nullptr; return FAILED(hr) ? hr : E_FAIL; }
    hr = g_thread.threadMgr->Activate(&g_thread.client);
    if (FAILED(hr)) { g_thread.threadMgr->Release(); g_thread.threadMgr = nullptr; return hr; }
    g_thread.threadMgr->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&g_thread.keys));
    g_thread.threadMgr->CreateDocumentMgr(&g_thread.disabled);
    g_thread.documents = 1;
    trace("thread manager activated, client %lu", (unsigned long)g_thread.client);
    return S_OK;
}

void threadRelease() {
    if (--g_thread.documents > 0 || !g_thread.threadMgr) return;
    g_thread.threadMgr->SetFocus(nullptr);
    if (g_thread.disabled) { g_thread.disabled->Release(); g_thread.disabled = nullptr; }
    if (g_thread.keys) { g_thread.keys->Release(); g_thread.keys = nullptr; }
    g_thread.threadMgr->Deactivate();
    g_thread.threadMgr->Release();
    g_thread.threadMgr = nullptr;
    g_thread.client = TF_CLIENTID_NULL;
    trace("thread manager deactivated");
}

struct Document;

// MARK: - Candidate list sink (thread manager)

class UIElementSink final : public ITfUIElementSink {
public:
    explicit UIElementSink(Document *doc) : doc_(doc) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfUIElementSink)) { *ppv = static_cast<ITfUIElementSink *>(this); AddRef(); return S_OK; }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG r = --refs_; if (r == 0) delete this; return r; }
    HRESULT STDMETHODCALLTYPE BeginUIElement(DWORD id, BOOL *show) override;
    HRESULT STDMETHODCALLTYPE UpdateUIElement(DWORD id) override;
    HRESULT STDMETHODCALLTYPE EndUIElement(DWORD id) override;
    void detach() { doc_ = nullptr; }
private:
    void count(DWORD id);
    std::atomic<ULONG> refs_{1};
    Document *doc_;
};

// MARK: - Text store

class TextStore final : public ITextStoreACP, public ITfContextOwnerCompositionSink, public ITfTextEditSink {
public:
    explicit TextStore(Document *doc) : doc_(doc) {}

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITextStoreACP)) *ppv = static_cast<ITextStoreACP *>(this);
        else if (IsEqualIID(riid, IID_ITfContextOwnerCompositionSink)) *ppv = static_cast<ITfContextOwnerCompositionSink *>(this);
        else if (IsEqualIID(riid, IID_ITfTextEditSink)) *ppv = static_cast<ITfTextEditSink *>(this);
        else { *ppv = nullptr; return E_NOINTERFACE; }
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG r = --refs_; if (r == 0) delete this; return r; }

    // ITextStoreACP
    HRESULT STDMETHODCALLTYPE AdviseSink(REFIID riid, IUnknown *punk, DWORD mask) override;
    HRESULT STDMETHODCALLTYPE UnadviseSink(IUnknown *punk) override;
    HRESULT STDMETHODCALLTYPE RequestLock(DWORD flags, HRESULT *session) override;
    HRESULT STDMETHODCALLTYPE GetStatus(TS_STATUS *status) override;
    HRESULT STDMETHODCALLTYPE QueryInsert(LONG testStart, LONG testEnd, ULONG count, LONG *resultStart, LONG *resultEnd) override;
    HRESULT STDMETHODCALLTYPE GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP *selection, ULONG *fetched) override;
    HRESULT STDMETHODCALLTYPE SetSelection(ULONG count, const TS_SELECTION_ACP *selection) override;
    HRESULT STDMETHODCALLTYPE GetText(LONG start, LONG end, WCHAR *plain, ULONG plainRequested, ULONG *plainReturned,
                                      TS_RUNINFO *runs, ULONG runsRequested, ULONG *runsReturned, LONG *next) override;
    HRESULT STDMETHODCALLTYPE SetText(DWORD flags, LONG start, LONG end, const WCHAR *text, ULONG count, TS_TEXTCHANGE *change) override;
    HRESULT STDMETHODCALLTYPE GetFormattedText(LONG start, LONG end, IDataObject **data) override;
    HRESULT STDMETHODCALLTYPE GetEmbedded(LONG pos, REFGUID service, REFIID riid, IUnknown **unk) override;
    HRESULT STDMETHODCALLTYPE QueryInsertEmbedded(const GUID *service, const FORMATETC *format, BOOL *insertable) override;
    HRESULT STDMETHODCALLTYPE InsertEmbedded(DWORD flags, LONG start, LONG end, IDataObject *data, TS_TEXTCHANGE *change) override;
    HRESULT STDMETHODCALLTYPE InsertTextAtSelection(DWORD flags, const WCHAR *text, ULONG count, LONG *start, LONG *end, TS_TEXTCHANGE *change) override;
    HRESULT STDMETHODCALLTYPE InsertEmbeddedAtSelection(DWORD flags, IDataObject *data, LONG *start, LONG *end, TS_TEXTCHANGE *change) override;
    HRESULT STDMETHODCALLTYPE RequestSupportedAttrs(DWORD flags, ULONG count, const TS_ATTRID *filter) override;
    HRESULT STDMETHODCALLTYPE RequestAttrsAtPosition(LONG pos, ULONG count, const TS_ATTRID *filter, DWORD flags) override;
    HRESULT STDMETHODCALLTYPE RequestAttrsTransitioningAtPosition(LONG pos, ULONG count, const TS_ATTRID *filter, DWORD flags) override;
    HRESULT STDMETHODCALLTYPE FindNextAttrTransition(LONG start, LONG end, ULONG count, const TS_ATTRID *filter, DWORD flags, LONG *next, BOOL *found, LONG *overlap) override;
    HRESULT STDMETHODCALLTYPE RetrieveRequestedAttrs(ULONG capacity, TS_ATTRVAL *values, ULONG *returned) override;
    HRESULT STDMETHODCALLTYPE GetEndACP(LONG *end) override;
    HRESULT STDMETHODCALLTYPE GetActiveView(TsViewCookie *view) override;
    HRESULT STDMETHODCALLTYPE GetACPFromPoint(TsViewCookie view, const POINT *screen, DWORD flags, LONG *acp) override;
    HRESULT STDMETHODCALLTYPE GetTextExt(TsViewCookie view, LONG start, LONG end, RECT *rect, BOOL *clipped) override;
    HRESULT STDMETHODCALLTYPE GetScreenExt(TsViewCookie view, RECT *rect) override;
    HRESULT STDMETHODCALLTYPE GetWnd(TsViewCookie view, HWND *wnd) override;

    // ITfContextOwnerCompositionSink
    HRESULT STDMETHODCALLTYPE OnStartComposition(ITfCompositionView *view, BOOL *ok) override;
    HRESULT STDMETHODCALLTYPE OnUpdateComposition(ITfCompositionView *view, ITfRange *range) override;
    HRESULT STDMETHODCALLTYPE OnEndComposition(ITfCompositionView *view) override;

    // ITfTextEditSink
    HRESULT STDMETHODCALLTYPE OnEndEdit(ITfContext *context, TfEditCookie readOnly, ITfEditRecord *record) override;

    // Window side
    void sync(const uint16_t *text, int32_t length, int32_t selStart, int32_t selEnd);
    void layoutChanged();
    bool composing() const { return composition_ != nullptr; }
    void detach();

private:
    HRESULT grant(DWORD flags);
    void report();
    void replace(LONG start, LONG end, const WCHAR *text, ULONG count, TS_TEXTCHANGE *change);
    bool readWriteLocked() const { return (lock_ & TS_LF_READWRITE) == TS_LF_READWRITE; }
    LONG length() const { return static_cast<LONG>(text_.size()); }
    void compositionExtent(LONG *start, LONG *length) const;

    std::atomic<ULONG> refs_{1};
    Document *doc_;
    ITextStoreACPSink *sink_ = nullptr;
    DWORD sinkMask_ = 0;
    DWORD lock_ = 0;           // the lock being granted (TS_LF_READ / TS_LF_READWRITE)
    DWORD pending_ = 0;        // asynchronous requests made while locked or busy
    bool busy_ = false;        // inside RequestLock (refresh, grants, report)
    bool edited_ = false;      // the input method changed text, selection or composition
    std::u16string text_;
    LONG selStart_ = 0, selEnd_ = 0;
    TsActiveSelEnd activeEnd_ = TS_AE_END;
    ITfCompositionView *composition_ = nullptr;
    std::vector<CTSClause> clauses_;
    bool hasPendingSync_ = false;
    std::u16string pendingText_;
    LONG pendingSelStart_ = 0, pendingSelEnd_ = 0;
};

// MARK: - Document

struct Document {
    CTSCallbacks cb{};
    HWND hwnd = nullptr;
    ITfDocumentMgr *documentMgr = nullptr;
    ITfContext *context = nullptr;
    TextStore *store = nullptr;
    UIElementSink *uiSink = nullptr;
    DWORD uiCookie = TF_INVALID_COOKIE;
    DWORD editCookie = TF_INVALID_COOKIE;
    ITfCategoryMgr *categories = nullptr;
    ITfDisplayAttributeMgr *attributes = nullptr;
    int candidates = 0;
    bool focused = false;
    bool threadAcquired = false;

    ~Document() {
        if (context && editCookie != TF_INVALID_COOKIE) {
            ITfSource *source = nullptr;
            if (SUCCEEDED(context->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&source)))) {
                source->UnadviseSink(editCookie);
                source->Release();
            }
        }
        if (g_thread.threadMgr && uiCookie != TF_INVALID_COOKIE) {
            ITfSource *source = nullptr;
            if (SUCCEEDED(g_thread.threadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&source)))) {
                source->UnadviseSink(uiCookie);
                source->Release();
            }
        }
        if (documentMgr) documentMgr->Pop(TF_POPF_ALL);
        if (context) context->Release();
        if (documentMgr) documentMgr->Release();
        if (uiSink) { uiSink->detach(); uiSink->Release(); }
        if (store) { store->detach(); store->Release(); }
        if (categories) categories->Release();
        if (attributes) attributes->Release();
        if (threadAcquired) threadRelease();
    }
};

// MARK: - Candidate list

void UIElementSink::count(DWORD id) {
    if (!doc_ || !doc_->focused || !g_thread.threadMgr) return;
    ITfUIElementMgr *mgr = nullptr;
    if (FAILED(g_thread.threadMgr->QueryInterface(IID_ITfUIElementMgr, reinterpret_cast<void **>(&mgr))) || !mgr) return;
    ITfUIElement *element = nullptr;
    if (SUCCEEDED(mgr->GetUIElement(id, &element)) && element) {
        ITfCandidateListUIElement *list = nullptr;
        if (SUCCEEDED(element->QueryInterface(IID_ITfCandidateListUIElement, reinterpret_cast<void **>(&list))) && list) {
            UINT n = 0;
            if (SUCCEEDED(list->GetCount(&n))) {
                doc_->candidates = static_cast<int>(n);
                trace("candidate list %u entries", n);
                if (doc_->cb.candidates) doc_->cb.candidates(doc_->cb.user, doc_->candidates);
            }
            list->Release();
        }
        element->Release();
    }
    mgr->Release();
}

HRESULT STDMETHODCALLTYPE UIElementSink::BeginUIElement(DWORD id, BOOL *show) {
    if (show) *show = TRUE;     // the input method draws its candidate list, placed by GetTextExt
    count(id);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE UIElementSink::UpdateUIElement(DWORD id) {
    count(id);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE UIElementSink::EndUIElement(DWORD) {
    if (!doc_) return S_OK;
    if (doc_->candidates != 0) trace("candidate list closed");
    doc_->candidates = 0;
    if (doc_->cb.candidates) doc_->cb.candidates(doc_->cb.user, 0);
    return S_OK;
}

// MARK: - Store: sinks and locks

HRESULT STDMETHODCALLTYPE TextStore::AdviseSink(REFIID riid, IUnknown *punk, DWORD mask) {
    if (!IsEqualIID(riid, IID_ITextStoreACPSink) || !punk) return E_INVALIDARG;
    if (sink_) {
        // The same sink again only changes its mask.
        IUnknown *a = nullptr, *b = nullptr;
        punk->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&a));
        sink_->QueryInterface(IID_IUnknown, reinterpret_cast<void **>(&b));
        bool same = a == b;
        if (a) a->Release();
        if (b) b->Release();
        if (!same) return CONNECT_E_ADVISELIMIT;
        sinkMask_ = mask;
        return S_OK;
    }
    HRESULT hr = punk->QueryInterface(IID_ITextStoreACPSink, reinterpret_cast<void **>(&sink_));
    if (FAILED(hr)) { sink_ = nullptr; return hr; }
    sinkMask_ = mask;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::UnadviseSink(IUnknown *) {
    if (sink_) { sink_->Release(); sink_ = nullptr; }
    sinkMask_ = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::RequestLock(DWORD flags, HRESULT *session) {
    if (!session) return E_INVALIDARG;
    if (!sink_) { *session = E_FAIL; return E_UNEXPECTED; }
    DWORD kind = flags & TS_LF_READWRITE;
    if (lock_ != 0 || busy_) {
        if (flags & TS_LF_SYNC) { *session = TS_E_SYNCHRONOUS; return S_OK; }
        pending_ |= kind;
        *session = TS_S_ASYNC;
        return S_OK;
    }
    busy_ = true;
    AddRef();
    // The view may have changed since the last sync (a click, typing): the window brings
    // the store up to date before the input method reads it.
    if (doc_ && doc_->cb.refresh) doc_->cb.refresh(doc_->cb.user);
    *session = grant(kind);
    while (pending_ != 0 && sink_) {
        DWORD next = (pending_ & TS_LF_READWRITE) == TS_LF_READWRITE ? TS_LF_READWRITE : TS_LF_READ;
        pending_ = 0;
        grant(next);
    }
    busy_ = false;
    Release();
    return S_OK;
}

HRESULT TextStore::grant(DWORD flags) {
    if (!sink_) return E_FAIL;
    lock_ = flags;
    HRESULT hr = sink_->OnLockGranted(flags);
    lock_ = 0;
    if (hasPendingSync_) {
        hasPendingSync_ = false;
        std::u16string t = pendingText_;
        sync(reinterpret_cast<const uint16_t *>(t.data()), static_cast<int32_t>(t.size()), pendingSelStart_, pendingSelEnd_);
    }
    if (edited_) { edited_ = false; report(); }
    return hr;
}

void TextStore::compositionExtent(LONG *start, LONG *length) const {
    *start = -1;
    *length = 0;
    if (!composition_) return;
    ITfRange *range = nullptr;
    if (SUCCEEDED(composition_->GetRange(&range)) && range) {
        ITfRangeACP *acp = nullptr;
        if (SUCCEEDED(range->QueryInterface(IID_ITfRangeACP, reinterpret_cast<void **>(&acp))) && acp) {
            acp->GetExtent(start, length);
            acp->Release();
        }
        range->Release();
    }
}

void TextStore::report() {
    if (!doc_ || !doc_->cb.edited) return;
    LONG cs = -1, cl = 0;
    compositionExtent(&cs, &cl);
    trace("edited: %ld units, selection %ld..%ld, composition %ld+%ld, %zu clauses", length(), selStart_, selEnd_, cs, cl, clauses_.size());
    std::u16string copy = text_;
    std::vector<CTSClause> clauses = composition_ ? clauses_ : std::vector<CTSClause>();
    doc_->cb.edited(doc_->cb.user, reinterpret_cast<const uint16_t *>(copy.data()), static_cast<int32_t>(copy.size()),
                    selStart_, selEnd_, cs, cl, clauses.empty() ? nullptr : clauses.data(), static_cast<int32_t>(clauses.size()));
}

HRESULT STDMETHODCALLTYPE TextStore::GetStatus(TS_STATUS *status) {
    if (!status) return E_INVALIDARG;
    status->dwDynamicFlags = 0;
    status->dwStaticFlags = TS_SS_NOHIDDENTEXT;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::QueryInsert(LONG testStart, LONG testEnd, ULONG, LONG *resultStart, LONG *resultEnd) {
    if (!resultStart || !resultEnd) return E_INVALIDARG;
    if (testStart < 0 || testStart > testEnd || testEnd > length()) return E_INVALIDARG;
    *resultStart = testStart;
    *resultEnd = testEnd;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP *selection, ULONG *fetched) {
    if (!selection || !fetched) return E_INVALIDARG;
    *fetched = 0;
    if (lock_ == 0) return TS_E_NOLOCK;
    if (index != TF_DEFAULT_SELECTION && index != 0) return TS_E_NOSELECTION;
    if (count == 0) return S_OK;
    selection[0].acpStart = selStart_;
    selection[0].acpEnd = selEnd_;
    selection[0].style.ase = activeEnd_;
    selection[0].style.fInterimChar = FALSE;
    *fetched = 1;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::SetSelection(ULONG count, const TS_SELECTION_ACP *selection) {
    if (!selection || count == 0) return E_INVALIDARG;
    if (!readWriteLocked()) return TS_E_NOLOCK;
    LONG start = selection[0].acpStart, end = selection[0].acpEnd;
    if (start < 0 || end < start || end > length()) return TS_E_INVALIDPOS;
    if (start != selStart_ || end != selEnd_) edited_ = true;
    selStart_ = start;
    selEnd_ = end;
    activeEnd_ = selection[0].style.ase;
    trace("SetSelection %ld..%ld", start, end);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetText(LONG start, LONG end, WCHAR *plain, ULONG plainRequested, ULONG *plainReturned,
                                             TS_RUNINFO *runs, ULONG runsRequested, ULONG *runsReturned, LONG *next) {
    if (lock_ == 0) return TS_E_NOLOCK;
    if (plainReturned) *plainReturned = 0;
    if (runsReturned) *runsReturned = 0;
    if (next) *next = start;
    LONG n = length();
    if (start < 0 || start > n) return TS_E_INVALIDPOS;
    if (end == -1 || end > n) end = n;
    if (end < start) return TS_E_INVALIDPOS;
    LONG wanted = end - start;
    if (plain) {
        if (static_cast<ULONG>(wanted) > plainRequested) wanted = static_cast<LONG>(plainRequested);
    } else if (runsRequested == 0) {
        wanted = 0;
    }
    if (plain && wanted > 0) {
        for (LONG i = 0; i < wanted; i++) plain[i] = static_cast<WCHAR>(text_[static_cast<size_t>(start + i)]);
    }
    if (plainReturned) *plainReturned = plain ? static_cast<ULONG>(wanted) : 0;
    if (runs && runsRequested > 0 && wanted > 0) {
        runs[0].uCount = static_cast<ULONG>(wanted);
        runs[0].type = TS_RT_PLAIN;
        if (runsReturned) *runsReturned = 1;
    }
    if (next) *next = start + wanted;
    return S_OK;
}

void TextStore::replace(LONG start, LONG end, const WCHAR *text, ULONG count, TS_TEXTCHANGE *change) {
    std::u16string inserted;
    if (text && count > 0) inserted.assign(reinterpret_cast<const char16_t *>(text), count);
    text_.replace(static_cast<size_t>(start), static_cast<size_t>(end - start), inserted);
    LONG newEnd = start + static_cast<LONG>(count);
    selStart_ = newEnd;
    selEnd_ = newEnd;
    activeEnd_ = TS_AE_END;
    edited_ = true;
    if (change) { change->acpStart = start; change->acpOldEnd = end; change->acpNewEnd = newEnd; }
}

HRESULT STDMETHODCALLTYPE TextStore::SetText(DWORD, LONG start, LONG end, const WCHAR *text, ULONG count, TS_TEXTCHANGE *change) {
    if (!readWriteLocked()) return TS_E_NOLOCK;
    if (start < 0 || end < start || end > length()) return TS_E_INVALIDPOS;
    trace("SetText %ld..%ld, %lu units", start, end, (unsigned long)count);
    replace(start, end, text, count, change);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::InsertTextAtSelection(DWORD flags, const WCHAR *text, ULONG count, LONG *start, LONG *end, TS_TEXTCHANGE *change) {
    LONG s = selStart_, e = selEnd_;
    if (flags & TF_IAS_QUERYONLY) {
        if (lock_ == 0) return TS_E_NOLOCK;
        if (start) *start = s;
        if (end) *end = s + static_cast<LONG>(count);
        return S_OK;
    }
    if (!readWriteLocked()) return TS_E_NOLOCK;
    trace("InsertTextAtSelection %ld..%ld, %lu units", s, e, (unsigned long)count);
    replace(s, e, text, count, change);
    if (!(flags & TF_IAS_NOQUERY)) {
        if (start) *start = s;
        if (end) *end = s + static_cast<LONG>(count);
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetFormattedText(LONG, LONG, IDataObject **data) {
    if (data) *data = nullptr;
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE TextStore::GetEmbedded(LONG, REFGUID, REFIID, IUnknown **unk) {
    if (unk) *unk = nullptr;
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE TextStore::QueryInsertEmbedded(const GUID *, const FORMATETC *, BOOL *insertable) {
    if (!insertable) return E_INVALIDARG;
    *insertable = FALSE;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::InsertEmbedded(DWORD, LONG, LONG, IDataObject *, TS_TEXTCHANGE *) { return E_NOTIMPL; }

HRESULT STDMETHODCALLTYPE TextStore::InsertEmbeddedAtSelection(DWORD, IDataObject *, LONG *start, LONG *end, TS_TEXTCHANGE *) {
    if (start) *start = selStart_;
    if (end) *end = selEnd_;
    return E_NOTIMPL;
}

// No text attributes are offered (fonts, input scope): input methods work without them.
HRESULT STDMETHODCALLTYPE TextStore::RequestSupportedAttrs(DWORD, ULONG, const TS_ATTRID *) { return S_OK; }
HRESULT STDMETHODCALLTYPE TextStore::RequestAttrsAtPosition(LONG, ULONG, const TS_ATTRID *, DWORD) { return S_OK; }
HRESULT STDMETHODCALLTYPE TextStore::RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID *, DWORD) { return S_OK; }

HRESULT STDMETHODCALLTYPE TextStore::FindNextAttrTransition(LONG, LONG end, ULONG, const TS_ATTRID *, DWORD, LONG *next, BOOL *found, LONG *overlap) {
    if (next) *next = end;
    if (found) *found = FALSE;
    if (overlap) *overlap = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::RetrieveRequestedAttrs(ULONG, TS_ATTRVAL *, ULONG *returned) {
    if (returned) *returned = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetEndACP(LONG *end) {
    if (!end) return E_INVALIDARG;
    if (lock_ == 0) return TS_E_NOLOCK;
    *end = length();
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetActiveView(TsViewCookie *view) {
    if (!view) return E_INVALIDARG;
    *view = 1;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetACPFromPoint(TsViewCookie, const POINT *, DWORD, LONG *acp) {
    if (acp) *acp = 0;
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE TextStore::GetTextExt(TsViewCookie, LONG start, LONG end, RECT *rect, BOOL *clipped) {
    if (!rect || !clipped) return E_INVALIDARG;
    if (lock_ == 0) return TS_E_NOLOCK;
    *clipped = FALSE;
    if (start < 0 || end < start || start > length()) return TS_E_INVALIDPOS;
    int32_t ltrb[4] = {0, 0, 0, 0};
    if (!doc_ || !doc_->cb.rect || !doc_->cb.rect(doc_->cb.user, start, end - start, ltrb)) return TS_E_NOLAYOUT;
    rect->left = ltrb[0];
    rect->top = ltrb[1];
    rect->right = ltrb[2];
    rect->bottom = ltrb[3];
    trace("GetTextExt %ld..%ld -> (%ld,%ld)-(%ld,%ld)", start, end, rect->left, rect->top, rect->right, rect->bottom);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetScreenExt(TsViewCookie, RECT *rect) {
    if (!rect) return E_INVALIDARG;
    if (!doc_ || !doc_->hwnd || !GetClientRect(doc_->hwnd, rect)) return E_FAIL;
    POINT origin{0, 0};
    ClientToScreen(doc_->hwnd, &origin);
    OffsetRect(rect, origin.x, origin.y);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetWnd(TsViewCookie, HWND *wnd) {
    if (!wnd) return E_INVALIDARG;
    *wnd = doc_ ? doc_->hwnd : nullptr;
    return S_OK;
}

// MARK: - Store: composition

HRESULT STDMETHODCALLTYPE TextStore::OnStartComposition(ITfCompositionView *view, BOOL *ok) {
    if (ok) *ok = TRUE;
    if (composition_) composition_->Release();
    composition_ = view;
    if (composition_) composition_->AddRef();
    clauses_.clear();
    edited_ = true;
    trace("composition started");
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::OnUpdateComposition(ITfCompositionView *, ITfRange *) {
    edited_ = true;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::OnEndComposition(ITfCompositionView *) {
    if (composition_) { composition_->Release(); composition_ = nullptr; }
    clauses_.clear();
    edited_ = true;
    trace("composition ended");
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::OnEndEdit(ITfContext *context, TfEditCookie readOnly, ITfEditRecord *) {
    clauses_.clear();
    if (!composition_ || !context || !doc_ || !doc_->categories || !doc_->attributes) return S_OK;
    ITfRange *whole = nullptr;
    if (FAILED(composition_->GetRange(&whole)) || !whole) return S_OK;
    ITfProperty *property = nullptr;
    if (SUCCEEDED(context->GetProperty(GUID_PROP_ATTRIBUTE, &property)) && property) {
        IEnumTfRanges *ranges = nullptr;
        if (SUCCEEDED(property->EnumRanges(readOnly, &ranges, whole)) && ranges) {
            ITfRange *range = nullptr;
            while (ranges->Next(1, &range, nullptr) == S_OK && range) {
                bool thick = false;
                VARIANT value;
                VariantInit(&value);
                if (SUCCEEDED(property->GetValue(readOnly, range, &value)) && value.vt == VT_I4) {
                    GUID guid;
                    if (SUCCEEDED(doc_->categories->GetGUID(static_cast<TfGuidAtom>(value.lVal), &guid))) {
                        ITfDisplayAttributeInfo *info = nullptr;
                        if (SUCCEEDED(doc_->attributes->GetDisplayAttributeInfo(guid, &info, nullptr)) && info) {
                            TF_DISPLAYATTRIBUTE da{};
                            if (SUCCEEDED(info->GetAttributeInfo(&da))) {
                                thick = da.bAttr == TF_ATTR_TARGET_CONVERTED || da.bAttr == TF_ATTR_TARGET_NOTCONVERTED || da.fBoldLine;
                            }
                            info->Release();
                        }
                    }
                }
                VariantClear(&value);
                ITfRangeACP *acp = nullptr;
                if (SUCCEEDED(range->QueryInterface(IID_ITfRangeACP, reinterpret_cast<void **>(&acp))) && acp) {
                    LONG s = 0, n = 0;
                    if (SUCCEEDED(acp->GetExtent(&s, &n)) && n > 0) {
                        clauses_.push_back(CTSClause{static_cast<int32_t>(s), static_cast<int32_t>(n), thick ? 1 : 0});
                    }
                    acp->Release();
                }
                range->Release();
                range = nullptr;
            }
            ranges->Release();
        }
        property->Release();
    }
    whole->Release();
    return S_OK;
}

// MARK: - Store: the window's side

void TextStore::sync(const uint16_t *text, int32_t count, int32_t selStart, int32_t selEnd) {
    std::u16string next;
    if (text && count > 0) next.assign(reinterpret_cast<const char16_t *>(text), static_cast<size_t>(count));
    LONG n = static_cast<LONG>(next.size());
    if (selStart < 0) selStart = 0;
    if (selEnd < selStart) selEnd = selStart;
    if (selStart > n) selStart = n;
    if (selEnd > n) selEnd = n;
    if (lock_ != 0) {
        hasPendingSync_ = true;
        pendingText_ = next;
        pendingSelStart_ = selStart;
        pendingSelEnd_ = selEnd;
        return;
    }
    // The changed span, for the input method's ranges (its composition keeps its place).
    size_t oldN = text_.size(), newN = next.size();
    size_t p = 0;
    while (p < oldN && p < newN && text_[p] == next[p]) p++;
    size_t s = 0;
    while (s < oldN - p && s < newN - p && text_[oldN - 1 - s] == next[newN - 1 - s]) s++;
    bool textChanged = p != oldN || p != newN;
    bool selectionChanged = selStart != selStart_ || selEnd != selEnd_;
    text_ = next;
    selStart_ = selStart;
    selEnd_ = selEnd;
    activeEnd_ = TS_AE_END;
    if (textChanged) trace("sync: text %zu..%zu -> %zu units, selection %d..%d", p, oldN - s, newN - s - p, selStart, selEnd);
    if (textChanged && sink_ && (sinkMask_ & TS_AS_TEXT_CHANGE)) {
        TS_TEXTCHANGE change{static_cast<LONG>(p), static_cast<LONG>(oldN - s), static_cast<LONG>(newN - s)};
        sink_->OnTextChange(0, &change);
    }
    if ((selectionChanged || textChanged) && sink_ && (sinkMask_ & TS_AS_SEL_CHANGE)) sink_->OnSelectionChange();
    if (textChanged && sink_ && (sinkMask_ & TS_AS_LAYOUT_CHANGE)) sink_->OnLayoutChange(TS_LC_CHANGE, 1);
}

void TextStore::layoutChanged() {
    if (lock_ != 0 || !sink_ || !(sinkMask_ & TS_AS_LAYOUT_CHANGE)) return;
    sink_->OnLayoutChange(TS_LC_CHANGE, 1);
}

void TextStore::detach() {
    doc_ = nullptr;
    if (composition_) { composition_->Release(); composition_ = nullptr; }
    if (sink_) { sink_->Release(); sink_ = nullptr; }
}

// MARK: - Compartments (open state, conversion mode)

void setCompartment(REFGUID key, int32_t value) {
    if (!g_thread.threadMgr) return;
    ITfCompartmentMgr *mgr = nullptr;
    if (FAILED(g_thread.threadMgr->GetGlobalCompartment(&mgr)) || !mgr) return;
    ITfCompartment *compartment = nullptr;
    if (SUCCEEDED(mgr->GetCompartment(key, &compartment)) && compartment) {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_I4;
        v.lVal = value;
        compartment->SetValue(g_thread.client, &v);
        compartment->Release();
    }
    mgr->Release();
}

int32_t compartmentValue(REFGUID key) {
    if (!g_thread.threadMgr) return 0;
    ITfCompartmentMgr *mgr = nullptr;
    if (FAILED(g_thread.threadMgr->GetGlobalCompartment(&mgr)) || !mgr) return 0;
    int32_t result = 0;
    ITfCompartment *compartment = nullptr;
    if (SUCCEEDED(mgr->GetCompartment(key, &compartment)) && compartment) {
        VARIANT v;
        VariantInit(&v);
        if (SUCCEEDED(compartment->GetValue(&v)) && v.vt == VT_I4) result = v.lVal;
        VariantClear(&v);
        compartment->Release();
    }
    mgr->Release();
    return result;
}

} // namespace

// MARK: - C interface

extern "C" {

CTSDocument *cts_document_create(const CTSCallbacks *callbacks, void *hwnd, int32_t *hresult) {
    if (hresult) *hresult = S_OK;
    if (!callbacks) { if (hresult) *hresult = E_INVALIDARG; return nullptr; }
    HRESULT hr = threadAcquire();
    if (FAILED(hr)) { if (hresult) *hresult = hr; trace("no thread manager: hr 0x%08lx", (unsigned long)hr); return nullptr; }
    Document *d = new Document();
    d->threadAcquired = true;
    d->cb = *callbacks;
    d->hwnd = static_cast<HWND>(hwnd);
    hr = g_thread.threadMgr->CreateDocumentMgr(&d->documentMgr);
    if (FAILED(hr) || !d->documentMgr) { if (hresult) *hresult = hr; delete d; return nullptr; }
    d->store = new TextStore(d);
    TfEditCookie ec = TF_INVALID_EDIT_COOKIE;
    hr = d->documentMgr->CreateContext(g_thread.client, 0, static_cast<ITextStoreACP *>(d->store), &d->context, &ec);
    if (FAILED(hr) || !d->context) { if (hresult) *hresult = hr; delete d; return nullptr; }
    hr = d->documentMgr->Push(d->context);
    if (FAILED(hr)) { if (hresult) *hresult = hr; delete d; return nullptr; }

    ITfSource *contextSource = nullptr;
    if (SUCCEEDED(d->context->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&contextSource))) && contextSource) {
        contextSource->AdviseSink(IID_ITfTextEditSink, static_cast<ITfTextEditSink *>(d->store), &d->editCookie);
        contextSource->Release();
    }
    d->uiSink = new UIElementSink(d);
    ITfSource *threadSource = nullptr;
    if (SUCCEEDED(g_thread.threadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&threadSource))) && threadSource) {
        threadSource->AdviseSink(IID_ITfUIElementSink, static_cast<ITfUIElementSink *>(d->uiSink), &d->uiCookie);
        threadSource->Release();
    }
    CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfCategoryMgr, reinterpret_cast<void **>(&d->categories));
    CoCreateInstance(CLSID_TF_DisplayAttributeMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfDisplayAttributeMgr, reinterpret_cast<void **>(&d->attributes));
    trace("document created for hwnd %p (display attributes %s)", hwnd, d->attributes ? "yes" : "no");
    return reinterpret_cast<CTSDocument *>(d);
}

void cts_document_destroy(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d) return;
    if (d->focused && g_thread.threadMgr) g_thread.threadMgr->SetFocus(g_thread.disabled);
    delete d;
}

void cts_document_set_focus(CTSDocument *document, int focused) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !g_thread.threadMgr) return;
    d->focused = focused != 0;
    HRESULT hr = g_thread.threadMgr->SetFocus(focused ? d->documentMgr : g_thread.disabled);
    trace("focus %s hr 0x%08lx", focused ? "document" : "none", (unsigned long)hr);
}

void cts_document_sync(CTSDocument *document, const uint16_t *text, int32_t length, int32_t selectionStart, int32_t selectionEnd) {
    Document *d = reinterpret_cast<Document *>(document);
    if (d && d->store) d->store->sync(text, length, selectionStart, selectionEnd);
}

void cts_document_layout_changed(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (d && d->store) d->store->layoutChanged();
}

void cts_document_end_composition(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->context || !d->store || !d->store->composing()) return;
    ITfContextOwnerCompositionServices *services = nullptr;
    if (SUCCEEDED(d->context->QueryInterface(IID_ITfContextOwnerCompositionServices, reinterpret_cast<void **>(&services))) && services) {
        HRESULT hr = services->TerminateComposition(nullptr);
        trace("terminate composition hr 0x%08lx", (unsigned long)hr);
        services->Release();
    }
}

int cts_document_composing(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    return (d && d->store && d->store->composing()) ? 1 : 0;
}

int cts_document_candidate_count(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    return d ? d->candidates : 0;
}

void cts_document_set_ime_open(CTSDocument *, int open) { setCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, open ? 1 : 0); }
int cts_document_ime_open(CTSDocument *) { return compartmentValue(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE) != 0; }
void cts_document_set_conversion(CTSDocument *, int32_t mode) { setCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, mode); }
int32_t cts_document_conversion(CTSDocument *) { return compartmentValue(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION); }

int cts_process_key(uint32_t message, uint64_t wParam, int64_t lParam) {
    if (!g_thread.keys) return 0;
    WPARAM w = static_cast<WPARAM>(wParam);
    LPARAM l = static_cast<LPARAM>(lParam);
    BOOL eaten = FALSE;
    if (message == WM_KEYDOWN) {
        if (SUCCEEDED(g_thread.keys->TestKeyDown(w, l, &eaten)) && eaten) {
            eaten = FALSE;
            g_thread.keys->KeyDown(w, l, &eaten);
        }
    } else if (message == WM_KEYUP) {
        if (SUCCEEDED(g_thread.keys->TestKeyUp(w, l, &eaten)) && eaten) {
            eaten = FALSE;
            g_thread.keys->KeyUp(w, l, &eaten);
        }
    }
    if (eaten) trace("key %s vk 0x%llx taken by the input method", message == WM_KEYDOWN ? "down" : "up", (unsigned long long)wParam);
    return eaten ? 1 : 0;
}

int32_t cts_activate_microsoft_ime_jp(void) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ITfInputProcessorProfileMgr *mgr = nullptr;
    HRESULT hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&mgr));
    if (FAILED(hr) || !mgr) return hr;
    // The Microsoft IME (Japanese) text service and its profile.
    static const GUID imeClsid = {0x03B5835F, 0xF03C, 0x411B, {0x9C, 0xE2, 0xAA, 0x23, 0xE1, 0x17, 0x1E, 0x36}};
    static const GUID imeProfile = {0xA76C93D9, 0x5523, 0x4E90, {0xAA, 0xFA, 0x4D, 0xB1, 0x12, 0xF9, 0xAC, 0x76}};
    hr = mgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, 0x0411, imeClsid, imeProfile, nullptr, TF_IPPMF_FORPROCESS | TF_IPPMF_ENABLEPROFILE);
    trace("activate Microsoft IME (Japanese) hr 0x%08lx", (unsigned long)hr);
    mgr->Release();
    return hr;
}

void cts_set_trace(int on) { g_trace = on != 0; }

} // extern "C"
