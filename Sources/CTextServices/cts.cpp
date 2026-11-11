// Text Services Framework for one window (ADR-0016). See include/cts.h for the model.
//
// The document owns a thread manager (one per window), a document manager with one context,
// and the text store that is the context's owner. Edits from the input method arrive as
// ITextStoreACP calls inside locks; this file grants the lock at once (everything is on the
// UI thread), reads and writes through the callbacks, and reports composition start, update
// and end. The candidate list is shown by the input method itself: the shim asks TSF to show
// it and counts its entries for the window.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <initguid.h>
#include <msctf.h>
#include <textstor.h>
#include <ctffunc.h>
#include <olectl.h>
#include <tsattrs.h>
#include <atomic>
#include <cstring>
#include <cstdio>

#include "cts.h"

namespace {

struct Document;

// MARK: - Edit session (reconversion runs its work inside one)

class ReconvertSession final : public ITfEditSession {
public:
    ReconvertSession(Document *doc) : doc_(doc) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_ITfEditSession) { *ppv = static_cast<ITfEditSession *>(this); AddRef(); return S_OK; }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG r = --refs_; if (r == 0) delete this; return r; }
    HRESULT STDMETHODCALLTYPE DoEditSession(TfEditCookie ec) override;
private:
    std::atomic<ULONG> refs_{1};
    Document *doc_;
};

// MARK: - Candidate list sink (thread manager)

class UIElementSink final : public ITfUIElementSink {
public:
    explicit UIElementSink(Document *doc) : doc_(doc) {}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_ITfUIElementSink) { *ppv = static_cast<ITfUIElementSink *>(this); AddRef(); return S_OK; }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
    ULONG STDMETHODCALLTYPE Release() override { ULONG r = --refs_; if (r == 0) delete this; return r; }
    HRESULT STDMETHODCALLTYPE BeginUIElement(DWORD id, BOOL *show) override;
    HRESULT STDMETHODCALLTYPE UpdateUIElement(DWORD id) override;
    HRESULT STDMETHODCALLTYPE EndUIElement(DWORD id) override;
private:
    std::atomic<ULONG> refs_{1};
    Document *doc_;
};

// MARK: - Text store

class TextStore final : public ITextStoreACP, public ITfContextOwnerCompositionSink {
public:
    explicit TextStore(Document *doc) : doc_(doc) {}

    // IUnknown (both interfaces share it)
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid, void **ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_ITextStoreACP) { *ppv = static_cast<ITextStoreACP *>(this); }
        else if (riid == IID_ITfContextOwnerCompositionSink) { *ppv = static_cast<ITfContextOwnerCompositionSink *>(this); }
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

    // Internal
    void notifyTextChange(LONG start, LONG oldEnd, LONG newEnd);
    void notifySelectionChange();
    void setComposing(bool composing) { composing_ = composing; }
    bool composing() const { return composing_; }

private:
    void replaceRange(LONG start, LONG end, const WCHAR *text, ULONG count, TS_TEXTCHANGE *change, LONG *newStart, LONG *newEnd);

    std::atomic<ULONG> refs_{1};
    Document *doc_;
    ITextStoreACPSink *sink_ = nullptr;
    DWORD sinkMask_ = 0;
    DWORD lock_ = 0;
    bool composing_ = false;
    ITfCompositionView *compositionView_ = nullptr;
};

// MARK: - Document

struct Document {
    CTSCallbacks cb{};
    HWND hwnd = nullptr;
    TfClientId client = TF_CLIENTID_NULL;
    ITfThreadMgr *threadMgr = nullptr;
    ITfDocumentMgr *documentMgr = nullptr;
    ITfContext *context = nullptr;
    TextStore *store = nullptr;
    UIElementSink *uiSink = nullptr;
    DWORD uiCookie = TF_INVALID_COOKIE;
    DWORD ownerCookie = TF_INVALID_COOKIE;
    int candidates = 0;
    bool comInitialised = false;

