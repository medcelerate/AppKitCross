import Foundation

public final class CGColorSpace: Equatable, @unchecked Sendable {
    public static let sRGB = "kCGColorSpaceSRGB"
    public static let genericRGBLinear = "kCGColorSpaceGenericRGBLinear"
    public static let genericGrayGamma2_2 = "kCGColorSpaceGenericGrayGamma2_2"
    public static let displayP3 = "kCGColorSpaceDisplayP3"

    public enum Model: Int32, Sendable { case unknown = -1, monochrome, rgb, cmyk, lab, deviceN, indexed, pattern, XYZ }

    public let name: String?
    public let model: Model

    public init?(name: String) {
        self.name = name
        switch name {
        case CGColorSpace.sRGB, CGColorSpace.genericRGBLinear, CGColorSpace.displayP3: model = .rgb
        case CGColorSpace.genericGrayGamma2_2: model = .monochrome
        default: return nil
        }
    }
    public var numberOfComponents: Int { model == .monochrome ? 1 : 3 }
    public static func == (l: CGColorSpace, r: CGColorSpace) -> Bool { l.name == r.name }
}

/// A color in sRGB, premultiplication deferred to the rasterizer. Other color spaces are
/// converted on creation; Direct2D composites in sRGB.
public final class CGColor: Equatable, @unchecked Sendable {
    public let colorSpace: CGColorSpace?
    public let components: [CGFloat]      // r, g, b, a  (or w, a for monochrome)

    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        components = [red, green, blue, alpha]
    }
    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    public init(gray: CGFloat, alpha: CGFloat) {
        colorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        components = [gray, alpha]
    }
    public init?(colorSpace: CGColorSpace, components: UnsafePointer<CGFloat>) {
        self.colorSpace = colorSpace
        let n = colorSpace.numberOfComponents + 1
        self.components = Array(UnsafeBufferPointer(start: components, count: n))
    }

    public var numberOfComponents: Int { components.count }
    public var alpha: CGFloat { components.last ?? 1 }

    /// sRGB red, green, blue, alpha whatever the storage model.
    public var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
        if components.count == 2 { return (components[0], components[0], components[0], components[1]) }
        return (components[0], components[1], components[2], components[3])
    }

    public func copy(alpha: CGFloat) -> CGColor? {
        if components.count == 2 { return CGColor(gray: components[0], alpha: alpha) }
        return CGColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: alpha)
    }
    public func copy() -> CGColor? { self }

    public static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    public static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public static let clear = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    public static func == (l: CGColor, r: CGColor) -> Bool { l.rgba == r.rgba }
}
