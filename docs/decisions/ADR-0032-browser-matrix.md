# ADR-0032: NSMatrix, NSForm and NSBrowser

Date: 2026-11-12. Status: accepted, awaiting verification on the Windows PC.

## Context

`NSMatrix`, `NSForm`/`NSFormCell` and `NSBrowser`/`NSBrowserCell` were generated stubs
(about 260 `unimplemented()` members) in the stub burn-down. They are the cell-based
controls AppKit kept from NeXTSTEP: a matrix is one control drawing a grid of cells and
owning their selection; a form is a one-column matrix of titled text entries; a browser
is a row of columns, each a list matrix, whose selection walks a hierarchy. Mac code that
still uses them — radio groups built in a nib as a matrix, Finder-like column browsers,
preferences forms — needs them to behave, not just compile.

The port already draws cells (`NSCell`, `NSButtonCell`, `NSTextFieldCell`), edits text in
the window's field editor laid over a control (`NSTextField`, ADR-0021's search and token
fields), and scrolls with `NSScrollView`. Windows and Linux have nothing to map these
controls to: the Win32 common controls have no column browser, and a radio group there is
separate `BUTTON` windows. So all three are drawn by the package on every backend, as the
other everyday controls are.

## Decision

### NSMatrix is the real grid, and the other two are built on it

`NSMatrix` keeps its cells in a row-major array and lays them out itself (flipped, row 0
at the top) at `cellSize` with `intercellSpacing`; `cellFrame(atRow:column:)`, hit testing
(`getRow(_:column:for:)`, which misses in the spacing), `sizeToCells`, `autosizesCells`
and `autorecalculatesCellSize` follow from that. Each cell draws through its own
`draw(withFrame:in:)`, so a radio matrix of `NSButtonCell`s looks exactly like the port's
radio buttons. Rows and columns are added, inserted, removed, renewed and replaced
(`putCell`) with new cells from `makeCell(atRow:column:)`: a copy of `prototype`, else a
new `cellClass`.

The matrix owns the selection, per mode, as AppKit does:

- radio: one selected cell, state on, the others off; with `allowsEmptySelection` false
  (the default) the first cell is selected as soon as there is one;
- list: any set of highlighted cells — click, Shift-click (range), Command-click
  (toggle), drag (by rectangle or reading order per `isSelectionByRect`),
  `setSelectionFrom(_:to:anchor:highlight:)`, `selectAll`;
- highlight and track: each click flips the clicked cell's state (highlighting it while
  the mouse is down in highlight mode) and makes it the selected cell.

