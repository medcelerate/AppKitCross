// Core depth, second round (ADR-0038): NSEvent monitors, keyboard translation and the
// type-checked members; NSApplication's legacy sheet, search and target lookups; NSColor
// CMYK, catalog, dynamic, pattern and asset-catalog colours; NSCell's field editor
// lifecycle and stored state; NSTextView undo coalescing and the Format actions. The
// expected values were printed by the real AppKit on macOS 15.

import XCTest
@testable import AppKit

/// A box a Sendable closure can bump (the Linux and Windows toolchains reject mutating a
/// captured var in one).
private final class _Depth2Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.001) -> Bool { abs(a - b) <= tol }

@MainActor
private func makeWindow(_ rect: NSRect = NSRect(x: 100, y: 100, width: 300, height: 200)) -> NSWindow {
    let w = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    return w
}

@MainActor
private func appDefined(_ data1: Int) -> NSEvent {
    NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: data1, data2: 0)!
}

@MainActor
private func key(_ code: UInt16, _ chars: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                     characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
}

final class CoreDepth2EventTests: XCTestCase {
    func testEventTypeMaskFromType() {
        XCTAssertEqual(NSEvent.EventTypeMask(type: .leftMouseDown), .leftMouseDown)
        XCTAssertEqual(NSEvent.EventTypeMask(type: .keyDown), .keyDown)
        XCTAssertEqual(NSEvent.EventTypeMask(type: .applicationDefined), .applicationDefined)
        XCTAssertEqual(NSEvent.EventTypeMask(type: .pressure).rawValue, 1 << 34)
    }

