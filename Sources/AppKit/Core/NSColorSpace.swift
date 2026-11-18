// NSColorSpace (hand-written; seeded from the generated stub, ADR-0037).
//
// Every colour space is a matrix/TRC profile in the ICC sense: linear RGB to CIE XYZ relative
// to D50 (the ICC profile connection space), plus a transfer curve per channel; gray spaces
// have one curve, CMYK spaces convert naively through device RGB. The standard spaces carry
// Apple's names and primaries, and their ICC profiles are synthesised (ICC v4, `para`
// curves), so `iccProfileData` round-trips through `init(iccProfileData:)` on every
// platform. `cgColorSpace` hands back the platform CGColorSpace with Apple's name (the port's
// own CoreGraphics on Windows and Linux, Apple's on the macOS host build).

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

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace
open class NSColorSpace: NSObject, NSSecureCoding, NSCoding {

    // MARK: Storage

    internal let _profile: _NSColorSpaceProfile
    internal let _standard: _NSStandardColorSpace?
    private let _explicitICC: Data?
    private let _explicitCG: CGColorSpace?

    internal init(_standard s: _NSStandardColorSpace) {
        _profile = s.profile
        _standard = s
        _explicitICC = nil
        _explicitCG = nil
        super.init()
    }

    private init(_profile p: _NSColorSpaceProfile, icc: Data?, cg: CGColorSpace?) {
        _profile = p
        _standard = _NSStandardColorSpace.matching(p)
        _explicitICC = icc
        _explicitCG = cg
        super.init()
    }

