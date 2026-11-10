// NSToolbar and NSToolbarItem: delegate-driven items, insertion and removal, selection,
// validation, overflow, autosave, the window's placement of the package-drawn toolbar
// and its drawing (ADR-0018).

import XCTest
@testable import AppKit

@MainActor
private final class Delegate: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSSelectorHandling {
    static let back = NSToolbarItem.Identifier("back")
    static let forward = NSToolbarItem.Identifier("forward")
    static let share = NSToolbarItem.Identifier("share")
    static let search = NSToolbarItem.Identifier("search")
    static let colors = NSToolbarItem.Identifier("colors")
    static let style = NSToolbarItem.Identifier("style")
    static let more = NSToolbarItem.Identifier("more")
    static let doAction = Selector(("toolbarAction:"))

    var defaults: [NSToolbarItem.Identifier] = [back, forward, .flexibleSpace, share, colors]
    var allowed: [NSToolbarItem.Identifier] = [back, forward, share, colors, search, style, more, .flexibleSpace, .space, .separator, .print]
    var selectable: [NSToolbarItem.Identifier] = [share, colors]
    var disabled: Set<NSToolbarItem.Identifier> = []
    var fired: [String] = []
    var added: [String] = []
    var removed: [String] = []
    var made: [String] = []

    @MainActor static func icon(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 24, height: 24), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { defaults }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { allowed }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { selectable }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard allowed.contains(id) || defaults.contains(id) else { return nil }
        made.append(id.rawValue)
        switch id {
        case Delegate.search:
            let s = NSSearchToolbarItem(itemIdentifier: id)
            s.preferredWidthForSearchField = 120
            return s
        case Delegate.style:
            return NSToolbarItemGroup(itemIdentifier: id, titles: ["Bold", "Italic"], selectionMode: .selectAny, labels: ["Bold", "Italic"], target: self, action: Delegate.doAction)
        case Delegate.more:
            let m = NSMenuToolbarItem(itemIdentifier: id)
            m.label = "More"
            m.image = Delegate.icon(.systemGray)
            let menu = NSMenu(title: "More")
            menu.addItem(withTitle: "First", action: Delegate.doAction, keyEquivalent: "").target = self
            m.menu = menu
            return m
        default:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = id.rawValue.capitalized
            item.image = Delegate.icon(id == Delegate.back ? .systemBlue : id == Delegate.share ? .systemGreen : .systemOrange)
            item.target = self
            item.action = Delegate.doAction
            item.toolTip = "Tip \(id.rawValue)"
            if id == Delegate.colors { item.visibilityPriority = .low }
            return item
        }
    }
    func toolbarWillAddItem(_ notification: Notification) { added.append((notification.userInfo?["item"] as? NSToolbarItem)?.itemIdentifier.rawValue ?? "?") }
    func toolbarDidRemoveItem(_ notification: Notification) { removed.append((notification.userInfo?["item"] as? NSToolbarItem)?.itemIdentifier.rawValue ?? "?") }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { !disabled.contains(item.itemIdentifier) }
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard action == Delegate.doAction else { return false }
        if let i = sender as? NSToolbarItem { fired.append(i.itemIdentifier.rawValue) }
        else if let m = sender as? NSMenuItem { fired.append("menu:\(m.title)") }
        else { fired.append("?") }
        return true
    }
}

@MainActor
private func makeWindow(_ mask: NSWindow.StyleMask = [.titled, .closable, .resizable], width: CGFloat = 600) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 300), styleMask: mask, backing: .buffered, defer: false)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func hostWindow(_ w: NSWindow) -> HostWindow? { Mirror(reflecting: w).descendant("_platform") as? HostWindow }

@MainActor
private func click(_ view: NSView, at local: NSPoint? = nil) {
    guard let w = view.window else { return }
    let p = view.convert(local ?? NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApplication.shared.sendEvent(e)
    }
}

