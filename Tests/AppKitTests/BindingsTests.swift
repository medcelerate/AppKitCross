// Bindings controllers (ADR-0032): NSArrayController arrangement and selection, the selection
// proxy, views bound to a controller (table, text field, pop-up, checkbox), NSTreeController
// index paths, NSTreeNode, and NSRuleEditor rows and predicates.

import XCTest
@testable import AppKit

// MARK: - Model

#if canImport(ObjectiveC)
/// On macOS the model is an ordinary KVO-compliant NSObject: Foundation's key-value coding
/// and observing serve the bindings, sort descriptors and format predicates.
final class BindingPerson: NSObject {
    @objc dynamic var name: String
    @objc dynamic var age: Int
    @objc dynamic var isMember: Bool = false
    init(_ name: String, _ age: Int) { self.name = name; self.age = age }
    override var description: String { name }
}
#else
/// Without the Objective-C runtime the model adopts NSKeyValueBindingCoding and announces
/// direct changes with didChangeValue(forKey:).
final class BindingPerson: NSObject, NSKeyValueBindingCoding {
    var name: String
    var age: Int
    var isMember: Bool = false
    init(_ name: String, _ age: Int) { self.name = name; self.age = age }
    override var description: String { name }
    func bindingValue(forKey key: String) -> Any? {
        switch key {
        case "name": return name
        case "age": return age
        case "isMember": return isMember
        default: return nil
        }
    }
    func setBindingValue(_ value: Any?, forKey key: String) {
        switch key {
        case "name": name = (value as? String) ?? String(describing: value ?? "")
        case "age": age = (value as? Int) ?? Int(String(describing: value ?? "")) ?? 0
        case "isMember": isMember = (value as? Bool) ?? false
        default: break
        }
    }
}
#endif

/// Changes a property directly, the way app code does, and announces it where the runtime
/// does not.
private func rename(_ p: BindingPerson, _ name: String) {
    p.name = name
    #if !canImport(ObjectiveC)
    p.didChangeValue(forKey: "name")
    #endif
}

#if canImport(ObjectiveC)
final class BindingRoster: NSObject {
    @objc dynamic var people: [BindingPerson] = []
}
#else
final class BindingRoster: NSObject, NSKeyValueBindingCoding {
    var people: [BindingPerson] = []
    func bindingValue(forKey key: String) -> Any? { key == "people" ? people : nil }
    func setBindingValue(_ value: Any?, forKey key: String) {
        if key == "people" { people = (value as? [Any])?.compactMap { $0 as? BindingPerson } ?? [] }
    }
}
#endif

private func people() -> [BindingPerson] {
    [BindingPerson("Cleo", 41), BindingPerson("Abe", 29), BindingPerson("Dana", 35), BindingPerson("Bea", 52)]
}

private func names(_ value: Any) -> [String] { (value as? [Any] ?? []).map { ($0 as! BindingPerson).name } }

private var byName: NSSortDescriptor { NSSortDescriptor(keyPath: \BindingPerson.name, ascending: true) }
private var byAgeDescending: NSSortDescriptor { NSSortDescriptor(keyPath: \BindingPerson.age, ascending: false) }
private func olderThan(_ n: Int) -> NSPredicate { NSPredicate { o, _ in ((o as? BindingPerson)?.age ?? 0) > n } }

// MARK: - Array controller

