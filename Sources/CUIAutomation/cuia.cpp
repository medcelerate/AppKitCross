// UI Automation providers over a snapshot tree (see cuia.h).

#include "cuia.h"

#include <windows.h>
#include <oleauto.h>
#include <uiautomation.h>

// The runtime-id prefix for elements under an HWND provider: newer SDKs define it in
// uiautomationcoreapi.h, the swift.org toolchain's SDK does not.
#ifndef UiaAppendRuntimeIdConstant
#define UiaAppendRuntimeIdConstant 3
#endif

#include <algorithm>
#include <map>
#include <string>
#include <vector>

namespace {

struct Node {
    int32_t id = 0;
    int32_t parent = -1;
    int32_t controlType = UIA_CustomControlTypeId;
    std::wstring name, value, help, automationId, itemType;
    bool hasName = false, hasValue = false, hasHelp = false, hasAutomationId = false, hasItemType = false;
    RECT rect = {0, 0, 0, 0};
    uint32_t flags = 0;
    double rangeValue = 0, rangeMin = 0, rangeMax = 0, rangeStep = 0;
    int32_t toggleState = 0;
    int32_t selStart = -1, selLength = 0;
    std::vector<int32_t> children;
};

static std::wstring copyString(const uint16_t *s, bool &present) {
    present = s != nullptr;
    if (!s) return std::wstring();
    return std::wstring(reinterpret_cast<const wchar_t *>(s));
}

static BSTR toBSTR(const std::wstring &s) { return SysAllocStringLen(s.c_str(), static_cast<UINT>(s.size())); }

class Provider;
class TextRange;

} // namespace

struct CUIARoot {
    HWND hwnd = nullptr;
    CUIACallbacks callbacks = {};
    std::map<int32_t, Node> nodes;
    std::map<int32_t, Provider *> providers;      // one reference each
    int32_t rootId = -1;
    bool stale = true;
    bool refreshing = false;
    bool settingNodes = false;
    bool destroyed = false;

    void ensureFresh();
    Node *node(int32_t id) { ensureFresh(); auto it = nodes.find(id); return it == nodes.end() ? nullptr : &it->second; }
    Provider *provider(int32_t id);          // creates on demand for live nodes; AddRef'd by the map only
    int32_t focused();
    int32_t hitTest(int32_t id, double x, double y);
};

namespace {

// MARK: - Provider

class Provider : public IRawElementProviderSimple,
                 public IRawElementProviderFragment,
                 public IRawElementProviderFragmentRoot,
                 public IInvokeProvider,
                 public IToggleProvider,
                 public IValueProvider,
                 public IRangeValueProvider,
                 public ISelectionProvider,
                 public ISelectionItemProvider,
                 public ITextProvider {
public:
    Provider(CUIARoot *root, int32_t id) : root_(root), id_(id) {}
    int32_t id() const { return id_; }
    void detach() { root_ = nullptr; }
    bool isRoot() const { return root_ && root_->rootId == id_; }
    Node *node() { return root_ && !root_->destroyed ? root_->node(id_) : nullptr; }

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(IRawElementProviderSimple)) *out = static_cast<IRawElementProviderSimple *>(this);
        else if (riid == __uuidof(IRawElementProviderFragment)) *out = static_cast<IRawElementProviderFragment *>(this);
        else if (riid == __uuidof(IRawElementProviderFragmentRoot)) { if (!isRoot()) return E_NOINTERFACE; *out = static_cast<IRawElementProviderFragmentRoot *>(this); }
        else if (riid == __uuidof(IInvokeProvider)) *out = static_cast<IInvokeProvider *>(this);
        else if (riid == __uuidof(IToggleProvider)) *out = static_cast<IToggleProvider *>(this);
        else if (riid == __uuidof(IValueProvider)) *out = static_cast<IValueProvider *>(this);
        else if (riid == __uuidof(IRangeValueProvider)) *out = static_cast<IRangeValueProvider *>(this);
        else if (riid == __uuidof(ISelectionProvider)) *out = static_cast<ISelectionProvider *>(this);
        else if (riid == __uuidof(ISelectionItemProvider)) *out = static_cast<ISelectionItemProvider *>(this);
        else if (riid == __uuidof(ITextProvider)) *out = static_cast<ITextProvider *>(this);
        else return E_NOINTERFACE;
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
    STDMETHODIMP_(ULONG) Release() override {
        ULONG n = InterlockedDecrement(&refs_);
        if (n == 0) delete this;
        return n;
    }

