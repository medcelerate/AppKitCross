// The opt-in unified caption on Windows (ADR-0053): a `fullSizeContentView` window with a
// transparent title bar draws its unified title bar as the caption, with the Windows caption
// buttons at the right and the application menu in a package-drawn row directly under the
// band; `APPKITWIN_UNIFIED_CAPTION` forces it off, or maps SwiftUI windows onto the recipe.
// The host backend stands in for Win32 (`drawsUnifiedCaption`); the policy itself is
// WinSDK-free and checked here on every platform.

import XCTest
@testable import AppKit
@testable import SwiftUI

final class UnifiedCaptionTests: XCTestCase, @unchecked Sendable {
    private let app: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    private var recipe: NSWindow.StyleMask { app.union(.fullSizeContentView) }

    private func chrome(transparent: Bool) -> PlatformWindowChrome {
        var c = PlatformWindowChrome()
        c.transparentTitleBar = transparent
        return c
    }

    // MARK: Policy (every platform)

    /// The default is the classic caption; only the standard macOS recipe opts a window in.
    func testOnlyTheRecipeOptsIn() throws {
        try MainActor.assumeIsolated {
            let mode = { (mask: NSWindow.StyleMask, transparent: Bool) in
                Win32WindowPolicy.captionMode(styleMask: mask, chrome: self.chrome(transparent: transparent), switch: .unset)
            }
            XCTAssertEqual(mode(app, false), .classic, "a plain titled window: the system caption and the HMENU bar")
            XCTAssertEqual(mode(app, true), .classic, "a transparent title bar alone is not the recipe")
            XCTAssertEqual(mode(recipe, false), .classic, "fullSizeContentView alone keeps today's custom frame without the menu row")
            XCTAssertEqual(mode(recipe, true), .unified, "fullSizeContentView + titlebarAppearsTransparent: the band is the caption")
            XCTAssertEqual(mode([.borderless, .fullSizeContentView], true), .classic, "a borderless window has no caption to replace")
            XCTAssertEqual(mode([.titled, .utilityWindow, .fullSizeContentView], true), .unified, "a panel may opt in (it just carries no menu row)")
        }
    }

    /// `APPKITWIN_UNIFIED_CAPTION=0` forces classic even for a window that opted in; `=1`
    /// changes nothing for AppKit windows (it maps SwiftUI windows onto the recipe).
    func testTheSwitchOverridesAndMapsSwiftUI() throws {
        try MainActor.assumeIsolated {
            XCTAssertEqual(Win32WindowPolicy.captionMode(styleMask: recipe, chrome: chrome(transparent: true), switch: .off), .classic)
            XCTAssertEqual(Win32WindowPolicy.captionMode(styleMask: recipe, chrome: chrome(transparent: true), switch: .on), .unified)
            XCTAssertEqual(Win32WindowPolicy.captionMode(styleMask: app, chrome: chrome(transparent: false), switch: .on), .classic, "the switch alone never changes an AppKit window")
            XCTAssertFalse(Win32WindowPolicy.mapsSwiftUIWindows(switch: .unset))
            XCTAssertFalse(Win32WindowPolicy.mapsSwiftUIWindows(switch: .off))
            XCTAssertTrue(Win32WindowPolicy.mapsSwiftUIWindows(switch: .on))
        }
    }

    /// The environment variable wins over the Info.plist key; both read the usual truths.
    func testFeatureSwitchReading() throws {
        try MainActor.assumeIsolated {
            XCTAssertEqual(PlatformFeatureSwitch.parse("1"), .on)
            XCTAssertEqual(PlatformFeatureSwitch.parse("YES"), .on)
            XCTAssertEqual(PlatformFeatureSwitch.parse("true"), .on)
            XCTAssertEqual(PlatformFeatureSwitch.parse("0"), .off)
            XCTAssertEqual(PlatformFeatureSwitch.parse("no"), .off)
            XCTAssertEqual(PlatformFeatureSwitch.parse(true), .on)
            XCTAssertEqual(PlatformFeatureSwitch.parse(NSNumber(value: 0)), .off)
            XCTAssertEqual(PlatformFeatureSwitch.parse("maybe"), .unset)
            XCTAssertEqual(PlatformFeatureSwitch.parse(nil), .unset)
            let env = Win32WindowPolicy.unifiedCaptionEnvironmentKey, key = Win32WindowPolicy.unifiedCaptionPlistKey
            XCTAssertEqual(PlatformFeatureSwitch.read(environment: [:], infoDictionary: [:], environmentKey: env, plistKey: key), .unset)
            XCTAssertEqual(PlatformFeatureSwitch.read(environment: [:], infoDictionary: [key: true], environmentKey: env, plistKey: key), .on)
            XCTAssertEqual(PlatformFeatureSwitch.read(environment: [env: "0"], infoDictionary: [key: true], environmentKey: env, plistKey: key), .off, "the environment overrides the plist")
            XCTAssertEqual(PlatformFeatureSwitch.read(environment: [env: "garbage"], infoDictionary: [key: "yes"], environmentKey: env, plistKey: key), .on, "an unreadable variable falls through to the plist")
        }
    }