    ~Document() {
        if (context) context->Release();
        if (documentMgr) documentMgr->Release();
        if (threadMgr) {
            if (uiCookie != TF_INVALID_COOKIE) {
                ITfSource *source = nullptr;
                if (SUCCEEDED(threadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&source)))) {
                    source->UnadviseSink(uiCookie);
                    source->Release();
                }
            }
            threadMgr->Deactivate();
            threadMgr->Release();
        }
        if (uiSink) uiSink->Release();
        if (store) store->Release();
        if (comInitialised) CoUninitialize();
    }
};

// MARK: - Implementation

HRESULT STDMETHODCALLTYPE ReconvertSession::DoEditSession(TfEditCookie ec) {
    ITfContext *context = doc_->context;
    if (!context) return E_FAIL;
    TF_SELECTION selection{};
    ULONG fetched = 0;
    HRESULT hr = context->GetSelection(ec, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
    if (FAILED(hr) || fetched == 0 || !selection.range) return FAILED(hr) ? hr : E_FAIL;
    ITfFunctionProvider *provider = nullptr;
    hr = doc_->threadMgr->GetFunctionProvider(GUID_SYSTEM_FUNCTIONPROVIDER, &provider);
    if (FAILED(hr)) { selection.range->Release(); return hr; }
    ITfFnReconversion *reconversion = nullptr;
    hr = provider->GetFunction(GUID{}, IID_ITfFnReconversion, reinterpret_cast<IUnknown **>(&reconversion));
    provider->Release();
    if (FAILED(hr) || !reconversion) { selection.range->Release(); return FAILED(hr) ? hr : E_NOINTERFACE; }
    ITfRange *target = nullptr;
    BOOL convertible = FALSE;
    hr = reconversion->QueryRange(selection.range, &target, &convertible);
    if (SUCCEEDED(hr) && convertible && target) hr = reconversion->Reconvert(target);
    if (target) target->Release();
    reconversion->Release();
    selection.range->Release();
    return hr;
}

HRESULT STDMETHODCALLTYPE UIElementSink::BeginUIElement(DWORD id, BOOL *show) {
    if (show) *show = TRUE;   // the input method draws its own candidate list
    ITfUIElementMgr *mgr = nullptr;
    if (FAILED(doc_->threadMgr->QueryInterface(IID_ITfUIElementMgr, reinterpret_cast<void **>(&mgr)))) return S_OK;
    ITfUIElement *element = nullptr;
    HRESULT hr = mgr->GetUIElement(id, &element);
    mgr->Release();
    if (SUCCEEDED(hr) && element) {
        ITfCandidateListUIElement *list = nullptr;
        if (SUCCEEDED(element->QueryInterface(IID_ITfCandidateListUIElement, reinterpret_cast<void **>(&list)))) {
            UINT count = 0;
            if (SUCCEEDED(list->GetCount(&count))) {
                doc_->candidates = static_cast<int>(count);
                if (doc_->cb.candidates) doc_->cb.candidates(doc_->cb.user, doc_->candidates);
            }
            list->Release();
        }
        element->Release();
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE UIElementSink::UpdateUIElement(DWORD id) {
    ITfUIElementMgr *mgr = nullptr;
    if (FAILED(doc_->threadMgr->QueryInterface(IID_ITfUIElementMgr, reinterpret_cast<void **>(&mgr)))) return S_OK;
    ITfUIElement *element = nullptr;
    if (SUCCEEDED(mgr->GetUIElement(id, &element)) && element) {
        ITfCandidateListUIElement *list = nullptr;
        if (SUCCEEDED(element->QueryInterface(IID_ITfCandidateListUIElement, reinterpret_cast<void **>(&list)))) {
            UINT count = 0;
            if (SUCCEEDED(list->GetCount(&count))) {
                doc_->candidates = static_cast<int>(count);
                if (doc_->cb.candidates) doc_->cb.candidates(doc_->cb.user, doc_->candidates);
            }
            list->Release();
        }
        element->Release();
    }
    mgr->Release();
    return S_OK;
}

HRESULT STDMETHODCALLTYPE UIElementSink::EndUIElement(DWORD) {
    doc_->candidates = 0;
    if (doc_->cb.candidates) doc_->cb.candidates(doc_->cb.user, 0);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::AdviseSink(REFIID riid, IUnknown *punk, DWORD mask) {
    if (riid != IID_ITextStoreACPSink) return E_INVALIDARG;
    if (!punk) return E_INVALIDARG;
    if (sink_) return CONNECT_E_ADVISELIMIT;
    ITextStoreACPSink *sink = nullptr;
    HRESULT hr = punk->QueryInterface(IID_ITextStoreACPSink, reinterpret_cast<void **>(&sink));
    if (FAILED(hr)) return hr;
    sink_ = sink;
    sinkMask_ = mask;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::UnadviseSink(IUnknown *) {
    if (sink_) { sink_->Release(); sink_ = nullptr; }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::RequestLock(DWORD flags, HRESULT *session) {
    if (!session) return E_INVALIDARG;
    if (!sink_) { *session = E_UNEXPECTED; return S_OK; }
    if (lock_ != 0) {
        // Nested requests are not granted: TSF retries after the current lock ends.
        *session = TS_E_SYNCHRONOUS;
        return S_OK;
    }
    lock_ = flags;
    *session = sink_->OnLockGranted(flags);
    lock_ = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetStatus(TS_STATUS *status) {
    if (!status) return E_INVALIDARG;
    status->dwDynamicFlags = 0;
    status->dwStaticFlags = 0;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::QueryInsert(LONG testStart, LONG testEnd, ULONG count, LONG *resultStart, LONG *resultEnd) {
    if (!resultStart || !resultEnd) return E_INVALIDARG;
    *resultStart = testStart;
    *resultEnd = testStart + static_cast<LONG>(count);
    (void)testEnd;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP *selection, ULONG *fetched) {
    if (!fetched) return E_INVALIDARG;
    *fetched = 0;
    if (count == 0 || !selection) return S_OK;
    if (index != TF_DEFAULT_SELECTION && index != 0) return TS_E_NOSELECTION;
    int32_t start = 0, length = 0;
    doc_->cb.selection(doc_->cb.user, &start, &length);
    selection[0].acpStart = start;
    selection[0].acpEnd = start + length;
    selection[0].style.ase = TS_AE_END;
    selection[0].style.fInterimChar = FALSE;
    *fetched = 1;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::SetSelection(ULONG count, const TS_SELECTION_ACP *selection) {
    if (count == 0 || !selection) return S_OK;
    LONG start = selection[0].acpStart;
    LONG end = selection[0].acpEnd;
    if (end < start) end = start;
    doc_->cb.setSelection(doc_->cb.user, start, end - start);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetText(LONG start, LONG end, WCHAR *plain, ULONG plainRequested, ULONG *plainReturned,
                                             TS_RUNINFO *runs, ULONG runsRequested, ULONG *runsReturned, LONG *next) {
    (void)runs; (void)runsRequested;
    if (plainReturned) *plainReturned = 0;
    if (runsReturned) *runsReturned = 0;
    LONG length = doc_->cb.length(doc_->cb.user);
    if (end < 0 || end > length) end = length;
    if (start < 0) start = 0;
    if (start > end) start = end;
    LONG wanted = end - start;
    if (static_cast<ULONG>(wanted) > plainRequested) wanted = static_cast<LONG>(plainRequested);
    int32_t copied = 0;
    if (plain && wanted > 0) copied = doc_->cb.read(doc_->cb.user, start, wanted, reinterpret_cast<uint16_t *>(plain));
    if (plainReturned) *plainReturned = static_cast<ULONG>(copied);
    if (next) *next = start + copied;
    return (copied == 0 && start < end) ? TS_E_INVALIDPOS : S_OK;
}

void TextStore::replaceRange(LONG start, LONG end, const WCHAR *text, ULONG count, TS_TEXTCHANGE *change, LONG *newStart, LONG *newEnd) {
    LONG length = doc_->cb.length(doc_->cb.user);
    if (end < start) end = start;
    if (end > length) end = length;
    if (start < 0) start = 0;
    doc_->cb.replace(doc_->cb.user, start, end - start, reinterpret_cast<const uint16_t *>(text), static_cast<int32_t>(count), composing_ ? 1 : 0);
    LONG inserted = static_cast<LONG>(count);
    if (change) {
        change->acpStart = start;
        change->acpOldEnd = end;
        change->acpNewEnd = start + inserted;
    }
    if (newStart) *newStart = start;
    if (newEnd) *newEnd = start + inserted;
}

HRESULT STDMETHODCALLTYPE TextStore::SetText(DWORD, LONG start, LONG end, const WCHAR *text, ULONG count, TS_TEXTCHANGE *change) {
    replaceRange(start, end, text, count, change, nullptr, nullptr);
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
    if (insertable) *insertable = FALSE;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::InsertEmbedded(DWORD, LONG, LONG, IDataObject *, TS_TEXTCHANGE *) {
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE TextStore::InsertTextAtSelection(DWORD flags, const WCHAR *text, ULONG count, LONG *start, LONG *end, TS_TEXTCHANGE *change) {
    int32_t selStart = 0, selLength = 0;
    doc_->cb.selection(doc_->cb.user, &selStart, &selLength);
    if (flags & TF_IAS_QUERYONLY) {
        if (start) *start = selStart;
        if (end) *end = selStart + selLength;
        return S_OK;
    }
    LONG newStart = selStart, newEnd = selStart;
    replaceRange(selStart, selStart + selLength, text, count, change, &newStart, &newEnd);
    if (start) *start = newStart;
    if (end) *end = newEnd;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::InsertEmbeddedAtSelection(DWORD, IDataObject *, LONG *start, LONG *end, TS_TEXTCHANGE *) {
    if (start) *start = 0;
    if (end) *end = 0;
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE TextStore::RequestSupportedAttrs(DWORD, ULONG, const TS_ATTRID *) { return S_OK; }

HRESULT STDMETHODCALLTYPE TextStore::RequestAttrsAtPosition(LONG, ULONG, const TS_ATTRID *, DWORD) { return S_OK; }

HRESULT STDMETHODCALLTYPE TextStore::RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID *, DWORD) { return S_OK; }

HRESULT STDMETHODCALLTYPE TextStore::FindNextAttrTransition(LONG start, LONG, ULONG, const TS_ATTRID *, DWORD, LONG *next, BOOL *found, LONG *overlap) {
    if (next) *next = start;
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
    *end = doc_->cb.length(doc_->cb.user);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetActiveView(TsViewCookie *view) {
    if (view) *view = 1;
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetACPFromPoint(TsViewCookie, const POINT *, DWORD, LONG *acp) {
    if (acp) *acp = 0;
    return E_NOTIMPL;
}

HRESULT STDMETHODCALLTYPE TextStore::GetTextExt(TsViewCookie, LONG start, LONG end, RECT *rect, BOOL *clipped) {
    if (clipped) *clipped = FALSE;
    if (!rect) return E_INVALIDARG;
    int32_t ltrb[4] = {0, 0, 0, 0};
    if (!doc_->cb.rect(doc_->cb.user, start, end - start, ltrb)) return TS_E_NOLAYOUT;
    rect->left = ltrb[0];
    rect->top = ltrb[1];
    rect->right = ltrb[2];
    rect->bottom = ltrb[3];
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetScreenExt(TsViewCookie, RECT *rect) {
    if (!rect) return E_INVALIDARG;
    HWND hwnd = static_cast<HWND>(doc_->cb.window(doc_->cb.user));
    if (!hwnd || !GetClientRect(hwnd, rect)) return E_FAIL;
    POINT origin{0, 0};
    ClientToScreen(hwnd, &origin);
    OffsetRect(rect, origin.x, origin.y);
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::GetWnd(TsViewCookie, HWND *wnd) {
    if (!wnd) return E_INVALIDARG;
    *wnd = static_cast<HWND>(doc_->cb.window(doc_->cb.user));
    return *wnd ? S_OK : E_FAIL;
}

HRESULT STDMETHODCALLTYPE TextStore::OnStartComposition(ITfCompositionView *view, BOOL *ok) {
    if (ok) *ok = TRUE;
    if (compositionView_) compositionView_->Release();
    compositionView_ = view;
    if (compositionView_) compositionView_->AddRef();
    composing_ = true;
    ITfRange *range = nullptr;
    if (view && SUCCEEDED(view->GetRange(&range)) && range) {
        ITfRangeACP *acp = nullptr;
        if (SUCCEEDED(range->QueryInterface(IID_ITfRangeACP, reinterpret_cast<void **>(&acp)))) {
            LONG start = 0, length = 0;
            if (SUCCEEDED(acp->GetExtent(&start, &length))) doc_->cb.markRange(doc_->cb.user, start, length);
            acp->Release();
        }
        range->Release();
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::OnUpdateComposition(ITfCompositionView *, ITfRange *range) {
    if (!range) return S_OK;
    ITfRangeACP *acp = nullptr;
    if (SUCCEEDED(range->QueryInterface(IID_ITfRangeACP, reinterpret_cast<void **>(&acp)))) {
        LONG start = 0, length = 0;
        if (SUCCEEDED(acp->GetExtent(&start, &length))) doc_->cb.markRange(doc_->cb.user, start, length);
        acp->Release();
    }
    return S_OK;
}

HRESULT STDMETHODCALLTYPE TextStore::OnEndComposition(ITfCompositionView *) {
    composing_ = false;
    if (compositionView_) { compositionView_->Release(); compositionView_ = nullptr; }
    doc_->cb.endComposition(doc_->cb.user);
    return S_OK;
}

void TextStore::notifyTextChange(LONG start, LONG oldEnd, LONG newEnd) {
    if (!sink_ || !(sinkMask_ & TS_AS_TEXT_CHANGE)) return;
    TS_TEXTCHANGE change{start, oldEnd, newEnd};
    sink_->OnTextChange(0, &change);
}

void TextStore::notifySelectionChange() {
    if (!sink_ || !(sinkMask_ & TS_AS_SEL_CHANGE)) return;
    sink_->OnSelectionChange();
}

// Setting a TSF attribute or status reaches us only through these; no other state is kept here.

void setCompartment(Document *d, REFGUID key, int32_t value) {
    ITfCompartmentMgr *mgr = nullptr;
    if (FAILED(d->threadMgr->GetGlobalCompartment(&mgr)) || !mgr) return;
    ITfCompartment *compartment = nullptr;
    if (SUCCEEDED(mgr->GetCompartment(key, &compartment)) && compartment) {
        VARIANT v;
        VariantInit(&v);
        v.vt = VT_I4;
        v.lVal = value;
        compartment->SetValue(d->client, &v);
        compartment->Release();
    }
    mgr->Release();
}

int32_t compartmentValue(Document *d, REFGUID key) {
    ITfCompartmentMgr *mgr = nullptr;
    if (FAILED(d->threadMgr->GetGlobalCompartment(&mgr)) || !mgr) return 0;
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

CTSDocument *cts_document_create(const CTSCallbacks *callbacks, void *hwnd) {
    if (!callbacks) return nullptr;
    Document *d = new Document();
    d->cb = *callbacks;
    d->hwnd = static_cast<HWND>(hwnd);
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    d->comInitialised = SUCCEEDED(hr);   // RPC_E_CHANGED_MODE: already initialised, nothing to undo
    hr = CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_ITfThreadMgr, reinterpret_cast<void **>(&d->threadMgr));
    if (FAILED(hr) || !d->threadMgr) { delete d; return nullptr; }
    if (FAILED(d->threadMgr->Activate(&d->client))) { delete d; return nullptr; }
    if (FAILED(d->threadMgr->CreateDocumentMgr(&d->documentMgr)) || !d->documentMgr) { delete d; return nullptr; }

    d->store = new TextStore(d);
    TfEditCookie ec = TF_INVALID_EDIT_COOKIE;
    IUnknown *owner = static_cast<IUnknown *>(static_cast<ITextStoreACP *>(d->store));
    if (FAILED(d->documentMgr->CreateContext(d->client, 0, owner, &d->context, &ec)) || !d->context) { delete d; return nullptr; }

    ITfSource *contextSource = nullptr;
    if (SUCCEEDED(d->context->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&contextSource)))) {
        contextSource->AdviseSink(IID_ITfContextOwnerCompositionSink, static_cast<ITfContextOwnerCompositionSink *>(d->store), &d->ownerCookie);
        contextSource->Release();
    }

    d->uiSink = new UIElementSink(d);
    ITfSource *threadSource = nullptr;
    if (SUCCEEDED(d->threadMgr->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&threadSource)))) {
        threadSource->AdviseSink(IID_ITfUIElementSink, static_cast<ITfUIElementSink *>(d->uiSink), &d->uiCookie);
        threadSource->Release();
    }
    return reinterpret_cast<CTSDocument *>(d);
}

void cts_document_destroy(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d) return;
    if (d->threadMgr) d->threadMgr->SetFocus(nullptr);
    if (d->context && d->ownerCookie != TF_INVALID_COOKIE) {
        ITfSource *source = nullptr;
        if (SUCCEEDED(d->context->QueryInterface(IID_ITfSource, reinterpret_cast<void **>(&source)))) {
            source->UnadviseSink(d->ownerCookie);
            source->Release();
        }
    }
    if (d->store) d->store->UnadviseSink(nullptr);
    delete d;
}

void cts_document_set_focus(CTSDocument *document, int focused) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->threadMgr) return;
    d->threadMgr->SetFocus(focused ? d->documentMgr : nullptr);
}

void cts_document_notify_change(CTSDocument *document, int32_t start, int32_t oldCount, int32_t newCount) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->store) return;
    d->store->notifyTextChange(start, start + oldCount, start + newCount);
}

void cts_document_notify_selection(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->store) return;
    d->store->notifySelectionChange();
}

void cts_document_set_ime_open(CTSDocument *document, int open) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->threadMgr) return;
    setCompartment(d, GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, open ? 1 : 0);
}

int cts_document_ime_open(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->threadMgr) return 0;
    return compartmentValue(d, GUID_COMPARTMENT_KEYBOARD_OPENCLOSE) != 0;
}

void cts_document_set_conversion(CTSDocument *document, int32_t mode) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->threadMgr) return;
    setCompartment(d, GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, mode);
}

int32_t cts_document_conversion(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->threadMgr) return 0;
    return compartmentValue(d, GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION);
}

int cts_document_candidate_count(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    return d ? d->candidates : 0;
}

int32_t cts_document_reconvert(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->context) return E_FAIL;
    ReconvertSession *session = new ReconvertSession(d);
    HRESULT sessionResult = E_FAIL;
    HRESULT hr = d->context->RequestEditSession(d->client, session, TF_ES_SYNC | TF_ES_READWRITE, &sessionResult);
    session->Release();
    if (FAILED(hr)) return hr;
    return sessionResult;
}

int cts_document_composing(CTSDocument *document) {
    Document *d = reinterpret_cast<Document *>(document);
    return (d && d->store && d->store->composing()) ? 1 : 0;
}

} // extern "C"

// Keys the text services may take (the input method's romaji and kana, its conversion keys).
// The app forwards each key message here before its own handling; TSF returns whether it ate it.
extern "C" int cts_document_key(CTSDocument *document, uint64_t wParam, int64_t lParam, int down) {
    Document *d = reinterpret_cast<Document *>(document);
    if (!d || !d->threadMgr) return 0;
    ITfKeystrokeMgr *keys = nullptr;
    if (FAILED(d->threadMgr->QueryInterface(IID_ITfKeystrokeMgr, reinterpret_cast<void **>(&keys))) || !keys) return 0;
    BOOL eaten = FALSE;
    WPARAM w = static_cast<WPARAM>(wParam);
    LPARAM l = static_cast<LPARAM>(lParam);
    if (down) {
        HRESULT hrTest = keys->TestKeyDown(w, l, &eaten);
        // Diagnostics (temporary): does the thread's focus match this document, and which profile is active?
        static bool logged = false;
        ITfDocumentMgr *focus = nullptr;
        d->threadMgr->GetFocus(&focus);
        fprintf(stderr, "[trace] cts key down vk 0x%llx testhr 0x%lx eaten %d focusIsDocument %d\n", (unsigned long long)wParam, (unsigned long)hrTest, (int)eaten, focus == d->documentMgr ? 1 : 0);
        if (!logged) {
            logged = true;
            ITfInputProcessorProfileMgr *pm = nullptr;
            if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&pm))) && pm) {
                TF_INPUTPROCESSORPROFILE prof{};
                HRESULT hrActive = pm->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &prof);
                fprintf(stderr, "[trace] cts active keyboard profile hr 0x%lx clsid {%08lX-%04X-%04X} langid 0x%04X type %lu\n", (unsigned long)hrActive, prof.clsid.Data1, prof.clsid.Data2, prof.clsid.Data3, prof.langid, (unsigned long)prof.dwProfileType);
                pm->Release();
            }
        }
        if (focus) focus->Release();
        if (eaten) keys->KeyDown(w, l, &eaten);
    } else {
        keys->TestKeyUp(w, l, &eaten);
        if (eaten) keys->KeyUp(w, l, &eaten);
    }
    keys->Release();
    return eaten ? 1 : 0;
}

