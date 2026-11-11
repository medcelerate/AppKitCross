// Accessibility follow-ups (ADR-0013): menus and pop-up items in the tree, virtual
// elements (`NSAccessibilityElement`), custom actions, structure events that name the
// child, SwiftUI control parity and frames on monitors of different scales. Host backend.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func hostWindow(_ w: NSWindow) -> HostWindow? {
    var m: Mirror? = Mirror(reflecting: w)
    while let cur = m {
        if let h = cur.descendant("_platform") as? HostWindow { return h }
        m = cur.superclassMirror
    }
    return nil
}

@MainActor
private func find(_ tree: PlatformAccessibilityElement, _ role: NSAccessibility.Role, title: String? = nil, label: String? = nil) -> PlatformAccessibilityElement? {
    tree.flattened.first { $0.role == role.rawValue && (title == nil || $0.title == title) && (label == nil || $0.label == label) }
}

@MainActor
private final class Recorder: NSObject, NSSelectorHandling {
    var actions: [String] = []
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool { actions.append(NSStringFromSelector(action)); return true }
}

/// A chart view that draws two bars and publishes them as virtual elements.
@MainActor
private final class BarChart: NSView {
    final class Bar: NSAccessibilityElement {
        var pressed = 0
        override func accessibilityPerformPress() -> Bool { pressed += 1; return true }
    }
    let bars: [Bar]
    var resetCount = 0
    override init(frame: NSRect) {
        bars = [Bar(), Bar()]
        super.init(frame: frame)
        for (i, b) in bars.enumerated() {
            b.setAccessibilityRole(.button)
            b.setAccessibilityLabel(i == 0 ? "January" : "February")
            b.setAccessibilityValue(i == 0 ? 12 : 30)
            b.setAccessibilityFrameInParentSpace(NSRect(x: 10 + CGFloat(i) * 40, y: 0, width: 30, height: CGFloat(i == 0 ? 40 : 90)))
            b.setAccessibilityParent(self)
        }
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Reset zoom") { [unowned self] in self.resetCount += 1; return true }])
    }
    required init?(coder: NSCoder) { nil }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Rainfall" }
    override func accessibilityChildren() -> [Any]? { bars }
}

final class AccessibilityFollowUpTests: XCTestCase, @unchecked Sendable {

    /// These tests read what the core told the platform window (`HostWindow`) and drive
    /// the host backend's displays; on a real window system (the Win32 or X11 backend,
    /// APPKITWIN_HOST_BACKEND unset) they skip. The platform halves have their own suites
    /// (UIAutomationTests, AtspiTests).
    override func setUpWithError() throws {
        try super.setUpWithError()
        let isHost = MainActor.assumeIsolated { Platform.backend is HostBackend }
        guard isHost else { throw XCTSkip("needs the host backend (APPKITWIN_HOST_BACKEND=1)") }
    }

    // MARK: Mixed DPI

