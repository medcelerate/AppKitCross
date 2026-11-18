// NSFontCollection (hand-written; seeded from the generated stub, see tools/apigen)
//
// A collection is a list of query descriptors (ADR-0022): its matching descriptors are
// the installed faces those queries match, minus the exclusions. Named collections and
// their visibility live in the user defaults (`NSFontCollections`, `NSHiddenFontCollections`)
// since these platforms have no font collection files of their own; the standard names
// (All Fonts, Favorites, Recently Used, User) always exist.

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
/// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection
open class NSFontCollection: NSObject, NSCopying, NSMutableCopying, NSCoding {
    // MARK: Storage
    internal var _queryDescriptors: [NSFontDescriptor]
    internal var _exclusionDescriptors: [NSFontDescriptor] = []
    internal var _name: NSFontCollection.Name? = nil
    internal var _visibility: NSFontCollection.Visibility = .process

    internal static let _storedKey = "NSFontCollections"
    internal static let _hiddenKey = "NSHiddenFontCollections"
    internal static let _standardNames: [NSFontCollection.Name] = [.allFonts, .favorites, .recentlyUsed, .user]

    internal init(_queries: [NSFontDescriptor], exclusions: [NSFontDescriptor] = [], name: NSFontCollection.Name? = nil, visibility: NSFontCollection.Visibility = .process) {
        _queryDescriptors = _queries
        _exclusionDescriptors = exclusions
        _name = name
        _visibility = visibility
        super.init()
    }

    // MARK: Persistence (user defaults)

