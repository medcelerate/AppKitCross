// NSBitmapImageRep (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(QuartzCore)
import QuartzCore
#endif
#if canImport(CoreText)
import CoreText
#endif
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep
open class NSBitmapImageRep: NSImageRep, NSSecureCoding {
    // MARK: Storage
    private var _image: CGImage?
    private var _bitmapFormat: NSBitmapImageRep.Format = []

    @MainActor internal override func _cgImage() -> CGImage? { _image }
    /// The decoded pixels, readable from any thread (a bitmap rep renders nothing).
    internal var _bitmapImage: CGImage? { _image }

    private func _adopt(_ image: CGImage) {
        _image = image
        _pixelsWide = image.width
        _pixelsHigh = image.height
        _size = NSSize(width: image.width, height: image.height)
        _hasAlpha = image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast
        _bitsPerSample = image.bitsPerComponent
    }

    /// Decodes with the platform image codec, on the calling thread as Apple's does.
    public convenience init?(data: Data) {
        guard let image = Platform.imageCodec.decode(data) else { return nil }
        self.init(cgImage: image)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(bitmapdataplanes:pixelswide:pixelshigh:bitspersample:samplesperpixel:hasalpha:isplanar:colorspacename:bitmapformat:bytesperrow:bitsperpixel:)
    public init?(bitmapDataPlanes planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide width: Int, pixelsHigh height: Int, bitsPerSample bps: Int, samplesPerPixel spp: Int, hasAlpha alpha: Bool, isPlanar: Bool, colorSpaceName: NSColorSpaceName, bitmapFormat: NSBitmapImageRep.Format, bytesPerRow rBytes: Int, bitsPerPixel pBits: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(bitmapdataplanes:pixelswide:pixelshigh:bitspersample:samplesperpixel:hasalpha:isplanar:colorspacename:bytesperrow:bitsperpixel:)
    public init?(bitmapDataPlanes planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide width: Int, pixelsHigh height: Int, bitsPerSample bps: Int, samplesPerPixel spp: Int, hasAlpha alpha: Bool, isPlanar: Bool, colorSpaceName: NSColorSpaceName, bytesPerRow rBytes: Int, bitsPerPixel pBits: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(cgimage:)
    public init(cgImage: CGImage) {
        super.init()
        _adopt(cgImage)
    }
    // SKIPPED (unknown module (CoreImage CIImage)): init(ciImage: CIImage)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(data:)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(focusedviewrect:)
    public init?(focusedViewRect rect: NSRect) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(forincrementalload:)
    public init(forIncrementalLoad: ()) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bitmapdata
    open var bitmapData: UnsafeMutablePointer<UInt8>? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bitmapformat
    open var bitmapFormat: NSBitmapImageRep.Format { _bitmapFormat }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bitsperpixel
    open var bitsPerPixel: Int { _image?.bitsPerPixel ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bytesperplane
    open var bytesPerPlane: Int { bytesPerRow * _pixelsHigh }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bytesperrow
    open var bytesPerRow: Int { _image?.bytesPerRow ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/canbecompressed(using:)
    open func canBeCompressed(using compression: NSBitmapImageRep.TIFFCompression) -> Bool { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/cgimage
    open var cgImage: CGImage? { _image }
    /// Replaces the pixels (NSView.cacheDisplay(in:to:) renders into an existing rep).
    internal func _setImage(_ image: CGImage) { _image = image }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/colorat(x:y:)
    open func colorAt(x: Int, y: Int) -> NSColor? {
        guard let image = _image, x >= 0, y >= 0, x < image.width, y < image.height, image.bitsPerPixel == 32 else { return nil }
        #if os(Windows) || os(Linux)
        let d = image.data
        #else
        guard let provider = image.dataProvider, let cf = provider.data else { return nil }
        let d = cf as Data
        #endif
        let i = y * image.bytesPerRow + x * 4
        guard i + 3 < d.count else { return nil }
        // Channel order from the byte order and alpha position: big-endian RGBA/ARGB,
        // little-endian ABGR/BGRA.
        let little = (image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue) == CGBitmapInfo.byteOrder32Little.rawValue
        let alphaFirst = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first || image.alphaInfo == .noneSkipFirst
        let order: [Int]   // indices of r, g, b, a within the 4 bytes
        switch (little, alphaFirst) {
        case (false, false): order = [0, 1, 2, 3]   // R G B A
        case (false, true):  order = [1, 2, 3, 0]   // A R G B
        case (true, false):  order = [3, 2, 1, 0]   // A B G R reversed -> bytes B? no: little RGBA = A B G R
        case (true, true):   order = [2, 1, 0, 3]   // B G R A
        }
        let hasAlpha = image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast
        let r = CGFloat(d[i + order[0]]) / 255
        let g = CGFloat(d[i + order[1]]) / 255
        let b = CGFloat(d[i + order[2]]) / 255
        let a = hasAlpha ? CGFloat(d[i + order[3]]) / 255 : 1
        let premultiplied = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .premultipliedLast
        if premultiplied && a > 0 { return NSColor(srgbRed: r / a, green: g / a, blue: b / a, alpha: a) }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/colorspace
    open var colorSpace: NSColorSpace { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/colorize(bymappinggray:to:blackmapping:whitemapping:)
    open func colorize(byMappingGray midPoint: CGFloat, to midPointColor: NSColor?, blackMapping shadowColor: NSColor?, whiteMapping lightColor: NSColor?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/converting(to:renderingintent:)
    open func converting(to targetSpace: NSColorSpace, renderingIntent: NSColorRenderingIntent) -> NSBitmapImageRep? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/getbitmapdataplanes(_:)
    open func getBitmapDataPlanes(_ data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/getcompression(_:factor:)
    open func getCompression(_ compression: UnsafeMutablePointer<NSBitmapImageRep.TIFFCompression>?, factor: UnsafeMutablePointer<Float>?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/getpixel(_:atx:y:)
    open func getPixel(_ p: UnsafeMutablePointer<Int>, atX x: Int, y: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/gettiffcompressiontypes(_:count:)
    public class func getTIFFCompressionTypes(_ list: UnsafeMutablePointer<UnsafePointer<NSBitmapImageRep.TIFFCompression>?>, count numTypes: UnsafeMutablePointer<Int>) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/imagereps(with:)
    public override class func imageReps(with data: Data) -> [NSImageRep] { NSBitmapImageRep(data: data).map { [$0] } ?? [] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/incrementalload(from:complete:)
    open func incrementalLoad(from data: Data, complete: Bool) -> Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/isplanar
    open var isPlanar: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/localizedname(fortiffcompressiontype:)
    public class func localizedName(forTIFFCompressionType compression: NSBitmapImageRep.TIFFCompression) -> String? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/numberofplanes
    open var numberOfPlanes: Int { 1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/representation(using:properties:)
    open func representation(using storageType: NSBitmapImageRep.FileType, properties: [NSBitmapImageRep.PropertyKey : Any]) -> Data? {
        guard let image = _image else { return nil }
        let format = storageType == .jpeg ? "public.jpeg" : "public.png"
        let quality = (properties[.compressionFactor] as? Double) ?? 0.9
        return Platform.imageCodec.encode(image, format: format, quality: quality)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/representationofimagereps(in:using:properties:)
    public class func representationOfImageReps(in imageReps: [NSImageRep], using storageType: NSBitmapImageRep.FileType, properties: [NSBitmapImageRep.PropertyKey : Any]) -> Data? {
        (imageReps.first as? NSBitmapImageRep)?.representation(using: storageType, properties: properties)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/retagging(with:)
    open func retagging(with newSpace: NSColorSpace) -> NSBitmapImageRep? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/samplesperpixel
    open var samplesPerPixel: Int { _hasAlpha ? 4 : 3 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setcolor(_:atx:y:)
    open func setColor(_ color: NSColor, atX x: Int, y: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setcompression(_:factor:)
    open func setCompression(_ compression: NSBitmapImageRep.TIFFCompression, factor: Float) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setpixel(_:atx:y:)
    open func setPixel(_ p: UnsafeMutablePointer<Int>, atX x: Int, y: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setproperty(_:withvalue:)
    open func setProperty(_ property: NSBitmapImageRep.PropertyKey, withValue value: Any?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentation
    open var tiffRepresentation: Data? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentation(using:factor:)
    open func tiffRepresentation(using comp: NSBitmapImageRep.TIFFCompression, factor: Float) -> Data? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentationofimagereps(in:)
    public class func tiffRepresentationOfImageReps(in array: [NSImageRep]) -> Data? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentationofimagereps(in:using:factor:)
    public class func tiffRepresentationOfImageReps(in array: [NSImageRep], using comp: NSBitmapImageRep.TIFFCompression, factor: Float) -> Data? { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/value(forproperty:)
    open func value(forProperty property: NSBitmapImageRep.PropertyKey) -> Any? { unimplemented() }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { unimplemented() }
    // Required by the superclass (NSCoding).
    public required init?(coder: NSCoder) { super.init(coder: coder) }
}
