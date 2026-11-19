# ADR-0040: TextKit 2 on the port's CoreText

Date: 2026-11-16. Status: accepted, awaiting verification on the Windows PC.

## Context

The port's text system is TextKit 1 (ADR-0007, ADR-0030): `NSTextStorage` feeds a hand-written
`NSLayoutManager` that typesets paragraphs with CoreText (Apple's on the macOS host build, the
port's `Sources/CoreText` over DirectWrite on Windows and Pango/HarfBuzz on Linux) into an
`NSTextContainer`, and `NSTextView` draws and edits through it. TextKit 2 was the largest
cluster of generated stubs left: `NSTextLayoutManager` (53 members), `NSTextContentManager` and
`NSTextContentStorage` (25), `NSTextLayoutFragment` (24), `NSTextLineFragment`, `NSTextRange`,
`NSTextLocation`, `NSTextElement`, `NSTextParagraph`, `NSTextSelection` and
`NSTextSelectionNavigation` (20), `NSTextViewportLayoutController`, and the TextKit 1
`NSTypesetter`/`NSATSTypesetter` (59) that Apple's `NSLayoutManager` delegates to.

Apple's model, which the public API fixes:

- A *content manager* presents the document as a sequence of *elements*; `NSTextContentStorage`
  backs it with an `NSTextStorage` (it is the storage's `textStorageObserver`) and vends one
  `NSTextParagraph` per paragraph. Positions are opaque `NSTextLocation`s, spans `NSTextRange`s.
- A *text layout manager* turns each element into an `NSTextLayoutFragment` holding
  `NSTextLineFragment`s. Fragments stack vertically in one `NSTextContainer`; a fragment's
  `layoutFragmentFrame` is in container coordinates, a line's `typographicBounds` in the
  fragment's.
- The *viewport layout controller* lays out only what is visible; everything else has an
  estimated size until it scrolls into view.
- Selections are `NSTextSelection`s over text ranges, and keyboard and mouse movement is
  computed by `NSTextSelectionNavigation` against an `NSTextSelectionDataSource` (the layout
  manager).
- `NSTextView` uses TextKit 2 unless its `layoutManager` is asked for, which switches it to
  TextKit 1 for good ("compatibility mode"); content TextKit 2 cannot lay out (text tables)
  triggers the same switch.

## Decision

### Locations, ranges, elements

Locations created by the port are an internal `_NSTextIndexLocation` (an `NSObject` holding a
UTF-16 offset into the document); `compare` orders them by offset, and a foreign location is
asked the inverse question. `NSTextRange` stores any two locations and implements containment,
intersection and union through `compare` only, so it works with other location types too.
`intersection`/`union` return `Self` and build `NSTextRange`s (a subclass gets a plain range;
Apple documents neither case). `NSTextElement` and `NSTextParagraph` are plain models;
a paragraph's content and separator ranges are derived from its `elementRange` and string.

### Content storage

`NSTextContentManager` keeps its layout managers (the first becomes primary), editing
transactions (nested; layout managers synchronise when the outermost one ends) and
`recordEditAction`. The element-provider members of the base class are abstract and stay
`unimplemented()` with that reason, as Apple's raise.

`NSTextContentStorage` creates its own `NSTextStorage` (or takes one through `textStorage`)
and observes it. It keeps the paragraph table as an array of `NSTextParagraph` objects. The
paragraph separators are the ones TextKit 1's layout uses (LF, CR, CR LF, U+2028, U+2029,
form feed), so both engines see the same paragraphs. An edit (`processEditing(for:…)`)
rebuilds the paragraphs that cover the edited range and shifts the `elementRange` of the ones
after it in place: unchanged paragraphs keep their identity, and so does their layout. The
content storage then tells each layout manager which document span changed. The delegate's
`textParagraphWith:` replaces a paragraph when it answers; `shouldEnumerate` filters
enumeration (the generated optional default was `false`, which would hide every paragraph; it
is `true` now through `optionalDefaults`, as are the layout manager delegate's
`shouldBreakLineBefore` and `textLayoutFragmentFor`, which builds a plain fragment).

### Layout on CoreText

`NSTextLayoutFragment` lays its paragraph out with the same code TextKit 1 uses. The CoreText
conversion of attributes (fonts, appearance-resolved colours, tab stops, attachments as run
delegates, outlines, link attributes) and the line typesetter (break with
`CTTypesetterSuggestLineBreakWithOffset`, clipping and truncation modes, indents, alignment,
line height multiple and limits, line and paragraph spacing) were extracted from
`NSLayoutManager` into `_NSCoreTextConversion` and `_NSLineTypesetter`, which both engines
call. A fragment therefore produces exactly TextKit 1's lines: the same breaks, the same
heights, the same x positions. Its `layoutFragmentFrame` is `(0, y, container width, height)`;
each line's `typographicBounds` is the TextKit 1 used rect relative to the fragment and its
`glyphOrigin` is `(0, ascent)`. Paragraph spacing before is inside the fragment (except at the
top of the document, as in TextKit 1); spacing after and the last line's line spacing are part
of its height, so the next fragment starts where TextKit 1's next line does. The last
paragraph's fragment carries an extra empty line fragment after a trailing newline, and an
empty document has one empty fragment, both standing in for TextKit 1's extra line fragment
(they are enumerated with `.ensuresExtraLineFragment`, and the caret uses them).

`NSTextLineFragment` holds its `CTLine`: `characterIndex(for:)`, `locationForCharacter(at:)`,
`fractionOfDistanceThroughGlyph(for:)` and `draw(at:in:)` are CoreText calls. Attachments draw
after the glyphs with their cell or image, strikethrough and the spelling underline the way
TextKit 1 draws them, and `.backgroundColor` runs before them. Text tables (`NSTextBlock` in a
paragraph style) are not laid out by TextKit 2, as on macOS: `NSTextView` switches to TextKit 1
when its text contains one.

### Layout manager and viewport

`NSTextLayoutManager` keeps one fragment per element in document order. Fragments that are
not laid out have an estimated height (lines × the paragraph font's line height, from the
paragraph's length and the container width) and state `.estimatedUsageBounds`; laid-out ones
are `.layoutAvailable`. Frames are stacked from the top whenever a height changes.
`ensureLayout(for:)` lays out ranges or rects; `enumerateTextLayoutFragments` lays out with
`.ensuresLayout`, walks backwards with `.reverse` and returns where it stopped;
`textLayoutFragment(for:)` finds fragments by location (binary search on offsets) or point;
`enumerateTextSegments` returns standard, selection and highlight rects per line (selection
segments extend over a selected line break, as TextKit 1's highlight does).
`usageBoundsForTextContainer` is the union of the frames. A container geometry change or
`invalidateLayout(for:)` returns fragments to the estimated state. Rendering attributes are
kept per range like TextKit 1's temporary attributes: background colour and the spelling state
are drawn by the fragment, a foreground colour re-runs the conversion for the fragments it
touches. `replaceContents` edits the content storage inside a transaction.

`NSTextViewportLayoutController` asks its delegate for the viewport bounds, lays out the
fragments that intersect them (and only those), calls `configureRenderingSurfaceFor:` for each
in order between `willLayout` and `didLayout`, and reports `viewportRange`. `relocateViewport`
lays out from a location and returns its fragment's offset; `adjustViewport(byVerticalOffset:)`
moves every frame (the text view uses it to keep the text under the viewport still when
estimates above it turn into real heights).

### Selection navigation

`NSTextSelection` stores ranges, affinity, granularity, the anchor position (the x a vertical
movement keeps), typing attributes and, internally, the anchor location an extension grows
from. `NSTextSelectionNavigation` implements its destinations against the data source protocol:
character (composed character sequences), word (letters, digits and the underscore: the TextKit 1
text view's double-click rule, used for option-arrow too), sentence and paragraph
(`enumerateSubstrings`, computed on the UTF-16 text because corelibs Foundation does not
implement `NSString.enumerateSubstrings`),
line (the data source's caret offsets and line fragment ranges; up and down keep
`anchorPositionOffset`), container and document. Left and right follow the paragraph's
writing direction. Moving without extending collapses a range to its start or end first;
extending keeps the anchor. `textSelections(interactingAt:…)` maps a point to a caret through
`lineFragmentRange(for:inContainerAt:)` and the caret offsets, extends from the anchors with
`.extend` or while `selecting`, and preserves word and paragraph granularity for double- and
triple-click drags. `deletionRanges` returns the selection, or the span to the destination.
`NSTextLayoutManager` is the data source.

### Text view

`NSTextView` gains `textLayoutManager`, `textContentStorage` and `init(usingTextLayoutManager:)`.
A TextKit 2 view owns an `NSTextContentStorage` whose `textStorage` is the view's storage, an
`NSTextLayoutManager` with the view's container (`NSTextContainer.textLayoutManager` answers)
and a viewport controller whose delegate is the view. `layoutManager` on a TextKit 2 view
switches it to TextKit 1 (the content storage stops observing, the NSLayoutManager attaches to
the storage and container) and then answers, as Apple's does; field editors and text with
tables switch too. Internal code that only needs TextKit 1 when it is active (spelling marks,
find highlights, attachments, the ruler) no longer goes through the public getter, so it does
not switch the view.

In TextKit 2 the view's geometry hooks (lines, caret rects, point to offset, content size) read
the layout manager, the frame follows `usageBoundsForTextContainer`, the viewport is laid out
from `layout()` and whenever the clip view scrolls (never from `draw(_:)`), and drawing walks
only the fragments in the dirty rect, background pass, selection and find highlights, then
glyphs, in the same order and at the same coordinates as TextKit 1, so both engines draw the
same pixels. The arrow, word, line, paragraph and document movement actions and their
selection-extending forms, and mouse clicks, shift-clicks, double- and triple-clicks and drags,
go through `textSelectionNavigation`, and so do the word and character deletions, page up and
down, and `selectWord:`/`selectLine:`/`selectParagraph:`; the result is mirrored into the
view's `selectedRange`, which the rest of NSText still uses, and the layout manager's
`textSelections` follow the view's selection (typing moves it) and set it when assigned.
Spelling marks are rendering attributes. Colours are resolved under the view's appearance at
layout time; a fragment drawn under another appearance (printing from a dark window) is
typeset again before it draws, as TextKit 1 does.

The port keeps TextKit 1 as the default for `NSTextView(frame:)` for now (Apple's default is
TextKit 2): `APPKITWIN_TEXTKIT=2` makes new non-field-editor text views use TextKit 2, so the
PC can compare both engines in TextEdit; `init(usingTextLayoutManager:)` chooses explicitly.
Flipping the default is a one-line change once TextKit 2 has been verified on all three
platforms.

### NSTypesetter

`NSATSTypesetter.shared` is `NSLayoutManager.typesetter` and the class behind
`NSTypesetter.sharedSystemTypesetter`. `NSLayoutManager` asks it, per line, for paragraph
spacing before and after and line spacing (defaults read the paragraph style, so a subclass can
change spacing), and the typesetter's paragraph and line state (`attributedString`,
`layoutManager`, `currentTextContainer`, `currentParagraphStyle`, the paragraph and separator
ranges) is set while it lays out. Hyphenation stays off (`hyphenationFactor` 0). The
convenience surface is real: `layoutCharacters(in:for:maximumNumberOfLineFragments:)` and
`layoutGlyphs` lay out through the layout manager, glyph and character ranges map through it,
`actionForControlCharacter`, `textTab(forGlyphLocation:…)`, `getLineFragmentRect(…)` (the
container's proposal), `baselineOffset(in:glyphIndex:)`, `substituteFont`,
`attributesForExtraLineFragment`, `boundingBox(forControlGlyphAt:…)` and
`printingAdjustment` (zero: the port lays out with printer metrics). The glyph setters
(`setLineFragmentRect`, `setLocation(_:withAdvancements:…)`, `setNotShownAttribute`,
`setDrawsOutsideLineFragment`, `setBidiLevels`) forward to the layout manager's manual-layout
setters (ADR-0039): the value replaces the laid-out one until the next layout pass. What
would edit glyphs (`insertGlyph`, `deleteGlyphs`, `substituteGlyphs`) or drive layout from a
`layoutParagraph(at:)` override stays `unimplemented()` with the reason: the port's
NSLayoutManager lays out CoreText lines, not glyph storage.

### Windows PC round

The first PC run found, besides engine parity, shared editing gaps that this change fixes for
both engines: edits scroll the insertion point into view (after fitting the frame, so a long
paste is not clamped to the old height); a click on an attachment selects it; continuous
spelling checks only the paragraphs edits touched (the whole text on every keystroke made a
3000-line paste take seconds); the caret just before a newline belongs to its line (Home and
End used the next line); the find bar redraws when shown; and the text navigation keys follow
the platform: macOS's table on the Mac, the PC's on Windows and Linux (Ctrl+arrows and
Ctrl+Backspace by word, Home/End by line, Ctrl+Home/End by document), where the backends
report Ctrl as Command (`APPKITWIN_KEY_BINDINGS=mac|pc` overrides). TextKit 2 adds rendering
attributes in document order without rebuilding the run list, and looks for text tables only
after content edits. TextEdit sizes its text view from the scroll view's content size, so a
legacy (Windows) scroller no longer covers the end of each line.

The second PC run measured seconds per keystroke in a 3000-line document under both
engines. The causes, all shared: the "incremental" spelling pass unioned its range with the
document's start; spelling indexed a bridged `String` character by character (linear per
access on corelibs Foundation, so quadratic); TextKit 1 drew the whole document on every
display, and its spelling underline looped every mark over every line. Spelling now copies
just the checked range, a long pass checks the visible text first and the rest 2000
characters per run-loop turn, TextKit 1 draws only the lines in the dirty rect, and the
underline starts at each mark's own line. A wrapping text view in a scroll view also keeps
its width equal to the clip view's (it watches the clip view's frame), so no path that
narrows the clip view can leave lines under the scroller.

### TextKit 1 relayout per paragraph (follow-up)

TextKit 1 first kept the line code of its whole-document pass: every edit converted the
whole text for CoreText and typeset it again. `NSLayoutManager` now lays out in units, as
AppKit invalidates and re-typesets paragraphs: a unit is one paragraph, or the run of
paragraphs in one outermost text block or table (a table's columns and rows depend on every
cell, so the block is the invalidation unit). Each unit is converted and typeset on its own
(`_NSCoreTextConversion.convert` of the unit's substring, its own `CTTypesetter`, the shared
`_NSLineTypesetter` for its lines), so its `CTLine`s index from the unit's start; a line
fragment carries that base (`lineBase`) and maps document indices through it.

The fragments stay one array in text order; each unit knows how many are its own. An edit
(`processEditing`, `invalidateLayout(forCharacterRange:…)`, a temporary attribute that
changes layout) turns the units it touches, plus the one ending where it starts (a line
break typed or deleted there joins or splits it) and a text block next to it (a paragraph
joining or leaving a table moves where the table's run ends), into one dirty unit, and moves
the units after it by the length delta. The next pass walks the units: a dirty one is typeset
again (as many units as the paragraphs now there need, and a new unit that runs over a cached
one replaces it too), and its lines are spliced into the array; a clean run of units after it
moves, in place, by the edit's length delta and the height delta. A clean unit's lines cannot
break differently (its text, attributes and width are unchanged), so where AppKit
re-typesets until a paragraph's breaks come out unchanged, the pass stops at the first clean
unit. A unit laid out at the top of the text (no space before its first paragraph) is typeset
again when it no longer is. In containers of bounded height (pages, columns, line limits) a
unit's position decides which container its lines land in, so units are kept only up to the
first one typeset again. A change of appearance, container geometry, typesetter, a secure
echo or `invalidateGlyphs` with a length change outside an edit still discards everything.
The units also remember the container geometry they were typeset in (size, padding,
alignment width, line break mode, line limit, exclusion bounds), and a pass that finds it
changed lays every unit out again, however the change arrived. An invalidation while a pass
runs (something the pass called out to resized the container) only marks the layout invalid,
and the pass drops what it laid out when it ends. Before this, such a pass carried on with its
cached units after the arrays had been emptied, and either trapped or left the text wrapped at
the old width (the PC's narrowed TextEdit window).

`NSTextView` no longer invalidates the whole layout after each edit: the edit reaches the
layout manager through the text storage, so the text view only fits its frame and redraws.
Setting `linkTextAttributes` invalidates the TextKit 1 layout (links resolve when a paragraph
is typeset). `usedRect(for:)` is cached until the lines change.

## Consequences

- Both engines share one typesetter, so TextKit 2 fragment frames match TextKit 1 line rects
  (the tests require 0.5 pt; in practice they are equal) and both draw the same pixels.
- A long document scrolled into the middle has estimated fragments above the viewport; they
  get real heights when they scroll in, and the viewport controller compensates.
- TextKit 1 is untouched in behaviour; its line code moved into shared helpers.
- The delegate's `shouldBreakLineBefore` is not consulted (CoreText chooses the breaks), and
  link runs take the text view's `linkTextAttributes` (or `linkRenderingAttributes` without a
  view) rather than asking the delegate per link; `renderingAttributes(forLink:at:)` answers
  with the delegate's attributes for callers.
- TextKit 1 relays out per paragraph (see the follow-up above): a keystroke typesets the
  edited paragraph (a table, if the edit is in one) and moves the lines after it. In a
  3000-line document a keystroke's layout pass took about 12 ms on the macOS host (debug
  build) when every edit typeset the whole text; it now takes about 1.3 ms, of which the
  typesetting is 0.03 ms and the rest moves the later lines (linear in their number, but
  plain arithmetic). On the Windows PC the whole-text pass took about 2 s per keystroke.
  `TextKit1IncrementalLayoutTests` compares the incremental layout with a full one (line rects, block
  frames, hit testing, pixels) after edits at the start, middle and end, paragraph splits and
  joins, wrapping changes, table cell edits and random edit sequences.
- Not done: multiple text containers in TextKit 2 (Apple's TextKit 2 has one per layout
  manager too), vertical layout orientation, `NSTextAttachmentViewProvider` views in fragments
  (attachments draw their image or cell), `layoutQueue` (layout is synchronous; the property
  stores the queue), list markers drawn from `NSTextList` without marker text (the port's lists
  keep TextKit 1's marker text, which TextKit 2 lays out like any text).
