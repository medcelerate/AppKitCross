// ADR-0037: NSColorSpace over CGColorSpace, accessibility search keys and custom rotors,
// NSView's nested types in Core, and the generator rule that a nested type Core declares
// never reappears in a Generated/<Type>+Types.swift companion.
// Expected values come from AppKit on macOS 15 (probed with the real framework).

import XCTest
@testable import AppKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif

private func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.01) -> Bool { abs(a - b) <= tol }

final class ColorSpaceTests: XCTestCase {
    func testStandardSpacesMatchAppKit() {
        let expected: [(NSColorSpace, String, NSColorSpace.Model, Int, String)] = [
            (.sRGB, "sRGB IEC61966-2.1", .rgb, 3, "kCGColorSpaceSRGB"),
            (.extendedSRGB, "sRGB IEC61966-2.1", .rgb, 3, "kCGColorSpaceExtendedSRGB"),
            (.genericRGB, "Generic RGB", .rgb, 3, "kCGColorSpaceGenericRGB"),
            (.deviceRGB, "Device RGB", .rgb, 3, "kCGColorSpaceDeviceRGB"),
            (.displayP3, "Display P3", .rgb, 3, "kCGColorSpaceDisplayP3"),
            (.adobeRGB1998, "Adobe RGB (1998)", .rgb, 3, "kCGColorSpaceAdobeRGB1998"),
            (.genericGray, "Generic Gray", .gray, 1, "kCGColorSpaceGenericGray"),
            (.deviceGray, "Device Gray", .gray, 1, "kCGColorSpaceDeviceGray"),
            (.genericGamma22Gray, "Generic Gray Gamma 2.2 Profile", .gray, 1, "kCGColorSpaceGenericGrayGamma2_2"),
            (.extendedGenericGamma22Gray, "Generic Gray Gamma 2.2 Profile", .gray, 1, "kCGColorSpaceExtendedGray"),
            (.genericCMYK, "Generic CMYK", .cmyk, 4, "kCGColorSpaceGenericCMYK"),
            (.deviceCMYK, "Device CMYK", .cmyk, 4, "kCGColorSpaceDeviceCMYK"),
        ]
        for (space, name, model, count, cgName) in expected {
            XCTAssertEqual(space.localizedName, name)
            XCTAssertEqual(space.colorSpaceModel, model, name)
            XCTAssertEqual(space.numberOfColorComponents, count, name)
            let cg = space.cgColorSpace
            XCTAssertNotNil(cg, name)
            if let cg { XCTAssertEqual(_NSCGColorSpaceName(cg), cgName) }
        }
        XCTAssertEqual(NSColorSpace.sRGB.description, "sRGB IEC61966-2.1 colorspace")
        XCTAssertEqual(NSColorSpace.extendedSRGB.description, "sRGB IEC61966-2.1 (extended) colorspace")
        XCTAssertTrue(NSColorSpace.sRGB === NSColorSpace.sRGB)
        XCTAssertNotEqual(NSColorSpace.sRGB, NSColorSpace.genericRGB)
        XCTAssertNotEqual(NSColorSpace.deviceRGB, NSColorSpace.sRGB)
        XCTAssertTrue(NSColorSpace.supportsSecureCoding)
    }

    func testCGColorSpaceRoundTrip() throws {
        let cg = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let space = try XCTUnwrap(NSColorSpace(cgColorSpace: cg))
        XCTAssertEqual(space, NSColorSpace.sRGB)
        XCTAssertEqual(space.localizedName, "sRGB IEC61966-2.1")
        XCTAssertEqual(space.cgColorSpace, cg)
        let p3 = try XCTUnwrap(NSColorSpace(cgColorSpace: try XCTUnwrap(NSColorSpace.displayP3.cgColorSpace)))
        XCTAssertEqual(p3, NSColorSpace.displayP3)
        XCTAssertEqual(p3.hash, NSColorSpace.displayP3.hash)
        let gray = try XCTUnwrap(NSColorSpace(cgColorSpace: CGColorSpaceCreateDeviceGray()))
        XCTAssertEqual(gray, NSColorSpace.deviceGray)
    }

