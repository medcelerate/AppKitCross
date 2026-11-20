// App scenes: the menu bar an App installs, CommandMenu and CommandGroup additions, and
// the Settings scene's window.

import XCTest
import Observation
@testable import AppKit
@testable import SwiftUI

@Observable private final class _SessionModel { var running = false }

@MainActor private func _appTestTexts(_ view: NSView?) -> [String] {
    guard let view else { return [] }
    return view.subviews.flatMap { _appTestTexts($0) } + [(view as? NSTextField)?.stringValue].compactMap { $0 }
}
@MainActor private func _appTestMenu(_ title: String) -> NSMenu? { NSApplication.shared.mainMenu?.items.first { $0.title == title }?.submenu }

/// An App whose scenes read its own `@State` and an `@Observable` model, in the window
/// content, in the commands and in the Settings scene (as Sibyl's does).
private struct _StatefulApp: App {
    @State private var exporting = false
    @State private var model = _SessionModel()
    init() {}
    var body: some Scene {
        // Text fields rather than Text: the port draws Text without a backing view, and the
        // test reads the hosted NSTextFields.
        WindowGroup("Main") { TextField("", text: .constant(exporting ? "Exporting" : "Idle")) }
            .commands {
                CommandMenu("Session") {
                    Button(model.running ? "Stop Capture" : "Start Capture") { model.running.toggle() }
                    Button("Export Show…") { exporting = true }
                }
            }
        Settings { TextField("", text: .constant(exporting ? "Settings: exporting" : "Settings: idle")).frame(minWidth: 200, maxWidth: .infinity, minHeight: 80, maxHeight: .infinity) }
    }
}

