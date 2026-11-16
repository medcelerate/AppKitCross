// Core depth, third round (ADR-0039): NSFont glyph metrics and user fonts, NSResponder key
// bindings and defaults, NSButton image layout and compression, NSMenu selection and
// palettes, NSScreen refresh, NSWorkspace volumes, NSGraphicsContext bitmap contexts,
// NSBezierPath (close, reversal, flattening, tangent arcs, glyphs, archives), NSLayoutManager
// manual layout, NSText RTF, and the NSCoding round trips. Expected values were printed by
// the real AppKit on macOS 15.

import XCTest
@testable import AppKit

private func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.001) -> Bool { abs(a - b) <= tol }

private func elements(_ p: NSBezierPath) -> String {
    var out: [String] = []
    let pts = NSPointArray.allocate(capacity: 3)
    defer { pts.deallocate() }
    func f(_ v: CGFloat) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.3g", Double(v)) }
    for i in 0..<p.elementCount {
        switch p.element(at: i, associatedPoints: pts) {
        case .moveTo: out.append("M\(f(pts[0].x)),\(f(pts[0].y))")
        case .lineTo: out.append("L\(f(pts[0].x)),\(f(pts[0].y))")
        case .cubicCurveTo: out.append("C\(f(pts[2].x)),\(f(pts[2].y))")
        case .quadraticCurveTo: out.append("Q\(f(pts[1].x)),\(f(pts[1].y))")
        case .closePath: out.append("Z")
        @unknown default: out.append("?")
        }
    }
    return out.joined(separator: " ")
}

private func roundTrip<T: NSObject & NSCoding>(_ object: T) throws -> T {
    let archiver = NSKeyedArchiver(requiringSecureCoding: false)
    archiver.encode(object, forKey: "root")
    archiver.finishEncoding()
    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
    unarchiver.requiresSecureCoding = false
    return try XCTUnwrap(unarchiver.decodeObject(forKey: "root") as? T)
}

final class CoreDepth3FontTests: XCTestCase {
    func testMatrixAndIdentity() {
        MainActor.assumeIsolated {
            let f = NSFont.systemFont(ofSize: 12)
            XCTAssertEqual((0..<6).map { f.matrix[$0] }, [12, 0, 0, 12, 0, 0])
            XCTAssertEqual((0..<6).map { NSFont.identityMatrix[$0] }, [1, 0, 0, 1, 0, 0])
        }
    }
    func testPreferredFontSizes() {
        MainActor.assumeIsolated {
            let sizes: [(NSFont.TextStyle, CGFloat)] = [(.largeTitle, 26), (.title1, 22), (.title2, 17), (.title3, 15), (.headline, 13),
                                                       (.subheadline, 11), (.body, 13), (.callout, 12), (.footnote, 10), (.caption1, 10), (.caption2, 10)]
            for (style, size) in sizes { XCTAssertEqual(NSFont.preferredFont(forTextStyle: style).pointSize, size, "\(style)") }
        }
    }
    func testPrinterScreenVerticalAreTheFont() {
        MainActor.assumeIsolated {
            let f = NSFont.systemFont(ofSize: 12)
            XCTAssertTrue(f.printer === f)
            XCTAssertTrue(f.screen === f)
            XCTAssertTrue(f.vertical === f)
            XCTAssertFalse(f.vertical.isVertical)
        }
    }
    func testUserFontDefaults() throws {
        try MainActor.assumeIsolated {
            NSFont.setUser(nil)
            XCTAssertEqual(NSFont.userFont(ofSize: 0)?.pointSize, 12)
            XCTAssertEqual(NSFont.userFixedPitchFont(ofSize: 0)?.pointSize, 11)
            let f = try XCTUnwrap(NSFont.userFont(ofSize: 15))
            NSFont.setUser(f)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "NSFont"), f.fontName)
            XCTAssertEqual(UserDefaults.standard.double(forKey: "NSFontSize"), 15)
            XCTAssertEqual(NSFont.userFont(ofSize: 0)?.pointSize, 15)
            NSFont.setUser(nil)
            XCTAssertNil(UserDefaults.standard.object(forKey: "NSFontSize").flatMap { ($0 as? NSNumber)?.doubleValue == 15 ? $0 : nil })
        }
    }
    #if os(macOS)
    func testGlyphMetricsMatchCoreText() throws {
        try MainActor.assumeIsolated {
            let f = try XCTUnwrap(NSFont(name: "Helvetica", size: 12))
            XCTAssertEqual(f.numberOfGlyphs, 2252)
            XCTAssertEqual(f.glyph(withName: "A"), 36)
            XCTAssertEqual(f.glyph(withName: "bogusname"), 0)
            XCTAssertTrue(near(f.advancement(forGlyph: 36).width, 8.00390625))
            let r = f.boundingRect(forGlyph: 36)
            XCTAssertTrue(near(r.minX, 0.17578125) && near(r.width, 7.681640625) && near(r.height, 8.607421875))
            XCTAssertEqual(f.advancement(forGlyph: 99999), .zero)
            XCTAssertEqual(f.boundingRect(forGlyph: 99999), .zero)
            XCTAssertTrue(f.coveredCharacterSet.contains("A"))
            var adv = [NSSize](repeating: .zero, count: 2)
            let packed: [UInt8] = [0, 36, 0, 36]
            packed.withUnsafeBytes { f.getAdvancements(&adv, forPackedGlyphs: $0.baseAddress!, length: 4) }
            XCTAssertTrue(near(adv[1].width, 8.00390625))
        }
    }
    #endif
}

