// NSColor (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor
/// `@unchecked Sendable` as Apple's (`NS_SWIFT_SENDABLE`): a colour is immutable once made.
open class NSColor: NSObject, NSAccessibilityColor, NSCopying, NSSecureCoding, NSCoding, NSPasteboardReading, NSPasteboardWriting, @unchecked Sendable {
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

        var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
            switch self {
            case let .rgb(r, g, b, a): return (r, g, b, a)
            case let .gray(w, a): return (w, w, w, a)
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
    ]
    internal let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
        super.init()
    }

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
        let (r, g, b, _) = storage.rgba
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
        switch storage {
        case let .rgb(r, g, b, a): return "sRGB IEC61966-2.1 colorspace \(r) \(g) \(b) \(a)"
        case let .gray(w, a): return "Generic Gray Gamma 2.2 Profile colorspace \(w) \(a)"
        case let .named(n, _, _, _, _): return "Catalog color: System \(n)"
        case let .namedAlpha(n, _, _, _, a): return "Catalog color: System \(n) alpha \(a)"
        }
    }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSColor else { return false }
        return other.storage.rgba == storage.rgba
    }
    open override var hash: Int {
        let (r, g, b, a) = storage.rgba
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
    public init?(catalogName listName: NSColorList.Name, colorName: NSColor.Name) { unimplemented() }
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
    public init(colorSpace space: NSColorSpace, components: UnsafePointer<CGFloat>, count numberOfComponents: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(colorspace:hue:saturation:brightness:alpha:)
    @available(macOS 10.12, *)
    public init(colorSpace space: NSColorSpace, hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(devicecyan:magenta:yellow:black:alpha:)
    public init(deviceCyan cyan: CGFloat, magenta: CGFloat, yellow: CGFloat, black: CGFloat, alpha: CGFloat) { unimplemented() }
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
        storage = .rgb(red, green, blue, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(for:)
    public init(for controlTint: NSControlTint) { unimplemented() }
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
    public init(name colorName: NSColor.Name?, dynamicProvider: @escaping (NSAppearance) -> NSColor) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(named:)
    @available(macOS 10.13, *)
    public init?(named name: NSColor.Name) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(named:bundle:)
    @available(macOS 10.13, *)
    public init?(named name: NSColor.Name, bundle: Bundle?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(patternimage:)
    public init(patternImage image: NSImage) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(red:green:blue:alpha:)
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        storage = .rgb(red, green, blue, alpha)
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(red:green:blue:alpha:exposure:)
    @available(macOS 26.0, *)
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, exposure: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/init(red:green:blue:alpha:linearexposure:)
    @available(macOS 26.0, *)
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, linearExposure: CGFloat) { unimplemented() }
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
    open var alphaComponent: CGFloat { storage.rgba.3 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/alternateselectedcontrolcolor
    class public var alternateSelectedControlColor: NSColor { named("alternateSelectedControlColor", 0, 0.388, 0.843, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/alternateselectedcontroltextcolor
    class public var alternateSelectedControlTextColor: NSColor { named("alternateSelectedControlTextColor", 1, 1, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/alternatingcontentbackgroundcolors
    @available(macOS 10.14, *)
    class public var alternatingContentBackgroundColors: [NSColor] { [named("alternatingContentBackgroundColors0", 1, 1, 1), named("alternatingContentBackgroundColors1", 0.96, 0.96, 0.96)] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/applyingcontentheadroom(_:)
    @available(macOS 26.0, *)
    open func applyingContentHeadroom(_ contentHeadroom: CGFloat) -> NSColor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/black
    class public var black: NSColor { NSColor(storage: .rgb(0, 0, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/blackcomponent
    open var blackComponent: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/blended(withfraction:of:)
    open func blended(withFraction fraction: CGFloat, of color: NSColor) -> NSColor? {
        let f = min(max(fraction, 0), 1)
        let (r1, g1, b1, a1) = storage.rgba
        let (r2, g2, b2, a2) = color.storage.rgba
        return NSColor(storage: .rgb(r1 + (r2 - r1) * f, g1 + (g2 - g1) * f, b1 + (b2 - b1) * f, a1 + (a2 - a1) * f))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/blue
    class public var blue: NSColor { NSColor(storage: .rgb(0, 0, 1, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/bluecomponent
    open var blueComponent: CGFloat { storage.rgba.2 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/brightnesscomponent
    open var brightnessComponent: CGFloat { hsb.2 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/brown
    class public var brown: NSColor { NSColor(storage: .rgb(0.6, 0.4, 0.2, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/catalognamecomponent
    open var catalogNameComponent: NSColorList.Name { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/cgcolor
    open var cgColor: CGColor {
        let (r, g, b, a) = storage.rgba
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/clear
    class public var clear: NSColor { NSColor(storage: .rgb(0, 0, 0, 0)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/colornamecomponent
    open var colorNameComponent: NSColor.Name { if case let .named(n, _, _, _, _) = storage { return NSColor.Name(n) }; unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/colorspace
    open var colorSpace: NSColorSpace { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/colorspacename
    open var colorSpaceName: NSColorSpaceName { if case .gray = storage { return .calibratedWhite }; return .calibratedRGB }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlaccentcolor
    @available(macOS 10.14, *)
    class public var controlAccentColor: NSColor { named("controlAccentColor", 0, 0.478, 1, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/controlalternatingrowbackgroundcolors
    class public var controlAlternatingRowBackgroundColors: [NSColor] { unimplemented() }
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
    open var cyanComponent: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/darkgray
    class public var darkGray: NSColor { NSColor(storage: .rgb(0.3333333333333333, 0.3333333333333333, 0.3333333333333333, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/disabledcontroltextcolor
    class public var disabledControlTextColor: NSColor { named("disabledControlTextColor", 0, 0, 0, 0.25) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/drawswatch(in:)
    open func drawSwatch(in rect: NSRect) { setFill(); NSBezierPath.fill(rect) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/findhighlightcolor
    @available(macOS 10.13, *)
    class public var findHighlightColor: NSColor { named("findHighlightColor", 1, 1, 0, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/getcomponents(_:)
    open func getComponents(_ components: UnsafeMutablePointer<CGFloat>) {
        if case let .gray(w, a) = storage { components[0] = w; components[1] = a; return }
        let (r, g, b, a) = storage.rgba
        components[0] = r; components[1] = g; components[2] = b; components[3] = a
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/getcyan(_:magenta:yellow:black:alpha:)
    open func getCyan(_ cyan: UnsafeMutablePointer<CGFloat>?, magenta: UnsafeMutablePointer<CGFloat>?, yellow: UnsafeMutablePointer<CGFloat>?, black: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/gethue(_:saturation:brightness:alpha:)
    open func getHue(_ hue: UnsafeMutablePointer<CGFloat>?, saturation: UnsafeMutablePointer<CGFloat>?, brightness: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        let (h, s, b) = hsb
        hue?.pointee = h; saturation?.pointee = s; brightness?.pointee = b; alpha?.pointee = alphaComponent
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/getred(_:green:blue:alpha:)
    open func getRed(_ red: UnsafeMutablePointer<CGFloat>?, green: UnsafeMutablePointer<CGFloat>?, blue: UnsafeMutablePointer<CGFloat>?, alpha: UnsafeMutablePointer<CGFloat>?) {
        let (r, g, b, a) = storage.rgba
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
    open var greenComponent: CGFloat { storage.rgba.1 }
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
    @MainActor class public var ignoresAlpha: Bool {
        get { unimplemented() }
        set { unimplemented() }
    }
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
    open var linearExposure: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/linkcolor
    @available(macOS 10.10, *)
    class public var linkColor: NSColor { named("linkColor", 0, 0.41, 0.85, 1) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/localizedcatalognamecomponent
    open var localizedCatalogNameComponent: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/localizedcolornamecomponent
    open var localizedColorNameComponent: String { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/magenta
    class public var magenta: NSColor { NSColor(storage: .rgb(1, 0, 1, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/magentacomponent
    open var magentaComponent: CGFloat { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/numberofcomponents
    open var numberOfComponents: Int { if case .gray = storage { return 2 }; return 4 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/orange
    class public var orange: NSColor { NSColor(storage: .rgb(1, 0.5, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/patternimage
    open var patternImage: NSImage { unimplemented() }
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
    class public var quaternarySystemFill: NSColor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/quinarylabel
    @available(macOS 11.0, *)
    class public var quinaryLabel: NSColor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/quinarysystemfill
    @available(macOS 14.0, *)
    class public var quinarySystemFill: NSColor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/red
    class public var red: NSColor { NSColor(storage: .rgb(1, 0, 0, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/redcomponent
    open var redComponent: CGFloat { storage.rgba.0 }
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
    class public var secondarySystemFill: NSColor { unimplemented() }
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
    open var standardDynamicRange: NSColor { unimplemented() }
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
    class public var systemFill: NSColor { unimplemented() }
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
    class public var tertiarySystemFill: NSColor { unimplemented() }
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
    open var type: NSColor.ColorType { if case .named = storage { return .catalog }; return .componentBased }
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
    open func usingColorSpace(_ space: NSColorSpace) -> NSColor? { self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/usingcolorspacename(_:)
    open func usingColorSpaceName(_ name: NSColorSpaceName) -> NSColor? { self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/usingcolorspacename(_:device:)
    open func usingColorSpaceName(_ name: NSColorSpaceName?, device deviceDescription: [NSDeviceDescriptionKey : Any]?) -> NSColor? { self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/usingtype(_:)
    @available(macOS 10.13, *)
    open func usingType(_ type: NSColor.ColorType) -> NSColor? { type == .componentBased ? NSColor(storage: .rgb(redComponent, greenComponent, blueComponent, alphaComponent)) : self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/white
    class public var white: NSColor { NSColor(storage: .rgb(1, 1, 1, 1)) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nscolor/whitecomponent
    open var whiteComponent: CGFloat {
        if case let .gray(w, _) = storage { return w }
        let (r, g, b, _) = storage.rgba
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
        switch storage {
        case let .rgb(r, g, b, _): return NSColor(storage: .rgb(r, g, b, alpha))
        case let .gray(w, _): return NSColor(storage: .gray(w, alpha))
        case let .named(n, r, g, b, _), let .namedAlpha(n, r, g, b, _): return NSColor(storage: .namedAlpha(n, r, g, b, alpha))
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
    open var yellowComponent: CGFloat { unimplemented() }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { unimplemented() }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // MARK: Pasteboard (`com.apple.cocoa.pasteboard.color`): the sRGB components as a property list.
    public static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [.color] }
    public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [.color] }
    public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .color else { return nil }
        let (r, g, b, a) = storage.rgba
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
