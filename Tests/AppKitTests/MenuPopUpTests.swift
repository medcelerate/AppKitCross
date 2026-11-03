// Menu pop-ups: tracking windows, keyboard navigation, submenus, NSPopUpButton.

import XCTest
@testable import AppKit

@MainActor
private func makeWindow() -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func menuWindows() -> [_NSMenuWindow] { NSApplication.shared.windows.compactMap { $0 as? _NSMenuWindow }.filter { $0.isVisible } }

@MainActor
private func send(_ type: NSEvent.EventType, screen point: NSPoint, in window: NSWindow? = nil) {
    let target = window ?? menuWindows().last { $0.frame.contains(point) }
    let location = target.map { $0.convertPoint(fromScreen: point) } ?? point
    let e = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: target?.windowNumber ?? 0,
                               context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    NSApplication.shared.sendEvent(e)
}

@MainActor
private func sendKey(_ code: UInt16, _ chars: String = "", window: NSWindow) {
    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    NSApplication.shared.sendEvent(e)
}

/// Screen point at the centre of row `row` of the deepest open menu.
@MainActor
private func rowCenter(_ row: Int, level: Int? = nil) -> NSPoint {
    let windows = menuWindows()
    let w = level.map { windows[$0] } ?? windows.last!
    let f = w.menuView.layout.rows[row].frame
    let inWindow = w.menuView.convert(NSPoint(x: f.midX, y: f.midY), to: nil)
    return w.convertPoint(toScreen: inWindow)
}

/// A counter that notification observers (Sendable closures) can bump.
private final class Counter: @unchecked Sendable { var n = 0 }