final class CoreDepth3ResponderTests: XCTestCase {
    func testDefaults() {
        MainActor.assumeIsolated {
            let r = NSResponder()
            XCTAssertNil(r.makeTouchBar())
            XCTAssertNil(r.touchBar)
            XCTAssertNil(r.validRequestor(forSendType: .string, returnType: nil))
            XCTAssertFalse(r.wantsForwardedScrollEvents(for: .horizontal))
            XCTAssertFalse(r.wantsScrollEventsForSwipeTracking(on: .horizontal))
            XCTAssertTrue(NSResponder.restorableStateKeyPaths.isEmpty)
            XCTAssertTrue(NSResponder.allowedClasses(forRestorableStateKeyPath: "x").isEmpty)
        }
    }
    func testInterpretKeyEventsReachesTextView() throws {
        try MainActor.assumeIsolated {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            let plain = NSResponder()
            plain.nextResponder = tv
            let e = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                   characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
            plain.interpretKeyEvents([e])
            XCTAssertEqual(tv.string, "x")
            tv.interpretKeyEvents([e, e])
            XCTAssertEqual(tv.string, "xxx")
            let left = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                      characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}", isARepeat: false, keyCode: 123))
            tv.interpretKeyEvents([left])
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 0))
        }
    }
}

final class CoreDepth3ButtonTests: XCTestCase {
    func testCompressionOptions() {
        MainActor.assumeIsolated {
            let a = NSUserInterfaceCompressionOptions.hideText
            XCTAssertEqual(a, NSUserInterfaceCompressionOptions(identifier: "NSUserInterfaceCompressionOptionHideText"))
            XCTAssertTrue(NSUserInterfaceCompressionOptions.standardOptions.contains(.hideImages))
            XCTAssertTrue(NSUserInterfaceCompressionOptions().isEmpty)
            XCTAssertTrue(a.union(.hideImages).intersects(.hideImages))
            XCTAssertTrue(a.union(.hideImages).subtracting(.hideImages) == a)
        }
    }
    func testImageLayoutAndCompression() throws {
        try MainActor.assumeIsolated {
            let image = NSImage(size: NSSize(width: 16, height: 16))
            let b = NSButton(title: "Hello there", image: image, target: nil, action: nil)
            b.imagePosition = .imageLeft
            let full = b.intrinsicContentSize
            let textOnly = b.minimumSize(withPrioritizedCompressionOptions: [.hideImages])
            let imageOnly = b.minimumSize(withPrioritizedCompressionOptions: [.hideText])
            XCTAssertLessThan(imageOnly.width, textOnly.width)
            XCTAssertLessThan(textOnly.width, full.width)
            XCTAssertEqual(b.minimumSize(withPrioritizedCompressionOptions: []), full)
            // Both: the first applies, the second would leave nothing (macOS 15).
            b.compress(withPrioritizedCompressionOptions: [.hideText, .hideImages])
            XCTAssertEqual(b.activeCompressionOptions, .hideText)
            XCTAssertEqual(b.intrinsicContentSize, imageOnly)
            b.compress(withPrioritizedCompressionOptions: [])
            XCTAssertTrue(b.activeCompressionOptions.isEmpty)
            let text = NSButton(title: "Text only", target: nil, action: nil)
            XCTAssertEqual(text.minimumSize(withPrioritizedCompressionOptions: [.hideText]), text.intrinsicContentSize)
            let cell = try XCTUnwrap(b.cell as? NSButtonCell)
            let rects = cell._imageAndTitleRects(in: NSRect(x: 0, y: 0, width: 200, height: 30), flipped: true)
            XCTAssertLessThan(rects.image.maxX, rects.title.minX + 1)
            b.imagePosition = .imageRight
            let right = cell._imageAndTitleRects(in: NSRect(x: 0, y: 0, width: 200, height: 30), flipped: true)
            XCTAssertGreaterThan(right.image.minX, right.title.minX)
        }
    }
    func testStoredMembers() {
        MainActor.assumeIsolated {
            let b = NSButton(title: "OK", target: nil, action: nil)
            XCTAssertEqual(b.attributedAlternateTitle.length, 0)
            b.alternateTitle = "Alt"
            XCTAssertEqual(b.attributedAlternateTitle.string, "Alt")
            XCTAssertEqual((b.attributedAlternateTitle.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineBreakMode, .byTruncatingTail)
            XCTAssertFalse(b.isSpringLoaded)
            XCTAssertEqual(b.maxAcceleratorLevel, 1)
            b.maxAcceleratorLevel = 0
            XCTAssertEqual(b.maxAcceleratorLevel, 1)
            b.maxAcceleratorLevel = 3
            XCTAssertEqual(b.maxAcceleratorLevel, 3)
            b.contentTintColor = .red
            XCTAssertEqual(b.contentTintColor, .red)
            let cell = b.cell as! NSButtonCell
            XCTAssertEqual(cell.gradientType, NSButton.GradientType.none)
            XCTAssertEqual(cell.keyEquivalentFont?.pointSize, 13)
        }
    }
}

final class CoreDepth3MenuTests: XCTestCase {
    func testSelectionModes() {
        MainActor.assumeIsolated {
            let m = NSMenu(title: "")
            let a = m.addItem(withTitle: "a", action: nil, keyEquivalent: "")
            let b = m.addItem(withTitle: "b", action: nil, keyEquivalent: "")
            XCTAssertEqual(m.selectionMode, .automatic)
            XCTAssertEqual(m.presentationStyle, .regular)
            XCTAssertFalse(m.menuChangedMessagesEnabled)
            a.state = .on
            XCTAssertTrue(m.selectedItems == [a])
            m.selectionMode = .selectOne
            m.selectedItems = [a, b]
            XCTAssertEqual(a.state, .off)
            XCTAssertEqual(b.state, .on)
            m.performActionForItem(at: 0)
            XCTAssertEqual(a.state, .on)
            XCTAssertEqual(b.state, .off)
        }
    }
    func testPalette() {
        MainActor.assumeIsolated {
            var changes = 0
            let p = NSMenu.palette(colors: [.red, .blue], titles: ["Red"]) { _ in changes += 1 }
            XCTAssertEqual(p.numberOfItems, 2)
            XCTAssertEqual(p.presentationStyle, .palette)
            XCTAssertEqual(p.selectionMode, .selectAny)
            XCTAssertEqual(p.item(at: 0)?.title, "Red")
            XCTAssertEqual(p.item(at: 1)?.title, "")
            p.performActionForItem(at: 1)
            XCTAssertEqual(p.item(at: 1)?.state, .on)
            XCTAssertEqual(changes, 1)
        }
    }
    func testItems() {
        MainActor.assumeIsolated {
            let h = NSMenuItem.sectionHeader(title: "Sec")
            XCTAssertTrue(h.isSectionHeader)
            XCTAssertTrue(h.isEnabled)
            XCTAssertNil(h.action)
            let i = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            i.setTitleWithMnemonic("Sa&ve && Quit")
            XCTAssertEqual(i.title, "Save && Quit")
            XCTAssertEqual(NSMenuItem(title: "X", action: nil, keyEquivalent: "x").userKeyEquivalent, "")
            if #available(macOS 15.2, *) { XCTAssertTrue(NSMenuItem.writingToolsItems.isEmpty) }
        }
    }
}

final class CoreDepth3ScreenWorkspaceTests: XCTestCase {
    func testScreen() throws {
        try MainActor.assumeIsolated {
            let s = try XCTUnwrap(NSScreen.main)
            XCTAssertEqual(s.maximumFramesPerSecond, 60)
            XCTAssertTrue(near(s.minimumRefreshInterval, 1.0 / 60))
            XCTAssertEqual(s.minimumRefreshInterval, s.maximumRefreshInterval)
            XCTAssertEqual(s.depth, .twentyfourBitRGB)
            XCTAssertNil(s.auxiliaryTopLeftArea)
            XCTAssertFalse(NSScreen.screensHaveSeparateSpaces)
            let d = s.deviceDescription
            XCTAssertEqual(d[.isScreen] as? String, "YES")
            XCTAssertEqual((d[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? NSNumber)?.intValue, 1)
        }
    }
    func testWorkspaceVolumes() throws {
        try requireHostBackend("uses the host workspace's volume hooks")
        try MainActor.assumeIsolated {
            let host = HostWorkspace.shared
            host.reset()
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cd3-volume-\(ProcessInfo.processInfo.processIdentifier)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir); host.reset() }
            host.removableVolumes = [dir.path]
            let ws = NSWorkspace.shared
            XCTAssertEqual(ws.mountedRemovableMedia() as? [String], [dir.path])
            var removable: ObjCBool = false, writable: ObjCBool = false, unmountable: ObjCBool = false
            var desc: NSString? = nil, type: NSString? = nil
            XCTAssertTrue(ws.getFileSystemInfo(forPath: dir.path, isRemovable: &removable, isWritable: &writable, isUnmountable: &unmountable, description: &desc, type: &type))
            XCTAssertTrue(removable.boolValue && writable.boolValue && unmountable.boolValue)
            XCTAssertEqual(type, "hostfs")
            XCTAssertFalse(ws.getFileSystemInfo(forPath: "/nonexistent/x", isRemovable: nil, isWritable: nil, isUnmountable: nil, description: nil, type: nil))
            XCTAssertTrue(ws.unmountAndEjectDevice(atPath: dir.path))
            XCTAssertEqual(host.ejectedVolumes.map(\.path), [dir.path])
            XCTAssertThrowsError(try ws.unmountAndEjectDevice(at: URL(fileURLWithPath: "/nonexistent"))) { e in
                XCTAssertEqual((e as NSError).code, -36)
            }
            XCTAssertTrue(ws.showSearchResults(forQueryString: "report"))
            XCTAssertEqual(host.searchQueries, ["report"])
            XCTAssertEqual(ws.fileLabels.count, 8)
            XCTAssertEqual(ws.fileLabelColors.count, 8)
            XCTAssertEqual(ws.extendPowerOff(by: 5000), 0)
        }
    }
}