final class ArrayControllerTests: XCTestCase, @unchecked Sendable {
    func testArrangeSortsThenFilters() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            XCTAssertEqual(names(ac.arrangedObjects), ["Cleo", "Abe", "Dana", "Bea"])
            ac.sortDescriptors = [byName]
            XCTAssertEqual(names(ac.arrangedObjects), ["Abe", "Bea", "Cleo", "Dana"])
            ac.filterPredicate = olderThan(34)
            XCTAssertEqual(names(ac.arrangedObjects), ["Bea", "Cleo", "Dana"])
            ac.sortDescriptors = [byAgeDescending]
            XCTAssertEqual(names(ac.arrangedObjects), ["Bea", "Cleo", "Dana"])
            ac.filterPredicate = nil
            XCTAssertEqual(names(ac.arrangedObjects), ["Bea", "Cleo", "Dana", "Abe"])
            XCTAssertEqual((ac.content as? [Any])?.count, 4, "arranging never changes the content")
            XCTAssertEqual(names(ac.arrange(people())), ["Bea", "Cleo", "Dana", "Abe"])
        }
    }

    func testSortIsStableForEqualKeys() {
        MainActor.assumeIsolated {
            let ps = [BindingPerson("x1", 30), BindingPerson("x2", 20), BindingPerson("x3", 30), BindingPerson("x4", 20)]
            let ac = NSArrayController(content: ps)
            ac.sortDescriptors = [NSSortDescriptor(keyPath: \BindingPerson.age, ascending: true)]
            XCTAssertEqual(names(ac.arrangedObjects), ["x2", "x4", "x1", "x3"])
        }
    }

    func testSelectionDefaultsAndPreservation() {
        MainActor.assumeIsolated {
            let ps = people()
            let ac = NSArrayController()
            XCTAssertEqual(ac.selectionIndex, NSNotFound)
            ac.content = ps
            XCTAssertEqual(ac.selectionIndexes, [0], "avoidsEmptySelection selects the first object")
            XCTAssertTrue(ac.setSelectionIndex(2))
            XCTAssertFalse(ac.setSelectionIndex(2), "no change, no YES")
            XCTAssertEqual(names(ac.selectedObjects), ["Dana"])
            ac.sortDescriptors = [byName]
            XCTAssertEqual(names(ac.selectedObjects), ["Dana"], "preservesSelection follows the object")
            XCTAssertEqual(ac.selectionIndex, 3)
            ac.preservesSelection = false
            ac.sortDescriptors = [byAgeDescending]
            XCTAssertEqual(ac.selectionIndex, 3, "without preservesSelection the index stays")
            XCTAssertEqual(names(ac.selectedObjects), ["Abe"])
            XCTAssertTrue(ac.setSelectionIndexes([0, 9]))
            XCTAssertEqual(ac.selectionIndexes, [0], "indexes outside the arrangement are dropped")
            XCTAssertTrue(ac.addSelectionIndexes([2]))
            XCTAssertEqual(ac.selectionIndexes, [0, 2])
            XCTAssertTrue(ac.removeSelectionIndexes([0]))
            XCTAssertEqual(ac.selectionIndexes, [2])
            XCTAssertTrue(ac.setSelectedObjects([ps[1]]))
            XCTAssertEqual(names(ac.selectedObjects), ["Abe"])
        }
    }

    func testRemovalSelectsTheNearestObject() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            _ = ac.setSelectionIndex(1)
            ac.remove(atArrangedObjectIndex: 1)
            XCTAssertEqual(names(ac.arrangedObjects), ["Cleo", "Dana", "Bea"])
            XCTAssertEqual(ac.selectionIndexes, [1], "the object that moved up into the removed slot")
            _ = ac.setSelectionIndex(2)
            ac.remove(atArrangedObjectIndex: 2)
            XCTAssertEqual(ac.selectionIndexes, [1], "removing the last selects the new last")
            ac.avoidsEmptySelection = false
            ac.remove(atArrangedObjectIndex: 1)
            XCTAssertEqual(ac.selectionIndexes, [])
            XCTAssertFalse(ac.canRemove)
        }
    }

    func testInsertionAddsSelectsAndClearsTheFilter() {
        MainActor.assumeIsolated {
            let ps = people()
            let ac = NSArrayController(content: ps)
            ac.sortDescriptors = [byName]
            ac.filterPredicate = olderThan(40)
            XCTAssertEqual(names(ac.arrangedObjects), ["Bea", "Cleo"])
            let eve = BindingPerson("Eve", 19)
            ac.addObject(eve)
            XCTAssertNil(ac.filterPredicate, "clearsFilterPredicateOnInsertion")
            XCTAssertEqual(names(ac.arrangedObjects), ["Abe", "Bea", "Cleo", "Dana", "Eve"])
            XCTAssertEqual(names(ac.selectedObjects), ["Eve"], "selectsInsertedObjects")
            // Without automatic rearrangement an inserted object stays where it was put.
            let al = BindingPerson("Al", 60)
            ac.insert(al, atArrangedObjectIndex: 2)
            XCTAssertEqual(names(ac.arrangedObjects), ["Abe", "Bea", "Al", "Cleo", "Dana", "Eve"])
            XCTAssertEqual(ac.selectionIndexes, [2])
            ac.rearrangeObjects()
            XCTAssertEqual(names(ac.arrangedObjects), ["Abe", "Al", "Bea", "Cleo", "Dana", "Eve"])
            XCTAssertEqual(names(ac.selectedObjects), ["Al"])
            ac.selectsInsertedObjects = false
            ac.add(contentsOf: [BindingPerson("Zed", 1)])
            XCTAssertEqual(names(ac.selectedObjects), ["Al"])
            ac.remove(contentsOf: [al, eve])
            XCTAssertEqual(names(ac.arrangedObjects), ["Abe", "Bea", "Cleo", "Dana", "Zed"])
            XCTAssertEqual((ac.content as? [Any])?.count, 5)
        }
    }

    func testAutomaticRearrangement() {
        MainActor.assumeIsolated {
            let ps = people()
            let ac = NSArrayController(content: ps)
            ac.sortDescriptors = [byName]
            rename(ps[0], "Aaron")      // Cleo
            XCTAssertEqual(names(ac.arrangedObjects), ["Abe", "Bea", "Aaron", "Dana"], "no rearrangement by default")
            ac.automaticallyRearrangesObjects = true
            XCTAssertEqual(names(ac.arrangedObjects), ["Aaron", "Abe", "Bea", "Dana"])
            rename(ps[0], "Zoe")
            XCTAssertEqual(names(ac.arrangedObjects), ["Abe", "Bea", "Dana", "Zoe"])
            XCTAssertNotNil(ac.automaticRearrangementKeyPaths)
        }
    }

    func testCanFlagsAndNavigation() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            XCTAssertTrue(ac.canAdd && ac.canInsert && ac.canRemove)
            XCTAssertFalse(ac.canSelectPrevious)
            XCTAssertTrue(ac.canSelectNext)
            ac.selectNext(nil)
            ac.selectNext(nil)
            XCTAssertEqual(ac.selectionIndex, 2)
            ac.selectPrevious(nil)
            XCTAssertEqual(ac.selectionIndex, 1)
            ac.isEditable = false
            XCTAssertFalse(ac.canAdd || ac.canInsert || ac.canRemove)
        }
    }

    func testSelectionProxyAnswersMarkersAndWritesThrough() {
        MainActor.assumeIsolated {
            let ps = people()
            let ac = NSArrayController(content: ps)
            let selection = ac.selection
            XCTAssertEqual(_KVC.value(selection, forKey: "name") as? String, "Cleo")
            _ = ac.setSelectionIndexes([0, 1])
            XCTAssertTrue(_KVC.value(selection, forKey: "name") as? NSBindingSelectionMarker === NSBindingSelectionMarker.multipleValues)
            _KVC.setValue(true, on: selection, forKeyPath: "isMember")
            XCTAssertTrue(ps[0].isMember && ps[1].isMember && !ps[2].isMember)
            XCTAssertEqual(_KVC.value(selection, forKey: "isMember") as? Bool, true, "equal values are one value")
            ac.alwaysUsesMultipleValuesMarker = true
            XCTAssertTrue(_KVC.value(selection, forKey: "isMember") as? NSBindingSelectionMarker === NSBindingSelectionMarker.multipleValues)
            _ = ac.setSelectionIndexes([])
            XCTAssertTrue(_KVC.value(selection, forKey: "name") as? NSBindingSelectionMarker === NSBindingSelectionMarker.noSelection)
            XCTAssertEqual(_KVC.value(ac, forKeyPath: "arrangedObjects.@count") as? Int, 4)
            XCTAssertEqual(_KVC.value(ac, forKeyPath: "arrangedObjects.name") as? [String], ["Cleo", "Abe", "Dana", "Bea"])
        }
    }

    func testDeferredActionsRunOnTheNextPass() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            ac.objectClass = NSMutableDictionary.self
            let done = expectation(description: "add ran")
            ac.add(nil)
            XCTAssertEqual((ac.content as? [Any])?.count, 4, "add: waits for the run loop")
            DispatchQueue.main.async { done.fulfill() }
            wait(for: [done], timeout: 2)
            XCTAssertEqual((ac.content as? [Any])?.count, 5)
            XCTAssertTrue(ac.selectedObjects.first is NSMutableDictionary)
        }
    }

    func testContentArrayBindingWritesTheModel() {
        MainActor.assumeIsolated {
            let roster = BindingRoster()
            roster.people = people()
            let ac = NSArrayController()
            ac.bind(NSBindingName.contentArray, to: roster, withKeyPath: "people")
            XCTAssertEqual(names(ac.arrangedObjects), ["Cleo", "Abe", "Dana", "Bea"])
            ac.addObject(BindingPerson("Eve", 30))
            XCTAssertEqual(roster.people.map(\.name), ["Cleo", "Abe", "Dana", "Bea", "Eve"])
            ac.remove(atArrangedObjectIndex: 0)
            XCTAssertEqual(roster.people.map(\.name), ["Abe", "Dana", "Bea", "Eve"])
            _KVC.setValue([BindingPerson("Solo", 1)], on: roster, forKeyPath: "people")
            XCTAssertEqual(names(ac.arrangedObjects), ["Solo"])
            let info = ac.infoForBinding(NSBindingName.contentArray)
            XCTAssertTrue(info?[NSBindingInfoKey.observedObject] as AnyObject? === roster)
            XCTAssertEqual(info?[NSBindingInfoKey.observedKeyPath] as? String, "people")
            ac.unbind(NSBindingName.contentArray)
            XCTAssertNil(ac.infoForBinding(NSBindingName.contentArray))
            XCTAssertTrue(ac.exposedBindings.contains(NSBindingName.contentArray))
        }
    }

    func testCommitEditingReachesRegisteredEditors() {
        MainActor.assumeIsolated {
            final class Editor: NSObject, NSEditor {
                var commits = 0
                func commitEditing() -> Bool { commits += 1; return true }
            }
            MainActor.assumeIsolated {
                let ac = NSArrayController(content: people())
                let e = Editor()
                ac.objectDidBeginEditing(e)
                XCTAssertTrue(ac.isEditing)
                XCTAssertTrue(ac.setSelectionIndex(3))
                XCTAssertEqual(e.commits, 1, "changing the selection commits pending edits")
                ac.objectDidEndEditing(e)
                XCTAssertFalse(ac.isEditing)
            }
        }
    }

    func testObjectControllerSelection() {
        MainActor.assumeIsolated {
            let p = BindingPerson("Ann", 3)
            let oc = NSObjectController(content: p)
            XCTAssertEqual(_KVC.value(oc, forKeyPath: "selection.name") as? String, "Ann")
            oc.content = nil
            XCTAssertTrue(_KVC.value(oc, forKeyPath: "selection.name") as? NSBindingSelectionMarker === NSBindingSelectionMarker.noSelection)
            oc.prepareContent()
            XCTAssertTrue(oc.content is NSMutableDictionary)
        }
    }
}