final class SwiftUIAppTests: XCTestCase, @unchecked Sendable {
    // These tests make `_AppRunner`s and close their windows; off macOS closing a runner's
    // last window quits the app (App.swift), which would end the test process early.
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { _AppRunner._terminatesAfterLastWindowCloses = false }
    }
    override func tearDown() {
        MainActor.assumeIsolated { _AppRunner._terminatesAfterLastWindowCloses = true }
        super.tearDown()
    }

    @MainActor private func items(_ menu: NSMenu?) -> [String] { (menu?.items ?? []).map { $0.isSeparatorItem ? "-" : $0.title } }

    func testWindowResizabilityContentSize() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            struct Fixed: View { var body: some View { Text("Fixed").frame(width: 240, height: 120) } }
            let runner = _AppRunner(name: "Fixed")
            runner.run(scene: WindowGroup("Fixed") { Fixed() }.windowResizability(.contentSize))
            let w = runner.windows.last!
            XCTAssertFalse(w.styleMask.contains(.resizable), "contentSize: no resize frame or zoom")
            XCTAssertEqual(w.minSize, w.maxSize)
            XCTAssertEqual(w.minSize, w.frame.size)
            let open = _AppRunner(name: "Open")
            open.run(scene: WindowGroup("Open") { Fixed() })
            XCTAssertTrue(open.windows.last!.styleMask.contains(.resizable), "automatic: resizable")
            w.close(); open.windows.last!.close()
        }
    }

    func testAppStateRerendersWindowsCommandsAndSettings() {
        MainActor.assumeIsolated {
            let texts = _appTestTexts, menu = _appTestMenu
            let runner = _AppRunner(name: "Sibyl")
            runner._runScenes(of: _StatefulApp())
            let window = runner.windows.last!
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(window.contentView).contains("Idle"))
            XCTAssertEqual(items(menu("Session")), ["Start Capture", "Export Show…"])

            // An @Observable property the commands read: the menu follows it.
            let start = menu("Session")!.items[0]
            _ = NSApplication.shared.sendAction(start.action!, to: start.target, from: start)
            runner._updateScenes()
            XCTAssertEqual(items(menu("Session")), ["Stop Capture", "Export Show…"], "the Session menu re-reads the model")

            // App @State read by the window content and the Settings scene.
            let settings = NSApplication.shared.mainMenu!.items[0].submenu!.items.first { $0.title.hasPrefix("Settings") }!
            _ = NSApplication.shared.sendAction(settings.action!, to: settings.target, from: settings)
            let prefs = NSApplication.shared.windows.first { $0.title == "Sibyl Settings" }!
            XCTAssertFalse(prefs.platformWantsMenuBar, "the Settings dialog carries no in-window menu bar")
            XCTAssertTrue(prefs.styleMask.contains(.resizable), "flexible content: a resizable Settings window")
            let export = menu("Session")!.items[1]
            _ = NSApplication.shared.sendAction(export.action!, to: export.target, from: export)
            runner._updateScenes()
            window.contentView?.layoutSubtreeIfNeeded()
            prefs.contentView?.layoutSubtreeIfNeeded()
            XCTAssertTrue(texts(window.contentView).contains("Exporting"), "the WindowGroup content re-renders on App @State")
            XCTAssertTrue(texts(prefs.contentView).contains("Settings: exporting"), "the open Settings window re-renders too")
            for w in runner.windows { w.close() }
            prefs.close()
            NSApplication.shared.mainMenu = nil
        }
    }

    func testMenuBarCommandsAndSettings() {
        MainActor.assumeIsolated {
            final class Log { var added = 0 }
            let log = Log()
            struct Main: View { var body: some View { Text("Main") } }
            struct Prefs: View { var body: some View { Text("Preferences").frame(width: 200, height: 80) } }
            let runner = _AppRunner(name: "Planets")
            runner.run(scene: WindowGroup("Planets") { Main() }.commands {
                CommandMenu("Catalog") {
                    Button("Add Planet") { log.added += 1 }.keyboardShortcut("n", modifiers: [.command, .shift])
                    Divider()
                    Menu("Export") { Button("As CSV") {} }
                }
                CommandGroup(replacing: .appInfo) { Button("About Planets (custom)") {} }
                CommandGroup(after: .newItem) { Button("New Catalog") {} }
            })
            runner.run(scene: Settings { Prefs() })
            runner.installMenuBar()
            let main = NSApplication.shared.mainMenu
            XCTAssertEqual(items(main), ["Planets", "File", "Edit", "Catalog", "Window", "Help"], "a custom menu sits before Window; an empty View menu is left out")
            func menu(_ title: String) -> NSMenu? { main?.items.first { $0.title == title }?.submenu }
            let app = menu("Planets")
            XCTAssertEqual(items(app), ["About Planets (custom)", "-", "Settings\u{2026}", "-", "Quit Planets"])
            XCTAssertEqual(app?.items[2].keyEquivalent, ",")
            let file = menu("File")
            XCTAssertEqual(items(file), ["New Window", "-", "New Catalog", "-", "Close"], "the addition follows the newItem group")
            let catalog = menu("Catalog")
            XCTAssertEqual(items(catalog), ["Add Planet", "-", "Export"])
            XCTAssertEqual(catalog?.items[0].keyEquivalent, "n")
            XCTAssertEqual(catalog?.items[0].keyEquivalentModifierMask, [.command, .shift])
            XCTAssertEqual(items(catalog?.items[2].submenu), ["As CSV"])
            // Items run their closures through target/action.
            let add = catalog!.items[0]
            _ = NSApplication.shared.sendAction(add.action!, to: add.target, from: add)
            XCTAssertEqual(log.added, 1)
            // The Edit menu carries the standard responder-chain actions.
            XCTAssertTrue(items(menu("Edit")).contains("Select All"))
            // Settings… opens one window with the scene's content and reuses it.
            let settings = app!.items[2]
            _ = NSApplication.shared.sendAction(settings.action!, to: settings.target, from: settings)
            let window = NSApplication.shared.windows.first { $0.title == "Planets Settings" }
            XCTAssertNotNil(window)
            XCTAssertTrue(window!.isVisible)
            _ = NSApplication.shared.sendAction(settings.action!, to: settings.target, from: settings)
            XCTAssertEqual(NSApplication.shared.windows.filter { $0.title == "Planets Settings" }.count, 1)
            for w in runner.windows { w.close() }
            window?.close()
            NSApplication.shared.mainMenu = nil
        }
    }
}
