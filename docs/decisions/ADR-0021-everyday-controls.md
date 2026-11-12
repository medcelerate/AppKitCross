# ADR-0021: The everyday controls — the date picker's graphical style and the token field's pop-up

Date: 2026-11-10. Status: accepted.

## Context

`NSSearchField`, `NSDatePicker`, `NSProgressIndicator`, `NSLevelIndicator`, `NSStepper`,
`NSPathControl` and `NSTokenField` are the controls most Mac applications use beyond
buttons, text fields and sliders, and they were still generated stubs. Each of them has a
cell where Apple has one, and two of them hide machinery that AppKit never exposes: the
date picker's calendar-and-clock style, and the token field, whose tokens are attachment
cells in the field editor's attributed string with a completion list under the caret. The
port's field editor is a plain `NSTextView` with a `String`, so neither comes for free.

## Decision

Every control is hand-written in `Sources/AppKit/Core` over its cell, draws itself with
`NSBezierPath` and the string drawing on every backend, and reports through
`NSAccessibility` with the roles AppKit uses (AXIncrementor, AXProgressIndicator /
AXBusyIndicator, AXLevelIndicator, AXTextField with the AXSearchField subrole,
AXDateTimeArea, AXGroup of AXButton children or AXPopUpButton for the path control).

- **Date picker, textual styles.** The cell asks `DateFormatter` for the locale's pattern
  of the selected elements (`yMd`, `jm`, ... through `dateFormat(fromTemplate:)`) and
  splits it into fields: a run of pattern letters is a field for a calendar component
  (the AM/PM marker is a field that toggles twelve hours), anything else is a literal.
  Each field is rendered by a formatter with just its run, laid out in order, and one of
  them is selected for Left/Right, Up/Down, the stepper and typed digits (a field moves on
  when it has all its digits, or no further digit could fit). Every change goes through
  `_propose`, which clamps to `minDate`/`maxDate` and lets the delegate's
  `validateProposedDateValue` adjust the date, then sends the action. The calendar, locale
  and time zone are one `Calendar` value applied to every computation.
- **Date picker, graphical style.** The cell draws the month calendar (header with the
  paging arrows, the calendar's weekday order, six rows of days, the selection as an
  accent disc, today ringed, the range tinted) and a clock face (hour, minute and, with
  seconds, a second hand; the time digitally below) directly in the cell frame, sized as
  AppKit's (160 × 150 and 120 × 150). Days are chosen by a click (Shift extends the range
  in range mode), months paged by the arrows or Page Up/Down, hands dragged (a point
  inside 50 % of the radius moves the hour hand, outside it the minute hand), and the
  arrows move a day or a week. The textual styles' calendar overlay
  (`presentsCalendarOverlay`) is stored, not shown.
- **Token field.** The tokens are the cell's value (`objectValue` is the array of
  represented objects; `stringValue` joins their display strings with the tokenizing
  character and splits on it). The cell draws the tokens from the leading edge of the
  text rect and reports what follows them as its text rect, so the field editor edits
  only the text after the tokens; `NSTextField` gained four small hooks for this
  (`_editorInitialString`, `_editorTextDidChange`, `_takeEditorValue`,
  `_editorDoCommand(by:)`), the last also routing the field editor's key-binding
  commands through the delegate's `control(_:textView:doCommandBy:)` as AppKit does. A
  tokenizing character cuts tokens off the typed text; Return, Tab and the end of editing
  tokenize the rest; Backspace at the start selects, then deletes, the last token; Left
  and Right walk the tokens; a double-click turns a token back into its editing string;
  a token with a menu opens it from its chevron. The delegate's `shouldAdd` and
  `styleForRepresentedObject` are consulted, so the generator now gives those optional
  methods usable defaults (`tokens` and `.default`), as it does for
  `NSControlTextEditingDelegate`'s `textShouldBeginEditing`/`textShouldEndEditing`, which
  defaulted to `false` and blocked editing for any field with a delegate.
