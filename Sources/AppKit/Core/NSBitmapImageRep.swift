// NSBitmapImageRep (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() are stubs awaiting implementation.
//
// Every member is either implemented (hand-written types only), stubbed with
// unimplemented(), or listed as SKIPPED with the reason it cannot compile on Windows yet.
//
// Pixels (ADR-0036): a rep holds a drawable image (`_image`, premultiplied BGRA on the
// port's CoreGraphics) and, once anything reads or writes samples, an 8-bit sample
// buffer in AppKit's layout (meshed or planar, alpha first or last, premultiplied unless
// `.alphaNonpremultiplied`). A rep made from planes, or whose `bitmapData` was handed
// out, redraws its image from the bytes whenever the image is asked for, as AppKit reads
// a bitmap's planes each time it draws.

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
    /// Sample planes (one when meshed); empty until samples are needed.
    private var _planes: [UnsafeMutablePointer<UInt8>] = []
    private var _ownsPlanes = false
    private var _bytesPerRow = 0
    private var _bitsPerPixel = 0
    private var _samplesPerPixel = 0
    private var _isPlanar = false
    /// The bytes changed since `_image` was made from them.
    private var _bytesNewer = false
    /// Someone holds a pointer into the bytes: they may change at any time.
    private var _bytesShared = false
    private var _properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
    private var _incrementalData: Data? = nil
    private let _lock = NSLock()

    deinit { if _ownsPlanes { for p in _planes { p.deallocate() } } }

    @MainActor internal override func _cgImage() -> CGImage? { _currentImage }
    /// The decoded pixels, readable from any thread (a bitmap rep renders nothing).
    internal var _bitmapImage: CGImage? { _currentImage }

    private var _currentImage: CGImage? {
        _lock.lock(); defer { _lock.unlock() }
        if (_bytesNewer || _bytesShared), !_planes.isEmpty {
            _image = _imageFromBytes()
            _bytesNewer = false
        }
        return _image
    }

    private func _adopt(_ image: CGImage) {
        _image = image
        _pixelsWide = image.width
        _pixelsHigh = image.height
        _size = NSSize(width: image.width, height: image.height)
        _hasAlpha = image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast
        _bitsPerSample = image.bitsPerComponent
        _bitsPerPixel = image.bitsPerPixel
        _bytesPerRow = image.bytesPerRow
        _samplesPerPixel = _hasAlpha ? 4 : 3
        _bitmapFormat = _hasAlpha ? .alphaNonpremultiplied : []
        _colorSpaceName = .calibratedRGB
    }

    /// Decodes with the platform image codec, on the calling thread as Apple's does; a
    /// TIFF the platform cannot read goes through the port's own reader.
    public convenience init?(data: Data) {
        if let image = Platform.imageCodec.decode(data) {
            self.init(cgImage: image)
        } else if _NSTIFFCodec.isTIFF(data), let first = _NSTIFFCodec.decode(data).first {
            self.init(_rgba: first)
        } else {
            return nil
        }
    }

    /// A meshed RGBA (non-premultiplied) rep holding `pixels`.
    internal convenience init(_rgba pixels: _NSRGBAPixels) {
        self.init(bitmapDataPlanes: nil, pixelsWide: pixels.width, pixelsHigh: pixels.height, bitsPerSample: 8,
                  samplesPerPixel: pixels.hasAlpha ? 4 : 3, hasAlpha: pixels.hasAlpha, isPlanar: false,
                  colorSpaceName: .calibratedRGB, bitmapFormat: pixels.hasAlpha ? .alphaNonpremultiplied : [],
                  bytesPerRow: 0, bitsPerPixel: 32)!
        let spp = _samplesPerPixel
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let s = (y * pixels.width + x) * 4, d = _planes[0] + y * _bytesPerRow + x * 4
                for i in 0..<spp { d[i] = pixels.bytes[s + i] }
            }
        }
        _bytesNewer = true
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(bitmapdataplanes:pixelswide:pixelshigh:bitspersample:samplesperpixel:hasalpha:isplanar:colorspacename:bitmapformat:bytesperrow:bitsperpixel:)
    /// With `planes` nil (or a nil plane) the rep allocates zeroed planes itself; given
    /// planes stay the caller's and are read whenever the rep draws. Zero `rBytes`/`pBits`
    /// pick the natural values (rows padded to 32 bytes, as AppKit pads them). Only 8-bit
    /// gray or RGB samples are modelled (ADR-0036).
    public init?(bitmapDataPlanes planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide width: Int, pixelsHigh height: Int, bitsPerSample bps: Int, samplesPerPixel spp: Int, hasAlpha alpha: Bool, isPlanar: Bool, colorSpaceName: NSColorSpaceName, bitmapFormat: NSBitmapImageRep.Format, bytesPerRow rBytes: Int, bitsPerPixel pBits: Int) {
        let colorSamples = NSBitmapImageRep._colorSamples(colorSpaceName)
        guard width > 0, height > 0, spp >= 1, spp <= 5, bps > 0, colorSamples > 0,
              spp == colorSamples + (alpha ? 1 : 0) else { return nil }
        guard bps == 8, !bitmapFormat.contains(.floatingPointSamples) else {
            unimplemented("NSBitmapImageRep(bitmapDataPlanes:) with \(bps)-bit\(bitmapFormat.contains(.floatingPointSamples) ? " float" : "") samples — only 8-bit samples are modelled")
        }
        let bitsPerPixel = pBits != 0 ? pBits : (isPlanar ? bps : bps * spp)
        guard isPlanar || bitsPerPixel >= bps * spp else { return nil }
        let naturalRow = (width * bitsPerPixel + 7) / 8
        let bytesPerRow = rBytes != 0 ? rBytes : (naturalRow + 31) / 32 * 32
        guard bytesPerRow >= naturalRow else { return nil }
        super.init()
        _pixelsWide = width; _pixelsHigh = height
        _size = NSSize(width: width, height: height)
        _bitsPerSample = bps; _hasAlpha = alpha; _isOpaque = !alpha
        _colorSpaceName = colorSpaceName
        _bitmapFormat = bitmapFormat
        _samplesPerPixel = spp; _isPlanar = isPlanar
        _bitsPerPixel = bitsPerPixel; _bytesPerRow = bytesPerRow
        let planeCount = isPlanar ? spp : 1
        var supplied: [UnsafeMutablePointer<UInt8>?] = (0..<planeCount).map { planes?[$0] }
        if supplied.contains(where: { $0 == nil }) {
            supplied = (0..<planeCount).map { _ in
                let p = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
                p.initialize(repeating: 0, count: bytesPerRow * height)
                return p
            }
            _ownsPlanes = true
        } else {
            _bytesShared = true   // the caller may write its planes at any time
        }
        _planes = supplied.map { $0! }
        _bytesNewer = true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(bitmapdataplanes:pixelswide:pixelshigh:bitspersample:samplesperpixel:hasalpha:isplanar:colorspacename:bytesperrow:bitsperpixel:)
    public convenience init?(bitmapDataPlanes planes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide width: Int, pixelsHigh height: Int, bitsPerSample bps: Int, samplesPerPixel spp: Int, hasAlpha alpha: Bool, isPlanar: Bool, colorSpaceName: NSColorSpaceName, bytesPerRow rBytes: Int, bitsPerPixel pBits: Int) {
        self.init(bitmapDataPlanes: planes, pixelsWide: width, pixelsHigh: height, bitsPerSample: bps, samplesPerPixel: spp, hasAlpha: alpha, isPlanar: isPlanar, colorSpaceName: colorSpaceName, bitmapFormat: [], bytesPerRow: rBytes, bitsPerPixel: pBits)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(cgimage:)
    public init(cgImage: CGImage) {
        super.init()
        _adopt(cgImage)
    }
    // SKIPPED (unknown module (CoreImage CIImage)): init(ciImage: CIImage)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(focusedviewrect:)
    /// The pixels of `rect` (the focused view's coordinates) as they are now: what the
    /// view's `lockFocus` drew, or else the view rendered. Nil with no focused view.
    public convenience init?(focusedViewRect rect: NSRect) {
        guard let image = MainActor.assumeIsolated({ () -> CGImage? in
            guard let view = NSView.focusView else { return nil }
            if let surfaceImage = view._focusSurfaceImage {
                // The surface covers the frame at its own scale: crop to `rect`.
                let scale = CGFloat(surfaceImage.width) / max(1, view.frame.width)
                let r = view._localToFocusSurface.applyingToRect(rect)
                let px = CGRect(x: r.minX * scale, y: (view.frame.height - r.maxY) * scale, width: r.width * scale, height: r.height * scale).integral
                return NSBitmapImageRep._crop(surfaceImage, to: px)
            }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
            view.cacheDisplay(in: rect, to: rep)
            return rep.cgImage
        }) else { return nil }
        self.init(cgImage: image)
        size = rect.size
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/init(forincrementalload:)
    /// An empty rep that `incrementalLoad(from:complete:)` fills.
    public init(forIncrementalLoad: ()) {
        super.init()
        _incrementalData = Data()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bitmapdata
    /// The first plane; the rep reads it back whenever it next draws.
    open var bitmapData: UnsafeMutablePointer<UInt8>? {
        _lock.lock(); defer { _lock.unlock() }
        _ensureBytes()
        _bytesShared = true
        return _planes.first
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bitmapformat
    open var bitmapFormat: NSBitmapImageRep.Format { _bitmapFormat }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bitsperpixel
    open var bitsPerPixel: Int { _bitsPerPixel }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bytesperplane
    open var bytesPerPlane: Int { bytesPerRow * _pixelsHigh }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/bytesperrow
    open var bytesPerRow: Int { _bytesPerRow }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/canbecompressed(using:)
    /// Whether `tiffRepresentation(using:factor:)` applies the scheme (none and PackBits).
    open func canBeCompressed(using compression: NSBitmapImageRep.TIFFCompression) -> Bool { _NSTIFFCodec.writableCompressions.contains(compression) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/cgimage
    open var cgImage: CGImage? { _currentImage }
    /// Replaces the pixels (NSView.cacheDisplay(in:to:) renders into an existing rep).
    internal func _setImage(_ image: CGImage) {
        _lock.lock(); defer { _lock.unlock() }
        _image = image
        if !_planes.isEmpty {
            // Keep the bytes: write the new pixels into them in the rep's layout.
            let rgba = NSBitmapImageRep._rgbaPixels(of: image)
            _storeRGBA(rgba)
            _bytesNewer = false
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/colorat(x:y:)
    /// The pixel in the rep's colour space family (device or calibrated, RGB or white),
    /// alpha divided out; nil outside the bitmap.
    open func colorAt(x: Int, y: Int) -> NSColor? {
        guard x >= 0, y >= 0, x < _pixelsWide, y < _pixelsHigh else { return nil }
        _lock.lock()
        _ensureBytes()
        let s = _samples(x: x, y: y)
        _lock.unlock()
        guard let s else { return nil }
        let (c, a) = _colorAndAlpha(s)
        let premultiplied = _hasAlpha && !_bitmapFormat.contains(.alphaNonpremultiplied)
        let comps = c.map { premultiplied && a > 0 ? min(1, $0 / a) : $0 }
        let device = _colorSpaceName == .deviceRGB || _colorSpaceName == .deviceWhite || _colorSpaceName.rawValue == "NSDeviceBlackColorSpace"
        if comps.count == 1 {
            let w = NSBitmapImageRep._isBlack(_colorSpaceName) ? 1 - comps[0] : comps[0]
            return device ? NSColor(deviceWhite: w, alpha: a) : NSColor(calibratedWhite: w, alpha: a)
        }
        return device ? NSColor(deviceRed: comps[0], green: comps[1], blue: comps[2], alpha: a)
                      : NSColor(calibratedRed: comps[0], green: comps[1], blue: comps[2], alpha: a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/colorspace
    /// Out of scope (ADR-0036): `NSColorSpace` is a generated stub.
    open var colorSpace: NSColorSpace { unimplemented("NSBitmapImageRep.colorSpace — NSColorSpace is not modelled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/colorize(bymappinggray:to:blackmapping:whitemapping:)
    /// Maps each pixel's gray level onto black → `shadowColor`, `midPoint` →
    /// `midPointColor`, white → `lightColor` (piecewise linear), keeping alpha.
    open func colorize(byMappingGray midPoint: CGFloat, to midPointColor: NSColor?, blackMapping shadowColor: NSColor?, whiteMapping lightColor: NSColor?) {
        let black = shadowColor ?? .black, mid = midPointColor ?? NSColor(white: midPoint, alpha: 1), white = lightColor ?? .white
        func rgb(_ c: NSColor) -> [CGFloat] { [c.redComponent, c.greenComponent, c.blueComponent] }
        let (b, m, w) = (rgb(black), rgb(mid), rgb(white))
        let mp = min(max(midPoint, 0.0001), 0.9999)
        for y in 0..<_pixelsHigh {
            for x in 0..<_pixelsWide {
                guard let c = colorAt(x: x, y: y) else { continue }
                let g = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
                let out: [CGFloat] = g <= mp ? zip(b, m).map { $0 + ($1 - $0) * g / mp } : zip(m, w).map { $0 + ($1 - $0) * (g - mp) / (1 - mp) }
                setColor(NSColor(deviceRed: out[0], green: out[1], blue: out[2], alpha: c.alphaComponent), atX: x, y: y)
            }
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/converting(to:renderingintent:)
    /// Out of scope (ADR-0036): `NSColorSpace` is a generated stub.
    open func converting(to targetSpace: NSColorSpace, renderingIntent: NSColorRenderingIntent) -> NSBitmapImageRep? { unimplemented("NSBitmapImageRep.converting(to:renderingIntent:) — NSColorSpace is not modelled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/getbitmapdataplanes(_:)
    /// Fills `data` with one pointer per plane (five slots, unused ones nil).
    open func getBitmapDataPlanes(_ data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>) {
        _lock.lock(); defer { _lock.unlock() }
        _ensureBytes()
        _bytesShared = true
        for i in 0..<5 { data[i] = i < _planes.count ? _planes[i] : nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/getcompression(_:factor:)
    open func getCompression(_ compression: UnsafeMutablePointer<NSBitmapImageRep.TIFFCompression>?, factor: UnsafeMutablePointer<Float>?) {
        compression?.pointee = NSBitmapImageRep._compression(_properties[.compressionMethod])
        factor?.pointee = (_properties[.compressionFactor] as? NSNumber)?.floatValue ?? (_properties[.compressionFactor] as? Float) ?? 0
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/getpixel(_:atx:y:)
    /// The raw samples of the pixel, in storage order.
    open func getPixel(_ p: UnsafeMutablePointer<Int>, atX x: Int, y: Int) {
        guard x >= 0, y >= 0, x < _pixelsWide, y < _pixelsHigh else { return }
        _lock.lock(); defer { _lock.unlock() }
        _ensureBytes()
        guard let s = _samples(x: x, y: y) else { return }
        for (i, v) in s.enumerated() { p[i] = Int(v) }
    }
    nonisolated(unsafe) private static let _tiffCompressionTypes: UnsafeMutablePointer<NSBitmapImageRep.TIFFCompression> = {
        let p = UnsafeMutablePointer<NSBitmapImageRep.TIFFCompression>.allocate(capacity: _NSTIFFCodec.writableCompressions.count)
        p.initialize(from: _NSTIFFCodec.writableCompressions, count: _NSTIFFCodec.writableCompressions.count)
        return p
    }()
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/gettiffcompressiontypes(_:count:)
    public class func getTIFFCompressionTypes(_ list: UnsafeMutablePointer<UnsafePointer<NSBitmapImageRep.TIFFCompression>?>, count numTypes: UnsafeMutablePointer<Int>) {
        list.pointee = UnsafePointer(_tiffCompressionTypes)
        numTypes.pointee = _NSTIFFCodec.writableCompressions.count
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/imagereps(with:)
    public override class func imageReps(with data: Data) -> [NSImageRep] {
        if Platform.imageCodec.decode(data) == nil, _NSTIFFCodec.isTIFF(data) {
            return _NSTIFFCodec.decode(data).map { NSBitmapImageRep(_rgba: $0) }   // every page
        }
        return NSBitmapImageRep(data: data).map { [$0] } ?? []
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/incrementalload(from:complete:)
    /// The decoders here are not progressive: until `complete` the rep asks for all the
    /// data, then decodes it in one go.
    open func incrementalLoad(from data: Data, complete: Bool) -> Int {
        guard _incrementalData != nil else { return NSBitmapImageRep.LoadStatus.completed.rawValue }
        _incrementalData = data
        guard complete else { return NSBitmapImageRep.LoadStatus.willNeedAllData.rawValue }
        _incrementalData = nil
        guard let image = Platform.imageCodec.decode(data) else {
            return (data.isEmpty ? NSBitmapImageRep.LoadStatus.unexpectedEOF : .invalidData).rawValue
        }
        _lock.lock(); _adopt(image); _lock.unlock()
        return NSBitmapImageRep.LoadStatus.completed.rawValue
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/isplanar
    open var isPlanar: Bool { _isPlanar }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/localizedname(fortiffcompressiontype:)
    public class func localizedName(forTIFFCompressionType compression: NSBitmapImageRep.TIFFCompression) -> String? {
        switch compression {
        case .none: return "No Compression"
        case .ccittfax3: return "CCITT Group 3 Fax"
        case .ccittfax4: return "CCITT Group 4 Fax"
        case .lzw: return "Lempel-Ziv & Welch"
        case .jpeg, .oldJPEG: return "JPEG"
        case .next: return "NeXT"
        case .packBits: return "PackBits"
        @unknown default: return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/numberofplanes
    open var numberOfPlanes: Int { _isPlanar ? _samplesPerPixel : 1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/representation(using:properties:)
    /// PNG and JPEG (and GIF, JPEG 2000 where the platform encodes them) through the
    /// platform codec; TIFF and BMP through the port's own writers, so they work
    /// everywhere. Nil when the platform has no encoder for the type (JPEG on Linux).
    open func representation(using storageType: NSBitmapImageRep.FileType, properties: [NSBitmapImageRep.PropertyKey : Any]) -> Data? {
        let props = _properties.merging(properties) { $1 }
        switch storageType {
        case .tiff:
            return tiffRepresentation(using: NSBitmapImageRep._compression(props[.compressionMethod]), factor: 0)
        case .bmp:
            guard let px = _rgba() else { return nil }
            return _NSBMPCodec.encode(px, dpi: _dpi)
        default:
            guard let image = _currentImage else { return nil }
            let uti: String
            switch storageType {
            case .jpeg: uti = "public.jpeg"
            case .gif: uti = "com.compuserve.gif"
            case .jpeg2000: uti = "public.jpeg-2000"
            default: uti = "public.png"
            }
            let quality = (props[.compressionFactor] as? NSNumber)?.doubleValue ?? (props[.compressionFactor] as? Double) ?? 0.9
            return Platform.imageCodec.encode(image, format: uti, quality: quality)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/representationofimagereps(in:using:properties:)
    /// TIFF holds every rep (one page each); the other types the first bitmap.
    public class func representationOfImageReps(in imageReps: [NSImageRep], using storageType: NSBitmapImageRep.FileType, properties: [NSBitmapImageRep.PropertyKey : Any]) -> Data? {
        if storageType == .tiff {
            return tiffRepresentationOfImageReps(in: imageReps, using: _compression(properties[.compressionMethod]), factor: 0)
        }
        return (imageReps.first { $0 is NSBitmapImageRep } as? NSBitmapImageRep)?.representation(using: storageType, properties: properties)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/retagging(with:)
    /// Out of scope (ADR-0036): `NSColorSpace` is a generated stub.
    open func retagging(with newSpace: NSColorSpace) -> NSBitmapImageRep? { unimplemented("NSBitmapImageRep.retagging(with:) — NSColorSpace is not modelled") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/samplesperpixel
    open var samplesPerPixel: Int { _samplesPerPixel }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setcolor(_:atx:y:)
    /// Stores the colour in the rep's family (gray from the RGB average for white reps),
    /// premultiplied unless the rep is not.
    open func setColor(_ color: NSColor, atX x: Int, y: Int) {
        guard x >= 0, y >= 0, x < _pixelsWide, y < _pixelsHigh else { return }
        let a = _hasAlpha ? color.alphaComponent : 1
        var comps: [CGFloat]
        if NSBitmapImageRep._colorSamples(_colorSpaceName) == 1 {
            var w = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            if NSBitmapImageRep._isBlack(_colorSpaceName) { w = 1 - w }
            comps = [w]
        } else {
            comps = [color.redComponent, color.greenComponent, color.blueComponent]
        }
        if _hasAlpha && !_bitmapFormat.contains(.alphaNonpremultiplied) { comps = comps.map { $0 * a } }
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded(.down)))) }
        var samples = comps.map(byte)
        if _hasAlpha { if _bitmapFormat.contains(.alphaFirst) { samples.insert(byte(a), at: 0) } else { samples.append(byte(a)) } }
        _lock.lock(); defer { _lock.unlock() }
        _ensureBytes()
        _setSamples(samples, x: x, y: y)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setcompression(_:factor:)
    open func setCompression(_ compression: NSBitmapImageRep.TIFFCompression, factor: Float) {
        _properties[.compressionMethod] = compression
        _properties[.compressionFactor] = NSNumber(value: factor)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setpixel(_:atx:y:)
    open func setPixel(_ p: UnsafeMutablePointer<Int>, atX x: Int, y: Int) {
        guard x >= 0, y >= 0, x < _pixelsWide, y < _pixelsHigh else { return }
        _lock.lock(); defer { _lock.unlock() }
        _ensureBytes()
        _setSamples((0..<_samplesPerPixel).map { UInt8(truncatingIfNeeded: p[$0]) }, x: x, y: y)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/setproperty(_:withvalue:)
    /// Stored; `representation(using:properties:)` uses the compression ones.
    open func setProperty(_ property: NSBitmapImageRep.PropertyKey, withValue value: Any?) { _properties[property] = value }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentation
    /// An uncompressed baseline TIFF, as AppKit writes by default.
    open var tiffRepresentation: Data? { tiffRepresentation(using: .none, factor: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentation(using:factor:)
    /// A scheme the writer cannot apply (see `canBeCompressed(using:)`) writes uncompressed.
    open func tiffRepresentation(using comp: NSBitmapImageRep.TIFFCompression, factor: Float) -> Data? {
        guard let px = _rgba() else { return nil }
        return _NSTIFFCodec.encode([(px, _dpi)], compression: comp)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentationofimagereps(in:)
    public class func tiffRepresentationOfImageReps(in array: [NSImageRep]) -> Data? { tiffRepresentationOfImageReps(in: array, using: .none, factor: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/tiffrepresentationofimagereps(in:using:factor:)
    /// One page per rep; reps that are not bitmaps are rendered at their pixel size.
    public class func tiffRepresentationOfImageReps(in array: [NSImageRep], using comp: NSBitmapImageRep.TIFFCompression, factor: Float) -> Data? {
        let pages = array.compactMap { rep -> (_NSRGBAPixels, (x: Double, y: Double))? in
            let bitmap = (rep as? NSBitmapImageRep) ?? rep._renderedBitmap()
            guard let bitmap, let px = bitmap._rgba() else { return nil }
            return (px, bitmap._dpi)
        }
        return pages.isEmpty ? nil : _NSTIFFCodec.encode(pages, compression: comp)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsbitmapimagerep/value(forproperty:)
    open func value(forProperty property: NSBitmapImageRep.PropertyKey) -> Any? { _properties[property] }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Required by the superclass (NSCoding).
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let data = coder.decodeObject(forKey: "NSTIFFRepresentation") as? Data, let image = Platform.imageCodec.decode(data) {
            _adopt(image)
        } else if let data = coder.decodeObject(forKey: "NSTIFFRepresentation") as? Data, let px = _NSTIFFCodec.decode(data).first,
                  let image = NSBitmapImageRep(_rgba: px).cgImage {
            _adopt(image)
        }
    }
    /// Archives the pixels as TIFF.
    open override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let tiff = tiffRepresentation { coder.encode(tiff, forKey: "NSTIFFRepresentation") }
    }
    open override func copy(with zone: NSZone? = nil) -> Any {
        guard let image = cgImage else { return self }
        let c = NSBitmapImageRep(cgImage: image)
        c._size = _size
        c._properties = _properties
        return c
    }

    // MARK: Types (ADR-0036)

    /// What the platform decoder reads (cairo's on Linux knows PNG; BMP and TIFF are the
    /// port's own readers there).
    private static var _decodable: [(uti: String, extensions: [String])] {
        var list: [(String, [String])] = [("public.png", ["png"]), ("public.tiff", ["tiff", "tif"]), ("com.microsoft.bmp", ["bmp"])]
        #if !os(Linux)
        list += [("public.jpeg", ["jpg", "jpeg", "jpe"]), ("com.compuserve.gif", ["gif"])]
        #endif
        return list
    }
    class public override var imageUnfilteredTypes: [String] { _decodable.map(\.uti) }
    public override class func imageUnfilteredFileTypes() -> [String] { _decodable.flatMap { $0.extensions + $0.extensions.map { $0.uppercased() } } }
    public override class func imageUnfilteredPasteboardTypes() -> [NSPasteboard.PasteboardType] { imageUnfilteredTypes.map { NSPasteboard.PasteboardType(rawValue: $0) } }
    /// Whether the data starts like a file the decoders read.
    public override class func canInit(with data: Data) -> Bool {
        let b = [UInt8](data.prefix(8))
        guard b.count >= 4 else { return false }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) || b.starts(with: [0x42, 0x4D]) || _NSTIFFCodec.isTIFF(data) { return true }
        #if !os(Linux)
        if b.starts(with: [0xFF, 0xD8, 0xFF]) || b.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }
        #endif
        return false
    }

    // MARK: Samples

    /// The deprecated "black" spaces: one sample, 0 is white.
    internal static func _isBlack(_ name: NSColorSpaceName) -> Bool { name.rawValue == "NSDeviceBlackColorSpace" || name.rawValue == "NSCalibratedBlackColorSpace" }
    /// A compression property value (the enum, or an NSNumber of its raw value).
    internal static func _compression(_ v: Any?) -> NSBitmapImageRep.TIFFCompression {
        if let c = v as? NSBitmapImageRep.TIFFCompression { return c }
        if let n = v as? NSNumber, let c = NSBitmapImageRep.TIFFCompression(rawValue: n.intValue) { return c }
        return .none
    }

    private var _dpi: (x: Double, y: Double) {
        (_size.width > 0 ? 72 * Double(_pixelsWide) / Double(_size.width) : 72, _size.height > 0 ? 72 * Double(_pixelsHigh) / Double(_size.height) : 72)
    }

    /// Colour samples per pixel for a colour space name: 3 RGB, 1 white/black, 0 unknown
    /// (CMYK and custom spaces are not modelled).
    internal static func _colorSamples(_ name: NSColorSpaceName) -> Int {
        switch name {
        case .deviceRGB, .calibratedRGB: return 3
        case .deviceWhite, .calibratedWhite: return 1
        default: return _isBlack(name) ? 1 : 0
        }
    }

    /// Unpacks the decoded image into a meshed 8-bit buffer, once.
    private func _ensureBytes() {
        guard _planes.isEmpty, let image = _image else { return }
        let px = NSBitmapImageRep._rgbaPixels(of: image)
        _samplesPerPixel = _hasAlpha ? 4 : 3
        _bitsPerSample = 8
        _bitsPerPixel = 32
        _isPlanar = false
        _bytesPerRow = px.width * 4
        _bitmapFormat = _hasAlpha ? .alphaNonpremultiplied : []
        let p = UnsafeMutablePointer<UInt8>.allocate(capacity: _bytesPerRow * px.height)
        p.initialize(repeating: 0, count: _bytesPerRow * px.height)
        _planes = [p]
        _ownsPlanes = true
        _storeRGBA(px)
    }

    /// Writes RGBA pixels (non-premultiplied) into the buffer in its layout.
    private func _storeRGBA(_ px: _NSRGBAPixels) {
        let gray = NSBitmapImageRep._colorSamples(_colorSpaceName) == 1
        let premultiply = _hasAlpha && !_bitmapFormat.contains(.alphaNonpremultiplied)
        for y in 0..<min(px.height, _pixelsHigh) {
            for x in 0..<min(px.width, _pixelsWide) {
                let i = (y * px.width + x) * 4
                let a = Int(px.bytes[i + 3])
                func pm(_ v: UInt8) -> UInt8 { premultiply ? UInt8((Int(v) * a + 127) / 255) : v }
                var s: [UInt8] = gray ? [pm(UInt8((Int(px.bytes[i]) + Int(px.bytes[i + 1]) + Int(px.bytes[i + 2])) / 3))]
                                      : [pm(px.bytes[i]), pm(px.bytes[i + 1]), pm(px.bytes[i + 2])]
                if NSBitmapImageRep._isBlack(_colorSpaceName) { s = s.map { 255 - $0 } }
                if _hasAlpha { if _bitmapFormat.contains(.alphaFirst) { s.insert(UInt8(a), at: 0) } else { s.append(UInt8(a)) } }
                _setSamples(s, x: x, y: y)
            }
        }
    }

    private func _samples(x: Int, y: Int) -> [UInt8]? {
        guard !_planes.isEmpty else { return nil }
        if _isPlanar { return (0..<_samplesPerPixel).map { _planes[$0][y * _bytesPerRow + x] } }
        let base = _planes[0] + y * _bytesPerRow + x * (_bitsPerPixel / 8)
        return (0..<_samplesPerPixel).map { base[$0] }
    }

    private func _setSamples(_ s: [UInt8], x: Int, y: Int) {
        guard !_planes.isEmpty else { return }
        if _isPlanar { for i in 0..<min(s.count, _samplesPerPixel) { _planes[i][y * _bytesPerRow + x] = s[i] } }
        else {
            let base = _planes[0] + y * _bytesPerRow + x * (_bitsPerPixel / 8)
            for i in 0..<min(s.count, _samplesPerPixel) { base[i] = s[i] }
        }
        _bytesNewer = true
    }

    /// Colour components and alpha (0...1) of raw samples, still premultiplied if stored so.
    private func _colorAndAlpha(_ s: [UInt8]) -> ([CGFloat], CGFloat) {
        var v = s.map { CGFloat($0) / 255 }
        var a: CGFloat = 1
        if _hasAlpha { a = _bitmapFormat.contains(.alphaFirst) ? v.removeFirst() : v.removeLast() }
        return (v, a)
    }

    /// The bitmap as non-premultiplied RGBA bytes.
    internal func _rgba() -> _NSRGBAPixels? {
        _lock.lock(); defer { _lock.unlock() }
        if _planes.isEmpty { return _image.map { NSBitmapImageRep._rgbaPixels(of: $0) } }
        var out = [UInt8](repeating: 0, count: _pixelsWide * _pixelsHigh * 4)
        let gray = NSBitmapImageRep._colorSamples(_colorSpaceName) == 1
        let black = NSBitmapImageRep._isBlack(_colorSpaceName)
        let premultiplied = _hasAlpha && !_bitmapFormat.contains(.alphaNonpremultiplied)
        for y in 0..<_pixelsHigh {
            for x in 0..<_pixelsWide {
                guard var s = _samples(x: x, y: y) else { continue }
                var a: UInt8 = 255
                if _hasAlpha { a = _bitmapFormat.contains(.alphaFirst) ? s.removeFirst() : s.removeLast() }
                if black { s = s.map { 255 - $0 } }
                if premultiplied && a > 0 && a < 255 { s = s.map { UInt8(min(255, (Int($0) * 255 + Int(a) / 2) / Int(a))) } }
                let i = (y * _pixelsWide + x) * 4
                if gray { out[i] = s[0]; out[i + 1] = s[0]; out[i + 2] = s[0] } else { out[i] = s[0]; out[i + 1] = s[1]; out[i + 2] = s[2] }
                out[i + 3] = a
            }
        }
        return _NSRGBAPixels(width: _pixelsWide, height: _pixelsHigh, bytes: out, hasAlpha: _hasAlpha)
    }

    /// Premultiplied BGRA (the port's native bitmap layout, and one CoreGraphics draws).
    private func _imageFromBytes() -> CGImage? {
        _lock.unlock(); defer { _lock.lock() }
        guard let px = _rgba() else { return nil }
        var bgra = [UInt8](repeating: 0, count: px.width * px.height * 4)
        for p in 0..<(px.width * px.height) {
            let a = Int(px.bytes[p * 4 + 3])
            func pm(_ v: UInt8) -> UInt8 { UInt8((Int(v) * a + 127) / 255) }
            bgra[p * 4] = pm(px.bytes[p * 4 + 2]); bgra[p * 4 + 1] = pm(px.bytes[p * 4 + 1]); bgra[p * 4 + 2] = pm(px.bytes[p * 4]); bgra[p * 4 + 3] = UInt8(a)
        }
        return NSBitmapImageRep._makeBGRAImage(width: px.width, height: px.height, bytes: bgra)
    }

    internal static func _makeBGRAImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage? {
        #if os(Windows) || os(Linux)
        return CGImage.fromBGRA(width: width, height: height, stride: width * 4, data: Data(bytes))
        #else
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        #endif
    }

    /// Any image's pixels as non-premultiplied RGBA bytes.
    internal static func _rgbaPixels(of image: CGImage) -> _NSRGBAPixels {
        let w = image.width, h = image.height
        var premul = [UInt8](repeating: 0, count: w * h * 4)   // premultiplied RGBA
        var known = false
        #if os(Windows) || os(Linux)
        let d = image.data
        known = image.bitsPerPixel == 32 && image.bitsPerComponent == 8
        #else
        var d = Data()
        if image.bitsPerPixel == 32, image.bitsPerComponent == 8, let cf = image.dataProvider?.data { d = cf as Data; known = true }
        #endif
        let hasAlpha = image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast
        if known {
            let little = (image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue) == CGBitmapInfo.byteOrder32Little.rawValue
            let alphaFirst = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first || image.alphaInfo == .noneSkipFirst
            let order: [Int]   // byte indices of r, g, b, a within a pixel
            switch (little, alphaFirst) {
            case (false, false): order = [0, 1, 2, 3]   // RGBA
            case (false, true):  order = [1, 2, 3, 0]   // ARGB
            case (true, false):  order = [3, 2, 1, 0]   // ABGR in memory
            case (true, true):   order = [2, 1, 0, 3]   // BGRA in memory
            }
            let premultiplied = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .premultipliedLast
            d.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
                for y in 0..<h {
                    for x in 0..<w {
                        let i = y * image.bytesPerRow + x * 4, o = (y * w + x) * 4
                        guard i + 3 < src.count else { continue }
                        let a = hasAlpha ? Int(src[i + order[3]]) : 255
                        for c in 0..<3 {
                            let v = Int(src[i + order[c]])
                            premul[o + c] = UInt8(premultiplied || !hasAlpha ? v : (v * a + 127) / 255)
                        }
                        premul[o + 3] = UInt8(a)
                    }
                }
            }
        } else {
            #if !(os(Windows) || os(Linux))
            // Other layouts: let CoreGraphics draw it into premultiplied RGBA.
            premul.withUnsafeMutableBytes { buf in
                if let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            #endif
        }
        // Divide the alpha out.
        for p in 0..<(w * h) {
            let a = Int(premul[p * 4 + 3])
            if a > 0 && a < 255 { for c in 0..<3 { premul[p * 4 + c] = UInt8(min(255, (Int(premul[p * 4 + c]) * 255 + a / 2) / a)) } }
        }
        return _NSRGBAPixels(width: w, height: h, bytes: premul, hasAlpha: hasAlpha)
    }

    /// `image`'s pixels inside `rect` (pixel coordinates, top row first).
    internal static func _crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let px = _rgbaPixels(of: image)
        let r = rect.intersection(CGRect(x: 0, y: 0, width: px.width, height: px.height))
        guard r.width >= 1, r.height >= 1 else { return nil }
        let x0 = Int(r.minX), y0 = Int(r.minY), w = Int(r.width), h = Int(r.height)
        var bgra = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let s = ((y0 + y) * px.width + x0 + x) * 4, o = (y * w + x) * 4
                let a = Int(px.bytes[s + 3])
                func pm(_ v: UInt8) -> UInt8 { UInt8((Int(v) * a + 127) / 255) }
                bgra[o] = pm(px.bytes[s + 2]); bgra[o + 1] = pm(px.bytes[s + 1]); bgra[o + 2] = pm(px.bytes[s]); bgra[o + 3] = UInt8(a)
            }
        }
        return _makeBGRAImage(width: w, height: h, bytes: bgra)
    }
}

extension CGAffineTransform {
    /// The bounding box of `rect` under the transform.
    internal func applyingToRect(_ rect: CGRect) -> CGRect {
        let pts = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].map { $0.applying(self) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