// MARK: - User defaults controller

final class UserDefaultsControllerTests: XCTestCase, @unchecked Sendable {
    func testValuesProxyAppliesAndReverts() {
        MainActor.assumeIsolated {
            let suite = "AppKitCross.BindingsTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let c = NSUserDefaultsController(defaults: defaults, initialValues: ["size": 12])
            let field = NSTextField(frame: .zero)
            field.bind(NSBindingName.value, to: c, withKeyPath: "values.size")
            XCTAssertEqual(field.stringValue, "12", "the initial value until the defaults have one")
            field.stringValue = "14"
            field._fireAction()
            XCTAssertEqual(defaults.string(forKey: "size"), "14", "appliesImmediately")
            c.appliesImmediately = false
            field.stringValue = "16"
            field._fireAction()
            XCTAssertTrue(c.hasUnappliedChanges)
            XCTAssertEqual(defaults.string(forKey: "size"), "14")
            c.revert(nil)
            XCTAssertEqual(field.stringValue, "14")
            field.stringValue = "18"
            field._fireAction()
            c.save(nil)
            XCTAssertEqual(defaults.string(forKey: "size"), "18")
            XCTAssertFalse(c.hasUnappliedChanges)
            c.appliesImmediately = true
            c.revertToInitialValues(nil)
            XCTAssertEqual(defaults.integer(forKey: "size"), 12)
            XCTAssertEqual(field.stringValue, "12")
        }
    }
}

// MARK: - Bound views

