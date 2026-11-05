// NSFont (hand-written; seeded from the generated stub, see tools/apigen)
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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont
open class NSFont: NSObject, NSCopying, NSSecureCoding, NSCoding {
    // MARK: Storage
    internal let handle: any PlatformFontHandle
    private let _fontName: String
    private let _weight: CGFloat
    private let _isSystem: Bool
    private let _italic: Bool
    private let _monospaced: Bool

    private init(handle: any PlatformFontHandle, fontName: String, weight: CGFloat, isSystem: Bool, italic: Bool, monospaced: Bool) {
        self.handle = handle
        _fontName = fontName
        _weight = weight
        _isSystem = isSystem
        _italic = italic
        _monospaced = monospaced
        super.init()
    }

    private static func make(family: String?, size: CGFloat, weight: CGFloat = 0, italic: Bool = false, monospaced: Bool = false) -> NSFont? {
        let s = size <= 0 ? NSFont.systemFontSize : size
        return MainActor.assumeIsolated {
            guard let h = Platform.backend.text.makeFont(family: family, size: s, weight: weight, italic: italic, monospaced: monospaced) else { return nil }
            return NSFont(handle: h, fontName: family ?? h.postScriptName, weight: weight, isSystem: family == nil, italic: italic, monospaced: monospaced)
        }
    }

    private static func system(_ size: CGFloat, weight: CGFloat = 0, monospaced: Bool = false) -> NSFont {
        guard let f = make(family: nil, size: size, weight: weight, monospaced: monospaced) else {
            fatalError("AppKitWin: the platform text backend has no system font")
        }
        return f
    }

    /// The same face with traits changed (NSFontManager's conversions).
    internal func _converted(italic: Bool?, weight: CGFloat?, monospaced: Bool?) -> NSFont {
        let i = italic ?? _italic, w = weight ?? _weight, m = monospaced ?? _monospaced
        if i == _italic, w == _weight, m == _monospaced { return self }
        return NSFont.make(family: _isSystem ? nil : _fontName, size: pointSize, weight: w, italic: i, monospaced: m) ?? self
    }
    internal var _isItalic: Bool { _italic }
    internal var _weightValue: CGFloat { _weight }