    /// Without the HMENU bar Alt+Space and Alt+F4 stay DefWindowProc's (system menu, close);
    /// the other Alt combinations are the package's (the row's mnemonics). With the bar,
    /// every system key is DefWindowProc's, as before.
    func testSystemKeysWithoutTheNativeMenuBar() throws {
        try MainActor.assumeIsolated {
            XCTAssertTrue(Win32WindowPolicy.passesSystemKeyToDefWindowProc(virtualKey: Win32WindowPolicy.VK_SPACE, hasNativeMenuBar: false))
            XCTAssertTrue(Win32WindowPolicy.passesSystemKeyToDefWindowProc(virtualKey: Win32WindowPolicy.VK_F4, hasNativeMenuBar: false))
            XCTAssertFalse(Win32WindowPolicy.passesSystemKeyToDefWindowProc(virtualKey: 0x46 /* F */, hasNativeMenuBar: false))
            XCTAssertFalse(Win32WindowPolicy.passesSystemKeyToDefWindowProc(virtualKey: 0x79 /* F10 */, hasNativeMenuBar: false))
            for vk: Int32 in [0x20, 0x73, 0x46, 0x79] { XCTAssertTrue(Win32WindowPolicy.passesSystemKeyToDefWindowProc(virtualKey: vk, hasNativeMenuBar: true)) }
        }
    }

    /// The HMENU bar still goes only on classic windows: a recipe window has no non-client
    /// area for it, which is why the row exists.
    func testTheNativeBarStaysOnClassicWindows() throws {
        try MainActor.assumeIsolated {
            XCTAssertTrue(Win32WindowPolicy.carriesMenuBar(app, applicationHasMenuBar: true))
            XCTAssertFalse(Win32WindowPolicy.carriesMenuBar(recipe, applicationHasMenuBar: true))
        }
    }

    // MARK: Windows (the host backend standing in for Win32)

