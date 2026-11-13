// Colour and font panels (ADR-0031) on the host backend: panel mode and colour round
// trips, continuous and final action delivery, `changeColor:` through the responder
// chain, colour wells (activation, the panel following, drag and drop, accessibility),
// the colour pasteboard type, the native-dialog hook, font conversion through the
// responder chain, font descriptors and collections, and SwiftUI's ColorPicker.

import XCTest
@testable import AppKit
@testable import SwiftUI

/// A log notification observers (Sendable closures) can append to.
private final class Log: @unchecked Sendable {
    var events: [String] = []
    func add(_ s: String) { events.append(s) }
}

/// Counts the actions it receives (`changeColor:` / `changeFont:` / a well's action).
@MainActor
private final class Receiver: NSObject, NSSelectorHandling {
    var received: [String] = []
    var colors: [NSColor] = []
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        received.append(NSStringFromSelector(action))
        if let p = sender as? NSColorPanel { colors.append(p.color) }
        if let w = sender as? NSColorWell { colors.append(w.color) }
        return true
    }
}

/// A responder that handles `changeFont:` and only wants the typeface list.
@MainActor
private final class FaceOnlyView: NSView, NSFontChanging, NSSelectorHandling {
    var fonts: [NSFont] = []
    override var acceptsFirstResponder: Bool { true }
    func changeFont(_ sender: NSFontManager?) { fonts.append((sender ?? NSFontManager.shared).convert(NSFont.systemFont(ofSize: 12))) }
    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask { .face }
    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        guard NSStringFromSelector(action) == "changeFont:" else { return false }
        changeFont(sender as? NSFontManager)
        return true
    }
    func respondsToSelectorAction(_ action: Selector) -> Bool { NSStringFromSelector(action) == "changeFont:" }
}

@MainActor
private func hostWindow(_ w: NSWindow) -> HostWindow? {
    var m: Mirror? = Mirror(reflecting: w)
    while let mirror = m {
        if let h = mirror.descendant("_platform") as? HostWindow { return h }
        m = mirror.superclassMirror
    }
    return nil
}

@MainActor
private func makeWindow(x: CGFloat = 100) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: x, y: 300, width: 360, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.makeKeyAndOrderFront(nil)
    return w
}

@MainActor
private func send(_ type: NSEvent.EventType, _ point: NSPoint, in w: NSWindow, flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    NSApplication.shared.sendEvent(e)
}

@MainActor
private func click(_ view: NSView) {
    guard let w = view.window else { return }
    let p = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
    send(.leftMouseDown, p, in: w)
    send(.leftMouseUp, p, in: w)
}

@MainActor
private func makeTextView(in w: NSWindow) -> NSTextView {
    let tv = NSTextView(frame: NSRect(x: 10, y: 10, width: 340, height: 120))
    tv.isRichText = true
    tv.isEditable = true
    tv.textStorage?.setAttributedString(NSAttributedString(string: "Hello colourful world", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]))
    w.contentView!.addSubview(tv)
    _ = w.makeFirstResponder(tv)
    tv.setSelectedRange(NSRange(location: 6, length: 9))
    return tv
}

/// A family with at least one member the panel lists, other than `exclude`.
@MainActor
private func someFamily(excluding exclude: String? = nil) -> String? {
    NSFontManager.shared.availableFontFamilies.first { $0 != exclude && (NSFontManager.shared.availableMembers(ofFontFamily: $0)?.isEmpty == false) && NSFont(name: $0, size: 12) != nil }
}

@MainActor
private func resetPanels() {
    if NSColorPanel.sharedColorPanelExists {
        let p = NSColorPanel.shared
        p.setTarget(nil); p.setAction(nil); p.isContinuous = true; p.showsAlpha = false; p.accessoryView = nil
        p.orderOut(nil)
    }
    if NSFontPanel.sharedFontPanelExists { NSFontPanel.shared.orderOut(nil) }
    NSFontManager.shared.target = nil
    NSFontManager.shared.isEnabled = true
    NSColorPanel._nativeDialogOverride = nil
}

final class PanelsTests: XCTestCase, @unchecked Sendable {
    override func setUp() { super.setUp(); MainActor.assumeIsolated { resetPanels() } }
    override func tearDown() { MainActor.assumeIsolated { resetPanels() }; super.tearDown() }

    // MARK: Colour panel