    func testICCProfileDataRoundTrips() throws {
        for space in [NSColorSpace.sRGB, .genericRGB, .displayP3, .adobeRGB1998, .genericGray, .genericGamma22Gray] {
            let data = try XCTUnwrap(space.iccProfileData, space.localizedName ?? "")
            XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "acsp")
            let back = try XCTUnwrap(NSColorSpace(iccProfileData: data))
            XCTAssertEqual(back, space, space.localizedName ?? "")
            XCTAssertEqual(back.localizedName, space.localizedName)
            XCTAssertEqual(back.numberOfColorComponents, space.numberOfColorComponents)
        }
        // Device spaces have no profile, as in AppKit; the port has no CMYK profile either.
        XCTAssertNil(NSColorSpace.deviceRGB.iccProfileData)
        XCTAssertNil(NSColorSpace.deviceGray.iccProfileData)
        XCTAssertNil(NSColorSpace.genericCMYK.iccProfileData)
        XCTAssertNil(NSColorSpace(iccProfileData: Data([1, 2, 3])))
    }

    func testCustomICCProfileKeepsItsBytes() throws {
        // A profile that is not a standard one: sRGB colorants with a 1.0 gamma and another name.
        var p = _NSStandardColorSpace.sRGB.profile
        p.name = "Linear Test"
        p.curves = [.gamma(1), .gamma(1), .gamma(1)]
        let data = try XCTUnwrap(_NSICCProfile.write(p))
        let space = try XCTUnwrap(NSColorSpace(iccProfileData: data))
        XCTAssertEqual(space.localizedName, "Linear Test")
        XCTAssertEqual(space.colorSpaceModel, .rgb)
        XCTAssertEqual(space.iccProfileData, data)
        XCTAssertNotEqual(space, NSColorSpace.sRGB)
        let mid = try XCTUnwrap(NSColorSpace.sRGB._convert([0.5, 0.5, 0.5], to: space))
        XCTAssertTrue(near(mid[0], 0.214), "\(mid)")
    }

    func testConversionsAgreeWithAppKit() throws {
        let p3 = try XCTUnwrap(NSColorSpace.sRGB._convert([1, 0, 0], to: .displayP3))
        XCTAssertTrue(near(p3[0], 0.9175) && near(p3[1], 0.2004) && near(p3[2], 0.1385), "\(p3)")
        let mid = try XCTUnwrap(NSColorSpace.sRGB._convert([0.2, 0.5, 0.8], to: .displayP3))
        XCTAssertTrue(near(mid[0], 0.2833) && near(mid[1], 0.4934) && near(mid[2], 0.7772), "\(mid)")
        let adobe = try XCTUnwrap(NSColorSpace.sRGB._convert([0.2, 0.5, 0.8], to: .adobeRGB1998))
        XCTAssertTrue(near(adobe[0], 0.3255) && near(adobe[1], 0.4962) && near(adobe[2], 0.7854), "\(adobe)")
        let gray = try XCTUnwrap(NSColorSpace.sRGB._convert([0.5, 0.5, 0.5], to: .genericGray))
        XCTAssertTrue(near(gray[0], 0.4247), "\(gray)")
        let fromGray = try XCTUnwrap(NSColorSpace.genericGamma22Gray._convert([0.5], to: .sRGB))
        XCTAssertTrue(fromGray.allSatisfy { near($0, 0.5) }, "\(fromGray)")
        let back = try XCTUnwrap(NSColorSpace.displayP3._convert(p3, to: .sRGB))
        XCTAssertTrue(near(back[0], 1) && near(back[1], 0) && near(back[2], 0), "\(back)")
        let cmyk = try XCTUnwrap(NSColorSpace.sRGB._convert([1, 0, 0], to: .deviceCMYK))
        XCTAssertEqual(cmyk.count, 4)
        XCTAssertNil(NSColorSpace.sRGB._convert([1, 0], to: .displayP3))
    }

    func testAvailableColorSpaces() {
        XCTAssertEqual(NSColorSpace.availableColorSpaces(with: .rgb).compactMap(\.localizedName),
                       ["Adobe RGB (1998)", "Device RGB", "Display P3", "Generic RGB", "sRGB IEC61966-2.1"])
        XCTAssertEqual(NSColorSpace.availableColorSpaces(with: .gray).compactMap(\.localizedName),
                       ["Device Gray", "Generic Gray", "Generic Gray Gamma 2.2 Profile"])
        XCTAssertEqual(NSColorSpace.availableColorSpaces(with: .cmyk).compactMap(\.localizedName), ["Device CMYK", "Generic CMYK"])
        XCTAssertEqual(NSColorSpace.availableColorSpaces(with: .unknown).count, 10)
        XCTAssertTrue(NSColorSpace.availableColorSpaces(with: .lab).isEmpty)
    }

    func testSecureCodingRoundTrip() throws {
        for space in [NSColorSpace.displayP3, .genericGray] {
            let data = try NSKeyedArchiver.archivedData(withRootObject: space, requiringSecureCoding: true)
            let back = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: NSColorSpace.self, from: data))
            XCTAssertEqual(back, space)
        }
    }

    func testBitmapImageRepColorSpaces() throws {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1, bitsPerSample: 8,
                                                 samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                                 colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        XCTAssertEqual(rep.colorSpace, NSColorSpace.genericRGB)
        var px = [255, 0, 0]
        rep.setPixel(&px, atX: 0, y: 0)
        let retagged = try XCTUnwrap(rep.retagging(with: .sRGB))
        XCTAssertEqual(retagged.colorSpace, NSColorSpace.sRGB)
        var out = [0, 0, 0]
        retagged.getPixel(&out, atX: 0, y: 0)
        XCTAssertEqual(out, [255, 0, 0])
        XCTAssertNil(rep.retagging(with: .genericGray))
        let p3 = try XCTUnwrap(retagged.converting(to: .displayP3, renderingIntent: .default))
        XCTAssertEqual(p3.colorSpace, NSColorSpace.displayP3)
        XCTAssertEqual(p3.samplesPerPixel, 3)
        p3.getPixel(&out, atX: 0, y: 0)
        XCTAssertEqual(out[0], 234, accuracy: 3)
        XCTAssertEqual(out[1], 51, accuracy: 3)
        XCTAssertEqual(out[2], 35, accuracy: 3)
        let gray = try XCTUnwrap(retagged.converting(to: .genericGamma22Gray, renderingIntent: .default))
        XCTAssertEqual(gray.samplesPerPixel, 1)
        XCTAssertNil(retagged.converting(to: .genericCMYK, renderingIntent: .default))
    }

    func testScreenColorSpace() throws {
        try MainActor.assumeIsolated {
            guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
            XCTAssertEqual(screen.colorSpace, NSColorSpace.sRGB)
            XCTAssertTrue(screen.canRepresent(.sRGB))
            XCTAssertFalse(screen.canRepresent(.p3))
        }
    }
}