    func testLocalMonitorsSeePostedEventsInOrderAndCanReplaceOrDrop() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let seen = _Depth2Box<[String]>([])
            let a = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { e in seen.value.append("A\(e.data1)"); return appDefined(8) }
            let b = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { e in seen.value.append("B\(e.data1)"); return nil }
            let c = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { e in seen.value.append("C\(e.data1)"); return e }
            let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in seen.value.append("K"); return e }
            app.sendEvent(appDefined(7))
            // macOS 15: A sees the event, B sees what A returned and drops it; C never runs.
            XCTAssertEqual(seen.value, ["A7", "B8"])
            for m in [a, b, c, keys] { NSEvent.removeMonitor(m!) }
            seen.value = []
            app.sendEvent(appDefined(7))
            XCTAssertEqual(seen.value, [], "removed monitors are not called")
            NSEvent.removeMonitor(a!)   // twice: nothing happens
        }
    }

    func testLocalMonitorSeesAnEventPostedToTheQueue() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let seen = _Depth2Box<[Int]>([])
            let m = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { e in seen.value.append(e.data1); return e }
            defer { NSEvent.removeMonitor(m!) }
            app.postEvent(appDefined(42), atStart: false)
            XCTAssertNotNil(app.nextEvent(matching: .applicationDefined, until: nil, inMode: .default, dequeue: false), "nextEvent no longer traps on EventTypeMask(type:)")
            app.sendEvent(app.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true)!)
            XCTAssertEqual(seen.value, [42])
        }
    }

    func testMonitorRemovedByAnEarlierMonitorIsNotCalled() {
        MainActor.assumeIsolated {
            let seen = _Depth2Box<[String]>([])
            let second = _Depth2Box<Any?>(nil)
            let first = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { e in seen.value.append("1"); NSEvent.removeMonitor(second.value!); return e }
            second.value = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { e in seen.value.append("2"); return e }
            NSApplication.shared.sendEvent(appDefined(1))
            XCTAssertEqual(seen.value, ["1"])
            NSEvent.removeMonitor(first!)
        }
    }

    func testGlobalMonitorReceivesWhatTheBackendReports() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let host = Platform.backend as! HostBackend
            let seen = _Depth2Box<[NSEvent.EventType]>([])
            let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { seen.value.append($0.type) }
            XCTAssertEqual(host.globalEventMask, [.keyDown, .leftMouseDown])
            host.globalEventHandler?(key(0, "a"))
            host.globalEventHandler?(appDefined(1))
            XCTAssertEqual(seen.value, [.keyDown], "only the monitor's mask")
            NSEvent.removeMonitor(m!)
            XCTAssertNil(host.globalEventHandler, "the last monitor stops the platform's reporting")
            XCTAssertEqual(host.globalEventMask, [])
        }
    }

    func testCharactersByApplyingModifiersOnTheUSLayout() throws {
        try requireHostBackend("the host backend models Apple's US layout")
        MainActor.assumeIsolated {
            let a = key(0, "a")
            XCTAssertEqual(a.characters(byApplyingModifiers: []), "a")
            XCTAssertEqual(a.characters(byApplyingModifiers: .shift), "A")
            XCTAssertEqual(a.characters(byApplyingModifiers: .option), "\u{E5}")            // å
            XCTAssertEqual(a.characters(byApplyingModifiers: [.shift, .option]), "\u{C5}")  // Å
            XCTAssertEqual(a.characters(byApplyingModifiers: .command), "a", "Command does not change the characters")
            XCTAssertEqual(a.characters(byApplyingModifiers: .control), "\u{1}")
            XCTAssertEqual(a.characters(byApplyingModifiers: .capsLock), "A")
            let one = key(18, "1")
            XCTAssertEqual(one.characters(byApplyingModifiers: .shift), "!")
            XCTAssertEqual(one.characters(byApplyingModifiers: .option), "\u{A1}")          // ¡
            XCTAssertEqual(key(14, "e").characters(byApplyingModifiers: .option), "\u{B4}", "a dead key gives its spacing accent")
            XCTAssertEqual(key(123, "\u{F702}").characters(byApplyingModifiers: .shift), "\u{F702}", "function keys keep their characters")
        }
    }

    func testTabletAndTouchMembersOnAMouseEvent() {
        MainActor.assumeIsolated {
            let e = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            // macOS 15's values for a mouse event that no tablet reported.
            XCTAssertEqual(e.absoluteX, 0); XCTAssertEqual(e.buttonMask, []); XCTAssertEqual(e.deviceID, 0)
            XCTAssertEqual(e.tilt, .zero); XCTAssertEqual(e.tabletID, 0); XCTAssertEqual(e.pointingDeviceType, .unknown)
            XCTAssertEqual(e.uniqueID, 0); XCTAssertFalse(e.isEnteringProximity)
            XCTAssertEqual((e.vendorDefined as? [NSNumber])?.count, 3)
            XCTAssertEqual(e.associatedEventsMask.rawValue, 70)
            let magnify = NSEvent._gestureEvent(type: .magnify, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, magnification: 0.1)
            XCTAssertTrue(magnify.allTouches().isEmpty)
            XCTAssertTrue(magnify.touches(matching: .any, in: nil).isEmpty)
            let pressure = NSEvent._gestureEvent(type: .pressure, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, pressure: 0.5, stage: 1, stageTransition: 0.25)
            XCTAssertEqual(pressure.stage, 1); XCTAssertEqual(pressure.stageTransition, 0.25)
            XCTAssertEqual(pressure.pressureBehavior, .primaryDefault)
        }
    }

    func testClassConstants() {
        XCTAssertEqual(NSEvent.foreverDuration, .greatestFiniteMagnitude)
        XCTAssertFalse(NSEvent.isMouseCoalescingEnabled)
        NSEvent.isMouseCoalescingEnabled = true
        XCTAssertTrue(NSEvent.isMouseCoalescingEnabled)
        NSEvent.isMouseCoalescingEnabled = false
    }

    func testPeriodicEventsArePostedAndStop() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.discardEvents(matching: .periodic, before: nil)
            NSEvent.startPeriodicEvents(afterDelay: 0, withPeriod: 0.01)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            NSEvent.stopPeriodicEvents()
            let e = app.nextEvent(matching: .periodic, until: nil, inMode: .default, dequeue: true)
            XCTAssertEqual(e?.type, .periodic)
            app.discardEvents(matching: .periodic, before: nil)
        }
    }
}

final class CoreDepth2ApplicationTests: XCTestCase {
    func testConstants() {
        MainActor.assumeIsolated {
            XCTAssertEqual(NSApplication.launchIsDefaultUserInfoKey, "NSApplicationLaunchIsDefaultLaunchKey")
            XCTAssertEqual(NSApplication.launchUserNotificationUserInfoKey, "NSApplicationLaunchUserNotificationKey")
            XCTAssertEqual(NSApplication.displayWindowRunLoopOrdering, 600000)
            XCTAssertEqual(NSApplication.resetCursorRectsRunLoopOrdering, 700000)
            XCTAssertEqual(NSApplication.updateWindowsRunLoopOrdering, 500000)
        }
    }