    // IRawElementProviderSimple
    STDMETHODIMP get_ProviderOptions(ProviderOptions *out) override {
        if (!out) return E_POINTER;
        *out = static_cast<ProviderOptions>(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
        return S_OK;
    }
    STDMETHODIMP GetPatternProvider(PATTERNID patternId, IUnknown **out) override;
    STDMETHODIMP GetPropertyValue(PROPERTYID propertyId, VARIANT *out) override;
    STDMETHODIMP get_HostRawElementProvider(IRawElementProviderSimple **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (isRoot() && root_->hwnd) return UiaHostProviderFromHwnd(root_->hwnd, out);
        return S_OK;
    }

    // IRawElementProviderFragment
    STDMETHODIMP Navigate(NavigateDirection direction, IRawElementProviderFragment **out) override;
    STDMETHODIMP GetRuntimeId(SAFEARRAY **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (isRoot()) return S_OK;      // the host provider supplies the window's id
        int ids[2] = {UiaAppendRuntimeIdConstant, id_};
        SAFEARRAY *a = SafeArrayCreateVector(VT_I4, 0, 2);
        if (!a) return E_OUTOFMEMORY;
        for (LONG i = 0; i < 2; i++) SafeArrayPutElement(a, &i, &ids[i]);
        *out = a;
        return S_OK;
    }
    STDMETHODIMP get_BoundingRectangle(UiaRect *out) override {
        if (!out) return E_POINTER;
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        out->left = n->rect.left; out->top = n->rect.top;
        out->width = n->rect.right - n->rect.left; out->height = n->rect.bottom - n->rect.top;
        return S_OK;
    }
    STDMETHODIMP GetEmbeddedFragmentRoots(SAFEARRAY **out) override { if (!out) return E_POINTER; *out = nullptr; return S_OK; }
    STDMETHODIMP SetFocus() override {
        if (!root_) return UIA_E_ELEMENTNOTAVAILABLE;
        if (root_->callbacks.setFocus && root_->callbacks.setFocus(root_->callbacks.context, id_)) return S_OK;
        return UIA_E_INVALIDOPERATION;
    }
    STDMETHODIMP get_FragmentRoot(IRawElementProviderFragmentRoot **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (!root_) return UIA_E_ELEMENTNOTAVAILABLE;
        Provider *r = root_->provider(root_->rootId);
        if (!r) return E_FAIL;
        return r->QueryInterface(__uuidof(IRawElementProviderFragmentRoot), reinterpret_cast<void **>(out));
    }

    // IRawElementProviderFragmentRoot
    STDMETHODIMP ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (!root_) return UIA_E_ELEMENTNOTAVAILABLE;
        int32_t hit = root_->hitTest(root_->rootId, x, y);
        if (hit < 0) return S_OK;
        Provider *p = root_->provider(hit);
        if (!p) return S_OK;
        return p->QueryInterface(__uuidof(IRawElementProviderFragment), reinterpret_cast<void **>(out));
    }
    STDMETHODIMP GetFocus(IRawElementProviderFragment **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (!root_) return UIA_E_ELEMENTNOTAVAILABLE;
        int32_t f = root_->focused();
        if (f < 0) return S_OK;
        Provider *p = root_->provider(f);
        if (!p) return S_OK;
        return p->QueryInterface(__uuidof(IRawElementProviderFragment), reinterpret_cast<void **>(out));
    }

    // IInvokeProvider
    STDMETHODIMP Invoke() override {
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!(n->flags & CUIA_ENABLED)) return UIA_E_ELEMENTNOTENABLED;
        if (root_->callbacks.invoke && root_->callbacks.invoke(root_->callbacks.context, id_)) return S_OK;
        return UIA_E_INVALIDOPERATION;
    }

    // IToggleProvider
    STDMETHODIMP Toggle() override {
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!(n->flags & CUIA_ENABLED)) return UIA_E_ELEMENTNOTENABLED;
        if (root_->callbacks.toggle && root_->callbacks.toggle(root_->callbacks.context, id_)) return S_OK;
        return UIA_E_INVALIDOPERATION;
    }
    STDMETHODIMP get_ToggleState(ToggleState *out) override {
        if (!out) return E_POINTER;
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        *out = n->toggleState == 1 ? ToggleState_On : n->toggleState == 2 ? ToggleState_Indeterminate : ToggleState_Off;
        return S_OK;
    }

    // IValueProvider
    STDMETHODIMP SetValue(LPCWSTR value) override {
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!(n->flags & CUIA_ENABLED)) return UIA_E_ELEMENTNOTENABLED;
        if (!(n->flags & CUIA_SETTABLE)) return UIA_E_INVALIDOPERATION;
        if (root_->callbacks.setValue && root_->callbacks.setValue(root_->callbacks.context, id_, reinterpret_cast<const uint16_t *>(value ? value : L""))) return S_OK;
        return UIA_E_INVALIDOPERATION;
    }
    STDMETHODIMP get_Value(BSTR *out) override {
        if (!out) return E_POINTER;
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        *out = toBSTR(n->value);
        return S_OK;
    }
    STDMETHODIMP get_IsReadOnly(BOOL *out) override {
        if (!out) return E_POINTER;
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        *out = (n->flags & CUIA_SETTABLE) && (n->flags & CUIA_ENABLED) ? FALSE : TRUE;
        return S_OK;
    }

    // IRangeValueProvider
    STDMETHODIMP SetValue(double value) override {
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!(n->flags & CUIA_ENABLED)) return UIA_E_ELEMENTNOTENABLED;
        if (!(n->flags & CUIA_SETTABLE)) return UIA_E_INVALIDOPERATION;
        if (root_->callbacks.setRangeValue && root_->callbacks.setRangeValue(root_->callbacks.context, id_, value)) return S_OK;
        return UIA_E_INVALIDOPERATION;
    }
    STDMETHODIMP get_Value(double *out) override { return rangeField(out, &Node::rangeValue); }
    STDMETHODIMP get_Maximum(double *out) override { return rangeField(out, &Node::rangeMax); }
    STDMETHODIMP get_Minimum(double *out) override { return rangeField(out, &Node::rangeMin); }
    STDMETHODIMP get_LargeChange(double *out) override { return rangeField(out, &Node::rangeStep); }
    STDMETHODIMP get_SmallChange(double *out) override { return rangeField(out, &Node::rangeStep); }

    // ISelectionProvider
    STDMETHODIMP GetSelection(SAFEARRAY **out) override;
    STDMETHODIMP get_CanSelectMultiple(BOOL *out) override { return flag(out, CUIA_CAN_SELECT_MULTIPLE); }
    STDMETHODIMP get_IsSelectionRequired(BOOL *out) override { if (!out) return E_POINTER; *out = FALSE; return S_OK; }

    // ISelectionItemProvider
    STDMETHODIMP Select() override { return select(0); }
    STDMETHODIMP AddToSelection() override { return select(1); }
    STDMETHODIMP RemoveFromSelection() override { return select(2); }
    STDMETHODIMP get_IsSelected(BOOL *out) override { return flag(out, CUIA_SELECTED); }
    STDMETHODIMP get_SelectionContainer(IRawElementProviderSimple **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        // The nearest ancestor with the Selection pattern (a table for its rows).
        int32_t p = n->parent;
        while (p >= 0) {
            Node *pn = root_->node(p);
            if (!pn) break;
            if (pn->flags & CUIA_HAS_SELECTION) {
                Provider *pp = root_->provider(p);
                if (!pp) break;
                return pp->QueryInterface(__uuidof(IRawElementProviderSimple), reinterpret_cast<void **>(out));
            }
            p = pn->parent;
        }
        return S_OK;
    }

    // ITextProvider
    STDMETHODIMP GetVisibleRanges(SAFEARRAY **out) override;
    STDMETHODIMP RangeFromChild(IRawElementProviderSimple *, ITextRangeProvider **out) override;
    STDMETHODIMP RangeFromPoint(UiaPoint, ITextRangeProvider **out) override;
    STDMETHODIMP get_DocumentRange(ITextRangeProvider **out) override;
    STDMETHODIMP get_SupportedTextSelection(SupportedTextSelection *out) override {
        if (!out) return E_POINTER;
        *out = SupportedTextSelection_Single;
        return S_OK;
    }

    HRESULT makeRange(int32_t start, int32_t end, ITextRangeProvider **out);
    CUIARoot *root() { return root_; }

