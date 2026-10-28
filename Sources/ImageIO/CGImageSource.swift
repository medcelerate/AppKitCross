// CGImageSource (CGImageSource.h) over the platform codecs. A source holds the container
// bytes; images and properties come out of them on demand and are cached per index.

import Foundation
import CoreGraphics

public final class CGImageSource: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data
    private var isFinal: Bool
    private let typeHint: String?
    private var cachedImage: CGImage?
    private var decodeFailed = false

    init(data: Data, final: Bool, options: CFDictionary?) {
        self.data = data
        self.isFinal = final
        self.typeHint = (options?.imageIOValue(kCGImageSourceTypeIdentifierHint) as? String)
    }

    /// The container type, when sniffed and decodable here (the hint only breaks ties).
    var type: String? {
        lock.lock(); defer { lock.unlock() }
        return sniffedType()
    }

    private func sniffedType() -> String? {
        if let sniffed = ImageIOCodec.sniff(data), ImageIOCodec.canonicalType(sniffed, in: ImageIOCodec.decodableTypes) != nil { return sniffed }
        if let hint = typeHint, let canonical = ImageIOCodec.canonicalType(hint, in: ImageIOCodec.decodableTypes), !data.isEmpty { return canonical }
        return nil
    }

    var count: Int { type == nil ? 0 : 1 }

    var status: CGImageSourceStatus {
        lock.lock(); defer { lock.unlock() }
        if data.isEmpty { return isFinal ? .statusInvalidData : .statusReadingHeader }
        guard sniffedType() != nil else { return isFinal ? .statusInvalidData : .statusReadingHeader }
        if !isFinal { return .statusIncomplete }
        return decodeFailed ? .statusInvalidData : .statusComplete
    }

    func image(at index: Int) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard index == 0, sniffedType() != nil, !decodeFailed else { return nil }
        if let cachedImage { return cachedImage }
        guard let image = ImageIOCodec.decode(data) else { decodeFailed = true; return nil }
        cachedImage = image
        return image
    }

    func removeCache() {
        lock.lock(); defer { lock.unlock() }
        cachedImage = nil
    }

    func update(_ newData: Data, final: Bool) {
        lock.lock(); defer { lock.unlock() }
        data = newData
        isFinal = final
        cachedImage = nil
        decodeFailed = false
    }

    var snapshot: Data { lock.lock(); defer { lock.unlock() }; return data }
    var fileSize: Int { snapshot.count }

    func properties(at index: Int) -> NSDictionary? {
        guard index == 0, let type else { return nil }
        let props = NSMutableDictionary()
        func set(_ key: CFString, _ value: Any) { props.setObject(value, forKey: key) }
        if type == "public.png", let header = ImageIOCodec.pngHeader(snapshot) {
            set(kCGImagePropertyPixelWidth, header.width)
            set(kCGImagePropertyPixelHeight, header.height)
            set(kCGImagePropertyDepth, header.depth)
            set(kCGImagePropertyColorModel, header.colorModel)
            if let hasAlpha = header.hasAlpha { set(kCGImagePropertyHasAlpha, hasAlpha) }
            if header.isIndexed { set(kCGImagePropertyIsIndexed, true) }
            if let dpi = header.dpiWidth { set(kCGImagePropertyDPIWidth, dpi) }
            if let dpi = header.dpiHeight { set(kCGImagePropertyDPIHeight, dpi) }
            let png = NSMutableDictionary()
            if let gamma = header.pngGamma { png.setObject(gamma, forKey: kCGImagePropertyPNGGamma) }
            if let interlace = header.pngInterlace { png.setObject(interlace, forKey: kCGImagePropertyPNGInterlaceType) }
            if let ppm = header.pngPixelsPerMeter {
                png.setObject(ppm.x, forKey: kCGImagePropertyPNGXPixelsPerMeter)
                png.setObject(ppm.y, forKey: kCGImagePropertyPNGYPixelsPerMeter)
            }
            set(kCGImagePropertyPNGDictionary, png)
            return props
        }
        // Other containers: the decoded pixels describe the image.
        guard let image = image(at: 0) else { return nil }
        set(kCGImagePropertyPixelWidth, image.width)
        set(kCGImagePropertyPixelHeight, image.height)
        set(kCGImagePropertyDepth, image.bitsPerComponent)
        set(kCGImagePropertyColorModel, "RGB")
        set(kCGImagePropertyHasAlpha, image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast)
        return props
    }
}