/// NSAccessibilityElement adopts NSAccessibility but not NSAccessibilityElementProtocol (as
/// in AppKit), so rotor targets are a subclass that adopts it.
private final class RotorItem: NSAccessibilityElement, NSAccessibilityElementProtocol {}

private final class RotorSearch: NSObject, NSAccessibilityCustomRotorItemSearchDelegate {
    let items: [RotorItem]
    var last: NSAccessibilityCustomRotor.SearchParameters?
    init(_ items: [RotorItem]) { self.items = items }
    func rotor(_ rotor: NSAccessibilityCustomRotor, resultFor searchParameters: NSAccessibilityCustomRotor.SearchParameters) -> NSAccessibilityCustomRotor.ItemResult? {
        last = searchParameters
        let matching = items.filter { searchParameters.filterString.isEmpty || ($0.accessibilityLabel() ?? "").contains(searchParameters.filterString) }
        let current = searchParameters.currentItem?.targetElement as? RotorItem
        let index = current.flatMap { c in matching.firstIndex { $0 === c } }
        let next: Int
        switch searchParameters.searchDirection {
        case .next: next = index.map { $0 + 1 } ?? 0
        case .previous: next = index.map { $0 - 1 } ?? matching.count - 1
        }
        guard matching.indices.contains(next) else { return nil }
        let r = NSAccessibilityCustomRotor.ItemResult(targetElement: matching[next])
        r.customLabel = matching[next].accessibilityLabel()
        return r
    }
}

final class AccessibilityRotorTests: XCTestCase {
    func testSearchKeyValues() throws {
        // macOS 26 constants: they run on Windows and Linux (no availability there) and on a
        // macOS 26 host.
        guard #available(macOS 26.0, *) else { throw XCTSkip("NSAccessibilitySearchKey constants are macOS 26 API") }
        XCTAssertEqual(NSAccessibilitySearchKey.anyTypeSearchKey.rawValue, "AXAnyTypeSearchKey")
        XCTAssertEqual(NSAccessibilitySearchKey.blockquoteSameLevelSearchKey.rawValue, "AXBlockquoteSameLevelSearchKey")
        XCTAssertEqual(NSAccessibilitySearchKey.headingLevel3SearchKey.rawValue, "AXHeadingLevel3SearchKey")
        XCTAssertEqual(NSAccessibilitySearchKey.checkBoxSearchKey.rawValue, "AXCheckBoxSearchKey")
        XCTAssertEqual(NSAccessibilitySearchKey.misspelledWordSearchKey.rawValue, "AXMisspelledWordSearchKey")
        XCTAssertEqual(NSAccessibilitySearchKey.unvisitedLinkSearchKey.rawValue, "AXUnvisitedLinkSearchKey")
        XCTAssertEqual(NSAccessibilitySearchKey.textStateChangeTypeKey.rawValue, "AXTextStateChangeType")
        XCTAssertEqual(NSAccessibilitySearchKey.textStateSyncKey.rawValue, "AXTextStateSync")
    }