private:
    HRESULT rangeField(double *out, double Node::*field) {
        if (!out) return E_POINTER;
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        *out = n->*field;
        return S_OK;
    }
    HRESULT flag(BOOL *out, uint32_t f) {
        if (!out) return E_POINTER;
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        *out = (n->flags & f) ? TRUE : FALSE;
        return S_OK;
    }
    HRESULT select(int32_t mode) {
        Node *n = node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        if (!(n->flags & CUIA_ENABLED)) return UIA_E_ELEMENTNOTENABLED;
        if (root_->callbacks.select && root_->callbacks.select(root_->callbacks.context, id_, mode)) return S_OK;
        return UIA_E_INVALIDOPERATION;
    }

    CUIARoot *root_;
    int32_t id_;
    ULONG refs_ = 1;
};

// The ISelectionProvider and ITextProvider GetSelection overloads share a name; C++
// resolves them by signature, and both are declared here through the base interfaces.
STDMETHODIMP Provider::GetSelection(SAFEARRAY **out) {
    if (!out) return E_POINTER;
    *out = nullptr;
    Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    if (n->flags & CUIA_HAS_TEXT) {
        // ITextProvider::GetSelection: the selected range (or the caret) as one range.
        int32_t start = n->selStart < 0 ? 0 : n->selStart;
        int32_t end = n->selStart < 0 ? 0 : n->selStart + n->selLength;
        SAFEARRAY *a = SafeArrayCreateVector(VT_UNKNOWN, 0, 1);
        if (!a) return E_OUTOFMEMORY;
        ITextRangeProvider *r = nullptr;
        HRESULT hr = makeRange(start, end, &r);
        if (FAILED(hr)) { SafeArrayDestroy(a); return hr; }
        LONG i = 0;
        SafeArrayPutElement(a, &i, r);
        r->Release();
        *out = a;
        return S_OK;
    }
    // ISelectionProvider::GetSelection: the selected children.
    std::vector<int32_t> selected;
    for (int32_t c : n->children) {
        Node *cn = root_->node(c);
        if (cn && (cn->flags & CUIA_SELECTED)) selected.push_back(c);
    }
    SAFEARRAY *a = SafeArrayCreateVector(VT_UNKNOWN, 0, static_cast<ULONG>(selected.size()));
    if (!a) return E_OUTOFMEMORY;
    LONG i = 0;
    for (int32_t c : selected) {
        Provider *p = root_->provider(c);
        if (!p) continue;
        IRawElementProviderSimple *s = nullptr;
        p->QueryInterface(__uuidof(IRawElementProviderSimple), reinterpret_cast<void **>(&s));
        SafeArrayPutElement(a, &i, s);
        s->Release();
        i++;
    }
    *out = a;
    return S_OK;
}

// MARK: - Text ranges

// A private IID that only our ranges answer, so a foreign ITextRangeProvider can be told apart
// without RTTI.
static const GUID IID_CUIATextRange = {0x6f1d2c4a, 0x9b3e, 0x4c21, {0x8a, 0x5d, 0x3e, 0x7f, 0x11, 0x22, 0x33, 0x44}};

class TextRange : public ITextRangeProvider {
public:
    TextRange(Provider *owner, int32_t start, int32_t end) : owner_(owner), start_(start), end_(end) { owner_->AddRef(); clamp(); }
    ~TextRange() { owner_->Release(); }

    /// The TextRange behind a range another call handed us, or null for a foreign one.
    static TextRange *from(ITextRangeProvider *other) {
        if (!other) return nullptr;
        void *p = nullptr;
        if (FAILED(other->QueryInterface(IID_CUIATextRange, &p)) || !p) return nullptr;
        TextRange *r = static_cast<TextRange *>(p);
        r->Release();           // the caller holds `other` for the duration of the call
        return r;
    }

