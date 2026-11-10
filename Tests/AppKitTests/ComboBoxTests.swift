// NSComboBox on the host backend: items and selection, a data source, completion while
// typing, the pop-up list opened and driven with synthesized events, notifications and
// the delegate, the keyboard, and accessibility.

import XCTest
@testable import AppKit

/// A log notification observers (Sendable closures) can append to.
private final class Log: @unchecked Sendable {
    var events: [String] = []
    func add(_ s: String) { events.append(s) }
}

@MainActor
private final class Sizes: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
    var items = ["Small", "Medium", "Large", "Extra large"]
    var lookups = 0
    let log: Log
    init(log: Log) { self.log = log }
    func numberOfItems(in comboBox: NSComboBox) -> Int { items.count }
    func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? { items[index] }
    func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int { lookups += 1; return items.firstIndex(of: string) ?? NSNotFound }
    func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? { items.first { $0.lowercased().hasPrefix(string.lowercased()) } }
    func comboBoxWillPopUp(_ notification: Notification) { log.add("delegate willPopUp") }
    func comboBoxWillDismiss(_ notification: Notification) { log.add("delegate willDismiss") }
    func comboBoxSelectionDidChange(_ notification: Notification) { log.add("delegate didChange \((notification.object as? NSComboBox)?.indexOfSelectedItem ?? -2)") }
    func comboBoxSelectionIsChanging(_ notification: Notification) { log.add("delegate isChanging \((notification.object as? NSComboBox)?.indexOfSelectedItem ?? -2)") }
}

@MainActor
private func makeWindow() -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 300, width: 320, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func makeCombo(in w: NSWindow, items: [String] = ["Apple", "Apricot", "Banana", "Blueberry", "Cherry", "Fig", "Grape"]) -> NSComboBox {
    let c = NSComboBox(frame: NSRect(x: 20, y: 100, width: 200, height: 24))
    c.addItems(withObjectValues: items)
    w.contentView!.addSubview(c)
    return c
}

@MainActor
private func click(_ w: NSWindow, _ p: NSPoint, flags: NSEvent.ModifierFlags = []) {
    for (type, pressure) in [(NSEvent.EventType.leftMouseDown, 1 as Float), (.leftMouseUp, 0)] {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure)!
        NSApplication.shared.sendEvent(e)
    }
}

/// A click at a screen point, as the platform delivers it (to the window under it, or
/// with no window when nothing of ours is there).
@MainActor
private func clickScreen(_ p: NSPoint) {
    let target = NSApplication.shared.windows.last { $0.isVisible && $0.frame.contains(p) }
    let local = target.map { $0.convertPoint(fromScreen: p) } ?? p
    for (type, pressure) in [(NSEvent.EventType.leftMouseDown, 1 as Float), (.leftMouseUp, 0)] {
        let e = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: 0, windowNumber: target?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure)!
        NSApplication.shared.sendEvent(e)
    }
}

@MainActor
private func key(_ w: NSWindow, _ chars: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    NSApplication.shared.sendEvent(e)
}

/// Screen point at the centre of row `row` of the open list.
@MainActor
private func listRowCenter(_ row: Int) -> NSPoint {
    let p = _NSComboBoxPopUp.current!
    let r = p.table.rect(ofRow: row)
    let inWindow = p.table.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
    return p.window.convertPoint(toScreen: inWindow)
}

