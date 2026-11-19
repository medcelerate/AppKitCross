# ADR-0047: Input methods (IME) on Windows and Linux

Date: 2026-11-18. Status: accepted.

## Context

Chinese, Japanese and Korean users type through an input method: keystrokes build a
composition (marked text) that the input method converts and then commits. On macOS the
text view is an `NSTextInputClient`; the input method calls `setMarkedText` for the
composition, `insertText` to commit and `firstRect(forCharacterRange:)` to place its
candidate window, and `NSTextInputContext` decides which client gets the keyboard.

The port had the client half (`NSTextView` keeps marked text inline and underlines it) and a
first IMM32 (`WM_IME_*`) path on Windows, but `NSTextInputContext` was a generated stub
(21 `unimplemented()` sites), `NSView.inputContext` stopped there, Text Services Framework
input (draft PR 58) did not compose, and Linux had no input method support at all. Without
it, an unmodified Mac app cannot be shipped to these users.

## Decision

### One input method layer in the core

`NSTextInputContext` is hand-written (`Sources/AppKit/Core/NSTextInputContext.swift`).
`NSView.inputContext` makes one for any view that is an `NSTextInputClient` and keeps it.
The key window's first responder owns the input method: `NSWindow.makeFirstResponder`,
`becomeKey` and `resignKey` call `activate()`/`deactivate()`, so `current` is that context,
as on macOS. `discardMarkedText()` tells the platform to drop its composition and has the
client keep the marked text (`unmarkText()`); `handleEvent(_:)` runs the key bindings into the
client (the platform input method already saw the key before it became an event);
`invalidateCharacterCoordinates()` and the scroll/selection notifications ask the platform to
read the caret rectangle again. The core reaches the window backend through a new
`PlatformWindow.textInputChanged(_:)` (default: ignored) with `.activated`, `.deactivated`,
`.textChanged`, `.selectionChanged`, `.layoutChanged` and `.discardComposition`. `NSText`
reports its own edits and selection changes; edits made by the input method are not echoed.
`keyboardInputSources`, `selectedKeyboardInputSource` and `localizedName(forInputSource:)`
stay `unimplemented()`: platform keyboard layouts and input methods have no macOS input source
identifiers.

`_TextInputSession` (`NSTextInputContext+Session.swift`) is what every backend drives. It
turns each platform protocol's edit into the calls a macOS input method makes:

- `setComposition` → `setMarkedText` with an attributed string whose underline style marks the
  clauses (`.single` for a clause, `.thick` for the clause being converted) and
  `markedClauseSegment` per clause, as macOS input methods send them; `commit` →
  `insertText`; `cancelComposition` → `setMarkedText("")`.
- `applyStoreEdit` (TSF): the store's new text is compared with the snapshot it was given; the
  changed span outside the composition is committed, the composition becomes marked text.
- `apply(TextInputV3State)` (Wayland): one `done` batch in the protocol's order (remove the
  preedit, delete surrounding text, commit, new preedit with its cursor; byte offsets in
  UTF-8 converted to UTF-16).
- `_XIMPreedit` (X11): the preedit string XIM's draw callbacks edit character by character,
  with each character's feedback (reverse or highlight = thick).
- `surroundingText`, `snapshot` (a window of 32k UTF-16 units around the selection, not the
  whole document per keystroke) and `caretRectInWindow` for the candidate window.

`NSTextView` keeps the clauses (`_markedClauses`) from the marked string's underline styles
(without any, the selected part of the marked text is the thick clause) and draws each clause
underlined in the text colour, 1 pt or 2 pt, with a 1 pt gap between clauses. A click in the
text view commits the composition (`discardMarkedText`), as on macOS.

### Windows: Text Services Framework, IMM32 as the fallback

`Sources/CTextServices` (continuing PR 58) is a C++ shim over TSF in the
`CUIAutomation`/`CWinAppServices` style: plain COM, no ATL or WRL.

- One `ITfThreadMgr` per thread (activated with the first window that needs it), a document
  manager and context per window, and an empty document manager that gets the focus when no
  text client has it, which turns the input method off for tables, buttons and the like.
  Each focus change is also recorded with `AssociateFocus(hwnd, …)`: TSF moves its focus by
  itself when the window gets `WM_SETFOCUS`, to the document manager associated with the
  window, and without the association that is none. The open state and conversion mode are
  the thread manager's own compartments (`QueryInterface(IID_ITfCompartmentMgr)`), not the
  global compartment manager.
