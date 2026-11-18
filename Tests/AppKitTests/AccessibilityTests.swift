// Accessibility (ADR-0013): the element tree the core builds from the NSAccessibility
// protocol answers of its views, the change notifications it sends the platform window,
// and the SwiftUI modifiers that feed it. Everything here runs on the host backend; the
// platform halves (UI Automation, AT-SPI2) have their own tests.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func _allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(_allViews) }

@MainActor
private func hostWindow(_ w: NSWindow) -> HostWindow? { Mirror(reflecting: w).descendant("_platform") as? HostWindow }

@MainActor
private func element(_ tree: PlatformAccessibilityElement, role: NSAccessibility.Role, label: String? = nil) -> PlatformAccessibilityElement? {
    tree.flattened.first { $0.role == role.rawValue && (label == nil || $0.label == label) }
}

/// A window laid out like HelloWindow's main window: a label, an editable field, a push
/// button, a check box, a slider, a pop-up and an image, inside a plain content view.
@MainActor
private final class Fixture: NSObject, NSSelectorHandling {
    let window: NSWindow
    let canvas: NSView
    let prompt: NSTextField
    let field: NSTextField
    let clear: NSButton
    let grid: NSButton
    let slider: NSSlider
    let colours: NSPopUpButton
    let image: NSImageView
    var actions: [String] = []

    override init() {
        window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 640, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Hello, AppKit on Windows"
        canvas = NSView(frame: window.contentView!.bounds)
        window.contentView = canvas
        prompt = NSTextField(labelWithString: "Your name:")
        prompt.frame.origin = NSPoint(x: 40, y: 300)
        field = NSTextField(string: "")
        field.placeholderString = "type here, then press Enter"
        field.frame = NSRect(x: 120, y: 296, width: 180, height: 24)
        field.action = Selector(("nameEntered:"))
        clear = NSButton(title: "Clear dots", target: nil, action: Selector(("clearDots:")))
        clear.frame.origin = NSPoint(x: 500, y: 16)
        grid = NSButton(checkboxWithTitle: "Show grid", target: nil, action: Selector(("toggleGrid:")))
        grid.state = .on
        grid.frame.origin = NSPoint(x: 380, y: 16)
        slider = NSSlider(value: 120, minValue: 40, maxValue: 200, target: nil, action: Selector(("sizeChanged:")))
        slider.frame = NSRect(x: 40, y: 20, width: 220, height: 21)
        slider.numberOfTickMarks = 5
        colours = NSPopUpButton(frame: NSRect(x: 280, y: 60, width: 0, height: 0), pullsDown: false)
        colours.addItems(withTitles: ["Blue", "Red", "Green"])
        colours.sizeToFit()
        image = NSImageView(frame: NSRect(x: 400, y: 60, width: 64, height: 64))
        image.toolTip = "Badge"
        super.init()
        for c in [prompt, field, clear, grid, slider, colours] as [NSControl] { c.target = self }
        for v in [prompt, field, clear, grid, slider, colours, image] as [NSView] { canvas.addSubview(v) }
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(canvas)
    }

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        actions.append(NSStringFromSelector(action))
        return true
    }
}

final class AccessibilityTests: XCTestCase, @unchecked Sendable {

    /// These tests read what the core told the platform window (`HostWindow`) and drive
    /// the host backend's displays; on a real window system (the Win32 or X11 backend,
    /// APPKITWIN_HOST_BACKEND unset) they skip. The platform halves have their own suites
    /// (UIAutomationTests, AtspiTests).
    override func setUpWithError() throws {
        try super.setUpWithError()
        let isHost = MainActor.assumeIsolated { Platform.backend is HostBackend }
        guard isHost else { throw XCTSkip("needs the host backend (APPKITWIN_HOST_BACKEND=1)") }
    }

    // MARK: The tree

    func testWindowTreeHasRolesLabelsAndValues() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let tree = f.window.accessibilityTree()
            XCTAssertEqual(tree.role, "AXWindow")
            XCTAssertEqual(tree.subrole, "AXStandardWindow")
            XCTAssertEqual(tree.title, "Hello, AppKit on Windows")
            XCTAssertEqual(tree.id, f.window._accessibilityElementID)
            XCTAssertTrue(tree.isFocused, "the key window is focused")
            // The plain content view is ignored: the controls are the window's children.
            XCTAssertEqual(tree.children.map(\.role), ["AXStaticText", "AXTextField", "AXButton", "AXCheckBox", "AXSlider", "AXPopUpButton", "AXImage"])