    @MainActor private func makeMainMenu() -> NSMenu {
        let main = NSMenu(title: "")
        for (title, items) in [("TextEdit", ["About", "Quit"]), ("File", ["New", "Open…", "Save"]), ("Edit", ["Undo", "Redo", "Cut"]), ("View", ["Zoom"])] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            for t in items { sub.addItem(NSMenuItem(title: t, action: nil, keyEquivalent: "")) }
            item.submenu = sub
            main.addItem(item)
        }
        return main
    }

    @MainActor private final class Delegate: NSObject, NSToolbarDelegate {
        static let a = NSToolbarItem.Identifier("a"), b = NSToolbarItem.Identifier("b")
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Delegate.a, Delegate.b] }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Delegate.a, Delegate.b] }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = id.rawValue
            item.image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { r in NSColor.red.setFill(); NSBezierPath(ovalIn: r).fill(); return true }
            return item
        }
    }

    /// Runs `body` with the host backend drawing the unified caption (as Win32 does), the
    /// caption button style, a main menu and the switch pinned to `value`.
    @MainActor private func onWindows<T>(switch value: PlatformFeatureSwitch = .unset, menu: Bool = true, _ body: (HostBackend) throws -> T) throws -> T {
        try requireHostBackend()
        let host = Platform.backend as! HostBackend
        let savedSwitch = Platform.unifiedCaptionSwitchOverride, savedDraw = host.drawsUnifiedCaption, savedMenu = NSApplication.shared.mainMenu
        host.drawsUnifiedCaption = true
        Platform.unifiedCaptionSwitchOverride = value
        if menu { NSApplication.shared.mainMenu = makeMainMenu() }
        defer {
            _NSMenuTracker.current?.cancel()
            NSApplication.shared.mainMenu = savedMenu
            Platform.unifiedCaptionSwitchOverride = savedSwitch
            host.drawsUnifiedCaption = savedDraw
        }
        return try withWindowButtonStyle(.caption) { try body(host) }
    }

    /// The toolbar's delegate is weak: kept here for the window's lifetime.
    private var toolbarDelegate: Delegate?

    @MainActor private func recipeWindow(toolbar: Bool = true, transparent: Bool = true, width: CGFloat = 600) -> (NSWindow, NSToolbar?) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 300), styleMask: recipe, backing: .buffered, defer: false)
        w.title = "New Show"
        w.contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        var tb: NSToolbar?
        if toolbar {
            let t = NSToolbar(identifier: "unified.caption.test")
            toolbarDelegate = Delegate()
            t.delegate = toolbarDelegate
            t.displayMode = .iconOnly
            w.toolbarStyle = .unified
            w.toolbar = t
            tb = t
        }
        w.titlebarAppearsTransparent = transparent
        w.makeKeyAndOrderFront(nil)
        (Platform.backend as! HostBackend).drain()
        return (w, tb)
    }

    /// On macOS and Linux (and on Windows with `APPKITWIN_UNIFIED_CAPTION=0`) the recipe
    /// changes nothing: no menu row, the frame as before.
    func testNoRowWhereTheBackendDrawsNoUnifiedCaption() throws {
        try MainActor.assumeIsolated {
            try requireHostBackend()
            do {
                let host = Platform.backend as! HostBackend
                XCTAssertFalse(host.drawsUnifiedCaption, "the host backend defaults to the macOS / Linux behaviour")
                let saved = NSApplication.shared.mainMenu
                NSApplication.shared.mainMenu = makeMainMenu()
                defer { NSApplication.shared.mainMenu = saved }
                let (w, _) = recipeWindow()
                defer { w.close() }
                XCTAssertFalse(w._usesUnifiedCaption)
                XCTAssertFalse(w._showsMenuBarRow)
                XCTAssertNil(w._menuBarRow)
                XCTAssertEqual(w._menuBarRowHeight, 0)
                XCTAssertEqual(w.contentView!.bounds.height, 300)
                XCTAssertFalse(w._chrome.unifiedCaption)
            }
            try onWindows(switch: .off) { _ in
                let (w, _) = recipeWindow()
                defer { w.close() }
                XCTAssertFalse(w._usesUnifiedCaption, "APPKITWIN_UNIFIED_CAPTION=0 forces the classic caption")
                XCTAssertNil(w._menuBarRow)
            }
        }
    }

    /// The band is the caption: the toolbar at the top of the platform's content area, the
    /// caption buttons in its top-right, the menu row directly under it, the frame grown by
    /// the row so the content keeps its size, and `contentLayoutRect` under all of it.
    func testBandLayoutWithTheMenuRow() throws {
        try MainActor.assumeIsolated {
            try onWindows { host in
                let (w, tb) = recipeWindow()
                defer { w.close() }
                XCTAssertTrue(w._usesUnifiedCaption)
                XCTAssertTrue(w._chrome.unifiedCaption)
                XCTAssertTrue(w._showsMenuBarRow)
                let pc = w._platformContentSize
                XCTAssertEqual(pc.height, 324, "the frame grew by the row: content 300 + row 24")
                XCTAssertEqual(w.contentView!.bounds.height, 300, "the content kept its size")
                let band = tb!._view!.frame
                XCTAssertEqual(band, NSRect(x: 0, y: 272, width: 600, height: 52), "a unified icon-only band over the top of the content area")
                let row = w._menuBarRow!
                XCTAssertFalse(row.isHidden)
                XCTAssertEqual(row.frame, NSRect(x: 0, y: 248, width: 600, height: 24), "the menu row directly under the band")
                XCTAssertEqual(row.frame.maxY, band.minY)
                XCTAssertEqual(w.contentLayoutRect.height, 248, "the content's layout area stops under the row")
                XCTAssertEqual(row.titles.map { $0.item.title }, ["TextEdit", "File", "Edit", "View"])
                XCTAssertTrue(row.titles[0].frame.minX < row.titles[1].frame.minX)
                // The caption buttons: minimise, maximise, close at the trailing edge of the band's top 28 points.
                let close = w.standardWindowButton(.closeButton)!, zoom = w.standardWindowButton(.zoomButton)!, mini = w.standardWindowButton(.miniaturizeButton)!
                XCTAssertEqual(windowCenter(of: close).x, 600 - 23)
                XCTAssertEqual(windowCenter(of: zoom).x, 600 - 69)
                XCTAssertEqual(windowCenter(of: mini).x, 600 - 115)
                XCTAssertEqual(windowCenter(of: close).y, 324 - 14)
                XCTAssertEqual(w._toolbarMetrics!.trailingInset, _NSWindowButtonsView.captionWidth + 4, "the toolbar keeps clear of the buttons")
                w.display()
            }
        }
    }

    /// What Windows hears for each region (`WM_NCHITTEST`): the band drags (HTCAPTION), the
    /// buttons answer as caption buttons (snap layouts over maximise), the menu row and the
    /// content are client.
    func testHitRegionsAndCodes() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, tb) = recipeWindow()
                defer { w.close() }
                w.display()
                @MainActor func code(_ p: NSPoint) -> Int32 { Win32WindowPolicy.hitCode(for: w.platformWindowHitTest(p)) }
                let view = tb!._view!
                let itemFrame = view.convert(try XCTUnwrap(view._frame(ofItem: tb!.items[0])), to: nil)
                let itemCenter = NSPoint(x: itemFrame.midX, y: itemFrame.midY)
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 300, y: 280)), .caption, "the band between the items and the buttons")
                XCTAssertEqual(code(NSPoint(x: 300, y: 280)), Win32WindowPolicy.HTCAPTION)
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 577, y: 310)), .closeButton)
                XCTAssertEqual(code(NSPoint(x: 577, y: 310)), Win32WindowPolicy.HTCLOSE)
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 531, y: 310)), .zoomButton)
                XCTAssertEqual(code(NSPoint(x: 531, y: 310)), Win32WindowPolicy.HTMAXBUTTON)
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 485, y: 310)), .miniaturizeButton)
                XCTAssertEqual(code(NSPoint(x: 485, y: 310)), Win32WindowPolicy.HTMINBUTTON)
                XCTAssertEqual(w.platformWindowHitTest(itemCenter), .client, "a toolbar item takes its own clicks")
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 20, y: 260)), .client, "a menu title is the row's, never a drag")
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 500, y: 260)), .client, "the empty end of the menu row does not drag either, as on Windows")
                XCTAssertEqual(code(NSPoint(x: 500, y: 260)), Win32WindowPolicy.HTCLIENT)
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 300, y: 100)), .client)
                XCTAssertTrue(w._hitTestForTests(NSPoint(x: 20, y: 260)) is _NSMenuBarRowView)
            }
        }
    }

    /// Opting in and out at run time moves the row: turning the transparent title bar off
    /// drops it (the frame shrinks back), turning it on brings it back.
    func testOptingOutAndInMovesTheRow() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, _) = recipeWindow()
                defer { w.close() }
                XCTAssertEqual(w._platformContentSize.height, 324)
                w.titlebarAppearsTransparent = false
                XCTAssertFalse(w._usesUnifiedCaption)
                XCTAssertTrue(w._menuBarRow!.isHidden)
                XCTAssertEqual(w._platformContentSize.height, 300, "the frame shrank back by the row")
                XCTAssertEqual(w.contentView!.bounds.height, 300)
                w.titlebarAppearsTransparent = true
                XCTAssertFalse(w._menuBarRow!.isHidden)
                XCTAssertEqual(w._platformContentSize.height, 324)
                // Dropping `fullSizeContentView` leaves the recipe too.
                w.styleMask.remove(.fullSizeContentView)
                XCTAssertFalse(w._usesUnifiedCaption)
                XCTAssertTrue(w._menuBarRow!.isHidden)
            }
        }
    }

    /// The row follows the application's main menu: it goes when the menu does and
    /// re-reads retitled items without a relayout (the native bars rebuild on every item
    /// state change, which must stay cheap).
    func testTheRowFollowsTheMainMenu() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, _) = recipeWindow()
                defer { w.close() }
                let row = w._menuBarRow!
                XCTAssertEqual(row.titles.count, 4)
                let fileItem = NSApplication.shared.mainMenu!.items[1]
                let heightBefore = w._platformContentSize.height
                fileItem.title = "Document"
                XCTAssertEqual(row.titles[1].item.title, "Document")
                XCTAssertEqual(w._platformContentSize.height, heightBefore, "a retitle is no relayout")
                fileItem.submenu!.items[0].isEnabled = false
                XCTAssertEqual(w._platformContentSize.height, heightBefore, "an item state change is no relayout")
                NSApplication.shared.mainMenu = nil
                XCTAssertTrue(row.isHidden)
                XCTAssertEqual(w._platformContentSize.height, 300, "no menu, no row")
                NSApplication.shared.mainMenu = makeMainMenu()
                XCTAssertFalse(row.isHidden)
                XCTAssertEqual(w._platformContentSize.height, 324)
            }
            // A panel opts into the caption but carries no application menu, like the HMENU bar.
            try onWindows { _ in
                let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
                defer { p.close() }
                p.titlebarAppearsTransparent = true
                XCTAssertTrue(p._usesUnifiedCaption)
                XCTAssertFalse(p._showsMenuBarRow)
            }
        }
    }

    /// A recipe window without a toolbar shows its title in the 28-point band (the band
    /// is still the caption and the buttons sit in it).
    func testTitleInTheBandWithoutAToolbar() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, _) = recipeWindow(toolbar: false)
                defer { w.close() }
                XCTAssertTrue(w._showsMenuBarRow)
                XCTAssertEqual(w._menuBarRow!.frame, NSRect(x: 0, y: 324 - 28 - 24, width: 600, height: 24), "the row directly under the title band")
                XCTAssertEqual(w._windowButtonsRowForTests?.titleText, "New Show")
                w.title = "Renamed"
                XCTAssertEqual(w._windowButtonsRowForTests?.titleText, "Renamed")
                XCTAssertEqual(w.platformWindowHitTest(NSPoint(x: 300, y: 310)), .caption, "the title band drags")
                w.titleVisibility = .hidden
                w.titlebarAppearsTransparent = true
                XCTAssertNil(w._windowButtonsRowForTests?.titleText)
            }
        }
    }

    // MARK: The menu row

    @MainActor private func key(_ w: NSWindow, _ chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }
    @MainActor private func mouse(_ type: NSEvent.EventType, _ w: NSWindow, _ p: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
    }
    @MainActor private func flags(_ w: NSWindow, _ f: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent(type: .flagsChanged, location: .zero, modifierFlags: f, timestamp: 0, windowNumber: w.windowNumber)
    }
    @MainActor private func titleCenter(_ row: _NSMenuBarRowView, _ i: Int) -> NSPoint {
        row.convert(NSPoint(x: row.titles[i].frame.midX, y: row.titles[i].frame.midY), to: nil)
    }

    /// A click on a title opens its menu below the title; the pointer crossing to another
    /// title switches menus; a click on the open title closes it; a click elsewhere too.
    func testClickingAndHoveringTheTitles() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, _) = recipeWindow()
                defer { w.close() }
                let row = w._menuBarRow!
                let app = NSApplication.shared
                app.sendEvent(mouse(.mouseMoved, w, titleCenter(row, 1)))
                XCTAssertEqual(row.hoveredIndex, 1, "hover highlights the title under the pointer")
                app.sendEvent(mouse(.leftMouseDown, w, titleCenter(row, 1)))
                app.sendEvent(mouse(.leftMouseUp, w, titleCenter(row, 1)))
                XCTAssertEqual(row.openIndex, 1)
                let tracker = try XCTUnwrap(_NSMenuTracker.current)
                XCTAssertTrue(tracker.rootMenu === app.mainMenu!.items[1].submenu, "the File menu opened")
                XCTAssertTrue(tracker.menuBarRow === row)
                let menuFrame = tracker.levels[0].window.frame
                let titleScreen = w.convertToScreen(row.convert(row.titles[1].frame, to: nil))
                XCTAssertEqual(menuFrame.maxY, titleScreen.minY, accuracy: 0.5, "the menu hangs below its title")
                XCTAssertEqual(menuFrame.minX, titleScreen.minX, accuracy: 0.5)
                // Across to Edit: the Edit menu replaces File without a click.
                app.sendEvent(mouse(.mouseMoved, w, titleCenter(row, 2)))
                XCTAssertEqual(row.openIndex, 2)
                XCTAssertTrue(_NSMenuTracker.current?.rootMenu === app.mainMenu!.items[2].submenu)
                // A click on the open title closes it.
                app.sendEvent(mouse(.leftMouseDown, w, titleCenter(row, 2)))
                app.sendEvent(mouse(.leftMouseUp, w, titleCenter(row, 2)))
                XCTAssertNil(row.openIndex)
                XCTAssertNil(_NSMenuTracker.current)
                // Open again, click in the content: closed, and the content keeps the click.
                app.sendEvent(mouse(.leftMouseDown, w, titleCenter(row, 3)))
                app.sendEvent(mouse(.leftMouseUp, w, titleCenter(row, 3)))
                XCTAssertEqual(row.openIndex, 3)
                app.sendEvent(mouse(.leftMouseDown, w, NSPoint(x: 300, y: 100)))
                XCTAssertNil(row.openIndex)
                app.sendEvent(mouse(.mouseMoved, w, NSPoint(x: -100_000, y: -100_000)))
                XCTAssertNil(row.hoveredIndex, "the pointer left the window")
            }
        }
    }

    /// Keyboard access as Windows gives it: F10 enters the bar (first title highlighted),
    /// Right and Left move along it, Down opens the menu with its first item highlighted,
    /// Right from an open root menu moves to the next menu, Escape leaves, and a letter
    /// in the bar opens the matching menu.
    func testKeyboardModeAndArrows() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, _) = recipeWindow()
                defer { w.close() }
                let row = w._menuBarRow!
                let app = NSApplication.shared
                app.sendEvent(key(w, "\u{F70D}", code: 109))                       // F10
                XCTAssertTrue(row.isKeyboardActive)
                XCTAssertEqual(row.keyboardIndex, 0)
                XCTAssertTrue(_NSMenuBarRowView.active === row)
                app.sendEvent(key(w, "", code: 124))                               // right
                XCTAssertEqual(row.keyboardIndex, 1)
                app.sendEvent(key(w, "", code: 123))                               // left
                app.sendEvent(key(w, "", code: 123))                               // left wraps
                XCTAssertEqual(row.keyboardIndex, 3)
                app.sendEvent(key(w, "", code: 125))                               // down opens
                XCTAssertFalse(row.isKeyboardActive)
                XCTAssertEqual(row.openIndex, 3)
                var tracker = try XCTUnwrap(_NSMenuTracker.current)
                XCTAssertTrue(tracker.rootMenu === app.mainMenu!.items[3].submenu)
                XCTAssertNotNil(tracker.highlightedItem, "the first item is highlighted for the keyboard")
                app.sendEvent(key(w, "", code: 124))                               // right: the next menu (wrapping)
                XCTAssertEqual(row.openIndex, 0)
                tracker = try XCTUnwrap(_NSMenuTracker.current)
                XCTAssertTrue(tracker.rootMenu === app.mainMenu!.items[0].submenu)
                app.sendEvent(key(w, "", code: 123))                               // left: back
                XCTAssertEqual(row.openIndex, 3)
                app.sendEvent(key(w, "\u{1B}", code: 53))                          // escape closes
                XCTAssertNil(row.openIndex)
                XCTAssertNil(_NSMenuTracker.current)
                XCTAssertNil(_NSMenuBarRowView.active)
                // F10, then a letter: the matching menu opens.
                app.sendEvent(key(w, "\u{F70D}", code: 109))
                app.sendEvent(key(w, "e", code: 14))
                XCTAssertEqual(row.openIndex, 2, "E for Edit")
                app.sendEvent(key(w, "\u{1B}", code: 53))
                // F10 twice leaves the bar; Escape leaves it too.
                app.sendEvent(key(w, "\u{F70D}", code: 109))
                app.sendEvent(key(w, "\u{F70D}", code: 109))
                XCTAssertFalse(row.isKeyboardActive)
                app.sendEvent(key(w, "\u{F70D}", code: 109))
                app.sendEvent(key(w, "\u{1B}", code: 53))
                XCTAssertFalse(row.isKeyboardActive)
            }
        }
    }

    /// Alt+letter opens the menu whose title starts with the letter (the access key Windows
    /// takes when a title has no `&`); an Alt tap toggles keyboard mode; Alt held with a key
    /// is no tap. Key equivalents keep precedence.
    func testMnemonicsAndTheAltTap() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, _) = recipeWindow()
                defer { w.close() }
                let row = w._menuBarRow!
                let app = NSApplication.shared
                app.sendEvent(key(w, "f", code: 3, flags: .option))
                XCTAssertEqual(row.openIndex, 1, "Alt+F opens File")
                app.sendEvent(key(w, "\u{1B}", code: 53))
                app.sendEvent(key(w, "v", code: 9, flags: .option))
                XCTAssertEqual(row.openIndex, 3, "Alt+V opens View")
                app.sendEvent(key(w, "\u{1B}", code: 53))
                app.sendEvent(key(w, "x", code: 7, flags: .option))
                XCTAssertNil(row.openIndex, "no title starts with X")
                app.sendEvent(key(w, "f", code: 3, flags: [.option, .command]))
                XCTAssertNil(row.openIndex, "Ctrl+Alt+F is not a mnemonic")
                // An Alt tap.
                app.sendEvent(flags(w, .option))
                app.sendEvent(flags(w, []))
                XCTAssertTrue(row.isKeyboardActive)
                app.sendEvent(flags(w, .option))
                app.sendEvent(flags(w, []))
                XCTAssertFalse(row.isKeyboardActive, "a second tap leaves")
                // Alt held while a key is pressed: no tap.
                app.sendEvent(flags(w, .option))
                app.sendEvent(key(w, "x", code: 7, flags: .option))
                app.sendEvent(flags(w, []))
                XCTAssertFalse(row.isKeyboardActive)
                // A key equivalent wins over a mnemonic: Ctrl+Alt+Shift... use an Option-only equivalent.
                let file = app.mainMenu!.items[1].submenu!
                @MainActor final class Target: NSObject, NSSelectorHandling {
                    var fired = 0
                    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool { fired += 1; return true }
                }
                let target = Target()
                let item = NSMenuItem(title: "Flip", action: Selector(("go:")), keyEquivalent: "e")
                item.keyEquivalentModifierMask = .option
                item.target = target
                file.addItem(item)
                app.sendEvent(key(w, "e", code: 14, flags: .option))
                XCTAssertEqual(target.fired, 1, "Option+E was the item's key equivalent")
                XCTAssertNil(row.openIndex, "so Edit did not open")
                // Losing key status leaves keyboard mode.
                app.sendEvent(key(w, "\u{F70D}", code: 109))
                XCTAssertTrue(row.isKeyboardActive)
                w.resignKey()
                XCTAssertFalse(row.isKeyboardActive)
            }
        }
    }

    /// The row draws: background, titles, and the highlight of the open or keyboard title
    /// (pixels differ around the title once highlighted).
    func testTheRowDraws() throws {
        try MainActor.assumeIsolated {
            try onWindows { _ in
                let (w, _) = recipeWindow()
                defer { w.close() }
                let row = w._menuBarRow!
                let t = row.titles[1].frame
                w.display()
                let before = try XCTUnwrap(w._captureContent())
                let scale = CGFloat(before.width) / 600
                NSApplication.shared.sendEvent(key(w, "\u{F70D}", code: 109))
                NSApplication.shared.sendEvent(key(w, "", code: 124))
                w.display()
                let after = try XCTUnwrap(w._captureContent())
                // Sample a pixel inside the File title's highlight, clear of its text: the left
                // padding, at the title's mid height (image rows run from the top).
                let fromTop = CGFloat(after.height) / scale - row.frame.maxY + t.midY
                let px = Int((row.frame.minX + t.minX + 3) * scale), py = Int(fromTop * scale)
                func pixel(_ img: CGImage) -> [UInt8] {
                    let d = _pixels(img)
                    let i = py * img.bytesPerRow + px * 4
                    return [d[i], d[i + 1], d[i + 2]]
                }
                XCTAssertNotEqual(pixel(before), pixel(after), "the keyboard highlight paints behind the title")
                NSApplication.shared.sendEvent(key(w, "\u{1B}", code: 53))
            }
        }
    }

    // MARK: SwiftUI

    // Off macOS closing a runner's last window quits the app (App.swift). Linux's XCTest
    // runs these two nonisolated, so they hop explicitly.
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { _AppRunner._terminatesAfterLastWindowCloses = false }
    }
    override func tearDown() {
        MainActor.assumeIsolated { _AppRunner._terminatesAfterLastWindowCloses = true }
        super.tearDown()
    }

    /// With the switch on, a SwiftUI scene window takes the recipe (its title still shown
    /// in the band) and its content lays out under the band and the row; without it the
    /// window keeps the classic caption; the Settings window keeps it either way.
    func testTheSwitchMapsSwiftUIWindows() throws {
        try MainActor.assumeIsolated {
            for value in [PlatformFeatureSwitch.unset, .on] {
                try onWindows(switch: value, menu: false) { host in
                    let runner = _AppRunner(name: "Captioned")
                    runner._runScenes(of: _CaptionedApp())
                    let w = try XCTUnwrap(runner.windows.last)
                    defer {
                        for x in runner.windows { x.close() }
                        NSApplication.shared.windows.first { $0.title == "Captioned Settings" }?.close()
                        NSApplication.shared.mainMenu = nil
                    }
                    for _ in 0..<25 { host.drain() }
                    let mapped = value == .on
                    XCTAssertEqual(w.styleMask.contains(.fullSizeContentView), mapped, "\(value)")
                    XCTAssertEqual(w.titlebarAppearsTransparent, mapped, "\(value)")
                    XCTAssertEqual(w.titleVisibility, .visible, "the band shows the title")
                    XCTAssertEqual(w._usesUnifiedCaption, mapped, "\(value)")
                    XCTAssertNotNil(w.toolbar)
                    if mapped {
                        XCTAssertTrue(w._showsMenuBarRow, "the App's menu bar in the row")
                        XCTAssertFalse(w._menuBarRow!.titles.isEmpty)
                        let hosting = try XCTUnwrap(w.contentView as? any _NSHostingLayoutReporting)
                        w.contentView!.layoutSubtreeIfNeeded()
                        let layoutBounds = hosting._layoutBounds
                        XCTAssertLessThan(layoutBounds.height, w.contentView!.bounds.height, "the content lays out under the band and the row")
                        XCTAssertEqual(layoutBounds.height, w.contentLayoutRect.height, accuracy: 0.5)
                        XCTAssertEqual(layoutBounds.maxY, w.contentView!.bounds.maxY, "flipped: the free area is the lower part")
                    } else {
                        XCTAssertFalse(w._showsMenuBarRow)
                        XCTAssertEqual((w.contentView as? any _NSHostingLayoutReporting)?._layoutBounds, w.contentView?.bounds)
                    }
                    // Settings stays classic whatever the switch.
                    let settings = NSApplication.shared.mainMenu!.items[0].submenu!.items.first { $0.title.hasPrefix("Settings") }!
                    _ = NSApplication.shared.sendAction(settings.action!, to: settings.target, from: settings)
                    let prefs = try XCTUnwrap(NSApplication.shared.windows.first { $0.title == "Captioned Settings" })
                    XCTAssertFalse(prefs.styleMask.contains(.fullSizeContentView), "\(value)")
                    XCTAssertFalse(prefs._usesUnifiedCaption)
                }
            }
        }
    }
}