final class BoundViewTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private func makeTable(_ ac: NSArrayController) -> (NSWindow, NSTableView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let table = NSTableView(frame: .zero)
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.width = 150
        table.addTableColumn(name)
        let age = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("age"))
        table.addTableColumn(age)
        name.bind(NSBindingName.value, to: ac, withKeyPath: "arrangedObjects.name")
        age.bind(NSBindingName.value, to: ac, withKeyPath: "arrangedObjects.age")
        scroll.documentView = table
        window.contentView!.addSubview(scroll)
        window.makeKeyAndOrderFront(nil)
        scroll.layoutSubtreeIfNeeded()
        return (window, table)
    }

    @MainActor
    private func cellText(_ table: NSTableView, _ row: Int, _ column: Int = 0) -> String? {
        (table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue
    }

    func testTableReflectsAddsAndRemoves() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            let (window, table) = makeTable(ac)
            _ = window
            XCTAssertEqual(table.numberOfRows, 4)
            XCTAssertEqual(cellText(table, 0), "Cleo")
            XCTAssertEqual(cellText(table, 1, 1), "29")
            XCTAssertNotNil(table.infoForBinding(NSBindingName.content), "a column bound to arrangedObjects binds the table")
            ac.addObject(BindingPerson("Eve", 30))
            XCTAssertEqual(table.numberOfRows, 5)
            XCTAssertEqual(cellText(table, 4), "Eve")
            XCTAssertEqual(table.selectedRowIndexes, [4], "the inserted object is selected in the table too")
            ac.remove(atArrangedObjectIndexes: [0, 1])
            XCTAssertEqual(table.numberOfRows, 3)
            XCTAssertEqual(cellText(table, 0), "Dana")
            ac.sortDescriptors = [byName]
            XCTAssertEqual((0..<3).compactMap { cellText(table, $0) }, ["Bea", "Dana", "Eve"])
            XCTAssertEqual(table.sortDescriptors.count, 1, "the table shows the controller's sort descriptors")
            rename((ac.arrangedObjects as! [BindingPerson])[0], "Bianca")
            XCTAssertEqual(cellText(table, 0), "Bianca", "a model change reloads the bound column")
        }
    }

    func testHeaderSortRedrawsEveryRow() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            let (window, table) = makeTable(ac)
            table.tableColumns[0].sortDescriptorPrototype = NSSortDescriptor(keyPath: \BindingPerson.name, ascending: true)
            table.tableColumns[1].sortDescriptorPrototype = NSSortDescriptor(keyPath: \BindingPerson.age, ascending: true)
            @MainActor func shown() -> [String] {
                window.display()
                var out: [(Int, String)] = []
                table.enumerateAvailableRowViews { rv, row in
                    let texts = rv._cellViews.map { ($0 as? NSTableCellView)?.textField?.stringValue ?? "?" }
                    out.append((row, texts.joined(separator: "/")))
                }
                return out.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            XCTAssertEqual(shown(), ["Cleo/41", "Abe/29", "Dana/35", "Bea/52"])
            table._headerClicked(column: 0)
            XCTAssertEqual(shown(), ["Abe/29", "Bea/52", "Cleo/41", "Dana/35"])
            table._headerClicked(column: 1)
            XCTAssertEqual(shown(), ["Abe/29", "Dana/35", "Cleo/41", "Bea/52"])
            table._headerClicked(column: 1)
            XCTAssertEqual(shown(), ["Bea/52", "Cleo/41", "Dana/35", "Abe/29"])
            XCTAssertEqual(names(ac.selectedObjects), ["Cleo"], "the selection follows the object")
            XCTAssertEqual(table.selectedRowIndexes, [1])
            // Six rows, a multiple selection and repeated toggles: every visible row redraws.
            ac.add(contentsOf: [BindingPerson("Eve", 72), BindingPerson("Fay", 18)])
            table.selectRowIndexes([0, 2], byExtendingSelection: false)
            for i in 0..<12 {
                table._headerClicked(column: i % 3 == 0 ? 0 : 1)
                let expected = (ac.arrangedObjects as! [BindingPerson]).map { "\($0.name)/\($0.age)" }
                XCTAssertEqual(shown(), expected, "after click \(i)")
            }
        }
    }

    func testSortAfterAddRemoveAndPickKeepsEveryRow() {
        MainActor.assumeIsolated {
            let ps = [BindingPerson("Ada", 36), BindingPerson("Grace", 45), BindingPerson("Alan", 41),
                      BindingPerson("Edsger", 72), BindingPerson("Barbara", 29), BindingPerson("Ken", 58)]
            let ac = NSArrayController(content: ps)
            let (window, table) = makeTable(ac)
            table.allowsMultipleSelection = true
            table.tableColumns[0].sortDescriptorPrototype = NSSortDescriptor(keyPath: \BindingPerson.name, ascending: true)
            table.tableColumns[1].sortDescriptorPrototype = NSSortDescriptor(keyPath: \BindingPerson.age, ascending: true)
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24), pullsDown: false)
            popup.bind(NSBindingName.content, to: ac, withKeyPath: "arrangedObjects")
            popup.bind(NSBindingName.contentValues, to: ac, withKeyPath: "arrangedObjects.name")
            popup.bind(NSBindingName.selectedIndex, to: ac, withKeyPath: "selectionIndex")
            window.contentView!.addSubview(popup)
            @MainActor func check(_ label: String) {
                window.display()
                let expected = (ac.arrangedObjects as! [BindingPerson]).map { "\($0.name)/\($0.age)" }
                XCTAssertEqual(table.numberOfRows, expected.count, label)
                for row in 0..<expected.count {
                    let rv = table.rowView(atRow: row, makeIfNecessary: false)
                    XCTAssertNotNil(rv, "\(label): row \(row) has a row view")
                    XCTAssertTrue(rv?.superview === table, "\(label): row \(row) is in the table")
                    XCTAssertEqual(rv?.frame.minY, table.rect(ofRow: row).minY, "\(label): row \(row) frame")
                    let texts = rv?._cellViews.map { ($0 as? NSTableCellView)?.textField?.stringValue ?? "?" }.joined(separator: "/")
                    XCTAssertEqual(texts, expected[row], "\(label): row \(row)")
                }
                XCTAssertEqual(table.subviews.compactMap { $0 as? NSTableRowView }.count, expected.count, "\(label): no stray row views")
            }
            check("start")
            ac.addObject(BindingPerson("New person 1", 21))
            check("after add")
            ac.remove(atArrangedObjectIndexes: ac.selectionIndexes)
            check("after remove")
            XCTAssertEqual(names(ac.selectedObjects), ["Ken"])
            popup.selectItem(at: 2)
            popup._fireAction()
            check("after pick")
            table._headerClicked(column: 0)
            check("name sort")
            table._headerClicked(column: 1)
            check("age sort")
            table.selectRowIndexes([1, 3], byExtendingSelection: false)
            table._headerClicked(column: 1)
            check("age sort reversed")
        }
    }

    func testReloadDuringRowCreationLeavesEveryRowDrawn() {
        MainActor.assumeIsolated {
            /// Reading its name removes the first row from the controller once: a model change
            /// that lands while the table is making its row views (a main-queue block run mid-paint).
            final class Tripwire: NSObject, NSKeyValueBindingCoding {
                let name: String
                var onRead: (() -> Void)?
                init(_ name: String) { self.name = name }
                func bindingValue(forKey key: String) -> Any? {
                    if key == "name", let f = onRead { onRead = nil; f() }
                    return key == "name" ? name : nil
                }
            }
            let items = (0..<6).map { Tripwire("Item \($0)") }
            let ac = NSArrayController(content: items)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
            let table = NSTableView(frame: .zero)
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
            column.width = 200
            table.addTableColumn(column)
            column.bind(NSBindingName.value, to: ac, withKeyPath: "arrangedObjects.name")
            scroll.documentView = table
            window.contentView!.addSubview(scroll)
            window.makeKeyAndOrderFront(nil)
            window.display()
            items[3].onRead = { ac.remove(atArrangedObjectIndex: 0) }
            table.reloadData()
            window.display()
            window.display()
            let expected = (ac.arrangedObjects as! [Tripwire]).map(\.name)
            XCTAssertEqual(expected.count, 5)
            for row in 0..<5 {
                let rv = table.rowView(atRow: row, makeIfNecessary: false)
                XCTAssertTrue(rv?.superview === table, "row \(row) has a row view in the table")
                XCTAssertEqual((rv?._cellViews.first as? NSTableCellView)?.textField?.stringValue, expected[row], "row \(row)")
            }
            XCTAssertEqual(table.subviews.compactMap { $0 as? NSTableRowView }.count, 5, "no stray row views")
        }
    }

    func testSelectionFollowsBothWays() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            let (window, table) = makeTable(ac)
            _ = window
            XCTAssertEqual(table.selectedRowIndexes, [0])
            _ = ac.setSelectionIndex(2)
            XCTAssertEqual(table.selectedRow, 2)
            table.selectRowIndexes([1, 3], byExtendingSelection: false)
            XCTAssertEqual(ac.selectionIndexes, table.allowsMultipleSelection ? [1, 3] : [3])
            table.sortDescriptors = [byAgeDescending]
            XCTAssertEqual(ac.sortDescriptors.count, 1, "the table's sort descriptors go to the controller")
            XCTAssertEqual(cellText(table, 0), "Bea")
        }
    }

    func testTextFieldBoundToSelection() {
        MainActor.assumeIsolated {
            let ps = people()
            let ac = NSArrayController(content: ps)
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
            field.bind(NSBindingName.value, to: ac, withKeyPath: "selection.name")
            XCTAssertEqual(field.stringValue, "Cleo")
            _ = ac.setSelectionIndex(1)
            XCTAssertEqual(field.stringValue, "Abe")
            rename(ps[1], "Abraham")
            XCTAssertEqual(field.stringValue, "Abraham", "the field follows the selected object")
            _ = ac.setSelectionIndexes([0, 1])
            XCTAssertEqual(field.stringValue, "")
            XCTAssertEqual(field.placeholderString, "Multiple Values")
            XCTAssertTrue(field.isEditable)
            _ = ac.setSelectionIndexes([])
            XCTAssertEqual(field.placeholderString, "No Selection")
            XCTAssertFalse(field.isEditable, "conditionallySetsEditable")
            _ = ac.setSelectionIndex(2)
            XCTAssertTrue(field.isEditable)
            XCTAssertNil(field.placeholderString)
            field.stringValue = "Daniela"
            field._fireAction()
            XCTAssertEqual(ps[2].name, "Daniela", "the edited value goes back to the selected object")
            field.unbind(NSBindingName.value)
            _ = ac.setSelectionIndex(0)
            XCTAssertEqual(field.stringValue, "Daniela")
        }
    }

    func testMultipleAndEmptySelectionAreSafeForEveryBoundView() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24), pullsDown: false)
            popup.bind(NSBindingName.content, to: ac, withKeyPath: "arrangedObjects")
            popup.bind(NSBindingName.contentValues, to: ac, withKeyPath: "arrangedObjects.name")
            popup.bind(NSBindingName.selectedIndex, to: ac, withKeyPath: "selectionIndex")
            let valuePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24), pullsDown: false)
            valuePopup.bind(NSBindingName.contentValues, to: ac, withKeyPath: "arrangedObjects.name")
            valuePopup.bind(NSBindingName.selectedValue, to: ac, withKeyPath: "selection.name")
            let tagPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24), pullsDown: false)
            tagPopup.bind(NSBindingName.selectedTag, to: ac, withKeyPath: "selection.age")
            let field = NSTextField(frame: .zero)
            field.bind(NSBindingName.value, to: ac, withKeyPath: "selection.age")
            let box = NSButton(checkboxWithTitle: "Member", target: nil, action: nil)
            box.bind(NSBindingName.value, to: ac, withKeyPath: "selection.isMember")
            _ = ac.setSelectionIndexes([1, 2])
            XCTAssertEqual(popup.indexOfSelectedItem, 1, "selectionIndex is the first selected index")
            XCTAssertEqual(field.placeholderString, "Multiple Values")
            _ = ac.setSelectionIndexes([2])
            XCTAssertEqual(popup.indexOfSelectedItem, 2)
            XCTAssertEqual(field.stringValue, "35")
            _ = ac.setSelectionIndexes([])
            XCTAssertNotEqual(popup.indexOfSelectedItem, 2, "NSNotFound does not keep the old index")
            XCTAssertFalse(valuePopup.isEnabled, "no selection disables a pop-up bound to the selection")
            XCTAssertEqual(field.placeholderString, "No Selection")
            XCTAssertFalse(box.isEnabled)
            XCTAssertEqual(box.state, .off)
            _ = ac.setSelectionIndexes([0, 3])
            _ = ac.setSelectionIndexes([3])
            XCTAssertEqual(popup.titleOfSelectedItem, "Bea")
            XCTAssertTrue(box.isEnabled)
            XCTAssertTrue(valuePopup.isEnabled)
            XCTAssertEqual(valuePopup.titleOfSelectedItem, "Bea")
        }
    }

    func testTextFieldPlaceholderOptions() {
        MainActor.assumeIsolated {
            let ac = NSArrayController()
            let field = NSTextField(frame: .zero)
            field.bind(NSBindingName.value, to: ac, withKeyPath: "selection.name", options: [NSBindingOption.noSelectionPlaceholder: "Pick someone"])
            XCTAssertEqual(field.placeholderString, "Pick someone")
        }
    }

    func testPopUpBoundToContentAndSelection() {
        MainActor.assumeIsolated {
            let ac = NSArrayController(content: people())
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24), pullsDown: false)
            popup.bind(NSBindingName.content, to: ac, withKeyPath: "arrangedObjects")
            popup.bind(NSBindingName.contentValues, to: ac, withKeyPath: "arrangedObjects.name")
            popup.bind(NSBindingName.selectedIndex, to: ac, withKeyPath: "selectionIndex")
            XCTAssertEqual(popup.itemTitles, ["Cleo", "Abe", "Dana", "Bea"])
            XCTAssertEqual(popup.indexOfSelectedItem, 0)
            _ = ac.setSelectionIndex(3)
            XCTAssertEqual(popup.titleOfSelectedItem, "Bea")
            popup.selectItem(at: 1)
            popup._fireAction()
            XCTAssertEqual(ac.selectionIndex, 1, "choosing an item writes selectedIndex back")
            ac.addObject(BindingPerson("Eve", 30))
            XCTAssertEqual(popup.itemTitles.last, "Eve")
            XCTAssertEqual(popup.titleOfSelectedItem, "Eve")
            XCTAssertTrue(popup.selectedItem?.representedObject as? BindingPerson === (ac.arrangedObjects as! [BindingPerson]).last)
        }
    }

    func testCheckboxAndEnabledBindings() {
        MainActor.assumeIsolated {
            let ps = people()
            let ac = NSArrayController(content: ps)
            let box = NSButton(checkboxWithTitle: "Member", target: nil, action: nil)
            box.bind(NSBindingName.value, to: ac, withKeyPath: "selection.isMember")
            let remove = NSButton(title: "Remove", target: nil, action: nil)
            remove.bind(NSBindingName.enabled, to: ac, withKeyPath: "canRemove")
            XCTAssertEqual(box.state, .off)
            box.state = .on
            box._fireAction()
            XCTAssertTrue(ps[0].isMember)
            XCTAssertTrue(remove.isEnabled)
            _ = ac.setSelectionIndexes([])
            XCTAssertFalse(remove.isEnabled)
            XCTAssertFalse(box.isEnabled, "no selection disables a bound control")
        }
    }
}

