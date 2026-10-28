// ImageIO for Windows and Linux (ADR-0009): the option and property keys of
// CGImageSource.h, CGImageDestination.h and CGImageProperties.h. String values match
// Apple's so dictionaries round-trip through archives and property lists unchanged.
// CF types in the API are the corelibs Foundation classes, as in CoreText (CTTypes.swift).

import Foundation
@_exported import CoreGraphics
@_exported import CoreText

// MARK: CGImageSource options (CGImageSource.h)

public let kCGImageSourceTypeIdentifierHint: CFString = "kCGImageSourceTypeIdentifierHint"
public let kCGImageSourceShouldCache: CFString = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldCacheImmediately: CFString = "kCGImageSourceShouldCacheImmediately"
public let kCGImageSourceShouldAllowFloat: CFString = "kCGImageSourceShouldAllowFloat"
public let kCGImageSourceCreateThumbnailFromImageIfAbsent: CFString = "kCGImageSourceCreateThumbnailFromImageIfAbsent"
public let kCGImageSourceCreateThumbnailFromImageAlways: CFString = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceThumbnailMaxPixelSize: CFString = "kCGImageSourceThumbnailMaxPixelSize"
public let kCGImageSourceCreateThumbnailWithTransform: CFString = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceSubsampleFactor: CFString = "kCGImageSourceSubsampleFactor"

public enum CGImageSourceStatus: Int32, Sendable {
    case statusUnexpectedEOF = -5
    case statusInvalidData = -4
    case statusUnknownType = -3
    case statusReadingHeader = -2
    case statusIncomplete = -1
    case statusComplete = 0
}

// MARK: CGImageDestination options (CGImageDestination.h)

public let kCGImageDestinationLossyCompressionQuality: CFString = "kCGImageDestinationLossyCompressionQuality"
public let kCGImageDestinationBackgroundColor: CFString = "kCGImageDestinationBackgroundColor"
public let kCGImageDestinationImageMaxPixelSize: CFString = "kCGImageDestinationImageMaxPixelSize"
public let kCGImageDestinationEmbedThumbnail: CFString = "kCGImageDestinationEmbedThumbnail"
public let kCGImageDestinationOptimizeColorForSharing: CFString = "kCGImageDestinationOptimizeColorForSharing"
public let kCGImageDestinationMetadata: CFString = "kCGImageDestinationMetadata"
public let kCGImageDestinationMergeMetadata: CFString = "kCGImageDestinationMergeMetadata"
public let kCGImageMetadataShouldExcludeXMP: CFString = "kCGImageMetadataShouldExcludeXMP"
public let kCGImageMetadataShouldExcludeGPS: CFString = "kCGImageMetadataShouldExcludeGPS"
public let kCGImageDestinationDateTime: CFString = "kCGImageDestinationDateTime"
public let kCGImageDestinationOrientation: CFString = "kCGImageDestinationOrientation"
public let kCGImageDestinationPreserveGainMap: CFString = "kCGImageDestinationPreserveGainMap"

// MARK: Image properties (CGImageProperties.h)

public let kCGImagePropertyFileSize: CFString = "FileSize"
public let kCGImagePropertyImageCount: CFString = "ImageCount"
public let kCGImagePropertyImageIndex: CFString = "ImageIndex"
public let kCGImagePropertyPrimaryImage: CFString = "PrimaryImage"
public let kCGImagePropertyImages: CFString = "Images"
public let kCGImagePropertyThumbnailImages: CFString = "ThumbnailImages"
public let kCGImagePropertyPixelHeight: CFString = "PixelHeight"
public let kCGImagePropertyPixelWidth: CFString = "PixelWidth"
public let kCGImagePropertyDPIHeight: CFString = "DPIHeight"
public let kCGImagePropertyDPIWidth: CFString = "DPIWidth"
public let kCGImagePropertyDepth: CFString = "Depth"
public let kCGImagePropertyOrientation: CFString = "Orientation"
public let kCGImagePropertyIsFloat: CFString = "IsFloat"
public let kCGImagePropertyIsIndexed: CFString = "IsIndexed"
public let kCGImagePropertyHasAlpha: CFString = "HasAlpha"
public let kCGImagePropertyColorModel: CFString = "ColorModel"
public let kCGImagePropertyProfileName: CFString = "ProfileName"
public let kCGImagePropertyNamedColorSpace: CFString = "NamedColorSpace"
public let kCGImagePropertyWidth: CFString = "Width"
public let kCGImagePropertyHeight: CFString = "Height"
public let kCGImagePropertyBytesPerRow: CFString = "BytesPerRow"
public let kCGImagePropertyPixelFormat: CFString = "PixelFormat"