private struct _CaptionedApp: App {
    init() {}
    var body: some Scene {
        WindowGroup("Captioned") {
            Text("Body").frame(minWidth: 400, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .navigationTitle("Show")
                .toolbar { ToolbarItem(placement: .primaryAction) { Button("Go", systemImage: "play.fill") {} } }
        }
        Settings { Text("Settings").frame(minWidth: 200, maxWidth: .infinity, minHeight: 80, maxHeight: .infinity) }
    }
}

/// The classic HMENU bar, two PC findings fixed alongside ADR-0053: a rebuild that repainted
/// the bar on every item state change (a white flash while typing), and the bar staying
/// light in the dark app theme.
final class ClassicMenuBarTests: XCTestCase {
    private func item(_ id: Int, _ title: String, enabled: Bool = true, hidden: Bool = false, children: [PlatformMenuItem]? = nil) -> PlatformMenuItem {
        PlatformMenuItem(id: id, title: title, isSeparator: false, isEnabled: enabled, isChecked: false, isHidden: hidden, keyEquivalentLabel: "",
                         submenu: children.map { PlatformMenu(id: id * 100, title: title, items: $0) })
    }
    private func bar(_ items: [PlatformMenuItem]) -> PlatformMenu { PlatformMenu(id: 1, title: "", items: items) }

