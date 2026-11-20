// A TabView in the Settings scene: macOS's Settings tab bar (icon over label, the selected
// item highlighted, the window titled by the selected tab) rather than a segmented control.

import XCTest
@testable import AppKit
@testable import SwiftUI

private enum _Pane: String, Hashable { case look, audio, network }

@MainActor
private func _settingsHost<V: View>(_ view: V, width: CGFloat = 640, height: CGFloat = 400) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.title = "App Settings"
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor private func _allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_allViews) }

/// The tab view Sibyl's Settings scene shows, with a binding the test can read and set.
private struct _PanesProbe: View {
    @Binding var selected: _Pane
    var body: some View {
        TabView(selection: $selected) {
            Tab("Look & Feel", systemImage: "paintbrush", value: _Pane.look) { Text("look page") }
            Tab("Audio", systemImage: "waveform", value: _Pane.audio) { Text("audio page") }
            Tab("Network", systemImage: "network", value: _Pane.network) { Text("network page") }
        }
        .frame(minWidth: 560, idealWidth: 760, maxWidth: .infinity, minHeight: 380, idealHeight: 520, maxHeight: .infinity)
    }
}

@MainActor private final class _SelectionBox { var value = _Pane.audio }

final class SwiftUISettingsTabsTests: XCTestCase, @unchecked Sendable {
    func testSettingsTabViewShowsToolbarStyleTabBar() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let box = _SelectionBox()
            let binding = Binding(get: { box.value }, set: { box.value = $0 })
            let (window, host) = _settingsHost(_PanesProbe(selected: binding).environment(\._isSettingsScene, true))
            defer { window.close() }
            let views = _allViews(host)
            XCTAssertTrue(views.compactMap { $0 as? NSSegmentedControl }.isEmpty, "no segmented control in the Settings window")
            let bar = try! XCTUnwrap(views.compactMap { $0 as? _SettingsTabBarView }.first)
            XCTAssertEqual(bar.frame.width, host.frame.width, "the band spans the window")
            XCTAssertEqual(bar.frame.minY, 0, "the band sits under the title bar")
            let items = bar.buttons
            XCTAssertEqual(items.map(\.title), ["Look & Feel", "Audio", "Network"])
            XCTAssertTrue(items.allSatisfy { $0.image != nil }, "each item carries its symbol")
            XCTAssertEqual(items.map(\.state), [.off, .on, .off], "the selected tab's item is on")
            XCTAssertEqual(items[1].contentTintColor, .labelColor)
            XCTAssertEqual(items[0].contentTintColor, .secondaryLabelColor)
            // The row is centred in the band.
            let left = items.first!.frame.minX, right = bar.frame.width - items.last!.frame.maxX
            XCTAssertLessThanOrEqual(abs(left - right), 1, "items centred")
            // Accessibility: a radio group of radio buttons, the selected one marked.
            XCTAssertEqual(bar.accessibilityRole(), .radioGroup)
            XCTAssertEqual(bar.accessibilityValue() as? String, "Audio")
            XCTAssertEqual(items[1].accessibilityRole(), .radioButton)
            XCTAssertTrue(items[1].isAccessibilitySelected())
            XCTAssertFalse(items[0].isAccessibilitySelected())
            // The window shows the selected tab's title.
            XCTAssertEqual(window.title, "Audio")

            // A click selects: the binding follows, the highlight moves, the title follows.
            items[2].performClick(nil)
            XCTAssertEqual(box.value, .network)
            host.layoutSubtreeIfNeeded()
            let after = _allViews(host).compactMap { $0 as? _SettingsTabBarView }.first!
            XCTAssertEqual(after.buttons.map(\.state), [.off, .off, .on])
            XCTAssertEqual(window.title, "Network")
            XCTAssertTrue(_allViews(host).compactMap { ($0 as? _TextView)?.storage.string }.contains("network page"))