    func testSearchStringMatchesWordPrefixes() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            var found = NSRange(location: 0, length: 0)
            @MainActor func search(_ q: String, _ s: String, _ range: NSRange? = nil) -> Bool {
                app.searchString(q, inUserInterfaceItemString: s, range: range ?? NSRange(location: 0, length: (s as NSString).length), found: &found)
            }
            // macOS 15's answers.
            XCTAssertFalse(search("ell", "Hello World")); XCTAssertEqual(found.location, NSNotFound)
            XCTAssertTrue(search("wor", "Hello World")); XCTAssertEqual(found, NSRange(location: 6, length: 5))
            XCTAssertFalse(search("o w", "Hello World"))
            XCTAssertTrue(search("HELLO", "hello world")); XCTAssertEqual(found, NSRange(location: 0, length: 5))
            XCTAssertFalse(search("", "Hello"))
            XCTAssertTrue(search("lo", "Hello lo")); XCTAssertEqual(found, NSRange(location: 6, length: 2))
            XCTAssertFalse(search("World", "Hello World", NSRange(location: 0, length: 5)))
        }
    }

    func testTargetForAction() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let w = makeWindow()
            XCTAssertTrue(app.target(forAction: Selector(("terminate:"))) as AnyObject? === app)
            XCTAssertTrue(app.target(forAction: Selector(("copy:")), to: w, from: nil) as AnyObject? === w, "an explicit target is returned as is")
            XCTAssertNil(app.target(forAction: Selector(("noSuchAction:"))))
            XCTAssertNil(app.context)
        }
    }

    func testLegacyBeginSheetDeliversDidEndToTheDelegate() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let w = makeWindow()
            w.makeKeyAndOrderFront(nil)
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
            let delegate = NSObject()
            let codes = _Depth2Box<[Int]>([])
            delegate.setActionHandler(for: Selector(("sheetDidEnd:returnCode:contextInfo:"))) { sender in codes.value.append((sender as? NSNumber)?.intValue ?? -1) }
            app.beginSheet(sheet, modalFor: w, modalDelegate: delegate, didEnd: Selector(("sheetDidEnd:returnCode:contextInfo:")), contextInfo: nil)
            XCTAssertTrue(w.attachedSheet === sheet, "the legacy call drives the window's sheet")
            XCTAssertTrue(sheet.isSheet)
            app.endSheet(sheet, returnCode: NSApplication.ModalResponse.OK.rawValue)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            XCTAssertNil(w.attachedSheet)
            XCTAssertEqual(codes.value, [NSApplication.ModalResponse.OK.rawValue])
        }
    }

    func testMakeWindowsPerformAndSearchHandlers() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let w = makeWindow()
            w.orderFront(nil)
            defer { w.orderOut(nil) }
            let hit = _Depth2Box(0)
            w.setActionHandler(for: Selector(("ping:"))) { _ in hit.value += 1 }
            XCTAssertTrue(app.makeWindowsPerform(Selector(("ping:")), inOrder: true) === w)
            XCTAssertEqual(hit.value, 1)
            XCTAssertNil(app.makeWindowsPerform(Selector(("nobodyHandles:")), inOrder: false))
            w.setActionHandler(for: Selector(("ping:")), nil)
            XCTAssertFalse(app.isAutomaticCustomizeTouchBarMenuItemEnabled)
            app.isAutomaticCustomizeTouchBarMenuItemEnabled = true
            XCTAssertTrue(app.isAutomaticCustomizeTouchBarMenuItemEnabled)
            app.isAutomaticCustomizeTouchBarMenuItemEnabled = false
            XCTAssertEqual(app.enabledRemoteNotificationTypes, [])
        }
    }
}

final class CoreDepth2ColorTests: XCTestCase {
    func testCMYKComponentsRoundTrip() {
        let c = NSColor(deviceCyan: 0.2, magenta: 0.4, yellow: 0.6, black: 0.1, alpha: 0.9)
        XCTAssertEqual(c.cyanComponent, 0.2); XCTAssertEqual(c.magentaComponent, 0.4)
        XCTAssertEqual(c.yellowComponent, 0.6); XCTAssertEqual(c.blackComponent, 0.1); XCTAssertEqual(c.alphaComponent, 0.9)
        XCTAssertEqual(c.colorSpaceName, .deviceCMYK)
        XCTAssertEqual(c.numberOfComponents, 5)
        XCTAssertEqual(c.type, .componentBased)
        var cy: CGFloat = 0, m: CGFloat = 0, y: CGFloat = 0, k: CGFloat = 0, a: CGFloat = 0
        c.getCyan(&cy, magenta: &m, yellow: &y, black: &k, alpha: &a)
        XCTAssertEqual([cy, m, y, k, a], [0.2, 0.4, 0.6, 0.1, 0.9])
        XCTAssertEqual(c.description, "NSDeviceCMYKColorSpace 0.2 0.4 0.6 0.1 0.9")
    }

