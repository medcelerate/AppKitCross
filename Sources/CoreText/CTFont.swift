// CTFont and CTFontDescriptor (CTFont.h, CTFontDescriptor.h, CTFontTraits.h).

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctfontdescriptor
public final class CTFontDescriptor: NSObject {
    let attributes: [String: Any]
    init(attributes: [String: Any]) { self.attributes = attributes }

    public override var description: String { "<CTFontDescriptor \(attributes)>" }
    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CTFontDescriptor else { return false }
        return (attributes as NSDictionary).isEqual(o.attributes as NSDictionary)
    }
}

public func CTFontDescriptorGetTypeID() -> CFTypeID { 1 }

/// A numeric attribute value however it was boxed: callers store CGFloat, Double or Int
/// in CF dictionaries, and corelibs Foundation does not bridge every one of those to
/// NSNumber on an `as?` cast (CGFloat on Windows, for one).
func _ctNumber(_ value: Any?) -> Double? {
    switch value {
    case let n as NSNumber: return n.doubleValue
    case let d as Double: return d
    case let f as CGFloat: return Double(f)
    case let f as Float: return Double(f)
    case let i as Int: return Double(i)
    case let u as UInt32: return Double(u)
    default: return nil
    }
}

public func CTFontDescriptorCreateWithNameAndSize(_ name: CFString, _ size: CGFloat) -> CTFontDescriptor {
    CTFontDescriptor(attributes: [kCTFontNameAttribute as String: name as String, kCTFontSizeAttribute as String: size])
}

public func CTFontDescriptorCreateWithAttributes(_ attributes: CFDictionary) -> CTFontDescriptor {
    var dict: [String: Any] = [:]
    for (k, v) in attributes { if let key = k as? String { dict[key] = v } else if let key = k as? NSString { dict[key as String] = v } }
    return CTFontDescriptor(attributes: dict)
}

public func CTFontDescriptorCreateCopyWithAttributes(_ original: CTFontDescriptor, _ attributes: CFDictionary) -> CTFontDescriptor {
    var dict = original.attributes
    for (k, v) in attributes { if let key = (k as? String) ?? (k as? NSString).map({ $0 as String }) { dict[key] = v } }
    return CTFontDescriptor(attributes: dict)
}

public func CTFontDescriptorCreateCopyWithFamily(_ original: CTFontDescriptor, _ family: CFString) -> CTFontDescriptor? {
    var dict = original.attributes
    dict[kCTFontFamilyNameAttribute as String] = family as String
    dict[kCTFontNameAttribute as String] = nil
    return CTFontDescriptor(attributes: dict)
}

public func CTFontDescriptorCreateCopyWithSymbolicTraits(_ original: CTFontDescriptor, _ symTraitValue: CTFontSymbolicTraits, _ symTraitMask: CTFontSymbolicTraits) -> CTFontDescriptor? {
    var dict = original.attributes
    var traits = (dict[kCTFontTraitsAttribute as String] as? [String: Any]) ?? [:]
    let current = CTFontSymbolicTraits(rawValue: _ctNumber(traits[kCTFontSymbolicTrait as String]).map { UInt32($0) } ?? 0)
    let updated = CTFontSymbolicTraits(rawValue: (current.rawValue & ~symTraitMask.rawValue) | (symTraitValue.rawValue & symTraitMask.rawValue))
    traits[kCTFontSymbolicTrait as String] = NSNumber(value: updated.rawValue)
    dict[kCTFontTraitsAttribute as String] = traits
    return CTFontDescriptor(attributes: dict)
}

public func CTFontDescriptorCopyAttribute(_ descriptor: CTFontDescriptor, _ attribute: CFString) -> CFTypeRef? {
    descriptor.attributes[attribute as String].map { $0 as AnyObject }
}

public func CTFontDescriptorCopyAttributes(_ descriptor: CTFontDescriptor) -> CFDictionary {
    descriptor.attributes as NSDictionary
}

public func CTFontDescriptorCreateMatchingFontDescriptor(_ descriptor: CTFontDescriptor, _ mandatoryAttributes: CFCharacterSet?) -> CTFontDescriptor? {
    guard let f = CTFont._resolve(descriptor, size: nil) else { return nil }
    return CTFontCopyFontDescriptor(CTFont(engine: f))
}

