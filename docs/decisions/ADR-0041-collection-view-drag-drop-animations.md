# ADR-0041: Collection view drag and drop and animated updates

Date: 2026-11-17. Status: accepted.

## Context

`NSCollectionView` (ADR-0020), its layouts and the diffable data source (ADR-0029) were
hand-written without drag and drop and without animations: `draggingImageForItems`,
`NSCollectionViewItem.draggingImageComponents`, the delegate's drag and drop methods and the
layouts' drop-target queries were stubs or empty, and every batch update (including
`apply(_:animatingDifferences: true)`) changed the views at once. `NSView.beginDraggingSession`,
the drag tracker and the destination driver (ADR-0011) and the table/outline drag code were
already in place on every backend, as was the layer animation path behind `animator()`.

AppKit's behaviour was probed on macOS 15 (throwaway Swift programs against the real
framework) before writing the port's: the drop targets and inter-item gap frames of a flow
and a grid layout, the components `draggingImageComponents` returns, the appearing and
disappearing attributes a flow layout answers during an update, the archive keys of the
layouts, and the legacy `frameForItem(at:withNumberOfItems:)` grid.

## Decision

**Delegate defaults.** The Objective-C protocol makes every drag and drop method optional and
AppKit asks `respondsToSelector:`; the port has no such check, so the generated protocol
extension supplies what an unimplemented method means (config `optionalDefaults`, which now
accepts a per-overload map keyed by a fragment of the declaration). Each index-path form falls
back to its old index form when the collection view has one section, exactly AppKit's lookup
order ("the old methods will not be invoked for a multi-section NSCollectionView"); the old
forms default to AppKit's answers when neither is implemented: `canDragItemsAt` true (the
header: "the collection view will act as if it returned YES"), no pasteboard writer, no
`writeItemsAt`, no drop (`validateDrop` none, `acceptDrop` false), no promised files, and the
drag image from `NSCollectionView.draggingImageForItems`. The generated default for
`canDragItemsAt` used to say false.

**Drag source.** A press on an item followed by a move of more than 3 points starts a drag of
that item, or of the whole selection when the item is selected (a press on one of several
selected items no longer collapses the selection at once: the plain click selects just it on
mouse-up, as in AppKit). The delegate vets the index paths with `canDragItemsAt`, then gives a
pasteboard writer per item; each becomes an `NSDraggingItem` at the item's frame whose image
components come from `NSCollectionViewItem.draggingImageComponents`. Without writers the
legacy path runs: `writeItemsAt` fills the drag pasteboard and one image
(`draggingImageForItemsAt`, centred under the pointer plus the returned offset) represents the
items. The session goes through `NSView.beginDraggingSession`, as the outline view's does, so
every backend (tracker-driven on the host and X11, OLE on Windows, the data device on Wayland)
carries it. The collection view is the `NSDraggingSource`: its masks default to every
operation locally and none outside (`setDraggingSourceOperationMask`), and it forwards
`willBeginAt`/`endedAt` to the delegate. `draggingImageComponents` follows AppKit: an `.icon`
snapshot of the image view and a `.label` of the text field (the text field is the `.icon`
when there is no image view; the whole view when there is neither), frames measured from the
item view's bottom-left. The drag tracker now composes an item's several components into its
drag image instead of showing the first.

