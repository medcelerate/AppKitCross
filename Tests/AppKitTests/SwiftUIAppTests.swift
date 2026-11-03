// App scenes: the menu bar an App installs, CommandMenu and CommandGroup additions, and
// the Settings scene's window.

import XCTest
@testable import AppKit
@testable import SwiftUI

final class SwiftUIAppTests: XCTestCase, @unchecked Sendable {
    @MainActor private func items(_ menu: NSMenu?) -> [String] { (menu?.items ?? []).map { $0.isSeparatorItem ? "-" : $0.title } }

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
