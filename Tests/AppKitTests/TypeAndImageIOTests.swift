// UniformTypeIdentifiers and ImageIO behaviour that must hold on every platform: on macOS
// these run against Apple's modules (the specification), on Windows and Linux against
// the package's (ADR-0009).

import XCTest
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
final class UTTypeTests: XCTestCase {
    func testCoreTypeIdentifiersAndTags() {
        XCTAssertEqual(UTType.png.identifier, "public.png")
        XCTAssertEqual(UTType.png.preferredFilenameExtension, "png")
        XCTAssertEqual(UTType.png.preferredMIMEType, "image/png")
        XCTAssertEqual(UTType.jpeg.identifier, "public.jpeg")
        XCTAssertEqual(UTType.jpeg.preferredFilenameExtension, "jpeg")
        XCTAssertEqual(Set(UTType.jpeg.tags[.filenameExtension] ?? []), ["jpeg", "jpg", "jpe"])
        XCTAssertEqual(UTType.plainText.identifier, "public.plain-text")
        XCTAssertEqual(UTType.folder.identifier, "public.folder")
        XCTAssertEqual(UTType.pdf.identifier, "com.adobe.pdf")
        XCTAssertEqual(UTType.swiftSource.preferredFilenameExtension, "swift")
        XCTAssertEqual(UTType.json.preferredMIMEType, "application/json")
        XCTAssertEqual(UTType.image.localizedDescription, "image")
        XCTAssertTrue(UTType.png.isPublic)
        XCTAssertTrue(UTType.png.isDeclared)
        XCTAssertFalse(UTType.png.isDynamic)
        XCTAssertFalse(UTType.pdf.isPublic)
        XCTAssertEqual(UTType.png.description, "public.png")
        XCTAssertEqual("\(UTType.png)", "public.png")
    }

    func testLookupByExtensionAndMIMEType() {
        XCTAssertEqual(UTType(filenameExtension: "png"), .png)
        XCTAssertEqual(UTType(filenameExtension: "PNG"), .png)
        XCTAssertEqual(UTType(filenameExtension: "jpg"), .jpeg)
        XCTAssertEqual(UTType(filenameExtension: "txt"), .plainText)
        XCTAssertEqual(UTType(filenameExtension: "swift"), .swiftSource)
        XCTAssertEqual(UTType(mimeType: "image/png"), .png)
        XCTAssertEqual(UTType(mimeType: "image/jpeg"), .jpeg)
        XCTAssertEqual(UTType(mimeType: "text/html"), .html)
        XCTAssertEqual(UTType(tag: "gif", tagClass: .filenameExtension, conformingTo: nil), .gif)
        XCTAssertEqual(UTType(tag: "application/pdf", tagClass: .mimeType, conformingTo: .data), .pdf)
        // A declared extension that does not conform to the requested supertype yields a dynamic type.
        let pngAsText = UTType(filenameExtension: "png", conformingTo: .text)
        XCTAssertEqual(pngAsText?.identifier, "dyn.ah62d4r34ge81a5xh")
        XCTAssertEqual(pngAsText?.isDynamic, true)
        XCTAssertEqual(UTType.types(tag: "jpg", tagClass: .filenameExtension, conformingTo: nil), [.jpeg])
        XCTAssertEqual(UTType("public.png"), .png)
        XCTAssertNil(UTType("public.no-such-type-anywhere"))
    }

    func testConformance() {
        XCTAssertTrue(UTType.png.conforms(to: .image))
        XCTAssertTrue(UTType.image.conforms(to: .data))
        XCTAssertTrue(UTType.png.conforms(to: .data))
        XCTAssertTrue(UTType.png.conforms(to: .item))
        XCTAssertTrue(UTType.png.conforms(to: .png))
        XCTAssertFalse(UTType.png.conforms(to: .text))
        XCTAssertFalse(UTType.image.conforms(to: .png))
        XCTAssertTrue(UTType.swiftSource.conforms(to: .sourceCode))
        XCTAssertTrue(UTType.sourceCode.conforms(to: .plainText))
        XCTAssertTrue(UTType.folder.conforms(to: .directory))
        XCTAssertTrue(UTType.image.isSupertype(of: .png))
        XCTAssertTrue(UTType.png.isSubtype(of: .image))
        XCTAssertFalse(UTType.png.isSupertype(of: .png))
        XCTAssertFalse(UTType.png.isSubtype(of: .png))
        XCTAssertTrue(UTType.png.supertypes.contains(.image))
        XCTAssertTrue(UTType.png.supertypes.contains(.data))
        XCTAssertTrue(UTType.png.supertypes.contains(.item))
        XCTAssertFalse(UTType.png.supertypes.contains(.png))
        XCTAssertTrue(UTType.item.supertypes.isEmpty)
    }