    /// Only what the bar shows (titles, order, visibility, enabled state) is a change of the
    /// bar; an item inside a menu (Undo enabling, a retitle, a check) refills the pop-up.
    func testOnlyTopLevelChangesRebuildTheBar() {
        let undo = item(10, "Undo", enabled: false), redo = item(11, "Redo")
        let a = bar([item(1, "File", children: [item(5, "Save")]), item(2, "Edit", children: [undo, redo])])
        let b = bar([item(1, "File", children: [item(5, "Save")]), item(2, "Edit", children: [item(10, "Undo Typing", enabled: true), redo])])
        XCTAssertFalse(Win32WindowPolicy.menuBarChanged(from: a, to: b), "an item inside Edit changed: refill, no SetMenu")
        XCTAssertFalse(Win32WindowPolicy.menuBarChanged(from: a, to: a))
        XCTAssertTrue(Win32WindowPolicy.menuBarChanged(from: a, to: bar([item(1, "File"), item(2, "Edit", children: []), item(3, "View", children: [])])), "a new top-level menu")
        XCTAssertTrue(Win32WindowPolicy.menuBarChanged(from: a, to: bar([item(1, "Document", children: []), item(2, "Edit", children: [])])), "a retitled top-level menu")
        XCTAssertTrue(Win32WindowPolicy.menuBarChanged(from: a, to: bar([item(1, "File", children: []), item(2, "Edit", enabled: false, children: [])])), "a disabled top-level menu")
        XCTAssertTrue(Win32WindowPolicy.menuBarChanged(from: a, to: bar([item(1, "File", children: []), item(2, "Edit", hidden: true, children: [])])), "a hidden top-level menu")
        XCTAssertFalse(Win32WindowPolicy.menuBarChanged(from: bar([item(1, "File", children: []), item(9, "Debug", hidden: true, children: [])]), to: bar([item(1, "File", children: [])])), "hidden items never showed")
        XCTAssertTrue(Win32WindowPolicy.menuBarChanged(from: nil, to: a))
        XCTAssertTrue(Win32WindowPolicy.menuBarChanged(from: a, to: nil))
        XCTAssertFalse(Win32WindowPolicy.menuBarChanged(from: nil, to: nil))
    }