            let label = element(tree, role: .staticText)!
            XCTAssertEqual(label.value, .string("Your name:"))
            XCTAssertFalse(label.isFocusable)

            let field = element(tree, role: .textField)!
            XCTAssertEqual(field.placeholder, "type here, then press Enter")
            XCTAssertEqual(field.label, "type here, then press Enter", "an unlabelled field is named by its placeholder")
            XCTAssertEqual(field.value, .string(""))
            XCTAssertTrue(field.isSettable)
            XCTAssertTrue(field.isFocusable)
            XCTAssertEqual(field.actions, [.confirm])

            let button = element(tree, role: .button)!
            XCTAssertEqual(button.label, "Clear dots")
            XCTAssertNil(button.value, "a push button has no value")
            XCTAssertEqual(button.actions, [.press])
            XCTAssertTrue(button.isEnabled)

            let check = element(tree, role: .checkBox)!
            XCTAssertEqual(check.label, "Show grid")
            XCTAssertEqual(check.value, .number(1))
            XCTAssertTrue(check.isSettable)

            let slider = element(tree, role: .slider)!
            XCTAssertEqual(slider.value, .number(120))
            XCTAssertEqual(slider.minValue, 40)
            XCTAssertEqual(slider.maxValue, 200)
            XCTAssertEqual(slider.actions, [.increment, .decrement])

            let popup = element(tree, role: .popUpButton)!
            XCTAssertEqual(popup.value, .string("Blue"))
            XCTAssertEqual(popup.actions, [.press, .showMenu, .expand, .collapse])
            XCTAssertEqual(popup.isExpanded, false, "a closed pop-up is collapsed")
            XCTAssertEqual(popup.children, [], "its items are children only while the menu is open")