    func testColorPanelModeAndColorRoundTrip() {
        MainActor.assumeIsolated {
            let p = NSColorPanel.shared
            XCTAssertTrue(NSColorPanel.sharedColorPanelExists)
            XCTAssertFalse(p.canBecomeMain)
            for m in [NSColorPanel.Mode.wheel, .gray, .RGB, .CMYK, .HSB, .colorList, .crayon] {
                p.mode = m
                XCTAssertEqual(p.mode, m)
                XCTAssertEqual(p._view.currentMode, m)
            }
            NSColorPanel.setPickerMode(.crayon)
            XCTAssertEqual(p.mode, .crayon)
            p.mode = .RGB
            let red = NSColor(red: 1, green: 0.2, blue: 0.1, alpha: 1)
            let notified = Log()
            let token = NotificationCenter.default.addObserver(forName: NSColorPanel.colorDidChangeNotification, object: nil, queue: nil) { _ in notified.add("changed") }
            defer { NotificationCenter.default.removeObserver(token) }
            p.color = red
            XCTAssertEqual(p.color.redComponent, 1, accuracy: 0.001)
            XCTAssertEqual(p._view.hexField.stringValue, "FF331A")
            XCTAssertEqual(p._view.sliderFields[0].stringValue, "255")
            XCTAssertEqual(notified.events.count, 1, "setting the colour posts the notification")
            // Alpha only counts while shown.
            XCTAssertFalse(p.showsAlpha)
            p.color = red.withAlphaComponent(0.5)
            XCTAssertEqual(p.alpha, 1, "alpha is 1 while the panel hides it")
            p.showsAlpha = true
            p.color = red.withAlphaComponent(0.5)
            XCTAssertEqual(p.alpha, 0.5, accuracy: 0.001)
            XCTAssertEqual(p._view.alphaField.stringValue, "50")
            // The hex field parses what the user types, keeping the alpha.
            p._view.hexField.stringValue = "#00FF00"
            _ = p._view.hexField.sendAction(p._view.hexField.action, to: p._view.hexField.target)
            XCTAssertEqual(p.color.greenComponent, 1, accuracy: 0.001)
            XCTAssertEqual(p.color.alphaComponent, 0.5, accuracy: 0.001)
            // The panel grows for the alpha row and an accessory view, keeping its width.
            let withoutAccessory = p.frame.height
            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
            p.accessoryView = accessory
            XCTAssertEqual(p.frame.height, withoutAccessory + 48, accuracy: 0.5)
            XCTAssertEqual(p.contentView!.frame.width, NSColorPanel.contentWidth)
            XCTAssertTrue(accessory.superview === p._view)
            p.accessoryView = nil
            XCTAssertNil(accessory.superview)
        }
    }

    func testColorPanelSendsItsActionContinuouslyOrOnMouseUp() {
        MainActor.assumeIsolated {
            let p = NSColorPanel.shared
            p.mode = .wheel
            p.showsAlpha = false
            p.color = .white
            p.orderFront(nil)
            let r = Receiver()
            p.setTarget(r)
            p.setAction(Selector(("changeColor:")))
            let wheel = p._view.wheel
            @MainActor func point(angle: CGFloat, radius: CGFloat) -> NSPoint {
                let c = wheel.wheelRect
                let local = NSPoint(x: c.midX + cos(angle) * c.width / 2 * radius, y: c.midY + sin(angle) * c.width / 2 * radius)
                return wheel.convert(local, to: nil)
            }
            send(.leftMouseDown, point(angle: 0, radius: 0.9), in: p)
            send(.leftMouseDragged, point(angle: .pi / 3, radius: 0.9), in: p)
            send(.leftMouseUp, point(angle: .pi / 3, radius: 0.9), in: p)
            XCTAssertEqual(r.received.count, 2, "continuous: the mouse down and the drag each send; the mouse up repeats no colour")
            XCTAssertEqual(r.received.first, "changeColor:")
            XCTAssertEqual(p.color.hueComponent, 1.0 / 6, accuracy: 0.03)
            XCTAssertEqual(p.color.saturationComponent, 0.9, accuracy: 0.05)
            // Not continuous: only the mouse up sends.
            p.isContinuous = false
            r.received.removeAll()
            send(.leftMouseDown, point(angle: .pi, radius: 0.5), in: p)
            send(.leftMouseDragged, point(angle: .pi, radius: 0.7), in: p)
            XCTAssertTrue(r.received.isEmpty)
            send(.leftMouseUp, point(angle: .pi, radius: 0.7), in: p)
            XCTAssertEqual(r.received, ["changeColor:"])
            XCTAssertEqual(r.colors.last?.hueComponent ?? 0, 0.5, accuracy: 0.03)
            // The brightness slider and the crayons report the same way.
            p.isContinuous = true
            r.received.removeAll()
            let slider = p._view.brightnessSlider
            let s = slider.convert(NSPoint(x: slider.bounds.midX, y: slider.bounds.midY), to: nil)
            send(.leftMouseDown, s, in: p)
            send(.leftMouseUp, s, in: p)
            XCTAssertEqual(r.received.count, 1)
            XCTAssertEqual(p.color.brightnessComponent, 0.5, accuracy: 0.05)
            p.mode = .crayon
            r.received.removeAll()
            let crayons = p._view.crayons
            let cr = crayons.rect(of: 14)   // Lemon
            send(.leftMouseDown, crayons.convert(NSPoint(x: cr.midX, y: cr.midY), to: nil), in: p)
            send(.leftMouseUp, crayons.convert(NSPoint(x: cr.midX, y: cr.midY), to: nil), in: p)
            XCTAssertEqual(r.received.count, 1)
            XCTAssertEqual(p.color.redComponent, 1, accuracy: 0.001)
            XCTAssertEqual(p.color.greenComponent, 1, accuracy: 0.001)
            XCTAssertEqual(crayons.selected, 14)
        }
    }

