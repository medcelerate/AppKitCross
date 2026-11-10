# ADR-0020: NSCollectionView, NSGridView and NSBox

Date: 2026-11-10. Status: accepted.

## Context

Three container views that most AppKit applications reach for were still generated
stubs: `NSCollectionView` (82 members calling `unimplemented()`), `NSGridView` and `NSBox`.
Each has a design question the port has to answer without an Objective-C runtime, a nib
loader or AppKit's private layout machinery:

- A collection view instantiates the item class the application *registers*
  (`register(_:forItemWithIdentifier:)`), and AppKit does that with `[cls alloc]
  initWithNibName:bundle:`. Swift can only construct a class through a metatype when the
  initializer is `required`.
- Its layout objects run an invalidation cycle (`invalidateLayout()`, `prepare()`,
  `layoutAttributesForElements(in:)`) that AppKit drives from its own display pass, and the
  data source and delegate protocols are Objective-C `@optional` methods whose absence
  AppKit detects with `respondsToSelector:`; a Swift protocol with defaulted requirements
  cannot tell an implemented method from the default.
- `NSGridView` lays its cells out with Auto Layout on macOS, and the port's layout engine
  (ADR for M5) already runs `NSStackView` that way.
- `NSBox` draws the platform's group box, which differs between the Cairo, Direct2D and
  CoreGraphics canvases only in what the canvas can do, not in what the box asks of it.

## Decision

### NSCollectionView

- **Items on screen only.** As with `NSTableView`, views exist for the elements the
  layout places in the visible rect; `viewWillDraw` makes the missing ones and recycles
  the rest, scrolling redraws the view, and every query (`item(at:)`, `visibleItems()`,
  `indexPathForItem(at:)`) brings the visible set up to date first. Recycled items go
  into a spare pool per reuse identifier; `makeItem(withIdentifier:for:)` hands a spare
  back after `prepareForReuse()`, else constructs the registered class. Supplementary
  views (headers and footers) and decoration views follow the same path.
- **Constructing registered classes.** `NSCollectionViewItem` declares
  `init(nibName:bundle:)` as `required` (AppKit's is not): a subclass without a designated
  initializer of its own inherits it unchanged, a subclass with one must also implement it,
  which is the one divergence from the SDK. Registered *view* classes (supplementary and
  decoration views) are constructed through the `required init?(coder:)` every `NSView`
  subclass already has, with a placeholder coder that decodes nothing, so a class that
  chains to `super.init(coder:)` comes out as a zero-frame view. Nib registrations are
  stored but cannot be loaded (`unimplemented()`), as nowhere else in the port loads nibs.
- **Optional protocol methods.** The generator's `optionalDefaults` give the defaulted
  requirements AppKit's "not implemented" behaviour: `numberOfSections(in:)` is 1, the
  `shouldSelect`/`shouldDeselect`/`shouldChange` methods return their input, and the
  `NSCollectionViewDelegateFlowLayout` metrics return the flow layout's own properties.
  The layouts call the delegate unconditionally and get the right answer either way.
- **The invalidation cycle.** `NSCollectionViewLayout.invalidateLayout(with:)` tells the
  collection view (`_layoutDidInvalidate`), which marks the layout stale and the view
  dirty; the next draw or geometry query runs `prepare()` again and sizes the document
  view to `collectionViewContentSize` (at least the clip view). A clip view resize asks
  `shouldInvalidateLayout(forBoundsChange:)`; the flow layout says yes when the extent
  across its scrolling axis changed, the grid layout whenever the size did. A context
  that names only particular elements still re-prepares the flow layout, whose frames
  depend on every item before them.
- **Flow layout.** Lines wrap at the clip view's width (vertical) or height (horizontal),
  items start at the leading edge of each line with the minimum inter-item spacing and
  are not justified, which is what AppKit's flow layout does and what the Layout Demo
  shows; the per-section insets, spacings, header and footer sizes come from the delegate
  when it implements them. Headers and footers can pin to the visible bounds (they move
  with the scroll and are stacked above the items through `zIndex`); sections collapse
  to their header, and `toggleSectionCollapse(_:)` finds the section of the header a
  sender sits in.
- **Grid layout.** Columns are as many as the minimum item size fits in the width (capped
  by `maximumNumberOfColumns`), the cells share the width up to the maximum size keeping
  the minimum size's proportions, rows follow as the items need (capped by
  `maximumNumberOfRows`; items beyond are hidden), and sections run through the same
  grid. `backgroundColors` stripe the rows.
- **Selection.** `isSelectable` is off by default, as on macOS. The user's clicks, drags
  and keys go through `shouldSelectItemsAt`/`shouldDeselectItemsAt` and report through
  `didSelectItemsAt`/`didDeselectItemsAt`; the item under the mouse is highlighted
  (`forSelection`, or `forDeselection` for a Cmd-click on a selected item) through
  `shouldChangeItemsAt:to:`/`didChangeItemsAt:to:` until the mouse goes up. Setting
  `selectionIndexPaths` or calling `selectItems`/`deselectItems` changes the selection
  without the delegate, as AppKit's programmatic selection does. Arrow keys move to the
  nearest item above or below (by frame) or the previous and next item in order, Shift
  extends from the anchor, Home and End jump, Cmd-A reaches `selectAll(_:)` through the
  responder chain. Items draw no selection themselves: the collection view sets
  `isSelected` and `highlightState` and marks the item's view for display.