final class MenuPopUpTests: XCTestCase, @unchecked Sendable {
    @MainActor private final class Receiver: NSObject, NSSelectorHandling {
        var chosen: [String] = []
        static let pick = Selector(("pick:"))
        func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
            guard action == Receiver.pick else { return false }
            chosen.append((sender as? NSMenuItem)?.title ?? (sender as? NSPopUpButton)?.titleOfSelectedItem ?? "?")
            return true
        }
    }

    @MainActor private func sampleMenu(_ r: Receiver) -> NSMenu {
        let m = NSMenu(title: "Sample")
        m.addItem(withTitle: "Cut", action: Receiver.pick, keyEquivalent: "x").target = r
        m.addItem(withTitle: "Copy", action: Receiver.pick, keyEquivalent: "c").target = r
        m.addItem(.separator())
        let disabled = m.addItem(withTitle: "Unavailable", action: Receiver.pick, keyEquivalent: "")
        disabled.target = r
        disabled.isEnabled = false
        m.autoenablesItems = false
        let more = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "More")
        sub.addItem(withTitle: "Deep", action: Receiver.pick, keyEquivalent: "").target = r
        more.submenu = sub
        m.addItem(more)
        return m
    }

    func testContextMenuOpensTracksAndChoosesWithTheMouse() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let menu = sampleMenu(r)
            let began = Counter(), ended = Counter()
            let o1 = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: menu, queue: nil) { _ in began.n += 1 }
            let o2 = NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: menu, queue: nil) { _ in ended.n += 1 }
            defer { NotificationCenter.default.removeObserver(o1); NotificationCenter.default.removeObserver(o2) }
            let click = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 50, y: 150), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            XCTAssertTrue(_NSMenuTracker.isTracking)
            XCTAssertEqual(began.n, 1)
            let windows = menuWindows()
            XCTAssertEqual(windows.count, 1)
            let mw = windows[0]
            XCTAssertFalse(mw.isKeyWindow, "menu windows never take the keyboard")
            XCTAssertTrue(w.isKeyWindow)
            // The top-left corner sits at the click point (screen coordinates).
            let clickScreen = w.convertPoint(toScreen: NSPoint(x: 50, y: 150))
            XCTAssertEqual(mw.frame.minX, clickScreen.x, accuracy: 0.5)
            XCTAssertEqual(mw.frame.maxY, clickScreen.y, accuracy: 0.5)
            XCTAssertEqual(mw.menuView.layout.rows.count, 5)
            XCTAssertEqual(mw.frame.size, menu.size)
            XCTAssertGreaterThan(menu.size.width, 60)
            // Hovering highlights; the separator and disabled items do not take the highlight.
            send(.mouseMoved, screen: rowCenter(1))
            XCTAssertEqual(menu.highlightedItem?.title, "Copy")
            send(.mouseMoved, screen: rowCenter(2))
            XCTAssertNil(menu.highlightedItem)
            send(.mouseMoved, screen: rowCenter(3))
            XCTAssertEqual(menu.highlightedItem?.title, "Unavailable")
            send(.leftMouseUp, screen: rowCenter(3))
            XCTAssertTrue(_NSMenuTracker.isTracking, "releasing over a disabled item keeps the menu open")
            // Choosing sends the item's action after the window closes.
            send(.mouseMoved, screen: rowCenter(0))
            send(.leftMouseUp, screen: rowCenter(0))
            XCTAssertEqual(r.chosen, ["Cut"])
            XCTAssertFalse(_NSMenuTracker.isTracking)
            XCTAssertTrue(menuWindows().isEmpty)
            XCTAssertEqual(ended.n, 1)
            w.close()
        }
    }

    func testClickOutsideClosesAndIsSwallowed() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let menu = sampleMenu(r)
            let click = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 50, y: 150), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            let button = NSButton(frame: NSRect(x: 200, y: 10, width: 80, height: 24))
            var clicks = 0
            button.target = button
            button.action = Selector(("countClick:"))
            button.setActionHandler(for: Selector(("countClick:"))) { _ in clicks += 1 }
            w.contentView!.addSubview(button)
            // A click on the window underneath closes the menu and never reaches the button.
            let outside = NSPoint(x: 240, y: 20)
            send(.leftMouseDown, screen: w.convertPoint(toScreen: outside), in: w)
            XCTAssertFalse(_NSMenuTracker.isTracking)
            send(.leftMouseUp, screen: w.convertPoint(toScreen: outside), in: w)
            XCTAssertEqual(clicks, 0)
            XCTAssertTrue(r.chosen.isEmpty)
            // With no menu open the same click reaches the button.
            send(.leftMouseDown, screen: w.convertPoint(toScreen: outside), in: w)
            send(.leftMouseUp, screen: w.convertPoint(toScreen: outside), in: w)
            XCTAssertEqual(clicks, 1)
            w.close()
        }
    }

    func testKeyboardNavigationAndSubmenus() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let menu = sampleMenu(r)
            let click = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 50, y: 150), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            sendKey(125, window: w)                       // down -> Cut
            XCTAssertEqual(menu.highlightedItem?.title, "Cut")
            sendKey(126, window: w)                       // up wraps to More (skips the disabled item and separator)
            XCTAssertEqual(menu.highlightedItem?.title, "More")
            sendKey(124, window: w)                       // right opens the submenu and highlights its first item
            XCTAssertEqual(menuWindows().count, 2)
            let sub = menu.item(withTitle: "More")!.submenu!
            XCTAssertEqual(sub.highlightedItem?.title, "Deep")
            let parent = menuWindows()[0], child = menuWindows()[1]
            XCTAssertEqual(child.frame.minX, parent.frame.maxX - 4, accuracy: 0.5, "the submenu opens to the right of its item")
            sendKey(123, window: w)                       // left closes it
            XCTAssertEqual(menuWindows().count, 1)
            sendKey(0, "c", window: w)                    // type-select cycles through the matches
            XCTAssertEqual(menu.highlightedItem?.title, "Cut")
            sendKey(0, "c", window: w)
            XCTAssertEqual(menu.highlightedItem?.title, "Copy")
            sendKey(36, window: w)                        // return chooses
            XCTAssertEqual(r.chosen, ["Copy"])
            XCTAssertFalse(_NSMenuTracker.isTracking)
            // Escape cancels without choosing; the key never reaches the window's responder.
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            sendKey(53, window: w)
            XCTAssertFalse(_NSMenuTracker.isTracking)
            XCTAssertEqual(r.chosen, ["Copy"])
            w.close()
        }
    }

    func testSubmenuOpensOnHoverAndChoosesDeepItem() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let menu = sampleMenu(r)
            let click = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 50, y: 150), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            send(.mouseMoved, screen: rowCenter(4))
            XCTAssertEqual(menuWindows().count, 2)
            send(.mouseMoved, screen: rowCenter(0, level: 1))
            send(.leftMouseUp, screen: rowCenter(0, level: 1))
            XCTAssertEqual(r.chosen, ["Deep"])
            XCTAssertTrue(menuWindows().isEmpty)
            // Hovering another top-level item closes an open submenu.
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            send(.mouseMoved, screen: rowCenter(4))
            XCTAssertEqual(menuWindows().count, 2)
            send(.mouseMoved, screen: rowCenter(0, level: 0))
            XCTAssertEqual(menuWindows().count, 1)
            menu.cancelTracking()
            XCTAssertTrue(menuWindows().isEmpty)
            w.close()
        }
    }

    func testPopUpPositioningRunsUntilTheMenuCloses() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let menu = sampleMenu(r)
            let host = Platform.backend as! HostBackend
            host.post {
                send(.mouseMoved, screen: rowCenter(1))
                send(.leftMouseUp, screen: rowCenter(1))
            }
            let chose = menu.popUp(positioning: menu.item(at: 1), at: NSPoint(x: 20, y: 100), in: w.contentView)
            XCTAssertTrue(chose)
            XCTAssertEqual(r.chosen, ["Copy"])
            host.post { menu.cancelTracking() }
            XCTAssertFalse(menu.popUp(positioning: nil, at: NSPoint(x: 20, y: 100), in: w.contentView))
            w.close()
        }
    }

    func testRightClickOnAViewOpensItsMenu() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            v.menu = sampleMenu(r)
            w.contentView!.addSubview(v)
            send(.rightMouseDown, screen: w.convertPoint(toScreen: NSPoint(x: 40, y: 40)), in: w)
            XCTAssertTrue(_NSMenuTracker.isTracking)
            XCTAssertEqual(menuWindows().count, 1)
            send(.rightMouseUp, screen: w.convertPoint(toScreen: NSPoint(x: 40, y: 40)), in: w)
            XCTAssertTrue(_NSMenuTracker.isTracking, "releasing the opening click in place keeps the menu open")
            send(.mouseMoved, screen: rowCenter(0))
            send(.leftMouseUp, screen: rowCenter(0))
            XCTAssertEqual(r.chosen, ["Cut"])
            w.close()
        }
    }

    func testPopUpButtonSelectionTitleAndAction() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let b = NSPopUpButton(frame: NSRect(x: 20, y: 100, width: 0, height: 0), pullsDown: false)
            b.addItems(withTitles: ["Small", "Medium", "Large"])
            b.target = r
            b.action = Receiver.pick
            b.sizeToFit()
            w.contentView!.addSubview(b)
            XCTAssertEqual(b.numberOfItems, 3)
            XCTAssertEqual(b.indexOfSelectedItem, 0)
            XCTAssertEqual(b.title, "Small")
            XCTAssertEqual(b.itemArray[0].state, .on)
            XCTAssertGreaterThan(b.frame.width, 60)
            b.selectItem(at: 2)
            XCTAssertEqual(b.titleOfSelectedItem, "Large")
            XCTAssertEqual(b.itemArray[0].state, .off)
            XCTAssertEqual(b.itemArray[2].state, .on)
            XCTAssertTrue(b.selectItem(withTag: 0) == false || b.selectedItem != nil)
            b.addItem(withTitle: "Medium")
            XCTAssertEqual(b.itemTitles, ["Small", "Large", "Medium"], "adding a duplicate title moves the item")
            b.selectItem(withTitle: "Large")
            // Pressing opens the menu with the selected item over the button, title aligned.
            let willPopUp = Counter()
            let o = NotificationCenter.default.addObserver(forName: NSPopUpButton.willPopUpNotification, object: b, queue: nil) { _ in willPopUp.n += 1 }
            defer { NotificationCenter.default.removeObserver(o) }
            let inButton = w.convertPoint(toScreen: NSPoint(x: b.frame.midX, y: b.frame.midY))
            send(.leftMouseDown, screen: inButton, in: w)
            XCTAssertEqual(willPopUp.n, 1)
            XCTAssertTrue(_NSMenuTracker.isTracking)
            let mw = menuWindows()[0]
            let buttonScreen = w.convertToScreen(b.frame)
            let selectedRow = mw.menuView.layout.row(forItemIndex: 1)!
            let rowScreen = mw.convertToScreen(mw.menuView.convert(selectedRow.frame, to: nil))
            XCTAssertEqual(rowScreen.midY, buttonScreen.midY, accuracy: 1, "the selected item sits over the button")
            XCTAssertEqual(mw.frame.minX + mw.menuView.layout.textLeft, buttonScreen.minX + NSPopUpButtonCell.titleInset, accuracy: 1)
            XCTAssertGreaterThanOrEqual(mw.frame.width, b.frame.width)
            // Releasing in place keeps it open; hovering and releasing picks.
            send(.leftMouseUp, screen: inButton, in: w)
            XCTAssertTrue(_NSMenuTracker.isTracking)
            send(.mouseMoved, screen: rowCenter(2))
            send(.leftMouseUp, screen: rowCenter(2))
            XCTAssertFalse(_NSMenuTracker.isTracking)
            XCTAssertEqual(b.titleOfSelectedItem, "Medium")
            XCTAssertEqual(r.chosen, ["Medium"])
            XCTAssertFalse(b.cell!.isHighlighted)
            // Press, drag to an item and release: chooses in one gesture.
            send(.leftMouseDown, screen: inButton, in: w)
            send(.leftMouseDragged, screen: rowCenter(0), in: w)
            send(.leftMouseUp, screen: rowCenter(0), in: w)
            XCTAssertEqual(b.titleOfSelectedItem, "Small")
            XCTAssertEqual(r.chosen, ["Medium", "Small"])
            w.close()
        }
    }

    func testPullDownButtonKeepsItsTitleAndHangsBelow() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let menu = NSMenu(title: "")
            menu.addItem(withTitle: "New File", action: Receiver.pick, keyEquivalent: "").target = r
            menu.addItem(withTitle: "New Folder", action: Receiver.pick, keyEquivalent: "").target = r
            let b = NSPopUpButton(title: "New", pullDownMenu: menu)
            b.frame.origin = NSPoint(x: 20, y: 150)
            w.contentView!.addSubview(b)
            XCTAssertTrue(b.pullsDown)
            XCTAssertEqual(b.title, "New")
            b.performClick(nil)
            let mw = menuWindows()[0]
            let buttonScreen = w.convertToScreen(b.frame)
            XCTAssertEqual(mw.frame.maxY, buttonScreen.minY, accuracy: 0.5)
            XCTAssertEqual(mw.frame.minX, buttonScreen.minX, accuracy: 0.5)
            XCTAssertEqual(mw.menuView.layout.rows.count, 2, "a pull-down with its own title shows every item")
            send(.mouseMoved, screen: rowCenter(1))
            send(.leftMouseUp, screen: rowCenter(1))
            XCTAssertEqual(r.chosen, ["New Folder"])
            XCTAssertEqual(b.title, "New", "choosing does not change a pull-down's title")
            // A pull-down that uses its first item as the title hides that item.
            let b2 = NSPopUpButton(frame: NSRect(x: 20, y: 100, width: 0, height: 0), pullsDown: true)
            b2.addItems(withTitles: ["Actions", "One", "Two"])
            b2.sizeToFit()
            w.contentView!.addSubview(b2)
            XCTAssertEqual(b2.title, "Actions")
            b2.performClick(nil)
            XCTAssertEqual(menuWindows()[0].menuView.layout.rows.map { $0.item.title }, ["One", "Two"])
            menu.cancelTracking(); b2.menu?.cancelTracking()
            XCTAssertTrue(menuWindows().isEmpty)
            w.close()
        }
    }

    func testOwnerLosingKeyClosesTheMenu() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let r = Receiver()
            let menu = sampleMenu(r)
            let click = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 50, y: 150), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                           context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSMenu.popUpContextMenu(menu, with: click, for: w.contentView!)
            XCTAssertTrue(_NSMenuTracker.isTracking)
            let other = makeWindow()
            XCTAssertFalse(_NSMenuTracker.isTracking, "activating another window dismisses the menu")
            other.close(); w.close()
        }
    }
}