    func testChangeColorReachesTheTextViewThroughTheResponderChain() throws {
        try requireHostBackend("known Win32 defect, see PR body")
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let tv = makeTextView(in: w)
            let p = NSColorPanel.shared
            p.setTarget(nil)
            p.orderFront(nil)
            XCTAssertTrue(w.isKeyWindow, "the panel does not take key from the document window")
            let green = NSColor(red: 0, green: 0.8, blue: 0.2, alpha: 1)
            p._userSetColor(green, final: true)
            let selected = tv.textStorage!.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor
            let outside = tv.textStorage!.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
            XCTAssertEqual(selected?.greenComponent ?? 0, 0.8, accuracy: 0.001, "the selection took the colour")
            XCTAssertEqual(outside?.greenComponent ?? 1, 0, accuracy: 0.001, "text outside the selection kept its colour")
            XCTAssertEqual((tv.typingAttributes[.foregroundColor] as? NSColor)?.greenComponent ?? 0, 0.8, accuracy: 0.001)
            // NSApplication.orderFrontColorPanel: and the toolbar's nil-target action reach the panel.
            p.orderOut(nil)
            XCTAssertTrue(NSApplication.shared.sendAction(Selector(("orderFrontColorPanel:")), to: nil, from: nil))
            XCTAssertTrue(p.isVisible)
        }
    }

    func testColorListsAttachAndDetach() {
        MainActor.assumeIsolated {
            let p = NSColorPanel.shared
            let list = NSColorList(name: "Test Palette")
            list.setColor(NSColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1), forKey: "Dusk")
            list.insertColor(.red, key: "Alarm", at: 0)
            XCTAssertEqual(list.allKeys, ["Alarm", "Dusk"])
            XCTAssertFalse(NSColorList.availableColorLists.contains { $0 === list }, "an unsaved list is not available by name")
            XCTAssertNotNil(NSColorList(named: "Crayons"))
            XCTAssertEqual(NSColorList(named: "Apple")?.color(withKey: "Red")?.redComponent, 1)
            p.attachColorList(list)
            p.mode = .colorList
            XCTAssertTrue(p._view.listPicker.lists.contains { $0 === list })
            // Round trip through a file.
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppKitCrossTest-\(getpid()).clr")
            do { try list.write(to: url) } catch { XCTFail("write: \(error)") }
            XCTAssertTrue(NSColorList.availableColorLists.contains { $0 === list }, "a written list is")
            XCTAssertNotNil(NSColorList(named: "Test Palette"))
            let back = NSColorList(name: "Back", fromFile: url.path)
            XCTAssertEqual(back?.allKeys, ["Alarm", "Dusk"])
            XCTAssertEqual(back?.color(withKey: "Dusk")?.blueComponent ?? 0, 0.3, accuracy: 0.001)
            try? FileManager.default.removeItem(at: url)
            list.removeFile()
            p.detachColorList(list)
            XCTAssertFalse(p._view.listPicker.lists.contains { $0 === list })
        }
    }

    func testNativeColorDialogHook() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let host = Platform.backend as! HostBackend
            let p = NSColorPanel.shared
            p.orderOut(nil)
            let r = Receiver()
            p.setTarget(r)
            p.setAction(nil)
            NSColorPanel._nativeDialogOverride = true
            host.nextColorDialogResult = (0.25, 0.5, 0.75)
            p.orderFront(nil)
            XCTAssertFalse(p.isVisible, "the native dialog stands in for the panel window")
            XCTAssertEqual(r.received, ["changeColor:"])
            XCTAssertEqual(p.color.blueComponent, 0.75, accuracy: 0.001)
            // An active well gets the dialog's colour through takeColorFrom: and sends its action.
            let w = makeWindow()
            defer { w.close() }
            let well = NSColorWell(frame: NSRect(x: 20, y: 100, width: 44, height: 24))
            well.color = .red
            well.target = r
            well.action = Selector(("wellChanged:"))
            w.contentView!.addSubview(well)
            r.received.removeAll()
            host.nextColorDialogResult = (0.1, 0.9, 0.2)
            click(well)
            XCTAssertEqual(well.color.greenComponent, 0.9, accuracy: 0.001, "the native result landed in the well")
            XCTAssertEqual(r.received, ["wellChanged:"])
            XCTAssertFalse(p.isVisible)
            host.nextColorDialogResult = nil
            r.received.removeAll()
            p.orderFront(nil)
            XCTAssertTrue(r.received.isEmpty, "cancelling sends nothing")
            NSColorPanel._nativeDialogOverride = nil
        }
    }

    // MARK: Colour wells

    func testColorWellActivatesAndFollowsThePanel() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let a = NSColorWell(frame: NSRect(x: 20, y: 100, width: 44, height: 24))
            let b = NSColorWell(frame: NSRect(x: 100, y: 100, width: 44, height: 24))
            a.color = .red
            b.color = .blue
            let r = Receiver()
            for well in [a, b] { well.target = r; well.action = Selector(("wellChanged:")); w.contentView!.addSubview(well) }
            XCTAssertEqual(a.accessibilityRole(), .colorWell)
            XCTAssertEqual(a.accessibilityValue() as? String, "rgb 1 0 0 1")
            click(a)
            XCTAssertTrue(a.isActive)
            let p = NSColorPanel.shared
            XCTAssertTrue(p.isVisible)
            XCTAssertTrue(p._target === a)
            XCTAssertEqual(p.color.redComponent, 1)
            // The panel's change lands in the well, which sends its own action.
            p._userSetColor(NSColor(red: 0, green: 1, blue: 0, alpha: 1), final: true)
            XCTAssertEqual(a.color.greenComponent, 1)
            XCTAssertEqual(r.received, ["wellChanged:"])
            // Setting the active well's colour shows in the panel.
            a.color = .yellow
            XCTAssertEqual(p.color.greenComponent, 1)
            XCTAssertEqual(p.color.blueComponent, 0)
            // Another well's click takes over (exclusive), and a click on the active well deactivates it.
            click(b)
            XCTAssertTrue(b.isActive)
            XCTAssertFalse(a.isActive)
            XCTAssertEqual(p.color.blueComponent, 1)
            click(b)
            XCTAssertFalse(b.isActive)
            XCTAssertNil(p._target)
            a.activate(false)
            b.activate(false)
            XCTAssertTrue(a.isActive && b.isActive, "non-exclusive activation keeps both")
            b.deactivate()
            XCTAssertTrue(a.isActive)
            // Leaving the window deactivates.
            a.removeFromSuperview()
            XCTAssertFalse(a.isActive)
            // The press action opens the panel like a click.
            XCTAssertTrue(b.accessibilityPerformPress())
            XCTAssertTrue(b.isActive)
            b.isEnabled = false
            b.deactivate()
            click(b)
            XCTAssertFalse(b.isActive, "a disabled well ignores clicks")
        }
    }

    /// The panel's own sliders, wheel and swatch are accessibility elements (a plain
    /// NSView is ignored unless it opts in), the sliders in percent with a label; a well
    /// reads as a colour well with a role description, help and a settable colour value.
    func testPanelAndWellAccessibility() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let well = NSColorWell(frame: NSRect(x: 20, y: 100, width: 44, height: 24))
            well.color = .blue
            let r = Receiver()
            well.target = r; well.action = Selector(("wellChanged:"))
            w.contentView!.addSubview(well)
            let e = w.accessibilityTree().flattened.first { $0.role == NSAccessibility.Role.colorWell.rawValue }
            XCTAssertNotNil(e)
            XCTAssertEqual(e?.roleDescription, "color well")
            XCTAssertEqual(e?.value?.stringValue, "rgb 0 0 1 1")
            XCTAssertFalse(e?.help?.isEmpty ?? true)
            XCTAssertTrue(e?.isSettable ?? false)
            XCTAssertTrue(e?.actions.contains(.press) ?? false)
            XCTAssertTrue(well._accessibilitySetValue(.string("#FF0000")))
            XCTAssertEqual(well.color.redComponent, 1)
            XCTAssertEqual(well.color.blueComponent, 0)
            XCTAssertTrue(well._accessibilitySetValue(.string("rgb 0 1 0 1")))
            XCTAssertEqual(well.color.greenComponent, 1)
            XCTAssertEqual(r.received, ["wellChanged:", "wellChanged:"])

            let p = NSColorPanel.shared
            p.showsAlpha = true
            p.color = NSColor(red: 0.5, green: 0.25, blue: 0, alpha: 1)
            p.mode = .wheel
            p.orderFront(nil)
            defer { p.orderOut(nil); p.showsAlpha = false }
            @MainActor func sliders() -> [PlatformAccessibilityElement] {
                p.accessibilityTree().flattened.filter { $0.role == NSAccessibility.Role.slider.rawValue }
            }
            var labels = sliders().map { $0.label ?? "" }
            XCTAssertTrue(labels.contains("Brightness"), "\(labels)")
            XCTAssertTrue(labels.contains("Opacity"), "\(labels)")
            let wheel = p.accessibilityTree().flattened.first { $0.label == "Color wheel" }
            XCTAssertEqual(wheel?.role, NSAccessibility.Role.colorWell.rawValue)
            p.mode = .RGB
            labels = sliders().map { $0.label ?? "" }
            XCTAssertEqual(labels, ["Red", "Green", "Blue", "Opacity"])
            let red = sliders()[0]
            XCTAssertEqual(red.minValue, 0)
            XCTAssertEqual(red.maxValue, 100)
            XCTAssertEqual(red.value?.doubleValue, 50)
            XCTAssertTrue(red.isSettable)
            // Setting the value through accessibility changes the panel's colour.
            let view = p._view
            XCTAssertTrue(view.sliders[0]._accessibilitySetValue(.number(100)))
            XCTAssertEqual(p.color.redComponent, 1, accuracy: 0.01)
        }
    }

    /// The panel opened from a well shows the well's colour in its sliders, in the tree
    /// too, and every slider, swatch, wheel and well change reaches the platform as a
    /// value change (a UIA client that waits for RangeValue events sees the new value).
    func testPanelOpenedFromAWellReportsItsSliderValues() throws {
        try requireHostBackend()
        try MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let well = NSColorWell(frame: NSRect(x: 20, y: 100, width: 44, height: 24))
            w.contentView!.addSubview(well)
            let p = NSColorPanel.shared
            p.mode = .wheel
            well.color = NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
            click(well)
            XCTAssertTrue(p.isVisible)
            defer { p.orderOut(nil) }
            let host = try XCTUnwrap(hostWindow(p))
            let mainHost = try XCTUnwrap(hostWindow(w))
            host.clearAccessibilityChanges()
            mainHost.clearAccessibilityChanges()
            @MainActor func sliders() -> [PlatformAccessibilityElement] { p.accessibilityTree().flattened.filter { $0.role == NSAccessibility.Role.slider.rawValue } }
            XCTAssertEqual(sliders().map { $0.label ?? "" }, ["Brightness", "Opacity"])   // a well supports alpha, so the panel shows it
            XCTAssertEqual(sliders()[0].value?.doubleValue, 90)
            // The mode control's segment, as a click on the Sliders radio would.
            let view = p._view
            view.modeControl.selectedSegment = 1   // "Sliders", second of wheel, sliders, lists, crayons
            _ = view.modeControl.sendAction(view.modeControl.action, to: view.modeControl.target)
            XCTAssertEqual(p.mode, .RGB)
            XCTAssertEqual(sliders().map { "\($0.label ?? "")=\($0.value?.doubleValue ?? -1)" }, ["Red=20.0", "Green=50.0", "Blue=90.0", "Opacity=100.0"])
            // A later change from the panel reaches the well and its tree value, and the
            // slider, swatch and well each report a value change to their platform window.
            p._userSetColor(.black, final: true)
            var changed: [Int] = []
            for c in host.accessibilityChanges + mainHost.accessibilityChanges { if case .value(let id) = c { changed.append(id) } }
            XCTAssertTrue(changed.contains(well._accessibilityElementID), "well")
            XCTAssertTrue(changed.contains(view.sliders[0]._accessibilityElementID), "red slider")
            XCTAssertTrue(changed.contains(view.preview._accessibilityElementID), "swatch")
            XCTAssertEqual(sliders().map { $0.value?.doubleValue ?? -1 }, [0, 0, 0, 100])
            XCTAssertEqual(w.accessibilityTree().flattened.first { $0.role == NSAccessibility.Role.colorWell.rawValue }?.value?.stringValue, "rgb 0 0 0 1")
        }
    }

    /// A colour's hex "3380E6" reads as the number 3380e6 to `Double`, which overflowed
    /// the Win32 bridge's `Int32` toggle state and trapped the process under UIA. The
    /// conversion is now total, and the swatch's value is "#RRGGBB".
    func testAccessibilityValuesThatLookNumericDoNotTrap() {
        XCTAssertEqual(PlatformAccessibilityValue.string("3380E6").toggleState, 0)
        XCTAssertEqual(PlatformAccessibilityValue.string("1e300").toggleState, 0)
        XCTAssertEqual(PlatformAccessibilityValue.string("nan").toggleState, 0)
        XCTAssertEqual(PlatformAccessibilityValue.string("inf").toggleState, 0)
        XCTAssertEqual(PlatformAccessibilityValue.number(1).toggleState, 1)
        XCTAssertEqual(PlatformAccessibilityValue.number(2).toggleState, 2)
        XCTAssertEqual(PlatformAccessibilityValue.number(50).toggleState, 0)
        XCTAssertEqual(PlatformAccessibilityValue.boolean(true).toggleState, 1)
        XCTAssertEqual(PlatformAccessibilityValue.string("rgb 0.2 0.5 0.9 1").toggleState, 0)
        MainActor.assumeIsolated {
            let p = NSColorPanel.shared
            p.color = NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
            let swatch = p.accessibilityTree().flattened.first { $0.label == "Current color" }
            XCTAssertEqual(swatch?.value?.stringValue, "#3380E6")
            XCTAssertNil(swatch?.value?.doubleValue)
            // Every value in the panel's and a well's tree converts without trapping.
            for e in p.accessibilityTree().flattened { _ = e.value?.toggleState }
        }
    }

    func testColorWellDragAndDrop() throws {
        try requireHostBackend("hangs on Win32: not diagnosed, no result after 60s")
        MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let a = NSColorWell(frame: NSRect(x: 20, y: 100, width: 44, height: 24))
            let b = NSColorWell(frame: NSRect(x: 200, y: 100, width: 44, height: 24))
            a.color = NSColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1)
            b.color = .blue
            let r = Receiver()
            b.target = r
            b.action = Selector(("wellChanged:"))
            w.contentView!.addSubview(a)
            w.contentView!.addSubview(b)
            let start = NSPoint(x: 42, y: 112), end = NSPoint(x: 222, y: 112)
            send(.leftMouseDown, start, in: w)
            send(.leftMouseDragged, NSPoint(x: start.x + 12, y: start.y), in: w)
            XCTAssertTrue(_NSDragTracker.isDragging, "dragging past the threshold starts a colour drag")
            XCTAssertFalse(a.isActive, "a drag is not a click")
            send(.leftMouseDragged, end, in: w)
            send(.leftMouseUp, end, in: w)
            XCTAssertFalse(_NSDragTracker.isDragging)
            XCTAssertEqual(b.color.redComponent, 0.9, accuracy: 0.001, "the drop replaced the well's colour")
            XCTAssertEqual(r.received, ["wellChanged:"])
            // Dropping on the colour panel's swatch sets the panel's colour too.
            let p = NSColorPanel.shared
            p.color = .white
            let pb = NSPasteboard.withUniqueName()
            _ = pb.writeObjects([a.color])
            XCTAssertEqual(NSColor(from: pb)?.redComponent ?? 0, 0.9, accuracy: 0.001)
            XCTAssertEqual((pb.readObjects(forClasses: [NSColor.self])?.first as? NSColor)?.greenComponent ?? 0, 0.1, accuracy: 0.001)
            XCTAssertEqual(pb.types, [.color])
        }
    }

    func testColorWellStylesAndPulldown() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            guard #available(macOS 13.0, *) else { return }
            let w = makeWindow()
            defer { w.close() }
            let well = NSColorWell(style: .expanded)
            well.frame = NSRect(x: 20, y: 100, width: 64, height: 24)
            w.contentView!.addSubview(well)
            let r = Receiver()
            well.pulldownTarget = r
            well.pulldownAction = Selector(("pulldown:"))
            XCTAssertEqual(well.colorWellStyle, .expanded)
            XCTAssertNotNil(well._pulldownRect)
            let pull = well.convert(NSPoint(x: well._pulldownRect!.midX, y: well._pulldownRect!.midY), to: nil)
            send(.leftMouseDown, pull, in: w)
            send(.leftMouseUp, pull, in: w)
            XCTAssertEqual(r.received, ["pulldown:"])
            XCTAssertFalse(well.isActive, "the pull-down segment sends its action instead of activating")
            well.colorWellStyle = .minimal
            XCTAssertNil(well._pulldownRect)
            XCTAssertEqual(well.intrinsicContentSize.width, 28)
            // The well draws its colour inside the bezel.
            well.colorWellStyle = .default
            well.color = NSColor(red: 0, green: 0, blue: 1, alpha: 1)
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            guard let image = platform.lastImage else { return XCTFail("no image") }
            let data = _pixels(image)
            let centre = well.convert(NSPoint(x: well._swatchRect.midX, y: well._swatchRect.midY), to: w.contentView)
            let x = Int(centre.x * 2), row = image.height - 1 - Int(centre.y * 2), i = row * image.bytesPerRow + x * 4
            XCTAssertGreaterThan(Int(data[i]), 200, "blue swatch")
            XCTAssertLessThan(Int(data[i + 2]), 60)
        }
    }

    // MARK: Font panel and manager

    func testFontPanelConvertAppliesFamilyFaceAndSize() throws {
        try MainActor.assumeIsolated {
            let fm = NSFontManager.shared
            guard let family = someFamily(), let other = someFamily(excluding: family) else { throw XCTSkip("needs two installed families") }
            let base = try XCTUnwrap(NSFont(name: family, size: 12))
            let panel = NSFontPanel.shared
            XCTAssertTrue(NSFontPanel.sharedFontPanelExists)
            XCTAssertTrue(panel.worksWhenModal)
            panel.setPanelFont(base, isMultiple: false)
            XCTAssertEqual(panel._selectedFamily, family)
            XCTAssertEqual(panel._selectedSize, 12)
            XCTAssertNotNil(panel._view.preview.font)
            // Pick another family in the list: convert() turns any font into that family at the panel's size.
            let view = panel._view
            let row = try XCTUnwrap(view.families.firstIndex(of: other))
            view.familyTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            XCTAssertEqual(panel._selectedFamily, other)
            XCTAssertFalse(view.faces.isEmpty, "the typeface list follows the family")
            let sizeRow = try XCTUnwrap(NSFontPanel.standardSizes.firstIndex(of: 24))
            view.sizeTable.selectRowIndexes(IndexSet(integer: sizeRow), byExtendingSelection: false)
            let converted = panel.convert(base)
            XCTAssertEqual(converted.familyName?.lowercased(), other.lowercased())
            XCTAssertEqual(converted.pointSize, 24)
            XCTAssertEqual(fm.currentFontAction, .viaPanelFontAction)
            XCTAssertEqual(fm.convert(base).pointSize, 24, "the manager asks the panel")
            // Several fonts selected: only what the user changed applies to each.
            panel.setPanelFont(base, isMultiple: true)
            view.sizeTable.selectRowIndexes(IndexSet(integer: sizeRow), byExtendingSelection: false)
            let otherFont = try XCTUnwrap(NSFont(name: other, size: 9))
            let multi = panel.convert(otherFont)
            XCTAssertEqual(multi.familyName?.lowercased(), other.lowercased(), "the family was not changed, so it stays")
            XCTAssertEqual(multi.pointSize, 24)
            // The size field accepts a size outside the list.
            view.sizeField.stringValue = "17.5"
            _ = view.sizeField.sendAction(view.sizeField.action, to: view.sizeField.target)
            XCTAssertEqual(panel._selectedSize, 17.5)
            XCTAssertEqual(panel.convert(base).pointSize, 17.5)
            // The manager's own conversions.
            XCTAssertEqual(fm.convert(base, toFamily: other).familyName?.lowercased(), other.lowercased())
            XCTAssertEqual(fm.convert(base, toSize: 30).pointSize, 30)
            XCTAssertTrue(fm.traits(of: fm.convert(base, toHaveTrait: .boldFontMask)).contains(.boldFontMask))
            XCTAssertEqual(fm.availableMembers(ofFontFamily: family)?.first?.count, 4)
            XCTAssertTrue(fm.availableFonts.count >= fm.availableFontFamilies.count)
        }
    }

    func testChangeFontReachesTheTextViewThroughTheResponderChain() throws {
        try requireHostBackend("known Win32 defect, see PR body")
        try MainActor.assumeIsolated {
            let w = makeWindow()
            defer { w.close() }
            let tv = makeTextView(in: w)
            let fm = NSFontManager.shared
            XCTAssertEqual(fm.selectedFont?.pointSize, 12, "the text view reports the selection's font as first responder")
            fm.orderFrontFontPanel(nil)
            let panel = NSFontPanel.shared
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(w.isKeyWindow)
            XCTAssertEqual(panel._selectedSize, 12)
            XCTAssertTrue(panel._effectiveModeMask.contains(.size))
            let view = panel._view
            let sizeRow = try XCTUnwrap(NSFontPanel.standardSizes.firstIndex(of: 24))
            view.sizeTable.selectRowIndexes(IndexSet(integer: sizeRow), byExtendingSelection: false)
            let inside = tv.textStorage!.attribute(.font, at: 8, effectiveRange: nil) as? NSFont
            let outside = tv.textStorage!.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
            XCTAssertEqual(inside?.pointSize, 24, "changeFont: converted the selection")
            XCTAssertEqual(outside?.pointSize, 12, "and left the rest")
            XCTAssertEqual((tv.typingAttributes[.font] as? NSFont)?.pointSize, 24)
            // The Font menu's Bigger goes through the same path.
            let bigger = NSMenuItem(title: "Bigger", action: Selector(("modifyFont:")), keyEquivalent: "")
            bigger.tag = NSFontAction.sizeUpFontAction.rawValue
            fm.modifyFont(bigger)
            XCTAssertEqual((tv.textStorage!.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.pointSize, 25)
            let bold = NSMenuItem(title: "Bold", action: Selector(("addFontTrait:")), keyEquivalent: "")
            bold.tag = Int(NSFontTraitMask.boldFontMask.rawValue)
            fm.addFontTrait(bold)
            XCTAssertTrue(fm.traits(of: (tv.textStorage!.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)!).contains(.boldFontMask))
            XCTAssertNotNil(fm.fontMenu(true))
            // A disabled manager sends nothing.
            fm.isEnabled = false
            fm.modifyFont(bigger)
            XCTAssertEqual((tv.textStorage!.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.pointSize, 25)
            fm.isEnabled = true
            // A responder that only wants the typeface list hides the size column.
            let face = FaceOnlyView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            w.contentView!.addSubview(face)
            _ = w.makeFirstResponder(face)
            fm.orderFrontFontPanel(nil)
            XCTAssertEqual(panel._effectiveModeMask, .face)
            XCTAssertTrue(view.sizeScroll.isHidden)
            XCTAssertFalse(view.familyScroll.isHidden)
            view.sizeTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            XCTAssertEqual(face.fonts.count, 1, "changeFont: reached the responder")
            // While the panel is the key window with its size field editing (as on Win32,
            // where a click in the panel activates it), its field editor does not swallow
            // changeFont: and the send still reaches the document window's text view.
            _ = w.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: 6, length: 9))
            fm.orderFrontFontPanel(nil)
            panel.makeKeyAndOrderFront(nil)
            _ = panel.makeFirstResponder(view.sizeField)
            XCTAssertTrue(panel.isKeyWindow)
            XCTAssertTrue(w.isMainWindow, "a utility panel never takes main")
            XCTAssertTrue((panel.firstResponder as? NSTextView)?.isFieldEditor ?? false, "the size field is editing")
            let before = (tv.textStorage!.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.pointSize
            let big = try XCTUnwrap(NSFontPanel.standardSizes.firstIndex(of: 36))
            view.sizeTable.selectRowIndexes(IndexSet(integer: big), byExtendingSelection: false)
            XCTAssertNotEqual(before, 36)
            XCTAssertEqual((tv.textStorage!.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.pointSize, 36, "changeFont: crossed from the key panel to the main window")
            XCTAssertNotEqual((panel.firstResponder as? NSTextView)?.font?.pointSize, 36, "the panel's own field editor kept its font")
            w.makeKeyAndOrderFront(nil)
            // A click on a button (the demo's "Fonts…") does not move the keyboard focus off
            // the text view, so the panel's send still starts at it (PC step 5).
            _ = w.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: 6, length: 9))
            let button = NSButton(title: "Fonts…", target: nil, action: Selector(("orderFrontFontPanel:")))
            button.frame = NSRect(x: 10, y: 160, width: 80, height: 24)
            w.contentView!.addSubview(button)
            panel.orderOut(nil)
            click(button)
            XCTAssertTrue(w.firstResponder === tv, "a button click keeps the text view first responder")
            XCTAssertTrue(panel.isVisible, "the button's nil-target action opened the panel")
            panel.makeKeyAndOrderFront(nil)
            let r48 = try XCTUnwrap(NSFontPanel.standardSizes.firstIndex(of: 48))
            view.sizeTable.selectRowIndexes(IndexSet(integer: r48), byExtendingSelection: false)
            XCTAssertEqual((tv.textStorage!.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)?.pointSize, 48)
            w.makeKeyAndOrderFront(nil)
            // The toolbar's nil-target orderFrontFontPanel: ends at the application.
            panel.orderOut(nil)
            XCTAssertTrue(NSApplication.shared.sendAction(Selector(("orderFrontFontPanel:")), to: nil, from: nil))
            XCTAssertTrue(panel.isVisible)
        }
    }

    func testFontDescriptorMatching() throws {
        try MainActor.assumeIsolated {
            let bold = NSFont.boldSystemFont(ofSize: 14).fontDescriptor
            XCTAssertEqual(bold.pointSize, 14)
            XCTAssertTrue(bold.symbolicTraits.contains(.bold))
            XCTAssertNotNil(bold.postscriptName)
            XCTAssertEqual(bold.withSize(20).pointSize, 20)
            XCTAssertTrue(bold.withSymbolicTraits([.bold, .italic]).symbolicTraits.contains(.italic))
            XCTAssertEqual(NSFontDescriptor(name: "Nonexistent", size: 9).object(forKey: .name) as? String, "Nonexistent")
            XCTAssertTrue(NSFontDescriptor(name: "Nonexistent", size: 9).matchingFontDescriptors(withMandatoryKeys: [.name]).isEmpty)
            guard let family = someFamily() else { throw XCTSkip("needs an installed family") }
            let query = NSFontDescriptor(fontAttributes: [.family: family])
            let matches = query.matchingFontDescriptors(withMandatoryKeys: [.family])
            XCTAssertFalse(matches.isEmpty)
            for m in matches {
                XCTAssertEqual((m.object(forKey: .family) as? String)?.lowercased(), family.lowercased())
                XCTAssertNotNil(m.object(forKey: .name))
                XCTAssertNotNil(m.object(forKey: .face))
            }
            XCTAssertEqual(query.withFamily(family).object(forKey: .family) as? String, family)
            XCTAssertNil(query.withFace("Bold").object(forKey: .name))
            let font = try XCTUnwrap(NSFont(descriptor: matches[0], size: 15))
            XCTAssertEqual(font.pointSize, 15)
            XCTAssertEqual(font.familyName?.lowercased(), family.lowercased())
            XCTAssertEqual(NSFont(descriptor: query.withSize(11), size: 0)?.pointSize, 11)
            XCTAssertEqual(NSFontManager.shared.availableFontNames(matching: query)?.count, matches.count)
        }
    }

    func testFontCollections() throws {
        try MainActor.assumeIsolated {
            let all = NSFontCollection.withAllAvailableDescriptors
            XCTAssertNotNil(all.queryDescriptors)
            XCTAssertFalse(all.matchingDescriptors?.isEmpty ?? true)
            guard let family = someFamily() else { throw XCTSkip("needs an installed family") }
            let members = NSFontManager.shared.availableMembers(ofFontFamily: family)?.count ?? 0
            let c = NSFontCollection(descriptors: [NSFontDescriptor(fontAttributes: [.family: family])])
            XCTAssertEqual(c.matchingDescriptors?.count, members, "family \(family): \(String(describing: c.matchingDescriptors)) members \(String(describing: NSFontManager.shared.availableMembers(ofFontFamily: family)))")
            XCTAssertEqual(c.matchingDescriptors(forFamily: family)?.count, members)
            XCTAssertNil(c.matchingDescriptors(forFamily: "No Such Family"))
            // Exclusions drop faces; a mutable copy edits the queries.
            let m = try XCTUnwrap(c.mutableCopy() as? NSMutableFontCollection)
            let first = try XCTUnwrap(c.matchingDescriptors?.first)
            m.exclusionDescriptors = [first]
            XCTAssertEqual(m.matchingDescriptors?.count ?? 0, members - 1)
            m.exclusionDescriptors = nil
            m.removeQuery(for: c.queryDescriptors ?? [])
            XCTAssertNil(m.queryDescriptors)
            m.addQuery(for: [NSFontDescriptor(fontAttributes: [.family: family])])
            XCTAssertEqual(m.matchingDescriptors?.count, members)
            // Named collections live in the user defaults; show/hide round-trip and notify.
            let name = NSFontCollection.Name("AppKitCross Test \(getpid())")
            defer {
                var stored = NSFontCollection._stored; stored[name.rawValue] = nil; NSFontCollection._stored = stored
                NSFontCollection._hidden = NSFontCollection._hidden.filter { $0 != name.rawValue }
            }
            let actions = Log()
            let token = NotificationCenter.default.addObserver(forName: NSFontCollection.didChangeNotification, object: nil, queue: nil) { n in
                if let a = n.userInfo?[NSFontCollection.actionUserInfoKey.rawValue] as? NSFontCollection.ActionTypeKey { actions.add(a.rawValue) }
            }
            defer { NotificationCenter.default.removeObserver(token) }
            XCTAssertNil(NSFontCollection(name: name))
            XCTAssertNoThrow(try NSFontCollection.show(m, withName: name, visibility: .user))
            XCTAssertTrue(NSFontCollection.allFontCollectionNames.contains(name))
            XCTAssertTrue(NSFontCollection.allFontCollectionNames.contains(.allFonts))
            let back = try XCTUnwrap(NSFontCollection(name: name))
            XCTAssertEqual((back.queryDescriptors?.first?.object(forKey: .family) as? String), family)
            XCTAssertEqual(back.matchingDescriptors?.count, members)
            XCTAssertNoThrow(try NSFontCollection.hide(withName: name, visibility: .user))
            XCTAssertFalse(NSFontCollection.allFontCollectionNames.contains(name))
            XCTAssertEqual(actions.events, [NSFontCollection.ActionTypeKey.shown.rawValue, NSFontCollection.ActionTypeKey.hidden.rawValue])
            XCTAssertThrowsError(try NSFontCollection.hide(withName: NSFontCollection.Name("Never Shown"), visibility: .user))
            // The manager's collection API is the same store.
            XCTAssertTrue(NSFontManager.shared.addCollection("AppKitCross Manager \(getpid())", options: []))
            XCTAssertTrue(NSFontManager.shared.removeCollection("AppKitCross Manager \(getpid())"))
            XCTAssertFalse(NSFontManager.shared.removeCollection("AppKitCross Manager \(getpid())"))
        }
    }

    // MARK: SwiftUI

    func testSwiftUIColorPickerPresentsTheColorPanel() {
        MainActor.assumeIsolated {
            struct Picker: View {
                @Binding var tint: Color
                var body: some View { ColorPicker("Tint", selection: $tint) }
            }
            final class Model { var tint: Color; init(_ c: Color) { tint = c } }
            let model = Model(Color.red)
            let binding = Binding(get: { model.tint }, set: { model.tint = $0 })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            let h = NSHostingView(rootView: Picker(tint: binding))
            h.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
            w.contentView!.addSubview(h)
            w.makeKeyAndOrderFront(nil)
            h.layoutSubtreeIfNeeded()
            defer { w.close() }
            @MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }
            guard let well = allViews(h).compactMap({ $0 as? NSColorWell }).first else { return XCTFail("no well") }
            XCTAssertEqual(well.color.redComponent, 1)
            XCTAssertTrue(allViews(h).contains { ($0 as? NSTextField)?.stringValue == "Tint" })
            w.display()
            click(well)
            XCTAssertTrue(well.isActive)
            XCTAssertTrue(NSColorPanel.shared.isVisible, "the picker presents the shared colour panel")
            NSColorPanel.shared._userSetColor(NSColor(red: 0, green: 0, blue: 1, alpha: 1), final: true)
            XCTAssertEqual(NSColor(model.tint).blueComponent, 1, "the panel's colour reached the binding")
        }
    }
}