            // A selection changed from outside (an @AppStorage default) re-renders the bar.
            box.value = .look
            host.rootView = _PanesProbe(selected: binding).environment(\._isSettingsScene, true)
            host.layoutSubtreeIfNeeded()
            let outside = _allViews(host).compactMap { $0 as? _SettingsTabBarView }.first!
            XCTAssertEqual(outside.buttons.map(\.state), [.on, .off, .off])
            XCTAssertEqual(window.title, "Look & Feel")
        }
    }

    func testAppStorageSelectionInSettingsTabView() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let key = "SwiftUISettingsTabsTests.pane"
            UserDefaults.standard.removeObject(forKey: key)
            defer { UserDefaults.standard.removeObject(forKey: key) }
            struct Stored: View {
                @AppStorage("SwiftUISettingsTabsTests.pane") var pane = _Pane.look.rawValue
                var body: some View {
                    TabView(selection: $pane) {
                        Tab("Look & Feel", systemImage: "paintbrush", value: _Pane.look.rawValue) { Text("look page") }
                        Tab("Audio", systemImage: "waveform", value: _Pane.audio.rawValue) { Text("audio page") }
                    }
                }
            }
            let (window, host) = _settingsHost(Stored().environment(\._isSettingsScene, true))
            defer { window.close() }
            var bar: _SettingsTabBarView { _allViews(host).compactMap { $0 as? _SettingsTabBarView }.first! }
            XCTAssertEqual(bar.buttons.map(\.state), [.on, .off])
            bar.buttons[1].performClick(nil)
            XCTAssertEqual(UserDefaults.standard.string(forKey: key), _Pane.audio.rawValue, "a click writes the stored selection")
            // The default changes from outside: the bar follows.
            UserDefaults.standard.set(_Pane.look.rawValue, forKey: key)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(bar.buttons.map(\.state), [.on, .off])
            XCTAssertEqual(window.title, "Look & Feel")
        }
    }

    func testTabViewOutsideSettingsKeepsSegmentedControl() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let box = _SelectionBox()
            let binding = Binding(get: { box.value }, set: { box.value = $0 })
            let (window, host) = _settingsHost(_PanesProbe(selected: binding))
            defer { window.close() }
            let views = _allViews(host)
            XCTAssertTrue(views.compactMap { $0 as? _SettingsTabBarView }.isEmpty)
            let seg = try! XCTUnwrap(views.compactMap { $0 as? NSSegmentedControl }.first)
            XCTAssertEqual(seg.segmentCount, 3)
            XCTAssertEqual(seg.selectedSegment, 1)
            XCTAssertEqual(window.title, "App Settings", "a TabView elsewhere leaves the window title alone")
        }
    }

    func testSettingsSceneWindowUsesSettingsTabBar() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            _AppRunner._terminatesAfterLastWindowCloses = false
            defer { _AppRunner._terminatesAfterLastWindowCloses = true }
            struct Main: View { var body: some View { Text("Main") } }
            struct Prefs: View {
                @State var pane = _Pane.look
                var body: some View { _PanesProbe(selected: $pane) }
            }
            let runner = _AppRunner(name: "Panes")
            runner.run(scene: WindowGroup("Panes") { Main() })
            runner.run(scene: Settings { Prefs() })
            runner.installMenuBar()
            let app = NSApplication.shared.mainMenu!.items[0].submenu!
            let settings = app.items.first { $0.title.hasPrefix("Settings") }!
            _ = NSApplication.shared.sendAction(settings.action!, to: settings.target, from: settings)
            let window = try! XCTUnwrap(NSApplication.shared.windows.last { $0 is _SettingsWindow && $0.isVisible })
            window.contentView?.layoutSubtreeIfNeeded()
            let bar = try! XCTUnwrap(_allViews(window.contentView!).compactMap { $0 as? _SettingsTabBarView }.first)
            XCTAssertEqual(bar.buttons.map(\.title), ["Look & Feel", "Audio", "Network"])
            XCTAssertEqual(window.title, "Look & Feel", "the Settings window is titled by the selected tab, not the app")
            XCTAssertTrue(window.styleMask.contains(.resizable))
            bar.buttons[1].performClick(nil)
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.title, "Audio")
            for w in runner.windows { w.close() }
            window.close()
            NSApplication.shared.mainMenu = nil
        }
    }
}