    // MARK: Initialisers

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/init(cgcolorspace:)
    /// A CGColorSpace with one of Apple's standard names becomes that standard space (equal to
    /// `NSColorSpace.sRGB` and so on); any other keeps the CGColorSpace and takes its model,
    /// reading its ICC profile where the platform's CoreGraphics provides one.
    public init?(cgColorSpace: CGColorSpace) {
        if let name = _NSCGColorSpaceName(cgColorSpace), let s = _NSStandardColorSpace.forCGName(name) {
            _profile = s.profile
            _standard = s
            _explicitICC = nil
            _explicitCG = cgColorSpace
            super.init()
            return
        }
        let icc = _NSCGColorSpaceICCData(cgColorSpace)
        let parsed = icc.flatMap { _NSICCProfile.parse($0) }
        let profile: _NSColorSpaceProfile
        if let parsed = parsed {
            profile = parsed
        } else {
            switch cgColorSpace.model {
            case .rgb: profile = _NSStandardColorSpace.sRGB.profile.renamed(nil)
            case .monochrome: profile = _NSStandardColorSpace.genericGamma22Gray.profile.renamed(nil)
            case .cmyk: profile = _NSStandardColorSpace.deviceCMYK.profile.renamed(nil)
            default: return nil
            }
        }
        _profile = profile
        _standard = nil
        _explicitICC = icc
        _explicitCG = cgColorSpace
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/init(colorsyncprofile:)
    /// Out of scope (ADR-0037): ColorSync does not exist on Windows or Linux; use
    /// `init(iccProfileData:)` with the profile's bytes.
    public init?(colorSyncProfile prof: UnsafeMutableRawPointer) { appleOnlyUnavailable("NSColorSpace.init(colorSyncProfile:) — ColorSync is macOS-only") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/init(iccprofiledata:)
    /// Reads RGB matrix/TRC and gray TRC profiles (ICC v2 and v4: `curv` and `para` curves,
    /// `desc` and `mluc` names) and CMYK headers. A profile describing one of the standard
    /// spaces (same name and colorants) is equal to that space. Profiles of other kinds
    /// (LUT-based, Lab) answer nil.
    public init?(iccProfileData iccData: Data) {
        guard let p = _NSICCProfile.parse(iccData) else { return nil }
        _profile = p
        _standard = _NSStandardColorSpace.matching(p)
        _explicitICC = iccData
        _explicitCG = nil
        super.init()
    }

    // MARK: Standard spaces

    nonisolated(unsafe) private static let _shared: [_NSStandardColorSpace: NSColorSpace] = {
        var d: [_NSStandardColorSpace: NSColorSpace] = [:]
        for s in _NSStandardColorSpace.allCases { d[s] = NSColorSpace(_standard: s) }
        return d
    }()
    internal static func _standardSpace(_ s: _NSStandardColorSpace) -> NSColorSpace { _shared[s]! }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/adobergb1998
    class public var adobeRGB1998: NSColorSpace { _standardSpace(.adobeRGB1998) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/devicecmyk
    class public var deviceCMYK: NSColorSpace { _standardSpace(.deviceCMYK) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/devicegray
    class public var deviceGray: NSColorSpace { _standardSpace(.deviceGray) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/devicergb
    class public var deviceRGB: NSColorSpace { _standardSpace(.deviceRGB) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/displayp3
    @available(macOS 10.12, *)
    class public var displayP3: NSColorSpace { _standardSpace(.displayP3) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/extendedgenericgamma22gray
    @available(macOS 10.12, *)
    class public var extendedGenericGamma22Gray: NSColorSpace { _standardSpace(.extendedGenericGamma22Gray) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/extendedsrgb
    @available(macOS 10.12, *)
    class public var extendedSRGB: NSColorSpace { _standardSpace(.extendedSRGB) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/genericcmyk
    /// The port has no CMYK ICC profile: `iccProfileData` is nil and conversions go naively
    /// through device RGB (c = 1 − r, ..., with black generation k = 1 − max(r, g, b)).
    class public var genericCMYK: NSColorSpace { _standardSpace(.genericCMYK) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/genericgamma22gray
    class public var genericGamma22Gray: NSColorSpace { _standardSpace(.genericGamma22Gray) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/genericgray
    class public var genericGray: NSColorSpace { _standardSpace(.genericGray) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/genericrgb
    class public var genericRGB: NSColorSpace { _standardSpace(.genericRGB) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/srgb
    class public var sRGB: NSColorSpace { _standardSpace(.sRGB) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/availablecolorspaces(with:)
    /// The standard spaces of `model` (all of them, gray then RGB then CMYK, for `.unknown`),
    /// each group sorted by localized name. The extended variants are not listed, as in AppKit.
    public class func availableColorSpaces(with model: NSColorSpace.Model) -> [NSColorSpace] {
        let listed = _NSStandardColorSpace.allCases.filter { !$0.profile.extended }
        func group(_ m: NSColorSpace.Model) -> [NSColorSpace] {
            listed.filter { $0.profile.model == m }
                .sorted { $0.profile.name ?? "" < $1.profile.name ?? "" }
                .map { _standardSpace($0) }
        }
        if model == .unknown { return group(.gray) + group(.rgb) + group(.cmyk) }
        return group(model)
    }

    // MARK: Properties

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/cgcolorspace
    open var cgColorSpace: CGColorSpace? {
        if let cg = _explicitCG { return cg }
        if let s = _standard { return s.makeCGColorSpace() }
        if let icc = _explicitICC { return _NSCGColorSpaceFromICC(icc) }
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/colorspacemodel
    open var colorSpaceModel: NSColorSpace.Model { _profile.model }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/colorsyncprofile
    /// Out of scope (ADR-0037): ColorSync is macOS-only; `iccProfileData` has the bytes.
    open var colorSyncProfile: UnsafeMutableRawPointer? { appleOnlyUnavailable("NSColorSpace.colorSyncProfile — ColorSync is macOS-only") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/iccprofiledata
    /// The bytes a space was made from, or a synthesised ICC v4 profile for the standard
    /// spaces. Device spaces have none (as in AppKit), nor do the CMYK spaces on the port.
    open var iccProfileData: Data? {
        if let d = _explicitICC { return d }
        if let s = _standard { return s.iccData }
        return _NSICCProfile.write(_profile)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/localizedname
    /// English names, as AppKit gives them in an English locale.
    open var localizedName: String? { _profile.name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/numberofcolorcomponents
    open var numberOfColorComponents: Int {
        switch _profile.model {
        case .gray: return 1
        case .cmyk: return 4
        case .rgb, .lab: return 3
        default: return 0
        }
    }

    open override var description: String {
        (localizedName ?? "Unnamed") + (_profile.extended ? " (extended)" : "") + " colorspace"
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSColorSpace else { return false }
        if o === self { return true }
        if let a = _standard, let b = o._standard { return a == b }
        if _standard != nil || o._standard != nil { return false }
        if let a = _explicitICC, let b = o._explicitICC { return a == b }
        return _profile == o._profile
    }
    open override var hash: Int {
        if let s = _standard { return s.hashValue }
        return _profile.hashValue
    }

    // MARK: Coding

    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    /// Archives the standard space's identifier ("NSID") or the ICC bytes ("NSICC").
    open func encode(with coder: NSCoder) {
        coder.encode(_profile.model.rawValue, forKey: "NSModel")
        if let s = _standard {
            coder.encode(s.rawValue + 1, forKey: "NSID")
        } else if let d = iccProfileData {
            coder.encode(d, forKey: "NSICC")
        }
    }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) {
        let id = coder.decodeInteger(forKey: "NSID")
        if id > 0, let s = _NSStandardColorSpace(rawValue: id - 1) {
            _profile = s.profile
            _standard = s
            _explicitICC = nil
            _explicitCG = nil
        } else if let d = coder.decodeObject(of: NSData.self, forKey: "NSICC") as Data?,
                  let p = _NSICCProfile.parse(d) {
            _profile = p
            _standard = _NSStandardColorSpace.matching(p)
            _explicitICC = d
            _explicitCG = nil
        } else {
            return nil
        }
        super.init()
    }

    // MARK: Conversion (internal; NSColor and NSBitmapImageRep convert through this)

    /// Converts colour components (no alpha) from this space to `target` through the D50
    /// connection space. Nil when either space is not RGB, gray or CMYK, or the count is wrong.
    internal func _convert(_ components: [CGFloat], to target: NSColorSpace) -> [CGFloat]? {
        guard components.count == numberOfColorComponents else { return nil }
        if isEqual(target) { return components }
        guard let xyz = _profile.toPCS(components.map { Double($0) }),
              let out = target._profile.fromPCS(xyz) else { return nil }
        return out.map { CGFloat($0) }
    }
}

extension NSColorSpace {
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model
    public enum Model: Int, Sendable, Equatable, Hashable {
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/cmyk
        case cmyk = 2
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/devicen
        case deviceN = 4
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/gray
        case gray = 0
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/indexed
        case indexed = 5
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/lab
        case lab = 3
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/patterned
        case patterned = 6
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/rgb
        case rgb = 1
        /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolorspace/model/unknown
        case unknown = -1
    }
}

// MARK: - CoreGraphics bridging (Apple's CG takes CFString names; the port's takes String)

internal func _NSCGColorSpace(named name: String) -> CGColorSpace? {
    #if os(Windows) || os(Linux)
    return CGColorSpace(name: name)
    #else
    return CGColorSpace(name: name as CFString)
    #endif
}

internal func _NSCGColorSpaceName(_ cg: CGColorSpace) -> String? {
    #if os(Windows) || os(Linux)
    return cg.name
    #else
    return cg.name as String?
    #endif
}

internal func _NSCGColorSpaceICCData(_ cg: CGColorSpace) -> Data? {
    #if os(Windows) || os(Linux)
    return nil     // the port's CGColorSpace carries no ICC profile
    #else
    return cg.copyICCData() as Data?
    #endif
}

internal func _NSCGColorSpaceFromICC(_ data: Data) -> CGColorSpace? {
    #if os(Windows) || os(Linux)
    return nil     // the port's CGColorSpace is name-based
    #else
    return CGColorSpace(iccData: data as CFData)
    #endif
}

// MARK: - Standard spaces

internal enum _NSStandardColorSpace: Int, CaseIterable, Hashable {
    case sRGB, extendedSRGB, genericRGB, deviceRGB, displayP3, adobeRGB1998
    case genericGray, deviceGray, genericGamma22Gray, extendedGenericGamma22Gray
    case genericCMYK, deviceCMYK

    /// Apple's CoreGraphics name for the space (`kCGColorSpace…`).
    var cgName: String {
        switch self {
        case .sRGB: return "kCGColorSpaceSRGB"
        case .extendedSRGB: return "kCGColorSpaceExtendedSRGB"
        case .genericRGB: return "kCGColorSpaceGenericRGB"
        case .deviceRGB: return "kCGColorSpaceDeviceRGB"
        case .displayP3: return "kCGColorSpaceDisplayP3"
        case .adobeRGB1998: return "kCGColorSpaceAdobeRGB1998"
        case .genericGray: return "kCGColorSpaceGenericGray"
        case .deviceGray: return "kCGColorSpaceDeviceGray"
        case .genericGamma22Gray: return "kCGColorSpaceGenericGrayGamma2_2"
        case .extendedGenericGamma22Gray: return "kCGColorSpaceExtendedGray"
        case .genericCMYK: return "kCGColorSpaceGenericCMYK"
        case .deviceCMYK: return "kCGColorSpaceDeviceCMYK"
        }
    }

    static func forCGName(_ name: String) -> _NSStandardColorSpace? {
        allCases.first { $0.cgName == name }
    }

    func makeCGColorSpace() -> CGColorSpace? {
        switch self {
        case .deviceRGB: return CGColorSpaceCreateDeviceRGB()
        case .deviceGray: return CGColorSpaceCreateDeviceGray()
        case .deviceCMYK: return CGColorSpaceCreateDeviceCMYK()
        default: return _NSCGColorSpace(named: cgName)
        }
    }

    var isDevice: Bool { self == .deviceRGB || self == .deviceGray || self == .deviceCMYK }

    var profile: _NSColorSpaceProfile {
        typealias P = _NSColorSpaceProfile
        switch self {
        case .sRGB: return P.rgb("sRGB IEC61966-2.1", P.rec709, .sRGB)
        case .extendedSRGB: return P.rgb("sRGB IEC61966-2.1", P.rec709, .sRGB, extended: true)
        case .genericRGB: return P.rgb("Generic RGB", P.appleGenericRGB, .gamma(1.8))
        case .deviceRGB: return P.rgb("Device RGB", P.rec709, .sRGB)
        case .displayP3: return P.rgb("Display P3", P.p3, .sRGB)
        case .adobeRGB1998: return P.rgb("Adobe RGB (1998)", P.adobe1998, .gamma(563.0 / 256.0))
        case .genericGray: return P.gray("Generic Gray", .gamma(1.8))
        case .deviceGray: return P.gray("Device Gray", .gamma(2.2))
        case .genericGamma22Gray: return P.gray("Generic Gray Gamma 2.2 Profile", .gamma(2.2))
        case .extendedGenericGamma22Gray: return P.gray("Generic Gray Gamma 2.2 Profile", .gamma(2.2), extended: true)
        case .genericCMYK: return P(model: .cmyk, name: "Generic CMYK", matrix: nil, curves: [], extended: false)
        case .deviceCMYK: return P(model: .cmyk, name: "Device CMYK", matrix: nil, curves: [], extended: false)
        }
    }

    /// Synthesised ICC profile; none for device and CMYK spaces.
    var iccData: Data? {
        if isDevice || profile.model == .cmyk { return nil }
        return _NSICCProfile.write(profile)
    }

    /// The standard space a parsed or CoreGraphics profile describes: same model, name and
    /// (for RGB) colorants and curves. Non-extended and non-device spaces win ties.
    static func matching(_ p: _NSColorSpaceProfile) -> _NSStandardColorSpace? {
        allCases.first { s in
            !s.isDevice && s.profile.model != .cmyk && s.profile.approximatelyEquals(p)
        }
    }
}

// MARK: - Profiles and transfer curves

internal enum _NSTransferCurve: Hashable {
    case gamma(Double)
    /// ICC parametric type 3 / IEC 61966-2-1: Y = (aX + b)^g for X ≥ d, cX below.
    case parametric(g: Double, a: Double, b: Double, c: Double, d: Double)
    /// A sampled `curv` table, values 0…1 at evenly spaced inputs.
    case table([Double])

    static let sRGB = _NSTransferCurve.parametric(g: 2.4, a: 1 / 1.055, b: 0.055 / 1.055, c: 1 / 12.92, d: 0.04045)

    /// Encoded value → linear light. Extended curves mirror negative values.
    func decode(_ x: Double) -> Double {
        let s: Double = x < 0 ? -1 : 1, v = abs(x)
        switch self {
        case .gamma(let g): return s * pow(v, g)
        case let .parametric(g, a, b, c, d): return s * (v >= d ? pow(a * v + b, g) : c * v)
        case .table(let t):
            guard t.count > 1 else { return x }
            let p = min(v, 1) * Double(t.count - 1), i = min(Int(p), t.count - 2), f = p - Double(i)
            return s * (t[i] + (t[i + 1] - t[i]) * f)
        }
    }
    /// Linear light → encoded value.
    func encode(_ y: Double) -> Double {
        let s: Double = y < 0 ? -1 : 1, v = abs(y)
        switch self {
        case .gamma(let g): return s * pow(v, 1 / g)
        case let .parametric(g, a, b, c, d):
            let knee = c * d
            return s * (v >= knee ? (pow(v, 1 / g) - b) / a : v / c)
        case .table(let t):
            guard t.count > 1 else { return y }
            if v <= t[0] { return 0 }
            if v >= t[t.count - 1] { return s }
            var lo = 0, hi = t.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if t[m] <= v { lo = m } else { hi = m } }
            let f = t[hi] == t[lo] ? 0 : (v - t[lo]) / (t[hi] - t[lo])
            return s * (Double(lo) + f) / Double(t.count - 1)
        }
    }

    func approximatelyEquals(_ o: _NSTransferCurve) -> Bool {
        for x in stride(from: 0.0, through: 1.0, by: 0.125) where abs(decode(x) - o.decode(x)) > 2e-3 { return false }
        return true
    }
}

internal struct _NSColorSpaceProfile: Hashable {
    var model: NSColorSpace.Model
    var name: String?
    /// Linear RGB → XYZ (D50), row-major 3×3. Nil for gray and CMYK.
    var matrix: [Double]?
    var curves: [_NSTransferCurve]
    var extended: Bool

    func renamed(_ n: String?) -> _NSColorSpaceProfile { var p = self; p.name = n; return p }

    static let d50: [Double] = [0.9642, 1.0, 0.8249]

    // Primaries (x, y for red, green, blue) and white point (x, y).
    static let rec709: [Double] = [0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.3290]
    static let p3: [Double] = [0.680, 0.320, 0.265, 0.690, 0.150, 0.060, 0.3127, 0.3290]
    static let adobe1998: [Double] = [0.64, 0.33, 0.21, 0.71, 0.15, 0.06, 0.3127, 0.3290]
    /// Apple's "Generic RGB" (Trinitron-like phosphors, D65, gamma 1.8).
    static let appleGenericRGB: [Double] = [0.630, 0.340, 0.295, 0.605, 0.155, 0.077, 0.3127, 0.3290]

    static func rgb(_ name: String, _ prim: [Double], _ curve: _NSTransferCurve, extended: Bool = false) -> _NSColorSpaceProfile {
        _NSColorSpaceProfile(model: .rgb, name: name, matrix: _NSMatrix.adaptedToD50(primaries: prim),
                             curves: [curve, curve, curve], extended: extended)
    }
    static func gray(_ name: String, _ curve: _NSTransferCurve, extended: Bool = false) -> _NSColorSpaceProfile {
        _NSColorSpaceProfile(model: .gray, name: name, matrix: nil, curves: [curve], extended: extended)
    }

    func approximatelyEquals(_ o: _NSColorSpaceProfile) -> Bool {
        guard model == o.model, name == o.name, curves.count == o.curves.count else { return false }
        for (a, b) in zip(curves, o.curves) where !a.approximatelyEquals(b) { return false }
        switch (matrix, o.matrix) {
        case (nil, nil): return true
        case let (a?, b?): return zip(a, b).allSatisfy { abs($0 - $1) < 1e-3 }
        default: return false
        }
    }

    /// Components → XYZ (D50).
    func toPCS(_ c: [Double]) -> [Double]? {
        switch model {
        case .rgb:
            guard let m = matrix, c.count == 3, curves.count == 3 else { return nil }
            let lin = (0..<3).map { curves[$0].decode(c[$0]) }
            return _NSMatrix.apply(m, lin)
        case .gray:
            guard c.count == 1, let curve = curves.first else { return nil }
            let y = curve.decode(c[0])
            return _NSColorSpaceProfile.d50.map { $0 * y }
        case .cmyk:
            guard c.count == 4 else { return nil }
            let k = 1 - c[3]
            let rgb = [(1 - c[0]) * k, (1 - c[1]) * k, (1 - c[2]) * k]
            return _NSStandardColorSpace.deviceRGB.profile.toPCS(rgb)
        default:
            return nil
        }
    }

    /// XYZ (D50) → components, clamped to 0…1 unless the space is extended.
    func fromPCS(_ xyz: [Double]) -> [Double]? {
        func clamp(_ v: Double) -> Double { extended ? v : min(1, max(0, v)) }
        switch model {
        case .rgb:
            guard let m = matrix, let inv = _NSMatrix.inverse(m), curves.count == 3 else { return nil }
            let lin = _NSMatrix.apply(inv, xyz)
            return (0..<3).map { clamp(curves[$0].encode(lin[$0])) }
        case .gray:
            guard let curve = curves.first else { return nil }
            return [clamp(curve.encode(xyz[1]))]
        case .cmyk:
            guard let rgb = _NSStandardColorSpace.deviceRGB.profile.fromPCS(xyz) else { return nil }
            let k = 1 - max(rgb[0], rgb[1], rgb[2])
            if k >= 1 { return [0, 0, 0, 1] }
            return [(1 - rgb[0] - k) / (1 - k), (1 - rgb[1] - k) / (1 - k), (1 - rgb[2] - k) / (1 - k), k]
        default:
            return nil
        }
    }
}

internal enum _NSMatrix {
    static func apply(_ m: [Double], _ v: [Double]) -> [Double] {
        [m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
         m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
         m[6] * v[0] + m[7] * v[1] + m[8] * v[2]]
    }
    static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                var sum = 0.0
                for k in 0..<3 { sum += a[i * 3 + k] * b[k * 3 + j] }
                r[i * 3 + j] = sum
            }
        }
        return r
    }
    static func inverse(_ m: [Double]) -> [Double]? {
        let det = m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6])
        guard abs(det) > 1e-12 else { return nil }
        let i = 1 / det
        return [(m[4] * m[8] - m[5] * m[7]) * i, (m[2] * m[7] - m[1] * m[8]) * i, (m[1] * m[5] - m[2] * m[4]) * i,
                (m[5] * m[6] - m[3] * m[8]) * i, (m[0] * m[8] - m[2] * m[6]) * i, (m[2] * m[3] - m[0] * m[5]) * i,
                (m[3] * m[7] - m[4] * m[6]) * i, (m[1] * m[6] - m[0] * m[7]) * i, (m[0] * m[4] - m[1] * m[3]) * i]
    }
    static func xyz(_ x: Double, _ y: Double) -> [Double] { [x / y, 1, (1 - x - y) / y] }

    /// RGB → XYZ for the primaries and white, Bradford-adapted to D50 as ICC profiles store it.
    static func adaptedToD50(primaries p: [Double]) -> [Double] {
        let r = xyz(p[0], p[1]), g = xyz(p[2], p[3]), b = xyz(p[4], p[5]), w = xyz(p[6], p[7])
        let prim = [r[0], g[0], b[0], r[1], g[1], b[1], r[2], g[2], b[2]]
        let s = apply(inverse(prim)!, w)
        let m = [prim[0] * s[0], prim[1] * s[1], prim[2] * s[2],
                 prim[3] * s[0], prim[4] * s[1], prim[5] * s[2],
                 prim[6] * s[0], prim[7] * s[1], prim[8] * s[2]]
        let brad: [Double] = [0.8951, 0.2664, -0.1614, -0.7502, 1.7135, 0.0367, 0.0389, -0.0685, 1.0296]
        let src = apply(brad, w), dst = apply(brad, _NSColorSpaceProfile.d50)
        let scale: [Double] = [dst[0] / src[0], 0, 0, 0, dst[1] / src[1], 0, 0, 0, dst[2] / src[2]]
        let adapt = multiply(inverse(brad)!, multiply(scale, brad))
        return multiply(adapt, m)
    }
}

// MARK: - ICC profiles (write v4 matrix/TRC; read v2 and v4 matrix/TRC)

internal enum _NSICCProfile {
    private static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
    private static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xff)] }
    private static func sig(_ s: String) -> [UInt8] { Array(s.utf8.prefix(4)) + [UInt8](repeating: 0x20, count: max(0, 4 - s.utf8.count)) }
    private static func s15(_ v: Double) -> [UInt8] { be32(UInt32(bitPattern: Int32((v * 65536).rounded()))) }

    private static func mluc(_ text: String) -> [UInt8] {
        let u = Array(text.utf16).flatMap { be16($0) }
        return sig("mluc") + be32(0) + be32(1) + be32(12) + Array("enUS".utf8) + be32(UInt32(u.count)) + be32(28) + u
    }
    private static func xyzTag(_ v: [Double]) -> [UInt8] { sig("XYZ ") + be32(0) + v.flatMap { s15($0) } }
    private static func curveTag(_ c: _NSTransferCurve) -> [UInt8] {
        switch c {
        case .gamma(let g): return sig("para") + be32(0) + be16(0) + be16(0) + s15(g)
        case let .parametric(g, a, b, cc, d):
            return sig("para") + be32(0) + be16(3) + be16(0) + [g, a, b, cc, d].flatMap { s15($0) }
        case .table(let t):
            return sig("curv") + be32(0) + be32(UInt32(t.count)) + t.flatMap { be16(UInt16(min(1, max(0, $0)) * 65535)) }
        }
    }

    /// An ICC v4 display profile for an RGB matrix/TRC or gray TRC profile; nil otherwise.
    static func write(_ p: _NSColorSpaceProfile) -> Data? {
        var tags: [(String, [UInt8])] = [("desc", mluc(p.name ?? "Unnamed")), ("cprt", mluc("No copyright, use freely")),
                                          ("wtpt", xyzTag(_NSColorSpaceProfile.d50))]
        let space: String
        switch p.model {
        case .rgb:
            guard let m = p.matrix, p.curves.count == 3 else { return nil }
            space = "RGB "
            tags += [("rXYZ", xyzTag([m[0], m[3], m[6]])), ("gXYZ", xyzTag([m[1], m[4], m[7]])), ("bXYZ", xyzTag([m[2], m[5], m[8]])),
                     ("rTRC", curveTag(p.curves[0])), ("gTRC", curveTag(p.curves[1])), ("bTRC", curveTag(p.curves[2]))]
        case .gray:
            guard let c = p.curves.first else { return nil }
            space = "GRAY"
            tags.append(("kTRC", curveTag(c)))
        default:
            return nil
        }
        var table: [UInt8] = be32(UInt32(tags.count))
        var body: [UInt8] = []
        var offset = 128 + 4 + 12 * tags.count
        for (s, d) in tags {
            table += sig(s) + be32(UInt32(offset)) + be32(UInt32(d.count))
            var padded = d
            while padded.count % 4 != 0 { padded.append(0) }
            body += padded
            offset += padded.count
        }
        let size = 128 + table.count + body.count
        var h: [UInt8] = be32(UInt32(size)) + be32(0) + be32(0x0430_0000) + sig("mntr") + sig(space) + sig("XYZ ")
        h += be16(2026) + be16(1) + be16(1) + be16(0) + be16(0) + be16(0)          // creation date (fixed)
        h += sig("acsp") + be32(0) + be32(0) + be32(0) + be32(0) + be32(0) + be32(0) + be32(0)
        h += _NSColorSpaceProfile.d50.flatMap { s15($0) } + be32(0)
        h += [UInt8](repeating: 0, count: 128 - h.count)
        return Data(h + table + body)
    }

    /// Reads an RGB matrix/TRC, gray TRC or CMYK profile; nil for anything else.
    static func parse(_ data: Data) -> _NSColorSpaceProfile? {
        let b = [UInt8](data)
        guard b.count >= 132 else { return nil }
        func u32(_ o: Int) -> UInt32? {
            guard o >= 0, o + 4 <= b.count else { return nil }
            return UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
        }
        func u16(_ o: Int) -> UInt16? { guard o >= 0, o + 2 <= b.count else { return nil }; return UInt16(b[o]) << 8 | UInt16(b[o + 1]) }
        func s15(_ o: Int) -> Double? { u32(o).map { Double(Int32(bitPattern: $0)) / 65536 } }
        func str(_ o: Int) -> String { String(decoding: b[o..<min(o + 4, b.count)], as: UTF8.self) }
        guard str(36) == "acsp", let n = u32(128), n < 1000 else { return nil }
        var tags: [String: (Int, Int)] = [:]
        for i in 0..<Int(n) {
            let e = 132 + 12 * i
            guard let off = u32(e + 4), let len = u32(e + 8), Int(off) + Int(len) <= b.count else { return nil }
            tags[str(e)] = (Int(off), Int(len))
        }
        func name() -> String? {
            guard let (o, len) = tags["desc"] else { return nil }
            switch str(o) {
            case "mluc":
                guard let count = u32(o + 8), count > 0, let l = u32(o + 20), let so = u32(o + 24) else { return nil }
                let start = o + Int(so), end = start + Int(l)
                guard end <= b.count, end <= o + len else { return nil }
                var units: [UInt16] = []
                var i = start
                while i + 1 < end { units.append(UInt16(b[i]) << 8 | UInt16(b[i + 1])); i += 2 }
                return String(decoding: units, as: UTF16.self)
            case "desc":
                guard let l = u32(o + 8), l > 0, o + 12 + Int(l) <= b.count else { return nil }
                return String(decoding: b[(o + 12)..<(o + 12 + Int(l) - 1)], as: UTF8.self)
            default:
                return nil
            }
        }
        func xyz(_ s: String) -> [Double]? {
            guard let (o, _) = tags[s], str(o) == "XYZ ", let x = s15(o + 8), let y = s15(o + 12), let z = s15(o + 16) else { return nil }
            return [x, y, z]
        }
        func curve(_ s: String) -> _NSTransferCurve? {
            guard let (o, _) = tags[s] else { return nil }
            switch str(o) {
            case "curv":
                guard let count = u32(o + 8) else { return nil }
                if count == 0 { return .gamma(1) }
                if count == 1 { return u16(o + 12).map { .gamma(Double($0) / 256) } }
                var t: [Double] = []
                for i in 0..<Int(count) { guard let v = u16(o + 12 + 2 * i) else { return nil }; t.append(Double(v) / 65535) }
                return .table(t)
            case "para":
                guard let type = u16(o + 8) else { return nil }
                let p = (0..<7).compactMap { s15(o + 12 + 4 * $0) }
                switch type {
                case 0: return p.count >= 1 ? .gamma(p[0]) : nil
                case 3, 4: return p.count >= 5 ? .parametric(g: p[0], a: p[1], b: p[2], c: p[3], d: p[4]) : nil
                default: return nil
                }
            default:
                return nil
            }
        }
        switch str(16) {
        case "RGB ":
            guard let r = xyz("rXYZ"), let g = xyz("gXYZ"), let bl = xyz("bXYZ"),
                  let rc = curve("rTRC"), let gc = curve("gTRC"), let bc = curve("bTRC") else { return nil }
            return _NSColorSpaceProfile(model: .rgb, name: name(), matrix: [r[0], g[0], bl[0], r[1], g[1], bl[1], r[2], g[2], bl[2]],
                                        curves: [rc, gc, bc], extended: false)
        case "GRAY":
            guard let k = curve("kTRC") else { return nil }
            return _NSColorSpaceProfile(model: .gray, name: name(), matrix: nil, curves: [k], extended: false)
        case "CMYK":
            return _NSColorSpaceProfile(model: .cmyk, name: name(), matrix: nil, curves: [], extended: false)
        default:
            return nil
        }
    }
}