/// The installed faces a descriptor matches: a descriptor with a PostScript name
/// resolves to that face; one with a family alone lists every face of the family, which
/// a style name (`kCTFontStyleNameAttribute`) or symbolic bold/italic traits narrow.
/// Each result carries the name, family, style, display name, size and traits of a
/// real face, as Apple's CoreText reports them.
public func CTFontDescriptorCreateMatchingFontDescriptors(_ descriptor: CTFontDescriptor, _ mandatoryAttributes: CFCharacterSet?) -> CFArray? {
    let a = descriptor.attributes
    let size = _ctNumber(a[kCTFontSizeAttribute as String]).map { CGFloat($0) } ?? 12
    if a[kCTFontNameAttribute as String] != nil {
        return CTFontDescriptorCreateMatchingFontDescriptor(descriptor, mandatoryAttributes).map { [$0] as NSArray }
    }
    guard let family = a[kCTFontFamilyNameAttribute as String] as? String else {
        return CTFontDescriptorCreateMatchingFontDescriptor(descriptor, mandatoryAttributes).map { [$0] as NSArray }
    }
    var faces = CTRuntime.engine.faces(inFamily: family, size: size)
    if let style = a[kCTFontStyleNameAttribute as String] as? String {
        faces = faces.filter { $0.styleName.lowercased() == style.lowercased() }
    }
    if let traits = a[kCTFontTraitsAttribute as String] as? [String: Any], let sym = _ctNumber(traits[kCTFontSymbolicTrait as String]) {
        let wanted = CTFontSymbolicTraits(rawValue: UInt32(sym))
        faces = faces.filter { f in (!wanted.contains(.traitBold) || f.isBold) && (!wanted.contains(.traitItalic) || f.isItalic) }
    }
    guard !faces.isEmpty else { return nil }
    return faces.map { CTFontCopyFontDescriptor(CTFont(engine: $0)) } as NSArray
}

// MARK: CTFontManager (the installed fonts)

/// - SeeAlso: https://developer.apple.com/documentation/coretext/1499516-ctfontmanagercopyavailablefontfamilynames
public func CTFontManagerCopyAvailableFontFamilyNames() -> CFArray {
    CTRuntime.engine.familyNames as NSArray
}

/// - SeeAlso: https://developer.apple.com/documentation/coretext/1499485-ctfontmanagercopyavailablepostscriptnames
public func CTFontManagerCopyAvailablePostScriptNames() -> CFArray {
    CTRuntime.engine.familyNames.flatMap { CTRuntime.engine.faces(inFamily: $0, size: 12).map { $0.postScriptName } } as NSArray
}


/// - SeeAlso: https://developer.apple.com/documentation/coretext/ctfont
public final class CTFont: NSObject {
    let engine: CTEngineFont
    let matrix: CGAffineTransform
    private let requestedName: String?

    init(engine: CTEngineFont, matrix: CGAffineTransform = .identity, requestedName: String? = nil) {
        self.engine = engine
        self.matrix = matrix
        self.requestedName = requestedName
    }

    public override var description: String { "<CTFont \(engine.postScriptName) \(engine.size) pt>" }
    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CTFont else { return false }
        return o.engine.postScriptName == engine.postScriptName && o.engine.size == engine.size && o.matrix == matrix
    }
    public override var hash: Int { engine.postScriptName.hashValue ^ Int(engine.size * 64) }

    var symbolicTraits: CTFontSymbolicTraits {
        var t = CTFontSymbolicTraits()
        if engine.isBold { t.insert(.traitBold) }
        if engine.isItalic { t.insert(.traitItalic) }
        if engine.isMonospace { t.insert(.traitMonoSpace) }
        return t
    }

    /// Resolves a descriptor (name, family, size, traits) through the engine.
    static func _resolve(_ d: CTFontDescriptor, size: CGFloat?) -> CTEngineFont? {
        let a = d.attributes
        let pointSize = size ?? _ctNumber(a[kCTFontSizeAttribute as String]).map { CGFloat($0) } ?? 12
        let name = (a[kCTFontNameAttribute as String] as? String) ?? (a[kCTFontFamilyNameAttribute as String] as? String)
        var weight: CGFloat? = nil
        var italic: Bool? = nil
        if let traits = a[kCTFontTraitsAttribute as String] as? [String: Any] ?? (a[kCTFontTraitsAttribute as String] as? NSDictionary).map({ d in
            var out: [String: Any] = [:]; for (k, v) in d { if let s = (k as? String) ?? (k as? NSString).map({ $0 as String }) { out[s] = v } }; return out }) {
            if let w = _ctNumber(traits[kCTFontWeightTrait as String]) { weight = CGFloat(w) }
            if let s = _ctNumber(traits[kCTFontSlantTrait as String]) { italic = s != 0 }
            if let sym = _ctNumber(traits[kCTFontSymbolicTrait as String]) {
                let st = CTFontSymbolicTraits(rawValue: UInt32(sym))
                if st.contains(.traitBold) { weight = max(weight ?? 0, 0.4) }
                if st.contains(.traitItalic) { italic = true }
            }
        }
        let uiType: CTFontUIFontType = (a[kCTFontNameAttribute as String] == nil && a[kCTFontFamilyNameAttribute as String] == nil) ? .system : .none
        return CTRuntime.engine.makeFont(name: name, size: pointSize, weight: weight, italic: italic, uiType: uiType)
    }
}