**File promises.** `NSDraggingInfo.namesOfPromisedFilesDropped(atDestination:)` reaches a
collection view source, which asks its delegate's `namesOfPromisedFilesDroppedAtDestination`
for the dragged items (AppKit's legacy promise path). `NSFilePromiseProvider` and
`NSFilePromiseReceiver` remain generated stubs: they are a feature of their own.

**Drop destination.** With types registered, the collection view proposes a target from the
layout's `layoutAttributesForDropTarget(at:)`: over an item, on it when the pointer is nearer
the item's middle than its edges along the line, else before it or before the next item; over
an inter-item gap, before the item after the gap; nothing from the layout, before the end of
the last section. The delegate's `validateDrop` gets the proposal through the in/out pointers
(an `NSIndexPath` and the operation) and may retarget it; a non-empty answer shows the target:
`.on` sets the item's `highlightState` to `.asDropTarget` (through `shouldChangeItemsAt`, whose
refusal refuses the drop, as the header says), `.before` shows the inter-item gap indicator at
the layout's gap frame. The indicator is the data source's supplementary view when a class or
nib is registered for `elementKindInterItemGapIndicator`, else a bar in the accent colour; it
stays above the items and never takes clicks. `prepareForDragOperation` needs a target,
`performDragOperation` calls `acceptDrop` with it, and exit, conclusion and the end of the drag
clear it. A drag hovering within 16 points of the visible edge scrolls. `NSCollectionView` has
no `draggingDestinationFeedbackStyle` in the SDK (that is `NSTableView`'s), so none is added.

**Layout drop targets and gaps.** The flow and grid layouts lay items out in lines, so one
implementation in `NSCollectionViewLayout` serves both: a point inside an item targets the
item; otherwise the nearest line of the section the point is in (a flow keeps section frames;
the grid's sections share one run) is chosen, and the target is the gap before the first item
whose middle lies past the point (after the line's last item when none does). Gap frames
match AppKit's: between the neighbours, one spacing wide ahead of a line's first item and
after its last. Lines run across for vertical scrolling (mirrored right to left) and down for a
horizontal flow. An empty section targets the gap before its first item. The base layout
answers nothing, as AppKit's does.

**Animated updates.** `performBatchUpdates` and the single-change calls animate when they are
sent through `animator()` with a non-zero `NSAnimationContext` duration and the collection view
is in a window on screen; `apply(_:animatingDifferences:)` already sends them so, and its
`false` path stays an instant update. `NSView.animator()` now also records the request when the
view has no layer yet (`_takeAnimatorRequest`), and an animating collection view becomes
layer-backed, as AppKit's effectively always is. The model is final at once (frames, alpha,
selection): the layers animate from where the update started. During the update the
collection view gives the layout the old-to-new index path map and, for an animated update,
the attributes the old layout gave; the flow and grid layouts then answer
`initialLayoutAttributesForAppearingItem` and `finalLayoutAttributesForDisappearingItem` as
AppKit's do (a surviving item from its old frame, an inserted one at its new frame
transparent, a deleted one at its old frame transparent; outside an update, the current
attributes transparent). The layout prepares before `prepare(forCollectionViewUpdates:)`, in
UICollectionView's order. Every visible item animates from the initial attributes (else its
old view state, else transparent if inserted) to its final frame and alpha; deleted and
reloaded items keep their views, animate to the final attributes (else fade in place), take no
clicks, and are recycled when the animation group completes, which is also when the batch's
completion handler runs. An instant update runs the handler before returning. Nothing is
invalidated from `draw`.

An off-screen update is instant: the port advances layer animations only for trees on screen,
so an animation in a window never shown would never complete. That exposed a QuartzCore bug:
transaction completion blocks waited in one queue and every finished animation counted against
the first, so one never-finishing group stalled every later completion. Each transaction now
has a token its animations carry, and an animation replaced under its key counts as finished
for its own transaction.

**Remaining stubs.** `frameForItem(at:withNumberOfItems:)` reproduces the legacy grid (columns
of `minItemSize`, or the prototype view's size, never more than the items or
`maxNumberOfColumns`, widened up to `maxItemSize`, rows without spacing).
`newItem(forRepresentedObject:)` copies `itemPrototype`; `NSCollectionViewItem.copy` makes an
item of the same class and nib with the same represented object, whose view comes from
`loadView()` at the original's size: AppKit copies the view by archiving it, and the port cannot
archive views. The layouts archive and unarchive under AppKit's keys (`NSItemSize`,
`NSSectionInset`, `NSMargins`, …, sizes and insets as `NSValue`s, only non-default values
written, absent keys keeping defaults since corelibs' unarchiver aborts on a missing key), and
`NSCollectionView.init?(coder:)` reads its selection, background and dragging-mask keys. The
nib registrations stay `unimplemented()`: the port cannot load nibs.

## Consequences

- Drag and drop works on every backend through the existing session and destination paths;
  Windows drags within the application run through OLE and come back through the platform
  delivery, so the PC checklist covers reordering and dropping text from other applications.
- The legacy `content`/`itemPrototype` display mode (items made from `content` without a data
  source) is still not drawn; only the members around it work.
- The port's flow layout starts every line at the leading edge with the minimum spacing,
  where AppKit's spreads the items of full lines across the width (the last line stays at
  the leading edge). Drop targets and gaps follow whichever positions the layout produced; the
  justification is a separate fidelity fix.
- `NSFilePromiseProvider`/`NSFilePromiseReceiver` and the compositional layout remain
  generated stubs.
- Tests: `CollectionViewDragDropTests` (13): drags synthesised through the host backend's
  event path (delegate call order, pasteboard contents, drop index paths and operations,
  retargeting, reordering, the legacy forms), the grid's AppKit-probed targets and gaps, flow
  targets vertical and horizontal, drag image components, animated updates ending at the
  instant update's frames, diffable animation only when asked, the transaction completion fix,
  the legacy grid frames, and layout archiving.