// Makes the Microsoft IME for Japanese this process's active text service (the profile of its
// keyboard layout). Only this process's profile changes (TF_IPPMF_FORPROCESS).
extern "C" int32_t cts_activate_microsoft_ime_jp(void) {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    ITfInputProcessorProfileMgr *mgr = nullptr;
    hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfileMgr, reinterpret_cast<void **>(&mgr));
    if (FAILED(hr) || !mgr) return hr;
    // The Microsoft IME (Japanese) text service and its profile.
    static const GUID imeClsid = {0x03B5835F, 0xF03C, 0x411B, {0x9C, 0xE2, 0xAA, 0x23, 0xE1, 0x17, 0x1E, 0x36}};
    static const GUID imeProfile = {0xA76C93D9, 0x5523, 0x4E90, {0xAA, 0xFA, 0x4D, 0xB1, 0x12, 0xF9, 0xAC, 0x76}};
    // A NULL layout returns S_OK here; an explicit 04110411 returns E_INVALIDARG.
    hr = mgr->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, 0x0411, imeClsid, imeProfile, nullptr,
                              TF_IPPMF_FORPROCESS | TF_IPPMF_ENABLEPROFILE);
    fprintf(stderr, "[trace] cts ActivateProfile hr 0x%lx\n", (unsigned long)hr);
    mgr->Release();
    // The classic per-thread route: set the input language, then activate the language profile on this thread.
    ITfInputProcessorProfiles *profiles = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_ITfInputProcessorProfiles, reinterpret_cast<void **>(&profiles))) && profiles) {
        HRESULT hrLang = profiles->ChangeCurrentLanguage(0x0411);
        HRESULT hrProfile = profiles->ActivateLanguageProfile(imeClsid, 0x0411, imeProfile);
        fprintf(stderr, "[trace] cts ChangeCurrentLanguage hr 0x%lx ActivateLanguageProfile hr 0x%lx\n", (unsigned long)hrLang, (unsigned long)hrProfile);
        profiles->Release();
        if (SUCCEEDED(hrProfile)) hr = hrProfile;
    }
    return hr;
}
