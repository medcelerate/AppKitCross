// NSColor (hand-written; seeded from the generated stub, see tools/apigen)
// Members still marked unimplemented() say why (ADR-0038).
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor
/// `@unchecked Sendable` as Apple's (`NS_SWIFT_SENDABLE`): a colour is immutable once made.
open class NSColor: NSObject, NSAccessibilityColor, NSCopying, NSSecureCoding, NSCoding, NSPasteboardReading, NSPasteboardWriting, @unchecked Sendable {
    #if !canImport(Darwin)
    /// First stored word: a non-zero CF type ID, see Support/CFBridgeLayout.swift.
    private let _cfinfo = _swiftObjectCFInfo
    #endif
    // MARK: Storage
    //
    // Colors are stored as sRGB components (or a gray level). Semantic (system) colors
    // carry their name and resolve to fixed light-appearance values until NSAppearance
    // and the Windows theme bridge exist.
    internal enum Storage: Equatable {
        case rgb(CGFloat, CGFloat, CGFloat, CGFloat)
        case gray(CGFloat, CGFloat)
        case named(String, CGFloat, CGFloat, CGFloat, CGFloat)
        /// A semantic colour whose alpha was replaced (`withAlphaComponent`): the hue still
        /// follows the appearance, the alpha is the caller's.
        case namedAlpha(String, CGFloat, CGFloat, CGFloat, CGFloat)
        /// Device CMYK (cyan, magenta, yellow, black, alpha), converted to RGB naively
        /// (r = (1 − c)(1 − k)); macOS converts through ColorSync profiles (ADR-0038).
        case cmyk(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        /// Components (no alpha) in another colour space (Display P3, Adobe RGB, extended or
        /// linear spaces, ICC profiles), converted to sRGB through NSColorSpace (ADR-0038).
        case space(NSColorSpace, [CGFloat], CGFloat)

        var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
            switch self {
            case let .rgb(r, g, b, a): return (r, g, b, a)
            case let .gray(w, a): return (w, w, w, a)
            case let .cmyk(c, m, y, k, a): return ((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k), a)
            case let .space(cs, comps, a):
                // init(colorSpace:…) admits only spaces NSColorSpace converts (RGB, gray, CMYK).
                let rgb = cs._convert(comps, to: .sRGB)!
                return (rgb[0], rgb[1], rgb[2], a)
            case let .named(name, r, g, b, a):
                if NSAppearance.currentIsDark, let dark = NSColor.darkValues[name] { return dark }
                return (r, g, b, a)
            case let .namedAlpha(name, r, g, b, a):
                if NSAppearance.currentIsDark, let dark = NSColor.darkValues[name] { return (dark.0, dark.1, dark.2, a) }
                return (r, g, b, a)
            }
        }
    }

    /// Dark-appearance values of the semantic colours (Apple's dark Aqua palette).
    internal static let darkValues: [String: (CGFloat, CGFloat, CGFloat, CGFloat)] = [
        "alternatingContentBackgroundColors0": (0.118, 0.118, 0.118, 1), "alternatingContentBackgroundColors1": (0.145, 0.145, 0.145, 1),
        "controlBackgroundColor": (0.118, 0.118, 0.118, 1), "controlColor": (0.4, 0.4, 0.4, 1), "controlTextColor": (1, 1, 1, 0.85),
        "disabledControlTextColor": (1, 1, 1, 0.25), "gridColor": (0.1, 0.1, 0.1, 1), "headerTextColor": (1, 1, 1, 0.85),
        "keyboardFocusIndicatorColor": (0.1, 0.47, 0.9, 0.5), "labelColor": (1, 1, 1, 0.85), "linkColor": (0.25, 0.56, 1, 1),
        "placeholderTextColor": (1, 1, 1, 0.25), "quaternaryLabelColor": (1, 1, 1, 0.1), "scrollBarColor": (0.5, 0.5, 0.5, 1),
        "secondaryLabelColor": (1, 1, 1, 0.55), "selectedContentBackgroundColor": (0, 0.345, 0.74, 1), "selectedControlColor": (0.24, 0.42, 0.62, 1),
        "selectedTextBackgroundColor": (0.24, 0.42, 0.62, 1), "selectedTextColor": (1, 1, 1, 1), "separatorColor": (1, 1, 1, 0.1),
        "tertiaryLabelColor": (1, 1, 1, 0.25), "textBackgroundColor": (0.118, 0.118, 0.118, 0.92), "textColor": (1, 1, 1, 1),
        "underPageBackgroundColor": (0.16, 0.16, 0.16, 0.9), "unemphasizedSelectedContentBackgroundColor": (0.27, 0.27, 0.27, 1),
        "windowBackgroundColor": (0.196, 0.196, 0.196, 1), "windowFrameTextColor": (1, 1, 1, 0.85),
        // Probed on macOS 15 (ADR-0038).
        "controlAlternatingRowColor0": (0.1176, 0.1176, 0.1176, 1), "controlAlternatingRowColor1": (1, 1, 1, 0.0471),
        "systemFillColor": (1, 1, 1, 0.098), "secondarySystemFillColor": (1, 1, 1, 0.0784), "tertiarySystemFillColor": (1, 1, 1, 0.0471),
        "quaternarySystemFillColor": (1, 1, 1, 0.0275), "quinarySystemFillColor": (1, 1, 1, 0.0078), "quinaryLabelColor": (1, 1, 1, 0.0471),
    ]
    internal let storage: Storage
    /// A pattern colour's image (`init(patternImage:)`).
    private var _pattern: NSImage? = nil
    /// A dynamic colour's provider and name (`init(name:dynamicProvider:)`, asset catalogs).
    private var _provider: ((NSAppearance) -> NSColor)? = nil
    private var _dynamicName: String? = nil
    /// The catalog of a colour from a colour list other than System (`init(catalogName:colorName:)`).
    private var _catalog: (list: String, name: String)? = nil
    /// HDR exposure (macOS 26): the factor over the standard-dynamic-range components.
    private var _linearExposure: CGFloat = 1

    private init(storage: Storage) {
        self.storage = storage
        super.init()
    }