public func CTFontGetTypeID() -> CFTypeID { 2 }

public func CTFontCreateWithName(_ name: CFString, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    let s = size == 0 ? 12 : size
    let n = name as String
    // As on Apple platforms, an unknown name falls back silently (callers compare names).
    let f = CTRuntime.engine.makeFont(name: n, size: s, weight: nil, italic: nil, uiType: .none)
        ?? CTRuntime.engine.makeFont(name: nil, size: s, weight: nil, italic: nil, uiType: .user)!
    return CTFont(engine: f, matrix: matrix?.pointee ?? .identity, requestedName: n)
}

public func CTFontCreateWithNameAndOptions(_ name: CFString, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?, _ options: CTFontOptions) -> CTFont {
    CTFontCreateWithName(name, size, matrix)
}

public func CTFontCreateWithFontDescriptor(_ descriptor: CTFontDescriptor, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?) -> CTFont {
    let f = CTFont._resolve(descriptor, size: size == 0 ? nil : size)
        ?? CTRuntime.engine.makeFont(name: nil, size: size == 0 ? 12 : size, weight: nil, italic: nil, uiType: .user)!
    return CTFont(engine: f, matrix: matrix?.pointee ?? .identity)
}

public func CTFontCreateWithFontDescriptorAndOptions(_ descriptor: CTFontDescriptor, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?, _ options: CTFontOptions) -> CTFont {
    CTFontCreateWithFontDescriptor(descriptor, size, matrix)
}

public func CTFontCreateUIFontForLanguage(_ uiType: CTFontUIFontType, _ size: CGFloat, _ language: CFString?) -> CTFont? {
    var s = size
    if s == 0 {
        switch uiType {
        case .smallSystem, .smallEmphasizedSystem, .smallToolbar, .toolTip, .systemDetail, .emphasizedSystemDetail: s = 11
        case .miniSystem, .miniEmphasizedSystem: s = 9
        case .label, .controlContent: s = 10
        case .windowTitle, .pushButton, .menuTitle, .menuItem, .alertHeader, .message, .application, .views, .user, .userFixedPitch, .system, .emphasizedSystem, .none, .utilityWindowTitle, .palette, .menuItemMark, .menuItemCmdKey, .toolbar: s = 13
        }
    }
    let bold: Bool
    switch uiType {
    case .emphasizedSystem, .smallEmphasizedSystem, .miniEmphasizedSystem, .emphasizedSystemDetail, .alertHeader, .windowTitle, .menuTitle: bold = true
    default: bold = false
    }
    guard let f = CTRuntime.engine.makeFont(name: nil, size: s, weight: bold ? 0.4 : nil, italic: nil, uiType: uiType) else { return nil }
    return CTFont(engine: f)
}

public func CTFontCreateUIFont(_ uiType: CTFontUIFontType, _ size: CGFloat, _ language: CFString?) -> CTFont? {
    CTFontCreateUIFontForLanguage(uiType, size, language)
}

public func CTFontCreateCopyWithAttributes(_ font: CTFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?, _ attributes: CTFontDescriptor?) -> CTFont {
    let s = size == 0 ? font.engine.size : size
    if let attributes {
        var merged = CTFontCopyFontDescriptor(font).attributes
        for (k, v) in attributes.attributes { merged[k] = v }
        if let f = CTFont._resolve(CTFontDescriptor(attributes: merged), size: s) {
            return CTFont(engine: f, matrix: matrix?.pointee ?? font.matrix)
        }
    }
    return CTFont(engine: font.engine.withSize(s), matrix: matrix?.pointee ?? font.matrix)
}