// MARK: - Tree controller

#if canImport(ObjectiveC)
final class TreeItem: NSObject {
    @objc dynamic var name: String
    @objc dynamic var children: [TreeItem]
    @objc dynamic var leaf: Bool = false
    @objc dynamic var count: Int = 0
    init(_ name: String, _ children: [TreeItem] = []) { self.name = name; self.children = children }
}
#else
final class TreeItem: NSObject, NSKeyValueBindingCoding {
    var name: String
    var children: [TreeItem]
    var leaf: Bool = false
    var count: Int = 0
    init(_ name: String, _ children: [TreeItem] = []) { self.name = name; self.children = children }
    func bindingValue(forKey key: String) -> Any? {
        switch key {
        case "name": return name
        case "children": return children
        case "leaf": return leaf
        case "count": return count
        default: return nil
        }
    }
    func setBindingValue(_ value: Any?, forKey key: String) {
        switch key {
        case "name": name = (value as? String) ?? ""
        case "children": children = ((value as? [Any]) ?? []).compactMap { $0 as? TreeItem }
        default: break
        }
    }
}
#endif

final class TreeControllerTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private func node(_ name: String, _ children: [TreeItem] = []) -> TreeItem { TreeItem(name, children) }
    @MainActor
    private func name(_ n: NSTreeNode?) -> String? { (n?.representedObject as? TreeItem)?.name }

    func testIndexPathsAndSelection() {
        MainActor.assumeIsolated {
            let tc = NSTreeController()
            tc.childrenKeyPath = "children"
            tc.content = [node("Fruit", [node("Apple"), node("Pear")]), node("Veg", [node("Kale", [node("Curly")])])]
            let root = tc.arrangedObjects
            XCTAssertEqual(root.children?.count, 2)
            XCTAssertEqual(root.indexPath, IndexPath())
            XCTAssertEqual(name(root.descendant(at: [0, 1])), "Pear")
            XCTAssertEqual(name(root.descendant(at: [1, 0, 0])), "Curly")
            XCTAssertNil(root.descendant(at: [0, 2]))
            XCTAssertEqual(root.descendant(at: [1, 0, 0])?.indexPath, [1, 0, 0])
            XCTAssertTrue(root.descendant(at: [0, 0])?.isLeaf ?? false)
            XCTAssertFalse(root.descendant(at: [1])?.isLeaf ?? true)
            XCTAssertEqual(name(root.descendant(at: [1, 0, 0])?.parent?.parent), "Veg")

            XCTAssertEqual(tc.selectionIndexPaths, [[0]], "avoidsEmptySelection")
            XCTAssertTrue(tc.setSelectionIndexPaths([[1, 0], [0, 1], [5]]))
            XCTAssertEqual(tc.selectionIndexPaths, [[0, 1], [1, 0]], "sorted, missing paths dropped")
            XCTAssertEqual(tc.selectedObjects.compactMap { ($0 as? TreeItem)?.name }, ["Pear", "Kale"])
            XCTAssertEqual(tc.selectedNodes.map { $0.indexPath }, [[0, 1], [1, 0]])
            XCTAssertEqual(tc.selectionIndexPath, [0, 1])
            XCTAssertTrue(tc.removeSelectionIndexPaths([[0, 1]]))
            XCTAssertEqual(tc.selectionIndexPaths, [[1, 0]])
            XCTAssertEqual(_KVC.value(tc, forKeyPath: "selection.name") as? String, "Kale")
            tc.sortDescriptors = [NSSortDescriptor(keyPath: \TreeItem.name, ascending: false)]
            XCTAssertEqual(name(tc.arrangedObjects.descendant(at: [0])), "Veg")
            XCTAssertEqual(name(tc.arrangedObjects.descendant(at: [1, 0])), "Pear")
            XCTAssertEqual(tc.selectionIndexPaths, [[0, 0]], "preservesSelection follows Kale")
        }
    }

    func testInsertRemoveAndMoveEditTheModel() {
        MainActor.assumeIsolated {
            let fruit = node("Fruit", [node("Apple")])
            let veg = node("Veg")
            let tc = NSTreeController(content: [fruit, veg])
            tc.childrenKeyPath = "children"
            tc.insert(node("Fig"), atArrangedObjectIndexPath: [0, 0])
            XCTAssertEqual(fruit.children.map(\.name), ["Fig", "Apple"])
            XCTAssertEqual(tc.selectionIndexPaths, [[0, 0]], "selectsInsertedObjects")
            tc.insert(node("Grain"), atArrangedObjectIndexPath: [2])
            XCTAssertEqual((tc.content as? [Any])?.compactMap { ($0 as? TreeItem)?.name }, ["Fruit", "Veg", "Grain"])
            tc.move(tc.arrangedObjects.descendant(at: [0, 1])!, to: [1, 0])
            XCTAssertEqual(veg.children.map(\.name), ["Apple"])
            XCTAssertEqual(fruit.children.map(\.name), ["Fig"])
            XCTAssertEqual(name(tc.arrangedObjects.descendant(at: [1, 0])), "Apple")
            tc.removeObject(atArrangedObjectIndexPath: [0])
            XCTAssertEqual(tc.arrangedObjects.children?.count, 2)
            XCTAssertEqual(name(tc.arrangedObjects.descendant(at: [0, 0])), "Apple")
            XCTAssertTrue(tc.canInsert)
            _ = tc.setSelectionIndexPath([0])
            XCTAssertTrue(tc.canAddChild)
            // A model change announced on a node rebuilds the tree.
            #if canImport(ObjectiveC)
            veg.children.append(node("Leek"))
            #else
            veg.children.append(node("Leek"))
            veg.didChangeValue(forKey: "children")
            #endif
            XCTAssertEqual(name(tc.arrangedObjects.descendant(at: [0, 1])), "Leek")
        }
    }

    func testLeafAndCountKeyPaths() {
        MainActor.assumeIsolated {
            let a = node("A"); a.leaf = true
            let b = node("B"); b.count = 0
            let c = node("C"); c.count = 2
            let tc = NSTreeController(content: [a, b, c])
            tc.childrenKeyPath = "children"
            tc.leafKeyPath = "leaf"
            XCTAssertTrue(tc.arrangedObjects.descendant(at: [0])!.isLeaf)
            XCTAssertFalse(tc.arrangedObjects.descendant(at: [1])!.isLeaf)
            tc.leafKeyPath = nil
            tc.countKeyPath = "count"
            XCTAssertTrue(tc.arrangedObjects.descendant(at: [1])!.isLeaf)
            XCTAssertFalse(tc.arrangedObjects.descendant(at: [2])!.isLeaf)
            XCTAssertEqual(tc.countKeyPath(for: tc.arrangedObjects), "count")
        }
    }

    func testTreeNodeMutableChildren() {
        MainActor.assumeIsolated {
            let root = NSTreeNode(representedObject: "root")
            let a = NSTreeNode(representedObject: "a"), b = NSTreeNode(representedObject: "b")
            root.mutableChildren.add(a)
            root.mutableChildren.insert(b, at: 0)
            XCTAssertEqual(root.children?.compactMap { $0.representedObject as? String }, ["b", "a"])
            XCTAssertTrue(a.parent === root)
            XCTAssertEqual(a.indexPath, [1])
            XCTAssertEqual(root.mutableChildren.count, 2)
            root.mutableChildren.removeObject(at: 0)
            XCTAssertNil(b.parent)
            XCTAssertEqual(a.indexPath, [0])
            XCTAssertFalse(root.isLeaf)
            XCTAssertTrue(a.isLeaf)
        }
    }
}