    /// The owner-drawn bar exists only for the dark app theme on a window with the bar;
    /// its colours follow the item state user32 reports.
    func testDarkMenuBarTheme() {
        XCTAssertTrue(Win32WindowPolicy.drawsMenuBarItself(systemAppThemeIsDark: true, hasNativeMenuBar: true))
        XCTAssertFalse(Win32WindowPolicy.drawsMenuBarItself(systemAppThemeIsDark: false, hasNativeMenuBar: true), "light bars stay user32's")
        XCTAssertFalse(Win32WindowPolicy.drawsMenuBarItself(systemAppThemeIsDark: true, hasNativeMenuBar: false), "a unified caption has no HMENU bar (its row follows the appearance itself)")
        let t = Win32WindowPolicy.darkMenuBarTheme
        let rest = Win32WindowPolicy.menuBarItemColors(itemState: 0)
        XCTAssertEqual(rest.fill, t.background)
        XCTAssertEqual(rest.text, t.text)
        XCTAssertEqual(Win32WindowPolicy.menuBarItemColors(itemState: Win32WindowPolicy.ODS_HOTLIGHT).fill, t.hotBackground)
        XCTAssertEqual(Win32WindowPolicy.menuBarItemColors(itemState: Win32WindowPolicy.ODS_SELECTED).fill, t.selectedBackground)
        XCTAssertEqual(Win32WindowPolicy.menuBarItemColors(itemState: Win32WindowPolicy.ODS_SELECTED | Win32WindowPolicy.ODS_HOTLIGHT).fill, t.selectedBackground, "open beats hot")
        XCTAssertEqual(Win32WindowPolicy.menuBarItemColors(itemState: Win32WindowPolicy.ODS_GRAYED | Win32WindowPolicy.ODS_HOTLIGHT).fill, t.background, "a disabled title shows no hover")
        XCTAssertEqual(Win32WindowPolicy.menuBarItemColors(itemState: Win32WindowPolicy.ODS_GRAYED).text, t.disabledText)
        XCTAssertEqual(Win32WindowPolicy.menuBarItemColors(itemState: Win32WindowPolicy.ODS_INACTIVE).text, t.disabledText, "an inactive window greys its titles")
        XCTAssertEqual(t.underline, t.background)
    }
}