    func testColorSpaceNameConversions() {
        // Naive device formulas (macOS goes through ColorSync, so its numbers differ).
        let rgb = NSColor(deviceRed: 0.8, green: 0.4, blue: 0.2, alpha: 1)
        let cmyk = rgb.usingColorSpaceName(.deviceCMYK)!
        XCTAssertTrue(near(cmyk.blackComponent, 0.2)); XCTAssertTrue(near(cmyk.cyanComponent, 0))
        XCTAssertTrue(near(cmyk.magentaComponent, 0.5)); XCTAssertTrue(near(cmyk.yellowComponent, 0.75))
        let back = cmyk.usingColorSpaceName(.deviceRGB)!
        XCTAssertTrue(near(back.redComponent, 0.8)); XCTAssertTrue(near(back.greenComponent, 0.4)); XCTAssertTrue(near(back.blueComponent, 0.2))
        XCTAssertEqual(NSColor(white: 0.3, alpha: 1).usingColorSpaceName(.deviceCMYK)!.blackComponent, 0.7, accuracy: 0.0001)
        XCTAssertTrue(rgb.usingColorSpaceName(rgb.colorSpaceName) === rgb)
        XCTAssertEqual(rgb.usingColorSpaceName(.deviceWhite)!.colorSpaceName, .calibratedWhite)
        let label = NSColor.labelColor.usingColorSpaceName(.deviceRGB)!
        XCTAssertEqual(label.type, .componentBased)
        XCTAssertNil(NSColor(patternImage: NSImage(size: NSSize(width: 2, height: 2))).usingColorSpaceName(.deviceRGB))
    }

    func testCatalogComponentsAndInit() {
        let label = NSColor.labelColor
        XCTAssertEqual(label.catalogNameComponent, "System")
        XCTAssertEqual(label.colorNameComponent, "labelColor")
        XCTAssertEqual(label.localizedCatalogNameComponent, "Developer")   // macOS 15
        XCTAssertEqual(label.localizedColorNameComponent, "labelColor")
        XCTAssertEqual(label.colorSpaceName, .named)
        let fromCatalog = NSColor(catalogName: "System", colorName: "labelColor")
        XCTAssertEqual(fromCatalog?.colorNameComponent, "labelColor")
        XCTAssertNil(NSColor(catalogName: "System", colorName: "nope"))
        XCTAssertEqual(NSColor(for: .graphiteControlTint).colorNameComponent, "graphiteControlTintColor")
        XCTAssertEqual(NSColor(for: .defaultControlTint).colorNameComponent, "blueControlTintColor")
        XCTAssertTrue(NSColor.supportsSecureCoding)
    }

    func testSystemFillsAndAlternatingRowsFollowTheAppearance() {
        func alpha(_ c: NSColor) -> CGFloat { c.alphaComponent }
        let saved = NSAppearance.current
        defer { NSAppearance.current = saved }
        NSAppearance.current = NSAppearance(named: .aqua)
        XCTAssertEqual(alpha(.systemFill), 0.098, accuracy: 0.001)
        XCTAssertEqual(alpha(.quinarySystemFill), 0.0078, accuracy: 0.001)
        XCTAssertEqual(NSColor.systemFill.redComponent, 0)
        let rows = NSColor.controlAlternatingRowBackgroundColors
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].redComponent, 0.9569, accuracy: 0.001)
        NSAppearance.current = NSAppearance(named: .darkAqua)
        XCTAssertEqual(NSColor.systemFill.redComponent, 1)
        XCTAssertEqual(NSColor.controlAlternatingRowBackgroundColors[1].alphaComponent, 0.0471, accuracy: 0.001)
    }

    func testDynamicColorResolvesUnderTheCurrentAppearance() {
        let saved = NSAppearance.current
        defer { NSAppearance.current = saved }
        let c = NSColor(name: "mine") { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black }
        XCTAssertEqual(c.type, .catalog)
        XCTAssertEqual(c.colorNameComponent, "mine")
        NSAppearance.current = NSAppearance(named: .aqua)
        XCTAssertEqual(c.redComponent, 0)
        NSAppearance.current = NSAppearance(named: .darkAqua)
        XCTAssertEqual(c.redComponent, 1)
        XCTAssertEqual(c.withAlphaComponent(0.5).alphaComponent, 0.5)
    }

    func testPatternColor() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let p = NSColor(patternImage: image)
        XCTAssertEqual(p.type, .pattern)
        XCTAssertEqual(p.colorSpaceName, .pattern)
        XCTAssertTrue(p.patternImage === image)
        XCTAssertEqual(p, NSColor(patternImage: image))
    }

    func testExposureIsStored() {
        if #available(macOS 26.0, *) {
            let c = NSColor(red: 1, green: 0.5, blue: 0, alpha: 1, exposure: 1)
            XCTAssertEqual(c.linearExposure, 2)
            XCTAssertEqual(c.applyingContentHeadroom(1.5).linearExposure, 1.5)
            XCTAssertEqual(c.standardDynamicRange.linearExposure, 1)
            XCTAssertEqual(c.redComponent, 1)
        }
    }

    func testAssetCatalogColorSet() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("depth2-\(UUID().uuidString)")
        let set = root.appendingPathComponent("Resources/Assets.xcassets/Brand.colorset")
        try fm.createDirectory(at: set, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let json = """
        {"colors":[{"idiom":"universal","color":{"color-space":"srgb","components":{"red":"0x80","green":"255","blue":"0.250","alpha":"1.000"}}},
                   {"idiom":"universal","appearances":[{"appearance":"luminosity","value":"dark"}],"color":{"color-space":"gray-gamma-22","components":{"white":"0.900","alpha":"1.000"}}}]}
        """
        try json.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        let bundle = try XCTUnwrap(Bundle(path: root.path))
        let saved = NSAppearance.current
        defer { NSAppearance.current = saved }
        let c = try XCTUnwrap(NSColor(named: "Brand", bundle: bundle))
        NSAppearance.current = NSAppearance(named: .aqua)
        XCTAssertEqual(c.redComponent, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.greenComponent, 1, accuracy: 0.001)
        XCTAssertEqual(c.blueComponent, 0.25, accuracy: 0.001)
        NSAppearance.current = NSAppearance(named: .darkAqua)
        XCTAssertEqual(c.redComponent, 0.9, accuracy: 0.001)
        XCTAssertNil(NSColor(named: "Missing", bundle: bundle))
    }
}

