// AppKit globals and AppKit's Foundation extensions (ADR-0033): constants carry the SDK's
// values, drawing globals change pixels, string drawing with options measures like the
// layout manager, document reading, paragraph and script edits, index paths, bindings
// markers and NSWorkspace's typed notification messages.

import XCTest
@testable import AppKit

/// A view whose drawing is supplied by the test.
@MainActor
private final class DrawingView: NSView {
    var body: (NSRect) -> Void = { _ in }
    override func draw(_ dirtyRect: NSRect) { body(bounds) }
}

/// An 8-bit premultiplied bitmap context with an AppKit graphics context around it.
@MainActor
private func withBitmapContext(width: Int = 40, height: Int = 40, flipped: Bool = false, _ body: (NSGraphicsContext) -> Void) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let gc = NSGraphicsContext(cgContext: ctx, flipped: flipped)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = gc
    body(gc)
    NSGraphicsContext.current = previous
    return ctx
}

/// The pixel at (x, y), y up from the bottom of the image, as 0...255 components.
private func rgba(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let data = _pixels(image)
    let i = (image.height - 1 - y) * image.bytesPerRow + x * 4
    return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]), Int(data[i + 3]))
}

final class GlobalsFoundationTests: XCTestCase, @unchecked Sendable {

    // MARK: Constants

    func testGlobalConstantsCarryTheSDKValues() {
        // Function keys are the Unicode private-use code points AppKit puts in key events.
        XCTAssertEqual(NSUpArrowFunctionKey, 0xF700)
        XCTAssertEqual(NSDownArrowFunctionKey, 0xF701)
        XCTAssertEqual(NSF1FunctionKey, 0xF704)
        XCTAssertEqual(NSF35FunctionKey, 0xF726)
        XCTAssertEqual(NSDeleteFunctionKey, 0xF728)
        XCTAssertEqual(NSModeSwitchFunctionKey, 0xF747)
        XCTAssertEqual(NSEnterCharacter, 0x03)
        XCTAssertEqual(NSBackspaceCharacter, 0x08)
        XCTAssertEqual(NSTabCharacter, 0x09)
        XCTAssertEqual(NSCarriageReturnCharacter, 0x0D)
        XCTAssertEqual(NSDeleteCharacter, 0x7F)
        XCTAssertEqual(NSLineSeparatorCharacter, 0x2028)
        XCTAssertEqual(NSParagraphSeparatorCharacter, 0x2029)
        // Panel and alert return codes.
        XCTAssertEqual(NSOKButton, 1)
        XCTAssertEqual(NSCancelButton, 0)
        XCTAssertEqual(NSAlertDefaultReturn, 1)
        XCTAssertEqual(NSAlertAlternateReturn, 0)
        XCTAssertEqual(NSAlertOtherReturn, -1)
        XCTAssertEqual(NSAlertErrorReturn, -2)
        XCTAssertEqual(NSRunStoppedResponse, -1000)
        XCTAssertEqual(NSRunAbortedResponse, -1001)
        XCTAssertEqual(NSRunContinuesResponse, -1002)
        // Text movement codes and masks.
        XCTAssertEqual(NSReturnTextMovement, 0x10)
        XCTAssertEqual(NSTabTextMovement, 0x11)
        XCTAssertEqual(NSFontPanelAllModesMask, 0xFFFF_FFFF)
        XCTAssertEqual(NSFontItalicTrait, 1)
        XCTAssertEqual(NSFontBoldTrait, 2)
        // String constants equal Apple's strings.
        XCTAssertEqual(NSAccessibilitySearchDirectionNext, "AXDirectionNext")
        XCTAssertEqual(NSAccessibilitySearchCurrentElementKey, "AXStartElement")
        XCTAssertEqual(NSAllRomanInputSourcesLocaleIdentifier, "NSAllRomanInputSourcesLocaleIdentifier")
        // AppKit's Foundation constants.
        XCTAssertEqual(CocoaError.Code.serviceMiscellaneous.rawValue, 66800)
        XCTAssertEqual(CocoaError.Code.textReadInapplicableDocumentType.rawValue, 65806)
    }