    func testDynamicTypes() throws {
        let dynamic = try XCTUnwrap(UTType(filenameExtension: "zzqx"))
        XCTAssertTrue(dynamic.isDynamic)
        XCTAssertFalse(dynamic.isDeclared)
        XCTAssertFalse(dynamic.isPublic)
        XCTAssertTrue(dynamic.identifier.hasPrefix("dyn."))
        XCTAssertEqual(dynamic.identifier, "dyn.ah62d4rv4ge81y8xvta")   // Apple's encoding of ?0=6:1=zzqx
        XCTAssertEqual(dynamic.preferredFilenameExtension, "zzqx")
        XCTAssertNil(dynamic.preferredMIMEType)
        XCTAssertTrue(dynamic.conforms(to: .data))
        XCTAssertFalse(dynamic.conforms(to: .image))
        XCTAssertEqual(dynamic.tags[.filenameExtension], ["zzqx"])
        XCTAssertEqual(UTType(filenameExtension: "zzqx"), dynamic)
        XCTAssertEqual(UTType(dynamic.identifier), dynamic)

        let image = try XCTUnwrap(UTType(filenameExtension: "zzqx", conformingTo: .image))
        XCTAssertEqual(image.identifier, "dyn.ah62d4uv4ge81y8xvta")
        XCTAssertTrue(image.conforms(to: .image))
        XCTAssertNotEqual(image, dynamic)

        let mime = try XCTUnwrap(UTType(mimeType: "application/x-zzqx"))
        XCTAssertEqual(mime.identifier, "dyn.ah62d4rv4gq80c6durvy0g2pyrf106p52fz7hy6p2")
        XCTAssertEqual(mime.preferredMIMEType, "application/x-zzqx")
        XCTAssertNil(mime.preferredFilenameExtension)

        let untyped = try XCTUnwrap(UTType(tag: "zzqx", tagClass: .filenameExtension, conformingTo: nil))
        XCTAssertEqual(untyped.identifier, "dyn.age81y8xvta")
        XCTAssertEqual(UTType("dyn.age81y8xvta")?.preferredFilenameExtension, "zzqx")
    }

    func testDeclaredAppTypes() {
        let exported = UTType(exportedAs: "com.appkitwin.test-document", conformingTo: .data)
        XCTAssertEqual(exported.identifier, "com.appkitwin.test-document")
        XCTAssertTrue(exported.isDeclared)
        XCTAssertFalse(exported.isDynamic)
        XCTAssertFalse(exported.isPublic)
        let imported = UTType(importedAs: "com.appkitwin.other-document")
        XCTAssertEqual(imported.identifier, "com.appkitwin.other-document")
        XCTAssertTrue(imported.isDeclared)
    }

    func testHashableAndCodable() throws {
        var set: Set<UTType> = [.png, .jpeg, .png]
        XCTAssertEqual(set.count, 2)
        set.insert(UTType("public.png")!)
        XCTAssertEqual(set.count, 2)

        let encoded = try JSONEncoder().encode([UTType.png, .plainText, UTType(filenameExtension: "zzqx")!])
        let decoded = try JSONDecoder().decode([UTType].self, from: encoded)
        XCTAssertEqual(decoded, [.png, .plainText, UTType(filenameExtension: "zzqx")!])
        XCTAssertEqual(decoded[0].preferredFilenameExtension, "png")
        XCTAssertTrue(decoded[0].conforms(to: .image))
        // The plain identifier string decodes too, whichever platform wrote it.
        let fromString = try JSONDecoder().decode(UTType.self, from: Data("\"public.jpeg\"".utf8))
        XCTAssertEqual(fromString, .jpeg)
    }

    func testURLAdditions() {
        let base = URL(fileURLWithPath: "/tmp/dir")
        XCTAssertEqual(base.appendingPathExtension(for: .png).lastPathComponent, "dir.png")
        XCTAssertEqual(base.appendingPathComponent("picture", conformingTo: .png).lastPathComponent, "picture.png")
        XCTAssertEqual(base.appendingPathComponent("picture.png", conformingTo: .image).lastPathComponent, "picture.png")
        XCTAssertEqual(base.appendingPathComponent("notes.txt", conformingTo: .png).lastPathComponent, "notes.txt.png")
    }
}
#endif