public let kCGImagePropertyColorModelRGB: CFString = "RGB"
public let kCGImagePropertyColorModelGray: CFString = "Gray"
public let kCGImagePropertyColorModelCMYK: CFString = "CMYK"
public let kCGImagePropertyColorModelLab: CFString = "Lab"

public let kCGImagePropertyTIFFDictionary: CFString = "{TIFF}"
public let kCGImagePropertyGIFDictionary: CFString = "{GIF}"
public let kCGImagePropertyJFIFDictionary: CFString = "{JFIF}"
public let kCGImagePropertyExifDictionary: CFString = "{Exif}"
public let kCGImagePropertyPNGDictionary: CFString = "{PNG}"
public let kCGImagePropertyIPTCDictionary: CFString = "{IPTC}"
public let kCGImagePropertyGPSDictionary: CFString = "{GPS}"
public let kCGImagePropertyWebPDictionary: CFString = "{WebP}"
public let kCGImagePropertyHEICSDictionary: CFString = "{HEICS}"
public let kCGImagePropertyFileContentsDictionary: CFString = "{FileContents}"

public let kCGImagePropertyPNGGamma: CFString = "Gamma"
public let kCGImagePropertyPNGInterlaceType: CFString = "InterlaceType"
public let kCGImagePropertyPNGXPixelsPerMeter: CFString = "XPixelsPerMeter"
public let kCGImagePropertyPNGYPixelsPerMeter: CFString = "YPixelsPerMeter"
public let kCGImagePropertyPNGCompressionFilter: CFString = "kCGImagePropertyPNGCompressionFilter"

public let kCGImagePropertyGIFDelayTime: CFString = "DelayTime"
public let kCGImagePropertyGIFLoopCount: CFString = "LoopCount"
public let kCGImagePropertyGIFUnclampedDelayTime: CFString = "UnclampedDelayTime"
public let kCGImagePropertyGIFHasGlobalColorMap: CFString = "HasGlobalColorMap"

public let kCGImagePropertyTIFFCompression: CFString = "Compression"
public let kCGImagePropertyTIFFOrientation: CFString = "Orientation"
public let kCGImagePropertyTIFFXResolution: CFString = "XResolution"
public let kCGImagePropertyTIFFYResolution: CFString = "YResolution"
public let kCGImagePropertyTIFFResolutionUnit: CFString = "ResolutionUnit"

public let kCGImagePropertyJFIFVersion: CFString = "JFIFVersion"
public let kCGImagePropertyJFIFXDensity: CFString = "XDensity"
public let kCGImagePropertyJFIFYDensity: CFString = "YDensity"
public let kCGImagePropertyJFIFDensityUnit: CFString = "DensityUnit"
public let kCGImagePropertyJFIFIsProgressive: CFString = "IsProgressive"

public let kCGImagePropertyExifPixelXDimension: CFString = "PixelXDimension"
public let kCGImagePropertyExifPixelYDimension: CFString = "PixelYDimension"
public let kCGImagePropertyExifDateTimeOriginal: CFString = "DateTimeOriginal"
public let kCGImagePropertyExifUserComment: CFString = "UserComment"

/// EXIF/TIFF orientation values (CGImageProperties.h), the type of `kCGImagePropertyOrientation`.
public enum CGImagePropertyOrientation: UInt32, Sendable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8
}