// MARK: - Rule editor

/// A criterion: what it shows and the predicate parts it contributes.
private final class Criterion: NSObject {
    let title: String
    let parts: [NSRuleEditor.PredicatePartKey: Any]
    let children: [Criterion]
    let isField: Bool
    let numeric: Bool
    init(_ title: String, _ parts: [NSRuleEditor.PredicatePartKey: Any] = [:], field: Bool = false, numeric: Bool = false, _ children: [Criterion] = []) {
        self.title = title; self.parts = parts; self.isField = field; self.numeric = numeric; self.children = children
    }
}

@MainActor
private final class PeopleRules: NSObject, NSRuleEditorDelegate {
    static func op(_ o: NSComparisonPredicate.Operator) -> [NSRuleEditor.PredicatePartKey: Any] { [.operatorType: NSNumber(value: o.rawValue)] }
    let simple: [Criterion] = [
        Criterion("name", [.leftExpression: "name"], [
            Criterion("begins with", op(.beginsWith), [Criterion("text", field: true)]),
            Criterion("is", op(.equalTo), [Criterion("text", field: true)]),
        ]),
        Criterion("age", [.leftExpression: "age"], [
            Criterion("is greater than", op(.greaterThan), [Criterion("number", field: true, numeric: true)]),
            Criterion("is less than", op(.lessThan), [Criterion("number", field: true, numeric: true)]),
        ]),
    ]
    let compound: [Criterion] = [
        Criterion("All", [.compoundType: NSNumber(value: NSCompoundPredicate.LogicalType.and.rawValue)], [Criterion("of the following are true")]),
        Criterion("Any", [.compoundType: NSNumber(value: NSCompoundPredicate.LogicalType.or.rawValue)], [Criterion("of the following are true")]),
    ]
    var changes = 0

