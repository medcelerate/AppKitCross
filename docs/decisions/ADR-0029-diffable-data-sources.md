# ADR-0029: Diffable data sources

Date: 2026-11-10. Status: accepted.

## Context

`NSDiffableDataSourceSnapshot`, `NSTableViewDiffableDataSource` and
`NSCollectionViewDiffableDataSource` were generated stubs. Modern AppKit code (and code ported
from UIKit) builds its tables and collection views on them: the app describes the whole content
as a snapshot of section and item identifiers, and `apply` works out the inserts, deletes and
moves and drives the view's batch updates. The table (PR 41) and the collection view (PR 45,
ADR-0020) already implement those batch updates, so the data sources are a layer on top.

## Decision

**Snapshot.** A value type holding the section identifiers in order and, per section, its item
identifiers in order, with a map from item to section. Identifiers are compared through their
`Hashable` conformance only (an item type whose `==` looks at an id alone is matched by id, as
on macOS). Every item identifier is unique in the whole snapshot and every section identifier
among the sections; a duplicate, an anchor the snapshot does not hold (insert/move before or
after it), a move relative to itself, a reload of an unknown identifier and appending items with
no section are precondition failures with messages close to AppKit's exceptions. Deleting
unknown identifiers is ignored. `reloadItems`/`reloadSections` set marks that travel with the
snapshot to `apply`, which consumes them: `snapshot()` returns the contents without marks.
Only the members in the SDK's symbol graph exist; `reconfigureItems` and
`reloadedItemIdentifiers` are UIKit-only and are not added.

**The diff (Support/IdentifierDiff.swift).** Because identifiers are unique, Heckel's
"unique lines" pass pairs every surviving element with its old and new position through one
hash table. The elements that keep their place are a longest increasing subsequence of the old
positions taken in new order (patience sort, O(n log n)), which for unique elements is the
longest common subsequence: every other survivor is a move, so the move count is the minimum.
Myers' algorithm was not used: it reports moves as a delete plus an insert, which would make a
table drop and recreate the row view of every moved row.

Two forms are produced. The collection view's batch convention (deletes and reloads at old index
paths, inserts at new ones, moves old to new, all applied at the end of `performBatchUpdates`)
takes the diff directly. The table applies `insertRows`/`removeRows`/`moveRow` one after the
other inside `beginUpdates`/`endUpdates`, each in the coordinates the previous one left, so
`sequentialEdits` turns the diff into steps: one removal of every deleted row, then, in new
order, each insert (consecutive ones merged) and each move placed right after its new
predecessor. Applying the steps to the old ordering yields the new one exactly; a randomized
test checks that for 300 cases.

**Table.** The data source sets itself as the table's `dataSource` (the table holds it weakly,
as on macOS). The SDK class conforms only to `NSTableViewDataSource`, yet AppKit takes the cell
views from its cell provider rather than the delegate; the port does the same through an
internal protocol (`_NSTableViewContentProviding`) that `NSTableView`'s subclass hooks consult
before the delegate for the cell view, the row view (`rowViewProvider`) and group rows. The
delegate keeps heights, selection and the rest. Rows are the snapshot flattened; with a
`sectionHeaderViewProvider` each section adds a header row first, which is a group row and whose
view spans the row. `row(forSectionIdentifier:)` gives that header row, or the section's first
item row without headers. `apply` diffs the flattened rows, then calls
`reloadData(forRowIndexes:columnIndexes:)` for reloaded items and every row of reloaded
sections that existed before.

`NSTableView` now keeps its row views with their rows through `insertRows`/`removeRows`/
`moveRow`: it tracks where each live row view's row went during the update block and at
`endUpdates` re-files the views (with their cells) instead of dropping them all, so a moved row
keeps its view, its cells and its accessibility element, and only inserted rows ask for cells.
The selection mapping for multiple inserted rows was also corrected.

**Collection view.** Sections are diffed first (deletes, inserts, moves; reloads at their old
index). Items are diffed inside every section present on both sides and not reloaded: an item
that stays (the common run of its section) is left alone, any other survivor between two such
sections is a move (also across sections), the rest are deletes and inserts. An item that comes
from or goes to an inserted, deleted or reloaded section is only an insert or a delete on the
other side; the section operation covers its own side. Reloaded items surviving in such sections
are reloaded at their old index path. The new snapshot is installed inside the batch block, after
the view has read the old counts, so the collection view's count check sees the old and new
states it expects. Two bugs in the batch updates surfaced and are fixed here: a moved section
took its items before the item deletes inside it were applied, and the selection was filtered
against the new counts before being mapped to the new index paths.

**Animation.** `animatingDifferences: true` passes `defaultRowAnimation` (`.effectFade` by
default) to the table's row calls and runs the collection view's batch through `animator()`;
`false` passes no animation options and runs the batch in a zero-duration animation group. Both
still apply the diff (as on macOS 12 and later) rather than reloading everything, so selection
and views survive. The port's table and collection view do not animate rows or items yet, so
both land at once; the choice is visible to subclasses and to a future animation pass.

**Threads.** `apply` and the initializers may be called off the main thread (AppKit allows a
background `apply`): the work then runs synchronously on the main queue. The completion handler
is called after the updates, on the caller's thread.

## Consequences

- Tables and collection views can be driven entirely by snapshots; `DiffableTests` (17) cover
  the diff, snapshot semantics, both data sources with recording subclasses counting the update
  calls, animated and non-animated applies, and randomized applies against the snapshot.
- Layout Demo tab `diffable`: a table with section header rows and a swatch collection driven
  by one snapshot, with Shuffle, Insert, Delete and Reload; `APPKITWIN_DIFFABLE_STEPS` runs steps
  on launch for the comparison renders.
- Not done: the Objective-C `NSDiffableDataSourceSnapshotReference`/`…DataSourceReference`
  classes stay generated stubs; row and item animations belong to the views.