final class CoreDepth3DrawingTests: XCTestCase {
    func testBitmapContextDrawsIntoRep() throws {
        try requireHostBackend("draws through the host offscreen surface")
        try MainActor.assumeIsolated {
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4,
                                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = NSSize(width: 10, height: 10)
            let g = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
            XCTAssertFalse(g.isFlipped)
            XCTAssertEqual(g.colorRenderingIntent, .relativeColorimetric)
            XCTAssertTrue(g.graphicsPort == Unmanaged.passUnretained(g.cgContext).toOpaque())
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = g
            NSColor.red.setFill()
            NSBezierPath.fill(NSRect(x: 0, y: 0, width: 5, height: 5))   // points: 10×10 pixels
            NSGraphicsContext.restoreGraphicsState()
            XCTAssertEqual(rep.colorAt(x: 2, y: 17)?.alphaComponent ?? 0, 1, accuracy: 0.01)
            XCTAssertEqual(rep.colorAt(x: 8, y: 11)?.redComponent ?? 0, 1, accuracy: 0.01)
            XCTAssertEqual(rep.colorAt(x: 12, y: 12)?.alphaComponent ?? 1, 0, accuracy: 0.01)
            XCTAssertNil(NSGraphicsContext(attributes: [:]))
            XCTAssertNotNil(NSGraphicsContext(attributes: [.destination: rep]))
        }
    }
    func testBezierCloseMoveAndReverse() {
        let r = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertEqual(r.elementCount, 5)
        XCTAssertEqual(elements(r.reversed), "M0,0 L0,20 L10,20 L10,0 Z M0,0")
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 1, y: 2)); p.line(to: NSPoint(x: 3, y: 4)); p.close()
        XCTAssertEqual(p.elementCount, 4)   // M L Z M (macOS 15)
        let m = NSBezierPath()
        m.move(to: .zero); m.move(to: NSPoint(x: 2, y: 2))
        XCTAssertEqual(m.elementCount, 1)
        let o = NSBezierPath()
        o.move(to: .zero); o.line(to: NSPoint(x: 5, y: 0))
        o.curve(to: NSPoint(x: 10, y: 10), controlPoint1: NSPoint(x: 6, y: 1), controlPoint2: NSPoint(x: 9, y: 4))
        o.move(to: NSPoint(x: 20, y: 20)); o.line(to: NSPoint(x: 30, y: 20))
        XCTAssertEqual(elements(o.reversed), "M10,10 C5,0 L0,0 M30,20 L20,20")
    }
    func testBezierFlattenAndTangentArc() {
        let oval = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 100, height: 100))
        let flat = oval.flattened
        for i in 0..<flat.elementCount { XCTAssertTrue([.moveTo, .lineTo, .closePath].contains(flat.element(at: i))) }
        XCTAssertGreaterThan(flat.elementCount, 16)
        XCTAssertTrue(near(flat.bounds.width, 100, 0.5))
        let p = NSBezierPath()
        p.move(to: .zero)
        p.appendArc(from: NSPoint(x: 10, y: 0), to: NSPoint(x: 10, y: 10), radius: 5)
        XCTAssertEqual(elements(p), "M0,0 L5,0 C10,5")
        let c = NSBezierPath()
        c.move(to: .zero)
        c.appendArc(from: NSPoint(x: 10, y: 0), to: NSPoint(x: 20, y: 0), radius: 5)
        XCTAssertEqual(elements(c), "M0,0 L10,0")
        let e = NSBezierPath()
        e.appendArc(from: NSPoint(x: 10, y: 0), to: NSPoint(x: 10, y: 10), radius: 5)
        XCTAssertTrue(e.isEmpty)
        XCTAssertTrue(NSBezierPath.supportsSecureCoding)
    }
    func testBezierArchiveUsesAppKitSegments() throws {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 1, y: 2))
        p.curve(to: NSPoint(x: 3, y: 4), controlPoint1: NSPoint(x: 5, y: 6), controlPoint2: NSPoint(x: 7, y: 8))
        p.close()
        p.lineWidth = 3
        p.windingRule = .evenOdd
        var dash: [CGFloat] = [2, 3]
        p.setLineDash(&dash, count: 2, phase: 1)
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        p.encode(with: archiver)
        archiver.finishEncoding()
        let u = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        u.requiresSecureCoding = false
        let seg = try XCTUnwrap(u.decodeObject(forKey: "NSSegments") as? Data)
        XCTAssertEqual(seg.count, 54)   // M, three curve points, Z, M: nine bytes each (macOS 15)
        XCTAssertEqual(Array(seg.prefix(9)), [0x00, 0x3f, 0x80, 0, 0, 0x40, 0, 0, 0])
        let back = try roundTrip(p)
        XCTAssertEqual(elements(back), elements(p))
        XCTAssertEqual(back.lineWidth, 3)
        XCTAssertEqual(back.windingRule, .evenOdd)
        var count = 0
        back.getLineDash(nil, count: &count, phase: nil)
        XCTAssertEqual(count, 2)
    }
    #if os(macOS)
    func testBezierAppendGlyph() throws {
        try MainActor.assumeIsolated {
            let f = try XCTUnwrap(NSFont(name: "Helvetica", size: 20))
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 100, y: 100))
            p.appendGlyph(43, in: f)   // H
            XCTAssertEqual(p.elementCount, 14)
            XCTAssertTrue(near(p.currentPoint.x, 114.443359375))
            XCTAssertTrue(near(p.bounds.minX, 101.572, 0.01))
        }
    }
    #endif
}