#if canImport(ImageIO) && canImport(CoreGraphics)
final class ImageIOTests: XCTestCase {
    /// A 4x3 bitmap: red with the bottom-right pixel blue, as a premultiplied BGRA CGImage.
    private func makeImage() throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 3, y: 0, width: 1, height: 1))     // bottom-right in CG coordinates
        return try XCTUnwrap(ctx.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        #if os(Windows) || os(Linux)
        let data = image.data
        #else
        let data = image.dataProvider!.data! as Data
        #endif
        let little = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue
        let i = y * image.bytesPerRow + x * 4
        let alphaFirst = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first || image.alphaInfo == .noneSkipFirst
        if little && alphaFirst { return (data[i + 2], data[i + 1], data[i], data[i + 3]) }      // BGRA
        if !little && !alphaFirst { return (data[i], data[i + 1], data[i + 2], data[i + 3]) }    // RGBA
        if !little && alphaFirst { return (data[i + 1], data[i + 2], data[i + 3], data[i]) }     // ARGB
        return (data[i + 3], data[i + 2], data[i + 1], data[i])                                   // ABGR
    }

    func testTypeIdentifiers() {
        let sources = CGImageSourceCopyTypeIdentifiers() as NSArray as! [String]
        let destinations = CGImageDestinationCopyTypeIdentifiers() as NSArray as! [String]
        XCTAssertTrue(sources.contains("public.png"))
        XCTAssertTrue(destinations.contains("public.png"))
        XCTAssertNil(CGImageDestinationCreateWithData(NSMutableData() as CFMutableData, "public.no-such-image" as CFString, 1, nil))
    }

    func testPNGRoundTripThroughDestinationAndSource() throws {
        let image = try makeImage()
        let out = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertGreaterThan(out.length, 8)
        let bytes = out as Data
        XCTAssertEqual([UInt8](bytes.prefix(4)), [0x89, 0x50, 0x4E, 0x47])

        let source = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, "public.png")
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        XCTAssertEqual(CGImageSourceGetStatus(source), .statusComplete)

        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 4)
        XCTAssertEqual(decoded.height, 3)
        let red = pixel(decoded, x: 0, y: 0), blue = pixel(decoded, x: 3, y: 2)
        XCTAssertEqual([red.r, red.g, red.b, red.a], [255, 0, 0, 255])
        XCTAssertEqual([blue.r, blue.g, blue.b, blue.a], [0, 0, 255, 255])

        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)) as NSDictionary
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth as String] as? Int, 4)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight as String] as? Int, 3)
        XCTAssertEqual(properties[kCGImagePropertyDepth as String] as? Int, 8)
        XCTAssertEqual(properties[kCGImagePropertyColorModel as String] as? String, kCGImagePropertyColorModelRGB as String)
        XCTAssertNotNil(properties[kCGImagePropertyPNGDictionary as String])
        let container = try XCTUnwrap(CGImageSourceCopyProperties(source, nil)) as NSDictionary
        XCTAssertEqual(container[kCGImagePropertyFileSize as String] as? Int, out.length)
    }

    func testFileURLDestinationAndSource() throws {
        let image = try makeImage()
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("appkitwin-imageio-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality as String: 0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, "public.png")
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 4)
        XCTAssertEqual(decoded.height, 3)
    }

    func testInvalidDataHasNoImages() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(Data([1, 2, 3, 4]) as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 0)
        XCTAssertNil(CGImageSourceGetType(source))
        XCTAssertNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(CGImageSourceGetStatus(source), .statusInvalidData)
    }

    func testThumbnailFromImage() throws {
        let image = try makeImage()
        let out = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let full = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, nil))   // nothing embedded: the image itself
        XCTAssertEqual(full.width, 4)
        let options = [kCGImageSourceCreateThumbnailFromImageAlways as String: true, kCGImageSourceThumbnailMaxPixelSize as String: 2] as CFDictionary
        let thumbnail = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, options))
        XCTAssertEqual(thumbnail.width, 2)
        XCTAssertLessThanOrEqual(thumbnail.height, 2)
    }
}
#endif