private let cgImageSourceTypeID: CFTypeID = 0x494D4753   // 'IMGS'

public func CGImageSourceGetTypeID() -> CFTypeID { cgImageSourceTypeID }

/// The container types the platform decoder reads.
public func CGImageSourceCopyTypeIdentifiers() -> CFArray {
    NSArray(array: ImageIOCodec.decodableTypes.map { $0 as NSString })
}

public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? {
    CGImageSource(data: Data(referencing: data), final: true, options: options)
}

/// Reads the file at `url`; nil when it cannot be read.
public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? {
    guard let data = try? Data(contentsOf: url as URL) else { return nil }
    return CGImageSource(data: data, final: true, options: options)
}

public func CGImageSourceGetType(_ isrc: CGImageSource) -> CFString? {
    isrc.type.map { $0 as NSString }
}

public func CGImageSourceGetCount(_ isrc: CGImageSource) -> Int { isrc.count }

/// Container-level properties: the file size.
public func CGImageSourceCopyProperties(_ isrc: CGImageSource, _ options: CFDictionary?) -> CFDictionary? {
    let props = NSMutableDictionary()
    props.setObject(isrc.fileSize, forKey: kCGImagePropertyFileSize)
    return props
}

public func CGImageSourceCopyPropertiesAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CFDictionary? {
    isrc.properties(at: index)
}

public func CGImageSourceCreateImageAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    isrc.image(at: index)
}

public func CGImageSourceRemoveCacheAtIndex(_ isrc: CGImageSource, _ index: Int) {
    if index == 0 { isrc.removeCache() }
}

/// No supported container embeds thumbnails, so the thumbnail is the decoded image (as
/// Apple's ImageIO does for such files), scaled down to `kCGImageSourceThumbnailMaxPixelSize`
/// when given. `kCGImageSourceCreateThumbnailWithTransform` has nothing to apply: no
/// orientation metadata is read.
public func CGImageSourceCreateThumbnailAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? {
    guard let image = isrc.image(at: index) else { return nil }
    guard let maxSize = options?.imageIODouble(kCGImageSourceThumbnailMaxPixelSize) else { return image }
    return ImageIOCodec.scaled(image, maxPixelSize: Int(maxSize))
}

public func CGImageSourceCreateIncremental(_ options: CFDictionary?) -> CGImageSource {
    CGImageSource(data: Data(), final: false, options: options)
}

/// Replaces the source's bytes with `data`, which holds everything received so far.
public func CGImageSourceUpdateData(_ isrc: CGImageSource, _ data: CFData, _ final: Bool) {
    isrc.update(Data(referencing: data), final: final)
}

public func CGImageSourceGetStatus(_ isrc: CGImageSource) -> CGImageSourceStatus { isrc.status }

public func CGImageSourceGetStatusAtIndex(_ isrc: CGImageSource, _ index: Int) -> CGImageSourceStatus {
    index == 0 ? isrc.status : .statusUnknownType
}

public func CGImageSourceGetPrimaryImageIndex(_ isrc: CGImageSource) -> Int { 0 }

/// Auxiliary images (depth, matte, gain map) are not carried by any supported container.
public func CGImageSourceCopyAuxiliaryDataInfoAtIndex(_ isrc: CGImageSource, _ index: Int, _ auxiliaryImageDataType: CFString) -> CFDictionary? { nil }