    STDMETHODIMP QueryInterface(REFIID riid, void **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (riid == __uuidof(IUnknown) || riid == __uuidof(ITextRangeProvider)) { *out = static_cast<ITextRangeProvider *>(this); AddRef(); return S_OK; }
        if (riid == IID_CUIATextRange) { *out = this; AddRef(); return S_OK; }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
    STDMETHODIMP_(ULONG) Release() override { ULONG n = InterlockedDecrement(&refs_); if (n == 0) delete this; return n; }

    STDMETHODIMP Clone(ITextRangeProvider **out) override { if (!out) return E_POINTER; *out = new TextRange(owner_, start_, end_); return S_OK; }
    STDMETHODIMP Compare(ITextRangeProvider *other, BOOL *out) override {
        if (!out) return E_POINTER;
        TextRange *o = TextRange::from(other);
        *out = o && o->owner_->id() == owner_->id() && o->start_ == start_ && o->end_ == end_;
        return S_OK;
    }
    STDMETHODIMP CompareEndpoints(TextPatternRangeEndpoint endpoint, ITextRangeProvider *other, TextPatternRangeEndpoint targetEndpoint, int *out) override {
        if (!out) return E_POINTER;
        TextRange *o = TextRange::from(other);
        if (!o) return E_INVALIDARG;
        int32_t a = endpoint == TextPatternRangeEndpoint_Start ? start_ : end_;
        int32_t b = targetEndpoint == TextPatternRangeEndpoint_Start ? o->start_ : o->end_;
        *out = a < b ? -1 : a > b ? 1 : 0;
        return S_OK;
    }
    STDMETHODIMP ExpandToEnclosingUnit(TextUnit unit) override {
        const std::wstring &t = text();
        switch (unit) {
        case TextUnit_Character:
            end_ = start_ < static_cast<int32_t>(t.size()) ? start_ + 1 : start_;
            break;
        case TextUnit_Format:
        case TextUnit_Word: {
            int32_t s = start_;
            while (s > 0 && !iswspace(t[s - 1])) s--;
            int32_t e = start_;
            while (e < static_cast<int32_t>(t.size()) && !iswspace(t[e])) e++;
            while (e < static_cast<int32_t>(t.size()) && iswspace(t[e])) e++;      // a word carries its trailing spaces
            start_ = s; end_ = e;
            break;
        }
        case TextUnit_Line:
        case TextUnit_Paragraph: {
            int32_t s = start_;
            while (s > 0 && t[s - 1] != L'\n') s--;
            int32_t e = start_;
            while (e < static_cast<int32_t>(t.size()) && t[e] != L'\n') e++;
            if (e < static_cast<int32_t>(t.size())) e++;
            start_ = s; end_ = e;
            break;
        }
        default:
            start_ = 0; end_ = static_cast<int32_t>(t.size());
            break;
        }
        return S_OK;
    }
    STDMETHODIMP FindAttribute(TEXTATTRIBUTEID, VARIANT, BOOL, ITextRangeProvider **out) override { if (!out) return E_POINTER; *out = nullptr; return S_OK; }
    STDMETHODIMP FindText(BSTR needle, BOOL backward, BOOL ignoreCase, ITextRangeProvider **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (!needle) return E_INVALIDARG;
        std::wstring hay = text().substr(start_, end_ - start_), n = needle;
        if (ignoreCase) { for (auto &c : hay) c = towlower(c); for (auto &c : n) c = towlower(c); }
        size_t pos = backward ? hay.rfind(n) : hay.find(n);
        if (pos == std::wstring::npos) return S_OK;
        *out = new TextRange(owner_, start_ + static_cast<int32_t>(pos), start_ + static_cast<int32_t>(pos + n.size()));
        return S_OK;
    }
    STDMETHODIMP GetAttributeValue(TEXTATTRIBUTEID attribute, VARIANT *out) override {
        if (!out) return E_POINTER;
        VariantInit(out);
        if (attribute == UIA_IsReadOnlyAttributeId) {
            Node *n = owner_->node();
            out->vt = VT_BOOL;
            out->boolVal = n && (n->flags & CUIA_SETTABLE) ? VARIANT_FALSE : VARIANT_TRUE;
            return S_OK;
        }
        IUnknown *ns = nullptr;
        UiaGetReservedNotSupportedValue(&ns);
        out->vt = VT_UNKNOWN;
        out->punkVal = ns;
        return S_OK;
    }
    STDMETHODIMP GetBoundingRectangles(SAFEARRAY **out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        Node *n = owner_->node();
        if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
        SAFEARRAY *a = SafeArrayCreateVector(VT_R8, 0, 4);
        if (!a) return E_OUTOFMEMORY;
        double v[4] = {static_cast<double>(n->rect.left), static_cast<double>(n->rect.top),
                       static_cast<double>(n->rect.right - n->rect.left), static_cast<double>(n->rect.bottom - n->rect.top)};
        for (LONG i = 0; i < 4; i++) SafeArrayPutElement(a, &i, &v[i]);
        *out = a;
        return S_OK;
    }
    STDMETHODIMP GetEnclosingElement(IRawElementProviderSimple **out) override {
        if (!out) return E_POINTER;
        return owner_->QueryInterface(__uuidof(IRawElementProviderSimple), reinterpret_cast<void **>(out));
    }
    STDMETHODIMP GetText(int maxLength, BSTR *out) override {
        if (!out) return E_POINTER;
        std::wstring s = text().substr(start_, end_ - start_);
        if (maxLength >= 0 && static_cast<int>(s.size()) > maxLength) s.resize(maxLength);
        *out = toBSTR(s);
        return S_OK;
    }
    STDMETHODIMP Move(TextUnit unit, int count, int *out) override {
        if (!out) return E_POINTER;
        int moved = 0;
        int32_t len = static_cast<int32_t>(text().size());
        // Degenerate the range at its start, step it, then expand to the unit.
        bool degenerate = start_ == end_;
        end_ = start_;
        for (int i = 0; i < abs(count); i++) {
            int32_t before = start_;
            if (count > 0) { ExpandToEnclosingUnit(unit); start_ = end_; end_ = start_; }
            else { if (start_ > 0) start_--; ExpandToEnclosingUnit(unit); end_ = start_; }
            if (start_ == before || start_ < 0 || start_ > len) { start_ = before; end_ = before; break; }
            moved += count > 0 ? 1 : -1;
        }
        if (!degenerate) ExpandToEnclosingUnit(unit);
        *out = moved;
        return S_OK;
    }
    STDMETHODIMP MoveEndpointByUnit(TextPatternRangeEndpoint endpoint, TextUnit unit, int count, int *out) override {
        if (!out) return E_POINTER;
        int32_t len = static_cast<int32_t>(text().size());
        int32_t &p = endpoint == TextPatternRangeEndpoint_Start ? start_ : end_;
        int moved = 0;
        for (int i = 0; i < abs(count); i++) {
            int32_t before = p;
            if (unit == TextUnit_Character) p += count > 0 ? 1 : -1;
            else if (unit == TextUnit_Word || unit == TextUnit_Format) {
                TextRange probe(owner_, count > 0 ? p : (p > 0 ? p - 1 : 0), count > 0 ? p : (p > 0 ? p - 1 : 0));
                probe.ExpandToEnclosingUnit(unit);
                p = count > 0 ? probe.end_ : probe.start_;
            } else {
                TextRange probe(owner_, count > 0 ? p : (p > 0 ? p - 1 : 0), count > 0 ? p : (p > 0 ? p - 1 : 0));
                probe.ExpandToEnclosingUnit(unit);
                p = count > 0 ? probe.end_ : probe.start_;
            }
            if (p < 0) p = 0;
            if (p > len) p = len;
            if (p == before) break;
            moved += count > 0 ? 1 : -1;
        }
        if (start_ > end_) { if (endpoint == TextPatternRangeEndpoint_Start) end_ = start_; else start_ = end_; }
        *out = moved;
        return S_OK;
    }
    STDMETHODIMP MoveEndpointByRange(TextPatternRangeEndpoint endpoint, ITextRangeProvider *other, TextPatternRangeEndpoint targetEndpoint) override {
        TextRange *o = TextRange::from(other);
        if (!o) return E_INVALIDARG;
        int32_t v = targetEndpoint == TextPatternRangeEndpoint_Start ? o->start_ : o->end_;
        if (endpoint == TextPatternRangeEndpoint_Start) { start_ = v; if (end_ < start_) end_ = start_; }
        else { end_ = v; if (start_ > end_) start_ = end_; }
        return S_OK;
    }
    STDMETHODIMP Select() override { return S_OK; }
    STDMETHODIMP AddToSelection() override { return UIA_E_INVALIDOPERATION; }
    STDMETHODIMP RemoveFromSelection() override { return UIA_E_INVALIDOPERATION; }
    STDMETHODIMP ScrollIntoView(BOOL) override { return S_OK; }
    STDMETHODIMP GetChildren(SAFEARRAY **out) override {
        if (!out) return E_POINTER;
        *out = SafeArrayCreateVector(VT_UNKNOWN, 0, 0);
        return *out ? S_OK : E_OUTOFMEMORY;
    }

private:
    const std::wstring &text() {
        Node *n = owner_->node();
        static const std::wstring empty;
        return n ? n->value : empty;
    }
    void clamp() {
        int32_t len = static_cast<int32_t>(text().size());
        if (start_ < 0) start_ = 0;
        if (end_ < 0) end_ = 0;
        if (start_ > len) start_ = len;
        if (end_ > len) end_ = len;
        if (end_ < start_) end_ = start_;
    }

    Provider *owner_;
    int32_t start_, end_;
    ULONG refs_ = 1;
};

HRESULT Provider::makeRange(int32_t start, int32_t end, ITextRangeProvider **out) {
    if (!out) return E_POINTER;
    *out = new TextRange(this, start, end);
    return S_OK;
}

STDMETHODIMP Provider::GetVisibleRanges(SAFEARRAY **out) {
    if (!out) return E_POINTER;
    *out = nullptr;
    Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    SAFEARRAY *a = SafeArrayCreateVector(VT_UNKNOWN, 0, 1);
    if (!a) return E_OUTOFMEMORY;
    ITextRangeProvider *r = nullptr;
    makeRange(0, static_cast<int32_t>(n->value.size()), &r);
    LONG i = 0;
    SafeArrayPutElement(a, &i, r);
    r->Release();
    *out = a;
    return S_OK;
}
STDMETHODIMP Provider::RangeFromChild(IRawElementProviderSimple *, ITextRangeProvider **out) { return get_DocumentRange(out); }
STDMETHODIMP Provider::RangeFromPoint(UiaPoint, ITextRangeProvider **out) {
    if (!out) return E_POINTER;
    return makeRange(0, 0, out);
}
STDMETHODIMP Provider::get_DocumentRange(ITextRangeProvider **out) {
    if (!out) return E_POINTER;
    *out = nullptr;
    Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    return makeRange(0, static_cast<int32_t>(n->value.size()), out);
}

// MARK: - Patterns and properties

STDMETHODIMP Provider::GetPatternProvider(PATTERNID patternId, IUnknown **out) {
    if (!out) return E_POINTER;
    *out = nullptr;
    Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    switch (patternId) {
    case UIA_InvokePatternId: if (n->flags & CUIA_HAS_INVOKE) *out = static_cast<IInvokeProvider *>(this); break;
    case UIA_TogglePatternId: if (n->flags & CUIA_HAS_TOGGLE) *out = static_cast<IToggleProvider *>(this); break;
    case UIA_ValuePatternId: if (n->flags & CUIA_HAS_VALUE) *out = static_cast<IValueProvider *>(this); break;
    case UIA_RangeValuePatternId: if (n->flags & CUIA_HAS_RANGE) *out = static_cast<IRangeValueProvider *>(this); break;
    case UIA_SelectionPatternId: if (n->flags & CUIA_HAS_SELECTION) *out = static_cast<ISelectionProvider *>(this); break;
    case UIA_SelectionItemPatternId: if (n->flags & CUIA_HAS_SELECTION_ITEM) *out = static_cast<ISelectionItemProvider *>(this); break;
    case UIA_TextPatternId: if (n->flags & CUIA_HAS_TEXT) *out = static_cast<ITextProvider *>(this); break;
    default: break;
    }
    if (*out) AddRef();
    return S_OK;
}

STDMETHODIMP Provider::GetPropertyValue(PROPERTYID propertyId, VARIANT *out) {
    if (!out) return E_POINTER;
    VariantInit(out);
    Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    auto setBool = [&](bool v) { out->vt = VT_BOOL; out->boolVal = v ? VARIANT_TRUE : VARIANT_FALSE; };
    auto setStr = [&](const std::wstring &s) { out->vt = VT_BSTR; out->bstrVal = toBSTR(s); };
    auto setInt = [&](int v) { out->vt = VT_I4; out->lVal = v; };
    switch (propertyId) {
    case UIA_ControlTypePropertyId: setInt(n->controlType); break;
    case UIA_NamePropertyId: if (n->hasName) setStr(n->name); break;
    case UIA_HelpTextPropertyId: if (n->hasHelp) setStr(n->help); break;
    case UIA_AutomationIdPropertyId: if (n->hasAutomationId) setStr(n->automationId); else setStr(L"AppKitWin." + std::to_wstring(n->id)); break;
    case UIA_LocalizedControlTypePropertyId: if (n->hasItemType) setStr(n->itemType); break;
    case UIA_ItemTypePropertyId: if (n->hasItemType) setStr(n->itemType); break;
    case UIA_IsEnabledPropertyId: setBool(n->flags & CUIA_ENABLED); break;
    case UIA_IsKeyboardFocusablePropertyId: setBool((n->flags & CUIA_FOCUSABLE) && (n->flags & CUIA_ENABLED)); break;
    case UIA_HasKeyboardFocusPropertyId: setBool(n->flags & CUIA_FOCUSED); break;
    case UIA_IsControlElementPropertyId: setBool(true); break;
    case UIA_IsContentElementPropertyId: setBool(n->flags & CUIA_IS_CONTENT); break;
    case UIA_IsOffscreenPropertyId: setBool(n->rect.right <= n->rect.left || n->rect.bottom <= n->rect.top); break;
    case UIA_IsPasswordPropertyId: setBool(n->flags & CUIA_PASSWORD); break;
    case UIA_FrameworkIdPropertyId: setStr(L"AppKitWin"); break;
    case UIA_ProviderDescriptionPropertyId: setStr(L"AppKitWin NSAccessibility provider"); break;
    case UIA_ClassNamePropertyId: setStr(L"AppKitWin.NSView"); break;
    case UIA_NativeWindowHandlePropertyId: if (isRoot() && root_->hwnd) setInt(static_cast<int>(reinterpret_cast<intptr_t>(root_->hwnd))); break;
    case UIA_ValueValuePropertyId: if (n->flags & CUIA_HAS_VALUE) setStr(n->value); break;
    case UIA_ValueIsReadOnlyPropertyId: if (n->flags & CUIA_HAS_VALUE) setBool(!((n->flags & CUIA_SETTABLE) && (n->flags & CUIA_ENABLED))); break;
    case UIA_ToggleToggleStatePropertyId: if (n->flags & CUIA_HAS_TOGGLE) setInt(n->toggleState == 1 ? ToggleState_On : n->toggleState == 2 ? ToggleState_Indeterminate : ToggleState_Off); break;
    case UIA_RangeValueValuePropertyId: if (n->flags & CUIA_HAS_RANGE) { out->vt = VT_R8; out->dblVal = n->rangeValue; } break;
    case UIA_RangeValueMinimumPropertyId: if (n->flags & CUIA_HAS_RANGE) { out->vt = VT_R8; out->dblVal = n->rangeMin; } break;
    case UIA_RangeValueMaximumPropertyId: if (n->flags & CUIA_HAS_RANGE) { out->vt = VT_R8; out->dblVal = n->rangeMax; } break;
    case UIA_SelectionItemIsSelectedPropertyId: if (n->flags & CUIA_HAS_SELECTION_ITEM) setBool(n->flags & CUIA_SELECTED); break;
    case UIA_SelectionCanSelectMultiplePropertyId: if (n->flags & CUIA_HAS_SELECTION) setBool(n->flags & CUIA_CAN_SELECT_MULTIPLE); break;
    default: break;
    }
    return S_OK;
}

STDMETHODIMP Provider::Navigate(NavigateDirection direction, IRawElementProviderFragment **out) {
    if (!out) return E_POINTER;
    *out = nullptr;
    Node *n = node();
    if (!n) return UIA_E_ELEMENTNOTAVAILABLE;
    int32_t target = -1;
    switch (direction) {
    case NavigateDirection_Parent: target = n->parent; break;
    case NavigateDirection_FirstChild: if (!n->children.empty()) target = n->children.front(); break;
    case NavigateDirection_LastChild: if (!n->children.empty()) target = n->children.back(); break;
    case NavigateDirection_NextSibling:
    case NavigateDirection_PreviousSibling: {
        if (n->parent < 0) break;
        Node *p = root_->node(n->parent);
        if (!p) break;
        for (size_t i = 0; i < p->children.size(); i++) {
            if (p->children[i] != id_) continue;
            if (direction == NavigateDirection_NextSibling && i + 1 < p->children.size()) target = p->children[i + 1];
            if (direction == NavigateDirection_PreviousSibling && i > 0) target = p->children[i - 1];
            break;
        }
        break;
    }
    default: break;
    }
    if (target < 0) return S_OK;
    Provider *p = root_->provider(target);
    if (!p) return S_OK;
    return p->QueryInterface(__uuidof(IRawElementProviderFragment), reinterpret_cast<void **>(out));
}

} // namespace