public func CTFontCreateCopyWithSymbolicTraits(_ font: CTFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?, _ symTraitValue: CTFontSymbolicTraits, _ symTraitMask: CTFontSymbolicTraits) -> CTFont? {
    let s = size == 0 ? font.engine.size : size
    let current = font.symbolicTraits
    let wanted = CTFontSymbolicTraits(rawValue: (current.rawValue & ~symTraitMask.rawValue) | (symTraitValue.rawValue & symTraitMask.rawValue))
    let weight: CGFloat? = symTraitMask.contains(.traitBold) ? (wanted.contains(.traitBold) ? 0.4 : 0) : font.engine.weight
    let italic: Bool? = symTraitMask.contains(.traitItalic) ? wanted.contains(.traitItalic) : font.engine.isItalic
    guard let f = CTRuntime.engine.makeFont(name: font.engine.familyName, size: s, weight: weight, italic: italic, uiType: .none) else { return nil }
    return CTFont(engine: f, matrix: matrix?.pointee ?? font.matrix)
}

public func CTFontCreateCopyWithFamily(_ font: CTFont, _ size: CGFloat, _ matrix: UnsafePointer<CGAffineTransform>?, _ family: CFString) -> CTFont? {
    let s = size == 0 ? font.engine.size : size
    guard let f = CTRuntime.engine.makeFont(name: family as String, size: s, weight: font.engine.weight, italic: font.engine.isItalic, uiType: .none) else { return nil }
    return CTFont(engine: f, matrix: matrix?.pointee ?? font.matrix)
}

public func CTFontCreateForString(_ currentFont: CTFont, _ string: CFString, _ range: CFRange) -> CTFont {
    // The font that can show `string`: the first fallback the engine picks for it.
    let text = CTText(string)
    let sub = Array(text.units[max(0, range.location)..<min(text.count, range.location + range.length)])
    let runs = CTRuntime.engine.shape(sub, font: currentFont.engine, language: nil)
    if let first = runs.first, first.font.postScriptName != currentFont.engine.postScriptName { return CTFont(engine: first.font, matrix: currentFont.matrix) }
    return currentFont
}

public func CTFontCreateForStringWithLanguage(_ currentFont: CTFont, _ string: CFString, _ range: CFRange, _ language: CFString?) -> CTFont {
    CTFontCreateForString(currentFont, string, range)
}

public func CTFontCopyFontDescriptor(_ font: CTFont) -> CTFontDescriptor {
    let traits: [String: Any] = [
        kCTFontSymbolicTrait as String: NSNumber(value: font.symbolicTraits.rawValue),
        kCTFontWeightTrait as String: NSNumber(value: Double(font.engine.weight)),
        kCTFontSlantTrait as String: NSNumber(value: Double(font.engine.slant)),
    ]
    return CTFontDescriptor(attributes: [
        kCTFontNameAttribute as String: font.engine.postScriptName,
        kCTFontFamilyNameAttribute as String: font.engine.familyName,
        kCTFontStyleNameAttribute as String: font.engine.styleName,
        kCTFontDisplayNameAttribute as String: font.engine.fullName,
        kCTFontSizeAttribute as String: NSNumber(value: Double(font.engine.size)),
        kCTFontTraitsAttribute as String: traits,
    ])
}

public func CTFontCopyAttribute(_ font: CTFont, _ attribute: CFString) -> CFTypeRef? {
    CTFontDescriptorCopyAttribute(CTFontCopyFontDescriptor(font), attribute)
}

public func CTFontGetSize(_ font: CTFont) -> CGFloat { font.engine.size }
public func CTFontGetMatrix(_ font: CTFont) -> CGAffineTransform { font.matrix }
public func CTFontGetSymbolicTraits(_ font: CTFont) -> CTFontSymbolicTraits { font.symbolicTraits }

public func CTFontCopyTraits(_ font: CTFont) -> CFDictionary {
    (CTFontCopyFontDescriptor(font).attributes[kCTFontTraitsAttribute as String] as? [String: Any] ?? [:]) as NSDictionary
}

