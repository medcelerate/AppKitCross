// C interface over UI Automation's provider side (ADR-0013).
//
// A window hands the shim a flat snapshot of its accessibility tree (CUIANode records,
// parents before children) and answers WM_GETOBJECT through it; the shim keeps one COM
// provider object per node (IRawElementProviderSimple, IRawElementProviderFragment, the
// FragmentRoot on the window, and the Invoke, Toggle, Value, RangeValue, Selection,
// SelectionItem and Text patterns) so UI Automation clients (Narrator, Accessibility
// Insights, inspect.exe) see the same identities across snapshots. Actions come back
// through the callbacks; events go out with UiaRaise*Event.
//
// The providers opt into COM threading, so every callback arrives on the thread that
// created the root (the UI thread, an STA).
#ifndef CUIA_H
#define CUIA_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CUIARoot CUIARoot;

enum {
    CUIA_ENABLED = 1 << 0,
    CUIA_FOCUSABLE = 1 << 1,
    CUIA_FOCUSED = 1 << 2,
    CUIA_SELECTED = 1 << 3,
    /// The value can be set through the Value or RangeValue pattern.
    CUIA_SETTABLE = 1 << 4,
    CUIA_MULTILINE = 1 << 5,
    CUIA_HAS_INVOKE = 1 << 6,
    CUIA_HAS_TOGGLE = 1 << 7,
    CUIA_HAS_VALUE = 1 << 8,
    CUIA_HAS_RANGE = 1 << 9,
    CUIA_HAS_SELECTION_ITEM = 1 << 10,
    CUIA_HAS_SELECTION = 1 << 11,
    CUIA_HAS_TEXT = 1 << 12,
    /// IsContentElement (everything is a control element).
    CUIA_IS_CONTENT = 1 << 13,
    CUIA_CAN_SELECT_MULTIPLE = 1 << 14,
    CUIA_PASSWORD = 1 << 15,
};

/// One element. Strings are UTF-16, NUL-terminated, and may be NULL; the shim copies
/// them during cuia_root_set_nodes. Rectangles are screen pixels.
typedef struct CUIANode {
    int32_t id;
    int32_t parent;                 // -1 for the root
    int32_t controlType;            // a UIA_*ControlTypeId
    const uint16_t *name;
    const uint16_t *value;
    const uint16_t *help;
    const uint16_t *automationId;
    const uint16_t *itemType;       // ItemType / LocalizedControlType hint (role description), optional
    int32_t left, top, right, bottom;
    uint32_t flags;
    double rangeValue, rangeMin, rangeMax, rangeStep;
    int32_t toggleState;            // 0 off, 1 on, 2 indeterminate
    int32_t textSelectionStart;     // -1 when there is no selection
    int32_t textSelectionLength;
} CUIANode;

typedef struct CUIACallbacks {
    void *context;
    /// The snapshot is stale: push a new one with cuia_root_set_nodes before returning.
    void (*refresh)(void *context);
    bool (*invoke)(void *context, int32_t id);
    bool (*toggle)(void *context, int32_t id);
    bool (*setValue)(void *context, int32_t id, const uint16_t *value);
    bool (*setRangeValue)(void *context, int32_t id, double value);
    /// mode: 0 selects the element alone, 1 adds it to the selection, 2 removes it.
    bool (*select)(void *context, int32_t id, int32_t mode);
    bool (*setFocus)(void *context, int32_t id);
} CUIACallbacks;

/// Creates the provider root for a window. `hwnd` may be NULL for tests (no host
/// provider, no events).
CUIARoot *cuia_root_create(void *hwnd, const CUIACallbacks *callbacks);
/// Replaces the snapshot. `nodes[0]` is the root; every parent precedes its children,
/// and children keep the array's order. Providers of nodes that vanished are
/// disconnected.
void cuia_root_set_nodes(CUIARoot *root, const CUIANode *nodes, int32_t count);
/// Marks the snapshot stale: the next provider call asks `refresh` first.
void cuia_root_invalidate(CUIARoot *root);
/// Answers WM_GETOBJECT. Returns 0 when the request is not for UI Automation (the
/// caller then falls back to DefWindowProc).
intptr_t cuia_root_handle_getobject(CUIARoot *root, uintptr_t wParam, intptr_t lParam);
/// Events; `which` for property changes: 0 value, 1 name, 2 selection.
void cuia_root_raise_focus(CUIARoot *root, int32_t id);
void cuia_root_raise_property_changed(CUIARoot *root, int32_t id, int32_t which);
void cuia_root_raise_structure_changed(CUIARoot *root, int32_t id);
/// Disconnects every provider and tells UI Automation the window is gone (WM_DESTROY).
void cuia_root_destroy(CUIARoot *root);
/// True when a UI Automation client is listening (events are worth raising).
bool cuia_clients_are_listening(void);

/// Test hooks: a property through IRawElementProviderSimple::GetPropertyValue, rendered
/// as text (numbers and booleans too); false when the provider has no value for it.
bool cuia_root_debug_property(CUIARoot *root, int32_t id, int32_t propertyId, uint16_t *buffer, int32_t capacity);
/// Test hook: the children of a node through IRawElementProviderFragment::Navigate.
int32_t cuia_root_debug_child_count(CUIARoot *root, int32_t id);
/// Test hook: whether the pattern provider for `patternId` exists on the node.
bool cuia_root_debug_has_pattern(CUIARoot *root, int32_t id, int32_t patternId);
/// Test hook: the text of the document range of the node's Text pattern.
bool cuia_root_debug_text(CUIARoot *root, int32_t id, uint16_t *buffer, int32_t capacity);
/// Test hooks: the pattern methods, as a client would call them (true on S_OK).
bool cuia_debug_invoke(CUIARoot *root, int32_t id);
bool cuia_debug_toggle(CUIARoot *root, int32_t id);
bool cuia_debug_set_value(CUIARoot *root, int32_t id, const uint16_t *value);
bool cuia_debug_set_range_value(CUIARoot *root, int32_t id, double value);
bool cuia_debug_set_focus(CUIARoot *root, int32_t id);

#ifdef __cplusplus
}
#endif
#endif