    internal static func _plist(_ d: NSFontDescriptor) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in d.fontAttributes {
            if k == .traits {
                var t: [String: Double] = [:]
                for (tk, tv) in d._traits { if let n = NSFontDescriptor._number(tv) { t[tk.rawValue] = n } }
                out[k.rawValue] = t
            } else if let s = v as? String { out[k.rawValue] = s }
            else if let n = NSFontDescriptor._number(v) { out[k.rawValue] = n }
        }
        return out
    }

    internal static func _descriptor(_ plist: [String: Any]) -> NSFontDescriptor {
        var a: [NSFontDescriptor.AttributeName: Any] = [:]
        for (k, v) in plist {
            if k == NSFontDescriptor.AttributeName.traits.rawValue, let t = v as? [String: Any] {
                var traits: [NSFontDescriptor.TraitKey: Any] = [:]
                for (tk, tv) in t { if let n = NSFontDescriptor._number(tv) { traits[NSFontDescriptor.TraitKey(tk)] = NSNumber(value: n) } }
                a[.traits] = traits
            } else if k == NSFontDescriptor.AttributeName.size.rawValue, let n = NSFontDescriptor._number(v) { a[.size] = CGFloat(n) }
            else { a[NSFontDescriptor.AttributeName(k)] = v }
        }
        return NSFontDescriptor(fontAttributes: a)
    }

    internal static var _stored: [String: [[String: Any]]] {
        get { (UserDefaults.standard.dictionary(forKey: _storedKey) as? [String: [[String: Any]]]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: _storedKey); UserDefaults.standard.synchronize() }
    }
    internal static var _hidden: [String] {
        get { UserDefaults.standard.stringArray(forKey: _hiddenKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: _hiddenKey); UserDefaults.standard.synchronize() }
    }

    private static func _post(_ action: NSFontCollection.ActionTypeKey, name: NSFontCollection.Name, oldName: NSFontCollection.Name? = nil, visibility: NSFontCollection.Visibility) {
        var info: [NSFontCollection.UserInfoKey: Any] = [actionUserInfoKey: action, nameUserInfoKey: name, visibilityUserInfoKey: visibility]
        if let oldName { info[oldNameUserInfoKey] = oldName }
        var userInfo: [AnyHashable: Any] = [:]
        for (k, v) in info { userInfo[k.rawValue] = v }
        NotificationCenter.default.post(name: didChangeNotification, object: nil, userInfo: userInfo)
    }

    /// Every installed face: one query that names no font, which matches all families.
    internal static var _allQuery: [NSFontDescriptor] { [NSFontDescriptor(fontAttributes: [:])] }

    /// The faces one query descriptor matches.
    internal static func _matches(_ query: NSFontDescriptor) -> [NSFontDescriptor] {
        let a = query.fontAttributes
        if a[.name] != nil { return query.matchingFontDescriptors(withMandatoryKeys: [.name]) }
        if a[.family] != nil {
            var keys: Set<NSFontDescriptor.AttributeName> = [.family]
            if a[.face] != nil { keys.insert(.face) }
            if a[.traits] != nil { keys.insert(.traits) }
            return query.matchingFontDescriptors(withMandatoryKeys: keys)
        }
        // No name: every family, narrowed by traits when given.
        let traits = query.symbolicTraits
        let families = MainActor.assumeIsolated { NSFontManager.shared.availableFontFamilies }
        var out: [NSFontDescriptor] = []
        for fam in families {
            var d: [NSFontDescriptor.AttributeName: Any] = [.family: fam]
            if !traits.isEmpty { d[.traits] = [NSFontDescriptor.TraitKey.symbolic: NSNumber(value: traits.rawValue)] }
            out += NSFontDescriptor(fontAttributes: d).matchingFontDescriptors(withMandatoryKeys: traits.isEmpty ? [.family] : [.family, .traits])
        }
        return out
    }

    open override var description: String { "<\(type(of: self)) \(_name?.rawValue ?? "unnamed") queries=\(_queryDescriptors.count)>" }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? NSFontCollection else { return false }
        return o._queryDescriptors == _queryDescriptors && o._exclusionDescriptors == _exclusionDescriptors && o._name == _name
    }
    open override var hash: Int { _queryDescriptors.count &+ (_name?.rawValue.hashValue ?? 0) }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/init(descriptors:)
    public init(descriptors queryDescriptors: [NSFontDescriptor]) {
        _queryDescriptors = queryDescriptors
        super.init()
    }
    /// The installed fonts carry no language coverage on these platforms: every font.
    internal init(_locale: Locale) {
        _queryDescriptors = NSFontCollection._allQuery
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/init(locale:)
    public convenience init?(locale: Locale) { self.init(_locale: locale) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/init(name:)
    public convenience init?(name: NSFontCollection.Name) {
        self.init(name: name, visibility: [.process, .user, .computer])
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/init(name:visibility:)
    public init?(name: NSFontCollection.Name, visibility: NSFontCollection.Visibility) {
        if let stored = NSFontCollection._stored[name.rawValue] {
            _queryDescriptors = stored.map { NSFontCollection._descriptor($0) }
            _name = name
            _visibility = visibility.contains(.user) ? .user : visibility
        } else if NSFontCollection._standardNames.contains(name) {
            _queryDescriptors = name == .allFonts || name == .user ? NSFontCollection._allQuery : []
            _name = name
            _visibility = .computer
        } else {
            return nil
        }
        super.init()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/actionuserinfokey
    static public var actionUserInfoKey: NSFontCollection.UserInfoKey { NSFontCollection.UserInfoKey(rawValue: "NSFontCollectionAction") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/allfontcollectionnames
    class public var allFontCollectionNames: [NSFontCollection.Name] {
        let hidden = Set(_hidden)
        var names = _standardNames.filter { !hidden.contains($0.rawValue) }
        names += _stored.keys.filter { !hidden.contains($0) }.sorted().map { NSFontCollection.Name($0) }
        return names
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/didchangenotification
    static public var didChangeNotification: NSNotification.Name { NSNotification.Name(rawValue: "NSFontCollectionDidChange") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/exclusiondescriptors
    open var exclusionDescriptors: [NSFontDescriptor]? { _exclusionDescriptors.isEmpty ? nil : _exclusionDescriptors }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/hide(withname:visibility:)
    public class func hide(withName name: NSFontCollection.Name, visibility: NSFontCollection.Visibility) throws {
        guard _stored[name.rawValue] != nil || _standardNames.contains(name) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "The font collection “\(name.rawValue)” does not exist."])
        }
        if !_hidden.contains(name.rawValue) { _hidden.append(name.rawValue) }
        _post(.hidden, name: name, visibility: visibility)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/matchingdescriptors
    open var matchingDescriptors: [NSFontDescriptor]? { matchingDescriptors(options: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/matchingdescriptors(forfamily:)
    open func matchingDescriptors(forFamily family: String) -> [NSFontDescriptor]? { matchingDescriptors(forFamily: family, options: nil) }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/matchingdescriptors(forfamily:options:)
    open func matchingDescriptors(forFamily family: String, options: [NSFontCollectionMatchingOptionKey : NSNumber]? = nil) -> [NSFontDescriptor]? {
        guard let all = matchingDescriptors(options: options) else { return nil }
        let wanted = family.lowercased()
        let inFamily = all.filter { ($0.object(forKey: .family) as? String)?.lowercased() == wanted }
        return inFamily.isEmpty ? nil : inFamily
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/matchingdescriptors(options:)
    open func matchingDescriptors(options: [NSFontCollectionMatchingOptionKey : NSNumber]? = nil) -> [NSFontDescriptor]? {
        let excluded = Set(_exclusionDescriptors.flatMap { NSFontCollection._matches($0) }.compactMap { $0.postscriptName })
        var seen: Set<String> = []
        var out: [NSFontDescriptor] = []
        for q in _queryDescriptors {
            for d in NSFontCollection._matches(q) {
                let key = d.postscriptName ?? "\(d.fontAttributes)"
                if excluded.contains(key) || seen.contains(key) { continue }
                seen.insert(key)
                out.append(d)
            }
        }
        return out.isEmpty ? nil : out
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/nameuserinfokey
    static public var nameUserInfoKey: NSFontCollection.UserInfoKey { NSFontCollection.UserInfoKey(rawValue: "NSFontCollectionName") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/oldnameuserinfokey
    static public var oldNameUserInfoKey: NSFontCollection.UserInfoKey { NSFontCollection.UserInfoKey(rawValue: "NSFontCollectionOldName") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/querydescriptors
    open var queryDescriptors: [NSFontDescriptor]? { _queryDescriptors.isEmpty ? nil : _queryDescriptors }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/rename(fromname:visibility:toname:)
    public class func rename(fromName oldName: NSFontCollection.Name, visibility: NSFontCollection.Visibility, toName newName: NSFontCollection.Name) throws {
        var stored = _stored
        guard let entry = stored[oldName.rawValue] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "The font collection “\(oldName.rawValue)” does not exist."])
        }
        stored[oldName.rawValue] = nil
        stored[newName.rawValue] = entry
        _stored = stored
        _hidden = _hidden.map { $0 == oldName.rawValue ? newName.rawValue : $0 }
        _post(.renamed, name: newName, oldName: oldName, visibility: visibility)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/show(_:withname:visibility:)
    public class func show(_ collection: NSFontCollection, withName name: NSFontCollection.Name, visibility: NSFontCollection.Visibility) throws {
        var stored = _stored
        stored[name.rawValue] = collection._queryDescriptors.map { _plist($0) }
        _stored = stored
        _hidden = _hidden.filter { $0 != name.rawValue }
        collection._name = name
        collection._visibility = visibility
        _post(.shown, name: name, visibility: visibility)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/visibilityuserinfokey
    static public var visibilityUserInfoKey: NSFontCollection.UserInfoKey { NSFontCollection.UserInfoKey(rawValue: "NSFontCollectionVisibility") }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nsfontcollection/withallavailabledescriptors
    class public var withAllAvailableDescriptors: NSFontCollection { NSFontCollection(_queries: _allQuery, name: .allFonts, visibility: .computer) }
    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        NSFontCollection(_queries: _queryDescriptors, exclusions: _exclusionDescriptors, name: _name, visibility: _visibility)
    }
    // Requirement of NSMutableCopying
    open func mutableCopy(with zone: NSZone? = nil) -> Any {
        NSMutableFontCollection(_queries: _queryDescriptors, exclusions: _exclusionDescriptors, name: _name, visibility: _visibility)
    }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) {
        coder.encode(_queryDescriptors.map { NSFontCollection._plist($0) } as NSArray, forKey: "NSFontCollectionQueries")
        coder.encode(_exclusionDescriptors.map { NSFontCollection._plist($0) } as NSArray, forKey: "NSFontCollectionExclusions")
        if let n = _name { coder.encode(n.rawValue, forKey: "NSFontCollectionName") }
    }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) {
        _queryDescriptors = ((coder.decodeObject(forKey: "NSFontCollectionQueries") as? [[String: Any]]) ?? []).map { NSFontCollection._descriptor($0) }
        _exclusionDescriptors = ((coder.decodeObject(forKey: "NSFontCollectionExclusions") as? [[String: Any]]) ?? []).map { NSFontCollection._descriptor($0) }
        _name = (coder.decodeObject(forKey: "NSFontCollectionName") as? String).map { NSFontCollection.Name($0) }
        super.init()
    }
}
