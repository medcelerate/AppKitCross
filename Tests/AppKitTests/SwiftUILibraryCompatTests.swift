// The members added in the second library-compatibility round
// (docs/compatibility/swiftui-libraries.md): what Nuke, NukeUI and SwiftUI-Introspect
// reach for on the macOS host build. AsyncImage and Material, the deprecated
// `.accessibility(...)` spellings, Sendable NSColor/NSImage, AppKit re-exporting ImageIO,
// and a library's own main-actor protocol refining NSViewControllerRepresentable.

import XCTest
@testable import AppKit
@testable import SwiftUI

@MainActor
private func host<V: View>(_ view: V, width: CGFloat = 200, height: CGFloat = 100) -> (NSWindow, NSHostingView<V>) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
    let h = NSHostingView(rootView: view)
    h.frame = NSRect(x: 0, y: 0, width: width, height: height)
    w.contentView!.addSubview(h)
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    return (w, h)
}

@MainActor
private func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(allViews) }

/// Pumps the main run loop, laying `host` out after each turn (the headless host has no
/// display cycle to flush a state change), until `condition` holds or `seconds` pass.
@MainActor
private func pump(_ host: NSView, _ seconds: TimeInterval, until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition(), Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        host.layoutSubtreeIfNeeded()
    }
}

/// A 4x4 PNG (left half red, right half blue), written to a temporary file.
@MainActor
private func samplePNGFile() -> URL {
    let img = NSImage(size: NSSize(width: 4, height: 4))
    img.lockFocus()
    NSColor.red.setFill(); NSBezierPath.fill(NSRect(x: 0, y: 0, width: 2, height: 4))
    NSColor.blue.setFill(); NSBezierPath.fill(NSRect(x: 2, y: 0, width: 2, height: 4))
    img.unlockFocus()
    let rep = img.representations.first as! NSBitmapImageRep
    let data = rep.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("appkitcross-asyncimage-\(UUID().uuidString).png")
    try! data.write(to: url)
    return url
}

final class SwiftUIAsyncImageTests: XCTestCase, @unchecked Sendable {
    func testLoadsAFileURLIntoAnImageView() {
        MainActor.assumeIsolated {
            let url = samplePNGFile()
            defer { try? FileManager.default.removeItem(at: url) }
            let (w, h) = host(AsyncImage(url: url))
            let imageView = allViews(h).compactMap { $0 as? NSImageView }.first
            XCTAssertNotNil(imageView, "the empty phase shows an (empty) Image")
            pump(h, 3) { imageView?.image?.isValid == true }
            guard let loaded = imageView?.image else { return XCTFail("the file was not loaded") }
            XCTAssertEqual(loaded.size, NSSize(width: 8, height: 8), "lockFocus rendered the sample at 2x")
            w.close()
        }
    }

    func testScaleDividesThePointSize() {
        MainActor.assumeIsolated {
            let url = samplePNGFile()
            defer { try? FileManager.default.removeItem(at: url) }
            let (w, h) = host(AsyncImage(url: url, scale: 2))
            let imageView = allViews(h).compactMap { $0 as? NSImageView }.first
            pump(h, 3) { imageView?.image?.isValid == true }
            XCTAssertEqual(imageView?.image?.size, NSSize(width: 4, height: 4))
            w.close()
        }
    }

    func testPhasesAndPlaceholder() {
        MainActor.assumeIsolated {
            let url = samplePNGFile()
            defer { try? FileManager.default.removeItem(at: url) }
            // content/placeholder: the placeholder shows until the image is decoded.
            let (w, h) = host(AsyncImage(url: url) { image in image.resizable() } placeholder: { Text("loading") })
            XCTAssertEqual(allViews(h).compactMap { $0 as? _TextView }.first?.storage.string, "loading")
            pump(h, 3) { allViews(h).contains { $0 is NSImageView } }
            XCTAssertTrue(allViews(h).contains { $0 is NSImageView }, "the content closure's Image replaced the placeholder")
            XCTAssertTrue(allViews(h).compactMap { $0 as? _TextView }.isEmpty)
            w.close()

            // The phase closure sees .failure for a URL that cannot be read.
            let missing = URL(fileURLWithPath: "/nonexistent/appkitcross-\(UUID().uuidString).png")
            let (w2, h2) = host(AsyncImage(url: missing) { phase -> Text in
                if phase.error != nil { return Text("failed") }
                if phase.image != nil { return Text("image") }
                return Text("empty")
            })
            let text = allViews(h2).compactMap { $0 as? _TextView }.first
            XCTAssertEqual(text?.storage.string, "empty")
            pump(h2, 3) { text?.storage.string == "failed" }
            XCTAssertEqual(text?.storage.string, "failed")
            w2.close()
        }
    }

    func testNilURLStaysEmpty() {
        MainActor.assumeIsolated {
            let (w, h) = host(AsyncImage(url: nil) { phase in Text(phase.image == nil && phase.error == nil ? "empty" : "other") })
            let text = allViews(h).compactMap { $0 as? _TextView }.first
            pump(h, 0.3) { false }
            XCTAssertEqual(text?.storage.string, "empty")
            w.close()
        }
    }
}