`selectCell(atRow:column:)`, `selectCell(withTag:)`, `setState(_:atRow:column:)`,
`deselectAllCells`, `deselectSelectedCell`, `selectedCells`/`selectedRow`/`selectedColumn`
and the inherited value accessors (the selected cell's value) all go through that model.
The arrow keys move the key cell (and the radio or list selection), Space clicks it,
`performKeyEquivalent` clicks a button cell by its key equivalent. `sendAction()` sends
the selected cell's action to its target if it has one, else the matrix's own;
`doubleAction` and `sendAction(_:to:forAllCells:)` are there too. NSMatrix overrides
`target`, `action`, `tag` and `isEnabled` with its own storage (NSControl keeps them in its
single cell, which a matrix doesn't have); enabling the matrix enables every cell.

Editable text cells are edited in the window's field editor laid over the cell's text
rect, the way `NSTextField` does it. AppKit's NSMatrix is the field editor's delegate
without declaring `NSTextDelegate`; the port keeps that API exactly by giving the editor a
small internal delegate object that forwards to the matrix's public `textDidBeginEditing`
… `textShouldEndEditing` members. Return sends the action and keeps editing with the text
selected; Tab and Shift-Tab go to the next or previous editable cell when
`tabKeyTraversesCells`, then to the next key view; Escape restores the cell's text.

### NSForm and NSFormCell

`NSForm` is an NSMatrix whose default cell class is `NSFormCell`, one column, 22 pt
entries 8 pt apart, as wide as the form (`setFrameSize` keeps them so). Before drawing it
gives every entry the widest title's width, so the entries line up; a title width set on a
cell wins. `NSFormCell(textCell:)` takes the title (the value starts empty, as in AppKit);
the cell draws the title (right-aligned by default, its own font and writing direction)
and a bezeled entry filling the rest, with the placeholder when empty, and tells the
matrix where the field editor goes (`_entryTextRect`).

### NSBrowser: a row of scroll views holding list matrices

Each loaded column is an `NSScrollView` whose document view is a list-mode `NSMatrix` of
`NSBrowserCell`s (made from `cellPrototype`, of `matrixClass()`), as in AppKit, so
`matrix(inColumn:)` and `column(of:)` answer real objects and the delegate's
`createRowsForColumn(_:in:)` fills a real matrix. The browser lays the columns side by
side from `firstVisibleColumn` under optional titles and over a horizontal `NSScroller`:

- `autoColumnResizing` (the default): as many columns as fit `minColumnWidth`, at most
  `maxVisibleColumns`, sharing the width equally;
- `userColumnResizing`: each column at its own width (`setWidth`, `defaultColumnWidth`),
  dragged at its right edge (all columns with `prefersAllColumnUserResizing` or Option),
  double-click to size to fit; widths persist under `columnsAutosaveName` in the user
  defaults, and changes post `columnConfigurationDidChangeNotification`;
- `noColumnResizing`: own widths, no dragging.

Content comes from the delegate in one of AppKit's three ways: item-based
(`rootItem`, `numberOfChildrenOfItem`, `child`, `isLeafItem`, `objectValueForItem`),
passive matrix-based (`numberOfRowsInColumn` then `willDisplayCell` per row), or active
(`createRowsForColumn`). Selecting exactly one branch in a column loads the next column
and scrolls it into view; anything else makes that column the last. On top of that sit
`path()`/`path(toColumn:)`/`setPath(_:)` (absolute or relative, with the delegate's
`selectCellWith` when it has one), `selectRow`, `selectRowIndexes` (through
`selectionIndexesForProposedSelection`), `selectionIndexPath(s)`, `indexPath(forColumn:)`,
`item(at:)`, `parentForItems(inColumn:)`, `reloadColumn`, `validateVisibleColumns`,
`reloadData(forRowIndexes:inColumn:)`, per-row heights from `heightOfRow`, column titles
(delegate, then `setTitle`, then the previous column's selection when
`takesTitleFromPreviousColumn`), `editItem(at:with:select:)` through the matrix's field
editor, and `reusesColumns`.

Keyboard: Up/Down/Home/End move within a column, Right enters a selected branch (focus to
the next column, first row selected), Left returns to the parent column (which keeps its
selection); each sends the action when `sendsActionOnArrowKeys`. Typing selects the first
row whose title (or the delegate's type-select string) starts with what was typed in the
last second. `NSBrowserCell` draws its row with the accent selection colour while its
column has keyboard focus in the key window and the unemphasized grey otherwise, and a
chevron for branches.

### Optional delegate methods are detected, not guessed

AppKit chooses item-based, passive or active content — and whether to use the delegate's
title matching, row heights or type-select matching — by `respondsToSelector:`. Swift
protocol extensions cannot be asked that, so `NSBrowserDelegate` moves to Core (listed as
hand-written) and the defaults of those particular optional methods call an internal
`NSBrowser._noteDelegateMethodMissing()`; the browser runs the call and checks the flag.
The other optional methods now carry AppKit's behaviour when absent rather than the
generator's guesses: `isColumnValid` true, `shouldTypeSelect` true,
`selectionIndexesForProposedSelection` the proposal, `shouldSizeColumn` the suggested
width, `heightOfRow` the browser's `rowHeight`, `sizeToFitWidthOfColumn` the widest
cell. The item-mode probe asks for column 0's row count once and reuses it, so a delegate
sees exactly one `numberOfChildrenOfItem` per column load.

### Cells copy for real

`NSCell.copy(with:)` returned `self`, which a matrix prototype cannot use. A copy is now a
new cell of the same class from the required `init(coder:)` with the original's settings
copied by an internal `_copyCellState(from:)`, overridden by `NSActionCell`,
`NSButtonCell`, `NSTextFieldCell`, `NSFormCell` and `NSBrowserCell` for their own storage.
Other cell subclasses copy the NSCell part only until they add the override. For
`cellClass`, Swift can only construct through a metatype with a required initializer:
AppKit's own cell classes get their `init()` equivalents (an NSButtonCell titled
"Button", an NSFormCell titled "Field:" …) and other subclasses come from `init(coder:)`
— a subclass whose `init(coder:)` traps should be given as a `prototype` instead. The same
applies to `NSBrowser.setMatrixClass` with an NSMatrix subclass.

## Not yet

- Browser drag and drop: `canDragRows` and the source operation masks are answered, but
  no row drag starts; `draggingImageForRows` returns the delegate's image and otherwise
  calls `unimplemented()`.
- `NSMatrix.sort(using:)` with a selector other than `compare:` (needs the Objective-C
  runtime); the closure form works.
- Cell tool tips are stored (`setToolTip(_:for:)`, the `NSViewToolTipOwner` answer) but
  no tool-tip rect is registered, as `NSView.addToolTip` is still a stub.
- Accessibility: the matrix is an AXRadioGroup (radio mode) or AXGroup and the browser an
  AXBrowser with the path as value; the cells are not yet elements of their own.
- `NSBrowser` header view controllers and preview view controllers are not shown.

## Verification

`BrowserMatrixTests` (13, host backend): radio exclusivity and empty selection, tags,
list ranges by rectangle and reading order, structure edits and hit testing, radio clicks
and arrows with target/action, highlight-mode toggling and list Shift/Command/drag,
form layout and title alignment, form editing with Tab and Return through the field
editor, the item-based path round trip with per-column delegate counts, passive and
active matrix delegates, mouse and arrow navigation between columns with
`sendsActionOnArrowKeys` and type select, column scrolling and user resizing, and a radio
matrix's pixels (skipped off the host backend). HelloWindow's Layout Demo has a Browser
tab (`APPKITWIN_LAYOUT_TAB=browser`): a file-system-like browser, a radio matrix choosing
the column resizing, and a form whose Go to entry sets the path.