final class ToolbarTests: XCTestCase, @unchecked Sendable {
    func testDelegateSuppliesTheDefaultItemsInOrder() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.order")
            tb.delegate = d
            XCTAssertTrue(tb.items.isEmpty, "items load once a window attaches the toolbar")
            w.toolbar = tb
            XCTAssertEqual(tb.items.map { $0.itemIdentifier.rawValue }, ["back", "forward", "NSToolbarFlexibleSpaceItem", "share", "colors"])
            XCTAssertEqual(d.added, ["back", "forward", "NSToolbarFlexibleSpaceItem", "share", "colors"])
            XCTAssertEqual(d.made, ["back", "forward", "share", "colors"], "the flexible space is AppKit's own item")
            XCTAssertTrue(tb.items.allSatisfy { $0.toolbar === tb })
            XCTAssertEqual(tb.items[0].label, "Back")
            XCTAssertEqual(tb.items[0].paletteLabel, "Back", "the palette label falls back to the label")
            XCTAssertTrue(tb.items[2].allowsDuplicatesInToolbar)
            XCTAssertFalse(tb.items[0].allowsDuplicatesInToolbar)
            XCTAssertEqual(tb.visibleItems?.count, 5)
            XCTAssertTrue(tb.items[0].isVisible)
        }
    }

    func testInsertRemoveAndIdentifiersRoundTrip() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.insert")
            tb.delegate = d
            w.toolbar = tb
            let willAdd = expectation(forNotification: NSToolbar.willAddItemNotification, object: tb)
            tb.insertItem(withItemIdentifier: Delegate.search, at: 1)
            wait(for: [willAdd], timeout: 1)
            XCTAssertEqual(tb.items[1].itemIdentifier, Delegate.search)
            XCTAssertTrue(tb.items[1] is NSSearchToolbarItem)
            tb.insertItem(withItemIdentifier: Delegate.back, at: 0)
            XCTAssertEqual(tb.items.filter { $0.itemIdentifier == Delegate.back }.count, 1, "no duplicates unless the item allows them")
            tb.insertItem(withItemIdentifier: .space, at: 0)
            tb.insertItem(withItemIdentifier: .space, at: 0)
            XCTAssertEqual(tb.items.filter { $0.itemIdentifier == .space }.count, 2)
            let didRemove = expectation(forNotification: NSToolbar.didRemoveItemNotification, object: tb)
            let removedItem = tb.items[2]
            tb.removeItem(at: 2)
            wait(for: [didRemove], timeout: 1)
            XCTAssertNil(removedItem.toolbar)
            XCTAssertEqual(d.removed, ["back"])
            if #available(macOS 15.0, *) {
                tb.removeItem(identifier: Delegate.search)
                XCTAssertFalse(tb.items.contains { $0.itemIdentifier == Delegate.search })
                tb.itemIdentifiers = [Delegate.forward, Delegate.back]
                XCTAssertEqual(tb.itemIdentifiers, [Delegate.forward, Delegate.back])
            } else {
                tb.setConfiguration(["TB Item Identifiers": ["forward", "back"]])
            }
            XCTAssertEqual(tb.items[1].label, "Back")
            XCTAssertTrue(d.removed.contains("share") && d.removed.contains("colors"))
            tb.insertItem(withItemIdentifier: NSToolbarItem.Identifier("unknown"), at: 0)
            XCTAssertEqual(tb.items.count, 2, "an identifier the delegate declines adds nothing")
        }
    }

    func testStandardItemsExistAndStandardActionsValidate() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let d = Delegate()
            d.defaults = [.print, .showColors, .showFonts, .toggleSidebar, .cloudSharing, .customizeToolbar, .separator]
            let tb = NSToolbar(identifier: "test.standard")
            tb.delegate = d
            tb.allowsUserCustomization = true
            w.toolbar = tb
            XCTAssertEqual(tb.items.count, 7)
            XCTAssertEqual(tb.items[0].label, "Print")
            XCTAssertNotNil(tb.items[0].image)
            XCTAssertEqual(tb.items[0].action, Selector(("printDocument:")))
            tb.validateVisibleItems()
            XCTAssertFalse(tb.items[0].isEnabled, "nothing in the chain prints")
            XCTAssertFalse(tb.items[4].isEnabled, "cloud sharing has no service behind it")
            XCTAssertTrue(tb.items[5].isEnabled, "the window runs the customization palette")
            w.setActionHandler(for: Selector(("printDocument:"))) { _ in }
            tb.validateVisibleItems()
            XCTAssertTrue(tb.items[0].isEnabled, "the responder chain prints now")
        }
    }

    func testSelectionAndValidationThroughTheTarget() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.select")
            tb.delegate = d
            w.toolbar = tb
            XCTAssertEqual(tb._selectableItemIdentifiers, [Delegate.share, Delegate.colors])
            tb.selectedItemIdentifier = Delegate.share
            XCTAssertEqual(tb.selectedItemIdentifier, Delegate.share)
            // The target adopts NSToolbarItemValidation: it decides.
            d.disabled = [Delegate.forward]
            tb.validateVisibleItems()
            XCTAssertTrue(tb.items[0].isEnabled)
            XCTAssertFalse(tb.items[1].isEnabled)
            XCTAssertFalse(tb._view!.subviews.compactMap { $0 as? _NSToolbarItemButton }.first { $0.item === tb.items[1] }!.isEnabled)
            d.disabled = []
            tb.validateVisibleItems()
            XCTAssertTrue(tb.items[1].isEnabled)
            // An item whose target performs nothing is disabled; autovalidates off keeps its state.
            let orphan = tb.items[0]
            orphan.target = NSObject()
            tb.validateVisibleItems()
            XCTAssertFalse(orphan.isEnabled)
            orphan.autovalidates = false
            orphan.isEnabled = true
            tb.validateVisibleItems()
            XCTAssertTrue(orphan.isEnabled)
            // A nil target reaches the responder chain (the delegate is the application delegate here).
            let item = tb.items[3]
            item.target = nil
            let previous = NSApplication.shared.delegate
            NSApplication.shared.delegate = nil
            tb.validateVisibleItems()
            XCTAssertFalse(item.isEnabled)
            w.setActionHandler(for: Delegate.doAction) { _ in d.fired.append("chain") }
            tb.validateVisibleItems()
            XCTAssertTrue(item.isEnabled)
            NSApplication.shared.delegate = previous
        }
    }

    func testClicksSendActionsAndGroupsAndMenusWork() {
        MainActor.assumeIsolated {
            let w = makeWindow(width: 700)
            defer { w.close() }
            let d = Delegate()
            d.defaults = [Delegate.back, Delegate.style, Delegate.more]
            let tb = NSToolbar(identifier: "test.click")
            tb.delegate = d
            w.toolbar = tb
            w.display()
            let view = tb._view!
            let backButton = view.subviews.compactMap { $0 as? _NSToolbarItemButton }.first { $0.item === tb.items[0] }!
            XCTAssertEqual(backButton.toolTip, "Tip back")
            click(backButton)
            XCTAssertEqual(d.fired, ["back"])
            // The toolbar band itself drags the window; its buttons do not.
            let bandPoint = NSPoint(x: view.frame.midX, y: view.frame.maxY - 2)
            XCTAssertEqual(w.platformWindowHitTest(bandPoint), .caption)
            XCTAssertEqual(w.platformWindowHitTest(backButton.convert(NSPoint(x: 5, y: 5), to: nil)), .client)
            // The group's segmented control sends the group's action with the group as sender.
            let group = tb.items[1] as! NSToolbarItemGroup
            let control = group.view as! NSSegmentedControl
            XCTAssertEqual(control.segmentCount, 2)
            control.setSelected(true, forSegment: 1)
            control.performClick(nil)
            XCTAssertEqual(d.fired, ["back", "style"])
            XCTAssertTrue(group.isSelected(at: 1))
            XCTAssertFalse(group.isSelected(at: 0))
            group.setSelected(true, at: 0)
            XCTAssertTrue(control.isSelected(forSegment: 0))
            // The menu item opens its menu below its button.
            let more = tb.items[2] as! NSMenuToolbarItem
            let moreButton = view.subviews.compactMap { $0 as? _NSToolbarItemButton }.first { $0.item === more }!
            click(moreButton)
            XCTAssertTrue(_NSMenuTracker.isTracking)
            let menuWindow = NSApplication.shared.windows.compactMap { $0 as? _NSMenuWindow }.first { $0.isVisible }!
            let buttonScreen = w.convertToScreen(moreButton.convert(moreButton.bounds, to: nil))
            XCTAssertEqual(menuWindow.frame.maxY, buttonScreen.minY, accuracy: 1, "the menu hangs below the button")
            _NSMenuTracker.current?.cancel()
            XCTAssertFalse(_NSMenuTracker.isTracking)
        }
    }

    func testNarrowWindowsOverflowIntoTheChevronMenu() {
        MainActor.assumeIsolated {
            let w = makeWindow(width: 600)
            defer { w.close() }
            let d = Delegate()
            d.defaults = [Delegate.back, Delegate.forward, Delegate.share, Delegate.colors, Delegate.more]
            let tb = NSToolbar(identifier: "test.overflow")
            tb.delegate = d
            w.toolbar = tb
            w.display()
            let view = tb._view!
            XCTAssertEqual(tb.visibleItems?.count, 5)
            XCTAssertTrue(view.overflowItems.isEmpty)
            w.setContentSize(NSSize(width: 170, height: 300))
            w.display()
            XCTAssertLessThan(tb.visibleItems!.count, 5)
            XCTAssertFalse(view.overflowItems.isEmpty)
            XCTAssertTrue(view.overflowItems.contains { $0.itemIdentifier == Delegate.colors }, "the low-priority item goes first")
            XCTAssertTrue(view.overflowItems.contains { $0.itemIdentifier == Delegate.more }, "then the rightmost standard one")
            XCTAssertFalse(tb.items[3].isVisible)
            XCTAssertTrue(tb.items[0].isVisible)
            let chevron = view.subviews.compactMap { $0 as? _NSToolbarOverflowButton }.first!
            XCTAssertFalse(chevron.isHidden)
            XCTAssertLessThanOrEqual(chevron.frame.maxX, view.bounds.width)
            let menu = view._overflowMenu()
            XCTAssertEqual(menu.items.map { $0.title }, view.overflowItems.map { $0.label })
            XCTAssertNotNil(menu.items.last?.submenu, "a menu item's menu becomes a submenu")
            // Choosing an overflowed item sends its action.
            click(chevron)
            XCTAssertTrue(_NSMenuTracker.isTracking)
            let menuWindow = NSApplication.shared.windows.compactMap { $0 as? _NSMenuWindow }.first { $0.isVisible }!
            let row = menuWindow.menuView.layout.rows[0].frame
            let screen = menuWindow.convertPoint(toScreen: menuWindow.menuView.convert(NSPoint(x: row.midX, y: row.midY), to: nil))
            let local = menuWindow.convertPoint(fromScreen: screen)
            for type in [NSEvent.EventType.mouseMoved, .leftMouseUp] {
                NSApplication.shared.sendEvent(NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: 0, windowNumber: menuWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
            }
            XCTAssertEqual(d.fired, [view.overflowItems[0].itemIdentifier.rawValue])
            // Wide again: everything is back.
            w.setContentSize(NSSize(width: 600, height: 300))
            w.display()
            XCTAssertEqual(tb.visibleItems?.count, 5)
            XCTAssertTrue(chevron.isHidden)
        }
    }

    func testAutosaveRoundTrip() {
        MainActor.assumeIsolated {
            let key = "NSToolbar Configuration test.autosave"
            UserDefaults.standard.removeObject(forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let w = makeWindow()
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.autosave")
            tb.delegate = d
            tb.autosavesConfiguration = true
            w.toolbar = tb
            tb.removeItem(at: 0)
            tb.insertItem(withItemIdentifier: Delegate.search, at: 0)
            tb.displayMode = .iconOnly
            tb.sizeMode = .small
            let saved = UserDefaults.standard.dictionary(forKey: key)
            XCTAssertEqual(saved?["TB Item Identifiers"] as? [String], ["search", "forward", "NSToolbarFlexibleSpaceItem", "share", "colors"])
            XCTAssertEqual(saved?["TB Display Mode"] as? Int, NSToolbar.DisplayMode.iconOnly.rawValue)
            XCTAssertEqual(saved?["TB Size Mode"] as? Int, NSToolbar.SizeMode.small.rawValue)
            XCTAssertEqual(saved?["TB Is Shown"] as? Bool, true)
            XCTAssertEqual(tb.configuration["TB Item Identifiers"] as? [String], saved?["TB Item Identifiers"] as? [String])
            w.close()
            let w2 = makeWindow()
            defer { w2.close() }
            let tb2 = NSToolbar(identifier: "test.autosave")
            tb2.autosavesConfiguration = true
            let d2 = Delegate()
            tb2.delegate = d2
            w2.toolbar = tb2
            XCTAssertEqual(tb2.items.map { $0.itemIdentifier.rawValue }, ["search", "forward", "NSToolbarFlexibleSpaceItem", "share", "colors"])
            XCTAssertEqual(tb2.displayMode, .iconOnly)
            XCTAssertEqual(tb2.sizeMode, .small)
            tb2.setConfiguration(["TB Item Identifiers": ["back"], "TB Display Mode": NSToolbar.DisplayMode.labelOnly.rawValue])
            XCTAssertEqual(tb2.items.map { $0.itemIdentifier }, [Delegate.back])
            XCTAssertEqual(tb2.displayMode, .labelOnly)
        }
    }

    func testWindowGrowsByTheBandAndKeepsItsContentSize() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let frameBefore = w.frame
            let contentBefore = w.contentView!.frame.size
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.geometry")
            tb.delegate = d
            w.toolbar = tb
            let band = w._toolbarMetrics!.height
            XCTAssertGreaterThan(band, 40)
            XCTAssertEqual(w.frame.height, frameBefore.height + band, "the frame grows by the band")
            XCTAssertEqual(w.frame.maxY, frameBefore.maxY, "the top edge stays")
            XCTAssertEqual(w.contentView!.frame.size, contentBefore, "the content keeps its size")
            XCTAssertEqual(w.contentRect(forFrameRect: w.frame).height, contentBefore.height)
            XCTAssertEqual(w.frameRect(forContentRect: w.contentRect(forFrameRect: w.frame)), w.frame)
            let view = tb._view!
            XCTAssertEqual(view.frame.minY, contentBefore.height, "the toolbar sits right above the content")
            XCTAssertEqual(view.frame.maxY, w._platformContentSize.height, "and right under the title band")
            XCTAssertEqual(view.frame.width, w.frame.width)
            // Hiding takes the band away again; the menu action toggles it.
            w.toggleToolbarShown(nil)
            XCTAssertFalse(tb.isVisible)
            XCTAssertNil(tb.visibleItems)
            XCTAssertEqual(w.frame, frameBefore)
            XCTAssertTrue(view.isHidden)
            XCTAssertTrue(w.performSelectorAction(Selector(("toggleToolbarShown:")), with: nil))
            XCTAssertTrue(tb.isVisible)
            XCTAssertEqual(w.frame.height, frameBefore.height + band)
            // Display mode changes the height.
            tb.displayMode = .iconOnly
            let compact = w._toolbarMetrics!.height
            XCTAssertLessThan(compact, band)
            XCTAssertEqual(w.frame.height, frameBefore.height + compact)
            XCTAssertEqual(w.contentView!.frame.size, contentBefore)
            // Detaching restores the plain frame.
            w.toolbar = nil
            XCTAssertEqual(w.frame, frameBefore)
            XCTAssertNil(tb._window)
        }
    }

    func testUnifiedToolbarOverlaysContentThatCoversTheTitleBar() {
        MainActor.assumeIsolated {
            let w = makeWindow([.titled, .closable, .resizable, .fullSizeContentView])
            defer { w.close() }
            let frameBefore = w.frame
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.unified")
            tb.delegate = d
            w.toolbar = tb
            XCTAssertEqual(w.frame, frameBefore, "the content covers the title bar: the toolbar overlays it")
            let m = w._toolbarMetrics!
            XCTAssertEqual(m.placement, .overContent)
            XCTAssertEqual(m.height, 52, "automatic resolves to unified")
            XCTAssertEqual(w.contentLayoutRect.height, w.contentView!.bounds.height - 52)
            let view = tb._view!
            XCTAssertEqual(view.frame.maxY, w.contentView!.bounds.height)
            w.display()
            // Items start after the standard buttons.
            let first = view.subviews.compactMap { $0 as? _NSToolbarItemButton }.min { $0.frame.minX < $1.frame.minX }!
            XCTAssertGreaterThanOrEqual(first.frame.minX, _NSWindowButtonsView.width)
            XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 18, y: w.contentView!.bounds.height - 14)), .client, "the close button is still on top")
            w.toolbarStyle = .unifiedCompact
            XCTAssertEqual(w._toolbarMetrics!.height, 38)
            w.toolbarStyle = .expanded
            XCTAssertEqual(w._toolbarMetrics!.topInset, NSWindow._titleBarBandHeight, "expanded on such a window keeps the title band above the items")
            XCTAssertEqual(w.frame, frameBefore)
        }
    }

    func testToolbarDrawsUnderTheTitleBandAboveTheContent() {
        MainActor.assumeIsolated {
            final class Red: NSView { override func draw(_ r: NSRect) { NSColor.red.setFill(); NSBezierPath.fill(bounds) } }
            let w = makeWindow()
            defer { w.close() }
            let content = Red(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
            content.autoresizingMask = [.width, .height]
            w.contentView = content
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.pixels")
            tb.delegate = d
            w.toolbar = tb
            w.appearance = NSAppearance(named: .aqua)
            w.display()
            guard let image = hostWindow(w)?.lastImage else { return XCTFail("no host image") }
            let data = _pixels(image)
            let scale = Int(w.backingScaleFactor)
            func pixel(_ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int, a: Int) {   // content points, y up
                let i = (image.height - 1 - y * scale) * image.bytesPerRow + x * scale * 4
                return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
            }
            let band = Int(w._toolbarMetrics!.height)
            let contentHeight = Int(w.contentView!.bounds.height)
            XCTAssertEqual(image.height, (contentHeight + band) * scale, "the backing store holds the content and the band")
            let inContent = pixel(300, contentHeight - 5)
            XCTAssertTrue(inContent.r > 200 && inContent.g < 60, "red content just below the band \(inContent)")
            let inBand = pixel(300, contentHeight + 3)
            XCTAssertTrue(inBand.r > 200 && inBand.g > 200 && inBand.b > 200, "a light band above the content \(inBand)")
            XCTAssertTrue(abs(inBand.r - inBand.g) < 6, "grey, not red \(inBand)")
            let separator = pixel(300, contentHeight)
            XCTAssertTrue(separator.r < inBand.r, "the baseline separator is darker than the band \(separator) vs \(inBand)")
            // An item's icon (blue circle) sits inside the band.
            let back = tb._view!.subviews.compactMap { $0 as? _NSToolbarItemButton }.first { $0.item === tb.items[0] }!
            let center = tb._view!.convert(NSPoint(x: back.frame.midX, y: back.frame.midY), to: nil)
            let icon = pixel(Int(center.x), Int(center.y))
            XCTAssertTrue(icon.b > 150 && icon.r < 120, "the blue icon is drawn in the band \(icon)")
            // cacheDisplay of the toolbar view alone gives the same band.
            let rep = tb._view!.bitmapImageRepForCachingDisplay(in: tb._view!.bounds)!
            tb._view!.cacheDisplay(in: tb._view!.bounds, to: rep)
            XCTAssertEqual(rep.pixelsHigh, band * scale)
        }
    }

    func testCustomizationPaletteAddsAndRemovesItems() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.palette")
            tb.delegate = d
            w.toolbar = tb
            w.runToolbarCustomizationPalette(nil)
            XCTAssertFalse(tb.customizationPaletteIsRunning, "customization is off by default")
            tb.allowsUserCustomization = true
            w.runToolbarCustomizationPalette(nil)
            XCTAssertTrue(tb.customizationPaletteIsRunning)
            XCTAssertEqual(w.sheets.count, 1)
            let palette = Mirror(reflecting: tb).descendant("_palette") as! _NSToolbarCustomizationPalette
            XCTAssertEqual(palette.addPopUp.itemTitles.contains("Search"), true)
            XCTAssertFalse(palette.addPopUp.itemTitles.contains("Back"), "items already in the toolbar are not offered twice")
            palette.addPopUp.selectItem(withTitle: "Search")
            palette.addButton.performClick(nil)
            XCTAssertEqual(tb.items.last?.itemIdentifier, Delegate.search)
            palette.removePopUp.selectItem(withTitle: "Back")
            palette.removeButton.performClick(nil)
            XCTAssertFalse(tb.items.contains { $0.itemIdentifier == Delegate.back })
            palette.displayPopUp.selectItem(at: 1)
            _ = palette.displayPopUp.sendAction(palette.displayPopUp.action, to: palette.displayPopUp.target)
            XCTAssertEqual(tb.displayMode, .iconOnly)
            palette.defaultsButton.performClick(nil)
            XCTAssertEqual(tb.items.map { $0.itemIdentifier }, d.defaults)
            palette.doneButton.performClick(nil)
            XCTAssertFalse(tb.customizationPaletteIsRunning)
            XCTAssertTrue(w.sheets.isEmpty)
        }
    }

    func testToolbarItemsAreAccessibleButtons() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let d = Delegate()
            let tb = NSToolbar(identifier: "test.a11y")
            tb.delegate = d
            w.toolbar = tb
            w.display()
            let tree = w.accessibilityTree()
            guard let toolbar = tree.children.first(where: { $0.role == NSAccessibility.Role.toolbar.rawValue }) else { return XCTFail("no toolbar element in \(tree.children.map { $0.role })") }
            let buttons = toolbar.children.filter { $0.role == NSAccessibility.Role.button.rawValue }
            XCTAssertEqual(buttons.map { $0.label }, ["Back", "Forward", "Share", "Colors"])
            XCTAssertTrue(buttons[0].actions.contains(.press))
            XCTAssertTrue(w.accessibilityPerform(.press, on: buttons[0].id))
            XCTAssertEqual(d.fired, ["back"])
        }
    }
}