// MARK: - Root

void CUIARoot::ensureFresh() {
    if (!stale || refreshing || destroyed) return;
    refreshing = true;
    if (callbacks.refresh) callbacks.refresh(callbacks.context);
    refreshing = false;
    stale = false;
}

Provider *CUIARoot::provider(int32_t id) {
    if (destroyed) return nullptr;
    auto it = providers.find(id);
    if (it != providers.end()) return it->second;
    if (nodes.find(id) == nodes.end()) return nullptr;
    Provider *p = new Provider(this, id);
    providers[id] = p;
    return p;
}

int32_t CUIARoot::focused() {
    ensureFresh();
    for (auto &kv : nodes) if (kv.second.flags & CUIA_FOCUSED) return kv.first;
    return -1;
}

int32_t CUIARoot::hitTest(int32_t id, double x, double y) {
    Node *n = node(id);
    if (!n) return -1;
    for (auto it = n->children.rbegin(); it != n->children.rend(); ++it) {
        int32_t hit = hitTest(*it, x, y);
        if (hit >= 0) return hit;
    }
    if (x >= n->rect.left && x < n->rect.right && y >= n->rect.top && y < n->rect.bottom) return id;
    return -1;
}

// MARK: - C interface

CUIARoot *cuia_root_create(void *hwnd, const CUIACallbacks *callbacks) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    CUIARoot *root = new CUIARoot();
    root->hwnd = static_cast<HWND>(hwnd);
    if (callbacks) root->callbacks = *callbacks;
    return root;
}

