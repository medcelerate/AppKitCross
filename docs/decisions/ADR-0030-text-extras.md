# ADR-0030: The text system as an editor: find, spelling, attachments, lists and tables

Date: 2026-11-10. Status: accepted, awaiting verification on the Windows PC.

## Context

M9 gave the port a TextKit 1 text system (NSTextStorage, NSLayoutManager over CoreText,
NSTextContainer, NSTextView), and PR 42 a TextEdit example with RTF. What makes AppKit's
text view an editor was missing: `NSTextFinder` and the find bar, `NSSpellChecker`,
`NSTextAttachment` and its cell, `NSTextList`, `NSTextTable`/`NSTextTableBlock`/`NSTextBlock`,
`NSTextTab`, and about 160 `NSTextView` members were stubs.

Three platform facts shape the design:

- macOS has a system-wide spell checker; Windows 8 and later have the Spell Checking API
  (`ISpellCheckerFactory`, COM, the language packs the user installed); Linux desktops use
  hunspell with dictionaries under `/usr/share/hunspell`, which a minimal machine (or a CI
  container) may not have at all.
- In TextKit 1 the list markers are ordinary text ("\t1.\t") at the start of each item,
  positioned by tab stops, and table cells are paragraphs whose paragraph style names a
  text block. Applications and RTF depend on that representation.
- CoreText reserves space for inline objects with run delegates (`CTRunDelegate`) and
  positions tabs from the paragraph style's `CTTextTab`s; our CoreText module had neither.

## Decision

### CoreText

`CTRunDelegate` (`CTRunDelegateCreate`, `CTRunDelegateCallbacks`, `kCTRunDelegateAttributeName`)
and `CTTextTab` are added to the CoreText module with Apple's signatures. A delegate's
characters skip shaping: each advances by the delegate's width, raises the line to its
ascent and descent, and draws nothing. Tabs advance to the next `CTTextTab` of the
paragraph style past the pen (left, right and centred stops), else to the next multiple of
`kCTParagraphStyleSpecifierDefaultTabInterval` (28 points by default); the line's offset
(`CTTypesetterCreateLineWithOffset`, `...SuggestLineBreakWithOffset`) is where the
paragraph's head indent puts the line, so stops are measured from the same origin as in
AppKit. Line breaking measures tabbed text with the same rule. On macOS the host build
uses Apple's CoreText, which already does all of this.

### Attachments

`NSTextAttachment` stores contents, file type, file wrapper, image and bounds;
`init(fileWrapper:)` gets an `NSTextAttachmentCell` showing the file's image (or a page
icon) the first time `attachmentCell` is read, as AppKit does. `NSTextAttachmentCell` is
hand-written (it was pending: the protocol requires `cellSize()` as a method while NSCell
has a `cellSize` property; Swift allows the method in the subclass beside the inherited
property). The layout manager gives every U+FFFC with an `.attachment` a run delegate
sized by the cell (`cellSize()`, `cellBaselineOffset()`) or by
`attachmentBounds(for:proposedLineFragment:glyphPosition:characterIndex:)`, and draws the
attachments after the glyphs (`showAttachmentCell` for plain NSCells). An attachment is one
character, so the caret moves over it, it selects and deletes as one glyph. View providers
belong to TextKit 2, which this port does not lay out with: the registry is kept,
`viewProvider(for:...)` answers nil.

### Lists, tabs and blocks

`NSTextList` expands its marker format's `{token}` (disc, circle, square, box, check,
diamond, hyphen, decimal, octal, hexadecimal, alphabetic, roman) and keeps literal text
around it. `NSTextView` makes list items: a list paragraph has `textLists` (outermost
first), a hanging indent of 36 points per level and tab stops for the marker and the text;
Return makes the next item with the next number and renumbers what follows, Return on an
empty item leaves the list (one level at a time), Tab at the start of an item's text nests
it (bullets step disc → circle → square, numbers decimal → alphabetic → roman), Shift-Tab
brings it out. Lists compare by identity in paragraph styles (`NSParagraphStyle.isEqual`
now compares tab stops, lists and blocks), so two lists with the same format stay apart.

`NSTextBlock` resolves content width, minimum and maximum sizes, and padding, border and
margin per edge (absolute or a percentage of the enclosing width) into
`rectForLayout(at:in:textContainer:characterRange:)` and
`boundsRect(forContentRect:in:textContainer:characterRange:)`, and draws its background and
border bands. The layout manager lays a run of paragraphs whose outermost block is the same
block inside that block's content rect, records the box for drawing and for
`boundsRect(for:at:effectiveRange:)`/`layoutRect(for:at:effectiveRange:)`. A table's cells
are laid out row by row: the table first computes its columns (`NSTextTable._layoutColumns`):
a span-1 cell with a content width fixes its column; the fixed algorithm shares the rest
equally, the automatic one in proportion to the cells' natural widths and, when the table
has no width of its own, no wider than they need. Each row's cells sit side by side and the
row is as tall as its tallest cell; cells align vertically per `verticalAlignment`. Row
spans are laid out as single rows, and `collapsesBorders` draws adjacent borders side by
side (both recorded as limitations). Hit testing picks the fragment under the point among
side-by-side ones. Tab in a cell moves to the next cell; Format > Table inserts a table.

### RTF and RTFD

