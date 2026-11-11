// NSFontDescriptor (hand-written; seeded from the generated stub, see tools/apigen)
//
// A dictionary of font attributes (ADR-0022). Matching goes through CoreText:
// `CTFontDescriptorCreateMatchingFontDescriptors` over the installed fonts, which the
// port's CoreText module answers from DirectWrite / Pango and the macOS host from Apple's.
// The attribute names are the strings CoreText uses for the same keys, so a descriptor
// converts to a CTFontDescriptor by copying its dictionary.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor
open class NSFontDescriptor: NSObject, NSCopying, NSSecureCoding, NSCoding {
    // MARK: Storage
    internal let _attributes: [NSFontDescriptor.AttributeName: Any]

    /// The traits dictionary, with `TraitKey` keys whatever the caller used.
    internal var _traits: [NSFontDescriptor.TraitKey: Any] {
        guard let raw = _attributes[.traits] else { return [:] }
        if let typed = raw as? [NSFontDescriptor.TraitKey: Any] { return typed }
        var out: [NSFontDescriptor.TraitKey: Any] = [:]
        if let dict = raw as? [String: Any] { for (k, v) in dict { out[NSFontDescriptor.TraitKey(k)] = v } }
        else if let dict = raw as? NSDictionary { for (k, v) in dict { if let s = (k as? String) ?? (k as? NSString).map({ $0 as String }) { out[NSFontDescriptor.TraitKey(s)] = v } } }
        return out
    }