    private func kids(_ c: Any?, _ type: NSRuleEditor.RowType) -> [Criterion] {
        if let c = c as? Criterion { return c.children }
        return type == .compound ? compound : simple
    }
    func ruleEditor(_ editor: NSRuleEditor, numberOfChildrenForCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Int { kids(criterion, rowType).count }
    func ruleEditor(_ editor: NSRuleEditor, child index: Int, forCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Any { kids(criterion, rowType)[index] }
    func ruleEditor(_ editor: NSRuleEditor, displayValueForCriterion criterion: Any, inRow row: Int) -> Any {
        let c = criterion as! Criterion
        if c.isField { return NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 22)) }
        return c.title
    }
    func ruleEditor(_ editor: NSRuleEditor, predicatePartsForCriterion criterion: Any, withDisplayValue value: Any, inRow row: Int) -> [NSRuleEditor.PredicatePartKey: Any]? {
        let c = criterion as! Criterion
        if c.isField, let f = value as? NSTextField {
            return [.rightExpression: c.numeric ? (Int(f.stringValue) ?? 0) as Any : f.stringValue as Any]
        }
        return c.parts
    }
    func ruleEditorRowsDidChange(_ notification: Notification) { changes += 1 }
}

final class RuleEditorTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private func editor(_ mode: NSRuleEditor.NestingMode, _ rules: PeopleRules) -> NSRuleEditor {
        let e = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
        e.nestingMode = mode
        e.delegate = rules
        return e
    }

    @MainActor
    private func field(_ e: NSRuleEditor, row: Int) -> NSTextField { e.displayValues(forRow: row).last as! NSTextField }

    @MainActor
    private func popUps(_ e: NSRuleEditor, row: Int) -> [NSPopUpButton] {
        let rowViews = e.subviews.compactMap { $0 as? _NSRuleEditorRowView }
        return rowViews[row].subviews.compactMap { $0 as? NSPopUpButton }
    }

    func testTwoRowListIsAnAND() {
        MainActor.assumeIsolated {
            let rules = PeopleRules()
            let e = editor(.list, rules)
            e.addRow(nil)
            e.addRow(nil)
            XCTAssertEqual(e.numberOfRows, 2)
            XCTAssertEqual((e.criteria(forRow: 1) as! [Criterion]).map(\.title), ["name", "begins with", "text"])
            XCTAssertEqual(e.displayValues(forRow: 1).prefix(2).compactMap { $0 as? String }, ["name", "begins with"])
            // Pick "age" in the second row's first pop-up, as a click would.
            let first = popUps(e, row: 1)[0]
            XCTAssertEqual(first.itemTitles, ["name", "age"])
            first.selectItem(at: 1)
            first._fireAction()
            XCTAssertEqual((e.criteria(forRow: 1) as! [Criterion]).map(\.title), ["age", "is greater than", "number"])
            XCTAssertEqual(popUps(e, row: 1)[1].itemTitles, ["is greater than", "is less than"])
            field(e, row: 0).stringValue = "A"
            field(e, row: 1).stringValue = "30"
            let p = e.predicate
            XCTAssertEqual(p?.predicateFormat, "name BEGINSWITH \"A\" AND age > 30")
            XCTAssertEqual(e.predicate(forRow: 1)?.predicateFormat, "age > 30")
            let all = [BindingPerson("Ada", 31), BindingPerson("Al", 20), BindingPerson("Bo", 40)]
            XCTAssertEqual(all.filter { p!.evaluate(with: $0) }.map(\.name), ["Ada"])
            XCTAssertGreaterThanOrEqual(rules.changes, 3)
        }
    }

    func testCompoundNesting() {
        MainActor.assumeIsolated {
            let rules = PeopleRules()
            let e = editor(.compound, rules)
            e.addRow(nil)
            XCTAssertEqual(e.numberOfRows, 2, "a compound row with one simple subrow")
            XCTAssertEqual(e.rowType(forRow: 0), .compound)
            XCTAssertEqual(e.rowType(forRow: 1), .simple)
            XCTAssertEqual(e.parentRow(forRow: 1), 0)
            e.addRow(nil)
            XCTAssertEqual(e.subrowIndexes(forRow: 0), [1, 2])
            field(e, row: 1).stringValue = "B"
            field(e, row: 2).stringValue = "Cleo"
            let rowPopUps = popUps(e, row: 2)
            rowPopUps[1].selectItem(at: 1)            // "is"
            rowPopUps[1]._fireAction()
            field(e, row: 2).stringValue = "Cleo"     // a new field came with the new criterion
            XCTAssertEqual(e.predicate?.predicateFormat, "name BEGINSWITH \"B\" AND name == \"Cleo\"")
            let any = popUps(e, row: 0)[0]
            any.selectItem(at: 1)
            any._fireAction()
            XCTAssertEqual(e.predicate?.predicateFormat, "name BEGINSWITH \"B\" OR name == \"Cleo\"")
            XCTAssertEqual(people().filter { e.predicate!.evaluate(with: $0) }.map(\.name), ["Cleo", "Bea"])
            // A nested compound row.
            e.insertRow(at: 3, with: .compound, asSubrowOfRow: 0, animate: false)
            e.insertRow(at: 4, with: .simple, asSubrowOfRow: 3, animate: false)
            field(e, row: 4).stringValue = "D"
            XCTAssertEqual(e.parentRow(forRow: 4), 3)
            XCTAssertEqual(e.predicate?.predicateFormat, "name BEGINSWITH \"B\" OR name == \"Cleo\" OR (name BEGINSWITH \"D\")")
            // Removing the nested compound row hands its subrow to the root row.
            e.removeRow(at: 3)
            XCTAssertEqual(e.numberOfRows, 4)
            XCTAssertEqual(e.parentRow(forRow: 3), 0)
            e.removeRows(at: [0], includeSubrows: true)
            XCTAssertEqual(e.numberOfRows, 0)
            XCTAssertNil(e.predicate)
        }
    }

    func testPlusAndMinusButtonsEditRows() {
        MainActor.assumeIsolated {
            let rules = PeopleRules()
            let e = editor(.compound, rules)
            e.addRow(nil)
            @MainActor func button(_ row: Int, _ title: String) -> NSButton {
                let rowViews = e.subviews.compactMap { $0 as? _NSRuleEditorRowView }
                return rowViews[row].subviews.compactMap { $0 as? NSButton }.first { $0.title == title }!
            }
            button(1, "+")._fireAction()
            XCTAssertEqual(e.numberOfRows, 3, "+ on a simple row adds a sibling after it")
            XCTAssertEqual(e.parentRow(forRow: 2), 0)
            button(0, "+")._fireAction()
            XCTAssertEqual(e.numberOfRows, 4, "+ on a compound row adds a child at its end")
            XCTAssertEqual(e.subrowIndexes(forRow: 0), [1, 2, 3])
            button(2, "\u{2212}")._fireAction()
            XCTAssertEqual(e.numberOfRows, 3)
            e.canRemoveAllRows = false
            XCTAssertFalse(button(0, "\u{2212}").isEnabled, "the root row holds every row")
            XCTAssertTrue(button(1, "\u{2212}").isEnabled)
            e.isEditable = false
            XCTAssertTrue(e.subviews.compactMap { $0 as? _NSRuleEditorRowView }.allSatisfy { $0.subviews.allSatisfy { !($0 is NSButton) || $0 is NSPopUpButton } })
        }
    }

    func testTypingInARowFieldUpdatesThePredicateAndSendsTheAction() {
        MainActor.assumeIsolated {
            final class Sink: NSObject, NSSelectorHandling {
                var formats: [String] = []
                weak var editor: NSRuleEditor?
                @MainActor func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
                    formats.append(editor?.predicate?.predicateFormat ?? "nil")
                    return true
                }
            }
            let rules = PeopleRules()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let e = editor(.list, rules)
            window.contentView!.addSubview(e)
            window.makeKeyAndOrderFront(nil)
            let sink = Sink()
            sink.editor = e
            e.target = sink
            e.action = Selector(("rulesChanged:"))
            XCTAssertTrue(e.target === sink, "the rule editor keeps its target")
            XCTAssertEqual(e.action, Selector(("rulesChanged:")))
            e.addRow(nil)
            let first = popUps(e, row: 0)[0]
            first.selectItem(at: 1)                    // age
            first._fireAction()
            let f = field(e, row: 0)
            XCTAssertTrue(window.makeFirstResponder(f))
            let editorView = f._fieldEditor!
            editorView.insertText("4", replacementRange: NSRange(location: NSNotFound, length: 0))
            editorView.insertText("0", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(e.predicate?.predicateFormat, "age > 40", "the live field value, while editing")
            XCTAssertEqual(sink.formats.suffix(2), ["age > 4", "age > 40"], "each keystroke sends the action")
            XCTAssertTrue(sink.formats.contains("age > 0"), "picking a criterion sends the action")
        }
    }

    func testRowQueriesAndSelection() {
        MainActor.assumeIsolated {
            let rules = PeopleRules()
            let e = editor(.list, rules)
            e.addRow(nil)
            e.addRow(nil)
            let f = field(e, row: 1)
            XCTAssertEqual(e.row(forDisplayValue: f), 1)
            XCTAssertEqual(e.row(forDisplayValue: "nothing"), -1)
            e.selectRowIndexes([1], byExtendingSelection: false)
            e.selectRowIndexes([0], byExtendingSelection: true)
            XCTAssertEqual(e.selectedRowIndexes, [0, 1])
            let notes = expectation(forNotification: NSRuleEditor.rowsDidChangeNotification, object: e)
            e.removeRow(at: 0)
            wait(for: [notes], timeout: 1)
            XCTAssertEqual(e.selectedRowIndexes, [0])
            e.setCriteria(Array(rules.simple[1].children[1].children.prefix(0)), andDisplayValues: [], forRowAt: 0)
            XCTAssertEqual(e.criteria(forRow: 0).count, 0)
            XCTAssertNil(e.predicate(forRow: 0), "a row without parts has no predicate")
            e.reloadCriteria()
            XCTAssertEqual((e.criteria(forRow: 0) as! [Criterion]).map(\.title), ["name", "begins with", "text"])
            XCTAssertEqual(e.intrinsicContentSize.height, e.rowHeight)
        }
    }

    #if canImport(ObjectiveC)
    func testExpressionPartsMakeFoundationPredicates() {
        MainActor.assumeIsolated {
            final class ExpressionRules: NSObject, NSRuleEditorDelegate {
                func ruleEditor(_ editor: NSRuleEditor, numberOfChildrenForCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Int { criterion == nil ? 1 : 0 }
                func ruleEditor(_ editor: NSRuleEditor, child index: Int, forCriterion criterion: Any?, with rowType: NSRuleEditor.RowType) -> Any { "age" }
                func ruleEditor(_ editor: NSRuleEditor, displayValueForCriterion criterion: Any, inRow row: Int) -> Any { "age is 41" }
                func ruleEditor(_ editor: NSRuleEditor, predicatePartsForCriterion criterion: Any, withDisplayValue value: Any, inRow row: Int) -> [NSRuleEditor.PredicatePartKey: Any]? {
                    [.leftExpression: NSExpression(forKeyPath: "age"), .rightExpression: NSExpression(forConstantValue: 41),
                     .operatorType: NSNumber(value: NSComparisonPredicate.Operator.equalTo.rawValue)]
                }
            }
            let rules = ExpressionRules()
            let e = NSRuleEditor(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
            e.nestingMode = .list
            e.delegate = rules
            e.addRow(nil)
            let p = e.predicate as? NSComparisonPredicate
            XCTAssertEqual(p?.predicateFormat, "age == 41")
            XCTAssertEqual(people().filter { p!.evaluate(with: $0) }.map(\.name), ["Cleo"])
        }
    }
    #endif
}