    open override var description: String { "\(fontName) \(pointSize) pt." }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSFont else { return false }
        return o.fontName == fontName && o.pointSize == pointSize && o._weight == _weight && o._italic == _italic
    }
    open override var hash: Int { var h = Hasher(); h.combine(fontName); h.combine(pointSize); return h.finalize() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(descriptor:size:)
    public init?(descriptor fontDescriptor: NSFontDescriptor, size fontSize: CGFloat) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(descriptor:texttransform:)
    public init?(descriptor fontDescriptor: NSFontDescriptor, textTransform: AffineTransform?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(name:matrix:)
    public init?(name fontName: String, matrix fontMatrix: UnsafePointer<CGFloat>) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(name:size:)
    public convenience init?(name fontName: String, size fontSize: CGFloat) {
        guard let f = NSFont.make(family: fontName, size: fontSize) else { return nil }
        self.init(handle: f.handle, fontName: fontName, weight: 0, isSystem: false, italic: false, monospaced: f._monospaced)
    }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func advancement(forCGGlyph glyph: CGGlyph) -> NSSize
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/advancement(forglyph:)
    open func advancement(forGlyph glyph: NSGlyph) -> NSSize { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/antialiasthresholdchangednotification
    static public var antialiasThresholdChangedNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSAntialiasThresholdChangedNotification") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/ascender
    /// The CoreText font behind this font (the text system lays out and draws with it).
    #if canImport(CoreText)
    internal var _coreTextFont: CTFont {
        if let h = handle as? HostFont { return h.ct }
        return CTFontCreateWithName(fontName as CFString, pointSize, nil)
    }
    #endif
    open var ascender: CGFloat { handle.ascent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/boldsystemfont(ofsize:)
    public class func boldSystemFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize, weight: NSFont.Weight.bold.rawValue) }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func boundingRect(forCGGlyph glyph: CGGlyph) -> NSRect
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/boundingrect(forglyph:)
    open func boundingRect(forGlyph glyph: NSGlyph) -> NSRect { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/boundingrectforfont
    open var boundingRectForFont: NSRect { NSRect(x: 0, y: -handle.descent, width: pointSize, height: handle.ascent + handle.descent) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/capheight
    open var capHeight: CGFloat { handle.capHeight }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/controlcontentfont(ofsize:)
    public class func controlContentFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/coveredcharacterset
    open var coveredCharacterSet: CharacterSet { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/descender
    open var descender: CGFloat { -handle.descent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/displayname
    open var displayName: String? { handle.familyName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/familyname
    open var familyName: String? { handle.familyName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/fontdescriptor
    open var fontDescriptor: NSFontDescriptor { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/fontname
    open var fontName: String { _fontName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/fontsetchangednotification
    static public var fontSetChangedNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSFontSetChangedNotification") }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func getAdvancements(_ advancements: NSSizeArray, forCGGlyphs glyphs: UnsafePointer<CGGlyph>, count glyphCount: Int)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/getadvancements(_:forglyphs:count:)
    open func getAdvancements(_ advancements: NSSizeArray, forGlyphs glyphs: UnsafePointer<NSGlyph>, count glyphCount: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/getadvancements(_:forpackedglyphs:length:)
    open func getAdvancements(_ advancements: NSSizeArray, forPackedGlyphs packedGlyphs: UnsafeRawPointer, length: Int) { unimplemented() }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func getBoundingRects(_ bounds: NSRectArray, forCGGlyphs glyphs: UnsafePointer<CGGlyph>, count glyphCount: Int)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/getboundingrects(_:forglyphs:count:)
    open func getBoundingRects(_ bounds: NSRectArray, forGlyphs glyphs: UnsafePointer<NSGlyph>, count glyphCount: Int) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/glyph(withname:)
    open func glyph(withName name: String) -> NSGlyph { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/identitymatrix
    class public var identityMatrix: UnsafePointer<CGFloat> { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/isfixedpitch
    open var isFixedPitch: Bool { handle.isFixedPitch }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/isvertical
    open var isVertical: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/italicangle
    open var italicAngle: CGFloat { _italic ? -12 : 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/labelfont(ofsize:)
    public class func labelFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/labelfontsize
    class public var labelFontSize: CGFloat { 10 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/leading
    open var leading: CGFloat { handle.leading }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/matrix
    open var matrix: UnsafePointer<CGFloat> { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/maximumadvancement
    open var maximumAdvancement: NSSize { NSSize(width: pointSize, height: 0) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/menubarfont(ofsize:)
    public class func menuBarFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/menufont(ofsize:)
    public class func menuFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/messagefont(ofsize:)
    public class func messageFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/monospaceddigitsystemfont(ofsize:weight:)
    @available(macOS 10.11, *)
    public class func monospacedDigitSystemFont(ofSize fontSize: CGFloat, weight: NSFont.Weight) -> NSFont { system(fontSize, weight: weight.rawValue) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/monospacedsystemfont(ofsize:weight:)
    @available(macOS 10.15, *)
    public class func monospacedSystemFont(ofSize fontSize: CGFloat, weight: NSFont.Weight) -> NSFont { system(fontSize, weight: weight.rawValue, monospaced: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/mostcompatiblestringencoding
    open var mostCompatibleStringEncoding: UInt { String.Encoding.utf8.rawValue }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/numberofglyphs
    open var numberOfGlyphs: Int { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/palettefont(ofsize:)
    public class func paletteFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/pointsize
    open var pointSize: CGFloat { handle.pointSize }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/preferredfont(fortextstyle:options:)
    @available(macOS 11.0, *)
    public class func preferredFont(forTextStyle style: NSFont.TextStyle, options: [NSFont.TextStyleOptionKey : Any] = [:]) -> NSFont { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/printer
    open var printer: NSFont { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/renderingmode
    open var renderingMode: NSFontRenderingMode { .defaultRenderingMode }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/screen
    open var screen: NSFont { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/screenfont(with:)
    open func screenFont(with renderingMode: NSFontRenderingMode) -> NSFont { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/set()
    open func set() { NSGraphicsContext.current?._font = self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/set(in:)
    open func set(in graphicsContext: NSGraphicsContext) { graphicsContext._font = self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/setuser(_:)
    public class func setUser(_ font: NSFont?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/setuserfixedpitch(_:)
    public class func setUserFixedPitch(_ font: NSFont?) { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/smallsystemfontsize
    class public var smallSystemFontSize: CGFloat { 11 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/systemfont(ofsize:)
    public class func systemFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/systemfont(ofsize:weight:)
    @available(macOS 10.11, *)
    public class func systemFont(ofSize fontSize: CGFloat, weight: NSFont.Weight) -> NSFont { system(fontSize, weight: weight.rawValue) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/systemfont(ofsize:weight:width:)
    @available(macOS 13.0, *)
    public class func systemFont(ofSize fontSize: CGFloat, weight: NSFont.Weight, width: NSFont.Width) -> NSFont { system(fontSize, weight: weight.rawValue) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/systemfontsize
    class public var systemFontSize: CGFloat { 13 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/systemfontsize(for:)
    public class func systemFontSize(for controlSize: NSControl.ControlSize) -> CGFloat {
        switch controlSize {
        case .small: return 11
        case .mini: return 9
        case .large: return 15
        default: return 13
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/texttransform
    open var textTransform: AffineTransform { AffineTransform.identity }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/titlebarfont(ofsize:)
    public class func titleBarFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/tooltipsfont(ofsize:)
    public class func toolTipsFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/underlineposition
    open var underlinePosition: CGFloat { -handle.descent / 2 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/underlinethickness
    open var underlineThickness: CGFloat { max(1, pointSize / 14) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/userfixedpitchfont(ofsize:)
    public class func userFixedPitchFont(ofSize fontSize: CGFloat) -> NSFont? { system(fontSize, monospaced: true) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/userfont(ofsize:)
    public class func userFont(ofSize fontSize: CGFloat) -> NSFont? { make(family: "Helvetica", size: fontSize) ?? system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/vertical
    open var vertical: NSFont { unimplemented() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/withsize(_:)
    @available(macOS 10.15, *)
    open func withSize(_ fontSize: CGFloat) -> NSFont { NSFont.make(family: _isSystem ? nil : _fontName, size: fontSize, weight: _weight, italic: _italic, monospaced: _monospaced) ?? self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/xheight
    open var xHeight: CGFloat { handle.xHeight }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { }
    // Requirement of NSCoding
    public required convenience init?(coder: NSCoder) { self.init(name: "Helvetica", size: 12) }
}