    func testRotorModel() {
        let search = RotorSearch([])
        let custom = NSAccessibilityCustomRotor(label: "Errors", itemSearchDelegate: search)
        XCTAssertEqual(custom.label, "Errors")
        XCTAssertEqual(custom.type, .custom)
        XCTAssertTrue(custom.itemSearchDelegate === search)
        let headings = NSAccessibilityCustomRotor(rotorType: .heading, itemSearchDelegate: search)
        XCTAssertEqual(headings.type, .heading)
        XCTAssertEqual(headings.label, "")
        headings.label = "Sections"
        headings.type = .headingLevel2
        XCTAssertEqual(headings.label, "Sections")
        XCTAssertEqual(headings.type, .headingLevel2)

        let params = NSAccessibilityCustomRotor.SearchParameters()
        XCTAssertNil(params.currentItem)
        XCTAssertEqual(params.searchDirection, .previous)
        XCTAssertEqual(params.filterString, "")

        let token = NSString(string: "row-7")
        let pending = NSAccessibilityCustomRotor.ItemResult(itemLoadingToken: token, customLabel: "Row 7")
        XCTAssertEqual(pending.customLabel, "Row 7")
        XCTAssertTrue(pending.itemLoadingToken === token)
        XCTAssertNil(pending.targetElement)
        pending.targetRange = NSRange(location: 3, length: 4)
        XCTAssertEqual(pending.targetRange, NSRange(location: 3, length: 4))
    }

    func testRotorDelegateIsWeak() {
        var search: RotorSearch? = RotorSearch([])
        let rotor = NSAccessibilityCustomRotor(label: "Weak", itemSearchDelegate: search!)
        XCTAssertNotNil(rotor.itemSearchDelegate)
        search = nil
        XCTAssertNil(rotor.itemSearchDelegate)
    }

    func testRotorRegisteredOnViewAndSearched() throws {
        try MainActor.assumeIsolated {
            let items = ["Intro", "Usage", "Usage notes"].map { label -> RotorItem in
                let e = RotorItem()
                e.setAccessibilityLabel(label)
                e.setAccessibilityRole(.staticText)
                return e
            }
            let search = RotorSearch(items)
            let rotor = NSAccessibilityCustomRotor(label: "Sections", itemSearchDelegate: search)
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            XCTAssertTrue(view.accessibilityCustomRotors().isEmpty)
            view.setAccessibilityCustomRotors([rotor])
            let registered = try XCTUnwrap(view.accessibilityCustomRotors().first)
            XCTAssertTrue(registered === rotor)

            let params = NSAccessibilityCustomRotor.SearchParameters()
            params.searchDirection = .next
            params.filterString = "Usage"
            let first = try XCTUnwrap(registered.itemSearchDelegate?.rotor(registered, resultFor: params))
            XCTAssertEqual(first.customLabel, "Usage")
            XCTAssertTrue(search.last === params)
            params.currentItem = first
            let second = try XCTUnwrap(registered.itemSearchDelegate?.rotor(registered, resultFor: params))
            XCTAssertEqual(second.customLabel, "Usage notes")
            params.currentItem = second
            XCTAssertNil(registered.itemSearchDelegate?.rotor(registered, resultFor: params))

            let element = NSAccessibilityElement()
            element.setAccessibilityCustomRotors([rotor])
            XCTAssertEqual(element.accessibilityCustomRotors().count, 1)
        }
    }
}

private final class InvalidatingView: NSView {
    @NSView.Invalidating(.display) var tint: Int = 0
    @NSView.Invalidating(.layout, .intrinsicContentSize) var spacing: CGFloat = 4
}

final class NSViewNestedTypesTests: XCTestCase {
    func testInvalidatingWrapperRunsInvalidations() {
        MainActor.assumeIsolated {
            let v = InvalidatingView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            v.needsDisplay = false
            v.needsLayout = false
            v.tint = 0                // unchanged: nothing invalidated
            XCTAssertFalse(v.needsDisplay)
            v.tint = 3
            XCTAssertEqual(v.tint, 3)
            XCTAssertTrue(v.needsDisplay)
            v.spacing = 8
            XCTAssertEqual(v.spacing, 8)
            XCTAssertTrue(v.needsLayout)
        }
    }

