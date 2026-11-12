# ADR-0035: Bindings and the controller classes

Date: 2026-11-12. Status: accepted.

## Context

`NSObjectController`, `NSArrayController`, `NSTreeController`, `NSTreeNode`,
`NSUserDefaultsController`, their base `NSController`, `NSBindingSelectionMarker` and
`NSRuleEditor` were generated stubs (203 `unimplemented()` members between them). They are
Cocoa bindings: a view's property follows a key path on a controller (`arrangedObjects.name`,
`selection.name`), and edits flow back. On macOS that machinery is Foundation's key-value coding
(KVC) and key-value observing (KVO). swift-corelibs-foundation has neither: `NSObject` has no
`value(forKey:)` or `didChangeValue(forKey:)`, `NSSortDescriptor(key:)` and
`NSPredicate(format:)` are unavailable, and `NSExpression`/`NSComparisonPredicate` trap in every
initializer. There was no bindings support in Core to extend; `NSObject.bind(_:to:withKeyPath:options:)`
and the rest of `NSKeyValueBindingCreation` were not emitted at all (the generator does not emit
AppKit's `NSObject` extensions).

## Decision

**A portable key-value layer, used on every platform** (`Core/NSKeyValueBinding.swift`).

- `_KVC` reads and writes key paths. In order: the controllers and proxies of this module (an
  internal protocol), objects adopting the new **`NSKeyValueBindingCoding`** protocol (additive
  API: `bindingValue(forKey:)`, `setBindingValue(_:forKey:)`), Foundation collections, Swift
  arrays and dictionaries, on macOS any `NSObject` that answers the key (real KVC, guarded by
  `responds(to:)`), and finally stored properties found through `Mirror`. A key applied to an
  array maps over the elements; `@count`, `@sum`, `@avg`, `@min`, `@max` work. An undefined key
  traps with Foundation's "not key value coding-compliant" message, as KVC raises.
- `_KVO` is an observation hub keyed by object identity and key (plus an any-key observer). The
  controllers post to it directly; every write made through a binding is announced; a model
  announces its own changes with `didChangeValue(forKey:)` — Foundation's method on macOS, where a
  bridge observer forwards real KVO for the key into the hub, and an equivalent `NSObject`
  extension on corelibs (which has none). So an `@objc dynamic` model works unchanged on macOS and
  the same model adopting `NSKeyValueBindingCoding` works everywhere.
- `_KeyPathObservation` follows a multi-component path, re-observing intermediate objects — every
  element of an intermediate array, and the selected objects behind the selection proxy — when an
  earlier component changes.
- `NSObject.bind/unbind/infoForBinding/exposedBindings/exposeBinding` (Apple's names and
  signatures) record a binding, observe the key path and hand each value to the receiver. Classes
  that define bindings apply them; for anything else the binding name is set through `_KVC`, as
  NSObject's default does. `valueClassForBinding` is `unimplemented()`;
  `optionDescriptionsForBinding` needs Core Data's `NSAttributeDescription` and is absent like the
  rest of Core Data. Value transformers apply on macOS; corelibs has no `ValueTransformer`, so a
  transformer option there reaches `unimplemented()`.

**The controllers.** `NSController` keeps registered editors for `commitEditing()`/`discardEditing()`
(a bound text field registers while it edits). `NSObjectController` has the content object and the
**selection proxy**: reading a key answers the selected objects' common value, or
`NSBindingSelectionMarker.noSelection`/`.multipleValues`; writing sets every selected object.
`NSArrayController` follows AppKit's rules: arrangement = filter, then a stable sort; inserted
objects stay where they are put until `rearrangeObjects()` unless `automaticallyRearrangesObjects`
(which rearranges when any content object announces a change); `clearsFilterPredicateOnInsertion`,
`selectsInsertedObjects`, `preservesSelection` (by object), `avoidsEmptySelection` (first object
for new content, the nearest object after a removal); `setSelectionIndexes` commits edits first and
returns whether the selection changed; `add:`/`insert:`/`remove:` commit and run on the next pass of
the main queue, as AppKit defers them. `NSTreeController` builds `NSTreeNode`s from `childrenKeyPath`
(leaf from `leafKeyPath`, else `countKeyPath`, else the child count), sorts each level, keeps the
selection as index paths, and inserts/removes/moves by editing the model (the root array, or the
parent's children array through `_KVC`); a change a model announces for those key paths rebuilds the
tree. `NSTreeNode.mutableChildren` is live (on macOS a KVC collection proxy, since Swift cannot
subclass `NSArray` there; on corelibs an `NSMutableArray` subclass). `NSUserDefaultsController.values`
reads unapplied changes, then the defaults, then `initialValues`, writes at once or on `save:`, and
follows `UserDefaults.didChangeNotification`. Controllers answer `add:`, `remove:`, `insert:`,
`selectNext:`, `addChild:`, `save:`... through the port's target/action (`NSSelectorHandling`), so
a button can target the controller as in AppKit. Core Data (`fetch:`, entities, managed object
contexts) and archiving stay `unimplemented()`.

**View bindings** (`Core/NSKeyValueBinding+Views.swift`). `hidden`, `toolTip` (views); `enabled`,
`value` (controls, written back before the control sends its action); text fields: `value` with the
null/selection-marker placeholders (binding option, then `NSBindingSelectionMarker`'s registered
default placeholder, then "No Selection"/"Multiple Values"/"Not Applicable"), editable only for a
single value (`conditionallySetsEditable`), written back when editing ends or on every change with
`continuouslyUpdatesValue`, `editable`, `textColor`; buttons: `value` (state), `title`; pop-ups:
`content`, `contentObjects`, `contentValues`, `selectedIndex`, `selectedObject`, `selectedValue`,
`selectedTag`; tables: `content`, `selectionIndexes`, `sortDescriptors`, and columns: `value`.
As in AppKit, binding a column to an array controller's `arrangedObjects.<key>` binds the table's
content, selection and sort descriptors to that controller implicitly. Bound tables show text cells
(cell editing in a bound table is not implemented). Other binding options are ignored.

**NSRuleEditor.** Rows are a tree addressed in display order. A row's criteria are a path through
the delegate's criterion tree for its row type (first children by default, kept across
`reloadCriteria()` where the delegate still offers them). The row UI is package-drawn: string
display values become pop-ups of their siblings' display values (a label when there is one), views
are embedded, rows stripe and show the selection, and +/− buttons add a sibling (a child on a
compound row; Option for a compound row in compound nesting) and remove a subtree, honouring
`canRemoveAllRows`, `isEditable` and the nesting mode. Picking a criterion rebuilds the rest of the
path; changes post `rowsDidChangeNotification`, tell the delegate and send the action; a text edit in
a row sends the action. The predicate merges every criterion's predicate parts: compound rows give
compound predicates, simple rows comparison predicates, several root rows an AND. On macOS the
parts are NSExpressions and the result is Foundation's `NSComparisonPredicate`; on corelibs, which
cannot build either, a left expression may be a key-path string and a right expression a plain
value (accepted on macOS too), and the editor returns a comparison predicate of its own that
evaluates through `_KVC` (all operators but custom selectors, case/diacritic options, ANY/ALL) and
prints Apple's format (`name BEGINSWITH[c] "A" AND age > 30`, nested compounds in parentheses), plus
a compound-predicate subclass that prints its format. `formattingDictionary` and
`formattingStringsFilename` are stored but not applied.

## Consequences

- `NSArrayController`, `NSTreeController` and `NSBindingSelectionMarker` have no `unimplemented()`
  left; the rest keep only Core Data, `NSCoding`, the three-argument `commitEditing(withDelegate:...)`
  callback and the corelibs-only paths above (13 in the eight classes, from 203, plus four in the
  bindings layer: `valueClassForBinding` and value transformers on corelibs).
- Model objects off macOS adopt `NSKeyValueBindingCoding` (or rely on reflection for read-only
  stored properties) and call `didChangeValue(forKey:)` after direct changes. Swift classes with
  `@objc dynamic` properties need nothing on macOS.
- corelibs bridges `NSArray`/`NSDictionary` contents to Swift value types on every read, so
  dictionary model objects inside collections lose identity there (the port falls back to `isEqual`);
  tree content should be class objects. `objectClass` instantiation needs a `required init()`, which
  corelibs' `NSObject` lacks: override `newObject()` there.
- Our controllers do not post real KVO on macOS (their properties are Swift, not `@objc dynamic`);
  observe them through bindings. In the macOS host test target Apple's AppKit is visible through
  XCTest, so `bind(.value, ...)` is ambiguous there; tests spell `NSBindingName.value`.
- Tests: `BindingsTests.swift` (28 tests: array controller arrangement, selection and proxy,
  content binding, editors, deferred actions; table, text field, pop-up and checkbox bound to a
  controller; tree controller index paths, model edits, leaf/count key paths; NSTreeNode;
  user-defaults controller; rule editor list and compound predicates, row buttons, queries) on macOS
  and in the Linux container. Layout Demo tab `bindings` (`APPKITWIN_LAYOUT_TAB=bindings`): a table,
  detail fields, a checkbox and a pop-up bound to one array controller, +/− buttons targeting it, and
  a rule editor whose predicate filters the table.
- Not yet: `NSDictionaryController`, outline views bound to a tree controller, editing cells in a
  bound table, display-pattern bindings, value transformers on corelibs, rule-editor row bindings
  (`rows`, `rowClass`) and formatting dictionaries, `NSPredicateEditor`.