final class CoreDepth3TextTests: XCTestCase {
    func testLayoutManagerSetters() {
        MainActor.assumeIsolated {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            tv.string = "Hello\nWorld"
            let lm = tv.layoutManager!
            let container = tv.textContainer!
            _ = lm.glyphRange(for: container)
            XCTAssertEqual(lm.intAttribute(1, forGlyphAt: 0), 0)
            lm.setIntAttribute(1, value: 7, forGlyphAt: 0)
            XCTAssertEqual(lm.intAttribute(1, forGlyphAt: 0), 7)
            lm.setNotShownAttribute(true, forGlyphAt: 1)
            XCTAssertTrue(lm.notShownAttribute(forGlyphAt: 1))
            lm.setDrawsOutsideLineFragment(true, forGlyphAt: 2)
            XCTAssertTrue(lm.drawsOutsideLineFragment(forGlyphAt: 2))
            lm.setLocation(NSPoint(x: 40, y: 9), forStartOfGlyphRange: NSRange(location: 3, length: 1))
            XCTAssertEqual(lm.location(forGlyphAt: 3), NSPoint(x: 40, y: 9))
            let rect = NSRect(x: 0, y: 50, width: 150, height: 20)
            lm.setLineFragmentRect(rect, forGlyphRange: NSRange(location: 6, length: 5), usedRect: rect.insetBy(dx: 10, dy: 0))
            XCTAssertEqual(lm.lineFragmentRect(forGlyphAt: 7, effectiveRange: nil), rect)
            lm.setExtraLineFragmentRect(NSRect(x: 0, y: 90, width: 5, height: 10), usedRect: .zero, textContainer: container)
            XCTAssertEqual(lm.extraLineFragmentRect, NSRect(x: 0, y: 90, width: 5, height: 10))
            // A new layout pass drops what was set.
            tv.string = "Hello\nWorld!"
            _ = lm.glyphRange(for: container)
            XCTAssertEqual(lm.intAttribute(1, forGlyphAt: 0), 0)
            XCTAssertNotEqual(lm.lineFragmentRect(forGlyphAt: 7, effectiveRange: nil), rect)
        }
    }
    func testRulerAccessory() throws {
        try MainActor.assumeIsolated {
            let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            tv.string = "abc"
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let ruler = NSRulerView(scrollView: sv, orientation: .horizontalRuler)
            let accessory = try XCTUnwrap(tv.layoutManager?.rulerAccessoryView(for: tv, paragraphStyle: style, ruler: ruler, enabled: true) as? _NSRulerAccessoryView)
            XCTAssertEqual(accessory.alignment.selectedSegment, 1)
            accessory.alignment.selectedSegment = 2
            _ = accessory.performSelectorAction(Selector(("_rulerAlignmentChosen:")), with: nil)
            XCTAssertEqual(tv.alignment, .right)
        }
    }
    func testTextRTFRoundTrip() throws {
        try MainActor.assumeIsolated {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            tv.isRichText = true
            tv.textStorage?.setAttributedString(NSAttributedString(string: "Bold text", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]))
            let rtf = try XCTUnwrap(tv.rtf(from: NSRange(location: 0, length: 4)))
            let other = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            other.isRichText = true
            other.string = "X"
            other.replaceCharacters(in: NSRange(location: 0, length: 1), withRTF: rtf)
            XCTAssertEqual(other.string, "Bold")
            XCTAssertEqual(NSText.movementUserInfoKey, "NSTextMovement")
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("cd3-\(ProcessInfo.processInfo.processIdentifier).rtfd").path
            defer { try? FileManager.default.removeItem(atPath: path) }
            XCTAssertTrue(tv.writeRTFD(toFile: path, atomically: true))
            XCTAssertTrue(other.readRTFD(fromFile: path))
            XCTAssertEqual(other.string, "Bold text")
        }
    }
    func testTextFieldPlaceholders() {
        MainActor.assumeIsolated {
            let tf = NSTextField(string: "")
            if #available(macOS 15.4, *) {
                XCTAssertTrue(tf.allowsWritingTools)
                XCTAssertFalse(tf.allowsWritingToolsAffordance)
            }
            if #available(macOS 26.0, *) {
                tf.placeholderStrings = ["A long placeholder", "Short"]
                XCTAssertEqual(tf.placeholderStrings, ["A long placeholder", "Short"])
            } else {
                (tf.cell as? NSTextFieldCell)?._placeholderCandidates = [NSAttributedString(string: "A long placeholder"), NSAttributedString(string: "Short")]
                tf.placeholderString = "A long placeholder"
            }
            XCTAssertEqual(tf.placeholderString, "A long placeholder")
        }
    }
}