    func testLayoutRegions() throws {
        try MainActor.assumeIsolated {
            guard #available(macOS 26.0, *) else { throw XCTSkip("NSView.LayoutRegion is macOS 26 API") }
            let v = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
            XCTAssertEqual(NSView.LayoutRegion.safeArea(), NSView.LayoutRegion.safeArea(cornerAdaptation: nil))
            XCTAssertNotEqual(NSView.LayoutRegion.safeArea(), NSView.LayoutRegion.margins())
            XCTAssertNotEqual(NSView.LayoutRegion.safeArea(cornerAdaptation: .horizontal), NSView.LayoutRegion.safeArea(cornerAdaptation: .vertical))
            XCTAssertEqual(Set([NSView.LayoutRegion.margins(), .margins()]).count, 1)
            XCTAssertEqual(v.rect(for: .safeArea()), v.bounds)
            XCTAssertEqual(v.edgeInsets(for: .margins()).left, 0)
            XCTAssertTrue(v.layoutGuide(for: .safeArea()) === v.safeAreaLayoutGuide)
            XCTAssertTrue(v.layoutGuide(for: .margins()) === v.layoutMarginsGuide)
        }
    }

    func testValueTypes() {
        XCTAssertEqual(NSView.BackgroundStyle.dark, .emphasized)
        XCTAssertEqual(NSView.AutoresizingMask([.width, .height]).rawValue, 18)
        XCTAssertEqual(NSView.LayerContentsPlacement.topLeft.rawValue, 11)
        XCTAssertEqual(NSView.FullScreenModeOptionKey.fullScreenModeAllScreens.rawValue, "NSFullScreenModeAllScreens")
    }
}

/// The generator rule (ADR-0037): a nested type that Sources/AppKit/Core declares is never
/// emitted again in Sources/AppKit/Generated/<Type>+Types.swift. Mirrors
/// `Generator.core_nested_types()` in tools/apigen/apigen.py over the checked-in sources, so
/// a regeneration that brought a stray companion back would fail here as well as in the build.
final class GeneratorDriftTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// "Parent.Name" for each type declared at depth 1 inside a top-level class/extension.
    private func nestedTypes(in text: String) -> Set<String> {
        var found = Set<String>()
        var depth = 0
        var container: String?
        let containerRE = try! NSRegularExpression(pattern: #"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:open|public|internal|fileprivate|private|final)\s+)*(?:class|struct|enum|extension)\s+([A-Za-z_][\w.]*)"#)
        let typeRE = try! NSRegularExpression(pattern: #"^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:open|public|internal|fileprivate|private|final|indirect)\s+)*(?:struct|enum|class|protocol|typealias|actor)\s+([A-Za-z_]\w*)\b"#)
        func first(_ re: NSRegularExpression, _ s: String) -> String? {
            guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let r = Range(m.range(at: 1), in: s) else { return nil }
            return String(s[r])
        }
        // CRLF checkouts (core.autocrlf on Windows): "\r\n" is one Character in Swift, so a
        // split on "\n" alone would see the whole file as a single line.
        for line in text.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.hasPrefix("//") { continue }
            if depth == 0 { container = first(containerRE, stripped) }
            else if depth == 1, let c = container, let n = first(typeRE, stripped) { found.insert(c + "." + n) }
            let code = line.components(separatedBy: "//")[0]
            depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
        }
        return found
    }

    private func swiftFiles(_ dir: URL) -> [URL] {
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        return (e?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    func testNoTypesCompanionRedeclaresACoreNestedType() throws {
        let core = root.appendingPathComponent("Sources/AppKit/Core")
        let generated = root.appendingPathComponent("Sources/AppKit/Generated")
        guard FileManager.default.fileExists(atPath: core.path) else { throw XCTSkip("sources not next to the tests") }
        var coreTypes = Set<String>()
        for f in swiftFiles(core) { coreTypes.formUnion(nestedTypes(in: try String(contentsOf: f, encoding: .utf8))) }
        XCTAssertTrue(coreTypes.contains("NSToolbar.DisplayMode"))
        XCTAssertTrue(coreTypes.contains("NSView.Invalidations"))
        for f in swiftFiles(generated) where f.lastPathComponent.hasSuffix("+Types.swift") {
            let dup = nestedTypes(in: try String(contentsOf: f, encoding: .utf8)).intersection(coreTypes)
            XCTAssertTrue(dup.isEmpty, "\(f.lastPathComponent) re-emits \(dup.sorted()) that Core declares")
        }
        for name in ["NSView", "NSColorSpace", "NSAccessibilityCustomRotor", "NSToolbar", "NSBrowser", "NSMatrix",
                     "NSGestureRecognizer", "NSStatusItem", "NSToolbarItem", "NSToolbarItemGroup"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: generated.appendingPathComponent(name + "+Types.swift").path), name)
        }
    }
}