    func testNotificationNamesEqualApplesStrings() {
        XCTAssertEqual(NSNotification.Name.NSApplicationProtectedDataDidBecomeAvailable.rawValue, "NSApplicationProtectedDataDidBecomeAvailableNotification")
        XCTAssertEqual(NSWorkspace.didHideApplicationNotification.rawValue, "NSWorkspaceDidHideApplicationNotification")
        XCTAssertEqual(NSWorkspace.didRenameVolumeNotification.rawValue, "NSWorkspaceDidRenameVolumeNotification")
    }

    func testCocoaErrorRanges() {
        XCTAssertTrue(CocoaError(.serviceApplicationNotFound).isServiceError)
        XCTAssertFalse(CocoaError(.serviceApplicationNotFound).isFontError)
        XCTAssertTrue(CocoaError(.fontAssetDownloadError).isFontError)
        XCTAssertTrue(CocoaError(.sharingServiceNotConfigured).isSharingServiceError)
        XCTAssertTrue(CocoaError(.textReadInapplicableDocumentType).isTextReadWriteError)
        XCTAssertFalse(CocoaError(.fileNoSuchFile).isTextReadWriteError)
    }

    // MARK: Geometry, glyphs, index paths, markers

    func testGeometryAndIndexPathHelpers() {
        let zero = NSDirectionalEdgeInsetsZero
        XCTAssertEqual([zero.top, zero.leading, zero.bottom, zero.trailing], [0, 0, 0, 0])
        var insets = NSDirectionalEdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        insets.leading = 5
        XCTAssertEqual([insets.top, insets.leading, insets.bottom, insets.trailing], [1, 5, 3, 4])

        let path = NSIndexPath(forItem: 7, inSection: 3)
        XCTAssertEqual(path.item, 7)
        XCTAssertEqual(path.section, 3)
        XCTAssertEqual(path as IndexPath, IndexPath(item: 7, section: 3))

        let set = NSSet(collectionViewIndexPaths: [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 2)])
        var seen: Set<IndexPath> = []
        set.enumerateIndexPaths { p, _ in seen.insert(p) }
        XCTAssertEqual(seen, [IndexPath(item: 0, section: 0), IndexPath(item: 1, section: 2)])
        XCTAssertEqual(NSSet(collectionViewIndexPath: IndexPath(item: 4, section: 1)).count, 1)
        var visits = 0
        set.enumerateIndexPaths { _, stop in visits += 1; stop.pointee = true }
        XCTAssertEqual(visits, 1, "stop ends the enumeration")

        var glyphs: [NSGlyph] = [0x41, 0x1234, 0x10002]
        var packed = [CChar](repeating: 0, count: 6)
        XCTAssertEqual(NSConvertGlyphsToPackedGlyphs(&glyphs, 3, .nativeShortGlyphPacking, &packed), 6)
        let shorts = packed.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        XCTAssertEqual(shorts, [0x41, 0x1234, 0x0002])