            let image = element(tree, role: .image)!
            XCTAssertEqual(image.label, "Badge", "the tool tip names an image")
            XCTAssertEqual(image.help, "Badge")
            f.window.close()
        }
    }

    func testFramesAreInScreenCoordinates() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let tree = f.window.accessibilityTree()
            XCTAssertEqual(tree.frame, f.window.frame)
            let button = element(tree, role: .button)!
            let expected = f.window.convertToScreen(f.clear.convert(f.clear.bounds, to: nil))
            XCTAssertEqual(button.frame, expected)
            XCTAssertEqual(button.frame.minX, 100 + 500, "window origin plus the button's x")
            XCTAssertTrue(tree.frame.contains(button.frame))
            // The element at a screen point is the deepest one whose frame holds it.
            let hit = tree.element(at: NSPoint(x: button.frame.midX, y: button.frame.midY))
            XCTAssertEqual(hit?.id, button.id)
            XCTAssertEqual(tree.element(at: NSPoint(x: f.window.frame.minX + 5, y: f.window.frame.minY + 5))?.id, tree.id, "empty canvas: the window")
            XCTAssertNil(tree.element(at: NSPoint(x: -1000, y: -1000)))
            XCTAssertEqual(tree.parent(of: button.id)?.id, tree.id)
            f.window.close()
        }
    }

    func testIgnoredAndHiddenViews() {
        MainActor.assumeIsolated {
            let f = Fixture()
            // A plain view is ignored but its subviews are not: a box around a button
            // contributes the button to the window.
            let box = NSView(frame: NSRect(x: 0, y: 100, width: 200, height: 100))
            let inner = NSButton(title: "Inner", target: nil, action: nil)
            box.addSubview(inner)
            f.canvas.addSubview(box)
            var tree = f.window.accessibilityTree()
            XCTAssertNotNil(element(tree, role: .button, label: "Inner"))
            XCTAssertEqual(inner.accessibilityParent() as? NSWindow, f.window, "the nearest element above an ignored view is the window")
            XCTAssertFalse(box.isAccessibilityElement())
            // A hidden view takes its subtree out of the tree; so does accessibilityHidden.
            box.isHidden = true
            tree = f.window.accessibilityTree()
            XCTAssertNil(element(tree, role: .button, label: "Inner"))
            box.isHidden = false
            f.clear.setAccessibilityHidden(true)
            tree = f.window.accessibilityTree()
            XCTAssertNil(element(tree, role: .button, label: "Clear dots"))
            XCTAssertNotNil(element(tree, role: .button, label: "Inner"))
            f.clear.setAccessibilityHidden(false)
            // A view given a role becomes an element of its own, with the overrides it was given.
            box.setAccessibilityRole(.group)
            box.setAccessibilityLabel("Tools")
            box.setAccessibilityHelp("Buttons live here")
            tree = f.window.accessibilityTree()
            let group = element(tree, role: .group)!
            XCTAssertEqual(group.label, "Tools")
            XCTAssertEqual(group.help, "Buttons live here")
            XCTAssertEqual(group.children.map(\.label), ["Inner"])
            XCTAssertTrue(inner.accessibilityParent() as? NSView === box)
            // A disabled control reports so; the override wins when set.
            f.clear.isEnabled = false
            XCTAssertFalse(element(f.window.accessibilityTree(), role: .button, label: "Clear dots")!.isEnabled)
            f.clear.setAccessibilityEnabled(true)
            XCTAssertTrue(element(f.window.accessibilityTree(), role: .button, label: "Clear dots")!.isEnabled)
            f.window.close()
        }
    }

    func testOverridesReplaceDerivedValues() {
        MainActor.assumeIsolated {
            let f = Fixture()
            f.clear.setAccessibilityLabel("Remove every dot")
            f.clear.setAccessibilityIdentifier("clear-button")
            f.slider.setAccessibilityValue("about half")
            f.field.setAccessibilityPlaceholderValue("your name")
            let tree = f.window.accessibilityTree()
            let button = element(tree, role: .button)!
            XCTAssertEqual(button.label, "Remove every dot")
            XCTAssertEqual(button.title, "Clear dots", "the title stays the control's")
            XCTAssertEqual(button.identifier, "clear-button")
            XCTAssertEqual(element(tree, role: .slider)!.value, .string("about half"))
            XCTAssertEqual(element(tree, role: .textField)!.placeholder, "your name")
            f.window.close()
        }
    }

    // MARK: Focus

    func testFocusFollowsTheFirstResponder() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let host = hostWindow(f.window)!
            host.clearAccessibilityChanges()
            XCTAssertNil(f.window.accessibilityFocusedElementID, "the canvas is not an element")
            _ = f.window.makeFirstResponder(f.clear)
            XCTAssertEqual(f.window.accessibilityFocusedElementID, f.clear._accessibilityElementID)
            XCTAssertTrue(f.clear.isAccessibilityFocused())
            XCTAssertEqual(host.accessibilityChanges.last, .focus(f.clear._accessibilityElementID))
            XCTAssertTrue(element(f.window.accessibilityTree(), role: .button)!.isFocused)
            // Editing a text field focuses its field editor; the field is what the platform sees.
            _ = f.window.makeFirstResponder(f.field)
            XCTAssertTrue(f.window.firstResponder is NSTextView, "the field editor took over")
            XCTAssertEqual(f.window.accessibilityFocusedElementID, f.field._accessibilityElementID)
            XCTAssertTrue(f.field.isAccessibilityFocused())
            XCTAssertEqual(host.accessibilityChanges.last, .focus(f.field._accessibilityElementID))
            let tree = f.window.accessibilityTree()
            XCTAssertTrue(element(tree, role: .textField)!.isFocused)
            XCTAssertNil(element(tree, role: .textArea), "the field editor is not an element of its own")
            // The platform moves focus through the provider.
            XCTAssertTrue(f.window.accessibilityFocus(f.slider._accessibilityElementID))
            XCTAssertTrue(f.window.firstResponder === f.slider)
            XCTAssertEqual(NSApp.accessibilityApplicationFocusedUIElement() as? NSView, f.slider)
            // setAccessibilityFocused is the AppKit way to do the same.
            f.grid.setAccessibilityFocused(true)
            XCTAssertTrue(f.window.firstResponder === f.grid)
            f.window.close()
        }
    }

    // MARK: Actions and values

    func testActionsReachTheControls() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let host = hostWindow(f.window)!
            let w = f.window
            XCTAssertTrue(w.accessibilityPerform(.press, on: f.clear._accessibilityElementID))
            XCTAssertEqual(f.actions, ["clearDots:"])
            // Pressing a check box toggles it and reports the value change.
            host.clearAccessibilityChanges()
            XCTAssertTrue(w.accessibilityPerform(.press, on: f.grid._accessibilityElementID))
            XCTAssertEqual(f.grid.state, .off)
            XCTAssertEqual(f.actions.last, "toggleGrid:")
            XCTAssertTrue(host.accessibilityChanges.contains(.value(f.grid._accessibilityElementID)))
            XCTAssertEqual(element(w.accessibilityTree(), role: .checkBox)!.value, .number(0))
            // Setting the value of a check box is a press when it differs.
            XCTAssertTrue(w.accessibilitySetValue(.number(1), on: f.grid._accessibilityElementID))
            XCTAssertEqual(f.grid.state, .on)
            // A slider steps by a tick mark and sends its action.
            XCTAssertTrue(w.accessibilityPerform(.increment, on: f.slider._accessibilityElementID))
            XCTAssertEqual(f.slider.doubleValue, 160, "five tick marks over 40...200: a step of 40")
            XCTAssertEqual(f.actions.last, "sizeChanged:")
            XCTAssertTrue(w.accessibilityPerform(.decrement, on: f.slider._accessibilityElementID))
            XCTAssertTrue(w.accessibilityPerform(.decrement, on: f.slider._accessibilityElementID))
            XCTAssertEqual(f.slider.doubleValue, 80)
            XCTAssertTrue(w.accessibilitySetValue(.number(1000), on: f.slider._accessibilityElementID))
            XCTAssertEqual(f.slider.doubleValue, 200, "clamped to the range")
            // Text goes into the field as if typed, and the action fires as Enter would.
            host.clearAccessibilityChanges()
            XCTAssertTrue(w.accessibilitySetValue(.string("Ada"), on: f.field._accessibilityElementID))
            XCTAssertEqual(f.field.stringValue, "Ada")
            XCTAssertEqual(f.actions.last, "nameEntered:")
            XCTAssertTrue(host.accessibilityChanges.contains(.value(f.field._accessibilityElementID)))
            XCTAssertEqual(element(w.accessibilityTree(), role: .textField)!.value, .string("Ada"))
            // A pop-up picks an item by title.
            XCTAssertTrue(w.accessibilitySetValue(.string("Green"), on: f.colours._accessibilityElementID))
            XCTAssertEqual(f.colours.titleOfSelectedItem, "Green")
            XCTAssertFalse(w.accessibilitySetValue(.string("Purple"), on: f.colours._accessibilityElementID))
            // Unknown ids and a label (no value to set) are refused.
            XCTAssertFalse(w.accessibilityPerform(.press, on: 1_000_000))
            XCTAssertFalse(w.accessibilitySetValue(.string("x"), on: f.prompt._accessibilityElementID))
            // A disabled button refuses the press.
            f.clear.isEnabled = false
            f.actions.removeAll()
            XCTAssertFalse(w.accessibilityPerform(.press, on: f.clear._accessibilityElementID))
            XCTAssertEqual(f.actions, [])
            w.close()
        }
    }

    func testTypingInTheFieldEditorReportsValueChanges() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let host = hostWindow(f.window)!
            _ = f.window.makeFirstResponder(f.field)
            host.clearAccessibilityChanges()
            (f.window.firstResponder as? NSTextView)?.insertText("Hi", replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(f.field.stringValue, "Hi")
            XCTAssertTrue(host.accessibilityChanges.contains(.value(f.field._accessibilityElementID)))
            let field = element(f.window.accessibilityTree(), role: .textField)!
            XCTAssertEqual(field.value, .string("Hi"))
            XCTAssertEqual(field.selectedTextRange, NSRange(location: 2, length: 0), "the caret after the typed text")
            f.window.close()
        }
    }

    // MARK: Structure and name changes

    func testStructureAndNameChangesAreReported() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let host = hostWindow(f.window)!
            host.clearAccessibilityChanges()
            let extra = NSButton(title: "Extra", target: nil, action: nil)
            let windowID = f.window._accessibilityElementID
            f.canvas.addSubview(extra)
            XCTAssertEqual(host.accessibilityChanges, [.structure(windowID), .childAdded(parent: windowID, child: extra._accessibilityElementID)],
                           "the canvas is ignored, so the window's children changed: the event names the new child")
            host.clearAccessibilityChanges()
            extra.removeFromSuperview()
            XCTAssertEqual(host.accessibilityChanges, [.structure(windowID), .childRemoved(parent: windowID, child: extra._accessibilityElementID)])
            host.clearAccessibilityChanges()
            f.clear.isHidden = true
            XCTAssertEqual(host.accessibilityChanges, [.structure(windowID), .childRemoved(parent: windowID, child: f.clear._accessibilityElementID)])
            host.clearAccessibilityChanges()
            // An ignored container brings the elements inside it.
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            let inner = NSButton(checkboxWithTitle: "Inner", target: nil, action: nil)
            box.addSubview(inner)
            f.canvas.addSubview(box)
            XCTAssertEqual(host.accessibilityChanges.last, .childAdded(parent: windowID, child: inner._accessibilityElementID))
            box.removeFromSuperview()
            host.clearAccessibilityChanges()
            f.clear.title = "Wipe"
            XCTAssertEqual(host.accessibilityChanges, [.name(f.clear._accessibilityElementID)])
            host.clearAccessibilityChanges()
            f.window.title = "Renamed"
            XCTAssertEqual(host.accessibilityChanges, [.name(f.window._accessibilityElementID)])
            XCTAssertEqual(f.window.accessibilityTree().title, "Renamed")
            // The AppKit way of saying so for custom views.
            host.clearAccessibilityChanges()
            NSAccessibility.post(element: f.slider, notification: .valueChanged)
            NSAccessibility.post(element: f.window, notification: .focusedWindowChanged)
            XCTAssertEqual(host.accessibilityChanges, [.value(f.slider._accessibilityElementID), .focus(nil)])
            f.window.close()
        }
    }

    // MARK: Tables

    func testTableRowsAreElementsWithIndexAndSelection() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
            let data = Rows()
            let table = NSTableView(frame: .zero)
            let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
            name.width = 120
            table.addTableColumn(name)
            table.dataSource = data
            table.delegate = data
            table.rowHeight = 20
            table.allowsMultipleSelection = true
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            scroll.hasVerticalScroller = true
            scroll.documentView = table
            w.contentView!.addSubview(scroll)
            w.makeKeyAndOrderFront(nil)
            _ = w.makeFirstResponder(table)
            scroll.layoutSubtreeIfNeeded()
            w.display()

            let tree = w.accessibilityTree()
            let area = element(tree, role: .scrollArea)!
            let t = element(tree, role: .table)!
            XCTAssertEqual(tree.parent(of: t.id)?.id, area.id, "the table sits in the scroll area; the clip view is ignored")
            XCTAssertGreaterThanOrEqual(t.children.count, 3)
            XCTAssertEqual(t.children.map(\.role).first, "AXRow")
            XCTAssertEqual(t.children.map(\.index), Array(0..<t.children.count), "rows in order with their indices")
            XCTAssertEqual(t.children[1].label, "Venus", "a row reads as its cells' text")
            XCTAssertEqual(t.children[1].subrole, "AXTableRow")
            XCTAssertEqual(t.children[1].children.map(\.role), ["AXCell"])
            XCTAssertEqual(t.children[1].children[0].children.map(\.role), ["AXStaticText"])
            XCTAssertFalse(t.children[1].isSelected)
            XCTAssertEqual(t.children[1].actions, [.press])
            // Selecting through the provider runs the table's selection.
            let host = hostWindow(w)!
            host.clearAccessibilityChanges()
            XCTAssertTrue(w.accessibilitySetSelected(true, on: t.children[1].id, extending: false))
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1))
            XCTAssertEqual(data.selectionChanges, 1)
            XCTAssertTrue(host.accessibilityChanges.contains(.selection(table._accessibilityElementID)))
            XCTAssertTrue(w.accessibilitySetSelected(true, on: t.children[2].id, extending: true))
            XCTAssertEqual(table.selectedRowIndexes, IndexSet([1, 2]))
            XCTAssertTrue(w.accessibilitySetSelected(false, on: t.children[1].id, extending: true))
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 2))
            let after = element(w.accessibilityTree(), role: .table)!
            XCTAssertEqual(after.children.map(\.isSelected), after.children.indices.map { $0 == 2 })
            XCTAssertEqual((table.accessibilitySelectedRows() ?? []).map { $0.accessibilityIndex() }, [2])
            // Pressing a row selects it on its own.
            XCTAssertTrue(w.accessibilityPerform(.press, on: t.children[0].id))
            XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))
            w.close()
        }
    }

    private final class Rows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let rows = ["Mercury", "Venus", "Earth", "Mars"]
        var selectionChanges = 0
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { rows[row] }
        func tableViewSelectionDidChange(_ notification: Notification) { selectionChanges += 1 }
    }

    // MARK: Keyboard focus

    func testTabMovesFocusBetweenControls() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let host = hostWindow(f.window)!
            XCTAssertTrue(f.window.firstResponder === f.window, "a plain view refuses first responder, so the window has it")
            @MainActor func press(_ key: String, shift: Bool = false) {
                let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: f.window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: 48)!
                NSApp.sendEvent(e)
            }
            host.clearAccessibilityChanges()
            press("\t")
            let first = f.window.firstResponder
            XCTAssertFalse(first === f.window, "Tab left the window")
            XCTAssertTrue(first is NSView && (first as? NSView)?.isAccessibilityElement() == true || first is NSTextView, "Tab lands on a control: \(String(describing: first))")
            XCTAssertEqual(host.accessibilityChanges.last, .focus(f.window.accessibilityFocusedElementID), "the platform hears the focus move")
            var stops: [NSView] = []
            for _ in 0..<6 {
                press("\t")
                if let v = (f.window.firstResponder as? NSView)?._accessibilityFocusTarget { stops.append(v) }
            }
            XCTAssertTrue(stops.contains { $0 === f.clear } && stops.contains { $0 === f.grid } && stops.contains { $0 === f.field } && stops.contains { $0 === f.slider }, "Tab visits the button, check box, field and slider: \(stops.map { type(of: $0) })")
            let before = f.window.firstResponder
            press("\t", shift: true)
            XCTAssertFalse(f.window.firstResponder === before, "Shift-Tab moves back")
            f.window.close()
        }
    }

    // MARK: Tabs and segments (elements that are not views)

    func testTabsAndSegmentsAreVirtualElements() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
            let form = NSTabViewItem(identifier: "form"); form.label = "Form"; form.view = NSView(frame: .zero)
            let table = NSTabViewItem(identifier: "table"); table.label = "Table"
            let page = NSView(frame: .zero)
            page.addSubview(NSButton(title: "On the table page", target: nil, action: nil))
            table.view = page
            tabs.addTabViewItem(form)
            tabs.addTabViewItem(table)
            w.contentView!.addSubview(tabs)
            let seg = NSSegmentedControl(labels: ["Left", "Right"], trackingMode: .selectOne, target: nil, action: nil)
            seg.frame = NSRect(x: 10, y: 250, width: 200, height: 24)
            seg.selectedSegment = 0
            w.contentView!.addSubview(seg)
            w.makeKeyAndOrderFront(nil)
            tabs.layoutSubtreeIfNeeded()

            var tree = w.accessibilityTree()
            let group = element(tree, role: .tabGroup)!
            XCTAssertEqual(group.value, .string("Form"))
            let tabElements = group.children.filter { $0.subrole == "AXTabButton" }
            XCTAssertEqual(tabElements.map(\.label), ["Form", "Table"], "the tabs come first")
            XCTAssertEqual(tabElements.map(\.isSelected), [true, false])
            XCTAssertEqual(tabElements[0].role, "AXRadioButton")
            XCTAssertTrue(tabElements[1].frame.width > 0 && tree.frame.contains(tabElements[1].frame), "a tab has a screen frame inside the window")
            XCTAssertNil(element(tree, role: .button, label: "On the table page"), "only the selected page's views are in the tree")
            // Pressing (or selecting) a tab selects it; the page's views follow.
            XCTAssertTrue(w.accessibilityPerform(.press, on: tabElements[1].id))
            XCTAssertTrue(tabs.selectedTabViewItem === table)
            tree = w.accessibilityTree()
            XCTAssertNotNil(element(tree, role: .button, label: "On the table page"))
            XCTAssertTrue(w.accessibilitySetSelected(true, on: tabElements[0].id, extending: false))
            XCTAssertTrue(tabs.selectedTabViewItem === form)
            XCTAssertEqual(tabElements[1].id, element(w.accessibilityTree(), role: .tabGroup)!.children[1].id, "tab ids are stable across snapshots")
            // Segments.
            let radio = element(tree, role: .radioGroup)!
            XCTAssertEqual(radio.children.map(\.label), ["Left", "Right"])
            XCTAssertEqual(radio.children.map(\.isSelected), [true, false])
            XCTAssertTrue(radio.children[1].frame.minX > radio.children[0].frame.minX)
            XCTAssertTrue(w.accessibilityPerform(.press, on: radio.children[1].id))
            XCTAssertEqual(seg.selectedSegment, 1)
            XCTAssertEqual(element(w.accessibilityTree(), role: .radioGroup)!.children.map(\.isSelected), [false, true])
            XCTAssertTrue(w.accessibilityFocus(radio.children[0].id), "focusing a segment focuses its control")
            XCTAssertTrue(w.firstResponder === seg)
            w.close()
        }
    }

    // MARK: The application

    func testApplicationListsWindowsKeyFirst() {
        MainActor.assumeIsolated {
            let f = Fixture()
            let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            other.title = "Other"
            other.makeKeyAndOrderFront(nil)
            XCTAssertEqual(NSApp.accessibilityRole(), .application)
            let windows = (NSApp.accessibilityWindows() ?? []).compactMap { $0 as? NSWindow }
            XCTAssertTrue(windows.first === other, "the key window comes first")
            XCTAssertTrue(windows.contains { $0 === f.window })
            XCTAssertTrue(NSApp.accessibilityFocusedWindow() as? NSWindow === other)
            XCTAssertTrue(NSApp.accessibilityApplicationFocusedUIElement() as? NSWindow === other, "nothing focused inside: the window itself")
            XCTAssertEqual(f.window.accessibilityParent() as? NSApplication, NSApp)
            other.close()
            f.window.close()
        }
    }

    // MARK: SwiftUI

    private struct Form: View {
        @State var count = 0
        var body: some View {
            VStack {
                Text("Count: \(count)").accessibilityHidden(true)
                Button("Increment") { count += 1 }.accessibilityLabel("Add one").accessibilityIdentifier("add")
                Button(action: { count += 10 }) { HStack { Image(systemName: "plus"); Text("Add ten") } }
                Toggle("Dark", isOn: .constant(true)).accessibilityValue("enabled")
                Text("Plain")
            }
        }
    }

    func testSwiftUIModifiersFeedTheBackingViews() {
        MainActor.assumeIsolated {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Form())
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            let tree = w.accessibilityTree()
            XCTAssertNil(element(tree, role: .staticText, label: nil).flatMap { $0.value == .string("Count: 0") ? $0 : nil }, "accessibilityHidden takes the text out")
            XCTAssertNotNil(tree.flattened.first { $0.value == .string("Plain") }, "an ordinary Text is AXStaticText with its string as value")
            let add = element(tree, role: .button, label: "Add one")!
            XCTAssertEqual(add.title, "Increment", "the AppKit title stays; the label is the modifier's")
            XCTAssertEqual(add.identifier, "add")
            let custom = element(tree, role: .button, label: "Add ten")!
            XCTAssertEqual(custom.children, [], "a custom button reads its label through itself")
            XCTAssertEqual(element(tree, role: .checkBox, label: "Dark")?.value, .string("enabled"))
            // Pressing through the provider runs the SwiftUI actions.
            XCTAssertTrue(w.accessibilityPerform(.press, on: add.id))
            XCTAssertTrue(w.accessibilityPerform(.press, on: custom.id))
            h.layoutSubtreeIfNeeded()
            let countText = _allViews(h).compactMap { $0 as? _TextView }.first { $0.storage.string.hasPrefix("Count") }
            XCTAssertEqual(countText?.storage.string, "Count: 11")
            w.close()
        }
    }
}

extension PlatformAccessibilityElement: Equatable {
    public static func == (a: PlatformAccessibilityElement, b: PlatformAccessibilityElement) -> Bool { a.id == b.id }
}