void cuia_root_set_nodes(CUIARoot *root, const CUIANode *nodes, int32_t count) {
    if (!root || root->destroyed) return;
    if (root->settingNodes) {
        // Re-entered from a provider callback (UiaDisconnectProvider asks the provider for
        // its runtime id, which may refresh): the outer call finishes with its snapshot
        // and the next request refreshes again.
        root->stale = true;
        return;
    }
    root->settingNodes = true;
    std::map<int32_t, Node> fresh;
    int32_t newRoot = -1;
    for (int32_t i = 0; i < count; i++) {
        const CUIANode &src = nodes[i];
        Node n;
        n.id = src.id;
        n.parent = src.parent;
        n.controlType = src.controlType;
        n.name = copyString(src.name, n.hasName);
        n.value = copyString(src.value, n.hasValue);
        n.help = copyString(src.help, n.hasHelp);
        n.automationId = copyString(src.automationId, n.hasAutomationId);
        n.itemType = copyString(src.itemType, n.hasItemType);
        n.rect.left = src.left; n.rect.top = src.top; n.rect.right = src.right; n.rect.bottom = src.bottom;
        n.flags = src.flags;
        n.rangeValue = src.rangeValue; n.rangeMin = src.rangeMin; n.rangeMax = src.rangeMax; n.rangeStep = src.rangeStep;
        n.toggleState = src.toggleState;
        n.selStart = src.textSelectionStart; n.selLength = src.textSelectionLength;
        if (i == 0) newRoot = n.id;
        fresh[n.id] = n;
    }
    for (auto &kv : fresh) {
        if (kv.second.parent < 0) continue;
        auto p = fresh.find(kv.second.parent);
        if (p != fresh.end()) p->second.children.push_back(kv.first);
    }
    // Children keep the array's order (the map iterates by id, so re-sort by position).
    std::map<int32_t, int32_t> position;
    for (int32_t i = 0; i < count; i++) position[nodes[i].id] = i;
    for (auto &kv : fresh) {
        auto &c = kv.second.children;
        std::sort(c.begin(), c.end(), [&](int32_t a, int32_t b) { return position[a] < position[b]; });
    }
    // Providers of nodes that vanished are taken out of the table first; they are
    // disconnected and released only once the tables are consistent, since
    // UiaDisconnectProvider calls back into the provider (and anything it reaches).
    std::vector<Provider *> vanished;
    for (auto it = root->providers.begin(); it != root->providers.end();) {
        if (fresh.find(it->first) == fresh.end()) {
            vanished.push_back(it->second);
            it = root->providers.erase(it);
        } else {
            ++it;
        }
    }
    root->nodes.swap(fresh);
    root->rootId = newRoot;
    root->stale = false;
    for (Provider *p : vanished) {
        if (root->hwnd) UiaDisconnectProvider(static_cast<IRawElementProviderSimple *>(p));
        p->detach();
        p->Release();
    }
    root->settingNodes = false;
}