final class ComboBoxTests: XCTestCase, @unchecked Sendable {
    func testItemsAndSelection() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let c = makeCombo(in: w, items: ["One", "Two", "Three"])
            XCTAssertEqual(c.numberOfItems, 3)
            XCTAssertEqual(c.objectValues as? [String], ["One", "Two", "Three"])
            XCTAssertEqual(c.indexOfSelectedItem, -1)
            XCTAssertNil(c.objectValueOfSelectedItem)
            c.insertItem(withObjectValue: "Zero", at: 0)
            c.addItem(withObjectValue: "Four")
            XCTAssertEqual(c.objectValues as? [String], ["Zero", "One", "Two", "Three", "Four"])
            XCTAssertEqual(c.indexOfItem(withObjectValue: "Three"), 3)
            XCTAssertEqual(c.indexOfItem(withObjectValue: "Nine"), NSNotFound)
            XCTAssertEqual(c.itemObjectValue(at: 2) as? String, "Two")
            let log = Log()
            let o = NotificationCenter.default.addObserver(forName: NSComboBox.selectionDidChangeNotification, object: c, queue: nil) { n in
                log.add("didChange")
            }
            c.selectItem(at: 2)
            XCTAssertEqual(c.indexOfSelectedItem, 2)
            XCTAssertEqual(c.objectValueOfSelectedItem as? String, "Two")
            XCTAssertEqual(c.stringValue, "Two", "selecting shows the item")
            XCTAssertEqual(log.events, ["didChange"])
            c.selectItem(withObjectValue: "Four")
            XCTAssertEqual(c.indexOfSelectedItem, 4)
            c.removeItem(at: 0)
            XCTAssertEqual(c.indexOfSelectedItem, 3, "the selection follows the item")
            c.removeItem(withObjectValue: "Three")
            XCTAssertEqual(c.objectValues as? [String], ["One", "Two", "Four"])
            XCTAssertEqual(c.indexOfSelectedItem, 2)
            c.deselectItem(at: 2)
            XCTAssertEqual(c.indexOfSelectedItem, -1)
            XCTAssertEqual(log.events.count, 3)
            c.selectItem(at: 9)
            XCTAssertEqual(c.indexOfSelectedItem, -1, "out of range is ignored")
            c.removeAllItems()
            XCTAssertEqual(c.numberOfItems, 0)
            NotificationCenter.default.removeObserver(o)
            // The cell carries the same list API.
            let cell = NSComboBoxCell(textCell: "")
            cell.addItems(withObjectValues: ["a", "b"])
            cell.selectItem(at: 1)
            XCTAssertEqual(cell.numberOfItems, 2)
            XCTAssertEqual(cell.indexOfSelectedItem, 1)
            XCTAssertEqual(cell.stringValue, "b")
            XCTAssertEqual(cell.completedString("B"), "b")
            w.close()
        }
    }

    func testDataSourceAndCompletionThroughIt() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let log = Log()
            let sizes = Sizes(log: log)
            let c = NSComboBox(frame: NSRect(x: 20, y: 100, width: 200, height: 24))
            c.usesDataSource = true
            c.dataSource = sizes
            c.delegate = sizes
            w.contentView!.addSubview(c)
            XCTAssertEqual(c.numberOfItems, 4)
            XCTAssertEqual(c.itemObjectValue(at: 1) as? String, "Medium")
            XCTAssertEqual(c.objectValues as? [String], sizes.items)
            XCTAssertEqual(c.indexOfItem(withObjectValue: "Large"), 2)
            XCTAssertEqual(c._comboCell._index(ofString: "Large"), 2)
            XCTAssertEqual(sizes.lookups, 1, "the data source's lookup is used")
            XCTAssertEqual(c._comboCell._completed("ex"), "Extra large")
            sizes.items.append("Huge")
            c.noteNumberOfItemsChanged()
            XCTAssertEqual(c.numberOfItems, 5)
            c.selectItem(at: 4)
            XCTAssertEqual(c.stringValue, "Huge")
            XCTAssertEqual(log.events, ["delegate didChange 4"])
            sizes.items.removeAll()
            c.reloadData()
            XCTAssertEqual(c.numberOfItems, 0)
            XCTAssertEqual(c.indexOfSelectedItem, -1)
            w.close()
        }
    }

    func testCompletionWhileTyping() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let c = makeCombo(in: w)
            c.completes = true
            click(w, NSPoint(x: 60, y: 112))
            XCTAssertNotNil(c.currentEditor)
            key(w, "a")
            XCTAssertEqual(c.stringValue, "Apple", "the first item with the typed prefix completes it")
            XCTAssertEqual(c.currentEditor?.selectedRange, NSRange(location: 1, length: 4), "the completed part is selected")
            key(w, "p")
            XCTAssertEqual(c.stringValue, "Apple")
            XCTAssertEqual(c.currentEditor?.selectedRange, NSRange(location: 2, length: 3))
            key(w, "r")
            XCTAssertEqual(c.stringValue, "Apricot")
            XCTAssertEqual(c.currentEditor?.selectedRange, NSRange(location: 3, length: 4))
            key(w, "\u{7F}")       // delete: removes the selected completion, no new completion
            XCTAssertEqual(c.stringValue, "Apr")
            key(w, "x")
            XCTAssertEqual(c.stringValue, "Aprx", "nothing matches: the text stays as typed")
            c.completes = false
            key(w, "a", flags: .command)
            key(w, "b")
            XCTAssertEqual(c.stringValue, "b", "no completion when it is off")
            XCTAssertEqual(c.indexOfSelectedItem, -1, "typing does not select an item")
            w.close()
        }
    }

    func testPopUpOpensSelectsWithTheMouseAndDismisses() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let log = Log()
            let sizes = Sizes(log: log)
            let c = makeCombo(in: w)
            c.delegate = sizes
            var actions = 0
            let target = NSObject()
            target.setActionHandler(for: Selector(("chosen:"))) { _ in actions += 1 }
            c.target = target
            c.action = Selector(("chosen:"))
            let observers = [NSComboBox.willPopUpNotification, NSComboBox.willDismissNotification, NSComboBox.selectionDidChangeNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: c, queue: nil) { _ in log.add(name.rawValue) }
            }
            // The button sits at the trailing edge of the field.
            let button = c._buttonRect
            XCTAssertEqual(button.maxX, c.bounds.maxX - 2, accuracy: 0.5)
            XCTAssertEqual(button.width, NSComboBoxCell.buttonWidth)
            XCTAssertFalse(c._isPopUpOpen)
            click(w, c.convert(NSPoint(x: button.midX, y: button.midY), to: nil))
            XCTAssertTrue(c._isPopUpOpen)
            XCTAssertNotNil(c.currentEditor, "clicking the button starts editing too")
            XCTAssertEqual(log.events, ["NSComboBoxWillPopUpNotification", "delegate willPopUp"])
            let popUp = _NSComboBoxPopUp.current!
            XCTAssertTrue(popUp.window.isVisible)
            XCTAssertFalse(popUp.window.canBecomeKey)
            XCTAssertTrue(w.isKeyWindow, "the field's window keeps the keyboard")
            XCTAssertEqual(popUp.table.numberOfRows, 7)
            XCTAssertEqual(popUp.table.tableColumns.count, 1)
            XCTAssertNil(popUp.table.headerView)
            // Placed under the field, as wide as it.
            let anchor = w.convertToScreen(c.convert(c.bounds, to: nil))
            XCTAssertEqual(popUp.window.frame.width, anchor.width, accuracy: 0.5)
            XCTAssertEqual(popUp.window.frame.maxY, anchor.minY, accuracy: 0.5)
            XCTAssertEqual(popUp.window.frame.minX, anchor.minX, accuracy: 0.5)
            let rowStep = c.itemHeight + c.intercellSpacing.height
            XCTAssertEqual(popUp.window.frame.height, 5 * rowStep - c.intercellSpacing.height + 4, accuracy: 0.5, "five visible rows")
            // Clicking a row chooses it: text, selection, notification, delegate, action.
            log.events.removeAll()
            clickScreen(listRowCenter(2))
            XCTAssertFalse(c._isPopUpOpen)
            XCTAssertFalse(popUp.window.isVisible)
            XCTAssertEqual(c.stringValue, "Banana")
            XCTAssertEqual(c.indexOfSelectedItem, 2)
            XCTAssertEqual(c.currentEditor?.string, "Banana", "the editor shows the chosen item")
            XCTAssertEqual(log.events, ["delegate isChanging 2", "NSComboBoxWillDismissNotification", "delegate willDismiss", "NSComboBoxSelectionDidChangeNotification", "delegate didChange 2"],
                           "the press highlights the row (changing), the release chooses it")
            XCTAssertEqual(actions, 1)
            // Open again: the chosen row is selected in the list; a click outside dismisses
            // without choosing and goes on to what is under it.
            click(w, c.convert(NSPoint(x: button.midX, y: button.midY), to: nil))
            XCTAssertTrue(c._isPopUpOpen)
            XCTAssertEqual(_NSComboBoxPopUp.current!.table.selectedRow, 2)
            log.events.removeAll()
            var outsideClicks = 0
            let catcher = NSButton(frame: NSRect(x: 240, y: 20, width: 70, height: 24))     // clear of the list, which hangs under the field
            catcher.setActionHandler(for: Selector(("hit:"))) { _ in outsideClicks += 1 }
            catcher.target = catcher
            catcher.action = Selector(("hit:"))
            w.contentView!.addSubview(catcher)
            XCTAssertFalse(_NSComboBoxPopUp.current!.window.frame.contains(w.convertPoint(toScreen: NSPoint(x: 275, y: 32))))
            click(w, NSPoint(x: 275, y: 32))
            XCTAssertFalse(c._isPopUpOpen)
            XCTAssertEqual(outsideClicks, 1, "the dismissing click reaches the control under it")
            XCTAssertEqual(c.indexOfSelectedItem, 2)
            XCTAssertEqual(log.events, ["NSComboBoxWillDismissNotification", "delegate willDismiss"])
            XCTAssertEqual(actions, 1)
            // The button toggles: a second click on it closes the list.
            click(w, c.convert(NSPoint(x: button.midX, y: button.midY), to: nil))
            XCTAssertTrue(c._isPopUpOpen)
            click(w, c.convert(NSPoint(x: button.midX, y: button.midY), to: nil))
            XCTAssertFalse(c._isPopUpOpen)
            // Losing key closes it.
            click(w, c.convert(NSPoint(x: button.midX, y: button.midY), to: nil))
            XCTAssertTrue(c._isPopUpOpen)
            let other = makeWindow()
            XCTAssertFalse(c._isPopUpOpen, "another window becoming key dismisses the list")
            other.close()
            for o in observers { NotificationCenter.default.removeObserver(o) }
            w.close()
        }
    }

    func testKeyboardDrivesTheList() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let log = Log()
            let sizes = Sizes(log: log)
            let c = makeCombo(in: w)
            c.delegate = sizes
            var actions = 0
            let target = NSObject()
            target.setActionHandler(for: Selector(("chosen:"))) { _ in actions += 1 }
            c.target = target
            c.action = Selector(("chosen:"))
            click(w, NSPoint(x: 60, y: 112))
            XCTAssertNotNil(c.currentEditor)
            key(w, "\u{F701}", code: 125)            // down opens the list
            XCTAssertTrue(c._isPopUpOpen)
            XCTAssertEqual(c.indexOfSelectedItem, -1)
            key(w, "\u{F701}", code: 125)            // down: first item, "changing"
            XCTAssertEqual(c.indexOfSelectedItem, 0)
            XCTAssertEqual(c.stringValue, "Apple", "arrowing shows the item in the field")
            key(w, "\u{F701}", code: 125)
            key(w, "\u{F701}", code: 125)
            XCTAssertEqual(c.indexOfSelectedItem, 2)
            key(w, "\u{F700}", code: 126)            // up
            XCTAssertEqual(c.indexOfSelectedItem, 1)
            XCTAssertEqual(log.events.filter { $0.hasPrefix("delegate isChanging") }, ["delegate isChanging 0", "delegate isChanging 1", "delegate isChanging 2", "delegate isChanging 1"])
            XCTAssertFalse(log.events.contains { $0.hasPrefix("delegate didChange") }, "nothing committed yet")
            XCTAssertEqual(actions, 0)
            key(w, "\r", code: 36)                   // return commits
            XCTAssertFalse(c._isPopUpOpen)
            XCTAssertEqual(c.indexOfSelectedItem, 1)
            XCTAssertEqual(c.stringValue, "Apricot")
            XCTAssertEqual(log.events.last, "delegate didChange 1")
            XCTAssertEqual(actions, 1)
            XCTAssertNotNil(c.currentEditor, "the field keeps editing")
            // A click on a row works after a keyboard-opened list too.
            key(w, "\u{F701}", code: 125)
            XCTAssertTrue(c._isPopUpOpen)
            clickScreen(listRowCenter(4))
            XCTAssertFalse(c._isPopUpOpen)
            XCTAssertEqual(c.stringValue, "Cherry")
            XCTAssertEqual(actions, 2)
            // Escape dismisses without choosing; typing goes on in the field while open.
            key(w, "\u{F701}", code: 125)
            key(w, "\u{F701}", code: 125)
            XCTAssertEqual(c.indexOfSelectedItem, 5)
            key(w, "\u{1B}", code: 53)
            XCTAssertFalse(c._isPopUpOpen)
            XCTAssertEqual(actions, 2)
            key(w, "\u{F701}", code: 125)
            key(w, "a", flags: .command)
            key(w, "z")
            XCTAssertTrue(c._isPopUpOpen, "typing leaves the list open")
            XCTAssertEqual(c.stringValue, "z", "and reaches the field")
            key(w, "\u{1B}", code: 53)
            w.close()
        }
    }

    func testAccessibility() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let c = makeCombo(in: w)
            c.selectItem(at: 1)
            XCTAssertEqual(c.accessibilityRole(), .comboBox)
            let value: Any? = c.accessibilityValue()
            XCTAssertEqual(value as? String, "Apricot")
            XCTAssertFalse(c.isAccessibilityExpanded())
            let element = c._accessibilityElement()
            XCTAssertEqual(element.role, "AXComboBox")
            XCTAssertEqual(element.isExpanded, false)
            XCTAssertTrue(element.actions.contains(.showMenu))
            XCTAssertTrue(element.actions.contains(.expand))
            XCTAssertTrue(w.accessibilityPerform(.showMenu, on: c._accessibilityElementID))
            XCTAssertTrue(c._isPopUpOpen)
            XCTAssertTrue(c.isAccessibilityExpanded())
            let list = _NSComboBoxPopUp.current!.table
            XCTAssertEqual(list.accessibilityRole(), .list)
            XCTAssertEqual(list.accessibilityRowCount(), 7)
            XCTAssertTrue(w.accessibilityPerform(.collapse, on: c._accessibilityElementID))
            XCTAssertFalse(c._isPopUpOpen)
            w.close()
        }
    }

    func testLayoutAndDrawing() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let c = makeCombo(in: w)
            XCTAssertGreaterThan(c.intrinsicContentSize.width, NSTextField(string: "").intrinsicContentSize.width + NSComboBoxCell.buttonWidth - 1)
            let text = c._comboCell._textRect(forBounds: c.bounds)
            XCTAssertLessThanOrEqual(text.maxX, c._buttonRect.minX, "the text keeps clear of the button")
            c.userInterfaceLayoutDirection = .rightToLeft
            XCTAssertEqual(c._buttonRect.minX, 2, accuracy: 0.5, "the button mirrors to the leading (right-to-left: left) edge")
            XCTAssertGreaterThanOrEqual(c._comboCell._textRect(forBounds: c.bounds).minX, c._buttonRect.maxX)
            c.userInterfaceLayoutDirection = .leftToRight
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            guard let image = platform.lastImage else { return XCTFail("no image") }
            let data = _pixels(image)
            func pixel(_ p: NSPoint) -> (r: UInt8, g: UInt8, b: UInt8) {   // content coordinates, points
                let x = Int(p.x * 2), row = image.height - 1 - Int(p.y * 2), i = row * image.bytesPerRow + x * 4
                return (data[i + 2], data[i + 1], data[i])
            }
            let button = c.convert(c._buttonRect, to: w.contentView)
            let fill = pixel(NSPoint(x: button.minX + 3, y: button.midY))
            XCTAssertGreaterThan(Int(fill.b), Int(fill.r) + 40, "the bordered button is filled with the (blue) accent colour, not the white field background")
            c.isButtonBordered = false
            w.display()
            guard let plain = platform.lastImage else { return XCTFail("no image") }
            let plainData = _pixels(plain)
            let x = Int((button.minX + 3) * 2), row = plain.height - 1 - Int(button.midY * 2), i = row * plain.bytesPerRow + x * 4
            XCTAssertGreaterThan(plainData[i], 200, "unbordered: the field background shows through")
            w.close()
        }
    }
}