final class CoreDepth2CellTests: XCTestCase {
    func testDefaults() {
        MainActor.assumeIsolated {
            // macOS 15's answers for NSCell() and a text cell.
            let c = NSCell()
            XCTAssertEqual(c.type, .nullCellType)
            XCTAssertTrue(c.allowsUndo); XCTAssertTrue(c.allowsEditingTextAttributes)
            XCTAssertEqual(c.controlTint, .defaultControlTint); XCTAssertFalse(c.importsGraphics)
            XCTAssertFalse(c.sendsActionOnEndEditing); XCTAssertEqual(c.userInterfaceLayoutDirection, .leftToRight)
            XCTAssertFalse(c.wantsNotificationForMarkedText); XCTAssertTrue(c.hasValidObjectValue)
            XCTAssertFalse(NSCell.prefersTrackingUntilMouseUp); XCTAssertNil(NSCell.defaultMenu)
            let t = NSCell(textCell: "hello")
            XCTAssertTrue(t.allowsUndo); XCTAssertFalse(t.allowsEditingTextAttributes)
            var d: Float = 0, i: Float = 0
            t.getPeriodicDelay(&d, interval: &i)
            XCTAssertEqual(d, 0.2); XCTAssertEqual(i, 0.025)
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            let r = NSRect(x: 10, y: 10, width: 40, height: 20)
            XCTAssertEqual(t.focusRingMaskBounds(forFrame: r, in: v), .zero)
            XCTAssertEqual(t.expansionFrame(withFrame: r, in: v), .zero)
            XCTAssertNil(t.fieldEditor(for: v))
            XCTAssertEqual(t.highlightColor(withFrame: r, in: v), .secondarySelectedControlColor)
            XCTAssertNil(t.menu(for: NSEvent(), in: r, of: v))
            let menu = NSMenu(title: "m"); t.menu = menu
            XCTAssertTrue(t.menu(for: NSEvent(), in: r, of: v) === menu)
            XCTAssertEqual(t.draggingImageComponents(withFrame: r, in: v).map(\.key), [.icon, .label])
            XCTAssertEqual(NSImageCell(imageCell: NSImage(size: NSSize(width: 8, height: 8))).draggingImageComponents(withFrame: r, in: v).map(\.key), [.icon])
        }
    }

    func testTakeValueFrom() {
        MainActor.assumeIsolated {
            let src = NSCell(textCell: "3.75"), dst = NSCell(textCell: "")
            dst.takeDoubleValueFrom(src); XCTAssertEqual(dst.objectValue as? Double, 3.75)
            dst.takeIntegerValueFrom(src); XCTAssertEqual(dst.objectValue as? Int, 3)
            dst.takeStringValueFrom(src); XCTAssertEqual(dst.objectValue as? String, "3.75")
            dst.takeObjectValueFrom(src); XCTAssertEqual(dst.objectValue as? String, "3.75")
        }
    }

    func testFieldEditorBeginAndEndWithATextField() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let w = makeWindow()
            let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
            w.contentView!.addSubview(field)
            w.makeKeyAndOrderFront(nil)
            let cell = NSTextFieldCell(textCell: "edit me")
            cell.isEditable = true
            cell.font = NSFont.systemFont(ofSize: 17)
            let editor = w.fieldEditor(true, for: field)!
            let rect = NSRect(x: 2, y: 2, width: 196, height: 20)
            cell.edit(withFrame: rect, in: field, editor: editor, delegate: nil, event: nil)
            // macOS 15: the editor holds the text with the insertion point at the start and is first responder.
            XCTAssertTrue(editor.superview === field)
            XCTAssertEqual(editor.frame, rect)
            XCTAssertEqual(editor.string, "edit me")
            XCTAssertEqual(editor.selectedRange, NSRange(location: 0, length: 0))
            XCTAssertTrue(w.firstResponder === editor)
            XCTAssertTrue(editor.isFieldEditor)
            XCTAssertEqual(editor.font?.pointSize, 17)
            cell.endEditing(editor)
            XCTAssertNil(editor.superview)
            XCTAssertTrue(w.firstResponder === w)
            XCTAssertEqual(editor.string, "")
            XCTAssertEqual(cell.stringValue, "edit me", "ending does not take the editor's text")
            cell.select(withFrame: rect, in: field, editor: editor, delegate: nil, start: 1, length: 3)
            XCTAssertEqual(editor.selectedRange, NSRange(location: 1, length: 3))
            (editor as! NSTextView).insertText("ZZ", replacementRange: editor.selectedRange)
            XCTAssertEqual(editor.string, "eZZ me")
            XCTAssertEqual(cell.stringValue, "edit me")
            cell.endEditing(editor)
        }
    }
}