public func CTFontCopyPostScriptName(_ font: CTFont) -> CFString { font.engine.postScriptName as NSString }
public func CTFontCopyFamilyName(_ font: CTFont) -> CFString { font.engine.familyName as NSString }
public func CTFontCopyFullName(_ font: CTFont) -> CFString { font.engine.fullName as NSString }
public func CTFontCopyDisplayName(_ font: CTFont) -> CFString { font.engine.fullName as NSString }

public func CTFontCopyName(_ font: CTFont, _ nameKey: CFString) -> CFString? {
    let key = nameKey as String
    if key == kCTFontFamilyNameKey as String { return font.engine.familyName as NSString }
    if key == kCTFontSubFamilyNameKey as String || key == kCTFontStyleNameKey as String { return font.engine.styleName as NSString }
    if key == kCTFontFullNameKey as String { return font.engine.fullName as NSString }
    if key == kCTFontPostScriptNameKey as String { return font.engine.postScriptName as NSString }
    return nil
}

public func CTFontCopyLocalizedName(_ font: CTFont, _ nameKey: CFString, _ actualLanguage: UnsafeMutablePointer<Unmanaged<CFString>?>?) -> CFString? {
    CTFontCopyName(font, nameKey)
}

public func CTFontCopyCharacterSet(_ font: CTFont) -> CFCharacterSet {
    // Characters the face maps: probed over the Basic Multilingual Plane on demand.
    let set = NSMutableCharacterSet()
    var units: [UInt16] = []
    units.reserveCapacity(0xD800)
    for u in 0..<0xD800 { units.append(UInt16(u)) }
    for u in 0xE000..<0x10000 { units.append(UInt16(u)) }
    let glyphs = font.engine.glyphs(for: units)
    for (i, g) in glyphs.enumerated() where g != 0 { set.addCharacters(in: NSRange(location: Int(units[i]), length: 1)) }
    return set
}

public func CTFontGetStringEncoding(_ font: CTFont) -> UInt32 { 0x0100 }   // kCFStringEncodingUnicode

public func CTFontCopySupportedLanguages(_ font: CTFont) -> CFArray { ["en"] as NSArray }

public func CTFontGetAscent(_ font: CTFont) -> CGFloat { font.engine.ascent }
public func CTFontGetDescent(_ font: CTFont) -> CGFloat { font.engine.descent }
public func CTFontGetLeading(_ font: CTFont) -> CGFloat { font.engine.leading }
public func CTFontGetUnitsPerEm(_ font: CTFont) -> UInt32 { font.engine.unitsPerEm }
public func CTFontGetGlyphCount(_ font: CTFont) -> CFIndex { font.engine.glyphCount }
public func CTFontGetBoundingBox(_ font: CTFont) -> CGRect { font.engine.boundingBox }
public func CTFontGetUnderlinePosition(_ font: CTFont) -> CGFloat { font.engine.underlinePosition }
public func CTFontGetUnderlineThickness(_ font: CTFont) -> CGFloat { font.engine.underlineThickness }
public func CTFontGetSlantAngle(_ font: CTFont) -> CGFloat { font.engine.isItalic ? -12 : 0 }
public func CTFontGetCapHeight(_ font: CTFont) -> CGFloat { font.engine.capHeight }
public func CTFontGetXHeight(_ font: CTFont) -> CGFloat { font.engine.xHeight }

public func CTFontGetGlyphWithName(_ font: CTFont, _ glyphName: CFString) -> CGGlyph { font.engine.glyph(named: glyphName as String) }

public func CTFontCreatePathForGlyph(_ font: CTFont, _ glyph: CGGlyph, _ matrix: UnsafePointer<CGAffineTransform>?) -> CGPath? {
    guard let p = font.engine.path(for: glyph) else { return nil }
    var m = (matrix?.pointee ?? .identity).concatenating(font.matrix)
    if m == .identity { return p }
    return p.copy(using: &m)
}

/// Maps characters to glyphs. Returns true when every character mapped.
@discardableResult
public func CTFontGetGlyphsForCharacters(_ font: CTFont, _ characters: UnsafePointer<UniChar>, _ glyphs: UnsafeMutablePointer<CGGlyph>, _ count: CFIndex) -> Bool {
    guard count > 0 else { return true }
    let units = Array(UnsafeBufferPointer(start: characters, count: count))
    let g = font.engine.glyphs(for: units)
    var all = true
    for i in 0..<count {
        glyphs[i] = g[i]
        // A trailing surrogate maps to 0 by design and does not count as a miss.
        if g[i] == 0 && !(i > 0 && (0xDC00...0xDFFF).contains(units[i]) && (0xD800...0xDBFF).contains(units[i - 1])) { all = false }
    }
    return all
}