    /// The colour's components as sRGB, a dynamic colour resolved under the current
    /// drawing appearance.
    internal var _rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
        if let p = _provider { return p(NSAppearance.current)._rgba }
        _requireComponents()
        return storage.rgba
    }

    /// Red, green, blue as the colour's own space has them (an RGB colour in Display P3
    /// reports its P3 components, as on macOS); sRGB otherwise.
    internal var _ownRGBA: (CGFloat, CGFloat, CGFloat, CGFloat) {
        if _provider == nil, case let .space(cs, comps, a) = storage, cs.colorSpaceModel == .rgb { return (comps[0], comps[1], comps[2], a) }
        return _rgba
    }

    /// The colour as (space, components without alpha, alpha), for colour-space conversion;
    /// a catalog or dynamic colour resolves to sRGB under the current appearance.
    internal var _spaceComponents: (NSColorSpace, [CGFloat], CGFloat)? {
        if _pattern != nil { return nil }
        if _provider == nil {
            switch storage {
            case let .space(cs, comps, a): return (cs, comps, a)
            case let .gray(w, a): return (.genericGamma22Gray, [w], a)
            case let .cmyk(c, m, y, k, a): return (.deviceCMYK, [c, m, y, k], a)
            case let .rgb(r, g, b, a): return (.sRGB, [r, g, b], a)
            case .named, .namedAlpha: break
            }
        }
        let (r, g, b, a) = _rgba
        return (.sRGB, [r, g, b], a)
    }

    /// A component colour in `space`, stored in the plain cases when the space is theirs.
    internal static func _make(_ space: NSColorSpace, _ comps: [CGFloat], _ alpha: CGFloat) -> NSColor {
        if space === NSColorSpace.sRGB { return NSColor(storage: .rgb(comps[0], comps[1], comps[2], alpha)) }
        if space === NSColorSpace.genericGamma22Gray { return NSColor(storage: .gray(comps[0], alpha)) }
        if space === NSColorSpace.deviceCMYK { return NSColor(storage: .cmyk(comps[0], comps[1], comps[2], comps[3], alpha)) }
        return NSColor(storage: .space(space, comps, alpha))
    }

    /// AppKit raises when components are read from a pattern colour ("need to first
    /// convert colorspace"); the port stops the same way.
    private func _requireComponents(_ member: String = #function) {
        precondition(_pattern == nil, "-\(member) not valid for the NSColor Pattern color; need to first convert colorspace.")
    }
    private func _requireCMYK(_ member: String = #function) -> (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) {
        guard _provider == nil, case let .cmyk(c, m, y, k, a) = storage else {
            preconditionFailure("-\(member) not valid for the NSColor \(description); need to first convert colorspace.")
        }
        return (c, m, y, k, a)
    }
    private var _isCatalog: Bool {
        if _provider != nil || _catalog != nil { return true }
        switch storage { case .named, .namedAlpha: return true; default: return false }
    }
    private var _namedComponent: String? {
        if let n = _dynamicName { return n }
        if let c = _catalog { return c.name }
        switch storage { case let .named(n, _, _, _, _), let .namedAlpha(n, _, _, _, _): return n; default: return nil }
    }

    /// The system colours by catalog name, for `init(catalogName:colorName:)` with "System".
    private static let _systemColors: [String: () -> NSColor] = {
        var table: [String: () -> NSColor] = [:]
        for (name, make) in _systemColorList { table[name] = make }
        return table
    }()

    private static func named(_ name: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(storage: .named(name, r, g, b, a))
    }

    private static func hsbToRGB(_ h: CGFloat, _ s: CGFloat, _ v: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        if s <= 0 { return (v, v, v) }
        let hh = (h - h.rounded(.down)) * 6
        let i = Int(hh.rounded(.down))
        let f = hh - CGFloat(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    private var hsb: (CGFloat, CGFloat, CGFloat) {
        let (r, g, b, _) = _ownRGBA
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var h: CGFloat = 0
        if delta > 0 {
            if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = maxC == 0 ? 0 : delta / maxC
        return (h, s, maxC)
    }

    open override var description: String {
        if let image = _pattern { return "NSColor Pattern color: \(image)" }
        if _provider != nil { return "Catalog color: #$customDynamic \(_dynamicName ?? "")" }
        if let c = _catalog { return "Catalog color: \(c.list) \(c.name)" }
        switch storage {
        case let .rgb(r, g, b, a): return "sRGB IEC61966-2.1 colorspace \(r) \(g) \(b) \(a)"
        case let .gray(w, a): return "Generic Gray Gamma 2.2 Profile colorspace \(w) \(a)"
        case let .named(n, _, _, _, _): return "Catalog color: System \(n)"
        case let .namedAlpha(n, _, _, _, a): return "Catalog color: System \(n) alpha \(a)"
        case let .cmyk(c, m, y, k, a): return "NSDeviceCMYKColorSpace \(c) \(m) \(y) \(k) \(a)"
        case let .space(cs, comps, a): return "\(cs.localizedName ?? "Custom") colorspace \((comps + [a]).map { "\($0)" }.joined(separator: " "))"
        }
    }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSColor else { return false }
        if _pattern != nil || other._pattern != nil { return _pattern === other._pattern }
        return other._rgba == _rgba
    }
    open override var hash: Int {
        if let image = _pattern { return ObjectIdentifier(image).hashValue }
        let (r, g, b, a) = _rgba
        var h = Hasher()
        h.combine(r); h.combine(g); h.combine(b); h.combine(a)
        return h.finalize()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init()
    public override init() {
        storage = .rgb(0, 0, 0, 1)
        super.init()
    }
    // SKIPPED (unknown module (CoreImage CIColor)): init(CIColor color: CIColor)
    // SKIPPED (unknown module (CoreImage CIColor)): init(CIColor color: CIColor)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(calibratedhue:saturation:brightness:alpha:)
    public init(calibratedHue hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let (r, g, b) = NSColor.hsbToRGB(hue, saturation, brightness)
        storage = .rgb(r, g, b, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(calibratedred:green:blue:alpha:)
    public init(calibratedRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        storage = .rgb(red, green, blue, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(calibratedwhite:alpha:)
    public init(calibratedWhite white: CGFloat, alpha: CGFloat) {
        storage = .gray(white, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(catalogname:colorname:)
    /// "System" names the system colours (`labelColor`, `controlAccentColor`, …); other
    /// catalogs are the available colour lists (NSColorList, ADR-0031).
    public convenience init?(catalogName listName: NSColorList.Name, colorName: NSColor.Name) {
        if listName == "System" {
            guard let make = NSColor._systemColors[colorName] else { return nil }
            self.init(storage: make().storage)
            return
        }
        guard let list = NSColorList(named: listName), let color = list.color(withKey: colorName) else { return nil }
        self.init(storage: color.storage)
        _catalog = (listName, colorName)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(cgcolor:)
    public convenience init?(cgColor: CGColor) {
        #if os(Windows) || os(Linux)
        let (r, g, b, a) = cgColor.rgba
        #else
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let comps = (cgColor.converted(to: space, intent: .defaultIntent, options: nil) ?? cgColor).components ?? [0, 0, 0, 1]
        let (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = comps.count >= 4 ? (comps[0], comps[1], comps[2], comps[3]) : comps.count == 2 ? (comps[0], comps[0], comps[0], comps[1]) : (0, 0, 0, 1)
        #endif
        self.init(red: r, green: g, blue: b, alpha: a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(coder:)
    public required init?(coder: NSCoder) {
        storage = .rgb(0, 0, 0, 1)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(colorspace:components:count:)
    /// `count` is the space's components plus alpha (last).
    public convenience init(colorSpace space: NSColorSpace, components: UnsafePointer<CGFloat>, count numberOfComponents: Int) {
        let n = space.numberOfColorComponents
        precondition(numberOfComponents == n + 1, "NSColor.init(colorSpace:components:count:): \(space.localizedName ?? "the space") takes \(n) components and alpha")
        let comps = (0..<n).map { components[$0] }
        guard [.rgb, .gray, .cmyk].contains(space.colorSpaceModel) else {
            unimplemented("NSColor.init(colorSpace:components:count:) — \(space.colorSpaceModel) spaces have no conversion in NSColorSpace (RGB, gray and CMYK only)")
        }
        self.init(storage: NSColor._make(space, comps, components[n]).storage)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(colorspace:hue:saturation:brightness:alpha:)
    @available(macOS 10.12, *)
    /// HSB in an RGB-model space (macOS raises for others).
    public convenience init(colorSpace space: NSColorSpace, hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        precondition(space.colorSpaceModel == .rgb, "NSColor.init(colorSpace:hue:saturation:brightness:alpha:) needs an RGB colour space")
        let (r, g, b) = NSColor.hsbToRGB(hue, saturation, brightness)
        self.init(storage: NSColor._make(space, [r, g, b], alpha).storage)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(devicecyan:magenta:yellow:black:alpha:)
    public init(deviceCyan cyan: CGFloat, magenta: CGFloat, yellow: CGFloat, black: CGFloat, alpha: CGFloat) {
        storage = .cmyk(cyan, magenta, yellow, black, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(devicehue:saturation:brightness:alpha:)
    public init(deviceHue hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let (r, g, b) = NSColor.hsbToRGB(hue, saturation, brightness)
        storage = .rgb(r, g, b, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(devicered:green:blue:alpha:)
    public init(deviceRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        storage = .rgb(red, green, blue, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(devicewhite:alpha:)
    public init(deviceWhite white: CGFloat, alpha: CGFloat) {
        storage = .gray(white, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(displayp3red:green:blue:alpha:)
    @available(macOS 10.12, *)
    public init(displayP3Red red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        storage = .space(.displayP3, [red, green, blue], alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(for:)
    /// The tint's catalog colour (macOS 15 values; the default tint is blue).
    public convenience init(for controlTint: NSControlTint) {
        switch controlTint {
        case .graphiteControlTint: self.init(storage: .named("graphiteControlTintColor", 0.7294, 0.7569, 0.8, 1))
        case .clearControlTint: self.init(storage: .named("clearControlTintColor", 0.8196, 0.8196, 0.8196, 1))
        default: self.init(storage: .named("blueControlTintColor", 0.6078, 0.7569, 0.9098, 1))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(from:)
    public convenience init?(from pasteBoard: NSPasteboard) {
        guard let plist = pasteBoard.propertyList(forType: .color) else { return nil }
        self.init(pasteboardPropertyList: plist, ofType: .color)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(genericgamma22white:alpha:)
    public init(genericGamma22White white: CGFloat, alpha: CGFloat) {
        storage = .gray(white, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(hue:saturation:brightness:alpha:)
    public init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let (r, g, b) = NSColor.hsbToRGB(hue, saturation, brightness)
        storage = .rgb(r, g, b, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(name:dynamicprovider:)
    @available(macOS 10.15, *)
    /// Resolved under the current drawing appearance whenever its components are read or
    /// it is set in a context (as the views draw under their effective appearance).
    public init(name colorName: NSColor.Name?, dynamicProvider: @escaping (NSAppearance) -> NSColor) {
        storage = .rgb(0, 0, 0, 1)
        super.init()
        _provider = dynamicProvider
        _dynamicName = colorName
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(named:)
    @available(macOS 10.13, *)
    /// A colour set from the main bundle's asset catalogs (see `init(named:bundle:)`).
    public convenience init?(named name: NSColor.Name) { self.init(named: name, bundle: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(named:bundle:)
    @available(macOS 10.13, *)
    /// A `<name>.colorset` in an asset catalog (`*.xcassets`) the bundle (main if nil) carries
    /// as resources. The port reads the uncompiled catalog's Contents.json (there is no
    /// actool): the universal colour, plus its dark-appearance variant as a dynamic colour.
    public convenience init?(named name: NSColor.Name, bundle: Bundle?) {
        guard let set = _NSColorAssetCatalog.colorSet(named: name, in: bundle ?? .main) else { return nil }
        let light = set.light, dark = set.dark
        if let dark {
            self.init(name: name) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
        } else {
            self.init(storage: light.storage)
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(patternimage:)
    /// A pattern colour. Its image tiles `drawSwatch(in:)`; filling paths with it needs
    /// CGPattern, which the port's CoreGraphics lacks, so `set()`/`setFill()`/`cgColor` stop
    /// with that reason (ADR-0038).
    public init(patternImage image: NSImage) {
        storage = .rgb(0, 0, 0, 1)
        super.init()
        _pattern = image
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(red:green:blue:alpha:)
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        storage = .rgb(red, green, blue, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(red:green:blue:alpha:exposure:)
    @available(macOS 26.0, *)
    /// Stored: the components are the standard-dynamic-range colour, `linearExposure` is 2^exposure.
    public convenience init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, exposure: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha, linearExposure: pow(2, exposure))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(red:green:blue:alpha:linearexposure:)
    @available(macOS 26.0, *)
    /// Stored: the components are the standard-dynamic-range colour and `linearExposure` its
    /// brightness factor (at least 1). The port's surfaces draw the SDR colour.
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, linearExposure: CGFloat) {
        storage = .rgb(red, green, blue, alpha)
        super.init()
        _linearExposure = max(1, linearExposure)
    }
    // SKIPPED (DeveloperToolsSupport.ColorResource): convenience init(resource: ColorResource)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(srgbred:green:blue:alpha:)
    public init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        storage = .rgb(red, green, blue, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(white:alpha:)
    public init(white: CGFloat, alpha: CGFloat) {
        storage = .gray(white, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/alphacomponent
    open var alphaComponent: CGFloat { _rgba.3 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/alternateselectedcontrolcolor
    class public var alternateSelectedControlColor: NSColor { named("alternateSelectedControlColor", 0, 0.388, 0.843, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/alternateselectedcontroltextcolor
    class public var alternateSelectedControlTextColor: NSColor { named("alternateSelectedControlTextColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/alternatingcontentbackgroundcolors
    @available(macOS 10.14, *)
    class public var alternatingContentBackgroundColors: [NSColor] { [named("alternatingContentBackgroundColors0", 1, 1, 1), named("alternatingContentBackgroundColors1", 0.96, 0.96, 0.96)] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/applyingcontentheadroom(_:)
    @available(macOS 26.0, *)
    /// The colour with its exposure limited to `contentHeadroom` (at least 1).
    open func applyingContentHeadroom(_ contentHeadroom: CGFloat) -> NSColor {
        let c = NSColor(storage: storage)
        c._linearExposure = min(_linearExposure, max(1, contentHeadroom))
        return c
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/black
    class public var black: NSColor { NSColor(storage: .rgb(0, 0, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/blackcomponent
    /// CMYK colours only (macOS raises for others; convert with `usingColorSpaceName(.deviceCMYK)`).
    open var blackComponent: CGFloat { _requireCMYK().3 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/blended(withfraction:of:)
    open func blended(withFraction fraction: CGFloat, of color: NSColor) -> NSColor? {
        let f = min(max(fraction, 0), 1)
        let (r1, g1, b1, a1) = _rgba
        let (r2, g2, b2, a2) = color._rgba
        return NSColor(storage: .rgb(r1 + (r2 - r1) * f, g1 + (g2 - g1) * f, b1 + (b2 - b1) * f, a1 + (a2 - a1) * f))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/blue
    class public var blue: NSColor { NSColor(storage: .rgb(0, 0, 1, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/bluecomponent
    open var blueComponent: CGFloat { _ownRGBA.2 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/brightnesscomponent
    open var brightnessComponent: CGFloat { hsb.2 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/brown
    class public var brown: NSColor { NSColor(storage: .rgb(0.6, 0.4, 0.2, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/catalognamecomponent
    /// "System" for the system colours; catalog colours only (macOS raises for others).
    open var catalogNameComponent: NSColorList.Name {
        precondition(_isCatalog, "-catalogNameComponent not valid for the NSColor \(description); need to first convert colorspace.")
        if _provider != nil { return "#$customDynamic" }
        return _catalog?.list ?? "System"
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/cgcolor
    open var cgColor: CGColor {
        if _pattern != nil { unimplemented("NSColor.cgColor of a pattern colour — the port's CoreGraphics has no CGPattern") }
        let (r, g, b, a) = _rgba
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/clear
    class public var clear: NSColor { NSColor(storage: .rgb(0, 0, 0, 0)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/colornamecomponent
    /// Catalog colours only (macOS raises for others).
    open var colorNameComponent: NSColor.Name {
        guard let n = _namedComponent else { preconditionFailure("-colorNameComponent not valid for the NSColor \(description); need to first convert colorspace.") }
        return NSColor.Name(n)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/colorspace
    /// Component colours only (macOS raises for catalog and pattern colours). The port's
    /// device and calibrated RGB colours are sRGB, its white colours Generic Gray Gamma 2.2.
    open var colorSpace: NSColorSpace {
        precondition(!_isCatalog && _pattern == nil, "-colorSpace not valid for the NSColor \(description); need to first convert colorspace.")
        return _spaceComponents!.0
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/colorspacename
    open var colorSpaceName: NSColorSpaceName {
        if _pattern != nil { return .pattern }
        if _isCatalog { return .named }
        switch storage { case .gray: return .calibratedWhite; case .cmyk: return .deviceCMYK; case .space: return .custom; default: return .calibratedRGB }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlaccentcolor
    @available(macOS 10.14, *)
    class public var controlAccentColor: NSColor { named("controlAccentColor", 0, 0.478, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlalternatingrowbackgroundcolors
    /// macOS 15 values: white and (0.957, 0.961, 0.961); dark, (0.118) and white at 4.7 %.
    class public var controlAlternatingRowBackgroundColors: [NSColor] { [named("controlAlternatingRowColor0", 1, 1, 1), named("controlAlternatingRowColor1", 0.9569, 0.9608, 0.9608)] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlbackgroundcolor
    class public var controlBackgroundColor: NSColor { named("controlBackgroundColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlcolor
    class public var controlColor: NSColor { named("controlColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controldarkshadowcolor
    class public var controlDarkShadowColor: NSColor { named("controlDarkShadowColor", 0, 0, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlhighlightcolor
    class public var controlHighlightColor: NSColor { named("controlHighlightColor", 0.9, 0.9, 0.9, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controllighthighlightcolor
    class public var controlLightHighlightColor: NSColor { named("controlLightHighlightColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlshadowcolor
    class public var controlShadowColor: NSColor { named("controlShadowColor", 0, 0, 0, 0.2) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controltextcolor
    class public var controlTextColor: NSColor { named("controlTextColor", 0, 0, 0, 0.85) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/currentcontroltint
    class public var currentControlTint: NSControlTint { NSControlTint(rawValue: 1)! }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/currentcontroltintdidchangenotification
    static public var currentControlTintDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSControlTintDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/cyan
    class public var cyan: NSColor { NSColor(storage: .rgb(0, 1, 1, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/cyancomponent
    /// CMYK colours only.
    open var cyanComponent: CGFloat { _requireCMYK().0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/darkgray
    class public var darkGray: NSColor { NSColor(storage: .rgb(0.3333333333333333, 0.3333333333333333, 0.3333333333333333, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/disabledcontroltextcolor
    class public var disabledControlTextColor: NSColor { named("disabledControlTextColor", 0, 0, 0, 0.25) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/drawswatch(in:)
    /// A pattern colour tiles its image from the rect's origin.
    open func drawSwatch(in rect: NSRect) {
        guard let image = _pattern else { setFill(); NSBezierPath.fill(rect); return }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                image.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
                x += size.width
            }
            y += size.height
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/findhighlightcolor
    @available(macOS 10.13, *)
    class public var findHighlightColor: NSColor { named("findHighlightColor", 1, 1, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/getcomponents(_:)
    open func getComponents(_ components: UnsafeMutablePointer<CGFloat>) {
        _requireComponents()
        if case let .gray(w, a) = storage { components[0] = w; components[1] = a; return }
        if case let .cmyk(c, m, y, k, a) = storage { components[0] = c; components[1] = m; components[2] = y; components[3] = k; components[4] = a; return }
        if case let .space(_, comps, a) = storage { for (i, c) in comps.enumerated() { components[i] = c }; components[comps.count] = a; return }
        let (r, g, b, a) = _rgba
        components[0] = r; components[1] = g; components[2] = b; components[3] = a
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/getcyan(_:magenta:yellow:black:alpha:)
    /// CMYK colours only.
    open func getCyan(_ cyan: UnsafeMutablePointer<CGFloat>?, magenta: UnsafeMutablePointer<CGFloat>?, yellow: UnsafeMutablePointer<CGFloat>?, black: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        let (c, m, y, k, a) = _requireCMYK()
        cyan?.pointee = c; magenta?.pointee = m; yellow?.pointee = y; black?.pointee = k; alpha?.pointee = a
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/gethue(_:saturation:brightness:alpha:)
    open func getHue(_ hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?, brightness: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        let (h, s, b) = hsb
        hue?.pointee = h; saturation?.pointee = s; brightness?.pointee = b; alpha?.pointee = alphaComponent
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/getred(_:green:blue:alpha:)
    open func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        let (r, g, b, a) = _ownRGBA
        red?.pointee = r; green?.pointee = g; blue?.pointee = b; alpha?.pointee = a
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/getwhite(_:alpha:)
    open func getWhite(_ white: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        white?.pointee = whiteComponent; alpha?.pointee = alphaComponent
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/gray
    class public var gray: NSColor { NSColor(storage: .rgb(0.5, 0.5, 0.5, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/green
    class public var green: NSColor { NSColor(storage: .rgb(0, 1, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/greencomponent
    open var greenComponent: CGFloat { _ownRGBA.1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/gridcolor
    class public var gridColor: NSColor { named("gridColor", 0.898, 0.898, 0.898, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/headercolor
    class public var headerColor: NSColor { named("headerColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/headertextcolor
    class public var headerTextColor: NSColor { named("headerTextColor", 0, 0, 0, 0.85) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/highlight(withlevel:)
    open func highlight(withLevel val: CGFloat) -> NSColor? { blended(withFraction: val, of: .white) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/highlightcolor
    class public var highlightColor: NSColor { named("highlightColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/huecomponent
    open var hueComponent: CGFloat { hsb.0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/ignoresalpha
    /// Stored (default false). The port's colour panel and wells always show opacity.
    @MainActor class public var ignoresAlpha: Bool {
        get { _ignoresAlpha }
        set { _ignoresAlpha = newValue }
    }
    @MainActor private static var _ignoresAlpha = false
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/keyboardfocusindicatorcolor
    class public var keyboardFocusIndicatorColor: NSColor { named("keyboardFocusIndicatorColor", 0, 0.388, 0.843, 0.5) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/knobcolor
    class public var knobColor: NSColor { named("knobColor", 0.6, 0.6, 0.6, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/labelcolor
    @available(macOS 10.10, *)
    class public var labelColor: NSColor { named("labelColor", 0, 0, 0, 0.85) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/lightgray
    class public var lightGray: NSColor { NSColor(storage: .rgb(0.6666666666666666, 0.6666666666666666, 0.6666666666666666, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/linearexposure
    @available(macOS 26.0, *)
    open var linearExposure: CGFloat { _linearExposure }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/linkcolor
    @available(macOS 10.10, *)
    class public var linkColor: NSColor { named("linkColor", 0, 0.41, 0.85, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/localizedcatalognamecomponent
    /// macOS shows the System catalog as "Developer".
    open var localizedCatalogNameComponent: String { catalogNameComponent == "System" ? "Developer" : catalogNameComponent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/localizedcolornamecomponent
    open var localizedColorNameComponent: String { colorNameComponent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/magenta
    class public var magenta: NSColor { NSColor(storage: .rgb(1, 0, 1, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/magentacomponent
    open var magentaComponent: CGFloat { _requireCMYK().1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/numberofcomponents
    open var numberOfComponents: Int {
        _requireComponents()
        switch storage { case .gray: return 2; case .cmyk: return 5; case let .space(cs, _, _): return cs.numberOfColorComponents + 1; default: return 4 }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/orange
    class public var orange: NSColor { NSColor(storage: .rgb(1, 0.5, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/patternimage
    /// Pattern colours only (macOS raises for others).
    open var patternImage: NSImage {
        guard let image = _pattern else { preconditionFailure("-patternImage not valid for the NSColor \(description); need to first convert colorspace.") }
        return image
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/placeholdertextcolor
    @available(macOS 10.10, *)
    class public var placeholderTextColor: NSColor { named("placeholderTextColor", 0, 0, 0, 0.25) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/purple
    class public var purple: NSColor { NSColor(storage: .rgb(0.5, 0, 0.5, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/quaternarylabelcolor
    @available(macOS 10.10, *)
    class public var quaternaryLabelColor: NSColor { named("quaternaryLabelColor", 0, 0, 0, 0.1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/quaternarysystemfill
    @available(macOS 14.0, *)
    class public var quaternarySystemFill: NSColor { named("quaternarySystemFillColor", 0, 0, 0, 0.0275) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/quinarylabel
    @available(macOS 11.0, *)
    class public var quinaryLabel: NSColor { named("quinaryLabelColor", 0, 0, 0, 0.0471) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/quinarysystemfill
    @available(macOS 14.0, *)
    class public var quinarySystemFill: NSColor { named("quinarySystemFillColor", 0, 0, 0, 0.0078) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/red
    class public var red: NSColor { NSColor(storage: .rgb(1, 0, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/redcomponent
    open var redComponent: CGFloat { _ownRGBA.0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/saturationcomponent
    open var saturationComponent: CGFloat { hsb.1 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/scrollbarcolor
    class public var scrollBarColor: NSColor { named("scrollBarColor", 0.5, 0.5, 0.5, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/scrubbertexturedbackground
    @available(macOS 10.12, *)
    class public var scrubberTexturedBackground: NSColor { named("scrubberTexturedBackground", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/secondarylabelcolor
    @available(macOS 10.10, *)
    class public var secondaryLabelColor: NSColor { named("secondaryLabelColor", 0, 0, 0, 0.5) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/secondaryselectedcontrolcolor
    class public var secondarySelectedControlColor: NSColor { named("secondarySelectedControlColor", 0.863, 0.863, 0.863, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/secondarysystemfill
    @available(macOS 14.0, *)
    class public var secondarySystemFill: NSColor { named("secondarySystemFillColor", 0, 0, 0, 0.0784) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedcontentbackgroundcolor
    @available(macOS 10.14, *)
    class public var selectedContentBackgroundColor: NSColor { named("selectedContentBackgroundColor", 0, 0.388, 0.843, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedcontrolcolor
    class public var selectedControlColor: NSColor { named("selectedControlColor", 0.702, 0.839, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedcontroltextcolor
    class public var selectedControlTextColor: NSColor { named("selectedControlTextColor", 0, 0, 0, 0.85) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedknobcolor
    class public var selectedKnobColor: NSColor { named("selectedKnobColor", 0.4, 0.4, 0.4, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedmenuitemcolor
    class public var selectedMenuItemColor: NSColor { named("selectedMenuItemColor", 0, 0.388, 0.843, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedmenuitemtextcolor
    class public var selectedMenuItemTextColor: NSColor { named("selectedMenuItemTextColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedtextbackgroundcolor
    class public var selectedTextBackgroundColor: NSColor { named("selectedTextBackgroundColor", 0.702, 0.839, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/selectedtextcolor
    class public var selectedTextColor: NSColor { named("selectedTextColor", 0, 0, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/separatorcolor
    @available(macOS 10.14, *)
    class public var separatorColor: NSColor { named("separatorColor", 0, 0, 0, 0.1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/set()
    open func set() { setFill(); setStroke() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/setfill()
    open func setFill() { NSGraphicsContext.current?.cgContext.setFillColor(cgColor) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/setstroke()
    open func setStroke() { NSGraphicsContext.current?.cgContext.setStrokeColor(cgColor) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/shadow(withlevel:)
    open func shadow(withLevel val: CGFloat) -> NSColor? { blended(withFraction: val, of: .black) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/shadowcolor
    class public var shadowColor: NSColor { named("shadowColor", 0, 0, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/standarddynamicrange
    @available(macOS 26.0, *)
    open var standardDynamicRange: NSColor { _linearExposure == 1 ? self : NSColor(storage: storage) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemblue
    @available(macOS 10.10, *)
    class public var systemBlue: NSColor { named("systemBlue", 0, 0.478, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systembrown
    @available(macOS 10.10, *)
    class public var systemBrown: NSColor { named("systemBrown", 0.635, 0.518, 0.368, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemcolorsdidchangenotification
    static public var systemColorsDidChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSSystemColorsDidChangeNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemcyan
    @available(macOS 12.0, *)
    class public var systemCyan: NSColor { named("systemCyan", 0.333, 0.745, 0.898, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemfill
    @available(macOS 14.0, *)
    class public var systemFill: NSColor { named("systemFillColor", 0, 0, 0, 0.098) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemgray
    @available(macOS 10.10, *)
    class public var systemGray: NSColor { named("systemGray", 0.557, 0.557, 0.576, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemgreen
    @available(macOS 10.10, *)
    class public var systemGreen: NSColor { named("systemGreen", 0.204, 0.78, 0.349, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemindigo
    @available(macOS 10.15, *)
    class public var systemIndigo: NSColor { named("systemIndigo", 0.345, 0.337, 0.839, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemmint
    @available(macOS 10.12, *)
    class public var systemMint: NSColor { named("systemMint", 0, 0.78, 0.745, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemorange
    @available(macOS 10.10, *)
    class public var systemOrange: NSColor { named("systemOrange", 1, 0.584, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systempink
    @available(macOS 10.10, *)
    class public var systemPink: NSColor { named("systemPink", 1, 0.176, 0.333, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systempurple
    @available(macOS 10.10, *)
    class public var systemPurple: NSColor { named("systemPurple", 0.686, 0.322, 0.871, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemred
    @available(macOS 10.10, *)
    class public var systemRed: NSColor { named("systemRed", 1, 0.231, 0.188, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemteal
    @available(macOS 10.12, *)
    class public var systemTeal: NSColor { named("systemTeal", 0.353, 0.784, 0.98, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/systemyellow
    @available(macOS 10.10, *)
    class public var systemYellow: NSColor { named("systemYellow", 1, 0.8, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/tertiarylabelcolor
    @available(macOS 10.10, *)
    class public var tertiaryLabelColor: NSColor { named("tertiaryLabelColor", 0, 0, 0, 0.26) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/tertiarysystemfill
    @available(macOS 14.0, *)
    class public var tertiarySystemFill: NSColor { named("tertiarySystemFillColor", 0, 0, 0, 0.0471) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/textbackgroundcolor
    class public var textBackgroundColor: NSColor { named("textBackgroundColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/textcolor
    class public var textColor: NSColor { named("textColor", 0, 0, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/textinsertionpointcolor
    @available(macOS 14.0, *)
    class public var textInsertionPointColor: NSColor { named("textInsertionPointColor", 0, 0, 0, 1) }
    // SKIPPED (CoreTransferable.TransferRepresentation): static var transferRepresentation: some TransferRepresentation { get }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/type
    @available(macOS 10.13, *)
    open var type: NSColor.ColorType { _pattern != nil ? .pattern : _isCatalog ? .catalog : .componentBased }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/underpagebackgroundcolor
    class public var underPageBackgroundColor: NSColor { named("underPageBackgroundColor", 0.588, 0.588, 0.588, 0.9) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/unemphasizedselectedcontentbackgroundcolor
    @available(macOS 10.14, *)
    class public var unemphasizedSelectedContentBackgroundColor: NSColor { named("unemphasizedSelectedContentBackgroundColor", 0.863, 0.863, 0.863, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/unemphasizedselectedtextbackgroundcolor
    @available(macOS 10.14, *)
    class public var unemphasizedSelectedTextBackgroundColor: NSColor { named("unemphasizedSelectedTextBackgroundColor", 0.863, 0.863, 0.863, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/unemphasizedselectedtextcolor
    @available(macOS 10.14, *)
    class public var unemphasizedSelectedTextColor: NSColor { named("unemphasizedSelectedTextColor", 0, 0, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/usingcolorspace(_:)
    /// The colour in `space`, through NSColorSpace's D50 conversion (CMYK naively through
    /// device RGB); catalog and dynamic colours resolve under the current appearance first.
    /// Nil for a pattern colour or a space NSColorSpace does not convert (Lab, indexed).
    open func usingColorSpace(_ space: NSColorSpace) -> NSColor? {
        guard let (src, comps, a) = _spaceComponents else { return nil }
        if src === space || (src.isEqual(space) && !_isCatalog) { return _isCatalog ? NSColor._make(space, comps, a) : self }
        guard let out = src._convert(comps, to: space) else { return nil }
        return NSColor._make(space, out, a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/usingcolorspacename(_:)
    /// Converts between the component spaces: RGB (device or calibrated), white and device
    /// CMYK. CMYK goes through the naive device formulas (macOS uses ColorSync profiles, so
    /// its numbers differ); catalog and dynamic colours resolve under the current
    /// appearance first. A pattern colour converts only to the pattern space.
    open func usingColorSpaceName(_ name: NSColorSpaceName) -> NSColor? {
        if name == colorSpaceName { return self }
        if _pattern != nil { return nil }
        switch name {
        case .calibratedRGB, .deviceRGB:
            let (r, g, b, a) = _rgba
            return NSColor(storage: .rgb(r, g, b, a))
        case .calibratedWhite, .deviceWhite:
            return NSColor(storage: .gray(whiteComponent, alphaComponent))
        case .deviceCMYK:
            if _provider == nil, case let .gray(w, a) = storage { return NSColor(storage: .cmyk(0, 0, 0, 1 - w, a)) }
            let (r, g, b, a) = _rgba
            let k = 1 - max(r, g, b)
            guard k < 1 else { return NSColor(storage: .cmyk(0, 0, 0, 1, a)) }
            return NSColor(storage: .cmyk((1 - r - k) / (1 - k), (1 - g - k) / (1 - k), (1 - b - k) / (1 - k), k, a))
        default:
            return nil
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/usingcolorspacename(_:device:)
    open func usingColorSpaceName(_ name: NSColorSpaceName?, device deviceDescription: [NSDeviceDescriptionKey : Any]?) -> NSColor? { name.map { usingColorSpaceName($0) } ?? self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/usingtype(_:)
    @available(macOS 10.13, *)
    open func usingType(_ type: NSColor.ColorType) -> NSColor? {
        if type == self.type { return self }
        guard type == .componentBased, _pattern == nil else { return nil }
        let (r, g, b, a) = _rgba
        return NSColor(storage: .rgb(r, g, b, a))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/white
    class public var white: NSColor { NSColor(storage: .rgb(1, 1, 1, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/whitecomponent
    open var whiteComponent: CGFloat {
        if _provider == nil, case let .gray(w, _) = storage { return w }
        let (r, g, b, _) = _rgba
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/windowbackgroundcolor
    class public var windowBackgroundColor: NSColor { named("windowBackgroundColor", 0.925, 0.925, 0.925, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/windowframecolor
    class public var windowFrameColor: NSColor { named("windowFrameColor", 0.667, 0.667, 0.667, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/windowframetextcolor
    class public var windowFrameTextColor: NSColor { named("windowFrameTextColor", 0, 0, 0, 0.85) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/withalphacomponent(_:)
    open func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        if let p = _provider {
            let c = NSColor(storage: storage)
            c._provider = { p($0).withAlphaComponent(alpha) }
            c._dynamicName = _dynamicName
            return c
        }
        _requireComponents()
        switch storage {
        case let .rgb(r, g, b, _): return NSColor(storage: .rgb(r, g, b, alpha))
        case let .gray(w, _): return NSColor(storage: .gray(w, alpha))
        case let .named(n, r, g, b, _), let .namedAlpha(n, r, g, b, _): return NSColor(storage: .namedAlpha(n, r, g, b, alpha))
        case let .cmyk(c, m, y, k, _): return NSColor(storage: .cmyk(c, m, y, k, alpha))
        case let .space(cs, comps, _): return NSColor(storage: .space(cs, comps, alpha))
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/withsystemeffect(_:)
    @available(macOS 10.14, *)
    open func withSystemEffect(_ systemEffect: NSColor.SystemEffect) -> NSColor {
        switch systemEffect {
        case .pressed: return blended(withFraction: 0.2, of: .black) ?? self
        case .deepPressed: return blended(withFraction: 0.35, of: .black) ?? self
        case .disabled: return withAlphaComponent(alphaComponent * 0.5)
        case .rollover: return blended(withFraction: 0.1, of: .white) ?? self
        default: return self
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/write(to:)
    open func write(to pasteBoard: NSPasteboard) {
        _ = pasteBoard.writeObjects([self])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/yellow
    class public var yellow: NSColor { NSColor(storage: .rgb(1, 1, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/yellowcomponent
    open var yellowComponent: CGFloat { _requireCMYK().2 }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // MARK: Pasteboard (`com.apple.cocoa.pasteboard.color`): the sRGB components as a property list.
    public static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [.color] }
    public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [.color] }
    public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .color else { return nil }
        let (r, g, b, a) = _rgba
        return ["red": Double(r), "green": Double(g), "blue": Double(b), "alpha": Double(a)] as [String: Any]
    }
    // Requirement of NSPasteboardReading
    public required convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        guard type == .color else { return nil }
        var dict: [String: Any] = [:]
        if let d = propertyList as? [String: Any] { dict = d }
        else if let d = propertyList as? NSDictionary { for (k, v) in d { if let s = (k as? String) ?? (k as? NSString).map({ $0 as String }) { dict[s] = v } } }
        else if let data = propertyList as? Data, let d = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] { dict = d }
        func number(_ v: Any?) -> CGFloat? {
            switch v { case let n as NSNumber: return CGFloat(n.doubleValue); case let d as Double: return CGFloat(d); case let f as CGFloat: return f; case let i as Int: return CGFloat(i); default: return nil }
        }
        guard let r = number(dict["red"]), let g = number(dict["green"]), let b = number(dict["blue"]) else { return nil }
        self.init(red: r, green: g, blue: b, alpha: number(dict["alpha"]) ?? 1)
    }
}

extension NSColor {
    /// The catalog name of each system colour property (the names the colours report).
    fileprivate static let _systemColorList: [(String, () -> NSColor)] = [
        ("alternateSelectedControlColor", { NSColor.alternateSelectedControlColor }),
        ("alternateSelectedControlTextColor", { NSColor.alternateSelectedControlTextColor }),
        ("controlAccentColor", { NSColor.controlAccentColor }),
        ("controlBackgroundColor", { NSColor.controlBackgroundColor }),
        ("controlColor", { NSColor.controlColor }),
        ("controlDarkShadowColor", { NSColor.controlDarkShadowColor }),
        ("controlHighlightColor", { NSColor.controlHighlightColor }),
        ("controlLightHighlightColor", { NSColor.controlLightHighlightColor }),
        ("controlShadowColor", { NSColor.controlShadowColor }),
        ("controlTextColor", { NSColor.controlTextColor }),
        ("disabledControlTextColor", { NSColor.disabledControlTextColor }),
        ("findHighlightColor", { NSColor.findHighlightColor }),
        ("gridColor", { NSColor.gridColor }),
        ("headerColor", { NSColor.headerColor }),
        ("headerTextColor", { NSColor.headerTextColor }),
        ("highlightColor", { NSColor.highlightColor }),
        ("keyboardFocusIndicatorColor", { NSColor.keyboardFocusIndicatorColor }),
        ("knobColor", { NSColor.knobColor }),
        ("labelColor", { NSColor.labelColor }),
        ("linkColor", { NSColor.linkColor }),
        ("placeholderTextColor", { NSColor.placeholderTextColor }),
        ("quaternaryLabelColor", { NSColor.quaternaryLabelColor }),
        ("quaternarySystemFillColor", { NSColor.quaternarySystemFill }),
        ("quinaryLabelColor", { NSColor.quinaryLabel }),
        ("quinarySystemFillColor", { NSColor.quinarySystemFill }),
        ("scrollBarColor", { NSColor.scrollBarColor }),
        ("scrubberTexturedBackground", { NSColor.scrubberTexturedBackground }),
        ("secondaryLabelColor", { NSColor.secondaryLabelColor }),
        ("secondarySelectedControlColor", { NSColor.secondarySelectedControlColor }),
        ("secondarySystemFillColor", { NSColor.secondarySystemFill }),
        ("selectedContentBackgroundColor", { NSColor.selectedContentBackgroundColor }),
        ("selectedControlColor", { NSColor.selectedControlColor }),
        ("selectedControlTextColor", { NSColor.selectedControlTextColor }),
        ("selectedKnobColor", { NSColor.selectedKnobColor }),
        ("selectedMenuItemColor", { NSColor.selectedMenuItemColor }),
        ("selectedMenuItemTextColor", { NSColor.selectedMenuItemTextColor }),
        ("selectedTextBackgroundColor", { NSColor.selectedTextBackgroundColor }),
        ("selectedTextColor", { NSColor.selectedTextColor }),
        ("separatorColor", { NSColor.separatorColor }),
        ("shadowColor", { NSColor.shadowColor }),
        ("systemBlue", { NSColor.systemBlue }),
        ("systemBrown", { NSColor.systemBrown }),
        ("systemCyan", { NSColor.systemCyan }),
        ("systemFillColor", { NSColor.systemFill }),
        ("systemGray", { NSColor.systemGray }),
        ("systemGreen", { NSColor.systemGreen }),
        ("systemIndigo", { NSColor.systemIndigo }),
        ("systemMint", { NSColor.systemMint }),
        ("systemOrange", { NSColor.systemOrange }),
        ("systemPink", { NSColor.systemPink }),
        ("systemPurple", { NSColor.systemPurple }),
        ("systemRed", { NSColor.systemRed }),
        ("systemTeal", { NSColor.systemTeal }),
        ("systemYellow", { NSColor.systemYellow }),
        ("tertiaryLabelColor", { NSColor.tertiaryLabelColor }),
        ("tertiarySystemFillColor", { NSColor.tertiarySystemFill }),
        ("textBackgroundColor", { NSColor.textBackgroundColor }),
        ("textColor", { NSColor.textColor }),
        ("textInsertionPointColor", { NSColor.textInsertionPointColor }),
        ("underPageBackgroundColor", { NSColor.underPageBackgroundColor }),
        ("unemphasizedSelectedContentBackgroundColor", { NSColor.unemphasizedSelectedContentBackgroundColor }),
        ("unemphasizedSelectedTextBackgroundColor", { NSColor.unemphasizedSelectedTextBackgroundColor }),
        ("unemphasizedSelectedTextColor", { NSColor.unemphasizedSelectedTextColor }),
        ("windowBackgroundColor", { NSColor.windowBackgroundColor }),
        ("windowFrameColor", { NSColor.windowFrameColor }),
        ("windowFrameTextColor", { NSColor.windowFrameTextColor }),
    ]
}