/// Hands the text view an undo manager that does not group by run-loop pass (each change
/// is its own group, as each keystroke is its own event in an application).
@MainActor
private final class _UndoDelegate: NSObject, NSTextViewDelegate {
    let manager: UndoManager = { let m = UndoManager(); m.groupsByEvent = false; return m }()
    func undoManager(for view: NSTextView) -> UndoManager? { manager }
}
@MainActor private var _undoDelegates: [_UndoDelegate] = []

@MainActor
private func textView(rich: Bool = false) -> (NSTextView, UndoManager, NSWindow) {
        let w = makeWindow()
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        tv.isRichText = rich
        tv.allowsUndo = true
        let delegate = _UndoDelegate()
        _undoDelegates.append(delegate)
        tv.delegate = delegate
        w.contentView!.addSubview(tv)
        _ = w.makeFirstResponder(tv)
        return (tv, tv.undoManager!, w)
}

final class CoreDepth2TextViewTests: XCTestCase {

    func testTypingCoalescesUntilBroken() {
        MainActor.assumeIsolated {
            let (tv, undo, _) = textView()
            XCTAssertFalse(tv.isCoalescingUndo)
            tv.insertText("ab", replacementRange: tv.selectedRange())
            XCTAssertTrue(tv.isCoalescingUndo)
            XCTAssertEqual(undo.undoActionName, "Typing")
            tv.insertText("cd", replacementRange: tv.selectedRange())
            tv.breakUndoCoalescing()
            XCTAssertFalse(tv.isCoalescingUndo)
            tv.insertText("ef", replacementRange: tv.selectedRange())
            tv.deleteBackward(nil)
            XCTAssertTrue(tv.isCoalescingUndo, "Backspace joins the typing step")
            XCTAssertEqual(tv.string, "abcde")
            undo.undo()
            XCTAssertEqual(tv.string, "abcd", "the step after the break")
            XCTAssertFalse(tv.isCoalescingUndo)
            undo.undo()
            XCTAssertEqual(tv.string, "", "the two coalesced insertions together")
            XCTAssertFalse(undo.canUndo)
            undo.redo()
            XCTAssertEqual(tv.string, "abcd")
            undo.redo()
            XCTAssertEqual(tv.string, "abcde")
        }
    }

    func testMovingTheInsertionPointBreaksCoalescing() {
        MainActor.assumeIsolated {
            let (tv, undo, _) = textView()
            tv.insertText("hello", replacementRange: tv.selectedRange())
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            XCTAssertFalse(tv.isCoalescingUndo)
            tv.insertText(">", replacementRange: tv.selectedRange())
            XCTAssertEqual(tv.string, ">hello")
            undo.undo()
            XCTAssertEqual(tv.string, "hello")
            // Backspacing past the start of the step takes the deleted text into it.
            tv.setSelectedRange(NSRange(location: 5, length: 0))
            tv.deleteBackward(nil); tv.deleteBackward(nil)
            XCTAssertEqual(tv.string, "hel")
            undo.undo()
            XCTAssertEqual(tv.string, "hello")
        }
    }

    func testNoUndoWithoutAllowsUndo() {
        MainActor.assumeIsolated {
            let (tv, undo, _) = textView()
            tv.allowsUndo = false
            tv.insertText("x", replacementRange: tv.selectedRange())
            XCTAssertFalse(undo.canUndo)
            XCTAssertFalse(tv.isCoalescingUndo)
        }
    }

