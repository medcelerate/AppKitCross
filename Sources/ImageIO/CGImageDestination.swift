// CGImageDestination (CGImageDestination.h) over the platform encoders. Images are
// collected by `AddImage` and written by `Finalize`, to the mutable data or the file URL
// the destination was created with.

import Foundation
import CoreGraphics

public final class CGImageDestination: @unchecked Sendable {
    enum Output {
        case data(NSMutableData)
        case url(URL)
    }

    private let lock = NSLock()
    let output: Output
    let type: String
    let count: Int
    private var properties: NSDictionary?
    private var images: [(image: CGImage, properties: NSDictionary?)] = []
    private var finalized = false

    init(output: Output, type: String, count: Int, options: CFDictionary?) {
        self.output = output
        self.type = type
        self.count = count
        self.properties = options
    }

    func setProperties(_ props: NSDictionary?) {
        lock.lock(); defer { lock.unlock() }
        properties = props
    }

    func add(_ image: CGImage, properties props: NSDictionary?) {
        lock.lock(); defer { lock.unlock() }
        guard !finalized, images.count < count else { return }
        images.append((image, props))
    }

    /// Encodes the first image (every supported container holds one) and writes it out.
    func finalize() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finalized, let first = images.first else { return false }
        finalized = true
        let quality = first.properties?.imageIODouble(kCGImageDestinationLossyCompressionQuality)
            ?? properties?.imageIODouble(kCGImageDestinationLossyCompressionQuality) ?? 1.0
        var image = first.image
        if let maxSize = first.properties?.imageIODouble(kCGImageDestinationImageMaxPixelSize) ?? properties?.imageIODouble(kCGImageDestinationImageMaxPixelSize),
           let scaled = ImageIOCodec.scaled(image, maxPixelSize: Int(maxSize)) {
            image = scaled
        }
        guard let encoded = ImageIOCodec.encode(image, type: type, quality: min(1, max(0, quality))) else { return false }
        switch output {
        case .data(let data): data.append(encoded)
        case .url(let url):
            do { try encoded.write(to: url) } catch { return false }
        }
        return true
    }
}

private let cgImageDestinationTypeID: CFTypeID = 0x494D4744   // 'IMGD'

public func CGImageDestinationGetTypeID() -> CFTypeID { cgImageDestinationTypeID }

/// The container types the platform encoder writes.
public func CGImageDestinationCopyTypeIdentifiers() -> CFArray {
    NSArray(array: ImageIOCodec.encodableTypes.map { $0 as NSString })
}

public func CGImageDestinationCreateWithData(_ data: CFMutableData, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? {
    guard count > 0, let canonical = ImageIOCodec.canonicalType(type as String, in: ImageIOCodec.encodableTypes) else { return nil }
    return CGImageDestination(output: .data(data), type: canonical, count: count, options: options)
}

public func CGImageDestinationCreateWithURL(_ url: CFURL, _ type: CFString, _ count: Int, _ options: CFDictionary?) -> CGImageDestination? {
    guard count > 0, let canonical = ImageIOCodec.canonicalType(type as String, in: ImageIOCodec.encodableTypes) else { return nil }
    return CGImageDestination(output: .url(url as URL), type: canonical, count: count, options: options)
}

public func CGImageDestinationSetProperties(_ idst: CGImageDestination, _ properties: CFDictionary?) {
    idst.setProperties(properties)
}

public func CGImageDestinationAddImage(_ idst: CGImageDestination, _ image: CGImage, _ properties: CFDictionary?) {
    idst.add(image, properties: properties)
}

public func CGImageDestinationAddImageFromSource(_ idst: CGImageDestination, _ isrc: CGImageSource, _ index: Int, _ properties: CFDictionary?) {
    guard let image = isrc.image(at: index) else { return }
    idst.add(image, properties: properties)
}

public func CGImageDestinationFinalize(_ idst: CGImageDestination) -> Bool { idst.finalize() }