public func CTFontGetAdvancesForGlyphs(_ font: CTFont, _ orientation: CTFontOrientation, _ glyphs: UnsafePointer<CGGlyph>, _ advances: UnsafeMutablePointer<CGSize>?, _ count: CFIndex) -> Double {
    guard count > 0 else { return 0 }
    let g = Array(UnsafeBufferPointer(start: glyphs, count: count))
    let a = font.engine.advances(for: g)
    var total = 0.0
    for i in 0..<count {
        let adv = font.matrix == .identity ? a[i] : a[i].applying(font.matrix)
        advances?[i] = adv
        total += Double(adv.width)
    }
    return total
}

public func CTFontGetBoundingRectsForGlyphs(_ font: CTFont, _ orientation: CTFontOrientation, _ glyphs: UnsafePointer<CGGlyph>, _ boundingRects: UnsafeMutablePointer<CGRect>?, _ count: CFIndex) -> CGRect {
    guard count > 0 else { return .null }
    let g = Array(UnsafeBufferPointer(start: glyphs, count: count))
    let r = font.engine.boundingRects(for: g)
    var union = CGRect.null
    for i in 0..<count {
        let rect = font.matrix == .identity ? r[i] : r[i].applying(font.matrix)
        boundingRects?[i] = rect
        union = union.union(rect)
    }
    return union
}

public func CTFontGetOpticalBoundsForGlyphs(_ font: CTFont, _ glyphs: UnsafePointer<CGGlyph>, _ boundingRects: UnsafeMutablePointer<CGRect>?, _ count: CFIndex, _ options: CFOptionFlags) -> CGRect {
    CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, boundingRects, count)
}

public func CTFontGetVerticalTranslationsForGlyphs(_ font: CTFont, _ glyphs: UnsafePointer<CGGlyph>, _ translations: UnsafeMutablePointer<CGSize>, _ count: CFIndex) {
    for i in 0..<count { translations[i] = .zero }
}

public func CTFontDrawGlyphs(_ font: CTFont, _ glyphs: UnsafePointer<CGGlyph>, _ positions: UnsafePointer<CGPoint>, _ count: Int, _ context: CGContext) {
    guard count > 0 else { return }
    let g = Array(UnsafeBufferPointer(start: glyphs, count: count))
    let p = Array(UnsafeBufferPointer(start: positions, count: count))
    font.engine.draw(glyphs: g, positions: p, color: context._fillColor, in: context)
}

public func CTFontHasTable(_ font: CTFont, _ tag: CTFontTableTag) -> Bool { font.engine.hasTable(tag) }

public func CTFontCopyAvailableTables(_ font: CTFont, _ options: CTFontTableOptions) -> CFArray? {
    let tags = font.engine.availableTables()
    return tags.isEmpty ? nil : tags.map { NSNumber(value: $0) } as NSArray
}

public func CTFontCopyTable(_ font: CTFont, _ table: CTFontTableTag, _ options: CTFontTableOptions) -> CFData? {
    font.engine.table(table).map { $0 as NSData }
}

public func CTFontCopyVariationAxes(_ font: CTFont) -> CFArray? { nil }
public func CTFontCopyVariation(_ font: CTFont) -> CFDictionary? { nil }
public func CTFontCopyFeatures(_ font: CTFont) -> CFArray? { nil }
public func CTFontCopyFeatureSettings(_ font: CTFont) -> CFArray? { nil }

public func CTFontCopyDefaultCascadeListForLanguages(_ font: CTFont, _ languagePrefList: CFArray?) -> CFArray? { nil }

public typealias CFOptionFlags = UInt

public enum CTFontOrientation: UInt32, Sendable { case `default` = 0, horizontal = 1, vertical = 2 }

/// Four-character table tags as integers (`CTFontTableTag`), e.g. `CTFontTableTag("cmap")`.
extension UInt32 {
    public init(fourCharacterCode s: String) {
        var v: UInt32 = 0
        for u in s.utf8.prefix(4) { v = (v << 8) | UInt32(u) }
        self = v
    }
}