void cuia_root_invalidate(CUIARoot *root) { if (root) root->stale = true; }

intptr_t cuia_root_handle_getobject(CUIARoot *root, uintptr_t wParam, intptr_t lParam) {
    if (!root || root->destroyed) return 0;
    if (static_cast<LONG>(lParam) != UiaRootObjectId) return 0;
    root->ensureFresh();
    Provider *p = root->provider(root->rootId);
    if (!p) return 0;
    return UiaReturnRawElementProvider(root->hwnd, static_cast<WPARAM>(wParam), static_cast<LPARAM>(lParam), static_cast<IRawElementProviderSimple *>(p));
}

static Provider *providerForEvent(CUIARoot *root, int32_t id) {
    if (!root || root->destroyed || !root->hwnd) return nullptr;
    root->ensureFresh();
    return root->provider(id);
}

void cuia_root_raise_focus(CUIARoot *root, int32_t id) {
    Provider *p = providerForEvent(root, id);
    if (p) UiaRaiseAutomationEvent(static_cast<IRawElementProviderSimple *>(p), UIA_AutomationFocusChangedEventId);
}

void cuia_root_raise_property_changed(CUIARoot *root, int32_t id, int32_t which) {
    Provider *p = providerForEvent(root, id);
    if (!p) return;
    Node *n = root->node(id);
    if (!n) return;
    VARIANT empty, value;
    VariantInit(&empty);
    VariantInit(&value);
    IRawElementProviderSimple *s = static_cast<IRawElementProviderSimple *>(p);
    if (which == 1) {
        value.vt = VT_BSTR; value.bstrVal = toBSTR(n->name);
        UiaRaiseAutomationPropertyChangedEvent(s, UIA_NamePropertyId, empty, value);
    } else if (which == 2) {
        UiaRaiseAutomationEvent(s, UIA_Selection_InvalidatedEventId);
        for (int32_t c : n->children) {
            Node *cn = root->node(c);
            if (!cn || !(cn->flags & CUIA_SELECTED)) continue;
            Provider *cp = root->provider(c);
            if (cp) UiaRaiseAutomationEvent(static_cast<IRawElementProviderSimple *>(cp), UIA_SelectionItem_ElementSelectedEventId);
        }
    } else if (n->flags & CUIA_HAS_TOGGLE) {
        value.vt = VT_I4; value.lVal = n->toggleState == 1 ? ToggleState_On : n->toggleState == 2 ? ToggleState_Indeterminate : ToggleState_Off;
        UiaRaiseAutomationPropertyChangedEvent(s, UIA_ToggleToggleStatePropertyId, empty, value);
    } else if (n->flags & CUIA_HAS_RANGE) {
        value.vt = VT_R8; value.dblVal = n->rangeValue;
        UiaRaiseAutomationPropertyChangedEvent(s, UIA_RangeValueValuePropertyId, empty, value);
    } else {
        value.vt = VT_BSTR; value.bstrVal = toBSTR(n->value);
        UiaRaiseAutomationPropertyChangedEvent(s, UIA_ValueValuePropertyId, empty, value);
        if (n->flags & CUIA_HAS_TEXT) UiaRaiseAutomationEvent(s, UIA_Text_TextChangedEventId);
    }
    VariantClear(&value);
}

