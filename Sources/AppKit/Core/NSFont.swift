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
    #if !canImport(Darwin)
    /// First stored word: a non-zero CF type ID, see Support/CFBridgeLayout.swift.
    private let _cfinfo = _swiftObjectCFInfo
    #endif
    // MARK: Storage
    internal let handle: any PlatformFontHandle
    private let _fontName: String
    private let _weight: CGFloat
    private let _isSystem: Bool
    private let _italic: Bool
    private let _monospaced: Bool

    /// What makes two fonts measure alike: the face, size and traits (the text measurement
    /// cache's key, so a label is measured once however many `NSFont` objects name its font).
    internal struct _Identity: Hashable {
        let name: String, size: CGFloat, weight: CGFloat, system: Bool, italic: Bool, monospaced: Bool
    }
    internal var _identity: _Identity {
        _Identity(name: _fontName, size: pointSize, weight: _weight, system: _isSystem, italic: _italic, monospaced: _monospaced)
    }

    private init(handle: any PlatformFontHandle, fontName: String, weight: CGFloat, isSystem: Bool, italic: Bool, monospaced: Bool) {
        self.handle = handle
        _fontName = fontName
        _weight = weight
        _isSystem = isSystem
        _italic = italic
        _monospaced = monospaced
        super.init()
    }

    /// Fonts already made, by request: `systemFont(ofSize:weight:)` in a `draw(_:)` would
    /// otherwise build a platform font every frame (on Windows a DirectWrite face lookup and a
    /// descriptor copy, a large part of a scroll frame; ADR-0054). Fonts are immutable, so a
    /// request answers with the same object, as AppKit's shared font instances do. A miss is
    /// remembered too, so an absent family is not looked up again.
    private struct _Request: Hashable { let family: String?, size: CGFloat, weight: CGFloat, italic: Bool, monospaced: Bool }
    @MainActor private static var _made: [_Request: NSFont?] = [:]
    /// Entries kept before the cache starts over (a bound on memory, not a working set).
    internal static let _madeLimit = 1024
    /// Platform fonts built (cache misses), and the time it took, for `APPKITWIN_TRACE_FRAMES`.
    @MainActor internal static var _platformFontsMade = 0
    @MainActor internal static var _platformFontMilliseconds = 0.0
    @MainActor internal static func _removeCachedFonts() { _made.removeAll() }

    private static func make(family: String?, size: CGFloat, weight: CGFloat = 0, italic: Bool = false, monospaced: Bool = false) -> NSFont? {
        let s = size <= 0 ? NSFont.systemFontSize : size
        return MainActor.assumeIsolated {
            let request = _Request(family: family, size: s, weight: weight, italic: italic, monospaced: monospaced)
            if let known = _made[request] { return known }
            let t0 = NSView._traceFrames ? NSView._traceClock() : 0
            let font: NSFont? = Platform.backend.text.makeFont(family: family, size: s, weight: weight, italic: italic, monospaced: monospaced).map { h in
                NSFont(handle: h, fontName: family ?? h.postScriptName, weight: weight, isSystem: family == nil, italic: italic, monospaced: monospaced)
            }
            _platformFontsMade &+= 1
            if NSView._traceFrames { _platformFontMilliseconds += NSView._traceClock() - t0 }
            if _made.count >= _madeLimit { _made.removeAll(keepingCapacity: true) }
            _made[request] = font
            return font
        }
    }

    private static func system(_ size: CGFloat, weight: CGFloat = 0, monospaced: Bool = false) -> NSFont {
        guard let f = make(family: nil, size: size, weight: weight, monospaced: monospaced) else {
            fatalError("AppKitCross: the platform text backend has no system font")
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
    /// The face a descriptor describes: by PostScript name, or by family with the bold and
    /// italic symbolic traits (and the weight trait) applied. A size of 0 takes the descriptor's.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(descriptor:size:)
    public convenience init?(descriptor fontDescriptor: NSFontDescriptor, size fontSize: CGFloat) {
        let size = fontSize > 0 ? fontSize : (fontDescriptor.pointSize > 0 ? fontDescriptor.pointSize : NSFont.systemFontSize)
        let a = fontDescriptor.fontAttributes
        let traits = fontDescriptor.symbolicTraits
        var weight: CGFloat = traits.contains(.bold) ? NSFont.Weight.bold.rawValue : 0
        if let w = NSFontDescriptor._number(fontDescriptor._traits[.weight]) { weight = CGFloat(w) }
        let italic = traits.contains(.italic) || (NSFontDescriptor._number(fontDescriptor._traits[.slant]).map { $0 != 0 } ?? false)
        if let name = a[.name] as? String {
            guard let f = NSFont.make(family: name, size: size) else { return nil }
            // A named face already carries its own weight and slant; traits only add to it.
            let base = NSFont(handle: f.handle, fontName: name, weight: 0, isSystem: false, italic: false, monospaced: f._monospaced)
            let adjusted = (weight != 0 || italic) ? base._converted(italic: italic ? true : nil, weight: weight != 0 ? weight : nil, monospaced: nil) : base
            self.init(handle: adjusted.handle, fontName: adjusted._fontName, weight: adjusted._weight, isSystem: false, italic: adjusted._italic, monospaced: adjusted._monospaced)
            return
        }
        if let family = a[.family] as? String {
            guard let f = NSFont.make(family: family, size: size, weight: weight, italic: italic, monospaced: traits.contains(.monoSpace)) else { return nil }
            self.init(handle: f.handle, fontName: family, weight: weight, isSystem: false, italic: italic, monospaced: f._monospaced)
            return
        }
        // Neither: the system font with the traits.
        let f = NSFont.system(size, weight: weight, monospaced: traits.contains(.monoSpace))._converted(italic: italic ? true : nil, weight: nil, monospaced: nil)
        self.init(handle: f.handle, fontName: f._fontName, weight: f._weight, isSystem: true, italic: f._italic, monospaced: f._monospaced)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(descriptor:texttransform:)
    public convenience init?(descriptor fontDescriptor: NSFontDescriptor, textTransform: AffineTransform?) {
        self.init(descriptor: fontDescriptor, size: 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(name:matrix:)
    /// The matrix's x scale is the point size (AppKit: the identity matrix makes a 1-point
    /// font). A sheared or rotated matrix keeps that size; the port draws fonts unsheared.
    public convenience init?(name fontName: String, matrix fontMatrix: UnsafePointer<CGFloat>) {
        let size = fontMatrix[0] == 0 ? abs(fontMatrix[3]) : abs(fontMatrix[0])
        guard let f = NSFont.make(family: fontName, size: size) else { return nil }
        self.init(handle: f.handle, fontName: fontName, weight: 0, isSystem: false, italic: false, monospaced: f._monospaced)
        _matrixOverride = (0..<6).map { fontMatrix[$0] }
    }
    private var _matrixOverride: [CGFloat]? = nil
    private var _matrixBuffer: UnsafeMutablePointer<CGFloat>? = nil
    deinit { _matrixBuffer?.deallocate() }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/init(name:size:)
    public convenience init?(name fontName: String, size fontSize: CGFloat) {
        guard let f = NSFont.make(family: fontName, size: fontSize) else { return nil }
        self.init(handle: f.handle, fontName: fontName, weight: 0, isSystem: false, italic: false, monospaced: f._monospaced)
    }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func advancement(forCGGlyph glyph: CGGlyph) -> NSSize
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/advancement(forglyph:)
    /// Zero for a glyph the face does not have (macOS 15).
    open func advancement(forGlyph glyph: NSGlyph) -> NSSize {
        guard glyph < NSGlyph(numberOfGlyphs) else { return .zero }
        var a = NSSize.zero
        getAdvancements(&a, forGlyphs: [glyph], count: 1)
        return a
    }
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
    /// Zero for a glyph the face does not have (macOS 15).
    open func boundingRect(forGlyph glyph: NSGlyph) -> NSRect {
        guard glyph < NSGlyph(numberOfGlyphs) else { return .zero }
        var r = NSRect.zero
        getBoundingRects(&r, forGlyphs: [glyph], count: 1)
        return r
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/boundingrectforfont
    open var boundingRectForFont: NSRect { NSRect(x: 0, y: -handle.descent, width: pointSize, height: handle.ascent + handle.descent) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/capheight
    open var capHeight: CGFloat { handle.capHeight }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/controlcontentfont(ofsize:)
    public class func controlContentFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/coveredcharacterset
    open var coveredCharacterSet: CharacterSet {
        #if canImport(CoreText)
        return CTFontCopyCharacterSet(_coreTextFont) as CharacterSet
        #else
        unimplemented("NSFont.coveredCharacterSet — needs CoreText")
        #endif
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/descender
    open var descender: CGFloat { -handle.descent }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/displayname
    open var displayName: String? { handle.familyName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/familyname
    open var familyName: String? { handle.familyName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/fontdescriptor
    open var fontDescriptor: NSFontDescriptor {
        var symbolic: NSFontDescriptor.SymbolicTraits = []
        if _italic { symbolic.insert(.italic) }
        if _weight >= NSFont.Weight.semibold.rawValue { symbolic.insert(.bold) }
        if isFixedPitch { symbolic.insert(.monoSpace) }
        if _isSystem { symbolic.insert(.UIOptimized) }
        let traits: [NSFontDescriptor.TraitKey: Any] = [.symbolic: NSNumber(value: symbolic.rawValue), .weight: NSNumber(value: Double(_weight)), .slant: NSNumber(value: _italic ? 0.2 : 0)]
        var a: [NSFontDescriptor.AttributeName: Any] = [.name: handle.postScriptName, .size: pointSize, .traits: traits]
        if let fam = familyName { a[.family] = fam }
        if let name = displayName { a[.visibleName] = name }
        a[.face] = _styleName
        return NSFontDescriptor(fontAttributes: a)
    }
    /// The face's style name ("Bold Italic"), from the platform when it knows it.
    internal var _styleName: String {
        if let s = handle.styleName, !s.isEmpty { return s }
        switch (_weight >= NSFont.Weight.semibold.rawValue, _italic) {
        case (true, true): return "Bold Italic"
        case (true, false): return "Bold"
        case (false, true): return "Italic"
        case (false, false): return "Regular"
        }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/fontname
    open var fontName: String { _fontName }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/fontsetchangednotification
    static public var fontSetChangedNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSFontSetChangedNotification") }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func getAdvancements(_ advancements: NSSizeArray, forCGGlyphs glyphs: UnsafePointer<CGGlyph>, count glyphCount: Int)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/getadvancements(_:forglyphs:count:)
    open func getAdvancements(_ advancements: NSSizeArray, forGlyphs glyphs: UnsafePointer<NSGlyph>, count glyphCount: Int) {
        guard glyphCount > 0 else { return }
        #if canImport(CoreText)
        let cg = (0..<glyphCount).map { CGGlyph(truncatingIfNeeded: glyphs[$0]) }
        cg.withUnsafeBufferPointer { _ = CTFontGetAdvancesForGlyphs(_coreTextFont, .horizontal, $0.baseAddress!, advancements, glyphCount) }
        #else
        unimplemented("NSFont.getAdvancements — needs CoreText")
        #endif
    }
    /// Packed glyphs are NSNativeShortGlyphPacking: big-endian 16-bit glyphs, `length` bytes.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/getadvancements(_:forpackedglyphs:length:)
    open func getAdvancements(_ advancements: NSSizeArray, forPackedGlyphs packedGlyphs: UnsafeRawPointer, length: Int) {
        let bytes = packedGlyphs.assumingMemoryBound(to: UInt8.self)
        let glyphs = (0..<(length / 2)).map { NSGlyph(UInt16(bytes[2 * $0]) << 8 | UInt16(bytes[2 * $0 + 1])) }
        glyphs.withUnsafeBufferPointer { getAdvancements(advancements, forGlyphs: $0.baseAddress!, count: glyphs.count) }
    }
    // SKIPPED (CoreGraphics.CGGlyph not implemented): func getBoundingRects(_ bounds: NSRectArray, forCGGlyphs glyphs: UnsafePointer<CGGlyph>, count glyphCount: Int)
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/getboundingrects(_:forglyphs:count:)
    open func getBoundingRects(_ bounds: NSRectArray, forGlyphs glyphs: UnsafePointer<NSGlyph>, count glyphCount: Int) {
        guard glyphCount > 0 else { return }
        #if canImport(CoreText)
        let cg = (0..<glyphCount).map { CGGlyph(truncatingIfNeeded: glyphs[$0]) }
        cg.withUnsafeBufferPointer { _ = CTFontGetBoundingRectsForGlyphs(_coreTextFont, .horizontal, $0.baseAddress!, bounds, glyphCount) }
        #else
        unimplemented("NSFont.getBoundingRects — needs CoreText")
        #endif
    }
    /// The glyph named in the face's post table; 0 (.notdef) when there is none.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/glyph(withname:)
    open func glyph(withName name: String) -> NSGlyph {
        #if canImport(CoreText)
        return NSGlyph(CTFontGetGlyphWithName(_coreTextFont, name as CFString))
        #else
        unimplemented("NSFont.glyph(withName:) — needs CoreText")
        #endif
    }
    private static let _identityMatrixStorage: UnsafeMutablePointer<CGFloat> = {
        let p = UnsafeMutablePointer<CGFloat>.allocate(capacity: 6)
        p.initialize(from: [1, 0, 0, 1, 0, 0], count: 6)
        return p
    }()
    /// AppKit's NSFontIdentityMatrix is a null sentinel; Swift needs a real pointer, so this
    /// one points at the identity matrix, which `init(name:matrix:)` reads the same way (a
    /// 1-point font, as macOS makes for the sentinel).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/identitymatrix
    class public var identityMatrix: UnsafePointer<CGFloat> { UnsafePointer(_identityMatrixStorage) }
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
    /// The point size scaled identity (`[12 0 0 12 0 0]` for a 12-point font), or the matrix
    /// the font was made with.
    open var matrix: UnsafePointer<CGFloat> {
        if _matrixBuffer == nil {
            let p = UnsafeMutablePointer<CGFloat>.allocate(capacity: 6)
            p.initialize(from: _matrixOverride ?? [pointSize, 0, 0, pointSize, 0, 0], count: 6)
            _matrixBuffer = p
        }
        return UnsafePointer(_matrixBuffer!)
    }
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
    open var numberOfGlyphs: Int {
        #if canImport(CoreText)
        return CTFontGetGlyphCount(_coreTextFont)
        #else
        unimplemented("NSFont.numberOfGlyphs — needs CoreText")
        #endif
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/palettefont(ofsize:)
    public class func paletteFont(ofSize fontSize: CGFloat) -> NSFont { system(fontSize) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/pointsize
    open var pointSize: CGFloat { handle.pointSize }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/preferredfont(fortextstyle:options:)
    @available(macOS 11.0, *)
    /// macOS 15's sizes and weights (there is no Dynamic Type on the Mac, so options change nothing).
    public class func preferredFont(forTextStyle style: NSFont.TextStyle, options: [NSFont.TextStyleOptionKey : Any] = [:]) -> NSFont {
        switch style {
        case .largeTitle: return system(26)
        case .title1: return system(22)
        case .title2: return system(17)
        case .title3: return system(15)
        case .headline: return system(13, weight: NSFont.Weight.bold.rawValue)
        case .subheadline: return system(11)
        case .callout: return system(12)
        case .footnote, .caption1: return system(10)
        case .caption2: return system(10, weight: NSFont.Weight.medium.rawValue)
        default: return system(13)
        }
    }
    /// The font itself: printing uses the same outlines (macOS returns the receiver).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/printer
    open var printer: NSFont { self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/renderingmode
    open var renderingMode: NSFontRenderingMode { .defaultRenderingMode }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/screen
    /// The font itself: the port has no separate bitmap screen fonts (its rasterisers hint
    /// the outlines), so the screen font measures as the printer font does.
    open var screen: NSFont { self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/screenfont(with:)
    open func screenFont(with renderingMode: NSFontRenderingMode) -> NSFont { self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/set()
    open func set() { NSGraphicsContext.current?._font = self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/set(in:)
    open func set(in graphicsContext: NSGraphicsContext) { graphicsContext._font = self }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/setuser(_:)
    /// Stores the font in the `NSFont`/`NSFontSize` defaults (nil removes them), as macOS.
    public class func setUser(_ font: NSFont?) { _setDefault(font, name: "NSFont", size: "NSFontSize") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/setuserfixedpitch(_:)
    public class func setUserFixedPitch(_ font: NSFont?) { _setDefault(font, name: "NSFixedPitchFont", size: "NSFixedPitchFontSize") }
    private class func _setDefault(_ font: NSFont?, name: String, size: String) {
        let d = UserDefaults.standard
        if let font { d.set(font.fontName, forKey: name); d.set(Double(font.pointSize), forKey: size) }
        else { d.removeObject(forKey: name); d.removeObject(forKey: size) }
    }
    /// The user font from the defaults, at `fontSize` or (0) the stored size.
    private class func _userDefault(name: String, size: String, ofSize fontSize: CGFloat, fallbackSize: CGFloat) -> NSFont? {
        let d = UserDefaults.standard
        guard let n = d.string(forKey: name) else { return nil }
        let stored = d.double(forKey: size)
        return NSFont(name: n, size: fontSize > 0 ? fontSize : (stored > 0 ? CGFloat(stored) : fallbackSize))
    }
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
    /// The `NSFixedPitchFont` default, else the system monospaced font; size 0 is the stored
    /// size or 11 points (macOS: Menlo 11).
    public class func userFixedPitchFont(ofSize fontSize: CGFloat) -> NSFont? {
        _userDefault(name: "NSFixedPitchFont", size: "NSFixedPitchFontSize", ofSize: fontSize, fallbackSize: 11)
            ?? system(fontSize > 0 ? fontSize : 11, monospaced: true)
    }
    /// The `NSFont` default, else Helvetica; size 0 is the stored size or 12 points.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/userfont(ofsize:)
    public class func userFont(ofSize fontSize: CGFloat) -> NSFont? {
        let size = fontSize > 0 ? fontSize : 12
        return _userDefault(name: "NSFont", size: "NSFontSize", ofSize: fontSize, fallbackSize: 12)
            ?? make(family: "Helvetica", size: size) ?? system(size)
    }
    /// The font itself, as macOS answers for faces without vertical metrics (Helvetica); the
    /// port lays out horizontally only, so every face answers so (`isVertical` stays false).
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfont/vertical
    open var vertical: NSFont { self }
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