    func testFramesReachPhysicalPixelsThroughTheWindowsOwnScale() {
        MainActor.assumeIsolated {
            let backend = Platform.backend as! HostBackend
            let saved = backend.displays
            defer { backend.displays = saved; backend.physicalOrigins = [:] }
            // A 100% primary (1920x1080 pixels) and a 200% monitor to its right, 2560x1440
            // pixels, top-aligned: in AppKit points the second one is 1280x720.
            backend.displays = [
                PlatformDisplay(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1040), backingScaleFactor: 1, localizedName: "Primary", isMain: true),
                PlatformDisplay(frame: NSRect(x: 1920, y: 360, width: 1280, height: 720), visibleFrame: NSRect(x: 1920, y: 360, width: 1280, height: 720), backingScaleFactor: 2, localizedName: "Second", isMain: false),
            ]
            backend.physicalOrigins = [0: CGPoint(x: 0, y: 0), 1: CGPoint(x: 1920, y: 0)]
            let w = NSWindow(contentRect: NSRect(x: 2000, y: 500, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let button = NSButton(title: "OK", target: nil, action: nil)
            button.frame = NSRect(x: 20, y: 30, width: 80, height: 24)
            w.contentView!.addSubview(button)
            w.makeKeyAndOrderFront(nil)
            let host = hostWindow(w)!
            host.setBackingScaleFactor(2)        // the window is on the 200% monitor
            let tree = w.accessibilityTree()
            XCTAssertEqual(tree.clientFrame, NSRect(x: 2000, y: 500, width: 400, height: 300), "the root carries the client area in the frames' points")
            let mapping = host.accessibilityScreenMapping(clientFrame: tree.mappingClientFrame)!
            XCTAssertEqual(mapping.clientOriginX, 1920 + 80 * 2)
            XCTAssertEqual(mapping.clientOriginY, (1080 - 800) * 2)
            let ok = find(tree, .button, title: "OK")!
            XCTAssertEqual(ok.frame, NSRect(x: 2020, y: 530, width: 80, height: 24))
            let px = mapping.pixelRect(ok.frame)
            XCTAssertEqual(px.x, 2080 + 40)
            XCTAssertEqual(px.y, 560 + (800 - 554) * 2)
            XCTAssertEqual(px.width, 160, "the size is in the window's pixels: twice the points")
            XCTAssertEqual(px.height, 48)
            // What the primary monitor's scale would have given: nowhere near the button.
            let naiveLeft = Int32(ok.frame.minX * saved[0].backingScaleFactor / 2)
            XCTAssertNotEqual(naiveLeft, px.x)
            // Hit testing goes back the same way.
            let centre = mapping.point(pixelX: Double(px.x) + 80, pixelY: Double(px.y) + 24)
            XCTAssertEqual(tree.element(at: centre)?.id, ok.id)
            // On the primary monitor at 100% the same window maps one point to one pixel.
            w.setFrameOrigin(NSPoint(x: 100, y: 100))
            host.setBackingScaleFactor(1)
            let t2 = w.accessibilityTree()
            let m2 = host.accessibilityScreenMapping(clientFrame: t2.mappingClientFrame)!
            let px2 = m2.pixelRect(find(t2, .button, title: "OK")!.frame)
            XCTAssertEqual(px2.width, 80)
            XCTAssertEqual(px2.x, Int32(t2.clientFrame!.minX) + 20)
            w.close()
        }
    }

    // MARK: Menus

    private func makeMainMenu(_ recorder: Recorder) -> NSMenu {
        let main = NSMenu(title: "Main")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        let open = NSMenuItem(title: "Open…", action: Selector(("openDocument:")), keyEquivalent: "o")
        open.target = recorder
        let ruler = NSMenuItem(title: "Show Ruler", action: Selector(("toggleRuler:")), keyEquivalent: "")
        ruler.target = recorder
        ruler.state = .on
        let off = NSMenuItem(title: "Disabled", action: nil, keyEquivalent: "")
        off.isEnabled = false
        file.autoenablesItems = false
        file.addItem(open)
        file.addItem(.separator())
        file.addItem(ruler)
        file.addItem(off)
        fileItem.submenu = file
        main.addItem(fileItem)
        return main
    }

    func testMainMenuIsAMenuBarOfItems() {
        MainActor.assumeIsolated {
            let recorder = Recorder()
            let saved = NSApp.mainMenu
            defer { NSApp.mainMenu = saved }
            NSApp.mainMenu = makeMainMenu(recorder)
            XCTAssertTrue((NSApp.accessibilityChildren() ?? []).contains { ($0 as? NSMenu) === NSApp.mainMenu }, "the application lists its menu bar")
            let bar = NSApp.accessibilityMenuBarTree()!
            XCTAssertEqual(bar.role, "AXMenuBar")
            let file = find(bar, .menuBarItem, title: "File")!
            XCTAssertEqual(file.children.first?.role, "AXMenu", "a closed item's submenu is its child")
            XCTAssertEqual(file.isExpanded, false)
            let items = file.children.first!.children
            XCTAssertEqual(items.map(\.title), ["Open…", "Show Ruler", "Disabled"], "separators are not elements")
            XCTAssertEqual(items[0].role, "AXMenuItem")
            XCTAssertEqual(items[0].keyEquivalent, NSMenuItem(title: "", action: nil, keyEquivalent: "o")._keyEquivalentLabel)
            XCTAssertNotNil(items[0].keyEquivalent)
            XCTAssertEqual(items[0].checkedState, 0)
            XCTAssertEqual(items[1].checkedState, 1)
            XCTAssertFalse(items[2].isEnabled)
            XCTAssertEqual(items[0].actions, [.press, .pick])
            // Pressing a closed leaf performs it.
            XCTAssertTrue(NSApp.accessibilityPerformMenuBarAction(.press, on: items[0].id))
            XCTAssertEqual(recorder.actions, ["openDocument:"])
            XCTAssertFalse(NSApp.accessibilityPerformMenuBarAction(.press, on: items[2].id), "a disabled item does nothing")
            // Pressing the bar item opens its menu as a live AXMenu.
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            w.makeKeyAndOrderFront(nil)
            XCTAssertTrue(NSApp.accessibilityPerformMenuBarAction(.press, on: file.id))
            let tracker = _NSMenuTracker.current!
            XCTAssertEqual(NSApp.accessibilityMenuBarTree().flatMap { find($0, .menuBarItem, title: "File") }?.isExpanded, true)
            let menuWindow = tracker.levels[0].window
            let tree = menuWindow.accessibilityTree()
            XCTAssertEqual(tree.role, "AXMenu", "the open menu's window is the menu")
            XCTAssertEqual(tree.label, "File")
            XCTAssertEqual(tree.children.map(\.title), ["Open…", "Show Ruler", "Disabled"])
            XCTAssertFalse(tree.children[0].frame.isEmpty, "open items have frames")
            XCTAssertTrue(menuWindow.frame.contains(tree.children[0].frame))
            XCTAssertTrue(hostWindow(menuWindow)!.accessibilityChanges.contains(.menuOpened(menuWindow._accessibilityElementID)))
            // Choosing an item through the menu window performs it and closes the menu.
            XCTAssertTrue(menuWindow.accessibilityPerform(.press, on: tree.children[1].id))
            XCTAssertNil(_NSMenuTracker.current)
            XCTAssertEqual(recorder.actions, ["openDocument:", "toggleRuler:"])
            w.close()
        }
    }

    func testPopUpButtonItemsWhileOpen() {
        MainActor.assumeIsolated {
            let recorder = Recorder()
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let popup = NSPopUpButton(frame: NSRect(x: 20, y: 20, width: 120, height: 24), pullsDown: false)
            popup.addItems(withTitles: ["Blue", "Red", "Green"])
            popup.target = recorder
            popup.action = Selector(("colourChanged:"))
            w.contentView!.addSubview(popup)
            w.makeKeyAndOrderFront(nil)
            let host = hostWindow(w)!
            var p = find(w.accessibilityTree(), .popUpButton)!
            XCTAssertEqual(p.value, .string("Blue"))
            XCTAssertEqual(p.isExpanded, false)
            host.clearAccessibilityChanges()
            // Expanding (UIA ExpandCollapse, AT-SPI's expand) opens the menu.
            XCTAssertTrue(w.accessibilityPerform(.expand, on: p.id))
            XCTAssertNotNil(_NSMenuTracker.current)
            p = find(w.accessibilityTree(), .popUpButton)!
            XCTAssertEqual(p.isExpanded, true)
            let menu = p.children.first!
            XCTAssertEqual(menu.role, "AXMenu")
            XCTAssertEqual(menu.children.map(\.role), ["AXMenuItem", "AXMenuItem", "AXMenuItem"])
            XCTAssertEqual(menu.children.map(\.title), ["Blue", "Red", "Green"])
            XCTAssertFalse(menu.children[1].frame.isEmpty)
            XCTAssertTrue(host.accessibilityChanges.contains(.childAdded(parent: p.id, child: menu.id)), "the event names the menu")
            // Picking "Red" selects it, sends the action and closes the menu.
            host.clearAccessibilityChanges()
            XCTAssertTrue(w.accessibilityPerform(.pick, on: menu.children[1].id))
            XCTAssertNil(_NSMenuTracker.current)
            XCTAssertEqual(popup.titleOfSelectedItem, "Red")
            XCTAssertEqual(recorder.actions, ["colourChanged:"])
            p = find(w.accessibilityTree(), .popUpButton)!
            XCTAssertEqual(p.value, .string("Red"))
            XCTAssertEqual(p.children, [])
            XCTAssertTrue(host.accessibilityChanges.contains(.childRemoved(parent: p.id, child: menu.id)))
            // Collapsing closes without choosing.
            XCTAssertTrue(w.accessibilityPerform(.expand, on: p.id))
            XCTAssertTrue(w.accessibilityPerform(.collapse, on: p.id))
            XCTAssertNil(_NSMenuTracker.current)
            XCTAssertEqual(popup.titleOfSelectedItem, "Red")
            w.close()
        }
    }

    func testOpenMenuReportsTheHighlightedItemAsFocus() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let popup = NSPopUpButton(frame: NSRect(x: 20, y: 20, width: 120, height: 24), pullsDown: false)
            popup.addItems(withTitles: ["One", "Two"])
            w.contentView!.addSubview(popup)
            w.makeKeyAndOrderFront(nil)
            popup.performClick(nil)
            let t = _NSMenuTracker.current!
            let menuWindow = t.levels[0].window
            let mh = hostWindow(menuWindow)!
            mh.clearAccessibilityChanges()
            t.handle(NSEvent._menuKey(125))      // down
            let tree = menuWindow.accessibilityTree()
            let highlighted = tree.children.first { $0.isSelected }!
            XCTAssertTrue(highlighted.isFocused)
            XCTAssertEqual(mh.accessibilityChanges.last, .focus(highlighted.id))
            XCTAssertTrue(menuWindow.accessibilityPerform(.cancel, on: menuWindow._accessibilityElementID), "cancel on the menu closes it")
            XCTAssertNil(_NSMenuTracker.current)
            XCTAssertTrue(mh.accessibilityChanges.contains(.menuClosed(menuWindow._accessibilityElementID)))
            w.close()
        }
    }

    // MARK: Virtual elements and custom actions

    func testAccessibilityElementsArePublishedByCustomViews() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let chart = BarChart(frame: NSRect(x: 50, y: 20, width: 200, height: 150))
            w.contentView!.addSubview(chart)
            w.makeKeyAndOrderFront(nil)
            let tree = w.accessibilityTree()
            let group = find(tree, .group, label: "Rainfall")!
            XCTAssertEqual(group.children.map(\.label), ["January", "February"])
            let jan = group.children[0], feb = group.children[1]
            XCTAssertEqual(jan.role, "AXButton")
            XCTAssertEqual(jan.value, .number(12))
            // Parent space is the chart's: offset by the chart's place in the window.
            let content = w.contentRect(forFrameRect: w.frame)
            XCTAssertEqual(feb.frame, NSRect(x: content.minX + 50 + 50, y: content.minY + 20, width: 30, height: 90))
            XCTAssertTrue(chart.frame.offsetBy(dx: content.minX, dy: content.minY).contains(jan.frame))
            XCTAssertEqual(tree.element(at: NSPoint(x: feb.frame.midX, y: feb.frame.midY))?.id, feb.id, "hit testing finds the virtual element")
            XCTAssertTrue(w.accessibilityPerform(.press, on: feb.id))
            XCTAssertEqual(chart.bars[1].pressed, 1)
            // The chart's custom action is listed by name and runs by its id.
            XCTAssertEqual(group.customActions.map(\.name), ["Reset zoom"])
            XCTAssertTrue(w.accessibilityPerform(.press, on: group.customActions[0].id))
            XCTAssertEqual(chart.resetCount, 1)
            // Nested elements add their parent's offset.
            let detail = NSAccessibilityElement()
            detail.setAccessibilityRole(.staticText)
            detail.setAccessibilityLabel("Peak")
            detail.setAccessibilityFrameInParentSpace(NSRect(x: 5, y: 5, width: 10, height: 10))
            chart.bars[1].accessibilityAddChildElement(detail)
            let peak = find(w.accessibilityTree(), .staticText, label: "Peak")!
            XCTAssertEqual(peak.frame, NSRect(x: feb.frame.minX + 5, y: feb.frame.minY + 5, width: 10, height: 10))
            let made = NSAccessibilityElement.element(withRole: .image, frame: NSRect(x: 1, y: 2, width: 3, height: 4), label: "Logo", parent: chart) as! NSAccessibilityElement
            XCTAssertEqual(made.accessibilityFrame(), NSRect(x: 1, y: 2, width: 3, height: 4))
            XCTAssertEqual(made.accessibilityLabel(), "Logo")
            XCTAssertTrue(made.accessibilityParent() as? NSView === chart)
            w.close()
        }
    }

    func testCustomActionsWithTargetAndSelector() {
        MainActor.assumeIsolated {
            let recorder = Recorder()
            let a = NSAccessibilityCustomAction(name: "Archive", target: recorder, selector: Selector(("archive:")))
            XCTAssertEqual(a.name, "Archive")
            XCTAssertEqual(a.selector, Selector(("archive:")))
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let b = NSButton(title: "Message", target: nil, action: nil)
            b.setAccessibilityCustomActions([a])
            w.contentView!.addSubview(b)
            w.makeKeyAndOrderFront(nil)
            let e = find(w.accessibilityTree(), .button, title: "Message")!
            XCTAssertEqual(e.customActions, [PlatformAccessibilityCustomAction(id: a._accessibilityElementID, name: "Archive")])
            XCTAssertTrue(w.accessibilityPerform(.press, on: e.customActions[0].id))
            XCTAssertEqual(recorder.actions, ["archive:"])
            w.close()
        }
    }

    // MARK: SwiftUI parity

    private struct Controls: View {
        @State var speed = 30.0
        @State var on = false
        @State var name = "Car"
        @State var colour = "A"
        var body: some View {
            VStack(alignment: .leading) {
                TextField("Name", text: $name)
                Slider(value: $speed, in: 0...120, step: 10) { Text("Speed") }
                Toggle("Moving", isOn: $on)
                Picker("Colour", selection: $colour) { Text("A").tag("A"); Text("B").tag("B") }
                ProgressView(value: 0.25)
            }
        }
    }

    func testSwiftUIControlsReachTheTreeLikeTheirAppKitCounterparts() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = NSHostingView(rootView: Controls())
            w.makeKeyAndOrderFront(nil)
            w.contentView!.layoutSubtreeIfNeeded()
            let tree = w.accessibilityTree()
            let slider = find(tree, .slider)!
            XCTAssertEqual(slider.label, "Speed", "the slider's label names it")
            XCTAssertEqual(slider.value, .number(30))
            XCTAssertEqual(slider.minValue, 0)
            XCTAssertEqual(slider.maxValue, 120)
            XCTAssertEqual(slider.actions, [.increment, .decrement])
            XCTAssertTrue(slider.isSettable)
            XCTAssertTrue(w.accessibilityPerform(.increment, on: slider.id))
            XCTAssertEqual(find(w.accessibilityTree(), .slider)?.value, .number(40), "an increment moves one step")
            XCTAssertTrue(w.accessibilityPerform(.decrement, on: slider.id))
            XCTAssertTrue(w.accessibilitySetValue(.number(77), on: slider.id))
            XCTAssertEqual(find(w.accessibilityTree(), .slider)?.value, .number(80), "a stepped slider snaps to its steps")
            XCTAssertEqual(find(tree, .textField)?.label, "Name")
            w.contentView!.layoutSubtreeIfNeeded()
            let toggle = find(tree, .checkBox, title: "Moving")!
            XCTAssertTrue(w.accessibilityPerform(.press, on: toggle.id))
            w.contentView!.layoutSubtreeIfNeeded()
            XCTAssertEqual(find(w.accessibilityTree(), .checkBox, title: "Moving")?.value, .number(1))
            let picker = find(tree, .popUpButton)!
            XCTAssertEqual(picker.label, "Colour", "the picker's label names its pop-up")
            XCTAssertEqual(picker.value, .string("A"))
            let progress = find(tree, .progressIndicator)!
            XCTAssertEqual(progress.value, .number(0.25))
            XCTAssertEqual(progress.maxValue, 1)
            w.close()
        }
    }
}