The RTF reader and writer (ADR-0017) now carry paragraph indents (`\li \fi \ri`),
spacing (`\sb \sa`), tab stops (`\tx`, `\tqr`, `\tqc`), lists (Cocoa's `\listtable` with
`\levelmarker`, `\ls`, `\ilvl`, and Word's `\levelnfc` codes when reading) and tables
(`\trowd`, `\cellx` with borders and backgrounds, `\intbl`, `\cell`, `\row`). RTFD is a
directory of `TXT.rtf` and the attachments' files, referenced as `\NeXTGraphic` groups
(`rtfdFileWrapper(from:documentAttributes:)`, `init(RTFDFileWrapper:documentAttributes:)`).
The flat RTFD data (`rtfd(from:)`, `init(RTFD:)`, the `com.apple.flat-rtfd` pasteboard
type) is this port's own archive of that directory, since FileWrapper's serialised form
needs the Objective-C runtime; on macOS the reader also accepts Apple's.

### Spell checking

A `PlatformSpellChecker` seam (`Platform/SpellChecking.swift`) with one implementation over
the `CSpellCheck` C shim: `cspell_win.cpp` drives `ISpellCheckerFactory`/`ISpellChecker`
(Check, Suggest, Add; languages from `get_SupportedLanguages`, "en" picks the first
installed dialect), `cspell_hunspell.c` loads libhunspell with `dlopen` and finds
dictionaries in `$DICPATH`, `/usr/share/hunspell`, `/usr/share/myspell` (converting to the
dictionary's encoding with iconv), so neither the library nor dictionaries are needed to
run. Without a system checker (the macOS host build, a Linux machine without dictionaries,
or `APPKITWIN_SPELL_CHECKER=wordlist`) `NSSpellChecker` uses a built-in English word list
with common inflections, plus `/usr/share/dict/words` when present; guesses come from
Damerau–Levenshtein distance. On top of either, `NSSpellChecker` keeps learned words
(persistent, user defaults key `NSSpellCheckerLearnedWords`), ignored words per spell
document tag, completions (the document's words, learned words and the word list),
`correction(...)` (the first guess when one edit away), the Spelling panel and the
Substitutions panel. Grammar checking is not implemented (`checkGrammar` finds nothing,
`isGrammarCheckingEnabled` is stored); languages are not identified
(`automaticallyIdentifiesLanguages` is stored). `requestChecking`/`check(_:range:types:...)`
stay skipped by the generator: `NSTextCheckingTypes` is not in swift-corelibs-foundation.

`NSTextView` checks continuously when `isContinuousSpellCheckingEnabled`: after each edit
(coalesced on the main queue) misspelt words get the `.spellingState` temporary attribute,
which the layout manager draws as a red dotted underline without laying the text out again
(`.spellingState` and `.backgroundColor` are display-only temporary attributes). The word
being typed is not flagged. The context menu offers guesses, Ignore Spelling and Learn
Spelling, then Cut/Copy/Paste and the Spelling and Substitutions submenus;
`checkSpelling(_:)` selects the next misspelling, `showGuessPanel(_:)` opens the panel.
Autocorrection (`isAutomaticSpellingCorrectionEnabled`), text replacement, smart quotes and
smart dashes act when a word is finished.

### Find

`NSTextFinder` runs the search over its client's text (read with
`string(at:effectiveRange:endsWithSearchBoundary:)`/`stringLength()`, whose defaults now
answer from `string` through `optionalDefaults`), case-insensitive by default, with the
contains/starts with/full word/ends with matching types, and implements every
`NSTextFinder.Action`. It builds the find bar (`_NSFindBarView`: options menu, search field,
match count, previous/next, Done, and the Replace row) and puts it in the
`findBarContainer`: `NSScrollView` shows it above or below the content per
`findBarPosition` and tiles the content into the rest. A text view with `usesFindPanel` and
no scroll view gets the same bar in a small panel. `NSTextView` (privately a finder client,
as in AppKit) handles `performFindPanelAction(_:)` and `performTextFinderAction(_:)` by tag,
draws incremental matches with `NSTextFinder.drawIncrementalMatchHighlight(in:)` and a ring
around the current match while the bar is up. `incrementalSearchingShouldDimContentView` is
stored, nothing is dimmed.

### NSTextView

Beyond the above: completion (`complete(_:)` with a menu at the insertion point,
`completions(forPartialWordRange:indexOfSelectedItem:)` through the delegate,
`insertCompletion`, `rangeForUserCompletion`), smart insert and delete (paste of a word
selection adds spaces, as AppKit's smart-paste pasteboard type marks it), the rich
pasteboard (RTF, RTFD, PNG/TIFF and file URLs as attachments; copy writes RTF and RTFD),
drag and drop of images and files into rich text, links (`clicked(onLink:at:)`), kerning,
baseline and ligature commands, the user-change ranges, `setAlignment`/`setBaseWritingDirection`
for paragraphs, the scrollable factory methods, and the toggles. The ruler is recorded as
missing: `usesRuler` is stored and no `NSRulerView` is shown. The `unimplemented()` count in
NSTextView went from 162 to 45 (the PR lists the rest).

## Consequences

- TextEdit has Edit > Find, Spelling and Grammar, Substitutions and Complete, Format >
  Lists and Table, attachments by drag and drop or paste, and saves rich text with
  attachments as RTFD (`--roundtrip-rtfd` checks it on every CI job;
  `--sample-screenshot` renders the comparison image).
- Applications that build attributed strings with lists, tables or attachments get them
  laid out and drawn, and RTF keeps them.
- Typing attributes no longer restyle the whole text of a rich text view; text typed at the
  start of a paragraph takes that paragraph's style.
- Tests: `TextExtrasTests` (find bar, replace, spelling with a known word list and the
  system checker where present, attachment layout and selection, RTFD, list markers and
  editing, lists and tables through RTF, table layout rects, tab stops).