- **Token completions.** The delegate's completions for the typed text show in a
  borderless, non-activating panel under the text (`_NSTokenCompletionPopUp`, at most
  eight rows, placed above the field when the screen has no room below). The field's
  window keeps the keyboard: Up/Down, Return/Tab and Escape reach the list through the
  editor hook; a click on a row takes it. The list closes with a token, on Escape, when
  no completion matches, and when editing ends. Unlike the combo box's list (PR 41), it
  does not intercept events at the application, so a click on an inert area of the
  window leaves it open until editing ends.
- **Search field.** The cell keeps the recent searches (saved under
  `recentsAutosaveName` in `UserDefaults`) and builds the search button's menu from
  the template's tagged items (title, recents, no recents, clear). Searches are sent
  as the user types (at once with `sendsSearchStringImmediately`, else after a 0.3 s
  pause on a run-loop timer) unless `sendsWholeSearchString` keeps them to Return;
  Escape and the cancel button clear and send the empty search; Return records the
  string in the recents.
- **Stepper, progress and the delays.** The stepper repeats (0.5 s, then every 0.1 s)
  while the mouse stays over the pressed half; the date picker's stepper repeats the
  same way; the search field waits 0.3 s after the last keystroke; the token field waits
  `completionDelay`. All four run on the frame clock (`_NSFrameTimer`, a `CADisplayLink`
  that counts down), not on a Foundation `Timer`: every backend schedules frames for a
  running display link, whereas RunLoop timers are serviced only between frames and did
  not fire on Win32 during a held press. A repeat fires at most once per frame, as a
  `Timer` fires once however many of its periods passed: a late frame (the Win32 pump
  held up by a slow layout pass) fires the repeat that is due, and the next is the next
  scheduled time after it, rather than every interval the frame covered at once (the
  bursts of four steps the Windows probe showed). A repeat re-lays its window ten times a
  second, which the Windows probe showed costing about 0.35 s a pass: the engine was
  resolving the application's layout direction (a copy of the process environment and a
  defaults read) for every leading/trailing anchor, measuring every label's text again,
  and solving every stack view's fitting size again. The direction is now resolved once,
  measured text is cached by string, font and wrap width (`_NSTextMeasureCache`), and a
  view's `fittingSize` is kept until something in its subtree changes, so a pass after a
  text change gathers only the changed subtree; `APPKITWIN_TRACE_FRAMES=1` shows the
  cost of each pass. The progress indicator's indeterminate
  animations (the bar's sweep, the spinner's spokes) advance on a `CADisplayLink` too,
  so the platform schedules frames only while something animates; `observedProgress`
  is read each frame (KVO is not available on every platform).
- **Level indicator.** All four styles are drawn by the cell (relevancy as a hatched
  bar, capacity as one bar or one segment per unit coloured green/yellow/red against the
  warning and critical values, tiered when asked, rating as stars or the control's
  images) with tick marks below or above; editable indicators take clicks, drags and
  arrows.
- **Path control.** The standard style lays the component cells out with chevrons and
  shrinks all but the last when narrow; the pop-up style is a pop-up button whose menu
  lists the ancestors (and "Choose…" with an `NSOpenPanel` when editable). Dragging
  path items is not provided. Its draw passes the enabled state to each component cell
  without going through the cell's setter when nothing changed: that setter invalidates
  the control, and a view invalidated by its own paint repaints forever (on Windows the
  pump never left WM_PAINT, so the main queue, timers and the demo's probe never ran;
  `RepaintLoopTests` keeps the Controls rows settling after each frame, and the Win32
  pump now services the main queue every 50 ms even while paints keep coming).
- **SwiftUI.** `ProgressView` hosts an `NSProgressIndicator` (a spinner under
  `.progressViewStyle(.circular)`); `Stepper` and `DatePicker` are new over `NSStepper`
  and `NSDatePicker` (graphical under `.datePickerStyle(.graphical)`).

## Consequences

- The controls look and behave the same on every backend and are testable on the host
  backend down to the pixel (`EverydayControlsTests`).
- Text in the date picker is laid out by the port, not by the system's date picker, so
  the fields follow the locale's order but not its native widget's exact spacing.
- A token field's editor never contains the tokens: `currentEditor?.string` is the text
  after them, and attributed-string attachment APIs on the editor do not show tokens.
- Delegates that implement only some of `NSTokenFieldDelegate` get the generator's
  defaults for the rest; a delegate that wants to refuse tokens implements `shouldAdd`.