    func testFormatActionsChangeTheSelectionAndTypingAttributes() {
        MainActor.assumeIsolated {
            let (tv, undo, w) = textView(rich: true)
            tv.string = "hello world"
            tv.setSelectedRange(NSRange(location: 0, length: 5))
            tv.underline(nil)
            XCTAssertEqual((tv.textStorage!.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber)?.intValue, 1)
            XCTAssertEqual(undo.undoActionName, "Underline")
            undo.undo()
            XCTAssertNil(tv.textStorage!.attribute(.underlineStyle, at: 0, effectiveRange: nil))
            _ = w
            tv.outline(nil)
            XCTAssertEqual((tv.textStorage!.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? NSNumber)?.doubleValue, 3)
            tv.outline(nil)
            XCTAssertNil(tv.textStorage!.attribute(.strokeWidth, at: 0, effectiveRange: nil))
            tv.toggleTraditionalCharacterShape(nil)
            XCTAssertEqual((tv.textStorage!.attribute(.characterShapeAttributeName, at: 0, effectiveRange: nil) as? NSNumber)?.intValue, 1)
            tv.toggleTraditionalCharacterShape(nil)
            XCTAssertEqual((tv.textStorage!.attribute(.characterShapeAttributeName, at: 0, effectiveRange: nil) as? NSNumber)?.intValue, 0)
            if #available(macOS 15.0, *) {
                tv.highlight(nil)
                XCTAssertEqual(tv.textStorage!.attribute(.textHighlightStyle, at: 0, effectiveRange: nil) as? String, "NSTextHighlightStyleDefault")
                XCTAssertEqual(tv.textStorage!.attribute(.textHighlightColorScheme, at: 0, effectiveRange: nil) as? String, "NSTextHighlightColorSchemeDefault")
                tv.highlight(nil)
                XCTAssertNil(tv.textStorage!.attribute(.textHighlightStyle, at: 0, effectiveRange: nil))
            }
            // An empty selection changes the typing attributes.
            tv.setSelectedRange(NSRange(location: 6, length: 0))
            tv.underline(nil)
            XCTAssertEqual((tv.typingAttributes[.underlineStyle] as? NSNumber)?.intValue, 1)
            // changeAttributes: from the font manager keeps the attributes it does not convert.
            tv.setSelectedRange(NSRange(location: 6, length: 5))
            tv.changeAttributes(NSFontManager.shared)
            XCTAssertNotNil(tv.textStorage!.attribute(.font, at: 6, effectiveRange: nil))
        }
    }

    func testEditUndoReachesTheWindowsUndoManager() {
        MainActor.assumeIsolated {
            let w = makeWindow()
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            tv.isRichText = true
            tv.allowsUndo = true
            w.contentView!.addSubview(tv)
            tv.string = "hello"
            tv.setSelectedRange(NSRange(location: 0, length: 5))
            XCTAssertFalse(w.respondsToSelectorAction(Selector(("undo:"))))
            tv.underline(nil)
            XCTAssertTrue(tv.undoManager === w.undoManager)
            XCTAssertTrue(w.respondsToSelectorAction(Selector(("undo:"))))
            XCTAssertTrue(w.performSelectorAction(Selector(("undo:")), with: nil), "Edit > Undo reaches the window's undo manager")
            XCTAssertNil(tv.textStorage!.attribute(.underlineStyle, at: 0, effectiveRange: nil))
            XCTAssertTrue(w.performSelectorAction(Selector(("redo:")), with: nil))
            XCTAssertNotNil(tv.textStorage!.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        }
    }

    func testDocumentBackgroundAndFieldEditorFactory() {
        MainActor.assumeIsolated {
            let (tv, _, _) = textView(rich: true)
            let well = NSColorWell(); well.color = .red
            tv.changeDocumentBackgroundColor(well)
            XCTAssertNotEqual(tv.backgroundColor, .red, "ignored unless allowsDocumentBackgroundColorChange")
            tv.allowsDocumentBackgroundColorChange = true
            tv.changeDocumentBackgroundColor(well)
            XCTAssertEqual(tv.backgroundColor, .red)
            let fe = NSTextView.fieldEditor()
            // macOS 15's field editor.
            XCTAssertTrue(fe.isFieldEditor); XCTAssertTrue(fe.isRichText); XCTAssertEqual(fe.frame, .zero)
            XCTAssertTrue(fe.isEditable); XCTAssertFalse(fe.allowsUndo)
            XCTAssertEqual(tv.layoutOrientation, .horizontal)
            if #available(macOS 15.0, *) {
                XCTAssertEqual(tv.writingToolsBehavior, .default)
                XCTAssertEqual(tv.allowedWritingToolsResultOptions, [])
                XCTAssertEqual(tv.textHighlightAttributes[.foregroundColor] as? NSColor, .controlAccentColor)
            }
            XCTAssertFalse(tv.usesAdaptiveColorMappingForDarkAppearance)
        }
    }

    func testDragImageForSelection() throws {
        try requireHostBackend()
        MainActor.assumeIsolated {
            let (tv, _, _) = textView()
            tv.string = "drag this text"
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            var origin = NSPoint(x: -1, y: -1)
            XCTAssertNil(tv.dragImageForSelection(with: NSEvent(), origin: &origin))
            tv.setSelectedRange(NSRange(location: 5, length: 4))
            let image = tv.dragImageForSelection(with: NSEvent(), origin: &origin)
            XCTAssertNotNil(image)
            XCTAssertGreaterThan(image?.size.width ?? 0, 0)
            XCTAssertGreaterThan(origin.x, 0, "the image starts at the selected word")
        }
    }
}