final class CoreDepth3CodingTests: XCTestCase {
    func testColorArchive() throws {
        let c = try roundTrip(NSColor(srgbRed: 0.5, green: 0.25, blue: 0.125, alpha: 0.5))
        XCTAssertTrue(near(c.redComponent, 0.5) && near(c.greenComponent, 0.25) && near(c.alphaComponent, 0.5))
        let w = try roundTrip(NSColor(white: 0.5, alpha: 0.75))
        XCTAssertTrue(near(w.whiteComponent, 0.5) && near(w.alphaComponent, 0.75))
        let label = try roundTrip(MainActor.assumeIsolated { NSColor.labelColor })
        XCTAssertEqual(label.colorNameComponent, "labelColor")
    }
    func testModelArchives() throws {
        try MainActor.assumeIsolated {
            let g = try XCTUnwrap(NSGradient(colors: [.red, .blue]))
            XCTAssertEqual(try roundTrip(g).numberOfColorStops, 2)
            let a = NSAnimation(duration: 2, animationCurve: .easeIn)
            a.frameRate = 30
            a.addProgressMark(0.5)
            let a2 = try roundTrip(a)
            XCTAssertEqual(a2.duration, 2)
            XCTAssertEqual(a2.animationCurve, .easeIn)
            XCTAssertEqual(a2.frameRate, 30)
            XCTAssertEqual(a2.progressMarks.count, 1)
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
            col.width = 120; col.title = "Name"; col.isHidden = true
            let col2 = try roundTrip(col)
            XCTAssertEqual(col2.identifier.rawValue, "col")
            XCTAssertEqual(col2.width, 120)
            XCTAssertEqual(col2.title, "Name")
            XCTAssertTrue(col2.isHidden)
            let t = NSTrackingArea(rect: NSRect(x: 1, y: 2, width: 3, height: 4), options: [.mouseEnteredAndExited, .activeAlways], owner: nil, userInfo: ["k": "v"])
            let t2 = try roundTrip(t)
            XCTAssertEqual(t2.rect, NSRect(x: 1, y: 2, width: 3, height: 4))
            XCTAssertEqual(t2.options, [.mouseEnteredAndExited, .activeAlways])
            XCTAssertEqual(t2.userInfo?["k"] as? String, "v")
            let flow = NSCollectionViewFlowLayout()
            flow.itemSize = NSSize(width: 40, height: 50); flow.scrollDirection = .horizontal
            let flow2 = try roundTrip(flow)
            XCTAssertEqual(flow2.itemSize, NSSize(width: 40, height: 50))
            XCTAssertEqual(flow2.scrollDirection, .horizontal)
            let grid = NSCollectionViewGridLayout()
            grid.maximumNumberOfColumns = 3
            XCTAssertEqual(try roundTrip(grid).maximumNumberOfColumns, 3)
            XCTAssertEqual(try roundTrip(NSScrubberProportionalLayout(numberOfVisibleItems: 3)).numberOfVisibleItems, 3)
        }
    }
    func testViewsDecodeAsEmpty() throws {
        try MainActor.assumeIsolated {
            let archiver = NSKeyedArchiver(requiringSecureCoding: false)
            archiver.finishEncoding()
            let coder = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
            let box = try XCTUnwrap(NSBox(coder: coder))
            XCTAssertNotNil(box.contentView)
            let combo = try XCTUnwrap(NSComboBox(coder: coder))
            XCTAssertTrue(combo.cell is NSComboBoxCell)
            XCTAssertTrue(combo.isEditable)
            XCTAssertNotNil(NSTableView(coder: coder)?.headerView)
            XCTAssertTrue(NSSegmentedControl(coder: coder)?.cell is NSSegmentedCell)
            XCTAssertNotNil(NSCollectionView(coder: coder))
            XCTAssertNotNil(NSScrubber(coder: coder))
        }
    }
}