final class SwiftUIMaterialTests: XCTestCase, @unchecked Sendable {
    func testMaterialFillsWithATranslucentWindowBackground() {
        MainActor.assumeIsolated {
            let (w, h) = host(Rectangle().fill(Material.regular), width: 40, height: 40)
            guard let rep = h.bitmapImageRepForCachingDisplay(in: h.bounds) else { return XCTFail("no rep") }
            h.cacheDisplay(in: h.bounds, to: rep)
            let scale = max(1, rep.pixelsWide / 40)
            guard let c = rep.colorAt(x: 20 * scale, y: 20 * scale) else { return XCTFail("no pixel") }
            XCTAssertEqual(c.alphaComponent, 0.8, accuracy: 0.1, "regular material is 80 % window background")
            w.close()
        }
    }

    func testStaticMembersAndBackgroundOverloads() {
        MainActor.assumeIsolated {
            // `.background(Material.ultraThick)` (NukeUI) and the `.regularMaterial` spelling type-check
            // and draw as a backdrop; `.background(Color)` keeps resolving to the view overload.
            let view = VStack {
                Text("a").background(Material.ultraThick)
                Text("b").background(.regularMaterial)
                Text("c").background(Color.red)
                Text("d").background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
            let (w, h) = host(view)
            XCTAssertEqual(allViews(h).compactMap { $0 as? _TextView }.count, 4)
            XCTAssertEqual(Material.ultraThin.opacity, 0.55)
            w.close()
        }
    }
}

final class SwiftUILibraryIdiomRound2Tests: XCTestCase, @unchecked Sendable {
    /// Nuke keeps an `NSImage` and an `NSColor` in `Sendable` structs, as Apple's are
    /// (`NS_SWIFT_SENDABLE`); `AsyncImagePhase` carries an `Image`.
    struct Border: Sendable { let color: NSColor; let image: NSImage; let phase: AsyncImagePhase }

    func testColourAndImageAreSendable() {
        let border = Border(color: .red, image: NSImage(), phase: .success(Image(nsImage: NSImage())))
        XCTAssertNotNil(border.phase.image)
        XCTAssertNil(border.phase.error)
    }

    /// Nuke decodes on its pipeline's tasks and decompresses the result by drawing its
    /// `cgImage` there: `NSImage(data:)`, `NSBitmapImageRep(data:)` and
    /// `cgImage(forProposedRect:context:hints:)` work off the main actor, as Apple's do.
    func testImagesDecodeOffTheMainActor() {
        let data: Data = MainActor.assumeIsolated {
            let url = samplePNGFile()
            defer { try? FileManager.default.removeItem(at: url) }
            return try! Data(contentsOf: url)
        }
        let done = expectation(description: "decoded")
        final class Box: @unchecked Sendable { var size = NSSize.zero; var pixels = 0; var png = 0 }
        let box = Box()
        Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            if let image = NSImage(data: data) {
                box.size = image.size
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { box.pixels = cg.width * cg.height }
                if let rep = image.representations.first as? NSBitmapImageRep {
                    box.png = rep.representation(using: .png, properties: [:])?.count ?? 0
                }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(box.size, NSSize(width: 8, height: 8))
        XCTAssertEqual(box.pixels, 64)
        XCTAssertGreaterThan(box.png, 20, "encoding works there too")
    }

    /// `import AppKit` brings ImageIO into scope, as Apple's does (Nuke calls the C API
    /// through AppKit alone): `CGImageSource` resolves without an ImageIO import here.
    func testAppKitReExportsImageIO() {
        XCTAssertNotNil(CGImageSource.self)
    }

    /// SwiftUI-Introspect refines `NSViewControllerRepresentable` with its own
    /// `@MainActor` protocol and conforms a nonisolated struct to it. `View`,
    /// `NSViewControllerRepresentable` and `NSHostingContent` are `@preconcurrency`, so the
    /// conformance is accepted in the Swift 6 language mode.
    @MainActor
    protocol PlatformControllerRepresentable: NSViewControllerRepresentable {
        func makePlatformViewController(context: Context) -> NSViewControllerType
    }

    struct Anchor: PlatformControllerRepresentable {
        typealias NSViewControllerType = NSViewController
        func makePlatformViewController(context: Context) -> NSViewController {
            let c = NSViewController()
            c.view = NSView()
            return c
        }
        func makeNSViewController(context: Context) -> NSViewController { makePlatformViewController(context: context) }
        func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
    }

    func testLibraryRefinedRepresentableHosts() {
        MainActor.assumeIsolated {
            let (w, h) = host(Anchor().frame(width: 0, height: 0).accessibility(hidden: true))
            XCTAssertGreaterThan(allViews(h).count, 1)
            w.close()
        }
    }

    func testDeprecatedAccessibilitySpellingsApply() {
        MainActor.assumeIsolated {
            let (w, h) = host(VStack {
                Text("a").accessibility(label: Text("Label")).accessibility(identifier: "id")
                Text("b").accessibility(value: Text("Value")).accessibility(hint: Text("Hint"))
                Text("c").accessibility(hidden: true)
            })
            let texts = allViews(h).compactMap { $0 as? _TextView }
            XCTAssertEqual(texts.count, 3)
            XCTAssertEqual(texts[0].accessibilityLabel(), "Label")
            XCTAssertEqual(texts[0].accessibilityIdentifier(), "id")
            XCTAssertEqual(texts[1].accessibilityValue() as? String, "Value")
            XCTAssertEqual(texts[1].accessibilityHelp(), "Hint")
            XCTAssertTrue(texts[2].isAccessibilityHidden())
            w.close()
        }
    }
}