    /// A numeric attribute however it was boxed (NSNumber, Double, CGFloat, Int).
    internal static func _number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let f as CGFloat: return Double(f)
        case let f as Float: return Double(f)
        case let i as Int: return Double(i)
        case let u as UInt32: return Double(u)
        case let u as UInt: return Double(u)
        default: return nil
        }
    }

    private func _with(_ changes: (inout [NSFontDescriptor.AttributeName: Any]) -> Void) -> NSFontDescriptor {
        var a = _attributes
        changes(&a)
        return NSFontDescriptor(fontAttributes: a)
    }

    #if canImport(CoreText)
    /// The CoreText form: the same keys as strings, the traits as a string-keyed dictionary.
    internal var _coreTextAttributes: [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in _attributes {
            if k == .traits {
                var traits: [String: Any] = [:]
                for (tk, tv) in _traits { traits[tk.rawValue] = tv }
                out[kCTFontTraitsAttribute as String] = traits
            } else if k == .matrix {
                continue
            } else {
                out[k.rawValue] = v
            }
        }
        return out
    }

    internal var _coreTextDescriptor: CTFontDescriptor { CTFontDescriptorCreateWithAttributes(_coreTextAttributes as CFDictionary) }

    /// A descriptor from CoreText's dictionary (CFString keys, NSNumber values).
    internal convenience init(_ ct: CTFontDescriptor) {
        var out: [NSFontDescriptor.AttributeName: Any] = [:]
        let dict = CTFontDescriptorCopyAttributes(ct) as NSDictionary
        for (k, v) in dict {
            guard let key = (k as? String) ?? (k as? NSString).map({ $0 as String }) else { continue }
            if key == kCTFontTraitsAttribute as String {
                var traits: [NSFontDescriptor.TraitKey: Any] = [:]
                if let td = v as? NSDictionary { for (tk, tv) in td { if let s = (tk as? String) ?? (tk as? NSString).map({ $0 as String }) { traits[NSFontDescriptor.TraitKey(s)] = tv } } }
                out[.traits] = traits
            } else if key == kCTFontSizeAttribute as String {
                if let n = NSFontDescriptor._number(v) { out[.size] = CGFloat(n) }
            } else {
                out[NSFontDescriptor.AttributeName(key)] = v
            }
        }
        self.init(fontAttributes: out)
    }
    #endif

    #if canImport(CoreText)
    /// A matched descriptor with the face's family, style name, display name and traits
    /// filled in from the font itself (Apple's CoreText answers a match with the
    /// PostScript name alone; the port's CoreText carries all of them).
    internal func _completed() -> NSFontDescriptor {
        guard let name = _attributes[.name] as? String, _attributes[.family] == nil || _attributes[.face] == nil || _attributes[.traits] == nil else { return self }
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        guard (CTFontCopyPostScriptName(font) as String) == name else { return self }
        var a = _attributes
        if a[.family] == nil { a[.family] = CTFontCopyFamilyName(font) as String }
        if a[.face] == nil, let style = CTFontCopyName(font, kCTFontStyleNameKey) { a[.face] = style as String }
        if a[.visibleName] == nil { a[.visibleName] = CTFontCopyDisplayName(font) as String }
        if a[.traits] == nil {
            var traits: [NSFontDescriptor.TraitKey: Any] = [.symbolic: NSNumber(value: CTFontGetSymbolicTraits(font).rawValue)]
            let ct = CTFontCopyTraits(font) as NSDictionary
            if let w = NSFontDescriptor._number(ct[kCTFontWeightTrait as String] ?? ct[kCTFontWeightTrait]) { traits[.weight] = NSNumber(value: w) }
            if let sl = NSFontDescriptor._number(ct[kCTFontSlantTrait as String] ?? ct[kCTFontSlantTrait]) { traits[.slant] = NSNumber(value: sl) }
            a[.traits] = traits
        }
        return NSFontDescriptor(fontAttributes: a)
    }
    #endif

    open override var description: String { "<NSFontDescriptor \(_attributes)>" }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSFontDescriptor else { return false }
        var mine: [String: Any] = [:], theirs: [String: Any] = [:]
        for (k, v) in _attributes { mine[k.rawValue] = k == .traits ? Dictionary(uniqueKeysWithValues: _traits.map { ($0.key.rawValue, $0.value) }) : v }
        for (k, v) in o._attributes { theirs[k.rawValue] = k == .traits ? Dictionary(uniqueKeysWithValues: o._traits.map { ($0.key.rawValue, $0.value) }) : v }
        return (mine as NSDictionary).isEqual(theirs as NSDictionary)
    }
    open override var hash: Int {
        var h = Hasher()
        h.combine(postscriptName ?? "")
        h.combine(object(forKey: .family) as? String ?? "")
        h.combine(pointSize)
        return h.finalize()
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/init(fontattributes:)
    public required init(fontAttributes attributes: [NSFontDescriptor.AttributeName : Any]? = nil) {
        _attributes = attributes ?? [:]
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/init(name:matrix:)
    public convenience init(name fontName: String, matrix: AffineTransform) {
        self.init(fontAttributes: [.name: fontName, .matrix: matrix])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/init(name:size:)
    public convenience init(name fontName: String, size: CGFloat) {
        self.init(fontAttributes: [.name: fontName, .size: size])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/addingattributes(_:)
    open func addingAttributes(_ attributes: [NSFontDescriptor.AttributeName : Any] = [:]) -> NSFontDescriptor {
        _with { a in for (k, v) in attributes { a[k] = v } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/fontattributes
    open var fontAttributes: [NSFontDescriptor.AttributeName : Any] { _attributes }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/matchingfontdescriptor(withmandatorykeys:)
    open func matchingFontDescriptor(withMandatoryKeys mandatoryKeys: Set<NSFontDescriptor.AttributeName>?) -> NSFontDescriptor? {
        matchingFontDescriptors(withMandatoryKeys: mandatoryKeys).first
    }
    /// The installed faces this descriptor describes: by PostScript name, or every face of
    /// a family (narrowed by a face name or bold/italic traits when given). Attributes
    /// outside the mandatory set are preferences, as on macOS: a size or matrix never
    /// excludes a face.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/matchingfontdescriptors(withmandatorykeys:)
    open func matchingFontDescriptors(withMandatoryKeys mandatoryKeys: Set<NSFontDescriptor.AttributeName>?) -> [NSFontDescriptor] {
        #if canImport(CoreText)
        var query = _coreTextAttributes
        // A face name alone resolves through its family on every CoreText.
        if let keys = mandatoryKeys {
            for k in [NSFontDescriptor.AttributeName.face, .traits] where !keys.contains(k) && (keys.contains(.name) || keys.contains(.family)) { query[k.rawValue] = nil }
        }
        let ct = CTFontDescriptorCreateWithAttributes(query as CFDictionary)
        guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(ct, nil) as? [CTFontDescriptor] else { return [] }
        let size = pointSize
        return matches.map { m in
            var d = NSFontDescriptor(m)._completed()
            if size > 0 { d = d._with { $0[.size] = size } }
            return d
        }
        #else
        return []
        #endif
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/matrix
    open var matrix: AffineTransform? { _attributes[.matrix] as? AffineTransform }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/object(forkey:)
    open func object(forKey attribute: NSFontDescriptor.AttributeName) -> Any? {
        if attribute == .traits { let t = _traits; return t.isEmpty ? _attributes[.traits] : t }
        return _attributes[attribute]
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/pointsize
    open var pointSize: CGFloat { NSFontDescriptor._number(_attributes[.size]).map { CGFloat($0) } ?? 0 }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/postscriptname
    open var postscriptName: String? {
        if let n = _attributes[.name] as? String { return n }
        #if canImport(CoreText)
        if _attributes[.family] != nil, let m = matchingFontDescriptors(withMandatoryKeys: [.family]).first, let n = m._attributes[.name] as? String { return n }
        #endif
        return nil
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/preferredfontdescriptor(fortextstyle:options:)
    @available(macOS 11.0, *)
    public class func preferredFontDescriptor(forTextStyle style: NSFont.TextStyle, options: [NSFont.TextStyleOptionKey : Any] = [:]) -> NSFontDescriptor {
        let size: CGFloat
        var traits: NSFontDescriptor.SymbolicTraits = []
        switch style {
        case .largeTitle: size = 26
        case .title1: size = 22
        case .title2: size = 17
        case .title3: size = 15
        case .headline: size = 13; traits = .bold
        case .subheadline: size = 11
        case .callout: size = 12
        case .footnote: size = 10
        case .caption1: size = 10
        case .caption2: size = 10
        default: size = 13
        }
        let system = NSFont.systemFont(ofSize: size).fontDescriptor
        return traits.isEmpty ? system : system.withSymbolicTraits(traits)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/requiresfontassetrequest
    @available(macOS 10.13, *)
    open var requiresFontAssetRequest: Bool { false }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/symbolictraits
    open var symbolicTraits: NSFontDescriptor.SymbolicTraits {
        NSFontDescriptor.SymbolicTraits(rawValue: NSFontDescriptor._number(_traits[.symbolic]).map { UInt32(max(0, $0)) } ?? 0)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/withdesign(_:)
    @available(macOS 10.15, *)
    open func withDesign(_ design: NSFontDescriptor.SystemDesign) -> Self? {
        var a = _attributes
        if design == .monospaced {
            var traits = _traits
            traits[.symbolic] = NSNumber(value: symbolicTraits.union(.monoSpace).rawValue)
            a[.traits] = traits
        }
        return type(of: self).init(fontAttributes: a)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/withface(_:)
    open func withFace(_ newFace: String) -> NSFontDescriptor {
        _with { a in a[.face] = newFace; a[.name] = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/withfamily(_:)
    open func withFamily(_ newFamily: String) -> NSFontDescriptor {
        _with { a in a[.family] = newFamily; a[.name] = nil }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/withmatrix(_:)
    open func withMatrix(_ matrix: AffineTransform) -> NSFontDescriptor { _with { $0[.matrix] = matrix } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/withsize(_:)
    open func withSize(_ newPointSize: CGFloat) -> NSFontDescriptor { _with { $0[.size] = newPointSize } }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontdescriptor/withsymbolictraits(_:)
    open func withSymbolicTraits(_ symbolicTraits: NSFontDescriptor.SymbolicTraits) -> NSFontDescriptor {
        _with { a in
            var traits = _traits
            traits[.symbolic] = NSNumber(value: symbolicTraits.rawValue)
            a[.traits] = traits
            // A trait change applies to the family: the face it names may not have it.
            if a[.family] == nil, let name = a[.name] as? String, let f = NSFont(name: name, size: 12), let fam = f.familyName { a[.family] = fam }
            if a[.family] != nil { a[.name] = nil; a[.face] = nil }
        }
    }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any { self }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        if let n = postscriptName { coder.encode(n, forKey: "NSFontDescriptorName") }
        coder.encode(Double(pointSize), forKey: "NSFontDescriptorSize")
    }
    // Requirement of NSCoding
    public required convenience init?(coder: NSCoder) {
        let name = coder.decodeObject(forKey: "NSFontDescriptorName") as? String
        let size = coder.decodeDouble(forKey: "NSFontDescriptorSize")
        var a: [NSFontDescriptor.AttributeName: Any] = [:]
        if let name { a[.name] = name }
        if size > 0 { a[.size] = CGFloat(size) }
        self.init(fontAttributes: a)
    }
}