final class CoreDepth3TailTests: XCTestCase {
    func testAccessibilityHelpers() {
        MainActor.assumeIsolated {
            XCTAssertEqual(NSAccessibility.ErrorCodeExceptionInfo, "NSAccessibilityErrorCodeExceptionInfo")
            XCTAssertTrue(NSAccessibility.setMayContainProtectedContent(true))
            let plain = NSView(frame: .zero)
            let button = NSButton(title: "B", target: nil, action: nil)
            plain.addSubview(button)
            let kids = NSAccessibility.unignoredChildren(from: [plain])
            XCTAssertEqual(kids.count, 1)
            XCTAssertTrue(kids.first as AnyObject === button)
            XCTAssertTrue(NSAccessibility.unignoredDescendant(of: plain) as AnyObject === button)
        }
    }
    func testClassDefaults() {
        MainActor.assumeIsolated {
            XCTAssertTrue(NSScroller.isCompatibleWithOverlayScrollers)
            final class Sub: NSScroller {}
            XCTAssertFalse(Sub.isCompatibleWithOverlayScrollers)
            XCTAssertTrue(NSSliderCell.prefersTrackingUntilMouseUp)
            XCTAssertTrue(NSTextField(string: "").valueClassForBinding(NSBindingName.value) == NSString.self)
            XCTAssertTrue(NSSlider().valueClassForBinding(NSBindingName.value) == NSNumber.self)
            XCTAssertNil(NSButton().valueClassForBinding(NSBindingName.value))
            XCTAssertNil(NSObject().valueClassForBinding(NSBindingName.value))
        }
    }
    func testPasteboardItemAndSound() throws {
        let item = try XCTUnwrap(NSPasteboardItem(pasteboardPropertyList: "hello", ofType: .string))
        XCTAssertEqual(item.string(forType: .string), "hello")
        XCTAssertNil(NSSound(pasteboardPropertyList: "x", ofType: .sound))
    }
    func testCollectionLegacyContent() {
        MainActor.assumeIsolated {
            let cv = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
            cv.collectionViewLayout = NSCollectionViewGridLayout()
            cv.itemPrototype = NSCollectionViewItem(nibName: nil, bundle: nil)
            cv.content = ["a", "b", "c"]
            XCTAssertEqual(cv.numberOfItems(inSection: 0), 3)
            let item = cv.newItem(forRepresentedObject: "z")
            XCTAssertEqual(item.representedObject as? String, "z")
            let f0 = cv.frameForItem(at: 0, withNumberOfItems: 10), f1 = cv.frameForItem(at: 1, withNumberOfItems: 10)
            XCTAssertGreaterThan(f1.minX, f0.minX)
            XCTAssertEqual(cv.frameForItem(at: 12, withNumberOfItems: 10), .zero)
        }
    }
}