- **Batch updates.** `performBatchUpdates` collects the inserts, deletes, moves and
  reloads; deletes and reloads address the old index paths and inserts the new ones
  (moves are a delete plus an insert of the same element). The visible items, the
  selection, the anchor and the highlighted set follow their elements to the new index
  paths, so an item's view keeps its identity across the update; the counts the data
  source then reports must match, or the update fails a precondition with the section
  and counts in the message, as AppKit's exception does. The layout hears
  `prepare(forCollectionViewUpdates:)` and `finalizeCollectionViewUpdates()`; there are
  no animations, so the completion handler runs at once with `true`.
- **Background.** The first of `backgroundColors` fills the view (a grid layout's own
  colours win when set, and more than one colour stripes the grid's rows); a
  `backgroundView` replaces the colours, sits behind every element and covers the content
  or, with `backgroundViewScrollsWithContent` off, the visible rect.
- **Accessibility.** The collection view is an `AXGrid` whose children are the headers'
  elements and the visible items' views in order; each item's view becomes an `AXGroup`
  (unless the view sets a role of its own) at its flat index, selected or not, labelled by
  the item's text field unless the view labels itself. A new seam field,
  `PlatformAccessibilityElement.isSelectable`, tells the platforms which elements take
  selection: UI Automation exposes the SelectionItem pattern on them and the Selection
  pattern on the grid (control type List), AT-SPI2 sets the selectable/selected states
  and maps `AXGrid` to the list role. Selecting or pressing an item through assistive
  technology runs the same delegate path as a click (new `NSView` hooks let a container
  answer for its children).
- **Not done.** Drag and drop out of or into a collection view, the inter-item gap
  indicator, animations, `NSCollectionViewCompositionalLayout`, the diffable data sources
  and the transition layout stay generated stubs, as does the legacy
  `itemPrototype`/`content` path (the properties store their values; `newItem(forRepresentedObject:)`
  is `unimplemented()`). `prefetchDataSource` is stored but not called.

### NSGridView

Rows and columns are Auto Layout tracks: `updateConstraints()` makes a layout guide per
column and per row, chained with the spacing and the paddings (hidden tracks are zero
wide, add no spacing, and hide their content views until shown again), given their
`width`/`height` when set and otherwise hugging their content with a weak zero size so
the content's compression resistance holds them open. Every cell's content view is
placed in its track by the effective x and y placements (the cell's, else the column's
or row's, else the grid's; the grid's default is leading and top) or by the row
alignment for baseline rows (the first view of the row leads, the others meet its
baseline), or by its own `customPlacementConstraints` when set. A merged region
(`mergeCells(inHorizontalRange:verticalRange:)`, and the row's and column's
`mergeCells(in:)`) keeps the top-leading cell's content and spans the region's tracks;
the other cells lose theirs. `intrinsicContentSize` sums the tracks from the content
views' fitting sizes. `NSGridCell.emptyContentView` is the placeholder that leaves a
cell empty in `init(views:)` and the row and column initializers.

### NSBox

`primary` and `secondary` draw macOS's group box (a faint fill and a hairline, rounded);
`custom` draws `fillColor`, `borderColor`, `borderWidth` and `cornerRadius` with the
`borderType`; `separator` is a one-point line across the long axis; `oldStyle` a bevelled
frame. The title sits at the six positions: above and below the border it takes a band of
its own, at the top or bottom it straddles the border, which is drawn through a clip that
leaves a gap for it. `borderRect`, `titleRect` and the content view's frame (the border
inset by the border width, the title band where it is inside, and `contentViewMargins`)
derive from the title position; the content view autoresizes with the box,
`setFrameFromContentFrame` and `sizeToFit` invert the insets. `isTransparent` draws
nothing. The box is an `AXGroup` titled by its title.

## Consequences

- `IndexPath(item:section:)`, `.item` and `.section` are hand-written AppKit additions
  (`Core/IndexPath+AppKit.swift`, listed in the generator's `skipMembers`).
- `NSScrollView.tile` tells any document view about a clip view resize through
  `NSView._clipViewDidResize()` (the table view overrides it as before).
- Tests: `CollectionViewTests` (15: layout attributes, flow wrapping and insets, delegate
  metrics and collapsing, reuse, batch updates, selection and keyboard, pinned headers,
  the grid layout and its stripes, the invalidation cycle, the background view,
  accessibility, grid placement, merges and baselines, the box's geometry and pixels).
- The Layout Demo gains the `collection`, `grid` and `box` tabs (`APPKITWIN_LAYOUT_TAB`),
  rendered by `tools/linux/compare.sh` for docs/comparisons.md.
