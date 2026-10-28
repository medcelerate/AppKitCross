import Foundation

public enum CGImageAlphaInfo: UInt32, Sendable {
    case none = 0, premultipliedLast = 1, premultipliedFirst = 2, last = 3, first = 4, noneSkipLast = 5, noneSkipFirst = 6, alphaOnly = 7
}

public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let floatComponents = CGBitmapInfo(rawValue: 1 << 8)
    public static let byteOrderMask = CGBitmapInfo(rawValue: 0x7000)
    public static let byteOrder16Little = CGBitmapInfo(rawValue: 1 << 12)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 2 << 12)
    public static let byteOrder16Big = CGBitmapInfo(rawValue: 3 << 12)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 4 << 12)
}

/// A bitmap image. Milestone 1 only needs the type and raw pixel storage; drawing it into
/// a `CGContext` arrives with WIC/Direct2D bitmaps in Milestone 2.
public final class CGImage: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let bitsPerComponent: Int
    public let bitsPerPixel: Int
    public let bytesPerRow: Int
    public let colorSpace: CGColorSpace?
    public let bitmapInfo: CGBitmapInfo
    public let alphaInfo: CGImageAlphaInfo
    /// Pixel rows, top row first, `bytesPerRow` bytes each.
    public let data: Data

    public init?(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int, bytesPerRow: Int,
                 space: CGColorSpace, bitmapInfo: CGBitmapInfo, data: Data) {
        guard width > 0, height > 0, data.count >= bytesPerRow * height else { return nil }
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.bytesPerRow = bytesPerRow
        self.colorSpace = space
        self.bitmapInfo = bitmapInfo
        self.alphaInfo = CGImageAlphaInfo(rawValue: bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue) ?? .none
        self.data = data
    }

    public func copy() -> CGImage? { self }

    /// BGRA premultiplied, top row first: the native layout of the Direct2D/WIC pipeline.
    public static func fromBGRA(width: Int, height: Int, stride: Int, data: Data) -> CGImage? {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), data: data)
    }
}

/// Display identifier; Windows has no CoreGraphics display IDs, so monitors are numbered.
public typealias CGDirectDisplayID = UInt32
public typealias CGWindowID = UInt32

/// Quartz Event Services do not exist on Windows. The type exists so that AppKit's
/// `NSEvent.cgEvent` family keeps its signatures; instances are never created.
public final class CGEvent: @unchecked Sendable {
    private init() {}
}