/// A document whose window holds an undoable text view (Examples/TextEdit since ADR-0038).
private final class _UndoTextDocument: NSDocument {
    var textView: NSTextView?
    override func makeWindowControllers() {
        let w = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 320, height: 200), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let tv = NSTextView(frame: w.contentView!.bounds)
        tv.allowsUndo = true
        w.contentView?.addSubview(tv)
        textView = tv
        addWindowController(NSWindowController(window: w))
    }
}

final class CoreDepth2DocumentUndoTests: XCTestCase {
    func testTypingMarksTheDocumentEditedThroughItsUndoManager() {
        MainActor.assumeIsolated {
            let doc = _UndoTextDocument()
            doc.makeWindowControllers()
            let tv = doc.textView!
            XCTAssertTrue(tv.undoManager === doc.undoManager, "window → window controller → document")
            XCTAssertFalse(doc.isDocumentEdited)
            tv.insertText("hi", replacementRange: tv.selectedRange())
            // The end of the event: the manager closes its run-loop group (groupsByEvent).
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            XCTAssertTrue(doc.isDocumentEdited)
            doc.undoManager?.undo()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            XCTAssertEqual(tv.string, "")
            XCTAssertFalse(doc.isDocumentEdited, "undoing back to the saved text is clean")
            doc.close()
        }
    }
}

/// NSColor's colour-space members over NSColorSpace (PR #78's `_convert`); expected values
/// printed by AppKit on macOS 15.
final class CoreDepth2ColorSpaceTests: XCTestCase {
    private func comps(_ c: NSColor?) -> [CGFloat] {
        guard let c else { return [] }
        var a = [CGFloat](repeating: 0, count: c.numberOfComponents)
        c.getComponents(&a)
        return a
    }
    private func assertNear(_ a: [CGFloat], _ b: [CGFloat], _ tol: CGFloat = 0.003, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, message, line: line)
        for (x, y) in zip(a, b) where abs(x - y) > tol { XCTFail("\(a) is not \(b) \(message)", line: line); return }
    }

    func testConversionsBetweenSpaces() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        assertNear(comps(red.usingColorSpace(.displayP3)), [0.9175, 0.2004, 0.1385, 1])
        XCTAssertTrue(red.usingColorSpace(.displayP3)?.colorSpace === NSColorSpace.displayP3)
        XCTAssertTrue(red.usingColorSpace(.sRGB) === red, "already in the space")
        let p3 = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(p3.redComponent, 1, "components in the colour's own space")
        XCTAssertEqual(p3.colorSpaceName, .custom)
        XCTAssertTrue(p3.colorSpace === NSColorSpace.displayP3)
        assertNear(comps(p3.usingColorSpace(.extendedSRGB)), [1.0931, -0.2268, -0.1501, 1])
        var c: [CGFloat] = [0.2, 0.4, 0.6, 0.5]
        let adobe = NSColor(colorSpace: .adobeRGB1998, components: &c, count: 4)
        assertNear(comps(adobe), [0.2, 0.4, 0.6, 0.5])
        XCTAssertEqual(adobe.numberOfComponents, 4)
        assertNear(comps(adobe.usingColorSpace(.sRGB)), [0, 0.4005, 0.6124, 0.5], 0.01)
        assertNear(comps(NSColor(colorSpace: .displayP3, hue: 0.5, saturation: 1, brightness: 1, alpha: 1)), [0, 1, 1, 1])
        assertNear(comps(NSColor(white: 0.5, alpha: 1).usingColorSpace(.sRGB)), [0.5, 0.5, 0.5, 1], 0.01)
        XCTAssertTrue(NSColor(white: 0.5, alpha: 1).colorSpace === NSColorSpace.genericGamma22Gray)
        XCTAssertTrue(NSColor(deviceCyan: 0, magenta: 0, yellow: 0, black: 0, alpha: 1).colorSpace === NSColorSpace.deviceCMYK)
        XCTAssertNil(NSColor(patternImage: NSImage(size: NSSize(width: 2, height: 2))).usingColorSpace(.sRGB))
        let saved = NSAppearance.current
        defer { NSAppearance.current = saved }
        NSAppearance.current = NSAppearance(named: .aqua)
        let label = NSColor.labelColor.usingColorSpace(.sRGB)
        XCTAssertEqual(label?.type, .componentBased, "a catalog colour resolves under the current appearance")
        assertNear(comps(label), [0, 0, 0, 0.85], 0.01)
    }
}