        XCTAssertTrue(NSIsControllerMarker(NSMultipleValuesMarker))
        XCTAssertTrue(NSIsControllerMarker(NSNoSelectionMarker))
        XCTAssertTrue(NSIsControllerMarker(NSNotApplicableMarker))
        XCTAssertFalse(NSIsControllerMarker("value"))
        XCTAssertFalse(NSIsControllerMarker(nil))
        XCTAssertFalse(NSMultipleValuesMarker === NSNoSelectionMarker)
    }

    // MARK: Drawing globals

    func testTiledRectsSliceAndFill() {
        MainActor.assumeIsolated {
            var remainder = NSRect.zero
            let ctx = withBitmapContext { _ in
                let sides: [NSRectEdge] = [NSRectEdge(rawValue: 2)!, NSRectEdge(rawValue: 1)!]   // maxX, minY
                let grays: [CGFloat] = [0, 1]
                remainder = NSDrawTiledRects(NSRect(x: 0, y: 0, width: 40, height: 40), NSRect(x: 0, y: 0, width: 40, height: 40), sides, grays, 2)
            }
            XCTAssertEqual(remainder, NSRect(x: 0, y: 1, width: 39, height: 39))
            let image = ctx.makeImage()!
            XCTAssertEqual(rgba(image, 39, 20).r, 0, "black strip on the right")
            XCTAssertEqual(rgba(image, 39, 20).a, 255)
            XCTAssertEqual(rgba(image, 10, 0).r, 255, "white strip along the bottom")
            XCTAssertEqual(rgba(image, 10, 10).a, 0, "the remainder is untouched")
        }
    }

    func testRectFillEraseAndReadPixel() {
        MainActor.assumeIsolated {
            var read: NSColor?
            var erased: NSColor?
            let ctx = withBitmapContext { gc in
                NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 20, height: 40).fill()
                read = NSReadPixel(NSPoint(x: 5, y: 30))
                NSEraseRect(NSRect(x: 20, y: 0, width: 20, height: 40))
                erased = NSReadPixel(NSPoint(x: 30, y: 30))
                NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 10, height: 10).frame(withWidth: 2)
                // An NSAffineTransform concat moves later drawing.
                let t = NSAffineTransform()
                t.translateX(by: 30, yBy: 30)
                gc.saveGraphicsState()
                t.concat()
                NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: 5, height: 5).fill()
                gc.restoreGraphicsState()
            }
            let image = ctx.makeImage()!
            XCTAssertEqual(rgba(image, 5, 30).r, 255)
            XCTAssertEqual(rgba(image, 30, 10).g, 255, "erased to white")
            XCTAssertEqual(rgba(image, 1, 5).b, 255, "frame band")
            XCTAssertEqual(rgba(image, 5, 5).r, 255, "inside the frame keeps the red fill")
            XCTAssertEqual(rgba(image, 32, 32).g, 255, "drawn through the transform")
            XCTAssertEqual(rgba(image, 32, 32).r, 0)
            guard let read, let erased else { return XCTFail("NSReadPixel answered nil on a bitmap context") }
            let r = read, e = erased
            XCTAssertEqual(r.redComponent, 1, accuracy: 0.02)
            XCTAssertEqual(r.greenComponent, 0, accuracy: 0.02)
            XCTAssertEqual(e.greenComponent, 1, accuracy: 0.02)
        }
    }

    func testDrawBitmapAndBezels() {
        MainActor.assumeIsolated {
            // A 4x4 meshed RGB bitmap, left half red and right half blue, stretched over the
            // bottom half. Samples sit in the middle of each colour block: a scaled image is
            // filtered, and at the image's outer edge Cairo blends with transparent padding
            // where CoreGraphics clamps, so edge pixels differ by backend.
            let red: [UInt8] = [255, 0, 0], blue: [UInt8] = [0, 0, 255]
            let row = [red, red, blue, blue].flatMap { $0 }
            var bytes: [UInt8] = Array(repeating: row, count: 4).flatMap { $0 }
            let ctx = withBitmapContext { _ in
                bytes.withUnsafeBufferPointer { buf in
                    var planes: [UnsafePointer<UInt8>?] = [buf.baseAddress, nil, nil, nil, nil]
                    NSDrawBitmap(NSRect(x: 0, y: 0, width: 40, height: 20), 4, 4, 8, 3, 24, 12, false, false, .deviceRGB, &planes)
                }
                NSDrawButton(NSRect(x: 0, y: 20, width: 40, height: 20), NSRect(x: 0, y: 0, width: 40, height: 40))
            }
            let image = ctx.makeImage()!
            // (10, 10) and (30, 10) map to source (1, 2) and (3, 2): between two pixels of one colour.
            XCTAssertEqual(rgba(image, 10, 10).r, 255)
            XCTAssertEqual(rgba(image, 10, 10).b, 0)
            XCTAssertEqual(rgba(image, 30, 10).b, 255)
            XCTAssertEqual(rgba(image, 30, 10).r, 0)
            // NSDrawButton: black outer bottom/right, white top/left, light grey face.
            XCTAssertEqual(rgba(image, 39, 30).r, 0, "outer right edge is black")
            XCTAssertEqual(rgba(image, 0, 30).r, 255, "left edge is white")
            XCTAssertEqual(rgba(image, 20, 30).r, 170, accuracy: 2, "light grey face")
        }
    }

    func testRectFillChangesPixelsInAHostWindow() throws {
        try MainActor.assumeIsolated {
            guard Platform.backend is HostBackend else { throw XCTSkip("reads the host backend's rendered window") }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 60, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
            let v = DrawingView(frame: NSRect(x: 0, y: 0, width: 60, height: 40))
            v.body = { bounds in
                NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height).fill()
                NSDrawWindowBackground(NSRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height))
            }
            w.contentView = v
            w.display()
            let platform = Mirror(reflecting: w).descendant("_platform") as! HostWindow
            guard let image = platform.lastImage else { return XCTFail("no image") }
            let data = _pixels(image)
            let scale = image.width / 60
            func pixel(_ x: CGFloat, _ y: CGFloat) -> (r: Int, g: Int, b: Int) {
                let px = Int(x) * scale, row = image.height - 1 - Int(y) * scale, i = row * image.bytesPerRow + px * 4
                return (Int(data[i + 2]), Int(data[i + 1]), Int(data[i]))
            }
            let left = pixel(10, 20), right = pixel(50, 20)
            XCTAssertGreaterThan(left.b, 200)
            XCTAssertLessThan(left.r, 40)
            XCTAssertEqual(right.r, right.b, accuracy: 6, "window background is a grey")
            w.close()
        }
    }

    // MARK: String drawing with options

    func testAttributedStringMeasurementMatchesTheLayoutManager() {
        MainActor.assumeIsolated {
            let font = NSFont.systemFont(ofSize: 13)
            let text = NSAttributedString(string: "The quick brown fox jumps over the lazy dog", attributes: [.font: font])
            // A layout manager set up by hand, as a text view would.
            let storage = NSTextStorage(attributedString: text)
            let lm = NSLayoutManager()
            lm.usesFontLeading = false
            storage.addLayoutManager(lm)
            let container = NSTextContainer(size: NSSize(width: 120, height: 10_000))
            container.lineFragmentPadding = 0
            lm.addTextContainer(container)
            let used = lm.usedRect(for: container)

            let wrapped = _NSStringDrawingLayout(text, size: CGSize(width: 120, height: 0), options: [.usesLineFragmentOrigin]).boundingRect
            XCTAssertEqual(wrapped.width, used.width, accuracy: 0.01)
            XCTAssertEqual(wrapped.height, used.height, accuracy: 0.01)
            XCTAssertEqual(wrapped.minY, 0)

            let line = _NSStringDrawingLayout(text, size: CGSize(width: 120, height: 0), options: []).boundingRect
            XCTAssertGreaterThan(line.width, 120, "without the line fragment origin option the text stays on one line")
            XCTAssertLessThan(line.minY, 0, "the single-line rect starts below the baseline")
            XCTAssertGreaterThan(wrapped.height, line.height * 1.5, "wrapped to more than one line")
            XCTAssertEqual(line.height, wrapped.height / (wrapped.height / line.height).rounded(), accuracy: 1)
        }
    }

    func testDrawWithOptionsPutsTextInsideTheRect() {
        MainActor.assumeIsolated {
            let text = NSAttributedString(string: "MMMM", attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black])
            for flipped in [false, true] {
                let ctx = withBitmapContext(width: 80, height: 80, flipped: flipped) { gc in
                    // A flipped context is a flipped CTM, as a flipped view sets up.
                    if flipped { gc.cgContext.translateBy(x: 0, y: 80); gc.cgContext.scaleBy(x: 1, y: -1) }
                    _NSStringDrawingLayout(text, size: CGSize(width: 80, height: 40), options: [.usesLineFragmentOrigin])
                        .draw(in: CGRect(x: 0, y: flipped ? 0 : 40, width: 80, height: 40))
                }
                let image = ctx.makeImage()!
                // Ink only in the top half of the bitmap (y up 40...80).
                var top = 0, bottom = 0
                for y in 0..<80 { for x in 0..<80 where rgba(image, x, y).a > 128 { if y >= 40 { top += 1 } else { bottom += 1 } } }
                XCTAssertGreaterThan(top, 20, "flipped: \(flipped)")
                XCTAssertEqual(bottom, 0, "flipped: \(flipped)")
            }
        }
    }

    // MARK: Documents and editing

    func testReadingDocumentsByURL() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("globals-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let rtf = dir.appendingPathComponent("a.rtf")
        try Data("{\\rtf1\\ansi {\\fonttbl\\f0 Helvetica;}\\f0 Hello {\\b bold}}".utf8).write(to: rtf)
        var attrs: NSDictionary?
        let s = try _NSAttributedStringDocuments.read(url: rtf, options: [:], documentAttributes: &attrs)
        XCTAssertEqual(s.string, "Hello bold")
        XCTAssertEqual(attrs?["DocumentType"] as? String, "NSRTF")
        let txt = dir.appendingPathComponent("b.txt")
        try Data("plain".utf8).write(to: txt)
        XCTAssertEqual(try _NSAttributedStringDocuments.read(url: txt, options: [:], documentAttributes: nil).string, "plain")
        XCTAssertThrowsError(try _NSAttributedStringDocuments.read(data: Data("<b>x</b>".utf8), options: [NSAttributedString.DocumentReadingOptionKey(rawValue: "DocumentType"): "NSHTML"], documentAttributes: nil))
    }

    func testParagraphAndScriptEdits() {
        // Typed locals: Apple's text enums are visible to the macOS test target too.
        let center: NSTextAlignment = .center, rtl: NSWritingDirection = .rightToLeft
        let s = NSMutableAttributedString(string: "one\ntwo\nthree")
        s.setAlignment(center, range: NSRange(location: 5, length: 1))
        func style(_ i: Int) -> NSParagraphStyle? { s.attribute(.paragraphStyle, at: i, effectiveRange: nil) as? NSParagraphStyle }
        XCTAssertNil(style(0), "the first paragraph is untouched")
        XCTAssertEqual(style(4)?.alignment, center, "the whole second paragraph")
        XCTAssertEqual(style(7)?.alignment, center)
        XCTAssertNil(style(8))
        s.setBaseWritingDirection(rtl, range: NSRange(location: 0, length: s.length))
        XCTAssertEqual(style(0)?.baseWritingDirection, rtl)
        XCTAssertEqual(style(4)?.alignment, center, "other settings are kept")

        // A paragraph with two styles takes the first one throughout.
        let left = NSMutableParagraphStyle(); left.alignment = .left
        let right = NSMutableParagraphStyle(); right.alignment = .right
        let p = NSMutableAttributedString(string: "abcd")
        p.addAttribute(.paragraphStyle, value: left, range: NSRange(location: 0, length: 2))
        p.addAttribute(.paragraphStyle, value: right, range: NSRange(location: 2, length: 2))
        p.fixParagraphStyleAttribute(in: NSRange(location: 0, length: 4))
        XCTAssertEqual((p.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .left)

        let t = NSMutableAttributedString(string: "x2")
        t.superscriptRange(NSRange(location: 1, length: 1))
        t.superscriptRange(NSRange(location: 1, length: 1))
        XCTAssertEqual(t.attribute(.superscript, at: 1, effectiveRange: nil) as? Int, 2)
        t.subscriptRange(NSRange(location: 1, length: 1))
        XCTAssertEqual(t.attribute(.superscript, at: 1, effectiveRange: nil) as? Int, 1)
        t.unscriptRange(NSRange(location: 0, length: 2))
        XCTAssertNil(t.attribute(.superscript, at: 1, effectiveRange: nil))

        let link = NSMutableAttributedString(string: "see here")
        link.addAttribute(.link, value: "https://example.com/", range: NSRange(location: 4, length: 4))
        var range = NSRange()
        XCTAssertEqual(link.url(at: 5, effectiveRange: &range), URL(string: "https://example.com/"))
        XCTAssertEqual(range, NSRange(location: 4, length: 4))
        XCTAssertEqual(link.lineBreak(before: 6, within: NSRange(location: 0, length: 8)), 4)
        XCTAssertEqual(link.lineBreak(before: 3, within: NSRange(location: 0, length: 8)), NSNotFound)
        XCTAssertTrue(NSAttributedString.textTypes.contains("public.rtf"))
    }

    // MARK: Pasteboard

    func testURLAndStringPasteboardHooks() {
        MainActor.assumeIsolated {
            let pb = NSPasteboard(name: NSPasteboard.Name("globals-test-\(UUID().uuidString)"))
            _ = pb.clearContents()
            NSURL(string: "https://example.com/a")!.write(to: pb)
            XCTAssertEqual(NSURL(fromPasteboard: pb)?.absoluteString, "https://example.com/a")
            XCTAssertEqual(NSString(pasteboardPropertyList: "text", ofType: NSPasteboard.PasteboardType(rawValue: "public.utf8-plain-text")) as String?, "text")
            XCTAssertEqual(NSString(pasteboardPropertyList: Data("data".utf8), ofType: NSPasteboard.PasteboardType(rawValue: "public.utf8-plain-text")) as String?, "data")
            XCTAssertNil(NSString(pasteboardPropertyList: 3, ofType: NSPasteboard.PasteboardType(rawValue: "public.utf8-plain-text")))
        }
    }

    // MARK: Workspace messages

    func testWorkspaceMessagesRoundTripThroughNotifications() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("NSWorkspace messages are macOS 26 API") }
        try MainActor.assumeIsolated {
            let message = NSWorkspace.DidRenameVolumeMessage(localizedVolumeName: "New", volumeURL: URL(fileURLWithPath: "/Volumes/New"),
                                                             oldLocalizedVolumeName: "Old", oldVolumeURL: URL(fileURLWithPath: "/Volumes/Old"))
            let note = NSWorkspace.DidRenameVolumeMessage.makeNotification(message)
            XCTAssertEqual(note.name, NSWorkspace.didRenameVolumeNotification)
            XCTAssertEqual(note.userInfo?[NSWorkspace.oldLocalizedVolumeNameUserInfoKey] as? String, "Old")
            let back = try XCTUnwrap(NSWorkspace.DidRenameVolumeMessage.makeMessage(note))
            XCTAssertEqual(back.localizedVolumeName, "New")
            XCTAssertEqual(back.oldVolumeURL.path, "/Volumes/Old")
            XCTAssertNil(NSWorkspace.DidRenameVolumeMessage.makeMessage(Notification(name: NSWorkspace.didWakeNotification)))
            XCTAssertNotNil(NSWorkspace.DidWakeMessage.makeMessage(Notification(name: NSWorkspace.didWakeNotification)))
            XCTAssertNil(NSWorkspace.DidLaunchApplicationMessage.makeMessage(Notification(name: NSWorkspace.didLaunchApplicationNotification)),
                         "a notification without its application gives no message")
        }
    }
}
