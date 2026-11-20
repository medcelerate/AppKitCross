# ADR-0051: The opt-in macOS control look (`APPKITWIN_MAC_CONTROLS`)

Date: 2026-11-20. Status: accepted.

## Context

The port draws every control itself (ADR-0021, ADR-0025), and the eight Windows PC rounds of
the Sibyl port (ADR-0050) compared the result against the Mac's own captures
(`ClockworksTech/Sibyl`, branch `appkitcross-port`, `docs/port/mac-1100x700/`). Evan's ask:
"the components take a windows styling I believe, it would be useful to build in a flag
potentially into appkitcross to follow mac styling more closely, like button shading, how text
inputs look etc, potentially even liquid glass but that is a larger project."

The comparison found nine gaps. Some are the port's own flatter, Windows-flavoured drawing,
which a Windows user expects and which stays the default; others are places where the port
simply does not do what SwiftUI does on macOS, which every ported app expects whatever the
platform. The two had to be told apart before a flag could gate anything.

## Decision

### Triage

| Gap (Windows PC vs the Mac capture) | Verdict | What changed |
|---|---|---|
| Push buttons: macOS draws a white softly shaded bezel with a hairline and a shadow; the port draws flat outlined rounded rects | **Style**, gated | Under the flag `NSButtonCell.drawBezel` shades the bezel (white to light grey; dark: a grey a shade lighter at the top) with a hairline and a one-point shadow; pressed and "on" bezels shade darker; the default button is the shaded accent. The flat bezel stays the default. |
| Text inputs: a grouped Form's `TextField` value (Show ▸ Name, Rule ▸ Name) is plain right-aligned text on the Mac, a boxed field on Windows | **Bug**, fixed | A `TextField` in a grouped form row is plain, trailing-aligned text at rest and takes its bezel and focus ring while the field editor is up (macOS 13+ Settings forms and inspectors). `NSTextFieldCell._bezelsWhileEditing` (port-only) carries it. |
| Text inputs: the bordered field's dark 1-point border vs the Mac's light inset bezel | **Style**, gated | Under the flag the bezel is a light hairline with a darker top edge (the inset) and the focus ring is a soft three-point accent ring. |
| Text inputs: no focus ring while editing (a search field too) | **Bug**, fixed | The cell took the control as the first responder; while editing the field editor is. `NSTextFieldCell` now treats a field whose editor is up as focused, under both looks. |
| Toggles: a `Toggle` in a Form or inspector is a switch on the Mac, a checkbox on Windows | **Bug**, fixed | The automatic toggle style is a switch inside a grouped form (macOS 13+), a checkbox elsewhere; `.toggleStyle(.checkbox)` still forces a checkbox. |
| Pop-up buttons: in forms the Mac shows plain text with an up/down chevron and no blue capsule; the port a white bezel with a blue end-cap | **Bug**, fixed | A `Picker` in a grouped form row is a borderless `NSPopUpButton`: the title as plain text, the chevrons in a small plain bezel. Outside forms the bezel with the accent cap is macOS's own look and stays under both looks. |
| Sliders: the Mac's tick-marked track (Cooldown, text size) is plain on Windows | **Bug**, fixed | `Slider(value:in:step:)` shows a tick per step and snaps to them (`numberOfTickMarks`, `allowsTickMarkValuesOnly`), as SwiftUI does on macOS; past 255 steps the ticks are left out. Under the flag the ticks are the Mac's comb behind the track and the knob a pill. |
| Sliders: the text size slider's small/large "A" labels vs symbol images | **Bug**, fixed | Sibyl's labels are `Image(systemName: "textformat.size.smaller")` and `.larger`; the catalogue drew the "aA" pair for both. They are now one small and one large "A" (`textformat.size` keeps the pair). |
| Search field: a rounded rect with a leading placeholder on the Mac, a capsule with a centred placeholder on Windows | **Bug**, fixed | Since macOS 11 the search field is a rounded rect (6-point corners) and its placeholder sits after the search button whatever `centersPlaceholder` says (the property is kept; `APPKITWIN_SEARCH_PLACEHOLDER=center` restores the centred placeholder of earlier releases). The rounded bezel of SwiftUI's `.roundedBorder` fields follows. |
| Alerts and sheets: a centred narrow sheet with the app icon, stacked buttons, a red destructive button and a dimmed parent on the Mac; a wide alert with side-by-side buttons and the destructive button as the blue default on Windows | **Both** | Bug, fixed: a SwiftUI alert button with the destructive role sets `NSButton.hasDestructiveAction`, which draws the title in the system red and never the accent bezel; `NSAlert` gives Return to its first button only when that button is not destructive, so "Delete Channel" / "Cancel" has no default, as on the Mac. Style, gated: under the flag `NSAlert` builds macOS's 260-point panel (the icon, centred message and informative text, full-width stacked buttons, the first on top), the sheet is centred over the parent's content instead of hanging from the title bar, and the parent's content dims (`_NSSheetDimView`) while it is up. The "near the top-right" placement the PC reported could not be reproduced on the host backend and is on the PC checklist. |
| Scrollers: overlay and hidden on the Mac; a legacy bar always shown on Windows (Matrix view) | **Style**, gated | `NSScroller.preferredScrollerStyle` and a scroll view's default `scrollerStyle` are `.overlay` under the flag: the scrollers take no room from the content, show as a translucent pill over its trailing edge when it scrolls, and a second later fade out over a quarter of a second and hide (frame timers; a scroll during the fade brings them back; `APPKITWIN_TRACE_SCROLLERS=1` logs each step). Legacy stays the default. Hover widening is not drawn. |
| Inactive-window appearance: the Mac greys selection, toggles and icons; the port greys the selection only | **Style**, gated | Under the flag the accent of a switch, an "on" checkbox or radio, the default button, the pop-up's end-cap and a slider's filled track greys out when the window is not key (`_NSControlStyle.isActive`), and the window repaints its views on each key change. Sidebar icons keep their colour: they are the app's own tinted images. |

### The switch

`APPKITWIN_MAC_CONTROLS=1` in the environment, or `AppKitCrossMacControls` = YES in the
Info.plist (the port's own key, beside `AppKitCrossRegistersFileTypes`), turns the macOS look
on for the process; the environment wins when both are set. The cells read
`_NSControlStyle.macControls` (`Support/ControlStyle.swift`), resolved once; tests force it
with `_NSControlStyle._override`. Apple has no public API for this (`NSAppearance` names are
light and dark variants, and no `NSControl` member picks a platform look), so no public
member is added: the switch is in the same spirit as the opt-in unified caption band.

### What stays out

Liquid Glass (macOS 26's materials: translucent, refracting toolbar and sheet surfaces) is a
later phase: it needs a material compositor per backend, not a cell's draw, and nothing in
Sibyl's captures depends on it. Sidebar icon greying in inactive windows, overlay scrollers'
hover widening, and a shaded pop-up bezel are left out as well.

## Consequences

- Under the default look nothing changes for the controls the PC rounds did not fault; the
  unconditional fixes change grouped-form rows (a switch for a toggle, a borderless pop-up, a
  plain field), stepped sliders, search fields, destructive alert buttons and the field focus
  ring on every platform, and `SwiftUIFormFixTests`, `SwiftUIRealAppTests` and
  `SwiftUIGroupedFormPixelTests` now look for the switch row where they looked for a checkbox.
- `MacControlsPixelTests` renders each control under both looks, light and dark, key and
  non-key, on the host backend.
- A port that wants the macOS look ships `AppKitCrossMacControls` in its Info.plist; a user
  can try it on any port with the environment variable.