void cuia_root_raise_structure_changed(CUIARoot *root, int32_t id) {
    Provider *p = providerForEvent(root, id);
    if (p) UiaRaiseStructureChangedEvent(static_cast<IRawElementProviderSimple *>(p), StructureChangeType_ChildrenInvalidated, nullptr, 0);
}

void cuia_root_destroy(CUIARoot *root) {
    if (!root) return;
    root->destroyed = true;
    std::map<int32_t, Provider *> providers;
    providers.swap(root->providers);
    for (auto &kv : providers) {
        if (root->hwnd) UiaDisconnectProvider(static_cast<IRawElementProviderSimple *>(kv.second));
        kv.second->detach();
        kv.second->Release();
    }
    if (root->hwnd) UiaReturnRawElementProvider(root->hwnd, 0, 0, nullptr);
    delete root;
}

bool cuia_clients_are_listening(void) { return UiaClientsAreListening() ? true : false; }

static bool writeString(const std::wstring &s, uint16_t *buffer, int32_t capacity) {
    if (!buffer || capacity <= 0) return false;
    size_t n = s.size() < static_cast<size_t>(capacity - 1) ? s.size() : static_cast<size_t>(capacity - 1);
    memcpy(buffer, s.c_str(), n * sizeof(wchar_t));
    buffer[n] = 0;
    return true;
}

bool cuia_root_debug_property(CUIARoot *root, int32_t id, int32_t propertyId, uint16_t *buffer, int32_t capacity) {
    if (!root) return false;
    root->ensureFresh();
    Provider *p = root->provider(id);
    if (!p) return false;
    VARIANT v;
    VariantInit(&v);
    if (FAILED(p->GetPropertyValue(propertyId, &v))) return false;
    std::wstring s;
    switch (v.vt) {
    case VT_BSTR: s = v.bstrVal ? v.bstrVal : L""; break;
    case VT_BOOL: s = v.boolVal ? L"true" : L"false"; break;
    case VT_I4: s = std::to_wstring(v.lVal); break;
    case VT_R8: { wchar_t buf[64]; swprintf(buf, 64, L"%g", v.dblVal); s = buf; break; }
    default: VariantClear(&v); return false;
    }
    VariantClear(&v);
    return writeString(s, buffer, capacity);
}

int32_t cuia_root_debug_child_count(CUIARoot *root, int32_t id) {
    if (!root) return -1;
    root->ensureFresh();
    Provider *p = root->provider(id);
    if (!p) return -1;
    int32_t count = 0;
    IRawElementProviderFragment *child = nullptr;
    if (FAILED(p->Navigate(NavigateDirection_FirstChild, &child))) return -1;
    while (child) {
        count++;
        IRawElementProviderFragment *next = nullptr;
        child->Navigate(NavigateDirection_NextSibling, &next);
        child->Release();
        child = next;
    }
    return count;
}

bool cuia_root_debug_has_pattern(CUIARoot *root, int32_t id, int32_t patternId) {
    if (!root) return false;
    root->ensureFresh();
    Provider *p = root->provider(id);
    if (!p) return false;
    IUnknown *u = nullptr;
    if (FAILED(p->GetPatternProvider(patternId, &u)) || !u) return false;
    u->Release();
    return true;
}

bool cuia_root_debug_text(CUIARoot *root, int32_t id, uint16_t *buffer, int32_t capacity) {
    if (!root) return false;
    root->ensureFresh();
    Provider *p = root->provider(id);
    if (!p) return false;
    ITextRangeProvider *r = nullptr;
    if (FAILED(p->get_DocumentRange(&r)) || !r) return false;
    BSTR text = nullptr;
    r->GetText(-1, &text);
    r->Release();
    std::wstring s = text ? text : L"";
    if (text) SysFreeString(text);
    return writeString(s, buffer, capacity);
}

template <typename I>
static I *patternOf(CUIARoot *root, int32_t id, PATTERNID pattern) {
    if (!root) return nullptr;
    root->ensureFresh();
    Provider *p = root->provider(id);
    if (!p) return nullptr;
    IUnknown *u = nullptr;
    if (FAILED(p->GetPatternProvider(pattern, &u)) || !u) return nullptr;
    I *i = nullptr;
    u->QueryInterface(__uuidof(I), reinterpret_cast<void **>(&i));
    u->Release();
    return i;
}

bool cuia_debug_invoke(CUIARoot *root, int32_t id) {
    IInvokeProvider *p = patternOf<IInvokeProvider>(root, id, UIA_InvokePatternId);
    if (!p) return false;
    HRESULT hr = p->Invoke();
    p->Release();
    return SUCCEEDED(hr);
}

bool cuia_debug_toggle(CUIARoot *root, int32_t id) {
    IToggleProvider *p = patternOf<IToggleProvider>(root, id, UIA_TogglePatternId);
    if (!p) return false;
    HRESULT hr = p->Toggle();
    p->Release();
    return SUCCEEDED(hr);
}

bool cuia_debug_set_value(CUIARoot *root, int32_t id, const uint16_t *value) {
    IValueProvider *p = patternOf<IValueProvider>(root, id, UIA_ValuePatternId);
    if (!p) return false;
    HRESULT hr = p->SetValue(reinterpret_cast<LPCWSTR>(value));
    p->Release();
    return SUCCEEDED(hr);
}

bool cuia_debug_set_range_value(CUIARoot *root, int32_t id, double value) {
    IRangeValueProvider *p = patternOf<IRangeValueProvider>(root, id, UIA_RangeValuePatternId);
    if (!p) return false;
    HRESULT hr = p->SetValue(value);
    p->Release();
    return SUCCEEDED(hr);
}

bool cuia_debug_set_focus(CUIARoot *root, int32_t id) {
    if (!root) return false;
    root->ensureFresh();
    Provider *p = root->provider(id);
    if (!p) return false;
    return SUCCEEDED(p->SetFocus());
}
