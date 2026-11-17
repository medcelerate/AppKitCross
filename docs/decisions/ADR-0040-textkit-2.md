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
`printingAdjustment` (zero: the port lays out with printer metrics). What would let a subclass
place glyphs itself (`setLineFragmentRect`, `setLocation(_:withAdvancements:…)`, `insertGlyph`,
`substituteGlyphs`, bidi levels, `layoutParagraph(at:)` overrides driving the layout) stays
`unimplemented()` with the reason: the port's NSLayoutManager lays out CoreText lines, not glyph
storage.

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
- Not done: multiple text containers in TextKit 2 (Apple's TextKit 2 has one per layout
  manager too), vertical layout orientation, `NSTextAttachmentViewProvider` views in fragments
  (attachments draw their image or cell), `layoutQueue` (layout is synchronous; the property
  stores the queue), list markers drawn from `NSTextList` without marker text (the port's lists
  keep TextKit 1's marker text, which TextKit 2 lays out like any text).
