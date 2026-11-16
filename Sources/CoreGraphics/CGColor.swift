import Foundation

public final class CGColorSpace: Equatable, @unchecked Sendable {
    public static let sRGB = "kCGColorSpaceSRGB"
    public static let extendedSRGB = "kCGColorSpaceExtendedSRGB"
    public static let linearSRGB = "kCGColorSpaceLinearSRGB"
    public static let genericRGBLinear = "kCGColorSpaceGenericRGBLinear"
    public static let displayP3 = "kCGColorSpaceDisplayP3"
    public static let adobeRGB1998 = "kCGColorSpaceAdobeRGB1998"
    public static let genericGrayGamma2_2 = "kCGColorSpaceGenericGrayGamma2_2"
    public static let extendedGray = "kCGColorSpaceExtendedGray"
    public static let linearGray = "kCGColorSpaceLinearGray"
    public static let genericCMYK = "kCGColorSpaceGenericCMYK"

    public enum Model: Int32, Sendable { case unknown = -1, monochrome, rgb, cmyk, lab, deviceN, indexed, pattern, XYZ }

    public let name: String?
    public let model: Model

    /// Names the port knows, with their model. The deprecated generic and the device names
    /// are here so AppKit's `NSColorSpace.genericRGB` / `deviceRGB` (and gray, CMYK) can hand
    /// back a colour space with Apple's name; drawing treats every RGB space as sRGB.
    private static let models: [String: Model] = [
        sRGB: .rgb, extendedSRGB: .rgb, linearSRGB: .rgb, genericRGBLinear: .rgb, displayP3: .rgb,
        adobeRGB1998: .rgb, "kCGColorSpaceGenericRGB": .rgb, "kCGColorSpaceDeviceRGB": .rgb,
        genericGrayGamma2_2: .monochrome, extendedGray: .monochrome, linearGray: .monochrome,
        "kCGColorSpaceGenericGray": .monochrome, "kCGColorSpaceDeviceGray": .monochrome,
        genericCMYK: .cmyk, "kCGColorSpaceDeviceCMYK": .cmyk,
    ]

    public init?(name: String) {
        guard let m = CGColorSpace.models[name] else { return nil }
        self.name = name
        self.model = m
    }
    public var numberOfComponents: Int {
        switch model {
        case .monochrome: return 1
        case .cmyk: return 4
        default: return 3
        }
    }
    public static func == (l: CGColorSpace, r: CGColorSpace) -> Bool { l.name == r.name }
}

public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace(name: "kCGColorSpaceDeviceRGB")! }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace(name: "kCGColorSpaceDeviceGray")! }
public func CGColorSpaceCreateDeviceCMYK() -> CGColorSpace { CGColorSpace(name: "kCGColorSpaceDeviceCMYK")! }

// Hashable as Apple's CF types are. It matters beyond API shape: Foundation on Windows and
// Linux boxes a non-Hashable value with an identity hash, so two equal colours in adjacent
// attribute runs compare equal with different hashes and CFAttributedString traps
// (CFBasicHashesAreEqual) when it merges the runs, e.g. two attachments side by side.
extension CGColorSpace: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

/// A color in sRGB, premultiplication deferred to the rasterizer. Other color spaces are
/// converted on creation; Direct2D composites in sRGB.
/// An NSObject on Windows and Linux so swift-corelibs-foundation stores it in attributed
/// strings as itself, not boxed (a box's first word is this colour's address; see
/// `_cfinfo`). Equality and hashing are by component values, as with CoreGraphics' colours.
public final class CGColor: NSObject, @unchecked Sendable {
    /// First stored word: a non-zero CF type ID for swift-corelibs-foundation, which reads a
    /// Swift object's type from it when the object is an attributed-string attribute value
    /// (see AppKit's Support/CFBridgeLayout.swift). A pointer here gave a type ID from the
    /// heap address, and CFEqual halted whenever that came out 0.
    private let _cfinfo: UInt64 = 0x3FF << 8
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
        if components.count == 5 {   // CMYK, naively through device RGB
            let k = 1 - components[3]
            return ((1 - components[0]) * k, (1 - components[1]) * k, (1 - components[2]) * k, components[4])
        }
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

    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CGColor else { return false }
        return o.rgba == rgba
    }
    public override var hash: Int {
        var hasher = Hasher()
        let (r, g, b, a) = rgba
        hasher.combine(r); hasher.combine(g); hasher.combine(b); hasher.combine(a)
        return hasher.finalize()
    }
}