- The `ITextStoreACP` keeps its own copy of the text around the selection (as Chromium's and
  Firefox's stores do). The window syncs it from the view (`cts_document_sync`, coalesced
  after the view's change notifications and refreshed before every lock), and the store tells
  TSF what changed (`OnTextChange`, `OnSelectionChange`, `OnLayoutChange`).
- Lock requests made while a lock is held are queued (`TS_S_ASYNC`) and granted after it;
  synchronous ones get `TS_E_SYNCHRONOUS`. When a lock in which the input method edited ends,
  the store hands the window the text, selection, composition and clauses at once, outside any
  lock; the window applies them to the view through `applyStoreEdit` and syncs back.
- `ITfContextOwnerCompositionSink` tracks the composition; `ITfTextEditSink::OnEndEdit` reads
  its display attributes (`GUID_PROP_ATTRIBUTE` → `ITfDisplayAttributeMgr`):
  `TF_ATTR_TARGET_CONVERTED`, `TF_ATTR_TARGET_NOTCONVERTED` or a bold line is the thick clause.
- `GetTextExt` answers from the client's `firstRect(forCharacterRange:)`, so the input method
  draws its own candidate window under the composition. `ITfUIElementSink` only reports the
  candidate count (shown, not suppressed).
- Key messages for the focused window are offered to `ITfKeystrokeMgr` in the message pump
  before `TranslateMessage` (keys TSF's own hook already took arrive as `VK_PROCESSKEY` and
  are skipped); what the input method takes never becomes an `NSEvent`.
- Deactivating a client detaches it before the composition is terminated, so the input
  method's final edit cannot land in the next field the reused field editor serves.

Without TSF (document creation fails, or `APPKITWIN_TSF=0`) the existing `WM_IME_*` path
handles composition through the same session, with clause attributes from `GCS_COMPATTR`; it
is off whenever TSF owns the window's input.

### Linux: text-input-v3 on Wayland, XIM on X11

- Wayland: `zwp_text_input_manager_v3`/`zwp_text_input_v3` (generated by
  `tools/linux/gen-wayland-protocols.sh` with the other protocols). The text input is enabled
  while the surface that has text-input focus belongs to a window whose first responder is a
  text client, and disabled otherwise; on `done` the batch goes through `apply`; after every
  change the client sends surrounding text, change cause, content type (password purpose and
  hidden text for `NSSecureTextField`) and the caret rectangle in surface coordinates, then
  `commit`. The compositor withholds the keys the input method takes.
- X11: `XOpenIM` with the user's locale (`XMODIFIERS` names the server: ibus and fcitx5 both
  serve XIM; LC_CTYPE falls back to C.UTF-8) and one input context per window. On-the-spot
  style (`XIMPreeditCallbacks`) when the input method offers it; otherwise Xlib's own input
  method (dead keys) in root-window style. Every event goes through `XFilterEvent` first;
  `Xutf8LookupString` gives committed text (`XLookupChars`, or a synthetic key press without a
  key code), which goes to the client with `insertText`. The context has the X focus only while
  a text client is active; `XNSpotLocation` follows the caret's baseline. XIM's variadic
  setup calls are static inline helpers in `Sources/CX11/shim.h`.

### Diagnostics

`APPKITWIN_TRACE_TEXTINPUT=1` prints one `[textinput]` line per step on stderr: context
activation, the thread's active text service with its open state and conversion mode (at
activation, on focus and whenever they change), text service profile switches, the thread
manager's focus changes, every key down offered to `ITfKeystrokeMgr` with its
`TestKeyDown` answer, `WM_INPUTLANGCHANGE`, `setMarkedText`/`insertText`/cancel with the text, the TSF store's edits, locks,
`GetTextExt` rectangles and candidate counts, the IMM composition strings, text-input-v3
batches and XIM preedit draws.

## Consequences

- `NSTextInputContext` has 3 members left `unimplemented()` (input source enumeration); the
  generated file is gone. `NSView.inputContext` is real.
- `NSTextField.currentEditor()` now answers the field editor; a non-Apple `currentEditor`
  property had shadowed it and `NSControl.currentEditor()` returned nil (NSComboBox, the
  search field cell and SwiftUI's focus binding now call the method).
- Host tests (`TextInputMethodTests`, 13) drive scripted compositions on `NSTextView` and an
  `NSTextField`'s field editor (Japanese conversion and commit, cancel, Korean syllables,
  clauses), context activation across focus changes, TSF store edits (including a commit and a
  new composition in one edit, and reconversion), text-input-v3 batches with UTF-8 offsets,
  surrounding text, and the XIM preedit buffer. `X11InputMethodTests` checks the input context
  and `Xutf8LookupString` under Xvfb. `tools/linux/ime-e2e.sh` runs ibus-libpinyin over XIM
  into TextEdit in the Linux image: "nihao" composes inline (underlined, candidate window
  under it), Space commits 你好. There, Escape cleared the engine's buffer without ibus sending
  the empty preedit draw, so the last preedit stayed marked until the next keystroke replaced
  it (the engine's behaviour; ibus-x11 does send draw("") and done when a preedit is hidden).
  CI has no input method on any platform, so composition
  with a real input method is checked by hand (the PR's PC checklist; ibus or fcitx5 on Linux).
- Not covered: reconversion started from the application, `GetACPFromPoint` (clicks inside the
  composition), TSF text attributes and input scopes, the Windows emoji panel's own checks,
  XIM's status area and IM server restarts (`XRegisterIMInstantiateCallback`), text-input-v1/v2
  compositors, and vertical text.
